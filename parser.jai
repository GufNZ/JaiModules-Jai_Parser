#import "Compiler";
#import "Pool";

// The compiler outputs values for these enums that aren't publically named, so we define them manually here:
Code_Literal_Value_Flags_SIGNIFICANT_DIGITS :: 0x400;
Code_Directive_Code_Flags_CALLER_CODE :: 0x4;
Code_Directive_Import_Flags_SOURCE_PATH :: 0x4;
Code_Directive_Run_Flags_HOST :: 0x10;

Token_Index :: #type,distinct s64;
Parser_Checkpoint :: #type,distinct s64;

Token_Span :: struct {
	first: Token_Index;
	one_past_last: Token_Index;
}

Parser_Asm_Feature :: struct {
	span: Token_Span;
	name: *Parser_Ident;
}

Parser_Asm_Statement_Kind :: enum u8 {
	UNPARSED;
	INSTRUCTION;
	REGISTER_DECLARATION;
	REGISTER_PINNING;
}

Parser_Asm_Operand_Kind :: enum u8 {
	UNPARSED;
	VALUE;
	REGISTER_DECLARATION;
	REGISTER_PINNING;
	MEMORY;
}

Parser_Asm_Mnemonic_Size_Kind :: enum u8 {
	FIXED;
	POLYMORPHIC;
}

Parser_Asm_Mnemonic_Size :: struct {
	kind: Parser_Asm_Mnemonic_Size_Kind;
	span: Token_Span;
	polymorphic_name: *Parser_Ident;
}

Parser_Asm_Operand_Modifier_Kind :: enum u8 {
	BANG;
	BANG_N;
	BANG_D;
	BANG_U;
	BANG_Z;
	AMPERSAND;
	AMPERSAND_STAR;
}

Parser_Asm_Value :: struct {
	span: Token_Span;
	expression: *Parser_Node;
}

Parser_Asm_Register_Pinning :: struct {
	span: Token_Span;
	source: Parser_Asm_Value;
	target: Parser_Asm_Value;
}

Parser_Asm_Register_Declaration :: struct {
	span: Token_Span;
	name: *Parser_Ident;
	register_class: *Parser_Ident;
	is_inferred: bool;
	pinning: *Parser_Asm_Register_Pinning;
}

Parser_Asm_Memory_Operand :: struct {
	span: Token_Span;
	base: Parser_Asm_Value;
	index: Parser_Asm_Value;
	scale: Parser_Asm_Value;
	displacement: Parser_Asm_Value;
}

Parser_Asm_Operand_Modifier :: struct {
	kind: Parser_Asm_Operand_Modifier_Kind;
	span: Token_Span;
	argument: Parser_Asm_Value;
}

Parser_Asm_Operand :: struct {
	kind: Parser_Asm_Operand_Kind;
	span: Token_Span;
	value: Parser_Asm_Value;
	register_declaration: *Parser_Asm_Register_Declaration;
	register_pinning: *Parser_Asm_Register_Pinning;
	memory: *Parser_Asm_Memory_Operand;
	modifiers: []*Parser_Asm_Operand_Modifier;
}

Parser_Asm_Instruction :: struct {
	span: Token_Span;
	mnemonic: *Parser_Ident;
	size: *Parser_Asm_Mnemonic_Size;
	operands: []*Parser_Asm_Operand;
}

Parser_Asm_Statement :: struct {
	kind: Parser_Asm_Statement_Kind;
	span: Token_Span;
	instruction: *Parser_Asm_Instruction;
	register_declaration: *Parser_Asm_Register_Declaration;
	register_pinning: *Parser_Asm_Register_Pinning;
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

// Records a loop iteration's starting cursor so parser_ensure_progress can consume one token, or stop at end of input, when parsing makes no progress during recovery.
Parser_Progress_Guard :: struct {
	cursor: s64;
}

Synthetic_Token :: struct {
	token: Token;
	insertion_index: Token_Index;
}

Recovery_Record :: struct {
	kind: enum u8 {
		MISSING_TOKEN;
		EXPECTED_EXPRESSION;
		SKIPPED_TOKENS;
		ERROR_SPAN;
	}

	span: Token_Span;
	diagnostic_index: s64;
	synthetic_token_index: s64 = -1;
}

Restart_Point :: struct {
	kind: enum u8 {
		DECLARATION;
		BLOCK;
	}

	span: Token_Span;
}

Parser_Binding :: struct {
	name: string;
	declaration: *Parser_Declaration;
}

Parser_Lexical_Scope :: struct {
	parent: *Parser_Lexical_Scope;
	owner: *Parser_Node;
	children: [..]*Parser_Lexical_Scope;
	bindings: [..]Parser_Binding;
	references: [..]*Parser_Ident;
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
		UNNECESSARY_SEMICOLON;
		LEXER_ERROR;
	}

	severity: enum u8 { ERROR; WARNING; } = .ERROR;
	span: Token_Span;
	message: string;
	lexer_line: s32;
	lexer_column: s32;
	related_information: []Parse_Diagnostic_Info;
	expected_token: Token_Type;
	actual_token: Token_Type;
	recovery_action: Recovery_Action;
}

Rendered_Diagnostic_Line :: struct {
	source: string;
	carets: string;
}

// Expand tabs in both the displayed source and caret positions so diagnostics point at the same visual columns.
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
	// Source-backed token text is borrowed and must outlive this value.
	source: string;
	fully_pathed_filename: string;
	tokens: [..]Parser_Token;
	synthetic_tokens: [..]Synthetic_Token;
	diagnostics: [..]Parse_Diagnostic;
	recovery_records: [..]Recovery_Record;
	restart_points: [..]Restart_Point;
	status: Parse_Status;
	root: *Parser_Node;
	root_scope: *Parser_Lexical_Scope;
	node_pool: Pool;
	identifier_storage: Identifier_Storage;
}


Parser_Node :: struct {
	#if ENABLE_TRIVIA {
		first_token: Token_Index;
		one_past_last_token: Token_Index;
	}

	#as using code_node: Code_Node;
}

// Concrete compiler node layouts embedded into the code-gened parser-owned counterparts below.
TYPES :: Type.[
	Code_Asm,
	Code_Binary_Operator,
	Code_Block,
	Code_Case,
	Code_Cast,
	Code_Comma_Separated_Arguments,
	Code_Compound_Declaration,
	Code_Context,
	Code_Declaration,
	Code_Defer,
	Code_Directive_Add_Context,
	Code_Directive_Bake,
	Code_Directive_Bytes,
	Code_Directive_Code,
	Code_Directive_Context_Type,
	Code_Directive_Exists,
	Code_Directive_Import,
	Code_Directive_Insert,
	Code_Directive_Library,
	Code_Directive_Load,
	Code_Directive_Location,
	Code_Directive_Modify,
	Code_Directive_Module_Parameters,
	Code_Directive_Overlay,
	Code_Directive_Poke_Name,
	Code_Directive_Procedure_Name,
	Code_Directive_Run,
	Code_Directive_Scope,
	Code_Directive_Through,
	Code_Directive_Wildcard,
	Code_Enum,
	Code_Expression_Query,
	Code_For,
	Code_Ident,
	Code_If,
	Code_Literal,
	Code_Loop_Control,
	Code_Note,
	Code_Placeholder,
	Code_Procedure_Body,
	Code_Procedure_Call,
	Code_Procedure_Header,
	Code_Push_Context,
	Code_Return,
	Code_Struct,
	Code_Type_Instantiation,
	Code_Type_Query,
	Code_Unary_Operator,
	Code_Using,
	Code_While,
];
#insert -> string {
	is_parser_struct :: (name: string) -> bool {
		for TYPES {
			if it.(*Type_Info_Struct).name == name {
				return true;
			}
		}


		return name == "Code_Node"
			|| name == "Code_Argument"
			|| name == "Code_Array_Literal_Info"
			|| name == "Code_Comma_Separated_Argument"
			|| name == "Code_Struct_Literal_Info";
	}

	has_parser_type :: (info: *Type_Info) -> bool {
		if info.type == {
			case .POINTER;
				return has_parser_type(info.(*Type_Info_Pointer).pointer_to);
			case .ARRAY;
				return has_parser_type(info.(*Type_Info_Array).element_type);
			case .STRUCT;
				return is_parser_struct(info.(*Type_Info_Struct).name);

			case;
				return false;
		}
	}

	print_parser_type :: (info: *Type_Info, b: *String_Builder) {
		if info.type == {
			case .POINTER;
				print(b, "*");
				print_parser_type(info.(*Type_Info_Pointer).pointer_to, b);

			case .ARRAY;
				array := info.(*Type_Info_Array);
				if array.array_type == {
					case .FIXED;		print(b, "[%]", array.array_count);
					case .VIEW;			print(b, "[]");
					case .RESIZABLE;	print(b, "[..]");
				}

				print_parser_type(array.element_type, b);

			case .STRUCT;
				struct_info := info.(*Type_Info_Struct);
				name_suffix := string.{struct_info.name.count - 4, struct_info.name.data + 4};
				print(b, "Parser%", name_suffix);
		}
	}

	print_parser_member_exceptions :: (t: *Type_Info_Struct, b: *String_Builder) {
		for t.members {
			if it.offset_in_bytes >= 0 && !(it.flags & .AS) && has_parser_type(it.type) {
				print(b, ", %", it.name);
			}

			if it.flags & .USING && it.type.type == .STRUCT {
				print_parser_member_exceptions(it.type.(*Type_Info_Struct), b);
			}
		}
	}

	print_parser_member_overlays :: (owner_name: string, t: *Type_Info_Struct, b: *String_Builder) {
		for t.members {
			if it.offset_in_bytes >= 0 && !(it.flags & .AS) && has_parser_type(it.type) {
				print(b, "\t#overlay(_%.%) %: ", owner_name, it.name, it.name);
				print_parser_type(it.type, b);
				print(b, ";\n");
			}

			if it.flags & .USING && it.type.type == .STRUCT {
				print_parser_member_overlays(owner_name, it.type.(*Type_Info_Struct), b);
			}
		}
	}

	printNode :: (t: *Type_Info_Struct, b: *String_Builder) {
		assert(t.name.count > 4 && starts_with(t.name, "Code_"));
		name_suffix := string.{t.name.count - 4, t.name.data + 4};
		print(b, "Parser% :: struct {\n\t#as using base: Parser_Node;\n", name_suffix);

		print(b, "\t_padding: [%]u8;\n", t.runtime_size - size_of(Code_Node));

		print(b, "\t#overlay(code_node) #as using,except(base, Kind, kind, node_flags, type, Location, location, enclosing_load, l0, c0, l1, c1, serial");
		if t.name == "Code_Procedure_Call" {
			print(b, ", context_modification");
		}

		print_parser_member_exceptions(t, b);
		print(b, ") _%: %1;\n", t.name);

		print_parser_member_overlays(t.name, t, b);

		// Preserve source-level fields that the compiler AST has already lowered or narrowed:
		if t.name == {
			case "Code_Procedure_Call";
				print(b, "\t#overlay(_Code_Procedure_Call.context_modification) context_modification: *Parser_Context_Modification;\n");
			case "Code_Directive_Run";
				print(b, "\texpression: *Parser_Node;\n");
			case "Code_Directive_Poke_Name";
				print(b, "\t#overlay(_Code_Directive_Poke_Name.module_struct) module_expression: *Parser_Node;\n");
			case "Code_Asm";
				print(b, "\tfeatures: []*Parser_Asm_Feature;\n\tstatements: []*Parser_Asm_Statement;\n\tbody_span: Token_Span;\n\tenclosing_scope: *Parser_Block;\n");
			case "Code_Placeholder";
				print(b, "\tname: string;\n");
		}

		print(b, "}\n\n");
	}

	b: String_Builder;
	for TYPES {
		printNode(it.(*Type_Info_Struct), *b);
	}

	return builder_to_string(*b);
}

Parser_Struct_Literal_Info :: struct {
	type_expression: *Parser_Type_Instantiation;
	arguments: []*Parser_Node;
}

Parser_Array_Literal_Info :: struct {
	element_type: *Parser_Type_Instantiation;
	alignment: *Parser_Node;
	array_members: []*Parser_Node;
	array_literal_flags: type_of(Code_Array_Literal_Info.array_literal_flags);
}

Parser_Argument :: struct {
	expression: *Parser_Node;
	name: *Parser_Ident;
}

Parser_Context_Modification :: struct {
	modification_expressions: []*Parser_Node;
}

Parser_Comma_Separated_Argument :: struct {
	node: *Parser_Node;
	modifier: type_of(Code_Comma_Separated_Argument.modifier);
}

Parser :: struct {
	parsed: *Parsed_Source;
	edit_source: *Parsed_Source;
	edit_start: s64;
	edit_end: s64;
	reuse_block: *Parser_Block;
	reuse_statement_index: s64;
	cursor: s64;
	current_scope: *Parser_Lexical_Scope;
	parsing_condition: bool;
	allow_unprefixed_struct_literal: bool;
	warn_unnecessary_semicolons: bool;
}

parser_node_allocator :: inline (parsed: *Parsed_Source) -> Allocator {
	return .{ proc = pool_allocator_proc, data = *parsed.node_pool };
}

new_parser_node :: inline (parser: *Parser, $T: Type) -> *T {
	result := New(T,, parser_node_allocator(parser.parsed));
	#if T == Parser_Directive_Wildcard	result.index = -1;
	#if T == Parser_Struct				result.alignment = -1;
	return result;
}

push_lexical_scope :: (parser: *Parser) -> *Parser_Lexical_Scope {
	scope := New(Parser_Lexical_Scope,, parser_node_allocator(parser.parsed));
	scope.parent = parser.current_scope;
	scope.children.allocator = parser_node_allocator(parser.parsed);
	scope.bindings.allocator = parser_node_allocator(parser.parsed);
	scope.references.allocator = parser_node_allocator(parser.parsed);
	if scope.parent {
		array_add(*scope.parent.children, scope);
	}

	parser.current_scope = scope;
	return scope;
}

resolve_lexical_references :: (scope: *Parser_Lexical_Scope) {
	for reference: scope.references {
		if reference.flags & .IS_RHS_OF_DOT_DEREFERENCE != 0 {
			continue;
		}


		lookup := scope;
		while lookup {
			found := false;
			for binding: lookup.bindings {
				if binding.name == reference.name {
					reference.resolved_declaration = binding.declaration;
					found = true;
					break;
				}
			}


			if found break;


			lookup = lookup.parent;
		}
	}

	for scope.children {
		resolve_lexical_references(it);
	}
}

release_parser_tree :: (parsed: *Parsed_Source) {
	parsed.root = null;
	parsed.root_scope = null;
	release(*parsed.node_pool);
}

release_parser_names :: (parsed: *Parsed_Source) {
	assert(parsed.root == null);
	release_identifier_storage(*parsed.identifier_storage);
}

make_token_span :: inline (first: s64, one_past_last: s64) -> Token_Span {
	assert(first >= 0);
	assert(one_past_last >= first);
	return .{ first = xx first, one_past_last = xx one_past_last };
}

Lexer_Error :: struct {
	message: string;
	line: s32;
	column: s32;
	details: [..]string;
}

collect_lexer_error :: (lexer: *Lexer, message: string, line: s32, column: s32) {
	errors := lexer.user_data.(*[..]Lexer_Error);
	array_add(errors, .{message = copy_string(message), line = line, column = column});
}

collect_lexer_detail :: (lexer: *Lexer, message: string) {
	errors := lexer.user_data.(*[..]Lexer_Error);
	assert(errors.count > 0);
	array_add(*errors.data[errors.count - 1].details, copy_string(message));
}

token_at :: (parsed: *Parsed_Source, index: Token_Index) -> *Parser_Token #expand {
	return *parsed.tokens[xx index];
}

previous_token :: inline (parsed: *Parsed_Source, index: Token_Index) -> *Parser_Token {
	raw_index := index.(s64);
	return ifx (raw_index > 0)
		then *parsed.tokens[raw_index - 1]
		else null;
}

next_token :: inline (parsed: *Parsed_Source, index: Token_Index) -> *Parser_Token {
	raw_index := index.(s64);
	return ifx (raw_index >= 0 && raw_index + 1 < parsed.tokens.count)
		then *parsed.tokens[raw_index + 1]
		else null;
}


#scope_file

// Common setup for parsing functions:
parseInit :: (
	source: string,
	rootParser: (*Parser) -> *Parser_Node,
	fully_pathed_filename: string = "",
	warn_unnecessary_semicolons: bool = false,
	materialised: *Parsed_Source = null,
	edit_source: *Parsed_Source = null,
	edit_start: s64 = 0,
	edit_end: s64 = 0
) -> *Parsed_Source, Parser #expand {
	parser: Parser;
	parser.edit_source = edit_source;
	parser.edit_start = edit_start;
	parser.edit_end = edit_end;
	parser.warn_unnecessary_semicolons = warn_unnecessary_semicolons;
	parser.parsed = ifx materialised
		then materialised
		else *materialise_tokens(source);

	parser.parsed.fully_pathed_filename = fully_pathed_filename;
	set_allocators(*parser.parsed.node_pool);
	parser.parsed.root_scope = push_lexical_scope(*parser);
	parser.parsed.root = rootParser(*parser);
	resolve_lexical_references(parser.parsed.root_scope);
	return parser.parsed, parser;
}

#scope_export

// Parse one value expression, such as `call(x + 1)`, rather than a statement or file.
// Empty input and trailing tokens are diagnosed.  The result retains tokens, diagnostics, a root expression, and lexical bindings; source and filename are borrowed until release.
// Warning mode reports optional semicolons where applicable without changing parse status.
parse_expression :: (source: string, fully_pathed_filename: string = "", warn_unnecessary_semicolons: bool = false) -> Parsed_Source {
	result, parser := parseInit(source, p => parse_value_expression(p), fully_pathed_filename, warn_unnecessary_semicolons);

	if !result.root && !result.diagnostics.count {
		add_expected_expression(*parser);
	} else if parser_peek(*parser).type != .END_OF_INPUT {
		add_unexpected_token(*parser);
	}

	return result;
}

// Parse a single declaration, such as `answer: s64 = 42;`, including trailing notes.
// An optional final semicolon is consumed; further input is diagnosed rather than silently becoming another declaration.
// The returned tree, tokens, and diagnostics follow the same borrowed-source and independent tree/name release rules as parse_file.
parse_declaration :: (source: string, fully_pathed_filename: string = "", warn_unnecessary_semicolons: bool = false) -> Parsed_Source {
	result, parser := parseInit(source, p => parse_declaration_node(p), fully_pathed_filename, warn_unnecessary_semicolons);

	if !result.root && !result.diagnostics.count {
		add_expected_expression(*parser);
	}

	if parser_peek(*parser).type == #char ";" {
		if warn_unnecessary_semicolons && result.root && !statement_requires_semicolon(result.root) {
			add_unnecessary_semicolon(*parser);
		}

		parser_eat(*parser);
	}

	if result.root {
		parse_declaration_notes(*parser, result.root);
	}

	if result.root && parser_peek(*parser).type != .END_OF_INPUT {
		add_unexpected_token(*parser);
	}

	return result;
}

// Parse one braced imperative block, such as `{ value := 1; return value; }`.
// The root is a Parser_Block; missing braces and unexpected input after the block produce diagnostics while retaining the partial tree for editor use.  Input is borrowed.
parse_block :: (source: string, fully_pathed_filename: string = "", warn_unnecessary_semicolons: bool = false) -> Parsed_Source {
	result, parser := parseInit(source, p => parse_block_node(p).(*Parser_Node), fully_pathed_filename, warn_unnecessary_semicolons);

	if !result.root && !result.diagnostics.count {
		add_expected_expression(*parser);
	} else if parser_peek(*parser).type != .END_OF_INPUT {
		add_unexpected_token(*parser);
	}

	return result;
}

// Parse one braced DATA_DECLARATIONS block, such as a struct member body.
// Unlike parse_block, its contents use declaration grammar.  A missing delimiter or trailing input is diagnosed, and the partial tree remains available for recovery.
// The returned source and filename are borrowed, as with the other parse entrypoints.
parse_declaration_block :: (source: string, fully_pathed_filename: string = "", warn_unnecessary_semicolons: bool = false) -> Parsed_Source {
	result, parser := parseInit(
		source,
		(parser) => parse_block_node(parser, block_type=.DATA_DECLARATIONS).(*Parser_Node),
		fully_pathed_filename, warn_unnecessary_semicolons
	);

	if !result.root && !result.diagnostics.count {
		add_expected_expression(*parser);
	} else if parser_peek(*parser).type != .END_OF_INPUT {
		add_unexpected_token(*parser);
	}

	return result;
}

// Parse all top-level declarations into an unbraced DATA_DECLARATIONS block.
// Empty files still have a root; malformed regions retain partial declarations and diagnostics while parsing continues.
// The returned snapshot borrows source and filename; retain both while inspecting tokens, source spans, or the tree.
// Release the tree separately from retained tokens and optional interned identifier names.
parse_file :: (source: string, fully_pathed_filename: string = "", warn_unnecessary_semicolons: bool = false) -> Parsed_Source {
	result, parser := parseInit(source, parse_file_node, fully_pathed_filename, warn_unnecessary_semicolons);
	return result;
}

// Parse a complete replacement snapshot after one edit to old.source's byte range [start, end).
// The unchanged prefix and suffix must match exactly; otherwise return an empty result and false without parsing.
// On success, retain the old filename and return a new, independently owned tree and token snapshot.
// Unchanged syntax may be copied only when eligible; other regions are reparsed.
// Keep both source buffers alive while their snapshots are in use, and pass warning mode again if it was enabled.
parse_file_edit :: (old: *Parsed_Source, start: s64, end: s64, new_source: string, warn_unnecessary_semicolons: bool = false) -> Parsed_Source, bool {
	old_source := old.source;
	if start >= 0 && end >= start && end <= old_source.count {
		inserted_count := new_source.count - (old_source.count - (end - start));
		if inserted_count >= 0 {
			if (
				slice(new_source, 0, start) == slice(old_source, 0, start)
				&& slice(new_source, start + inserted_count, old_source.count - end) == slice(old_source, end, old_source.count - end)
			) {
				materialised := materialise_tokens(new_source, old, start, end);
				result, parser := parseInit(new_source, parse_file_node, old.fully_pathed_filename, warn_unnecessary_semicolons, *materialised, old, start, end);
				return result, true;
			}
		}
	}


	return .{}, false;
}

