// Harness host (phase 4 step 3): the host side of `jai-cache-interface/1` for tests, the acceptance runner and measurements.
// It declares one project root, binds the service incarnation to an epoch reserved in that root, keys documents by their root-relative paths,
//  issues provider revisions, observation tokens and host confirmations, reads disk for observations
//  and drains completions through a serial dispatcher.  It never writes source files; only the issuer writes `.jaiParserEpoch`.

HARNESS_AUTHORITY_PREFIX	:: "jai-parser-harness:";
HARNESS_POLICY_VERSION		:: 1;

Harness_Host :: struct {
	service:			*Service;
	session:			Handle(.SESSION);
	session_identity:	Session_ID;

	// Absolute, `/`-separated, without a trailing separator:
	root:				string;

	epoch:				u64;
	workspace:			[]u8;
	provider_namespace:	[]u8;
	host_authority:		[]u8;
	revisions:			Identity_Counter;
	observations:		Identity_Counter;
	confirmations:		Identity_Counter;

	// Context identities the session already owns:
	registered:			[..][]u8;

	dispatching:		bool;
	dispatch_failures:	s64;
}

Host_Batch :: struct {
	host:			*Harness_Host;
	description:	Session_Description;
	events:			[..]Document_Event;
	contexts:		[..]Context_Registration;
}

Host_Failure :: enum u8 {
	NONE;
	INVALID_ROOT;
	EPOCH_UNAVAILABLE;
	SESSION_REJECTED;
}

open_harness_host :: (root: string, ceilings: Limits, minima: Limits, requested_limits := Limit_Request.{}) -> Host_Failure, *Harness_Host, Operation_Error {
	normalised := copy_string(root);
	for 0..normalised.count - 1 {
		if normalised[it] == #char "\\" {
			normalised[it] = #char "/";
		}
	}

	while normalised.count > 1 && normalised[normalised.count - 1] == #char "/" {
		normalised.count -= 1;
	}

	directory, directory_ok := is_directory(normalised);
	if !directory || !directory_ok {
		free(normalised);
		return .INVALID_ROOT, null, .{};
	}


	authority := tprint("%1%2", HARNESS_AUTHORITY_PREFIX, normalised).([]u8);
	epoch_ok, epoch := reserve_epoch(normalised, authority);
	if !epoch_ok {
		free(normalised);
		return .EPOCH_UNAVAILABLE, null, .{};
	}


	host := New(Harness_Host);
	host.root = normalised;
	host.epoch = epoch;
	host.service = open_service(authority, epoch, ceilings, minima);
	host.workspace = make_key("harness-workspace", authority);
	host.provider_namespace = make_key("harness-provider", authority);
	host.host_authority = make_key("harness-host", authority, little_endian(epoch, 8));
	options := Session_Options.{
		version = INTERFACE_VERSION,
		workspace = host.workspace,
		provider_namespace = host.provider_namespace,
		host_authority = host.host_authority,
		provider_capabilities = .{
			adapter_schema = SOURCE_PROVIDER_SCHEMA,
			authority_identity = host.host_authority,
			document_policy_version = HARNESS_POLICY_VERSION,
			path_platform = ifx OS == .WINDOWS
				then .WINDOWS_UTF16LE
				else .POSIX_BYTES,
			consistency_capabilities = .IMMUTABLE_CAPTURE,
		},
		supported_tuples = .[IMPLEMENTED_SCHEMA_TUPLE],
		requested_limits = requested_limits,
	};

	opened_ok, opened, error := open_session(host.service, options);
	if !opened_ok {
		free(host.root);
		free(host);
		return .SESSION_REJECTED, null, error;
	}


	host.session = opened.session;
	host.session_identity = opened.description.session_identity;
	return .NONE, host, .{};
}

// Shuts the session down, waits for `.STOPPED` and releases the session; child handles the caller still owns stay valid:
close_harness_host :: (host: *Harness_Host) -> bool, Operation_Error {
	ok, shutdown, error := request_shutdown(host.service, host.session);
	if !ok {
		return false, error;
	}


	waited_ok, waited, wait_error := wait(host.service, shutdown, .{clock_identity = host.service.clock_identity, nanoseconds = U64_MAX});
	release(host.service, shutdown);
	if !waited_ok || waited.timed_out {
		return false, wait_error;
	}


	released, release_error := release(host.service, host.session);
	return released, release_error;
}

harness_document :: (host: *Harness_Host, relative: string) -> []u8 {
	return document_id(host.provider_namespace, HARNESS_POLICY_VERSION, xx relative);
}

