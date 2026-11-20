Owned_Allocation :: struct {
	previous: *Owned_Allocation;
	next: *Owned_Allocation;
	size: s64;
	heap: *Owned_Heap;
}

Owned_Heap :: struct {
	gate: Mutex;
	service: *Service;
	delegate: Allocator;
	first: *Owned_Allocation;
	allocations: s64;
	bytes: s64;
}

#if TEST_HOOKS {
	service_test_allocator: Allocator;
}

free_description :: (description: *Session_Description) {
	free(description.session_identity.data);
	free(description.workspace.data);
	free(description.provider_namespace.data);
	free(description.accepted_frontier.data);
	free(description.clock_identity.data);
	for * description.tracked_document_states {
		free(it.document.data);
		free(it.provider_revision.data);
		free(it.binding.document.data);
		free(it.binding.absolute_path.code_units.data);
		free(it.disk_source_revision.data);
		free(it.disk_context.data);
		free(it.overlay_installation_revision.data);
		free(it.overlay_source_revision.data);
		free(it.overlay_context.data);
	}

	free(description.tracked_document_states.data);
	description.* = .{};
}

#scope_module

owner_allocator :: (session: *Session) -> Allocator {
	return .{proc = owned_allocate, data = *session.heap};
}

use_owner_memory :: (session: *Session) #expand {
	previous_allocator := context.allocator;
	previous_output := context.cache_service_output_allocator;
	context.cache_service_output_allocator = previous_allocator;
	context.allocator = owner_allocator(session);
	`defer {
		context.allocator = previous_allocator;
		context.cache_service_output_allocator = previous_output;
	}
}

try_output_array :: (allocator: Allocator, count: s64, $T: Type) -> bool, [] T {
	if count < 0 || count > S64_MAX / size_of(T) {
		return false, .[];
	}


	if !count {
		return true, .[];
	}


	size := count * size_of(T);
	memory := allocator.proc(.ALLOCATE, size, 0, null, allocator.data);
	if !memory {
		return false, .[];
	}


	memset(memory, 0, size);
	return true, .{count = count, data = memory.(*T)};
}

try_output_key :: (allocator: Allocator, tag: string, fields: .. [] u8) -> bool, [] u8 {
	count := 8 + KEY_MAGIC.count + 4 + 8 + tag.count + 8;
	for fields {
		if it.count < 0 || count > S64_MAX - 8 || it.count > S64_MAX - count - 8 {
			return false, .[];
		}


		count += 8 + it.count;
	}


	ok, storage := try_output_array(allocator, count, u8);
	if !ok {
		return false, .[];
	}


	encoded: [..] u8;
	encoded.data = storage.data;
	encoded.allocated = storage.count;
	append_framed(*encoded, KEY_MAGIC.([] u8));
	append_u32_le(*encoded, KEY_SCHEMA_VERSION);
	append_framed(*encoded, tag.([] u8));
	append_u64_le(*encoded, xx fields.count);
	for fields {
		append_framed(*encoded, it);
	}

	assert(encoded.count == storage.count);
	return true, storage;
}

#if TEST_HOOKS {
	shutdown_reserve_allocate :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, data: *void) -> *void {
		session := data.(*Session);
		if mode == .ALLOCATE || mode == .RESIZE {
			attempt := atomic_add(*session.service.shutdown_reserve_attempts, 1) + 1;
			if attempt == session.service.fail_shutdown_reserve_at {
				return null;
			}
		}

		allocator := owner_allocator(session);
		return allocator.proc(mode, size, old_size, old_memory, allocator.data);
	}
}

prepare_shutdown_backing :: (session: *Session) -> bool {
	allocator := owner_allocator(session);
	#if TEST_HOOKS {
		allocator = .{proc = shutdown_reserve_allocate, data = session};
	}

	ok, slots := try_output_array(allocator, 2, Registration_Slot);
	if !ok {
		return false;
	}


	session.registry.slots.data = slots.data;
	session.registry.slots.count = slots.count;
	session.registry.slots.allocated = slots.count;
	slots[0] = .{generation = 1, kind = .SESSION};
	slots[1] = .{generation = 1, kind = .SHUTDOWN};
	registrations_ok, registrations := try_output_array(allocator, 2, *Registration);
	if !registrations_ok {
		return false;
	}


	session.registrations.data = registrations.data;
	session.registrations.count = registrations.count;
	session.registrations.allocated = registrations.count;
	for * registrations {
		ok, storage := try_output_array(allocator, 1, Registration);
		if !ok {
			return false;
		}


		it.* = storage.data;
	}


	operations_ok, operations := try_output_array(allocator, 1, Operation);
	if !operations_ok {
		return false;
	}


	session.shutdown_control = operations.data;
	token: [8] u8;
	identity_ok, identity := try_output_key(allocator, "operation", session.identities.session.([] u8), token);
	if !identity_ok {
		return false;
	}


	session.shutdown_control.identity = xx identity;
	session.shutdown_registration = .{
		session = session.identities.session,
		slot = 1,
		generation = 1,
		owner_service = session.service,
		owner_token = session.registry.owner_token,
	};

	return true;
}

try_source_batch_pool :: (allocator: Allocator = context.allocator) -> *Pool {
	ok, storage := try_output_array(allocator, 1, Pool);
	if !ok {
		return null;
	}


	storage.data.* = .{};
	return storage.data;
}

try_source_batch_metadata_storage :: (pool: *Pool, count: s64) -> bool, [] u8 {
	if count < 0 {
		return false, .[];
	}


	if !count {
		return true, .[];
	}


	header_size :: size_of(type_of(pool.current_memblock.*));
	if (pool.alignment <= 0 || pool.alignment > 0x80000000
		|| (pool.alignment & (pool.alignment - 1))
		|| count > S64_MAX - header_size - (pool.alignment - 1)
	) {
		return false, .[];
	}


	if !pool.block_allocator.proc {
		set_allocators(pool);
	}

	if count < pool.oversized_size {
		if count > pool.memblock_size - header_size - (pool.alignment - 1) {
			return false, .[];
		}


		offset := (pool.current_pos.(u64) & (pool.alignment - 1).(u64)).(s64);
		bump := (pool.alignment - offset) & (pool.alignment - 1);
		if pool.bytes_left < count + bump && !pool.unused_memblocks {
			ok, storage := try_output_array(pool.block_allocator, pool.memblock_size, u8);
			if !ok {
				return false, .[];
			}


			block := storage.data.(type_of(pool.unused_memblocks));
			block.next = null;
			if pool.overwrite_memory {
				memset(storage.data + header_size, 0xCC, storage.count - header_size);
			}

			pool.unused_memblocks = block;
		}
	}


	ok, copied := try_output_array(.{proc = pool_allocator_proc, data = pool}, count, u8);
	return ok, copied;
}

try_source_batch_metadata :: (pool: *Pool, source: [] u8) -> bool, [] u8 {
	ok, storage := try_source_batch_metadata_storage(pool, source.count);
	if ok && source.count {
		memcpy(storage.data, source.data, source.count);
	}

	return ok, storage;
}

source_batch_metadata_pool_allocate :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, data: *void) -> *void {
	if mode == .ALLOCATE || mode == .RESIZE {
		ok, storage := try_source_batch_metadata_storage(data.(*Pool), size);
		if !ok {
			return null;
		}


		if mode == .RESIZE && old_size && size {
			memcpy(storage.data, old_memory, min(old_size, size));
		}

		return storage.data;
	}


	return pool_allocator_proc(mode, size, old_size, old_memory, data);
}

Source_Batch_Metadata_Allocation :: struct {
	session: *Session;
	storage: *Pool;
}

try_source_batch_frontier :: (model: *Provider_Model, allocator: Allocator = context.allocator) -> bool, [] u8, Identity_Counter {
	counter := model.frontier_counter;
	ok, token := issue_token(*counter);
	if !ok {
		return false, .[], model.frontier_counter;
	}


	encoded: [8] u8;
	for 0..7 {
		encoded[it] = xx ((token >> (8 * it)) & 0xFF);
	}

	identity_ok, identity := try_output_key(allocator, "provider-frontier", model.provider_namespace, model.session.([] u8), encoded);
	if !identity_ok {
		return false, .[], model.frontier_counter;
	}


	return true, identity, counter;
}

Source_Batch_Commit_Backing :: struct {
	documents: [] *Document_State;
	contexts: [] Admitted_Context;
}

try_source_batch_commit :: (
	model: *Provider_Model,
	additional_documents: s64,
	additional_contexts: s64,
	allocator: Allocator = context.allocator
) -> bool, Source_Batch_Commit_Backing {
	result: Source_Batch_Commit_Backing;
	if (additional_documents < 0 || additional_contexts < 0
		|| model.documents.count > S64_MAX - additional_documents
		|| model.contexts.count > S64_MAX - additional_contexts
	) {
		return false, result;
	}


	document_count := model.documents.count + additional_documents;
	context_count := model.contexts.count + additional_contexts;
	if document_count > model.documents.allocated {
		capacity := max(8, document_count);
		if model.documents.allocated <= S64_MAX / 2 {
			capacity = max(capacity, model.documents.allocated * 2);
		}

		ok, storage := try_output_array(allocator, capacity, *Document_State);
		if !ok {
			return false, result;
		}


		if model.documents.count {
			memcpy(storage.data, model.documents.data, model.documents.count * size_of(*Document_State));
		}

		result.documents = storage;
	}


	if context_count > model.contexts.allocated {
		capacity := max(8, context_count);
		if model.contexts.allocated <= S64_MAX / 2 {
			capacity = max(capacity, model.contexts.allocated * 2);
		}

		ok, storage := try_output_array(allocator, capacity, Admitted_Context);
		if !ok {
			free(result.documents.data,, allocator);
			return false, .{};
		}


		if model.contexts.count {
			memcpy(storage.data, model.contexts.data, model.contexts.count * size_of(Admitted_Context));
		}

		result.contexts = storage;
	}


	return true, result;
}

try_source_batch_references :: (event_count: s64, allocator: Allocator = context.allocator) -> bool, [..] [] u8 {
	result: [..] [] u8;
	if event_count < 0 || event_count > S64_MAX / 2 {
		return false, result;
	}


	ok, storage := try_output_array(allocator, event_count * 2, [] u8);
	if !ok {
		return false, result;
	}


	result.data = storage.data;
	result.allocated = storage.count;
	result.allocator = allocator;
	return true, result;
}

try_source_batch_revisions :: (existing: *Document_State, allocator: Allocator = context.allocator) -> bool, [..] [] u8 {
	result: [..] [] u8;
	count := ifx existing
		then existing.used_revisions.count
		else 0;
	if count == S64_MAX {
		return false, result;
	}


	ok, storage := try_output_array(allocator, count + 1, [] u8);
	if !ok {
		return false, result;
	}


	result.data = storage.data;
	result.count = count;
	result.allocated = storage.count;
	result.allocator = allocator;
	if existing {
		memcpy(result.data, existing.used_revisions.data, count * size_of([] u8));
	}

	return true, result;
}

try_source_batch_storage :: (model: *Provider_Model, allocator: Allocator = context.allocator) -> bool {
	if model.batch_storage.count < model.batch_storage.allocated {
		return true;
	}


	if model.batch_storage.count > S64_MAX / 2 {
		return false;
	}


	capacity := max(8, model.batch_storage.count * 2);
	ok, storage := try_output_array(allocator, capacity, *Pool);
	if !ok {
		return false;
	}


	previous := model.batch_storage;
	memcpy(storage.data, previous.data, previous.count * size_of(*Pool));
	model.batch_storage.data = storage.data;
	model.batch_storage.allocated = storage.count;
	model.batch_storage.allocator = allocator;
	array_free(previous);
	return true;
}

#if TEST_HOOKS {
	source_batch_revisions_allocate :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, data: *void) -> *void {
		session := data.(*Session);
		if mode == .ALLOCATE || mode == .RESIZE {
			hook := session.faults.source_batch_revisions_allocation_hook;
			if hook && !hook(size, session.faults.source_batch_revisions_allocation_data) {
				return null;
			}
		}


		allocator := owner_allocator(session);
		return allocator.proc(mode, size, old_size, old_memory, allocator.data);
	}

	source_batch_metadata_allocate :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, data: *void) -> *void {
		allocation := data.(*Source_Batch_Metadata_Allocation);
		if mode == .ALLOCATE || mode == .RESIZE {
			hook := allocation.session.faults.source_batch_metadata_allocation_hook;
			if hook && !hook(size, allocation.session.faults.source_batch_metadata_allocation_data) {
				return null;
			}
		}


		return source_batch_metadata_pool_allocate(mode, size, old_size, old_memory, allocation.storage);
	}

	source_batch_frontier_allocate :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, data: *void) -> *void {
		session := data.(*Session);
		if mode == .ALLOCATE || mode == .RESIZE {
			hook := session.faults.source_batch_frontier_allocation_hook;
			if hook && !hook(size, session.faults.source_batch_frontier_allocation_data) {
				return null;
			}
		}


		allocator := owner_allocator(session);
		return allocator.proc(mode, size, old_size, old_memory, allocator.data);
	}

	source_batch_commit_allocate :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, data: *void) -> *void {
		session := data.(*Session);
		if mode == .ALLOCATE || mode == .RESIZE {
			hook := session.faults.source_batch_commit_allocation_hook;
			if hook && !hook(size, session.faults.source_batch_commit_allocation_data) {
				return null;
			}
		}


		allocator := owner_allocator(session);
		return allocator.proc(mode, size, old_size, old_memory, allocator.data);
	}

	source_batch_path_allocate :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, data: *void) -> *void {
		session := data.(*Session);
		if mode == .ALLOCATE || mode == .RESIZE {
			hook := session.faults.source_batch_path_allocation_hook;
			if hook && !hook(size, session.faults.source_batch_path_allocation_data) {
				return null;
			}
		}


		allocator := owner_allocator(session);
		return allocator.proc(mode, size, old_size, old_memory, allocator.data);
	}

	source_batch_context_list_allocate :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, data: *void) -> *void {
		session := data.(*Session);
		if mode == .ALLOCATE || mode == .RESIZE {
			hook := session.faults.source_batch_context_list_allocation_hook;
			if hook && !hook(size, session.faults.source_batch_context_list_allocation_data) {
				return null;
			}
		}


		allocator := owner_allocator(session);
		return allocator.proc(mode, size, old_size, old_memory, allocator.data);
	}

	source_batch_reference_list_allocate :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, data: *void) -> *void {
		session := data.(*Session);
		if mode == .ALLOCATE || mode == .RESIZE {
			hook := session.faults.source_batch_reference_list_allocation_hook;
			if hook && !hook(size, session.faults.source_batch_reference_list_allocation_data) {
				return null;
			}
		}


		allocator := owner_allocator(session);
		return allocator.proc(mode, size, old_size, old_memory, allocator.data);
	}

	source_batch_state_list_allocate :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, data: *void) -> *void {
		session := data.(*Session);
		if mode == .ALLOCATE || mode == .RESIZE {
			hook := session.faults.source_batch_state_list_allocation_hook;
			if hook && !hook(size, session.faults.source_batch_state_list_allocation_data) {
				return null;
			}
		}


		allocator := owner_allocator(session);
		return allocator.proc(mode, size, old_size, old_memory, allocator.data);
	}

	source_batch_edit_allocate :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, data: *void) -> *void {
		session := data.(*Session);
		if mode == .ALLOCATE || mode == .RESIZE {
			hook := session.faults.source_batch_edit_allocation_hook;
			if hook && !hook(size, session.faults.source_batch_edit_allocation_data) {
				return null;
			}
		}


		allocator := owner_allocator(session);
		return allocator.proc(mode, size, old_size, old_memory, allocator.data);
	}

	source_batch_source_identity_allocate :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, data: *void) -> *void {
		session := data.(*Session);
		if mode == .ALLOCATE || mode == .RESIZE {
			hook := session.faults.source_batch_source_identity_allocation_hook;
			if hook && !hook(size, session.faults.source_batch_source_identity_allocation_data) {
				return null;
			}
		}


		allocator := owner_allocator(session);
		return allocator.proc(mode, size, old_size, old_memory, allocator.data);
	}

	source_batch_source_bytes_allocate :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, data: *void) -> *void {
		session := data.(*Session);
		if mode == .ALLOCATE || mode == .RESIZE {
			hook := session.faults.source_batch_source_bytes_allocation_hook;
			if hook && !hook(size, session.faults.source_batch_source_bytes_allocation_data) {
				return null;
			}
		}


		allocator := owner_allocator(session);
		return allocator.proc(mode, size, old_size, old_memory, allocator.data);
	}

	source_batch_source_allocate :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, data: *void) -> *void {
		session := data.(*Session);
		if mode == .ALLOCATE || mode == .RESIZE {
			hook := session.faults.source_batch_source_allocation_hook;
			if hook && !hook(size, session.faults.source_batch_source_allocation_data) {
				return null;
			}
		}


		allocator := owner_allocator(session);
		return allocator.proc(mode, size, old_size, old_memory, allocator.data);
	}

	source_batch_state_allocate :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, data: *void) -> *void {
		session := data.(*Session);
		if mode == .ALLOCATE || mode == .RESIZE {
			hook := session.faults.source_batch_state_allocation_hook;
			if hook && !hook(size, session.faults.source_batch_state_allocation_data) {
				return null;
			}
		}


		allocator := owner_allocator(session);
		return allocator.proc(mode, size, old_size, old_memory, allocator.data);
	}

	source_batch_storage_allocate :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, data: *void) -> *void {
		session := data.(*Session);
		if mode == .ALLOCATE || mode == .RESIZE {
			hook := session.faults.source_batch_storage_allocation_hook;
			if hook && !hook(size, session.faults.source_batch_storage_allocation_data) {
				return null;
			}
		}


		allocator := owner_allocator(session);
		return allocator.proc(mode, size, old_size, old_memory, allocator.data);
	}

	source_batch_pool_allocate :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, data: *void) -> *void {
		session := data.(*Session);
		if mode == .ALLOCATE || mode == .RESIZE {
			hook := session.faults.source_batch_pool_allocation_hook;
			if hook && !hook(size, session.faults.source_batch_pool_allocation_data) {
				return null;
			}
		}


		allocator := owner_allocator(session);
		return allocator.proc(mode, size, old_size, old_memory, allocator.data);
	}
}

Source_Provider_Backing :: struct {
	model: *Provider_Model;
	documents: [] *Document_State;
	contexts: [] Admitted_Context;
	states_count: s64;
}

#if TEST_HOOKS {
	source_provider_allocate :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, data: *void) -> *void {
		session := data.(*Session);
		if mode == .ALLOCATE || mode == .RESIZE {
			hook := session.faults.source_provider_allocation_hook;
			if hook && !hook(size, session.faults.source_provider_allocation_data) {
				return null;
			}
		}


		allocator := owner_allocator(session);
		return allocator.proc(mode, size, old_size, old_memory, allocator.data);
	}
}

prepare_source_provider_backing :: (session: *Session, backing: *Source_Provider_Backing) -> bool {
	allocator := owner_allocator(session);
	#if TEST_HOOKS {
		allocator = .{proc = source_provider_allocate, data = session};
	}

	ok: bool;
	unlock(
		*session.gate,
		#code {
			prepared, storage := try_output_array(allocator, 1, Provider_Model);
			ok = prepared;
			backing.model = storage.data;
		}
	);

	return ok;
}

source_provider_arrays_ready :: (session: *Session, backing: *Source_Provider_Backing) -> bool {
	return backing.documents.count >= session.provider.documents.count
		&& backing.contexts.count >= session.provider.contexts.count;
}

#if TEST_HOOKS {
	source_provider_arrays_allocate :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, data: *void) -> *void {
		session := data.(*Session);
		if mode == .ALLOCATE || mode == .RESIZE {
			hook := session.faults.source_provider_arrays_allocation_hook;
			if hook && !hook(size, session.faults.source_provider_arrays_allocation_data) {
				return null;
			}
		} else if mode == .FREE && old_memory {
			hook := session.faults.source_provider_arrays_cleanup_hook;
			if hook {
				hook(size, session.faults.source_provider_arrays_cleanup_data);
			}
		}


		allocator := owner_allocator(session);
		return allocator.proc(mode, size, old_size, old_memory, allocator.data);
	}
}

prepare_source_provider_arrays :: (session: *Session, backing: *Source_Provider_Backing) -> bool {
	documents_count := session.provider.documents.count;
	contexts_count := session.provider.contexts.count;
	need_documents := backing.documents.count < documents_count;
	need_contexts := backing.contexts.count < contexts_count;
	candidate: Source_Provider_Backing;
	defer finish_source_provider_backing(session, *candidate);

	allocator := owner_allocator(session);
	#if TEST_HOOKS {
		allocator = .{proc = source_provider_arrays_allocate, data = session};
	}

	ok := true;
	unlock(
		*session.gate,
		#code {
			if need_documents {
				ok, candidate.documents = try_output_array(allocator, documents_count, *Document_State);
			}

			if ok && need_contexts {
				ok, candidate.contexts = try_output_array(allocator, contexts_count, Admitted_Context);
			}
		}
	);

	if !ok {
		return false;
	}


	if backing.documents.count < session.provider.documents.count && candidate.documents.count >= session.provider.documents.count {
		memcpy(candidate.documents.data, backing.documents.data, backing.states_count * size_of(*Document_State));
		backing.documents, candidate.documents = candidate.documents, backing.documents;
	}

	if backing.contexts.count < session.provider.contexts.count && candidate.contexts.count >= session.provider.contexts.count {
		backing.contexts, candidate.contexts = candidate.contexts, backing.contexts;
	}

	return true;
}

source_provider_states_ready :: (session: *Session, backing: *Source_Provider_Backing) -> bool {
	return backing.states_count == session.provider.documents.count;
}

#if TEST_HOOKS {
	source_provider_states_allocate :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, data: *void) -> *void {
		session := data.(*Session);
		if mode == .ALLOCATE || mode == .RESIZE {
			hook := session.faults.source_provider_states_allocation_hook;
			if hook && !hook(size, session.faults.source_provider_states_allocation_data) {
				return null;
			}
		} else if mode == .FREE && old_memory {
			hook := session.faults.source_provider_states_cleanup_hook;
			if hook {
				hook(size, session.faults.source_provider_states_cleanup_data);
			}
		}


		allocator := owner_allocator(session);
		return allocator.proc(mode, size, old_size, old_memory, allocator.data);
	}
}

source_provider_revisions_ready :: (session: *Session, backing: *Source_Provider_Backing) -> bool {
	if !source_provider_states_ready(session, backing) {
		return false;
	}


	for session.provider.documents {
		if backing.documents[it_index].used_revisions.allocated < it.used_revisions.count {
			return false;
		}
	}


	return true;
}

#if TEST_HOOKS {
	source_provider_revisions_allocate :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, data: *void) -> *void {
		session := data.(*Session);
		if mode == .ALLOCATE || mode == .RESIZE {
			hook := session.faults.source_provider_revisions_allocation_hook;
			if hook && !hook(size, session.faults.source_provider_revisions_allocation_data) {
				return null;
			}
		} else if mode == .FREE && old_memory {
			hook := session.faults.source_provider_revisions_cleanup_hook;
			if hook {
				hook(size, session.faults.source_provider_revisions_cleanup_data);
			}
		}


		allocator := owner_allocator(session);
		return allocator.proc(mode, size, old_size, old_memory, allocator.data);
	}
}

finish_source_provider_revisions :: (session: *Session, backing: *Source_Provider_Backing) {
	allocator := owner_allocator(session);
	#if TEST_HOOKS {
		allocator = .{proc = source_provider_revisions_allocate, data = session};
	}

	unlock(
		*session.gate,
		#code {
			for 0..backing.states_count - 1 {
				copy := backing.documents[it];
				revisions := copy.used_revisions;
				empty: [..] [] u8;
				copy.used_revisions = empty;
				free(revisions.data,, allocator);
			}
		}
	);
}

finish_source_provider_revision_storage :: (session: *Session, storage: [] [] u8) {
	allocator := owner_allocator(session);
	#if TEST_HOOKS {
		allocator = .{proc = source_provider_revisions_allocate, data = session};
	}

	unlock(
		*session.gate,
		#code {
			free(storage.data,, allocator);
		}
	);
}

prepare_source_provider_revisions :: (session: *Session, backing: *Source_Provider_Backing) -> bool {
	if !source_provider_states_ready(session, backing) {
		return true;
	}


	index: s64 = -1;
	count: s64;
	for session.provider.documents {
		if backing.documents[it_index].used_revisions.allocated < it.used_revisions.count {
			index = it_index;
			count = it.used_revisions.count;
			break;
		}
	}

	if index < 0 {
		return true;
	}


	allocator := owner_allocator(session);
	#if TEST_HOOKS {
		allocator = .{proc = source_provider_revisions_allocate, data = session};
	}

	storage: [] [] u8;
	defer finish_source_provider_revision_storage(session, storage);

	ok: bool;
	unlock(
		*session.gate,
		#code {
			ok, storage = try_output_array(allocator, count, [] u8);
		}
	);

	if !ok {
		finish_source_provider_revisions(session, backing);
		return false;
	}


	if (
		source_provider_states_ready(session, backing)
		&& index < session.provider.documents.count
		&& storage.count >= session.provider.documents[index].used_revisions.count
	) {
		copy := backing.documents[index];
		old_storage := copy.used_revisions.data;
		old_count := copy.used_revisions.allocated;
		copy.used_revisions.data = storage.data;
		copy.used_revisions.allocated = storage.count;
		copy.used_revisions.allocator = owner_allocator(session);
		storage = .{data = old_storage, count = old_count};
	}

	return true;
}

finish_source_provider_states :: (session: *Session, backing: *Source_Provider_Backing) {
	finish_source_provider_revisions(session, backing);
	allocator := owner_allocator(session);
	#if TEST_HOOKS {
		allocator = .{proc = source_provider_states_allocate, data = session};
	}

	unlock(
		*session.gate,
		#code {
			while backing.states_count {
				backing.states_count -= 1;
				free(backing.documents[backing.states_count],, allocator);
				backing.documents[backing.states_count] = null;
			}
		}
	);
}

prepare_source_provider_states :: (session: *Session, backing: *Source_Provider_Backing) -> bool {
	count := session.provider.documents.count;
	if count > backing.documents.count {
		return false;
	}


	allocator := owner_allocator(session);
	revisions_allocator := allocator;
	#if TEST_HOOKS {
		allocator = .{proc = source_provider_states_allocate, data = session};
		revisions_allocator = .{proc = source_provider_revisions_allocate, data = session};
	}

	ok := true;
	unlock(
		*session.gate,
		#code {
			while backing.states_count > count {
				backing.states_count -= 1;
				free(backing.documents[backing.states_count].used_revisions.data,, revisions_allocator);
				free(backing.documents[backing.states_count],, allocator);
				backing.documents[backing.states_count] = null;
			}

			while backing.states_count < count {
				prepared, storage := try_output_array(allocator, 1, Document_State);
				if !prepared {
					ok = false;
					break;
				}


				backing.documents[backing.states_count] = storage.data;
				backing.states_count += 1;
			}
		}
	);

	if !ok {
		finish_source_provider_states(session, backing);
	}

	return ok;
}

finish_source_provider_backing :: (session: *Session, backing: *Source_Provider_Backing) {
	finish_source_provider_states(session, backing);
	allocator := owner_allocator(session);
	arrays_allocator := allocator;
	#if TEST_HOOKS {
		arrays_allocator = .{proc = source_provider_arrays_allocate, data = session};
	}

	unlock(
		*session.gate,
		#code {
			free(backing.model,, allocator);
			free(backing.documents.data,, arrays_allocator);
			free(backing.contexts.data,, arrays_allocator);
		}
	);

	backing.* = .{};
}

Source_Operation_Backing :: struct {
	storage: [] *Operation;
	old_storage: [] *Operation;
}

source_operation_backing_ready :: (session: *Session) -> bool {
	return session.operations.count < session.operations.allocated;
}

finish_source_operation_backing :: (session: *Session, backing: *Source_Operation_Backing) {
	allocator := owner_allocator(session);
	#if TEST_HOOKS {
		allocator = .{proc = source_operation_allocate, data = session};
	}

	unlock(
		*session.gate,
		#code {
			free(backing.storage.data,, allocator);
			free(backing.old_storage.data,, allocator);
		}
	);
}

#if TEST_HOOKS {
	source_operation_allocate :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, data: *void) -> *void {
		session := data.(*Session);
		if mode == .ALLOCATE || mode == .RESIZE {
			hook := session.faults.source_operation_allocation_hook;
			if hook && !hook(size, session.faults.source_operation_allocation_data) {
				return null;
			}
		} else if mode == .FREE && old_memory {
			hook := session.faults.source_operation_cleanup_hook;
			if hook {
				hook(size, session.faults.source_operation_allocation_data);
			}
		}


		allocator := owner_allocator(session);
		return allocator.proc(mode, size, old_size, old_memory, allocator.data);
	}
}

prepare_source_operation_backing :: (session: *Session) -> bool {
	if source_operation_backing_ready(session) {
		return true;
	}


	count := session.operations.count;
	if count >= S64_MAX / 2 {
		return false;
	}


	capacity := max(8, (count + 1) * 2);
	backing: Source_Operation_Backing;
	defer finish_source_operation_backing(session, *backing);

	allocator := owner_allocator(session);
	#if TEST_HOOKS {
		allocator = .{proc = source_operation_allocate, data = session};
	}

	ok: bool;
	unlock(
		*session.gate,
		#code {
			ok, backing.storage = try_output_array(allocator, capacity, *Operation);
		}
	);

	if !ok {
		return false;
	}


	count = session.operations.count;
	if source_operation_backing_ready(session) || count >= capacity {
		return true;
	}


	memcpy(backing.storage.data, session.operations.data, count * size_of(*Operation));
	backing.old_storage = .{data = session.operations.data, count = count};
	session.operations.data = backing.storage.data;
	session.operations.allocated = capacity;
	backing.storage = .[];
	return true;
}

#if TEST_HOOKS {
	source_candidate_capture_allocate :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, data: *void) -> *void {
		session := data.(*Session);
		if mode == .ALLOCATE || mode == .RESIZE {
			hook := session.faults.source_candidate_capture_allocation_hook;
			if hook && !hook(size, session.faults.source_candidate_capture_allocation_data) {
				return null;
			}
		}


		allocator := owner_allocator(session);
		return allocator.proc(mode, size, old_size, old_memory, allocator.data);
	}
}

#if TEST_HOOKS {
	source_candidate_world_allocate :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, data: *void) -> *void {
		session := data.(*Session);
		if mode == .ALLOCATE || mode == .RESIZE {
			hook := session.faults.source_candidate_world_allocation_hook;
			if hook && !hook(size, session.faults.source_candidate_world_allocation_data) {
				return null;
			}
		}


		allocator := owner_allocator(session);
		return allocator.proc(mode, size, old_size, old_memory, allocator.data);
	}
}

#if TEST_HOOKS {
	source_candidate_task_allocate :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, data: *void) -> *void {
		session := data.(*Session);
		if mode == .ALLOCATE || mode == .RESIZE {
			hook := session.faults.source_candidate_task_allocation_hook;
			if hook && !hook(size, session.faults.source_candidate_task_allocation_data) {
				return null;
			}
		}


		allocator := owner_allocator(session);
		return allocator.proc(mode, size, old_size, old_memory, allocator.data);
	}
}

Source_Candidate_Join_Backing :: struct {
	task: *Task;
	operations: [] *Operation;
	ready: [] *Task;
}

prepare_source_candidate_join_backing :: (session: *Session, key: [] u8) -> bool, Source_Candidate_Join_Backing {
	world := find_candidate_world(session, key);
	if !world || world.state == .PUBLISHED {
		return true, .{};
	}


	task := find_candidate_task(session, world);
	if !task {
		return true, .{};
	}


	operations_capacity: s64;
	if task.operations.count >= task.operations.allocated {
		operations_capacity = ifx task.operations.count <= S64_MAX / 2 - 1
			then max(8, (task.operations.count + 1) * 2)
			else -1;
	}

	ready_capacity: s64;
	if task.optional && task.phase == .READY && session.ready.count >= session.ready.allocated {
		ready_capacity = ifx session.ready.count <= S64_MAX / 2 - 1
			then max(8, (session.ready.count + 1) * 2)
			else -1;
	}

	allocator := owner_allocator(session);
	#if TEST_HOOKS {
		allocator = .{proc = source_candidate_join_allocate, data = session};
	}

	ok: bool;
	backing: Source_Candidate_Join_Backing;
	unlock(
		*session.gate,
		#code {
			ok, backing = try_source_candidate_join_backing(operations_capacity, ready_capacity, allocator);
		}
	);
	backing.task = task;
	return ok, backing;
}

source_candidate_join_backing_ready :: (session: *Session, key: [] u8, backing: *Source_Candidate_Join_Backing) -> bool {
	world := find_candidate_world(session, key);
	if !world || world.state == .PUBLISHED {
		return true;
	}


	task := find_candidate_task(session, world);
	if !task {
		return !backing.task;
	}


	return task == backing.task
		&& (task.operations.count < task.operations.allocated || backing.operations.count > task.operations.count)
		&& (!task.optional || task.phase != .READY
			|| session.ready.count < session.ready.allocated || backing.ready.count > session.ready.count);
}

adopt_source_candidate_join_backing :: (session: *Session, backing: *Source_Candidate_Join_Backing) {
	task := backing.task;
	if task.operations.count >= task.operations.allocated {
		assert(backing.operations.count > task.operations.count);
		previous := task.operations;
		memcpy(backing.operations.data, previous.data, previous.count * size_of(*Operation));
		task.operations.data = backing.operations.data;
		task.operations.allocated = backing.operations.count;
		task.operations.allocator = owner_allocator(session);
		backing.operations = .{data = previous.data, count = previous.allocated};
	}

	if task.optional && task.phase == .READY {
		adopt_source_candidate_task_list(*session.ready, *backing.ready, owner_allocator(session));
	}
}

#if TEST_HOOKS {
	source_candidate_join_allocate :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, data: *void) -> *void {
		session := data.(*Session);
		if mode == .ALLOCATE || mode == .RESIZE {
			hook := session.faults.source_candidate_join_allocation_hook;
			if hook && !hook(size, session.faults.source_candidate_join_allocation_data) {
				return null;
			}
		}


		allocator := owner_allocator(session);
		return allocator.proc(mode, size, old_size, old_memory, allocator.data);
	}
}

try_source_candidate_join_backing :: (
	operations_capacity: s64,
	ready_capacity: s64,
	allocator: Allocator = context.allocator
) -> bool, Source_Candidate_Join_Backing {
	if operations_capacity < 0 || ready_capacity < 0 {
		return false, .{};
	}


	result: Source_Candidate_Join_Backing;
	accepted := false;
	defer {
		if !accepted {
			free_source_candidate_join_backing(*result, allocator);
		}
	}

	operations_ok, operations := try_output_array(allocator, operations_capacity, *Operation);
	if !operations_ok {
		return false, .{};
	}


	result.operations = operations;
	ready_ok, ready := try_output_array(allocator, ready_capacity, *Task);
	if !ready_ok {
		return false, .{};
	}


	result.ready = ready;
	accepted = true;
	return true, result;
}

finish_analysis_candidate_join_backing :: (session: *Session, backing: *Source_Candidate_Join_Backing) {
	allocator := owner_allocator(session);
	unlock(
		*session.gate,
		#code {
			free_source_candidate_join_backing(backing, allocator);
		}
	);
}

free_source_candidate_join_backing :: (backing: *Source_Candidate_Join_Backing, allocator: Allocator = context.allocator) {
	free(backing.operations.data,, allocator);
	free(backing.ready.data,, allocator);
	backing.* = .{};
}

Source_Candidate_Task_Backing :: struct {
	task: *Task;
	key: [] u8;
	world_identity_offset: s64;
	operations: [] *Operation;
	tasks: [] *Task;
	ready: [] *Task;
}

prepare_query_task_key :: (session: *Session, world: *World, member: s64, backing: *Source_Candidate_Task_Backing) -> bool {
	allocator := owner_allocator(session);
	#if TEST_HOOKS {
		allocator = .{proc = source_candidate_task_allocate, data = session};
	}

	ok: bool;
	unlock(
		*session.gate,
		#code {
			ok, backing.key = try_output_key(
				allocator,
				"execution-task",
				session.identities.session.([] u8),
				world.identity.([] u8),
				xx "QUERY_PAYLOAD",
				world.members[member].document,
				xx "SYNTAX_DIAGNOSTICS"
			);
		}
	);

	return ok;
}

find_query_task :: (session: *Session, key: [] u8) -> *Task {
	result: *Task;
	for session.tasks {
		if it.phase != .TERMINAL && bytes_equal(it.key, key) {
			result = it;
		}
	}

	return result;
}

query_new_task_backing_ready :: (session: *Session, backing: *Source_Candidate_Task_Backing) -> bool {
	return !!find_query_task(session, backing.key)
		|| backing.task && backing.operations.count && source_candidate_task_backing_ready(session, backing);
}

query_task_backing_ready :: (
	session: *Session,
	backing: *Source_Candidate_Task_Backing,
	join: *Source_Candidate_Join_Backing
) -> bool {
	task := find_query_task(session, backing.key);
	if task {
		return task.operations.count < task.operations.allocated
			|| join && join.task == task && join.operations.count > task.operations.count;
	}

	return query_new_task_backing_ready(session, backing);
}

prepare_query_task_backing :: (
	session: *Session,
	backing: *Source_Candidate_Task_Backing,
	join: *Source_Candidate_Join_Backing
) -> bool {
	task := find_query_task(session, backing.key);
	if !task {
		return prepare_query_new_task_backing(session, backing);
	}


	assert(!!join);
	if join.task {
		finish_analysis_candidate_join_backing(session, join);
		return true;
	}


	capacity := ifx task.operations.count <= S64_MAX / 2 - 1
		then max(8, (task.operations.count + 1) * 2)
		else -1;
	allocator := owner_allocator(session);
	#if TEST_HOOKS {
		allocator = .{proc = source_candidate_join_allocate, data = session};
	}

	ok: bool;
	unlock(
		*session.gate,
		#code {
			ok, join.* = try_source_candidate_join_backing(capacity, 0, allocator);
		}
	);
	join.task = task;
	return ok;
}

prepare_query_new_task_backing :: (session: *Session, backing: *Source_Candidate_Task_Backing) -> bool {
	if session.tasks.count == S64_MAX || session.ready.count == S64_MAX {
		return false;
	}


	allocator := owner_allocator(session);
	#if TEST_HOOKS {
		allocator = .{proc = source_candidate_task_allocate, data = session};
	}

	tasks_capacity := ifx session.tasks.count < session.tasks.allocated
		then 0
		else max(8, session.tasks.count + 1);
	ready_capacity := ifx session.ready.count < session.ready.allocated
		then 0
		else max(8, session.ready.count + 1);
	ok := true;
	unlock(
		*session.gate,
		#code {
			if !backing.task {
				ok, storage := try_output_array(allocator, 1, Task);
				backing.task = storage.data;
				if !ok {
					return false;
				}
			}


			if !backing.operations.count {
				ok, backing.operations = try_output_array(allocator, 1, *Operation);
				if !ok {
					return false;
				}
			}


			if tasks_capacity > backing.tasks.count {
				free(backing.tasks.data,, allocator);
				ok, backing.tasks = try_output_array(allocator, tasks_capacity, *Task);
				if !ok {
					return false;
				}
			}


			if ready_capacity > backing.ready.count {
				free(backing.ready.data,, allocator);
				ok, backing.ready = try_output_array(allocator, ready_capacity, *Task);
			}
		}
	);


	return ok;
}

try_source_candidate_task_backing :: (
	identity: Session_ID,
	world_identity: World_ID,
	tasks_capacity: s64,
	ready_capacity: s64,
	allocator: Allocator = context.allocator
) -> bool, Source_Candidate_Task_Backing {
	if tasks_capacity < 0 || ready_capacity < 0 {
		return false, .{};
	}


	result: Source_Candidate_Task_Backing;
	accepted := false;
	defer {
		if !accepted {
			free_source_candidate_task_backing(*result, allocator);
		}
	}

	task_ok, tasks := try_output_array(allocator, 1, Task);
	if !task_ok {
		return false, .{};
	}


	result.task = tasks.data;
	key_ok, key := try_output_key(allocator, "execution-task", identity.([] u8), world_identity.([] u8), xx "PARSE_INDEX");
	if !key_ok {
		return false, .{};
	}


	result.key = key;
	result.world_identity_offset = key.count - 8 - "PARSE_INDEX".count - world_identity.count;
	operations_ok, operations := try_output_array(allocator, 1, *Operation);
	if !operations_ok {
		return false, .{};
	}


	result.operations = operations;
	tasks_ok, task_storage := try_output_array(allocator, tasks_capacity, *Task);
	if !tasks_ok {
		return false, .{};
	}


	result.tasks = task_storage;
	ready_ok, ready := try_output_array(allocator, ready_capacity, *Task);
	if !ready_ok {
		return false, .{};
	}


	result.ready = ready;
	accepted = true;
	return true, result;
}

source_candidate_task_backing_ready :: (session: *Session, backing: *Source_Candidate_Task_Backing) -> bool {
	return (session.tasks.count < session.tasks.allocated || backing.tasks.count > session.tasks.count)
		&& (session.ready.count < session.ready.allocated || backing.ready.count > session.ready.count);
}

set_source_candidate_task_world :: (backing: *Source_Candidate_Task_Backing, identity: World_ID) {
	memcpy(backing.key.data + backing.world_identity_offset, identity.data, identity.count);
}

adopt_source_candidate_task_list :: (live: *[..] *Task, prepared: *[] *Task, allocator: Allocator) {
	if live.count < live.allocated {
		return;
	}


	assert(prepared.count > live.count);
	previous := live.*;
	memcpy(prepared.data, previous.data, previous.count * size_of(*Task));
	live.data = prepared.data;
	live.allocated = prepared.count;
	live.allocator = allocator;
	prepared.* = .{data = previous.data, count = previous.allocated};
}

finish_analysis_candidate_task_backing :: (session: *Session, backing: *Source_Candidate_Task_Backing) {
	allocator := owner_allocator(session);
	unlock(
		*session.gate,
		#code {
			free_source_candidate_task_backing(backing, allocator);
		}
	);
}

free_source_candidate_task_backing :: (backing: *Source_Candidate_Task_Backing, allocator: Allocator = context.allocator) {
	free(backing.task,, allocator);
	free(backing.key.data,, allocator);
	free(backing.operations.data,, allocator);
	free(backing.tasks.data,, allocator);
	free(backing.ready.data,, allocator);
	backing.* = .{};
}

Source_Candidate_World_Backing :: struct {
	world: *World;
	identity: [] u8;
	worlds: [] *World;
}

try_source_candidate_world_backing :: (
	identity: Session_ID,
	capacity: s64,
	allocator: Allocator = context.allocator
) -> bool, Source_Candidate_World_Backing {
	if capacity < 0 {
		return false, .{};
	}


	result: Source_Candidate_World_Backing;
	accepted := false;
	defer {
		if !accepted {
			free_source_candidate_world_backing(*result, allocator);
		}
	}

	world_ok, worlds := try_output_array(allocator, 1, World);
	if !world_ok {
		return false, .{};
	}


	result.world = worlds.data;
	token: [8] u8;
	identity_ok, encoded := try_output_key(allocator, "world", identity.([] u8), token);
	if !identity_ok {
		return false, .{};
	}


	result.identity = encoded;
	storage_ok, storage := try_output_array(allocator, capacity, *World);
	if !storage_ok {
		return false, .{};
	}


	result.worlds = storage;
	accepted = true;
	return true, result;
}

source_candidate_world_backing_ready :: (session: *Session, backing: *Source_Candidate_World_Backing) -> bool {
	return session.worlds.count < session.worlds.allocated || backing.worlds.count > session.worlds.count;
}

finish_analysis_candidate_world_backing :: (session: *Session, backing: *Source_Candidate_World_Backing) {
	allocator := owner_allocator(session);
	unlock(
		*session.gate,
		#code {
			free_source_candidate_world_backing(backing, allocator);
		}
	);
}

free_source_candidate_world_backing :: (backing: *Source_Candidate_World_Backing, allocator: Allocator = context.allocator) {
	free(backing.world,, allocator);
	free(backing.identity.data,, allocator);
	free(backing.worlds.data,, allocator);
	backing.* = .{};
}

Source_Candidate_Capture :: struct {
	members: [] Selected_Member;
	key: [] u8;
	consistency: Consistency;
	capturable: bool;
}

Analysis_Candidate_Snapshot :: struct {
	model: Provider_Model;
	states: [] Document_State;
	documents: [] *Document_State;
	contexts: [] Admitted_Context;
	metadata: [] u8;
}

free_analysis_candidate_snapshot :: (snapshot: *Analysis_Candidate_Snapshot, allocator: Allocator = context.allocator) {
	push_allocator(allocator);
	for * snapshot.states {
		source := selected_document(it).source;
		if source {
			release_source(source);
		}
	}

	free(snapshot.states.data,, allocator);
	free(snapshot.documents.data,, allocator);
	free(snapshot.contexts.data,, allocator);
	free(snapshot.metadata.data,, allocator);
	snapshot.* = .{};
}

try_analysis_candidate_snapshot :: (
	count: s64,
	metadata_count: s64,
	allocator: Allocator = context.allocator
) -> bool, Analysis_Candidate_Snapshot {
	if count < 0 || metadata_count < 0 {
		return false, .{};
	}


	result: Analysis_Candidate_Snapshot;
	accepted := false;
	defer {
		if !accepted {
			free_analysis_candidate_snapshot(*result, allocator);
		}
	}

	ok: bool;
	ok, result.states = try_output_array(allocator, count, Document_State);
	if !ok {
		return false, .{};
	}


	ok, result.documents = try_output_array(allocator, count, *Document_State);
	if !ok {
		return false, .{};
	}


	ok, result.contexts = try_output_array(allocator, count, Admitted_Context);
	if !ok {
		return false, .{};
	}


	ok, result.metadata = try_output_array(allocator, metadata_count, u8);
	if !ok {
		return false, .{};
	}


	accepted = true;
	return true, result;
}

analysis_candidate_metadata_count :: (model: *Provider_Model, documents: [] [] u8) -> bool, s64 {
	count: s64;
	for documents {
		state := find_document(model, it);
		if !state {
			return false, 0;
		}


		selected := selected_document(state);
		admitted := find_context(model, selected.syntax_context);
		if !admitted {
			return false, 0;
		}


		consistency: Consistency;
		if selected.provenance {
			consistency = selected.provenance.consistency;
		}

		counts := s64.[
			state.document.count,
			state.provider_revision.count,
			selected.syntax_context.count,
			admitted.paths.visible_filename.code_units.count,
			consistency.provider_namespace.count,
			consistency.capture_token.count
		];
		for counts {
			if it < 0 || it > S64_MAX - count {
				return false, 0;
			}


			count += it;
		}
	}


	return true, count;
}

analysis_snapshot_bytes :: (snapshot: *Analysis_Candidate_Snapshot, cursor: *s64, bytes: [] u8) -> [] u8 {
	assert(bytes.count >= 0 && bytes.count <= snapshot.metadata.count - cursor.*);
	result := ([] u8).{data = snapshot.metadata.data + cursor.*, count = bytes.count};
	memcpy(result.data, bytes.data, bytes.count);
	cursor.* += bytes.count;
	return result;
}

stage_analysis_candidate_snapshot :: (model: *Provider_Model, documents: [] [] u8, snapshot: *Analysis_Candidate_Snapshot) {
	assert(snapshot.states.count == documents.count);
	cursor: s64;
	for documents {
		state := find_document(model, it);
		selected := selected_document(state);
		admitted := find_context(model, selected.syntax_context);
		context_identity := analysis_snapshot_bytes(snapshot, *cursor, selected.syntax_context);
		copy := Document_State.{
			document = analysis_snapshot_bytes(snapshot, *cursor, state.document),
			provider_revision = analysis_snapshot_bytes(snapshot, *cursor, state.provider_revision),
		};
		consistency: Consistency;
		if selected.provenance {
			consistency = .{
				kind = selected.provenance.consistency.kind,
				provider_namespace = analysis_snapshot_bytes(snapshot, *cursor, selected.provenance.consistency.provider_namespace),
				capture_token = analysis_snapshot_bytes(snapshot, *cursor, selected.provenance.consistency.capture_token),
			};
		}

		if state.has_overlay {
			copy.has_overlay = true;
			copy.overlay = .{source = selected.source, syntax_context = context_identity};
		} else {
			copy.disk = .{
				kind = state.disk.kind,
				source = selected.source,
				syntax_context = context_identity,
				provenance = .{consistency = consistency},
			};
		}

		if selected.source {
			retain_source(selected.source);
		}

		snapshot.states[it_index] = copy;
		snapshot.documents[it_index] = *snapshot.states[it_index];
		snapshot.contexts[it_index] = .{
			identity = context_identity,
			paths = .{
				visible_filename = .{
					encoding = admitted.paths.visible_filename.encoding,
					code_units = analysis_snapshot_bytes(snapshot, *cursor, admitted.paths.visible_filename.code_units),
				},
			},
		};
	}

	assert(cursor == snapshot.metadata.count);
	snapshot.model.documents.data = snapshot.documents.data;
	snapshot.model.documents.count = snapshot.documents.count;
	snapshot.model.documents.allocated = snapshot.documents.count;
	snapshot.model.contexts.data = snapshot.contexts.data;
	snapshot.model.contexts.count = snapshot.contexts.count;
	snapshot.model.contexts.allocated = snapshot.contexts.count;
}

bind_analysis_candidate_capture :: (model: *Provider_Model, documents: [] [] u8, capture: *Source_Candidate_Capture) {
	for * capture.members {
		state := find_document(model, documents[it_index]);
		selected := selected_document(state);
		it.document = state.document;
		it.provider_revision = state.provider_revision;
		it.context_identity = selected.syntax_context;
		if !it_index && capture.consistency.kind == .COHERENT_CAPTURE {
			assert(!!selected.provenance);
			capture.consistency = selected.provenance.consistency;
		}
	}
}

finish_analysis_candidate_capture :: (
	session: *Session,
	snapshot: *Analysis_Candidate_Snapshot,
	capture: *Source_Candidate_Capture
) {
	allocator := owner_allocator(session);
	unlock(
		*session.gate,
		#code {
			free_source_candidate_capture(capture, allocator);
			free_analysis_candidate_snapshot(snapshot, allocator);
		}
	);
}

try_source_candidate_capture :: (
	model: *Provider_Model,
	identity: Session_ID,
	frontier: [] u8,
	documents: [] [] u8,
	allocator: Allocator = context.allocator
) -> bool, Source_Candidate_Capture {
	result := Source_Candidate_Capture.{capturable = true};
	members_ok, members := try_output_array(allocator, documents.count, Selected_Member);
	if !members_ok {
		return false, .{};
	}


	result.members = members;
	accepted := false;
	defer {
		if !accepted {
			free_source_candidate_capture(*result, allocator);
		}
	}

	keys_ok, member_keys := try_output_array(allocator, documents.count, [] u8);
	if !keys_ok {
		return false, .{};
	}


	defer {
		for member_keys {
			free(it.data,, allocator);
		}

		free(member_keys.data,, allocator);
	}

	coherent := true;
	capture: Consistency;
	for documents {
		state := find_document(model, it);
		selected := selected_document(state);
		coherent &&= selected.provenance && selected.provenance.consistency.kind == .COHERENT_CAPTURE;
		if coherent {
			coherent = !capture.capture_token.count || bytes_equal(capture.capture_token, selected.provenance.consistency.capture_token);
			capture = selected.provenance.consistency;
		}

		admitted := find_context(model, selected.syntax_context);
		filename_ok, filename := try_path_spelling(admitted.paths.visible_filename, allocator);
		if !filename_ok {
			return false, .{};
		}


		member := Selected_Member.{
			document = state.document,
			provider_revision = state.provider_revision,
			context_identity = selected.syntax_context,
			state = xx selected.kind,
			source = selected.source,
			filename = filename,
		};

		members[it_index] = member;
		result.capturable &&= member.state == .PRESENT || member.state == .ABSENT;
		source_revision := ifx member.source then member.source.revision;
		key_ok, key := try_output_key(allocator, "member", member.document, member.provider_revision, member.context_identity, source_revision);
		if !key_ok {
			return false, .{};
		}


		member_keys[it_index] = key;
	}


	members_key_ok, members_key := try_output_key(allocator, "members", ..member_keys);
	if !members_key_ok {
		return false, .{};
	}


	defer free(members_key.data,, allocator);
	key_ok, key := try_output_key(allocator, "execution-capture", identity.([] u8), frontier, members_key, xx "SYNTAX_INDEX");
	if !key_ok {
		return false, .{};
	}


	result.key = key;
	result.consistency = ifx coherent
		then capture
		else .{kind = .IMMUTABLE_CAPTURE};
	accepted = true;
	return true, result;
}

free_source_candidate_capture :: (capture: *Source_Candidate_Capture, allocator: Allocator = context.allocator) {
	for capture.members {
		free(it.filename.data,, allocator);
	}

	free(capture.members.data,, allocator);
	free(capture.key.data,, allocator);
	capture.* = .{};
}

Source_Update_Backing :: struct {
	operation: *Operation;
	documents: [] [] u8;
	identity: [] u8;
}

#if TEST_HOOKS {
	source_update_allocate :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, data: *void) -> *void {
		session := data.(*Session);
		if mode == .ALLOCATE || mode == .RESIZE {
			hook := session.faults.source_update_allocation_hook;
			if hook && !hook(size, session.faults.source_update_allocation_data) {
				return null;
			}
		}


		allocator := owner_allocator(session);
		return allocator.proc(mode, size, old_size, old_memory, allocator.data);
	}
}

prepare_query_operation_identity :: (session: *Session, backing: *Source_Update_Backing) -> bool {
	allocator := owner_allocator(session);
	#if TEST_HOOKS {
		allocator = .{proc = source_update_allocate, data = session};
	}

	prepared := false;
	unlock(
		*session.gate,
		#code {
			token: [8] u8;
			prepared, backing.identity = try_output_key(allocator, "operation", session.identities.session.([] u8), token);
		}
	);

	return prepared;
}

prepare_source_update_backing :: (session: *Session, count: s64, backing: *Source_Update_Backing) -> bool {
	allocator := owner_allocator(session);
	#if TEST_HOOKS {
		allocator = .{proc = source_update_allocate, data = session};
	}

	prepared := false;
	unlock(
		*session.gate,
		#code {
			ok, operations := try_output_array(allocator, 1, Operation);
			if ok {
				backing.operation = operations.data;
				documents_ok, documents := try_output_array(allocator, count, [] u8);
				backing.documents = documents;
				if documents_ok {
					token: [8] u8;
					prepared, backing.identity = try_output_key(allocator, "operation", session.identities.session.([] u8), token);
				}
			}
		}
	);

	return prepared;
}

prepare_analysis_document_backing :: (session: *Session, request: Analysis_Request, documents: [] [] u8, frontier: *[] u8) -> bool {
	allocator := owner_allocator(session);
	#if TEST_HOOKS {
		allocator = .{proc = source_update_allocate, data = session};
	}

	ok := true;
	unlock(
		*session.gate,
		#code {
			for request.documents {
				document_ok, storage := try_output_array(allocator, it.count, u8);
				documents[it_index] = storage;
				if !document_ok {
					ok = false;
					break;
				}
			}

			if ok {
				ok, frontier.* = try_output_array(allocator, request.expected_frontier.count, u8);
			}
		}
	);

	return ok;
}

finish_source_update_backing :: (session: *Session, backing: *Source_Update_Backing) {
	allocator := owner_allocator(session);
	unlock(
		*session.gate,
		#code {
			free(backing.operation,, allocator);
			free(backing.documents.data,, allocator);
			free(backing.identity.data,, allocator);
		}
	);

	backing.* = .{};
}

finish_query_operation_backing :: (session: *Session, backing: *Source_Update_Backing) {
	if backing.operation && backing.operation.waiters.data {
		allocator := owner_allocator(session);
		unlock(
			*session.gate,
			#code {
				free(backing.operation.waiters.data,, allocator);
			}
		);
	}

	finish_source_update_backing(session, backing);
}

Immediate_Result_Backing :: struct {
	result: *Query_Result;
	identity: [] u8;
}

prepare_immediate_result_backing :: (session: *Session, backing: *Immediate_Result_Backing, asynchronous := false) -> bool {
	allocator := owner_allocator(session);
	#if TEST_HOOKS {
		allocator = ifx asynchronous
			then Allocator.{proc = query_result_allocate, data = session}
			else .{proc = registration_backing_allocate, data = session};
	}

	prepared := false;
	unlock(
		*session.gate,
		#code {
			ok, storage := try_output_array(allocator, 1, Query_Result);
			if ok {
				backing.result = storage.data;
				token: [8] u8;
				prepared, backing.identity = try_output_key(allocator, "result", session.identities.session.([] u8), token);
			}
		}
	);

	return prepared;
}

#if TEST_HOOKS {
	query_result_allocate :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, data: *void) -> *void {
		session := data.(*Session);
		if mode == .ALLOCATE || mode == .RESIZE {
			hook := session.faults.query_result_allocation_hook;
			if hook && !hook(size, session.faults.query_result_allocation_data) {
				return null;
			}
		}


		allocator := owner_allocator(session);
		return allocator.proc(mode, size, old_size, old_memory, allocator.data);
	}
}

finish_immediate_result_backing :: (session: *Session, backing: *Immediate_Result_Backing) {
	allocator := owner_allocator(session);
	unlock(
		*session.gate,
		#code {
			free(backing.result,, allocator);
			free(backing.identity.data,, allocator);
		}
	);

	backing.* = .{};
}

Registration_Backing :: struct {
	slots: [] Registration_Slot;
	registrations: [] *Registration;
	registration: *Registration;
	old_slots: [] Registration_Slot;
	old_registrations: [] *Registration;
}

registration_backing_ready :: (session: *Session) -> bool {
	return session.registry.free_slots.count
		|| session.registry.slots.count < session.registry.slots.allocated && session.registry.slots.count < session.registrations.count;
}

finish_registration_backing :: (session: *Session, backing: *Registration_Backing) {
	allocator := owner_allocator(session);
	unlock(
		*session.gate,
		#code {
			free(backing.slots.data,, allocator);
			free(backing.registrations.data,, allocator);
			free(backing.registration,, allocator);
			free(backing.old_slots.data,, allocator);
			free(backing.old_registrations.data,, allocator);
		}
	);
}

#if TEST_HOOKS {
	registration_backing_allocate :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, data: *void) -> *void {
		session := data.(*Session);
		if mode == .ALLOCATE || mode == .RESIZE {
			hook := session.faults.registration_allocation_hook;
			if hook && !hook(size, session.faults.registration_allocation_data) {
				return null;
			}
		}


		allocator := owner_allocator(session);
		return allocator.proc(mode, size, old_size, old_memory, allocator.data);
	}
}

prepare_registration_backing :: (session: *Session) -> bool {
	if registration_backing_ready(session) {
		return true;
	}


	count := session.registry.slots.count;
	if count >= S64_MAX / 2 {
		return false;
	}


	capacity := max(8, (count + 1) * 2);
	need_slots := count >= session.registry.slots.allocated;
	need_registrations := count >= session.registrations.allocated;
	need_registration := count >= session.registrations.count;
	backing: Registration_Backing;
	defer finish_registration_backing(session, *backing);

	allocator := owner_allocator(session);
	#if TEST_HOOKS {
		allocator = .{proc = registration_backing_allocate, data = session};
	}

	ok := true;
	unlock(
		*session.gate,
		#code {
			if need_slots {
				ok, backing.slots = try_output_array(allocator, capacity, Registration_Slot);
			}

			if ok && need_registrations {
				ok, backing.registrations = try_output_array(allocator, capacity, *Registration);
			}

			if ok && need_registration {
				registration_ok, storage := try_output_array(allocator, 1, Registration);
				ok = registration_ok;
				backing.registration = storage.data;
			}
		}
	);

	if !ok {
		return false;
	}


	if registration_backing_ready(session) || session.registry.slots.count >= capacity {
		return true;
	}


	count = session.registry.slots.count;
	if count >= session.registry.slots.allocated && !backing.slots.count {
		return true;
	}


	if count >= session.registrations.allocated && !backing.registrations.count {
		return true;
	}


	if count >= session.registrations.count && !backing.registration {
		return true;
	}


	if count >= session.registry.slots.allocated {
		memcpy(backing.slots.data, session.registry.slots.data, count * size_of(Registration_Slot));
		backing.old_slots = .{data = session.registry.slots.data, count = count};
		session.registry.slots.data = backing.slots.data;
		session.registry.slots.allocated = backing.slots.count;
		backing.slots = .[];
	}

	if count >= session.registrations.allocated {
		memcpy(backing.registrations.data, session.registrations.data, session.registrations.count * size_of(*Registration));
		backing.old_registrations = .{data = session.registrations.data, count = session.registrations.count};
		session.registrations.data = backing.registrations.data;
		session.registrations.allocated = backing.registrations.count;
		backing.registrations = .[];
	}

	if count >= session.registrations.count {
		array_add(*session.registrations, backing.registration);
		backing.registration = null;
	}

	return true;
}

Waiter_Backing :: struct {
	storage: [] Slot_Reference;
	old_storage: [] Slot_Reference;
}

finish_waiter_backing :: (session: *Session, backing: *Waiter_Backing) {
	allocator := owner_allocator(session);
	unlock(
		*session.gate,
		#code {
			free(backing.storage.data,, allocator);
			free(backing.old_storage.data,, allocator);
		}
	);
}

lookup_waiter_source :: (session: *Session, source: Handle($K)) -> *Session, *Registration {
	current, registration := lookup_pinned(session, source);
	#if TEST_HOOKS {
		if (
			!current && session.faults.allow_stale_waiter_source
			&& source.slot < xx session.registry.slots.count
			&& session.registry.slots[source.slot].live
			&& session.registry.slots[source.slot].kind == K
		) {
			current = session;
			registration = session.registrations[source.slot];
		}
	}

	return current, registration;
}

prepare_waiter_backing :: (session: *Session, source: Handle($K), operation: *Operation) -> bool {
	#assert K == .TICKET || K == .WORLD;
	count := operation.waiters.count;
	if count < operation.waiters.allocated {
		return true;
	}


	if count >= S64_MAX / 2 {
		return false;
	}


	capacity := max(8, (count + 1) * 2);
	backing: Waiter_Backing;
	defer finish_waiter_backing(session, *backing);

	allocator := owner_allocator(session);
	#if TEST_HOOKS {
		allocator = .{proc = registration_backing_allocate, data = session};
	}

	ok: bool;
	unlock(
		*session.gate,
		#code {
			ok, backing.storage = try_output_array(allocator, capacity, Slot_Reference);
		}
	);

	current, registration := lookup_waiter_source(session, source);
	if !current {
		return ok;
	}


	#if K == .TICKET {
		operation = registration.operation;
		if operation.terminal {
			return ok;
		}
	}


	if !ok {
		return false;
	}


	count = operation.waiters.count;
	if count < operation.waiters.allocated || count >= capacity {
		return true;
	}


	memcpy(backing.storage.data, operation.waiters.data, count * size_of(Slot_Reference));
	backing.old_storage = .{data = operation.waiters.data, count = count};
	operation.waiters.data = backing.storage.data;
	operation.waiters.allocated = capacity;
	backing.storage = .[];
	return true;
}

issue_shutdown_identity :: (session: *Session) -> bool, Operation_ID {
	ok, token := issue_token(*session.identities.operation_counter);
	if !ok {
		return false, .[];
	}


	identity := session.shutdown_control.identity;
	for 0..7 {
		identity[identity.count - 8 + it] = xx ((token >> (8 * it)) & 0xFF);
	}

	return true, identity;
}

try_output_bytes :: (allocator: Allocator, source: [] u8) -> bool, [] u8 {
	ok, bytes := try_output_array(allocator, source.count, u8);
	if ok && source.count {
		memcpy(bytes.data, source.data, source.count);
	}

	return ok, bytes;
}

try_output_argument_error :: (
	allocator: Allocator,
	rule: Argument_Rule,
	name: string,
	index: s64 = -1,
	nested_field: string = ""
) -> Operation_Error {
	ok, path := try_output_array(allocator, ifx index >= 0 || nested_field.count then 2 else 1, Path_Step);
	if !ok {
		return .{code = .ADMISSION_DENIED, admission = .{kind = .RESOURCE_EXHAUSTED}};
	}


	path[0] = .{kind = .FIELD, name = name};
	if index >= 0 {
		path[1] = .{kind = .ELEMENT, index = index};
	} else if nested_field.count {
		path[1] = .{kind = .FIELD, name = nested_field};
	}

	return .{code = .INVALID_ARGUMENT, rule = rule, path = path};
}

try_output_operation_error :: (allocator: Allocator, source: Operation_Error) -> bool, Operation_Error {
	path_ok, path := try_output_array(allocator, source.path.count, Path_Step);
	if !path_ok {
		return false, .{code = .ADMISSION_DENIED, admission = .{kind = .RESOURCE_EXHAUSTED}};
	}


	if source.path.count {
		memcpy(path.data, source.path.data, source.path.count * size_of(Path_Step));
	}

	document_ok, document := try_output_bytes(allocator, source.document);
	if !document_ok {
		free(path.data,, allocator);
		return false, .{code = .ADMISSION_DENIED, admission = .{kind = .RESOURCE_EXHAUSTED}};
	}


	output := source;
	output.path = path;
	output.document = document;
	return true, output;
}

open_argument_error :: (service: *Service, rule: Argument_Rule, name: string) -> Operation_Error {
	allocator := context.allocator;
	#if TEST_HOOKS {
		if service.cached_open_argument_allocator {
			allocator = output_allocator();
		}
	}

	error := try_output_argument_error(allocator, rule, name);
	#if TEST_HOOKS {
		if error.code == .ADMISSION_DENIED && service.allow_failed_open_argument {
			error = .{code = .INVALID_ARGUMENT, rule = rule};
		}
	}

	return error;
}

export_argument_error :: (
	session: *Session,
	handle: Handle($K),
	rule: Argument_Rule,
	name: string,
	index: s64 = -1,
	nested_field: string = ""
) -> Operation_Error {
	allocator := output_allocator();
	error: Operation_Error;
	unlock(
		*session.gate,
		#code {
			error = try_output_argument_error(allocator, rule, name, index, nested_field);
		}
	);

	owner, registration := lookup_pinned(session, handle);
	live := !!owner;
	#if TEST_HOOKS {
		live ||= session.faults.allow_stale_argument_error;
		if error.code == .ADMISSION_DENIED && session.faults.allow_failed_argument_error {
			error = .{code = .INVALID_ARGUMENT, rule = rule};
		}
	}

	if !live {
		unlock(
			*session.gate,
			#code {
				free(error.path.data,, allocator);
			}
		);

		return stale(K);
	}


	return error;
}

export_bytes :: (session: *Session, handle: Handle($K), source: [] u8) -> (ok: bool, bytes: [] u8, error: Operation_Error) {
	allocator := output_allocator();
	snapshot := array_copy(source);
	ok: bool;
	output: [] u8;
	unlock(
		*session.gate,
		#code {
			ok, output = try_output_bytes(allocator, snapshot);
			free(snapshot.data);
		}
	);

	owner, registration := lookup_pinned(session, handle);
	live := !!owner;
	#if TEST_HOOKS {
		live ||= session.faults.allow_stale_byte_export;
	}

	if !live {
		unlock(
			*session.gate,
			#code {
				free(output.data,, allocator);
			}
		);

		return false, .[], stale(K);
	}


	if !ok {
		return false, .[], .{code = .ADMISSION_DENIED, admission = .{kind = .RESOURCE_EXHAUSTED}};
	}


	return true, output, .{};
}

export_query_terminal :: (session: *Session, handle: Handle(.WORLD), observation: Observation) -> bool, Query_Start, Operation_Error {
	ok, output, error := export_observation(session, handle, observation);
	#if TEST_HOOKS {
		if !ok && error.code == .ADMISSION_DENIED && session.faults.allow_failed_terminal_query {
			return true, .{kind = .TERMINAL}, .{};
		}
	}

	if !ok {
		return false, .{}, error;
	}


	return true, .{kind = .TERMINAL, observation = output}, .{};
}

export_world_observation :: (session: *Session, handle: Handle($K), observation: Observation) -> bool, World_Acquisition, Operation_Error {
	if observation.kind == .PENDING {
		ok, identity, error := export_bytes(session, handle, observation.operation_identity.([] u8));
		if !ok {
			return false, .{}, error;
		}


		return true, .{kind = .PENDING, operation_identity = xx identity}, .{};
	}


	ok, output, error := export_observation(session, handle, observation);
	if !ok {
		return false, .{}, error;
	}


	return true, .{kind = .UNAVAILABLE, unavailable = .UPDATE_TERMINAL, observation = output}, .{};
}

try_output_tracked_document :: (allocator: Allocator, source: Tracked_Document) -> bool, Tracked_Document {
	result := source;
	result.document = .[];
	result.provider_revision = .[];
	result.binding.document = .[];
	result.binding.absolute_path.code_units = .[];
	result.disk_source_revision = .[];
	result.disk_context = .[];
	result.overlay_installation_revision = .[];
	result.overlay_source_revision = .[];
	result.overlay_context = .[];
	sources := ([] u8).[
		source.document,
		source.provider_revision,
		source.binding.document,
		source.binding.absolute_path.code_units,
		source.disk_source_revision,
		source.disk_context,
		source.overlay_installation_revision,
		source.overlay_source_revision,
		source.overlay_context,
	];

	destinations := (*[] u8).[
		*result.document,
		*result.provider_revision,
		*result.binding.document,
		*result.binding.absolute_path.code_units,
		*result.disk_source_revision,
		*result.disk_context,
		*result.overlay_installation_revision,
		*result.overlay_source_revision,
		*result.overlay_context,
	];

	for sources {
		ok, bytes := try_output_bytes(allocator, it);
		if !ok {
			for destinations {
				free(it.*.data,, allocator);
			}

			return false, .{};
		}


		destinations[it_index].* = bytes;
	}


	return true, result;
}

try_output_description :: (allocator: Allocator, source: Session_Description) -> bool, Session_Description {
	result := source;
	result.session_identity = .[];
	result.workspace = .[];
	result.provider_namespace = .[];
	result.accepted_frontier = .[];
	result.clock_identity = .[];
	result.tracked_document_states = .[];
	sources := ([] u8).[
		source.session_identity.([] u8),
		source.workspace,
		source.provider_namespace,
		source.accepted_frontier,
		source.clock_identity,
	];

	destinations := (*[] u8).[
		(*result.session_identity).(*[] u8),
		*result.workspace,
		*result.provider_namespace,
		*result.accepted_frontier,
		*result.clock_identity,
	];

	for sources {
		ok, bytes := try_output_bytes(allocator, it);
		if !ok {
			free_description(*result,, allocator);
			return false, .{};
		}


		destinations[it_index].* = bytes;
	}


	ok: bool;
	ok, result.tracked_document_states = try_output_array(allocator, source.tracked_document_states.count, Tracked_Document);
	if !ok {
		free_description(*result,, allocator);
		return false, .{};
	}


	for source.tracked_document_states {
		ok, result.tracked_document_states[it_index] = try_output_tracked_document(allocator, it);
		if !ok {
			free_description(*result,, allocator);
			return false, .{};
		}
	}


	return true, result;
}

try_output_observation :: (allocator: Allocator, source: Observation) -> bool, Observation {
	result := source;
	result.operation_identity = .[];
	result.provider_frontier = .[];
	result.documents = .[];
	result.update.world_identity = .[];
	result.update.successor = .[];
	result.world_identity = .[];
	result.document = .[];
	result.context_identity = .[];
	result.query.result_identity = .[];
	sources := ([] u8).[
		source.operation_identity.([] u8),
		source.provider_frontier,
		source.update.world_identity.([] u8),
		source.update.successor.([] u8),
		source.world_identity.([] u8),
		source.document,
		source.context_identity,
		source.query.result_identity.([] u8),
	];
	destinations := (*[] u8).[
		(*result.operation_identity).(*[] u8),
		*result.provider_frontier,
		(*result.update.world_identity).(*[] u8),
		(*result.update.successor).(*[] u8),
		(*result.world_identity).(*[] u8),
		*result.document,
		*result.context_identity,
		(*result.query.result_identity).(*[] u8),
	];
	for sources {
		ok, bytes := try_output_bytes(allocator, it);
		if !ok {
			free_observation(*result,, allocator);
			return false, .{};
		}


		destinations[it_index].* = bytes;
	}


	ok: bool;
	ok, result.documents = try_output_array(allocator, source.documents.count, [] u8);
	if !ok {
		free_observation(*result,, allocator);
		return false, .{};
	}


	for source.documents {
		ok, result.documents[it_index] = try_output_bytes(allocator, it);
		if !ok {
			free_observation(*result,, allocator);
			return false, .{};
		}
	}


	return true, result;
}

free_output_records :: (allocator: Allocator, records: [] Completion_Record) {
	for * records {
		free_observation(*it.observation,, allocator);
	}

	free(records.data,, allocator);
}

try_output_records :: (allocator: Allocator, snapshots: [] Completion_Record) -> bool, [] Completion_Record {
	ok, records := try_output_array(allocator, snapshots.count, Completion_Record);
	if !ok {
		return false, .[];
	}


	for snapshots {
		records[it_index].registration = it.registration;
		ok, records[it_index].observation = try_output_observation(allocator, it.observation);
		if !ok {
			free_output_records(allocator, records);
			return false, .[];
		}
	}


	return true, records;
}

release_drain_copies :: (
	session: *Session,
	snapshots: [] Completion_Record,
	discarded: [] Observation,
	records: [] Completion_Record,
	allocator: Allocator
) {
	unlock(
		*session.gate,
		#code {
			for * snapshots {
				free_observation(*it.observation);
			}

			array_free(snapshots);
			for * discarded {
				free_observation(it,, allocator);
			}

			array_free(discarded);
			free_output_records(allocator, records);
		}
	);
}

export_observation :: (session: *Session, handle: Handle($K), source: Observation) -> bool, Observation, Operation_Error {
	allocator := output_allocator();
	snapshot := owned_observation(source);
	ok: bool;
	output: Observation;
	unlock(
		*session.gate,
		#code {
			ok, output = try_output_observation(allocator, snapshot);
			free_observation(*snapshot);
		}
	);

	live, registration := lookup_pinned(session, handle);
	#if TEST_HOOKS && K == .WORLD {
		if session.faults.allow_stale_terminal_query {
			live = session;
		}
	}

	if !live {
		unlock(
			*session.gate,
			#code {
				free_observation(*output,, allocator);
			}
		);

		return false, .{}, stale(K);
	}


	if !ok {
		return false, .{}, .{code = .ADMISSION_DENIED, admission = .{kind = .RESOURCE_EXHAUSTED}};
	}


	return true, output, .{};
}

output_allocator :: () -> Allocator {
	return ifx context.cache_service_output_allocator.proc
		then context.cache_service_output_allocator
		else context.allocator;
}

owned_allocate :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, data: *void) -> *void {
	heap := data.(*Owned_Heap);
	if mode != .ALLOCATE && mode != .RESIZE && mode != .FREE {
		return heap.delegate.proc(mode, size, old_size, old_memory, heap.delegate.data);
	}


	if size < 0 || size > S64_MAX - size_of(Owned_Allocation) {
		return null;
	}


	result: *Owned_Allocation;
	old: *Owned_Allocation;
	lock(
		*heap.gate,
		#code {
			if old_memory {
				old = (old_memory.(*u8) - size_of(Owned_Allocation)).(*Owned_Allocation);
				assert(old.heap == heap, "\e[91Released an allocation through the wrong owner.\e[0m");
			}

			if mode != .FREE {
				result = heap.delegate.proc(.ALLOCATE, size + size_of(Owned_Allocation), 0, null, heap.delegate.data).(*Owned_Allocation);
				if !result {
					return null;
				}


				result.* = .{size = size, next = heap.first, heap = heap};
				if heap.first {
					heap.first.previous = result;
				}

				heap.first = result;
				heap.allocations += 1;
				heap.bytes += size;
				#if TEST_HOOKS {
					atomic_add(*heap.service.owned_allocations, 1);
					atomic_add(*heap.service.owned_bytes, size);
				}

				if old {
					memcpy(result.(*u8) + size_of(Owned_Allocation), old_memory, min(size, old.size));
				}
			}

			if old {
				if old.previous {
					old.previous.next = old.next;
				} else {
					heap.first = old.next;
				}

				if old.next {
					old.next.previous = old.previous;
				}

				heap.allocations -= 1;
				heap.bytes -= old.size;
				#if TEST_HOOKS {
					atomic_add(*heap.service.owned_allocations, -1);
					atomic_add(*heap.service.owned_bytes, -old.size);
				}
			}
		}
	);

	if old {
		heap.delegate.proc(.FREE, 0, old.size + size_of(Owned_Allocation), old, heap.delegate.data);
	}

	return ifx result then result.(*u8) + size_of(Owned_Allocation);
}

release_owner_heap :: (heap: *Owned_Heap) {
	while heap.first {
		allocation := heap.first;
		heap.first = allocation.next;
		#if TEST_HOOKS {
			atomic_add(*heap.service.owned_allocations, -1);
			atomic_add(*heap.service.owned_bytes, -allocation.size);
		}
		heap.delegate.proc(.FREE, 0, allocation.size + size_of(Owned_Allocation), allocation, heap.delegate.data);
	}

	heap.allocations = 0;
	heap.bytes = 0;
	destroy(*heap.gate);
}