// Keep parsing declarations after an error, but force progress when recovery lands on another possible declaration start.
parse_file_node :: (parser: *Parser) -> *Parser_Node {
	first := parser.cursor;
	result := new_parser_node(parser, Parser_Block);
	result.kind = .BLOCK;
	result.block_type = .DATA_DECLARATIONS;
	parser.current_scope.owner = result;

	statements: [..]*Parser_Node;
	statements.allocator = parser_node_allocator(parser.parsed);

	while parser_peek(parser).type != .END_OF_INPUT {
		guard := parser_progress_guard(parser);
		declaration := reuse_simple_declaration(parser);
		if !declaration {
			declaration = parse_declaration_node(parser);
		}

		if declaration {
			array_add(*statements, declaration);
			finish_statement(parser, declaration);
		} else {
			if parser_peek(parser).type == .END_OF_INPUT {
				add_expected_expression(parser);
				break;
			}


			add_unexpected_token(parser);
			parser_synchronise(parser, .DECLARATION);
		}

		if !parser_ensure_progress(parser, guard) {
			break;
		}
	}

	result.statements = statements;
	if parser.cursor > first {
		finish_node(parser, result, first);
	} else {
		set_empty_node_location(parser, result, first);
	}

	return result;
}

// Reuse only declarations whose token boundaries and dependencies can be mapped unambiguously across the edit.
// The old tree is a template, never shared: reject metadata and expression shapes that cannot be cloned into the new pool with new-source names, spans, and lexical links.
reuse_simple_declaration :: (parser: *Parser) -> *Parser_Node {
	#if ENABLE_TRIVIA {
		old := parser.edit_source;
		if !old || old.status != .COMPLETE || !old.root || old.root.kind != .BLOCK {
			return null;
		}


		old_statements := ifx parser.reuse_block
			then parser.reuse_block.statements
			else old.root.(*Parser_Block).statements;

		new_byte := parser.parsed.tokens[parser.cursor].byte_start;
		byte_delta := parser.parsed.source.count - old.source.count;
		inserted_count := byte_delta + parser.edit_end - parser.edit_start;
		if new_byte >= parser.edit_start && new_byte < parser.edit_start + inserted_count {
			return null;
		}


		old_byte := ifx new_byte < parser.edit_start
			then new_byte
			else new_byte - byte_delta;

		// Advance past old declarations before this byte position; never pair by array index alone.
		while parser.reuse_statement_index < old_statements.count {
			it := old_statements[parser.reuse_statement_index];
			candidate_byte := old.tokens[it.first_token.(s64)].byte_start;
			if candidate_byte < old_byte {
				parser.reuse_statement_index += 1;
				continue;
			}


			if candidate_byte > old_byte || (it.kind != .DECLARATION && it.kind != .COMPOUND_DECLARATION) {
				return null;
			}


			first := it.first_token.(s64);
			last := it.one_past_last_token.(s64);
			if last - first < 3 || old.tokens[last].type != #char ";" {
				return null;
			}


			previous: *Parser_Declaration;
			compound: *Parser_Compound_Declaration;
			typed := false;
			typed_compound := false;
			reassignment_compound := false;
			if it.kind == .DECLARATION {
				previous = it.(*Parser_Declaration);
				typed = previous.type_inst != null;
				without_initializer := typed && !previous.expression;
				expression_first := ifx typed
					then previous.type_inst.one_past_last_token.(s64) + 1
					else first + 3;
				// Require a whole, simple declaration; partial token matches could reuse stale children.
				if (
					!without_initializer && (
						!reusable_expression(previous.expression)
						|| previous.expression.first_token.(s64) != expression_first
						|| previous.expression.one_past_last_token.(s64) != last
					)
					|| previous.notes.count
					|| previous.alignment_expression
					|| previous.import_target
					|| old.tokens[first].type != .IDENT || old.tokens[first + 1].type != #char ":"
					|| (ifx typed
							then (
								!reusable_type_instantiation(previous.type_inst)
								|| previous.type_inst.first_token.(s64) != first + 2
								|| (ifx without_initializer
										then previous.type_inst.one_past_last_token.(s64) != last
										else old.tokens[expression_first - 1].type != #char ":" && old.tokens[expression_first - 1].type != #char "="
								)
							) else old.tokens[first + 2].type != #char ":" && old.tokens[first + 2].type != #char "="
					)
				) {
					return null;
				}
			} else {
				compound = it.(*Parser_Compound_Declaration);
				properties := compound.declaration_properties;
				arguments := compound.comma_separated_assignment;
				if !properties || !arguments || arguments.arguments.count < 2 {
					return null;
				}


				argument_count := arguments.arguments.count;
				separator_at := first + 2 * argument_count - 1;
				typed_compound = properties.type_inst != null;
				reassignment_compound = compound.operator_type == #char "=";
				without_initializer := typed_compound && !properties.expression;
				expression_first := ifx typed_compound
					then properties.type_inst.one_past_last_token.(s64) + 1
					else ifx reassignment_compound
						then separator_at + 1
						else separator_at + 2;

				// Compound names must occupy the expected comma-separated slots, with no hidden metadata.
				if (last - first < (ifx without_initializer || reassignment_compound then 2 * argument_count + 1 else 2 * argument_count + 2)
					|| compound.notes.count
					|| compound.alignment_expression
					|| properties.notes.count
					|| properties.alignment_expression
					|| properties.import_target
					|| !without_initializer && (
						!reusable_expression(properties.expression)
						|| properties.expression.first_token.(s64) != expression_first
						|| properties.expression.one_past_last_token.(s64) != last
					)
					|| arguments.first_token.(s64) != first || arguments.one_past_last_token.(s64) != separator_at + 1
					|| (ifx reassignment_compound
							then typed_compound || old.tokens[separator_at].type != #char "="
							else old.tokens[separator_at].type != #char ":"
					)
					|| (ifx typed_compound
							then (!reusable_type_instantiation(properties.type_inst)
								|| properties.type_inst.first_token.(s64) != separator_at + 1
								|| (ifx without_initializer
										then properties.type_inst.one_past_last_token.(s64) != last
										else old.tokens[expression_first - 1].type != #char ":" && old.tokens[expression_first - 1].type != #char "=")
								)
							else !reassignment_compound && old.tokens[separator_at + 1].type != #char ":"
					)
				) {
					return null;
				}


				// Each target must be one identifier, not a member, index, or mixed assignment.
				for arguments.arguments {
					argument_first := first + 2 * it_index;
					if (it.modifier != .NONE
						|| !it.node
						|| it.node.kind != .IDENT
						|| it.node.first_token.(s64) != argument_first
						|| it.node.one_past_last_token.(s64) != argument_first + 1
						|| old.tokens[argument_first].type != .IDENT
						|| it_index < argument_count - 1 && old.tokens[argument_first + 1].type != #char ","
					 ) {
						return null;
					}
				}
			}


			shift: s64;
			if old.tokens[last - 1].byte_end <= parser.edit_start {
				shift = 0;
			} else if old.tokens[first].byte_start >= parser.edit_end {
				shift = byte_delta;
			} else {
				return null;
			}


			count := last - first;
			if (parser.parsed.tokens.count - parser.cursor <= count
				|| parser.parsed.tokens[parser.cursor + count].type != #char ";"
				|| parser.parsed.tokens[parser.cursor].byte_start != old.tokens[first].byte_start + shift
			) {
				return null;
			}


			matches := true;
			for offset: 0..count-1 {
				before := old.tokens[first + offset];
				after := parser.parsed.tokens[parser.cursor + offset];
				if (before.type != after.type
					|| before.value_flags != after.value_flags
					|| before.original_text != after.original_text
				) {
					matches = false;
					break;
				}
			}

			if !matches {
				return null;
			}


			start := parser.cursor;
			parser.cursor += count;
			// Rebuild the argument list and declaration properties so no old-pool pointers escape.
			if compound {
				old_arguments := compound.comma_separated_assignment;
				arguments := new_parser_node(parser, Parser_Comma_Separated_Arguments);
				arguments.* = old_arguments.*;
				arguments.first_token = xx start;
				arguments.one_past_last_token = xx (start + 2 * old_arguments.arguments.count);
				copied_arguments: [..]Parser_Comma_Separated_Argument;
				copied_arguments.allocator = parser_node_allocator(parser.parsed);
				for old_arguments.arguments {
					argument := it;
					argument.node = copy_reusable_expression(parser, it.node, start - first, false);
					array_add(*copied_arguments, argument);
				}

				arguments.arguments = copied_arguments;

				properties := new_parser_node(parser, Parser_Declaration);
				properties.* = compound.declaration_properties.*;
				if typed_compound {
					properties.type_inst = copy_reusable_type_instantiation(parser, compound.declaration_properties.type_inst, start - first);
				}

				properties.expression = ifx compound.declaration_properties.expression
					then copy_reusable_expression(parser, compound.declaration_properties.expression, start - first)
					else null;
				declaration := new_parser_node(parser, Parser_Compound_Declaration);
				declaration.* = compound.*;
				declaration.comma_separated_assignment = arguments;
				declaration.declaration_properties = properties;
				finish_node(parser, declaration, start);
				if !reassignment_compound {
					for copied_arguments {
						array_add(*parser.current_scope.bindings, Parser_Binding.{name = it.node.(*Parser_Ident).name, declaration = properties});
					}
				}

				return declaration;
			}


			type_inst: *Parser_Type_Instantiation;
			if typed {
				type_inst = copy_reusable_type_instantiation(parser, previous.type_inst, start - first);
			}

			expression := ifx previous.expression
				then copy_reusable_expression(parser, previous.expression, start - first)
				else null;

			declaration := new_parser_node(parser, Parser_Declaration);
			declaration.* = previous.*;
			declaration.name = parser.parsed.tokens[start].ident_value.name;
			declaration.type_inst = type_inst;
			declaration.expression = expression;
			finish_node(parser, declaration, start);
			return declaration;
		}
	}


	return null;
}

// Match by source position and block kind so nested declarations reuse candidates from their own lexical scope.
find_old_declaration_block :: (parser: *Parser, scope: *Parser_Lexical_Scope, first: s64, block_type: type_of(Code_Block.block_type)) -> *Parser_Block {
	#if ENABLE_TRIVIA {
		old := parser.edit_source;
		if !old || old.status != .COMPLETE || !old.root_scope {
			return null;
		}


		new_token := parser.parsed.tokens[first];
		byte_delta := parser.parsed.source.count - old.source.count;
		inserted_count := byte_delta + parser.edit_end - parser.edit_start;
		if new_token.byte_start >= parser.edit_start && new_token.byte_start < parser.edit_start + inserted_count {
			return null;
		}


		old_byte := ifx new_token.byte_start < parser.edit_start
			then new_token.byte_start
			else new_token.byte_start - byte_delta;

		// Nested candidates belong to the same braced block, even if another block has the same start offset.
		for scope.children {
			if it.owner && it.owner.kind == .BLOCK {
				block := it.owner.(*Parser_Block);
				old_token := old.tokens[block.first_token.(s64)];
				if ((!parser.current_scope || (ifx parser.reuse_block then scope.owner == parser.reuse_block else scope == old.root_scope))
					&& block.block_type == block_type
					&& old_token.type == #char "{"
					&& old_token.byte_start == old_byte
					&& (old_token.byte_end <= parser.edit_start || old_token.byte_start >= parser.edit_end)
				) {
					close_index := block.one_past_last_token.(s64) - 1;
					if close_index >= 0 && close_index < old.tokens.count {
						old_close := old.tokens[close_index];
						if (old_close.type == #char "}"
							&& (old_close.byte_end <= parser.edit_start || old_close.byte_start >= parser.edit_end)
						) {
							depth := 0;
							for index: first..parser.parsed.tokens.count-1 {
								token := parser.parsed.tokens[index];
								if token.type == #char "{" {
									depth += 1;
								} else if token.type == #char "}" {
									depth -= 1;
									if depth == 0 {
										if token.byte_start == old_close.byte_start + (ifx old_close.byte_start >= parser.edit_end then byte_delta else 0) {
											return block;
										}


										break;
									}
								}
							}
						}
					}
				}
			}


			found := find_old_declaration_block(parser, it, first, block_type);
			if found {
				return found;
			}
		}
	}


	return null;
}

reusable_type_instantiation :: (original: *Parser_Type_Instantiation) -> bool {
	#if ENABLE_TRIVIA {
		if !original {
			return false;
		}


		if original.pointer_to {
			return original.pointer_to.first_token.(s64) == original.first_token.(s64) + 1
				&& original.one_past_last_token == original.pointer_to.one_past_last_token
				&& reusable_type_instantiation(original.pointer_to);
		}


		// A wrapper is reusable only when its element and dimension consume the exact source shape.
		if original.array_element_type {
			return (
				original.array_dimension
					&& original.inst_flags == 0
					&& original.array_dimension.first_token.(s64) == original.first_token.(s64) + 1
					&& original.array_dimension.one_past_last_token.(s64) + 1 == original.array_element_type.first_token.(s64)
					&& reusable_expression(original.array_dimension)
					|| !original.array_dimension
						&& (
							original.inst_flags == .ARRAY_VIEW && original.array_element_type.first_token.(s64) == original.first_token.(s64) + 2
							|| original.inst_flags == .RESIZABLE && original.array_element_type.first_token.(s64) == original.first_token.(s64) + 3
						)
					)
					&& original.one_past_last_token == original.array_element_type.one_past_last_token
					&& reusable_type_instantiation(original.array_element_type);
		}


		return original.type_valued_expression && original.type_valued_expression.kind == .IDENT
			&& original.one_past_last_token.(s64) == original.first_token.(s64) + 1;
	}


	return false;
}

copy_reusable_type_instantiation :: (parser: *Parser, original: *Parser_Type_Instantiation, token_delta: s64) -> *Parser_Type_Instantiation {
	#if ENABLE_TRIVIA {
		if !original.pointer_to && !original.array_element_type {
			type_expression := copy_reusable_expression(parser, original.type_valued_expression, token_delta);
			return make_type_instantiation(parser, type_expression);
		}


		wrapper := new_parser_node(parser, Parser_Type_Instantiation);
		wrapper.* = original.*;
		if original.pointer_to {
			wrapper.pointer_to = copy_reusable_type_instantiation(parser, original.pointer_to, token_delta);
		} else {
			if original.array_dimension {
				wrapper.array_dimension = copy_reusable_expression(parser, original.array_dimension, token_delta);
			}
			wrapper.array_element_type = copy_reusable_type_instantiation(parser, original.array_element_type, token_delta);
		}

		first := original.first_token.(s64) + token_delta;
		last := original.one_past_last_token.(s64) + token_delta;
		wrapper.first_token = xx first;
		wrapper.one_past_last_token = xx last;
		wrapper.l0 = parser.parsed.tokens[first].l0;
		wrapper.c0 = parser.parsed.tokens[first].c0;
		wrapper.l1 = parser.parsed.tokens[last - 1].l1;
		wrapper.c1 = parser.parsed.tokens[last - 1].c1;
		return wrapper;
	}


	return null;
}

// Whitelist expression shapes that can be cloned without retaining old-source references or stale scope links.
reusable_expression :: (node: *Parser_Node) -> bool {
	#if ENABLE_TRIVIA {
		if !node {
			return false;
		}


		if node.kind == .IDENT {
			return true;
		}


		// Literal values with self-contained members, such as `[1, 2]` or `.{x = 1}`, can be rebuilt; contextual here strings and unsupported payloads cannot.
		if node.kind == .LITERAL {
			literal := node.(*Parser_Literal);
			if literal.value_type == .ARRAY {
				info := literal.array_literal_info;
				if (!info
					|| info.alignment
					|| info.element_type && (
						!info.element_type.type_valued_expression
						|| info.element_type.type_valued_expression.kind != .IDENT
					)
				) {
					return false;
				}


				for info.array_members {
					if !reusable_expression(it) {
						return false;
					}
				}


				return true;
			}


			if literal.value_type == .STRUCT {
				info := literal.struct_literal_info;
				if (!info
					|| info.type_expression && (
						!info.type_expression.type_valued_expression
						|| info.type_expression.type_valued_expression.kind != .IDENT
					)
				) {
					return false;
				}


				for info.arguments {
					if !reusable_expression(it) {
						return false;
					}
				}


				return true;
			}


			return literal.value_type == .NUMBER
				|| literal.value_type == .BOOLEAN
				|| literal.value_type == .STRING && !(literal.value_flags & .HERE_STRING)
					&& literal.one_past_last_token.(s64) == literal.first_token.(s64) + 1;
		}


		if node.kind == .UNARY_OPERATOR {
			unary := node.(*Parser_Unary_Operator);
			return (
					unary.operator_type == #char "!"
					|| unary.operator_type == #char "~"
					|| unary.operator_type == #char "+"
					|| unary.operator_type == #char "-"
					|| unary.operator_type == #char "*"
					|| unary.operator_type == .POINTER_DEREFERENCE
					|| unary.operator_type == .POSTFIX_DEREFERENCE
				)
				&& reusable_expression(unary.subexpression);
		}


		if node.kind == .EXPRESSION_QUERY {
			query := node.(*Parser_Expression_Query);
			return (query.query_kind == .TYPE_OF || query.query_kind == .IS_CONSTANT || query.query_kind == .CODE_OF)
				&& query.expression_to_query
				&& query.expression_to_query.first_token.(s64) == query.first_token.(s64) + 2
				&& query.expression_to_query.one_past_last_token.(s64) + 1 == query.one_past_last_token.(s64)
				&& reusable_expression(query.expression_to_query);
		}


		if node.kind == .TYPE_QUERY {
			query := node.(*Parser_Type_Query);
			return (query.query_kind == .SIZE_OF || query.query_kind == .TYPE_INFO || query.query_kind == .INITIALIZER_OF)
				&& query.type_to_query
				&& query.type_to_query.first_token.(s64) == query.first_token.(s64) + 2
				&& query.type_to_query.one_past_last_token.(s64) + 1 == query.one_past_last_token.(s64)
				&& reusable_type_instantiation(query.type_to_query);
		}


		if node.kind == .PROCEDURE_CALL {
			call := node.(*Parser_Procedure_Call);
			if !reusable_expression(call.procedure_expression) {
				return false;
			}


			for call.arguments_unsorted {
				if (it.name && it.name.kind != .IDENT) || !reusable_expression(it.expression) {
					return false;
				}
			}


			if call.context_modification {
				for call.context_modification.modification_expressions {
					if !reusable_expression(it) {
						return false;
					}
				}
			}


			return true;
		}


		if node.kind == .CAST {
			cast_node := node.(*Parser_Cast);
			return reusable_type_instantiation(cast_node.target_type)
				&& reusable_expression(cast_node.expression);
		}


		if node.kind == .BINARY_OPERATOR {
			binary := node.(*Parser_Binary_Operator);
			if binary.operator_type == #char "." {
				return binary.right && binary.right.kind == .IDENT
					&& (binary.right.(*Parser_Ident).flags & .IS_RHS_OF_DOT_DEREFERENCE) != 0
					&& reusable_expression(binary.left);
			}


			if binary.operator_type == .ARRAY_SUBSCRIPT {
				return reusable_expression(binary.left) && reusable_expression(binary.right);
			}


			if (binary.operator_type != #char "+"
				&& binary.operator_type != #char "-"
				&& binary.operator_type != #char "*"
				&& binary.operator_type != #char "/"
				&& binary.operator_type != #char "%"
				&& binary.operator_type != .IS_EQUAL
				&& binary.operator_type != .IS_NOT_EQUAL
				&& binary.operator_type != #char "<"
				&& binary.operator_type != .LESS_OR_EQUAL
				&& binary.operator_type != #char ">"
				&& binary.operator_type != .GREATER_OR_EQUAL
				&& binary.operator_type != .LOGICAL_AND
				&& binary.operator_type != .LOGICAL_OR
				&& binary.operator_type != #char "&"
				&& binary.operator_type != #char "|"
				&& binary.operator_type != #char "^"
				&& binary.operator_type != .SHIFT_LEFT
				&& binary.operator_type != .SHIFT_RIGHT
				&& binary.operator_type != .ROTATE_LEFT
				&& binary.operator_type != .ROTATE_RIGHT
			) {
				return false;
			}


			return reusable_expression(binary.left) && reusable_expression(binary.right);
		}
	}

	return false;
}

copy_reusable_expression :: (parser: *Parser, original: *Parser_Node, token_delta: s64, register_reference: bool = true) -> *Parser_Node {
	#if ENABLE_TRIVIA {
		first := original.first_token.(s64) + token_delta;
		last := original.one_past_last_token.(s64) + token_delta;
		result: *Parser_Node;

		// Clone only the shapes approved by reusable_expression; each case below reconstructs children or source-backed names instead of keeping old pointers.
		if original.kind == {
			// Literal payloads, e.g. `"hi"` or `[1, 2]`, need new token text or member storage.
			case .LITERAL;
				literal := new_parser_node(parser, Parser_Literal);
				literal.* = original.(*Parser_Literal).*;
				if literal.value_type == {
					case .STRING;
						for index: first..last-1 {
							if parser.parsed.tokens[index].type == .STRING {
								literal._string = parser.parsed.tokens[index].string_value;
								break;
							}
						}

					case .ARRAY;
						old_info := original.(*Parser_Literal).array_literal_info;
						info := new_parser_node(parser, Parser_Array_Literal_Info);
						info.* = old_info.*;
						if old_info.element_type {
							type_expression := copy_reusable_expression(parser, old_info.element_type.type_valued_expression, token_delta);
							info.element_type = make_type_instantiation(parser, type_expression);
						}

						members: [..]*Parser_Node;
						members.allocator = parser_node_allocator(parser.parsed);
						for old_info.array_members {
							array_add(*members, copy_reusable_expression(parser, it, token_delta));
						}

						info.array_members = members;
						literal.array_literal_info = info;

					case .STRUCT;
						old_info := original.(*Parser_Literal).struct_literal_info;
						info := new_parser_node(parser, Parser_Struct_Literal_Info);
						info.* = old_info.*;
						if old_info.type_expression {
							type_expression := copy_reusable_expression(parser, old_info.type_expression.type_valued_expression, token_delta);
							info.type_expression = make_type_instantiation(parser, type_expression);
						}

						members: [..]*Parser_Node;
						members.allocator = parser_node_allocator(parser.parsed);
						for old_info.arguments {
							array_add(*members, copy_reusable_expression(parser, it, token_delta));
						}

						info.arguments = members;
						literal.struct_literal_info = info;
				}

				result = literal;

			// Identifier `value` gets its new token spelling and a fresh scope reference.
			case .IDENT;
				ident := new_parser_node(parser, Parser_Ident);
				ident.* = original.(*Parser_Ident).*;
				for index: first..last-1 {
					if parser.parsed.tokens[index].type == .IDENT {
						ident.name = parser.parsed.tokens[index].ident_value.name;
						break;
					}
				}

				ident.resolved_declaration = null;
				if register_reference {
					array_add(*parser.current_scope.references, ident);
				}

				result = ident;

			// Prefix or postfix unary `-value` / `value.*` clones its operand.
			case .UNARY_OPERATOR;
				unary := new_parser_node(parser, Parser_Unary_Operator);
				unary.* = original.(*Parser_Unary_Operator).*;
				unary.subexpression = copy_reusable_expression(parser, unary.subexpression, token_delta);
				result = unary;

			// Expression query `type_of(value)` clones the queried expression.
			case .EXPRESSION_QUERY;
				query := new_parser_node(parser, Parser_Expression_Query);
				query.* = original.(*Parser_Expression_Query).*;
				query.expression_to_query = copy_reusable_expression(parser, query.expression_to_query, token_delta);
				result = query;

			// Type query `size_of(T)` clones the type wrapper and its dependencies.
			case .TYPE_QUERY;
				query := new_parser_node(parser, Parser_Type_Query);
				query.* = original.(*Parser_Type_Query).*;
				query.type_to_query = copy_reusable_type_instantiation(parser, query.type_to_query, token_delta);
				result = query;

			// Call `f(x, name=y)` rebuilds argument labels, values, and context replacements.
			case .PROCEDURE_CALL;
				old_call := original.(*Parser_Procedure_Call);
				call := new_parser_node(parser, Parser_Procedure_Call);
				call.* = old_call.*;
				call.procedure_expression = copy_reusable_expression(parser, old_call.procedure_expression, token_delta);
				arguments: [..]Parser_Argument;
				arguments.allocator = parser_node_allocator(parser.parsed);
				for old_call.arguments_unsorted {
					argument := it;
					if it.name {
						argument.name = copy_reusable_expression(parser, it.name, token_delta, false).(*Parser_Ident);
					}

					argument.expression = copy_reusable_expression(parser, it.expression, token_delta);
					array_add(*arguments, argument);
				}

				call.arguments_unsorted = arguments;
				if old_call.context_modification {
					modification := New(Parser_Context_Modification,, parser_node_allocator(parser.parsed));
					expressions: [..]*Parser_Node;
					expressions.allocator = parser_node_allocator(parser.parsed);
					for old_call.context_modification.modification_expressions {
						array_add(*expressions, copy_reusable_expression(parser, it, token_delta));
					}

					modification.modification_expressions = expressions;
					call.context_modification = modification;
				}

				result = call;

			// Cast `cast(T) value` rebuilds the type and value separately.
			case .CAST;
				old_cast := original.(*Parser_Cast);
				cast_node := new_parser_node(parser, Parser_Cast);
				cast_node.* = old_cast.*;
				cast_node.target_type = copy_reusable_type_instantiation(parser, old_cast.target_type, token_delta);
				cast_node.expression = copy_reusable_expression(parser, old_cast.expression, token_delta);
				result = cast_node;

			// Binary `left + right` rebuilds both operands before remapping the span.
			case .BINARY_OPERATOR;
				binary := new_parser_node(parser, Parser_Binary_Operator);
				binary.* = original.(*Parser_Binary_Operator).*;
				old_binary := original.(*Parser_Binary_Operator);
				binary.left = copy_reusable_expression(parser, old_binary.left, token_delta);
				binary.right = copy_reusable_expression(parser, old_binary.right, token_delta);
				result = binary;

			// Any newly approved expression kind needs an explicit copy rule first.
			case;
				assert(false, "Unexpected reusable node kind: %", original.kind);
				return null;
		}

		result.first_token = xx first;
		result.one_past_last_token = xx last;
		first_token := parser.parsed.tokens[first];
		last_token := parser.parsed.tokens[last - 1];
		result.l0 = first_token.l0;
		result.c0 = first_token.c0;
		result.l1 = last_token.l1;
		result.c1 = last_token.c1;
		return result;
	}


	return null;
}