// Relative paths stay inside the root: no absolute, drive or backslash spellings and no empty, `.` or `..` segments:
valid_relative :: (relative: string) -> bool {
	if !relative.count || relative[0] == #char "/" || find_index_from_left(relative, #char "\\") >= 0 || find_index_from_left(relative, #char ":") >= 0 {
		return false;
	}


	for split(relative, "/",, temp) {
		if !it.count || it == "." || it == ".." {
			return false;
		}
	}


	return true;
}

// Snapshots the accepted frontier and tracked states the batch's expected bases come from:
begin_batch :: (host: *Harness_Host) -> Host_Batch {
	_, description := describe_session(host.service, host.session);
	return .{host = host, description = description};
}

set_overlay :: (batch: *Host_Batch, relative: string, text: string) -> bool {
	event := prepare(batch, relative);
	if !event {
		return false;
	}


	event.kind = .SET_OVERLAY;
	event.source = .{kind = .INLINE_BYTES, bytes = xx text};
	return true;
}

// Edits apply to the tracked overlay's bytes, each to the previous edit's result:
edit_overlay :: (batch: *Host_Batch, relative: string, edits: []Range_Edit) -> bool {
	tracked := find_tracked(batch, relative);
	event := prepare(batch, relative);
	if !event || !tracked || !tracked.has_overlay {
		return false;
	}


	event.kind = .EDIT_OVERLAY;
	event.edit_overlay = .{base_source_revision = tracked.overlay_source_revision, edits = edits};
	return true;
}

// Present bytes, confirmed absence, or `false` when the file exists but cannot be read; a read failure is never absence:
observe_disk :: (batch: *Host_Batch, relative: string) -> bool {
	context_count := batch.contexts.count;
	event := prepare(batch, relative);
	if !event {
		return false;
	}


	ok, disk := disk_observation(batch.host, event, relative);
	if !ok {
		batch.events.count -= 1;
		batch.contexts.count = context_count;
		return false;
	}


	event.kind = .OBSERVE_DISK;
	event.disk = disk;
	return true;
}

// The host saved an overlay installation's bytes itself (default: the current one); clearing it needs matching bytes:
ack_save :: (batch: *Host_Batch, relative: string, installation: []u8 = .[]) -> bool {
	tracked := find_tracked(batch, relative);
	context_count := batch.contexts.count;
	event := prepare(batch, relative);
	if !event || !tracked || !tracked.has_overlay {
		return false;
	}


	ok, disk := disk_observation(batch.host, event, relative);
	if !ok {
		batch.events.count -= 1;
		batch.contexts.count = context_count;
		return false;
	}


	event.kind = .ACK_SAVE;
	if disk.kind != .PRESENT {
		event.ack_save = .{disk = disk};
		return false;
	}


	expected_overlay_revision := ifx installation.count
		then installation
		else tracked.overlay_installation_revision;

	event.ack_save = .{
		disk = disk,
		written_source_revision = disk.present.source_revision,
		expected_overlay_revision = expected_overlay_revision,
	};
	return true;
}

reset_overlay :: (batch: *Host_Batch, relative: string) -> bool {
	context_count := batch.contexts.count;
	event := prepare(batch, relative);
	if !event || event.expected_provider_state.kind == .UNTRACKED {
		return false;
	}


	confirmed, host_confirmation := confirmation(batch.host, event, .RESET);
	observed: bool;
	disk: Disk_Observation;
	if confirmed {
		observed, disk = disk_observation(batch.host, event, relative);
	}

	if !observed {
		batch.events.count -= 1;
		batch.contexts.count = context_count;
		return false;
	}


	event.kind = .RESET_OVERLAY;
	event.reset_overlay = .{disk = disk, host_confirmation = host_confirmation};
	return true;
}

// The host confirms restoring `text` from `candidate`; the confirmation binds both:
restore_overlay :: (batch: *Host_Batch, relative: string, text: string, candidate: []u8) -> bool {
	context_count := batch.contexts.count;
	event := prepare(batch, relative);
	if !event || !candidate.count {
		return false;
	}


	ok, host_confirmation := confirmation(batch.host, event, .RESTORE);
	if !ok {
		batch.events.count -= 1;
		batch.contexts.count = context_count;
		return false;
	}


	host_confirmation.source_revision = source_revision_of(xx text);
	host_confirmation.recovery_candidate = candidate;
	event.kind = .RESTORE_OVERLAY;
	event.restore_overlay = .{
		source = .{kind = .INLINE_BYTES, bytes = xx text},
		host_confirmation = host_confirmation,
		recovery_candidate = candidate,
	};
	return true;
}

submit_batch :: (batch: *Host_Batch) -> bool, Accepted, Operation_Error {
	host := batch.host;
	source_batch := Source_Batch.{
		version = INTERFACE_VERSION,
		session = host.session_identity,
		expected_frontier = batch.description.accepted_frontier,
		contexts = batch.contexts,
		events = batch.events,
	};
	ok, accepted, error := submit_source_batch(host.service, host.session, source_batch);
	if ok {
		for batch.contexts {
			array_add(*host.registered, array_copy(it.identity));
		}
	}

	return ok, accepted, error;
}

