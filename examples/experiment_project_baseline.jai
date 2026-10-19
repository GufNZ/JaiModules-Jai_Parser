#import "Basic";
#import "Compiler";
#import "File";
#import "File_Utilities";
#import "Hash";
#import "Hash_Table";
#import "Pool";
#import "Sort";
#import "String";
#import "Text_File_Handler";

Parser :: #import "Jai_Parser"(ENABLE_TRIVIA = true);
#load "snapshot_oracle.jai";

snapshot_checks: s64;

VERIFY_ONLY :: false;

Snapshot :: struct {
	parsed: Parser.Parsed_Source;
	storage: Pool;
	source: string;
	digest: u64;
}

make_snapshot :: (source: string, filename: string, digest: u64) -> *Snapshot {
	snapshot := New(Snapshot);
	set_allocators(*snapshot.storage);
	push_allocator(.{proc = pool_allocator_proc, data = *snapshot.storage});
	snapshot.source = copy_string(source);
	snapshot.digest = digest;
	snapshot.parsed = Parser.parse_file(snapshot.source, filename);
	return snapshot;
}

release_snapshot :: (snapshot: *Snapshot) {
	Parser.release_parser_tree(*snapshot.parsed);
	Parser.release_parser_names(*snapshot.parsed);
	release(*snapshot.storage);
	free(snapshot);
}

elapsed_ns :: (start: Apollo_Time) -> s64 {
	value, ok := to_nanoseconds(current_time_monotonic() - start);
	assert(ok && value >= 0);
	return value;
}

MAX_SOURCE_BYTES :: 524288;
MAX_FILES :: 64;
TRIALS :: 21;
HEX :: "0123456789ABCDEF";

Mode :: enum {
	FRESH;
	RESIDENT;
	TEXT_SOURCE_REPARSE;
}

Entry :: struct {
	filename: string;
	artifact: string;
	current: *Snapshot;
}

Measurement :: struct {
	elapsed: s64;
	read: s64;
	hash: s64;
	decode: s64;
	parse: s64;
	cleanup: s64;
	source_bytes: s64;
	artifact_bytes: s64;
	parses: s64;
	hits: s64;
	tokens: s64;
	diagnostics: s64;
}

Ledger :: struct {
	delegate: Allocator;
	allocations: Table(*void, s64);
	live: s64;
	peak: s64;
	requests: s64;
}

tracking_allocator :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, data: *void) -> *void {
	ledger := data.(*Ledger);
	result := ledger.delegate.proc(mode, size, old_size, old_memory, ledger.delegate.data);
	push_allocator(ledger.delegate);
	if (mode == .FREE || mode == .RESIZE && result) && old_memory {
		found, bytes := table_remove(*ledger.allocations, old_memory);
		assert(found);
		ledger.live -= bytes;
	}

	if (mode == .ALLOCATE || mode == .RESIZE) && result {
		table_add(*ledger.allocations, result, size);
		ledger.live += size;
		ledger.peak = Max(ledger.peak, ledger.live);
		ledger.requests += 1;
	}

	assert(ledger.live >= 0);
	return result;
}

encode_source :: (source: string) -> string {
	assert(source.count <= MAX_SOURCE_BYTES);
	digest := fnv1a_hash(source.data, source.count);
	builder: String_Builder;
	print(*builder, "[12]\n% % %\n", source.count, digest >> 32, digest & 0xFFFFFFFF);
	row: [128]u8;
	used: s64;
	for byte: source {
		row[used] = HEX[byte >> 4];
		row[used + 1] = HEX[byte & 0xF];
		used += 2;
		if used == row.count {
			append(*builder, string.{count = used, data = row.data});
			append(*builder, "\n");
			used = 0;
		}
	}

	if used {
		append(*builder, string.{count = used, data = row.data});
		append(*builder, "\n");
	}

	return builder_to_string(*builder);
}

decimal :: (cursor: *string) -> s64 {
	token, rest := break_by_spaces(cursor.*);
	cursor.* = rest;
	value, ok, trailing := string_to_int(token);
	assert(ok && !trailing.count && value >= 0);
	return value;
}

hex_value :: (byte: u8) -> u8 {
	if byte >= #char "0" && byte <= #char "9" {
		return byte - #char "0";
	}


	assert(byte >= #char "A" && byte <= #char "F");
	return byte - #char "A" + 10;
}

