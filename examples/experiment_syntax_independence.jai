#import "Basic";
#import "Compiler";
#import "File";
#import "File_Utilities";
#import "Pool";
#import "String";

#import "Jai_Parser"(ENABLE_TRIVIA = true, INTERN_IDENTIFIERS = true);

OUTPUT_DIRECTORY :: ".build/syntax_independence";
COMPILER_VERSION :: #run compiler_get_version_info(null);

syntax_checks: s64;
context_creations: s64;
context_releases: s64;
text_mutations: s64;

SOURCE :: #string JAI
number :: 7;
reference :: external;
text :: "first\nsecond\t\"quoted\"";
JAI

Owned_Token :: struct {
	type: Token_Type;
	start: s64;
	end: s64;
	text: string;
	leading_start: s64;
	l0, c0, l1, c1: s32;
}

Owned_Declaration :: struct {
	name: string;
	span: Token_Span;
	start: s64;
	end: s64;
	kind: enum u8 { OPAQUE; INTEGER; TEXT; REFERENCE; }
	text: string;
	number: u64;
	flags: u32;
	expression_kind: s64 = -1;
	expression_span: Token_Span;
}

Owned_Related :: struct {
	span: Token_Span;
	message: string;
}

Owned_Diagnostic :: struct {
	kind, severity: s64;
	span: Token_Span;
	message: string;
	lexer_line, lexer_column: s32;
	expected, actual: Token_Type;
	action: Recovery_Action;
	related: []Owned_Related;
}
Owned_Synthetic :: struct {
	type: Token_Type;
	index: Token_Index;
	text: string;
	l0, c0, l1, c1: s32;
}

Owned_Syntax :: struct {
	source: string;
	filename: string;
	tokens: []Owned_Token;
	declarations: []Owned_Declaration;
	status: Parse_Status;
	diagnostics: []Owned_Diagnostic;
	recovery: []Recovery_Record;
	restarts: []Restart_Point;
	synthetic: []Owned_Synthetic;
}

Fixture :: struct { name: string; source: string; status: Parse_Status; }
FIXTURES :: Fixture.[
	.{"scalar_and_decoded",	SOURCE,																		.COMPLETE},
	.{
		name = "here_string",
		status = .COMPLETE,
		source = #string JAI
text :: #string TEXT
first
second
TEXT
reference :: external;
JAI
	},
	.{"missing_semicolon",	"first :: 1 second :: external;",											.RECOVERED},
	.{"missing_paren",		"number :: (7;\nreference :: external;",									.RECOVERED},
	.{"body_recovery",		"main :: () { bad: ; next := 2; }\nafter :: 3;",							.RECOVERED},
	.{"incomplete",			"broken :: () { next :=",													.INCOMPLETE},
	.{"empty",				"",																			.COMPLETE},
	.{"empty_and_wide",		"empty :: \"\";\nwide :: 18446744073709551615;\nreference :: external;",	.COMPLETE},
];


Semantic_Symbol :: struct {
	name: string;
	value: u64;
}

Semantic_Binding :: struct {
	target: *Semantic_Symbol;
	text: string;
}

Semantic_Context :: struct {
	syntax: *Owned_Syntax;
	symbol: *Semantic_Symbol;
	bindings: []Semantic_Binding;
}

