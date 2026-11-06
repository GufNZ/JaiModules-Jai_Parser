// The fifteen `jai-cache-interface/1` operations share a pinned session gate; worker computation and recursive cleanup run outside it.

Lifecycle :: enum u8 {
	OPEN;
	QUIESCING;
	DRAINING;
	STOPPED;
}

Query_Kind :: enum u8 {
	SYNTAX_SNAPSHOT;
	SYNTAX_DIAGNOSTICS;
	SYNTAX_DECLARATION_INDEX;
	SEMANTIC_QUERY;
	COMPILER_EVALUATION;
}

Cancellation_Reason :: enum u8 {
	CALLER;
	WORLD_SUPERSEDED;
	SHUTDOWN;
	PRESSURE;
}

Failure :: struct {
	stage: enum u8 {
		ADMISSION;
		PROVIDER;
		PARSER;
		CONVERSION;
		PUBLICATION;
		SERVICE;
	};
	code: enum u8 {
		IO;
		PERMISSION;
		REVISION_UNAVAILABLE;
		INVALID_EVIDENCE;
		INVALID_REFERENCE;
		INVALID_TEXT;
		RESOURCE_LIMIT;
		INTERNAL;
	};
}

Ticket_Terminal :: struct {
	kind: enum u8 {
		PUBLISHED;
		SUPERSEDED;
		CANCELLED;
		FAILED;
	};
	world_identity: World_ID;
	// Empty means null.
	successor: Operation_ID;
	cancellation: Cancellation_Reason;
	failure: Failure;
}

Query_Terminal :: struct {
	kind: enum u8 {
		AVAILABLE;
		UNAVAILABLE;
		UNSUPPORTED;
		CANCELLED;
		FAILED;
	};
	result_identity: Result_ID;
	unavailable: Unavailable_Reason;
	unsupported: Query_Kind;
	cancellation: Cancellation_Reason;
	failure: Failure;
}

Pending_Phase :: enum u8 {
	QUEUED;
	RUNNING;
	QUIESCING;
	DRAINING;
}

// Flattened `Observation`: only the fields of the arm selected by `kind` are meaningful.
// Identity bytes are immutable session-owned values that outlive every registration that can observe them.
Observation :: struct {
	kind: enum u8 {
		UPDATE;
		QUERY;
		SHUTDOWN;
		PENDING;
	};
	operation_identity: Operation_ID;
	provider_frontier: [] u8;
	documents: [] [] u8;
	update: Ticket_Terminal;
	world_identity: World_ID;
	document: [] u8;
	context_identity: [] u8;
	query_kind: Query_Kind;
	query: Query_Terminal;
	phase: Pending_Phase;
}

is_terminal :: (observation: Observation) -> bool {
	return observation.kind != .PENDING;
}

Session_Options :: struct {
	version: string;
	workspace: [] u8;
	provider_namespace: [] u8;
	host_authority: [] u8;
	provider_capabilities: Provider_Adapter_Descriptor;
	supported_tuples: [] Schema_Tuple;
	contexts: [] Context_Registration;
	requested_limits: Limit_Request;
}

Tracked_Document :: struct {
	document: [] u8;
	provider_revision: [] u8;
	binding: Document_Binding;
	disk_kind: type_of(Disk_State.kind);
	disk_source_revision: [] u8;
	disk_context: [] u8;
	has_overlay: bool;
	overlay_installation_revision: [] u8;
	overlay_source_revision: [] u8;
	overlay_context: [] u8;
	overlay_origin: Overlay_Origin;
	selection: type_of(Selected_Document.selection);
}

Store_Mode :: enum u8 {
	ENABLED;
	DISABLED;
	DEGRADED;
}

Session_Description :: struct {
	session_identity: Session_ID;
	workspace: [] u8;
	provider_namespace: [] u8;
	lifecycle: Lifecycle;
	accepted_frontier: [] u8;
	tracked_document_states: [] Tracked_Document;
	clock_identity: [] u8;
	effective_limits: Limits;
	// No store binding exists before phase 6.
	store_mode: Store_Mode;
}

Opened :: struct {
	session: Handle(.SESSION);
	description: Session_Description;
}

Accepted :: struct {
	ticket: Handle(.TICKET);
	frontier: [] u8;
}

Analysis_Request :: struct {
	version: string;
	expected_frontier: [] u8;
	documents: [] [] u8;
}

Ticket_Observation :: struct {
	terminal: bool;
	observation: Observation;
	waiter: Handle(.WAITER);
}

World_Selector :: struct {
	kind: enum u8 {
		PUBLISHED_UPDATE;
		HEAD;
	};
	// `.PUBLISHED_UPDATE`: an update ticket, or an update waiter when `use_waiter` is set.
	ticket: Handle(.TICKET);
	waiter: Handle(.WAITER);
	use_waiter: bool;
	// `.HEAD`.
	session: Handle(.SESSION);
	workspace: [] u8;
	expected_frontier: [] u8;
}

World_Acquisition :: struct {
	kind: enum u8 {
		ACQUIRED;
		PENDING;
		UNAVAILABLE;
	};
	world: Handle(.WORLD);
	operation_identity: Operation_ID;
	unavailable: enum u8 {
		NO_HEAD;
		FRONTIER_MISMATCH;
		UPDATE_TERMINAL;
	};
	published_frontier: [] u8;
	observation: Observation;
}

Query_Request :: struct {
	version: string;
	world: Handle(.WORLD);
	document: [] u8;
	kind: Query_Kind;
}

Query_Start :: struct {
	kind: enum u8 {
		AVAILABLE;
		PENDING;
		TERMINAL;
	};
	result: Handle(.RESULT);
	waiter: Handle(.WAITER);
	observation: Observation;
}

Deadline :: struct {
	clock_identity: [] u8;
	nanoseconds: u64;
}

Wait_Observation :: struct {
	timed_out: bool;
	observation: Observation;
}

Result_Acquisition :: struct {
	kind: enum u8 {
		ACQUIRED;
		PENDING;
		TERMINAL;
	};
	result: Handle(.RESULT);
	observation: Observation;
}

Cancel_Outcome :: struct {
	already_terminal: bool;
	observation: Observation;
}

Completion_Record :: struct {
	registration: Handle(.WAITER);
	observation: Observation;
}

Diagnostics_Status :: struct {
	parse_status: Parse_Status_Observation;
	error_count: u64;
	warning_count: u64;
}

Member_State :: enum u8 {
	PRESENT;
	ABSENT;
	UNKNOWN;
	UNAVAILABLE;
}

Selected_Member :: struct {
	document: [] u8;
	provider_revision: [] u8;
	context_identity: [] u8;
	state: Member_State;
	source: *Source_Backing;
	filename: string;
}

Member_Syntax :: struct {
	owner: *Owned_Syntax;
	snapshot: *Syntax_Snapshot;
	index: *Declaration_Index;
	status: Diagnostics_Status;
	// Filled by the first published diagnostics query task.
	diagnostics: *Diagnostics_Projection;
}

World :: struct {
	identity: World_ID;
	frontier: [] u8;
	capture_key: [] u8;
	// Canonical `DocumentID` order.
	members: [] Selected_Member;
	syntax: [] Member_Syntax;
	// Coherent only when every member is a disk observation under one attested capture token.
	consistency: Consistency;
	state: enum u8 {
		PENDING;
		PUBLISHED;
		FAILED;
		CANCELLED;
	};
	references: s64;
}

Query_Result :: struct {
	identity: Result_ID;
	world: *World;
	member: s64;
	kind: Query_Kind;
	references: s64;
}

Result_Description :: struct {
	result_identity: Result_ID;
	world_identity: World_ID;
	document: [] u8;
	source_revision: [] u8;
	context_identity: [] u8;
	kind: Query_Kind;
	diagnostics_status: Diagnostics_Status;
	// The protected syntax backing every query kind's references resolve against.
	backing: *Syntax_Snapshot;
	snapshot: *Syntax_Snapshot;
	diagnostics: *Diagnostics_Projection;
	index: *Declaration_Index;
}

Operation :: struct {
	identity: Operation_ID;
	kind: enum u8 {
		UPDATE;
		QUERY;
		SHUTDOWN;
	};
	terminal: bool;
	// `.UPDATE`.
	frontier: [] u8;
	documents: [] [] u8;
	update: Ticket_Terminal;
	// `.UPDATE` candidate or `.QUERY` world; held until the operation is reaped.
	world: *World;
	// `.QUERY`.
	member: s64;
	query_kind: Query_Kind;
	query: Query_Terminal;
	result: *Query_Result;
	task: *Task;
	registrations: s64;
	waiters: [..] Slot_Reference;
}

Task :: struct {
	optional: bool;
	kind: enum u8 {
		PARSE_INDEX;
		QUERY_PAYLOAD;
	};
	key: [] u8;
	world: *World;
	member: s64;
	phase: enum u8 {
		READY;
		RUNNING;
		STOP_REQUESTED;
		TERMINAL;
	};
	attempt: u64;
	operations: [..] *Operation;
}

