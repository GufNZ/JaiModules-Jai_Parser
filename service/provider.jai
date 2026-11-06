// Source provider model (phase 4 step 1): milestone-2 provider admission, document and revision identities, and atomic source batches over separate overlay and disk branches,
//  per CACHE_CONTRACTS.md "Source Event Payloads", "Milestone 2: Provider Admission and Bounded Values" and the source-capture contract.
// It holds source selection only; parsing, worlds and tickets belong to the coordinator.
// Accepted bytes are copied into reference-counted backings, so a capture that retains one keeps it exact after later events.

INTERFACE_VERSION :: "jai-cache-interface/1";
SOURCE_PROVIDER_SCHEMA :: "jai-cache-source-provider/1";

Path_Platform :: enum u8 {
	WINDOWS_UTF16LE;
	POSIX_BYTES;
}

Alias_Policy :: struct {
	kind: enum u8 {
		DISTINCT_KEYS;
		HOST_VALIDATED_ALIASES;
	};
	policy_identity: string;
}

Reappearance_Policy :: enum u8 {
	SAME_KEY;
	FRESH_KEY;
}

Consistency_Capability :: enum_flags u8 {
	IMMUTABLE_CAPTURE;
	COHERENT_CAPTURE;
}

Lease_Capability :: struct {
	kind: enum u8 {
		COPY_ONLY;
		IMMUTABLE_RETAIN_RELEASE;
	};
	lease_schema: string;
}

Provider_Adapter_Descriptor :: struct {
	adapter_schema: string;
	authority_identity: [] u8;
	document_policy_version: u32;
	path_platform: Path_Platform;
	case_alias_link_policy: Alias_Policy;
	reappearance_policy: Reappearance_Policy;
	consistency_capabilities: Consistency_Capability;
	lease_capabilities: Lease_Capability;
}

Provider_Failure :: enum u8 {
	NONE;
	SCHEMA;
	AUTHORITY;
	ALIAS_POLICY;
	CONSISTENCY;
	LEASE;
}

// Only what this build implements: distinct host-issued keys and copied inline bytes.
// No alias validator or lease schema is registered.
validate_provider_descriptor :: (descriptor: Provider_Adapter_Descriptor) -> Provider_Failure {
	if descriptor.adapter_schema != SOURCE_PROVIDER_SCHEMA {
		return .SCHEMA;
	}


	if !descriptor.authority_identity.count {
		return .AUTHORITY;
	}


	if descriptor.case_alias_link_policy.kind != .DISTINCT_KEYS {
		return .ALIAS_POLICY;
	}


	if !descriptor.consistency_capabilities {
		return .CONSISTENCY;
	}


	return ifx descriptor.lease_capabilities.kind == .COPY_ONLY then .NONE else .LEASE;
}

// `K("document", [provider_namespace, document_policy_version:u32, provider_document_key])`.
document_id :: (provider_namespace: [] u8, policy_version: u32, document_key: [] u8) -> [] u8 {
	return make_key("document", provider_namespace, little_endian(policy_version, 4), document_key);
}

// `K("source", [u32 1, u64 byte_count, DIGEST128(bytes)])`.
source_revision_of :: (bytes: [] u8) -> [] u8 {
	digest := digest_128(bytes);
	return make_key("source", little_endian(1, 4), little_endian(xx bytes.count, 8), digest.bytes);
}

provider_revision_id :: (provider_namespace: [] u8, session: Session_ID, document: [] u8, token: [] u8) -> [] u8 {
	return make_key("provider-revision", provider_namespace, session.([] u8), document, token);
}

provider_frontier_id :: (provider_namespace: [] u8, session: Session_ID, token: u64) -> [] u8 {
	return make_key("provider-frontier", provider_namespace, session.([] u8), little_endian(token, 8));
}

Document_Binding :: struct {
	document: [] u8;
	absolute_path: Path_Value;
	provider_policy_version: u32;
}

Source_Input :: struct {
	kind: enum u8 {
		INLINE_BYTES;
		PROVIDER_LEASE;
	};
	bytes: [] u8;
}

Consistency :: struct {
	kind: enum u8 {
		IMMUTABLE_CAPTURE;
		COHERENT_CAPTURE;
	};
	provider_namespace: [] u8;
	capture_token: [] u8;
}

