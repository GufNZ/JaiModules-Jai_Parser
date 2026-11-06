// Phase-2 foundations tests: canonical encodings, content digest, identities/handles, limits/ledger and the epoch issuer.
// Run from this directory: jai service_foundations_test.jai -x64 -quiet && ./service_foundations_test.exe
#import "Basic";
#import "File";
#import "File_Utilities";
#import "Process";
#import "Sort";
#import "String";

Service :: #import "Jai_Parser/service"(TEST_HOOKS = true);
// Operators from a named import are not visible here, so alias the one the tests use.
operator == :: Service.operator ==;

main :: () {
	arguments := get_command_line_arguments();
	if arguments.count == 5 && arguments[1] == "--reserve-epochs" {
		reserve_epochs_child(arguments[2], arguments[3], string_to_int(arguments[4]));
		return;
	}


	test_key_encoding();
	test_value_encodings();
	test_canonical_order();
	test_parse_key();
	test_digest();
	test_identities();
	test_handle_registry();
	test_limits();
	test_ledger();
	test_epoch_issuer(arguments[0]);
	print("Service foundations PASS.\n");
}

// Independent oracle: literal byte layout of K(tag, fields), not the production encoder.
literal_le64 :: (value: u64) -> [8] u8 {
	result: [8] u8;
	for 0..7 {
		result[it] = xx ((value >> (8 * it)) & 0xFF);
	}

	return result;
}

expected_key :: (tag: string, fields: .. string) -> [] u8 {
	expected: [..] u8;
	add_all :: (expected: *[..] u8, bytes: [] u8) {
		for bytes {
			array_add(expected, it);
		}
	}

	add_all(*expected, literal_le64(13));
	add_all(*expected, "jai-cache-key".([] u8));
	add_all(*expected, u8.[1, 0, 0, 0]);
	add_all(*expected, literal_le64(xx tag.count));
	add_all(*expected, tag.([] u8));
	add_all(*expected, literal_le64(xx fields.count));
	for fields {
		add_all(*expected, literal_le64(xx it.count));
		add_all(*expected, it.([] u8));
	}

	return expected;
}

test_key_encoding :: () {
	assert(Service.bytes_equal(Service.make_key("t", "ab".([] u8)), expected_key("t", "ab")));
	assert(Service.bytes_equal(Service.make_key("empty"), expected_key("empty")));
	assert(Service.bytes_equal(Service.make_key("pair", "".([] u8), "x".([] u8)), expected_key("pair", "", "x")));

	// Negative control: the oracle comparison must notice a one-byte difference.
	mutated := expected_key("t", "ab");
	mutated[mutated.count - 1] = #char "c";
	assert(!Service.bytes_equal(Service.make_key("t", "ab".([] u8)), mutated));

	// Nested keys are framed fields, so field boundaries cannot be confused.
	assert(!Service.bytes_equal(Service.make_key("t", "ab".([] u8), "c".([] u8)), Service.make_key("t", "a".([] u8), "bc".([] u8))));
}

test_value_encodings :: () {
	assert(Service.bytes_equal(Service.v_bool(true), expected_key("bool", "\x01")));
	assert(Service.bytes_equal(Service.v_u16(0x1234), expected_key("u16", "\x34\x12")));
	assert(Service.bytes_equal(Service.v_s32(-2), expected_key("s32", "\xFE\xFF\xFF\xFF")));
	assert(Service.bytes_equal(Service.v_u64(1), expected_key("u64", "\x01\x00\x00\x00\x00\x00\x00\x00")));

	negative_zero := -0.0;
	assert(Service.bytes_equal(Service.v_float64_bits(negative_zero), expected_key("float64-bits", "\x00\x00\x00\x00\x00\x00\x00\x80")));
	assert(!Service.bytes_equal(Service.v_float64_bits(negative_zero), Service.v_float64_bits(0.0)));
	nan_bits: u64 = 0x7FF8_0000_0000_1234;
	nan := (*nan_bits).(*float64).*;
	assert(Service.bytes_equal(Service.v_float64_bits(nan), expected_key("float64-bits", "\x34\x12\x00\x00\x00\x00\xF8\x7F")));

	ascii_ok, ascii := Service.v_ascii("jai-cache-interface/1");
	assert(ascii_ok && Service.bytes_equal(ascii, expected_key("ascii", "jai-cache-interface/1")));
	for string.["", "has space", "tab\t", "\x7F", "caf\xC3\xA9"] {
		ok := Service.v_ascii(it);
		assert(!ok, "ASCII tag '%' should reject.", it);
	}

	assert(Service.bytes_equal(Service.v_null(), expected_key("null")));
	assert(!Service.bytes_equal(Service.v_null(), Service.v_bytes(.[])));
	schema := "jai-cache-interface/1/Example".([] u8);
	record := Service.v_record(schema, Service.v_bool(false), Service.v_bytes("x".([] u8)));
	assert(Service.bytes_equal(record, Service.make_key("record", schema, Service.v_bool(false), Service.v_bytes("x".([] u8)))));
	assert(Service.bytes_equal(Service.v_enum(schema, "FIRST"), expected_key("enum", "jai-cache-interface/1/Example", "FIRST")));
	assert(Service.interface_schema("Example") == "jai-cache-interface/1/Example");
}

