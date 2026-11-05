// Phase-3 owned-snapshot tests (C1): an owned parse must equal an independent fresh parse after its input and siblings are poisoned and released.
// Run from this directory: jai service_snapshot_test.jai -x64 -quiet && ./service_snapshot_test.exe
#import "Basic";
#import "Compiler";
#import "File";
#import "File_Utilities";
#import "Pool";
#import "String";

Service :: #import "Jai_Parser/service";
// Operators from a named import are not visible here, so alias the overloads the tests use.
operator == :: Service.operator ==;
Parser :: Service.Parser;
// The oracle's reuse-tracking self-checks need a TRACK_AST_REUSE parser; this one has the default.
VERIFY_ONLY :: false;
#load "snapshot_oracle.jai";

INPUT_POISON :: 0xDD;
JAI_ROOT :: #run tprint("%../../..", #filepath);

// W1 seeds for the owned-parse step: malformed, trivia-only and value-route sources.  Registry-route vectors extend this list in later steps.
W1_SOURCES :: string.[
	"",
	"\xEF\xBB\xBF",
	"// comment only\n",
	"/* unterminated /* nested",
	"#!shebang\nvalue :: 1;",
	"value :: ;",
	"broken: := ;\nnext :: 2;",
	"a, b := 1, 2; a=, b := f(); x.y, z[0] = v;",
	"#program_export \"exported\" entry :: () {}",
	"text :: \"tab\\t\\x41\"; raw :: #string END\nhere\nEND;",
	"hex :: 0xFF_FF; big :: 18446744073709551615; over :: 18446744073709551616; f :: 1.5e300; tiny :: 0.1;",
	"note :: 1 @note @\"quoted note\";",
	"proc :: (a: int, b := 2) -> int { return a + b; }",
	"S :: struct { x: int; #as using base: Base; } E :: enum u8 { A; B :: 3; }",
	"main :: () { if x == { case 1; #through; case 2; } for < it: items { defer free(it); } }",
	"\x01\xFF garbage ` tokens ### here"
];

main :: () {
	route_allocator = context.allocator;
	route_counts.allocator = context.allocator;

	test_snapshot_oracle();
	test_borrowed_parse_negative_control();
	test_token_tags();
	test_token_values();
	test_projection_negative_controls();
	test_node_vectors();
	test_node_negative_controls();
	test_statement_and_procedure_vectors();
	test_directive_vectors();
	test_assembly_vectors();
	test_route_vectors();
	test_flag_vectors();
	test_snapshot_and_diagnostics();
	test_snapshot_and_diagnostics_controls();
	test_declaration_index_vectors();
	test_declaration_index_controls();
	test_syntax_adapter_descriptor();

	for W1_SOURCES {
		check_owned_parse(it, tprint("w1_%.jai", it_index));
	}

	print("W1: % authored sources.\n", W1_SOURCES.count);
	report_node_coverage();

	inventories := string.["how_to", "examples/invaders", "modules/Jai_Parser", "modules/Basic"];
	recursive := bool.[false, true, false, false];
	for inventories {
		files := inventory_files(tprint("%/%", JAI_ROOT, it), recursive[it_index]);
		bytes: s64;
		for path: files {
			source, ok := read_entire_file(path);
			assert(ok, "Unable to read %.", path);
			bytes += source.count;
			check_owned_parse(source, path);
			free(source);
		}

		print("W2 %: % files, % bytes.\n", it, files.count, bytes);
		report_node_coverage();
	}

	report_route_coverage();
	print("Service snapshot PASS.\n");
}

inventory_files :: (directory: string, recursive: bool) -> [..] string {
	visit :: (info: *File_Visit_Info, files: *[..] string) {
		if !info.is_directory && ends_with(info.full_name, ".jai") {
			array_add(files, copy_string(info.full_name));
		}
	}

	files: [..] string;
	visit_files(directory, recursive, *files, visit, visit_symlinks = false);
	quick_sort(files, compare_strings);
	return files;
}

// Owns a parse, then poisons/frees the caller's buffer, releases a sibling owner and compares against a fresh parse of an independent copy.
check_owned_parse :: (text: string, temporary_path: string) {
	// Callers may pass a temporary-storage path, and this procedure resets temporary storage.
	path := copy_string(temporary_path);
	defer free(path);

	input := copy_string(text);
	owned := Service.own_parse(input, path);
	assert((!input.count || owned.source.data != input.data) && owned.filename.data != path.data);

	sibling := Service.own_parse(input, path);
	memset(input.data, INPUT_POISON, input.count);
	free(input);
	Service.release_owned_syntax(sibling);
	reset_temporary_storage();

	storage: Pool;
	set_allocators(*storage);
	defer release(*storage);
	push_allocator(pool_allocator_proc, *storage);

	fresh_source := copy_string(text);
	fresh := Parser.parse_file(fresh_source, path, resolve_identifiers = false);
	check_snapshot(*owned.parsed, *fresh);

	fault, snapshot := Service.project_snapshot(owned);
	assert(fault.failure == .NONE, "Snapshot of % failed: % at %[%].", path, fault.failure, fault.record, fault.index);
	assert(snapshot.source.data == owned.source.data && snapshot.root == snapshot.node_projection.root && snapshot.tokens.data == snapshot.token_projection.tokens.data);
	matched, reason := token_projection_matches(snapshot.token_projection, *fresh);
	assert(matched, "Projection of % differs: %.", path, reason);
	valid, problem := node_projection_invariants(snapshot.node_projection);
	assert(valid, "Node projection of % violates an invariant: %.", path, problem);
	node_coverage.projected += 1;
	tally_routes(snapshot.node_projection);
	for snapshot.recoveries {
		producer := owned.parsed.recovery_records[it_index];
		assert((it.owner == .NONE) == !producer.owner && it.cursor == producer.cursor && it.discarded == producer.discarded, "Recovery % of % ownership.", it_index, path);
		if it.owner == .NODE {
			assert(snapshot.nodes[it.owner_node_id].token_span.first == producer.owner.first_token.(s64), "Recovery % of % maps to the wrong node.", it_index, path);
		}

		node_coverage.unpublished += (it.owner == .UNPUBLISHED && !it.discarded).(s64);
		node_coverage.recoveries += (!it.discarded).(s64);
	}

	index_fault, index := Service.project_declaration_index(snapshot);
	assert(index_fault.failure == .NONE, "Index of % failed: % at %[%].", path, index_fault.failure, index_fault.record, index_fault.index);
	index_valid, index_problem := declaration_index_invariants(index, snapshot);
	assert(index_valid, "Index of % violates an invariant: %.", path, index_problem);
	node_coverage.entries += index.entries.count;
	node_coverage.partial += (index.coverage.kind == .PARTIAL_SYNTAX_TRAVERSAL).(s64);
	Service.release_declaration_index(index);
	Service.release_snapshot(snapshot);

	diagnostics_fault, diagnostics := Service.project_diagnostics(owned);
	assert(diagnostics_fault.failure == .NONE, "Diagnostics of % failed: % at %[%].", path, diagnostics_fault.failure, diagnostics_fault.record, diagnostics_fault.index);
	diagnostics_matched, diagnostics_reason := diagnostics_match(diagnostics, *fresh);
	assert(diagnostics_matched, "Diagnostics of % differ: %.", path, diagnostics_reason);
	Service.release_diagnostics_projection(diagnostics);

	Parser.release_parser_tree(*fresh);
	Parser.release_parser_names(*fresh);

	Service.release_owned_syntax(owned);
}

// A parse that borrows its caller's buffer must fail the same comparison once that buffer is poisoned.
test_borrowed_parse_negative_control :: () {
	TEXT :: "value :: \"borrowed\"; other := value;";
	storage: Pool;
	set_allocators(*storage);
	defer release(*storage);
	push_allocator(pool_allocator_proc, *storage);

	input := copy_string(TEXT);
	borrowed := Parser.parse_file(input, "borrowed.jai", resolve_identifiers = false);
	memset(input.data, INPUT_POISON, input.count);

	fresh := Parser.parse_file(copy_string(TEXT), "borrowed.jai", resolve_identifiers = false);
	check_snapshot(*borrowed, *fresh, expect_match = false);
}

// Compares every projected record with an independent fresh parse, reading the producer's own fields directly.
token_projection_matches :: (projection: *Service.Token_Projection, fresh: *Parser.Parsed_Source) -> bool, string {
	source := projection.owner.source;
	if projection.tokens.count != fresh.tokens.count {
		return false, "token count";
	}


	reconstructed: String_Builder;
	for record: projection.tokens {
		token := *fresh.tokens[it_index];
		if (slice(source, record.original.start, record.original.end - record.original.start) != token.original_text
			|| slice(source, record.preceding.start, record.preceding.end - record.preceding.start) != token.preceding_trivia
			|| record.origin.start != token.byte_start
			|| record.origin.end != token.byte_end
		) {
			return false, tprint("token % source slices", it_index);
		}


		if (record.coordinates.l0 != token.l0
			|| record.coordinates.c0 != token.c0
			|| record.coordinates.l1 != token.l1
			|| record.coordinates.c1 != token.c1
			|| record.value_flags != token.value_flags.(u32)
			|| record.ident_is_backticked != token.ident_is_backticked
		) {
			return false, tprint("token % observations", it_index);
		}


		_, tag := Service.token_tag(token.type);
		if record.tag != tag || !values_equal(record.value, expected_value(token)) {
			return false, tprint("token % tag/value", it_index);
		}


		append(*reconstructed, slice(source, record.preceding.start, record.preceding.end - record.preceding.start));
		append(*reconstructed, slice(source, record.original.start, record.original.end - record.original.start));
	}


	if builder_to_string(*reconstructed,, temp) != source {
		return false, "reconstruction";
	}


	last := projection.tokens[projection.tokens.count - 1];
	if last.tag != Service.Token_Tag.{kind = .NAMED, name = "END_OF_INPUT"} || last.origin.start != source.count || last.value.kind != .NO_VALUE {
		return false, "end-of-input record";
	}


	if projection.synthetic_tokens.count != fresh.synthetic_tokens.count {
		return false, "synthetic count";
	}


	for projection.synthetic_tokens {
		producer := *fresh.synthetic_tokens[it_index];
		_, tag := Service.token_tag(producer.token.type);
		if (it.insertion_index != producer.insertion_index.(s64)
			|| it.tag != tag
			|| it.coordinates.l0 != producer.token.l0
			|| it.coordinates.c1 != producer.token.c1
			|| it.value.kind != .NO_VALUE
		) {
			return false, tprint("synthetic %", it_index);
		}
	}


	if projection.recoveries.count != fresh.recovery_records.count {
		return false, "recovery count";
	}


	for projection.recoveries {
		producer := fresh.recovery_records[it_index];
		if (it.kind.(s64) != producer.kind.(s64)
			|| it.token_span.first != producer.span.first.(s64)
			|| it.token_span.one_past_last != producer.span.one_past_last.(s64)
			|| it.diagnostic_index != producer.diagnostic_index
			|| it.synthetic_token_index != producer.synthetic_token_index
		) {
			return false, tprint("recovery %", it_index);
		}
	}


	if projection.diagnostics.count != fresh.diagnostics.count {
		return false, "diagnostic count";
	}


	for projection.diagnostics {
		producer := *fresh.diagnostics[it_index];
		_, expected_tag := Service.token_tag(producer.expected_token);
		_, actual_tag := Service.token_tag(producer.actual_token);
		if (it.code.(s64) != producer.kind.(s64)
			|| it.severity.(s64) != producer.severity.(s64)
			|| it.recovery_action.(s64) != producer.recovery_action.(s64)
			|| it.token_span.first != producer.span.first.(s64)
			|| it.token_span.one_past_last != producer.span.one_past_last.(s64)
			|| it.message_bytes.(string) != producer.message
			|| it.expected_token != expected_tag
			|| it.actual_token != actual_tag
			|| it.lexer_line != producer.lexer_line
			|| it.lexer_column != producer.lexer_column
			|| it.related.count != producer.related_information.count
		) {
			return false, tprint("diagnostic %", it_index);
		}


		for related: it.related {
			other := producer.related_information[it_index];
			if related.message_bytes.(string) != other.message || related.token_span.first != other.span.first.(s64) {
				return false, "related diagnostic";
			}
		}
	}


	if projection.parse_status.(s64) != fresh.status.(s64) {
		return false, "parse status";
	}


	return true, "";
}

expected_value :: (token: *Parser.Parser_Token) -> Service.Token_Value {
	if token.type == .IDENT || token.type == .NOTE || (token.type >= .KEYWORD_FOR && token.type <= .KEYWORD_INTERFACE) {
		return .{kind = .NAME, bytes = xx token.ident_value.name.(string)};
	}


	if token.type == .STRING {
		return .{kind = .STRING_BYTES, bytes = xx token.string_value};
	}


	if token.type == .NUMBER {
		return ifx token.value_flags & .FLOAT
			then Service.Token_Value.{kind = .FLOAT64_BITS, bits = (*token.float64_value).(*u64).*}
			else Service.Token_Value.{kind = .UNSIGNED_INTEGER, bits = token.integer_value};
	}


	return .{kind = .NO_VALUE};
}

values_equal :: (a: Service.Token_Value, b: Service.Token_Value) -> bool {
	return a.kind == b.kind && a.bits == b.bits && a.bytes.(string) == b.bytes.(string);
}

