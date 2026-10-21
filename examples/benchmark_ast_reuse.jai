#import "Basic";
#import "Compiler";
#import "File";
#import "File_Utilities";
#import "Math";
#import "Pool";
#import "Sort";
#import "String";

WARMUP_COUNT :: 2;
TRIAL_COUNT :: 21;
SEQUENCE_EDIT_COUNT :: 3;
SEQUENCE_SNAPSHOT_COUNT :: SEQUENCE_EDIT_COUNT + 1;
UPDATE_SAMPLE_COUNT :: TRIAL_COUNT * SEQUENCE_EDIT_COUNT;
TOTAL_TRIAL_COUNT :: WARMUP_COUNT + TRIAL_COUNT;
TAIL_PERCENTILE :: 95;
PERCENT_SCALE :: 100;
MILLISECONDS_PER_SECOND :: 1000;
OLD_SOURCE_POISON :: 0xDD;

VERIFY_ONLY :: #run -> bool {
	arguments := get_build_options().compile_time_command_line;
	assert(arguments.count == 0 || (arguments.count == 1 && arguments[0] == "verify-only"));
	return arguments.count == 1;
};

Parser :: #import "Jai_Parser"(ENABLE_TRIVIA = true, TRACK_AST_REUSE = VERIFY_ONLY);
#load "snapshot_oracle.jai";

ticks :: () -> Apollo_Time {
	return current_time_monotonic();
}

elapsed_ticks :: (duration: Apollo_Time) -> s64 {
	nanoseconds, ok := to_nanoseconds(duration);
	assert(ok);
	return nanoseconds;
}

parse_tokens :: (parsed: *Parser.Parsed_Source, old: *Parser.Parsed_Source = null, edit_start: s64 = 0, edit_end: s64 = 0) {
	parser := Parser.Parser.{parsed = parsed, edit_source = old, edit_start = edit_start, edit_end = edit_end};
	set_allocators(*parsed.node_pool);
	parsed.root_scope = Parser.push_lexical_scope(*parser);
	parsed.root = Parser.parse_file_node(*parser);
	Parser.resolve_lexical_references(parsed.root_scope);
}

release_snapshot :: (parsed: *Parser.Parsed_Source, storage: *Pool) {
	Parser.release_parser_tree(parsed);
	Parser.release_parser_names(parsed);
	release(storage);
}

measure_baseline :: (source: string, filename: string, frequency: s64) {
	lex_samples: [TRIAL_COUNT]float64;
	ast_samples: [TRIAL_COUNT]float64;
	total_samples: [TRIAL_COUNT]float64;
	for trial: 0..TOTAL_TRIAL_COUNT-1 {
		storage: Pool;
		set_allocators(*storage);
		previous_allocator := context.allocator;
		context.allocator = .{proc = pool_allocator_proc, data = *storage};
		start := ticks();
		parsed := Parser.materialise_tokens(source);
		lex_end := ticks();
		parsed.fully_pathed_filename = filename;
		parse_tokens(*parsed);
		ast_end := ticks();
		release_snapshot(*parsed, *storage);
		end := ticks();
		context.allocator = previous_allocator;
		if trial >= WARMUP_COUNT {
			index := trial - WARMUP_COUNT;
			lex_samples[index] = elapsed_ticks(lex_end - start).(float64) * MILLISECONDS_PER_SECOND / frequency.(float64);
			ast_samples[index] = elapsed_ticks(ast_end - lex_end).(float64) * MILLISECONDS_PER_SECOND / frequency.(float64);
			total_samples[index] = elapsed_ticks(end - start).(float64) * MILLISECONDS_PER_SECOND / frequency.(float64);
		}
	}

	quick_sort(lex_samples, (value: float64) -> float64 { return value; });
	quick_sort(ast_samples, (value: float64) -> float64 { return value; });
	quick_sort(total_samples, (value: float64) -> float64 { return value; });
	median_index := TRIAL_COUNT / 2;
	tail_index := percentile_index(TRIAL_COUNT, TAIL_PERCENTILE);
	print(
		"  full baseline ms: lex median=%; AST+binding median=%; end-to-end incl cleanup median=% p95=% range=%..%\n",
		lex_samples[median_index],
		ast_samples[median_index],
		total_samples[median_index],
		total_samples[tail_index],
		total_samples[0],
		total_samples[TRIAL_COUNT - 1]
	);
}

Update_Mode :: enum {
	FULL;
	TOKENS;
	AST;
}