test_canonical_order :: () {
	assert(Service.compare_canonical("ab".([] u8), "ab".([] u8)) == 0);
	assert(Service.compare_canonical("a".([] u8), "ab".([] u8)) < 0);
	assert(Service.compare_canonical("ab".([] u8), "a".([] u8)) > 0);
	assert(Service.compare_canonical("\x01".([] u8), "\xFF".([] u8)) < 0);
	assert(Service.compare_canonical("".([] u8), "\x00".([] u8)) < 0);
}

test_parse_key :: () {
	key := Service.make_key("tag", "one".([] u8), "".([] u8), "three".([] u8));
	ok, view := Service.parse_key(key, 8);
	assert(ok && Service.bytes_equal(view.tag, "tag".([] u8)) && view.fields.count == 3);
	assert(Service.bytes_equal(view.fields[0], "one".([] u8)) && !view.fields[1].count && Service.bytes_equal(view.fields[2], "three".([] u8)));

	for prefix: 0..key.count - 1 {
		truncated_ok := Service.parse_key(.{count = prefix, data = key.data}, 8);
		assert(!truncated_ok, "Truncated key of % bytes accepted.", prefix);
	}

	trailing: [..] u8;
	array_add(*trailing, ..key);
	array_add(*trailing, 0);
	trailing_ok := Service.parse_key(trailing, 8);
	assert(!trailing_ok);

	too_many_ok := Service.parse_key(key, 2);
	assert(!too_many_ok);

	wrong_version := array_copy(key);
	wrong_version[8 + 13] = 2;
	version_ok := Service.parse_key(wrong_version, 8);
	assert(!version_ok);

	wrong_magic := array_copy(key);
	wrong_magic[8] = #char "J";
	magic_ok := Service.parse_key(wrong_magic, 8);
	assert(!magic_ok);

	// A huge declared field count must reject before any allocation proportional to it.
	huge := Service.make_key("tag");
	count_at := huge.count - 8;
	for 0..7 {
		huge[count_at + it] = 0xFF;
	}

	huge_ok := Service.parse_key(huge, Service.U64_MAX);
	assert(!huge_ok);
}

test_digest :: () {
	sizes :: s64.[0, 1, 15, 16, 31, 32, 255, 256, 257, 4095, 4096, 4097, 100_000];
	chunks :: s64.[1, 7, 64, 4096];
	data := NewArray(100_000, u8);
	for * data {
		it.* = xx ((it_index * 131 + 7) & 0xFF);
	}

	for size: sizes {
		input: [] u8 = .{count = size, data = data.data};
		one_shot := Service.digest_128(input);
		assert(one_shot == Service.digest_128(input), "Digest is not deterministic for % bytes.", size);
		for chunk: chunks {
			state: Service.Digest_State;
			Service.digest_begin(*state);
			offset := 0;
			while offset < size {
				length := min(chunk, size - offset);
				Service.digest_absorb(*state, .{count = length, data = data.data + offset});
				offset += length;
			}

			assert(Service.digest_end(*state) == one_shot, "Streaming digest differs for % bytes in % byte chunks.", size, chunk);
		}

		if size {
			data[size / 2] ^= 0x01;
			assert(Service.digest_128(input) != one_shot, "Bit flip not detected for % bytes.", size);
			data[size / 2] ^= 0x01;
		}
	}

	// Regression pins for this meow_hash build, not independent published vectors.
	empty := Service.digest_128(.[]);
	abc := Service.digest_128("abc".([] u8));
	assert(hex(empty) == "45C059582AA07C655E26830355B5A775", "Empty-input digest changed: %.", hex(empty));
	assert(hex(abc) == "3BCC0A43EC73F719B49A4C426B236D5F", "\"abc\" digest changed: %.", hex(abc));
}