// The registry's 77 names, aliases, byte characters and unregistered producer values.
test_token_tags :: () {
	assert(Service.TOKEN_TAG_NAMES.count == 77);
	for a, i: Service.TOKEN_TAG_NAMES {
		for b, j: Service.TOKEN_TAG_NAMES {
			assert(i == j || a != b, "Duplicate token tag %.", a);
		}
	}

	// Every producer name at or above 256 is registered under its own name, except the two keyword aliases and the two AST-only operator values.
	info := type_info(Parser.Token_Type);
	for name: info.names {
		value := info.values[it_index];
		if value < 256 || begins_with(name, "__") || begins_with(name, "OPERATOR_") {
			continue;
		}


		ok, tag := Service.token_tag(xx value);
		assert(ok && tag.kind == .NAMED && tag.name == name, "Token % maps to %.", name, tag);
	}

	Byte :: (value: u8) -> Service.Token_Tag {
		return .{kind = .BYTE_CHAR, byte = value};
	}

	Named :: (name: string) -> Service.Token_Tag {
		return .{kind = .NAMED, name = name};
	}

	check :: (type: Parser.Token_Type, expected: Service.Token_Tag) {
		ok, tag := Service.token_tag(type);
		assert(ok && tag == expected, "Token type % maps to %, expected %.", type.(s64), tag, expected);
	}

	check(.BITWISE_XOR, Byte(94));
	check(.BITWISE_NOT, Byte(126));
	check(.BITWISE_AND, Byte(38));
	check(.BITWISE_OR, Byte(124));
	check(.__FIRST_KEYWORD, Named("KEYWORD_FOR"));
	check(.__LAST_KEYWORD, Named("KEYWORD_INTERFACE"));
	check(xx 0, Byte(0));
	check(xx 255, Byte(255));
	check(xx #char ";", Byte(59));
	check(.IDENT, Named("IDENT"));
	check(.ERROR, Named("ERROR"));

	for value: s16.[-1, 278, 289, 400, 499, 500, 501, 503, 1000] {
		ok := Service.token_tag(xx value);
		assert(!ok, "Unregistered producer value % mapped.", value);
	}
}

// Authored expectations for each active value arm, independent of the producer's discriminator logic.
test_token_values :: () {
	SOURCE :: "h :: 0x10; f :: 1.5; s :: \"t\\tz\"; o :: 18446744073709551616; k := cast(int) x; n :: 1 @\"quoted note\" @plain;";
	owned := Service.own_parse(SOURCE, "values.jai");
	defer Service.release_owned_syntax(owned);

	fault, projection := Service.project_tokens(owned);
	assert(fault.failure == .NONE);
	defer Service.release_token_projection(projection);

	find :: (projection: *Service.Token_Projection, spelling: string) -> Service.Token_Record {
		for projection.tokens {
			if slice(projection.owner.source, it.original.start, it.original.end - it.original.start) == spelling {
				return it;
			}
		}

		assert(false, "No token spelled %.", spelling);
		return .{};
	}

	hex := find(projection, "0x10");
	assert(hex.value.kind == .UNSIGNED_INTEGER && hex.value.bits == 16);
	decimal := find(projection, "1.5");
	assert(decimal.value.kind == .FLOAT64_BITS && decimal.value.bits == 0x3FF8_0000_0000_0000);
	text := find(projection, "\"t\\tz\"");
	assert(text.value.kind == .STRING_BYTES && text.value.bytes.(string) == "t\tz");
	overflow := find(projection, "18446744073709551616");
	assert(overflow.value.kind == .UNSIGNED_INTEGER && !!(overflow.value_flags & 0x1000_0000));
	keyword := find(projection, "cast");
	assert(keyword.tag.name == "KEYWORD_CAST" && keyword.value.kind == .NAME && keyword.value.bytes.(string) == "cast");
	semicolon := find(projection, ";");
	assert(semicolon.tag.kind == .BYTE_CHAR && semicolon.tag.byte == #char ";" && semicolon.value.kind == .NO_VALUE);

	notes: [..] string;
	for projection.tokens {
		if it.tag.name == "NOTE" {
			assert(it.value.kind == .NAME);
			array_add(*notes, it.value.bytes.(string),, temp);
		}
	}

	assert(notes.count == 2 && notes[0] == "quoted note" && notes[1] == "plain", "Notes: %", notes);

	last := projection.tokens[projection.tokens.count - 1];
	assert(last.tag.name == "END_OF_INPUT" && last.origin.start == SOURCE.count && last.origin.end == SOURCE.count && last.value.kind == .NO_VALUE);

	MISSING :: "value :: (";
	missing := Service.own_parse(MISSING, "missing.jai");
	defer Service.release_owned_syntax(missing);

	missing_fault, missing_projection := Service.project_tokens(missing);
	assert(missing_fault.failure == .NONE && missing_projection.synthetic_tokens.count > 0 && missing_projection.diagnostics.count > 0);
	for missing_projection.recoveries {
		if it.kind == .MISSING_TOKEN {
			assert(it.synthetic_token_index >= 0 && it.synthetic_token_index < missing_projection.synthetic_tokens.count);
			assert(missing_projection.diagnostics[it.diagnostic_index].recovery_action == .INSERT_MISSING_TOKEN);
		}
	}

	Service.release_token_projection(missing_projection);
}

// Each injected producer defect must fail conversion with its own reason, and the comparator must notice an altered record.
test_projection_negative_controls :: () {
	SOURCE :: "value :: 1; other := \"text\";";
	expect :: (mutate: (*Parser.Parsed_Source), expected: Service.Projection_Failure) {
		owned := Service.own_parse(SOURCE, "negative.jai");
		mutate(*owned.parsed);
		fault, projection := Service.project_tokens(owned);
		assert(fault.failure == expected && !projection, "Expected %, got %.", expected, fault.failure);
		Service.release_owned_syntax(owned);
	}

	unknown_flag :: (p: *Parser.Parsed_Source) {
		p.tokens[0].value_flags = xx 0x80;
	}

	unregistered_type :: (p: *Parser.Parsed_Source) {
		p.tokens[2].type = xx 278;
	}

	shifted_text :: (p: *Parser.Parsed_Source) {
		p.tokens[1].original_text.data += 1;
	}

	widened_origin :: (p: *Parser.Parsed_Source) {
		p.tokens[3].byte_end += 1;
	}

	expect(unknown_flag, .UNKNOWN_VALUE_FLAGS);
	expect(unregistered_type, .UNREGISTERED_TOKEN_TYPE);
	expect(shifted_text, .UNMAPPED_SOURCE_SLICE);
	expect(widened_origin, .UNMAPPED_SOURCE_SLICE);

	owned := Service.own_parse(SOURCE, "negative.jai");
	defer Service.release_owned_syntax(owned);

	fault, projection := Service.project_tokens(owned);
	assert(fault.failure == .NONE);
	defer Service.release_token_projection(projection);

	storage: Pool;
	set_allocators(*storage);
	defer release(*storage);

	push_allocator(pool_allocator_proc, *storage);
	fresh := Parser.parse_file(copy_string(SOURCE), "negative.jai", resolve_identifiers = false);

	matched := token_projection_matches(projection, *fresh);
	assert(matched);
	projection.tokens[2].coordinates.c1 += 1;
	matched = token_projection_matches(projection, *fresh);
	assert(!matched, "Comparator missed an altered coordinate.");
	projection.tokens[2].coordinates.c1 -= 1;
	projection.tokens[4].value.bytes.count -= 1;
	matched = token_projection_matches(projection, *fresh);
	assert(!matched, "Comparator missed an altered value.");

	print("Token projection tags, values and negative controls PASS\n");
}

#import "Sort";

Node_Coverage :: struct {
	projected: s64;
	diagnostics: s64;
	entries: s64;
	partial: s64;
	recoveries: s64;
	unpublished: s64;
}

node_coverage: Node_Coverage;

report_node_coverage :: () {
	print(
		"  snapshots: % projected, % diagnostics, % index entries, % partial indices, % recovery events (% with unpublished owners)\n",
		node_coverage.projected,
		node_coverage.diagnostics,
		node_coverage.entries,
		node_coverage.partial,
		node_coverage.recoveries,
		node_coverage.unpublished
	);
	node_coverage = .{};
}

// Independent origin oracle: reads the fresh parse's own tokens, recovery records and synthetic tokens.
diagnostics_match :: (projection: *Service.Diagnostics_Projection, fresh: *Parser.Parsed_Source) -> bool, string {
	if projection.records.count != fresh.diagnostics.count || projection.parse_status.(s64) != fresh.status.(s64) {
		return false, "record count or status";
	}


	node_coverage.diagnostics += fresh.diagnostics.count;
	source := projection.owner.source;
	expected_origin :: (fresh: *Parser.Parsed_Source, first: s64, one_past_last: s64) -> (located: bool, start: s64, end: s64) {
		count := fresh.tokens.count;
		if first < 0 || one_past_last < first || one_past_last > count || first >= count {
			return false, 0, 0;
		}


		start := fresh.tokens[first].byte_start;
		return true, start, ifx one_past_last > first then fresh.tokens[one_past_last - 1].byte_end else start;
	}

	for record, index: projection.records {
		producer := *fresh.diagnostics[index];
		if record.message_utf8 != producer.message || record.code.(s64) != producer.kind.(s64) || record.related.count != producer.related_information.count {
			return false, tprint("diagnostic % payload", index);
		}


		origin := record.primary_origin;
		if producer.recovery_action == .INSERT_MISSING_TOKEN {
			synthetic_index := -1;
			for fresh.recovery_records {
				if it.kind == .MISSING_TOKEN && it.diagnostic_index == index {
					synthetic_index = it.synthetic_token_index;
				}
			}

			if synthetic_index < 0 {
				return false, tprint("diagnostic % has no synthetic token in the fresh parse", index);
			}


			insertion := fresh.synthetic_tokens[synthetic_index].insertion_index.(s64);
			anchor := fresh.tokens[insertion].byte_start;
			if origin.kind != .INSERTED || origin.span.start != anchor || origin.span.end != anchor {
				return false, tprint("diagnostic % inserted origin", index);
			}
		} else {
			located, start, end := expected_origin(fresh, producer.span.first.(s64), producer.span.one_past_last.(s64));
			if located != (origin.kind == .SOURCE) || (located && (origin.span.start != start || origin.span.end != end)) {
				return false, tprint("diagnostic % source origin", index);
			}
		}

		if origin.kind != .UNLOCATED && (origin.span.start < 0 || origin.span.end < origin.span.start || origin.span.end > source.count) {
			return false, tprint("diagnostic % origin outside the source", index);
		}


		for related: record.related {
			other := producer.related_information[it_index];
			located, start, end := expected_origin(fresh, other.span.first.(s64), other.span.one_past_last.(s64));
			if related.message_utf8 != other.message || located != (related.origin.kind == .SOURCE) || (located && related.origin.span.start != start) {
				return false, tprint("diagnostic % related %", index, it_index);
			}
		}
	}

	return true, "";
}

// Authored expectations for the envelope root and for inserted, zero-width and lexer origins.
test_snapshot_and_diagnostics :: () {
	{
		SOURCE :: "value :: (";
		owned := Service.own_parse(SOURCE, "missing.jai");
		defer Service.release_owned_syntax(owned);

		fault, diagnostics := Service.project_diagnostics(owned);
		assert(fault.failure == .NONE);
		defer Service.release_diagnostics_projection(diagnostics);

		// The parser reports expected-expression holes at end of input, then inserts the missing `;`.
		inserted := 0;
		for diagnostics.records {
			assert(it.primary_origin.span.start == SOURCE.count && it.primary_origin.span.end == SOURCE.count, "Every diagnostic here anchors at end of input.");
			if it.parser_observation.recovery_action == .INSERT_MISSING_TOKEN {
				inserted += 1;
				assert(it.primary_origin.kind == .INSERTED && it.primary_origin.expected_token == it.parser_observation.expected_token);
				assert(it.primary_origin.expected_token.kind == .BYTE_CHAR && it.primary_origin.expected_token.byte == #char ";");
			} else {
				assert(it.code == .EXPECTED_EXPRESSION && it.primary_origin.kind == .SOURCE);
			}
		}

		assert(inserted == 1 && diagnostics.records.count == 3 && diagnostics.parse_status != .COMPLETE);
	}

	{
		SOURCE :: "a :: ;";
		owned := Service.own_parse(SOURCE, "expected.jai");
		defer Service.release_owned_syntax(owned);

		fault, diagnostics := Service.project_diagnostics(owned);
		assert(fault.failure == .NONE && diagnostics.records.count >= 1);
		defer Service.release_diagnostics_projection(diagnostics);

		first := diagnostics.records[0];
		assert(first.code == .EXPECTED_EXPRESSION && first.primary_origin.kind == .SOURCE);
		assert(first.primary_origin.span.start == 5 && first.primary_origin.span.end == 5, "An expected expression anchors zero-width at the `;`, got %.", first.primary_origin.span);
	}

	{
		SOURCE :: "a :: 1;\ns :: \"bad \\q escape\";";
		owned := Service.own_parse(SOURCE, "lexer.jai");
		defer Service.release_owned_syntax(owned);

		fault, diagnostics := Service.project_diagnostics(owned);
		assert(fault.failure == .NONE);
		defer Service.release_diagnostics_projection(diagnostics);

		lexer_errors := 0;
		for diagnostics.records {
			if it.code == .LEXER_ERROR {
				lexer_errors += 1;
				assert(it.primary_origin.kind == .SOURCE && it.primary_origin.span.start >= 7);
			}
		}

		assert(lexer_errors >= 1, "Expected a lexer error.");
	}

	{
		owned := Service.own_parse("a :: 1;", "rootless.jai");
		defer Service.release_owned_syntax(owned);

		owned.parsed.root = null;
		fault, snapshot := Service.project_snapshot(owned);
		assert(fault.failure == .NONE && snapshot.root == -1 && !snapshot.nodes.count && snapshot.tokens.count == owned.parsed.tokens.count, "A rootless parse keeps its tokens with root -1.");
		Service.release_snapshot(snapshot);
	}

	print("Snapshot envelope and diagnostics vectors PASS\n");
}

// Each injected defect fails the envelope or diagnostics conversion with its own reason, or degrades an origin to unlocated.
test_snapshot_and_diagnostics_controls :: () {
	{
		owned := Service.own_parse("a :: b + 1;", "negative.jai");
		defer Service.release_owned_syntax(owned);

		declaration := owned.parsed.root.(*Parser.Parser_Block).statements[0].(*Parser.Parser_Declaration);
		declaration.expression.(*Parser.Parser_Binary_Operator).flags = xx 0x80;
		fault, snapshot := Service.project_snapshot(owned);
		assert(fault.failure == .UNKNOWN_SOURCE_FLAGS && !snapshot, "A node failure fails the whole envelope.");
	}

	{
		owned := Service.own_parse("a :: ;", "negative.jai");
		defer Service.release_owned_syntax(owned);

		owned.parsed.diagnostics[0].message = "bad \xFF byte";
		fault, diagnostics := Service.project_diagnostics(owned);
		assert(fault.failure == .INVALID_TEXT && !diagnostics);
	}

	{
		owned := Service.own_parse("value :: (", "negative.jai");
		defer Service.release_owned_syntax(owned);

		for * owned.parsed.recovery_records {
			if it.kind == .MISSING_TOKEN {
				it.synthetic_token_index = owned.parsed.synthetic_tokens.count;
			}
		}

		fault, diagnostics := Service.project_diagnostics(owned);
		assert(fault.failure == .INVALID_REFERENCE && !diagnostics);
	}

	{
		owned := Service.own_parse("value :: (", "negative.jai");
		defer Service.release_owned_syntax(owned);

		duplicate: Parser.Recovery_Record;
		for owned.parsed.recovery_records {
			if it.kind == .MISSING_TOKEN {
				duplicate = it;
			}
		}

		array_add(*owned.parsed.recovery_records, duplicate);
		fault, diagnostics := Service.project_diagnostics(owned);
		assert(fault.failure == .NONE);
		defer Service.release_diagnostics_projection(diagnostics);

		for diagnostics.records {
			if it.parser_observation.recovery_action == .INSERT_MISSING_TOKEN && it_index == duplicate.diagnostic_index {
				assert(it.primary_origin.kind == .UNLOCATED && it.primary_origin.reason == .RECOVERED_LOCATION_UNAVAILABLE, "Ambiguous correlation is unlocated, not guessed.");
			}
		}
	}

	assert(!Service.is_valid_utf8(xx "\xC0\x80") && !Service.is_valid_utf8(xx "\xED\xA0\x80") && !Service.is_valid_utf8(xx "\xF4\x90\x80\x80") && !Service.is_valid_utf8(xx "\xE2\x82"));
	assert(Service.is_valid_utf8(xx "plain \xC3\xA9 \xE2\x82\xAC \xF0\x9F\x98\x80"));
	print("Snapshot envelope and diagnostics controls PASS\n");
}

// Independent shape checks: dense preorder IDs, each non-root node owned exactly once by an earlier record, helpers likewise.
node_projection_invariants :: (projection: *Service.Node_Projection) -> bool, string {
	if !projection.nodes.count {
		return projection.root == -1, "empty projection without a -1 root";
	}


	if projection.root != 0 {
		return false, "root is not node 0";
	}


	node_owners := NewArray(projection.nodes.count, s64,, temp);
	helper_owners := NewArray(projection.helpers.count, s64,, temp);
	for * node_owners {
		it.* = -1;
	}

	for * helper_owners {
		it.* = -1;
	}

	check_value :: (value: Service.Field_Value, owner: s64, node_owners: [] s64, helper_owners: [] s64) -> bool {
		if value.kind == {
			case .NODE;
				if value.signed == -1 {
					return true;
				}


				// Aliases name an existing node without owning it.
				if value.relationship == .ALIAS {
					return value.signed >= 0 && value.signed < node_owners.count;
				}


				if value.signed <= 0 || value.signed >= node_owners.count || node_owners[value.signed] != -1 {
					return false;
				}


				node_owners[value.signed] = owner;

			case .HELPER;
				if value.signed == -1 {
					return true;
				}


				if value.signed < 0 || value.signed >= helper_owners.count || helper_owners[value.signed] != -1 {
					return false;
				}


				helper_owners[value.signed] = owner;

			case .LIST;
				for value.elements {
					if !check_value(it, owner, node_owners, helper_owners) {
						return false;
					}
				}
		}


		return true;
	}

	for record, record_index: projection.nodes {
		if record.local_node_id != xx record_index {
			return false, tprint("node % has id %", record_index, record.local_node_id);
		}


		for record.fields {
			if !check_value(it.value, record_index, node_owners, helper_owners) {
				return false, tprint("node % field % has a bad or repeated reference", record_index, it.path[it.path.count - 1].name);
			}
		}
	}


	for record, record_index: projection.helpers {
		for record.fields {
			if !check_value(it.value, -2 - record_index, node_owners, helper_owners) {
				return false, tprint("helper % field % has a bad or repeated reference", record_index, it.path[it.path.count - 1].name);
			}
		}
	}


	for 1..node_owners.count - 1 {
		if node_owners[it] == -1 {
			return false, tprint("node % has no owner", it);
		}
	}


	for helper_owners {
		if it == -1 {
			return false, tprint("helper % has no owner", it_index);
		}
	}


	// Preorder: a node's owner precedes it.
	for 1..node_owners.count - 1 {
		owner := node_owners[it];
		if owner >= 0 && owner >= it {
			return false, tprint("node % is owned by later node %", it, owner);
		}
	}


	// Field observations are unique and sorted by canonical path bytes, computed here independently.
	check_order :: (fields: [] Service.Field_Observation) -> bool {
		previous: [] u8;
		for fields {
			key := authored_path_key(it.path);
			if it_index && Service.compare_canonical(previous, key) >= 0 {
				return false;
			}


			previous = key;
		}

		return true;
	}

	for projection.nodes {
		if !check_order(it.fields) {
			return false, tprint("node % fields out of canonical order", it_index);
		}
	}


	for projection.helpers {
		if !check_order(it.fields) {
			return false, tprint("helper % fields out of canonical order", it_index);
		}
	}


	return true, "";
}

// Literal K/V layout of a field path, written out from the contract rather than through the service's encoders.
authored_path_key :: (path: [] Service.Path_Step) -> [] u8 {
	frame :: (builder: *String_Builder, bytes: string) {
		count := bytes.count;
		for 0..7 {
			append(builder, ((count >> (8 * it)) & 0xFF).(u8));
		}

		append(builder, bytes);
	}

	key :: (tag: string, fields: .. string) -> string {
		builder: String_Builder;
		frame(*builder, "jai-cache-key");
		append(*builder, "\x01\x00\x00\x00");
		frame(*builder, tag);
		count := fields.count;
		for 0..7 {
			append(*builder, ((count >> (8 * it)) & 0xFF).(u8));
		}

		for fields {
			frame(*builder, it);
		}

		return builder_to_string(*builder,, temp);
	}

	SCHEMA :: "jai-cache-interface/1/PathStep";
	schema := key("ascii", SCHEMA);
	steps := NewArray(path.count + 1, string,, temp);
	steps[0] = schema;
	for path {
		steps[it_index + 1] = key("variant", schema, "FIELD", key("ascii", it.name));
	}

	return xx key("sequence", ..steps);
}

get_field :: (fields: [] Service.Field_Observation, names: .. string) -> Service.Field_Value {
	for fields {
		if it.path.count != names.count {
			continue;
		}


		matched := true;
		for step: it.path {
			if step.name != names[it_index] {
				matched = false;
			}
		}

		if matched {
			return it.value;
		}
	}


	assert(false, "No field %.", names);
	return .{};
}

project_source_nodes :: (source: string) -> *Service.Owned_Syntax, *Service.Node_Projection {
	owned := Service.own_parse(source, "vector.jai");
	fault, projection := Service.project_nodes(owned);
	assert(fault.failure == .NONE, "Node projection of '%' failed: % (%).", source, fault.failure, fault.record);
	valid, problem := node_projection_invariants(projection);
	assert(valid, "Invariant: %", problem);
	tally_routes(projection);
	return owned, projection;
}

// Authored expectations: exact IDs, kinds, child references and scalar observations for small registered-only sources.
test_node_vectors :: () {
	kinds :: (projection: *Service.Node_Projection) -> string {
		builder: String_Builder;
		for projection.nodes {
			print(*builder, "% ", it.kind);
		}

		return builder_to_string(*builder,, temp);
	}

	{
		owned, projection := project_source_nodes("a :: b + 1;");
		defer Service.release_owned_syntax(owned);
		defer Service.release_node_projection(projection);

		assert(kinds(projection) == "BLOCK DECLARATION BINARY_OPERATOR IDENT LITERAL ", "Kinds: %", kinds(projection));
		nodes := projection.nodes;
		statements := get_field(nodes[0].fields, "statements");
		assert(statements.kind == .LIST && statements.elements.count == 1 && statements.elements[0].signed == 1);
		assert(get_field(nodes[0].fields, "block_type").name == "DATA_DECLARATIONS");
		assert(get_field(nodes[1].fields, "entry", "name").bytes.(string) == "a");
		assert(get_field(nodes[1].fields, "expression").signed == 2 && get_field(nodes[1].fields, "type_inst").signed == -1);
		declaration_flags := get_field(nodes[1].fields, "flags");
		assert(declaration_flags.names.count == 1 && declaration_flags.names[0] == "IS_CONSTANT");
		operator_field := get_field(nodes[2].fields, "operator_type");
		assert(operator_field.kind == .OPERATOR && operator_field.tag.kind == .BYTE_CHAR && operator_field.tag.byte == #char "+");
		assert(get_field(nodes[2].fields, "left").signed == 3 && get_field(nodes[2].fields, "right").signed == 4);
		assert(get_field(nodes[3].fields, "name").bytes.(string) == "b");
		assert(get_field(nodes[4].fields, "value_type").name == "NUMBER" && get_field(nodes[4].fields, "values", "_u64").unsigned == 1);
		assert(nodes[2].has_origin && slice(owned.source, nodes[2].origin.start, nodes[2].origin.end - nodes[2].origin.start) == "b + 1");
		assert(projection.helpers.count == 0);
	}

	{
		owned, projection := project_source_nodes("a, b := f(x, name = y);");
		defer Service.release_owned_syntax(owned);
		defer Service.release_node_projection(projection);

		assert(
			kinds(projection) == "BLOCK COMPOUND_DECLARATION COMMA_SEPARATED_ARGUMENTS IDENT IDENT DECLARATION PROCEDURE_CALL IDENT IDENT IDENT IDENT ",
			"Kinds: %",
			kinds(projection)
		);
		nodes := projection.nodes;
		assert(get_field(nodes[1].fields, "comma_separated_assignment").signed == 2 && get_field(nodes[1].fields, "declaration_properties").signed == 5);
		// `:=` lexes as `:` then `=`; the shared operator is the colon at token 3 and records operator value 0.
		operator_field := get_field(nodes[1].fields, "operator_type");
		assert(operator_field.tag.kind == .BYTE_CHAR && operator_field.tag.byte == 0 && get_field(nodes[1].fields, "operator_token").signed == 3);
		arguments := get_field(nodes[2].fields, "arguments");
		assert(arguments.elements.count == 2 && arguments.elements[0].signed == 0 && arguments.elements[1].signed == 1);
		assert(projection.helpers.count == 4);
		assert(projection.helpers[0].layout == "Parser_Comma_Separated_Argument" && get_field(projection.helpers[0].fields, "separator_token").signed == 1);
		assert(get_field(projection.helpers[1].fields, "separator_token").signed == -1);
		assert(get_field(nodes[5].fields, "expression").signed == 6);
		assert(get_field(nodes[6].fields, "procedure_expression").signed == 7 && get_field(nodes[6].fields, "context_modification").signed == -1);
		call_arguments := get_field(nodes[6].fields, "arguments_unsorted");
		assert(call_arguments.elements.count == 2 && call_arguments.elements[0].signed == 2 && call_arguments.elements[1].signed == 3);
		assert(get_field(projection.helpers[2].fields, "name").signed == -1 && get_field(projection.helpers[2].fields, "expression").signed == 8);
		assert(get_field(projection.helpers[3].fields, "name").signed == 9 && get_field(projection.helpers[3].fields, "expression").signed == 10);
	}

	{
		SOURCE :: "p: *[4] int = null; c := cast(u8) n; x := xx w; s := size_of(int); t := type_of(c); u := .[1, 2]; q := Point.{1, 2}; e := -n; d := #this; v := m.(u16);";
		owned, projection := project_source_nodes(SOURCE);
		defer Service.release_owned_syntax(owned);
		defer Service.release_node_projection(projection);

		find :: (projection: *Service.Node_Projection, kind: string, occurrence := 0) -> *Service.Node_Record {
			seen := 0;
			for * projection.nodes {
				if it.kind == kind {
					if seen == occurrence {
						return it;
					}


					seen += 1;
				}
			}

			assert(false, "No % #%.", kind, occurrence);
			return null;
		}

		pointer := find(projection, "TYPE_INSTANTIATION");
		assert(get_field(pointer.fields, "pointer_to").signed == pointer.local_node_id.(s64) + 1 && get_field(pointer.fields, "array_dimension").kind == .INACTIVE);
		array := find(projection, "TYPE_INSTANTIATION", 1);
		dimension := get_field(array.fields, "array_dimension").signed;
		element := get_field(array.fields, "array_element_type").signed;
		assert(dimension > 0 && element > dimension, "Fixed arrays visit the dimension before the element.");
		null_count: s64;
		for projection.nodes {
			if it.kind == "LITERAL" && get_field(it.fields, "value_type").name == "POINTER" {
				assert(get_field(it.fields, "values", "pointer_literal_info").kind == .SOURCE_NULL);
				null_count += 1;
			}
		}

		assert(null_count == 1);

		prefix := find(projection, "CAST");
		assert(get_field(prefix.fields, "target_type").signed < get_field(prefix.fields, "expression").signed, "Prefix casts visit the target first.");
		auto := find(projection, "CAST", 1);
		assert(get_field(auto.fields, "target_type").kind == .INACTIVE && get_field(auto.fields, "cast_flags").names[0] == "IS_AUTO");
		postfix := find(projection, "CAST", 2);
		assert(get_field(postfix.fields, "expression").signed < get_field(postfix.fields, "target_type").signed, "Postfix casts visit the expression first.");

		assert(get_field(find(projection, "TYPE_QUERY").fields, "query_kind").name == "SIZE_OF");
		assert(get_field(find(projection, "EXPRESSION_QUERY").fields, "query_kind").name == "TYPE_OF");
		unary := find(projection, "UNARY_OPERATOR");
		assert(get_field(unary.fields, "operator_type").tag.byte == #char "-");
		find(projection, "DIRECTIVE_THIS");

		array_helper_count: s64;
		struct_helper_count: s64;
		for projection.helpers {
			if it.layout == "Parser_Array_Literal_Info" {
				array_helper_count += 1;
				assert(get_field(it.fields, "array_literal_flags").names[0] == "WAS_UNTYPED");
				assert(get_field(it.fields, "array_members").elements.count == 2);
			} else if it.layout == "Parser_Struct_Literal_Info" {
				struct_helper_count += 1;
				assert(get_field(it.fields, "type_expression").signed > 0 && get_field(it.fields, "arguments").elements.count == 2);
			}
		}

		assert(array_helper_count == 1 && struct_helper_count == 1);
	}

	// Named producer operators lie in the byte range (131-169) yet must project by name, not as byte characters.
	{
		owned, projection := project_source_nodes("c := a == b; d := x[0]; e := p.*; f := a <= b;");
		defer Service.release_owned_syntax(owned);
		defer Service.release_node_projection(projection);

		names: [..] string;
		for projection.nodes {
			if it.kind == "BINARY_OPERATOR" || it.kind == "UNARY_OPERATOR" {
				operator_field := get_field(it.fields, "operator_type");
				assert(operator_field.kind == .OPERATOR && operator_field.tag.kind == .NAMED, "Operator % is not named.", operator_field.tag);
				array_add(*names, operator_field.tag.name,, temp);
			}
		}

		assert(names.count == 4 && names[0] == "IS_EQUAL" && names[1] == "ARRAY_SUBSCRIPT" && names[2] == "POSTFIX_DEREFERENCE" && names[3] == "LESS_OR_EQUAL", "Operators: %", names);
	}

	print("Node projection authored vectors PASS\n");
}

// Each injected producer defect fails node conversion with its own reason.
test_node_negative_controls :: () {
	expect :: (source: string, mutate: (*Parser.Parsed_Source), expected: Service.Projection_Failure) {
		owned := Service.own_parse(source, "negative.jai");
		defer Service.release_owned_syntax(owned);

		mutate(*owned.parsed);
		fault, projection := Service.project_nodes(owned);
		assert(fault.failure == expected && !projection, "Expected %, got % (%).", expected, fault.failure, fault.record);
	}

	binary_of :: (parsed: *Parser.Parsed_Source) -> *Parser.Parser_Binary_Operator {
		declaration := parsed.root.(*Parser.Parser_Block).statements[0].(*Parser.Parser_Declaration);
		return declaration.expression.(*Parser.Parser_Binary_Operator);
	}

	none :: (parsed: *Parser.Parsed_Source) {
	}

	unknown_flag :: (parsed: *Parser.Parsed_Source) {
		binary_of(parsed).flags = xx 0x80;
	}

	shared_child :: (parsed: *Parser.Parsed_Source) {
		binary := binary_of(parsed);
		binary.right = binary.left;
	}

	unknown_operator :: (parsed: *Parser.Parsed_Source) {
		binary_of(parsed).operator_type = xx 0x3FF;
	}

	populated_dimension :: (parsed: *Parser.Parsed_Source) {
		declaration := parsed.root.(*Parser.Parser_Block).statements[0].(*Parser.Parser_Declaration);
		declaration.type_inst.array_dimension = declaration.expression;
	}

	forged_placeholder :: (parsed: *Parser.Parsed_Source) {
		declaration := parsed.root.(*Parser.Parser_Block).statements[0];
		assert(declaration.kind == .PLACEHOLDER);
		declaration.(*Parser.Parser_Placeholder).name = "forged";
	}

	expect("a :: b + 1;", unknown_flag, .UNKNOWN_SOURCE_FLAGS);
	expect("a :: b + 1;", shared_child, .UNREGISTERED_SHARING);
	expect("a :: b + 1;", unknown_operator, .UNKNOWN_PRODUCER_ENUM);
	expect("p: *int = q;", populated_dimension, .UNEXPECTED_ACTIVE_FIELD);
	expect("#placeholder name;", forged_placeholder, .UNQUALIFIED_ROUTE);
	compiler_only_kind :: (parsed: *Parser.Parsed_Source) {
		parsed.root.(*Parser.Parser_Block).statements[0].kind = .EXTRACT;
	}

	expect("a :: b;", compiler_only_kind, .UNREGISTERED_NODE_KIND);

	first_assembly :: (parsed: *Parser.Parsed_Source) -> *Parser.Parser_Asm {
		declaration := parsed.root.(*Parser.Parser_Block).statements[0].(*Parser.Parser_Declaration);
		body := declaration.expression.(*Parser.Parser_Procedure_Header).body_or_null;
		return body.block.statements[0].(*Parser.Parser_Asm);
	}

	second_arm :: (parsed: *Parser.Parsed_Source) {
		assembly := first_assembly(parsed);
		assembly.statements[0].register_declaration = assembly.statements[1].register_declaration;
	}

	unknown_statement_kind :: (parsed: *Parser.Parsed_Source) {
		first_assembly(parsed).statements[0].kind = xx 9;
	}

	bang_argument :: (parsed: *Parser.Parsed_Source) {
		instruction := first_assembly(parsed).statements[3].instruction;
		bang := instruction.operands[1].modifiers[0];
		bang.argument.expression = instruction.mnemonic;
	}

	expect(ASSEMBLY_SOURCE, second_arm, .UNEXPECTED_ACTIVE_FIELD);
	expect(ASSEMBLY_SOURCE, unknown_statement_kind, .UNKNOWN_PRODUCER_ENUM);
	expect(ASSEMBLY_SOURCE, bang_argument, .UNEXPECTED_ACTIVE_FIELD);

	header_of :: (parsed: *Parser.Parsed_Source) -> *Parser.Parser_Procedure_Header {
		declaration := parsed.root.(*Parser.Parser_Block).statements[0].(*Parser.Parser_Declaration);
		return declaration.expression.(*Parser.Parser_Procedure_Header);
	}

	unmatched_using :: (parsed: *Parser.Parsed_Source) {
		header_of(parsed).parameter_usings[0].expression = null;
	}

	reordered_using :: (parsed: *Parser.Parsed_Source) {
		header := header_of(parsed);
		header.parameter_usings[1].expression = header.arguments[0];
	}

	struct_notes :: (parsed: *Parser.Parsed_Source) {
		declaration := parsed.root.(*Parser.Parser_Block).statements[0].(*Parser.Parser_Declaration);
		declaration.expression.(*Parser.Parser_Struct).notes = NewArray(1, *Parser.Parser_Note);
	}

	defer_pop_with_body :: (parsed: *Parser.Parsed_Source) {
		body := header_of(parsed).body_or_null;
		push := body.block.statements[0].(*Parser.Parser_Push_Context);
		assert(push.kind == .PUSH_CONTEXT && !!push.block);
		push.push_context_flags |= 0x2;
	}

	expect("f :: (using a: A, b: B) {}", unmatched_using, .UNQUALIFIED_ROUTE);
	expect("f :: (using a: A, using b: B) {}", reordered_using, .UNQUALIFIED_ROUTE);
	expect("S :: struct { x: int; }", struct_notes, .UNEXPECTED_ACTIVE_FIELD);
	expect("f :: () { push_context c { g(); } }", defer_pop_with_body, .UNEXPECTED_ACTIVE_FIELD);

	first_expression :: (parsed: *Parser.Parsed_Source) -> *Parser.Parser_Node {
		return parsed.root.(*Parser.Parser_Block).statements[0].(*Parser.Parser_Declaration).expression;
	}

	foreign_import_callee :: (parsed: *Parser.Parsed_Source) {
		import_node := first_expression(parsed).(*Parser.Parser_Directive_Import);
		import_node.module_parameters_call.procedure_expression = import_node.module_parameters_call.arguments_unsorted[0].expression;
	}

	foreign_run_expression :: (parsed: *Parser.Parsed_Source) {
		run := first_expression(parsed).(*Parser.Parser_Directive_Run);
		run.expression = run.procedure.body_or_null;
	}

	null_code_payload :: (parsed: *Parser.Parsed_Source) {
		code := first_expression(parsed).(*Parser.Parser_Directive_Code);
		code.expression = code;
	}

	expect("M :: #import \"Module\"(ENABLED = true);", foreign_import_callee, .UNQUALIFIED_ROUTE);
	expect("VALUE :: #run -> int { return 1; };", foreign_run_expression, .UNQUALIFIED_ROUTE);
	expect("c :: #code,null;", null_code_payload, .UNEXPECTED_ACTIVE_FIELD);

	// The invariant checker must notice a repeated owning reference and out-of-order fields.
	owned, projection := project_source_nodes("a :: b + 1;");
	defer Service.release_owned_syntax(owned);
	defer Service.release_node_projection(projection);

	binary_fields := projection.nodes[2].fields;
	for * binary_fields {
		if it.path[0].name == "right" {
			it.value.signed = 3;
		}
	}

	valid := node_projection_invariants(projection);
	assert(!valid, "Invariant checker missed a repeated owning reference.");
	for * binary_fields {
		if it.path[0].name == "right" {
			it.value.signed = 4;
		}
	}

	valid = node_projection_invariants(projection);
	assert(valid);
	binary_fields[0], binary_fields[1] = binary_fields[1], binary_fields[0];
	valid = node_projection_invariants(projection);
	assert(!valid, "Invariant checker missed out-of-order fields.");

	print("Node projection negative controls PASS\n");
}

find_node :: (projection: *Service.Node_Projection, kind: string, occurrence := 0) -> *Service.Node_Record {
	seen := 0;
	for * projection.nodes {
		if it.kind == kind {
			if seen == occurrence {
				return it;
			}


			seen += 1;
		}
	}

	assert(false, "No % #%.", kind, occurrence);
	return null;
}

has_flag :: (value: Service.Field_Value, name: string) -> bool {
	return array_find(value.names, name);
}

node_id :: (record: *Service.Node_Record) -> s64 {
	return record.local_node_id.(s64);
}

// Authored expectations for control flow, procedures, quick lambdas and aggregates.
test_statement_and_procedure_vectors :: () {
	{
		SOURCE :: #string END
f :: (x: int, using b: B, c := 2) -> int {
	if x == {
		case 1; #through;
		case;
	}
	for < * thing, index: items {
		break thing;
	}
	while c {
		defer free(c);
	}
	v := ifx x then 1 else 2;
	return x;
}
END
		owned, projection := project_source_nodes(SOURCE);
		defer Service.release_owned_syntax(owned);
		defer Service.release_node_projection(projection);

		header := find_node(projection, "PROCEDURE_HEADER");
		arguments := get_field(header.fields, "arguments").elements;
		usings := get_field(header.fields, "parameter_usings").elements;
		assert(arguments.count == 3 && usings.count == 1);
		assert(usings[0].signed > arguments[0].signed && usings[0].signed < arguments[1].signed, "A parameter using precedes its argument.");
		using_record := *projection.nodes[usings[0].signed];
		using_target := get_field(using_record.fields, "expression");
		assert(using_target.relationship == .ALIAS && using_target.signed == arguments[1].signed, "The using expression is an alias to its argument.");
		assert(get_field(header.fields, "returns").elements.count == 1);
		body := get_field(header.fields, "body_or_null").signed;
		assert(projection.nodes[body].kind == "PROCEDURE_BODY");

		switch := find_node(projection, "IF");
		assert(has_flag(get_field(switch.fields, "if_flags"), "IS_SWITCH_STATEMENT"));
		first_case := find_node(projection, "CASE");
		default_case := find_node(projection, "CASE", 1);
		assert(get_field(first_case.fields, "marked_as_fallthrough").boolean && get_field(first_case.fields, "condition").signed > 0);
		assert(!get_field(default_case.fields, "marked_as_fallthrough").boolean && get_field(default_case.fields, "condition").signed == -1);

		loop := find_node(projection, "FOR");
		loop_flags := get_field(loop.fields, "for_flags");
		assert(has_flag(loop_flags, "REVERSE") && has_flag(loop_flags, "POINTER") && loop_flags.names[0] == "POINTER", "Flags: %", loop_flags.names);
		it_name := get_field(loop.fields, "ident_it").signed;
		index_name := get_field(loop.fields, "ident_it_index").signed;
		iteration := get_field(loop.fields, "iteration_expression").signed;
		assert(it_name > 0 && index_name > it_name && iteration > index_name && get_field(loop.fields, "block").signed > iteration);
		assert(get_field(loop.fields, "want_reverse_expression").signed == -1 && get_field(loop.fields, "iteration_expression_right").signed == -1);
		control := find_node(projection, "LOOP_CONTROL");
		assert(get_field(control.fields, "control_type").name == "BREAK" && get_field(control.fields, "target_ident").signed > 0);

		loop_while := find_node(projection, "WHILE");
		assert(get_field(loop_while.fields, "condition").signed < get_field(loop_while.fields, "block").signed);
		assert(get_field(find_node(projection, "DEFER").fields, "block").signed > 0);
		conditional := find_node(projection, "IF", 1);
		assert(has_flag(get_field(conditional.fields, "if_flags"), "IS_IFX") && get_field(conditional.fields, "else_block").signed > 0);

		return_record := find_node(projection, "RETURN");
		assert(get_field(return_record.fields, "arguments_unsorted").elements.count == 1);
		assert(!get_field(return_record.fields, "return_flags").names.count);
	}

	{
		owned, projection := project_source_nodes("f :: x => x + 1;");
		defer Service.release_owned_syntax(owned);
		defer Service.release_node_projection(projection);

		header := find_node(projection, "PROCEDURE_HEADER");
		assert(has_flag(get_field(header.fields, "procedure_flags"), "QUICK"));
		quick_return := find_node(projection, "RETURN");
		assert(has_flag(get_field(quick_return.fields, "return_flags"), "AUTO_INSERTED_FOR_QUICK_LAMBDA"));
		assert(node_id(find_node(projection, "PROCEDURE_BODY")) < node_id(quick_return) && node_id(quick_return) < node_id(find_node(projection, "BINARY_OPERATOR")));
	}

	{
		SOURCE :: "S :: struct (N: int) #no_padding { a: int; } U :: union { x: int; } E :: enum_flags u8 #specified { A :: 1; B; }";
		owned, projection := project_source_nodes(SOURCE);
		defer Service.release_owned_syntax(owned);
		defer Service.release_node_projection(projection);

		aggregate := find_node(projection, "STRUCT");
		assert(has_flag(get_field(aggregate.fields, "textual_flags"), "NO_PADDING"));
		parameters := get_field(aggregate.fields, "arguments_block").signed;
		assert(parameters > 0 && parameters < get_field(aggregate.fields, "block").signed, "Struct parameters precede the body.");
		assert(get_field(projection.nodes[parameters].fields, "block_type").name == "STRUCT_ARGUMENTS");
		union_record := find_node(projection, "STRUCT", 1);
		assert(has_flag(get_field(union_record.fields, "textual_flags"), "UNION") && get_field(union_record.fields, "arguments_block").signed == -1);
		enumeration := find_node(projection, "ENUM");
		assert(get_field(enumeration.fields, "is_flags").boolean && get_field(enumeration.fields, "marked_as_specified").boolean);
		assert(get_field(enumeration.fields, "internal_type_inst").signed < get_field(enumeration.fields, "block").signed);
	}

	{
		owned, projection := project_source_nodes("f :: () { push_context c { g(); } }");
		defer Service.release_owned_syntax(owned);
		defer Service.release_node_projection(projection);

		push := find_node(projection, "PUSH_CONTEXT");
		assert(get_field(push.fields, "to_push").signed < get_field(push.fields, "block").signed);
	}

	print("Statement and procedure vectors PASS\n");
}

// Authored expectations for directive payloads, the import-callee association and the arrow-run body alias.
test_directive_vectors :: () {
	{
		SOURCE :: "M :: #import \"Module\"(ENABLED = true); #load \"other.jai\"; lib :: #library,system \"kernel32\"; #scope_file";
		owned, projection := project_source_nodes(SOURCE);
		defer Service.release_owned_syntax(owned);
		defer Service.release_node_projection(projection);

		import_record := find_node(projection, "DIRECTIVE_IMPORT");
		assert(get_field(import_record.fields, "name").bytes.(string) == "Module");
		call_id := get_field(import_record.fields, "module_parameters_call").signed;
		assert(call_id > node_id(import_record) && get_field(import_record.fields, "program_parameters_call").signed == -1);
		callee := get_field(projection.nodes[call_id].fields, "procedure_expression");
		assert(callee.relationship == .ALIAS && callee.signed == node_id(import_record), "An import parameter call's callee is an alias to its import.");
		assert(get_field(projection.nodes[call_id].fields, "arguments_unsorted").elements.count == 1);
		assert(get_field(find_node(projection, "DIRECTIVE_LOAD").fields, "short_name").bytes.(string) == "other.jai");
		library := find_node(projection, "DIRECTIVE_LIBRARY");
		assert(get_field(library.fields, "name").bytes.(string) == "kernel32" && has_flag(get_field(library.fields, "library_flags"), "IS_SYSTEM_LIBRARY"));
		assert(get_field(find_node(projection, "DIRECTIVE_SCOPE").fields, "scope_type").name == "FILE");
	}

	{
		owned, projection := project_source_nodes("VALUE :: #run -> int { return 1; };");
		defer Service.release_owned_syntax(owned);
		defer Service.release_node_projection(projection);

		run := find_node(projection, "DIRECTIVE_RUN");
		header := get_field(run.fields, "procedure").signed;
		assert(header > node_id(run) && projection.nodes[header].kind == "PROCEDURE_HEADER");
		body := get_field(projection.nodes[header].fields, "body_or_null").signed;
		block := get_field(projection.nodes[body].fields, "block").signed;
		expression := get_field(run.fields, "expression");
		assert(expression.relationship == .ALIAS && expression.signed == block, "An arrow run's expression is an alias to its header's body block.");
	}

	{
		owned, projection := project_source_nodes("f :: (loc := #caller_location) { c := #code,null; d := #code x + 1; }");
		defer Service.release_owned_syntax(owned);
		defer Service.release_node_projection(projection);

		location := find_node(projection, "DIRECTIVE_LOCATION");
		assert(get_field(location.fields, "is_caller_location").boolean && get_field(location.fields, "expression").signed == -1);
		null_code := find_node(projection, "DIRECTIVE_CODE");
		assert(has_flag(get_field(null_code.fields, "code_flags"), "NULL") && get_field(null_code.fields, "expression").kind == .INACTIVE);
		ordinary_code := find_node(projection, "DIRECTIVE_CODE", 1);
		assert(get_field(ordinary_code.fields, "expression").signed > node_id(ordinary_code));
	}

	// A typed array literal's parenthesised element type yields a wrapper whose interval starts at `(`, yet its form is the fixed array inside.
	{
		owned, projection := project_source_nodes("a := ([2] int).[.[1, 2]];");
		defer Service.release_owned_syntax(owned);
		defer Service.release_node_projection(projection);

		arrays := 0;
		for * projection.nodes {
			if it.kind != "TYPE_INSTANTIATION" || get_field(it.fields, "array_dimension").kind == .INACTIVE {
				continue;
			}


			arrays += 1;
			dimension := get_field(it.fields, "array_dimension").signed;
			assert(dimension > 0 && get_field(it.fields, "array_element_type").signed > dimension && get_field(it.fields, "type_valued_expression").kind == .INACTIVE);
			first := owned.parsed.tokens[it.token_span.first].type;
			assert(first == #char "(", "The fixed-array wrapper should start at the parenthesis.");
		}

		assert(arrays == 1, "Fixed arrays: %", arrays);
	}

	print("Directive vectors PASS\n");
}

// Routes no other vector or W1/W2 file reaches: rarely used directives, using filters, import forms, `---` and assembly arms.
ROUTE_SOURCE :: #string END
#placeholder P;
w :: #wildcard;
e :: #exists(Foo);
e2 :: #exists(Foo, true);
n :: #procedure_name();
n2 :: #procedure_name(g);
bytes :: #bytes "abc";
#poke_name Basic poked;
F :: #import,file "a.jai";
D :: #import,dir "lib";
S :: #import,string "x :: 1;";
g :: () {
	#through;
	using,only(a) s;
	using,except(b) t;
	using,map(m) u;
	x = ---;
	#asm {
		5;
		mov p === rax, q;
		mov c !n, d !d, e !u, f &h;
	}
}
END

test_route_vectors :: () {
	owned, projection := project_source_nodes(ROUTE_SOURCE);
	defer Service.release_owned_syntax(owned);
	defer Service.release_node_projection(projection);

	assert(!owned.parsed.diagnostics.count, "Route vectors should parse cleanly; first diagnostic: %.", ifx owned.parsed.diagnostics.count then owned.parsed.diagnostics[0].message);
	for string.["PLACEHOLDER", "DIRECTIVE_WILDCARD", "DIRECTIVE_EXISTS", "DIRECTIVE_PROCEDURE_NAME", "DIRECTIVE_BYTES", "DIRECTIVE_POKE_NAME", "DIRECTIVE_THROUGH"] {
		find_node(projection, it);
	}

	exists_with_sync := find_node(projection, "DIRECTIVE_EXISTS", 1);
	assert(get_field(exists_with_sync.fields, "sync_expression").signed > 0);
	assert(get_field(find_node(projection, "DIRECTIVE_PROCEDURE_NAME").fields, "argument").signed == -1);
	assert(get_field(find_node(projection, "DIRECTIVE_PROCEDURE_NAME", 1).fields, "argument").signed > 0);
	imports := string.["PATH_TO_FILE", "PATH_TO_DIRECTORY", "FULL_TEXT"];
	for imports {
		assert(get_field(find_node(projection, "DIRECTIVE_IMPORT", it_index).fields, "import_type").name == it);
	}

	filters := string.["ONLY", "EXCEPT", "MAP"];
	for filters {
		assert(get_field(find_node(projection, "USING", it_index).fields, "filter_type").name == it);
	}

	// A populated semantic backreference is never traversed or recorded.
	{
		SOURCE :: "a :: 1; b :: a;";
		plain_owned, plain := project_source_nodes(SOURCE);
		defer Service.release_owned_syntax(plain_owned);
		defer Service.release_node_projection(plain);

		linked := Service.own_parse(SOURCE, "linked.jai");
		defer Service.release_owned_syntax(linked);
		statements := linked.parsed.root.(*Parser.Parser_Block).statements;
		use := statements[1].(*Parser.Parser_Declaration).expression.(*Parser.Parser_Ident);
		use.resolved_declaration = statements[0].(*Parser.Parser_Declaration);
		fault, projection := Service.project_nodes(linked);
		assert(fault.failure == .NONE && projection.nodes.count == plain.nodes.count && projection.helpers.count == plain.helpers.count);
		defer Service.release_node_projection(projection);
		for projection.nodes {
			assert(it.kind == plain.nodes[it_index].kind && it.fields.count == plain.nodes[it_index].fields.count, "Node % changed with a populated backreference.", it_index);
		}
	}

	print("Route vectors PASS\n");
}

// Source flags that only rare modifiers set.
FLAG_SOURCE :: #string END
h :: () #compiler #no_context #intrinsic #no_debug #entry_point #entry_point_hook #no_call {}
St :: struct #foreign #type_info_no_size_complaint { x: int; }
v: int #elsewhere;
k :: cast,truncate,very_force(int) 1;
L :: #library,no_static_library "lib";
r :: #run,stallable h();
precise :: 1.2345678;
g :: () {
	no_inline h();
	push_context,defer_pop c;
	`push_context c {
	}
}
END

test_flag_vectors :: () {
	owned, projection := project_source_nodes(FLAG_SOURCE);
	defer Service.release_owned_syntax(owned);
	defer Service.release_node_projection(projection);

	assert(!owned.parsed.diagnostics.count, "Flag vectors should parse cleanly; first diagnostic: %.", ifx owned.parsed.diagnostics.count then owned.parsed.diagnostics[0].message);
	print("Flag vectors PASS\n");
}

ASSEMBLY_SOURCE :: #string END
f :: () {
	#asm AVX512F {
		mov.64 apple:, 10;
		banana: gpr;
		gatherdps dest:, [base + index*4], mask;
		cvtps2dq v5: &* mask, v4 !z;
		popcnt?BITS result, value;
	}
}
END

// Authored expectations for assembly helpers: kind-selected arms, embedded value slots, sizes and modifiers.
test_assembly_vectors :: () {
	owned, projection := project_source_nodes(ASSEMBLY_SOURCE);
	defer Service.release_owned_syntax(owned);
	defer Service.release_node_projection(projection);

	assembly := find_node(projection, "ASM");
	assert(get_field(assembly.fields, "features").elements.count == 1);
	statement_ids := get_field(assembly.fields, "statements").elements;
	assert(statement_ids.count == 5);
	helper :: (projection: *Service.Node_Projection, value: Service.Field_Value) -> *Service.Helper_Record {
		assert(value.kind == .HELPER && value.signed >= 0, "Expected a helper, got %.", value.kind);
		return *projection.helpers[value.signed];
	}

	statements: [5] *Service.Helper_Record;
	for statement_ids {
		statements[it_index] = helper(projection, it);
		assert(statements[it_index].layout == "Parser_Asm_Statement");
	}

	declaration := statements[1];
	assert(get_field(declaration.fields, "kind").name == "REGISTER_DECLARATION" && get_field(declaration.fields, "instruction").kind == .INACTIVE);
	register := helper(projection, get_field(declaration.fields, "register_declaration"));
	assert(!get_field(register.fields, "is_inferred").boolean && get_field(register.fields, "register_class").signed > 0);

	fixed := helper(projection, get_field(statements[0].fields, "instruction"));
	fixed_size := helper(projection, get_field(fixed.fields, "size"));
	assert(get_field(fixed_size.fields, "kind").name == "FIXED" && get_field(fixed_size.fields, "polymorphic_name").kind == .INACTIVE);
	polymorphic := helper(projection, get_field(statements[4].fields, "instruction"));
	polymorphic_size := helper(projection, get_field(polymorphic.fields, "size"));
	assert(get_field(polymorphic_size.fields, "kind").name == "POLYMORPHIC" && get_field(polymorphic_size.fields, "polymorphic_name").signed > 0);

	gather := helper(projection, get_field(statements[2].fields, "instruction"));
	address := helper(projection, get_field(gather.fields, "operands").elements[1]);
	assert(get_field(address.fields, "kind").name == "MEMORY" && get_field(address.fields, "value").kind == .INACTIVE);
	memory := helper(projection, get_field(address.fields, "memory"));
	base_value := helper(projection, get_field(memory.fields, "base"));
	index_value := helper(projection, get_field(memory.fields, "index"));
	scale_value := helper(projection, get_field(memory.fields, "scale"));
	assert(get_field(memory.fields, "displacement").kind == .INACTIVE, "An unused displacement slot is inactive.");
	base_node := get_field(base_value.fields, "expression").signed;
	index_node := get_field(index_value.fields, "expression").signed;
	assert(base_node > 0 && index_node > base_node && get_field(scale_value.fields, "expression").signed > index_node);

	masked := helper(projection, get_field(statements[3].fields, "instruction"));
	operands := get_field(masked.fields, "operands").elements;
	masked_declaration := helper(projection, operands[0]);
	ampersand := helper(projection, get_field(masked_declaration.fields, "modifiers").elements[0]);
	assert(get_field(ampersand.fields, "kind").name == "AMPERSAND_STAR" && get_field(ampersand.fields, "argument").kind == .HELPER);
	bang := helper(projection, get_field(helper(projection, operands[1]).fields, "modifiers").elements[0]);
	assert(get_field(bang.fields, "kind").name == "BANG_Z" && get_field(bang.fields, "argument").kind == .INACTIVE);

	print("Assembly vectors PASS\n");
}

// Independent declaration-index checks: owners recomputed from the snapshot's fields, containers derived upwards, visibility from list order,
// bindings from the recorded modifiers.
declaration_index_invariants :: (index: *Service.Declaration_Index, snapshot: *Service.Syntax_Snapshot) -> bool, string {
	nodes := snapshot.nodes;
	entries := index.entries;
	source := snapshot.source;
	owners := NewArray(nodes.count, s64,, temp);
	owner_fields := NewArray(nodes.count, string,, temp);
	entry_of_node := NewArray(nodes.count, s64,, temp);
	region_of_compound := NewArray(nodes.count, s64,, temp);
	for 0..nodes.count - 1 {
		owners[it] = -1;
		entry_of_node[it] = -1;
		region_of_compound[it] = -1;
	}

	collect :: (value: Service.Field_Value, owner: s64, field: string, snapshot: *Service.Syntax_Snapshot, owners: [] s64, owner_fields: [] string) {
		if value.kind == {
			case .LIST;
				for value.elements {
					collect(it, owner, field, snapshot, owners, owner_fields);
				}

			case .NODE;
				if value.signed >= 0 && value.relationship == .OWNED {
					owners[value.signed] = owner;
					owner_fields[value.signed] = field;
				}

			case .HELPER;
				if value.signed >= 0 {
					for snapshot.helpers[value.signed].fields {
						collect(it.value, owner, field, snapshot, owners, owner_fields);
					}
				}
		}
	}

	for record, id: nodes {
		for record.fields {
			collect(it.value, id, it.path[0].name, snapshot, owners, owner_fields);
		}
	}

	is_properties :: (id: s64, nodes: [] Service.Node_Record, owners: [] s64, owner_fields: [] string) -> bool {
		owner := owners[id];
		return owner >= 0 && nodes[owner].kind == "COMPOUND_DECLARATION" && owner_fields[id] == "declaration_properties";
	}


	// The nearest enclosing entry declaration or shared payload, walking owners upwards from `node`.
	expected_container :: (node: s64, nodes: [] Service.Node_Record, owners: [] s64, owner_fields: [] string, entry_of_node: [] s64, region_of_compound: [] s64) -> Service.Container {
		child := node;
		while owners[child] >= 0 {
			parent := owners[child];
			if nodes[parent].kind == "COMPOUND_DECLARATION" && owner_fields[child] != "comma_separated_assignment" {
				return .{kind = .SHARED_REGION, local_id = xx region_of_compound[parent]};
			}


			if entry_of_node[parent] >= 0 {
				return .{kind = .DECLARATION, local_id = xx entry_of_node[parent]};
			}


			child = parent;
		}

		return .{};
	}

	for index.shared_regions {
		compound := it.compound_node_id.(s64);
		if it.local_region_id != xx it_index || compound >= nodes.count || nodes[compound].kind != "COMPOUND_DECLARATION" || region_of_compound[compound] != -1 {
			return false, tprint("region % is malformed", it_index);
		}


		region_of_compound[compound] = it_index;
	}

	previous_node := 0;
	for entry, entry_index: entries {
		node := entry.declaration_node_id.(s64);
		if entry.local_entry_id != xx entry_index || node >= nodes.count || node < previous_node {
			return false, tprint("entry % has a bad ID or is out of event order", entry_index);
		}


		previous_node = node;
		expected_kind := ifx entry.syntax_kind == .DECLARATION
			then "DECLARATION"
			else ifx entry.syntax_kind == .COMPOUND_BINDING
				then "COMPOUND_DECLARATION"
				else "IDENT";
		if nodes[node].kind != expected_kind {
			return false, tprint("entry % names a % node", entry_index, nodes[node].kind);
		}


		if entry.syntax_kind == .DECLARATION {
			if is_properties(node, nodes, owners, owner_fields) || entry_of_node[node] != -1 {
				return false, tprint("entry % repeats or indexes a compound's properties", entry_index);
			}


			entry_of_node[node] = entry_index;
		}
	}


	for nodes {
		if it.kind == "DECLARATION" && !is_properties(it_index, nodes, owners, owner_fields) && entry_of_node[it_index] == -1 {
			return false, tprint("declaration node % has no entry", it_index);
		}


		if it.kind == "COMPOUND_DECLARATION" && region_of_compound[it_index] == -1 {
			return false, tprint("compound node % has no region", it_index);
		}


		if it.kind == "ENUM" {
			block := get_field(it.fields, "block").signed;
			if block >= 0 {
				for statement: get_field(nodes[block].fields, "statements").elements {
					if nodes[statement.signed].kind != "IDENT" {
						continue;
					}


					found := false;
					for entries {
						found ||= it.syntax_kind == .ENUM_MEMBER && it.declaration_node_id == xx statement.signed;
					}

					if !found {
						return false, tprint("bare enum member % has no entry", statement.signed);
					}
				}
			}
		}
	}


	// An event reaches an entry when the entry's node is on its owner's ownership path, except through a compound's targets for its bindings.
	reaches :: (owner: s64, node: s64, binding: bool, owners: [] s64, owner_fields: [] string) -> bool {
		child := -1;
		current := owner;
		while current >= 0 {
			if current == node {
				return !binding || child < 0 || owner_fields[child] != "comma_separated_assignment";
			}


			child = current;
			current = owners[current];
		}

		return false;
	}

	unpublished := false;
	for snapshot.recoveries {
		unpublished ||= !it.discarded && it.owner == .UNPUBLISHED;
	}
	for entry, entry_index: entries {
		node := entry.declaration_node_id.(s64);
		container := expected_container(node, nodes, owners, owner_fields, entry_of_node, region_of_compound);
		if entry.container != container || (container.kind == .DECLARATION && container.local_id >= xx entry_index) {
			return false, tprint("entry % container % % differs from %", entry_index, entry.container.kind, entry.container.local_id, container);
		}


		child := node;
		list := -1;
		statement := -1;
		while owners[child] >= 0 {
			parent := owners[child];
			if nodes[parent].kind == "BLOCK" && owner_fields[child] == "statements" {
				list = parent;
				statement = child;
				break;
			}


			child = parent;
		}

		directive := -1;
		if list >= 0 {
			for get_field(nodes[list].fields, "statements").elements {
				if it.signed == statement {
					break;
				}


				if nodes[it.signed].kind == "DIRECTIVE_SCOPE" {
					directive = it.signed;
				}
			}
		}

		visibility := entry.visibility_syntax;
		tag := Service.Scope_Directive_Tag.UNSPECIFIED;		if directive >= 0 {
			if get_field(nodes[directive].fields, "scope_type").name == {
				case "EXPORT";		tag = .SCOPE_EXPORT;
				case "INTERNAL";	tag = .SCOPE_MODULE;
				case "FILE";		tag = .SCOPE_FILE;
			}
		}

		observed := ifx visibility.observations.count == 1 then visibility.observations[0].span;
		if (visibility.scope_basis.statement_list_node_id != list
			|| visibility.scope_basis.preceding_directive_node_id != directive
			|| visibility.scope_directive != tag
			|| visibility.observations.count != (directive >= 0).(s64)
			|| (directive >= 0 && (observed.start != nodes[directive].origin.start || observed.end != nodes[directive].origin.end))
		) {
			return false, tprint("entry % visibility differs from list % directive %", entry_index, list, directive);
		}


		name := entry.name;
		if name.kind == .SPELLED {
			span := name.origin.span;
			if name.origin.kind != .SOURCE || span.start < 0 || span.end > source.count || span.end <= span.start {
				return false, tprint("entry % name origin is invalid", entry_index);
			}


			spelling := name.spelling_bytes.(string);
			producer := name.producer_name_bytes.(string);
			if spelling != slice(source, span.start, span.end - span.start) {
				return false, tprint("entry % spelling is not its source slice", entry_index);
			}


			// The lexer drops a leading backtick, and each backslash inside an identifier together with the spaces after it (Invaders uses both).
			if name.form == .IDENTIFIER {
				builder: String_Builder;
				skipping := false;
				for spelling {
					if it == #char "\\" {
						skipping = true;
					} else if !(skipping && it == #char " ") && !(it_index == 0 && it == #char "`") {
						skipping = false;
						append(*builder, it);
					}
				}

				unescaped := builder_to_string(*builder,, temp);
				if unescaped != producer {
					return false, tprint("entry % identifier spelling '%' does not match '%'", entry_index, spelling, producer);
				}
			}


			recorded := ifx entry.syntax_kind == .DECLARATION
				then get_field(nodes[node].fields, "entry", "name").bytes.(string)
				else ifx entry.syntax_kind == .ENUM_MEMBER
					then get_field(nodes[node].fields, "name").bytes.(string)
					else producer;
			if producer != recorded {
				return false, tprint("entry % producer name differs from its node", entry_index);
			}
		} else if name.kind == .UNMAPPED {
			found := false;
			for index.coverage.reasons {
				found ||= it.code == .UNMAPPED_NAME && it.subject.local_node_id == name.reason.subject.local_node_id;
			}

			if !found {
				return false, tprint("entry % unmapped name has no top-level reason", entry_index);
			}
		} else if name.kind == .ANONYMOUS {
			owner := owners[node];
			if owner < 0 || nodes[owner].kind != "PROCEDURE_HEADER" || get_field(nodes[node].fields, "entry", "name").bytes.count {
				return false, tprint("entry % is anonymous outside a header slot", entry_index);
			}
		}


		expected_status := ifx unpublished
			then type_of(Service.Recovery_Status.kind).UNCLASSIFIED
			else .PARSED;
		if !unpublished {
			for snapshot.recoveries {
				if !it.discarded && it.owner == .NODE && reaches(it.owner_node_id, node, entry.syntax_kind == .COMPOUND_BINDING, owners, owner_fields) {
					expected_status = .RECOVERED;
				}
			}

			for snapshot.recoveries {
				ambiguous := (expected_status == .PARSED && !it.discarded && it.owner == .NODE
					&& it.token_span.first >= it.cursor && nodes[node].token_span.first == it.cursor
					&& node != it.owner_node_id && reaches(node, it.owner_node_id, false, owners, owner_fields)
				);
				if ambiguous {
					expected_status = .UNCLASSIFIED;
				}
			}
		}

		if entry.recovery_status.kind != expected_status {
			return false, tprint("entry % recovery status % differs from %", entry_index, entry.recovery_status.kind, expected_status);
		}


		export := entry.program_export_syntax;
		if export {
			marker := export.marker_origin.span;
			marker_text := slice(source, marker.start, marker.end - marker.start);
			if !begins_with(marker_text, "#") || !ends_with(marker_text, "program_export") {
				return false, tprint("entry % export marker spans '%'", entry_index, marker_text);
			}


			if export.name_argument && source[export.name_argument.origin.span.start] != #char "\"" {
				return false, tprint("entry % export name is not a string token", entry_index);
			}


			properties := ifx entry.syntax_kind == .COMPOUND_BINDING
				then get_field(nodes[node].fields, "declaration_properties").signed
				else node;
			if !has_flag(get_field(nodes[properties].fields, "flags"), "PROGRAM_EXPORT") {
				return false, tprint("entry % has an export occurrence without the flag", entry_index);
			}
		}
	}


	binding_region := NewArray(entries.count, s64,, temp);
	for * binding_region {
		it.* = -1;
	}

	for region, region_index: index.shared_regions {
		compound := region.compound_node_id.(s64);
		if region.parent_container != expected_container(compound, nodes, owners, owner_fields, entry_of_node, region_of_compound) {
			return false, tprint("region % parent container", region_index);
		}


		fields := nodes[compound].fields;
		declares := get_field(fields, "operator_type").tag == Service.Token_Tag.{kind = .BYTE_CHAR, byte = 0};
		comma := get_field(fields, "comma_separated_assignment").signed;
		declared := 0;
		for get_field(nodes[comma].fields, "arguments").elements {
			argument := snapshot.helpers[it.signed].fields;
			modifier := get_field(argument, "modifier").name;
			target := get_field(argument, "node").signed;
			if (modifier == "DECLARE" || (modifier == "NONE" && declares)) && nodes[target].kind == "IDENT" {
				declared += 1;
			}
		}

		if region.binding_entries.count != declared {
			return false, tprint("region % has % bindings, expected %", region_index, region.binding_entries.count, declared);
		}


		previous: s64 = -1;
		for region.binding_entries {
			binding := it.(s64);
			if binding <= previous || binding >= entries.count || binding_region[binding] != -1 {
				return false, tprint("region % binding % is out of order or repeated", region_index, binding);
			}


			entry := entries[binding];
			if entry.syntax_kind != .COMPOUND_BINDING || entry.declaration_node_id != region.compound_node_id || entry.container != region.parent_container {
				return false, tprint("region % binding % does not belong to it", region_index, binding);
			}


			binding_region[binding] = region_index;
			previous = binding;
		}
	}


	for entries {
		if it.syntax_kind == .COMPOUND_BINDING && binding_region[it_index] == -1 {
			return false, tprint("binding entry % has no region", it_index);
		}
	}


	coverage := index.coverage;
	if (coverage.kind == .COMPLETE_SYNTAX_TRAVERSAL) != !coverage.reasons.count {
		return false, "coverage kind disagrees with its reasons";
	}


	for coverage.reasons {
		if !it.impacts || (it.subject.kind == .NODE && it.subject.local_node_id >= xx nodes.count) || !Service.is_valid_utf8(xx it.detail_utf8) {
			return false, tprint("reason % is malformed", it_index);
		}
	}


	return true, "";
}

