#import "Basic";
#import "Compiler";
#import "File";
#import "Process";
#import "String";

Parser :: #import "Jai_Parser"(ENABLE_TRIVIA=true);

Comparison_Layer :: enum u8 {
	SYNTAX;
	SEMANTIC;
}

Normalized_Field :: struct {
	path: string;
	value: string;
}

Normalized_Tree :: struct {
	fields: [..] Normalized_Field;
}

procedure_syntax_flags :: (flags: type_of(Code_Procedure_Header.procedure_flags)) -> type_of(Code_Procedure_Header.procedure_flags) {
	return flags & (
		.ELSEWHERE | .DEBUG_DUMP | .C_CALL | .TYPE_ONLY | .INTRINSIC | .DEPRECATED
		| .SYNTACTICALLY_MARKED_AS_NO_CONTEXT | .QUICK | .QUICK_IN_BLOCK_FORM
		| .CPP_METHOD | .NO_CALL | .MACRO | .NO_DEBUG | .ENTRY_POINT | .SYMMETRIC
		| .ENTRY_POINT_HOOK | .SYNTACTICALLY_MARKED_AS_COMPILE_TIME
		| .SYNTACTICALLY_MARKED_AS_COMPILER | .SYNTACTICALLY_MARKED_AS_INLINE_YES
		| .SYNTACTICALLY_MARKED_AS_INLINE_NO | .INITIALIZER
	);
}

Structural_Difference :: struct {
	path: string;
	expected: string;
	actual: string;
}

Differential_Result :: struct {
	differences: [..] Structural_Difference;
}

Workspace_Fixture_Result :: struct {
	completed: bool;
	compilation_succeeded: bool;
	typechecked_message_count: s64;
	declaration_count: s64;
	found_expected_declaration: bool;
}

Compiler_Source_Location :: struct {
	file_path: string;
	l0: s64;
	c0: s64;
	l1: s64;
	c1: s64;
}

Compiler_Related_Info :: struct {
	location: Compiler_Source_Location;
	message: string;
}

Compiler_Diagnostic :: struct {
	location: Compiler_Source_Location;
	message: string;
	related_information: [..] Compiler_Related_Info;
}

Compiler_Diagnostic_Result :: struct {
	process_result: Process_Result;
	standard_output: string;
	standard_error: string;
	diagnostics: [..] Compiler_Diagnostic;
}

main :: () {
	test_structural_difference_reporting();
	test_comparison_layers();
	assert_invalid_expression_compiler_message(
		"1 +",
		"Unable to parse an expression to the right of this binary operator."
	);
	test_compiler_related_diagnostics();
	assert_trivia_round_trip("value /* comment */ + 42;\n");
	assert_trivia_round_trip("text :: #string END\nbody\nEND; // tail");
}