// Scope reuse to this block and restore the parent's candidates when nested blocks return.
parse_block_node :: (parser: *Parser, parent: *Parser_Block = null, block_type := Code_Block.block_type.IMPERATIVE, enum_members := false) -> *Parser_Block {
	first := parser.cursor;
	if !parser_eat_if(parser, #char "{") {
		return null;
	}


	reuse_block := parser.reuse_block;
	reuse_statement_index := parser.reuse_statement_index;
	parser.reuse_block = ifx block_type == .DATA_DECLARATIONS && !enum_members && parser.edit_source && parser.edit_source.root_scope
		then find_old_declaration_block(parser, parser.edit_source.root_scope, first, block_type)
		else null;

	parser.reuse_statement_index = 0;
	defer {
		parser.reuse_block = reuse_block;
		parser.reuse_statement_index = reuse_statement_index;
	}

	parent_scope := parser.current_scope;
	push_lexical_scope(parser);
	defer parser.current_scope = parent_scope;

	result := new_parser_node(parser, Parser_Block);
	result.kind = .BLOCK;
	parser.current_scope.owner = result;
	result.node_flags |= .IS_PARENTHESIZED;
	result.parent = parent;
	result.block_type = block_type;

	statements: [..]*Parser_Node;
	statements.allocator = parser_node_allocator(parser.parsed);

	token := parser_peek(parser);
	// Keep declaration, enum, and imperative grammars in the same scoped recovery loop.
	while token.type != #char "}" && token.type != .END_OF_INPUT {
		guard := parser_progress_guard(parser);
		statement: *Parser_Node;
		if enum_members && parser_peek(parser).type == .IDENT && parser_peek(parser, 1).type == #char ";" {
			statement = parse_enum_member(parser);
		} else if enum_members && parser_peek_if(parser, #char "#", .KEYWORD_IF) {
			statement = parse_static_if_statement(parser, result, .DATA_DECLARATIONS, true);
		} else if block_type == .DATA_DECLARATIONS {
			if parser.reuse_block {
				statement = reuse_simple_declaration(parser);
			}

			if !statement {
				statement = parse_declaration_node(parser);
			}
		} else {
			statement = parse_statement(parser, result);
		}

		if statement {
			array_add(*statements, statement);
			finish_statement(parser, statement);
		} else {
			add_unexpected_token(parser);
			parser_synchronise(parser, .STATEMENT);
		}


		if !parser_ensure_progress(parser, guard) {
			break;
		}


		token = parser_peek(parser);
	}

	parser_expect(parser, #char "}");

	result.statements = statements;
	finish_node(parser, result, first);
	return result;
}

finish_statement :: (parser: *Parser, statement: *Parser_Node) {
	if parser_peek(parser).type == #char ";" {
		if parser.warn_unnecessary_semicolons && !statement_requires_semicolon(statement) {
			add_unnecessary_semicolon(parser);
		}

		parser_eat(parser);
	} else if statement_requires_semicolon(statement) {
		parser_expect(parser, #char ";");
	}

	if statement.kind == .DECLARATION || statement.kind == .COMPOUND_DECLARATION {
		parse_declaration_notes(parser, statement);
	}
}

add_unnecessary_semicolon :: (parser: *Parser) {
	array_add(
		*parser.parsed.diagnostics,
		Parse_Diagnostic.{
			kind = .UNNECESSARY_SEMICOLON,
			severity = .WARNING,
			span = make_token_span(parser.cursor, parser.cursor + 1),
			message = "Semicolon is unnecessary here.",
			actual_token = #char ";"
		}
	);
}

// Decide by the parsed form, not just its leading token: block-bodied expressions can terminate without a semicolon.
statement_requires_semicolon :: (statement: *Parser_Node) -> bool {
	if statement.kind == {
		case .IF;
			return ((statement.(*Parser_If).if_flags & .IS_IFX) != 0);

		case .DIRECTIVE_RUN;
			return statement.(*Parser_Directive_Run).expression == null
				|| statement.(*Parser_Directive_Run).expression.kind != .BLOCK;

		case .DIRECTIVE_INSERT;
			expression := statement.(*Parser_Directive_Insert).expression;
			if expression && expression.kind == .DIRECTIVE_RUN {
				run := expression.(*Parser_Directive_Run);
				if run.procedure && run.expression && run.expression.kind == .BLOCK {
					return false;
				}
			}

		case .USING;
			expression := statement.(*Parser_Using).expression;
			if expression && expression.kind == .ENUM {
				return false;
			}

		// A braced value `ifx` ends a declaration at `}`, like `x := ifx ok { 1 } else { 2 }`.
		case .DECLARATION;
			expression := statement.(*Parser_Declaration).expression;
			if expression {
				if expression.kind == .IF {
					conditional := expression.(*Parser_If);
					if (conditional.if_flags & .IS_IFX
						&& conditional.then_block
						&& conditional.else_block
						&& conditional.then_block.node_flags & .IS_PARENTHESIZED
						&& conditional.else_block.node_flags & .IS_PARENTHESIZED
					) {
						return false;
					}
				}


				if expression.kind == .LITERAL && (expression.(*Parser_Literal).value_flags & .HERE_STRING) {
					return false;
				}


				if expression.kind == .DIRECTIVE_RUN {
					run := expression.(*Parser_Directive_Run);
					if run.procedure && run.expression && run.expression.kind == .BLOCK {
						return false;
					}
				}


				if expression.kind == .STRUCT || expression.kind == .ENUM {
					return false;
				}


				if expression.kind == .PROCEDURE_HEADER {
					header := expression.(*Parser_Procedure_Header);
					if header.body_or_null {
						return header.procedure_flags & .QUICK != 0
							&& header.procedure_flags & .QUICK_IN_BLOCK_FORM == 0;
					}
				}
			}
	}


	return statement.kind != .DIRECTIVE_SCOPE
		&& statement.kind != .DIRECTIVE_MODULE_PARAMETERS
		&& statement.kind != .DIRECTIVE_MODIFY
		&& statement.kind != .WHILE
		&& statement.kind != .FOR
		&& statement.kind != .DEFER
		&& statement.kind != .PUSH_CONTEXT
		&& statement.kind != .ASM
		&& statement.kind != .BLOCK;
}

parse_statement :: (parser: *Parser, parent: *Parser_Block = null) -> *Parser_Node {
	previous_allow_unprefixed_struct_literal := parser.allow_unprefixed_struct_literal;
	parser.allow_unprefixed_struct_literal = false;
	defer parser.allow_unprefixed_struct_literal = previous_allow_unprefixed_struct_literal;

	token := parser_peek(parser);
	if parser_peek_if(parser, #char "#", .KEYWORD_IF) {
		return parse_static_if_statement(parser, parent, .IMPERATIVE);
	}


	if parser_peek_if(parser, #char "#", .IDENT) && parser_peek(parser, 1).ident_value.name == "asm" {
		return parse_asm_statement(parser, parent);
	}


	if token.type == #char "#" && !(parser_peek_if(parser, #char "#", .IDENT, #char "(") && parser_peek(parser, 1).ident_value.name == "this") {
		directive := parse_declaration_directive(parser);
		if directive {
			return directive;
		}
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


	if looks_like_declaration(parser) || looks_like_compound_reassignment(parser) {
		return parse_declaration_node(parser);
	}


	first := parser.cursor;
	left := parse_binary(parser);
	if !left || parser_peek(parser).type != #char "," {
		return left;
	}


	// A comma can belong to an expression; commit to a compound assignment only after finding its operator.
	comma := parser_checkpoint(parser);
	arguments: [..]Parser_Comma_Separated_Argument;
	arguments.allocator = parser_node_allocator(parser.parsed);
	array_add(*arguments, .{ node = left });
	while parser_eat_if(parser, #char ",") {
		argument := parse_binary(parser, 2);
		if !argument {
			parser_restore(parser, comma);
			return left;
		}


		array_add(*arguments, .{ node = argument });
	}

	is_binary, _, precedence, _ := binary_operator_info(parser_peek(parser).type);
	if !is_binary || precedence != 1 {
		parser_restore(parser, comma);
		return left;
	}


	arguments_node := new_parser_node(parser, Parser_Comma_Separated_Arguments);
	arguments_node.kind = .COMMA_SEPARATED_ARGUMENTS;
	arguments_node.arguments = arguments;
	finish_node(parser, arguments_node, first);
	parser_eat(parser);
	right := parse_declaration_expression(parser);
	if !right {
		add_expected_expression(parser);
	}

	result := new_parser_node(parser, Parser_Compound_Declaration);
	result.kind = .COMPOUND_DECLARATION;
	result.comma_separated_assignment = arguments_node;
	result.declaration_properties = new_parser_node(parser, Parser_Declaration);
	result.declaration_properties.kind = .DECLARATION;
	result.declaration_properties.expression = right;
	finish_node(parser, result, first);
	return result;
}

new_asm_ident :: (parser: *Parser, token_index: s64) -> *Parser_Ident {
	token := parser.parsed.tokens[token_index];
	assert(token.type == .IDENT);

	result := new_parser_node(parser, Parser_Ident);
	result.kind = .IDENT;
	result.name = token.ident_value.name;
	result.l0 = token.l0;
	result.c0 = token.c0;
	result.l1 = token.l1;
	result.c1 = token.c1;
	#if ENABLE_TRIVIA {
		result.first_token = xx token_index;
		result.one_past_last_token = xx (token_index + 1);
	}

	return result;
}

asm_tokens_are_adjacent :: (parser: *Parser, left_index: s64, right_index: s64) -> bool {
	left := parser.parsed.tokens[left_index];
	right := parser.parsed.tokens[right_index];
	return (left.l1 == right.l0 && left.c1 == right.c0);
}

parse_asm_register_pinning_span :: (parser: *Parser, first: s64, equals_index: s64, one_past_last: s64) -> *Parser_Asm_Register_Pinning {
	if equals_index != one_past_last - 2 || parser.parsed.tokens[first].type != .IDENT || parser.parsed.tokens[equals_index].type != .TRIPLE_EQUALS {
		return null;
	}


	target_type := parser.parsed.tokens[equals_index + 1].type;
	if target_type != .IDENT && target_type != .NUMBER {
		return null;
	}


	result := New(Parser_Asm_Register_Pinning,, parser_node_allocator(parser.parsed));
	result.span = make_token_span(first, one_past_last);
	result.source = parse_asm_value_span(parser, first, first + 1);
	result.target = parse_asm_value_span(parser, equals_index + 1, one_past_last);
	return result;
}

parse_asm_register_declaration_span :: (parser: *Parser, first: s64, one_past_last: s64) -> *Parser_Asm_Register_Declaration {
	if first + 1 >= one_past_last || parser.parsed.tokens[first].type != .IDENT || parser.parsed.tokens[first + 1].type != #char ":" {
		return null;
	}


	end := first + 2;
	if end < one_past_last && parser.parsed.tokens[end].type == .IDENT {
		end += 1;
	}

	if end < one_past_last && parser.parsed.tokens[end].type != .TRIPLE_EQUALS {
		return null;
	}


	result := New(Parser_Asm_Register_Declaration,, parser_node_allocator(parser.parsed));
	result.span = make_token_span(first, end);
	result.name = new_asm_ident(parser, first);
	result.is_inferred = end == first + 2;
	if !result.is_inferred {
		result.register_class = new_asm_ident(parser, first + 2);
	}

	if end < one_past_last {
		result.pinning = parse_asm_register_pinning_span(parser, first, end, one_past_last);
	}

	return result;
}

asm_memory_constant_end :: (parser: *Parser, first: s64, limit: s64) -> s64 {
	if first >= limit {
		return first;
	}


	if parser.parsed.tokens[first].type == .NUMBER || parser.parsed.tokens[first].type == .IDENT {
		return first + 1;
	}


	if parser.parsed.tokens[first].type != #char "(" {
		return first;
	}


	depth: s64;
	for first..limit-1 {
		token_type := parser.parsed.tokens[it].type;
		if token_type == {
			case #char "(";
				depth += 1;

			case #char ")";
				depth -= 1;
				if depth == 0 {
					return it + 1;
				}
		}
	}


	return first;
}

parse_asm_value_span :: (parser: *Parser, first: s64, one_past_last: s64) -> Parser_Asm_Value {
	result: Parser_Asm_Value;
	result.span = make_token_span(first, one_past_last);
	saved_cursor := parser.cursor;
	parser.cursor = first;
	result.expression = parse_prefix(parser);
	assert(parser.cursor == one_past_last);
	parser.cursor = saved_cursor;
	return result;
}

// Validate the whole addressing form before constructing subexpressions, so malformed operands stay a single recoverable span.
parse_asm_memory_span :: (parser: *Parser, first: s64, one_past_last: s64) -> *Parser_Asm_Memory_Operand {
	if (first + 2 >= one_past_last
		|| parser.parsed.tokens[first + 1].type != .IDENT
		|| parser.parsed.tokens[one_past_last - 1].type != #char "]"
	) {
		return null;
	}


	close := one_past_last - 1;
	index_first: s64;
	scale_first: s64;
	scale_end: s64;
	displacement_first: s64;
	position := first + 2;
	if position < close {
		sign := parser.parsed.tokens[position].type;
		if sign != #char "+" && sign != #char "-" {
			return null;
		}


		position += 1;
		if position >= close {
			return null;
		}


		if sign == #char "+" && parser.parsed.tokens[position].type == .IDENT {
			index_first = position;
			position += 1;
			if position < close && parser.parsed.tokens[position].type == #char "*" {
				position += 1;
				scale_first = position;
				scale_end = asm_memory_constant_end(parser, position, close);
				if scale_end == position {
					return null;
				}


				position = scale_end;
			}


			if position < close {
				sign = parser.parsed.tokens[position].type;
				if sign != #char "+" && sign != #char "-" {
					return null;
				}


				position += 1;
			}
		}


		if position < close {
			displacement_first = position - 1;
			position = asm_memory_constant_end(parser, position, close);
			if position == displacement_first + 1 {
				return null;
			}
		}
	}


	if position != close {
		return null;
	}


	result := New(Parser_Asm_Memory_Operand,, parser_node_allocator(parser.parsed));
	result.span = make_token_span(first, one_past_last);
	result.base.span = make_token_span(first + 1, first + 2);
	result.base.expression = new_asm_ident(parser, first + 1);

	if index_first {
		result.index.span = make_token_span(index_first, index_first + 1);
		result.index.expression = new_asm_ident(parser, index_first);
	}

	if scale_first {
		result.scale = parse_asm_value_span(parser, scale_first, scale_end);
	}

	if displacement_first {
		result.displacement = parse_asm_value_span(parser, displacement_first, close);
	}

	return result;
}

add_asm_operand_diagnostic :: (parser: *Parser, first: s64, one_past_last: s64, message: string) {
	// The block scanner has passed this operand; locate the error without moving its recovery point.
	saved_cursor := parser.cursor;
	parser.cursor = first;
	add_expected_expression_at(parser, make_token_span(first, one_past_last), message);
	parser.cursor = saved_cursor;
}

// Split modifiers only at the operand's top level; nested expressions can contain the same punctuation.
add_asm_operand :: (parser: *Parser, operands: *[..]*Parser_Asm_Operand, first: s64, one_past_last: s64) {
	if first >= one_past_last {
		return;
	}


	operand := New(Parser_Asm_Operand,, parser_node_allocator(parser.parsed));
	operand.span = make_token_span(first, one_past_last);
	base_end := one_past_last;
	parenthesis_depth: s64;
	bracket_depth: s64;

	for first..one_past_last-1 {
		token_type := parser.parsed.tokens[it].type;
		if !parenthesis_depth && !bracket_depth && (token_type == #char "!" || token_type == .BITWISE_AND) {
			base_end = it;
			break;
		}


		if token_type == {
			case #char "(";		parenthesis_depth += 1;
			case #char ")";		parenthesis_depth -= 1;

			case #char "[";		bracket_depth += 1;
			case #char "]";		bracket_depth -= 1;
		}
	}

	if base_end < one_past_last {
		modifiers: [..]*Parser_Asm_Operand_Modifier;
		modifiers.allocator = parser_node_allocator(parser.parsed);
		position := base_end;

		// Suffixes may stack, e.g. `[base]! &* mask`; retain their source order.
		while position < one_past_last {
			modifier_first := position;
			modifier := New(Parser_Asm_Operand_Modifier,, parser_node_allocator(parser.parsed));
			token_type := parser.parsed.tokens[position].type;
			position += 1;
			if token_type == #char "!" {
				modifier.kind = .BANG;
				if position < one_past_last && parser.parsed.tokens[position].type == .IDENT && asm_tokens_are_adjacent(parser, modifier_first, position) {
					name: string = parser.parsed.tokens[position].ident_value.name;
					if name.count == 1 {
						if name[0] == {
							case #char "n";		modifier.kind = .BANG_N;
							case #char "d";		modifier.kind = .BANG_D;
							case #char "u";		modifier.kind = .BANG_U;
							case #char "z";		modifier.kind = .BANG_Z;
						}
					}

					if modifier.kind == .BANG {
						add_asm_operand_diagnostic(parser, modifier_first, one_past_last, "Malformed assembly operand modifier.");
						array_add(operands, operand);
						return;
					}


					position += 1;
				}
			} else if token_type == .BITWISE_AND {
				modifier.kind = .AMPERSAND;
				if position < one_past_last && parser.parsed.tokens[position].type == #char "*" && asm_tokens_are_adjacent(parser, modifier_first, position) {
					modifier.kind = .AMPERSAND_STAR;
					position += 1;
				}

				if position >= one_past_last || parser.parsed.tokens[position].type != .IDENT {
					add_asm_operand_diagnostic(parser, modifier_first, one_past_last, "Malformed assembly operand modifier.");
					array_add(operands, operand);
					return;
				}


				modifier.argument.span = make_token_span(position, position + 1);
				modifier.argument.expression = new_asm_ident(parser, position);
				position += 1;
			} else {
				add_asm_operand_diagnostic(parser, modifier_first, one_past_last, "Malformed assembly operand modifier.");
				array_add(operands, operand);
				return;
			}

			modifier.span = make_token_span(modifier_first, position);
			array_add(*modifiers, modifier);
		}


		operand.modifiers = modifiers;
	}


	if base_end == first {
		add_asm_operand_diagnostic(parser, first, one_past_last, "Missing assembly operand before modifier.");
		array_add(operands, operand);
		return;
	}


	operand.register_declaration = parse_asm_register_declaration_span(parser, first, base_end);
	if operand.register_declaration {
		operand.kind = .REGISTER_DECLARATION;
	} else if first + 1 < base_end {
		operand.register_pinning = parse_asm_register_pinning_span(parser, first, first + 1, base_end);
		if operand.register_pinning {
			operand.kind = .REGISTER_PINNING;
		}
	}

	if operand.kind == .UNPARSED && parser.parsed.tokens[first].type == #char "[" {
		operand.memory = parse_asm_memory_span(parser, first, base_end);
		if operand.memory {
			operand.kind = .MEMORY;
		} else {
			add_asm_operand_diagnostic(parser, first, base_end, "Malformed assembly memory operand.");
		}
	}

	// Only self-contained values become expression nodes; unknown forms keep their raw span.
	if operand.kind == .UNPARSED {
		is_number := (base_end == first + 1 && parser.parsed.tokens[first].type == .NUMBER);
		is_ident := (base_end == first + 1 && parser.parsed.tokens[first].type == .IDENT);
		is_signed_number := (
			base_end == first + 2
			&& (parser.parsed.tokens[first].type == #char "+" || parser.parsed.tokens[first].type == #char "-")
			&& parser.parsed.tokens[first + 1].type == .NUMBER
		);
		is_parenthesized := (
			base_end > first + 2
			&& parser.parsed.tokens[first].type == #char "("
			&& asm_memory_constant_end(parser, first, base_end) == base_end
		);

		if is_number || is_signed_number || is_ident || is_parenthesized {
			operand.value = parse_asm_value_span(parser, first, base_end);
			operand.kind = .VALUE;
		}
	}

	array_add(operands, operand);
}

