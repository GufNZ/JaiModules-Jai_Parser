// Phase-4 acceptance traces T1-T8 and V1-V8 through the harness host and the deterministic executor.
// Each trace authors its expected selections and outcomes; published syntax is compared with an independent fresh parse of the authored bytes.
// Store-dependent branches (T5 eviction and rehydration, T8 store denial) belong to phase 6, and the X traces to phase 5.
// Run from this directory: jai service_traces_test.jai -x64 -quiet && ./service_traces_test.exe
#import "Basic";
#import "Compiler";
#import "File";
#import "File_Utilities";
#import "Pool";
#import "String";
#import "Thread"(LOAD_THREAD_GROUP = false);

REAL_WORKER :: #run -> bool {
	arguments := get_build_options().compile_time_command_line;
	assert(!arguments.count || arguments.count == 1 && arguments[0] == "real-worker");
	return !!arguments.count;
};

Service :: #import "Jai_Parser/service"(TEST_HOOKS = true, REAL_WORKER = REAL_WORKER);
Parser :: Service.Parser;
VERIFY_ONLY :: false;
#load "snapshot_oracle.jai";

FOREVER :: 0xFFFF_FFFF_FFFF_FFFF;

main :: () {
	trace_t1();
	trace_t2();
	trace_t3();
	trace_t4();
	trace_t5();
	trace_t6();
	trace_t7();
	trace_t8();
	trace_v1();
	trace_v2();
	trace_v3();
	trace_v4();
	trace_v5();
	trace_v6();
	trace_v7();
	trace_v8();
	print("Service traces PASS.\n");
}

Trace :: struct {
	name: string;
	root: string;
	host: *Service.Harness_Host;
	session: *Service.Session;
}

start :: (name: string) -> Trace {
	trace: Trace;
	trace.name = name;
	trace.root = sprint("%.build/traces/%", #filepath, name);
	if file_exists(trace.root) {
		delete_directory(trace.root);
	}

	make_directory_if_it_does_not_exist(trace.root, recursive = true);
	reopen(*trace);
	return trace;
}

reopen :: (trace: *Trace) {
	ceilings: Service.Limits;
	for * ceilings.values {
		it.* = 1 << 20;
	}

	minima: Service.Limits;
	minima.values[Service.Limit_Name.LIVE_HANDLES] = 2;
	minima.values[Service.Limit_Name.IN_FLIGHT_OPERATIONS] = 1;
	failure, host, error := Service.open_harness_host(trace.root, ceilings, minima);
	assert(failure == .NONE, "%: host failed to open: % %.", trace.name, failure, error);
	trace.host = host;
	trace.session = Service.session_of(host.service, host.session);
}

// Every child registration has been released: only the `.SESSION` handle and, before shutdown, the shutdown reservation remain charged.
finish :: (trace: *Trace) {
	Service.with_lock(
		*trace.session.gate,
		#code {
			ledger := trace.session.ledger;
			stopped := trace.session.lifecycle == .STOPPED;
			for ledger.live {
				name := it_index.(Service.Limit_Name);
				live_expected := ifx name == .LIVE_HANDLES then 1;
				reserved_expected := ifx !stopped && (name == .LIVE_HANDLES || name == .IN_FLIGHT_OPERATIONS) then 1;
				assert(it == live_expected && ledger.reserved[it_index] == reserved_expected, "%: ledger % holds % live, % reserved.", trace.name, name, it, ledger.reserved[it_index]);
			}
		}
	);

	service := trace.host.service;
	handle := trace.host.session;
	closed, error := Service.close_harness_host(trace.host);
	assert(closed, "%: close failed: %.", trace.name, error);
	assert(!Service.session_of(service, handle), "%: the session survived its final release.", trace.name);
	print("% PASS\n", trace.name);
}

write :: (trace: *Trace, relative: string, text: string) {
	assert(write_entire_file(tprint("%/%", trace.root, relative), text));
}

submit :: (batch: *Service.Host_Batch) -> Service.Handle(.TICKET), [] u8 {
	ok, accepted, error := Service.submit_batch(batch);
	assert(ok, "Submit failed: %.", error);
	return accepted.ticket, accepted.frontier;
}