decode_source :: (text: string) -> string {
	assert(text.count <= MAX_SOURCE_BYTES * 3 && text.count && text[text.count - 1] == 10);
	handler := Text_File_Handler.{strip_comments_from_ends_of_lines = false};
	defer deinit(*handler);
	start_from_memory(*handler, "E12", "source.artifact", text);
	assert(!handler.failed && handler.version == 12);
	row, found := consume_next_line(*handler);
	assert(found);
	count := decimal(*row);
	high := decimal(*row);
	low := decimal(*row);
	assert(!row.count && count <= MAX_SOURCE_BYTES && high <= 0xFFFFFFFF && low <= 0xFFFFFFFF);
	digest := (high.(u64) << 32) | low.(u64);
	result := string.{count = count, data = alloc(count)};
	written: s64;
	while true {
		line, more := consume_next_line(*handler);
		if !more {
			break;
		}


		assert(line.count <= 128 && line.count % 2 == 0);
		for 0..line.count / 2 - 1 {
			assert(written < result.count);
			result[written] = (hex_value(line[it * 2]) << 4) | hex_value(line[it * 2 + 1]);
			written += 1;
		}
	}

	assert(written == result.count && fnv1a_hash(result.data, result.count) == digest);
	return result;
}

read_source :: (filename: string) -> string {
	source, ok := read_entire_file(filename);
	assert(ok && source.count <= MAX_SOURCE_BYTES);
	return source;
}

measure_project :: (entries: []Entry, mode: Mode) -> Measurement {
	result: Measurement;
	start := current_time_monotonic();
	for entry: entries {
		phase := current_time_monotonic();
		source := read_source(entry.filename);
		result.read += elapsed_ns(phase);
		result.source_bytes += source.count;
		phase = current_time_monotonic();
		digest := fnv1a_hash(source.data, source.count);
		unchanged := digest == entry.current.digest && source == entry.current.source;
		result.hash += elapsed_ns(phase);
		assert(unchanged);
		snapshot := entry.current;
		if mode == .RESIDENT {
			result.hits += 1;
		} else {
			decoded: string;
			if mode == .TEXT_SOURCE_REPARSE {
				phase = current_time_monotonic();
				text, ok := read_entire_file(entry.artifact);
				assert(ok);
				result.read += elapsed_ns(phase);
				result.artifact_bytes += text.count;
				phase = current_time_monotonic();
				decoded = decode_source(text);
				assert(decoded == source);
				free(text);
				result.decode += elapsed_ns(phase);
			}

			phase = current_time_monotonic();
			snapshot = make_snapshot(ifx mode == .TEXT_SOURCE_REPARSE then decoded else source, entry.filename, digest);
			result.parse += elapsed_ns(phase);
			result.parses += 1;
			if mode == .TEXT_SOURCE_REPARSE {
				free(decoded);
			}
		}

		result.tokens += snapshot.parsed.tokens.count;
		result.diagnostics += snapshot.parsed.diagnostics.count;
		phase = current_time_monotonic();
		if mode != .RESIDENT {
			release_snapshot(snapshot);
		}

		free(source);
		result.cleanup += elapsed_ns(phase);
	}

	result.elapsed = elapsed_ns(start);
	assert(result.parses + result.hits == entries.count);
	return result;
}

profile_residency :: (entries: []Entry, output: *String_Builder) {
	ledger := Ledger.{delegate = context.allocator};
	defer table_reset(*ledger.allocations);
	owned: [MAX_FILES]*Snapshot;
	old: [2]*Snapshot;
	{
		push_allocator(.{proc = tracking_allocator, data = *ledger});
		for entry: entries {
			owned[it_index] = make_snapshot(entry.current.source, entry.filename, entry.current.digest);
		}

		print(output, "resident\t%\t%\t%\t%\n", entries.count, ledger.live, ledger.peak, ledger.requests);
		for 0..1 {
			old[it] = make_snapshot(entries[0].current.source, entries[0].filename, entries[0].current.digest);
		}

		print(output, "two_retained_worlds\t%\t%\t%\t%\n", entries.count + old.count, ledger.live, ledger.peak, ledger.requests);
		for snapshot: old {
			check_snapshot(*snapshot.parsed, *entries[0].current.parsed);
			snapshot_checks += 1;
			release_snapshot(snapshot);
		}

		for 0..entries.count - 1 {
			release_snapshot(owned[it]);
		}
	}

	assert(!ledger.live && !ledger.allocations.count);
	print(output, "released\t0\t%\t%\t%\n", ledger.live, ledger.peak, ledger.requests);
}

