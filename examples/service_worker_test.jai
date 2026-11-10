#import "Basic";
#import "Compiler";
#import "File";
#import "File_Utilities";
#import "Hash_Table";
#import "Pool";
#import "Thread"(LOAD_THREAD_GROUP = false);

Service :: #import "Jai_Parser/service"(TEST_HOOKS = true, REAL_WORKER = true);

FOREVER :: 0xFFFF_FFFF_FFFF_FFFF;

BATCH_POOL_ONLY :: #run -> bool {
	arguments := get_build_options().compile_time_command_line;
	assert(!arguments.count || arguments.count == 1 && arguments[0] == "batch-pool");
	return !!arguments.count;
}

Allocation_Ledger :: struct {
	gate: Mutex;
	delegate: Allocator;
	sizes: Table(*void, s64);
	live_bytes: s64;
	allocation_attempts: s64;
	reject_allocations: bool;
	directory_retirement: *Directory_Retirement;
	pool_cleanup: *Pool_Cleanup_Probe;
}

allocation_ledger: Allocation_Ledger;

spy_allocate :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, data: *void) -> *void {
	ledger := data.(*Allocation_Ledger);
	if mode != .ALLOCATE && mode != .RESIZE && mode != .FREE {
		return ledger.delegate.proc(mode, size, old_size, old_memory, ledger.delegate.data);
	}


	pool_cleanup: *Pool_Cleanup_Probe;
	if mode == .FREE {
		retirement: *Directory_Retirement;
		Service.with_lock(
			*ledger.gate,
			#code {
				if ledger.directory_retirement && ledger.directory_retirement.memory == old_memory {
					retirement = ledger.directory_retirement;
					ledger.directory_retirement = null;
				}
				if ledger.pool_cleanup && ledger.pool_cleanup.memory == old_memory {
					assert(table_contains(*ledger.sizes, old_memory));
					pool_cleanup = ledger.pool_cleanup;
					ledger.pool_cleanup = null;
				}
			}
		);

		if retirement {
			push_allocator(context.default_allocator);

			thread := Thread.{data = retirement};
			if retirement.direct {
				directory_retirement_job(*thread);
				retirement.gate_progress = true;
			} else {
				assert(thread_init(*thread, directory_retirement_job));
				thread_start(*thread);
				retirement.gate_progress = thread_is_done(*thread, 10_000);
				assert(retirement.gate_progress, "\e[91mDirectory backing was freed while its gate was held.\e[0m");
				thread_deinit(*thread);
			}
		}

		if pool_cleanup && !pool_cleanup.suppress_callback {
			push_allocator(context.default_allocator);

			heap := old_memory.(*Service.Owned_Allocation).heap;
			if pool_cleanup.hold_heap_gate {
				lock(*heap.gate);
			}

			thread := Thread.{data = pool_cleanup};
			if pool_cleanup.direct {
				pool_cleanup_job(*thread);
				pool_cleanup.gate_progress = true;
			} else {
				assert(thread_init(*thread, pool_cleanup_job));
				thread_start(*thread);
				if pool_cleanup.hold_heap_gate {
					assert(wait_for(*pool_cleanup.heap_entered, 10_000) == .SUCCESS);
					pool_cleanup.heap_blocked = !thread_is_done(*thread, 100);
					unlock(*heap.gate);
					assert(pool_cleanup.heap_blocked, "\e[91mHeld heap-gate cleanup control was not detected.\e[0m");
				}

				pool_cleanup.gate_progress = thread_is_done(*thread, 10_000);
				assert(pool_cleanup.gate_progress, "\e[91mPool-root free blocked session-gate progress.\e[0m");
				thread_deinit(*thread);
			}
		}
	}

	result: *void;
	Service.with_lock(
		*ledger.gate,
		#code {
			if mode == .ALLOCATE || mode == .RESIZE {
				ledger.allocation_attempts += 1;
				if ledger.reject_allocations {
					return null;
				}
			}


			push_allocator(ledger.delegate);

			result = ledger.delegate.proc(mode, size, old_size, old_memory, ledger.delegate.data);
			if ledger.pool_cleanup && ledger.pool_cleanup.allocation_pending {
				assert(mode == .ALLOCATE && size == ledger.pool_cleanup.allocation_size + size_of(Service.Owned_Allocation) && result);
				ledger.pool_cleanup.memory = result;
				ledger.pool_cleanup.allocation_pending = false;
			}

			if old_memory && (mode == .FREE || mode == .RESIZE && result) {
				found, previous_size := table_remove(*ledger.sizes, old_memory);
				assert(found, "\e[91mAn allocation was freed twice or by the wrong owner.\e[0m");
				ledger.live_bytes -= previous_size;
				if pool_cleanup {
					pool_cleanup.frees += 1;
				}
			}

			if result && (mode == .ALLOCATE || mode == .RESIZE) {
				assert(!table_contains(*ledger.sizes, result));
				table_add(*ledger.sizes, result, size);
				ledger.live_bytes += size;
			}
		}
	);

	return result;
}

assert_no_owned_allocations :: () {
	Service.with_lock(
		*allocation_ledger.gate,
		#code {
			assert(!allocation_ledger.live_bytes && !allocation_ledger.sizes.count, "\e[91mIndependent allocation ledger retained % bytes.\e[0m", allocation_ledger.live_bytes);
		}
	);
}

Fixture :: struct {
	host: *Service.Harness_Host;
	session: *Service.Session;
}

Waiting :: struct {
	service: *Service.Service;
	handle: Service.Handle(.WAITER);
	ok: bool;
	error: Service.Operation_Error;
	outcome: Service.Wait_Observation;
}

Submitting :: struct {
	batch: Service.Host_Batch;
	ok: bool;
	accepted: Service.Accepted;
	error: Service.Operation_Error;
}

Releasing :: struct {
	fixture: Fixture;
	handle: Service.Handle(.WORLD);
	ok: bool;
}

release_job :: (thread: *Thread) -> s64 {
	releasing := thread.data.(*Releasing);
	releasing.ok = Service.release(releasing.fixture.host.service, releasing.handle);
	return 0;
}

open :: (name: string, max_handles: s64 = 1 << 20) -> Fixture {
	root := tprint("%.build/worker/%", #filepath, name);
	make_directory_if_it_does_not_exist(root, recursive = true);
	ceilings: Service.Limits;
	for * ceilings.values {
		it.* = 1 << 20;
	}

	ceilings.values[Service.Limit_Name.LIVE_HANDLES] = max_handles;

	minima: Service.Limits;
	minima.values[Service.Limit_Name.LIVE_HANDLES] = 2;
	minima.values[Service.Limit_Name.IN_FLIGHT_OPERATIONS] = 1;
	failure, host := Service.open_harness_host(root, ceilings, minima);
	assert(failure == .NONE);
	return .{host = host, session = Service.session_of(host.service, host.session)};
}

submit :: (fixture: Fixture, text: string) -> Service.Handle(.TICKET) {
	batch := Service.begin_batch(fixture.host);
	assert(Service.set_overlay(*batch, "a.jai", text));
	ok, accepted, error := Service.submit_batch(*batch);
	assert(ok, "\e[91mSubmission failed: %.\e[0m", error);
	return accepted.ticket;
}

await :: (fixture: Fixture, handle: Service.Handle($K)) -> Service.Observation {
	ok, waited, error := Service.wait(fixture.host.service, handle, .{
		clock_identity = fixture.host.service.clock_identity,
		nanoseconds = FOREVER,
	});
	assert(ok && !waited.timed_out, "\e[91mWait failed: %.\e[0m", error);
	return waited.observation;
}

world_of :: (fixture: Fixture, ticket: Service.Handle(.TICKET)) -> Service.Handle(.WORLD) {
	observation := await(fixture, ticket);
	assert(observation.update.kind == .PUBLISHED);
	Service.free_observation(*observation);
	ok, acquired := Service.acquire_world(fixture.host.service, .{
		kind = .PUBLISHED_UPDATE,
		ticket = ticket,
	});
	assert(ok && acquired.kind == .ACQUIRED);
	return acquired.world;
}

query :: (fixture: Fixture, world: Service.Handle(.WORLD), kind: Service.Query_Kind) -> Service.Query_Start {
	ok, started := Service.query(fixture.host.service, .{
		version = Service.INTERFACE_VERSION,
		world = world,
		document = Service.harness_document(fixture.host, "a.jai"),
		kind = kind,
	});
	assert(ok);
	return started;
}

release :: (fixture: Fixture, handle: Service.Handle($K)) {
	ok, error := Service.release(fixture.host.service, handle);
	assert(ok, "\e[91mRelease failed: %.\e[0m", error);
}

close :: (fixture: Fixture) {
	assert(Service.close_harness_host(fixture.host));
	assert(!Service.session_of(fixture.host.service, fixture.host.session));
	assert(!fixture.host.service.owned_allocations && !fixture.host.service.owned_bytes, "\e[91mFinal release retained session allocations.\e[0m");
	assert_no_owned_allocations();
}

wait_job :: (thread: *Thread) -> s64 {
	waiting := thread.data.(*Waiting);
	waiting.ok, waiting.outcome, waiting.error = Service.wait(
		waiting.service,
		waiting.handle,
		.{
			clock_identity = waiting.service.clock_identity,
			nanoseconds = FOREVER,
		}
	);

	return 0;
}

start_wait :: (thread: *Thread, waiting: *Waiting) {
	thread.data = waiting;
	assert(thread_init(thread, wait_job));
	thread_start(thread);
}

join :: (thread: *Thread) {
	assert(thread_is_done(thread, 10_000), "\e[91mA concurrent call did not finish.\e[0m");
	thread_deinit(thread);
}

submit_job :: (thread: *Thread) -> s64 {
	submitting := thread.data.(*Submitting);
	submitting.ok, submitting.accepted, submitting.error = Service.submit_batch(*submitting.batch);
	return 0;
}

start_submit :: (thread: *Thread, submitting: *Submitting) {
	thread.data = submitting;
	assert(thread_init(thread, submit_job));
	thread_start(thread);
}

test_provider_stall_and_shutdown :: () {
	fixture := open("X6-provider");
	ticket := submit(fixture, "old :: 1;");
	world := world_of(fixture, ticket);
	submitting := Submitting.{batch = Service.begin_batch(fixture.host)};
	assert(Service.set_overlay(*submitting.batch, "a.jai", "new :: 2;"));
	Service.arm_pause(fixture.session, .SOURCE_STAGING);
	thread: Thread;
	start_submit(*thread, *submitting);
	assert(Service.await_pause(fixture.session, .SOURCE_STAGING));
	started := query(fixture, world, .SYNTAX_DIAGNOSTICS);
	assert(started.kind == .PENDING);
	observation := await(fixture, started.waiter);
	assert(observation.query.kind == .AVAILABLE, "\e[91mHeld source acquisition blocked unrelated compute.\e[0m");
	Service.free_observation(*observation);
	_, shutdown := Service.request_shutdown(fixture.host.service, fixture.host.session);
	_, waited := Service.wait(
		fixture.host.service,
		shutdown,
		.{
			clock_identity = fixture.host.service.clock_identity,
			nanoseconds = 0,
		}
	);
	assert(waited.timed_out && waited.observation.phase == .DRAINING);
	Service.free_observation(*waited.observation);
	Service.resume_pause(fixture.session, .SOURCE_STAGING);
	join(*thread);
	assert(!submitting.ok && submitting.error.code == .SERVICE_CLOSED);
	observation = await(fixture, shutdown);
	assert(observation.kind == .SHUTDOWN);
	Service.free_observation(*observation);
	release(fixture, started.waiter);
	release(fixture, world);
	release(fixture, ticket);
	release(fixture, shutdown);
	close(fixture);
	print("X6/X7/X8 held provider/independent compute/revalidation \e[92mPASS\e[0m\n");
}

test_cleanup_pin :: () {
	fixture := open("X8-cleanup");
	old_ticket := submit(fixture, "old :: 1;");
	old_world := world_of(fixture, old_ticket);
	new_ticket := submit(fixture, "new :: 2;");
	new_world := world_of(fixture, new_ticket);
	release(fixture, old_ticket);
	Service.arm_pause(fixture.session, .CLEANUP);
	releasing := Releasing.{fixture = fixture, handle = old_world};
	thread: Thread;
	thread.data = *releasing;
	assert(thread_init(*thread, release_job));
	thread_start(*thread);
	assert(Service.await_pause(fixture.session, .CLEANUP));
	_, shutdown := Service.request_shutdown(fixture.host.service, fixture.host.session);
	_, waited := Service.wait(
		fixture.host.service,
		shutdown,
		.{
			clock_identity = fixture.host.service.clock_identity,
			nanoseconds = 0,
		}
	);
	assert(waited.timed_out && waited.observation.phase == .DRAINING);
	Service.free_observation(*waited.observation);
	Service.resume_pause(fixture.session, .CLEANUP);
	join(*thread);
	assert(releasing.ok);
	observation := await(fixture, shutdown);
	assert(observation.kind == .SHUTDOWN);
	Service.free_observation(*observation);
	release(fixture, shutdown);
	release(fixture, new_world);
	release(fixture, new_ticket);
	close(fixture);
	print("X8 cleanup pin prevents premature stopped \e[92mPASS\e[0m\n");
}

analysis :: (fixture: Fixture, relative: string) -> Service.Handle(.TICKET) {
	_, description := Service.describe_session(fixture.host.service, fixture.host.session);
	ok, accepted := Service.request_analysis(
		fixture.host.service,
		fixture.host.session,
		.{
			version = Service.INTERFACE_VERSION,
			expected_frontier = description.accepted_frontier,
			documents = .[Service.harness_document(fixture.host, relative)],
		}
	);
	assert(ok);
	return accepted.ticket;
}

demote_for_test :: (fixture: Fixture, ticket: Service.Handle(.TICKET)) {
	Service.with_lock(
		*fixture.session.gate,
		#code {
			world := fixture.session.registrations[ticket.slot].operation.world;
			for fixture.session.ready {
				if it.world == world {
					task := it;
					remove it;

					task.optional = true;
					push_allocator(fixture.session.compute.starting_context.allocator);
					array_add(*fixture.session.optional_ready, task);
					return;
				}
			}


			assert(false, "\e[91mNo queued task was available for the optional scheduling control.\e[0m");
		}
	);
}

test_optional_fifo :: () {
	for 0..2 {
		mode := it;
		fixture := open(tprint("X6-optional-%", mode));
		batch := Service.begin_batch(fixture.host);
		for string.["a.jai", "b.jai", "c.jai", "d.jai"] {
			assert(Service.set_overlay(*batch, it, "value :: 1;"));
		}

		_, accepted := Service.submit_batch(*batch);
		world := world_of(fixture, accepted.ticket);
		Service.arm_pause(fixture.session, .SELECTED);
		first := analysis(fixture, "a.jai");
		assert(Service.await_pause(fixture.session, .SELECTED));
		second := analysis(fixture, "b.jai");
		optional := analysis(fixture, "c.jai");
		demote_for_test(fixture, optional);
		third := analysis(fixture, "d.jai");
		promoted: Service.Handle(.TICKET);
		if mode == 1 {
			promoted = analysis(fixture, "c.jai");
		}

		if mode == 2 {
			Service.with_lock(
				*fixture.session.gate,
				#code {
					fixture.session.faults.optional_first = true;
				}
			);
		}

		correct_order := true;
		for string.["a.jai", "b.jai", "d.jai", "c.jai"] {
			mailbox := Service.last_mailbox(fixture.session);
			correct_order &&= Service.bytes_equal(mailbox.task.world.members[0].document, Service.harness_document(fixture.host, it));
			if mode == 1 && it_index == 3 {
				assert(!mailbox.task.optional, "\e[91mA shared optional prerequisite was not promoted.\e[0m");
			}

			if it_index < 3 {
				Service.arm_pause(fixture.session, .SELECTED);
			}

			Service.resume_pause(fixture.session, .SELECTED);
			if it_index < 3 {
				assert(Service.await_pause(fixture.session, .SELECTED));
			}
		}

		assert(correct_order == (mode != 2), "\e[91mOptional priority control was not detected.\e[0m");
		for Service.Handle(.TICKET).[first, second, third, optional] {
			observation := await(fixture, it);
			assert(observation.update.kind == .PUBLISHED);
			Service.free_observation(*observation);
			release(fixture, it);
		}

		if mode == 1 {
			release(fixture, promoted);
		}

		release(fixture, accepted.ticket);
		release(fixture, world);
		close(fixture);
	}

	print("X6 optional fallback/promotion/priority negative control \e[92mPASS\e[0m\n");
}

test_required_fifo :: () {
	fixture := open("X6-fifo");
	batch := Service.begin_batch(fixture.host);
	for string.["a.jai", "b.jai", "c.jai"] {
		assert(Service.set_overlay(*batch, it, "value :: 1;"));
	}

	_, accepted := Service.submit_batch(*batch);
	world := world_of(fixture, accepted.ticket);
	Service.arm_pause(fixture.session, .SELECTED);
	first := analysis(fixture, "a.jai");
	assert(Service.await_pause(fixture.session, .SELECTED));
	second := analysis(fixture, "b.jai");
	third := analysis(fixture, "c.jai");
	joined: [8] Service.Handle(.TICKET);
	for * joined {
		it.* = analysis(fixture, "c.jai");
	}

	for string.["a.jai", "b.jai", "c.jai"] {
		mailbox := Service.last_mailbox(fixture.session);
		assert(Service.bytes_equal(mailbox.task.world.members[0].document, Service.harness_document(fixture.host, it)), "\e[91mLater required work overtook the FIFO.\e[0m");
		if it_index < 2 {
			Service.arm_pause(fixture.session, .SELECTED);
		}

		Service.resume_pause(fixture.session, .SELECTED);
		if it_index < 2 {
			assert(Service.await_pause(fixture.session, .SELECTED));
		}
	}

	for joined {
		observation := await(fixture, it);
		assert(observation.update.kind == .PUBLISHED);
		Service.free_observation(*observation);
		release(fixture, it);
	}

	for Service.Handle(.TICKET).[first, second, third, accepted.ticket] {
		release(fixture, it);
	}

	release(fixture, world);
	close(fixture);
	print("X6 required FIFO/shared later demand \e[92mPASS\e[0m\n");
}

dispatch_world: Service.Handle(.WORLD);
dispatch_shutdown: Service.Handle(.SHUTDOWN);
dispatch_count: s64;

reenter_dispatch :: (host: *Service.Harness_Host, record: Service.Completion_Record) -> bool {
	dispatch_count += 1;
	assert(!Service.dispatch_completions(host, reenter_dispatch));
	ok, started := Service.query(
		host.service,
		.{
			version = Service.INTERFACE_VERSION,
			world = dispatch_world,
			document = Service.harness_document(host, "a.jai"),
			kind = .SYNTAX_SNAPSHOT,
		}
	);
	assert(ok && started.kind == .AVAILABLE);
	_, retained := Service.retain(host.service, started.result);
	assert(Service.release(host.service, started.result));
	_, description := Service.read_result(host.service, retained);
	assert(description.snapshot.source == "answer :: 42;");
	assert(Service.release(host.service, retained));
	_, cancelled := Service.cancel_waiter(host.service, record.registration);
	assert(cancelled.already_terminal);
	Service.free_observation(*cancelled.observation);
	ok, dispatch_shutdown = Service.request_shutdown(host.service, host.session);
	assert(ok);
	return false;
}

test_reentrant_dispatch :: () {
	fixture := open("X4");
	Service.arm_pause(fixture.session, .PUBLICATION);
	ticket := submit(fixture, "answer :: 42;");
	assert(Service.await_pause(fixture.session, .PUBLICATION));
	_, attached := Service.observe_ticket(fixture.host.service, ticket);
	Service.resume_pause(fixture.session, .PUBLICATION);
	dispatch_world = world_of(fixture, ticket);
	assert(Service.dispatch_completions(fixture.host, reenter_dispatch) == 1);
	assert(dispatch_count == 1 && fixture.host.dispatch_failures == 1);
	assert(!Service.dispatch_completions(fixture.host, reenter_dispatch));
	observation := await(fixture, dispatch_shutdown);
	Service.free_observation(*observation);
	release(fixture, dispatch_shutdown);
	release(fixture, dispatch_world);
	release(fixture, attached.waiter);
	release(fixture, ticket);
	close(fixture);
	print("X4 reentrant query/cancel/release/shutdown/dispatch \e[92mPASS\e[0m\n");
}

test_pressure_and_reserved_shutdown :: () {
	fixture := open("X5", 4);
	Service.arm_pause(fixture.session, .SELECTED);
	ticket := submit(fixture, "answer :: 42;");
	assert(Service.await_pause(fixture.session, .SELECTED));
	_, attached := Service.observe_ticket(fixture.host.service, ticket);
	ok, _, error := Service.observe_ticket(fixture.host.service, ticket);
	assert(!ok && error.admission.limit == .LIVE_HANDLES);
	fixture.session.faults.shutdown_from_ordinary_capacity = true;
	ok, _, error = Service.request_shutdown(fixture.host.service, fixture.host.session);
	assert(!ok && error.admission.limit == .LIVE_HANDLES, "\e[91mShutdown reservation negative control was not detected.\e[0m");
	fixture.session.faults.shutdown_from_ordinary_capacity = false;
	_, shutdown := Service.request_shutdown(fixture.host.service, fixture.host.session);
	Service.resume_pause(fixture.session, .SELECTED);
	observation := await(fixture, shutdown);
	Service.free_observation(*observation);
	_, pending_records := Service.drain_completions(fixture.host.service, fixture.host.session, 0);
	assert(!pending_records.count);
	_, records := Service.drain_completions(fixture.host.service, fixture.host.session, 8);
	assert(records.count == 1 && records[0].observation.update.cancellation == .SHUTDOWN);
	Service.free_observation(*records[0].observation);
	array_free(records);
	_, records = Service.drain_completions(fixture.host.service, fixture.host.session, 8);
	assert(!records.count);
	release(fixture, attached.waiter);
	release(fixture, ticket);
	release(fixture, shutdown);
	close(fixture);
	print("X5 delayed drain/full capacity/reservation negative control \e[92mPASS\e[0m\n");
}

test_registration_and_wait :: () {
	for 0..2 {
		fixture := open(tprint("X1-%", it));
		Service.arm_pause(fixture.session, .PUBLICATION);
		ticket := submit(fixture, "answer :: 42;");
		assert(Service.await_pause(fixture.session, .PUBLICATION));
		if !it {
			Service.resume_pause(fixture.session, .PUBLICATION);
			observation := await(fixture, ticket);
			Service.free_observation(*observation);
		}

		ok, attached := Service.observe_ticket(fixture.host.service, ticket);
		assert(ok);
		if !it {//TODO: flip
			assert(attached.terminal && attached.observation.update.kind == .PUBLISHED);
			Service.free_observation(*attached.observation);
		} else {
			assert(!attached.terminal);
			waiting := Waiting.{service = fixture.host.service, handle = attached.waiter};
			thread: Thread;
			Service.arm_pause(fixture.session, .WAIT_ARMING);
			start_wait(*thread, *waiting);
			assert(Service.await_pause(fixture.session, .WAIT_ARMING));
			if it == 1 {
				Service.resume_pause(fixture.session, .PUBLICATION);
				observation := await(fixture, ticket);
				Service.free_observation(*observation);
				Service.resume_pause(fixture.session, .WAIT_ARMING);
			} else {
				Service.resume_pause(fixture.session, .WAIT_ARMING);
				Service.resume_pause(fixture.session, .PUBLICATION);
			}

			join(*thread);
			assert(waiting.ok && !waiting.outcome.timed_out && waiting.outcome.observation.update.kind == .PUBLISHED);
			Service.free_observation(*waiting.outcome.observation);
			release(fixture, attached.waiter);
		}

		world := world_of(fixture, ticket);
		result := query(fixture, world, .SYNTAX_SNAPSHOT);
		_, description := Service.read_result(fixture.host.service, result.result);
		assert(description.snapshot.source == "answer :: 42;");
		tampered := result.result;
		tampered.session = xx "foreign session".([] u8);
		valid := Service.read_result(fixture.host.service, tampered);
		assert(!valid, "\e[91mInline routing byPASSed the live handle's session binding.\e[0m");
		release(fixture, result.result);
		release(fixture, world);
		release(fixture, ticket);
		close(fixture);
	}

	print("X1 registration/wait orderings \e[92mPASS\e[0m\n");
}

test_cancel_and_completion :: () {
	for 0..1 {
		fixture := open(tprint("X2-%", it));
		ticket := submit(fixture, "answer :: 42;");
		world := world_of(fixture, ticket);
		Service.arm_pause(fixture.session, .PUBLICATION);
		first := query(fixture, world, .SYNTAX_DIAGNOSTICS);
		assert(first.kind == .PENDING);
		assert(Service.await_pause(fixture.session, .PUBLICATION));
		second := query(fixture, world, .SYNTAX_DIAGNOSTICS);
		assert(second.kind == .PENDING);
		if it == 1 {
			Service.resume_pause(fixture.session, .PUBLICATION);
			observation := await(fixture, second.waiter);
			Service.free_observation(*observation);
		}

		ok, cancelled := Service.cancel_waiter(fixture.host.service, first.waiter);
		assert(ok && cancelled.already_terminal == (it == 1));
		assert(cancelled.observation.query.kind == ifx it == 1 then .AVAILABLE else .CANCELLED);
		if !it {
			assert(cancelled.observation.query.cancellation == .CALLER);
			Service.resume_pause(fixture.session, .PUBLICATION);
		}

		Service.free_observation(*cancelled.observation);
		observation := await(fixture, second.waiter);
		assert(observation.query.kind == .AVAILABLE);
		Service.free_observation(*observation);
		_, records := Service.drain_completions(fixture.host.service, fixture.host.session, 8);
		assert(records.count == 2);
		for * records {
			Service.free_observation(*it.observation);
		}

		array_free(records);
		release(fixture, first.waiter);
		release(fixture, second.waiter);
		release(fixture, world);
		release(fixture, ticket);
		close(fixture);
	}

	print("X2 caller/completion orderings \e[92mPASS\e[0m\n");
}

test_retirement_while_waiting :: () {
	fixture := open("X3");
	Service.arm_pause(fixture.session, .PUBLICATION);
	ticket := submit(fixture, "answer :: 42;");
	assert(Service.await_pause(fixture.session, .PUBLICATION));
	_, attached := Service.observe_ticket(fixture.host.service, ticket);
	waiting := Waiting.{service = fixture.host.service, handle = attached.waiter};
	thread: Thread;
	Service.arm_pause(fixture.session, .WAIT_ARMING);
	start_wait(*thread, *waiting);
	assert(Service.await_pause(fixture.session, .WAIT_ARMING));
	release(fixture, attached.waiter);
	_, replacement := Service.observe_ticket(fixture.host.service, ticket);
	assert(replacement.waiter.slot == attached.waiter.slot && replacement.waiter.generation != attached.waiter.generation);
	Service.resume_pause(fixture.session, .WAIT_ARMING);
	join(*thread);
	assert(!waiting.ok && waiting.error.code == .INVALID_HANDLE);
	Service.resume_pause(fixture.session, .PUBLICATION);
	observation := await(fixture, replacement.waiter);
	assert(observation.update.kind == .PUBLISHED);
	Service.free_observation(*observation);
	release(fixture, replacement.waiter);
	release(fixture, ticket);
	close(fixture);
	ok, _, error := Service.poll(fixture.host.service, attached.waiter);
	assert(!ok && error.code == .INVALID_HANDLE);
	print("X3 retirement/reuse/stale lookup \e[92mPASS\e[0m\n");
}

test_shutdown_deadline_and_owners :: () {
	for 0..1 {
		fixture := open(tprint("X8-%", it));
		ticket := submit(fixture, "old :: 1;");
		world := world_of(fixture, ticket);
		result := query(fixture, world, .SYNTAX_SNAPSHOT);
		Service.arm_pause(fixture.session, ifx it then .PUBLICATION else .PARSED);
		new_ticket := submit(fixture, "new :: 2;");
		boundary := ifx it then Service.Test_Boundary.PUBLICATION else .PARSED;
		assert(Service.await_pause(fixture.session, boundary));
		ok, shutdown := Service.request_shutdown(fixture.host.service, fixture.host.session);
		assert(ok);
		_, repeated := Service.request_shutdown(fixture.host.service, fixture.host.session);
		_, first_observation := Service.poll(fixture.host.service, shutdown);
		_, repeated_observation := Service.poll(fixture.host.service, repeated);
		assert(Service.bytes_equal(first_observation.operation_identity.([] u8), repeated_observation.operation_identity.([] u8)));
		Service.free_observation(*first_observation);
		Service.free_observation(*repeated_observation);
		_, waited := Service.wait(
			fixture.host.service,
			shutdown,
			.{
				clock_identity = fixture.host.service.clock_identity,
				nanoseconds = 0,
			}
		);
		assert(waited.timed_out && waited.observation.phase == .DRAINING);
		Service.free_observation(*waited.observation);
		batch := Service.begin_batch(fixture.host);
		assert(Service.set_overlay(*batch, "\e[91a.jai\e[0m", "forbidden :: 3;"));
		accepted, _, error := Service.submit_batch(*batch);
		assert(!accepted && error.code == .SERVICE_CLOSED);
		Service.resume_pause(fixture.session, boundary);
		assert(thread_is_done(*fixture.session.reaper, 10_000), "\e[91mShutdown depended on host polling.\e[0m");
		observation := await(fixture, shutdown);
		assert(observation.kind == .SHUTDOWN);
		Service.free_observation(*observation);
		release(fixture, shutdown);
		release(fixture, repeated);
		release(fixture, new_ticket);
		release(fixture, ticket);
		release(fixture, fixture.host.session);
		_, description := Service.read_result(fixture.host.service, result.result);
		assert(description.snapshot.source == "old :: 1;");
		release(fixture, world);
		release(fixture, result.result);
		assert(!Service.session_of(fixture.host.service, fixture.host.session));
		assert(!fixture.host.service.owned_allocations && !fixture.host.service.owned_bytes);
		assert_no_owned_allocations();
	}

	print("X7/X8 shutdown/deadline/surviving owner \e[92mPASS\e[0m\n");
}

Drain_Fixture :: struct {
	fixture: Fixture;
	ticket: Service.Handle(.TICKET);
	world: Service.Handle(.WORLD);
	first: Service.Handle(.WAITER);
	second: Service.Handle(.WAITER);
}

prepared_drain :: (name: string, held := false) -> Drain_Fixture {
	fixture := open(name);
	ticket := submit(fixture, "answer :: 42;");
	world := world_of(fixture, ticket);
	Service.arm_pause(fixture.session, .PUBLICATION);
	first := query(fixture, world, .SYNTAX_DIAGNOSTICS);
	assert(Service.await_pause(fixture.session, .PUBLICATION));
	second := query(fixture, world, .SYNTAX_DIAGNOSTICS);
	assert(first.kind == .PENDING && second.kind == .PENDING);
	if !held {
		Service.resume_pause(fixture.session, .PUBLICATION);
		observation := await(fixture, second.waiter);
		assert(observation.query.kind == .AVAILABLE);
		Service.free_observation(*observation);
	}

	return .{
		fixture = fixture,
		ticket = ticket,
		world = world,
		first = first.waiter,
		second = second.waiter,
	};
}

finish_drain :: (
	drain: Drain_Fixture,
	first_released := false,
	session_released := false,
	ticket_released := false,
	held := false
) {
	if held {
		Service.resume_pause(drain.fixture.session, .PUBLICATION);
	}

	if !first_released {
		release(drain.fixture, drain.first);
	}

	release(drain.fixture, drain.second);
	release(drain.fixture, drain.world);
	if !ticket_released {
		release(drain.fixture, drain.ticket);
	}

	if session_released {
		assert(!Service.session_of(drain.fixture.host.service, drain.fixture.host.session));
		assert_no_owned_allocations();
	} else {
		close(drain.fixture);
	}
}

free_records :: (records: [] Service.Completion_Record, allocator: Allocator = context.allocator) {
	for * records {
		Service.free_observation(*it.observation,, allocator);
	}

	free(records.data,, allocator);
}

Output_Action :: enum {
	NONE;
	RELEASE_WAITER;
	RELEASE_TICKET;
	OTHER_DRAIN;
	RELEASE_SESSION;
	COMPLETE_WORK;
	CANCEL_WAITER;
	REQUEST_SHUTDOWN;
	REPLACE_SOURCE;
	STOP_AND_RELEASE_SESSION;
	RETIRE_AND_REUSE_SESSION;
	RELEASE_QUERY_WORLD;
	RETIRE_QUERY_OWNER;
	RELEASE_ACCESS_RESULT;
	RETIRE_ACCESS_OWNER;
	RETIRE_COORDINATOR_HANDLE;
	RETIRE_COORDINATOR_OWNER;
	REPLACE_HELD_SOURCE;
	CHECK_PRIVATE_OPEN;
	REJECT_ACTIVE_RELEASE;
	CHECK_STAGING_SHUTDOWN;
	TAKE_ANALYSIS_CAPACITY;
	FILL_REGISTRATION_CAPACITY;
	FILL_OPERATION_CAPACITY;
	GROW_PROVIDER_CLONE_COUNTS;
	GROW_PROVIDER_REVISION_COUNTS;
	FILL_SHUTDOWN_CAPACITY;
	COMPLETE_SHUTDOWN;
	TAKE_RETAIN_CAPACITY;
	RETIRE_RETAIN_OWNER;
	COMPLETE_WAITER_TICKET;
	REPLACE_WAITER_TICKET;
	FILL_WAITER_CAPACITY;
	TAKE_PENDING_CAPACITY;
	TAKE_COMPLETION_CAPACITY;
	RETIRE_SELECTED_WORLD;
	RETIRE_SELECTED_RESULT;
	ISSUE_COMPETING_RESULT;
	EXHAUST_RESULT_COUNTER;
	EXHAUST_OPERATION_COUNTER;
	RETIRE_IMMEDIATE_WORLD;
}

Output_Interleaving :: struct {
	drain: Drain_Fixture;
	action: Output_Action;
	ok: bool;
	replacement: Service.Handle(.RESULT);
	replacement_world: Service.Handle(.WORLD);
	surviving_world: Service.Handle(.WORLD);
	access_result: Service.Handle(.RESULT);
	surviving_result: Service.Handle(.RESULT);
	coordinator_case: Coordinator_Argument_Case;
	coordinator_shutdown: Service.Handle(.SHUTDOWN);
	active_source_retirement: bool;
	retirement_ticket: Service.Handle(.TICKET);
	retirement_waiter: Service.Handle(.WAITER);
	retirement_world: Service.Handle(.WORLD);
	analysis_ticket: Service.Handle(.TICKET);
	records: [] Service.Completion_Record;
	retained_worlds: [] Service.Handle(.WORLD);
	retained_results: [] Service.Handle(.RESULT);
	competing_worlds: [..] Service.Handle(.WORLD);
	competing_shutdowns: [..] Service.Handle(.SHUTDOWN);
	competing_waiters: [..] Service.Handle(.WAITER);
	competing_tickets: [..] Service.Handle(.TICKET);
	replacement_ticket: Service.Handle(.TICKET);
}

output_interleaving_job :: (thread: *Thread) -> s64 {
	job := thread.data.(*Output_Interleaving);
	fixture := job.drain.fixture;
	if job.action == {
		case .ISSUE_COMPETING_RESULT;
			started := query(fixture, job.drain.world, .SYNTAX_SNAPSHOT);
			assert(started.kind == .AVAILABLE);
			job.replacement = started.result;
			job.ok = true;

		case .EXHAUST_OPERATION_COUNTER;
			Service.with_lock(
				*fixture.session.gate,
				#code {
					fixture.session.identities.operation_counter.next = Service.U64_MAX;
				}
			);

			job.ok = true;

		case .EXHAUST_RESULT_COUNTER;
			Service.with_lock(
				*fixture.session.gate,
				#code {
					fixture.session.identities.result_counter.next = Service.U64_MAX;
				}
			);

			job.ok = true;

		case .RETIRE_IMMEDIATE_WORLD;
			ticket := submit(fixture, "answer :: 99;");
			observation := await(fixture, ticket);
			assert(observation.update.kind == .PUBLISHED);
			Service.free_observation(*observation);
			release(fixture, ticket);
			release(fixture, job.drain.first);
			release(fixture, job.drain.second);
			release(fixture, job.drain.world);
			release(fixture, job.drain.ticket);
			for job.retained_worlds {
				release(fixture, it);
			}

			job.ok = true;

		case .RETIRE_SELECTED_RESULT;
			release(fixture, job.drain.first);
			release(fixture, job.drain.second);
			job.ok = true;

		case .RELEASE_WAITER;
			job.ok = Service.release(fixture.host.service, job.drain.first);
			if job.ok {
				started := query(fixture, job.drain.world, .SYNTAX_SNAPSHOT);
				assert(started.kind == .AVAILABLE);
				job.replacement = started.result;
			}

		case .OTHER_DRAIN;
			job.ok, job.records = Service.drain_completions(fixture.host.service, fixture.host.session, 8);

		case .RELEASE_TICKET;
			job.ok = Service.release(fixture.host.service, job.drain.ticket);
			if job.ok {
				started := query(fixture, job.drain.world, .SYNTAX_SNAPSHOT);
				assert(started.kind == .AVAILABLE);
				job.replacement = started.result;
			}

		case .COMPLETE_WAITER_TICKET;
			Service.resume_pause(fixture.session, .PUBLICATION);
			observation := await(fixture, job.drain.ticket);
			job.ok = observation.kind == .UPDATE;
			Service.free_observation(*observation);

		case .REPLACE_WAITER_TICKET;
			job.ok = Service.release(fixture.host.service, job.drain.ticket);
			assert(job.ok);
			job.replacement_ticket = submit(fixture, "answer :: 44;");
			assert(job.replacement_ticket.slot == job.drain.ticket.slot && job.replacement_ticket.generation != job.drain.ticket.generation);

		case .FILL_WAITER_CAPACITY;
			target: s64;
			Service.with_lock(
				*fixture.session.gate,
				#code {
					operation := fixture.session.registrations[job.drain.ticket.slot].operation;
					target = max(8, (operation.waiters.count + 1) * 2);
				}
			);

			while true {
				filled: bool;
				Service.with_lock(
					*fixture.session.gate,
					#code {
						filled = fixture.session.registrations[job.drain.ticket.slot].operation.waiters.count >= target;
					}
				);

				if filled {
					break;
				}


				ok, observed := Service.observe_ticket(fixture.host.service, job.drain.ticket);
				assert(ok && !observed.terminal && observed.waiter.generation);
				array_add(*job.competing_waiters, observed.waiter);
			}

			job.ok = true;

		case .RELEASE_SESSION;
			job.ok = Service.release(fixture.host.service, fixture.host.session);

		case .COMPLETE_WORK;
			Service.resume_pause(fixture.session, .PUBLICATION);
			observation := await(fixture, job.drain.second);
			job.ok = (
				observation.kind == .QUERY && observation.query.kind == .AVAILABLE
				|| observation.kind == .UPDATE && observation.update.kind == .PUBLISHED
			);
			Service.free_observation(*observation);

		case .CANCEL_WAITER;
			ok, cancelled := Service.cancel_waiter(fixture.host.service, job.drain.first);
			job.ok = ok && !cancelled.already_terminal;
			Service.free_observation(*cancelled.observation);

		case .REQUEST_SHUTDOWN;
			ok, shutdown := Service.request_shutdown(fixture.host.service, fixture.host.session);
			job.ok = ok;
			if ok {
				release(fixture, shutdown);
			}

		case .RETIRE_SELECTED_WORLD;
			ticket := submit(fixture, "answer :: 99;");
			observation := await(fixture, ticket);
			assert(observation.update.kind == .PUBLISHED);
			Service.free_observation(*observation);
			release(fixture, ticket);
			release(fixture, job.retirement_world);
			release(fixture, job.retirement_ticket);
			release(fixture, job.retirement_waiter);
			job.ok = true;

		case .REPLACE_SOURCE;
			ticket := submit(fixture, "answer :: 99;");
			observation := await(fixture, ticket);
			job.ok = observation.update.kind == .PUBLISHED;
			Service.free_observation(*observation);
			release(fixture, ticket);

		case .STOP_AND_RELEASE_SESSION;		#through;
		case .RETIRE_AND_REUSE_SESSION;
			ok, shutdown := Service.request_shutdown(fixture.host.service, fixture.host.session);
			assert(ok);
			if job.active_source_retirement {
				job.coordinator_shutdown = shutdown;
			} else {
				Service.resume_pause(fixture.session, .PUBLICATION);
				observation := await(fixture, shutdown);
				Service.free_observation(*observation);
				release(fixture, shutdown);
			}

			job.ok = Service.release(fixture.host.service, fixture.host.session);
			if job.ok && job.action == .RETIRE_AND_REUSE_SESSION {
				retained, replacement := Service.retain(fixture.host.service, job.drain.world);
				assert(retained);
				job.replacement_world = replacement;
				assert(replacement.slot == fixture.host.session.slot && replacement.generation != fixture.host.session.generation);
			}

		case .REPLACE_HELD_SOURCE;
			ticket := submit(fixture, "answer :: 99;");
			Service.resume_pause(fixture.session, .PUBLICATION);
			observation := await(fixture, ticket);
			job.ok = observation.update.kind == .PUBLISHED;
			Service.free_observation(*observation);
			release(fixture, ticket);

		case .RELEASE_QUERY_WORLD;
			job.ok = Service.release(fixture.host.service, job.drain.world);
			retained, replacement := Service.retain(fixture.host.service, job.surviving_world);
			assert(retained && replacement.slot == job.drain.world.slot && replacement.generation != job.drain.world.generation);
			job.replacement_world = replacement;

		case .RELEASE_ACCESS_RESULT;
			job.ok = Service.release(fixture.host.service, job.access_result);
			retained, replacement := Service.retain(fixture.host.service, job.surviving_result);
			assert(retained && replacement.slot == job.access_result.slot && replacement.generation != job.access_result.generation);
			job.replacement = replacement;

		case .RETIRE_QUERY_OWNER;	#through;
		case .RETIRE_ACCESS_OWNER;
			ok, shutdown := Service.request_shutdown(fixture.host.service, fixture.host.session);
			assert(ok);
			observation := await(fixture, shutdown);
			Service.free_observation(*observation);
			release(fixture, shutdown);
			job.ok = Service.release(fixture.host.service, fixture.host.session);
			if job.access_result.owner_token {
				release(fixture, job.access_result);
			}

			if job.drain.first.owner_token {
				release(fixture, job.drain.first);
				release(fixture, job.drain.second);
			}

			release(fixture, job.drain.world);
			release(fixture, job.drain.ticket);
			if job.retirement_ticket.owner_token {
				release(fixture, job.retirement_ticket);
			}

		case .RETIRE_COORDINATOR_HANDLE;
			retire_coordinator_argument(job, false);

		case .RETIRE_COORDINATOR_OWNER;
			retire_coordinator_argument(job, true);

		case .CHECK_PRIVATE_OPEN;
			unpublished: bool;
			Service.with_lock(
				*fixture.host.service.directory,
				#code {
					unpublished = fixture.host.service.sessions.count == 1 && fixture.host.service.sessions[0] == fixture.session;
				}
			);

			drained, records := Service.drain_completions(fixture.host.service, fixture.host.session, 8);
			job.records = records;
			job.ok = unpublished && drained && records.count == 2;

		case .REJECT_ACTIVE_RELEASE;
			released, error := Service.release(fixture.host.service, fixture.host.session);
			job.ok = !released && error.code == .ACTIVE_SESSION;

		case .CHECK_STAGING_SHUTDOWN;
			released, error := Service.release(fixture.host.service, fixture.host.session);
			assert(!released && error.code == .ACTIVE_SESSION);
			ok, shutdown := Service.request_shutdown(fixture.host.service, fixture.host.session);
			assert(ok);
			wait_ok, waited := Service.wait(
				fixture.host.service,
				shutdown,
				.{
					clock_identity = fixture.host.service.clock_identity,
					nanoseconds = 0,
				}
			);

			assert(wait_ok && waited.timed_out && waited.observation.phase == .DRAINING);
			Service.free_observation(*waited.observation);
			released, error = Service.release(fixture.host.service, fixture.host.session);
			assert(!released && error.code == .ACTIVE_SESSION);
			described, description := Service.describe_session(fixture.host.service, fixture.host.session);
			assert(described && Service.bytes_equal(description.session_identity.([] u8), fixture.host.session_identity.([] u8)));
			Service.free_description(*description);
			read_ok := Service.read_world(fixture.host.service, job.drain.world);
			assert(read_ok);
			release(fixture, shutdown);
			job.ok = true;

		case .TAKE_ANALYSIS_CAPACITY;
			_, description := Service.describe_session(fixture.host.service, fixture.host.session);
			ok, accepted := Service.request_analysis(
				fixture.host.service,
				fixture.host.session,
				.{
					version = Service.INTERFACE_VERSION,
					expected_frontier = description.accepted_frontier,
					documents = .[Service.harness_document(fixture.host, "a.jai")],
				}
			);

			job.ok = ok;
			job.analysis_ticket = accepted.ticket;
			free(accepted.frontier.data);
			Service.free_description(*description);

		case .COMPLETE_SHUTDOWN;
			Service.resume_pause(fixture.session, .PUBLICATION);
			observation := await(fixture, job.coordinator_shutdown);
			job.ok = observation.kind == .SHUTDOWN;
			Service.free_observation(*observation);

		case .GROW_PROVIDER_CLONE_COUNTS;
			Service.with_lock(
				*fixture.session.gate,
				#code {
					push_allocator(Service.owner_allocator(fixture.session));
					array_add(*fixture.session.provider.documents, fixture.session.provider.documents[0]);
					array_add(*fixture.session.provider.contexts, fixture.session.provider.contexts[0]);
				}
			);

			job.ok = true;

		case .GROW_PROVIDER_REVISION_COUNTS;
			Service.with_lock(
				*fixture.session.gate,
				#code {
					push_allocator(Service.owner_allocator(fixture.session));
					array_add(*fixture.session.provider.documents[0].used_revisions, fixture.session.provider.documents[0].used_revisions[0]);
				}
			);

			job.ok = true;

		case .FILL_OPERATION_CAPACITY;
			target: s64;
			Service.with_lock(
				*fixture.session.gate,
				#code {
					target = max(8, (fixture.session.operations.count + 1) * 2);
				}
			);

			_, description := Service.describe_session(fixture.host.service, fixture.host.session);
			while true {
				filled: bool;
				Service.with_lock(
					*fixture.session.gate,
					#code {
						filled = fixture.session.operations.count >= target;
						}
				);

				if filled {
					break;
				}


				ok, accepted := Service.request_analysis(
					fixture.host.service,
					fixture.host.session,
					.{
						version = Service.INTERFACE_VERSION,
						expected_frontier = description.accepted_frontier,
						documents = .[Service.harness_document(fixture.host, "a.jai")],
					}
				);

				assert(ok);
				array_add(*job.competing_tickets, accepted.ticket);
				free(accepted.frontier.data);
				observation := await(fixture, accepted.ticket);
				assert(observation.update.kind == .PUBLISHED);
				Service.free_observation(*observation);
			}

			Service.free_description(*description);
			job.ok = true;

		case .FILL_REGISTRATION_CAPACITY; #through;
		case .FILL_SHUTDOWN_CAPACITY;
			target: s64;
			Service.with_lock(
				*fixture.session.gate,
				#code {
					target = max(8, (fixture.session.registry.slots.count + 1) * 2);
				}
			);

			while true {
				filled: bool;
				Service.with_lock(
					*fixture.session.gate,
					#code {
						filled = fixture.session.registry.slots.count >= target;
					}
				);

				if filled {
					break;
				}


				if job.action == .FILL_SHUTDOWN_CAPACITY {
					ok, duplicate := Service.request_shutdown(fixture.host.service, fixture.host.session);
					assert(ok);
					array_add(*job.competing_shutdowns, duplicate);
				} else {
					ok, duplicate := Service.retain(fixture.host.service, job.drain.world);
					assert(ok);
					array_add(*job.competing_worlds, duplicate);
				}
			}

			job.ok = true;

		case .TAKE_RETAIN_CAPACITY;		#through;
		case .TAKE_PENDING_CAPACITY;	#through;
		case .TAKE_COMPLETION_CAPACITY;
			name := Service.Limit_Name.LIVE_HANDLES;
			if job.action == {
				case .TAKE_PENDING_CAPACITY;
					name = .PENDING_REGISTRATIONS;
				case .TAKE_COMPLETION_CAPACITY;
					name = .COMPLETION_RECORDS;
			}

			Service.with_lock(
				*fixture.session.gate,
				#code {
					fixture.session.ledger.limits.values[name] = fixture.session.ledger.live[name] + fixture.session.ledger.reserved[name];
				}
			);

			job.ok = true;

		case .RETIRE_RETAIN_OWNER;
			ok, shutdown := Service.request_shutdown(fixture.host.service, fixture.host.session);
			assert(ok);
			Service.resume_pause(fixture.session, .PUBLICATION);
			observation := await(fixture, shutdown);
			Service.free_observation(*observation);
			release(fixture, shutdown);
			release(fixture, fixture.host.session);
			release(fixture, job.drain.first);
			release(fixture, job.drain.second);
			release(fixture, job.drain.world);
			release(fixture, job.drain.ticket);
			for job.retained_worlds {
				release(fixture, it);
			}

			for job.retained_results {
				release(fixture, it);
			}

			if job.coordinator_shutdown.owner_token {
				release(fixture, job.coordinator_shutdown);
			}

			if job.retirement_ticket.owner_token {
				release(fixture, job.retirement_ticket);
			}

			if job.retirement_waiter.owner_token {
				release(fixture, job.retirement_waiter);
			}

			job.ok = !Service.session_of(fixture.host.service, fixture.host.session);
	}


	return 0;
}

Output_Probe :: struct {
	backing: Allocation_Ledger;
	allocations: s64;
	fail_at: s64;
	direct: bool;
	job: Output_Interleaving;
	gate_progress: bool;
	registration_probe: *Registration_Probe;
	source_document: [] u8;
	source_references: [2] s64;
	source_active_admissions: [2] s64;
}

output_probe_allocate :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, data: *void) -> *void {
	probe := data.(*Output_Probe);
	if mode == .ALLOCATE || mode == .RESIZE {
		probe.allocations += 1;
		if probe.allocations == 1 && probe.job.action != .NONE {
			push_allocator(context.default_allocator);
			if probe.registration_probe {
				probe.registration_probe.running = true;
			}

			thread := Thread.{data = *probe.job};
			if probe.direct {
				output_interleaving_job(*thread);
				probe.gate_progress = true;
			} else {
				assert(thread_init(*thread, output_interleaving_job));
				thread_start(*thread);
				probe.gate_progress = thread_is_done(*thread, 10_000);
				assert(probe.gate_progress, "\e[91mA caller allocator ran while the service state gate was held.\e[0m");
				thread_deinit(*thread);
			}

			if probe.registration_probe {
				probe.registration_probe.running = false;
			}
		}

		if probe.source_document.count {
			session := probe.job.drain.fixture.session;
			Service.with_lock(
				*session.gate,
				#code {
					state := Service.find_document(session.provider, probe.source_document);
					assert(state && state.has_overlay && state.overlay.source);
					assert(probe.allocations <= probe.source_references.count);
					probe.source_references[probe.allocations - 1] = state.overlay.source.references;
					probe.source_active_admissions[probe.allocations - 1] = session.active_admissions;
				}
			);
		}

		if probe.allocations == probe.fail_at {
			return null;
		}
	}


	return spy_allocate(mode, size, old_size, old_memory, *probe.backing);
}

open_output_probe :: (probe: *Output_Probe) -> Allocator {
	init(*probe.backing.gate);
	probe.backing.delegate = context.default_allocator;
	return .{proc = output_probe_allocate, data = probe};
}

close_output_probe :: (probe: *Output_Probe) {
	assert(!probe.backing.live_bytes && !probe.backing.sizes.count, "\e[91mA failed or retired caller copy leaked.\e[0m");
	deinit(*probe.backing.sizes);
	destroy(*probe.backing.gate);
}

test_drain_allocation_failures :: () {
	drain := prepared_drain("X5-output-failures");
	probe: Output_Probe;
	allocator := open_output_probe(*probe);
	fail_at: s64 = 1;
	while true {
		probe.fail_at = fail_at;
		probe.allocations = 0;
		ok, records, error := Service.drain_completions(
			drain.fixture.host.service,
			drain.fixture.host.session,
			8
			,, allocator
		);
		if ok {
			assert(records.count == 2 && probe.allocations == fail_at - 1);
			assert(records[0].registration.slot == drain.first.slot && records[1].registration.slot == drain.second.slot);
			free_records(records, allocator);
			break;
		}


		assert(error.code == .ADMISSION_DENIED && error.admission.kind == .RESOURCE_EXHAUSTED);
		assert(!records.count && !probe.backing.live_bytes && !probe.backing.sizes.count);
		Service.with_lock(
			*drain.fixture.session.gate,
			#code {
				assert(drain.fixture.session.ledger.live[Service.Limit_Name.COMPLETION_RECORDS] == 2, "\e[91mA failed drain consumed reserved completions.\e[0m");
			}
		);

		for Service.Handle(.WAITER).[drain.first, drain.second] {
			_, observation := Service.poll(drain.fixture.host.service, it);
			assert(observation.query.kind == .AVAILABLE);
			Service.free_observation(*observation);
		}

		fail_at += 1;
		assert(fail_at < 100, "\e[91mOutput failure injection did not reach a successful drain.\e[0m");
	}

	close_output_probe(*probe);
	finish_drain(drain);
	print("X5 every caller-output allocation failure preserves readiness \e[92mPASS\e[0m\n");
}

test_drain_output_interleavings :: (direct := false) {
	for Output_Action.[.RELEASE_WAITER, .OTHER_DRAIN, .RELEASE_SESSION] {
		action := it;
		drain := prepared_drain(tprint("X3-X5-output-%", action));
		if action == .RELEASE_SESSION {
			_, shutdown := Service.request_shutdown(drain.fixture.host.service, drain.fixture.host.session);
			observation := await(drain.fixture, shutdown);
			Service.free_observation(*observation);
			release(drain.fixture, shutdown);
		}

		probe := Output_Probe.{direct = direct, job = .{drain = drain, action = action}};
		allocator := open_output_probe(*probe);
		ok, records, error := Service.drain_completions(
			drain.fixture.host.service,
			drain.fixture.host.session,
			8
			,, allocator
		);
		assert(probe.gate_progress && probe.job.ok);
		if action == {
			case .RELEASE_WAITER;
				assert(ok && records.count == 1 && records[0].registration.slot == drain.second.slot);
				assert(probe.job.replacement.slot == drain.first.slot && probe.job.replacement.generation != drain.first.generation);
				_, description := Service.read_result(drain.fixture.host.service, probe.job.replacement);
				assert(description.snapshot.source == "answer :: 42;");
				release(drain.fixture, probe.job.replacement);

			case .OTHER_DRAIN;
				assert(ok && !records.count && probe.job.records.count == 2);
				free_records(probe.job.records);

			case .RELEASE_SESSION;
				assert(!ok && !records.count && error.code == .INVALID_HANDLE);
		}

		free_records(records, allocator);
		close_output_probe(*probe);
		finish_drain(drain, first_released = action == .RELEASE_WAITER, session_released = action == .RELEASE_SESSION);
	}

	print("X3/X5 off-gate caller allocation/reuse/concurrent drain/session retirement (direct = %) \e[92mPASS\e[0m\n", direct);
}

test_observer_output_failures :: () {
	for bool.[false, true] {
		use_wait := it;
		drain := prepared_drain(tprint("X1-observer-failure-%", use_wait));
		probe: Output_Probe;
		allocator := open_output_probe(*probe);
		fail_at: s64 = 1;
		while true {
			probe.fail_at = fail_at;
			probe.allocations = 0;
			ok: bool;
			observation: Service.Observation;
			error: Service.Operation_Error;
			if use_wait {
				waited: Service.Wait_Observation;
				ok, waited, error = Service.wait(
					drain.fixture.host.service,
					drain.first,
					.{clock_identity = drain.fixture.host.service.clock_identity, nanoseconds = FOREVER}
					,, allocator
				);
				observation = waited.observation;
			} else {
				ok, observation, error = Service.poll(drain.fixture.host.service, drain.first,, allocator);
			}

			if ok {
				assert(observation.query.kind == .AVAILABLE && probe.allocations == fail_at - 1);
				Service.free_observation(*observation,, allocator);
				break;
			}


			assert(error.code == .ADMISSION_DENIED && error.admission.kind == .RESOURCE_EXHAUSTED);
			assert(!probe.backing.live_bytes && !probe.backing.sizes.count);
			Service.with_lock(
				*drain.fixture.session.gate,
				#code {
					assert(drain.fixture.session.ledger.live[Service.Limit_Name.COMPLETION_RECORDS] == 2);
				}
			);

			fail_at += 1;
			assert(fail_at < 100);
		}

		close_output_probe(*probe);
		finish_drain(drain);
	}

	print("X1 every poll/wait output allocation failure preserves terminal state \e[92mPASS\e[0m\n");
}

test_observer_output_retirement :: (direct := false) {
	for bool.[false, true] {
		use_wait := it;
		drain := prepared_drain(tprint("X3-observer-retirement-%", use_wait));
		probe := Output_Probe.{direct = direct, job = .{drain = drain, action = .RELEASE_WAITER}};
		allocator := open_output_probe(*probe);
		ok: bool;
		observation: Service.Observation;
		error: Service.Operation_Error;
		if use_wait {
			waited: Service.Wait_Observation;
			ok, waited, error = Service.wait(
				drain.fixture.host.service,
				drain.first,
				.{clock_identity = drain.fixture.host.service.clock_identity, nanoseconds = FOREVER}
				,, allocator
			);
			observation = waited.observation;
		} else {
			ok, observation, error = Service.poll(drain.fixture.host.service, drain.first,, allocator);
		}

		assert(probe.gate_progress && probe.job.ok && !ok && error.code == .INVALID_HANDLE);
		Service.free_observation(*observation,, allocator);
		assert(probe.job.replacement.slot == drain.first.slot && probe.job.replacement.generation != drain.first.generation);
		release(drain.fixture, probe.job.replacement);
		close_output_probe(*probe);
		finish_drain(drain, first_released = true);
	}

	print("X3 poll/wait caller allocation permits retirement and reuse (direct = %) \e[92mPASS\e[0m\n", direct);
}

test_drain_output_negative_controls :: () {
	drain := prepared_drain("X5-failed-drain-control");
	drain.fixture.session.faults.consume_failed_drain = true;
	probe := Output_Probe.{fail_at = 1};
	allocator := open_output_probe(*probe);
	ok, records := Service.drain_completions(drain.fixture.host.service, drain.fixture.host.session, 8,, allocator);
	assert(!ok && !records.count);
	readiness_intact: bool;
	Service.with_lock(
		*drain.fixture.session.gate,
		#code {
			readiness_intact = drain.fixture.session.ledger.live[Service.Limit_Name.COMPLETION_RECORDS] == 2;
		}
	);

	assert(!readiness_intact, "\e[91mPremature drain-consumption control was not detected.\e[0m");
	close_output_probe(*probe);
	finish_drain(drain);

	drain = prepared_drain("X3-stale-drain-control");
	drain.fixture.session.faults.allow_stale_drain_output = true;
	probe = .{job = .{drain = drain, action = .RELEASE_WAITER}};
	allocator = open_output_probe(*probe);
	ok, records = Service.drain_completions(drain.fixture.host.service, drain.fixture.host.session, 8,, allocator);
	retired_delivered := false;
	for records {
		retired_delivered ||= it.registration.slot == drain.first.slot && it.registration.generation == drain.first.generation;
	}

	assert(ok && retired_delivered, "\e[91mStale-generation drain control was not detected.\e[0m");
	free_records(records, allocator);
	release(drain.fixture, probe.job.replacement);
	close_output_probe(*probe);
	finish_drain(drain, first_released = true);
	print("X3/X5 premature consumption and stale-output negative controls \e[92mPASS\e[0m\n");
}

Output_Read :: enum {
	PENDING_RESULT;
	CANCELLED_RESULT;
	TERMINAL_CANCELLATION;
	TERMINAL_TICKET;
	QUERY_CANCELLATION;
	UPDATE_CANCELLATION;
}

prepared_output_read :: (kind: Output_Read) -> Drain_Fixture {
	if kind == .UPDATE_CANCELLATION {
		fixture := open("X2-update-cancellation-output");
		previous := submit(fixture, "answer :: 42;");
		world := world_of(fixture, previous);
		release(fixture, previous);
		Service.arm_pause(fixture.session, .PUBLICATION);
		ticket := submit(fixture, "answer :: 84;");
		assert(Service.await_pause(fixture.session, .PUBLICATION));
		ok, first := Service.observe_ticket(fixture.host.service, ticket);
		assert(ok && !first.terminal);
		second_ok, second := Service.observe_ticket(fixture.host.service, ticket);
		assert(second_ok && !second.terminal);
		return .{
			fixture = fixture,
			ticket = ticket,
			world = world,
			first = first.waiter,
			second = second.waiter,
		};
	}


	drain := prepared_drain(tprint("X3-output-read-%", kind), held = kind != .TERMINAL_TICKET);
	if kind == .CANCELLED_RESULT || kind == .TERMINAL_CANCELLATION {
		ok, cancelled := Service.cancel_waiter(drain.fixture.host.service, drain.first);
		assert(ok && cancelled.observation.query.cancellation == .CALLER);
		Service.free_observation(*cancelled.observation);
	}

	return drain;
}

read_fixture_output :: (drain: Drain_Fixture, kind: Output_Read, allocator: Allocator) -> bool, Service.Observation, Service.Operation_Error {
	if (
		kind == .TERMINAL_CANCELLATION
		|| kind == .QUERY_CANCELLATION
		|| kind == .UPDATE_CANCELLATION
	) {
		ok, cancelled, error := Service.cancel_waiter(drain.fixture.host.service, drain.first,, allocator);
		if ok {
			assert(cancelled.already_terminal == (kind == .TERMINAL_CANCELLATION));
			if kind == .UPDATE_CANCELLATION {
				assert(cancelled.observation.kind == .UPDATE && cancelled.observation.update.kind == .CANCELLED);
				assert(cancelled.observation.update.cancellation == .CALLER);
			} else {
				assert(cancelled.observation.query.kind == .CANCELLED);
				assert(cancelled.observation.query.cancellation == .CALLER);
			}
		}

		return ok, cancelled.observation, error;
	}


	if kind == .TERMINAL_TICKET {
		ok, observed, error := Service.observe_ticket(drain.fixture.host.service, drain.ticket,, allocator);
		if ok {
			assert(observed.terminal && observed.observation.update.kind == .PUBLISHED);
			assert(observed.observation.documents.count == 1);
		}

		return ok, observed.observation, error;
	}


	ok, acquired, error := Service.acquire_result(drain.fixture.host.service, drain.first,, allocator);
	if ok {
		assert(!acquired.result.generation, "\e[91mAn observational acquisition created a payload handle.\e[0m");
		if kind == .PENDING_RESULT {
			assert(acquired.kind == .PENDING && acquired.observation.kind == .PENDING);
		} else {
			assert(acquired.kind == .TERMINAL && acquired.observation.query.kind == .CANCELLED);
			assert(acquired.observation.query.cancellation == .CALLER);
		}
	}

	return ok, acquired.observation, error;
}

test_acquisition_output_failures :: () {
	for Output_Read.[
		.PENDING_RESULT,
		.CANCELLED_RESULT,
		.TERMINAL_CANCELLATION,
		.TERMINAL_TICKET,
		.QUERY_CANCELLATION,
		.UPDATE_CANCELLATION,
	] {
		kind := it;
		drain := prepared_output_read(kind);
		live_handles := drain.fixture.session.ledger.live[Service.Limit_Name.LIVE_HANDLES];
		completions := drain.fixture.session.ledger.live[Service.Limit_Name.COMPLETION_RECORDS];
		probe: Output_Probe;
		allocator := open_output_probe(*probe);
		fail_at: s64 = 1;
		while true {
			probe.fail_at = fail_at;
			probe.allocations = 0;
			ok, observation, error := read_fixture_output(drain, kind, allocator);
			assert(drain.fixture.session.ledger.live[Service.Limit_Name.LIVE_HANDLES] == live_handles);
			assert(drain.fixture.session.ledger.live[Service.Limit_Name.COMPLETION_RECORDS] == completions);
			if ok {
				assert(fail_at > 1 && probe.allocations == fail_at - 1);
				Service.free_observation(*observation,, allocator);
				break;
			}


			assert(error.code == .ADMISSION_DENIED && error.admission.kind == .RESOURCE_EXHAUSTED);
			assert(!probe.backing.live_bytes && !probe.backing.sizes.count);
			if kind == .QUERY_CANCELLATION || kind == .UPDATE_CANCELLATION {
				_, pending := Service.poll(drain.fixture.host.service, drain.first);
				assert(pending.kind == .PENDING, "\e[91mFailed output allocation committed cancellation.\e[0m");
				Service.free_observation(*pending);
			}

			fail_at += 1;
			assert(fail_at < 100);
		}


		close_output_probe(*probe);
		finish_drain(drain, held = kind != .TERMINAL_TICKET);
	}

	print("X1/X5 acquisition/ticket/cancellation allocation failures preserve state \e[92mPASS\e[0m\n");
}

test_acquisition_output_retirement :: (direct := false) {
	for Output_Read.[
		.PENDING_RESULT,
		.CANCELLED_RESULT,
		.TERMINAL_CANCELLATION,
		.TERMINAL_TICKET,
		.QUERY_CANCELLATION,
		.UPDATE_CANCELLATION,
	] {
		kind := it;
		drain := prepared_output_read(kind);
		probe := Output_Probe.{
			direct = direct,
			job = .{
				drain = drain,
				action = ifx kind == .TERMINAL_TICKET
					then .RELEASE_TICKET
					else .RELEASE_WAITER,
			},
		};

		allocator := open_output_probe(*probe);
		ok, observation, error := read_fixture_output(drain, kind, allocator);
		assert(probe.gate_progress && probe.job.ok && !ok && error.code == .INVALID_HANDLE);
		if kind == .TERMINAL_TICKET {
			assert(probe.job.replacement.slot == drain.ticket.slot && probe.job.replacement.generation != drain.ticket.generation);
		} else {
			assert(probe.job.replacement.slot == drain.first.slot && probe.job.replacement.generation != drain.first.generation);
		}

		Service.free_observation(*observation,, allocator);
		release(drain.fixture, probe.job.replacement);
		close_output_probe(*probe);
		finish_drain(
			drain,
			first_released = kind != .TERMINAL_TICKET,
			ticket_released = kind == .TERMINAL_TICKET,
			held = kind != .TERMINAL_TICKET
		);
	}

	print("X3 acquisition/ticket/cancellation output retirement and reuse (direct = %) \e[92mPASS\e[0m\n", direct);
}

test_cancellation_output_winners :: (direct := false) {
	for Output_Read.[.QUERY_CANCELLATION, .UPDATE_CANCELLATION] {
		kind := it;
		for Output_Action.[.COMPLETE_WORK, .CANCEL_WAITER, .REQUEST_SHUTDOWN] {
			action := it;
			drain := prepared_output_read(kind);
			probe := Output_Probe.{
				direct = direct,
				job = .{drain = drain, action = action},
			};

			allocator := open_output_probe(*probe);
			ok, cancelled := Service.cancel_waiter(drain.fixture.host.service, drain.first,, allocator);
			assert(probe.gate_progress && probe.job.ok && ok && cancelled.already_terminal);
			observation := cancelled.observation;
			if action == .COMPLETE_WORK {
				if kind == .QUERY_CANCELLATION {
					assert(observation.query.kind == .AVAILABLE);
				} else {
					assert(observation.update.kind == .PUBLISHED);
				}
			} else {
				cause := ifx kind == .QUERY_CANCELLATION
					then observation.query.cancellation
					else observation.update.cancellation;
				assert(cause == (ifx action == .CANCEL_WAITER then .CALLER else .SHUTDOWN));
			}

			Service.free_observation(*cancelled.observation,, allocator);
			close_output_probe(*probe);
			if action != .REQUEST_SHUTDOWN {
				if action != .COMPLETE_WORK {
					Service.resume_pause(drain.fixture.session, .PUBLICATION);
				}

				observation = await(drain.fixture, drain.second);
				if kind == .QUERY_CANCELLATION {
					assert(observation.query.kind == .AVAILABLE);
				} else {
					assert(observation.update.kind == .PUBLISHED);
				}

				Service.free_observation(*observation);
			}

			_, records := Service.drain_completions(drain.fixture.host.service, drain.fixture.host.session, 8);
			assert(records.count == 2, "\e[91mCancellation staging duplicated or lost a terminal completion.\e[0m");
			assert(records[0].registration.slot != records[1].registration.slot);
			free_records(records);
			finish_drain(drain, held = action == .REQUEST_SHUTDOWN);
		}
	}

	print("X2 cancellation output completion/cancel/shutdown winners (direct = %) \e[92mPASS\e[0m\n", direct);
}

test_cancellation_output_negative_control :: () {
	for Output_Read.[.QUERY_CANCELLATION, .UPDATE_CANCELLATION] {
		drain := prepared_output_read(it);
		drain.fixture.session.faults.cancel_before_output = true;
		probe := Output_Probe.{fail_at = 1};
		allocator := open_output_probe(*probe);
		ok, cancelled, error := Service.cancel_waiter(drain.fixture.host.service, drain.first,, allocator);
		assert(!ok && error.code == .ADMISSION_DENIED && error.admission.kind == .RESOURCE_EXHAUSTED);
		Service.free_observation(*cancelled.observation,, allocator);
		_, observation := Service.poll(drain.fixture.host.service, drain.first);
		assert(observation.kind != .PENDING, "\e[91mPremature cancellation negative control was not detected.\e[0m");
		Service.free_observation(*observation);
		close_output_probe(*probe);
		finish_drain(drain, held = true);
	}

	print("X5 cancellation-before-copy negative control \e[92mPASS\e[0m\n");
}

test_cancellation_retry_output_failures :: (direct := false) {
	for Output_Read.[.QUERY_CANCELLATION, .UPDATE_CANCELLATION] {
		kind := it;
		fail_at: s64 = 1;
		while true {
			drain := prepared_output_read(kind);
			probe := Output_Probe.{
				fail_at = fail_at,
				direct = direct,
				job = .{drain = drain, action = .COMPLETE_WORK},
			};

			allocator := open_output_probe(*probe);
			ok, cancelled, error := Service.cancel_waiter(drain.fixture.host.service, drain.first,, allocator);
			assert(probe.gate_progress && probe.job.ok);
			if ok {
				assert(cancelled.already_terminal && probe.allocations == fail_at - 1);
				if kind == .QUERY_CANCELLATION {
					assert(cancelled.observation.query.kind == .AVAILABLE);
				} else {
					assert(cancelled.observation.update.kind == .PUBLISHED);
				}
			} else {
				assert(error.code == .ADMISSION_DENIED && error.admission.kind == .RESOURCE_EXHAUSTED);
			}

			Service.free_observation(*cancelled.observation,, allocator);
			close_output_probe(*probe);
			_, observation := Service.poll(drain.fixture.host.service, drain.first);
			if kind == .QUERY_CANCELLATION {
				assert(observation.query.kind == .AVAILABLE);
			} else {
				assert(observation.update.kind == .PUBLISHED);
			}

			Service.free_observation(*observation);
			_, records := Service.drain_completions(drain.fixture.host.service, drain.fixture.host.session, 8);
			assert(records.count == 2);
			free_records(records);
			finish_drain(drain);
			if ok {
				break;
			}


			fail_at += 1;
			assert(fail_at < 100);
		}
	}

	print("X2/X5 cancellation completion-winner retry allocation failures (direct = %) \e[92mPASS\e[0m\n", direct);
}

prepared_description :: () -> Drain_Fixture {
	drain := prepared_drain("X5-description-output");
	write_entire_file(tprint("%/a.jai", drain.fixture.host.root), "disk :: 7;");
	write_entire_file(tprint("%/b.jai", drain.fixture.host.root), "other :: 8;");
	batch := Service.begin_batch(drain.fixture.host);
	assert(Service.observe_disk(*batch, "a.jai"));
	assert(Service.observe_disk(*batch, "b.jai"));
	ok, accepted := Service.submit_batch(*batch);
	assert(ok);
	observation := await(drain.fixture, accepted.ticket);
	assert(observation.update.kind == .PUBLISHED);
	Service.free_observation(*observation);
	release(drain.fixture, accepted.ticket);
	return drain;
}

assert_description_bytes :: (copy: [] u8, expected: [] u8) {
	assert(Service.bytes_equal(copy, expected));
	assert(!copy.count || copy.data != expected.data, "\e[91mDescription exports alias another owner's bytes.\e[0m");
}

assert_description_copy :: (copy: Service.Session_Description, expected: Service.Session_Description) {
	assert_description_bytes(copy.session_identity.([] u8), expected.session_identity.([] u8));
	assert_description_bytes(copy.workspace, expected.workspace);
	assert_description_bytes(copy.provider_namespace, expected.provider_namespace);
	assert_description_bytes(copy.accepted_frontier, expected.accepted_frontier);
	assert_description_bytes(copy.clock_identity, expected.clock_identity);
	assert(copy.lifecycle == expected.lifecycle && copy.store_mode == expected.store_mode);
	for expected.effective_limits.values {
		assert(copy.effective_limits.values[it_index] == it);
	}

	assert(copy.tracked_document_states.count == expected.tracked_document_states.count);
	assert(!copy.tracked_document_states.count || copy.tracked_document_states.data != expected.tracked_document_states.data);
	for expected.tracked_document_states {
		actual := copy.tracked_document_states[it_index];
		assert_description_bytes(actual.document, it.document);
		assert_description_bytes(actual.provider_revision, it.provider_revision);
		assert_description_bytes(actual.binding.document, it.binding.document);
		assert_description_bytes(actual.binding.absolute_path.code_units, it.binding.absolute_path.code_units);
		assert_description_bytes(actual.disk_source_revision, it.disk_source_revision);
		assert_description_bytes(actual.disk_context, it.disk_context);
		assert_description_bytes(actual.overlay_installation_revision, it.overlay_installation_revision);
		assert_description_bytes(actual.overlay_source_revision, it.overlay_source_revision);
		assert_description_bytes(actual.overlay_context, it.overlay_context);
		assert(actual.binding.absolute_path.encoding == it.binding.absolute_path.encoding);
		assert(actual.binding.provider_policy_version == it.binding.provider_policy_version);
		assert(actual.disk_kind == it.disk_kind && actual.has_overlay == it.has_overlay);
		assert(actual.overlay_origin == it.overlay_origin && actual.selection == it.selection);
	}
}

test_description_output_failures :: () {
	drain := prepared_description();
	_, expected := Service.describe_session(drain.fixture.host.service, drain.fixture.host.session);
	assert(expected.tracked_document_states.count == 2);
	for expected.tracked_document_states {
		assert(it.disk_kind == .PRESENT && it.disk_source_revision.count && it.disk_context.count);
		if Service.bytes_equal(it.document, Service.harness_document(drain.fixture.host, "a.jai")) {
			assert(it.has_overlay && it.overlay_installation_revision.count && it.overlay_source_revision.count && it.overlay_context.count);
		} else {
			assert(!it.has_overlay && !it.overlay_source_revision.count);
		}
	}

	probe: Output_Probe;
	allocator := open_output_probe(*probe);
	fail_at: s64 = 1;
	while true {
		probe.fail_at = fail_at;
		probe.allocations = 0;
		ok, description, error := Service.describe_session(drain.fixture.host.service, drain.fixture.host.session,, allocator);
		if ok {
			assert(probe.allocations == fail_at - 1 && fail_at > 15);
			assert_description_copy(description, expected);
			description.workspace[0] ^= 0x7F;
			description.tracked_document_states[0].binding.absolute_path.code_units[0] ^= 0x7F;
			Service.free_description(*description,, allocator);
			break;
		}


		assert(error.code == .ADMISSION_DENIED && error.admission.kind == .RESOURCE_EXHAUSTED);
		assert(!description.tracked_document_states.count && !description.accepted_frontier.count);
		Service.free_description(*description,, allocator);
		assert(!probe.backing.live_bytes && !probe.backing.sizes.count);
		fail_at += 1;
		assert(fail_at < 100);
	}

	_, current := Service.describe_session(drain.fixture.host.service, drain.fixture.host.session);
	assert_description_copy(current, expected);
	Service.free_description(*current);
	Service.free_description(*expected);
	close_output_probe(*probe);
	finish_drain(drain);
	print("X5 every description allocation failure and deep-copy isolation \e[92mPASS\e[0m\n");
}

test_description_output_interleavings :: (direct := false) {
	for Output_Action.[.REPLACE_SOURCE, .REQUEST_SHUTDOWN, .RELEASE_SESSION] {
		action := it;
		drain := prepared_description();
		if action == .RELEASE_SESSION {
			_, shutdown := Service.request_shutdown(drain.fixture.host.service, drain.fixture.host.session);
			observation := await(drain.fixture, shutdown);
			Service.free_observation(*observation);
			release(drain.fixture, shutdown);
		}

		_, expected := Service.describe_session(drain.fixture.host.service, drain.fixture.host.session);
		probe := Output_Probe.{
			direct = direct,
			job = .{drain = drain, action = action},
		};

		allocator := open_output_probe(*probe);
		ok, description, error := Service.describe_session(drain.fixture.host.service, drain.fixture.host.session,, allocator);
		assert(probe.gate_progress && probe.job.ok);
		if action == .RELEASE_SESSION {
			assert(!ok && error.code == .INVALID_HANDLE);
		} else {
			assert(ok);
			assert_description_copy(description, expected);
			_, current := Service.describe_session(drain.fixture.host.service, drain.fixture.host.session);
			if action == .REPLACE_SOURCE {
				assert(!Service.bytes_equal(current.accepted_frontier, description.accepted_frontier));
			} else {
				assert(current.lifecycle != .OPEN && description.lifecycle == .OPEN);
			}

			Service.free_description(*current);
		}

		Service.free_description(*description,, allocator);
		Service.free_description(*expected);
		close_output_probe(*probe);
		finish_drain(drain, session_released = action == .RELEASE_SESSION);
	}

	print("X3/X5 description snapshot/frontier/shutdown/retirement (direct = %) \e[92mPASS\e[0m\n", direct);
}

test_description_retirement_negative_control :: () {
	drain := prepared_description();
	_, shutdown := Service.request_shutdown(drain.fixture.host.service, drain.fixture.host.session);
	observation := await(drain.fixture, shutdown);
	Service.free_observation(*observation);
	release(drain.fixture, shutdown);
	drain.fixture.session.faults.allow_retired_description = true;
	probe := Output_Probe.{
		direct = true,
		job = .{drain = drain, action = .RELEASE_SESSION},
	};

	allocator := open_output_probe(*probe);
	ok, description := Service.describe_session(drain.fixture.host.service, drain.fixture.host.session,, allocator);
	assert(probe.gate_progress && probe.job.ok && ok, "\e[91mRetired-description negative control was not detected.\e[0m");
	assert(!Service.session_of(drain.fixture.host.service, drain.fixture.host.session));
	Service.free_description(*description,, allocator);
	close_output_probe(*probe);
	finish_drain(drain, session_released = true);
	print("X3 retired-description revalidation negative control \e[92mPASS\e[0m\n");
}

open_output_options :: () -> Service.Session_Options {
	return .{
		version = Service.INTERFACE_VERSION,
		workspace = xx "open-output-workspace",
		provider_namespace = xx "open-output-provider",
		host_authority = xx "open-output-host",
		provider_capabilities = .{
			adapter_schema = Service.SOURCE_PROVIDER_SCHEMA,
			authority_identity = xx "open-output-host",
			document_policy_version = 1,
			path_platform = .WINDOWS_UTF16LE,
			consistency_capabilities = .IMMUTABLE_CAPTURE,
		},
		supported_tuples = .[Service.IMPLEMENTED_SCHEMA_TUPLE],
	};
}

close_output_session :: (service: *Service.Service, handle: Service.Handle(.SESSION)) {
	ok, shutdown := Service.request_shutdown(service, handle);
	assert(ok);
	waited_ok, waited := Service.wait(
		service,
		shutdown,
		.{
			clock_identity = service.clock_identity,
			nanoseconds = FOREVER,
		}
	);

	assert(waited_ok && !waited.timed_out && waited.observation.kind == .SHUTDOWN);
	Service.free_observation(*waited.observation);
	assert(Service.release(service, shutdown));
	assert(Service.release(service, handle));
}

directory_service_owned :: (service: *Service.Service) -> bool {
	service_owned: bool;
	Service.with_lock(
		*allocation_ledger.gate,
		#code {
			service_owned = table_contains(*allocation_ledger.sizes, service.sessions.data);
		}
	);

	return service_owned;
}

Directory_Retirement :: struct {
	service: *Service.Service;
	memory: *void;
	direct: bool;
	gate_progress: bool;
	reopened: Service.Handle(.SESSION);
}

directory_retirement_job :: (thread: *Thread) -> s64 {
	retirement := thread.data.(*Directory_Retirement);
	assert(!retirement.service.sessions.count && !retirement.service.sessions.data);
	ok, opened := Service.open_session(retirement.service, open_output_options());
	assert(ok && retirement.service.sessions.data != retirement.memory);
	Service.free_description(*opened.description);
	retirement.reopened = opened.session;
	return 0;
}

test_directory_backing :: () {
	for bool.[false, true] {
		first_retires_early := it;
		fixture := open("X3-directory-backing");
		service := fixture.host.service;
		assert(directory_service_owned(service), "\e[91mThe shared directory backing belongs to a session heap.\e[0m");
		capacity := service.sessions.allocated;
		extra: [..] Service.Handle(.SESSION);
		ok, survivor := Service.open_session(service, open_output_options());
		assert(ok);
		Service.free_description(*survivor.description);
		if first_retires_early {
			close_output_session(service, fixture.host.session);
		}

		for 0..capacity {
			admitted, opened := Service.open_session(service, open_output_options());
			assert(admitted && opened.session.owner_token != fixture.host.session.owner_token);
			Service.free_description(*opened.description);
			array_add(*extra, opened.session);
		}

		assert(service.sessions.allocated > capacity && directory_service_owned(service));
		for extra {
			described, description := Service.describe_session(service, it);
			assert(described && description.lifecycle == .OPEN);
			Service.free_description(*description);
			close_output_session(service, it);
		}

		array_free(extra);
		survived, description := Service.describe_session(service, survivor.session);
		assert(survived && description.lifecycle == .OPEN);
		Service.free_description(*description);
		close_output_session(service, survivor.session);
		if !first_retires_early {
			close_output_session(service, fixture.host.session);
		}

		assert(!service.sessions.count && !service.sessions.data && !service.sessions.allocated && !service.sessions.allocator.proc);
		assert(!service.owned_allocations && !service.owned_bytes);
		assert_no_owned_allocations();
		retired_ok, retired, error := Service.describe_session(service, fixture.host.session);
		assert(!retired_ok && error.code == .INVALID_HANDLE);
		Service.free_description(*retired);
		for 0..2 {
			reopened_ok, reopened := Service.open_session(service, open_output_options());
			assert(reopened_ok && reopened.session.owner_token != fixture.host.session.owner_token);
			assert(directory_service_owned(service));
			Service.free_description(*reopened.description);
			close_output_session(service, reopened.session);
			assert(!service.sessions.data && !service.owned_allocations && !service.owned_bytes);
			assert_no_owned_allocations();
		}

		service.session_owned_directory = true;
		control_ok, control := Service.open_session(service, open_output_options());
		assert(control_ok && !directory_service_owned(service), "\e[91mSession-owned directory negative control was not detected.\e[0m");
		Service.free_description(*control.description);
		close_output_session(service, control.session);
		assert(!service.sessions.data && !service.owned_allocations && !service.owned_bytes);
		assert_no_owned_allocations();
	}

	print("X3 shared directory growth/retirement/reopen and owner negative control \e[92mPASS\e[0m\n");
}

test_directory_retirement_reentry :: (direct := false, negative_control := false) {
	fixture := open("X3-directory-retirement-reentry");
	service := fixture.host.service;
	handle := fixture.host.session;
	if negative_control {
		close_output_session(service, handle);
		service.session_owned_directory = true;
		ok, opened := Service.open_session(service, open_output_options());
		assert(ok);
		handle = opened.session;
		Service.free_description(*opened.description);
	}

	retirement := Directory_Retirement.{
		service = service,
		memory = service.sessions.data,
		direct = direct,
	};

	Service.with_lock(
		*allocation_ledger.gate,
		#code {
			allocation_ledger.directory_retirement = *retirement;
		}
	);

	close_output_session(service, handle);
	if negative_control {
		detected: bool;
		Service.with_lock(
			*allocation_ledger.gate,
			#code {
				detected = allocation_ledger.directory_retirement == *retirement;
				allocation_ledger.directory_retirement = null;
			}
		);

		assert(detected && !retirement.gate_progress && !retirement.reopened.generation, "\e[91mWrong-owner directory free negative control was not detected.\e[0m");
		assert(!service.sessions.data && !service.owned_allocations && !service.owned_bytes);
		assert_no_owned_allocations();
		print("X3 wrong-owner directory free negative control (direct = %) \e[92mPASS\e[0m\n", direct);
		return;
	}


	assert(retirement.gate_progress && retirement.reopened.generation);
	assert(service.sessions.count == 1 && directory_service_owned(service));
	described, description := Service.describe_session(service, retirement.reopened);
	assert(described && description.lifecycle == .OPEN);
	Service.free_description(*description);
	close_output_session(service, retirement.reopened);
	assert(!service.sessions.data && !service.owned_allocations && !service.owned_bytes);
	assert_no_owned_allocations();
	print("X3 directory retirement permits reopen before backing free (direct = %) \e[92mPASS\e[0m\n", direct);
}

Directory_Allocation :: struct {
	delegate: Allocator;
	fail_next: bool;
	attempts: s64;
	failures: s64;
	service: *Service.Service;
	armed: bool;
	direct: bool;
	gate_progress: bool;
	expected_count: s64;
	retire: [] Service.Handle(.SESSION);
	open_count: s64;
	opened: [..] Service.Handle(.SESSION);
}

directory_allocate :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, data: *void) -> *void {
	probe := data.(*Directory_Allocation);
	if mode == .ALLOCATE {
		probe.attempts += 1;
		if probe.fail_next {
			probe.fail_next = false;
			probe.failures += 1;
			return null;
		}


		if probe.armed {
			probe.armed = false;
			push_allocator(context.default_allocator);

			thread := Thread.{data = probe};
			if probe.direct {
				directory_allocation_job(*thread);
				probe.gate_progress = true;
			} else {
				assert(thread_init(*thread, directory_allocation_job));
				thread_start(*thread);
				probe.gate_progress = thread_is_done(*thread, 10_000);
				assert(probe.gate_progress, "\e[91mDirectory backing allocation held its gate.\e[0m");
				thread_deinit(*thread);
			}
		}
	}


	return probe.delegate.proc(mode, size, old_size, old_memory, probe.delegate.data);
}

directory_allocation_job :: (thread: *Thread) -> s64 {
	probe := thread.data.(*Directory_Allocation);
	Service.with_lock(
		*probe.service.directory,
		#code {
			assert(probe.service.sessions.count == probe.expected_count, "\e[91mThe allocating session was published before admission.\e[0m");
		}
	);

	for probe.retire {
		close_output_session(probe.service, it);
	}

	if probe.retire.count {
		assert(!probe.service.sessions.data && !probe.service.sessions.count);
	}

	while probe.opened.count < probe.open_count {
		ok, opened := Service.open_session(probe.service, open_output_options());
		assert(ok);
		Service.free_description(*opened.description);
		array_add(*probe.opened, opened.session);
	}

	return 0;
}

test_directory_allocation_interleavings :: (direct := false) {
	for bool.[false, true] {
		retire_directory := it;
		for bool.[false, true] {
			negative_control := it;
			fixture := open("X3-directory-allocation-interleaving");
			service := fixture.host.service;
			handles: [..] Service.Handle(.SESSION);
			array_add(*handles, fixture.host.session);
			while service.sessions.count < service.sessions.allocated {
				ok, opened := Service.open_session(service, open_output_options());
				assert(ok);
				Service.free_description(*opened.description);
				array_add(*handles, opened.session);
			}

			capacity := service.sessions.allocated;
			probe := Directory_Allocation.{
				delegate = service.allocator,
				service = service,
				armed = true,
				direct = direct,
				expected_count = service.sessions.count,
				open_count = (ifx retire_directory then 1 else capacity),
			};

			if retire_directory {
				probe.retire = handles;
			}

			service.directory_allocator = .{proc = directory_allocate, data = *probe};
			service.reject_changed_directory = negative_control;
			ok, opened, error := Service.open_session(service, open_output_options());
			assert(probe.gate_progress && !probe.armed && !probe.failures);
			assert(ok != negative_control, "\e[91mChanged-directory rejection negative control was not detected.\e[0m");
			if ok {
				Service.free_description(*opened.description);
			} else {
				assert(error.code == .ADMISSION_DENIED && error.admission.kind == .RESOURCE_EXHAUSTED);
			}

			service.reject_changed_directory = false;
			expected_count := (ifx retire_directory then 0 else handles.count) + probe.opened.count + ok.(s64);
			assert(service.sessions.count == expected_count && directory_service_owned(service));
			if retire_directory {
				assert(probe.attempts == 2 && service.sessions.allocated == capacity);
			} else {
				assert(probe.attempts == (ifx negative_control then 2 else 3));
				assert(service.sessions.allocated == capacity * (ifx negative_control then 2 else 4));
			}

			for handles {
				described, description, describe_error := Service.describe_session(service, it);
				if retire_directory {
					assert(!described && describe_error.code == .INVALID_HANDLE);
				} else {
					assert(described && description.lifecycle == .OPEN);
					close_output_session(service, it);
				}

				Service.free_description(*description);
			}

			for probe.opened {
				described, description := Service.describe_session(service, it);
				assert(described && description.lifecycle == .OPEN);
				Service.free_description(*description);
				close_output_session(service, it);
			}

			if ok {
				close_output_session(service, opened.session);
			}

			array_free(handles);
			array_free(probe.opened);
			assert(!service.sessions.data && !service.owned_allocations && !service.owned_bytes);
			assert_no_owned_allocations();
		}
	}

	print("X3 directory allocation/retry/concurrent open/retirement and negative controls (direct = %) \e[92mPASS\e[0m\n", direct);
}

test_directory_allocation_failures :: () {
	for bool.[false, true] {
		empty_directory := it;
		for bool.[false, true] {
			negative_control := it;
			fixture := open("X3-directory-allocation-failure");
			service := fixture.host.service;
			handles: [..] Service.Handle(.SESSION);
			if empty_directory {
				close_output_session(service, fixture.host.session);
			} else {
				array_add(*handles, fixture.host.session);
				while service.sessions.count < service.sessions.allocated {
					ok, opened := Service.open_session(service, open_output_options());
					assert(ok);
					Service.free_description(*opened.description);
					array_add(*handles, opened.session);
				}
			}

			backing := service.sessions.data;
			count := service.sessions.count;
			owned_bytes := service.owned_bytes;
			owned_allocations := service.owned_allocations;
			next_identity := service.incarnation.session_counter.next;
			probe := Directory_Allocation.{delegate = service.allocator, fail_next = true};
			service.directory_allocator = .{proc = directory_allocate, data = *probe};
			service.retry_failed_directory_allocation = negative_control;
			caller := Allocation_Ledger.{delegate = context.default_allocator};
			init(*caller.gate);
			caller_allocator := Allocator.{proc = spy_allocate, data = *caller};
			ok, opened, error := Service.open_session(service, open_output_options(),, caller_allocator);
			rejected := !ok && error.code == .ADMISSION_DENIED && error.admission.kind == .RESOURCE_EXHAUSTED;
			assert(probe.failures == 1 && rejected != negative_control, "\e[91mDirectory allocation failure/admission negative control was not detected.\e[0m");
			assert(service.incarnation.session_counter.next == next_identity + 1);
			if ok {
				Service.free_description(*opened.description,, caller_allocator);
				close_output_session(service, opened.session);
			} else {
				assert(!opened.session.owner_token && !opened.description.workspace.count);
				assert(probe.attempts == 1 && service.sessions.data == backing && service.sessions.count == count);
			}

			assert(service.owned_bytes == owned_bytes && service.owned_allocations == owned_allocations);
			assert(!caller.live_bytes && !caller.sizes.count, "\e[91mRejected directory admission leaked caller output.\e[0m");
			deinit(*caller.sizes);
			destroy(*caller.gate);
			service.retry_failed_directory_allocation = false;
			retried, retry := Service.open_session(service, open_output_options());
			assert(retried && retry.session.owner_token >= next_identity + 1);
			Service.free_description(*retry.description);
			close_output_session(service, retry.session);
			for handles {
				described, description := Service.describe_session(service, it);
				assert(described && description.lifecycle == .OPEN);
				Service.free_description(*description);
				close_output_session(service, it);
			}

			array_free(handles);
			assert(!service.sessions.data && !service.owned_allocations && !service.owned_bytes);
			assert_no_owned_allocations();
		}
	}

	print("X3 directory allocation failure/private worker cleanup/admission negative control \e[92mPASS\e[0m\n");
}

receipt_source_batch :: (batch: Service.Host_Batch) -> Service.Source_Batch {
	return .{
		version = Service.INTERFACE_VERSION,
		session = batch.host.session_identity,
		expected_frontier = batch.description.accepted_frontier,
		contexts = batch.contexts,
		events = batch.events,
	};
}

test_source_registration_failures :: (
	update := false,
	list := false,
	provider := false,
	arrays := false,
	states := false,
	revisions := false,
	pool := false,
	batch_states := false,
	batch_revisions := false,
	batch_pair := false,
	batch_sources := false,
	batch_source_bytes := false,
	batch_source_identities := false,
	batch_edits := false,
	batch_state_list := false,
	batch_reference_list := false,
	batch_context_list := false,
	batch_paths := false,
	path_error := false,
	edit_pair := false,
	empty_source := false,
	event_kind: Service.Event_Kind = .SET_OVERLAY
) {
	assert(event_kind == .SET_OVERLAY || (batch_sources || batch_source_bytes || batch_source_identities || batch_edits || batch_reference_list || batch_paths) && !batch_pair && (!empty_source || batch_edits));
	assert(!path_error || batch_paths && event_kind == .OBSERVE_DISK);
	assert(!batch_edits || event_kind == .EDIT_OVERLAY);
	assert(!edit_pair || batch_edits && !empty_source);
	assert(!empty_source || (batch_source_bytes || batch_source_identities || batch_edits) && !batch_pair);
	assert(!batch_pair || batch_states || batch_revisions || batch_sources || batch_source_bytes || batch_source_identities || batch_state_list || batch_reference_list || batch_context_list || batch_paths);
	for Retain_Backing_Case.[.ARRAYS, .OBJECT, .REUSE] {
		scenario := it;
		allocation_count := ifx batch_paths
			then ifx path_error
				then 2
				else 1
			else ifx batch_context_list
				then ifx batch_pair
					then 1
					else 0
				else ifx empty_source && (batch_source_bytes || batch_edits)
					then 0
					else ifx batch_edits
						then ifx edit_pair
							then 2
							else 1
						else ifx batch_state_list || batch_reference_list
							then 1
							else ifx arrays
								then 2
								else ifx batch_states || batch_revisions || batch_sources || batch_source_bytes || batch_source_identities
									then ifx batch_pair
										then 2
										else 1
									else ifx list || provider || states || revisions || pool
										then 1
										else ifx update || scenario == .ARRAYS
											then 3
											else ifx scenario == .OBJECT
												then 1
												else 0;

		for 1..allocation_count + 1 {
			fail_at := it;
			test := prepared_retain(.WORLD, scenario);
			fixture := test.drain.fixture;
			batch := Service.begin_batch(fixture.host);
			submitted := ifx empty_source then "" else "answer :: 77;";
			expected_world := submitted;
			assert(Service.set_overlay(*batch, "a.jai", submitted));
			if batch_pair {
				assert(Service.set_overlay(*batch, "added.jai", "second :: 2;"));
			}

			edits: [2] Service.Range_Edit;
			disk_revision: [] u8;
			if event_kind == .OBSERVE_DISK {
				disk_revision = Service.source_revision_of(xx submitted);
			}

			before: Service.Resource_Ledger;
			identities: Service.Session_Identities;
			slots: [] Service.Registration_Slot;
			free_count: s64;
			operations: s64;
			documents: s64;
			source: *Service.Source_Backing;
			source_references: s64;
			probe := Registration_Probe.{fail_at = fail_at};
			output_probe := Output_Probe.{};
			allocator := open_output_probe(*output_probe);
			Service.with_lock(
				*fixture.session.gate,
				#code {
					before = fixture.session.ledger;
					identities = fixture.session.identities;
					slots = array_copy(fixture.session.registry.slots);
					free_count = fixture.session.registry.free_slots.count;
					operations = fixture.session.operations.count;
					documents = fixture.session.provider.documents.count;
					source = Service.selected_document(Service.find_document(fixture.session.provider, batch.events[0].document)).source;
					assert(!!source);
					source_references = source.references;
					event := *batch.events[0];
					event.kind = event_kind;
					if event_kind == {
						case .EDIT_OVERLAY;
							event.base_source_revision = source.revision;
							first := ifx edit_pair
								then "x :: 1;"
								else submitted;
							edits[0] = .{
								end_byte = xx source.bytes.count,
								replacement = xx first,
							};

							edits[1] = .{
								end_byte = xx first.count,
								replacement = xx submitted,
							};

							event.edits = edits;
							event.edits.count = ifx edit_pair
								then 2
								else 1;

						case .OBSERVE_DISK;
							expected_world = source.bytes.(string);
							event.disk = .{
								kind = .PRESENT,
								source = event.source,
								source_revision = disk_revision,
								syntax_context = event.source_context,
								provenance = .{
									provider_identity = fixture.session.provider.provider_namespace,
									observation_token = xx "source-construction-test",
								},
							};
					}

					if path_error {
						event.disk.syntax_context = xx "unknown-context";
					}

					if batch_paths {
						fixture.session.faults.source_batch_path_allocation_hook = registration_allocation_probe;
						fixture.session.faults.source_batch_path_allocation_data = *probe;
					} else if batch_context_list {
						fixture.session.faults.source_batch_context_list_allocation_hook = registration_allocation_probe;
						fixture.session.faults.source_batch_context_list_allocation_data = *probe;
					} else if batch_reference_list {
						fixture.session.faults.source_batch_reference_list_allocation_hook = registration_allocation_probe;
						fixture.session.faults.source_batch_reference_list_allocation_data = *probe;
					} else if batch_state_list {
						fixture.session.faults.source_batch_state_list_allocation_hook = registration_allocation_probe;
						fixture.session.faults.source_batch_state_list_allocation_data = *probe;
					} else if batch_edits {
						fixture.session.faults.source_batch_edit_allocation_hook = registration_allocation_probe;
						fixture.session.faults.source_batch_edit_allocation_data = *probe;
					} else if batch_source_identities {
						fixture.session.faults.source_batch_source_identity_allocation_hook = registration_allocation_probe;
						fixture.session.faults.source_batch_source_identity_allocation_data = *probe;
					} else if batch_source_bytes {
						fixture.session.faults.source_batch_source_bytes_allocation_hook = registration_allocation_probe;
						fixture.session.faults.source_batch_source_bytes_allocation_data = *probe;
					} else if batch_sources {
						fixture.session.faults.source_batch_source_allocation_hook = registration_allocation_probe;
						fixture.session.faults.source_batch_source_allocation_data = *probe;
					} else if batch_revisions {
						fixture.session.faults.source_batch_revisions_allocation_hook = registration_allocation_probe;
						fixture.session.faults.source_batch_revisions_allocation_data = *probe;
					} else if batch_states {
						fixture.session.faults.source_batch_state_allocation_hook = registration_allocation_probe;
						fixture.session.faults.source_batch_state_allocation_data = *probe;
					} else if pool {
						fixture.session.faults.source_batch_pool_allocation_hook = registration_allocation_probe;
						fixture.session.faults.source_batch_pool_allocation_data = *probe;
					} else if revisions {
						fixture.session.faults.source_provider_revisions_allocation_hook = registration_allocation_probe;
						fixture.session.faults.source_provider_revisions_allocation_data = *probe;
					} else if states {
						fixture.session.faults.source_provider_states_allocation_hook = registration_allocation_probe;
						fixture.session.faults.source_provider_states_allocation_data = *probe;
					} else if arrays {
						fixture.session.faults.source_provider_arrays_allocation_hook = registration_allocation_probe;
						fixture.session.faults.source_provider_arrays_allocation_data = *probe;
					} else if provider {
						fixture.session.faults.source_provider_allocation_hook = registration_allocation_probe;
						fixture.session.faults.source_provider_allocation_data = *probe;
					} else if list {
						fixture.session.operations.allocated = operations;
						fixture.session.faults.source_operation_allocation_hook = registration_allocation_probe;
						fixture.session.faults.source_operation_allocation_data = *probe;
					} else if update {
						fixture.session.faults.source_update_allocation_hook = registration_allocation_probe;
						fixture.session.faults.source_update_allocation_data = *probe;
					} else {
						fixture.session.faults.registration_allocation_hook = registration_allocation_probe;
						fixture.session.faults.registration_allocation_data = *probe;
					}
				}
			);

			ok, accepted, error := Service.submit_source_batch(
				fixture.host.service,
				fixture.host.session,
				receipt_source_batch(batch)
				,, allocator
			);

			assert(probe.allocations == min(fail_at, allocation_count));
			Service.with_lock(
				*fixture.session.gate,
				#code {
					fixture.session.faults.registration_allocation_hook = null;
					fixture.session.faults.registration_allocation_data = null;
					fixture.session.faults.source_update_allocation_hook = null;
					fixture.session.faults.source_update_allocation_data = null;
					fixture.session.faults.source_operation_allocation_hook = null;
					fixture.session.faults.source_operation_allocation_data = null;
					fixture.session.faults.source_provider_allocation_hook = null;
					fixture.session.faults.source_provider_allocation_data = null;
					fixture.session.faults.source_provider_arrays_allocation_hook = null;
					fixture.session.faults.source_provider_arrays_allocation_data = null;
					fixture.session.faults.source_provider_states_allocation_hook = null;
					fixture.session.faults.source_provider_states_allocation_data = null;
					fixture.session.faults.source_provider_revisions_allocation_hook = null;
					fixture.session.faults.source_provider_revisions_allocation_data = null;
					fixture.session.faults.source_batch_pool_allocation_hook = null;
					fixture.session.faults.source_batch_pool_allocation_data = null;
					fixture.session.faults.source_batch_state_allocation_hook = null;
					fixture.session.faults.source_batch_state_allocation_data = null;
					fixture.session.faults.source_batch_revisions_allocation_hook = null;
					fixture.session.faults.source_batch_revisions_allocation_data = null;
					fixture.session.faults.source_batch_source_allocation_hook = null;
					fixture.session.faults.source_batch_source_allocation_data = null;
					fixture.session.faults.source_batch_source_bytes_allocation_hook = null;
					fixture.session.faults.source_batch_source_bytes_allocation_data = null;
					fixture.session.faults.source_batch_source_identity_allocation_hook = null;
					fixture.session.faults.source_batch_source_identity_allocation_data = null;
					fixture.session.faults.source_batch_edit_allocation_hook = null;
					fixture.session.faults.source_batch_edit_allocation_data = null;
					fixture.session.faults.source_batch_state_list_allocation_hook = null;
					fixture.session.faults.source_batch_state_list_allocation_data = null;
					fixture.session.faults.source_batch_reference_list_allocation_hook = null;
					fixture.session.faults.source_batch_reference_list_allocation_data = null;
					fixture.session.faults.source_batch_context_list_allocation_hook = null;
					fixture.session.faults.source_batch_context_list_allocation_data = null;
					fixture.session.faults.source_batch_path_allocation_hook = null;
					fixture.session.faults.source_batch_path_allocation_data = null;
					assert(!fixture.session.active_admissions);
					if fail_at <= allocation_count || path_error {
						assert(!ok && !accepted.ticket.owner_token && !accepted.frontier.count);
						if fail_at <= allocation_count {
							assert(error.code == .ADMISSION_DENIED && error.admission.kind == .RESOURCE_EXHAUSTED);
							assert(!error.path.count && !output_probe.allocations);
						} else {
							assert(error.code == .INVALID_ARGUMENT && error.rule == .INCONSISTENT_BINDING && output_probe.allocations == 1);
							assert(error.path.count == 4);
							assert(error.path[0].kind == .FIELD && error.path[0].name == "events");
							assert(error.path[1].kind == .ELEMENT && !error.path[1].index);
							assert(error.path[2].kind == .FIELD && error.path[2].name == "disk");
							assert(error.path[3].kind == .FIELD && error.path[3].name == "context");
						}

						assert(Service.bytes_equal(fixture.session.provider.accepted_frontier, batch.description.accepted_frontier));
						assert(fixture.session.provider.documents.count == documents);
						assert(Service.selected_document(Service.find_document(fixture.session.provider, batch.events[0].document)).source == source);
						assert(source.references == source_references);
						assert(fixture.session.operations.count == operations && fixture.session.registry.slots.count == slots.count && fixture.session.registry.free_slots.count == free_count);
						for slots {
							current := fixture.session.registry.slots[it_index];
							assert(current.generation == it.generation && current.kind == it.kind && current.live == it.live && current.retired == it.retired);
						}

						for before.live {
							assert(fixture.session.ledger.live[it_index] == it && fixture.session.ledger.reserved[it_index] == before.reserved[it_index]);
						}

						assert(fixture.session.identities.operation_counter.next == identities.operation_counter.next);
						assert(fixture.session.identities.world_counter.next == identities.world_counter.next);
					} else {
						assert(ok && accepted.ticket.owner_token && output_probe.allocations == 1);
						assert(Service.handle_is_live(*fixture.session.registry, accepted.ticket));
						assert(Service.bytes_equal(fixture.session.provider.accepted_frontier, accepted.frontier));
						if event_kind == .OBSERVE_DISK {
							state := Service.find_document(fixture.session.provider, batch.events[0].document);
							assert(state.disk.source && Service.bytes_equal(state.disk.source.bytes, xx submitted));
						}

						if batch_pair {
							assert(fixture.session.provider.documents.count == documents + 1);
							added := Service.find_document(fixture.session.provider, batch.events[1].document);
							assert(!!added);
							assert(Service.bytes_equal(Service.selected_document(added).source.bytes, xx "second :: 2;"));
						}

						assert(fixture.session.ledger.live[Service.Limit_Name.LIVE_HANDLES] == before.live[Service.Limit_Name.LIVE_HANDLES] + 1);
						if scenario == .REUSE {
							assert(accepted.ticket.slot < xx slots.count && accepted.ticket.generation == slots[accepted.ticket.slot].generation + 1);
						} else {
							assert(accepted.ticket.slot == xx slots.count && accepted.ticket.generation == 1);
						}
					}

					assert(fixture.session.identities.result_counter.next == identities.result_counter.next);
				}
			);

			if ok {
				polled, receipt := Service.poll(fixture.host.service, accepted.ticket);
				assert(polled);
				token_bytes := Service.little_endian(identities.operation_counter.next, 8);
				expected_identity := Service.make_key("operation", fixture.host.session_identity.([] u8), token_bytes);
				assert(Service.bytes_equal(receipt.operation_identity.([] u8), expected_identity));
				free(token_bytes.data);
				free(expected_identity.data);
				Service.free_observation(*receipt);

				observation := await(fixture, accepted.ticket);
				assert(observation.update.kind == .PUBLISHED);
				Service.free_observation(*observation);
				acquired := world_of(fixture, accepted.ticket);
				world_ok, description := Service.read_world(fixture.host.service, acquired);
				assert(world_ok && Service.bytes_equal(description.members[0].source.bytes, xx expected_world));
				release(fixture, acquired);
				release(fixture, accepted.ticket);
			}

			free(accepted.frontier.data,, allocator);
			free(error.path.data,, allocator);
			close_output_probe(*output_probe);
			free(disk_revision.data);
			free(slots.data);
			finish_retain(test);
		}
	}

	print(
		"X5 source ticket/update/list/provider backing array/object/reuse failures/provider commit/charges/generations/canonical identities (update = %, list = %, provider = %, arrays = %, states = %, revisions = %, pool = %, batch states = %, batch revisions = %, batch pair = %, batch sources = %, batch source bytes = %, batch source identities = %, batch edits = %, batch state list = %, batch reference list = %, batch context list = %, batch paths = %, path error = %, edit pair = %, empty source = %, event = %) \e[92mPASS\e[0m\n",
		update,
		list,
		provider,
		arrays,
		states,
		revisions,
		pool,
		batch_states,
		batch_revisions,
		batch_pair,
		batch_sources,
		batch_source_bytes,
		batch_source_identities,
		batch_edits,
		batch_state_list,
		batch_reference_list,
		batch_context_list,
		batch_paths,
		path_error,
		edit_pair,
		empty_source,
		event_kind
	);
}

test_source_batch_source_event_failures :: () {
	for Service.Event_Kind.[.EDIT_OVERLAY, .OBSERVE_DISK] {
		test_source_registration_failures(batch_sources = true, event_kind = it);
		test_source_registration_failures(batch_source_bytes = true, event_kind = it);
		test_source_registration_failures(batch_source_identities = true, event_kind = it);
	}

	print("X5 checked source construction edit/disk rejection routes \e[92mPASS\e[0m\n");
}

test_source_batch_edit_failures :: () {
	maximum :: 0x7FFFFFFFFFFFFFFF;
	ok, size := Service.try_source_edit_size(maximum, 1, 1, maximum);
	assert(ok && size == maximum);
	ok, size = Service.try_source_edit_size(maximum, 0, 1, maximum);
	assert(!ok && !size);
	ok, size = Service.try_source_edit_size(12, 12, 0, 0);
	assert(ok && !size);
	ok, size = Service.try_source_edit_size(12, 3, 5, 14);
	assert(ok && size == 14);
	ok, size = Service.try_source_edit_size(12, 3, 5, 13);
	assert(!ok && !size);
	ok, size = Service.try_source_edit_size(12, 12, maximum, 12);
	assert(!ok && !size);
	ok, size = Service.try_source_edit_size(12, 13, 0, maximum);
	assert(!ok && !size);
	ok, size = Service.try_source_edit_size(12, 0, -1, maximum);
	assert(!ok && !size);

	test_source_registration_failures(batch_edits = true, event_kind = .EDIT_OVERLAY);
	test_source_registration_failures(batch_edits = true, edit_pair = true, event_kind = .EDIT_OVERLAY);
	test_source_registration_failures(batch_edits = true, empty_source = true, event_kind = .EDIT_OVERLAY);
	print("X5 checked edit intermediate backing/size limits/overflow/empty result \e[92mPASS\e[0m\n");
}

test_source_batch_reference_storage :: () {
	probe := Output_Probe.{fail_at = 1};
	allocator := open_output_probe(*probe);
	maximum :: 0x7FFFFFFFFFFFFFFF;
	for s64.[-1, maximum, maximum / 2 + 1, maximum / 2] {
		ok, storage := Service.try_source_batch_references(it, allocator);
		assert(!ok && !storage.count && !storage.allocated && !probe.allocations);
	}

	empty_ok, empty := Service.try_source_batch_references(0, allocator);
	assert(empty_ok && !empty.count && !empty.allocated && !probe.allocations);
	array_free(empty);
	rejected, rejected_storage := Service.try_source_batch_references(1, allocator);
	assert(!rejected && !rejected_storage.count && !rejected_storage.allocated && probe.allocations == 1);
	probe.fail_at = 0;
	ok, storage := Service.try_source_batch_references(2, allocator);
	assert(ok && !storage.count && storage.allocated == 4 && probe.allocations == 2);
	for 0..3 {
		array_add(*storage, "known-context".([] u8));
	}

	assert(storage.count == 4 && probe.allocations == 2);
	array_free(storage);
	close_output_probe(*probe);
	test_source_registration_failures(batch_reference_list = true);
	test_source_registration_failures(batch_reference_list = true, batch_pair = true);
	test_source_registration_failures(batch_reference_list = true, event_kind = .OBSERVE_DISK);
	print("X5 checked batch context-reference capacity/overflow/rejection/disk capacity \e[92mPASS\e[0m\n");
}

test_source_batch_pool_defaults :: () {
	probe := Output_Probe.{fail_at = 1};
	allocator := open_output_probe(*probe);
	rejected := Service.try_source_batch_pool(allocator);
	assert(!rejected && probe.allocations == 1 && !probe.backing.live_bytes);
	probe.fail_at = 0;
	storage := Service.try_source_batch_pool(allocator);
	assert(storage && probe.allocations == 2);
	defaults: type_of(storage.*);
	assert(storage.memblock_size == defaults.memblock_size);
	assert(storage.oversized_size == defaults.oversized_size);
	assert(storage.alignment == defaults.alignment);
	assert(!storage.current_memblock && !storage.block_allocator.proc);
	free(storage,, allocator);
	close_output_probe(*probe);
	print("X5 checked batch Pool object/defaults/rejection/cleanup \e[92mPASS\e[0m\n");
}

test_source_batch_revision_storage :: () {
	probe := Output_Probe.{fail_at = 1};
	allocator := open_output_probe(*probe);
	ok, revisions := Service.try_source_batch_revisions(null, allocator);
	assert(!ok && !revisions.data && !probe.backing.live_bytes);
	probe.fail_at = 0;
	ok, revisions = Service.try_source_batch_revisions(null, allocator);
	assert(ok && !revisions.count && revisions.allocated == 1);
	array_add(*revisions, xx "first");
	assert(probe.allocations == 2);
	array_free(revisions);
	state: Service.Document_State;
	array_add(*state.used_revisions, xx "first");
	array_add(*state.used_revisions, xx "second");
	previous := state.used_revisions;
	probe.fail_at = 3;
	ok, revisions = Service.try_source_batch_revisions(*state, allocator);
	assert(!ok && !revisions.data && state.used_revisions.data == previous.data && state.used_revisions.count == previous.count);
	probe.fail_at = 0;
	ok, revisions = Service.try_source_batch_revisions(*state, allocator);
	assert(ok && revisions.count == previous.count && revisions.allocated == previous.count + 1 && revisions.data != previous.data);
	for previous {
		assert(revisions[it_index].data == it.data && revisions[it_index].count == it.count);
	}

	array_add(*revisions, xx "third");
	assert(probe.allocations == 4 && state.used_revisions.count == previous.count);
	array_free(revisions);
	array_free(state.used_revisions);
	MAX_COUNT :: 0x7FFFFFFFFFFFFFFF;
	overflow: Service.Document_State;
	overflow.used_revisions.count = MAX_COUNT;
	ok, revisions = Service.try_source_batch_revisions(*overflow, allocator);
	assert(!ok && !revisions.data && probe.allocations == 4);
	overflow.used_revisions.count = MAX_COUNT / size_of([] u8);
	ok, revisions = Service.try_source_batch_revisions(*overflow, allocator);
	assert(!ok && !revisions.data && probe.allocations == 4);
	close_output_probe(*probe);
	print("X5 checked batch revision storage/empty/copy/rejection/allocation-free append \e[92mPASS\e[0m\n");
}

test_source_batch_storage_growth :: () {
	model: Service.Provider_Model;
	sentinel: Pool;
	probe := Output_Probe.{fail_at = 1};
	allocator := open_output_probe(*probe);
	assert(!Service.try_source_batch_storage(*model, allocator));
	assert(!model.batch_storage.data && !model.batch_storage.count && !model.batch_storage.allocated);
	probe.fail_at = 0;
	assert(Service.try_source_batch_storage(*model, allocator));
	capacity := model.batch_storage.allocated;
	for 0..capacity - 1 {
		array_add(*model.batch_storage, *sentinel);
	}

	previous := model.batch_storage;
	probe.fail_at = 3;
	assert(!Service.try_source_batch_storage(*model, allocator));
	assert(model.batch_storage.data == previous.data && model.batch_storage.count == capacity && model.batch_storage.allocated == capacity);
	assert(model.batch_storage[capacity - 1] == *sentinel);
	probe.fail_at = 0;
	assert(Service.try_source_batch_storage(*model, allocator));
	assert(model.batch_storage.count == capacity && model.batch_storage.allocated > capacity && probe.allocations == 4);
	for model.batch_storage {
		assert(it == *sentinel);
	}

	assert(Service.try_source_batch_storage(*model, allocator) && probe.allocations == 4);
	array_free(model.batch_storage);
	close_output_probe(*probe);
	print("X5 checked batch pool-list empty/full growth/rejection/pointer preservation/retry \e[92mPASS\e[0m\n");
}

test_source_batch_storage_admission :: (
	direct := false,
	replace := false,
	negative_control := false,
	shutdown := false,
	receipt_retry := false,
	list := false,
	retry_rejection := false,
	retire := false,
	batch_states := false,
	batch_revisions := false,
	shutdown_guard := false
) {
	construction := batch_states || batch_revisions;
	allocations_per_attempt := ifx construction then 1 else 2;
	assert(!batch_states || !batch_revisions);
	assert(!shutdown_guard || shutdown);
	assert(!negative_control || replace || shutdown || retire);
	assert(!shutdown || !replace);
	assert(!retire || !replace && !shutdown && !receipt_retry && !retry_rejection);
	assert(!list || receipt_retry);
	assert(!receipt_retry || !replace && !shutdown);
	assert(!retry_rejection || !replace && !shutdown);
	for 0..(ifx receipt_retry then allocations_per_attempt * 2 + 1 else allocations_per_attempt + 1) {
		fail_at := it;
		if (
			replace && fail_at && (!construction || negative_control)
			|| (shutdown || retire) && fail_at < allocations_per_attempt && fail_at
		) {
			continue;
		}


		if shutdown && negative_control && fail_at != allocations_per_attempt {
			continue;
		}


		if retry_rejection && (fail_at < (ifx receipt_retry then allocations_per_attempt + 1 else 1) || fail_at > (ifx receipt_retry then allocations_per_attempt * 2 else allocations_per_attempt)) {
			continue;
		}


		test := prepared_retain(.WORLD, .ARRAYS);
		fixture := test.drain.fixture;
		while !construction {
			full: bool;
			count: s64;
			Service.with_lock(
				*fixture.session.gate,
				#code {
					count = fixture.session.provider.batch_storage.count;
					full = count == fixture.session.provider.batch_storage.allocated;
				}
			);

			if full {
				break;
			}


			ticket := submit(fixture, tprint("answer :: %;", 100 + count));
			observation := await(fixture, ticket);
			assert(observation.update.kind == .PUBLISHED);
			Service.free_observation(*observation);
			release(fixture, ticket);
		}

		batch := Service.begin_batch(fixture.host);
		assert(Service.set_overlay(*batch, "a.jai", "answer :: 77;"));
		probe := Registration_Probe.{
			fail_at = fail_at,
			job_at = allocations_per_attempt,
			direct = direct,
			track_source = replace || shutdown || retire,
			job = .{
				drain = test.drain,
				action = ifx replace
					then .REPLACE_SOURCE
					else ifx shutdown
						then ifx shutdown_guard
							then .CHECK_STAGING_SHUTDOWN
							else .REQUEST_SHUTDOWN
						else ifx retire
							then .RETIRE_AND_REUSE_SESSION
							else .NONE,
				active_source_retirement = retire,
			},
		};

		output_probe := Output_Probe.{
			direct = direct,
			job = .{
				drain = test.drain,
				action = ifx receipt_retry
					then ifx list
						then .FILL_OPERATION_CAPACITY
						else .FILL_REGISTRATION_CAPACITY
					else .NONE,
			},
		};

		allocator := open_output_probe(*output_probe);
		before: Service.Resource_Ledger;
		storage: [..] *Pool;
		identities: Service.Session_Identities;
		Service.with_lock(
			*fixture.session.gate,
			#code {
				before = fixture.session.ledger;
				storage = fixture.session.provider.batch_storage;
				identities = fixture.session.identities;
				if batch_revisions {
					fixture.session.faults.source_batch_revisions_allocation_hook = registration_allocation_probe;
					fixture.session.faults.source_batch_revisions_allocation_data = *probe;
				} else if batch_states {
					fixture.session.faults.source_batch_state_allocation_hook = registration_allocation_probe;
					fixture.session.faults.source_batch_state_allocation_data = *probe;
				} else {
					fixture.session.faults.source_batch_storage_allocation_hook = registration_allocation_probe;
					fixture.session.faults.source_batch_storage_allocation_data = *probe;
				}

				fixture.session.faults.allow_stale_source_batch_storage = negative_control && replace;
				fixture.session.faults.retry_failed_source_batch_storage = retry_rejection;
				fixture.session.faults.prefer_failed_source_batch_storage = negative_control && shutdown;
				fixture.session.faults.allow_active_session_release = retire;
				fixture.session.faults.allow_stale_source_batch_pool = negative_control && retire;
			}
		);

		ok, accepted, error := Service.submit_source_batch(
			fixture.host.service,
			fixture.host.session,
			receipt_source_batch(batch)
			,, allocator
		);

		allocation_count := allocations_per_attempt * (ifx receipt_retry then 2 else 1);
		expected_success := (!replace && !shutdown && !retire && (!fail_at || fail_at > allocation_count)) || negative_control && replace || retry_rejection;
		assert(ok == expected_success, "\e[91mBatch pool-list allocation/revalidation oracle failed.\e[0m");
		expected_allocations := ifx retry_rejection
			then fail_at + allocations_per_attempt
			else ifx fail_at && fail_at <= allocation_count
				then fail_at
				else allocation_count;
		assert(probe.allocations == expected_allocations);
		if receipt_retry && (!fail_at || fail_at > allocations_per_attempt) {
			assert(output_probe.gate_progress && output_probe.job.ok);
			assert(output_probe.allocations == (ifx ok then 2 else 1));
		}

		if replace || shutdown || retire {
			assert(probe.gate_progress && probe.job.ok && probe.source_active_admissions == 1);
		}

		Service.with_lock(
			*fixture.session.gate,
			#code {
				fixture.session.faults.source_batch_storage_allocation_hook = null;
				fixture.session.faults.source_batch_storage_allocation_data = null;
				fixture.session.faults.source_batch_state_allocation_hook = null;
				fixture.session.faults.source_batch_state_allocation_data = null;
				fixture.session.faults.source_batch_revisions_allocation_hook = null;
				fixture.session.faults.source_batch_revisions_allocation_data = null;
				fixture.session.faults.allow_stale_source_batch_storage = false;
				fixture.session.faults.retry_failed_source_batch_storage = false;
				fixture.session.faults.prefer_failed_source_batch_storage = false;
				fixture.session.faults.allow_active_session_release = false;
				fixture.session.faults.allow_stale_source_batch_pool = false;
				assert(!fixture.session.active_admissions);
				assert(
					fixture.session.ledger.live[Service.Limit_Name.LIVE_HANDLES]
					== before.live[Service.Limit_Name.LIVE_HANDLES] + output_probe.job.competing_worlds.count + output_probe.job.competing_tickets.count + xx ok + xx retire
				);
				assert(fixture.session.ledger.live[Service.Limit_Name.CONCURRENT_ACQUISITIONS] == before.live[Service.Limit_Name.CONCURRENT_ACQUISITIONS]);
				if !ok && !replace {
					assert(fixture.session.provider.batch_storage.data == storage.data && fixture.session.provider.batch_storage.count == storage.count);
					assert(Service.bytes_equal(fixture.session.provider.accepted_frontier, batch.description.accepted_frontier));
					assert(fixture.session.identities.operation_counter.next == identities.operation_counter.next + xx (shutdown || retire) + xx output_probe.job.competing_tickets.count);
					if !shutdown && !retire {
						assert(fixture.session.ledger.live[Service.Limit_Name.IN_FLIGHT_OPERATIONS] == before.live[Service.Limit_Name.IN_FLIGHT_OPERATIONS]);
					}
				}

				if replace {
					state := Service.find_document(fixture.session.provider, Service.harness_document(fixture.host, "a.jai"));
					assert(state && state.has_overlay && Service.bytes_equal(state.overlay.source.bytes, xx (ifx negative_control then "answer :: 77;" else "answer :: 99;")));
				}
			}
		);

		if ok {
			observation := await(fixture, accepted.ticket);
			assert(observation.update.kind == .PUBLISHED);
			Service.free_observation(*observation);
			world := world_of(fixture, accepted.ticket);
			read_ok, description := Service.read_world(fixture.host.service, world);
			assert(read_ok && description.members.count == 1 && Service.bytes_equal(description.members[0].source.bytes, xx "answer :: 77;"));
			release(fixture, world);
			release(fixture, accepted.ticket);
		} else {
			assert(!accepted.ticket.owner_token && !accepted.frontier.count);
			if retire {
				if negative_control {
					assert(error.code == .SERVICE_CLOSED, "\e[91mTransfer stale-session control was not detected.\e[0m");
				} else {
					assert(error.code == .INVALID_HANDLE && error.handle_kind == .SESSION);
				}
			} else if shutdown {
				if negative_control {
					assert(error.code == .ADMISSION_DENIED && error.admission.kind == .RESOURCE_EXHAUSTED, "\e[91mTransfer shutdown precedence control was not detected.\e[0m");
				} else {
					assert(error.code == .SERVICE_CLOSED);
				}
			} else if replace {
				assert(error.code == .BASE_MISMATCH && error.scope == .FRONTIER);
			} else {
				assert(error.code == .ADMISSION_DENIED && error.admission.kind == .RESOURCE_EXHAUSTED);
			}
		}

		assert(Service.read_world(fixture.host.service, test.drain.world));
		if retire {
			observation := await(fixture, probe.job.coordinator_shutdown);
			assert(observation.kind == .SHUTDOWN);
			Service.free_observation(*observation);
			release(fixture, probe.job.coordinator_shutdown);
			assert(Service.read_world(fixture.host.service, probe.job.replacement_world));
			release(fixture, probe.job.replacement_world);
		}

		for output_probe.job.competing_worlds {
			assert(Service.read_world(fixture.host.service, it));
			release(fixture, it);
		}

		array_free(output_probe.job.competing_worlds);
		for output_probe.job.competing_tickets {
			release(fixture, it);
		}

		array_free(output_probe.job.competing_tickets);
		free(accepted.frontier.data,, allocator);
		free(error.path.data,, allocator);
		free(error.document.data,, allocator);
		close_output_probe(*output_probe);
		if retire {
			for test.held {
				release(fixture, it);
			}

			array_free(test.held);
			release(fixture, test.source);
			finish_drain(test.drain, session_released = true);
		} else {
			finish_retain(test);
		}
	}

	print(
		"X5 checked batch transfer/construction allocation rejection/frontier reentry (direct = %, replace = %, negative control = %, shutdown = %, receipt retry = %, list = %, rejection control = %, retire = %, batch states = %, batch revisions = %, shutdown guard = %) \e[92mPASS\e[0m\n",
		direct,
		replace,
		negative_control,
		shutdown,
		receipt_retry,
		list,
		retry_rejection,
		retire,
		batch_states,
		batch_revisions,
		shutdown_guard
	);
}

test_source_batch_construction_reference_rollback :: () {
	for bool.[false, true] {
		revisions := it;
		for bool.[false, true] {
			direct := it;
			for bool.[false, true] {
				reference_control := it;
				for 0..2 {
					test_source_registration_receipt_retry(
						direct = direct,
						list = it == 1,
						reject_receipt = it == 2,
						reference_control = reference_control,
						batch_states = !revisions,
						batch_revisions = revisions
					);
				}
			}
		}
	}

	print("X5 state/revision retained-sentinel source-reference rollback/controls \e[92mPASS\e[0m\n");
}

test_source_batch_construction_receipt_retry :: (revisions := false) {
	test_source_batch_storage_admission(
		retry_rejection = true,
		batch_states = !revisions,
		batch_revisions = revisions
	);

	for bool.[false, true] {
		direct := it;
		for bool.[false, true] {
			list := it;
			for bool.[false, true] {
				test_source_batch_storage_admission(
					direct = direct,
					receipt_retry = true,
					list = list,
					retry_rejection = it,
					batch_states = !revisions,
					batch_revisions = revisions
				);
			}
		}
	}
}

test_source_batch_construction_callbacks :: (revisions := false) {
	for bool.[false, true] {
		direct := it;
		for Output_Action.[.REPLACE_SOURCE, .REQUEST_SHUTDOWN, .CHECK_STAGING_SHUTDOWN, .RETIRE_AND_REUSE_SESSION] {
			action := it;
			for bool.[false, true] {
				test_source_batch_storage_admission(
					direct = direct,
					replace = action == .REPLACE_SOURCE,
					shutdown = action == .REQUEST_SHUTDOWN || action == .CHECK_STAGING_SHUTDOWN,
					retire = action == .RETIRE_AND_REUSE_SESSION,
					negative_control = it,
					batch_states = !revisions,
					batch_revisions = revisions,
					shutdown_guard = action == .CHECK_STAGING_SHUTDOWN
				);
			}
		}
	}
}

Pool_Cleanup_Probe :: struct {
	fixture: Fixture;
	world: Service.Handle(.WORLD);
	memory: *void;
	allocation_pending: bool;
	allocation_size: s64 = size_of(Pool);
	capture_at: s64;
	allocations: s64;
	callbacks: s64;
	frees: s64;
	direct: bool;
	suppress_callback: bool;
	gate_progress: bool;
	readable: bool;
	allocate: bool;
	allocated: bool;
	mutate: bool;
	mutated: bool;
	hold_heap_gate: bool;
	heap_blocked: bool;
	heap_entered: Semaphore;
	active_admissions: s64;
	ledger: Service.Resource_Ledger;
	job: Output_Interleaving;
}

Storage_Cleanup_Case :: enum {
	PRIVATE_LIST;
	DISCARDED_TRANSFER;
	REPLACED_LIST;
}

storage_cleanup_allocation_probe :: (size: s64, data: *void) -> bool {
	probe := data.(*Pool_Cleanup_Probe);
	Service.with_lock(
		*allocation_ledger.gate,
		#code {
			probe.allocations += 1;
			if probe.allocations == probe.capture_at {
				assert(!allocation_ledger.pool_cleanup && !probe.memory);
				probe.allocation_size = size;
				probe.allocation_pending = true;
				allocation_ledger.pool_cleanup = probe;
			}
		}
	);

	return true;
}

test_source_batch_storage_cleanup :: (
	direct := false,
	negative_control := false,
	action: Output_Action = .NONE
) {
	assert(action == .NONE || action == .CHECK_STAGING_SHUTDOWN || action == .RETIRE_AND_REUSE_SESSION);
	active_lifecycle := action != .NONE && !negative_control;
	retired := active_lifecycle && action == .RETIRE_AND_REUSE_SESSION;
	for Storage_Cleanup_Case.[.PRIVATE_LIST, .DISCARDED_TRANSFER, .REPLACED_LIST] {
		scenario := it;
		test := prepared_retain(.WORLD, .ARRAYS);
		fixture := test.drain.fixture;
		while true {
			full: bool;
			count: s64;
			Service.with_lock(
				*fixture.session.gate,
				#code {
					count = fixture.session.provider.batch_storage.count;
					full = count == fixture.session.provider.batch_storage.allocated;
				}
			);

			if full {
				break;
			}


			ticket := submit(fixture, tprint("answer :: %;", 100 + count));
			observation := await(fixture, ticket);
			assert(observation.update.kind == .PUBLISHED);
			Service.free_observation(*observation);
			release(fixture, ticket);
		}

		batch := Service.begin_batch(fixture.host);
		assert(Service.set_overlay(*batch, "a.jai", "answer :: 77;"));
		probe := Pool_Cleanup_Probe.{
			fixture = fixture,
			world = test.drain.world,
			direct = direct,
			suppress_callback = negative_control,
			allocate = true,
			mutate = true,
			capture_at = ifx scenario == .PRIVATE_LIST
				then 1
				else ifx scenario == .DISCARDED_TRANSFER
					then 2
					else 0,
			job = .{
				drain = test.drain,
				action = action,
				active_source_retirement = retired,
			},
		};

		if scenario == .REPLACED_LIST {
			Service.with_lock(
				*fixture.session.gate,
				#code {
					probe.memory = fixture.session.provider.batch_storage.data.(*u8) - size_of(Service.Owned_Allocation);
				}
			);

			Service.with_lock(
				*allocation_ledger.gate,
				#code {
					assert(!allocation_ledger.pool_cleanup && table_contains(*allocation_ledger.sizes, probe.memory));
					allocation_ledger.pool_cleanup = *probe;
				}
			);
		}

		output_probe := Output_Probe.{fail_at = ifx scenario == .DISCARDED_TRANSFER then 1 else 0};
		allocator := open_output_probe(*output_probe);
		before: Service.Resource_Ledger;
		Service.with_lock(
			*fixture.session.gate,
			#code {
				before = fixture.session.ledger;
				fixture.session.faults.source_batch_storage_allocation_hook = storage_cleanup_allocation_probe;
				fixture.session.faults.source_batch_storage_allocation_data = *probe;
				fixture.session.faults.allow_active_session_release = retired;
			}
		);

		ok, accepted, error := Service.submit_source_batch(
			fixture.host.service,
			fixture.host.session,
			receipt_source_batch(batch)
			,, allocator
		);

		assert(ok == (scenario != .DISCARDED_TRANSFER));
		assert(probe.allocations == 2 && probe.memory && !probe.allocation_pending);
		assert(probe.job.ok == active_lifecycle);
		if negative_control {
			assert(!probe.callbacks && !probe.gate_progress && !probe.allocated && !probe.mutated);
		} else {
			assert(probe.callbacks == 1 && probe.gate_progress && probe.readable && probe.allocated && probe.mutated);
			assert(probe.active_admissions == 1);
			assert(probe.ledger.live[Service.Limit_Name.LIVE_HANDLES] == before.live[Service.Limit_Name.LIVE_HANDLES] + xx ok);
			assert(probe.ledger.live[Service.Limit_Name.CONCURRENT_ACQUISITIONS] == before.live[Service.Limit_Name.CONCURRENT_ACQUISITIONS] + 1);
		}

		Service.with_lock(
			*allocation_ledger.gate,
			#code {
				assert(probe.frees == 1 && !allocation_ledger.pool_cleanup);
			}
		);

		Service.with_lock(
			*fixture.session.gate,
			#code {
				fixture.session.faults.source_batch_storage_allocation_hook = null;
				fixture.session.faults.source_batch_storage_allocation_data = null;
				fixture.session.faults.allow_active_session_release = false;
				assert(!fixture.session.active_admissions);
				assert(fixture.session.ledger.live[Service.Limit_Name.LIVE_HANDLES] == before.live[Service.Limit_Name.LIVE_HANDLES] + xx ok + xx retired);
				assert(fixture.session.ledger.live[Service.Limit_Name.CONCURRENT_ACQUISITIONS] == before.live[Service.Limit_Name.CONCURRENT_ACQUISITIONS]);
				if active_lifecycle {
					assert(fixture.session.lifecycle != .OPEN);
				}

				if !ok {
					assert(Service.bytes_equal(fixture.session.provider.accepted_frontier, batch.description.accepted_frontier));
					if !active_lifecycle {
						assert(fixture.session.ledger.live[Service.Limit_Name.IN_FLIGHT_OPERATIONS] == before.live[Service.Limit_Name.IN_FLIGHT_OPERATIONS]);
					}
				}
			}
		);

		if ok {
			observation := await(fixture, accepted.ticket);
			assert(observation.update.kind == .PUBLISHED || active_lifecycle && observation.update.kind == .CANCELLED && observation.update.cancellation == .SHUTDOWN);
			if observation.update.kind == .PUBLISHED {
				world := world_of(fixture, accepted.ticket);
				read_ok, description := Service.read_world(fixture.host.service, world);
				assert(read_ok && description.members.count == 1 && Service.bytes_equal(description.members[0].source.bytes, xx "answer :: 77;"));
				release(fixture, world);
			}

			Service.free_observation(*observation);
			release(fixture, accepted.ticket);
		} else {
			assert(!accepted.ticket.owner_token && !accepted.frontier.count && error.code == .ADMISSION_DENIED && error.admission.kind == .RESOURCE_EXHAUSTED);
		}

		assert(Service.read_world(fixture.host.service, test.drain.world));
		if retired {
			observation := await(fixture, probe.job.coordinator_shutdown);
			assert(observation.kind == .SHUTDOWN);
			Service.free_observation(*observation);
			release(fixture, probe.job.coordinator_shutdown);
			assert(Service.read_world(fixture.host.service, probe.job.replacement_world));
			release(fixture, probe.job.replacement_world);
		}

		free(accepted.frontier.data,, allocator);
		free(error.path.data,, allocator);
		free(error.document.data,, allocator);
		close_output_probe(*output_probe);
		if retired {
			for test.held {
				release(fixture, it);
			}

			array_free(test.held);
			release(fixture, test.source);
			finish_drain(test.drain, session_released = true);
		} else {
			finish_retain(test);
		}
	}

	print(
		"X5 actual transfer-list private/discard/replacement frees/allocating reentry (direct = %, negative control = %, action = %) \e[92mPASS\e[0m\n",
		direct,
		negative_control,
		action
	);
}

pool_cleanup_allocation_probe :: (size: s64, data: *void) -> bool {
	probe := data.(*Pool_Cleanup_Probe);
	assert(size == size_of(Pool));
	Service.with_lock(
		*allocation_ledger.gate,
		#code {
			probe.allocations += 1;
			if !probe.memory {
				assert(!allocation_ledger.pool_cleanup);
				probe.allocation_pending = true;
				allocation_ledger.pool_cleanup = probe;
			}
		}
	);

	return true;
}

pool_cleanup_job :: (thread: *Thread) -> s64 {
	probe := thread.data.(*Pool_Cleanup_Probe);
	Service.with_lock(
		*probe.fixture.session.gate,
		#code {
			probe.active_admissions = probe.fixture.session.active_admissions;
			probe.ledger = probe.fixture.session.ledger;
		}
	);

	probe.readable = Service.read_world(probe.fixture.host.service, probe.world);
	if probe.hold_heap_gate {
		signal(*probe.heap_entered);
	}

	if probe.allocate {
		allocator := Service.owner_allocator(probe.fixture.session);
		storage := Service.try_source_batch_pool(allocator);
		assert(!!storage);
		free(storage,, allocator);
		probe.allocated = true;
	}

	if probe.mutate {
		retained, handle := Service.retain(probe.fixture.host.service, probe.world);
		assert(retained);
		probe.mutated = Service.release(probe.fixture.host.service, handle);
		assert(probe.mutated);
	}

	if probe.job.action != .NONE {
		job_thread := Thread.{data = *probe.job};
		output_interleaving_job(*job_thread);
	}

	probe.callbacks += 1;
	return 0;
}

test_source_batch_pool_cleanup :: (
	direct := false,
	retry := false,
	negative_control := false,
	list := false,
	validation := false,
	allocate := false,
	mutate := false,
	hold_heap_gate := false,
	batch_states := false,
	batch_revisions := false,
	new_document := false,
	action: Output_Action = .NONE
) {
	assert(action == .NONE || (batch_states || batch_revisions) && (action == .CHECK_STAGING_SHUTDOWN || action == .RETIRE_AND_REUSE_SESSION));
	active_lifecycle := action != .NONE && !negative_control;
	retired := active_lifecycle && action == .RETIRE_AND_REUSE_SESSION;
	pre_decision := batch_states && !new_document || validation;
	assert(!batch_states || !batch_revisions);
	assert(!new_document || batch_states);
	assert(!list || retry);
	assert(!validation || !retry);
	assert(!hold_heap_gate || allocate && !direct && !negative_control);
	test := prepared_retain(.WORLD, .ARRAYS);
	fixture := test.drain.fixture;
	batch := Service.begin_batch(fixture.host);
	filename := ifx new_document then "added.jai" else "a.jai";
	assert(Service.set_overlay(*batch, filename, "answer :: 77;"));
	source := receipt_source_batch(batch);
	if validation {
		prepare_provider_error(*source, .DUPLICATE_EVENT, .{}, .[]);
	}

	probe := Pool_Cleanup_Probe.{
		fixture = fixture,
		world = test.drain.world,
		direct = direct,
		suppress_callback = negative_control,
		allocate = allocate,
		mutate = mutate,
		hold_heap_gate = hold_heap_gate,
		capture_at = 1,
		job = .{
			drain = test.drain,
			action = action,
			active_source_retirement = retired,
		},
	};

	if hold_heap_gate {
		init(*probe.heap_entered);
	}

	output_probe := Output_Probe.{
		fail_at = ifx retry || validation
			then 0
			else 1,
		direct = direct,
		job = .{
			drain = test.drain,
			action = ifx retry && !(active_lifecycle && pre_decision)
				then ifx list
					then .FILL_OPERATION_CAPACITY
					else .FILL_REGISTRATION_CAPACITY
				else .NONE,
		},
	};

	allocator := open_output_probe(*output_probe);
	before: Service.Resource_Ledger;
	Service.with_lock(
		*fixture.session.gate,
		#code {
			before = fixture.session.ledger;
			fixture.session.faults.allow_active_session_release = retired;
			if batch_revisions {
				fixture.session.faults.source_batch_revisions_allocation_hook = storage_cleanup_allocation_probe;
				fixture.session.faults.source_batch_revisions_allocation_data = *probe;
			} else if batch_states {
				fixture.session.faults.source_batch_state_allocation_hook = storage_cleanup_allocation_probe;
				fixture.session.faults.source_batch_state_allocation_data = *probe;
			} else {
				fixture.session.faults.source_batch_pool_allocation_hook = pool_cleanup_allocation_probe;
				fixture.session.faults.source_batch_pool_allocation_data = *probe;
			}
		}
	);

	ok, accepted, error := Service.submit_source_batch(
		fixture.host.service,
		fixture.host.session,
		source
		,, allocator
	);

	assert(probe.memory && !probe.allocation_pending);
	assert(probe.allocations == (ifx retry && !active_lifecycle then 2 else 1));
	assert(probe.job.ok == active_lifecycle);
	if negative_control {
		assert(!probe.callbacks && !probe.gate_progress, "\e[91mMissing pool-root free callback negative control was not detected.\e[0m");
		assert(!probe.allocated && !probe.mutated);
	} else {
		assert(probe.callbacks == 1 && probe.gate_progress && probe.readable && probe.active_admissions == 1);
		assert(probe.allocated == allocate);
		assert(probe.mutated == mutate && probe.heap_blocked == hold_heap_gate);
		assert(probe.ledger.live[Service.Limit_Name.CONCURRENT_ACQUISITIONS] == before.live[Service.Limit_Name.CONCURRENT_ACQUISITIONS] + 1);
		callback_handles := ifx batch_states && !new_document
			then 1
			else output_probe.job.competing_worlds.count + output_probe.job.competing_tickets.count + xx validation;
		assert(probe.ledger.live[Service.Limit_Name.LIVE_HANDLES] == before.live[Service.Limit_Name.LIVE_HANDLES] + callback_handles);
	}

	Service.with_lock(
		*allocation_ledger.gate,
		#code {
			assert(probe.frees == 1 && !allocation_ledger.pool_cleanup);
		}
	);

	Service.with_lock(
		*fixture.session.gate,
		#code {
			fixture.session.faults.source_batch_pool_allocation_hook = null;
			fixture.session.faults.source_batch_pool_allocation_data = null;
			fixture.session.faults.source_batch_state_allocation_hook = null;
			fixture.session.faults.source_batch_state_allocation_data = null;
			fixture.session.faults.source_batch_revisions_allocation_hook = null;
			fixture.session.faults.source_batch_revisions_allocation_data = null;
			fixture.session.faults.allow_active_session_release = false;
			assert(!fixture.session.active_admissions);
			assert(fixture.session.ledger.live[Service.Limit_Name.CONCURRENT_ACQUISITIONS] == before.live[Service.Limit_Name.CONCURRENT_ACQUISITIONS]);
			assert(
				fixture.session.ledger.live[Service.Limit_Name.LIVE_HANDLES]
				== before.live[Service.Limit_Name.LIVE_HANDLES] + output_probe.job.competing_worlds.count + output_probe.job.competing_tickets.count + xx ok + xx retired
			);
			if !ok {
				assert(Service.bytes_equal(fixture.session.provider.accepted_frontier, batch.description.accepted_frontier));
				if !active_lifecycle {
					assert(fixture.session.ledger.live[Service.Limit_Name.IN_FLIGHT_OPERATIONS] == before.live[Service.Limit_Name.IN_FLIGHT_OPERATIONS]);
				}
			}

			if new_document {
				added := Service.find_document(fixture.session.provider, batch.events[0].document);
				assert(!!added == ok);
				if added {
					assert(Service.bytes_equal(Service.selected_document(added).source.bytes, xx "answer :: 77;"));
				}
			}
		}
	);

	if retry && !active_lifecycle {
		assert(ok && output_probe.gate_progress && output_probe.job.ok && output_probe.allocations == 2);
		observation := await(fixture, accepted.ticket);
		assert(observation.update.kind == .PUBLISHED);
		Service.free_observation(*observation);
		if batch_states || batch_revisions {
			world := world_of(fixture, accepted.ticket);
			read_ok, description := Service.read_world(fixture.host.service, world);
			assert(read_ok && description.members.count == 1);
			if !new_document {
				assert(Service.bytes_equal(description.members[0].source.bytes, xx "answer :: 77;"));
			}

			release(fixture, world);
		}

		release(fixture, accepted.ticket);
	} else if active_lifecycle && (pre_decision || retry) {
		assert(!ok && !accepted.ticket.owner_token && !accepted.frontier.count);
		if retired {
			assert(error.code == .INVALID_HANDLE && error.handle_kind == .SESSION);
		} else {
			assert(error.code == .SERVICE_CLOSED);
		}

		if retry {
			assert(output_probe.allocations == 1);
			assert(output_probe.job.ok == !pre_decision);
		}
	} else if validation {
		assert(!ok && !accepted.ticket.owner_token && !accepted.frontier.count);
		assert_provider_error(error, .DUPLICATE_EVENT, .[]);
	} else {
		assert(!ok && !accepted.ticket.owner_token && !accepted.frontier.count && error.code == .ADMISSION_DENIED && error.admission.kind == .RESOURCE_EXHAUSTED);
	}

	if validation {
		free_provider_error_batch(source, .DUPLICATE_EVENT);
	}

	assert(Service.read_world(fixture.host.service, test.drain.world));
	if retired {
		observation := await(fixture, probe.job.coordinator_shutdown);
		assert(observation.kind == .SHUTDOWN);
		Service.free_observation(*observation);
		release(fixture, probe.job.coordinator_shutdown);
		assert(Service.read_world(fixture.host.service, probe.job.replacement_world));
		release(fixture, probe.job.replacement_world);
	}

	free(accepted.frontier.data,, allocator);
	for output_probe.job.competing_worlds {
		read_ok := Service.read_world(fixture.host.service, it);
		assert(read_ok);
		release(fixture, it);
	}

	array_free(output_probe.job.competing_worlds);
	for output_probe.job.competing_tickets {
		release(fixture, it);
	}

	array_free(output_probe.job.competing_tickets);
	free(error.path.data,, allocator);
	free(error.document.data,, allocator);
	close_output_probe(*output_probe);
	if hold_heap_gate {
		destroy(*probe.heap_entered);
	}

	if retired {
		for test.held {
			release(fixture, it);
		}

		array_free(test.held);
		release(fixture, test.source);
		finish_drain(test.drain, session_released = true);
	} else {
		finish_retain(test);
	}

	print(
		"X5 actual root/construction free/gate progress/private charges (direct = %, retry = %, negative control = %, list = %, validation = %, allocate = %, mutate = %, held heap = %, batch states = %, batch revisions = %, new document = %, action = %) \e[92mPASS\e[0m\n",
		direct,
		retry,
		negative_control,
		list,
		validation,
		allocate,
		mutate,
		hold_heap_gate,
		batch_states,
		batch_revisions,
		new_document,
		action
	);
}

test_source_batch_state_cleanup_lifecycle :: (revisions := false) {
	for bool.[false, true] {
		new_document := it;
		if revisions && new_document {
			continue;
		}


		for 0..3 {
			retry := it == 1 || it == 2;
			list := it == 2;
			validation := it == 3;
			for bool.[false, true] {
				direct := it;
				for Output_Action.[.CHECK_STAGING_SHUTDOWN, .RETIRE_AND_REUSE_SESSION] {
					action := it;
					for bool.[false, true] {
						test_source_batch_pool_cleanup(
							direct = direct,
							retry = retry,
							list = list,
							validation = validation,
							allocate = true,
							mutate = true,
							negative_control = it,
							batch_states = !revisions,
							batch_revisions = revisions,
							new_document = new_document,
							action = action
						);
					}
				}
			}
		}
	}
}

test_source_batch_construction_cleanup :: (revisions := false, new_document := false) {
	assert(!new_document || !revisions);
	for 0..3 {
		retry := it == 1 || it == 2;
		list := it == 2;
		validation := it == 3;
		for bool.[false, true] {
			direct := it;
			for bool.[false, true] {
				test_source_batch_pool_cleanup(
					direct = direct,
					retry = retry,
					list = list,
					validation = validation,
					allocate = true,
					mutate = true,
					negative_control = it,
					batch_states = !revisions,
					batch_revisions = revisions,
					new_document = new_document
				);
			}
		}

		test_source_batch_pool_cleanup(
			retry = retry,
			list = list,
			validation = validation,
			allocate = true,
			mutate = true,
			hold_heap_gate = true,
			batch_states = !revisions,
			batch_revisions = revisions,
			new_document = new_document
		);
	}
}

test_source_batch_pool_cleanup_reentry :: () {
	for 0..3 {
		retry := it == 1 || it == 2;
		list := it == 2;
		validation := it == 3;
		for bool.[false, true] {
			test_source_batch_pool_cleanup(
				direct = it,
				retry = retry,
				list = list,
				validation = validation,
				allocate = true,
				mutate = true
			);

			test_source_batch_pool_cleanup(
				direct = it,
				retry = retry,
				negative_control = true,
				list = list,
				validation = validation,
				allocate = true,
				mutate = true
			);
		}

		test_source_batch_pool_cleanup(
			retry = retry,
			list = list,
			validation = validation,
			allocate = true,
			mutate = true,
			hold_heap_gate = true
		);
	}
}

test_source_registration_quota :: () {
	for Service.Limit_Name.[.LIVE_HANDLES, .IN_FLIGHT_OPERATIONS, .CONCURRENT_ACQUISITIONS] {
		name := it;
		test := prepared_retain(.WORLD, .ARRAYS);
		fixture := test.drain.fixture;
		batch := Service.begin_batch(fixture.host);
		assert(Service.set_overlay(*batch, "a.jai", "answer :: 77;"));
		before: Service.Resource_Ledger;
		probe := Registration_Probe.{};
		Service.with_lock(
			*fixture.session.gate,
			#code {
				before = fixture.session.ledger;
				fixture.session.ledger.limits.values[name] = before.live[name] + before.reserved[name];
				fixture.session.faults.registration_allocation_hook = registration_allocation_probe;
				fixture.session.faults.registration_allocation_data = *probe;
				fixture.session.faults.source_provider_allocation_hook = registration_allocation_probe;
				fixture.session.faults.source_provider_allocation_data = *probe;
				fixture.session.faults.source_provider_arrays_allocation_hook = registration_allocation_probe;
				fixture.session.faults.source_provider_arrays_allocation_data = *probe;
				fixture.session.faults.source_provider_states_allocation_hook = registration_allocation_probe;
				fixture.session.faults.source_provider_states_allocation_data = *probe;
				fixture.session.faults.source_provider_revisions_allocation_hook = registration_allocation_probe;
				fixture.session.faults.source_provider_revisions_allocation_data = *probe;
				fixture.session.faults.source_batch_pool_allocation_hook = registration_allocation_probe;
				fixture.session.faults.source_batch_pool_allocation_data = *probe;
			}
		);

		ok, accepted, error := Service.submit_source_batch(fixture.host.service, fixture.host.session, receipt_source_batch(batch));
		assert(!ok && !accepted.ticket.owner_token && !accepted.frontier.count && !probe.allocations);
		assert(error.code == .ADMISSION_DENIED && error.admission.kind == .LIMIT && error.admission.limit == name);
		Service.with_lock(
			*fixture.session.gate,
			#code {
				assert(!fixture.session.active_admissions);
				assert(Service.bytes_equal(fixture.session.provider.accepted_frontier, batch.description.accepted_frontier));
				for before.live {
					assert(fixture.session.ledger.live[it_index] == it && fixture.session.ledger.reserved[it_index] == before.reserved[it_index]);
				}

				fixture.session.ledger.limits = before.limits;
				fixture.session.faults.registration_allocation_hook = null;
				fixture.session.faults.registration_allocation_data = null;
				fixture.session.faults.source_provider_allocation_hook = null;
				fixture.session.faults.source_provider_allocation_data = null;
				fixture.session.faults.source_provider_arrays_allocation_hook = null;
				fixture.session.faults.source_provider_arrays_allocation_data = null;
				fixture.session.faults.source_provider_states_allocation_hook = null;
				fixture.session.faults.source_provider_states_allocation_data = null;
				fixture.session.faults.source_provider_revisions_allocation_hook = null;
				fixture.session.faults.source_provider_revisions_allocation_data = null;
				fixture.session.faults.source_batch_pool_allocation_hook = null;
				fixture.session.faults.source_batch_pool_allocation_data = null;
			}
		);

		finish_retain(test);
	}

	print("X5 source ticket full handle/operation/acquisition quota/no backing allocation/no provider commit \e[92mPASS\e[0m\n");
}

test_source_registration_interleavings :: (
	direct := false,
	negative_control := false,
	update := false,
	job_at: s64 = 1,
	list := false,
	cleanup := false,
	provider := false,
	arrays := false,
	states := false,
	revisions := false,
	multiple := false,
	pool := false,
	pool_retirement := false
) {
	assert(!pool_retirement || pool);
	for Output_Action.[
		.OTHER_DRAIN,
		.REQUEST_SHUTDOWN,
		.REPLACE_SOURCE,
		.FILL_REGISTRATION_CAPACITY,
		.FILL_OPERATION_CAPACITY,
		.TAKE_RETAIN_CAPACITY,
		.RETIRE_AND_REUSE_SESSION,
		.RETIRE_RETAIN_OWNER,
		.ISSUE_COMPETING_RESULT,
		.EXHAUST_OPERATION_COUNTER,
		.REJECT_ACTIVE_RELEASE,
		.CHECK_STAGING_SHUTDOWN,
	] {
		action := it;
		if pool_retirement && action != .RETIRE_AND_REUSE_SESSION {
			continue;
		}


		if !pool && (action == .REJECT_ACTIVE_RELEASE || action == .CHECK_STAGING_SHUTDOWN) {
			continue;
		}


		if pool && !pool_retirement && (action == .RETIRE_AND_REUSE_SESSION || action == .RETIRE_RETAIN_OWNER || action == .TAKE_RETAIN_CAPACITY) {
			continue;
		}


		if !update && !list && !provider && !arrays && !states && !revisions && !pool && (action == .ISSUE_COMPETING_RESULT || action == .EXHAUST_OPERATION_COUNTER) {
			continue;
		}


		if !list && !update && !provider && !arrays && !states && !revisions && !pool && action == .FILL_OPERATION_CAPACITY {
			continue;
		}


		if (
			negative_control && (ifx pool && !pool_retirement
				then action != .FILL_REGISTRATION_CAPACITY && action != .FILL_OPERATION_CAPACITY
				else action != .RETIRE_AND_REUSE_SESSION
			)
		) {
			continue;
		}


		for 0..(ifx pool then 3 else 6) {
			fail_at := it;
			if pool && !pool_retirement && negative_control && fail_at != 2 {
				continue;
			}


			if cleanup && fail_at {
				continue;
			}


			if fail_at && fail_at < job_at {
				continue;
			}


			test := prepared_retain(.WORLD, .ARRAYS);
			fixture := test.drain.fixture;
			if (states || revisions) && (cleanup || multiple) {
				extra := Service.begin_batch(fixture.host);
				assert(Service.set_overlay(*extra, "b.jai", "second :: 2;"));
				added_ok, added := Service.submit_batch(*extra);
				assert(added_ok);
				observation := await(fixture, added.ticket);
				assert(observation.update.kind == .PUBLISHED);
				Service.free_observation(*observation);
				release(fixture, added.ticket);
				free(added.frontier.data);
			}

			batch := Service.begin_batch(fixture.host);
			assert(Service.set_overlay(*batch, "a.jai", "answer :: 77;"));
			probe := Registration_Probe.{
				fail_at = fail_at,
				job_at = job_at,
				direct = direct,
				track_source = true,
				job = .{
					drain = test.drain,
					action = action,
					active_source_retirement = pool_retirement,
				},
			};
			allocation_failure := Registration_Probe.{fail_at = 2, guard = *probe};

			if action == .RETIRE_RETAIN_OWNER {
				array_add(*test.held, test.source);
				probe.job.retained_worlds = test.held;
			}

			operation_counter: Service.Identity_Counter;
			Service.with_lock(
				*fixture.session.gate,
				#code {
					operation_counter = fixture.session.identities.operation_counter;
					if pool {
						fixture.session.faults.source_batch_pool_allocation_hook = registration_allocation_probe;
						fixture.session.faults.source_batch_pool_allocation_data = *probe;
						fixture.session.faults.retry_failed_source_batch_pool = negative_control && !pool_retirement;
						fixture.session.faults.allow_active_session_release = pool_retirement;
						fixture.session.faults.allow_stale_source_batch_pool = negative_control && pool_retirement;
					} else if revisions {
						fixture.session.faults.allow_stale_source_provider_revisions = negative_control;
						fixture.session.faults.source_provider_revisions_allocation_hook = registration_allocation_probe;
						if cleanup {
							fixture.session.faults.source_provider_revisions_allocation_data = *allocation_failure;
							fixture.session.faults.source_provider_revisions_cleanup_hook = registration_allocation_probe;
							fixture.session.faults.source_provider_revisions_cleanup_data = *probe;
						} else {
							fixture.session.faults.source_provider_revisions_allocation_data = *probe;
						}
					} else if states {
						fixture.session.faults.allow_stale_source_provider_states = negative_control;
						fixture.session.faults.source_provider_states_allocation_hook = registration_allocation_probe;
						if cleanup {
							fixture.session.faults.source_provider_states_allocation_data = *allocation_failure;
							fixture.session.faults.source_provider_states_cleanup_hook = registration_allocation_probe;
							fixture.session.faults.source_provider_states_cleanup_data = *probe;
						} else {
							fixture.session.faults.source_provider_states_allocation_data = *probe;
						}
					} else if arrays {
						fixture.session.faults.allow_stale_source_provider_arrays = negative_control;
						fixture.session.faults.source_provider_arrays_allocation_hook = registration_allocation_probe;
						if cleanup {
							fixture.session.faults.source_provider_arrays_allocation_data = *allocation_failure;
							fixture.session.faults.source_provider_arrays_cleanup_hook = registration_allocation_probe;
							fixture.session.faults.source_provider_arrays_cleanup_data = *probe;
						} else {
							fixture.session.faults.source_provider_arrays_allocation_data = *probe;
						}
					} else if provider {
						fixture.session.faults.source_provider_allocation_hook = registration_allocation_probe;
						fixture.session.faults.source_provider_allocation_data = *probe;
						fixture.session.faults.allow_stale_source_provider = negative_control;
					} else if list {
						fixture.session.operations.allocated = fixture.session.operations.count;
						fixture.session.faults.source_operation_allocation_data = *probe;
						fixture.session.faults.allow_stale_source_operation = negative_control;
						if cleanup {
							fixture.session.faults.source_operation_cleanup_hook = registration_allocation_probe;
						} else {
							fixture.session.faults.source_operation_allocation_hook = registration_allocation_probe;
						}
					} else if update {
						fixture.session.faults.source_update_allocation_hook = registration_allocation_probe;
						fixture.session.faults.source_update_allocation_data = *probe;
					} else {
						fixture.session.faults.registration_allocation_hook = registration_allocation_probe;
						fixture.session.faults.registration_allocation_data = *probe;
					}
					fixture.session.faults.allow_stale_source_registration = negative_control && !pool;
				}
			);

			ok, accepted, error := Service.submit_source_batch(fixture.host.service, fixture.host.session, receipt_source_batch(batch));
			assert(probe.gate_progress && probe.job.ok && probe.allocations);
			if (arrays || states || revisions) && cleanup {
				assert(allocation_failure.allocations == 2);
			}

			assert(probe.source_active_admissions == (ifx pool then 1 else 0));
			retired := action == .RETIRE_AND_REUSE_SESSION || action == .RETIRE_RETAIN_OWNER;
			if pool && !pool_retirement && negative_control {
				assert(ok && accepted.ticket.owner_token && accepted.frontier.count && probe.allocations == 3, "\e[91mFailed pool-root retry admission negative control was not detected.\e[0m");
			} else if negative_control {
				assert(!ok && error.code == .SERVICE_CLOSED, "\e[91mSkipped source-session revalidation negative control was not detected.\e[0m");
			} else if retired {
				assert(!ok && !accepted.ticket.owner_token && error.code == .INVALID_HANDLE && error.handle_kind == .SESSION);
			} else if action == .REQUEST_SHUTDOWN || action == .CHECK_STAGING_SHUTDOWN {
				assert(!ok && error.code == .SERVICE_CLOSED);
			} else if action == .REPLACE_SOURCE {
				assert(!ok && error.code == .BASE_MISMATCH && error.scope == .FRONTIER);
			} else if fail_at && fail_at <= probe.allocations || (arrays || states || revisions) && cleanup {
				assert(!ok && !accepted.ticket.owner_token && error.code == .ADMISSION_DENIED && error.admission.kind == .RESOURCE_EXHAUSTED);
				if pool && fail_at == 2 {
					assert(probe.allocations == 2 && !accepted.frontier.count);
				}
			} else if action == .TAKE_RETAIN_CAPACITY {
				assert(!ok && error.code == .ADMISSION_DENIED && error.admission.kind == .LIMIT && error.admission.limit == .LIVE_HANDLES);
			} else if action == .EXHAUST_OPERATION_COUNTER {
				assert(!ok && !accepted.ticket.owner_token && error.code == .ADMISSION_DENIED && error.admission.kind == .RESOURCE_EXHAUSTED);
			} else {
				assert(ok && accepted.ticket.owner_token && accepted.frontier.count);
				if action == .FILL_REGISTRATION_CAPACITY {
					assert(
						probe.allocations == (ifx pool || arrays || ((states || revisions) && multiple)
							then 2
							else ifx list || provider || states || revisions
								then 1
								else ifx update
									then 3
									else 6
						)
					);
				}

				if action == .FILL_OPERATION_CAPACITY {
					assert(
						probe.allocations == (ifx pool || arrays || (states || revisions) && multiple
							then 2
							else ifx provider || states || revisions
								then 1
								else ifx list
									then 2
									else 3
						),
						"\e[91mOperation list callbacks: %, cleanup = %, direct = %, fail = %\e[0m",
						probe.allocations,
						cleanup,
						direct,
						fail_at
					);
				}
			}

			if action == .RETIRE_RETAIN_OWNER {
				allocation_count := ifx revisions
					then ifx cleanup
						then 1
						else job_at
					else ifx arrays || (states && multiple)
						then ifx cleanup
							then 1
							else 2
						else ifx list || provider || states
							then 1
							else 3;
				assert(probe.allocations == (ifx fail_at && fail_at <= allocation_count then fail_at else allocation_count));
			} else {
				Service.with_lock(
					*fixture.session.gate,
					#code {
						fixture.session.faults.registration_allocation_hook = null;
						fixture.session.faults.registration_allocation_data = null;
						fixture.session.faults.source_update_allocation_hook = null;
						fixture.session.faults.source_update_allocation_data = null;
						fixture.session.faults.source_operation_allocation_hook = null;
						fixture.session.faults.source_operation_cleanup_hook = null;
						fixture.session.faults.source_operation_allocation_data = null;
						fixture.session.faults.allow_stale_source_operation = false;
						fixture.session.faults.source_provider_allocation_hook = null;
						fixture.session.faults.source_provider_allocation_data = null;
						fixture.session.faults.allow_stale_source_provider = false;
						fixture.session.faults.source_provider_arrays_allocation_hook = null;
						fixture.session.faults.source_provider_arrays_allocation_data = null;
						fixture.session.faults.source_provider_arrays_cleanup_hook = null;
						fixture.session.faults.source_provider_arrays_cleanup_data = null;
						fixture.session.faults.allow_stale_source_provider_arrays = false;
						fixture.session.faults.source_provider_states_allocation_hook = null;
						fixture.session.faults.source_provider_states_allocation_data = null;
						fixture.session.faults.source_provider_states_cleanup_hook = null;
						fixture.session.faults.source_provider_states_cleanup_data = null;
						fixture.session.faults.allow_stale_source_provider_states = false;
						fixture.session.faults.source_provider_revisions_allocation_hook = null;
						fixture.session.faults.source_provider_revisions_allocation_data = null;
						fixture.session.faults.source_provider_revisions_cleanup_hook = null;
						fixture.session.faults.source_provider_revisions_cleanup_data = null;
						fixture.session.faults.allow_stale_source_provider_revisions = false;
						fixture.session.faults.source_batch_pool_allocation_hook = null;
						fixture.session.faults.source_batch_pool_allocation_data = null;
						fixture.session.faults.retry_failed_source_batch_pool = false;
						fixture.session.faults.allow_active_session_release = false;
						fixture.session.faults.allow_stale_source_batch_pool = false;
						fixture.session.faults.allow_stale_source_registration = false;
						assert(!fixture.session.active_admissions);
						private_charge: s64 = ifx pool
							then 1
							else 0;
						assert(fixture.session.ledger.live[Service.Limit_Name.LIVE_HANDLES] == probe.waiter_ledger.live[Service.Limit_Name.LIVE_HANDLES] - private_charge + xx ok);
						assert(fixture.session.ledger.live[Service.Limit_Name.CONCURRENT_ACQUISITIONS] == probe.waiter_ledger.live[Service.Limit_Name.CONCURRENT_ACQUISITIONS] - private_charge);
						if !ok {
							assert(fixture.session.identities.operation_counter.next == probe.callback_identities.operation_counter.next);
							assert(fixture.session.identities.world_counter.next == probe.callback_identities.world_counter.next);
							assert(fixture.session.identities.result_counter.next == probe.callback_identities.result_counter.next);
							if action != .REPLACE_SOURCE {
								assert(Service.bytes_equal(fixture.session.provider.accepted_frontier, batch.description.accepted_frontier));
							}
						}

						if action == .EXHAUST_OPERATION_COUNTER {
							fixture.session.identities.operation_counter = operation_counter;
						}
					}
				);
			}

			if ok {
				if update || list || provider || arrays || states || revisions || pool {
					polled, receipt := Service.poll(fixture.host.service, accepted.ticket);
					assert(polled);
					token_bytes := Service.little_endian(probe.callback_identities.operation_counter.next, 8);
					expected_identity := Service.make_key("operation", fixture.host.session_identity.([] u8), token_bytes);
					assert(Service.bytes_equal(receipt.operation_identity.([] u8), expected_identity));
					free(token_bytes.data);
					free(expected_identity.data);
					Service.free_observation(*receipt);
				}

				observation := await(fixture, accepted.ticket);
				assert(observation.update.kind == .PUBLISHED);
				Service.free_observation(*observation);
				release(fixture, accepted.ticket);
			}

			if probe.job.coordinator_shutdown.owner_token {
				observation := await(fixture, probe.job.coordinator_shutdown);
				assert(observation.kind == .SHUTDOWN);
				Service.free_observation(*observation);
				release(fixture, probe.job.coordinator_shutdown);
			}

			free(accepted.frontier.data);
			if probe.job.replacement.owner_token {
				read_ok := Service.read_result(fixture.host.service, probe.job.replacement);
				assert(read_ok);
				release(fixture, probe.job.replacement);
			}

			for probe.job.competing_worlds {
				read_ok := Service.read_world(fixture.host.service, it);
				assert(read_ok);
				release(fixture, it);
			}

			if probe.job.replacement_world.owner_token {
				read_ok := Service.read_world(fixture.host.service, probe.job.replacement_world);
				assert(read_ok);
				release(fixture, probe.job.replacement_world);
			}

			array_free(probe.job.competing_worlds);
			for probe.job.competing_tickets {
				observation := await(fixture, it);
				assert(observation.update.kind == .PUBLISHED);
				Service.free_observation(*observation);
				release(fixture, it);
			}

			array_free(probe.job.competing_tickets);
			free_records(probe.job.records);
			if action == .RETIRE_AND_REUSE_SESSION {
				for test.held {
					release(fixture, it);
				}

				array_free(test.held);
				release(fixture, test.source);
				finish_drain(test.drain, session_released = true);
			} else {
				finish_retain(test, owner_released = action == .RETIRE_RETAIN_OWNER);
			}
		}
	}

	print(
		"X3/X5 source ticket/update/list/provider backing/frontier/shutdown/quota/capacity retry/counters/session reuse/owner retirement (direct = %, negative control = %, update = %, callback = %, list = %, cleanup = %, provider = %, arrays = %, states = %, revisions = %, multiple = %, pool = %, pool retirement = %) \e[92mPASS\e[0m\n",
		direct,
		negative_control,
		update,
		job_at,
		list,
		cleanup,
		provider,
		arrays,
		states,
		revisions,
		multiple,
		pool,
		pool_retirement
	);
}

test_source_registration_receipt_retry :: (
	direct := false,
	list := false,
	provider := false,
	arrays := false,
	states := false,
	revisions := false,
	reject_receipt := false,
	pool := false,
	reference_control := false,
	transfer := false,
	batch_states := false,
	batch_revisions := false
) {
	construction := batch_states || batch_revisions;
	track_references := revisions || pool || transfer || construction;
	assert(!batch_states || !batch_revisions);
	assert(!construction || !pool && !transfer && !provider && !arrays && !states && !revisions);
	assert(!reference_control || pool || transfer || construction);
	assert(!transfer || !pool && !revisions && !states && !arrays && !provider);
	for 0..(ifx transfer then 5 else ifx pool || construction then 3 else 6) {
		fail_at := it;
		if (reject_receipt || reference_control) && fail_at {
			continue;
		}


		test := prepared_retain(.WORLD, .ARRAYS);
		fixture := test.drain.fixture;
		sentinel_world: Service.Handle(.WORLD);
		source_document: [] u8;
		if track_references {
			extra := Service.begin_batch(fixture.host);
			assert(Service.set_overlay(*extra, "b.jai", "second :: 2;"));
			added_ok, added := Service.submit_batch(*extra);
			assert(added_ok);
			sentinel_world = world_of(fixture, added.ticket);
			source_document = Service.harness_document(fixture.host, "b.jai").([] u8);
			release(fixture, added.ticket);
			free(added.frontier.data);
		}

		if transfer {
			while true {
				full: bool;
				count: s64;
				Service.with_lock(
					*fixture.session.gate,
					#code {
						count = fixture.session.provider.batch_storage.count;
						full = count == fixture.session.provider.batch_storage.allocated;
					}
				);

				if full {
					break;
				}


				ticket := submit(fixture, tprint("answer :: %;", 100 + count));
				observation := await(fixture, ticket);
				assert(observation.update.kind == .PUBLISHED);
				Service.free_observation(*observation);
				release(fixture, ticket);
			}
		}

		batch := Service.begin_batch(fixture.host);
		assert(Service.set_overlay(*batch, "a.jai", "answer :: 77;"));
		probe := Registration_Probe.{
			fail_at = fail_at,
			job_at = ifx transfer
				then 3
				else ifx pool || construction
					then 2
					else ifx arrays || revisions
						then 3
						else ifx list || provider || states
							then 2
							else 4,
			direct = direct,
			track_source = true,
			source_document = source_document,
			job = .{drain = test.drain, action = .OTHER_DRAIN},
		};

		output_probe := Output_Probe.{
			fail_at = ifx reject_receipt
				then 1
				else 0,
			direct = direct,
			job = .{
				drain = test.drain,
				action = ifx reject_receipt
					then .NONE
					else ifx list
						then .FILL_OPERATION_CAPACITY
						else .FILL_REGISTRATION_CAPACITY
			},
			registration_probe = *probe,
			source_document = source_document,
		};

		allocator := open_output_probe(*output_probe);
		before: Service.Resource_Ledger;
		identities: Service.Session_Identities;
		source_references: s64;
		Service.with_lock(
			*fixture.session.gate,
			#code {
				before = fixture.session.ledger;
				identities = fixture.session.identities;
				if track_references {
					state := Service.find_document(fixture.session.provider, source_document);
					assert(state && state.has_overlay && state.overlay.source);
					source_references = state.overlay.source.references;
					if reference_control {
						assert(source_references >= 2);
						fixture.session.faults.retain_source_batch_reference = state.overlay.source;
					}
				}

				if list {
					fixture.session.operations.allocated = fixture.session.operations.count;
				}

				if batch_states {
					fixture.session.faults.source_batch_state_allocation_hook = registration_allocation_probe;
					fixture.session.faults.source_batch_state_allocation_data = *probe;
				} else if batch_revisions {
					fixture.session.faults.source_batch_revisions_allocation_hook = registration_allocation_probe;
					fixture.session.faults.source_batch_revisions_allocation_data = *probe;
				} else if transfer {
					fixture.session.faults.source_batch_storage_allocation_hook = registration_allocation_probe;
					fixture.session.faults.source_batch_storage_allocation_data = *probe;
				} else if pool {
					fixture.session.faults.source_batch_pool_allocation_hook = registration_allocation_probe;
					fixture.session.faults.source_batch_pool_allocation_data = *probe;
				} else if revisions {
					fixture.session.faults.source_provider_revisions_allocation_hook = registration_allocation_probe;
					fixture.session.faults.source_provider_revisions_allocation_data = *probe;
				} else if states {
					fixture.session.faults.source_provider_states_allocation_hook = registration_allocation_probe;
					fixture.session.faults.source_provider_states_allocation_data = *probe;
				} else if arrays {
					fixture.session.faults.source_provider_arrays_allocation_hook = registration_allocation_probe;
					fixture.session.faults.source_provider_arrays_allocation_data = *probe;
				} else if provider {
					fixture.session.faults.source_provider_allocation_hook = registration_allocation_probe;
					fixture.session.faults.source_provider_allocation_data = *probe;
				} else if list {
					fixture.session.faults.source_operation_allocation_hook = registration_allocation_probe;
					fixture.session.faults.source_operation_allocation_data = *probe;
				} else {
					fixture.session.faults.registration_allocation_hook = registration_allocation_probe;
					fixture.session.faults.registration_allocation_data = *probe;
				}
			}
		);

		ok, accepted, error := Service.submit_source_batch(
			fixture.host.service,
			fixture.host.session,
			receipt_source_batch(batch)
			,, allocator
		);

		initial_allocations := ifx transfer
			then 2
			else ifx pool || construction
				then 1
				else ifx arrays || revisions
					then 2
					else ifx list || provider || states
						then 1
						else 3;
		if fail_at && fail_at <= initial_allocations {
			assert(!ok && probe.allocations == fail_at && !output_probe.allocations);
		} else if reject_receipt {
			assert(!ok && probe.allocations == initial_allocations && output_probe.allocations == 1);
			assert(!probe.gate_progress && !output_probe.gate_progress);
			assert(output_probe.source_references[0] == source_references + 1);
			assert(output_probe.source_active_admissions[0] == 1);
		} else {
			assert(output_probe.gate_progress && output_probe.job.ok);
			assert(probe.gate_progress && probe.job.ok && probe.source_active_admissions == (ifx pool || transfer || construction then 1 else 0));
			private_charge: s64 = ifx pool || transfer || construction then 1 else 0;
			if track_references {
				assert(probe.source_references == source_references + private_charge + xx reference_control);
				for 0..output_probe.allocations - 1 {
					assert(output_probe.source_references[it] == source_references + 1 + xx (reference_control && it > 0));
					assert(output_probe.source_active_admissions[it] == 1);
				}
			}

			assert(probe.waiter_ledger.live[Service.Limit_Name.CONCURRENT_ACQUISITIONS] == before.live[Service.Limit_Name.CONCURRENT_ACQUISITIONS] + private_charge);
			assert(probe.waiter_ledger.live[Service.Limit_Name.IN_FLIGHT_OPERATIONS] == before.live[Service.Limit_Name.IN_FLIGHT_OPERATIONS] + private_charge);
			assert(probe.waiter_ledger.live[Service.Limit_Name.LIVE_HANDLES] == before.live[Service.Limit_Name.LIVE_HANDLES] + output_probe.job.competing_worlds.count + output_probe.job.competing_tickets.count + private_charge);
			assert(probe.callback_identities.operation_counter.next == identities.operation_counter.next + xx output_probe.job.competing_tickets.count);
			assert(output_probe.allocations == (ifx ok then 2 else 1));
			total_allocations := ifx transfer
				then 4
				else ifx pool || construction
					then 2
					else ifx arrays || revisions
						then 4
						else ifx list || provider || states
							then 2
							else 6;
			assert(probe.allocations == (ifx fail_at && fail_at <= total_allocations then fail_at else total_allocations));
		}

		if !ok {
			assert(!accepted.ticket.owner_token && !accepted.frontier.count && error.code == .ADMISSION_DENIED && error.admission.kind == .RESOURCE_EXHAUSTED);
		}

		control_reference: *Service.Source_Backing;
		Service.with_lock(
			*fixture.session.gate,
			#code {
				fixture.session.faults.registration_allocation_hook = null;
				fixture.session.faults.registration_allocation_data = null;
				fixture.session.faults.source_operation_allocation_hook = null;
				fixture.session.faults.source_operation_allocation_data = null;
				fixture.session.faults.source_provider_allocation_hook = null;
				fixture.session.faults.source_provider_allocation_data = null;
				fixture.session.faults.source_provider_arrays_allocation_hook = null;
				fixture.session.faults.source_provider_arrays_allocation_data = null;
				fixture.session.faults.source_provider_states_allocation_hook = null;
				fixture.session.faults.source_provider_states_allocation_data = null;
				fixture.session.faults.source_provider_revisions_allocation_hook = null;
				fixture.session.faults.source_provider_revisions_allocation_data = null;
				fixture.session.faults.source_batch_pool_allocation_hook = null;
				fixture.session.faults.source_batch_pool_allocation_data = null;
				fixture.session.faults.source_batch_storage_allocation_hook = null;
				fixture.session.faults.source_batch_storage_allocation_data = null;
				fixture.session.faults.source_batch_state_allocation_hook = null;
				fixture.session.faults.source_batch_state_allocation_data = null;
				fixture.session.faults.source_batch_revisions_allocation_hook = null;
				fixture.session.faults.source_batch_revisions_allocation_data = null;
				assert(!fixture.session.active_admissions);
				assert(fixture.session.ledger.live[Service.Limit_Name.LIVE_HANDLES] == before.live[Service.Limit_Name.LIVE_HANDLES] + output_probe.job.competing_worlds.count + output_probe.job.competing_tickets.count + xx ok);
				assert(fixture.session.ledger.live[Service.Limit_Name.CONCURRENT_ACQUISITIONS] == before.live[Service.Limit_Name.CONCURRENT_ACQUISITIONS]);
				if track_references {
					state := Service.find_document(fixture.session.provider, source_document);
					assert(state && state.overlay.source.references == source_references + xx reference_control, "\e[91mSource-reference rollback oracle did not distinguish the retained-reference control.\e[0m");
					if reference_control {
						assert(!fixture.session.faults.retain_source_batch_reference);
						control_reference = state.overlay.source;
					}
				}

				if !ok {
					assert(fixture.session.ledger.live[Service.Limit_Name.IN_FLIGHT_OPERATIONS] == before.live[Service.Limit_Name.IN_FLIGHT_OPERATIONS]);
					assert(Service.bytes_equal(fixture.session.provider.accepted_frontier, batch.description.accepted_frontier));
					assert(fixture.session.identities.operation_counter.next == identities.operation_counter.next + xx output_probe.job.competing_tickets.count);
					expected_world_counter := ifx probe.gate_progress
						then probe.callback_identities.world_counter.next
						else identities.world_counter.next;

					assert(fixture.session.identities.world_counter.next == expected_world_counter);
				}
			}
		);

		if control_reference {
			push_allocator(Service.owner_allocator(fixture.session));
			Service.release_source(control_reference);
			assert(control_reference.references == source_references);
		}

		if ok {
			observation := await(fixture, accepted.ticket);
			assert(observation.update.kind == .PUBLISHED);
			Service.free_observation(*observation);
			if track_references {
				published := world_of(fixture, accepted.ticket);
				read_ok, description := Service.read_world(fixture.host.service, published);
				assert(read_ok && description.members.count == 1);
				assert(Service.bytes_equal(description.members[0].source.bytes, xx "answer :: 77;"));
				release(fixture, published);
			}

			release(fixture, accepted.ticket);
		}

		free(accepted.frontier.data,, allocator);
		for output_probe.job.competing_worlds {
			read_ok := Service.read_world(fixture.host.service, it);
			assert(read_ok);
			release(fixture, it);
		}

		array_free(output_probe.job.competing_worlds);
		for output_probe.job.competing_tickets {
			observation := await(fixture, it);
			assert(observation.update.kind == .PUBLISHED);
			Service.free_observation(*observation);
			release(fixture, it);
		}

		array_free(output_probe.job.competing_tickets);
		free_records(probe.job.records);
		close_output_probe(*output_probe);
		if track_references {
			read_ok, description := Service.read_world(fixture.host.service, sentinel_world);
			assert(read_ok && description.members.count == 1);
			assert(Service.bytes_equal(description.members[0].source.bytes, xx "second :: 2;"));
			release(fixture, sentinel_world);
		}

		finish_retain(test);
	}

	print(
		"X3/X5 source receipt capacity race/private attempt cleanup/released charges/checked retry/provider atomicity (direct = %, list = %, provider = %, arrays = %, states = %, revisions = %, reject receipt = %, pool = %, reference control = %, transfer = %) \e[92mPASS\e[0m\n",
		direct,
		list,
		provider,
		arrays,
		states,
		revisions,
		reject_receipt,
		pool,
		reference_control,
		transfer
	);
}

test_source_registration_failure_control :: (update := false, list := false, provider := false, arrays := false, states := false, revisions := false, pool := false) {
	allocation_count := ifx arrays || revisions
		then 2
		else ifx list || provider || states || pool
			then 1
			else 3;
	for 1..allocation_count {
		fail_at := it;
		test := prepared_retain(.WORLD, .ARRAYS);
		fixture := test.drain.fixture;
		if revisions {
			extra := Service.begin_batch(fixture.host);
			assert(Service.set_overlay(*extra, "b.jai", "second :: 2;"));
			added_ok, added := Service.submit_batch(*extra);
			assert(added_ok);
			observation := await(fixture, added.ticket);
			assert(observation.update.kind == .PUBLISHED);
			Service.free_observation(*observation);
			release(fixture, added.ticket);
			free(added.frontier.data);
		}

		batch := Service.begin_batch(fixture.host);
		assert(Service.set_overlay(*batch, "a.jai", "answer :: 77;"));
		probe := Registration_Probe.{fail_at = fail_at};
		Service.with_lock(
			*fixture.session.gate,
			#code {
				if pool {
					fixture.session.faults.source_batch_pool_allocation_hook = registration_allocation_probe;
					fixture.session.faults.source_batch_pool_allocation_data = *probe;
					fixture.session.faults.retry_failed_source_batch_pool = true;
				} else if revisions {
					fixture.session.faults.source_provider_revisions_allocation_hook = registration_allocation_probe;
					fixture.session.faults.source_provider_revisions_allocation_data = *probe;
					fixture.session.faults.retry_failed_source_provider_revisions = true;
				} else if states {
					fixture.session.faults.source_provider_states_allocation_hook = registration_allocation_probe;
					fixture.session.faults.source_provider_states_allocation_data = *probe;
					fixture.session.faults.retry_failed_source_provider_states = true;
				} else if arrays {
					fixture.session.faults.source_provider_arrays_allocation_hook = registration_allocation_probe;
					fixture.session.faults.source_provider_arrays_allocation_data = *probe;
					fixture.session.faults.retry_failed_source_provider_arrays = true;
				} else if provider {
					fixture.session.faults.source_provider_allocation_hook = registration_allocation_probe;
					fixture.session.faults.source_provider_allocation_data = *probe;
					fixture.session.faults.retry_failed_source_provider = true;
				} else if list {
					fixture.session.operations.allocated = fixture.session.operations.count;
					fixture.session.faults.source_operation_allocation_hook = registration_allocation_probe;
					fixture.session.faults.source_operation_allocation_data = *probe;
					fixture.session.faults.retry_failed_source_operation = true;
				} else if update {
					fixture.session.faults.source_update_allocation_hook = registration_allocation_probe;
					fixture.session.faults.source_update_allocation_data = *probe;
					fixture.session.faults.retry_failed_source_update = true;
				} else {
					fixture.session.faults.registration_allocation_hook = registration_allocation_probe;
					fixture.session.faults.registration_allocation_data = *probe;
					fixture.session.faults.retry_failed_source_registration = true;
				}
			}
		);

		ok, accepted := Service.submit_source_batch(fixture.host.service, fixture.host.session, receipt_source_batch(batch));
		assert(ok && accepted.ticket.owner_token && probe.allocations == fail_at + allocation_count, "\e[91mFailed source backing admission negative control was not detected.\e[0m");
		Service.with_lock(
			*fixture.session.gate,
			#code {
				fixture.session.faults.registration_allocation_hook = null;
				fixture.session.faults.registration_allocation_data = null;
				fixture.session.faults.retry_failed_source_registration = false;
				fixture.session.faults.source_update_allocation_hook = null;
				fixture.session.faults.source_update_allocation_data = null;
				fixture.session.faults.retry_failed_source_update = false;
				fixture.session.faults.source_operation_allocation_hook = null;
				fixture.session.faults.source_operation_allocation_data = null;
				fixture.session.faults.retry_failed_source_operation = false;
				fixture.session.faults.source_provider_allocation_hook = null;
				fixture.session.faults.source_provider_allocation_data = null;
				fixture.session.faults.retry_failed_source_provider = false;
				fixture.session.faults.source_provider_arrays_allocation_hook = null;
				fixture.session.faults.source_provider_arrays_allocation_data = null;
				fixture.session.faults.retry_failed_source_provider_arrays = false;
				fixture.session.faults.source_provider_states_allocation_hook = null;
				fixture.session.faults.source_provider_states_allocation_data = null;
				fixture.session.faults.retry_failed_source_provider_states = false;
				fixture.session.faults.source_provider_revisions_allocation_hook = null;
				fixture.session.faults.source_provider_revisions_allocation_data = null;
				fixture.session.faults.retry_failed_source_provider_revisions = false;
				fixture.session.faults.source_batch_pool_allocation_hook = null;
				fixture.session.faults.source_batch_pool_allocation_data = null;
				fixture.session.faults.retry_failed_source_batch_pool = false;
			}
		);

		observation := await(fixture, accepted.ticket);
		assert(observation.update.kind == .PUBLISHED);
		Service.free_observation(*observation);
		release(fixture, accepted.ticket);
		free(accepted.frontier.data);
		finish_retain(test);
	}

	print(
		"X5 source ticket/update/list/provider failed-backing provider-admission negative controls (update = %, list = %, provider = %, arrays = %, states = %, revisions = %, pool = %) \e[92mPASS\e[0m\n",
		update,
		list,
		provider,
		arrays,
		states,
		revisions,
		pool
	);
}

test_source_provider_arrays_refresh :: (direct := false, empty := false, states := false) {
	test := prepared_retain(.WORLD, .REUSE);
	fixture := test.drain.fixture;
	probe := Registration_Probe.{
		direct = direct,
		job = .{
			drain = test.drain,
			action = ifx empty
				then .NONE
				else .GROW_PROVIDER_CLONE_COUNTS
		},
	};

	backing: Service.Source_Provider_Backing;
	Service.with_lock(
		*fixture.session.gate,
		#code {
			documents_count := fixture.session.provider.documents.count;
			contexts_count := fixture.session.provider.contexts.count;
			before := fixture.session.ledger;
			identities := fixture.session.identities;
			assert(documents_count && contexts_count);
			if states {
				fixture.session.faults.source_provider_states_allocation_hook = registration_allocation_probe;
				fixture.session.faults.source_provider_states_allocation_data = *probe;
			} else {
				fixture.session.faults.source_provider_arrays_allocation_hook = registration_allocation_probe;
				fixture.session.faults.source_provider_arrays_allocation_data = *probe;
			}
			if empty {
				fixture.session.provider.documents.count = 0;
				fixture.session.provider.contexts.count = 0;
			}

			prepared := Service.prepare_source_provider_arrays(fixture.session, *backing);
			assert(prepared);
			if states {
				objects_ready := Service.prepare_source_provider_states(fixture.session, *backing);
				assert(objects_ready);
				if empty {
					assert(!probe.allocations && !backing.states_count);
				} else {
					assert(probe.allocations == documents_count && probe.gate_progress && probe.job.ok);
					assert(backing.states_count == documents_count);
					assert(!Service.source_provider_states_ready(fixture.session, *backing));
					prefix := backing.documents[0];
					assert(prefix && !prefix.disk.source && !prefix.overlay.source && !prefix.used_revisions.count);
					arrays_ready := Service.prepare_source_provider_arrays(fixture.session, *backing);
					assert(arrays_ready && Service.source_provider_arrays_ready(fixture.session, *backing));
					assert(backing.documents[0] == prefix && backing.states_count == documents_count);
					states_ready := Service.prepare_source_provider_states(fixture.session, *backing);
					assert(states_ready && probe.allocations == documents_count + 1);
					assert(backing.states_count == documents_count + 1 && backing.documents[0] == prefix);
					assert(backing.documents[documents_count] != prefix);
				}
			} else if empty {
				assert(!probe.allocations && !backing.documents.count && !backing.contexts.count);
			} else {
				assert(probe.allocations == 2 && probe.gate_progress && probe.job.ok);
				assert(!backing.documents.count && !backing.contexts.count);
				assert(!Service.source_provider_arrays_ready(fixture.session, *backing));
				assert(fixture.session.provider.documents.count == documents_count + 1);
				assert(fixture.session.provider.contexts.count == contexts_count + 1);
				refreshed := Service.prepare_source_provider_arrays(fixture.session, *backing);
				assert(refreshed && probe.allocations == 4);
				assert(backing.documents.count == documents_count + 1);
				assert(backing.contexts.count == contexts_count + 1);
			}

			assert(Service.source_provider_arrays_ready(fixture.session, *backing));
			fixture.session.provider.documents.count = documents_count;
			fixture.session.provider.contexts.count = contexts_count;
			if states && !empty {
				prefix := backing.documents[0];
				trimmed := Service.prepare_source_provider_states(fixture.session, *backing);
				assert(trimmed && Service.source_provider_states_ready(fixture.session, *backing));
				assert(backing.documents[0] == prefix && !backing.documents[documents_count]);
				assert(probe.allocations == documents_count + 1);
			}

			fixture.session.faults.source_provider_arrays_allocation_hook = null;
			fixture.session.faults.source_provider_arrays_allocation_data = null;
			fixture.session.faults.source_provider_states_allocation_hook = null;
			fixture.session.faults.source_provider_states_allocation_data = null;
			Service.finish_source_provider_backing(fixture.session, *backing);
			assert(!backing.documents.count && !backing.contexts.count);
			assert(!fixture.session.active_admissions);
			for before.live {
				assert(fixture.session.ledger.live[it_index] == it && fixture.session.ledger.reserved[it_index] == before.reserved[it_index]);
			}

			assert(fixture.session.identities.operation_counter.next == identities.operation_counter.next);
			assert(fixture.session.identities.world_counter.next == identities.world_counter.next);
			assert(fixture.session.identities.result_counter.next == identities.result_counter.next);
		}
	);

	finish_retain(test);
	print(
		"X5 provider clone backing stale-count refresh/prefix preservation/trim/empty allocation-free/cleanup (direct = %, empty = %, states = %) \e[92mPASS\e[0m\n",
		direct,
		empty,
		states
	);
}

test_source_provider_revisions_refresh :: (direct := false, surplus := false) {
	test := prepared_retain(.WORLD, .REUSE);
	fixture := test.drain.fixture;
	if surplus {
		extra := Service.begin_batch(fixture.host);
		assert(Service.set_overlay(*extra, "b.jai", "second :: 2;"));
		added_ok, added := Service.submit_batch(*extra);
		assert(added_ok);
		observation := await(fixture, added.ticket);
		assert(observation.update.kind == .PUBLISHED);
		Service.free_observation(*observation);
		release(fixture, added.ticket);
		free(added.frontier.data);
	}

	allocation_probe := Registration_Probe.{
		direct = direct,
		job = .{drain = test.drain, action = .GROW_PROVIDER_REVISION_COUNTS},
	};
	cleanup_probe := Registration_Probe.{
		direct = direct,
		job = .{drain = test.drain, action = .GROW_PROVIDER_REVISION_COUNTS},
	};
	backing: Service.Source_Provider_Backing;
	Service.with_lock(
		*fixture.session.gate,
		#code {
			push_allocator(Service.owner_allocator(fixture.session));
			before := fixture.session.ledger;
			identities := fixture.session.identities;
			documents_count := fixture.session.provider.documents.count;
			extra_allocations := surplus.(s64);
			assert(documents_count == 1 + extra_allocations);
			revisions_count := fixture.session.provider.documents[0].used_revisions.count;
			source_references := fixture.session.provider.documents[0].overlay.source.references;
			assert(!!revisions_count);
			arrays_ready := Service.prepare_source_provider_arrays(fixture.session, *backing);
			states_ready := Service.prepare_source_provider_states(fixture.session, *backing);
			assert(arrays_ready && states_ready && backing.states_count == documents_count);
			prefix := backing.documents[0];
			fixture.session.faults.source_provider_revisions_allocation_hook = registration_allocation_probe;
			fixture.session.faults.source_provider_revisions_allocation_data = *allocation_probe;
			fixture.session.faults.source_provider_revisions_cleanup_hook = registration_allocation_probe;
			fixture.session.faults.source_provider_revisions_cleanup_data = *cleanup_probe;

			prepared := Service.prepare_source_provider_revisions(fixture.session, *backing);
			assert(prepared && allocation_probe.allocations == 1 && cleanup_probe.allocations == 1);
			assert(allocation_probe.gate_progress && allocation_probe.job.ok && cleanup_probe.gate_progress && cleanup_probe.job.ok);
			assert(fixture.session.provider.documents[0].used_revisions.count == revisions_count + 2);
			assert(backing.documents[0] == prefix && !prefix.used_revisions.data && !prefix.used_revisions.allocated);
			assert(!Service.source_provider_revisions_ready(fixture.session, *backing));
			refreshed := Service.prepare_source_provider_revisions(fixture.session, *backing);
			if surplus {
				second_ready := Service.prepare_source_provider_revisions(fixture.session, *backing);
				assert(second_ready && backing.documents[1].used_revisions.allocated);
				assert(!backing.documents[1].used_revisions.count && !backing.documents[1].disk.source && !backing.documents[1].overlay.source);
			}

			assert(refreshed && Service.source_provider_revisions_ready(fixture.session, *backing));
			assert(allocation_probe.allocations == 2 + extra_allocations && cleanup_probe.allocations == 1);
			assert(prefix.used_revisions.allocated == revisions_count + 2);

			old_storage := prefix.used_revisions.data;
			array_add(*fixture.session.provider.documents[0].used_revisions, fixture.session.provider.documents[0].used_revisions[0]);
			cleanup_probe.allocations = 0;
			cleanup_probe.gate_progress = false;
			cleanup_probe.job.ok = false;
			replaced := Service.prepare_source_provider_revisions(fixture.session, *backing);
			assert(replaced && allocation_probe.allocations == 3 + extra_allocations && cleanup_probe.allocations == 1);
			assert(cleanup_probe.gate_progress && cleanup_probe.job.ok);
			assert(backing.documents[0] == prefix && prefix.used_revisions.data != old_storage);
			assert(prefix.used_revisions.allocated == revisions_count + 3);
			assert(!Service.source_provider_revisions_ready(fixture.session, *backing));
			ready := Service.prepare_source_provider_revisions(fixture.session, *backing);
			assert(ready && Service.source_provider_revisions_ready(fixture.session, *backing));
			assert(allocation_probe.allocations == 4 + extra_allocations && cleanup_probe.allocations == 2);
			assert(prefix.used_revisions.allocated == revisions_count + 4);
			assert(!prefix.used_revisions.count && !prefix.disk.source && !prefix.overlay.source);
			assert(fixture.session.provider.documents[0].overlay.source.references == source_references);
			if surplus {
				retained_storage := prefix.used_revisions.data;
				fixture.session.provider.documents.count = 1;
				cleanup_probe.allocations = 0;
				cleanup_probe.gate_progress = false;
				cleanup_probe.job.ok = false;
				trimmed := Service.prepare_source_provider_states(fixture.session, *backing);
				assert(trimmed && Service.source_provider_states_ready(fixture.session, *backing));
				assert(backing.states_count == 1 && backing.documents[0] == prefix && !backing.documents[1]);
				assert(prefix.used_revisions.data == retained_storage && prefix.used_revisions.allocated == revisions_count + 4);
				assert(cleanup_probe.allocations == 1 && cleanup_probe.gate_progress && cleanup_probe.job.ok);
				assert(allocation_probe.allocations == 5 && !Service.source_provider_revisions_ready(fixture.session, *backing));
				prefix_ready := Service.prepare_source_provider_revisions(fixture.session, *backing);
				assert(prefix_ready && Service.source_provider_revisions_ready(fixture.session, *backing));
				assert(allocation_probe.allocations == 6 && cleanup_probe.allocations == 2);
				assert(prefix.used_revisions.allocated == revisions_count + 5);

				fixture.session.provider.documents.count = documents_count;
				restored := Service.prepare_source_provider_states(fixture.session, *backing);
				assert(restored && Service.source_provider_states_ready(fixture.session, *backing));
				assert(backing.documents[0] == prefix && !backing.documents[1].used_revisions.data);
				assert(!Service.source_provider_revisions_ready(fixture.session, *backing));
				second_ready := Service.prepare_source_provider_revisions(fixture.session, *backing);
				assert(second_ready && Service.source_provider_revisions_ready(fixture.session, *backing));
				assert(allocation_probe.allocations == 7 && cleanup_probe.allocations == 2);
				assert(!backing.documents[1].used_revisions.count && !backing.documents[1].disk.source && !backing.documents[1].overlay.source);
				assert(fixture.session.provider.documents[0].overlay.source.references == source_references);
			}

			fixture.session.provider.documents[0].used_revisions.count = revisions_count;
			fixture.session.faults.source_provider_revisions_allocation_hook = null;
			fixture.session.faults.source_provider_revisions_allocation_data = null;
			Service.finish_source_provider_backing(fixture.session, *backing);
			assert(cleanup_probe.allocations == 3 + extra_allocations);
			fixture.session.faults.source_provider_revisions_cleanup_hook = null;
			fixture.session.faults.source_provider_revisions_cleanup_data = null;
			assert(!backing.states_count && !backing.documents.count && !backing.contexts.count);
			assert(!fixture.session.active_admissions);
			for before.live {
				assert(fixture.session.ledger.live[it_index] == it && fixture.session.ledger.reserved[it_index] == before.reserved[it_index]);
			}

			assert(fixture.session.identities.operation_counter.next == identities.operation_counter.next);
			assert(fixture.session.identities.world_counter.next == identities.world_counter.next);
			assert(fixture.session.identities.result_counter.next == identities.result_counter.next);
		}
	);

	finish_retain(test);
	print("X5 provider revision current counts/stale discard/replacement/surplus/cleanup reentry/no source retains (direct = %, surplus = %) \e[92mPASS\e[0m\n", direct, surplus);
}

test_source_provider_revisions_empty :: (empty_provider := false) {
	test := prepared_retain(.WORLD, .REUSE);
	fixture := test.drain.fixture;
	probe := Registration_Probe.{fail_at = 1};
	backing: Service.Source_Provider_Backing;
	Service.with_lock(
		*fixture.session.gate,
		#code {
			before := fixture.session.ledger;
			identities := fixture.session.identities;
			assert(fixture.session.provider.documents.count == 1);
			revisions_count := fixture.session.provider.documents[0].used_revisions.count;
			assert(!!revisions_count);
			fixture.session.faults.source_provider_revisions_allocation_hook = registration_allocation_probe;
			fixture.session.faults.source_provider_revisions_allocation_data = *probe;
			if empty_provider {
				fixture.session.provider.documents.count = 0;
			} else {
				fixture.session.provider.documents[0].used_revisions.count = 0;
			}

			arrays_ready := Service.prepare_source_provider_arrays(fixture.session, *backing);
			states_ready := Service.prepare_source_provider_states(fixture.session, *backing);
			assert(arrays_ready && states_ready && Service.source_provider_revisions_ready(fixture.session, *backing));
			prepared := Service.prepare_source_provider_revisions(fixture.session, *backing);
			assert(prepared && Service.source_provider_revisions_ready(fixture.session, *backing));
			assert(!probe.allocations);
			for 0..backing.states_count - 1 {
				assert(!backing.documents[it].used_revisions.data && !backing.documents[it].used_revisions.allocated);
			}

			fixture.session.provider.documents.count = 1;
			fixture.session.provider.documents[0].used_revisions.count = revisions_count;
			fixture.session.faults.source_provider_revisions_allocation_hook = null;
			fixture.session.faults.source_provider_revisions_allocation_data = null;
			Service.finish_source_provider_backing(fixture.session, *backing);
			assert(!backing.states_count && !backing.documents.count && !backing.contexts.count);
			assert(!fixture.session.active_admissions);
			for before.live {
				assert(fixture.session.ledger.live[it_index] == it && fixture.session.ledger.reserved[it_index] == before.reserved[it_index]);
			}

			assert(fixture.session.identities.operation_counter.next == identities.operation_counter.next);
			assert(fixture.session.identities.world_counter.next == identities.world_counter.next);
			assert(fixture.session.identities.result_counter.next == identities.result_counter.next);
		}
	);

	finish_retain(test);
	print("X5 provider revision empty backing/no allocation/charges/counters/cleanup (empty provider = %) \e[92mPASS\e[0m\n", empty_provider);
}

test_source_update_counter :: (last_token := false, late := false, direct := false) {
	test := prepared_retain(.WORLD, .REUSE);
	fixture := test.drain.fixture;
	batch := Service.begin_batch(fixture.host);
	assert(Service.set_overlay(*batch, "a.jai", "answer :: 77;"));
	probe := Registration_Probe.{};
	output_probe := Output_Probe.{direct = direct};
	if late {
		output_probe.job = .{drain = test.drain, action = .EXHAUST_OPERATION_COUNTER};
	}

	allocator := open_output_probe(*output_probe);
	before: Service.Resource_Ledger;
	identities: Service.Session_Identities;
	Service.with_lock(
		*fixture.session.gate,
		#code {
			before = fixture.session.ledger;
			identities = fixture.session.identities;
			fixture.session.faults.source_update_allocation_hook = registration_allocation_probe;
			fixture.session.faults.source_update_allocation_data = *probe;
			if !late {
				fixture.session.identities.operation_counter.next = ifx last_token
					then Service.U64_MAX - 1
					else Service.U64_MAX;
			}
		}
	);

	ok, accepted, error := Service.submit_source_batch(
		fixture.host.service,
		fixture.host.session,
		receipt_source_batch(batch)
		,, allocator
	);

	if last_token {
		assert(ok && accepted.ticket.owner_token && probe.allocations == 3 && output_probe.allocations == 1);
		polled, receipt := Service.poll(fixture.host.service, accepted.ticket);
		assert(polled);
		token_bytes := Service.little_endian(Service.U64_MAX - 1, 8);
		expected := Service.make_key("operation", fixture.host.session_identity.([] u8), token_bytes);
		assert(Service.bytes_equal(receipt.operation_identity.([] u8), expected));
		free(token_bytes.data);
		free(expected.data);
		Service.free_observation(*receipt);

		observation := await(fixture, accepted.ticket);
		assert(observation.update.kind == .PUBLISHED);
		Service.free_observation(*observation);
		release(fixture, accepted.ticket);
		second_batch := Service.begin_batch(fixture.host);
		assert(Service.set_overlay(*second_batch, "a.jai", "answer :: 88;"));
		second_ok, second, second_error := Service.submit_source_batch(fixture.host.service, fixture.host.session, receipt_source_batch(second_batch));
		assert(!second_ok && !second.ticket.owner_token && second_error.code == .ADMISSION_DENIED && second_error.admission.kind == .RESOURCE_EXHAUSTED && probe.allocations == 3);
	} else {
		assert(!ok && !accepted.ticket.owner_token && !accepted.frontier.count);
		assert(error.code == .ADMISSION_DENIED && error.admission.kind == .RESOURCE_EXHAUSTED);
		assert(probe.allocations == (ifx late then 3 else 0));
		assert(output_probe.allocations == (ifx late then 1 else 0));
		if late {
			assert(output_probe.gate_progress && output_probe.job.ok);
		}
	}

	Service.with_lock(
		*fixture.session.gate,
		#code {
			assert(fixture.session.identities.operation_counter.next == Service.U64_MAX);
			assert(!fixture.session.active_admissions);
			if !ok {
				assert(Service.bytes_equal(fixture.session.provider.accepted_frontier, batch.description.accepted_frontier));
				assert(fixture.session.identities.world_counter.next == identities.world_counter.next);
				for before.live {
					assert(fixture.session.ledger.live[it_index] == it && fixture.session.ledger.reserved[it_index] == before.reserved[it_index]);
				}
			}

			fixture.session.identities.operation_counter = identities.operation_counter;
			fixture.session.faults.source_update_allocation_hook = null;
			fixture.session.faults.source_update_allocation_data = null;
		}
	);

	free(accepted.frontier.data,, allocator);
	close_output_probe(*output_probe);
	finish_retain(test);
	print(
		"X5 source update initial/receipt-late counter exhaustion/final-token identity/no wrap/provider atomicity (last token = %, late = %, direct = %) \e[92mPASS\e[0m\n",
		last_token,
		late,
		direct
	);
}

test_source_receipt_failures :: () {
	for bool.[false, true] {
		negative_control := it;
		fixture := open("X5-source-receipt-failure");
		seed := submit(fixture, "answer :: 42;");
		world := world_of(fixture, seed);
		batch := Service.begin_batch(fixture.host);
		assert(Service.set_overlay(*batch, "a.jai", "answer :: 77;"));
		source_batch := receipt_source_batch(batch);
		before: Service.Resource_Ledger;
		Service.with_lock(
			*fixture.session.gate,
			#code {
				before = fixture.session.ledger;
				fixture.session.faults.allow_failed_submit_output = negative_control;
			}
		);

		probe: Output_Probe;
		allocator := open_output_probe(*probe);
		fail_at: s64 = 1;
		while true {
			probe.fail_at = fail_at;
			probe.allocations = 0;
			ok, accepted, error := Service.submit_source_batch(
				fixture.host.service,
				fixture.host.session,
				source_batch
				,, allocator
			);

			if !ok {
				assert(!negative_control && error.code == .ADMISSION_DENIED && error.admission.kind == .RESOURCE_EXHAUSTED);
				assert(!accepted.ticket.owner_token && !accepted.frontier.count);
				assert(probe.allocations == 1 && !probe.backing.live_bytes && !probe.backing.sizes.count);
				Service.with_lock(
					*fixture.session.gate,
					#code {
						assert(Service.bytes_equal(fixture.session.provider.accepted_frontier, source_batch.expected_frontier));
						assert(!fixture.session.active_admissions);
						for before.live {
							assert(fixture.session.ledger.live[it_index] == it && fixture.session.ledger.reserved[it_index] == before.reserved[it_index]);
						}
					}
				);

				fail_at += 1;
				continue;
			}


			assert(probe.allocations == 1 && fail_at == (ifx negative_control then 1 else 2));
			Service.with_lock(
				*fixture.session.gate,
				#code {
					assert(!Service.bytes_equal(fixture.session.provider.accepted_frontier, source_batch.expected_frontier));
					if negative_control {
						assert(!accepted.frontier.count, "\e[91mSource commit-before-copy negative control was not detected.\e[0m");
					} else {
						assert(Service.bytes_equal(fixture.session.provider.accepted_frontier, accepted.frontier));
						assert(fixture.session.provider.accepted_frontier.data != accepted.frontier.data);
						accepted.frontier[0] ^= 1;
						assert(!Service.bytes_equal(fixture.session.provider.accepted_frontier, accepted.frontier));
					}
				}
			);

			free(accepted.frontier.data,, allocator);
			observation := await(fixture, accepted.ticket);
			assert(observation.update.kind == .PUBLISHED);
			Service.free_observation(*observation);
			release(fixture, accepted.ticket);
			break;
		}

		close_output_probe(*probe);
		release(fixture, world);
		release(fixture, seed);
		close(fixture);
	}

	print("X5 source receipt allocation failure/atomic admission/copy isolation/negative control \e[92mPASS\e[0m\n");
}

test_source_receipt_interleavings :: (direct := false) {
	for Output_Action.[.REPLACE_SOURCE, .REQUEST_SHUTDOWN, .REJECT_ACTIVE_RELEASE, .OTHER_DRAIN] {
		action := it;
		for bool.[false, true] {
			fail_copy := it;
			drain := prepared_drain("X3-X5-source-receipt");
			fixture := drain.fixture;
			batch := Service.begin_batch(fixture.host);
			assert(Service.set_overlay(*batch, "a.jai", "answer :: 77;"));
			probe := Output_Probe.{
				fail_at = (ifx fail_copy then 1),
				direct = direct,
				job = .{drain = drain, action = action},
			};

			allocator := open_output_probe(*probe);
			ok, accepted, error := Service.submit_source_batch(
				fixture.host.service,
				fixture.host.session,
				receipt_source_batch(batch)
				,, allocator
			);

			assert(probe.gate_progress && probe.job.ok && probe.allocations == 1);
			if action == .REPLACE_SOURCE {
				assert(!ok && error.code == .BASE_MISMATCH && error.scope == .FRONTIER);
			} else if action == .REQUEST_SHUTDOWN {
				assert(!ok && error.code == .SERVICE_CLOSED);
			} else if fail_copy {
				assert(!ok && error.code == .ADMISSION_DENIED && error.admission.kind == .RESOURCE_EXHAUSTED);
			} else {
				assert(ok && accepted.frontier.count);
			}

			if ok {
				observation := await(fixture, accepted.ticket);
				assert(observation.update.kind == .PUBLISHED);
				Service.free_observation(*observation);
				release(fixture, accepted.ticket);
			} else {
				assert(!accepted.ticket.owner_token && !accepted.frontier.count);
			}

			free(accepted.frontier.data,, allocator);
			free_records(probe.job.records);
			close_output_probe(*probe);
			finish_drain(drain);
		}
	}

	print("X3/X5 source receipt frontier/shutdown/release/drain/failure interleavings (direct = %) \e[92mPASS\e[0m\n", direct);
}

test_analysis_receipt_failures :: () {
	for bool.[false, true] {
		negative_control := it;
		fixture := open("X5-analysis-receipt-failure");
		seed := submit(fixture, "answer :: 42;");
		world := world_of(fixture, seed);
		_, description := Service.describe_session(fixture.host.service, fixture.host.session);
		documents := ([] u8).[Service.harness_document(fixture.host, "a.jai")];
		request := Service.Analysis_Request.{
			version = Service.INTERFACE_VERSION,
			expected_frontier = description.accepted_frontier,
			documents = documents,
		};

		before: Service.Resource_Ledger;
		before_operations: s64;
		before_slots: s64;
		Service.with_lock(
			*fixture.session.gate,
			#code {
				before = fixture.session.ledger;
				before_operations = fixture.session.operations.count;
				before_slots = fixture.session.registry.slots.count;
				fixture.session.faults.allow_failed_analysis_output = negative_control;
			}
		);

		probe: Output_Probe;
		allocator := open_output_probe(*probe);
		fail_at: s64 = 1;
		while true {
			probe.fail_at = fail_at;
			probe.allocations = 0;
			ok, accepted, error := Service.request_analysis(
				fixture.host.service,
				fixture.host.session,
				request
				,, allocator
			);

			if !ok {
				assert(!negative_control && error.code == .ADMISSION_DENIED && error.admission.kind == .RESOURCE_EXHAUSTED);
				assert(!accepted.ticket.owner_token && !accepted.frontier.count);
				assert(probe.allocations == 1 && !probe.backing.live_bytes && !probe.backing.sizes.count);
				Service.with_lock(
					*fixture.session.gate,
					#code {
						assert(Service.bytes_equal(fixture.session.provider.accepted_frontier, request.expected_frontier));
						assert(fixture.session.operations.count == before_operations && fixture.session.registry.slots.count == before_slots);
						for before.live {
							assert(fixture.session.ledger.live[it_index] == it && fixture.session.ledger.reserved[it_index] == before.reserved[it_index]);
						}
					}
				);

				fail_at += 1;
				continue;
			}


			assert(probe.allocations == 1 && fail_at == (ifx negative_control then 1 else 2));
			Service.with_lock(
				*fixture.session.gate,
				#code {
					operation := fixture.session.registrations[accepted.ticket.slot].operation;
					assert(Service.bytes_equal(operation.frontier, request.expected_frontier));
					if negative_control {
						assert(!accepted.frontier.count, "\e[91mAnalysis admit-before-copy negative control was not detected.\e[0m");
					} else {
						assert(Service.bytes_equal(operation.frontier, accepted.frontier));
						assert(operation.frontier.data != accepted.frontier.data);
						accepted.frontier[0] ^= 1;
						assert(!Service.bytes_equal(operation.frontier, accepted.frontier));
						assert(Service.bytes_equal(fixture.session.provider.accepted_frontier, request.expected_frontier));
					}
				}
			);

			free(accepted.frontier.data,, allocator);
			observation := await(fixture, accepted.ticket);
			assert(observation.update.kind == .PUBLISHED);
			Service.free_observation(*observation);
			release(fixture, accepted.ticket);
			break;
		}

		close_output_probe(*probe);
		Service.free_description(*description);
		release(fixture, world);
		release(fixture, seed);
		close(fixture);
	}

	print("X5 analysis receipt allocation failure/atomic admission/copy isolation/negative control \e[92mPASS\e[0m\n");
}

test_analysis_receipt_interleavings :: (direct := false, negative_control := false) {
	for Output_Action.[.REPLACE_SOURCE, .REQUEST_SHUTDOWN, .REJECT_ACTIVE_RELEASE, .OTHER_DRAIN, .STOP_AND_RELEASE_SESSION, .TAKE_ANALYSIS_CAPACITY, .COMPLETE_WORK] {
		action := it;
		if negative_control && action != .REPLACE_SOURCE {
			continue;
		}


		for bool.[false, true] {
			fail_copy := it;
			if negative_control && fail_copy {
				continue;
			}


			drain := prepared_drain("X3-X5-analysis-receipt", held = action == .COMPLETE_WORK);
			fixture := drain.fixture;
			_, description := Service.describe_session(fixture.host.service, fixture.host.session);
			documents := ([] u8).[Service.harness_document(fixture.host, "a.jai")];
			request := Service.Analysis_Request.{
				version = Service.INTERFACE_VERSION,
				expected_frontier = description.accepted_frontier,
				documents = documents,
			};

			Service.with_lock(
				*fixture.session.gate,
				#code {
					fixture.session.faults.skip_analysis_frontier_check = negative_control;
					if action == .TAKE_ANALYSIS_CAPACITY {
						fixture.session.ledger.limits.values[Service.Limit_Name.LIVE_HANDLES] = fixture.session.ledger.live[Service.Limit_Name.LIVE_HANDLES]
							+ fixture.session.ledger.reserved[Service.Limit_Name.LIVE_HANDLES]
							+ 1;
					}
				}
			);

			probe := Output_Probe.{
				fail_at = (ifx fail_copy then 1),
				direct = direct,
				job = .{drain = drain, action = action},
			};

			allocator := open_output_probe(*probe);
			ok, accepted, error := Service.request_analysis(
				fixture.host.service,
				fixture.host.session,
				request
				,, allocator
			);

			assert(probe.gate_progress && probe.job.ok && probe.allocations == 1);
			if negative_control {
				assert(ok && Service.bytes_equal(accepted.frontier, request.expected_frontier), "\e[91mStale analysis frontier negative control was not detected.\e[0m");
			} else if action == .REPLACE_SOURCE {
				assert(!ok && error.code == .BASE_MISMATCH && error.scope == .FRONTIER);
			} else if action == .STOP_AND_RELEASE_SESSION {
				assert(!ok && error.code == .INVALID_HANDLE);
			} else if action == .REQUEST_SHUTDOWN {
				assert(!ok && error.code == .SERVICE_CLOSED);
			} else if fail_copy {
				assert(!ok && error.code == .ADMISSION_DENIED && error.admission.kind == .RESOURCE_EXHAUSTED);
			} else if action == .TAKE_ANALYSIS_CAPACITY {
				assert(!ok && error.admission.limit == .LIVE_HANDLES);
			} else {
				assert(ok && Service.bytes_equal(accepted.frontier, request.expected_frontier));
			}

			if ok {
				if !negative_control {
					observation := await(fixture, accepted.ticket);
					assert(observation.update.kind == .PUBLISHED);
					Service.free_observation(*observation);
				}

				release(fixture, accepted.ticket);
			} else {
				assert(!accepted.ticket.owner_token && !accepted.frontier.count);
			}

			if probe.job.analysis_ticket.owner_token {
				observation := await(fixture, probe.job.analysis_ticket);
				assert(observation.update.kind == .PUBLISHED);
				Service.free_observation(*observation);
				release(fixture, probe.job.analysis_ticket);
			}

			free(accepted.frontier.data,, allocator);
			free_records(probe.job.records);
			close_output_probe(*probe);
			Service.free_description(*description);
			finish_drain(drain, session_released = action == .STOP_AND_RELEASE_SESSION);
		}
	}

	print("X3/X5 analysis receipt frontier/shutdown/retirement/capacity/completion interleavings (direct = %, negative control = %) \e[92mPASS\e[0m\n", direct, negative_control);
}

assert_analysis_argument_path :: (error: Service.Operation_Error, rule: Service.Argument_Rule) {
	assert(error.code == .INVALID_ARGUMENT && error.rule == rule);
	assert(error.path.count == (ifx rule == .MISSING then 1 else 2));
	assert(error.path[0].kind == .FIELD && error.path[0].name == "documents");
	if rule != .MISSING {
		assert(error.path[1].kind == .ELEMENT && error.path[1].index == 1);
	}
}

test_analysis_argument_failures :: () {
	for Service.Argument_Rule.[.MISSING, .INCONSISTENT_BINDING, .DUPLICATE] {
		rule := it;
		for bool.[false, true] {
			negative_control := it;
			fixture := open("X5-analysis-argument-failure");
			seed := submit(fixture, "answer :: 42;");
			world := world_of(fixture, seed);
			_, description := Service.describe_session(fixture.host.service, fixture.host.session);
			document := Service.harness_document(fixture.host, "a.jai");
			documents := ([] u8).[document, document];
			request := Service.Analysis_Request.{
				version = Service.INTERFACE_VERSION,
				expected_frontier = description.accepted_frontier,
				documents = documents,
			};

			if rule == {
				case .MISSING;
					request.documents = .[];

				case .INCONSISTENT_BINDING;
					documents[1] = xx "not-registered";
			}

			before: Service.Resource_Ledger;
			before_operations: s64;
			before_slots: s64;
			Service.with_lock(
				*fixture.session.gate,
				#code {
					before = fixture.session.ledger;
					before_operations = fixture.session.operations.count;
					before_slots = fixture.session.registry.slots.count;
					fixture.session.faults.allow_failed_argument_error = negative_control;
				}
			);

			probe: Output_Probe;
			allocator := open_output_probe(*probe);
			fail_at: s64 = 1;
			while true {
				probe.allocations = 0;
				probe.fail_at = fail_at;
				ok, accepted, error := Service.request_analysis(
					fixture.host.service,
					fixture.host.session,
					request
					,, allocator
				);

				assert(!ok && !accepted.ticket.owner_token && !accepted.frontier.count && probe.allocations == 1);
				Service.with_lock(
					*fixture.session.gate,
					#code {
						assert(Service.bytes_equal(fixture.session.provider.accepted_frontier, request.expected_frontier));
						assert(fixture.session.operations.count == before_operations && fixture.session.registry.slots.count == before_slots);
						for before.live {
							assert(fixture.session.ledger.live[it_index] == it && fixture.session.ledger.reserved[it_index] == before.reserved[it_index]);
						}
					}
				);

				if negative_control {
					assert(error.code == .INVALID_ARGUMENT && !error.path.count, "\e[91mFailed argument-path allocation negative control was not detected.\e[0m");
					break;
				}


				if error.code == .ADMISSION_DENIED {
					assert(error.admission.kind == .RESOURCE_EXHAUSTED && !error.path.count);
					assert(fail_at == 1 && !probe.backing.live_bytes && !probe.backing.sizes.count);
					fail_at += 1;
					continue;
				}


				assert(fail_at == 2);
				assert_analysis_argument_path(error, rule);
				probe.fail_at = 0;
				repeated_ok, repeated, second_error := Service.request_analysis(
					fixture.host.service,
					fixture.host.session,
					request
					,, allocator
				);

				assert(!repeated_ok && !repeated.ticket.owner_token && !repeated.frontier.count);
				assert_analysis_argument_path(second_error, rule);
				assert(second_error.path.data != error.path.data);
				error.path[0].name = "changed";
				assert_analysis_argument_path(second_error, rule);
				free(error.path.data,, allocator);
				free(second_error.path.data,, allocator);
				break;
			}

			close_output_probe(*probe);
			Service.free_description(*description);
			release(fixture, world);
			release(fixture, seed);
			close(fixture);
		}
	}

	print("X5 analysis argument-path allocation failures/isolation/no admission/negative control \e[92mPASS\e[0m\n");
}

test_analysis_argument_interleavings :: (direct := false, negative_control := false) {
	for Service.Argument_Rule.[.MISSING, .INCONSISTENT_BINDING, .DUPLICATE] {
		rule := it;
		for Output_Action.[.REPLACE_SOURCE, .REQUEST_SHUTDOWN, .REJECT_ACTIVE_RELEASE, .OTHER_DRAIN, .RETIRE_AND_REUSE_SESSION] {
			action := it;
			if negative_control && action != .RETIRE_AND_REUSE_SESSION {
				continue;
			}


			for bool.[false, true] {
				fail_copy := it;
				if negative_control && fail_copy {
					continue;
				}


				drain := prepared_drain("X3-X5-analysis-argument");
				fixture := drain.fixture;
				_, description := Service.describe_session(fixture.host.service, fixture.host.session);
				document := Service.harness_document(fixture.host, "a.jai");
				documents := ([] u8).[document, document];
				request := Service.Analysis_Request.{
					version = Service.INTERFACE_VERSION,
					expected_frontier = description.accepted_frontier,
					documents = documents,
				};

				if rule == {
					case .MISSING;
						request.documents = .[];

					case .INCONSISTENT_BINDING;
						documents[1] = xx "not-registered";
				}

				Service.with_lock(
					*fixture.session.gate,
					#code {
						fixture.session.faults.allow_stale_argument_error = negative_control;
					}
				);

				probe := Output_Probe.{
					fail_at = (ifx fail_copy then 1),
					direct = direct,
					job = .{drain = drain, action = action},
				};

				allocator := open_output_probe(*probe);
				ok, accepted, error := Service.request_analysis(
					fixture.host.service,
					fixture.host.session,
					request
					,, allocator
				);

				assert(probe.gate_progress && probe.job.ok && probe.allocations == 1);
				assert(!ok && !accepted.ticket.owner_token && !accepted.frontier.count);
				if negative_control {
					assert_analysis_argument_path(error, rule);
					assert(!Service.session_of(fixture.host.service, fixture.host.session), "\e[91mStale argument-path negative control was not detected.\e[0m");
				} else if action == .RETIRE_AND_REUSE_SESSION {
					assert(error.code == .INVALID_HANDLE && error.handle_kind == .SESSION && !error.path.count);
				} else if fail_copy {
					assert(error.code == .ADMISSION_DENIED && error.admission.kind == .RESOURCE_EXHAUSTED && !error.path.count);
				} else {
					assert_analysis_argument_path(error, rule);
				}

				if probe.job.replacement_world.owner_token {
					world_ok, replacement := Service.read_world(fixture.host.service, probe.job.replacement_world);
					assert(world_ok && Service.bytes_equal(replacement.members[0].source.bytes, xx "answer :: 42;"));
					release(fixture, probe.job.replacement_world);
				}

				free(error.path.data,, allocator);
				free_records(probe.job.records);
				close_output_probe(*probe);
				Service.free_description(*description);
				finish_drain(drain, session_released = action == .RETIRE_AND_REUSE_SESSION);
			}
		}
	}

	print("X3/X5 analysis argument-path allocation/frontier/shutdown/retirement/reuse (direct = %, negative control = %) \e[92mPASS\e[0m\n", direct, negative_control);
}

Terminal_Query_Case :: enum {
	NOT_CAPTURED;
	SEMANTIC;
	EVALUATION;
	SOURCE_ABSENT;
	OBSOLETE;
}

Terminal_Query_Fixture :: struct {
	scenario: Terminal_Query_Case;
	fixture: Fixture;
	ticket: Service.Handle(.TICKET);
	newer_ticket: Service.Handle(.TICKET);
	request: Service.Query_Request;
	expected: Service.Observation;
}

prepared_terminal_query :: (scenario: Terminal_Query_Case) -> Terminal_Query_Fixture {
	fixture := open("X5-terminal-query");
	ticket: Service.Handle(.TICKET);
	if scenario == .SOURCE_ABSENT {
		batch := Service.begin_batch(fixture.host);
		assert(Service.observe_disk(*batch, "missing-query.jai"));
		ok, accepted := Service.submit_batch(*batch);
		assert(ok);
		ticket = accepted.ticket;
	} else {
		ticket = submit(fixture, "answer :: 42;");
	}

	world := world_of(fixture, ticket);
	_, backing := Service.read_world(fixture.host.service, world);
	request := Service.Query_Request.{
		version = Service.INTERFACE_VERSION,
		world = world,
		document = backing.members[0].document,
		kind = .SYNTAX_SNAPSHOT,
	};

	newer_ticket: Service.Handle(.TICKET);
	if scenario == {
		case .NOT_CAPTURED;
			request.document = xx "never-captured";

		case .SEMANTIC;
			request.kind = .SEMANTIC_QUERY;

		case .EVALUATION;
			request.kind = .COMPILER_EVALUATION;

		case .OBSOLETE;
			request.kind = .SYNTAX_DIAGNOSTICS;
			newer_ticket = submit(fixture, "answer :: 99;");
			observation := await(fixture, newer_ticket);
			assert(observation.update.kind == .PUBLISHED);
			Service.free_observation(*observation);
	}

	expected := Service.Observation.{
		kind = .QUERY,
		world_identity = xx array_copy(backing.identity.([] u8)),
		document = array_copy(request.document),
		query_kind = request.kind,
	};

	if scenario != .NOT_CAPTURED {
		expected.context_identity = array_copy(backing.members[0].context_identity);
	}

	return .{
		scenario = scenario,
		fixture = fixture,
		ticket = ticket,
		newer_ticket = newer_ticket,
		request = request,
		expected = expected,
	};
}

assert_terminal_query :: (test: Terminal_Query_Fixture, output: Service.Query_Start) {
	assert(output.kind == .TERMINAL && !output.result.owner_token && !output.waiter.owner_token);
	observation := output.observation;
	assert(observation.kind == .QUERY && observation.operation_identity.count);
	assert(Service.bytes_equal(observation.world_identity.([] u8), test.expected.world_identity.([] u8)));
	assert(Service.bytes_equal(observation.document, test.expected.document));
	assert(Service.bytes_equal(observation.context_identity, test.expected.context_identity));
	assert(observation.query_kind == test.request.kind);

	if test.scenario == {
		case .NOT_CAPTURED;
			assert(observation.query.kind == .UNAVAILABLE && observation.query.unavailable == .NOT_CAPTURED);

		case .SEMANTIC;		#through;
		case .EVALUATION;
			assert(observation.query.kind == .UNSUPPORTED && observation.query.unsupported == test.request.kind);

		case .SOURCE_ABSENT;
			assert(observation.query.kind == .UNAVAILABLE && observation.query.unavailable == .SOURCE_ABSENT);

		case .OBSOLETE;
			assert(observation.query.kind == .CANCELLED && observation.query.cancellation == .WORLD_SUPERSEDED);
	}
}

finish_terminal_query :: (test: Terminal_Query_Fixture, world_released := false, owner_released := false) {
	if owner_released {
		assert(!Service.session_of(test.fixture.host.service, test.fixture.host.session));
		assert(!test.fixture.host.service.owned_allocations && !test.fixture.host.service.owned_bytes);
		assert_no_owned_allocations();
		Service.free_observation(*test.expected);
		return;
	}


	if !world_released {
		release(test.fixture, test.request.world);
	}

	if test.newer_ticket.owner_token {
		release(test.fixture, test.newer_ticket);
	}

	release(test.fixture, test.ticket);
	Service.free_observation(*test.expected);
	close(test.fixture);
}

test_terminal_query_failures :: (negative_control := false) {
	for Terminal_Query_Case.[.NOT_CAPTURED, .SEMANTIC, .EVALUATION, .SOURCE_ABSENT, .OBSOLETE] {
		test := prepared_terminal_query(it);
		fixture := test.fixture;
		before: Service.Resource_Ledger;
		before_operations: s64;
		before_slots: s64;
		Service.with_lock(
			*fixture.session.gate,
			#code {
				before = fixture.session.ledger;
				before_operations = fixture.session.operations.count;
				before_slots = fixture.session.registry.slots.count;
				fixture.session.faults.allow_failed_terminal_query = negative_control;
			}
		);

		probe: Output_Probe;
		allocator := open_output_probe(*probe);
		fail_at: s64 = 1;
		while true {
			probe.allocations = 0;
			probe.fail_at = fail_at;
			ok, output, error := Service.query(fixture.host.service, test.request,, allocator);
			Service.with_lock(
				*fixture.session.gate,
				#code {
					assert(fixture.session.operations.count == before_operations && fixture.session.registry.slots.count == before_slots);
					for before.live {
						assert(fixture.session.ledger.live[it_index] == it && fixture.session.ledger.reserved[it_index] == before.reserved[it_index]);
					}
				}
			);

			if negative_control {
				assert(ok && output.kind == .TERMINAL && !output.observation.operation_identity.count && probe.allocations == 1, "\e[91mFailed terminal query copy negative control was not detected.\e[0m");
				Service.free_observation(*output.observation,, allocator);
				break;
			}


			if !ok {
				assert(error.code == .ADMISSION_DENIED && error.admission.kind == .RESOURCE_EXHAUSTED);
				assert(!output.result.owner_token && !output.waiter.owner_token && !output.observation.operation_identity.count);
				assert(probe.allocations == fail_at && !probe.backing.live_bytes && !probe.backing.sizes.count);
				fail_at += 1;
				continue;
			}


			assert(probe.allocations == fail_at - 1);
			assert_terminal_query(test, output);
			probe.fail_at = 0;
			second_ok, second := Service.query(fixture.host.service, test.request,, allocator);
			assert(second_ok);
			assert_terminal_query(test, second);
			assert(!Service.bytes_equal(output.observation.operation_identity.([] u8), second.observation.operation_identity.([] u8)));
			assert(output.observation.world_identity.data != second.observation.world_identity.data);
			assert(output.observation.document.data != second.observation.document.data);
			world_bytes := output.observation.world_identity.([] u8);
			world_bytes[0] ^= 1;
			output.observation.document[0] ^= 1;
			if output.observation.context_identity.count {
				assert(output.observation.context_identity.data != second.observation.context_identity.data);
				output.observation.context_identity[0] ^= 1;
			}

			assert_terminal_query(test, second);
			Service.free_observation(*output.observation,, allocator);
			Service.free_observation(*second.observation,, allocator);
			break;
		}

		close_output_probe(*probe);
		finish_terminal_query(test);
	}

	print("X5 terminal query every allocation failure/independent observations/no admission (negative control = %) \e[92mPASS\e[0m\n", negative_control);
}

test_terminal_query_interleavings :: (direct := false, negative_control := false) {
	for Terminal_Query_Case.[.NOT_CAPTURED, .SEMANTIC, .EVALUATION, .SOURCE_ABSENT, .OBSOLETE] {
		scenario := it;
		for Output_Action.[.REPLACE_SOURCE, .REQUEST_SHUTDOWN, .REJECT_ACTIVE_RELEASE, .OTHER_DRAIN, .RELEASE_QUERY_WORLD, .RETIRE_QUERY_OWNER] {
			action := it;
			if negative_control && action != .RELEASE_QUERY_WORLD && action != .RETIRE_QUERY_OWNER {
				continue;
			}


			for bool.[false, true] {
				fail_copy := it;
				if negative_control && fail_copy {
					continue;
				}


				test := prepared_terminal_query(scenario);
				fixture := test.fixture;
				probe := Output_Probe.{
					fail_at = (ifx fail_copy then 2),
					direct = direct,
					job = .{
						drain = .{fixture = fixture, ticket = test.ticket, world = test.request.world},
						action = action,
						retirement_ticket = test.newer_ticket,
					},
				};

				if action == .RELEASE_QUERY_WORLD {
					retained, surviving := Service.retain(fixture.host.service, test.request.world);
					assert(retained);
					probe.job.surviving_world = surviving;
				}

				Service.with_lock(
					*fixture.session.gate,
					#code {
						fixture.session.faults.allow_stale_terminal_query = negative_control;
					}
				);

				allocator := open_output_probe(*probe);
				ok, output, error := Service.query(fixture.host.service, test.request,, allocator);
				assert(probe.gate_progress && probe.job.ok);
				retired := action == .RELEASE_QUERY_WORLD || action == .RETIRE_QUERY_OWNER;
				if negative_control {
					assert(ok, "\e[91mStale terminal query negative control was not detected.\e[0m");
					assert_terminal_query(test, output);
				} else if retired {
					assert(!ok && error.code == .INVALID_HANDLE && error.handle_kind == .WORLD);
				} else if fail_copy {
					assert(!ok && error.code == .ADMISSION_DENIED && error.admission.kind == .RESOURCE_EXHAUSTED);
				} else {
					assert(ok);
					assert_terminal_query(test, output);
				}

				if !ok {
					assert(!output.result.owner_token && !output.waiter.owner_token && !output.observation.operation_identity.count);
				}

				if probe.job.replacement_world.owner_token {
					world_ok, replacement := Service.read_world(fixture.host.service, probe.job.replacement_world);
					assert(world_ok && Service.bytes_equal(replacement.identity.([] u8), test.expected.world_identity.([] u8)));
					release(fixture, probe.job.replacement_world);
					release(fixture, probe.job.surviving_world);
				}

				Service.free_observation(*output.observation,, allocator);
				free_records(probe.job.records);
				close_output_probe(*probe);
				finish_terminal_query(
					test,
					world_released = action == .RELEASE_QUERY_WORLD,
					owner_released = action == .RETIRE_QUERY_OWNER
				);
			}
		}
	}

	print("X3/X5 terminal query allocation/frontier/shutdown/world reuse/owner retirement (direct = %, negative control = %) \e[92mPASS\e[0m\n", direct, negative_control);
}

Result_Access_Case :: enum {
	SOURCE_REVERSED;
	SOURCE_PAST_END;
	NODE;
	TOKEN;
	RECOVERY;
}

result_access_field :: (scenario: Result_Access_Case) -> string {
	if scenario == {
		case .SOURCE_REVERSED;	#through;
		case .SOURCE_PAST_END;
			return "end_byte";

		case .NODE;
			return "node_id";

		case .TOKEN;
			return "token_id";

		case .RECOVERY;
			return "recovery_id";
	}


	return "";
}

result_access_error :: (fixture: Fixture, handle: Service.Handle(.RESULT), scenario: Result_Access_Case) -> Service.Operation_Error {
	described, description := Service.read_result(fixture.host.service, handle);
	assert(described && description.backing);
	error: Service.Operation_Error;
	if scenario == {
		case .SOURCE_REVERSED;
			ok, output, failure := Service.read_source(fixture.host.service, handle, 1, 0);
			assert(!ok && !output.count && !output.data);
			error = failure;

		case .SOURCE_PAST_END;
			ok, output, failure := Service.read_source(fixture.host.service, handle, 0, xx (description.backing.source.count + 1));
			assert(!ok && !output.count && !output.data);
			error = failure;

		case .NODE;
			ok, output, failure := Service.resolve_node(fixture.host.service, handle, xx description.backing.nodes.count);
			assert(!ok && !output);
			error = failure;

		case .TOKEN;
			ok, output, failure := Service.resolve_token(fixture.host.service, handle, xx description.backing.tokens.count);
			assert(!ok && !output);
			error = failure;

		case .RECOVERY;
			ok, output, failure := Service.resolve_recovery(fixture.host.service, handle, xx description.backing.recoveries.count);
			assert(!ok && !output);
			error = failure;
	}

	return error;
}

assert_result_argument_path :: (error: Service.Operation_Error, scenario: Result_Access_Case) {
	assert(error.code == .INVALID_ARGUMENT && error.rule == .OUT_OF_RANGE);
	assert(error.path.count == 1 && error.path[0].kind == .FIELD && error.path[0].name == result_access_field(scenario));
}

test_result_argument_failures :: () {
	for Service.Query_Kind.[.SYNTAX_SNAPSHOT, .SYNTAX_DIAGNOSTICS, .SYNTAX_DECLARATION_INDEX] {
		kind := it;
		for Result_Access_Case.[.SOURCE_REVERSED, .SOURCE_PAST_END, .NODE, .TOKEN, .RECOVERY] {
			scenario := it;
			for bool.[false, true] {
				negative_control := it;
				drain := prepared_drain("X5-result-argument");
				fixture := drain.fixture;
				started := query(fixture, drain.world, kind);
				assert(started.kind == .AVAILABLE);
				source_ok, source := Service.read_source(fixture.host.service, started.result, 0, 1);
				node_ok, node := Service.resolve_node(fixture.host.service, started.result, 0);
				token_ok, token := Service.resolve_token(fixture.host.service, started.result, 0);
				assert(source_ok && Service.bytes_equal(source, xx "a") && node_ok && node && token_ok && token);
				before: Service.Resource_Ledger;
				before_operations: s64;
				before_slots: s64;
				Service.with_lock(
					*fixture.session.gate,
					#code {
						before = fixture.session.ledger;
						before_operations = fixture.session.operations.count;
						before_slots = fixture.session.registry.slots.count;
						fixture.session.faults.allow_failed_argument_error = negative_control;
					}
				);

				probe: Output_Probe;
				allocator := open_output_probe(*probe);
				fail_at: s64 = 1;
				while true {
					probe.allocations = 0;
					probe.fail_at = fail_at;
					error := result_access_error(fixture, started.result, scenario,, allocator);
					assert(probe.allocations == 1);
					Service.with_lock(
						*fixture.session.gate,
						#code {
							assert(fixture.session.operations.count == before_operations && fixture.session.registry.slots.count == before_slots);
							for before.live {
								assert(fixture.session.ledger.live[it_index] == it && fixture.session.ledger.reserved[it_index] == before.reserved[it_index]);
							}
						}
					);

					if negative_control {
						assert(error.code == .INVALID_ARGUMENT && !error.path.count, "\e[91mFailed result argument-path negative control was not detected.\e[0m");
						break;
					}


					if error.code == .ADMISSION_DENIED {
						assert(error.admission.kind == .RESOURCE_EXHAUSTED && !error.path.count);
						assert(fail_at == 1 && !probe.backing.live_bytes && !probe.backing.sizes.count);
						fail_at += 1;
						continue;
					}


					assert(fail_at == 2);
					assert_result_argument_path(error, scenario);
					probe.fail_at = 0;
					second_error := result_access_error(fixture, started.result, scenario,, allocator);
					assert_result_argument_path(second_error, scenario);
					assert(second_error.path.data != error.path.data);
					error.path[0].name = "changed";
					assert_result_argument_path(second_error, scenario);
					free(error.path.data,, allocator);
					free(second_error.path.data,, allocator);
					break;
				}

				close_output_probe(*probe);
				release(fixture, started.result);
				finish_drain(drain);
			}
		}
	}

	print("X5 result argument-path allocation failures/all result kinds/borrowed reads/no admission/negative controls \e[92mPASS\e[0m\n");
}

test_result_argument_interleavings :: (direct := false, negative_control := false) {
	for Service.Query_Kind.[.SYNTAX_SNAPSHOT, .SYNTAX_DIAGNOSTICS, .SYNTAX_DECLARATION_INDEX] {
		kind := it;
		for Result_Access_Case.[.SOURCE_REVERSED, .SOURCE_PAST_END, .NODE, .TOKEN, .RECOVERY] {
			scenario := it;
			for Output_Action.[.REPLACE_SOURCE, .REQUEST_SHUTDOWN, .REJECT_ACTIVE_RELEASE, .OTHER_DRAIN, .RELEASE_ACCESS_RESULT, .RETIRE_ACCESS_OWNER] {
				action := it;
				if negative_control && action != .RELEASE_ACCESS_RESULT && action != .RETIRE_ACCESS_OWNER {
					continue;
				}


				for bool.[false, true] {
					fail_copy := it;
					if negative_control && fail_copy {
						continue;
					}


					drain := prepared_drain("X3-X5-result-argument");
					fixture := drain.fixture;
					started := query(fixture, drain.world, kind);
					assert(started.kind == .AVAILABLE);
					probe := Output_Probe.{
						fail_at = (ifx fail_copy then 1),
						direct = direct,
						job = .{drain = drain, action = action, access_result = started.result},
					};

					if action == .RELEASE_ACCESS_RESULT {
						retained, surviving := Service.retain(fixture.host.service, started.result);
						assert(retained);
						probe.job.surviving_result = surviving;
					}

					Service.with_lock(
						*fixture.session.gate,
						#code {
							fixture.session.faults.allow_stale_argument_error = negative_control;
						}
					);

					allocator := open_output_probe(*probe);
					error := result_access_error(fixture, started.result, scenario,, allocator);
					assert(probe.gate_progress && probe.job.ok && probe.allocations == 1);
					retired := action == .RELEASE_ACCESS_RESULT || action == .RETIRE_ACCESS_OWNER;
					if negative_control {
						assert_result_argument_path(error, scenario);
						old_ok := Service.read_result(fixture.host.service, started.result);
						assert(!old_ok, "\e[91mStale result argument-path negative control was not detected.\e[0m");
					} else if retired {
						assert(error.code == .INVALID_HANDLE && error.handle_kind == .RESULT && !error.path.count);
					} else if fail_copy {
						assert(error.code == .ADMISSION_DENIED && error.admission.kind == .RESOURCE_EXHAUSTED && !error.path.count);
					} else {
						assert_result_argument_path(error, scenario);
					}

					if probe.job.replacement.owner_token {
						source_ok, source := Service.read_source(fixture.host.service, probe.job.replacement, 0, 1);
						assert(source_ok && Service.bytes_equal(source, xx "a"));
						release(fixture, probe.job.replacement);
						release(fixture, probe.job.surviving_result);
					}

					free(error.path.data,, allocator);
					free_records(probe.job.records);
					close_output_probe(*probe);
					if action == .RETIRE_ACCESS_OWNER {
						assert(!Service.session_of(fixture.host.service, fixture.host.session));
						assert(!fixture.host.service.owned_allocations && !fixture.host.service.owned_bytes);
						assert_no_owned_allocations();
					} else {
						if action != .RELEASE_ACCESS_RESULT {
							release(fixture, started.result);
						}

						finish_drain(drain);
					}
				}
			}
		}
	}

	print("X3/X5 result argument-path allocation/source/shutdown/result reuse/owner retirement (direct = %, negative control = %) \e[92mPASS\e[0m\n", direct, negative_control);
}

Coordinator_Argument_Case :: enum {
	WORKSPACE;
	WAIT_TICKET;
	WAIT_WAITER;
	WAIT_SHUTDOWN;
	DRAIN_MAXIMUM;
}

Coordinator_Argument_Fixture :: struct {
	scenario: Coordinator_Argument_Case;
	drain: Drain_Fixture;
	shutdown: Service.Handle(.SHUTDOWN);
}

prepared_coordinator_argument :: (scenario: Coordinator_Argument_Case) -> Coordinator_Argument_Fixture {
	drain := prepared_drain("X5-coordinator-argument");
	shutdown: Service.Handle(.SHUTDOWN);
	if scenario == .WAIT_SHUTDOWN {
		ok: bool;
		ok, shutdown = Service.request_shutdown(drain.fixture.host.service, drain.fixture.host.session);
		assert(ok);
		observation := await(drain.fixture, shutdown);
		Service.free_observation(*observation);
	}

	return .{scenario = scenario, drain = drain, shutdown = shutdown};
}

coordinator_argument_error :: (test: Coordinator_Argument_Fixture) -> Service.Operation_Error {
	fixture := test.drain.fixture;
	deadline := Service.Deadline.{clock_identity = xx "wrong-clock"};
	error: Service.Operation_Error;
	if test.scenario == {
		case .WORKSPACE;
			ok, output, failure := Service.acquire_world(
				fixture.host.service,
				.{kind = .HEAD, session = fixture.host.session, workspace = xx "wrong-workspace"}
			);

			assert(!ok && !output.world.owner_token && !output.operation_identity.count);
			error = failure;

		case .WAIT_TICKET;
			ok, output, failure := Service.wait(fixture.host.service, test.drain.ticket, deadline);
			assert(!ok && !output.observation.operation_identity.count);
			error = failure;

		case .WAIT_WAITER;
			ok, output, failure := Service.wait(fixture.host.service, test.drain.first, deadline);
			assert(!ok && !output.observation.operation_identity.count);
			error = failure;

		case .WAIT_SHUTDOWN;
			ok, output, failure := Service.wait(fixture.host.service, test.shutdown, deadline);
			assert(!ok && !output.observation.operation_identity.count);
			error = failure;

		case .DRAIN_MAXIMUM;
			maximum := fixture.session.ledger.limits.values[Service.Limit_Name.ELEMENTS_PER_LIST] + 1;
			ok, output, failure := Service.drain_completions(fixture.host.service, fixture.host.session, xx maximum);
			assert(!ok && !output.count && !output.data);
			error = failure;
	}

	return error;
}

assert_coordinator_argument_path :: (error: Service.Operation_Error, scenario: Coordinator_Argument_Case) {
	assert(error.code == .INVALID_ARGUMENT && error.path.count && error.path[0].kind == .FIELD);
	if scenario == {
		case .WORKSPACE;
			assert(error.rule == .INCONSISTENT_BINDING && error.path.count == 1 && error.path[0].name == "workspace");

		case .DRAIN_MAXIMUM;
			assert(error.rule == .OUT_OF_RANGE && error.path.count == 1 && error.path[0].name == "maximum");

		case .WAIT_TICKET;	#through;
		case .WAIT_WAITER;	#through;
		case .WAIT_SHUTDOWN;
			assert(error.rule == .INCONSISTENT_BINDING && error.path.count == 2 && error.path[0].name == "deadline");
			assert(error.path[1].kind == .FIELD && error.path[1].name == "clock_identity");
	}
}

finish_coordinator_argument :: (test: Coordinator_Argument_Fixture, retired_handle := false, owner_released := false) {
	fixture := test.drain.fixture;
	if owner_released {
		assert(!Service.session_of(fixture.host.service, fixture.host.session));
		assert(!fixture.host.service.owned_allocations && !fixture.host.service.owned_bytes);
		assert_no_owned_allocations();
		return;
	}


	if test.shutdown.owner_token && !retired_handle {
		release(fixture, test.shutdown);
	}

	finish_drain(
		test.drain,
		first_released = retired_handle && test.scenario == .WAIT_WAITER,
		session_released = retired_handle && (test.scenario == .WORKSPACE || test.scenario == .DRAIN_MAXIMUM),
		ticket_released = retired_handle && test.scenario == .WAIT_TICKET
	);
}

test_coordinator_argument_failures :: () {
	for Coordinator_Argument_Case.[.WORKSPACE, .WAIT_TICKET, .WAIT_WAITER, .WAIT_SHUTDOWN, .DRAIN_MAXIMUM] {
		scenario := it;
		for bool.[false, true] {
			negative_control := it;
			test := prepared_coordinator_argument(scenario);
			fixture := test.drain.fixture;
			before: Service.Resource_Ledger;
			before_operations: s64;
			before_slots: s64;
			before_completions: s64;
			Service.with_lock(
				*fixture.session.gate,
				#code {
					before = fixture.session.ledger;
					before_operations = fixture.session.operations.count;
					before_slots = fixture.session.registry.slots.count;
					before_completions = fixture.session.completions.count;
					fixture.session.faults.allow_failed_argument_error = negative_control;
				}
			);

			probe: Output_Probe;
			allocator := open_output_probe(*probe);
			fail_at: s64 = 1;
			while true {
				probe.allocations = 0;
				probe.fail_at = fail_at;
				error := coordinator_argument_error(test,, allocator);
				assert(probe.allocations == 1);
				Service.with_lock(
					*fixture.session.gate,
					#code {
						assert(fixture.session.operations.count == before_operations && fixture.session.registry.slots.count == before_slots);
						assert(fixture.session.completions.count == before_completions);
						for before.live {
							assert(fixture.session.ledger.live[it_index] == it && fixture.session.ledger.reserved[it_index] == before.reserved[it_index]);
						}
					}
				);

				if negative_control {
					assert(error.code == .INVALID_ARGUMENT && !error.path.count, "\e[91mFailed coordinator argument-path negative control was not detected.\e[0m");
					break;
				}


				if error.code == .ADMISSION_DENIED {
					assert(error.admission.kind == .RESOURCE_EXHAUSTED && !error.path.count);
					assert(fail_at == 1 && !probe.backing.live_bytes && !probe.backing.sizes.count);
					fail_at += 1;
					continue;
				}


				assert(fail_at == 2);
				assert_coordinator_argument_path(error, scenario);
				probe.fail_at = 0;
				second_error := coordinator_argument_error(test,, allocator);
				assert_coordinator_argument_path(second_error, scenario);
				assert(second_error.path.data != error.path.data);
				error.path[0].name = "changed";
				if error.path.count == 2 {
					error.path[1].name = "changed";
				}

				assert_coordinator_argument_path(second_error, scenario);
				free(error.path.data,, allocator);
				free(second_error.path.data,, allocator);
				break;
			}

			close_output_probe(*probe);
			finish_coordinator_argument(test);
		}
	}

	print("X5 coordinator selector/deadline/maximum diagnostic failures/isolation/no admission/negative controls \e[92mPASS\e[0m\n");
}

retire_coordinator_argument :: (job: *Output_Interleaving, release_owner: bool) {
	fixture := job.drain.fixture;
	shutdown := job.coordinator_shutdown;
	if !shutdown.owner_token {
		ok: bool;
		ok, shutdown = Service.request_shutdown(fixture.host.service, fixture.host.session);
		assert(ok);
	}

	observation := await(fixture, shutdown);
	Service.free_observation(*observation);
	if job.coordinator_case != .WAIT_SHUTDOWN {
		release(fixture, shutdown);
	}

	slot := fixture.host.session.slot;
	generation := fixture.host.session.generation;
	if job.coordinator_case == {
		case .WORKSPACE;	#through;
		case .DRAIN_MAXIMUM;
			job.ok = Service.release(fixture.host.service, fixture.host.session);

		case .WAIT_TICKET;
			slot = job.drain.ticket.slot;
			generation = job.drain.ticket.generation;
			job.ok = Service.release(fixture.host.service, job.drain.ticket);

		case .WAIT_WAITER;
			slot = job.drain.first.slot;
			generation = job.drain.first.generation;
			job.ok = Service.release(fixture.host.service, job.drain.first);

		case .WAIT_SHUTDOWN;
			slot = shutdown.slot;
			generation = shutdown.generation;
			job.ok = Service.release(fixture.host.service, shutdown);
	}

	assert(job.ok);
	if !release_owner {
		retained, replacement := Service.retain(fixture.host.service, job.drain.world);
		assert(retained && replacement.slot == slot && replacement.generation != generation);
		job.replacement_world = replacement;
		return;
	}


	if job.coordinator_case != .WORKSPACE && job.coordinator_case != .DRAIN_MAXIMUM {
		release(fixture, fixture.host.session);
	}

	if job.coordinator_case != .WAIT_WAITER {
		release(fixture, job.drain.first);
	}

	release(fixture, job.drain.second);
	if job.coordinator_case != .WAIT_TICKET {
		release(fixture, job.drain.ticket);
	}

	release(fixture, job.drain.world);
}

test_coordinator_argument_interleavings :: (direct := false, negative_control := false) {
	for Coordinator_Argument_Case.[.WORKSPACE, .WAIT_TICKET, .WAIT_WAITER, .WAIT_SHUTDOWN, .DRAIN_MAXIMUM] {
		scenario := it;
		for Output_Action.[.REPLACE_SOURCE, .REQUEST_SHUTDOWN, .REJECT_ACTIVE_RELEASE, .OTHER_DRAIN, .RETIRE_COORDINATOR_HANDLE, .RETIRE_COORDINATOR_OWNER] {
			action := it;
			retired := action == .RETIRE_COORDINATOR_HANDLE || action == .RETIRE_COORDINATOR_OWNER;
			if negative_control && !retired {
				continue;
			}


			if scenario == .WAIT_SHUTDOWN && (action == .REPLACE_SOURCE || action == .REJECT_ACTIVE_RELEASE) {
				continue;
			}


			for bool.[false, true] {
				fail_copy := it;
				if negative_control && fail_copy {
					continue;
				}


				test := prepared_coordinator_argument(scenario);
				fixture := test.drain.fixture;
				probe := Output_Probe.{
					fail_at = (ifx fail_copy then 1),
					direct = direct,
					job = .{
						drain = test.drain,
						action = action,
						coordinator_case = scenario,
						coordinator_shutdown = test.shutdown,
					},
				};

				Service.with_lock(
					*fixture.session.gate,
					#code {
						fixture.session.faults.allow_stale_argument_error = negative_control;
					}
				);

				allocator := open_output_probe(*probe);
				error := coordinator_argument_error(test,, allocator);
				assert(probe.gate_progress && probe.job.ok && probe.allocations == 1);
				if negative_control {
					assert_coordinator_argument_path(error, scenario);
				} else if retired {
					expected_kind := Service.Handle_Kind.SESSION;
					if scenario == {
						case .WAIT_TICKET;
							expected_kind = .TICKET;

						case .WAIT_WAITER;
							expected_kind = .WAITER;

						case .WAIT_SHUTDOWN;
							expected_kind = .SHUTDOWN;
					}

					assert(error.code == .INVALID_HANDLE && error.handle_kind == expected_kind && !error.path.count);
				} else if fail_copy {
					assert(error.code == .ADMISSION_DENIED && error.admission.kind == .RESOURCE_EXHAUSTED && !error.path.count);
				} else {
					assert_coordinator_argument_path(error, scenario);
				}

				if probe.job.replacement_world.owner_token {
					world_ok, replacement := Service.read_world(fixture.host.service, probe.job.replacement_world);
					assert(world_ok && Service.bytes_equal(replacement.members[0].source.bytes, xx "answer :: 42;"));
					release(fixture, probe.job.replacement_world);
				}

				free(error.path.data,, allocator);
				free_records(probe.job.records);
				close_output_probe(*probe);
				finish_coordinator_argument(
					test,
					retired_handle = action == .RETIRE_COORDINATOR_HANDLE,
					owner_released = action == .RETIRE_COORDINATOR_OWNER
				);
			}
		}
	}

	print("X3/X5 coordinator diagnostic allocation/source/shutdown/handle reuse/owner retirement (direct = %, negative control = %) \e[92mPASS\e[0m\n", direct, negative_control);
}

Retain_Backing_Case :: enum {
	ARRAYS;
	OBJECT;
	REUSE;
}

Retain_Fixture :: struct (K: Service.Handle_Kind) {
	drain: Drain_Fixture;
	source: Service.Handle(K);
	held: [..] Service.Handle(K);
}

prepared_retain :: ($K: Service.Handle_Kind, scenario: Retain_Backing_Case, held := false, acquisition := false) -> Retain_Fixture(K) {
	test := Retain_Fixture(K).{drain = prepared_drain("X3-X5-retain-backing", held = held)};
	fixture := test.drain.fixture;
	#if K == .WORLD {
		ok: bool;
		ok, test.source = Service.retain(fixture.host.service, test.drain.world);
		assert(ok);
	} else {
		if acquisition {
			ok, acquired := Service.acquire_result(fixture.host.service, test.drain.first);
			assert(ok && acquired.kind == .ACQUIRED);
			test.source = acquired.result;
		} else {
			started := query(fixture, test.drain.world, .SYNTAX_SNAPSHOT);
			assert(started.kind == .AVAILABLE);
			test.source = started.result;
		}
	}

	while true {
		room: bool;
		Service.with_lock(
			*fixture.session.gate,
			#code {
				room = !!fixture.session.registry.free_slots.count
					|| fixture.session.registry.slots.count < fixture.session.registry.slots.allocated;
			}
		);

		if !room {
			break;
		}


		ok, duplicate := Service.retain(fixture.host.service, test.source);
		assert(ok);
		array_add(*test.held, duplicate);
	}


	if scenario != .ARRAYS {
		ok, duplicate := Service.retain(fixture.host.service, test.source);
		assert(ok);
		if scenario == .REUSE {
			release(fixture, duplicate);
		} else {
			array_add(*test.held, duplicate);
		}
	}

	return test;
}

finish_retain :: (test: Retain_Fixture($K), source_released := false, owner_released := false, held := false) {
	if owner_released {
		array_free(test.held);
		assert(!test.drain.fixture.host.service.owned_allocations && !test.drain.fixture.host.service.owned_bytes);
		assert_no_owned_allocations();
		return;
	}


	for test.held {
		release(test.drain.fixture, it);
	}

	array_free(test.held);
	if !source_released {
		release(test.drain.fixture, test.source);
	}

	finish_drain(test.drain, held = held);
}

Registration_Probe :: struct {
	allocations: s64;
	fail_at: s64;
	job_at: s64 = 1;
	direct: bool;
	running: bool;
	guard: *Registration_Probe;
	gate_progress: bool;
	job: Output_Interleaving;
	track_shutdown: bool;
	shutdown_references: s64;
	shutdown_live: s64;
	track_waiter: bool;
	waiter_ledger: Service.Resource_Ledger;
	track_source: bool;
	source_active_admissions: s64;
	source_document: [] u8;
	source_references: s64;
	track_world: *Service.World;
	world_references: s64;
	callback_identities: Service.Session_Identities;
	track_result: *Service.Query_Result;
	result_references: s64;
}

registration_allocation_probe :: (size: s64, data: *void) -> bool {
	probe := data.(*Registration_Probe);
	if probe.running || (probe.guard && probe.guard.running) {
		return true;
	}


	probe.allocations += 1;
	if probe.allocations == probe.job_at && probe.job.action != .NONE {
		push_allocator(context.default_allocator);

		probe.running = true;
		thread := Thread.{data = *probe.job};
		if probe.direct {
			output_interleaving_job(*thread);
			probe.gate_progress = true;
		} else {
			assert(thread_init(*thread, output_interleaving_job));
			thread_start(*thread);
			probe.gate_progress = thread_is_done(*thread, 10_000);
			assert(probe.gate_progress, "\e[91mRegistration backing allocation held the state gate.\e[0m");
			thread_deinit(*thread);
		}

		if probe.track_source {
			session := probe.job.drain.fixture.session;
			Service.with_lock(
				*session.gate,
				#code {
					probe.waiter_ledger = session.ledger;
					probe.callback_identities = session.identities;
					probe.source_active_admissions = session.active_admissions;
					if probe.source_document.count {
						state := Service.find_document(session.provider, probe.source_document);
						assert(state && state.has_overlay && state.overlay.source);
						probe.source_references = state.overlay.source.references;
					}
				}
			);
		}

		if probe.track_shutdown && probe.job.action != .RETIRE_RETAIN_OWNER {
			session := probe.job.drain.fixture.session;
			Service.with_lock(
				*session.gate,
				#code {
					probe.shutdown_references = session.shutdown.registrations;
					probe.shutdown_live = session.ledger.live[Service.Limit_Name.LIVE_HANDLES];
				}
			);
		}

		if probe.track_result {
			session := probe.job.drain.fixture.session;
			Service.with_lock(
				*session.gate,
				#code {
					probe.result_references = probe.track_result.references;
				}
			);
		}

		if probe.track_world {
			session := probe.job.drain.fixture.session;
			Service.with_lock(
				*session.gate,
				#code {
					probe.world_references = probe.track_world.references;
					probe.callback_identities = session.identities;
				}
			);
		}

		if probe.track_waiter && probe.job.action != .RETIRE_RETAIN_OWNER {
			session := probe.job.drain.fixture.session;
			Service.with_lock(
				*session.gate,
				#code {
					probe.waiter_ledger = session.ledger;
				}
			);
		}

		probe.running = false;
	}

	return probe.allocations != probe.fail_at;
}

test_retain_backing_failures :: ($K: Service.Handle_Kind, acquisition := false) {
	for Retain_Backing_Case.[.ARRAYS, .OBJECT, .REUSE] {
		scenario := it;
		allocation_count := ifx scenario == .ARRAYS
			then 3
			else ifx scenario == .OBJECT
				then 1
				else 0;

		for 1..allocation_count + 1 {
			fail_at := it;
			test := prepared_retain(K, scenario, acquisition = acquisition);
			fixture := test.drain.fixture;
			session := fixture.session;
			probe := Registration_Probe.{fail_at = fail_at};
			before: Service.Resource_Ledger;
			before_slots: [] Service.Registration_Slot;
			before_registrations: s64;
			before_free: s64;
			before_references: s64;
			before_identities: Service.Session_Identities;
			Service.with_lock(
				*session.gate,
				#code {
					before = session.ledger;
					before_identities = session.identities;
					before_slots = array_copy(session.registry.slots);
					before_registrations = session.registrations.count;
					before_free = session.registry.free_slots.count;
					#if K == .WORLD {
						before_references = session.registrations[test.source.slot].world.references;
					} else {
						before_references = session.registrations[test.source.slot].result.references;
					}

					session.faults.registration_allocation_hook = registration_allocation_probe;
					session.faults.registration_allocation_data = *probe;
				}
			);

			ok, duplicate, error := register_retain_fixture(test, acquisition);
			assert(probe.allocations == min(fail_at, allocation_count));
			Service.with_lock(
				*session.gate,
				#code {
					session.faults.registration_allocation_hook = null;
					session.faults.registration_allocation_data = null;
					assert(!session.registry.slots[session.shutdown_registration.slot].live);
					if fail_at <= allocation_count {
						assert(!ok && !duplicate.owner_token && error.code == .ADMISSION_DENIED && error.admission.kind == .RESOURCE_EXHAUSTED);
						assert(session.registry.slots.count == before_slots.count && session.registrations.count == before_registrations);
						assert(session.registry.free_slots.count == before_free);
						for before_slots {
							current := session.registry.slots[it_index];
							assert(current.generation == it.generation && current.kind == it.kind && current.live == it.live && current.retired == it.retired);
						}

						for before.live {
							assert(session.ledger.live[it_index] == it && session.ledger.reserved[it_index] == before.reserved[it_index]);
						}
					} else {
						assert(ok && duplicate.owner_service == test.source.owner_service && duplicate.owner_token == test.source.owner_token);
						assert(Service.handle_is_live(*session.registry, duplicate));
						assert(session.ledger.live[Service.Limit_Name.LIVE_HANDLES] == before.live[Service.Limit_Name.LIVE_HANDLES] + 1);
						if scenario == .REUSE {
							assert(duplicate.slot < xx before_slots.count && duplicate.generation == before_slots[duplicate.slot].generation + 1);
						} else {
							assert(duplicate.slot == xx before_slots.count && duplicate.generation == 1);
						}
					}

					#if K == .WORLD {
						assert(session.registrations[test.source.slot].world.references == before_references + (ifx ok then 1));
					} else {
						assert(session.registrations[test.source.slot].result.references == before_references + (ifx ok then 1));
					}

					if acquisition {
						assert(session.registrations[test.drain.first.slot].terminal);
						assert(session.registrations[test.drain.first.slot].observation.query.kind == .AVAILABLE);
						assert(session.identities.operation_counter.next == before_identities.operation_counter.next);
						assert(session.identities.world_counter.next == before_identities.world_counter.next);
						assert(session.identities.result_counter.next == before_identities.result_counter.next);
					}
				}
			);

			if ok {
				release(fixture, duplicate);
			}

			free(before_slots.data);
			finish_retain(test);
		}
	}

	print(
		"X5 registration array/object failure/reuse/generation/charge/reference atomicity (kind = %, result acquisition = %) \e[92mPASS\e[0m\n",
		K,
		acquisition
	);
}

register_retain_fixture :: (test: Retain_Fixture($K), acquisition: bool) -> (ok: bool, handle: Service.Handle(K), error: Service.Operation_Error) {
	#if K == .RESULT {
		if acquisition {
			ok, acquired, error := Service.acquire_result(test.drain.fixture.host.service, test.drain.first);
			return ok, acquired.result, error;
		}
	}


	ok, handle, error := Service.retain(test.drain.fixture.host.service, test.source);
	return ok, handle, error;
}

query_immediate_fixture :: (test: Retain_Fixture(.WORLD), kind: Service.Query_Kind) -> (ok: bool, started: Service.Query_Start, error: Service.Operation_Error) {
	ok, started, error := Service.query(
		test.drain.fixture.host.service,
		.{
			version = Service.INTERFACE_VERSION,
			world = test.source,
			document = Service.harness_document(test.drain.fixture.host, "a.jai"),
			kind = kind,
		}
	);

	return ok, started, error;
}

assert_immediate_result :: (fixture: Fixture, handle: Service.Handle(.RESULT), world: *Service.World, kind: Service.Query_Kind, token: u64) {
	ok, description := Service.read_result(fixture.host.service, handle);
	assert(ok && description.kind == kind);
	assert(Service.bytes_equal(description.world_identity.([] u8), world.identity.([] u8)));
	token_bytes := Service.little_endian(token, 8);
	expected := Service.make_key("result", fixture.host.session_identity.([] u8), token_bytes);
	assert(Service.bytes_equal(description.result_identity.([] u8), expected));
	free(token_bytes.data);
	free(expected.data);
}

test_immediate_result_failures :: () {
	for Service.Query_Kind.[.SYNTAX_SNAPSHOT, .SYNTAX_DIAGNOSTICS, .SYNTAX_DECLARATION_INDEX] {
		kind := it;
		for Retain_Backing_Case.[.ARRAYS, .OBJECT, .REUSE] {
			scenario := it;
			allocation_count := ifx scenario == .ARRAYS
				then 5
				else ifx scenario == .OBJECT
					then 3
					else 2;

			for 1..allocation_count + 1 {
				fail_at := it;
				test := prepared_retain(.WORLD, scenario);
				fixture := test.drain.fixture;
				before: Service.Resource_Ledger;
				identities: Service.Session_Identities;
				slots: [] Service.Registration_Slot;
				free_count: s64;
				registrations: s64;
				world: *Service.World;
				references: s64;
				probe := Registration_Probe.{fail_at = fail_at};
				Service.with_lock(
					*fixture.session.gate,
					#code {
						before = fixture.session.ledger;
						identities = fixture.session.identities;
						slots = array_copy(fixture.session.registry.slots);
						free_count = fixture.session.registry.free_slots.count;
						registrations = fixture.session.registrations.count;
						world = fixture.session.registrations[test.source.slot].world;
						references = world.references;
						fixture.session.faults.registration_allocation_hook = registration_allocation_probe;
						fixture.session.faults.registration_allocation_data = *probe;
					}
				);

				ok, started, error := query_immediate_fixture(test, kind);
				assert(probe.allocations == min(fail_at, allocation_count));
				Service.with_lock(
					*fixture.session.gate,
					#code {
						fixture.session.faults.registration_allocation_hook = null;
						fixture.session.faults.registration_allocation_data = null;
						if fail_at <= allocation_count {
							assert(!ok && !started.result.owner_token && !started.waiter.owner_token);
							assert(error.code == .ADMISSION_DENIED && error.admission.kind == .RESOURCE_EXHAUSTED);
							assert(fixture.session.registry.slots.count == slots.count && fixture.session.registry.free_slots.count == free_count);
							if fail_at <= allocation_count - 2 {
								assert(fixture.session.registrations.count == registrations);
							}

							for slots {
								current := fixture.session.registry.slots[it_index];
								assert(current.generation == it.generation && current.kind == it.kind && current.live == it.live && current.retired == it.retired);
							}
						} else {
							assert(ok && started.kind == .AVAILABLE && Service.handle_is_live(*fixture.session.registry, started.result));
							assert(fixture.session.registrations[started.result.slot].result.references == 1);
							if scenario == .REUSE {
								assert(started.result.slot < xx slots.count && started.result.generation == slots[started.result.slot].generation + 1);
							} else {
								assert(started.result.slot == xx slots.count && started.result.generation == 1);
							}
						}

						for before.live {
							amount := ifx it_index == Service.Limit_Name.LIVE_HANDLES.(s64)
								then xx ok
								else 0;

							assert(fixture.session.ledger.live[it_index] == it + amount);
							assert(fixture.session.ledger.reserved[it_index] == before.reserved[it_index]);
						}

						assert(world.references == references + (ifx ok then 1 else 0));
						assert(fixture.session.identities.operation_counter.next == identities.operation_counter.next + xx ok);
						assert(fixture.session.identities.result_counter.next == identities.result_counter.next + xx ok);
						assert(fixture.session.identities.world_counter.next == identities.world_counter.next);
					}
				);

				if ok {
					assert_immediate_result(fixture, started.result, world, kind, identities.result_counter.next);
					release(fixture, started.result);
				}

				free(slots.data);
				finish_retain(test);
			}
		}
	}

	print("X5 immediate result all kinds/registration/object/identity/reuse failure/ledger/reference/generation/counter/canonical identity atomicity \e[92mPASS\e[0m\n");
}

test_immediate_result_limits :: () {
	for 0..2 {
		scenario := it;
		test := prepared_retain(.WORLD, .ARRAYS);
		fixture := test.drain.fixture;
		before: Service.Resource_Ledger;
		identities: Service.Session_Identities;
		probe := Registration_Probe.{};
		world: *Service.World;
		references: s64;
		Service.with_lock(
			*fixture.session.gate,
			#code {
				before = fixture.session.ledger;
				identities = fixture.session.identities;
				world = fixture.session.registrations[test.source.slot].world;
				references = world.references;
				fixture.session.faults.registration_allocation_hook = registration_allocation_probe;
				fixture.session.faults.registration_allocation_data = *probe;
				if scenario == {
					case 0;
						fixture.session.ledger.limits.values[Service.Limit_Name.LIVE_HANDLES] = before.live[Service.Limit_Name.LIVE_HANDLES] + before.reserved[Service.Limit_Name.LIVE_HANDLES];
					case 1;
						fixture.session.identities.operation_counter.next = Service.U64_MAX;
					case 2;
						fixture.session.identities.result_counter.next = Service.U64_MAX;
				}
			}
		);

		ok, started, error := query_immediate_fixture(test, .SYNTAX_SNAPSHOT);
		assert(!ok && !started.result.owner_token && !started.waiter.owner_token && !probe.allocations);
		assert(error.code == .ADMISSION_DENIED);
		if scenario == 0 {
			assert(error.admission.kind == .LIMIT && error.admission.limit == .LIVE_HANDLES);
		} else {
			assert(error.admission.kind == .RESOURCE_EXHAUSTED);
		}

		Service.with_lock(
			*fixture.session.gate,
			#code {
				assert(world.references == references);
				assert(fixture.session.identities.operation_counter.next == (ifx scenario == 1 then Service.U64_MAX else identities.operation_counter.next));
				assert(fixture.session.identities.result_counter.next == (ifx scenario == 2 then Service.U64_MAX else identities.result_counter.next));
				for before.live {
					assert(fixture.session.ledger.live[it_index] == it && fixture.session.ledger.reserved[it_index] == before.reserved[it_index]);
				}

				fixture.session.ledger.limits = before.limits;
				fixture.session.identities = identities;
				fixture.session.faults.registration_allocation_hook = null;
				fixture.session.faults.registration_allocation_data = null;
			}
		);

		finish_retain(test);
	}

	print("X5 immediate result handle quota/operation-result counter exhaustion/no allocation/no admission \e[92mPASS\e[0m\n");
}

test_immediate_result_interleavings :: (direct := false, negative_control := false) {
	for Output_Action.[
		.OTHER_DRAIN,
		.REQUEST_SHUTDOWN,
		.REPLACE_SOURCE,
		.FILL_REGISTRATION_CAPACITY,
		.TAKE_RETAIN_CAPACITY,
		.ISSUE_COMPETING_RESULT,
		.EXHAUST_RESULT_COUNTER,
		.RELEASE_QUERY_WORLD,
		.RETIRE_IMMEDIATE_WORLD,
		.RETIRE_RETAIN_OWNER,
	] {
		action := it;
		if negative_control && action != .RELEASE_QUERY_WORLD {
			continue;
		}


		for s64.[1, 4, 5] {
			job_at := it;
			for 0..8 {
				fail_at := it;
				if fail_at && fail_at < job_at || negative_control && fail_at {
					continue;
				}


				test := prepared_retain(.WORLD, .ARRAYS);
				fixture := test.drain.fixture;
				probe := Registration_Probe.{
					fail_at = fail_at,
					job_at = job_at,
					direct = direct,
					track_waiter = true,
					job = .{drain = test.drain, action = action},
				};

				if action == .RELEASE_QUERY_WORLD {
					probe.job.drain.world = test.source;
					probe.job.surviving_world = test.drain.world;
				}

				if action == .RETIRE_RETAIN_OWNER || action == .RETIRE_IMMEDIATE_WORLD {
					array_add(*test.held, test.source);
					probe.job.retained_worlds = test.held;
				}

				world_identity: [] u8;
				Service.with_lock(
					*fixture.session.gate,
					#code {
						probe.track_world = fixture.session.registrations[test.source.slot].world;
						world_identity = array_copy(probe.track_world.identity.([] u8));
						fixture.session.faults.registration_allocation_hook = registration_allocation_probe;
						fixture.session.faults.registration_allocation_data = *probe;
						fixture.session.faults.allow_stale_immediate_result = negative_control;
					}
				);

				ok, started, error := query_immediate_fixture(test, .SYNTAX_SNAPSHOT);
				assert(probe.gate_progress && probe.job.ok && probe.allocations >= job_at);
				retired := action == .RELEASE_QUERY_WORLD || action == .RETIRE_IMMEDIATE_WORLD || action == .RETIRE_RETAIN_OWNER;
				if retired && !negative_control {
					assert(!ok && !started.result.owner_token && error.code == .INVALID_HANDLE && error.handle_kind == .WORLD);
				} else if negative_control {
					assert(ok && started.kind == .AVAILABLE, "\e[91mStale immediate-world negative control was not detected.\e[0m");
				} else if fail_at && fail_at <= probe.allocations {
					assert(!ok && !started.result.owner_token && error.code == .ADMISSION_DENIED && error.admission.kind == .RESOURCE_EXHAUSTED);
				} else if action == .REQUEST_SHUTDOWN {
					assert(!ok && !started.result.owner_token && error.code == .SERVICE_CLOSED);
				} else if action == .TAKE_RETAIN_CAPACITY {
					assert(!ok && !started.result.owner_token && error.code == .ADMISSION_DENIED && error.admission.kind == .LIMIT && error.admission.limit == .LIVE_HANDLES);
				} else if action == .EXHAUST_RESULT_COUNTER {
					assert(!ok && !started.result.owner_token && error.code == .ADMISSION_DENIED && error.admission.kind == .RESOURCE_EXHAUSTED);
				} else {
					assert(ok && started.kind == .AVAILABLE);
					if action == .FILL_REGISTRATION_CAPACITY {
						assert(probe.allocations == 8);
					}
				}

				if action == .RETIRE_RETAIN_OWNER {
					assert(probe.world_references == 1);
					last_allocation := ifx job_at == 1
						then 3
						else 5;

					assert(probe.allocations == (ifx fail_at && fail_at <= last_allocation then fail_at else last_allocation));
				} else {
					Service.with_lock(
						*fixture.session.gate,
						#code {
							fixture.session.faults.registration_allocation_hook = null;
							fixture.session.faults.registration_allocation_data = null;
							fixture.session.faults.allow_stale_immediate_result = false;
							for probe.waiter_ledger.live {
								amount := ifx it_index == Service.Limit_Name.LIVE_HANDLES.(s64)
									then xx ok
									else 0;

								assert(fixture.session.ledger.live[it_index] == it + amount);
								expected_reserved := probe.waiter_ledger.reserved[it_index];
								if (
									action == .REQUEST_SHUTDOWN
									&& it_index == Service.Limit_Name.IN_FLIGHT_OPERATIONS.(s64)
									&& fixture.session.lifecycle == .STOPPED
								) {
									expected_reserved = 0;
								}

								assert(fixture.session.ledger.reserved[it_index] == expected_reserved);
							}

							assert(fixture.session.identities.operation_counter.next == probe.callback_identities.operation_counter.next + xx ok);
							assert(fixture.session.identities.result_counter.next == probe.callback_identities.result_counter.next + xx ok);
							assert(fixture.session.identities.world_counter.next == probe.callback_identities.world_counter.next);
							if action == .RETIRE_IMMEDIATE_WORLD {
								assert(probe.world_references == 1);
								for fixture.session.worlds {
									assert(!Service.bytes_equal(it.identity.([] u8), world_identity));
								}
							} else {
								assert(probe.track_world.references == probe.world_references - (ifx ok then 0 else 1));
							}
						}
					);
				}

				if ok {
					assert_immediate_result(fixture, started.result, probe.track_world, .SYNTAX_SNAPSHOT, probe.callback_identities.result_counter.next);
					release(fixture, started.result);
				}

				if probe.job.replacement.owner_token {
					read_ok := Service.read_result(fixture.host.service, probe.job.replacement);
					assert(read_ok);
					release(fixture, probe.job.replacement);
				}

				if probe.job.replacement_world.owner_token {
					read_ok := Service.read_world(fixture.host.service, probe.job.replacement_world);
					assert(read_ok);
					release(fixture, probe.job.replacement_world);
				}

				for probe.job.competing_worlds {
					read_ok := Service.read_world(fixture.host.service, it);
					assert(read_ok);
					release(fixture, it);
				}

				array_free(probe.job.competing_worlds);
				free_records(probe.job.records);
				free(world_identity.data);
				if action == .RETIRE_IMMEDIATE_WORLD {
					array_free(test.held);
					close(fixture);
				} else {
					finish_retain(
						test,
						source_released = action == .RELEASE_QUERY_WORLD,
						owner_released = action == .RETIRE_RETAIN_OWNER
					);
				}
			}
		}
	}

	print(
		"X3/X5 immediate result registration/object/identity callbacks/shutdown/frontier/retry/quota/competing counter/source reuse/last reference/owner retirement (direct = %, negative control = %) \e[92mPASS\e[0m\n",
		direct,
		negative_control
	);
}

test_immediate_result_failure_control :: () {
	for 1..5 {
		fail_at := it;
		test := prepared_retain(.WORLD, .ARRAYS);
		fixture := test.drain.fixture;
		probe := Registration_Probe.{fail_at = fail_at};
		Service.with_lock(
			*fixture.session.gate,
			#code {
				fixture.session.faults.registration_allocation_hook = registration_allocation_probe;
				fixture.session.faults.registration_allocation_data = *probe;
				fixture.session.faults.retry_failed_immediate_result = true;
			}
		);

		ok, started := query_immediate_fixture(test, .SYNTAX_SNAPSHOT);
		expected_allocations := ifx fail_at <= 3
			then 5 + fail_at
			else fail_at + 2;

		assert(ok && started.kind == .AVAILABLE && probe.allocations == expected_allocations, "\e[91mFailed immediate result admission negative control was not detected.\e[0m");
		Service.with_lock(
			*fixture.session.gate,
			#code {
				fixture.session.faults.registration_allocation_hook = null;
				fixture.session.faults.registration_allocation_data = null;
				fixture.session.faults.retry_failed_immediate_result = false;
			}
		);

		release(fixture, started.result);
		finish_retain(test);
	}

	print("X5 immediate result registration/object/identity failed-admission negative controls \e[92mPASS\e[0m\n");
}

test_immediate_result_last_token :: () {
	test := prepared_retain(.WORLD, .REUSE);
	fixture := test.drain.fixture;
	probe := Registration_Probe.{};
	world: *Service.World;
	operation_token: u64;
	Service.with_lock(
		*fixture.session.gate,
		#code {
			world = fixture.session.registrations[test.source.slot].world;
			operation_token = fixture.session.identities.operation_counter.next;
			fixture.session.identities.result_counter.next = Service.U64_MAX - 1;
			fixture.session.faults.registration_allocation_hook = registration_allocation_probe;
			fixture.session.faults.registration_allocation_data = *probe;
		}
	);

	ok, started := query_immediate_fixture(test, .SYNTAX_SNAPSHOT);
	assert(ok && started.kind == .AVAILABLE && probe.allocations == 2);
	assert_immediate_result(fixture, started.result, world, .SYNTAX_SNAPSHOT, Service.U64_MAX - 1);
	second_ok, second, error := query_immediate_fixture(test, .SYNTAX_SNAPSHOT);
	assert(!second_ok && !second.result.owner_token && error.code == .ADMISSION_DENIED && error.admission.kind == .RESOURCE_EXHAUSTED && probe.allocations == 2);
	Service.with_lock(
		*fixture.session.gate,
		#code {
			assert(fixture.session.identities.result_counter.next == Service.U64_MAX);
			assert(fixture.session.identities.operation_counter.next == operation_token + 1);
			fixture.session.faults.registration_allocation_hook = null;
			fixture.session.faults.registration_allocation_data = null;
		}
	);

	release(fixture, started.result);
	finish_retain(test);
	print("X5 immediate result last-token canonical identity/retired counter/no wrap/no second operation admission \e[92mPASS\e[0m\n");
}

test_result_registration_interleavings :: (direct := false, negative_control := false) {
	for Output_Action.[
		.OTHER_DRAIN,
		.REQUEST_SHUTDOWN,
		.REPLACE_SOURCE,
		.FILL_REGISTRATION_CAPACITY,
		.TAKE_RETAIN_CAPACITY,
		.RELEASE_WAITER,
		.RETIRE_SELECTED_RESULT,
		.RETIRE_RETAIN_OWNER,
	] {
		action := it;
		if negative_control && action != .RELEASE_WAITER {
			continue;
		}


		for s64.[0, 1, 2, 3, 4, 5, 6] {
			fail_at := it;
			if negative_control && fail_at {
				continue;
			}


			test := prepared_retain(.RESULT, .ARRAYS);
			fixture := test.drain.fixture;
			probe := Registration_Probe.{
				fail_at = fail_at,
				direct = direct,
				track_waiter = true,
				job = .{drain = test.drain, action = action},
			};

			if action == .RETIRE_RETAIN_OWNER {
				array_add(*test.held, test.source);
				probe.job.retained_results = test.held;
			}

			Service.with_lock(
				*fixture.session.gate,
				#code {
					probe.track_result = fixture.session.registrations[test.drain.first.slot].operation.result;
					probe.track_world = probe.track_result.world;
					fixture.session.faults.registration_allocation_hook = registration_allocation_probe;
					fixture.session.faults.registration_allocation_data = *probe;
					fixture.session.faults.allow_stale_result_registration = negative_control;
				}
			);

			ok, acquired, error := Service.acquire_result(fixture.host.service, test.drain.first);
			assert(probe.gate_progress && probe.job.ok && probe.allocations);
			retired := action == .RELEASE_WAITER || action == .RETIRE_SELECTED_RESULT || action == .RETIRE_RETAIN_OWNER;
			if retired && !negative_control {
				assert(!ok && !acquired.result.owner_token && error.code == .INVALID_HANDLE && error.handle_kind == .WAITER);
			} else if negative_control {
				assert(ok && acquired.kind == .ACQUIRED, "\e[91mStale result-selector negative control was not detected.\e[0m");
			} else if fail_at && fail_at <= probe.allocations {
				assert(!ok && !acquired.result.owner_token && error.code == .ADMISSION_DENIED && error.admission.kind == .RESOURCE_EXHAUSTED);
			} else if action == .TAKE_RETAIN_CAPACITY {
				assert(!ok && !acquired.result.owner_token && error.code == .ADMISSION_DENIED && error.admission.kind == .LIMIT && error.admission.limit == .LIVE_HANDLES);
			} else {
				assert(ok && acquired.kind == .ACQUIRED);
				if action == .FILL_REGISTRATION_CAPACITY {
					assert(probe.allocations == 6);
				}
			}

			if action == .RETIRE_RETAIN_OWNER {
				assert(probe.result_references == 1);
				assert(probe.allocations == (ifx fail_at && fail_at <= 3 then fail_at else 3));
			} else {
				Service.with_lock(
					*fixture.session.gate,
					#code {
						fixture.session.faults.registration_allocation_hook = null;
						fixture.session.faults.registration_allocation_data = null;
						fixture.session.faults.allow_stale_result_registration = false;
						for probe.waiter_ledger.live {
							amount := ifx it_index == Service.Limit_Name.LIVE_HANDLES.(s64)
								then xx ok
								else 0;

							assert(fixture.session.ledger.live[it_index] == it + amount);
							expected_reserved := probe.waiter_ledger.reserved[it_index];
							if (
								action == .REQUEST_SHUTDOWN
								&& it_index == Service.Limit_Name.IN_FLIGHT_OPERATIONS.(s64)
								&& fixture.session.lifecycle == .STOPPED
							) {
								expected_reserved = 0;
							}

							assert(fixture.session.ledger.reserved[it_index] == expected_reserved);
						}

						if action == .RETIRE_SELECTED_RESULT {
							assert(probe.result_references == 1);
							assert(probe.track_world.references == probe.world_references - 1);
						} else {
							assert(probe.track_result.references == probe.result_references - (ifx ok then 0 else 1));
						}

						if ok {
							assert(fixture.session.registrations[acquired.result.slot].result == probe.track_result);
						}
					}
				);
			}

			if ok {
				read_ok := Service.read_result(fixture.host.service, acquired.result);
				assert(read_ok);
				release(fixture, acquired.result);
			}

			if probe.job.replacement.owner_token {
				assert(probe.job.replacement.slot == test.drain.first.slot && probe.job.replacement.generation != test.drain.first.generation);
				read_ok := Service.read_result(fixture.host.service, probe.job.replacement);
				assert(read_ok);
				release(fixture, probe.job.replacement);
			}

			for probe.job.competing_worlds {
				read_ok := Service.read_world(fixture.host.service, it);
				assert(read_ok);
				release(fixture, it);
			}

			array_free(probe.job.competing_worlds);
			free_records(probe.job.records);
			if action == .RETIRE_SELECTED_RESULT {
				for test.held {
					release(fixture, it);
				}

				array_free(test.held);
				release(fixture, test.source);
				release(fixture, test.drain.world);
				release(fixture, test.drain.ticket);
				close(fixture);
			} else if action == .RELEASE_WAITER {
				for test.held {
					release(fixture, it);
				}

				array_free(test.held);
				release(fixture, test.source);
				finish_drain(test.drain, first_released = true);
			} else {
				finish_retain(test, owner_released = action == .RETIRE_RETAIN_OWNER);
			}
		}
	}

	print(
		"X3/X5 successful result registration shutdown/replacement/retry/quota/waiter reuse/last reference/owner retirement (direct = %, negative control = %) \e[92mPASS\e[0m\n",
		direct,
		negative_control
	);
}

test_result_registration_quota_and_control :: (negative_control := false) {
	test := prepared_retain(.RESULT, .ARRAYS, acquisition = true);
	fixture := test.drain.fixture;
	probe := Registration_Probe.{fail_at = 1};
	before: Service.Resource_Ledger;
	before_references: s64;
	Service.with_lock(
		*fixture.session.gate,
		#code {
			before = fixture.session.ledger;
			before_references = fixture.session.registrations[test.source.slot].result.references;
			fixture.session.faults.registration_allocation_hook = registration_allocation_probe;
			fixture.session.faults.registration_allocation_data = *probe;
			fixture.session.faults.retry_failed_result_registration = negative_control;
			if !negative_control {
				fixture.session.ledger.limits.values[Service.Limit_Name.LIVE_HANDLES] = before.live[Service.Limit_Name.LIVE_HANDLES] + before.reserved[Service.Limit_Name.LIVE_HANDLES];
			}
		}
	);

	ok, acquired, error := Service.acquire_result(fixture.host.service, test.drain.first);
	if negative_control {
		assert(ok && acquired.kind == .ACQUIRED && probe.allocations == 4, "\e[91mFailed result registration admission negative control was not detected.\e[0m");
	} else {
		assert(!ok && !acquired.result.owner_token && error.code == .ADMISSION_DENIED && error.admission.kind == .LIMIT && error.admission.limit == .LIVE_HANDLES);
		assert(!probe.allocations);
	}

	Service.with_lock(
		*fixture.session.gate,
		#code {
			fixture.session.faults.registration_allocation_hook = null;
			fixture.session.faults.registration_allocation_data = null;
			fixture.session.faults.retry_failed_result_registration = false;
			fixture.session.ledger.limits = before.limits;
			assert(fixture.session.registrations[test.source.slot].result.references == before_references + (ifx ok then 1 else 0));
			for before.live {
				amount := ifx it_index == Service.Limit_Name.LIVE_HANDLES.(s64)
					then xx ok
					else 0;

				assert(fixture.session.ledger.live[it_index] == it + amount);
				assert(fixture.session.ledger.reserved[it_index] == before.reserved[it_index]);
			}
		}
	);

	if ok {
		release(fixture, acquired.result);
	}

	finish_retain(test);
	print("X5 successful result registration quota/failed-admission control (negative control = %) \e[92mPASS\e[0m\n", negative_control);
}

test_retain_backing_interleavings :: ($K: Service.Handle_Kind, direct := false, negative_control := false) {
	for Output_Action.[
		.REPLACE_SOURCE,
		.REQUEST_SHUTDOWN,
		.REJECT_ACTIVE_RELEASE,
		.OTHER_DRAIN,
		.RELEASE_QUERY_WORLD,
		.FILL_REGISTRATION_CAPACITY,
		.TAKE_RETAIN_CAPACITY,
		.RETIRE_RETAIN_OWNER,
	] {
		action := it;
		if negative_control && action != .RELEASE_QUERY_WORLD {
			continue;
		}


		for s64.[0, 1, 2, 3, 4, 5, 6] {
			fail_at := it;
			if negative_control && fail_at {
				continue;
			}


			test := prepared_retain(K, .ARRAYS);
			fixture := test.drain.fixture;
			probe := Registration_Probe.{
				fail_at = fail_at,
				direct = direct,
				job = .{drain = test.drain, action = action},
			};

			if action == .RELEASE_QUERY_WORLD {
				retained, survivor := Service.retain(fixture.host.service, test.source);
				assert(retained);
				array_add(*test.held, survivor);
				#if K == .WORLD {
					probe.job.drain.world = test.source;
					probe.job.surviving_world = survivor;
				} else {
					probe.job.action = .RELEASE_ACCESS_RESULT;
					probe.job.access_result = test.source;
					probe.job.surviving_result = survivor;
				}
			}

			if action == .RETIRE_RETAIN_OWNER {
				array_add(*test.held, test.source);
				#if K == .WORLD {
					probe.job.retained_worlds = test.held;
				} else {
					probe.job.retained_results = test.held;
				}
			}

			Service.with_lock(
				*fixture.session.gate,
				#code {
					fixture.session.faults.registration_allocation_hook = registration_allocation_probe;
					fixture.session.faults.registration_allocation_data = *probe;
					fixture.session.faults.allow_stale_retain_registration = negative_control;
				}
			);

			ok, duplicate, error := Service.retain(fixture.host.service, test.source);
			assert(probe.gate_progress && probe.job.ok && probe.allocations);
			if action != .RETIRE_RETAIN_OWNER {
				Service.with_lock(
					*fixture.session.gate,
					#code {
						fixture.session.faults.registration_allocation_hook = null;
						fixture.session.faults.registration_allocation_data = null;
					}
				);
			}

			if action == .RELEASE_QUERY_WORLD {
				if negative_control {
					assert(ok, "\e[91mStale retained-source negative control was not detected.\e[0m");
					release(fixture, duplicate);
				} else {
					assert(!ok && !duplicate.owner_token && error.code == .INVALID_HANDLE && error.handle_kind == K);
				}
				#if K == .WORLD {
					read_ok := Service.read_world(fixture.host.service, probe.job.replacement_world);
					assert(read_ok);
					release(fixture, probe.job.replacement_world);
				} else {
					read_ok := Service.read_result(fixture.host.service, probe.job.replacement);
					assert(read_ok);
					release(fixture, probe.job.replacement);
				}
			} else if action == .RETIRE_RETAIN_OWNER {
				assert(!ok && !duplicate.owner_token && error.code == .INVALID_HANDLE && error.handle_kind == K);
				assert(probe.allocations == (ifx fail_at && fail_at <= 3 then fail_at else 3));
			} else if fail_at && fail_at <= probe.allocations {
				assert(!ok && !duplicate.owner_token && error.code == .ADMISSION_DENIED && error.admission.kind == .RESOURCE_EXHAUSTED);
			} else if action == .TAKE_RETAIN_CAPACITY {
				assert(!ok && !duplicate.owner_token && error.code == .ADMISSION_DENIED && error.admission.kind == .LIMIT && error.admission.limit == .LIVE_HANDLES);
			} else {
				assert(ok);
				if action == .FILL_REGISTRATION_CAPACITY {
					assert(probe.allocations >= 6);
				}

				release(fixture, duplicate);
			}

			for probe.job.competing_worlds {
				read_ok, borrowed := Service.read_world(fixture.host.service, it);
				assert(read_ok && Service.bytes_equal(borrowed.members[0].source.bytes, xx "answer :: 42;"));
				release(fixture, it);
			}

			array_free(probe.job.competing_worlds);
			free_records(probe.job.records);
			finish_retain(
				test,
				source_released = action == .RELEASE_QUERY_WORLD,
				owner_released = action == .RETIRE_RETAIN_OWNER
			);
		}
	}

	print(
		"X3/X5 retain registration allocation/source/shutdown/drain/reuse/capacity/retirement (kind = %, direct = %, negative control = %) \e[92mPASS\e[0m\n",
		K,
		direct,
		negative_control
	);
}

Waiter_Admission_Fixture :: struct ($K: Service.Handle_Kind) {
	retained: Retain_Fixture(.WORLD);
	source: Service.Handle(K);
}

prepared_waiter_admission :: ($K: Service.Handle_Kind, scenario: Retain_Backing_Case) -> Waiter_Admission_Fixture(K) {
	#assert K == .TICKET || K == .WORLD;
	test := Waiter_Admission_Fixture(K).{retained = prepared_retain(.WORLD, .ARRAYS, held = true)};
	fixture := test.retained.drain.fixture;
	#if K == .TICKET {
		test.source = submit(fixture, "answer :: 43;");
	} else {
		test.source = test.retained.source;
	}

	while true {
		room: bool;
		Service.with_lock(
			*fixture.session.gate,
			#code {
				room = !!fixture.session.registry.free_slots.count
					|| fixture.session.registry.slots.count < fixture.session.registry.slots.allocated;
			}
		);

		if !room {
			break;
		}


		ok, duplicate := Service.retain(fixture.host.service, test.retained.source);
		assert(ok);
		array_add(*test.retained.held, duplicate);
	}

	if scenario != .ARRAYS {
		ok, duplicate := Service.retain(fixture.host.service, test.retained.source);
		assert(ok);
		if scenario == .REUSE {
			release(fixture, duplicate);
		} else {
			array_add(*test.retained.held, duplicate);
		}
	}

	return test;
}

admit_test_waiter :: (test: Waiter_Admission_Fixture($K)) -> bool, Service.Handle(.WAITER), Service.Operation_Error, bool {
	fixture := test.retained.drain.fixture;
	#if K == .TICKET {
		ok, observed, error := Service.observe_ticket(fixture.host.service, test.source);
		Service.free_observation(*observed.observation);
		return ok, observed.waiter, error, observed.terminal;
	} else {
		ok, started, error := Service.query(
			fixture.host.service,
			.{
				version = Service.INTERFACE_VERSION,
				world = test.source,
				document = Service.harness_document(fixture.host, "a.jai"),
				kind = .SYNTAX_DIAGNOSTICS,
			}
		);

		terminal := ok && started.kind != .PENDING;
		if terminal && started.kind == .AVAILABLE {
			release(fixture, started.result);
		} else if terminal {
			assert(started.kind == .TERMINAL && started.observation.query.kind == .CANCELLED && started.observation.query.cancellation == .WORLD_SUPERSEDED);
			Service.free_observation(*started.observation);
		}

		return ok, started.waiter, error, terminal;
	}
}

finish_waiter_admission :: (test: Waiter_Admission_Fixture($K), source_released := false, owner_released := false) {
	#if K == .TICKET {
		if !source_released && !owner_released {
			release(test.retained.drain.fixture, test.source);
		}
	}

	finish_retain(
		test.retained,
		source_released = K == .WORLD && source_released,
		owner_released = owner_released,
		held = true
	);
}

test_waiter_backing_failures :: ($K: Service.Handle_Kind) {
	for Retain_Backing_Case.[.ARRAYS, .OBJECT, .REUSE] {
		scenario := it;
		allocation_count := ifx scenario == .ARRAYS
			then 4
			else ifx scenario == .OBJECT
				then 2
				else 1;

		for 1..allocation_count + 1 {
			fail_at := it;
			test := prepared_waiter_admission(K, scenario);
			fixture := test.retained.drain.fixture;
			session := fixture.session;
			probe := Registration_Probe.{fail_at = fail_at};
			before: Service.Resource_Ledger;
			before_slots: [] Service.Registration_Slot;
			before_operations: s64;
			before_tasks: s64;
			before_references: s64;
			before_free: s64;
			before_counter: u64;
			Service.with_lock(
				*session.gate,
				#code {
					before = session.ledger;
					before_slots = array_copy(session.registry.slots);
					before_operations = session.operations.count;
					before_tasks = session.tasks.count;
					before_free = session.registry.free_slots.count;
					before_counter = session.identities.operation_counter.next;
					#if K == .TICKET {
						operation := session.registrations[test.source.slot].operation;
						assert(!operation.terminal && !operation.waiters.count);
						before_references = operation.registrations;
					} else {
						before_references = session.registrations[test.source.slot].world.references;
					}

					session.faults.registration_allocation_hook = registration_allocation_probe;
					session.faults.registration_allocation_data = *probe;
				}
			);

			ok, waiter, error, terminal := admit_test_waiter(test);
			assert(!terminal && probe.allocations == min(fail_at, allocation_count));
			Service.with_lock(
				*session.gate,
				#code {
					session.faults.registration_allocation_hook = null;
					if fail_at <= allocation_count {
						assert(!ok && !waiter.owner_token && error.code == .ADMISSION_DENIED && error.admission.kind == .RESOURCE_EXHAUSTED);
						assert(session.registry.slots.count == before_slots.count);
						assert(session.operations.count == before_operations && session.tasks.count == before_tasks && session.registry.free_slots.count == before_free);
						for before_slots {
							current := session.registry.slots[it_index];
							assert(current.generation == it.generation && current.live == it.live && current.kind == it.kind && current.retired == it.retired);
						}

						for before.live {
							assert(session.ledger.live[it_index] == it && session.ledger.reserved[it_index] == before.reserved[it_index]);
						}
					} else {
						assert(ok && Service.handle_is_live(*session.registry, waiter));
						operation := session.registrations[waiter.slot].operation;
						assert(operation.waiters.count == 1 && operation.waiters[0].slot == waiter.slot && operation.waiters[0].generation == waiter.generation);
						if scenario == .REUSE {
							assert(waiter.slot < xx before_slots.count && waiter.generation == before_slots[waiter.slot].generation + 1);
						} else {
							assert(waiter.slot == xx before_slots.count && waiter.generation == 1);
						}

						for Service.Limit_Name.[.LIVE_HANDLES, .PENDING_REGISTRATIONS, .COMPLETION_RECORDS] {
							assert(session.ledger.live[it] == before.live[it] + 1);
						}
					}

					#if K == .TICKET {
						operation := session.registrations[test.source.slot].operation;
						assert(operation.registrations == before_references + xx ok);
						assert(session.identities.operation_counter.next == before_counter);
					} else {
						assert(session.registrations[test.source.slot].world.references == before_references + xx ok);
						assert(session.identities.operation_counter.next == before_counter + 1);
					}
				}
			);

			if ok {
				release(fixture, waiter);
			}

			free(before_slots.data);
			finish_waiter_admission(test);
		}
	}

	print("X5 waiter registration/list array/object/reuse failure/ledger/reference/generation atomicity (kind = %) \e[92mPASS\e[0m\n", K);
}

test_waiter_backing_quota :: ($K: Service.Handle_Kind) {
	for Service.Limit_Name.[.LIVE_HANDLES, .PENDING_REGISTRATIONS, .COMPLETION_RECORDS, .IN_FLIGHT_OPERATIONS] {
		name := it;
		if K == .TICKET && name == .IN_FLIGHT_OPERATIONS {
			continue;
		}


		test := prepared_waiter_admission(K, .ARRAYS);
		fixture := test.retained.drain.fixture;
		probe: Registration_Probe;
		before: Service.Resource_Ledger;
		Service.with_lock(
			*fixture.session.gate,
			#code {
				before = fixture.session.ledger;
				fixture.session.ledger.limits.values[name] = before.live[name] + before.reserved[name];
				fixture.session.faults.registration_allocation_hook = registration_allocation_probe;
				fixture.session.faults.registration_allocation_data = *probe;
			}
		);

		ok, waiter, error, terminal := admit_test_waiter(test);
		assert(!ok && !waiter.owner_token && !terminal && !probe.allocations);
		assert(error.code == .ADMISSION_DENIED && error.admission.kind == .LIMIT && error.admission.limit == name);
		Service.with_lock(
			*fixture.session.gate,
			#code {
				fixture.session.faults.registration_allocation_hook = null;
				fixture.session.ledger.limits = before.limits;
				for before.live {
					assert(fixture.session.ledger.live[it_index] == it && fixture.session.ledger.reserved[it_index] == before.reserved[it_index]);
				}
			}
		);

		finish_waiter_admission(test);
	}

	print("X5 waiter full operation/handle/pending/completion quota/no allocation (kind = %) \e[92mPASS\e[0m\n", K);
}

test_waiter_backing_interleavings :: ($K: Service.Handle_Kind, direct := false, negative_control := false) {
	for s64.[1, 4] {
		job_at := it;
		for Output_Action.[.OTHER_DRAIN, .REQUEST_SHUTDOWN, .COMPLETE_WORK, .REPLACE_HELD_SOURCE, .FILL_REGISTRATION_CAPACITY, .FILL_WAITER_CAPACITY, .TAKE_RETAIN_CAPACITY, .TAKE_PENDING_CAPACITY, .TAKE_COMPLETION_CAPACITY, .RELEASE_QUERY_WORLD, .RETIRE_RETAIN_OWNER] {
			action := it;
			if K == .WORLD && action == .FILL_WAITER_CAPACITY || negative_control && action != .RELEASE_QUERY_WORLD {
				continue;
			}


			for s64.[0, 1, 2, 3, 4, 5, 6, 7, 8] {
				fail_at := it;
				if fail_at && fail_at < job_at || negative_control && fail_at {
					continue;
				}


				test := prepared_waiter_admission(K, .ARRAYS);
				fixture := test.retained.drain.fixture;
				probe := Registration_Probe.{
					fail_at = fail_at,
					job_at = job_at,
					direct = direct,
					track_waiter = true,
					job = .{drain = test.retained.drain, action = action},
				};

				#if K == .TICKET {
					probe.job.drain.ticket = test.source;
					if action == .COMPLETE_WORK {
						probe.job.action = .COMPLETE_WAITER_TICKET;
					} else if action == .RELEASE_QUERY_WORLD {
						probe.job.action = .REPLACE_WAITER_TICKET;
					} else if action == .RETIRE_RETAIN_OWNER {
						probe.job.retirement_ticket = test.retained.drain.ticket;
					}
				} else {
					if action == .RELEASE_QUERY_WORLD {
						probe.job.drain.world = test.source;
						probe.job.surviving_world = test.retained.drain.world;
					}
				}

				if action == .RETIRE_RETAIN_OWNER {
					array_add(*test.retained.held, test.retained.source);
					probe.job.retained_worlds = test.retained.held;
				}

				Service.with_lock(
					*fixture.session.gate,
					#code {
						fixture.session.faults.registration_allocation_hook = registration_allocation_probe;
						fixture.session.faults.registration_allocation_data = *probe;
						fixture.session.faults.allow_stale_waiter_source = negative_control;
					}
				);

				ok, waiter, error, terminal := admit_test_waiter(test);
				assert(probe.gate_progress && probe.job.ok && probe.allocations >= job_at);
				retired := action == .RELEASE_QUERY_WORLD || action == .RETIRE_RETAIN_OWNER;
				completion_winner := K == .TICKET && (action == .COMPLETE_WORK || action == .REQUEST_SHUTDOWN || action == .REPLACE_HELD_SOURCE);
				if retired && !negative_control {
					assert(!ok && !waiter.owner_token && !terminal && error.code == .INVALID_HANDLE && error.handle_kind == K);
				} else if negative_control {
					assert(ok && waiter.generation && !terminal, "\e[91mStale waiter-source negative control was not detected.\e[0m");
				} else if completion_winner {
					assert(ok && terminal && !waiter.owner_token);
				} else if action == .REQUEST_SHUTDOWN {
					assert(!ok && !waiter.owner_token && !terminal && error.code == .SERVICE_CLOSED);
				} else if action == .REPLACE_HELD_SOURCE {
					assert(ok && terminal && !waiter.owner_token);
				} else if fail_at && fail_at <= probe.allocations {
					assert(!ok && !waiter.owner_token && !terminal && error.code == .ADMISSION_DENIED && error.admission.kind == .RESOURCE_EXHAUSTED);
				} else if action == .TAKE_RETAIN_CAPACITY || action == .TAKE_PENDING_CAPACITY || action == .TAKE_COMPLETION_CAPACITY {
					assert(!ok && !waiter.owner_token && !terminal && error.code == .ADMISSION_DENIED && error.admission.kind == .LIMIT);
				} else {
					assert(ok && waiter.generation && !terminal);
					if action == .FILL_REGISTRATION_CAPACITY {
						assert(probe.allocations >= 7);
					} else if action == .FILL_WAITER_CAPACITY && job_at == 4 {
						assert(probe.allocations >= 6);
					}
				}

				if action == .RETIRE_RETAIN_OWNER {
					assert(
						probe.allocations == (
							ifx job_at == 4
								then 4
								else ifx fail_at && fail_at <= 3
									then fail_at
									else 3
						)
					);
				} else {
					Service.with_lock(
						*fixture.session.gate,
						#code {
							fixture.session.faults.registration_allocation_hook = null;
							fixture.session.faults.allow_stale_waiter_source = false;
							for Service.Limit_Name.[.LIVE_HANDLES, .PENDING_REGISTRATIONS, .COMPLETION_RECORDS] {
								assert(
									fixture.session.ledger.live[it] == probe.waiter_ledger.live[it] + xx !!waiter.owner_token,
									"\e[91mWaiter charges changed: kind %, action %, callback %, failure %, limit %, before %, after %.\e[0m",
									K,
									action,
									job_at,
									fail_at,
									it,
									probe.waiter_ledger.live[it],
									fixture.session.ledger.live[it]
								);
							}
						}
					);
				}

				if waiter.owner_token {
					release(fixture, waiter);
				}

				for probe.job.competing_worlds {
					read_ok := Service.read_world(fixture.host.service, it);
					assert(read_ok);
					release(fixture, it);
				}

				for probe.job.competing_waiters {
					polled, observation := Service.poll(fixture.host.service, it);
					assert(polled && observation.kind == .PENDING);
					Service.free_observation(*observation);
					release(fixture, it);
				}

				if probe.job.replacement_world.owner_token {
					read_ok := Service.read_world(fixture.host.service, probe.job.replacement_world);
					assert(read_ok);
					release(fixture, probe.job.replacement_world);
				}

				if probe.job.replacement_ticket.owner_token {
					release(fixture, probe.job.replacement_ticket);
				}

				array_free(probe.job.competing_worlds);
				array_free(probe.job.competing_waiters);
				free_records(probe.job.records);
				finish_waiter_admission(
					test,
					source_released = retired,
					owner_released = action == .RETIRE_RETAIN_OWNER
				);
			}
		}
	}

	print(
		"X3/X5 waiter registration/list allocation/completion/frontier/quota/retry/source reuse/owner retirement (kind = %, direct = %, negative control = %) \e[92mPASS\e[0m\n",
		K,
		direct,
		negative_control
	);
}

test_waiter_failed_backing_control :: ($K: Service.Handle_Kind) {
	test := prepared_waiter_admission(K, .ARRAYS);
	fixture := test.retained.drain.fixture;
	probe := Registration_Probe.{fail_at = 1};
	Service.with_lock(
		*fixture.session.gate,
		#code {
			fixture.session.faults.registration_allocation_hook = registration_allocation_probe;
			fixture.session.faults.registration_allocation_data = *probe;
			fixture.session.faults.allow_failed_waiter_backing = true;
		}
	);

	ok, waiter, error, terminal := admit_test_waiter(test);
	assert(ok && waiter.generation && !terminal && probe.allocations > 4, "\e[91mFailed waiter backing negative control was not detected.\e[0m");
	Service.with_lock(
		*fixture.session.gate,
		#code {
			fixture.session.faults.registration_allocation_hook = null;
			fixture.session.faults.allow_failed_waiter_backing = false;
		}
	);

	release(fixture, waiter);
	finish_waiter_admission(test);
	print("X5 failed waiter backing admission negative control (kind = %) \e[92mPASS\e[0m\n", K);
}

World_Registration_Case :: enum {
	HEAD;
	TICKET;
	WAITER;
}

World_Registration_Fixture :: struct {
	retained: Retain_Fixture(.WORLD);
	scenario: World_Registration_Case;
	selector: Service.World_Selector;
	ticket: Service.Handle(.TICKET);
	waiter: Service.Handle(.WAITER);
	world: Service.Handle(.WORLD);
	identity: [] u8;
}

prepared_world_registration :: (scenario: World_Registration_Case, backing_case: Retain_Backing_Case) -> World_Registration_Fixture {
	test := World_Registration_Fixture.{
		retained = prepared_retain(.WORLD, .ARRAYS),
		scenario = scenario,
	};

	fixture := test.retained.drain.fixture;
	Service.arm_pause(fixture.session, .PUBLICATION);
	test.ticket = submit(fixture, "answer :: 43;");
	assert(Service.await_pause(fixture.session, .PUBLICATION));
	observed_ok, observed := Service.observe_ticket(fixture.host.service, test.ticket);
	assert(observed_ok && !observed.terminal && observed.waiter.generation);
	test.waiter = observed.waiter;
	Service.resume_pause(fixture.session, .PUBLICATION);
	test.world = world_of(fixture, test.ticket);
	read_ok, world := Service.read_world(fixture.host.service, test.world);
	assert(read_ok);
	test.identity = array_copy(world.identity.([] u8));
	if scenario == .HEAD {
		ok, description := Service.describe_session(fixture.host.service, fixture.host.session);
		assert(ok);
		test.selector = .{
			kind = .HEAD,
			session = fixture.host.session,
			workspace = array_copy(description.workspace),
			expected_frontier = array_copy(description.accepted_frontier),
		};

		Service.free_description(*description);
	} else {
		test.selector = .{
			kind = .PUBLISHED_UPDATE,
			ticket = test.ticket,
			waiter = test.waiter,
			use_waiter = scenario == .WAITER,
		};
	}

	while true {
		room: bool;
		Service.with_lock(
			*fixture.session.gate,
			#code {
				room = !!fixture.session.registry.free_slots.count
					|| fixture.session.registry.slots.count < fixture.session.registry.slots.allocated;
			}
		);

		if !room {
			break;
		}


		ok, duplicate := Service.retain(fixture.host.service, test.retained.source);
		assert(ok);
		array_add(*test.retained.held, duplicate);
	}

	if backing_case != .ARRAYS {
		ok, duplicate := Service.retain(fixture.host.service, test.retained.source);
		assert(ok);
		if backing_case == .REUSE {
			release(fixture, duplicate);
		} else {
			array_add(*test.retained.held, duplicate);
		}
	}

	return test;
}

assert_world_registration :: (test: World_Registration_Fixture, handle: Service.Handle(.WORLD)) {
	fixture := test.retained.drain.fixture;
	ok, world := Service.read_world(fixture.host.service, handle);
	assert(ok && Service.bytes_equal(world.identity.([] u8), test.identity));
	assert(Service.bytes_equal(world.members[0].source.bytes, xx "answer :: 43;"));
}

finish_world_registration :: (test: World_Registration_Fixture, source_released := false, selected_released := false, owner_released := false) {
	fixture := test.retained.drain.fixture;
	free(test.selector.workspace.data);
	free(test.selector.expected_frontier.data);
	free(test.identity.data);
	if owner_released {
		array_free(test.retained.held);
		assert(!fixture.host.service.owned_allocations && !fixture.host.service.owned_bytes);
		assert_no_owned_allocations();
		return;
	}


	for test.retained.held {
		release(fixture, it);
	}

	array_free(test.retained.held);
	release(fixture, test.retained.source);
	if !selected_released {
		release(fixture, test.world);
		if !source_released || test.scenario != .TICKET {
			release(fixture, test.ticket);
		}

		if !source_released || test.scenario != .WAITER {
			release(fixture, test.waiter);
		}
	}

	finish_drain(test.retained.drain, session_released = source_released && test.scenario == .HEAD);
}

test_world_registration_failures :: () {
	for World_Registration_Case.[.HEAD, .TICKET, .WAITER] {
		scenario := it;
		for Retain_Backing_Case.[.ARRAYS, .OBJECT, .REUSE] {
			backing_case := it;
			allocation_count := ifx backing_case == .ARRAYS
				then 3
				else ifx backing_case == .OBJECT
					then 1
					else 0;

			for 1..allocation_count + 1 {
				fail_at := it;
				test := prepared_world_registration(scenario, backing_case);
				fixture := test.retained.drain.fixture;
				session := fixture.session;
				probe := Registration_Probe.{fail_at = fail_at};
				before: Service.Resource_Ledger;
				before_slots: [] Service.Registration_Slot;
				before_free: s64;
				before_references: s64;
				before_identities: Service.Session_Identities;
				Service.with_lock(
					*session.gate,
					#code {
						before = session.ledger;
						before_slots = array_copy(session.registry.slots);
						before_free = session.registry.free_slots.count;
						before_references = session.registrations[test.world.slot].world.references;
						before_identities = session.identities;
						session.faults.registration_allocation_hook = registration_allocation_probe;
						session.faults.registration_allocation_data = *probe;
					}
				);

				ok, acquired, error := Service.acquire_world(fixture.host.service, test.selector);
				assert(probe.allocations == min(fail_at, allocation_count));
				Service.with_lock(
					*session.gate,
					#code {
						session.faults.registration_allocation_hook = null;
						assert(session.identities.operation_counter.next == before_identities.operation_counter.next);
						assert(session.identities.world_counter.next == before_identities.world_counter.next && session.identities.result_counter.next == before_identities.result_counter.next);
						assert(session.registrations[test.world.slot].world.references == before_references + xx ok);
						if fail_at <= allocation_count {
							assert(!ok && !acquired.world.owner_token && error.code == .ADMISSION_DENIED && error.admission.kind == .RESOURCE_EXHAUSTED);
							assert(session.registry.slots.count == before_slots.count && session.registry.free_slots.count == before_free);
							for before_slots {
								current := session.registry.slots[it_index];
								assert(current.generation == it.generation && current.kind == it.kind && current.live == it.live && current.retired == it.retired);
							}

							for before.live {
								assert(session.ledger.live[it_index] == it && session.ledger.reserved[it_index] == before.reserved[it_index]);
							}
						} else {
							assert(ok && acquired.kind == .ACQUIRED && Service.handle_is_live(*session.registry, acquired.world));
							assert(session.ledger.live[Service.Limit_Name.LIVE_HANDLES] == before.live[Service.Limit_Name.LIVE_HANDLES] + 1);
							if backing_case == .REUSE {
								assert(acquired.world.slot < xx before_slots.count && acquired.world.generation == before_slots[acquired.world.slot].generation + 1);
							} else {
								assert(acquired.world.slot == xx before_slots.count && acquired.world.generation == 1);
							}
						}
					}
				);

				if ok {
					assert_world_registration(test, acquired.world);
					release(fixture, acquired.world);
				}

				free(before_slots.data);
				finish_world_registration(test);
			}
		}
	}

	print("X5 successful world registration selector/array/object/reuse failure/generation/ledger/reference/identity atomicity \e[92mPASS\e[0m\n");
}

test_world_registration_quota :: () {
	for World_Registration_Case.[.HEAD, .TICKET, .WAITER] {
		test := prepared_world_registration(it, .ARRAYS);
		fixture := test.retained.drain.fixture;
		probe: Registration_Probe;
		before: Service.Resource_Ledger;
		Service.with_lock(
			*fixture.session.gate,
			#code {
				before = fixture.session.ledger;
				fixture.session.ledger.limits.values[Service.Limit_Name.LIVE_HANDLES] = before.live[Service.Limit_Name.LIVE_HANDLES] + before.reserved[Service.Limit_Name.LIVE_HANDLES];
				fixture.session.faults.registration_allocation_hook = registration_allocation_probe;
				fixture.session.faults.registration_allocation_data = *probe;
			}
		);

		ok, acquired, error := Service.acquire_world(fixture.host.service, test.selector);
		assert(!ok && !acquired.world.owner_token && !probe.allocations);
		assert(error.code == .ADMISSION_DENIED && error.admission.kind == .LIMIT && error.admission.limit == .LIVE_HANDLES);
		Service.with_lock(
			*fixture.session.gate,
			#code {
				fixture.session.faults.registration_allocation_hook = null;
				fixture.session.ledger.limits = before.limits;
				for before.live {
					assert(fixture.session.ledger.live[it_index] == it && fixture.session.ledger.reserved[it_index] == before.reserved[it_index]);
				}
			}
		);

		finish_world_registration(test);
	}

	print("X5 successful world registration full quota/no allocation/no admission \e[92mPASS\e[0m\n");
}

test_world_registration_interleavings :: (direct := false, negative_control := false) {
	for World_Registration_Case.[.HEAD, .TICKET, .WAITER] {
		scenario := it;
		for Output_Action.[
			.OTHER_DRAIN,
			.REQUEST_SHUTDOWN,
			.REPLACE_SOURCE,
			.FILL_REGISTRATION_CAPACITY,
			.TAKE_RETAIN_CAPACITY,
			.RELEASE_QUERY_WORLD,
			.RETIRE_SELECTED_WORLD,
			.RETIRE_RETAIN_OWNER
		] {
			action := it;
			if action == .RETIRE_SELECTED_WORLD && scenario != .HEAD || negative_control && action != .RELEASE_QUERY_WORLD {
				continue;
			}


			for s64.[0, 1, 2, 3, 4, 5, 6] {
				fail_at := it;
				if negative_control && fail_at {
					continue;
				}


				test := prepared_world_registration(scenario, .ARRAYS);
				fixture := test.retained.drain.fixture;
				probe := Registration_Probe.{
					fail_at = fail_at,
					direct = direct,
					track_waiter = true,
					job = .{drain = test.retained.drain, action = action},
				};

				if action == .RELEASE_QUERY_WORLD {
					if scenario == {
						case .HEAD;
							probe.job.action = .RETIRE_AND_REUSE_SESSION;
						case .TICKET;
							probe.job.action = .RELEASE_TICKET;
							probe.job.drain.ticket = test.ticket;
						case .WAITER;
							probe.job.action = .RELEASE_WAITER;
							probe.job.drain.first = test.waiter;
					}
				}

				if action == .RETIRE_RETAIN_OWNER {
					array_add(*test.retained.held, test.retained.source);
					array_add(*test.retained.held, test.world);
					probe.job.retained_worlds = test.retained.held;
				}

				if action == .RETIRE_RETAIN_OWNER || action == .RETIRE_SELECTED_WORLD {
					probe.job.retirement_ticket = test.ticket;
					probe.job.retirement_waiter = test.waiter;
					probe.job.retirement_world = test.world;
				}

				Service.with_lock(
					*fixture.session.gate,
					#code {
						probe.track_world = fixture.session.registrations[test.world.slot].world;
						fixture.session.faults.registration_allocation_hook = registration_allocation_probe;
						fixture.session.faults.registration_allocation_data = *probe;
						fixture.session.faults.allow_stale_world_registration = negative_control;
					}
				);

				ok, acquired, error := Service.acquire_world(fixture.host.service, test.selector);
				assert(probe.gate_progress && probe.job.ok && probe.allocations);
				retired := action == .RELEASE_QUERY_WORLD || action == .RETIRE_RETAIN_OWNER;
				if retired && !negative_control {
					expected_kind := ifx scenario == .HEAD
						then Service.Handle_Kind.SESSION
						else ifx scenario == .TICKET
							then .TICKET
							else .WAITER;

					assert(!ok && !acquired.world.owner_token && error.code == .INVALID_HANDLE && error.handle_kind == expected_kind);
				} else if negative_control {
					assert(ok && acquired.kind == .ACQUIRED, "\e[91mStale world-selector negative control was not detected.\e[0m");
				} else if fail_at && fail_at <= probe.allocations {
					assert(!ok && !acquired.world.owner_token && error.code == .ADMISSION_DENIED && error.admission.kind == .RESOURCE_EXHAUSTED);
				} else if action == .TAKE_RETAIN_CAPACITY {
					assert(!ok && !acquired.world.owner_token && error.code == .ADMISSION_DENIED && error.admission.kind == .LIMIT && error.admission.limit == .LIVE_HANDLES);
				} else {
					assert(ok && acquired.kind == .ACQUIRED);
					if action == .FILL_REGISTRATION_CAPACITY {
						assert(probe.allocations == 6);
					}
				}

				if action == .RETIRE_RETAIN_OWNER {
					assert(probe.allocations == (ifx fail_at && fail_at <= 3 then fail_at else 3));
					assert(probe.world_references == 1);
				} else {
					Service.with_lock(
						*fixture.session.gate,
						#code {
							fixture.session.faults.registration_allocation_hook = null;
							fixture.session.faults.allow_stale_world_registration = false;
							for probe.waiter_ledger.live {
								amount := ifx it_index == Service.Limit_Name.LIVE_HANDLES.(s64)
									then xx ok
									else 0;

								assert(
									fixture.session.ledger.live[it_index] == it + amount,
									"\e[91mWorld registration live charge changed: scenario %, action %, failure %, limit %, before %, after %.\e[0m",
									scenario,
									action,
									fail_at,
									it_index,
									it + amount,
									fixture.session.ledger.live[it_index]
								);

								expected_reserved := probe.waiter_ledger.reserved[it_index];
								if (
									action == .REQUEST_SHUTDOWN
									&& it_index == Service.Limit_Name.IN_FLIGHT_OPERATIONS.(s64)
									&& fixture.session.lifecycle == .STOPPED
								) {
									expected_reserved = 0;
								}

								assert(
									fixture.session.ledger.reserved[it_index] == expected_reserved,
									"\e[91mWorld registration reservation changed: scenario %, action %, failure %, limit %, before %, after %.\e[0m",
									scenario,
									action,
									fail_at,
									it_index,
									probe.waiter_ledger.reserved[it_index],
									fixture.session.ledger.reserved[it_index]
								);
							}

							if action == .RETIRE_SELECTED_WORLD {
								assert(probe.world_references == 1);
								if !ok {
									for fixture.session.worlds {
										assert(!Service.bytes_equal(it.identity.([] u8), test.identity));
									}
								}
							} else if !ok {
								assert(fixture.session.registrations[test.world.slot].world.references == probe.world_references - 1);
							}
						}
					);
				}

				if ok {
					assert_world_registration(test, acquired.world);
					Service.with_lock(
						*fixture.session.gate,
						#code {
							assert(fixture.session.registrations[acquired.world.slot].world.references == probe.world_references);
						}
					);

					release(fixture, acquired.world);
				}

				for probe.job.competing_worlds {
					read_ok := Service.read_world(fixture.host.service, it);
					assert(read_ok);
					release(fixture, it);
				}

				if probe.job.replacement_world.owner_token {
					read_ok := Service.read_world(fixture.host.service, probe.job.replacement_world);
					assert(read_ok);
					release(fixture, probe.job.replacement_world);
				}

				if probe.job.replacement.owner_token {
					read_ok := Service.read_result(fixture.host.service, probe.job.replacement);
					assert(read_ok);
					release(fixture, probe.job.replacement);
				}

				array_free(probe.job.competing_worlds);
				free_records(probe.job.records);
				finish_world_registration(
					test,
					source_released = retired,
					selected_released = action == .RETIRE_SELECTED_WORLD,
					owner_released = action == .RETIRE_RETAIN_OWNER
				);
			}
		}
	}

	print(
		"X3/X5 successful world registration selector/shutdown/head replacement/retry/quota/reuse/last reference/owner retirement (direct = %, negative control = %) \e[92mPASS\e[0m\n",
		direct,
		negative_control
	);
}

test_world_registration_failure_control :: () {
	for World_Registration_Case.[.HEAD, .TICKET, .WAITER] {
		test := prepared_world_registration(it, .ARRAYS);
		fixture := test.retained.drain.fixture;
		probe := Registration_Probe.{fail_at = 1};
		Service.with_lock(
			*fixture.session.gate,
			#code {
				fixture.session.faults.registration_allocation_hook = registration_allocation_probe;
				fixture.session.faults.registration_allocation_data = *probe;
				fixture.session.faults.retry_failed_world_registration = true;
			}
		);

		ok, acquired := Service.acquire_world(fixture.host.service, test.selector);
		assert(ok && acquired.kind == .ACQUIRED && probe.allocations == 4, "\e[91mFailed world registration admission negative control was not detected.\e[0m");
		Service.with_lock(
			*fixture.session.gate,
			#code {
				fixture.session.faults.registration_allocation_hook = null;
				fixture.session.faults.retry_failed_world_registration = false;
			}
		);

		assert_world_registration(test, acquired.world);
		release(fixture, acquired.world);
		finish_world_registration(test);
	}

	print("X5 successful world registration failed-admission negative controls \e[92mPASS\e[0m\n");
}

Shutdown_Registration_Fixture :: struct {
	retained: Retain_Fixture(.WORLD);
	first: Service.Handle(.SHUTDOWN);
	held: bool;
}

prepared_shutdown_registration :: (scenario: Retain_Backing_Case, held: bool) -> Shutdown_Registration_Fixture {
	retained := prepared_retain(.WORLD, scenario, held = held);
	fixture := retained.drain.fixture;
	ok, first := Service.request_shutdown(fixture.host.service, fixture.host.session);
	assert(ok);
	if !held {
		observation := await(fixture, first);
		assert(observation.kind == .SHUTDOWN);
		Service.free_observation(*observation);
	}

	return .{retained = retained, first = first, held = held};
}

finish_shutdown_registration :: (test: Shutdown_Registration_Fixture, session_released := false, owner_released := false) {
	fixture := test.retained.drain.fixture;
	if owner_released {
		array_free(test.retained.held);
		assert(!fixture.host.service.owned_allocations && !fixture.host.service.owned_bytes);
		assert_no_owned_allocations();
		return;
	}


	for test.retained.held {
		release(fixture, it);
	}

	array_free(test.retained.held);
	release(fixture, test.retained.source);
	release(fixture, test.first);
	finish_drain(test.retained.drain, session_released = session_released, held = test.held);
}

test_repeated_shutdown_failures :: () {
	for bool.[false, true] {
		held := it;
		for Retain_Backing_Case.[.ARRAYS, .OBJECT, .REUSE] {
			scenario := it;
			allocation_count := ifx scenario == .ARRAYS
				then 3
				else ifx scenario == .OBJECT
					then 1
					else 0;

			for 1..allocation_count + 1 {
				fail_at := it;
				test := prepared_shutdown_registration(scenario, held);
				fixture := test.retained.drain.fixture;
				session := fixture.session;
				probe := Registration_Probe.{fail_at = fail_at};
				before: Service.Resource_Ledger;
				before_slots: [] Service.Registration_Slot;
				before_registrations: s64;
				before_free: s64;
				before_references: s64;
				before_identity: [] u8;
				Service.with_lock(
					*session.gate,
					#code {
						before = session.ledger;
						before_slots = array_copy(session.registry.slots);
						before_registrations = session.registrations.count;
						before_free = session.registry.free_slots.count;
						before_references = session.shutdown.registrations;
						before_identity = array_copy(session.shutdown.identity.([] u8));
						session.identities.operation_counter.next = Service.U64_MAX;
						session.faults.registration_allocation_hook = registration_allocation_probe;
						session.faults.registration_allocation_data = *probe;
					}
				);

				ok, duplicate, error := Service.request_shutdown(fixture.host.service, fixture.host.session);
				assert(probe.allocations == min(fail_at, allocation_count));
				Service.with_lock(
					*session.gate,
					#code {
						session.faults.registration_allocation_hook = null;
						session.faults.registration_allocation_data = null;
						assert(session.identities.operation_counter.next == Service.U64_MAX);
						assert(Service.bytes_equal(session.shutdown.identity.([] u8), before_identity));
						assert(session.lifecycle == (ifx held then Service.Lifecycle.DRAINING else .STOPPED));
						if fail_at <= allocation_count {
							assert(!ok && !duplicate.owner_token && error.code == .ADMISSION_DENIED && error.admission.kind == .RESOURCE_EXHAUSTED);
							assert(session.registry.slots.count == before_slots.count && session.registrations.count == before_registrations);
							assert(session.registry.free_slots.count == before_free && session.shutdown.registrations == before_references);
							for before_slots {
								current := session.registry.slots[it_index];
								assert(current.generation == it.generation && current.kind == it.kind && current.live == it.live && current.retired == it.retired);
							}

							for before.live {
								assert(session.ledger.live[it_index] == it && session.ledger.reserved[it_index] == before.reserved[it_index]);
							}
						} else {
							assert(ok && Service.handle_is_live(*session.registry, duplicate));
							assert(session.registrations[duplicate.slot].operation == session.shutdown);
							assert(session.shutdown.registrations == before_references + 1);
							assert(session.ledger.live[Service.Limit_Name.LIVE_HANDLES] == before.live[Service.Limit_Name.LIVE_HANDLES] + 1);
							if scenario == .REUSE {
								assert(duplicate.slot < xx before_slots.count && duplicate.generation == before_slots[duplicate.slot].generation + 1);
							} else {
								assert(duplicate.slot == xx before_slots.count && duplicate.generation == 1);
							}
						}
					}
				);

				if ok {
					polled, observation := Service.poll(fixture.host.service, duplicate);
					assert(polled && Service.bytes_equal(observation.operation_identity.([] u8), before_identity));
					Service.free_observation(*observation);
					release(fixture, duplicate);
				}

				free(before_identity.data);
				free(before_slots.data);
				finish_shutdown_registration(test);
			}
		}
	}

	print("X5 repeated shutdown array/object failure/reuse/shared identity/counter/ledger/reference atomicity \e[92mPASS\e[0m\n");
}

test_repeated_shutdown_quota :: () {
	for bool.[false, true] {
		held := it;
		test := prepared_shutdown_registration(.ARRAYS, held);
		fixture := test.retained.drain.fixture;
		probe: Registration_Probe;
		before_references: s64;
		Service.with_lock(
			*fixture.session.gate,
			#code {
				fixture.session.ledger.limits.values[Service.Limit_Name.LIVE_HANDLES] = fixture.session.ledger.live[Service.Limit_Name.LIVE_HANDLES]
					+ fixture.session.ledger.reserved[Service.Limit_Name.LIVE_HANDLES];
				before_references = fixture.session.shutdown.registrations;
				fixture.session.faults.registration_allocation_hook = registration_allocation_probe;
				fixture.session.faults.registration_allocation_data = *probe;
			}
		);

		ok, duplicate, error := Service.request_shutdown(fixture.host.service, fixture.host.session);
		assert(!ok && !duplicate.owner_token && !probe.allocations);
		assert(error.code == .ADMISSION_DENIED && error.admission.kind == .LIMIT && error.admission.limit == .LIVE_HANDLES);
		Service.with_lock(
			*fixture.session.gate,
			#code {
				assert(fixture.session.shutdown.registrations == before_references);
				fixture.session.faults.registration_allocation_hook = null;
				fixture.session.faults.registration_allocation_data = null;
			}
		);

		finish_shutdown_registration(test);
	}

	print("X5 repeated shutdown full handle quota/no allocation/no reference mutation \e[92mPASS\e[0m\n");
}

test_repeated_shutdown_interleavings :: (direct := false, negative_control := false) {
	for bool.[false, true] {
		held := it;
		for Output_Action.[
			.OTHER_DRAIN,
			.REQUEST_SHUTDOWN,
			.COMPLETE_SHUTDOWN,
			.FILL_REGISTRATION_CAPACITY,
			.FILL_SHUTDOWN_CAPACITY,
			.TAKE_RETAIN_CAPACITY,
			.STOP_AND_RELEASE_SESSION,
			.RETIRE_AND_REUSE_SESSION,
			.RETIRE_RETAIN_OWNER
		] {
			action := it;
			if negative_control && action != .RETIRE_AND_REUSE_SESSION {
				continue;
			}


			for s64.[0, 1, 2, 3, 4, 5, 6] {
				fail_at := it;
				if negative_control && fail_at {
					continue;
				}


				test := prepared_shutdown_registration(.ARRAYS, held);
				fixture := test.retained.drain.fixture;
				probe := Registration_Probe.{
					fail_at = fail_at,
					direct = direct,
					track_shutdown = true,
					job = .{
						drain = test.retained.drain,
						action = action,
						coordinator_shutdown = test.first,
					},
				};

				if action == .RETIRE_RETAIN_OWNER {
					array_add(*test.retained.held, test.retained.source);
					probe.job.retained_worlds = test.retained.held;
				}

				before_identity: [] u8;
				before_counter: u64;
				Service.with_lock(
					*fixture.session.gate,
					#code {
						before_identity = array_copy(fixture.session.shutdown.identity.([] u8));
						before_counter = fixture.session.identities.operation_counter.next;
						fixture.session.faults.registration_allocation_hook = registration_allocation_probe;
						fixture.session.faults.registration_allocation_data = *probe;
						fixture.session.faults.allow_stale_shutdown_registration = negative_control;
					}
				);

				ok, duplicate, error := Service.request_shutdown(fixture.host.service, fixture.host.session);
				assert(probe.gate_progress && probe.job.ok && probe.allocations);
				retired := action == .STOP_AND_RELEASE_SESSION || action == .RETIRE_AND_REUSE_SESSION || action == .RETIRE_RETAIN_OWNER;
				if retired && !negative_control {
					assert(!ok && !duplicate.owner_token && error.code == .INVALID_HANDLE && error.handle_kind == .SESSION);
				} else if negative_control {
					assert(ok, "\e[91mStale shutdown-session negative control was not detected.\e[0m");
				} else if fail_at && fail_at <= probe.allocations {
					assert(!ok && !duplicate.owner_token && error.code == .ADMISSION_DENIED && error.admission.kind == .RESOURCE_EXHAUSTED);
				} else if action == .TAKE_RETAIN_CAPACITY {
					assert(!ok && !duplicate.owner_token && error.code == .ADMISSION_DENIED && error.admission.kind == .LIMIT && error.admission.limit == .LIVE_HANDLES);
				} else {
					assert(ok);
					if action == .FILL_REGISTRATION_CAPACITY || action == .FILL_SHUTDOWN_CAPACITY {
						assert(probe.allocations == 6);
					}
				}

				if action == .RETIRE_RETAIN_OWNER {
					assert(probe.allocations == (ifx fail_at && fail_at <= 3 then fail_at else 3));
				} else {
					Service.with_lock(
						*fixture.session.gate,
						#code {
							fixture.session.faults.registration_allocation_hook = null;
							fixture.session.faults.registration_allocation_data = null;
							assert(fixture.session.identities.operation_counter.next == before_counter);
							assert(Service.bytes_equal(fixture.session.shutdown.identity.([] u8), before_identity));
							assert(fixture.session.shutdown.registrations == probe.shutdown_references + xx ok);
							assert(fixture.session.ledger.live[Service.Limit_Name.LIVE_HANDLES] == probe.shutdown_live + xx ok);
							if action == .COMPLETE_SHUTDOWN {
								assert(fixture.session.lifecycle == .STOPPED);
							}
						}
					);
				}

				if ok {
					polled, observation := Service.poll(fixture.host.service, duplicate);
					assert(polled && Service.bytes_equal(observation.operation_identity.([] u8), before_identity));
					Service.free_observation(*observation);
					release(fixture, duplicate);
				}

				for probe.job.competing_worlds {
					read_ok := Service.read_world(fixture.host.service, it);
					assert(read_ok);
					release(fixture, it);
				}

				for probe.job.competing_shutdowns {
					polled, observation := Service.poll(fixture.host.service, it);
					assert(polled && Service.bytes_equal(observation.operation_identity.([] u8), before_identity));
					Service.free_observation(*observation);
					release(fixture, it);
				}

				if probe.job.replacement_world.owner_token {
					read_ok := Service.read_world(fixture.host.service, probe.job.replacement_world);
					assert(read_ok);
					release(fixture, probe.job.replacement_world);
				}

				array_free(probe.job.competing_worlds);
				array_free(probe.job.competing_shutdowns);
				free_records(probe.job.records);
				free(before_identity.data);
				finish_shutdown_registration(
					test,
					session_released = retired,
					owner_released = action == .RETIRE_RETAIN_OWNER
				);
			}
		}
	}

	print(
		"X3/X5 repeated shutdown allocation/drain/stopped/retry/quota/session reuse/owner retirement (direct = %, negative control = %) \e[92mPASS\e[0m\n",
		direct,
		negative_control
	);
}

test_shutdown_reserve_failures :: () {
	ceilings: Service.Limits;
	for * ceilings.values {
		it.* = 1 << 20;
	}

	service := Service.open_service(xx "shutdown-reserve-error", 1, ceilings, .{});
	probe: Output_Probe;
	allocator := open_output_probe(*probe);
	for 1..7 {
		fail_at := it;
		service.fail_shutdown_reserve_at = fail_at;
		service.shutdown_reserve_attempts = 0;
		probe.allocations = 0;
		token := service.incarnation.session_counter.next;
		ok, opened, error := Service.open_session(service, open_output_options(),, allocator);
		assert(service.incarnation.session_counter.next == token + 1);
		assert(service.shutdown_reserve_attempts == min(fail_at, 6));
		if fail_at <= 6 {
			assert(!ok && !opened.session.owner_token && !opened.description.session_identity.count && !probe.allocations);
			assert(error.code == .ADMISSION_DENIED && error.admission.kind == .RESOURCE_EXHAUSTED);
			assert(!service.sessions.count && !service.owned_allocations && !service.owned_bytes);
			assert_no_owned_allocations();
		} else {
			assert(ok && probe.allocations == 5);
			session := Service.session_of(service, opened.session);
			assert(session.registry.slots.count == 2 && session.registrations.count == 2);
			assert(session.registry.slots[0].live && !session.registry.slots[1].live && !session.registry.free_slots.count);
			assert(!Service.handle_is_live(*session.registry, session.shutdown_registration));
			assert(session.identities.operation_counter.next == 1);
			Service.free_description(*opened.description,, allocator);
			service.fail_shutdown_reserve_at = 0;
			close_output_session(service, opened.session);
			assert_no_owned_allocations();
		}
	}

	close_output_probe(*probe);
	print("X5 first-shutdown physical reserve every allocation failure/private cleanup/nonlive slot \e[92mPASS\e[0m\n");
}

test_shutdown_reserved_activation :: (pressure := false, negative_control := false) {
	fixture := open("X5-shutdown-physical-reserve", 4);
	world: Service.Handle(.WORLD);
	copy: Service.Handle(.WORLD);
	if pressure {
		ticket := submit(fixture, "answer :: 42;");
		world = world_of(fixture, ticket);
		release(fixture, ticket);
		retained, duplicate := Service.retain(fixture.host.service, world);
		assert(retained);
		copy = duplicate;
	}

	session := fixture.session;
	reserved_handle: Service.Handle(.SHUTDOWN);
	token: u64;
	before_slots: s64;
	before_registrations: s64;
	Service.with_lock(
		*session.gate,
		#code {
			reserved_handle = session.shutdown_registration;
			token = session.identities.operation_counter.next;
			before_slots = session.registry.slots.count;
			before_registrations = session.registrations.count;
			assert(!Service.handle_is_live(*session.registry, reserved_handle));
			for session.registry.free_slots {
				assert(it != reserved_handle.slot);
			}

			if pressure {
				assert(session.ledger.live[Service.Limit_Name.LIVE_HANDLES] + session.ledger.reserved[Service.Limit_Name.LIVE_HANDLES] == 4);
			}

			session.faults.allocate_shutdown_backing = negative_control;
		}
	);

	token_bytes := Service.little_endian(token, 8);
	expected_identity := Service.make_key("operation", fixture.host.session_identity.([] u8), token_bytes);
	defer free(token_bytes.data);
	defer free(expected_identity.data);

	before_allocations: s64;
	Service.with_lock(
		*allocation_ledger.gate,
		#code {
			before_allocations = allocation_ledger.allocation_attempts;
			allocation_ledger.reject_allocations = !negative_control;
		}
	);

	ok, shutdown, error := Service.request_shutdown(fixture.host.service, fixture.host.session);
	allocation_count: s64;
	Service.with_lock(
		*allocation_ledger.gate,
		#code {
			allocation_ledger.reject_allocations = false;
			allocation_count = allocation_ledger.allocation_attempts - before_allocations;
		}
	);

	assert(ok, "\e[91mReserved shutdown failed: %.\e[0m", error);
	if negative_control {
		assert(allocation_count > 0, "\e[91mAllocating shutdown negative control was not detected.\e[0m");
	} else {
		assert(!allocation_count && shutdown.slot == reserved_handle.slot && shutdown.generation == reserved_handle.generation);
		assert(session.registry.slots.count == before_slots && session.registrations.count == before_registrations);
	}

	Service.with_lock(
		*session.gate,
		#code {
			assert(session.identities.operation_counter.next == token + 1);
			assert(Service.bytes_equal(session.shutdown.identity.([] u8), expected_identity));
			assert(Service.handle_is_live(*session.registry, shutdown));
		}
	);

	observation := await(fixture, shutdown);
	assert(observation.kind == .SHUTDOWN);
	Service.free_observation(*observation);
	if pressure {
		read_ok, borrowed := Service.read_world(fixture.host.service, copy);
		assert(read_ok && Service.bytes_equal(borrowed.members[0].source.bytes, xx "answer :: 42;"));
		release(fixture, copy);
		release(fixture, world);
	}

	release(fixture, shutdown);
	close(fixture);
	print("X5 first-shutdown no allocation/canonical identity/reserved slot (pressure = %, negative control = %) \e[92mPASS\e[0m\n", pressure, negative_control);
}

test_shutdown_identity_exhaustion :: () {
	fixture := open("X5-shutdown-identity-exhaustion");
	session := fixture.session;
	before: Service.Resource_Ledger;
	Service.with_lock(
		*session.gate,
		#code {
			session.identities.operation_counter.next = Service.U64_MAX;
			before = session.ledger;
		}
	);

	ok, shutdown, error := Service.request_shutdown(fixture.host.service, fixture.host.session);
	assert(!ok && !shutdown.owner_token && error.code == .ADMISSION_DENIED && error.admission.kind == .RESOURCE_EXHAUSTED);
	Service.with_lock(
		*session.gate,
		#code {
			assert(session.lifecycle == .OPEN && !session.shutdown);
			assert(!Service.handle_is_live(*session.registry, session.shutdown_registration));
			assert(session.identities.operation_counter.next == Service.U64_MAX);
			for before.live {
				assert(session.ledger.live[it_index] == it && session.ledger.reserved[it_index] == before.reserved[it_index]);
			}

			session.identities.operation_counter.next = Service.U64_MAX - 1;
		}
	);

	last_ok, last := Service.request_shutdown(fixture.host.service, fixture.host.session);
	assert(last_ok && session.identities.operation_counter.next == Service.U64_MAX);
	token_bytes := Service.little_endian(Service.U64_MAX - 1, 8);
	expected := Service.make_key("operation", fixture.host.session_identity.([] u8), token_bytes);
	assert(Service.bytes_equal(session.shutdown.identity.([] u8), expected));
	free(expected.data);
	free(token_bytes.data);
	observation := await(fixture, last);
	Service.free_observation(*observation);
	release(fixture, last);
	close(fixture);
	print("X5 first-shutdown identity exhaustion/no mutation/final token canonical encoding \e[92mPASS\e[0m\n");
}

Provider_Error_Case :: enum {
	SESSION;
	MISSING_EVENTS;
	CONTEXT_ENCODING;
	CONTEXT_DUPLICATE;
	DUPLICATE_EVENT;
	SOURCE_CONTEXT;
	DOCUMENT_MISMATCH;
	UNSUPPORTED;
	CAPABILITY;
	SOURCE_LIMIT;
	VERSION;
}

prepare_provider_error :: (
	batch: *Service.Source_Batch,
	scenario: Provider_Error_Case,
	registration: Service.Context_Registration,
	oversized_source: [] u8
) {
	if scenario == {
		case .SESSION;
			batch.session = xx "wrong-session";

		case .MISSING_EVENTS;
			batch.events = .[];

		case .CONTEXT_ENCODING;
			batch.contexts = NewArray(1, Service.Context_Registration);
			batch.contexts[0] = .{identity = xx "invalid-context", descriptor = registration.descriptor};

		case .CONTEXT_DUPLICATE;
			batch.contexts = NewArray(2, Service.Context_Registration);
			batch.contexts[0] = registration;
			batch.contexts[1] = registration;

		case .DUPLICATE_EVENT;
			events := NewArray(2, Service.Document_Event);
			events[0] = batch.events[0];
			events[1] = batch.events[0];
			batch.events = events;

		case .SOURCE_CONTEXT;
			batch.events[0].source_context = xx "unknown-context";

		case .DOCUMENT_MISMATCH;
			batch.events[0].expected_provider_state = .{};

		case .UNSUPPORTED;
			batch.events[0].kind = .RENAME;

		case .CAPABILITY;
			batch.events[0].kind = .OBSERVE_DISK;
			batch.events[0].disk = .{
				syntax_context = batch.events[0].source_context,
				source = .{kind = .PROVIDER_LEASE},
				provenance = .{
					provider_identity = xx "provider",
					observation_token = xx "observation",
				},
			};

		case .SOURCE_LIMIT;
			batch.events[0].source.bytes = oversized_source;

		case .VERSION;
			batch.version = "invalid-version";
	}
}

free_provider_error_batch :: (batch: Service.Source_Batch, scenario: Provider_Error_Case) {
	if scenario == .CONTEXT_ENCODING || scenario == .CONTEXT_DUPLICATE {
		free(batch.contexts.data);
	} else if scenario == .DUPLICATE_EVENT {
		free(batch.events.data);
	}
}

assert_provider_error :: (error: Service.Operation_Error, scenario: Provider_Error_Case, document: [] u8) {
	if scenario == .VERSION {
		assert(error.code == .INVALID_VERSION && !error.path.count && !error.document.count);
		return;
	}


	if scenario == .SESSION || scenario == .MISSING_EVENTS {
		assert(error.code == .INVALID_ARGUMENT && error.path.count == 1 && error.path[0].kind == .FIELD);
		assert(error.rule == (ifx scenario == .SESSION then Service.Argument_Rule.INCONSISTENT_BINDING else .MISSING));
		assert(error.path[0].name == (ifx scenario == .SESSION then "session" else "events"));
		return;
	}


	if scenario == .CONTEXT_ENCODING || scenario == .CONTEXT_DUPLICATE {
		assert_context_error(error, scenario == .CONTEXT_DUPLICATE);
		return;
	}


	assert(error.path.count >= 2 && error.path[0].kind == .FIELD && error.path[0].name == "events");
	assert(error.path[1].kind == .ELEMENT && error.path[1].index == (ifx scenario == .DUPLICATE_EVENT then 1 else 0));
	if scenario == {
		case .DUPLICATE_EVENT; #through;
		case .SOURCE_CONTEXT;
			assert(error.code == .INVALID_ARGUMENT && error.path.count == 3 && error.path[2].kind == .FIELD);
			assert(error.rule == (ifx scenario == .DUPLICATE_EVENT then Service.Argument_Rule.DUPLICATE else .INCONSISTENT_BINDING));
			assert(error.path[2].name == (ifx scenario == .DUPLICATE_EVENT then "document" else "source_context"));

		case .DOCUMENT_MISMATCH;
			assert(error.code == .BASE_MISMATCH && error.scope == .DOCUMENT && error.path.count == 2);
			assert(Service.bytes_equal(error.document, document) && error.document.data != document.data);

		case .UNSUPPORTED;
			assert(error.code == .UNSUPPORTED_EVENT && error.event_tag == "RENAME" && error.path.count == 2);

		case .CAPABILITY;
			assert(error.code == .ADMISSION_DENIED && error.admission.kind == .CAPABILITY && error.admission.schema == "PROVIDER_LEASE");
			assert(error.path.count == 4 && error.path[2].kind == .FIELD && error.path[2].name == "disk");
			assert(error.path[3].kind == .FIELD && error.path[3].name == "source");

		case .SOURCE_LIMIT;
			assert(error.code == .ADMISSION_DENIED && error.admission.kind == .LIMIT && error.admission.limit == .SOURCE_BYTES);
			assert(error.path.count == 2);
	}

	if scenario != .DOCUMENT_MISMATCH {
		assert(!error.document.count);
	}
}

test_provider_error_failures :: () {
	registration := error_context_registration();
	oversized_source := NewArray((1 << 20) + 1, u8);
	defer free(registration.identity.data);
	defer free(registration.descriptor.data);
	defer free(oversized_source.data);

	for Provider_Error_Case.[
		.SESSION,
		.MISSING_EVENTS,
		.CONTEXT_ENCODING,
		.CONTEXT_DUPLICATE,
		.DUPLICATE_EVENT,
		.SOURCE_CONTEXT,
		.DOCUMENT_MISMATCH,
		.UNSUPPORTED,
		.CAPABILITY,
		.SOURCE_LIMIT,
		.VERSION,
	] {
		scenario := it;
		drain := prepared_drain("X5-provider-error");
		fixture := drain.fixture;
		batch := Service.begin_batch(fixture.host);
		assert(Service.set_overlay(*batch, "a.jai", "answer :: 77;"));
		source_batch := receipt_source_batch(batch);
		document := source_batch.events[0].document;
		prepare_provider_error(*source_batch, scenario, registration, oversized_source);
		allocation_count: s64 = ifx scenario == .DOCUMENT_MISMATCH
			then 2
			else ifx scenario == .VERSION
				then 0
				else 1;

		before: Service.Resource_Ledger;
		before_operations: s64;
		before_slots: s64;
		before_contexts: s64;
		before_completions: s64;
		Service.with_lock(
			*fixture.session.gate,
			#code {
				before = fixture.session.ledger;
				before_operations = fixture.session.operations.count;
				before_slots = fixture.session.registry.slots.count;
				before_contexts = fixture.session.provider.contexts.count;
				before_completions = fixture.session.completions.count;
			}
		);

		probe: Output_Probe;
		allocator := open_output_probe(*probe);
		for 1..allocation_count + 1 {
			probe.fail_at = it;
			probe.allocations = 0;
			ok, accepted, error := Service.submit_source_batch(fixture.host.service, fixture.host.session, source_batch,, allocator);
			assert(!ok && !accepted.ticket.owner_token && !accepted.frontier.count);
			assert(probe.allocations == min(probe.fail_at, allocation_count));
			if probe.fail_at <= allocation_count {
				assert(error.code == .ADMISSION_DENIED && error.admission.kind == .RESOURCE_EXHAUSTED && !error.path.count && !error.document.count);
			} else {
				assert_provider_error(error, scenario, document);
				probe.fail_at = 0;
				second_ok, second, second_error := Service.submit_source_batch(fixture.host.service, fixture.host.session, source_batch,, allocator);
				assert(!second_ok && !second.ticket.owner_token);
				assert_provider_error(second_error, scenario, document);
				if error.path.count {
					assert(error.path.data != second_error.path.data);
					error.path[0].kind = .ELEMENT;
				}

				if error.document.count {
					assert(error.document.data != second_error.document.data);
					error.document[0] ^= 0xFF;
				}

				assert_provider_error(second_error, scenario, document);
				free(second_error.path.data,, allocator);
				free(second_error.document.data,, allocator);
			}

			free(error.path.data,, allocator);
			free(error.document.data,, allocator);
			assert(!probe.backing.live_bytes && !probe.backing.sizes.count);
			Service.with_lock(
				*fixture.session.gate,
				#code {
					assert(Service.bytes_equal(fixture.session.provider.accepted_frontier, source_batch.expected_frontier));
					assert(fixture.session.operations.count == before_operations && fixture.session.registry.slots.count == before_slots);
					assert(fixture.session.provider.contexts.count == before_contexts && fixture.session.completions.count == before_completions);
					assert(!fixture.session.active_admissions);
					for before.live {
						assert(fixture.session.ledger.live[it_index] == it && fixture.session.ledger.reserved[it_index] == before.reserved[it_index]);
					}
				}
			);
		}

		if scenario == .CONTEXT_ENCODING {
			Service.with_lock(
				*fixture.session.gate,
				#code {
					fixture.session.faults.allow_failed_argument_error = true;
				}
			);

			probe.fail_at = 1;
			probe.allocations = 0;
			control_ok, control, control_error := Service.submit_source_batch(fixture.host.service, fixture.host.session, source_batch,, allocator);
			assert(!control_ok && !control.ticket.owner_token && probe.allocations == 1);
			assert(control_error.code == .INVALID_ARGUMENT && !control_error.path.count, "\e[91mFailed provider diagnostic copy was not detected.\e[0m");
		}

		close_output_probe(*probe);
		free_provider_error_batch(source_batch, scenario);
		finish_drain(drain);
	}

	print("X5 provider diagnostic every allocation failure/path/document isolation/no admission/negative control \e[92mPASS\e[0m\n");
}

test_provider_error_interleavings :: (direct := false) {
	registration := error_context_registration();
	defer free(registration.identity.data);
	defer free(registration.descriptor.data);

	for Provider_Error_Case.[.DOCUMENT_MISMATCH, .CONTEXT_DUPLICATE] {
		scenario := it;
		allocation_count := ifx scenario == .DOCUMENT_MISMATCH
			then 2
			else 1;

		for Output_Action.[.REPLACE_SOURCE, .REQUEST_SHUTDOWN, .REJECT_ACTIVE_RELEASE, .OTHER_DRAIN] {
			action := it;
			for 1..allocation_count + 1 {
				fail_at := it;
				drain := prepared_drain("X3-X5-provider-error");
				fixture := drain.fixture;
				batch := Service.begin_batch(fixture.host);
				assert(Service.set_overlay(*batch, "a.jai", "answer :: 77;"));
				source_batch := receipt_source_batch(batch);
				document := source_batch.events[0].document;
				prepare_provider_error(*source_batch, scenario, registration, .[]);
				probe := Output_Probe.{
					fail_at = fail_at,
					direct = direct,
					job = .{drain = drain, action = action},
				};

				allocator := open_output_probe(*probe);
				ok, accepted, error := Service.submit_source_batch(fixture.host.service, fixture.host.session, source_batch,, allocator);
				assert(!ok && !accepted.ticket.owner_token && !accepted.frontier.count);
				assert(probe.gate_progress && probe.job.ok && probe.allocations == min(fail_at, allocation_count));
				if action == .REPLACE_SOURCE {
					assert(error.code == .BASE_MISMATCH && error.scope == .FRONTIER && !error.path.count && !error.document.count);
				} else if action == .REQUEST_SHUTDOWN {
					assert(error.code == .SERVICE_CLOSED && !error.path.count && !error.document.count);
				} else if fail_at <= allocation_count {
					assert(error.code == .ADMISSION_DENIED && error.admission.kind == .RESOURCE_EXHAUSTED && !error.path.count && !error.document.count);
				} else {
					assert_provider_error(error, scenario, document);
				}

				free(error.path.data,, allocator);
				free(error.document.data,, allocator);
				free_records(probe.job.records);
				close_output_probe(*probe);
				free_provider_error_batch(source_batch, scenario);
				finish_drain(drain);
			}
		}
	}

	print("X3/X5 provider diagnostic partial copy/frontier/shutdown/release/drain (direct = %) \e[92mPASS\e[0m\n", direct);
}

error_context_registration :: () -> Service.Context_Registration {
	_, filename := Service.windows_path_value("D:/error/context.jai");
	_, directory := Service.windows_path_value("D:/error");
	_, base := Service.windows_path_value("D:/error");
	ok, descriptor := Service.syntax_context_descriptor(
		.{
			visible_filename = filename,
			visible_directory = directory,
			relative_base = base,
		}
	);

	assert(ok);
	free(filename.code_units.data);
	free(directory.code_units.data);
	free(base.code_units.data);
	return .{identity = Service.context_id(descriptor), descriptor = descriptor};
}

assert_context_error :: (error: Service.Operation_Error, duplicate: bool) {
	assert(error.code == .INVALID_ARGUMENT);
	assert(error.rule == (ifx duplicate then Service.Argument_Rule.DUPLICATE else .INVALID_ENCODING));
	assert(error.path.count == 2 && error.path[0].kind == .FIELD && error.path[0].name == "contexts");
	assert(error.path[1].kind == .ELEMENT && error.path[1].index == (ifx duplicate then 1 else 0));
}

test_open_context_failures :: () {
	registration := error_context_registration();
	defer free(registration.identity.data);
	defer free(registration.descriptor.data);

	ceilings: Service.Limits;
	for * ceilings.values {
		it.* = 1 << 20;
	}

	service := Service.open_service(xx "open-context-error", 1, ceilings, .{});
	for bool.[false, true] {
		duplicate := it;
		registrations := Service.Context_Registration.[registration, registration];
		options := open_output_options();
		options.contexts = registrations;
		if !duplicate {
			registrations[0].identity = xx "invalid-context";
			options.contexts.count = 1;
		}

		probe: Output_Probe;
		allocator := open_output_probe(*probe);
		for 1..2 {
			probe.fail_at = it;
			probe.allocations = 0;
			token := service.incarnation.session_counter.next;
			ok, opened, error := Service.open_session(service, options,, allocator);
			assert(!ok && !opened.session.owner_token && !opened.description.session_identity.count && probe.allocations == 1);
			assert(service.incarnation.session_counter.next == token + 1 && !service.sessions.count);
			assert(!service.owned_allocations && !service.owned_bytes);
			assert_no_owned_allocations();
			if probe.fail_at == 1 {
				assert(error.code == .ADMISSION_DENIED && error.admission.kind == .RESOURCE_EXHAUSTED && !error.path.count);
			} else {
				assert_context_error(error, duplicate);
				probe.fail_at = 0;
				second_ok, second, second_error := Service.open_session(service, options,, allocator);
				assert(!second_ok && !second.session.owner_token);
				assert_context_error(second_error, duplicate);
				assert(error.path.data != second_error.path.data);
				error.path[1].index = 99;
				assert_context_error(second_error, duplicate);
				free(second_error.path.data,, allocator);
			}

			free(error.path.data,, allocator);
			assert(!probe.backing.live_bytes && !probe.backing.sizes.count);
		}

		service.allow_failed_open_output = true;
		probe.allocations = 0;
		probe.fail_at = 1;
		control_ok, control, control_error := Service.open_session(service, options,, allocator);
		assert(!control_ok && !control.session.owner_token && probe.allocations == 1);
		assert(control_error.code == .INVALID_ARGUMENT && !control_error.path.count, "\e[91mFailed context diagnostic copy was not detected.\e[0m");
		service.allow_failed_open_output = false;
		close_output_probe(*probe);
		assert_no_owned_allocations();
	}

	print("X5 private-open context diagnostic failure/owner lifetime/isolation/negative control \e[92mPASS\e[0m\n");
}

test_open_context_interleavings :: (direct := false) {
	registration := error_context_registration();
	defer free(registration.identity.data);
	defer free(registration.descriptor.data);

	for bool.[false, true] {
		duplicate := it;
		for bool.[false, true] {
			fail_copy := it;
			drain := prepared_drain("X4-X5-open-context-error");
			service := drain.fixture.host.service;
			token := service.incarnation.session_counter.next;
			registrations := Service.Context_Registration.[registration, registration];
			options := open_output_options();
			options.contexts = registrations;
			if !duplicate {
				registrations[0].identity = xx "invalid-context";
				options.contexts.count = 1;
			}

			probe := Output_Probe.{
				fail_at = (ifx fail_copy then 1),
				direct = direct,
				job = .{drain = drain, action = .CHECK_PRIVATE_OPEN},
			};

			allocator := open_output_probe(*probe);
			ok, opened, error := Service.open_session(service, options,, allocator);
			assert(!ok && !opened.session.owner_token && probe.allocations == 1);
			assert(probe.gate_progress && probe.job.ok && service.incarnation.session_counter.next == token + 1);
			assert(service.sessions.count == 1 && probe.job.records.count == 2);
			if fail_copy {
				assert(error.code == .ADMISSION_DENIED && error.admission.kind == .RESOURCE_EXHAUSTED && !error.path.count);
			} else {
				assert_context_error(error, duplicate);
			}

			free(error.path.data,, allocator);
			free_records(probe.job.records);
			close_output_probe(*probe);
			finish_drain(drain);
		}
	}

	print("X4/X5 private-open context diagnostic allocation/reentry/cleanup (direct = %) \e[92mPASS\e[0m\n", direct);
}

open_argument_options :: (scenario: s64) -> Service.Session_Options {
	options := open_output_options();
	if scenario == {
		case 0;
			options.workspace = .[];

		case 1;
			options.provider_namespace = .[];

		case 2;
			options.host_authority = .[];

		case 3;
			options.requested_limits.values[Service.Limit_Name.OWNED_BYTES] = -2;
	}

	return options;
}

assert_open_argument_path :: (error: Service.Operation_Error, scenario: s64) {
	names := string.["workspace", "provider_namespace", "host_authority", "requested_limits"];
	rule := ifx scenario == 3
		then Service.Argument_Rule.OUT_OF_RANGE
		else Service.Argument_Rule.MISSING;

	assert(error.code == .INVALID_ARGUMENT && error.rule == rule && error.path.count == 1);
	assert(error.path[0].kind == .FIELD && error.path[0].name == names[scenario]);
}

test_open_argument_failures :: () {
	ceilings: Service.Limits;
	for * ceilings.values {
		it.* = 1 << 20;
	}

	service := Service.open_service(xx "open-argument-authority", 1, ceilings, .{});
	probe: Output_Probe;
	cached_probe: Output_Probe;
	allocator := open_output_probe(*probe);
	cached_allocator := open_output_probe(*cached_probe);
	previous_output := context.cache_service_output_allocator;
	context.cache_service_output_allocator = cached_allocator;
	for s64.[0, 1, 2, 3] {
		scenario := it;
		options := open_argument_options(scenario);
		for 1..2 {
			probe.fail_at = it;
			probe.allocations = 0;
			ok, opened, error := Service.open_session(service, options,, allocator);
			assert(!ok && !opened.session.owner_token && !opened.session.generation);
			assert(!opened.description.session_identity.count && probe.allocations == 1 && !cached_probe.allocations);
			if probe.fail_at == 1 {
				assert(error.code == .ADMISSION_DENIED && error.admission.kind == .RESOURCE_EXHAUSTED && !error.path.count);
			} else {
				assert_open_argument_path(error, scenario);
				probe.fail_at = 0;
				second_ok, second, second_error := Service.open_session(service, options,, allocator);
				assert(!second_ok && !second.session.owner_token);
				assert_open_argument_path(second_error, scenario);
				assert(second_error.path.data != error.path.data);
				error.path[0].kind = .ELEMENT;
				assert_open_argument_path(second_error, scenario);
				free(second_error.path.data,, allocator);
			}

			free(error.path.data,, allocator);
			assert(service.incarnation.session_counter.next == 1 && !service.sessions.count);
			assert(!service.owned_allocations && !service.owned_bytes && !probe.backing.live_bytes && !probe.backing.sizes.count);
			assert_no_owned_allocations();
		}

		service.allow_failed_open_argument = true;
		probe.fail_at = 1;
		probe.allocations = 0;
		control_ok, control, control_error := Service.open_session(service, options,, allocator);
		assert(!control_ok && !control.session.owner_token && probe.allocations == 1);
		assert(control_error.code == .INVALID_ARGUMENT && !control_error.path.count, "\e[91mFailed pre-owner diagnostic copy was not detected.\e[0m");
		service.allow_failed_open_argument = false;
		service.cached_open_argument_allocator = true;
		probe.allocations = 0;
		cached_probe.allocations = 0;
		cached_ok, cached, cached_error := Service.open_session(service, options,, allocator);
		assert(!cached_ok && !cached.session.owner_token && !probe.allocations && cached_probe.allocations == 1, "\e[91mInherited pre-owner allocator misuse was not detected.\e[0m");
		assert_open_argument_path(cached_error, scenario);
		free(cached_error.path.data,, cached_allocator);
		service.cached_open_argument_allocator = false;
		cached_probe.allocations = 0;
	}

	assert(service.incarnation.session_counter.next == 1 && !service.sessions.count && !service.owned_allocations && !service.owned_bytes);
	context.cache_service_output_allocator = previous_output;
	close_output_probe(*cached_probe);
	close_output_probe(*probe);
	assert_no_owned_allocations();
	print("X5 pre-owner open diagnostic failure/isolation/caller allocator/no identity/negative controls \e[92mPASS\e[0m\n");
}

test_open_argument_interleavings :: (direct := false) {
	for s64.[0, 1, 2, 3] {
		scenario := it;
		for bool.[false, true] {
			fail_copy := it;
			drain := prepared_drain("X4-X5-open-argument");
			service := drain.fixture.host.service;
			token := service.incarnation.session_counter.next;
			probe := Output_Probe.{
				fail_at = (ifx fail_copy then 1),
				direct = direct,
				job = .{drain = drain, action = .CHECK_PRIVATE_OPEN},
			};

			allocator := open_output_probe(*probe);
			ok, opened, error := Service.open_session(service, open_argument_options(scenario),, allocator);
			assert(!ok && !opened.session.owner_token && probe.allocations == 1);
			assert(probe.gate_progress && probe.job.ok && service.incarnation.session_counter.next == token);
			assert(service.sessions.count == 1 && probe.job.records.count == 2);
			if fail_copy {
				assert(error.code == .ADMISSION_DENIED && error.admission.kind == .RESOURCE_EXHAUSTED && !error.path.count);
			} else {
				assert_open_argument_path(error, scenario);
			}

			free(error.path.data,, allocator);
			free_records(probe.job.records);
			close_output_probe(*probe);
			finish_drain(drain);
		}
	}

	print("X4/X5 pre-owner open diagnostic allocation permits reentry without identity issuance (direct = %) \e[92mPASS\e[0m\n", direct);
}

test_open_output_failures :: () {
	ceilings: Service.Limits;
	for * ceilings.values {
		it.* = 1 << 20;
	}

	minima: Service.Limits;
	minima.values[Service.Limit_Name.LIVE_HANDLES] = 2;
	minima.values[Service.Limit_Name.IN_FLIGHT_OPERATIONS] = 1;
	service := Service.open_service(xx "open-output-authority", 1, ceilings, minima);
	options := open_output_options();
	probe: Output_Probe;
	allocator := open_output_probe(*probe);
	for ([] Service.Schema_Tuple).[
		.[],
		.[Service.IMPLEMENTED_SCHEMA_TUPLE, Service.IMPLEMENTED_SCHEMA_TUPLE],
		.[Service.Schema_Tuple.{}],
	] {
		invalid_options := options;
		invalid_options.supported_tuples = it;
		admitted, rejected := Service.open_session(service, invalid_options,, allocator);
		assert(!admitted && !rejected.session.generation && !probe.allocations);
		assert(service.incarnation.session_counter.next == 1 && !service.sessions.count);
		assert_no_owned_allocations();
	}

	service.fail_worker_startup = true;
	started, failed_start, start_error := Service.open_session(service, options,, allocator);
	assert(!started && start_error.code == .ADMISSION_DENIED && start_error.admission.kind == .RESOURCE_EXHAUSTED);
	assert(probe.allocations == 5 && !failed_start.session.generation);
	Service.free_description(*failed_start.description,, allocator);
	assert(!probe.backing.live_bytes && !probe.backing.sizes.count);
	assert(!service.sessions.count && !service.owned_allocations && !service.owned_bytes);
	assert_no_owned_allocations();
	service.fail_worker_startup = false;
	fail_at: s64 = 1;
	while true {
		probe.fail_at = fail_at;
		probe.allocations = 0;
		token := service.incarnation.session_counter.next;
		ok, opened, error := Service.open_session(service, options,, allocator);
		assert(service.incarnation.session_counter.next == token + 1, "\e[91mA failed open reused a session identity.\e[0m");
		if ok {
			assert(fail_at == 6 && probe.allocations == 5);
			assert(service.sessions.count == 1 && opened.session.generation == 1);
			described, expected := Service.describe_session(service, opened.session);
			assert(described);
			assert_description_copy(opened.description, expected);
			opened.description.workspace[0] ^= 0xFF;
			_, current := Service.describe_session(service, opened.session);
			assert_description_copy(current, expected);
			Service.free_description(*current);
			Service.free_description(*expected);
			Service.free_description(*opened.description,, allocator);
			close_output_session(service, opened.session);
			break;
		}


		assert(error.code == .ADMISSION_DENIED && error.admission.kind == .RESOURCE_EXHAUSTED);
		assert(!opened.session.generation && !opened.description.session_identity.count);
		Service.free_description(*opened.description,, allocator);
		assert(!probe.backing.live_bytes && !probe.backing.sizes.count);
		assert(!service.sessions.count && !service.owned_allocations && !service.owned_bytes);
		assert_no_owned_allocations();
		fail_at += 1;
		assert(fail_at <= 6);
	}

	assert(!service.sessions.count && !service.owned_allocations && !service.owned_bytes);
	assert_no_owned_allocations();
	control_service := Service.open_service(xx "open-output-control-authority", 1, ceilings, minima);
	control_service.allow_failed_open_output = true;
	probe.fail_at = 1;
	probe.allocations = 0;
	control_ok, control := Service.open_session(control_service, options,, allocator);
	assert(control_ok && !control.description.session_identity.count && probe.allocations == 1, "\e[91mFailed-copy admission negative control was not detected.\e[0m");
	Service.free_description(*control.description,, allocator);
	close_output_session(control_service, control.session);
	assert(!control_service.sessions.count && !control_service.owned_allocations && !control_service.owned_bytes);
	assert_no_owned_allocations();
	close_output_probe(*probe);
	print("X5 open-session output/startup failure cleanup and admission negative control \e[92mPASS\e[0m\n");
}

test_open_output_interleavings :: (direct := false) {
	for bool.[false, true] {
		fail_copy := it;
		drain := prepared_drain("X4-X5-open-output");
		probe := Output_Probe.{
			fail_at = ifx fail_copy
				then 2,
			direct = direct,
			job = .{drain = drain, action = .CHECK_PRIVATE_OPEN},
		};

		allocator := open_output_probe(*probe);
		ok, opened, error := Service.open_session(drain.fixture.host.service, open_output_options(),, allocator);
		assert(probe.gate_progress && probe.job.ok, "\e[91mOpen-session output allocation blocked reentry or exposed an unadmitted session.\e[0m");
		free_records(probe.job.records);
		if fail_copy {
			assert(!ok && error.code == .ADMISSION_DENIED && error.admission.kind == .RESOURCE_EXHAUSTED);
			assert(!opened.session.generation && drain.fixture.host.service.sessions.count == 1);
		} else {
			assert(ok && drain.fixture.host.service.sessions.count == 2);
			assert(opened.description.lifecycle == .OPEN);
			close_output_session(drain.fixture.host.service, opened.session);
		}

		Service.free_description(*opened.description,, allocator);
		close_output_probe(*probe);
		finish_drain(drain);
	}

	print("X4/X5 private open-session output allocation permits reentry (direct = %) \e[92mPASS\e[0m\n", direct);
}

World_Output :: enum {
	PENDING_TICKET;
	PENDING_WAITER;
	PENDING_HEAD;
	TERMINAL_TICKET;
	TERMINAL_WAITER;
	MISMATCH_HEAD;
}

prepared_world_output :: (kind: World_Output) -> Drain_Fixture {
	drain := prepared_output_read(.UPDATE_CANCELLATION);
	if kind == .TERMINAL_TICKET {
		replacement := submit(drain.fixture, "answer :: 99;");
		release(drain.fixture, replacement);
	} else if kind == .TERMINAL_WAITER {
		ok, cancelled := Service.cancel_waiter(drain.fixture.host.service, drain.first);
		assert(ok);
		Service.free_observation(*cancelled.observation);
	}

	return drain;
}

world_output_selector :: (drain: Drain_Fixture, kind: World_Output) -> Service.World_Selector {
	if kind == .PENDING_HEAD || kind == .MISMATCH_HEAD {
		frontier: [] u8;
		if kind == .PENDING_HEAD {
			_, description := Service.describe_session(drain.fixture.host.service, drain.fixture.host.session);
			frontier = array_copy(description.accepted_frontier);
			Service.free_description(*description);
		} else {
			frontier = array_copy("unmatched-frontier".([] u8));
		}

		return .{
			kind = .HEAD,
			session = drain.fixture.host.session,
			workspace = drain.fixture.host.workspace,
			expected_frontier = frontier,
		};
	}


	return .{
		kind = .PUBLISHED_UPDATE,
		ticket = drain.ticket,
		waiter = drain.first,
		use_waiter = kind == .PENDING_WAITER || kind == .TERMINAL_WAITER,
	};
}

free_world_output :: (output: *Service.World_Acquisition, allocator: Allocator = context.allocator) {
	assert(!output.world.generation, "\e[91mAn observational world acquisition created a world handle.\e[0m");
	free(output.operation_identity.data,, allocator);
	free(output.published_frontier.data,, allocator);
	Service.free_observation(*output.observation,, allocator);
	output.* = .{};
}

assert_world_output :: (output: Service.World_Acquisition, expected: Service.World_Acquisition) {
	assert(output.kind == expected.kind && output.unavailable == expected.unavailable);
	assert_description_bytes(output.operation_identity.([] u8), expected.operation_identity.([] u8));
	assert_description_bytes(output.published_frontier, expected.published_frontier);
	assert_description_bytes(output.observation.operation_identity.([] u8), expected.observation.operation_identity.([] u8));
	assert_description_bytes(output.observation.provider_frontier, expected.observation.provider_frontier);
	assert(output.observation.kind == expected.observation.kind);
	assert(output.observation.update.kind == expected.observation.update.kind);
	assert(output.observation.update.cancellation == expected.observation.update.cancellation);
	assert_description_bytes(output.observation.update.successor.([] u8), expected.observation.update.successor.([] u8));
	assert(output.observation.documents.count == expected.observation.documents.count);
	for expected.observation.documents {
		assert_description_bytes(output.observation.documents[it_index], it);
	}
}

test_world_output_failures :: () {
	for World_Output.[.PENDING_TICKET, .PENDING_WAITER, .PENDING_HEAD, .TERMINAL_TICKET, .TERMINAL_WAITER, .MISMATCH_HEAD] {
		kind := it;
		drain := prepared_world_output(kind);
		selector := world_output_selector(drain, kind);
		ok, expected := Service.acquire_world(drain.fixture.host.service, selector);
		assert(ok && expected.kind != .ACQUIRED);
		live_handles := drain.fixture.session.ledger.live[Service.Limit_Name.LIVE_HANDLES];
		completions := drain.fixture.session.ledger.live[Service.Limit_Name.COMPLETION_RECORDS];
		probe: Output_Probe;
		allocator := open_output_probe(*probe);
		fail_at: s64 = 1;
		while true {
			probe.fail_at = fail_at;
			probe.allocations = 0;
			ok, output, error := Service.acquire_world(drain.fixture.host.service, selector,, allocator);
			assert(drain.fixture.session.ledger.live[Service.Limit_Name.LIVE_HANDLES] == live_handles);
			assert(drain.fixture.session.ledger.live[Service.Limit_Name.COMPLETION_RECORDS] == completions);
			if ok {
				assert(fail_at > 1 && probe.allocations == fail_at - 1);
				assert_world_output(output, expected);
				free_world_output(*output, allocator);
				break;
			}


			assert(error.code == .ADMISSION_DENIED && error.admission.kind == .RESOURCE_EXHAUSTED);
			free_world_output(*output, allocator);
			assert(!probe.backing.live_bytes && !probe.backing.sizes.count);
			fail_at += 1;
			assert(fail_at < 100);
		}


		close_output_probe(*probe);
		free_world_output(*expected);
		free(selector.expected_frontier.data);
		finish_drain(drain, held = true);
	}

	print("X5 every world-acquisition descriptive allocation failure \e[92mPASS\e[0m\n");
}

test_world_output_retirement :: (direct := false) {
	for World_Output.[.PENDING_TICKET, .PENDING_WAITER, .PENDING_HEAD, .TERMINAL_TICKET, .TERMINAL_WAITER, .MISMATCH_HEAD] {
		kind := it;
		drain := prepared_world_output(kind);
		selector := world_output_selector(drain, kind);
		probe := Output_Probe.{
			direct = direct,
			job = .{
				drain = drain,
				action = ifx selector.kind == .HEAD
					then .STOP_AND_RELEASE_SESSION
					else ifx selector.use_waiter
						then .RELEASE_WAITER
						else .RELEASE_TICKET,
			},
		};

		allocator := open_output_probe(*probe);
		ok, output, error := Service.acquire_world(drain.fixture.host.service, selector,, allocator);
		assert(probe.gate_progress && probe.job.ok && !ok && error.code == .INVALID_HANDLE);
		if selector.kind != .HEAD {
			retired_slot := ifx selector.use_waiter
				then drain.first.slot
				else drain.ticket.slot;
			retired_generation := ifx selector.use_waiter
				then drain.first.generation
				else drain.ticket.generation;
			assert(probe.job.replacement.slot == retired_slot && probe.job.replacement.generation != retired_generation);
			release(drain.fixture, probe.job.replacement);
		}

		free_world_output(*output, allocator);
		close_output_probe(*probe);
		free(selector.expected_frontier.data);
		finish_drain(
			drain,
			first_released = selector.kind != .HEAD && selector.use_waiter,
			ticket_released = selector.kind != .HEAD && !selector.use_waiter,
			session_released = selector.kind == .HEAD,
			held = selector.kind != .HEAD
		);
	}

	print("X3 world-acquisition output retirement/reuse (direct = %) \e[92mPASS\e[0m\n", direct);
}

test_world_output_changes :: (direct := false) {
	for World_Output.[.PENDING_TICKET, .PENDING_WAITER, .PENDING_HEAD, .MISMATCH_HEAD] {
		kind := it;
		for Output_Action.[.COMPLETE_WORK, .REPLACE_HELD_SOURCE, .REQUEST_SHUTDOWN] {
			action := it;
			drain := prepared_world_output(kind);
			selector := world_output_selector(drain, kind);
			_, expected := Service.acquire_world(drain.fixture.host.service, selector);
			probe := Output_Probe.{
				direct = direct,
				job = .{drain = drain, action = action},
			};

			allocator := open_output_probe(*probe);
			ok, output := Service.acquire_world(drain.fixture.host.service, selector,, allocator);
			assert(probe.gate_progress && probe.job.ok && ok);
			assert_world_output(output, expected);
			current_ok, current := Service.acquire_world(drain.fixture.host.service, selector);
			assert(current_ok);
			if action == .COMPLETE_WORK && kind != .MISMATCH_HEAD {
				assert(current.kind == .ACQUIRED);
				release(drain.fixture, current.world);
			} else {
				assert(current.kind == .UNAVAILABLE);
				if kind == .MISMATCH_HEAD && action != .REQUEST_SHUTDOWN {
					assert(!Service.bytes_equal(current.published_frontier, output.published_frontier));
				}

				free_world_output(*current);
			}

			free_world_output(*output, allocator);
			free_world_output(*expected);
			close_output_probe(*probe);
			free(selector.expected_frontier.data);
			finish_drain(drain, held = action == .REQUEST_SHUTDOWN);
		}
	}

	print("X3 world snapshot survives completion/frontier/shutdown during copy (direct = %) \e[92mPASS\e[0m\n", direct);
}

test_world_output_revalidation_control :: () {
	for World_Output.[.PENDING_TICKET, .PENDING_HEAD] {
		drain := prepared_world_output(it);
		selector := world_output_selector(drain, it);
		drain.fixture.session.faults.allow_stale_byte_export = true;
		probe := Output_Probe.{
			direct = true,
			job = .{
				drain = drain,
				action = ifx selector.kind == .HEAD
					then .STOP_AND_RELEASE_SESSION
					else .RELEASE_TICKET,
			},
		};

		allocator := open_output_probe(*probe);
		ok, output := Service.acquire_world(drain.fixture.host.service, selector,, allocator);
		assert(probe.gate_progress && probe.job.ok && ok && output.kind == .PENDING, "\e[91mStale byte-export negative control was not detected.\e[0m");
		free_world_output(*output, allocator);
		close_output_probe(*probe);
		free(selector.expected_frontier.data);
		if selector.kind != .HEAD {
			release(drain.fixture, probe.job.replacement);
		}

		finish_drain(
			drain,
			ticket_released = selector.kind != .HEAD,
			session_released = selector.kind == .HEAD,
			held = selector.kind != .HEAD
		);
	}

	print("X3 stale world byte-export negative controls \e[92mPASS\e[0m\n");
}

main :: () {
	init(*allocation_ledger.gate);
	allocation_ledger.delegate = context.default_allocator;
	Service.service_test_allocator = .{proc = spy_allocate, data = *allocation_ledger};
	#if BATCH_POOL_ONLY {
		test_source_batch_pool_defaults();
		test_source_registration_failures(batch_sources = true);
		test_source_registration_failures(batch_sources = true, batch_pair = true);
		test_source_registration_failures(batch_source_bytes = true);
		test_source_registration_failures(batch_source_bytes = true, batch_pair = true);
		test_source_registration_failures(batch_source_bytes = true, empty_source = true);
		test_source_registration_failures(batch_source_identities = true);
		test_source_registration_failures(batch_source_identities = true, batch_pair = true);
		test_source_registration_failures(batch_source_identities = true, empty_source = true);
		test_source_batch_source_event_failures();
		test_source_batch_edit_failures();
		test_source_registration_failures(batch_state_list = true);
		test_source_registration_failures(batch_state_list = true, batch_pair = true);
		test_source_batch_reference_storage();
		test_source_registration_failures(batch_context_list = true);
		test_source_registration_failures(batch_context_list = true, batch_pair = true);
		test_source_registration_failures(batch_paths = true);
		test_source_registration_failures(batch_paths = true, batch_pair = true);
		test_source_registration_failures(batch_paths = true, path_error = true, event_kind = .OBSERVE_DISK);
		test_source_batch_construction_reference_rollback();
		test_source_batch_construction_cleanup();
		test_source_batch_construction_cleanup(new_document = true);
		test_source_batch_state_cleanup_lifecycle();
		test_source_batch_state_cleanup_lifecycle(revisions = true);
		test_source_batch_construction_cleanup(revisions = true);
		test_source_batch_construction_receipt_retry();
		test_source_batch_construction_receipt_retry(revisions = true);
		test_source_batch_construction_callbacks();
		test_source_batch_construction_callbacks(revisions = true);
		test_source_registration_failures(batch_states = true);
		test_source_registration_failures(batch_revisions = true);
		test_source_registration_failures(batch_states = true, batch_pair = true);
		test_source_registration_failures(batch_revisions = true, batch_pair = true);
		test_source_batch_revision_storage();
		test_source_batch_storage_growth();
		test_source_batch_storage_admission();
		test_source_batch_storage_admission(replace = true);
		test_source_batch_storage_admission(direct = true, replace = true);
		test_source_batch_storage_admission(replace = true, negative_control = true);
		test_source_batch_storage_admission(direct = true, replace = true, negative_control = true);
		test_source_batch_storage_admission(shutdown = true);
		test_source_batch_storage_admission(direct = true, shutdown = true);
		test_source_batch_storage_admission(shutdown = true, negative_control = true);
		test_source_batch_storage_admission(direct = true, shutdown = true, negative_control = true);
		test_source_batch_storage_admission(retire = true);
		test_source_batch_storage_admission(direct = true, retire = true);
		test_source_batch_storage_admission(retire = true, negative_control = true);
		test_source_batch_storage_admission(direct = true, retire = true, negative_control = true);
		test_source_batch_storage_admission(retry_rejection = true);
		test_source_batch_storage_admission(receipt_retry = true);
		test_source_batch_storage_admission(direct = true, receipt_retry = true);
		test_source_batch_storage_admission(receipt_retry = true, list = true);
		test_source_batch_storage_admission(direct = true, receipt_retry = true, list = true);
		test_source_batch_storage_admission(receipt_retry = true, retry_rejection = true);
		test_source_batch_storage_admission(direct = true, receipt_retry = true, retry_rejection = true);
		test_source_batch_storage_admission(receipt_retry = true, list = true, retry_rejection = true);
		test_source_batch_storage_admission(direct = true, receipt_retry = true, list = true, retry_rejection = true);
		test_source_batch_pool_cleanup();
		test_source_batch_pool_cleanup(direct = true);
		test_source_batch_pool_cleanup(retry = true);
		test_source_batch_pool_cleanup(direct = true, retry = true);
		test_source_batch_pool_cleanup(negative_control = true);
		test_source_batch_pool_cleanup(retry = true, negative_control = true);
		test_source_batch_pool_cleanup(retry = true, list = true);
		test_source_batch_pool_cleanup(direct = true, retry = true, list = true);
		test_source_batch_pool_cleanup(retry = true, negative_control = true, list = true);
		test_source_batch_pool_cleanup(direct = true, retry = true, negative_control = true, list = true);
		test_source_batch_pool_cleanup(validation = true);
		test_source_batch_pool_cleanup(direct = true, validation = true);
		test_source_batch_pool_cleanup(negative_control = true, validation = true);
		test_source_batch_pool_cleanup(direct = true, negative_control = true, validation = true);
		test_source_batch_pool_cleanup(allocate = true);
		test_source_batch_pool_cleanup(direct = true, allocate = true);
		test_source_batch_pool_cleanup(negative_control = true, allocate = true);
		test_source_batch_pool_cleanup(direct = true, negative_control = true, allocate = true);
		test_source_batch_pool_cleanup_reentry();
		test_source_batch_storage_cleanup();
		test_source_batch_storage_cleanup(direct = true);
		test_source_batch_storage_cleanup(negative_control = true);
		test_source_batch_storage_cleanup(direct = true, negative_control = true);
		test_source_batch_storage_cleanup(action = .CHECK_STAGING_SHUTDOWN);
		test_source_batch_storage_cleanup(direct = true, action = .CHECK_STAGING_SHUTDOWN);
		test_source_batch_storage_cleanup(negative_control = true, action = .CHECK_STAGING_SHUTDOWN);
		test_source_batch_storage_cleanup(direct = true, negative_control = true, action = .CHECK_STAGING_SHUTDOWN);
		test_source_batch_storage_cleanup(action = .RETIRE_AND_REUSE_SESSION);
		test_source_batch_storage_cleanup(direct = true, action = .RETIRE_AND_REUSE_SESSION);
		test_source_batch_storage_cleanup(negative_control = true, action = .RETIRE_AND_REUSE_SESSION);
		test_source_batch_storage_cleanup(direct = true, negative_control = true, action = .RETIRE_AND_REUSE_SESSION);
		test_source_registration_failures(pool = true);
		test_source_registration_failure_control(pool = true);
		test_source_registration_receipt_retry(pool = true);
		test_source_registration_receipt_retry(direct = true, pool = true);
		test_source_registration_receipt_retry(list = true, pool = true);
		test_source_registration_receipt_retry(direct = true, list = true, pool = true);
		test_source_registration_receipt_retry(reject_receipt = true, pool = true);
		test_source_registration_receipt_retry(direct = true, reject_receipt = true, pool = true);
		test_source_registration_receipt_retry(pool = true, reference_control = true);
		test_source_registration_receipt_retry(direct = true, pool = true, reference_control = true);
		test_source_registration_receipt_retry(list = true, pool = true, reference_control = true);
		test_source_registration_receipt_retry(direct = true, list = true, pool = true, reference_control = true);
		test_source_registration_receipt_retry(reject_receipt = true, pool = true, reference_control = true);
		test_source_registration_receipt_retry(direct = true, reject_receipt = true, pool = true, reference_control = true);
		test_source_registration_receipt_retry(transfer = true);
		test_source_registration_receipt_retry(direct = true, transfer = true);
		test_source_registration_receipt_retry(list = true, transfer = true);
		test_source_registration_receipt_retry(direct = true, list = true, transfer = true);
		test_source_registration_receipt_retry(reject_receipt = true, transfer = true);
		test_source_registration_receipt_retry(direct = true, reject_receipt = true, transfer = true);
		test_source_registration_receipt_retry(transfer = true, reference_control = true);
		test_source_registration_receipt_retry(direct = true, transfer = true, reference_control = true);
		test_source_registration_receipt_retry(list = true, transfer = true, reference_control = true);
		test_source_registration_receipt_retry(direct = true, list = true, transfer = true, reference_control = true);
		test_source_registration_receipt_retry(reject_receipt = true, transfer = true, reference_control = true);
		test_source_registration_receipt_retry(direct = true, reject_receipt = true, transfer = true, reference_control = true);
		test_source_registration_quota();
		test_source_registration_interleavings(pool = true);
		test_source_registration_interleavings(direct = true, pool = true);
		test_source_registration_interleavings(negative_control = true, pool = true);
		test_source_registration_interleavings(direct = true, negative_control = true, pool = true);
		test_source_registration_interleavings(pool = true, pool_retirement = true);
		test_source_registration_interleavings(direct = true, pool = true, pool_retirement = true);
		test_source_registration_interleavings(negative_control = true, pool = true, pool_retirement = true);
		test_source_registration_interleavings(direct = true, negative_control = true, pool = true, pool_retirement = true);
		assert_no_owned_allocations();
		deinit(*allocation_ledger.sizes);
		destroy(*allocation_ledger.gate);
		print("Service batch Pool checks .\e[92mPASS\e[0m.\n");
		return;
	}


	test_registration_and_wait();
	test_cancel_and_completion();
	test_retirement_while_waiting();
	test_reentrant_dispatch();
	test_pressure_and_reserved_shutdown();
	test_drain_allocation_failures();
	test_drain_output_interleavings();
	test_drain_output_interleavings(direct = true);
	test_observer_output_failures();
	test_observer_output_retirement();
	test_observer_output_retirement(direct = true);
	test_drain_output_negative_controls();
	test_acquisition_output_failures();
	test_acquisition_output_retirement();
	test_acquisition_output_retirement(direct = true);
	test_cancellation_output_winners();
	test_cancellation_output_winners(direct = true);
	test_cancellation_output_negative_control();
	test_cancellation_retry_output_failures();
	test_cancellation_retry_output_failures(direct = true);
	test_description_output_failures();
	test_description_output_interleavings();
	test_description_output_interleavings(direct = true);
	test_description_retirement_negative_control();
	test_directory_backing();
	test_directory_retirement_reentry();
	test_directory_retirement_reentry(direct = true);
	test_directory_retirement_reentry(negative_control = true);
	test_directory_retirement_reentry(direct = true, negative_control = true);
	test_directory_allocation_failures();
	test_directory_allocation_interleavings();
	test_directory_allocation_interleavings(direct = true);
	test_source_receipt_failures();
	test_source_registration_failures();
	test_source_registration_quota();
	test_source_registration_interleavings();
	test_source_registration_interleavings(direct = true);
	test_source_registration_interleavings(negative_control = true);
	test_source_registration_interleavings(direct = true, negative_control = true);
	test_source_registration_receipt_retry();
	test_source_registration_receipt_retry(direct = true);
	test_source_registration_failure_control();
	test_source_registration_failures(update = true);
	test_source_registration_failure_control(update = true);
	test_source_registration_failures(list = true);
	test_source_registration_failures(provider = true);
	test_source_registration_failures(arrays = true);
	test_source_registration_failures(states = true);
	test_source_registration_failures(revisions = true);
	test_source_registration_failures(pool = true);
	test_source_registration_failures(batch_states = true);
	test_source_registration_failures(batch_sources = true);
	test_source_registration_failures(batch_sources = true, batch_pair = true);
	test_source_registration_failures(batch_source_bytes = true);
	test_source_registration_failures(batch_source_bytes = true, batch_pair = true);
	test_source_registration_failures(batch_source_bytes = true, empty_source = true);
	test_source_registration_failures(batch_source_identities = true);
	test_source_registration_failures(batch_source_identities = true, batch_pair = true);
	test_source_registration_failures(batch_source_identities = true, empty_source = true);
	test_source_batch_source_event_failures();
	test_source_batch_edit_failures();
	test_source_registration_failures(batch_state_list = true);
	test_source_registration_failures(batch_state_list = true, batch_pair = true);
	test_source_batch_reference_storage();
	test_source_registration_failures(batch_context_list = true);
	test_source_registration_failures(batch_context_list = true, batch_pair = true);
	test_source_registration_failures(batch_paths = true);
	test_source_registration_failures(batch_paths = true, batch_pair = true);
	test_source_registration_failures(batch_paths = true, path_error = true, event_kind = .OBSERVE_DISK);
	test_source_batch_construction_reference_rollback();
	test_source_batch_construction_cleanup();
	test_source_batch_construction_cleanup(new_document = true);
	test_source_batch_state_cleanup_lifecycle();
	test_source_batch_state_cleanup_lifecycle(revisions = true);
	test_source_batch_construction_cleanup(revisions = true);
	test_source_batch_construction_receipt_retry();
	test_source_batch_construction_receipt_retry(revisions = true);
	test_source_batch_construction_callbacks();
	test_source_batch_construction_callbacks(revisions = true);
	test_source_registration_failures(batch_revisions = true);
	test_source_registration_failures(batch_states = true, batch_pair = true);
	test_source_registration_failures(batch_revisions = true, batch_pair = true);
	test_source_batch_revision_storage();
	test_source_registration_failure_control(pool = true);
	test_source_batch_pool_defaults();
	test_source_batch_storage_growth();
	test_source_batch_storage_admission();
	test_source_batch_storage_admission(replace = true);
	test_source_batch_storage_admission(direct = true, replace = true);
	test_source_batch_storage_admission(replace = true, negative_control = true);
	test_source_batch_storage_admission(direct = true, replace = true, negative_control = true);
	test_source_batch_storage_admission(shutdown = true);
	test_source_batch_storage_admission(direct = true, shutdown = true);
	test_source_batch_storage_admission(shutdown = true, negative_control = true);
	test_source_batch_storage_admission(direct = true, shutdown = true, negative_control = true);
	test_source_batch_storage_admission(retire = true);
	test_source_batch_storage_admission(direct = true, retire = true);
	test_source_batch_storage_admission(retire = true, negative_control = true);
	test_source_batch_storage_admission(direct = true, retire = true, negative_control = true);
	test_source_batch_storage_admission(retry_rejection = true);
	test_source_batch_storage_admission(receipt_retry = true);
	test_source_batch_storage_admission(direct = true, receipt_retry = true);
	test_source_batch_storage_admission(receipt_retry = true, list = true);
	test_source_batch_storage_admission(direct = true, receipt_retry = true, list = true);
	test_source_batch_storage_admission(receipt_retry = true, retry_rejection = true);
	test_source_batch_storage_admission(direct = true, receipt_retry = true, retry_rejection = true);
	test_source_batch_storage_admission(receipt_retry = true, list = true, retry_rejection = true);
	test_source_batch_storage_admission(direct = true, receipt_retry = true, list = true, retry_rejection = true);
	test_source_registration_receipt_retry(pool = true);
	test_source_registration_receipt_retry(direct = true, pool = true);
	test_source_registration_receipt_retry(list = true, pool = true);
	test_source_registration_receipt_retry(direct = true, list = true, pool = true);
	test_source_registration_receipt_retry(reject_receipt = true, pool = true);
	test_source_registration_receipt_retry(direct = true, reject_receipt = true, pool = true);
	test_source_registration_receipt_retry(pool = true, reference_control = true);
	test_source_registration_receipt_retry(direct = true, pool = true, reference_control = true);
	test_source_registration_receipt_retry(list = true, pool = true, reference_control = true);
	test_source_registration_receipt_retry(direct = true, list = true, pool = true, reference_control = true);
	test_source_registration_receipt_retry(reject_receipt = true, pool = true, reference_control = true);
	test_source_registration_receipt_retry(direct = true, reject_receipt = true, pool = true, reference_control = true);
	test_source_registration_receipt_retry(transfer = true);
	test_source_registration_receipt_retry(direct = true, transfer = true);
	test_source_registration_receipt_retry(list = true, transfer = true);
	test_source_registration_receipt_retry(direct = true, list = true, transfer = true);
	test_source_registration_receipt_retry(reject_receipt = true, transfer = true);
	test_source_registration_receipt_retry(direct = true, reject_receipt = true, transfer = true);
	test_source_registration_receipt_retry(transfer = true, reference_control = true);
	test_source_registration_receipt_retry(direct = true, transfer = true, reference_control = true);
	test_source_registration_receipt_retry(list = true, transfer = true, reference_control = true);
	test_source_registration_receipt_retry(direct = true, list = true, transfer = true, reference_control = true);
	test_source_registration_receipt_retry(reject_receipt = true, transfer = true, reference_control = true);
	test_source_registration_receipt_retry(direct = true, reject_receipt = true, transfer = true, reference_control = true);
	test_source_registration_interleavings(pool = true);
	test_source_batch_pool_cleanup();
	test_source_batch_pool_cleanup(direct = true);
	test_source_batch_pool_cleanup(retry = true);
	test_source_batch_pool_cleanup(direct = true, retry = true);
	test_source_batch_pool_cleanup(negative_control = true);
	test_source_batch_pool_cleanup(retry = true, negative_control = true);
	test_source_batch_pool_cleanup(retry = true, list = true);
	test_source_batch_pool_cleanup(direct = true, retry = true, list = true);
	test_source_batch_pool_cleanup(retry = true, negative_control = true, list = true);
	test_source_batch_pool_cleanup(direct = true, retry = true, negative_control = true, list = true);
	test_source_batch_pool_cleanup(validation = true);
	test_source_batch_pool_cleanup(direct = true, validation = true);
	test_source_batch_pool_cleanup(negative_control = true, validation = true);
	test_source_batch_pool_cleanup(direct = true, negative_control = true, validation = true);
	test_source_batch_pool_cleanup(allocate = true);
	test_source_batch_pool_cleanup(direct = true, allocate = true);
	test_source_batch_pool_cleanup(negative_control = true, allocate = true);
	test_source_batch_pool_cleanup(direct = true, negative_control = true, allocate = true);
	test_source_batch_pool_cleanup_reentry();
	test_source_batch_storage_cleanup();
	test_source_batch_storage_cleanup(direct = true);
	test_source_batch_storage_cleanup(negative_control = true);
	test_source_batch_storage_cleanup(direct = true, negative_control = true);
	test_source_batch_storage_cleanup(action = .CHECK_STAGING_SHUTDOWN);
	test_source_batch_storage_cleanup(direct = true, action = .CHECK_STAGING_SHUTDOWN);
	test_source_batch_storage_cleanup(negative_control = true, action = .CHECK_STAGING_SHUTDOWN);
	test_source_batch_storage_cleanup(direct = true, negative_control = true, action = .CHECK_STAGING_SHUTDOWN);
	test_source_batch_storage_cleanup(action = .RETIRE_AND_REUSE_SESSION);
	test_source_batch_storage_cleanup(direct = true, action = .RETIRE_AND_REUSE_SESSION);
	test_source_batch_storage_cleanup(negative_control = true, action = .RETIRE_AND_REUSE_SESSION);
	test_source_batch_storage_cleanup(direct = true, negative_control = true, action = .RETIRE_AND_REUSE_SESSION);
	test_source_registration_interleavings(direct = true, pool = true);
	test_source_registration_interleavings(negative_control = true, pool = true);
	test_source_registration_interleavings(direct = true, negative_control = true, pool = true);
	test_source_registration_interleavings(pool = true, pool_retirement = true);
	test_source_registration_interleavings(direct = true, pool = true, pool_retirement = true);
	test_source_registration_interleavings(negative_control = true, pool = true, pool_retirement = true);
	test_source_registration_interleavings(direct = true, negative_control = true, pool = true, pool_retirement = true);
	test_source_registration_failure_control(states = true);
	test_source_registration_failure_control(revisions = true);
	test_source_provider_arrays_refresh(states = true);
	test_source_provider_arrays_refresh(direct = true, states = true);
	test_source_provider_arrays_refresh(empty = true, states = true);
	test_source_provider_revisions_empty();
	test_source_provider_revisions_empty(empty_provider = true);
	test_source_provider_revisions_refresh();
	test_source_provider_revisions_refresh(direct = true);
	test_source_provider_revisions_refresh(surplus = true);
	test_source_provider_revisions_refresh(direct = true, surplus = true);
	for 1..2 {
		test_source_registration_interleavings(states = true, multiple = true, job_at = it);
		test_source_registration_interleavings(direct = true, states = true, multiple = true, job_at = it);
		test_source_registration_interleavings(negative_control = true, states = true, multiple = true, job_at = it);
		test_source_registration_interleavings(direct = true, negative_control = true, states = true, multiple = true, job_at = it);
	}

	test_source_registration_interleavings(states = true);
	test_source_registration_interleavings(direct = true, states = true);
	test_source_registration_interleavings(negative_control = true, states = true);
	test_source_registration_interleavings(direct = true, negative_control = true, states = true);
	test_source_registration_interleavings(states = true, cleanup = true);
	test_source_registration_interleavings(direct = true, states = true, cleanup = true);
	test_source_registration_interleavings(negative_control = true, states = true, cleanup = true);
	test_source_registration_interleavings(direct = true, negative_control = true, states = true, cleanup = true);
	for 1..2 {
		test_source_registration_interleavings(revisions = true, multiple = true, job_at = it);
		test_source_registration_interleavings(direct = true, revisions = true, multiple = true, job_at = it);
		test_source_registration_interleavings(negative_control = true, revisions = true, multiple = true, job_at = it);
		test_source_registration_interleavings(direct = true, negative_control = true, revisions = true, multiple = true, job_at = it);
	}

	test_source_registration_interleavings(revisions = true);
	test_source_registration_interleavings(direct = true, revisions = true);
	test_source_registration_interleavings(negative_control = true, revisions = true);
	test_source_registration_interleavings(direct = true, negative_control = true, revisions = true);
	test_source_registration_interleavings(revisions = true, cleanup = true);
	test_source_registration_interleavings(direct = true, revisions = true, cleanup = true);
	test_source_registration_interleavings(negative_control = true, revisions = true, cleanup = true);
	test_source_registration_interleavings(direct = true, negative_control = true, revisions = true, cleanup = true);
	test_source_registration_receipt_retry(states = true);
	test_source_registration_receipt_retry(direct = true, states = true);
	test_source_registration_receipt_retry(list = true, states = true);
	test_source_registration_receipt_retry(direct = true, list = true, states = true);
	test_source_registration_receipt_retry(revisions = true);
	test_source_registration_receipt_retry(direct = true, revisions = true);
	test_source_registration_receipt_retry(list = true, revisions = true);
	test_source_registration_receipt_retry(direct = true, list = true, revisions = true);
	test_source_registration_receipt_retry(revisions = true, reject_receipt = true);
	test_source_registration_failure_control(arrays = true);
	test_source_provider_arrays_refresh();
	test_source_provider_arrays_refresh(direct = true);
	test_source_provider_arrays_refresh(empty = true);
	for 1..2 {
		test_source_registration_interleavings(arrays = true, job_at = it);
		test_source_registration_interleavings(direct = true, arrays = true, job_at = it);
		test_source_registration_interleavings(negative_control = true, arrays = true, job_at = it);
		test_source_registration_interleavings(direct = true, negative_control = true, arrays = true, job_at = it);
	}

	test_source_registration_interleavings(arrays = true, cleanup = true);
	test_source_registration_interleavings(direct = true, arrays = true, cleanup = true);
	test_source_registration_interleavings(negative_control = true, arrays = true, cleanup = true);
	test_source_registration_interleavings(direct = true, negative_control = true, arrays = true, cleanup = true);
	test_source_registration_receipt_retry(arrays = true);
	test_source_registration_receipt_retry(direct = true, arrays = true);
	test_source_registration_receipt_retry(list = true, arrays = true);
	test_source_registration_receipt_retry(direct = true, list = true, arrays = true);
	test_source_registration_failure_control(provider = true);
	test_source_registration_interleavings(provider = true);
	test_source_registration_interleavings(direct = true, provider = true);
	test_source_registration_interleavings(negative_control = true, provider = true);
	test_source_registration_interleavings(direct = true, negative_control = true, provider = true);
	test_source_registration_receipt_retry(provider = true);
	test_source_registration_receipt_retry(direct = true, provider = true);
	test_source_registration_receipt_retry(list = true, provider = true);
	test_source_registration_receipt_retry(direct = true, list = true, provider = true);
	test_source_registration_failure_control(list = true);
	test_source_registration_interleavings(list = true);
	test_source_registration_interleavings(direct = true, list = true);
	test_source_registration_interleavings(negative_control = true, list = true);
	test_source_registration_interleavings(direct = true, negative_control = true, list = true);
	test_source_registration_interleavings(list = true, cleanup = true);
	test_source_registration_interleavings(direct = true, list = true, cleanup = true);
	test_source_registration_interleavings(negative_control = true, list = true, cleanup = true);
	test_source_registration_interleavings(direct = true, negative_control = true, list = true, cleanup = true);
	test_source_registration_receipt_retry(list = true);
	test_source_registration_receipt_retry(direct = true, list = true);
	for s64.[1, 2, 3] {
		test_source_registration_interleavings(update = true, job_at = it);
		test_source_registration_interleavings(direct = true, update = true, job_at = it);
	}

	test_source_update_counter();
	test_source_update_counter(last_token = true);
	test_source_update_counter(late = true);
	test_source_update_counter(late = true, direct = true);
	test_source_receipt_interleavings();
	test_source_receipt_interleavings(direct = true);
	test_open_output_failures();
	test_open_argument_failures();
	test_open_context_failures();
	test_open_context_interleavings();
	test_open_context_interleavings(direct = true);
	test_shutdown_reserve_failures();
	test_repeated_shutdown_failures();
	test_waiter_backing_failures(.TICKET);
	test_waiter_backing_failures(.WORLD);
	test_world_registration_failures();
	test_world_registration_quota();
	test_world_registration_interleavings();
	test_world_registration_interleavings(direct = true);
	test_world_registration_interleavings(negative_control = true);
	test_world_registration_interleavings(direct = true, negative_control = true);
	test_world_registration_failure_control();
	test_retain_backing_failures(.RESULT, acquisition = true);
	test_result_registration_quota_and_control();
	test_result_registration_quota_and_control(negative_control = true);
	test_result_registration_interleavings();
	test_result_registration_interleavings(direct = true);
	test_result_registration_interleavings(negative_control = true);
	test_result_registration_interleavings(direct = true, negative_control = true);
	test_immediate_result_failures();
	test_immediate_result_limits();
	test_immediate_result_interleavings();
	test_immediate_result_interleavings(direct = true);
	test_immediate_result_interleavings(negative_control = true);
	test_immediate_result_interleavings(direct = true, negative_control = true);
	test_immediate_result_failure_control();
	test_immediate_result_last_token();
	test_waiter_backing_quota(.TICKET);
	test_waiter_backing_quota(.WORLD);
	test_waiter_backing_interleavings(.TICKET);
	test_waiter_backing_interleavings(.TICKET, direct = true);
	test_waiter_backing_interleavings(.WORLD);
	test_waiter_backing_interleavings(.WORLD, direct = true);
	test_waiter_backing_interleavings(.TICKET, negative_control = true);
	test_waiter_backing_interleavings(.TICKET, direct = true, negative_control = true);
	test_waiter_backing_interleavings(.WORLD, negative_control = true);
	test_waiter_backing_interleavings(.WORLD, direct = true, negative_control = true);
	test_waiter_failed_backing_control(.TICKET);
	test_waiter_failed_backing_control(.WORLD);
	test_repeated_shutdown_quota();
	test_repeated_shutdown_interleavings();
	test_repeated_shutdown_interleavings(direct = true);
	test_repeated_shutdown_interleavings(negative_control = true);
	test_repeated_shutdown_interleavings(direct = true, negative_control = true);
	test_retain_backing_failures(.WORLD);
	test_retain_backing_failures(.RESULT);
	test_retain_backing_interleavings(.WORLD);
	test_retain_backing_interleavings(.WORLD, direct = true);
	test_retain_backing_interleavings(.RESULT);
	test_retain_backing_interleavings(.RESULT, direct = true);
	test_retain_backing_interleavings(.WORLD, negative_control = true);
	test_retain_backing_interleavings(.WORLD, direct = true, negative_control = true);
	test_retain_backing_interleavings(.RESULT, negative_control = true);
	test_retain_backing_interleavings(.RESULT, direct = true, negative_control = true);
	test_shutdown_reserved_activation();
	test_shutdown_reserved_activation(pressure = true);
	test_shutdown_reserved_activation(negative_control = true);
	test_shutdown_reserved_activation(pressure = true, negative_control = true);
	test_shutdown_identity_exhaustion();
	test_provider_error_failures();
	test_provider_error_interleavings();
	test_provider_error_interleavings(direct = true);
	test_open_argument_interleavings();
	test_open_argument_interleavings(direct = true);
	test_analysis_receipt_failures();
	test_analysis_argument_failures();
	test_terminal_query_failures();
	test_result_argument_failures();
	test_coordinator_argument_failures();
	test_coordinator_argument_interleavings();
	test_coordinator_argument_interleavings(direct = true);
	test_coordinator_argument_interleavings(negative_control = true);
	test_coordinator_argument_interleavings(direct = true, negative_control = true);
	test_result_argument_interleavings();
	test_result_argument_interleavings(direct = true);
	test_result_argument_interleavings(negative_control = true);
	test_result_argument_interleavings(direct = true, negative_control = true);
	test_terminal_query_failures(negative_control = true);
	test_terminal_query_interleavings();
	test_terminal_query_interleavings(direct = true);
	test_terminal_query_interleavings(negative_control = true);
	test_terminal_query_interleavings(direct = true, negative_control = true);
	test_analysis_argument_interleavings();
	test_analysis_argument_interleavings(direct = true);
	test_analysis_argument_interleavings(negative_control = true);
	test_analysis_argument_interleavings(direct = true, negative_control = true);
	test_analysis_receipt_interleavings();
	test_analysis_receipt_interleavings(direct = true);
	test_analysis_receipt_interleavings(negative_control = true);
	test_analysis_receipt_interleavings(direct = true, negative_control = true);
	test_open_output_interleavings();
	test_open_output_interleavings(direct = true);
	test_world_output_failures();
	test_world_output_retirement();
	test_world_output_retirement(direct = true);
	test_world_output_changes();
	test_world_output_changes(direct = true);
	test_world_output_revalidation_control();
	test_provider_stall_and_shutdown();
	test_required_fifo();
	test_optional_fifo();
	test_cleanup_pin();
	test_shutdown_deadline_and_owners();
	assert_no_owned_allocations();
	deinit(*allocation_ledger.sizes);
	destroy(*allocation_ledger.gate);
	print("Service worker \e[92mPASS\e[0m.\n");
}