reject :: (batch: *Service.Host_Batch, code: Service.Operation_Error_Code) -> Service.Operation_Error {
	ok, _, error := Service.submit_batch(batch);
	assert(!ok && error.code == code, "Expected %, got % (accepted %).", code, error.code, ok);
	return error;
}

await :: (trace: *Trace, ticket: Service.Handle(.TICKET)) -> Service.Observation {
	ok, waited := Service.wait(trace.host.service, ticket, .{clock_identity = trace.host.service.clock_identity, nanoseconds = FOREVER});
	assert(ok && !waited.timed_out);
	return waited.observation;
}

world_of :: (trace: *Trace, ticket: Service.Handle(.TICKET)) -> Service.Handle(.WORLD) {
	observation := await(trace, ticket);
	assert(observation.update.kind == .PUBLISHED, "%: update ended %.", trace.name, observation.update.kind);
	ok, acquisition := Service.acquire_world(trace.host.service, .{kind = .PUBLISHED_UPDATE, ticket = ticket});
	assert(ok && acquisition.kind == .ACQUIRED);
	return acquisition.world;
}

query :: (trace: *Trace, world: Service.Handle(.WORLD), relative: string, kind: Service.Query_Kind) -> Service.Query_Start {
	ok, start := Service.query(trace.host.service, .{version = Service.INTERFACE_VERSION, world = world, document = Service.harness_document(trace.host, relative), kind = kind});
	assert(ok, "Query failed.");
	return start;
}

// Independent oracle: the published snapshot equals a fresh parse of the authored bytes under the same filename.
expect_text :: (trace: *Trace, world: Service.Handle(.WORLD), relative: string, text: string) {
	start := query(trace, world, relative, .SYNTAX_SNAPSHOT);
	assert(start.kind == .AVAILABLE, "%: % is not available.", trace.name, relative);
	expect_result(trace, start.result, relative, text);
	release(trace, start.result);
}

expect_result :: (trace: *Trace, result: Service.Handle(.RESULT), relative: string, text: string) {
	ok, description := Service.read_result(trace.host.service, result);
	assert(ok);
	fresh := Parser.parse_file(copy_string(text), tprint("%/%", trace.root, relative), resolve_identifiers = false);
	check_snapshot(*description.backing.owner.parsed, *fresh);
	status := description.diagnostics_status;
	assert(xx (status.error_count + status.warning_count) == fresh.diagnostics.count, "%: diagnostic summary disagrees with the fresh parse.", trace.name);
}

release :: (trace: *Trace, handle: Service.Handle($K)) {
	ok, error := Service.release(trace.host.service, handle);
	assert(ok, "Release failed: %.", error);
}

selection :: (trace: *Trace, relative: string) -> Service.Tracked_Document {
	_, description := Service.describe_session(trace.host.service, trace.host.session);
	for description.tracked_document_states {
		if Service.bytes_equal(it.document, Service.harness_document(trace.host, relative)) {
			return it;
		}
	}


	assert(false, "% is not tracked.", relative);
	return .{};
}

frontier :: (trace: *Trace) -> [] u8 {
	_, description := Service.describe_session(trace.host.service, trace.host.session);
	return description.accepted_frontier;
}

disk :: (trace: *Trace, relatives: .. string) -> Service.Handle(.TICKET) {
	batch := Service.begin_batch(trace.host);
	for relatives {
		assert(Service.observe_disk(*batch, it));
	}

	ticket := submit(*batch);
	return ticket;
}

overlay :: (trace: *Trace, relative: string, text: string) -> Service.Handle(.TICKET) {
	batch := Service.begin_batch(trace.host);
	assert(Service.set_overlay(*batch, relative, text));
	ticket := submit(*batch);
	return ticket;
}

