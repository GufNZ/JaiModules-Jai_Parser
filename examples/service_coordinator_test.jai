// Phase-4 coordinator tests: the fifteen operations over one session with the deterministic step executor.
// Run from this directory: jai service_coordinator_test.jai -x64 -quiet && ./service_coordinator_test.exe
#import "Basic";

Service :: #import "Jai_Parser/service"(TEST_HOOKS = true);

NAMESPACE :: "test-provider";
HOST :: "test-host";
WORKSPACE :: "test-workspace";

main :: () {
	test_open_session();
	test_edit_and_query();
	test_shared_waiters();
	test_supersession();
	test_analysis_requests();
	test_shutdown_and_limits();
	test_negative_controls();
	print("Service coordinator \e[92mPASS\e[0m.\n");
}

new_service :: () -> *Service.Service {
	ceilings: Service.Limits;
	for * ceilings.values {
		it.* = 1 << 20;
	}

	minima: Service.Limits;
	minima.values[Service.Limit_Name.LIVE_HANDLES] = 2;
	minima.values[Service.Limit_Name.IN_FLIGHT_OPERATIONS] = 1;
	return Service.open_service(xx "test-authority", 1, ceilings, minima);
}

registration :: (filename := "D:/project/main.jai") -> Service.Context_Registration {
	paths: Service.Context_Paths;
	_, paths.visible_filename = Service.windows_path_value(filename);
	_, paths.visible_directory = Service.windows_path_value("D:/project");
	_, paths.relative_base = Service.windows_path_value("D:/project");
	_, descriptor := Service.syntax_context_descriptor(paths);
	return .{identity = Service.context_id(descriptor), descriptor = descriptor};
}

options :: () -> Service.Session_Options {
	contexts := NewArray(1, Service.Context_Registration);
	contexts[0] = registration();
	return .{
		version = Service.INTERFACE_VERSION,
		workspace = xx WORKSPACE,
		provider_namespace = xx NAMESPACE,
		host_authority = xx HOST,
		provider_capabilities = .{
			adapter_schema = Service.SOURCE_PROVIDER_SCHEMA,
			authority_identity = xx NAMESPACE,
			document_policy_version = 1,
			path_platform = .WINDOWS_UTF16LE,
			consistency_capabilities = .IMMUTABLE_CAPTURE,
		},
		supported_tuples = .[Service.IMPLEMENTED_SCHEMA_TUPLE],
		contexts = contexts,
	};
}

Fixture :: struct {
	service: *Service.Service;
	handle: Service.Handle(.SESSION);
	session: *Service.Session;
	revisions: s64;
}

open :: () -> Fixture {
	return open(options());
}

open :: (session_options: Service.Session_Options) -> Fixture {
	fixture: Fixture;
	fixture.service = new_service();
	ok, opened, error := Service.open_session(fixture.service, session_options);
	assert(ok, "\e[91mOpenSession failed: %.\e[0m", error);
	fixture.handle = opened.session;
	fixture.session = Service.session_of(fixture.service, opened.session);
	return fixture;
}

doc :: (key: string) -> [] u8 {
	return Service.document_id(xx NAMESPACE, 1, xx key);
}

same :: (a: $T, b: T) -> bool {
	return Service.bytes_equal(a.([] u8), b.([] u8));
}

// Replaces `key`'s overlay with `text` in one batch and returns the ticket.
set_text :: (fixture: *Fixture, key: string, text: string) -> Service.Handle(.TICKET), [] u8 {
	session := fixture.session;
	document := doc(key);
	state := Service.find_document(session.provider, document);
	fixture.revisions += 1;
	binding := New(Service.Document_Binding);
	binding.document = document;
	binding.provider_policy_version = 1;
	_, binding.absolute_path = Service.windows_path_value(tprint("D:/project/%.jai", key));
	event := Service.Document_Event.{
		document = document,
		expected_provider_state = ifx state then Service.Expected_Provider_State.{kind = .REVISION, revision = state.provider_revision},
		source_context = registration().identity,
		binding = ifx !state then binding,
		kind = .SET_OVERLAY,
		source = .{kind = .INLINE_BYTES, bytes = xx text},
		resulting_provider_revision = Service.provider_revision_id(xx NAMESPACE, session.identities.session, document, xx tprint("%", fixture.revisions)),
	};
	batch := Service.Source_Batch.{
		version = Service.INTERFACE_VERSION,
		session = session.identities.session,
		expected_frontier = session.provider.accepted_frontier,
		events = .[event],
	};
	ok, accepted, error := Service.submit_source_batch(fixture.service, fixture.handle, batch);
	assert(ok, "\e[91mSubmitSourceBatch failed: %.\e[0m", error);
	return accepted.ticket, accepted.frontier;
}