hex :: (digest: Service.Digest_128) -> string {
	builder: String_Builder;
	Service.append_uppercase_hex(*builder, digest.bytes);
	return builder_to_string(*builder,, temp);
}

test_identities :: () {
	authority := "test-authority".([] u8);
	incarnation := Service.make_service_incarnation(authority, 7);
	assert(Service.bytes_equal(incarnation.namespace, expected_key("service-incarnation", "test-authority", "\x07\x00\x00\x00\x00\x00\x00\x00")));
	other := Service.make_service_incarnation(authority, 8);
	assert(!Service.bytes_equal(incarnation.namespace, other.namespace));

	ok_a, session_a := Service.issue_session(*incarnation);
	ok_b, session_b := Service.issue_session(*incarnation);
	assert(ok_a && ok_b && !Service.bytes_equal(session_a.session.([] u8), session_b.session.([] u8)));
	_, world := Service.issue_world(*session_a);
	_, result := Service.issue_result(*session_a);
	assert(!Service.bytes_equal(world.([] u8), result.([] u8)), "Equal tokens in different domains must stay distinct.");

	counter := Service.Identity_Counter.{next = Service.U64_MAX - 1};
	last_ok, last := Service.issue_token(*counter);
	exhausted_ok, _ := Service.issue_token(*counter);
	assert(last_ok && last == Service.U64_MAX - 1 && !exhausted_ok);
	still_exhausted, _ := Service.issue_token(*counter);
	assert(!still_exhausted);
}

test_handle_registry :: () {
	registry: Service.Handle_Registry;
	registry.session = xx "session-a".([] u8);

	ok, world := Service.register_handle(*registry, .WORLD);
	assert(ok && world.slot == 0 && world.generation == 1 && Service.handle_is_live(*registry, world));

	_, ticket := Service.register_handle(*registry, .TICKET);
	assert(ticket.slot == 1);

	forged := Service.Handle(.RESULT).{session = world.session, slot = world.slot, generation = world.generation};
	assert(!Service.handle_is_live(*registry, forged), "A handle of the wrong kind must not validate.");

	foreign := world;
	foreign.session = xx "session-b".([] u8);
	assert(!Service.handle_is_live(*registry, foreign));

	assert(Service.release_handle(*registry, world));
	assert(!Service.release_handle(*registry, world), "Double release must fail.");
	assert(!Service.handle_is_live(*registry, world));

	_, reused := Service.register_handle(*registry, .RESULT);
	assert(reused.slot == world.slot && reused.generation == 2);
	stale := Service.Handle(.RESULT).{session = world.session, slot = world.slot, generation = world.generation};
	assert(!Service.handle_is_live(*registry, stale), "A stale generation must not address the reused slot.");

	registry.slots[reused.slot].generation = Service.U64_MAX;
	reused.generation = Service.U64_MAX;
	assert(Service.release_handle(*registry, reused));
	assert(registry.slots[reused.slot].retired && !registry.free_slots.count);
	_, fresh := Service.register_handle(*registry, .WAITER);
	assert(fresh.slot == 2 && fresh.generation == 1, "An exhausted slot must be retired, never reused.");
}

test_limits :: () {
	ceilings: Service.Limits;
	minima: Service.Limits;
	for * ceilings.values {
		it.* = 1000;
	}

	minima.values[Service.Limit_Name.LIVE_HANDLES] = 2;

	failure, defaults := Service.negotiate_limits(.{}, ceilings, minima);
	assert(failure == .NONE && defaults.values[Service.Limit_Name.OWNED_BYTES] == 1000);

	request: Service.Limit_Request;
	request.values[Service.Limit_Name.OWNED_BYTES] = 400;
	request.values[Service.Limit_Name.VALUE_BYTES] = 5000;
	request.values[Service.Limit_Name.BATCH_EVENTS] = 0;
	effective_failure, effective := Service.negotiate_limits(request, ceilings, minima);
	assert(effective_failure == .NONE);
	assert(effective.values[Service.Limit_Name.OWNED_BYTES] == 400);
	assert(effective.values[Service.Limit_Name.VALUE_BYTES] == 1000, "A request above the ceiling is clamped to it.");
	assert(effective.values[Service.Limit_Name.BATCH_EVENTS] == 0);

	below_minimum: Service.Limit_Request;
	below_minimum.values[Service.Limit_Name.LIVE_HANDLES] = 1;
	minimum_failure, _, minimum_name := Service.negotiate_limits(below_minimum, ceilings, minima);
	assert(minimum_failure == .LIMIT && minimum_name == .LIVE_HANDLES);

	invalid: Service.Limit_Request;
	invalid.values[Service.Limit_Name.KEY_BYTES] = -2;
	invalid_failure, _, invalid_name := Service.negotiate_limits(invalid, ceilings, minima);
	assert(invalid_failure == .INVALID_ARGUMENT && invalid_name == .KEY_BYTES);

	assert(Service.within_limit(effective, .OWNED_BYTES, 400) && !Service.within_limit(effective, .OWNED_BYTES, 401));
	assert(!Service.within_limit(effective, .OWNED_BYTES, -1));
}