project_syntax :: (parsed: *Parsed_Source, storage: *Pool) -> Owned_Syntax {
	previous := context.allocator;
	context.allocator = .{proc = pool_allocator_proc, data = storage};
	defer context.allocator = previous;

	result: Owned_Syntax;
	result.source = copy_string(parsed.source);
	result.filename = copy_string(parsed.fully_pathed_filename);
	result.status = parsed.status;
	result.tokens = NewArray(parsed.tokens.count, Owned_Token);

	for token: parsed.tokens {
		result.tokens[it_index] = .{
			type = token.type,
			start = token.byte_start,
			end = token.byte_end,
			text = slice(result.source, token.byte_start, token.byte_end - token.byte_start),
			leading_start = token.preceding_trivia_byte_start,
			l0 = token.l0, c0 = token.c0,
			l1 = token.l1, c1 = token.c1
		};
	}

	result.diagnostics = NewArray(parsed.diagnostics.count, Owned_Diagnostic);
	for diagnostic: parsed.diagnostics {
		owned := Owned_Diagnostic.{
			kind = diagnostic.kind.(s64),
			severity = diagnostic.severity.(s64),
			span = diagnostic.span,
			message = copy_string(diagnostic.message),
			lexer_line = diagnostic.lexer_line,
			lexer_column = diagnostic.lexer_column,
			expected = diagnostic.expected_token,
			actual = diagnostic.actual_token,
			action = diagnostic.recovery_action,
			related = NewArray(diagnostic.related_information.count, Owned_Related)
		};

		for related, related_index: diagnostic.related_information {
			owned.related[related_index] = .{related.span, copy_string(related.message)};
		}

		result.diagnostics[it_index] = owned;
	}

	result.recovery = NewArray(parsed.recovery_records.count, Recovery_Record);
	for record: parsed.recovery_records {
		result.recovery[it_index] = record;
	}

	result.restarts = NewArray(parsed.restart_points.count, Restart_Point);
	for point: parsed.restart_points {
		result.restarts[it_index] = point;
	}

	result.synthetic = NewArray(parsed.synthetic_tokens.count, Owned_Synthetic);
	for synthetic: parsed.synthetic_tokens {
		result.synthetic[it_index] = .{
			type = synthetic.token.type,
			index = synthetic.insertion_index,
			text = copy_string(synthetic.token.original_text),
			l0 = synthetic.token.l0, c0 = synthetic.token.c0,
			l1 = synthetic.token.l1, c1 = synthetic.token.c1
		};
	}

	statements := parsed.root.(*Parser_Block).statements;
	declarations: [..]Owned_Declaration;
	for statement: statements {
		if statement.kind != .DECLARATION {
			continue;
		}


		declaration := statement.(*Parser_Declaration);
		first := declaration.first_token.(s64);
		last := declaration.one_past_last_token.(s64);
		owned: Owned_Declaration;
		owned.name = copy_string(parsed.tokens[first].original_text);
		owned.span = .{first = xx first, one_past_last = xx last};
		owned.start = parsed.tokens[first].byte_start;
		owned.end = ifx last > first
			then parsed.tokens[last - 1].byte_end
			else owned.start;

		if declaration.expression {
			owned.expression_kind = declaration.expression.kind.(s64);
			owned.expression_span = .{declaration.expression.first_token, declaration.expression.one_past_last_token};
			if declaration.expression.kind == {
				case .IDENT;
					owned.kind = .REFERENCE;
					owned.text = copy_string(declaration.expression.(*Parser_Ident).name);

				case .LITERAL;
					literal := declaration.expression.(*Parser_Literal);
					owned.flags = literal.value_flags.(u32);
					if literal.value_type == {
						case .STRING;
							owned.kind = .TEXT;
							owned.text = copy_string(literal._string);

						case .NUMBER;
							owned.kind = .INTEGER;
							owned.number = literal._u64;
					}
			}
		}

		array_add(*declarations, owned);
	}

	result.declarations = declarations;
	return result;
}