capture_compiler_error :: (code: string, log_output := false) -> Compiler_Diagnostic_Result {
	fixture_path :: "jai_parser_compiler_diagnostic_fixture.jai";
	assert(find_index_from_left(code, #char "\t") < 0, "Compiler diagnostic fixtures must use spaces instead of tabs.");
	written := write_entire_file(fixture_path, code);
	assert(written, "Unable to write compiler diagnostic fixture '%'.", fixture_path);
	defer file_delete(fixture_path);

	result: Compiler_Diagnostic_Result;
	result.process_result, result.standard_output, result.standard_error = run_command(
		"jai", "-x64", fixture_path,
		capture_and_return_output=true,
		print_captured_output=log_output
	);
	assert(result.process_result.type == .EXITED, "Compiler diagnostic fixture failed to run.");
	assert(result.process_result.exit_code != 0, "Compiler accepted invalid fixture:\n%", code);

	append_compiler_diagnostics(result.standard_error, *result.diagnostics);
	append_compiler_diagnostics(result.standard_output, *result.diagnostics);
	assert(result.diagnostics.count > 0, "Compiler failed without an Error diagnostic.\nstdout:\n%\nstderr:\n%", result.standard_output, result.standard_error);
	return result;
}

append_compiler_diagnostics :: (output: string, diagnostics: *[..] Compiler_Diagnostic) {
	current: *Compiler_Diagnostic;
	pending_location: *Compiler_Source_Location;
	for line: split(output, "\n") {
		found_error, location, message := parse_compiler_message_line(line, ": Error: ");
		if found_error {
			array_add(diagnostics, .{location=location, message=message});
			current = *diagnostics.*[diagnostics.count - 1];
			pending_location = *current.location;
			continue;
		}


		found_info, info_location, info_message := parse_compiler_message_line(line, ": Info: ");
		if found_info && current {
			array_add(*current.related_information, .{location=info_location, message=info_message});
			pending_location = *current.related_information[current.related_information.count - 1].location;
			continue;
		}


		caret_start := find_index_from_left(line, #char "^");
		if caret_start >= 0 && pending_location {
			caret_count: s64;
			while caret_start + caret_count < line.count && line[caret_start + caret_count] == #char "^" {
				caret_count += 1;
			}
			pending_location.l1 = pending_location.l0;
			pending_location.c1 = pending_location.c0 + caret_count;
			pending_location = null;
		}
	}
}

parse_compiler_message_line :: (line: string, marker: string) -> bool, Compiler_Source_Location, string {
	marker_index := find_index_from_left(line, marker);
	if marker_index < 0		return false, .{}, "";


	location_text := slice(line, 0, marker_index);
	comma_index := find_index_from_right(location_text, #char ",");
	if comma_index < 0		return false, .{}, "";


	line_prefix := slice(location_text, 0, comma_index);
	line_separator := find_index_from_right(line_prefix, #char ":");
	if line_separator < 0	return false, .{}, "";


	line_number, valid_line, line_remainder := string_to_int(advance(line_prefix, line_separator + 1), T=s64);
	column_number, valid_column, column_remainder := string_to_int(advance(location_text, comma_index + 1), T=s64);
	if !valid_line || line_remainder || !valid_column || column_remainder	return false, .{}, "";


	location := Compiler_Source_Location.{
		file_path=slice(location_text, 0, line_separator),
		l0=line_number,
		c0=column_number,
		l1=line_number,
		c1=column_number
	};
	message := trim(advance(line, marker_index + marker.count));
	return true, location, message;
}

assert_compiler_error_message :: (code: string, expected_message: string) {
	result := capture_compiler_error(code);
	actual := result.diagnostics[0].message;
	assert(
		actual == expected_message,
		"Compiler diagnostic differed.\nExpected: %\nActual:   %\n",
		expected_message,
		actual
	);
}

assert_invalid_expression_compiler_message :: (source: string, expected_message: string) {
	parsed := Parser.parse_expression(source);
	defer Parser.release_parser_tree(*parsed);
	assert(parsed.status != .COMPLETE, "Parser accepted invalid expression '%'.", source);
	assert(parsed.diagnostics.count > 0, "Parser rejected '%' without a diagnostic.", source);
	assert(parsed.diagnostics[0].message == expected_message, "Parser diagnostic differed.\nExpected: %\nActual:   %\n", expected_message, parsed.diagnostics[0].message);

	code := tprint("main :: () {\n    value := %;\n}\n", source);
	assert_compiler_error_message(code, expected_message);
}

test_compiler_related_diagnostics :: () {
	result := capture_compiler_error(
		"takes_integer :: (value: s64) {}\nmain :: () { takes_integer(\"text\"); }\n",
		log_output=true
	);
	assert(result.diagnostics.count == 1);

	diagnostic := result.diagnostics[0];
	assert(diagnostic.location.l0 == 2 && diagnostic.location.c0 == 28);
	assert(diagnostic.location.l1 == 2 && diagnostic.location.c1 == 34);
	assert(diagnostic.message == "Type mismatch. Type wanted: s64; type given: string.");
	assert(diagnostic.related_information.count == 1);
	assert(diagnostic.related_information[0].location.l0 == 1);
	assert(diagnostic.related_information[0].location.c0 == 18);
	assert(diagnostic.related_information[0].location.l1 == 1);
	assert(diagnostic.related_information[0].location.c1 == 30);
	assert(diagnostic.related_information[0].message == "... in checking argument 1 of call to takes_integer.");
}

test_structural_difference_reporting :: () {
	actual_source := Parser.parse_expression("left + right");
	expected_source := Parser.parse_expression("left - right");
	defer Parser.release_parser_tree(*actual_source);
	defer Parser.release_parser_tree(*expected_source);

	actual := normalize_parser_tree(actual_source.root);
	expected := normalize_parser_tree(expected_source.root);
	result := compare_normalized_trees(actual, expected);
	assert(result.differences.count == 1);
	assert(result.differences[0].path == "root.operator");
}

test_comparison_layers :: () {
	parsed := Parser.parse_expression("value");
	defer Parser.release_parser_tree(*parsed);

	syntax := normalize_parser_tree(parsed.root, .SYNTAX);
	semantic := normalize_parser_tree(parsed.root, .SEMANTIC);
	assert(find_normalized_field(syntax.fields, "root.has_type") == null);
	assert(find_normalized_field(semantic.fields, "root.has_type") != null);
}

normalize_tree :: (node: *Code_Node, layer := Comparison_Layer.SYNTAX) -> Normalized_Tree {
	result: Normalized_Tree;
	normalize_node(node, "root", layer, *result);
	return result;
}

normalize_parser_tree :: (node: *Parser.Parser_Node, layer := Comparison_Layer.SYNTAX) -> Normalized_Tree {
	result: Normalized_Tree;
	normalize_parser_node(node, "root", layer, *result);
	return result;
}

normalize_parser_node :: (node: *Parser.Parser_Node, path: string, layer: Comparison_Layer, result: *Normalized_Tree) {
	if !node {
		add_normalized_field(result, path, "kind", "<null>");
		return;
	}


	add_normalized_field(result, path, "kind", tprint("%", node.kind));
	add_normalized_field(result, path, "parenthesized", tprint("%", (node.node_flags & .IS_PARENTHESIZED) != 0));

	if layer == .SEMANTIC {
		add_normalized_field(result, path, "has_type", tprint("%", node.type != null));
	}

	if node.kind == {
		case .IDENT;
			ident := node.(*Parser.Parser_Ident);
			add_normalized_field(result, path, "name", ident.name);
			add_normalized_field(result, path, "has_scope_modifier", tprint("%", (ident.flags & .HAS_SCOPE_MODIFIER) != 0));
			add_normalized_field(result, path, "do_not_resolve", tprint("%", (ident.flags & .DO_NOT_RESOLVE_DUE_TO_PARSER) != 0));

		case .LITERAL;
			literal := node.(*Parser.Parser_Literal);
			add_normalized_field(result, path, "value_type", tprint("%", literal.value_type));
			add_normalized_field(result, path, "value_flags", tprint("%", literal.value_flags));

			if literal.value_type == {
				case .NUMBER;
					if literal.value_flags & .FLOAT {
						add_normalized_field(result, path, "float64", tprint("%", literal._float64));
					} else {
						add_normalized_field(result, path, "u64", tprint("%", literal._u64));
					}

				case .STRING;
					add_normalized_field(result, path, "string", literal._string);

				case .BOOLEAN;
					add_normalized_field(result, path, "boolean", tprint("%", literal._u64));

				case .POINTER;
					if literal.pointer_literal_info {
						add_normalized_field(result, path, "pointer_type", tprint("%", literal.pointer_literal_info.pointer_literal_type));
						add_normalized_field(result, path, "pointer_offset", tprint("%", literal.pointer_literal_info.offset_from_symbol));
					} else {
						add_normalized_field(result, path, "pointer_type", "<missing>");
					}

				case .ARRAY;
					info := literal.array_literal_info;
					add_normalized_field(result, path, "untyped", tprint("%", (info.array_literal_flags & .WAS_UNTYPED) != 0));
					add_normalized_field(result, path, "member_count", tprint("%", info.array_members.count));
					if info.element_type {
						normalize_parser_node(info.element_type.type_valued_expression, tprint("%.element_type", path), layer, result);
					}
					for info.array_members {
						normalize_parser_node(it, tprint("%.member[%]", path, it_index), layer, result);
					}

				case .STRUCT;
					info := literal.struct_literal_info;
					add_normalized_field(result, path, "argument_count", tprint("%", info.arguments.count));
					if info.type_expression {
						normalize_parser_node(info.type_expression.type_valued_expression, tprint("%.type_expression", path), layer, result);
					}
					for info.arguments {
						normalize_parser_node(it, tprint("%.argument[%]", path, it_index), layer, result);
					}
			}

		case .UNARY_OPERATOR;
			unary := node.(*Parser.Parser_Unary_Operator);
			add_normalized_field(result, path, "operator", tprint("%", unary.operator_type));
			normalize_parser_node(unary.subexpression, tprint("%.operand", path), layer, result);

		case .BINARY_OPERATOR;
			binary := node.(*Parser.Parser_Binary_Operator);
			add_normalized_field(result, path, "operator", tprint("%", binary.operator_type));
			add_normalized_field(result, path, "operator_flags", tprint("%", binary.flags));
			normalize_parser_node(binary.left, tprint("%.left", path), layer, result);
			normalize_parser_node(binary.right, tprint("%.right", path), layer, result);

		case .PROCEDURE_CALL;
			call := node.(*Parser.Parser_Procedure_Call);
			add_normalized_field(result, path, "argument_count", tprint("%", call.arguments_unsorted.count));
			normalize_parser_node(call.procedure_expression, tprint("%.procedure", path), layer, result);
			for call.arguments_unsorted {
				argument_path := tprint("%.argument[%]", path, it_index);
				add_normalized_field(result, argument_path, "name", ifx it.name then it.name.name else "<positional>");
				normalize_parser_node(it.expression, tprint("%.expression", argument_path), layer, result);
			}

		case .CAST;
			cast_node := node.(*Parser.Parser_Cast);
			add_normalized_field(result, path, "cast_flags", tprint("%", cast_node.cast_flags));
			if cast_node.target_type {
				normalize_parser_node(cast_node.target_type.type_valued_expression, tprint("%.target_type", path), layer, result);
			}
			normalize_parser_node(cast_node.expression, tprint("%.expression", path), layer, result);

		case .EXPRESSION_QUERY;
			query := node.(*Parser.Parser_Expression_Query);
			add_normalized_field(result, path, "query_kind", tprint("%", query.query_kind));
			normalize_parser_node(query.expression_to_query, tprint("%.expression", path), layer, result);

		case .TYPE_QUERY;
			query := node.(*Parser.Parser_Type_Query);
			add_normalized_field(result, path, "query_kind", tprint("%", query.query_kind));
			normalize_parser_node(query.type_to_query.type_valued_expression, tprint("%.type", path), layer, result);

		case .DIRECTIVE_CODE;
			directive := node.(*Parser.Parser_Directive_Code);
			add_normalized_field(result, path, "code_flags", tprint("%", directive.code_flags));
			normalize_parser_node(directive.expression, tprint("%.expression", path), layer, result);

		case .DIRECTIVE_RUN;
			directive := node.(*Parser.Parser_Directive_Run);
			add_normalized_field(result, path, "flags", tprint("%", directive.flags));
			normalize_parser_node(directive.expression, tprint("%.expression", path), layer, result);

		case .DIRECTIVE_INSERT;
			directive := node.(*Parser.Parser_Directive_Insert);
			normalize_parser_node(directive.expression, tprint("%.expression", path), layer, result);
			normalize_parser_node(directive.scope_redirection, tprint("%.scope", path), layer, result);
			normalize_parser_node(directive.break_replacement, tprint("%.break", path), layer, result);
			normalize_parser_node(directive.continue_replacement, tprint("%.continue", path), layer, result);
			normalize_parser_node(directive.remove_replacement, tprint("%.remove", path), layer, result);

		case .DIRECTIVE_BAKE;
			directive := node.(*Parser.Parser_Directive_Bake);
			add_normalized_field(result, path, "bake_type", tprint("%", directive.bake_type));
			normalize_parser_node(directive.procedure_call, tprint("%.call", path), layer, result);

		case .DIRECTIVE_LOCATION;
			directive := node.(*Parser.Parser_Directive_Location);
			add_normalized_field(result, path, "caller", tprint("%", directive.is_caller_location));
			normalize_parser_node(directive.expression, tprint("%.expression", path), layer, result);

		case .DIRECTIVE_LIBRARY;
			directive := node.(*Parser.Parser_Directive_Library);
			add_normalized_field(result, path, "name", directive.name);
			add_normalized_field(result, path, "flags", tprint("%", directive.library_flags));

		case .DIRECTIVE_LOAD;
			add_normalized_field(result, path, "name", node.(*Parser.Parser_Directive_Load).short_name);

		case .DIRECTIVE_BYTES;
			normalize_parser_node(node.(*Parser.Parser_Directive_Bytes).expression, tprint("%.expression", path), layer, result);

		case .DIRECTIVE_PROCEDURE_NAME;
			normalize_parser_node(node.(*Parser.Parser_Directive_Procedure_Name).argument, tprint("%.argument", path), layer, result);

		case .DIRECTIVE_WILDCARD;

		case .DIRECTIVE_EXISTS;
			directive := node.(*Parser.Parser_Directive_Exists);
			normalize_parser_node(directive.query_expression, tprint("%.query", path), layer, result);
			normalize_parser_node(directive.sync_expression, tprint("%.sync", path), layer, result);

		case .DIRECTIVE_IMPORT;
			directive := node.(*Parser.Parser_Directive_Import);
			add_normalized_field(result, path, "name", directive.name);
			add_normalized_field(result, path, "flags", tprint("%", directive.flags));
			add_normalized_field(result, path, "import_type", tprint("%", directive.import_type));
			add_normalized_field(result, path, "module_argument_count", tprint("%", ifx directive.module_parameters_call then directive.module_parameters_call.arguments_unsorted.count else 0));
			add_normalized_field(result, path, "program_argument_count", tprint("%", ifx directive.program_parameters_call then directive.program_parameters_call.arguments_unsorted.count else 0));

		case .DIRECTIVE_POKE_NAME;
			directive := node.(*Parser.Parser_Directive_Poke_Name);
			add_normalized_field(result, path, "name", directive.name);

		case .DIRECTIVE_THROUGH;

		case .DIRECTIVE_OVERLAY;
			directive := node.(*Parser.Parser_Directive_Overlay);
			normalize_parser_node(directive.target_expression, tprint("%.target", path), layer, result);
			normalize_parser_node(directive.declaration_or_using, tprint("%.declaration", path), layer, result);

		case .DIRECTIVE_ADD_CONTEXT;
			normalize_parser_node(node.(*Parser.Parser_Directive_Add_Context).expression, tprint("%.expression", path), layer, result);

		case .DIRECTIVE_CONTEXT_TYPE;

		case .DIRECTIVE_SCOPE;
			add_normalized_field(result, path, "scope_type", tprint("%", node.(*Parser.Parser_Directive_Scope).scope_type));

		case .DIRECTIVE_MODULE_PARAMETERS;
			directive := node.(*Parser.Parser_Directive_Module_Parameters);
			normalize_parser_node(directive.module_parameters, tprint("%.module", path), layer, result);
			normalize_parser_node(directive.program_parameters, tprint("%.program", path), layer, result);
			normalize_parser_node(directive.common_code, tprint("%.common", path), layer, result);

		case .DIRECTIVE_MODIFY;
			normalize_parser_node(node.(*Parser.Parser_Directive_Modify).block, tprint("%.block", path), layer, result);

		case .TYPE_INSTANTIATION;
			type_inst := node.(*Parser.Parser_Type_Instantiation);
			add_normalized_field(result, path, "inst_flags", tprint("%", type_inst.inst_flags));
			normalize_parser_node(type_inst.type_valued_expression, tprint("%.expression", path), layer, result);
			normalize_parser_node(type_inst.must_implement, tprint("%.restriction", path), layer, result);
			normalize_parser_node(type_inst.pointer_to, tprint("%.pointer_to", path), layer, result);
			normalize_parser_node(type_inst.type_directive_target, tprint("%.directive_target", path), layer, result);
			normalize_parser_node(type_inst.array_element_type, tprint("%.element_type", path), layer, result);
			normalize_parser_node(type_inst.array_dimension, tprint("%.dimension", path), layer, result);

		case .PROCEDURE_HEADER;
			header := node.(*Parser.Parser_Procedure_Header);
			add_normalized_field(result, path, "flags", tprint("%", procedure_syntax_flags(header.procedure_flags)));
			add_normalized_field(result, path, "name", header.name);
			add_normalized_field(result, path, "foreign_name", header.foreign_function_name);
			add_normalized_field(result, path, "library", ifx header.library_identifier then header.library_identifier.name else "");
			add_normalized_field(result, path, "deprecated", header.deprecation_string);
			add_normalized_field(result, path, "using_count", tprint("%", header.parameter_usings.count));
			add_normalized_field(result, path, "modify_count", tprint("%", header.modify_directives.count));
			add_normalized_field(result, path, "argument_count", tprint("%", header.arguments.count));
			add_normalized_field(result, path, "return_count", tprint("%", header.returns.count));
			for header.arguments {
				argument_path := tprint("%.argument[%]", path, it_index);
				if header.procedure_flags & .QUICK {
					add_normalized_field(result, argument_path, "kind", tprint("%", it.kind));
					add_normalized_field(result, argument_path, "name", it.name);
				} else {
					normalize_parser_node(it, argument_path, layer, result);
				}
			}
			for header.returns 		normalize_parser_node(it, tprint("%.return[%]", path, it_index), layer, result);
			for header.modify_directives normalize_parser_node(it, tprint("%.modify[%]", path, it_index), layer, result);

		case .PROCEDURE_BODY;
			body := node.(*Parser.Parser_Procedure_Body);
			normalize_parser_node(body.block, tprint("%.block", path), layer, result);

		case .STRUCT;
			aggregate := node.(*Parser.Parser_Struct);
			add_normalized_field(result, path, "flags", tprint("%", aggregate.textual_flags));
			add_normalized_field(result, path, "note_count", tprint("%", aggregate.notes.count));
			for aggregate.notes add_normalized_field(result, tprint("%.note[%]", path, it_index), "text", it.text);
			add_normalized_field(result, path, "modify_count", tprint("%", aggregate.modify_directives.count));
			for aggregate.modify_directives 	normalize_parser_node(it, tprint("%.modify[%]", path, it_index), layer, result);
			normalize_parser_node(aggregate.block, tprint("%.block", path), layer, result);

		case .ENUM;
			aggregate := node.(*Parser.Parser_Enum);
			add_normalized_field(result, path, "flags", tprint("%", aggregate.is_flags));
			add_normalized_field(result, path, "complete", tprint("%", aggregate.marked_as_complete));
			add_normalized_field(result, path, "specified", tprint("%", aggregate.marked_as_specified));
			add_normalized_field(result, path, "note_count", tprint("%", aggregate.notes.count));
			for aggregate.notes add_normalized_field(result, tprint("%.note[%]", path, it_index), "text", it.text);
			normalize_parser_node(aggregate.internal_type_inst, tprint("%.internal_type", path), layer, result);
			normalize_parser_node(aggregate.block, tprint("%.block", path), layer, result);

		case .DECLARATION;
			declaration := node.(*Parser.Parser_Declaration);
			normalize_parser_declaration(declaration, path, layer, result);

		case .COMPOUND_DECLARATION;
			declaration := node.(*Parser.Parser_Compound_Declaration);
			add_normalized_field(result, path, "argument_count", tprint("%", declaration.comma_separated_assignment.arguments.count));
			for declaration.comma_separated_assignment.arguments {
				normalize_parser_node(it.node, tprint("%.argument[%]", path, it_index), layer, result);
			}
			normalize_parser_declaration(*declaration.declaration_properties, tprint("%.properties", path), layer, result);
			normalize_parser_node(declaration.alignment_expression, tprint("%.alignment", path), layer, result);
			add_normalized_field(result, path, "note_count", tprint("%", declaration.notes.count));
			for declaration.notes {
				add_normalized_field(result, tprint("%.note[%]", path, it_index), "text", it.text);
			}

		case .COMMA_SEPARATED_ARGUMENTS;
			arguments := node.(*Parser.Parser_Comma_Separated_Arguments);
			add_normalized_field(result, path, "argument_count", tprint("%", arguments.arguments.count));
			for arguments.arguments {
				normalize_parser_node(it.node, tprint("%.argument[%]", path, it_index), layer, result);
			}

		case .NOTE;
			add_normalized_field(result, path, "text", node.(*Parser.Parser_Note).text);

		case .BLOCK;
			block := node.(*Parser.Parser_Block);
			add_normalized_field(result, path, "block_type", tprint("%", block.block_type));
			add_normalized_field(result, path, "statement_count", tprint("%", block.statements.count));
			for block.statements	normalize_parser_node(it, tprint("%.statement[%]", path, it_index), layer, result);

		case .RETURN;
			return_node := node.(*Parser.Parser_Return);
			add_normalized_field(result, path, "backticked", tprint("%", (return_node.return_flags & .IS_BACKTICKED) != 0));
			add_normalized_field(result, path, "quick", tprint("%", (return_node.return_flags & .AUTO_INSERTED_FOR_QUICK_LAMBDA) != 0));
			add_normalized_field(result, path, "argument_count", tprint("%", return_node.arguments_unsorted.count));
			for return_node.arguments_unsorted	normalize_parser_node(it.expression, tprint("%.argument[%]", path, it_index), layer, result);

		case .LOOP_CONTROL;
			control := node.(*Parser.Parser_Loop_Control);
			add_normalized_field(result, path, "control_type", tprint("%", control.control_type));
			normalize_parser_node(control.target_ident, tprint("%.target", path), layer, result);

		case .WHILE;
			while_node := node.(*Parser.Parser_While);
			normalize_parser_node(while_node.condition, tprint("%.condition", path), layer, result);
			normalize_parser_node(while_node.block, tprint("%.block", path), layer, result);

		case .FOR;
			for_node := node.(*Parser.Parser_For);
			add_normalized_field(result, path, "flags", tprint("%", for_node.for_flags));
			normalize_parser_node(for_node.ident_it, tprint("%.iterator", path), layer, result);
			normalize_parser_node(for_node.ident_it_index, tprint("%.index", path), layer, result);
			normalize_parser_node(for_node.iteration_expression, tprint("%.iteration", path), layer, result);
			normalize_parser_node(for_node.iteration_expression_right, tprint("%.iteration_right", path), layer, result);
			normalize_parser_node(for_node.block, tprint("%.block", path), layer, result);

		case .IF;
			if_node := node.(*Parser.Parser_If);
			add_normalized_field(result, path, "switch", tprint("%", (if_node.if_flags & .IS_SWITCH_STATEMENT) != 0));
			add_normalized_field(result, path, "ifx", tprint("%", (if_node.if_flags & .IS_IFX) != 0));
			add_normalized_field(result, path, "complete", tprint("%", (if_node.if_flags & .MARKED_AS_COMPLETE) != 0));
			normalize_parser_node(if_node.condition, tprint("%.condition", path), layer, result);
			normalize_parser_node(if_node.then_block, tprint("%.then", path), layer, result);
			normalize_parser_node(if_node.else_block, tprint("%.else", path), layer, result);

		case .CASE;
			case_node := node.(*Parser.Parser_Case);
			add_normalized_field(result, path, "fallthrough", tprint("%", case_node.marked_as_fallthrough));
			normalize_parser_node(case_node.condition, tprint("%.condition", path), layer, result);
			normalize_parser_node(case_node.then_block, tprint("%.block", path), layer, result);

		case .DEFER;
			defer_node := node.(*Parser.Parser_Defer);
			add_normalized_field(result, path, "backticked", tprint("%", defer_node.is_backticked));
			normalize_parser_node(defer_node.block, tprint("%.block", path), layer, result);

		case .USING;
			using_node := node.(*Parser.Parser_Using);
			add_normalized_field(result, path, "filter_type", tprint("%", using_node.filter_type));
			add_normalized_field(result, path, "no_parameters", tprint("%", using_node.no_parameters));
			normalize_parser_node(using_node.expression, tprint("%.expression", path), layer, result);
			normalize_parser_node(using_node.filter_expression, tprint("%.filter", path), layer, result);

		case .PUSH_CONTEXT;
			push := node.(*Parser.Parser_Push_Context);
			add_normalized_field(result, path, "flags", tprint("%", push.push_context_flags));
			normalize_parser_node(push.to_push, tprint("%.expression", path), layer, result);
			normalize_parser_node(push.block, tprint("%.block", path), layer, result);

		case .CONTEXT;
		case .PLACEHOLDER;

		case;
			add_normalized_field(result, path, "unsupported", "true");
	}
}

normalize_node :: (node: *Code_Node, path: string, layer: Comparison_Layer, result: *Normalized_Tree) {
	if !node {
		add_normalized_field(result, path, "kind", "<null>");
		return;
	}


	add_normalized_field(result, path, "kind", tprint("%", node.kind));
	add_normalized_field(result, path, "parenthesized", tprint("%", (node.node_flags & .IS_PARENTHESIZED) != 0));

	if layer == .SEMANTIC {
		add_normalized_field(result, path, "has_type", tprint("%", node.type != null));
	}

	if node.kind == {
		case .IDENT;
			ident := node.(*Code_Ident);
			add_normalized_field(result, path, "name", ident.name);
			add_normalized_field(result, path, "has_scope_modifier", tprint("%", (ident.flags & .HAS_SCOPE_MODIFIER) != 0));
			add_normalized_field(result, path, "do_not_resolve", tprint("%", (ident.flags & .DO_NOT_RESOLVE_DUE_TO_PARSER) != 0));

		case .LITERAL;
			literal := node.(*Code_Literal);
			add_normalized_field(result, path, "value_type", tprint("%", literal.value_type));
			add_normalized_field(result, path, "value_flags", tprint("%", literal.value_flags));

			if literal.value_type == {
				case .NUMBER;
					if literal.value_flags & .FLOAT {
						add_normalized_field(result, path, "float64", tprint("%", literal._float64));
					} else {
						add_normalized_field(result, path, "u64", tprint("%", literal._u64));
					}

				case .STRING;
					add_normalized_field(result, path, "string", literal._string);

				case .BOOLEAN;
					add_normalized_field(result, path, "boolean", tprint("%", literal._u64));

				case .POINTER;
					if literal.pointer_literal_info {
						add_normalized_field(result, path, "pointer_type", tprint("%", literal.pointer_literal_info.pointer_literal_type));
						add_normalized_field(result, path, "pointer_offset", tprint("%", literal.pointer_literal_info.offset_from_symbol));
					} else {
						add_normalized_field(result, path, "pointer_type", "<missing>");
					}

				case .ARRAY;
					info := literal.array_literal_info;
					add_normalized_field(result, path, "untyped", tprint("%", (info.array_literal_flags & .WAS_UNTYPED) != 0));
					add_normalized_field(result, path, "member_count", tprint("%", info.array_members.count));
					if info.element_type {
						normalize_node(info.element_type.type_valued_expression, tprint("%.element_type", path), layer, result);
					}
					for info.array_members {
						normalize_node(it, tprint("%.member[%]", path, it_index), layer, result);
					}

				case .STRUCT;
					info := literal.struct_literal_info;
					add_normalized_field(result, path, "argument_count", tprint("%", info.arguments.count));
					if info.type_expression {
						normalize_node(info.type_expression.type_valued_expression, tprint("%.type_expression", path), layer, result);
					}
					for info.arguments {
						normalize_node(it, tprint("%.argument[%]", path, it_index), layer, result);
					}
			}

		case .UNARY_OPERATOR;
			unary := node.(*Code_Unary_Operator);
			add_normalized_field(result, path, "operator", tprint("%", unary.operator_type));
			normalize_node(unary.subexpression, tprint("%.operand", path), layer, result);

		case .BINARY_OPERATOR;
			binary := node.(*Code_Binary_Operator);
			add_normalized_field(result, path, "operator", tprint("%", binary.operator_type));
			add_normalized_field(result, path, "operator_flags", tprint("%", binary.flags));
			normalize_node(binary.left, tprint("%.left", path), layer, result);
			normalize_node(binary.right, tprint("%.right", path), layer, result);

		case .PROCEDURE_CALL;
			call := node.(*Code_Procedure_Call);
			add_normalized_field(result, path, "argument_count", tprint("%", call.arguments_unsorted.count));
			normalize_node(call.procedure_expression, tprint("%.procedure", path), layer, result);
			for call.arguments_unsorted {
				argument_path := tprint("%.argument[%]", path, it_index);
				add_normalized_field(result, argument_path, "name", ifx it.name then it.name.name else "<positional>");
				normalize_node(it.expression, tprint("%.expression", argument_path), layer, result);
			}

		case .CAST;
			cast_node := node.(*Code_Cast);
			add_normalized_field(result, path, "cast_flags", tprint("%", cast_node.cast_flags));
			if cast_node.target_type {
				normalize_node(cast_node.target_type.type_valued_expression, tprint("%.target_type", path), layer, result);
			}
			normalize_node(cast_node.expression, tprint("%.expression", path), layer, result);

		case .EXPRESSION_QUERY;
			query := node.(*Code_Expression_Query);
			add_normalized_field(result, path, "query_kind", tprint("%", query.query_kind));
			normalize_node(query.expression_to_query, tprint("%.expression", path), layer, result);

		case .TYPE_QUERY;
			query := node.(*Code_Type_Query);
			add_normalized_field(result, path, "query_kind", tprint("%", query.query_kind));
			normalize_node(query.type_to_query.type_valued_expression, tprint("%.type", path), layer, result);

		case .DIRECTIVE_CODE;
			directive := node.(*Code_Directive_Code);
			add_normalized_field(result, path, "code_flags", tprint("%", directive.code_flags));
			normalize_node(directive.expression, tprint("%.expression", path), layer, result);

		case .DIRECTIVE_RUN;
			directive := node.(*Code_Directive_Run);
			add_normalized_field(result, path, "flags", tprint("%", directive.flags));
			expression: *Code_Node;
			if directive.procedure && directive.procedure.body_or_null {
				body := directive.procedure.body_or_null.block;
				if (body.node_flags & .IS_PARENTHESIZED) != 0 {
					expression = body;
				} else if body.statements.count == 1 {
					expression = body.statements[0];
				}
			}
			normalize_node(expression, tprint("%.expression", path), layer, result);

		case .DIRECTIVE_INSERT;
			directive := node.(*Code_Directive_Insert);
			normalize_node(directive.expression, tprint("%.expression", path), layer, result);
			normalize_node(directive.scope_redirection, tprint("%.scope", path), layer, result);
			normalize_node(directive.break_replacement, tprint("%.break", path), layer, result);
			normalize_node(directive.continue_replacement, tprint("%.continue", path), layer, result);
			normalize_node(directive.remove_replacement, tprint("%.remove", path), layer, result);

		case .DIRECTIVE_BAKE;
			directive := node.(*Code_Directive_Bake);
			add_normalized_field(result, path, "bake_type", tprint("%", directive.bake_type));
			normalize_node(directive.procedure_call, tprint("%.call", path), layer, result);

		case .DIRECTIVE_LOCATION;
			directive := node.(*Code_Directive_Location);
			add_normalized_field(result, path, "caller", tprint("%", directive.is_caller_location));
			normalize_node(directive.expression, tprint("%.expression", path), layer, result);

		case .DIRECTIVE_LIBRARY;
			directive := node.(*Code_Directive_Library);
			add_normalized_field(result, path, "name", directive.name);
			add_normalized_field(result, path, "flags", tprint("%", directive.library_flags));

		case .DIRECTIVE_LOAD;
			add_normalized_field(result, path, "name", node.(*Code_Directive_Load).short_name);

		case .DIRECTIVE_BYTES;
			normalize_node(node.(*Code_Directive_Bytes).expression, tprint("%.expression", path), layer, result);

		case .DIRECTIVE_PROCEDURE_NAME;
			normalize_node(node.(*Code_Directive_Procedure_Name).argument, tprint("%.argument", path), layer, result);

		case .DIRECTIVE_WILDCARD;

		case .DIRECTIVE_EXISTS;
			directive := node.(*Code_Directive_Exists);
			normalize_node(directive.query_expression, tprint("%.query", path), layer, result);
			normalize_node(directive.sync_expression, tprint("%.sync", path), layer, result);

		case .DIRECTIVE_IMPORT;
			directive := node.(*Code_Directive_Import);
			add_normalized_field(result, path, "name", directive.name);
			add_normalized_field(result, path, "flags", tprint("%", directive.flags));
			add_normalized_field(result, path, "import_type", tprint("%", directive.import_type));
			add_normalized_field(result, path, "module_argument_count", tprint("%", ifx directive.module_parameters_call then directive.module_parameters_call.arguments_unsorted.count else 0));
			add_normalized_field(result, path, "program_argument_count", tprint("%", ifx directive.program_parameters_call then directive.program_parameters_call.arguments_unsorted.count else 0));

		case .DIRECTIVE_POKE_NAME;
			add_normalized_field(result, path, "name", node.(*Code_Directive_Poke_Name).name);

		case .DIRECTIVE_THROUGH;

		case .DIRECTIVE_OVERLAY;
			directive := node.(*Code_Directive_Overlay);
			normalize_node(directive.target_expression, tprint("%.target", path), layer, result);
			normalize_node(directive.declaration_or_using, tprint("%.declaration", path), layer, result);

		case .DIRECTIVE_ADD_CONTEXT;
			normalize_node(node.(*Code_Directive_Add_Context).expression, tprint("%.expression", path), layer, result);

		case .DIRECTIVE_CONTEXT_TYPE;

		case .DIRECTIVE_SCOPE;
			add_normalized_field(result, path, "scope_type", tprint("%", node.(*Code_Directive_Scope).scope_type));

		case .DIRECTIVE_MODULE_PARAMETERS;
			directive := node.(*Code_Directive_Module_Parameters);
			normalize_node(directive.module_parameters, tprint("%.module", path), layer, result);
			normalize_node(directive.program_parameters, tprint("%.program", path), layer, result);
			normalize_node(directive.common_code, tprint("%.common", path), layer, result);

		case .DIRECTIVE_MODIFY;
			normalize_node(node.(*Code_Directive_Modify).block, tprint("%.block", path), layer, result);

		case .TYPE_INSTANTIATION;
			type_inst := node.(*Code_Type_Instantiation);
			add_normalized_field(result, path, "inst_flags", tprint("%", type_inst.inst_flags));
			normalize_node(type_inst.type_valued_expression, tprint("%.expression", path), layer, result);
			normalize_node(type_inst.must_implement, tprint("%.restriction", path), layer, result);
			normalize_node(type_inst.pointer_to, tprint("%.pointer_to", path), layer, result);
			normalize_node(type_inst.type_directive_target, tprint("%.directive_target", path), layer, result);
			normalize_node(type_inst.array_element_type, tprint("%.element_type", path), layer, result);
			normalize_node(type_inst.array_dimension, tprint("%.dimension", path), layer, result);

		case .PROCEDURE_HEADER;
			header := node.(*Code_Procedure_Header);
			add_normalized_field(result, path, "flags", tprint("%", procedure_syntax_flags(header.procedure_flags)));
			add_normalized_field(result, path, "name", header.name);
			add_normalized_field(result, path, "foreign_name", header.foreign_function_name);
			add_normalized_field(result, path, "library", ifx header.library_identifier then header.library_identifier.name else "");
			add_normalized_field(result, path, "deprecated", header.deprecation_string);
			add_normalized_field(result, path, "using_count", tprint("%", header.parameter_usings.count));
			add_normalized_field(result, path, "modify_count", tprint("%", header.modify_directives.count));
			add_normalized_field(result, path, "argument_count", tprint("%", header.arguments.count));
			add_normalized_field(result, path, "return_count", tprint("%", header.returns.count));
			for header.arguments {
				argument_path := tprint("%.argument[%]", path, it_index);
				if header.procedure_flags & .QUICK {
					add_normalized_field(result, argument_path, "kind", tprint("%", it.kind));
					add_normalized_field(result, argument_path, "name", it.name);
				} else {
					normalize_node(it, argument_path, layer, result);
				}
			}
			for header.returns normalize_node(it, tprint("%.return[%]", path, it_index), layer, result);
			for header.modify_directives 	normalize_node(it, tprint("%.modify[%]", path, it_index), layer, result);

		case .PROCEDURE_BODY;
			body := node.(*Code_Procedure_Body);
			normalize_node(body.block, tprint("%.block", path), layer, result);

		case .STRUCT;
			aggregate := node.(*Code_Struct);
			add_normalized_field(result, path, "flags", tprint("%", aggregate.textual_flags));
			add_normalized_field(result, path, "note_count", tprint("%", aggregate.notes.count));
			for aggregate.notes add_normalized_field(result, tprint("%.note[%]", path, it_index), "text", it.text);
			add_normalized_field(result, path, "modify_count", tprint("%", aggregate.modify_directives.count));
			for aggregate.modify_directives 	normalize_node(it, tprint("%.modify[%]", path, it_index), layer, result);
			normalize_node(aggregate.block, tprint("%.block", path), layer, result);

		case .ENUM;
			aggregate := node.(*Code_Enum);
			add_normalized_field(result, path, "flags", tprint("%", aggregate.is_flags));
			add_normalized_field(result, path, "complete", tprint("%", aggregate.marked_as_complete));
			add_normalized_field(result, path, "specified", tprint("%", aggregate.marked_as_specified));
			add_normalized_field(result, path, "note_count", tprint("%", aggregate.notes.count));
			for aggregate.notes add_normalized_field(result, tprint("%.note[%]", path, it_index), "text", it.text);
			normalize_node(aggregate.internal_type_inst, tprint("%.internal_type", path), layer, result);
			normalize_node(aggregate.block, tprint("%.block", path), layer, result);

		case .DECLARATION;
			declaration := node.(*Code_Declaration);
			normalize_declaration(declaration, path, layer, result);

		case .COMPOUND_DECLARATION;
			declaration := node.(*Code_Compound_Declaration);
			add_normalized_field(result, path, "argument_count", tprint("%", declaration.comma_separated_assignment.arguments.count));
			for declaration.comma_separated_assignment.arguments normalize_node(it.node, tprint("%.argument[%]", path, it_index), layer, result);
			normalize_declaration(declaration.declaration_properties, tprint("%.properties", path), layer, result);
			normalize_node(declaration.alignment_expression, tprint("%.alignment", path), layer, result);
			add_normalized_field(result, path, "note_count", tprint("%", declaration.notes.count));
			for declaration.notes add_normalized_field(result, tprint("%.note[%]", path, it_index), "text", it.text);

		case .COMMA_SEPARATED_ARGUMENTS;
			arguments := node.(*Code_Comma_Separated_Arguments);
			add_normalized_field(result, path, "argument_count", tprint("%", arguments.arguments.count));
			for arguments.arguments normalize_node(it.node, tprint("%.argument[%]", path, it_index), layer, result);

		case .NOTE;
			add_normalized_field(result, path, "text", node.(*Code_Note).text);

		case .BLOCK;
			block := node.(*Code_Block);
			add_normalized_field(result, path, "block_type", tprint("%", block.block_type));
			add_normalized_field(result, path, "statement_count", tprint("%", block.statements.count));
			for block.statements	normalize_node(it, tprint("%.statement[%]", path, it_index), layer, result);

		case .RETURN;
			return_node := node.(*Code_Return);
			add_normalized_field(result, path, "backticked", tprint("%", (return_node.return_flags & .IS_BACKTICKED) != 0));
			add_normalized_field(result, path, "quick", tprint("%", (return_node.return_flags & .AUTO_INSERTED_FOR_QUICK_LAMBDA) != 0));
			add_normalized_field(result, path, "argument_count", tprint("%", return_node.arguments_unsorted.count));
			for return_node.arguments_unsorted	normalize_node(it.expression, tprint("%.argument[%]", path, it_index), layer, result);

		case .LOOP_CONTROL;
			control := node.(*Code_Loop_Control);
			add_normalized_field(result, path, "control_type", tprint("%", control.control_type));
			normalize_node(control.target_ident, tprint("%.target", path), layer, result);

		case .WHILE;
			while_node := node.(*Code_While);
			normalize_node(while_node.condition, tprint("%.condition", path), layer, result);
			normalize_node(while_node.block, tprint("%.block", path), layer, result);

		case .FOR;
			for_node := node.(*Code_For);
			add_normalized_field(result, path, "flags", tprint("%", for_node.for_flags));
			normalize_node(for_node.ident_it, tprint("%.iterator", path), layer, result);
			normalize_node(for_node.ident_it_index, tprint("%.index", path), layer, result);
			normalize_node(for_node.iteration_expression, tprint("%.iteration", path), layer, result);
			normalize_node(for_node.iteration_expression_right, tprint("%.iteration_right", path), layer, result);
			normalize_node(for_node.block, tprint("%.block", path), layer, result);

		case .IF;
			if_node := node.(*Code_If);
			add_normalized_field(result, path, "switch", tprint("%", (if_node.if_flags & .IS_SWITCH_STATEMENT) != 0));
			add_normalized_field(result, path, "ifx", tprint("%", (if_node.if_flags & .IS_IFX) != 0));
			add_normalized_field(result, path, "complete", tprint("%", (if_node.if_flags & .MARKED_AS_COMPLETE) != 0));
			normalize_node(if_node.condition, tprint("%.condition", path), layer, result);
			normalize_node(if_node.then_block, tprint("%.then", path), layer, result);
			normalize_node(if_node.else_block, tprint("%.else", path), layer, result);

		case .CASE;
			case_node := node.(*Code_Case);
			add_normalized_field(result, path, "fallthrough", tprint("%", case_node.marked_as_fallthrough));
			normalize_node(case_node.condition, tprint("%.condition", path), layer, result);
			normalize_node(case_node.then_block, tprint("%.block", path), layer, result);

		case .DEFER;
			defer_node := node.(*Code_Defer);
			add_normalized_field(result, path, "backticked", tprint("%", defer_node.is_backticked));
			normalize_node(defer_node.block, tprint("%.block", path), layer, result);

		case .USING;
			using_node := node.(*Code_Using);
			add_normalized_field(result, path, "filter_type", tprint("%", using_node.filter_type));
			add_normalized_field(result, path, "no_parameters", tprint("%", using_node.no_parameters));
			normalize_node(using_node.expression, tprint("%.expression", path), layer, result);
			normalize_node(using_node.filter_expression, tprint("%.filter", path), layer, result);

		case .PUSH_CONTEXT;
			push := node.(*Code_Push_Context);
			add_normalized_field(result, path, "flags", tprint("%", push.push_context_flags));
			normalize_node(push.to_push, tprint("%.expression", path), layer, result);
			normalize_node(push.block, tprint("%.block", path), layer, result);

		case .CONTEXT;
		case .PLACEHOLDER;

		case;
			add_normalized_field(result, path, "unsupported", "true");
	}
}

normalize_parser_declaration :: (declaration: *Parser.Parser_Declaration, path: string, layer: Comparison_Layer, result: *Normalized_Tree) {
	add_normalized_field(result, path, "name", declaration.name);
	add_normalized_field(result, path, "constant", tprint("%", (declaration.flags & .IS_CONSTANT) != 0));
	add_normalized_field(result, path, "uninitialized", tprint("%", (declaration.flags & .IS_UNINITIALIZED) != 0));
	add_normalized_field(result, path, "auto_bake", tprint("%", (declaration.flags & .AUTO_VALUE_BAKE) != 0));
	add_normalized_field(result, path, "auto_bake_required", tprint("%", (declaration.flags & .AUTO_VALUE_BAKE_IS_REQUIRED) != 0));
	add_normalized_field(result, path, "scope_modifier", tprint("%", (declaration.flags & .HAS_SCOPE_MODIFIER) != 0));
	normalize_parser_node(declaration.type_inst, tprint("%.type", path), layer, result);
	normalize_parser_node(declaration.expression, tprint("%.expression", path), layer, result);
	normalize_parser_node(declaration.alignment_expression, tprint("%.alignment", path), layer, result);
	add_normalized_field(result, path, "note_count", tprint("%", declaration.notes.count));
	for declaration.notes {
		add_normalized_field(result, tprint("%.note[%]", path, it_index), "text", it.text);
	}
}

normalize_declaration :: (declaration: *Code_Declaration, path: string, layer: Comparison_Layer, result: *Normalized_Tree) {
	add_normalized_field(result, path, "name", declaration.name);
	add_normalized_field(result, path, "constant", tprint("%", (declaration.flags & .IS_CONSTANT) != 0));
	add_normalized_field(result, path, "uninitialized", tprint("%", (declaration.flags & .IS_UNINITIALIZED) != 0));
	add_normalized_field(result, path, "auto_bake", tprint("%", (declaration.flags & .AUTO_VALUE_BAKE) != 0));
	add_normalized_field(result, path, "auto_bake_required", tprint("%", (declaration.flags & .AUTO_VALUE_BAKE_IS_REQUIRED) != 0));
	add_normalized_field(result, path, "scope_modifier", tprint("%", (declaration.flags & .HAS_SCOPE_MODIFIER) != 0));
	normalize_node(declaration.type_inst, tprint("%.type", path), layer, result);
	normalize_node(declaration.expression, tprint("%.expression", path), layer, result);
	normalize_node(declaration.alignment_expression, tprint("%.alignment", path), layer, result);
	add_normalized_field(result, path, "note_count", tprint("%", declaration.notes.count));
	for declaration.notes add_normalized_field(result, tprint("%.note[%]", path, it_index), "text", it.text);
}

add_normalized_field :: (tree: *Normalized_Tree, path: string, name: string, value: string) {
	array_add(*tree.fields, .{path=tprint("%.%", path, name), value=value});
}

find_normalized_field :: (fields: [] Normalized_Field, path: string) -> *Normalized_Field {
	for * fields {
		if it.path == path return it;
	}


	return null;
}

compare_normalized_trees :: (actual: Normalized_Tree, expected: Normalized_Tree) -> Differential_Result {
	result: Differential_Result;

	for expected.fields {
		actual_field := find_normalized_field(actual.fields, it.path);
		if !actual_field {
			array_add(*result.differences, .{path=it.path, expected=it.value, actual="<missing>"});
		} else if actual_field.value != it.value {
			array_add(*result.differences, .{path=it.path, expected=it.value, actual=actual_field.value});
		}
	}

	for actual.fields {
		if !find_normalized_field(expected.fields, it.path) {
			array_add(*result.differences, .{path=it.path, expected="<missing>", actual=it.value});
		}
	}

	return result;
}

format_structural_differences :: (result: Differential_Result) -> string {
	builder: String_Builder;
	for result.differences {
		print_to_builder(*builder, "%: expected %, actual %\n", it.path, it.expected, it.actual);
	}

	return builder_to_string(*builder);
}

assert_expression_matches_code :: (source: string, expected_code: Code, layer := Comparison_Layer.SYNTAX) {
	parsed := Parser.parse_expression(source);
	defer Parser.release_parser_tree(*parsed);
	assert(parsed.status == .COMPLETE, "Parser did not complete fixture '%'.", source);

	actual := normalize_parser_tree(parsed.root, layer);
	expected := normalize_tree(compiler_get_nodes(expected_code), layer);
	difference := compare_normalized_trees(actual, expected);
	assert(!difference.differences.count, "AST mismatch for '%':\n%", source, format_structural_differences(difference));
}

assert_expression_fixture :: ($source: string, $layer := Comparison_Layer.SYNTAX) #expand {
	#insert -> string {
		return tprint("assert_expression_matches_code(source, (#code %), layer);", source);
	}
}

assert_statement_matches_code :: (source: string, expected_code: Code) {
	parsed := Parser.parse_block(tprint("{ % }", source));
	defer Parser.release_parser_tree(*parsed);

	assert(parsed.status == .COMPLETE, "Parser did not complete statement fixture '%'.", source);
	actual_block := parsed.root.(*Parser.Parser_Block);
	assert(actual_block.statements.count == 1, "Parser produced % statements for fixture '%'.", actual_block.statements.count, source);

	expected_root := compiler_get_nodes(expected_code);
	assert(expected_root.kind == .BLOCK);
	expected_block := expected_root.(*Code_Block);
	assert(expected_block.statements.count == 1, "Compiler produced % statements for fixture '%'.", expected_block.statements.count, source);

	actual := normalize_parser_tree(actual_block.statements[0]);
	expected := normalize_tree(expected_block.statements[0]);
	difference := compare_normalized_trees(actual, expected);
	assert(!difference.differences.count, "Statement AST mismatch for '%':\n%", source, format_structural_differences(difference));
}

assert_statement_fixture :: ($source: string) #expand {
	#insert -> string {
		return tprint("assert_statement_matches_code(source, #code { % });", source);
	}
}