// T1: capture disk A, notify overlay B, await B and query it; no semantic promise, and A's leased results stay exact.
trace_t1 :: () {
	trace := start("T1");
	write(*trace, "a.jai", "a :: 1;");
	ticket_a := disk(*trace, "a.jai");
	world_a := world_of(*trace, ticket_a);
	leased_a := query(*trace, world_a, "a.jai", .SYNTAX_SNAPSHOT);

	ticket_b := overlay(*trace, "a.jai", "b :: (x: int) -> int { return x; }");
	world_b := world_of(*trace, ticket_b);
	expect_text(*trace, world_b, "a.jai", "b :: (x: int) -> int { return x; }");
	semantic := query(*trace, world_b, "a.jai", .SEMANTIC_QUERY);
	assert(semantic.kind == .TERMINAL && semantic.observation.query.kind == .UNSUPPORTED);
	expect_result(*trace, leased_a.result, "a.jai", "a :: 1;");

	release(*trace, leased_a.result);
	for Service.Handle(.WORLD).[world_a, world_b] {
		release(*trace, it);
	}

	for Service.Handle(.TICKET).[ticket_a, ticket_b] {
		release(*trace, it);
	}

	finish(*trace);
}

// T2: a stale source base and an invalid range each reject atomically with B unchanged; a full replacement then succeeds.
trace_t2 :: () {
	trace := start("T2");
	ticket_a := overlay(*trace, "a.jai", "a :: 1;");
	await(*trace, ticket_a);
	ticket_b := overlay(*trace, "a.jai", "b :: 2;");
	world_b := world_of(*trace, ticket_b);
	before := frontier(*trace);

	stale := Service.begin_batch(trace.host);
	assert(Service.edit_overlay(*stale, "a.jai", .[.{start_byte = 0, end_byte = 1, replacement = xx "x"}]));
	stale.events[0].base_source_revision = Service.source_revision_of(xx "a :: 1;");
	error := reject(*stale, .BASE_MISMATCH);
	assert(error.scope == .SOURCE);

	invalid := Service.begin_batch(trace.host);
	assert(Service.edit_overlay(*invalid, "a.jai", .[.{start_byte = 0, end_byte = 1, replacement = xx "c"}, .{start_byte = 5, end_byte = 100}]));
	error = reject(*invalid, .INVALID_ARGUMENT);
	assert(error.rule == .OUT_OF_RANGE);

	assert(Service.bytes_equal(frontier(*trace), before), "A rejected batch advanced the frontier.");
	assert(Service.bytes_equal(selection(*trace, "a.jai").overlay_source_revision, Service.source_revision_of(xx "b :: 2;")));
	expect_text(*trace, world_b, "a.jai", "b :: 2;");

	ticket_c := overlay(*trace, "a.jai", "c :: 3;");
	world_c := world_of(*trace, ticket_c);
	expect_text(*trace, world_c, "a.jai", "c :: 3;");

	for Service.Handle(.WORLD).[world_b, world_c] {
		release(*trace, it);
	}

	for Service.Handle(.TICKET).[ticket_a, ticket_b, ticket_c] {
		release(*trace, it);
	}

	finish(*trace);
}

// T3: B's save is acknowledged after a newer byte-identical overlay C: disk points at B and C stays selected.
trace_t3 :: () {
	trace := start("T3");
	ticket_b := overlay(*trace, "a.jai", "b :: 2;");
	await(*trace, ticket_b);
	installation_b := selection(*trace, "a.jai").overlay_installation_revision;
	write(*trace, "a.jai", "b :: 2;");

	ticket_c := overlay(*trace, "a.jai", "b :: 2;");
	await(*trace, ticket_c);
	installation_c := selection(*trace, "a.jai").overlay_installation_revision;
	assert(!Service.bytes_equal(installation_b, installation_c), "Equal bytes reused the installation stamp.");

	batch := Service.begin_batch(trace.host);
	assert(Service.ack_save(*batch, "a.jai", installation_b));
	ticket_save := submit(*batch);
	world := world_of(*trace, ticket_save);
	state := selection(*trace, "a.jai");
	assert(state.selection == .OVERLAY && Service.bytes_equal(state.overlay_installation_revision, installation_c), "The late acknowledgement discarded C.");
	assert(Service.bytes_equal(state.disk_source_revision, Service.source_revision_of(xx "b :: 2;")));
	expect_text(*trace, world, "a.jai", "b :: 2;");

	release(*trace, world);
	for Service.Handle(.TICKET).[ticket_b, ticket_c, ticket_save] {
		release(*trace, it);
	}

	finish(*trace);
}