UPDATE_MODES :: Update_Mode.[.FULL, .TOKENS, .AST];
MODE_COUNT :: UPDATE_MODES.count;

Update_Edit :: struct {
	source: string;
	start: s64;
	end: s64;
	expect_added_errors: bool;
	restores_baseline: bool;
}

valid_edit :: (old: *Parser.Parsed_Source, edit: Update_Edit) -> bool {
	if edit.start < 0 || edit.end < edit.start || edit.end > old.source.count {
		return false;
	}


	inserted := edit.source.count - old.source.count + edit.end - edit.start;
	return inserted >= 0
		&& slice(edit.source, 0, edit.start) == slice(old.source, 0, edit.start)
		&& slice(edit.source, edit.start + inserted, old.source.count - edit.end) == slice(old.source, edit.end, old.source.count - edit.end);
}

check_update :: (actual: *Parser.Parsed_Source, expected: *Parser.Parsed_Source) {
	assert(actual.status == expected.status && actual.tokens.count == expected.tokens.count);
	assert(actual.diagnostics.count == expected.diagnostics.count);
	assert(actual.recovery_records.count == expected.recovery_records.count);
	assert(actual.restart_points.count == expected.restart_points.count);
	assert(actual.root && actual.root.kind == expected.root.kind);
	assert(actual.root.(*Parser.Parser_Block).statements.count == expected.root.(*Parser.Parser_Block).statements.count);
	for token, index: actual.tokens {
		reference := expected.tokens[index];
		assert(token.type == reference.type && token.value_flags == reference.value_flags);
		assert(token.byte_start == reference.byte_start && token.byte_end == reference.byte_end);
		assert(token.l0 == reference.l0 && token.c0 == reference.c0 && token.l1 == reference.l1 && token.c1 == reference.c1);
		assert(token.original_text == reference.original_text);
		assert(token.preceding_trivia == reference.preceding_trivia);
	}

	assert(Parser.reconstruct_source(actual) == expected.source);
	#if VERIFY_ONLY {
		check_snapshot(actual, expected);
	}
}

Update_Snapshot :: struct {
	storage: Pool;
	parsed: Parser.Parsed_Source;
	owned_source: string;
}

Edit_Measurements :: struct {
	acquire: float64;
	lex: float64;
	ast: float64;
	construction: float64;
	release_old: float64;
	lifecycle: float64;
}

Sequence_Measurements :: struct {
	edits: [SEQUENCE_EDIT_COUNT]Edit_Measurements;
	initial: float64;
	release_final: float64;
}

run_sequence :: (source: string, filename: string, edits: []Update_Edit, mode: Update_Mode, frequency: s64, $verify: bool) -> Sequence_Measurements {
	snapshots: [SEQUENCE_SNAPSHOT_COUNT]Update_Snapshot;
	assert(edits.count == SEQUENCE_EDIT_COUNT);
	measurements: Sequence_Measurements;
	scale := MILLISECONDS_PER_SECOND / frequency.(float64);
	previous_allocator := context.allocator;
	initial_start := ticks();
	set_allocators(*snapshots[0].storage, previous_allocator);
	context.allocator = .{proc = pool_allocator_proc, data = *snapshots[0].storage};
	defer context.allocator = previous_allocator;

	snapshots[0].owned_source = copy_string(source);
	snapshots[0].parsed = Parser.parse_file(snapshots[0].owned_source, filename);
	measurements.initial = elapsed_ticks(ticks() - initial_start).(float64) * scale;
	baseline_status := snapshots[0].parsed.status;
	baseline_diagnostics := snapshots[0].parsed.diagnostics.count;

	for edit, index: edits {
		old := *snapshots[index].parsed;
		next := *snapshots[index + 1];
		#if verify {
			assert(valid_edit(old, edit));
		}

		update_start := ticks();
		set_allocators(*next.storage, previous_allocator);
		context.allocator = .{proc = pool_allocator_proc, data = *next.storage};
		next.owned_source = copy_string(edit.source);
		start := ticks();

		next.parsed = Parser.materialise_tokens(next.owned_source, ifx mode != .FULL then old, edit.start, edit.end);
		lex_end := ticks();
		next.parsed.fully_pathed_filename = filename;
		parse_tokens(*next.parsed, ifx mode == .AST then old, edit.start, edit.end);
		ast_end := ticks();
		#if verify {
			if edit.expect_added_errors {
				assert(next.parsed.diagnostics.count > old.diagnostics.count, "Malformed edit must add a diagnostic.");
			} else if baseline_status == .COMPLETE {
				assert(next.parsed.status == .COMPLETE && !next.parsed.diagnostics.count, "Valid edits must preserve a clean baseline.");
			}

			if edit.restores_baseline {
				assert(next.parsed.status == baseline_status && next.parsed.diagnostics.count == baseline_diagnostics, "Repair must restore the baseline status and diagnostic count.");
			}

			fresh := Parser.parse_file(edit.source, filename);
			check_update(*next.parsed, *fresh);
			#if VERIFY_ONLY {
				print("    verified % edit=% old-status=% copied-declarations=%\n", mode, index + 1, old.status, next.parsed.reused_declarations);
				if mode != .AST || old.status != .COMPLETE {
					assert(next.parsed.reused_declarations == 0);
				}
			}

			memset(old.source.data, OLD_SOURCE_POISON, old.source.count);
			release_snapshot(old, *snapshots[index].storage);
			check_update(*next.parsed, *fresh);
			Parser.release_parser_tree(*fresh);
			Parser.release_parser_names(*fresh);
		} else {
			release_snapshot(old, *snapshots[index].storage);
		}

		update_end := ticks();
		measurements.edits[index] = .{
			acquire = elapsed_ticks(start - update_start).(float64) * scale,
			lex = elapsed_ticks(lex_end - start).(float64) * scale,
			ast = elapsed_ticks(ast_end - lex_end).(float64) * scale,
			construction = elapsed_ticks(ast_end - start).(float64) * scale,
			release_old = elapsed_ticks(update_end - ast_end).(float64) * scale,
			lifecycle = elapsed_ticks(update_end - update_start).(float64) * scale
		};

		#if verify {
			assert(Parser.reconstruct_source(*next.parsed) == edit.source);
		}
	}

	final_start := ticks();
	release_snapshot(*snapshots[edits.count].parsed, *snapshots[edits.count].storage);
	measurements.release_final = elapsed_ticks(ticks() - final_start).(float64) * scale;
	return measurements;
}