Observation_Provenance :: struct {
	provider_identity: [] u8;
	observation_token: [] u8;
	consistency: Consistency;
}

Disk_Observation :: struct {
	kind: enum u8 {
		PRESENT;
		ABSENT;
	};
	// `.PRESENT` only.
	source: Source_Input;
	source_revision: [] u8;
	// `.ABSENT` only.
	provider_revision: [] u8;
	syntax_context: [] u8;
	provenance: Observation_Provenance;
}

Expected_Provider_State :: struct {
	kind: enum u8 {
		UNTRACKED;
		REVISION;
	};
	revision: [] u8;
}

Confirmation_Action :: enum u8 {
	RESET;
	RESTORE;
}

Host_Confirmation :: struct {
	host_authority: [] u8;
	confirmation_token: [] u8;
	document: [] u8;
	expected_provider_state: Expected_Provider_State;
	action: Confirmation_Action;
	// Empty means null.
	source_revision: [] u8;
	recovery_candidate: [] u8;
}

Range_Edit :: struct {
	start_byte: u64;
	end_byte: u64;
	replacement: [] u8;
}

Event_Kind :: enum u8 {
	SET_OVERLAY;
	EDIT_OVERLAY;
	OBSERVE_DISK;
	ACK_SAVE;
	RESET_OVERLAY;
	RESTORE_OVERLAY;
	RENAME;
}

// One record for every arm; each kind reads only its own payload fields.
Document_Event :: struct {
	document: [] u8;
	expected_provider_state: Expected_Provider_State;
	source_context: [] u8;
	binding: *Document_Binding;
	kind: Event_Kind;
	// `.SET_OVERLAY` and `.RESTORE_OVERLAY`.
	source: Source_Input;
	// `.EDIT_OVERLAY`.
	base_source_revision: [] u8;
	edits: [] Range_Edit;
	// `.OBSERVE_DISK`, `.ACK_SAVE` and `.RESET_OVERLAY`.
	disk: Disk_Observation;
	// `.ACK_SAVE`.
	written_source_revision: [] u8;
	expected_overlay_revision: [] u8;
	// `.RESET_OVERLAY` and `.RESTORE_OVERLAY`.
	host_confirmation: Host_Confirmation;
	recovery_candidate: [] u8;
	resulting_provider_revision: [] u8;
}

Context_Registration :: struct {
	identity: [] u8;
	descriptor: [] u8;
}

Source_Batch :: struct {
	version: string;
	session: Session_ID;
	expected_frontier: [] u8;
	contexts: [] Context_Registration;
	events: [] Document_Event;
}

Operation_Error_Code :: enum u8 {
	INVALID_VERSION;
	INVALID_ARGUMENT;
	INVALID_HANDLE;
	BASE_MISMATCH;
	UNSUPPORTED_EVENT;
	ADMISSION_DENIED;
	ACTIVE_SESSION;
	SERVICE_CLOSED;
}

Argument_Rule :: enum u8 {
	MISSING;
	UNKNOWN_FIELD;
	UNKNOWN_TAG;
	DUPLICATE;
	WRONG_KIND;
	OUT_OF_RANGE;
	INVALID_ENCODING;
	INCONSISTENT_BINDING;
	INVALID_CONFIRMATION;
}

Base_Scope :: enum u8 {
	FRONTIER;
	DOCUMENT;
	SOURCE;
	OVERLAY;
}

Admission_Reason :: struct {
	kind: enum u8 {
		LIMIT;
		CONFIGURATION_REQUIRED;
		CAPABILITY;
		SOURCE_ACQUISITION;
		RESOURCE_EXHAUSTED;
	};
	limit: Limit_Name;
	schema: string;
}

// Only the arm selected by `code` is meaningful.
Operation_Error :: struct {
	code: Operation_Error_Code;
	path: [] Path_Step;
	rule: Argument_Rule;
	scope: Base_Scope;
	document: [] u8;
	event_tag: string;
	admission: Admission_Reason;
	handle_kind: Handle_Kind;
}

Source_Backing :: struct {
	revision: [] u8;
	bytes: [] u8;
	references: s64;
}

retain_source :: (backing: *Source_Backing) {
	atomic_add(*backing.references, 1);
}

release_source :: (backing: *Source_Backing) {
	previous := atomic_add(*backing.references, -1);
	assert(previous > 0);
	if previous == 1 {
		free(backing.revision.data);
		free(backing.bytes.data);
		free(backing);
	}
}

