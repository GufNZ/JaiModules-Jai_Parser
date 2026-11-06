#import "Basic";
#import "File";
#import "File_Utilities";
#import "Hash_Table";
#import "Thread"(LOAD_THREAD_GROUP = false);

Service :: #import "Jai_Parser/service"(TEST_HOOKS = true, REAL_WORKER = true);

FOREVER :: 0xFFFF_FFFF_FFFF_FFFF;

Allocation_Ledger :: struct {
	gate: Mutex;
	delegate: Allocator;
	sizes: Table(*void, s64);
	live_bytes: s64;
}

allocation_ledger: Allocation_Ledger;

spy_allocate :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, data: *void) -> *void {
	ledger := data.(*Allocation_Ledger);
	if mode != .ALLOCATE && mode != .RESIZE && mode != .FREE {
		return ledger.delegate.proc(mode, size, old_size, old_memory, ledger.delegate.data);
	}


	lock(*ledger.gate);
	defer unlock(*ledger.gate);

	push_allocator(ledger.delegate);
	result := ledger.delegate.proc(mode, size, old_size, old_memory, ledger.delegate.data);
	if old_memory && (mode == .FREE || mode == .RESIZE && result) {
		found, previous_size := table_remove(*ledger.sizes, old_memory);
		assert(found, "An allocation was freed twice or by the wrong owner.");
		ledger.live_bytes -= previous_size;
	}

	if result && (mode == .ALLOCATE || mode == .RESIZE) {
		assert(!table_contains(*ledger.sizes, result));
		table_add(*ledger.sizes, result, size);
		ledger.live_bytes += size;
	}

	return result;
}

assert_no_owned_allocations :: () {
	lock(*allocation_ledger.gate);
	defer unlock(*allocation_ledger.gate);

	assert(!allocation_ledger.live_bytes && !allocation_ledger.sizes.count, "Independent allocation ledger retained % bytes.", allocation_ledger.live_bytes);
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
	assert(ok, "Submission failed: %.", error);
	return accepted.ticket;
}

await :: (fixture: Fixture, handle: Service.Handle($K)) -> Service.Observation {
	ok, waited, error := Service.wait(fixture.host.service, handle, .{
		clock_identity = fixture.host.service.clock_identity,
		nanoseconds = FOREVER,
	});
	assert(ok && !waited.timed_out, "Wait failed: %.", error);
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
	assert(ok, "Release failed: %.", error);
}

close :: (fixture: Fixture) {
	assert(Service.close_harness_host(fixture.host));
	assert(!Service.session_of(fixture.host.service, fixture.host.session));
	assert(!fixture.host.service.owned_allocations && !fixture.host.service.owned_bytes, "Final release retained session allocations.");
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
	assert(thread_is_done(thread, 10_000), "A concurrent call did not finish.");
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
	assert(observation.query.kind == .AVAILABLE, "Held source acquisition blocked unrelated compute.");
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
	print("X6/X7/X8 held provider/independent compute/revalidation PASS\n");
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
	print("X8 cleanup pin prevents premature stopped PASS\n");
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
	lock(*fixture.session.gate);
	defer unlock(*fixture.session.gate);

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

	assert(false, "No queued task was available for the optional scheduling control.");
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
			lock(*fixture.session.gate);
			fixture.session.faults.optional_first = true;
			unlock(*fixture.session.gate);
		}

		correct_order := true;
		for string.["a.jai", "b.jai", "d.jai", "c.jai"] {
			mailbox := Service.last_mailbox(fixture.session);
			correct_order &&= Service.bytes_equal(mailbox.task.world.members[0].document, Service.harness_document(fixture.host, it));
			if mode == 1 && it_index == 3 {
				assert(!mailbox.task.optional, "A shared optional prerequisite was not promoted.");
			}

			if it_index < 3 {
				Service.arm_pause(fixture.session, .SELECTED);
			}

			Service.resume_pause(fixture.session, .SELECTED);
			if it_index < 3 {
				assert(Service.await_pause(fixture.session, .SELECTED));
			}
		}

		assert(correct_order == (mode != 2), "Optional priority control was not detected.");
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

	print("X6 optional fallback/promotion/priority negative control PASS\n");
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
		assert(Service.bytes_equal(mailbox.task.world.members[0].document, Service.harness_document(fixture.host, it)), "Later required work overtook the FIFO.");
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
	print("X6 required FIFO/shared later demand PASS\n");
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
	print("X4 reentrant query/cancel/release/shutdown/dispatch PASS\n");
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
	assert(!ok && error.admission.limit == .LIVE_HANDLES, "Shutdown reservation negative control was not detected.");
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
	print("X5 delayed drain/full capacity/reservation negative control PASS\n");
}

test_registration_and_wait :: () {
	for 0..2 {
		fixture := open(tprint("X1-%", it));
		Service.arm_pause(fixture.session, .PUBLICATION);
		ticket := submit(fixture, "answer :: 42;");
		assert(Service.await_pause(fixture.session, .PUBLICATION));
		if it == 0 {
			Service.resume_pause(fixture.session, .PUBLICATION);
			observation := await(fixture, ticket);
			Service.free_observation(*observation);
		}

		ok, attached := Service.observe_ticket(fixture.host.service, ticket);
		assert(ok);
		if it == 0 {//TODO: flip
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
		assert(!valid, "Inline routing bypassed the live handle's session binding.");
		release(fixture, result.result);
		release(fixture, world);
		release(fixture, ticket);
		close(fixture);
	}

	print("X1 registration/wait orderings PASS\n");
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

	print("X2 caller/completion orderings PASS\n");
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
	print("X3 retirement/reuse/stale lookup PASS\n");
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
		assert(Service.set_overlay(*batch, "a.jai", "forbidden :: 3;"));
		accepted, _, error := Service.submit_batch(*batch);
		assert(!accepted && error.code == .SERVICE_CLOSED);
		Service.resume_pause(fixture.session, boundary);
		assert(thread_is_done(*fixture.session.reaper, 10_000), "Shutdown depended on host polling.");
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

	print("X7/X8 shutdown/deadline/surviving owner PASS\n");
}

main :: () {
	init(*allocation_ledger.gate);
	allocation_ledger.delegate = context.default_allocator;
	Service.service_test_allocator = .{proc = spy_allocate, data = *allocation_ledger};
	test_registration_and_wait();
	test_cancel_and_completion();
	test_retirement_while_waiting();
	test_reentrant_dispatch();
	test_pressure_and_reserved_shutdown();
	test_provider_stall_and_shutdown();
	test_required_fifo();
	test_optional_fifo();
	test_cleanup_pin();
	test_shutdown_deadline_and_owners();
	assert_no_owned_allocations();
	deinit(*allocation_ledger.sizes);
	destroy(*allocation_ledger.gate);
	print("Service worker PASS.\n");
}