freeze_syntax :: (syntax: *Owned_Syntax) -> string {
	builder: String_Builder;
	print(*builder, "%:%\n%:%\n%\n", syntax.source.count, syntax.source, syntax.filename.count, syntax.filename, syntax.status);

	for token: syntax.tokens {
		print(*builder, "% % % %:%\n", token.type, token.start, token.end, token.text.count, token.text);
		print(*builder, "% % % % %\n", token.leading_start, token.l0, token.c0, token.l1, token.c1);
	}

	for declaration: syntax.declarations {
		print(
			*builder,
			"%:% % % % % % % % %:%\n",
			declaration.name.count,
			declaration.name,
			declaration.span.first,
			declaration.span.one_past_last,
			declaration.start,
			declaration.end,
			declaration.kind,
			declaration.number,
			declaration.flags,
			declaration.text.count,
			declaration.text
		);

		print(*builder, "% % %\n", declaration.expression_kind, declaration.expression_span.first, declaration.expression_span.one_past_last);
	}

	print(*builder, "metadata % % % %\n", syntax.diagnostics.count, syntax.recovery.count, syntax.restarts.count, syntax.synthetic.count);
	for diagnostic: syntax.diagnostics {
		print(*builder, "% % % % %:%\n", diagnostic.kind, diagnostic.severity, diagnostic.span.first, diagnostic.span.one_past_last, diagnostic.message.count, diagnostic.message);
		print(*builder, "% % % % % %\n", diagnostic.lexer_line, diagnostic.lexer_column, diagnostic.expected, diagnostic.actual, diagnostic.action, diagnostic.related.count);
		for related: diagnostic.related {
			print(*builder, "% % %:%\n", related.span.first, related.span.one_past_last, related.message.count, related.message);
		}
	}

	for record: syntax.recovery {
		print(*builder, "% % % % %\n", record.kind, record.span.first, record.span.one_past_last, record.diagnostic_index, record.synthetic_token_index);
	}

	for point: syntax.restarts {
		print(*builder, "% % %\n", point.kind, point.span.first, point.span.one_past_last);
	}

	for synthetic: syntax.synthetic {
		print(*builder, "% % %:% % % % %\n", synthetic.type, synthetic.index, synthetic.text.count, synthetic.text, synthetic.l0, synthetic.c0, synthetic.l1, synthetic.c1);
	}

	return builder_to_string(*builder);
}

assert_unchanged :: (syntax: *Owned_Syntax, expected: string) {
	actual := freeze_syntax(syntax);
	defer free(actual);

	assert(actual == expected, "E6 syntax changed or retained producer storage");
	syntax_checks += 1;
}

check_span :: (syntax: *Owned_Syntax, span: Token_Span) {
	assert(span.first >= xx 0 && span.one_past_last >= span.first);
	assert(span.one_past_last <= xx syntax.tokens.count);
}

check_spans :: (syntax: *Owned_Syntax) {
	for token: syntax.tokens {
		assert(token.leading_start >= 0 && token.leading_start <= token.start);
		assert(token.start <= token.end && token.end <= syntax.source.count);
		assert(token.text == slice(syntax.source, token.start, token.end - token.start));
		assert(token.l0 > 0 && token.c0 > 0 && token.l1 > 0 && token.c1 > 0);
	}

	for declaration: syntax.declarations {
		check_span(syntax, declaration.span);
		assert(declaration.start >= 0 && declaration.end >= declaration.start && declaration.end <= syntax.source.count);
		assert(slice(syntax.source, declaration.start, declaration.name.count) == declaration.name);
		if declaration.expression_kind >= 0 {
			check_span(syntax, declaration.expression_span);
		}
	}

	for diagnostic: syntax.diagnostics {
		check_span(syntax, diagnostic.span);
		for related: diagnostic.related {
			check_span(syntax, related.span);
		}
	}

	for record: syntax.recovery {
		check_span(syntax, record.span);
		assert(record.diagnostic_index >= 0 && record.diagnostic_index < syntax.diagnostics.count);
		assert(record.synthetic_token_index >= -1 && record.synthetic_token_index < syntax.synthetic.count);
	}

	for point: syntax.restarts {
		check_span(syntax, point.span);
	}

	for synthetic: syntax.synthetic {
		assert(synthetic.index >= xx 0 && synthetic.index <= xx syntax.tokens.count);
	}
}

attach_context :: (syntax: *Owned_Syntax, storage: *Pool, value: u64) -> Semantic_Context {
	previous := context.allocator;
	set_allocators(storage, previous);
	storage.overwrite_memory = true;
	context.allocator = .{proc = pool_allocator_proc, data = storage};
	defer context.allocator = previous;

	result: Semantic_Context;
	result.syntax = syntax;
	result.symbol = New(Semantic_Symbol);
	result.symbol.* = .{copy_string("external"), value};
	result.bindings = NewArray(syntax.declarations.count, Semantic_Binding);
	context_creations += 1;

	for declaration: syntax.declarations {
		if declaration.kind == {
			case .REFERENCE;
				if declaration.text == result.symbol.name {
					result.bindings[it_index].target = result.symbol;
				}

			case .TEXT;
				result.bindings[it_index].text = copy_string(declaration.text);
		}
	}

	return result;
}

release_context :: (semantic: *Semantic_Context, storage: *Pool) {
	release(storage);
	semantic.* = .{};
	context_releases += 1;
}

