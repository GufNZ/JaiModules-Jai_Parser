#import "Basic";
#import "Bucket_Array";
#import "Compiler";
#import "File";
#import "File_Utilities";
#import "Pool";
#import "Sort";
#import "String";

OUTPUT_DIRECTORY :: ".build/allocation_eviction";
COMPILER_VERSION :: #run compiler_get_version_info(null);

Allocation :: struct {
	memory: *void;
	bytes: s64;
}

Ledger :: struct {
	delegate: Allocator;
	allocations: [256]Allocation;
	live: s64;
	peak: s64;
	requests: s64;
	requested_bytes: s64;
	frees: s64;
}

tracking_allocator :: (
	mode: Allocator_Mode,
	size: s64,
	old_size: s64,
	old_memory: *void,
	data: *void
) -> *void {
	ledger := data.(*Ledger);
	result := ledger.delegate.proc(mode, size, old_size, old_memory, ledger.delegate.data);
	if mode == .FREE || mode == .RESIZE && result {
		if old_memory {
			found := false;
			for *entry: ledger.allocations {
				if entry.memory == old_memory {
					ledger.live -= entry.bytes;
					entry.* = .{};
					ledger.frees += 1;
					found = true;
					break;
				}
			}

			assert(found);
		}
	}

	if (mode == .ALLOCATE || mode == .RESIZE) && result {
		found := false;
		for *entry: ledger.allocations {
			if !entry.memory {
				entry.* = .{memory = result, bytes = size};
				found = true;
				break;
			}
		}

		assert(found);
		ledger.requests += 1;
		ledger.requested_bytes += size;
		ledger.live += size;
		ledger.peak = Max(ledger.peak, ledger.live);
	}

	assert(ledger.live >= 0);
	return result;
}

Record :: struct {
	identity: s64;
	generation: s64;
	payload: string;
}

Record_Pool :: Bucket_Array(Record, 8);

probe_apis :: () {
	ledger := Ledger.{delegate = context.allocator};
	allocator := Allocator.{proc = tracking_allocator, data = *ledger};
	arena := Pool.{memblock_size = 4096, oversized_size = 512};
	set_allocators(*arena, allocator);
	first := get(*arena, 64);
	before := ledger.live;
	pool_allocator_proc(.FREE, 0, 0, first, *arena);
	assert(ledger.live == before);
	second := get(*arena, 64);
	assert(second != first);
	reset(*arena);
	assert(ledger.live == before);
	assert(get(*arena, 64) == first);
	release(*arena);
	assert(!ledger.live);

	records := Record_Pool.{allocator = allocator};
	locator, record := bucket_array_add(*records, .{identity = 1, generation = 1});
	old_generation := record.generation;
	before = ledger.live;
	bucket_array_remove(*records, locator);
	assert(ledger.live == before && !records.count);
	replacement, pointer := bucket_array_add(*records, .{identity = 2, generation = 2});
	assert(pointer == record && pointer.generation != old_generation);
	assert(replacement.bucket_index == locator.bucket_index && replacement.slot_index == locator.slot_index);
	bucket_array_reset(*records);
	assert(!ledger.live);
	print("E9 API probe passed: arena frees ignored; typed slots reused; final backing released.\n");
}

Mode :: enum {
	ARENA;
	TYPED;
	HYBRID;
}

RECORD_COUNT :: 32;
EDIT_COUNT :: 6;
CHANGE_COUNT :: 8;
RETAIN_COUNT :: 2;
SLOT_LIMIT :: 128;
MODE_COUNT :: #run enum_names(Mode).count;
WARMUP_COUNT :: 3;
TRIAL_COUNT :: 21;
BATCH_COUNT :: 64;
CREATED_PER_WORKLOAD :: RECORD_COUNT + CHANGE_COUNT * (EDIT_COUNT + 1);

Handle :: struct {
	slot: s64 = -1;
	generation: s64;
}

Slot :: struct {
	record: *Record;
	locator: Bucket_Locator;
	generation: s64;
	group: s64;
	leases: s64;
	active: bool;
	evicted: bool;
}

Group :: struct {
	arena: Pool;
	initialized: bool;
	live_records: s64;
	requested_bytes: s64;
	live_bytes: s64;
}

