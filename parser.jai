#import "Compiler";
#import "Pool";

Token_Index :: #type,distinct s64;
Parser_Checkpoint :: #type,distinct s64;

//TODO: postfix cast

Token_Span :: struct {
	first: Token_Index;
	one_past_last: Token_Index;
}

Parse_Status :: enum u8 {
	COMPLETE;
	INCOMPLETE;
	RECOVERED;
	FATAL;
}

Recovery_Action :: enum u8 {
	NONE;
	INSERT_MISSING_TOKEN;
	SKIP_TOKENS;
}

Synchronization_Context :: enum u8 {
	EXPRESSION;
	STATEMENT;
	DECLARATION;
	BLOCK;
}

//TODO: document Parser_Progress_Guard structure and its usage.
Parser_Progress_Guard :: struct {
	cursor: s64;
}

Synthetic_Token :: struct {
	token: Token;
	insertion_index: Token_Index;
}

Parse_Diagnostic_Info :: struct {
	span: Token_Span;
	message: string;
}

Parse_Diagnostic :: struct {
	kind: enum u8 {
		EXPECTED_TOKEN;
		EXPECTED_EXPRESSION;
		UNEXPECTED_TOKEN;
	}

	span: Token_Span;
	message: string;
	related_information: [] Parse_Diagnostic_Info;
	expected_token: Token_Type;
	actual_token: Token_Type;
	recovery_action: Recovery_Action;
}

Rendered_Diagnostic_Line :: struct {
	source: string;
	carets: string;
}

render_diagnostic_line :: (source_line: string, c0: s64, c1: s64, tab_size: s64 = 4) -> Rendered_Diagnostic_Line {
	assert(tab_size > 0);
	assert(c0 >= 1 && c1 >= c0);
	assert(c1 <= source_line.count + 1);

	result: Rendered_Diagnostic_Line;
	source_builder: String_Builder;
	visual_column: s64 = 1;
	visual_c0: s64;
	visual_c1: s64;

	for source_line {
		source_column := it_index + 1;
		if source_column == c0	visual_c0 = visual_column;
		if source_column == c1	visual_c1 = visual_column;


		if it == #char "\t" {
			spaces := tab_size - ((visual_column - 1) % tab_size);
			for 0..spaces-1		append(*source_builder, " ");
			visual_column += spaces;
		} else {
			append(*source_builder, to_string(*it, 1));
			visual_column += 1;
		}
	}

	if c0 == source_line.count + 1	visual_c0 = visual_column;
	if c1 == source_line.count + 1	visual_c1 = visual_column;

	caret_builder: String_Builder;
	for 1..visual_c0-1	append(*caret_builder, " ");
	caret_count := Max(1, visual_c1 - visual_c0);
	for 1..caret_count	append(*caret_builder, "^");

	result.source = builder_to_string(*source_builder);
	result.carets = builder_to_string(*caret_builder);
	return result;
}

#if ENABLE_TRIVIA {
	Parser_Token :: struct {
		using lexer_token: Token;

		index: Token_Index;
		preceding_trivia_byte_start: s64;
		byte_start: s64;
		byte_end: s64;
	}
} else {
	Parser_Token :: Token;
}

Parsed_Source :: struct {
	// Source and all token text are borrowed - they must outlive this value.
	source: string;
	tokens: [..] Parser_Token;
	synthetic_tokens: [..] Synthetic_Token;
	diagnostics: [..] Parse_Diagnostic;
	status: Parse_Status;
	root: *Parser_Node;
	node_pool: Pool;
}

//LATER: codegen these based on what's in Preload.  Consider alt layouts that allow for direct conversion between subclasses, e.g. put the trivia fields first?
Parser_Node :: struct {
	#if ENABLE_TRIVIA {
		first_token: Token_Index;
		one_past_last_token: Token_Index;
	}

	#as using code_node: Code_Node;
}

TYPES :: Type.[Code_Ident];
NODES :: #run {
	t: [..]Type_Info_Struct;
	for NODES {
		array_add(t, get_type_info(it));
	}
}
//BUG: why is this not firing?
#insert -> string {
	debug_break();
	print(">>>Generating parser nodes...\n");
	printNode :: (t: Type_Info_Struct, b: *String_Builder) {
		p := replace(t.name, "Code", "Parser");
		print(b, "% :: {\t#as using base: Parser_Node;\n", p);
		print(b, "\t_padding: [%]u8;\n", t.runtime_size - size_of(Code_Node) - 6);
		print(b, "\t#overlay(code_node) #as using _%: %1;\n", t.name);
		print(b, "}\n");

	}

	b: String_Builder;
	#insert -> string {
		for NODES {
			printNode(it, *b);
		}
	}
	return builder_to_string(*b);
}

Parser_Type_Instantiation :: struct {
	#as using base: Parser_Node;
	kind = .TYPE_INSTANTIATION;

	result: *Type_Info;
	type_valued_expression: *Parser_Node;
	must_implement: *Parser_Node;
	pointer_to: *Parser_Type_Instantiation;
	type_directive_target: *Parser_Type_Instantiation;
	array_element_type: *Parser_Type_Instantiation;
	array_dimension: *Parser_Node;
	inst_flags: type_of(Code_Type_Instantiation.inst_flags);
}

Parser_Struct_Literal_Info :: struct {
	type_expression: *Parser_Type_Instantiation;
	arguments: [] *Parser_Node;
}

Parser_Array_Literal_Info :: struct {
	element_type: *Parser_Type_Instantiation;
	alignment: *Parser_Node;
	array_members: [] *Parser_Node;
	array_literal_flags: type_of(Code_Array_Literal_Info.array_literal_flags);
}

Parser_Literal :: struct {
	#as using base: Parser_Node;
	kind = .LITERAL;

	value_type: type_of(Code_Literal.value_type);
	using values: union {
		_string: string;
		_float64: float64;
		_s64: s64;
		_u64: u64;

		struct_literal_info: *Parser_Struct_Literal_Info;
		array_literal_info: *Parser_Array_Literal_Info;
		pointer_literal_info: *Code_Pointer_Literal_Info;
		type_info_literal_defn: *Code_Type_Definition;
	}

	value_flags: type_of(Code_Literal.value_flags);
}

Parser_Context :: struct {
	#as using base: Parser_Node;
	kind = .CONTEXT;
}

Parser_Placeholder :: struct {
	#as using base: Parser_Node;
	kind = .PLACEHOLDER;
}

Parser_Unary_Operator :: struct {
	#as using base: Parser_Node;
	kind = .UNARY_OPERATOR;

	operator_type: Operator_Type;
	subexpression: *Parser_Node;
}

Parser_Binary_Operator :: struct {
	#as using base: Parser_Node;
	kind = .BINARY_OPERATOR;

	operator_type: Operator_Type;
	flags: Code_Binary_Operator.Flags;
	left: *Parser_Node;
	right: *Parser_Node;
}

Parser_Argument :: struct {
	expression: *Parser_Node;
	name: *Parser_Ident;
}

Parser_Procedure_Call :: struct {
	#as using base: Parser_Node;
	kind = .PROCEDURE_CALL;

	procedure_expression: *Parser_Node;
	resolved_procedure_expression: *Parser_Node;
	overloads: *[] *Code_Declaration;
	arguments_unsorted: [] Parser_Argument;
	arguments_sorted: [] *Parser_Node;
	num_return_values_received: s64;
	macro_expansion_block: *Parser_Block;
	context_modification: *Code_Procedure_Call.Context_Modification;
	flags: Code_Procedure_Call.Flags;
}

Parser_Cast :: struct {
	#as using base: Parser_Node;
	kind = .CAST;

	target_type: *Parser_Type_Instantiation;
	expression: *Parser_Node;
	cast_flags: type_of(Code_Cast.cast_flags);
}

Parser_Expression_Query :: struct {
	#as using base: Parser_Node;
	kind = .EXPRESSION_QUERY;

	query_kind: type_of(Code_Expression_Query.query_kind);
	expression_to_query: *Parser_Node;
}

Parser_Type_Query :: struct {
	#as using base: Parser_Node;
	kind = .TYPE_QUERY;

	query_kind: type_of(Code_Type_Query.query_kind);
	type_to_query: *Parser_Type_Instantiation;
}

Parser_Directive_Code :: struct {
	#as using base: Parser_Node;
	kind = .DIRECTIVE_CODE;

	expression: *Parser_Node;
	code_flags: type_of(Code_Directive_Code.code_flags);
}

Parser_Directive_Run :: struct {
	#as using base: Parser_Node;
	kind = .DIRECTIVE_RUN;

	procedure: *Parser_Procedure_Header;
	flags: type_of(Code_Directive_Run.flags);
	assertion_string: string;
	expression: *Parser_Node;
}

Parser_Directive_Insert :: struct {
	#as using base: Parser_Node;
	kind = .DIRECTIVE_INSERT;

	expression: *Parser_Node;
	scope_redirection: *Parser_Node;
	break_replacement: *Parser_Node;
	continue_replacement: *Parser_Node;
	remove_replacement: *Parser_Node;
	expansion: *Parser_Node;
	is_internal: bool;
}

Parser_Directive_Bake :: struct {
	#as using base: Parser_Node;
	kind = .DIRECTIVE_BAKE;

	procedure_call: *Parser_Procedure_Call;
	bake_type: type_of(Code_Directive_Bake.bake_type);
}

Parser_Directive_Location :: struct {
	#as using base: Parser_Node;
	kind = .DIRECTIVE_LOCATION;

	expression: *Parser_Node;
	is_caller_location: bool;
}

Parser_Directive_Library :: struct {
	#as using base: Parser_Node;
	kind = .DIRECTIVE_LIBRARY;

	name: string;
	library_flags: type_of(Code_Directive_Library.library_flags);
}

Parser_Directive_Load :: struct {
	#as using base: Parser_Node;
	kind = .DIRECTIVE_LOAD;

	short_name: string;
	load_flags: s32;
}

Parser_Directive_Bytes :: struct {
	#as using base: Parser_Node;
	kind = .DIRECTIVE_BYTES;

	expression: *Parser_Node;
}

Parser_Directive_Procedure_Name :: struct {
	#as using base: Parser_Node;
	kind = .DIRECTIVE_PROCEDURE_NAME;

	argument: *Parser_Node;
}

Parser_Directive_Wildcard :: struct {
	#as using base: Parser_Node;
	kind = .DIRECTIVE_WILDCARD;

	index: s32 = -1;
}

Parser_Directive_Exists :: struct {
	#as using base: Parser_Node;
	kind = .DIRECTIVE_EXISTS;

	query_expression: *Parser_Node;
	sync_expression: *Parser_Node;
}

Parser_Directive_Import :: struct {
	#as using base: Parser_Node;
	kind = .DIRECTIVE_IMPORT;

	name: string;
	flags: type_of(Code_Directive_Import.flags);
	import_type: type_of(Code_Directive_Import.import_type);
	module_parameters_call: *Parser_Procedure_Call;
	program_parameters_call: *Parser_Procedure_Call;
}

Parser_Directive_Poke_Name :: struct {
	#as using base: Parser_Node;
	kind = .DIRECTIVE_POKE_NAME;

	module_expression: *Parser_Node;
	name: string;
}

Parser_Directive_Through :: struct {
	#as using base: Parser_Node;
	kind = .DIRECTIVE_THROUGH;
}

Parser_Directive_Overlay :: struct {
	#as using base: Parser_Node;
	kind = .DIRECTIVE_OVERLAY;

	target_expression: *Parser_Node;
	declaration_or_using: *Parser_Node;
}

Parser_Directive_Add_Context :: struct {
	#as using base: Parser_Node;
	kind = .DIRECTIVE_ADD_CONTEXT;

	expression: *Parser_Node;
}

Parser_Directive_Context_Type :: struct {
	#as using base: Parser_Node;
	kind = .DIRECTIVE_CONTEXT_TYPE;
}

Parser_Directive_Scope :: struct {
	#as using base: Parser_Node;
	kind = .DIRECTIVE_SCOPE;

	scope_type: type_of(Code_Directive_Scope.scope_type);
}

Parser_Directive_Module_Parameters :: struct {
	#as using base: Parser_Node;
	kind = .DIRECTIVE_MODULE_PARAMETERS;

	module_parameters: *Parser_Procedure_Header;
	program_parameters: *Parser_Procedure_Header;
	common_code: *Parser_Block;
}

Parser_Directive_Modify :: struct {
	#as using base: Parser_Node;
	kind = .DIRECTIVE_MODIFY;

	block: *Parser_Block;
}

Parser_Declaration :: struct {
	#as using base: Parser_Node;
	kind = .DECLARATION;

	name: string;
	import_target: *Parser_Declaration;
	type_inst: *Parser_Type_Instantiation;
	expression: *Parser_Node;
	flags: type_of(Code_Declaration.flags);
	alignment_expression: *Parser_Node;
	notes: [] *Parser_Note;
	program_export_name: string;
}

Parser_Note :: struct {
	#as using base: Parser_Node;
	kind = .NOTE;

	text: string;
}

Parser_Comma_Separated_Argument :: struct {
	node: *Parser_Node;
}

Parser_Comma_Separated_Arguments :: struct {
	#as using base: Parser_Node;
	kind = .COMMA_SEPARATED_ARGUMENTS;

	arguments: [] Parser_Comma_Separated_Argument;
}

Parser_Compound_Declaration :: struct {
	#as using base: Parser_Node;
	kind = .COMPOUND_DECLARATION;

	comma_separated_assignment: Parser_Comma_Separated_Arguments;
	declaration_properties: Parser_Declaration;
	alignment_expression: *Parser_Node;
	notes: [] *Parser_Note;
	operator_type: Operator_Type;
}

Parser_Return :: struct {
	#as using base: Parser_Node;
	kind = .RETURN;

	arguments_unsorted: [] Parser_Argument;
	arguments_sorted: [] *Parser_Node;
	return_flags: type_of(Code_Return.return_flags);
}

Parser_Loop_Control :: struct {
	#as using base: Parser_Node;
	kind = .LOOP_CONTROL;

	control_type: type_of(Code_Loop_Control.control_type);
	target_ident: *Parser_Ident;
}

Parser_While :: struct {
	#as using base: Parser_Node;
	kind = .WHILE;

	condition: *Parser_Node;
	block: *Parser_Block;
}