measure_updates :: (source: string, filename: string, frequency: s64) {
	FIRST :: "// benchmark prefix insertion\n";
	SECOND :: "// benchmark prefix replacement with longer text\n";
	first := sprint("%%", FIRST, source);
	second := sprint("%%", SECOND, source);
	defer free(first);
	defer free(second);

	edits := Update_Edit.[
		.{source = first,	start = 0,	end = 0},
		.{source = second,	start = 0,	end = FIRST.count},
		.{source = source,	start = 0,	end = SECOND.count}
	];

	measure_sequence(source, filename, frequency, edits, "prefix-comment", "trivia-control");
}

Latency_Samples :: struct {
	acquire: [UPDATE_SAMPLE_COUNT]float64;
	lex: [UPDATE_SAMPLE_COUNT]float64;
	ast: [UPDATE_SAMPLE_COUNT]float64;
	construction: [UPDATE_SAMPLE_COUNT]float64;
	release_old: [UPDATE_SAMPLE_COUNT]float64;
	lifecycle: [UPDATE_SAMPLE_COUNT]float64;
	by_edit: [SEQUENCE_EDIT_COUNT][TRIAL_COUNT]float64;
	initial: [TRIAL_COUNT]float64;
	release_final: [TRIAL_COUNT]float64;
}

Allocation_Profile :: struct {
	delegate: Allocator;
	accounting_allocator: Allocator;
	track_live: bool;
	sizes: Table(*void, s64);
	requests: s64;
	bytes: s64;
	live: s64;
	peak: s64;
}

Snapshot_Allocations :: struct {
	backing: Allocation_Profile;
	caller: Allocation_Profile;
}

Snapshot_Memory :: struct {
	requests: s64;
	requested_bytes: s64;
	retained: s64;
	overlap_peak: s64;
}

profile_allocator :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, data: *void) -> *void {
	counts := data.(*Allocation_Profile);
	if mode == .ALLOCATE || mode == .RESIZE {
		counts.requests += 1;
		counts.bytes += size;
	}

	result := counts.delegate.proc(mode, size, old_size, old_memory, counts.delegate.data);
	if !counts.track_live {
		return result;
	}


	push_allocator(counts.accounting_allocator);
	if mode == .FREE || (mode == .RESIZE && result) {
		if old_memory {
			found, bytes := table_remove(*counts.sizes, old_memory);
			assert(found);
			counts.live -= bytes;
		}
	}

	if (mode == .ALLOCATE || mode == .RESIZE) && result {
		assert(!table_contains(*counts.sizes, result));
		table_add(*counts.sizes, result, size);
		counts.live += size;
		counts.peak = max(counts.peak, counts.live);
	}

	assert(counts.live >= 0);
	return result;
}