Unavailable_Reason :: enum u8 {
	NOT_CAPTURED;
	SOURCE_ABSENT;
	SOURCE_UNKNOWN;
	REVISION_UNAVAILABLE;
	PROVIDER_UNAVAILABLE;
}

Disk_State :: struct {
	kind: enum u8 {
		UNKNOWN;
		PRESENT;
		ABSENT;
		UNAVAILABLE;
	};
	source: *Source_Backing;
	syntax_context: [] u8;
	provenance: Observation_Provenance;
	reason: Unavailable_Reason;
}

Overlay_Origin :: enum u8 {
	ACTIVE;
	RESTORED;
}

Overlay_State :: struct {
	installation_revision: [] u8;
	source: *Source_Backing;
	syntax_context: [] u8;
	origin: Overlay_Origin;
}

Document_State :: struct {
	document: [] u8;
	provider_revision: [] u8;
	binding: Document_Binding;
	disk: Disk_State;
	has_overlay: bool;
	overlay: Overlay_State;
	// Every provider revision accepted for this document; a token is never reassigned.
	used_revisions: [..] [] u8;
}

Selected_Document :: struct {
	document: [] u8;
	provider_revision: [] u8;
	syntax_context: [] u8;
	kind: enum u8 {
		PRESENT;
		ABSENT;
		UNKNOWN;
		UNAVAILABLE;
	};
	source: *Source_Backing;
	selection: enum u8 {
		OVERLAY;
		DISK;
		RESTORED_OVERLAY;
	};
	// Set for overlay selections only.
	overlay_revision: [] u8;
	// Null for host overlays.
	provenance: *Observation_Provenance;
	reason: Unavailable_Reason;
}

// An overlay takes precedence over the acknowledged disk branch.
selected_document :: (state: *Document_State) -> Selected_Document {
	result := Selected_Document.{document = state.document, provider_revision = state.provider_revision};
	if state.has_overlay {
		result.kind = .PRESENT;
		result.source = state.overlay.source;
		result.syntax_context = state.overlay.syntax_context;
		result.selection = ifx state.overlay.origin == .RESTORED
			then .RESTORED_OVERLAY
			else .OVERLAY;
		result.overlay_revision = state.overlay.installation_revision;
		return result;
	}


	result.syntax_context = state.disk.syntax_context;
	result.selection = .DISK;
	if state.disk.kind == {
		case .PRESENT;
			result.kind = .PRESENT;
			result.source = state.disk.source;
			result.provenance = *state.disk.provenance;

		case .ABSENT;
			result.kind = .ABSENT;
			result.provenance = *state.disk.provenance;

		case .UNKNOWN;
			result.kind = .UNKNOWN;

		case .UNAVAILABLE;
			result.kind = .UNAVAILABLE;
			result.reason = state.disk.reason;
	}

	return result;
}

Provider_Model :: struct {
	descriptor: Provider_Adapter_Descriptor;
	provider_namespace: [] u8;
	session: Session_ID;
	host_authority: [] u8;
	limits: Limits;
	documents: [..] *Document_State;
	contexts: [..] Admitted_Context;
	frontier_counter: Identity_Counter;
	accepted_frontier: [] u8;
	// Each accepted batch's copied identities and metadata; released with the model.
	batch_storage: [..] *Pool;
}

// The descriptor must already have passed `validate_provider_descriptor`.
// The initial frontier precedes every accepted batch.
open_provider_model :: (descriptor: Provider_Adapter_Descriptor, provider_namespace: [] u8, session: Session_ID, host_authority: [] u8, limits: Limits) -> *Provider_Model {
	model := New(Provider_Model);
	model.descriptor = descriptor;
	model.provider_namespace = array_copy(provider_namespace);
	model.session = xx array_copy(session.([] u8));
	model.host_authority = array_copy(host_authority);
	model.limits = limits;
	_, token := issue_token(*model.frontier_counter);
	model.accepted_frontier = provider_frontier_id(model.provider_namespace, model.session, token);
	return model;
}

close_provider_model :: (model: *Provider_Model) {
	for model.documents {
		release_document_sources(it);
		array_free(it.used_revisions);
		free(it);
	}

	array_free(model.documents);
	array_free(model.contexts);
	for model.batch_storage {
		release(it);
		free(it);
	}

	array_free(model.batch_storage);
	free(model);
}