assert_all_operator_fixtures :: () #expand {
	#insert -> string {
		operators := string.[
			"<<", ">>", "<<<", ">>>", "&", "|", "^",
			"*", "/", "%", "+", "-",
			"==", "!=", "<=", ">=", "<", ">", "&&", "||",
			"=", "+=", "-=", "*=", "/=", "%=", "<<=", ">>=", "<<<=", ">>>=", "&=", "|=", "^=", "&&=", "||="
		];
		builder: String_Builder;
		for operators {
			source := tprint("a % b", it);
			print(*builder, "assert_expression_matches_code(\"%\", (#code %));\n", source, source);
		}

		return builder_to_string(*builder);
	}
}

assert_all_precedence_pairs :: () #expand {
	#insert -> string {
		// Ordered lowest to highest according to print_precedences.jai.
		representatives := string.["=", "||", "&&", "==", "+", "%", "*", "<<"];
		builder: String_Builder;
		for lower_index: 0..representatives.count-2 {
			for higher_index: lower_index+1..representatives.count-1 {
				lower := representatives[lower_index];
				higher := representatives[higher_index];
				lower_then_higher := tprint("a % b % c", lower, higher);
				higher_then_lower := tprint("a % b % c", higher, lower);
				print(*builder, "assert_expression_matches_code(\"%\", (#code %));\n", lower_then_higher, lower_then_higher);
				print(*builder, "assert_expression_matches_code(\"%\", (#code %));\n", higher_then_lower, higher_then_lower);
			}
		}

		return builder_to_string(*builder);
	}
}