Store :: struct {
	mode: Mode;
	allocator: Allocator;
	ledger: Ledger;
	records: Record_Pool;
	groups: [EDIT_COUNT + 2]Group;
	slots: [SLOT_LIMIT]Slot;
	retired: [SLOT_LIMIT]Handle;
	freed_addresses: [SLOT_LIMIT]*Record;
	retired_count: s64;
	next_generation: s64 = 1;
	live_records: s64;
	live_payload_bytes: s64;
	created: s64;
	cleaned: s64;
	deferred: s64;
	slot_reuses: s64;
	address_reuses: s64;
	checks: s64;
	negative_controls: s64;
}

resolve :: (store: *Store, handle: Handle, ignore_generation: bool = false) -> *Record {
	if handle.slot < 0 || handle.slot >= SLOT_LIMIT {
		return null;
	}


	slot := store.slots[handle.slot];
	return ifx slot.active && (ignore_generation || slot.generation == handle.generation)
		then slot.record;
}

create_record :: (store: *Store, group_index: s64) -> Handle {
	index: s64 = -1;
	for 0..SLOT_LIMIT - 1 {
		if !store.slots[it].active {
			index = it;
			break;
		}
	}

	assert(index >= 0);
	slot := *store.slots[index];
	if slot.generation {
		store.slot_reuses += 1;
	}

	generation := store.next_generation;
	store.next_generation += 1;
	group := *store.groups[group_index];
	if store.mode != .TYPED && !group.initialized {
		group.arena = .{memblock_size = 4096, oversized_size = 1024};
		set_allocators(*group.arena, store.allocator);
		group.initialized = true;
	}

	record: *Record;
	locator: Bucket_Locator;
	if store.mode == .ARENA {
		record = get(*group.arena, size_of(Record)).(*Record);
	} else {
		locator, record = bucket_array_add(*store.records, .{});
	}

	payload_size := 32 + (generation % 5) * 96;
	payload: *u8;
	if store.mode == .TYPED {
		payload = alloc(payload_size,, store.allocator);
	} else {
		payload = get(*group.arena, payload_size).(*u8);
		bytes := payload_size;
		if store.mode == .ARENA {
			bytes += size_of(Record);
		}

		group.requested_bytes += bytes;
		group.live_bytes += bytes;
	}

	assert(record && payload);
	memset(payload, (generation % 251).(u8), payload_size);
	record.* = .{
		identity = generation,
		generation = generation,
		payload = .{count = payload_size, data = payload}
	};

	slot.* = .{
		record = record,
		locator = locator,
		generation = generation,
		group = group_index,
		leases = 1,
		active = true
	};

	for 0..store.retired_count - 1 {
		if store.freed_addresses[it] == record {
			store.address_reuses += 1;
			break;
		}
	}

	group.live_records += 1;
	store.live_records += 1;
	store.live_payload_bytes += payload_size;
	store.created += 1;
	return .{slot = index, generation = generation};
}

reclaim :: (store: *Store, index: s64) {
	slot := *store.slots[index];
	assert(slot.active && slot.evicted && !slot.leases);
	record := slot.record;
	payload_size := record.payload.count;
	memset(record.payload.data, 0xDD, payload_size);
	if store.mode == .TYPED {
		free(record.payload.data,, store.allocator);
	}

	group := *store.groups[slot.group];
	if store.mode != .TYPED {
		group.live_bytes -= payload_size;
		if store.mode == .ARENA {
			group.live_bytes -= size_of(Record);
		}
	}

	assert(store.retired_count < SLOT_LIMIT);
	store.retired[store.retired_count] = .{slot = index, generation = slot.generation};
	store.freed_addresses[store.retired_count] = record;
	store.retired_count += 1;
	memset(record, 0xDD, size_of(Record));
	if store.mode != .ARENA {
		bucket_array_remove(*store.records, slot.locator);
	}

	slot.active = false;
	group.live_records -= 1;
	if !group.live_records && group.initialized {
		release(*group.arena);
		group.requested_bytes = 0;
		group.live_bytes = 0;
	}

	store.live_records -= 1;
	store.live_payload_bytes -= payload_size;
	store.cleaned += 1;
}

drop_lease :: (store: *Store, handle: Handle) {
	assert(resolve(store, handle) != null);
	slot := *store.slots[handle.slot];
	assert(slot.leases > 0);
	slot.leases -= 1;
	if !slot.leases && slot.evicted {
		reclaim(store, handle.slot);
	}
}