world_of :: (fixture: *Fixture, ticket: Service.Handle(.TICKET)) -> Service.Handle(.WORLD) {
	ok, acquisition := Service.acquire_world(fixture.service, .{kind = .PUBLISHED_UPDATE, ticket = ticket});
	assert(ok && acquisition.kind == .ACQUIRED, "\e[91mAcquireWorld: %.\e[0m", acquisition.kind);
	return acquisition.world;
}

query :: (fixture: *Fixture, world: Service.Handle(.WORLD), key: string, kind: Service.Query_Kind) -> Service.Query_Start {
	ok, start, error := Service.query(fixture.service, .{version = Service.INTERFACE_VERSION, world = world, document = doc(key), kind = kind});
	assert(ok, "\e[91mQuery failed: %.\e[0m", error);
	return start;
}

release :: (fixture: *Fixture, handle: Service.Handle($K)) {
	ok, error := Service.release(fixture.service, handle);
	assert(ok, "\e[91mRelease failed: %.\e[0m", error);
}

// After shutdown and every child release, only the `.SESSION` registration is still charged.
close :: (fixture: *Fixture) {
	ok, shutdown := Service.request_shutdown(fixture.service, fixture.handle);
	assert(ok);
	_, observation := Service.poll(fixture.service, shutdown);
	assert(observation.kind == .SHUTDOWN, "\e[91mShutdown still pending: %.\e[0m", observation.phase);
	release(fixture, shutdown);
	ledger := fixture.session.ledger;
	for ledger.live {
		expected := ifx it_index.(Service.Limit_Name) == .LIVE_HANDLES then 1;
		assert(it == expected && !ledger.reserved[it_index], "\e[91mLedger % holds % live, % reserved.\e[0m", it_index.(Service.Limit_Name), it, ledger.reserved[it_index]);
	}

	release(fixture, fixture.handle);
	assert(!Service.session_of(fixture.service, fixture.handle), "\e[91mThe session survived its final release.\e[0m");
}

test_open_session :: () {
	service := new_service();
	expect :: (service: *Service.Service, session_options: Service.Session_Options, code: Service.Operation_Error_Code, what: string) {
		ok, _, error := Service.open_session(service, session_options);
		assert(!ok && error.code == code, "\e[91m%: expected %, got %.\e[0m", what, code, error.code);
		assert(!service.sessions.count, "\e[91m%: a partial session escaped.\e[0m", what);
	}

	wrong_version := options();
	wrong_version.version = "jai-cache-interface/2";
	expect(service, wrong_version, .INVALID_VERSION, "version");

	no_workspace := options();
	no_workspace.workspace = .[];
	expect(service, no_workspace, .INVALID_ARGUMENT, "workspace");

	lease := options();
	lease.provider_capabilities.lease_capabilities.kind = .IMMUTABLE_RETAIN_RELEASE;
	expect(service, lease, .ADMISSION_DENIED, "lease capability");

	changed := Service.IMPLEMENTED_SCHEMA_TUPLE;
	changed.nodes = "jai-cache-authored-nodes/2";
	tuple := options();
	tuple.supported_tuples = .[changed];
	expect(service, tuple, .ADMISSION_DENIED, "schema tuple");

	tiny := options();
	tiny.requested_limits.values[Service.Limit_Name.LIVE_HANDLES] = 1;
	expect(service, tiny, .ADMISSION_DENIED, "below the handle minimum");

	forged := options();
	forged.contexts = .[.{identity = registration("D:/project/other.jai").identity, descriptor = registration().descriptor}];
	expect(service, forged, .INVALID_ARGUMENT, "forged context");

	fixture := open();
	ok, description := Service.describe_session(fixture.service, fixture.handle);
	assert(ok && description.lifecycle == .OPEN && description.accepted_frontier.count && !description.tracked_document_states.count);
	assert(description.store_mode == .DISABLED && Service.bytes_equal(description.clock_identity, fixture.service.clock_identity));

	// A non-stopped session cannot be released.
	release_ok, error := Service.release(fixture.service, fixture.handle);
	assert(!release_ok && error.code == .ACTIVE_SESSION);
	close(*fixture);
	print("Open session \e[92mPASS\e[0m\n");
}