assert_trivia_round_trip :: (source: string) {
	parsed := Parser.materialize_tokens(source);
	reconstructed := Parser.reconstruct_source(*parsed);
	assert(reconstructed == source, "Trivia round trip differed for source:\n%", source);
}

run_typechecked_workspace_fixture :: (source: string, expected_declaration: string) -> Workspace_Fixture_Result {
	result: Workspace_Fixture_Result;
	workspace := compiler_create_workspace("Jai_Parser differential fixture");
	assert(workspace != 0, "Unable to create differential fixture workspace.");

	options := get_build_options(workspace);
	copy_commonly_propagated_fields(get_build_options(), *options);
	options.output_type = .NO_OUTPUT;
	options.write_added_strings = false;
	set_build_options(options, workspace);

	compiler_begin_intercept(workspace);
	add_build_string(source, workspace);

	while true {
		message := compiler_wait_for_message();
		if message.workspace != workspace	continue;


		if message.kind == {
			case .TYPECHECKED;
				typechecked := message.(*Message_Typechecked);
				result.typechecked_message_count += 1;
				for declaration: typechecked.declarations {
					result.declaration_count += 1;
					if declaration.expression.name == expected_declaration {
						result.found_expected_declaration = true;
					}
				}

			case .COMPLETE;
				complete := message.(*Message_Complete);
				result.completed = true;
				result.compilation_succeeded = complete.error_code == .NONE;
				break;
		}
	}

	compiler_end_intercept(workspace);
	return result;
}