// T4: confirmed reset selects disk A; after a restart B is not selected merely because it existed, and restoring it is a new confirmed event.
trace_t4 :: () {
	trace := start("T4 before restart");
	write(*trace, "a.jai", "a :: 1;");
	ticket_a := disk(*trace, "a.jai");
	await(*trace, ticket_a);
	ticket_b := overlay(*trace, "a.jai", "b :: 2;");
	await(*trace, ticket_b);

	batch := Service.begin_batch(trace.host);
	assert(Service.reset_overlay(*batch, "a.jai"));
	ticket_reset := submit(*batch);
	world_reset := world_of(*trace, ticket_reset);
	expect_text(*trace, world_reset, "a.jai", "a :: 1;");
	assert(selection(*trace, "a.jai").selection == .DISK);
	release(*trace, world_reset);
	for Service.Handle(.TICKET).[ticket_a, ticket_b, ticket_reset] {
		release(*trace, it);
	}

	finish(*trace);

	trace.name = "T4 after restart";
	reopen(*trace);
	ticket_restart := disk(*trace, "a.jai");
	world_restart := world_of(*trace, ticket_restart);
	expect_text(*trace, world_restart, "a.jai", "a :: 1;");
	assert(!selection(*trace, "a.jai").has_overlay, "The discarded overlay came back after restart.");

	batch = Service.begin_batch(trace.host);
	assert(Service.restore_overlay(*batch, "a.jai", "b :: 2;", xx "recovered-b"));
	ticket_restore := submit(*batch);
	world_restore := world_of(*trace, ticket_restore);
	expect_text(*trace, world_restore, "a.jai", "b :: 2;");
	assert(selection(*trace, "a.jai").selection == .RESTORED_OVERLAY);

	for Service.Handle(.WORLD).[world_restart, world_restore] {
		release(*trace, it);
	}

	for Service.Handle(.TICKET).[ticket_restart, ticket_restore] {
		release(*trace, it);
	}

	finish(*trace);
}

// T5: a leased A result stays exact after B is published and A's world and ticket are released; its released handle then rejects, even once its slot is reused.
trace_t5 :: () {
	trace := start("T5");
	ticket_a := overlay(*trace, "a.jai", "a :: 1;");
	world_a := world_of(*trace, ticket_a);
	leased := query(*trace, world_a, "a.jai", .SYNTAX_DECLARATION_INDEX);
	ticket_b := overlay(*trace, "a.jai", "b :: 2;");
	world_b := world_of(*trace, ticket_b);
	release(*trace, world_a);
	release(*trace, ticket_a);

	expect_result(*trace, leased.result, "a.jai", "a :: 1;");
	release(*trace, leased.result);
	stale_ok, _, stale_error := Service.read_result(trace.host.service, leased.result);
	assert(!stale_ok && stale_error.code == .INVALID_HANDLE);

	reused := query(*trace, world_b, "a.jai", .SYNTAX_SNAPSHOT);
	assert(reused.result.slot == leased.result.slot && reused.result.generation == leased.result.generation + 1, "The freed slot was not reused with a new generation.");
	stale_ok = Service.read_result(trace.host.service, leased.result);
	assert(!stale_ok, "A stale handle reached the reused slot.");

	release(*trace, reused.result);
	release(*trace, world_b);
	release(*trace, ticket_b);
	finish(*trace);
}