Parser_If :: struct {
	#as using base: Parser_Node;
	kind = .IF;

	condition: *Parser_Node;
	then_block: *Parser_Block;
	else_block: *Parser_Block;
	if_flags: type_of(Code_If.if_flags);
	static_if_flags: type_of(Code_If.static_if_flags);
	static_if_accepted_case: *Parser_Case;
}

Parser_Case :: struct {
	#as using base: Parser_Node;
	kind = .CASE;

	condition: *Parser_Node;
	then_block: *Parser_Block;
	owning_if: *Parser_If;
	marked_as_fallthrough: bool;
}

Parser_For :: struct {
	#as using base: Parser_Node;
	kind = .FOR;

	iteration_expression: *Parser_Node;
	iteration_expression_right: *Parser_Node;
	block: *Parser_Block;
	ident_it: *Parser_Ident;
	ident_it_index: *Parser_Ident;
	ident_decl: *Parser_Declaration;
	index_decl: *Parser_Declaration;
	want_replacement_for_expansion: *Parser_Node;
	want_pointer_expression: *Parser_Node;
	want_reverse_expression: *Parser_Node;
	macro_expansion_procedure_call: *Parser_Procedure_Call;
	for_flags: For_Flags;
}

Parser_Defer :: struct {
	#as using base: Parser_Node;
	kind = .DEFER;

	block: *Parser_Block;
	is_backticked: bool;
}

Parser_Using :: struct {
	#as using base: Parser_Node;
	kind = .USING;

	expression: *Parser_Node;
	filter_type: type_of(Code_Using.filter_type);
	filter_expression: *Parser_Node;
	no_parameters: bool;
}

Parser_Push_Context :: struct {
	#as using base: Parser_Node;
	kind = .PUSH_CONTEXT;

	to_push: *Parser_Node;
	block: *Parser_Block;
	push_context_flags: type_of(Code_Push_Context.push_context_flags);
}

Parser_Procedure_Header :: struct {
	#as using base: Parser_Node;
	kind = .PROCEDURE_HEADER;

	constants_block: *Parser_Block;
	arguments: [] *Parser_Declaration;
	returns: [] *Parser_Declaration;
	parameter_usings: [] *Parser_Using;
	name: string;
	foreign_function_name: string;
	library_identifier: *Parser_Ident;
	deprecation_string: string;
	polymorph_source_header: *Parser_Procedure_Header;
	modify_directives: [] *Parser_Directive_Modify;
	body_or_null: *Parser_Procedure_Body;
	procedure_flags: type_of(Code_Procedure_Header.procedure_flags);
	notes: [] *Parser_Note;
}

Parser_Procedure_Body :: struct {
	#as using base: Parser_Node;
	kind = .PROCEDURE_BODY;

	block: *Parser_Block;
	header: *Parser_Procedure_Header;
	body_flags: type_of(Code_Procedure_Body.body_flags);
}

Parser_Struct :: struct {
	#as using base: Parser_Node;
	kind = .STRUCT;

	modify_directives: [] *Parser_Directive_Modify;
	block: *Parser_Block;
	arguments_block: *Parser_Block;
	constants_block: *Parser_Block;
	notes: [] *Parser_Note;
	textual_flags: Struct_Textual_Flags;
	alignment: s32 = -1;
}

Parser_Enum :: struct {
	#as using base: Parser_Node;
	kind = .ENUM;

	internal_type_inst: *Parser_Type_Instantiation;
	block: *Parser_Block;
	notes: [] *Parser_Note;
	marked_as_complete: bool;
	marked_as_specified: bool;
	is_flags: bool;
}

Parser_Block :: struct {
	#as using base: Parser_Node;
	kind = .BLOCK;

	parent: *Parser_Block;
	block_type: type_of(Code_Block.block_type);
	block_flags: type_of(Code_Block.block_flags);
	belongs_to_struct: *Parser_Struct;
	members: [] *Code_Scope_Entry;
	statements: [] *Parser_Node;
	owning_statement: *Parser_Node;
}

Parser :: struct {
	parsed: *Parsed_Source;
	cursor: s64;
}

parser_node_allocator :: inline (parsed: *Parsed_Source) -> Allocator {
	return .{proc=pool_allocator_proc, data=*parsed.node_pool};
}

new_parser_node :: inline (parser: *Parser, $T: Type) -> *T {
	return New(
		T,
		//LATER: speed: initialized=false --need to verify safe first.  Audit init coverage.
		,, parser_node_allocator(parser.parsed)
	);
}

release_parser_tree :: (parsed: *Parsed_Source) {
	parsed.root = null;
	release(*parsed.node_pool);
}

make_token_span :: inline (first: s64, one_past_last: s64) -> Token_Span {
	assert(first >= 0);
	assert(one_past_last >= first);
	return .{first=xx first, one_past_last=xx one_past_last};
}

token_at :: (parsed: *Parsed_Source, index: Token_Index) -> *Parser_Token #expand {
	return *parsed.tokens[xx index];
}

//QUESTION: do we need this proc at all?
previous_token :: inline (parsed: *Parsed_Source, index: Token_Index) -> *Parser_Token {
	raw_index := index.(s64);
	return ifx (raw_index > 0)
		then *parsed.tokens[raw_index - 1]
		else null;
}

//QUESTION: do we need this proc at all?
next_token :: inline (parsed: *Parsed_Source, index: Token_Index) -> *Parser_Token {
	raw_index := index.(s64);
	return ifx (raw_index >= 0 && raw_index + 1 < parsed.tokens.count)
		then *parsed.tokens[raw_index + 1]
		else null;
}


#scope_file

parseInit :: (source: string, rootParser: (*Parser) -> *Parser_Node) -> *Parsed_Source, Parser #expand {
	parser: Parser;
	parser.parsed = *materialize_tokens(source);
	set_allocators(*parser.parsed.node_pool);
	parser.parsed.root = rootParser(*parser);
	return parser.parsed, parser;
}

#scope_export

//FIXME: extract common startup code from these parse_* procs:
parse_expression :: (source: string) -> Parsed_Source {
	result, parser := parseInit(source, p => parse_binary(p));

	if !result.root && !result.diagnostics.count {
		add_expected_expression(*parser);
	} else if parser_peek(*parser).type != .END_OF_INPUT {
		add_unexpected_token(*parser);
	}

	return result;
}

//TODO: a lot less oneline ifs...

parse_declaration :: (source: string) -> Parsed_Source {
	result, parser := parseInit(source, parse_declaration_node);

	if !result.root && !result.diagnostics.count {
		add_expected_expression(*parser);
	}
	if parser_peek(*parser).type == #char ";"	parser_eat(*parser);
	if result.root	parse_declaration_notes(*parser, result.root);
	if result.root && parser_peek(*parser).type != .END_OF_INPUT {
		add_unexpected_token(*parser);
	}

	return result;
}

parse_block :: (source: string) -> Parsed_Source {
	result, parser := parseInit(source, p => parse_block_node(p).(*Parser_Node));

	if !result.root && !result.diagnostics.count {
		add_expected_expression(*parser);
	} else if parser_peek(*parser).type != .END_OF_INPUT {
		add_unexpected_token(*parser);
	}

	return result;
}

parse_declaration_block :: (source: string) -> Parsed_Source {
	result, parser := parseInit(
		source,
		(parser) => parse_block_node(parser, block_type=.DATA_DECLARATIONS).(*Parser_Node)
	);

	if !result.root && !result.diagnostics.count {
		add_expected_expression(*parser);
	} else if parser_peek(*parser).type != .END_OF_INPUT {
		add_unexpected_token(*parser);
	}

	return result;
}

parse_block_node :: (parser: *Parser, parent: *Parser_Block = null, block_type := Code_Block.block_type.IMPERATIVE) -> *Parser_Block {
	if parser_peek(parser).type != #char "{"	return null;


	first := parser.cursor;
	parser_eat(parser);
	result := new_parser_node(parser, Parser_Block);
	result.kind = .BLOCK;
	result.node_flags |= .IS_PARENTHESIZED;
	result.parent = parent;
	result.block_type = block_type;
	statements: [..] *Parser_Node;
	statements.allocator = parser_node_allocator(parser.parsed);
	while parser_peek(parser).type != #char "}" && parser_peek(parser).type != .END_OF_INPUT {
		guard := parser_progress_guard(parser);
		statement := ifx block_type == .DATA_DECLARATIONS then parse_declaration_node(parser) else parse_statement(parser, result);
		if statement {
			array_add(*statements, statement);
			finish_statement(parser, statement);
		} else {
			add_unexpected_token(parser);
			parser_synchronize(parser, .STATEMENT);
		}


		if !parser_ensure_progress(parser, guard)	break;
	}

	parser_expect(parser, #char "}");
	result.statements = statements;
	finish_node(parser, result, first);
	return result;
}

finish_statement :: (parser: *Parser, statement: *Parser_Node) {
	if parser_peek(parser).type == #char ";" {
		parser_eat(parser);
	} else if statement_requires_semicolon(statement) {
		parser_expect(parser, #char ";");
	}

	if statement.kind == .DECLARATION || statement.kind == .COMPOUND_DECLARATION {
		parse_declaration_notes(parser, statement);
	}
}

statement_requires_semicolon :: (statement: *Parser_Node) -> bool {
	if statement.kind == .IF	return (statement.(*Parser_If).if_flags & .IS_IFX) != 0;


	return statement.kind != .DIRECTIVE_SCOPE
		&& statement.kind != .DIRECTIVE_MODULE_PARAMETERS
		&& statement.kind != .DIRECTIVE_MODIFY
		&& statement.kind != .WHILE
		&& statement.kind != .FOR
		&& statement.kind != .DEFER
		&& statement.kind != .PUSH_CONTEXT
		&& statement.kind != .BLOCK;
}

parse_statement :: (parser: *Parser, parent: *Parser_Block = null) -> *Parser_Node {
	token := parser_peek(parser);
	if token.type == #char "#" {
		directive := parse_declaration_directive(parser);
		if directive	return directive;
	}


	if token.type == {
		case #char "{";
			return parse_block_node(parser, parent);
		case .KEYWORD_RETURN;
			return parse_return_statement(parser);
		case .KEYWORD_IF;
			return parse_if_statement(parser, parent, false);
		case .KEYWORD_WHILE;
			return parse_while_statement(parser, parent);
		case .KEYWORD_FOR;
			return parse_for_statement(parser, parent);
		case .KEYWORD_DEFER;
			return parse_defer_statement(parser, parent);
		case .KEYWORD_USING;
			return parse_using_statement(parser);
		case .KEYWORD_PUSH_CONTEXT;
			return parse_push_context_statement(parser, parent);

		case .KEYWORD_BREAK; #through;
		case .KEYWORD_CONTINUE; #through;
		case .KEYWORD_REMOVE;
			return parse_loop_control_statement(parser);
	}


	return ifx looks_like_declaration(parser)
		then parse_declaration_node(parser)
		else parse_binary(parser);
}

parse_statement_block :: (parser: *Parser, parent: *Parser_Block) -> *Parser_Block {
	if parser_peek(parser).type == #char "{"	return parse_block_node(parser, parent);


	first := parser.cursor;
	statement := parse_statement(parser, parent);
	if !statement {
		add_expected_expression(parser);
		return null;
	}


	finish_statement(parser, statement);

	statements: [..] *Parser_Node;
	statements.allocator = parser_node_allocator(parser.parsed);
	array_add(*statements, statement);
	result := new_parser_node(parser, Parser_Block);
	result.kind = .BLOCK;
	result.parent = parent;
	result.block_type = .IMPERATIVE;
	result.statements = statements;
	finish_node(parser, result, first);
	return result;
}

parse_while_statement :: (parser: *Parser, parent: *Parser_Block) -> *Parser_While {
	first := parser.cursor;
	parser_eat(parser);
	result := new_parser_node(parser, Parser_While);
	result.kind = .WHILE;
	result.condition = parse_condition(parser);
	if !result.condition	add_expected_expression(parser);
	result.block = parse_statement_block(parser, parent);
	if result.block		result.block.owning_statement = result;
	finish_node(parser, result, first);
	return result;
}

parse_condition :: (parser: *Parser) -> *Parser_Node {
	return ifx looks_like_declaration(parser) then parse_declaration_node(parser) else parse_binary(parser);
}

parse_if_statement :: (parser: *Parser, parent: *Parser_Block, is_ifx: bool) -> *Parser_If {
	first := parser.cursor;
	parser_eat(parser);
	result := new_parser_node(parser, Parser_If);
	result.kind = .IF;
	if is_ifx	result.if_flags |= .IS_IFX;

	if parser_peek(parser).type == #char "#" && parser_peek(parser, 1).type == .IDENT && parser_peek(parser, 1).ident_value.name == "complete" {
		parser_eat(parser);
		parser_eat(parser);
		result.if_flags |= .MARKED_AS_COMPLETE;
	}

	if !is_ifx && has_switch_case_block(parser) {
		result.condition = parse_binary(parser, 5);
		parser_expect(parser, .ISEQUAL);
		result.if_flags |= .IS_SWITCH_STATEMENT;
		result.then_block = parse_case_block(parser, parent, result);
		if result.then_block	result.then_block.owning_statement = result;
		finish_node(parser, result, first);
		return result;
	}


	result.condition = parse_condition(parser);
	if !result.condition	add_expected_expression(parser);
	if parser_peek(parser).type == .KEYWORD_THEN	parser_eat(parser);

	result.then_block = ifx is_ifx
		then parse_ifx_branch(parser, parent)
		else parse_statement_block(parser, parent);

	if result.then_block	result.then_block.owning_statement = result;

	if parser_peek(parser).type == .KEYWORD_ELSE {
		parser_eat(parser);
		result.else_block = ifx is_ifx then parse_ifx_branch(parser, parent) else parse_statement_block(parser, parent);
		if result.else_block	result.else_block.owning_statement = result;
	} else if is_ifx {
		parser_expect(parser, .KEYWORD_ELSE);
	}

	finish_node(parser, result, first);
	return result;
}

parse_ifx_branch :: (parser: *Parser, parent: *Parser_Block) -> *Parser_Block {
	if parser_peek(parser).type == #char "{"	return parse_block_node(parser, parent);


	first := parser.cursor;
	expression := parse_binary(parser);
	if !expression {
		add_expected_expression(parser);
		return null;
	}


	statements: [..] *Parser_Node;
	statements.allocator = parser_node_allocator(parser.parsed);
	array_add(*statements, expression);
	result := new_parser_node(parser, Parser_Block);
	result.kind = .BLOCK;
	result.parent = parent;
	result.block_type = .IMPERATIVE;
	result.statements = statements;
	finish_node(parser, result, first);
	return result;
}