evict_current :: (store: *Store, handle: Handle) {
	assert(resolve(store, handle) != null);
	slot := *store.slots[handle.slot];
	slot.evicted = true;
	if slot.leases > 1 {
		store.deferred += 1;
	}

	drop_lease(store, handle);
}

check_handle :: (store: *Store, handle: Handle) {
	record := resolve(store, handle);
	assert(record && record.generation == handle.generation && record.identity == handle.generation);
	for byte: record.payload {
		assert(byte == (record.identity % 251).(u8));
	}

	store.checks += 1;
}

verify_state :: (
	store: *Store,
	current: []Handle,
	retained: *[EDIT_COUNT][RECORD_COUNT]Handle,
	held: *[EDIT_COUNT]bool
) {
	for handle: current {
		if handle.slot >= 0 {
			check_handle(store, handle);
		}
	}

	for 0..EDIT_COUNT - 1 {
		if held.*[it] {
			for handle: retained.*[it] {
				check_handle(store, handle);
			}
		}
	}

	for 0..store.retired_count - 1 {
		assert(!resolve(store, store.retired[it]));
		store.checks += 1;
	}

	live: s64;
	payload: s64;
	for slot: store.slots {
		if slot.active {
			assert(slot.leases > 0);
			live += 1;
			payload += slot.record.payload.count;
		}
	}

	assert(live == store.live_records && payload == store.live_payload_bytes);
	assert(store.created - store.cleaned == live);
	if store.mode != .ARENA {
		assert(store.records.count == live);
	}
}

save_phase :: (store: *Store, phase: string, edit: s64, summary: *String_Builder) {
	dead_arena_bytes: s64;
	for group: store.groups {
		dead_arena_bytes += group.requested_bytes - group.live_bytes;
	}

	capacity := store.records.all_buckets.count * 8;
	empty_buckets: s64;
	for bucket: store.records.all_buckets {
		if !bucket.count {
			empty_buckets += 1;
		}
	}

	useful := store.live_records * size_of(Record) + store.live_payload_bytes;
	assert(store.ledger.live >= useful);
	print(
		summary,
		"%\t%\t%\t%\t%\t%\t%\t%\t%\t%\t%\t%\t%\t%\t%\t%\t%\t%\t%\t%\n",
		store.mode,
		phase,
		edit,
		store.live_records,
		store.live_payload_bytes,
		useful,
		store.ledger.live,
		store.ledger.peak,
		store.ledger.live - useful,
		dead_arena_bytes,
		capacity,
		capacity - store.records.count,
		empty_buckets,
		store.ledger.requests,
		store.ledger.frees,
		store.cleaned,
		store.deferred,
		store.slot_reuses,
		store.address_reuses,
		store.created
	);
}

Measurement :: struct {
	checks: s64;
	negative_controls: s64;
	created: s64;
	cleaned: s64;
	peak: s64;
	requests: s64;
	requested_bytes: s64;
	slot_reuses: s64;
	address_reuses: s64;
}