// One per dispatch; the producer fills it once and the coordinator consumes it once.
Mailbox :: struct {
	session: *Session;
	task: *Task;
	attempt: u64;
	consumed: bool;
	ok: bool;
	failure: Failure;
	syntax: [] Member_Syntax;
	diagnostics: *Diagnostics_Projection;
}

Slot_Reference :: struct {
	slot: u64;
	generation: u64;
}

Registration :: struct {
	kind: Handle_Kind;
	operation: *Operation;
	world: *World;
	result: *Query_Result;
	// `.WAITER`: its own terminal observation, which caller cancellation can decide independently of the operation.
	terminal: bool;
	observation: Observation;
	delivered: bool;
}

Retired_Output :: struct {
	syntax: [] Member_Syntax;
	diagnostics: *Diagnostics_Projection;
}

Session :: struct {
	service: *Service;
	heap: Owned_Heap;
	gate: Mutex;
	changed: Condition_Variable;
	compute: Thread;
	reaper: Thread;
	threaded: bool;
	worker_joined: bool;
	call_pins: s64;
	active_admissions: s64;
	cleanup_pins: s64;
	retiring: bool;
	directory_retiring: bool;
	identities: Session_Identities;
	workspace: [] u8;
	lifecycle: Lifecycle;
	provider: *Provider_Model;
	ledger: Resource_Ledger;
	registry: Handle_Registry;
	registrations: [..] *Registration;
	operations: [..] *Operation;
	worlds: [..] *World;
	tasks: [..] *Task;
	ready: [..] *Task;
	optional_ready: [..] *Task;
	mailboxes: [..] *Mailbox;
	retired_worlds: [..] *World;
	retired_outputs: [..] Retired_Output;
	retired_sources: [..] *Source_Backing;
	completions: [..] Slot_Reference;
	head: *World;
	head_target: *World;
	shutdown: *Operation;
	shutdown_control: *Operation;
	session_released: bool;
	// Deterministic monotonic clock, advanced only by `wait`.
	now: u64;
	#if TEST_HOOKS {
		faults: Test_Faults;
		pauses: [#run enum_names(Test_Boundary).count] Test_Pause;
	}
}

Service :: struct {
	directory: Mutex;
	clock_base: Apollo_Time;
	allocator: Allocator;
	#if TEST_HOOKS {
		owned_allocations: s64;
		owned_bytes: s64;
	}
	incarnation: Service_Incarnation;
	clock_identity: [] u8;
	ceilings: Limits;
	minima: Limits;
	sessions: [..] *Session;
}

// `epoch` must come from the trusted issuer (phase 2 `reserve_epoch`).
open_service :: (authority_namespace: [] u8, epoch: u64, ceilings: Limits, minima: Limits) -> *Service {
	service := New(Service);
	service.allocator = context.default_allocator;
	#if TEST_HOOKS {
		if service_test_allocator.proc {
			service.allocator = service_test_allocator;
		}
	}
	init(*service.directory);
	service.clock_base = current_time_monotonic();
	service.incarnation = make_service_incarnation(authority_namespace, epoch);
	service.clock_identity = clock_identity(service.incarnation);
	service.ceilings = ceilings;
	service.minima = minima;
	return service;
}

open_session :: (service: *Service, options: Session_Options) -> bool, Opened, Operation_Error {
	if options.version != INTERFACE_VERSION {
		return false, .{}, .{code = .INVALID_VERSION};
	}


	if !options.workspace.count || !options.provider_namespace.count || !options.host_authority.count {
		return false, .{}, invalid(.MISSING, ifx !options.workspace.count
			then "workspace"
			else ifx !options.provider_namespace.count
				then "provider_namespace"
				else "host_authority"
		);
	}


	if validate_provider_descriptor(options.provider_capabilities) != .NONE {
		return false, .{}, capability(SOURCE_PROVIDER_SCHEMA);
	}


	// Only the implemented tuple is admitted; there is no fallback to a neighbouring schema.
	tuples_ok := configuration_id(options.supported_tuples);
	for options.supported_tuples {
		tuples_ok &&= it == IMPLEMENTED_SCHEMA_TUPLE;
	}

	if !tuples_ok {
		return false, .{}, capability(SYNTAX_CONTEXT_SCHEMA);
	}


	limit_failure, limits, limit_name := negotiate_limits(options.requested_limits, service.ceilings, service.minima);
	if limit_failure == .INVALID_ARGUMENT {
		return false, .{}, invalid(.OUT_OF_RANGE, "requested_limits");
	}


	if limit_failure == .LIMIT {
		return false, .{}, limit(limit_name);
	}


	lock(*service.directory);
	identities_ok, identities := issue_session(*service.incarnation);
	owner_token := service.incarnation.session_counter.next - 1;
	unlock(*service.directory);
	if !identities_ok {
		return false, .{}, .{code = .ADMISSION_DENIED, admission = .{kind = .RESOURCE_EXHAUSTED}};
	}


	session := New(Session,, service.allocator);
	#if TEST_HOOKS {
		atomic_add(*service.owned_allocations, 1);
		atomic_add(*service.owned_bytes, size_of(Session));
	}
	session.heap.service = service;
	session.heap.delegate = service.allocator;
	init(*session.heap.gate);
	use_owner_memory(session);
	init(*session.gate);
	init(*session.changed);
	#if TEST_HOOKS {
		for * session.pauses {
			init(*it.arrived);
			init(*it.proceed);
		}
	}
	session.service = service;
	session.identities = identities;
	session.identities.session = xx array_copy(identities.session.([] u8));
	free(identities.session.data,, output_allocator());
	session.workspace = array_copy(options.workspace);
	session.ledger.limits = limits;
	session.registry.session = session.identities.session;
	session.registry.owner_service = service;
	session.registry.owner_token = owner_token;
	session.provider = open_provider_model(options.provider_capabilities, options.provider_namespace, session.identities.session, options.host_authority, limits);
	contexts_ok, context_error := register_contexts(session.provider, options.contexts);
	if !contexts_ok {
		destroy_session(session);
		return false, .{}, context_error;
	}


	// The `.SESSION` slot, the first `.SHUTDOWN` slot and the shutdown operation are reserved before anything else can use them.
	if !reserve(*session.ledger, .{.LIVE_HANDLES, 2}, .{.IN_FLIGHT_OPERATIONS, 1}) {
		destroy_session(session);
		return false, .{}, limit(ifx limits.values[Limit_Name.LIVE_HANDLES] < 2 then .LIVE_HANDLES else .IN_FLIGHT_OPERATIONS);
	}


	commit_reserved(*session.ledger, .LIVE_HANDLES, 1);
	session.shutdown_control = New(Operation);
	handle := register(session, .SESSION, .{});
	if !start_workers(session) {
		session.registrations[handle.slot].* = .{};
		release_handle(*session.registry, handle);
		destroy_session(session);
		return false, .{}, .{code = .ADMISSION_DENIED, admission = .{kind = .RESOURCE_EXHAUSTED}};
	}


	lock(*service.directory);
	array_add(*service.sessions, session);
	unlock(*service.directory);
	return true, .{session = handle, description = describe(session)}, .{};
}

describe_session :: (service: *Service, handle: Handle(.SESSION)) -> bool, Session_Description, Operation_Error {
	call := enter_call(service, handle);
	defer leave_call(call);

	session := validate_session(call, handle);
	if !session {
		return false, .{}, stale(.SESSION);
	}


	use_owner_memory(session);

	return true, describe(session), .{};
}

submit_source_batch :: (service: *Service, handle: Handle(.SESSION), batch: Source_Batch) -> bool, Accepted, Operation_Error {
	call := enter_call(service, handle);
	defer leave_call(call);

	session := validate_session(call, handle);
	if !session {
		return false, .{}, stale(.SESSION);
	}

	use_owner_memory(session);


	if session.lifecycle != .OPEN {
		return false, .{}, .{code = .SERVICE_CLOSED};
	}


	taken, missing := take(session, .LIVE_HANDLES, .IN_FLIGHT_OPERATIONS, .CONCURRENT_ACQUISITIONS);
	if !taken {
		return false, .{}, limit(missing);
	}


	staged := stage_provider_copy(session.provider);
	session.active_admissions += 1;
	unlock(*session.gate);
	#if TEST_HOOKS {
		worker_pause(session, .SOURCE_STAGING);
	}

	ok, frontier, error := apply_source_batch(staged, batch);
	lock(*session.gate);
	defer {
		unlock(*session.gate);
		release_provider_copy(staged);
		lock(*session.gate);
		session.active_admissions -= 1;
		give(session, .CONCURRENT_ACQUISITIONS);
		wake_all(*session.changed);
	}

	if session.lifecycle != .OPEN {
		give(session, .LIVE_HANDLES, .IN_FLIGHT_OPERATIONS);
		return false, .{}, .{code = .SERVICE_CLOSED};
	}


	if !bytes_equal(batch.expected_frontier, session.provider.accepted_frontier) {
		give(session, .LIVE_HANDLES, .IN_FLIGHT_OPERATIONS);
		return false, .{}, .{code = .BASE_MISMATCH, scope = .FRONTIER};
	}


	if !ok {
		give(session, .LIVE_HANDLES, .IN_FLIGHT_OPERATIONS);
		return false, .{}, error;
	}


	commit_provider_copy(session.provider, staged);

	documents := NewArray(batch.events.count, [] u8);
	for batch.events {
		documents[it_index] = accepted_document(session, it.document);
	}

	sort_canonical(documents);
	operation := new_update_operation(session, frontier, documents);
	supersede_obsolete(session);
	start_candidate(session, operation);
	ticket := register(session, .TICKET, .{operation = operation});
	operation.registrations += 1;
	return true, .{ticket = ticket, frontier = array_copy(frontier,, output_allocator())}, .{};
}