has_switch_case_block :: (parser: *Parser) -> bool {
	lookahead: s64;
	parenthesis_depth: s64;
	bracket_depth: s64;
	while true {
		token := parser_peek(parser, lookahead);
		if token.type == {
			case .END_OF_INPUT; #through;
			case .KEYWORD_THEN;
				return false;

			case #char "(";
				parenthesis_depth += 1;
			case #char ")";
				parenthesis_depth -= 1;//TODO: handle negative depth

			case #char "[";
				bracket_depth += 1;
			case #char "]";
				bracket_depth -= 1;//TODO: handle negative depth

			case .ISEQUAL;
				if !parenthesis_depth && !bracket_depth		return parser_peek(parser, lookahead + 1).type == #char "{";

			case #char "{";
				if !parenthesis_depth && !bracket_depth		return false;
		}

		lookahead += 1;
	}


	return false;
}

parse_case_block :: (parser: *Parser, parent: *Parser_Block, owning_if: *Parser_If) -> *Parser_Block {
	if parser_peek(parser).type != #char "{"	return null;


	first := parser.cursor;
	parser_eat(parser);
	result := new_parser_node(parser, Parser_Block);
	result.kind = .BLOCK;
	result.node_flags |= .IS_PARENTHESIZED;
	result.parent = parent;
	result.block_type = .IMPERATIVE;
	result.owning_statement = owning_if;
	cases: [..] *Parser_Node;
	cases.allocator = parser_node_allocator(parser.parsed);

	while parser_peek(parser).type != #char "}" && parser_peek(parser).type != .END_OF_INPUT {
		case_first := parser.cursor;
		if !parser_expect(parser, .KEYWORD_CASE) {
			parser_synchronize(parser, .STATEMENT);
			if parser_peek(parser).type != .KEYWORD_CASE	break;


			continue;
		}


		case_node := new_parser_node(parser, Parser_Case);
		case_node.kind = .CASE;
		case_node.owning_if = owning_if;
		if parser_peek(parser).type != #char ";"	case_node.condition = parse_binary(parser);
		parser_expect(parser, #char ";");

		body_first := parser.cursor;
		body := new_parser_node(parser, Parser_Block);
		body.kind = .BLOCK;
		body.parent = result;
		body.block_type = .IMPERATIVE;
		body.owning_statement = case_node;
		statements: [..] *Parser_Node;
		statements.allocator = parser_node_allocator(parser.parsed);//TODO: cache parserPeek
		while parser_peek(parser).type != .KEYWORD_CASE && parser_peek(parser).type != #char "}" && parser_peek(parser).type != .END_OF_INPUT {
			if parser_peek(parser).type == #char "#" && parser_peek(parser, 1).type == .IDENT && parser_peek(parser, 1).ident_value.name == "through" {
				parser_eat(parser);
				parser_eat(parser);
				if parser_peek(parser).type == #char ";"	parser_eat(parser);
				case_node.marked_as_fallthrough = true;
				continue;
			}


			guard := parser_progress_guard(parser);
			statement := parse_statement(parser, body);
			if statement {
				array_add(*statements, statement);
				finish_statement(parser, statement);
			} else {
				add_unexpected_token(parser);
				parser_synchronize(parser, .STATEMENT);
			}

			if !parser_ensure_progress(parser, guard)	break;
		}

		body.statements = statements;

		if parser.cursor > body_first {
			finish_node(parser, body, body_first);
		} else {
			set_empty_node_location(parser, body, body_first);
		}

		case_node.then_block = body;
		finish_node(parser, case_node, case_first);
		array_add(*cases, case_node);
	}

	parser_expect(parser, #char "}");
	result.statements = cases;
	finish_node(parser, result, first);
	return result;
}

set_empty_node_location :: (parser: *Parser, node: *$T/Parser_Node, at: s64) {
	token := parser.parsed.tokens[at];
	node.l0 = token.l0;
	node.c0 = token.c0;
	node.l1 = token.l0;
	node.c1 = token.c0;
	#if ENABLE_TRIVIA {
		node.first_token = xx at;
		node.one_past_last_token = xx at;
	}
}

parse_for_statement :: (parser: *Parser, parent: *Parser_Block) -> *Parser_For {
	first := parser.cursor;
	parser_eat(parser);
	result := new_parser_node(parser, Parser_For);
	result.kind = .FOR;
	if parser_peek(parser).type == #char "<" {	//TODO: cache parserPeek; maybe case?
		parser_eat(parser);
		result.for_flags |= .REVERSE;
	} else if parser_peek(parser).type == #char "*" {
		parser_eat(parser);
		result.for_flags |= .POINTER;
	}

	if parser_peek(parser).type == .IDENT && (parser_peek(parser, 1).type == #char ":" || parser_peek(parser, 1).type == #char ",") {
		ident_first := parser.cursor;
		token := parser_eat(parser);
		result.ident_it = new_parser_node(parser, Parser_Ident);
		result.ident_it.kind = .IDENT;
		result.ident_it.name = token.ident_value.name;
		finish_node(parser, result.ident_it, ident_first);
		if parser_peek(parser).type == #char "," {
			parser_eat(parser);
			index_first := parser.cursor;
			index_token := parser_peek(parser);
			if index_token.type == .IDENT {
				parser_eat(parser);
				result.ident_it_index = new_parser_node(parser, Parser_Ident);
				result.ident_it_index.kind = .IDENT;
				result.ident_it_index.name = index_token.ident_value.name;
				finish_node(parser, result.ident_it_index, index_first);
			} else {
				add_expected_expression(parser);
			}
		}

		parser_expect(parser, #char ":");
	}

	result.iteration_expression = parse_binary(parser);
	if !result.iteration_expression		add_expected_expression(parser);
	if parser_peek(parser).type == .DOUBLE_DOT {
		parser_eat(parser);
		result.iteration_expression_right = parse_binary(parser);
		if !result.iteration_expression_right	add_expected_expression(parser);
	}

	result.block = parse_statement_block(parser, parent);
	if result.block		result.block.owning_statement = result;
	finish_node(parser, result, first);
	return result;
}

parse_defer_statement :: (parser: *Parser, parent: *Parser_Block) -> *Parser_Defer {
	first := parser.cursor;
	keyword := parser_eat(parser);
	result := new_parser_node(parser, Parser_Defer);
	result.kind = .DEFER;
	result.is_backticked = keyword.ident_is_backticked;
	result.block = parse_statement_block(parser, parent);
	if result.block		result.block.owning_statement = result;
	finish_node(parser, result, first);
	return result;
}

parse_using_statement :: (parser: *Parser) -> *Parser_Using {
	first := parser.cursor;
	parser_eat(parser);
	result := new_parser_node(parser, Parser_Using);
	result.kind = .USING;
	result.expression = ifx looks_like_declaration(parser) then parse_declaration_node(parser) else parse_binary(parser);
	if !result.expression	add_expected_expression(parser);
	finish_node(parser, result, first);
	return result;
}

parse_push_context_statement :: (parser: *Parser, parent: *Parser_Block) -> *Parser_Push_Context {
	first := parser.cursor;
	keyword := parser_eat(parser);
	result := new_parser_node(parser, Parser_Push_Context);
	result.kind = .PUSH_CONTEXT;
	if keyword.ident_is_backticked		result.push_context_flags |= .IS_BACKTICKED;

	if parser_peek(parser).type == #char "," {//TODO: cache parserPeek
		parser_eat(parser);
		modifier := parser_peek(parser);
		if modifier.type == .IDENT && modifier.ident_value.name == "defer_pop" {
			parser_eat(parser);
			result.push_context_flags |= .DEFER_POP;
		} else {
			add_unexpected_token(parser);
		}
	}

	if parser_peek(parser).type != #char "{"		result.to_push = parse_binary(parser);
	if !(result.push_context_flags & .DEFER_POP)	result.block = parse_statement_block(parser, parent);
	if result.block									result.block.owning_statement = result;
	finish_node(parser, result, first);
	return result;
}

looks_like_declaration :: (parser: *Parser) -> bool {
	lookahead: s64;
	if parser_peek(parser, lookahead).type == #char "$" || parser_peek(parser, lookahead).type == .DOUBLE_DOLLAR {	//TODO: cache parserPeek	//TODO: case after that?
		lookahead += 1;
	}

	if parser_peek(parser, lookahead).type != .IDENT	return false;


	lookahead += 1;
	while parser_peek(parser, lookahead).type == #char "," {
		lookahead += 1;
		if parser_peek(parser, lookahead).type != .IDENT	return false;


		lookahead += 1;
	}


	return parser_peek(parser, lookahead).type == #char ":";
}

parse_return_statement :: (parser: *Parser) -> *Parser_Return {
	first := parser.cursor;
	keyword := parser_eat(parser);
	arguments: [..] Parser_Argument;
	arguments.allocator = parser_node_allocator(parser.parsed);

	if keyword.ident_is_backticked {
		return_flags: type_of(Code_Return.return_flags) = .IS_BACKTICKED;
	}

	while parser_peek(parser).type != #char ";" && parser_peek(parser).type != #char "}" && parser_peek(parser).type != .END_OF_INPUT {
		expression := parse_binary(parser);
		if !expression {
			add_expected_expression(parser);
			break;
		}


		array_add(*arguments, .{expression=expression});
		if parser_peek(parser).type != #char ","	break;


		parser_eat(parser);
	}

	result := new_parser_node(parser, Parser_Return);
	result.kind = .RETURN;
	result.arguments_unsorted = arguments;
	if keyword.ident_is_backticked	result.return_flags |= .IS_BACKTICKED;
	finish_node(parser, result, first);
	return result;
}

parse_loop_control_statement :: (parser: *Parser) -> *Parser_Loop_Control {
	first := parser.cursor;
	keyword := parser_eat(parser);
	result := new_parser_node(parser, Parser_Loop_Control);
	result.kind = .LOOP_CONTROL;
	if keyword.type == {
		case .KEYWORD_BREAK;		result.control_type = .BREAK;
		case .KEYWORD_CONTINUE;		result.control_type = .CONTINUE;
		case .KEYWORD_REMOVE;		result.control_type = .REMOVE;
	}

	if parser_peek(parser).type == .IDENT {
		target_first := parser.cursor;
		target := parser_eat(parser);
		result.target_ident = new_parser_node(parser, Parser_Ident);
		result.target_ident.kind = .IDENT;
		result.target_ident.name = target.ident_value.name;
		finish_node(parser, result.target_ident, target_first);
	}

	finish_node(parser, result, first);
	return result;
}

parse_declaration_node :: (parser: *Parser) -> *Parser_Node {
	first := parser.cursor;
	if parser_peek(parser).type == #char "#" {
		return parse_declaration_directive(parser);
	}


	declaration_flags: type_of(Code_Declaration.flags);
	if parser_peek(parser).type == #char "$" {
		parser_eat(parser);
		declaration_flags |= .AUTO_VALUE_BAKE;
		declaration_flags |= .AUTO_VALUE_BAKE_IS_REQUIRED;
	} else if parser_peek(parser).type == .DOUBLE_DOLLAR {
		parser_eat(parser);
		declaration_flags |= .AUTO_VALUE_BAKE;
	}


	name_token := parser_peek(parser);
	if name_token.type != .IDENT	return null;


	parser_eat(parser);
	if parser_peek(parser).type == #char "," {
		arguments: [..] Parser_Comma_Separated_Argument;
		arguments.allocator = parser_node_allocator(parser.parsed);

		first_ident := new_parser_node(parser, Parser_Ident);
		first_ident.kind = .IDENT;
		first_ident.name = name_token.ident_value.name;
		if name_token.ident_is_backticked	first_ident.flags |= .HAS_SCOPE_MODIFIER;
		finish_node(parser, first_ident, first);
		array_add(*arguments, .{node=first_ident});

		while parser_peek(parser).type == #char "," {
			parser_eat(parser);
			argument_first := parser.cursor;
			argument_token := parser_peek(parser);
			if argument_token.type != .IDENT {
				add_expected_expression(parser);
				break;
			}


			parser_eat(parser);
			ident := new_parser_node(parser, Parser_Ident);
			ident.kind = .IDENT;
			ident.name = argument_token.ident_value.name;
			if argument_token.ident_is_backticked	ident.flags |= .HAS_SCOPE_MODIFIER;
			finish_node(parser, ident, argument_first);
			array_add(*arguments, .{node=ident});
		}

		parser_expect(parser, #char ":");
		result := new_parser_node(parser, Parser_Compound_Declaration);
		result.kind = .COMPOUND_DECLARATION;
		result.comma_separated_assignment.kind = .COMMA_SEPARATED_ARGUMENTS;
		result.comma_separated_assignment.arguments = arguments;
		result.comma_separated_assignment.first_token = xx first;
		result.comma_separated_assignment.one_past_last_token = xx parser.cursor;
		result.declaration_properties.kind = .DECLARATION;
		result.declaration_properties.flags = declaration_flags;
		parse_declaration_properties(parser, *result.declaration_properties);
		parse_declaration_metadata(parser, *result.declaration_properties, *result.alignment_expression);
		finish_node(parser, result, first);
		return result;
	}


	if parser_peek(parser).type != #char ":"	return null;


	parser_eat(parser);

	result := new_parser_node(parser, Parser_Declaration);
	result.kind = .DECLARATION;
	result.name = name_token.ident_value.name;
	result.flags = declaration_flags;
	if name_token.ident_is_backticked	result.flags |= .HAS_SCOPE_MODIFIER;

	parse_declaration_properties(parser, result);
	if result.expression && result.expression.kind == .PROCEDURE_HEADER {
		result.expression.(*Parser_Procedure_Header).name = result.name;
	}

	parse_declaration_metadata(parser, result, *result.alignment_expression);
	finish_node(parser, result, first);
	return result;
}