test_typechecked_workspace_fixture :: () {
	result := run_typechecked_workspace_fixture("fixture_value :: 1 + 2;", "fixture_value");
	assert(result.completed);
	assert(result.compilation_succeeded);
	assert(result.typechecked_message_count > 0);
	assert(result.declaration_count > 0);
	assert(result.found_expected_declaration);
}

assert_file_workspace_fixture :: (source: string, expected_declaration: string) {
	result := run_typechecked_workspace_fixture(source, expected_declaration);
	assert(result.completed, "Compiler did not complete file fixture '%'.", source);
	assert(result.compilation_succeeded, "Compiler rejected file fixture '%'.", source);
	assert(result.typechecked_message_count > 0, "Compiler did not typecheck file fixture '%'.", source);
	assert(result.found_expected_declaration, "Compiler did not expose '%' for file fixture '%'.", expected_declaration, source);
}

test_file_workspace_fixtures :: () {
	assert_file_workspace_fixture("#scope_file\nfixture_file_scope :: 1;", "fixture_file_scope");
	assert_file_workspace_fixture("#scope_export\nfixture_export_scope :: 1;", "fixture_export_scope");
	assert_file_workspace_fixture("#add_context fixture_context_value: s64;\nfixture_add_context :: 1;", "fixture_add_context");
}