test_allocation_profile :: () {
	INITIAL_BYTES :: 16;
	RESIZED_BYTES :: 40;
	counts := Allocation_Profile.{delegate = context.allocator, accounting_allocator = context.allocator, track_live = true};
	memory := profile_allocator(.ALLOCATE, INITIAL_BYTES, 0, null, *counts);
	assert(memory && counts.live == INITIAL_BYTES);
	memory = profile_allocator(.RESIZE, RESIZED_BYTES, INITIAL_BYTES, memory, *counts);
	assert(memory && counts.live == RESIZED_BYTES && counts.peak == RESIZED_BYTES);
	profile_allocator(.FREE, 0, 0, memory, *counts);
	assert(counts.requests == 2 && counts.bytes == INITIAL_BYTES + RESIZED_BYTES && counts.live == 0 && counts.sizes.count == 0);
	table_reset(*counts.sizes);
}

profile_snapshot :: (snapshot: *Update_Snapshot, counts: *Snapshot_Allocations, backing: Allocator, source: string, filename: string, old: *Parser.Parsed_Source = null, mode: Update_Mode = .FULL, start: s64 = 0, end: s64 = 0) {
	counts.backing.delegate = backing;
	counts.backing.accounting_allocator = backing;
	counts.backing.track_live = true;
	set_allocators(*snapshot.storage, .{proc = profile_allocator, data = *counts.backing});
	counts.caller.delegate = .{proc = pool_allocator_proc, data = *snapshot.storage};
	push_allocator(.{proc = profile_allocator, data = *counts.caller});
	snapshot.owned_source = copy_string(source);
	if !old {
		snapshot.parsed = Parser.parse_file(snapshot.owned_source, filename);
	} else {
		snapshot.parsed = Parser.materialise_tokens(snapshot.owned_source, ifx mode != .FULL then old, start, end);
		snapshot.parsed.fully_pathed_filename = filename;
		parse_tokens(*snapshot.parsed, ifx mode == .AST then old, start, end);
	}
}

profile_sequence :: (source: string, filename: string, edits: []Update_Edit, mode: Update_Mode) -> [SEQUENCE_EDIT_COUNT]Snapshot_Memory {
	snapshots: [SEQUENCE_SNAPSHOT_COUNT]Update_Snapshot;
	counts: [SEQUENCE_SNAPSHOT_COUNT]Snapshot_Allocations;
	results: [SEQUENCE_EDIT_COUNT]Snapshot_Memory;
	assert(edits.count == results.count);
	backing := context.allocator;
	profile_snapshot(*snapshots[0], *counts[0], backing, source, filename);
	print(
		"    % untimed memory: initial retained=% source=% bytes caller_requests=% requested_bytes=% backing_requests=% backing_bytes=%\n",
		mode,
		counts[0].backing.live,
		source.count,
		counts[0].caller.requests,
		counts[0].caller.bytes,
		counts[0].backing.requests, counts[0].backing.bytes
	);

	for edit, index: edits {
		old := *snapshots[index];
		next := *snapshots[index + 1];
		old_counts := *counts[index];
		next_counts := *counts[index + 1];
		old_retained := old_counts.backing.live;
		assert(valid_edit(*old.parsed, edit));
		profile_snapshot(next, next_counts, backing, edit.source, filename, *old.parsed, mode, edit.start, edit.end);
		assert(old_counts.backing.live == old_retained);
		results[index] = .{
			requests = next_counts.caller.requests,
			requested_bytes = next_counts.caller.bytes,
			retained = next_counts.backing.live,
			overlap_peak = old_retained + next_counts.backing.peak
		};

		print(
			"      edit=% old_retained=% new_retained=% overlap=% overlap_peak=% old_source=% new_source=% bytes; caller_requests=% requested_bytes=% backing_requests=% backing_bytes=%\n",
			index + 1,
			old_retained,
			next_counts.backing.live,
			old_retained + next_counts.backing.live,
			results[index].overlap_peak,
			old.parsed.source.count,
			next.parsed.source.count,
			next_counts.caller.requests,
			next_counts.caller.bytes,
			next_counts.backing.requests,
			next_counts.backing.bytes
		);

		release_snapshot(*old.parsed, *old.storage);
		assert(old_counts.backing.live == 0 && old_counts.backing.sizes.count == 0);
		assert(next_counts.backing.live == results[index].retained);
		print("        after old release: old=0 new=% bytes\n", next_counts.backing.live);

		{
			check_storage: Pool;
			set_allocators(*check_storage, backing);
			push_allocator(.{proc = pool_allocator_proc, data = *check_storage});
			defer release(*check_storage);

			assert(Parser.reconstruct_source(*next.parsed) == edit.source);
		}
	}

	release_snapshot(*snapshots[edits.count].parsed, *snapshots[edits.count].storage);
	for *snapshot_counts: counts {
		assert(snapshot_counts.backing.live == 0 && snapshot_counts.backing.sizes.count == 0);
		table_reset(*snapshot_counts.backing.sizes);
	}

	print("      final release: all snapshot backing bytes=0; ledger checks PASS\n");
	return results;
}