check_context :: (semantic: *Semantic_Context, value: u64) {
	assert(semantic.symbol.value == value);
	for declaration, index: semantic.syntax.declarations {
		if declaration.kind == {
			case .REFERENCE;
				assert(semantic.bindings[index].target == semantic.symbol);
				assert(semantic.bindings[index].target.value == value);

			case .TEXT;
				assert(semantic.bindings[index].text == declaration.text);
		}
	}
}

destroy_producer :: (parsed: *Parsed_Source, storage: *Pool, input: string, filename: string) {
	for *byte: input {
		byte.* = 0xDD;
	}

	for *byte: filename {
		byte.* = 0xDD;
	}

	parsed.node_pool.overwrite_memory = true;
	release_parser_tree(parsed);
	release_parser_names(parsed);
	release(storage);
	free(input);
	free(filename);
}

check_shallow_alias_control :: () {
	storage: Pool;
	set_allocators(*storage, context.allocator);
	storage.overwrite_memory = true;
	previous := context.allocator;
	context.allocator = .{proc = pool_allocator_proc, data = *storage};
	parsed := parse_file("target :: 7; reference :: target;", resolve_identifiers = false);
	context.allocator = previous;

	left_alias := parsed;
	right_alias := parsed;

	statements := parsed.root.(*Parser_Block).statements;
	reference := statements[1].(*Parser_Declaration).expression.(*Parser_Ident);

	assert(reference.resolved_declaration == null);
	resolve_lexical_references(left_alias.root_scope);
	right_reference := right_alias.root.(*Parser_Block).statements[1].(*Parser_Declaration).expression.(*Parser_Ident);
	assert(right_reference == reference);
	assert(right_reference.resolved_declaration == statements[0].(*Parser_Declaration));

	release_parser_tree(*parsed);
	release_parser_names(*parsed);
	release(*storage);
}