parse_asm_instruction_span :: (parser: *Parser, statement: *Parser_Asm_Statement, content_first: s64, content_one_past_last: s64) {
	if content_first >= content_one_past_last {
		return;
	}


	if parser.parsed.tokens[content_first].type != .IDENT {
		return;
	}


	after_mnemonic := content_first + 1;
	if after_mnemonic < content_one_past_last {
		next_type := parser.parsed.tokens[after_mnemonic].type;
		if next_type == #char ":" {
			statement.register_declaration = parse_asm_register_declaration_span(parser, content_first, content_one_past_last);
			if statement.register_declaration {
				statement.kind = .REGISTER_DECLARATION;
			}

			return;
		}


		if next_type == .TRIPLE_EQUALS {
			statement.register_pinning = parse_asm_register_pinning_span(parser, content_first, after_mnemonic, content_one_past_last);
			if statement.register_pinning {
				statement.kind = .REGISTER_PINNING;
			}

			return;
		}
	}


	instruction := New(Parser_Asm_Instruction,, parser_node_allocator(parser.parsed));
	instruction.span = statement.span;
	instruction.mnemonic = new_asm_ident(parser, content_first);

	// Adjacent `.8` or `?BITS` belongs to the mnemonic, not its first operand.
	operand_first := after_mnemonic;
	if (operand_first < content_one_past_last
		&& parser.parsed.tokens[operand_first].type == .NUMBER
		&& asm_tokens_are_adjacent(parser, content_first, operand_first)
	) {
		size := New(Parser_Asm_Mnemonic_Size,, parser_node_allocator(parser.parsed));
		size.kind = .FIXED;
		size.span = make_token_span(operand_first, operand_first + 1);
		instruction.size = size;
		operand_first += 1;
	} else if (
		operand_first + 1 < content_one_past_last
		&& parser.parsed.tokens[operand_first].type == #char "?"
		&& parser.parsed.tokens[operand_first + 1].type == .IDENT
		&& asm_tokens_are_adjacent(parser, content_first, operand_first)
		&& asm_tokens_are_adjacent(parser, operand_first, operand_first + 1)
	) {
		size := New(Parser_Asm_Mnemonic_Size,, parser_node_allocator(parser.parsed));
		size.kind = .POLYMORPHIC;
		size.span = make_token_span(operand_first, operand_first + 2);
		size.polymorphic_name = new_asm_ident(parser, operand_first + 1);
		instruction.size = size;
		operand_first += 2;
	}

	operands: [..]*Parser_Asm_Operand;
	operands.allocator = parser_node_allocator(parser.parsed);
	parenthesis_depth: s64;
	bracket_depth: s64;
	brace_depth: s64;
	index := operand_first;
	// Commas inside memory or parenthesized values do not separate instruction operands.
	while index < content_one_past_last {
		token_type := parser.parsed.tokens[index].type;
		at_top_level := (!parenthesis_depth && !bracket_depth && !brace_depth);
		// Split only unambiguous adjacent values; other operand forms stay intact for syntax parsing.
		if at_top_level && index == operand_first + 1 && parser.parsed.tokens[operand_first].type == .IDENT && (token_type == .IDENT || token_type == .NUMBER) {
			add_asm_operand(parser, *operands, operand_first, index);
			saved_cursor := parser.cursor;
			parser.cursor = index;
			add_missing_token(parser, #char ",");
			parser.cursor = saved_cursor;
			operand_first = index;
		}

		if token_type == {
			case #char ",";
				if at_top_level {
					add_asm_operand(parser, *operands, operand_first, index);
					operand_first = index + 1;
				}

			case #char "(";							parenthesis_depth += 1;
			case #char ")";	if parenthesis_depth	parenthesis_depth -= 1;

			case #char "[";							bracket_depth += 1;
			case #char "]";	if bracket_depth  		bracket_depth -= 1;

			case #char "{";							brace_depth += 1;
			case #char "}";	if brace_depth			brace_depth -= 1;
		}

		index += 1;
	}

	add_asm_operand(parser, *operands, operand_first, content_one_past_last);
	instruction.operands = operands;

	statement.kind = .INSTRUCTION;
	statement.instruction = instruction;
}

new_asm_statement :: (parser: *Parser, first: s64, one_past_last: s64, content_one_past_last: s64) -> *Parser_Asm_Statement {
	result := New(Parser_Asm_Statement,, parser_node_allocator(parser.parsed));
	result.span = make_token_span(first, one_past_last);
	parse_asm_instruction_span(parser, result, first, content_one_past_last);
	return result;
}

parse_asm_statement :: (parser: *Parser, enclosing_scope: *Parser_Block) -> *Parser_Asm {
	first := parser.cursor;
	parser_eat(parser, 2);

	features: [..]*Parser_Asm_Feature;
	features.allocator = parser_node_allocator(parser.parsed);
	while parser_peek(parser).type == .IDENT {
		feature_first := parser.cursor;
		feature_token := parser_eat(parser);
		feature_name := new_parser_node(parser, Parser_Ident);
		feature_name.kind = .IDENT;
		feature_name.name = feature_token.ident_value.name;
		finish_node(parser, feature_name, feature_first);

		feature := New(Parser_Asm_Feature,, parser_node_allocator(parser.parsed));
		feature.span = make_token_span(feature_first, parser.cursor);
		feature.name = feature_name;
		array_add(*features, feature);
		if !parser_eat_if(parser, #char ",") {
			break;
		}
	}

	result := new_parser_node(parser, Parser_Asm);
	result.kind = .ASM;
	result.features = features;
	result.enclosing_scope = enclosing_scope;
	statements: [..]*Parser_Asm_Statement;
	statements.allocator = parser_node_allocator(parser.parsed);

	if !parser_expect(parser, #char "{") {
		result.statements = statements;
		return finish_node(parser, result, first);
	}


	body_first := parser.cursor;
	statement_first := parser.cursor;
	brace_depth: s64 = 1;
	// Nested braces belong to assembly statements; only the outer brace ends the block.
	while brace_depth && parser_peek(parser).type != .END_OF_INPUT {
		token := parser_peek(parser);
		if token.type == #char "{" {
			brace_depth += 1;
		} else if token.type == #char "}" {
			brace_depth -= 1;
			if !brace_depth {
				if parser.cursor > statement_first {
					statement := new_asm_statement(parser, statement_first, parser.cursor, parser.cursor);
					array_add(*statements, statement);
					add_missing_token(parser, #char ";");
				}

				result.body_span = make_token_span(body_first, parser.cursor);
				parser_eat(parser);
				break;
			}
		} else if token.type == #char ";" && brace_depth == 1 {
			// An unmatched operand bracket must not absorb the next assembly instruction.
			parser_eat(parser);
			statement := new_asm_statement(parser, statement_first, parser.cursor, parser.cursor - 1);
			array_add(*statements, statement);
			statement_first = parser.cursor;
			continue;
		}


		parser_eat(parser);
	}

	if brace_depth {
		if parser.cursor > statement_first {
			statement := new_asm_statement(parser, statement_first, parser.cursor, parser.cursor);
			array_add(*statements, statement);
			add_missing_token(parser, #char ";");
		}

		result.body_span = make_token_span(body_first, parser.cursor);
		parser_expect(parser, #char "}");
	}

	result.statements = statements;

	return finish_node(parser, result, first);
}

parse_statement_block :: (parser: *Parser, parent: *Parser_Block, block_type := Code_Block.block_type.IMPERATIVE, enum_members := false) -> *Parser_Block {
	if parser_peek(parser).type == #char "{" {
		return parse_block_node(parser, parent, block_type, enum_members);
	}


	first := parser.cursor;
	statement: *Parser_Node;
	if enum_members && parser_peek(parser).type == .IDENT && parser_peek(parser, 1).type == #char ";" {
		statement = parse_enum_member(parser);
	} else if enum_members && parser_peek_if(parser, #char "#", .KEYWORD_IF) {
		statement = parse_static_if_statement(parser, parent, .DATA_DECLARATIONS, true);
	} else if block_type == .DATA_DECLARATIONS {
		statement = parse_declaration_node(parser);
	} else {
		statement = parse_statement(parser, parent);
	}

	if !statement {
		add_expected_expression(parser);
		return null;
	}


	finish_statement(parser, statement);

	statements: [..]*Parser_Node;
	statements.allocator = parser_node_allocator(parser.parsed);
	array_add(*statements, statement);

	result := new_parser_node(parser, Parser_Block);
	result.kind = .BLOCK;
	result.parent = parent;
	result.block_type = block_type;
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
	if !result.condition {
		add_expected_expression(parser);
	}
	result.block = parse_statement_block(parser, parent);
	if result.block {
		result.block.owning_statement = result;
	}

	finish_node(parser, result, first);
	return result;
}

parse_condition :: (parser: *Parser) -> *Parser_Node {
	if looks_like_declaration(parser) {
		return parse_declaration_node(parser);
	}


	// Parenthesized conditions can otherwise look like procedure headers.
	was_parsing_condition := parser.parsing_condition;
	parser.parsing_condition = true;
	result := parse_value_expression(parser);
	parser.parsing_condition = was_parsing_condition;
	return result;
}

parse_static_if_statement :: (parser: *Parser, parent: *Parser_Block, block_type: type_of(Code_Block.block_type), enum_members := false) -> *Parser_If {
	parser_eat(parser);
	result := parse_if_statement(parser, parent, false, block_type, enum_members);
	result.if_flags |= .IS_STATIC;
	return result;
}

// Detect the switch-like case form before parsing the condition, since its comparison token has a different role.
parse_if_statement :: (parser: *Parser, parent: *Parser_Block, is_ifx: bool, block_type := Code_Block.block_type.IMPERATIVE, enum_members := false) -> *Parser_If {
	first := parser.cursor;
	parser_eat(parser);

	result := new_parser_node(parser, Parser_If);
	result.kind = .IF;
	if is_ifx {
		result.if_flags |= .IS_IFX;
	}

	if parser_peek(parser).type == #char "#" {
		next := parser_peek(parser, 1);
		if next.type == .IDENT && next.ident_value.name == "complete" {
			parser_eat(parser, 2);
			result.if_flags |= .MARKED_AS_COMPLETE;
		}
	}

	if !is_ifx && has_switch_case_block(parser) {
		result.condition = parse_binary(parser, 5);

		parser_expect(parser, .ISEQUAL);

		result.if_flags |= .IS_SWITCH_STATEMENT;
		result.then_block = parse_case_block(parser, parent, result);
		if result.then_block {
			result.then_block.owning_statement = result;
		}

		finish_node(parser, result, first);
		return result;
	}


	result.condition = parse_condition(parser);
	if !result.condition {
		add_expected_expression(parser);
	}

	has_then_keyword := parser_eat_if(parser, .KEYWORD_THEN);

	if !is_ifx || has_then_keyword || (parser_peek(parser).type != .KEYWORD_ELSE && !is_synchronization_point(parser_peek(parser).type, .EXPRESSION)) {
		result.then_block = ifx is_ifx
			then parse_ifx_branch(parser, parent)
			else parse_statement_block(parser, parent, block_type, enum_members);
	}

	if result.then_block {
		result.then_block.owning_statement = result;
	}

	if parser_eat_if(parser, .KEYWORD_ELSE) {
		result.else_block = ifx is_ifx
			then parse_ifx_branch(parser, parent)
			else parse_statement_block(parser, parent, block_type, enum_members);

		if result.else_block {
			result.else_block.owning_statement = result;
		}
	}

	finish_node(parser, result, first);
	return result;
}

parse_ifx_branch :: (parser: *Parser, parent: *Parser_Block) -> *Parser_Block {
	if parser_peek(parser).type == #char "{" {
		return parse_block_node(parser, parent);
	}


	first := parser.cursor;

	expression := parse_binary(parser);
	if !expression {
		add_expected_expression(parser);
		return null;
	}


	statements: [..]*Parser_Node;
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
				if !parenthesis_depth {
					return false;
				}


				parenthesis_depth -= 1;

			case #char "[";
				bracket_depth += 1;
			case #char "]";
				if !bracket_depth {
					return false;
				}


				bracket_depth -= 1;

			case .ISEQUAL;
				if !parenthesis_depth && !bracket_depth {
					opening := parser_peek(parser, lookahead + 1);
					if opening.type != #char "{"  {
						return false;
					}


					first_member := parser_peek(parser, lookahead + 2);
					return first_member.type == .KEYWORD_CASE
						|| (first_member.type == #char "}" && first_member.l0 > opening.l0);
				}

			case #char "{";
				if !parenthesis_depth && !bracket_depth {
					return false;
				}
		}


		lookahead += 1;
	}


	return false;
}

// Recover within each case body so a bad statement does not swallow the next case label.
parse_case_block :: (parser: *Parser, parent: *Parser_Block, owning_if: *Parser_If) -> *Parser_Block {
	first := parser.cursor;
	if !parser_eat_if(parser, #char "{") {
		return null;
	}

	parent_scope := parser.current_scope;
	push_lexical_scope(parser);
	defer parser.current_scope = parent_scope;

	result := new_parser_node(parser, Parser_Block);
	result.kind = .BLOCK;
	parser.current_scope.owner = result;
	result.node_flags |= .IS_PARENTHESIZED;
	result.parent = parent;
	result.block_type = .IMPERATIVE;
	result.owning_statement = owning_if;

	cases: [..]*Parser_Node;
	cases.allocator = parser_node_allocator(parser.parsed);

	token := parser_peek(parser);
	// A malformed arm must recover before the next `case`, leaving the switch intact.
	while token.type != #char "}" && token.type != .END_OF_INPUT {
		case_first := parser.cursor;
		if !parser_expect(parser, .KEYWORD_CASE) {
			parser_synchronise(parser, .STATEMENT);
			if parser_peek(parser).type != .KEYWORD_CASE {
				break;
			}


			continue;
		}


		case_node := new_parser_node(parser, Parser_Case);
		case_node.kind = .CASE;
		case_node.owning_if = owning_if;

		if parser_peek(parser).type != #char ";" {
			case_node.condition = parse_binary(parser);
		}

		parser_expect(parser, #char ";");

		body_first := parser.cursor;
		case_scope := parser.current_scope;
		push_lexical_scope(parser);
		body := new_parser_node(parser, Parser_Block);
		body.kind = .BLOCK;
		parser.current_scope.owner = body;
		body.parent = result;
		body.block_type = .IMPERATIVE;
		body.owning_statement = case_node;
		statements: [..]*Parser_Node;
		statements.allocator = parser_node_allocator(parser.parsed);
		while true {
			token := parser_peek(parser);
			if token.type == .KEYWORD_CASE || token.type == #char "}" || token.type == .END_OF_INPUT {
				break;
			}


			if token.type == #char "#" {
				directive := parser_peek(parser, 1);
				if directive.type == .IDENT && directive.ident_value.name == "through" {
					parser_eat(parser, 2);
					if parser_peek(parser).type == #char ";" {
						if parser.warn_unnecessary_semicolons {
							add_unnecessary_semicolon(parser);
						}

						parser_eat(parser);
					}

					case_node.marked_as_fallthrough = true;
					continue;
				}
			}


			guard := parser_progress_guard(parser);

			statement := parse_statement(parser, body);
			if statement {
				array_add(*statements, statement);
				finish_statement(parser, statement);
			} else {
				add_unexpected_token(parser);
				parser_synchronise(parser, .STATEMENT);
			}

			if !parser_ensure_progress(parser, guard) {
				break;
			}
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
		parser.current_scope = case_scope;

		token = parser_peek(parser);
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

	if node.kind == .BLOCK {
		array_add(*parser.parsed.restart_points, Restart_Point.{kind = .BLOCK, span = make_token_span(at, at)});
	}
}

add_duplicate_for_flag :: (parser: *Parser, first: s64) {
	diagnostic := Parse_Diagnostic.{
		kind = .UNEXPECTED_TOKEN,
		span = make_token_span(first, parser.cursor),
		actual_token = parser.parsed.tokens[first].type,
		message = "Duplicate for-loop flag."
	};
	array_add(*parser.parsed.diagnostics, diagnostic);
	array_add(
		*parser.parsed.recovery_records,
		Recovery_Record.{
			kind = .ERROR_SPAN,
			span = diagnostic.span,
			diagnostic_index = parser.parsed.diagnostics.count - 1
		}
	);

	mark_parse_error(parser, false);
}

parse_for_statement :: (parser: *Parser, parent: *Parser_Block) -> *Parser_For {
	first := parser.cursor;
	parser_eat(parser);

	result := new_parser_node(parser, Parser_For);
	result.kind = .FOR;
	while true {
		flag_first := parser.cursor;
		if parser_eat_if(parser, #char "<") {
			if result.for_flags & .REVERSE != 0 {
				add_duplicate_for_flag(parser, flag_first);
			} else {
				result.for_flags |= .REVERSE;
			}
		} else if parser_eat_if(parser, #char "*") {
			if result.for_flags & .POINTER != 0 {
				add_duplicate_for_flag(parser, flag_first);
			} else {
				result.for_flags |= .POINTER;
			}
		} else {
			break;
		}
	}

	// Without a delimiter before the collection, binary flag expressions need parentheses.
	seen_reverse := result.for_flags & .REVERSE != 0;
	seen_pointer := result.for_flags & .POINTER != 0;
	while true {
		flag_first := parser.cursor;
		if parser_eat_if(parser, .LESSEQUALS) {
			if seen_reverse {
				add_duplicate_for_flag(parser, flag_first);
			}

			expression := parse_prefix(parser);
			if !expression {
				add_expected_expression(parser);
			} else if !seen_reverse {
				result.want_reverse_expression = expression;
			}
			seen_reverse = true;
		} else if parser_eat_if(parser, .TIMESEQUALS) {
			if seen_pointer {
				add_duplicate_for_flag(parser, flag_first);
			}

			expression := parse_prefix(parser);
			if !expression {
				add_expected_expression(parser);
			} else if !seen_pointer {
				result.want_pointer_expression = expression;
			}
			seen_pointer = true;
		} else if seen_reverse && parser_eat_if(parser, #char "<") {
			add_duplicate_for_flag(parser, flag_first);
		} else if seen_pointer && parser_eat_if(parser, #char "*") {
			add_duplicate_for_flag(parser, flag_first);
		} else {
			break;
		}


		if parser_peek(parser).type == #char "," && (parser_peek(parser, 1).type == .LESSEQUALS || parser_peek(parser, 1).type == .TIMESEQUALS) {
			parser_eat(parser);
		} else if parser_peek(parser).type == .LESSEQUALS || parser_peek(parser).type == .TIMESEQUALS {
			add_missing_token(parser, #char ",");
		}
	}

	// Named for-expansions are only valid after the any flags have been specified.
	if parser_eat_if(parser, #char ":") {
		result.want_replacement_for_expansion = parse_postfix(parser);
		if !result.want_replacement_for_expansion {
			add_expected_expression(parser);
		}
	}

	token := parser_peek(parser);
	if token.type == .IDENT {
		next := parser_peek(parser, 1);
		if next.type == #char ":" || next.type == #char "," {
			ident_first := parser.cursor;
			parser_eat(parser);

			result.ident_it = new_parser_node(parser, Parser_Ident);
			result.ident_it.kind = .IDENT;
			result.ident_it.name = token.ident_value.name;
			if token.ident_is_backticked {
				result.ident_it.flags |= .HAS_SCOPE_MODIFIER;
			}

			finish_node(parser, result.ident_it, ident_first);

			if parser_eat_if(parser, #char ",") {
				index_first := parser.cursor;
				index_token := parser_peek(parser);
				if parser_eat_if(parser, .IDENT) {
					result.ident_it_index = new_parser_node(parser, Parser_Ident);
					result.ident_it_index.kind = .IDENT;
					result.ident_it_index.name = index_token.ident_value.name;
					if index_token.ident_is_backticked {
						result.ident_it_index.flags |= .HAS_SCOPE_MODIFIER;
					}

					finish_node(parser, result.ident_it_index, index_first);
				} else {
					add_expected_expression(parser);
				}
			}

			parser_expect(parser, #char ":");
		}
	}

	result.iteration_expression = parse_binary(parser);
	if !result.iteration_expression {
		add_expected_expression(parser);
	}

	if parser_eat_if(parser, .DOUBLE_DOT) {
		result.iteration_expression_right = parse_binary(parser);
		if !result.iteration_expression_right {
			add_expected_expression(parser);
		}
	}

	result.block = parse_statement_block(parser, parent);
	if result.block {
		result.block.owning_statement = result;
	}
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
	if result.block {
		result.block.owning_statement = result;
	}

	finish_node(parser, result, first);
	return result;
}

parse_using_statement :: (parser: *Parser) -> *Parser_Using {
	first := parser.cursor;
	parser_eat(parser);

	result := parse_using_statement_after_keyword(parser, first);
	return result;
}

parse_using_statement_after_keyword :: (parser: *Parser, first: s64) -> *Parser_Using {
	result := new_parser_node(parser, Parser_Using);
	result.kind = .USING;
	parse_using_filter(parser, result);
	marked_as_as := false;
	if parser_peek_if(parser, #char "#", .IDENT) && parser_peek(parser, 1).ident_value.name == "as" {
		parser_eat(parser, 2);
		marked_as_as = true;
	}

	result.expression = ifx looks_like_declaration(parser)
		then parse_declaration_node(parser)
		else parse_binary(parser);
	if !result.expression {
		add_expected_expression(parser);
	} else if marked_as_as && result.expression.kind == .DECLARATION {
		result.expression.(*Parser_Declaration).flags |= .IS_MARKED_AS_AS;
	}

	finish_node(parser, result, first);
	return result;
}