test_ledger :: () {
	ledger: Service.Resource_Ledger;
	ledger.limits.values[Service.Limit_Name.LIVE_HANDLES] = 4;
	ledger.limits.values[Service.Limit_Name.OWNED_BYTES] = 100;

	assert(Service.reserve(*ledger, .{.LIVE_HANDLES, 2}, .{.OWNED_BYTES, 60}));
	assert(!Service.reserve(*ledger, .{.LIVE_HANDLES, 1}, .{.OWNED_BYTES, 41}), "One over the byte limit must reject.");
	assert(ledger.reserved[Service.Limit_Name.LIVE_HANDLES] == 2, "A rejected reservation must not leave partial charges.");
	assert(Service.reserve(*ledger, .{.LIVE_HANDLES, 1}, .{.OWNED_BYTES, 40}), "Exactly reaching the limit is allowed.");

	Service.commit_reserved(*ledger, .LIVE_HANDLES, 3);
	assert(ledger.live[Service.Limit_Name.LIVE_HANDLES] == 3 && !ledger.reserved[Service.Limit_Name.LIVE_HANDLES]);
	assert(!Service.reserve(*ledger, .{.LIVE_HANDLES, 2}));
	Service.release_live(*ledger, .LIVE_HANDLES, 1);
	assert(Service.reserve(*ledger, .{.LIVE_HANDLES, 2}));

	assert(!Service.reserve(*ledger, .{.OWNED_BYTES, -1}));
	assert(!Service.reserve(*ledger, .{.OWNED_BYTES, Service.S64_MAX}, .{.OWNED_BYTES, 1}), "Amount overflow must reject.");
	Service.release_reserved(*ledger, .OWNED_BYTES, 100);
	assert(!ledger.reserved[Service.Limit_Name.OWNED_BYTES]);
}