parse_declaration_properties :: (parser: *Parser, result: *Parser_Declaration) {
	if parser_peek(parser).type == #char ":" {	//TODO: cache parserPeek then case.
		parser_eat(parser);
		result.flags |= .IS_CONSTANT;
		result.expression = parse_declaration_expression(parser);
		if !result.expression	add_expected_expression(parser);
	} else if parser_peek(parser).type == #char "=" {
		parser_eat(parser);
		result.expression = parse_declaration_expression(parser);
		if !result.expression	add_expected_expression(parser);
	} else {
		result.type_inst = parse_type_instantiation(parser);
		if !result.type_inst {
			add_expected_expression(parser);
			return;
		}


		if parser_peek(parser).type == #char "=" {
			parser_eat(parser);
			result.expression = parse_declaration_expression(parser);
			if !result.expression	add_expected_expression(parser);
		}
	}


	if result.expression && result.expression.kind == .PLACEHOLDER {
		result.flags |= .IS_UNINITIALIZED;
		result.expression = null;
	}
}

parse_declaration_metadata :: (parser: *Parser, properties: *Parser_Declaration, alignment_expression: **Parser_Node) {
	while parser_peek(parser).type == #char "#" && parser_peek(parser, 1).type == .IDENT {
		directive := cast(string) parser_peek(parser, 1).ident_value.name;
		if directive == {
			case "align";
				parser_eat(parser);		//TODO: extract common?
				parser_eat(parser);
				alignment_expression.* = parse_binary(parser);
				if !alignment_expression.*	add_expected_expression(parser);

			case "no_reset";
				parser_eat(parser);
				parser_eat(parser);
				properties.flags |= .NO_RESET;

			case "uninitialized";
				parser_eat(parser);
				parser_eat(parser);
				properties.flags |= .IS_UNINITIALIZED;

			case "elsewhere";
				parser_eat(parser);
				parser_eat(parser);
				properties.flags |= .ELSEWHERE;

			case "program_export";
				parser_eat(parser);
				parser_eat(parser);
				properties.flags |= .PROGRAM_EXPORT;
				if parser_peek(parser).type == .STRING {
					properties.program_export_name = parser_eat(parser).string_value;
				}

			case;
				break;
		}
	}
}

parse_declaration_notes :: (parser: *Parser, declaration: *Parser_Node) {
	notes: [..] *Parser_Note;
	notes.allocator = parser_node_allocator(parser.parsed);
	while parser_peek(parser).type == .NOTE {
		first := parser.cursor;
		token := parser_eat(parser);
		note := new_parser_node(parser, Parser_Note);
		note.kind = .NOTE;
		note.text = token.ident_value.name;
		if note.text.count && note.text[note.text.count - 1] == 0	note.text.count -= 1;
		finish_node(parser, note, first);
		array_add(*notes, note);
	}

	if !notes.count		return;


	if declaration.kind == .DECLARATION {
		declaration.(*Parser_Declaration).notes = notes;
	} else if declaration.kind == .COMPOUND_DECLARATION {
		declaration.(*Parser_Compound_Declaration).notes = notes;
	}

	finish_node(parser, declaration, declaration.first_token.(s64));
}

parse_declaration_expression :: (parser: *Parser) -> *Parser_Node {
	first := parser.cursor;
	first_expression := parse_binary(parser);
	if !first_expression || parser_peek(parser).type != #char ","	return first_expression;


	arguments: [..] Parser_Comma_Separated_Argument;
	arguments.allocator = parser_node_allocator(parser.parsed);
	array_add(*arguments, .{node=first_expression});
	while parser_peek(parser).type == #char "," {
		parser_eat(parser);
		expression := parse_binary(parser);
		if !expression {
			add_expected_expression(parser);
			break;
		}


		array_add(*arguments, .{node=expression});
	}

	result := new_parser_node(parser, Parser_Comma_Separated_Arguments);
	result.kind = .COMMA_SEPARATED_ARGUMENTS;
	result.arguments = arguments;
	finish_node(parser, result, first);
	return result;
}

parse_type_instantiation :: (parser: *Parser) -> *Parser_Type_Instantiation {
	first := parser.cursor;
	if parser_peek(parser).type == .DOUBLE_DOT {	//TODO: cache parserPeek then case
		parser_eat(parser);
		element_type := parse_type_instantiation(parser);
		if !element_type {
			add_expected_expression(parser);
			return null;
		}


		result := new_parser_node(parser, Parser_Type_Instantiation);
		result.kind = .TYPE_INSTANTIATION;
		result.inst_flags |= .VARARGS;
		result.inst_flags |= .ARRAY_VIEW;
		result.array_element_type = element_type;
		finish_node(parser, result, first);
		return result;
	}


	if parser_peek(parser).type == #char "$" {
		parser_eat(parser);
		name_token := parser_peek(parser);
		if name_token.type != .IDENT {
			add_expected_expression(parser);
			return null;
		}


		parser_eat(parser);
		ident := new_parser_node(parser, Parser_Ident);
		ident.kind = .IDENT;
		ident.name = name_token.ident_value.name;
		ident.flags |= .DEFINES_POLYMORPH_VARIABLE;
		finish_node(parser, ident, first);

		result := make_type_instantiation(parser, ident);
		if parser_peek(parser).type == #char "/" {
			parser_eat(parser);
			if parser_peek(parser).type == .KEYWORD_INTERFACE {
				parser_eat(parser);
				result.inst_flags |= .INTERFACE;
			}
			result.must_implement = parse_postfix(parser);
			if !result.must_implement	add_expected_expression(parser);
			finish_node(parser, result, first);
		}

		return result;
	}


	if parser_peek(parser).type == #char "#" && parser_peek(parser, 1).type == .IDENT && parser_peek(parser, 1).ident_value.name == "type" {
		parser_eat(parser);
		parser_eat(parser);
		result := new_parser_node(parser, Parser_Type_Instantiation);
		result.kind = .TYPE_INSTANTIATION;
		result.inst_flags |= .TYPE_DIRECTIVE;
		if parser_peek(parser).type == #char "," {
			parser_eat(parser);
			modifier := parser_peek(parser);
			if modifier.type == .IDENT && modifier.ident_value.name == "distinct" {//TODO: split & nest common condition
				result.inst_flags |= .TYPE_DIRECTIVE_DISTINCT;
				parser_eat(parser);
			} else if modifier.type == .IDENT && modifier.ident_value.name == "isa" {
				result.inst_flags |= .TYPE_DIRECTIVE_ISA;
				parser_eat(parser);
			} else {
				add_unexpected_token(parser);
			}
		}

		result.type_directive_target = parse_type_instantiation(parser);
		if !result.type_directive_target	add_expected_expression(parser);
		finish_node(parser, result, first);
		return result;
	}


	if parser_peek(parser).type == #char "*" {
		parser_eat(parser);
		pointee := parse_type_instantiation(parser);
		if !pointee {
			add_expected_expression(parser);
			return null;
		}


		result := new_parser_node(parser, Parser_Type_Instantiation);
		result.kind = .TYPE_INSTANTIATION;
		result.pointer_to = pointee;
		finish_node(parser, result, first);
		return result;
	}


	if parser_peek(parser).type == #char "[" {
		parser_eat(parser);
		result := new_parser_node(parser, Parser_Type_Instantiation);
		result.kind = .TYPE_INSTANTIATION;
		if parser_peek(parser).type == #char "]" {//TODO: cache parserPeek then case
			result.inst_flags |= .ARRAY_VIEW;
		} else if parser_peek(parser).type == .DOUBLE_DOT {
			parser_eat(parser);
			result.inst_flags |= .RESIZABLE;
		} else {
			result.array_dimension = parse_binary(parser);
			if !result.array_dimension	add_expected_expression(parser);
		}

		parser_expect(parser, #char "]");
		result.array_element_type = parse_type_instantiation(parser);
		if !result.array_element_type	add_expected_expression(parser);
		finish_node(parser, result, first);
		return result;
	}


	if parser_peek(parser).type == #char "(" {
		header := parse_procedure_type_header(parser);
		if !header	return null;


		header.procedure_flags |= .TYPE_ONLY;

		result := new_parser_node(parser, Parser_Type_Instantiation);
		result.kind = .TYPE_INSTANTIATION;
		result.inst_flags |= .TYPE_OF_PROCEDURE;
		result.type_valued_expression = header;
		finish_node(parser, result, first);
		return result;
	}


	type_expression := parse_postfix(parser);
	if !type_expression		return null;
	return make_type_instantiation(parser, type_expression);
}

parse_procedure_type_header :: (parser: *Parser, parse_body := false) -> *Parser_Procedure_Header {
	first := parser.cursor;
	quick := procedure_header_terminator(parser) == .QUICK_LAMBDA;
	parser_expect(parser, #char "(");
	arguments: [..] *Parser_Declaration;
	arguments.allocator = parser_node_allocator(parser.parsed);
	parameter_usings: [..] *Parser_Using;
	parameter_usings.allocator = parser_node_allocator(parser.parsed);
	while parser_peek(parser).type != #char ")" && parser_peek(parser).type != .END_OF_INPUT {
		marked_using := parser_peek(parser).type == .KEYWORD_USING;
		if marked_using		parser_eat(parser);
		argument: *Parser_Declaration;
		//TODO: cache parserPeek
		if quick && parser_peek(parser).type == .IDENT && parser_peek(parser, 1).type != #char ":" {
			argument_first := parser.cursor;
			name := parser_eat(parser);
			argument = new_parser_node(parser, Parser_Declaration);
			argument.kind = .DECLARATION;
			argument.name = name.ident_value.name;
			finish_node(parser, argument, argument_first);
		} else {
			argument_node := parse_declaration_node(parser);
			if !argument_node || argument_node.kind != .DECLARATION {
				add_expected_expression(parser);
				break;
			}


			argument = argument_node.(*Parser_Declaration);
		}


		array_add(*arguments, argument);
		if marked_using {
			using_node := new_parser_node(parser, Parser_Using);
			using_node.kind = .USING;
			using_node.expression = argument;
			array_add(*parameter_usings, using_node);
		}

		if parser_peek(parser).type != #char ","	break;


		parser_eat(parser);
	}

	parser_expect(parser, #char ")");

	returns: [..] *Parser_Declaration;
	returns.allocator = parser_node_allocator(parser.parsed);
	if parser_peek(parser).type == .RIGHT_ARROW {
		parser_eat(parser);
		parenthesized := parser_peek(parser).type == #char "(";
		if parenthesized	parser_eat(parser);
		while true {
			return_first := parser.cursor;
			declaration: *Parser_Declaration;//TODO: cache parserPeek
			if parser_peek(parser).type == .IDENT && parser_peek(parser, 1).type == #char ":" {
				declaration = parse_declaration_node(parser).(*Parser_Declaration);
			} else {
				return_type := parse_type_instantiation(parser);
				if !return_type {
					add_expected_expression(parser);
					break;
				}


				declaration = new_parser_node(parser, Parser_Declaration);
				declaration.kind = .DECLARATION;
				declaration.type_inst = return_type;
				finish_node(parser, declaration, return_first);
			}


			array_add(*returns, declaration);
			if parser_peek(parser).type != #char ","	break;


			parser_eat(parser);
		}

		if parenthesized	parser_expect(parser, #char ")");
	}

	result := new_parser_node(parser, Parser_Procedure_Header);
	result.kind = .PROCEDURE_HEADER;
	result.arguments = arguments;
	result.returns = returns;
	result.parameter_usings = parameter_usings;
	if quick	result.procedure_flags |= .QUICK;
	for arguments {
		if type_instantiation_is_polymorphic(it.type_inst) {
			result.procedure_flags |= .POLYMORPHIC;
			break;
		}
	}

	if !(result.procedure_flags & .POLYMORPHIC) {
		for returns {
			if type_instantiation_is_polymorphic(it.type_inst) {
				result.procedure_flags |= .POLYMORPHIC;
				break;
			}
		}
	}

	parse_procedure_flags(parser, result);
	modify_directives: [..] *Parser_Directive_Modify;
	modify_directives.allocator = parser_node_allocator(parser.parsed);
	//TODO: if possible cache parserPeek.
	while parser_peek(parser).type == #char "#" && parser_peek(parser, 1).type == .IDENT && parser_peek(parser, 1).ident_value.name == "modify" {
		modify := parse_declaration_directive(parser);
		if !modify || modify.kind != .DIRECTIVE_MODIFY	break;


		array_add(*modify_directives, modify.(*Parser_Directive_Modify));
	}

	result.modify_directives = modify_directives;
	if parse_body	parse_procedure_body(parser, result, first);
	if !result.body_or_null && !(result.procedure_flags & .QUICK)	result.procedure_flags |= .TYPE_ONLY;

	finish_node(parser, result, first);
	return result;
}

parse_arrow_procedure_header :: (parser: *Parser, first: s64) -> *Parser_Procedure_Header {
	parser_expect(parser, .RIGHT_ARROW);
	returns: [..] *Parser_Declaration;
	returns.allocator = parser_node_allocator(parser.parsed);
	parenthesized := parser_peek(parser).type == #char "(";
	if parenthesized	parser_eat(parser);
	while true {
		return_first := parser.cursor;
		declaration: *Parser_Declaration;
		//TODO: cache parserPeek
		if parser_peek(parser).type == .IDENT && parser_peek(parser, 1).type == #char ":" {
			declaration_node := parse_declaration_node(parser);
			if declaration_node && declaration_node.kind == .DECLARATION	declaration = declaration_node.(*Parser_Declaration);
		} else {
			return_type := parse_type_instantiation(parser);
			if return_type {
				declaration = new_parser_node(parser, Parser_Declaration);
				declaration.kind = .DECLARATION;
				declaration.type_inst = return_type;
				finish_node(parser, declaration, return_first);
			}
		}

		if !declaration {
			add_expected_expression(parser);
			break;
		}


		array_add(*returns, declaration);
		if parser_peek(parser).type != #char ","	break;


		parser_eat(parser);
	}

	if parenthesized	parser_expect(parser, #char ")");

	result := new_parser_node(parser, Parser_Procedure_Header);
	result.kind = .PROCEDURE_HEADER;
	result.returns = returns;
	parse_procedure_flags(parser, result);
	parse_procedure_body(parser, result, first);
	if !result.body_or_null		result.procedure_flags |= .TYPE_ONLY;
	finish_node(parser, result, first);
	return result;
}

procedure_header_terminator :: (parser: *Parser) -> Token_Type {
	if parser_peek(parser).type != #char "("	return xx 0;


	depth := 0;
	index := parser.cursor;
	while index < parser.parsed.tokens.count {
		type := parser.parsed.tokens[index].type;
		if type == #char "(" {
			depth += 1;
		} else if type == #char ")" {
			depth -= 1;
			if depth == 0 {
				return ifx index + 1 >= parser.parsed.tokens.count
					then .END_OF_INPUT
					else parser.parsed.tokens[index + 1].type;
			}
		} else if type == .END_OF_INPUT {
			break;
		}


		index += 1;
	}


	return .END_OF_INPUT;
}