request_analysis :: (service: *Service, handle: Handle(.SESSION), request: Analysis_Request) -> bool, Accepted, Operation_Error {
	call := enter_call(service, handle);
	defer leave_call(call);
	session := validate_session(call, handle);
	if !session {
		return false, .{}, stale(.SESSION);
	}


	use_owner_memory(session);

	if request.version != INTERFACE_VERSION {
		return false, .{}, .{code = .INVALID_VERSION};
	}


	if session.lifecycle != .OPEN {
		return false, .{}, .{code = .SERVICE_CLOSED};
	}


	if !bytes_equal(request.expected_frontier, session.provider.accepted_frontier) {
		return false, .{}, .{code = .BASE_MISMATCH, scope = .FRONTIER};
	}


	if !request.documents.count {
		return false, .{}, invalid(.MISSING, "documents");
	}


	if !within_limit(session.ledger.limits, .CAPTURE_DOCUMENTS, request.documents.count) {
		return false, .{}, limit(.CAPTURE_DOCUMENTS);
	}


	documents := NewArray(request.documents.count, [] u8);
	for request.documents {
		state := find_document(session.provider, it);
		if !state {
			return false, .{}, invalid_element(.INCONSISTENT_BINDING, "documents", it_index);
		}


		for 0..it_index - 1 {
			if bytes_equal(request.documents[it], state.document) {
				return false, .{}, invalid_element(.DUPLICATE, "documents", it_index);
			}
		}

		documents[it_index] = state.document;
	}


	taken, missing := take(session, .LIVE_HANDLES, .IN_FLIGHT_OPERATIONS);
	if !taken {
		return false, .{}, limit(missing);
	}


	sort_canonical(documents);
	operation := new_update_operation(session, session.provider.accepted_frontier, documents);
	start_candidate(session, operation);
	ticket := register(session, .TICKET, .{operation = operation});
	operation.registrations += 1;
	return true, .{ticket = ticket, frontier = array_copy(operation.frontier,, output_allocator())}, .{};
}

observe_ticket :: (service: *Service, handle: Handle(.TICKET)) -> bool, Ticket_Observation, Operation_Error {
	call := enter_call(service, handle);
	defer leave_call(call);

	session, registration := lookup_pinned(call, handle);
	if !session {
		return false, .{}, stale(.TICKET);
	}


	use_owner_memory(session);

	operation := registration.operation;
	if operation.terminal {
		return true, .{terminal = true, observation = copy_observation(update_observation(operation))}, .{};
	}


	if session.lifecycle != .OPEN {
		return false, .{}, .{code = .SERVICE_CLOSED};
	}


	waiter, error := new_waiter(session, operation);
	if !waiter.generation {
		return false, .{}, error;
	}


	return true, .{waiter = waiter}, .{};
}

acquire_world :: (service: *Service, selector: World_Selector) -> bool, World_Acquisition, Operation_Error {
	owner_service := ifx selector.kind == .HEAD
		then selector.session.owner_service
		else ifx selector.use_waiter
			then selector.waiter.owner_service
			else selector.ticket.owner_service;
	owner_token := ifx selector.kind == .HEAD
		then selector.session.owner_token
		else ifx selector.use_waiter
			then selector.waiter.owner_token
			else selector.ticket.owner_token;
	call := enter_owner(service, owner_service, owner_token);
	defer leave_call(call);

	if !call {
		return
			false,
			.{},
			stale(
				ifx selector.kind == .HEAD
					then .SESSION
					else ifx selector.use_waiter
						then .WAITER
						else .TICKET
			);
	}


	use_owner_memory(call);

	if selector.kind == .HEAD {
		session := validate_session(call, selector.session);
		if !session {
			return false, .{}, stale(.SESSION);
		}


		if !bytes_equal(selector.workspace, session.workspace) {
			return false, .{}, invalid(.INCONSISTENT_BINDING, "workspace");
		}


		head := session.head;
		if head && bytes_equal(head.frontier, selector.expected_frontier) {
			ok, acquisition, error := acquire_world_handle(session, head);
			return ok, acquisition, error;
		}


		for session.operations {
			if it.kind == .UPDATE && !it.terminal && bytes_equal(it.frontier, selector.expected_frontier) {
				return true, .{kind = .PENDING, operation_identity = xx array_copy(it.identity.([] u8))}, .{};
			}
		}


		if head {
			return true, .{kind = .UNAVAILABLE, unavailable = .FRONTIER_MISMATCH, published_frontier = array_copy(head.frontier)}, .{};
		}


		return true, .{kind = .UNAVAILABLE, unavailable = .NO_HEAD}, .{};
	}


	session: *Session;
	registration: *Registration;
	observation: Observation;
	if selector.use_waiter {
		session, registration = lookup_pinned(call, selector.waiter);
		if !session || registration.operation.kind != .UPDATE {
			return false, .{}, stale(.WAITER);
		}


		observation = waiter_observation(session, registration);
	} else {
		session, registration = lookup_pinned(call, selector.ticket);
		if !session {
			return false, .{}, stale(.TICKET);
		}


		observation = ifx registration.operation.terminal
			then update_observation(registration.operation)
			else pending_observation(registration.operation);
	}


	operation := registration.operation;
	if observation.kind == .PENDING {
		return true, .{kind = .PENDING, operation_identity = xx array_copy(operation.identity.([] u8))}, .{};
	}


	if observation.update.kind != .PUBLISHED {
		return true, .{kind = .UNAVAILABLE, unavailable = .UPDATE_TERMINAL, observation = copy_observation(observation)}, .{};
	}


	ok, acquisition, error := acquire_world_handle(session, operation.world);
	return ok, acquisition, error;
}

query :: (service: *Service, request: Query_Request) -> bool, Query_Start, Operation_Error {
	if request.version != INTERFACE_VERSION {
		return false, .{}, .{code = .INVALID_VERSION};
	}


	call := enter_call(service, request.world);
	defer leave_call(call);

	session, registration := lookup_pinned(call, request.world);
	if !session {
		return false, .{}, stale(.WORLD);
	}


	use_owner_memory(session);

	if session.lifecycle != .OPEN {
		return false, .{}, .{code = .SERVICE_CLOSED};
	}


	world := registration.world;
	member := -1;
	for world.members {
		if bytes_equal(it.document, request.document) {
			member = it_index;
		}
	}

	// Every query gets its own operation identity, even when it is answered at once or shares a task.
	ok, identity := issue_operation(*session.identities);
	if !ok {
		return false, .{}, .{code = .ADMISSION_DENIED, admission = .{kind = .RESOURCE_EXHAUSTED}};
	}


	// A document this world never captured is unavailable, never read from current source.
	if member < 0 {
		uncaptured := Observation.{
			kind = .QUERY,
			operation_identity = identity,
			world_identity = world.identity,
			document = request.document,
			query_kind = request.kind,
			query = .{kind = .UNAVAILABLE, unavailable = .NOT_CAPTURED},
		};
		return true, .{kind = .TERMINAL, observation = copy_observation(uncaptured)}, .{};
	}


	terminal := Query_Terminal.{kind = .UNSUPPORTED};
	immediate := query_observation(identity, world, member, request.kind, terminal);
	if request.kind == .SEMANTIC_QUERY || request.kind == .COMPILER_EVALUATION {
		immediate.query.unsupported = request.kind;
		return true, .{kind = .TERMINAL, observation = copy_observation(immediate)}, .{};
	}


	if world.members[member].state != .PRESENT {
		immediate.query = .{kind = .UNAVAILABLE, unavailable = .SOURCE_ABSENT};
		return true, .{kind = .TERMINAL, observation = copy_observation(immediate)}, .{};
	}


	if request.kind != .SYNTAX_DIAGNOSTICS || world.syntax[member].diagnostics {
		taken := take(session, .LIVE_HANDLES);
		if !taken {
			return false, .{}, limit(.LIVE_HANDLES);
		}


		result := new_result(session, world, member, request.kind);
		result.references += 1;
		return true, .{kind = .AVAILABLE, result = register(session, .RESULT, .{result = result})}, .{};
	}


	// An obsolete world can still serve published results but never starts fresh work.
	if !bytes_equal(world.frontier, session.provider.accepted_frontier) {
		immediate.query = .{kind = .CANCELLED, cancellation = .WORLD_SUPERSEDED};
		return true, .{kind = .TERMINAL, observation = copy_observation(immediate)}, .{};
	}


	taken, missing := take(session, .IN_FLIGHT_OPERATIONS);
	if !taken {
		return false, .{}, limit(missing);
	}


	operation := New(Operation);
	operation.identity = identity;
	operation.kind = .QUERY;
	operation.world = world;
	operation.member = member;
	operation.query_kind = request.kind;
	world.references += 1;
	waiter, error := new_waiter(session, operation);
	if !waiter.generation {
		world.references -= 1;
		free(operation);
		give(session, .IN_FLIGHT_OPERATIONS);
		return false, .{}, error;
	}


	array_add(*session.operations, operation);
	key := make_key("execution-task", session.identities.session.([] u8), world.identity.([] u8), xx "QUERY_PAYLOAD", world.members[member].document, xx "SYNTAX_DIAGNOSTICS");
	task: *Task;
	for session.tasks {
		if it.phase != .TERMINAL && bytes_equal(it.key, key) {
			task = it;
		}
	}

	if !task {
		task = New(Task);
		task.kind = .QUERY_PAYLOAD;
		task.key = key;
		task.world = world;
		task.member = member;
		task.attempt = 1;
		world.references += 1;
		array_add(*session.tasks, task);
		array_add(*session.ready, task);
	}

	array_add(*task.operations, operation);
	operation.task = task;
	return true, .{kind = .PENDING, waiter = waiter}, .{};
}