percentile_index :: (sample_count: s64, percentile: s64) -> s64 {
	return (sample_count * percentile + PERCENT_SCALE - 1) / PERCENT_SCALE - 1;
}

report_latency :: (label: string, samples: []float64) -> float64, float64 {
	quick_sort(samples, (value: float64) -> float64 { return value; });
	median := samples[samples.count / 2];
	tail := samples[percentile_index(samples.count, TAIL_PERCENTILE)];
	print("      %: median=% p%=% range=%..% ms (n=%)\n", label, median, TAIL_PERCENTILE, tail, samples[0], samples[samples.count - 1], samples.count);
	return median, tail;
}

report_savings :: (label: string, baseline: float64, updated: float64) {
	print("    % savings=% ms (% percent)\n", label, baseline - updated, PERCENT_SCALE * (1 - updated / baseline));
}

measure_sequence :: (source: string, filename: string, frequency: s64, edits: []Update_Edit, name: string, category: string) {
	#if VERIFY_ONLY {
		print("  Verifying workload: % [%]\n", name, category);
	}

	for mode: UPDATE_MODES {
		run_sequence(source, filename, edits, mode, frequency, true);
	}

	#if VERIFY_ONLY {
		print("  Deep snapshot/lifetime checks PASS\n");
		return;
	}


	samples: [MODE_COUNT]Latency_Samples;

	for trial: 0..TOTAL_TRIAL_COUNT-1 {
		for offset: 0..MODE_COUNT-1 {
			mode := UPDATE_MODES[(trial + offset) % MODE_COUNT];
			result := run_sequence(source, filename, edits, mode, frequency, false);
			if trial >= WARMUP_COUNT {
				trial_index := trial - WARMUP_COUNT;
				mode_samples := *samples[mode.(s64)];
				mode_samples.initial[trial_index] = result.initial;
				mode_samples.release_final[trial_index] = result.release_final;
				for edit, index: result.edits {
					sample_index := trial_index * SEQUENCE_EDIT_COUNT + index;
					mode_samples.acquire[sample_index] = edit.acquire;
					mode_samples.lex[sample_index] = edit.lex;
					mode_samples.ast[sample_index] = edit.ast;
					mode_samples.construction[sample_index] = edit.construction;
					mode_samples.release_old[sample_index] = edit.release_old;
					mode_samples.lifecycle[sample_index] = edit.lifecycle;
					mode_samples.by_edit[index][trial_index] = edit.lifecycle;
				}
			}
		}
	}

	print("  Workload: % [%]; preliminary checks PASS; individual edits, source ownership and old release included\n", name, category);
	lifecycle_medians: [MODE_COUNT]float64;
	lifecycle_tails: [MODE_COUNT]float64;
	construction_medians: [MODE_COUNT]float64;
	for mode: UPDATE_MODES {
		index := mode.(s64);
		mode_samples := *samples[index];
		print("    %\n", mode);
		report_latency("lex+internal edit validation", mode_samples.lex);
		report_latency("AST+binding", mode_samples.ast);
		construction_medians[index] = report_latency("construction", mode_samples.construction);
		report_latency("new pool+owned source copy", mode_samples.acquire);
		report_latency("old snapshot release", mode_samples.release_old);
		lifecycle_medians[index], lifecycle_tails[index] = report_latency("owned lifecycle", mode_samples.lifecycle);
		for edit_samples, edit_index: mode_samples.by_edit {
			print("      edit=%\n", edit_index + 1);
			report_latency("owned lifecycle by edit", edit_samples);
		}

		report_latency("initial owned snapshot (outside update)", mode_samples.initial);
		report_latency("final snapshot release (outside update)", mode_samples.release_final);
	}

	FULL_INDEX :: Update_Mode.FULL.(s64);
	TOKENS_INDEX :: Update_Mode.TOKENS.(s64);
	AST_INDEX :: Update_Mode.AST.(s64);
	report_savings("AST versus TOKENS lifecycle median", lifecycle_medians[TOKENS_INDEX], lifecycle_medians[AST_INDEX]);
	report_savings("AST versus TOKENS lifecycle p95", lifecycle_tails[TOKENS_INDEX], lifecycle_tails[AST_INDEX]);
	report_savings("AST versus FULL lifecycle median", lifecycle_medians[FULL_INDEX], lifecycle_medians[AST_INDEX]);
	report_savings("AST versus FULL lifecycle p95", lifecycle_tails[FULL_INDEX], lifecycle_tails[AST_INDEX]);
	report_savings("TOKENS versus FULL lifecycle median", lifecycle_medians[FULL_INDEX], lifecycle_medians[TOKENS_INDEX]);
	report_savings("TOKENS versus FULL lifecycle p95", lifecycle_tails[FULL_INDEX], lifecycle_tails[TOKENS_INDEX]);
	report_savings("AST versus TOKENS construction median", construction_medians[TOKENS_INDEX], construction_medians[AST_INDEX]);

	profiles: [MODE_COUNT][SEQUENCE_EDIT_COUNT]Snapshot_Memory;
	for mode: UPDATE_MODES {
		profiles[mode.(s64)] = profile_sequence(source, filename, edits, mode);
	}

	for 0..edits.count-1 {
		baseline := profiles[TOKENS_INDEX][it];
		updated := profiles[AST_INDEX][it];

		print(
			"    edit=% AST versus TOKENS memory savings: requests=% (% percent); requested=% (% percent) retained=% (% percent) overlap_peak=% (% percent) bytes\n",
			it + 1,
			baseline.requests - updated.requests,
			PERCENT_SCALE * (1 - updated.requests.(float64) / baseline.requests.(float64)),
			baseline.requested_bytes - updated.requested_bytes,
			PERCENT_SCALE * (1 - updated.requested_bytes.(float64) / baseline.requested_bytes.(float64)),
			baseline.retained - updated.retained, PERCENT_SCALE * (1 - updated.retained.(float64) / baseline.retained.(float64)),
			baseline.overlap_peak - updated.overlap_peak,
			PERCENT_SCALE * (1 - updated.overlap_peak.(float64) / baseline.overlap_peak.(float64))
		);
	}
}