looks_like_procedure_header :: (parser: *Parser) -> bool {
	terminator := procedure_header_terminator(parser);
	return parser_peek(parser, 1).type == #char ")"
		|| terminator == .RIGHT_ARROW
		|| terminator == .QUICK_LAMBDA
		|| terminator == #char "{"
		|| terminator == #char "#"
		|| terminator == .KEYWORD_INLINE
		|| terminator == .KEYWORD_NO_INLINE;
}

parse_procedure_flags :: (parser: *Parser, result: *Parser_Procedure_Header) {
	while true {
		//TODO: cache parserPeek when the same args
		if parser_peek(parser).type == .KEYWORD_INLINE {
			parser_eat(parser);
			result.procedure_flags |= .SYNTACTICALLY_MARKED_AS_INLINE_YES;
			continue;
		}


		if parser_peek(parser).type == .KEYWORD_NO_INLINE {
			parser_eat(parser);
			result.procedure_flags |= .SYNTACTICALLY_MARKED_AS_INLINE_NO;
			continue;
		}


		if parser_peek(parser).type != #char "#" || parser_peek(parser, 1).type != .IDENT	break;


		name := cast(string) parser_peek(parser, 1).ident_value.name;
		matched := true;
		if name == {
			case "expand";
				result.procedure_flags |= .MACRO;
			case "compile_time";
				result.procedure_flags |= .COMPILE_TIME_ONLY;
				result.procedure_flags |= .SYNTACTICALLY_MARKED_AS_COMPILE_TIME;
			case "compiler";
				result.procedure_flags |= .SYNTACTICALLY_MARKED_AS_COMPILER;
			case "no_context";
				result.procedure_flags |= .SYNTACTICALLY_MARKED_AS_NO_CONTEXT;
			case "c_call";
				result.procedure_flags |= .C_CALL;
			case "intrinsic";
				result.procedure_flags |= .INTRINSIC;
			case "no_debug";
				result.procedure_flags |= .NO_DEBUG;

			case "elsewhere"; #through;
			case "foreign";
				result.procedure_flags |= .ELSEWHERE;

			case "deprecated";
				result.procedure_flags |= .DEPRECATED;
			case "entry_point";
				result.procedure_flags |= .ENTRY_POINT;
			case "entry_point_hook";
				result.procedure_flags |= .ENTRY_POINT_HOOK;
			case "symmetric";
				result.procedure_flags |= .SYMMETRIC;
			case "no_call";
				result.procedure_flags |= .NO_CALL;
			case;
				matched = false;
		}

		if !matched		break;


		parser_eat(parser);
		parser_eat(parser);
		if name == "deprecated" && parser_peek(parser).type == .STRING {
			result.deprecation_string = parser_eat(parser).string_value;
		} else if name == "foreign" {
			if parser_peek(parser).type == .IDENT {
				library_first := parser.cursor;
				library := parser_eat(parser);
				result.library_identifier = new_parser_node(parser, Parser_Ident);
				result.library_identifier.kind = .IDENT;
				result.library_identifier.name = library.ident_value.name;
				finish_node(parser, result.library_identifier, library_first);
			}

			if parser_peek(parser).type == .STRING {
				result.foreign_function_name = parser_eat(parser).string_value;
			}
		}
	}
}

parse_procedure_body :: (parser: *Parser, header: *Parser_Procedure_Header, first: s64) {
	body := new_parser_node(parser, Parser_Procedure_Body);
	body.kind = .PROCEDURE_BODY;
	body.header = header;
	if parser_peek(parser).type == .QUICK_LAMBDA {//TODO: cache parserPeek
		parser_eat(parser);
		header.procedure_flags |= .QUICK;
		if parser_peek(parser).type == #char "{" {
			header.procedure_flags |= .QUICK_IN_BLOCK_FORM;
			body.block = parse_block_node(parser);
		} else {
			expression := parse_binary(parser);
			if !expression	add_expected_expression(parser);


			return_node := new_parser_node(parser, Parser_Return);
			return_node.kind = .RETURN;
			return_node.return_flags |= .AUTO_INSERTED_FOR_QUICK_LAMBDA;
			if expression {
				arguments: [..] Parser_Argument;
				arguments.allocator = parser_node_allocator(parser.parsed);
				array_add(*arguments, .{expression=expression});
				return_node.arguments_unsorted = arguments;
			}
			finish_node(parser, return_node, first);


			statements: [..] *Parser_Node;
			statements.allocator = parser_node_allocator(parser.parsed);
			array_add(*statements, return_node);
			body.block = new_parser_node(parser, Parser_Block);
			body.block.kind = .BLOCK;
			body.block.block_type = .IMPERATIVE;
			body.block.statements = statements;
			finish_node(parser, body.block, first);
		}
	} else if parser_peek(parser).type == #char "{" {
		body.block = parse_block_node(parser);
	} else {
		return;
	}


	body.block.owning_statement = body;
	header.body_or_null = body;
	finish_node(parser, body, first);
}

type_instantiation_is_polymorphic :: (type_inst: *Parser_Type_Instantiation) -> bool {
	if !type_inst	return false;


	if type_inst.type_valued_expression && type_inst.type_valued_expression.kind == .IDENT {
		return (type_inst.type_valued_expression.(*Parser_Ident).flags & .DEFINES_POLYMORPH_VARIABLE) != 0;
	}


	return type_instantiation_is_polymorphic(type_inst.pointer_to)
		|| type_instantiation_is_polymorphic(type_inst.array_element_type)
		|| type_instantiation_is_polymorphic(type_inst.type_directive_target);
}

parse_aggregate_definition :: (parser: *Parser) -> *Parser_Node {
	first := parser.cursor;
	keyword := parser_eat(parser);
	if keyword.type == .KEYWORD_ENUM || keyword.type == .KEYWORD_ENUM_FLAGS {
		result := new_parser_node(parser, Parser_Enum);
		result.kind = .ENUM;
		result.is_flags = keyword.type == .KEYWORD_ENUM_FLAGS;
		//TODO: cache parserPeek
		if parser_peek(parser).type != #char "#" && parser_peek(parser).type != #char "{" {
			result.internal_type_inst = parse_type_instantiation(parser);
			if !result.internal_type_inst	add_expected_expression(parser);
		}


		while parser_peek(parser).type == #char "#" && parser_peek(parser, 1).type == .IDENT {
			name := parser_peek(parser, 1).ident_value.name;
			if name != "complete" && name != "specified"	break;


			parser_eat(parser);
			parser_eat(parser);
			if name == "complete" {
				result.marked_as_complete = true;
			} else {
				result.marked_as_specified = true;
			}
		}

		result.block = parse_aggregate_block(parser, true);
		if !result.block	parser_expect(parser, #char "{");
		finish_node(parser, result, first);
		return result;
	}


	result := new_parser_node(parser, Parser_Struct);
	result.kind = .STRUCT;
	if keyword.type == .KEYWORD_UNION	result.textual_flags |= .UNION;
	parse_struct_modifiers(parser, result);
	if parser_peek(parser).type == #char "(" {
		result.arguments_block = parse_aggregate_parameter_block(parser);
	}

	parse_struct_modifiers(parser, result);
	modify_directives: [..] *Parser_Directive_Modify;
	modify_directives.allocator = parser_node_allocator(parser.parsed);
	while parser_peek(parser).type == #char "#" && parser_peek(parser, 1).type == .IDENT && parser_peek(parser, 1).ident_value.name == "modify" {
		modify := parse_declaration_directive(parser);
		if !modify || modify.kind != .DIRECTIVE_MODIFY	break;


		array_add(*modify_directives, modify.(*Parser_Directive_Modify));
	}

	result.modify_directives = modify_directives;
	result.block = parse_aggregate_block(parser, false);
	if result.block {
		result.block.belongs_to_struct = result;
	} else {
		parser_expect(parser, #char "{");
	}

	parse_struct_modifiers(parser, result);
	finish_node(parser, result, first);
	return result;
}

parse_aggregate_parameter_block :: (parser: *Parser) -> *Parser_Block {
	first := parser.cursor;
	parser_expect(parser, #char "(");
	statements: [..] *Parser_Node;
	statements.allocator = parser_node_allocator(parser.parsed);
	while parser_peek(parser).type != #char ")" && parser_peek(parser).type != .END_OF_INPUT {
		parameter := parse_declaration_node(parser);
		if !parameter {
			add_expected_expression(parser);
			parser_synchronize(parser, .DECLARATION);
			break;
		}


		array_add(*statements, parameter);
		if parser_peek(parser).type != #char ","	break;


		parser_eat(parser);
	}

	parser_expect(parser, #char ")");

	result := new_parser_node(parser, Parser_Block);
	result.kind = .BLOCK;
	result.block_type = .STRUCT_ARGUMENTS;
	result.node_flags |= .IS_PARENTHESIZED;
	result.statements = statements;
	finish_node(parser, result, first);
	return result;
}

parse_aggregate_block :: (parser: *Parser, enum_members: bool) -> *Parser_Block {
	if parser_peek(parser).type != #char "{"	return null;


	first := parser.cursor;
	parser_eat(parser);
	result := new_parser_node(parser, Parser_Block);
	result.kind = .BLOCK;
	result.block_type = .DATA_DECLARATIONS;
	result.node_flags |= .IS_PARENTHESIZED;
	statements: [..] *Parser_Node;
	statements.allocator = parser_node_allocator(parser.parsed);
	//TODO: cache parserPeek
	while parser_peek(parser).type != #char "}" && parser_peek(parser).type != .END_OF_INPUT {
		guard := parser_progress_guard(parser);
		member: *Parser_Node;
		if enum_members && parser_peek(parser).type == .IDENT && parser_peek(parser, 1).type == #char ";" {
			member_first := parser.cursor;
			token := parser_eat(parser);
			ident := new_parser_node(parser, Parser_Ident);
			ident.kind = .IDENT;
			ident.name = token.ident_value.name;
			finish_node(parser, ident, member_first);
			member = ident;
		} else {
			member = parse_declaration_node(parser);
		}

		if member {
			array_add(*statements, member);
			finish_statement(parser, member);
		} else {
			add_unexpected_token(parser);
			parser_synchronize(parser, .DECLARATION);
		}

		if !parser_ensure_progress(parser, guard)	break;
	}

	parser_expect(parser, #char "}");
	result.statements = statements;
	finish_node(parser, result, first);
	return result;
}

parse_struct_modifiers :: (parser: *Parser, result: *Parser_Struct) {
	while parser_peek(parser).type == #char "#" && parser_peek(parser, 1).type == .IDENT {
		name := cast(string) parser_peek(parser, 1).ident_value.name;
		matched := true;
		if name == {
			case "foreign";
				result.textual_flags |= .FOREIGN;
			case "no_padding";
				result.textual_flags |= .NO_PADDING;
			case "type_info_none";
				result.textual_flags |= .TYPE_INFO_NONE;
			case "type_info_no_size_complaint";
				result.textual_flags |= .TYPE_INFO_NO_SIZE_COMPLAINT;
			case "type_info_procedures_are_void_pointers";
				result.textual_flags |= .TYPE_INFO_PROCEDURES_ARE_VOID_POINTERS;

			case "align";
				parser_eat(parser);
				parser_eat(parser);
				if parser_peek(parser).type == .NUMBER {
					result.alignment = xx parser_eat(parser).integer_value;
				} else {
					add_expected_expression(parser);
				}
				continue;

			case;
				matched = false;
		}


		if !matched		break;


		parser_eat(parser);
		parser_eat(parser);
	}
}