poll :: (service: *Service, handle: Handle($K)) -> bool, Observation, Operation_Error {
	#assert K == .TICKET || K == .WAITER || K == .SHUTDOWN;
	call := enter_call(service, handle);
	defer leave_call(call);

	ok, observation, error := poll_pinned(call, handle);
	return ok, observation, error;
}

#scope_module

poll_pinned :: (call: *Session, handle: Handle($K)) -> bool, Observation, Operation_Error {
	session, registration := lookup_pinned(call, handle);
	if !session {
		return false, .{}, stale(K);
	}


	#if K == .TICKET {
		operation := registration.operation;
		return true, copy_observation(ifx operation.terminal then update_observation(operation) else pending_observation(operation)), .{};
	} else #if K == .WAITER {
		return true, copy_observation(waiter_observation(session, registration)), .{};
	} else {
		return true, copy_observation(shutdown_observation(session)), .{};
	}
}

#scope_export

// Native waits release the state gate atomically; deterministic tests retain the stepped clock.
wait :: (service: *Service, handle: Handle($K), deadline: Deadline) -> bool, Wait_Observation, Operation_Error {
	#assert K == .TICKET || K == .WAITER || K == .SHUTDOWN;
	session := enter_call(service, handle);
	defer leave_call(session);

	if session && !bytes_equal(deadline.clock_identity, service.clock_identity) {
		return false, .{}, invalid(.INCONSISTENT_BINDING, "deadline", "clock_identity");
	}


	if !session {
		return false, .{}, stale(K);
	}


	use_owner_memory(session);

	ok, observation, error := poll_pinned(session, handle);
	while ok && !is_terminal(observation) {
		if session.threaded {
			#if TEST_HOOKS {
				if session.pauses[Test_Boundary.WAIT_ARMING].enabled {
					pause_locked(session, .WAIT_ARMING);
					free_observation(*observation,, output_allocator());
					ok, observation, error = poll_pinned(session, handle);
					continue;
				}
			}


			now := monotonic_now(service);
			if now >= deadline.nanoseconds {
				break;
			}


			wait_changed(session, deadline.nanoseconds - now);
		} else {
			if session.now >= deadline.nanoseconds {
				break;
			}


			mailbox := dispatch_task(session);
			if !mailbox {
				session.now = deadline.nanoseconds;
				break;
			}

			deliver_mailbox(session, mailbox);
		}

		free_observation(*observation,, output_allocator());
		ok, observation, error = poll_pinned(session, handle);
	}

	if !ok {
		return false, .{}, error;
	}


	return true, .{timed_out = !is_terminal(observation), observation = observation}, .{};
}

acquire_result :: (service: *Service, handle: Handle(.WAITER)) -> bool, Result_Acquisition, Operation_Error {
	call := enter_call(service, handle);
	defer leave_call(call);

	session, registration := lookup_pinned(call, handle);
	if !session || registration.operation.kind != .QUERY {
		return false, .{}, stale(.WAITER);
	}


	use_owner_memory(session);

	observation := waiter_observation(session, registration);
	if observation.kind == .PENDING {
		return true, .{kind = .PENDING, observation = copy_observation(observation)}, .{};
	}


	if observation.query.kind != .AVAILABLE {
		return true, .{kind = .TERMINAL, observation = copy_observation(observation)}, .{};
	}


	taken := take(session, .LIVE_HANDLES);
	if !taken {
		return false, .{}, limit(.LIVE_HANDLES);
	}


	result := registration.operation.result;
	result.references += 1;
	return true, .{kind = .ACQUIRED, result = register(session, .RESULT, .{result = result})}, .{};
}

cancel_waiter :: (service: *Service, handle: Handle(.WAITER)) -> bool, Cancel_Outcome, Operation_Error {
	call := enter_call(service, handle);
	defer leave_call(call);

	session, registration := lookup_pinned(call, handle);
	if !session {
		return false, .{}, stale(.WAITER);
	}


	use_owner_memory(session);

	if registration.terminal {
		return true, .{already_terminal = true, observation = copy_observation(registration.observation)}, .{};
	}


	operation := registration.operation;
	if operation.kind == .QUERY {
		finish_query(session, operation, .{kind = .CANCELLED, cancellation = .CALLER});
	} else {
		observation := pending_observation(operation);
		observation.kind = .UPDATE;
		observation.provider_frontier = operation.frontier;
		observation.documents = operation.documents;
		observation.update = .{kind = .CANCELLED, cancellation = .CALLER};
		resolve_waiter(session, operation, handle.slot, observation);
	}

	return true, .{observation = copy_observation(registration.observation)}, .{};
}

drain_completions :: (service: *Service, handle: Handle(.SESSION), maximum: u64) -> bool, [] Completion_Record, Operation_Error {
	call := enter_call(service, handle);
	defer leave_call(call);

	session := validate_session(call, handle);
	if !session {
		return false, .[], stale(.SESSION);
	}


	use_owner_memory(session);

	if maximum > xx session.ledger.limits.values[Limit_Name.ELEMENTS_PER_LIST] {
		return false, .[], invalid(.OUT_OF_RANGE, "maximum");
	}


	records: [..] Completion_Record;
	kept: [..] Slot_Reference;
	for session.completions {
		registration := live_registration(session, it);
		if !registration || registration.delivered {
			continue;
		}


		if records.count < xx maximum {
			array_add(
				*records,
				.{
					registration = .{
						session = session.identities.session,
						slot = it.slot,
						generation = it.generation,
						owner_service = service,
						owner_token = session.registry.owner_token
					},
					observation = copy_observation(registration.observation),
				}
				,, output_allocator()
			);
			registration.delivered = true;
			give(session, .COMPLETION_RECORDS);
		} else {
			array_add(*kept, it);
		}
	}

	array_free(session.completions);
	session.completions = kept;
	return true, records, .{};
}

retain :: (service: *Service, handle: Handle($K)) -> bool, Handle(K), Operation_Error {
	#assert K == .WORLD || K == .RESULT;
	call := enter_call(service, handle);
	defer leave_call(call);

	session, registration := lookup_pinned(call, handle);
	if !session {
		return false, .{}, stale(K);
	}


	use_owner_memory(session);

	if !take(session, .LIVE_HANDLES) {
		return false, .{}, limit(.LIVE_HANDLES);
	}


	#if K == .WORLD {
		registration.world.references += 1;
		return true, register(session, .WORLD, .{world = registration.world}), .{};
	} else {
		registration.result.references += 1;
		return true, register(session, .RESULT, .{result = registration.result}), .{};
	}
}

release :: (service: *Service, handle: Handle($K)) -> bool, Operation_Error {
	call := enter_call(service, handle);
	defer leave_call(call);

	session, registration := lookup_pinned(call, handle);
	if !session {
		return false, stale(K);
	}


	use_owner_memory(session);

	#if K == .SESSION {
		if session.lifecycle != .STOPPED {
			return false, .{code = .ACTIVE_SESSION};
		}


		session.session_released = true;
		if session.head {
			release_world(session, session.head);
			session.head = null;
		}

		for session.provider.documents {
			if it.disk.source {
				array_add(*session.retired_sources, it.disk.source);
				it.disk.source = null;
			}

			if it.has_overlay && it.overlay.source {
				array_add(*session.retired_sources, it.overlay.source);
				it.overlay.source = null;
				it.has_overlay = false;
			}
		}
	} else #if K == .WORLD {
		release_world(session, registration.world);
	} else #if K == .RESULT {
		release_result(session, registration.result);
	} else #if K == .TICKET {
		registration.operation.registrations -= 1;
		reap(session, registration.operation);
	} else #if K == .WAITER {
		operation := registration.operation;
		if !registration.terminal {
			// Releasing a pending waiter detaches its interest; a query waiter is its operation's only consumer.
			if operation.kind == .QUERY {
				finish_query(session, operation, .{kind = .CANCELLED, cancellation = .CALLER}, notify = false);
			} else {
				detach_waiter(session, operation, handle.slot);
				give(session, .PENDING_REGISTRATIONS);
			}
		}

		if !registration.delivered {
			give(session, .COMPLETION_RECORDS);
		}

		if registration.terminal {
			free_observation(*registration.observation);
		}

		operation.registrations -= 1;
		reap(session, operation);
	} else #if K == .SHUTDOWN {
		registration.operation.registrations -= 1;
	}

	registration.* = .{};
	release_handle(*session.registry, handle);
	give(session, .LIVE_HANDLES);
	maybe_destroy(session);
	return true, .{};
}