// T1: capture A, edit to B, await B's milestone and query it; A's leased results stay unchanged.
test_edit_and_query :: () {
	fixture := open();
	ticket_a := set_text(*fixture, "main", "a :: 1;");
	ok, observed := Service.observe_ticket(fixture.service, ticket_a);
	assert(ok && !observed.terminal);
	waiter_a := observed.waiter;
	_, pending := Service.poll(fixture.service, waiter_a);
	assert(pending.kind == .PENDING && pending.phase == .QUEUED);
	assert(Service.executor_run(fixture.session) == 1);
	_, published := Service.poll(fixture.service, waiter_a);
	assert(published.kind == .UPDATE && published.update.kind == .PUBLISHED);

	world_a := world_of(*fixture, ticket_a);
	snapshot_a := query(*fixture, world_a, "main", .SYNTAX_SNAPSHOT);
	assert(snapshot_a.kind == .AVAILABLE);
	_, description := Service.read_result(fixture.service, snapshot_a.result);
	assert(description.snapshot.source == "a :: 1;" && description.diagnostics_status.parse_status == .COMPLETE);
	assert(same(description.world_identity, published.update.world_identity));
	source_ok, slice := Service.read_source(fixture.service, snapshot_a.result, 0, 1);
	assert(source_ok && slice.(string) == "a");
	beyond_ok := Service.read_source(fixture.service, snapshot_a.result, 0, 8);
	assert(!beyond_ok);

	index := query(*fixture, world_a, "main", .SYNTAX_DECLARATION_INDEX);
	_, index_description := Service.read_result(fixture.service, index.result);
	assert(index.kind == .AVAILABLE && index_description.index.entries.count == 1);

	// An index result resolves its node references through its own backing, with no snapshot query held.
	node_ok, node := Service.resolve_node(fixture.service, index.result, index_description.index.entries[0].declaration_node_id);
	assert(node_ok && node.kind == "DECLARATION", "\e[91mResolved %.\e[0m", node.kind);
	token_ok, token := Service.resolve_token(fixture.service, index.result, 0);
	assert(token_ok && token == *index_description.index.snapshot.tokens[0]);
	no_node := Service.resolve_node(fixture.service, index.result, 1000);
	no_token := Service.resolve_token(fixture.service, index.result, 1000);
	no_recovery := Service.resolve_recovery(fixture.service, index.result, 0);
	assert(!no_node && !no_token && !no_recovery, "\e[91mAn out-of-range reference resolved.\e[0m");

	// Observations and descriptions are caller-owned copies: changing one leaves the next unchanged.
	_, mine := Service.poll(fixture.service, waiter_a);
	mine.operation_identity[0] ^= 0xFF;
	_, fresh := Service.poll(fixture.service, waiter_a);
	assert(!same(mine.operation_identity, fresh.operation_identity), "\e[91mAn observation borrowed session storage.\e[0m");
	Service.free_observation(*mine);
	Service.free_observation(*fresh);
	_, described := Service.describe_session(fixture.service, fixture.handle);
	described.accepted_frontier[0] ^= 0xFF;
	assert(!Service.bytes_equal(described.accepted_frontier, fixture.session.provider.accepted_frontier), "\e[91mA description borrowed session storage.\e[0m");

	semantic := query(*fixture, world_a, "main", .SEMANTIC_QUERY);
	assert(semantic.kind == .TERMINAL && semantic.observation.query.kind == .UNSUPPORTED && !fixture.session.ready.count, "\e[91mUnsupported queries create no task.\e[0m");

	_, records := Service.drain_completions(fixture.service, fixture.handle, 10);
	assert(records.count == 1 && records[0].registration.slot == waiter_a.slot && records[0].observation.update.kind == .PUBLISHED);
	_, again := Service.drain_completions(fixture.service, fixture.handle, 10);
	assert(!again.count, "\e[91mA completion was delivered twice.\e[0m");

	ticket_b, frontier_b := set_text(*fixture, "main", "b :: 2;\nc :: 3;");
	head_ok, head := Service.acquire_world(fixture.service, .{kind = .HEAD, session = fixture.handle, workspace = xx WORKSPACE, expected_frontier = frontier_b});
	assert(head_ok && head.kind == .PENDING);
	Service.executor_run(fixture.session);
	head_ok, head = Service.acquire_world(fixture.service, .{kind = .HEAD, session = fixture.handle, workspace = xx WORKSPACE, expected_frontier = frontier_b});
	assert(head_ok && head.kind == .ACQUIRED);
	stale_head_ok, stale_head := Service.acquire_world(fixture.service, .{kind = .HEAD, session = fixture.handle, workspace = xx WORKSPACE, expected_frontier = published.provider_frontier});
	assert(stale_head_ok && stale_head.kind == .UNAVAILABLE && stale_head.unavailable == .FRONTIER_MISMATCH);

	snapshot_b := query(*fixture, head.world, "main", .SYNTAX_SNAPSHOT);
	_, description_b := Service.read_result(fixture.service, snapshot_b.result);
	_, description = Service.read_result(fixture.service, snapshot_a.result);
	assert(description_b.snapshot.source == "b :: 2;\nc :: 3;" && description.snapshot.source == "a :: 1;", "\e[91mA changed after B was published.\e[0m");

	// A retained result outlives its world and ticket registrations.
	release(*fixture, world_a);
	release(*fixture, ticket_a);
	release(*fixture, waiter_a);
	_, description = Service.read_result(fixture.service, snapshot_a.result);
	assert(description.snapshot.source == "a :: 1;");
	twice_ok, twice := Service.release(fixture.service, waiter_a);
	assert(!twice_ok && twice.code == .INVALID_HANDLE, "\e[91mDouble release was accepted.\e[0m");

	release(*fixture, snapshot_a.result);
	release(*fixture, index.result);
	release(*fixture, snapshot_b.result);
	release(*fixture, head.world);
	release(*fixture, ticket_b);
	close(*fixture);
	print("Edit and query \e[92mPASS\e[0m\n");
}