measure_patch_sequence :: (source: string, filename: string, frequency: s64, start: s64, end: s64, first_payload: string, second_payload: string, name: string, category: string, malformed: bool = false) {
	assert(start >= 0 && end >= start && end <= source.count);
	prefix := slice(source, 0, start);
	suffix := slice(source, end, source.count - end);

	first := sprint("%%%", prefix, first_payload, suffix);
	second := sprint("%%%", prefix, second_payload, suffix);
	defer free(first);
	defer free(second);

	edits := Update_Edit.[
		.{source = first,	start = start,	end = end},
		.{source = second,	start = start,	end = start + first_payload.count, expect_added_errors = malformed},
		.{source = source,	start = start,	end = start + second_payload.count, restores_baseline = true}
	];

	print(
		"  Edit anchor: byte=%/% (% percent), removed=% bytes; inserted/replaced/restored payloads=%/%/% bytes\n",
		start,
		source.count,
		start.(float64) * PERCENT_SCALE / source.count.(float64),
		end - start,
		first_payload.count,
		second_payload.count, end - start
	);
	measure_sequence(source, filename, frequency, edits, name, category);
}

simple_candidate :: (parsed: *Parser.Parsed_Source, node: *Parser.Parser_Node) -> bool {
	if !node || node.kind != .DECLARATION {
		return false;
	}


	declaration := node.(*Parser.Parser_Declaration);
	last := node.one_past_last_token.(s64);
	return declaration.expression && Parser.reusable_expression(declaration.expression)
		&& (!declaration.type_inst || Parser.reusable_type_instantiation(declaration.type_inst))
		&& !declaration.notes.count && !declaration.alignment_expression && !declaration.import_target
		&& last < parsed.tokens.count && parsed.tokens[last].type == #char ";";
}