request_shutdown :: (service: *Service, handle: Handle(.SESSION)) -> bool, Handle(.SHUTDOWN), Operation_Error {
	call := enter_call(service, handle);
	defer leave_call(call);

	session := validate_session(call, handle);
	if !session {
		return false, .{}, stale(.SESSION);
	}


	use_owner_memory(session);

	if session.shutdown {
		if !take(session, .LIVE_HANDLES) {
			return false, .{}, limit(.LIVE_HANDLES);
		}


		session.shutdown.registrations += 1;
		return true, register(session, .SHUTDOWN, .{operation = session.shutdown}), .{};
	}


	// The first request uses the slot and operation reserved at open, so it succeeds even at full capacity.
	#if TEST_HOOKS {
		if session.faults.shutdown_from_ordinary_capacity && !take(session, .LIVE_HANDLES) {
			return false, .{}, limit(.LIVE_HANDLES);
		}
	}


	commit_reserved(*session.ledger, .LIVE_HANDLES, 1);
	_, identity := issue_operation(*session.identities);
	operation := session.shutdown_control;
	operation.identity = identity;
	operation.kind = .SHUTDOWN;
	operation.registrations = 1;
	session.shutdown = operation;
	shutdown_handle := register(session, .SHUTDOWN, .{operation = operation});

	session.lifecycle = .QUIESCING;
	for session.operations {
		if it.terminal {
			continue;
		}


		if it.kind == .UPDATE {
			finish_update(session, it, .{kind = .CANCELLED, cancellation = .SHUTDOWN});
		} else {
			finish_query(session, it, .{kind = .CANCELLED, cancellation = .SHUTDOWN});
		}
	}

	for session.tasks {
		stop_task(session, it);
	}

	session.lifecycle = .DRAINING;
	check_stopped(session);
	reap_all(session);
	return true, shutdown_handle, .{};
}

read_world :: (service: *Service, handle: Handle(.WORLD)) -> bool, *World, Operation_Error {
	call := enter_call(service, handle);
	defer leave_call(call);

	session, registration := lookup_pinned(call, handle);
	if !session {
		return false, null, stale(.WORLD);
	}


	return true, registration.world, .{};
}

read_result :: (service: *Service, handle: Handle(.RESULT)) -> bool, Result_Description, Operation_Error {
	call := enter_call(service, handle);
	defer leave_call(call);

	session, registration := lookup_pinned(call, handle);
	if !session {
		return false, .{}, stale(.RESULT);
	}


	result := registration.result;
	world := result.world;
	member := world.members[result.member];
	syntax := world.syntax[result.member];
	description := Result_Description.{
		result_identity = result.identity,
		world_identity = world.identity,
		document = member.document,
		source_revision = member.source.revision,
		context_identity = member.context_identity,
		kind = result.kind,
		diagnostics_status = syntax.status,
		backing = syntax.snapshot,
	};
	if result.kind == {
		case .SYNTAX_SNAPSHOT;
			description.snapshot = syntax.snapshot;

		case .SYNTAX_DIAGNOSTICS;
			description.diagnostics = syntax.diagnostics;

		case .SYNTAX_DECLARATION_INDEX;
			description.index = syntax.index;
	}

	return true, description, .{};
}

read_source :: (service: *Service, handle: Handle(.RESULT), start_byte: u64, end_byte: u64) -> bool, [] u8, Operation_Error {
	call := enter_call(service, handle);
	defer leave_call(call);

	session, registration := lookup_pinned(call, handle);
	if !session {
		return false, .[], stale(.RESULT);
	}


	bytes := registration.result.world.members[registration.result.member].source.bytes;
	if start_byte > end_byte || end_byte > xx bytes.count {
		return false, .[], invalid(.OUT_OF_RANGE, "end_byte");
	}


	return true, .{count = xx (end_byte - start_byte), data = bytes.data + start_byte}, .{};
}

// The three resolvers borrow from the result's protected syntax backing, whatever the query kind.
resolve_node :: (service: *Service, handle: Handle(.RESULT), node_id: u64) -> bool, *Node_Record, Operation_Error {
	ok, snapshot, error := result_snapshot(service, handle);
	if !ok || node_id >= xx snapshot.nodes.count {
		return false, null, ifx ok then invalid(.OUT_OF_RANGE, "node_id") else error;
	}


	return true, *snapshot.nodes[node_id], .{};
}

resolve_token :: (service: *Service, handle: Handle(.RESULT), token_id: u64) -> bool, *Token_Record, Operation_Error {
	ok, snapshot, error := result_snapshot(service, handle);
	if !ok || token_id >= xx snapshot.tokens.count {
		return false, null, ifx ok then invalid(.OUT_OF_RANGE, "token_id") else error;
	}


	return true, *snapshot.tokens[token_id], .{};
}

resolve_recovery :: (service: *Service, handle: Handle(.RESULT), recovery_id: u64) -> bool, *Recovery_Observation, Operation_Error {
	ok, snapshot, error := result_snapshot(service, handle);
	if !ok || recovery_id >= xx snapshot.recoveries.count {
		return false, null, ifx ok then invalid(.OUT_OF_RANGE, "recovery_id") else error;
	}


	return true, *snapshot.recoveries[recovery_id], .{};
}

// Releases an observation copy returned by this module; copies made under `,, temp` need no release.
free_observation :: (observation: *Observation) {
	free(observation.operation_identity.data);
	free(observation.provider_frontier.data);
	for observation.documents {
		free(it.data);
	}

	array_free(observation.documents);
	free(observation.update.world_identity.data);
	free(observation.update.successor.data);
	free(observation.world_identity.data);
	free(observation.document.data);
	free(observation.context_identity.data);
	free(observation.query.result_identity.data);
	observation.* = .{};
}

Delivery :: enum u8 {
	PUBLISHED;
	FAILED;
	DISCARDED;
	REJECTED;
}

// Compiled only for `TEST_HOOKS`: tests choose when the step executor dispatches and delivers, and may inspect session state.
#if TEST_HOOKS {
	Test_Boundary :: enum {
		CLEANUP;
		SOURCE_STAGING;
		SELECTED;
		PARSED;
		PUBLICATION;
		WAIT_ARMING;
	}

	Test_Pause :: struct {
		enabled: bool;
		arrived: Semaphore;
		proceed: Semaphore;
	}

	pause_locked :: (session: *Session, boundary: Test_Boundary) {
		pause := *session.pauses[boundary];
		if !pause.enabled {
			return;
		}


		pause.enabled = false;
		unlock(*session.gate);
		signal(*pause.arrived);
		wait_for(*pause.proceed);
		lock(*session.gate);
	}

	worker_pause :: (session: *Session, boundary: Test_Boundary) {
		if session.threaded {
			lock(*session.gate);
			pause_locked(session, boundary);
			unlock(*session.gate);
		}
	}

	arm_pause :: (session: *Session, boundary: Test_Boundary) {
		lock(*session.gate);
		session.pauses[boundary].enabled = true;
		unlock(*session.gate);
	}

	await_pause :: (session: *Session, boundary: Test_Boundary) -> bool {
		return wait_for(*session.pauses[boundary].arrived, 10_000) == .SUCCESS;
	}

	resume_pause :: (session: *Session, boundary: Test_Boundary) {
		signal(*session.pauses[boundary].proceed);
	}

	// Each switch removes one safeguard, so a test can show that its control detects the loss.
	Test_Faults :: struct {
		optional_first: bool;
		skip_running_stop: bool;
		skip_publication_frontier_check: bool;
		keep_unconsumed_work: bool;
		shutdown_from_ordinary_capacity: bool;
		// Fails conversion of this member in its candidate's parse task.
		fail_parse_document: [] u8;
	}

	session_of :: (service: *Service, handle: Handle(.SESSION)) -> *Session {
		call := enter_call(service, handle);
		defer leave_call(call);

		return validate_session(call, handle);
	}

	executor_dispatch :: (session: *Session) -> *Mailbox {
		push_allocator(owner_allocator(session));
		return dispatch_task(session);
	}

	executor_deliver :: (session: *Session, mailbox: *Mailbox) -> Delivery {
		push_allocator(owner_allocator(session));
		if session.threaded {
			lock(*session.gate);
		}

		delivery := deliver_mailbox(session, mailbox);
		if session.threaded {
			unlock(*session.gate);
		}

		cleanup_owned(session);
		return delivery;
	}

	last_mailbox :: (session: *Session) -> *Mailbox {
		lock(*session.gate);
		defer unlock(*session.gate);

		return session.mailboxes[session.mailboxes.count - 1];
	}

	// Dispatches and delivers until the required FIFO is empty; returns the number of tasks run.
	executor_run :: (session: *Session) -> s64 {
		push_allocator(owner_allocator(session));
		count := 0;
		mailbox := dispatch_task(session);
		while mailbox {
			deliver_mailbox(session, mailbox);
			count += 1;
			mailbox = dispatch_task(session);
		}

		cleanup_owned(session);
		return count;
	}
}