// T6: two waiters share one diagnostics task; the cancelled one gets no payload and a duplicate completion is rejected.
test_shared_waiters :: () {
	fixture := open();
	ticket := set_text(*fixture, "main", "a :: ;");
	Service.executor_run(fixture.session);
	world := world_of(*fixture, ticket);

	// Releasing the last consumer of queued work removes it.
	lone := query(*fixture, world, "main", .SYNTAX_DIAGNOSTICS);
	assert(lone.kind == .PENDING && fixture.session.ready.count == 1);
	release(*fixture, lone.waiter);
	assert(!fixture.session.ready.count, "\e[91mUnconsumed queued work survived.\e[0m");

	first := query(*fixture, world, "main", .SYNTAX_DIAGNOSTICS);
	second := query(*fixture, world, "main", .SYNTAX_DIAGNOSTICS);
	assert(first.kind == .PENDING && second.kind == .PENDING && fixture.session.ready.count == 1, "\e[91mEquivalent queries did not share one task.\e[0m");

	ok, cancelled := Service.cancel_waiter(fixture.service, first.waiter);
	assert(ok && !cancelled.already_terminal && cancelled.observation.query.cancellation == .CALLER);
	assert(fixture.session.ready.count == 1, "\e[91mCancelling one consumer removed shared work.\e[0m");

	mailbox := Service.executor_dispatch(fixture.session);
	assert(Service.executor_deliver(fixture.session, mailbox) == .PUBLISHED);
	assert(Service.executor_deliver(fixture.session, mailbox) == .REJECTED, "\e[91mA duplicate completion was accepted.\e[0m");

	_, acquired := Service.acquire_result(fixture.service, second.waiter);
	assert(acquired.kind == .ACQUIRED);
	_, description := Service.read_result(fixture.service, acquired.result);
	assert(description.diagnostics.records.count.(u64) == description.diagnostics_status.error_count + description.diagnostics_status.warning_count);
	assert(description.diagnostics_status.error_count > 0);

	_, late := Service.acquire_result(fixture.service, first.waiter);
	assert(late.kind == .TERMINAL && late.observation.query.kind == .CANCELLED, "\e[91mThe cancelled waiter received a payload.\e[0m");
	_, recancel := Service.cancel_waiter(fixture.service, second.waiter);
	assert(recancel.already_terminal && recancel.observation.query.kind == .AVAILABLE);

	// The published payload now answers equal queries at once.
	third := query(*fixture, world, "main", .SYNTAX_DIAGNOSTICS);
	assert(third.kind == .AVAILABLE && !fixture.session.ready.count);

	_, records := Service.drain_completions(fixture.service, fixture.handle, 10);
	assert(records.count == 2 && records[0].observation.query.kind == .CANCELLED && records[1].observation.query.kind == .AVAILABLE, "\e[91mCompletions out of commit order.\e[0m");


	release(*fixture, first.waiter);
	release(*fixture, second.waiter);
	release(*fixture, acquired.result);
	release(*fixture, third.result);
	release(*fixture, world);
	release(*fixture, ticket);
	Service.executor_run(fixture.session);
	close(*fixture);
	print("Shared waiters \e[92mPASS\e[0m\n");
}