find_document :: (model: *Provider_Model, document: [] u8) -> *Document_State {
	for model.documents {
		if bytes_equal(it.document, document) {
			return it;
		}
	}


	return null;
}

// Tracked documents in canonical `DocumentID` order; the states stay owned by the model.
tracked_documents :: (model: *Provider_Model) -> [] *Document_State {
	result := array_copy(model.documents,, temp);
	for i: 1..result.count - 1 {
		j := i;
		while j > 0 && compare_canonical(result[j - 1].document, result[j].document) > 0 {
			result[j - 1], result[j] = result[j], result[j - 1];
			j -= 1;
		}
	}

	return result;
}

has_context :: (model: *Provider_Model, identity: [] u8) -> bool {
	return find_context(model, identity) != null;
}

find_context :: (model: *Provider_Model, identity: [] u8) -> *Admitted_Context {
	for * model.contexts {
		if bytes_equal(it.identity, identity) {
			return it;
		}
	}


	return null;
}

// Session-level registrations from `OpenSession`; all are admitted or none.
register_contexts :: (model: *Provider_Model, registrations: [] Context_Registration) -> bool, Operation_Error {
	admitted: [..] Admitted_Context;
	for registrations {
		failure, context_value := admit_context(it.identity, it.descriptor);
		duplicate := has_context(model, context_value.identity);
		for other: admitted {
			duplicate ||= bytes_equal(other.identity, context_value.identity);
		}

		if failure != .NONE || duplicate {
			array_free(admitted);
			error := Operation_Error.{code = .INVALID_ARGUMENT, rule = ifx failure != .NONE then Argument_Rule.INVALID_ENCODING else .DUPLICATE};
			error.path = NewArray(2, Path_Step);
			error.path[0] = .{kind = .FIELD, name = "contexts"};
			error.path[1] = .{kind = .ELEMENT, index = it_index};
			return false, error;
		}


		array_add(*admitted, context_value);
	}


	array_add(*model.contexts, ..admitted);
	array_free(admitted);
	return true, .{};
}

// Validates the whole batch against staged copies, then commits every member and one new frontier together, or nothing.
apply_source_batch :: (model: *Provider_Model, batch: Source_Batch) -> bool, [] u8, Operation_Error {
	staging: Batch_Staging;
	staging.model = model;
	staging.storage = New(Pool);
	set_allocators(staging.storage);
	ok := stage_batch(*staging, batch);
	if !ok {
		discard_staging(*staging);
		return false, .[], staging.error;
	}


	for staging.contexts {
		array_add(*model.contexts, it);
	}

	for staged: staging.states {
		existing := find_document(model, staged.document);
		if existing {
			release_document_sources(existing);
			array_free(existing.used_revisions);
			existing.* = staged.*;
			free(staged);
		} else {
			array_add(*model.documents, staged);
		}
	}

	token_ok, token := issue_token(*model.frontier_counter);
	assert(token_ok);
	model.accepted_frontier = provider_frontier_id(model.provider_namespace, model.session, token);
	array_add(*model.batch_storage, staging.storage);
	array_free(staging.states);
	array_free(staging.contexts);
	array_free(staging.referenced_contexts);
	array_free(staging.path);
	return true, model.accepted_frontier, .{};
}

#scope_file

Batch_Staging :: struct {
	model: *Provider_Model;
	states: [..] *Document_State;
	contexts: [..] Admitted_Context;
	referenced_contexts: [..] [] u8;
	error: Operation_Error;
	path: [..] Path_Step;
	storage: *Pool;
}

release_document_sources :: (state: *Document_State) {
	if state.disk.source {
		release_source(state.disk.source);
	}

	if state.has_overlay {
		release_source(state.overlay.source);
	}
}

discard_staging :: (staging: *Batch_Staging) {
	for staging.states {
		release_document_sources(it);
		array_free(it.used_revisions);
		free(it);
	}

	array_free(staging.states);
	array_free(staging.contexts);
	array_free(staging.referenced_contexts);
	array_free(staging.path);
	release(staging.storage);
	free(staging.storage);
}

own :: (staging: *Batch_Staging, bytes: [] u8) -> [] u8 {
	return array_copy(bytes,, Allocator.{pool_allocator_proc, staging.storage});
}