#scope_module

validate_session :: (call: *Session, handle: Handle(.SESSION)) -> *Session {
	session, registration := lookup_pinned(call, handle);
	return session;
}

// Runs the head of the required FIFO to completion into a fresh mailbox without publishing it.
dispatch_task :: (session: *Session) -> *Mailbox {
	mailbox := select_task(session);
	if mailbox {
		compute_task(session, mailbox);
	}

	return mailbox;
}

select_task :: (session: *Session) -> *Mailbox {
	if !session.ready.count && !session.optional_ready.count {
		return null;
	}


	required := !!session.ready.count;
	#if TEST_HOOKS {
		if session.faults.optional_first && session.optional_ready.count {
			required = false;
		}
	}

	queue := ifx required
		then *session.ready
		else *session.optional_ready;

	task := queue.*[0];
	array_ordered_remove_by_index(queue, 0);
	task.phase = .RUNNING;
	mailbox := New(Mailbox);
	mailbox.session = session;
	mailbox.task = task;
	mailbox.attempt = task.attempt;
	array_add(*session.mailboxes, mailbox);
	return mailbox;
}

compute_task :: (session: *Session, mailbox: *Mailbox) {
	task := mailbox.task;
	world := task.world;
	if task.kind == .PARSE_INDEX {
		mailbox.ok = true;
		mailbox.syntax = NewArray(world.members.count, Member_Syntax);
		for world.members {
			if stop_requested(session, task) {
				return;
			}


			if it.state != .PRESENT {
				continue;
			}


			syntax := *mailbox.syntax[it_index];
			syntax.owner = own_parse(xx it.source.bytes, it.filename);
			#if TEST_HOOKS {
				worker_pause(session, .PARSED);
			}

			if stop_requested(session, task) {
				return;
			}


			fault: Projection_Fault;
			fault, syntax.snapshot = project_snapshot(syntax.owner);
			if stop_requested(session, task) {
				return;
			}


			if fault.failure == .NONE {
				fault, syntax.index = project_declaration_index(syntax.snapshot);
			}

			#if TEST_HOOKS {
				if bytes_equal(it.document, session.faults.fail_parse_document) {
					fault.failure = .CONFLICTING_EVIDENCE;
				}
			}

			if fault.failure != .NONE {
				mailbox.ok = false;
				mailbox.failure = .{stage = .CONVERSION, code = ifx fault.failure == .INVALID_TEXT then .INVALID_TEXT else .INVALID_EVIDENCE};
				break;
			}


			syntax.status.parse_status = syntax.snapshot.parse_status;
			for diagnostic: syntax.snapshot.diagnostics {
				if diagnostic.severity == .ERROR {
					syntax.status.error_count += 1;
				} else {
					syntax.status.warning_count += 1;
				}
			}
		}
	} else {
		if stop_requested(session, task) {
			return;
		}


		fault: Projection_Fault;
		fault, mailbox.diagnostics = project_diagnostics(world.syntax[task.member].owner);
		mailbox.ok = fault.failure == .NONE;
		mailbox.failure = .{stage = .CONVERSION, code = ifx fault.failure == .INVALID_TEXT then .INVALID_TEXT else .INVALID_EVIDENCE};
	}

}

// Consumes a mailbox once; a duplicate or stale delivery is rejected without touching published state.
deliver_mailbox :: (session: *Session, mailbox: *Mailbox) -> Delivery {
	if mailbox.consumed {
		return .REJECTED;
	}


	mailbox.consumed = true;
	task := mailbox.task;
	world := task.world;
	if task.attempt != mailbox.attempt || (task.phase != .RUNNING && task.phase != .STOP_REQUESTED) {
		release_mailbox_output(mailbox);
		return .REJECTED;
	}


	stopped := task.phase == .STOP_REQUESTED || !bytes_equal(world.frontier, session.provider.accepted_frontier);
	#if TEST_HOOKS {
		if session.faults.skip_publication_frontier_check {
			stopped = task.phase == .STOP_REQUESTED;
		}
	}

	task.phase = .TERMINAL;
	defer {
		release_world(session, world);
		reap_all(session);
		check_stopped(session);
	}

	if stopped {
		release_mailbox_output(mailbox);
		return .DISCARDED;
	}


	if task.kind == .PARSE_INDEX {
		if !mailbox.ok {
			release_mailbox_output(mailbox);
			world.state = .FAILED;
			for task.operations {
				finish_update(session, it, .{kind = .FAILED, failure = mailbox.failure});
			}

			return .FAILED;
		}


		world.syntax = mailbox.syntax;
		mailbox.syntax = .[];
		world.state = .PUBLISHED;
		for task.operations {
			finish_update(session, it, .{kind = .PUBLISHED, world_identity = world.identity});
		}

		install_head(session, world);
		return .PUBLISHED;
	}


	if !mailbox.ok {
		release_mailbox_output(mailbox);
		for array_copy(task.operations,, temp) {
			finish_query(session, it, .{kind = .FAILED, failure = mailbox.failure});
		}

		return .FAILED;
	}


	unconsumed := !task.operations.count;
	#if TEST_HOOKS {
		unconsumed &&= !session.faults.keep_unconsumed_work;
	}

	if unconsumed {
		release_mailbox_output(mailbox);
		return .DISCARDED;
	}


	world.syntax[task.member].diagnostics = mailbox.diagnostics;
	mailbox.diagnostics = null;
	result := new_result(session, world, task.member, .SYNTAX_DIAGNOSTICS);
	for array_copy(task.operations,, temp) {
		if !it.terminal {
			it.result = result;
			result.references += 1;
			finish_query(session, it, .{kind = .AVAILABLE, result_identity = result.identity});
		}
	}

	if !result.references {
		result.references = 1;
		release_result(session, result);
	}

	return .PUBLISHED;
}

invalid :: (rule: Argument_Rule, names: .. string) -> Operation_Error {
	push_allocator(output_allocator());
	error := Operation_Error.{code = .INVALID_ARGUMENT, rule = rule};
	error.path = NewArray(names.count, Path_Step);
	for names {
		error.path[it_index] = .{kind = .FIELD, name = it};
	}

	return error;
}

// Caller-owned copy from the context allocator; the original keeps borrowing session-owned identities.
copy_observation :: (observation: Observation) -> Observation {
	push_allocator(output_allocator());
	return owned_observation(observation);
}

owned_observation :: (observation: Observation) -> Observation {
	result := observation;
	result.operation_identity = xx array_copy(observation.operation_identity.([] u8));
	result.provider_frontier = array_copy(observation.provider_frontier);
	result.documents = NewArray(observation.documents.count, [] u8);
	for observation.documents {
		result.documents[it_index] = array_copy(it);
	}

	result.update.world_identity = xx array_copy(observation.update.world_identity.([] u8));
	result.update.successor = xx array_copy(observation.update.successor.([] u8));
	result.world_identity = xx array_copy(observation.world_identity.([] u8));
	result.document = array_copy(observation.document);
	result.context_identity = array_copy(observation.context_identity);
	result.query.result_identity = xx array_copy(observation.query.result_identity.([] u8));
	return result;
}

result_snapshot :: (service: *Service, handle: Handle(.RESULT)) -> bool, *Syntax_Snapshot, Operation_Error {
	call := enter_call(service, handle);
	defer leave_call(call);

	session, registration := lookup_pinned(call, handle);
	if !session {
		return false, null, stale(.RESULT);
	}


	return true, registration.result.world.syntax[registration.result.member].snapshot, .{};
}

invalid_element :: (rule: Argument_Rule, name: string, index: s64) -> Operation_Error {
	push_allocator(output_allocator());
	error := Operation_Error.{code = .INVALID_ARGUMENT, rule = rule};
	error.path = NewArray(2, Path_Step);
	error.path[0] = .{kind = .FIELD, name = name};
	error.path[1] = .{kind = .ELEMENT, index = index};
	return error;
}

stale :: (kind: Handle_Kind) -> Operation_Error {
	return .{code = .INVALID_HANDLE, handle_kind = kind};
}

limit :: (name: Limit_Name) -> Operation_Error {
	return .{code = .ADMISSION_DENIED, admission = .{kind = .LIMIT, limit = name}};
}

capability :: (schema: string) -> Operation_Error {
	return .{code = .ADMISSION_DENIED, admission = .{kind = .CAPABILITY, schema = schema}};
}