// T6: two waiters share one task; the caller-cancelled one gets no payload, a duplicate completion is rejected and one task ran.
trace_t6 :: () {
	trace := start("T6");
	text :: "a :: ;\nb :: 1";
	ticket := overlay(*trace, "a.jai", text);
	world := world_of(*trace, ticket);
	#if REAL_WORKER {
		Service.arm_pause(trace.session, .PUBLICATION);
	}

	first := query(*trace, world, "a.jai", .SYNTAX_DIAGNOSTICS);
	#if REAL_WORKER {
		assert(Service.await_pause(trace.session, .PUBLICATION));
	}

	second := query(*trace, world, "a.jai", .SYNTAX_DIAGNOSTICS);
	assert(first.kind == .PENDING && second.kind == .PENDING);

	_, cancelled := Service.cancel_waiter(trace.host.service, first.waiter);
	assert(!cancelled.already_terminal && cancelled.observation.query.cancellation == .CALLER);
	#if REAL_WORKER {
		mailbox := Service.last_mailbox(trace.session);
		Service.resume_pause(trace.session, .PUBLICATION);
		_, waited := Service.wait(trace.host.service, second.waiter, .{clock_identity = trace.host.service.clock_identity, nanoseconds = FOREVER});
		assert(!waited.timed_out && waited.observation.query.kind == .AVAILABLE);
		Service.free_observation(*waited.observation);
		assert(Service.executor_deliver(trace.session, mailbox) == .REJECTED);
	} else {
		assert(trace.session.ready.count == 1);
		mailbox := Service.executor_dispatch(trace.session);
		assert(!Service.executor_dispatch(trace.session), "Equivalent queries dispatched twice.");
		assert(Service.executor_deliver(trace.session, mailbox) == .PUBLISHED);
		assert(Service.executor_deliver(trace.session, mailbox) == .REJECTED);
	}

	_, survivor := Service.acquire_result(trace.host.service, second.waiter);
	assert(survivor.kind == .ACQUIRED);
	_, description := Service.read_result(trace.host.service, survivor.result);
	fresh := Parser.parse_file(copy_string(text), tprint("%/a.jai", trace.root), resolve_identifiers = false);
	assert(description.diagnostics.records.count == fresh.diagnostics.count && fresh.diagnostics.count > 0);
	_, late := Service.acquire_result(trace.host.service, first.waiter);
	assert(late.kind == .TERMINAL, "The cancelled waiter received a payload.");

	release(*trace, survivor.result);
	for Service.Handle(.WAITER).[first.waiter, second.waiter] {
		release(*trace, it);
	}

	release(*trace, world);
	release(*trace, ticket);
	finish(*trace);
}

// T7: newer source C supersedes B's pending update and its waiters and cancels B's running query work; nothing late publishes and nothing is reissued.
trace_t7 :: () {
	trace := start("T7");
	ticket_b := overlay(*trace, "a.jai", "b :: 1;");
	world_b := world_of(*trace, ticket_b);
	#if REAL_WORKER {
		Service.arm_pause(trace.session, .PUBLICATION);
	}

	queries: [2] Service.Query_Start;
	for * queries {
		it.* = query(*trace, world_b, "a.jai", .SYNTAX_DIAGNOSTICS);
	}

	running: *Service.Mailbox;
	#if REAL_WORKER {
		assert(Service.await_pause(trace.session, .PUBLICATION));
		running = Service.last_mailbox(trace.session);
	} else {
		running = Service.executor_dispatch(trace.session);
	}
	ticket_pending := overlay(*trace, "a.jai", "b :: 2;");
	update_waiters: [2] Service.Handle(.WAITER);
	for * update_waiters {
		_, observed := Service.observe_ticket(trace.host.service, ticket_pending);
		it.* = observed.waiter;
	}

	ticket_c := overlay(*trace, "a.jai", "c :: 3;");
	for queries {
		_, observation := Service.poll(trace.host.service, it.waiter);
		assert(observation.query.cancellation == .WORLD_SUPERSEDED, "A pending B query waiter survived.");
	}

	for update_waiters {
		_, observation := Service.poll(trace.host.service, it);
		assert(observation.kind == .UPDATE && observation.update.kind == .SUPERSEDED);
	}

	#if REAL_WORKER {
		Service.resume_pause(trace.session, .PUBLICATION);
	} else {
		assert(Service.executor_deliver(trace.session, running) == .DISCARDED, "B published a late result.");
		assert(trace.session.ready.count == 1, "Superseded work was reissued.");
	}
	expect_text(*trace, world_b, "a.jai", "b :: 1;");
	world_c := world_of(*trace, ticket_c);
	#if REAL_WORKER {
		assert(Service.executor_deliver(trace.session, running) == .REJECTED);
	}
	expect_text(*trace, world_c, "a.jai", "c :: 3;");

	for queries {
		release(*trace, it.waiter);
	}

	for update_waiters {
		release(*trace, it);
	}

	for Service.Handle(.WORLD).[world_b, world_c] {
		release(*trace, it);
	}

	for Service.Handle(.TICKET).[ticket_b, ticket_pending, ticket_c] {
		release(*trace, it);
	}

	finish(*trace);
}