root_anchor_byte :: (parsed: *Parser.Parsed_Source, node: *Parser.Parser_Node) -> s64 {
	index := node.first_token.(s64);
	return ifx index > 0 && parsed.tokens[index - 1].original_text == "#" && parsed.tokens[index - 1].byte_end == parsed.tokens[index].byte_start
		then parsed.tokens[index - 1].byte_start
		else parsed.tokens[index].byte_start;
}

nearest_root_anchor :: (parsed: *Parser.Parsed_Source, target: s64, pair: bool = false) -> s64 {
	statements := parsed.root.(*Parser.Parser_Block).statements;
	best: s64 = -1;
	distance := parsed.source.count + 1;
	for statement, index: statements {
		if pair && (index + 1 >= statements.count || !simple_candidate(parsed, statement) || !simple_candidate(parsed, statements[index + 1])) {
			continue;
		}


		byte := root_anchor_byte(parsed, statement);
		delta := abs(byte - target);
		if delta < distance {
			distance = delta;
			best = index;
		}
	}

	return best;
}

nearest_procedure_body :: (parsed: *Parser.Parsed_Source, target: s64) -> *Parser.Parser_Block {
	best: *Parser.Parser_Block;
	distance := parsed.source.count + 1;
	for node: parsed.root.(*Parser.Parser_Block).statements {
		if node.kind != .DECLARATION {
			continue;
		}


		value := node.(*Parser.Parser_Declaration).expression;
		if !value || value.kind != .PROCEDURE_HEADER {
			continue;
		}


		header := value.(*Parser.Parser_Procedure_Header);
		if !header.body_or_null || !header.body_or_null.block {
			continue;
		}


		block := header.body_or_null.block;
		token := parsed.tokens[block.first_token.(s64)];
		if token.type != #char "{" {
			continue;
		}


		delta := abs(token.byte_start - target);
		if delta < distance {
			distance = delta;
			best = block;
		}
	}

	return best;
}

find_nested_declaration_block :: (parsed: *Parser.Parsed_Source, scope: *Parser.Parser_Lexical_Scope) -> *Parser.Parser_Block {
	for child: scope.children {
		if child.owner && child.owner.kind == .BLOCK {
			block := child.owner.(*Parser.Parser_Block);
			if block.block_type == .DATA_DECLARATIONS && parsed.tokens[block.first_token.(s64)].type == #char "{" {
				return block;
			}
		}


		found := find_nested_declaration_block(parsed, child);
		if found {
			return found;
		}
	}


	return null;
}

measure_realistic_updates :: (source: string, filename: string, frequency: s64) {
	storage: Pool;
	set_allocators(*storage);
	previous_allocator := context.allocator;
	context.allocator = .{proc = pool_allocator_proc, data = *storage};
	parsed := Parser.parse_file(source, filename);
	context.allocator = previous_allocator;
	defer release_snapshot(*parsed, *storage);

	assert(parsed.root && parsed.root_scope);
	root := parsed.root.(*Parser.Parser_Block);
	declaration_category := ifx parsed.status == .COMPLETE
		then "eligible-declaration-context"
		else "recovered-baseline fallback";

	positions := s64.[5, 50, 95];
	labels := string.["start", "middle", "end"];

	for position, index: positions {
		target := source.count * position / PERCENT_SCALE;
		anchor := nearest_root_anchor(*parsed, target);
		if anchor >= 0 {
			start := root_anchor_byte(*parsed, root.statements[anchor]);
			name := sprint("root-declaration-%", labels[index]);
			defer free(name);

			measure_patch_sequence(source, filename, frequency, start, start, "__parser_benchmark_enabled :: false;\n", "__parser_benchmark_enabled :: true;\n", name, declaration_category);
			malformed_name := sprint("malformed-repair-%", labels[index]);
			defer free(malformed_name);

			measure_patch_sequence(source, filename, frequency, start, start, "__parser_benchmark_enabled :: true;\n", "__parser_benchmark_enabled :: ;\n", malformed_name, "malformed/repair fallback", true);
		} else {
			print("  SKIPPED root edits at %: no declaration boundary.\n", labels[index]);
		}

		body := nearest_procedure_body(*parsed, target);
		if body {
			start := parsed.tokens[body.first_token.(s64)].byte_end;
			name := sprint("procedure-body-%", labels[index]);
			defer free(name);

			measure_patch_sequence(
				source,
				filename,
				frequency,
				start,
				start,
				"\n\t__parser_benchmark_enabled := false;\n",
				"\n\t__parser_benchmark_enabled := true;\n",
				name,
				"procedure-body reparse (other declarations may copy)"
			);
		} else {
			print("  SKIPPED procedure edits at %: no braced top-level procedure.\n", labels[index]);
		}
	}

	nested := find_nested_declaration_block(*parsed, parsed.root_scope);
	if nested {
		start := parsed.tokens[nested.first_token.(s64)].byte_end;
		measure_patch_sequence(source, filename, frequency, start, start, "\n\t__parser_benchmark_enabled :: false;\n", "\n\t__parser_benchmark_enabled :: true;\n", "nested-declaration", declaration_category);
	} else {
		print("  SKIPPED nested-declaration: no existing braced declaration block.\n");
	}

	pair := nearest_root_anchor(*parsed, source.count / 2, true);
	if pair >= 0 {
		left := root.statements[pair];
		right := root.statements[pair + 1];
		start := parsed.tokens[left.first_token.(s64)].byte_start;
		left_end := parsed.tokens[left.one_past_last_token.(s64)].byte_end;
		end := parsed.tokens[right.one_past_last_token.(s64)].byte_end;
		both := slice(source, start, end - start);

		first := sprint("#if true {\n%\n}\n", both);
		second := sprint("#if true {\n%\n}\n%", slice(source, start, left_end - start), slice(source, left_end, end - left_end));
		defer free(first);
		defer free(second);

		measure_patch_sequence(source, filename, frequency, start, end, first, second, "move-closing-brace-across-declaration", "scope/boundary reparse (other declarations may copy)");
	} else {
		print("  SKIPPED scope-boundary: no adjacent simple declaration pair.\n");
	}
}