Completion_Handler :: #type (host: *Harness_Host, record: Completion_Record) -> bool;

// Serial host dispatch: a nested call returns at once, and the outer loop keeps draining until nothing is ready.
// A handler's failure is counted, not retried; the delivered record stays observable through its registration.
dispatch_completions :: (host: *Harness_Host, handler: Completion_Handler, batch_size: u64 = 16) -> s64 {
	if host.dispatching {
		return 0;
	}


	host.dispatching = true;
	defer host.dispatching = false;

	count := 0;
	while true {
		ok, records := drain_completions(host.service, host.session, batch_size);
		if !ok || !records.count {
			break;
		}


		for * records {
			count += 1;
			if !handler(host, it.*) {
				host.dispatch_failures += 1;
			}

			free_observation(*it.observation);
		}

		array_free(records);
	}

	return count;
}

#scope_file

path_value :: (spelling: string) -> Path_Value {
	ok: bool;
	value: Path_Value;
	#if OS == .WINDOWS {
		ok, value = windows_path_value(spelling);
	} else {
		ok, value = posix_path_value(spelling);
	}

	assert(ok);
	return value;
}

context_registration :: (host: *Harness_Host, relative: string) -> Context_Registration {
	absolute := tprint("%/%", host.root, relative);
	slash := find_index_from_right(absolute, #char "/");
	paths := Context_Paths.{
		visible_filename = path_value(absolute),
		visible_directory = path_value(slice(absolute, 0, slash)),
		relative_base = path_value(host.root),
	};
	ok, descriptor := syntax_context_descriptor(paths);
	assert(ok);
	return .{identity = context_id(descriptor), descriptor = descriptor};
}

find_tracked :: (batch: *Host_Batch, relative: string) -> *Tracked_Document {
	document := harness_document(batch.host, relative);
	for * batch.description.tracked_document_states {
		if bytes_equal(it.document, document) {
			return it;
		}
	}


	return null;
}

// Fills the identity, base, context, binding and a fresh provider revision shared by every event kind:
// Derive these from the batch's captured state so an event cannot silently adopt a later base.
prepare :: (batch: *Host_Batch, relative: string) -> *Document_Event {
	if !valid_relative(relative) {
		return null;
	}


	host := batch.host;
	ok, token := issue_token(*host.revisions);
	if !ok {
		return null;
	}


	registration := context_registration(host, relative);
	known := false;
	for host.registered {
		known ||= bytes_equal(it, registration.identity);
	}

	for batch.contexts {
		known ||= bytes_equal(it.identity, registration.identity);
	}

	if !known {
		array_add(*batch.contexts, registration);
	}

	tracked := find_tracked(batch, relative);
	event := array_add(*batch.events);
	event.document = harness_document(host, relative);
	event.source_context = registration.identity;
	event.resulting_provider_revision = provider_revision_id(host.provider_namespace, host.session_identity, event.document, little_endian(token, 8));
	if tracked {
		event.expected_provider_state = .{kind = .REVISION, revision = tracked.provider_revision};
	} else {
		event.binding = New(Document_Binding,, temp);
		event.binding.* = .{
			document = event.document,
			absolute_path = path_value(tprint("%/%", host.root, relative)),
			provider_policy_version = HARNESS_POLICY_VERSION,
		};
	}

	return event;
}

disk_observation :: (host: *Harness_Host, event: *Document_Event, relative: string) -> bool, Disk_Observation {
	ok, token := issue_token(*host.observations);
	if !ok {
		return false, .{};
	}


	provenance := Observation_Provenance.{provider_identity = host.provider_namespace, observation_token = little_endian(token, 8,, temp)};
	path := tprint("%/%", host.root, relative);
	text, read_ok := read_entire_file(path, log_errors = false,, temp);
	if read_ok {
		return true, disk_present(
			event.source_context,
			provenance,
			.{kind = .INLINE_BYTES, bytes = xx text},
			source_revision_of(xx text)
		);
	}


	if file_exists(path) {
		return false, .{};
	}


	return true, disk_absent(event.source_context, provenance, event.resulting_provider_revision);
}

confirmation :: (host: *Harness_Host, event: *Document_Event, action: Confirmation_Action) -> bool, Host_Confirmation {
	ok, token := issue_token(*host.confirmations);
	if !ok {
		return false, .{};
	}


	return true, .{
		host_authority = host.host_authority,
		confirmation_token = make_key("harness-confirmation", host.host_authority, little_endian(token, 8),, temp),
		document = event.document,
		expected_provider_state = event.expected_provider_state,
		action = action,
	};
}