project_source_index :: (source: string) -> *Service.Owned_Syntax, *Service.Syntax_Snapshot, *Service.Declaration_Index {
	owned := Service.own_parse(source, "index.jai");
	fault, snapshot := Service.project_snapshot(owned);
	assert(fault.failure == .NONE, "Snapshot of '%' failed: %.", source, fault.failure);
	index_fault, index := Service.project_declaration_index(snapshot);
	assert(index_fault.failure == .NONE, "Index of '%' failed: % at %[%].", source, index_fault.failure, index_fault.record, index_fault.index);
	valid, problem := declaration_index_invariants(index, snapshot);
	assert(valid, "Index invariant for '%': %", source, problem);
	tally_routes(snapshot.node_projection);
	return owned, snapshot, index;
}

release_source_index :: (owned: *Service.Owned_Syntax, snapshot: *Service.Syntax_Snapshot, index: *Service.Declaration_Index) {
	if index {
		Service.release_declaration_index(index);
	}

	Service.release_snapshot(snapshot);
	Service.release_owned_syntax(owned);
}

// One `kind name container scope` group per entry: `D`/`B`/`M` kinds, `R`/`D<entry>`/`S<region>` containers, `-`/`E`/`M`/`F`/`?` directives.
index_summary :: (index: *Service.Declaration_Index) -> string {
	KINDS :: string.["D", "B", "M"];
	CONTAINERS :: string.["R", "D", "S"];
	SCOPES :: string.["-", "E", "M", "F", "?"];
	builder: String_Builder;
	for index.entries {
		if it_index {
			append(*builder, "; ");
		}

		name := ifx it.name.kind == .SPELLED
			then it.name.spelling_bytes.(string)
			else ifx it.name.kind == .ANONYMOUS
				then "#anon"
				else "#unmapped";
		container := ifx it.container.kind == .ROOT
			then "R"
			else tprint("%1%2", CONTAINERS[it.container.kind.(s64)], it.container.local_id);
		print(
			*builder,
			"% % % %",
			KINDS[it.syntax_kind.(s64)],
			name,
			container,
			SCOPES[it.visibility_syntax.scope_directive.(s64)]
		);
	}

	return builder_to_string(*builder,, temp);
}