// One unit of each name, all or nothing; reports the first name without room.
take :: (session: *Session, names: .. Limit_Name) -> bool, Limit_Name {
	amounts := NewArray(names.count, Ledger_Amount,, temp);
	for names {
		amounts[it_index] = .{name = it, amount = 1};
	}

	if !reserve(*session.ledger, ..amounts) {
		for names {
			if !reserve(*session.ledger, .{name = it, amount = 1}) {
				return false, it;
			}


			release_reserved(*session.ledger, it, 1);
		}

		return false, names[0];
	}


	for names {
		commit_reserved(*session.ledger, it, 1);
	}

	return true, .VALUE_BYTES;
}

give :: (session: *Session, names: .. Limit_Name) {
	for names {
		release_live(*session.ledger, it, 1);
	}
}

find_session :: (service: *Service, identity: Session_ID) -> *Session {
	for service.sessions {
		if bytes_equal(it.identities.session.([] u8), identity.([] u8)) {
			return it;
		}
	}


	return null;
}

lookup_pinned :: (session: *Session, handle: Handle($K)) -> *Session, *Registration {
	if !session || !handle_is_live(*session.registry, handle) {
		return null, null;
	}


	return session, session.registrations[handle.slot];
}

live_registration :: (session: *Session, reference: Slot_Reference) -> *Registration {
	if reference.slot >= xx session.registry.slots.count {
		return null;
	}


	slot := session.registry.slots[reference.slot];
	return ifx slot.live && slot.generation == reference.generation then session.registrations[reference.slot];
}

register :: (session: *Session, $kind: Handle_Kind, registration: Registration) -> Handle(kind) {
	ok, handle := register_handle(*session.registry, kind);
	assert(ok);
	while session.registrations.count <= xx handle.slot {
		array_add(*session.registrations, New(Registration));
	}

	session.registrations[handle.slot].* = registration;
	session.registrations[handle.slot].kind = kind;
	return handle;
}

describe :: (session: *Session) -> Session_Description {
	push_allocator(output_allocator());
	documents := tracked_documents(session.provider);
	tracked := NewArray(documents.count, Tracked_Document);
	for documents {
		selected := selected_document(it);
		tracked[it_index] = .{
			document = array_copy(it.document),
			provider_revision = array_copy(it.provider_revision),
			binding = .{
				document = array_copy(it.binding.document),
				absolute_path = .{encoding = it.binding.absolute_path.encoding, code_units = array_copy(it.binding.absolute_path.code_units)},
				provider_policy_version = it.binding.provider_policy_version,
			},
			disk_kind = it.disk.kind,
			disk_source_revision = array_copy(ifx it.disk.source then it.disk.source.revision),
			disk_context = array_copy(it.disk.syntax_context),
			has_overlay = it.has_overlay,
			overlay_installation_revision = array_copy(it.overlay.installation_revision),
			overlay_source_revision = array_copy(ifx it.has_overlay then it.overlay.source.revision),
			overlay_context = array_copy(it.overlay.syntax_context),
			overlay_origin = it.overlay.origin,
			selection = selected.selection,
		};
	}

	return .{
		session_identity = xx array_copy(session.identities.session.([] u8)),
		workspace = array_copy(session.workspace),
		provider_namespace = array_copy(session.provider.provider_namespace),
		lifecycle = session.lifecycle,
		accepted_frontier = array_copy(session.provider.accepted_frontier),
		tracked_document_states = tracked,
		clock_identity = array_copy(session.service.clock_identity),
		effective_limits = session.ledger.limits,
		store_mode = .DISABLED,
	};
}

// The session-owned copy of an accepted document identity.
accepted_document :: (session: *Session, document: [] u8) -> [] u8 {
	return find_document(session.provider, document).document;
}

sort_canonical :: (values: [] [] u8) {
	for i: 1..values.count - 1 {
		j := i;
		while j > 0 && compare_canonical(values[j - 1], values[j]) > 0 {
			values[j - 1], values[j] = values[j], values[j - 1];
			j -= 1;
		}
	}
}

new_update_operation :: (session: *Session, frontier: [] u8, documents: [] [] u8) -> *Operation {
	_, identity := issue_operation(*session.identities);
	operation := New(Operation);
	operation.identity = identity;
	operation.kind = .UPDATE;
	operation.frontier = frontier;
	operation.documents = documents;
	array_add(*session.operations, operation);
	return operation;
}

// Captures the selected state of `operation.documents`, joining an equal pending or published candidate, and makes it the head target.
start_candidate :: (session: *Session, operation: *Operation) {
	members := NewArray(operation.documents.count, Selected_Member);
	member_keys := NewArray(members.count, [] u8,, temp);
	capturable := true;
	coherent := true;
	capture: Consistency;
	for operation.documents {
		state := find_document(session.provider, it);
		selected := selected_document(state);
		coherent &&= selected.provenance && selected.provenance.consistency.kind == .COHERENT_CAPTURE;
		if coherent {
			coherent = !capture.capture_token.count || bytes_equal(capture.capture_token, selected.provenance.consistency.capture_token);
			capture = selected.provenance.consistency;
		}

		member := *members[it_index];
		member.document = state.document;
		member.provider_revision = state.provider_revision;
		member.context_identity = selected.syntax_context;
		member.state = xx selected.kind;
		member.source = selected.source;
		capturable &&= member.state == .PRESENT || member.state == .ABSENT;
		admitted := find_context(session.provider, selected.syntax_context);
		member.filename = path_spelling(admitted.paths.visible_filename);
		source_revision := ifx member.source then member.source.revision;
		member_keys[it_index] = make_key("member", member.document, member.provider_revision, member.context_identity, source_revision,, temp);
	}

	key := make_key("execution-capture", session.identities.session.([] u8), operation.frontier, make_key("members", ..member_keys,, temp), xx "SYNTAX_INDEX");
	for session.worlds {
		if (it.state == .PENDING || it.state == .PUBLISHED) && bytes_equal(it.capture_key, key) {
			free(members.data);
			operation.world = it;
			it.references += 1;
			session.head_target = it;
			if it.state == .PUBLISHED {
				finish_update(session, operation, .{kind = .PUBLISHED, world_identity = it.identity});
				install_head(session, it);
			} else {
				for task: session.tasks {
					if task.world == it && task.kind == .PARSE_INDEX && task.phase != .TERMINAL {
						require_task(session, task);
						array_add(*task.operations, operation);
					}
				}
			}

			return;
		}
	}


	for * members {
		if it.source {
			retain_source(it.source);
		}
	}

	_, identity := issue_world(*session.identities);
	world := New(World);
	world.identity = identity;
	world.frontier = operation.frontier;
	world.capture_key = key;
	world.members = members;
	world.consistency = ifx coherent then capture else .{kind = .IMMUTABLE_CAPTURE};
	world.references = 2;
	array_add(*session.worlds, world);
	operation.world = world;
	session.head_target = world;
	if !capturable {
		world.state = .FAILED;
		world.references -= 1;
		finish_update(session, operation, .{kind = .FAILED, failure = .{stage = .PROVIDER, code = .REVISION_UNAVAILABLE}});
		return;
	}


	task := New(Task);
	task.kind = .PARSE_INDEX;
	task.key = make_key("execution-task", session.identities.session.([] u8), world.identity.([] u8), xx "PARSE_INDEX");
	task.world = world;
	task.attempt = 1;
	array_add(*task.operations, operation);
	array_add(*session.tasks, task);
	array_add(*session.ready, task);
}

// A new accepted frontier supersedes pending older updates and cancels every unfinished task and query on older worlds.
supersede_obsolete :: (session: *Session) {
	successor := session.operations[session.operations.count - 1].identity;
	for session.operations {
		if it.terminal || bytes_equal(it.frontier, session.provider.accepted_frontier) {
			continue;
		}


		if it.kind == .UPDATE {
			finish_update(session, it, .{kind = .SUPERSEDED, successor = successor});
		} else if it.kind == .QUERY && !bytes_equal(it.world.frontier, session.provider.accepted_frontier) {
			finish_query(session, it, .{kind = .CANCELLED, cancellation = .WORLD_SUPERSEDED});
		}
	}

	for session.tasks {
		if !bytes_equal(it.world.frontier, session.provider.accepted_frontier) {
			stop_task(session, it);
		}
	}

	reap_all(session);
}

stop_task :: (session: *Session, task: *Task) {
	if task.phase == .READY {
		for session.ready {
			if it == task {
				remove it;
			}
		}

		for session.optional_ready {
			if it == task {
				remove it;
			}
		}

		task.phase = .TERMINAL;
		if task.kind == .PARSE_INDEX && task.world.state == .PENDING {
			task.world.state = .CANCELLED;
		}

		release_world(session, task.world);
	} else if task.phase == .RUNNING {
		#if TEST_HOOKS {
			if session.faults.skip_running_stop {
				return;
			}
		}


		task.phase = .STOP_REQUESTED;
		if task.kind == .PARSE_INDEX && task.world.state == .PENDING {
			task.world.state = .CANCELLED;
		}
	}
}