// T7: newer source supersedes B's unfinished work and pending waiters; B's published results stay readable and nothing is reissued.
test_supersession :: () {
	fixture := open();
	ticket_b := set_text(*fixture, "main", "b :: 1;");
	Service.executor_run(fixture.session);
	world_b := world_of(*fixture, ticket_b);
	first := query(*fixture, world_b, "main", .SYNTAX_DIAGNOSTICS);
	second := query(*fixture, world_b, "main", .SYNTAX_DIAGNOSTICS);
	running := Service.executor_dispatch(fixture.session);
	_, phase := Service.poll(fixture.service, first.waiter);
	assert(phase.kind == .PENDING && phase.phase == .RUNNING);

	ticket_c1 := set_text(*fixture, "main", "c :: 1;");
	ticket_c2 := set_text(*fixture, "main", "c :: 2;");
	for Service.Handle(.WAITER).[first.waiter, second.waiter] {
		_, observation := Service.poll(fixture.service, it);
		assert(observation.query.kind == .CANCELLED && observation.query.cancellation == .WORLD_SUPERSEDED);
	}

	_, c1 := Service.poll(fixture.service, ticket_c1);
	_, c2 := Service.poll(fixture.service, ticket_c2);
	assert(c1.kind == .UPDATE && c1.update.kind == .SUPERSEDED && same(c1.update.successor, c2.operation_identity));
	assert(c2.kind == .PENDING && fixture.session.ready.count == 1, "\e[91mThe superseded candidate is still queued.\e[0m");

	assert(Service.executor_deliver(fixture.session, running) == .DISCARDED, "\e[91mA late obsolete-world result was published.\e[0m");
	assert(!fixture.session.worlds[0].syntax[0].diagnostics);
	late := query(*fixture, world_b, "main", .SYNTAX_DIAGNOSTICS);
	assert(late.kind == .TERMINAL && late.observation.query.cancellation == .WORLD_SUPERSEDED && fixture.session.ready.count == 1);
	kept := query(*fixture, world_b, "main", .SYNTAX_SNAPSHOT);
	assert(kept.kind == .AVAILABLE, "\e[91mB's published syntax became unreadable.\e[0m");

	Service.executor_run(fixture.session);
	_, c2 = Service.poll(fixture.service, ticket_c2);
	assert(c2.update.kind == .PUBLISHED && same(fixture.session.head.identity, c2.update.world_identity));

	for Service.Handle(.WAITER).[first.waiter, second.waiter] {
		release(*fixture, it);
	}

	release(*fixture, kept.result);
	release(*fixture, world_b);
	for Service.Handle(.TICKET).[ticket_b, ticket_c1, ticket_c2] {
		release(*fixture, it);
	}

	close(*fixture);
	print("Supersession \e[92mPASS\e[0m\n");
}