region_summary :: (index: *Service.Declaration_Index) -> string {
	builder: String_Builder;
	for index.shared_regions {
		parent := ifx it.parent_container.kind == .ROOT
			then "R"
			else tprint("%1%2", ifx it.parent_container.kind == .DECLARATION then "D" else "S", it.parent_container.local_id);
		print(*builder, "%1%2%3 ", it.local_region_id, it.binding_entries, parent);
	}

	return builder_to_string(*builder,, temp);
}

// Authored expectations for containers, regions, names, enum members, program exports, recovery and same-list scope provenance.
test_declaration_index_vectors :: () {
	check :: (source: string, expected: string, expected_regions := "") {
		owned, snapshot, index := project_source_index(source);
		summary := index_summary(index);
		assert(summary == expected, "Index of '%':\n  got      %\n  expected %", source, summary, expected);
		regions := region_summary(index);
		assert(regions == expected_regions, "Regions of '%': got '%', expected '%'.", source, regions, expected_regions);
		assert(index.coverage.kind == .COMPLETE_SYNTAX_TRAVERSAL, "'%' should be complete.", source);
		release_source_index(owned, snapshot, index);
	}

	NESTED :: #string END
#scope_file
A :: 1;
Outer :: struct {
	x: int;
	#scope_export
	y := 2;
}
#scope_export
f :: (p: int, $T: Type) -> (r: int, float) {
	inner := 3;
	return 0, 0;
}
END
	check(NESTED, "D A R F; D Outer R F; D x D1 -; D y D1 E; D f R E; D p D4 E; D T D4 E; D r D4 E; D #anon D4 E; D inner D4 -");

	// Bindings precede their shared payload; targets are uses unless declared, and a nested compound's region keeps the outer one as parent.
	check(
		"a, b := 1, 2; c, d = 3, 4; e:, g = h(); m, n := () -> int { k := 1; return k; }, 2; o, w := () { i, j := 1, 2; }, 0;",
		"B a R -; B b R -; B e R -; B m R -; B n R -; D #anon S3 -; D k S3 -; B o R -; B w R -; B i S4 -; B j S4 -",
		"0[0, 1]R 1[]R 2[2]R 3[3, 4]R 4[7, 8]R 5[9, 10]S4 "
	);

	check(
		"`bt :: 1; operator [ ] = :: (a: *T, i: int, v: int) {} operator == :: (a: T, b: T) -> bool { return true; } operator *[] :: (a: *T, i: int) -> *int { return null; }",
		"D `bt R -; D [ ] = R -; D a D1 -; D i D1 -; D v D1 -; D == R -; D a D5 -; D b D5 -; D #anon D5 -; D *[] R -; D a D9 -; D i D9 -; D #anon D9 -"
	);

	// The identifier in the static-if condition is a use, not a member.
	check("E :: enum { A; B :: 5; #if A { C; } else { D; } }", "D E R -; M A D0 -; D B D0 -; M C D0 -; M D D0 -");
	check("q :: (x, y) => x + y; s :: z => z;", "D q R -; D x D0 -; D y D0 -; D s R -; D z D3 -");
	check("u :: (using v: Vector3) { using w: Vector3; }", "D u R -; D v D0 -; D w D0 -");
	check("#no_reset nr: int; $$ab :: 1; $c: int;", "D nr R -; D ab R -; D c R -");

	{
		owned, snapshot, index := project_source_index("`bt :: 1; operator [ ] = :: (a: *T, i: int, v: int) {}");
		assert(index.entries[0].name.producer_name_bytes.(string) == "bt" && index.entries[0].name.form == .IDENTIFIER);
		assert(index.entries[1].name.producer_name_bytes.(string) == "[]=" && index.entries[1].name.form == .OPERATOR);
		assert(!index.entries[1].name.recovery_origins.count);
		release_source_index(owned, snapshot, index);
	}

	{
		owned, snapshot, index := project_source_index("long\\  _name :: 1;");
		name := index.entries[0].name;
		assert(name.spelling_bytes.(string) == "long\\  _name" && name.producer_name_bytes.(string) == "long_name", "Identifier continuations stay in the spelling only.");
		release_source_index(owned, snapshot, index);
	}

	{
		// Single-character operator names once pointed into a stack copy of their token.
		SOURCE :: "operator + :: (a: T, b: T) -> T { return a; } operator ! :: (a: T) -> T { return a; } operator ^ :: (a: T, b: T) -> T { return a; }";
		owned, snapshot, index := project_source_index(SOURCE);
		assert(index_summary(index) == "D + R -; D a D0 -; D b D0 -; D #anon D0 -; D ! R -; D a D4 -; D #anon D4 -; D ^ R -; D a D7 -; D b D7 -; D #anon D7 -");
		for i: s64.[0, 4, 7] {
			name := index.entries[i].name;
			assert(name.form == .OPERATOR && name.producer_name_bytes.(string) == name.spelling_bytes.(string));
		}

		release_source_index(owned, snapshot, index);
	}

	{
		SOURCE :: "#if A {\n\t#scope_file\n\tp :: 1;\n} else {\n\t#scope_export\n\tq :: 2;\n}\nr :: 3;";
		owned, snapshot, index := project_source_index(SOURCE);
		assert(index_summary(index) == "D p R F; D q R E; D r R -");
		projection := snapshot.node_projection;
		then_block := node_id(find_node(projection, "BLOCK", 1));
		else_block := node_id(find_node(projection, "BLOCK", 2));
		basis :: (index: *Service.Declaration_Index, entry: s64) -> Service.Scope_Basis {
			return index.entries[entry].visibility_syntax.scope_basis;
		}

		assert(basis(index, 0).statement_list_node_id == then_block && basis(index, 0).preceding_directive_node_id == node_id(find_node(projection, "DIRECTIVE_SCOPE", 0)));
		assert(basis(index, 1).statement_list_node_id == else_block && basis(index, 1).preceding_directive_node_id == node_id(find_node(projection, "DIRECTIVE_SCOPE", 1)));
		assert(basis(index, 2).statement_list_node_id == 0 && basis(index, 2).preceding_directive_node_id == -1, "A parent declaration after the branches has no direct directive.");
		release_source_index(owned, snapshot, index);
	}

	{
		SOURCE :: "#program_export \"name\" f :: () {} #program_export g :: () {} #program_export \"\" h :: () {} #program_export x, y: int; plain :: 1;";
		owned, snapshot, index := project_source_index(SOURCE);
		assert(index_summary(index) == "D f R -; D g R -; D h R -; B x R -; B y R -; D plain R -");
		text :: (span: Service.Byte_Span) -> string {
			return slice(SOURCE, span.start, span.end - span.start);
		}

		named := index.entries[0].program_export_syntax;
		assert(named && text(named.marker_origin.span) == "#program_export" && named.name_argument);
		assert(named.name_argument.value_bytes.(string) == "name" && text(named.name_argument.origin.span) == "\"name\"");
		assert(index.entries[1].program_export_syntax && !index.entries[1].program_export_syntax.name_argument, "A bare marker has no name argument.");
		empty := index.entries[2].program_export_syntax;
		assert(empty && empty.name_argument && !empty.name_argument.value_bytes.count, "An explicit empty name is present.");
		assert(index.entries[3].program_export_syntax && index.entries[3].program_export_syntax == index.entries[4].program_export_syntax, "Compound bindings share one occurrence.");
		assert(!index.entries[5].program_export_syntax);
		release_source_index(owned, snapshot, index);
	}

	// One letter per entry: `P`arsed, `R`ecovered, `U`nclassified.
	statuses :: (source: string, expected: string) {
		owned, snapshot, index := project_source_index(source);
		builder: String_Builder;
		for index.entries {
			append(*builder, "PRU"[it.recovery_status.kind.(s64)]);
		}

		got := builder_to_string(*builder,, temp);
		assert(got == expected, "Recovery statuses of '%': got %, expected %.", source, got, expected);
		assert(index.coverage.kind == .COMPLETE_SYNTAX_TRAVERSAL, "Attributed recovery keeps '%' complete.", source);
		release_source_index(owned, snapshot, index);
	}

	statuses("a :: 1; b :: ;", "PR");
	// The discriminating case: a recovered body declaration recovers its procedure, not its siblings.
	statuses("f :: () {\n\tinner :: ;\n\tother :: 1;\n}\ng :: 2;", "RRPP");
	statuses("x :: 1 y :: 2;", "RP");
	statuses("a, b := ; c := 1;", "RRP");
	statuses("p, q := (1 + ), 2;", "RR");
	// A broken target is target syntax: it reaches the outer context, not the bindings.
	statuses("f :: () { a, (1 + ) := 1; }", "RP");
	// A parameter that parses as a compound is discarded; its events return to the header instead of an unpublished owner.
	statuses("f :: (a: int, b, c := 1 + ) {}", "RP");
	// Other discarded subtrees: a non-call after `inline`, a cast without an operand, a non-call after `#bake` and `#procedure_of_call`, and an assembly value that does not fill its operand.
	statuses("g :: inline (dest: *", "R");
	statuses("x := cast(int) ; y := 1;", "RP");
	statuses("x := #bake (a + ); y := 1;", "RP");
	statuses("x := #procedure_of_call (a + ); y := 1;", "RP");
	statuses("f :: () { #asm { add x, (a b); } } g :: 1;", "RP");

	{
		owned, snapshot, index := project_source_index("a :: 1;");
		assert(index.entries[0].recovery_status.kind == .PARSED && index.entries[0].declaration_origin.kind == .SOURCE);
		assert(index.entries[0].declaration_origin.span.start == 0 && index.entries[0].declaration_origin.span.end == 6);
		release_source_index(owned, snapshot, index);
	}

	print("Declaration index vectors PASS\n");
}