// T8 (capability branch): semantic and evaluation requests are terminal and unsupported, create no task, and leave syntax usable.
trace_t8 :: () {
	trace := start("T8");
	ticket := overlay(*trace, "a.jai", "a :: #run 1 + 1;");
	world := world_of(*trace, ticket);
	tasks := trace.session.tasks.count;
	for Service.Query_Kind.[.SEMANTIC_QUERY, .COMPILER_EVALUATION] {
		start := query(*trace, world, "a.jai", it);
		assert(start.kind == .TERMINAL && start.observation.query.kind == .UNSUPPORTED && start.observation.query.unsupported == it);
	}

	assert(trace.session.tasks.count == tasks && !trace.session.ready.count, "An unsupported request created work.");
	expect_text(*trace, world, "a.jai", "a :: #run 1 + 1;");
	release(*trace, world);
	release(*trace, ticket);
	finish(*trace);
}

// V1: a captured overlay world stays exact while disk events, a save and a reset arrive; the disk branch advances truthfully.
trace_v1 :: () {
	trace := start("V1");
	write(*trace, "a.jai", "a :: 1;");
	ticket_disk := disk(*trace, "a.jai");
	await(*trace, ticket_disk);
	ticket_b := overlay(*trace, "a.jai", "b :: 2;");
	world_b := world_of(*trace, ticket_b);

	write(*trace, "a.jai", "x :: 9;");
	ticket_external := disk(*trace, "a.jai");
	await(*trace, ticket_external);
	assert(Service.bytes_equal(selection(*trace, "a.jai").disk_source_revision, Service.source_revision_of(xx "x :: 9;")));
	expect_text(*trace, world_b, "a.jai", "b :: 2;");

	write(*trace, "a.jai", "b :: 2;");
	batch := Service.begin_batch(trace.host);
	assert(Service.ack_save(*batch, "a.jai"));
	ticket_save := submit(*batch);
	await(*trace, ticket_save);
	assert(selection(*trace, "a.jai").selection == .DISK);
	expect_text(*trace, world_b, "a.jai", "b :: 2;");

	ticket_c := overlay(*trace, "a.jai", "c :: 3;");
	await(*trace, ticket_c);
	batch = Service.begin_batch(trace.host);
	assert(Service.reset_overlay(*batch, "a.jai"));
	ticket_reset := submit(*batch);
	await(*trace, ticket_reset);
	expect_text(*trace, world_b, "a.jai", "b :: 2;");

	release(*trace, world_b);
	for Service.Handle(.TICKET).[ticket_disk, ticket_b, ticket_external, ticket_save, ticket_c, ticket_reset] {
		release(*trace, it);
	}

	finish(*trace);
}

// V2: an uncaptured document is unavailable as not captured, distinct from a provider-confirmed absent member.
trace_v2 :: () {
	trace := start("V2");
	write(*trace, "a.jai", "a :: 1;");
	ticket := disk(*trace, "a.jai", "missing.jai");
	world := world_of(*trace, ticket);
	uncaptured := query(*trace, world, "elsewhere.jai", .SYNTAX_DECLARATION_INDEX);
	absent := query(*trace, world, "missing.jai", .SYNTAX_DECLARATION_INDEX);
	assert(uncaptured.kind == .TERMINAL && uncaptured.observation.query.unavailable == .NOT_CAPTURED);
	assert(absent.kind == .TERMINAL && absent.observation.query.unavailable == .SOURCE_ABSENT);
	assert(!trace.session.ready.count);
	release(*trace, world);
	release(*trace, ticket);
	finish(*trace);
}

// V3: a document first observed at a later frontier is not attached to an older world; analysis must name the current frontier.
trace_v3 :: () {
	trace := start("V3");
	write(*trace, "a.jai", "a :: 1;");
	ticket_one := disk(*trace, "a.jai");
	world_one := world_of(*trace, ticket_one);
	first_frontier := frontier(*trace);

	write(*trace, "b.jai", "b :: 2;");
	ticket_two := disk(*trace, "b.jai");
	await(*trace, ticket_two);
	late := query(*trace, world_one, "b.jai", .SYNTAX_SNAPSHOT);
	assert(late.kind == .TERMINAL && late.observation.query.unavailable == .NOT_CAPTURED, "Later bytes were attached to the old world.");

	members := ([] u8).[Service.harness_document(trace.host, "a.jai"), Service.harness_document(trace.host, "b.jai")];
	ok, _, error := Service.request_analysis(trace.host.service, trace.host.session, .{version = Service.INTERFACE_VERSION, expected_frontier = first_frontier, documents = members});
	assert(!ok && error.code == .BASE_MISMATCH);
	analysed: Service.Accepted;
	ok, analysed = Service.request_analysis(trace.host.service, trace.host.session, .{version = Service.INTERFACE_VERSION, expected_frontier = frontier(*trace), documents = members});
	assert(ok);
	world_both := world_of(*trace, analysed.ticket);
	expect_text(*trace, world_both, "a.jai", "a :: 1;");
	expect_text(*trace, world_both, "b.jai", "b :: 2;");

	for Service.Handle(.WORLD).[world_one, world_both] {
		release(*trace, it);
	}

	for Service.Handle(.TICKET).[ticket_one, ticket_two, analysed.ticket] {
		release(*trace, it);
	}

	finish(*trace);
}