test_epoch_issuer :: (executable: string) {
	directory := tprint("%/.build/epoch_test", #filepath);
	make_directory_if_it_does_not_exist(directory, recursive = true);
	epoch_path := tprint("%/%", directory, Service.EPOCH_FILE_NAME);
	file_delete(epoch_path);
	authority := "project:D:/example".([] u8);

	ok, first := Service.reserve_epoch(directory, authority);
	assert(ok && first == 1);
	ok_second, second := Service.reserve_epoch(directory, authority);
	assert(ok_second && second == 2);
	ok_floor, floored := Service.reserve_epoch(directory, authority, 10);
	assert(ok_floor && floored == 11);

	// A deleted epoch file restarts above the head floor, never at 1.
	file_delete(epoch_path);
	ok_deleted, after_delete := Service.reserve_epoch(directory, authority, 11);
	assert(ok_deleted && after_delete == 12);

	ok_other, _, other_failure := Service.reserve_epoch(directory, "project:D:/other".([] u8));
	assert(!ok_other && other_failure == .AUTHORITY_MISMATCH);
	ok_after_mismatch, after_mismatch := Service.reserve_epoch(directory, authority);
	assert(ok_after_mismatch && after_mismatch == 13, "A rejected reservation must not consume or reset the epoch.");

	NAMESPACE_HEX :: "70726F6A6563743A443A2F6578616D706C65";
	malformed_files := string.[
		"",
		"jai-cache-epoch/1\n",
		"wrong/1\nAB\n1\n",
		tprint("jai-cache-epoch/1\r\n%\n1\n", NAMESPACE_HEX),
		tprint("jai-cache-epoch/1\n%\n01\n", NAMESPACE_HEX),
		tprint("jai-cache-epoch/1\n%\n99999999999999999999\n", NAMESPACE_HEX),
		tprint("jai-cache-epoch/1\n%\n5", NAMESPACE_HEX),
		tprint("jai-cache-epoch/1\n%\n5\nextra\n", NAMESPACE_HEX)
	];
	assert(Service.encode_epoch_file(authority, 5,, temp) == tprint("jai-cache-epoch/1\n%\n5\n", NAMESPACE_HEX));
	for malformed_files {
		write_entire_file(epoch_path, it);
		ok_malformed, _, malformed_failure := Service.reserve_epoch(directory, authority);
		assert(!ok_malformed && malformed_failure == .MALFORMED_FILE, "Malformed epoch file % accepted (%).", it_index, malformed_failure);
	}

	write_entire_file(epoch_path, Service.encode_epoch_file(authority, Service.U64_MAX - 1,, temp));
	ok_exhausted, _, exhausted_failure := Service.reserve_epoch(directory, authority);
	assert(!ok_exhausted && exhausted_failure == .EXHAUSTED);

	// One lock attempt makes a lock left held by a failure path fail fast instead of waiting.
	hooks := *Service.epoch_test_hooks;
	hooks.lock_attempts = 1;

	// Injected I/O failures reserve nothing, leave the epoch file intact and release the lock.
	intact := Service.encode_epoch_file(authority, 20);
	write_entire_file(epoch_path, intact);
	for Service.Epoch_Fault_Point.[.READ, .STAGING_WRITE, .REPLACE] {
		hooks.fail_at = it;
		ok_fault, _, fault_failure := Service.reserve_epoch(directory, authority);
		hooks.fail_at = .NONE;
		assert(!ok_fault && fault_failure == .IO_ERROR, "Fault % gave %.", it, fault_failure);
		contents, read_ok := read_entire_file(epoch_path);
		assert(read_ok && contents == intact, "Fault % changed the epoch file.", it);
	}

	ok_recovered, recovered := Service.reserve_epoch(directory, authority);
	assert(ok_recovered && recovered == 21, "A failed reservation consumed an epoch or left the lock held.");

	// A held lock blocks reservation; without the lock's exclusion the same holder does not (negative control).
	held_ok, held := Service.hold_epoch_lock(directory);
	assert(held_ok);
	ok_blocked, _, blocked_failure := Service.reserve_epoch(directory, authority);
	assert(!ok_blocked && blocked_failure == .LOCK_UNAVAILABLE, "A reservation ran while the lock was held (%).", blocked_failure);
	hooks.shared_lock = true;
	ok_shared := Service.reserve_epoch(directory, authority);
	hooks.shared_lock = false;
	assert(ok_shared, "Control undetected: a reservation without exclusion was still blocked.");
	Service.drop_epoch_lock(held);
	hooks.lock_attempts = Service.EPOCH_LOCK_ATTEMPTS;

	// Concurrent processes must never receive the same epoch.
	file_delete(epoch_path);
	PROCESSES :: 4;
	PER_PROCESS :: 25;
	processes: [PROCESSES] Process;
	for * processes {
		started := create_process(it, executable, "--reserve-epochs", directory, "project:D:/example", tprint("%", PER_PROCESS), capture_and_return_output = true);
		assert(started);
	}

	seen: [..] u64;
	for * processes {
		output: [..] u8;
		buffer: [4096] u8;
		error_buffer: [4096] u8;
		while true {
			read_ok, output_bytes, error_bytes := read_from_process(it, buffer, error_buffer, 100);
			for 0..output_bytes - 1 {
				array_add(*output, buffer[it]);
			}

			finished, result := get_process_result(it, 0);
			if finished && result.type == .EXITED && !output_bytes && !error_bytes {
				assert(result.exit_code == 0, "Epoch child failed.");
				break;
			}


			if !read_ok && !output_bytes && !error_bytes {
				sleep_milliseconds(5);
			}
		}

		for line: split(cast(string) output, "\n") {
			if line.count {
				value, value_ok := string_to_int(line, T = u64);
				assert(value_ok);
				array_add(*seen, value);
			}
		}
	}

	assert(seen.count == PROCESSES * PER_PROCESS, "Expected % epochs, got %.", PROCESSES * PER_PROCESS, seen.count);
	quick_sort(seen, x => x);
	for seen {
		assert(it == xx (it_index + 1), "Epochs must be unique and contiguous: position % holds %.", it_index, it);
	}
}

reserve_epochs_child :: (directory: string, authority: string, count: s64) {
	for 1..count {
		ok, epoch, failure := Service.reserve_epoch(directory, authority.([] u8));
		if !ok {
			print("FAILED %\n", failure);
			exit(1);
		}


		print("%\n", epoch);
	}
}