reject :: (staging: *Batch_Staging, code: Operation_Error_Code) -> bool {
	staging.error.code = code;
	staging.error.path = array_copy(staging.path);
	return false;
}

argument :: (staging: *Batch_Staging, rule: Argument_Rule, names: .. string) -> bool {
	for names {
		array_add(*staging.path, .{kind = .FIELD, name = it});
	}

	staging.error.rule = rule;
	return reject(staging, .INVALID_ARGUMENT);
}

base_mismatch :: (staging: *Batch_Staging, scope: Base_Scope, document: [] u8) -> bool {
	staging.error.scope = scope;
	staging.error.document = document;
	return reject(staging, .BASE_MISMATCH);
}

limit :: (staging: *Batch_Staging, name: Limit_Name) -> bool {
	staging.error.admission = .{kind = .LIMIT, limit = name};
	return reject(staging, .ADMISSION_DENIED);
}

capability :: (staging: *Batch_Staging, schema: string) -> bool {
	staging.error.admission = .{kind = .CAPABILITY, schema = schema};
	return reject(staging, .ADMISSION_DENIED);
}

new_source :: (bytes: [] u8) -> *Source_Backing {
	backing := New(Source_Backing);
	backing.bytes = array_copy(bytes);
	backing.revision = source_revision_of(bytes);
	backing.references = 1;
	return backing;
}

key_fields :: (key: [] u8, tag: string, count: s64) -> bool, [] [] u8 {
	ok, view := parse_key(key, xx count,, temp);
	if !ok || view.tag.(string) != tag || view.fields.count != count {
		return false, .[];
	}


	return true, view.fields;
}

stage_batch :: (staging: *Batch_Staging, batch: Source_Batch) -> bool {
	model := staging.model;
	if batch.version != INTERFACE_VERSION {
		staging.error.code = .INVALID_VERSION;
		return false;
	}


	if !bytes_equal(batch.session.([] u8), model.session.([] u8)) {
		return argument(staging, .INCONSISTENT_BINDING, "session");
	}


	if !batch.events.count {
		return argument(staging, .MISSING, "events");
	}


	if !within_limit(model.limits, .BATCH_EVENTS, batch.events.count) {
		return limit(staging, .BATCH_EVENTS);
	}


	if !bytes_equal(batch.expected_frontier, model.accepted_frontier) {
		return base_mismatch(staging, .FRONTIER, .[]);
	}


	for registration: batch.contexts {
		array_add(*staging.path, .{kind = .FIELD, name = "contexts"}, .{kind = .ELEMENT, index = it_index});
		failure, admitted := admit_context(registration.identity, registration.descriptor);
		if failure != .NONE {
			return argument(staging, .INVALID_ENCODING);
		}


		duplicate := has_context(model, admitted.identity);
		for staging.contexts {
			duplicate ||= bytes_equal(it.identity, admitted.identity);
		}

		if duplicate {
			return argument(staging, .DUPLICATE);
		}


		array_add(*staging.contexts, admitted);
		staging.path.count = 0;
	}


	tracked_count := model.documents.count;
	for event, event_index: batch.events {
		array_add(*staging.path, .{kind = .FIELD, name = "events"}, .{kind = .ELEMENT, index = event_index});
		for 0..event_index - 1 {
			if bytes_equal(batch.events[it].document, event.document) {
				return argument(staging, .DUPLICATE, "document");
			}
		}

		existing := find_document(model, event.document);
		if !existing {
			tracked_count += 1;
			if !within_limit(model.limits, .CAPTURE_DOCUMENTS, tracked_count) {
				return limit(staging, .CAPTURE_DOCUMENTS);
			}
		}

		if !stage_event(staging, event, existing) {
			return false;
		}


		staging.path.count = 0;
	}


	// Each new registration must be used by this batch.
	for staging.contexts {
		used := false;
		for referenced: staging.referenced_contexts {
			used ||= bytes_equal(referenced, it.identity);
		}

		if !used {
			array_add(*staging.path, .{kind = .FIELD, name = "contexts"}, .{kind = .ELEMENT, index = it_index});
			return argument(staging, .INCONSISTENT_BINDING);
		}
	}


	return true;
}

known_context :: (staging: *Batch_Staging, identity: [] u8) -> bool {
	array_add(*staging.referenced_contexts, identity);
	if has_context(staging.model, identity) {
		return true;
	}


	for staging.contexts {
		if bytes_equal(it.identity, identity) {
			return true;
		}
	}


	return false;
}