// V4: a file changed during sequential acquisition keeps the bytes read for the capture, and no coherent snapshot is claimed.
trace_v4 :: () {
	trace := start("V4");
	write(*trace, "a.jai", "a :: 1;");
	write(*trace, "b.jai", "b :: 2;");
	batch := Service.begin_batch(trace.host);
	assert(Service.observe_disk(*batch, "a.jai"));
	write(*trace, "a.jai", "a :: 100;");
	assert(Service.observe_disk(*batch, "b.jai"));
	ticket := submit(*batch);
	world := world_of(*trace, ticket);
	_, described := Service.read_world(trace.host.service, world);
	assert(described.consistency.kind == .IMMUTABLE_CAPTURE, "Sequential reads were labelled coherent.");
	expect_text(*trace, world, "a.jai", "a :: 1;");
	expect_text(*trace, world, "b.jai", "b :: 2;");
	release(*trace, world);
	release(*trace, ticket);
	finish(*trace);
}

// V5: one stale member and an unsupported rename each reject the whole batch; a valid replacement then commits one frontier.
trace_v5 :: () {
	trace := start("V5");
	ticket_a := overlay(*trace, "a.jai", "a :: 1;");
	await(*trace, ticket_a);
	before := frontier(*trace);

	batch := Service.begin_batch(trace.host);
	assert(Service.set_overlay(*batch, "new.jai", "n :: 1;"));
	assert(Service.edit_overlay(*batch, "a.jai", .[.{start_byte = 0, end_byte = 1, replacement = xx "z"}]));
	batch.events[1].base_source_revision = Service.source_revision_of(xx "stale");
	reject(*batch, .BASE_MISMATCH);

	batch = Service.begin_batch(trace.host);
	assert(Service.set_overlay(*batch, "new.jai", "n :: 1;"));
	assert(Service.set_overlay(*batch, "a.jai", "a :: 2;"));
	batch.events[1].kind = .RENAME;
	reject(*batch, .UNSUPPORTED_EVENT);

	_, description := Service.describe_session(trace.host.service, trace.host.session);
	assert(Service.bytes_equal(description.accepted_frontier, before) && description.tracked_document_states.count == 1, "A rejected batch committed a member.");

	batch = Service.begin_batch(trace.host);
	assert(Service.set_overlay(*batch, "new.jai", "n :: 1;"));
	assert(Service.set_overlay(*batch, "a.jai", "a :: 2;"));
	ticket, accepted_frontier := submit(*batch);
	world := world_of(*trace, ticket);
	expect_text(*trace, world, "new.jai", "n :: 1;");
	expect_text(*trace, world, "a.jai", "a :: 2;");
	assert(!Service.bytes_equal(accepted_frontier, before));

	release(*trace, world);
	release(*trace, ticket_a);
	release(*trace, ticket);
	finish(*trace);
}