run_workload :: (
	mode: Mode,
	$VERIFY: bool,
	summary: *String_Builder = null,
	controls: *String_Builder = null
) -> Measurement {
	store := Store.{mode = mode};
	store.ledger.delegate = context.allocator;
	store.allocator = context.allocator;
	#if VERIFY {
		store.allocator = .{proc = tracking_allocator, data = *store.ledger};
	}

	store.records.allocator = store.allocator;
	current: [RECORD_COUNT]Handle;
	retained: [EDIT_COUNT][RECORD_COUNT]Handle;
	held: [EDIT_COUNT]bool;
	for 0..RECORD_COUNT - 1 {
		current[it] = create_record(*store, 0);
	}

	#if VERIFY {
		verify_state(*store, current, *retained, *held);
		save_phase(*store, "initial", -1, summary);
	}

	for 0..CHANGE_COUNT - 1 {
		index := it * 4;
		evict_current(*store, current[index]);
		current[index] = .{};
	}

	#if VERIFY {
		verify_state(*store, current, *retained, *held);
		save_phase(*store, "sparse", -1, summary);
	}

	for 0..CHANGE_COUNT - 1 {
		current[it * 4] = create_record(*store, 1);
	}

	#if VERIFY {
		stale := store.retired[0];
		bad := resolve(*store, stale, true);
		assert(!resolve(*store, stale) && bad && bad.generation != stale.generation);
		store.negative_controls += 1;
		if controls {
			print(
				controls,
				"%\t%\t%\t%\t%\t%\n",
				mode,
				stale.slot,
				stale.generation,
				bad.generation,
				!resolve(*store, stale),
				bad == store.freed_addresses[0]
			);
		}

		verify_state(*store, current, *retained, *held);
		save_phase(*store, "refilled", -1, summary);
	}

	for edit: 0..EDIT_COUNT - 1 {
		retained[edit] = current;
		held[edit] = true;
		for handle: current {
			store.slots[handle.slot].leases += 1;
		}

		for 0..CHANGE_COUNT - 1 {
			index := (edit * 3 + it * 4) % RECORD_COUNT;
			evict_current(*store, current[index]);
			current[index] = create_record(*store, edit + 2);
		}

		#if VERIFY {
			verify_state(*store, current, *retained, *held);
			save_phase(*store, "edit_pinned", edit, summary);
		}

		if edit >= RETAIN_COUNT {
			old := edit - RETAIN_COUNT;
			for handle: retained[old] {
				drop_lease(*store, handle);
			}

			held[old] = false;
		}

		#if VERIFY {
			verify_state(*store, current, *retained, *held);
			save_phase(*store, "edit_reclaimed", edit, summary);
		}
	}

	for *handle: current {
		evict_current(*store, handle.*);
		handle.* = .{};
	}

	#if VERIFY {
		verify_state(*store, current, *retained, *held);
		save_phase(*store, "retained_only", -1, summary);
	}

	for 0..EDIT_COUNT - 1 {
		if held[it] {
			for handle: retained[it] {
				drop_lease(*store, handle);
			}

			held[it] = false;
		}
	}

	#if VERIFY {
		verify_state(*store, current, *retained, *held);
		save_phase(*store, "empty", -1, summary);
	}

	bucket_array_reset(*store.records);
	for *group: store.groups {
		if group.initialized {
			release(*group.arena);
		}
	}

	assert(!store.live_records && !store.live_payload_bytes && store.created == store.cleaned);
	#if VERIFY {
		assert(!store.ledger.live);
		for entry: store.ledger.allocations {
			assert(!entry.memory);
		}

		save_phase(*store, "destroyed", -1, summary);
	}

	return .{
		checks = store.checks,
		negative_controls = store.negative_controls,
		created = store.created,
		cleaned = store.cleaned,
		peak = store.ledger.peak,
		requests = store.ledger.requests,
		requested_bytes = store.ledger.requested_bytes,
		slot_reuses = store.slot_reuses,
		address_reuses = store.address_reuses
	};
}

run_timings :: (samples_output: *String_Builder, stats: *String_Builder) {
	frequency :: 1000000000;
	samples: [MODE_COUNT][TRIAL_COUNT]s64;
	modes := enum_values_as_enum(Mode);
	for trial: 0..WARMUP_COUNT + TRIAL_COUNT - 1 {
		for 0..MODE_COUNT - 1 {
			order := it;
			mode := modes[(trial + order) % MODE_COUNT];
			completed: s64;
			start := current_time_monotonic();
			for 0..BATCH_COUNT - 1 {
				measurement := run_workload(mode, false);
				completed += measurement.cleaned;
			}

			elapsed, ok := to_nanoseconds(current_time_monotonic() - start);
			assert(ok);
			assert(completed == CREATED_PER_WORKLOAD * BATCH_COUNT && elapsed > 0);
			if trial >= WARMUP_COUNT {
				index := trial - WARMUP_COUNT;
				samples[mode.(s64)][index] = elapsed;
				print(
					samples_output,
					"%\t%\t%\t%\t%\t%\t%\n",
					mode,
					index,
					order,
					BATCH_COUNT,
					elapsed,
					frequency,
					completed
				);
			}
		}
	}

	for mode: modes {
		values := samples[mode.(s64)];
		quick_sort(values, (value: s64) -> s64 { return value; });
		scale := 1000000000.0 / frequency / BATCH_COUNT;
		median := values[TRIAL_COUNT / 2].(float64) * scale;
		tail_index := (TRIAL_COUNT * 95 + 99) / 100 - 1;
		tail := values[tail_index].(float64) * scale;
		print(
			stats,
			"%\t%\t%\t%\t%\t%\t%\n",
			mode,
			TRIAL_COUNT,
			BATCH_COUNT,
			median,
			tail,
			values[0].(float64) * scale,
			values[TRIAL_COUNT - 1].(float64) * scale
		);

		print("E9 %: median % ns/lifecycle, batch p95 % ns/lifecycle.\n", mode, median, tail);
	}
}