// A host-issued key under this provider's namespace and policy version.
valid_document_key :: (model: *Provider_Model, document: [] u8) -> bool {
	ok, fields := key_fields(document, "document", 3);
	if !ok || !bytes_equal(fields[0], model.provider_namespace) || !fields[2].count {
		return false;
	}


	return bytes_equal(fields[1], little_endian(model.descriptor.document_policy_version, 4,, temp));
}

bindings_equal :: (a: Document_Binding, b: Document_Binding) -> bool {
	return bytes_equal(a.document, b.document)
		&& a.absolute_path.encoding == b.absolute_path.encoding
		&& bytes_equal(a.absolute_path.code_units, b.absolute_path.code_units)
		&& a.provider_policy_version == b.provider_policy_version;
}

expected_equal :: (a: Expected_Provider_State, b: Expected_Provider_State) -> bool {
	return a.kind == b.kind && (a.kind == .UNTRACKED || bytes_equal(a.revision, b.revision));
}

stage_source :: (staging: *Batch_Staging, input: Source_Input, names: .. string) -> *Source_Backing {
	if input.kind != .INLINE_BYTES {
		for names {
			array_add(*staging.path, .{kind = .FIELD, name = it});
		}

		capability(staging, "PROVIDER_LEASE");
		return null;
	}


	if !within_limit(staging.model.limits, .SOURCE_BYTES, input.bytes.count) {
		limit(staging, .SOURCE_BYTES);
		return null;
	}


	return new_source(input.bytes);
}

valid_provenance :: (staging: *Batch_Staging, provenance: Observation_Provenance) -> bool {
	if !provenance.provider_identity.count || !provenance.observation_token.count {
		return argument(staging, .MISSING, "observation_provenance");
	}


	if provenance.consistency.kind == .COHERENT_CAPTURE {
		if !(staging.model.descriptor.consistency_capabilities & .COHERENT_CAPTURE) {
			return capability(staging, "COHERENT_CAPTURE");
		}


		if !provenance.consistency.capture_token.count || !bytes_equal(provenance.consistency.provider_namespace, staging.model.provider_namespace) {
			return argument(staging, .INCONSISTENT_BINDING, "observation_provenance", "consistency");
		}
	}


	return true;
}

// Applies a disk observation to `state.disk`, checking its revision claim against the bytes rather than trusting it.
stage_disk :: (staging: *Batch_Staging, state: *Document_State, observation: Disk_Observation, resulting: [] u8) -> bool {
	if !known_context(staging, observation.syntax_context) {
		return argument(staging, .INCONSISTENT_BINDING, "disk", "context");
	}


	if !valid_provenance(staging, observation.provenance) {
		return false;
	}


	if observation.kind == .ABSENT {
		if !bytes_equal(observation.provider_revision, resulting) {
			return argument(staging, .INCONSISTENT_BINDING, "disk", "provider_revision");
		}


		if state.disk.source {
			release_source(state.disk.source);
		}

		state.disk = .{
			kind = .ABSENT,
			syntax_context = own(staging, observation.syntax_context),
			provenance = owned_provenance(staging, observation.provenance),
		};
		return true;
	}


	source := stage_source(staging, observation.source, "disk", "source");
	if !source {
		return false;
	}


	if !bytes_equal(source.revision, observation.source_revision) {
		release_source(source);
		return argument(staging, .INCONSISTENT_BINDING, "disk", "source_revision");
	}


	if state.disk.source {
		release_source(state.disk.source);
	}

	state.disk = .{
		kind = .PRESENT,
		source = source,
		syntax_context = own(staging, observation.syntax_context),
		provenance = owned_provenance(staging, observation.provenance),
	};
	return true;
}

owned_provenance :: (staging: *Batch_Staging, provenance: Observation_Provenance) -> Observation_Provenance {
	result := provenance;
	result.provider_identity = own(staging, provenance.provider_identity);
	result.observation_token = own(staging, provenance.observation_token);
	result.consistency.provider_namespace = own(staging, provenance.consistency.provider_namespace);
	result.consistency.capture_token = own(staging, provenance.consistency.capture_token);
	return result;
}