run_edits :: (entry: Entry, output_prefix: string) {
	suffixes := string.[
		"__e12_probe :: () -> s64 { return 1; }\n",
		"__e12_probe :: () -> s64 { return 2; }\n",
		"__e12_probe :: () -> s32 { return 2; }\n",
		"__e12_shape :: struct { first: s64; second: s64; }\n",
		"__e12_probe :: () -> s64 { return 2;\n",
		"__e12_probe :: () -> s64 { return 3; }\n"
	];
	names := string.["BODY_1", "BODY_2", "INTERFACE", "LAYOUT", "MALFORMED", "REPAIR"];
	output: String_Builder;
	defer reset(*output);

	print(*output, "trial\tedit\telapsed_ns\tsource_bytes\ttokens\tdiagnostics\tretained\n");
	for trial: -1..TRIALS - 1 {
		current := make_snapshot(entry.current.source, entry.filename, entry.current.digest);
		retained: [2]*Snapshot;
		for suffix: suffixes {
			index := it_index;
			source := sprint("%\n%", entry.current.source, suffix);
			defer free(source);

			start := current_time_monotonic();
			digest := fnv1a_hash(source.data, source.count);
			next := make_snapshot(source, entry.filename, digest);
			if retained[index % retained.count] {
				release_snapshot(retained[index % retained.count]);
			}

			retained[index % retained.count] = current;
			current = next;
			duration := elapsed_ns(start);
			fresh := make_snapshot(source, entry.filename, digest);
			check_snapshot(*current.parsed, *fresh.parsed);
			snapshot_checks += 1;
			release_snapshot(fresh);
			if names[index] == "MALFORMED" {
				assert(!!current.parsed.diagnostics.count);
			}

			if trial >= 0 {
				print(*output, "%\t%\t%\t%\t%\t%\t%\n", trial, names[index], duration, source.count, current.parsed.tokens.count, current.parsed.diagnostics.count, Min(index + 1, retained.count));
			}

			reset_temporary_storage();
		}

		release_snapshot(current);
		for snapshot: retained {
			fresh := make_snapshot(snapshot.source, entry.filename, snapshot.digest);
			check_snapshot(*snapshot.parsed, *fresh.parsed);
			snapshot_checks += 1;
			release_snapshot(fresh);
			release_snapshot(snapshot);
		}
	}

	text := builder_to_string(*output);
	defer free(text);

	assert(write_entire_file(tprint("%.edits.tsv", output_prefix), text));
}