// Recorded evidence that disagrees with the token stream fails conversion; missing correlations degrade to explicit partial records.
test_declaration_index_controls :: () {
	project :: (source: string) -> *Service.Owned_Syntax, *Service.Syntax_Snapshot {
		owned := Service.own_parse(source, "control.jai");
		fault, snapshot := Service.project_snapshot(owned);
		assert(fault.failure == .NONE);
		return owned, snapshot;
	}

	set_signed :: (record: *Service.Node_Record, name: string, value: s64) {
		for * record.fields {
			if it.path[0].name == name {
				it.value.signed = value;
			}
		}
	}

	{
		owned, snapshot := project("a:, b = f();");
		comma := find_node(snapshot.node_projection, "COMMA_SEPARATED_ARGUMENTS");
		first := snapshot.helpers[get_field(comma.fields, "arguments").elements[0].signed];
		modifier_token := get_field(first.fields, "modifier_token").signed;
		snapshot.tokens[modifier_token].tag = .{kind = .BYTE_CHAR, byte = #char "="};
		fault, index := Service.project_declaration_index(snapshot);
		assert(fault.failure == .CONFLICTING_EVIDENCE && !index, "A modifier token that does not match its modifier fails conversion.");
		release_source_index(owned, snapshot, null);
	}

	{
		owned, snapshot := project("a, b := 1, 2;");
		compound := find_node(snapshot.node_projection, "COMPOUND_DECLARATION");
		set_signed(compound, "operator_token", get_field(compound.fields, "operator_token").signed + 1);
		fault, index := Service.project_declaration_index(snapshot);
		assert(fault.failure == .CONFLICTING_EVIDENCE && !index, "A shared operator token that is not `:` fails conversion.");
		release_source_index(owned, snapshot, null);
	}

	{
		owned, snapshot := project("a :: 1; b :: 2;");
		statements := get_field(snapshot.nodes[0].fields, "statements").elements;
		statements[1].signed = statements[0].signed;
		fault, index := Service.project_declaration_index(snapshot);
		assert(fault.failure == .INVALID_REFERENCE && !index, "A node with two owners fails conversion.");
		release_source_index(owned, snapshot, null);
	}

	{
		owned, snapshot := project("abc :: 1;");
		declaration := find_node(snapshot.node_projection, "DECLARATION");
		for * declaration.fields {
			if it.path[0].name == "entry" {
				it.value.bytes = xx "zz";
			}
		}

		fault, index := Service.project_declaration_index(snapshot);
		assert(fault.failure == .NONE);
		name := index.entries[0].name;
		assert(name.kind == .UNMAPPED && name.producer_name_bytes.(string) == "zz" && name.reason.code == .UNMAPPED_NAME, "A producer name that its token does not spell is unmapped, not guessed.");
		assert(index.coverage.kind == .PARTIAL_SYNTAX_TRAVERSAL && index.coverage.reasons[0].subject.local_node_id == xx node_id(declaration));
		valid, problem := declaration_index_invariants(index, snapshot);
		assert(valid, problem);
		release_source_index(owned, snapshot, index);
	}

	{
		owned, snapshot := project("#program_export f :: () {}");
		declaration := find_node(snapshot.node_projection, "DECLARATION");
		for * declaration.fields {
			if it.path[0].name == "flags" {
				it.value.names.count = 0;
			}
		}

		fault, index := Service.project_declaration_index(snapshot);
		assert(fault.failure == .NONE && !index.entries[0].program_export_syntax);
		assert(
			index.coverage.reasons.count == 1 && index.coverage.reasons[0].code == .UNCORRELATED_METADATA && index.coverage.reasons[0].impacts == .METADATA,
			"A marker without its flag is uncorrelated metadata."
		);
		release_source_index(owned, snapshot, index);
	}

	{
		owned, snapshot := project("E :: enum { A; }");
		member := find_node(snapshot.node_projection, "IDENT");
		snapshot.tokens[member.token_span.one_past_last].tag = .{kind = .BYTE_CHAR, byte = #char ","};
		fault, index := Service.project_declaration_index(snapshot);
		assert(fault.failure == .NONE && index.entries.count == 1, "Without `IDENT ;` evidence no member entry is guessed.");
		reason := index.coverage.reasons[0];
		assert(reason.code == .UNCLASSIFIED_ROUTE && reason.impacts == (.DECLARATION_SET | .NAMES) && reason.subject.local_node_id == xx node_id(member));
		release_source_index(owned, snapshot, index);
	}

	{
		owned, snapshot := project("a :: 1; b :: ;");
		assert(snapshot.recoveries[0].owner == .NODE);
		snapshot.recoveries[0].owner = .UNPUBLISHED;
		fault, index := Service.project_declaration_index(snapshot);
		assert(fault.failure == .NONE && index.coverage.reasons.count == 1 && index.coverage.reasons[0].subject.kind == .DOCUMENT);
		for index.entries {
			assert(it.recovery_status.kind == .UNCLASSIFIED, "An event without a published owner leaves every entry unclassified.");
		}

		release_source_index(owned, snapshot, index);
	}

	{
		// Moved zero-width onto `b`'s first token under its enclosing block, the event may belong to either builder.
		owned, snapshot := project("f :: () { a :: 1; b :: 2; } g :: ;");
		target := find_node(snapshot.node_projection, "DECLARATION", 2);
		event := *snapshot.recoveries[0];
		event.token_span = .{target.token_span.first, target.token_span.first};
		event.cursor = target.token_span.first;
		event.owner_node_id = node_id(find_node(snapshot.node_projection, "BLOCK", 1));
		fault, index := Service.project_declaration_index(snapshot);
		assert(fault.failure == .NONE);
		got: [4] type_of(Service.Recovery_Status.kind);
		for index.entries {
			got[it_index] = it.recovery_status.kind;
		}

		assert(got[0] == .RECOVERED && got[1] == .PARSED && got[2] == .UNCLASSIFIED && got[3] == .PARSED, "Statuses %.", got);
		assert(index.coverage.kind == .PARTIAL_SYNTAX_TRAVERSAL && index.coverage.reasons[0].subject.local_node_id == xx node_id(target));
		valid, problem := declaration_index_invariants(index, snapshot);
		assert(valid, problem);
		release_source_index(owned, snapshot, index);
	}

	// The invariant checker itself must reject forged containers, scope tags and region memberships.
	{
		owned, snapshot, index := project_source_index("Outer :: struct { #scope_file x: int; } a, b := 1, 2;");
		forged :: (index: *Service.Declaration_Index, snapshot: *Service.Syntax_Snapshot, what: string) {
			valid := declaration_index_invariants(index, snapshot);
			assert(!valid, "The invariant checker accepted a forged %.", what);
		}

		entry := *index.entries[1];
		saved_container := entry.container;
		entry.container = .{};
		forged(index, snapshot, "container");
		entry.container = saved_container;

		entry.visibility_syntax.scope_directive = .SCOPE_EXPORT;
		forged(index, snapshot, "scope tag");
		entry.visibility_syntax.scope_directive = .SCOPE_FILE;

		bindings := *index.shared_regions[0].binding_entries;
		bindings.count -= 1;
		forged(index, snapshot, "region membership");
		bindings.count += 1;

		valid, problem := declaration_index_invariants(index, snapshot);
		assert(valid, problem);
		release_source_index(owned, snapshot, index);
	}

	print("Declaration index controls PASS\n");
}

// The descriptor's exact feature order and closed method tags, decoded through the bounded key parser.
test_syntax_adapter_descriptor :: () {
	FEATURES :: string.["authored_edges", "builder_function_routes", "compound_routes", "name_origins", "metadata_origins"];
	METHODS :: string.["UNAVAILABLE", "CAPTURED", "RECONSTRUCTED"];
	descriptor := Service.syntax_adapter_descriptor();
	ok, key := Service.parse_key(descriptor, 16);
	assert(ok && key.tag.(string) == "syntax-adapter" && key.fields.count == FEATURES.count + 2);
	assert(key.fields[0].(string) == "jai-cache-syntax-adapter/1" && key.fields[1].(string) == Service.SYNTAX_REGISTRY_BINDING);
	for FEATURES {
		feature_ok, feature := Service.parse_key(key.fields[it_index + 2], 2);
		assert(feature_ok && feature.tag.(string) == it && feature.fields.count == 2, "Feature % is out of order or malformed.", it);
		method := feature.fields[0].(string);
		schema := feature.fields[1].(string);
		assert(array_find(METHODS, method) && (method == "UNAVAILABLE") == !schema.count, "Feature % has method % and schema '%'.", it, method, schema);
	}

	assert(Service.bytes_equal(descriptor, Service.syntax_adapter_descriptor()), "The descriptor is deterministic.");
	print("Syntax adapter descriptor PASS\n");
}

#import "Hash_Table";

// Route coverage across every projection checked by this run: node kinds, helper layouts, producer enum names, source flags and populated owning fields.
// Keys are `kind:NAME`, `helper:LAYOUT`, `enum:DOMAIN=NAME`, `flag:DOMAIN.NAME` and `child:KIND.FIELD`.
route_counts: Table(string, s64);
// Tallies outlive the per-parse pools that are current when they are recorded.
route_allocator: Allocator;

tally :: (key: string) {
	count := table_find_pointer(*route_counts, key);
	if count {
		count.* += 1;
	} else {
		table_add(*route_counts, copy_string(key,, route_allocator), 1);
	}
}

tally_routes :: (projection: *Service.Node_Projection) {
	tally_value :: (owner: string, path: [] Service.Path_Step, value: Service.Field_Value) {
		if value.kind == {
			case .ENUM;
				tally(tprint("enum:%=%", value.domain, value.name));

			case .FLAGS;
				for value.names {
					tally(tprint("flag:%.%", value.domain, it));
				}

			case .NODE;
				if value.signed >= 0 {
					tally(tprint("child:%.%", owner, path[0].name));
				}

			case .LIST;
				for value.elements {
					tally_value(owner, path, it);
				}
		}
	}

	for projection.nodes {
		tally(tprint("kind:%", it.kind));
		for field: it.fields {
			tally_value(it.kind, field.path, field.value);
		}
	}

	for projection.helpers {
		tally(tprint("helper:%", it.layout));
		for field: it.fields {
			tally_value(it.layout, field.path, field.value);
		}
	}

	reset_temporary_storage();
}

Enum_Domain :: struct {
	domain: string;
	type: Type;
}

ENUM_DOMAINS :: Enum_Domain.[
	.{"Code_Comma_Separated_Argument.modifier",		type_of(Parser.Parser_Comma_Separated_Argument.modifier)},
	.{"Parser_Asm_Statement.kind",					Parser.Parser_Asm_Statement_Kind},
	.{"Parser_Asm_Mnemonic_Size.kind",				Parser.Parser_Asm_Mnemonic_Size_Kind},
	.{"Parser_Asm_Operand.kind",					Parser.Parser_Asm_Operand_Kind},
	.{"Parser_Asm_Operand_Modifier.kind",			Parser.Parser_Asm_Operand_Modifier_Kind},
	.{"Code_Expression_Query.query_kind",			type_of(Parser.Parser_Expression_Query.query_kind)},
	.{"Code_Type_Query.query_kind",					type_of(Parser.Parser_Type_Query.query_kind)},
	.{"Code_Block.block_type",						type_of(Parser.Parser_Block.block_type)},
	.{"Code_Loop_Control.control_type",				type_of(Parser.Parser_Loop_Control.control_type)},
	.{"Code_Using.filter_type",						type_of(Parser.Parser_Using.filter_type)},
	.{"Code_Directive_Import.import_type",			type_of(Parser.Parser_Directive_Import.import_type)},
	.{"Code_Directive_Bake.bake_type",				type_of(Parser.Parser_Directive_Bake.bake_type)},
	.{"Code_Directive_Scope.scope_type",			type_of(Parser.Parser_Directive_Scope.scope_type)},
	.{"Code_Literal.value_type",					type_of(Parser.Parser_Literal.value_type)}
];

HELPER_LAYOUTS :: string.[
	"Parser_Argument",
	"Parser_Context_Modification",
	"Parser_Comma_Separated_Argument",
	"Parser_Struct_Literal_Info",
	"Parser_Array_Literal_Info",
	"Parser_Asm_Feature",
	"Parser_Asm_Statement",
	"Parser_Asm_Instruction",
	"Parser_Asm_Mnemonic_Size",
	"Parser_Asm_Operand",
	"Parser_Asm_Operand_Modifier",
	"Parser_Asm_Value",
	"Parser_Asm_Register_Declaration",
	"Parser_Asm_Register_Pinning",
	"Parser_Asm_Memory_Operand"
];

// Prints every registered route this run never observed, so each can be given a vector or a recorded disposition.
report_route_coverage :: () {
	missing: [..] string;
	kinds := type_info(type_of(Parser.Parser_Node.kind)).(*Type_Info_Enum);
	for kinds.names {
		if !table_find_pointer(*route_counts, tprint("kind:%", it)) {
			array_add(*missing, tprint("kind:%", it));
		}
	}

	for HELPER_LAYOUTS {
		if !table_find_pointer(*route_counts, tprint("helper:%", it)) {
			array_add(*missing, tprint("helper:%", it));
		}
	}

	for domain: ENUM_DOMAINS {
		info := domain.type.(*Type_Info_Enum);
		for info.names {
			key := tprint("enum:%=%", domain.domain, it);
			if !table_find_pointer(*route_counts, key) {
				array_add(*missing, key);
			}
		}
	}

	print("Route coverage: % distinct routes observed; % registered enum names or kinds never observed:\n", route_counts.count, missing.count);
	for missing {
		print("  %\n", it);
	}

	// Compiler-only kinds and arms: no parser builder function produces them, and projection rejects unregistered kinds.
	COMPILER_ONLY :: string.[
		"kind:UNINITIALIZED",
		"kind:TYPE_DEFINITION",
		"kind:EXTRACT",
		"kind:MAKE_VARARGS",
		"kind:DIRECTIVE_PLACE",
		"kind:DIRECTIVE_COMPILE_TIME",
		"kind:RESOLVED_OVERLOAD",
		"enum:Code_Block.block_type=UNINITIALIZED",
		"enum:Code_Block.block_type=ARGUMENTS",
		"enum:Code_Block.block_type=RETURNS",
		"enum:Code_Block.block_type=CONSTANTS",
		"enum:Code_Literal.value_type=TYPE_INFO"
	];
	for missing {
		assert(array_find(COMPILER_ONLY, it), "Registered route % has neither a vector nor a recorded disposition.", it);
	}

	// Flags no parser builder function sets: the first group is in the projection's closed source-flag domains, the rest are compiler-only.
	UNPRODUCED_FLAGS :: string.[
		"NODE.EXPRESSION_IS_SPREAD",
		"NODE.NO_ARRAY_BOUNDS_CHECK",
		"NODE.STATEMENT_IS_DEFERRED",
		"BINARY.SHIFT_MARKED_AS_LOGICAL",
		"BINARY.SHIFT_MARKED_AS_SMALL",
		"CALL.NO_DEBUG",
		"CALL.IS_MODULE_PARAMETERS",
		"BLOCK.NO_ARRAY_BOUNDS_CHECK",
		"BLOCK.NO_ARITHMETIC_OVERFLOW_CHECK",
		"DECLARATION.IS_MARKED_AS_DISCARD",
		"LIBRARY.DYNAMIC_LIBRARY_UNAVAILABLE",
		"LIBRARY.LINK_ALWAYS",
		"CAST.HAS_FUNCTION_SYNTAX",

		"NODE.CREATED_BY_DESUGARING",
		"NODE.EXPRESSION_IS_DEPRECATED",
		"IDENT.RESOLVES_ONLY_SHALLOWLY",
		"IDENT.GENERATED_BY_OPERATOR_OVERLOAD",
		"IDENT.DO_NOT_RESOLVE_DUE_TO_PARSER",
		"IDENT.CAN_RESOLVE_TO_REG",
		"DECLARATION.IS_ITERATOR",
		"DECLARATION.COMES_FROM_ASM",
		"DECLARATION.IS_IMPORTED",
		"DECLARATION.IS_OVERLAY",
		"DECLARATION.SCOPE_FILE",
		"DECLARATION.IS_GLOBAL",
		"STRUCT.UNION_IS_TAGGED",
		"PROCEDURE.COMPILER_GENERATED",
		"PROCEDURE.CPP_METHOD",
		"PROCEDURE.HAS_IMPLICIT_RETURN_VALUE",
		"PROCEDURE.CPP_RETURN_TYPE_IS_NON_POD",
		"PROCEDURE.INITIALIZER",
		"CAST.IS_IMPLICIT",
		"CAST.IS_POINTER_DEREFERENCE",
		"CAST.AS",
		"CAST.ISA"
	];
	for domain: FLAG_DOMAINS {
		info := domain.type.(*Type_Info_Enum);
		for info.names {
			name := tprint("%.%", domain.domain, it);
			if !table_find_pointer(*route_counts, tprint("flag:%", name)) {
				assert(array_find(UNPRODUCED_FLAGS, name), "Source flag % has neither a vector nor a recorded disposition.", name);
			}
		}
	}
}

FLAG_DOMAINS :: Enum_Domain.[
	.{"NODE",				type_of(Parser.Parser_Node.node_flags)},
	.{"IDENT",				type_of(Parser.Parser_Ident.flags)},
	.{"BINARY",				type_of(Parser.Parser_Binary_Operator.flags)},
	.{"CALL",				type_of(Parser.Parser_Procedure_Call.flags)},
	.{"BLOCK",				type_of(Parser.Parser_Block.block_flags)},
	.{"DECLARATION",		type_of(Parser.Parser_Declaration.flags)},
	.{"IF",					type_of(Parser.Parser_If.if_flags)},
	.{"FOR",				type_of(Parser.Parser_For.for_flags)},
	.{"RETURN",				type_of(Parser.Parser_Return.return_flags)},
	.{"PUSH_CONTEXT",		type_of(Parser.Parser_Push_Context.push_context_flags)},
	.{"STRUCT",				type_of(Parser.Parser_Struct.textual_flags)},
	.{"IMPORT",				type_of(Parser.Parser_Directive_Import.flags)},
	.{"LIBRARY",			type_of(Parser.Parser_Directive_Library.library_flags)},
	.{"RUN",				type_of(Parser.Parser_Directive_Run.flags)},
	.{"PROCEDURE",			type_of(Parser.Parser_Procedure_Header.procedure_flags)},
	.{"CAST",				type_of(Parser.Parser_Cast.cast_flags)},
	.{"LITERAL",			type_of(Parser.Parser_Literal.value_flags)},
	.{"TYPE_INSTANTIATION",	type_of(Parser.Parser_Type_Instantiation.inst_flags)},
	.{"ARRAY_LITERAL",		type_of(Parser.Parser_Array_Literal_Info.array_literal_flags)}
];