// Keep map expressions distinct from only/except name lists so their syntax and diagnostics stay local to the filter.
parse_using_filter :: (parser: *Parser, result: *Parser_Using) {
	if !parser_eat_if(parser, #char ",") {
		return;
	}


	modifier := parser_peek(parser);
	if modifier.type == .IDENT && modifier.ident_value.name == "except" {
		result.filter_type = .EXCEPT;
	} else if modifier.type == .IDENT && modifier.ident_value.name == "only" {
		result.filter_type = .ONLY;
	} else if modifier.type == .IDENT && modifier.ident_value.name == "map" {
		result.filter_type = .MAP;
	} else {
		if modifier.type == .IDENT {
			add_unexpected_token(parser);
		} else {
			parser_expect(parser, .IDENT);
		}

		return;
	}


	parser_eat(parser);

	if result.filter_type == .MAP {
		parenthesized := parser_expect(parser, #char "(");
		result.filter_expression = parse_binary(parser);
		if !result.filter_expression {
			add_expected_expression(parser);
		}

		if parenthesized && result.filter_expression {
			result.filter_expression.node_flags |= .IS_PARENTHESIZED;
		}

		parser_expect(parser, #char ")");
		return;
	}


	if parser_eat_if(parser, #char "(") {
		list_first := parser.cursor - 1;
		members: [..]*Parser_Node;
		members.allocator = parser_node_allocator(parser.parsed);

		while parser_peek(parser).type != #char ")" && parser_peek(parser).type != .END_OF_INPUT {
			member_first := parser.cursor;
			name := parser_peek(parser);
			if !parser_eat_if(parser, .IDENT) {
				parser_expect(parser, .IDENT);
				break;
			}


			member := new_parser_node(parser, Parser_Literal);
			member.kind = .LITERAL;
			member.value_type = .STRING;
			member._string = name.ident_value.name;
			finish_node(parser, member, member_first);
			array_add(*members, member);
			if !parser_eat_if(parser, #char ",") {
				break;
			}
		}

		parser_expect(parser, #char ")");
		filter := new_parser_node(parser, Parser_Literal);
		filter.kind = .LITERAL;
		filter.value_type = .ARRAY;
		filter.array_literal_info = new_parser_node(parser, Parser_Array_Literal_Info);
		filter.array_literal_info.array_members = members;
		result.filter_expression = finish_node(parser, filter, list_first);
	} else {
		result.filter_expression = parse_binary(parser);
		if !result.filter_expression {
			add_expected_expression(parser);
		}
	}
}

parse_push_context_statement :: (parser: *Parser, parent: *Parser_Block) -> *Parser_Push_Context {
	first := parser.cursor;
	keyword := parser_eat(parser);

	result := new_parser_node(parser, Parser_Push_Context);
	result.kind = .PUSH_CONTEXT;
	if keyword.ident_is_backticked {
		result.push_context_flags |= .IS_BACKTICKED;
	}

	if parser_eat_if(parser, #char ",") {
		modifier := parser_peek(parser);
		if modifier.type == .IDENT && modifier.ident_value.name == "defer_pop" {
			parser_eat(parser);
			result.push_context_flags |= .DEFER_POP;
		} else {
			add_unexpected_token(parser);
		}
	}

	if parser_peek(parser).type != #char "{" {
		result.to_push = parse_binary(parser);
	}

	if !(result.push_context_flags & .DEFER_POP) {
		result.block = parse_statement_block(parser, parent);
	}

	if result.block {
		result.block.owning_statement = result;
	}

	finish_node(parser, result, first);
	return result;
}

// Distinguish `name: Type` and `a, b := value` from identifier-led statements without consuming input; the real declaration parser owns error reporting.
looks_like_declaration :: (parser: *Parser) -> bool {
	lookahead: s64;
	token := parser_peek(parser, lookahead);
	if token.type == .KEYWORD_OPERATOR {
		return true;
	}


	if token.type == #char "$" || token.type == .DOUBLE_DOLLAR {
		lookahead += 1;
		token = parser_peek(parser, lookahead);
	}

	if token.type != .IDENT {
		return false;
	}


	lookahead += 1;
	while parser_peek(parser, lookahead).type == #char "," {
		lookahead += 1;
		if parser_peek(parser, lookahead).type != .IDENT {
			return false;
		}


		lookahead += 1;
	}


	return parser_peek(parser, lookahead).type == #char ":";
}

// Spot mixed-target forms such as `a=, b := call()` before parsing an ordinary expression statement.  A single assignment is not a compound reassignment.
looks_like_compound_reassignment :: (parser: *Parser) -> bool {
	if parser_peek(parser).type != .IDENT {
		return false;
	}


	lookahead: s64;
	saw_comma := false;
	while true {
		lookahead += 1;
		if parser_peek(parser, lookahead).type == #char ":" || parser_peek(parser, lookahead).type == #char "=" {
			lookahead += 1;
		}

		if parser_peek(parser, lookahead).type != #char "," {
			break;
		}


		saw_comma = true;
		lookahead += 1;
		if parser_peek(parser, lookahead).type != .IDENT {
			return false;
		}
	}


	return saw_comma
		&& (
			parser_peek(parser, lookahead).type == #char "="
			|| parser_peek(parser, lookahead).type == #char ":"
		);
}

parse_return_statement :: (parser: *Parser) -> *Parser_Return {
	first := parser.cursor;
	keyword := parser_eat(parser);

	arguments: [..]Parser_Argument;
	arguments.allocator = parser_node_allocator(parser.parsed);

	token := parser_peek(parser);
	while token.type != #char ";" && token.type != #char "}" && token.type != .END_OF_INPUT {
		expression := parse_value_expression(parser);
		if !expression {
			add_expected_expression(parser);
			break;
		}


		array_add(*arguments, .{expression=expression});
		if !parser_eat_if(parser, #char ",") {
			break;
		}
	}

	result := new_parser_node(parser, Parser_Return);
	result.kind = .RETURN;
	result.arguments_unsorted = arguments;
	if keyword.ident_is_backticked {
		result.return_flags |= .IS_BACKTICKED;
	}

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

	target_first := parser.cursor;
	target := parser_peek(parser);
	if parser_eat_if(parser, .IDENT) {
		result.target_ident = new_parser_node(parser, Parser_Ident);
		result.target_ident.kind = .IDENT;
		result.target_ident.name = target.ident_value.name;
		finish_node(parser, result.target_ident, target_first);
	}

	finish_node(parser, result, first);
	return result;
}

// Declaration position admits static branches, using, placeholders, directives, and ordinary names; parameter lists disable multi-value initializers at commas.
parse_declaration_node :: (parser: *Parser, allow_multi_value_expression := true) -> *Parser_Node {
	first := parser.cursor;
	if parser_peek_if(parser, #char "#", .KEYWORD_IF) {
		return parse_static_if_statement(parser, null, .DATA_DECLARATIONS);
	}


	if parser_peek(parser).type == .KEYWORD_USING {
		return parse_using_statement(parser);
	}


	if parser_peek_if(parser, #char "#", .IDENT) && parser_peek(parser, 1).ident_value.name == "placeholder" {
		parser_eat(parser, 2);
		name := parser_peek(parser);
		if !parser_eat_if(parser, .IDENT) {
			parser_expect(parser, .IDENT);
		}

		result := new_parser_node(parser, Parser_Placeholder);
		result.kind = .PLACEHOLDER;
		result.name = name.ident_value.name;
		return finish_node(parser, result, first);
	}


	marked_no_reset := parser_peek_if(parser, #char "#", .IDENT) && parser_peek(parser, 1).ident_value.name == "no_reset";
	if marked_no_reset {
		parser_eat(parser, 2);
	}


	if parser_peek(parser).type == #char "#" {
		if marked_no_reset {
			add_expected_expression(parser);
			return null;
		}


		return parse_declaration_directive(parser);
	}


	declaration_flags: type_of(Code_Declaration.flags);
	if marked_no_reset {
		declaration_flags |= .NO_RESET;
	}

	if parser_eat_if(parser, #char "$") {
		declaration_flags |= .AUTO_VALUE_BAKE;
		declaration_flags |= .AUTO_VALUE_BAKE_IS_REQUIRED;
	} else if parser_eat_if(parser, .DOUBLE_DOLLAR) {
		declaration_flags |= .AUTO_VALUE_BAKE;
	}

	operator_declaration := parser_eat_if(parser, .KEYWORD_OPERATOR);
	name_token := parser_peek(parser);

	declaration_name := ifx operator_declaration
		then parse_operator_declaration_name(parser)
		else ifx parser_eat_if(parser, .IDENT)
			then name_token.ident_value.name
			else "";
	if !declaration_name {
		return null;
	}


	// A comma makes `a=, b := call()` one compound node with per-name modifiers.
	if (parser_peek(parser).type == #char "," || parser_peek(parser, 1).type == #char ","
		&& (parser_peek(parser).type == #char ":" || parser_peek(parser).type == #char "=")
	) {
		// 1. Capture names and their individual declare/assign intent before the shared separator.
		arguments: [..]Parser_Comma_Separated_Argument;
		arguments.allocator = parser_node_allocator(parser.parsed);

		first_ident := new_parser_node(parser, Parser_Ident);
		first_ident.kind = .IDENT;
		first_ident.name = name_token.ident_value.name;
		if name_token.ident_is_backticked {
			first_ident.flags |= .HAS_SCOPE_MODIFIER;
		}

		finish_node(parser, first_ident, first);

		first_modifier: type_of(Code_Comma_Separated_Argument.modifier);

		if parser_peek(parser, 1).type == #char "," {
			if parser_eat_if(parser, #char ":") {
				first_modifier = .DECLARE;
			} else if parser_eat_if(parser, #char "=") {
				first_modifier = .ASSIGN;
			}
		}

		array_add(*arguments, .{node=first_ident, modifier=first_modifier});

		while parser_eat_if(parser, #char ",") {
			argument_first := parser.cursor;
			argument_token := parser_peek(parser);
			if !parser_eat_if(parser, .IDENT) {
				add_expected_expression(parser);
				break;
			}


			ident := new_parser_node(parser, Parser_Ident);
			ident.kind = .IDENT;
			ident.name = argument_token.ident_value.name;
			if argument_token.ident_is_backticked {
				ident.flags |= .HAS_SCOPE_MODIFIER;
			}

			finish_node(parser, ident, argument_first);

			modifier: type_of(Code_Comma_Separated_Argument.modifier);
			if parser_peek(parser, 1).type == #char "," {
				if parser_eat_if(parser, #char ":") {
					modifier = .DECLARE;
				} else if parser_eat_if(parser, #char "=") {
					modifier = .ASSIGN;
				}
			}

			array_add(*arguments, .{node=ident, modifier=modifier});
		}

		// 2. A shared `=` reassigns existing targets; `:` introduces declaration properties.
		reassignment := parser_eat_if(parser, #char "=");
		if !reassignment {
			parser_expect(parser, #char ":");
		}

		// 3. Preserve the compiler's compound shape even for multi-target reassignment.
		result := new_parser_node(parser, Parser_Compound_Declaration);
		result.kind = .COMPOUND_DECLARATION;

		if reassignment {
			result.operator_type = #char "=";
		}

		result.comma_separated_assignment = new_parser_node(parser, Parser_Comma_Separated_Arguments);
		result.comma_separated_assignment.kind = .COMMA_SEPARATED_ARGUMENTS;
		result.comma_separated_assignment.arguments = arguments;
		#if ENABLE_TRIVIA {
			result.comma_separated_assignment.first_token = xx first;
			result.comma_separated_assignment.one_past_last_token = xx parser.cursor;
		}
		result.declaration_properties = new_parser_node(parser, Parser_Declaration);
		result.declaration_properties.kind = .DECLARATION;
		result.declaration_properties.flags = declaration_flags;

		// 4. Reassignments take RHS values; declarations may also have types and metadata.
		if reassignment {
			result.declaration_properties.expression = parse_declaration_expression(parser);
			if !result.declaration_properties.expression {
				add_expected_expression(parser);
			}
		} else {
			parse_declaration_properties(parser, result.declaration_properties, allow_multi_value_expression);
		}

		parse_declaration_metadata(parser, result.declaration_properties, *result.alignment_expression);

		finish_node(parser, result, first);

		// 5. Only newly declared names enter this scope; assigned targets remain uses.
		for arguments {
			if (!reassignment && it.modifier != .ASSIGN) || it.modifier == .DECLARE {
				name := it.node.(*Parser_Ident).name;
				array_add(*parser.current_scope.bindings, Parser_Binding.{name = name, declaration = result.declaration_properties});
			}
		}

		return result;
	}


	if !parser_eat_if(parser, #char ":") {
		return null;
	}


	result := new_parser_node(parser, Parser_Declaration);
	result.kind = .DECLARATION;
	result.name = declaration_name;
	result.flags = declaration_flags;
	if name_token.ident_is_backticked {
		result.flags |= .HAS_SCOPE_MODIFIER;
	}

	parse_declaration_properties(parser, result, allow_multi_value_expression);
	if result.expression && result.expression.kind == .PROCEDURE_HEADER {
		result.expression.(*Parser_Procedure_Header).name = result.name;
	}

	parse_declaration_metadata(parser, result, *result.alignment_expression);

	finish_node(parser, result, first);
	return result;
}

parse_operator_declaration_name :: (parser: *Parser) -> string {
	token := parser_peek(parser);
	if token.type == #char "*" && parser_peek(parser, 1).type == #char "[" {
		parser_eat(parser, 2);
		parser_expect(parser, #char "]");
		return "*[]";
	}


	if token.type == #char "[" {
		parser_eat(parser);
		parser_expect(parser, #char "]");
		return ifx parser_eat_if(parser, #char "=")
			then "[]="
			else "[]";
	}


	name: string;
	if token.type == {
		case #char "+";				name = "+";
		case #char "-";				name = "-";
		case #char "*";				name = "*";
		case #char "/";				name = "/";
		case #char "%";				name = "%";
		case #char "<";				name = "<";
		case #char ">";				name = ">";
		case #char "=";				name = "=";
		case #char ".";				name = ".";
		case #char "!";				name = "!";
		case #char "~";				name = "~";
		case #char "&";				name = "&";
		case #char "|";				name = "|";
		case #char "^";				name = "^";
		case .ISEQUAL;				name = "==";
		case .ISNOTEQUAL;			name = "!=";
		case .LESSEQUALS;			name = "<=";
		case .GREATEREQUALS;		name = ">=";
		case .LOGICAL_AND;			name = "&&";
		case .LOGICAL_OR;			name = "||";
		case .SHIFT_LEFT;			name = "<<";
		case .SHIFT_RIGHT;			name = ">>";
		case .ROTATE_LEFT;			name = "<<<";
		case .ROTATE_RIGHT;			name = ">>>";
		case .PLUSEQUALS;			name = "+=";
		case .MINUSEQUALS;			name = "-=";
		case .TIMESEQUALS;			name = "*=";
		case .DIVEQUALS;			name = "/=";
		case .MODEQUALS;			name = "%=";
		case .SHIFT_LEFT_EQUALS;	name = "<<=";
		case .SHIFT_RIGHT_EQUALS;	name = ">>=";
		case .ROTATE_LEFT_EQUALS;	name = "<<<=";
		case .ROTATE_RIGHT_EQUALS;	name = ">>>=";
		case .BITWISE_AND_EQUALS;	name = "&=";
		case .BITWISE_OR_EQUALS;	name = "|=";
		case .BITWISE_XOR_EQUALS;	name = "^=";
		case .LOGICAL_AND_EQUALS;	name = "&&=";
		case .LOGICAL_OR_EQUALS;	name = "||=";
	}

	if !name {
		add_unexpected_token(parser);
		return "";
	}


	parser_eat(parser);
	return name;
}

// A leading : or = omits the explicit type; otherwise parse the type before the initializer delimiter.
parse_declaration_properties :: (parser: *Parser, result: *Parser_Declaration, allow_multi_value_expression := true) {
	if parser_eat_if(parser, #char ":") {
		result.flags |= .IS_CONSTANT;
		result.expression = parse_declaration_expression(parser, allow_multi_value_expression);
		if !result.expression {
			add_expected_expression(parser);
		}
	} else if parser_eat_if(parser, #char "=") {
		result.expression = parse_declaration_expression(parser, allow_multi_value_expression);
		if !result.expression {
			add_expected_expression(parser);
		}
	} else {
		result.type_inst = parse_type_instantiation(parser);
		if !result.type_inst {
			add_expected_expression(parser);
			return;
		}


		if parser_eat_if(parser, #char ":") {
			result.flags |= .IS_CONSTANT;
			result.expression = parse_declaration_expression(parser, allow_multi_value_expression);
			if !result.expression {
				add_expected_expression(parser);
			}
		} else if parser_eat_if(parser, #char "=") {
			result.expression = parse_declaration_expression(parser, allow_multi_value_expression);
			if !result.expression {
				add_expected_expression(parser);
			}
		}
	}


	if (result.expression && result.expression.kind == .LITERAL
		&& result.expression.(*Parser_Literal).value_type == .UNINITIALIZED
	) {
		result.flags |= .IS_UNINITIALIZED;
		result.expression = null;
	}
}

parse_declaration_metadata :: (parser: *Parser, properties: *Parser_Declaration, alignment_expression: **Parser_Node) {
	token := parser_peek(parser);
	while token.type == #char "#" && parser_peek(parser, 1).type == .IDENT {
		directive: string = parser_peek(parser, 1).ident_value.name;
		if directive == {
			case "align";
				parser_eat(parser, 2);
				alignment_expression.* = parse_binary(parser);
				if !alignment_expression.*	add_expected_expression(parser);

			case "no_reset";
				parser_eat(parser, 2);
				properties.flags |= .NO_RESET;

			case "uninitialized";
				parser_eat(parser, 2);
				properties.flags |= .IS_UNINITIALIZED;

			case "elsewhere";
				parser_eat(parser, 2);
				properties.flags |= .ELSEWHERE;

			case "program_export";
				parser_eat(parser, 2);
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
	notes: [..]*Parser_Note;
	notes.allocator = parser_node_allocator(parser.parsed);

	while parser_peek(parser).type == .NOTE {
		first := parser.cursor;
		token := parser_eat(parser);

		note := new_parser_node(parser, Parser_Note);
		note.kind = .NOTE;
		note.text = token.ident_value.name;
		if note.text.count && note.text[note.text.count - 1] == 0 {
			note.text.count -= 1;
		}

		finish_node(parser, note, first);
		array_add(*notes, note);
	}

	if !notes.count {
		return;
	}


	if declaration.kind == .DECLARATION {
		declaration.(*Parser_Declaration).notes = notes;
	} else if declaration.kind == .COMPOUND_DECLARATION {
		declaration.(*Parser_Compound_Declaration).notes = notes;
	}

	first: s64;
	#if ENABLE_TRIVIA {
		first = declaration.first_token.(s64);
	} else {
		first = parser.parsed.restart_points[parser.parsed.restart_points.count - 1].span.first.(s64);
	}

	finish_node(parser, declaration, first);
}

parse_declaration_expression :: (parser: *Parser, allow_multi_value_expression := true) -> *Parser_Node {
	first := parser.cursor;
	first_expression := parse_value_expression(parser);
	if !allow_multi_value_expression || !first_expression || parser_peek(parser).type != #char "," {
		return first_expression;
	}


	arguments: [..]Parser_Comma_Separated_Argument;
	arguments.allocator = parser_node_allocator(parser.parsed);
	array_add(*arguments, .{ node = first_expression });

	while parser_eat_if(parser, #char ",") {
		expression := parse_value_expression(parser);
		if !expression {
			add_expected_expression(parser);
			break;
		}


		array_add(*arguments, .{ node = expression });
	}

	result := new_parser_node(parser, Parser_Comma_Separated_Arguments);
	result.kind = .COMMA_SEPARATED_ARGUMENTS;
	result.arguments = arguments;
	finish_node(parser, result, first);
	return result;
}

// Parse type-only prefixes before general expressions so polymorphic bindings and pointer/view types keep their structure.
// For example, `*T`, `[] T`, and `#type distinct T` describe types here, while `*value` in an ordinary expression can instead mean address-of.
parse_type_instantiation :: (parser: *Parser) -> *Parser_Type_Instantiation {
	first := parser.cursor;

	token := parser_peek(parser);
	if parser_eat_if(parser, .DOUBLE_DOT) {
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


	if parser_eat_if(parser, #char "$") {
		name_token := parser_peek(parser);
		if !parser_eat_if(parser, .IDENT) {
			add_expected_expression(parser);
			return null;
		}


		ident := new_parser_node(parser, Parser_Ident);
		ident.kind = .IDENT;
		ident.name = name_token.ident_value.name;
		ident.flags |= .DEFINES_POLYMORPH_VARIABLE;
		finish_node(parser, ident, first);

		result := make_type_instantiation(parser, ident);
		if parser_eat_if(parser, #char "/") {
			if parser_eat_if(parser, .KEYWORD_INTERFACE)	result.inst_flags |= .INTERFACE;

			result.must_implement = parse_postfix(parser);
			if !result.must_implement {
				add_expected_expression(parser);
			}

			finish_node(parser, result, first);
		}

		return result;
	}


	is_type_directive := false;
	if token.type == #char "#" {
		lookahead := parser_peek(parser, 1);
		is_type_directive = (lookahead.type == .IDENT && lookahead.ident_value.name == "type");
	}

	if is_type_directive {
		parser_eat(parser, 2);

		result := new_parser_node(parser, Parser_Type_Instantiation);
		result.kind = .TYPE_INSTANTIATION;
		result.inst_flags |= .TYPE_DIRECTIVE;

		if parser_eat_if(parser, #char ",") {
			modifier := parser_peek(parser);
			if modifier.type == .IDENT {
				if modifier.ident_value.name == "distinct" {
					result.inst_flags |= .TYPE_DIRECTIVE_DISTINCT;
					parser_eat(parser);
				} else if modifier.ident_value.name == "isa" {
					result.inst_flags |= .TYPE_DIRECTIVE_ISA;
					parser_eat(parser);
				} else {
					add_unexpected_token(parser);
				}
			}
		}

		result.type_directive_target = parse_type_instantiation(parser);
		if !result.type_directive_target {
			add_expected_expression(parser);
		}

		finish_node(parser, result, first);
		return result;
	}


	if parser_eat_if(parser, #char "*") {
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


	if parser_eat_if(parser, #char "[") {
		result := new_parser_node(parser, Parser_Type_Instantiation);
		result.kind = .TYPE_INSTANTIATION;

		token = parser_peek(parser);
		if token.type == #char "]" {
			result.inst_flags |= .ARRAY_VIEW;
		} else if parser_eat_if(parser, .DOUBLE_DOT) {
			result.inst_flags |= .RESIZABLE;
		} else {
			result.array_dimension = parse_binary(parser);
			if !result.array_dimension {
				add_expected_expression(parser);
			}
		}

		parser_expect(parser, #char "]");

		result.array_element_type = parse_type_instantiation(parser);
		if !result.array_element_type {
			add_expected_expression(parser);
		}

		finish_node(parser, result, first);
		return result;
	}


	if parser_peek(parser).type == #char "(" {
		header := parse_procedure_type_header(parser);
		if !header {
			return null;
		}


		header.procedure_flags |= .TYPE_ONLY;

		result := new_parser_node(parser, Parser_Type_Instantiation);
		result.kind = .TYPE_INSTANTIATION;
		result.inst_flags |= .TYPE_OF_PROCEDURE;
		result.type_valued_expression = header;
		finish_node(parser, result, first);
		return result;
	}


	type_expression := parse_postfix(parser);
	return ifx type_expression
		then make_type_instantiation(parser, type_expression)
		else null;
}