finish_update :: (session: *Session, operation: *Operation, outcome: Ticket_Terminal) {
	if operation.terminal {
		return;
	}


	operation.terminal = true;
	operation.update = outcome;
	give(session, .IN_FLIGHT_OPERATIONS);
	observation := update_observation(operation);
	while operation.waiters.count {
		resolve_waiter(session, operation, operation.waiters[0].slot, observation);
	}
}

// Completes a query operation, its waiter and its claim on the shared task; the last consumer of a queued task removes it.
finish_query :: (session: *Session, operation: *Operation, outcome: Query_Terminal, notify := true) {
	if operation.terminal {
		return;
	}


	operation.terminal = true;
	operation.query = outcome;
	give(session, .IN_FLIGHT_OPERATIONS);
	task := operation.task;
	if task {
		for task.operations {
			if it == operation {
				remove it;
			}
		}

		unconsumed := task.phase == .READY && !task.operations.count;
		#if TEST_HOOKS {
			unconsumed &&= !session.faults.keep_unconsumed_work;
		}

		if unconsumed {
			stop_task(session, task);
		}
	}

	observation := query_observation(operation.identity, operation.world, operation.member, operation.query_kind, outcome);
	while operation.waiters.count {
		if notify {
			resolve_waiter(session, operation, operation.waiters[0].slot, observation);
		} else {
			detach_waiter(session, operation, operation.waiters[0].slot);
			give(session, .PENDING_REGISTRATIONS);
		}
	}
}

new_waiter :: (session: *Session, operation: *Operation) -> Handle(.WAITER), Operation_Error {
	taken, missing := take(session, .LIVE_HANDLES, .PENDING_REGISTRATIONS, .COMPLETION_RECORDS);
	if !taken {
		return .{}, limit(missing);
	}


	handle := register(session, .WAITER, .{operation = operation});
	array_add(*operation.waiters, .{slot = handle.slot, generation = handle.generation});
	operation.registrations += 1;
	return handle, .{};
}

detach_waiter :: (session: *Session, operation: *Operation, slot: u64) {
	for operation.waiters {
		if it.slot == slot {
			remove it;
		}
	}
}

// One terminal transition per waiter, appended to the completion order.
resolve_waiter :: (session: *Session, operation: *Operation, slot: u64, observation: Observation) {
	reference: Slot_Reference;
	for operation.waiters {
		if it.slot == slot {
			reference = it;
		}
	}

	detach_waiter(session, operation, slot);
	registration := session.registrations[slot];
	registration.terminal = true;
	registration.observation = owned_observation(observation);
	give(session, .PENDING_REGISTRATIONS);
	array_add(*session.completions, reference);
}

pending_observation :: (operation: *Operation) -> Observation {
	phase := Pending_Phase.QUEUED;
	task := operation.task;
	if operation.kind == .UPDATE {
		task = null;
	}

	if task && task.phase == .RUNNING {
		phase = .RUNNING;
	}

	return .{kind = .PENDING, operation_identity = operation.identity, phase = phase};
}

update_observation :: (operation: *Operation) -> Observation {
	return .{
		kind = .UPDATE,
		operation_identity = operation.identity,
		provider_frontier = operation.frontier,
		documents = operation.documents,
		update = operation.update,
	};
}

query_observation :: (identity: Operation_ID, world: *World, member: s64, kind: Query_Kind, outcome: Query_Terminal) -> Observation {
	return .{
		kind = .QUERY,
		operation_identity = identity,
		world_identity = world.identity,
		document = world.members[member].document,
		context_identity = world.members[member].context_identity,
		query_kind = kind,
		query = outcome,
	};
}

waiter_observation :: (session: *Session, registration: *Registration) -> Observation {
	return ifx registration.terminal
		then registration.observation
		else pending_observation(registration.operation);
}

shutdown_observation :: (session: *Session) -> Observation {
	if session.lifecycle == .STOPPED {
		return .{kind = .SHUTDOWN, operation_identity = session.shutdown.identity};
	}


	return .{
		kind = .PENDING,
		operation_identity = session.shutdown.identity,
		phase = ifx session.lifecycle == .QUIESCING
			then .QUIESCING
			else .DRAINING,
	};
}

acquire_world_handle :: (session: *Session, world: *World) -> bool, World_Acquisition, Operation_Error {
	if !take(session, .LIVE_HANDLES) {
		return false, .{}, limit(.LIVE_HANDLES);
	}


	world.references += 1;
	return true, .{kind = .ACQUIRED, world = register(session, .WORLD, .{world = world})}, .{};
}

// Only the head target at the current frontier replaces the head.
install_head :: (session: *Session, world: *World) {
	if world != session.head_target || !bytes_equal(world.frontier, session.provider.accepted_frontier) || world == session.head {
		return;
	}


	world.references += 1;
	if session.head {
		release_world(session, session.head);
	}

	session.head = world;
}

new_result :: (session: *Session, world: *World, member: s64, kind: Query_Kind) -> *Query_Result {
	_, identity := issue_result(*session.identities);
	result := New(Query_Result);
	result.identity = identity;
	result.world = world;
	result.member = member;
	result.kind = kind;
	world.references += 1;
	return result;
}

release_result :: (session: *Session, result: *Query_Result) {
	result.references -= 1;
	if !result.references {
		release_world(session, result.world);
		free(result);
	}
}

release_member_syntax :: (syntax: *Member_Syntax) {
	if syntax.diagnostics {
		release_diagnostics_projection(syntax.diagnostics);
	}

	if syntax.index {
		release_declaration_index(syntax.index);
	}

	if syntax.snapshot {
		release_snapshot(syntax.snapshot);
	}

	if syntax.owner {
		release_owned_syntax(syntax.owner);
	}

	syntax.* = .{};
}

release_mailbox_output :: (mailbox: *Mailbox) {
	if mailbox.syntax.count || mailbox.diagnostics {
		array_add(
			*mailbox.session.retired_outputs,
			.{
				syntax = mailbox.syntax,
				diagnostics = mailbox.diagnostics,
			}
		);
	}

	mailbox.syntax = .[];
	mailbox.diagnostics = null;
}

release_world :: (session: *Session, world: *World) {
	world.references -= 1;
	if world.references {
		return;
	}


	for session.worlds {
		if it == world {
			remove it;
		}
	}

	array_add(*session.retired_worlds, world);
}

// Frees terminal operations no registration can observe any more.
reap :: (session: *Session, operation: *Operation) {
	if !operation.terminal || operation.registrations || operation.kind == .SHUTDOWN {
		return;
	}


	for session.operations {
		if it == operation {
			remove it;
		}
	}

	if operation.result {
		release_result(session, operation.result);
	}

	if operation.world {
		release_world(session, operation.world);
	}

	array_free(operation.waiters);
	free(operation);
}

reap_all :: (session: *Session) {
	for < session.operations {
		reap(session, it);
	}
}

// `.STOPPED` needs every dispatched producer's mailbox consumed; the reserved shutdown operation then completes.
check_stopped :: (session: *Session) {
	if (session.lifecycle != .DRAINING
		|| session.threaded && !session.worker_joined
		|| session.active_admissions
		|| session.cleanup_pins
		|| session.retired_worlds.count
		|| session.retired_outputs.count
		|| session.retired_sources.count
	) {
		return;
	}



	for session.tasks {
		if it.phase == .RUNNING || it.phase == .STOP_REQUESTED {
			return;
		}
	}


	session.lifecycle = .STOPPED;
	session.shutdown.terminal = true;
	release_reserved(*session.ledger, .IN_FLIGHT_OPERATIONS, 1);
}

maybe_destroy :: (session: *Session) {
	if !session.session_released {
		return;
	}


	for session.registry.slots {
		if it.live {
			return;
		}
	}


	session.retiring = true;
}

destroy_session :: (session: *Session) {
	push_allocator(owner_allocator(session));
	if session.head {
		release_world(session, session.head);
	}

	for session.mailboxes {
		release_mailbox_output(it);
		free(it);
	}

	cleanup_owned(session);

	for session.tasks {
		array_free(it.operations);
		free(it);
	}

	for session.registrations {
		free(it);
	}

	if session.shutdown {
		free(session.shutdown);
	}

	assert(!session.operations.count && !session.worlds.count, "Destroyed a session with live operations or worlds.");
	close_provider_model(session.provider);
	array_free(session.registrations);
	array_free(session.operations);
	array_free(session.worlds);
	array_free(session.tasks);
	array_free(session.ready);
	array_free(session.optional_ready);
	array_free(session.mailboxes);
	array_free(session.retired_worlds);
	array_free(session.retired_outputs);
	array_free(session.retired_sources);
	array_free(session.completions);
	array_free(session.registry.slots);
	array_free(session.registry.free_slots);
	destroy(*session.changed);
	destroy(*session.gate);
	#if TEST_HOOKS {
		for * session.pauses {
			destroy(*it.arrived);
			destroy(*it.proceed);
		}
	}

	if session.shutdown_control && !session.shutdown {
		free(session.shutdown_control);
	}

	release_owner_heap(*session.heap);
	#if TEST_HOOKS {
		atomic_add(*session.service.owned_allocations, -1);
		atomic_add(*session.service.owned_bytes, -size_of(Session));
	}
	free(session,, session.service.allocator);
}
