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


	lock(*heap.gate);
	defer unlock(*heap.gate);

	old: *Owned_Allocation;
	if old_memory {
		old = (old_memory.(*u8) - size_of(Owned_Allocation)).(*Owned_Allocation);
		assert(old.heap == heap, "Released an allocation through the wrong owner.");
	}

	result: *Owned_Allocation;
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