// Give parameters their own scope so defaults and the eventual body resolve against the header's bindings.
// This also prevents a parameter named `value` from binding a same-named use in the enclosing file; unnamed type-only arguments have no declaration to bind.
parse_procedure_type_header :: (parser: *Parser, parse_body := false) -> *Parser_Procedure_Header {
	first := parser.cursor;

	parent_scope := parser.current_scope;
	push_lexical_scope(parser);
	defer parser.current_scope = parent_scope;

	quick := procedure_header_terminator(parser) == .QUICK_LAMBDA;
	parser_expect(parser, #char "(");

	arguments: [..]*Parser_Declaration;
	arguments.allocator = parser_node_allocator(parser.parsed);

	parameter_usings: [..]*Parser_Using;
	parameter_usings.allocator = parser_node_allocator(parser.parsed);

	while true {
		token := parser_peek(parser);
		if token.type == #char ")" || token.type == .END_OF_INPUT {
			break;
		}


		using_first := parser.cursor;
		marked_using := parser_eat_if(parser, .KEYWORD_USING);
		parameter_using: *Parser_Using;
		if marked_using {
			parameter_using = new_parser_node(parser, Parser_Using);
			parameter_using.kind = .USING;
			parse_using_filter(parser, parameter_using);
			token = parser_peek(parser);
		}

		argument: *Parser_Declaration;
		quick_argument := false;
		if quick && token.type == .IDENT {
			quick_argument = (parser_peek(parser, 1).type != #char ":");
		}

		if quick_argument {
			argument_first := parser.cursor;

			parser_eat(parser);

			argument = new_parser_node(parser, Parser_Declaration);
			argument.kind = .DECLARATION;
			argument.name = token.ident_value.name;
			finish_node(parser, argument, argument_first);
		} else if !marked_using && !looks_like_declaration(parser) {
			argument_first := parser.cursor;
			argument_type := parse_type_instantiation(parser);
			if !argument_type {
				add_expected_expression(parser);
				break;
			}


			argument = new_parser_node(parser, Parser_Declaration);
			argument.kind = .DECLARATION;
			argument.type_inst = argument_type;
			finish_node(parser, argument, argument_first);
		} else {
			// The comma separates parameters, not values in a parameter initializer.
			argument_node := parse_declaration_node(parser, false);
			if !argument_node || argument_node.kind != .DECLARATION {
				add_expected_expression(parser);
				break;
			}


			argument = argument_node.(*Parser_Declaration);
		}


		array_add(*arguments, argument);
		if marked_using {
			parameter_using.expression = argument;
			finish_node(parser, parameter_using, using_first);
			array_add(*parameter_usings, parameter_using);
		}

		if !parser_eat_if(parser, #char ",") {
			break;
		}
	}

	parser_expect(parser, #char ")");

	returns: [..]*Parser_Declaration;
	returns.allocator = parser_node_allocator(parser.parsed);
	if parser_eat_if(parser, .RIGHT_ARROW) {
		parenthesized := parser_eat_if(parser, #char "(");

		while true {
			if parenthesized && returns.count == 0 && parser_peek(parser).type == #char ")" {
				break;
			}


			return_first := parser.cursor;
			declaration: *Parser_Declaration;

			token := parser_peek(parser);
			named_return := (token.type == .IDENT && parser_peek(parser, 1).type == #char ":");
			if named_return {
				declaration = parse_declaration_node(parser, false).(*Parser_Declaration);
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
			if !parser_eat_if(parser, #char ",") {
				break;
			}
		}

		if parenthesized {
			parser_expect(parser, #char ")");
		}
	}

	result := new_parser_node(parser, Parser_Procedure_Header);
	result.kind = .PROCEDURE_HEADER;
	parser.current_scope.owner = result;
	result.arguments = arguments;
	result.returns = returns;
	result.parameter_usings = parameter_usings;
	if quick {
		result.procedure_flags |= .QUICK;
	}

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

	modify_directives: [..]*Parser_Directive_Modify;
	modify_directives.allocator = parser_node_allocator(parser.parsed);

	while parser_peek_if(parser, #char "#", .IDENT) && parser_peek(parser, 1).ident_value.name == "modify" {
		modify := parse_declaration_directive(parser);
		if !modify || modify.kind != .DIRECTIVE_MODIFY {
			break;
		}


		array_add(*modify_directives, modify.(*Parser_Directive_Modify));
	}

	result.modify_directives = modify_directives;

	if parse_body {
		parse_procedure_body(parser, result, first);
	}

	if !result.body_or_null && !(result.procedure_flags & .QUICK) {
		result.procedure_flags |= .TYPE_ONLY;
	}

	finish_node(parser, result, first);
	return result;
}

// Parse arrow-return shorthand in a child scope so named returns do not leak into the enclosing declaration.
parse_arrow_procedure_header :: (parser: *Parser, first: s64) -> *Parser_Procedure_Header {
	parent_scope := parser.current_scope;
	push_lexical_scope(parser);
	defer parser.current_scope = parent_scope;

	parser_expect(parser, .RIGHT_ARROW);

	returns: [..]*Parser_Declaration;
	returns.allocator = parser_node_allocator(parser.parsed);

	parenthesized := parser_eat_if(parser, #char "(");

	while true {
		return_first := parser.cursor;
		declaration: *Parser_Declaration;

		token := parser_peek(parser);
		named_return := (token.type == .IDENT && parser_peek(parser, 1).type == #char ":");
		if named_return {
			declaration_node := parse_declaration_node(parser, false);
			if declaration_node && declaration_node.kind == .DECLARATION {
				declaration = declaration_node.(*Parser_Declaration);
			}
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
		if !parser_eat_if(parser, #char ",") {
			break;
		}
	}

	if parenthesized {
		parser_expect(parser, #char ")");
	}

	result := new_parser_node(parser, Parser_Procedure_Header);
	result.kind = .PROCEDURE_HEADER;
	parser.current_scope.owner = result;
	result.returns = returns;

	parse_procedure_flags(parser, result);
	parse_procedure_body(parser, result, first);

	if !result.body_or_null {
		result.procedure_flags |= .TYPE_ONLY;
	}

	finish_node(parser, result, first);
	return result;
}

procedure_header_terminator :: (parser: *Parser) -> Token_Type {
	if parser_peek(parser).type != #char "(" {
		return .END_OF_INPUT;
	}


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

// A leading `(...)` can be a procedure header or a grouped condition.
// Peek past balanced parameters before deciding whether `{` begins a body or an `if` block.
looks_like_procedure_header :: (parser: *Parser) -> bool {
	terminator := procedure_header_terminator(parser);
	if terminator == #char "{" {
		depth := 1;
		has_parameter_declaration := false;
		index := parser.cursor + 1;
		while index < parser.parsed.tokens.count {
			type := parser.parsed.tokens[index].type;
			if type == #char "(" {
				depth += 1;
			} else if type == #char ")" {
				depth -= 1;
				if depth == 0 {
					break;
				}
			} else if depth == 1 {
				if type == #char ":" {
					has_parameter_declaration = true;
					break;
				}


				if type == .ISEQUAL || type == .ISNOTEQUAL || type == .LOGICAL_AND || type == .LOGICAL_OR || type == #char "%" {
					return false;
				}
			}


			index += 1;
		}


		// Without a parameter declaration, a parenthesized condition is not a procedure body.
		if parser.parsing_condition && !has_parameter_declaration && parser_peek(parser, 1).type != #char ")" {
			return false;
		}
	}


	return parser_peek(parser, 1).type == #char ")"
		|| terminator == .RIGHT_ARROW
		|| terminator == .QUICK_LAMBDA
		|| terminator == #char "{"
		|| terminator == #char "#"
		|| terminator == .KEYWORD_INLINE
		|| terminator == .KEYWORD_NO_INLINE;
}

// Stop at an unknown directive so the enclosing grammar can interpret it instead of consuming it as a procedure flag.
// Header flags like `#expand` belong to `(x: T) #expand { ... }`, but a later `#run` or `#insert` must remain available to its own expression parser.
parse_procedure_flags :: (parser: *Parser, result: *Parser_Procedure_Header) {
	while true {
		if parser_eat_if(parser, .KEYWORD_INLINE) {
			result.procedure_flags |= .SYNTACTICALLY_MARKED_AS_INLINE_YES;
			continue;
		}


		if parser_eat_if(parser, .KEYWORD_NO_INLINE) {
			result.procedure_flags |= .SYNTACTICALLY_MARKED_AS_INLINE_NO;
			continue;
		}


		token := parser_peek(parser);
		if token.type != #char "#" {
			break;
		}


		directive := parser_peek(parser, 1);
		if directive.type != .IDENT {
			break;
		}


		matched := true;
		name: string = directive.ident_value.name;
		if name == {
			case "expand";
				result.procedure_flags |= .MACRO;

			case "compile_time";
				result.procedure_flags |= .COMPILE_TIME_ONLY;
				result.procedure_flags |= .SYNTACTICALLY_MARKED_AS_COMPILE_TIME;

			case "compiler";
				result.procedure_flags |= .COMPILE_TIME_ONLY;
				result.procedure_flags |= .SYNTACTICALLY_MARKED_AS_COMPILER;

			case "no_context";
				result.procedure_flags |= .SYNTACTICALLY_MARKED_AS_NO_CONTEXT;

			case "c_call";
				result.procedure_flags |= .C_CALL;

			case "intrinsic";
				result.procedure_flags |= .INTRINSIC;

			case "no_debug";
				result.procedure_flags |= .NO_DEBUG;

			case "dump";
				result.procedure_flags |= .DEBUG_DUMP;

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

		if !matched {
			break;
		}


		parser_eat(parser, 2);
		if name == "deprecated" && parser_peek(parser).type == .STRING {
			result.deprecation_string = parser_eat(parser).string_value;
		} else if name == "foreign" {
			library_first := parser.cursor;
			library := parser_peek(parser);

			if parser_eat_if(parser, .IDENT) {
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

// Represent expression-bodied quick lambdas as blocks with implicit returns to share downstream body handling.
parse_procedure_body :: (parser: *Parser, header: *Parser_Procedure_Header, first: s64) {
	body := new_parser_node(parser, Parser_Procedure_Body);
	body.kind = .PROCEDURE_BODY;
	body.header = header;

	if parser_eat_if(parser, .QUICK_LAMBDA) {
		header.procedure_flags |= .QUICK;

		if parser_peek(parser).type == #char "{" {
			header.procedure_flags |= .QUICK_IN_BLOCK_FORM;
			body.block = parse_block_node(parser);
		} else {
			expression := parse_binary(parser);
			if !expression{
				add_expected_expression(parser);
			}


			return_node := new_parser_node(parser, Parser_Return);
			return_node.kind = .RETURN;
			return_node.return_flags |= .AUTO_INSERTED_FOR_QUICK_LAMBDA;

			if expression {
				arguments: [..]Parser_Argument;
				arguments.allocator = parser_node_allocator(parser.parsed);
				array_add(*arguments, .{expression=expression});
				return_node.arguments_unsorted = arguments;
			}

			finish_node(parser, return_node, first);


			statements: [..]*Parser_Node;
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
	if !type_inst{
		return false;
	}


	if type_inst.type_valued_expression && type_inst.type_valued_expression.kind == .IDENT {
		return ((type_inst.type_valued_expression.(*Parser_Ident).flags & .DEFINES_POLYMORPH_VARIABLE) != 0);
	}


	return type_instantiation_is_polymorphic(type_inst.pointer_to)
		|| type_instantiation_is_polymorphic(type_inst.array_element_type)
		|| type_instantiation_is_polymorphic(type_inst.type_directive_target);
}

// Keep aggregate members in a child scope, while allowing struct modifiers in each position accepted by the grammar.
// Enum bodies hold member names, while struct and union bodies hold declarations and defaults; parameters such as `struct (T: Type) { value: T; }` precede that body.
parse_aggregate_definition :: (parser: *Parser) -> *Parser_Node {
	first := parser.cursor;
	keyword := parser_eat(parser);

	parent_scope := parser.current_scope;
	push_lexical_scope(parser);
	defer parser.current_scope = parent_scope;

	if keyword.type == .KEYWORD_ENUM || keyword.type == .KEYWORD_ENUM_FLAGS {
		result := new_parser_node(parser, Parser_Enum);
		result.kind = .ENUM;
		parser.current_scope.owner = result;
		result.is_flags = keyword.type == .KEYWORD_ENUM_FLAGS;

		token := parser_peek(parser);
		if token.type != #char "#" && token.type != #char "{" {
			result.internal_type_inst = parse_type_instantiation(parser);
			if !result.internal_type_inst {
				add_expected_expression(parser);
			}
		}


		while true {
			token = parser_peek(parser);
			if token.type != #char "#" {
				break;
			}


			directive := parser_peek(parser, 1);
			if directive.type != .IDENT {
				break;
			}


			name := directive.ident_value.name;
			if name != "complete" && name != "specified" {
				break;
			}


			parser_eat(parser, 2);
			if name == "complete" {
				result.marked_as_complete = true;
			} else {
				result.marked_as_specified = true;
			}
		}

		result.block = parse_aggregate_block(parser, true);
		if !result.block {
			parser_expect(parser, #char "{");
		}

		finish_node(parser, result, first);
		return result;
	}


	result := new_parser_node(parser, Parser_Struct);
	result.kind = .STRUCT;
	parser.current_scope.owner = result;
	if keyword.type == .KEYWORD_UNION {
		result.textual_flags |= .UNION;
	}

	parse_struct_modifiers(parser, result);
	if parser_peek(parser).type == #char "(" {
		result.arguments_block = parse_aggregate_parameter_block(parser);
	}

	parse_struct_modifiers(parser, result);

	modify_directives: [..]*Parser_Directive_Modify;
	modify_directives.allocator = parser_node_allocator(parser.parsed);

	while parser_peek_if(parser, #char "#", .IDENT) && parser_peek(parser, 1).ident_value.name == "modify" {
		modify := parse_declaration_directive(parser);
		if !modify || modify.kind != .DIRECTIVE_MODIFY {
			break;
		}


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

	statements: [..]*Parser_Node;
	statements.allocator = parser_node_allocator(parser.parsed);

	token := parser_peek(parser);
	while token.type != #char ")" && token.type != .END_OF_INPUT {
		parameter := parse_declaration_node(parser, false);
		if !parameter {
			add_expected_expression(parser);
			parser_synchronise(parser, .DECLARATION);
			break;
		}


		array_add(*statements, parameter);
		if !parser_eat_if(parser, #char ",") {
			break;
		}


		token = parser_peek(parser);
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

parse_enum_member :: (parser: *Parser) -> *Parser_Ident {
	first := parser.cursor;
	token := parser_eat(parser);
	result := new_parser_node(parser, Parser_Ident);
	result.kind = .IDENT;
	result.name = token.ident_value.name;
	finish_node(parser, result, first);
	return result;
}

// An aggregate body uses declaration grammar, except bare enum members and field-default assignments such as `field = 1` or `info.flavor = "sweet"`.
parse_aggregate_block :: (parser: *Parser, enum_members: bool) -> *Parser_Block {
	first := parser.cursor;
	if !parser_eat_if(parser, #char "{") {
		return null;
	}


	parent_scope := parser.current_scope;
	push_lexical_scope(parser);
	defer parser.current_scope = parent_scope;

	result := new_parser_node(parser, Parser_Block);
	result.kind = .BLOCK;
	parser.current_scope.owner = result;
	result.block_type = .DATA_DECLARATIONS;
	result.node_flags |= .IS_PARENTHESIZED;

	statements: [..]*Parser_Node;
	statements.allocator = parser_node_allocator(parser.parsed);

	while true {
		token := parser_peek(parser);
		if token.type == #char "}" || token.type == .END_OF_INPUT {
			break;
		}


		guard := parser_progress_guard(parser);
		member: *Parser_Node;
		assignment_lookahead: s64 = 1;

		if !enum_members && token.type == .IDENT {
			while parser_peek(parser, assignment_lookahead).type == #char "." && parser_peek(parser, assignment_lookahead + 1).type == .IDENT {
				assignment_lookahead += 2;
			}
		}

		if enum_members && token.type == .IDENT && parser_peek(parser, 1).type == #char ";" {
			member = parse_enum_member(parser);
		} else if enum_members && parser_peek_if(parser, #char "#", .KEYWORD_IF) {
			member = parse_static_if_statement(parser, result, .DATA_DECLARATIONS, true);
		} else if !enum_members && token.type == .IDENT && parser_peek(parser, assignment_lookahead).type == #char "=" {
			// Field defaults, including dotted targets, assign to existing members rather than declare new ones.
			member = parse_binary(parser);
			if member && member.kind == .BINARY_OPERATOR {
				assignment := member.(*Parser_Binary_Operator);
				left := assignment.left;
				while left.kind == .BINARY_OPERATOR && left.(*Parser_Binary_Operator).operator_type == #char "." {
					left = left.(*Parser_Binary_Operator).left;
				}

				if assignment.operator_type == #char "=" && left.kind == .IDENT {
					ident := left.(*Parser_Ident);
					for statements {
						if it.kind != .DECLARATION {
							continue;
						}


						declaration := it.(*Parser_Declaration);
						if declaration.name == ident.name {
							ident.resolved_declaration = declaration;
						}
					}
				}
			}
		} else {
			member = parse_declaration_node(parser);
		}

		if member {
			array_add(*statements, member);
			finish_statement(parser, member);
		} else {
			add_unexpected_token(parser);
			parser_synchronise(parser, .DECLARATION);
		}

		if !parser_ensure_progress(parser, guard) {
			break;
		}
	}

	parser_expect(parser, #char "}");

	result.statements = statements;
	finish_node(parser, result, first);
	return result;
}

parse_struct_modifiers :: (parser: *Parser, result: *Parser_Struct) {
	while parser_peek(parser).type == #char "#" && parser_peek(parser, 1).type == .IDENT {
		matched := true;

		name: string= parser_peek(parser, 1).ident_value.name;
		if name == {
			case "foreign";									result.textual_flags |= .FOREIGN;
			case "no_padding";								result.textual_flags |= .NO_PADDING;
			case "type_info_none";							result.textual_flags |= .TYPE_INFO_NONE;
			case "type_info_no_size_complaint";				result.textual_flags |= .TYPE_INFO_NO_SIZE_COMPLAINT;
			case "type_info_procedures_are_void_pointers";	result.textual_flags |= .TYPE_INFO_PROCEDURES_ARE_VOID_POINTERS;

			case "align";
				parser_eat(parser, 2);
				if parser_peek(parser).type == .NUMBER {
					result.alignment = xx parser_eat(parser).integer_value;
				} else {
					add_expected_expression(parser);
				}
				continue;

			case;
				matched = false;
		}


		if !matched {
			break;
		}


		parser_eat(parser, 2);
	}
}

// Consume only directives valid in declaration position; unknown names remain for the caller's recovery path.
// `#placeholder Name` and `#as using field: T` introduce declaration-shaped nodes, whereas expression-only directives must not consume the next declaration.
parse_declaration_directive :: (parser: *Parser) -> *Parser_Node {
	if !parser_peek_if(parser, #char "#", .IDENT) {
		return null;
	}


	first := parser.cursor;
	directive := parser_peek(parser, 1);
	name: string = directive.ident_value.name;
	if name == {
		case "as";
			parser_eat(parser, 2);
			if !parser_expect(parser, .KEYWORD_USING) {
				return null;
			}


			result := parse_using_statement_after_keyword(parser, first);
			if result.expression && result.expression.kind == .DECLARATION {
				result.expression.(*Parser_Declaration).flags |= .IS_MARKED_AS_AS;
			}

			return result;

		case "scope_module"; #through;
		case "scope_export"; #through;
		case "scope_file";
			parser_eat(parser, 2);

			result := new_parser_node(parser, Parser_Directive_Scope);
			result.kind = .DIRECTIVE_SCOPE;
			if name == {
				case "scope_module";	result.scope_type = .INTERNAL;
				case "scope_export";	result.scope_type = .EXPORT;
				case "scope_file";		result.scope_type = .FILE;
			}

			finish_node(parser, result, first);
			return result;

		case "through";
			parser_eat(parser, 2);

			result := new_parser_node(parser, Parser_Directive_Through);
			result.kind = .DIRECTIVE_THROUGH;
			finish_node(parser, result, first);
			return result;

		case "add_context";
			parser_eat(parser, 2);

			result := new_parser_node(parser, Parser_Directive_Add_Context);
			result.kind = .DIRECTIVE_ADD_CONTEXT;
			result.expression = parse_declaration_node(parser);
			if !result.expression {
				add_expected_expression(parser);
			}

			finish_node(parser, result, first);
			return result;

		case "overlay";
			parser_eat(parser, 2);

			parser_expect(parser, #char "(");

			result := new_parser_node(parser, Parser_Directive_Overlay);
			result.kind = .DIRECTIVE_OVERLAY;
			result.target_expression = parse_binary(parser);
			if !result.target_expression {
				add_expected_expression(parser);
			}

			parser_expect(parser, #char ")");

			result.declaration_or_using = ifx parser_peek(parser).type == .KEYWORD_USING
				then parse_using_statement(parser).(*Parser_Node)
				else parse_declaration_node(parser);

			if !result.declaration_or_using {
				add_expected_expression(parser);
			}

			finish_node(parser, result, first);
			return result;

		case "modify";
			parser_eat(parser, 2);

			result := new_parser_node(parser, Parser_Directive_Modify);
			result.kind = .DIRECTIVE_MODIFY;
			result.block = parse_block_node(parser);
			if !result.block {
				parser_expect(parser, #char "{");
			}

			finish_node(parser, result, first);
			return result;

		case "module_parameters";
			parser_eat(parser, 2);

			result := new_parser_node(parser, Parser_Directive_Module_Parameters);
			result.kind = .DIRECTIVE_MODULE_PARAMETERS;
			token := parser_peek(parser);
			if token.type == {
				case #char "(";
					result.module_parameters = parse_procedure_type_header(parser);
					if parser_peek(parser).type == {
						case #char "(";
							result.program_parameters = parse_procedure_type_header(parser);
							if parser_peek(parser).type == #char "{" {
								result.common_code = parse_block_node(parser);
							}

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

parser_eat :: inline (parser: *Parser, count: s64 = 1) -> *Parser_Token {
	assert(count > 0);
	result := parser_peek(parser);
	parser.cursor += 1;
	count -= 1;

	while count > 0 && result.type != .END_OF_INPUT {
		result = parser_peek(parser);
		parser.cursor += 1;
		count -= 1;
	}

	return result;
}

parser_peek_if :: inline (parser: *Parser, expected: ..Token_Type) -> bool {
	assert(expected.count > 0);
	if parser.cursor + expected.count > parser.parsed.tokens.count {
		return false;
	}


	for expected {
		if parser_peek(parser, it_index).type != it {
			return false;
		}
	}

	return true;
}

parser_eat_if :: inline (parser: *Parser, expected: ..Token_Type) -> bool {
	if !parser_peek_if(parser, ..expected) {
		return false;
	}


	parser_eat(parser, expected.count);
	return true;
}

parser_expect :: inline (parser: *Parser, expected: ..Token_Type) -> bool {
	assert(expected.count > 0);
	for expected {
		if parser_peek(parser).type != it {
			add_missing_token(parser, it);
			return false;
		}


		parser_eat(parser);
	}


	return true;
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
	return .{ cursor = parser.cursor };
}

parser_ensure_progress :: inline (parser: *Parser, guard: Parser_Progress_Guard) -> bool {
	assert(parser.cursor >= guard.cursor);
	if parser.cursor > guard.cursor {
		return true;
	}


	if parser_peek(parser).type == .END_OF_INPUT {
		return false;
	}


	first := parser.cursor;
	parser_eat(parser);

	array_add(
		*parser.parsed.recovery_records,
		Recovery_Record.{
			kind = .SKIPPED_TOKENS,
			span = make_token_span(first, parser.cursor),
			diagnostic_index = -1
		}
	);

	return true;
}

is_synchronization_point :: (token_type: Token_Type, synchronization_context: Synchronization_Context) -> bool {
	if token_type == .END_OF_INPUT {
		return true;
	}


	if synchronization_context == {
		case .EXPRESSION;
			if token_type == {
				case #char ",";	#through;
				case #char ";";	#through;
				case #char ")";	#through;
				case #char "]";	#through;
				case #char "}";
					return true;
			}

		case .STATEMENT;
			if token_type == {
				case #char ";";				#through;
				case #char "}";				#through;
				case .IDENT;				#through;
				case .KEYWORD_IF;			#through;
				case .KEYWORD_IFX;			#through;
				case .KEYWORD_FOR;			#through;
				case .KEYWORD_WHILE;		#through;
				case .KEYWORD_RETURN;		#through;
				case .KEYWORD_DEFER;		#through;
				case .KEYWORD_USING;		#through;
				case .KEYWORD_PUSH_CONTEXT;	#through;
				case .KEYWORD_BREAK;		#through;
				case .KEYWORD_CONTINUE;		#through;
				case .KEYWORD_REMOVE;		#through;
				case .KEYWORD_CASE;			#through;
				case .KEYWORD_ELSE;
					return true;
			}

		case .DECLARATION;
			if token_type == {
				case #char ";";				#through;
				case #char "}";				#through;
				case .IDENT;				#through;
				case .NOTE;					#through;
				case .KEYWORD_USING;		#through;
				case .KEYWORD_STRUCT;		#through;
				case .KEYWORD_UNION;		#through;
				case .KEYWORD_ENUM;			#through;
				case .KEYWORD_ENUM_FLAGS;	#through;
				case .KEYWORD_INTERFACE;	#through;
				case .KEYWORD_OPERATOR;
					return true;
			}

		case .BLOCK;
			return token_type == #char "}";
	}


	return false;
}

// Resume at a boundary the caller can still consume; ignore candidate boundaries inside nested delimiters so a malformed child cannot masquerade as an outer statement.
parser_synchronise :: (parser: *Parser, synchronization_context: Synchronization_Context, record_skip := true) -> Token_Span {
	first := parser.cursor;
	parenthesis_depth: s64;
	bracket_depth: s64;
	brace_depth: s64;

	while true {
		token := parser_peek(parser);
		at_top_level := !parenthesis_depth && !bracket_depth && !brace_depth;
		// Delimiters inside a damaged construct are not safe restart points.
		if at_top_level && is_synchronization_point(token.type, synchronization_context) {
			break;
		}


		if token.type == .END_OF_INPUT {
			break;
		}


		completed_braced_region := false;
		if token.type == {
			case #char "(";							parenthesis_depth += 1;
			case #char ")";	if parenthesis_depth	parenthesis_depth -= 1;

			case #char "[";							bracket_depth += 1;
			case #char "]";	if bracket_depth 		bracket_depth -= 1;

			case #char "{";							brace_depth += 1;
			case #char "}";
				if brace_depth {
					brace_depth -= 1;
					completed_braced_region = !brace_depth;
				}
		}

		parser_eat(parser);
		// Stop after a complete nested block so its contents cannot become outer statements.
		if completed_braced_region && synchronization_context != .BLOCK {
			break;
		}
	}

	span := make_token_span(first, parser.cursor);
	if record_skip && parser.cursor > first {
		array_add(
			*parser.parsed.recovery_records,
			Recovery_Record.{
				kind = .SKIPPED_TOKENS,
				span = span,
				diagnostic_index = -1
			}
		);
	}

	return span;
}

// Raise the minimum precedence for left-associative operators so the right side cannot absorb a peer operator.
parse_binary :: (parser: *Parser, minimum_precedence: s32 = 1) -> *Parser_Node {
	previous_allow_unprefixed_struct_literal := parser.allow_unprefixed_struct_literal;
	if parser_peek(parser).type != #char "{" {
		parser.allow_unprefixed_struct_literal = true;
	}
	defer parser.allow_unprefixed_struct_literal = previous_allow_unprefixed_struct_literal;

	first := parser.cursor;

	left := parse_prefix(parser);
	if !left {
		return null;
	}


	while true {
		is_binary, operator_type, precedence, right_associative := binary_operator_info(parser_peek(parser).type);
		if !is_binary || precedence < minimum_precedence{
			break;
		}


		operator_index := parser.cursor;
		parser_eat(parser);

		diagnostic_count := parser.parsed.diagnostics.count;
		next_precedence := precedence + xx !right_associative;

		right := parse_value_expression(parser, next_precedence);
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

		if !right{
			break;
		}
	}

	return left;
}

parse_value_expression :: (parser: *Parser, minimum_precedence: s32 = 1) -> *Parser_Node {
	previous_allow_unprefixed_struct_literal := parser.allow_unprefixed_struct_literal;
	parser.allow_unprefixed_struct_literal = true;
	defer parser.allow_unprefixed_struct_literal = previous_allow_unprefixed_struct_literal;

	return parse_binary(parser, minimum_precedence);
}

/*
	See print_precedence.jai for how operator precedence is calculated.
	Higher precedence numbers bind more tightly: in a + b * c, * groups before +.
	Lower numbers bind more loosely and combine the results of higher-precedence operators.
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
		case #char "^";		operator_type = token_type.(Operator_Type);		precedence = 8;

		case #char "*"; #through;
		case #char "/";		operator_type = token_type.(Operator_Type);		precedence = 7;

		case #char "%";		operator_type = token_type.(Operator_Type);		precedence = 6;

		case #char "+"; #through;
		case #char "-";		operator_type = token_type.(Operator_Type);		precedence = 5;

		case .ISEQUAL;				operator_type = .IS_EQUAL;				precedence = 4;
		case .ISNOTEQUAL;			operator_type = .IS_NOT_EQUAL;			precedence = 4;
		case .LESSEQUALS;			operator_type = .LESS_OR_EQUAL;			precedence = 4;
		case .GREATEREQUALS;		operator_type = .GREATER_OR_EQUAL;		precedence = 4;
		case #char "<"; #through;
		case #char ">";		operator_type = token_type.(Operator_Type);		precedence = 4;

		case .LOGICAL_AND;			operator_type = .LOGICAL_AND;			precedence = 3;

		case .LOGICAL_OR;			operator_type = .LOGICAL_OR;			precedence = 2;

		case #char "=";		operator_type = token_type.(Operator_Type);		precedence = 1;
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

// Recognize explicit type prefixes before unary operators, since the same punctuation can begin either form.
// `[3] T` and `*[] T` are type-valued expressions; `-3` stays a signed literal, and a leading `.` binds to its immediate primary before later postfix access.
parse_prefix :: (parser: *Parser) -> *Parser_Node {
	first := parser.cursor;
	token := parser_peek(parser);
	negative_number := parser_peek_if(parser, #char "-", .NUMBER);
	starts_explicit_type := token.type == #char "["
		|| token.type == .DOUBLE_DOT
		|| token.type == #char "$"
		|| token.type == #char "*" && parser_peek(parser, 1).type == #char "[";
	if starts_explicit_type {
		return parse_type_instantiation(parser);
	}


	if parser_eat_if(parser, #char ".") {
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


	if parser_eat_if(parser, .KEYWORD_AUTO_CAST) {
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


	if parser_eat_if(parser, .KEYWORD_CAST) {
		cast_flags: type_of(Code_Cast.cast_flags);
		while parser_eat_if(parser, #char ",") {
			modifier := parser_peek(parser);
			if modifier.type != .IDENT {
				parser_expect(parser, .IDENT);
				break;
			}


			modifier_name: string = modifier.ident_value.name;
			if modifier_name == {
				case "no_check";	cast_flags |= .NO_BOUNDS_CHECK;
				case "truncate";	cast_flags |= .TRUNCATE;
				case "force";		cast_flags |= .FORCE;
				case "very_force";	cast_flags |= .VERY_FORCE;
				case;
					add_unexpected_token(parser);
					break;
			}


			parser_eat(parser);
		}

		parser_expect(parser, #char "(");

		target_type := parse_type_instantiation(parser);
		if !target_type {
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
		result.target_type = target_type;
		result.expression = expression;
		result.cast_flags = cast_flags;
		finish_node(parser, result, first);
		return result;
	}


	operator_type: Operator_Type;
	if token.type == {
		case #char "+"; #through;
		case #char "-"; #through;
		case #char "*"; #through;
		case #char "!"; #through;
		case #char "~";
			operator_type = token.type.(Operator_Type);

		// Prefix dereference `(.*)`, e.g. `(.*)value`, applies before postfix access.
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


	if negative_number {
		literal := subexpression.(*Parser_Literal);
		if literal.value_flags & .FLOAT {
			literal._float64 = -literal._float64;
		} else {
			literal._u64 = 0 - literal._u64;
			literal.value_flags |= .MINUS_SIGN;
		}

		return finish_node(parser, literal, first);
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
			// Call suffix `(x)`, e.g. `make(1)` or `factory()(2)`.
			case #char "(";
				result = parse_procedure_call(parser, result, first);

			// Index suffix `[i]`, e.g. `items[0]`.
			case #char "[";
				parser_eat(parser);

				index := parse_binary(parser);
				if !index{
					add_expected_expression(parser);
				}

				parser_expect(parser, #char "]");

				subscript := new_parser_node(parser, Parser_Binary_Operator);
				subscript.kind = .BINARY_OPERATOR;
				subscript.operator_type = .ARRAY_SUBSCRIPT;
				subscript.left = result;
				subscript.right = index;
				result = finish_node(parser, subscript, first);

			// Postfix dereference `.*`, e.g. `pointer.*`.
			case .POSTFIX_DEREFERENCE;
				parser_eat(parser);

				dereference := new_parser_node(parser, Parser_Unary_Operator);
				dereference.kind = .UNARY_OPERATOR;
				dereference.operator_type = .POSTFIX_DEREFERENCE;
				dereference.subexpression = result;
				result = finish_node(parser, dereference, first);

			// Member `.name` or postfix cast `.(T)`, e.g. `item.field` / `value.(s64)`.
			case #char ".";
				parser_eat(parser);
				if parser_eat_if(parser, #char "(") {
					target_type := parse_type_instantiation(parser);
					if !target_type {
						add_expected_expression(parser);
						return result;
					}


					parser_expect(parser, #char ")");

					cast_node := new_parser_node(parser, Parser_Cast);
					cast_node.kind = .CAST;
					cast_node.target_type = target_type;
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

			// Typed array literal prefix, e.g. `T.[1, 2]`.
			case .BEGIN_ARRAY_LITERAL;
				result = parse_aggregate_literal(parser, .ARRAY, result, first);

			// Typed struct literal prefix, e.g. `T.{field = 1}`.
			case .BEGIN_STRUCT_LITERAL;
				result = parse_aggregate_literal(parser, .STRUCT, result, first);

			// No more postfix syntax: leave the next token to the enclosing expression.
			case;
				break;
		}
	}

	return result;
}

// Treat `,,` as the boundary between ordinary arguments and call-local context modifications.
// In `f(x, name=y,, allocator=arena)`, the first two are call arguments; `allocator=arena` is retained separately as source-spelled context replacement.
parse_procedure_call :: (parser: *Parser, procedure: *Parser_Node, first: s64) -> *Parser_Node {
	parser_eat(parser);

	arguments: [..]Parser_Argument;
	arguments.allocator = parser_node_allocator(parser.parsed);
	context_modification: *Parser_Context_Modification;

	while true {
		token := parser_peek(parser);
		if token.type == #char ")" || token.type == .END_OF_INPUT{
			break;
		}


		if parser_eat_if(parser, .DOUBLE_COMMA) {
			context_modification = new_parser_node(parser, Parser_Context_Modification);

			expressions: [..]*Parser_Node;
			expressions.allocator = parser_node_allocator(parser.parsed);

			while parser_peek(parser).type != #char ")" && parser_peek(parser).type != .END_OF_INPUT {
				expression := parse_value_expression(parser);
				if !expression {
					add_expected_expression(parser);
					parser_synchronise(parser, .EXPRESSION);
					break;
				}


				array_add(*expressions, expression);
				if !parser_eat_if(parser, #char ",") {
					break;
				}
			}

			if !expressions.count {
				add_expected_expression(parser);
			}

			context_modification.modification_expressions = expressions;
			break;
		}

		argument: Parser_Argument;
		name_first := parser.cursor;
		if parser_eat_if(parser, .IDENT, #char "=") {
			argument.name = new_parser_node(parser, Parser_Ident);
			argument.name.kind = .IDENT;
			argument.name.name = token.ident_value.name;
			finish_node(parser, argument.name, name_first);
		}

		argument.expression = parse_value_expression(parser, 2);
		if !argument.expression {
			add_expected_expression(parser);
			parser_synchronise(parser, .EXPRESSION);
			break;
		}


		array_add(*arguments, argument);

		if !parser_eat_if(parser, #char ",") {
			if parser_peek(parser).type == .DOUBLE_COMMA {
				continue;
			}


			break;
		}
	}

	parser_expect(parser, #char ")");

	result := new_parser_node(parser, Parser_Procedure_Call);
	result.kind = .PROCEDURE_CALL;
	result.procedure_expression = procedure;
	result.arguments_unsorted = arguments;
	result.context_modification = context_modification;
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

// Build array or struct literals in either typed postfix form (`T.[1]`, `T.{x=1}`) or untyped primary form (`.[1]`, `.{x=1}`), retaining the contextual type separately.
parse_aggregate_literal :: (
	parser: *Parser,
	value_type: type_of(Code_Literal.value_type),
	type_expression: *Parser_Node,
	first: s64
) -> *Parser_Node {
	assert(value_type == .ARRAY || value_type == .STRUCT);
	closing_token := ifx value_type == .ARRAY
		then (#char "]").(Token_Type)
		else (#char "}").(Token_Type);

	parser_eat(parser);

	members: [..]*Parser_Node;
	members.allocator = parser_node_allocator(parser.parsed);

	while true {
		token := parser_peek(parser);
		if token.type == closing_token || token.type == .END_OF_INPUT{
			break;
		}

		member := parse_value_expression(parser);
		if !member {
			add_expected_expression(parser);
			parser_synchronise(parser, .EXPRESSION);
			break;
		}


		array_add(*members, member);

		if !parser_eat_if(parser, #char ",") {
			break;
		}
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
		if type_expression {
			info.type_expression = make_type_instantiation(parser, type_expression);
		}

		info.arguments = members;
		result.struct_literal_info = info;
	}

	finish_node(parser, result, first);
	return result;
}

// Dispatch context-sensitive prefixes here before treating their following tokens as ordinary postfix expressions.
parse_primary :: (parser: *Parser) -> *Parser_Node {
	first := parser.cursor;
	token := parser_peek(parser);

	if token.type == {
		// Value conditional `ifx condition then a else b` (not a statement `if`).
		case .KEYWORD_IFX;
			return parse_if_statement(parser, null, true);

		// Inline hint before a call or header, e.g. `inline f()` / `inline (x: T) { ... }`.
		case .KEYWORD_INLINE; #through;
		case .KEYWORD_NO_INLINE;
			parser_eat(parser);
			if parser_peek(parser).type != #char "(" || !looks_like_procedure_header(parser) {
				call := parse_postfix(parser);
				if !call || call.kind != .PROCEDURE_CALL {
					add_expected_expression(parser);
					return null;
				}


				call.(*Parser_Procedure_Call).flags |= ifx token.type == .KEYWORD_INLINE
					then .INLINE_YES
					else .INLINE_NO;

				finish_node(parser, call, first);
				return call;
			}


			header := parse_procedure_type_header(parser, true);
			header.procedure_flags |= ifx token.type == .KEYWORD_INLINE
				then .SYNTACTICALLY_MARKED_AS_INLINE_YES
				else .SYNTACTICALLY_MARKED_AS_INLINE_NO;

			finish_node(parser, header, first);
			return header;

		// Aggregate type value, e.g. `struct { x: s64; }` or `enum u8 { A; }`.
		case .KEYWORD_STRUCT; #through;
		case .KEYWORD_UNION; #through;
		case .KEYWORD_ENUM; #through;
		case .KEYWORD_ENUM_FLAGS;
			return parse_aggregate_definition(parser);

		// Query an expression, e.g. `type_of(value)` or `is_constant(value)`.
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

		// Query a type, e.g. `size_of(T)` or `type_info(T)`.
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

		// Expression directive `#run x`, `#ifx ...`, or `#string` here-string.
		case #char "#";
			directive_name := parser_peek(parser, 1);
			if directive_name.type == .KEYWORD_IFX {
				parser_eat(parser);
				result := parse_if_statement(parser, null, true);
				result.if_flags |= .IS_STATIC;
				finish_node(parser, result, first);
				return result;
			}


			if directive_name.type != .IDENT				return null;
			if directive_name.ident_value.name == "type"	return parse_type_instantiation(parser);
			if directive_name.ident_value.name != "string"	return parse_expression_directive(parser, first, directive_name.ident_value.name);


			parser_eat(parser, 2);

			while parser_eat_if(parser, #char ",") {
				parser_expect(parser, .IDENT);
			}

			parser_expect(parser, .IDENT);

			body := parser_peek(parser);
			if !parser_eat_if(parser, .STRING) {
				add_expected_expression(parser);
				return null;
			}


			parser_expect(parser, .IDENT);

			result := new_parser_node(parser, Parser_Literal);
			result.kind = .LITERAL;
			result.value_type = .STRING;
			result._string = body.string_value;
			result.value_flags |= .HERE_STRING;
			finish_node(parser, result, first);
			return result;

		// Untyped array literal `.[1, 2]`.
		case .BEGIN_ARRAY_LITERAL;
			return parse_aggregate_literal(parser, .ARRAY, null, first);

		// Struct literal `.{x=1}`; bare `{x=1}` only where a value is expected.
		case .BEGIN_STRUCT_LITERAL; #through;
		case #char "{";
			return ifx token.type == #char "{" && !parser.allow_unprefixed_struct_literal
				then null
				else parse_aggregate_literal(parser, .STRUCT, null, first);

		// Uninitialised marker `---`, retained as a literal for standalone parsing.
		case .TRIPLE_MINUS;
			parser_eat(parser);

			result := new_parser_node(parser, Parser_Literal);
			result.kind = .LITERAL;
			result.value_type = .UNINITIALIZED;
			finish_node(parser, result, first);
			return result;

		// Group `(a + b)` or procedure header `(x: T) -> T { ... }`.
		case #char "(";
			if looks_like_procedure_header(parser) {
				return parse_procedure_type_header(parser, true);
			}


			parser_eat(parser);

			result := parse_value_expression(parser);
			if !result {
				add_expected_expression(parser);
				return null;
			}


			parser_expect(parser, #char ")");

			result.node_flags |= .IS_PARENTHESIZED;
			finish_node(parser, result, first);
			return result;

		// Identifier `value` or single-argument quick lambda `x => x + 1`.
		case .IDENT;
			if parser_peek(parser, 1).type == .QUICK_LAMBDA {
				parser_eat(parser);

				parent_scope := parser.current_scope;
				push_lexical_scope(parser);
				defer parser.current_scope = parent_scope;

				argument := new_parser_node(parser, Parser_Declaration);
				argument.kind = .DECLARATION;
				argument.name = token.ident_value.name;
				finish_node(parser, argument, first);

				header := new_parser_node(parser, Parser_Procedure_Header);
				header.kind = .PROCEDURE_HEADER;
				parser.current_scope.owner = header;
				header.procedure_flags |= .QUICK;

				arguments: [..]*Parser_Declaration;
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
			array_add(*parser.current_scope.references, result);
			return result;

		// Numeric literal `42`, `0xFF`, or `1.5`, preserving spelling-dependent flags.
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

			if token.value_flags & .HEX						result.value_flags |= .HEX;
			if token.value_flags & .BINARY					result.value_flags |= .BINARY;
			if token.value_flags & .DEFAULTS_TO_FLOAT64		result.value_flags |= .DEFAULTS_TO_FLOAT64;
			if token.value_flags & .REQUIRES_FLOAT64		result.value_flags |= .REQUIRES_FLOAT64;
			if token.value_flags & .REQUIRES_FLOAT64_DUE_TO_SIGNIFICANT_DIGITS {
				result.value_flags |= xx Code_Literal_Value_Flags_SIGNIFICANT_DIGITS;
			}

			finish_node(parser, result, first);
			return result;

		// Quoted or materialised here-string body, e.g. `"text"`.
		case .STRING;
			parser_eat(parser);

			result := new_parser_node(parser, Parser_Literal);
			result.kind = .LITERAL;
			result.value_type = .STRING;
			result._string = token.string_value;
			if token.value_flags & .HERE_STRING{
				result.value_flags |= .HERE_STRING;
			}

			finish_node(parser, result, first);
			return result;

		// Boolean literals `true` and `false`.
		case .KEYWORD_TRUE; #through;
		case .KEYWORD_FALSE;
			parser_eat(parser);

			result := new_parser_node(parser, Parser_Literal);
			result.kind = .LITERAL;
			result.value_type = .BOOLEAN;
			result._u64 = xx (token.type == .KEYWORD_TRUE);
			finish_node(parser, result, first);
			return result;

		// Null pointer literal `null`.
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

		// Current context value `context`.
		case .KEYWORD_CONTEXT;
			parser_eat(parser);

			result := new_parser_node(parser, Parser_Context);
			result.kind = .CONTEXT;
			finish_node(parser, result, first);
			return result;

		// Not a primary; let the caller diagnose or recover at this token.
		case;
			return null;
	}
}

parse_expression_directive :: (parser: *Parser, first: s64, name: string) -> *Parser_Node {
	if name == {
		case "assert";
			parser_eat(parser, 2);

			result := new_parser_node(parser, Parser_Directive_Run);
			result.kind = .DIRECTIVE_RUN;
			result.flags |= .ASSERTION;
			result.flags |= .HAS_IMPLICIT_RETURN_TYPES;
			result.expression = parse_binary(parser);
			if !result.expression {
				add_expected_expression(parser);
			}

			if parser_peek(parser).type == .STRING {
				result.assertion_string = parser_eat(parser).string_value;
			}

			finish_node(parser, result, first);
			return result;

		case "procedure_of_call";
			parser_eat(parser, 2);
			call := parse_postfix(parser);
			if !call || call.kind != .PROCEDURE_CALL {
				add_expected_expression(parser);
				return null;
			}


			call.(*Parser_Procedure_Call).flags |= .RETURNS_PROCEDURE_POINTER_ONLY;
			finish_node(parser, call, first);
			return call;

		case "Context";
			parser_eat(parser, 2);

			result := new_parser_node(parser, Parser_Directive_Context_Type);
			result.kind = .DIRECTIVE_CONTEXT_TYPE;
			finish_node(parser, result, first);
			return result;

		case "char";
			parser_eat(parser, 2);

			character := parser_peek(parser);
			if !parser_eat_if(parser, .STRING) {
				parser_expect(parser, .STRING);
			}

			result := new_parser_node(parser, Parser_Literal);
			result.kind = .LITERAL;
			result.value_type = .NUMBER;
			result.value_flags |= .IS_A_NUMBER;
			if character.type == .STRING && character.string_value.count {
				result._u64 = character.string_value[0];
			}

			finish_node(parser, result, first);
			return result;

		case "this";
			parser_eat(parser, 2);

			result := new_parser_node(parser, Parser_Node);
			result.kind = .DIRECTIVE_THIS;
			finish_node(parser, result, first);
			return result;

		case "filepath";
			parser_eat(parser, 2);

			directory_end: s64;
			for parser.parsed.fully_pathed_filename {
				if it == #char "/" || it == #char "\\" {
					directory_end = it_index + 1;
				}
			}

			result := new_parser_node(parser, Parser_Literal);
			result.kind = .LITERAL;
			result.value_type = .STRING;
			result._string = slice(parser.parsed.fully_pathed_filename, 0, directory_end);
			finish_node(parser, result, first);
			return result;

		case "caller_code";
			parser_eat(parser, 2);

			result := new_parser_node(parser, Parser_Directive_Code);
			result.kind = .DIRECTIVE_CODE;
			result.code_flags |= xx Code_Directive_Code_Flags_CALLER_CODE;
			finish_node(parser, result, first);
			return result;

		case "load";
			parser_eat(parser, 2);

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
			parser_eat(parser, 2);

			result := new_parser_node(parser, Parser_Directive_Bytes);
			result.kind = .DIRECTIVE_BYTES;
			result.expression = parse_binary(parser);
			if !result.expression{
				add_expected_expression(parser);
			}

			finish_node(parser, result, first);
			return result;

		case "procedure_name";
			parser_eat(parser, 2);

			result := new_parser_node(parser, Parser_Directive_Procedure_Name);
			result.kind = .DIRECTIVE_PROCEDURE_NAME;

			parser_expect(parser, #char "(");

			if parser_peek(parser).type != #char ")" {
				result.argument = parse_binary(parser);
				if !result.argument{
					add_expected_expression(parser);
				}
			}

			parser_expect(parser, #char ")");

			finish_node(parser, result, first);
			return result;

		case "wildcard";
			parser_eat(parser, 2);

			result := new_parser_node(parser, Parser_Directive_Wildcard);
			result.kind = .DIRECTIVE_WILDCARD;
			finish_node(parser, result, first);
			return result;

		case "exists";
			parser_eat(parser, 2);

			result := new_parser_node(parser, Parser_Directive_Exists);
			result.kind = .DIRECTIVE_EXISTS;
			parser_expect(parser, #char "(");
			result.query_expression = parse_binary(parser);
			if !result.query_expression{
				add_expected_expression(parser);
			}

			if parser_eat_if(parser, #char ",") {
				result.sync_expression = parse_binary(parser);
				if !result.sync_expression{
					add_expected_expression(parser);
				}
			}

			parser_expect(parser, #char ")");

			finish_node(parser, result, first);
			return result;

		case "import";
			parser_eat(parser, 2);

			result := new_parser_node(parser, Parser_Directive_Import);
			result.kind = .DIRECTIVE_IMPORT;

			while parser_eat_if(parser, #char ",") {
				modifier := parser_peek(parser);
				if !parser_eat_if(parser, .IDENT) {
					parser_expect(parser, .IDENT);
					break;
				}


				modifier_name: string = modifier.ident_value.name;
				if modifier_name == {
					case "file";
						result.import_type = .PATH_TO_FILE;
						result.flags |= xx Code_Directive_Import_Flags_SOURCE_PATH;
					case "dir";
						result.import_type = .PATH_TO_DIRECTORY;
						result.flags |= xx Code_Directive_Import_Flags_SOURCE_PATH;
					case "string";
						result.import_type = .FULL_TEXT;
						result.flags |= .UNSHARED;
					case;
						add_unexpected_token(parser);
				}
			}

			token := parser_peek(parser);
			if (token.type == #char "#" && parser_peek(parser, 1).type == .IDENT
				&& parser_peek(parser, 1).ident_value.name == "string"
			) {
				literal := parse_primary(parser);
				if literal {
					result.name = literal.(*Parser_Literal)._string;
				}
			} else if parser_eat_if(parser, .STRING) {
				result.name = token.string_value;
			} else {
				parser_expect(parser, .STRING);
			}

			token = parser_peek(parser);
			if token.type == #char "(" {
				result.module_parameters_call = parse_procedure_call(parser, result, first)
					.(*Parser_Procedure_Call);
			}

			token = parser_peek(parser);
			if token.type == #char "(" {
				result.program_parameters_call = parse_procedure_call(parser, result, first)
					.(*Parser_Procedure_Call);
			}

			finish_node(parser, result, first);
			return result;

		case "poke_name";
			parser_eat(parser, 2);

			result := new_parser_node(parser, Parser_Directive_Poke_Name);
			result.kind = .DIRECTIVE_POKE_NAME;
			result.module_expression = parse_postfix(parser);
			if !result.module_expression{
				add_expected_expression(parser);
			}

			if parser_peek(parser).type == .IDENT {
				result.name = parser_eat(parser).ident_value.name;
			} else {
				parser_expect(parser, .IDENT);
			}

			finish_node(parser, result, first);
			return result;

		case "library";
			parser_eat(parser, 2);

			result := new_parser_node(parser, Parser_Directive_Library);
			result.kind = .DIRECTIVE_LIBRARY;

			while parser_eat_if(parser, #char ",") {
				modifier := parser_peek(parser);
				if !parser_eat_if(parser, .IDENT) {
					parser_expect(parser, .IDENT);
					break;
				}


				modifier_name: string = modifier.ident_value.name;
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
			}


			library_name := parser_peek(parser);
			if parser_eat_if(parser, .STRING) {
				result.name = library_name.string_value;
			} else {
				parser_expect(parser, .STRING);
			}

			finish_node(parser, result, first);
			return result;

		case "location";		#through;
		case "caller_location";
			parser_eat(parser, 2);

			result := new_parser_node(parser, Parser_Directive_Location);
			result.kind = .DIRECTIVE_LOCATION;
			result.is_caller_location = name == "caller_location";
			if !result.is_caller_location {
				parser_expect(parser, #char "(");
				if parser_peek(parser).type != #char ")" {
					result.expression = parse_binary(parser);
					if !result.expression{
						add_expected_expression(parser);
					}
				}

				parser_expect(parser, #char ")");
			}

			finish_node(parser, result, first);
			return result;

		case "code";			#through;
		case "run";				#through;
		case "insert";			#through;
		case "bake";			#through;
		case "bake_constants";	#through;
		case "bake_arguments";
			parser_eat(parser, 2);

			if name == {
				case "code";
					result := new_parser_node(parser, Parser_Directive_Code);
					result.kind = .DIRECTIVE_CODE;

					parse_payload := true;
					if parser_peek(parser).type == #char "," {
						modifier := parser_peek(parser, 1);
						if modifier.type == {
							case .KEYWORD_NULL;
								parser_eat(parser, 2);

								result.code_flags |= .NULL;
								parse_payload = false;

							case .IDENT;
								if modifier.ident_value.name == "typed" {
									parser_eat(parser, 2);

									result.code_flags |= .TYPED;
								}
						}
					}

					if parse_payload {
						result.expression = ifx parser_peek(parser).type == #char "{"
							then parse_block_node(parser).(*Parser_Node)
							else ifx looks_like_declaration(parser)
								then parse_declaration_node(parser)
								else parse_binary(parser);

						if !result.expression {
							add_expected_expression(parser);
						}
					}

					finish_node(parser, result, first);
					return result;

				case "run";
					result := new_parser_node(parser, Parser_Directive_Run);
					result.kind = .DIRECTIVE_RUN;

					if parser_eat_if(parser, #char ",") {
						modifier := parser_peek(parser);
						if modifier.type == .IDENT && modifier.ident_value.name == "stallable" {
							parser_eat(parser);
							result.flags |= .STALLABLE;
						} else if modifier.type == .IDENT && modifier.ident_value.name == "host" {
							parser_eat(parser);
							result.flags |= xx Code_Directive_Run_Flags_HOST;
						} else {
							add_unexpected_token(parser);
						}
					}

					token := parser_peek(parser);
					if token.type == .RIGHT_ARROW {
						result.procedure = parse_arrow_procedure_header(parser, first);
						if result.procedure.body_or_null {
							result.expression = result.procedure.body_or_null.block;
						}
					} else if token.type == #char "{" {
						result.expression = parse_block_node(parser);
					} else {
						result.flags |= .HAS_IMPLICIT_RETURN_TYPES;
						result.expression = parse_binary(parser);
					}

					if !result.expression {
						add_expected_expression(parser);
					}

					finish_node(parser, result, first);
					return result;


				case "insert";
					result := new_parser_node(parser, Parser_Directive_Insert);
					result.kind = .DIRECTIVE_INSERT;

					if parser_eat_if(parser, #char ",") {
						modifier := parser_peek(parser);
						if modifier.type == .IDENT && modifier.ident_value.name == "scope" {
							parser_eat(parser);
							parser_expect(parser, #char "(");

							if parser_peek(parser).type != #char ")" {
								result.scope_redirection = parse_binary(parser);
								if !result.scope_redirection {
									add_expected_expression(parser);
								}
							}

							parser_expect(parser, #char ")");
						} else {
							parser_expect(parser, .IDENT);
						}

					}

					if parser_eat_if(parser, #char "(") {
						while true {
							modifier := parser_peek(parser);
							if modifier.type == #char ")" || modifier.type == .END_OF_INPUT {
								break;
							}


							if modifier.type == .IDENT || modifier.type == .KEYWORD_BREAK || modifier.type == .KEYWORD_CONTINUE || modifier.type == .KEYWORD_REMOVE {
								parser_eat(parser);
							} else {
								parser_expect(parser, .IDENT);
							}

							parser_expect(parser, #char "=");

							replacement := parse_statement(parser);
							if !replacement {
								add_expected_expression(parser);
							}

							if modifier.type == {
								case .KEYWORD_BREAK;		result.break_replacement = replacement;
								case .KEYWORD_CONTINUE;		result.continue_replacement = replacement;
								case .KEYWORD_REMOVE;		result.remove_replacement = replacement;
							}

							if !parser_eat_if(parser, #char ",") {
								break;
							}
						}

						parser_expect(parser, #char ")");
					}

					token := parser_peek(parser);
					if token.type == .RIGHT_ARROW {
						header := parse_arrow_procedure_header(parser, first);

						run := new_parser_node(parser, Parser_Directive_Run);
						run.kind = .DIRECTIVE_RUN;
						run.flags |= .SYNTACTICALLY_IMPLICIT;
						run.procedure = header;
						if header.body_or_null {
							run.expression = header.body_or_null.block;
						}

						finish_node(parser, run, first);
						result.expression = run;
					} else {
						result.expression = parse_binary(parser);
					}

					if !result.expression {
						add_expected_expression(parser);
					}

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

add_missing_token :: (parser: *Parser, expectedType: Token_Type) {
	actual := parser_peek(parser);

	synthetic := Synthetic_Token.{
		.{
			type = expectedType,
			l0 = actual.l0,
			c0 = actual.c0,
			l1 = actual.l0,
			c1 = actual.c0
		},
		xx parser.cursor
	};
	array_add(*parser.parsed.synthetic_tokens, synthetic);

	diagnostic := Parse_Diagnostic.{
		kind = .EXPECTED_TOKEN,
		span = make_token_span(parser.cursor, parser.cursor),
		expected_token = expectedType,
		actual_token = actual.type,
		recovery_action = .INSERT_MISSING_TOKEN
	};
	array_add(*parser.parsed.diagnostics, diagnostic);
	array_add(
		*parser.parsed.recovery_records,
		.{
			kind = .MISSING_TOKEN,
			span = diagnostic.span,
			diagnostic_index = parser.parsed.diagnostics.count - 1,
			synthetic_token_index = parser.parsed.synthetic_tokens.count - 1
		}
	);

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
	actual_token := parser_peek(parser).type;
	diagnostic := Parse_Diagnostic.{
		kind = .EXPECTED_EXPRESSION,
		span = span,
		message = message,
		actual_token = actual_token
	};
	array_add(*parser.parsed.diagnostics, diagnostic);
	array_add(
		*parser.parsed.recovery_records,
		.{
			kind = .EXPECTED_EXPRESSION,
			span = diagnostic.span,
			diagnostic_index = parser.parsed.diagnostics.count - 1
		}
	);

	mark_parse_error(parser, actual_token == .END_OF_INPUT);
}

add_unexpected_token :: (parser: *Parser) {
	actual := parser_peek(parser);
	first := parser.cursor;

	parser_eat(parser);
	parser_synchronise(parser, .EXPRESSION, false);

	diagnostic := Parse_Diagnostic.{
		kind = .UNEXPECTED_TOKEN,
		span = make_token_span(first, parser.cursor),
		actual_token = actual.type,
		recovery_action = .SKIP_TOKENS
	};
	array_add(*parser.parsed.diagnostics, diagnostic);
	array_add(
		*parser.parsed.recovery_records,
		.{
			kind = .SKIPPED_TOKENS,
			span = diagnostic.span,
			diagnostic_index = parser.parsed.diagnostics.count - 1
		}
	);

	mark_parse_error(parser, false);
}

mark_parse_error :: (parser: *Parser, incomplete: bool) {
	if parser.parsed.status == .FATAL {
		return;
	}


	if incomplete {
		if parser.parsed.status == .COMPLETE {
			parser.parsed.status = .INCOMPLETE;
		}
	} else {
		parser.parsed.status = .RECOVERED;
	}
}

finish_node :: (parser: *Parser, node: *$T/Parser_Node, first: s64) -> *T {
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

	if node.kind == .DECLARATION {
		declaration := node.(*Parser_Declaration);
		if declaration.name {
			array_add(*parser.current_scope.bindings, .{name = declaration.name, declaration = declaration});
		}
	}

	if node.kind == .BLOCK || node.kind == .DECLARATION || node.kind == .COMPOUND_DECLARATION {
		kind := ifx node.kind == .BLOCK
			then Restart_Point.kind.BLOCK
			else .DECLARATION;

		array_add(*parser.parsed.restart_points, .{kind = kind, span = make_token_span(first, parser.cursor)});
	}

	return node;
}

// Relex around an edit until a stable token boundary is found, then reuse the unchanged suffix with adjusted positions.
// A clean, trivia-enabled old snapshot permits copying prefix tokens before the edited region; lex from one token earlier to account for token/trivia merging.
// Only an identical token and trivia boundary after the edit permits suffix reuse.
// Here strings and lexer errors force full lexing because their tokenisation depends on wider context.
// Every copied token gets new-source views and adjusted locations.
materialise_tokens :: (source: string, old: *Parsed_Source = null, edit_start: s64 = 0, edit_end: s64 = 0) -> Parsed_Source {
	result: Parsed_Source;
	result.source = source;

	errors: [..]Lexer_Error;
	lexer: Lexer;
	lexer.user_data = *errors;
	lexer.error_callback = collect_lexer_error;
	lexer.detail_callback = collect_lexer_detail;

	#if INTERN_IDENTIFIERS {
		set_identifier_storage(*lexer, *result.identifier_storage);
	}

	set_input_from_string(*lexer, source);

	source_cursor: s64;
	restart: s64;
	can_reuse := false;
	byte_delta: s64;

	#if ENABLE_TRIVIA {
		if old && old.status == .COMPLETE && old.diagnostics.count == 0 && old.tokens.count > 1 {
			can_reuse = true;
			for old.tokens {
				if it.type == .STRING && it.value_flags & .HERE_STRING != 0 {
					can_reuse = false;
					break;
				}
			}
		}

		if can_reuse {
			byte_delta = source.count - old.source.count;
			first := 0;
			last := old.tokens.count;
			while first < last {
				middle := first + (last - first) / 2;
				if old.tokens[middle].byte_end < edit_start {
					first = middle + 1;
				} else {
					last = middle;
				}
			}

			restart = Max(0, first - 1);
			for index: 0..restart-1 {
				copy_materialised_token(*result, *lexer, old.tokens[index], 0, 0, 0, 0);
			}

			if restart > 0 {
				previous := old.tokens[restart - 1];
				source_cursor = previous.byte_end;
				lexer.input_cursor = source_cursor;
				lexer.current_line_number = previous.l1;
				lexer.current_character_index = previous.c1;
				lexer.previous_token_line_number = previous.l1;
			}
		}
	}

	// The lexer reuses ring slots; retained spans and arbitrary lookahead need stable copies.
	while true {
		token := peek_next_token(*lexer);

		#if ENABLE_TRIVIA {
			if can_reuse && !lexer.reported_error && source_cursor >= edit_end + byte_delta {
				old_cursor := source_cursor - byte_delta;
				first := restart;
				last := old.tokens.count;
				while first < last {
					middle := first + (last - first) / 2;
					if old.tokens[middle].preceding_trivia_byte_start < old_cursor {
						first = middle + 1;
					} else {
						last = middle;
					}
				}

				if first < old.tokens.count {
					match := old.tokens[first];
					if (match.preceding_trivia_byte_start == old_cursor
						&& match.type == token.type
						&& match.preceding_trivia == token.preceding_trivia
						&& match.original_text == token.original_text
						&& (match.type != .END_OF_INPUT || match.trailing_trivia == token.trailing_trivia)
					) {
						line_delta := token.l0 - match.l0;
						column_delta := token.c0 - match.c0;
						for index: first..old.tokens.count-1 {
							copy_materialised_token(*result, *lexer, old.tokens[index], byte_delta, line_delta, column_delta, match.l0);
						}

						break;
					}
				}
			}
		}

		if token.type == {
			case .END_OF_INPUT;
				append_materialised_token(*result, token, *source_cursor);
				break;

			case #char "#";
				next := peek_token(*lexer, 1);
				if next.type == .IDENT && next.ident_value.name == "string" {
					materialise_here_string(*result, *lexer, *source_cursor);
					continue;
				}
		}


		consume_materialised_token(*result, *lexer, *source_cursor);
	}

	for errors {
		index: s64;
		while index + 1 < result.tokens.count {
			token := result.tokens[index];
			if token.l1 > it.line || token.l1 == it.line && token.c1 >= it.column {
				break;
			}


			index += 1;
		}

		related := NewArray(it.details.count, Parse_Diagnostic_Info);
		for it.details {
			related[it_index] = .{span = make_token_span(index, index + 1), message = it};
		}

		array_free(it.details);

		array_add(
			*result.diagnostics,
			.{
				kind = .LEXER_ERROR,
				span = make_token_span(index, index + 1),
				message = it.message,
				related_information = related,
				lexer_line = it.line,
				lexer_column = it.column,
				actual_token = result.tokens[index].type
			}
		);
	}

	array_free(errors);

	result.status = ifx lexer.reported_error
		then .RECOVERED
		else .COMPLETE;

	return result;
}

// Rebase source slices and owned values when reusing tokens; the old snapshot may be released independently.
copy_materialised_token :: (parsed: *Parsed_Source, lexer: *Lexer, old: Parser_Token, byte_delta: s64, line_delta: s32, column_delta: s32, anchor_line: s32) {
	#if ENABLE_TRIVIA {
		copy := old;
		copy.index = xx parsed.tokens.count;
		copy.preceding_trivia_byte_start += byte_delta;
		copy.byte_start += byte_delta;
		copy.byte_end += byte_delta;
		copy.original_text = slice(parsed.source, copy.byte_start, old.original_text.count);
		copy.preceding_trivia = slice(parsed.source, copy.preceding_trivia_byte_start, old.preceding_trivia.count);
		if copy.type == .END_OF_INPUT {
			copy.trailing_trivia = slice(parsed.source, copy.preceding_trivia_byte_start, old.trailing_trivia.count);
		}

		copy.l0 += line_delta;
		copy.l1 += line_delta;
		if old.l0 == anchor_line {
			copy.c0 += column_delta;
		}
		if old.l1 == anchor_line {
			copy.c1 += column_delta;
		}

		if old.type == .IDENT {
			copy.ident_value.name = lexer.identifier_handler(lexer, old.ident_value.name, "");
		} else if old.type == .NOTE || (old.type >= .__FIRST_KEYWORD && old.type <= .__LAST_KEYWORD) {
			copy.ident_value.name = copy_string(old.ident_value.name).(Table_String);
		} else if old.type == .STRING && old.string_value.count {
			copy.string_value = copy_string(old.string_value);
		}

		array_add(*parsed.tokens, copy);
	}
}

consume_materialised_token :: (
	parsed: *Parsed_Source,
	lexer: *Lexer,
	source_cursor: *s64
) -> Token {
	token := peek_next_token(lexer);
	append_materialised_token(parsed, token, source_cursor);
	eat_token(lexer);
	return token.*;
}

append_materialised_token :: (
	parsed: *Parsed_Source,
	token: *Token,
	source_cursor: *s64
) {
	#if ENABLE_TRIVIA {
		materialised: Parser_Token;
		materialised.lexer_token = token.*;
		materialised.index = xx parsed.tokens.count;
		materialised.preceding_trivia_byte_start = source_cursor.*;

		if token.type == .END_OF_INPUT {
			source_cursor.* += token.trailing_trivia.count;
			materialised.byte_start = source_cursor.*;
			materialised.byte_end = source_cursor.*;
		} else {
			materialised.byte_start = source_cursor.* + token.preceding_trivia.count;
			materialised.byte_end = materialised.byte_start + token.original_text.count;
			source_cursor.* = materialised.byte_end;
		}

		array_add(*parsed.tokens, materialised);
	} else {
		array_add(*parsed.tokens, token.*);
	}
}

// Retain the directive tokens before the lexer takes over the body, so token spans and source reconstruction include both parts.
materialise_here_string :: (
	parsed: *Parsed_Source,
	lexer: *Lexer,
	source_cursor: *s64
) {
	consume_materialised_token(parsed, lexer, source_cursor);
	name := consume_materialised_token(parsed, lexer, source_cursor);
	assert(name.type == .IDENT && name.ident_value.name == "string");

	want_cr := false;
	want_percent := false;
	while peek_next_token(lexer).type == #char "," {
		consume_materialised_token(parsed, lexer, source_cursor);

		modifier := consume_materialised_token(parsed, lexer, source_cursor);
		if modifier.type != .IDENT {
			report_parse_error(lexer, *modifier, "Expected a #string modifier.");
			return;
		}


		modifier_name: string = modifier.ident_value.name;
		if modifier_name == {
			case "cr";		want_cr = true;
			case "\\%";		want_percent = true;
		}
	}

	delimiter := consume_materialised_token(parsed, lexer, source_cursor);
	if delimiter.type != .IDENT {
		report_parse_error(lexer, *delimiter, "Expected a #string delimiter.");
		return;
	}


	body := parse_here_string_body(lexer, delimiter.ident_value.name, want_cr, want_percent);
	if !body {
		return;
	}


	append_materialised_token(parsed, body, source_cursor);
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