parse_declaration_directive :: (parser: *Parser) -> *Parser_Node {
	if parser_peek(parser).type != #char "#" || parser_peek(parser, 1).type != .IDENT	return null;


	first := parser.cursor;
	//TODO: cache parserPeek(1)
	name := cast(string) parser_peek(parser, 1).ident_value.name;
	if name == {
		case "scope_export"; #through;
		case "scope_file";
			parser_eat(parser);
			parser_eat(parser);
			result := new_parser_node(parser, Parser_Directive_Scope);
			result.kind = .DIRECTIVE_SCOPE;
			result.scope_type = ifx name == "scope_export"
				then .EXPORT
				else .FILE;

			finish_node(parser, result, first);
			return result;

		case "through";
			parser_eat(parser);
			parser_eat(parser);
			result := new_parser_node(parser, Parser_Directive_Through);
			result.kind = .DIRECTIVE_THROUGH;
			finish_node(parser, result, first);
			return result;

		case "add_context";
			parser_eat(parser);
			parser_eat(parser);
			result := new_parser_node(parser, Parser_Directive_Add_Context);
			result.kind = .DIRECTIVE_ADD_CONTEXT;
			result.expression = parse_declaration_node(parser);
			if !result.expression	add_expected_expression(parser);
			finish_node(parser, result, first);
			return result;

		case "overlay";
			parser_eat(parser);
			parser_eat(parser);
			result := new_parser_node(parser, Parser_Directive_Overlay);
			result.kind = .DIRECTIVE_OVERLAY;
			parser_expect(parser, #char "(");
			result.target_expression = parse_binary(parser);
			if !result.target_expression	add_expected_expression(parser);
			parser_expect(parser, #char ")");

			result.declaration_or_using = ifx parser_peek(parser).type == .KEYWORD_USING
				then parse_using_statement(parser).(*Parser_Node)
				else parse_declaration_node(parser);

			if !result.declaration_or_using		add_expected_expression(parser);
			finish_node(parser, result, first);
			return result;

		case "modify";
			parser_eat(parser);
			parser_eat(parser);
			result := new_parser_node(parser, Parser_Directive_Modify);
			result.kind = .DIRECTIVE_MODIFY;
			result.block = parse_block_node(parser);
			if !result.block	parser_expect(parser, #char "{");
			finish_node(parser, result, first);
			return result;

		case "module_parameters";
			parser_eat(parser);
			parser_eat(parser);
			result := new_parser_node(parser, Parser_Directive_Module_Parameters);
			result.kind = .DIRECTIVE_MODULE_PARAMETERS;
			if parser_peek(parser).type == {	//TODO: cache parserPeek
				case #char "(";
					result.module_parameters = parse_procedure_type_header(parser);
					if parser_peek(parser).type == {
						case #char "(";
							result.program_parameters = parse_procedure_type_header(parser);
							if parser_peek(parser).type == #char "{"	result.common_code = parse_block_node(parser);
						case #char "{";
							result.common_code = parse_block_node(parser);
					}

				case #char "{";
					result.common_code = parse_block_node(parser);
			}

			finish_node(parser, result, first);
			return result;

		case;
			return parse_expression_directive(parser, first, name);
	}
}

parser_peek :: inline (parser: *Parser, lookahead: s64 = 0) -> *Parser_Token {
	return *parser.parsed.tokens[parser.cursor + lookahead];
}

parser_eat :: inline (parser: *Parser) -> *Parser_Token {
	result := parser_peek(parser);
	if result.type != .END_OF_INPUT {
		parser.cursor += 1;
	}

	return result;
}

parser_expect :: inline (parser: *Parser, expected: Token_Type) -> bool {
	actual := parser_peek(parser);
	if actual.type == expected {
		parser_eat(parser);
		return true;
	}


	add_missing_token(parser, expected);
	return false;
}

parser_checkpoint :: inline (parser: *Parser) -> Parser_Checkpoint {
	return xx parser.cursor;
}

parser_restore :: inline (parser: *Parser, checkpoint: Parser_Checkpoint) {
	cursor := checkpoint.(s64);
	assert(cursor >= 0 && cursor < parser.parsed.tokens.count);
	parser.cursor = cursor;
}

parser_progress_guard :: inline (parser: *Parser) -> Parser_Progress_Guard {
	return .{cursor=parser.cursor};
}

parser_ensure_progress :: inline (parser: *Parser, guard: Parser_Progress_Guard) -> bool {
	assert(parser.cursor >= guard.cursor);
	if parser.cursor > guard.cursor					return true;
	if parser_peek(parser).type == .END_OF_INPUT	return false;


	parser_eat(parser);
	return true;
}

is_synchronization_point :: (token_type: Token_Type, synchronization_context: Synchronization_Context) -> bool {
	if token_type == .END_OF_INPUT	return true;


	if synchronization_context == {
		case .EXPRESSION;
			if token_type == {
				case #char ","; #through;
				case #char ";"; #through;
				case #char ")"; #through;
				case #char "]"; #through;
				case #char "}";
					return true;
			}

		case .STATEMENT;
			if token_type == {
				case #char ";"; #through;
				case #char "}"; #through;
				case .IDENT; #through;
				case .KEYWORD_IF; #through;
				case .KEYWORD_IFX; #through;
				case .KEYWORD_FOR; #through;
				case .KEYWORD_WHILE; #through;
				case .KEYWORD_RETURN; #through;
				case .KEYWORD_DEFER; #through;
				case .KEYWORD_USING; #through;
				case .KEYWORD_PUSH_CONTEXT; #through;
				case .KEYWORD_BREAK; #through;
				case .KEYWORD_CONTINUE; #through;
				case .KEYWORD_REMOVE; #through;
				case .KEYWORD_CASE; #through;
				case .KEYWORD_ELSE;
					return true;
			}

		case .DECLARATION;
			if token_type == {
				case #char ";"; #through;
				case #char "}"; #through;
				case .IDENT; #through;
				case .NOTE; #through;
				case .KEYWORD_USING; #through;
				case .KEYWORD_STRUCT; #through;
				case .KEYWORD_UNION; #through;
				case .KEYWORD_ENUM; #through;
				case .KEYWORD_ENUM_FLAGS; #through;
				case .KEYWORD_INTERFACE; #through;
				case .KEYWORD_OPERATOR;
					return true;
			}

		case .BLOCK;
			return token_type == #char "}";
	}


	return false;
}

parser_synchronize :: (parser: *Parser, synchronization_context: Synchronization_Context) -> Token_Span {
	first := parser.cursor;
	while !is_synchronization_point(parser_peek(parser).type, synchronization_context) {
		guard := parser_progress_guard(parser);
		if !parser_ensure_progress(parser, guard)	break;
	}

	return make_token_span(first, parser.cursor);
}

parse_binary :: (parser: *Parser, minimum_precedence: s32 = 1) -> *Parser_Node {
	first := parser.cursor;
	left := parse_prefix(parser);
	if !left	return null;


	while true {
		is_binary, operator_type, precedence, right_associative := binary_operator_info(parser_peek(parser).type);
		if !is_binary || precedence < minimum_precedence	break;


		operator_index := parser.cursor;
		parser_eat(parser);
		diagnostic_count := parser.parsed.diagnostics.count;
		next_precedence := precedence + xx !right_associative;
		right := parse_binary(parser, next_precedence);
		if !right && parser.parsed.diagnostics.count == diagnostic_count {
			add_expected_expression_at(
				parser,
				make_token_span(operator_index, operator_index + 1),
				"Unable to parse an expression to the right of this binary operator."
			);
		}

		result := new_parser_node(parser, Parser_Binary_Operator);
		result.kind = .BINARY_OPERATOR;
		result.operator_type = operator_type;
		result.left = left;
		result.right = right;
		finish_node(parser, result, first);
		left = result;

		if !right	break;
	}

	return left;
}

/*
	See print_precedence.jai for how operator precedence is calculated.
*/
binary_operator_info :: (token_type: Token_Type) -> (bool, Operator_Type, s32, bool) {
	operator_type: Operator_Type;
	precedence: s32;

	if token_type == {
		case .SHIFT_LEFT;			operator_type = .SHIFT_LEFT;			precedence = 8;
		case .SHIFT_RIGHT;			operator_type = .SHIFT_RIGHT;			precedence = 8;
		case .ROTATE_LEFT;			operator_type = .ROTATE_LEFT;			precedence = 8;
		case .ROTATE_RIGHT;			operator_type = .ROTATE_RIGHT;			precedence = 8;
		case #char "&"; #through;
		case #char "|"; #through;
		case #char "^";
			operator_type = token_type.(Operator_Type);						precedence = 8;

		case #char "*"; #through;
		case #char "/";
			operator_type = token_type.(Operator_Type);						precedence = 7;

		case #char "%";
			operator_type = token_type.(Operator_Type);						precedence = 6;

		case #char "+"; #through;
		case #char "-";
			operator_type = token_type.(Operator_Type);						precedence = 5;

		case .ISEQUAL;				operator_type = .IS_EQUAL;				precedence = 4;
		case .ISNOTEQUAL;			operator_type = .IS_NOT_EQUAL;			precedence = 4;
		case .LESSEQUALS;			operator_type = .LESS_OR_EQUAL;			precedence = 4;
		case .GREATEREQUALS;		operator_type = .GREATER_OR_EQUAL;		precedence = 4;
		case #char "<"; #through;
		case #char ">";
			operator_type = token_type.(Operator_Type);						precedence = 4;

		case .LOGICAL_AND;			operator_type = .LOGICAL_AND;			precedence = 3;
		case .LOGICAL_OR;			operator_type = .LOGICAL_OR;			precedence = 2;

		case #char "=";
			operator_type = token_type.(Operator_Type);						precedence = 1;

		case .PLUSEQUALS;			operator_type = .PLUS_ASSIGN;			precedence = 1;
		case .MINUSEQUALS;			operator_type = .MINUS_ASSIGN;			precedence = 1;
		case .TIMESEQUALS;			operator_type = .TIMES_ASSIGN;			precedence = 1;
		case .DIVEQUALS;			operator_type = .DIV_ASSIGN;			precedence = 1;
		case .MODEQUALS;			operator_type = .MOD_ASSIGN;			precedence = 1;
		case .SHIFT_LEFT_EQUALS;	operator_type = .SHIFT_LEFT_ASSIGN;		precedence = 1;
		case .SHIFT_RIGHT_EQUALS;	operator_type = .SHIFT_RIGHT_ASSIGN;	precedence = 1;
		case .ROTATE_LEFT_EQUALS;	operator_type = .ROTATE_LEFT_ASSIGN;	precedence = 1;
		case .ROTATE_RIGHT_EQUALS;	operator_type = .ROTATE_RIGHT_ASSIGN;	precedence = 1;
		case .BITWISE_AND_EQUALS;	operator_type = .BITWISE_AND_ASSIGN;	precedence = 1;
		case .BITWISE_OR_EQUALS;	operator_type = .BITWISE_OR_ASSIGN;		precedence = 1;
		case .BITWISE_XOR_EQUALS;	operator_type = .BITWISE_XOR_ASSIGN;	precedence = 1;
		case .LOGICAL_AND_EQUALS;	operator_type = .LOGICAL_AND_ASSIGN;	precedence = 1;
		case .LOGICAL_OR_EQUALS;	operator_type = .LOGICAL_OR_ASSIGN;		precedence = 1;

		case;
			return false, xx 0, 0, false;
	}


	return true, operator_type, precedence, false;
}

parse_prefix :: (parser: *Parser) -> *Parser_Node {
	first := parser.cursor;
	token := parser_peek(parser);
	if token.type == #char "." {//TODO: case
		parser_eat(parser);
		subexpression := parse_primary(parser);
		if !subexpression {
			add_expected_expression(parser);
			return null;
		}


		result := new_parser_node(parser, Parser_Unary_Operator);
		result.kind = .UNARY_OPERATOR;
		result.operator_type = #char ".";
		result.subexpression = subexpression;
		finish_node(parser, result, first);
		return parse_postfix_suffixes(parser, result, first);
	}


	if token.type == .KEYWORD_AUTO_CAST {
		parser_eat(parser);
		expression := parse_prefix(parser);
		if !expression {
			add_expected_expression(parser);
			return null;
		}


		result := new_parser_node(parser, Parser_Cast);
		result.kind = .CAST;
		result.expression = expression;
		result.cast_flags |= .IS_AUTO;
		finish_node(parser, result, first);
		return result;
	}


	if token.type == .KEYWORD_CAST {
		parser_eat(parser);
		parser_expect(parser, #char "(");
		type_expression := parse_binary(parser);
		if !type_expression {
			add_expected_expression(parser);
			return null;
		}


		parser_expect(parser, #char ")");

		expression := parse_prefix(parser);
		if !expression {
			add_expected_expression(parser);
			return null;
		}


		result := new_parser_node(parser, Parser_Cast);
		result.kind = .CAST;
		result.target_type = make_type_instantiation(parser, type_expression);
		result.expression = expression;
		finish_node(parser, result, first);
		return result;
	}


	operator_type: Operator_Type;
	if token.type == {
		case #char "+"; #through;
		case #char "-"; #through;
		case #char "!"; #through;
		case #char "~";
			operator_type = token.type.(Operator_Type);

		case .PREFIX_DEREFERENCE;
			operator_type = .POINTER_DEREFERENCE;

		case;
			return parse_postfix(parser);
	}

	parser_eat(parser);
	subexpression := parse_prefix(parser);
	if !subexpression {
		add_expected_expression(parser);
		return null;
	}


	result := new_parser_node(parser, Parser_Unary_Operator);
	result.kind = .UNARY_OPERATOR;
	result.operator_type = operator_type;
	result.subexpression = subexpression;

	finish_node(parser, result, first);
	return result;
}

parse_postfix :: (parser: *Parser) -> *Parser_Node {
	first := parser.cursor;
	result := parse_primary(parser);
	return ifx result
		then parse_postfix_suffixes(parser, result, first)
		else null;
}

parse_postfix_suffixes :: (parser: *Parser, result: *Parser_Node, first: s64) -> *Parser_Node {
	while true {
		if parser_peek(parser).type == {
			case #char "(";
				result = parse_procedure_call(parser, result, first);

			case #char "[";
				parser_eat(parser);
				index := parse_binary(parser);
				if !index	add_expected_expression(parser);
				parser_expect(parser, #char "]");

				subscript := new_parser_node(parser, Parser_Binary_Operator);
				subscript.kind = .BINARY_OPERATOR;
				subscript.operator_type = .ARRAY_SUBSCRIPT;
				subscript.left = result;
				subscript.right = index;
				result = finish_node(parser, subscript, first);

			case .POSTFIX_DEREFERENCE;
				parser_eat(parser);
				dereference := new_parser_node(parser, Parser_Unary_Operator);
				dereference.kind = .UNARY_OPERATOR;
				dereference.operator_type = .POSTFIX_DEREFERENCE;
				dereference.subexpression = result;
				result = finish_node(parser, dereference, first);

			case #char ".";
				parser_eat(parser);
				if parser_peek(parser).type == #char "(" {
					parser_eat(parser);
					type_expression := parse_binary(parser);
					if !type_expression {
						add_expected_expression(parser);
						return result;
					}


					parser_expect(parser, #char ")");

					cast_node := new_parser_node(parser, Parser_Cast);
					cast_node.kind = .CAST;
					cast_node.target_type = make_type_instantiation(parser, type_expression);
					cast_node.expression = result;
					cast_node.cast_flags |= .HAS_POSTFIX_SYNTAX;
					result = finish_node(parser, cast_node, first);
					continue;
				}


				member := parse_primary(parser);
				if !member {
					add_expected_expression(parser);
					return result;
				}


				if member.kind == .IDENT {
					member.(*Parser_Ident).flags |= .IS_RHS_OF_DOT_DEREFERENCE;
				}

				access := new_parser_node(parser, Parser_Binary_Operator);
				access.kind = .BINARY_OPERATOR;
				access.operator_type = #char ".";
				access.left = result;
				access.right = member;
				result = finish_node(parser, access, first);

			case .BEGIN_ARRAY_LITERAL;
				result = parse_aggregate_literal(parser, .ARRAY, result, first);
			case .BEGIN_STRUCT_LITERAL;
				result = parse_aggregate_literal(parser, .STRUCT, result, first);

			case;
				break;
		}
	}

	return result;
}

parse_procedure_call :: (parser: *Parser, procedure: *Parser_Node, first: s64) -> *Parser_Node {
	parser_eat(parser);
	arguments: [..] Parser_Argument;
	arguments.allocator = parser_node_allocator(parser.parsed);

	while parser_peek(parser).type != #char ")" && parser_peek(parser).type != .END_OF_INPUT {//TODO: cache parserPeek
		argument: Parser_Argument;
		if parser_peek(parser).type == .IDENT && parser_peek(parser, 1).type == #char "=" {
			name_first := parser.cursor;
			name_token := parser_eat(parser);
			argument.name = new_parser_node(parser, Parser_Ident);
			argument.name.kind = .IDENT;
			argument.name.name = name_token.ident_value.name;
			finish_node(parser, argument.name, name_first);
			parser_eat(parser);
		}

		argument.expression = parse_binary(parser, 2);
		if !argument.expression {
			add_expected_expression(parser);
			parser_synchronize(parser, .EXPRESSION);
			break;
		}


		array_add(*arguments, argument);

		if parser_peek(parser).type != #char ","	break;


		parser_eat(parser);
	}

	parser_expect(parser, #char ")");
	result := new_parser_node(parser, Parser_Procedure_Call);
	result.kind = .PROCEDURE_CALL;
	result.procedure_expression = procedure;
	result.arguments_unsorted = arguments;
	finish_node(parser, result, first);
	return result;
}

make_type_instantiation :: (parser: *Parser, expression: *Parser_Node) -> *Parser_Type_Instantiation {
	result := new_parser_node(parser, Parser_Type_Instantiation);
	result.kind = .TYPE_INSTANTIATION;
	result.type_valued_expression = expression;
	result.l0 = expression.l0;
	result.c0 = expression.c0;
	result.l1 = expression.l1;
	result.c1 = expression.c1;
	#if ENABLE_TRIVIA {
		result.first_token = expression.first_token;
		result.one_past_last_token = expression.one_past_last_token;
	}
	return result;
}

parse_aggregate_literal :: (
	parser: *Parser,
	value_type: type_of(Code_Literal.value_type),
	type_expression: *Parser_Node,
	first: s64
) -> *Parser_Node {
	assert(value_type == .ARRAY || value_type == .STRUCT);
	closing_token := ifx value_type == .ARRAY then (#char "]").(Token_Type) else (#char "}").(Token_Type);
	parser_eat(parser);

	members: [..] *Parser_Node;
	members.allocator = parser_node_allocator(parser.parsed);
	while parser_peek(parser).type != closing_token && parser_peek(parser).type != .END_OF_INPUT {//TODO: cache parserPeek
		member := parse_binary(parser);
		if !member {
			add_expected_expression(parser);
			parser_synchronize(parser, .EXPRESSION);
			break;
		}


		array_add(*members, member);

		if parser_peek(parser).type != #char ","	break;
		parser_eat(parser);
	}

	parser_expect(parser, closing_token);

	result := new_parser_node(parser, Parser_Literal);
	result.kind = .LITERAL;
	result.node_flags |= .ALLOWED_BY_CONTEXT;
	result.value_type = value_type;

	if value_type == .ARRAY {
		info := new_parser_node(parser, Parser_Array_Literal_Info);
		if type_expression {
			info.element_type = make_type_instantiation(parser, type_expression);
		} else {
			info.array_literal_flags |= .WAS_UNTYPED;
		}

		info.array_members = members;
		result.array_literal_info = info;
	} else {
		info := new_parser_node(parser, Parser_Struct_Literal_Info);
		if type_expression	info.type_expression = make_type_instantiation(parser, type_expression);
		info.arguments = members;
		result.struct_literal_info = info;
	}

	finish_node(parser, result, first);
	return result;
}

parse_primary :: (parser: *Parser) -> *Parser_Node {
	first := parser.cursor;
	token := parser_peek(parser);

	if token.type == {
		case .KEYWORD_IFX;
			return parse_if_statement(parser, null, true);

		case .KEYWORD_INLINE; #through;
		case .KEYWORD_NO_INLINE;
			parser_eat(parser);
			if parser_peek(parser).type != #char "(" || !looks_like_procedure_header(parser) {
				add_expected_expression(parser);
				return null;
			}


			header := parse_procedure_type_header(parser, true);
			if token.type == .KEYWORD_INLINE {//TODO: ifx
				header.procedure_flags |= .SYNTACTICALLY_MARKED_AS_INLINE_YES;
			} else {
				header.procedure_flags |= .SYNTACTICALLY_MARKED_AS_INLINE_NO;
			}

			finish_node(parser, header, first);
			return header;

		case .KEYWORD_STRUCT; #through;
		case .KEYWORD_UNION; #through;
		case .KEYWORD_ENUM; #through;
		case .KEYWORD_ENUM_FLAGS;
			return parse_aggregate_definition(parser);

		case .KEYWORD_TYPE_OF; #through;
		case .KEYWORD_IS_CONSTANT; #through;
		case .KEYWORD_CODE_OF;
			parser_eat(parser);
			parser_expect(parser, #char "(");
			expression := parse_binary(parser);
			if !expression {
				add_expected_expression(parser);
				return null;
			}


			parser_expect(parser, #char ")");

			result := new_parser_node(parser, Parser_Expression_Query);
			result.kind = .EXPRESSION_QUERY;
			if token.type == {
				case .KEYWORD_TYPE_OF;		result.query_kind = .TYPE_OF;
				case .KEYWORD_IS_CONSTANT;	result.query_kind = .IS_CONSTANT;
				case .KEYWORD_CODE_OF;		result.query_kind = .CODE_OF;
			}

			result.expression_to_query = expression;
			finish_node(parser, result, first);
			return result;

		case .KEYWORD_SIZE_OF; #through;
		case .KEYWORD_TYPE_INFO; #through;
		case .KEYWORD_INITIALIZER_OF;
			parser_eat(parser);
			parser_expect(parser, #char "(");
			type_expression := parse_binary(parser);
			if !type_expression {
				add_expected_expression(parser);
				return null;
			}


			parser_expect(parser, #char ")");

			result := new_parser_node(parser, Parser_Type_Query);
			result.kind = .TYPE_QUERY;
			if token.type == {
				case .KEYWORD_SIZE_OF;			result.query_kind = .SIZE_OF;
				case .KEYWORD_TYPE_INFO;		result.query_kind = .TYPE_INFO;
				case .KEYWORD_INITIALIZER_OF;	result.query_kind = .INITIALIZER_OF;
			}

			result.type_to_query = make_type_instantiation(parser, type_expression);
			finish_node(parser, result, first);
			return result;

		case #char "#";
			directive_name := parser_peek(parser, 1);
			if directive_name.type != .IDENT				return null;
			if directive_name.ident_value.name == "type"	return parse_type_instantiation(parser);
			if directive_name.ident_value.name != "string"	return parse_expression_directive(parser, first, directive_name.ident_value.name);


			parser_eat(parser);
			parser_eat(parser);
			while parser_peek(parser).type == #char "," {
				parser_eat(parser);
				parser_expect(parser, .IDENT);
			}

			parser_expect(parser, .IDENT);
			body := parser_peek(parser);
			if body.type != .STRING {
				add_expected_expression(parser);
				return null;
			}


			parser_eat(parser);
			parser_expect(parser, .IDENT);

			result := new_parser_node(parser, Parser_Literal);
			result.kind = .LITERAL;
			result.value_type = .STRING;
			result._string = body.string_value;
			result.value_flags |= .HERE_STRING;
			finish_node(parser, result, first);
			return result;

		case .BEGIN_ARRAY_LITERAL;
			return parse_aggregate_literal(parser, .ARRAY, null, first);

		case .BEGIN_STRUCT_LITERAL;
			return parse_aggregate_literal(parser, .STRUCT, null, first);

		case .TRIPLE_MINUS;
			parser_eat(parser);
			result := new_parser_node(parser, Parser_Placeholder);
			result.kind = .PLACEHOLDER;
			finish_node(parser, result, first);
			return result;

		case #char "(";
			if looks_like_procedure_header(parser) {
				return parse_procedure_type_header(parser, true);
			}


			parser_eat(parser);
			result := parse_binary(parser);
			if !result {
				add_expected_expression(parser);
				return null;
			}


			parser_expect(parser, #char ")");
			result.node_flags |= .IS_PARENTHESIZED;
			finish_node(parser, result, first);
			return result;

		case .IDENT;
			if parser_peek(parser, 1).type == .QUICK_LAMBDA {
				parser_eat(parser);
				argument := new_parser_node(parser, Parser_Declaration);
				argument.kind = .DECLARATION;
				argument.name = token.ident_value.name;
				finish_node(parser, argument, first);

				header := new_parser_node(parser, Parser_Procedure_Header);
				header.kind = .PROCEDURE_HEADER;
				header.procedure_flags |= .QUICK;
				arguments: [..] *Parser_Declaration;
				arguments.allocator = parser_node_allocator(parser.parsed);
				array_add(*arguments, argument);
				header.arguments = arguments;
				parse_procedure_body(parser, header, first);
				finish_node(parser, header, first);
				return header;
			}


			parser_eat(parser);

			result := new_parser_node(parser, Parser_Ident);
			result.kind = .IDENT;
			result.name = token.ident_value.name;
			finish_node(parser, result, first);
			return result;

		case .NUMBER;
			parser_eat(parser);

			result := new_parser_node(parser, Parser_Literal);
			result.kind = .LITERAL;
			result.value_type = .NUMBER;
			result.value_flags |= .IS_A_NUMBER;

			if token.value_flags & .FLOAT {
				result._float64 = token.float64_value;
				result.value_flags |= .FLOAT;
			} else {
				result._u64 = token.integer_value;
			}

			//QUESTION: is this exhaustive?
			if token.value_flags & .HEX						result.value_flags |= .HEX;
			if token.value_flags & .BINARY					result.value_flags |= .BINARY;
			if token.value_flags & .DEFAULTS_TO_FLOAT64		result.value_flags |= .DEFAULTS_TO_FLOAT64;
			if token.value_flags & (.REQUIRES_FLOAT64 | .REQUIRES_FLOAT64_DUE_TO_SIGNIFICANT_DIGITS)	result.value_flags |= .REQUIRES_FLOAT64;

			finish_node(parser, result, first);
			return result;

		case .STRING;
			parser_eat(parser);

			result := new_parser_node(parser, Parser_Literal);
			result.kind = .LITERAL;
			result.value_type = .STRING;
			result._string = token.string_value;
			if token.value_flags & .HERE_STRING		result.value_flags |= .HERE_STRING;

			finish_node(parser, result, first);
			return result;

		case .KEYWORD_TRUE; #through;
		case .KEYWORD_FALSE;
			parser_eat(parser);

			result := new_parser_node(parser, Parser_Literal);
			result.kind = .LITERAL;
			result.value_type = .BOOLEAN;
			result._u64 = xx (token.type == .KEYWORD_TRUE);

			finish_node(parser, result, first);
			return result;

		case .KEYWORD_NULL;
			parser_eat(parser);

			pointer_info := new_parser_node(parser, Code_Pointer_Literal_Info);
			pointer_info.pointer_literal_type = .CONSTANT_VALUE;

			result := new_parser_node(parser, Parser_Literal);
			result.kind = .LITERAL;
			result.value_type = .POINTER;
			result.pointer_literal_info = pointer_info;

			finish_node(parser, result, first);
			return result;

		case .KEYWORD_CONTEXT;
			parser_eat(parser);

			result := new_parser_node(parser, Parser_Context);
			result.kind = .CONTEXT;

			finish_node(parser, result, first);
			return result;

		case;
			return null;
	}
}

parse_expression_directive :: (parser: *Parser, first: s64, name: string) -> *Parser_Node {
	if name == {
		case "load";
			parser_eat(parser);
			parser_eat(parser);
			result := new_parser_node(parser, Parser_Directive_Load);
			result.kind = .DIRECTIVE_LOAD;

			if parser_peek(parser).type == .STRING {
				result.short_name = parser_eat(parser).string_value;
			} else {
				parser_expect(parser, .STRING);
			}

			finish_node(parser, result, first);
			return result;

		case "bytes";
			parser_eat(parser);
			parser_eat(parser);
			result := new_parser_node(parser, Parser_Directive_Bytes);
			result.kind = .DIRECTIVE_BYTES;
			result.expression = parse_binary(parser);
			if !result.expression	add_expected_expression(parser);
			finish_node(parser, result, first);
			return result;

		case "procedure_name";
			parser_eat(parser);
			parser_eat(parser);
			result := new_parser_node(parser, Parser_Directive_Procedure_Name);
			result.kind = .DIRECTIVE_PROCEDURE_NAME;
			parser_expect(parser, #char "(");
			if parser_peek(parser).type != #char ")" {
				result.argument = parse_binary(parser);
				if !result.argument		add_expected_expression(parser);
			}

			parser_expect(parser, #char ")");
			finish_node(parser, result, first);
			return result;

		case "wildcard";
			parser_eat(parser);
			parser_eat(parser);
			result := new_parser_node(parser, Parser_Directive_Wildcard);
			result.kind = .DIRECTIVE_WILDCARD;
			finish_node(parser, result, first);
			return result;

		case "exists";
			parser_eat(parser);
			parser_eat(parser);
			result := new_parser_node(parser, Parser_Directive_Exists);
			result.kind = .DIRECTIVE_EXISTS;
			parser_expect(parser, #char "(");
			result.query_expression = parse_binary(parser);
			if !result.query_expression		add_expected_expression(parser);

			if parser_peek(parser).type == #char "," {
				parser_eat(parser);
				result.sync_expression = parse_binary(parser);
				if !result.sync_expression	add_expected_expression(parser);
			}

			parser_expect(parser, #char ")");
			finish_node(parser, result, first);
			return result;

		case "import";
			parser_eat(parser);
			parser_eat(parser);
			result := new_parser_node(parser, Parser_Directive_Import);
			result.kind = .DIRECTIVE_IMPORT;//TODO: cache parserPeek
			while parser_peek(parser).type == #char "," {
				parser_eat(parser);
				modifier := parser_peek(parser);
				if modifier.type != .IDENT {
					parser_expect(parser, .IDENT);
					break;
				}


				modifier_name := cast(string) modifier.ident_value.name;
				if modifier_name == {
					case "file";
						result.import_type = .PATH_TO_FILE;
						result.flags |= xx 0x4;		// Unnamed source-path bit in the public compiler enum.
					case "dir";
						result.import_type = .PATH_TO_DIRECTORY;
						result.flags |= xx 0x4;		// Unnamed source-path bit in the public compiler enum.
					case "string";
						result.import_type = .FULL_TEXT;
						result.flags |= .UNSHARED;
					case;
						add_unexpected_token(parser);
				}

				parser_eat(parser);
			}

			if parser_peek(parser).type == .STRING {//TODO: cache parserPeek
				result.name = parser_eat(parser).string_value;
			} else {
				parser_expect(parser, .STRING);
			}

			if parser_peek(parser).type == #char "(" {
				result.module_parameters_call = parse_procedure_call(parser, result, first).(*Parser_Procedure_Call);
			}

			if parser_peek(parser).type == #char "(" {
				result.program_parameters_call = parse_procedure_call(parser, result, first).(*Parser_Procedure_Call);
			}

			finish_node(parser, result, first);
			return result;

		case "poke_name";
			parser_eat(parser);
			parser_eat(parser);
			result := new_parser_node(parser, Parser_Directive_Poke_Name);
			result.kind = .DIRECTIVE_POKE_NAME;
			result.module_expression = parse_postfix(parser);
			if !result.module_expression	add_expected_expression(parser);

			if parser_peek(parser).type == .IDENT {
				result.name = parser_eat(parser).ident_value.name;
			} else {
				parser_expect(parser, .IDENT);
			}

			finish_node(parser, result, first);
			return result;

		case "library";
			parser_eat(parser);
			parser_eat(parser);
			result := new_parser_node(parser, Parser_Directive_Library);
			result.kind = .DIRECTIVE_LIBRARY;
			while parser_peek(parser).type == #char "," {
				parser_eat(parser);
				modifier := parser_peek(parser);
				if modifier.type != .IDENT {
					parser_expect(parser, .IDENT);
					break;
				}


				modifier_name := cast(string) modifier.ident_value.name;
				if modifier_name == {
					case "system";
						result.library_flags |= .IS_SYSTEM_LIBRARY;
					case "no_static_library";
						result.library_flags |= .STATIC_LIBRARY_UNAVAILABLE;
					case "link_always";
						// The raw compiler AST accepts this spelling but leaves LINK_ALWAYS clear.
					case;
						add_unexpected_token(parser);
				}

				parser_eat(parser);
			}


			if parser_peek(parser).type == .STRING {
				result.name = parser_eat(parser).string_value;
			} else {
				parser_expect(parser, .STRING);
			}

			finish_node(parser, result, first);
			return result;

		case "location"; #through;
		case "caller_location";
			parser_eat(parser);
			parser_eat(parser);

			result := new_parser_node(parser, Parser_Directive_Location);
			result.kind = .DIRECTIVE_LOCATION;
			result.is_caller_location = name == "caller_location";
			if !result.is_caller_location {
				parser_expect(parser, #char "(");
				if parser_peek(parser).type != #char ")" {
					result.expression = parse_binary(parser);
					if !result.expression	add_expected_expression(parser);
				}

				parser_expect(parser, #char ")");
			}

			finish_node(parser, result, first);
			return result;

		case "code"; #through;
		case "run"; #through;
		case "insert"; #through;
		case "bake"; #through;
		case "bake_constants"; #through;
		case "bake_arguments";
			parser_eat(parser);
			parser_eat(parser);

			if name == "code" {//TODO: case
				result := new_parser_node(parser, Parser_Directive_Code);
				result.kind = .DIRECTIVE_CODE;
				parse_payload := true;
				if parser_peek(parser).type == #char "," {
					modifier := parser_peek(parser, 1);
					if modifier.type == {
						case .KEYWORD_NULL;
							parser_eat(parser);
							parser_eat(parser);
							result.code_flags |= .NULL;
							parse_payload = false;
						case .IDENT;
							if cast(string) modifier.ident_value.name == "typed" {
								parser_eat(parser);
								parser_eat(parser);
								result.code_flags |= .TYPED;
							}
					}
				}
				if parse_payload {
					if parser_peek(parser).type == #char "{" {//TODO: ifx
						result.expression = parse_block_node(parser);
					} else {
						result.expression = parse_binary(parser);
					}

					if !result.expression	add_expected_expression(parser);
				}

				finish_node(parser, result, first);
				return result;
			}

			if name == "run" {
				result := new_parser_node(parser, Parser_Directive_Run);
				result.kind = .DIRECTIVE_RUN;
				if parser_peek(parser).type == #char "," && parser_peek(parser, 1).type == .IDENT && parser_peek(parser, 1).ident_value.name == "stallable" {
					parser_eat(parser);
					parser_eat(parser);
					result.flags |= .STALLABLE;
				}
				if parser_peek(parser).type == #char "{" {
					result.expression = parse_block_node(parser);
				} else {
					result.flags |= .HAS_IMPLICIT_RETURN_TYPES;
					result.expression = parse_binary(parser);
				}
				if !result.expression	add_expected_expression(parser);
				finish_node(parser, result, first);
				return result;
			}


			if name == "insert" {
				result := new_parser_node(parser, Parser_Directive_Insert);
				result.kind = .DIRECTIVE_INSERT;//TODO: cache parserPeek, carefully
				if parser_peek(parser).type == #char "," {
					parser_eat(parser);
					modifier := parser_peek(parser);
					if modifier.type == .IDENT && modifier.ident_value.name == "scope" {
						parser_eat(parser);
						parser_expect(parser, #char "(");
						result.scope_redirection = parse_binary(parser);
						if !result.scope_redirection	add_expected_expression(parser);
						parser_expect(parser, #char ")");
					} else {
						parser_expect(parser, .IDENT);
					}
				}

				if parser_peek(parser).type == #char "(" {
					parser_eat(parser);
					while parser_peek(parser).type != #char ")" && parser_peek(parser).type != .END_OF_INPUT {//TODO: cache parserPeek
						modifier := parser_peek(parser);
						if modifier.type == .IDENT || modifier.type == .KEYWORD_BREAK || modifier.type == .KEYWORD_CONTINUE || modifier.type == .KEYWORD_REMOVE {
							parser_eat(parser);
						} else {
							parser_expect(parser, .IDENT);
						}

						parser_expect(parser, #char "=");
						replacement := parse_statement(parser);
						if !replacement	add_expected_expression(parser);
						if modifier.type == {
							case .KEYWORD_BREAK;		result.break_replacement = replacement;
							case .KEYWORD_CONTINUE;	result.continue_replacement = replacement;
							case .KEYWORD_REMOVE;		result.remove_replacement = replacement;
						}
						if parser_peek(parser).type != #char ","	break;


						parser_eat(parser);
					}

					parser_expect(parser, #char ")");
				}

				if parser_peek(parser).type == .RIGHT_ARROW {
					header := parse_arrow_procedure_header(parser, first);
					run := new_parser_node(parser, Parser_Directive_Run);
					run.kind = .DIRECTIVE_RUN;
					run.flags |= .SYNTACTICALLY_IMPLICIT;
					run.procedure = header;
					if header.body_or_null	run.expression = header.body_or_null.block;
					finish_node(parser, run, first);
					result.expression = run;
				} else {
					result.expression = parse_binary(parser);
				}

				if !result.expression	add_expected_expression(parser);
				finish_node(parser, result, first);
				return result;
			}


			result := new_parser_node(parser, Parser_Directive_Bake);
			result.kind = .DIRECTIVE_BAKE;
			if name == {
				case "bake_constants";	result.bake_type = .CONSTANTS_BAKE;
				case "bake_arguments";	result.bake_type = .PARAMETER_VALUE_BAKE;
				case "bake";			result.bake_type = .DYNAMIC_SPECIALIZE;
			}

			call := parse_postfix(parser);
			if call && call.kind == .PROCEDURE_CALL {
				result.procedure_call = call.(*Parser_Procedure_Call);
			} else {
				add_expected_expression_at(parser, make_token_span(first, parser.cursor), "Expected a procedure call after #bake.");
			}

			finish_node(parser, result, first);
			return result;

		case;
			return null;
	}
}

add_missing_token :: (parser: *Parser, expected: Token_Type) {
	actual := parser_peek(parser);

	synthetic: Synthetic_Token;		//LATER: speed: = ---; --need to audit initialisation coverage.
	synthetic.token.type = expected;
	synthetic.token.l0 = actual.l0;
	synthetic.token.c0 = actual.c0;
	synthetic.token.l1 = actual.l0;
	synthetic.token.c1 = actual.c0;
	synthetic.insertion_index = xx parser.cursor;
	array_add(*parser.parsed.synthetic_tokens, synthetic);

	diagnostic: Parse_Diagnostic;	//LATER: speed: = ---; --need to audit initialisation coverage.
	diagnostic.kind = .EXPECTED_TOKEN;
	diagnostic.span = make_token_span(parser.cursor, parser.cursor);
	diagnostic.expected_token = expected;
	diagnostic.actual_token = actual.type;
	diagnostic.recovery_action = .INSERT_MISSING_TOKEN;
	array_add(*parser.parsed.diagnostics, diagnostic);

	mark_parse_error(parser, actual.type == .END_OF_INPUT);
}

add_expected_expression :: (parser: *Parser) {
	add_expected_expression_at(
		parser,
		make_token_span(parser.cursor, parser.cursor),
		"Unable to parse an expression."
	);
}

add_expected_expression_at :: (parser: *Parser, span: Token_Span, message: string) {
	diagnostic: Parse_Diagnostic;	//LATER: speed: = ---; --need to audit initialisation coverage.
	diagnostic.kind = .EXPECTED_EXPRESSION;
	diagnostic.span = span;
	diagnostic.message = message;
	diagnostic.actual_token = parser_peek(parser).type;
	array_add(*parser.parsed.diagnostics, diagnostic);
	mark_parse_error(parser, diagnostic.actual_token == .END_OF_INPUT);
}

add_unexpected_token :: (parser: *Parser) {
	actual := parser_peek(parser);
	first := parser.cursor;
	parser_eat(parser);
	parser_synchronize(parser, .EXPRESSION);

	diagnostic: Parse_Diagnostic;	//LATER: speed: = ---; --need to audit initialisation coverage.
	diagnostic.kind = .UNEXPECTED_TOKEN;
	diagnostic.span = make_token_span(first, parser.cursor);
	diagnostic.actual_token = actual.type;
	diagnostic.recovery_action = .SKIP_TOKENS;
	array_add(*parser.parsed.diagnostics, diagnostic);
	mark_parse_error(parser, false);
}

mark_parse_error :: (parser: *Parser, incomplete: bool) {
	if parser.parsed.status == .FATAL	return;


	if incomplete {
		if parser.parsed.status == .COMPLETE {
			parser.parsed.status = .INCOMPLETE;
		}
	} else {
		parser.parsed.status = .RECOVERED;
	}
}

finish_node :: (parser: *Parser, node: *$T/Parser_Node, first: s64) -> *T {
	assert(first >= 0 && first < parser.cursor);
	first_token := parser.parsed.tokens[first];
	last_token := parser.parsed.tokens[parser.cursor - 1];

	node.l0 = first_token.l0;
	node.c0 = first_token.c0;
	node.l1 = last_token.l1;
	node.c1 = last_token.c1;

	#if ENABLE_TRIVIA {
		node.first_token = xx first;
		node.one_past_last_token = xx parser.cursor;
	}

	return node;
}

materialize_tokens :: (source: string) -> Parsed_Source {
	result: Parsed_Source;
	result.source = source;

	lexer: Lexer;
	set_input_from_string(*lexer, source);

	source_cursor: s64;

	while true {
		token := peek_next_token(*lexer);
		if token.type == .END_OF_INPUT {//TODO: case
			append_materialized_token(*result, token, *source_cursor);
			break;
		}


		if token.type == #char "#" {
			next := peek_token(*lexer, 1);
			if next.type == .IDENT && next.ident_value.name == "string" {
				materialize_here_string(*result, *lexer, *source_cursor);
				continue;
			}
		}


		consume_materialized_token(*result, *lexer, *source_cursor);
	}

	result.status = ifx lexer.reported_error
		then .RECOVERED
		else .COMPLETE;

	return result;
}

consume_materialized_token :: (
	parsed: *Parsed_Source,
	lexer: *Lexer,
	source_cursor: *s64
) -> Token {
	token := peek_next_token(lexer);
	result := token.*;
	append_materialized_token(parsed, token, source_cursor);
	eat_token(lexer);
	return result;
}

append_materialized_token :: (
	parsed: *Parsed_Source,
	token: *Token,
	source_cursor: *s64
) {
	#if ENABLE_TRIVIA {
		materialized: Parser_Token;
		materialized.lexer_token = token.*;
		materialized.index = xx parsed.tokens.count;
		materialized.preceding_trivia_byte_start = source_cursor.*;

		if token.type == .END_OF_INPUT {
			source_cursor.* += token.trailing_trivia.count;
			materialized.byte_start = source_cursor.*;
			materialized.byte_end = source_cursor.*;
		} else {
			materialized.byte_start = source_cursor.* + token.preceding_trivia.count;
			materialized.byte_end = materialized.byte_start + token.original_text.count;
			source_cursor.* = materialized.byte_end;
		}

		array_add(*parsed.tokens, materialized);
	} else {
		array_add(*parsed.tokens, token.*);
	}
}

