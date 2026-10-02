// Parse focused valid and malformed source snippets under default and trivia-enabled imports; assert token spans, parser-owned AST fields, round trips, and recovery.
// Some tests copy string-literal sources so they can free an old input while checking that newer parse snapshots remain valid.

#import "Basic";
#import "Compiler";
#import "File";
#import "File_Utilities";
#import "Hash";
#import "Pool";
#import "String";

Default  :: #import "Jai_Parser";
Extended :: #import "Jai_Parser"(ENABLE_TRIVIA=true, INTERN_IDENTIFIERS=true);

COMPILER_PERCENT_HERE_STRING :: #string,\% END
%\%
END

compiler_node_for_source :: ($source: string) -> *Code_Node #expand {
	#insert -> string {
		return tprint("return compiler_get_nodes(#code %);", source);
	}
}

#assert(size_of(Default.Parser_Token) == size_of(Default.Token));
#assert(size_of(Extended.Parser_Token) > size_of(Extended.Token));
#assert(size_of(Default.Parser_Node) == size_of(Code_Node));
#assert(size_of(Extended.Parser_Node) > size_of(Default.Parser_Node));
#assert(size_of(Default.Parsed_Source) == size_of(Extended.Parsed_Source));

#run {
	first := compiler_get_nodes(#code { a: int; a=, b := proc(); }).(*Code_Block).statements[1].(*Code_Compound_Declaration);
	second := compiler_get_nodes(#code { b: int; a:, b = proc(); }).(*Code_Block).statements[1].(*Code_Compound_Declaration);
	assert(first.comma_separated_assignment.arguments[0].modifier == .ASSIGN);
	assert(first.comma_separated_assignment.arguments[1].modifier == .NONE);
	assert(first.operator_type == 0);
	assert(second.comma_separated_assignment.arguments[0].modifier == .DECLARE);
	assert(second.comma_separated_assignment.arguments[1].modifier == .NONE);
	assert(second.operator_type == #char "=");
}

main :: () {
	// Lexer contracts and complete tutorial sources.
	test_default_tokens();
	test_lexer_only_recovery();
	test_star_token_contract();
	test_asm_token_contract();
	test_asm_tutorial_source();
	test_for_expansion_tutorial_source();
	test_asm_tutorial_forms();

	// Tokens, node ownership, and edit snapshot lifetimes.
	test_utf8_bom();
	test_trivia_round_trip();
	test_node_token_spans();
	test_identifier_expression();
	test_literal_expressions();
	test_aggregate_literals();
	test_operator_declarations();
	test_uninitialized_indicator_and_here_string();
	test_token_navigation();
	test_parser_node_pool();
	test_identifier_storage_lifetime();
	test_edit_snapshot_lifetime();
	test_reuse_snapshot_lifetime();
	test_file_edit_api();

	// Declaration reuse and candidate boundaries.
	test_numeric_ast_reuse();
	test_recovered_snapshot_ast_reuse_fallback();
	test_new_recovered_edit_fallback();
	test_repeated_convergence_edit();
	test_simple_candidate_syntax_edits();
	test_semicolon_boundary_ast_reuse();
	test_typed_declaration_ast_reuse();
	test_nested_type_instantiation_reuse();
	test_type_instantiation_fallback();
	test_array_view_declaration_ast_reuse();
	test_fixed_array_declaration_ast_reuse();
	test_double_pointer_declaration_ast_reuse();
	test_uninitialized_typed_declaration_ast_reuse();
	test_typed_compound_ast_reuse();
	test_uninitialized_typed_compound_ast_reuse();
	test_compound_ast_reuse();
	test_three_name_compound_ast_reuse();
	test_four_name_compound_ast_reuse();
	test_compound_reassignment_ast_reuse();
	test_compound_candidate_edits();

	// Literal, operator, and query reuse.
	test_scalar_literal_ast_reuse();
	test_source_backed_ast_reuse();
	test_source_position_ast_reuse();
	test_excluded_literal_ast_reuse_fallback();
	test_aggregate_payload_edits();
	test_nested_ast_reuse();
	test_remainder_ast_reuse();
	test_equality_ast_reuse();
	test_inequality_ast_reuse();
	test_ordered_comparison_ast_reuse();
	test_logical_ast_reuse();
	test_bitwise_ast_reuse();
	test_shift_rotate_ast_reuse();
	test_operator_grouping_edit();
	test_unary_ast_reuse();
	test_expression_query_ast_reuse();
	test_query_fallback();
	test_type_query_ast_reuse();

	// Excluded nodes and body fallback boundaries.
	test_excluded_expression_nodes();
	test_excluded_file_nodes();
	test_excluded_statement_nodes();
	test_imperative_body_fallback();
	test_aggregate_body_fallback();
	test_aggregate_parameter_block_fallback();
	test_single_declaration_branch_fallback();
	test_synthetic_imperative_block_fallback();
	test_enum_body_fallback();
	test_case_arm_fallback();
	test_lowered_directive_ast_reuse();
	test_excluded_directive_payload_edit();

	// Unary, cast, call, and aggregate subtree reuse.
	test_positive_unary_ast_reuse();
	test_negative_unary_ast_reuse();
	test_prefix_dereference_ast_reuse();
	test_pointer_dereference_ast_reuse();
	test_postfix_dereference_ast_reuse();
	test_cast_ast_reuse();
	test_cast_flags_ast_reuse();
	test_call_ast_reuse();
	test_member_callee_ast_reuse();
	test_call_context_ast_reuse();
	test_call_context_fallback();
	test_call_cast_fallback();
	test_call_cast_candidate_edits();
	test_member_ast_reuse();
	test_subscript_ast_reuse();
	test_aggregate_ast_reuse();

	// Nested scopes and invalidation after edits.
	test_nested_block_ast_reuse();
	test_nested_block_scope_reuse();
	test_indentation_only_ast_reuse();
	test_nested_shadowing_ast_reuse();
	test_dependency_forward_binding_edit();
	test_moved_closing_brace_ast_reuse();
	test_default_edit_fallback();

	// Recovery, diagnostics, and complete-file contracts.
	test_recovery_synchronization();
	test_complete_file_parsing();
	test_parenthesized_expression();
	test_missing_close_parenthesis();
	test_null_and_context();
	test_unexpected_token_diagnostic();
	test_recovery_records();
	test_restart_points();
	test_incomplete_diagnostics();
	test_lexical_bindings();
	test_file_import_resolution();
	test_diagnostic_tab_rendering();

	// Expression and declaration grammar.
	test_prefix_expressions();
	test_postfix_expressions();
	test_call_context_modification();
	test_casts_and_queries();
	test_parameter_default_delimiters();
	test_static_if_directives();
	test_preserved_directive_forms();
	test_expression_directives();
	test_binary_expressions();
	test_basic_declarations();
	test_compound_declarations();
	test_container_types();
	test_procedure_types();
	test_polymorphic_types();
	test_declaration_metadata();

	// Statements, control flow, and assembly recovery.
	test_basic_statements_and_blocks();
	test_loop_and_scoped_statements();
	test_for_body_forms();
	test_duplicate_for_flags();
	test_conditional_statements();
	test_statement_recovery();
	test_section_13_recovery();
	test_assembly_node_model();
	test_assembly_recovery();
}

test_asm_tutorial_source :: () {
	source, success := read_entire_file("../../../how_to/900_inline_assembly.jai");
	assert(success);
	defer free(source);

	parsed := Extended.parse_file(source);
	defer Extended.release_parser_tree(*parsed);

	assert(parsed.status == .COMPLETE);
	assert(parsed.diagnostics.count == 0);
	assert(Extended.reconstruct_source(*parsed) == source);
}

test_for_expansion_tutorial_source :: () {
	source, success := read_entire_file("../../../how_to/730_for_expansions.jai");
	assert(success);
	defer free(source);

	parsed := Extended.parse_file(source);
	defer Extended.release_parser_tree(*parsed);

	assert(parsed.status == .COMPLETE);
	assert(parsed.diagnostics.count == 0);
	assert(Extended.reconstruct_source(*parsed) == source);
}

test_asm_tutorial_forms :: () {
	BASICS_SOURCE :: #string JAI
{
	#asm {
		mov apple:, 10;
		banana: gpr;
		mov.64 banana, 17;
	}
	#asm {
		sub banana, apple;
		add count, banana;
	}
}
JAI;
	basics := Extended.parse_block(BASICS_SOURCE);
	assert(basics.status == .COMPLETE);
	basics_statements := basics.root.(*Extended.Parser_Block).statements;
	assert(basics_statements.count == 2);
	basics_asm := basics_statements[0].(*Extended.Parser_Asm);
	assert(basics_asm.statements[0].instruction.operands[0].register_declaration.name.name == "apple");
	assert(basics_asm.statements[1].register_declaration.register_class.name == "gpr");
	assert(basics_asm.statements[2].instruction.size.kind == .FIXED);
	assert(basics_statements[0].(*Extended.Parser_Asm).enclosing_scope == basics_statements[1].(*Extended.Parser_Asm).enclosing_scope);
	assert(Extended.reconstruct_source(*basics) == BASICS_SOURCE);

	IMMEDIATE_SOURCE :: #string JAI
{
	#asm {
		mov.8 b1:, 255;
		mov.8 b2:, -127;
		mov.16 w1:, 65535;
		mov.32 d1:, 4294967295;
		mov.64 q3:, 18446744073709551615;
		mov.64 q4:, -9223372036854775808;
		mov.32 f1:, 133.247;
		mov.64 f2:, 133.247;
	}
}
JAI;
	immediates := Extended.parse_block(IMMEDIATE_SOURCE);
	assert(immediates.status == .COMPLETE);
	immediate_statements := immediates.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Asm).statements;
	assert(immediate_statements.count == 8);
	assert(immediate_statements[0].instruction.size.kind == .FIXED);
	assert(immediate_statements[4].instruction.operands[1].value.expression.(*Extended.Parser_Literal)._u64 == 18446744073709551615);
	assert((immediate_statements[5].instruction.operands[1].value.expression.(*Extended.Parser_Literal).value_flags & .MINUS_SIGN) != 0);
	assert(immediate_statements[6].instruction.operands[1].value.expression.kind == .LITERAL);
	assert(immediate_statements[7].instruction.operands[1].value.expression.kind == .LITERAL);
	assert(Extended.reconstruct_source(*immediates) == IMMEDIATE_SOURCE);

	FEATURE_SOURCE :: #string JAI
{
	#asm AVX, AVX2 {}
	#asm AVX2 {
		pxor v1:, v1, v1;
	}
}
JAI;
	features := Extended.parse_block(FEATURE_SOURCE);
	assert(features.status == .COMPLETE);
	feature_blocks := features.root.(*Extended.Parser_Block).statements;
	assert(feature_blocks.count == 2);
	assert(feature_blocks[0].(*Extended.Parser_Asm).features.count == 2);
	assert(feature_blocks[0].(*Extended.Parser_Asm).statements.count == 0);
	assert(feature_blocks[1].(*Extended.Parser_Asm).features[0].name.name == "AVX2");
	assert(feature_blocks[1].(*Extended.Parser_Asm).statements[0].instruction.mnemonic.name == "pxor");
	assert(Extended.reconstruct_source(*features) == FEATURE_SOURCE);

	MACRO_SOURCE :: #string JAI
{
	reg :: __reg;
	add_the_two_regs :: (left: reg, right: reg) #expand {
		#asm {
			add left, right;
		}
	}
	#asm {
		mov a:, 12;
		mov b:, 18;
	}
	add_the_two_regs(b, a);
}
JAI;
	macro := Extended.parse_block(MACRO_SOURCE);
	assert(macro.status == .COMPLETE);
	macro_statements := macro.root.(*Extended.Parser_Block).statements;
	assert(macro_statements.count == 4);
	assert(macro_statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).name == "__reg");
	macro_header := macro_statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header);
	assert(macro_header.arguments.count == 2);
	assert(macro_header.arguments[0].type_inst.type_valued_expression.(*Extended.Parser_Ident).name == "reg");
	assert(macro_header.arguments[1].type_inst.type_valued_expression.(*Extended.Parser_Ident).name == "reg");
	assert(macro_header.body_or_null.block.statements[0].(*Extended.Parser_Asm).statements[0].instruction.operands[0].value.expression.(*Extended.Parser_Ident).name == "left");
	assert(macro_statements[3].kind == .PROCEDURE_CALL);
	assert(Extended.reconstruct_source(*macro) == MACRO_SOURCE);

	RUN_SOURCE :: #string JAI
{
	do_some_work :: (a: int, b: int) -> int {
		#asm {
			add a, b;
		}
		return a;
	}
	A :: #run do_some_work(10, 13);
}
JAI;
	run_file := Extended.parse_block(RUN_SOURCE);
	assert(run_file.status == .COMPLETE);
	run_statements := run_file.root.(*Extended.Parser_Block).statements;
	work_body := run_statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block;
	assert(work_body.statements[0].(*Extended.Parser_Asm).statements[0].instruction.mnemonic.name == "add");
	assert(run_statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Directive_Run).expression.kind == .PROCEDURE_CALL);
	assert(Extended.reconstruct_source(*run_file) == RUN_SOURCE);

	VSIB_SOURCE :: #string JAI
{
	#asm AVX, AVX2 {
		gatherdps gather_dest:, [original_float_array_pointer + vindex*4], gather_mask;
	}
}
JAI;
	vsib := Extended.parse_block(VSIB_SOURCE);
	assert(vsib.status == .COMPLETE);
	vsib_asm := vsib.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Asm);
	assert(vsib_asm.features.count == 2);
	gather := vsib_asm.statements[0].instruction;
	assert(gather.mnemonic.name == "gatherdps" && gather.operands.count == 3);
	assert(gather.operands[0].register_declaration.name.name == "gather_dest");
	assert(gather.operands[1].kind == .MEMORY);
	assert(gather.operands[1].memory.base.expression.(*Extended.Parser_Ident).name == "original_float_array_pointer");
	assert(gather.operands[1].memory.index.expression.(*Extended.Parser_Ident).name == "vindex");
	assert(gather.operands[1].memory.scale.expression.(*Extended.Parser_Literal)._u64 == 4);
	assert(gather.operands[2].value.expression.(*Extended.Parser_Ident).name == "gather_mask");
	assert(Extended.reconstruct_source(*vsib) == VSIB_SOURCE);

	EVEX_SOURCE :: #string JAI
{
	#asm AVX512F {
		cvtps2dq v1:, [value_pointer]!;
		cvtps2dq v3:, v2 !z;
		cvtps2dq v5: &* mask, v4 !z;
	}
}
JAI;
	evex := Extended.parse_block(EVEX_SOURCE);
	assert(evex.status == .COMPLETE);
	evex_asm := evex.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Asm);
	assert(evex_asm.features[0].name.name == "AVX512F");
	assert(evex_asm.statements.count == 3);
	assert(evex_asm.statements[0].instruction.operands[1].kind == .MEMORY);
	assert(evex_asm.statements[0].instruction.operands[1].modifiers[0].kind == .BANG);
	assert(evex_asm.statements[1].instruction.operands[1].modifiers[0].kind == .BANG_Z);
	masked := evex_asm.statements[2].instruction.operands[0];
	assert(masked.kind == .REGISTER_DECLARATION);
	assert(masked.register_declaration.name.name == "v5");
	assert(masked.modifiers[0].kind == .AMPERSAND_STAR);
	assert(masked.modifiers[0].argument.expression.(*Extended.Parser_Ident).name == "mask");
	assert(evex_asm.statements[2].instruction.operands[1].modifiers[0].kind == .BANG_Z);
	assert(Extended.reconstruct_source(*evex) == EVEX_SOURCE);

	SIZE_SOURCE :: #string JAI
{
	#if BITS == 8 #asm {
		popcnt.16 result, two_bytes;
	} else #asm {
		popcnt?BITS result, value;
		popcnt?T result, value;
	}
}
JAI;
	sizes := Extended.parse_block(SIZE_SOURCE);
	assert(sizes.status == .COMPLETE);
	size_branch := sizes.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_If);
	assert((size_branch.if_flags & .IS_STATIC) != 0);
	fixed := size_branch.then_block.statements[0].(*Extended.Parser_Asm).statements[0].instruction;
	assert(fixed.mnemonic.name == "popcnt" && fixed.size.kind == .FIXED);
	assert(Extended.token_at(*sizes, fixed.size.span.first).original_text == ".16");
	polymorphic := size_branch.else_block.statements[0].(*Extended.Parser_Asm).statements;
	assert(polymorphic[0].instruction.size.kind == .POLYMORPHIC);
	assert(polymorphic[0].instruction.size.polymorphic_name.name == "BITS");
	assert(polymorphic[1].instruction.size.polymorphic_name.name == "T");
	assert(Extended.reconstruct_source(*sizes) == SIZE_SOURCE);
}

test_default_tokens :: () {
	parsed := Default.materialise_tokens("a + b * c");
	assert(parsed.status == .COMPLETE);
	assert(parsed.tokens.count == 6);
	assert(parsed.tokens[0].type == .IDENT);
	assert(parsed.tokens[5].type == .END_OF_INPUT);
}

test_lexer_only_recovery :: () {
	IDENTIFIER_LENGTH :: Extended.MAX_IDENTIFIER_LENGTH + 8;
	SUFFIX :: " :: 1;";

	source := alloc_string(IDENTIFIER_LENGTH + SUFFIX.count);
	defer free(source);

	for index: 0..IDENTIFIER_LENGTH-1 {
		source.data[index] = #char "a";
	}

	memcpy(source.data + IDENTIFIER_LENGTH, SUFFIX.data, SUFFIX.count);

	parsed := Extended.parse_file(source);
	defer Extended.release_parser_tree(*parsed);

	assert(parsed.status == .RECOVERED);
	assert(parsed.diagnostics.count == 1);
	diagnostic := parsed.diagnostics[0];
	assert(diagnostic.kind == .LEXER_ERROR);
	assert(diagnostic.message == "Identifier exceeds the maximum length of 511 bytes.\n");
	assert(diagnostic.lexer_line == 1 && diagnostic.lexer_column == 513);
	assert(diagnostic.span.first == xx 0 && diagnostic.span.one_past_last == xx 1);
	assert(parsed.root.(*Extended.Parser_Block).statements.count == 1);
	assert(Extended.reconstruct_source(*parsed) == source);

	lexer: Extended.Lexer;
	Extended.set_input_from_string(*lexer, source);
	assert(lexer.error_callback == null);
	Extended.peek_next_token(*lexer);
	assert(lexer.reported_error);

	overflow := Extended.parse_expression("18446744073709551616");
	defer Extended.release_parser_tree(*overflow);

	assert(overflow.status == .RECOVERED);
	assert(overflow.diagnostics.count == 1);
	assert(overflow.diagnostics[0].kind == .LEXER_ERROR);
	assert(overflow.diagnostics[0].message == "Integer literal is too big.  All integer literals must fit into 64 bits.\n");
	assert(overflow.diagnostics[0].lexer_line == 1 && overflow.diagnostics[0].lexer_column == 1);
	assert(overflow.diagnostics[0].span.first == xx 0);

	mixed := Extended.parse_expression("18446744073709551616 +");
	defer Extended.release_parser_tree(*mixed);

	assert(mixed.diagnostics.count == 2);
	assert(mixed.diagnostics[0].kind == .LEXER_ERROR);
	assert(mixed.diagnostics[1].kind == .EXPECTED_EXPRESSION);

	escape := Extended.parse_expression("\"\\d?\"");
	defer Extended.release_parser_tree(*escape);

	assert(escape.status == .RECOVERED);
	assert(escape.diagnostics.count == 1);
	assert(escape.diagnostics[0].kind == .LEXER_ERROR);
	assert(escape.diagnostics[0].message == "A decimal digit is required here.\n");
	assert(escape.diagnostics[0].related_information.count == 1);
	assert(escape.diagnostics[0].related_information[0].message == "\\d must be followed by exactly three decimal digits.\n", "Actual detail: '%'.", escape.diagnostics[0].related_information[0].message);
	assert(escape.diagnostics[0].related_information[0].span.first == escape.diagnostics[0].span.first);
}

test_star_token_contract :: () {
	pointer_type := Extended.materialise_tokens("*u8");
	assert(pointer_type.tokens.count == 3);
	assert(pointer_type.tokens[0].type == #char "*");
	assert(pointer_type.tokens[1].type == .IDENT);

	address_of := Extended.materialise_tokens("*value");
	assert(address_of.tokens.count == 3);
	assert(address_of.tokens[0].type == #char "*");
	assert(address_of.tokens[1].type == .IDENT);

	pointer_literal := Extended.materialise_tokens("*[123] int");
	assert(pointer_literal.tokens.count == 6);
	assert(pointer_literal.tokens[0].type == #char "*");
	assert(pointer_literal.tokens[1].type == #char "[");
	assert(pointer_literal.tokens[2].type == .NUMBER);
	assert(pointer_literal.tokens[3].type == #char "]");
	assert(pointer_literal.tokens[4].type == .IDENT);

	cast_type := Extended.materialise_tokens("cast(*u8)");
	assert(cast_type.tokens.count == 6);
	assert(cast_type.tokens[0].type == .KEYWORD_CAST);
	assert(cast_type.tokens[1].type == #char "(");
	assert(cast_type.tokens[2].type == #char "*");
	assert(cast_type.tokens[3].type == .IDENT);
	assert(cast_type.tokens[4].type == #char ")");

	generic_type := Extended.materialise_tokens("Table(*Message, Info)");
	assert(generic_type.tokens.count == 8);
	assert(generic_type.tokens[0].type == .IDENT);
	assert(generic_type.tokens[2].type == #char "*");
	assert(generic_type.tokens[3].type == .IDENT);

	multiplication := Extended.materialise_tokens("left * right");
	assert(multiplication.tokens[1].type == #char "*");

	postfix_dereference := Extended.materialise_tokens("value.*");
	assert(postfix_dereference.tokens.count == 3);
	assert(postfix_dereference.tokens[1].type == .POSTFIX_DEREFERENCE);

	prefix_dereference := Extended.materialise_tokens("(.*)value");
	assert(prefix_dereference.tokens.count == 3);
	assert(prefix_dereference.tokens[0].type == .PREFIX_DEREFERENCE);
}

test_asm_token_contract :: () {
	SOURCE :: #string JAI
#asm AVX, AVX2 {
	// declaration and pinning
	mov.8 apple:, -10;
	t: future_class === source;
	popcnt?BITS result, value;
	cvtps2dq destination:, [base + index*8 - (-10.5)]!z &* mask; /* tail */
}
JAI;
	parsed := Extended.materialise_tokens(SOURCE);
	assert(parsed.status == .COMPLETE);
	assert(Extended.reconstruct_source(*parsed) == SOURCE);

	expected_types := Extended.Token_Type.[
		#char "#", .IDENT, .IDENT, #char ",", .IDENT, #char "{",
		.IDENT, .NUMBER, .IDENT, #char ":", #char ",", #char "-", .NUMBER, #char ";",
		.IDENT, #char ":", .IDENT, .TRIPLE_EQUALS, .IDENT, #char ";",
		.IDENT, #char "?", .IDENT, .IDENT, #char ",", .IDENT, #char ";",
		.IDENT, .IDENT, #char ":", #char ",", #char "[", .IDENT, #char "+", .IDENT, #char "*", .NUMBER, #char "-", #char "(", #char "-",
		.NUMBER, #char ")", #char "]", #char "!", .IDENT, .BITWISE_AND, #char "*", .IDENT, #char ";",
		#char "}",
		.END_OF_INPUT,
	];
	expected_spellings := string.[
		"#", "asm", "AVX", ",", "AVX2", "{",
		"mov", ".8", "apple", ":", ",", "-", "10", ";",
		"t", ":", "future_class", "===", "source", ";",
		"popcnt", "?", "BITS", "result", ",", "value", ";",
		"cvtps2dq", "destination", ":", ",", "[", "base", "+", "index", "*", "8", "-", "(", "-", "10.5", ")", "]", "!", "z", "&", "*", "mask", ";",
		"}",
		"",
	];

	assert(parsed.tokens.count == expected_types.count);
	assert(parsed.tokens.count == expected_spellings.count);
	for token: parsed.tokens {
		assert(token.type == expected_types[it_index], "Assembly token % ('%') has type %, expected %.", it_index, token.original_text, token.type, expected_types[it_index]);
		assert(token.original_text == expected_spellings[it_index], "Assembly token % has spelling '%', expected '%'.", it_index, token.original_text, expected_spellings[it_index]);
		assert(token.byte_end - token.byte_start == token.original_text.count);
		assert(slice(SOURCE, token.byte_start, token.byte_end - token.byte_start) == token.original_text);
	}

	assert(parsed.tokens[6].preceding_trivia == "\n\t// declaration and pinning\n\t");
	assert(parsed.tokens[parsed.tokens.count - 2].preceding_trivia == " /* tail */\n");

	MODIFIER_SOURCE :: "value! value!n value!d value!u value!z value & mask value &* mask -10 +20 -10.5 +20.5";
	modifiers := Extended.materialise_tokens(MODIFIER_SOURCE);
	expected_modifier_spellings := string.[
		"value", "!", "value", "!", "n", "value", "!", "d", "value", "!", "u", "value", "!", "z",
		"value", "&", "mask", "value", "&", "*", "mask",
		"-", "10", "+", "20", "-", "10.5", "+", "20.5", "",
	];
	assert(modifiers.tokens.count == expected_modifier_spellings.count);
	for token: modifiers.tokens {
		assert(token.original_text == expected_modifier_spellings[it_index]);
		assert(slice(MODIFIER_SOURCE, token.byte_start, token.byte_end - token.byte_start) == token.original_text);
	}

	assert(modifiers.tokens[1].type == #char "!");
	assert(modifiers.tokens[15].type == .BITWISE_AND);
	assert(modifiers.tokens[18].type == .BITWISE_AND);
	assert(modifiers.tokens[19].type == #char "*");
	assert(modifiers.tokens[21].type == #char "-");
	assert(modifiers.tokens[22].type == .NUMBER);
	assert(modifiers.tokens[23].type == #char "+");
	assert(modifiers.tokens[24].type == .NUMBER);
	assert(Extended.reconstruct_source(*modifiers) == MODIFIER_SOURCE);

	SUFFIX_SOURCE :: "mov.8 mov.64 popcnt?BITS popcnt?T";
	suffixes := Extended.materialise_tokens(SUFFIX_SOURCE);
	expected_suffix_types := Extended.Token_Type.[
		.IDENT, .NUMBER,
		.IDENT, .NUMBER,
		.IDENT, #char "?", .IDENT,
		.IDENT, #char "?", .IDENT,
		.END_OF_INPUT,
	];
	expected_suffix_spellings := string.[
		"mov", ".8",
		"mov", ".64",
		"popcnt", "?", "BITS",
		"popcnt", "?", "T",
		"",
	];

	assert(suffixes.tokens.count == expected_suffix_types.count);
	for token: suffixes.tokens {
		assert(token.type == expected_suffix_types[it_index]);
		assert(token.original_text == expected_suffix_spellings[it_index]);
	}

	assert(Extended.reconstruct_source(*suffixes) == SUFFIX_SOURCE);

	ORDINARY_SOURCE :: "object.member value?T";
	ordinary := Extended.materialise_tokens(ORDINARY_SOURCE);
	expected_ordinary_types := Extended.Token_Type.[
		.IDENT, #char ".", .IDENT,
		.IDENT, #char "?", .IDENT,
		.END_OF_INPUT,
	];
	assert(ordinary.tokens.count == expected_ordinary_types.count);
	for token: ordinary.tokens {
		assert(token.type == expected_ordinary_types[it_index]);
	}

	assert(ordinary.tokens[1].original_text == ".");
	assert(ordinary.tokens[4].original_text == "?");
	assert(Extended.reconstruct_source(*ordinary) == ORDINARY_SOURCE);
}

test_utf8_bom :: () {
	SOURCE :: "\xEF\xBB\xBFvalue :: 1;";
	parsed := Extended.parse_file(SOURCE);
	assert(parsed.status == .COMPLETE);
	assert(parsed.tokens[0].type == .IDENT);
	assert(parsed.tokens[0].byte_start == 3 && parsed.tokens[0].c0 == 1);
	assert(parsed.tokens[0].preceding_trivia == slice(SOURCE, 0, 3));
	assert(Extended.reconstruct_source(*parsed) == SOURCE);

	EDITED_SOURCE :: "\xEF\xBB\xBFvalue :: 2;";
	edited, ok := Extended.parse_file_edit(*parsed, SOURCE.count - 2, SOURCE.count - 1, EDITED_SOURCE);
	assert(ok && edited.status == .COMPLETE);
	assert(edited.tokens[0].byte_start == 3 && edited.tokens[0].preceding_trivia == slice(EDITED_SOURCE, 0, 3));
	assert(Extended.reconstruct_source(*edited) == EDITED_SOURCE);
	Extended.release_parser_tree(*edited);
	Extended.release_parser_names(*edited);
	Extended.release_parser_tree(*parsed);
	Extended.release_parser_names(*parsed);

	empty := Extended.parse_file("\xEF\xBB\xBF");
	assert(empty.status == .COMPLETE && empty.root.(*Extended.Parser_Block).statements.count == 0);
	assert(Extended.reconstruct_source(*empty) == empty.source);
	Extended.release_parser_tree(*empty);
	Extended.release_parser_names(*empty);
}

test_trivia_round_trip :: () {
	SOURCE :: #string JAI
str :: #string /**/ , /**/ cr END
123
END; // tail
JAI;
	parsed := Extended.materialise_tokens(SOURCE);
	assert(parsed.status == .COMPLETE);

	for token: parsed.tokens {
		assert(token.index == xx it_index);
	}

	body := parsed.tokens[8];
	assert(body.type == .STRING);
	assert((body.value_flags & .HERE_STRING) != 0);
	assert(body.preceding_trivia == "\n");
	assert(body.original_text == "123\n");
	assert(slice(SOURCE, body.byte_start, body.byte_end - body.byte_start) == body.original_text);

	reconstructed := Extended.reconstruct_source(*parsed);
	assert(reconstructed == SOURCE);
}

test_token_navigation :: () {
	parsed := Extended.materialise_tokens("a + b");
	first := Extended.token_at(*parsed, xx 0);
	second := Extended.next_token(*parsed, first.index);
	third := Extended.next_token(*parsed, second.index);

	assert(first.type == .IDENT);
	assert(second.type == #char "+");
	assert(third.type == .IDENT);
	assert(Extended.previous_token(*parsed, third.index) == second);
	assert(Extended.previous_token(*parsed, first.index) == null);

	parser := Extended.Parser.{parsed=*parsed};
	checkpoint := Extended.parser_checkpoint(*parser);
	Extended.parser_eat(*parser);
	assert(parser.cursor == 1);
	Extended.parser_restore(*parser, checkpoint);
	assert(parser.cursor == 0);

	assert(Extended.parser_peek_if(*parser, .IDENT, #char "+"));
	assert(!Extended.parser_peek_if(*parser, .IDENT, #char "-"));
	assert(parser.cursor == 0);

	assert(Extended.parser_eat_if(*parser, .IDENT, #char "+"));
	assert(parser.cursor == 2);
	Extended.parser_restore(*parser, checkpoint);

	assert(!Extended.parser_eat_if(*parser, .IDENT, #char "-"));
	assert(parser.cursor == 0);

	assert(Extended.parser_expect(*parser, .IDENT, #char "+"));
	assert(parser.cursor == 2);

	missing := Extended.materialise_tokens("a + b");
	missing_parser := Extended.Parser.{parsed=*missing};
	assert(!Extended.parser_expect(*missing_parser, .IDENT, #char "-"));
	assert(missing_parser.cursor == 1);
	assert(missing.diagnostics.count == 1);
	assert(missing.diagnostics[0].expected_token == #char "-");
	assert(missing.diagnostics[0].actual_token == #char "+");
}

test_parser_node_pool :: () {
	parsed := Extended.parse_expression("left + right");
	assert(parsed.root != null);
	assert(parsed.node_pool.used_memblocks != null);

	children: [..] *Extended.Parser_Node;
	children.allocator = Extended.parser_node_allocator(*parsed);
	array_add(*children, parsed.root);
	assert(children.count == 1);

	Extended.release_parser_tree(*parsed);
	assert(parsed.root == null);
	assert(parsed.node_pool.used_memblocks == null);
	assert(parsed.node_pool.unused_memblocks == null);
}

test_identifier_storage_lifetime :: () {
	copying := Default.materialise_tokens("alpha alpha");
	assert(copying.tokens[0].ident_value.name == copying.tokens[1].ident_value.name);
	assert(copying.tokens[0].ident_value.name.data != copying.tokens[1].ident_value.name.data);
	assert(copying.identifier_storage.names.count == 0);
	Default.release_parser_names(*copying);

	source := copy_string("alpha alpha some\\  name if @note");
	parsed := Extended.materialise_tokens(source);
	assert(parsed.tokens[0].ident_value.name.data == source.data);
	assert(parsed.tokens[0].ident_value.name.data == parsed.tokens[1].ident_value.name.data);
	assert(parsed.tokens[2].ident_value.name == "somename");
	assert(parsed.tokens[2].ident_value.name.data != source.data + 12);
	assert(parsed.tokens[3].type == .KEYWORD_IF);
	assert(parsed.tokens[4].type == .NOTE);
	assert(parsed.tokens[4].ident_value.name == "note");
	assert(parsed.tokens[4].ident_value.name.count == 4);
	assert(parsed.tokens[4].ident_value.name.data == source.data + source.count - 4);
	assert(parsed.identifier_storage.names.count == 3);
	assert(Extended.reconstruct_source(*parsed) == source);

	variants_source := copy_string("alpha `alpha beta beta if if @note @note");
	variants := Extended.materialise_tokens(variants_source);
	assert(variants.status == .COMPLETE);
	assert(variants.identifier_storage.names.count == 3);
	assert(variants.tokens[0].ident_value.name.data == variants.tokens[1].ident_value.name.data);
	assert(variants.tokens[1].ident_is_backticked);
	assert(variants.tokens[1].original_text == "`alpha");
	assert(variants.tokens[2].ident_value.name.data == variants.tokens[3].ident_value.name.data);
	assert(variants.tokens[0].ident_value.name.data != variants.tokens[2].ident_value.name.data);
	assert(variants.tokens[4].type == .KEYWORD_IF && variants.tokens[5].type == .KEYWORD_IF);
	assert(variants.tokens[6].type == .NOTE && variants.tokens[7].type == .NOTE);
	assert(variants.tokens[4].ident_value.name.data != variants.tokens[5].ident_value.name.data);
	assert(variants.tokens[6].ident_value.name.data == variants.tokens[7].ident_value.name.data);
	assert(Extended.reconstruct_source(*variants) == variants_source);

	assert(get_hash("id_vukw35") == get_hash("id_4f72ce"));
	collisions := Extended.materialise_tokens("id_vukw35 id_4f72ce id_vukw35 id_4f72ce");
	assert(collisions.identifier_storage.names.count == 2);
	assert(collisions.tokens[0].ident_value.name == "id_vukw35");
	assert(collisions.tokens[1].ident_value.name == "id_4f72ce");
	assert(collisions.tokens[0].ident_value.name.data == collisions.tokens[2].ident_value.name.data);
	assert(collisions.tokens[1].ident_value.name.data == collisions.tokens[3].ident_value.name.data);
	assert(collisions.tokens[0].ident_value.name.data != collisions.tokens[1].ident_value.name.data);
	Extended.release_parser_names(*collisions);

	other_source := copy_string("alpha");
	other := Extended.materialise_tokens(other_source);
	assert(other.tokens[0].ident_value.name == parsed.tokens[0].ident_value.name);
	assert(other.tokens[0].ident_value.name.data != parsed.tokens[0].ident_value.name.data);
	Extended.release_parser_tree(*parsed);
	assert(parsed.tokens[2].ident_value.name == "somename");
	Extended.release_parser_names(*parsed);
	Extended.release_parser_names(*other);
	assert(variants.tokens[1].ident_value.name == "alpha");
	Extended.release_parser_names(*variants);
	free(source);
	free(other_source);
	free(variants_source);

	file := Extended.parse_file("value :: 1;");
	assert(file.root != null);
	Extended.release_parser_tree(*file);
	assert(file.tokens[0].ident_value.name == "value");
	Extended.release_parser_names(*file);

	first_file_source :=	copy_string("entry :: entry; // first\n");
	second_file_source :=	copy_string("entry :: entry; // second\n");
	first_file := Extended.parse_file(first_file_source);
	second_file := Extended.parse_file(second_file_source);
	assert(first_file.status == .COMPLETE && second_file.status == .COMPLETE);
	assert(first_file.tokens[0].ident_value.name.data == first_file.tokens[3].ident_value.name.data);
	assert(first_file.tokens[0].ident_value.name.data != second_file.tokens[0].ident_value.name.data);
	Extended.release_parser_tree(*first_file);
	Extended.release_parser_names(*first_file);
	free(first_file_source);
	assert(second_file.root != null);
	assert(second_file.tokens[3].ident_value.name == "entry");
	assert(Extended.reconstruct_source(*second_file) == second_file_source);
	Extended.release_parser_tree(*second_file);
	Extended.release_parser_names(*second_file);
	free(second_file_source);

	standalone_source := copy_string("alpha");
	lexer: Extended.Lexer;
	Extended.set_input_from_string(*lexer, standalone_source);
	standalone_token := Extended.peek_next_token(*lexer).*;
	assert(standalone_token.ident_value.name.data != standalone_source.data);
	Extended.set_input_from_string(*lexer, "other");
	free(standalone_source);
	assert(standalone_token.ident_value.name == "alpha");

	standalone_note_source := copy_string("@note");
	Extended.set_input_from_string(*lexer, standalone_note_source);
	standalone_note := Extended.peek_next_token(*lexer).*;
	assert(standalone_note.type == .NOTE);
	assert(standalone_note.ident_value.name.data != standalone_note_source.data + 1);
	assert(standalone_note.ident_value.name.count == 4);
	Extended.set_input_from_string(*lexer, "other");
	free(standalone_note_source);
	assert(standalone_note.ident_value.name == "note");

	storage: Extended.Identifier_Storage;
	first_source := copy_string("shared");
	second_source := copy_string("shared");
	Extended.set_identifier_storage(*lexer, *storage);
	Extended.set_input_from_string(*lexer, first_source);
	first_token := Extended.peek_next_token(*lexer).*;
	Extended.set_input_from_string(*lexer, second_source);
	second_token := Extended.peek_next_token(*lexer).*;
	assert(first_token.ident_value.name.data == second_token.ident_value.name.data);
	assert(Extended.set_input_from_file(*lexer, "../../../how_to/001_first.jai"));
	file_name := Extended.peek_token(*lexer, 1).ident_value.name;
	assert(file_name == "import");
	Extended.set_input_from_string(*lexer, "after");
	assert(file_name == "import");
	Extended.set_identifier_storage(*lexer, null);
	Extended.release_identifier_storage(*storage);
	copy_source := copy_string("shared");
	Extended.set_input_from_string(*lexer, copy_source);
	copied_token := Extended.peek_next_token(*lexer).*;
	assert(copied_token.ident_value.name.data != copy_source.data);
	free(copy_source);
	assert(copied_token.ident_value.name == "shared");
	free(first_source);
	free(second_source);
}

test_edit_snapshot_lifetime :: () {
	old_source := copy_string("a :: 1;\nproc :: () { result := a");
	old := Extended.parse_file(old_source);
	assert(old.status == .INCOMPLETE);
	assert(old.synthetic_tokens.count > 0 && old.recovery_records.count > 0);
	old_root := old.root.(*Extended.Parser_Block);
	old_declaration := old_root.statements[0].(*Extended.Parser_Declaration);
	old_body := old_root.statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block;
	old_use := old_body.statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident);
	assert(old_use.resolved_declaration == old_declaration);
	old_anchor := old.restart_points[0].span.first;

	new_source := copy_string("inserted :: 2;\na :: 1;\nproc :: () { result := a; }");
	updated := Extended.parse_file(new_source);
	assert(updated.status == .COMPLETE);
	new_root := updated.root.(*Extended.Parser_Block);
	new_declaration := new_root.statements[1].(*Extended.Parser_Declaration);
	new_body := new_root.statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block;
	new_use := new_body.statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident);
	assert(new_use.resolved_declaration == new_declaration);
	assert(new_use.resolved_declaration != old_declaration);
	assert(Extended.token_at(*old, old_anchor).original_text != Extended.token_at(*updated, old_anchor).original_text);
	assert(Extended.reconstruct_source(*old) == old_source);
	assert(Extended.reconstruct_source(*updated) == new_source);

	Extended.release_parser_tree(*old);
	assert(old.root == null && old.root_scope == null);
	assert(old.restart_points[0].span.first == old_anchor);
	assert(old.tokens[0].original_text == "a");
	Extended.release_parser_names(*old);
	free(old_source);
	assert(new_use.resolved_declaration == new_declaration);
	assert(Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	free(new_source);
}

test_reuse_snapshot_lifetime :: () {
	for release_old_first: bool.[true, false] {
		old_source := copy_string(			   "target :: 1; left, right :: target; blocked := #run target; #if true { inner := target; }");
		new_source := copy_string("added :: 0;\ntarget :: 1; left, right :: target; blocked := #run target; #if true { inner := target; }");
		old := Extended.parse_file(old_source);
		updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
		assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE);
		old_statements := old.root.(*Extended.Parser_Block).statements;
		statements := updated.root.(*Extended.Parser_Block).statements;
		old_compound := old_statements[1].(*Extended.Parser_Compound_Declaration);
		compound := statements[2].(*Extended.Parser_Compound_Declaration);
		old_fallback := old_statements[2].(*Extended.Parser_Declaration).expression;
		fallback := statements[3].(*Extended.Parser_Declaration).expression;
		old_branch := old_statements[3].(*Extended.Parser_If).then_block;
		branch := statements[4].(*Extended.Parser_If).then_block;
		probe_tokens := Extended.materialise_tokens(new_source);
		probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, cursor=statements[2].first_token.(s64)};
		set_allocators(*probe_tokens.node_pool, context.default_allocator);
		probe.current_scope = Extended.push_lexical_scope(*probe);
		probe_tokens.root = Extended.reuse_simple_declaration(*probe);
		assert(probe_tokens.root && probe_tokens.root.kind == .COMPOUND_DECLARATION);
		probe.cursor = statements[3].first_token.(s64);
		assert(Extended.reuse_simple_declaration(*probe) == null);
		Extended.release_parser_tree(*probe_tokens);
		Extended.release_parser_names(*probe_tokens);
		assert(compound != old_compound && fallback != old_fallback && branch != old_branch);
		assert(compound.comma_separated_assignment.arguments.count == 2);
		assert(compound.declaration_properties.expression.(*Extended.Parser_Ident).resolved_declaration == statements[1].(*Extended.Parser_Declaration));
		assert(branch.statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == statements[1].(*Extended.Parser_Declaration));
		assert(old_branch.statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == old_statements[0].(*Extended.Parser_Declaration));

		if release_old_first {
			Extended.release_parser_tree(*old);
			Extended.release_parser_names(*old);
			free(old_source);
			assert(compound.comma_separated_assignment.arguments[0].node.(*Extended.Parser_Ident).name == "left");
			assert(fallback.kind == .DIRECTIVE_RUN && branch.owning_statement == statements[4]);
			assert(branch.statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).name == "target");
			assert(Extended.token_at(*updated, compound.first_token).original_text == "left");
			assert(Extended.reconstruct_source(*updated) == new_source);
			Extended.release_parser_tree(*updated);
			Extended.release_parser_names(*updated);
			free(new_source);
		} else {
			Extended.release_parser_tree(*updated);
			Extended.release_parser_names(*updated);
			free(new_source);
			assert(old_compound.comma_separated_assignment.arguments[0].node.(*Extended.Parser_Ident).name == "left");
			assert(old_fallback.kind == .DIRECTIVE_RUN && old_branch.owning_statement == old_statements[3]);
			assert(old_branch.statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).name == "target");
			assert(Extended.token_at(*old, old_compound.first_token).original_text == "left");
			assert(Extended.reconstruct_source(*old) == old_source);
			Extended.release_parser_tree(*old);
			Extended.release_parser_names(*old);
			free(old_source);
		}
	}
}

test_file_edit_api :: () {
	old_source := copy_string(				 "value := missing;");
	new_source := copy_string("missing :: 1;\nvalue := missing;");
	old := Extended.parse_file(old_source, "edited.jai");
	updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
	assert(ok && updated.status == .COMPLETE);
	assert(updated.fully_pathed_filename == "edited.jai");
	assert(updated.tokens[0].byte_start == 0);
	assert(updated.tokens[5].byte_start == 14);
	assert(Extended.reconstruct_source(*updated) == new_source);
	old_use := old.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident);
	new_root := updated.root.(*Extended.Parser_Block);
	new_use := new_root.statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident);
	assert(old_use.resolved_declaration == null);
	assert(new_use.resolved_declaration == new_root.statements[0].(*Extended.Parser_Declaration));

	replaced_source := copy_string("missing :: 12;\nvalue := missing;");
	replaced, replaced_ok := Extended.parse_file_edit(*updated, 12, 12, replaced_source);
	assert(replaced_ok && replaced.status == .COMPLETE);
	assert(Extended.reconstruct_source(*replaced) == replaced_source);
	assert(Extended.reconstruct_source(*updated) == new_source);

	invalid, invalid_ok := Extended.parse_file_edit(*old, -1, 0, new_source);
	assert(!invalid_ok && invalid.root == null);
	invalid, invalid_ok = Extended.parse_file_edit(*old, 1, 0, new_source);
	assert(!invalid_ok && invalid.root == null);
	invalid, invalid_ok = Extended.parse_file_edit(*old, 0, old_source.count + 1, new_source);
	assert(!invalid_ok && invalid.root == null);
	invalid, invalid_ok = Extended.parse_file_edit(*old, 0, 0, "bad");
	assert(!invalid_ok && invalid.root == null);
	invalid, invalid_ok = Extended.parse_file_edit(*old, 0, 0, "missing :: 1;\nvalue := changed;");
	assert(!invalid_ok && invalid.root == null);

	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	free(new_source);
	assert(Extended.reconstruct_source(*replaced) == replaced_source);
	Extended.release_parser_tree(*replaced);
	Extended.release_parser_names(*replaced);
	free(replaced_source);

	check_regional_lex(
				  "a :: 1; b := a;",
		"new :: 2; a :: 1; b := a;",
		0,
		0
	);
	check_regional_lex(
		"a :: 1; b := a;",
		"a :: 1;\n b := a;",
		7,
		7
	);
	check_regional_lex(
		"a :: 1;\nb := a;",
		"a :: 1;\n\nb := a;",
		8,
		8
	);
	check_regional_lex(
		"a :: 1; b := a;",
		"a :: 1;b := a;",
		7,
		8
	);
	check_regional_lex(
		"alpha := 1; beta := 2;",
		"al := 1; beta := 2;",
		2,
		5
	);
	check_regional_lex(
		"a :: 1; /* comment */\nb := a;",
		"a :: 1; \nb := a;",
		8,
		21
	);
	check_regional_lex(
		"a :: 1; b := 2;",
		"a :: 1; /*b := 2;",
		8,
		8
	);
	check_regional_lex(
		"broken: ; stable :: 1;",
		"broken: s64; stable :: 1;",
		"broken: ".count,
		"broken: ".count
	);
	check_regional_lex(
		"bad :: 18446744073709551616; stable :: 1;",
		"bad :: 1; stable :: 1;",
		"bad :: ".count,
		"bad :: 18446744073709551616".count
	);
	check_regional_lex(
		"bad :: 1; stable :: 1;",
		"bad :: 18446744073709551616; stable :: 1;",
		"bad :: ".count,
		"bad :: 1".count
	);
	check_regional_lex(
		"a :: \"x\"; b := 2;",
		"a :: \"xy\"; b := 2;",
		7,
		7
	);
	check_regional_lex(
		"first :: 1; middle :: 1; last :: 1; use := last;",
		"first :: 11; middle :: 1; last :: 1; use := last;",
		"first :: 1".count,
		"first :: 1".count
	);
	check_regional_lex(
		"text :: #string END\nhello\nEND\nnext :: 1;",
		"text :: #string END\nworld\nEND\nnext :: 1;",
		"text :: #string END\n".count,
		"text :: #string END\nhello".count
	);
	check_regional_lex(
		"text :: #string END\nhello\nEND\nnext :: 1;",
		"prefix :: 0;\ntext :: #string END\nhello\nEND\nnext :: 1;",
		0,
		0
	);
	check_regional_lex(
		"a :: 1; // tail",
		"a :: 1; // tail\n",
		"a :: 1; // tail".count,
		"a :: 1; // tail".count
	);
}

test_numeric_ast_reuse :: () {
	old_source := copy_string(				"use := missing; missing :: 2; tail :: 3;");
	new_source := copy_string("prefix :: 1;\nuse := missing; missing :: 2; tail :: 3;");
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && updated.status == .COMPLETE && fresh.status == .COMPLETE);

	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, edit_start=0, edit_end=0, cursor=5};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root && probe_tokens.root.(*Extended.Parser_Declaration).expression.kind == .IDENT);
	assert(probe_tokens.root.(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == null);
	assert(probe.current_scope.references.count == 1);
	probe.cursor = 10;
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root && probe_tokens.root.kind == .DECLARATION);
	assert(probe.cursor == 14);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);

	updated_statements := updated.root.(*Extended.Parser_Block).statements;
	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	assert(updated_statements.count == fresh_statements.count);
	assert(updated.diagnostics.count == fresh.diagnostics.count);
	assert(updated.restart_points.count == fresh.restart_points.count);
	for updated_statements {
		other := fresh_statements[it_index];
		assert(it.kind == other.kind && it.first_token == other.first_token && it.one_past_last_token == other.one_past_last_token);
		assert(it.l0 == other.l0 && it.c0 == other.c0 && it.l1 == other.l1 && it.c1 == other.c1);
	}

	for updated.restart_points {
		other := fresh.restart_points[it_index];
		assert(it.kind == other.kind && it.span.first == other.span.first && it.span.one_past_last == other.span.one_past_last);
	}

	updated_use := updated_statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident);
	fresh_use := fresh_statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident);
	assert(!(updated_statements[1].(*Extended.Parser_Declaration).flags & .IS_CONSTANT));
	assert(updated_statements[1].(*Extended.Parser_Declaration).flags == fresh_statements[1].(*Extended.Parser_Declaration).flags);
	assert((updated_statements[2].(*Extended.Parser_Declaration).flags & .IS_CONSTANT) != 0);
	assert(updated_statements[2].(*Extended.Parser_Declaration).flags == fresh_statements[2].(*Extended.Parser_Declaration).flags);
	assert(updated_use.resolved_declaration == updated_statements[2].(*Extended.Parser_Declaration));
	assert(fresh_use.resolved_declaration == fresh_statements[2].(*Extended.Parser_Declaration));
	assert(Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(updated_statements[2].(*Extended.Parser_Declaration).name == "missing");
	assert(updated_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Literal)._u64 == 2);
	assert(Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);

	changed := Extended.parse_file("a :: 1;");
	changed_result, changed_ok := Extended.parse_file_edit(*changed, 6, 6, "a :: 1+2;");
	assert(changed_ok && changed_result.status == .COMPLETE);
	assert(changed_result.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Declaration).expression.kind == .BINARY_OPERATOR);
	Extended.release_parser_tree(*changed);
	Extended.release_parser_names(*changed);
	Extended.release_parser_tree(*changed_result);
	Extended.release_parser_names(*changed_result);

	old_binding := Extended.parse_file("target :: 1; use := target;");
	assert(old_binding.root.(*Extended.Parser_Block).statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration != null);
	new_binding, binding_ok := Extended.parse_file_edit(*old_binding, 0, "target :: 1;".count, "other :: 1; use := target;");
	assert(binding_ok && new_binding.status == .COMPLETE);
	assert(new_binding.root.(*Extended.Parser_Block).statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == null);
	Extended.release_parser_tree(*old_binding);
	Extended.release_parser_names(*old_binding);
	Extended.release_parser_tree(*new_binding);
	Extended.release_parser_names(*new_binding);
	check_removed_binding_ast_reuse(			"use := target;", 0, "target :: 1; ".count);
	check_removed_binding_ast_reuse("other :: 1; use := target;", 0, "target".count);
}

check_removed_binding_ast_reuse :: (new_text: string, edit_start: s64, edit_end: s64) {
	old_source := copy_string("target :: 1; use := target;");
	new_source := copy_string(new_text);
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, edit_start, edit_end, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && updated.status == .COMPLETE && fresh.status == .COMPLETE);
	old_statements := old.root.(*Extended.Parser_Block).statements;
	assert(old_statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == old_statements[0].(*Extended.Parser_Declaration));

	statements := updated.root.(*Extended.Parser_Block).statements;
	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	use_statement := statements[statements.count - 1].(*Extended.Parser_Declaration);
	fresh_use := fresh_statements[fresh_statements.count - 1].(*Extended.Parser_Declaration);
	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, edit_start=edit_start, edit_end=edit_end, cursor=use_statement.first_token.(s64)};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root && probe_tokens.root.(*Extended.Parser_Declaration).name == "use");
	assert(probe.current_scope.references.count == 1);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);

	assert(use_statement.first_token == fresh_use.first_token && use_statement.one_past_last_token == fresh_use.one_past_last_token);
	use := use_statement.expression.(*Extended.Parser_Ident);
	assert(!use.resolved_declaration && !fresh_use.expression.(*Extended.Parser_Ident).resolved_declaration);
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(use.name == "target" && Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);
}

test_repeated_convergence_edit :: () {
	repeated_old_source := copy_string( "first :: 1; middle :: 1; last :: 1; use := last;");
	repeated_new_source := copy_string("first :: 11; middle :: 1; last :: 1; use := last;");
	repeated_edit := "first :: 1".count;
	repeated_old := Extended.parse_file(repeated_old_source);
	repeated_updated, repeated_ok := Extended.parse_file_edit(*repeated_old, repeated_edit, repeated_edit, repeated_new_source);
	repeated_fresh := Extended.parse_file(repeated_new_source);
	assert(repeated_ok && repeated_updated.status == .COMPLETE && repeated_fresh.status == .COMPLETE);
	repeated_statements := repeated_updated.root.(*Extended.Parser_Block).statements;
	repeated_fresh_statements := repeated_fresh.root.(*Extended.Parser_Block).statements;
	repeated_tokens := Extended.materialise_tokens(repeated_new_source);
	repeated_probe := Extended.Parser.{parsed=*repeated_tokens, edit_source=*repeated_old, edit_start=repeated_edit, edit_end=repeated_edit};
	set_allocators(*repeated_tokens.node_pool, context.default_allocator);
	repeated_probe.current_scope = Extended.push_lexical_scope(*repeated_probe);
	assert(Extended.reuse_simple_declaration(*repeated_probe) == null);
	repeated_probe.cursor = repeated_statements[1].first_token.(s64);
	repeated_tokens.root = Extended.reuse_simple_declaration(*repeated_probe);
	assert(repeated_tokens.root && repeated_tokens.root.(*Extended.Parser_Declaration).name == "middle");
	Extended.release_parser_tree(*repeated_tokens);
	Extended.release_parser_names(*repeated_tokens);
	for repeated_statements {
		other := repeated_fresh_statements[it_index];
		assert(it.kind == other.kind && it.first_token == other.first_token && it.one_past_last_token == other.one_past_last_token);
	}

	assert(repeated_statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == repeated_statements[2].(*Extended.Parser_Declaration));
	assert(repeated_fresh_statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == repeated_fresh_statements[2].(*Extended.Parser_Declaration));
	assert(repeated_updated.diagnostics.count == repeated_fresh.diagnostics.count && repeated_updated.restart_points.count == repeated_fresh.restart_points.count);
	Extended.release_parser_tree(*repeated_old);
	Extended.release_parser_names(*repeated_old);
	free(repeated_old_source);
	assert(Extended.reconstruct_source(*repeated_updated) == repeated_new_source);
	Extended.release_parser_tree(*repeated_updated);
	Extended.release_parser_names(*repeated_updated);
	Extended.release_parser_tree(*repeated_fresh);
	Extended.release_parser_names(*repeated_fresh);
	free(repeated_new_source);
}

test_new_recovered_edit_fallback :: () {
	old_source := copy_string("value := 1; keep := value;");
	new_source := copy_string("value := ; keep := value;");
	edit_start := "value := ".count;
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, edit_start, edit_start + 1, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && old.status == .COMPLETE && updated.status == fresh.status && updated.status != .COMPLETE);
	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, edit_start=edit_start, edit_end=edit_start + 1};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	assert(Extended.reuse_simple_declaration(*probe) == null);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.diagnostics.count > 0);
	assert(updated.recovery_records.count == fresh.recovery_records.count && updated.restart_points.count == fresh.restart_points.count);
	for updated.diagnostics {
		other := fresh.diagnostics[it_index];
		assert(it.kind == other.kind && it.message == other.message);
		assert(it.span.first == other.span.first && it.span.one_past_last == other.span.one_past_last);
		assert(it.lexer_line == other.lexer_line && it.lexer_column == other.lexer_column);
	}

	for updated.recovery_records {
		other := fresh.recovery_records[it_index];
		assert(it.kind == other.kind && it.span.first == other.span.first && it.span.one_past_last == other.span.one_past_last);
		assert(it.diagnostic_index == other.diagnostic_index && it.synthetic_token_index == other.synthetic_token_index);
	}

	assert(updated.tokens.count == fresh.tokens.count);
	for updated.tokens {
		other := fresh.tokens[it_index];
		assert(it.type == other.type && it.byte_start == other.byte_start && it.byte_end == other.byte_end);
	}

	assert(Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);

	lexer_old_source := copy_string("bad :: 1; stable :: 1;");
	lexer_new_source := copy_string("bad :: 18446744073709551616; stable :: 1;");
	lexer_start := "bad :: ".count;
	lexer_old := Extended.parse_file(lexer_old_source);
	lexer_updated, lexer_ok := Extended.parse_file_edit(*lexer_old, lexer_start, lexer_start + 1, lexer_new_source);
	lexer_fresh := Extended.parse_file(lexer_new_source);
	assert(lexer_ok && lexer_old.status == .COMPLETE && lexer_updated.status == .RECOVERED && lexer_fresh.status == .RECOVERED);
	assert(lexer_updated.diagnostics.count == lexer_fresh.diagnostics.count && lexer_updated.diagnostics[0].kind == .LEXER_ERROR);
	lexer_tokens := Extended.materialise_tokens(lexer_new_source);
	lexer_probe := Extended.Parser.{parsed=*lexer_tokens, edit_source=*lexer_old, edit_start=lexer_start, edit_end=lexer_start + 1};
	set_allocators(*lexer_tokens.node_pool, context.default_allocator);
	lexer_probe.current_scope = Extended.push_lexical_scope(*lexer_probe);
	assert(Extended.reuse_simple_declaration(*lexer_probe) == null);
	Extended.release_parser_tree(*lexer_tokens);
	Extended.release_parser_names(*lexer_tokens);
	assert(lexer_updated.recovery_records.count == lexer_fresh.recovery_records.count && lexer_updated.restart_points.count == lexer_fresh.restart_points.count);
	Extended.release_parser_tree(*lexer_old);
	Extended.release_parser_names(*lexer_old);
	free(lexer_old_source);
	assert(Extended.reconstruct_source(*lexer_updated) == lexer_new_source);
	Extended.release_parser_tree(*lexer_updated);
	Extended.release_parser_names(*lexer_updated);
	Extended.release_parser_tree(*lexer_fresh);
	Extended.release_parser_names(*lexer_fresh);
	free(lexer_new_source);
}

test_recovered_snapshot_ast_reuse_fallback :: () {
	parser_recovery_source := copy_string("broken: ; stable :: 1;");
	parser_repaired_source := copy_string("broken: s64; stable :: 1;");
	parser_recovery := Extended.parse_file(parser_recovery_source);
	parser_repaired, parser_repaired_ok := Extended.parse_file_edit(*parser_recovery, "broken: ".count, "broken: ".count, parser_repaired_source);
	parser_fresh := Extended.parse_file(parser_repaired_source);
	assert(parser_repaired_ok && parser_recovery.status != .COMPLETE && parser_repaired.status == .COMPLETE && parser_fresh.status == .COMPLETE);
	parser_probe_tokens := Extended.materialise_tokens(parser_repaired_source);
	parser_probe := Extended.Parser.{
		parsed=*parser_probe_tokens,
		edit_source=*parser_recovery,
		edit_start="broken: ".count,
		edit_end="broken: ".count,
		cursor=parser_repaired.root.(*Extended.Parser_Block).statements[1].first_token.(s64),
	};
	set_allocators(*parser_probe_tokens.node_pool, context.default_allocator);
	parser_probe.current_scope = Extended.push_lexical_scope(*parser_probe);
	assert(Extended.reuse_simple_declaration(*parser_probe) == null);
	Extended.release_parser_tree(*parser_probe_tokens);
	Extended.release_parser_names(*parser_probe_tokens);
	assert(parser_repaired.diagnostics.count == parser_fresh.diagnostics.count && parser_repaired.restart_points.count == parser_fresh.restart_points.count);
	Extended.release_parser_tree(*parser_recovery);
	Extended.release_parser_names(*parser_recovery);
	free(parser_recovery_source);
	assert(Extended.reconstruct_source(*parser_repaired) == parser_repaired_source);
	Extended.release_parser_tree(*parser_repaired);
	Extended.release_parser_names(*parser_repaired);
	Extended.release_parser_tree(*parser_fresh);
	Extended.release_parser_names(*parser_fresh);
	free(parser_repaired_source);

	old_source := copy_string("broken: ; stable :: 1;");
	new_source := copy_string("broken: ; stable :: 1; later := stable;");
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, old_source.count, old_source.count, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && old.status == .RECOVERED && updated.status == fresh.status);
	assert(old.diagnostics.count > 0 && updated.diagnostics.count == fresh.diagnostics.count);

	statements := updated.root.(*Extended.Parser_Block).statements;
	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	assert(statements.count == fresh_statements.count);
	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, edit_start=old_source.count, edit_end=old_source.count, cursor=statements[1].first_token.(s64)};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	assert(Extended.reuse_simple_declaration(*probe) == null);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);

	for statements {
		other := fresh_statements[it_index];
		assert(it.kind == other.kind && it.first_token == other.first_token && it.one_past_last_token == other.one_past_last_token);
	}

	assert(statements[1].(*Extended.Parser_Declaration).name == "stable");
	use := statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident);
	assert(use.resolved_declaration == statements[1].(*Extended.Parser_Declaration));
	assert(fresh_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[1].(*Extended.Parser_Declaration));
	assert(updated.restart_points.count == fresh.restart_points.count && updated.recovery_records.count == fresh.recovery_records.count);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(use.name == "stable" && Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);

	lexer_old_source := copy_string("bad :: 18446744073709551616; stable :: 1;");
	lexer_new_source := copy_string("bad :: 18446744073709551616; stable :: 1; later := stable;");
	lexer_old := Extended.parse_file(lexer_old_source);
	lexer_updated, lexer_ok := Extended.parse_file_edit(*lexer_old, lexer_old_source.count, lexer_old_source.count, lexer_new_source);
	lexer_fresh := Extended.parse_file(lexer_new_source);
	assert(lexer_ok && lexer_old.status == .RECOVERED && lexer_old.diagnostics[0].kind == .LEXER_ERROR);
	assert(lexer_updated.status == lexer_fresh.status && lexer_updated.diagnostics.count == lexer_fresh.diagnostics.count);
	lexer_statements := lexer_updated.root.(*Extended.Parser_Block).statements;
	lexer_fresh_statements := lexer_fresh.root.(*Extended.Parser_Block).statements;
	assert(lexer_statements.count == lexer_fresh_statements.count);
	lexer_probe_tokens := Extended.materialise_tokens(lexer_new_source);
	lexer_probe := Extended.Parser.{parsed=*lexer_probe_tokens, edit_source=*lexer_old, edit_start=lexer_old_source.count, edit_end=lexer_old_source.count, cursor=lexer_statements[1].first_token.(s64)};
	set_allocators(*lexer_probe_tokens.node_pool, context.default_allocator);
	lexer_probe.current_scope = Extended.push_lexical_scope(*lexer_probe);
	assert(Extended.reuse_simple_declaration(*lexer_probe) == null);
	Extended.release_parser_tree(*lexer_probe_tokens);
	Extended.release_parser_names(*lexer_probe_tokens);
	assert(lexer_statements[1].(*Extended.Parser_Declaration).name == "stable");
	assert(lexer_statements[1].first_token == lexer_fresh_statements[1].first_token);
	assert(lexer_statements[1].one_past_last_token == lexer_fresh_statements[1].one_past_last_token);
	lexer_use := lexer_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident);
	assert(lexer_use.resolved_declaration == lexer_statements[1].(*Extended.Parser_Declaration));
	assert(lexer_fresh_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == lexer_fresh_statements[1].(*Extended.Parser_Declaration));
	assert(lexer_updated.restart_points.count == lexer_fresh.restart_points.count && lexer_updated.recovery_records.count == lexer_fresh.recovery_records.count);
	Extended.release_parser_tree(*lexer_old);
	Extended.release_parser_names(*lexer_old);
	free(lexer_old_source);
	assert(lexer_use.name == "stable" && Extended.reconstruct_source(*lexer_updated) == lexer_new_source);
	Extended.release_parser_tree(*lexer_updated);
	Extended.release_parser_names(*lexer_updated);
	Extended.release_parser_tree(*lexer_fresh);
	Extended.release_parser_names(*lexer_fresh);
	free(lexer_new_source);
}

test_simple_candidate_syntax_edits :: () {
	check_simple_candidate_edit(
		"left :: 1; result := left + 2; keep := result;",
		"left :: 1; result := (left + 2); keep := result;",
		"left :: 1; result := ".count,
		"left :: 1; result := left + 2".count
	);
	check_simple_candidate_edit(
		"left :: 1; result := (left + 2); keep := result;",
		"left :: 1; result := left + 2; keep := result;",
		"left :: 1; result := ".count,
		"left :: 1; result := (left + 2)".count
	);
	check_simple_candidate_edit(
		"left :: 1; result := left + 2; keep := result;",
		"left :: 1; result := left + 3 + 2; keep := result;",
		"left :: 1; result := left + ".count,
		"left :: 1; result := left + ".count
	);
	check_simple_candidate_edit(
		"left :: 1; result := left + 2; keep := result;",
		"left :: 1; result := left - 2; keep := result;",
		"left :: 1; result := left ".count,
		"left :: 1; result := left +".count
	);
	check_simple_candidate_edit(
		"left :: 1; result := left + 2; keep := result;",
		"left :: 1; result := other + 2; keep := result;",
		"left :: 1; result := ".count,
		"left :: 1; result := left".count
	);
	check_simple_candidate_edit(
		"left :: 1; result: s64 = left; keep := result;",
		"left :: 1; result: u64 = left; keep := result;",
		"left :: 1; result: ".count,
		"left :: 1; result: s64".count
	);
	check_simple_candidate_edit(
		"left :: 1; result: [2]s64 = left; keep := result;",
		"left :: 1; result: s64 = left; keep := result;",
		"left :: 1; result: ".count,
		"left :: 1; result: [2]s64".count
	);
	check_simple_candidate_edit(
		"left :: 1; result: s64 = left; keep := result;",
		"left :: 1; result: [2]s64 = left; keep := result;",
		"left :: 1; result: ".count,
		"left :: 1; result: s64".count
	);
	check_simple_candidate_edit(
		"left :: 1; result := left + 2; keep := result;",
		"other :: 1; result := other + 2; keep := result;",
		0,
		"left :: 1; result := left + 2".count
	);
	check_nested_candidate_syntax_edit();
	check_semicolon_candidate_edit(
		"value := 1 + 2; keep := value;",
		"value := 1; + 2; keep := value;",
		"value := 1".count,
		"value := 1".count
	);
	check_semicolon_candidate_edit(
		"value := 1; keep := value;",
		"value := 1: keep := value;",
		"value := 1".count,
		"value := 1;".count
	);
}

check_semicolon_candidate_edit :: (before: string, after: string, edit_start: s64, edit_end: s64) {
	old_source := copy_string(before);
	new_source := copy_string(after);
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, edit_start, edit_end, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && old.status == .COMPLETE && updated.status == fresh.status);
	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, edit_start=edit_start, edit_end=edit_end};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	assert(Extended.reuse_simple_declaration(*probe) == null);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);
	statements := updated.root.(*Extended.Parser_Block).statements;
	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	assert(statements.count == fresh_statements.count);
	for statements {
		other := fresh_statements[it_index];
		assert(it.kind == other.kind && it.first_token == other.first_token && it.one_past_last_token == other.one_past_last_token);
	}

	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.recovery_records.count == fresh.recovery_records.count);
	assert(updated.restart_points.count == fresh.restart_points.count);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);
}

check_nested_candidate_syntax_edit :: () {
	old_source := copy_string("#if true { left :: 1; result := left + 2; keep := result; }");
	new_source := copy_string("#if true { left :: 1; result := (left + 2); keep := result; }");
	edit_start :=	"#if true { left :: 1; result := ".count;
	edit_end :=		"#if true { left :: 1; result := left + 2".count;
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, edit_start, edit_end, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE && fresh.status == .COMPLETE);
	old_block := old.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_If).then_block;
	block := updated.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_If).then_block;
	fresh_block := fresh.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_If).then_block;
	assert(block != old_block && block.statements.count == 3 && block.statements.count == fresh_block.statements.count);
	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, edit_start=edit_start, edit_end=edit_end, cursor=block.statements[1].first_token.(s64)};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.reuse_block = Extended.find_old_declaration_block(*probe, old.root_scope, block.first_token.(s64), .DATA_DECLARATIONS);
	assert(probe.reuse_block == old_block);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	assert(Extended.reuse_simple_declaration(*probe) == null);
	probe.cursor = block.statements[2].first_token.(s64);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root && probe_tokens.root.(*Extended.Parser_Declaration).name == "keep");
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);
	for block.statements {
		other := fresh_block.statements[it_index];
		assert(it.kind == other.kind && it.first_token == other.first_token && it.one_past_last_token == other.one_past_last_token);
	}

	use := block.statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident);
	assert(use.resolved_declaration == block.statements[1].(*Extended.Parser_Declaration));
	assert(fresh_block.statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == fresh_block.statements[1].(*Extended.Parser_Declaration));
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(use.name == "result" && Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);
}

check_simple_candidate_edit :: (before: string, after: string, edit_start: s64, edit_end: s64) {
	old_source := copy_string(before);
	new_source := copy_string(after);
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, edit_start, edit_end, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE && fresh.status == .COMPLETE);
	statements := updated.root.(*Extended.Parser_Block).statements;
	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	assert(statements.count == 3 && statements.count == fresh_statements.count);
	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, edit_start=edit_start, edit_end=edit_end, cursor=statements[1].first_token.(s64)};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	assert(Extended.reuse_simple_declaration(*probe) == null);
	probe.cursor = statements[2].first_token.(s64);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root && probe_tokens.root.(*Extended.Parser_Declaration).name == "keep");
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);
	for statements {
		other := fresh_statements[it_index];
		assert(it.kind == other.kind && it.first_token == other.first_token && it.one_past_last_token == other.one_past_last_token);
	}

	assert(statements[1].(*Extended.Parser_Declaration).expression.kind == fresh_statements[1].(*Extended.Parser_Declaration).expression.kind);
	use := statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident);
	assert(use.resolved_declaration == statements[1].(*Extended.Parser_Declaration));
	assert(fresh_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[1].(*Extended.Parser_Declaration));
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	assert(updated.recovery_records.count == fresh.recovery_records.count);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(use.name == "result" && Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);
}

test_semicolon_boundary_ast_reuse :: () {
	old_source := copy_string("value := 1;");
	new_source := copy_string("value := 1");
	edit_start := new_source.count;
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, edit_start, old_source.count, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && old.status == .COMPLETE && updated.status == fresh.status);
	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, edit_start=edit_start, edit_end=old_source.count};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	assert(Extended.reuse_simple_declaration(*probe) == null);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	assert(Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);

	trivia_old_source := copy_string("value := 1; keep := value;");
	trivia_new_source := copy_string("value := 1 /* note */; keep := value;");
	trivia_edit_start := "value := 1".count;
	trivia_old := Extended.parse_file(trivia_old_source);
	trivia_updated, trivia_ok := Extended.parse_file_edit(*trivia_old, trivia_edit_start, trivia_edit_start, trivia_new_source);
	trivia_fresh := Extended.parse_file(trivia_new_source);
	assert(trivia_ok && trivia_updated.status == .COMPLETE && trivia_fresh.status == .COMPLETE);
	trivia_probe_tokens := Extended.materialise_tokens(trivia_new_source);
	trivia_probe := Extended.Parser.{parsed=*trivia_probe_tokens, edit_source=*trivia_old, edit_start=trivia_edit_start, edit_end=trivia_edit_start};
	set_allocators(*trivia_probe_tokens.node_pool, context.default_allocator);
	trivia_probe.current_scope = Extended.push_lexical_scope(*trivia_probe);
	trivia_probe_tokens.root = Extended.reuse_simple_declaration(*trivia_probe);
	assert(trivia_probe_tokens.root && trivia_probe_tokens.root.(*Extended.Parser_Declaration).name == "value");
	Extended.release_parser_tree(*trivia_probe_tokens);
	Extended.release_parser_names(*trivia_probe_tokens);
	trivia_statements := trivia_updated.root.(*Extended.Parser_Block).statements;
	trivia_fresh_statements := trivia_fresh.root.(*Extended.Parser_Block).statements;
	assert(trivia_statements[0].first_token == trivia_fresh_statements[0].first_token);
	assert(trivia_statements[0].one_past_last_token == trivia_fresh_statements[0].one_past_last_token);
	assert(trivia_statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == trivia_statements[0].(*Extended.Parser_Declaration));
	assert(trivia_fresh_statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == trivia_fresh_statements[0].(*Extended.Parser_Declaration));
	assert(trivia_updated.diagnostics.count == trivia_fresh.diagnostics.count && trivia_updated.restart_points.count == trivia_fresh.restart_points.count);
	assert(Extended.reconstruct_source(*trivia_updated) == trivia_new_source);
	Extended.release_parser_tree(*trivia_old);
	Extended.release_parser_names(*trivia_old);
	free(trivia_old_source);
	assert(trivia_statements[0].(*Extended.Parser_Declaration).name == "value");
	Extended.release_parser_tree(*trivia_updated);
	Extended.release_parser_names(*trivia_updated);
	Extended.release_parser_tree(*trivia_fresh);
	Extended.release_parser_names(*trivia_fresh);
	free(trivia_new_source);
}

test_typed_declaration_ast_reuse :: () {
	old_source := copy_string(			   "use: Target = value; Target :: 1; value :: 2;");
	new_source := copy_string("added :: 0;\nuse: Target = value; Target :: 1; value :: 2;");
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && updated.status == .COMPLETE && fresh.status == .COMPLETE);

	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, cursor=updated.root.(*Extended.Parser_Block).statements[1].first_token.(s64)};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root && probe_tokens.root.(*Extended.Parser_Declaration).type_inst);
	assert(probe.current_scope.references.count == 2);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);

	statements := updated.root.(*Extended.Parser_Block).statements;
	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	declaration := statements[1].(*Extended.Parser_Declaration);
	fresh_declaration := fresh_statements[1].(*Extended.Parser_Declaration);
	assert(declaration.first_token == fresh_declaration.first_token && declaration.one_past_last_token == fresh_declaration.one_past_last_token);
	assert(declaration.type_inst.first_token == fresh_declaration.type_inst.first_token && declaration.type_inst.one_past_last_token == fresh_declaration.type_inst.one_past_last_token);
	type_name := declaration.type_inst.type_valued_expression.(*Extended.Parser_Ident);
	assert(type_name.resolved_declaration == statements[2].(*Extended.Parser_Declaration));
	assert(fresh_declaration.type_inst.type_valued_expression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[2].(*Extended.Parser_Declaration));
	value_name := declaration.expression.(*Extended.Parser_Ident);
	assert(value_name.resolved_declaration == statements[3].(*Extended.Parser_Declaration));
	assert(fresh_declaration.expression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[3].(*Extended.Parser_Declaration));
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	assert_eligible_edit_matches_fresh(*updated, *fresh);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(type_name.name == "Target" && value_name.name == "value" && Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);

	pointer_old_source := copy_string(			   "use: *Target = value; Target :: 1; value :: 2;");
	pointer_new_source := copy_string("added :: 0;\nuse: *Target = value; Target :: 1; value :: 2;");
	pointer_old := Extended.parse_file(pointer_old_source);
	pointer_updated, pointer_ok := Extended.parse_file_edit(*pointer_old, 0, 0, pointer_new_source);
	pointer_fresh := Extended.parse_file(pointer_new_source);
	assert(pointer_ok && pointer_updated.status == .COMPLETE && pointer_fresh.status == .COMPLETE);
	pointer_probe_tokens := Extended.materialise_tokens(pointer_new_source);
	pointer_probe := Extended.Parser.{parsed=*pointer_probe_tokens, edit_source=*pointer_old, cursor=pointer_updated.root.(*Extended.Parser_Block).statements[1].first_token.(s64)};
	set_allocators(*pointer_probe_tokens.node_pool, context.default_allocator);
	pointer_probe.current_scope = Extended.push_lexical_scope(*pointer_probe);
	pointer_probe_tokens.root = Extended.reuse_simple_declaration(*pointer_probe);
	assert(pointer_probe_tokens.root && pointer_probe.current_scope.references.count == 2);
	Extended.release_parser_tree(*pointer_probe_tokens);
	Extended.release_parser_names(*pointer_probe_tokens);

	pointer_statements := pointer_updated.root.(*Extended.Parser_Block).statements;
	pointer_fresh_statements := pointer_fresh.root.(*Extended.Parser_Block).statements;
	pointer_decl := pointer_statements[1].(*Extended.Parser_Declaration);
	pointer_fresh_decl := pointer_fresh_statements[1].(*Extended.Parser_Declaration);
	assert(pointer_decl.first_token == pointer_fresh_decl.first_token && pointer_decl.one_past_last_token == pointer_fresh_decl.one_past_last_token);
	assert(pointer_decl.type_inst.first_token == pointer_fresh_decl.type_inst.first_token && pointer_decl.type_inst.one_past_last_token == pointer_fresh_decl.type_inst.one_past_last_token);
	assert(
		pointer_decl.type_inst.pointer_to.first_token == pointer_fresh_decl.type_inst.pointer_to.first_token
		&& pointer_decl.type_inst.pointer_to.one_past_last_token == pointer_fresh_decl.type_inst.pointer_to.one_past_last_token
	);
	pointer_name := pointer_decl.type_inst.pointer_to.type_valued_expression.(*Extended.Parser_Ident);
	assert(pointer_name.resolved_declaration == pointer_statements[2].(*Extended.Parser_Declaration));
	assert(pointer_fresh_decl.type_inst.pointer_to.type_valued_expression.(*Extended.Parser_Ident).resolved_declaration == pointer_fresh_statements[2].(*Extended.Parser_Declaration));
	assert(pointer_decl.expression.(*Extended.Parser_Ident).resolved_declaration == pointer_statements[3].(*Extended.Parser_Declaration));
	assert(pointer_updated.diagnostics.count == pointer_fresh.diagnostics.count && pointer_updated.restart_points.count == pointer_fresh.restart_points.count);
	Extended.release_parser_tree(*pointer_old);
	Extended.release_parser_names(*pointer_old);
	free(pointer_old_source);
	assert(pointer_name.name == "Target" && Extended.reconstruct_source(*pointer_updated) == pointer_new_source);
	Extended.release_parser_tree(*pointer_updated);
	Extended.release_parser_names(*pointer_updated);
	Extended.release_parser_tree(*pointer_fresh);
	Extended.release_parser_names(*pointer_fresh);
	free(pointer_new_source);

	constant_old_source := copy_string(			    "Target :: s64; value :: 2; result: Target : value;");
	constant_new_source := copy_string("added :: 0;\nTarget :: s64; value :: 2; result: Target : value;");
	constant_old := Extended.parse_file(constant_old_source);
	constant_updated, constant_ok := Extended.parse_file_edit(*constant_old, 0, 0, constant_new_source);
	constant_fresh := Extended.parse_file(constant_new_source);
	assert(constant_ok && constant_old.status == .COMPLETE && constant_updated.status == .COMPLETE && constant_fresh.status == .COMPLETE);
	constant_statements := constant_updated.root.(*Extended.Parser_Block).statements;
	constant_fresh_statements := constant_fresh.root.(*Extended.Parser_Block).statements;
	constant_tokens := Extended.materialise_tokens(constant_new_source);
	constant_probe := Extended.Parser.{parsed=*constant_tokens, edit_source=*constant_old, cursor=constant_statements[3].first_token.(s64)};
	set_allocators(*constant_tokens.node_pool, context.default_allocator);
	constant_probe.current_scope = Extended.push_lexical_scope(*constant_probe);
	constant_tokens.root = Extended.reuse_simple_declaration(*constant_probe);
	assert(constant_tokens.root && constant_tokens.root.(*Extended.Parser_Declaration).flags & .IS_CONSTANT);
	assert(constant_probe.current_scope.references.count == 2);
	Extended.release_parser_tree(*constant_tokens);
	Extended.release_parser_names(*constant_tokens);
	constant_decl := constant_statements[3].(*Extended.Parser_Declaration);
	constant_fresh_decl := constant_fresh_statements[3].(*Extended.Parser_Declaration);
	assert(constant_decl.flags & .IS_CONSTANT && constant_decl.flags == constant_fresh_decl.flags);
	assert(constant_decl.first_token == constant_fresh_decl.first_token && constant_decl.one_past_last_token == constant_fresh_decl.one_past_last_token);
	assert(constant_decl.l0 == constant_fresh_decl.l0 && constant_decl.c0 == constant_fresh_decl.c0);
	assert(constant_decl.l1 == constant_fresh_decl.l1 && constant_decl.c1 == constant_fresh_decl.c1);
	assert(constant_decl.type_inst.first_token == constant_fresh_decl.type_inst.first_token && constant_decl.type_inst.one_past_last_token == constant_fresh_decl.type_inst.one_past_last_token);
	assert(constant_decl.expression.first_token == constant_fresh_decl.expression.first_token && constant_decl.expression.one_past_last_token == constant_fresh_decl.expression.one_past_last_token);
	constant_type := constant_decl.type_inst.type_valued_expression.(*Extended.Parser_Ident);
	constant_value := constant_decl.expression.(*Extended.Parser_Ident);
	assert(constant_type.resolved_declaration == constant_statements[1].(*Extended.Parser_Declaration));
	assert(constant_value.resolved_declaration == constant_statements[2].(*Extended.Parser_Declaration));
	assert(constant_fresh_decl.type_inst.type_valued_expression.(*Extended.Parser_Ident).resolved_declaration == constant_fresh_statements[1].(*Extended.Parser_Declaration));
	assert(constant_fresh_decl.expression.(*Extended.Parser_Ident).resolved_declaration == constant_fresh_statements[2].(*Extended.Parser_Declaration));
	assert(constant_updated.diagnostics.count == constant_fresh.diagnostics.count && constant_updated.restart_points.count == constant_fresh.restart_points.count);
	Extended.release_parser_tree(*constant_old);
	Extended.release_parser_names(*constant_old);
	free(constant_old_source);
	assert(constant_type.name == "Target" && constant_value.name == "value" && Extended.reconstruct_source(*constant_updated) == constant_new_source);
	Extended.release_parser_tree(*constant_updated);
	Extended.release_parser_names(*constant_updated);
	Extended.release_parser_tree(*constant_fresh);
	Extended.release_parser_names(*constant_fresh);
	free(constant_new_source);

	changed_old_source :=	copy_string("Target :: s64; value :: 2; result: Target : value;");
	changed_source :=		copy_string("Target :: s64; value :: 2; result: Target = value;");
	changed_old := Extended.parse_file(changed_old_source);
	separator_start := "Target :: s64; value :: 2; result: Target ".count;
	changed, changed_ok := Extended.parse_file_edit(*changed_old, separator_start, separator_start + 1, changed_source);
	changed_fresh := Extended.parse_file(changed_source);
	assert(changed_ok && changed.status == .COMPLETE && changed_fresh.status == .COMPLETE);
	changed_statements := changed.root.(*Extended.Parser_Block).statements;
	changed_fresh_statements := changed_fresh.root.(*Extended.Parser_Block).statements;
	changed_tokens := Extended.materialise_tokens(changed_source);
	changed_probe := Extended.Parser.{parsed=*changed_tokens, edit_source=*changed_old, edit_start=separator_start, edit_end=separator_start + 1, cursor=changed_statements[2].first_token.(s64)};
	set_allocators(*changed_tokens.node_pool, context.default_allocator);
	changed_probe.current_scope = Extended.push_lexical_scope(*changed_probe);
	assert(Extended.reuse_simple_declaration(*changed_probe) == null);
	Extended.release_parser_tree(*changed_tokens);
	Extended.release_parser_names(*changed_tokens);
	changed_decl := changed_statements[2].(*Extended.Parser_Declaration);
	changed_fresh_decl := changed_fresh_statements[2].(*Extended.Parser_Declaration);
	assert(!(changed_decl.flags & .IS_CONSTANT) && changed_decl.flags == changed_fresh_decl.flags);
	assert(changed_decl.first_token == changed_fresh_decl.first_token && changed_decl.one_past_last_token == changed_fresh_decl.one_past_last_token);
	assert(changed_decl.type_inst.type_valued_expression.(*Extended.Parser_Ident).resolved_declaration == changed_statements[0].(*Extended.Parser_Declaration));
	assert(changed_decl.expression.(*Extended.Parser_Ident).resolved_declaration == changed_statements[1].(*Extended.Parser_Declaration));
	assert(changed_fresh_decl.type_inst.type_valued_expression.(*Extended.Parser_Ident).resolved_declaration == changed_fresh_statements[0].(*Extended.Parser_Declaration));
	assert(changed_fresh_decl.expression.(*Extended.Parser_Ident).resolved_declaration == changed_fresh_statements[1].(*Extended.Parser_Declaration));
	assert(changed.diagnostics.count == changed_fresh.diagnostics.count && changed.restart_points.count == changed_fresh.restart_points.count);
	Extended.release_parser_tree(*changed_old);
	Extended.release_parser_names(*changed_old);
	free(changed_old_source);
	assert(Extended.reconstruct_source(*changed) == changed_source);
	Extended.release_parser_tree(*changed);
	Extended.release_parser_names(*changed);
	Extended.release_parser_tree(*changed_fresh);
	Extended.release_parser_names(*changed_fresh);
	free(changed_source);
}

test_nested_type_instantiation_reuse :: () {
	old_source := copy_string(			   "value: *[size + 1][..]Target; keep := value; size :: 4; Target :: s64;");
	new_source := copy_string("added :: 0;\nvalue: *[size + 1][..]Target; keep := value; size :: 4; Target :: s64;");
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE && fresh.status == .COMPLETE);
	statements := updated.root.(*Extended.Parser_Block).statements;
	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, cursor=statements[1].first_token.(s64)};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root != null && probe.current_scope.references.count == 2);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);
	old_type := old.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Declaration).type_inst;
	type_inst := statements[1].(*Extended.Parser_Declaration).type_inst;
	fresh_type := fresh_statements[1].(*Extended.Parser_Declaration).type_inst;
	assert(type_inst.kind == fresh_type.kind && type_inst.node_flags == fresh_type.node_flags && type_inst.inst_flags == fresh_type.inst_flags);
	assert(type_inst != old_type && type_inst.first_token == fresh_type.first_token && type_inst.one_past_last_token == fresh_type.one_past_last_token);
	assert(type_inst.l0 == fresh_type.l0 && type_inst.c0 == fresh_type.c0 && type_inst.l1 == fresh_type.l1 && type_inst.c1 == fresh_type.c1);
	array := type_inst.pointer_to;
	fresh_array := fresh_type.pointer_to;
	assert(array.kind == fresh_array.kind && array.node_flags == fresh_array.node_flags);
	assert(array != old_type.pointer_to && array.first_token == fresh_array.first_token && array.one_past_last_token == fresh_array.one_past_last_token);
	assert(array.inst_flags == 0 && array.inst_flags == fresh_array.inst_flags);
	assert(array.l0 == fresh_array.l0 && array.c0 == fresh_array.c0 && array.l1 == fresh_array.l1 && array.c1 == fresh_array.c1);
	dimension := array.array_dimension.(*Extended.Parser_Binary_Operator);
	fresh_dimension := fresh_array.array_dimension.(*Extended.Parser_Binary_Operator);
	assert(dimension.kind == fresh_dimension.kind && dimension.node_flags == fresh_dimension.node_flags && dimension.flags == fresh_dimension.flags);
	assert(dimension.operator_type == #char "+" && dimension.operator_type == fresh_dimension.operator_type);
	assert(dimension.first_token == fresh_dimension.first_token && dimension.one_past_last_token == fresh_dimension.one_past_last_token);
	assert(dimension.l0 == fresh_dimension.l0 && dimension.c0 == fresh_dimension.c0 && dimension.l1 == fresh_dimension.l1 && dimension.c1 == fresh_dimension.c1);
	assert(dimension.left.(*Extended.Parser_Ident).resolved_declaration == statements[3].(*Extended.Parser_Declaration));
	assert(fresh_dimension.left.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[3].(*Extended.Parser_Declaration));
	view := array.array_element_type;
	fresh_view := fresh_array.array_element_type;
	assert(view.kind == fresh_view.kind && view.node_flags == fresh_view.node_flags);
	assert(view != old_type.pointer_to.array_element_type && view.inst_flags == .RESIZABLE && view.inst_flags == fresh_view.inst_flags);
	assert(view.first_token == fresh_view.first_token && view.one_past_last_token == fresh_view.one_past_last_token);
	assert(view.l0 == fresh_view.l0 && view.c0 == fresh_view.c0 && view.l1 == fresh_view.l1 && view.c1 == fresh_view.c1);
	name := view.array_element_type.type_valued_expression.(*Extended.Parser_Ident);
	fresh_name := fresh_view.array_element_type.type_valued_expression.(*Extended.Parser_Ident);
	assert(name.kind == fresh_name.kind && name.node_flags == fresh_name.node_flags && name.flags == fresh_name.flags);
	assert(name.first_token == fresh_name.first_token && name.one_past_last_token == fresh_name.one_past_last_token);
	assert(name.l0 == fresh_name.l0 && name.c0 == fresh_name.c0 && name.l1 == fresh_name.l1 && name.c1 == fresh_name.c1);
	assert(name.resolved_declaration == statements[4].(*Extended.Parser_Declaration));
	assert(fresh_view.array_element_type.type_valued_expression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[4].(*Extended.Parser_Declaration));
	assert(statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == statements[1].(*Extended.Parser_Declaration));
	assert(updated.tokens.count == fresh.tokens.count);
	for updated.tokens {
		other := fresh.tokens[it_index];
		assert(it.type == other.type && it.value_flags == other.value_flags);
		assert(it.byte_start == other.byte_start && it.byte_end == other.byte_end && it.preceding_trivia_byte_start == other.preceding_trivia_byte_start);
		assert(it.l0 == other.l0 && it.c0 == other.c0 && it.l1 == other.l1 && it.c1 == other.c1);
		assert(it.original_text == other.original_text && it.preceding_trivia == other.preceding_trivia && it.trailing_trivia == other.trailing_trivia);
	}

	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.recovery_records.count == fresh.recovery_records.count);
	assert(updated.restart_points.count == fresh.restart_points.count);
	for updated.restart_points {
		other := fresh.restart_points[it_index];
		assert(it.kind == other.kind && it.span.first == other.span.first && it.span.one_past_last == other.span.one_past_last);
	}

	changed_source := copy_string("value: *[size + 2][..]Target; keep := value; size :: 4; Target :: s64;");
	dimension_start := "value: *[size + ".count;
	changed, changed_ok := Extended.parse_file_edit(*old, dimension_start, dimension_start + 1, changed_source);
	changed_fresh := Extended.parse_file(changed_source);
	assert(changed_ok && changed.status == .COMPLETE && changed_fresh.status == .COMPLETE);
	changed_statements := changed.root.(*Extended.Parser_Block).statements;
	changed_fresh_statements := changed_fresh.root.(*Extended.Parser_Block).statements;
	changed_tokens := Extended.materialise_tokens(changed_source);
	changed_probe := Extended.Parser.{parsed=*changed_tokens, edit_source=*old, edit_start=dimension_start, edit_end=dimension_start + 1, cursor=changed_statements[0].first_token.(s64)};
	set_allocators(*changed_tokens.node_pool, context.default_allocator);
	changed_probe.current_scope = Extended.push_lexical_scope(*changed_probe);
	assert(Extended.reuse_simple_declaration(*changed_probe) == null);
	changed_probe.cursor = changed_statements[1].first_token.(s64);
	changed_tokens.root = Extended.reuse_simple_declaration(*changed_probe);
	assert(changed_tokens.root != null);
	Extended.release_parser_tree(*changed_tokens);
	Extended.release_parser_names(*changed_tokens);
	changed_type := changed_statements[0].(*Extended.Parser_Declaration).type_inst;
	changed_fresh_type := changed_fresh_statements[0].(*Extended.Parser_Declaration).type_inst;
	assert(changed_type.first_token == changed_fresh_type.first_token && changed_type.one_past_last_token == changed_fresh_type.one_past_last_token);
	assert(changed_type.pointer_to.array_dimension.(*Extended.Parser_Binary_Operator).right.(*Extended.Parser_Literal)._u64 == 2);
	assert(changed_type.pointer_to.array_dimension.(*Extended.Parser_Binary_Operator).left.(*Extended.Parser_Ident).resolved_declaration == changed_statements[2].(*Extended.Parser_Declaration));
	assert(changed_fresh_type.pointer_to.array_dimension.(*Extended.Parser_Binary_Operator).left.(*Extended.Parser_Ident).resolved_declaration == changed_fresh_statements[2].(*Extended.Parser_Declaration));
	assert(changed_type.pointer_to.array_element_type.array_element_type.type_valued_expression.(*Extended.Parser_Ident).resolved_declaration == changed_statements[3].(*Extended.Parser_Declaration));
	assert(changed_statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == changed_statements[0].(*Extended.Parser_Declaration));
	assert(changed.diagnostics.count == changed_fresh.diagnostics.count && changed.restart_points.count == changed_fresh.restart_points.count);
	assert(Extended.reconstruct_source(*changed) == changed_source);
	Extended.release_parser_tree(*changed);
	Extended.release_parser_names(*changed);
	Extended.release_parser_tree(*changed_fresh);
	Extended.release_parser_names(*changed_fresh);
	free(changed_source);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	for updated.tokens {
		other := fresh.tokens[it_index];
		assert(it.original_text == other.original_text && it.preceding_trivia == other.preceding_trivia && it.trailing_trivia == other.trailing_trivia);
	}

	assert(name.name == "Target" && Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);
}

test_type_instantiation_fallback :: () {
	check_excluded_type_instantiation("(Target) -> Target");
	check_excluded_type_instantiation("$T");
	check_excluded_type_instantiation("$T / interface Target");
	check_excluded_type_instantiation("#type Target");
	check_excluded_type_instantiation("#type,distinct Target");
	check_excluded_type_instantiation("#type,isa Target");
	check_excluded_type_instantiation("..Target");
	check_excluded_type_instantiation("Target.field");
	check_excluded_type_instantiation("Target(size)");
	check_excluded_type_instantiation("[#run 4]Target");
	check_excluded_type_instantiation("[null]Target");
	check_excluded_expression_node("#type,distinct Target", .TYPE_INSTANTIATION);
}

check_excluded_type_instantiation :: (type_source: string) {
	old_source := copy_string(tprint(			  "Target :: s64; size :: 4; value: %; keep := value;", type_source));
	new_source := copy_string(tprint("added :: 0;\nTarget :: s64; size :: 4; value: %; keep := value;", type_source));
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE && fresh.status == .COMPLETE, "%", type_source);
	old_type := old.root.(*Extended.Parser_Block).statements[2].(*Extended.Parser_Declaration).type_inst;
	assert(old_type && !Extended.reusable_type_instantiation(old_type), "%", type_source);
	statements := updated.root.(*Extended.Parser_Block).statements;
	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, cursor=statements[3].first_token.(s64)};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	assert(Extended.reuse_simple_declaration(*probe) == null);
	probe.cursor = statements[4].first_token.(s64);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root != null);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);
	type_inst := statements[3].(*Extended.Parser_Declaration).type_inst;
	fresh_type := fresh_statements[3].(*Extended.Parser_Declaration).type_inst;
	assert(type_inst && type_inst.kind == .TYPE_INSTANTIATION && type_inst.inst_flags == fresh_type.inst_flags);
	assert(type_inst.node_flags == fresh_type.node_flags);
	assert(type_inst.first_token == fresh_type.first_token && type_inst.one_past_last_token == fresh_type.one_past_last_token);
	assert(type_inst.l0 == fresh_type.l0 && type_inst.c0 == fresh_type.c0 && type_inst.l1 == fresh_type.l1 && type_inst.c1 == fresh_type.c1);
	assert((type_inst.pointer_to == null) == (fresh_type.pointer_to == null));
	assert((type_inst.array_element_type == null) == (fresh_type.array_element_type == null));
	assert((type_inst.type_valued_expression == null) == (fresh_type.type_valued_expression == null));
	assert((type_inst.type_directive_target == null) == (fresh_type.type_directive_target == null));
	if type_inst.type_valued_expression {
		assert(type_inst.type_valued_expression.kind == fresh_type.type_valued_expression.kind);
		assert(type_inst.type_valued_expression.first_token == fresh_type.type_valued_expression.first_token);
		if starts_with(type_source, "Target.") {
			member := type_inst.type_valued_expression.(*Extended.Parser_Binary_Operator);
			fresh_member := fresh_type.type_valued_expression.(*Extended.Parser_Binary_Operator);
			assert(member.left.(*Extended.Parser_Ident).resolved_declaration == statements[1].(*Extended.Parser_Declaration));
			assert(fresh_member.left.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[1].(*Extended.Parser_Declaration));
			assert(member.right.(*Extended.Parser_Ident).resolved_declaration == null && fresh_member.right.(*Extended.Parser_Ident).resolved_declaration == null);
		} else if starts_with(type_source, "Target(") {
			call := type_inst.type_valued_expression.(*Extended.Parser_Procedure_Call);
			fresh_call := fresh_type.type_valued_expression.(*Extended.Parser_Procedure_Call);
			assert(call.procedure_expression.(*Extended.Parser_Ident).resolved_declaration == statements[1].(*Extended.Parser_Declaration));
			assert(fresh_call.procedure_expression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[1].(*Extended.Parser_Declaration));
			assert(call.arguments_unsorted[0].expression.(*Extended.Parser_Ident).resolved_declaration == statements[2].(*Extended.Parser_Declaration));
			assert(fresh_call.arguments_unsorted[0].expression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[2].(*Extended.Parser_Declaration));
		} else if starts_with(type_source, "$") {
			assert((type_inst.type_valued_expression.(*Extended.Parser_Ident).flags & .DEFINES_POLYMORPH_VARIABLE) != 0);
			assert(type_inst.type_valued_expression.(*Extended.Parser_Ident).flags == fresh_type.type_valued_expression.(*Extended.Parser_Ident).flags);
		}
	}

	if type_inst.array_element_type {
		assert(type_inst.array_element_type.first_token == fresh_type.array_element_type.first_token);
		assert(type_inst.array_element_type.one_past_last_token == fresh_type.array_element_type.one_past_last_token);
		assert(type_inst.array_element_type.type_valued_expression.(*Extended.Parser_Ident).resolved_declaration == statements[1].(*Extended.Parser_Declaration));
		assert(fresh_type.array_element_type.type_valued_expression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[1].(*Extended.Parser_Declaration));
	}

	if type_inst.array_dimension {
		assert(type_inst.array_dimension.kind == fresh_type.array_dimension.kind);
		assert(type_inst.array_dimension.first_token == fresh_type.array_dimension.first_token && type_inst.array_dimension.one_past_last_token == fresh_type.array_dimension.one_past_last_token);
	}

	if type_inst.type_directive_target {
		assert(type_inst.type_directive_target.first_token == fresh_type.type_directive_target.first_token);
		assert(type_inst.type_directive_target.type_valued_expression.(*Extended.Parser_Ident).resolved_declaration == statements[1].(*Extended.Parser_Declaration));
		assert(fresh_type.type_directive_target.type_valued_expression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[1].(*Extended.Parser_Declaration));
	}

	if type_inst.must_implement {
		assert(type_inst.must_implement.kind == fresh_type.must_implement.kind);
		assert(type_inst.must_implement.(*Extended.Parser_Ident).resolved_declaration == statements[1].(*Extended.Parser_Declaration));
		assert(fresh_type.must_implement.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[1].(*Extended.Parser_Declaration));
	}

	assert(statements[4].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == statements[3].(*Extended.Parser_Declaration));
	assert(fresh_statements[4].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[3].(*Extended.Parser_Declaration));
	assert(updated.tokens.count == fresh.tokens.count);
	for updated.tokens {
		other := fresh.tokens[it_index];
		assert(it.type == other.type && it.value_flags == other.value_flags);
		assert(it.byte_start == other.byte_start && it.byte_end == other.byte_end && it.preceding_trivia_byte_start == other.preceding_trivia_byte_start);
		assert(it.l0 == other.l0 && it.c0 == other.c0 && it.l1 == other.l1 && it.c1 == other.c1);
		assert(it.original_text == other.original_text && it.preceding_trivia == other.preceding_trivia && it.trailing_trivia == other.trailing_trivia);
	}

	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.recovery_records.count == fresh.recovery_records.count);
	assert(updated.restart_points.count == fresh.restart_points.count);
	for updated.diagnostics {
		other := fresh.diagnostics[it_index];
		assert(it.kind == other.kind && it.message == other.message);
		assert(it.span.first == other.span.first && it.span.one_past_last == other.span.one_past_last);
		assert(it.lexer_line == other.lexer_line && it.lexer_column == other.lexer_column);
	}

	for updated.recovery_records {
		other := fresh.recovery_records[it_index];
		assert(it.kind == other.kind && it.span.first == other.span.first && it.span.one_past_last == other.span.one_past_last);
		assert(it.diagnostic_index == other.diagnostic_index && it.synthetic_token_index == other.synthetic_token_index);
	}

	for updated.restart_points {
		other := fresh.restart_points[it_index];
		assert(it.kind == other.kind && it.span.first == other.span.first && it.span.one_past_last == other.span.one_past_last);
	}

	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);
}

test_array_view_declaration_ast_reuse :: () {
	old_source := copy_string(			   "use: []Target = value; Target :: 1; value :: 2;");
	new_source := copy_string("added :: 0;\nuse: []Target = value; Target :: 1; value :: 2;");
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE && fresh.status == .COMPLETE);
	statements := updated.root.(*Extended.Parser_Block).statements;
	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, cursor=statements[1].first_token.(s64)};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root && probe.current_scope.references.count == 2);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);
	declaration := statements[1].(*Extended.Parser_Declaration);
	fresh_declaration := fresh_statements[1].(*Extended.Parser_Declaration);
	assert(declaration.first_token == fresh_declaration.first_token && declaration.one_past_last_token == fresh_declaration.one_past_last_token);
	view := declaration.type_inst;
	fresh_view := fresh_declaration.type_inst;
	assert(view.node_flags == fresh_view.node_flags);
	assert(view.inst_flags == .ARRAY_VIEW && view.inst_flags == fresh_view.inst_flags && !view.array_dimension);
	assert(view.first_token == fresh_view.first_token && view.one_past_last_token == fresh_view.one_past_last_token);
	assert(view.l0 == fresh_view.l0 && view.c0 == fresh_view.c0 && view.l1 == fresh_view.l1 && view.c1 == fresh_view.c1);
	assert(view.array_element_type.first_token == fresh_view.array_element_type.first_token && view.array_element_type.one_past_last_token == fresh_view.array_element_type.one_past_last_token);
	type_name := view.array_element_type.type_valued_expression.(*Extended.Parser_Ident);
	assert(type_name.resolved_declaration == statements[2].(*Extended.Parser_Declaration));
	assert(fresh_view.array_element_type.type_valued_expression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[2].(*Extended.Parser_Declaration));
	assert(declaration.expression.(*Extended.Parser_Ident).resolved_declaration == statements[3].(*Extended.Parser_Declaration));
	assert(fresh_declaration.expression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[3].(*Extended.Parser_Declaration));
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	assert_eligible_edit_matches_fresh(*updated, *fresh);

	changed_source := copy_string("use: [..]Target = value; Target :: 1; value :: 2;");
	insert_at := "use: [".count;
	changed, changed_ok := Extended.parse_file_edit(*old, insert_at, insert_at, changed_source);
	changed_fresh := Extended.parse_file(changed_source);
	assert(changed_ok && changed.status == .COMPLETE && changed_fresh.status == .COMPLETE);
	changed_tokens := Extended.materialise_tokens(changed_source);
	changed_probe := Extended.Parser.{parsed=*changed_tokens, edit_source=*old, edit_start=insert_at, edit_end=insert_at, cursor=0};
	set_allocators(*changed_tokens.node_pool, context.default_allocator);
	changed_probe.current_scope = Extended.push_lexical_scope(*changed_probe);
	assert(Extended.reuse_simple_declaration(*changed_probe) == null);
	Extended.release_parser_tree(*changed_tokens);
	Extended.release_parser_names(*changed_tokens);
	changed_statements := changed.root.(*Extended.Parser_Block).statements;
	changed_fresh_statements := changed_fresh.root.(*Extended.Parser_Block).statements;
	changed_view := changed_statements[0].(*Extended.Parser_Declaration).type_inst;
	changed_fresh_view := changed_fresh_statements[0].(*Extended.Parser_Declaration).type_inst;
	assert(changed_view.inst_flags == changed_fresh_view.inst_flags && (changed_view.inst_flags & .RESIZABLE) != 0);
	assert(changed_view.first_token == changed_fresh_view.first_token && changed_view.one_past_last_token == changed_fresh_view.one_past_last_token);
	assert(changed_view.array_element_type.type_valued_expression.(*Extended.Parser_Ident).resolved_declaration == changed_statements[1].(*Extended.Parser_Declaration));
	assert(changed.diagnostics.count == changed_fresh.diagnostics.count && changed.restart_points.count == changed_fresh.restart_points.count);
	assert(Extended.reconstruct_source(*changed) == changed_source);
	Extended.release_parser_tree(*changed);
	Extended.release_parser_names(*changed);
	Extended.release_parser_tree(*changed_fresh);
	Extended.release_parser_names(*changed_fresh);
	free(changed_source);

	resizable_old_source := copy_string(			 "use: [..]Target = value; Target :: 1; value :: 2;");
	resizable_new_source := copy_string("added :: 0;\nuse: [..]Target = value; Target :: 1; value :: 2;");
	resizable_old := Extended.parse_file(resizable_old_source);
	resizable_updated, resizable_ok := Extended.parse_file_edit(*resizable_old, 0, 0, resizable_new_source);
	resizable_fresh := Extended.parse_file(resizable_new_source);
	assert(resizable_ok && resizable_old.status == .COMPLETE && resizable_updated.status == .COMPLETE && resizable_fresh.status == .COMPLETE);
	resizable_statements := resizable_updated.root.(*Extended.Parser_Block).statements;
	resizable_fresh_statements := resizable_fresh.root.(*Extended.Parser_Block).statements;
	resizable_probe_tokens := Extended.materialise_tokens(resizable_new_source);
	resizable_probe := Extended.Parser.{parsed=*resizable_probe_tokens, edit_source=*resizable_old, cursor=resizable_statements[1].first_token.(s64)};
	set_allocators(*resizable_probe_tokens.node_pool, context.default_allocator);
	resizable_probe.current_scope = Extended.push_lexical_scope(*resizable_probe);
	resizable_probe_tokens.root = Extended.reuse_simple_declaration(*resizable_probe);
	assert(resizable_probe_tokens.root && resizable_probe.current_scope.references.count == 2);
	Extended.release_parser_tree(*resizable_probe_tokens);
	Extended.release_parser_names(*resizable_probe_tokens);
	resizable_declaration := resizable_statements[1].(*Extended.Parser_Declaration);
	resizable_fresh_declaration := resizable_fresh_statements[1].(*Extended.Parser_Declaration);
	resizable_type := resizable_declaration.type_inst;
	resizable_fresh_type := resizable_fresh_declaration.type_inst;
	assert(resizable_type.node_flags == resizable_fresh_type.node_flags);
	assert(resizable_type.inst_flags == .RESIZABLE && resizable_type.inst_flags == resizable_fresh_type.inst_flags && !resizable_type.array_dimension);
	assert(resizable_type.first_token == resizable_fresh_type.first_token && resizable_type.one_past_last_token == resizable_fresh_type.one_past_last_token);
	assert(resizable_type.l0 == resizable_fresh_type.l0 && resizable_type.c0 == resizable_fresh_type.c0);
	assert(resizable_type.l1 == resizable_fresh_type.l1 && resizable_type.c1 == resizable_fresh_type.c1);
	assert(
		resizable_type.array_element_type.first_token == resizable_fresh_type.array_element_type.first_token
		&& resizable_type.array_element_type.one_past_last_token == resizable_fresh_type.array_element_type.one_past_last_token
	);
	resizable_name := resizable_type.array_element_type.type_valued_expression.(*Extended.Parser_Ident);
	assert(resizable_name.resolved_declaration == resizable_statements[2].(*Extended.Parser_Declaration));
	assert(resizable_fresh_type.array_element_type.type_valued_expression.(*Extended.Parser_Ident).resolved_declaration == resizable_fresh_statements[2].(*Extended.Parser_Declaration));
	assert(resizable_declaration.expression.(*Extended.Parser_Ident).resolved_declaration == resizable_statements[3].(*Extended.Parser_Declaration));
	assert(resizable_fresh_declaration.expression.(*Extended.Parser_Ident).resolved_declaration == resizable_fresh_statements[3].(*Extended.Parser_Declaration));
	assert(resizable_updated.diagnostics.count == resizable_fresh.diagnostics.count && resizable_updated.restart_points.count == resizable_fresh.restart_points.count);
	assert_eligible_edit_matches_fresh(*resizable_updated, *resizable_fresh);
	Extended.release_parser_tree(*resizable_old);
	Extended.release_parser_names(*resizable_old);
	free(resizable_old_source);
	assert(resizable_name.name == "Target" && Extended.reconstruct_source(*resizable_updated) == resizable_new_source);
	Extended.release_parser_tree(*resizable_updated);
	Extended.release_parser_names(*resizable_updated);
	Extended.release_parser_tree(*resizable_fresh);
	Extended.release_parser_names(*resizable_fresh);
	free(resizable_new_source);

	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(type_name.name == "Target" && Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);
}

test_fixed_array_declaration_ast_reuse :: () {
	old_source := copy_string(			   "use: [size]Target = value; size :: 4; Target :: 1; value :: 2;");
	new_source := copy_string("added :: 0;\nuse: [size]Target = value; size :: 4; Target :: 1; value :: 2;");
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE && fresh.status == .COMPLETE);
	statements := updated.root.(*Extended.Parser_Block).statements;
	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, cursor=statements[1].first_token.(s64)};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root && probe.current_scope.references.count == 3);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);
	declaration := statements[1].(*Extended.Parser_Declaration);
	fresh_declaration := fresh_statements[1].(*Extended.Parser_Declaration);
	assert(declaration.type_inst.node_flags == fresh_declaration.type_inst.node_flags);
	assert(declaration.first_token == fresh_declaration.first_token && declaration.one_past_last_token == fresh_declaration.one_past_last_token);
	array_type := declaration.type_inst;
	fresh_array_type := fresh_declaration.type_inst;
	assert(array_type.node_flags == fresh_array_type.node_flags);
	assert(array_type.inst_flags == 0 && array_type.inst_flags == fresh_array_type.inst_flags);
	assert(array_type.first_token == fresh_array_type.first_token && array_type.one_past_last_token == fresh_array_type.one_past_last_token);
	assert(array_type.l0 == fresh_array_type.l0 && array_type.c0 == fresh_array_type.c0 && array_type.l1 == fresh_array_type.l1 && array_type.c1 == fresh_array_type.c1);
	assert(array_type.array_element_type.first_token == fresh_array_type.array_element_type.first_token && array_type.array_element_type.one_past_last_token == fresh_array_type.array_element_type.one_past_last_token);
	dimension := array_type.array_dimension.(*Extended.Parser_Ident);
	assert(dimension.first_token == fresh_array_type.array_dimension.first_token && dimension.one_past_last_token == fresh_array_type.array_dimension.one_past_last_token);
	assert(dimension.resolved_declaration == statements[2].(*Extended.Parser_Declaration));
	assert(fresh_array_type.array_dimension.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[2].(*Extended.Parser_Declaration));
	type_name := array_type.array_element_type.type_valued_expression.(*Extended.Parser_Ident);
	assert(type_name.resolved_declaration == statements[3].(*Extended.Parser_Declaration));
	assert(fresh_array_type.array_element_type.type_valued_expression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[3].(*Extended.Parser_Declaration));
	assert(declaration.expression.(*Extended.Parser_Ident).resolved_declaration == statements[4].(*Extended.Parser_Declaration));
	assert(fresh_declaration.expression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[4].(*Extended.Parser_Declaration));
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	assert_eligible_edit_matches_fresh(*updated, *fresh);

	changed_source := copy_string("use: [4]Target = value; size :: 4; Target :: 1; value :: 2;");
	dimension_start := "use: [".count;
	changed, changed_ok := Extended.parse_file_edit(*old, dimension_start, dimension_start + "size".count, changed_source);
	changed_fresh := Extended.parse_file(changed_source);
	assert(changed_ok && changed.status == .COMPLETE && changed_fresh.status == .COMPLETE);
	changed_tokens := Extended.materialise_tokens(changed_source);
	changed_probe := Extended.Parser.{parsed=*changed_tokens, edit_source=*old, edit_start=dimension_start, edit_end=dimension_start + "size".count, cursor=0};
	set_allocators(*changed_tokens.node_pool, context.default_allocator);
	changed_probe.current_scope = Extended.push_lexical_scope(*changed_probe);
	assert(Extended.reuse_simple_declaration(*changed_probe) == null);
	Extended.release_parser_tree(*changed_tokens);
	Extended.release_parser_names(*changed_tokens);
	changed_type := changed.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Declaration).type_inst;
	changed_fresh_type := changed_fresh.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Declaration).type_inst;
	assert(changed_type.first_token == changed_fresh_type.first_token && changed_type.one_past_last_token == changed_fresh_type.one_past_last_token);
	assert(changed_type.array_dimension.(*Extended.Parser_Literal)._u64 == changed_fresh_type.array_dimension.(*Extended.Parser_Literal)._u64);
	assert(changed_type.array_element_type.type_valued_expression.(*Extended.Parser_Ident).resolved_declaration == changed.root.(*Extended.Parser_Block).statements[2].(*Extended.Parser_Declaration));
	assert(changed.diagnostics.count == changed_fresh.diagnostics.count && changed.restart_points.count == changed_fresh.restart_points.count);
	assert(Extended.reconstruct_source(*changed) == changed_source);
	Extended.release_parser_tree(*changed);
	Extended.release_parser_names(*changed);
	Extended.release_parser_tree(*changed_fresh);
	Extended.release_parser_names(*changed_fresh);
	free(changed_source);

	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(dimension.name == "size" && type_name.name == "Target" && Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);
}

test_double_pointer_declaration_ast_reuse :: () {
	old_source := copy_string(			   "use: **Target = value; Target :: 1; value :: 2;");
	new_source := copy_string("added :: 0;\nuse: **Target = value; Target :: 1; value :: 2;");
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE && fresh.status == .COMPLETE);
	statements := updated.root.(*Extended.Parser_Block).statements;
	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, cursor=statements[1].first_token.(s64)};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root && probe.current_scope.references.count == 2);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);
	declaration := statements[1].(*Extended.Parser_Declaration);
	fresh_declaration := fresh_statements[1].(*Extended.Parser_Declaration);
	assert(declaration.first_token == fresh_declaration.first_token && declaration.one_past_last_token == fresh_declaration.one_past_last_token);
	assert(declaration.type_inst.first_token == fresh_declaration.type_inst.first_token && declaration.type_inst.one_past_last_token == fresh_declaration.type_inst.one_past_last_token);
	assert(declaration.type_inst.l0 == fresh_declaration.type_inst.l0 && declaration.type_inst.c0 == fresh_declaration.type_inst.c0);
	assert(declaration.type_inst.l1 == fresh_declaration.type_inst.l1 && declaration.type_inst.c1 == fresh_declaration.type_inst.c1);
	inner := declaration.type_inst.pointer_to;
	fresh_inner := fresh_declaration.type_inst.pointer_to;
	assert(inner.node_flags == fresh_inner.node_flags);
	assert(inner.first_token == fresh_inner.first_token && inner.one_past_last_token == fresh_inner.one_past_last_token);
	assert(inner.l0 == fresh_inner.l0 && inner.c0 == fresh_inner.c0 && inner.l1 == fresh_inner.l1 && inner.c1 == fresh_inner.c1);
	type_name := inner.pointer_to.type_valued_expression.(*Extended.Parser_Ident);
	assert(type_name.resolved_declaration == statements[2].(*Extended.Parser_Declaration));
	assert(fresh_inner.pointer_to.type_valued_expression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[2].(*Extended.Parser_Declaration));
	assert(declaration.expression.(*Extended.Parser_Ident).resolved_declaration == statements[3].(*Extended.Parser_Declaration));
	assert(fresh_declaration.expression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[3].(*Extended.Parser_Declaration));
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	assert_eligible_edit_matches_fresh(*updated, *fresh);

	changed_source := copy_string("use: *Target = value; Target :: 1; value :: 2;");
	changed, changed_ok := Extended.parse_file_edit(*old, "use: ".count, "use: *".count, changed_source);
	changed_fresh := Extended.parse_file(changed_source);
	assert(changed_ok && changed.status == .COMPLETE && changed_fresh.status == .COMPLETE);
	changed_tokens := Extended.materialise_tokens(changed_source);
	changed_probe := Extended.Parser.{parsed=*changed_tokens, edit_source=*old, edit_start="use: ".count, edit_end="use: *".count, cursor=0};
	set_allocators(*changed_tokens.node_pool, context.default_allocator);
	changed_probe.current_scope = Extended.push_lexical_scope(*changed_probe);
	assert(Extended.reuse_simple_declaration(*changed_probe) == null);
	Extended.release_parser_tree(*changed_tokens);
	Extended.release_parser_names(*changed_tokens);
	changed_declaration := changed.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Declaration);
	changed_fresh_declaration := changed_fresh.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Declaration);
	assert(changed_declaration.type_inst.first_token == changed_fresh_declaration.type_inst.first_token && changed_declaration.type_inst.one_past_last_token == changed_fresh_declaration.type_inst.one_past_last_token);
	assert(changed_declaration.type_inst.pointer_to.type_valued_expression.(*Extended.Parser_Ident).resolved_declaration == changed.root.(*Extended.Parser_Block).statements[1].(*Extended.Parser_Declaration));
	assert(changed.diagnostics.count == changed_fresh.diagnostics.count && changed.restart_points.count == changed_fresh.restart_points.count);
	assert(Extended.reconstruct_source(*changed) == changed_source);
	Extended.release_parser_tree(*changed);
	Extended.release_parser_names(*changed);
	Extended.release_parser_tree(*changed_fresh);
	Extended.release_parser_names(*changed_fresh);
	free(changed_source);

	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(type_name.name == "Target" && Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);
}

test_uninitialized_typed_declaration_ast_reuse :: () {
	old_source := copy_string(			   "item: Target; Target :: 1; use := item;");
	new_source := copy_string("added :: 0;\nitem: Target; Target :: 1; use := item;");
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && updated.status == .COMPLETE && fresh.status == .COMPLETE);

	statements := updated.root.(*Extended.Parser_Block).statements;
	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, cursor=statements[1].first_token.(s64)};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root && probe.current_scope.references.count == 1);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);

	declaration := statements[1].(*Extended.Parser_Declaration);
	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	fresh_declaration := fresh_statements[1].(*Extended.Parser_Declaration);
	assert(!declaration.expression && !fresh_declaration.expression);
	assert(!(declaration.flags & .IS_UNINITIALIZED) && declaration.flags == fresh_declaration.flags);
	assert(declaration.first_token == fresh_declaration.first_token && declaration.one_past_last_token == fresh_declaration.one_past_last_token);
	assert(declaration.type_inst.first_token == fresh_declaration.type_inst.first_token && declaration.type_inst.one_past_last_token == fresh_declaration.type_inst.one_past_last_token);
	type_name := declaration.type_inst.type_valued_expression.(*Extended.Parser_Ident);
	assert(type_name.resolved_declaration == statements[2].(*Extended.Parser_Declaration));
	assert(fresh_declaration.type_inst.type_valued_expression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[2].(*Extended.Parser_Declaration));
	assert(statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == declaration);
	assert(fresh_statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == fresh_declaration);
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(type_name.name == "Target" && declaration.name == "item" && Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);

	pointer_old_source := copy_string(			   "item: *Target; Target :: 1; use := item;");
	pointer_new_source := copy_string("added :: 0;\nitem: *Target; Target :: 1; use := item;");
	pointer_old := Extended.parse_file(pointer_old_source);
	pointer_updated, pointer_ok := Extended.parse_file_edit(*pointer_old, 0, 0, pointer_new_source);
	pointer_fresh := Extended.parse_file(pointer_new_source);
	assert(pointer_ok && pointer_updated.status == .COMPLETE && pointer_fresh.status == .COMPLETE);
	pointer_statements := pointer_updated.root.(*Extended.Parser_Block).statements;
	pointer_probe_tokens := Extended.materialise_tokens(pointer_new_source);
	pointer_probe := Extended.Parser.{parsed=*pointer_probe_tokens, edit_source=*pointer_old, cursor=pointer_statements[1].first_token.(s64)};
	set_allocators(*pointer_probe_tokens.node_pool, context.default_allocator);
	pointer_probe.current_scope = Extended.push_lexical_scope(*pointer_probe);
	pointer_probe_tokens.root = Extended.reuse_simple_declaration(*pointer_probe);
	assert(pointer_probe_tokens.root && pointer_probe.current_scope.references.count == 1);
	Extended.release_parser_tree(*pointer_probe_tokens);
	Extended.release_parser_names(*pointer_probe_tokens);
	pointer_decl := pointer_statements[1].(*Extended.Parser_Declaration);
	pointer_fresh_statements := pointer_fresh.root.(*Extended.Parser_Block).statements;
	pointer_fresh_decl := pointer_fresh_statements[1].(*Extended.Parser_Declaration);
	assert(!pointer_decl.expression && !pointer_fresh_decl.expression);
	assert(pointer_decl.type_inst.first_token == pointer_fresh_decl.type_inst.first_token && pointer_decl.type_inst.one_past_last_token == pointer_fresh_decl.type_inst.one_past_last_token);
	assert(
		pointer_decl.type_inst.pointer_to.first_token == pointer_fresh_decl.type_inst.pointer_to.first_token
		&& pointer_decl.type_inst.pointer_to.one_past_last_token == pointer_fresh_decl.type_inst.pointer_to.one_past_last_token
	);
	pointer_name := pointer_decl.type_inst.pointer_to.type_valued_expression.(*Extended.Parser_Ident);
	assert(pointer_name.resolved_declaration == pointer_statements[2].(*Extended.Parser_Declaration));
	assert(pointer_fresh_decl.type_inst.pointer_to.type_valued_expression.(*Extended.Parser_Ident).resolved_declaration == pointer_fresh_statements[2].(*Extended.Parser_Declaration));
	assert(pointer_statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == pointer_decl);
	assert(pointer_updated.diagnostics.count == pointer_fresh.diagnostics.count && pointer_updated.restart_points.count == pointer_fresh.restart_points.count);
	Extended.release_parser_tree(*pointer_old);
	Extended.release_parser_names(*pointer_old);
	free(pointer_old_source);
	assert(pointer_name.name == "Target" && Extended.reconstruct_source(*pointer_updated) == pointer_new_source);
	Extended.release_parser_tree(*pointer_updated);
	Extended.release_parser_names(*pointer_updated);
	Extended.release_parser_tree(*pointer_fresh);
	Extended.release_parser_names(*pointer_fresh);
	free(pointer_new_source);

	uninitialized_old_source := copy_string(			 "Target :: s64; item: Target = ---; use := item;");
	uninitialized_new_source := copy_string("added :: 0;\nTarget :: s64; item: Target = ---; use := item;");
	uninitialized_old := Extended.parse_file(uninitialized_old_source);
	uninitialized_updated, uninitialized_ok := Extended.parse_file_edit(*uninitialized_old, 0, 0, uninitialized_new_source);
	uninitialized_fresh := Extended.parse_file(uninitialized_new_source);
	assert(uninitialized_ok && uninitialized_old.status == .COMPLETE && uninitialized_updated.status == .COMPLETE && uninitialized_fresh.status == .COMPLETE);
	uninitialized_statements := uninitialized_updated.root.(*Extended.Parser_Block).statements;
	uninitialized_fresh_statements := uninitialized_fresh.root.(*Extended.Parser_Block).statements;
	uninitialized_tokens := Extended.materialise_tokens(uninitialized_new_source);
	uninitialized_probe := Extended.Parser.{parsed=*uninitialized_tokens, edit_source=*uninitialized_old, cursor=uninitialized_statements[2].first_token.(s64)};
	set_allocators(*uninitialized_tokens.node_pool, context.default_allocator);
	uninitialized_probe.current_scope = Extended.push_lexical_scope(*uninitialized_probe);
	assert(Extended.reuse_simple_declaration(*uninitialized_probe) == null);
	Extended.release_parser_tree(*uninitialized_tokens);
	Extended.release_parser_names(*uninitialized_tokens);
	uninitialized_decl := uninitialized_statements[2].(*Extended.Parser_Declaration);
	uninitialized_fresh_decl := uninitialized_fresh_statements[2].(*Extended.Parser_Declaration);
	assert(!uninitialized_decl.expression && !uninitialized_fresh_decl.expression);
	assert(uninitialized_decl.flags & .IS_UNINITIALIZED && uninitialized_decl.flags == uninitialized_fresh_decl.flags);
	assert(uninitialized_decl.first_token == uninitialized_fresh_decl.first_token && uninitialized_decl.one_past_last_token == uninitialized_fresh_decl.one_past_last_token);
	assert(uninitialized_decl.type_inst.first_token == uninitialized_fresh_decl.type_inst.first_token && uninitialized_decl.type_inst.one_past_last_token == uninitialized_fresh_decl.type_inst.one_past_last_token);
	assert(uninitialized_decl.l0 == uninitialized_fresh_decl.l0 && uninitialized_decl.c0 == uninitialized_fresh_decl.c0);
	assert(uninitialized_decl.type_inst.type_valued_expression.(*Extended.Parser_Ident).resolved_declaration == uninitialized_statements[1].(*Extended.Parser_Declaration));
	assert(uninitialized_fresh_decl.type_inst.type_valued_expression.(*Extended.Parser_Ident).resolved_declaration == uninitialized_fresh_statements[1].(*Extended.Parser_Declaration));
	assert(uninitialized_statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == uninitialized_decl);
	assert(uninitialized_fresh_statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == uninitialized_fresh_decl);
	assert(uninitialized_updated.diagnostics.count == uninitialized_fresh.diagnostics.count && uninitialized_updated.restart_points.count == uninitialized_fresh.restart_points.count);
	Extended.release_parser_tree(*uninitialized_old);
	Extended.release_parser_names(*uninitialized_old);
	free(uninitialized_old_source);
	assert(Extended.reconstruct_source(*uninitialized_updated) == uninitialized_new_source);
	Extended.release_parser_tree(*uninitialized_updated);
	Extended.release_parser_names(*uninitialized_updated);
	Extended.release_parser_tree(*uninitialized_fresh);
	Extended.release_parser_names(*uninitialized_fresh);
	free(uninitialized_new_source);

	import_old_source := copy_string(			  "Basic :: #import \"Basic\"; use := Basic;");
	import_new_source := copy_string("added :: 0;\nBasic :: #import \"Basic\"; use := Basic;");
	import_old := Extended.parse_file(import_old_source);
	import_updated, import_ok := Extended.parse_file_edit(*import_old, 0, 0, import_new_source);
	import_fresh := Extended.parse_file(import_new_source);
	assert(import_ok && import_old.status == .COMPLETE && import_updated.status == .COMPLETE && import_fresh.status == .COMPLETE);
	import_statements := import_updated.root.(*Extended.Parser_Block).statements;
	import_fresh_statements := import_fresh.root.(*Extended.Parser_Block).statements;
	import_tokens := Extended.materialise_tokens(import_new_source);
	import_probe := Extended.Parser.{parsed=*import_tokens, edit_source=*import_old, cursor=import_statements[1].first_token.(s64)};
	set_allocators(*import_tokens.node_pool, context.default_allocator);
	import_probe.current_scope = Extended.push_lexical_scope(*import_probe);
	assert(Extended.reuse_simple_declaration(*import_probe) == null);
	Extended.release_parser_tree(*import_tokens);
	Extended.release_parser_names(*import_tokens);
	import_decl := import_statements[1].(*Extended.Parser_Declaration);
	import_fresh_decl := import_fresh_statements[1].(*Extended.Parser_Declaration);
	assert(import_decl.expression.kind == .DIRECTIVE_IMPORT && import_fresh_decl.expression.kind == .DIRECTIVE_IMPORT);
	assert(!import_decl.import_target && !import_fresh_decl.import_target);
	assert(import_decl.expression.(*Extended.Parser_Directive_Import).name == import_fresh_decl.expression.(*Extended.Parser_Directive_Import).name);
	assert(import_decl.first_token == import_fresh_decl.first_token && import_decl.one_past_last_token == import_fresh_decl.one_past_last_token);
	assert(import_decl.expression.first_token == import_fresh_decl.expression.first_token && import_decl.expression.one_past_last_token == import_fresh_decl.expression.one_past_last_token);
	assert(import_decl.l0 == import_fresh_decl.l0 && import_decl.c0 == import_fresh_decl.c0);
	assert(import_decl.expression.l0 == import_fresh_decl.expression.l0 && import_decl.expression.c0 == import_fresh_decl.expression.c0);
	assert(import_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == import_decl);
	assert(import_fresh_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == import_fresh_decl);
	assert(import_updated.diagnostics.count == import_fresh.diagnostics.count && import_updated.restart_points.count == import_fresh.restart_points.count);
	Extended.release_parser_tree(*import_old);
	Extended.release_parser_names(*import_old);
	free(import_old_source);
	assert(import_decl.expression.(*Extended.Parser_Directive_Import).name == "Basic" && Extended.reconstruct_source(*import_updated) == import_new_source);
	Extended.release_parser_tree(*import_updated);
	Extended.release_parser_names(*import_updated);
	Extended.release_parser_tree(*import_fresh);
	Extended.release_parser_names(*import_fresh);
	free(import_new_source);

	using_old_source := copy_string(			 "State :: struct { member: s64; }; using global: State; after := 1;");
	using_new_source := copy_string("added :: 0;\nState :: struct { member: s64; }; using global: State; after := 1;");
	using_old := Extended.parse_file(using_old_source);
	using_updated, using_ok := Extended.parse_file_edit(*using_old, 0, 0, using_new_source);
	using_fresh := Extended.parse_file(using_new_source);
	assert(using_ok && using_old.status == .COMPLETE && using_updated.status == .COMPLETE && using_fresh.status == .COMPLETE);
	using_statements := using_updated.root.(*Extended.Parser_Block).statements;
	using_fresh_statements := using_fresh.root.(*Extended.Parser_Block).statements;
	using_tokens := Extended.materialise_tokens(using_new_source);
	using_probe := Extended.Parser.{parsed=*using_tokens, edit_source=*using_old, cursor=using_statements[2].first_token.(s64)};
	set_allocators(*using_tokens.node_pool, context.default_allocator);
	using_probe.current_scope = Extended.push_lexical_scope(*using_probe);
	assert(Extended.reuse_simple_declaration(*using_probe) == null);
	Extended.release_parser_tree(*using_tokens);
	Extended.release_parser_names(*using_tokens);
	using_node := using_statements[2].(*Extended.Parser_Using);
	using_fresh_node := using_fresh_statements[2].(*Extended.Parser_Using);
	using_decl := using_node.expression.(*Extended.Parser_Declaration);
	using_fresh_decl := using_fresh_node.expression.(*Extended.Parser_Declaration);
	assert(using_node.first_token == using_fresh_node.first_token && using_node.one_past_last_token == using_fresh_node.one_past_last_token);
	assert(using_decl.first_token == using_fresh_decl.first_token && using_decl.one_past_last_token == using_fresh_decl.one_past_last_token);
	assert(using_node.l0 == using_fresh_node.l0 && using_node.c0 == using_fresh_node.c0);
	assert(using_decl.type_inst.type_valued_expression.(*Extended.Parser_Ident).resolved_declaration == using_statements[1].(*Extended.Parser_Declaration));
	assert(using_fresh_decl.type_inst.type_valued_expression.(*Extended.Parser_Ident).resolved_declaration == using_fresh_statements[1].(*Extended.Parser_Declaration));
	assert(using_updated.diagnostics.count == using_fresh.diagnostics.count && using_updated.restart_points.count == using_fresh.restart_points.count);
	Extended.release_parser_tree(*using_old);
	Extended.release_parser_names(*using_old);
	free(using_old_source);
	assert(using_decl.name == "global" && Extended.reconstruct_source(*using_updated) == using_new_source);
	Extended.release_parser_tree(*using_updated);
	Extended.release_parser_names(*using_updated);
	Extended.release_parser_tree(*using_fresh);
	Extended.release_parser_names(*using_fresh);
	free(using_new_source);
}

test_typed_compound_ast_reuse :: () {
	old_source := copy_string(			   "left, right: Target = value; Target :: 1; value :: 2; use := right;");
	new_source := copy_string("added :: 0;\nleft, right: Target = value; Target :: 1; value :: 2; use := right;");
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && updated.status == .COMPLETE && fresh.status == .COMPLETE);

	statements := updated.root.(*Extended.Parser_Block).statements;
	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, cursor=statements[1].first_token.(s64)};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root && probe_tokens.root.kind == .COMPOUND_DECLARATION);
	assert(probe.current_scope.bindings.count == 2 && probe.current_scope.references.count == 2);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);

	compound := statements[1].(*Extended.Parser_Compound_Declaration);
	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	fresh_compound := fresh_statements[1].(*Extended.Parser_Compound_Declaration);
	assert(compound.kind == fresh_compound.kind && compound.node_flags == fresh_compound.node_flags);
	assert(compound.first_token == fresh_compound.first_token && compound.one_past_last_token == fresh_compound.one_past_last_token);
	assert(compound.l0 == fresh_compound.l0 && compound.c0 == fresh_compound.c0 && compound.l1 == fresh_compound.l1 && compound.c1 == fresh_compound.c1);
	assert(compound.comma_separated_assignment.kind == fresh_compound.comma_separated_assignment.kind && compound.comma_separated_assignment.node_flags == fresh_compound.comma_separated_assignment.node_flags);
	assert(compound.comma_separated_assignment.first_token == fresh_compound.comma_separated_assignment.first_token);
	assert(compound.comma_separated_assignment.one_past_last_token == fresh_compound.comma_separated_assignment.one_past_last_token);
	assert(compound.declaration_properties.node_flags == fresh_compound.declaration_properties.node_flags);
	assert(compound.declaration_properties.type_inst.first_token == fresh_compound.declaration_properties.type_inst.first_token);
	assert(compound.declaration_properties.type_inst.one_past_last_token == fresh_compound.declaration_properties.type_inst.one_past_last_token);
	type_name := compound.declaration_properties.type_inst.type_valued_expression.(*Extended.Parser_Ident);
	value_name := compound.declaration_properties.expression.(*Extended.Parser_Ident);
	assert(type_name.resolved_declaration == statements[2].(*Extended.Parser_Declaration));
	assert(value_name.resolved_declaration == statements[3].(*Extended.Parser_Declaration));
	assert(fresh_compound.declaration_properties.type_inst.type_valued_expression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[2].(*Extended.Parser_Declaration));
	assert(fresh_compound.declaration_properties.expression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[3].(*Extended.Parser_Declaration));
	assert(statements[4].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == compound.declaration_properties);
	assert(fresh_statements[4].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == fresh_compound.declaration_properties);
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(type_name.name == "Target" && value_name.name == "value" && Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);

	pointer_old_source := copy_string(			   "left, middle, right: *Target = value; Target :: 1; value :: 2; use := middle;");
	pointer_new_source := copy_string("added :: 0;\nleft, middle, right: *Target = value; Target :: 1; value :: 2; use := middle;");
	pointer_old := Extended.parse_file(pointer_old_source);
	pointer_updated, pointer_ok := Extended.parse_file_edit(*pointer_old, 0, 0, pointer_new_source);
	pointer_fresh := Extended.parse_file(pointer_new_source);
	assert(pointer_ok && pointer_updated.status == .COMPLETE && pointer_fresh.status == .COMPLETE);
	pointer_statements := pointer_updated.root.(*Extended.Parser_Block).statements;
	pointer_probe_tokens := Extended.materialise_tokens(pointer_new_source);
	pointer_probe := Extended.Parser.{parsed=*pointer_probe_tokens, edit_source=*pointer_old, cursor=pointer_statements[1].first_token.(s64)};
	set_allocators(*pointer_probe_tokens.node_pool, context.default_allocator);
	pointer_probe.current_scope = Extended.push_lexical_scope(*pointer_probe);
	pointer_probe_tokens.root = Extended.reuse_simple_declaration(*pointer_probe);
	assert(pointer_probe_tokens.root && pointer_probe.current_scope.bindings.count == 3 && pointer_probe.current_scope.references.count == 2);
	Extended.release_parser_tree(*pointer_probe_tokens);
	Extended.release_parser_names(*pointer_probe_tokens);

	pointer_compound := pointer_statements[1].(*Extended.Parser_Compound_Declaration);
	pointer_fresh_statements := pointer_fresh.root.(*Extended.Parser_Block).statements;
	pointer_fresh_compound := pointer_fresh_statements[1].(*Extended.Parser_Compound_Declaration);
	assert(pointer_compound.comma_separated_assignment.one_past_last_token == pointer_fresh_compound.comma_separated_assignment.one_past_last_token);
	assert(pointer_compound.declaration_properties.type_inst.first_token == pointer_fresh_compound.declaration_properties.type_inst.first_token);
	assert(pointer_compound.declaration_properties.type_inst.one_past_last_token == pointer_fresh_compound.declaration_properties.type_inst.one_past_last_token);
	assert(pointer_compound.declaration_properties.type_inst.pointer_to.first_token == pointer_fresh_compound.declaration_properties.type_inst.pointer_to.first_token);
	assert(pointer_compound.declaration_properties.type_inst.pointer_to.one_past_last_token == pointer_fresh_compound.declaration_properties.type_inst.pointer_to.one_past_last_token);
	pointer_type_name := pointer_compound.declaration_properties.type_inst.pointer_to.type_valued_expression.(*Extended.Parser_Ident);
	assert(pointer_type_name.resolved_declaration == pointer_statements[2].(*Extended.Parser_Declaration));
	assert(pointer_fresh_compound.declaration_properties.type_inst.pointer_to.type_valued_expression.(*Extended.Parser_Ident).resolved_declaration == pointer_fresh_statements[2].(*Extended.Parser_Declaration));
	assert(pointer_compound.declaration_properties.expression.(*Extended.Parser_Ident).resolved_declaration == pointer_statements[3].(*Extended.Parser_Declaration));
	assert(pointer_statements[4].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == pointer_compound.declaration_properties);
	assert(pointer_fresh_statements[4].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == pointer_fresh_compound.declaration_properties);
	assert(pointer_updated.diagnostics.count == pointer_fresh.diagnostics.count && pointer_updated.restart_points.count == pointer_fresh.restart_points.count);
	Extended.release_parser_tree(*pointer_old);
	Extended.release_parser_names(*pointer_old);
	free(pointer_old_source);
	assert(pointer_type_name.name == "Target" && Extended.reconstruct_source(*pointer_updated) == pointer_new_source);
	Extended.release_parser_tree(*pointer_updated);
	Extended.release_parser_names(*pointer_updated);
	Extended.release_parser_tree(*pointer_fresh);
	Extended.release_parser_names(*pointer_fresh);
	free(pointer_new_source);

	double_old_source := copy_string(			  "left, right: **Target = value; Target :: 1; value :: 2; use := right;");
	double_new_source := copy_string("added :: 0;\nleft, right: **Target = value; Target :: 1; value :: 2; use := right;");
	double_old := Extended.parse_file(double_old_source);
	double_updated, double_ok := Extended.parse_file_edit(*double_old, 0, 0, double_new_source);
	double_fresh := Extended.parse_file(double_new_source);
	assert(double_ok && double_old.status == .COMPLETE && double_updated.status == .COMPLETE && double_fresh.status == .COMPLETE);
	double_statements := double_updated.root.(*Extended.Parser_Block).statements;
	double_fresh_statements := double_fresh.root.(*Extended.Parser_Block).statements;
	double_probe_tokens := Extended.materialise_tokens(double_new_source);
	double_probe := Extended.Parser.{parsed=*double_probe_tokens, edit_source=*double_old, cursor=double_statements[1].first_token.(s64)};
	set_allocators(*double_probe_tokens.node_pool, context.default_allocator);
	double_probe.current_scope = Extended.push_lexical_scope(*double_probe);
	double_probe_tokens.root = Extended.reuse_simple_declaration(*double_probe);
	assert(double_probe_tokens.root && double_probe_tokens.root.kind == .COMPOUND_DECLARATION);
	assert(double_probe.current_scope.bindings.count == 2 && double_probe.current_scope.references.count == 2);
	Extended.release_parser_tree(*double_probe_tokens);
	Extended.release_parser_names(*double_probe_tokens);
	double_compound := double_statements[1].(*Extended.Parser_Compound_Declaration);
	double_fresh_compound := double_fresh_statements[1].(*Extended.Parser_Compound_Declaration);
	assert(double_compound.first_token == double_fresh_compound.first_token && double_compound.one_past_last_token == double_fresh_compound.one_past_last_token);
	double_type := double_compound.declaration_properties.type_inst;
	double_fresh_type := double_fresh_compound.declaration_properties.type_inst;
	assert(double_type.first_token == double_fresh_type.first_token && double_type.one_past_last_token == double_fresh_type.one_past_last_token);
	assert(double_type.l0 == double_fresh_type.l0 && double_type.c0 == double_fresh_type.c0 && double_type.l1 == double_fresh_type.l1 && double_type.c1 == double_fresh_type.c1);
	assert(double_type.pointer_to.first_token == double_fresh_type.pointer_to.first_token && double_type.pointer_to.one_past_last_token == double_fresh_type.pointer_to.one_past_last_token);
	assert(double_type.pointer_to.l0 == double_fresh_type.pointer_to.l0 && double_type.pointer_to.c0 == double_fresh_type.pointer_to.c0);
	assert(double_type.pointer_to.l1 == double_fresh_type.pointer_to.l1 && double_type.pointer_to.c1 == double_fresh_type.pointer_to.c1);
	assert(double_type.pointer_to.pointer_to.first_token == double_fresh_type.pointer_to.pointer_to.first_token);
	assert(double_type.pointer_to.pointer_to.one_past_last_token == double_fresh_type.pointer_to.pointer_to.one_past_last_token);
	double_type_name := double_type.pointer_to.pointer_to.type_valued_expression.(*Extended.Parser_Ident);
	assert(double_type_name.first_token == double_fresh_type.pointer_to.pointer_to.type_valued_expression.first_token);
	assert(double_type_name.one_past_last_token == double_fresh_type.pointer_to.pointer_to.type_valued_expression.one_past_last_token);
	assert(double_type_name.resolved_declaration == double_statements[2].(*Extended.Parser_Declaration));
	assert(double_fresh_type.pointer_to.pointer_to.type_valued_expression.(*Extended.Parser_Ident).resolved_declaration == double_fresh_statements[2].(*Extended.Parser_Declaration));
	assert(double_compound.declaration_properties.expression.(*Extended.Parser_Ident).resolved_declaration == double_statements[3].(*Extended.Parser_Declaration));
	assert(double_fresh_compound.declaration_properties.expression.(*Extended.Parser_Ident).resolved_declaration == double_fresh_statements[3].(*Extended.Parser_Declaration));
	assert(double_statements[4].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == double_compound.declaration_properties);
	assert(double_fresh_statements[4].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == double_fresh_compound.declaration_properties);
	assert(double_updated.diagnostics.count == double_fresh.diagnostics.count && double_updated.restart_points.count == double_fresh.restart_points.count);
	Extended.release_parser_tree(*double_old);
	Extended.release_parser_names(*double_old);
	free(double_old_source);
	assert(double_type_name.name == "Target" && Extended.reconstruct_source(*double_updated) == double_new_source);
	Extended.release_parser_tree(*double_updated);
	Extended.release_parser_names(*double_updated);
	Extended.release_parser_tree(*double_fresh);
	Extended.release_parser_names(*double_fresh);
	free(double_new_source);

	array_old_source := copy_string(			 "left, right: [size]Target = value; size :: 4; Target :: u8; value :: 2; use := right;");
	array_new_source := copy_string("added :: 0;\nleft, right: [size]Target = value; size :: 4; Target :: u8; value :: 2; use := right;");
	array_old := Extended.parse_file(array_old_source);
	array_updated, array_ok := Extended.parse_file_edit(*array_old, 0, 0, array_new_source);
	array_fresh := Extended.parse_file(array_new_source);
	assert(array_ok && array_old.status == .COMPLETE && array_updated.status == .COMPLETE && array_fresh.status == .COMPLETE);
	array_statements := array_updated.root.(*Extended.Parser_Block).statements;
	array_fresh_statements := array_fresh.root.(*Extended.Parser_Block).statements;
	array_probe_tokens := Extended.materialise_tokens(array_new_source);
	array_probe := Extended.Parser.{parsed=*array_probe_tokens, edit_source=*array_old, cursor=array_statements[1].first_token.(s64)};
	set_allocators(*array_probe_tokens.node_pool, context.default_allocator);
	array_probe.current_scope = Extended.push_lexical_scope(*array_probe);
	array_probe_tokens.root = Extended.reuse_simple_declaration(*array_probe);
	assert(array_probe_tokens.root && array_probe_tokens.root.kind == .COMPOUND_DECLARATION);
	assert(array_probe.current_scope.bindings.count == 2 && array_probe.current_scope.references.count == 3);
	Extended.release_parser_tree(*array_probe_tokens);
	Extended.release_parser_names(*array_probe_tokens);
	array_compound := array_statements[1].(*Extended.Parser_Compound_Declaration);
	array_fresh_compound := array_fresh_statements[1].(*Extended.Parser_Compound_Declaration);
	assert(array_compound.first_token == array_fresh_compound.first_token && array_compound.one_past_last_token == array_fresh_compound.one_past_last_token);
	array_type := array_compound.declaration_properties.type_inst;
	array_fresh_type := array_fresh_compound.declaration_properties.type_inst;
	assert(array_type.first_token == array_fresh_type.first_token && array_type.one_past_last_token == array_fresh_type.one_past_last_token);
	assert(array_type.l0 == array_fresh_type.l0 && array_type.c0 == array_fresh_type.c0 && array_type.l1 == array_fresh_type.l1 && array_type.c1 == array_fresh_type.c1);
	array_size := array_type.array_dimension.(*Extended.Parser_Ident);
	assert(array_size.first_token == array_fresh_type.array_dimension.first_token && array_size.one_past_last_token == array_fresh_type.array_dimension.one_past_last_token);
	assert(array_size.resolved_declaration == array_statements[2].(*Extended.Parser_Declaration));
	assert(array_fresh_type.array_dimension.(*Extended.Parser_Ident).resolved_declaration == array_fresh_statements[2].(*Extended.Parser_Declaration));
	array_type_name := array_type.array_element_type.type_valued_expression.(*Extended.Parser_Ident);
	assert(array_type_name.resolved_declaration == array_statements[3].(*Extended.Parser_Declaration));
	assert(array_fresh_type.array_element_type.type_valued_expression.(*Extended.Parser_Ident).resolved_declaration == array_fresh_statements[3].(*Extended.Parser_Declaration));
	assert(array_compound.declaration_properties.expression.(*Extended.Parser_Ident).resolved_declaration == array_statements[4].(*Extended.Parser_Declaration));
	assert(array_fresh_compound.declaration_properties.expression.(*Extended.Parser_Ident).resolved_declaration == array_fresh_statements[4].(*Extended.Parser_Declaration));
	assert(array_statements[5].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == array_compound.declaration_properties);
	assert(array_fresh_statements[5].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == array_fresh_compound.declaration_properties);
	assert(array_updated.diagnostics.count == array_fresh.diagnostics.count && array_updated.restart_points.count == array_fresh.restart_points.count);
	Extended.release_parser_tree(*array_old);
	Extended.release_parser_names(*array_old);
	free(array_old_source);
	assert(array_size.name == "size" && array_type_name.name == "Target" && Extended.reconstruct_source(*array_updated) == array_new_source);
	Extended.release_parser_tree(*array_updated);
	Extended.release_parser_names(*array_updated);
	Extended.release_parser_tree(*array_fresh);
	Extended.release_parser_names(*array_fresh);
	free(array_new_source);

	fixed_value_old_source := copy_string(			   "Target :: s64; value: [2]Target : .[1, 2]; left, right: [2]Target = value; main :: () { use_left := left; use_right := right; }");
	fixed_value_new_source := copy_string("added :: 0;\nTarget :: s64; value: [2]Target : .[1, 2]; left, right: [2]Target = value; main :: () { use_left := left; use_right := right; }");
	fixed_value_old := Extended.parse_file(fixed_value_old_source);
	fixed_value_updated, fixed_value_ok := Extended.parse_file_edit(*fixed_value_old, 0, 0, fixed_value_new_source);
	fixed_value_fresh := Extended.parse_file(fixed_value_new_source);
	assert(fixed_value_ok && fixed_value_old.status == .COMPLETE && fixed_value_updated.status == .COMPLETE && fixed_value_fresh.status == .COMPLETE);
	fixed_value_statements := fixed_value_updated.root.(*Extended.Parser_Block).statements;
	fixed_value_fresh_statements := fixed_value_fresh.root.(*Extended.Parser_Block).statements;
	fixed_value_tokens := Extended.materialise_tokens(fixed_value_new_source);
	fixed_value_probe := Extended.Parser.{parsed=*fixed_value_tokens, edit_source=*fixed_value_old, cursor=fixed_value_statements[3].first_token.(s64)};
	set_allocators(*fixed_value_tokens.node_pool, context.default_allocator);
	fixed_value_probe.current_scope = Extended.push_lexical_scope(*fixed_value_probe);
	fixed_value_tokens.root = Extended.reuse_simple_declaration(*fixed_value_probe);
	assert(fixed_value_tokens.root && fixed_value_tokens.root.kind == .COMPOUND_DECLARATION);
	assert(fixed_value_probe.current_scope.bindings.count == 2 && fixed_value_probe.current_scope.references.count == 2);
	Extended.release_parser_tree(*fixed_value_tokens);
	Extended.release_parser_names(*fixed_value_tokens);
	fixed_value_compound := fixed_value_statements[3].(*Extended.Parser_Compound_Declaration);
	fixed_value_fresh_compound := fixed_value_fresh_statements[3].(*Extended.Parser_Compound_Declaration);
	fixed_value_type := fixed_value_compound.declaration_properties.type_inst;
	fixed_value_fresh_type := fixed_value_fresh_compound.declaration_properties.type_inst;
	assert(fixed_value_type.inst_flags == 0 && fixed_value_type.inst_flags == fixed_value_fresh_type.inst_flags);
	assert(fixed_value_compound.first_token == fixed_value_fresh_compound.first_token && fixed_value_compound.one_past_last_token == fixed_value_fresh_compound.one_past_last_token);
	assert(fixed_value_type.first_token == fixed_value_fresh_type.first_token && fixed_value_type.one_past_last_token == fixed_value_fresh_type.one_past_last_token);
	assert(fixed_value_type.l0 == fixed_value_fresh_type.l0 && fixed_value_type.c0 == fixed_value_fresh_type.c0 && fixed_value_type.l1 == fixed_value_fresh_type.l1 && fixed_value_type.c1 == fixed_value_fresh_type.c1);
	fixed_value_dimension := fixed_value_type.array_dimension.(*Extended.Parser_Literal);
	assert(fixed_value_dimension._u64 == 2 && fixed_value_dimension._u64 == fixed_value_fresh_type.array_dimension.(*Extended.Parser_Literal)._u64);
	assert(fixed_value_dimension.first_token == fixed_value_fresh_type.array_dimension.first_token && fixed_value_dimension.one_past_last_token == fixed_value_fresh_type.array_dimension.one_past_last_token);
	fixed_value_name := fixed_value_type.array_element_type.type_valued_expression.(*Extended.Parser_Ident);
	assert(fixed_value_name.resolved_declaration == fixed_value_statements[1].(*Extended.Parser_Declaration));
	assert(fixed_value_fresh_type.array_element_type.type_valued_expression.(*Extended.Parser_Ident).resolved_declaration == fixed_value_fresh_statements[1].(*Extended.Parser_Declaration));
	fixed_value_expression := fixed_value_compound.declaration_properties.expression.(*Extended.Parser_Ident);
	fixed_value_fresh_expression := fixed_value_fresh_compound.declaration_properties.expression.(*Extended.Parser_Ident);
	assert(fixed_value_expression.first_token == fixed_value_fresh_expression.first_token && fixed_value_expression.one_past_last_token == fixed_value_fresh_expression.one_past_last_token);
	assert(fixed_value_expression.resolved_declaration == fixed_value_statements[2].(*Extended.Parser_Declaration));
	assert(fixed_value_fresh_expression.resolved_declaration == fixed_value_fresh_statements[2].(*Extended.Parser_Declaration));
	fixed_value_body := fixed_value_statements[4].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block;
	fixed_value_fresh_body := fixed_value_fresh_statements[4].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block;
	for 0..1 {
		assert(fixed_value_body.statements[it].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == fixed_value_compound.declaration_properties);
		assert(fixed_value_fresh_body.statements[it].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == fixed_value_fresh_compound.declaration_properties);
	}

	assert(fixed_value_updated.diagnostics.count == fixed_value_fresh.diagnostics.count && fixed_value_updated.restart_points.count == fixed_value_fresh.restart_points.count);
	Extended.release_parser_tree(*fixed_value_old);
	Extended.release_parser_names(*fixed_value_old);
	free(fixed_value_old_source);
	assert(fixed_value_name.name == "Target" && fixed_value_expression.name == "value" && Extended.reconstruct_source(*fixed_value_updated) == fixed_value_new_source);
	Extended.release_parser_tree(*fixed_value_updated);
	Extended.release_parser_names(*fixed_value_updated);
	Extended.release_parser_tree(*fixed_value_fresh);
	Extended.release_parser_names(*fixed_value_fresh);
	free(fixed_value_new_source);
	check_compound_reuse_fallback("left, right: [#run 4]u8; main :: () { use_left := left; use_right := right; }", false, false, false, "", 0, true);
}

test_uninitialized_typed_compound_ast_reuse :: () {
	old_source := copy_string(			   "left, right: Target; Target :: 1; use := right;");
	new_source := copy_string("added :: 0;\nleft, right: Target; Target :: 1; use := right;");
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && updated.status == .COMPLETE && fresh.status == .COMPLETE);

	statements := updated.root.(*Extended.Parser_Block).statements;
	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, cursor=statements[1].first_token.(s64)};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root && probe_tokens.root.kind == .COMPOUND_DECLARATION);
	assert(probe.current_scope.bindings.count == 2 && probe.current_scope.references.count == 1);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);

	compound := statements[1].(*Extended.Parser_Compound_Declaration);
	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	fresh_compound := fresh_statements[1].(*Extended.Parser_Compound_Declaration);
	assert(!compound.declaration_properties.expression && !fresh_compound.declaration_properties.expression);
	assert(compound.first_token == fresh_compound.first_token && compound.one_past_last_token == fresh_compound.one_past_last_token);
	assert(compound.comma_separated_assignment.one_past_last_token == fresh_compound.comma_separated_assignment.one_past_last_token);
	assert(compound.declaration_properties.type_inst.first_token == fresh_compound.declaration_properties.type_inst.first_token);
	assert(compound.declaration_properties.type_inst.one_past_last_token == fresh_compound.declaration_properties.type_inst.one_past_last_token);
	for compound.comma_separated_assignment.arguments {
		other := fresh_compound.comma_separated_assignment.arguments[it_index];
		assert(it.node.first_token == other.node.first_token && it.node.one_past_last_token == other.node.one_past_last_token);
	}

	type_name := compound.declaration_properties.type_inst.type_valued_expression.(*Extended.Parser_Ident);
	assert(type_name.resolved_declaration == statements[2].(*Extended.Parser_Declaration));
	assert(fresh_compound.declaration_properties.type_inst.type_valued_expression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[2].(*Extended.Parser_Declaration));
	assert(statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == compound.declaration_properties);
	assert(fresh_statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == fresh_compound.declaration_properties);
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(type_name.name == "Target" && compound.comma_separated_assignment.arguments[1].node.(*Extended.Parser_Ident).name == "right");
	assert(Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);

	pointer_old_source := copy_string(			   "left, middle, right: *Target; Target :: 1; use := middle;");
	pointer_new_source := copy_string("added :: 0;\nleft, middle, right: *Target; Target :: 1; use := middle;");
	pointer_old := Extended.parse_file(pointer_old_source);
	pointer_updated, pointer_ok := Extended.parse_file_edit(*pointer_old, 0, 0, pointer_new_source);
	pointer_fresh := Extended.parse_file(pointer_new_source);
	assert(pointer_ok && pointer_updated.status == .COMPLETE && pointer_fresh.status == .COMPLETE);
	pointer_statements := pointer_updated.root.(*Extended.Parser_Block).statements;
	pointer_probe_tokens := Extended.materialise_tokens(pointer_new_source);
	pointer_probe := Extended.Parser.{parsed=*pointer_probe_tokens, edit_source=*pointer_old, cursor=pointer_statements[1].first_token.(s64)};
	set_allocators(*pointer_probe_tokens.node_pool, context.default_allocator);
	pointer_probe.current_scope = Extended.push_lexical_scope(*pointer_probe);
	pointer_probe_tokens.root = Extended.reuse_simple_declaration(*pointer_probe);
	assert(pointer_probe_tokens.root && pointer_probe.current_scope.bindings.count == 3 && pointer_probe.current_scope.references.count == 1);
	Extended.release_parser_tree(*pointer_probe_tokens);
	Extended.release_parser_names(*pointer_probe_tokens);

	pointer_compound := pointer_statements[1].(*Extended.Parser_Compound_Declaration);
	pointer_fresh_statements := pointer_fresh.root.(*Extended.Parser_Block).statements;
	pointer_fresh_compound := pointer_fresh_statements[1].(*Extended.Parser_Compound_Declaration);
	assert(!pointer_compound.declaration_properties.expression && !pointer_fresh_compound.declaration_properties.expression);
	assert(pointer_compound.comma_separated_assignment.one_past_last_token == pointer_fresh_compound.comma_separated_assignment.one_past_last_token);
	assert(pointer_compound.declaration_properties.type_inst.first_token == pointer_fresh_compound.declaration_properties.type_inst.first_token);
	assert(pointer_compound.declaration_properties.type_inst.one_past_last_token == pointer_fresh_compound.declaration_properties.type_inst.one_past_last_token);
	assert(pointer_compound.declaration_properties.type_inst.pointer_to.first_token == pointer_fresh_compound.declaration_properties.type_inst.pointer_to.first_token);
	assert(pointer_compound.declaration_properties.type_inst.pointer_to.one_past_last_token == pointer_fresh_compound.declaration_properties.type_inst.pointer_to.one_past_last_token);
	pointer_type_name := pointer_compound.declaration_properties.type_inst.pointer_to.type_valued_expression.(*Extended.Parser_Ident);
	assert(pointer_type_name.resolved_declaration == pointer_statements[2].(*Extended.Parser_Declaration));
	assert(pointer_fresh_compound.declaration_properties.type_inst.pointer_to.type_valued_expression.(*Extended.Parser_Ident).resolved_declaration == pointer_fresh_statements[2].(*Extended.Parser_Declaration));
	assert(pointer_statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == pointer_compound.declaration_properties);
	assert(pointer_fresh_statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == pointer_fresh_compound.declaration_properties);
	assert(pointer_updated.diagnostics.count == pointer_fresh.diagnostics.count && pointer_updated.restart_points.count == pointer_fresh.restart_points.count);
	Extended.release_parser_tree(*pointer_old);
	Extended.release_parser_names(*pointer_old);
	free(pointer_old_source);
	assert(pointer_type_name.name == "Target" && Extended.reconstruct_source(*pointer_updated) == pointer_new_source);
	Extended.release_parser_tree(*pointer_updated);
	Extended.release_parser_names(*pointer_updated);
	Extended.release_parser_tree(*pointer_fresh);
	Extended.release_parser_names(*pointer_fresh);
	free(pointer_new_source);

	double_old_source := copy_string(			  "left, right: **Target; Target :: 1; use := right;");
	double_new_source := copy_string("added :: 0;\nleft, right: **Target; Target :: 1; use := right;");
	double_old := Extended.parse_file(double_old_source);
	double_updated, double_ok := Extended.parse_file_edit(*double_old, 0, 0, double_new_source);
	double_fresh := Extended.parse_file(double_new_source);
	assert(double_ok && double_old.status == .COMPLETE && double_updated.status == .COMPLETE && double_fresh.status == .COMPLETE);
	double_statements := double_updated.root.(*Extended.Parser_Block).statements;
	double_fresh_statements := double_fresh.root.(*Extended.Parser_Block).statements;
	double_probe_tokens := Extended.materialise_tokens(double_new_source);
	double_probe := Extended.Parser.{parsed=*double_probe_tokens, edit_source=*double_old, cursor=double_statements[1].first_token.(s64)};
	set_allocators(*double_probe_tokens.node_pool, context.default_allocator);
	double_probe.current_scope = Extended.push_lexical_scope(*double_probe);
	double_probe_tokens.root = Extended.reuse_simple_declaration(*double_probe);
	assert(double_probe_tokens.root && double_probe_tokens.root.kind == .COMPOUND_DECLARATION);
	assert(double_probe.current_scope.bindings.count == 2 && double_probe.current_scope.references.count == 1);
	Extended.release_parser_tree(*double_probe_tokens);
	Extended.release_parser_names(*double_probe_tokens);
	double_compound := double_statements[1].(*Extended.Parser_Compound_Declaration);
	double_fresh_compound := double_fresh_statements[1].(*Extended.Parser_Compound_Declaration);
	assert(!double_compound.declaration_properties.expression && !double_fresh_compound.declaration_properties.expression);
	assert(double_compound.first_token == double_fresh_compound.first_token && double_compound.one_past_last_token == double_fresh_compound.one_past_last_token);
	double_type := double_compound.declaration_properties.type_inst;
	double_fresh_type := double_fresh_compound.declaration_properties.type_inst;
	assert(double_type.first_token == double_fresh_type.first_token && double_type.one_past_last_token == double_fresh_type.one_past_last_token);
	assert(double_type.l0 == double_fresh_type.l0 && double_type.c0 == double_fresh_type.c0 && double_type.l1 == double_fresh_type.l1 && double_type.c1 == double_fresh_type.c1);
	assert(double_type.pointer_to.first_token == double_fresh_type.pointer_to.first_token && double_type.pointer_to.one_past_last_token == double_fresh_type.pointer_to.one_past_last_token);
	assert(double_type.pointer_to.l0 == double_fresh_type.pointer_to.l0 && double_type.pointer_to.c0 == double_fresh_type.pointer_to.c0);
	assert(double_type.pointer_to.l1 == double_fresh_type.pointer_to.l1 && double_type.pointer_to.c1 == double_fresh_type.pointer_to.c1);
	assert(double_type.pointer_to.pointer_to.first_token == double_fresh_type.pointer_to.pointer_to.first_token);
	assert(double_type.pointer_to.pointer_to.one_past_last_token == double_fresh_type.pointer_to.pointer_to.one_past_last_token);
	double_type_name := double_type.pointer_to.pointer_to.type_valued_expression.(*Extended.Parser_Ident);
	assert(double_type_name.resolved_declaration == double_statements[2].(*Extended.Parser_Declaration));
	assert(double_fresh_type.pointer_to.pointer_to.type_valued_expression.(*Extended.Parser_Ident).resolved_declaration == double_fresh_statements[2].(*Extended.Parser_Declaration));
	assert(double_statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == double_compound.declaration_properties);
	assert(double_fresh_statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == double_fresh_compound.declaration_properties);
	assert(double_updated.diagnostics.count == double_fresh.diagnostics.count && double_updated.restart_points.count == double_fresh.restart_points.count);
	Extended.release_parser_tree(*double_old);
	Extended.release_parser_names(*double_old);
	free(double_old_source);
	assert(double_type_name.name == "Target" && Extended.reconstruct_source(*double_updated) == double_new_source);
	Extended.release_parser_tree(*double_updated);
	Extended.release_parser_names(*double_updated);
	Extended.release_parser_tree(*double_fresh);
	Extended.release_parser_names(*double_fresh);
	free(double_new_source);

	array_old_source := copy_string(			 "left, right: [size]Target; size :: 4; Target :: u8; use := right;");
	array_new_source := copy_string("added :: 0;\nleft, right: [size]Target; size :: 4; Target :: u8; use := right;");
	array_old := Extended.parse_file(array_old_source);
	array_updated, array_ok := Extended.parse_file_edit(*array_old, 0, 0, array_new_source);
	array_fresh := Extended.parse_file(array_new_source);
	assert(array_ok && array_old.status == .COMPLETE && array_updated.status == .COMPLETE && array_fresh.status == .COMPLETE);
	array_statements := array_updated.root.(*Extended.Parser_Block).statements;
	array_fresh_statements := array_fresh.root.(*Extended.Parser_Block).statements;
	array_probe_tokens := Extended.materialise_tokens(array_new_source);
	array_probe := Extended.Parser.{parsed=*array_probe_tokens, edit_source=*array_old, cursor=array_statements[1].first_token.(s64)};
	set_allocators(*array_probe_tokens.node_pool, context.default_allocator);
	array_probe.current_scope = Extended.push_lexical_scope(*array_probe);
	array_probe_tokens.root = Extended.reuse_simple_declaration(*array_probe);
	assert(array_probe_tokens.root && array_probe_tokens.root.kind == .COMPOUND_DECLARATION);
	assert(array_probe.current_scope.bindings.count == 2 && array_probe.current_scope.references.count == 2);
	Extended.release_parser_tree(*array_probe_tokens);
	Extended.release_parser_names(*array_probe_tokens);
	array_compound := array_statements[1].(*Extended.Parser_Compound_Declaration);
	array_fresh_compound := array_fresh_statements[1].(*Extended.Parser_Compound_Declaration);
	assert(!array_compound.declaration_properties.expression && !array_fresh_compound.declaration_properties.expression);
	assert(array_compound.first_token == array_fresh_compound.first_token && array_compound.one_past_last_token == array_fresh_compound.one_past_last_token);
	array_type := array_compound.declaration_properties.type_inst;
	array_fresh_type := array_fresh_compound.declaration_properties.type_inst;
	assert(array_type.first_token == array_fresh_type.first_token && array_type.one_past_last_token == array_fresh_type.one_past_last_token);
	assert(array_type.l0 == array_fresh_type.l0 && array_type.c0 == array_fresh_type.c0 && array_type.l1 == array_fresh_type.l1 && array_type.c1 == array_fresh_type.c1);
	array_size := array_type.array_dimension.(*Extended.Parser_Ident);
	assert(array_size.first_token == array_fresh_type.array_dimension.first_token && array_size.one_past_last_token == array_fresh_type.array_dimension.one_past_last_token);
	assert(array_size.resolved_declaration == array_statements[2].(*Extended.Parser_Declaration));
	assert(array_fresh_type.array_dimension.(*Extended.Parser_Ident).resolved_declaration == array_fresh_statements[2].(*Extended.Parser_Declaration));
	array_type_name := array_type.array_element_type.type_valued_expression.(*Extended.Parser_Ident);
	assert(array_type_name.resolved_declaration == array_statements[3].(*Extended.Parser_Declaration));
	assert(array_fresh_type.array_element_type.type_valued_expression.(*Extended.Parser_Ident).resolved_declaration == array_fresh_statements[3].(*Extended.Parser_Declaration));
	assert(array_statements[4].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == array_compound.declaration_properties);
	assert(array_fresh_statements[4].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == array_fresh_compound.declaration_properties);
	assert(array_updated.diagnostics.count == array_fresh.diagnostics.count && array_updated.restart_points.count == array_fresh.restart_points.count);
	Extended.release_parser_tree(*array_old);
	Extended.release_parser_names(*array_old);
	free(array_old_source);
	assert(array_size.name == "size" && array_type_name.name == "Target" && Extended.reconstruct_source(*array_updated) == array_new_source);
	Extended.release_parser_tree(*array_updated);
	Extended.release_parser_names(*array_updated);
	Extended.release_parser_tree(*array_fresh);
	Extended.release_parser_names(*array_fresh);
	free(array_new_source);

	dimension_old_source := copy_string(			 "size :: 1; Target :: s64; left, right: [size + 1]Target; main :: () { use_left := left; use_right := right; }");
	dimension_new_source := copy_string("added :: 0;\nsize :: 1; Target :: s64; left, right: [size + 1]Target; main :: () { use_left := left; use_right := right; }");
	dimension_old := Extended.parse_file(dimension_old_source);
	dimension_updated, dimension_ok := Extended.parse_file_edit(*dimension_old, 0, 0, dimension_new_source);
	dimension_fresh := Extended.parse_file(dimension_new_source);
	assert(dimension_ok && dimension_old.status == .COMPLETE && dimension_updated.status == .COMPLETE && dimension_fresh.status == .COMPLETE);
	dimension_statements := dimension_updated.root.(*Extended.Parser_Block).statements;
	dimension_fresh_statements := dimension_fresh.root.(*Extended.Parser_Block).statements;
	dimension_tokens := Extended.materialise_tokens(dimension_new_source);
	dimension_probe := Extended.Parser.{parsed=*dimension_tokens, edit_source=*dimension_old, cursor=dimension_statements[3].first_token.(s64)};
	set_allocators(*dimension_tokens.node_pool, context.default_allocator);
	dimension_probe.current_scope = Extended.push_lexical_scope(*dimension_probe);
	dimension_tokens.root = Extended.reuse_simple_declaration(*dimension_probe);
	assert(dimension_tokens.root && dimension_tokens.root.kind == .COMPOUND_DECLARATION);
	assert(dimension_probe.current_scope.bindings.count == 2 && dimension_probe.current_scope.references.count == 2);
	Extended.release_parser_tree(*dimension_tokens);
	Extended.release_parser_names(*dimension_tokens);
	dimension_compound := dimension_statements[3].(*Extended.Parser_Compound_Declaration);
	dimension_fresh_compound := dimension_fresh_statements[3].(*Extended.Parser_Compound_Declaration);
	dimension_type := dimension_compound.declaration_properties.type_inst;
	dimension_fresh_type := dimension_fresh_compound.declaration_properties.type_inst;
	assert(!dimension_compound.declaration_properties.expression && !dimension_fresh_compound.declaration_properties.expression);
	assert(dimension_compound.first_token == dimension_fresh_compound.first_token && dimension_compound.one_past_last_token == dimension_fresh_compound.one_past_last_token);
	assert(dimension_type.first_token == dimension_fresh_type.first_token && dimension_type.one_past_last_token == dimension_fresh_type.one_past_last_token);
	assert(dimension_type.l0 == dimension_fresh_type.l0 && dimension_type.c0 == dimension_fresh_type.c0 && dimension_type.l1 == dimension_fresh_type.l1 && dimension_type.c1 == dimension_fresh_type.c1);
	dimension_expression := dimension_type.array_dimension.(*Extended.Parser_Binary_Operator);
	dimension_fresh_expression := dimension_fresh_type.array_dimension.(*Extended.Parser_Binary_Operator);
	assert(dimension_expression.operator_type == #char "+" && dimension_expression.operator_type == dimension_fresh_expression.operator_type);
	assert(dimension_expression.first_token == dimension_fresh_expression.first_token && dimension_expression.one_past_last_token == dimension_fresh_expression.one_past_last_token);
	assert(
		dimension_expression.l0 == dimension_fresh_expression.l0
		&& dimension_expression.c0 == dimension_fresh_expression.c0
		&& dimension_expression.l1 == dimension_fresh_expression.l1
		&& dimension_expression.c1 == dimension_fresh_expression.c1
	);
	dimension_name := dimension_expression.left.(*Extended.Parser_Ident);
	assert(dimension_name.resolved_declaration == dimension_statements[1].(*Extended.Parser_Declaration));
	assert(dimension_fresh_expression.left.(*Extended.Parser_Ident).resolved_declaration == dimension_fresh_statements[1].(*Extended.Parser_Declaration));
	assert(dimension_expression.right.(*Extended.Parser_Literal)._u64 == 1 && dimension_fresh_expression.right.(*Extended.Parser_Literal)._u64 == 1);
	dimension_type_name := dimension_type.array_element_type.type_valued_expression.(*Extended.Parser_Ident);
	assert(dimension_type_name.resolved_declaration == dimension_statements[2].(*Extended.Parser_Declaration));
	assert(dimension_fresh_type.array_element_type.type_valued_expression.(*Extended.Parser_Ident).resolved_declaration == dimension_fresh_statements[2].(*Extended.Parser_Declaration));
	dimension_body := dimension_statements[4].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block;
	dimension_fresh_body := dimension_fresh_statements[4].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block;
	for 0..1 {
		assert(dimension_body.statements[it].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == dimension_compound.declaration_properties);
		assert(dimension_fresh_body.statements[it].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == dimension_fresh_compound.declaration_properties);
	}

	assert(dimension_updated.diagnostics.count == dimension_fresh.diagnostics.count && dimension_updated.restart_points.count == dimension_fresh.restart_points.count);
	Extended.release_parser_tree(*dimension_old);
	Extended.release_parser_names(*dimension_old);
	free(dimension_old_source);
	assert(dimension_name.name == "size" && dimension_type_name.name == "Target" && Extended.reconstruct_source(*dimension_updated) == dimension_new_source);
	Extended.release_parser_tree(*dimension_updated);
	Extended.release_parser_names(*dimension_updated);
	Extended.release_parser_tree(*dimension_fresh);
	Extended.release_parser_names(*dimension_fresh);
	free(dimension_new_source);

	resizable_old_source := copy_string(			 "Target :: s64; left, right: [..]Target; main :: () { use := right; }");
	resizable_new_source := copy_string("added :: 0;\nTarget :: s64; left, right: [..]Target; main :: () { use := right; }");
	resizable_old := Extended.parse_file(resizable_old_source);
	resizable_updated, resizable_ok := Extended.parse_file_edit(*resizable_old, 0, 0, resizable_new_source);
	resizable_fresh := Extended.parse_file(resizable_new_source);
	assert(resizable_ok && resizable_old.status == .COMPLETE && resizable_updated.status == .COMPLETE && resizable_fresh.status == .COMPLETE);
	resizable_statements := resizable_updated.root.(*Extended.Parser_Block).statements;
	resizable_fresh_statements := resizable_fresh.root.(*Extended.Parser_Block).statements;
	resizable_tokens := Extended.materialise_tokens(resizable_new_source);
	resizable_probe := Extended.Parser.{parsed=*resizable_tokens, edit_source=*resizable_old, cursor=resizable_statements[2].first_token.(s64)};
	set_allocators(*resizable_tokens.node_pool, context.default_allocator);
	resizable_probe.current_scope = Extended.push_lexical_scope(*resizable_probe);
	resizable_tokens.root = Extended.reuse_simple_declaration(*resizable_probe);
	assert(resizable_tokens.root && resizable_tokens.root.kind == .COMPOUND_DECLARATION);
	assert(resizable_probe.current_scope.bindings.count == 2 && resizable_probe.current_scope.references.count == 1);
	Extended.release_parser_tree(*resizable_tokens);
	Extended.release_parser_names(*resizable_tokens);
	resizable_compound := resizable_statements[2].(*Extended.Parser_Compound_Declaration);
	resizable_fresh_compound := resizable_fresh_statements[2].(*Extended.Parser_Compound_Declaration);
	resizable_type := resizable_compound.declaration_properties.type_inst;
	resizable_fresh_type := resizable_fresh_compound.declaration_properties.type_inst;
	assert(!resizable_compound.declaration_properties.expression && !resizable_fresh_compound.declaration_properties.expression);
	assert(resizable_type.inst_flags == .RESIZABLE && resizable_type.inst_flags == resizable_fresh_type.inst_flags);
	assert(resizable_compound.first_token == resizable_fresh_compound.first_token && resizable_compound.one_past_last_token == resizable_fresh_compound.one_past_last_token);
	assert(resizable_type.first_token == resizable_fresh_type.first_token && resizable_type.one_past_last_token == resizable_fresh_type.one_past_last_token);
	assert(resizable_type.l0 == resizable_fresh_type.l0 && resizable_type.c0 == resizable_fresh_type.c0 && resizable_type.l1 == resizable_fresh_type.l1 && resizable_type.c1 == resizable_fresh_type.c1);
	assert(
		resizable_type.array_element_type.first_token == resizable_fresh_type.array_element_type.first_token
		&& resizable_type.array_element_type.one_past_last_token == resizable_fresh_type.array_element_type.one_past_last_token
	);
	assert(
		resizable_type.array_element_type.l0 == resizable_fresh_type.array_element_type.l0
		&& resizable_type.array_element_type.c0 == resizable_fresh_type.array_element_type.c0
		&& resizable_type.array_element_type.l1 == resizable_fresh_type.array_element_type.l1
		&& resizable_type.array_element_type.c1 == resizable_fresh_type.array_element_type.c1
	);
	resizable_name := resizable_type.array_element_type.type_valued_expression.(*Extended.Parser_Ident);
	assert(resizable_name.resolved_declaration == resizable_statements[1].(*Extended.Parser_Declaration));
	assert(resizable_fresh_type.array_element_type.type_valued_expression.(*Extended.Parser_Ident).resolved_declaration == resizable_fresh_statements[1].(*Extended.Parser_Declaration));
	resizable_body := resizable_statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block;
	resizable_fresh_body := resizable_fresh_statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block;
	assert(resizable_body.statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == resizable_compound.declaration_properties);
	assert(resizable_fresh_body.statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == resizable_fresh_compound.declaration_properties);
	assert(resizable_updated.diagnostics.count == resizable_fresh.diagnostics.count && resizable_updated.restart_points.count == resizable_fresh.restart_points.count);
	Extended.release_parser_tree(*resizable_old);
	Extended.release_parser_names(*resizable_old);
	free(resizable_old_source);
	assert(resizable_name.name == "Target" && resizable_compound.comma_separated_assignment.arguments[1].node.(*Extended.Parser_Ident).name == "right");
	assert(Extended.reconstruct_source(*resizable_updated) == resizable_new_source);
	Extended.release_parser_tree(*resizable_updated);
	Extended.release_parser_names(*resizable_updated);
	Extended.release_parser_tree(*resizable_fresh);
	Extended.release_parser_names(*resizable_fresh);
	free(resizable_new_source);

	view_old_source := copy_string(				"Target :: s64; left, right: []Target; main :: () { use_left := left; use_right := right; }");
	view_new_source := copy_string("added :: 0;\nTarget :: s64; left, right: []Target; main :: () { use_left := left; use_right := right; }");
	view_old := Extended.parse_file(view_old_source);
	view_updated, view_ok := Extended.parse_file_edit(*view_old, 0, 0, view_new_source);
	view_fresh := Extended.parse_file(view_new_source);
	assert(view_ok && view_old.status == .COMPLETE && view_updated.status == .COMPLETE && view_fresh.status == .COMPLETE);
	view_statements := view_updated.root.(*Extended.Parser_Block).statements;
	view_fresh_statements := view_fresh.root.(*Extended.Parser_Block).statements;
	view_tokens := Extended.materialise_tokens(view_new_source);
	view_probe := Extended.Parser.{parsed=*view_tokens, edit_source=*view_old, cursor=view_statements[2].first_token.(s64)};
	set_allocators(*view_tokens.node_pool, context.default_allocator);
	view_probe.current_scope = Extended.push_lexical_scope(*view_probe);
	view_tokens.root = Extended.reuse_simple_declaration(*view_probe);
	assert(view_tokens.root && view_tokens.root.kind == .COMPOUND_DECLARATION);
	assert(view_probe.current_scope.bindings.count == 2 && view_probe.current_scope.references.count == 1);
	Extended.release_parser_tree(*view_tokens);
	Extended.release_parser_names(*view_tokens);
	view_compound := view_statements[2].(*Extended.Parser_Compound_Declaration);
	view_fresh_compound := view_fresh_statements[2].(*Extended.Parser_Compound_Declaration);
	view_type := view_compound.declaration_properties.type_inst;
	view_fresh_type := view_fresh_compound.declaration_properties.type_inst;
	assert(!view_compound.declaration_properties.expression && !view_fresh_compound.declaration_properties.expression);
	assert(view_type.inst_flags == .ARRAY_VIEW && view_type.inst_flags == view_fresh_type.inst_flags && !view_type.array_dimension);
	assert(view_compound.first_token == view_fresh_compound.first_token && view_compound.one_past_last_token == view_fresh_compound.one_past_last_token);
	assert(view_type.first_token == view_fresh_type.first_token && view_type.one_past_last_token == view_fresh_type.one_past_last_token);
	assert(view_type.l0 == view_fresh_type.l0 && view_type.c0 == view_fresh_type.c0 && view_type.l1 == view_fresh_type.l1 && view_type.c1 == view_fresh_type.c1);
	assert(view_type.array_element_type.first_token == view_fresh_type.array_element_type.first_token && view_type.array_element_type.one_past_last_token == view_fresh_type.array_element_type.one_past_last_token);
	assert(
		view_type.array_element_type.l0 == view_fresh_type.array_element_type.l0
		&& view_type.array_element_type.c0 == view_fresh_type.array_element_type.c0
		&& view_type.array_element_type.l1 == view_fresh_type.array_element_type.l1
		&& view_type.array_element_type.c1 == view_fresh_type.array_element_type.c1
	);
	view_name := view_type.array_element_type.type_valued_expression.(*Extended.Parser_Ident);
	assert(view_name.resolved_declaration == view_statements[1].(*Extended.Parser_Declaration));
	assert(view_fresh_type.array_element_type.type_valued_expression.(*Extended.Parser_Ident).resolved_declaration == view_fresh_statements[1].(*Extended.Parser_Declaration));
	view_body := view_statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block;
	view_fresh_body := view_fresh_statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block;
	for 0..1 {
		assert(view_body.statements[it].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == view_compound.declaration_properties);
		assert(view_fresh_body.statements[it].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == view_fresh_compound.declaration_properties);
	}

	assert(view_updated.diagnostics.count == view_fresh.diagnostics.count && view_updated.restart_points.count == view_fresh.restart_points.count);
	Extended.release_parser_tree(*view_old);
	Extended.release_parser_names(*view_old);
	free(view_old_source);
	assert(view_name.name == "Target" && view_compound.comma_separated_assignment.arguments[0].node.(*Extended.Parser_Ident).name == "left");
	assert(view_compound.comma_separated_assignment.arguments[1].node.(*Extended.Parser_Ident).name == "right");
	assert(Extended.reconstruct_source(*view_updated) == view_new_source);
	Extended.release_parser_tree(*view_updated);
	Extended.release_parser_names(*view_updated);
	Extended.release_parser_tree(*view_fresh);
	Extended.release_parser_names(*view_fresh);
	free(view_new_source);

	view_pointer_old_source := copy_string(				"Target :: s64; left, right: *[]Target; main :: () { use_left := left; use_right := right; }");
	view_pointer_new_source := copy_string("added :: 0;\nTarget :: s64; left, right: *[]Target; main :: () { use_left := left; use_right := right; }");
	view_pointer_old := Extended.parse_file(view_pointer_old_source);
	view_pointer_updated, view_pointer_ok := Extended.parse_file_edit(*view_pointer_old, 0, 0, view_pointer_new_source);
	view_pointer_fresh := Extended.parse_file(view_pointer_new_source);
	assert(view_pointer_ok && view_pointer_old.status == .COMPLETE && view_pointer_updated.status == .COMPLETE && view_pointer_fresh.status == .COMPLETE);
	view_pointer_statements := view_pointer_updated.root.(*Extended.Parser_Block).statements;
	view_pointer_fresh_statements := view_pointer_fresh.root.(*Extended.Parser_Block).statements;
	view_pointer_tokens := Extended.materialise_tokens(view_pointer_new_source);
	view_pointer_probe := Extended.Parser.{parsed=*view_pointer_tokens, edit_source=*view_pointer_old, cursor=view_pointer_statements[2].first_token.(s64)};
	set_allocators(*view_pointer_tokens.node_pool, context.default_allocator);
	view_pointer_probe.current_scope = Extended.push_lexical_scope(*view_pointer_probe);
	view_pointer_tokens.root = Extended.reuse_simple_declaration(*view_pointer_probe);
	assert(view_pointer_tokens.root && view_pointer_tokens.root.kind == .COMPOUND_DECLARATION);
	assert(view_pointer_probe.current_scope.bindings.count == 2 && view_pointer_probe.current_scope.references.count == 1);
	Extended.release_parser_tree(*view_pointer_tokens);
	Extended.release_parser_names(*view_pointer_tokens);
	view_pointer_compound := view_pointer_statements[2].(*Extended.Parser_Compound_Declaration);
	view_pointer_fresh_compound := view_pointer_fresh_statements[2].(*Extended.Parser_Compound_Declaration);
	view_pointer_type := view_pointer_compound.declaration_properties.type_inst;
	view_pointer_fresh_type := view_pointer_fresh_compound.declaration_properties.type_inst;
	assert(!view_pointer_compound.declaration_properties.expression && !view_pointer_fresh_compound.declaration_properties.expression);
	assert(view_pointer_type.pointer_to && view_pointer_type.pointer_to.inst_flags == .ARRAY_VIEW && !view_pointer_type.pointer_to.array_dimension);
	assert(view_pointer_compound.first_token == view_pointer_fresh_compound.first_token && view_pointer_compound.one_past_last_token == view_pointer_fresh_compound.one_past_last_token);
	assert(view_pointer_type.first_token == view_pointer_fresh_type.first_token && view_pointer_type.one_past_last_token == view_pointer_fresh_type.one_past_last_token);
	assert(
		view_pointer_type.l0 == view_pointer_fresh_type.l0
		&& view_pointer_type.c0 == view_pointer_fresh_type.c0
		&& view_pointer_type.l1 == view_pointer_fresh_type.l1
		&& view_pointer_type.c1 == view_pointer_fresh_type.c1
	);
	view_pointer_view := view_pointer_type.pointer_to;
	view_pointer_fresh_view := view_pointer_fresh_type.pointer_to;
	assert(view_pointer_view.first_token == view_pointer_fresh_view.first_token && view_pointer_view.one_past_last_token == view_pointer_fresh_view.one_past_last_token);
	assert(
		view_pointer_view.l0 == view_pointer_fresh_view.l0
		&& view_pointer_view.c0 == view_pointer_fresh_view.c0
		&& view_pointer_view.l1 == view_pointer_fresh_view.l1
		&& view_pointer_view.c1 == view_pointer_fresh_view.c1
	);
	assert(
		view_pointer_view.array_element_type.first_token == view_pointer_fresh_view.array_element_type.first_token
		&& view_pointer_view.array_element_type.one_past_last_token == view_pointer_fresh_view.array_element_type.one_past_last_token
	);
	view_pointer_name := view_pointer_view.array_element_type.type_valued_expression.(*Extended.Parser_Ident);
	assert(view_pointer_name.resolved_declaration == view_pointer_statements[1].(*Extended.Parser_Declaration));
	assert(view_pointer_fresh_view.array_element_type.type_valued_expression.(*Extended.Parser_Ident).resolved_declaration == view_pointer_fresh_statements[1].(*Extended.Parser_Declaration));
	view_pointer_body := view_pointer_statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block;
	view_pointer_fresh_body := view_pointer_fresh_statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block;
	for 0..1 {
		assert(view_pointer_body.statements[it].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == view_pointer_compound.declaration_properties);
		assert(view_pointer_fresh_body.statements[it].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == view_pointer_fresh_compound.declaration_properties);
	}

	assert(view_pointer_updated.diagnostics.count == view_pointer_fresh.diagnostics.count && view_pointer_updated.restart_points.count == view_pointer_fresh.restart_points.count);
	Extended.release_parser_tree(*view_pointer_old);
	Extended.release_parser_names(*view_pointer_old);
	free(view_pointer_old_source);
	assert(view_pointer_name.name == "Target" && view_pointer_compound.comma_separated_assignment.arguments[0].node.(*Extended.Parser_Ident).name == "left");
	assert(view_pointer_compound.comma_separated_assignment.arguments[1].node.(*Extended.Parser_Ident).name == "right");
	assert(Extended.reconstruct_source(*view_pointer_updated) == view_pointer_new_source);
	Extended.release_parser_tree(*view_pointer_updated);
	Extended.release_parser_names(*view_pointer_updated);
	Extended.release_parser_tree(*view_pointer_fresh);
	Extended.release_parser_names(*view_pointer_fresh);
	free(view_pointer_new_source);
	check_compound_reuse_fallback("left, right: (s64) -> s64; main :: () { use_left := left; use_right := right; }", true);
	check_compound_reuse_fallback("left, right: type_of(1); main :: () { use_left := left; use_right := right; }", false, true);
	check_compound_reuse_fallback("left, right: s64 = ---; main :: () { use_left := left; use_right := right; }", false, false, true);
}

test_compound_ast_reuse :: () {
	old_source := copy_string(			   "left, right :: value; value :: 1; sum := left + right;");
	new_source := copy_string("added :: 2;\nleft, right :: value; value :: 1; sum := left + right;");
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && updated.status == .COMPLETE && fresh.status == .COMPLETE);

	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, cursor=updated.root.(*Extended.Parser_Block).statements[1].first_token.(s64)};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root && probe_tokens.root.kind == .COMPOUND_DECLARATION);
	assert(probe.current_scope.bindings.count == 2 && probe.current_scope.references.count == 1);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);

	statements := updated.root.(*Extended.Parser_Block).statements;
	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	compound := statements[1].(*Extended.Parser_Compound_Declaration);
	fresh_compound := fresh_statements[1].(*Extended.Parser_Compound_Declaration);
	assert(compound.first_token == fresh_compound.first_token && compound.one_past_last_token == fresh_compound.one_past_last_token);
	assert(compound.comma_separated_assignment.arguments.count == 2);
	for compound.comma_separated_assignment.arguments {
		other := fresh_compound.comma_separated_assignment.arguments[it_index];
		assert(it.node.first_token == other.node.first_token && it.node.one_past_last_token == other.node.one_past_last_token);
		assert(it.node.(*Extended.Parser_Ident).name == other.node.(*Extended.Parser_Ident).name);
	}

	assert(compound.declaration_properties.expression.(*Extended.Parser_Ident).resolved_declaration == statements[2].(*Extended.Parser_Declaration));
	assert(fresh_compound.declaration_properties.expression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[2].(*Extended.Parser_Declaration));
	sum := statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Binary_Operator);
	fresh_sum := fresh_statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Binary_Operator);
	assert(sum.left.(*Extended.Parser_Ident).resolved_declaration == compound.declaration_properties);
	assert(sum.right.(*Extended.Parser_Ident).resolved_declaration == compound.declaration_properties);
	assert(fresh_sum.left.(*Extended.Parser_Ident).resolved_declaration == fresh_compound.declaration_properties);
	assert(fresh_sum.right.(*Extended.Parser_Ident).resolved_declaration == fresh_compound.declaration_properties);
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	assert_eligible_edit_matches_fresh(*updated, *fresh);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(compound.comma_separated_assignment.arguments[0].node.(*Extended.Parser_Ident).name == "left");
	assert(Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);
	check_compound_reuse_fallback("left, right :: 1; @Serializable");
	check_compound_reuse_fallback("left, right :: 1; @Tag(1)", false, false, false, "Tag(1)");
	check_compound_reuse_fallback("left, right: s64 #align 16; main :: () { use_left := left; use_right := right; }", false, false, false, "", 16);
}

test_compound_reassignment_ast_reuse :: () {
	old_source := copy_string(			   "left :: 1; right :: 2; left, right = value; value :: 3; use := left;");
	new_source := copy_string("added :: 0;\nleft :: 1; right :: 2; left, right = value; value :: 3; use := left;");
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && updated.status == .COMPLETE && fresh.status == .COMPLETE);

	statements := updated.root.(*Extended.Parser_Block).statements;
	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, cursor=statements[3].first_token.(s64)};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root && probe_tokens.root.kind == .COMPOUND_DECLARATION);
	assert(probe.current_scope.bindings.count == 0 && probe.current_scope.references.count == 1);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);

	compound := statements[3].(*Extended.Parser_Compound_Declaration);
	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	fresh_compound := fresh_statements[3].(*Extended.Parser_Compound_Declaration);
	assert(compound.operator_type == #char "=" && fresh_compound.operator_type == #char "=");
	assert(compound.first_token == fresh_compound.first_token && compound.one_past_last_token == fresh_compound.one_past_last_token);
	assert(compound.comma_separated_assignment.one_past_last_token == fresh_compound.comma_separated_assignment.one_past_last_token);
	for compound.comma_separated_assignment.arguments {
		other := fresh_compound.comma_separated_assignment.arguments[it_index];
		assert(it.node.first_token == other.node.first_token && it.node.one_past_last_token == other.node.one_past_last_token);
		assert(it.node.(*Extended.Parser_Ident).name == other.node.(*Extended.Parser_Ident).name);
	}

	value_name := compound.declaration_properties.expression.(*Extended.Parser_Ident);
	assert(value_name.resolved_declaration == statements[4].(*Extended.Parser_Declaration));
	assert(fresh_compound.declaration_properties.expression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[4].(*Extended.Parser_Declaration));
	assert(statements[5].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == statements[1].(*Extended.Parser_Declaration));
	assert(fresh_statements[5].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[1].(*Extended.Parser_Declaration));
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(value_name.name == "value" && Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);

	three_old_source := copy_string(			 "a :: 1; b :: 2; c :: 3; a, b, c = value; value :: 4; use := c;");
	three_new_source := copy_string("added :: 0;\na :: 1; b :: 2; c :: 3; a, b, c = value; value :: 4; use := c;");
	three_old := Extended.parse_file(three_old_source);
	three_updated, three_ok := Extended.parse_file_edit(*three_old, 0, 0, three_new_source);
	three_fresh := Extended.parse_file(three_new_source);
	assert(three_ok && three_updated.status == .COMPLETE && three_fresh.status == .COMPLETE);
	three_statements := three_updated.root.(*Extended.Parser_Block).statements;
	three_probe_tokens := Extended.materialise_tokens(three_new_source);
	three_probe := Extended.Parser.{parsed=*three_probe_tokens, edit_source=*three_old, cursor=three_statements[4].first_token.(s64)};
	set_allocators(*three_probe_tokens.node_pool, context.default_allocator);
	three_probe.current_scope = Extended.push_lexical_scope(*three_probe);
	three_probe_tokens.root = Extended.reuse_simple_declaration(*three_probe);
	assert(three_probe_tokens.root && three_probe.current_scope.bindings.count == 0 && three_probe.current_scope.references.count == 1);
	Extended.release_parser_tree(*three_probe_tokens);
	Extended.release_parser_names(*three_probe_tokens);
	three_compound := three_statements[4].(*Extended.Parser_Compound_Declaration);
	three_fresh_statements := three_fresh.root.(*Extended.Parser_Block).statements;
	three_fresh_compound := three_fresh_statements[4].(*Extended.Parser_Compound_Declaration);
	assert(three_compound.comma_separated_assignment.arguments.count == 3);
	assert(three_compound.comma_separated_assignment.one_past_last_token == three_fresh_compound.comma_separated_assignment.one_past_last_token);
	for three_compound.comma_separated_assignment.arguments {
		other := three_fresh_compound.comma_separated_assignment.arguments[it_index];
		assert(it.node.first_token == other.node.first_token && it.node.one_past_last_token == other.node.one_past_last_token);
		assert(!it.node.(*Extended.Parser_Ident).resolved_declaration && !other.node.(*Extended.Parser_Ident).resolved_declaration);
	}

	assert(three_compound.declaration_properties.expression.(*Extended.Parser_Ident).resolved_declaration == three_statements[5].(*Extended.Parser_Declaration));
	assert(three_fresh_compound.declaration_properties.expression.(*Extended.Parser_Ident).resolved_declaration == three_fresh_statements[5].(*Extended.Parser_Declaration));
	assert(three_statements[6].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == three_statements[3].(*Extended.Parser_Declaration));
	assert(three_updated.diagnostics.count == three_fresh.diagnostics.count && three_updated.restart_points.count == three_fresh.restart_points.count);
	Extended.release_parser_tree(*three_old);
	Extended.release_parser_names(*three_old);
	free(three_old_source);
	assert(three_compound.comma_separated_assignment.arguments[2].node.(*Extended.Parser_Ident).name == "c");
	assert(Extended.reconstruct_source(*three_updated) == three_new_source);
	Extended.release_parser_tree(*three_updated);
	Extended.release_parser_names(*three_updated);
	Extended.release_parser_tree(*three_fresh);
	Extended.release_parser_names(*three_fresh);
	free(three_new_source);
	check_compound_reuse_fallback("left:, right = value;");

	mixed_old_source := copy_string(			 "right := 2; value :: 3; left:, right = value; use_left := left; use_right := right;");
	mixed_new_source := copy_string("added :: 0;\nright := 2; value :: 3; left:, right = value; use_left := left; use_right := right;");
	mixed_old := Extended.parse_file(mixed_old_source);
	mixed_updated, mixed_ok := Extended.parse_file_edit(*mixed_old, 0, 0, mixed_new_source);
	mixed_fresh := Extended.parse_file(mixed_new_source);
	assert(mixed_ok && mixed_old.status == .COMPLETE && mixed_updated.status == .COMPLETE && mixed_fresh.status == .COMPLETE);
	mixed_statements := mixed_updated.root.(*Extended.Parser_Block).statements;
	mixed_fresh_statements := mixed_fresh.root.(*Extended.Parser_Block).statements;
	mixed_tokens := Extended.materialise_tokens(mixed_new_source);
	mixed_probe := Extended.Parser.{parsed=*mixed_tokens, edit_source=*mixed_old, cursor=mixed_statements[3].first_token.(s64)};
	set_allocators(*mixed_tokens.node_pool, context.default_allocator);
	mixed_probe.current_scope = Extended.push_lexical_scope(*mixed_probe);
	assert(Extended.reuse_simple_declaration(*mixed_probe) == null);
	Extended.release_parser_tree(*mixed_tokens);
	Extended.release_parser_names(*mixed_tokens);
	mixed_compound := mixed_statements[3].(*Extended.Parser_Compound_Declaration);
	mixed_fresh_compound := mixed_fresh_statements[3].(*Extended.Parser_Compound_Declaration);
	assert(mixed_compound.comma_separated_assignment.arguments[0].modifier == .DECLARE);
	assert(mixed_compound.comma_separated_assignment.arguments[1].modifier == .NONE);
	assert(mixed_compound.comma_separated_assignment.arguments[0].modifier == mixed_fresh_compound.comma_separated_assignment.arguments[0].modifier);
	assert(mixed_compound.comma_separated_assignment.arguments[1].modifier == mixed_fresh_compound.comma_separated_assignment.arguments[1].modifier);
	assert(mixed_compound.first_token == mixed_fresh_compound.first_token && mixed_compound.one_past_last_token == mixed_fresh_compound.one_past_last_token);
	assert(mixed_compound.declaration_properties.expression.(*Extended.Parser_Ident).resolved_declaration == mixed_statements[2].(*Extended.Parser_Declaration));
	assert(mixed_fresh_compound.declaration_properties.expression.(*Extended.Parser_Ident).resolved_declaration == mixed_fresh_statements[2].(*Extended.Parser_Declaration));
	assert(mixed_statements[4].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == mixed_compound.declaration_properties);
	assert(mixed_fresh_statements[4].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == mixed_fresh_compound.declaration_properties);
	assert(mixed_statements[5].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == mixed_statements[1].(*Extended.Parser_Declaration));
	assert(mixed_fresh_statements[5].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == mixed_fresh_statements[1].(*Extended.Parser_Declaration));
	assert(mixed_updated.diagnostics.count == mixed_fresh.diagnostics.count && mixed_updated.restart_points.count == mixed_fresh.restart_points.count);
	Extended.release_parser_tree(*mixed_old);
	Extended.release_parser_names(*mixed_old);
	free(mixed_old_source);
	assert(mixed_compound.comma_separated_assignment.arguments[0].node.(*Extended.Parser_Ident).name == "left");
	assert(Extended.reconstruct_source(*mixed_updated) == mixed_new_source);
	Extended.release_parser_tree(*mixed_updated);
	Extended.release_parser_names(*mixed_updated);
	Extended.release_parser_tree(*mixed_fresh);
	Extended.release_parser_names(*mixed_fresh);
	free(mixed_new_source);

	member_old_source := copy_string(
					 "Container :: struct { x: s64; y: s64; }; container: Container; main :: () { container.x, container.y = 1, 2; values: [2]s64; index :: 0; values[index], values[index + 1] = 3, 4; }"
	);
	member_new_source := copy_string(
		"added :: 0;\nContainer :: struct { x: s64; y: s64; }; container: Container; main :: () { container.x, container.y = 1, 2; values: [2]s64; index :: 0; values[index], values[index + 1] = 3, 4; }"
	);
	member_old := Extended.parse_file(member_old_source);
	member_updated, member_ok := Extended.parse_file_edit(*member_old, 0, 0, member_new_source);
	member_fresh := Extended.parse_file(member_new_source);
	assert(member_ok && member_old.status == .COMPLETE && member_updated.status == .COMPLETE && member_fresh.status == .COMPLETE);
	member_statements := member_updated.root.(*Extended.Parser_Block).statements;
	member_fresh_statements := member_fresh.root.(*Extended.Parser_Block).statements;
	member_tokens := Extended.materialise_tokens(member_new_source);
	member_probe := Extended.Parser.{parsed=*member_tokens, edit_source=*member_old, cursor=member_statements[3].first_token.(s64)};
	set_allocators(*member_tokens.node_pool, context.default_allocator);
	member_probe.current_scope = Extended.push_lexical_scope(*member_probe);
	assert(Extended.reuse_simple_declaration(*member_probe) == null);
	Extended.release_parser_tree(*member_tokens);
	Extended.release_parser_names(*member_tokens);
	member_body := member_statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block;
	member_fresh_body := member_fresh_statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block;
	member_compound := member_body.statements[0].(*Extended.Parser_Compound_Declaration);
	member_fresh_compound := member_fresh_body.statements[0].(*Extended.Parser_Compound_Declaration);
	assert(member_compound.first_token == member_fresh_compound.first_token && member_compound.one_past_last_token == member_fresh_compound.one_past_last_token);
	assert(member_compound.l0 == member_fresh_compound.l0 && member_compound.c0 == member_fresh_compound.c0);
	assert(member_compound.comma_separated_assignment.arguments.count == 2);
	for member_compound.comma_separated_assignment.arguments {
		target := it.node.(*Extended.Parser_Binary_Operator);
		fresh_target := member_fresh_compound.comma_separated_assignment.arguments[it_index].node.(*Extended.Parser_Binary_Operator);
		assert(target.operator_type == #char "." && target.operator_type == fresh_target.operator_type);
		assert(target.first_token == fresh_target.first_token && target.one_past_last_token == fresh_target.one_past_last_token);
		assert(target.left.(*Extended.Parser_Ident).resolved_declaration == member_statements[2].(*Extended.Parser_Declaration));
		assert(fresh_target.left.(*Extended.Parser_Ident).resolved_declaration == member_fresh_statements[2].(*Extended.Parser_Declaration));
	}

	indexed_compound := member_body.statements[3].(*Extended.Parser_Compound_Declaration);
	indexed_fresh_compound := member_fresh_body.statements[3].(*Extended.Parser_Compound_Declaration);
	assert(indexed_compound.first_token == indexed_fresh_compound.first_token && indexed_compound.one_past_last_token == indexed_fresh_compound.one_past_last_token);
	assert(indexed_compound.l0 == indexed_fresh_compound.l0 && indexed_compound.c0 == indexed_fresh_compound.c0);
	assert(indexed_compound.comma_separated_assignment.arguments.count == 2);
	for indexed_compound.comma_separated_assignment.arguments {
		target := it.node.(*Extended.Parser_Binary_Operator);
		fresh_target := indexed_fresh_compound.comma_separated_assignment.arguments[it_index].node.(*Extended.Parser_Binary_Operator);
		assert(target.operator_type == .ARRAY_SUBSCRIPT && target.operator_type == fresh_target.operator_type);
		assert(target.first_token == fresh_target.first_token && target.one_past_last_token == fresh_target.one_past_last_token);
		assert(target.left.(*Extended.Parser_Ident).resolved_declaration == member_body.statements[1].(*Extended.Parser_Declaration));
		assert(fresh_target.left.(*Extended.Parser_Ident).resolved_declaration == member_fresh_body.statements[1].(*Extended.Parser_Declaration));
	}

	first_index := indexed_compound.comma_separated_assignment.arguments[0].node.(*Extended.Parser_Binary_Operator).right.(*Extended.Parser_Ident);
	second_index := indexed_compound.comma_separated_assignment.arguments[1].node.(*Extended.Parser_Binary_Operator).right.(*Extended.Parser_Binary_Operator).left.(*Extended.Parser_Ident);
	assert(first_index.resolved_declaration == member_body.statements[2].(*Extended.Parser_Declaration));
	assert(second_index.resolved_declaration == member_body.statements[2].(*Extended.Parser_Declaration));
	assert(
		indexed_fresh_compound.comma_separated_assignment.arguments[0].node.(*Extended.Parser_Binary_Operator).right.(*Extended.Parser_Ident).resolved_declaration
		== member_fresh_body.statements[2].(*Extended.Parser_Declaration)
	);
	assert(
		indexed_fresh_compound.comma_separated_assignment.arguments[1].node.(*Extended.Parser_Binary_Operator).right.(*Extended.Parser_Binary_Operator).left.(*Extended.Parser_Ident).resolved_declaration
		== member_fresh_body.statements[2].(*Extended.Parser_Declaration)
	);
	assert(member_updated.diagnostics.count == member_fresh.diagnostics.count && member_updated.restart_points.count == member_fresh.restart_points.count);
	Extended.release_parser_tree(*member_old);
	Extended.release_parser_names(*member_old);
	free(member_old_source);
	assert(member_compound.comma_separated_assignment.arguments[0].node.(*Extended.Parser_Binary_Operator).left.(*Extended.Parser_Ident).name == "container");
	assert(first_index.name == "index" && second_index.name == "index");
	assert(Extended.reconstruct_source(*member_updated) == member_new_source);
	Extended.release_parser_tree(*member_updated);
	Extended.release_parser_names(*member_updated);
	Extended.release_parser_tree(*member_fresh);
	Extended.release_parser_names(*member_fresh);
	free(member_new_source);

	deref_old_source := copy_string(			 "main :: () { left: s64; pointer := *left; right: s64; pointer.*, right = 1, 2; use_right := right; right=, new_value := 3; use_new := new_value; use_right_again := right; }");
	deref_new_source := copy_string("added :: 0;\nmain :: () { left: s64; pointer := *left; right: s64; pointer.*, right = 1, 2; use_right := right; right=, new_value := 3; use_new := new_value; use_right_again := right; }");
	deref_old := Extended.parse_file(deref_old_source);
	deref_updated, deref_ok := Extended.parse_file_edit(*deref_old, 0, 0, deref_new_source);
	deref_fresh := Extended.parse_file(deref_new_source);
	assert(deref_ok && deref_old.status == .COMPLETE && deref_updated.status == .COMPLETE && deref_fresh.status == .COMPLETE);
	deref_statements := deref_updated.root.(*Extended.Parser_Block).statements;
	deref_fresh_statements := deref_fresh.root.(*Extended.Parser_Block).statements;
	deref_tokens := Extended.materialise_tokens(deref_new_source);
	deref_probe := Extended.Parser.{parsed=*deref_tokens, edit_source=*deref_old, cursor=deref_statements[1].first_token.(s64)};
	set_allocators(*deref_tokens.node_pool, context.default_allocator);
	deref_probe.current_scope = Extended.push_lexical_scope(*deref_probe);
	assert(Extended.reuse_simple_declaration(*deref_probe) == null);
	Extended.release_parser_tree(*deref_tokens);
	Extended.release_parser_names(*deref_tokens);
	deref_body := deref_statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block;
	deref_fresh_body := deref_fresh_statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block;
	deref_compound := deref_body.statements[3].(*Extended.Parser_Compound_Declaration);
	deref_fresh_compound := deref_fresh_body.statements[3].(*Extended.Parser_Compound_Declaration);
	assert(deref_compound.first_token == deref_fresh_compound.first_token && deref_compound.one_past_last_token == deref_fresh_compound.one_past_last_token);
	assert(deref_compound.comma_separated_assignment.arguments.count == 2 && deref_fresh_compound.comma_separated_assignment.arguments.count == 2);
	deref_target := deref_compound.comma_separated_assignment.arguments[0].node.(*Extended.Parser_Unary_Operator);
	deref_fresh_target := deref_fresh_compound.comma_separated_assignment.arguments[0].node.(*Extended.Parser_Unary_Operator);
	assert(deref_target.operator_type == .POSTFIX_DEREFERENCE && deref_target.operator_type == deref_fresh_target.operator_type);
	assert(deref_target.first_token == deref_fresh_target.first_token && deref_target.one_past_last_token == deref_fresh_target.one_past_last_token);
	assert(deref_target.subexpression.(*Extended.Parser_Ident).resolved_declaration == deref_body.statements[1].(*Extended.Parser_Declaration));
	assert(deref_fresh_target.subexpression.(*Extended.Parser_Ident).resolved_declaration == deref_fresh_body.statements[1].(*Extended.Parser_Declaration));
	assert(deref_compound.comma_separated_assignment.arguments[1].node.first_token == deref_fresh_compound.comma_separated_assignment.arguments[1].node.first_token);
	assert(deref_body.statements[4].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == deref_body.statements[2].(*Extended.Parser_Declaration));
	assert(deref_fresh_body.statements[4].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == deref_fresh_body.statements[2].(*Extended.Parser_Declaration));
	deref_mixed := deref_body.statements[5].(*Extended.Parser_Compound_Declaration);
	deref_fresh_mixed := deref_fresh_body.statements[5].(*Extended.Parser_Compound_Declaration);
	assert(deref_mixed.first_token == deref_fresh_mixed.first_token && deref_mixed.one_past_last_token == deref_fresh_mixed.one_past_last_token);
	assert(deref_mixed.comma_separated_assignment.arguments[0].modifier == .ASSIGN && deref_mixed.comma_separated_assignment.arguments[1].modifier == .NONE);
	for deref_mixed.comma_separated_assignment.arguments {
		other := deref_fresh_mixed.comma_separated_assignment.arguments[it_index];
		assert(it.modifier == other.modifier && it.node.first_token == other.node.first_token && it.node.one_past_last_token == other.node.one_past_last_token);
	}

	assert(deref_body.statements[6].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == deref_mixed.declaration_properties);
	assert(deref_fresh_body.statements[6].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == deref_fresh_mixed.declaration_properties);
	assert(deref_body.statements[7].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == deref_body.statements[2].(*Extended.Parser_Declaration));
	assert(deref_fresh_body.statements[7].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == deref_fresh_body.statements[2].(*Extended.Parser_Declaration));
	assert(deref_updated.diagnostics.count == deref_fresh.diagnostics.count && deref_updated.restart_points.count == deref_fresh.restart_points.count);
	Extended.release_parser_tree(*deref_old);
	Extended.release_parser_names(*deref_old);
	free(deref_old_source);
	assert(deref_target.subexpression.(*Extended.Parser_Ident).name == "pointer" && Extended.reconstruct_source(*deref_updated) == deref_new_source);
	Extended.release_parser_tree(*deref_updated);
	Extended.release_parser_names(*deref_updated);
	Extended.release_parser_tree(*deref_fresh);
	Extended.release_parser_names(*deref_fresh);
	free(deref_new_source);
}

test_compound_candidate_edits :: () {
	BASE :: "left, right: s64; keep := right;";
	check_compound_candidate_edit(BASE, "left, middle, right: s64; keep := right;", "left, ".count, "left, ".count);
	check_compound_candidate_edit(BASE, "left, right :: s64; keep := right;", "left, right".count, "left, right:".count);
	check_compound_candidate_edit(BASE, "other, right: s64; keep := right;", 0, "left".count);
	check_compound_candidate_edit(BASE, "left, right: u64; keep := right;", "left, right: ".count, "left, right: s64".count);
	check_compound_candidate_edit("left, right :: 1; keep := right;", "left, right := 1; keep := right;", "left, right ".count, "left, right ::".count);

	old_source := copy_string(BASE);
	new_source := copy_string("left, right: s64 keep := right;");
	old := Extended.parse_file(old_source);
	semicolon_start := "left, right: s64".count;
	updated, ok := Extended.parse_file_edit(*old, semicolon_start, semicolon_start + 1, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && old.status == .COMPLETE && updated.status == fresh.status && updated.status != .COMPLETE);
	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, edit_start=semicolon_start, edit_end=semicolon_start + 1};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	assert(Extended.reuse_simple_declaration(*probe) == null);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);
	statements := updated.root.(*Extended.Parser_Block).statements;
	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	assert(statements.count == fresh_statements.count);
	for statements {
		other := fresh_statements[it_index];
		assert(it.kind == other.kind && it.first_token == other.first_token && it.one_past_last_token == other.one_past_last_token);
	}

	assert(updated.recovery_records.count == fresh.recovery_records.count);
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);
}

check_compound_candidate_edit :: (before: string, after: string, edit_start: s64, edit_end: s64) {
	old_source := copy_string(before);
	new_source := copy_string(after);
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, edit_start, edit_end, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE && fresh.status == .COMPLETE);
	statements := updated.root.(*Extended.Parser_Block).statements;
	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, edit_start=edit_start, edit_end=edit_end, cursor=statements[0].first_token.(s64)};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	assert(Extended.reuse_simple_declaration(*probe) == null);
	probe.cursor = statements[1].first_token.(s64);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root && probe_tokens.root.(*Extended.Parser_Declaration).name == "keep");
	assert(probe.current_scope.references.count == 1);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);
	compound := statements[0].(*Extended.Parser_Compound_Declaration);
	fresh_compound := fresh_statements[0].(*Extended.Parser_Compound_Declaration);
	assert(compound.first_token == fresh_compound.first_token && compound.one_past_last_token == fresh_compound.one_past_last_token);
	assert(compound.l0 == fresh_compound.l0 && compound.c0 == fresh_compound.c0 && compound.l1 == fresh_compound.l1 && compound.c1 == fresh_compound.c1);
	assert(compound.operator_type == fresh_compound.operator_type && compound.declaration_properties.flags == fresh_compound.declaration_properties.flags);
	assert(compound.comma_separated_assignment.arguments.count == fresh_compound.comma_separated_assignment.arguments.count);
	for compound.comma_separated_assignment.arguments {
		other := fresh_compound.comma_separated_assignment.arguments[it_index];
		assert(it.modifier == other.modifier && it.node.first_token == other.node.first_token && it.node.one_past_last_token == other.node.one_past_last_token);
		assert(it.node.(*Extended.Parser_Ident).name == other.node.(*Extended.Parser_Ident).name);
	}

	assert((compound.declaration_properties.type_inst == null) == (fresh_compound.declaration_properties.type_inst == null));
	if compound.declaration_properties.type_inst {
		type_inst := compound.declaration_properties.type_inst;
		fresh_type_inst := fresh_compound.declaration_properties.type_inst;
		assert(type_inst.first_token == fresh_type_inst.first_token && type_inst.one_past_last_token == fresh_type_inst.one_past_last_token);
		assert(type_inst.type_valued_expression.(*Extended.Parser_Ident).name == fresh_type_inst.type_valued_expression.(*Extended.Parser_Ident).name);
	}

	use := statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident);
	assert(use.resolved_declaration == compound.declaration_properties);
	assert(fresh_statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == fresh_compound.declaration_properties);
	assert(statements[1].first_token == fresh_statements[1].first_token && statements[1].one_past_last_token == fresh_statements[1].one_past_last_token);
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(use.name == "right" && Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);
}

test_three_name_compound_ast_reuse :: () {
	old_source := copy_string(			   "left, middle, right :: value; value :: 1; use := middle;");
	new_source := copy_string("added :: 2;\nleft, middle, right :: value; value :: 1; use := middle;");
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && updated.status == .COMPLETE && fresh.status == .COMPLETE);

	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, cursor=updated.root.(*Extended.Parser_Block).statements[1].first_token.(s64)};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root && probe_tokens.root.kind == .COMPOUND_DECLARATION);
	assert(probe.current_scope.bindings.count == 3 && probe.current_scope.references.count == 1);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);

	statements := updated.root.(*Extended.Parser_Block).statements;
	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	compound := statements[1].(*Extended.Parser_Compound_Declaration);
	fresh_compound := fresh_statements[1].(*Extended.Parser_Compound_Declaration);
	assert(compound.first_token == fresh_compound.first_token && compound.one_past_last_token == fresh_compound.one_past_last_token);
	assert(compound.comma_separated_assignment.arguments.count == 3);
	assert(compound.comma_separated_assignment.one_past_last_token == fresh_compound.comma_separated_assignment.one_past_last_token);
	for compound.comma_separated_assignment.arguments {
		other := fresh_compound.comma_separated_assignment.arguments[it_index];
		assert(it.node.first_token == other.node.first_token && it.node.one_past_last_token == other.node.one_past_last_token);
		assert(it.node.(*Extended.Parser_Ident).name == other.node.(*Extended.Parser_Ident).name);
	}

	assert(compound.declaration_properties.expression.(*Extended.Parser_Ident).resolved_declaration == statements[2].(*Extended.Parser_Declaration));
	assert(fresh_compound.declaration_properties.expression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[2].(*Extended.Parser_Declaration));
	assert(statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == compound.declaration_properties);
	assert(fresh_statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == fresh_compound.declaration_properties);
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	assert_eligible_edit_matches_fresh(*updated, *fresh);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(compound.comma_separated_assignment.arguments[1].node.(*Extended.Parser_Ident).name == "middle");
	assert(Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);
}

test_four_name_compound_ast_reuse :: () {
	old_source := copy_string(			   "a, b, c, d :: value; value :: 1; use := d;");
	new_source := copy_string("added :: 2;\na, b, c, d :: value; value :: 1; use := d;");
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && updated.status == .COMPLETE && fresh.status == .COMPLETE);

	statements := updated.root.(*Extended.Parser_Block).statements;
	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, cursor=statements[1].first_token.(s64)};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root && probe.current_scope.bindings.count == 4);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);

	compound := statements[1].(*Extended.Parser_Compound_Declaration);
	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	fresh_compound := fresh_statements[1].(*Extended.Parser_Compound_Declaration);
	assert(compound.comma_separated_assignment.arguments.count == 4);
	assert(compound.comma_separated_assignment.one_past_last_token == fresh_compound.comma_separated_assignment.one_past_last_token);
	for compound.comma_separated_assignment.arguments {
		other := fresh_compound.comma_separated_assignment.arguments[it_index];
		assert(it.node.first_token == other.node.first_token && it.node.one_past_last_token == other.node.one_past_last_token);
		assert(it.node.(*Extended.Parser_Ident).name == other.node.(*Extended.Parser_Ident).name);
	}

	assert(statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == compound.declaration_properties);
	assert(fresh_statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == fresh_compound.declaration_properties);
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(compound.comma_separated_assignment.arguments[3].node.(*Extended.Parser_Ident).name == "d");
	assert(Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);
}

check_compound_reuse_fallback :: (
	source: string,
	check_procedure_type := false,
	check_type_query := false,
	check_skipped_initialization := false,
	expected_note := "",
	expected_alignment: u64 = 0,
	check_run_dimension := false,
) {
	old_source := copy_string(source);
	new_source := copy_string(tprint("added :: 0;\n%", old_source));
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE && fresh.status == .COMPLETE);
	statements := updated.root.(*Extended.Parser_Block).statements;
	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, cursor=statements[1].first_token.(s64)};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	assert(Extended.reuse_simple_declaration(*probe) == null);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);
	compound := statements[1].(*Extended.Parser_Compound_Declaration);
	fresh_compound := fresh_statements[1].(*Extended.Parser_Compound_Declaration);
	assert(compound.first_token == fresh_compound.first_token && compound.one_past_last_token == fresh_compound.one_past_last_token);
	assert(compound.node_flags == fresh_compound.node_flags);
	assert(compound.l0 == fresh_compound.l0 && compound.c0 == fresh_compound.c0);
	assert(compound.comma_separated_assignment.arguments.count == fresh_compound.comma_separated_assignment.arguments.count);
	for compound.comma_separated_assignment.arguments {
		other := fresh_compound.comma_separated_assignment.arguments[it_index];
		assert(it.modifier == other.modifier && it.node.first_token == other.node.first_token && it.node.one_past_last_token == other.node.one_past_last_token);
	}

	assert(compound.declaration_properties.flags == fresh_compound.declaration_properties.flags);
	if expected_note.count {
		assert(compound.notes.count == 1 && fresh_compound.notes.count == 1);
		note := compound.notes[0];
		fresh_note := fresh_compound.notes[0];
		assert(note.text == expected_note && note.text == fresh_note.text);
		assert(note.first_token == fresh_note.first_token && note.one_past_last_token == fresh_note.one_past_last_token);
		assert(note.l0 == fresh_note.l0 && note.c0 == fresh_note.c0 && note.l1 == fresh_note.l1 && note.c1 == fresh_note.c1);
	}

	if expected_alignment {
		alignment := compound.alignment_expression.(*Extended.Parser_Literal);
		fresh_alignment := fresh_compound.alignment_expression.(*Extended.Parser_Literal);
		assert(alignment._u64 == expected_alignment && alignment._u64 == fresh_alignment._u64);
		assert(alignment.first_token == fresh_alignment.first_token && alignment.one_past_last_token == fresh_alignment.one_past_last_token);
		assert(alignment.l0 == fresh_alignment.l0 && alignment.c0 == fresh_alignment.c0 && alignment.l1 == fresh_alignment.l1 && alignment.c1 == fresh_alignment.c1);
	}

	if check_run_dimension {
		type_inst := compound.declaration_properties.type_inst;
		fresh_type_inst := fresh_compound.declaration_properties.type_inst;
		assert(type_inst.first_token == fresh_type_inst.first_token && type_inst.one_past_last_token == fresh_type_inst.one_past_last_token);
		assert(type_inst.l0 == fresh_type_inst.l0 && type_inst.c0 == fresh_type_inst.c0 && type_inst.l1 == fresh_type_inst.l1 && type_inst.c1 == fresh_type_inst.c1);
		dimension := type_inst.array_dimension;
		fresh_dimension := fresh_type_inst.array_dimension;
		assert(dimension.kind == .DIRECTIVE_RUN && dimension.kind == fresh_dimension.kind);
		assert(dimension.first_token == fresh_dimension.first_token && dimension.one_past_last_token == fresh_dimension.one_past_last_token);
		assert(dimension.l0 == fresh_dimension.l0 && dimension.c0 == fresh_dimension.c0 && dimension.l1 == fresh_dimension.l1 && dimension.c1 == fresh_dimension.c1);
	}

	if check_procedure_type {
		type_inst := compound.declaration_properties.type_inst;
		fresh_type_inst := fresh_compound.declaration_properties.type_inst;
		assert((type_inst.inst_flags & .TYPE_OF_PROCEDURE) != 0 && type_inst.inst_flags == fresh_type_inst.inst_flags);
		assert(type_inst.first_token == fresh_type_inst.first_token && type_inst.one_past_last_token == fresh_type_inst.one_past_last_token);
		assert(type_inst.l0 == fresh_type_inst.l0 && type_inst.c0 == fresh_type_inst.c0 && type_inst.l1 == fresh_type_inst.l1 && type_inst.c1 == fresh_type_inst.c1);
		header := type_inst.type_valued_expression.(*Extended.Parser_Procedure_Header);
		fresh_header := fresh_type_inst.type_valued_expression.(*Extended.Parser_Procedure_Header);
		assert(header.first_token == fresh_header.first_token && header.one_past_last_token == fresh_header.one_past_last_token);
		assert(header.arguments.count == 1 && header.returns.count == 1 && fresh_header.arguments.count == 1 && fresh_header.returns.count == 1);
		assert(header.arguments[0].type_inst.first_token == fresh_header.arguments[0].type_inst.first_token);
		assert(header.returns[0].type_inst.one_past_last_token == fresh_header.returns[0].type_inst.one_past_last_token);
	}

	if check_type_query {
		type_inst := compound.declaration_properties.type_inst;
		fresh_type_inst := fresh_compound.declaration_properties.type_inst;
		assert(type_inst.first_token == fresh_type_inst.first_token && type_inst.one_past_last_token == fresh_type_inst.one_past_last_token);
		assert(type_inst.l0 == fresh_type_inst.l0 && type_inst.c0 == fresh_type_inst.c0 && type_inst.l1 == fresh_type_inst.l1 && type_inst.c1 == fresh_type_inst.c1);
		query := type_inst.type_valued_expression.(*Extended.Parser_Expression_Query);
		fresh_query := fresh_type_inst.type_valued_expression.(*Extended.Parser_Expression_Query);
		assert(query.query_kind == .TYPE_OF && query.query_kind == fresh_query.query_kind);
		assert(query.first_token == fresh_query.first_token && query.one_past_last_token == fresh_query.one_past_last_token);
		assert(query.l0 == fresh_query.l0 && query.c0 == fresh_query.c0 && query.l1 == fresh_query.l1 && query.c1 == fresh_query.c1);
		assert(query.expression_to_query.first_token == fresh_query.expression_to_query.first_token && query.expression_to_query.one_past_last_token == fresh_query.expression_to_query.one_past_last_token);
	}

	if check_skipped_initialization {
		assert((compound.declaration_properties.flags & .IS_UNINITIALIZED) != 0);
		assert(!compound.declaration_properties.expression && !fresh_compound.declaration_properties.expression);
		type_inst := compound.declaration_properties.type_inst;
		fresh_type_inst := fresh_compound.declaration_properties.type_inst;
		assert(type_inst.first_token == fresh_type_inst.first_token && type_inst.one_past_last_token == fresh_type_inst.one_past_last_token);
		assert(type_inst.l0 == fresh_type_inst.l0 && type_inst.c0 == fresh_type_inst.c0 && type_inst.l1 == fresh_type_inst.l1 && type_inst.c1 == fresh_type_inst.c1);
		assert(type_inst.type_valued_expression.(*Extended.Parser_Ident).name == "s64");
	}

	if check_procedure_type || check_type_query || check_skipped_initialization || expected_alignment || check_run_dimension {
		body := statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block;
		fresh_body := fresh_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block;
		for 0..1 {
			assert(body.statements[it].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == compound.declaration_properties);
			assert(fresh_body.statements[it].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == fresh_compound.declaration_properties);
		}
	}

	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	assert_eligible_edit_matches_fresh(*updated, *fresh);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(compound.comma_separated_assignment.arguments[0].node.(*Extended.Parser_Ident).name == "left");
	if expected_note.count > 0 {
		assert(compound.notes[0].text == expected_note);
	}

	assert(Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);
}

test_scalar_literal_ast_reuse :: () {
	for expression: string.["42", "0xFF", "0b101", "3.5", "true", "false", "#char \"A\""] {
		old_source := copy_string(tprint(			   "value := %; use := value;", expression));
		new_source := copy_string(tprint("prefix :: 0;\nvalue := %; use := value;", expression));
		old := Extended.parse_file(old_source);
		updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
		fresh := Extended.parse_file(new_source);
		assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE && fresh.status == .COMPLETE);
		statements := updated.root.(*Extended.Parser_Block).statements;
		fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
		probe_tokens := Extended.materialise_tokens(new_source);
		probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, cursor=statements[1].first_token.(s64)};
		set_allocators(*probe_tokens.node_pool, context.default_allocator);
		probe.current_scope = Extended.push_lexical_scope(*probe);
		probe_tokens.root = Extended.reuse_simple_declaration(*probe);
		assert(probe_tokens.root != null);
		Extended.release_parser_tree(*probe_tokens);
		Extended.release_parser_names(*probe_tokens);
		literal := statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Literal);
		fresh_literal := fresh_statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Literal);
		assert(literal.node_flags == fresh_literal.node_flags);
		assert(literal.value_type == fresh_literal.value_type && literal.value_flags == fresh_literal.value_flags);
		if literal.value_flags & .FLOAT {
			assert(literal._float64 == fresh_literal._float64);
		} else {
			assert(literal._u64 == fresh_literal._u64);
		}

		assert(literal.first_token == fresh_literal.first_token && literal.one_past_last_token == fresh_literal.one_past_last_token);
		assert(literal.l0 == fresh_literal.l0 && literal.c0 == fresh_literal.c0 && literal.l1 == fresh_literal.l1 && literal.c1 == fresh_literal.c1);
		assert(statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == statements[1].(*Extended.Parser_Declaration));
		assert(fresh_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[1].(*Extended.Parser_Declaration));
		assert(updated.tokens.count == fresh.tokens.count);
		for updated.tokens {
			other := fresh.tokens[it_index];
			assert(it.type == other.type && it.value_flags == other.value_flags);
			assert(it.byte_start == other.byte_start && it.byte_end == other.byte_end && it.preceding_trivia_byte_start == other.preceding_trivia_byte_start);
			assert(it.l0 == other.l0 && it.c0 == other.c0 && it.l1 == other.l1 && it.c1 == other.c1);
			assert(it.original_text == other.original_text && it.preceding_trivia == other.preceding_trivia && it.trailing_trivia == other.trailing_trivia);
		}

		assert(updated.diagnostics.count == fresh.diagnostics.count && updated.recovery_records.count == fresh.recovery_records.count);
		assert(updated.restart_points.count == fresh.restart_points.count);
		for updated.restart_points {
			other := fresh.restart_points[it_index];
			assert(it.kind == other.kind && it.span.first == other.span.first && it.span.one_past_last == other.span.one_past_last);
		}

		Extended.release_parser_tree(*old);
		Extended.release_parser_names(*old);
		free(old_source);
		for updated.tokens {
			other := fresh.tokens[it_index];
			assert(it.original_text == other.original_text && it.preceding_trivia == other.preceding_trivia && it.trailing_trivia == other.trailing_trivia);
		}

		assert(Extended.reconstruct_source(*updated) == new_source);
		Extended.release_parser_tree(*updated);
		Extended.release_parser_names(*updated);
		Extended.release_parser_tree(*fresh);
		Extended.release_parser_names(*fresh);
		free(new_source);
	}
}

test_source_position_ast_reuse :: () {
	BASE :: "label :: \"one\\ntwo\"; use := label;";
	check_source_position_edit(BASE, "// before\nlabel :: \"one\\ntwo\"; use := label;", 0, 0, true, "one\ntwo");
	check_source_position_edit(BASE, " \tlabel :: \"one\\ntwo\"; use := label;", 0, 0, true, "one\ntwo");
	check_source_position_edit("// before\nlabel :: \"one\\ntwo\"; use := label;", BASE, 0, "// before\n".count, true, "one\ntwo");
	check_source_position_edit(BASE, "label \n :: \"one\\ntwo\"; use := label;", "label ".count, "label ".count, false, "one\ntwo");
	check_source_position_edit(BASE, "label :: \"one\\ntwo\" /* note */; use := label;", "label :: \"one\\ntwo\"".count, "label :: \"one\\ntwo\"".count, true, "one\ntwo");
	check_source_position_edit(BASE, "label :: \"one\\nthree\"; use := label;", "label :: \"one\\n".count, "label :: \"one\\ntwo".count, false, "one\nthree");
	check_source_position_edit(BASE, "label :: \"one\\ntwo\"; // between\nuse := label;", "label :: \"one\\ntwo\"; ".count, "label :: \"one\\ntwo\"; ".count, true, "one\ntwo");
	check_source_position_edit(BASE, "label :: \"one\\ntwo\"; use := label; // trailing\n", BASE.count, BASE.count, true, "one\ntwo");
}

check_source_position_edit :: (before: string, after: string, edit_start: s64, edit_end: s64, reuse_first: bool, expected_string: string) {
	old_source := copy_string(before);
	new_source := copy_string(after);
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, edit_start, edit_end, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE && fresh.status == .COMPLETE);
	statements := updated.root.(*Extended.Parser_Block).statements;
	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, edit_start=edit_start, edit_end=edit_end, cursor=statements[0].first_token.(s64)};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert((probe_tokens.root != null) == reuse_first);
	probe.cursor = statements[1].first_token.(s64);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root && probe_tokens.root.(*Extended.Parser_Declaration).name == "use");
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);
	assert(updated.tokens.count == fresh.tokens.count && statements.count == fresh_statements.count);
	for updated.tokens {
		other := fresh.tokens[it_index];
		assert(it.byte_start == other.byte_start && it.byte_end == other.byte_end && it.preceding_trivia_byte_start == other.preceding_trivia_byte_start);
		assert(it.l0 == other.l0 && it.c0 == other.c0 && it.l1 == other.l1 && it.c1 == other.c1);
		assert(it.original_text == other.original_text && it.preceding_trivia == other.preceding_trivia && it.trailing_trivia == other.trailing_trivia);
	}

	for statements {
		other := fresh_statements[it_index];
		assert(it.first_token == other.first_token && it.one_past_last_token == other.one_past_last_token);
		assert(it.l0 == other.l0 && it.c0 == other.c0 && it.l1 == other.l1 && it.c1 == other.c1);
	}

	label := statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Literal);
	assert(label._string == fresh_statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Literal)._string);
	assert(label._string.data == updated.tokens[label.first_token.(s64)].string_value.data);
	assert(statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == statements[0].(*Extended.Parser_Declaration));
	assert(fresh_statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[0].(*Extended.Parser_Declaration));
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	for updated.restart_points {
		other := fresh.restart_points[it_index];
		assert(it.kind == other.kind && it.span.first == other.span.first && it.span.one_past_last == other.span.one_past_last);
	}

	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	for updated.tokens {
		assert(it.original_text == slice(new_source, it.byte_start, it.original_text.count));
		assert(it.preceding_trivia == slice(new_source, it.preceding_trivia_byte_start, it.preceding_trivia.count));
	}

	assert(label._string == expected_string && Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);
}

test_source_backed_ast_reuse :: () {
	old_source := copy_string(			   "label :: \"one\\ntwo\"; enabled :: true;");
	new_source := copy_string("prefix :: 0; label :: \"one\\ntwo\"; enabled :: true;");
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && updated.status == .COMPLETE && fresh.status == .COMPLETE);

	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, cursor=5};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root && probe_tokens.root.(*Extended.Parser_Declaration).expression.(*Extended.Parser_Literal).value_type == .STRING);
	probe.cursor = 10;
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root && probe_tokens.root.(*Extended.Parser_Declaration).expression.(*Extended.Parser_Literal).value_type == .BOOLEAN);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);

	updated_statements := updated.root.(*Extended.Parser_Block).statements;
	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	assert(updated_statements.count == fresh_statements.count);
	assert(updated.diagnostics.count == fresh.diagnostics.count);
	for updated_statements {
		other := fresh_statements[it_index];
		assert(it.first_token == other.first_token && it.one_past_last_token == other.one_past_last_token);
		assert(it.l0 == other.l0 && it.c0 == other.c0 && it.l1 == other.l1 && it.c1 == other.c1);
	}

	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert((updated_statements[1].(*Extended.Parser_Declaration).flags & .IS_CONSTANT) != 0);
	assert(updated_statements[1].(*Extended.Parser_Declaration).flags == fresh_statements[1].(*Extended.Parser_Declaration).flags);
	assert((updated_statements[2].(*Extended.Parser_Declaration).flags & .IS_CONSTANT) != 0);
	assert(updated_statements[2].(*Extended.Parser_Declaration).flags == fresh_statements[2].(*Extended.Parser_Declaration).flags);
	label := updated_statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Literal);
	fresh_label := fresh_statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Literal);
	assert(label._string == "one\ntwo" && label._string == fresh_label._string);
	assert(label._string.data == updated.tokens[8].string_value.data);
	assert(updated_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Literal)._u64 == 1);
	assert(Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);

	filepath_old_source := copy_string(				 "path :: #filepath; use := path;");
	filepath_new_source := copy_string("prefix :: 0;\npath :: #filepath; use := path;");
	FILEPATH_FILENAME :: "C:/fixtures/source.jai";
	filepath_old := Extended.parse_file(filepath_old_source, FILEPATH_FILENAME);
	filepath_updated, filepath_ok := Extended.parse_file_edit(*filepath_old, 0, 0, filepath_new_source);
	filepath_fresh := Extended.parse_file(filepath_new_source, FILEPATH_FILENAME);
	assert(filepath_ok && filepath_old.status == .COMPLETE && filepath_updated.status == .COMPLETE && filepath_fresh.status == .COMPLETE);
	filepath_statements := filepath_updated.root.(*Extended.Parser_Block).statements;
	filepath_fresh_statements := filepath_fresh.root.(*Extended.Parser_Block).statements;
	filepath_probe_tokens := Extended.materialise_tokens(filepath_new_source);
	filepath_probe := Extended.Parser.{parsed=*filepath_probe_tokens, edit_source=*filepath_old, cursor=filepath_statements[1].first_token.(s64)};
	set_allocators(*filepath_probe_tokens.node_pool, context.default_allocator);
	filepath_probe.current_scope = Extended.push_lexical_scope(*filepath_probe);
	assert(Extended.reuse_simple_declaration(*filepath_probe) == null);
	Extended.release_parser_tree(*filepath_probe_tokens);
	Extended.release_parser_names(*filepath_probe_tokens);
	filepath_literal := filepath_statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Literal);
	filepath_fresh_literal := filepath_fresh_statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Literal);
	assert(filepath_literal.value_type == .STRING && filepath_literal._string == "C:/fixtures/");
	assert(filepath_literal._string == filepath_fresh_literal._string);
	assert(filepath_literal.first_token == filepath_fresh_literal.first_token && filepath_literal.one_past_last_token == filepath_fresh_literal.one_past_last_token);
	assert(filepath_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == filepath_statements[1].(*Extended.Parser_Declaration));
	assert(filepath_fresh_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == filepath_fresh_statements[1].(*Extended.Parser_Declaration));
	assert(filepath_updated.diagnostics.count == filepath_fresh.diagnostics.count && filepath_updated.restart_points.count == filepath_fresh.restart_points.count);
	Extended.release_parser_tree(*filepath_old);
	Extended.release_parser_names(*filepath_old);
	free(filepath_old_source);
	assert(filepath_literal._string == "C:/fixtures/" && Extended.reconstruct_source(*filepath_updated) == filepath_new_source);
	Extended.release_parser_tree(*filepath_updated);
	Extended.release_parser_names(*filepath_updated);
	Extended.release_parser_tree(*filepath_fresh);
	Extended.release_parser_names(*filepath_fresh);
	free(filepath_new_source);
}

test_excluded_literal_ast_reuse_fallback :: () {
	for declaration_source: string.[
		"value := .[null, 1];",
		"value := .{null, 1};",
		"value := .{field = 1};",
		"value := #string END\nbody\nEND\n",
	] {
		old_source := copy_string(tprint(			   "%\nuse := value;", declaration_source));
		new_source := copy_string(tprint("prefix :: 0;\n%\nuse := value;", declaration_source));
		old := Extended.parse_file(old_source);
		updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
		fresh := Extended.parse_file(new_source);
		assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE && fresh.status == .COMPLETE, "Excluded literal: %", declaration_source);
		old_literal := old.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Declaration).expression;
		assert(old_literal.kind == .LITERAL && !Extended.reusable_expression(old_literal));
		statements := updated.root.(*Extended.Parser_Block).statements;
		fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
		probe_tokens := Extended.materialise_tokens(new_source);
		probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, cursor=statements[1].first_token.(s64)};
		set_allocators(*probe_tokens.node_pool, context.default_allocator);
		probe.current_scope = Extended.push_lexical_scope(*probe);
		assert(Extended.reuse_simple_declaration(*probe) == null);
		Extended.release_parser_tree(*probe_tokens);
		Extended.release_parser_names(*probe_tokens);
		literal := statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Literal);
		fresh_literal := fresh_statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Literal);
		assert(literal.value_type == fresh_literal.value_type && literal.value_flags == fresh_literal.value_flags);
		assert(literal.first_token == fresh_literal.first_token && literal.one_past_last_token == fresh_literal.one_past_last_token);
		assert(literal.l0 == fresh_literal.l0 && literal.c0 == fresh_literal.c0 && literal.l1 == fresh_literal.l1 && literal.c1 == fresh_literal.c1);
		if literal.value_type == .STRING {
			assert(literal.value_flags & .HERE_STRING && literal._string == "body\n" && literal._string == fresh_literal._string);
		}

		assert(statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == statements[1].(*Extended.Parser_Declaration));
		assert(fresh_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[1].(*Extended.Parser_Declaration));
		assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
		Extended.release_parser_tree(*old);
		Extended.release_parser_names(*old);
		free(old_source);
		assert(Extended.reconstruct_source(*updated) == new_source);
		Extended.release_parser_tree(*updated);
		Extended.release_parser_names(*updated);
		Extended.release_parser_tree(*fresh);
		Extended.release_parser_names(*fresh);
		free(new_source);
	}
}

test_aggregate_payload_edits :: () {
	for replacement: string.["3", "\"new\""] {
		array_case := replacement == "3";
		prefix := ifx array_case
			then "value := .[1, "
			else "value := .{";
		suffix := ifx array_case
			then "]; use := value;"
			else "}; use := value;";
		old_payload := ifx array_case
			then "2"
			else "\"old\"";
		old_source := copy_string(tprint("%%%", prefix, old_payload, suffix));
		new_source := copy_string(tprint("%%%", prefix, replacement, suffix));
		old := Extended.parse_file(old_source);
		updated, ok := Extended.parse_file_edit(*old, prefix.count, prefix.count + old_payload.count, new_source);
		fresh := Extended.parse_file(new_source);
		assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE && fresh.status == .COMPLETE);
		statements := updated.root.(*Extended.Parser_Block).statements;
		fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
		probe_tokens := Extended.materialise_tokens(new_source);
		probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, edit_start=prefix.count, edit_end=prefix.count + old_payload.count, cursor=statements[0].first_token.(s64)};
		set_allocators(*probe_tokens.node_pool, context.default_allocator);
		probe.current_scope = Extended.push_lexical_scope(*probe);
		assert(Extended.reuse_simple_declaration(*probe) == null);
		probe.cursor = statements[1].first_token.(s64);
		probe_tokens.root = Extended.reuse_simple_declaration(*probe);
		assert(probe_tokens.root != null);
		Extended.release_parser_tree(*probe_tokens);
		Extended.release_parser_names(*probe_tokens);
		literal := statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Literal);
		fresh_literal := fresh_statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Literal);
		assert(literal.value_type == fresh_literal.value_type);
		assert(literal.first_token == fresh_literal.first_token && literal.one_past_last_token == fresh_literal.one_past_last_token);
		if array_case {
			assert(literal.array_literal_info.array_members[1].(*Extended.Parser_Literal)._u64 == 3);
			assert(literal.array_literal_info.array_members[1].first_token == fresh_literal.array_literal_info.array_members[1].first_token);
		} else {
			assert(literal.struct_literal_info.arguments[0].(*Extended.Parser_Literal)._string == "new");
			assert(literal.struct_literal_info.arguments[0].first_token == fresh_literal.struct_literal_info.arguments[0].first_token);
		}

		assert(statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == statements[0].(*Extended.Parser_Declaration));
		assert(fresh_statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[0].(*Extended.Parser_Declaration));
		assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
		Extended.release_parser_tree(*old);
		Extended.release_parser_names(*old);
		free(old_source);
		if !array_case {
			assert(literal.struct_literal_info.arguments[0].(*Extended.Parser_Literal)._string == "new");
		}

		assert(Extended.reconstruct_source(*updated) == new_source);
		Extended.release_parser_tree(*updated);
		Extended.release_parser_names(*updated);
		Extended.release_parser_tree(*fresh);
		Extended.release_parser_names(*fresh);
		free(new_source);
	}
}

test_nested_ast_reuse :: () {
	old_source := copy_string(				"base :: 2; value := (base + 3) * 4;");
	new_source := copy_string("prefix :: 1;\nbase :: 2; value := (base + 3) * 4;");
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && updated.status == .COMPLETE && fresh.status == .COMPLETE);

	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, cursor=10};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root && probe_tokens.root.(*Extended.Parser_Declaration).expression.kind == .BINARY_OPERATOR);
	assert(probe.current_scope.references.count == 1);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);

	updated_statements := updated.root.(*Extended.Parser_Block).statements;
	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	updated_product := updated_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Binary_Operator);
	fresh_product := fresh_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Binary_Operator);
	assert(updated_product.operator_type == fresh_product.operator_type && updated_product.operator_type == #char "*");
	assert(updated_product.first_token == fresh_product.first_token && updated_product.one_past_last_token == fresh_product.one_past_last_token);
	updated_sum := updated_product.left.(*Extended.Parser_Binary_Operator);
	fresh_sum := fresh_product.left.(*Extended.Parser_Binary_Operator);
	assert(updated_sum.operator_type == fresh_sum.operator_type && updated_sum.operator_type == #char "+");
	assert(updated_sum.first_token == fresh_sum.first_token && updated_sum.one_past_last_token == fresh_sum.one_past_last_token);
	updated_reference := updated_sum.left.(*Extended.Parser_Ident);
	fresh_reference := fresh_sum.left.(*Extended.Parser_Ident);
	assert(updated_reference.first_token == fresh_reference.first_token && updated_reference.one_past_last_token == fresh_reference.one_past_last_token);
	assert(updated_reference.resolved_declaration == updated_statements[1].(*Extended.Parser_Declaration));
	assert(fresh_reference.resolved_declaration == fresh_statements[1].(*Extended.Parser_Declaration));
	assert(updated_product.right.first_token == fresh_product.right.first_token);
	assert(updated.restart_points.count == fresh.restart_points.count && updated.diagnostics.count == fresh.diagnostics.count);
	assert(Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(updated_reference.name == "base" && updated_reference.resolved_declaration == updated_statements[1].(*Extended.Parser_Declaration));
	assert(Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);

	check_changed_candidate_ast_reuse("value := 1 * 2; keep := value;", "value := 1 ".count, "value := 1 +".count);
	check_changed_candidate_ast_reuse("value := 1; keep := value;", "value := 1".count, "value := 1 + 2".count);
}

check_changed_candidate_ast_reuse :: (new_text: string, edit_start: s64, edit_end: s64) {
	old_source := copy_string("value := 1 + 2; keep := value;");
	new_source := copy_string(new_text);
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, edit_start, edit_end, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE && fresh.status == .COMPLETE);

	statements := updated.root.(*Extended.Parser_Block).statements;
	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, edit_start=edit_start, edit_end=edit_end, cursor=statements[0].first_token.(s64)};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	assert(Extended.reuse_simple_declaration(*probe) == null);
	probe.cursor = statements[1].first_token.(s64);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root && probe_tokens.root.(*Extended.Parser_Declaration).name == "keep");
	assert(probe.current_scope.references.count == 1);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);

	value := statements[0].(*Extended.Parser_Declaration).expression;
	fresh_value := fresh_statements[0].(*Extended.Parser_Declaration).expression;
	assert(value.kind == fresh_value.kind);
	if value.kind == .BINARY_OPERATOR {
		assert(value.(*Extended.Parser_Binary_Operator).operator_type == #char "*");
		assert(value.(*Extended.Parser_Binary_Operator).operator_type == fresh_value.(*Extended.Parser_Binary_Operator).operator_type);
	} else {
		assert(value.kind == .LITERAL);
	}

	use := statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident);
	assert(use.resolved_declaration == statements[0].(*Extended.Parser_Declaration));
	assert(fresh_statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[0].(*Extended.Parser_Declaration));
	for statements {
		other := fresh_statements[it_index];
		assert(it.first_token == other.first_token && it.one_past_last_token == other.one_past_last_token);
	}

	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(use.name == "value" && Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);
}

test_remainder_ast_reuse :: () {
	old_source := copy_string(			   "left :: 7; right :: 3; remainder := left % right;");
	new_source := copy_string("added :: 0;\nleft :: 7; right :: 3; remainder := left % right;");
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE && fresh.status == .COMPLETE);

	statements := updated.root.(*Extended.Parser_Block).statements;
	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, cursor=statements[3].first_token.(s64)};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root && probe_tokens.root.(*Extended.Parser_Declaration).expression.kind == .BINARY_OPERATOR);
	assert(probe.current_scope.references.count == 2);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);

	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	assert(statements[3].first_token == fresh_statements[3].first_token && statements[3].one_past_last_token == fresh_statements[3].one_past_last_token);
	binary := statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Binary_Operator);
	fresh_binary := fresh_statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Binary_Operator);
	assert(binary.operator_type == #char "%" && binary.operator_type == fresh_binary.operator_type);
	assert(binary.first_token == fresh_binary.first_token && binary.one_past_last_token == fresh_binary.one_past_last_token);
	left := binary.left.(*Extended.Parser_Ident);
	right := binary.right.(*Extended.Parser_Ident);
	assert(left.first_token == fresh_binary.left.first_token && right.first_token == fresh_binary.right.first_token);
	assert(left.resolved_declaration == statements[1].(*Extended.Parser_Declaration));
	assert(right.resolved_declaration == statements[2].(*Extended.Parser_Declaration));
	assert(fresh_binary.left.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[1].(*Extended.Parser_Declaration));
	assert(fresh_binary.right.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[2].(*Extended.Parser_Declaration));
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	assert_eligible_edit_matches_fresh(*updated, *fresh);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(left.name == "left" && right.name == "right" && Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);
}

test_equality_ast_reuse :: () {
	old_source := copy_string(			   "left :: 7; right :: 3; equal := left == right;");
	new_source := copy_string("added :: 0;\nleft :: 7; right :: 3; equal := left == right;");
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE && fresh.status == .COMPLETE);

	statements := updated.root.(*Extended.Parser_Block).statements;
	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, cursor=statements[3].first_token.(s64)};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root && probe_tokens.root.(*Extended.Parser_Declaration).expression.kind == .BINARY_OPERATOR);
	assert(probe.current_scope.references.count == 2);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);

	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	binary := statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Binary_Operator);
	fresh_binary := fresh_statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Binary_Operator);
	assert(binary.operator_type == .IS_EQUAL && binary.operator_type == fresh_binary.operator_type);
	assert(binary.first_token == fresh_binary.first_token && binary.one_past_last_token == fresh_binary.one_past_last_token);
	assert(binary.l0 == fresh_binary.l0 && binary.c0 == fresh_binary.c0 && binary.l1 == fresh_binary.l1 && binary.c1 == fresh_binary.c1);
	left := binary.left.(*Extended.Parser_Ident);
	right := binary.right.(*Extended.Parser_Ident);
	assert(left.first_token == fresh_binary.left.first_token && right.first_token == fresh_binary.right.first_token);
	assert(left.resolved_declaration == statements[1].(*Extended.Parser_Declaration));
	assert(right.resolved_declaration == statements[2].(*Extended.Parser_Declaration));
	assert(fresh_binary.left.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[1].(*Extended.Parser_Declaration));
	assert(fresh_binary.right.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[2].(*Extended.Parser_Declaration));
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);

	changed_source := copy_string("left :: 7; right :: 3; equal := left != right;");
	operator_start := "left :: 7; right :: 3; equal := left ".count;
	changed, changed_ok := Extended.parse_file_edit(*old, operator_start, operator_start + 2, changed_source);
	changed_fresh := Extended.parse_file(changed_source);
	assert(changed_ok && changed.status == .COMPLETE && changed_fresh.status == .COMPLETE);
	changed_tokens := Extended.materialise_tokens(changed_source);
	changed_probe := Extended.Parser.{parsed=*changed_tokens, edit_source=*old, edit_start=operator_start, edit_end=operator_start + 2, cursor=changed.root.(*Extended.Parser_Block).statements[2].first_token.(s64)};
	set_allocators(*changed_tokens.node_pool, context.default_allocator);
	changed_probe.current_scope = Extended.push_lexical_scope(*changed_probe);
	assert(Extended.reuse_simple_declaration(*changed_probe) == null);
	Extended.release_parser_tree(*changed_tokens);
	Extended.release_parser_names(*changed_tokens);
	changed_statements := changed.root.(*Extended.Parser_Block).statements;
	changed_fresh_statements := changed_fresh.root.(*Extended.Parser_Block).statements;
	changed_binary := changed_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Binary_Operator);
	changed_fresh_binary := changed_fresh_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Binary_Operator);
	assert(changed_binary.operator_type == .IS_NOT_EQUAL);
	assert(changed_binary.first_token == changed_fresh_binary.first_token && changed_binary.one_past_last_token == changed_fresh_binary.one_past_last_token);
	assert(changed_binary.left.(*Extended.Parser_Ident).resolved_declaration == changed_statements[0].(*Extended.Parser_Declaration));
	assert(changed_binary.right.(*Extended.Parser_Ident).resolved_declaration == changed_statements[1].(*Extended.Parser_Declaration));
	assert(changed_fresh_binary.left.(*Extended.Parser_Ident).resolved_declaration == changed_fresh_statements[0].(*Extended.Parser_Declaration));
	assert(changed_fresh_binary.right.(*Extended.Parser_Ident).resolved_declaration == changed_fresh_statements[1].(*Extended.Parser_Declaration));
	assert(changed.diagnostics.count == changed_fresh.diagnostics.count && changed.restart_points.count == changed_fresh.restart_points.count);
	assert(Extended.reconstruct_source(*changed) == changed_source);
	Extended.release_parser_tree(*changed);
	Extended.release_parser_names(*changed);
	Extended.release_parser_tree(*changed_fresh);
	Extended.release_parser_names(*changed_fresh);
	free(changed_source);

	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(left.name == "left" && right.name == "right" && Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);
}

test_inequality_ast_reuse :: () {
	old_source := copy_string(			   "left :: 7; right :: 3; unequal := left != right;");
	new_source := copy_string("added :: 0;\nleft :: 7; right :: 3; unequal := left != right;");
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE && fresh.status == .COMPLETE);

	statements := updated.root.(*Extended.Parser_Block).statements;
	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, cursor=statements[3].first_token.(s64)};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root && probe_tokens.root.(*Extended.Parser_Declaration).expression.kind == .BINARY_OPERATOR);
	assert(probe.current_scope.references.count == 2);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);

	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	binary := statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Binary_Operator);
	fresh_binary := fresh_statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Binary_Operator);
	assert(binary.operator_type == .IS_NOT_EQUAL && binary.operator_type == fresh_binary.operator_type);
	assert(binary.first_token == fresh_binary.first_token && binary.one_past_last_token == fresh_binary.one_past_last_token);
	assert(binary.l0 == fresh_binary.l0 && binary.c0 == fresh_binary.c0 && binary.l1 == fresh_binary.l1 && binary.c1 == fresh_binary.c1);
	left := binary.left.(*Extended.Parser_Ident);
	right := binary.right.(*Extended.Parser_Ident);
	assert(left.first_token == fresh_binary.left.first_token && right.first_token == fresh_binary.right.first_token);
	assert(left.resolved_declaration == statements[1].(*Extended.Parser_Declaration));
	assert(right.resolved_declaration == statements[2].(*Extended.Parser_Declaration));
	assert(fresh_binary.left.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[1].(*Extended.Parser_Declaration));
	assert(fresh_binary.right.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[2].(*Extended.Parser_Declaration));
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(left.name == "left" && right.name == "right" && Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);
}

test_ordered_comparison_ast_reuse :: () {
	check_binary_ast_reuse("<", #char "<");
	check_binary_ast_reuse("<=", .LESS_OR_EQUAL);
	check_binary_ast_reuse(">", #char ">");
	check_binary_ast_reuse(">=", .GREATER_OR_EQUAL);

	old_source := copy_string("left :: 7; right :: 3; result := left < right;");
	new_source := copy_string("left :: 7; right :: 3; result := left <= right;");
	operator_start := "left :: 7; right :: 3; result := left ".count;
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, operator_start, operator_start + 1, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE && fresh.status == .COMPLETE);
	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, edit_start=operator_start, edit_end=operator_start + 1, cursor=updated.root.(*Extended.Parser_Block).statements[2].first_token.(s64)};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	assert(Extended.reuse_simple_declaration(*probe) == null);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);
	updated_statements := updated.root.(*Extended.Parser_Block).statements;
	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	updated_binary := updated_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Binary_Operator);
	fresh_binary := fresh_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Binary_Operator);
	assert(updated_binary.operator_type == .LESS_OR_EQUAL && updated_binary.operator_type == fresh_binary.operator_type);
	assert(updated_binary.first_token == fresh_binary.first_token && updated_binary.one_past_last_token == fresh_binary.one_past_last_token);
	assert(updated_binary.left.(*Extended.Parser_Ident).resolved_declaration == updated_statements[0].(*Extended.Parser_Declaration));
	assert(updated_binary.right.(*Extended.Parser_Ident).resolved_declaration == updated_statements[1].(*Extended.Parser_Declaration));
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	assert(Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(old_source);
	free(new_source);
}

check_binary_ast_reuse :: (spelling: string, expected_type: Operator_Type) {
	old_source := copy_string(tprint("left :: 7; right :: 3; result := left % right;", spelling));
	new_source := copy_string(tprint("added :: 0;\n%", old_source));
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE && fresh.status == .COMPLETE);

	statements := updated.root.(*Extended.Parser_Block).statements;
	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, cursor=statements[3].first_token.(s64)};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root && probe_tokens.root.(*Extended.Parser_Declaration).expression.kind == .BINARY_OPERATOR);
	assert(probe.current_scope.references.count == 2);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);

	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	binary := statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Binary_Operator);
	fresh_binary := fresh_statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Binary_Operator);
	assert(binary.kind == fresh_binary.kind && binary.node_flags == fresh_binary.node_flags && binary.flags == fresh_binary.flags);
	assert(binary.operator_type == expected_type && binary.operator_type == fresh_binary.operator_type);
	assert(binary.first_token == fresh_binary.first_token && binary.one_past_last_token == fresh_binary.one_past_last_token);
	assert(binary.l0 == fresh_binary.l0 && binary.c0 == fresh_binary.c0 && binary.l1 == fresh_binary.l1 && binary.c1 == fresh_binary.c1);
	left := binary.left.(*Extended.Parser_Ident);
	right := binary.right.(*Extended.Parser_Ident);
	assert(left.node_flags == fresh_binary.left.node_flags && right.node_flags == fresh_binary.right.node_flags);
	assert(left.first_token == fresh_binary.left.first_token && left.one_past_last_token == fresh_binary.left.one_past_last_token);
	assert(right.first_token == fresh_binary.right.first_token && right.one_past_last_token == fresh_binary.right.one_past_last_token);
	assert(left.resolved_declaration == statements[1].(*Extended.Parser_Declaration));
	assert(right.resolved_declaration == statements[2].(*Extended.Parser_Declaration));
	assert(fresh_binary.left.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[1].(*Extended.Parser_Declaration));
	assert(fresh_binary.right.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[2].(*Extended.Parser_Declaration));
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(left.name == "left" && right.name == "right" && Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);
}

test_logical_ast_reuse :: () {
	old_source := copy_string(				   "left :: true; middle :: false; right :: true; result := left || middle && right;");
	new_source := copy_string("added :: false;\nleft :: true; middle :: false; right :: true; result := left || middle && right;");
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE && fresh.status == .COMPLETE);

	statements := updated.root.(*Extended.Parser_Block).statements;
	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, cursor=statements[4].first_token.(s64)};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root && probe_tokens.root.(*Extended.Parser_Declaration).expression.kind == .BINARY_OPERATOR);
	assert(probe.current_scope.references.count == 3);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);

	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	binary := statements[4].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Binary_Operator);
	fresh_binary := fresh_statements[4].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Binary_Operator);
	assert(binary.operator_type == .LOGICAL_OR && binary.operator_type == fresh_binary.operator_type);
	assert(binary.first_token == fresh_binary.first_token && binary.one_past_last_token == fresh_binary.one_past_last_token);
	assert(binary.l0 == fresh_binary.l0 && binary.c0 == fresh_binary.c0 && binary.l1 == fresh_binary.l1 && binary.c1 == fresh_binary.c1);
	inner := binary.right.(*Extended.Parser_Binary_Operator);
	fresh_inner := fresh_binary.right.(*Extended.Parser_Binary_Operator);
	assert(inner.operator_type == .LOGICAL_AND && inner.operator_type == fresh_inner.operator_type);
	assert(inner.first_token == fresh_inner.first_token && inner.one_past_last_token == fresh_inner.one_past_last_token);
	assert(binary.left.(*Extended.Parser_Ident).resolved_declaration == statements[1].(*Extended.Parser_Declaration));
	assert(inner.left.(*Extended.Parser_Ident).resolved_declaration == statements[2].(*Extended.Parser_Declaration));
	assert(inner.right.(*Extended.Parser_Ident).resolved_declaration == statements[3].(*Extended.Parser_Declaration));
	assert(fresh_binary.left.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[1].(*Extended.Parser_Declaration));
	assert(fresh_inner.left.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[2].(*Extended.Parser_Declaration));
	assert(fresh_inner.right.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[3].(*Extended.Parser_Declaration));
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);

	changed_source := copy_string("left :: true; middle :: false; right :: true; result := left && middle && right;");
	operator_start := "left :: true; middle :: false; right :: true; result := left ".count;
	changed, changed_ok := Extended.parse_file_edit(*old, operator_start, operator_start + 2, changed_source);
	changed_fresh := Extended.parse_file(changed_source);
	assert(changed_ok && changed.status == .COMPLETE && changed_fresh.status == .COMPLETE);
	changed_tokens := Extended.materialise_tokens(changed_source);
	changed_probe := Extended.Parser.{parsed=*changed_tokens, edit_source=*old, edit_start=operator_start, edit_end=operator_start + 2, cursor=changed.root.(*Extended.Parser_Block).statements[3].first_token.(s64)};
	set_allocators(*changed_tokens.node_pool, context.default_allocator);
	changed_probe.current_scope = Extended.push_lexical_scope(*changed_probe);
	assert(Extended.reuse_simple_declaration(*changed_probe) == null);
	Extended.release_parser_tree(*changed_tokens);
	Extended.release_parser_names(*changed_tokens);
	changed_statements := changed.root.(*Extended.Parser_Block).statements;
	changed_fresh_statements := changed_fresh.root.(*Extended.Parser_Block).statements;
	changed_binary := changed_statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Binary_Operator);
	changed_fresh_binary := changed_fresh_statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Binary_Operator);
	assert(changed_binary.operator_type == .LOGICAL_AND && changed_binary.operator_type == changed_fresh_binary.operator_type);
	assert(changed_binary.first_token == changed_fresh_binary.first_token && changed_binary.one_past_last_token == changed_fresh_binary.one_past_last_token);
	assert(changed_binary.left.(*Extended.Parser_Binary_Operator).operator_type == .LOGICAL_AND);
	assert(changed_binary.right.(*Extended.Parser_Ident).resolved_declaration == changed_statements[2].(*Extended.Parser_Declaration));
	assert(changed.diagnostics.count == changed_fresh.diagnostics.count && changed.restart_points.count == changed_fresh.restart_points.count);
	assert(Extended.reconstruct_source(*changed) == changed_source);
	Extended.release_parser_tree(*changed);
	Extended.release_parser_names(*changed);
	Extended.release_parser_tree(*changed_fresh);
	Extended.release_parser_names(*changed_fresh);
	free(changed_source);

	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(inner.left.(*Extended.Parser_Ident).name == "middle" && Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);
}

test_bitwise_ast_reuse :: () {
	old_source := copy_string(			   "left :: 1; middle :: 2; right :: 3; last :: 4; result := left | middle & right ^ last;");
	new_source := copy_string("added :: 0;\nleft :: 1; middle :: 2; right :: 3; last :: 4; result := left | middle & right ^ last;");
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE && fresh.status == .COMPLETE);

	statements := updated.root.(*Extended.Parser_Block).statements;
	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, cursor=statements[5].first_token.(s64)};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root && probe_tokens.root.(*Extended.Parser_Declaration).expression.kind == .BINARY_OPERATOR);
	assert(probe.current_scope.references.count == 4);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);

	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	xor_node := statements[5].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Binary_Operator);
	fresh_xor := fresh_statements[5].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Binary_Operator);
	assert(xor_node.operator_type == #char "^" && xor_node.operator_type == fresh_xor.operator_type);
	assert(xor_node.first_token == fresh_xor.first_token && xor_node.one_past_last_token == fresh_xor.one_past_last_token);
	assert(xor_node.l0 == fresh_xor.l0 && xor_node.c0 == fresh_xor.c0 && xor_node.l1 == fresh_xor.l1 && xor_node.c1 == fresh_xor.c1);
	and_node := xor_node.left.(*Extended.Parser_Binary_Operator);
	fresh_and := fresh_xor.left.(*Extended.Parser_Binary_Operator);
	assert(and_node.operator_type == #char "&" && and_node.operator_type == fresh_and.operator_type);
	assert(and_node.first_token == fresh_and.first_token && and_node.one_past_last_token == fresh_and.one_past_last_token);
	or_node := and_node.left.(*Extended.Parser_Binary_Operator);
	fresh_or := fresh_and.left.(*Extended.Parser_Binary_Operator);
	assert(or_node.operator_type == #char "|" && or_node.operator_type == fresh_or.operator_type);
	assert(or_node.first_token == fresh_or.first_token && or_node.one_past_last_token == fresh_or.one_past_last_token);
	assert(or_node.left.(*Extended.Parser_Ident).resolved_declaration == statements[1].(*Extended.Parser_Declaration));
	assert(or_node.right.(*Extended.Parser_Ident).resolved_declaration == statements[2].(*Extended.Parser_Declaration));
	assert(and_node.right.(*Extended.Parser_Ident).resolved_declaration == statements[3].(*Extended.Parser_Declaration));
	assert(xor_node.right.(*Extended.Parser_Ident).resolved_declaration == statements[4].(*Extended.Parser_Declaration));
	assert(fresh_or.left.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[1].(*Extended.Parser_Declaration));
	assert(fresh_or.right.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[2].(*Extended.Parser_Declaration));
	assert(fresh_and.right.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[3].(*Extended.Parser_Declaration));
	assert(fresh_xor.right.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[4].(*Extended.Parser_Declaration));
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);

	changed_source := copy_string("left :: 1; middle :: 2; right :: 3; last :: 4; result := left & middle & right ^ last;");
	operator_start := "left :: 1; middle :: 2; right :: 3; last :: 4; result := left ".count;
	changed, changed_ok := Extended.parse_file_edit(*old, operator_start, operator_start + 1, changed_source);
	changed_fresh := Extended.parse_file(changed_source);
	assert(changed_ok && changed.status == .COMPLETE && changed_fresh.status == .COMPLETE);
	changed_tokens := Extended.materialise_tokens(changed_source);
	changed_probe := Extended.Parser.{parsed=*changed_tokens, edit_source=*old, edit_start=operator_start, edit_end=operator_start + 1, cursor=changed.root.(*Extended.Parser_Block).statements[4].first_token.(s64)};
	set_allocators(*changed_tokens.node_pool, context.default_allocator);
	changed_probe.current_scope = Extended.push_lexical_scope(*changed_probe);
	assert(Extended.reuse_simple_declaration(*changed_probe) == null);
	Extended.release_parser_tree(*changed_tokens);
	Extended.release_parser_names(*changed_tokens);
	changed_statements := changed.root.(*Extended.Parser_Block).statements;
	changed_fresh_statements := changed_fresh.root.(*Extended.Parser_Block).statements;
	changed_xor := changed_statements[4].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Binary_Operator);
	changed_fresh_xor := changed_fresh_statements[4].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Binary_Operator);
	assert(changed_xor.operator_type == #char "^" && changed_xor.operator_type == changed_fresh_xor.operator_type);
	assert(changed_xor.first_token == changed_fresh_xor.first_token && changed_xor.one_past_last_token == changed_fresh_xor.one_past_last_token);
	assert(changed_xor.left.(*Extended.Parser_Binary_Operator).left.(*Extended.Parser_Binary_Operator).operator_type == #char "&");
	assert(changed.diagnostics.count == changed_fresh.diagnostics.count && changed.restart_points.count == changed_fresh.restart_points.count);
	assert(Extended.reconstruct_source(*changed) == changed_source);
	Extended.release_parser_tree(*changed);
	Extended.release_parser_names(*changed);
	Extended.release_parser_tree(*changed_fresh);
	Extended.release_parser_names(*changed_fresh);
	free(changed_source);

	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(or_node.left.(*Extended.Parser_Ident).name == "left" && Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);
}

test_shift_rotate_ast_reuse :: () {
	check_binary_ast_reuse("<<", .SHIFT_LEFT);
	check_binary_ast_reuse(">>", .SHIFT_RIGHT);
	check_binary_ast_reuse("<<<", .ROTATE_LEFT);
	check_binary_ast_reuse(">>>", .ROTATE_RIGHT);

	old_source := copy_string("left :: 7; right :: 3; result := left << right;");
	new_source := copy_string("left :: 7; right :: 3; result := left <<< right;");
	operator_start := "left :: 7; right :: 3; result := left ".count;
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, operator_start, operator_start + 2, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE && fresh.status == .COMPLETE);
	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, edit_start=operator_start, edit_end=operator_start + 2, cursor=updated.root.(*Extended.Parser_Block).statements[2].first_token.(s64)};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	assert(Extended.reuse_simple_declaration(*probe) == null);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);
	statements := updated.root.(*Extended.Parser_Block).statements;
	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	binary := statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Binary_Operator);
	fresh_binary := fresh_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Binary_Operator);
	assert(binary.operator_type == .ROTATE_LEFT && binary.operator_type == fresh_binary.operator_type);
	assert(binary.first_token == fresh_binary.first_token && binary.one_past_last_token == fresh_binary.one_past_last_token);
	assert(binary.left.(*Extended.Parser_Ident).resolved_declaration == statements[0].(*Extended.Parser_Declaration));
	assert(binary.right.(*Extended.Parser_Ident).resolved_declaration == statements[1].(*Extended.Parser_Declaration));
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	assert(Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(old_source);
	free(new_source);
}

test_operator_grouping_edit :: () {
	old_source := copy_string("left :: 1; right :: 2; value := (left + right) * 3; keep := value;");
	new_source := copy_string("left :: 1; right :: 2; value := left + right * 3; keep := value;");
	expression_start := "left :: 1; right :: 2; value := ".count;
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, expression_start, expression_start + "(left + right) * 3".count, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE && fresh.status == .COMPLETE);
	statements := updated.root.(*Extended.Parser_Block).statements;
	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, edit_start=expression_start, edit_end=expression_start + "(left + right) * 3".count, cursor=statements[2].first_token.(s64)};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	assert(Extended.reuse_simple_declaration(*probe) == null);
	probe.cursor = statements[3].first_token.(s64);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root != null);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);
	binary := statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Binary_Operator);
	fresh_binary := fresh_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Binary_Operator);
	assert(binary.operator_type == #char "+" && binary.operator_type == fresh_binary.operator_type);
	assert(binary.first_token == fresh_binary.first_token && binary.one_past_last_token == fresh_binary.one_past_last_token);
	assert(binary.l0 == fresh_binary.l0 && binary.c0 == fresh_binary.c0 && binary.l1 == fresh_binary.l1 && binary.c1 == fresh_binary.c1);
	assert(binary.left.(*Extended.Parser_Ident).resolved_declaration == statements[0].(*Extended.Parser_Declaration));
	assert(fresh_binary.left.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[0].(*Extended.Parser_Declaration));
	product := binary.right.(*Extended.Parser_Binary_Operator);
	fresh_product := fresh_binary.right.(*Extended.Parser_Binary_Operator);
	assert(product.operator_type == #char "*" && product.operator_type == fresh_product.operator_type);
	assert(product.first_token == fresh_product.first_token && product.one_past_last_token == fresh_product.one_past_last_token);
	assert(product.left.(*Extended.Parser_Ident).resolved_declaration == statements[1].(*Extended.Parser_Declaration));
	assert(fresh_product.left.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[1].(*Extended.Parser_Declaration));
	assert(statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == statements[2].(*Extended.Parser_Declaration));
	assert(fresh_statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[2].(*Extended.Parser_Declaration));
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(binary.left.(*Extended.Parser_Ident).name == "left" && Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);
}

test_unary_ast_reuse :: () {
	check_excluded_operator_fallback(".member", #char ".", true);
	check_excluded_operator_fallback("left. 3", #char ".", false, false, true);
	check_excluded_operator_fallback("!null", #char "!", true, true);
	check_excluded_operator_fallback("left + null", #char "+", false, true);
	check_excluded_operator_fallback("left[null]", .ARRAY_SUBSCRIPT, false, true);
	check_excluded_operator_fallback("left = right", #char "=", false);
	check_excluded_operator_fallback("left += right", .PLUS_ASSIGN, false);
	check_excluded_operator_fallback("left -= right", .MINUS_ASSIGN, false);
	check_excluded_operator_fallback("left *= right", .TIMES_ASSIGN, false);
	check_excluded_operator_fallback("left /= right", .DIV_ASSIGN, false);
	check_excluded_operator_fallback("left %= right", .MOD_ASSIGN, false);
	check_excluded_operator_fallback("left <<= right", .SHIFT_LEFT_ASSIGN, false);
	check_excluded_operator_fallback("left >>= right", .SHIFT_RIGHT_ASSIGN, false);
	check_excluded_operator_fallback("left <<<= right", .ROTATE_LEFT_ASSIGN, false);
	check_excluded_operator_fallback("left >>>= right", .ROTATE_RIGHT_ASSIGN, false);
	check_excluded_operator_fallback("left &= right", .BITWISE_AND_ASSIGN, false);
	check_excluded_operator_fallback("left |= right", .BITWISE_OR_ASSIGN, false);
	check_excluded_operator_fallback("left ^= right", .BITWISE_XOR_ASSIGN, false);
	check_excluded_operator_fallback("left &&= right", .LOGICAL_AND_ASSIGN, false);
	check_excluded_operator_fallback("left ||= right", .LOGICAL_OR_ASSIGN, false);
	old_source := copy_string("flag :: true; result := !flag;");
	new_source := copy_string("added :: false;\nflag :: true; result := !flag;");
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && updated.status == .COMPLETE && fresh.status == .COMPLETE);

	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, cursor=10};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root && probe_tokens.root.(*Extended.Parser_Declaration).expression.kind == .UNARY_OPERATOR);
	assert(probe.current_scope.references.count == 1);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);

	updated_statements := updated.root.(*Extended.Parser_Block).statements;
	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	updated_unary := updated_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Unary_Operator);
	fresh_unary := fresh_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Unary_Operator);
	assert(updated_unary.kind == fresh_unary.kind && updated_unary.node_flags == fresh_unary.node_flags);
	assert(updated_unary.operator_type == fresh_unary.operator_type && updated_unary.operator_type == #char "!");
	assert(updated_unary.first_token == fresh_unary.first_token && updated_unary.one_past_last_token == fresh_unary.one_past_last_token);
	assert(updated_unary.l0 == fresh_unary.l0 && updated_unary.c0 == fresh_unary.c0 && updated_unary.l1 == fresh_unary.l1 && updated_unary.c1 == fresh_unary.c1);
	updated_reference := updated_unary.subexpression.(*Extended.Parser_Ident);
	fresh_reference := fresh_unary.subexpression.(*Extended.Parser_Ident);
	assert(updated_reference.node_flags == fresh_reference.node_flags && updated_reference.flags == fresh_reference.flags);
	assert(updated_reference.first_token == fresh_reference.first_token && updated_reference.one_past_last_token == fresh_reference.one_past_last_token);
	assert(updated_reference.l0 == fresh_reference.l0 && updated_reference.c0 == fresh_reference.c0 && updated_reference.l1 == fresh_reference.l1 && updated_reference.c1 == fresh_reference.c1);
	assert(updated_reference.resolved_declaration == updated_statements[1].(*Extended.Parser_Declaration));
	assert(fresh_reference.resolved_declaration == fresh_statements[1].(*Extended.Parser_Declaration));
	assert_eligible_edit_matches_fresh(*updated, *fresh);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(updated_reference.name == "flag" && Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);
}

assert_eligible_edit_matches_fresh :: (updated: *Extended.Parsed_Source, fresh: *Extended.Parsed_Source) {
	assert(updated.status == fresh.status && updated.tokens.count == fresh.tokens.count);
	for updated.tokens {
		other := fresh.tokens[it_index];
		assert(it.type == other.type && it.value_flags == other.value_flags);
		assert(it.byte_start == other.byte_start && it.byte_end == other.byte_end && it.preceding_trivia_byte_start == other.preceding_trivia_byte_start);
		assert(it.l0 == other.l0 && it.c0 == other.c0 && it.l1 == other.l1 && it.c1 == other.c1);
		assert(it.original_text == other.original_text && it.preceding_trivia == other.preceding_trivia && it.trailing_trivia == other.trailing_trivia);
	}

	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.recovery_records.count == fresh.recovery_records.count);
	assert(updated.restart_points.count == fresh.restart_points.count);
	for updated.diagnostics {
		other := fresh.diagnostics[it_index];
		assert(it.kind == other.kind && it.message == other.message);
		assert(it.span.first == other.span.first && it.span.one_past_last == other.span.one_past_last);
		assert(it.lexer_line == other.lexer_line && it.lexer_column == other.lexer_column);
	}

	for updated.recovery_records {
		other := fresh.recovery_records[it_index];
		assert(it.kind == other.kind && it.span.first == other.span.first && it.span.one_past_last == other.span.one_past_last);
		assert(it.diagnostic_index == other.diagnostic_index && it.synthetic_token_index == other.synthetic_token_index);
	}

	for updated.restart_points {
		other := fresh.restart_points[it_index];
		assert(it.kind == other.kind && it.span.first == other.span.first && it.span.one_past_last == other.span.one_past_last);
	}

	assert(Extended.reconstruct_source(updated) == Extended.reconstruct_source(fresh));
}

check_excluded_operator_fallback :: (expression: string, expected_operator: Operator_Type, is_unary: bool, unowned_child := false, non_ident_member := false) {
	old_source := copy_string(tprint(			  "left :: 1; right :: 2; value := %; keep := value;", expression));
	new_source := copy_string(tprint("added :: 0;\nleft :: 1; right :: 2; value := %; keep := value;", expression));
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE && fresh.status == .COMPLETE, "Excluded operator: %", expression);
	old_expression := old.root.(*Extended.Parser_Block).statements[2].(*Extended.Parser_Declaration).expression;
	assert(!Extended.reusable_expression(old_expression));
	statements := updated.root.(*Extended.Parser_Block).statements;
	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, cursor=statements[3].first_token.(s64)};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	assert(Extended.reuse_simple_declaration(*probe) == null);
	probe.cursor = statements[4].first_token.(s64);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root != null);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);
	expression_node := statements[3].(*Extended.Parser_Declaration).expression;
	fresh_expression := fresh_statements[3].(*Extended.Parser_Declaration).expression;
	assert(expression_node.kind == fresh_expression.kind);
	assert(expression_node.first_token == fresh_expression.first_token && expression_node.one_past_last_token == fresh_expression.one_past_last_token);
	assert(expression_node.l0 == fresh_expression.l0 && expression_node.c0 == fresh_expression.c0 && expression_node.l1 == fresh_expression.l1 && expression_node.c1 == fresh_expression.c1);
	if is_unary {
		assert(expression_node.kind == .UNARY_OPERATOR && expression_node.(*Extended.Parser_Unary_Operator).operator_type == expected_operator);
		assert(expression_node.(*Extended.Parser_Unary_Operator).subexpression.first_token == fresh_expression.(*Extended.Parser_Unary_Operator).subexpression.first_token);
		if unowned_child {
			assert(expression_node.(*Extended.Parser_Unary_Operator).subexpression.(*Extended.Parser_Literal).value_type == .POINTER);
		}
	} else {
		assert(expression_node.kind == .BINARY_OPERATOR && expression_node.(*Extended.Parser_Binary_Operator).operator_type == expected_operator);
		assert(expression_node.(*Extended.Parser_Binary_Operator).left.first_token == fresh_expression.(*Extended.Parser_Binary_Operator).left.first_token);
		assert(expression_node.(*Extended.Parser_Binary_Operator).left.(*Extended.Parser_Ident).resolved_declaration == statements[1].(*Extended.Parser_Declaration));
		assert(fresh_expression.(*Extended.Parser_Binary_Operator).left.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[1].(*Extended.Parser_Declaration));
		if unowned_child {
			assert(expression_node.(*Extended.Parser_Binary_Operator).right.(*Extended.Parser_Literal).value_type == .POINTER);
			assert(expression_node.(*Extended.Parser_Binary_Operator).right.first_token == fresh_expression.(*Extended.Parser_Binary_Operator).right.first_token);
		} else if non_ident_member {
			assert(expression_node.(*Extended.Parser_Binary_Operator).right.kind != .IDENT);
			assert(expression_node.(*Extended.Parser_Binary_Operator).right.kind == fresh_expression.(*Extended.Parser_Binary_Operator).right.kind);
			assert(expression_node.(*Extended.Parser_Binary_Operator).right.first_token == fresh_expression.(*Extended.Parser_Binary_Operator).right.first_token);
		} else {
			assert(expression_node.(*Extended.Parser_Binary_Operator).right.(*Extended.Parser_Ident).resolved_declaration == statements[2].(*Extended.Parser_Declaration));
			assert(fresh_expression.(*Extended.Parser_Binary_Operator).right.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[2].(*Extended.Parser_Declaration));
		}
	}

	assert(statements[4].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == statements[3].(*Extended.Parser_Declaration));
	assert(fresh_statements[4].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[3].(*Extended.Parser_Declaration));
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);
}

test_query_fallback :: () {
	old_source := copy_string(			   "value :: 1; result := type_of(null); keep := result;");
	new_source := copy_string("added :: 0;\nvalue :: 1; result := type_of(null); keep := result;");
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE && fresh.status == .COMPLETE);
	old_query := old.root.(*Extended.Parser_Block).statements[1].(*Extended.Parser_Declaration).expression;
	assert(old_query.kind == .EXPRESSION_QUERY && !Extended.reusable_expression(old_query));
	statements := updated.root.(*Extended.Parser_Block).statements;
	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, cursor=statements[2].first_token.(s64)};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	assert(Extended.reuse_simple_declaration(*probe) == null);
	probe.cursor = statements[3].first_token.(s64);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root != null);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);
	query := statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Expression_Query);
	fresh_query := fresh_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Expression_Query);
	assert(query.node_flags == fresh_query.node_flags);
	assert(query.query_kind == .TYPE_OF && query.query_kind == fresh_query.query_kind);
	assert(query.first_token == fresh_query.first_token && query.one_past_last_token == fresh_query.one_past_last_token);
	assert(query.l0 == fresh_query.l0 && query.c0 == fresh_query.c0 && query.l1 == fresh_query.l1 && query.c1 == fresh_query.c1);
	assert(query.expression_to_query.(*Extended.Parser_Literal).value_type == .POINTER);
	assert(query.expression_to_query.first_token == fresh_query.expression_to_query.first_token && query.expression_to_query.one_past_last_token == fresh_query.expression_to_query.one_past_last_token);
	assert(statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == statements[2].(*Extended.Parser_Declaration));
	assert(fresh_statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[2].(*Extended.Parser_Declaration));
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);
}

test_excluded_expression_nodes :: () {
	for 0..58 {
		if it == 13 {
			continue;
		}


		candidate := Extended.Parser_Node.{};
		candidate.kind = xx it;
		if (candidate.kind == .LITERAL || candidate.kind == .IDENT || candidate.kind == .UNARY_OPERATOR
			|| candidate.kind == .BINARY_OPERATOR || candidate.kind == .PROCEDURE_CALL || candidate.kind == .CAST
			|| candidate.kind == .EXPRESSION_QUERY || candidate.kind == .TYPE_QUERY
		) {
			continue;
		}


		assert(!Extended.reusable_expression(*candidate), "Unexpected expression reuse kind: %", candidate.kind);
	}

	check_excluded_expression_node("context", .CONTEXT);
	check_excluded_expression_node("value + ---", .BINARY_OPERATOR);
	check_excluded_expression_node("arg => arg", .PROCEDURE_HEADER);
	check_excluded_expression_node("is_constant(null)", .EXPRESSION_QUERY);
	check_excluded_expression_node("code_of(null)", .EXPRESSION_QUERY);
	check_excluded_expression_node("type_of(#run value)", .EXPRESSION_QUERY);
	check_excluded_expression_node("size_of([#run 4] Target)", .TYPE_QUERY);
	check_excluded_expression_node("type_info([#run 4] Target)", .TYPE_QUERY);
	check_excluded_expression_node("initializer_of([#run 4] Target)", .TYPE_QUERY);
	check_excluded_expression_node("#this", .DIRECTIVE_THIS);
	check_excluded_expression_node("#Context", .DIRECTIVE_CONTEXT_TYPE);
	check_excluded_expression_node("#load \"local.jai\"", .DIRECTIVE_LOAD);
	check_excluded_expression_node("#bytes value", .DIRECTIVE_BYTES);
	check_excluded_expression_node("#procedure_name(value)", .DIRECTIVE_PROCEDURE_NAME);
	check_excluded_expression_node("#wildcard", .DIRECTIVE_WILDCARD);
	check_excluded_expression_node("#exists(value, Target)", .DIRECTIVE_EXISTS);
	check_excluded_expression_node("#import,file \"../module.jai\"", .DIRECTIVE_IMPORT);
	check_excluded_expression_node("#poke_name value renamed", .DIRECTIVE_POKE_NAME);
	check_excluded_expression_node("#library,system \"Example\"", .DIRECTIVE_LIBRARY);
	check_excluded_expression_node("#location(value)", .DIRECTIVE_LOCATION);
	check_excluded_expression_node("#caller_location", .DIRECTIVE_LOCATION);
	check_excluded_expression_node("#run value", .DIRECTIVE_RUN);
	check_excluded_expression_node("#run,host value", .DIRECTIVE_RUN);
	check_excluded_expression_node("#run,stallable value", .DIRECTIVE_RUN);
	check_excluded_expression_node("#assert value \"message\"", .DIRECTIVE_RUN);
	check_excluded_expression_node("#run { local := value; return local; }", .DIRECTIVE_RUN);
	check_excluded_expression_node("#code value", .DIRECTIVE_CODE);
	check_excluded_expression_node("#code,null", .DIRECTIVE_CODE);
	check_excluded_expression_node("#code { local := value; }", .DIRECTIVE_CODE);
	check_excluded_expression_node("#caller_code", .DIRECTIVE_CODE);
	check_excluded_expression_node("#insert,scope(value) value", .DIRECTIVE_INSERT);
	check_excluded_expression_node("#insert(break=break outer) value", .DIRECTIVE_INSERT);
	check_excluded_expression_node("#bake specialize(value)", .DIRECTIVE_BAKE);
	check_excluded_expression_node("#bake_arguments specialize(value)", .DIRECTIVE_BAKE);
	check_excluded_expression_node("ifx value then value else 1", .IF);
	check_excluded_expression_node("#ifx value then value else 1", .IF);
	check_excluded_expression_node("struct { field: s64; }", .STRUCT);
	check_excluded_expression_node("enum u16 { A; }", .ENUM);
}

test_excluded_file_nodes :: () {
	check_excluded_file_node("#scope_file", .DIRECTIVE_SCOPE);
	check_excluded_file_node("#add_context token: string;", .DIRECTIVE_ADD_CONTEXT);
	check_excluded_file_node("#through;", .DIRECTIVE_THROUGH);
	check_excluded_file_node("#overlay (value) bits: u64;", .DIRECTIVE_OVERLAY);
	check_excluded_file_node("#modify { return true; }", .DIRECTIVE_MODIFY);
	check_excluded_file_node("#module_parameters()(PROGRAM_DEBUG := false) { setup(); }", .DIRECTIVE_MODULE_PARAMETERS);
	check_excluded_file_node("#placeholder Apple;", .PLACEHOLDER);
}

check_excluded_file_node :: (directive: string, expected_kind: type_of(Extended.Parser_Node.kind)) {
	old_source := copy_string(tprint(			  "value :: 1; % keep := value;", directive));
	new_source := copy_string(tprint("added :: 0;\nvalue :: 1; % keep := value;", directive));
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE && fresh.status == .COMPLETE, "%", directive);
	old_node := old.root.(*Extended.Parser_Block).statements[1];
	statements := updated.root.(*Extended.Parser_Block).statements;
	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	assert(old_node.kind == expected_kind && statements[2].kind == expected_kind && fresh_statements[2].kind == expected_kind);
	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, cursor=statements[2].first_token.(s64)};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	assert(Extended.reuse_simple_declaration(*probe) == null);
	probe.cursor = statements[3].first_token.(s64);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root != null);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);
	assert(statements[2] != old_node && statements[2].first_token == fresh_statements[2].first_token);
	assert(statements[2].node_flags == fresh_statements[2].node_flags);
	assert(statements[2].one_past_last_token == fresh_statements[2].one_past_last_token);
	assert(statements[2].l0 == fresh_statements[2].l0 && statements[2].c0 == fresh_statements[2].c0);
	assert(statements[2].l1 == fresh_statements[2].l1 && statements[2].c1 == fresh_statements[2].c1);
	if expected_kind == {
		case .DIRECTIVE_ADD_CONTEXT;
			wrapped := statements[2].(*Extended.Parser_Directive_Add_Context).expression.(*Extended.Parser_Declaration);
			fresh_wrapped := fresh_statements[2].(*Extended.Parser_Directive_Add_Context).expression.(*Extended.Parser_Declaration);
			assert(wrapped != old_node.(*Extended.Parser_Directive_Add_Context).expression.(*Extended.Parser_Declaration) && wrapped.name == fresh_wrapped.name);
		case .DIRECTIVE_OVERLAY;
			overlay := statements[2].(*Extended.Parser_Directive_Overlay);
			fresh_overlay := fresh_statements[2].(*Extended.Parser_Directive_Overlay);
			assert(overlay.target_expression.(*Extended.Parser_Ident).resolved_declaration == statements[1].(*Extended.Parser_Declaration));
			assert(fresh_overlay.target_expression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[1].(*Extended.Parser_Declaration));
			assert(overlay.declaration_or_using.kind == fresh_overlay.declaration_or_using.kind);
	}

	assert(statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == statements[1].(*Extended.Parser_Declaration));
	assert(fresh_statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[1].(*Extended.Parser_Declaration));
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	assert_eligible_edit_matches_fresh(*updated, *fresh);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	if expected_kind == {
		case .DIRECTIVE_ADD_CONTEXT;
			assert(statements[2].(*Extended.Parser_Directive_Add_Context).expression.(*Extended.Parser_Declaration).name == "token");
		case .DIRECTIVE_OVERLAY;
			assert(statements[2].(*Extended.Parser_Directive_Overlay).target_expression.(*Extended.Parser_Ident).name == "value");
		case .PLACEHOLDER;
			assert(statements[2].(*Extended.Parser_Placeholder).name == "Apple");
	}

	assert(Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);
}

test_excluded_statement_nodes :: () {
	check_excluded_statement_node("{ local := value; }", .BLOCK);
	check_excluded_statement_node("return value;", .RETURN);
	check_excluded_statement_node("while value { break; }", .WHILE);
	check_excluded_statement_node("while value break;", .WHILE);
	check_excluded_statement_node("if value { return value; }", .IF);
	check_excluded_statement_node("if value return value;", .IF);
	check_excluded_statement_node("if value == { case 1; return value; case; }", .IF);
	check_excluded_statement_node("for item: value { continue; }", .FOR);
	check_excluded_statement_node("defer tick();", .DEFER);
	check_excluded_statement_node("using state;", .USING);
	check_excluded_statement_node("push_context new_context { return; }", .PUSH_CONTEXT);
	check_excluded_statement_node("#asm { mov dst, value; }", .ASM);
}

test_imperative_body_fallback :: () {
	old_source := copy_string(			   "outer :: true; run :: () { local := outer; if local { local := false; defer tick(); while local { return; } } } tail := outer;");
	new_source := copy_string("added :: 0;\nouter :: true; run :: () { local := outer; if local { local := false; defer tick(); while local { return; } } } tail := outer;");
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE && fresh.status == .COMPLETE);
	old_body := old.root.(*Extended.Parser_Block).statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block;
	statements := updated.root.(*Extended.Parser_Block).statements;
	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	body := statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block;
	fresh_body := fresh_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block;
	assert(body != old_body && body.statements[0] != old_body.statements[0]);
	assert(body.first_token == fresh_body.first_token && body.one_past_last_token == fresh_body.one_past_last_token);
	assert(body.statements.count == fresh_body.statements.count && body.statements.count == 2);
	assert(body.statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == statements[1].(*Extended.Parser_Declaration));
	assert(fresh_body.statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[1].(*Extended.Parser_Declaration));
	probe := Extended.Parser.{parsed=*updated, edit_source=*old, cursor=body.statements[0].first_token.(s64)};
	assert(Extended.reuse_simple_declaration(*probe) == null);
	conditional := body.statements[1].(*Extended.Parser_If);
	inner := conditional.then_block;
	inner_local := inner.statements[0].(*Extended.Parser_Declaration);
	loop := inner.statements[2].(*Extended.Parser_While);
	assert(inner.parent == body && inner.owning_statement == conditional);
	assert(conditional.condition.(*Extended.Parser_Ident).resolved_declaration == body.statements[0].(*Extended.Parser_Declaration));
	assert(loop.block.parent == inner && loop.block.owning_statement == loop);
	assert(loop.condition.(*Extended.Parser_Ident).resolved_declaration == inner_local);
	assert(inner.statements[1].kind == .DEFER && loop.block.statements[0].kind == .RETURN);
	assert(loop.condition.first_token == fresh_body.statements[1].(*Extended.Parser_If).then_block.statements[2].(*Extended.Parser_While).condition.first_token);
	assert(updated.root_scope.children.count == fresh.root_scope.children.count);
	for updated.restart_points {
		other := fresh.restart_points[it_index];
		assert(it.kind == other.kind && it.span.first == other.span.first && it.span.one_past_last == other.span.one_past_last);
	}

	edit_start :=				"outer :: true; run :: () { local := outer; if local { local := ".count;
	inner_source := copy_string("outer :: true; run :: () { local := outer; if local { local := outer; defer tick(); while local { return; } } } tail := outer;");
	inner_updated, inner_ok := Extended.parse_file_edit(*old, edit_start, edit_start + "false".count, inner_source);
	inner_fresh := Extended.parse_file(inner_source);
	assert(inner_ok && inner_updated.status == .COMPLETE && inner_fresh.status == .COMPLETE);
	inner_body := inner_updated.root.(*Extended.Parser_Block).statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block;
	inner_fresh_body := inner_fresh.root.(*Extended.Parser_Block).statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block;
	assert(inner_body != old_body && inner_body.statements[0] != old_body.statements[0]);
	assert(inner_body.first_token == inner_fresh_body.first_token && inner_body.one_past_last_token == inner_fresh_body.one_past_last_token);
	inner_if := inner_body.statements[1].(*Extended.Parser_If);
	inner_fresh_if := inner_fresh_body.statements[1].(*Extended.Parser_If);
	assert(inner_if.then_block.statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == inner_updated.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Declaration));
	assert(inner_fresh_if.then_block.statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == inner_fresh.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Declaration));
	assert(inner_if.then_block.statements[2].(*Extended.Parser_While).condition.(*Extended.Parser_Ident).resolved_declaration == inner_if.then_block.statements[0].(*Extended.Parser_Declaration));
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	assert(inner_updated.diagnostics.count == inner_fresh.diagnostics.count && inner_updated.restart_points.count == inner_fresh.restart_points.count);
	assert_eligible_edit_matches_fresh(*updated, *fresh);
	assert_eligible_edit_matches_fresh(*inner_updated, *inner_fresh);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(loop.condition.(*Extended.Parser_Ident).resolved_declaration == inner_local);
	assert(inner_if.then_block.statements[2].(*Extended.Parser_While).condition.(*Extended.Parser_Ident).name == "local");
	assert(Extended.reconstruct_source(*updated) == new_source);
	assert(Extended.reconstruct_source(*inner_updated) == inner_source);
	Extended.release_parser_tree(*inner_updated);
	Extended.release_parser_names(*inner_updated);
	Extended.release_parser_tree(*inner_fresh);
	Extended.release_parser_names(*inner_fresh);
	free(inner_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);
}

test_aggregate_body_fallback :: () {
	old_source := copy_string(			   "Thing :: struct { field: s64; use := field; field = 1; } tail := 2;");
	new_source := copy_string("added :: 0;\nThing :: struct { field: s64; use := field; field = 1; } tail := 2;");
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE && fresh.status == .COMPLETE);
	old_block := old.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Struct).block;
	block := updated.root.(*Extended.Parser_Block).statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Struct).block;
	fresh_block := fresh.root.(*Extended.Parser_Block).statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Struct).block;
	assert(block != old_block && block.statements[0] != old_block.statements[0]);
	assert(block.statements.count == fresh_block.statements.count && block.statements.count == 3);
	assert(block.first_token == fresh_block.first_token && block.one_past_last_token == fresh_block.one_past_last_token);
	assert(block.statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == block.statements[0].(*Extended.Parser_Declaration));
	assert(fresh_block.statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == fresh_block.statements[0].(*Extended.Parser_Declaration));
	default_assignment := block.statements[2].(*Extended.Parser_Binary_Operator);
	assert(default_assignment.left.(*Extended.Parser_Ident).resolved_declaration == block.statements[0].(*Extended.Parser_Declaration));
	assert(fresh_block.statements[2].(*Extended.Parser_Binary_Operator).left.(*Extended.Parser_Ident).resolved_declaration == fresh_block.statements[0].(*Extended.Parser_Declaration));
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);

	inner_source := copy_string("Thing :: struct { field: u64; use := field; field = 1; } tail := 2;");
	inner_fresh := Extended.parse_file(inner_source);
	edit_start := "Thing :: struct { field: ".count;
	inner_updated, inner_ok := Extended.parse_file_edit(*old, edit_start, edit_start + "s64".count, inner_source);
	assert(inner_ok && inner_updated.status == .COMPLETE && inner_fresh.status == .COMPLETE);
	inner_block := inner_updated.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Struct).block;
	inner_fresh_block := inner_fresh.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Struct).block;
	assert(inner_block != old_block && inner_block.statements[0] != old_block.statements[0]);
	assert(inner_block.statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == inner_block.statements[0].(*Extended.Parser_Declaration));
	assert(inner_block.statements[2].(*Extended.Parser_Binary_Operator).left.(*Extended.Parser_Ident).resolved_declaration == inner_block.statements[0].(*Extended.Parser_Declaration));
	assert(inner_fresh_block.statements[2].(*Extended.Parser_Binary_Operator).left.(*Extended.Parser_Ident).resolved_declaration == inner_fresh_block.statements[0].(*Extended.Parser_Declaration));
	assert(inner_block.first_token == inner_fresh_block.first_token && inner_block.one_past_last_token == inner_fresh_block.one_past_last_token);
	assert(inner_updated.diagnostics.count == inner_fresh.diagnostics.count && inner_updated.restart_points.count == inner_fresh.restart_points.count);
	assert_eligible_edit_matches_fresh(*updated, *fresh);
	assert_eligible_edit_matches_fresh(*inner_updated, *inner_fresh);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(default_assignment.left.(*Extended.Parser_Ident).name == "field");
	assert(inner_block.statements[2].(*Extended.Parser_Binary_Operator).left.(*Extended.Parser_Ident).name == "field");
	assert(Extended.reconstruct_source(*inner_updated) == inner_source);
	assert(Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*inner_updated);
	Extended.release_parser_names(*inner_updated);
	Extended.release_parser_tree(*inner_fresh);
	Extended.release_parser_names(*inner_fresh);
	free(inner_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);
}

test_aggregate_parameter_block_fallback :: () {
	old_source := copy_string(			   "Thing :: struct (T: Type, N := 2) { value: T; C :: N; } tail := 2;");
	new_source := copy_string("added :: 0;\nThing :: struct (T: Type, N := 2) { value: T; C :: N; } tail := 2;");
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE && fresh.status == .COMPLETE);
	old_struct := old.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Struct);
	structure := updated.root.(*Extended.Parser_Block).statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Struct);
	fresh_struct := fresh.root.(*Extended.Parser_Block).statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Struct);
	assert(structure.arguments_block != old_struct.arguments_block && structure.arguments_block.block_type == .STRUCT_ARGUMENTS);
	assert(structure.arguments_block.statements.count == 2 && structure.arguments_block.statements[0] != old_struct.arguments_block.statements[0]);
	assert(structure.arguments_block.first_token == fresh_struct.arguments_block.first_token && structure.arguments_block.one_past_last_token == fresh_struct.arguments_block.one_past_last_token);
	assert(
		structure.block.statements[0].(*Extended.Parser_Declaration).type_inst.type_valued_expression.(*Extended.Parser_Ident).resolved_declaration
		== structure.arguments_block.statements[0].(*Extended.Parser_Declaration)
	);
	assert(fresh_struct.block.statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == fresh_struct.arguments_block.statements[1].(*Extended.Parser_Declaration));
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);

	inner_source := copy_string("Thing :: struct (T: Type, N := 3) { value: T; C :: N; } tail := 2;");
	inner_fresh := Extended.parse_file(inner_source);
	edit_start := "Thing :: struct (T: Type, N := ".count;
	inner_updated, inner_ok := Extended.parse_file_edit(*old, edit_start, edit_start + 1, inner_source);
	assert(inner_ok && inner_updated.status == .COMPLETE && inner_fresh.status == .COMPLETE);
	inner_struct := inner_updated.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Struct);
	inner_fresh_struct := inner_fresh.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Struct);
	assert(inner_struct.arguments_block != old_struct.arguments_block && inner_struct.arguments_block.statements[0] != old_struct.arguments_block.statements[0]);
	assert(inner_struct.arguments_block.statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Literal)._u64 == 3);
	assert(inner_struct.block.statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == inner_struct.arguments_block.statements[1].(*Extended.Parser_Declaration));
	assert(inner_fresh_struct.block.statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == inner_fresh_struct.arguments_block.statements[1].(*Extended.Parser_Declaration));
	assert(inner_updated.diagnostics.count == inner_fresh.diagnostics.count && inner_updated.restart_points.count == inner_fresh.restart_points.count);
	assert_eligible_edit_matches_fresh(*updated, *fresh);
	assert_eligible_edit_matches_fresh(*inner_updated, *inner_fresh);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(structure.arguments_block.statements[1].(*Extended.Parser_Declaration).name == "N");
	assert(inner_struct.arguments_block.statements[1].(*Extended.Parser_Declaration).name == "N");
	assert(Extended.reconstruct_source(*updated) == new_source && Extended.reconstruct_source(*inner_updated) == inner_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	Extended.release_parser_tree(*inner_updated);
	Extended.release_parser_names(*inner_updated);
	Extended.release_parser_tree(*inner_fresh);
	Extended.release_parser_names(*inner_fresh);
	free(new_source);
	free(inner_source);
}

test_single_declaration_branch_fallback :: () {
	old_source := copy_string(			   "#if true target :: 1; use := target;");
	new_source := copy_string("added :: 0;\n#if true target :: 1; use := target;");
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE && fresh.status == .COMPLETE);
	old_branch := old.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_If).then_block;
	branch := updated.root.(*Extended.Parser_Block).statements[1].(*Extended.Parser_If).then_block;
	fresh_branch := fresh.root.(*Extended.Parser_Block).statements[1].(*Extended.Parser_If).then_block;
	assert(branch.block_type == .DATA_DECLARATIONS && branch != old_branch && branch.statements[0] != old_branch.statements[0]);
	assert(branch.parent == fresh_branch.parent && branch.owning_statement == updated.root.(*Extended.Parser_Block).statements[1]);
	assert(branch.first_token == fresh_branch.first_token && branch.one_past_last_token == fresh_branch.one_past_last_token);
	assert(updated.root.(*Extended.Parser_Block).statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == branch.statements[0].(*Extended.Parser_Declaration));
	assert(fresh.root.(*Extended.Parser_Block).statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == fresh_branch.statements[0].(*Extended.Parser_Declaration));
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	assert_eligible_edit_matches_fresh(*updated, *fresh);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(branch.statements[0].(*Extended.Parser_Declaration).name == "target");
	assert(Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);
}

test_synthetic_imperative_block_fallback :: () {
	old_source := copy_string(			   "lambda := x => x; value := ifx true then 1 else 2;");
	new_source := copy_string("added :: 0;\nlambda := x => x; value := ifx true then 1 else 2;");
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE && fresh.status == .COMPLETE);
	old_statements := old.root.(*Extended.Parser_Block).statements;
	statements := updated.root.(*Extended.Parser_Block).statements;
	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	body := statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null;
	old_body := old_statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null;
	fresh_body := fresh_statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null;
	assert(body.block.block_type == .IMPERATIVE && body.block != old_body.block && body.block.statements[0] != old_body.block.statements[0]);
	assert(body.block.owning_statement == body && body.block.first_token == fresh_body.block.first_token);
	assert((body.block.statements[0].(*Extended.Parser_Return).return_flags & .AUTO_INSERTED_FOR_QUICK_LAMBDA) != 0);
	conditional := statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_If);
	old_conditional := old_statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_If);
	fresh_conditional := fresh_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_If);
	assert(conditional.then_block != old_conditional.then_block && conditional.else_block != old_conditional.else_block);
	assert(conditional.then_block.block_type == .IMPERATIVE && conditional.else_block.block_type == .IMPERATIVE);
	assert(conditional.then_block.owning_statement == conditional && conditional.else_block.owning_statement == conditional);
	assert(conditional.then_block.first_token == fresh_conditional.then_block.first_token && conditional.else_block.one_past_last_token == fresh_conditional.else_block.one_past_last_token);
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	assert_eligible_edit_matches_fresh(*updated, *fresh);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(body.block.statements[0].(*Extended.Parser_Return).arguments_unsorted[0].expression.(*Extended.Parser_Ident).name == "x");
	assert(Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);
}

test_enum_body_fallback :: () {
	old_source := copy_string(			   "Mode :: enum u16 { FIRST; #if true { SECOND; } THIRD; } tail := 2;");
	new_source := copy_string("added :: 0;\nMode :: enum u16 { FIRST; #if true { SECOND; } THIRD; } tail := 2;");
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE && fresh.status == .COMPLETE);
	old_enum := old.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Enum);
	enumeration := updated.root.(*Extended.Parser_Block).statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Enum);
	fresh_enum := fresh.root.(*Extended.Parser_Block).statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Enum);
	assert(enumeration != old_enum && enumeration.block != old_enum.block);
	assert(enumeration.block.statements.count == 3 && enumeration.block.statements.count == fresh_enum.block.statements.count);
	assert(enumeration.block.statements[0] != old_enum.block.statements[0]);
	assert(enumeration.block.statements[0].(*Extended.Parser_Ident).name == "FIRST");
	assert(enumeration.block.statements[0].(*Extended.Parser_Ident).resolved_declaration == null);
	branch := enumeration.block.statements[1].(*Extended.Parser_If).then_block;
	fresh_branch := fresh_enum.block.statements[1].(*Extended.Parser_If).then_block;
	assert(branch != old_enum.block.statements[1].(*Extended.Parser_If).then_block);
	assert(branch.statements.count == 1 && branch.statements[0].(*Extended.Parser_Ident).name == "SECOND");
	assert(branch.statements[0].first_token == fresh_branch.statements[0].first_token);
	assert(enumeration.block.statements[2].(*Extended.Parser_Ident).name == "THIRD");
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);

	inner_source := copy_string("Mode :: enum u16 { FIRST; #if true { FOURTH; } THIRD; } tail := 2;");
	inner_fresh := Extended.parse_file(inner_source);
	edit_start := "Mode :: enum u16 { FIRST; #if true { ".count;
	inner_updated, inner_ok := Extended.parse_file_edit(*old, edit_start, edit_start + "SECOND".count, inner_source);
	assert(inner_ok && inner_updated.status == .COMPLETE && inner_fresh.status == .COMPLETE);
	inner_enum := inner_updated.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Enum);
	inner_fresh_enum := inner_fresh.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Enum);
	assert(inner_enum.block != old_enum.block && inner_enum.block.statements[0] != old_enum.block.statements[0]);
	inner_member := inner_enum.block.statements[1].(*Extended.Parser_If).then_block.statements[0].(*Extended.Parser_Ident);
	inner_fresh_member := inner_fresh_enum.block.statements[1].(*Extended.Parser_If).then_block.statements[0].(*Extended.Parser_Ident);
	assert(inner_member.name == "FOURTH" && inner_member.first_token == inner_fresh_member.first_token);
	assert(inner_member.resolved_declaration == null && inner_member != old_enum.block.statements[1].(*Extended.Parser_If).then_block.statements[0].(*Extended.Parser_Ident));
	assert(inner_updated.diagnostics.count == inner_fresh.diagnostics.count && inner_updated.restart_points.count == inner_fresh.restart_points.count);
	assert_eligible_edit_matches_fresh(*updated, *fresh);
	assert_eligible_edit_matches_fresh(*inner_updated, *inner_fresh);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(branch.statements[0].(*Extended.Parser_Ident).name == "SECOND");
	assert(inner_member.name == "FOURTH" && Extended.reconstruct_source(*inner_updated) == inner_source);
	assert(Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*inner_updated);
	Extended.release_parser_names(*inner_updated);
	Extended.release_parser_tree(*inner_fresh);
	Extended.release_parser_names(*inner_fresh);
	free(inner_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);
}

test_case_arm_fallback :: () {
	old_source := copy_string(			   "run :: () { outer := 1; if outer == { case 1; local := outer; case 2; local := 2; inner := local; case; return; } } tail := 2;");
	new_source := copy_string("added :: 0;\nrun :: () { outer := 1; if outer == { case 1; local := outer; case 2; local := 2; inner := local; case; return; } } tail := 2;");
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE && fresh.status == .COMPLETE);
	old_body := old.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block;
	body := updated.root.(*Extended.Parser_Block).statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block;
	fresh_body := fresh.root.(*Extended.Parser_Block).statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block;
	switch_node := body.statements[1].(*Extended.Parser_If);
	fresh_switch := fresh_body.statements[1].(*Extended.Parser_If);
	old_switch := old_body.statements[1].(*Extended.Parser_If);
	assert(switch_node != old_switch && switch_node.then_block != old_switch.then_block);
	assert(switch_node.then_block.statements.count == 3 && fresh_switch.then_block.statements.count == 3);
	assert(switch_node.condition.(*Extended.Parser_Ident).resolved_declaration == body.statements[0].(*Extended.Parser_Declaration));
	for switch_node.then_block.statements {
		arm := it.(*Extended.Parser_Case);
		fresh_arm := fresh_switch.then_block.statements[it_index].(*Extended.Parser_Case);
		assert(arm != old_switch.then_block.statements[it_index].(*Extended.Parser_Case) && arm.then_block != old_switch.then_block.statements[it_index].(*Extended.Parser_Case).then_block);
		assert(arm.owning_if == switch_node && arm.then_block.parent == switch_node.then_block && arm.then_block.owning_statement == arm);
		assert(arm.first_token == fresh_arm.first_token && arm.one_past_last_token == fresh_arm.one_past_last_token);
	}

	first_arm := switch_node.then_block.statements[0].(*Extended.Parser_Case);
	second_arm := switch_node.then_block.statements[1].(*Extended.Parser_Case);
	assert(first_arm.then_block.statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == body.statements[0].(*Extended.Parser_Declaration));
	assert(second_arm.then_block.statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == second_arm.then_block.statements[0].(*Extended.Parser_Declaration));
	assert(
		fresh_switch.then_block.statements[1].(*Extended.Parser_Case).then_block.statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration
		== fresh_switch.then_block.statements[1].(*Extended.Parser_Case).then_block.statements[0].(*Extended.Parser_Declaration)
	);
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);

	inner_source := copy_string("run :: () { outer := 1; if outer == { case 1; local := outer; case 2; local := 3; inner := local; case; return; } } tail := 2;");
	inner_fresh := Extended.parse_file(inner_source);
	edit_start := "run :: () { outer := 1; if outer == { case 1; local := outer; case 2; local := ".count;
	inner_updated, inner_ok := Extended.parse_file_edit(*old, edit_start, edit_start + 1, inner_source);
	assert(inner_ok && inner_updated.status == .COMPLETE && inner_fresh.status == .COMPLETE);
	inner_body := inner_updated.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block;
	inner_fresh_body := inner_fresh.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block;
	inner_switch := inner_body.statements[1].(*Extended.Parser_If);
	inner_fresh_switch := inner_fresh_body.statements[1].(*Extended.Parser_If);
	assert(inner_switch.then_block != old_switch.then_block && inner_switch.then_block.statements[0] != old_switch.then_block.statements[0]);
	inner_arm := inner_switch.then_block.statements[1].(*Extended.Parser_Case);
	inner_decl := inner_arm.then_block.statements[0].(*Extended.Parser_Declaration);
	assert(inner_arm != old_switch.then_block.statements[1].(*Extended.Parser_Case) && inner_decl.expression.(*Extended.Parser_Literal)._u64 == 3);
	assert(inner_arm.then_block.statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == inner_decl);
	assert(
		inner_fresh_switch.then_block.statements[1].(*Extended.Parser_Case).then_block.statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration
		== inner_fresh_switch.then_block.statements[1].(*Extended.Parser_Case).then_block.statements[0].(*Extended.Parser_Declaration)
	);
	assert(inner_updated.diagnostics.count == inner_fresh.diagnostics.count && inner_updated.restart_points.count == inner_fresh.restart_points.count);
	assert_eligible_edit_matches_fresh(*updated, *fresh);
	assert_eligible_edit_matches_fresh(*inner_updated, *inner_fresh);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(second_arm.then_block.statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).name == "local");
	assert(inner_arm.then_block.statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).name == "local");
	assert(Extended.reconstruct_source(*inner_updated) == inner_source);
	assert(Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*inner_updated);
	Extended.release_parser_names(*inner_updated);
	Extended.release_parser_tree(*inner_fresh);
	Extended.release_parser_names(*inner_fresh);
	free(inner_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);
}

check_excluded_statement_node :: (statement: string, expected_kind: type_of(Extended.Parser_Node.kind)) {
	old_source := copy_string(tprint(			  "value :: 1; run :: () { % keep := value; } tail := value;", statement));
	new_source := copy_string(tprint("added :: 0;\nvalue :: 1; run :: () { % keep := value; } tail := value;", statement));
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE && fresh.status == .COMPLETE, "%", statement);
	old_statements := old.root.(*Extended.Parser_Block).statements;
	statements := updated.root.(*Extended.Parser_Block).statements;
	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	old_procedure_body := old_statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null;
	procedure_body := statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null;
	fresh_procedure_body := fresh_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null;
	old_body := old_procedure_body.block;
	body := procedure_body.block;
	fresh_body := fresh_procedure_body.block;
	assert(old_body.statements[0].kind == expected_kind && body.statements[0].kind == expected_kind && fresh_body.statements[0].kind == expected_kind);
	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, cursor=statements[2].first_token.(s64)};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	assert(Extended.reuse_simple_declaration(*probe) == null);
	probe.cursor = statements[3].first_token.(s64);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root != null);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);
	assert(procedure_body != old_procedure_body && procedure_body.first_token == fresh_procedure_body.first_token);
	assert(procedure_body.one_past_last_token == fresh_procedure_body.one_past_last_token);
	assert(body != old_body && body.statements[0] != old_body.statements[0]);
	assert(body.statements[0].node_flags == fresh_body.statements[0].node_flags);
	assert(body.statements[0].first_token == fresh_body.statements[0].first_token && body.statements[0].one_past_last_token == fresh_body.statements[0].one_past_last_token);
	assert(body.statements[0].l0 == fresh_body.statements[0].l0 && body.statements[0].c0 == fresh_body.statements[0].c0);
	assert(body.statements[0].l1 == fresh_body.statements[0].l1 && body.statements[0].c1 == fresh_body.statements[0].c1);

	if expected_kind == {
		case .WHILE;
			loop := body.statements[0].(*Extended.Parser_While);
			fresh_loop := fresh_body.statements[0].(*Extended.Parser_While);
			assert(loop.condition.(*Extended.Parser_Ident).resolved_declaration == statements[1].(*Extended.Parser_Declaration));
			assert(fresh_loop.condition.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[1].(*Extended.Parser_Declaration));
			assert(loop.block.statements[0].kind == .LOOP_CONTROL && fresh_loop.block.statements[0].kind == .LOOP_CONTROL);
			assert(loop.block.statements[0].first_token == fresh_loop.block.statements[0].first_token);

		case .IF;
			if starts_with(statement, "if value ==") {
				conditional := body.statements[0].(*Extended.Parser_If);
				fresh_conditional := fresh_body.statements[0].(*Extended.Parser_If);
				assert(conditional.then_block.statements[0].kind == .CASE && fresh_conditional.then_block.statements[0].kind == .CASE);
				assert(conditional.then_block.statements[0].first_token == fresh_conditional.then_block.statements[0].first_token);
				assert(conditional.then_block.statements[0].(*Extended.Parser_Case).then_block.statements[0].kind == .RETURN);
			}

		case .ASM;
			assembly := body.statements[0].(*Extended.Parser_Asm);
			fresh_assembly := fresh_body.statements[0].(*Extended.Parser_Asm);
			assert(assembly.statements.count == fresh_assembly.statements.count && assembly.statements.count == 1);
	}

	assert(body.statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == statements[1].(*Extended.Parser_Declaration));
	assert(fresh_body.statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[1].(*Extended.Parser_Declaration));
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	assert_eligible_edit_matches_fresh(*updated, *fresh);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(body.statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).name == "value");
	assert(Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);
}

check_excluded_expression_node :: (expression: string, expected_kind: type_of(Extended.Parser_Node.kind)) {
	old_source := copy_string(tprint(			  "Target :: s64; value :: 1; result := %; keep := result;", expression));
	new_source := copy_string(tprint("added :: 0;\nTarget :: s64; value :: 1; result := %; keep := result;", expression));
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE && fresh.status == .COMPLETE, "%", expression);
	old_expression := old.root.(*Extended.Parser_Block).statements[2].(*Extended.Parser_Declaration).expression;
	assert(old_expression.kind == expected_kind && !Extended.reusable_expression(old_expression), "%", expression);
	statements := updated.root.(*Extended.Parser_Block).statements;
	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, cursor=statements[3].first_token.(s64)};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	assert(Extended.reuse_simple_declaration(*probe) == null);
	probe.cursor = statements[4].first_token.(s64);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root != null);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);
	expression_node := statements[3].(*Extended.Parser_Declaration).expression;
	fresh_expression := fresh_statements[3].(*Extended.Parser_Declaration).expression;
	assert(expression_node.kind == expected_kind && expression_node.kind == fresh_expression.kind && expression_node.node_flags == fresh_expression.node_flags);
	assert(expression_node.first_token == fresh_expression.first_token && expression_node.one_past_last_token == fresh_expression.one_past_last_token);
	assert(expression_node.l0 == fresh_expression.l0 && expression_node.c0 == fresh_expression.c0 && expression_node.l1 == fresh_expression.l1 && expression_node.c1 == fresh_expression.c1);
	if expression == "value + ---" {
		assert(old_expression.(*Extended.Parser_Binary_Operator).right.(*Extended.Parser_Literal).value_type == .UNINITIALIZED);
		assert(expression_node.(*Extended.Parser_Binary_Operator).right.(*Extended.Parser_Literal).value_type == .UNINITIALIZED);
		assert(fresh_expression.(*Extended.Parser_Binary_Operator).right.(*Extended.Parser_Literal).value_type == .UNINITIALIZED);
	} else if expression == "arg => arg" {
		old_header := old_expression.(*Extended.Parser_Procedure_Header);
		header := expression_node.(*Extended.Parser_Procedure_Header);
		fresh_header := fresh_expression.(*Extended.Parser_Procedure_Header);
		assert(header != old_header && header.body_or_null != old_header.body_or_null);
		assert(header.arguments[0].name == "arg" && header.body_or_null.block.statements[0].kind == .RETURN);
		value := header.body_or_null.block.statements[0].(*Extended.Parser_Return).arguments_unsorted[0].expression.(*Extended.Parser_Ident);
		fresh_value := fresh_header.body_or_null.block.statements[0].(*Extended.Parser_Return).arguments_unsorted[0].expression.(*Extended.Parser_Ident);
		assert(value.resolved_declaration == header.arguments[0]);
		assert(fresh_value.resolved_declaration == fresh_header.arguments[0]);
	}

	if expected_kind == {
		case .EXPRESSION_QUERY;
			query := expression_node.(*Extended.Parser_Expression_Query);
			fresh_query := fresh_expression.(*Extended.Parser_Expression_Query);
			assert(query.query_kind == fresh_query.query_kind && query.expression_to_query.kind == fresh_query.expression_to_query.kind);
			assert(query.expression_to_query.first_token == fresh_query.expression_to_query.first_token && query.expression_to_query.one_past_last_token == fresh_query.expression_to_query.one_past_last_token);

		case .TYPE_QUERY;
			query := expression_node.(*Extended.Parser_Type_Query);
			fresh_query := fresh_expression.(*Extended.Parser_Type_Query);
			assert(query.query_kind == fresh_query.query_kind && query.type_to_query != old_expression.(*Extended.Parser_Type_Query).type_to_query);
			assert(query.type_to_query.first_token == fresh_query.type_to_query.first_token && query.type_to_query.one_past_last_token == fresh_query.type_to_query.one_past_last_token);

		case .DIRECTIVE_RUN;
			run := expression_node.(*Extended.Parser_Directive_Run);
			fresh_run := fresh_expression.(*Extended.Parser_Directive_Run);
			assert(run.flags == fresh_run.flags && run.expression.kind == fresh_run.expression.kind);
			if starts_with(expression, "#assert") {
				assert((run.flags & .ASSERTION) != 0 && run.assertion_string == "message" && run.assertion_string == fresh_run.assertion_string);
			}

			if run.expression.kind == .IDENT {
				assert(run.expression.(*Extended.Parser_Ident).resolved_declaration == statements[2].(*Extended.Parser_Declaration));
				assert(fresh_run.expression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[2].(*Extended.Parser_Declaration));
			}

		case .DIRECTIVE_CODE;
			code := expression_node.(*Extended.Parser_Directive_Code);
			fresh_code := fresh_expression.(*Extended.Parser_Directive_Code);
			assert(code.code_flags == fresh_code.code_flags && (code.expression == null) == (fresh_code.expression == null));
			if code.expression {
				assert(code.expression.kind == fresh_code.expression.kind && code.expression.first_token == fresh_code.expression.first_token);
			}

		case .DIRECTIVE_INSERT;
			insert := expression_node.(*Extended.Parser_Directive_Insert);
			fresh_insert := fresh_expression.(*Extended.Parser_Directive_Insert);
			assert(insert.expression.kind == fresh_insert.expression.kind && (insert.scope_redirection == null) == (fresh_insert.scope_redirection == null));
			assert((insert.break_replacement == null) == (fresh_insert.break_replacement == null));
			if insert.scope_redirection {
				assert(insert.scope_redirection.(*Extended.Parser_Ident).resolved_declaration == statements[2].(*Extended.Parser_Declaration));
				assert(fresh_insert.scope_redirection.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[2].(*Extended.Parser_Declaration));
			}

		case .IF;
			conditional := expression_node.(*Extended.Parser_If);
			fresh_conditional := fresh_expression.(*Extended.Parser_If);
			assert(conditional.if_flags == fresh_conditional.if_flags && (conditional.if_flags & .IS_IFX) != 0);
			assert(conditional.condition.(*Extended.Parser_Ident).resolved_declaration == statements[2].(*Extended.Parser_Declaration));
			assert(fresh_conditional.condition.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[2].(*Extended.Parser_Declaration));
			assert(conditional.then_block.first_token == fresh_conditional.then_block.first_token && conditional.else_block.first_token == fresh_conditional.else_block.first_token);

		case .DIRECTIVE_LOAD;
			assert(expression_node.(*Extended.Parser_Directive_Load).short_name == fresh_expression.(*Extended.Parser_Directive_Load).short_name);

		case .DIRECTIVE_IMPORT;
			import_node := expression_node.(*Extended.Parser_Directive_Import);
			fresh_import := fresh_expression.(*Extended.Parser_Directive_Import);
			assert(import_node.name == fresh_import.name && import_node.flags == fresh_import.flags && import_node.import_type == fresh_import.import_type);

		case .DIRECTIVE_LIBRARY;
			library := expression_node.(*Extended.Parser_Directive_Library);
			fresh_library := fresh_expression.(*Extended.Parser_Directive_Library);
			assert(library.name == fresh_library.name && library.library_flags == fresh_library.library_flags);

		case .DIRECTIVE_POKE_NAME;
			assert(expression_node.(*Extended.Parser_Directive_Poke_Name).name == fresh_expression.(*Extended.Parser_Directive_Poke_Name).name);

		case .STRUCT;
			structure := expression_node.(*Extended.Parser_Struct);
			fresh_structure := fresh_expression.(*Extended.Parser_Struct);
			assert(structure.block.statements[0].(*Extended.Parser_Declaration).name == fresh_structure.block.statements[0].(*Extended.Parser_Declaration).name);
			assert(structure.block.statements[0].first_token == fresh_structure.block.statements[0].first_token);

		case .ENUM;
			enumeration := expression_node.(*Extended.Parser_Enum);
			fresh_enumeration := fresh_expression.(*Extended.Parser_Enum);
			assert(enumeration.block.statements[0].(*Extended.Parser_Declaration).name == fresh_enumeration.block.statements[0].(*Extended.Parser_Declaration).name);
			assert(enumeration.block.statements[0].first_token == fresh_enumeration.block.statements[0].first_token);
	}

	assert(statements[4].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == statements[3].(*Extended.Parser_Declaration));
	assert(fresh_statements[4].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[3].(*Extended.Parser_Declaration));
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	for updated.tokens {
		other := fresh.tokens[it_index];
		assert(it.original_text == other.original_text && it.preceding_trivia == other.preceding_trivia && it.trailing_trivia == other.trailing_trivia);
	}

	if expected_kind == {
		case .DIRECTIVE_IMPORT;
			assert(expression_node.(*Extended.Parser_Directive_Import).name == "../module.jai");

		case .DIRECTIVE_LOAD;
			assert(expression_node.(*Extended.Parser_Directive_Load).short_name == "local.jai");

		case .DIRECTIVE_POKE_NAME;
			assert(expression_node.(*Extended.Parser_Directive_Poke_Name).name == "renamed");

		case .DIRECTIVE_RUN;
			if starts_with(expression, "#assert") {
				assert(expression_node.(*Extended.Parser_Directive_Run).assertion_string == "message");
			}

		case .STRUCT;
			assert(expression_node.(*Extended.Parser_Struct).block.statements[0].(*Extended.Parser_Declaration).name == "field");

		case .ENUM;
			assert(expression_node.(*Extended.Parser_Enum).block.statements[0].(*Extended.Parser_Declaration).name == "A");
	}

	assert(Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);
}

test_lowered_directive_ast_reuse :: () {
	expressions: []string = .["#char \"A\"", "#procedure_of_call Target(value)"];
	for expressions {
		old_source := copy_string(tprint(			  "Target :: 1; value :: 2; result := %;", it));
		new_source := copy_string(tprint("added :: 0;\nTarget :: 1; value :: 2; result := %;", it));
		old := Extended.parse_file(old_source);
		updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
		fresh := Extended.parse_file(new_source);
		assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE && fresh.status == .COMPLETE);
		old_expression := old.root.(*Extended.Parser_Block).statements[2].(*Extended.Parser_Declaration).expression;
		assert(Extended.reusable_expression(old_expression));
		statements := updated.root.(*Extended.Parser_Block).statements;
		fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
		probe_tokens := Extended.materialise_tokens(new_source);
		probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, cursor=statements[3].first_token.(s64)};
		set_allocators(*probe_tokens.node_pool, context.default_allocator);
		probe.current_scope = Extended.push_lexical_scope(*probe);
		probe_tokens.root = Extended.reuse_simple_declaration(*probe);
		assert(probe_tokens.root != null);
		Extended.release_parser_tree(*probe_tokens);
		Extended.release_parser_names(*probe_tokens);
		expression := statements[3].(*Extended.Parser_Declaration).expression;
		fresh_expression := fresh_statements[3].(*Extended.Parser_Declaration).expression;
		assert(expression.kind == fresh_expression.kind && expression.first_token == fresh_expression.first_token && expression.one_past_last_token == fresh_expression.one_past_last_token);
		assert(expression.l0 == fresh_expression.l0 && expression.c0 == fresh_expression.c0 && expression.l1 == fresh_expression.l1 && expression.c1 == fresh_expression.c1);
		if expression.kind == .LITERAL {
			literal := expression.(*Extended.Parser_Literal);
			fresh_literal := fresh_expression.(*Extended.Parser_Literal);
			assert(literal.value_type == .NUMBER && literal._u64 == #char "A" && literal._u64 == fresh_literal._u64);
			assert(literal.value_flags == fresh_literal.value_flags);
		} else {
			call := expression.(*Extended.Parser_Procedure_Call);
			fresh_call := fresh_expression.(*Extended.Parser_Procedure_Call);
			assert((call.flags & .RETURNS_PROCEDURE_POINTER_ONLY) != 0 && call.flags == fresh_call.flags);
			assert(call.arguments_unsorted.data != old_expression.(*Extended.Parser_Procedure_Call).arguments_unsorted.data);
			assert(call.procedure_expression.(*Extended.Parser_Ident).resolved_declaration == statements[1].(*Extended.Parser_Declaration));
			assert(fresh_call.procedure_expression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[1].(*Extended.Parser_Declaration));
			assert(call.arguments_unsorted[0].expression.(*Extended.Parser_Ident).resolved_declaration == statements[2].(*Extended.Parser_Declaration));
			assert(fresh_call.arguments_unsorted[0].expression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[2].(*Extended.Parser_Declaration));
		}

		assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
		Extended.release_parser_tree(*old);
		Extended.release_parser_names(*old);
		free(old_source);
		assert(Extended.reconstruct_source(*updated) == new_source);
		Extended.release_parser_tree(*updated);
		Extended.release_parser_names(*updated);
		Extended.release_parser_tree(*fresh);
		Extended.release_parser_names(*fresh);
		free(new_source);
	}
}

test_excluded_directive_payload_edit :: () {
	PREFIX :: "Target :: s64; value :: 1; result := #code ";
	old_source := copy_string(tprint("%value; keep := result;", PREFIX));
	new_source := copy_string(tprint("%Target; keep := result;", PREFIX));
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, PREFIX.count, PREFIX.count + "value".count, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE && fresh.status == .COMPLETE);
	statements := updated.root.(*Extended.Parser_Block).statements;
	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, edit_start=PREFIX.count, edit_end=PREFIX.count + "value".count, cursor=statements[2].first_token.(s64)};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	assert(Extended.reuse_simple_declaration(*probe) == null);
	probe.cursor = statements[3].first_token.(s64);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root != null);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);
	code := statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Directive_Code);
	fresh_code := fresh_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Directive_Code);
	assert(code.code_flags == fresh_code.code_flags && code.first_token == fresh_code.first_token && code.one_past_last_token == fresh_code.one_past_last_token);
	assert(code.l0 == fresh_code.l0 && code.c0 == fresh_code.c0 && code.l1 == fresh_code.l1 && code.c1 == fresh_code.c1);
	assert(code.expression.first_token == fresh_code.expression.first_token && code.expression.one_past_last_token == fresh_code.expression.one_past_last_token);
	assert(code.expression.(*Extended.Parser_Ident).resolved_declaration == statements[0].(*Extended.Parser_Declaration));
	assert(fresh_code.expression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[0].(*Extended.Parser_Declaration));
	assert(statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == statements[2].(*Extended.Parser_Declaration));
	assert(fresh_statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[2].(*Extended.Parser_Declaration));
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(code.expression.(*Extended.Parser_Ident).name == "Target" && Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);
}

test_expression_query_ast_reuse :: () {
	old_source := copy_string(			   "value :: 1; result := type_of(value);");
	new_source := copy_string("added :: 2;\nvalue :: 1; result := type_of(value);");
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE && fresh.status == .COMPLETE);
	statements := updated.root.(*Extended.Parser_Block).statements;
	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, cursor=statements[2].first_token.(s64)};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root && probe_tokens.root.(*Extended.Parser_Declaration).expression.kind == .EXPRESSION_QUERY);
	assert(probe.current_scope.references.count == 1);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);
	query := statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Expression_Query);
	fresh_query := fresh_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Expression_Query);
	assert(query.query_kind == .TYPE_OF && query.query_kind == fresh_query.query_kind);
	assert(query.first_token == fresh_query.first_token && query.one_past_last_token == fresh_query.one_past_last_token);
	assert(query.l0 == fresh_query.l0 && query.c0 == fresh_query.c0 && query.l1 == fresh_query.l1 && query.c1 == fresh_query.c1);
	name := query.expression_to_query.(*Extended.Parser_Ident);
	assert(name.first_token == fresh_query.expression_to_query.first_token && name.one_past_last_token == fresh_query.expression_to_query.one_past_last_token);
	assert(name.resolved_declaration == statements[1].(*Extended.Parser_Declaration));
	assert(fresh_query.expression_to_query.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[1].(*Extended.Parser_Declaration));
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	assert_eligible_edit_matches_fresh(*updated, *fresh);

	other_source := copy_string("value :: 1; result := is_constant(value);");
	other_old := Extended.parse_file(other_source);
	other_new_source := copy_string("added :: 2;\nvalue :: 1; result := is_constant(value);");
	other_updated, other_ok := Extended.parse_file_edit(*other_old, 0, 0, other_new_source);
	other_fresh := Extended.parse_file(other_new_source);
	assert(other_ok && other_old.status == .COMPLETE && other_updated.status == .COMPLETE && other_fresh.status == .COMPLETE);
	other_query := other_old.root.(*Extended.Parser_Block).statements[1].(*Extended.Parser_Declaration).expression;
	assert(other_query.kind == .EXPRESSION_QUERY && Extended.reusable_expression(other_query));
	other_statements := other_updated.root.(*Extended.Parser_Block).statements;
	other_fresh_statements := other_fresh.root.(*Extended.Parser_Block).statements;
	other_probe_tokens := Extended.materialise_tokens(other_new_source);
	other_probe := Extended.Parser.{parsed=*other_probe_tokens, edit_source=*other_old, cursor=other_statements[2].first_token.(s64)};
	set_allocators(*other_probe_tokens.node_pool, context.default_allocator);
	other_probe.current_scope = Extended.push_lexical_scope(*other_probe);
	other_probe_tokens.root = Extended.reuse_simple_declaration(*other_probe);
	assert(other_probe_tokens.root && other_probe_tokens.root.(*Extended.Parser_Declaration).expression.kind == .EXPRESSION_QUERY);
	assert(other_probe.current_scope.references.count == 1);
	Extended.release_parser_tree(*other_probe_tokens);
	Extended.release_parser_names(*other_probe_tokens);
	other_reused_query := other_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Expression_Query);
	other_fresh_query := other_fresh_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Expression_Query);
	assert(other_reused_query.query_kind == .IS_CONSTANT && other_reused_query.query_kind == other_fresh_query.query_kind);
	assert(other_reused_query.first_token == other_fresh_query.first_token && other_reused_query.one_past_last_token == other_fresh_query.one_past_last_token);
	assert(other_reused_query.l0 == other_fresh_query.l0 && other_reused_query.c0 == other_fresh_query.c0);
	assert(other_reused_query.l1 == other_fresh_query.l1 && other_reused_query.c1 == other_fresh_query.c1);
	other_name := other_reused_query.expression_to_query.(*Extended.Parser_Ident);
	assert(other_name.first_token == other_fresh_query.expression_to_query.first_token && other_name.one_past_last_token == other_fresh_query.expression_to_query.one_past_last_token);
	assert(other_name.resolved_declaration == other_statements[1].(*Extended.Parser_Declaration));
	assert(other_fresh_query.expression_to_query.(*Extended.Parser_Ident).resolved_declaration == other_fresh_statements[1].(*Extended.Parser_Declaration));
	assert(other_updated.diagnostics.count == other_fresh.diagnostics.count && other_updated.restart_points.count == other_fresh.restart_points.count);
	assert(other_reused_query.node_flags == other_fresh_query.node_flags);
	assert_eligible_edit_matches_fresh(*other_updated, *other_fresh);
	Extended.release_parser_tree(*other_old);
	Extended.release_parser_names(*other_old);
	free(other_source);
	assert(other_name.name == "value" && Extended.reconstruct_source(*other_updated) == other_new_source);
	Extended.release_parser_tree(*other_updated);
	Extended.release_parser_names(*other_updated);
	Extended.release_parser_tree(*other_fresh);
	Extended.release_parser_names(*other_fresh);
	free(other_new_source);

	code_old_source := copy_string(				"value :: 1; result := code_of(value);");
	code_new_source := copy_string("added :: 2;\nvalue :: 1; result := code_of(value);");
	code_old := Extended.parse_file(code_old_source);
	code_updated, code_ok := Extended.parse_file_edit(*code_old, 0, 0, code_new_source);
	code_fresh := Extended.parse_file(code_new_source);
	assert(code_ok && code_old.status == .COMPLETE && code_updated.status == .COMPLETE && code_fresh.status == .COMPLETE);
	code_statements := code_updated.root.(*Extended.Parser_Block).statements;
	code_fresh_statements := code_fresh.root.(*Extended.Parser_Block).statements;
	code_probe_tokens := Extended.materialise_tokens(code_new_source);
	code_probe := Extended.Parser.{parsed=*code_probe_tokens, edit_source=*code_old, cursor=code_statements[2].first_token.(s64)};
	set_allocators(*code_probe_tokens.node_pool, context.default_allocator);
	code_probe.current_scope = Extended.push_lexical_scope(*code_probe);
	code_probe_tokens.root = Extended.reuse_simple_declaration(*code_probe);
	assert(code_probe_tokens.root && code_probe_tokens.root.(*Extended.Parser_Declaration).expression.kind == .EXPRESSION_QUERY);
	assert(code_probe.current_scope.references.count == 1);
	Extended.release_parser_tree(*code_probe_tokens);
	Extended.release_parser_names(*code_probe_tokens);
	code_query := code_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Expression_Query);
	code_fresh_query := code_fresh_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Expression_Query);
	assert(code_query.query_kind == .CODE_OF && code_query.query_kind == code_fresh_query.query_kind);
	assert(code_query.first_token == code_fresh_query.first_token && code_query.one_past_last_token == code_fresh_query.one_past_last_token);
	assert(code_query.l0 == code_fresh_query.l0 && code_query.c0 == code_fresh_query.c0 && code_query.l1 == code_fresh_query.l1 && code_query.c1 == code_fresh_query.c1);
	code_name := code_query.expression_to_query.(*Extended.Parser_Ident);
	assert(code_name.first_token == code_fresh_query.expression_to_query.first_token && code_name.one_past_last_token == code_fresh_query.expression_to_query.one_past_last_token);
	assert(code_name.resolved_declaration == code_statements[1].(*Extended.Parser_Declaration));
	assert(code_fresh_query.expression_to_query.(*Extended.Parser_Ident).resolved_declaration == code_fresh_statements[1].(*Extended.Parser_Declaration));
	assert(code_updated.diagnostics.count == code_fresh.diagnostics.count && code_updated.restart_points.count == code_fresh.restart_points.count);
	assert(code_query.node_flags == code_fresh_query.node_flags);
	assert_eligible_edit_matches_fresh(*code_updated, *code_fresh);
	Extended.release_parser_tree(*code_old);
	Extended.release_parser_names(*code_old);
	free(code_old_source);
	assert(code_name.name == "value" && Extended.reconstruct_source(*code_updated) == code_new_source);
	Extended.release_parser_tree(*code_updated);
	Extended.release_parser_names(*code_updated);
	Extended.release_parser_tree(*code_fresh);
	Extended.release_parser_names(*code_fresh);
	free(code_new_source);

	changed_source := copy_string("value :: 1; result := is_constant(value);");
	query_start := "value :: 1; result := ".count;
	changed, changed_ok := Extended.parse_file_edit(*old, query_start, query_start + "type_of".count, changed_source);
	changed_fresh := Extended.parse_file(changed_source);
	assert(changed_ok && changed.status == .COMPLETE && changed_fresh.status == .COMPLETE);
	changed_tokens := Extended.materialise_tokens(changed_source);
	changed_probe := Extended.Parser.{parsed=*changed_tokens, edit_source=*old, edit_start=query_start, edit_end=query_start + "type_of".count, cursor=changed.root.(*Extended.Parser_Block).statements[1].first_token.(s64)};
	set_allocators(*changed_tokens.node_pool, context.default_allocator);
	changed_probe.current_scope = Extended.push_lexical_scope(*changed_probe);
	assert(Extended.reuse_simple_declaration(*changed_probe) == null);
	Extended.release_parser_tree(*changed_tokens);
	Extended.release_parser_names(*changed_tokens);
	changed_statements := changed.root.(*Extended.Parser_Block).statements;
	changed_fresh_statements := changed_fresh.root.(*Extended.Parser_Block).statements;
	changed_query := changed_statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Expression_Query);
	changed_fresh_query := changed_fresh_statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Expression_Query);
	assert(changed_query.query_kind == .IS_CONSTANT && changed_query.query_kind == changed_fresh_query.query_kind);
	assert(changed_query.first_token == changed_fresh_query.first_token && changed_query.one_past_last_token == changed_fresh_query.one_past_last_token);
	assert(changed_query.expression_to_query.(*Extended.Parser_Ident).resolved_declaration == changed_statements[0].(*Extended.Parser_Declaration));
	assert(changed.diagnostics.count == changed_fresh.diagnostics.count && changed.restart_points.count == changed_fresh.restart_points.count);
	assert(Extended.reconstruct_source(*changed) == changed_source);
	Extended.release_parser_tree(*changed);
	Extended.release_parser_names(*changed);
	Extended.release_parser_tree(*changed_fresh);
	Extended.release_parser_names(*changed_fresh);
	free(changed_source);

	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(name.name == "value" && Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);
}

test_type_query_ast_reuse :: () {
	old_source := copy_string(			   "Target :: s64; result := size_of(Target);");
	new_source := copy_string("added :: 2;\nTarget :: s64; result := size_of(Target);");
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE && fresh.status == .COMPLETE);
	statements := updated.root.(*Extended.Parser_Block).statements;
	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, cursor=statements[2].first_token.(s64)};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root && probe_tokens.root.(*Extended.Parser_Declaration).expression.kind == .TYPE_QUERY);
	assert(probe.current_scope.references.count == 1);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);
	query := statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Type_Query);
	fresh_query := fresh_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Type_Query);
	assert(query.node_flags == fresh_query.node_flags && query.type_to_query.node_flags == fresh_query.type_to_query.node_flags);
	assert(query.query_kind == .SIZE_OF && query.query_kind == fresh_query.query_kind);
	assert(query.first_token == fresh_query.first_token && query.one_past_last_token == fresh_query.one_past_last_token);
	assert(query.l0 == fresh_query.l0 && query.c0 == fresh_query.c0 && query.l1 == fresh_query.l1 && query.c1 == fresh_query.c1);
	assert(query.type_to_query.first_token == fresh_query.type_to_query.first_token && query.type_to_query.one_past_last_token == fresh_query.type_to_query.one_past_last_token);
	assert(query.type_to_query.l0 == fresh_query.type_to_query.l0 && query.type_to_query.c0 == fresh_query.type_to_query.c0);
	assert(query.type_to_query.l1 == fresh_query.type_to_query.l1 && query.type_to_query.c1 == fresh_query.type_to_query.c1);
	target := query.type_to_query.type_valued_expression.(*Extended.Parser_Ident);
	fresh_target := fresh_query.type_to_query.type_valued_expression.(*Extended.Parser_Ident);
	assert(target.first_token == fresh_target.first_token && target.one_past_last_token == fresh_target.one_past_last_token);
	assert(target.resolved_declaration == statements[1].(*Extended.Parser_Declaration));
	assert(fresh_target.resolved_declaration == fresh_statements[1].(*Extended.Parser_Declaration));
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	assert_eligible_edit_matches_fresh(*updated, *fresh);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(target.name == "Target" && Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);

	info_old_source := copy_string(				"Target :: s64; result := type_info(Target);");
	info_new_source := copy_string("added :: 2;\nTarget :: s64; result := type_info(Target);");
	info_old := Extended.parse_file(info_old_source);
	info_updated, info_ok := Extended.parse_file_edit(*info_old, 0, 0, info_new_source);
	info_fresh := Extended.parse_file(info_new_source);
	assert(info_ok && info_old.status == .COMPLETE && info_updated.status == .COMPLETE && info_fresh.status == .COMPLETE);
	info_statements := info_updated.root.(*Extended.Parser_Block).statements;
	info_fresh_statements := info_fresh.root.(*Extended.Parser_Block).statements;
	info_probe_tokens := Extended.materialise_tokens(info_new_source);
	info_probe := Extended.Parser.{parsed=*info_probe_tokens, edit_source=*info_old, cursor=info_statements[2].first_token.(s64)};
	set_allocators(*info_probe_tokens.node_pool, context.default_allocator);
	info_probe.current_scope = Extended.push_lexical_scope(*info_probe);
	info_probe_tokens.root = Extended.reuse_simple_declaration(*info_probe);
	assert(info_probe_tokens.root && info_probe_tokens.root.(*Extended.Parser_Declaration).expression.kind == .TYPE_QUERY);
	assert(info_probe.current_scope.references.count == 1);
	Extended.release_parser_tree(*info_probe_tokens);
	Extended.release_parser_names(*info_probe_tokens);
	info_query := info_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Type_Query);
	info_fresh_query := info_fresh_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Type_Query);
	assert(info_query.query_kind == .TYPE_INFO && info_query.query_kind == info_fresh_query.query_kind);
	assert(info_query.first_token == info_fresh_query.first_token && info_query.one_past_last_token == info_fresh_query.one_past_last_token);
	assert(info_query.l0 == info_fresh_query.l0 && info_query.c0 == info_fresh_query.c0);
	assert(info_query.l1 == info_fresh_query.l1 && info_query.c1 == info_fresh_query.c1);
	assert(info_query.type_to_query.first_token == info_fresh_query.type_to_query.first_token && info_query.type_to_query.one_past_last_token == info_fresh_query.type_to_query.one_past_last_token);
	assert(info_query.type_to_query.l0 == info_fresh_query.type_to_query.l0 && info_query.type_to_query.c0 == info_fresh_query.type_to_query.c0);
	assert(info_query.type_to_query.l1 == info_fresh_query.type_to_query.l1 && info_query.type_to_query.c1 == info_fresh_query.type_to_query.c1);
	info_target := info_query.type_to_query.type_valued_expression.(*Extended.Parser_Ident);
	assert(info_target.resolved_declaration == info_statements[1].(*Extended.Parser_Declaration));
	assert(info_fresh_query.type_to_query.type_valued_expression.(*Extended.Parser_Ident).resolved_declaration == info_fresh_statements[1].(*Extended.Parser_Declaration));
	assert(info_updated.diagnostics.count == info_fresh.diagnostics.count && info_updated.restart_points.count == info_fresh.restart_points.count);
	assert(info_query.node_flags == info_fresh_query.node_flags && info_query.type_to_query.node_flags == info_fresh_query.type_to_query.node_flags);
	assert_eligible_edit_matches_fresh(*info_updated, *info_fresh);
	Extended.release_parser_tree(*info_old);
	Extended.release_parser_names(*info_old);
	free(info_old_source);
	assert(info_target.name == "Target" && Extended.reconstruct_source(*info_updated) == info_new_source);
	Extended.release_parser_tree(*info_updated);
	Extended.release_parser_names(*info_updated);
	Extended.release_parser_tree(*info_fresh);
	Extended.release_parser_names(*info_fresh);
	free(info_new_source);

	initializer_old_source := copy_string(			   "Target :: struct { value: s64 = 42; }; result := initializer_of(Target);");
	initializer_new_source := copy_string("added :: 2;\nTarget :: struct { value: s64 = 42; }; result := initializer_of(Target);");
	initializer_old := Extended.parse_file(initializer_old_source);
	initializer_updated, initializer_ok := Extended.parse_file_edit(*initializer_old, 0, 0, initializer_new_source);
	initializer_fresh := Extended.parse_file(initializer_new_source);
	assert(initializer_ok && initializer_old.status == .COMPLETE && initializer_updated.status == .COMPLETE && initializer_fresh.status == .COMPLETE);
	initializer_statements := initializer_updated.root.(*Extended.Parser_Block).statements;
	initializer_fresh_statements := initializer_fresh.root.(*Extended.Parser_Block).statements;
	initializer_probe_tokens := Extended.materialise_tokens(initializer_new_source);
	initializer_probe := Extended.Parser.{parsed=*initializer_probe_tokens, edit_source=*initializer_old, cursor=initializer_statements[2].first_token.(s64)};
	set_allocators(*initializer_probe_tokens.node_pool, context.default_allocator);
	initializer_probe.current_scope = Extended.push_lexical_scope(*initializer_probe);
	initializer_probe_tokens.root = Extended.reuse_simple_declaration(*initializer_probe);
	assert(initializer_probe_tokens.root && initializer_probe_tokens.root.(*Extended.Parser_Declaration).expression.kind == .TYPE_QUERY);
	assert(initializer_probe.current_scope.references.count == 1);
	Extended.release_parser_tree(*initializer_probe_tokens);
	Extended.release_parser_names(*initializer_probe_tokens);
	initializer_query := initializer_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Type_Query);
	initializer_fresh_query := initializer_fresh_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Type_Query);
	assert(initializer_query.query_kind == .INITIALIZER_OF && initializer_query.query_kind == initializer_fresh_query.query_kind);
	assert(initializer_query.first_token == initializer_fresh_query.first_token && initializer_query.one_past_last_token == initializer_fresh_query.one_past_last_token);
	assert(initializer_query.l0 == initializer_fresh_query.l0 && initializer_query.c0 == initializer_fresh_query.c0);
	assert(initializer_query.l1 == initializer_fresh_query.l1 && initializer_query.c1 == initializer_fresh_query.c1);
	assert(
		initializer_query.type_to_query.first_token == initializer_fresh_query.type_to_query.first_token
		&& initializer_query.type_to_query.one_past_last_token == initializer_fresh_query.type_to_query.one_past_last_token
	);
	assert(initializer_query.type_to_query.l0 == initializer_fresh_query.type_to_query.l0 && initializer_query.type_to_query.c0 == initializer_fresh_query.type_to_query.c0);
	assert(initializer_query.type_to_query.l1 == initializer_fresh_query.type_to_query.l1 && initializer_query.type_to_query.c1 == initializer_fresh_query.type_to_query.c1);
	initializer_target := initializer_query.type_to_query.type_valued_expression.(*Extended.Parser_Ident);
	assert(initializer_target.resolved_declaration == initializer_statements[1].(*Extended.Parser_Declaration));
	assert(initializer_fresh_query.type_to_query.type_valued_expression.(*Extended.Parser_Ident).resolved_declaration == initializer_fresh_statements[1].(*Extended.Parser_Declaration));
	assert(initializer_updated.diagnostics.count == initializer_fresh.diagnostics.count && initializer_updated.restart_points.count == initializer_fresh.restart_points.count);
	assert(initializer_query.node_flags == initializer_fresh_query.node_flags && initializer_query.type_to_query.node_flags == initializer_fresh_query.type_to_query.node_flags);
	assert_eligible_edit_matches_fresh(*initializer_updated, *initializer_fresh);
	Extended.release_parser_tree(*initializer_old);
	Extended.release_parser_names(*initializer_old);
	free(initializer_old_source);
	assert(initializer_target.name == "Target" && Extended.reconstruct_source(*initializer_updated) == initializer_new_source);
	Extended.release_parser_tree(*initializer_updated);
	Extended.release_parser_names(*initializer_updated);
	Extended.release_parser_tree(*initializer_fresh);
	Extended.release_parser_names(*initializer_fresh);
	free(initializer_new_source);

	changed_source :=		copy_string("Target :: s64; result := type_info(Target);");
	changed_old_source :=	copy_string("Target :: s64; result := size_of(Target);");
	changed_old := Extended.parse_file(changed_old_source);
	query_start := "Target :: s64; result := ".count;
	changed, changed_ok := Extended.parse_file_edit(*changed_old, query_start, query_start + "size_of".count, changed_source);
	changed_fresh := Extended.parse_file(changed_source);
	assert(changed_ok && changed.status == .COMPLETE && changed_fresh.status == .COMPLETE);
	changed_tokens := Extended.materialise_tokens(changed_source);
	changed_probe := Extended.Parser.{
		parsed=*changed_tokens,
		edit_source=*changed_old,
		edit_start=query_start,
		edit_end=query_start + "size_of".count,
		cursor=changed.root.(*Extended.Parser_Block).statements[1].first_token.(s64),
	};
	set_allocators(*changed_tokens.node_pool, context.default_allocator);
	changed_probe.current_scope = Extended.push_lexical_scope(*changed_probe);
	assert(Extended.reuse_simple_declaration(*changed_probe) == null);
	Extended.release_parser_tree(*changed_tokens);
	Extended.release_parser_names(*changed_tokens);
	changed_query := changed.root.(*Extended.Parser_Block).statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Type_Query);
	changed_fresh_query := changed_fresh.root.(*Extended.Parser_Block).statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Type_Query);
	assert(changed_query.query_kind == .TYPE_INFO && changed_query.query_kind == changed_fresh_query.query_kind);
	assert(changed_query.type_to_query.type_valued_expression.(*Extended.Parser_Ident).resolved_declaration == changed.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Declaration));
	assert(changed.diagnostics.count == changed_fresh.diagnostics.count && changed.restart_points.count == changed_fresh.restart_points.count);
	assert(Extended.reconstruct_source(*changed) == changed_source);
	Extended.release_parser_tree(*changed_old);
	Extended.release_parser_names(*changed_old);
	Extended.release_parser_tree(*changed);
	Extended.release_parser_names(*changed);
	Extended.release_parser_tree(*changed_fresh);
	Extended.release_parser_names(*changed_fresh);
	free(changed_old_source);
	free(changed_source);
}

test_positive_unary_ast_reuse :: () {
	old_source := copy_string(			   "value :: 1; result := +value;");
	new_source := copy_string("added :: 2;\nvalue :: 1; result := +value;");
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE && fresh.status == .COMPLETE);

	statements := updated.root.(*Extended.Parser_Block).statements;
	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, cursor=statements[2].first_token.(s64)};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root && probe_tokens.root.(*Extended.Parser_Declaration).expression.kind == .UNARY_OPERATOR);
	assert(probe.current_scope.references.count == 1);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);

	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	unary := statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Unary_Operator);
	fresh_unary := fresh_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Unary_Operator);
	assert(unary.node_flags == fresh_unary.node_flags);
	assert(unary.operator_type == #char "+" && unary.operator_type == fresh_unary.operator_type);
	assert(unary.first_token == fresh_unary.first_token && unary.one_past_last_token == fresh_unary.one_past_last_token);
	assert(unary.l0 == fresh_unary.l0 && unary.c0 == fresh_unary.c0 && unary.l1 == fresh_unary.l1 && unary.c1 == fresh_unary.c1);
	name := unary.subexpression.(*Extended.Parser_Ident);
	assert(name.first_token == fresh_unary.subexpression.first_token && name.one_past_last_token == fresh_unary.subexpression.one_past_last_token);
	assert(name.resolved_declaration == statements[1].(*Extended.Parser_Declaration));
	assert(fresh_unary.subexpression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[1].(*Extended.Parser_Declaration));
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	assert_eligible_edit_matches_fresh(*updated, *fresh);

	changed_source := copy_string("value :: 1; result := -value;");
	operator_start := "value :: 1; result := ".count;
	changed, changed_ok := Extended.parse_file_edit(*old, operator_start, operator_start + 1, changed_source);
	changed_fresh := Extended.parse_file(changed_source);
	assert(changed_ok && changed.status == .COMPLETE && changed_fresh.status == .COMPLETE);
	changed_tokens := Extended.materialise_tokens(changed_source);
	changed_probe := Extended.Parser.{parsed=*changed_tokens, edit_source=*old, edit_start=operator_start, edit_end=operator_start + 1, cursor=changed.root.(*Extended.Parser_Block).statements[1].first_token.(s64)};
	set_allocators(*changed_tokens.node_pool, context.default_allocator);
	changed_probe.current_scope = Extended.push_lexical_scope(*changed_probe);
	assert(Extended.reuse_simple_declaration(*changed_probe) == null);
	Extended.release_parser_tree(*changed_tokens);
	Extended.release_parser_names(*changed_tokens);
	changed_statements := changed.root.(*Extended.Parser_Block).statements;
	changed_fresh_statements := changed_fresh.root.(*Extended.Parser_Block).statements;
	changed_unary := changed_statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Unary_Operator);
	changed_fresh_unary := changed_fresh_statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Unary_Operator);
	assert(changed_unary.operator_type == #char "-" && changed_unary.operator_type == changed_fresh_unary.operator_type);
	assert(changed_unary.first_token == changed_fresh_unary.first_token && changed_unary.one_past_last_token == changed_fresh_unary.one_past_last_token);
	assert(changed_unary.subexpression.(*Extended.Parser_Ident).resolved_declaration == changed_statements[0].(*Extended.Parser_Declaration));
	assert(changed.diagnostics.count == changed_fresh.diagnostics.count && changed.restart_points.count == changed_fresh.restart_points.count);
	assert(Extended.reconstruct_source(*changed) == changed_source);
	Extended.release_parser_tree(*changed);
	Extended.release_parser_names(*changed);
	Extended.release_parser_tree(*changed_fresh);
	Extended.release_parser_names(*changed_fresh);
	free(changed_source);

	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(name.name == "value" && Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);
}

test_negative_unary_ast_reuse :: () {
	old_source := copy_string(			   "value :: 1; result := -value;");
	new_source := copy_string("added :: 2;\nvalue :: 1; result := -value;");
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE && fresh.status == .COMPLETE);

	statements := updated.root.(*Extended.Parser_Block).statements;
	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, cursor=statements[2].first_token.(s64)};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root && probe_tokens.root.(*Extended.Parser_Declaration).expression.kind == .UNARY_OPERATOR);
	assert(probe.current_scope.references.count == 1);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);

	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	unary := statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Unary_Operator);
	fresh_unary := fresh_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Unary_Operator);
	assert(unary.node_flags == fresh_unary.node_flags);
	assert(unary.operator_type == #char "-" && unary.operator_type == fresh_unary.operator_type);
	assert(unary.first_token == fresh_unary.first_token && unary.one_past_last_token == fresh_unary.one_past_last_token);
	assert(unary.subexpression.first_token == fresh_unary.subexpression.first_token && unary.subexpression.one_past_last_token == fresh_unary.subexpression.one_past_last_token);
	name := unary.subexpression.(*Extended.Parser_Ident);
	assert(name.resolved_declaration == statements[1].(*Extended.Parser_Declaration));
	assert(fresh_unary.subexpression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[1].(*Extended.Parser_Declaration));
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	assert_eligible_edit_matches_fresh(*updated, *fresh);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(name.name == "value" && Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);
}

test_prefix_dereference_ast_reuse :: () {
	old_source := copy_string(			   "value :: 1; result := *value;");
	new_source := copy_string("added :: 2;\nvalue :: 1; result := *value;");
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE && fresh.status == .COMPLETE);

	statements := updated.root.(*Extended.Parser_Block).statements;
	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, cursor=statements[2].first_token.(s64)};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root && probe_tokens.root.(*Extended.Parser_Declaration).expression.kind == .UNARY_OPERATOR);
	assert(probe.current_scope.references.count == 1);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);

	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	unary := statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Unary_Operator);
	fresh_unary := fresh_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Unary_Operator);
	assert(unary.node_flags == fresh_unary.node_flags);
	assert(unary.operator_type == #char "*" && unary.operator_type == fresh_unary.operator_type);
	assert(unary.first_token == fresh_unary.first_token && unary.one_past_last_token == fresh_unary.one_past_last_token);
	assert(unary.l0 == fresh_unary.l0 && unary.c0 == fresh_unary.c0 && unary.l1 == fresh_unary.l1 && unary.c1 == fresh_unary.c1);
	name := unary.subexpression.(*Extended.Parser_Ident);
	assert(name.first_token == fresh_unary.subexpression.first_token && name.one_past_last_token == fresh_unary.subexpression.one_past_last_token);
	assert(name.resolved_declaration == statements[1].(*Extended.Parser_Declaration));
	assert(fresh_unary.subexpression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[1].(*Extended.Parser_Declaration));
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	assert_eligible_edit_matches_fresh(*updated, *fresh);

	changed_source := copy_string("value :: 1; result := +value;");
	operator_start := "value :: 1; result := ".count;
	changed, changed_ok := Extended.parse_file_edit(*old, operator_start, operator_start + 1, changed_source);
	changed_fresh := Extended.parse_file(changed_source);
	assert(changed_ok && changed.status == .COMPLETE && changed_fresh.status == .COMPLETE);
	changed_tokens := Extended.materialise_tokens(changed_source);
	changed_probe := Extended.Parser.{parsed=*changed_tokens, edit_source=*old, edit_start=operator_start, edit_end=operator_start + 1, cursor=changed.root.(*Extended.Parser_Block).statements[1].first_token.(s64)};
	set_allocators(*changed_tokens.node_pool, context.default_allocator);
	changed_probe.current_scope = Extended.push_lexical_scope(*changed_probe);
	assert(Extended.reuse_simple_declaration(*changed_probe) == null);
	Extended.release_parser_tree(*changed_tokens);
	Extended.release_parser_names(*changed_tokens);
	changed_statements := changed.root.(*Extended.Parser_Block).statements;
	changed_fresh_statements := changed_fresh.root.(*Extended.Parser_Block).statements;
	changed_unary := changed_statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Unary_Operator);
	changed_fresh_unary := changed_fresh_statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Unary_Operator);
	assert(changed_unary.operator_type == #char "+" && changed_unary.operator_type == changed_fresh_unary.operator_type);
	assert(changed_unary.first_token == changed_fresh_unary.first_token && changed_unary.one_past_last_token == changed_fresh_unary.one_past_last_token);
	assert(changed_unary.subexpression.(*Extended.Parser_Ident).resolved_declaration == changed_statements[0].(*Extended.Parser_Declaration));
	assert(changed.diagnostics.count == changed_fresh.diagnostics.count && changed.restart_points.count == changed_fresh.restart_points.count);
	assert(Extended.reconstruct_source(*changed) == changed_source);
	Extended.release_parser_tree(*changed);
	Extended.release_parser_names(*changed);
	Extended.release_parser_tree(*changed_fresh);
	Extended.release_parser_names(*changed_fresh);
	free(changed_source);

	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(name.name == "value" && Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);
}

test_pointer_dereference_ast_reuse :: () {
	old_source := copy_string(			   "value :: 1; result := (.*)value;");
	new_source := copy_string("added :: 2;\nvalue :: 1; result := (.*)value;");
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE && fresh.status == .COMPLETE);

	statements := updated.root.(*Extended.Parser_Block).statements;
	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, cursor=statements[2].first_token.(s64)};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root && probe_tokens.root.(*Extended.Parser_Declaration).expression.kind == .UNARY_OPERATOR);
	assert(probe.current_scope.references.count == 1);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);

	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	unary := statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Unary_Operator);
	fresh_unary := fresh_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Unary_Operator);
	assert(unary.node_flags == fresh_unary.node_flags);
	assert(unary.operator_type == .POINTER_DEREFERENCE && unary.operator_type == fresh_unary.operator_type);
	assert(unary.first_token == fresh_unary.first_token && unary.one_past_last_token == fresh_unary.one_past_last_token);
	assert(unary.l0 == fresh_unary.l0 && unary.c0 == fresh_unary.c0 && unary.l1 == fresh_unary.l1 && unary.c1 == fresh_unary.c1);
	name := unary.subexpression.(*Extended.Parser_Ident);
	assert(name.first_token == fresh_unary.subexpression.first_token && name.one_past_last_token == fresh_unary.subexpression.one_past_last_token);
	assert(name.resolved_declaration == statements[1].(*Extended.Parser_Declaration));
	assert(fresh_unary.subexpression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[1].(*Extended.Parser_Declaration));
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	assert_eligible_edit_matches_fresh(*updated, *fresh);

	changed_source := copy_string("value :: 1; result := *value;");
	operator_start := "value :: 1; result := ".count;
	changed, changed_ok := Extended.parse_file_edit(*old, operator_start, operator_start + 4, changed_source);
	changed_fresh := Extended.parse_file(changed_source);
	assert(changed_ok && changed.status == .COMPLETE && changed_fresh.status == .COMPLETE);
	changed_tokens := Extended.materialise_tokens(changed_source);
	changed_probe := Extended.Parser.{parsed=*changed_tokens, edit_source=*old, edit_start=operator_start, edit_end=operator_start + 4, cursor=changed.root.(*Extended.Parser_Block).statements[1].first_token.(s64)};
	set_allocators(*changed_tokens.node_pool, context.default_allocator);
	changed_probe.current_scope = Extended.push_lexical_scope(*changed_probe);
	assert(Extended.reuse_simple_declaration(*changed_probe) == null);
	Extended.release_parser_tree(*changed_tokens);
	Extended.release_parser_names(*changed_tokens);
	changed_statements := changed.root.(*Extended.Parser_Block).statements;
	changed_fresh_statements := changed_fresh.root.(*Extended.Parser_Block).statements;
	changed_unary := changed_statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Unary_Operator);
	changed_fresh_unary := changed_fresh_statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Unary_Operator);
	assert(changed_unary.operator_type == #char "*" && changed_unary.operator_type == changed_fresh_unary.operator_type);
	assert(changed_unary.first_token == changed_fresh_unary.first_token && changed_unary.one_past_last_token == changed_fresh_unary.one_past_last_token);
	assert(changed_unary.subexpression.(*Extended.Parser_Ident).resolved_declaration == changed_statements[0].(*Extended.Parser_Declaration));
	assert(changed.diagnostics.count == changed_fresh.diagnostics.count && changed.restart_points.count == changed_fresh.restart_points.count);
	assert(Extended.reconstruct_source(*changed) == changed_source);
	Extended.release_parser_tree(*changed);
	Extended.release_parser_names(*changed);
	Extended.release_parser_tree(*changed_fresh);
	Extended.release_parser_names(*changed_fresh);
	free(changed_source);

	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(name.name == "value" && Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);
}

test_postfix_dereference_ast_reuse :: () {
	old_source := copy_string(			   "pointer :: 1; result := pointer.*;");
	new_source := copy_string("added :: 2;\npointer :: 1; result := pointer.*;");
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && updated.status == .COMPLETE && fresh.status == .COMPLETE);

	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, cursor=updated.root.(*Extended.Parser_Block).statements[2].first_token.(s64)};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root && probe_tokens.root.(*Extended.Parser_Declaration).expression.(*Extended.Parser_Unary_Operator).operator_type == .POSTFIX_DEREFERENCE);
	assert(probe.current_scope.references.count == 1);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);

	statements := updated.root.(*Extended.Parser_Block).statements;
	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	dereference := statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Unary_Operator);
	fresh_dereference := fresh_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Unary_Operator);
	assert(dereference.node_flags == fresh_dereference.node_flags);
	assert(dereference.first_token == fresh_dereference.first_token && dereference.one_past_last_token == fresh_dereference.one_past_last_token);
	assert(dereference.l0 == fresh_dereference.l0 && dereference.c0 == fresh_dereference.c0 && dereference.l1 == fresh_dereference.l1 && dereference.c1 == fresh_dereference.c1);
	reference := dereference.subexpression.(*Extended.Parser_Ident);
	fresh_reference := fresh_dereference.subexpression.(*Extended.Parser_Ident);
	assert(reference.first_token == fresh_reference.first_token && reference.one_past_last_token == fresh_reference.one_past_last_token);
	assert(reference.resolved_declaration == statements[1].(*Extended.Parser_Declaration));
	assert(fresh_reference.resolved_declaration == fresh_statements[1].(*Extended.Parser_Declaration));
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	assert_eligible_edit_matches_fresh(*updated, *fresh);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(reference.name == "pointer" && Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);
}

test_cast_ast_reuse :: () {
	old_source := copy_string(				"value :: 1; result := cast(Target) value;");
	new_source := copy_string("Target :: 2;\nvalue :: 1; result := cast(Target) value;");
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && updated.status == .COMPLETE && fresh.status == .COMPLETE);

	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, cursor=updated.root.(*Extended.Parser_Block).statements[2].first_token.(s64)};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root && probe_tokens.root.(*Extended.Parser_Declaration).expression.kind == .CAST);
	assert(probe.current_scope.references.count == 2);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);

	statements := updated.root.(*Extended.Parser_Block).statements;
	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	cast_node := statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Cast);
	fresh_cast := fresh_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Cast);
	assert(cast_node.node_flags == fresh_cast.node_flags && cast_node.cast_flags == fresh_cast.cast_flags);
	assert(cast_node.target_type.node_flags == fresh_cast.target_type.node_flags);
	assert(cast_node.first_token == fresh_cast.first_token && cast_node.one_past_last_token == fresh_cast.one_past_last_token);
	assert(cast_node.target_type.first_token == fresh_cast.target_type.first_token && cast_node.target_type.one_past_last_token == fresh_cast.target_type.one_past_last_token);
	target := cast_node.target_type.type_valued_expression.(*Extended.Parser_Ident);
	fresh_target := fresh_cast.target_type.type_valued_expression.(*Extended.Parser_Ident);
	assert(target.resolved_declaration == statements[0].(*Extended.Parser_Declaration));
	assert(fresh_target.resolved_declaration == fresh_statements[0].(*Extended.Parser_Declaration));
	assert(cast_node.expression.(*Extended.Parser_Ident).resolved_declaration == statements[1].(*Extended.Parser_Declaration));
	assert(fresh_cast.expression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[1].(*Extended.Parser_Declaration));
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	assert_eligible_edit_matches_fresh(*updated, *fresh);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(target.name == "Target" && Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);

	pointer_old_source := copy_string(				"value :: 1; result := cast(*Target) value;");
	pointer_new_source := copy_string("Target :: 2;\nvalue :: 1; result := cast(*Target) value;");
	pointer_old := Extended.parse_file(pointer_old_source);
	pointer_updated, pointer_ok := Extended.parse_file_edit(*pointer_old, 0, 0, pointer_new_source);
	pointer_fresh := Extended.parse_file(pointer_new_source);
	assert(pointer_ok && pointer_updated.status == .COMPLETE && pointer_fresh.status == .COMPLETE);
	pointer_probe_tokens := Extended.materialise_tokens(pointer_new_source);
	pointer_probe := Extended.Parser.{parsed=*pointer_probe_tokens, edit_source=*pointer_old, cursor=pointer_updated.root.(*Extended.Parser_Block).statements[2].first_token.(s64)};
	set_allocators(*pointer_probe_tokens.node_pool, context.default_allocator);
	pointer_probe.current_scope = Extended.push_lexical_scope(*pointer_probe);
	pointer_probe_tokens.root = Extended.reuse_simple_declaration(*pointer_probe);
	assert(pointer_probe_tokens.root && pointer_probe.current_scope.references.count == 2);
	Extended.release_parser_tree(*pointer_probe_tokens);
	Extended.release_parser_names(*pointer_probe_tokens);

	pointer_statements := pointer_updated.root.(*Extended.Parser_Block).statements;
	pointer_fresh_statements := pointer_fresh.root.(*Extended.Parser_Block).statements;
	pointer_cast := pointer_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Cast);
	pointer_fresh_cast := pointer_fresh_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Cast);
	assert(pointer_cast.target_type.first_token == pointer_fresh_cast.target_type.first_token && pointer_cast.target_type.one_past_last_token == pointer_fresh_cast.target_type.one_past_last_token);
	assert(pointer_cast.target_type.l0 == pointer_fresh_cast.target_type.l0 && pointer_cast.target_type.c0 == pointer_fresh_cast.target_type.c0);
	assert(pointer_cast.target_type.l1 == pointer_fresh_cast.target_type.l1 && pointer_cast.target_type.c1 == pointer_fresh_cast.target_type.c1);
	assert(
		pointer_cast.target_type.pointer_to.first_token == pointer_fresh_cast.target_type.pointer_to.first_token
		&& pointer_cast.target_type.pointer_to.one_past_last_token == pointer_fresh_cast.target_type.pointer_to.one_past_last_token
	);
	pointer_ident := pointer_cast.target_type.pointer_to.type_valued_expression.(*Extended.Parser_Ident);
	assert(pointer_ident.resolved_declaration == pointer_statements[0].(*Extended.Parser_Declaration));
	assert(pointer_fresh_cast.target_type.pointer_to.type_valued_expression.(*Extended.Parser_Ident).resolved_declaration == pointer_fresh_statements[0].(*Extended.Parser_Declaration));
	assert(pointer_cast.expression.(*Extended.Parser_Ident).resolved_declaration == pointer_statements[1].(*Extended.Parser_Declaration));
	assert(pointer_updated.diagnostics.count == pointer_fresh.diagnostics.count && pointer_updated.restart_points.count == pointer_fresh.restart_points.count);
	Extended.release_parser_tree(*pointer_old);
	Extended.release_parser_names(*pointer_old);
	free(pointer_old_source);
	assert(pointer_ident.name == "Target" && Extended.reconstruct_source(*pointer_updated) == pointer_new_source);
	Extended.release_parser_tree(*pointer_updated);
	Extended.release_parser_names(*pointer_updated);
	Extended.release_parser_tree(*pointer_fresh);
	Extended.release_parser_names(*pointer_fresh);
	free(pointer_new_source);

	view_old_source := copy_string(				 "value :: 1; result := cast([]Target) value;");
	view_new_source := copy_string("Target :: 2;\nvalue :: 1; result := cast([]Target) value;");
	view_old := Extended.parse_file(view_old_source);
	view_updated, view_ok := Extended.parse_file_edit(*view_old, 0, 0, view_new_source);
	view_fresh := Extended.parse_file(view_new_source);
	assert(view_ok && view_old.status == .COMPLETE && view_updated.status == .COMPLETE && view_fresh.status == .COMPLETE);
	view_statements := view_updated.root.(*Extended.Parser_Block).statements;
	view_fresh_statements := view_fresh.root.(*Extended.Parser_Block).statements;
	view_probe_tokens := Extended.materialise_tokens(view_new_source);
	view_probe := Extended.Parser.{parsed=*view_probe_tokens, edit_source=*view_old, cursor=view_statements[2].first_token.(s64)};
	set_allocators(*view_probe_tokens.node_pool, context.default_allocator);
	view_probe.current_scope = Extended.push_lexical_scope(*view_probe);
	view_probe_tokens.root = Extended.reuse_simple_declaration(*view_probe);
	assert(view_probe_tokens.root && view_probe.current_scope.references.count == 2);
	Extended.release_parser_tree(*view_probe_tokens);
	Extended.release_parser_names(*view_probe_tokens);
	view_cast := view_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Cast);
	view_fresh_cast := view_fresh_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Cast);
	assert(view_cast.first_token == view_fresh_cast.first_token && view_cast.one_past_last_token == view_fresh_cast.one_past_last_token);
	view_type := view_cast.target_type;
	view_fresh_type := view_fresh_cast.target_type;
	assert(view_type.inst_flags == .ARRAY_VIEW && view_type.inst_flags == view_fresh_type.inst_flags);
	assert(view_type.first_token == view_fresh_type.first_token && view_type.one_past_last_token == view_fresh_type.one_past_last_token);
	assert(view_type.l0 == view_fresh_type.l0 && view_type.c0 == view_fresh_type.c0 && view_type.l1 == view_fresh_type.l1 && view_type.c1 == view_fresh_type.c1);
	view_name := view_type.array_element_type.type_valued_expression.(*Extended.Parser_Ident);
	assert(view_name.resolved_declaration == view_statements[0].(*Extended.Parser_Declaration));
	assert(view_fresh_type.array_element_type.type_valued_expression.(*Extended.Parser_Ident).resolved_declaration == view_fresh_statements[0].(*Extended.Parser_Declaration));
	assert(view_cast.expression.(*Extended.Parser_Ident).resolved_declaration == view_statements[1].(*Extended.Parser_Declaration));
	assert(view_updated.diagnostics.count == view_fresh.diagnostics.count && view_updated.restart_points.count == view_fresh.restart_points.count);
	Extended.release_parser_tree(*view_old);
	Extended.release_parser_names(*view_old);
	free(view_old_source);
	assert(view_name.name == "Target" && Extended.reconstruct_source(*view_updated) == view_new_source);
	Extended.release_parser_tree(*view_updated);
	Extended.release_parser_names(*view_updated);
	Extended.release_parser_tree(*view_fresh);
	Extended.release_parser_names(*view_fresh);
	free(view_new_source);

	array_old_source := copy_string(						 "value :: 1; result := cast([size]Target) value;");
	array_new_source := copy_string("size :: 4; Target :: 2;\nvalue :: 1; result := cast([size]Target) value;");
	array_old := Extended.parse_file(array_old_source);
	array_updated, array_ok := Extended.parse_file_edit(*array_old, 0, 0, array_new_source);
	array_fresh := Extended.parse_file(array_new_source);
	assert(array_ok && array_old.status == .COMPLETE && array_updated.status == .COMPLETE && array_fresh.status == .COMPLETE);
	array_statements := array_updated.root.(*Extended.Parser_Block).statements;
	array_fresh_statements := array_fresh.root.(*Extended.Parser_Block).statements;
	array_probe_tokens := Extended.materialise_tokens(array_new_source);
	array_probe := Extended.Parser.{parsed=*array_probe_tokens, edit_source=*array_old, cursor=array_statements[3].first_token.(s64)};
	set_allocators(*array_probe_tokens.node_pool, context.default_allocator);
	array_probe.current_scope = Extended.push_lexical_scope(*array_probe);
	array_probe_tokens.root = Extended.reuse_simple_declaration(*array_probe);
	assert(array_probe_tokens.root && array_probe.current_scope.references.count == 3);
	Extended.release_parser_tree(*array_probe_tokens);
	Extended.release_parser_names(*array_probe_tokens);
	array_cast := array_statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Cast);
	array_fresh_cast := array_fresh_statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Cast);
	assert(array_cast.first_token == array_fresh_cast.first_token && array_cast.one_past_last_token == array_fresh_cast.one_past_last_token);
	array_type := array_cast.target_type;
	array_fresh_type := array_fresh_cast.target_type;
	assert(array_type.first_token == array_fresh_type.first_token && array_type.one_past_last_token == array_fresh_type.one_past_last_token);
	assert(array_type.l0 == array_fresh_type.l0 && array_type.c0 == array_fresh_type.c0 && array_type.l1 == array_fresh_type.l1 && array_type.c1 == array_fresh_type.c1);
	array_size := array_type.array_dimension.(*Extended.Parser_Ident);
	assert(array_size.first_token == array_fresh_type.array_dimension.first_token && array_size.one_past_last_token == array_fresh_type.array_dimension.one_past_last_token);
	assert(array_size.resolved_declaration == array_statements[0].(*Extended.Parser_Declaration));
	assert(array_fresh_type.array_dimension.(*Extended.Parser_Ident).resolved_declaration == array_fresh_statements[0].(*Extended.Parser_Declaration));
	assert(array_type.array_element_type.type_valued_expression.(*Extended.Parser_Ident).resolved_declaration == array_statements[1].(*Extended.Parser_Declaration));
	assert(array_fresh_type.array_element_type.type_valued_expression.(*Extended.Parser_Ident).resolved_declaration == array_fresh_statements[1].(*Extended.Parser_Declaration));
	assert(array_cast.expression.(*Extended.Parser_Ident).resolved_declaration == array_statements[2].(*Extended.Parser_Declaration));
	assert(array_updated.diagnostics.count == array_fresh.diagnostics.count && array_updated.restart_points.count == array_fresh.restart_points.count);
	Extended.release_parser_tree(*array_old);
	Extended.release_parser_names(*array_old);
	free(array_old_source);
	assert(array_size.name == "size" && Extended.reconstruct_source(*array_updated) == array_new_source);
	Extended.release_parser_tree(*array_updated);
	Extended.release_parser_names(*array_updated);
	Extended.release_parser_tree(*array_fresh);
	Extended.release_parser_names(*array_fresh);
	free(array_new_source);

	double_old_source := copy_string(			   "value :: 1; result := cast(**Target) value;");
	double_new_source := copy_string("Target :: 2;\nvalue :: 1; result := cast(**Target) value;");
	double_old := Extended.parse_file(double_old_source);
	double_updated, double_ok := Extended.parse_file_edit(*double_old, 0, 0, double_new_source);
	double_fresh := Extended.parse_file(double_new_source);
	assert(double_ok && double_old.status == .COMPLETE && double_updated.status == .COMPLETE && double_fresh.status == .COMPLETE);
	double_statements := double_updated.root.(*Extended.Parser_Block).statements;
	double_fresh_statements := double_fresh.root.(*Extended.Parser_Block).statements;
	double_probe_tokens := Extended.materialise_tokens(double_new_source);
	double_probe := Extended.Parser.{parsed=*double_probe_tokens, edit_source=*double_old, cursor=double_statements[2].first_token.(s64)};
	set_allocators(*double_probe_tokens.node_pool, context.default_allocator);
	double_probe.current_scope = Extended.push_lexical_scope(*double_probe);
	double_probe_tokens.root = Extended.reuse_simple_declaration(*double_probe);
	assert(double_probe_tokens.root && double_probe.current_scope.references.count == 2);
	Extended.release_parser_tree(*double_probe_tokens);
	Extended.release_parser_names(*double_probe_tokens);
	double_cast := double_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Cast);
	double_fresh_cast := double_fresh_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Cast);
	assert(double_cast.first_token == double_fresh_cast.first_token && double_cast.one_past_last_token == double_fresh_cast.one_past_last_token);
	assert(double_cast.target_type.first_token == double_fresh_cast.target_type.first_token && double_cast.target_type.one_past_last_token == double_fresh_cast.target_type.one_past_last_token);
	assert(double_cast.target_type.l0 == double_fresh_cast.target_type.l0 && double_cast.target_type.c0 == double_fresh_cast.target_type.c0);
	assert(double_cast.target_type.l1 == double_fresh_cast.target_type.l1 && double_cast.target_type.c1 == double_fresh_cast.target_type.c1);
	double_inner := double_cast.target_type.pointer_to;
	double_fresh_inner := double_fresh_cast.target_type.pointer_to;
	assert(double_inner.first_token == double_fresh_inner.first_token && double_inner.one_past_last_token == double_fresh_inner.one_past_last_token);
	assert(double_inner.l0 == double_fresh_inner.l0 && double_inner.c0 == double_fresh_inner.c0 && double_inner.l1 == double_fresh_inner.l1 && double_inner.c1 == double_fresh_inner.c1);
	double_name := double_inner.pointer_to.type_valued_expression.(*Extended.Parser_Ident);
	assert(double_name.resolved_declaration == double_statements[0].(*Extended.Parser_Declaration));
	assert(double_fresh_inner.pointer_to.type_valued_expression.(*Extended.Parser_Ident).resolved_declaration == double_fresh_statements[0].(*Extended.Parser_Declaration));
	assert(double_cast.expression.(*Extended.Parser_Ident).resolved_declaration == double_statements[1].(*Extended.Parser_Declaration));
	assert(double_updated.diagnostics.count == double_fresh.diagnostics.count && double_updated.restart_points.count == double_fresh.restart_points.count);
	Extended.release_parser_tree(*double_old);
	Extended.release_parser_names(*double_old);
	free(double_old_source);
	assert(double_name.name == "Target" && Extended.reconstruct_source(*double_updated) == double_new_source);
	Extended.release_parser_tree(*double_updated);
	Extended.release_parser_names(*double_updated);
	Extended.release_parser_tree(*double_fresh);
	Extended.release_parser_names(*double_fresh);
	free(double_new_source);
}

test_cast_flags_ast_reuse :: () {
	expressions: []string = .["cast,no_check(Target) value", "value.(Target)"];
	for expressions {
		old_source := copy_string(tprint(			  "Target :: 1; value :: 2; result := %;", it));
		new_source := copy_string(tprint("added :: 0;\nTarget :: 1; value :: 2; result := %;", it));
		old := Extended.parse_file(old_source);
		updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
		fresh := Extended.parse_file(new_source);
		assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE && fresh.status == .COMPLETE, "%", it);
		statements := updated.root.(*Extended.Parser_Block).statements;
		fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
		probe_tokens := Extended.materialise_tokens(new_source);
		probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, cursor=statements[3].first_token.(s64)};
		set_allocators(*probe_tokens.node_pool, context.default_allocator);
		probe.current_scope = Extended.push_lexical_scope(*probe);
		probe_tokens.root = Extended.reuse_simple_declaration(*probe);
		assert(probe_tokens.root != null && probe.current_scope.references.count == 2);
		Extended.release_parser_tree(*probe_tokens);
		Extended.release_parser_names(*probe_tokens);
		cast_node := statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Cast);
		fresh_cast := fresh_statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Cast);
		assert(cast_node.node_flags == fresh_cast.node_flags && cast_node.cast_flags == fresh_cast.cast_flags);
		if starts_with(it, "cast") {
			assert((cast_node.cast_flags & .NO_BOUNDS_CHECK) != 0);
		} else {
			assert((cast_node.cast_flags & .HAS_POSTFIX_SYNTAX) != 0);
		}

		assert(cast_node.first_token == fresh_cast.first_token && cast_node.one_past_last_token == fresh_cast.one_past_last_token);
		assert(cast_node.l0 == fresh_cast.l0 && cast_node.c0 == fresh_cast.c0 && cast_node.l1 == fresh_cast.l1 && cast_node.c1 == fresh_cast.c1);
		assert(cast_node.target_type != old.root.(*Extended.Parser_Block).statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Cast).target_type);
		assert(cast_node.target_type.first_token == fresh_cast.target_type.first_token && cast_node.target_type.one_past_last_token == fresh_cast.target_type.one_past_last_token);
		assert(cast_node.target_type.type_valued_expression.(*Extended.Parser_Ident).resolved_declaration == statements[1].(*Extended.Parser_Declaration));
		assert(fresh_cast.target_type.type_valued_expression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[1].(*Extended.Parser_Declaration));
		assert(cast_node.expression.(*Extended.Parser_Ident).resolved_declaration == statements[2].(*Extended.Parser_Declaration));
		assert(fresh_cast.expression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[2].(*Extended.Parser_Declaration));
		assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
		assert_eligible_edit_matches_fresh(*updated, *fresh);
		Extended.release_parser_tree(*old);
		Extended.release_parser_names(*old);
		free(old_source);
		assert(cast_node.target_type.type_valued_expression.(*Extended.Parser_Ident).name == "Target" && Extended.reconstruct_source(*updated) == new_source);
		Extended.release_parser_tree(*updated);
		Extended.release_parser_names(*updated);
		Extended.release_parser_tree(*fresh);
		Extended.release_parser_names(*fresh);
		free(new_source);
	}
}

test_call_ast_reuse :: () {
	old_source := copy_string(		   "value :: 2; result := f(value, 3 + 4);");
	new_source := copy_string("f :: 1;\nvalue :: 2; result := f(value, 3 + 4);");
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && updated.status == .COMPLETE && fresh.status == .COMPLETE);

	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, cursor=10};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root && probe_tokens.root.(*Extended.Parser_Declaration).expression.kind == .PROCEDURE_CALL);
	assert(probe.current_scope.references.count == 2);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);

	updated_statements := updated.root.(*Extended.Parser_Block).statements;
	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	old_call := old.root.(*Extended.Parser_Block).statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Call);
	updated_call := updated_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Call);
	fresh_call := fresh_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Call);
	assert(updated_call.kind == fresh_call.kind && updated_call.node_flags == fresh_call.node_flags && updated_call.flags == fresh_call.flags);
	assert(updated_call.arguments_unsorted.count == fresh_call.arguments_unsorted.count && updated_call.arguments_unsorted.count == 2);
	assert(updated_call.arguments_unsorted.data != old_call.arguments_unsorted.data);
	assert(updated_call.first_token == fresh_call.first_token && updated_call.one_past_last_token == fresh_call.one_past_last_token);
	assert(updated_call.l0 == fresh_call.l0 && updated_call.c0 == fresh_call.c0 && updated_call.l1 == fresh_call.l1 && updated_call.c1 == fresh_call.c1);
	assert(updated_call.arguments_unsorted[1].expression.first_token == fresh_call.arguments_unsorted[1].expression.first_token);
	assert(updated_call.arguments_unsorted[1].expression.one_past_last_token == fresh_call.arguments_unsorted[1].expression.one_past_last_token);
	assert(updated_call.arguments_unsorted[1].expression.node_flags == fresh_call.arguments_unsorted[1].expression.node_flags);
	assert(updated_call.arguments_unsorted[1].expression.(*Extended.Parser_Binary_Operator).operator_type == #char "+");
	old_callee := old_call.procedure_expression.(*Extended.Parser_Ident);
	updated_callee := updated_call.procedure_expression.(*Extended.Parser_Ident);
	assert(old_callee.resolved_declaration == null);
	assert(updated_callee.resolved_declaration == updated_statements[0].(*Extended.Parser_Declaration));
	assert(fresh_call.procedure_expression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[0].(*Extended.Parser_Declaration));
	assert(updated_call.arguments_unsorted[0].expression.(*Extended.Parser_Ident).resolved_declaration == updated_statements[1].(*Extended.Parser_Declaration));
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	assert_eligible_edit_matches_fresh(*updated, *fresh);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(updated_callee.name == "f" && Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);

	named_old_source :=	copy_string(		   "result := f(name=3);");
	named_new :=		copy_string("name :: 0; result := f(name=3);");
	named_old := Extended.parse_file(named_old_source);
	named_updated, named_ok := Extended.parse_file_edit(*named_old, 0, 0, named_new);
	named_fresh := Extended.parse_file(named_new);
	assert(named_ok && named_updated.status == .COMPLETE);
	named_tokens := Extended.materialise_tokens(named_new);
	named_probe := Extended.Parser.{parsed=*named_tokens, edit_source=*named_old, cursor=5};
	set_allocators(*named_tokens.node_pool, context.default_allocator);
	named_probe.current_scope = Extended.push_lexical_scope(*named_probe);
	named_tokens.root = Extended.reuse_simple_declaration(*named_probe);
	assert(named_tokens.root && named_tokens.root.(*Extended.Parser_Declaration).expression.kind == .PROCEDURE_CALL);
	assert(named_probe.current_scope.references.count == 1);
	named_label := named_updated.root.(*Extended.Parser_Block).statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Call).arguments_unsorted[0].name;
	fresh_label := named_fresh.root.(*Extended.Parser_Block).statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Call).arguments_unsorted[0].name;
	assert(named_label.resolved_declaration == null && fresh_label.resolved_declaration == null);
	assert(named_label.first_token == fresh_label.first_token && named_label.one_past_last_token == fresh_label.one_past_last_token);
	Extended.release_parser_tree(*named_old);
	Extended.release_parser_names(*named_old);
	free(named_old_source);
	assert(named_label.name == "name" && named_label.name.data == named_updated.tokens[10].ident_value.name.data);
	Extended.release_parser_tree(*named_updated);
	Extended.release_parser_names(*named_updated);
	Extended.release_parser_tree(*named_tokens);
	Extended.release_parser_names(*named_tokens);
	Extended.release_parser_tree(*named_fresh);
	Extended.release_parser_names(*named_fresh);
	free(named_new);
}

test_member_callee_ast_reuse :: () {
	old_source := copy_string(			   "object :: 1; value :: 2; result := object.method(named=value + 1);");
	new_source := copy_string("named :: 0;\nobject :: 1; value :: 2; result := object.method(named=value + 1);");
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE && fresh.status == .COMPLETE);
	statements := updated.root.(*Extended.Parser_Block).statements;
	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, cursor=statements[3].first_token.(s64)};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root != null && probe.current_scope.references.count == 3);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);
	old_call := old.root.(*Extended.Parser_Block).statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Call);
	call := statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Call);
	fresh_call := fresh_statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Call);
	assert(call.arguments_unsorted.data != old_call.arguments_unsorted.data && call.arguments_unsorted.count == 1);
	assert(call.first_token == fresh_call.first_token && call.one_past_last_token == fresh_call.one_past_last_token);
	assert(call.l0 == fresh_call.l0 && call.c0 == fresh_call.c0 && call.l1 == fresh_call.l1 && call.c1 == fresh_call.c1);
	callee := call.procedure_expression.(*Extended.Parser_Binary_Operator);
	fresh_callee := fresh_call.procedure_expression.(*Extended.Parser_Binary_Operator);
	assert(callee.operator_type == #char "." && callee.first_token == fresh_callee.first_token && callee.one_past_last_token == fresh_callee.one_past_last_token);
	assert(callee.left.(*Extended.Parser_Ident).resolved_declaration == statements[1].(*Extended.Parser_Declaration));
	assert(fresh_callee.left.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[1].(*Extended.Parser_Declaration));
	assert(callee.right.(*Extended.Parser_Ident).resolved_declaration == null && fresh_callee.right.(*Extended.Parser_Ident).resolved_declaration == null);
	argument := call.arguments_unsorted[0];
	fresh_argument := fresh_call.arguments_unsorted[0];
	assert(argument.name != old_call.arguments_unsorted[0].name && argument.name.resolved_declaration == null && fresh_argument.name.resolved_declaration == null);
	assert(argument.name.first_token == fresh_argument.name.first_token && argument.name.one_past_last_token == fresh_argument.name.one_past_last_token);
	assert(argument.expression.(*Extended.Parser_Binary_Operator).left.(*Extended.Parser_Ident).resolved_declaration == statements[2].(*Extended.Parser_Declaration));
	assert(fresh_argument.expression.(*Extended.Parser_Binary_Operator).left.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[2].(*Extended.Parser_Declaration));
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(argument.name.name == "named" && callee.right.(*Extended.Parser_Ident).name == "method" && Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);
}

test_call_context_ast_reuse :: () {
	old_source := copy_string(		   "extra :: 2; result := f(1,, extra);");
	new_source := copy_string("f :: 1;\nextra :: 2; result := f(1,, extra);");
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && updated.status == .COMPLETE && fresh.status == .COMPLETE);

	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, cursor=10};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root && probe_tokens.root.(*Extended.Parser_Declaration).expression.kind == .PROCEDURE_CALL);
	assert(probe.current_scope.references.count == 2);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);

	old_call := old.root.(*Extended.Parser_Block).statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Call);
	statements := updated.root.(*Extended.Parser_Block).statements;
	call := statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Call);
	fresh_call := fresh.root.(*Extended.Parser_Block).statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Call);
	assert(call.context_modification && call.context_modification != old_call.context_modification);
	assert(call.context_modification.modification_expressions.data != old_call.context_modification.modification_expressions.data);
	assert(call.context_modification.modification_expressions.count == 1);
	assert(call.context_modification.modification_expressions[0].first_token == fresh_call.context_modification.modification_expressions[0].first_token);
	assert(call.context_modification.modification_expressions[0].(*Extended.Parser_Ident).resolved_declaration == statements[1].(*Extended.Parser_Declaration));
	assert(call.procedure_expression.(*Extended.Parser_Ident).resolved_declaration == statements[0].(*Extended.Parser_Declaration));
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(call.context_modification.modification_expressions[0].(*Extended.Parser_Ident).name == "extra");
	assert(Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);
}

test_call_context_fallback :: () {
	old_source := copy_string(			   "f :: 1; extra :: 2; result := f(1,, allocator = extra); keep := result;");
	new_source := copy_string("added :: 0;\nf :: 1; extra :: 2; result := f(1,, allocator = extra); keep := result;");
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE && fresh.status == .COMPLETE);
	old_call := old.root.(*Extended.Parser_Block).statements[2].(*Extended.Parser_Declaration).expression;
	assert(old_call.kind == .PROCEDURE_CALL && !Extended.reusable_expression(old_call));
	statements := updated.root.(*Extended.Parser_Block).statements;
	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, cursor=statements[3].first_token.(s64)};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	assert(Extended.reuse_simple_declaration(*probe) == null);
	probe.cursor = statements[4].first_token.(s64);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root != null);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);
	call := statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Call);
	fresh_call := fresh_statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Call);
	assert(call.first_token == fresh_call.first_token && call.one_past_last_token == fresh_call.one_past_last_token);
	assert(call.l0 == fresh_call.l0 && call.c0 == fresh_call.c0 && call.l1 == fresh_call.l1 && call.c1 == fresh_call.c1);
	assert(call.procedure_expression.(*Extended.Parser_Ident).resolved_declaration == statements[1].(*Extended.Parser_Declaration));
	assert(fresh_call.procedure_expression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[1].(*Extended.Parser_Declaration));
	modification := call.context_modification.modification_expressions[0].(*Extended.Parser_Binary_Operator);
	fresh_modification := fresh_call.context_modification.modification_expressions[0].(*Extended.Parser_Binary_Operator);
	assert(modification.operator_type == #char "=" && modification.operator_type == fresh_modification.operator_type);
	assert(modification.first_token == fresh_modification.first_token && modification.one_past_last_token == fresh_modification.one_past_last_token);
	assert(modification.right.(*Extended.Parser_Ident).resolved_declaration == statements[2].(*Extended.Parser_Declaration));
	assert(fresh_modification.right.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[2].(*Extended.Parser_Declaration));
	assert(statements[4].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == statements[3].(*Extended.Parser_Declaration));
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(modification.right.(*Extended.Parser_Ident).name == "extra" && Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);
}

test_call_cast_fallback :: () {
	expressions: []string = .["null(value)", "target(null)", "target(value,, null)", "xx value", "cast([#run 4] target) value", "cast((s64) -> s64) value", "cast(target) null"];
	for expressions {
		old_source := copy_string(tprint(			  "target :: 1; value :: 2; result := %; keep := result;", it));
		new_source := copy_string(tprint("added :: 0;\ntarget :: 1; value :: 2; result := %; keep := result;", it));
		old := Extended.parse_file(old_source);
		updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
		fresh := Extended.parse_file(new_source);
		assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE && fresh.status == .COMPLETE, "%", it);
		old_expression := old.root.(*Extended.Parser_Block).statements[2].(*Extended.Parser_Declaration).expression;
		assert((old_expression.kind == .PROCEDURE_CALL || old_expression.kind == .CAST) && !Extended.reusable_expression(old_expression), "%", it);
		statements := updated.root.(*Extended.Parser_Block).statements;
		fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
		probe_tokens := Extended.materialise_tokens(new_source);
		probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, cursor=statements[3].first_token.(s64)};
		set_allocators(*probe_tokens.node_pool, context.default_allocator);
		probe.current_scope = Extended.push_lexical_scope(*probe);
		assert(Extended.reuse_simple_declaration(*probe) == null);
		probe.cursor = statements[4].first_token.(s64);
		probe_tokens.root = Extended.reuse_simple_declaration(*probe);
		assert(probe_tokens.root != null);
		Extended.release_parser_tree(*probe_tokens);
		Extended.release_parser_names(*probe_tokens);
		expression := statements[3].(*Extended.Parser_Declaration).expression;
		fresh_expression := fresh_statements[3].(*Extended.Parser_Declaration).expression;
		assert(expression.kind == fresh_expression.kind);
		assert(expression.first_token == fresh_expression.first_token && expression.one_past_last_token == fresh_expression.one_past_last_token);
		assert(expression.l0 == fresh_expression.l0 && expression.c0 == fresh_expression.c0 && expression.l1 == fresh_expression.l1 && expression.c1 == fresh_expression.c1);
		assert(statements[4].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == statements[3].(*Extended.Parser_Declaration));
		assert(fresh_statements[4].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[3].(*Extended.Parser_Declaration));
		assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
		Extended.release_parser_tree(*old);
		Extended.release_parser_names(*old);
		free(old_source);
		assert(Extended.reconstruct_source(*updated) == new_source);
		Extended.release_parser_tree(*updated);
		Extended.release_parser_names(*updated);
		Extended.release_parser_tree(*fresh);
		Extended.release_parser_names(*fresh);
		free(new_source);
	}
}

test_call_cast_candidate_edits :: () {
	check_call_cast_candidate_edit("Target(value)", "value(value)", 0, "Target".count);
	check_call_cast_candidate_edit("Target(name=value)", "Target(other=value)", "Target(".count, "Target(name".count);
	check_call_cast_candidate_edit("Target(value)", "Target(null)", "Target(".count, "Target(value".count);
	check_call_cast_candidate_edit("Target(value,, value)", "Target(value, value)", "Target(value,".count, "Target(value,,".count);
	check_call_cast_candidate_edit("cast(Target) value", "cast(value) value", "cast(".count, "cast(Target".count);
	check_call_cast_candidate_edit("cast(Target) value", "cast(Target) Target", "cast(Target) ".count, "cast(Target) value".count);
}

check_call_cast_candidate_edit :: (old_expression: string, new_expression: string, edit_first: s64, edit_last: s64) {
	PREFIX :: "Target :: 1; value :: 2; result := ";
	old_source := copy_string(tprint("%%; keep := result;", PREFIX, old_expression));
	new_source := copy_string(tprint("%%; keep := result;", PREFIX, new_expression));
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, PREFIX.count + edit_first, PREFIX.count + edit_last, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE && fresh.status == .COMPLETE, "% -> %", old_expression, new_expression);
	statements := updated.root.(*Extended.Parser_Block).statements;
	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, edit_start=PREFIX.count + edit_first, edit_end=PREFIX.count + edit_last, cursor=statements[2].first_token.(s64)};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	assert(Extended.reuse_simple_declaration(*probe) == null);
	probe.cursor = statements[3].first_token.(s64);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root != null);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);
	expression := statements[2].(*Extended.Parser_Declaration).expression;
	fresh_expression := fresh_statements[2].(*Extended.Parser_Declaration).expression;
	assert(expression.kind == fresh_expression.kind);
	assert(expression.first_token == fresh_expression.first_token && expression.one_past_last_token == fresh_expression.one_past_last_token);
	assert(expression.l0 == fresh_expression.l0 && expression.c0 == fresh_expression.c0 && expression.l1 == fresh_expression.l1 && expression.c1 == fresh_expression.c1);
	assert(statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == statements[2].(*Extended.Parser_Declaration));
	assert(fresh_statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[2].(*Extended.Parser_Declaration));
	if expression.kind == .PROCEDURE_CALL {
		call := expression.(*Extended.Parser_Procedure_Call);
		fresh_call := fresh_expression.(*Extended.Parser_Procedure_Call);
		callee_index := 0;
		if call.procedure_expression.(*Extended.Parser_Ident).name == "value" {
			callee_index = 1;
		}

		assert(call.procedure_expression.(*Extended.Parser_Ident).resolved_declaration == statements[callee_index].(*Extended.Parser_Declaration));
		assert(fresh_call.procedure_expression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[callee_index].(*Extended.Parser_Declaration));
		assert(call.arguments_unsorted.count == fresh_call.arguments_unsorted.count);
		for index: 0..call.arguments_unsorted.count-1 {
			assert(call.arguments_unsorted[index].expression.kind == fresh_call.arguments_unsorted[index].expression.kind);
			assert(call.arguments_unsorted[index].expression.first_token == fresh_call.arguments_unsorted[index].expression.first_token);
			if call.arguments_unsorted[index].name {
				assert(call.arguments_unsorted[index].name.resolved_declaration == null && fresh_call.arguments_unsorted[index].name.resolved_declaration == null);
			}
		}
	} else {
		cast_node := expression.(*Extended.Parser_Cast);
		fresh_cast := fresh_expression.(*Extended.Parser_Cast);
		assert(cast_node.cast_flags == fresh_cast.cast_flags);
		assert(cast_node.target_type.first_token == fresh_cast.target_type.first_token && cast_node.target_type.one_past_last_token == fresh_cast.target_type.one_past_last_token);
		assert(cast_node.target_type.type_valued_expression.(*Extended.Parser_Ident).name == fresh_cast.target_type.type_valued_expression.(*Extended.Parser_Ident).name);
		assert(cast_node.expression.(*Extended.Parser_Ident).name == fresh_cast.expression.(*Extended.Parser_Ident).name);
		target_index := 0;
		if cast_node.target_type.type_valued_expression.(*Extended.Parser_Ident).name == "value" {
			target_index = 1;
		}

		operand_index := 0;
		if cast_node.expression.(*Extended.Parser_Ident).name == "value" {
			operand_index = 1;
		}

		assert(cast_node.target_type.type_valued_expression.(*Extended.Parser_Ident).resolved_declaration == statements[target_index].(*Extended.Parser_Declaration));
		assert(fresh_cast.target_type.type_valued_expression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[target_index].(*Extended.Parser_Declaration));
		assert(cast_node.expression.(*Extended.Parser_Ident).resolved_declaration == statements[operand_index].(*Extended.Parser_Declaration));
		assert(fresh_cast.expression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[operand_index].(*Extended.Parser_Declaration));
	}

	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);
}

test_member_ast_reuse :: () {
	old_source := copy_string(			   "object :: 1; result := object.field;");
	new_source := copy_string("field :: 5;\nobject :: 1; result := object.field;");
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && updated.status == .COMPLETE && fresh.status == .COMPLETE);

	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, cursor=10};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root && probe_tokens.root.(*Extended.Parser_Declaration).expression.kind == .BINARY_OPERATOR);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);

	statements := updated.root.(*Extended.Parser_Block).statements;
	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	access := statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Binary_Operator);
	fresh_access := fresh_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Binary_Operator);
	assert(access.operator_type == #char "." && access.first_token == fresh_access.first_token && access.one_past_last_token == fresh_access.one_past_last_token);
	assert(access.left.(*Extended.Parser_Ident).resolved_declaration == statements[1].(*Extended.Parser_Declaration));
	assert(access.right.(*Extended.Parser_Ident).resolved_declaration == null);
	assert(fresh_access.right.(*Extended.Parser_Ident).resolved_declaration == null);
	assert((access.right.(*Extended.Parser_Ident).flags & .IS_RHS_OF_DOT_DEREFERENCE) != 0);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(access.right.(*Extended.Parser_Ident).name == "field" && Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);

	chain_old_source := copy_string(						  "index :: 0; object :: 1; result := (object.field)[index].member;");
	chain_new_source := copy_string("field :: 5; member :: 6;\nindex :: 0; object :: 1; result := (object.field)[index].member;");
	chain_old := Extended.parse_file(chain_old_source);
	chain_updated, chain_ok := Extended.parse_file_edit(*chain_old, 0, 0, chain_new_source);
	chain_fresh := Extended.parse_file(chain_new_source);
	assert(chain_ok && chain_old.status == .COMPLETE && chain_updated.status == .COMPLETE && chain_fresh.status == .COMPLETE);
	chain_statements := chain_updated.root.(*Extended.Parser_Block).statements;
	chain_fresh_statements := chain_fresh.root.(*Extended.Parser_Block).statements;
	chain_probe_tokens := Extended.materialise_tokens(chain_new_source);
	chain_probe := Extended.Parser.{parsed=*chain_probe_tokens, edit_source=*chain_old, cursor=chain_statements[4].first_token.(s64)};
	set_allocators(*chain_probe_tokens.node_pool, context.default_allocator);
	chain_probe.current_scope = Extended.push_lexical_scope(*chain_probe);
	chain_probe_tokens.root = Extended.reuse_simple_declaration(*chain_probe);
	assert(chain_probe_tokens.root != null);
	Extended.release_parser_tree(*chain_probe_tokens);
	Extended.release_parser_names(*chain_probe_tokens);
	chain_outer := chain_statements[4].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Binary_Operator);
	chain_fresh_outer := chain_fresh_statements[4].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Binary_Operator);
	assert(chain_outer.operator_type == #char "." && chain_outer.first_token == chain_fresh_outer.first_token && chain_outer.one_past_last_token == chain_fresh_outer.one_past_last_token);
	assert(chain_outer.right.(*Extended.Parser_Ident).name == "member" && !chain_outer.right.(*Extended.Parser_Ident).resolved_declaration);
	assert(!chain_fresh_outer.right.(*Extended.Parser_Ident).resolved_declaration);
	chain_index := chain_outer.left.(*Extended.Parser_Binary_Operator);
	chain_fresh_index := chain_fresh_outer.left.(*Extended.Parser_Binary_Operator);
	assert(chain_index.operator_type == .ARRAY_SUBSCRIPT && chain_index.first_token == chain_fresh_index.first_token && chain_index.one_past_last_token == chain_fresh_index.one_past_last_token);
	assert(chain_index.right.(*Extended.Parser_Ident).resolved_declaration == chain_statements[2].(*Extended.Parser_Declaration));
	assert(chain_fresh_index.right.(*Extended.Parser_Ident).resolved_declaration == chain_fresh_statements[2].(*Extended.Parser_Declaration));
	chain_inner := chain_index.left.(*Extended.Parser_Binary_Operator);
	chain_fresh_inner := chain_fresh_index.left.(*Extended.Parser_Binary_Operator);
	assert(chain_inner.node_flags & .IS_PARENTHESIZED && chain_inner.node_flags == chain_fresh_inner.node_flags);
	assert(chain_inner.first_token == chain_fresh_inner.first_token && chain_inner.one_past_last_token == chain_fresh_inner.one_past_last_token);
	assert(chain_inner.left.(*Extended.Parser_Ident).resolved_declaration == chain_statements[3].(*Extended.Parser_Declaration));
	assert(chain_fresh_inner.left.(*Extended.Parser_Ident).resolved_declaration == chain_fresh_statements[3].(*Extended.Parser_Declaration));
	assert(chain_inner.right.(*Extended.Parser_Ident).name == "field" && !chain_inner.right.(*Extended.Parser_Ident).resolved_declaration);
	assert(!chain_fresh_inner.right.(*Extended.Parser_Ident).resolved_declaration);
	assert(chain_updated.diagnostics.count == chain_fresh.diagnostics.count && chain_updated.restart_points.count == chain_fresh.restart_points.count);
	Extended.release_parser_tree(*chain_old);
	Extended.release_parser_names(*chain_old);
	free(chain_old_source);
	assert(chain_inner.left.(*Extended.Parser_Ident).name == "object" && chain_outer.right.(*Extended.Parser_Ident).name == "member");
	assert(Extended.reconstruct_source(*chain_updated) == chain_new_source);
	Extended.release_parser_tree(*chain_updated);
	Extended.release_parser_names(*chain_updated);
	Extended.release_parser_tree(*chain_fresh);
	Extended.release_parser_names(*chain_fresh);
	free(chain_new_source);
}

test_subscript_ast_reuse :: () {
	old_source := copy_string(			   "values := .[10]; result := values[index];");
	new_source := copy_string("index :: 0;\nvalues := .[10]; result := values[index];");
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && updated.status == .COMPLETE && fresh.status == .COMPLETE);

	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, cursor=updated.root.(*Extended.Parser_Block).statements[2].first_token.(s64)};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root && probe_tokens.root.(*Extended.Parser_Declaration).expression.(*Extended.Parser_Binary_Operator).operator_type == .ARRAY_SUBSCRIPT);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);

	statements := updated.root.(*Extended.Parser_Block).statements;
	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	subscript := statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Binary_Operator);
	fresh_subscript := fresh_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Binary_Operator);
	assert(subscript.first_token == fresh_subscript.first_token && subscript.one_past_last_token == fresh_subscript.one_past_last_token);
	assert(subscript.left.(*Extended.Parser_Ident).resolved_declaration == statements[1].(*Extended.Parser_Declaration));
	assert(subscript.right.(*Extended.Parser_Ident).resolved_declaration == statements[0].(*Extended.Parser_Declaration));
	assert(fresh_subscript.right.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[0].(*Extended.Parser_Declaration));
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(subscript.right.(*Extended.Parser_Ident).name == "index" && Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);
}

test_aggregate_ast_reuse :: () {
	old_source := copy_string(				"name :: 1; items := .[name, .{2, \"blue\"}];");
	new_source := copy_string("prefix :: 0;\nname :: 1; items := .[name, .{2, \"blue\"}];");
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && updated.status == .COMPLETE && fresh.status == .COMPLETE);

	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, cursor=10};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root && probe_tokens.root.(*Extended.Parser_Declaration).expression.(*Extended.Parser_Literal).value_type == .ARRAY);
	assert(probe.current_scope.references.count == 1);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);

	old_array := old.root.(*Extended.Parser_Block).statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Literal);
	statements := updated.root.(*Extended.Parser_Block).statements;
	array_literal := statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Literal);
	fresh_array := fresh.root.(*Extended.Parser_Block).statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Literal);
	assert(array_literal.array_literal_info != old_array.array_literal_info);
	assert(array_literal.array_literal_info.array_members.data != old_array.array_literal_info.array_members.data);
	assert(array_literal.node_flags == fresh_array.node_flags && array_literal.value_flags == fresh_array.value_flags);
	assert(array_literal.first_token == fresh_array.first_token && array_literal.one_past_last_token == fresh_array.one_past_last_token);
	assert(array_literal.l0 == fresh_array.l0 && array_literal.c0 == fresh_array.c0 && array_literal.l1 == fresh_array.l1 && array_literal.c1 == fresh_array.c1);
	assert(array_literal.array_literal_info.array_members.count == fresh_array.array_literal_info.array_members.count);
	assert(array_literal.array_literal_info.array_members[0].(*Extended.Parser_Ident).resolved_declaration == statements[1].(*Extended.Parser_Declaration));
	assert(fresh_array.array_literal_info.array_members[0].(*Extended.Parser_Ident).resolved_declaration == fresh.root.(*Extended.Parser_Block).statements[1].(*Extended.Parser_Declaration));
	nested := array_literal.array_literal_info.array_members[1].(*Extended.Parser_Literal);
	old_nested := old_array.array_literal_info.array_members[1].(*Extended.Parser_Literal);
	fresh_nested := fresh_array.array_literal_info.array_members[1].(*Extended.Parser_Literal);
	assert(nested.value_type == .STRUCT && nested.struct_literal_info != old_nested.struct_literal_info);
	assert(nested.node_flags == fresh_nested.node_flags && nested.value_flags == fresh_nested.value_flags);
	assert(nested.struct_literal_info.arguments.data != old_nested.struct_literal_info.arguments.data);
	assert(nested.first_token == fresh_nested.first_token && nested.one_past_last_token == fresh_nested.one_past_last_token);
	assert(nested.struct_literal_info.arguments.count == 2 && nested.struct_literal_info.arguments[1].(*Extended.Parser_Literal)._string == "blue");
	assert(nested.struct_literal_info.arguments[1].first_token == fresh_nested.struct_literal_info.arguments[1].first_token);
	assert(nested.struct_literal_info.arguments[1].(*Extended.Parser_Literal)._string == fresh_nested.struct_literal_info.arguments[1].(*Extended.Parser_Literal)._string);
	assert_eligible_edit_matches_fresh(*updated, *fresh);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(array_literal.array_literal_info.array_members[0].(*Extended.Parser_Ident).name == "name");
	assert(nested.struct_literal_info.arguments[1].(*Extended.Parser_Literal)._string == "blue");
	assert(Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);

	typed_old := Extended.parse_file("items := u8.[1, 2];");
	typed_new := 			"u8 :: 0; items := u8.[1, 2];";
	typed_updated, typed_ok := Extended.parse_file_edit(*typed_old, 0, 0, typed_new);
	typed_fresh := Extended.parse_file(typed_new);
	assert(typed_ok && typed_updated.status == .COMPLETE && typed_fresh.status == .COMPLETE);
	typed_tokens := Extended.materialise_tokens(typed_new);
	typed_probe := Extended.Parser.{parsed=*typed_tokens, edit_source=*typed_old, cursor=5};
	set_allocators(*typed_tokens.node_pool, context.default_allocator);
	typed_probe.current_scope = Extended.push_lexical_scope(*typed_probe);
	typed_tokens.root = Extended.reuse_simple_declaration(*typed_probe);
	assert(typed_tokens.root && typed_tokens.root.(*Extended.Parser_Declaration).expression.kind == .LITERAL);
	typed_literal := typed_updated.root.(*Extended.Parser_Block).statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Literal);
	typed_original := typed_old.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Literal);
	assert(typed_literal.array_literal_info.element_type != typed_original.array_literal_info.element_type);
	assert(typed_literal.array_literal_info.element_type.type_valued_expression.(*Extended.Parser_Ident).name == "u8");
	assert(typed_literal.array_literal_info.element_type.type_valued_expression.(*Extended.Parser_Ident).resolved_declaration == typed_updated.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Declaration));
	assert(typed_literal.first_token == typed_fresh.root.(*Extended.Parser_Block).statements[1].(*Extended.Parser_Declaration).expression.first_token);
	assert(typed_literal.node_flags == typed_fresh.root.(*Extended.Parser_Block).statements[1].(*Extended.Parser_Declaration).expression.node_flags);
	assert_eligible_edit_matches_fresh(*typed_updated, *typed_fresh);
	Extended.release_parser_tree(*typed_old);
	Extended.release_parser_names(*typed_old);
	Extended.release_parser_tree(*typed_updated);
	Extended.release_parser_names(*typed_updated);
	Extended.release_parser_tree(*typed_fresh);
	Extended.release_parser_names(*typed_fresh);
	Extended.release_parser_tree(*typed_tokens);
	Extended.release_parser_names(*typed_tokens);

	struct_old := Extended.parse_file("item := Thing.{1, 2};");
	struct_new := 		  "Thing :: 0; item := Thing.{1, 2};";
	struct_updated, struct_ok := Extended.parse_file_edit(*struct_old, 0, 0, struct_new);
	struct_fresh := Extended.parse_file(struct_new);
	assert(struct_ok && struct_updated.status == .COMPLETE && struct_fresh.status == .COMPLETE);
	struct_literal := struct_updated.root.(*Extended.Parser_Block).statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Literal);
	struct_original := struct_old.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Literal);
	assert(struct_literal.struct_literal_info.type_expression != struct_original.struct_literal_info.type_expression);
	assert(
		struct_literal.struct_literal_info.type_expression.type_valued_expression.(*Extended.Parser_Ident).resolved_declaration
		== struct_updated.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Declaration)
	);
	assert(struct_literal.first_token == struct_fresh.root.(*Extended.Parser_Block).statements[1].(*Extended.Parser_Declaration).expression.first_token);
	assert(struct_literal.node_flags == struct_fresh.root.(*Extended.Parser_Block).statements[1].(*Extended.Parser_Declaration).expression.node_flags);
	assert_eligible_edit_matches_fresh(*struct_updated, *struct_fresh);
	Extended.release_parser_tree(*struct_old);
	Extended.release_parser_names(*struct_old);
	Extended.release_parser_tree(*struct_updated);
	Extended.release_parser_names(*struct_updated);
	Extended.release_parser_tree(*struct_fresh);
	Extended.release_parser_names(*struct_fresh);
}

test_nested_block_ast_reuse :: () {
	old_source := copy_string("#if true { use := later; later :: 2; }\nouter :: 1;");
	new_source := copy_string("#if true { added :: 3; use := later; later :: 2; }\nouter :: 1;");
	edit_start := "#if true { ".count;
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, edit_start, edit_start, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && updated.status == .COMPLETE && fresh.status == .COMPLETE);

	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, edit_start=edit_start, edit_end=edit_start, cursor=9};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.reuse_block = Extended.find_old_declaration_block(*probe, old.root_scope, 3, .DATA_DECLARATIONS);
	assert(probe.reuse_block != null);
	assert(Extended.find_old_declaration_block(*probe, old.root_scope, 3, .IMPERATIVE) == null);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root && probe_tokens.root.(*Extended.Parser_Declaration).name == "use");
	assert(probe.current_scope.references.count == 1);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);

	updated_block := updated.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_If).then_block;
	fresh_block := fresh.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_If).then_block;
	assert(updated_block.kind == fresh_block.kind && updated_block.node_flags == fresh_block.node_flags && updated_block.block_type == fresh_block.block_type);
	assert(updated_block.statements.count == fresh_block.statements.count && updated_block.statements.count == 3);
	assert(updated_block.first_token == fresh_block.first_token && updated_block.one_past_last_token == fresh_block.one_past_last_token);
	assert(updated_block.l0 == fresh_block.l0 && updated_block.c0 == fresh_block.c0 && updated_block.l1 == fresh_block.l1 && updated_block.c1 == fresh_block.c1);
	for updated_block.statements {
		other := fresh_block.statements[it_index];
		assert(it.kind == other.kind && it.node_flags == other.node_flags);
		assert(it.first_token == other.first_token && it.one_past_last_token == other.one_past_last_token);
		assert(it.l0 == other.l0 && it.c0 == other.c0 && it.l1 == other.l1 && it.c1 == other.c1);
	}

	use := updated_block.statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident);
	fresh_use := fresh_block.statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident);
	assert(use.node_flags == fresh_use.node_flags && use.flags == fresh_use.flags);
	assert(use.first_token == fresh_use.first_token && use.one_past_last_token == fresh_use.one_past_last_token);
	assert(use.resolved_declaration == updated_block.statements[2].(*Extended.Parser_Declaration));
	assert(fresh_use.resolved_declaration == fresh_block.statements[2].(*Extended.Parser_Declaration));
	assert(updated.tokens.count == fresh.tokens.count);
	for updated.tokens {
		other := fresh.tokens[it_index];
		assert(it.type == other.type && it.value_flags == other.value_flags);
		assert(it.byte_start == other.byte_start && it.byte_end == other.byte_end && it.preceding_trivia_byte_start == other.preceding_trivia_byte_start);
		assert(it.l0 == other.l0 && it.c0 == other.c0 && it.l1 == other.l1 && it.c1 == other.c1);
		assert(it.original_text == other.original_text && it.preceding_trivia == other.preceding_trivia && it.trailing_trivia == other.trailing_trivia);
	}

	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.recovery_records.count == fresh.recovery_records.count);
	assert(updated.restart_points.count == fresh.restart_points.count);
	for updated.restart_points {
		other := fresh.restart_points[it_index];
		assert(it.kind == other.kind && it.span.first == other.span.first && it.span.one_past_last == other.span.one_past_last);
	}

	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	for updated.tokens {
		other := fresh.tokens[it_index];
		assert(it.original_text == other.original_text && it.preceding_trivia == other.preceding_trivia && it.trailing_trivia == other.trailing_trivia);
	}

	assert(use.name == "later" && Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);

	brace_source := "#if true { a :: 1; }";
	brace_old := Extended.parse_file(brace_source);
	brace_at := "#if true ".count;
	brace_updated, brace_ok := Extended.parse_file_edit(*brace_old, brace_at, brace_at + 1, brace_source);
	assert(brace_ok && brace_updated.status == .COMPLETE);
	brace_probe := Extended.Parser.{parsed=*brace_updated, edit_source=*brace_old, edit_start=brace_at, edit_end=brace_at + 1};
	assert(Extended.find_old_declaration_block(*brace_probe, brace_old.root_scope, 3, .DATA_DECLARATIONS) == null);
	assert(brace_updated.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_If).then_block.statements.count == 1);
	Extended.release_parser_tree(*brace_old);
	Extended.release_parser_names(*brace_old);
	Extended.release_parser_tree(*brace_updated);
	Extended.release_parser_names(*brace_updated);
}

test_nested_block_scope_reuse :: () {
	old_source := copy_string("#if true { #if true { use := outer; } outer :: 1; }");
	new_source := copy_string("#if true { added :: 3; #if true { use := outer; } outer :: 1; }");
	edit_start := "#if true { ".count;
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, edit_start, edit_start, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && updated.status == .COMPLETE && fresh.status == .COMPLETE);

	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, edit_start=edit_start, edit_end=edit_start, cursor=13};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.reuse_block = Extended.find_old_declaration_block(*probe, old.root_scope, 12, .DATA_DECLARATIONS);
	assert(probe.reuse_block != null);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root && probe_tokens.root.(*Extended.Parser_Declaration).name == "use");
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);

	outer_block := updated.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_If).then_block;
	fresh_outer := fresh.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_If).then_block;
	inner := outer_block.statements[1].(*Extended.Parser_If).then_block;
	fresh_inner := fresh_outer.statements[1].(*Extended.Parser_If).then_block;
	assert(inner.first_token == fresh_inner.first_token && inner.one_past_last_token == fresh_inner.one_past_last_token);
	assert(inner.statements[0].first_token == fresh_inner.statements[0].first_token);
	use := inner.statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident);
	assert(use.resolved_declaration == outer_block.statements[2].(*Extended.Parser_Declaration));
	assert(fresh_inner.statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == fresh_outer.statements[2].(*Extended.Parser_Declaration));
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(use.name == "outer" && Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);

	boundary_source := copy_string("#if true { #if true { use := target; } target :: 1; }");
	boundary_old := Extended.parse_file(boundary_source);
	outer_at := "#if true ".count;
	boundary_updated, boundary_ok := Extended.parse_file_edit(*boundary_old, outer_at, outer_at + 1, boundary_source);
	boundary_fresh := Extended.parse_file(boundary_source);
	assert(boundary_ok && boundary_updated.status == .COMPLETE && boundary_fresh.status == .COMPLETE);
	boundary_tokens := Extended.materialise_tokens(boundary_source);
	boundary_probe := Extended.Parser.{parsed=*boundary_tokens, edit_source=*boundary_old, edit_start=outer_at, edit_end=outer_at + 1};
	set_allocators(*boundary_tokens.node_pool, context.default_allocator);
	boundary_probe.current_scope = Extended.push_lexical_scope(*boundary_probe);
	old_outer := boundary_old.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_If).then_block;
	old_inner := old_outer.statements[0].(*Extended.Parser_If).then_block;
	assert(Extended.find_old_declaration_block(*boundary_probe, boundary_old.root_scope, old_outer.first_token.(s64), .DATA_DECLARATIONS) == null);
	assert(Extended.find_old_declaration_block(*boundary_probe, boundary_old.root_scope, old_inner.first_token.(s64), .DATA_DECLARATIONS) == null);
	boundary_block := boundary_updated.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_If).then_block;
	boundary_fresh_block := boundary_fresh.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_If).then_block;
	assert(boundary_block.statements[0].(*Extended.Parser_If).then_block.statements[0].first_token == boundary_fresh_block.statements[0].(*Extended.Parser_If).then_block.statements[0].first_token);
	assert(boundary_updated.diagnostics.count == boundary_fresh.diagnostics.count && boundary_updated.restart_points.count == boundary_fresh.restart_points.count);
	Extended.release_parser_tree(*boundary_tokens);
	Extended.release_parser_names(*boundary_tokens);
	Extended.release_parser_tree(*boundary_old);
	Extended.release_parser_names(*boundary_old);
	assert(Extended.reconstruct_source(*boundary_updated) == boundary_source);
	Extended.release_parser_tree(*boundary_updated);
	Extended.release_parser_names(*boundary_updated);
	Extended.release_parser_tree(*boundary_fresh);
	Extended.release_parser_names(*boundary_fresh);
	free(boundary_source);
}

test_indentation_only_ast_reuse :: () {
	check_indentation_only_ast_reuse(
		"#if true {\n    use := target;\n    target :: 1;\n}",
		"#if true {\n        use := target;\n    target :: 1;\n}",
		4
	);
	check_indentation_only_ast_reuse(
		"#if true {\n        use := target;\n    target :: 1;\n}",
		"#if true {\n    use := target;\n    target :: 1;\n}",
		8
	);
}

check_indentation_only_ast_reuse :: (before: string, after: string, old_indent_length: s64) {
	old_source := copy_string(before);
	new_source := copy_string(after);
	edit_start := "#if true {\n".count;
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, edit_start, edit_start + old_indent_length, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE && fresh.status == .COMPLETE);

	old_block := old.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_If).then_block;
	block := updated.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_If).then_block;
	fresh_block := fresh.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_If).then_block;
	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, edit_start=edit_start, edit_end=edit_start + old_indent_length, cursor=block.statements[0].first_token.(s64)};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.reuse_block = Extended.find_old_declaration_block(*probe, old.root_scope, block.first_token.(s64), .DATA_DECLARATIONS);
	assert(probe.reuse_block == old_block);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root && probe_tokens.root.(*Extended.Parser_Declaration).name == "use");
	probe.cursor = block.statements[1].first_token.(s64);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root && probe_tokens.root.(*Extended.Parser_Declaration).name == "target");
	assert(probe.current_scope.references.count == 1 && probe.current_scope.bindings.count == 2);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);

	assert(block.first_token == fresh_block.first_token && block.one_past_last_token == fresh_block.one_past_last_token);
	for block.statements {
		other := fresh_block.statements[it_index];
		assert(it.first_token == other.first_token && it.one_past_last_token == other.one_past_last_token);
		assert(it.l0 == other.l0 && it.c0 == other.c0 && it.l1 == other.l1 && it.c1 == other.c1);
	}

	use := block.statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident);
	fresh_use := fresh_block.statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident);
	assert(use.first_token == fresh_use.first_token && use.one_past_last_token == fresh_use.one_past_last_token);
	assert(use.l0 == fresh_use.l0 && use.c0 == fresh_use.c0 && use.l1 == fresh_use.l1 && use.c1 == fresh_use.c1);
	assert(use.resolved_declaration == block.statements[1].(*Extended.Parser_Declaration));
	assert(fresh_use.resolved_declaration == fresh_block.statements[1].(*Extended.Parser_Declaration));
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(use.name == "target" && Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);
}

test_nested_shadowing_ast_reuse :: () {
	old_source := copy_string("#if true { target :: 1; #if true { use := target; } }");
	new_source := copy_string("#if true { target :: 1; #if true { target :: 2; use := target; } }");
	edit_start := "#if true { target :: 1; #if true { ".count;
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, edit_start, edit_start, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && updated.status == .COMPLETE && fresh.status == .COMPLETE);

	old_outer := old.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_If).then_block;
	old_inner := old_outer.statements[1].(*Extended.Parser_If).then_block;
	outer := updated.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_If).then_block;
	inner := outer.statements[1].(*Extended.Parser_If).then_block;
	fresh_outer := fresh.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_If).then_block;
	fresh_inner := fresh_outer.statements[1].(*Extended.Parser_If).then_block;
	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, edit_start=edit_start, edit_end=edit_start, cursor=inner.statements[1].first_token.(s64), reuse_block=old_inner};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root && probe_tokens.root.(*Extended.Parser_Declaration).name == "use");
	assert(probe.current_scope.references.count == 1);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);

	assert(inner.statements[1].first_token == fresh_inner.statements[1].first_token);
	use := inner.statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident);
	fresh_use := fresh_inner.statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident);
	assert(use.resolved_declaration == inner.statements[0].(*Extended.Parser_Declaration));
	assert(fresh_use.resolved_declaration == fresh_inner.statements[0].(*Extended.Parser_Declaration));
	assert(use.resolved_declaration != outer.statements[0].(*Extended.Parser_Declaration));
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(use.name == "target" && Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);
}

test_dependency_forward_binding_edit :: () {
	check_dependency_declaration_edit(
					"target :: 1; use := target;",
		"other :: 0; target :: 1; use := target;",
		0,
		0,
		1
	);
	check_dependency_declaration_edit(
		"target :: 1; use := target;",
					 "use := target;",
		0,
		"target :: 1; ".count,
		-1
	);
	check_dependency_declaration_edit(
		"target :: 1; use := target;",
		 "other :: 1; use := target;",
		0,
		"target".count,
		-1
	);
	check_dependency_declaration_edit(
					 "other :: 0; target :: 1; use := target;",
		"target :: 1; other :: 0; use := target;",
		0,
		"other :: 0; target :: 1; ".count,
		0
	);

	test_import_dependency_edit();
	test_using_dependency_edit();
	test_dependency_scope_move();

	old_source := copy_string("use := target; keep := use;");
	new_source := copy_string("use := target; target :: 1; keep := use;");
	edit_start := "use := target; ".count;
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, edit_start, edit_start, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE && fresh.status == .COMPLETE);
	old_statements := old.root.(*Extended.Parser_Block).statements;
	assert(old_statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == null);
	statements := updated.root.(*Extended.Parser_Block).statements;
	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, edit_start=edit_start, edit_end=edit_start, cursor=statements[0].first_token.(s64)};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root && probe_tokens.root.(*Extended.Parser_Declaration).name == "use");
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);
	use := statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident);
	assert(use.resolved_declaration == statements[1].(*Extended.Parser_Declaration));
	assert(fresh_statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[1].(*Extended.Parser_Declaration));
	assert(statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == statements[0].(*Extended.Parser_Declaration));
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(use.name == "target" && Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);
}

test_import_dependency_edit :: () {
	old_source := copy_string("Basic :: #import \"Basic\"; use := Basic;");
	new_source := copy_string("Basic :: #import \"String\"; use := Basic;");
	edit_start := "Basic :: #import \"".count;
	edit_end := "Basic :: #import \"Basic".count;
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, edit_start, edit_end, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE && fresh.status == .COMPLETE);
	statements := updated.root.(*Extended.Parser_Block).statements;
	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, edit_start=edit_start, edit_end=edit_end};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	assert(Extended.reuse_simple_declaration(*probe) == null);
	probe.cursor = statements[1].first_token.(s64);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root && probe_tokens.root.(*Extended.Parser_Declaration).name == "use");
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);
	import_decl := statements[0].(*Extended.Parser_Declaration);
	fresh_import := fresh_statements[0].(*Extended.Parser_Declaration);
	assert(import_decl.expression.(*Extended.Parser_Directive_Import).name == "String");
	assert(import_decl.expression.(*Extended.Parser_Directive_Import).name == fresh_import.expression.(*Extended.Parser_Directive_Import).name);
	use := statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident);
	assert(use.resolved_declaration == import_decl && use.resolved_declaration != old.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Declaration));
	assert(fresh_statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == fresh_import);
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(use.name == "Basic" && Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);
}

test_using_dependency_edit :: () {
	old_source := copy_string("State :: struct { member: s64; }; using global: State; keep := global;");
	new_source := copy_string("Other :: struct { member: s64; }; using global: State; keep := global;");
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, 0, "State".count, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE && fresh.status == .COMPLETE);
	statements := updated.root.(*Extended.Parser_Block).statements;
	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	old_using := old.root.(*Extended.Parser_Block).statements[1].(*Extended.Parser_Using);
	assert(
		old_using.expression.(*Extended.Parser_Declaration).type_inst.type_valued_expression.(*Extended.Parser_Ident).resolved_declaration
		== old.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Declaration)
	);
	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, edit_start=0, edit_end="State".count, cursor=statements[1].first_token.(s64)};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	assert(Extended.reuse_simple_declaration(*probe) == null);
	probe.cursor = statements[2].first_token.(s64);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root && probe_tokens.root.(*Extended.Parser_Declaration).name == "keep");
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);
	using_node := statements[1].(*Extended.Parser_Using);
	using_decl := using_node.expression.(*Extended.Parser_Declaration);
	using_type := using_decl.type_inst.type_valued_expression.(*Extended.Parser_Ident);
	assert(using_type.resolved_declaration == null);
	assert(fresh_statements[1].(*Extended.Parser_Using).expression.(*Extended.Parser_Declaration).type_inst.type_valued_expression.(*Extended.Parser_Ident).resolved_declaration == null);
	assert(using_node != old_using && using_decl != old_using.expression.(*Extended.Parser_Declaration));
	assert(using_node.first_token == fresh_statements[1].first_token && using_node.one_past_last_token == fresh_statements[1].one_past_last_token);
	assert(statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == using_decl);
	assert(fresh_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[1].(*Extended.Parser_Using).expression.(*Extended.Parser_Declaration));
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(using_type.name == "State" && Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);
}

test_dependency_scope_move :: () {
	old_source := copy_string("#if true { target :: 1; } use := target;");
	new_source := copy_string("target :: 1; #if true { } use := target;");
	edit_end := "#if true { target :: 1; } ".count;
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, 0, edit_end, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE && fresh.status == .COMPLETE);
	old_statements := old.root.(*Extended.Parser_Block).statements;
	assert(old_statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == null);
	statements := updated.root.(*Extended.Parser_Block).statements;
	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, edit_start=0, edit_end=edit_end, cursor=statements[2].first_token.(s64)};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root && probe_tokens.root.(*Extended.Parser_Declaration).name == "use");
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);
	use := statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident);
	assert(use.resolved_declaration == statements[0].(*Extended.Parser_Declaration));
	assert(fresh_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == fresh_statements[0].(*Extended.Parser_Declaration));
	assert(statements[1].(*Extended.Parser_If).then_block.statements.count == 0);
	assert(fresh_statements[1].(*Extended.Parser_If).then_block.statements.count == 0);
	assert(use.resolved_declaration != old_statements[0].(*Extended.Parser_If).then_block.statements[0].(*Extended.Parser_Declaration));
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(use.name == "target" && Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);
}

check_dependency_declaration_edit :: (before: string, after: string, edit_start: s64, edit_end: s64, target_index: s64) {
	old_source := copy_string(before);
	new_source := copy_string(after);
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, edit_start, edit_end, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE && fresh.status == .COMPLETE);
	statements := updated.root.(*Extended.Parser_Block).statements;
	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	use := statements[statements.count - 1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident);
	fresh_use := fresh_statements[fresh_statements.count - 1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident);
	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, edit_start=edit_start, edit_end=edit_end, cursor=statements[statements.count - 1].first_token.(s64)};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root && probe_tokens.root.(*Extended.Parser_Declaration).name == "use");
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);
	if target_index >= 0 {
		assert(use.resolved_declaration == statements[target_index].(*Extended.Parser_Declaration));
		assert(fresh_use.resolved_declaration == fresh_statements[target_index].(*Extended.Parser_Declaration));
	} else {
		assert(use.resolved_declaration == null && fresh_use.resolved_declaration == null);
	}

	assert(use.resolved_declaration != old.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Declaration));
	assert(statements.count == fresh_statements.count);
	for statements {
		other := fresh_statements[it_index];
		assert(it.kind == other.kind && it.first_token == other.first_token && it.one_past_last_token == other.one_past_last_token);
	}

	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(use.name == "target" && Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);
}

test_moved_closing_brace_ast_reuse :: () {
	old_source := copy_string("#if true { use := outer; } outer :: 1;");
	new_source := copy_string("#if true { use := outer; outer :: 1; }");
	edit_start := "#if true { use := outer; ".count;
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, edit_start, old_source.count, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE && fresh.status == .COMPLETE);

	old_statements := old.root.(*Extended.Parser_Block).statements;
	old_block := old_statements[0].(*Extended.Parser_If).then_block;
	assert(old_block.statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == old_statements[1].(*Extended.Parser_Declaration));
	block := updated.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_If).then_block;
	fresh_block := fresh.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_If).then_block;
	assert(block.statements.count == 2 && fresh_block.statements.count == 2);
	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, edit_start=edit_start, edit_end=old_source.count, cursor=block.statements[0].first_token.(s64)};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.reuse_block = Extended.find_old_declaration_block(*probe, old.root_scope, block.first_token.(s64), .DATA_DECLARATIONS);
	assert(probe.reuse_block == null);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	assert(Extended.reuse_simple_declaration(*probe) == null);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);

	use := block.statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident);
	fresh_use := fresh_block.statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident);
	assert(use.resolved_declaration == block.statements[1].(*Extended.Parser_Declaration));
	assert(fresh_use.resolved_declaration == fresh_block.statements[1].(*Extended.Parser_Declaration));
	assert(block.first_token == fresh_block.first_token && block.one_past_last_token == fresh_block.one_past_last_token);
	for block.statements {
		other := fresh_block.statements[it_index];
		assert(it.first_token == other.first_token && it.one_past_last_token == other.one_past_last_token);
	}

	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(use.name == "outer" && Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);
}

test_default_edit_fallback :: () {
	old := Default.parse_file("a :: 1; @tag");
	updated, ok := Default.parse_file_edit(*old, 0, 0, "b :: 2; a :: 1; @tag");
	fresh := Default.parse_file("b :: 2; a :: 1; @tag");
	assert(ok && updated.status == .COMPLETE && fresh.status == .COMPLETE);
	assert(updated.root.(*Default.Parser_Block).statements.count == fresh.root.(*Default.Parser_Block).statements.count);
	assert(updated.diagnostics.count == fresh.diagnostics.count);
	assert(updated.restart_points.count == fresh.restart_points.count);
	Default.release_parser_tree(*old);
	Default.release_parser_tree(*updated);
	Default.release_parser_tree(*fresh);

	compound_old := Default.parse_file("a, b :: 1; @tag");
	compound_updated, compound_ok := Default.parse_file_edit(*compound_old, 0, 0, "prefix :: 2; a, b :: 1; @tag");
	compound_fresh := Default.parse_file("prefix :: 2; a, b :: 1; @tag");
	assert(compound_ok && compound_updated.status == .COMPLETE && compound_fresh.status == .COMPLETE);
	assert(compound_updated.root.(*Default.Parser_Block).statements[1].kind == .COMPOUND_DECLARATION);
	assert(compound_updated.restart_points.count == compound_fresh.restart_points.count);
	for compound_updated.restart_points {
		other := compound_fresh.restart_points[it_index];
		assert(it.kind == other.kind && it.span.first == other.span.first && it.span.one_past_last == other.span.one_past_last);
	}

	Default.release_parser_tree(*compound_old);
	Default.release_parser_tree(*compound_updated);
	Default.release_parser_tree(*compound_fresh);

	import_before := copy_string("Basic :: #import \"Basic\"; use := Basic;");
	import_after := copy_string("Basic :: #import \"String\"; use := Basic;");
	import_start := "Basic :: #import \"".count;
	import_old := Default.parse_file(import_before);
	import_updated, import_ok := Default.parse_file_edit(*import_old, import_start, import_start + "Basic".count, import_after);
	import_fresh := Default.parse_file(import_after);
	assert(import_ok && import_old.status == .COMPLETE && import_updated.status == .COMPLETE && import_fresh.status == .COMPLETE);
	probe_tokens := Default.materialise_tokens(import_after);
	probe := Default.Parser.{parsed=*probe_tokens, edit_source=*import_old, edit_start=import_start, edit_end=import_start + "Basic".count};
	assert(Default.reuse_simple_declaration(*probe) == null);
	Default.release_parser_tree(*probe_tokens);
	assert(import_updated.tokens.count == import_fresh.tokens.count);
	for import_updated.tokens {
		other := import_fresh.tokens[it_index];
		assert(it.type == other.type && it.l0 == other.l0 && it.c0 == other.c0);
	}

	import_statements := import_updated.root.(*Default.Parser_Block).statements;
	import_fresh_statements := import_fresh.root.(*Default.Parser_Block).statements;
	import_decl := import_statements[0].(*Default.Parser_Declaration);
	assert(import_decl.expression.(*Default.Parser_Directive_Import).name == "String");
	assert(import_decl.expression.(*Default.Parser_Directive_Import).name == import_fresh_statements[0].(*Default.Parser_Declaration).expression.(*Default.Parser_Directive_Import).name);
	use := import_statements[1].(*Default.Parser_Declaration).expression.(*Default.Parser_Ident);
	assert(use.resolved_declaration == import_decl && use.resolved_declaration != import_old.root.(*Default.Parser_Block).statements[0].(*Default.Parser_Declaration));
	assert(import_fresh_statements[1].(*Default.Parser_Declaration).expression.(*Default.Parser_Ident).resolved_declaration == import_fresh_statements[0].(*Default.Parser_Declaration));
	assert(import_updated.diagnostics.count == import_fresh.diagnostics.count && import_updated.restart_points.count == import_fresh.restart_points.count);
	Default.release_parser_tree(*import_old);
	free(import_before);
	assert(use.name == "Basic");
	Default.release_parser_tree(*import_updated);
	Default.release_parser_tree(*import_fresh);
	free(import_after);
}

check_regional_lex :: (old_source: string, new_source: string, start: s64, end: s64) {
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, start, end, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && updated.status == fresh.status);
	assert(updated.tokens.count == fresh.tokens.count);
	assert(updated.diagnostics.count == fresh.diagnostics.count);
	assert(updated.recovery_records.count == fresh.recovery_records.count);
	assert(updated.restart_points.count == fresh.restart_points.count);

	for updated.tokens {
		other := fresh.tokens[it_index];
		assert(it.type == other.type && it.value_flags == other.value_flags);
		assert(it.original_text == other.original_text && it.preceding_trivia == other.preceding_trivia && it.trailing_trivia == other.trailing_trivia);
		assert(it.byte_start == other.byte_start && it.byte_end == other.byte_end && it.preceding_trivia_byte_start == other.preceding_trivia_byte_start);
		assert(it.l0 == other.l0 && it.c0 == other.c0 && it.l1 == other.l1 && it.c1 == other.c1);
		if it.type == .IDENT || it.type == .NOTE || (it.type >= .__FIRST_KEYWORD && it.type <= .__LAST_KEYWORD) {
			assert(it.ident_value.name == other.ident_value.name);
		} else if it.type == .STRING {
			assert(it.string_value == other.string_value);
		}
	}

	for updated.diagnostics {
		other := fresh.diagnostics[it_index];
		assert(it.kind == other.kind && it.message == other.message);
		assert(it.span.first == other.span.first && it.span.one_past_last == other.span.one_past_last);
		assert(it.lexer_line == other.lexer_line && it.lexer_column == other.lexer_column);
	}

	assert(Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	assert(Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
}

test_recovery_synchronization :: () {
	parsed := Extended.materialise_tokens("bad + value; next } tail");
	parser := Extended.Parser.{parsed=*parsed, cursor=1};

	expression_span := Extended.parser_synchronise(*parser, .EXPRESSION);
	assert(expression_span.first == xx 1);
	assert(expression_span.one_past_last == xx 3);
	assert(parsed.recovery_records.count == 1);
	assert(parsed.recovery_records[0].kind == .SKIPPED_TOKENS);
	assert(parsed.recovery_records[0].diagnostic_index == -1);
	assert(parsed.recovery_records[0].span.first == expression_span.first);
	assert(parsed.recovery_records[0].span.one_past_last == expression_span.one_past_last);
	assert(Extended.parser_peek(*parser).type == #char ";");

	nested_parsed := Extended.materialise_tokens("bad(inner; still_inner); next");
	nested_parser := Extended.Parser.{parsed=*nested_parsed};
	Extended.parser_synchronise(*nested_parser, .EXPRESSION);
	assert(nested_parser.cursor == 6);
	assert(Extended.parser_peek(*nested_parser).type == #char ";");

	guard := Extended.parser_progress_guard(*parser);
	assert(Extended.parser_ensure_progress(*parser, guard));
	assert(parser.cursor == 4);
	assert(parsed.recovery_records.count == 2);
	assert(parsed.recovery_records[1].span.first == xx 3);
	assert(parsed.recovery_records[1].span.one_past_last == xx 4);

	statement_span := Extended.parser_synchronise(*parser, .STATEMENT);
	declaration_span := Extended.parser_synchronise(*parser, .DECLARATION);
	assert(statement_span.first == statement_span.one_past_last);
	assert(declaration_span.first == declaration_span.one_past_last);

	block_span := Extended.parser_synchronise(*parser, .BLOCK);
	assert(block_span.first == xx 4);
	assert(block_span.one_past_last == xx 5);
	assert(parsed.recovery_records.count == 3);
	assert(parsed.recovery_records[2].span.first == block_span.first);
	assert(parsed.recovery_records[2].span.one_past_last == block_span.one_past_last);
	assert(Extended.parser_peek(*parser).type == #char "}");

	Extended.parser_eat(*parser);
	Extended.parser_eat(*parser);
	guard = Extended.parser_progress_guard(*parser);
	assert(!Extended.parser_ensure_progress(*parser, guard));
}

test_complete_file_parsing :: () {
	SOURCE :: #string JAI
first :: 1;
second: s64 = 2;
typed_constant: s64 : 3;
#scope_file
main :: () {
	value := cast,no_check(s32) 1;
}
third := 3;
JAI;
	parsed := Extended.parse_file(SOURCE, "fixture.jai");
	root := parsed.root.(*Extended.Parser_Block);
	if parsed.status != .COMPLETE {
		diagnostic := parsed.diagnostics[0];
		diagnostic_token := Extended.token_at(*parsed, diagnostic.span.first);
		assert(
			false,
			"Status %, diagnostics %, kind %, expected %, actual %, token '%'.",
			parsed.status,
			parsed.diagnostics.count,
			diagnostic.kind,
			diagnostic.expected_token,
			diagnostic.actual_token,
			diagnostic_token.original_text,
		);
	}

	assert(parsed.fully_pathed_filename == "fixture.jai");
	assert(root.block_type == .DATA_DECLARATIONS);
	assert(!(root.node_flags & .IS_PARENTHESIZED));
	assert(root.statements.count == 6);
	assert((root.statements[2].(*Extended.Parser_Declaration).flags & .IS_CONSTANT) != 0);
	assert(Extended.reconstruct_source(*parsed) == SOURCE);

	NO_RESET_SOURCE :: #string JAI
#no_reset x1: int;
#no_reset x2: int;
after :: 1;
JAI;
	no_reset := Extended.parse_file(NO_RESET_SOURCE);
	assert(no_reset.status == .COMPLETE);
	no_reset_statements := no_reset.root.(*Extended.Parser_Block).statements;
	assert(no_reset_statements.count == 3);
	assert((no_reset_statements[0].(*Extended.Parser_Declaration).flags & .NO_RESET) != 0);
	assert((no_reset_statements[1].(*Extended.Parser_Declaration).flags & .NO_RESET) != 0);
	assert((no_reset_statements[2].(*Extended.Parser_Declaration).flags & .NO_RESET) == 0);
	assert(Extended.reconstruct_source(*no_reset) == NO_RESET_SOURCE);
	malformed_no_reset := Extended.parse_file("#no_reset x: ;\nafter :: 1;");
	assert(malformed_no_reset.status == .RECOVERED);
	assert(malformed_no_reset.root.(*Extended.Parser_Block).statements[1].(*Extended.Parser_Declaration).name == "after");
	assert(Extended.parse_file("#no_reset").status == .INCOMPLETE);
	assert(Extended.parse_file("#no_reset #scope_file\nafter :: 1;").status == .RECOVERED);

	recovered := Extended.parse_file("first :: 1;\nbad: ;\nsecond :: 2;\nworse := ;\nthird :: 3;");
	recovered_root := recovered.root.(*Extended.Parser_Block);
	assert(recovered.status == .RECOVERED);
	assert(recovered.diagnostics.count == 2);
	assert(recovered_root.statements.count == 5);

	truncated := Extended.parse_file("first :: 1;\nsecond :: struct { value: s64;");
	truncated_root := truncated.root.(*Extended.Parser_Block);
	assert(truncated.status == .INCOMPLETE);
	assert(truncated_root.statements.count == 2);
	assert(truncated_root.statements[1].kind == .DECLARATION);

	empty := Extended.parse_file("", "empty.jai");
	empty_root := empty.root.(*Extended.Parser_Block);
	assert(empty.status == .COMPLETE);
	assert(empty_root.statements.count == 0);
	assert(empty_root.first_token == empty_root.one_past_last_token);

	TERMINATORS_SOURCE :: #string JAI
normal :: () { }
after_normal :: 1;
quick_block :: () => { }
#scope_file
quick_expression :: value => value + 1;
Record :: struct { }
after_struct :: 2;
Choice :: enum {
	ONLY;
}
outer :: () {
	nested :: () { }
	next := 3;
	Nested_Record :: struct { }
	Nested_Choice :: enum {
		ONLY;
	}
}
final :: () { }
JAI;
	terminators := Extended.parse_file(TERMINATORS_SOURCE);
	terminators_root := terminators.root.(*Extended.Parser_Block);
	assert(terminators.status == .COMPLETE);
	assert(terminators.diagnostics.count == 0);
	assert(terminators_root.statements.count == 10);
	outer := terminators_root.statements[8].(*Extended.Parser_Declaration);
	outer_block := outer.expression.(*Extended.Parser_Procedure_Header).body_or_null.block;
	assert(outer_block.statements.count == 4);
}

test_node_token_spans :: () {
	ident := New(Extended.Parser_Ident);
	ident.kind = .IDENT;
	ident.name = "left";
	ident.first_token = xx 0;
	ident.one_past_last_token = xx 1;

	literal := New(Extended.Parser_Literal);
	literal.kind = .LITERAL;

	binary := New(Extended.Parser_Binary_Operator);
	binary.kind = .BINARY_OPERATOR;
	binary.left = ident;
	binary.right = literal;
	binary.first_token = xx 0;
	binary.one_past_last_token = xx 3;

	block := New(Extended.Parser_Block);
	block.kind = .BLOCK;
	statements: [1] *Extended.Parser_Node = .[binary.(*Extended.Parser_Node)];
	block.statements = array_copy(statements);
	block.first_token = xx 0;
	block.one_past_last_token = xx 3;

	assert(ident.first_token == xx 0);
	assert(ident.one_past_last_token == xx 1);
	assert(block.statements[0].first_token == xx 0);
	assert(block.statements[0].one_past_last_token == xx 3);
}

test_assembly_node_model :: () {
	unknown_mnemonic: Extended.Parser_Ident;
	unknown_mnemonic.name = "future_instruction";
	unknown_register_class: Extended.Parser_Ident;
	unknown_register_class.name = "future_register_class";
	register_name: Extended.Parser_Ident;
	register_name.name = "destination";

	pinning: Extended.Parser_Asm_Register_Pinning;
	pinning.source.span = .{first=xx 1, one_past_last=xx 2};
	pinning.target.span = .{first=xx 4, one_past_last=xx 5};

	declaration: Extended.Parser_Asm_Register_Declaration;
	declaration.name = *register_name;
	declaration.register_class = *unknown_register_class;
	declaration.pinning = *pinning;

	memory: Extended.Parser_Asm_Memory_Operand;
	memory.base.span = .{first=xx 7, one_past_last=xx 8};
	memory.index.span = .{first=xx 9, one_past_last=xx 10};
	memory.scale.span = .{first=xx 11, one_past_last=xx 12};
	memory.displacement.span = .{first=xx 13, one_past_last=xx 14};

	modifier: Extended.Parser_Asm_Operand_Modifier;
	modifier.kind = .AMPERSAND_STAR;
	modifier.span = .{first=xx 15, one_past_last=xx 18};

	operand: Extended.Parser_Asm_Operand;
	operand.kind = .MEMORY;
	operand.memory = *memory;
	operand.modifiers = (*Extended.Parser_Asm_Operand_Modifier).[*modifier];

	instruction: Extended.Parser_Asm_Instruction;
	instruction.mnemonic = *unknown_mnemonic;
	instruction.operands = (*Extended.Parser_Asm_Operand).[*operand];

	statement: Extended.Parser_Asm_Statement;
	statement.kind = .INSTRUCTION;
	statement.instruction = *instruction;

	assert(statement.instruction.mnemonic.name == "future_instruction");
	assert(declaration.register_class.name == "future_register_class");
	assert(declaration.pinning.target.span.first == xx 4);
	assert(statement.instruction.operands[0].memory.scale.span.first == xx 11);
	assert(statement.instruction.operands[0].modifiers[0].kind == .AMPERSAND_STAR);
}

test_identifier_expression :: () {
	parsed := Extended.parse_expression("identifier");
	assert(parsed.status == .COMPLETE);
	assert(parsed.root.kind == .IDENT);

	ident := parsed.root.(*Extended.Parser_Ident);
	assert(ident.name == "identifier");
	assert(ident.l0 == 1 && ident.c0 == 1);
	assert(ident.l1 == 1 && ident.c1 == 11);

	assert(parsed.root.first_token == xx 0);
	assert(parsed.root.one_past_last_token == xx 1);
}

test_compiler_identifier_shape :: ($source: string) #expand {
	parsed := Extended.parse_expression(source);
	expected := compiler_node_for_source(source);

	assert(parsed.root.kind == expected.kind);
	assert(parsed.root.(*Extended.Parser_Ident).name == expected.(*Code_Ident).name);
}

test_literal_expressions :: () {
	integer := Extended.parse_expression("42");
	assert(integer.status == .COMPLETE);
	assert(integer.root.(*Extended.Parser_Literal).value_type == .NUMBER);
	assert(integer.root.(*Extended.Parser_Literal)._u64 == 42);

	text := Extended.parse_expression("\"hello\\n\"");
	assert(text.status == .COMPLETE);
	assert(text.root.(*Extended.Parser_Literal).value_type == .STRING);
	assert(text.root.(*Extended.Parser_Literal)._string == "hello\n");

	boolean := Extended.parse_expression("true");
	assert(boolean.status == .COMPLETE);
	assert(boolean.root.(*Extended.Parser_Literal).value_type == .BOOLEAN);
	assert(boolean.root.(*Extended.Parser_Literal)._u64 == 1);

	incomplete := Extended.parse_expression("");
	assert(incomplete.status == .INCOMPLETE);
	assert(incomplete.root == null);
}

test_aggregate_literals :: () {
	untyped_array := Extended.parse_expression(".[1, 2, 3]");
	assert(untyped_array.status == .COMPLETE);
	array_literal := untyped_array.root.(*Extended.Parser_Literal);
	assert(array_literal.value_type == .ARRAY);
	assert((array_literal.array_literal_info.array_literal_flags & .WAS_UNTYPED) != 0);
	assert(array_literal.array_literal_info.array_members.count == 3);
	assert(array_literal.array_literal_info.array_members[2].(*Extended.Parser_Literal)._u64 == 3);

	typed_array := Extended.parse_expression("u8.[1, 2]");
	typed_array_literal := typed_array.root.(*Extended.Parser_Literal);
	assert(typed_array_literal.array_literal_info.element_type.type_valued_expression.(*Extended.Parser_Ident).name == "u8");
	assert((typed_array_literal.array_literal_info.array_literal_flags & .WAS_UNTYPED) == 0);

	untyped_struct := Extended.parse_expression(".{1, 2}");
	struct_literal := untyped_struct.root.(*Extended.Parser_Literal);
	assert(struct_literal.value_type == .STRUCT);
	assert(struct_literal.struct_literal_info.type_expression == null);
	assert(struct_literal.struct_literal_info.arguments.count == 2);

	call_with_struct := Extended.parse_block("{ foo({1, 2, 3}); }");
	assert(call_with_struct.status == .COMPLETE);
	assert(call_with_struct.diagnostics.count == 0);
	call := call_with_struct.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Procedure_Call);
	assert(call.arguments_unsorted.count == 1);
	argument := call.arguments_unsorted[0].expression.(*Extended.Parser_Literal);
	assert(argument.value_type == .STRUCT);
	assert(argument.struct_literal_info.type_expression == null);
	assert(argument.struct_literal_info.arguments.count == 3);
	assert(argument.struct_literal_info.arguments[2].(*Extended.Parser_Literal)._u64 == 3);
	assert(Extended.reconstruct_source(*call_with_struct) == "{ foo({1, 2, 3}); }");

	bare_struct := Extended.parse_expression("{1, 2, 3}");
	assert(bare_struct.status == .COMPLETE);
	assert(bare_struct.root.(*Extended.Parser_Literal).value_type == .STRUCT);

	EXPRESSION_CONTEXTS_SOURCE :: "{ value := {}; items := .[{1, 2}, {3, 4}]; if value == {} { return {}; } }";
	expression_contexts := Extended.parse_block(EXPRESSION_CONTEXTS_SOURCE);
	assert(expression_contexts.status == .COMPLETE);
	assert(expression_contexts.diagnostics.count == 0);
	assert(Extended.reconstruct_source(*expression_contexts) == EXPRESSION_CONTEXTS_SOURCE);

	NESTED_CONDITION_SOURCE :: "{ if values[{1, 2}] { return {}; } }";
	nested_condition := Extended.parse_block(NESTED_CONDITION_SOURCE);
	assert(nested_condition.status == .COMPLETE);
	assert(nested_condition.diagnostics.count == 0);
	assert(Extended.reconstruct_source(*nested_condition) == NESTED_CONDITION_SOURCE);

	EMPTY_SWITCH_SOURCE :: "{ if fruit == {\n    // all cases commented out\n} }";
	empty_switch := Extended.parse_block(EMPTY_SWITCH_SOURCE);
	assert(empty_switch.status == .COMPLETE);
	empty_switch_if := empty_switch.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_If);
	assert((empty_switch_if.if_flags & .IS_SWITCH_STATEMENT) != 0);
	assert(empty_switch_if.then_block.statements.count == 0);
	assert(Extended.reconstruct_source(*empty_switch) == EMPTY_SWITCH_SOURCE);

	INLINE_LITERAL_SOURCE :: "{ if fruit == { /* no cases */ } { return; } }";
	inline_literal := Extended.parse_block(INLINE_LITERAL_SOURCE);
	assert(inline_literal.status == .COMPLETE);
	assert((inline_literal.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_If).if_flags & .IS_SWITCH_STATEMENT) == 0);
	assert(Extended.reconstruct_source(*inline_literal) == INLINE_LITERAL_SOURCE);

	LEADING_LITERAL_CONDITION_SOURCE :: "{ if {1} == {1} { return; } }";
	leading_literal_condition := Extended.parse_block(LEADING_LITERAL_CONDITION_SOURCE);
	assert(leading_literal_condition.status == .COMPLETE);
	assert(leading_literal_condition.diagnostics.count == 0);
	assert(Extended.reconstruct_source(*leading_literal_condition) == LEADING_LITERAL_CONDITION_SOURCE);

	missing_condition_body := Extended.parse_block("{ if value == {} }");
	assert(missing_condition_body.status == .RECOVERED);
	assert((missing_condition_body.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_If).if_flags & .IS_SWITCH_STATEMENT) == 0);
	assert(Extended.reconstruct_source(*missing_condition_body) == "{ if value == {} }");

	typed_struct := Extended.parse_expression("Thing.{1, 2}");
	typed_struct_literal := typed_struct.root.(*Extended.Parser_Literal);
	assert(typed_struct_literal.struct_literal_info.type_expression.type_valued_expression.(*Extended.Parser_Ident).name == "Thing");

	unary_dot := Extended.parse_expression(".member");
	assert(unary_dot.status == .COMPLETE);
	assert(unary_dot.root.(*Extended.Parser_Unary_Operator).operator_type == #char ".");
	assert(unary_dot.root.(*Extended.Parser_Unary_Operator).subexpression.(*Extended.Parser_Ident).name == "member");

	incomplete := Extended.parse_expression(".[1, 2");
	assert(incomplete.status == .INCOMPLETE);
	assert(incomplete.synthetic_tokens.count == 1);
	assert(incomplete.synthetic_tokens[0].token.type == #char "]");
}

test_uninitialized_indicator_and_here_string :: () {
	uninitialized_value := Extended.parse_expression("---");
	assert(uninitialized_value.status == .COMPLETE);
	assert(uninitialized_value.root.kind == .LITERAL);
	assert(uninitialized_value.root.(*Extended.Parser_Literal).value_type == .UNINITIALIZED);
	assert(Extended.reconstruct_source(*uninitialized_value) == "---");

	SOURCE :: "#string END\nbody\nEND";
	here_string := Extended.parse_expression(SOURCE);
	assert(here_string.status == .COMPLETE, "Here-string status %, token count %, diagnostics %.", here_string.status, here_string.tokens.count, here_string.diagnostics.count);
	literal := here_string.root.(*Extended.Parser_Literal);
	assert(literal.value_type == .STRING);
	assert((literal.value_flags & .HERE_STRING) != 0);
	assert(literal._string == "body\n");
	assert(Extended.reconstruct_source(*here_string) == SOURCE);

	CR_SOURCE :: "#string,cr END\nbody\nEND";
	cr_here_string := Extended.parse_expression(CR_SOURCE);
	assert(cr_here_string.status == .COMPLETE);
	assert(cr_here_string.root.(*Extended.Parser_Literal)._string == "body\r\n");
	assert(Extended.reconstruct_source(*cr_here_string) == CR_SOURCE);

	PERCENT_SOURCE :: "#string,\\% END\n%\\%\nEND";
	percent_here_string := Extended.parse_expression(PERCENT_SOURCE);
	assert(percent_here_string.status == .COMPLETE);
	percent_value := percent_here_string.root.(*Extended.Parser_Literal)._string;
	assert(percent_value.count == 3);
	assert(percent_value[0] == #char "%");
	assert(percent_value[1] == 31);
	assert(percent_value[2] == #char "\n");
	assert(percent_value == COMPILER_PERCENT_HERE_STRING);
	assert(Extended.reconstruct_source(*percent_here_string) == PERCENT_SOURCE);

	FILE_SOURCE :: "FIRST :: #string END\nfirst line\nEND\nSECOND :: #string,\\% DONE\n%\\%\nDONE\nafter :: 1;";
	file := Extended.parse_file(FILE_SOURCE);
	assert(file.status == .COMPLETE);
	assert(file.root.(*Extended.Parser_Block).statements.count == 3);
	assert(Extended.reconstruct_source(*file) == FILE_SOURCE);

	plain_string := Extended.parse_file("first :: \"text\"\nsecond :: 1;");
	assert(plain_string.status == .RECOVERED);
	assert(plain_string.diagnostics[0].expected_token == #char ";");
}

test_parenthesized_expression :: () {
	parsed := Extended.parse_expression("(identifier)");
	assert(parsed.status == .COMPLETE);
	assert(parsed.root.kind == .IDENT);
	assert((parsed.root.node_flags & .IS_PARENTHESIZED) != 0);
	assert(parsed.diagnostics.count == 0);
	assert(parsed.synthetic_tokens.count == 0);

	assert(parsed.root.first_token == xx 0);
	assert(parsed.root.one_past_last_token == xx 3);
}

test_missing_close_parenthesis :: () {
	SOURCE :: "(identifier";
	parsed := Extended.parse_expression(SOURCE);
	assert(parsed.status == .INCOMPLETE);
	assert(parsed.root.kind == .IDENT);
	assert((parsed.root.node_flags & .IS_PARENTHESIZED) != 0);
	assert(parsed.synthetic_tokens.count == 1);
	assert(parsed.diagnostics.count == 1);

	missing := parsed.synthetic_tokens[0];
	assert(missing.token.type == #char ")");
	assert(missing.insertion_index == xx 2);
	assert(missing.token.l0 == 1 && missing.token.c0 == 12);
	assert(missing.token.l1 == 1 && missing.token.c1 == 12);

	diagnostic := parsed.diagnostics[0];
	assert(diagnostic.kind == .EXPECTED_TOKEN);
	assert(diagnostic.span.first == xx 2);
	assert(diagnostic.span.one_past_last == xx 2);
	assert(diagnostic.expected_token == #char ")");
	assert(diagnostic.actual_token == .END_OF_INPUT);
	assert(diagnostic.recovery_action == .INSERT_MISSING_TOKEN);

	reconstructed := Extended.reconstruct_source(*parsed);
	assert(reconstructed == SOURCE);

	empty_group := Extended.parse_expression("(");
	assert(empty_group.status == .INCOMPLETE);
	assert(empty_group.root == null);
	assert(empty_group.diagnostics.count == 1);
	assert(empty_group.diagnostics[0].kind == .EXPECTED_EXPRESSION);
}

test_null_and_context :: () {
	null_result := Extended.parse_expression("null");
	assert(null_result.status == .COMPLETE);
	assert(null_result.root.kind == .LITERAL);
	null_literal := null_result.root.(*Extended.Parser_Literal);
	assert(null_literal.value_type == .POINTER);
	assert(null_literal.pointer_literal_info.pointer_literal_type == .CONSTANT_VALUE);
	assert(null_literal.pointer_literal_info.offset_from_symbol == 0);

	context_result := Extended.parse_expression("context");
	assert(context_result.status == .COMPLETE);
	assert(context_result.root.kind == .CONTEXT);
}

test_unexpected_token_diagnostic :: () {
	parsed := Extended.parse_expression("first second");
	assert(parsed.status == .RECOVERED);
	assert(parsed.root.kind == .IDENT);
	assert(parsed.diagnostics.count == 1);
	assert(parsed.synthetic_tokens.count == 0);

	diagnostic := parsed.diagnostics[0];
	assert(diagnostic.kind == .UNEXPECTED_TOKEN);
	assert(diagnostic.span.first == xx 1);
	assert(diagnostic.span.one_past_last == xx 2);
	assert(diagnostic.actual_token == .IDENT);
	assert(diagnostic.recovery_action == .SKIP_TOKENS);

	multiple := Extended.parse_expression("first second third");
	assert(multiple.diagnostics.count == 1);
	assert(multiple.diagnostics[0].span.first == xx 1);
	assert(multiple.diagnostics[0].span.one_past_last == xx 3);
}

test_recovery_records :: () {
	complete := Extended.parse_expression("value");
	assert(complete.recovery_records.count == 0);

	missing := Extended.parse_expression("(value");
	assert(missing.recovery_records.count == 1);
	missing_record := missing.recovery_records[0];
	assert(missing_record.kind == .MISSING_TOKEN);
	assert(missing_record.diagnostic_index == 0 && missing_record.synthetic_token_index == 0);
	assert(missing_record.span.first == xx 2 && missing_record.span.one_past_last == xx 2);
	assert(missing.synthetic_tokens[missing_record.synthetic_token_index].token.type == #char ")");
	assert(missing.diagnostics[missing_record.diagnostic_index].recovery_action == .INSERT_MISSING_TOKEN);
	assert(Extended.reconstruct_source(*missing) == "(value");

	missing_expression := Extended.parse_expression("(");
	assert(missing_expression.recovery_records.count == 1);
	assert(missing_expression.recovery_records[0].kind == .EXPECTED_EXPRESSION);
	assert(missing_expression.recovery_records[0].synthetic_token_index == -1);
	assert(missing_expression.recovery_records[0].span.first == missing_expression.diagnostics[0].span.first);
	assert(Extended.reconstruct_source(*missing_expression) == "(");

	skipped := Extended.parse_expression("first second third");
	assert(skipped.recovery_records.count == 1);
	skipped_record := skipped.recovery_records[0];
	assert(skipped_record.kind == .SKIPPED_TOKENS);
	assert(skipped_record.synthetic_token_index == -1 && skipped_record.diagnostic_index == 0);
	assert(skipped_record.span.first == xx 1 && skipped_record.span.one_past_last == xx 3);
	assert(skipped.diagnostics[skipped_record.diagnostic_index].recovery_action == .SKIP_TOKENS);
	assert(Extended.reconstruct_source(*skipped) == "first second third");

	CONTINUED_SOURCE :: "{ first := 1 second := 2; }";
	continued := Extended.parse_block(CONTINUED_SOURCE);
	assert(continued.root.(*Extended.Parser_Block).statements.count == 2);
	assert(continued.recovery_records.count == 1);
	assert(continued.recovery_records[0].kind == .MISSING_TOKEN);
	assert(continued.recovery_records[0].span.first == continued.synthetic_tokens[0].insertion_index);
	assert(Extended.reconstruct_source(*continued) == CONTINUED_SOURCE);
}

test_restart_points :: () {
	empty := Extended.parse_file("");
	assert(empty.restart_points.count == 1);
	assert(empty.restart_points[0].kind == .BLOCK);
	assert(empty.restart_points[0].span.first == xx 0 && empty.restart_points[0].span.one_past_last == xx 0);
	complete := Extended.parse_file("value :: 1;");
	assert(complete.status == .COMPLETE && complete.restart_points.count == 2);
	assert(Extended.parse_expression("value").restart_points.count == 0);

	SOURCE :: "main :: () { bad: ; next := 2; }\nafter :: 3;";
	parsed := Extended.parse_file(SOURCE);
	assert(parsed.status == .RECOVERED);
	assert(parsed.root.(*Extended.Parser_Block).statements.count == 2);
	saw_root := false;
	saw_body := false;
	saw_main := false;
	saw_next := false;
	saw_after := false;
	for parsed.restart_points {
		assert(it.span.first <= it.span.one_past_last);
		assert(it.span.one_past_last < xx parsed.tokens.count);
		if it.kind == .BLOCK {
			if it.span.first == xx 0 && it.span.one_past_last == xx (parsed.tokens.count - 1) {
				saw_root = true;
			}

			if Extended.token_at(*parsed, it.span.first).type == #char "{" {
				saw_body = true;
			}
		} else {
			name := Extended.token_at(*parsed, it.span.first).original_text;
			if		name == "main"	saw_main = true;
			else if name == "next"	saw_next = true;
			else if name == "after"	saw_after = true;
		}
	}

	assert(saw_root && saw_body && saw_main && saw_next && saw_after);
	assert(Extended.reconstruct_source(*parsed) == SOURCE);
	point_count := parsed.restart_points.count;
	Extended.release_parser_tree(*parsed);
	assert(parsed.restart_points.count == point_count);
	assert(Extended.token_at(*parsed, parsed.restart_points[point_count - 1].span.first) != null);
}

test_incomplete_diagnostics :: () {
	truncated := Extended.parse_file("broken :: () { next :=");
	assert(truncated.status == .INCOMPLETE);
	assert(truncated.diagnostics.count > 0);
	for source: string.["", "broken :: () {", "broken :: () { next :=", "broken :: () { bad: ; next := "] {
		parsed := Extended.parse_file(source);
		again := Extended.parse_file(source);
		assert(parsed.status == again.status);
		assert(parsed.diagnostics.count == again.diagnostics.count);
		assert(parsed.synthetic_tokens.count == again.synthetic_tokens.count);
		for parsed.diagnostics {
			other := again.diagnostics[it_index];
			assert(it.kind == other.kind && it.span.first == other.span.first && it.span.one_past_last == other.span.one_past_last);
			assert(it.expected_token == other.expected_token && it.actual_token == other.actual_token);
			assert(it.recovery_action == other.recovery_action && it.message == other.message);
			assert(it.related_information.count == other.related_information.count);
			for it.related_information {
				related := other.related_information[it_index];
				assert(it.span.first == related.span.first && it.span.one_past_last == related.span.one_past_last);
				assert(it.message == related.message);
			}
		}

		for parsed.synthetic_tokens {
			other := again.synthetic_tokens[it_index];
			assert(it.token.type == other.token.type && it.insertion_index == other.insertion_index);
			assert(it.token.l0 == other.token.l0 && it.token.c0 == other.token.c0);
		}

		assert(Extended.reconstruct_source(*parsed) == source);
	}

	SOURCE :: "broken :: () { bad: ; next := ";
	first := Extended.parse_file(SOURCE);
	assert(first.status == .RECOVERED && first.diagnostics.count > 0);
	assert(Extended.reconstruct_source(*first) == SOURCE);

	extended := Extended.parse_file("broken :: () { bad: ; next := 1;");
	assert(extended.diagnostics.count > 0);
	assert(first.diagnostics[0].kind == extended.diagnostics[0].kind);
	assert(first.diagnostics[0].span.first == extended.diagnostics[0].span.first);
	assert(first.diagnostics[0].span.one_past_last == extended.diagnostics[0].span.one_past_last);
	assert(first.diagnostics[0].actual_token == extended.diagnostics[0].actual_token);
	assert(first.diagnostics[0].message == extended.diagnostics[0].message);
}

test_lexical_bindings :: () {
	SOURCE :: #string JAI
global :: 1;
main :: (arg: s64) {
	local := arg;
	{
		local := 2;
		inner := local + global;
	}
	after := local;
}
forward := later;
later :: 3;
JAI;
	parsed := Extended.parse_file(SOURCE);
	assert(parsed.status == .COMPLETE);
	root := parsed.root.(*Extended.Parser_Block);
	global := root.statements[0].(*Extended.Parser_Declaration);
	main_declaration := root.statements[1].(*Extended.Parser_Declaration);
	header := main_declaration.expression.(*Extended.Parser_Procedure_Header);
	argument := header.arguments[0];
	body := header.body_or_null.block;
	local := body.statements[0].(*Extended.Parser_Declaration);
	arg_use := local.expression.(*Extended.Parser_Ident);
	assert(arg_use.resolved_declaration == argument);
	inner_block := body.statements[1].(*Extended.Parser_Block);
	inner_local := inner_block.statements[0].(*Extended.Parser_Declaration);
	inner := inner_block.statements[1].(*Extended.Parser_Declaration);
	addition := inner.expression.(*Extended.Parser_Binary_Operator);
	assert(addition.left.(*Extended.Parser_Ident).resolved_declaration == inner_local);
	assert(addition.right.(*Extended.Parser_Ident).resolved_declaration == global);
	after := body.statements[2].(*Extended.Parser_Declaration);
	assert(after.expression.(*Extended.Parser_Ident).resolved_declaration == local);
	forward := root.statements[2].(*Extended.Parser_Declaration);
	later := root.statements[3].(*Extended.Parser_Declaration);
	assert(forward.expression.(*Extended.Parser_Ident).resolved_declaration == later);
	assert(parsed.root_scope.bindings.count == 4);
	assert(parsed.root_scope.owner == parsed.root);
	assert(parsed.root_scope.children.count == 1);
	header_scope := parsed.root_scope.children[0];
	assert(header_scope.owner == header && header_scope.parent == parsed.root_scope);
	assert(header_scope.bindings[0].declaration == argument);
	assert(header_scope.children[0].owner == body);
	assert(Extended.reconstruct_source(*parsed) == SOURCE);
	Extended.release_parser_tree(*parsed);
	assert(parsed.root_scope == null);

	unresolved := Extended.parse_file("field :: 1; value := object.field;");
	member := unresolved.root.(*Extended.Parser_Block).statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Binary_Operator);
	assert(member.left.(*Extended.Parser_Ident).resolved_declaration == null);
	assert(member.right.(*Extended.Parser_Ident).resolved_declaration == null);

	compound := Extended.parse_file("left, right := pair; sum := left + right;");
	assert(compound.status == .COMPLETE);
	compound_root := compound.root.(*Extended.Parser_Block);
	compound_declaration := compound_root.statements[0].(*Extended.Parser_Compound_Declaration);
	sum := compound_root.statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Binary_Operator);
	assert(sum.left.(*Extended.Parser_Ident).resolved_declaration == compound_declaration.declaration_properties);
	assert(sum.right.(*Extended.Parser_Ident).resolved_declaration == compound_declaration.declaration_properties);
	assert(compound.root_scope.bindings.count == 3);
	reassignment := Extended.parse_file("left, right = pair; sum := left;");
	assert(reassignment.root_scope.bindings.count == 1);
	assert(reassignment.root.(*Extended.Parser_Block).statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == null);

	aggregate := Extended.parse_file("Record :: struct { field: s64; other: s64 = field; } outside := field;");
	assert(aggregate.status == .COMPLETE);
	aggregate_root := aggregate.root.(*Extended.Parser_Block);
	members := aggregate_root.statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Struct).block.statements;
	assert(members[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == members[0].(*Extended.Parser_Declaration));
	assert(aggregate_root.statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == null);

	cases := Extended.parse_block("{ if value == { case 1; local := 1; case 2; other := local; } }");
	assert(cases.status == .COMPLETE);
	case_block := cases.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_If).then_block;
	second_arm := case_block.statements[1].(*Extended.Parser_Case).then_block;
	assert(second_arm.statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == null);

	quick := Extended.parse_file("lambda := x => x;");
	assert(quick.status == .COMPLETE);
	quick_header := quick.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header);
	quick_return := quick_header.body_or_null.block.statements[0].(*Extended.Parser_Return);
	assert(quick_return.arguments_unsorted[0].expression.(*Extended.Parser_Ident).resolved_declaration == quick_header.arguments[0]);
}

test_using_map_names :: (using_node: *Extended.Parser_Using, names: [] string) -> bool {
	assert(using_node.filter_expression.(*Extended.Parser_Ident).name == "rename");
	for * names {
		it.* = ifx it.* == "pete"
			then "renamed_pete"
			else "";
	}

	return true;
}

test_using_map_collision :: (using_node: *Extended.Parser_Using, names: [] string) -> bool {
	for * names {
		it.* = "same_name";
	}

	return true;
}

test_using_map_fields :: (using_node: *Extended.Parser_Using, names: [] string) -> bool {
	for * names {
		it.* = ifx it.* == "Clear"
			then "glClear"
			else "";
	}

	return true;
}

test_semantic_field: Extended.Parser_Declaration;
test_semantic_field_name: string;

test_using_map_semantic_fields :: (using_node: *Extended.Parser_Using, bindings: *[..] Extended.Parser_Binding) -> bool {
	assert(using_node.expression.kind == .DECLARATION);
	array_add(bindings, .{name = test_semantic_field_name, declaration = *test_semantic_field});
	return true;
}

test_using_map_decline_fields :: (using_node: *Extended.Parser_Using, bindings: *[..] Extended.Parser_Binding) -> bool {
	array_add(bindings, .{name = "Ignored", declaration = *test_semantic_field});
	return false;
}

test_file_import_resolution :: () {
	filename := join(#filepath, "../../../how_to/040_import_and_load/main.jai");
	syntax := Extended.parse_file("item :: 1; value := item;", resolve_identifiers=false);
	syntax_statements := syntax.root.(*Extended.Parser_Block).statements;
	assert(syntax_statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == null);
	Extended.release_parser_tree(*syntax);
	Extended.release_parser_names(*syntax);

	EDIT_OLD_SOURCE :: "item :: 1; value := item;";
	EDIT_NEW_SOURCE :: "item :: 2; value := item;";
	edit_old := Extended.parse_file(EDIT_OLD_SOURCE);
	edit_start := "item :: ".count;
	edit_syntax, edit_success := Extended.parse_file_edit(*edit_old, edit_start, edit_start + 1, EDIT_NEW_SOURCE, resolve_identifiers=false);
	assert(edit_success);
	assert(edit_syntax.root.(*Extended.Parser_Block).statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == null);
	Extended.release_parser_tree(*edit_syntax);
	Extended.release_parser_names(*edit_syntax);
	Extended.release_parser_tree(*edit_old);
	Extended.release_parser_names(*edit_old);

	LOAD_SOURCE :: "#load \"files/From_Subdirectory/another_file.jai\"; call := pete;";
	load_parsed := Extended.parse_file(LOAD_SOURCE, filename);
	load_use := load_parsed.root.(*Extended.Parser_Block).statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident);
	assert(load_use.resolved_declaration == null);
	no_follow := Extended.resolve_file_imports(*load_parsed, follow=xx 0);
	assert(no_follow.loaded_files.count == 0 && load_use.resolved_declaration == null);
	Extended.release_file_imports(*no_follow);
	no_loads := Extended.resolve_file_imports(*load_parsed, follow=.ALL_IMPORTS);
	assert(no_loads.loaded_files.count == 0 && load_use.resolved_declaration == null);
	Extended.release_file_imports(*no_loads);
	loads := Extended.resolve_file_imports(*load_parsed, follow=.LOAD);
	assert(loads.loaded_files.count == 1);
	assert(load_use.resolved_declaration && load_use.resolved_declaration.name == "pete");
	Extended.release_file_imports(*loads);
	Extended.release_parser_tree(*load_parsed);
	Extended.release_parser_names(*load_parsed);

	SOURCE :: #string JAI
Specific :: #import,file "files/specific.jai";
value := Specific.mess_up_this_string;
nested := Specific.mess_up_this_string("text");
JAI;
	parsed := Extended.parse_file(SOURCE, filename);
	assert(parsed.status == .COMPLETE);
	root := parsed.root.(*Extended.Parser_Block);
	import_declaration := root.statements[0].(*Extended.Parser_Declaration);
	member := root.statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Binary_Operator);
	assert(member.left.(*Extended.Parser_Ident).resolved_declaration == import_declaration);
	assert(member.right.(*Extended.Parser_Ident).resolved_declaration == null);
	file_only := Extended.resolve_file_imports(*parsed, follow=.IMPORT_FILE);
	assert(file_only.modules.count == 1 && file_only.modules[0].loaded_files.count == 0);
	Extended.release_file_imports(*file_only);
	skipped := Extended.resolve_file_imports(*parsed, follow=.LOAD);
	assert(skipped.modules.count == 0 && skipped.unresolved_imports.count == 0);
	assert(member.right.(*Extended.Parser_Ident).resolved_declaration == null);
	Extended.release_file_imports(*skipped);
	imports := Extended.resolve_file_imports(*parsed);
	assert(imports.modules.count == 1);
	assert(member.right.(*Extended.Parser_Ident).resolved_declaration != null);
	assert(member.right.(*Extended.Parser_Ident).resolved_declaration.name == "mess_up_this_string");
	nested_call := root.statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Call);
	nested_member := nested_call.procedure_expression.(*Extended.Parser_Binary_Operator).right.(*Extended.Parser_Ident);
	assert(nested_member.resolved_declaration && nested_member.resolved_declaration.name == "mess_up_this_string");
	assert(Extended.reconstruct_source(*parsed) == SOURCE);
	Extended.release_file_imports(*imports);
	Extended.release_parser_tree(*parsed);
	Extended.release_parser_names(*parsed);

	DIRECTORY_SOURCE :: #string JAI
Subdir :: #import,dir "files/From_Subdirectory";
call := Subdir.repeat;
other := Subdir.pete;
JAI;
	directory := Extended.parse_file(DIRECTORY_SOURCE, filename);
	directory_only := Extended.resolve_file_imports(*directory, follow=.IMPORT_DIR);
	assert(directory_only.modules.count == 1 && directory_only.modules[0].loaded_files.count == 0);
	Extended.release_file_imports(*directory_only);
	directory_without_loads := Extended.resolve_file_imports(*directory, follow=.ALL_IMPORTS);
	assert(directory_without_loads.modules.count == 1);
	assert(directory_without_loads.modules[0].loaded_files.count == 0);
	Extended.release_file_imports(*directory_without_loads);
	directory_imports := Extended.resolve_file_imports(*directory);
	assert(directory_imports.modules.count == 1);
	directory_member := directory.root.(*Extended.Parser_Block).statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Binary_Operator).right.(*Extended.Parser_Ident);
	assert(directory_member.resolved_declaration && directory_member.resolved_declaration.name == "repeat");
	loaded_member := directory.root.(*Extended.Parser_Block).statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Binary_Operator).right.(*Extended.Parser_Ident);
	assert(loaded_member.resolved_declaration && loaded_member.resolved_declaration.name == "pete");
	Extended.release_file_imports(*directory_imports);
	Extended.release_parser_tree(*directory);
	Extended.release_parser_names(*directory);

	EXCEPT_SOURCE :: #string JAI
Subdir :: #import,dir "files/From_Subdirectory";
using,except(repeat) Subdir;
yes := pete;
no := repeat;
JAI;
	except_parsed := Extended.parse_file(EXCEPT_SOURCE, filename);
	except_imports := Extended.resolve_file_imports(*except_parsed);
	except_statements := except_parsed.root.(*Extended.Parser_Block).statements;
	assert(except_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration != null);
	assert(except_statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == null);
	Extended.release_file_imports(*except_imports);
	Extended.release_parser_tree(*except_parsed);
	Extended.release_parser_names(*except_parsed);

	MISSING_SOURCE :: #string JAI
Missing :: #import,file "files/does_not_exist.jai";
JAI;
	missing := Extended.parse_file(MISSING_SOURCE, filename);
	missing_imports := Extended.resolve_file_imports(*missing);
	assert(missing_imports.modules.count == 0);
	assert(missing_imports.unresolved_imports.count == 1);
	Extended.release_file_imports(*missing_imports);
	Extended.release_parser_tree(*missing);
	Extended.release_parser_names(*missing);

	search_path := join(#filepath, "../../../how_to/040_import_and_load/files");
	BARE_SOURCE :: #string JAI
#import "specific";
call := mess_up_this_string;
JAI;
	bare := Extended.parse_file(BARE_SOURCE, filename);
	bare_skipped := Extended.resolve_file_imports(*bare, .[search_path], follow=.IMPORT_FILE | .IMPORT_DIR);
	assert(bare_skipped.modules.count == 0 && bare_skipped.unresolved_imports.count == 0);
	Extended.release_file_imports(*bare_skipped);
	bare_only := Extended.resolve_file_imports(*bare, .[search_path], follow=.IMPORT);
	assert(bare_only.modules.count == 1 && bare_only.modules[0].loaded_files.count == 0);
	Extended.release_file_imports(*bare_only);
	bare_imports := Extended.resolve_file_imports(*bare, .[search_path]);
	assert(bare_imports.modules.count == 1);
	bare_use := bare.root.(*Extended.Parser_Block).statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident);
	assert(bare_use.resolved_declaration && bare_use.resolved_declaration.name == "mess_up_this_string");
	Extended.release_file_imports(*bare_imports);
	Extended.release_parser_tree(*bare);
	Extended.release_parser_names(*bare);
	free(search_path);

	USING_SOURCE :: #string JAI
using Specific :: #import,file "files/specific.jai";
call := mess_up_this_string;
JAI;
	using_parsed := Extended.parse_file(USING_SOURCE, filename);
	using_imports := Extended.resolve_file_imports(*using_parsed);
	assert(using_imports.modules.count == 1);
	using_use := using_parsed.root.(*Extended.Parser_Block).statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident);
	assert(using_use.resolved_declaration && using_use.resolved_declaration.name == "mess_up_this_string");
	Extended.release_file_imports(*using_imports);
	Extended.release_parser_tree(*using_parsed);
	Extended.release_parser_names(*using_parsed);

	FILTERED_SOURCE :: #string JAI
Subdir :: #import,dir "files/From_Subdirectory";
using,only(repeat) Subdir;
call := repeat;
hidden := pete;
JAI;
	filtered := Extended.parse_file(FILTERED_SOURCE, filename);
	filtered_imports := Extended.resolve_file_imports(*filtered);
	filtered_use := filtered.root.(*Extended.Parser_Block).statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident);
	assert(filtered_use.resolved_declaration && filtered_use.resolved_declaration.name == "repeat");
	filtered_hidden := filtered.root.(*Extended.Parser_Block).statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident);
	assert(filtered_hidden.resolved_declaration == null);
	Extended.release_file_imports(*filtered_imports);
	Extended.release_parser_tree(*filtered);
	Extended.release_parser_names(*filtered);

	MULTIPLE_SOURCE :: #string JAI
Subdir :: #import,dir "files/From_Subdirectory";
using,only(repeat) Subdir;
using,only(pete) Subdir;
first := repeat;
second := pete;
JAI;
	multiple := Extended.parse_file(MULTIPLE_SOURCE, filename);
	multiple_imports := Extended.resolve_file_imports(*multiple);
	multiple_statements := multiple.root.(*Extended.Parser_Block).statements;
	assert(multiple_statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration != null);
	assert(multiple_statements[4].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration != null);
	Extended.release_file_imports(*multiple_imports);
	assert(multiple_statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == null);
	assert(multiple_statements[4].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == null);
	Extended.release_parser_tree(*multiple);
	Extended.release_parser_names(*multiple);

	PLAIN_USING_SOURCE :: #string JAI
Specific :: #import,file "files/specific.jai";
using Specific;
call := mess_up_this_string;
JAI;
	plain_using := Extended.parse_file(PLAIN_USING_SOURCE, filename, resolve_identifiers=false);
	assert(plain_using.root.(*Extended.Parser_Block).statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == null);
	plain_imports := Extended.resolve_file_imports(*plain_using);
	plain_use := plain_using.root.(*Extended.Parser_Block).statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident);
	assert(plain_use.resolved_declaration && plain_use.resolved_declaration.name == "mess_up_this_string");
	Extended.release_file_imports(*plain_imports);
	Extended.release_parser_tree(*plain_using);
	Extended.release_parser_names(*plain_using);

	NESTED_USING_SOURCE :: #string JAI
Specific :: #import,file "files/specific.jai";
first :: () {
	using Specific;
	call := mess_up_this_string;
}
second :: () {
	call := mess_up_this_string;
}
JAI;
	nested_using := Extended.parse_file(NESTED_USING_SOURCE, filename);
	nested_imports := Extended.resolve_file_imports(*nested_using);
	nested_uses: [..]*Extended.Parser_Ident;
	for procedure_scope: nested_using.root_scope.children {
		for scope: procedure_scope.children {
			for reference: scope.references {
				if reference.name == "mess_up_this_string" {
					array_add(*nested_uses, reference);
				}
			}
		}
	}

	assert(nested_uses.count == 2);
	assert(nested_uses[0].resolved_declaration && nested_uses[0].resolved_declaration.name == "mess_up_this_string");
	assert(nested_uses[1].resolved_declaration == null);
	array_free(nested_uses);
	Extended.release_file_imports(*nested_imports);
	Extended.release_parser_tree(*nested_using);
	Extended.release_parser_names(*nested_using);

	MAP_SOURCE :: #string JAI
Specific :: #import,file "files/specific.jai";
using,map(rename) Specific;
call := mess_up_this_string;
JAI;
	map_parsed := Extended.parse_file(MAP_SOURCE, filename);
	map_imports := Extended.resolve_file_imports(*map_parsed);
	assert(map_imports.unsupported_using_filters.count == 1);
	assert(map_parsed.root.(*Extended.Parser_Block).statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == null);
	Extended.release_file_imports(*map_imports);
	Extended.release_parser_tree(*map_parsed);
	Extended.release_parser_names(*map_parsed);

	MAPPED_SOURCE :: #string JAI
Subdir :: #import,dir "files/From_Subdirectory";
using,map(rename) Subdir;
call := renamed_pete;
hidden := pete;
skipped := repeat;
JAI;
	mapped := Extended.parse_file(MAPPED_SOURCE, filename);
	mapped_imports := Extended.resolve_file_imports(*mapped, map_names=test_using_map_names);
	mapped_statements := mapped.root.(*Extended.Parser_Block).statements;
	assert(mapped_imports.unsupported_using_filters.count == 0);
	assert(mapped_imports.mapped_names.count == 2);
	found_pete_mapping := false;
	for mapped_imports.mapped_names {
		if it.source_name == "pete" {
			assert(it.exported_name == "renamed_pete" && it.declaration.name == "pete");
			found_pete_mapping = true;
		}
	}

	assert(found_pete_mapping);
	assert(mapped_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration.name == "pete");
	assert(mapped_statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == null);
	assert(mapped_statements[4].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == null);
	Extended.release_file_imports(*mapped_imports);
	assert(mapped_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == null);
	Extended.release_parser_tree(*mapped);
	Extended.release_parser_names(*mapped);

	COLLISION_SOURCE :: #string JAI
Subdir :: #import,dir "files/From_Subdirectory";
using,map(rename) Subdir;
call := same_name;
JAI;
	collision := Extended.parse_file(COLLISION_SOURCE, filename);
	collision_imports := Extended.resolve_file_imports(*collision, map_names=test_using_map_collision);
	assert(collision_imports.map_collisions.count == 1);
	assert(collision_imports.map_collisions[0].exported_name == "same_name");
	assert(collision_imports.map_collisions[0].first != collision_imports.map_collisions[0].second);
	assert(collision.root.(*Extended.Parser_Block).statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == null);
	Extended.release_file_imports(*collision_imports);
	Extended.release_parser_tree(*collision);
	Extended.release_parser_names(*collision);

	AGGREGATE_SOURCE :: #string JAI
Procs :: struct {
	Clear: int;
	PushMatrix: int;
}
main :: () {
	using,map(rename) procs: Procs;
	call := glClear;
	hidden := PushMatrix;
}
JAI;
	aggregate := Extended.parse_file(AGGREGATE_SOURCE, filename);
	aggregate_imports := Extended.resolve_file_imports(*aggregate, map_names=test_using_map_fields);
	assert(aggregate_imports.mapped_names.count == 2);
	aggregate_scope := aggregate.root_scope.children[1].children[0];
	for reference: aggregate_scope.references {
		if reference.name == "glClear" {
			assert(reference.resolved_declaration && reference.resolved_declaration.name == "Clear");
		}

		if reference.name == "PushMatrix" {
			assert(reference.resolved_declaration == null);
		}
	}

	Extended.release_file_imports(*aggregate_imports);
	for reference: aggregate_scope.references {
		if reference.name == "glClear" {
			assert(reference.resolved_declaration == null);
		}
	}

	Extended.release_parser_tree(*aggregate);
	Extended.release_parser_names(*aggregate);

	STATIC_SOURCE :: #string JAI
Procs :: struct {
	#if true {
		Clear: int;
	} else {
		PushMatrix: int;
	}
}
main :: () {
	using,map(rename) procs: Procs;
	call := glClear;
	hidden := PushMatrix;
}
JAI;
	static_value := Extended.parse_file(STATIC_SOURCE, filename);
	static_imports := Extended.resolve_file_imports(*static_value, map_names=test_using_map_fields);
	assert(static_value.status == .COMPLETE && static_imports.mapped_names.count == 1);
	static_statements := static_value.root.(*Extended.Parser_Block).statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block.statements;
	assert(static_statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == static_imports.mapped_names[0].declaration);
	assert(static_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == null);
	Extended.release_file_imports(*static_imports);
	Extended.release_parser_tree(*static_value);
	Extended.release_parser_names(*static_value);

	FALSE_SOURCE :: #string JAI
Procs :: struct {
	#if false {
		PushMatrix: int;
	} else {
		#if true {
			Clear: int;
		}
	}
}
main :: () {
	using,map(rename) procs: Procs;
	call := glClear;
	hidden := PushMatrix;
}
JAI;
	false_value := Extended.parse_file(FALSE_SOURCE, filename);
	false_imports := Extended.resolve_file_imports(*false_value, map_names=test_using_map_fields);
	assert(false_value.status == .COMPLETE && false_imports.mapped_names.count == 1);
	assert(false_imports.mapped_names[0].declaration.name == "Clear");
	false_statements := false_value.root.(*Extended.Parser_Block).statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block.statements;
	assert(false_statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == false_imports.mapped_names[0].declaration);
	assert(false_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == null);
	Extended.release_file_imports(*false_imports);
	Extended.release_parser_tree(*false_value);
	Extended.release_parser_names(*false_value);

	NEGATED_SOURCE :: #string JAI
Procs :: struct {
	#if !false {
		Clear: int;
	} else {
		PushMatrix: int;
	}
}
main :: () {
	using,map(rename) procs: Procs;
	call := glClear;
	hidden := PushMatrix;
}
JAI;
	negated_value := Extended.parse_file(NEGATED_SOURCE, filename);
	negated_imports := Extended.resolve_file_imports(*negated_value, map_names=test_using_map_fields);
	assert(negated_value.status == .COMPLETE && negated_imports.mapped_names.count == 1);
	negated_statements := negated_value.root.(*Extended.Parser_Block).statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block.statements;
	assert(negated_statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == negated_imports.mapped_names[0].declaration);
	assert(negated_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == null);
	Extended.release_file_imports(*negated_imports);
	Extended.release_parser_tree(*negated_value);
	Extended.release_parser_names(*negated_value);

	NEGATED_FALSE_SOURCE :: #string JAI
Procs :: struct {
	#if !true {
		PushMatrix: int;
	} else {
		Clear: int;
	}
}
main :: () {
	using,map(rename) procs: Procs;
	call := glClear;
	hidden := PushMatrix;
}
JAI;
	negated_false := Extended.parse_file(NEGATED_FALSE_SOURCE, filename);
	negated_false_imports := Extended.resolve_file_imports(*negated_false, map_names=test_using_map_fields);
	assert(negated_false.status == .COMPLETE && negated_false_imports.mapped_names.count == 1);
	assert(negated_false_imports.mapped_names[0].declaration.name == "Clear");
	negated_false_statements := negated_false.root.(*Extended.Parser_Block).statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block.statements;
	assert(negated_false_statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == negated_false_imports.mapped_names[0].declaration);
	assert(negated_false_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == null);
	Extended.release_file_imports(*negated_false_imports);
	Extended.release_parser_tree(*negated_false);
	Extended.release_parser_names(*negated_false);

	CONSTANT_SOURCE :: #string JAI
Enabled :: true;
Procs :: struct {
	#if Enabled {
		Clear: int;
	} else {
		PushMatrix: int;
	}
}
main :: () {
	using,map(rename) procs: Procs;
	call := glClear;
	hidden := PushMatrix;
}
JAI;
	constant_value := Extended.parse_file(CONSTANT_SOURCE, filename);
	constant_imports := Extended.resolve_file_imports(*constant_value, map_names=test_using_map_fields);
	assert(constant_value.status == .COMPLETE && constant_imports.mapped_names.count == 1);
	constant_statements := constant_value.root.(*Extended.Parser_Block).statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block.statements;
	assert(constant_statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == constant_imports.mapped_names[0].declaration);
	assert(constant_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == null);
	Extended.release_file_imports(*constant_imports);
	Extended.release_parser_tree(*constant_value);
	Extended.release_parser_names(*constant_value);

	AMBIGUOUS_CONSTANT_SOURCE :: #string JAI
Enabled :: true;
Enabled :: false;
Procs :: struct {
	#if Enabled {
		Clear: int;
	} else {
		PushMatrix: int;
	}
}
main :: () {
	using,map(rename) procs: Procs;
	call := glClear;
}
JAI;
	ambiguous_constant := Extended.parse_file(AMBIGUOUS_CONSTANT_SOURCE, filename);
	ambiguous_constant_imports := Extended.resolve_file_imports(*ambiguous_constant, map_names=test_using_map_fields);
	assert(ambiguous_constant.status == .COMPLETE && ambiguous_constant_imports.mapped_names.count == 0 && ambiguous_constant_imports.unsupported_using_filters.count == 1);
	ambiguous_constant_call := (
		ambiguous_constant.root.(*Extended.Parser_Block).statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header)
			.body_or_null.block.statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident)
	);
	assert(ambiguous_constant_call.resolved_declaration == null);
	Extended.release_file_imports(*ambiguous_constant_imports);
	Extended.release_parser_tree(*ambiguous_constant);
	Extended.release_parser_names(*ambiguous_constant);

	AMBIGUOUS_CONDITION_ALIAS_SOURCE :: #string JAI
Enabled :: true;
Enabled :: false;
Selected :: Enabled;
Procs :: struct {
	#if Selected {
		Clear: int;
	} else {
		PushMatrix: int;
	}
}
main :: () {
	using,map(rename) procs: Procs;
	call := glClear;
}
JAI;
	ambiguous_condition_alias := Extended.parse_file(AMBIGUOUS_CONDITION_ALIAS_SOURCE, filename);
	ambiguous_condition_alias_imports := Extended.resolve_file_imports(*ambiguous_condition_alias, map_names=test_using_map_fields);
	assert(ambiguous_condition_alias.status == .COMPLETE && ambiguous_condition_alias_imports.mapped_names.count == 0 && ambiguous_condition_alias_imports.unsupported_using_filters.count == 1);
	Extended.release_file_imports(*ambiguous_condition_alias_imports);
	Extended.release_parser_tree(*ambiguous_condition_alias);
	Extended.release_parser_names(*ambiguous_condition_alias);

	COMBINED_SOURCE :: #string JAI
Left :: false;
Right :: true;
Enabled :: Left || Right && !false;
Procs :: struct {
	#if Enabled {
		Clear: int;
	} else {
		PushMatrix: int;
	}
}
main :: () {
	using,map(rename) procs: Procs;
	call := glClear;
}
JAI;
	combined := Extended.parse_file(COMBINED_SOURCE, filename);
	combined_imports := Extended.resolve_file_imports(*combined, map_names=test_using_map_fields);
	assert(combined.status == .COMPLETE && combined_imports.mapped_names.count == 1);
	assert(combined_imports.mapped_names[0].declaration.name == "Clear");
	Extended.release_file_imports(*combined_imports);
	Extended.release_parser_tree(*combined);
	Extended.release_parser_names(*combined);

	MUTABLE_SOURCE :: #string JAI
Enabled := true;
Procs :: struct {
	Clear: int;
	#if Enabled {
		PushMatrix: int;
	}
}
main :: () {
	using,map(rename) procs: Procs;
	call := glClear;
}
JAI;
	mutable_value := Extended.parse_file(MUTABLE_SOURCE, filename);
	mutable_imports := Extended.resolve_file_imports(*mutable_value, map_names=test_using_map_fields);
	assert(mutable_value.status == .COMPLETE && mutable_imports.mapped_names.count == 0 && mutable_imports.unsupported_using_filters.count == 1);
	Extended.release_file_imports(*mutable_imports);
	Extended.release_parser_tree(*mutable_value);
	Extended.release_parser_names(*mutable_value);

	CONSTANT_CYCLE_SOURCE :: #string JAI
First :: Second;
Second :: First;
Procs :: struct {
	Clear: int;
	#if First {
		PushMatrix: int;
	}
}
main :: () {
	using,map(rename) procs: Procs;
	call := glClear;
}
JAI;
	constant_cycle := Extended.parse_file(CONSTANT_CYCLE_SOURCE, filename);
	constant_cycle_imports := Extended.resolve_file_imports(*constant_cycle, map_names=test_using_map_fields);
	assert(constant_cycle.status == .COMPLETE && constant_cycle_imports.mapped_names.count == 0 && constant_cycle_imports.unsupported_using_filters.count == 1);
	Extended.release_file_imports(*constant_cycle_imports);
	Extended.release_parser_tree(*constant_cycle);
	Extended.release_parser_names(*constant_cycle);

	UNKNOWN_SOURCE :: #string JAI
Procs :: struct {
	Clear: int;
	#if Unknown {
		PushMatrix: int;
	}
}
main :: () {
	using,map(rename) procs: Procs;
	call := glClear;
}
JAI;
	unknown_value := Extended.parse_file(UNKNOWN_SOURCE, filename);
	unknown_imports := Extended.resolve_file_imports(*unknown_value, map_names=test_using_map_fields);
	assert(unknown_value.status == .COMPLETE && unknown_imports.mapped_names.count == 0 && unknown_imports.unsupported_using_filters.count == 1);
	unknown_call := (
		unknown_value.root.(*Extended.Parser_Block).statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header)
			.body_or_null.block.statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident)
	);
	assert(unknown_call.resolved_declaration == null);
	Extended.release_file_imports(*unknown_imports);
	Extended.release_parser_tree(*unknown_value);
	Extended.release_parser_names(*unknown_value);

	NEGATED_UNKNOWN_SOURCE :: #string JAI
Procs :: struct {
	Clear: int;
	#if !Unknown {
		PushMatrix: int;
	}
}
main :: () {
	using,map(rename) procs: Procs;
	call := glClear;
}
JAI;
	negated_unknown := Extended.parse_file(NEGATED_UNKNOWN_SOURCE, filename);
	negated_unknown_imports := Extended.resolve_file_imports(*negated_unknown, map_names=test_using_map_fields);
	assert(negated_unknown.status == .COMPLETE && negated_unknown_imports.mapped_names.count == 0 && negated_unknown_imports.unsupported_using_filters.count == 1);
	Extended.release_file_imports(*negated_unknown_imports);
	Extended.release_parser_tree(*negated_unknown);
	Extended.release_parser_names(*negated_unknown);

	ALIAS_SOURCE :: #string JAI
Procs :: struct {
	Clear: int;
}
Alias :: Procs;
main :: () {
	using,map(rename) procs: Alias;
	call := glClear;
}
JAI;
	alias := Extended.parse_file(ALIAS_SOURCE, filename);
	alias_imports := Extended.resolve_file_imports(*alias, map_names=test_using_map_fields);
	assert(alias_imports.mapped_names.count == 1);
	alias_call := (
		alias.root.(*Extended.Parser_Block).statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header)
			.body_or_null.block.statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident)
	);
	assert(alias_call.resolved_declaration && alias_call.resolved_declaration.name == "Clear");
	Extended.release_file_imports(*alias_imports);
	Extended.release_parser_tree(*alias);
	Extended.release_parser_names(*alias);

	QUERY_TYPE_SOURCE :: #string JAI
Procs :: struct {
	Clear: int;
}
main :: () {
	original := Procs.{
		Clear=1
	};
	using,map(rename) procs: type_of(original);
	call := glClear;
}
JAI;
	query_type := Extended.parse_file(QUERY_TYPE_SOURCE, filename);
	query_type_imports := Extended.resolve_file_imports(*query_type, map_names=test_using_map_fields);
	assert(query_type.status == .COMPLETE && query_type_imports.mapped_names.count == 1 && query_type_imports.unsupported_using_filters.count == 0);
	query_type_statements := query_type.root.(*Extended.Parser_Block).statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block.statements;
	assert(query_type_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == query_type_imports.mapped_names[0].declaration);
	Extended.release_file_imports(*query_type_imports);
	Extended.release_parser_tree(*query_type);
	Extended.release_parser_names(*query_type);

	MEMBER_TYPE_SOURCE :: #string JAI
Child :: struct {
	Clear: int;
}
Container :: struct {
	Nested: Child;
}
main :: () {
	using,map(rename) procs := Container.{
		Nested=Child.{
			Clear=1
		}
	}.Nested;
	call := glClear;
}
JAI;
	member_type := Extended.parse_file(MEMBER_TYPE_SOURCE, filename);
	member_type_imports := Extended.resolve_file_imports(*member_type, map_names=test_using_map_fields);
	assert(member_type.status == .COMPLETE && member_type_imports.mapped_names.count == 1 && member_type_imports.unsupported_using_filters.count == 0);
	member_type_statements := member_type.root.(*Extended.Parser_Block).statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block.statements;
	assert(member_type_statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == member_type_imports.mapped_names[0].declaration);
	Extended.release_file_imports(*member_type_imports);
	Extended.release_parser_tree(*member_type);
	Extended.release_parser_names(*member_type);

	TYPED_MEMBER_SOURCE :: #string JAI
Child :: struct {
	Clear: int;
}
Container :: struct {
	Nested: Child;
}
main :: () {
	container: Container = .{
		Nested=Child.{
			Clear=1
		}
	};
	using,map(rename) procs := container.Nested;
	call := glClear;
}
JAI;
	typed_member := Extended.parse_file(TYPED_MEMBER_SOURCE, filename);
	typed_member_imports := Extended.resolve_file_imports(*typed_member, map_names=test_using_map_fields);
	assert(typed_member.status == .COMPLETE && typed_member_imports.mapped_names.count == 1 && typed_member_imports.unsupported_using_filters.count == 0);
	typed_member_statements := typed_member.root.(*Extended.Parser_Block).statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block.statements;
	assert(typed_member_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == typed_member_imports.mapped_names[0].declaration);
	Extended.release_file_imports(*typed_member_imports);
	Extended.release_parser_tree(*typed_member);
	Extended.release_parser_names(*typed_member);

	INFERRED_MEMBER_SOURCE :: #string JAI
Child :: struct {
	Clear: int;
}
Container :: struct {
	Nested: Child;
}
main :: () {
	container := Container.{
		Nested=Child.{
			Clear=1
		}
	};
	using,map(rename) procs := container.Nested;
	call := glClear;
}
JAI;
	inferred_member := Extended.parse_file(INFERRED_MEMBER_SOURCE, filename);
	inferred_member_imports := Extended.resolve_file_imports(*inferred_member, map_names=test_using_map_fields);
	assert(inferred_member.status == .COMPLETE && inferred_member_imports.mapped_names.count == 1 && inferred_member_imports.unsupported_using_filters.count == 0);
	inferred_member_statements := inferred_member.root.(*Extended.Parser_Block).statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block.statements;
	assert(inferred_member_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == inferred_member_imports.mapped_names[0].declaration);
	Extended.release_file_imports(*inferred_member_imports);
	Extended.release_parser_tree(*inferred_member);
	Extended.release_parser_names(*inferred_member);

	CALLED_MEMBER_SOURCE :: #string JAI
Child :: struct {
	Clear: int;
}
Container :: struct {
	Nested: Child;
}
make :: () -> Container {
	return .{
		Nested=Child.{
			Clear=1
		}
	};
}
main :: () {
	using,map(rename) procs := make().Nested;
	call := glClear;
}
JAI;
	called_member := Extended.parse_file(CALLED_MEMBER_SOURCE, filename);
	called_member_imports := Extended.resolve_file_imports(*called_member, map_names=test_using_map_fields);
	assert(called_member.status == .COMPLETE && called_member_imports.mapped_names.count == 1 && called_member_imports.unsupported_using_filters.count == 0);
	called_member_statements := called_member.root.(*Extended.Parser_Block).statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block.statements;
	assert(called_member_statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == called_member_imports.mapped_names[0].declaration);
	Extended.release_file_imports(*called_member_imports);
	Extended.release_parser_tree(*called_member);
	Extended.release_parser_names(*called_member);

	CAST_MEMBER_SOURCE :: #string JAI
Child :: struct {
	Clear: int;
}
Container :: struct {
	Nested: Child;
}
main :: () {
	original := Container.{
		Nested=Child.{
			Clear=1
		}
	};
	using,map(rename) procs := (cast(Container) original).Nested;
	call := glClear;
}
JAI;
	cast_member := Extended.parse_file(CAST_MEMBER_SOURCE, filename);
	cast_member_imports := Extended.resolve_file_imports(*cast_member, map_names=test_using_map_fields);
	assert(cast_member.status == .COMPLETE && cast_member_imports.mapped_names.count == 1 && cast_member_imports.unsupported_using_filters.count == 0);
	cast_member_statements := cast_member.root.(*Extended.Parser_Block).statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block.statements;
	assert(cast_member_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == cast_member_imports.mapped_names[0].declaration);
	Extended.release_file_imports(*cast_member_imports);
	Extended.release_parser_tree(*cast_member);
	Extended.release_parser_names(*cast_member);

	RUN_MEMBER_SOURCE :: #string JAI
Child :: struct {
	Clear: int;
}
Container :: struct {
	Nested: Child;
}
main :: () {
	using,map(rename) procs := (#run Container.{
		Nested=Child.{
			Clear=1
		}
	}).Nested;
	call := glClear;
}
JAI;
	run_member := Extended.parse_file(RUN_MEMBER_SOURCE, filename);
	run_member_imports := Extended.resolve_file_imports(*run_member, map_names=test_using_map_fields);
	assert(run_member.status == .COMPLETE && run_member_imports.mapped_names.count == 1 && run_member_imports.unsupported_using_filters.count == 0);
	run_member_statements := run_member.root.(*Extended.Parser_Block).statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block.statements;
	assert(run_member_statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == run_member_imports.mapped_names[0].declaration);
	Extended.release_file_imports(*run_member_imports);
	Extended.release_parser_tree(*run_member);
	Extended.release_parser_names(*run_member);

	CONDITIONAL_MEMBER_SOURCE :: #string JAI
Child :: struct {
	Clear: int;
}
Container :: struct {
	Nested: Child;
}
main :: (ready: bool) {
	using,map(rename) procs := (
		ifx ready
			then Container.{
				Nested=Child.{
					Clear=1
				}
			} else Container.{
				Nested=Child.{
					Clear=2
				}
			}
	).Nested;
	call := glClear;
}
JAI;
	conditional_member := Extended.parse_file(CONDITIONAL_MEMBER_SOURCE, filename);
	conditional_member_imports := Extended.resolve_file_imports(*conditional_member, map_names=test_using_map_fields);
	assert(conditional_member.status == .COMPLETE && conditional_member_imports.mapped_names.count == 1 && conditional_member_imports.unsupported_using_filters.count == 0);
	conditional_member_statements := conditional_member.root.(*Extended.Parser_Block).statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block.statements;
	assert(conditional_member_statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == conditional_member_imports.mapped_names[0].declaration);
	Extended.release_file_imports(*conditional_member_imports);
	Extended.release_parser_tree(*conditional_member);
	Extended.release_parser_names(*conditional_member);

	MISMATCHED_MEMBER_SOURCE :: #string JAI
Child :: struct {
	Clear: int;
}
Container :: struct {
	Nested: Child;
}
Other :: struct {
	Nested: Child;
}
main :: (ready: bool) {
	using,map(rename) procs := (
		ifx ready
			then Container.{
				Nested=Child.{
					Clear=1
				}
			} else Other.{
				Nested=Child.{
					Clear=2
				}
			}
	).Nested;
	call := glClear;
}
JAI;
	mismatched_member := Extended.parse_file(MISMATCHED_MEMBER_SOURCE, filename);
	mismatched_member_imports := Extended.resolve_file_imports(*mismatched_member, map_names=test_using_map_fields);
	assert(mismatched_member.status == .COMPLETE && mismatched_member_imports.mapped_names.count == 0 && mismatched_member_imports.unsupported_using_filters.count == 1);
	Extended.release_file_imports(*mismatched_member_imports);
	Extended.release_parser_tree(*mismatched_member);
	Extended.release_parser_names(*mismatched_member);

	STATIC_MEMBER_SOURCE :: #string JAI
Child :: struct {
	Clear: int;
}
Container :: struct {
	Nested: Child;
}
Other :: struct {
	PushMatrix: int;
}
main :: () {
	using,map(rename) procs := (
		#ifx true
			then Container.{
				Nested=Child.{
					Clear=1
				}
			} else Other.{
				PushMatrix=2
			}
	).Nested;
	call := glClear;
}
JAI;
	static_member := Extended.parse_file(STATIC_MEMBER_SOURCE, filename);
	static_member_imports := Extended.resolve_file_imports(*static_member, map_names=test_using_map_fields);
	assert(static_member.status == .COMPLETE && static_member_imports.mapped_names.count == 1 && static_member_imports.unsupported_using_filters.count == 0);
	static_member_statements := static_member.root.(*Extended.Parser_Block).statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block.statements;
	assert(static_member_statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == static_member_imports.mapped_names[0].declaration);
	Extended.release_file_imports(*static_member_imports);
	Extended.release_parser_tree(*static_member);
	Extended.release_parser_names(*static_member);

	OVERLOADED_RUN_MEMBER_SOURCE :: #string JAI
Child :: struct {
	Clear: int;
}
Container :: struct {
	Nested: Child;
}
Other :: struct {
	PushMatrix: int;
}
make :: (number: int) -> Container {
	return .{
		Nested=Child.{
			Clear=1
		}
	};
}
make :: (text: string) -> Other {
	return .{
		PushMatrix=1
	};
}
main :: () {
	using,map(rename) procs := (#run make(1)).Nested;
	call := glClear;
}
JAI;
	overloaded_run_member := Extended.parse_file(OVERLOADED_RUN_MEMBER_SOURCE, filename);
	overloaded_run_member_imports := Extended.resolve_file_imports(*overloaded_run_member, map_names=test_using_map_fields);
	assert(overloaded_run_member.status == .COMPLETE && overloaded_run_member_imports.mapped_names.count == 0 && overloaded_run_member_imports.unsupported_using_filters.count == 1);
	Extended.release_file_imports(*overloaded_run_member_imports);
	Extended.release_parser_tree(*overloaded_run_member);
	Extended.release_parser_names(*overloaded_run_member);

	AMBIGUOUS_CAST_MEMBER_SOURCE :: #string JAI
Child :: struct {
	Clear: int;
}
Container :: struct {
	Nested: Child;
}
Container :: struct {
	PushMatrix: int;
}
main :: () {
	original := Child.{
		Clear=1
	};
	using,map(rename) procs := (cast(Container) original).Nested;
	call := glClear;
}
JAI;
	ambiguous_cast_member := Extended.parse_file(AMBIGUOUS_CAST_MEMBER_SOURCE, filename);
	ambiguous_cast_member_imports := Extended.resolve_file_imports(*ambiguous_cast_member, map_names=test_using_map_fields);
	assert(ambiguous_cast_member.status == .COMPLETE && ambiguous_cast_member_imports.mapped_names.count == 0 && ambiguous_cast_member_imports.unsupported_using_filters.count == 1);
	Extended.release_file_imports(*ambiguous_cast_member_imports);
	Extended.release_parser_tree(*ambiguous_cast_member);
	Extended.release_parser_names(*ambiguous_cast_member);

	CALLED_OVERLOAD_MEMBER_SOURCE :: #string JAI
Child :: struct {
	Clear: int;
}
Container :: struct {
	Nested: Child;
}
Other :: struct {
	PushMatrix: int;
}
make :: (number: int) -> Container {
	return .{
		Nested=Child.{
			Clear=1
		}
	};
}
make :: (text: string) -> Other {
	return .{
		PushMatrix=1
	};
}
main :: () {
	using,map(rename) procs := make(1).Nested;
	call := glClear;
}
JAI;
	called_overload_member := Extended.parse_file(CALLED_OVERLOAD_MEMBER_SOURCE, filename);
	called_overload_member_imports := Extended.resolve_file_imports(*called_overload_member, map_names=test_using_map_fields);
	assert(called_overload_member.status == .COMPLETE && called_overload_member_imports.mapped_names.count == 0 && called_overload_member_imports.unsupported_using_filters.count == 1);
	Extended.release_file_imports(*called_overload_member_imports);
	Extended.release_parser_tree(*called_overload_member);
	Extended.release_parser_names(*called_overload_member);

	CALLED_POLYMORPHIC_MEMBER_SOURCE :: #string JAI
Child :: struct {
	Clear: int;
}
Container :: struct {
	Nested: Child;
}
make :: (value: $T) -> Container {
	return .{
		Nested=Child.{
			Clear=1
		}
	};
}
main :: () {
	using,map(rename) procs := make(1).Nested;
	call := glClear;
}
JAI;
	called_polymorphic_member := Extended.parse_file(CALLED_POLYMORPHIC_MEMBER_SOURCE, filename);
	called_polymorphic_member_imports := Extended.resolve_file_imports(*called_polymorphic_member, map_names=test_using_map_fields);
	assert(called_polymorphic_member.status == .COMPLETE && called_polymorphic_member_imports.mapped_names.count == 1 && called_polymorphic_member_imports.unsupported_using_filters.count == 0);
	Extended.release_file_imports(*called_polymorphic_member_imports);
	Extended.release_parser_tree(*called_polymorphic_member);
	Extended.release_parser_names(*called_polymorphic_member);

	ALIASED_MEMBER_SOURCE :: #string JAI
Child :: struct {
	Clear: int;
}
Container :: struct {
	Nested: Child;
}
main :: () {
	original := Container.{
		Nested=Child.{
			Clear=1
		}
	};
	container := original;
	using,map(rename) procs := container.Nested;
	call := glClear;
}
JAI;
	aliased_member := Extended.parse_file(ALIASED_MEMBER_SOURCE, filename);
	aliased_member_imports := Extended.resolve_file_imports(*aliased_member, map_names=test_using_map_fields);
	assert(aliased_member.status == .COMPLETE && aliased_member_imports.mapped_names.count == 1 && aliased_member_imports.unsupported_using_filters.count == 0);
	aliased_member_statements := aliased_member.root.(*Extended.Parser_Block).statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block.statements;
	assert(aliased_member_statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == aliased_member_imports.mapped_names[0].declaration);
	Extended.release_file_imports(*aliased_member_imports);
	Extended.release_parser_tree(*aliased_member);
	Extended.release_parser_names(*aliased_member);

	CYCLIC_MEMBER_SOURCE :: #string JAI
Child :: struct {
	Clear: int;
}
Container :: struct {
	Nested: Child;
}
main :: () {
	first := second;
	second := first;
	using,map(rename) procs := first.Nested;
	call := glClear;
}
JAI;
	cyclic_member := Extended.parse_file(CYCLIC_MEMBER_SOURCE, filename);
	cyclic_member_imports := Extended.resolve_file_imports(*cyclic_member, map_names=test_using_map_fields);
	assert(cyclic_member.status == .COMPLETE && cyclic_member_imports.mapped_names.count == 0 && cyclic_member_imports.unsupported_using_filters.count == 1);
	Extended.release_file_imports(*cyclic_member_imports);
	Extended.release_parser_tree(*cyclic_member);
	Extended.release_parser_names(*cyclic_member);

	OVERLOADED_MEMBER_SOURCE :: #string JAI
Child :: struct {
	Clear: int;
}
Container :: struct {
	Nested: Child;
}
Other :: struct {
	PushMatrix: int;
}
make :: (number: int) -> Container {
	return .{
		Nested=Child.{
			Clear=1
		}
	};
}
make :: (text: string) -> Other {
	return .{
		PushMatrix=1
	};
}
main :: () {
	original := make(1);
	container := original;
	using,map(rename) procs := container.Nested;
	call := glClear;
}
JAI;
	overloaded_member := Extended.parse_file(OVERLOADED_MEMBER_SOURCE, filename);
	overloaded_member_imports := Extended.resolve_file_imports(*overloaded_member, map_names=test_using_map_fields);
	assert(overloaded_member.status == .COMPLETE && overloaded_member_imports.mapped_names.count == 0 && overloaded_member_imports.unsupported_using_filters.count == 1);
	Extended.release_file_imports(*overloaded_member_imports);
	Extended.release_parser_tree(*overloaded_member);
	Extended.release_parser_names(*overloaded_member);

	AMBIGUOUS_ALIAS_MEMBER_SOURCE :: #string JAI
Child :: struct {
	Clear: int;
}
Container :: struct {
	Nested: Child;
}
main :: () {
	original := Container.{
		Nested=Child.{
			Clear=1
		}
	};
	original := Container.{
		Nested=Child.{
			Clear=2
		}
	};
	container := original;
	using,map(rename) procs := container.Nested;
	call := glClear;
}
JAI;
	ambiguous_alias_member := Extended.parse_file(AMBIGUOUS_ALIAS_MEMBER_SOURCE, filename);
	ambiguous_alias_member_imports := Extended.resolve_file_imports(*ambiguous_alias_member, map_names=test_using_map_fields);
	assert(ambiguous_alias_member.status == .COMPLETE && ambiguous_alias_member_imports.mapped_names.count == 0 && ambiguous_alias_member_imports.unsupported_using_filters.count == 1);
	Extended.release_file_imports(*ambiguous_alias_member_imports);
	Extended.release_parser_tree(*ambiguous_alias_member);
	Extended.release_parser_names(*ambiguous_alias_member);

	AMBIGUOUS_VALUE_MEMBER_SOURCE :: #string JAI
Child :: struct {
	Clear: int;
}
Container :: struct {
	Nested: Child;
}
main :: () {
	container: Container;
	container: Container;
	using,map(rename) procs := container.Nested;
	call := glClear;
}
JAI;
	ambiguous_value_member := Extended.parse_file(AMBIGUOUS_VALUE_MEMBER_SOURCE, filename);
	ambiguous_value_member_imports := Extended.resolve_file_imports(*ambiguous_value_member, map_names=test_using_map_fields);
	assert(ambiguous_value_member.status == .COMPLETE && ambiguous_value_member_imports.mapped_names.count == 0 && ambiguous_value_member_imports.unsupported_using_filters.count == 1);
	Extended.release_file_imports(*ambiguous_value_member_imports);
	Extended.release_parser_tree(*ambiguous_value_member);
	Extended.release_parser_names(*ambiguous_value_member);

	MISSING_MEMBER_SOURCE :: #string JAI
Child :: struct {
	Clear: int;
}
Container :: struct {
	Nested: Child;
}
main :: () {
	using,map(rename) procs := Container.{
		Nested=Child.{
			Clear=1
		}
	}.Missing;
	call := glClear;
}
JAI;
	missing_member := Extended.parse_file(MISSING_MEMBER_SOURCE, filename);
	missing_member_imports := Extended.resolve_file_imports(*missing_member, map_names=test_using_map_fields);
	assert(missing_member.status == .COMPLETE && missing_member_imports.mapped_names.count == 0 && missing_member_imports.unsupported_using_filters.count == 1);
	Extended.release_file_imports(*missing_member_imports);
	Extended.release_parser_tree(*missing_member);
	Extended.release_parser_names(*missing_member);

	AMBIGUOUS_MEMBER_SOURCE :: #string JAI
Child :: struct {
	Clear: int;
}
Child :: struct {
	PushMatrix: int;
}
Container :: struct {
	Nested: Child;
}
main :: () {
	using,map(rename) procs := Container.{
		Nested=Child.{
			Clear=1
		}
	}.Nested;
	call := glClear;
}
JAI;
	ambiguous_member := Extended.parse_file(AMBIGUOUS_MEMBER_SOURCE, filename);
	ambiguous_member_imports := Extended.resolve_file_imports(*ambiguous_member, map_names=test_using_map_fields);
	assert(ambiguous_member.status == .COMPLETE && ambiguous_member_imports.mapped_names.count == 0 && ambiguous_member_imports.unsupported_using_filters.count == 1);
	Extended.release_file_imports(*ambiguous_member_imports);
	Extended.release_parser_tree(*ambiguous_member);
	Extended.release_parser_names(*ambiguous_member);

	UNKNOWN_QUERY_SOURCE :: #string JAI
Procs :: struct {
	Clear: int;
}
main :: () {
	using,map(rename) procs: type_of(missing);
	call := glClear;
}
JAI;
	unknown_query := Extended.parse_file(UNKNOWN_QUERY_SOURCE, filename);
	unknown_query_imports := Extended.resolve_file_imports(*unknown_query, map_names=test_using_map_fields);
	assert(unknown_query.status == .COMPLETE && unknown_query_imports.mapped_names.count == 0 && unknown_query_imports.unsupported_using_filters.count == 1);
	Extended.release_file_imports(*unknown_query_imports);
	Extended.release_parser_tree(*unknown_query);
	Extended.release_parser_names(*unknown_query);

	CYCLIC_QUERY_SOURCE :: #string JAI
main :: () {
	value: type_of(value);
	using,map(rename) procs: type_of(value);
	call := glClear;
}
JAI;
	cyclic_query := Extended.parse_file(CYCLIC_QUERY_SOURCE, filename);
	cyclic_query_imports := Extended.resolve_file_imports(*cyclic_query, map_names=test_using_map_fields);
	assert(cyclic_query.status == .COMPLETE && cyclic_query_imports.mapped_names.count == 0 && cyclic_query_imports.unsupported_using_filters.count == 1);
	Extended.release_file_imports(*cyclic_query_imports);
	Extended.release_parser_tree(*cyclic_query);
	Extended.release_parser_names(*cyclic_query);

	OVERLOADED_QUERY_SOURCE :: #string JAI
Procs :: struct {
	Clear: int;
}
Other :: struct {
	PushMatrix: int;
}
make :: (number: int) -> Procs {
	return .{
		Clear=1
	};
}
make :: (text: string) -> Other {
	return .{
		PushMatrix=1
	};
}
main :: () {
	using,map(rename) procs: type_of(make(1));
	call := glClear;
}
JAI;
	overloaded_query := Extended.parse_file(OVERLOADED_QUERY_SOURCE, filename);
	overloaded_query_imports := Extended.resolve_file_imports(*overloaded_query, map_names=test_using_map_fields);
	assert(overloaded_query.status == .COMPLETE && overloaded_query_imports.mapped_names.count == 0 && overloaded_query_imports.unsupported_using_filters.count == 1);
	Extended.release_file_imports(*overloaded_query_imports);
	Extended.release_parser_tree(*overloaded_query);
	Extended.release_parser_names(*overloaded_query);

	AMBIGUOUS_TYPE_SOURCE :: #string JAI
Procs :: struct {
	Clear: int;
}
Procs :: struct {
	PushMatrix: int;
}
Alias :: Procs;
main :: () {
	using,map(rename) procs: Alias;
	call := glClear;
}
JAI;
	ambiguous_type := Extended.parse_file(AMBIGUOUS_TYPE_SOURCE, filename);
	ambiguous_type_imports := Extended.resolve_file_imports(*ambiguous_type, map_names=test_using_map_fields);
	assert(ambiguous_type.status == .COMPLETE && ambiguous_type_imports.mapped_names.count == 0 && ambiguous_type_imports.unsupported_using_filters.count == 1);
	ambiguous_type_call := ambiguous_type.root.(*Extended.Parser_Block).statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block.statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident);
	assert(ambiguous_type_call.resolved_declaration == null);
	Extended.release_file_imports(*ambiguous_type_imports);
	Extended.release_parser_tree(*ambiguous_type);
	Extended.release_parser_names(*ambiguous_type);

	SHADOWED_TYPE_SOURCE :: #string JAI
Procs :: struct {
	PushMatrix: int;
}
main :: () {
	Procs :: struct {
		Clear: int;
	}
	using,map(rename) procs: Procs;
	call := glClear;
	hidden := PushMatrix;
}
JAI;
	shadowed_type := Extended.parse_file(SHADOWED_TYPE_SOURCE, filename);
	shadowed_type_imports := Extended.resolve_file_imports(*shadowed_type, map_names=test_using_map_fields);
	assert(shadowed_type.status == .COMPLETE && shadowed_type_imports.mapped_names.count == 1 && shadowed_type_imports.mapped_names[0].declaration.name == "Clear");
	shadowed_type_statements := shadowed_type.root.(*Extended.Parser_Block).statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block.statements;
	assert(shadowed_type_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == shadowed_type_imports.mapped_names[0].declaration);
	assert(shadowed_type_statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == null);
	Extended.release_file_imports(*shadowed_type_imports);
	Extended.release_parser_tree(*shadowed_type);
	Extended.release_parser_names(*shadowed_type);

	LITERAL_SOURCE :: #string JAI
Procs :: struct {
	Clear: int;
}
main :: () {
	using,map(rename) procs := Procs.{
		Clear=1
	};
	call := glClear;
}
JAI;
	literal := Extended.parse_file(LITERAL_SOURCE, filename);
	literal_imports := Extended.resolve_file_imports(*literal, map_names=test_using_map_fields, aggregate_fields=test_using_map_decline_fields);
	assert(literal_imports.mapped_names.count == 1);
	literal_call := (
		literal.root.(*Extended.Parser_Block).statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header)
			.body_or_null.block.statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident)
	);
	assert(literal_call.resolved_declaration && literal_call.resolved_declaration.name == "Clear");
	Extended.release_file_imports(*literal_imports);
	Extended.release_parser_tree(*literal);
	Extended.release_parser_names(*literal);

	INFERRED_SOURCE :: #string JAI
Procs :: struct {
	Clear: int;
}
main :: () {
	original := Procs.{
		Clear=1
	};
	using,map(rename) procs := original;
	call := glClear;
}
JAI;
	inferred := Extended.parse_file(INFERRED_SOURCE, filename);
	inferred_imports := Extended.resolve_file_imports(*inferred, map_names=test_using_map_fields);
	assert(inferred_imports.mapped_names.count == 1 && inferred_imports.unsupported_using_filters.count == 0);
	inferred_statements := inferred.root.(*Extended.Parser_Block).statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block.statements;
	assert(inferred_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == inferred_imports.mapped_names[0].declaration);
	Extended.release_file_imports(*inferred_imports);
	Extended.release_parser_tree(*inferred);
	Extended.release_parser_names(*inferred);

	CONDITIONAL_SOURCE :: #string JAI
Procs :: struct {
	Clear: int;
}
main :: (ready: bool) {
	using,map(rename) procs := ifx ready
		then Procs.{
			Clear=1
		} else Procs.{
			Clear=2
		};
	call := glClear;
}
JAI;
	conditional := Extended.parse_file(CONDITIONAL_SOURCE, filename);
	conditional_imports := Extended.resolve_file_imports(*conditional, map_names=test_using_map_fields);
	assert(conditional.status == .COMPLETE && conditional_imports.mapped_names.count == 1 && conditional_imports.unsupported_using_filters.count == 0);
	conditional_statements := conditional.root.(*Extended.Parser_Block).statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block.statements;
	assert(conditional_statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == conditional_imports.mapped_names[0].declaration);
	Extended.release_file_imports(*conditional_imports);
	Extended.release_parser_tree(*conditional);
	Extended.release_parser_names(*conditional);

	CONDITIONAL_ALIAS_SOURCE :: #string JAI
Procs :: struct {
	Clear: int;
}
Alias :: Procs;
main :: (ready: bool) {
	first := Procs.{
		Clear=1
	};
	second := Alias.{
		Clear=2
	};
	using,map(rename) procs := ifx ready then first else second;
	call := glClear;
}
JAI;
	conditional_alias := Extended.parse_file(CONDITIONAL_ALIAS_SOURCE, filename);
	conditional_alias_imports := Extended.resolve_file_imports(*conditional_alias, map_names=test_using_map_fields);
	assert(conditional_alias.status == .COMPLETE && conditional_alias_imports.mapped_names.count == 1 && conditional_alias_imports.unsupported_using_filters.count == 0);
	conditional_alias_statements := conditional_alias.root.(*Extended.Parser_Block).statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block.statements;
	assert(conditional_alias_statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == conditional_alias_imports.mapped_names[0].declaration);
	Extended.release_file_imports(*conditional_alias_imports);
	Extended.release_parser_tree(*conditional_alias);
	Extended.release_parser_names(*conditional_alias);

	MISMATCHED_SOURCE :: #string JAI
Procs :: struct {
	Clear: int;
}
Other :: struct {
	Clear: int;
}
main :: (ready: bool) {
	using,map(rename) procs := ifx ready
		then Procs.{
			Clear=1
		} else Other.{
			Clear=2
		};
	call := glClear;
}
JAI;
	mismatched := Extended.parse_file(MISMATCHED_SOURCE, filename);
	mismatched_imports := Extended.resolve_file_imports(*mismatched, map_names=test_using_map_fields);
	assert(mismatched.status == .COMPLETE && mismatched_imports.mapped_names.count == 0 && mismatched_imports.unsupported_using_filters.count == 1);
	Extended.release_file_imports(*mismatched_imports);
	Extended.release_parser_tree(*mismatched);
	Extended.release_parser_names(*mismatched);

	STATIC_VALUE_SOURCE :: #string JAI
Enabled :: false;
Procs :: struct {
	Clear: int;
}
Other :: struct {
	PushMatrix: int;
}
main :: () {
	using,map(rename) procs := #ifx Enabled
		then Other.{
			PushMatrix=1
		} else Procs.{
			Clear=2
		};
	call := glClear;
	hidden := PushMatrix;
}
JAI;
	static_ifx_value := Extended.parse_file(STATIC_VALUE_SOURCE, filename);
	static_value_imports := Extended.resolve_file_imports(*static_ifx_value, map_names=test_using_map_fields);
	assert(static_ifx_value.status == .COMPLETE && static_value_imports.mapped_names.count == 1);
	static_value_statements := static_ifx_value.root.(*Extended.Parser_Block).statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block.statements;
	assert(static_value_statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == static_value_imports.mapped_names[0].declaration);
	assert(static_value_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == null);
	Extended.release_file_imports(*static_value_imports);
	Extended.release_parser_tree(*static_ifx_value);
	Extended.release_parser_names(*static_ifx_value);

	AMBIGUOUS_STATIC_IFX_SOURCE :: #string JAI
Enabled :: true;
Enabled :: false;
Procs :: struct {
	Clear: int;
}
Other :: struct {
	PushMatrix: int;
}
main :: () {
	using,map(rename) procs := #ifx
	Enabled
		then Procs.{
			Clear=1
		} else Other.{
			PushMatrix=2
		};
	call := glClear;
}
JAI;
	ambiguous_static_ifx := Extended.parse_file(AMBIGUOUS_STATIC_IFX_SOURCE, filename);
	ambiguous_static_ifx_imports := Extended.resolve_file_imports(*ambiguous_static_ifx, map_names=test_using_map_fields);
	assert(ambiguous_static_ifx.status == .COMPLETE && ambiguous_static_ifx_imports.mapped_names.count == 0 && ambiguous_static_ifx_imports.unsupported_using_filters.count == 1);
	Extended.release_file_imports(*ambiguous_static_ifx_imports);
	Extended.release_parser_tree(*ambiguous_static_ifx);
	Extended.release_parser_names(*ambiguous_static_ifx);

	STATIC_THEN_SOURCE :: #string JAI
Procs :: struct {
	Clear: int;
}
Other :: struct {
	PushMatrix: int;
}
main :: () {
	using,map(rename) procs := #ifx true
		then Procs.{
			Clear=1
		} else Other.{
			PushMatrix=2
		};
	call := glClear;
	hidden := PushMatrix;
}
JAI;
	static_then := Extended.parse_file(STATIC_THEN_SOURCE, filename);
	static_then_imports := Extended.resolve_file_imports(*static_then, map_names=test_using_map_fields);
	assert(static_then.status == .COMPLETE && static_then_imports.mapped_names.count == 1 && static_then_imports.mapped_names[0].declaration.name == "Clear");
	static_then_statements := static_then.root.(*Extended.Parser_Block).statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block.statements;
	assert(static_then_statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == static_then_imports.mapped_names[0].declaration);
	assert(static_then_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == null);
	Extended.release_file_imports(*static_then_imports);
	Extended.release_parser_tree(*static_then);
	Extended.release_parser_names(*static_then);

	STATIC_UNKNOWN_SOURCE :: #string JAI
Procs :: struct {
	Clear: int;
}
main :: () {
	using,map(rename) procs := #ifx Unknown
		then Procs.{
			Clear=1
		} else Procs.{
			Clear=2
		};
	call := glClear;
}
JAI;
	static_unknown := Extended.parse_file(STATIC_UNKNOWN_SOURCE, filename);
	static_unknown_imports := Extended.resolve_file_imports(*static_unknown, map_names=test_using_map_fields);
	assert(static_unknown.status == .COMPLETE && static_unknown_imports.mapped_names.count == 0 && static_unknown_imports.unsupported_using_filters.count == 1);
	Extended.release_file_imports(*static_unknown_imports);
	Extended.release_parser_tree(*static_unknown);
	Extended.release_parser_names(*static_unknown);

	CYCLE_SOURCE :: #string JAI
main :: () {
	first := second;
	second := first;
	using,map(rename) procs := first;
	call := glClear;
}
JAI;
	cycle := Extended.parse_file(CYCLE_SOURCE, filename);
	cycle_imports := Extended.resolve_file_imports(*cycle, map_names=test_using_map_fields);
	assert(cycle_imports.mapped_names.count == 0 && cycle_imports.unsupported_using_filters.count == 1);
	cycle_call := (
		cycle.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header)
			.body_or_null.block.statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident)
	);
	assert(cycle_call.resolved_declaration == null);
	Extended.release_file_imports(*cycle_imports);
	Extended.release_parser_tree(*cycle);
	Extended.release_parser_names(*cycle);

	AMBIGUOUS_VALUE_SOURCE :: #string JAI
Procs :: struct {
	Clear: int;
}
Other :: struct {
	PushMatrix: int;
}
main :: () {
	original := Procs.{
		Clear=1
	};
	original := Other.{
		PushMatrix=2
	};
	using,map(rename) procs := original;
	call := glClear;
}
JAI;
	ambiguous_value := Extended.parse_file(AMBIGUOUS_VALUE_SOURCE, filename);
	ambiguous_value_imports := Extended.resolve_file_imports(*ambiguous_value, map_names=test_using_map_fields);
	assert(ambiguous_value.status == .COMPLETE && ambiguous_value_imports.mapped_names.count == 0 && ambiguous_value_imports.unsupported_using_filters.count == 1);
	ambiguous_value_call := (
		ambiguous_value.root.(*Extended.Parser_Block).statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header)
			.body_or_null.block.statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident)
	);
	assert(ambiguous_value_call.resolved_declaration == null);
	Extended.release_file_imports(*ambiguous_value_imports);
	Extended.release_parser_tree(*ambiguous_value);
	Extended.release_parser_names(*ambiguous_value);

	SHADOWED_VALUE_SOURCE :: #string JAI
Procs :: struct {
	Clear: int;
}
Other :: struct {
	PushMatrix: int;
}
original := Other.{
	PushMatrix=1
};
main :: () {
	original := Procs.{
		Clear=2
	};
	using,map(rename) procs := original;
	call := glClear;
}
JAI;
	shadowed_value := Extended.parse_file(SHADOWED_VALUE_SOURCE, filename);
	shadowed_value_imports := Extended.resolve_file_imports(*shadowed_value, map_names=test_using_map_fields);
	assert(shadowed_value.status == .COMPLETE && shadowed_value_imports.mapped_names.count == 1 && shadowed_value_imports.unsupported_using_filters.count == 0);
	shadowed_value_call := (
		shadowed_value.root.(*Extended.Parser_Block).statements[3].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header)
			.body_or_null.block.statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident)
	);
	assert(shadowed_value_call.resolved_declaration == shadowed_value_imports.mapped_names[0].declaration);
	Extended.release_file_imports(*shadowed_value_imports);
	Extended.release_parser_tree(*shadowed_value);
	Extended.release_parser_names(*shadowed_value);

	CAST_SOURCE :: #string JAI
Procs :: struct {
	Clear: int;
}
main :: () {
	original: Procs;
	using,map(rename) procs := cast(Procs) original;
	call := glClear;
}
JAI;
	cast_value := Extended.parse_file(CAST_SOURCE, filename);
	cast_imports := Extended.resolve_file_imports(*cast_value, map_names=test_using_map_fields);
	assert(cast_value.status == .COMPLETE && cast_imports.mapped_names.count == 1);
	cast_statements := cast_value.root.(*Extended.Parser_Block).statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block.statements;
	assert(cast_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == cast_imports.mapped_names[0].declaration);
	Extended.release_file_imports(*cast_imports);
	Extended.release_parser_tree(*cast_value);
	Extended.release_parser_names(*cast_value);

	CALL_SOURCE :: #string JAI
Procs :: struct {
	Clear: int;
}
make :: () -> Procs {
	return .{
		Clear=1
	};
}
main :: () {
	using,map(rename) procs := make();
	call := glClear;
}
JAI;
	call := Extended.parse_file(CALL_SOURCE, filename);
	call_imports := Extended.resolve_file_imports(*call, map_names=test_using_map_fields);
	assert(call.status == .COMPLETE && call_imports.mapped_names.count == 1);
	call_reference := (
		call.root.(*Extended.Parser_Block).statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header)
			.body_or_null.block.statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident)
	);
	assert(call_reference.resolved_declaration && call_reference.resolved_declaration.name == "Clear");
	Extended.release_file_imports(*call_imports);
	Extended.release_parser_tree(*call);
	Extended.release_parser_names(*call);

	ALIASED_CALL_SOURCE :: #string JAI
Procs :: struct {
	Clear: int;
}
make :: () -> Procs {
	return .{
		Clear=1
	};
}
main :: () {
	make_alias :: make;
	using,map(rename) procs := make_alias();
	call := glClear;
}
JAI;
	aliased_call := Extended.parse_file(ALIASED_CALL_SOURCE, filename);
	aliased_call_imports := Extended.resolve_file_imports(*aliased_call, map_names=test_using_map_fields);
	assert(aliased_call.status == .COMPLETE && aliased_call_imports.mapped_names.count == 1 && aliased_call_imports.unsupported_using_filters.count == 0);
	aliased_call_statements := aliased_call.root.(*Extended.Parser_Block).statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block.statements;
	assert(aliased_call_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == aliased_call_imports.mapped_names[0].declaration);
	Extended.release_file_imports(*aliased_call_imports);
	Extended.release_parser_tree(*aliased_call);
	Extended.release_parser_names(*aliased_call);

	complete_call_receiver_sources: []string = .[
		#string JAI
Child :: struct {
	Clear: int;
}
Box :: struct (T: Type) {
	Nested: T;
}
make :: (value: Child) -> Box(Child) {
	return .{Nested=value};
}
main :: () {
	alias :: make;
	using,map(rename) procs := alias(Child.{Clear=1}).Nested;
	call := glClear;
}
JAI,

		#string JAI
Child :: struct {
	Clear: int;
}
Other :: struct {
	PushMatrix: int;
}
Box :: struct (T: Type) {
	Nested: T;
}
make :: (value: string) -> Box(Child) {
	return .{
		Nested=.{
			Clear=1
		}
	};
}
make :: (value: bool) -> Box(Other) {
	return .{
		Nested=.{
			PushMatrix=1
		}
	};
}
main :: () {
	using,map(rename) procs := make("a").Nested;
	call := glClear;
}
JAI,

		#string JAI
Child :: struct {
	Clear: int;
}
Box :: struct (T: Type) {
	Nested: T;
}
main :: () {
	original := Box(Child).{Nested=Child.{Clear=1}};
	using,map(rename) procs := (cast(Box(Child)) original).Nested;
	call := glClear;
}
JAI,

		#string JAI
Child :: struct {
	Clear: int;
}
Box :: struct (T: Type) {
	Nested: T;
}
make :: () -> Box(Child) {
	return .{
		Nested=Child.{
			Clear=1
		}
	};
}
main :: () {
	value: type_of(make());
	using,map(rename) procs := value.Nested;
	call := glClear;
}
JAI
	];
	for complete_call_receiver_sources {
		parsed := Extended.parse_file(it, filename);
		imports := Extended.resolve_file_imports(*parsed, map_names=test_using_map_fields);
		assert(parsed.status == .COMPLETE && imports.mapped_names.count == 1 && imports.unsupported_using_filters.count == 0, "Complete call receiver fixture: %", it);
		Extended.release_file_imports(*imports);
		Extended.release_parser_tree(*parsed);
		Extended.release_parser_names(*parsed);
	}

	unsupported_call_receiver_sources: []string = .[
		#string JAI
Child :: struct {
	Clear: int;
}
Other :: struct {
	PushMatrix: int;
}
Box :: struct (T: Type) {
	Nested: T;
}
make :: (value: string) -> Box(Child) {
	return .{
		Nested=.{
			Clear=1
		}
	};
}
make :: (value: bool) -> Box(Other) {
	return .{
		Nested=.{
			PushMatrix=1
		}
	};
}
main :: () {
	alias :: make;
	using,map(rename) procs := alias("a").Nested;
	call := glClear;
}
JAI,

		#string JAI
Child :: struct {
	Clear: int;
}
Other :: struct {
	PushMatrix: int;
}
Box :: struct (T: Type) {
	Nested: T;
}
make :: (value: string) -> Box(Child) {
	return .{
		Nested=.{
			Clear=1
		}
	};
}
make :: (value: bool) -> Box(Other) {
	return .{
		Nested=.{
			PushMatrix=1
		}
	};
}
main :: () {
	using,map(rename) procs := make(unknown).Nested;
	call := glClear;
}
JAI,

		#string JAI
Child :: struct {
	Clear: int;
}
Box :: struct (T: Type) {
	Nested: T;
}
make :: () -> Box(Child) {
	return .{
		Nested=Child.{
			Clear=1
		}
	};
}
main :: () {
	value: type_of(missing());
	using,map(rename) procs := value.Nested;
	call := glClear;
}
JAI,

		#string JAI
Child :: struct {
	Clear: int;
}
Box :: struct (T: Type) {
	Nested: T;
}
main :: () {
	original := Box(Child).{Nested=Child.{Clear=1}};
	using,map(rename) procs := (cast(Box(Missing)) original).Nested;
	call := glClear;
}
JAI
	];
	for unsupported_call_receiver_sources {
		parsed := Extended.parse_file(it, filename);
		imports := Extended.resolve_file_imports(*parsed, map_names=test_using_map_fields);
		assert(parsed.status == .COMPLETE && imports.mapped_names.count == 0 && imports.unsupported_using_filters.count == 1, "Unsupported call receiver fixture: %", it);
		Extended.release_file_imports(*imports);
		Extended.release_parser_tree(*parsed);
		Extended.release_parser_names(*parsed);
	}

	complete_receiver_inventory_sources: []string = .[
		#string JAI
Child :: struct {
	Clear: int;
}
Box :: struct (T: Type) {
	Nested: T;
}
main :: () {
	using,map(rename) procs := Box(Child).{Nested=Child.{Clear=1}}.Nested;
	call := glClear;
}
JAI
	];
	for complete_receiver_inventory_sources {
		parsed := Extended.parse_file(it, filename);
		imports := Extended.resolve_file_imports(*parsed, map_names=test_using_map_fields);
		assert(parsed.status == .COMPLETE && imports.mapped_names.count == 1 && imports.unsupported_using_filters.count == 0, "Complete receiver inventory fixture: %", it);
		Extended.release_file_imports(*imports);
		Extended.release_parser_tree(*parsed);
		Extended.release_parser_names(*parsed);
	}

	unsupported_receiver_inventory_sources: []string = .[
		#string JAI
Child :: struct {
	Clear: int;
}
Box :: struct (T: Type) {
	Nested: T;
}
main :: () {
	box := Box(Child).{Nested=Child.{Clear=1}};
	pointer := *box;
	using,map(rename) procs := pointer.*.Nested;
	call := glClear;
}
JAI,

		#string JAI
Child :: struct {
	Clear: int;
}
Box :: struct (T: Type) {
	Nested: T;
}
main :: () {
	boxes: [1] Box(Child) = .[Box(Child).{Nested=Child.{Clear=1}}];
	using,map(rename) procs := boxes[0].Nested;
	call := glClear;
}
JAI,

		#string JAI
main :: () {
	scalar := 1;
	using,map(rename) procs := scalar.Nested;
	call := glClear;
}
JAI
	];
	for unsupported_receiver_inventory_sources {
		parsed := Extended.parse_file(it, filename);
		imports := Extended.resolve_file_imports(*parsed, map_names=test_using_map_fields);
		assert(parsed.status == .COMPLETE && imports.mapped_names.count == 0 && imports.unsupported_using_filters.count == 1, "Unsupported receiver inventory fixture: %", it);
		Extended.release_file_imports(*imports);
		Extended.release_parser_tree(*parsed);
		Extended.release_parser_names(*parsed);
	}

	OVERLOADED_ALIAS_SOURCE :: #string JAI
Procs :: struct {
	Clear: int;
}
Other :: struct {
	PushMatrix: int;
}
make :: (number: int) -> Procs {
	return .{
		Clear=1
	};
}
make :: (text: string) -> Other {
	return .{
		PushMatrix=1
	};
}
main :: () {
	make_alias :: make;
	using,map(rename) procs := make_alias(1);
	call := glClear;
}
JAI;
	overloaded_alias := Extended.parse_file(OVERLOADED_ALIAS_SOURCE, filename);
	OVERLOADED_ALIAS_IMPORTS := Extended.resolve_file_imports(*overloaded_alias, map_names=test_using_map_fields);
	assert(overloaded_alias.status == .COMPLETE && OVERLOADED_ALIAS_IMPORTS.mapped_names.count == 0 && OVERLOADED_ALIAS_IMPORTS.unsupported_using_filters.count == 1);
	Extended.release_file_imports(*OVERLOADED_ALIAS_IMPORTS);
	Extended.release_parser_tree(*overloaded_alias);
	Extended.release_parser_names(*overloaded_alias);

	POLYMORPHIC_ALIAS_SOURCE :: #string JAI
Procs :: struct {
	Clear: int;
}
make :: (value: $T) -> Procs {
	return .{
		Clear=1
	};
}
main :: () {
	make_alias :: make;
	using,map(rename) procs := make_alias(1);
	call := glClear;
}
JAI;
	polymorphic_alias := Extended.parse_file(POLYMORPHIC_ALIAS_SOURCE, filename);
	POLYMORPHIC_ALIAS_IMPORTS := Extended.resolve_file_imports(*polymorphic_alias, map_names=test_using_map_fields);
	assert(polymorphic_alias.status == .COMPLETE && POLYMORPHIC_ALIAS_IMPORTS.mapped_names.count == 1 && POLYMORPHIC_ALIAS_IMPORTS.unsupported_using_filters.count == 0);
	Extended.release_file_imports(*POLYMORPHIC_ALIAS_IMPORTS);
	Extended.release_parser_tree(*polymorphic_alias);
	Extended.release_parser_names(*polymorphic_alias);

	MUTABLE_PROCEDURE_SOURCE :: #string JAI
Procs :: struct {
	Clear: int;
}
make :: () -> Procs {
	return .{
		Clear=1
	};
}
main :: () {
	make_alias := make;
	using,map(rename) procs := make_alias();
	call := glClear;
}
JAI;
	mutable_procedure := Extended.parse_file(MUTABLE_PROCEDURE_SOURCE, filename);
	MUTABLE_PROCEDURE_IMPORTS := Extended.resolve_file_imports(*mutable_procedure, map_names=test_using_map_fields);
	assert(mutable_procedure.status == .COMPLETE && MUTABLE_PROCEDURE_IMPORTS.mapped_names.count == 0 && MUTABLE_PROCEDURE_IMPORTS.unsupported_using_filters.count == 1);
	Extended.release_file_imports(*MUTABLE_PROCEDURE_IMPORTS);
	Extended.release_parser_tree(*mutable_procedure);
	Extended.release_parser_names(*mutable_procedure);

	OVERLOADED_SOURCE :: #string JAI
Procs :: struct {
	Clear: int;
}
Other :: struct {
	PushMatrix: int;
}
make :: (number: int) -> Procs {
	return .{
		Clear=1
	};
}
make :: (text: string) -> Other {
	return .{
		PushMatrix=1
	};
}
main :: () {
	using,map(rename) procs := make("text");
	call := glClear;
}
JAI;
	overloaded := Extended.parse_file(OVERLOADED_SOURCE, filename);
	overloaded_imports := Extended.resolve_file_imports(*overloaded, map_names=test_using_map_fields);
	assert(
		overloaded.status == .COMPLETE
		&& overloaded_imports.mapped_names.count == 1
		&& overloaded_imports.mapped_names[0].source_name == "PushMatrix"
		&& !overloaded_imports.mapped_names[0].exported_name
		&& overloaded_imports.unsupported_using_filters.count == 0
	);
	overloaded_call := (
		overloaded.root.(*Extended.Parser_Block).statements[4].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header)
			.body_or_null.block.statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident)
	);
	assert(overloaded_call.resolved_declaration == null);
	Extended.release_file_imports(*overloaded_imports);
	Extended.release_parser_tree(*overloaded);
	Extended.release_parser_names(*overloaded);

	CONCRETE_OVERLOAD_SOURCE :: #string JAI
Input :: struct {
	Value: int;
}
Alternate :: struct {
	Value: int;
}
Procs :: struct {
	Clear: int;
}
Other :: struct {
	PushMatrix: int;
}
make :: (input: Input) -> Procs {
	return .{
		Clear=1
	};
}
make :: (input: Alternate) -> Other {
	return .{
		PushMatrix=1
	};
}
main :: () {
	using,map(rename) procs := make(Input.{
		Value=1
	});
	call := glClear;
}
JAI;
	concrete_overload := Extended.parse_file(CONCRETE_OVERLOAD_SOURCE, filename);
	concrete_overload_imports := Extended.resolve_file_imports(*concrete_overload, map_names=test_using_map_fields);
	assert(concrete_overload.status == .COMPLETE && concrete_overload_imports.mapped_names.count == 1 && concrete_overload_imports.unsupported_using_filters.count == 0);
	concrete_overload_statements := concrete_overload.root.(*Extended.Parser_Block).statements[6].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block.statements;
	assert(concrete_overload_statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == concrete_overload_imports.mapped_names[0].declaration);
	Extended.release_file_imports(*concrete_overload_imports);
	Extended.release_parser_tree(*concrete_overload);
	Extended.release_parser_names(*concrete_overload);

	INSTANCIATED_OVERLOAD_SOURCE :: #string JAI
Input :: struct {
	Value: int;
}
Alternate :: struct {
	Value: int;
}
Box :: struct (T: Type) {
	Value: T;
}
Procs :: struct {
	Clear: int;
}
Other :: struct {
	PushMatrix: int;
}
make :: (input: Box(Input)) -> Procs {
	return .{
		Clear=1
	};
}
make :: (input: Box(Alternate)) -> Other {
	return .{
		PushMatrix=1
	};
}
main :: () {
	using,map(rename) procs := make(
		Box(Input).{
			Value=Input.{
				Value=1
			}
		}
	);
	call := glClear;
}
JAI;
	instantiated_overload := Extended.parse_file(INSTANCIATED_OVERLOAD_SOURCE, filename);
	instantiated_overload_imports := Extended.resolve_file_imports(*instantiated_overload, map_names=test_using_map_fields);
	assert(instantiated_overload.status == .COMPLETE && instantiated_overload_imports.mapped_names.count == 1 && instantiated_overload_imports.unsupported_using_filters.count == 0);
	Extended.release_file_imports(*instantiated_overload_imports);
	Extended.release_parser_tree(*instantiated_overload);
	Extended.release_parser_names(*instantiated_overload);

	AGGREGATE_CONVERSION_SOURCE :: #string JAI
Base :: struct {
	Value: int;
}
Wrapper :: struct {
	#as using base: Base;
}
Procs :: struct {
	Clear: int;
}
Other :: struct {
	PushMatrix: int;
}
make :: (value: Base) -> Procs {
	return .{Clear=1};
}
make :: (value: string) -> Other {
	return .{PushMatrix=1};
}
main :: () {
	using,map(rename) procs := make(Wrapper.{base=Base.{Value=1}});
	call := glClear;
}
JAI
	aggregate_conversion := Extended.parse_file(AGGREGATE_CONVERSION_SOURCE, filename);
	aggregate_conversion_imports := Extended.resolve_file_imports(*aggregate_conversion, map_names=test_using_map_fields);
	assert(
		aggregate_conversion.status == .COMPLETE
		&& aggregate_conversion_imports.mapped_names.count == 1
		&& aggregate_conversion_imports.mapped_names[0].source_name == "Clear"
		&& aggregate_conversion_imports.unsupported_using_filters.count == 0
	);
	Extended.release_file_imports(*aggregate_conversion_imports);
	Extended.release_parser_tree(*aggregate_conversion);
	Extended.release_parser_names(*aggregate_conversion);

	AGGREGATE_EXACT_RANK_SOURCE :: #string JAI
Base :: struct {
	Value: int;
}
Wrapper :: struct {
	#as using base: Base;
}
Procs :: struct {
	Clear: int;
}
Other :: struct {
	PushMatrix: int;
}
make :: (value: Base) -> Other {
	return .{PushMatrix=1};
}
make :: (value: Wrapper) -> Procs {
	return .{Clear=1};
}
main :: () {
	using,map(rename) procs := make(Wrapper.{base=Base.{Value=1}});
	call := glClear;
}
JAI
	aggregate_exact_rank := Extended.parse_file(AGGREGATE_EXACT_RANK_SOURCE, filename);
	aggregate_exact_rank_imports := Extended.resolve_file_imports(*aggregate_exact_rank, map_names=test_using_map_fields);
	assert(
		aggregate_exact_rank.status == .COMPLETE
		&& aggregate_exact_rank_imports.mapped_names.count == 1
		&& aggregate_exact_rank_imports.mapped_names[0].source_name == "Clear"
		&& aggregate_exact_rank_imports.unsupported_using_filters.count == 0
	);
	Extended.release_file_imports(*aggregate_exact_rank_imports);
	Extended.release_parser_tree(*aggregate_exact_rank);
	Extended.release_parser_names(*aggregate_exact_rank);

	ARY_OVERLOAD_SOURCE :: #string JAI
Input :: struct {
	Value: int;
}
Procs :: struct {
	Clear: int;
}
Other :: struct {
	PushMatrix: int;
}
make :: () -> Other {
	return .{
		PushMatrix=1
	};
}
make :: (input: Input) -> Procs {
	return .{
		Clear=1
	};
}
main :: () {
	using,map(rename) procs := make(Input.{
		Value=1
	});
	call := glClear;
}
JAI;
	ary_overload := Extended.parse_file(ARY_OVERLOAD_SOURCE, filename);
	ary_overload_imports := Extended.resolve_file_imports(*ary_overload, map_names=test_using_map_fields);
	assert(ary_overload.status == .COMPLETE && ary_overload_imports.mapped_names.count == 1 && ary_overload_imports.unsupported_using_filters.count == 0);
	Extended.release_file_imports(*ary_overload_imports);
	Extended.release_parser_tree(*ary_overload);
	Extended.release_parser_names(*ary_overload);

	PRIMITIVE_OVERLOAD_SOURCE :: #string JAI
Procs :: struct {
	Clear: int;
}
Other :: struct {
	PushMatrix: int;
}
make :: (number: s64) -> Other {
	return .{
		PushMatrix=1
	};
}
make :: (text: string) -> Procs {
	return .{
		Clear=1
	};
}
main :: () {
	using,map(rename) procs := make("text");
	call := glClear;
}
JAI;
	primitive_overload := Extended.parse_file(PRIMITIVE_OVERLOAD_SOURCE, filename);
	primitive_overload_imports := Extended.resolve_file_imports(*primitive_overload, map_names=test_using_map_fields);
	assert(primitive_overload.status == .COMPLETE && primitive_overload_imports.mapped_names.count == 1 && primitive_overload_imports.unsupported_using_filters.count == 0);
	Extended.release_file_imports(*primitive_overload_imports);
	Extended.release_parser_tree(*primitive_overload);
	Extended.release_parser_names(*primitive_overload);

	INTEGER_OVERLOAD_SOURCE :: #string JAI
Procs :: struct {
	Clear: int;
}
Other :: struct {
	PushMatrix: int;
}
make :: (number: s64) -> Procs {
	return .{
		Clear=1
	};
}
make :: (text: string) -> Other {
	return .{
		PushMatrix=1
	};
}
main :: () {
	using,map(rename) procs := make(1);
	call := glClear;
}
JAI;
	integer_overload := Extended.parse_file(INTEGER_OVERLOAD_SOURCE, filename);
	integer_overload_imports := Extended.resolve_file_imports(*integer_overload, map_names=test_using_map_fields);
	assert(integer_overload.status == .COMPLETE && integer_overload_imports.mapped_names.count == 1 && integer_overload_imports.unsupported_using_filters.count == 0);
	Extended.release_file_imports(*integer_overload_imports);
	Extended.release_parser_tree(*integer_overload);
	Extended.release_parser_names(*integer_overload);

	NUMERIC_RANK_SOURCE :: #string JAI
Procs :: struct {
	Clear: int;
}
Other :: struct {
	PushMatrix: int;
}
make :: (number: float64) -> Other {
	return .{PushMatrix=1};
}
make :: (number: s64) -> Procs {
	return .{Clear=1};
}
main :: () {
	using,map(rename) procs := make(1);
	call := glClear;
}
JAI
	numeric_rank := Extended.parse_file(NUMERIC_RANK_SOURCE, filename);
	numeric_rank_imports := Extended.resolve_file_imports(*numeric_rank, map_names=test_using_map_fields);
	assert(numeric_rank.status == .COMPLETE && numeric_rank_imports.mapped_names.count == 1 && numeric_rank_imports.mapped_names[0].source_name == "Clear" && numeric_rank_imports.unsupported_using_filters.count == 0);
	Extended.release_file_imports(*numeric_rank_imports);
	Extended.release_parser_tree(*numeric_rank);
	Extended.release_parser_names(*numeric_rank);

	CONVERTED_RANK_SOURCE :: #string JAI
Procs :: struct {
	Clear: int;
}
Other :: struct {
	PushMatrix: int;
}
make :: (number: float64) -> Procs {
	return .{Clear=1};
}
make :: (text: string) -> Other {
	return .{PushMatrix=1};
}
main :: () {
	using,map(rename) procs := make(1);
	call := glClear;
}
JAI
	converted_rank := Extended.parse_file(CONVERTED_RANK_SOURCE, filename);
	converted_rank_imports := Extended.resolve_file_imports(*converted_rank, map_names=test_using_map_fields);
	assert(
		converted_rank.status == .COMPLETE
		&& converted_rank_imports.mapped_names.count == 1
		&& converted_rank_imports.mapped_names[0].source_name == "Clear"
		&& converted_rank_imports.unsupported_using_filters.count == 0
	);
	Extended.release_file_imports(*converted_rank_imports);
	Extended.release_parser_tree(*converted_rank);
	Extended.release_parser_names(*converted_rank);

	FLOAT_RANK_SOURCE :: #string JAI
Procs :: struct {
	Clear: int;
}
Other :: struct {
	PushMatrix: int;
}
make :: (number: float64) -> Procs {
	return .{Clear=1};
}
make :: (text: string) -> Other {
	return .{PushMatrix=1};
}
main :: () {
	using,map(rename) procs := make(1.5);
	call := glClear;
}
JAI
	float_rank := Extended.parse_file(FLOAT_RANK_SOURCE, filename);
	float_rank_imports := Extended.resolve_file_imports(*float_rank, map_names=test_using_map_fields);
	assert(float_rank.status == .COMPLETE && float_rank_imports.mapped_names.count == 1 && float_rank_imports.mapped_names[0].source_name == "Clear" && float_rank_imports.unsupported_using_filters.count == 0);
	Extended.release_file_imports(*float_rank_imports);
	Extended.release_parser_tree(*float_rank);
	Extended.release_parser_names(*float_rank);

	NAMED_OVERLOAD_SOURCE :: #string JAI
Input :: struct {
	Value: int;
}
Alternate :: struct {
	Value: int;
}
Procs :: struct {
	Clear: int;
}
Other :: struct {
	PushMatrix: int;
}
make :: (input: Input) -> Procs {
	return .{
		Clear=1
	};
}
make :: (input: Alternate) -> Other {
	return .{
		PushMatrix=1
	};
}
main :: () {
	using,map(rename) procs := make(input=Input.{
		Value=1
	});
	call := glClear;
}
JAI;
	named_overload := Extended.parse_file(NAMED_OVERLOAD_SOURCE, filename);
	named_overload_imports := Extended.resolve_file_imports(*named_overload, map_names=test_using_map_fields);
	assert(named_overload.status == .COMPLETE && named_overload_imports.mapped_names.count == 1 && named_overload_imports.unsupported_using_filters.count == 0);
	Extended.release_file_imports(*named_overload_imports);
	Extended.release_parser_tree(*named_overload);
	Extended.release_parser_names(*named_overload);

	DEFAULTED_OVERLOAD_SOURCE :: #string JAI
Input :: struct {
	Value: int;
}
Procs :: struct {
	Clear: int;
}
Other :: struct {
	PushMatrix: int;
}
make :: (input: Input, enabled: bool = true) -> Procs {
	return .{Clear=1};
}
make :: (input: Input, required: string) -> Other {
	return .{PushMatrix=1};
}
main :: () {
	using,map(rename) procs := make(input=Input.{Value=1});
	call := glClear;
}
JAI
	defaulted_overload := Extended.parse_file(DEFAULTED_OVERLOAD_SOURCE, filename);
	defaulted_overload_imports := Extended.resolve_file_imports(*defaulted_overload, map_names=test_using_map_fields);
	assert(
		defaulted_overload.status == .COMPLETE
		&& defaulted_overload_imports.mapped_names.count == 1
		&& defaulted_overload_imports.mapped_names[0].source_name == "Clear"
		&& defaulted_overload_imports.unsupported_using_filters.count == 0
	);
	Extended.release_file_imports(*defaulted_overload_imports);
	Extended.release_parser_tree(*defaulted_overload);
	Extended.release_parser_names(*defaulted_overload);

	DEFAULTED_POSITIONAL_SOURCE :: #string JAI
Input :: struct {
	Value: int;
}
Procs :: struct {
	Clear: int;
}
Other :: struct {
	PushMatrix: int;
}
make :: (input: Input, enabled: bool = true) -> Procs {
	return .{Clear=1};
}
make :: (input: Input, required: string) -> Other {
	return .{PushMatrix=1};
}
main :: () {
	using,map(rename) procs := make(Input.{Value=1});
	call := glClear;
}
JAI
	defaulted_positional := Extended.parse_file(DEFAULTED_POSITIONAL_SOURCE, filename);
	defaulted_positional_imports := Extended.resolve_file_imports(*defaulted_positional, map_names=test_using_map_fields);
	assert(
		defaulted_positional.status == .COMPLETE
		&& defaulted_positional_imports.mapped_names.count == 1
		&& defaulted_positional_imports.mapped_names[0].source_name == "Clear"
		&& defaulted_positional_imports.unsupported_using_filters.count == 0
	);
	Extended.release_file_imports(*defaulted_positional_imports);
	Extended.release_parser_tree(*defaulted_positional);
	Extended.release_parser_names(*defaulted_positional);

	TYPED_PRIMITIVE_SOURCE :: #string JAI
Procs :: struct {
	Clear: int;
}
Other :: struct {
	PushMatrix: int;
}
make :: (number: s64) -> Other {
	return .{
		PushMatrix=1
	};
}
make :: (text: string) -> Procs {
	return .{
		Clear=1
	};
}
main :: () {
	original: string = "text";
	text := original;
	using,map(rename) procs := make(text);
	call := glClear;
}
JAI;
	typed_primitive := Extended.parse_file(TYPED_PRIMITIVE_SOURCE, filename);
	typed_primitive_imports := Extended.resolve_file_imports(*typed_primitive, map_names=test_using_map_fields);
	assert(typed_primitive.status == .COMPLETE && typed_primitive_imports.mapped_names.count == 1 && typed_primitive_imports.unsupported_using_filters.count == 0);
	Extended.release_file_imports(*typed_primitive_imports);
	Extended.release_parser_tree(*typed_primitive);
	Extended.release_parser_names(*typed_primitive);

	LATER_MISMATCH_SOURCE :: #string JAI
Input :: struct {
	Value: int;
}
Alternate :: struct {
	Value: int;
}
Procs :: struct {
	Clear: int;
}
Other :: struct {
	PushMatrix: int;
}
make :: (number: float64, input: Input) -> Other {
	return .{
		PushMatrix=1
	};
}
make :: (number: s64, input: Alternate) -> Procs {
	return .{
		Clear=1
	};
}
main :: () {
	using,map(rename) procs := make(1, Alternate.{
		Value=1
	});
	call := glClear;
}
JAI;
	later_mismatch := Extended.parse_file(LATER_MISMATCH_SOURCE, filename);
	later_mismatch_imports := Extended.resolve_file_imports(*later_mismatch, map_names=test_using_map_fields);
	assert(later_mismatch.status == .COMPLETE && later_mismatch_imports.mapped_names.count == 1 && later_mismatch_imports.unsupported_using_filters.count == 0);
	Extended.release_file_imports(*later_mismatch_imports);
	Extended.release_parser_tree(*later_mismatch);
	Extended.release_parser_names(*later_mismatch);

	CALLED_ALIAS_SOURCE :: #string JAI
Child :: struct {
	Clear: int;
}
Container :: struct {
	Nested: Child;
}
Alternate :: struct {
	PushMatrix: int;
}
make :: (ready: bool) -> Container {
	return .{
		Nested=Child.{
			Clear=1
		}
	};
}
make :: (ready: string) -> Alternate {
	return .{
		PushMatrix=1
	};
}
main :: () {
	original := make(true);
	value := original;
	using,map(rename) procs := value.Nested;
	call := glClear;
}
JAI;
	called_alias := Extended.parse_file(CALLED_ALIAS_SOURCE, filename);
	called_alias_imports := Extended.resolve_file_imports(*called_alias, map_names=test_using_map_fields);
	assert(called_alias.status == .COMPLETE && called_alias_imports.mapped_names.count == 1 && called_alias_imports.unsupported_using_filters.count == 0);
	Extended.release_file_imports(*called_alias_imports);
	Extended.release_parser_tree(*called_alias);
	Extended.release_parser_names(*called_alias);

	SHADOWED_OVERLOADS_SOURCE :: #string JAI
Procs :: struct {
	Clear: int;
}
Other :: struct {
	PushMatrix: int;
}
make :: (ready: bool) -> Other {
	return .{
		PushMatrix=1
	};
}
main :: () {
	make :: (ready: bool) -> Procs {
		return .{
			Clear=1
		};
	}
	make :: (ready: string) -> Other {
		return .{
			PushMatrix=2
		};
	}
	using,map(rename) procs := make(true);
	call := glClear;
}
JAI;
	shadowed_overloads := Extended.parse_file(SHADOWED_OVERLOADS_SOURCE, filename);
	shadowed_overloads_imports := Extended.resolve_file_imports(*shadowed_overloads, map_names=test_using_map_fields);
	assert(shadowed_overloads.status == .COMPLETE && shadowed_overloads_imports.mapped_names.count == 1 && shadowed_overloads_imports.mapped_names[0].source_name == "Clear" && shadowed_overloads_imports.unsupported_using_filters.count == 0);
	Extended.release_file_imports(*shadowed_overloads_imports);
	Extended.release_parser_tree(*shadowed_overloads);
	Extended.release_parser_names(*shadowed_overloads);

	unsupported_calls: [] string = .[
		#string JAI
First :: struct {
	Value: int;
}
Second :: struct {
	Value: int;
}
Wrapper :: struct {
	#as using first: First;
	#as using second: Second;
}
Procs :: struct {
	Clear: int;
}
Other :: struct {
	PushMatrix: int;
}
make :: (value: First) -> Procs {
	return .{
		Clear=1
	};
}
make :: (value: Second) -> Other {
	return .{
		PushMatrix=1
	};
}
main :: () {
	using,map(rename) procs := make(Wrapper.{
		first=First.{
			Value=1
		}, second=Second.{
			Value=2
		}
	});
	call := glClear;
}
JAI,

		#string JAI
Procs :: struct {
	Clear: int;
}
make :: (input: int, enabled: bool = Missing) -> Procs {
	return .{
		Clear=1
	};
}
main :: () {
	using,map(rename) procs := make(1);
	call := glClear;
}
JAI,

		#string JAI
Procs :: struct {
	Clear: int;
}
make :: (input: int, required: string) -> Procs {
	return .{
		Clear=1
	};
}
main :: () {
	using,map(rename) procs := make(input=1);
	call := glClear;
}
JAI,

		#string JAI
Input :: struct {
	Value: int;
}
Procs :: struct {
	Clear: int;
}
Other :: struct {
	PushMatrix: int;
}
make :: (input: Input) -> Procs {
	return .{Clear=1};
}
make :: (input: Input) -> Other {
	return .{PushMatrix=1};
}
main :: () {
	using,map(rename) procs := make(Input.{Value=1});
	call := glClear;
}
JAI,

		#string JAI
Child :: struct {
	Clear: int;
}
Other :: struct {
	PushMatrix: int;
}
Box :: struct (T: Type) {
	Nested: T;
}
wrap :: (value: $T) -> Box(T) {
	return .{
		Nested=value
	};
}
main :: (choose: bool) {
	using,map(rename) procs := (
		ifx choose
			then wrap(Child.{
				Clear=1
			}) else Box(Other).{
				Nested=Other.{
					PushMatrix=2
				}
			}
	).Nested;
	call := glClear;
}
JAI,

		#string JAI
Child :: struct {
	Clear: int;
	#if Unknown {
		Hidden: int;
	}
}
Box :: struct (T: Type) {
	Nested: T;
}
wrap :: (value: $T) -> Box(T) {
	return .{
		Nested=value
	};
}
main :: () {
	using,map(rename) procs := wrap(
		Child.{
			Clear=1
		}
	).Nested;
	call := glClear;
}
JAI,

		#string JAI
Child :: struct {
	Clear: int;
}
make :: (value: $T/Child) -> T {
	return value;
}
main :: () {
	using,map(rename) procs := make(
		Child.{
			Clear=1
		}
	);
	call := glClear;
}
JAI,

		#string JAI
Child :: struct {
	Clear: int;
}
make :: (value: $T, other: $U) -> T {
	return value;
}
main :: () {
	using,map(rename) procs := make(
		Child.{
			Clear=1
		}
	);
	call := glClear;
}
JAI,

		#string JAI
Child :: struct {
	Clear: int;
	#if Unknown {
		Hidden: int;
	}
}
make :: (value: $T) -> T {
	return value;
}
main :: () {
	using,map(rename) procs := make(
		Child.{
			Clear=1
		}
	);
	call := glClear;
}
JAI,

		#string JAI
Child :: struct {
	Clear: int;
}
Container :: struct {
	Nested: Child;
}
Other :: struct {
	PushMatrix: int;
}
make :: (ready: bool) -> Container {
	return .{
		Nested=Child.{
			Clear=1
		}
	};
}
make :: (ready: bool) -> Other {
	return .{
		PushMatrix=1
	};
}
main :: () {
	original := make(true);
	value := original;
	using,map(rename) procs := value.Nested;
	call := glClear;
}
JAI,

		#string JAI
Child :: struct {
	Clear: int;
}
Container :: struct {
	Nested: Child;
	#if Unknown {
		Hidden: int;
	}
}
make :: () -> Container {
	return .{
		Nested=Child.{
			Clear=1
		}
	};
}
main :: () {
	original := make();
	value := original;
	using,map(rename) procs := value.Nested;
	call := glClear;
}
JAI,

		#string JAI
Input :: struct {
	Value: int;
}
Procs :: struct {
	Clear: int;
}
Other :: struct {
	PushMatrix: int;
}
make :: (input: Input) -> Procs {
	return .{
		Clear=1
	};
}
make :: (input: Missing) -> Other {
	return .{
		PushMatrix=1
	};
}
main :: () {
	using,map(rename) procs := make(
		Input.{
			Value=1
		}
	);
	call := glClear;
}
JAI,

		#string JAI
Procs :: struct {
	Clear: int;
}
make :: () -> Procs {
	return .{
		Clear=1
	};
}
main :: () {
	using,map(rename) procs := make(1);
	call := glClear;
}
JAI,

		#string JAI
Procs :: struct {
	Clear: int;
}
identity :: (value: $T) -> T {
	return value;
}
main :: () {
	using,map(rename) procs := identity(missing);
	call := glClear;
}
JAI,

		#string JAI
Procs :: struct {
	Clear: int;
}
Alias := Procs;
main :: () {
	using,map(rename) procs: Alias;
	call := glClear;
}
JAI,

		#string JAI
Child :: struct {
	Clear: int;
}
Other :: struct {
	PushMatrix: int;
}
Box :: struct (T: Type) {
	Nested: T;
}
main :: (choose: bool) {
	using,map(rename) procs := (
		ifx choose
			then Box(Child).{
				Nested=Child.{
					Clear=1
				}
			} else Box(Other).{
				Nested=Other.{
					PushMatrix=2
				}
			}
	).Nested;
	call := glClear;
}
JAI,

		#string JAI
Child :: struct {
	Clear: int;
}
Other :: struct {
	PushMatrix: int;
}
Box :: struct (T: Type) {
	Clear: int;
	Nested: T;
}
main :: (choose: bool) {
	left: type_of(Box(Child).{
		Nested=Child.{
			Clear=1
		}
	});
	right: type_of(Box(Other).{
		Nested=Other.{
			PushMatrix=2
		}
	});
	using,map(rename) box := ifx choose then left else right;
	call := glClear;
}
JAI,

	];
	for unsupported_calls {
		parsed_call := Extended.parse_file(it, filename);
		call_imports := Extended.resolve_file_imports(*parsed_call, map_names=test_using_map_fields);
		assert(parsed_call.status == .COMPLETE && call_imports.mapped_names.count == 0 && call_imports.unsupported_using_filters.count == 1);
		Extended.release_file_imports(*call_imports);
		Extended.release_parser_tree(*parsed_call);
		Extended.release_parser_names(*parsed_call);
	}

	POLYMORPHIC_SOURCE :: #string JAI
Procs :: struct {
	Clear: int;
}
make :: (value: $T) -> Procs {
	return .{
		Clear=1
	};
}
main :: () {
	using,map(rename) procs := make(1);
	call := glClear;
}
JAI;
	polymorphic := Extended.parse_file(POLYMORPHIC_SOURCE, filename);
	polymorphic_header := polymorphic.root.(*Extended.Parser_Block).statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header);
	assert(polymorphic_header.procedure_flags & .POLYMORPHIC != 0);
	polymorphic_imports := Extended.resolve_file_imports(*polymorphic, map_names=test_using_map_fields);
	assert(polymorphic.status == .COMPLETE && polymorphic_imports.mapped_names.count == 1 && polymorphic_imports.unsupported_using_filters.count == 0);
	polymorphic_call := (
		polymorphic.root.(*Extended.Parser_Block).statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header)
			.body_or_null.block.statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident)
	);
	assert(polymorphic_call.resolved_declaration == polymorphic_imports.mapped_names[0].declaration);
	Extended.release_file_imports(*polymorphic_imports);
	Extended.release_parser_tree(*polymorphic);
	Extended.release_parser_names(*polymorphic);

	IDENTITY_SOURCE :: #string JAI
Procs :: struct {
	Clear: int;
}
identity :: (value: $T) -> T {
	return value;
}
main :: () {
	using,map(rename) procs := identity(
		Procs.{
			Clear=1
		}
	);
	call := glClear;
}
JAI;
	identity := Extended.parse_file(IDENTITY_SOURCE, filename);
	identity_imports := Extended.resolve_file_imports(*identity, map_names=test_using_map_fields);
	assert(identity.status == .COMPLETE && identity_imports.mapped_names.count == 1 && identity_imports.unsupported_using_filters.count == 0);
	identity_statements := identity.root.(*Extended.Parser_Block).statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block.statements;
	assert(identity_statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == identity_imports.mapped_names[0].declaration);
	Extended.release_file_imports(*identity_imports);
	Extended.release_parser_tree(*identity);
	Extended.release_parser_names(*identity);

	MULTIPLE_POLYMORPHIC_SOURCE :: #string JAI
Child :: struct {
	Clear: int;
}
Other :: struct {
	PushMatrix: int;
}
choose :: (left: $T, right: $U) -> T {
	return left;
}
main :: () {
	using,map(rename) procs := choose(
		Child.{
			Clear=1
		}, Other.{
			PushMatrix=2
		}
	);
	call := glClear;
}
JAI;
	multiple_polymorphic := Extended.parse_file(MULTIPLE_POLYMORPHIC_SOURCE, filename);
	multiple_polymorphic_imports := Extended.resolve_file_imports(*multiple_polymorphic, map_names=test_using_map_fields);
	assert(multiple_polymorphic.status == .COMPLETE && multiple_polymorphic_imports.mapped_names.count == 1 && multiple_polymorphic_imports.unsupported_using_filters.count == 0);
	Extended.release_file_imports(*multiple_polymorphic_imports);
	Extended.release_parser_tree(*multiple_polymorphic);
	Extended.release_parser_names(*multiple_polymorphic);

	NAMED_POLYMORPHIC_SOURCE :: #string JAI
Child :: struct {
	Clear: int;
}
Other :: struct {
	PushMatrix: int;
}
choose :: (left: $T, right: $U) -> T {
	return left;
}
main :: () {
	using,map(rename) procs := choose(
		right=Other.{
			PushMatrix=2
		}, left=Child.{
			Clear=1
		}
	);
	call := glClear;
}
JAI;
	named_polymorphic := Extended.parse_file(NAMED_POLYMORPHIC_SOURCE, filename);
	named_polymorphic_imports := Extended.resolve_file_imports(*named_polymorphic, map_names=test_using_map_fields);
	assert(named_polymorphic.status == .COMPLETE && named_polymorphic_imports.mapped_names.count == 1 && named_polymorphic_imports.unsupported_using_filters.count == 0);
	Extended.release_file_imports(*named_polymorphic_imports);
	Extended.release_parser_tree(*named_polymorphic);
	Extended.release_parser_names(*named_polymorphic);

	POLYMORPHIC_BOX_SOURCE :: #string JAI
Child :: struct {
	Clear: int;
}
Box :: struct (T: Type) {
	Nested: T;
}
wrap :: (value: $T) -> Box(T) {
	return .{
		Nested=value
	};
}
main :: () {
	original := wrap(
		Child.{
			Clear=1
		}
	);
	using,map(rename) procs := original.Nested;
	call := glClear;
}
JAI;
	polymorphic_box := Extended.parse_file(POLYMORPHIC_BOX_SOURCE, filename);
	box_header := polymorphic_box.root.(*Extended.Parser_Block).statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header);
	assert(box_header.returns.count == 1 && box_header.returns[0].type_inst && box_header.returns[0].type_inst.type_valued_expression && box_header.returns[0].type_inst.type_valued_expression.kind == .PROCEDURE_CALL);
	polymorphic_box_imports := Extended.resolve_file_imports(*polymorphic_box, map_names=test_using_map_fields);
	assert(polymorphic_box.status == .COMPLETE && polymorphic_box_imports.mapped_names.count == 1 && polymorphic_box_imports.unsupported_using_filters.count == 0);
	Extended.release_file_imports(*polymorphic_box_imports);
	Extended.release_parser_tree(*polymorphic_box);
	Extended.release_parser_names(*polymorphic_box);

	MATCHING_POLYMORPHIC_BOX_SOURCE :: #string JAI
Child :: struct {
	Clear: int;
}
Box :: struct (T: Type) {
	Nested: T;
}
wrap :: (value: $T) -> Box(T) {
	return .{
		Nested=value
	};
}
main :: (choose: bool) {
	using,map(rename) procs := (
		ifx choose
			then wrap(Child.{
				Clear=1
			}) else Box(Child).{
				Nested=Child.{
					Clear=2
				}
			}
	).Nested;
	call := glClear;
}
JAI;
	matching_polymorphic_box := Extended.parse_file(MATCHING_POLYMORPHIC_BOX_SOURCE, filename);
	matching_polymorphic_box_imports := Extended.resolve_file_imports(*matching_polymorphic_box, map_names=test_using_map_fields);
	assert(matching_polymorphic_box.status == .COMPLETE && matching_polymorphic_box_imports.mapped_names.count == 1 && matching_polymorphic_box_imports.unsupported_using_filters.count == 0);
	Extended.release_file_imports(*matching_polymorphic_box_imports);
	Extended.release_parser_tree(*matching_polymorphic_box);
	Extended.release_parser_names(*matching_polymorphic_box);

	POLYMORPHIC_PAIR_SOURCE :: #string JAI
Child :: struct {
	Clear: int;
}
Other :: struct {
	PushMatrix: int;
}
Pair :: struct (First: Type, Second: Type) {
	Left: First;
	Right: Second;
}
wrap :: (left: $T, right: $U) -> Pair(T, U) {
	return .{
		Left=left, Right=right
	};
}
main :: () {
	using,map(rename) procs := wrap(
		Other.{
			PushMatrix=1
		},
		Child.{
			Clear=2
		}
	).Right;
	call := glClear;
}
JAI;
	polymorphic_pair := Extended.parse_file(POLYMORPHIC_PAIR_SOURCE, filename);
	polymorphic_pair_imports := Extended.resolve_file_imports(*polymorphic_pair, map_names=test_using_map_fields);
	assert(polymorphic_pair.status == .COMPLETE && polymorphic_pair_imports.mapped_names.count == 1 && polymorphic_pair_imports.unsupported_using_filters.count == 0);
	Extended.release_file_imports(*polymorphic_pair_imports);
	Extended.release_parser_tree(*polymorphic_pair);
	Extended.release_parser_names(*polymorphic_pair);

	REORDERED_POLYMORPHIC_PAIR_SOURCE :: #string JAI
Child :: struct {
	Clear: int;
}
Other :: struct {
	PushMatrix: int;
}
Pair :: struct (First: Type, Second: Type) {
	Left: First;
	Right: Second;
}
wrap :: (left: $T, right: $U) -> Pair(U, T) {
	return .{
		Left=right, Right=left
	};
}
main :: () {
	using,map(rename) procs := wrap(
		right=Other.{
			PushMatrix=1
		},
		left=Child.{
			Clear=2
		}
	).Right;
	call := glClear;
}
JAI;
	reordered_polymorphic_pair := Extended.parse_file(REORDERED_POLYMORPHIC_PAIR_SOURCE, filename);
	reordered_polymorphic_pair_imports := Extended.resolve_file_imports(*reordered_polymorphic_pair, map_names=test_using_map_fields);
	assert(reordered_polymorphic_pair.status == .COMPLETE && reordered_polymorphic_pair_imports.mapped_names.count == 1 && reordered_polymorphic_pair_imports.unsupported_using_filters.count == 0);
	Extended.release_file_imports(*reordered_polymorphic_pair_imports);
	Extended.release_parser_tree(*reordered_polymorphic_pair);
	Extended.release_parser_names(*reordered_polymorphic_pair);

	NAMED_RETURN_PAIR_SOURCE :: #string JAI
Child :: struct {
	Clear: int;
}
Other :: struct {
	PushMatrix: int;
}
Pair :: struct (First: Type, Second: Type) {
	Left: First;
	Right: Second;
}
wrap :: (left: $T, right: $U) -> Pair(Second=T, First=U) {
	return .{
		Left=right, Right=left
	};
}
main :: () {
	using,map(rename) procs := wrap(
		right=Other.{
			PushMatrix=1
		},
		left=Child.{
			Clear=2
		}
	).Right;
	call := glClear;
}
JAI;
	named_return_pair := Extended.parse_file(NAMED_RETURN_PAIR_SOURCE, filename);
	named_return_pair_imports := Extended.resolve_file_imports(*named_return_pair, map_names=test_using_map_fields);
	assert(named_return_pair.status == .COMPLETE && named_return_pair_imports.mapped_names.count == 1 && named_return_pair_imports.unsupported_using_filters.count == 0);
	Extended.release_file_imports(*named_return_pair_imports);
	Extended.release_parser_tree(*named_return_pair);
	Extended.release_parser_names(*named_return_pair);

	ALIASED_RETURN_PAIR_SOURCE :: #string JAI
Child :: struct {
	Clear: int;
}
Other :: struct {
	PushMatrix: int;
}
Pair :: struct (First: Type, Second: Type) {
	Left: First;
	Right: Second;
}
Alias :: Pair;
wrap :: (left: $T, right: $U) -> Alias(Second=T, First=U) {
	return .{
		Left=right, Right=left
	};
}
main :: () {
	using,map(rename) procs := wrap(
		right=Other.{
			PushMatrix=1
		},
		left=Child.{
			Clear=2
		}
	).Right;
	call := glClear;
}
JAI;
	aliased_return_pair := Extended.parse_file(ALIASED_RETURN_PAIR_SOURCE, filename);
	aliased_return_pair_imports := Extended.resolve_file_imports(*aliased_return_pair, map_names=test_using_map_fields);
	assert(aliased_return_pair.status == .COMPLETE && aliased_return_pair_imports.mapped_names.count == 1 && aliased_return_pair_imports.unsupported_using_filters.count == 0);
	Extended.release_file_imports(*aliased_return_pair_imports);
	Extended.release_parser_tree(*aliased_return_pair);
	Extended.release_parser_names(*aliased_return_pair);

	generic_sources: [] string = .[
		#string JAI
Child :: struct {
	Clear: int;
}
Box :: struct (T: Type) {
	Clear: int;
}
main :: () {
	using,map(rename) box: Box(Child);
	call := glClear;
}
JAI,

		#string JAI
Child :: struct {
	Clear: int;
}
Box :: struct (T: Type) {
	Nested: T;
}
main :: () {
	box: Box(Child);
	using,map(rename) child := box.Nested;
	call := glClear;
}
JAI,

		#string JAI
Child :: struct {
	Clear: int;
}
Box :: struct (T: Type) {
	Nested: T;
}
main :: () {
	box: type_of(
		Box(Child).{
			Nested=Child.{
				Clear=1
			}
		}
	);
	using,map(rename) child := box.Nested;
	call := glClear;
}
JAI,

	];
	for generic_sources {
		generic := Extended.parse_file(it, filename);
		generic_imports := Extended.resolve_file_imports(*generic, map_names=test_using_map_fields);
		assert(generic.status == .COMPLETE && generic_imports.mapped_names.count == 1 && generic_imports.unsupported_using_filters.count == 0);
		if it == generic_sources[1] {
			structure := generic.root.(*Extended.Parser_Block).statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Struct);
			parameter := structure.arguments_block.statements[0].(*Extended.Parser_Declaration);
			field := structure.block.statements[0].(*Extended.Parser_Declaration);
			assert(field.type_inst.type_valued_expression.(*Extended.Parser_Ident).resolved_declaration == parameter);
		}

		Extended.release_file_imports(*generic_imports);
		Extended.release_parser_tree(*generic);
		Extended.release_parser_names(*generic);
	}

	MULTIPLE_GENERIC_SOURCE :: #string JAI
Child :: struct {
	Clear: int;
}
Other :: struct {
	PushMatrix: int;
}
Pair :: struct (First: Type, Second: Type) {
	Left: First;
	Right: Second;
}
main :: () {
	pair: Pair(Other, Child);
	using,map(rename) value := pair.Right;
	call := glClear;
}
JAI;
	multiple_generic := Extended.parse_file(MULTIPLE_GENERIC_SOURCE, filename);
	multiple_generic_imports := Extended.resolve_file_imports(*multiple_generic, map_names=test_using_map_fields);
	assert(multiple_generic.status == .COMPLETE && multiple_generic_imports.mapped_names.count == 1 && multiple_generic_imports.unsupported_using_filters.count == 0);
	Extended.release_file_imports(*multiple_generic_imports);
	Extended.release_parser_tree(*multiple_generic);
	Extended.release_parser_names(*multiple_generic);

	ALIASED_GENERIC_SOURCE :: #string JAI
Child :: struct {
	Clear: int;
}
Other :: struct {
	PushMatrix: int;
}
Pair :: struct (First: Type, Second: Type) {
	Left: First;
	Right: Second;
}
Alias :: Pair;
AliasAgain :: Alias;
main :: () {
	pair: AliasAgain(Second=Child, First=Other);
	using,map(rename) procs := pair.Right;
	call := glClear;
}
JAI;
	aliased_generic := Extended.parse_file(ALIASED_GENERIC_SOURCE, filename);
	aliased_generic_imports := Extended.resolve_file_imports(*aliased_generic, map_names=test_using_map_fields);
	assert(aliased_generic.status == .COMPLETE && aliased_generic_imports.mapped_names.count == 1 && aliased_generic_imports.unsupported_using_filters.count == 0);
	Extended.release_file_imports(*aliased_generic_imports);
	Extended.release_parser_tree(*aliased_generic);
	Extended.release_parser_names(*aliased_generic);

	ALIASED_INSTANCE_SOURCE :: #string JAI
Child :: struct {
	Clear: int;
}
Other :: struct {
	PushMatrix: int;
}
Pair :: struct (First: Type, Second: Type) {
	Left: First;
	Right: Second;
}
Instance :: Pair(Second=Child, First=Other);
Alias :: Instance;
main :: () {
	pair: Alias;
	using,map(rename) procs := pair.Right;
	call := glClear;
}
JAI;
	aliased_instance := Extended.parse_file(ALIASED_INSTANCE_SOURCE, filename);
	aliased_instance_imports := Extended.resolve_file_imports(*aliased_instance, map_names=test_using_map_fields);
	assert(aliased_instance.status == .COMPLETE && aliased_instance_imports.mapped_names.count == 1 && aliased_instance_imports.unsupported_using_filters.count == 0);
	Extended.release_file_imports(*aliased_instance_imports);
	Extended.release_parser_tree(*aliased_instance);
	Extended.release_parser_names(*aliased_instance);

	EQUIVALENT_INSTANCE_SOURCE :: #string JAI
Child :: struct {
	Clear: int;
}
Other :: struct {
	PushMatrix: int;
}
Pair :: struct (First: Type, Second: Type) {
	Left: First;
	Right: Second;
}
Instance :: Pair(Second=Child, First=Other);
main :: (choose: bool) {
	using,map(rename) procs := (
		ifx choose
			then Instance.{
				Right=Child.{
					Clear=1
				}
			} else Pair(Other, Child).{
				Right=Child.{
					Clear=2
				}
			}
	).Right;
	call := glClear;
}
JAI;
	equivalent_instance := Extended.parse_file(EQUIVALENT_INSTANCE_SOURCE, filename);
	equivalent_instance_imports := Extended.resolve_file_imports(*equivalent_instance, map_names=test_using_map_fields);
	assert(equivalent_instance.status == .COMPLETE && equivalent_instance_imports.mapped_names.count == 1 && equivalent_instance_imports.unsupported_using_filters.count == 0);
	Extended.release_file_imports(*equivalent_instance_imports);
	Extended.release_parser_tree(*equivalent_instance);
	Extended.release_parser_names(*equivalent_instance);

	NAMED_GENERIC_SOURCE :: #string JAI
Child :: struct {
	Clear: int;
}
Other :: struct {
	PushMatrix: int;
}
Pair :: struct (First: Type, Second: Type) {
	Left: First;
	Right: Second;
}
main :: () {
	pair: Pair(Second=Child, First=Other);
	using,map(rename) procs := pair.Right;
	call := glClear;
}
JAI;
	named_generic := Extended.parse_file(NAMED_GENERIC_SOURCE, filename);
	named_generic_imports := Extended.resolve_file_imports(*named_generic, map_names=test_using_map_fields);
	assert(named_generic.status == .COMPLETE && named_generic_imports.mapped_names.count == 1 && named_generic_imports.unsupported_using_filters.count == 0);
	Extended.release_file_imports(*named_generic_imports);
	Extended.release_parser_tree(*named_generic);
	Extended.release_parser_names(*named_generic);

	NESTED_GENERIC_SOURCE :: #string JAI
Child :: struct {
	Clear: int;
}
Other :: struct {
	PushMatrix: int;
}
Pair :: struct (First: Type, Second: Type) {
	Left: First;
	Right: Second;
}
main :: () {
	pair: Pair(Pair(Child, Other), Other);
	using,map(rename) procs := pair.Left.Left;
	call := glClear;
}
JAI;
	nested_generic := Extended.parse_file(NESTED_GENERIC_SOURCE, filename);
	nested_generic_imports := Extended.resolve_file_imports(*nested_generic, map_names=test_using_map_fields);
	assert(nested_generic.status == .COMPLETE && nested_generic_imports.mapped_names.count == 1 && nested_generic_imports.unsupported_using_filters.count == 0);
	Extended.release_file_imports(*nested_generic_imports);
	Extended.release_parser_tree(*nested_generic);
	Extended.release_parser_names(*nested_generic);

	NESTED_ALIAS_SOURCE :: #string JAI
Child :: struct {
	Clear: int;
}
Other :: struct {
	PushMatrix: int;
}
Pair :: struct (First: Type, Second: Type) {
	Left: First;
	Right: Second;
}
Inner :: Pair(Child, Other);
main :: () {
	pair: Pair(Inner, Other);
	using,map(rename) procs := pair.Left.Left;
	call := glClear;
}
JAI;
	nested_alias := Extended.parse_file(NESTED_ALIAS_SOURCE, filename);
	nested_alias_imports := Extended.resolve_file_imports(*nested_alias, map_names=test_using_map_fields);
	assert(nested_alias.status == .COMPLETE && nested_alias_imports.mapped_names.count == 1 && nested_alias_imports.unsupported_using_filters.count == 0);
	Extended.release_file_imports(*nested_alias_imports);
	Extended.release_parser_tree(*nested_alias);
	Extended.release_parser_names(*nested_alias);

	INSTANTIATED_FIELD_SOURCE :: #string JAI
Child :: struct {
	Clear: int;
}
Box :: struct (T: Type) {
	Nested: T;
}
Container :: struct {
	Item: Box(Child);
}
main :: () {
	container: Container;
	using,map(rename) procs := container.Item.Nested;
	call := glClear;
}
JAI;
	instantiated_field := Extended.parse_file(INSTANTIATED_FIELD_SOURCE, filename);
	instantiated_field_imports := Extended.resolve_file_imports(*instantiated_field, map_names=test_using_map_fields);
	assert(instantiated_field.status == .COMPLETE && instantiated_field_imports.mapped_names.count == 1 && instantiated_field_imports.unsupported_using_filters.count == 0);
	Extended.release_file_imports(*instantiated_field_imports);
	Extended.release_parser_tree(*instantiated_field);
	Extended.release_parser_names(*instantiated_field);

	PARAMETERIZED_FIELD_SOURCE :: #string JAI
Child :: struct {
	Clear: int;
}
Box :: struct (T: Type) {
	Nested: T;
}
Container :: struct (T: Type) {
	Item: Box(T);
}
main :: () {
	container: Container(Child);
	using,map(rename) procs := container.Item.Nested;
	call := glClear;
}
JAI;
	parameterized_field := Extended.parse_file(PARAMETERIZED_FIELD_SOURCE, filename);
	parameterized_field_imports := Extended.resolve_file_imports(*parameterized_field, map_names=test_using_map_fields);
	assert(parameterized_field.status == .COMPLETE && parameterized_field_imports.mapped_names.count == 1 && parameterized_field_imports.unsupported_using_filters.count == 0);
	assert(parameterized_field.root_scope.inference_pool == null);
	Extended.release_file_imports(*parameterized_field_imports);
	parameterized_field_imports = Extended.resolve_file_imports(*parameterized_field, map_names=test_using_map_fields);
	assert(parameterized_field_imports.mapped_names.count == 1 && parameterized_field_imports.unsupported_using_filters.count == 0);
	assert(parameterized_field.root_scope.inference_pool == null);
	Extended.release_file_imports(*parameterized_field_imports);
	Extended.release_parser_tree(*parameterized_field);
	Extended.release_parser_names(*parameterized_field);

	nested_field_sources: []string = .[
		#string JAI
Child :: struct {
	Clear: int;
}
Box :: struct (T: Type) {
	Nested: T;
}
Container :: struct (T: Type) {
	Item: Box(Box(T));
}
main :: () {
	container: Container(Child);
	using,map(rename) procs := container.Item.Nested.Nested;
	call := glClear;
}
JAI,

		#string JAI
Child :: struct {
	Clear: int;
}
Other :: struct {
	PushMatrix: int;
}
Pair :: struct (First: Type, Second: Type) {
	Left: First;
	Right: Second;
}
Container :: struct (T: Type, U: Type) {
	Item: Pair(Second=T, First=U);
}
main :: () {
	container: Container(U=Other, T=Child);
	using,map(rename) procs := container.Item.Right;
	call := glClear;
}
JAI,

	];
	for nested_field_sources {
		parsed := Extended.parse_file(it, filename);
		imports := Extended.resolve_file_imports(*parsed, map_names=test_using_map_fields);
		assert(parsed.status == .COMPLETE && imports.mapped_names.count == 1 && imports.unsupported_using_filters.count == 0, "Nested field fixture: %", it);
		Extended.release_file_imports(*imports);
		Extended.release_parser_tree(*parsed);
		Extended.release_parser_names(*parsed);
	}

	unsupported_nested_field_sources: []string = .[
		#string JAI
Child :: struct {
	Clear: int;
}
Box :: struct (T: Type) {
	Nested: T;
}
Container :: struct (T: Type) {
	Item: Box(T);
}
main :: () {
	using,map(rename) procs: Container;
	call := glClear;
}
JAI,

		#string JAI
Child :: struct {
	Clear: int;
}
Child :: struct {
	PushMatrix: int;
}
Box :: struct (T: Type) {
	Nested: T;
}
Container :: struct (T: Type) {
	Item: Box(T);
}
main :: () {
	container: Container(Child);
	using,map(rename) procs := container.Item.Nested;
	call := glClear;
}
JAI,

		#string JAI
Child :: struct {
	Clear: int;
	#if Unknown {
		Hidden: int;
	}
}
Box :: struct (T: Type) {
	Nested: T;
}
Container :: struct (T: Type) {
	Item: Box(T);
}
main :: () {
	container: Container(Child);
	using,map(rename) procs := container.Item.Nested;
	call := glClear;
}
JAI,

		#string JAI
Box :: struct (T: Type) {
	Nested: T;
}
Container :: struct (T: Type) {
	Item: Box(T);
}
Self :: Container(Self);
main :: () {
	container: Self;
	using,map(rename) procs := container.Item.Nested;
	call := glClear;
}
JAI,

	];
	for unsupported_nested_field_sources {
		parsed := Extended.parse_file(it, filename);
		imports := Extended.resolve_file_imports(*parsed, map_names=test_using_map_fields);
		assert(parsed.status == .COMPLETE && imports.mapped_names.count == 0 && imports.unsupported_using_filters.count == 1, "Unsupported nested field fixture: %", it);
		Extended.release_file_imports(*imports);
		Extended.release_parser_tree(*parsed);
		Extended.release_parser_names(*parsed);
	}

	complete_alias_sources: [] string = .[
		#string JAI
Child :: struct {
	Clear: int;
}
Box :: struct (T: Type) {
	Nested: T;
}
Instance :: Box(Child);
Alias :: Instance;
main :: () {
	value: Alias;
	using,map(rename) procs := value.Nested;
	call := glClear;
}
JAI,

		#string JAI
Child :: struct {
	Clear: int;
}
Box :: struct (T: Type) {
	Nested: T;
}
Instance :: Box(Child);
Alias :: Instance;
main :: () {
	original := Alias.{
		Nested=Child.{
			Clear=1
		}
	};
	first := original;
	second := first;
	using,map(rename) procs := second.Nested;
	call := glClear;
}
JAI,

		#string JAI
Child :: struct {
	Clear: int;
}
Box :: struct (T: Type) {
	Nested: T;
}
main :: () {
	value: Box(Child) = .{
		Nested=Child.{
			Clear=1
		}
	};
	alias := value;
	using,map(rename) procs := alias.Nested;
	call := glClear;
}
JAI,

	];
	for complete_alias_sources {
		complete_alias := Extended.parse_file(it, filename);
		complete_alias_imports := Extended.resolve_file_imports(*complete_alias, map_names=test_using_map_fields);
		assert(complete_alias.status == .COMPLETE && complete_alias_imports.mapped_names.count == 1 && complete_alias_imports.unsupported_using_filters.count == 0, "Complete alias fixture: %", it);
		Extended.release_file_imports(*complete_alias_imports);
		Extended.release_parser_tree(*complete_alias);
		Extended.release_parser_names(*complete_alias);
	}

	unsupported_alias_sources: [] string = .[
		#string JAI
Child :: struct {
	Clear: int;
}
Box :: struct (T: Type) {
	Nested: T;
}
Instance :: Box(Child);
Instance :: Box(Child);
main :: () {
	value: Instance;
	using,map(rename) procs := value.Nested;
	call := glClear;
}
JAI,

		#string JAI
Child :: struct {
	Clear: int;
}
Box :: struct (T: Type) {
	Nested: T;
}
Instance :: Box(Child);
main :: () {
	original := Instance.{
		Nested=Child.{
			Clear=1
		}
	};
	original := Instance.{
		Nested=Child.{
			Clear=2
		}
	};
	alias := original;
	using,map(rename) procs := alias.Nested;
	call := glClear;
}
JAI,

		#string JAI
Child :: struct {
	Clear: int;
}
Box :: struct (T: Type) {
	Nested: T;
}
First :: Second;
Second :: First;
main :: () {
	value: First;
	using,map(rename) procs := value.Nested;
	call := glClear;
}
JAI,

		#string JAI
Child :: struct {
	Clear: int;
}
Box :: struct (T: Type) {
	Nested: T;
}
main :: () {
	first := second;
	second := first;
	using,map(rename) procs := first.Nested;
	call := glClear;
}
JAI,

		#string JAI
Child :: struct {
	Clear: int;
}
Box :: struct (T: Type) {
	Nested: T;
}
Instance :: Box;
main :: () {
	value: Instance;
	using,map(rename) procs := value.Nested;
	call := glClear;
}
JAI,

		#string JAI
Child :: struct {
	Clear: int;
}
Box :: struct (T: Type) {
	Nested: T;
}
Instance :: Box(Missing);
main :: () {
	value: Instance;
	using,map(rename) procs := value.Nested;
	call := glClear;
}
JAI,

	];
	for unsupported_alias_sources {
		unsupported_alias := Extended.parse_file(it, filename);
		unsupported_alias_imports := Extended.resolve_file_imports(*unsupported_alias, map_names=test_using_map_fields);
		assert(unsupported_alias.status == .COMPLETE && unsupported_alias_imports.mapped_names.count == 0 && unsupported_alias_imports.unsupported_using_filters.count == 1, "Unsupported alias fixture: %", it);
		Extended.release_file_imports(*unsupported_alias_imports);
		Extended.release_parser_tree(*unsupported_alias);
		Extended.release_parser_names(*unsupported_alias);
	}

	PRIMITIVE_GENERIC_SOURCE :: #string JAI
Box :: struct (T: Type) {
	Clear: int;
	Nested: T;
}
main :: () {
	using,map(rename) box: Box(s64);
	call := glClear;
}
JAI;
	primitive_generic := Extended.parse_file(PRIMITIVE_GENERIC_SOURCE, filename);
	primitive_generic_imports := Extended.resolve_file_imports(*primitive_generic, map_names=test_using_map_fields);
	assert(primitive_generic.status == .COMPLETE && primitive_generic_imports.mapped_names.count == 2 && primitive_generic_imports.unsupported_using_filters.count == 0);
	Extended.release_file_imports(*primitive_generic_imports);
	Extended.release_parser_tree(*primitive_generic);
	Extended.release_parser_names(*primitive_generic);

	unsupported_generic_sources: [] string = .[
		#string JAI
Box :: struct (T: Type) {
	Nested: T;
}
main :: () {
	using,map(rename) box: Box;
	call := glNested;
}
JAI,

		#string JAI
Box :: struct (T: Type) {
	Nested: T;
}
main :: () {
	using,map(rename) box: Box(Missing);
	call := glNested;
}
JAI,

		#string JAI
Child :: struct {
	Clear: int;
}
Alias :: Loop;
Loop :: Alias;
main :: () {
	using,map(rename) value: Alias(Child);
	call := glClear;
}
JAI,

		#string JAI
Child :: struct {
	Clear: int;
}
Pair :: struct (First: Type, Second: Type) {
	Right: Second;
}
Self :: Pair(Self, Child);
main :: () {
	using,map(rename) pair: Self;
	call := glRight;
}
JAI,

		#string JAI
Child :: struct {
	Clear: int;
}
Pair :: struct (First: Type, Second: Type) {
	Right: Second;
}
Alias :: Pair;
main :: () {
	using,map(rename) pair: Alias(Unknown=Child, Second=Child);
	call := glRight;
}
JAI,

		#string JAI
Child :: struct {
	Clear: int;
}
Pair :: struct (First: Type, Second: Type) {
	Right: Second;
}
Alias :: Pair(Child);
main :: () {
	using,map(rename) pair: Alias;
	call := glRight;
}
JAI,

		#string JAI
Child :: struct {
	Clear: int;
}
Other :: struct {
	PushMatrix: int;
}
Pair :: struct (First: Type, Second: Type) {
	Left: First;
	Right: Second;
}
main :: (choose: bool) {
	using,map(rename) pair := ifx choose
		then Pair(Pair(Child, Other), Other).{
			Right=Other.{
				PushMatrix=1
			}
		} else Pair(Pair(Other, Child), Other).{
			Right=Other.{
				PushMatrix=2
			}
		};
	call := glRight;
}
JAI,

		#string JAI
Child :: struct {
	Clear: int;
}
Pair :: struct (First: Type, Second: Type) {
	Right: Second;
}
wrap :: (left: $T, right: $U) -> Pair(Second=T, Second=U) {
	return .{
		Right=left
	};
}
main :: () {
	using,map(rename) procs := wrap(
		Child.{
			Clear=1
		},
		Child.{
			Clear=2
		}
	);
	call := glRight;
}
JAI,

		#string JAI
Child :: struct {
	Clear: int;
}
Pair :: struct (First: Type, Second: Type) {
	Right: Second;
}
main :: () {
	using,map(rename) pair: Pair(First=Child, First=Child);
	call := glRight;
}
JAI,

		#string JAI
Child :: struct {
	Clear: int;
}
Pair :: struct (First: Type, Second: Type) {
	Right: Second;
}
main :: () {
	using,map(rename) pair: Pair(Child);
	call := glRight;
}
JAI,

		#string JAI
Child :: struct {
	Clear: int;
}
Pair :: struct (First: Type, Second: Type) {
	Right: Second;
}
main :: () {
	using,map(rename) pair: Pair(Child, Missing);
	call := glRight;
}
JAI,

		#string JAI
Child :: struct {
	Clear: int;
	#if Unknown {
		PushMatrix: int;
	}
}
Box :: struct (T: Type) {
	Clear: int;
}
main :: () {
	using,map(rename) box: Box(Child);
	call := glClear;
}
JAI,

	];
	for unsupported_generic_sources {
		generic := Extended.parse_file(it, filename);
		generic_imports := Extended.resolve_file_imports(*generic, map_names=test_using_map_fields);
		assert(generic.status == .COMPLETE && generic_imports.mapped_names.count == 0 && generic_imports.unsupported_using_filters.count == 1, "Unsupported generic fixture: %", it);
		Extended.release_file_imports(*generic_imports);
		Extended.release_parser_tree(*generic);
		Extended.release_parser_names(*generic);
	}

	TYPED_RUN_SOURCE :: #string JAI
Procs :: struct {
	Clear: int;
}
main :: () {
	using,map(rename) procs := #run -> Procs {
		return .{
			Clear=1
		};
	};
	call := glClear;
}
JAI;
	typed_run := Extended.parse_file(TYPED_RUN_SOURCE, filename);
	typed_run_imports := Extended.resolve_file_imports(*typed_run, map_names=test_using_map_fields);
	assert(typed_run.status == .COMPLETE);
	assert(typed_run_imports.mapped_names.count == 1 && typed_run_imports.unsupported_using_filters.count == 0);
	typed_run_call := (
		typed_run.root.(*Extended.Parser_Block).statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header)
			.body_or_null.block.statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident)
	);
	assert(typed_run_call.resolved_declaration == typed_run_imports.mapped_names[0].declaration);
	Extended.release_file_imports(*typed_run_imports);
	Extended.release_parser_tree(*typed_run);
	Extended.release_parser_names(*typed_run);

	complete_conditional_receiver_sources: []string = .[
		#string JAI
C :: struct {
	Clear: int;
}
Box :: struct (T: Type) {
	Nested: T;
}
main :: () {
	using,map(rename) procs := (#run Box(C).{Nested=C.{Clear=1}}).Nested;
	call := glClear;
}
JAI,

		#string JAI
C :: struct {
	Clear: int;
}
Box :: struct (T: Type) {
	Nested: T;
}
main :: () {
	using,map(rename) procs := (#run -> Box(C) {
		return .{Nested=C.{Clear=1}};
	}).Nested;
	call := glClear;
}
JAI,

		#string JAI
C :: struct {
	Clear: int;
}
Box :: struct (T: Type) {
	Nested: T;
}
main :: (choose: bool) {
	using,map(rename) procs := (
		ifx choose
			then Box(C).{Nested=C.{Clear=1}}
			else Box(C).{Nested=C.{Clear=2}}
	).Nested;
	call := glClear;
}
JAI,

		#string JAI
C :: struct {
	Clear: int;
}
O :: struct {
	PushMatrix: int;
}
Box :: struct (T: Type) {
	Nested: T;
}
main :: () {
	using,map(rename) procs := (
		#ifx true
			then Box(C).{Nested=C.{Clear=1}}
			else Box(O).{Nested=O.{PushMatrix=2}}
	).Nested;
	call := glClear;
}
JAI
	];
	for complete_conditional_receiver_sources {
		parsed := Extended.parse_file(it, filename);
		imports := Extended.resolve_file_imports(*parsed, map_names=test_using_map_fields);
		assert(parsed.status == .COMPLETE && imports.mapped_names.count == 1 && imports.unsupported_using_filters.count == 0, "Complete conditional receiver fixture: %", it);
		Extended.release_file_imports(*imports);
		Extended.release_parser_tree(*parsed);
		Extended.release_parser_names(*parsed);
	}

	unsupported_conditional_receiver_sources: []string = .[
		#string JAI
C :: struct {
	Clear: int;
}
O :: struct {
	PushMatrix: int;
}
Box :: struct (T: Type) {
	Nested: T;
}
main :: (choose: bool) {
	using,map(rename) procs := (
		#ifx choose
			then Box(C).{Nested=C.{Clear=1}}
			else Box(O).{Nested=O.{PushMatrix=2}}
	).Nested;
	call := glClear;
}
JAI,

		#string JAI
C :: struct {
	Clear: int;
}
Box :: struct (T: Type) {
	Nested: T;
}
main :: () {
	using,map(rename) procs := (
		#ifx Unknown
			then Box(C).{Nested=C.{Clear=1}}
			else Box(C).{Nested=C.{Clear=2}}
	).Nested;
	call := glClear;
}
JAI,

		#string JAI
C :: struct {
	Clear: int;
}
Box :: struct (T: Type) {
	Nested: T;
}
main :: () {
	using,map(rename) procs := (#run {
		return Box(C).{Nested=C.{Clear=1}};
	}).Nested;
	call := glClear;
}
JAI
	];
	for unsupported_conditional_receiver_sources {
		parsed := Extended.parse_file(it, filename);
		imports := Extended.resolve_file_imports(*parsed, map_names=test_using_map_fields);
		assert(parsed.status == .COMPLETE && imports.mapped_names.count == 0 && imports.unsupported_using_filters.count == 1, "Unsupported conditional receiver fixture: %", it);
		Extended.release_file_imports(*imports);
		Extended.release_parser_tree(*parsed);
		Extended.release_parser_names(*parsed);
	}

	EXPRESSION_RUN_SOURCE :: #string JAI
Procs :: struct {
	Clear: int;
}
main :: () {
	using,map(rename) procs := #run Procs.{
		Clear=1
	};
	call := glClear;
}
JAI;
	expression_run := Extended.parse_file(EXPRESSION_RUN_SOURCE, filename);
	expression_run_imports := Extended.resolve_file_imports(*expression_run, map_names=test_using_map_fields);
	assert(expression_run.status == .COMPLETE);
	assert(expression_run_imports.mapped_names.count == 1 && expression_run_imports.unsupported_using_filters.count == 0);
	expression_run_call := (
		expression_run.root.(*Extended.Parser_Block).statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header)
			.body_or_null.block.statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident)
	);
	assert(expression_run_call.resolved_declaration == expression_run_imports.mapped_names[0].declaration);
	Extended.release_file_imports(*expression_run_imports);
	Extended.release_parser_tree(*expression_run);
	Extended.release_parser_names(*expression_run);

	OVERLOADED_RUN_SOURCE :: #string JAI
Procs :: struct {
	Clear: int;
}
Other :: struct {
	PushMatrix: int;
}
make :: (number: int) -> Procs {
	return .{
		Clear=1
	};
}
make :: (text: string) -> Other {
	return .{
		PushMatrix=1
	};
}
main :: () {
	using,map(rename) procs := #run make("text");
	call := glClear;
}
JAI;
	overloaded_run := Extended.parse_file(OVERLOADED_RUN_SOURCE, filename);
	overloaded_run_imports := Extended.resolve_file_imports(*overloaded_run, map_names=test_using_map_fields);
	assert(
		overloaded_run.status == .COMPLETE
		&& overloaded_run_imports.mapped_names.count == 1
		&& overloaded_run_imports.mapped_names[0].source_name == "PushMatrix"
		&& !overloaded_run_imports.mapped_names[0].exported_name
		&& overloaded_run_imports.unsupported_using_filters.count == 0
	);
	Extended.release_file_imports(*overloaded_run_imports);
	Extended.release_parser_tree(*overloaded_run);
	Extended.release_parser_names(*overloaded_run);

	UNTYPED_RUN_SOURCE :: #string JAI
Procs :: struct {
	Clear: int;
}
main :: () {
	using,map(rename) procs := #run {
		return Procs.{
			Clear=1
		};
	};
	call := glClear;
}
JAI;
	untyped_run := Extended.parse_file(UNTYPED_RUN_SOURCE, filename);
	untyped_run_imports := Extended.resolve_file_imports(*untyped_run, map_names=test_using_map_fields);
	assert(untyped_run.status == .COMPLETE && untyped_run_imports.mapped_names.count == 0 && untyped_run_imports.unsupported_using_filters.count == 1);
	Extended.release_file_imports(*untyped_run_imports);
	Extended.release_parser_tree(*untyped_run);
	Extended.release_parser_names(*untyped_run);

	UNRESOLVED_CALL_SOURCE :: #string JAI
main :: () {
	using,map(rename) procs := missing();
	call := glClear;
}
JAI;
	unresolved_call := Extended.parse_file(UNRESOLVED_CALL_SOURCE, filename);
	unresolved_call_imports := Extended.resolve_file_imports(*unresolved_call, map_names=test_using_map_fields);
	assert(unresolved_call_imports.mapped_names.count == 0 && unresolved_call_imports.unsupported_using_filters.count == 1);
	unresolved_call_reference := (
		unresolved_call.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header)
			.body_or_null.block.statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident)
	);
	assert(unresolved_call_reference.resolved_declaration == null);
	Extended.release_file_imports(*unresolved_call_imports);
	Extended.release_parser_tree(*unresolved_call);
	Extended.release_parser_names(*unresolved_call);

	test_semantic_field.name = "Clear";
	test_semantic_field_name = copy_string("Clear");
	semantic_call := Extended.parse_file(UNRESOLVED_CALL_SOURCE, filename);
	semantic_imports := Extended.resolve_file_imports(*semantic_call, map_names=test_using_map_fields, aggregate_fields=test_using_map_semantic_fields);
	free(test_semantic_field_name);
	test_semantic_field_name = "";
	assert(semantic_imports.unsupported_using_filters.count == 0 && semantic_imports.mapped_names.count == 1);
	assert(semantic_imports.mapped_names[0].source_name == "Clear" && semantic_imports.mapped_names[0].exported_name == "glClear");
	semantic_reference := (
		semantic_call.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header)
			.body_or_null.block.statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident)
	);
	assert(semantic_reference.resolved_declaration == *test_semantic_field);
	Extended.release_file_imports(*semantic_imports);
	assert(semantic_reference.resolved_declaration == null);
	Extended.release_parser_tree(*semantic_call);
	Extended.release_parser_names(*semantic_call);

	AGGREGATE_COLLISION_SOURCE :: #string JAI
Procs :: struct {
	Clear: int;
	PushMatrix: int;
}
main :: () {
	using,map(rename) procs: Procs;
	call := same_name;
}
JAI;
	aggregate_collision := Extended.parse_file(AGGREGATE_COLLISION_SOURCE, filename);
	aggregate_collision_imports := Extended.resolve_file_imports(*aggregate_collision, map_names=test_using_map_collision);
	assert(aggregate_collision_imports.map_collisions.count == 1);
	for scope: aggregate_collision.root_scope.children[1].children {
		for reference: scope.references {
			if reference.name == "same_name" {
				assert(reference.resolved_declaration == null);
			}
		}
	}

	Extended.release_file_imports(*aggregate_collision_imports);
	Extended.release_parser_tree(*aggregate_collision);
	Extended.release_parser_names(*aggregate_collision);

	SEPARATE_SOURCE :: #string JAI
First :: struct {
	alpha: int;
}
Second :: struct {
	beta: int;
}
main :: () {
	using,map(rename) a: First;
	using,map(rename) b: Second;
	call := same_name;
}
JAI;
	separate := Extended.parse_file(SEPARATE_SOURCE, filename);
	separate_imports := Extended.resolve_file_imports(*separate, map_names=test_using_map_collision);
	assert(separate_imports.map_collisions.count == 1);
	separate_call := (
		separate.root.(*Extended.Parser_Block).statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header)
			.body_or_null.block.statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident)
	);
	assert(separate_call.resolved_declaration == null);
	Extended.release_file_imports(*separate_imports);
	Extended.release_parser_tree(*separate);
	Extended.release_parser_names(*separate);

	LEXICAL_SOURCE :: #string JAI
Procs :: struct {
	Clear: int;
}
main :: () {
	glClear :: 5;
	using,map(rename) procs: Procs;
	call := glClear;
}
JAI;
	lexical := Extended.parse_file(LEXICAL_SOURCE, filename);
	lexical_imports := Extended.resolve_file_imports(*lexical, map_names=test_using_map_fields);
	assert(lexical_imports.map_collisions.count == 1);
	lexical_statements := lexical.root.(*Extended.Parser_Block).statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block.statements;
	assert(lexical_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == lexical_statements[0].(*Extended.Parser_Declaration));
	Extended.release_file_imports(*lexical_imports);
	Extended.release_parser_tree(*lexical);
	Extended.release_parser_names(*lexical);

	LOCAL_SOURCE :: #string JAI
#import,file "files/specific.jai";
mess_up_this_string :: 4;
call := mess_up_this_string;
JAI;
	local := Extended.parse_file(LOCAL_SOURCE, filename);
	local_imports := Extended.resolve_file_imports(*local);
	local_statements := local.root.(*Extended.Parser_Block).statements;
	assert(local_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == local_statements[1].(*Extended.Parser_Declaration));
	Extended.release_file_imports(*local_imports);
	Extended.release_parser_tree(*local);
	Extended.release_parser_names(*local);
}

test_diagnostic_tab_rendering :: () {
	rendered := Extended.render_diagnostic_line("\tfoo\tbar", 2, 5);
	assert(rendered.source == "    foo bar");
	assert(rendered.carets == "    ^^^");

	leading_tab := Extended.render_diagnostic_line("\tfoo", 1, 2);
	assert(leading_tab.source == "    foo");
	assert(leading_tab.carets == "^^^^");

	after_tab_stop := Extended.render_diagnostic_line("abcd\tvalue", 5, 6);
	assert(after_tab_stop.source == "abcd    value");
	assert(after_tab_stop.carets == "    ^^^^");
}

test_prefix_expressions :: () {
	parsed := Extended.parse_expression("!~flag");
	assert(parsed.status == .COMPLETE);
	assert(parsed.root.kind == .UNARY_OPERATOR);

	logical_not := parsed.root.(*Extended.Parser_Unary_Operator);
	assert(logical_not.operator_type == #char "!");
	bitwise_not := logical_not.subexpression.(*Extended.Parser_Unary_Operator);
	assert(bitwise_not.operator_type == #char "~");
	assert(bitwise_not.subexpression.kind == .IDENT);

	unary_dot_chain := Extended.parse_expression(".member.field");
	assert(unary_dot_chain.status == .COMPLETE);
	member_access := unary_dot_chain.root.(*Extended.Parser_Binary_Operator);
	assert(member_access.operator_type == #char ".");
	unary_dot := member_access.left.(*Extended.Parser_Unary_Operator);
	assert(unary_dot.operator_type == #char ".");
	assert(unary_dot.subexpression.(*Extended.Parser_Ident).name == "member");

	incomplete := Extended.parse_expression("!");
	assert(incomplete.status == .INCOMPLETE);
	assert(incomplete.root == null);
	assert(incomplete.diagnostics.count == 1);
	assert(incomplete.diagnostics[0].kind == .EXPECTED_EXPRESSION);
}

test_postfix_expressions :: () {
	call_result := Extended.parse_expression("object.method(1, named = value)");
	assert(call_result.status == .COMPLETE);
	call := call_result.root.(*Extended.Parser_Procedure_Call);
	assert(call.arguments_unsorted.count == 2);
	assert(call.arguments_unsorted[0].name == null);
	assert(call.arguments_unsorted[1].name.name == "named");
	assert(call.arguments_unsorted[1].expression.(*Extended.Parser_Ident).name == "value");

	method := call.procedure_expression.(*Extended.Parser_Binary_Operator);
	assert(method.operator_type == #char ".");
	assert(method.right.(*Extended.Parser_Ident).name == "method");

	subscript_result := Extended.parse_expression("matrix[row][column].*");
	assert(subscript_result.status == .COMPLETE);
	dereference := subscript_result.root.(*Extended.Parser_Unary_Operator);
	assert(dereference.operator_type == .POSTFIX_DEREFERENCE);
	outer_subscript := dereference.subexpression.(*Extended.Parser_Binary_Operator);
	assert(outer_subscript.operator_type == .ARRAY_SUBSCRIPT);
	assert(outer_subscript.left.(*Extended.Parser_Binary_Operator).operator_type == .ARRAY_SUBSCRIPT);

	incomplete_call := Extended.parse_expression("function(1, 2");
	assert(incomplete_call.status == .INCOMPLETE);
	assert(incomplete_call.synthetic_tokens.count == 1);
	assert(incomplete_call.synthetic_tokens[0].token.type == #char ")");
}

test_call_context_modification :: () {
	SOURCE :: "f(16, 8,, allocator = pool_allocator, logger = my_logger)";
	parsed := Extended.parse_expression(SOURCE);
	assert(parsed.status == .COMPLETE);
	call := parsed.root.(*Extended.Parser_Procedure_Call);
	assert(call.arguments_unsorted.count == 2);
	assert(call.context_modification != null);
	assert(call.context_modification.modification_expressions.count == 2);
	first := call.context_modification.modification_expressions[0].(*Extended.Parser_Binary_Operator);
	assert(first.operator_type == #char "=");
	assert(first.left.(*Extended.Parser_Ident).name == "allocator");
	assert(first.right.(*Extended.Parser_Ident).name == "pool_allocator");
	second := call.context_modification.modification_expressions[1].(*Extended.Parser_Binary_Operator);
	assert(second.operator_type == #char "=");
	assert(second.left.(*Extended.Parser_Ident).name == "logger");
	assert(second.right.(*Extended.Parser_Ident).name == "my_logger");
	assert(Extended.reconstruct_source(*parsed) == SOURCE);

	shorthand := Extended.parse_expression("f(1000, 3,, pool_allocator)");
	assert(shorthand.status == .COMPLETE);
	shorthand_call := shorthand.root.(*Extended.Parser_Procedure_Call);
	assert(shorthand_call.arguments_unsorted.count == 2);
	assert(shorthand_call.context_modification.modification_expressions.count == 1);
	assert(shorthand_call.context_modification.modification_expressions[0].(*Extended.Parser_Ident).name == "pool_allocator");

	context_only := Extended.parse_expression("f(,, pool_allocator)");
	assert(context_only.status == .COMPLETE);
	context_call := context_only.root.(*Extended.Parser_Procedure_Call);
	assert(context_call.arguments_unsorted.count == 0);
	assert(context_call.context_modification.modification_expressions.count == 1);
	context_only_named := Extended.parse_expression("f(,, allocator = pool_allocator)");
	assert(context_only_named.status == .COMPLETE);
	context_named_call := context_only_named.root.(*Extended.Parser_Procedure_Call);
	assert(context_named_call.arguments_unsorted.count == 0);
	assert(context_named_call.context_modification.modification_expressions.count == 1);
	assert(context_named_call.context_modification.modification_expressions[0].(*Extended.Parser_Binary_Operator).left.(*Extended.Parser_Ident).name == "allocator");

	empty_context := Extended.parse_expression("f(1,,)");
	assert(empty_context.status == .RECOVERED);
	assert(empty_context.diagnostics.count > 0);
	assert(empty_context.root.(*Extended.Parser_Procedure_Call).context_modification != null);
}

test_casts_and_queries :: () {
	function_cast := Extended.parse_expression("cast(s32) value + other");
	assert(function_cast.status == .COMPLETE);
	addition := function_cast.root.(*Extended.Parser_Binary_Operator);
	cast_node := addition.left.(*Extended.Parser_Cast);
	assert(cast_node.cast_flags == 0);
	assert(cast_node.target_type.type_valued_expression.(*Extended.Parser_Ident).name == "s32");
	assert(cast_node.expression.(*Extended.Parser_Ident).name == "value");

	pointer_cast := Extended.parse_expression("cast(*u8) value");
	assert(pointer_cast.status == .COMPLETE);
	pointer_target := pointer_cast.root.(*Extended.Parser_Cast).target_type;
	assert(pointer_target.pointer_to.type_valued_expression.(*Extended.Parser_Ident).name == "u8");

	array_cast := Extended.parse_expression("cast([3] int) value");
	assert(array_cast.status == .COMPLETE);
	array_target := array_cast.root.(*Extended.Parser_Cast).target_type;
	assert(array_target.array_dimension.(*Extended.Parser_Literal)._u64 == 3);
	assert(array_target.array_element_type.type_valued_expression.(*Extended.Parser_Ident).name == "int");

	type_argument := Extended.parse_expression("New([3] int)");
	assert(type_argument.status == .COMPLETE);
	type_argument_node := type_argument.root.(*Extended.Parser_Procedure_Call).arguments_unsorted[0].expression.(*Extended.Parser_Type_Instantiation);
	assert(type_argument_node.array_dimension.(*Extended.Parser_Literal)._u64 == 3);
	assert(type_argument_node.array_element_type.type_valued_expression.(*Extended.Parser_Ident).name == "int");

	pointer_array_type := Extended.parse_expression("*[123] int");
	assert(pointer_array_type.status == .COMPLETE);
	pointer_array_node := pointer_array_type.root.(*Extended.Parser_Type_Instantiation);
	assert(pointer_array_node.pointer_to.array_dimension.(*Extended.Parser_Literal)._u64 == 123);

	address_argument := Extended.parse_expression("consume(*value)");
	assert(address_argument.status == .COMPLETE);
	address_node := address_argument.root.(*Extended.Parser_Procedure_Call).arguments_unsorted[0].expression.(*Extended.Parser_Unary_Operator);
	assert(address_node.operator_type == #char "*");

	multiplication := Extended.parse_expression("left * right");
	assert(multiplication.status == .COMPLETE);
	assert(multiplication.root.(*Extended.Parser_Binary_Operator).operator_type == #char "*");

	postfix_cast := Extended.parse_expression("value.(s32).field");
	access := postfix_cast.root.(*Extended.Parser_Binary_Operator);
	assert((access.left.(*Extended.Parser_Cast).cast_flags & .HAS_POSTFIX_SYNTAX) != 0);

	auto_cast := Extended.parse_expression("xx value.*");
	assert((auto_cast.root.(*Extended.Parser_Cast).cast_flags & .IS_AUTO) != 0);
	assert(auto_cast.root.(*Extended.Parser_Cast).expression.(*Extended.Parser_Unary_Operator).operator_type == .POSTFIX_DEREFERENCE);

	type_query_expression := Extended.parse_expression("type_of(a + b)");
	assert(type_query_expression.root.(*Extended.Parser_Expression_Query).query_kind == .TYPE_OF);
	assert(type_query_expression.root.(*Extended.Parser_Expression_Query).expression_to_query.kind == .BINARY_OPERATOR);

	constant_query := Extended.parse_expression("is_constant(42)");
	assert(constant_query.root.(*Extended.Parser_Expression_Query).query_kind == .IS_CONSTANT);
	code_query := Extended.parse_expression("code_of(value)");
	assert(code_query.root.(*Extended.Parser_Expression_Query).query_kind == .CODE_OF);

	size_query := Extended.parse_expression("size_of(s64)");
	assert(size_query.root.(*Extended.Parser_Type_Query).query_kind == .SIZE_OF);
	type_info_query := Extended.parse_expression("type_info(Thing)");
	assert(type_info_query.root.(*Extended.Parser_Type_Query).query_kind == .TYPE_INFO);
	initializer_query := Extended.parse_expression("initializer_of(Thing)");
	assert(initializer_query.root.(*Extended.Parser_Type_Query).query_kind == .INITIALIZER_OF);
}

test_parameter_default_delimiters :: () {
	procedure := Extended.parse_declaration("configure :: (width: s64 = 640, height: s64 = 480) {}");
	assert(procedure.status == .COMPLETE);
	procedure_header := procedure.root.(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header);
	assert(procedure_header.arguments.count == 2);
	assert(procedure_header.arguments[0].expression.(*Extended.Parser_Literal)._u64 == 640);
	assert(procedure_header.arguments[1].expression.(*Extended.Parser_Literal)._u64 == 480);

	aggregate := Extended.parse_declaration("Dimensions :: struct (width: s64 = 640, height: s64 = 480) {}");
	assert(aggregate.status == .COMPLETE);
	aggregate_parameters := aggregate.root.(*Extended.Parser_Declaration).expression.(*Extended.Parser_Struct).arguments_block.statements;
	assert(aggregate_parameters.count == 2);
	assert(aggregate_parameters[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Literal)._u64 == 640);
	assert(aggregate_parameters[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Literal)._u64 == 480);

	polymorphic := Extended.parse_declaration("choose :: (value: $T = 1, fallback: T = 2) -> T { return value; }");
	assert(polymorphic.status == .COMPLETE);
	polymorphic_header := polymorphic.root.(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header);
	assert(polymorphic_header.arguments.count == 2);
	assert((polymorphic_header.procedure_flags & .POLYMORPHIC) != 0);

	named_returns := Extended.parse_declaration("result :: () -> (value: s64 = 0, valid: bool = false) { return; }");
	assert(named_returns.status == .COMPLETE);
	named_return_header := named_returns.root.(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header);
	assert(named_return_header.returns.count == 2);
	assert(named_return_header.returns[0].expression.(*Extended.Parser_Literal)._u64 == 0);
	assert(named_return_header.returns[1].expression.(*Extended.Parser_Literal)._u64 == 0);

	multi_value := Extended.parse_declaration("values := 1, 2;");
	assert(multi_value.status == .COMPLETE);
	assert(multi_value.root.(*Extended.Parser_Declaration).expression.(*Extended.Parser_Comma_Separated_Arguments).arguments.count == 2);
}

test_expression_directives :: () {
	character := Extended.parse_expression("#char \"A\"");
	assert(character.status == .COMPLETE);
	character_literal := character.root.(*Extended.Parser_Literal);
	assert(character_literal.value_type == .NUMBER);
	assert((character_literal.value_flags & .IS_A_NUMBER) != 0);
	assert(character_literal._u64 == #char "A");

	this := Extended.parse_expression("#this");
	assert(this.status == .COMPLETE);
	assert(this.root.kind == .DIRECTIVE_THIS);

	filepath := Extended.parse_expression("#filepath", "D:/project/source/fixture.jai");
	assert(filepath.status == .COMPLETE);
	assert(filepath.root.(*Extended.Parser_Literal)._string == "D:/project/source/");

	caller_code := Extended.parse_expression("#caller_code");
	assert(caller_code.status == .COMPLETE);
	caller_code_node := caller_code.root.(*Extended.Parser_Directive_Code);
	assert((caller_code_node.code_flags & xx Extended.Code_Directive_Code_Flags_CALLER_CODE) != 0);
	assert(caller_code_node.expression == null);

	constant_context := Extended.parse_declaration("CHARACTER :: #char \"A\";");
	assert(constant_context.status == .COMPLETE);
	filepath_context := Extended.parse_declaration("SOURCE_DIRECTORY :: #filepath;", "D:/project/source/fixture.jai");
	assert(filepath_context.status == .COMPLETE);
	assert(filepath_context.root.(*Extended.Parser_Declaration).expression.(*Extended.Parser_Literal)._string == "D:/project/source/");
	default_context := Extended.parse_declaration("macro :: (call := #caller_code) #expand {}");
	assert(default_context.status == .COMPLETE);

	code := Extended.parse_expression("#code value + 1");
	assert(code.status == .COMPLETE);
	assert(code.root.(*Extended.Parser_Directive_Code).expression.kind == .BINARY_OPERATOR);

	null_code := Extended.parse_expression("#code,null");
	assert((null_code.root.(*Extended.Parser_Directive_Code).code_flags & .NULL) != 0);
	typed_code := Extended.parse_expression("#code,typed value");
	assert((typed_code.root.(*Extended.Parser_Directive_Code).code_flags & .TYPED) != 0);
	block_code := Extended.parse_expression("#code { value := 1; use(value); }");
	assert(block_code.root.(*Extended.Parser_Directive_Code).expression.(*Extended.Parser_Block).statements.count == 2);
	declaration_code := Extended.parse_expression("#code value: s64 = 1");
	assert(declaration_code.status == .COMPLETE);
	declaration_payload := declaration_code.root.(*Extended.Parser_Directive_Code).expression.(*Extended.Parser_Declaration);
	assert(declaration_payload.name == "value");
	assert(declaration_payload.type_inst.type_valued_expression.(*Extended.Parser_Ident).name == "s64");
	assert(declaration_payload.expression.(*Extended.Parser_Literal)._u64 == 1);
	constant_code := Extended.parse_expression("#code VALUE :: 1");
	constant_payload := constant_code.root.(*Extended.Parser_Directive_Code).expression.(*Extended.Parser_Declaration);
	assert((constant_payload.flags & .IS_CONSTANT) != 0);
	assert(constant_payload.name == "VALUE");

	run := Extended.parse_expression("#run,stallable compute()");
	run_node := run.root.(*Extended.Parser_Directive_Run);
	assert((run_node.flags & .STALLABLE) != 0);
	assert((run_node.flags & .HAS_IMPLICIT_RETURN_TYPES) != 0);
	assert(run_node.expression.kind == .PROCEDURE_CALL);
	block_run := Extended.parse_expression("#run,stallable { value := compute(); return value; }");
	block_run_node := block_run.root.(*Extended.Parser_Directive_Run);
	assert((block_run_node.flags & .STALLABLE) != 0);
	assert((block_run_node.flags & .HAS_IMPLICIT_RETURN_TYPES) == 0);
	assert(block_run_node.expression.(*Extended.Parser_Block).statements.count == 2);
	host_run := Extended.parse_expression("#run,host compute()");
	host_run_node := host_run.root.(*Extended.Parser_Directive_Run);
	assert((host_run_node.flags & xx Extended.Code_Directive_Run_Flags_HOST) != 0);
	assert((host_run_node.flags & .HAS_IMPLICIT_RETURN_TYPES) != 0);
	host_block_run := Extended.parse_expression("#run,host { compute(); }");
	host_block_run_node := host_block_run.root.(*Extended.Parser_Directive_Run);
	assert((host_block_run_node.flags & xx Extended.Code_Directive_Run_Flags_HOST) != 0);
	assert((host_block_run_node.flags & .HAS_IMPLICIT_RETURN_TYPES) == 0);
	assert(host_block_run_node.expression.(*Extended.Parser_Block).statements.count == 1);

	// Typed block runs own their return signature and leave the next declaration separate.
	TYPED_RUN_SOURCE :: "VALUE :: #run -> [] string { return .[\"ready\"]; }\nafter :: 1;";
	typed_run_file := Extended.parse_file(TYPED_RUN_SOURCE);
	assert(typed_run_file.status == .COMPLETE);
	typed_run_statements := typed_run_file.root.(*Extended.Parser_Block).statements;
	assert(typed_run_statements.count == 2);
	typed_run := typed_run_statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Directive_Run);
	assert((typed_run.flags & .HAS_IMPLICIT_RETURN_TYPES) == 0);
	assert(typed_run.procedure.returns.count == 1);
	assert(typed_run.expression == typed_run.procedure.body_or_null.block);
	assert(typed_run.expression.(*Extended.Parser_Block).statements.count == 1);
	assert(Extended.reconstruct_source(*typed_run_file) == TYPED_RUN_SOURCE);
	host_typed_run := Extended.parse_file("VALUE :: #run,host -> string { return \"ready\"; };\nafter :: 1;");
	assert(host_typed_run.status == .COMPLETE);
	host_typed_statements := host_typed_run.root.(*Extended.Parser_Block).statements;
	assert(host_typed_statements.count == 2);
	host_typed_directive := host_typed_statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Directive_Run);
	assert((host_typed_directive.flags & xx Extended.Code_Directive_Run_Flags_HOST) != 0);
	assert((host_typed_directive.flags & .HAS_IMPLICIT_RETURN_TYPES) == 0);
	assert(host_typed_directive.procedure.returns.count == 1);
	assert(host_typed_directive.expression == host_typed_directive.procedure.body_or_null.block);
	assert(Extended.parse_expression("#run -> string").status == .INCOMPLETE);

	ASSERT_SOURCE :: "{ #assert ready \"not ready\"; after(); }";
	assert_parsed := Extended.parse_block(ASSERT_SOURCE);
	assert(assert_parsed.status == .COMPLETE);
	assert_statements := assert_parsed.root.(*Extended.Parser_Block).statements;
	assert(assert_statements.count == 2);
	assert_run := assert_statements[0].(*Extended.Parser_Directive_Run);
	assert((assert_run.flags & .ASSERTION) != 0);
	assert((assert_run.flags & .HAS_IMPLICIT_RETURN_TYPES) != 0);
	assert(assert_run.expression.(*Extended.Parser_Ident).name == "ready");
	assert(assert_run.assertion_string == "not ready");
	assert(Extended.reconstruct_source(*assert_parsed) == ASSERT_SOURCE);
	module_assert := Extended.parse_file("#assert(is_constant(VERBOSE));\nrender :: () {}");
	assert(module_assert.status == .COMPLETE);
	assert(module_assert.root.(*Extended.Parser_Block).statements[0].kind == .DIRECTIVE_RUN);
	assert(Extended.parse_block("{ #assert; after(); }").status == .RECOVERED);

	RUN_SOURCE :: "{ #run { compile_step(); } after(); #run compute(); }";
	run_statements := Extended.parse_block(RUN_SOURCE);
	assert(run_statements.status == .COMPLETE);
	assert(run_statements.root.(*Extended.Parser_Block).statements.count == 3);
	assert(run_statements.root.(*Extended.Parser_Block).statements[1].kind == .PROCEDURE_CALL);
	assert(Extended.reconstruct_source(*run_statements) == RUN_SOURCE);

	FILE_RUN_SOURCE :: "#run { compile_step(); }\nmain :: () {}";
	file_run := Extended.parse_file(FILE_RUN_SOURCE);
	assert(file_run.status == .COMPLETE);
	assert(file_run.root.(*Extended.Parser_Block).statements.count == 2);
	assert(Extended.reconstruct_source(*file_run) == FILE_RUN_SOURCE);
	assert(Extended.parse_block("{ #run { compile_step(); }; after(); }").status == .COMPLETE);
	assert(Extended.parse_block("{ #run compute() after(); }").status == .RECOVERED);

	PLAIN_INSERT_SOURCE :: "#insert body";
	insert := Extended.parse_expression(PLAIN_INSERT_SOURCE);
	assert(insert.status == .COMPLETE);
	plain_insert := insert.root.(*Extended.Parser_Directive_Insert);
	assert(plain_insert.expression.(*Extended.Parser_Ident).name == "body");
	assert(plain_insert.scope_redirection == null);
	assert(plain_insert.break_replacement == null);
	assert(plain_insert.continue_replacement == null);
	assert(plain_insert.remove_replacement == null);
	assert(plain_insert.expansion == null);
	assert(Extended.reconstruct_source(*insert) == PLAIN_INSERT_SOURCE);

	EMPTY_SCOPE_SOURCE :: "{ code :: #code { value := 1; }; #insert,scope() code; after(); }";
	empty_scope := Extended.parse_block(EMPTY_SCOPE_SOURCE);
	assert(empty_scope.status == .COMPLETE);
	empty_statements := empty_scope.root.(*Extended.Parser_Block).statements;
	assert(empty_statements.count == 3);
	assert(empty_statements[0].(*Extended.Parser_Declaration).expression.kind == .DIRECTIVE_CODE);
	empty_insert := empty_statements[1].(*Extended.Parser_Directive_Insert);
	assert(empty_insert.scope_redirection == null);
	assert(empty_insert.expression.(*Extended.Parser_Ident).name == "code");
	assert(empty_statements[2].kind == .PROCEDURE_CALL);
	assert(Extended.reconstruct_source(*empty_scope) == EMPTY_SCOPE_SOURCE);
	assert(Extended.parse_expression("#insert,scope(code").status == .INCOMPLETE);
	insert_options := Extended.parse_expression("#insert,scope(caller) (break=break outer, continue=continue outer, remove=remove outer) body");
	assert(insert_options.status == .COMPLETE);
	insert_node := insert_options.root.(*Extended.Parser_Directive_Insert);
	assert(insert_node.scope_redirection.(*Extended.Parser_Ident).name == "caller");
	assert(insert_node.break_replacement.(*Extended.Parser_Loop_Control).control_type == .BREAK);
	assert(insert_node.continue_replacement.(*Extended.Parser_Loop_Control).control_type == .CONTINUE);
	assert(insert_node.remove_replacement.(*Extended.Parser_Loop_Control).control_type == .REMOVE);

	REPLACEMENTS_SOURCE :: "{ #insert(break=break y, continue=continue y, remove=#assert(false)) body; after(); }";
	replacements := Extended.parse_block(REPLACEMENTS_SOURCE);
	assert(replacements.status == .COMPLETE);
	assert(replacements.root.(*Extended.Parser_Block).statements.count == 2);
	replacement_insert := replacements.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Directive_Insert);
	assert(replacement_insert.break_replacement.(*Extended.Parser_Loop_Control).target_ident.name == "y");
	assert(replacement_insert.continue_replacement.(*Extended.Parser_Loop_Control).target_ident.name == "y");
	assert(replacement_insert.remove_replacement.kind == .DIRECTIVE_RUN);
	assert((replacement_insert.remove_replacement.(*Extended.Parser_Directive_Run).flags & .ASSERTION) != 0);
	assert(replacement_insert.expression.(*Extended.Parser_Ident).name == "body");
	assert(replacement_insert.expansion == null);
	assert(Extended.reconstruct_source(*replacements) == REPLACEMENTS_SOURCE);

	insert_procedure := Extended.parse_expression("#insert -> string { return \"generated\"; }");
	implicit_run := insert_procedure.root.(*Extended.Parser_Directive_Insert).expression.(*Extended.Parser_Directive_Run);
	assert((implicit_run.flags & .SYNTACTICALLY_IMPLICIT) != 0);
	assert(implicit_run.procedure.returns.count == 1);
	assert(implicit_run.expression.(*Extended.Parser_Block).statements.count == 1);

	SHORT_INSERT_SOURCE :: "{ #insert -> string { return \"x *= x;\"; } #insert -> Code { return #code x = x + 1; } after(); }";
	short_inserts := Extended.parse_block(SHORT_INSERT_SOURCE);
	assert(short_inserts.status == .COMPLETE);
	short_statements := short_inserts.root.(*Extended.Parser_Block).statements;
	assert(short_statements.count == 3);
	assert(short_statements[0].kind == .DIRECTIVE_INSERT);
	assert(short_statements[1].(*Extended.Parser_Directive_Insert).expression.(*Extended.Parser_Directive_Run).procedure.returns.count == 1);
	assert(short_statements[2].kind == .PROCEDURE_CALL);
	assert(Extended.reconstruct_source(*short_inserts) == SHORT_INSERT_SOURCE);

	bake := Extended.parse_expression("#bake specialize(value)");
	assert(bake.root.(*Extended.Parser_Directive_Bake).procedure_call.arguments_unsorted.count == 1);

	location := Extended.parse_expression("#location(value)");
	assert(location.root.(*Extended.Parser_Directive_Location).expression.(*Extended.Parser_Ident).name == "value");
	empty_location := Extended.parse_expression("#location()");
	assert(empty_location.root.(*Extended.Parser_Directive_Location).expression == null);
	caller_location := Extended.parse_expression("#caller_location");
	assert(caller_location.root.(*Extended.Parser_Directive_Location).is_caller_location);

	library := Extended.parse_declaration("User32 :: #library,system,no_static_library,link_always \"User32\";");
	assert(library.status == .COMPLETE);
	library_node := library.root.(*Extended.Parser_Declaration).expression.(*Extended.Parser_Directive_Library);
	assert(library_node.name == "User32");
	assert((library_node.library_flags & .IS_SYSTEM_LIBRARY) != 0);
	assert((library_node.library_flags & .STATIC_LIBRARY_UNAVAILABLE) != 0);
	assert((library_node.library_flags & .LINK_ALWAYS) == 0);

	load := Extended.parse_expression("#load \"local.jai\"");
	assert(load.root.(*Extended.Parser_Directive_Load).short_name == "local.jai");
	bytes := Extended.parse_expression("#bytes source");
	assert(bytes.root.(*Extended.Parser_Directive_Bytes).expression.kind == .IDENT);
	procedure_name := Extended.parse_expression("#procedure_name(target)");
	assert(procedure_name.root.(*Extended.Parser_Directive_Procedure_Name).argument.kind == .IDENT);

	PROCEDURE_SOURCE :: "{ selected := #procedure_of_call very_optional(\"Sailor?\", 2, 3, 4, **float); after(); }";
	procedure_of_call := Extended.parse_block(PROCEDURE_SOURCE);
	assert(procedure_of_call.status == .COMPLETE);
	selected_statements := procedure_of_call.root.(*Extended.Parser_Block).statements;
	assert(selected_statements.count == 2);
	selected_call := selected_statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Call);
	assert((selected_call.flags & .RETURNS_PROCEDURE_POINTER_ONLY) != 0);
	assert(selected_call.procedure_expression.(*Extended.Parser_Ident).name == "very_optional");
	assert(selected_call.arguments_unsorted.count == 5);
	assert(selected_call.arguments_unsorted[4].expression.kind == .UNARY_OPERATOR);
	assert(selected_statements[1].kind == .PROCEDURE_CALL);
	assert(Extended.reconstruct_source(*procedure_of_call) == PROCEDURE_SOURCE);
	assert(Extended.parse_expression("#procedure_of_call foo(1)").status == .COMPLETE);
	malformed_procedure := Extended.parse_block("{ #procedure_of_call foo; after(); }");
	assert(malformed_procedure.status == .RECOVERED);
	assert(Extended.reconstruct_source(*malformed_procedure) == "{ #procedure_of_call foo; after(); }");
	wildcard := Extended.parse_expression("#wildcard");
	assert(wildcard.root.(*Extended.Parser_Directive_Wildcard).index == -1);
	exists := Extended.parse_expression("#exists(value, ready)");
	assert(exists.root.(*Extended.Parser_Directive_Exists).sync_expression.kind == .IDENT);
	imported := Extended.parse_declaration("Basic :: #import \"Basic\"(DEBUG=true)();");
	assert(imported.status == .COMPLETE);
	import_node := imported.root.(*Extended.Parser_Declaration).expression.(*Extended.Parser_Directive_Import);
	assert(import_node.name == "Basic");
	assert(import_node.module_parameters_call.arguments_unsorted.count == 1);
	assert(import_node.program_parameters_call.arguments_unsorted.count == 0);
	file_import := Extended.parse_expression("#import,file \"../module.jai\"");
	assert(file_import.root.(*Extended.Parser_Directive_Import).import_type == .PATH_TO_FILE);
	directory_import := Extended.parse_expression("#import,dir \"../module\"");
	assert(directory_import.root.(*Extended.Parser_Directive_Import).import_type == .PATH_TO_DIRECTORY);

	// String imports require a semicolon after the here-string terminator.
	HERE_IMPORT_SOURCE :: "#import,string #string END\nVALUE :: 1;\nEND\n;\nafter :: 2;";
	here_import := Extended.parse_file(HERE_IMPORT_SOURCE);
	assert(here_import.status == .COMPLETE);
	assert(here_import.root.(*Extended.Parser_Block).statements.count == 2);
	here_import_node := here_import.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Directive_Import);
	assert(here_import_node.import_type == .FULL_TEXT);
	assert((here_import_node.flags & .UNSHARED) != 0);
	assert(here_import_node.name == "VALUE :: 1;\n");
	assert(here_import.root.(*Extended.Parser_Block).statements[1].kind == .DECLARATION);
	assert(Extended.reconstruct_source(*here_import) == HERE_IMPORT_SOURCE);
	missing_import_semicolon := Extended.parse_file("#import,string #string END\nVALUE :: 1;\nEND\nafter :: 2;");
	assert(missing_import_semicolon.status == .RECOVERED);
	assert(missing_import_semicolon.diagnostics[0].expected_token == #char ";");
	bake_constants := Extended.parse_expression("#bake_constants specialize(value)");
	assert(bake_constants.root.(*Extended.Parser_Directive_Bake).bake_type == .CONSTANTS_BAKE);
	bake_arguments := Extended.parse_expression("#bake_arguments specialize(value)");
	assert(bake_arguments.root.(*Extended.Parser_Directive_Bake).bake_type == .PARAMETER_VALUE_BAKE);

	directives := Extended.parse_declaration_block("{ #scope_file #add_context token: string; #overlay (value) bits: u64; #module_parameters(DEBUG := false)(); }");
	assert(directives.status == .COMPLETE);
	directive_block := directives.root.(*Extended.Parser_Block);
	assert(directive_block.statements[0].(*Extended.Parser_Directive_Scope).scope_type == .FILE);
	assert(directive_block.statements[1].(*Extended.Parser_Directive_Add_Context).expression.kind == .DECLARATION);
	assert(directive_block.statements[2].(*Extended.Parser_Directive_Overlay).declaration_or_using.kind == .DECLARATION);
	module_parameters := directive_block.statements[3].(*Extended.Parser_Directive_Module_Parameters);
	assert(module_parameters.module_parameters.arguments.count == 1);
	assert(module_parameters.program_parameters.arguments.count == 0);

	more_directives := Extended.parse_declaration_block("{ #scope_export #through; #poke_name Module Renamed; #overlay (value) using alias; #module_parameters()(PROGRAM_DEBUG := false) { setup(); } }");
	assert(more_directives.status == .COMPLETE);
	more_block := more_directives.root.(*Extended.Parser_Block);
	assert(more_block.statements[0].(*Extended.Parser_Directive_Scope).scope_type == .EXPORT);
	assert(more_block.statements[1].kind == .DIRECTIVE_THROUGH);
	assert(more_block.statements[2].(*Extended.Parser_Directive_Poke_Name).name == "Renamed");
	assert(more_block.statements[3].(*Extended.Parser_Directive_Overlay).declaration_or_using.kind == .USING);
	more_parameters := more_block.statements[4].(*Extended.Parser_Directive_Module_Parameters);
	assert(more_parameters.program_parameters.arguments.count == 1);
	assert(more_parameters.common_code.statements.count == 1);

	MODULE_SCOPE_SOURCE :: "#scope_module\n#import \"Math\";\nvalue :: 1;";
	module_scope := Extended.parse_file(MODULE_SCOPE_SOURCE);
	assert(module_scope.status == .COMPLETE);
	assert(module_scope.root.(*Extended.Parser_Block).statements.count == 3);
	assert(module_scope.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Directive_Scope).scope_type == .INTERNAL);
	assert(module_scope.root.(*Extended.Parser_Block).statements[1].kind == .DIRECTIVE_IMPORT);
	assert(module_scope.root.(*Extended.Parser_Block).statements[2].(*Extended.Parser_Declaration).name == "value");
	assert(Extended.reconstruct_source(*module_scope) == MODULE_SCOPE_SOURCE);

	modified := Extended.parse_declaration("choose :: (value: $T) -> T #modify { return true; } { return value; }");
	assert(modified.status == .COMPLETE);
	modified_header := modified.root.(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header);
	assert(modified_header.modify_directives.count == 1);
	assert(modified_header.body_or_null != null);
}

test_binary_expressions :: () {
	parsed := Extended.parse_expression("a + b * c");
	assert(parsed.status == .COMPLETE);
	root := parsed.root.(*Extended.Parser_Binary_Operator);
	assert(root.operator_type == #char "+");
	assert(root.left.kind == .IDENT);
	assert(root.right.(*Extended.Parser_Binary_Operator).operator_type == #char "*");

	left_associative := Extended.parse_expression("a - b - c").root.(*Extended.Parser_Binary_Operator);
	assert(left_associative.operator_type == #char "-");
	assert(left_associative.left.(*Extended.Parser_Binary_Operator).operator_type == #char "-");

	incomplete := Extended.parse_expression("a +");
	assert(incomplete.status == .INCOMPLETE);
	assert(incomplete.root.kind == .BINARY_OPERATOR);
	assert(incomplete.root.(*Extended.Parser_Binary_Operator).right == null);
	assert(incomplete.diagnostics.count == 1);
	assert(incomplete.diagnostics[0].span.first == xx 1);
	assert(incomplete.diagnostics[0].span.one_past_last == xx 2);
	assert(incomplete.diagnostics[0].message == "Unable to parse an expression to the right of this binary operator.");
	assert(incomplete.diagnostics[0].related_information.count == 0);
}

test_basic_declarations :: () {
	typed := Extended.parse_declaration("value: s64 = 42;");
	assert(typed.status == .COMPLETE);
	typed_node := typed.root.(*Extended.Parser_Declaration);
	assert(typed_node.name == "value");
	assert(typed_node.type_inst.type_valued_expression.(*Extended.Parser_Ident).name == "s64");
	assert(typed_node.expression.(*Extended.Parser_Literal)._u64 == 42);

	inferred := Extended.parse_declaration("value := 42;");
	assert(inferred.status == .COMPLETE);
	assert(inferred.root.(*Extended.Parser_Declaration).type_inst == null);
	assert(inferred.root.(*Extended.Parser_Declaration).expression != null);

	constant := Extended.parse_declaration("VALUE :: 42;");
	assert(constant.status == .COMPLETE);
	assert((constant.root.(*Extended.Parser_Declaration).flags & .IS_CONSTANT) != 0);

	uninitialized := Extended.parse_declaration("value: s64;");
	assert(uninitialized.status == .COMPLETE);
	assert(uninitialized.root.(*Extended.Parser_Declaration).expression == null);
}

test_compound_declarations :: () {
	REASSIGNED_SOURCE :: "{ out1, out2 = hello(1); out1 = 2; after(); }";
	reassigned := Extended.parse_block(REASSIGNED_SOURCE);
	assert(reassigned.status == .COMPLETE);
	reassigned_statements := reassigned.root.(*Extended.Parser_Block).statements;
	assert(reassigned_statements.count == 3);
	compound := reassigned_statements[0].(*Extended.Parser_Compound_Declaration);
	assert(compound.comma_separated_assignment.arguments.count == 2);
	assert(compound.comma_separated_assignment.arguments[0].node.(*Extended.Parser_Ident).name == "out1");
	assert(compound.comma_separated_assignment.arguments[1].node.(*Extended.Parser_Ident).name == "out2");
	assert(compound.declaration_properties.expression.kind == .PROCEDURE_CALL);
	assert(reassigned_statements[1].kind == .BINARY_OPERATOR);
	assert(reassigned_statements[2].kind == .PROCEDURE_CALL);
	assert(Extended.reconstruct_source(*reassigned) == REASSIGNED_SOURCE);

	broken_reassignment := Extended.parse_block("{ out1, out2 =; after(); }");
	assert(broken_reassignment.status == .RECOVERED);
	assert(broken_reassignment.root.(*Extended.Parser_Block).statements.count == 2);
	assert(broken_reassignment.root.(*Extended.Parser_Block).statements[1].kind == .PROCEDURE_CALL);

	multiple_values := Extended.parse_block("{ out1, out2 = 1, 2; }");
	assert(multiple_values.status == .COMPLETE);
	assert(multiple_values.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Compound_Declaration).declaration_properties.expression.(*Extended.Parser_Comma_Separated_Arguments).arguments.count == 2);

	// Indexed and member targets must retain their syntax under compound assignment lowering.
	INDEXED_SOURCE :: "{ array[it], array[it+1] += get_u8s(); after(); }";
	indexed := Extended.parse_block(INDEXED_SOURCE);
	assert(indexed.status == .COMPLETE);
	indexed_statements := indexed.root.(*Extended.Parser_Block).statements;
	assert(indexed_statements.count == 2);
	indexed_assignment := indexed_statements[0].(*Extended.Parser_Compound_Declaration);
	indexed_targets := indexed_assignment.comma_separated_assignment;
	assert(indexed_targets.arguments.count == 2);
	assert(indexed_targets.arguments[0].node.(*Extended.Parser_Binary_Operator).operator_type == .ARRAY_SUBSCRIPT);
	assert(indexed_targets.arguments[1].node.(*Extended.Parser_Binary_Operator).operator_type == .ARRAY_SUBSCRIPT);
	assert(indexed_assignment.declaration_properties.expression.kind == .PROCEDURE_CALL);
	assert(indexed_statements[1].kind == .PROCEDURE_CALL);
	assert(Extended.reconstruct_source(*indexed) == INDEXED_SOURCE);

	MEMBER_SOURCE :: "{ v.x, v.y, v.z = 1, 4, 9; after(); }";
	members := Extended.parse_block(MEMBER_SOURCE);
	assert(members.status == .COMPLETE);
	member_assignment := members.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Compound_Declaration);
	assert(member_assignment.comma_separated_assignment.arguments.count == 3);
	assert(member_assignment.declaration_properties.expression.(*Extended.Parser_Comma_Separated_Arguments).arguments.count == 3);
	assert(Extended.reconstruct_source(*members) == MEMBER_SOURCE);
	missing_value := Extended.parse_block("{ array[0], array[1] +=; after(); }");
	assert(missing_value.status == .RECOVERED);
	assert(missing_value.root.(*Extended.Parser_Block).statements[1].kind == .PROCEDURE_CALL);
	assert(Extended.parse_block("{ first(), second(); after(); }").status == .RECOVERED);

	typed := Extended.parse_declaration("x, y: int;");
	assert(typed.status == .COMPLETE);
	typed_node := typed.root.(*Extended.Parser_Compound_Declaration);
	assert(typed_node.comma_separated_assignment.arguments.count == 2);
	assert(typed_node.comma_separated_assignment.arguments[0].node.(*Extended.Parser_Ident).name == "x");
	assert(typed_node.comma_separated_assignment.arguments[1].node.(*Extended.Parser_Ident).name == "y");
	assert(typed_node.declaration_properties.type_inst.type_valued_expression.(*Extended.Parser_Ident).name == "int");

	inferred := Extended.parse_declaration("x, y := 1, 2;");
	assert(inferred.status == .COMPLETE);
	inferred_node := inferred.root.(*Extended.Parser_Compound_Declaration);
	values := inferred_node.declaration_properties.expression.(*Extended.Parser_Comma_Separated_Arguments);
	assert(values.arguments.count == 2);
	assert(values.arguments[0].node.(*Extended.Parser_Literal)._u64 == 1);
	assert(values.arguments[1].node.(*Extended.Parser_Literal)._u64 == 2);

	shared := Extended.parse_declaration("mask, lower, upper: u32 = 0xFFFFFFFF;");
	assert(shared.status == .COMPLETE);
	shared_node := shared.root.(*Extended.Parser_Compound_Declaration);
	assert(shared_node.comma_separated_assignment.arguments.count == 3);
	assert(shared_node.declaration_properties.expression.kind == .LITERAL);
	assert(shared_node.declaration_properties.expression.(*Extended.Parser_Literal)._u64 == 0xFFFFFFFF);

	PARTIAL_REASSIGNMENT_SOURCE :: "{ a: int; a=, b := proc(); after(); }";
	partial_reassignment := Extended.parse_block(PARTIAL_REASSIGNMENT_SOURCE);
	assert(partial_reassignment.status == .COMPLETE, "Partial reassignment: status %, diagnostics %.", partial_reassignment.status, partial_reassignment.diagnostics.count);
	partial_reassignment_statements := partial_reassignment.root.(*Extended.Parser_Block).statements;
	assert(partial_reassignment_statements.count == 3 && partial_reassignment_statements[2].kind == .PROCEDURE_CALL);
	partial_reassignment_node := partial_reassignment_statements[1].(*Extended.Parser_Compound_Declaration);
	assert(partial_reassignment_node.comma_separated_assignment.arguments[0].modifier == .ASSIGN);
	assert(partial_reassignment_node.comma_separated_assignment.arguments[1].modifier == .NONE);
	assert(partial_reassignment_node.operator_type == 0);
	assert(partial_reassignment.root_scope.children[0].bindings.count == 2);
	assert(partial_reassignment.root_scope.children[0].bindings[1].name == "b");
	assert(Extended.reconstruct_source(*partial_reassignment) == PARTIAL_REASSIGNMENT_SOURCE);

	PARTIAL_DECLARATION_SOURCE :: "{ b: int; a:, b = proc(); after(); }";
	partial_declaration := Extended.parse_block(PARTIAL_DECLARATION_SOURCE);
	assert(partial_declaration.status == .COMPLETE, "Partial declaration: status %, diagnostics %.", partial_declaration.status, partial_declaration.diagnostics.count);
	partial_declaration_statements := partial_declaration.root.(*Extended.Parser_Block).statements;
	assert(partial_declaration_statements.count == 3 && partial_declaration_statements[2].kind == .PROCEDURE_CALL);
	partial_declaration_node := partial_declaration_statements[1].(*Extended.Parser_Compound_Declaration);
	assert(partial_declaration_node.comma_separated_assignment.arguments[0].modifier == .DECLARE);
	assert(partial_declaration_node.comma_separated_assignment.arguments[1].modifier == .NONE);
	assert(partial_declaration_node.operator_type == #char "=");
	assert(partial_declaration.root_scope.children[0].bindings.count == 2);
	assert(partial_declaration.root_scope.children[0].bindings[1].name == "a");
	assert(Extended.reconstruct_source(*partial_declaration) == PARTIAL_DECLARATION_SOURCE);

	for source: string.[
		"{ a: int; a=, b :=; after(); }",
		"{ b: int; a:, b =; after(); }"
	] {
		broken := Extended.parse_block(source);
		assert(broken.status == .RECOVERED && broken.diagnostics.count > 0);
		statements := broken.root.(*Extended.Parser_Block).statements;
		assert(statements.count == 3);
		assert(statements[1].kind == .COMPOUND_DECLARATION);
		assert(statements[2].kind == .PROCEDURE_CALL);
		assert(Extended.reconstruct_source(*broken) == source);
	}
}

test_container_types :: () {
	pointer := Extended.parse_declaration("value: **s64;").root.(*Extended.Parser_Declaration).type_inst;
	assert(pointer.pointer_to.pointer_to.type_valued_expression.(*Extended.Parser_Ident).name == "s64");

	fixed := Extended.parse_declaration("values: [4] s64;").root.(*Extended.Parser_Declaration).type_inst;
	assert(fixed.array_dimension.(*Extended.Parser_Literal)._u64 == 4);
	assert(fixed.array_element_type.type_valued_expression.(*Extended.Parser_Ident).name == "s64");

	view := Extended.parse_declaration("values: [] s64;").root.(*Extended.Parser_Declaration).type_inst;
	assert((view.inst_flags & .ARRAY_VIEW) != 0);
	assert(view.array_dimension == null);

	resizable := Extended.parse_declaration("values: [..] s64;").root.(*Extended.Parser_Declaration).type_inst;
	assert((resizable.inst_flags & .RESIZABLE) != 0);
	assert(resizable.array_dimension == null);

	nested := Extended.parse_declaration("values: *[..] *[3] u8;").root.(*Extended.Parser_Declaration).type_inst;
	assert((nested.pointer_to.inst_flags & .RESIZABLE) != 0);
	assert(nested.pointer_to.array_element_type.pointer_to.array_dimension != null);
}

test_procedure_types :: () {
	definition := Extended.parse_declaration("main :: () {}");
	assert(definition.status == .COMPLETE);
	header_definition := definition.root.(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header);
	assert(header_definition.body_or_null != null);
	assert(header_definition.body_or_null.block.statements.count == 0);

	full := Extended.parse_declaration("map :: (value: $T) -> T #expand #compile_time { return value; }");
	assert(full.status == .COMPLETE);
	full_header := full.root.(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header);
	assert(full_header.arguments.count == 1);
	assert(full_header.returns.count == 1);
	assert((full_header.procedure_flags & .POLYMORPHIC) != 0);
	assert((full_header.procedure_flags & .MACRO) != 0);
	assert((full_header.procedure_flags & .COMPILE_TIME_ONLY) != 0);
	assert(full_header.body_or_null.block.statements[0].kind == .RETURN);
	assert(full_header.name == "map");

	// The conventional expansion name is an ordinary declaration until semantic lookup.
	VALUE_EXPANSION_SOURCE :: "for_expansion :: (holder: Holder, body: Code, flags: For_Flags) #expand {}";
	value_expansion := Extended.parse_declaration(VALUE_EXPANSION_SOURCE);
	assert(value_expansion.status == .COMPLETE);
	value_expansion_declaration := value_expansion.root.(*Extended.Parser_Declaration);
	assert(value_expansion_declaration.name == "for_expansion");
	value_expansion_header := value_expansion_declaration.expression.(*Extended.Parser_Procedure_Header);
	assert(value_expansion_header.name == "for_expansion");
	assert((value_expansion_header.procedure_flags & .MACRO) != 0);
	assert(value_expansion_header.arguments.count == 3);
	assert(value_expansion_header.arguments[0].name == "holder");
	assert(value_expansion_header.arguments[0].type_inst.type_valued_expression.(*Extended.Parser_Ident).name == "Holder");
	assert(value_expansion_header.arguments[1].type_inst.type_valued_expression.(*Extended.Parser_Ident).name == "Code");
	assert(value_expansion_header.arguments[2].type_inst.type_valued_expression.(*Extended.Parser_Ident).name == "For_Flags");
	assert(Extended.reconstruct_source(*value_expansion) == VALUE_EXPANSION_SOURCE);

	POINTER_EXPANSION_SOURCE :: "for_expansion :: (holder: *Holder, body: Code, flags: For_Flags) #expand {}";
	pointer_expansion := Extended.parse_declaration(POINTER_EXPANSION_SOURCE);
	assert(pointer_expansion.status == .COMPLETE);
	pointer_expansion_declaration := pointer_expansion.root.(*Extended.Parser_Declaration);
	assert(pointer_expansion_declaration.name == "for_expansion");
	pointer_expansion_header := pointer_expansion_declaration.expression.(*Extended.Parser_Procedure_Header);
	assert((pointer_expansion_header.procedure_flags & .MACRO) != 0);
	assert(pointer_expansion_header.arguments.count == 3);
	assert(pointer_expansion_header.arguments[0].type_inst.pointer_to.type_valued_expression.(*Extended.Parser_Ident).name == "Holder");
	assert(Extended.reconstruct_source(*pointer_expansion) == POINTER_EXPANSION_SOURCE);

	inlined := Extended.parse_declaration("fast :: inline () {}");
	assert(inlined.status == .COMPLETE);
	assert((inlined.root.(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).procedure_flags & .SYNTACTICALLY_MARKED_AS_INLINE_YES) != 0);

	INLINE_SOURCE :: "{ #if true { inline memcpy_v3(dest, source, bytes); } after(); }";
	inline_block := Extended.parse_block(INLINE_SOURCE);
	assert(inline_block.status == .COMPLETE);
	inline_statements := inline_block.root.(*Extended.Parser_Block).statements;
	assert(inline_statements.count == 2);
	inline_call := inline_statements[0].(*Extended.Parser_If).then_block.statements[0].(*Extended.Parser_Procedure_Call);
	assert((inline_call.flags & .INLINE_YES) != 0);
	assert(inline_call.arguments_unsorted.count == 3);
	assert(inline_statements[1].kind == .PROCEDURE_CALL);
	assert(Extended.reconstruct_source(*inline_block) == INLINE_SOURCE);

	malformed_inline := Extended.parse_block("{ inline missing(; after(); }");
	assert(malformed_inline.status == .RECOVERED);
	assert(malformed_inline.root.(*Extended.Parser_Block).statements[1].kind == .PROCEDURE_CALL);

	DUMP_SOURCE :: "square_poly :: (value: $T) -> T #dump { return value; }\nafter :: 1;";
	dumped := Extended.parse_file(DUMP_SOURCE);
	assert(dumped.status == .COMPLETE);
	dump_statements := dumped.root.(*Extended.Parser_Block).statements;
	assert(dump_statements.count == 2);
	dump_header := dump_statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header);
	assert((dump_header.procedure_flags & .DEBUG_DUMP) != 0);
	assert((dump_header.procedure_flags & .POLYMORPHIC) != 0);
	assert(dump_header.body_or_null.block.statements[0].kind == .RETURN);
	assert(Extended.reconstruct_source(*dumped) == DUMP_SOURCE);
	assert(Extended.parse_declaration("square :: () #dump { return; ").status == .INCOMPLETE);

	multiple_returns := Extended.parse_declaration("find :: (items: ..Any) -> value: s64, found: bool { return 0, false; }");
	assert(multiple_returns.status == .COMPLETE);
	multiple_header := multiple_returns.root.(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header);
	assert((multiple_header.arguments[0].type_inst.inst_flags & .VARARGS) != 0);
	assert(multiple_header.returns.count == 2);
	assert(multiple_header.returns[1].name == "found");

	using_parameter := Extended.parse_declaration("inspect :: (using value: *Thing) {}");
	assert(using_parameter.status == .COMPLETE);
	using_header := using_parameter.root.(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header);
	assert(using_header.arguments.count == 1);
	assert(using_header.parameter_usings.count == 1);

	filtered_parameter := Extended.parse_declaration("inspect :: (using value: *Thing, using,except(x, y, z) q: Quaternion) {}");
	assert(filtered_parameter.status == .COMPLETE);
	filtered_header := filtered_parameter.root.(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header);
	assert(filtered_header.arguments.count == 2);
	assert(filtered_header.parameter_usings.count == 2);
	assert(filtered_header.parameter_usings[1].filter_type == .EXCEPT);
	assert(filtered_header.parameter_usings[1].filter_expression.(*Extended.Parser_Literal).array_literal_info.array_members.count == 3);
	assert(Extended.reconstruct_source(*filtered_parameter) == "inspect :: (using value: *Thing, using,except(x, y, z) q: Quaternion) {}");

	missing_filter_name := Extended.parse_declaration("inspect :: (using,only(w, , y) q: Quaternion) {}");
	assert(missing_filter_name.status == .RECOVERED);
	assert(missing_filter_name.diagnostics.count > 0);
	mapped_filter := Extended.parse_block("{ using,map(prefix_with_gl) procs: Procs; }");
	assert(mapped_filter.status == .COMPLETE);
	mapped_using := mapped_filter.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Using);
	assert(mapped_using.filter_type == .MAP);
	assert(mapped_using.filter_expression.(*Extended.Parser_Ident).name == "prefix_with_gl");
	assert(mapped_using.expression.(*Extended.Parser_Declaration).name == "procs");
	assert(Extended.reconstruct_source(*mapped_filter) == "{ using,map(prefix_with_gl) procs: Procs; }");
	missing_map_expression := Extended.parse_block("{ using,map() procs: Procs; }");
	assert(missing_map_expression.status == .RECOVERED);
	assert(missing_map_expression.diagnostics.count > 0);
	assert(missing_map_expression.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Using).expression.kind == .DECLARATION);
	unsupported_filter := Extended.parse_block("{ using,unknown(prefix_with_gl) procs: Procs; }");
	assert(unsupported_filter.status == .RECOVERED);
	assert(unsupported_filter.diagnostics.count > 0);

	foreign := Extended.parse_declaration("external :: () -> s64 #foreign kernel32 \"external_name\";");
	assert(foreign.status == .COMPLETE);
	foreign_header := foreign.root.(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header);
	assert((foreign_header.procedure_flags & .ELSEWHERE) != 0);
	assert(foreign_header.library_identifier.name == "kernel32");
	assert(foreign_header.foreign_function_name == "external_name");

	quick := Extended.parse_declaration("increment :: value => value + 1;");
	assert(quick.status == .COMPLETE);
	quick_header := quick.root.(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header);
	assert((quick_header.procedure_flags & .QUICK) != 0);
	assert((quick_header.body_or_null.block.statements[0].(*Extended.Parser_Return).return_flags & .AUTO_INSERTED_FOR_QUICK_LAMBDA) != 0);

	quick_block := Extended.parse_declaration("combine :: (left, right) => { return left + right; }");
	assert(quick_block.status == .COMPLETE);
	quick_block_header := quick_block.root.(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header);
	assert(quick_block_header.arguments.count == 2);
	assert((quick_block_header.procedure_flags & .QUICK_IN_BLOCK_FORM) != 0);

	CALL_WITH_SOURCE :: #string JAI
{
	call_with :: (arg: $T, f: (T)) {
		f(arg);
	}
	call_with(
		5,
		x => {
			if x > 0
				then #this(x-1);
		}
	);
	after();
}
JAI;
	call_with := Extended.parse_block(CALL_WITH_SOURCE);
	assert(call_with.status == .COMPLETE);
	call_with_statements := call_with.root.(*Extended.Parser_Block).statements;
	assert(call_with_statements.count == 3);
	call := call_with_statements[1].(*Extended.Parser_Procedure_Call);
	assert(call.arguments_unsorted.count == 2);
	lambda := call.arguments_unsorted[1].expression.(*Extended.Parser_Procedure_Header);
	assert((lambda.procedure_flags & .QUICK_IN_BLOCK_FORM) != 0);
	recursive_if := lambda.body_or_null.block.statements[0].(*Extended.Parser_If);
	recursive_call := recursive_if.then_block.statements[0].(*Extended.Parser_Procedure_Call);
	assert(recursive_call.procedure_expression.kind == .DIRECTIVE_THIS);
	assert(recursive_call.arguments_unsorted.count == 1);
	assert(call_with_statements[2].kind == .PROCEDURE_CALL);
	assert(Extended.reconstruct_source(*call_with) == CALL_WITH_SOURCE);
	malformed_this_call := Extended.parse_block("{ #this(; after(); }");
	assert(malformed_this_call.status == .RECOVERED);
	assert(malformed_this_call.root.(*Extended.Parser_Block).statements[1].kind == .PROCEDURE_CALL);

	parsed := Extended.parse_declaration("callback: (value: s64, data: *void) -> (success: bool, string);");
	assert(parsed.status == .COMPLETE);
	type_inst := parsed.root.(*Extended.Parser_Declaration).type_inst;
	assert((type_inst.inst_flags & .TYPE_OF_PROCEDURE) != 0);
	header := type_inst.type_valued_expression.(*Extended.Parser_Procedure_Header);
	assert(header.arguments.count == 2);
	assert(header.arguments[0].name == "value");
	assert(header.arguments[1].type_inst.pointer_to.type_valued_expression.(*Extended.Parser_Ident).name == "void");
	assert(header.returns.count == 2);
	assert(header.returns[0].name == "success");
	assert(header.returns[1].name == "");
	assert(header.returns[1].type_inst.type_valued_expression.(*Extended.Parser_Ident).name == "string");

	UNNAMED_SOURCE :: "callback: (T) -> $R;";
	unnamed := Extended.parse_declaration(UNNAMED_SOURCE);
	assert(unnamed.status == .COMPLETE);
	unnamed_header := unnamed.root.(*Extended.Parser_Declaration).type_inst.type_valued_expression.(*Extended.Parser_Procedure_Header);
	assert(unnamed_header.arguments.count == 1);
	assert(unnamed_header.arguments[0].name == "");
	assert(unnamed_header.arguments[0].type_inst.type_valued_expression.(*Extended.Parser_Ident).name == "T");
	assert(unnamed_header.returns[0].type_inst.type_valued_expression.(*Extended.Parser_Ident).name == "R");
	assert(Extended.reconstruct_source(*unnamed) == UNNAMED_SOURCE);
	assert(Extended.parse_declaration("callback: (T);").status == .COMPLETE);
	assert(Extended.parse_declaration("SimpleProcedure :: #type () -> ();").status == .COMPLETE);
	compound_type := Extended.parse_declaration("callback: *(**void, [3] [5] Code) -> ([..] #Context);");
	assert(compound_type.status == .COMPLETE);
	compound_header := compound_type.root.(*Extended.Parser_Declaration).type_inst.pointer_to.type_valued_expression.(*Extended.Parser_Procedure_Header);
	assert(compound_header.arguments.count == 2);
	assert(compound_header.returns[0].type_inst.array_element_type.type_valued_expression.kind == .DIRECTIVE_CONTEXT_TYPE);
	assert(Extended.parse_declaration("callback: (T, -> R;").status == .RECOVERED);

	structure := Extended.parse_declaration("Thing :: struct (T: Type, N := 2) { value: T; C :: N; } #no_padding; @Serializable");
	assert(structure.status == .COMPLETE);
	struct_node := structure.root.(*Extended.Parser_Declaration).expression.(*Extended.Parser_Struct);
	assert(struct_node.arguments_block.statements.count == 2);
	assert(struct_node.block.statements.count == 2);
	assert((struct_node.block.statements[1].(*Extended.Parser_Declaration).flags & .IS_CONSTANT) != 0);
	assert((struct_node.textual_flags & .NO_PADDING) != 0);
	assert(structure.root.(*Extended.Parser_Declaration).notes[0].text == "Serializable");

	defaulted_field := Extended.parse_declaration("Defaulted :: struct { w: float; w = 1; }");
	assert(defaulted_field.status == .COMPLETE);
	defaulted_statements := defaulted_field.root.(*Extended.Parser_Declaration).expression.(*Extended.Parser_Struct).block.statements;
	assert(defaulted_statements.count == 2);
	field := defaulted_statements[0].(*Extended.Parser_Declaration);
	assignment := defaulted_statements[1].(*Extended.Parser_Binary_Operator);
	assert(assignment.operator_type == #char "=");
	assert(assignment.left.(*Extended.Parser_Ident).name == "w");
	assert(assignment.left.(*Extended.Parser_Ident).resolved_declaration == field);

	DOTTED_SOURCE :: #string JAI
Defaulted :: struct {
	info: Info;
	info.flavor = "chocolate";
	position: Vector3;
	position.z = 1.5;
	brightness: float;
	brightness = 101.2;
	after: s64;
}
JAI;
	dotted := Extended.parse_declaration(DOTTED_SOURCE);
	assert(dotted.status == .COMPLETE);
	dotted_members := dotted.root.(*Extended.Parser_Declaration).expression.(*Extended.Parser_Struct).block.statements;
	assert(dotted_members.count == 7);
	flavor := dotted_members[1].(*Extended.Parser_Binary_Operator);
	assert(flavor.operator_type == #char "=");
	flavor_access := flavor.left.(*Extended.Parser_Binary_Operator);
	assert(flavor_access.operator_type == #char ".");
	assert(flavor_access.right.(*Extended.Parser_Ident).name == "flavor");
	assert(flavor_access.left.(*Extended.Parser_Ident).resolved_declaration == dotted_members[0].(*Extended.Parser_Declaration));
	assert(dotted_members[3].(*Extended.Parser_Binary_Operator).left.(*Extended.Parser_Binary_Operator).right.(*Extended.Parser_Ident).name == "z");
	assert(dotted_members[6].(*Extended.Parser_Declaration).name == "after");
	assert(Extended.reconstruct_source(*dotted) == DOTTED_SOURCE);
	broken_dotted := Extended.parse_declaration("Defaulted :: struct { info: Info; info.flavor =; after: s64; }");
	assert(broken_dotted.status == .RECOVERED);
	broken_members := broken_dotted.root.(*Extended.Parser_Declaration).expression.(*Extended.Parser_Struct).block.statements;
	assert(broken_members.count == 3);
	assert(broken_members[2].(*Extended.Parser_Declaration).name == "after");

	union_result := Extended.parse_declaration("Value :: union { integer: s64; text: string; }");
	assert(union_result.status == .COMPLETE);
	assert((union_result.root.(*Extended.Parser_Declaration).expression.(*Extended.Parser_Struct).textual_flags & .UNION) != 0);

	enum_result := Extended.parse_declaration("Mode :: enum u16 #specified { READ :: 1; WRITE :: 2; }");
	assert(enum_result.status == .COMPLETE);
	enum_node := enum_result.root.(*Extended.Parser_Declaration).expression.(*Extended.Parser_Enum);
	assert(enum_node.marked_as_specified);
	assert(enum_node.internal_type_inst.type_valued_expression.(*Extended.Parser_Ident).name == "u16");
	assert(enum_node.block.statements.count == 2);

	complete_enum := Extended.parse_declaration("State :: enum #complete { READY; DONE; }");
	assert(complete_enum.status == .COMPLETE);
	assert(complete_enum.root.(*Extended.Parser_Declaration).expression.(*Extended.Parser_Enum).marked_as_complete);

	flags_result := Extended.parse_declaration("Options :: enum_flags u32 { FAST; SAFE; }");
	assert(flags_result.status == .COMPLETE);
	flags_node := flags_result.root.(*Extended.Parser_Declaration).expression.(*Extended.Parser_Enum);
	assert(flags_node.is_flags);
	assert(flags_node.block.statements[0].kind == .IDENT);

	interface_type := Extended.parse_declaration("value: $T/interface Has_XY;");
	assert(interface_type.status == .COMPLETE);
	assert((interface_type.root.(*Extended.Parser_Declaration).type_inst.inst_flags & .INTERFACE) != 0);
}

test_polymorphic_types :: () {
	polymorphic := Extended.parse_declaration("value: $T/Number;").root.(*Extended.Parser_Declaration).type_inst;
	poly_ident := polymorphic.type_valued_expression.(*Extended.Parser_Ident);
	assert(poly_ident.name == "T");
	assert((poly_ident.flags & .DEFINES_POLYMORPH_VARIABLE) != 0);
	assert(polymorphic.must_implement.(*Extended.Parser_Ident).name == "Number");

	procedure := Extended.parse_declaration("callback: (value: $T) -> T;").root.(*Extended.Parser_Declaration).type_inst;
	header := procedure.type_valued_expression.(*Extended.Parser_Procedure_Header);
	assert((header.procedure_flags & .POLYMORPHIC) != 0);

	type_directive := Extended.parse_declaration("Alias :: #type s64;").root.(*Extended.Parser_Declaration).expression.(*Extended.Parser_Type_Instantiation);
	assert((type_directive.inst_flags & .TYPE_DIRECTIVE) != 0);
	assert(type_directive.type_directive_target.type_valued_expression.(*Extended.Parser_Ident).name == "s64");

	distinct := Extended.parse_declaration("Handle :: #type,distinct u32;").root.(*Extended.Parser_Declaration).expression.(*Extended.Parser_Type_Instantiation);
	assert((distinct.inst_flags & .TYPE_DIRECTIVE_DISTINCT) != 0);
	isa := Extended.parse_declaration("Filename :: #type,isa string;").root.(*Extended.Parser_Declaration).expression.(*Extended.Parser_Type_Instantiation);
	assert((isa.inst_flags & .TYPE_DIRECTIVE_ISA) != 0);
}

check_declaration_metadata_edit :: (old_text: string, new_text: string, edit_start: s64, edit_end: s64, expected_alignment: u64, expected_note: string, expected_export_name := "") {
	old_source := copy_string(old_text);
	new_source := copy_string(new_text);
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, edit_start, edit_end, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE && fresh.status == .COMPLETE);
	statements := updated.root.(*Extended.Parser_Block).statements;
	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	probe_tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*probe_tokens, edit_source=*old, cursor=statements[0].first_token.(s64)};
	set_allocators(*probe_tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	assert(Extended.reuse_simple_declaration(*probe) == null);
	probe.cursor = statements[1].first_token.(s64);
	probe_tokens.root = Extended.reuse_simple_declaration(*probe);
	assert(probe_tokens.root != null);
	Extended.release_parser_tree(*probe_tokens);
	Extended.release_parser_names(*probe_tokens);
	declaration := statements[0].(*Extended.Parser_Declaration);
	fresh_declaration := fresh_statements[0].(*Extended.Parser_Declaration);
	assert(declaration.node_flags == fresh_declaration.node_flags);
	assert(declaration.flags == fresh_declaration.flags);
	assert(declaration.program_export_name == expected_export_name && declaration.program_export_name == fresh_declaration.program_export_name);
	assert(declaration.first_token == fresh_declaration.first_token && declaration.one_past_last_token == fresh_declaration.one_past_last_token);
	assert(declaration.alignment_expression.(*Extended.Parser_Literal)._u64 == expected_alignment);
	assert(declaration.alignment_expression.first_token == fresh_declaration.alignment_expression.first_token);
	assert(declaration.alignment_expression.one_past_last_token == fresh_declaration.alignment_expression.one_past_last_token);
	assert(declaration.notes.count == 1 && fresh_declaration.notes.count == 1);
	assert(declaration.notes[0].text == expected_note && declaration.notes[0].text == fresh_declaration.notes[0].text);
	assert(declaration.notes[0].first_token == fresh_declaration.notes[0].first_token && declaration.notes[0].one_past_last_token == fresh_declaration.notes[0].one_past_last_token);
	assert(statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == declaration);
	assert(fresh_statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == fresh_declaration);
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	assert_eligible_edit_matches_fresh(*updated, *fresh);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);

	test_using_map_collision :: (using_node: *Extended.Parser_Using, names: [] string) -> bool {
		for * names {
			it.* = "same_name";
		}

		return true;
	}

	assert(declaration.notes[0].text == expected_note && declaration.program_export_name == expected_export_name && Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);
}

check_flagged_declaration_fallback :: (source: string, expected_flag: type_of(Code_Declaration.flags), expected_export_name := "") {
	old_source := copy_string(tprint(			  "% main :: () { use := value; }", source));
	new_source := copy_string(tprint("added :: 0;\n% main :: () { use := value; }", source));
	old := Extended.parse_file(old_source);
	updated, ok := Extended.parse_file_edit(*old, 0, 0, new_source);
	fresh := Extended.parse_file(new_source);
	assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE && fresh.status == .COMPLETE);
	statements := updated.root.(*Extended.Parser_Block).statements;
	fresh_statements := fresh.root.(*Extended.Parser_Block).statements;
	tokens := Extended.materialise_tokens(new_source);
	probe := Extended.Parser.{parsed=*tokens, edit_source=*old, cursor=statements[1].first_token.(s64)};
	set_allocators(*tokens.node_pool, context.default_allocator);
	probe.current_scope = Extended.push_lexical_scope(*probe);
	assert(Extended.reuse_simple_declaration(*probe) == null);
	Extended.release_parser_tree(*tokens);
	Extended.release_parser_names(*tokens);
	declaration := statements[1].(*Extended.Parser_Declaration);
	fresh_declaration := fresh_statements[1].(*Extended.Parser_Declaration);
	assert(declaration.node_flags == fresh_declaration.node_flags);
	assert(declaration.flags & expected_flag && declaration.flags == fresh_declaration.flags);
	assert(declaration.program_export_name == expected_export_name && declaration.program_export_name == fresh_declaration.program_export_name);
	assert(declaration.first_token == fresh_declaration.first_token && declaration.one_past_last_token == fresh_declaration.one_past_last_token);
	assert(declaration.l0 == fresh_declaration.l0 && declaration.c0 == fresh_declaration.c0 && declaration.l1 == fresh_declaration.l1 && declaration.c1 == fresh_declaration.c1);
	body := statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block;
	fresh_body := fresh_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block;
	assert(body.statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == declaration);
	assert(fresh_body.statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == fresh_declaration);
	assert(updated.diagnostics.count == fresh.diagnostics.count && updated.restart_points.count == fresh.restart_points.count);
	assert_eligible_edit_matches_fresh(*updated, *fresh);
	Extended.release_parser_tree(*old);
	Extended.release_parser_names(*old);
	free(old_source);
	assert(declaration.program_export_name == expected_export_name && Extended.reconstruct_source(*updated) == new_source);
	Extended.release_parser_tree(*updated);
	Extended.release_parser_names(*updated);
	Extended.release_parser_tree(*fresh);
	Extended.release_parser_names(*fresh);
	free(new_source);
}

test_declaration_metadata :: () {
	check_declaration_metadata_edit("value: s64 #align 16; @Tag(1) keep := value;", "value: s64 #align 32; @Tag(1) keep := value;", 18, 20, 32, "Tag(1)");
	check_declaration_metadata_edit("value: s64 #align 16; @Tag(1) keep := value;", "value: s64 #align 16; @Tag(2) keep := value;", 27, 28, 16, "Tag(2)");
	EXPORT_PREFIX :: "value: s64 #align 16 #program_export \"";
	check_declaration_metadata_edit(
		tprint("%published\"; @Tag(1) keep := value;", EXPORT_PREFIX),
		tprint( "%released\"; @Tag(1) keep := value;", EXPORT_PREFIX),
		EXPORT_PREFIX.count, EXPORT_PREFIX.count + "published".count,
		16,
		"Tag(1)",
		"released"
	);
	check_flagged_declaration_fallback("#no_reset value: s64;", .NO_RESET);
	check_flagged_declaration_fallback("value: s64 #program_export \"exported_value\";", .PROGRAM_EXPORT, "exported_value");
	check_flagged_declaration_fallback("value: s64 #elsewhere;", .ELSEWHERE);
	check_flagged_declaration_fallback("value: s64 #uninitialized;", .IS_UNINITIALIZED);
	check_flagged_declaration_fallback("$value: Type;", .AUTO_VALUE_BAKE);
	check_flagged_declaration_fallback("$$value: Type;", .AUTO_VALUE_BAKE);
	aligned := Extended.parse_declaration("value: s64 #align 16;");
	assert(aligned.status == .COMPLETE);
	aligned_node := aligned.root.(*Extended.Parser_Declaration);
	assert(aligned_node.alignment_expression.(*Extended.Parser_Literal)._u64 == 16);
	aligned_old_source := copy_string("value: s64 #align 16; main :: () { use := value; }");
	aligned_new_source := copy_string("added :: 0;\nvalue: s64 #align 16; main :: () { use := value; }");
	aligned_old := Extended.parse_file(aligned_old_source);
	aligned_updated, aligned_ok := Extended.parse_file_edit(*aligned_old, 0, 0, aligned_new_source);
	aligned_fresh := Extended.parse_file(aligned_new_source);
	assert(aligned_ok && aligned_old.status == .COMPLETE && aligned_updated.status == .COMPLETE && aligned_fresh.status == .COMPLETE);
	aligned_statements := aligned_updated.root.(*Extended.Parser_Block).statements;
	aligned_fresh_statements := aligned_fresh.root.(*Extended.Parser_Block).statements;
	aligned_tokens := Extended.materialise_tokens(aligned_new_source);
	aligned_probe := Extended.Parser.{parsed=*aligned_tokens, edit_source=*aligned_old, cursor=aligned_statements[1].first_token.(s64)};
	set_allocators(*aligned_tokens.node_pool, context.default_allocator);
	aligned_probe.current_scope = Extended.push_lexical_scope(*aligned_probe);
	assert(Extended.reuse_simple_declaration(*aligned_probe) == null);
	Extended.release_parser_tree(*aligned_tokens);
	Extended.release_parser_names(*aligned_tokens);
	aligned_decl := aligned_statements[1].(*Extended.Parser_Declaration);
	aligned_fresh_decl := aligned_fresh_statements[1].(*Extended.Parser_Declaration);
	assert(aligned_decl.first_token == aligned_fresh_decl.first_token && aligned_decl.one_past_last_token == aligned_fresh_decl.one_past_last_token);
	assert(aligned_decl.l0 == aligned_fresh_decl.l0 && aligned_decl.c0 == aligned_fresh_decl.c0 && aligned_decl.l1 == aligned_fresh_decl.l1 && aligned_decl.c1 == aligned_fresh_decl.c1);
	assert(aligned_decl.flags == aligned_fresh_decl.flags && !aligned_decl.expression && !aligned_fresh_decl.expression);
	assert(aligned_decl.type_inst.first_token == aligned_fresh_decl.type_inst.first_token && aligned_decl.type_inst.one_past_last_token == aligned_fresh_decl.type_inst.one_past_last_token);
	aligned_value := aligned_decl.alignment_expression.(*Extended.Parser_Literal);
	aligned_fresh_value := aligned_fresh_decl.alignment_expression.(*Extended.Parser_Literal);
	assert(aligned_value._u64 == 16 && aligned_value._u64 == aligned_fresh_value._u64);
	assert(aligned_value.first_token == aligned_fresh_value.first_token && aligned_value.one_past_last_token == aligned_fresh_value.one_past_last_token);
	assert(aligned_value.l0 == aligned_fresh_value.l0 && aligned_value.c0 == aligned_fresh_value.c0 && aligned_value.l1 == aligned_fresh_value.l1 && aligned_value.c1 == aligned_fresh_value.c1);
	aligned_body := aligned_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block;
	aligned_fresh_body := aligned_fresh_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block;
	assert(aligned_body.statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == aligned_decl);
	assert(aligned_fresh_body.statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == aligned_fresh_decl);
	assert(aligned_updated.diagnostics.count == aligned_fresh.diagnostics.count && aligned_updated.restart_points.count == aligned_fresh.restart_points.count);
	assert_eligible_edit_matches_fresh(*aligned_updated, *aligned_fresh);
	Extended.release_parser_tree(*aligned_old);
	Extended.release_parser_names(*aligned_old);
	free(aligned_old_source);
	assert(aligned_decl.name == "value" && Extended.reconstruct_source(*aligned_updated) == aligned_new_source);
	Extended.release_parser_tree(*aligned_updated);
	Extended.release_parser_names(*aligned_updated);
	Extended.release_parser_tree(*aligned_fresh);
	Extended.release_parser_names(*aligned_fresh);
	free(aligned_new_source);

	noted := Extended.parse_declaration("value: s64; @JsonIgnore");
	assert(noted.status == .COMPLETE);
	noted_node := noted.root.(*Extended.Parser_Declaration);
	assert(noted_node.notes.count == 1);
	assert(noted_node.notes[0].text == "JsonIgnore");
	noted_old_source := copy_string(			 "value: s64; @Tag(1) main :: () { use := value; }");
	noted_new_source := copy_string("added :: 0;\nvalue: s64; @Tag(1) main :: () { use := value; }");
	noted_old := Extended.parse_file(noted_old_source);
	noted_updated, noted_ok := Extended.parse_file_edit(*noted_old, 0, 0, noted_new_source);
	noted_fresh := Extended.parse_file(noted_new_source);
	assert(noted_ok && noted_old.status == .COMPLETE && noted_updated.status == .COMPLETE && noted_fresh.status == .COMPLETE);
	noted_statements := noted_updated.root.(*Extended.Parser_Block).statements;
	noted_fresh_statements := noted_fresh.root.(*Extended.Parser_Block).statements;
	noted_tokens := Extended.materialise_tokens(noted_new_source);
	noted_probe := Extended.Parser.{parsed=*noted_tokens, edit_source=*noted_old, cursor=noted_statements[1].first_token.(s64)};
	set_allocators(*noted_tokens.node_pool, context.default_allocator);
	noted_probe.current_scope = Extended.push_lexical_scope(*noted_probe);
	assert(Extended.reuse_simple_declaration(*noted_probe) == null);
	Extended.release_parser_tree(*noted_tokens);
	Extended.release_parser_names(*noted_tokens);
	noted_decl := noted_statements[1].(*Extended.Parser_Declaration);
	noted_fresh_decl := noted_fresh_statements[1].(*Extended.Parser_Declaration);
	assert(noted_decl.first_token == noted_fresh_decl.first_token && noted_decl.one_past_last_token == noted_fresh_decl.one_past_last_token);
	assert(noted_decl.flags == noted_fresh_decl.flags && noted_decl.notes.count == 1 && noted_fresh_decl.notes.count == 1);
	note := noted_decl.notes[0];
	fresh_note := noted_fresh_decl.notes[0];
	assert(note.text == "Tag(1)" && note.text == fresh_note.text);
	assert(note.first_token == fresh_note.first_token && note.one_past_last_token == fresh_note.one_past_last_token);
	assert(note.l0 == fresh_note.l0 && note.c0 == fresh_note.c0 && note.l1 == fresh_note.l1 && note.c1 == fresh_note.c1);
	noted_body := noted_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block;
	noted_fresh_body := noted_fresh_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block;
	assert(noted_body.statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == noted_decl);
	assert(noted_fresh_body.statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == noted_fresh_decl);
	assert(noted_updated.diagnostics.count == noted_fresh.diagnostics.count && noted_updated.restart_points.count == noted_fresh.restart_points.count);
	assert_eligible_edit_matches_fresh(*noted_updated, *noted_fresh);
	Extended.release_parser_tree(*noted_old);
	Extended.release_parser_names(*noted_old);
	free(noted_old_source);
	assert(note.text == "Tag(1)" && Extended.reconstruct_source(*noted_updated) == noted_new_source);
	Extended.release_parser_tree(*noted_updated);
	Extended.release_parser_names(*noted_updated);
	Extended.release_parser_tree(*noted_fresh);
	Extended.release_parser_names(*noted_fresh);
	free(noted_new_source);

	scoped := Extended.parse_declaration("`value: s64;");
	assert(scoped.status == .COMPLETE);
	assert((scoped.root.(*Extended.Parser_Declaration).flags & .HAS_SCOPE_MODIFIER) != 0);
	scoped_old_source := copy_string(			  "`value := 1; use := value;");
	scoped_new_source := copy_string("added :: 0;\n`value := 1; use := value;");
	scoped_old := Extended.parse_file(scoped_old_source);
	scoped_updated, scoped_ok := Extended.parse_file_edit(*scoped_old, 0, 0, scoped_new_source);
	scoped_fresh := Extended.parse_file(scoped_new_source);
	assert(scoped_ok && scoped_old.status == .COMPLETE && scoped_updated.status == .COMPLETE && scoped_fresh.status == .COMPLETE);
	scoped_statements := scoped_updated.root.(*Extended.Parser_Block).statements;
	scoped_fresh_statements := scoped_fresh.root.(*Extended.Parser_Block).statements;
	scoped_tokens := Extended.materialise_tokens(scoped_new_source);
	scoped_probe := Extended.Parser.{parsed=*scoped_tokens, edit_source=*scoped_old, cursor=scoped_statements[1].first_token.(s64)};
	set_allocators(*scoped_tokens.node_pool, context.default_allocator);
	scoped_probe.current_scope = Extended.push_lexical_scope(*scoped_probe);
	scoped_tokens.root = Extended.reuse_simple_declaration(*scoped_probe);
	assert(scoped_tokens.root && scoped_tokens.root.(*Extended.Parser_Declaration).flags & .HAS_SCOPE_MODIFIER);
	Extended.release_parser_tree(*scoped_tokens);
	Extended.release_parser_names(*scoped_tokens);
	scoped_decl := scoped_statements[1].(*Extended.Parser_Declaration);
	scoped_fresh_decl := scoped_fresh_statements[1].(*Extended.Parser_Declaration);
	assert(scoped_decl.flags == scoped_fresh_decl.flags && scoped_decl.flags & .HAS_SCOPE_MODIFIER);
	assert(scoped_decl.first_token == scoped_fresh_decl.first_token && scoped_decl.one_past_last_token == scoped_fresh_decl.one_past_last_token);
	assert(Extended.token_at(*scoped_updated, scoped_decl.first_token).original_text == "`value");
	assert(scoped_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == scoped_decl);
	assert(scoped_fresh_statements[2].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Ident).resolved_declaration == scoped_fresh_decl);
	assert(scoped_updated.diagnostics.count == scoped_fresh.diagnostics.count && scoped_updated.restart_points.count == scoped_fresh.restart_points.count);
	Extended.release_parser_tree(*scoped_old);
	Extended.release_parser_names(*scoped_old);
	free(scoped_old_source);
	assert(scoped_decl.name == "value" && Extended.reconstruct_source(*scoped_updated) == scoped_new_source);
	Extended.release_parser_tree(*scoped_updated);
	Extended.release_parser_names(*scoped_updated);
	Extended.release_parser_tree(*scoped_fresh);
	Extended.release_parser_names(*scoped_fresh);
	free(scoped_new_source);

	EXPORTED_SOURCE :: "{ `it := value; `it_index: Coordinates; `visited_index := 0; }";
	exported := Extended.parse_block(EXPORTED_SOURCE);
	assert(exported.status == .COMPLETE);
	assert(exported.root.(*Extended.Parser_Block).statements.count == 3);
	for exported.root.(*Extended.Parser_Block).statements {
		declaration := it.(*Extended.Parser_Declaration);
		assert((declaration.flags & .HAS_SCOPE_MODIFIER) != 0);
		assert(Extended.token_at(*exported, declaration.first_token).original_text == tprint("`%", declaration.name));
	}

	assert(Extended.reconstruct_source(*exported) == EXPORTED_SOURCE);

	uninitialized := Extended.parse_declaration("value: s64 = ---;");
	assert(uninitialized.status == .COMPLETE);
	uninitialized_node := uninitialized.root.(*Extended.Parser_Declaration);
	assert((uninitialized_node.flags & .IS_UNINITIALIZED) != 0);
	assert(uninitialized_node.expression == null);

	auto_bake := Extended.parse_declaration("$T: Type;").root.(*Extended.Parser_Declaration);
	assert((auto_bake.flags & .AUTO_VALUE_BAKE) != 0);
	assert((auto_bake.flags & .AUTO_VALUE_BAKE_IS_REQUIRED) != 0);

	optional_bake := Extended.parse_declaration("$$T: Type;").root.(*Extended.Parser_Declaration);
	assert((optional_bake.flags & .AUTO_VALUE_BAKE) != 0);
	assert((optional_bake.flags & .AUTO_VALUE_BAKE_IS_REQUIRED) == 0);
}

Operator_Declaration_Fixture :: struct {
	source: string;
	name: string;
}

test_operator_declarations :: () {
	binary := Extended.parse_declaration("operator + :: (left: s64, right: s64) -> s64 #symmetric { return left + right; }");
	assert(binary.status == .COMPLETE);
	binary_declaration := binary.root.(*Extended.Parser_Declaration);
	assert(binary_declaration.name == "+");
	binary_header := binary_declaration.expression.(*Extended.Parser_Procedure_Header);
	assert(binary_header.arguments.count == 2);
	assert(binary_header.returns.count == 1);
	assert((binary_header.procedure_flags & .SYMMETRIC) != 0);
	assert(binary_header.body_or_null.block.statements.count == 1);

	unary := Extended.parse_declaration("operator - :: (value: s64) -> s64 { return -value; }");
	assert(unary.status == .COMPLETE);
	assert(unary.root.(*Extended.Parser_Declaration).name == "-");
	assert(unary.root.(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).arguments.count == 1);

	compound := Extended.parse_declaration("operator += :: (left: *s64, right: s64) { left.* += right; }");
	assert(compound.status == .COMPLETE);
	assert(compound.root.(*Extended.Parser_Declaration).name == "+=");

	fixtures := Operator_Declaration_Fixture.[
		.{source="operator + :: (left: s64, right: s64) -> s64 {}", name="+"},
		.{source="operator - :: (left: s64, right: s64) -> s64 {}", name="-"},
		.{source="operator * :: (left: s64, right: s64) -> s64 {}", name="*"},
		.{source="operator / :: (left: s64, right: s64) -> s64 {}", name="/"},
		.{source="operator % :: (left: s64, right: s64) -> s64 {}", name="%"},
		.{source="operator < :: (left: s64, right: s64) -> bool {}", name="<"},
		.{source="operator > :: (left: s64, right: s64) -> bool {}", name=">"},
		.{source="operator ! :: (value: s64) -> bool {}", name="!"},
		.{source="operator ~ :: (value: s64) -> s64 {}", name="~"},
		.{source="operator & :: (left: s64, right: s64) -> s64 {}", name="&"},
		.{source="operator | :: (left: s64, right: s64) -> s64 {}", name="|"},
		.{source="operator ^ :: (left: s64, right: s64) -> s64 {}", name="^"},
		.{source="operator == :: (left: s64, right: s64) -> bool {}", name="=="},
		.{source="operator != :: (left: s64, right: s64) -> bool {}", name="!="},
		.{source="operator <= :: (left: s64, right: s64) -> bool {}", name="<="},
		.{source="operator >= :: (left: s64, right: s64) -> bool {}", name=">="},
		.{source="operator && :: (left: s64, right: s64) -> bool {}", name="&&"},
		.{source="operator || :: (left: s64, right: s64) -> bool {}", name="||"},
		.{source="operator << :: (left: s64, right: s64) -> s64 {}", name="<<"},
		.{source="operator >> :: (left: s64, right: s64) -> s64 {}", name=">>"},
		.{source="operator <<< :: (left: s64, right: s64) -> s64 {}", name="<<<"},
		.{source="operator >>> :: (left: s64, right: s64) -> s64 {}", name=">>>"},
		.{source="operator += :: (left: *s64, right: s64) {}", name="+="},
		.{source="operator -= :: (left: *s64, right: s64) {}", name="-="},
		.{source="operator *= :: (left: *s64, right: s64) {}", name="*="},
		.{source="operator /= :: (left: *s64, right: s64) {}", name="/="},
		.{source="operator %= :: (left: *s64, right: s64) {}", name="%="},
		.{source="operator <<= :: (left: *s64, right: s64) {}", name="<<="},
		.{source="operator >>= :: (left: *s64, right: s64) {}", name=">>="},
		.{source="operator <<<= :: (left: *s64, right: s64) {}", name="<<<="},
		.{source="operator >>>= :: (left: *s64, right: s64) {}", name=">>>="},
		.{source="operator &= :: (left: *s64, right: s64) {}", name="&="},
		.{source="operator |= :: (left: *s64, right: s64) {}", name="|="},
		.{source="operator ^= :: (left: *s64, right: s64) {}", name="^="},
		.{source="operator &&= :: (left: *s64, right: s64) {}", name="&&="},
		.{source="operator ||= :: (left: *s64, right: s64) {}", name="||="},
		.{source="operator [] :: (value: s64, index: s64) -> s64 {}", name="[]"},
		.{source="operator []= :: (value: *s64, index: s64, replacement: s64) {}", name="[]="},
		.{source="operator *[] :: (value: *s64, index: s64) -> *s64 {}", name="*[]"},
	];
	assert(fixtures.count == 39);
	for fixtures {
		parsed := Extended.parse_declaration(it.source);
		assert(parsed.status == .COMPLETE, "Operator declaration did not parse: %", it.source);
		assert(parsed.root.(*Extended.Parser_Declaration).name == it.name);
	}
}

test_basic_statements_and_blocks :: () {
	parsed := Extended.parse_block("{ value := 1; value += 2; return value, 3; }");
	assert(parsed.status == .COMPLETE);
	block := parsed.root.(*Extended.Parser_Block);
	assert(block.block_type == .IMPERATIVE);
	assert(block.statements.count == 3);
	assert(block.statements[0].kind == .DECLARATION);
	assert(block.statements[1].kind == .BINARY_OPERATOR);
	return_node := block.statements[2].(*Extended.Parser_Return);
	assert(return_node.arguments_unsorted.count == 2);
	assert(return_node.arguments_unsorted[0].expression.(*Extended.Parser_Ident).name == "value");
	assert(return_node.arguments_unsorted[1].expression.(*Extended.Parser_Literal)._u64 == 3);

	controls := Extended.parse_block("{ break outer; continue; remove; }").root.(*Extended.Parser_Block);
	assert(controls.statements.count == 3);
	assert(controls.statements[0].(*Extended.Parser_Loop_Control).control_type == .BREAK);
	assert(controls.statements[0].(*Extended.Parser_Loop_Control).target_ident.name == "outer");
	assert(controls.statements[1].(*Extended.Parser_Loop_Control).control_type == .CONTINUE);
	assert(controls.statements[2].(*Extended.Parser_Loop_Control).control_type == .REMOVE);

	incomplete := Extended.parse_block("{ value := 1;");
	assert(incomplete.status == .INCOMPLETE);
	assert(incomplete.root.kind == .BLOCK);
	assert(incomplete.synthetic_tokens.count == 1);
	assert(incomplete.synthetic_tokens[0].token.type == #char "}");
}

test_loop_and_scoped_statements :: () {
	parsed := Extended.parse_block(#string JAI
{
	while ready {
		break;
	}
	for item, index: values {
		continue;
	}
	for 1..3	defer tick();
	using state;
	using local: State;
	push_context new_context {
		return;
	}
}
JAI);
	assert(parsed.status == .COMPLETE);
	block := parsed.root.(*Extended.Parser_Block);
	assert(block.statements.count == 6);

	while_node := block.statements[0].(*Extended.Parser_While);
	assert(while_node.condition.(*Extended.Parser_Ident).name == "ready");
	assert(while_node.block.parent == block);
	assert(while_node.block.owning_statement == while_node);
	assert(while_node.block.statements[0].kind == .LOOP_CONTROL);
	named_while := Extended.parse_block("{ while loop := ready { break loop; } }").root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_While);
	assert(named_while.condition.kind == .DECLARATION);

	collection_for := block.statements[1].(*Extended.Parser_For);
	assert(collection_for.ident_it.name == "item");
	assert(collection_for.ident_it_index.name == "index");
	assert(collection_for.iteration_expression.(*Extended.Parser_Ident).name == "values");

	range_for := block.statements[2].(*Extended.Parser_For);
	assert(range_for.iteration_expression.(*Extended.Parser_Literal)._u64 == 1);
	assert(range_for.iteration_expression_right.(*Extended.Parser_Literal)._u64 == 3);
	defer_node := range_for.block.statements[0].(*Extended.Parser_Defer);
	assert(defer_node.block.statements[0].kind == .PROCEDURE_CALL);

	// Prefix flags and selectors must leave both range endpoints and the following statement intact.
	PREFIXED_RANGE_SOURCE :: "{ for < * :utf8_iter value: 1..3 { process(value); } next(); }";
	prefixed_range := Extended.parse_block(PREFIXED_RANGE_SOURCE);
	assert(prefixed_range.status == .COMPLETE);
	prefixed_range_block := prefixed_range.root.(*Extended.Parser_Block);
	assert(prefixed_range_block.statements.count == 2);
	prefixed_range_loop := prefixed_range_block.statements[0].(*Extended.Parser_For);
	assert((prefixed_range_loop.for_flags & (.REVERSE | .POINTER)) == (.REVERSE | .POINTER));
	assert(prefixed_range_loop.want_replacement_for_expansion.(*Extended.Parser_Ident).name == "utf8_iter");
	assert(prefixed_range_loop.ident_it.name == "value");
	assert(prefixed_range_loop.iteration_expression.(*Extended.Parser_Literal)._u64 == 1);
	assert(prefixed_range_loop.iteration_expression_right.(*Extended.Parser_Literal)._u64 == 3);
	assert(prefixed_range_loop.block.statements[0].kind == .PROCEDURE_CALL);
	assert(prefixed_range_block.statements[1].kind == .PROCEDURE_CALL);
	assert(Extended.reconstruct_source(*prefixed_range) == PREFIXED_RANGE_SOURCE);

	PLAIN_RANGE_SOURCE :: "{ for value: first..last process(value); next(); }";
	plain_range := Extended.parse_block(PLAIN_RANGE_SOURCE);
	assert(plain_range.status == .COMPLETE);
	plain_range_block := plain_range.root.(*Extended.Parser_Block);
	assert(plain_range_block.statements.count == 2);
	plain_range_loop := plain_range_block.statements[0].(*Extended.Parser_For);
	assert(plain_range_loop.want_replacement_for_expansion == null);
	assert(plain_range_loop.for_flags == 0);
	assert(plain_range_loop.ident_it.name == "value");
	assert(plain_range_loop.iteration_expression.(*Extended.Parser_Ident).name == "first");
	assert(plain_range_loop.iteration_expression_right.(*Extended.Parser_Ident).name == "last");
	assert(plain_range_loop.block.statements[0].kind == .PROCEDURE_CALL);
	assert(Extended.reconstruct_source(*plain_range) == PLAIN_RANGE_SOURCE);

	CONTROLLED_RANGE_SOURCE :: "{ for <=reverse :utf8_iter value: first..last { process(value); } next(); }";
	controlled_range := Extended.parse_block(CONTROLLED_RANGE_SOURCE);
	assert(controlled_range.status == .COMPLETE);
	controlled_range_block := controlled_range.root.(*Extended.Parser_Block);
	assert(controlled_range_block.statements.count == 2);
	controlled_range_loop := controlled_range_block.statements[0].(*Extended.Parser_For);
	assert(controlled_range_loop.want_reverse_expression.(*Extended.Parser_Ident).name == "reverse");
	assert(controlled_range_loop.want_replacement_for_expansion.(*Extended.Parser_Ident).name == "utf8_iter");
	assert(controlled_range_loop.ident_it.name == "value");
	assert(controlled_range_loop.iteration_expression.(*Extended.Parser_Ident).name == "first");
	assert(controlled_range_loop.iteration_expression_right.(*Extended.Parser_Ident).name == "last");
	assert(controlled_range_loop.block.statements[0].kind == .PROCEDURE_CALL);
	assert(controlled_range_block.statements[1].kind == .PROCEDURE_CALL);
	assert(Extended.reconstruct_source(*controlled_range) == CONTROLLED_RANGE_SOURCE);

	reverse_for := Extended.parse_block("{ for < values process(it); }").root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_For);
	assert((reverse_for.for_flags & .REVERSE) != 0);
	assert(reverse_for.want_reverse_expression == null);

	pointer_for := Extended.parse_block("{ for * values process(it); }").root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_For);
	assert((pointer_for.for_flags & .POINTER) != 0);
	assert(pointer_for.want_pointer_expression == null);

	named_expansion := Extended.parse_block("{ for :utf8_iter value, index: text process(value); }").root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_For);
	assert(named_expansion.want_replacement_for_expansion.(*Extended.Parser_Ident).name == "utf8_iter");
	assert(named_expansion.ident_it.name == "value");
	assert(named_expansion.ident_it_index.name == "index");
	assert(named_expansion.iteration_expression.(*Extended.Parser_Ident).name == "text");

	combined_flags := Extended.parse_block("{ for < * :utf8_iter value, index: text process(value); }").root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_For);
	assert((combined_flags.for_flags & .REVERSE) != 0);
	assert((combined_flags.for_flags & .POINTER) != 0);
	assert(combined_flags.want_replacement_for_expansion.(*Extended.Parser_Ident).name == "utf8_iter");

	compact_flags := Extended.parse_block("{ for <* :utf8_iter text process(it); }").root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_For);
	assert((compact_flags.for_flags & (.REVERSE | .POINTER)) == (.REVERSE | .POINTER));
	assert(compact_flags.ident_it == null);
	assert(compact_flags.ident_it_index == null);

	// Implicit iterator names are supplied by expansion semantics, not syntax-owned identifiers.
	IMPLICIT_SOURCE :: "{ for values process(it); }";
	implicit := Extended.parse_block(IMPLICIT_SOURCE);
	assert(implicit.status == .COMPLETE);
	implicit_loop := implicit.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_For);
	assert(implicit_loop.ident_it == null);
	assert(implicit_loop.ident_it_index == null);
	assert(implicit_loop.iteration_expression.(*Extended.Parser_Ident).name == "values");
	assert(Extended.reconstruct_source(*implicit) == IMPLICIT_SOURCE);

	SELECTED_IMPLICIT_SOURCE :: "{ for :utf8_iter text process(it_index); }";
	selected_implicit := Extended.parse_block(SELECTED_IMPLICIT_SOURCE);
	assert(selected_implicit.status == .COMPLETE);
	selected_implicit_loop := selected_implicit.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_For);
	assert(selected_implicit_loop.want_replacement_for_expansion.(*Extended.Parser_Ident).name == "utf8_iter");
	assert(selected_implicit_loop.ident_it == null);
	assert(selected_implicit_loop.ident_it_index == null);
	assert(selected_implicit_loop.iteration_expression.(*Extended.Parser_Ident).name == "text");
	assert(Extended.reconstruct_source(*selected_implicit) == SELECTED_IMPLICIT_SOURCE);

	RENAMED_VALUE_SOURCE :: "{ for < :utf8_iter value: text process(value); }";
	renamed_value := Extended.parse_block(RENAMED_VALUE_SOURCE);
	assert(renamed_value.status == .COMPLETE);
	renamed_value_loop := renamed_value.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_For);
	assert((renamed_value_loop.for_flags & .REVERSE) != 0);
	assert(renamed_value_loop.want_replacement_for_expansion.(*Extended.Parser_Ident).name == "utf8_iter");
	assert(renamed_value_loop.ident_it.name == "value");
	assert(renamed_value_loop.ident_it_index == null);
	assert(renamed_value_loop.iteration_expression.(*Extended.Parser_Ident).name == "text");
	assert(Extended.reconstruct_source(*renamed_value) == RENAMED_VALUE_SOURCE);

	CONTROLLED_BINDINGS_SOURCE :: "{ for *=pointer_mode, <=reverse_mode :utf8_iter value, index: text process(value); }";
	controlled_bindings := Extended.parse_block(CONTROLLED_BINDINGS_SOURCE);
	assert(controlled_bindings.status == .COMPLETE);
	controlled_bindings_loop := controlled_bindings.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_For);
	assert(controlled_bindings_loop.want_pointer_expression.(*Extended.Parser_Ident).name == "pointer_mode");
	assert(controlled_bindings_loop.want_reverse_expression.(*Extended.Parser_Ident).name == "reverse_mode");
	assert(controlled_bindings_loop.want_replacement_for_expansion.(*Extended.Parser_Ident).name == "utf8_iter");
	assert(controlled_bindings_loop.ident_it.name == "value");
	assert(controlled_bindings_loop.ident_it_index.name == "index");
	assert(controlled_bindings_loop.iteration_expression.(*Extended.Parser_Ident).name == "text");
	assert(controlled_bindings_loop.ident_decl == null);
	assert(controlled_bindings_loop.index_decl == null);
	assert(controlled_bindings_loop.macro_expansion_procedure_call == null);
	assert(Extended.reconstruct_source(*controlled_bindings) == CONTROLLED_BINDINGS_SOURCE);

	// The synthetic single-statement block owns the semicolon; the call node does not.
	SINGLE_BODY_SOURCE :: "{ for <=reverse :utf8_iter value: text process(value); next(); }";
	single_body := Extended.parse_block(SINGLE_BODY_SOURCE);
	assert(single_body.status == .COMPLETE);
	single_body_parent := single_body.root.(*Extended.Parser_Block);
	assert(single_body_parent.statements.count == 2);
	single_body_loop := single_body_parent.statements[0].(*Extended.Parser_For);
	assert(single_body_loop.block.parent == single_body_parent);
	assert(single_body_loop.block.owning_statement == single_body_loop);
	assert(single_body_loop.block.statements.count == 1);
	assert(single_body_loop.block.first_token == single_body_loop.block.statements[0].first_token);
	assert(single_body_loop.block.one_past_last_token == single_body_loop.block.statements[0].one_past_last_token + 1);
	assert(single_body_loop.one_past_last_token == single_body_loop.block.one_past_last_token);
	assert(Extended.token_at(*single_body, single_body_loop.block.first_token).original_text == "process");
	assert(Extended.token_at(*single_body, single_body_loop.one_past_last_token - 1).original_text == ";");
	assert(Extended.token_at(*single_body, single_body_loop.one_past_last_token).original_text == "next");
	assert(Extended.reconstruct_source(*single_body) == SINGLE_BODY_SOURCE);

	BACKTICKED_BINDINGS_SOURCE :: "{ for :utf8_iter `it, `it_index: text process(it); }";
	backticked_bindings := Extended.parse_block(BACKTICKED_BINDINGS_SOURCE);
	assert(backticked_bindings.status == .COMPLETE);
	backticked_loop := backticked_bindings.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_For);
	assert(backticked_loop.ident_it.name == "it");
	assert((backticked_loop.ident_it.flags & .HAS_SCOPE_MODIFIER) != 0);
	assert(backticked_loop.ident_it_index.name == "it_index");
	assert((backticked_loop.ident_it_index.flags & .HAS_SCOPE_MODIFIER) != 0);
	assert(Extended.token_at(*backticked_bindings, backticked_loop.ident_it.first_token).original_text == "`it");
	assert(Extended.token_at(*backticked_bindings, backticked_loop.ident_it_index.first_token).original_text == "`it_index");
	assert(Extended.reconstruct_source(*backticked_bindings) == BACKTICKED_BINDINGS_SOURCE);

	controlled_reverse := Extended.parse_block("{ for <=reversed NAMES print(it); }");
	assert(controlled_reverse.status == .COMPLETE);
	reverse_loop := controlled_reverse.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_For);
	assert(reverse_loop.want_reverse_expression.(*Extended.Parser_Ident).name == "reversed");
	assert(reverse_loop.iteration_expression.(*Extended.Parser_Ident).name == "NAMES");

	controlled_both := Extended.parse_block("{ for *=cast(bool)(flags & .POINTER), <=cast(bool)(flags & .REVERSE) a.data print(it); }");
	assert(controlled_both.status == .COMPLETE);
	controlled_loop := controlled_both.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_For);
	assert(controlled_loop.want_pointer_expression.kind == .CAST);
	assert(controlled_loop.want_reverse_expression.kind == .CAST);
	assert(controlled_loop.iteration_expression.kind == .BINARY_OPERATOR);
	assert(controlled_loop.for_flags == 0);
	assert(Extended.reconstruct_source(*controlled_both) == "{ for *=cast(bool)(flags & .POINTER), <=cast(bool)(flags & .REVERSE) a.data print(it); }");

	controlled_pointer := Extended.parse_block("{ for *=pointer_mode values process(it); }");
	assert(controlled_pointer.status == .COMPLETE);
	pointer_loop := controlled_pointer.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_For);
	assert(pointer_loop.want_pointer_expression.(*Extended.Parser_Ident).name == "pointer_mode");
	assert(pointer_loop.iteration_expression.(*Extended.Parser_Ident).name == "values");

	// Parentheses keep comparison and assignment operators inside controlled flag values.
	COMPARISON_SOURCE :: "{ for *=(left == right), <=reverse values process(it); }";
	comparison := Extended.parse_block(COMPARISON_SOURCE);
	assert(comparison.status == .COMPLETE);
	comparison_loop := comparison.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_For);
	assert(comparison_loop.want_pointer_expression.(*Extended.Parser_Binary_Operator).operator_type == .IS_EQUAL);
	assert(comparison_loop.want_reverse_expression.(*Extended.Parser_Ident).name == "reverse");
	assert(comparison_loop.iteration_expression.(*Extended.Parser_Ident).name == "values");
	assert(Extended.reconstruct_source(*comparison) == COMPARISON_SOURCE);

	ASSIGNMENT_SOURCE :: "{ for <=(flag = enabled) values process(it); }";
	assignment := Extended.parse_block(ASSIGNMENT_SOURCE);
	assert(assignment.status == .COMPLETE);
	assignment_loop := assignment.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_For);
	assert(assignment_loop.want_reverse_expression.(*Extended.Parser_Binary_Operator).operator_type == #char "=");
	assert(assignment_loop.iteration_expression.(*Extended.Parser_Ident).name == "values");
	assert(Extended.reconstruct_source(*assignment) == ASSIGNMENT_SOURCE);

	// Unparenthesized operators instead belong to the collection expression.
	COMPARISON_COLLECTION_SOURCE :: "{ for <=reverse left == right process(it); }";
	comparison_collection := Extended.parse_block(COMPARISON_COLLECTION_SOURCE);
	assert(comparison_collection.status == .COMPLETE);
	comparison_collection_loop := comparison_collection.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_For);
	assert(comparison_collection_loop.want_reverse_expression.(*Extended.Parser_Ident).name == "reverse");
	assert(comparison_collection_loop.iteration_expression.(*Extended.Parser_Binary_Operator).operator_type == .IS_EQUAL);
	assert(Extended.reconstruct_source(*comparison_collection) == COMPARISON_COLLECTION_SOURCE);

	ASSIGNMENT_COLLECTION_SOURCE :: "{ for <=reverse target = source process(it); }";
	assignment_collection := Extended.parse_block(ASSIGNMENT_COLLECTION_SOURCE);
	assert(assignment_collection.status == .COMPLETE);
	assignment_collection_loop := assignment_collection.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_For);
	assert(assignment_collection_loop.want_reverse_expression.(*Extended.Parser_Ident).name == "reverse");
	assert(assignment_collection_loop.iteration_expression.(*Extended.Parser_Binary_Operator).operator_type == #char "=");
	assert(Extended.reconstruct_source(*assignment_collection) == ASSIGNMENT_COLLECTION_SOURCE);
	bare_comparison := Extended.parse_block("{ for <=left == right values process(it); }");
	assert(bare_comparison.status != .COMPLETE);
	bare_assignment := Extended.parse_block("{ for <=flag = enabled values process(it); }");
	assert(bare_assignment.status != .COMPLETE);
	reversed_order := Extended.parse_block("{ for <=reverse, *=pointer_mode values process(it); }");
	assert(reversed_order.status == .COMPLETE);
	reversed_order_loop := reversed_order.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_For);
	assert(reversed_order_loop.want_reverse_expression.(*Extended.Parser_Ident).name == "reverse");
	assert(reversed_order_loop.want_pointer_expression.(*Extended.Parser_Ident).name == "pointer_mode");
	assert(reversed_order_loop.iteration_expression.(*Extended.Parser_Ident).name == "values");
	missing_flag_comma := Extended.parse_block("{ for *=pointer_mode <=reversed values process(it); }");
	assert(missing_flag_comma.status == .RECOVERED);
	assert(missing_flag_comma.diagnostics[0].expected_token == #char ",");
	assert(Extended.token_at(*missing_flag_comma, missing_flag_comma.diagnostics[0].span.first).original_text == "<=");
	missing_comma_loop := missing_flag_comma.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_For);
	assert(missing_comma_loop.want_pointer_expression.(*Extended.Parser_Ident).name == "pointer_mode");
	assert(missing_comma_loop.want_reverse_expression.(*Extended.Parser_Ident).name == "reversed");
	assert(missing_comma_loop.iteration_expression.(*Extended.Parser_Ident).name == "values");
	assert(Extended.reconstruct_source(*missing_flag_comma) == "{ for *=pointer_mode <=reversed values process(it); }");

	MISSING_SELECTOR_SOURCE :: "{ for : { tick(); } after(); }";
	missing_selector := Extended.parse_block(MISSING_SELECTOR_SOURCE);
	assert(missing_selector.status == .RECOVERED);
	selector_block := missing_selector.root.(*Extended.Parser_Block);
	assert(selector_block.statements[0].kind == .FOR);
	assert(selector_block.statements[0].(*Extended.Parser_For).want_replacement_for_expansion == null);
	assert(Extended.reconstruct_source(*missing_selector) == MISSING_SELECTOR_SOURCE);

	MISSING_INDEX_SOURCE :: "{ for value,: values { tick(); } after(); }";
	missing_index := Extended.parse_block(MISSING_INDEX_SOURCE);
	assert(missing_index.status == .RECOVERED);
	index_loop := missing_index.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_For);
	assert(index_loop.ident_it.name == "value");
	assert(index_loop.ident_it_index == null);
	assert(index_loop.iteration_expression.(*Extended.Parser_Ident).name == "values");
	assert(Extended.reconstruct_source(*missing_index) == MISSING_INDEX_SOURCE);

	MISSING_BINDING_COLON_SOURCE :: "{ for value, index values { tick(); } after(); }";
	missing_binding_colon := Extended.parse_block(MISSING_BINDING_COLON_SOURCE);
	assert(missing_binding_colon.status == .RECOVERED);
	assert(missing_binding_colon.diagnostics[0].expected_token == #char ":");
	colon_loop := missing_binding_colon.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_For);
	assert(colon_loop.ident_it.name == "value");
	assert(colon_loop.ident_it_index.name == "index");
	assert(colon_loop.iteration_expression.(*Extended.Parser_Ident).name == "values");
	assert(Extended.reconstruct_source(*missing_binding_colon) == MISSING_BINDING_COLON_SOURCE);

	malformed_prefixes := string.[
		"for : ",
		"for <= ",
		"for *= ",
		"for value,: values ",
		"for value, index values ",
		"for *=pointer_mode <=reverse values ",
		"for < < values ",
	];
	for prefix: malformed_prefixes {
		source := tprint("outer :: () { % { local := 1; } after := 2; }\nfinal :: 3;", prefix);
		parsed_file := Extended.parse_file(source);
		assert(parsed_file.status == .RECOVERED, "Expected recovery for %", prefix);
		file_statements := parsed_file.root.(*Extended.Parser_Block).statements;
		assert(file_statements.count == 2, "Lost file-scope declaration after %", prefix);
		procedure_body := file_statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block;
		assert(procedure_body.statements.count == 2, "Lost procedure statement after %", prefix);
		partial_for := procedure_body.statements[0].(*Extended.Parser_For);
		assert(partial_for.block != null, "Lost loop body after %", prefix);
		assert(partial_for.block.statements.count == 1);
		assert(partial_for.block.statements[0].(*Extended.Parser_Declaration).name == "local");
		assert(procedure_body.statements[1].(*Extended.Parser_Declaration).name == "after");
		assert(file_statements[1].(*Extended.Parser_Declaration).name == "final");
		assert(Extended.reconstruct_source(*parsed_file) == source);
	}

	MALFORMED_SINGLE_BODY_SOURCE :: "outer :: () { for value,: values tick(); after := 2; }\nfinal :: 3;";
	single_body_file := Extended.parse_file(MALFORMED_SINGLE_BODY_SOURCE);
	assert(single_body_file.status == .RECOVERED);
	single_file_statements := single_body_file.root.(*Extended.Parser_Block).statements;
	assert(single_file_statements.count == 2);
	single_procedure_body := single_file_statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block;
	assert(single_procedure_body.statements.count == 2);
	single_for := single_procedure_body.statements[0].(*Extended.Parser_For);
	assert(single_for.ident_it.name == "value" && single_for.ident_it_index == null);
	assert(single_for.iteration_expression.(*Extended.Parser_Ident).name == "values");
	assert(single_for.block.statements.count == 1 && single_for.block.statements[0].kind == .PROCEDURE_CALL);
	assert(single_procedure_body.statements[1].(*Extended.Parser_Declaration).name == "after");
	assert(single_file_statements[1].(*Extended.Parser_Declaration).name == "final");
	assert(Extended.reconstruct_source(*single_body_file) == MALFORMED_SINGLE_BODY_SOURCE);

	using_expression := block.statements[3].(*Extended.Parser_Using);
	assert(using_expression.expression.(*Extended.Parser_Ident).name == "state");
	using_declaration := block.statements[4].(*Extended.Parser_Using);
	assert(using_declaration.expression.kind == .DECLARATION);

	push := block.statements[5].(*Extended.Parser_Push_Context);
	assert(push.to_push.(*Extended.Parser_Ident).name == "new_context");
	assert(push.block.parent == block);
	assert(push.block.owning_statement == push);
	deferred_push := Extended.parse_block("{ `push_context,defer_pop remap_context(); }").root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Push_Context);
	assert((deferred_push.push_context_flags & .IS_BACKTICKED) != 0);
	assert((deferred_push.push_context_flags & .DEFER_POP) != 0);
	assert(deferred_push.block == null);
	backticked := Extended.parse_block("{ `defer cleanup(); `return 1; }").root.(*Extended.Parser_Block);
	assert(backticked.statements[0].(*Extended.Parser_Defer).is_backticked);
	assert((backticked.statements[1].(*Extended.Parser_Return).return_flags & .IS_BACKTICKED) != 0);
}

test_for_body_forms :: () {
	prefixes := string.[
		"values",
		":utf8_iter values",
		"< values",
		"* values",
		"< * values",
		"<* values",
		"< :utf8_iter values",
		"* :utf8_iter values",
		"< * :utf8_iter values",
		"<* :utf8_iter values",
		"<=reverse values",
		"*=pointer_mode values",
		"<=reverse, *=pointer_mode values",
		"*=pointer_mode, <=reverse values",
		"<=reverse :utf8_iter values",
		"*=pointer_mode :utf8_iter values",
		"<=reverse, *=pointer_mode :utf8_iter values",
		"*=pointer_mode, <=reverse :utf8_iter values",
		"* <=reverse values",
		"< *=pointer_mode values",
		"* <=reverse :utf8_iter values",
		"< *=pointer_mode :utf8_iter values",
		"value, index: values",
		":positive_vibes_only value, index: values",
		":extra_info value, index: values",
		":polite values",
		"< :polite values",
		"*=cast(bool)(flags & .POINTER), <=cast(bool)(flags & .REVERSE) values",
		"`it, `it_index: values",
	];
	bodies := string.["process(it);", "{ process(it); }"];
	for prefix: prefixes {
		for body: bodies {
			source := tprint("{ for % % next(); }", prefix, body);
			parsed := Extended.parse_block(source);
			assert(parsed.status == .COMPLETE, "Loop body did not parse: %", source);
			root := parsed.root.(*Extended.Parser_Block);
			assert(root.statements.count == 2);
			loop := root.statements[0].(*Extended.Parser_For);
			assert(loop.block.parent == root);
			assert(loop.block.owning_statement == loop);
			assert(loop.block.statements.count == 1);
			assert(loop.block.statements[0].kind == .PROCEDURE_CALL);
			assert(loop.first_token < loop.block.first_token);
			assert(loop.block.first_token <= loop.block.statements[0].first_token);
			assert(loop.block.statements[0].one_past_last_token <= loop.block.one_past_last_token);
			assert(loop.one_past_last_token == loop.block.one_past_last_token);
			assert(root.statements[1].first_token == loop.one_past_last_token);
			assert(Extended.token_at(*parsed, loop.first_token).original_text == "for");
			assert(Extended.token_at(*parsed, loop.block.first_token).original_text == (ifx body == bodies[0] then "process" else "{"));
			assert(Extended.token_at(*parsed, loop.block.one_past_last_token - 1).original_text == (ifx body == bodies[0] then ";" else "}"));
			assert(Extended.token_at(*parsed, loop.one_past_last_token).original_text == "next");
			assert(Extended.reconstruct_source(*parsed) == source);
		}
	}
}

test_duplicate_for_flags :: () {
	LITERAL_REVERSE_SOURCE :: "{ for < < values process(it); }";
	literal_reverse := Extended.parse_block(LITERAL_REVERSE_SOURCE);
	assert(literal_reverse.status == .RECOVERED);
	assert(literal_reverse.diagnostics.count == 1);
	assert(literal_reverse.recovery_records.count == 1);
	assert(literal_reverse.recovery_records[0].kind == .ERROR_SPAN);
	assert(literal_reverse.recovery_records[0].diagnostic_index == 0);
	assert(literal_reverse.recovery_records[0].synthetic_token_index == -1);
	literal_reverse_loop := literal_reverse.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_For);
	assert((literal_reverse_loop.for_flags & .REVERSE) != 0);
	assert(literal_reverse_loop.iteration_expression.(*Extended.Parser_Ident).name == "values");
	assert(Extended.reconstruct_source(*literal_reverse) == LITERAL_REVERSE_SOURCE);

	LITERAL_POINTER_SOURCE :: "{ for * * values process(it); }";
	literal_pointer := Extended.parse_block(LITERAL_POINTER_SOURCE);
	assert(literal_pointer.status == .RECOVERED);
	assert(literal_pointer.diagnostics.count == 1);
	assert(Extended.token_at(*literal_pointer, literal_pointer.diagnostics[0].span.first).original_text == "*");
	literal_pointer_loop := literal_pointer.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_For);
	assert((literal_pointer_loop.for_flags & .POINTER) != 0);
	assert(literal_pointer_loop.iteration_expression.(*Extended.Parser_Ident).name == "values");
	assert(Extended.reconstruct_source(*literal_pointer) == LITERAL_POINTER_SOURCE);

	CONTROLLED_REVERSE_SOURCE :: "{ for <=first, <=second values process(it); }";
	controlled_reverse := Extended.parse_block(CONTROLLED_REVERSE_SOURCE);
	assert(controlled_reverse.status == .RECOVERED);
	assert(controlled_reverse.diagnostics.count == 1);
	assert(Extended.token_at(*controlled_reverse, controlled_reverse.diagnostics[0].span.first).original_text == "<=");
	controlled_reverse_loop := controlled_reverse.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_For);
	assert(controlled_reverse_loop.want_reverse_expression.(*Extended.Parser_Ident).name == "first");
	assert(controlled_reverse_loop.iteration_expression.(*Extended.Parser_Ident).name == "values");
	assert(Extended.reconstruct_source(*controlled_reverse) == CONTROLLED_REVERSE_SOURCE);

	CONTROLLED_POINTER_SOURCE :: "{ for *=first, *=second values process(it); }";
	controlled_pointer := Extended.parse_block(CONTROLLED_POINTER_SOURCE);
	assert(controlled_pointer.status == .RECOVERED);
	assert(controlled_pointer.diagnostics.count == 1);
	controlled_pointer_loop := controlled_pointer.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_For);
	assert(controlled_pointer_loop.want_pointer_expression.(*Extended.Parser_Ident).name == "first");
	assert(controlled_pointer_loop.iteration_expression.(*Extended.Parser_Ident).name == "values");
	assert(Extended.reconstruct_source(*controlled_pointer) == CONTROLLED_POINTER_SOURCE);

	MIXED_REVERSE_SOURCE :: "{ for < <=reverse values process(it); }";
	mixed_reverse := Extended.parse_block(MIXED_REVERSE_SOURCE);
	assert(mixed_reverse.status == .RECOVERED);
	assert(mixed_reverse.diagnostics.count == 1);
	mixed_reverse_loop := mixed_reverse.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_For);
	assert((mixed_reverse_loop.for_flags & .REVERSE) != 0);
	assert(mixed_reverse_loop.want_reverse_expression == null);
	assert(mixed_reverse_loop.iteration_expression.(*Extended.Parser_Ident).name == "values");
	assert(Extended.reconstruct_source(*mixed_reverse) == MIXED_REVERSE_SOURCE);

	MIXED_POINTER_SOURCE :: "{ for * *=pointer_mode values process(it); }";
	mixed_pointer := Extended.parse_block(MIXED_POINTER_SOURCE);
	assert(mixed_pointer.status == .RECOVERED);
	assert(mixed_pointer.diagnostics.count == 1);
	mixed_pointer_loop := mixed_pointer.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_For);
	assert((mixed_pointer_loop.for_flags & .POINTER) != 0);
	assert(mixed_pointer_loop.want_pointer_expression == null);
	assert(mixed_pointer_loop.iteration_expression.(*Extended.Parser_Ident).name == "values");
	assert(Extended.reconstruct_source(*mixed_pointer) == MIXED_POINTER_SOURCE);

	CONTROLLED_THEN_LITERAL_REVERSE_SOURCE :: "{ for <=reverse < values process(it); }";
	controlled_then_literal_reverse := Extended.parse_block(CONTROLLED_THEN_LITERAL_REVERSE_SOURCE);
	assert(controlled_then_literal_reverse.status == .RECOVERED);
	assert(controlled_then_literal_reverse.diagnostics.count == 1);
	controlled_then_literal_reverse_loop := controlled_then_literal_reverse.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_For);
	assert(controlled_then_literal_reverse_loop.want_reverse_expression.(*Extended.Parser_Ident).name == "reverse");
	assert((controlled_then_literal_reverse_loop.for_flags & .REVERSE) == 0);
	assert(controlled_then_literal_reverse_loop.iteration_expression.(*Extended.Parser_Ident).name == "values");
	assert(Extended.reconstruct_source(*controlled_then_literal_reverse) == CONTROLLED_THEN_LITERAL_REVERSE_SOURCE);

	CONTROLLED_THEN_LITERAL_POINTER_SOURCE :: "{ for *=pointer_mode * values process(it); }";
	controlled_then_literal_pointer := Extended.parse_block(CONTROLLED_THEN_LITERAL_POINTER_SOURCE);
	assert(controlled_then_literal_pointer.status == .RECOVERED);
	assert(controlled_then_literal_pointer.diagnostics.count == 1);
	controlled_then_literal_pointer_loop := controlled_then_literal_pointer.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_For);
	assert(controlled_then_literal_pointer_loop.want_pointer_expression.(*Extended.Parser_Ident).name == "pointer_mode");
	assert((controlled_then_literal_pointer_loop.for_flags & .POINTER) == 0);
	assert(controlled_then_literal_pointer_loop.iteration_expression.(*Extended.Parser_Ident).name == "values");
	assert(Extended.reconstruct_source(*controlled_then_literal_pointer) == CONTROLLED_THEN_LITERAL_POINTER_SOURCE);
}

test_conditional_statements :: () {
	parsed := Extended.parse_block(#string JAI
{
	if ready
		then run();
		else stop();
	if outer
		then if inner
			accept();
			else reject();
}
JAI);
	assert(parsed.status == .COMPLETE);
	block := parsed.root.(*Extended.Parser_Block);
	assert(block.statements.count == 2);
	first_if := block.statements[0].(*Extended.Parser_If);
	assert(first_if.then_block.statements[0].kind == .PROCEDURE_CALL);
	assert(first_if.else_block.statements[0].kind == .PROCEDURE_CALL);
	nested_if := block.statements[1].(*Extended.Parser_If).then_block.statements[0].(*Extended.Parser_If);
	assert(nested_if.else_block != null);

	CONDITION_SOURCE :: #string JAI
{
	if (mode == .ALLOCATE) && (size == 42) {
		run();
	}
	if (count % 2) {
		run();
	}
	if (pointer) {
		run();
	}
	while (pointer) {
		break;
	}
}
JAI;
	conditions := Extended.parse_block(CONDITION_SOURCE);
	assert(conditions.status == .COMPLETE);
	condition_statements := conditions.root.(*Extended.Parser_Block).statements;
	assert(condition_statements.count == 4);
	assert(condition_statements[0].(*Extended.Parser_If).condition.kind == .BINARY_OPERATOR);
	assert(condition_statements[1].(*Extended.Parser_If).condition.kind == .BINARY_OPERATOR);
	assert(condition_statements[2].(*Extended.Parser_If).condition.kind == .IDENT);
	assert((condition_statements[2].(*Extended.Parser_If).condition.node_flags & .IS_PARENTHESIZED) != 0);
	assert(condition_statements[3].(*Extended.Parser_While).condition.kind == .IDENT);
	assert(Extended.reconstruct_source(*conditions) == CONDITION_SOURCE);
	assert(Extended.parse_expression("(value: s64) { return; }").status == .COMPLETE);
	malformed_condition := Extended.parse_block("{ if (count ==) { run(); } after(); }");
	assert(malformed_condition.status == .RECOVERED);
	assert(Extended.reconstruct_source(*malformed_condition) == "{ if (count ==) { run(); } after(); }");

	ifx_expression := Extended.parse_expression("ifx ready then 1 else 2");
	assert(ifx_expression.status == .COMPLETE);
	ifx_node := ifx_expression.root.(*Extended.Parser_If);
	assert((ifx_node.if_flags & .IS_IFX) != 0);
	assert(ifx_node.then_block.statements[0].(*Extended.Parser_Literal)._u64 == 1);
	assert(ifx_node.else_block.statements[0].(*Extended.Parser_Literal)._u64 == 2);
	default_ifx := Extended.parse_expression("ifx ready then 1");
	assert(default_ifx.status == .COMPLETE);
	assert(default_ifx.root.(*Extended.Parser_If).else_block == null);
	assert(default_ifx.root.(*Extended.Parser_If).then_block.statements[0].(*Extended.Parser_Literal)._u64 == 1);

	// Missing branches in value-form ifx are legal; the next statement stays in the outer block.
	DEFAULT_SOURCE :: "{ name := ifx thing then thing.name; next(); }";
	default_block := Extended.parse_block(DEFAULT_SOURCE);
	assert(default_block.status == .COMPLETE);
	default_statements := default_block.root.(*Extended.Parser_Block).statements;
	assert(default_statements.count == 2);
	assert(default_statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_If).else_block == null);
	assert(default_statements[1].kind == .PROCEDURE_CALL);
	assert(Extended.reconstruct_source(*default_block) == DEFAULT_SOURCE);

	OMITTED_THEN_SOURCE :: "{ y2 := ifx x else 1; next(); }";
	omitted_then := Extended.parse_block(OMITTED_THEN_SOURCE);
	assert(omitted_then.status == .COMPLETE);
	omitted_then_statements := omitted_then.root.(*Extended.Parser_Block).statements;
	assert(omitted_then_statements.count == 2);
	omitted_then_ifx := omitted_then_statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_If);
	assert(omitted_then_ifx.then_block == null);
	assert(omitted_then_ifx.else_block.statements[0].(*Extended.Parser_Literal)._u64 == 1);
	assert(omitted_then_statements[1].kind == .PROCEDURE_CALL);
	assert(Extended.reconstruct_source(*omitted_then) == OMITTED_THEN_SOURCE);
	assert(Extended.parse_block("{ y2 := ifx x then else 1; next(); }").status == .RECOVERED);
	branchless_expression := Extended.parse_expression("ifx is_odd(x)");
	assert(branchless_expression.status == .COMPLETE);
	assert(branchless_expression.root.(*Extended.Parser_If).then_block == null);
	assert(branchless_expression.root.(*Extended.Parser_If).else_block == null);

	BRANCHLESS_SOURCE :: "{ y4 := ifx is_odd(x); next(); }";
	branchless := Extended.parse_block(BRANCHLESS_SOURCE);
	assert(branchless.status == .COMPLETE);
	branchless_statements := branchless.root.(*Extended.Parser_Block).statements;
	assert(branchless_statements.count == 2);
	assert(branchless_statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_If).then_block == null);
	assert(branchless_statements[1].kind == .PROCEDURE_CALL);
	assert(Extended.reconstruct_source(*branchless) == BRANCHLESS_SOURCE);
	assert(Extended.parse_block("{ y4 := ifx is_odd(x) then; next(); }").status == .RECOVERED);

	block_ifx := Extended.parse_expression("ifx ready { prepare(); 1; } else { 2; }");
	assert(block_ifx.status == .COMPLETE);
	assert(block_ifx.root.(*Extended.Parser_If).then_block.statements.count == 2);

	BRACED_SOURCE :: "{ value := ifx ready { prepare(); 1; } else { 2; } next(); }";
	braced := Extended.parse_block(BRACED_SOURCE);
	assert(braced.status == .COMPLETE);
	braced_statements := braced.root.(*Extended.Parser_Block).statements;
	assert(braced_statements.count == 2);
	assert(braced_statements[0].(*Extended.Parser_Declaration).expression.kind == .IF);
	assert(braced_statements[1].kind == .PROCEDURE_CALL);
	assert(Extended.reconstruct_source(*braced) == BRACED_SOURCE);
	braced_semicolon := Extended.parse_block("{ value := ifx ready { 1; } else { 2; }; next(); }");
	assert(braced_semicolon.status == .COMPLETE);
	assert(braced_semicolon.root.(*Extended.Parser_Block).statements.count == 2);
	assert(braced_semicolon.root.(*Extended.Parser_Block).statements[1].kind == .PROCEDURE_CALL);
	assert(Extended.reconstruct_source(*braced_semicolon) == "{ value := ifx ready { 1; } else { 2; }; next(); }");
	assert(braced_semicolon.diagnostics.count == 0);

	warned_semicolon := Extended.parse_block("{ value := ifx ready { 1; } else { 2; }; next(); }", warn_unnecessary_semicolons=true);
	assert(warned_semicolon.status == .COMPLETE && warned_semicolon.diagnostics.count == 1);
	assert(warned_semicolon.diagnostics[0].kind == .UNNECESSARY_SEMICOLON);
	assert(warned_semicolon.diagnostics[0].severity == .WARNING);
	assert(Extended.token_at(*warned_semicolon, warned_semicolon.diagnostics[0].span.first).original_text == ";");
	assert(warned_semicolon.recovery_records.count == 0);
	assert(warned_semicolon.root.(*Extended.Parser_Block).statements.count == 2);

	assert(Extended.parse_block("{ value := ifx ready then 1 else 2; next(); }", warn_unnecessary_semicolons=true).diagnostics.count == 0);
	optional_semicolons := Extended.parse_block("{ if ready { done(); }; while ready { tick(); }; value := 1; }", warn_unnecessary_semicolons=true);
	assert(optional_semicolons.status == .COMPLETE && optional_semicolons.diagnostics.count == 2);
	for optional_semicolons.diagnostics {
		assert(it.kind == .UNNECESSARY_SEMICOLON && it.severity == .WARNING);
		assert(it.span.one_past_last == it.span.first + 1);
	}

	assert(optional_semicolons.root.(*Extended.Parser_Block).statements.count == 3);

	file_semicolon := Extended.parse_file("Value :: struct {};", warn_unnecessary_semicolons=true);
	assert(file_semicolon.status == .COMPLETE && file_semicolon.diagnostics.count == 1);
	assert(file_semicolon.diagnostics[0].kind == .UNNECESSARY_SEMICOLON);

	assert(Extended.parse_file("Value :: struct {};").diagnostics.count == 0);
	declaration_semicolon := Extended.parse_declaration("Value :: struct {};", warn_unnecessary_semicolons=true);
	assert(declaration_semicolon.status == .COMPLETE && declaration_semicolon.diagnostics.count == 1);
	assert(declaration_semicolon.diagnostics[0].kind == .UNNECESSARY_SEMICOLON);
	assert(Extended.parse_block("{ value := ifx ready then 1 else 2 next(); }").status == .RECOVERED);

	SWITCH_SOURCE :: #string JAI
{
	if #complete value == {
		case 1;
			return 1;

		case 2; #through;
		case 3;
			return 3;

		case;
			return 0;
	}
}
JAI;
	switch_parsed := Extended.parse_block(SWITCH_SOURCE);
	assert(switch_parsed.status == .COMPLETE);
	switch_node := switch_parsed.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_If);
	assert((switch_node.if_flags & .IS_SWITCH_STATEMENT) != 0);
	assert((switch_node.if_flags & .MARKED_AS_COMPLETE) != 0);
	assert(switch_node.then_block.statements.count == 4);
	first_case := switch_node.then_block.statements[0].(*Extended.Parser_Case);
	assert(first_case.condition.(*Extended.Parser_Literal)._u64 == 1);
	second_case := switch_node.then_block.statements[1].(*Extended.Parser_Case);
	assert(second_case.condition.(*Extended.Parser_Literal)._u64 == 2);
	assert(second_case.marked_as_fallthrough);
	warned_through := Extended.parse_block(SWITCH_SOURCE, warn_unnecessary_semicolons=true);
	assert(warned_through.status == .COMPLETE && warned_through.diagnostics.count == 1);
	assert(warned_through.diagnostics[0].kind == .UNNECESSARY_SEMICOLON);
	default_case := switch_node.then_block.statements[3].(*Extended.Parser_Case);
	assert(default_case.condition == null);
	assert(default_case.owning_if == switch_node);

	empty_default := Extended.parse_block("{ if value == { case 1; return; case; } }");
	assert(empty_default.status == .COMPLETE);
	assert(empty_default.synthetic_tokens.count == 0);
	empty_default_cases := empty_default.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_If).then_block.statements;
	assert(empty_default_cases.count == 2);
	assert(empty_default_cases[1].(*Extended.Parser_Case).condition == null);
	assert(empty_default_cases[1].(*Extended.Parser_Case).then_block.statements.count == 0);

	unmatched_parenthesis := Extended.materialise_tokens("value) == {");
	unmatched_parenthesis_parser := Extended.Parser.{parsed=*unmatched_parenthesis};
	assert(!Extended.has_switch_case_block(*unmatched_parenthesis_parser));

	unmatched_bracket := Extended.materialise_tokens("value] == {");
	unmatched_bracket_parser := Extended.Parser.{parsed=*unmatched_bracket};
	assert(!Extended.has_switch_case_block(*unmatched_bracket_parser));
}

test_static_if_directives :: () {
	static_ifx_expression := Extended.parse_expression("#ifx ready then 1 else 2");
	assert(static_ifx_expression.status == .COMPLETE);
	static_ifx := static_ifx_expression.root.(*Extended.Parser_If);
	assert((static_ifx.if_flags & (.IS_STATIC | .IS_IFX)) == (.IS_STATIC | .IS_IFX));
	assert(static_ifx.then_block.statements[0].(*Extended.Parser_Literal)._u64 == 1);
	assert(static_ifx.else_block.statements[0].(*Extended.Parser_Literal)._u64 == 2);

	STATIC_IFX_SOURCE :: #string JAI
{
	value := #ifx ready {
		prepare();
		1;
	} else {
		2;
	}
	next();
}
JAI;
	static_ifx_block := Extended.parse_block(STATIC_IFX_SOURCE);
	assert(static_ifx_block.status == .COMPLETE);
	static_ifx_statements := static_ifx_block.root.(*Extended.Parser_Block).statements;
	assert(static_ifx_statements.count == 2);
	assert((static_ifx_statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_If).if_flags & .IS_STATIC) != 0);
	assert(static_ifx_statements[1].kind == .PROCEDURE_CALL);
	assert(Extended.reconstruct_source(*static_ifx_block) == STATIC_IFX_SOURCE);
	assert(Extended.parse_block("{ value := #ifx ready then else 2; next(); }").status == .RECOVERED);

	static_statement := Extended.parse_block(#string JAI
{
	#if true {
		enabled := 1;
	} else #if false
		disabled := 2;
		else fallback := 3;
}
JAI);
	assert(static_statement.status == .COMPLETE);
	static_if := static_statement.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_If);
	assert((static_if.if_flags & .IS_STATIC) != 0);
	assert(static_if.then_block.block_type == .IMPERATIVE);
	nested_static_if := static_if.else_block.statements[0].(*Extended.Parser_If);
	assert((nested_static_if.if_flags & .IS_STATIC) != 0);
	assert(nested_static_if.else_block.statements[0].kind == .DECLARATION);

	static_file := Extended.parse_file(#string JAI
#if true {
	first :: 1;
} else
	second :: 2;
after :: 3;
JAI);
	assert(static_file.status == .COMPLETE);
	file_if := static_file.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_If);
	assert((file_if.if_flags & .IS_STATIC) != 0);
	assert(file_if.then_block.block_type == .DATA_DECLARATIONS);
	assert(file_if.else_block.statements[0].kind == .DECLARATION);
	assert(static_file.root.(*Extended.Parser_Block).statements.count == 2);

	static_member := Extended.parse_declaration(#string JAI
Conditional :: struct {
	#if true {
		enabled: s64;
	} else
		disabled: s64;
}
JAI);
	assert(static_member.status == .COMPLETE);
	member_if := static_member.root.(*Extended.Parser_Declaration).expression.(*Extended.Parser_Struct).block.statements[0].(*Extended.Parser_If);
	assert((member_if.if_flags & .IS_STATIC) != 0);
	assert(member_if.then_block.block_type == .DATA_DECLARATIONS);

	ENUM_SOURCE :: #string JAI
Spells :: enum {
	BASE;
	#if true {
		BLORPLE;
		#if false {
			HIDDEN;
		} else
			VISIBLE;
	} else
		FALLBACK;
	AFTER;
}
JAI;
	static_enum := Extended.parse_declaration(ENUM_SOURCE);
	assert(static_enum.status == .COMPLETE);
	enum_statements := static_enum.root.(*Extended.Parser_Declaration).expression.(*Extended.Parser_Enum).block.statements;
	assert(enum_statements.count == 3);
	enum_if := enum_statements[1].(*Extended.Parser_If);
	assert((enum_if.if_flags & .IS_STATIC) != 0);
	assert(enum_if.then_block.block_type == .DATA_DECLARATIONS);
	assert(enum_if.then_block.statements[0].(*Extended.Parser_Ident).name == "BLORPLE");
	assert(enum_if.then_block.statements[1].(*Extended.Parser_If).else_block.statements[0].(*Extended.Parser_Ident).name == "VISIBLE");
	assert(enum_if.else_block.statements[0].(*Extended.Parser_Ident).name == "FALLBACK");
	assert(enum_statements[2].(*Extended.Parser_Ident).name == "AFTER");
	assert(Extended.reconstruct_source(*static_enum) == ENUM_SOURCE);
	assert(Extended.parse_declaration("Broken :: enum { #if true { NAME; ").status == .INCOMPLETE);

	static_empty_default := Extended.parse_block(#string JAI
{
	#if OS == {
		case .WINDOWS;
			return;
		case;
	}
}
JAI);
	assert(static_empty_default.status == .COMPLETE);
	assert(static_empty_default.synthetic_tokens.count == 0);
	static_cases := static_empty_default.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_If).then_block.statements;
	assert(static_cases.count == 2);
	assert(static_cases[1].(*Extended.Parser_Case).then_block.statements.count == 0);
}

test_preserved_directive_forms :: () {
	PLACEHOLDER_SOURCE :: "#placeholder Apple;\nafter :: 1;";
	placeholder := Extended.parse_file(PLACEHOLDER_SOURCE);
	assert(placeholder.status == .COMPLETE);
	placeholder_node := placeholder.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Placeholder);
	assert(placeholder_node.name == "Apple");
	assert(Extended.reconstruct_source(*placeholder) == PLACEHOLDER_SOURCE);

	as_fields := Extended.parse_declaration("Container :: struct { #as using base: Base; }");
	assert(as_fields.status == .COMPLETE);
	as_members := as_fields.root.(*Extended.Parser_Declaration).expression.(*Extended.Parser_Struct).block.statements;
	assert(as_members.count == 1);
	for as_members {
		using_node := it.(*Extended.Parser_Using);
		assert((using_node.expression.(*Extended.Parser_Declaration).flags & .IS_MARKED_AS_AS) != 0);
	}

	using_declarations := Extended.parse_file(#string JAI
using Global: State;
Container :: struct {
	using local: State;
	using #as base: Base;
}
JAI);
	assert(using_declarations.status == .COMPLETE);
	file_statements := using_declarations.root.(*Extended.Parser_Block).statements;
	assert(file_statements[0].(*Extended.Parser_Using).expression.(*Extended.Parser_Declaration).name == "Global");
	container_members := file_statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Struct).block.statements;
	assert(container_members.count == 2);
	assert(container_members[0].(*Extended.Parser_Using).expression.(*Extended.Parser_Declaration).name == "local");
	suffix_as := container_members[1].(*Extended.Parser_Using).expression.(*Extended.Parser_Declaration);
	assert(suffix_as.name == "base");
	assert((suffix_as.flags & .IS_MARKED_AS_AS) != 0);

	USING_ENUM_SOURCE :: #string JAI
{
	using enum u16 {
		CHOCOLATE :: 0;
		VANILLA;
	}
	after();
}
JAI;
	using_enum := Extended.parse_block(USING_ENUM_SOURCE);
	assert(using_enum.status == .COMPLETE);
	using_enum_statements := using_enum.root.(*Extended.Parser_Block).statements;
	assert(using_enum_statements.count == 2);
	assert(using_enum_statements[0].(*Extended.Parser_Using).expression.kind == .ENUM);
	assert(using_enum_statements[0].(*Extended.Parser_Using).expression.(*Extended.Parser_Enum).block.statements.count == 2);
	assert(using_enum_statements[1].kind == .PROCEDURE_CALL);
	assert(Extended.reconstruct_source(*using_enum) == USING_ENUM_SOURCE);
	assert(Extended.parse_block("{ using enum u16 { VANILLA; }; after(); }").status == .COMPLETE);
	ordinary_using := Extended.parse_block("{ using state after(); }");
	assert(ordinary_using.status == .RECOVERED);
	assert(ordinary_using.diagnostics[0].expected_token == #char ";");

	ASM_SOURCE :: #string JAI
{
	#asm AVX, AVX2 {
		mov apple:, 10;
		nested {
			ignored;
		};
	}
	after();
}
JAI;
	assembly := Extended.parse_block(ASM_SOURCE);
	assert(assembly.status == .COMPLETE);
	assembly_block := assembly.root.(*Extended.Parser_Block);
	assert(assembly_block.statements.count == 2);
	asm_node := assembly_block.statements[0].(*Extended.Parser_Asm);
	assert(asm_node.features.count == 2);
	assert(asm_node.features[0].name.name == "AVX");
	assert(asm_node.features[1].name.name == "AVX2");
	assert(Extended.token_at(*assembly, asm_node.features[0].span.first).original_text == "AVX");
	assert(Extended.token_at(*assembly, asm_node.features[1].span.first).original_text == "AVX2");
	assert(asm_node.features[0].span.one_past_last == asm_node.features[0].span.first + 1);
	assert(asm_node.features[1].span.one_past_last == asm_node.features[1].span.first + 1);
	assert(asm_node.features[0].name.first_token == asm_node.features[0].span.first);
	assert(asm_node.features[0].name.one_past_last_token == asm_node.features[0].span.one_past_last);
	assert(asm_node.statements.count == 2);
	assert(asm_node.statements[0].kind == .INSTRUCTION);
	assert(asm_node.statements[0].instruction.mnemonic.name == "mov");
	assert(asm_node.statements[0].instruction.size == null);
	assert(asm_node.statements[0].instruction.operands.count == 2);
	assert(asm_node.statements[0].instruction.operands[0].kind == .REGISTER_DECLARATION);
	assert(asm_node.statements[0].instruction.operands[0].register_declaration.is_inferred);
	assert(asm_node.statements[0].instruction.operands[0].register_declaration.name.name == "apple");
	assert(Extended.token_at(*assembly, asm_node.statements[0].instruction.operands[0].span.first).original_text == "apple");
	assert(Extended.token_at(*assembly, asm_node.statements[0].instruction.operands[1].span.first).original_text == "10");
	assert(Extended.token_at(*assembly, asm_node.statements[0].span.first).original_text == "mov");
	assert(Extended.token_at(*assembly, asm_node.statements[1].span.first).original_text == "nested");
	assert(asm_node.body_span.one_past_last > asm_node.body_span.first);
	assert(Extended.reconstruct_source(*assembly) == ASM_SOURCE);

	REGISTER_SOURCE :: #string JAI
{
	#asm {
		apple:;
		banana: gpr;
		mov cherry:, 10;
		mov w: gpr === 15, 10;
		t: gpr === a;
		v: vec === 9;
		x === a;
		mov y === a, z: gpr === 9;
	}
}
JAI;
	registers := Extended.parse_block(REGISTER_SOURCE);
	assert(registers.status == .COMPLETE);
	register_statements := registers.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Asm).statements;
	assert(register_statements.count == 8);
	assert(register_statements[0].kind == .REGISTER_DECLARATION);
	inferred_register := register_statements[0].register_declaration;
	assert(inferred_register.is_inferred && inferred_register.register_class == null);
	assert(inferred_register.name.name == "apple");
	assert(inferred_register.span.one_past_last == inferred_register.span.first + 2);
	assert(register_statements[1].kind == .REGISTER_DECLARATION);
	explicit_register := register_statements[1].register_declaration;
	assert(!explicit_register.is_inferred && explicit_register.register_class.name == "gpr");
	assert(explicit_register.span.one_past_last == explicit_register.span.first + 3);
	assert(register_statements[2].instruction.operands[0].register_declaration.is_inferred);
	pinned_operand := register_statements[3].instruction.operands[0];
	assert(pinned_operand.kind == .REGISTER_DECLARATION);
	assert(pinned_operand.register_declaration.name.name == "w");
	assert(pinned_operand.register_declaration.register_class.name == "gpr");
	assert(pinned_operand.register_declaration.pinning != null);
	assert(Extended.token_at(*registers, pinned_operand.register_declaration.pinning.target.span.first).original_text == "15");
	assert(pinned_operand.register_declaration.pinning.span.one_past_last == pinned_operand.span.one_past_last);
	assert(pinned_operand.span.one_past_last > pinned_operand.register_declaration.span.one_past_last);
	assert(register_statements[3].instruction.operands[1].kind == .VALUE);
	assert(register_statements[3].instruction.operands[1].value.expression.(*Extended.Parser_Literal)._u64 == 10);
	assert(register_statements[4].kind == .REGISTER_DECLARATION);
	t_pinning := register_statements[4].register_declaration.pinning;
	assert(t_pinning != null);
	assert(Extended.token_at(*registers, t_pinning.source.span.first).original_text == "t");
	assert(t_pinning.source.span.one_past_last == t_pinning.source.span.first + 1);
	assert(t_pinning.source.expression.(*Extended.Parser_Ident).name == "t");
	assert(Extended.token_at(*registers, t_pinning.target.span.first).original_text == "a");
	assert(t_pinning.target.span.one_past_last == t_pinning.target.span.first + 1);
	assert(t_pinning.target.expression.(*Extended.Parser_Ident).name == "a");
	assert(t_pinning.span.first == register_statements[4].register_declaration.span.first);
	assert(t_pinning.span.one_past_last == register_statements[4].span.one_past_last - 1);
	assert(register_statements[5].register_declaration.register_class.name == "vec");
	assert(Extended.token_at(*registers, register_statements[5].register_declaration.pinning.target.span.first).original_text == "9");
	assert(register_statements[5].register_declaration.pinning.target.expression.(*Extended.Parser_Literal)._u64 == 9);
	assert(register_statements[6].kind == .REGISTER_PINNING);
	x_pinning := register_statements[6].register_pinning;
	assert(Extended.token_at(*registers, x_pinning.source.span.first).original_text == "x");
	assert(Extended.token_at(*registers, x_pinning.target.span.first).original_text == "a");
	assert(x_pinning.span.one_past_last == register_statements[6].span.one_past_last - 1);
	assert(register_statements[7].kind == .INSTRUCTION);
	assert(register_statements[7].instruction.operands[0].kind == .REGISTER_PINNING);
	assert(Extended.token_at(*registers, register_statements[7].instruction.operands[0].register_pinning.target.span.first).original_text == "a");
	assert(register_statements[7].instruction.operands[1].kind == .REGISTER_DECLARATION);
	assert(Extended.token_at(*registers, register_statements[7].instruction.operands[1].register_declaration.pinning.target.span.first).original_text == "9");
	assert(Extended.reconstruct_source(*registers) == REGISTER_SOURCE);

	ASM_NUMERIC_SOURCE :: #string JAI
{
	#asm {
		mov dst, -10;
		mov dst, +0x2A;
		mov dst, -10.5;
		mov dst, +1.25;
		mov dst, 4294967296;
		mov dst, [base - 10];
	}
}
JAI;
	asm_numeric := Extended.parse_block(ASM_NUMERIC_SOURCE);
	assert(asm_numeric.status == .COMPLETE);
	asm_numeric_statements := asm_numeric.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Asm).statements;
	assert(asm_numeric_statements.count == 6);
	negative_integer := asm_numeric_statements[0].instruction.operands[1];
	assert(negative_integer.kind == .VALUE);
	assert(negative_integer.value.span.first == negative_integer.span.first);
	assert(negative_integer.value.span.one_past_last == negative_integer.span.one_past_last);
	assert(negative_integer.value.expression.kind == .LITERAL);
	assert((negative_integer.value.expression.(*Extended.Parser_Literal).value_flags & .MINUS_SIGN) != 0);
	assert(negative_integer.value.expression.first_token == negative_integer.span.first);
	assert(Extended.token_at(*asm_numeric, negative_integer.span.first).original_text == "-");
	positive_integer := asm_numeric_statements[1].instruction.operands[1];
	assert(positive_integer.kind == .VALUE);
	assert(positive_integer.value.expression.kind == .UNARY_OPERATOR);
	assert(positive_integer.value.expression.(*Extended.Parser_Unary_Operator).subexpression.(*Extended.Parser_Literal)._u64 == 42);
	negative_float := asm_numeric_statements[2].instruction.operands[1];
	assert(negative_float.kind == .VALUE);
	assert(negative_float.value.expression.(*Extended.Parser_Literal)._float64 == -10.5);
	positive_float := asm_numeric_statements[3].instruction.operands[1];
	assert(positive_float.kind == .VALUE);
	assert(positive_float.value.expression.(*Extended.Parser_Unary_Operator).subexpression.(*Extended.Parser_Literal)._float64 == 1.25);
	assert(asm_numeric_statements[4].instruction.operands[1].kind == .VALUE);
	assert(asm_numeric_statements[4].instruction.operands[1].value.expression.(*Extended.Parser_Literal)._u64 == 4294967296);
	assert(asm_numeric_statements[5].instruction.operands[1].kind == .MEMORY);
	assert(asm_numeric_statements[5].instruction.operands[1].memory.base.expression.(*Extended.Parser_Ident).name == "base");
	assert((asm_numeric_statements[5].instruction.operands[1].memory.displacement.expression.(*Extended.Parser_Literal).value_flags & .MINUS_SIGN) != 0);
	assert(Extended.reconstruct_source(*asm_numeric) == ASM_NUMERIC_SOURCE);

	ASM_MEMORY_SOURCE :: #string JAI
{
	#asm {
		mov dst, [b];
		mov dst, [base + index];
		mov dst, [base + index*8 - 10];
		mov dst, [base + vector_index*4 + (OFFSET * 2)];
		mov dst, [base + (OFFSET + 1)];
		mov dst, [base - (-10.5)];
		mov dst, [base + index*(SCALE + 1)];
		mov dst, [];
		mov dst, [base +];
		mov dst, [base + index*];
	}
}
JAI;
	asm_memory := Extended.parse_block(ASM_MEMORY_SOURCE);
	assert(asm_memory.status == .RECOVERED);
	assert(asm_memory.diagnostics.count == 3);
	memory_statements := asm_memory.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Asm).statements;
	assert(memory_statements.count == 10);
	bare_memory := memory_statements[0].instruction.operands[1];
	assert(bare_memory.kind == .MEMORY);
	assert(bare_memory.memory.span.first == bare_memory.span.first);
	assert(bare_memory.memory.span.one_past_last == bare_memory.span.one_past_last);
	assert(bare_memory.memory.base.expression.(*Extended.Parser_Ident).name == "b");
	assert(bare_memory.memory.index.expression == null && bare_memory.memory.scale.expression == null && bare_memory.memory.displacement.expression == null);
	assert(memory_statements[1].instruction.operands[1].memory.index.expression.(*Extended.Parser_Ident).name == "index");
	indexed_memory := memory_statements[2].instruction.operands[1].memory;
	assert(indexed_memory.index.expression.(*Extended.Parser_Ident).name == "index");
	assert(indexed_memory.scale.expression.(*Extended.Parser_Literal)._u64 == 8);
	assert(indexed_memory.displacement.expression.kind == .LITERAL);
	assert((indexed_memory.displacement.expression.(*Extended.Parser_Literal).value_flags & .MINUS_SIGN) != 0);
	assert(Extended.token_at(*asm_memory, indexed_memory.displacement.span.first).original_text == "-");
	assert(indexed_memory.scale.span.one_past_last == indexed_memory.displacement.span.first);
	vector_memory := memory_statements[3].instruction.operands[1].memory;
	assert(vector_memory.index.expression.(*Extended.Parser_Ident).name == "vector_index");
	assert(vector_memory.scale.expression.(*Extended.Parser_Literal)._u64 == 4);
	assert(vector_memory.displacement.expression.kind == .UNARY_OPERATOR);
	assert(vector_memory.displacement.expression.(*Extended.Parser_Unary_Operator).subexpression.kind == .BINARY_OPERATOR);
	assert(Extended.token_at(*asm_memory, vector_memory.displacement.span.first).original_text == "+");
	assert(memory_statements[4].instruction.operands[1].memory.displacement.expression.kind == .UNARY_OPERATOR);
	assert(memory_statements[5].instruction.operands[1].memory.displacement.expression.kind == .UNARY_OPERATOR);
	assert(memory_statements[6].instruction.operands[1].memory.scale.expression.kind == .BINARY_OPERATOR);
	for 7..9 {
		assert(memory_statements[it].instruction.operands[1].kind == .UNPARSED);
	}

	assert(Extended.reconstruct_source(*asm_memory) == ASM_MEMORY_SOURCE);

	// Tutorial addresses exercise symbolic scales and high-level constant subexpressions.
	TUTORIAL_MEMORY_SOURCE :: #string JAI
{
	#asm {
		mov t, [dummy_array_pointer + dummy_array_index*DUMMY_SCALE + DUMMY_DISP];
		mov t, [dummy_array_pointer + dummy_array_index*(size_of(u64)) + (-10 * 2 + 13)];
	}
}
JAI;
	tutorial_memory := Extended.parse_block(TUTORIAL_MEMORY_SOURCE);
	assert(tutorial_memory.status == .COMPLETE);
	tutorial_address := tutorial_memory.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Asm).statements[0].instruction.operands[1];
	assert(tutorial_address.kind == .MEMORY);
	assert(tutorial_address.memory.scale.expression.(*Extended.Parser_Ident).name == "DUMMY_SCALE");
	assert(tutorial_address.memory.displacement.expression.(*Extended.Parser_Unary_Operator).subexpression.(*Extended.Parser_Ident).name == "DUMMY_DISP");
	inline_address := tutorial_memory.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Asm).statements[1].instruction.operands[1];
	assert(inline_address.kind == .MEMORY);
	assert(inline_address.memory.scale.expression.(*Extended.Parser_Type_Query).query_kind == .SIZE_OF);
	assert(inline_address.memory.displacement.expression.(*Extended.Parser_Unary_Operator).subexpression.kind == .BINARY_OPERATOR);
	assert(Extended.reconstruct_source(*tutorial_memory) == TUTORIAL_MEMORY_SOURCE);

	ASM_MODIFIER_SOURCE :: #string JAI
{
	#asm {
		vload dst, [base]!;
		vop a!, b!n, c!d, d!u, e!z;
		vadd dst & mask, src &* mask;
		vop [base + vector_index*4 - 10]!z &* mask, -10!, bad!x, bad &*;
		vop [base + (OFFSET & FLAG)]!z;
	}
}
JAI;
	asm_modifiers := Extended.parse_block(ASM_MODIFIER_SOURCE);
	assert(asm_modifiers.status == .RECOVERED);
	assert(asm_modifiers.diagnostics.count == 2);
	modifier_statements := asm_modifiers.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Asm).statements;
	assert(modifier_statements.count == 5);
	broadcast := modifier_statements[0].instruction.operands[1];
	assert(broadcast.kind == .MEMORY && broadcast.modifiers.count == 1);
	assert(broadcast.modifiers[0].kind == .BANG);
	assert(broadcast.memory.span.one_past_last == broadcast.modifiers[0].span.first);
	assert(broadcast.modifiers[0].span.one_past_last == broadcast.span.one_past_last);
	rounding_operands := modifier_statements[1].instruction.operands;
	assert(rounding_operands.count == 5);
	assert(rounding_operands[0].modifiers[0].kind == .BANG);
	assert(rounding_operands[1].modifiers[0].kind == .BANG_N);
	assert(rounding_operands[2].modifiers[0].kind == .BANG_D);
	assert(rounding_operands[3].modifiers[0].kind == .BANG_U);
	assert(rounding_operands[4].modifiers[0].kind == .BANG_Z);
	assert(rounding_operands[4].modifiers[0].span.one_past_last == rounding_operands[4].span.one_past_last);
	mask_operands := modifier_statements[2].instruction.operands;
	assert(mask_operands[0].modifiers[0].kind == .AMPERSAND);
	assert(mask_operands[1].modifiers[0].kind == .AMPERSAND_STAR);
	assert(mask_operands[0].modifiers[0].argument.expression.(*Extended.Parser_Ident).name == "mask");
	assert(mask_operands[1].modifiers[0].argument.expression.(*Extended.Parser_Ident).name == "mask");
	assert(Extended.token_at(*asm_modifiers, mask_operands[1].modifiers[0].span.first).original_text == "&");
	assert(mask_operands[1].modifiers[0].argument.span.one_past_last == mask_operands[1].span.one_past_last);
	combined := modifier_statements[3].instruction.operands;
	assert(combined.count == 4);
	assert(combined[0].kind == .MEMORY && combined[0].modifiers.count == 2);
	assert(combined[0].memory.index.expression.(*Extended.Parser_Ident).name == "vector_index");
	assert(combined[0].modifiers[0].kind == .BANG_Z);
	assert(combined[0].modifiers[1].kind == .AMPERSAND_STAR);
	assert(combined[0].modifiers[0].span.one_past_last == combined[0].modifiers[1].span.first);
	assert(combined[0].modifiers[1].span.one_past_last == combined[0].span.one_past_last);
	assert(combined[1].kind == .VALUE && combined[1].modifiers[0].kind == .BANG);
	assert(combined[1].value.span.one_past_last == combined[1].modifiers[0].span.first);
	assert(combined[2].kind == .UNPARSED && combined[2].modifiers.count == 0);
	assert(combined[3].kind == .UNPARSED && combined[3].modifiers.count == 0);
	nested_ampersand := modifier_statements[4].instruction.operands[0];
	assert(nested_ampersand.kind == .MEMORY);
	assert(nested_ampersand.memory.displacement.expression.kind == .UNARY_OPERATOR);
	assert(nested_ampersand.memory.displacement.expression.(*Extended.Parser_Unary_Operator).subexpression.kind == .BINARY_OPERATOR);
	assert(nested_ampersand.modifiers.count == 1 && nested_ampersand.modifiers[0].kind == .BANG_Z);
	assert(Extended.reconstruct_source(*asm_modifiers) == ASM_MODIFIER_SOURCE);

	ASM_VALUE_SOURCE :: #string JAI
{
	#asm {
		mov dst, source_value;
		mov dst, MY_CONSTANT;
		mov dst, s64;
		mov dst, register_param;
		mov dst, (MY_CONSTANT + 1);
		mov dst, (register_param);
		mov dst, (MY_CONSTANT * (2 + 3)) &* mask;
		mov dst, [base + (MY_CONSTANT * 2)];
		mov dst, some_call(1);
	}
}
JAI;
	asm_values := Extended.parse_block(ASM_VALUE_SOURCE);
	assert(asm_values.status == .COMPLETE);
	value_statements := asm_values.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Asm).statements;
	assert(value_statements.count == 9);
	for 0..3 {
		operand := value_statements[it].instruction.operands[1];
		assert(operand.kind == .VALUE);
		assert(operand.value.expression.kind == .IDENT);
		assert(operand.value.span.first == operand.span.first);
		assert(operand.value.span.one_past_last == operand.span.one_past_last);
	}

	assert(value_statements[0].instruction.operands[1].value.expression.(*Extended.Parser_Ident).name == "source_value");
	assert(value_statements[1].instruction.operands[1].value.expression.(*Extended.Parser_Ident).name == "MY_CONSTANT");
	assert(value_statements[2].instruction.operands[1].value.expression.(*Extended.Parser_Ident).name == "s64");
	assert(value_statements[3].instruction.operands[1].value.expression.(*Extended.Parser_Ident).name == "register_param");
	assert(value_statements[4].instruction.operands[1].kind == .VALUE);
	assert(value_statements[4].instruction.operands[1].value.expression.kind == .BINARY_OPERATOR);
	assert(value_statements[4].instruction.operands[1].value.span.one_past_last == value_statements[4].instruction.operands[1].span.one_past_last);
	assert(value_statements[5].instruction.operands[1].value.expression.kind == .IDENT);
	assert((value_statements[5].instruction.operands[1].value.expression.node_flags & .IS_PARENTHESIZED) != 0);
	masked_expression := value_statements[6].instruction.operands[1];
	assert(masked_expression.kind == .VALUE && masked_expression.modifiers.count == 1);
	assert(masked_expression.value.expression.kind == .BINARY_OPERATOR);
	assert(masked_expression.modifiers[0].kind == .AMPERSAND_STAR);
	assert(masked_expression.value.span.one_past_last == masked_expression.modifiers[0].span.first);
	assert(value_statements[7].instruction.operands[1].kind == .MEMORY);
	assert(value_statements[7].instruction.operands[1].memory.displacement.expression.kind == .UNARY_OPERATOR);
	assert(value_statements[8].instruction.operands[1].kind == .UNPARSED);
	assert(Extended.reconstruct_source(*asm_values) == ASM_VALUE_SOURCE);

	ASM_MACRO_SOURCE :: #string JAI
fixture_macro :: (register_param: __reg, type_param: Type) #expand {
	#asm {
		mov register_param, (type_param);
	}
}
JAI;
	asm_macro := Extended.parse_file(ASM_MACRO_SOURCE);
	assert(asm_macro.status == .COMPLETE);
	macro_header := asm_macro.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header);
	assert(macro_header.arguments[0].type_inst.type_valued_expression.(*Extended.Parser_Ident).name == "__reg");
	macro_body := macro_header.body_or_null.block;
	macro_instruction := macro_body.statements[0].(*Extended.Parser_Asm).statements[0].instruction;
	assert(macro_instruction.operands[0].kind == .VALUE);
	assert(macro_instruction.operands[0].value.expression.(*Extended.Parser_Ident).name == "register_param");
	assert(macro_instruction.operands[1].value.expression.(*Extended.Parser_Ident).name == "type_param");
	assert(Extended.reconstruct_source(*asm_macro) == ASM_MACRO_SOURCE);

	bare_asm := Extended.parse_block("{ #asm {} }");
	assert(bare_asm.status == .COMPLETE);
	bare_asm_node := bare_asm.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Asm);
	assert(bare_asm_node.features.count == 0);
	assert(bare_asm_node.statements.count == 0);
	assert(bare_asm_node.body_span.first == bare_asm_node.body_span.one_past_last);

	shared_scope := Extended.parse_block(#string JAI
{
	#asm {
		first: gpr;
	}
	#asm {
		mov first, 1;
	}
	{
		#asm {
			nested: gpr;
		}
	}
}
JAI);
	assert(shared_scope.status == .COMPLETE);
	shared_scope_block := shared_scope.root.(*Extended.Parser_Block);
	first_asm := shared_scope_block.statements[0].(*Extended.Parser_Asm);
	second_asm := shared_scope_block.statements[1].(*Extended.Parser_Asm);
	nested_block := shared_scope_block.statements[2].(*Extended.Parser_Block);
	nested_asm := nested_block.statements[0].(*Extended.Parser_Asm);
	assert(first_asm.enclosing_scope == shared_scope_block);
	assert(second_asm.enclosing_scope == shared_scope_block);
	assert(first_asm.enclosing_scope == second_asm.enclosing_scope);
	assert(first_asm.statements.count == 1);
	assert(first_asm.statements[0].kind == .REGISTER_DECLARATION);
	assert(first_asm.statements[0].register_declaration.name.name == "first");
	assert(first_asm.statements[0].register_declaration.register_class.name == "gpr");
	assert(second_asm.statements.count == 1);
	assert(Extended.token_at(*shared_scope, first_asm.statements[0].span.first).original_text == "first");
	assert(Extended.token_at(*shared_scope, second_asm.statements[0].span.first).original_text == "mov");
	assert(nested_asm.enclosing_scope == nested_block);
	assert(nested_asm.enclosing_scope != first_asm.enclosing_scope);

	conditional_asm := Extended.parse_block(#string JAI
{
	#if BITS == 8 #asm {
		mov.8 result:, value;
	} else #asm {
		mov.64 result:, value;
	}
}
JAI);
	assert(conditional_asm.status == .COMPLETE);
	conditional_scope := conditional_asm.root.(*Extended.Parser_Block);
	conditional := conditional_scope.statements[0].(*Extended.Parser_If);
	assert((conditional.if_flags & .IS_STATIC) != 0);
	assert(conditional.then_block.statements.count == 1);
	assert(conditional.else_block.statements.count == 1);
	then_asm := conditional.then_block.statements[0].(*Extended.Parser_Asm);
	else_asm := conditional.else_block.statements[0].(*Extended.Parser_Asm);
	assert(then_asm.enclosing_scope == conditional_scope);
	assert(else_asm.enclosing_scope == conditional_scope);
	assert(Extended.token_at(*conditional_asm, then_asm.statements[0].span.first).original_text == "mov");
	assert(Extended.token_at(*conditional_asm, else_asm.statements[0].span.first).original_text == "mov");
	assert(then_asm.statements[0].instruction.size.kind == .FIXED);
	assert(Extended.token_at(*conditional_asm, then_asm.statements[0].instruction.size.span.first).original_text == ".8");
	assert(else_asm.statements[0].instruction.size.kind == .FIXED);
	assert(Extended.token_at(*conditional_asm, else_asm.statements[0].instruction.size.span.first).original_text == ".64");

	polymorphic_asm := Extended.parse_block(#string JAI
{
	#asm {
		popcnt?BITS result, value;
		popcnt?T other, value;
	}
}
JAI);
	assert(polymorphic_asm.status == .COMPLETE);
	polymorphic_statements := polymorphic_asm.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Asm).statements;
	assert(polymorphic_statements.count == 2);
	assert(polymorphic_statements[0].instruction.size.kind == .POLYMORPHIC);
	assert(polymorphic_statements[0].instruction.size.polymorphic_name.name == "BITS");
	assert(polymorphic_statements[1].instruction.size.polymorphic_name.name == "T");
	assert(polymorphic_statements[0].instruction.operands.count == 2);
	assert(polymorphic_statements[1].instruction.operands.count == 2);

	missing_asm_semicolon := Extended.parse_block(#string JAI
{
	#asm {
		mov result:, value
	}
	after();
}
JAI);
	assert(missing_asm_semicolon.status == .RECOVERED);
	assert(missing_asm_semicolon.diagnostics.count == 1);
	assert(missing_asm_semicolon.diagnostics[0].kind == .EXPECTED_TOKEN);
	assert(missing_asm_semicolon.diagnostics[0].expected_token == #char ";");
	assert(missing_asm_semicolon.root.(*Extended.Parser_Block).statements.count == 2);
	missing_semicolon_asm := missing_asm_semicolon.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Asm);
	assert(missing_semicolon_asm.statements[0].kind == .INSTRUCTION);
	assert(missing_semicolon_asm.statements[0].instruction.operands.count == 2);

	truncated_asm := Extended.parse_block(
		#string JAINot
{
	#asm {
		mov value:, 1;
JAINot
	);
	assert(truncated_asm.status == .INCOMPLETE);
	truncated_asm_node := truncated_asm.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Asm);
	assert(truncated_asm_node.statements.count == 1);
	assert(truncated_asm_node.statements[0].span.one_past_last == truncated_asm_node.body_span.one_past_last);
}

test_assembly_recovery :: () {
	SOURCE :: #string JAI
{
	#asm {
		mov destination source;
		add destination, 1;
	}
	after();
}
JAI;
	parsed := Extended.parse_block(SOURCE);
	assert(parsed.status == .RECOVERED);
	assert(parsed.diagnostics.count == 1);
	assert(parsed.diagnostics[0].expected_token == #char ",");
	assert(Extended.token_at(*parsed, parsed.diagnostics[0].span.first).original_text == "source");
	assert(parsed.synthetic_tokens.count == 1 && parsed.synthetic_tokens[0].token.type == #char ",");
	block := parsed.root.(*Extended.Parser_Block);
	assert(block.statements.count == 2);
	asm_block := block.statements[0].(*Extended.Parser_Asm);
	assert(asm_block.statements.count == 2);
	assert(asm_block.statements[0].instruction.operands.count == 2);
	assert(asm_block.statements[0].instruction.operands[1].value.expression.(*Extended.Parser_Ident).name == "source");
	assert(asm_block.statements[1].instruction.mnemonic.name == "add");
	assert(block.statements[1].kind == .PROCEDURE_CALL);
	assert(Extended.reconstruct_source(*parsed) == SOURCE);

	NUMERIC_SOURCE :: #string JAI
{
	#asm {
		mov destination 10;
		add destination, 1;
	}
	after();
}
JAI;
	numeric := Extended.parse_block(NUMERIC_SOURCE);
	assert(numeric.status == .RECOVERED);
	assert(numeric.diagnostics.count == 1 && numeric.diagnostics[0].expected_token == #char ",");
	numeric_block := numeric.root.(*Extended.Parser_Block);
	assert(numeric_block.statements.count == 2);
	numeric_asm := numeric_block.statements[0].(*Extended.Parser_Asm);
	assert(numeric_asm.statements.count == 2);
	assert(numeric_asm.statements[0].instruction.operands.count == 2);
	assert(numeric_asm.statements[1].instruction.mnemonic.name == "add");
	assert(numeric_block.statements[1].kind == .PROCEDURE_CALL);
	assert(Extended.reconstruct_source(*numeric) == NUMERIC_SOURCE);

	BAD_MEMORY_SOURCE :: #string JAI
{
	#asm {
		mov dst, [base +];
		add dst, 1;
	}
	after();
}
JAI;
	bad_memory := Extended.parse_block(BAD_MEMORY_SOURCE);
	assert(bad_memory.status == .RECOVERED);
	assert(bad_memory.diagnostics.count == 1);
	assert(bad_memory.diagnostics[0].message == "Malformed assembly memory operand.");
	assert(Extended.token_at(*bad_memory, bad_memory.diagnostics[0].span.first).original_text == "[");
	bad_memory_block := bad_memory.root.(*Extended.Parser_Block);
	assert(bad_memory_block.statements.count == 2);
	bad_memory_asm := bad_memory_block.statements[0].(*Extended.Parser_Asm);
	assert(bad_memory_asm.statements.count == 2);
	assert(bad_memory_asm.statements[0].instruction.operands[1].kind == .UNPARSED);
	assert(bad_memory_asm.statements[1].instruction.mnemonic.name == "add");
	assert(bad_memory_block.statements[1].kind == .PROCEDURE_CALL);
	assert(Extended.reconstruct_source(*bad_memory) == BAD_MEMORY_SOURCE);

	UNCLOSED_MEMORY_SOURCE :: #string JAI
{
	#asm {
		mov dst, [base +;
		add dst, 1;
	}
	after();
}
JAI;
	unclosed_memory := Extended.parse_block(UNCLOSED_MEMORY_SOURCE);
	assert(unclosed_memory.status == .RECOVERED && unclosed_memory.diagnostics.count == 1);
	unclosed_block := unclosed_memory.root.(*Extended.Parser_Block);
	assert(unclosed_block.statements.count == 2);
	unclosed_asm := unclosed_block.statements[0].(*Extended.Parser_Asm);
	assert(unclosed_asm.statements.count == 2);
	assert(unclosed_asm.statements[0].instruction.operands[1].kind == .UNPARSED);
	assert(unclosed_asm.statements[1].instruction.mnemonic.name == "add");
	assert(unclosed_block.statements[1].kind == .PROCEDURE_CALL);
	assert(Extended.reconstruct_source(*unclosed_memory) == UNCLOSED_MEMORY_SOURCE);

	BAD_MODIFIER_SOURCE :: #string JAI
{
	#asm {
		vop bad!x, bad &*;
		add dst, 1;
	}
	after();
}
JAI;
	bad_modifier := Extended.parse_block(BAD_MODIFIER_SOURCE);
	assert(bad_modifier.status == .RECOVERED);
	assert(bad_modifier.diagnostics.count == 2);
	assert(Extended.token_at(*bad_modifier, bad_modifier.diagnostics[0].span.first).original_text == "!");
	assert(Extended.token_at(*bad_modifier, bad_modifier.diagnostics[1].span.first).original_text == "&");
	bad_modifier_block := bad_modifier.root.(*Extended.Parser_Block);
	assert(bad_modifier_block.statements.count == 2);
	bad_modifier_asm := bad_modifier_block.statements[0].(*Extended.Parser_Asm);
	assert(bad_modifier_asm.statements.count == 2);
	assert(bad_modifier_asm.statements[0].instruction.operands[0].kind == .UNPARSED);
	assert(bad_modifier_asm.statements[0].instruction.operands[1].kind == .UNPARSED);
	assert(bad_modifier_asm.statements[1].instruction.mnemonic.name == "add");
	assert(bad_modifier_block.statements[1].kind == .PROCEDURE_CALL);
	assert(Extended.reconstruct_source(*bad_modifier) == BAD_MODIFIER_SOURCE);

	MISSING_SEMICOLON_SOURCE :: "{ #asm { mov dst, 1 } after(); }";
	missing_semicolon := Extended.parse_block(MISSING_SEMICOLON_SOURCE);
	assert(missing_semicolon.status == .RECOVERED && missing_semicolon.diagnostics.count == 1);
	assert(missing_semicolon.diagnostics[0].expected_token == #char ";");
	assert(missing_semicolon.diagnostics[0].actual_token == #char "}");
	assert(missing_semicolon.synthetic_tokens.count == 1 && missing_semicolon.synthetic_tokens[0].token.type == #char ";");
	missing_block := missing_semicolon.root.(*Extended.Parser_Block);
	assert(missing_block.statements.count == 2);
	missing_asm := missing_block.statements[0].(*Extended.Parser_Asm);
	assert(missing_asm.statements.count == 1);
	assert(missing_asm.statements[0].instruction.operands.count == 2);
	assert(missing_block.statements[1].kind == .PROCEDURE_CALL);
	assert(Extended.reconstruct_source(*missing_semicolon) == MISSING_SEMICOLON_SOURCE);

	TRUNCATED_SOURCE :: "{ #asm { mov dst, 1";
	truncated := Extended.parse_block(TRUNCATED_SOURCE);
	assert(truncated.status == .INCOMPLETE);
	assert(truncated.diagnostics.count >= 2);
	truncated_block := truncated.root.(*Extended.Parser_Block);
	assert(truncated_block.statements.count == 1);
	truncated_asm := truncated_block.statements[0].(*Extended.Parser_Asm);
	assert(truncated_asm.statements.count == 1);
	assert(truncated_asm.statements[0].instruction.operands.count == 2);
	assert(truncated_asm.statements[0].instruction.operands[1].kind == .VALUE);
	assert(truncated_asm.statements[0].span.one_past_last == truncated_asm.body_span.one_past_last);
	assert(Extended.reconstruct_source(*truncated) == TRUNCATED_SOURCE);
}

test_statement_recovery :: () {
	declarations := Extended.parse_declaration_block("{ first: s64; second := 2; }");
	assert(declarations.status == .COMPLETE);
	declaration_block := declarations.root.(*Extended.Parser_Block);
	assert(declaration_block.block_type == .DATA_DECLARATIONS);
	assert(declaration_block.statements.count == 2);

	nested := Extended.parse_block("{ { value := 1; } }");
	assert(nested.status == .COMPLETE);
	assert(nested.root.(*Extended.Parser_Block).statements[0].kind == .BLOCK);

	missing_semicolon := Extended.parse_block("{ first := 1 second := 2; }");
	assert(missing_semicolon.status == .RECOVERED);
	assert(missing_semicolon.root.(*Extended.Parser_Block).statements.count == 2);
	assert(missing_semicolon.synthetic_tokens.count == 1);
	assert(missing_semicolon.synthetic_tokens[0].token.type == #char ";");

	bad_expression := Extended.parse_block("{ value + ; next := 2; }");
	assert(bad_expression.status == .RECOVERED);
	assert(bad_expression.root.(*Extended.Parser_Block).statements.count == 2);
	assert(bad_expression.root.(*Extended.Parser_Block).statements[1].(*Extended.Parser_Declaration).name == "next");

	nested_recovery := Extended.parse_file(
		#string JAI
outer :: () {
	#unknown {
		leaked := 1;
	}
	after := 2;
}
final :: 3;
JAI
	);
	assert(nested_recovery.status == .RECOVERED);
	nested_root := nested_recovery.root.(*Extended.Parser_Block);
	assert(nested_root.statements.count == 2);
	assert(nested_root.statements[0].(*Extended.Parser_Declaration).name == "outer");
	assert(nested_root.statements[1].(*Extended.Parser_Declaration).name == "final");
	outer_body := nested_root.statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block;
	assert(outer_body.statements.count == 1);
	assert(outer_body.statements[0].(*Extended.Parser_Declaration).name == "after");

	declaration_recovery := Extended.parse_file(
		#string JAI
broken :: () #unknown {
	leaked := 1;
}
after :: 2;
JAI
	);
	assert(declaration_recovery.status == .RECOVERED);
	declaration_root := declaration_recovery.root.(*Extended.Parser_Block);
	assert(declaration_root.statements.count == 2);
	assert(declaration_root.statements[0].(*Extended.Parser_Declaration).name == "broken");
	assert(declaration_root.statements[1].(*Extended.Parser_Declaration).name == "after");
}

test_section_13_recovery :: () {
	truncated_procedure := Extended.parse_file("broken :: () { value :=");
	assert(truncated_procedure.status == .INCOMPLETE);
	assert(truncated_procedure.diagnostics.count > 0);
	procedure_declaration := truncated_procedure.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Declaration);
	assert(procedure_declaration.name == "broken");
	procedure_body := procedure_declaration.expression.(*Extended.Parser_Procedure_Header).body_or_null.block;
	assert(procedure_body.statements.count == 1);

	truncated_pointer := Extended.parse_declaration("value: *");
	assert(truncated_pointer.status == .INCOMPLETE);
	assert(truncated_pointer.diagnostics.count > 0);
	assert(truncated_pointer.root.(*Extended.Parser_Declaration).name == "value");

	truncated_cast := Extended.parse_declaration("value := cast(*u8)");
	assert(truncated_cast.status == .INCOMPLETE);
	assert(truncated_cast.diagnostics.count > 0);
	assert(truncated_cast.root.(*Extended.Parser_Declaration).name == "value");

	truncated_parameters := Extended.parse_declaration("procedure :: (x: s64 = 1, y:");
	assert(truncated_parameters.status != .COMPLETE && truncated_parameters.status != .FATAL);
	assert(truncated_parameters.diagnostics.count > 0);
	parameter_header := truncated_parameters.root.(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header);
	assert(parameter_header.arguments.count >= 1);

	truncated_static_if := Extended.parse_block("{ #if true { enabled := 1;");
	assert(truncated_static_if.status == .INCOMPLETE);
	static_if := truncated_static_if.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_If);
	assert((static_if.if_flags & .IS_STATIC) != 0);
	assert(static_if.then_block.statements.count == 1);

	truncated_placeholder := Extended.parse_file("#placeholder");
	assert(truncated_placeholder.status == .INCOMPLETE);
	assert(truncated_placeholder.root.(*Extended.Parser_Block).statements[0].kind == .PLACEHOLDER);

	truncated_as_using := Extended.parse_declaration("#as using base:");
	assert(truncated_as_using.status == .INCOMPLETE);
	as_declaration := truncated_as_using.root.(*Extended.Parser_Using).expression.(*Extended.Parser_Declaration);
	assert(as_declaration.name == "base");
	assert((as_declaration.flags & .IS_MARKED_AS_AS) != 0);

	truncated_char := Extended.parse_expression("#char");
	assert(truncated_char.status == .INCOMPLETE);
	assert(truncated_char.root.kind == .LITERAL);
	malformed_this := Extended.parse_expression("#this extra");
	assert(malformed_this.status == .RECOVERED);
	assert(malformed_this.root.kind == .DIRECTIVE_THIS);
	malformed_filepath := Extended.parse_expression("#filepath extra", "fixture.jai");
	assert(malformed_filepath.status == .RECOVERED);
	assert(malformed_filepath.root.kind == .LITERAL);
	malformed_caller_code := Extended.parse_expression("#caller_code extra");
	assert(malformed_caller_code.status == .RECOVERED);
	assert(malformed_caller_code.root.kind == .DIRECTIVE_CODE);

	truncated_member_assignment := Extended.parse_declaration("Defaulted :: struct { w: s64; w =");
	assert(truncated_member_assignment.status == .INCOMPLETE);
	defaulted_block := truncated_member_assignment.root.(*Extended.Parser_Declaration).expression.(*Extended.Parser_Struct).block;
	assert(defaulted_block.statements.count >= 1);
	assert(defaulted_block.statements[0].(*Extended.Parser_Declaration).name == "w");

	truncated_operator := Extended.parse_declaration("operator + :: (left: s64,");
	assert(truncated_operator.status != .COMPLETE && truncated_operator.status != .FATAL);
	operator_declaration := truncated_operator.root.(*Extended.Parser_Declaration);
	assert(operator_declaration.name == "+");
	assert(truncated_operator.diagnostics.count > 0);

	truncated_using := Extended.parse_declaration("using local:");
	assert(truncated_using.status == .INCOMPLETE);
	using_declaration := truncated_using.root.(*Extended.Parser_Using).expression.(*Extended.Parser_Declaration);
	assert(using_declaration.name == "local");

	truncated_code := Extended.parse_expression("#code value: s64 =");
	assert(truncated_code.status == .INCOMPLETE);
	code_directive := truncated_code.root.(*Extended.Parser_Directive_Code);
	assert(code_directive.expression.kind == .DECLARATION);
	assert(code_directive.expression.(*Extended.Parser_Declaration).name == "value");

	truncated_run := Extended.parse_expression("#run,host { compute();");
	assert(truncated_run.status == .INCOMPLETE);
	run_directive := truncated_run.root.(*Extended.Parser_Directive_Run);
	assert((run_directive.flags & xx Extended.Code_Directive_Run_Flags_HOST) != 0);
	assert(run_directive.expression.kind == .BLOCK);
	assert(run_directive.expression.(*Extended.Parser_Block).statements.count == 1);

	truncated_insert := Extended.parse_expression("#insert,scope(");
	assert(truncated_insert.status == .INCOMPLETE);
	assert(truncated_insert.root.kind == .DIRECTIVE_INSERT);

	TRUNCATED_FOR_SOURCE :: "{ for <* :utf8_iter text {";
	truncated_for := Extended.parse_block(TRUNCATED_FOR_SOURCE);
	assert(truncated_for.status == .INCOMPLETE);
	assert(truncated_for.diagnostics.count > 0);
	for_node := truncated_for.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_For);
	assert((for_node.for_flags & (.REVERSE | .POINTER)) == (.REVERSE | .POINTER));
	assert(for_node.want_replacement_for_expansion.(*Extended.Parser_Ident).name == "utf8_iter");
	assert(for_node.iteration_expression.(*Extended.Parser_Ident).name == "text");
	assert(for_node.block != null);
	assert(Extended.reconstruct_source(*truncated_for) == TRUNCATED_FOR_SOURCE);
	missing_controlled_value := Extended.parse_block("{ for <= { tick(); } }");
	assert(missing_controlled_value.status == .RECOVERED);
	missing_controlled_for := missing_controlled_value.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_For);
	assert(missing_controlled_for.want_reverse_expression == null);
	assert(missing_controlled_for.block != null);

	MISSING_POINTER_VALUE_SOURCE :: "{ for *= { tick(); } }";
	missing_pointer_value := Extended.parse_block(MISSING_POINTER_VALUE_SOURCE);
	assert(missing_pointer_value.status == .RECOVERED);
	assert(missing_pointer_value.diagnostics.count > 0);
	missing_pointer_for := missing_pointer_value.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_For);
	assert(missing_pointer_for.want_pointer_expression == null);
	assert(missing_pointer_for.block != null);
	assert(Extended.reconstruct_source(*missing_pointer_value) == MISSING_POINTER_VALUE_SOURCE);

	truncated_default_case := Extended.parse_block("{ if value == { case 1; return; case; value :=");
	assert(truncated_default_case.status == .INCOMPLETE);
	case_if := truncated_default_case.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_If);
	assert(case_if.then_block.statements.count == 2);
	default_case := case_if.then_block.statements[1].(*Extended.Parser_Case);
	assert(default_case.condition == null);
	assert(default_case.then_block.statements.count == 1);
}

assert_literal_matches :: (source: string, expected: *Code_Node) {
	parsed := Extended.parse_expression(source);
	assert(parsed.status == .COMPLETE);
	assert(parsed.root.kind == expected.kind);

	actual_literal := parsed.root.(*Extended.Parser_Literal);
	expected_literal := expected.(*Code_Literal);
	assert(actual_literal.value_type == expected_literal.value_type);
	assert(actual_literal.value_flags == expected_literal.value_flags);

	if actual_literal.value_type == {
		case .NUMBER;
			if actual_literal.value_flags & .FLOAT {
				assert(actual_literal._float64 == expected_literal._float64);
			} else {
				assert(actual_literal._u64 == expected_literal._u64);
			}

		case .STRING;
			assert(actual_literal._string == expected_literal._string);

		case .BOOLEAN;
			assert(actual_literal._u64 == expected_literal._u64);
	}
}

assert_literal_fixture :: ($source: string) #expand {
	assert_literal_matches(source, compiler_node_for_source(source));
}

test_compiler_literal_shapes :: () {
	assert_literal_fixture("42");
	assert_literal_fixture("-42");
	assert_literal_fixture("0xff");
	assert_literal_fixture("0XFF");
	assert_literal_fixture("-0xFF");
	assert_literal_fixture("0b101");
	assert_literal_fixture("0B101");
	assert_literal_fixture("0h3F800000");
	assert_literal_fixture("0H3F800000");
	assert_literal_fixture("1.25");
	assert_literal_fixture("-1.25");
	assert_literal_fixture("1.2345678");
	assert_literal_fixture("1.23456789");
	assert_literal_fixture("1.0e100");
	assert_literal_fixture("1.0E100");
	assert_literal_fixture("\"hello\\n\"");
	assert_literal_fixture("true");
	assert_literal_fixture("false");
}

test_compiler_parenthesized_shape :: ($source: string) #expand {
	parsed := Extended.parse_expression(source);
	expected := compiler_node_for_source(source);

	assert(parsed.root.kind == expected.kind);
	assert((parsed.root.node_flags & .IS_PARENTHESIZED) == (expected.node_flags & .IS_PARENTHESIZED));
	assert(parsed.root.(*Extended.Parser_Ident).name == expected.(*Code_Ident).name);
}

test_compiler_null_shape :: ($source: string) #expand {
	parsed := Extended.parse_expression(source);
	expected := compiler_node_for_source(source).(*Code_Literal);
	actual := parsed.root.(*Extended.Parser_Literal);
	assert(actual.value_type == expected.value_type);
	assert(actual.pointer_literal_info.pointer_literal_type == expected.pointer_literal_info.pointer_literal_type);
	assert(actual.pointer_literal_info.offset_from_symbol == expected.pointer_literal_info.offset_from_symbol);
}

test_compiler_context_shape :: ($source: string) #expand {
	parsed := Extended.parse_expression(source);
	expected := compiler_node_for_source(source);
	assert(parsed.root.kind == expected.kind);
}

assert_unary_matches :: (source: string, expected: *Code_Node) {
	parsed := Extended.parse_expression(source);
	assert(parsed.status == .COMPLETE);
	assert(parsed.root.kind == expected.kind);

	actual_unary := parsed.root.(*Extended.Parser_Unary_Operator);
	expected_unary := expected.(*Code_Unary_Operator);
	assert(actual_unary.operator_type == expected_unary.operator_type);
	assert(actual_unary.subexpression.kind == expected_unary.subexpression.kind);
}

assert_unary_fixture :: ($source: string) #expand {
	assert_unary_matches(source, compiler_node_for_source(source));
}

test_compiler_prefix_shapes :: () {
	assert_unary_fixture("-value");
	assert_unary_fixture("+value");
	assert_unary_fixture("!value");
	assert_unary_fixture("~value");
	assert_unary_fixture("(.*)value");
}

assert_expression_tree_matches :: (actual: *Extended.Parser_Node, expected: *Code_Node) {
	assert(actual.kind == expected.kind);

	if actual.kind == {
		case .IDENT;
			assert(actual.(*Extended.Parser_Ident).name == expected.(*Code_Ident).name);
		case .BINARY_OPERATOR;
			actual_binary := actual.(*Extended.Parser_Binary_Operator);
			expected_binary := expected.(*Code_Binary_Operator);
			assert(actual_binary.operator_type == expected_binary.operator_type);
			assert_expression_tree_matches(actual_binary.left, expected_binary.left);
			assert_expression_tree_matches(actual_binary.right, expected_binary.right);
		case;
			assert(false, "Unsupported expression kind % in differential comparison.", actual.kind);
	}
}

assert_expression_tree_fixture :: ($source: string) #expand {
	assert_expression_tree_matches(Extended.parse_expression(source).root, compiler_node_for_source(source));
}

test_compiler_binary_shapes :: () {
	assert_expression_tree_fixture("a + b * c");
	assert_expression_tree_fixture("a * b % c + d");
	assert_expression_tree_fixture("a - b - c");
	assert_expression_tree_fixture("a << b & c == d && e || f");
}

#run,stallable test_compiler_identifier_shape("identifier");
#run,stallable test_compiler_literal_shapes();
#run,stallable test_compiler_parenthesized_shape("(identifier)");
#run,stallable test_compiler_null_shape("null");
#run,stallable test_compiler_context_shape("context");
#run,stallable test_compiler_prefix_shapes();
#run,stallable test_compiler_binary_shapes();
