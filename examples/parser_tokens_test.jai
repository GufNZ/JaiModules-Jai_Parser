#import "Basic";
#import "Compiler";
#import "String";

Default  :: #import "Jai_Parser";
Extended :: #import "Jai_Parser"(ENABLE_TRIVIA=true);

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

main :: () {
	test_default_tokens();
	test_star_token_contract();
	test_asm_token_contract();
	test_trivia_round_trip();
	test_node_token_spans();
	test_identifier_expression();
	test_literal_expressions();
	test_aggregate_literals();
	test_operator_declarations();
	test_placeholder_and_here_string();
	test_token_navigation();
	test_parser_node_pool();
	test_recovery_synchronization();
	test_complete_file_parsing();
	test_parenthesized_expression();
	test_missing_close_parenthesis();
	test_null_and_context();
	test_unexpected_token_diagnostic();
	test_diagnostic_tab_rendering();
	test_prefix_expressions();
	test_postfix_expressions();
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
	test_basic_statements_and_blocks();
	test_loop_and_scoped_statements();
	test_conditional_statements();
	test_statement_recovery();
	test_section_13_recovery();
	test_assembly_node_model();
}

test_default_tokens :: () {
	parsed := Default.materialise_tokens("a + b * c");
	assert(parsed.status == .COMPLETE);
	assert(parsed.tokens.count == 6);
	assert(parsed.tokens[0].type == .IDENT);
	assert(parsed.tokens[5].type == .END_OF_INPUT);
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
	source :: "#asm AVX, AVX2 {\n\t// declaration and pinning\n\tmov.8 apple:, -10;\n\tt: future_class === source;\n\tpopcnt?BITS result, value;\n\tcvtps2dq destination:, [base + index*8 - (-10.5)]!z &* mask; /* tail */\n}";
	parsed := Extended.materialise_tokens(source);
	assert(parsed.status == .COMPLETE);
	assert(Extended.reconstruct_source(*parsed) == source);

	expected_types := Extended.Token_Type.[
		#char "#", .IDENT, .IDENT, #char ",", .IDENT, #char "{",
		.IDENT, .NUMBER, .IDENT, #char ":", #char ",", #char "-", .NUMBER, #char ";",
		.IDENT, #char ":", .IDENT, .TRIPLE_EQUALS, .IDENT, #char ";",
		.IDENT, #char "?", .IDENT, .IDENT, #char ",", .IDENT, #char ";",
		.IDENT, .IDENT, #char ":", #char ",", #char "[", .IDENT, #char "+", .IDENT, #char "*", .NUMBER, #char "-", #char "(", #char "-", .NUMBER, #char ")", #char "]", #char "!", .IDENT, .BITWISE_AND, #char "*", .IDENT, #char ";",
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
		assert(slice(source, token.byte_start, token.byte_end - token.byte_start) == token.original_text);
	}

	assert(parsed.tokens[6].preceding_trivia == "\n\t// declaration and pinning\n\t");
	assert(parsed.tokens[parsed.tokens.count - 2].preceding_trivia == " /* tail */\n");

	modifier_source :: "value! value!n value!d value!u value!z value & mask value &* mask -10 +20 -10.5 +20.5";
	modifiers := Extended.materialise_tokens(modifier_source);
	expected_modifier_spellings := string.[
		"value", "!", "value", "!", "n", "value", "!", "d", "value", "!", "u", "value", "!", "z",
		"value", "&", "mask", "value", "&", "*", "mask",
		"-", "10", "+", "20", "-", "10.5", "+", "20.5", "",
	];
	assert(modifiers.tokens.count == expected_modifier_spellings.count);
	for token: modifiers.tokens {
		assert(token.original_text == expected_modifier_spellings[it_index]);
		assert(slice(modifier_source, token.byte_start, token.byte_end - token.byte_start) == token.original_text);
	}

	assert(modifiers.tokens[1].type == #char "!");
	assert(modifiers.tokens[15].type == .BITWISE_AND);
	assert(modifiers.tokens[18].type == .BITWISE_AND);
	assert(modifiers.tokens[19].type == #char "*");
	assert(modifiers.tokens[21].type == #char "-");
	assert(modifiers.tokens[22].type == .NUMBER);
	assert(modifiers.tokens[23].type == #char "+");
	assert(modifiers.tokens[24].type == .NUMBER);
	assert(Extended.reconstruct_source(*modifiers) == modifier_source);

	suffix_source :: "mov.8 mov.64 popcnt?BITS popcnt?T";
	suffixes := Extended.materialise_tokens(suffix_source);
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

	assert(Extended.reconstruct_source(*suffixes) == suffix_source);

	ordinary_source :: "object.member value?T";
	ordinary := Extended.materialise_tokens(ordinary_source);
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
	assert(Extended.reconstruct_source(*ordinary) == ordinary_source);
}

test_trivia_round_trip :: () {
	source :: "\xC2\xA0str :: #string /**/ , /**/ cr END\n123\nEND; // tail";
	parsed := Extended.materialise_tokens(source);
	assert(parsed.status == .COMPLETE);

	for token: parsed.tokens {
		assert(token.index == xx it_index);
	}

	body := parsed.tokens[8];
	assert(body.type == .STRING);
	assert((body.value_flags & .HERE_STRING) != 0);
	assert(body.preceding_trivia == "\n");
	assert(body.original_text == "123\n");
	assert(slice(source, body.byte_start, body.byte_end - body.byte_start) == body.original_text);

	reconstructed := Extended.reconstruct_source(*parsed);
	assert(reconstructed == source);
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

test_recovery_synchronization :: () {
	parsed := Extended.materialise_tokens("bad + value; next } tail");
	parser := Extended.Parser.{parsed=*parsed, cursor=1};

	expression_span := Extended.parser_synchronise(*parser, .EXPRESSION);
	assert(expression_span.first == xx 1);
	assert(expression_span.one_past_last == xx 3);
	assert(Extended.parser_peek(*parser).type == #char ";");

	nested_parsed := Extended.materialise_tokens("bad(inner; still_inner); next");
	nested_parser := Extended.Parser.{parsed=*nested_parsed};
	Extended.parser_synchronise(*nested_parser, .EXPRESSION);
	assert(nested_parser.cursor == 6);
	assert(Extended.parser_peek(*nested_parser).type == #char ";");

	guard := Extended.parser_progress_guard(*parser);
	assert(Extended.parser_ensure_progress(*parser, guard));
	assert(parser.cursor == 4);

	statement_span := Extended.parser_synchronise(*parser, .STATEMENT);
	declaration_span := Extended.parser_synchronise(*parser, .DECLARATION);
	assert(statement_span.first == statement_span.one_past_last);
	assert(declaration_span.first == declaration_span.one_past_last);

	block_span := Extended.parser_synchronise(*parser, .BLOCK);
	assert(block_span.first == xx 4);
	assert(block_span.one_past_last == xx 5);
	assert(Extended.parser_peek(*parser).type == #char "}");

	Extended.parser_eat(*parser);
	Extended.parser_eat(*parser);
	guard = Extended.parser_progress_guard(*parser);
	assert(!Extended.parser_ensure_progress(*parser, guard));
}

test_complete_file_parsing :: () {
	source :: "first :: 1;\nsecond: s64 = 2;\ntyped_constant: s64 : 3;\n#scope_file\nmain :: () { value := cast,no_check(s32) 1; }\nthird := 3;";
	parsed := Extended.parse_file(source, "fixture.jai");
	root := parsed.root.(*Extended.Parser_Block);
	if parsed.status != .COMPLETE {
		diagnostic := parsed.diagnostics[0];
		diagnostic_token := Extended.token_at(*parsed, diagnostic.span.first);
		assert(false, "Status %, diagnostics %, kind %, expected %, actual %, token '%'.", parsed.status, parsed.diagnostics.count, diagnostic.kind, diagnostic.expected_token, diagnostic.actual_token, diagnostic_token.original_text);
	}
	assert(parsed.fully_pathed_filename == "fixture.jai");
	assert(root.block_type == .DATA_DECLARATIONS);
	assert(!(root.node_flags & .IS_PARENTHESIZED));
	assert(root.statements.count == 6);
	assert((root.statements[2].(*Extended.Parser_Declaration).flags & .IS_CONSTANT) != 0);
	assert(Extended.reconstruct_source(*parsed) == source);

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

	terminators_source :: "normal :: () {}\nafter_normal :: 1;\nquick_block :: () => {}\n#scope_file\nquick_expression :: value => value + 1;\nRecord :: struct {}\nafter_struct :: 2;\nChoice :: enum { ONLY; }\nouter :: () { nested :: () {}\nnext := 3;\nNested_Record :: struct {}\nNested_Choice :: enum { ONLY; } }\nfinal :: () {}";
	terminators := Extended.parse_file(terminators_source);
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

test_placeholder_and_here_string :: () {
	placeholder := Extended.parse_expression("---");
	assert(placeholder.status == .COMPLETE);
	assert(placeholder.root.kind == .PLACEHOLDER);

	source :: "#string END\nbody\nEND";
	here_string := Extended.parse_expression(source);
	assert(here_string.status == .COMPLETE, "Here-string status %, token count %, diagnostics %.", here_string.status, here_string.tokens.count, here_string.diagnostics.count);
	literal := here_string.root.(*Extended.Parser_Literal);
	assert(literal.value_type == .STRING);
	assert((literal.value_flags & .HERE_STRING) != 0);
	assert(literal._string == "body\n");
	assert(Extended.reconstruct_source(*here_string) == source);

	cr_source :: "#string,cr END\nbody\nEND";
	cr_here_string := Extended.parse_expression(cr_source);
	assert(cr_here_string.status == .COMPLETE);
	assert(cr_here_string.root.(*Extended.Parser_Literal)._string == "body\r\n");
	assert(Extended.reconstruct_source(*cr_here_string) == cr_source);

	percent_source :: "#string,\\% END\n%\\%\nEND";
	percent_here_string := Extended.parse_expression(percent_source);
	assert(percent_here_string.status == .COMPLETE);
	percent_value := percent_here_string.root.(*Extended.Parser_Literal)._string;
	assert(percent_value.count == 3);
	assert(percent_value[0] == #char "%");
	assert(percent_value[1] == 31);
	assert(percent_value[2] == #char "\n");
	assert(percent_value == COMPILER_PERCENT_HERE_STRING);
	assert(Extended.reconstruct_source(*percent_here_string) == percent_source);
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
	source :: "(identifier";
	parsed := Extended.parse_expression(source);
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
	assert(reconstructed == source);

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
	assert((caller_code_node.code_flags & xx 0x4) != 0);
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
	assert((host_run_node.flags & xx 0x10) != 0);
	assert((host_run_node.flags & .HAS_IMPLICIT_RETURN_TYPES) != 0);
	host_block_run := Extended.parse_expression("#run,host { compute(); }");
	host_block_run_node := host_block_run.root.(*Extended.Parser_Directive_Run);
	assert((host_block_run_node.flags & xx 0x10) != 0);
	assert((host_block_run_node.flags & .HAS_IMPLICIT_RETURN_TYPES) == 0);
	assert(host_block_run_node.expression.(*Extended.Parser_Block).statements.count == 1);

	insert := Extended.parse_expression("#insert generated_code");
	assert(insert.root.(*Extended.Parser_Directive_Insert).expression.(*Extended.Parser_Ident).name == "generated_code");
	insert_options := Extended.parse_expression("#insert,scope(caller) (break=break outer, continue=continue outer, remove=remove outer) body");
	insert_node := insert_options.root.(*Extended.Parser_Directive_Insert);
	assert(insert_node.scope_redirection.(*Extended.Parser_Ident).name == "caller");
	assert(insert_node.break_replacement.(*Extended.Parser_Loop_Control).control_type == .BREAK);
	assert(insert_node.continue_replacement.(*Extended.Parser_Loop_Control).control_type == .CONTINUE);
	assert(insert_node.remove_replacement.(*Extended.Parser_Loop_Control).control_type == .REMOVE);
	insert_procedure := Extended.parse_expression("#insert -> string { return \"generated\"; }");
	implicit_run := insert_procedure.root.(*Extended.Parser_Directive_Insert).expression.(*Extended.Parser_Directive_Run);
	assert((implicit_run.flags & .SYNTACTICALLY_IMPLICIT) != 0);
	assert(implicit_run.procedure.returns.count == 1);
	assert(implicit_run.expression.(*Extended.Parser_Block).statements.count == 1);

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

	shared := Extended.parse_declaration("mask, lower, upper: u32 = 0xffffffff;");
	assert(shared.status == .COMPLETE);
	shared_node := shared.root.(*Extended.Parser_Compound_Declaration);
	assert(shared_node.comma_separated_assignment.arguments.count == 3);
	assert(shared_node.declaration_properties.expression.kind == .LITERAL);
	assert(shared_node.declaration_properties.expression.(*Extended.Parser_Literal)._u64 == 0xffffffff);
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

	inlined := Extended.parse_declaration("fast :: inline () {}");
	assert(inlined.status == .COMPLETE);
	assert((inlined.root.(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).procedure_flags & .SYNTACTICALLY_MARKED_AS_INLINE_YES) != 0);

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

test_declaration_metadata :: () {
	aligned := Extended.parse_declaration("value: s64 #align 16;");
	assert(aligned.status == .COMPLETE);
	aligned_node := aligned.root.(*Extended.Parser_Declaration);
	assert(aligned_node.alignment_expression.(*Extended.Parser_Literal)._u64 == 16);

	noted := Extended.parse_declaration("value: s64; @JsonIgnore");
	assert(noted.status == .COMPLETE);
	noted_node := noted.root.(*Extended.Parser_Declaration);
	assert(noted_node.notes.count == 1);
	assert(noted_node.notes[0].text == "JsonIgnore");

	scoped := Extended.parse_declaration("`value: s64;");
	assert(scoped.status == .COMPLETE);
	assert((scoped.root.(*Extended.Parser_Declaration).flags & .HAS_SCOPE_MODIFIER) != 0);

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
	parsed := Extended.parse_block("{ while ready { break; } for item, index: values { continue; } for 1..3 defer tick(); using state; using local: State; push_context new_context { return; } }");
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

test_conditional_statements :: () {
	parsed := Extended.parse_block("{ if ready then run(); else stop(); if outer then if inner accept(); else reject(); }");
	assert(parsed.status == .COMPLETE);
	block := parsed.root.(*Extended.Parser_Block);
	assert(block.statements.count == 2);
	first_if := block.statements[0].(*Extended.Parser_If);
	assert(first_if.then_block.statements[0].kind == .PROCEDURE_CALL);
	assert(first_if.else_block.statements[0].kind == .PROCEDURE_CALL);
	nested_if := block.statements[1].(*Extended.Parser_If).then_block.statements[0].(*Extended.Parser_If);
	assert(nested_if.else_block != null);

	ifx_expression := Extended.parse_expression("ifx ready then 1 else 2");
	assert(ifx_expression.status == .COMPLETE);
	ifx_node := ifx_expression.root.(*Extended.Parser_If);
	assert((ifx_node.if_flags & .IS_IFX) != 0);
	assert(ifx_node.then_block.statements[0].(*Extended.Parser_Literal)._u64 == 1);
	assert(ifx_node.else_block.statements[0].(*Extended.Parser_Literal)._u64 == 2);

	block_ifx := Extended.parse_expression("ifx ready { prepare(); 1; } else { 2; }");
	assert(block_ifx.status == .COMPLETE);
	assert(block_ifx.root.(*Extended.Parser_If).then_block.statements.count == 2);

	switch_source :: "{ if #complete value == { case 1; return 1; case 2; #through; case 3; return 3; case; return 0; } }";
	switch_parsed := Extended.parse_block(switch_source);
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
	static_statement := Extended.parse_block("{ #if true { enabled := 1; } else #if false disabled := 2; else fallback := 3; }");
	assert(static_statement.status == .COMPLETE);
	static_if := static_statement.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_If);
	assert((static_if.if_flags & .IS_STATIC) != 0);
	assert(static_if.then_block.block_type == .IMPERATIVE);
	nested_static_if := static_if.else_block.statements[0].(*Extended.Parser_If);
	assert((nested_static_if.if_flags & .IS_STATIC) != 0);
	assert(nested_static_if.else_block.statements[0].kind == .DECLARATION);

	static_file := Extended.parse_file("#if true { first :: 1; } else second :: 2;\nafter :: 3;");
	assert(static_file.status == .COMPLETE);
	file_if := static_file.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_If);
	assert((file_if.if_flags & .IS_STATIC) != 0);
	assert(file_if.then_block.block_type == .DATA_DECLARATIONS);
	assert(file_if.else_block.statements[0].kind == .DECLARATION);
	assert(static_file.root.(*Extended.Parser_Block).statements.count == 2);

	static_member := Extended.parse_declaration("Conditional :: struct { #if true { enabled: s64; } else disabled: s64; }");
	assert(static_member.status == .COMPLETE);
	member_if := static_member.root.(*Extended.Parser_Declaration).expression.(*Extended.Parser_Struct).block.statements[0].(*Extended.Parser_If);
	assert((member_if.if_flags & .IS_STATIC) != 0);
	assert(member_if.then_block.block_type == .DATA_DECLARATIONS);

	static_empty_default := Extended.parse_block("{ #if OS == { case .WINDOWS; return; case; } }");
	assert(static_empty_default.status == .COMPLETE);
	assert(static_empty_default.synthetic_tokens.count == 0);
	static_cases := static_empty_default.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_If).then_block.statements;
	assert(static_cases.count == 2);
	assert(static_cases[1].(*Extended.Parser_Case).then_block.statements.count == 0);
}

test_preserved_directive_forms :: () {
	placeholder_source :: "#placeholder Apple;\nafter :: 1;";
	placeholder := Extended.parse_file(placeholder_source);
	assert(placeholder.status == .COMPLETE);
	placeholder_node := placeholder.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Placeholder);
	assert(placeholder_node.name == "Apple");
	assert(Extended.reconstruct_source(*placeholder) == placeholder_source);

	as_fields := Extended.parse_declaration("Container :: struct { #as using base: Base; }");
	assert(as_fields.status == .COMPLETE);
	as_members := as_fields.root.(*Extended.Parser_Declaration).expression.(*Extended.Parser_Struct).block.statements;
	assert(as_members.count == 1);
	for as_members {
		using_node := it.(*Extended.Parser_Using);
		assert((using_node.expression.(*Extended.Parser_Declaration).flags & .IS_MARKED_AS_AS) != 0);
	}

	using_declarations := Extended.parse_file("using Global: State;\nContainer :: struct { using local: State; using #as base: Base; }");
	assert(using_declarations.status == .COMPLETE);
	file_statements := using_declarations.root.(*Extended.Parser_Block).statements;
	assert(file_statements[0].(*Extended.Parser_Using).expression.(*Extended.Parser_Declaration).name == "Global");
	container_members := file_statements[1].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Struct).block.statements;
	assert(container_members.count == 2);
	assert(container_members[0].(*Extended.Parser_Using).expression.(*Extended.Parser_Declaration).name == "local");
	suffix_as := container_members[1].(*Extended.Parser_Using).expression.(*Extended.Parser_Declaration);
	assert(suffix_as.name == "base");
	assert((suffix_as.flags & .IS_MARKED_AS_AS) != 0);

	asm_source :: "{ #asm AVX, AVX2 { mov apple:, 10; nested { ignored; }; } after(); }";
	assembly := Extended.parse_block(asm_source);
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
	assert(Extended.token_at(*assembly, asm_node.statements[0].instruction.operands[0].span.first).original_text == "apple");
	assert(Extended.token_at(*assembly, asm_node.statements[0].instruction.operands[1].span.first).original_text == "10");
	assert(Extended.token_at(*assembly, asm_node.statements[0].span.first).original_text == "mov");
	assert(Extended.token_at(*assembly, asm_node.statements[1].span.first).original_text == "nested");
	assert(asm_node.body_span.one_past_last > asm_node.body_span.first);
	assert(Extended.reconstruct_source(*assembly) == asm_source);

	bare_asm := Extended.parse_block("{ #asm {} }");
	assert(bare_asm.status == .COMPLETE);
	bare_asm_node := bare_asm.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Asm);
	assert(bare_asm_node.features.count == 0);
	assert(bare_asm_node.statements.count == 0);
	assert(bare_asm_node.body_span.first == bare_asm_node.body_span.one_past_last);

	shared_scope := Extended.parse_block("{ #asm { first: gpr; } #asm { mov first, 1; } { #asm { nested: gpr; } } }");
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
	assert(second_asm.statements.count == 1);
	assert(Extended.token_at(*shared_scope, first_asm.statements[0].span.first).original_text == "first");
	assert(Extended.token_at(*shared_scope, second_asm.statements[0].span.first).original_text == "mov");
	assert(nested_asm.enclosing_scope == nested_block);
	assert(nested_asm.enclosing_scope != first_asm.enclosing_scope);

	conditional_asm := Extended.parse_block("{ #if BITS == 8 #asm { mov.8 result:, value; } else #asm { mov.64 result:, value; } }");
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

	polymorphic_asm := Extended.parse_block("{ #asm { popcnt?BITS result, value; popcnt?T other, value; } }");
	assert(polymorphic_asm.status == .COMPLETE);
	polymorphic_statements := polymorphic_asm.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Asm).statements;
	assert(polymorphic_statements.count == 2);
	assert(polymorphic_statements[0].instruction.size.kind == .POLYMORPHIC);
	assert(polymorphic_statements[0].instruction.size.polymorphic_name.name == "BITS");
	assert(polymorphic_statements[1].instruction.size.polymorphic_name.name == "T");
	assert(polymorphic_statements[0].instruction.operands.count == 2);
	assert(polymorphic_statements[1].instruction.operands.count == 2);

	missing_asm_semicolon := Extended.parse_block("{ #asm { mov result:, value } after(); }");
	assert(missing_asm_semicolon.status == .RECOVERED);
	assert(missing_asm_semicolon.diagnostics.count == 1);
	assert(missing_asm_semicolon.diagnostics[0].kind == .EXPECTED_TOKEN);
	assert(missing_asm_semicolon.diagnostics[0].expected_token == #char ";");
	assert(missing_asm_semicolon.root.(*Extended.Parser_Block).statements.count == 2);
	missing_semicolon_asm := missing_asm_semicolon.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Asm);
	assert(missing_semicolon_asm.statements[0].kind == .INSTRUCTION);
	assert(missing_semicolon_asm.statements[0].instruction.operands.count == 2);

	truncated_asm := Extended.parse_block("{ #asm { mov value:, 1;");
	assert(truncated_asm.status == .INCOMPLETE);
	truncated_asm_node := truncated_asm.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_Asm);
	assert(truncated_asm_node.statements.count == 1);
	assert(truncated_asm_node.statements[0].span.one_past_last == truncated_asm_node.body_span.one_past_last);
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

	nested_recovery := Extended.parse_file("outer :: () { #unknown { leaked := 1; } after := 2; }\nfinal :: 3;");
	assert(nested_recovery.status == .RECOVERED);
	nested_root := nested_recovery.root.(*Extended.Parser_Block);
	assert(nested_root.statements.count == 2);
	assert(nested_root.statements[0].(*Extended.Parser_Declaration).name == "outer");
	assert(nested_root.statements[1].(*Extended.Parser_Declaration).name == "final");
	outer_body := nested_root.statements[0].(*Extended.Parser_Declaration).expression.(*Extended.Parser_Procedure_Header).body_or_null.block;
	assert(outer_body.statements.count == 1);
	assert(outer_body.statements[0].(*Extended.Parser_Declaration).name == "after");

	declaration_recovery := Extended.parse_file("broken :: () #unknown { leaked := 1; }\nafter :: 2;");
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
	assert((run_directive.flags & xx 0x10) != 0);
	assert(run_directive.expression.kind == .BLOCK);
	assert(run_directive.expression.(*Extended.Parser_Block).statements.count == 1);

	truncated_insert := Extended.parse_expression("#insert,scope(");
	assert(truncated_insert.status == .INCOMPLETE);
	assert(truncated_insert.root.kind == .DIRECTIVE_INSERT);

	truncated_for := Extended.parse_block("{ for <* :utf8_iter text {");
	assert(truncated_for.status == .INCOMPLETE);
	for_node := truncated_for.root.(*Extended.Parser_Block).statements[0].(*Extended.Parser_For);
	assert((for_node.for_flags & (.REVERSE | .POINTER)) == (.REVERSE | .POINTER));
	assert(for_node.want_replacement_for_expansion.(*Extended.Parser_Ident).name == "utf8_iter");
	assert(for_node.iteration_expression.(*Extended.Parser_Ident).name == "text");
	assert(for_node.block != null);

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

	if actual_literal.value_type == .NUMBER {
		if actual_literal.value_flags & .FLOAT {
			assert(actual_literal._float64 == expected_literal._float64);
		} else {
			assert(actual_literal._u64 == expected_literal._u64);
		}
	} else if actual_literal.value_type == .STRING {
		assert(actual_literal._string == expected_literal._string);
	} else if actual_literal.value_type == .BOOLEAN {
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
	assert_literal_fixture("-0xff");
	assert_literal_fixture("0b101");
	assert_literal_fixture("1.25");
	assert_literal_fixture("-1.25");
	assert_literal_fixture("1.2345678");
	assert_literal_fixture("1.23456789");
	assert_literal_fixture("1.0e100");
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