visit :: (info: *File_Visit_Info, filenames: *[..]string) {
	if ends_with(info.short_name, ".jai") {
		array_add(filenames, copy_string(info.full_name));
	}
}

main :: () {
	test_allocation_profile();
	#if VERIFY_ONLY {
		test_snapshot_oracle();
	}

	arguments := get_command_line_arguments();
	assert(arguments.count <= 2, "Usage: benchmark_ast_reuse [CORPUS_DIRECTORY]");
	directory := ifx arguments.count == 2
		then arguments[1]
		else "../../../examples/invaders";

	filenames: [..]string;
	visit_files(directory, true, *filenames, visit, visit_symlinks = false);
	defer {
		for filenames {
			free(it);
		}

		array_free(filenames);
	}

	assert(!!filenames.count);
	print("File order: filesystem visitation order.\n");
	frequency :: 1000000000;
	bytes: s64;
	lines: s64;
	tokens: s64;
	complete: s64;
	print("AST reuse investigation: independent file snapshots; default SIMD, trivia, copied names, lexical binding enabled.\n");
	#if VERIFY_ONLY {
		print("Verification only: deep fresh-parse comparisons before/after old-source poisoning and release; actual declaration-copy counts; no timing trials.\n");
	} else {
		print("Baseline and %-mode edit comparison; no keep/drop decision. % warmups, % rotating-order trials/file; reuse instrumentation compiled out.\n", MODE_COUNT, WARMUP_COUNT, TRIAL_COUNT);
	}

	for filename: filenames {
		source, ok := read_entire_file(filename);
		assert(ok);
		defer free(source);

		line_count: s64;
		if source.count {
			line_count = 1;
			for source {
				if it == #char "\n" {
					line_count += 1;
				}
			}
		}

		storage: Pool;
		set_allocators(*storage);
		previous_allocator := context.allocator;
		context.allocator = .{proc = pool_allocator_proc, data = *storage};
		parsed := Parser.parse_file(source, filename);
		assert(parsed.root != null);
		reconstructed := Parser.reconstruct_source(*parsed);
		assert(reconstructed == source);
		print("%: bytes=% lines=% tokens=% status=% diagnostics=% round-trip=PASS\n", filename, source.count, line_count, parsed.tokens.count, parsed.status, parsed.diagnostics.count);
		bytes += source.count;
		lines += line_count;
		tokens += parsed.tokens.count;
		if parsed.status == .COMPLETE && !parsed.diagnostics.count {
			complete += 1;
		}

		release_snapshot(*parsed, *storage);
		context.allocator = previous_allocator;
		#if !VERIFY_ONLY {
			measure_baseline(source, filename, frequency);
		}

		measure_updates(source, filename, frequency);
		measure_realistic_updates(source, filename, frequency);
	}

	print("Corpus: % files, % bytes, % lines (one plus LF bytes per nonempty file), % tokens incl EOF; % complete zero-diagnostic.\n", filenames.count, bytes, lines, tokens, complete);
}