valid_confirmation :: (staging: *Batch_Staging, event: Document_Event, action: Confirmation_Action) -> bool {
	confirmation := event.host_confirmation;
	return confirmation.action == action
		&& confirmation.confirmation_token.count
		&& bytes_equal(confirmation.host_authority, staging.model.host_authority)
		&& bytes_equal(confirmation.document, event.document)
		&& expected_equal(confirmation.expected_provider_state, event.expected_provider_state);
}

clear_overlay :: (state: *Document_State) {
	if state.has_overlay {
		release_source(state.overlay.source);
		state.has_overlay = false;
		state.overlay = .{};
	}
}

install_overlay :: (staging: *Batch_Staging, state: *Document_State, source: *Source_Backing, event: Document_Event, origin: Overlay_Origin) {
	clear_overlay(state);
	state.has_overlay = true;
	state.overlay = .{
		installation_revision = own(staging, event.resulting_provider_revision),
		source = source,
		syntax_context = own(staging, event.source_context),
		origin = origin,
	};
}

stage_event :: (staging: *Batch_Staging, event: Document_Event, existing: *Document_State) -> bool {
	model := staging.model;
	if event.kind == .RENAME {
		staging.error.event_tag = "RENAME";
		return reject(staging, .UNSUPPORTED_EVENT);
	}


	if !valid_document_key(model, event.document) {
		return argument(staging, .INCONSISTENT_BINDING, "document");
	}


	// The expected state is checked against the authoritative tracked state before anything is acquired.
	if event.expected_provider_state.kind == .UNTRACKED {
		if existing {
			return base_mismatch(staging, .DOCUMENT, event.document);
		}


		if event.kind != .SET_OVERLAY && event.kind != .OBSERVE_DISK && event.kind != .RESTORE_OVERLAY {
			return base_mismatch(staging, .DOCUMENT, event.document);
		}
	} else if !existing || !bytes_equal(existing.provider_revision, event.expected_provider_state.revision) {
		return base_mismatch(staging, .DOCUMENT, event.document);
	}


	if existing {
		if event.binding && !bindings_equal(event.binding.*, existing.binding) {
			return argument(staging, .INCONSISTENT_BINDING, "binding");
		}
	} else {
		if !event.binding {
			return argument(staging, .MISSING, "binding");
		}


		binding := event.binding.*;
		platform_ok := (binding.absolute_path.encoding == .WINDOWS_UTF16LE) == (model.descriptor.path_platform == .WINDOWS_UTF16LE);
		if (!bytes_equal(binding.document, event.document) || binding.provider_policy_version != model.descriptor.document_policy_version
			|| !platform_ok || !path_is_valid(binding.absolute_path)
		) {
			return argument(staging, .INCONSISTENT_BINDING, "binding");
		}


		if !within_limit(model.limits, .PATH_BYTES, binding.absolute_path.code_units.count) {
			return limit(staging, .PATH_BYTES);
		}
	}


	revision_ok, revision_fields := key_fields(event.resulting_provider_revision, "provider-revision", 4);
	if (!revision_ok || !bytes_equal(revision_fields[0], model.provider_namespace) || !bytes_equal(revision_fields[1], model.session.([] u8))
		|| !bytes_equal(revision_fields[2], event.document) || !revision_fields[3].count
	) {
		return argument(staging, .INCONSISTENT_BINDING, "resulting_provider_revision");
	}


	if existing {
		for existing.used_revisions {
			if bytes_equal(it, event.resulting_provider_revision) {
				return argument(staging, .DUPLICATE, "resulting_provider_revision");
			}
		}
	}


	if !known_context(staging, event.source_context) {
		return argument(staging, .INCONSISTENT_BINDING, "source_context");
	}


	// Stage a private copy of the tracked state; the model is untouched until commit.
	state := New(Document_State);
	array_add(*staging.states, state);
	if existing {
		used_revisions: [..] [] u8;
		array_add(*used_revisions, ..existing.used_revisions);
		state.* = existing.*;
		state.used_revisions = used_revisions;
		if state.disk.source {
			retain_source(state.disk.source);
		}

		if state.has_overlay {
			retain_source(state.overlay.source);
		}
	} else {
		state.document = own(staging, event.document);
		state.binding = event.binding.*;
		state.binding.document = state.document;
		state.binding.absolute_path.code_units = own(staging, event.binding.absolute_path.code_units);
	}

	if event.kind == {
		case .SET_OVERLAY;
			source := stage_source(staging, event.source, "source");
			if !source {
				return false;
			}


			install_overlay(staging, state, source, event, .ACTIVE);

		case .EDIT_OVERLAY;
			if !state.has_overlay {
				return base_mismatch(staging, .OVERLAY, event.document);
			}


			if !bytes_equal(event.base_source_revision, state.overlay.source.revision) {
				return base_mismatch(staging, .SOURCE, event.document);
			}


			if !event.edits.count {
				return argument(staging, .MISSING, "edits");
			}


			if !within_limit(model.limits, .EDITS_PER_EVENT, event.edits.count) {
				return limit(staging, .EDITS_PER_EVENT);
			}


			// Each edit's range applies to the intermediate result of the edits before it.
			current := array_copy(state.overlay.source.bytes,, temp);
			for edit: event.edits {
				if edit.start_byte > edit.end_byte || edit.end_byte > xx current.count {
					array_add(*staging.path, .{kind = .FIELD, name = "edits"}, .{kind = .ELEMENT, index = it_index});
					return argument(staging, .OUT_OF_RANGE);
				}


				removed := (edit.end_byte - edit.start_byte).(s64);
				if current.count - removed > model.limits.values[Limit_Name.SOURCE_BYTES] - edit.replacement.count {
					return limit(staging, .SOURCE_BYTES);
				}


				next := NewArray(current.count - removed + edit.replacement.count, u8,, temp);
				start := edit.start_byte.(s64);
				memcpy(next.data, current.data, start);
				memcpy(next.data + start, edit.replacement.data, edit.replacement.count);
				memcpy(next.data + start + edit.replacement.count, current.data + edit.end_byte.(s64), current.count - edit.end_byte.(s64));
				current = next;
			}

			origin := state.overlay.origin;
			install_overlay(staging, state, new_source(current), event, origin);

		case .OBSERVE_DISK;
			if !stage_disk(staging, state, event.disk, event.resulting_provider_revision) {
				return false;
			}

		case .ACK_SAVE;
			if event.disk.kind != .PRESENT {
				return argument(staging, .WRONG_KIND, "disk");
			}


			if !stage_disk(staging, state, event.disk, event.resulting_provider_revision) {
				return false;
			}


			if !bytes_equal(event.written_source_revision, state.disk.source.revision) {
				return argument(staging, .INCONSISTENT_BINDING, "written_source_revision");
			}


			// Only the overlay installation the host saved is cleared, and only if its bytes are what was written.
			if state.has_overlay && bytes_equal(state.overlay.installation_revision, event.expected_overlay_revision) {
				if !bytes_equal(state.overlay.source.revision, event.written_source_revision) {
					return argument(staging, .INCONSISTENT_BINDING, "expected_overlay_revision");
				}


				clear_overlay(state);
			}

		case .RESET_OVERLAY;
			confirmation := event.host_confirmation;
			if !valid_confirmation(staging, event, .RESET) || confirmation.source_revision.count || confirmation.recovery_candidate.count {
				return argument(staging, .INVALID_CONFIRMATION, "host_confirmation");
			}


			if !stage_disk(staging, state, event.disk, event.resulting_provider_revision) {
				return false;
			}


			clear_overlay(state);

		case .RESTORE_OVERLAY;
			source := stage_source(staging, event.source, "source");
			if !source {
				return false;
			}


			confirmation := event.host_confirmation;
			if (!valid_confirmation(staging, event, .RESTORE) || !bytes_equal(confirmation.source_revision, source.revision)
				|| !event.recovery_candidate.count || !bytes_equal(confirmation.recovery_candidate, event.recovery_candidate)
			) {
				release_source(source);
				return argument(staging, .INVALID_CONFIRMATION, "host_confirmation");
			}


			install_overlay(staging, state, source, event, .RESTORED);
	}


	// The event's context names the resulting selection; an older acknowledged disk context may differ under a newer overlay.
	selected := selected_document(state);
	if (selected.kind != .PRESENT && selected.kind != .ABSENT) || !bytes_equal(selected.syntax_context, event.source_context) {
		return argument(staging, .INCONSISTENT_BINDING, "source_context");
	}


	state.provider_revision = own(staging, event.resulting_provider_revision);
	array_add(*state.used_revisions, state.provider_revision);
	return true;
}