test_analysis_requests :: () {
	fixture := open();
	ticket, frontier := set_text(*fixture, "main", "a :: 1;");
	Service.executor_run(fixture.session);
	_, published := Service.poll(fixture.service, ticket);

	request :: (fixture: *Fixture, frontier: [] u8, documents: .. [] u8) -> bool, Service.Accepted, Service.Operation_Error {
		ok, accepted, error := Service.request_analysis(fixture.service, fixture.handle, .{version = Service.INTERFACE_VERSION, expected_frontier = frontier, documents = documents});
		return ok, accepted, error;
	}

	// Joining an already published candidate resolves at once, at the same frontier.
	ok, joined := request(*fixture, frontier, doc("main"));
	assert(ok && Service.bytes_equal(joined.frontier, frontier));
	_, observation := Service.poll(fixture.service, joined.ticket);
	assert(observation.kind == .UPDATE && same(observation.update.world_identity, published.update.world_identity) && !fixture.session.ready.count);
	assert(!same(observation.operation_identity, published.operation_identity), "\e[91mA joined request reused another caller's operation.\e[0m");

	error: Service.Operation_Error;
	ok, _, error = request(*fixture, .[1, 2, 3], doc("main"));
	assert(!ok && error.code == .BASE_MISMATCH && error.scope == .FRONTIER);
	ok, _, error = request(*fixture, frontier, doc("main"), doc("main"));
	assert(!ok && error.rule == .DUPLICATE);
	ok, _, error = request(*fixture, frontier, doc("missing"));
	assert(!ok && error.rule == .INCONSISTENT_BINDING);
	ok, _, error = request(*fixture, frontier);
	assert(!ok && error.rule == .MISSING);
	assert(Service.bytes_equal(fixture.session.provider.accepted_frontier, frontier), "\e[91mAnalysis advanced the frontier.\e[0m");

	release(*fixture, joined.ticket);
	release(*fixture, ticket);
	close(*fixture);
	print("Analysis requests \e[92mPASS\e[0m\n");
}

// The first shutdown uses its reserved slot at full capacity, and `.STOPPED` waits for the running producer.
test_shutdown_and_limits :: () {
	limited := options();
	limited.requested_limits.values[Service.Limit_Name.LIVE_HANDLES] = 4;
	fixture := open(limited);
	ticket := set_text(*fixture, "main", "a :: 1;");
	_, observed := Service.observe_ticket(fixture.service, ticket);

	state := Service.find_document(fixture.session.provider, doc("main"));
	frontier := fixture.session.provider.accepted_frontier;
	batch := Service.Source_Batch.{
		version = Service.INTERFACE_VERSION,
		session = fixture.session.identities.session,
		expected_frontier = frontier,
		events = .[.{
			document = doc("main"),
			expected_provider_state = .{kind = .REVISION, revision = state.provider_revision},
			source_context = registration().identity,
			kind = .SET_OVERLAY,
			source = .{kind = .INLINE_BYTES, bytes = xx "b :: 1;"},
			resulting_provider_revision = Service.provider_revision_id(xx NAMESPACE, fixture.session.identities.session, doc("main"), xx "full"),
		}],
	};
	ok, _, error := Service.submit_source_batch(fixture.service, fixture.handle, batch);
	assert(!ok && error.code == .ADMISSION_DENIED && error.admission.limit == .LIVE_HANDLES);
	assert(Service.bytes_equal(fixture.session.provider.accepted_frontier, frontier), "\e[91mA rejected submission advanced the frontier.\e[0m");

	running := Service.executor_dispatch(fixture.session);
	shutdown_ok, shutdown := Service.request_shutdown(fixture.service, fixture.handle);
	assert(shutdown_ok, "\e[91mThe reserved shutdown slot was unavailable at full capacity.\e[0m");
	repeat_ok, _, repeat_error := Service.request_shutdown(fixture.service, fixture.handle);
	assert(!repeat_ok && repeat_error.admission.limit == .LIVE_HANDLES);

	_, ticket_observation := Service.poll(fixture.service, ticket);
	assert(ticket_observation.update.kind == .CANCELLED && ticket_observation.update.cancellation == .SHUTDOWN);
	submit_ok, _, closed := Service.submit_source_batch(fixture.service, fixture.handle, batch);
	assert(!submit_ok && closed.code == .SERVICE_CLOSED);

	// A deadline does not stop a producer that has not returned.
	deadline := Service.Deadline.{clock_identity = fixture.service.clock_identity, nanoseconds = 1000};
	_, waited := Service.wait(fixture.service, shutdown, deadline);
	assert(waited.timed_out && waited.observation.phase == .DRAINING && fixture.session.now == 1000);
	foreign_ok := Service.wait(fixture.service, shutdown, .{clock_identity = xx "other-clock", nanoseconds = 2000});
	assert(!foreign_ok, "\e[91mA foreign clock was accepted.\e[0m");

	assert(Service.executor_deliver(fixture.session, running) == .DISCARDED);
	_, stopped := Service.poll(fixture.service, shutdown);
	assert(stopped.kind == .SHUTDOWN);

	release(*fixture, shutdown);
	release(*fixture, observed.waiter);
	release(*fixture, ticket);
	close(*fixture);
	print("Shutdown and limits \e[92mPASS\e[0m\n");
}