run_project :: (manifest: string, output_prefix: string) {
	filenames := read_source(manifest);
	defer free(filenames);
	entries: [..]Entry;
	defer {
		for entry: entries {
			release_snapshot(entry.current);
			free(entry.artifact);
		}

		array_free(entries);
	}

	build_start := current_time_monotonic();
	paths := split(filenames, "\n");
	defer free(paths.data);

	for filename: paths {
		if !filename.count {
			continue;
		}


		assert(entries.count < MAX_FILES);
		source := read_source(filename);
		defer free(source);

		artifact := sprint("%.%.source", output_prefix, entries.count);
		array_add(*entries, .{filename = filename, artifact = artifact, current = make_snapshot(source, filename, fnv1a_hash(source.data, source.count))});
	}

	assert(!!entries.count);
	resident_build_ns := elapsed_ns(build_start);
	artifact_bytes: s64;
	encode_write_ns: s64;
	build_start = current_time_monotonic();

	for entry: entries {
		phase := current_time_monotonic();
		text := encode_source(entry.current.source);
		defer free(text);

		assert(write_entire_file(entry.artifact, text));
		encode_write_ns += elapsed_ns(phase);
		artifact_bytes += text.count;
		decoded := decode_source(text);
		defer free(decoded);

		fresh := make_snapshot(decoded, entry.filename, fnv1a_hash(decoded.data, decoded.count));
		defer release_snapshot(fresh);

		check_snapshot(*entry.current.parsed, *fresh.parsed);
		snapshot_checks += 1;
	}

	artifact_build_ns := elapsed_ns(build_start);
	raw: String_Builder;
	profile: String_Builder;
	defer reset(*raw);
	defer reset(*profile);

	print(*raw, "mode\ttrial\torder\telapsed_ns\tread_ns\thash_ns\tdecode_ns\tparse_ns\tcleanup_ns\tsource_bytes\tartifact_bytes\tparses\thits\ttokens\tdiagnostics\n");
	for trial: -2..TRIALS - 1 {
		for 0..(#run enum_names(Mode).count) - 1 {
			mode := ((it + trial + 3) % (#run enum_names(Mode).count)).(Mode);
			result := measure_project(entries, mode);
			if trial >= 0 {
				print(
					*raw,
					"%\t%\t%\t%\t%\t%\t%\t%\t%\t%\t%\t%\t%\t%\t%\n",
					mode,
					trial,
					it,
					result.elapsed,
					result.read,
					result.hash,
					result.decode,
					result.parse,
					result.cleanup,
					result.source_bytes,
					result.artifact_bytes,
					result.parses,
					result.hits,
					result.tokens,
					result.diagnostics
				);
			}

			reset_temporary_storage();
		}
	}

	print(*profile, "phase\tsnapshots\tbacking_bytes\tpeak_bytes\trequests\n");
	profile_residency(entries, *profile);
	run_edits(entries[0], output_prefix);
	text := builder_to_string(*raw);
	assert(write_entire_file(tprint("%.timings.tsv", output_prefix), text));
	free(text);

	text = builder_to_string(*profile);
	assert(write_entire_file(tprint("%.memory.tsv", output_prefix), text));
	free(text);

	assert(
		write_entire_file(
			tprint("%.setup.tsv", output_prefix),
			tprint(
				"files\tresident_build_ns\tencode_write_ns\tartifact_build_validate_oracle_ns\tartifact_bytes\tdeep_oracles\n%\t%\t%\t%\t%\t%\n",
				entries.count,
				resident_build_ns,
				encode_write_ns,
				artifact_build_ns,
				artifact_bytes,
				snapshot_checks
			)
		)
	);
	print("E12 project: % files; % text bytes; % deep oracles and 63 timed requests passed.\n", entries.count, artifact_bytes, snapshot_checks);
}

run_restart :: (manifest: string, output_prefix: string) {
	start := current_time_monotonic();
	filenames := read_source(manifest);
	defer free(filenames);

	paths := split(filenames, "\n");
	defer free(paths.data);

	files: s64;
	source_bytes: s64;
	artifact_bytes: s64;
	tokens: s64;
	diagnostics: s64;
	for filename: paths {
		if !filename.count {
			continue;
		}


		source := read_source(filename);
		defer free(source);

		text, ok := read_entire_file(tprint("%.%.source", output_prefix, files));
		assert(ok);
		defer free(text);

		decoded := decode_source(text);
		defer free(decoded);

		assert(source == decoded);
		snapshot := make_snapshot(decoded, filename, fnv1a_hash(source.data, source.count));
		tokens += snapshot.parsed.tokens.count;
		diagnostics += snapshot.parsed.diagnostics.count;
		source_bytes += source.count;
		artifact_bytes += text.count;
		files += 1;
		release_snapshot(snapshot);
	}

	print("E12_RESTART\t%\t%\t%\t%\t%\t%\n", files, source_bytes, artifact_bytes, tokens, diagnostics, elapsed_ns(start));
}

main :: () {
	arguments := get_command_line_arguments();
	defer reset_temporary_storage();
	assert(arguments.count >= 2 && arguments.count <= 4, "Usage: experiment_project_baseline SOURCE_FILE | MANIFEST OUTPUT_PREFIX [restart]");
	if arguments.count == 4 {
		assert(arguments[3] == "restart");
		run_restart(arguments[1], arguments[2]);
		return;
	}


	if arguments.count == 3 {
		run_project(arguments[1], arguments[2]);
		return;
	}


	filename := arguments[1];
	source, ok := read_entire_file(filename);
	assert(ok);
	defer free(source);

	start := current_time_monotonic();
	resident := make_snapshot(source, filename, fnv1a_hash(source.data, source.count));
	parse_ns := elapsed_ns(start);
	defer release_snapshot(resident);

	fresh := make_snapshot(source, filename, fnv1a_hash(source.data, source.count));
	defer release_snapshot(fresh);

	check_snapshot(*resident.parsed, *fresh.parsed);
	assert(resident.digest == fnv1a_hash(source.data, source.count) && resident.source == source);
	print("E12 owned parse probe: % bytes, % tokens, % diagnostics, % ns; deep snapshot oracle passed.\n", source.count, resident.parsed.tokens.count, resident.parsed.diagnostics.count, parse_ns);
}
