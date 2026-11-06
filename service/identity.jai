// Live identity allocation (CACHE_CONTRACTS.md milestone 3) and generation-checked handle registrations (milestone 2).

U64_MAX : u64 : 0xFFFF_FFFF_FFFF_FFFF;
S64_MAX : s64 : 0x7FFF_FFFF_FFFF_FFFF;

Session_ID :: #type,distinct [] u8;
World_ID :: #type,distinct [] u8;
Result_ID :: #type,distinct [] u8;
Operation_ID :: #type,distinct [] u8;

// Issues 1, 2, ... once each; retires at U64_MAX instead of wrapping.
Identity_Counter :: struct {
	next: u64 = 1;
}

issue_token :: (counter: *Identity_Counter) -> bool, u64 {
	if counter.next == U64_MAX {
		return false, 0;
	}


	value := counter.next;
	counter.next += 1;
	return true, value;
}

Service_Incarnation :: struct {
	namespace: [] u8;
	session_counter: Identity_Counter;
}

// One per service bootstrap; `epoch` must come from the trusted issuer and never repeat for this authority.
make_service_incarnation :: (authority_namespace: [] u8, epoch: u64) -> Service_Incarnation {
	return .{namespace = make_key("service-incarnation", authority_namespace, little_endian(epoch, 8))};
}

clock_identity :: (incarnation: Service_Incarnation) -> [] u8 {
	return make_key("service-clock", incarnation.namespace);
}

Session_Identities :: struct {
	session: Session_ID;
	world_counter: Identity_Counter;
	result_counter: Identity_Counter;
	operation_counter: Identity_Counter;
}

issue_session :: (incarnation: *Service_Incarnation) -> bool, Session_Identities {
	ok, token := issue_token(*incarnation.session_counter);
	if !ok {
		return false, .{};
	}


	return true, .{session = xx make_key("session", incarnation.namespace, little_endian(token, 8,, temp))};
}

issue_world :: (identities: *Session_Identities) -> bool, World_ID {
	ok, token := issue_token(*identities.world_counter);
	if !ok {
		return false, .[];
	}


	return true, xx make_key("world", identities.session.([] u8), little_endian(token, 8));
}

issue_result :: (identities: *Session_Identities) -> bool, Result_ID {
	ok, token := issue_token(*identities.result_counter);
	if !ok {
		return false, .[];
	}


	return true, xx make_key("result", identities.session.([] u8), little_endian(token, 8));
}

issue_operation :: (identities: *Session_Identities) -> bool, Operation_ID {
	ok, token := issue_token(*identities.operation_counter);
	if !ok {
		return false, .[];
	}


	return true, xx make_key("operation", identities.session.([] u8), little_endian(token, 8));
}

Handle_Kind :: enum u8 {
	SESSION;
	WORLD;
	TICKET;
	WAITER;
	RESULT;
	SHUTDOWN;
}

Handle :: struct (KIND: Handle_Kind) {
	session: Session_ID;
	slot: u64;
	generation: u64;
	owner_service: *void;
	owner_token: u64;
}

Registration_Slot :: struct {
	generation: u64;
	kind: Handle_Kind;
	live: bool;
	retired: bool;
}

// Slots are zero-based and start at generation 1; a reused slot gets the next generation, and a slot whose generation reaches U64_MAX is retired permanently.
Handle_Registry :: struct {
	session: Session_ID;
	owner_service: *void;
	owner_token: u64;
	slots: [..] Registration_Slot;
	free_slots: [..] u64;
}

register_handle :: (registry: *Handle_Registry, $kind: Handle_Kind) -> bool, Handle(kind) {
	if registry.free_slots.count {
		slot := pop(*registry.free_slots);
		entry := *registry.slots[slot];
		entry.generation += 1;
		entry.kind = kind;
		entry.live = true;
		return true, .{session = registry.session, slot = slot, generation = entry.generation, owner_service = registry.owner_service, owner_token = registry.owner_token};
	}


	array_add(*registry.slots, .{generation = 1, kind = kind, live = true});
	return true, .{session = registry.session, slot = xx (registry.slots.count - 1), generation = 1, owner_service = registry.owner_service, owner_token = registry.owner_token};
}

handle_is_live :: (registry: *Handle_Registry, handle: Handle($K)) -> bool {
	if handle.slot >= xx registry.slots.count {
		return false;
	}


	if registry.owner_service {
		if handle.owner_service != registry.owner_service || handle.owner_token != registry.owner_token {
			return false;
		}
	}

	if !bytes_equal(handle.session.([] u8), registry.session.([] u8)) {
		return false;
	}


	entry := registry.slots[handle.slot];
	return entry.live && entry.kind == K && entry.generation == handle.generation;
}

release_handle :: (registry: *Handle_Registry, handle: Handle($K)) -> bool {
	if !handle_is_live(registry, handle) {
		return false;
	}


	entry := *registry.slots[handle.slot];
	entry.live = false;
	if entry.generation == U64_MAX {
		entry.retired = true;
	} else {
		array_add(*registry.free_slots, handle.slot);
	}

	return true;
}