// V6: one failed member fails the whole milestone; no mixed world is published, the accepted source stays, and the old head stays labelled old.
trace_v6 :: () {
	trace := start("V6");
	ticket_old := overlay(*trace, "a.jai", "a :: 1;");
	await(*trace, ticket_old);
	old_head := trace.session.head;

	trace.session.faults.fail_parse_document = Service.harness_document(trace.host, "b.jai");
	batch := Service.begin_batch(trace.host);
	assert(Service.set_overlay(*batch, "a.jai", "a :: 2;"));
	assert(Service.set_overlay(*batch, "b.jai", "b :: 2;"));
	ticket, accepted_frontier := submit(*batch);
	observation := await(*trace, ticket);
	assert(observation.update.kind == .FAILED && observation.update.failure.stage == .CONVERSION);
	assert(trace.session.head == old_head && !Service.bytes_equal(old_head.frontier, accepted_frontier), "A mixed or failed world became the head.");
	assert(Service.bytes_equal(selection(*trace, "b.jai").overlay_source_revision, Service.source_revision_of(xx "b :: 2;")), "Failed analysis rolled back accepted source.");

	// Retrying analysis needs no replayed edit.
	trace.session.faults.fail_parse_document = .[];
	members := ([] u8).[Service.harness_document(trace.host, "a.jai"), Service.harness_document(trace.host, "b.jai")];
	ok, retry := Service.request_analysis(trace.host.service, trace.host.session, .{version = Service.INTERFACE_VERSION, expected_frontier = accepted_frontier, documents = members});
	assert(ok);
	world := world_of(*trace, retry.ticket);
	expect_text(*trace, world, "a.jai", "a :: 2;");
	expect_text(*trace, world, "b.jai", "b :: 2;");

	release(*trace, world);
	for Service.Handle(.TICKET).[ticket_old, ticket, retry.ticket] {
		release(*trace, it);
	}

	finish(*trace);
}

// V7: accepted bytes are copied, so releasing the caller's buffers and resetting the buffer leave a leased world exact.
trace_v7 :: () {
	trace := start("V7");
	text := sprint("v :: %;", 7);
	ticket := overlay(*trace, "a.jai", text);
	memset(text.data, #char "?", text.count);
	free(text);
	world := world_of(*trace, ticket);

	batch := Service.begin_batch(trace.host);
	assert(Service.reset_overlay(*batch, "a.jai"));
	ticket_reset := submit(*batch);
	await(*trace, ticket_reset);
	expect_text(*trace, world, "a.jai", "v :: 7;");

	release(*trace, world);
	release(*trace, ticket);
	release(*trace, ticket_reset);
	finish(*trace);
}

// V8: an unreadable provider path submits nothing; shutdown waits for a running producer, rejects its repeated completion and never writes source.
trace_v8 :: () {
	trace := start("V8");
	make_directory_if_it_does_not_exist(tprint("%/folder.jai", trace.root));
	batch := Service.begin_batch(trace.host);
	assert(!Service.observe_disk(*batch, "folder.jai"));

	write(*trace, "a.jai", "a :: 1;");
	#if REAL_WORKER {
		Service.arm_pause(trace.session, .PARSED);
	}

	ticket := disk(*trace, "a.jai");
	running: *Service.Mailbox;
	#if REAL_WORKER {
		assert(Service.await_pause(trace.session, .PARSED));
		running = Service.last_mailbox(trace.session);
	} else {
		running = Service.executor_dispatch(trace.session);
	}
	ok, shutdown := Service.request_shutdown(trace.host.service, trace.host.session);
	assert(ok);
	_, draining := Service.poll(trace.host.service, shutdown);
	assert(draining.kind == .PENDING && draining.phase == .DRAINING, "Shutdown stopped before its producer returned.");
	#if REAL_WORKER {
		Service.resume_pause(trace.session, .PARSED);
		_, waited := Service.wait(trace.host.service, shutdown, .{clock_identity = trace.host.service.clock_identity, nanoseconds = FOREVER});
		assert(!waited.timed_out && waited.observation.kind == .SHUTDOWN);
		Service.free_observation(*waited.observation);
	} else {
		assert(Service.executor_deliver(trace.session, running) == .DISCARDED);
	}
	assert(Service.executor_deliver(trace.session, running) == .REJECTED);
	_, stopped := Service.poll(trace.host.service, shutdown);
	assert(stopped.kind == .SHUTDOWN);
	_, observation := Service.poll(trace.host.service, ticket);
	assert(observation.update.kind == .CANCELLED && observation.update.cancellation == .SHUTDOWN);
	contents := read_entire_file(tprint("%/a.jai", trace.root));
	assert(contents == "a :: 1;", "Source was written.");

	release(*trace, shutdown);
	release(*trace, ticket);
	finish(*trace);
}