// Each fault removes one safeguard, and the scenario guarding it must notice before releasing its owners.
test_negative_controls :: () {
	late_delivery :: (faults: Service.Test_Faults) -> Service.Delivery {
		fixture := open();
		fixture.session.faults = faults;
		ticket := set_text(*fixture, "main", "b :: 1;");
		Service.executor_run(fixture.session);
		world := world_of(*fixture, ticket);
		started := query(*fixture, world, "main", .SYNTAX_DIAGNOSTICS);
		running := Service.executor_dispatch(fixture.session);
		successor := set_text(*fixture, "main", "c :: 1;");
		delivery := Service.executor_deliver(fixture.session, running);
		release(*fixture, started.waiter);
		release(*fixture, world);
		release(*fixture, ticket);
		release(*fixture, successor);
		close(*fixture);
		return delivery;
	}

	// Either the stop request or the publication frontier check alone keeps a late obsolete result out.
	assert(late_delivery(.{skip_running_stop = true, keep_unconsumed_work = true}) == .DISCARDED, "\e[91mThe publication frontier check alone let a late result through.\e[0m");
	assert(late_delivery(.{skip_publication_frontier_check = true, keep_unconsumed_work = true}) == .DISCARDED, "\e[91mThe stop request alone let a late result through.\e[0m");
	assert(late_delivery(.{skip_running_stop = true, skip_publication_frontier_check = true}) == .DISCARDED, "\e[91mUnconsumed output was retained.\e[0m");
	all_disabled := late_delivery(.{
		skip_running_stop = true,
		skip_publication_frontier_check = true,
		keep_unconsumed_work = true,
	});
	assert(all_disabled == .PUBLISHED, "\e[91mControl undetected: a late obsolete result was not published without its safeguards.\e[0m");

	unconsumed := open();
	unconsumed.session.faults.keep_unconsumed_work = true;
	ticket := set_text(*unconsumed, "main", "a :: 1;");
	Service.executor_run(unconsumed.session);
	world := world_of(*unconsumed, ticket);
	lone := query(*unconsumed, world, "main", .SYNTAX_DIAGNOSTICS);
	release(*unconsumed, lone.waiter);
	assert(unconsumed.session.ready.count == 1, "\e[91mControl undetected: queued work was removed without the last-consumer rule.\e[0m");
	release(*unconsumed, world);
	release(*unconsumed, ticket);
	close(*unconsumed);

	// The session, the reserved shutdown slot and one ticket fill three handles.
	limited := options();
	limited.requested_limits.values[Service.Limit_Name.LIVE_HANDLES] = 3;
	full := open(limited);
	full.session.faults.shutdown_from_ordinary_capacity = true;
	full_ticket := set_text(*full, "main", "a :: 1;");
	shutdown_ok := Service.request_shutdown(full.service, full.handle);
	assert(!shutdown_ok, "\e[91mControl undetected: shutdown from ordinary capacity succeeded at full capacity.\e[0m");
	full.session.faults.shutdown_from_ordinary_capacity = false;
	release(*full, full_ticket);
	close(*full);
	print("Negative controls \e[92mPASS\e[0m\n");
}