assert_declaration_workspace_fixture :: (source: string) {
	parsed := Parser.parse_declaration(source);
	defer Parser.release_parser_tree(*parsed);
	assert(parsed.status == .COMPLETE, "Parser did not complete declaration fixture '%'.", source);
	actual := normalize_parser_tree(parsed.root);

	workspace := compiler_create_workspace("Jai_Parser declaration fixture");
	options := get_build_options(workspace);
	copy_commonly_propagated_fields(get_build_options(), *options);
	options.output_type = .NO_OUTPUT;
	options.write_added_strings = false;
	set_build_options(options, workspace);
	compiler_begin_intercept(workspace);
	add_build_string(tprint("Fixture_Constraint :: struct { value: s64; }\nfixture_procedure :: () {\n%\n}\n", source), workspace);

	found := false;
	while true {
		message := compiler_wait_for_message();
		if message.workspace != workspace	continue;


		if message.kind == {
			case .TYPECHECKED;
				typechecked := message.(*Message_Typechecked);
				for wrapped: typechecked.procedure_bodies {
					for statement: wrapped.expression.block.statements {
						matches := false;
						if parsed.root.kind == .DECLARATION && statement.kind == .DECLARATION {
							matches = statement.(*Code_Declaration).name == parsed.root.(*Parser.Parser_Declaration).name;
						} else if parsed.root.kind == .COMPOUND_DECLARATION && statement.kind == .COMPOUND_DECLARATION {
							expected := parsed.root.(*Parser.Parser_Compound_Declaration);
							actual_compound := statement.(*Code_Compound_Declaration);
							matches = actual_compound.comma_separated_assignment.arguments[0].node.(*Code_Ident).name == expected.comma_separated_assignment.arguments[0].node.(*Parser.Parser_Ident).name;
						}

						if !matches		continue;


						expected := normalize_tree(statement);
						difference := compare_normalized_trees(actual, expected);
						assert(!difference.differences.count, "Declaration AST mismatch for '%':\n%", source, format_structural_differences(difference));
						found = true;
					}
				}

			case .COMPLETE;
				complete := message.(*Message_Complete);
				assert(complete.error_code == .NONE, "Compiler rejected declaration fixture '%'.", source);
				break;
		}
	}

	compiler_end_intercept(workspace);
	assert(found, "Compiler did not expose declaration fixture '%'.", source);
}