run_scenario :: (fixture: Fixture, producer_first: bool, right_first: bool, summary: *string) {
	syntax_storage: Pool;
	builder_storage: Pool;
	set_allocators(*syntax_storage, context.allocator);
	set_allocators(*builder_storage, context.allocator);
	syntax_storage.overwrite_memory = true;
	builder_storage.overwrite_memory = true;
	input := copy_string(fixture.source);
	filename := copy_string(tprint("e6/%.jai", fixture.name));

	previous := context.allocator;
	context.allocator = .{proc = pool_allocator_proc, data = *builder_storage};
	parsed := parse_file(input, filename, resolve_identifiers = false);
	context.allocator = previous;

	assert(parsed.status == fixture.status, "Unexpected E6 fixture status: %", fixture.name);
	assert(!!parsed.diagnostics.count == (fixture.status != .COMPLETE));
	assert(reconstruct_source(*parsed) == fixture.source);
	syntax := project_syntax(*parsed, *syntax_storage);
	check_spans(*syntax);

	if fixture.name == {
		case "scalar_and_decoded";
			assert(syntax.declarations.count == 3);
			assert(syntax.declarations[2].text == "first\nsecond\t\"quoted\"");

		case "here_string";
			assert(syntax.declarations[0].text == "first\nsecond\n");

		case "empty_and_wide";
			assert(syntax.declarations[0].text.count == 0);
			assert(syntax.declarations[1].number == 0xFFFF_FFFF_FFFF_FFFF);
	}

	frozen := freeze_syntax(*syntax);
	defer free(frozen);

	if producer_first {
		destroy_producer(*parsed, *builder_storage, input, filename);
		assert_unchanged(*syntax, frozen);
	}

	left_storage: Pool;
	right_storage: Pool;
	left := attach_context(*syntax, *left_storage, 19);
	right := attach_context(*syntax, *right_storage, 41);

	assert(left.syntax == right.syntax && left.symbol != right.symbol);
	if syntax.declarations.count {
		assert(left.bindings.data != right.bindings.data);
	}

	check_context(*left, 19);
	check_context(*right, 41);
	assert_unchanged(*syntax, frozen);

	if !producer_first {
		destroy_producer(*parsed, *builder_storage, input, filename);
	}

	assert_unchanged(*syntax, frozen);
	left.symbol.value = 23;
	check_context(*left, 23);
	check_context(*right, 41);

	for declaration, index: syntax.declarations {
		if declaration.kind == .TEXT && declaration.text.count {
			assert(left.bindings[index].text.data != declaration.text.data);
			left.bindings[index].text[0] ^= 1;
			assert(left.bindings[index].text != declaration.text);
			text_mutations += 1;
			check_context(*right, 41);
			assert_unchanged(*syntax, frozen);
			left.bindings[index].text[0] ^= 1;
		}
	}

	if right_first {
		release_context(*right, *right_storage);
		check_context(*left, 23);
	} else {
		release_context(*left, *left_storage);
		check_context(*right, 41);
	}

	assert_unchanged(*syntax, frozen);
	if right_first {
		release_context(*left, *left_storage);
	} else {
		release_context(*right, *right_storage);
	}

	assert_unchanged(*syntax, frozen);
	third_storage: Pool;
	third := attach_context(*syntax, *third_storage, 67);
	check_context(*third, 67);
	release_context(*third, *third_storage);
	assert_unchanged(*syntax, frozen);
	oracle_storage: Pool;
	oracle_builder: Pool;

	set_allocators(*oracle_storage, context.allocator);
	set_allocators(*oracle_builder, context.allocator);
	oracle_storage.overwrite_memory = true;
	oracle_builder.overwrite_memory = true;
	oracle_input := copy_string(fixture.source);
	oracle_filename := copy_string(tprint("e6/%.jai", fixture.name));

	context.allocator = .{proc = pool_allocator_proc, data = *oracle_builder};
	oracle_parsed := parse_file(oracle_input, oracle_filename, resolve_identifiers = false);
	context.allocator = previous;

	oracle := project_syntax(*oracle_parsed, *oracle_storage);
	destroy_producer(*oracle_parsed, *oracle_builder, oracle_input, oracle_filename);
	assert_unchanged(*oracle, frozen);
	release(*oracle_storage);
	assert_unchanged(*syntax, frozen);
	check_spans(*syntax);
	row := tprint(
		"%\t%\t%\t%\t%\t%\t%\t%\t%\n",
		fixture.name,
		producer_first,
		right_first,
		syntax.status,
		syntax.declarations.count,
		syntax.tokens.count,
		syntax.diagnostics.count,
		syntax.recovery.count,
		syntax.synthetic.count
	);
	summary.* = tprint("%%", summary.*, row);
	assert(write_entire_file(tprint("%/summary.tsv", OUTPUT_DIRECTORY), summary.*));
	print("%", row);
	release(*syntax_storage);
}

main :: () {
	assert(make_directory_if_it_does_not_exist(".build"));
	assert(make_directory_if_it_does_not_exist(OUTPUT_DIRECTORY));
	check_shallow_alias_control();
	summary := "case\tproducer_first\tright_first\tstatus\tdeclarations\ttokens\tdiagnostics\trecovery\tsynthetic\n";
	for fixture: FIXTURES {
		for producer_first: bool.[false, true] {
			for right_first: bool.[false, true] {
				run_scenario(fixture, producer_first, right_first, *summary);
			}
		}
	}

	scenarios := FIXTURES.count * 4;
	assert(context_creations == scenarios * 3 && context_releases == context_creations);
	assert(text_mutations == 8);
	assert(write_entire_file(tprint("%/compiler_version.txt", OUTPUT_DIRECTORY), COMPILER_VERSION));
	audit := tprint(
		"{\"scenarios\":%,\"fixtures\":%,\"fresh_oracles\":%,\"syntax_checks\":%,\"context_creations\":%,\"context_releases\":%,\"text_mutations\":%,\"shallow_alias_controls\":1}\n",
		scenarios,
		FIXTURES.count,
		scenarios,
		syntax_checks,
		context_creations,
		context_releases,
		text_mutations
	);
	assert(write_entire_file(tprint("%/audit_summary.json", OUTPUT_DIRECTORY), audit));
	print(
		"E6 complete: % lifecycle scenarios, % syntax checks, %/% semantic contexts created/released, and shared-node alias control.\n",
		scenarios,
		syntax_checks,
		context_creations,
		context_releases
	);
}

#run set_build_options_dc(.{write_added_strings = false});