write_output :: (name: string, builder: *String_Builder) {
	text := builder_to_string(builder);
	defer free(text);

	assert(write_entire_file(tprint("%/%", OUTPUT_DIRECTORY, name), text));
}

main :: () {
	probe_apis();
	assert(make_directory_if_it_does_not_exist(".build"));
	assert(make_directory_if_it_does_not_exist(OUTPUT_DIRECTORY));
	defer reset_temporary_storage();

	phases: String_Builder;
	profiles: String_Builder;
	controls: String_Builder;
	samples: String_Builder;
	stats: String_Builder;
	defer reset(*phases);
	defer reset(*profiles);
	defer reset(*controls);
	defer reset(*samples);
	defer reset(*stats);

	print(*phases, "mode\tphase\tedit\tlive_records\tpayload_bytes\tuseful_bytes\tbacking_bytes\tpeak_bytes\tnonlive_overhead_bytes\tdead_arena_bytes\tslot_capacity\tfree_slots\tempty_buckets\tbacking_requests\tbacking_frees\tcleaned\tdeferred\tslot_reuses\taddress_reuses\tcreated\n");
	print(*profiles, "mode\tchecks\tcreated\tcleaned\tpeak_bytes\tbacking_requests\trequested_bytes\tslot_reuses\taddress_reuses\tnegative_controls\n");
	print(*controls, "mode\tslot\tstale_generation\tobserved_generation\tguarded_rejected\tsame_address\n");
	print(*samples, "mode\ttrial\torder\tbatch\tticks\tfrequency\tcleaned\n");
	print(*stats, "mode\tsamples\tbatch\tmedian_ns\tp95_ns\tmin_ns\tmax_ns\n");
	total_checks: s64;
	total_cleaned: s64;
	total_controls: s64;
	for mode: enum_values_as_enum(Mode) {
		measurement := run_workload(mode, true, *phases, *controls);
		assert(measurement.created == CREATED_PER_WORKLOAD && measurement.cleaned == CREATED_PER_WORKLOAD);
		total_checks += measurement.checks;
		total_cleaned += measurement.cleaned;
		total_controls += measurement.negative_controls;
		print(
			*profiles,
			"%\t%\t%\t%\t%\t%\t%\t%\t%\t%\n",
			mode,
			measurement.checks,
			measurement.created,
			measurement.cleaned,
			measurement.peak,
			measurement.requests,
			measurement.requested_bytes,
			measurement.slot_reuses,
			measurement.address_reuses,
			measurement.negative_controls
		);

		print("E9 %: % checks, % backing peak, % requests, % slot reuses, % address reuses.\n", mode, measurement.checks, measurement.peak, measurement.requests, measurement.slot_reuses, measurement.address_reuses);
	}

	run_timings(*samples, *stats);
	write_output("phases.tsv", *phases);
	write_output("profiles.tsv", *profiles);
	write_output("generation_controls.tsv", *controls);
	write_output("timing_samples.tsv", *samples);
	write_output("timing_stats.tsv", *stats);
	assert(write_entire_file(tprint("%/compiler_version.txt", OUTPUT_DIRECTORY), COMPILER_VERSION));
	audit := tprint(
		"{\"modes\":%,\"profile_runs\":%,\"handle_checks\":%,\"cleaned_payloads\":%,\"generation_controls\":%,\"timing_samples\":%,\"batch\":%,\"warmups\":%,\"record_size\":%}\n",
		MODE_COUNT,
		MODE_COUNT,
		total_checks,
		total_cleaned,
		total_controls,
		MODE_COUNT * TRIAL_COUNT,
		BATCH_COUNT,
		WARMUP_COUNT,
		size_of(Record)
	);

	assert(write_entire_file(tprint("%/audit_summary.json", OUTPUT_DIRECTORY), audit));
	print("E9 complete: % modes, % handle checks, % payload cleanups, % generation controls.\n", MODE_COUNT, total_checks, total_cleaned, total_controls);
}