test_declaration_workspace_fixtures :: () {
	assert_declaration_workspace_fixture("fixture_typed: **s64 = null;");
	assert_declaration_workspace_fixture("fixture_fixed: [4] s64;");
	assert_declaration_workspace_fixture("fixture_view: [] s64;");
	assert_declaration_workspace_fixture("fixture_resizable: [..] s64;");
	assert_declaration_workspace_fixture("fixture_callback: (value: s64) -> bool;");
	assert_declaration_workspace_fixture("fixture_alias :: #type,distinct u32;");
	assert_declaration_workspace_fixture("fixture_x, fixture_y: s64 = 7;");
	assert_declaration_workspace_fixture("fixture_a, fixture_b := 1, 2;");
	assert_declaration_workspace_fixture("fixture_aligned: s64 #align 16;");
	assert_declaration_workspace_fixture("fixture_noted: s64; @FixtureNote");
	assert_declaration_workspace_fixture("fixture_inline :: inline () {}");
	assert_declaration_workspace_fixture("fixture_no_inline :: no_inline () {}");
	assert_declaration_workspace_fixture("fixture_modify :: (value: $T) -> T #modify { return true; } { return value; }");
	assert_declaration_workspace_fixture("Fixture_Modified_Struct :: struct (T: Type) #modify { return true; } { value: T; }");
	assert_declaration_workspace_fixture("Fixture_Struct :: struct { CONSTANT :: 1; }; @Serializable");
	assert_declaration_workspace_fixture("fixture_uninitialized: s64 = ---;");
}