materialize_here_string :: (
	parsed: *Parsed_Source,
	lexer: *Lexer,
	source_cursor: *s64
) {
	consume_materialized_token(parsed, lexer, source_cursor);
	name := consume_materialized_token(parsed, lexer, source_cursor);
	assert(name.type == .IDENT && name.ident_value.name == "string");

	want_cr := false;
	while peek_next_token(lexer).type == #char "," {
		consume_materialized_token(parsed, lexer, source_cursor);
		modifier := consume_materialized_token(parsed, lexer, source_cursor);
		if modifier.type != .IDENT {
			report_parse_error(lexer, *modifier, "Expected a #string modifier.");
			return;
		}


		if modifier.ident_value.name == "cr" {
			want_cr = true;
		}
		//TODO: \% handling...?
	}

	delimiter := consume_materialized_token(parsed, lexer, source_cursor);
	if delimiter.type != .IDENT {
		report_parse_error(lexer, *delimiter, "Expected a #string delimiter.");
		return;
	}


	body := parse_here_string_body(lexer, delimiter.ident_value.name, want_cr);
	if !body {
		return;
	}


	append_materialized_token(parsed, body, source_cursor);
}

#if ENABLE_TRIVIA {
	reconstruct_source :: (parsed: *Parsed_Source) -> string {
		builder: String_Builder;
		for * token: parsed.tokens {
			if token.type == .END_OF_INPUT {
				append(*builder, token.trailing_trivia);
			} else {
				append(*builder, token.preceding_trivia);
				append(*builder, token.original_text);
			}
		}

		return builder_to_string(*builder);
	}
}