#run {
	assert_all_operator_fixtures();
	assert_all_precedence_pairs();
	assert_expression_fixture("identifier");
	assert_expression_fixture("42");
	assert_expression_fixture("0xff");
	assert_expression_fixture("0b101");
	assert_expression_fixture("1.25");
	assert_expression_fixture("\"hello\\n\"");
	assert_expression_fixture("true");
	assert_expression_fixture("false");
	assert_expression_fixture("null");
	assert_expression_fixture("context");
	assert_expression_fixture(".[1, 2, 3]");
	assert_expression_fixture("u8.[1, 2, 3]");
	assert_expression_fixture(".{1, 2, 3}");
	assert_expression_fixture("Foo.{1, 2, 3}");
	assert_expression_fixture(".member");
	assert_expression_fixture("#string END\nbody\nEND");
	assert_expression_fixture("(identifier)");
	assert_expression_fixture("!~flag");
	assert_expression_fixture("foo()");
	assert_expression_fixture("foo(1, named = value)");
	assert_expression_fixture("object.method(1)[index].*");
	assert_expression_fixture("cast(s32) value");
	assert_expression_fixture("value.(s32)");
	assert_expression_fixture("xx value");
	assert_expression_fixture("type_of(a + b)");
	assert_expression_fixture("is_constant(42)");
	assert_expression_fixture("code_of(value)");
	assert_expression_fixture("size_of(s64)");
	assert_expression_fixture("type_info(Thing)");
	assert_expression_fixture("initializer_of(Thing)");
	assert_expression_fixture("#code value + 1");
	assert_expression_fixture("#code,null");
	assert_expression_fixture("#code,typed value");
	assert_expression_fixture("#code { value := 1; use(value); }");
	assert_expression_fixture("#code,typed { value := 1; use(value); }");
	assert_expression_fixture("#run compute()");
	assert_expression_fixture("#run,stallable compute()");
	assert_expression_fixture("#run,stallable { value := compute(); return value; }");
	assert_expression_fixture("#insert generated_code");
	assert_expression_fixture("#insert -> string { return \"generated\"; }");
	assert_expression_fixture("#insert,scope(caller) (break=break outer, continue=continue outer, remove=remove outer) body");
	assert_expression_fixture("#location()");
	assert_expression_fixture("#location(value)");
	assert_expression_fixture("#caller_location");
	assert_expression_fixture("#load \"local.jai\"");
	assert_expression_fixture("#bytes .[1, 2, 3]");
	assert_expression_fixture("#procedure_name()");
	assert_expression_fixture("#procedure_name(target)");
	assert_expression_fixture("#exists(value)");
	assert_expression_fixture("#exists(value, ready)");
	assert_expression_fixture("#import \"Basic\"");
	assert_expression_fixture("#import,file \"../module.jai\"");
	assert_expression_fixture("#import,dir \"../module\"");
	assert_expression_fixture("#import,string \"fixture_value :: 1;\"");
	assert_expression_fixture("#import,file \"../module.jai\"(DEBUG=true)(PROGRAM_DEBUG=false)");
	assert_expression_fixture("#library,system \"Example\"");
	assert_expression_fixture("#library,no_static_library \"Example\"");
	assert_expression_fixture("#library,link_always \"Example\"");
	assert_expression_fixture("#bake_constants specialize(value)");
	assert_expression_fixture("#bake_arguments specialize(value)");
	assert_expression_fixture("a + b * c");
	assert_expression_fixture("a * b % c + d");
	assert_expression_fixture("a - b - c");
	assert_expression_fixture("a << b & c == d && e || f");
	assert_expression_fixture("a <<< b >>> c");
	assert_expression_fixture("a += b *= c");
	assert_expression_fixture("-value.*");
	assert_expression_fixture("(.*)value.*");
	assert_expression_fixture("(-value).member");
	assert_expression_fixture("-(a + b) * c");
	assert_expression_fixture("(a + b)[index]");
	assert_expression_fixture("(a + b).(Result)");
	assert_expression_fixture(".member.field");
	assert_expression_fixture("value.*.member[index]");
	assert_expression_fixture("ifx ready then 1 else 2");
	assert_expression_fixture("ifx ready { prepare(); 1; } else { 2; }");
	assert_expression_fixture("() { return; }");
	assert_expression_fixture("(value: $T) -> T #expand #compile_time { return value; }");
	assert_expression_fixture("(items: ..Any) -> value: s64, found: bool { return 0, false; }");
	assert_expression_fixture("(value: $T/interface Constraint) -> T");
	assert_expression_fixture("(using value: *Thing) { return; }");
	assert_expression_fixture("() -> s64 #foreign kernel32 \"external_name\"");
	assert_expression_fixture("() #deprecated \"Use replacement instead.\" { return; }");
	assert_expression_fixture("value => value + 1");
	assert_expression_fixture("(left, right) => { return left + right; }");
	assert_expression_fixture("struct { value: s64; }");
	assert_expression_fixture("struct { value: u64; #overlay (value) bits: u64; }");
	assert_expression_fixture("struct (T: Type, N := 2) { value: T; CONSTANT :: N; }");
	assert_expression_fixture("struct { value: s64; } #no_padding");
	assert_expression_fixture("struct #type_info_none #type_info_no_size_complaint #type_info_procedures_are_void_pointers {}");
	assert_expression_fixture("union { integer: s64; text: string; }");
	assert_expression_fixture("enum u16 #specified { READ :: 1; WRITE :: 2; }");
	assert_expression_fixture("enum #complete { READY; DONE; }");
	assert_expression_fixture("enum_flags u32 { FAST; SAFE; }");
	assert_statement_fixture("return 1, 2;");
	assert_statement_fixture("{ value := 1; }");
	assert_statement_fixture("`return 1;");
	assert_statement_fixture("while ready { break; }");
	assert_statement_fixture("while loop := ready { break loop; }");
	assert_statement_fixture("for item, index: values { continue; }");
	assert_statement_fixture("for 1..3 defer tick();");
	assert_statement_fixture("for < values process(it);");
	assert_statement_fixture("for * values process(it);");
	assert_statement_fixture("if ready then run(); else stop();");
	assert_statement_fixture("if value == { case 1; return; case; break; }");
	assert_statement_fixture("if #complete value == { case 1; #through; case 2; return; case; return; }");
	assert_statement_fixture("defer cleanup();");
	assert_statement_fixture("`defer cleanup();");
	assert_statement_fixture("defer { cleanup(); }");
	assert_statement_fixture("using state;");
	assert_statement_fixture("using local: State;");
	assert_statement_fixture("push_context new_context { return; }");
	assert_statement_fixture("push_context { return; }");
	assert_statement_fixture("`push_context,defer_pop remap_context();");
}

#run,stallable test_typechecked_workspace_fixture();
#run,stallable test_file_workspace_fixtures();
#run,stallable test_declaration_workspace_fixtures();
