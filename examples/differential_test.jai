// Normalise parser and compiler ASTs from paired fixtures and compare their syntax; child workspaces cover contextual nodes, while invalid fixtures compare diagnostics.
#import "Basic";
#import "Compiler";
#import "File";
#import "Process";
#import "String";

#load "test_fixtures.jai";

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

CLEAR_PROGRESS_LINE :: "\r\e[K";

DIFFERENTIAL_SECTION_TOTAL	:: 23;
CONTEXT_TEST_TOTAL			:: 1;
TYPECHECKED_TEST_TOTAL		:: 1;
FILE_SCOPE_TEST_TOTAL		:: 3;
ASSEMBLY_CONTEXT_TEST_TOTAL	:: 8;
MEMBER_QUERY_TEST_TOTAL		:: 3;
DEFAULT_OVERLOAD_TEST_TOTAL	:: 10;
INTEGER_ROUNDING_TEST_TOTAL	:: 1;
AGGREGATE_TEST_TOTAL		:: 53;
ASSIGNMENT_TEST_TOTAL		:: 2;
RUNTIME_TEST_TOTAL			:: 8;

Differential_Section :: struct {
	name: string;
	total: s64;
}

COMPILED_SECTION :: #run -> string {
	arguments := get_build_options().compile_time_command_line;
	assert(arguments.count <= 1, "Pass one section number or quoted name after '-'; use '- list' to list sections.");
	if arguments.count {
		return arguments[0];
	}


	return "";
};

SYNTAX_TEST_TOTAL :: #run count_syntax_tests();
DIFFERENTIAL_SECTIONS :: #run collect_differential_sections();

Differential_Progress :: struct {
	section_index: s64;
	section_name: string;
	test_index: s64;
	test_total: s64;
	test_depth: s64;
	global_index: s64;
	global_total: s64;
	selection: string;
	section_enabled: bool;
	planning: bool;
	sections: [DIFFERENTIAL_SECTION_TOTAL] Differential_Section;
	fixture_source: string;
	fixture_path: string;
	failed: bool;
	counting: bool;
}

differential_progress: Differential_Progress;
previous_assertion_handler: (Source_Code_Location, string) -> bool;

differential_assertion_failed :: (location: Source_Code_Location, message: string) -> bool {
	differential_progress.failed = true;
	print_differential_test();
	print("\e[91mFAIL\e[0m\n");
	if !retain_differential_fixture() {
		print("Unable to save failed fixture.\n");
	} else if differential_progress.fixture_path {
		print("\e[93mRetained fixture: %\e[0m\n", differential_progress.fixture_path);
	}

	return previous_assertion_handler(location, message);
}

print_differential_test :: () {
	print(
		"%\e[90m[\e[91m%\e[90m/\e[91m%\e[90m]\e[0m \e[96m%\e[0m \e[93m%/%\e[0m \e[90m(total\e[0m \e[92m%\e[34m/\e[92m%\e[0m\e[90m)\e[0m: ",
		CLEAR_PROGRESS_LINE,
		differential_progress.section_index,
		DIFFERENTIAL_SECTION_TOTAL,
		differential_progress.section_name,
		differential_progress.test_index,
		differential_progress.test_total,
		differential_progress.global_index,
		differential_progress.global_total
	);
}

section_is_selected :: (selection: string, section: string, index: s64) -> bool {
	return !selection || selection == "all" || selection == section || selection == tprint("%", index);
}

prepare_differential_run :: (selection: string) -> bool {
	PADDING := "                            ";
	differential_progress = .{selection=selection};

	maxNameLen: int;
	for DIFFERENTIAL_SECTIONS {
		if it.name.count > maxNameLen {
			maxNameLen = it.name.count;
		}
	}

	for section, index: DIFFERENTIAL_SECTIONS {
		if selection == "list" {
			padding := string.{count=maxNameLen - section.name.count + 1, data=PADDING.data};
			print("\e[36m%\e[0m: %%(% tests)\n", FormatInt.{value=index + 1, minimum_digits=2, padding=32}, section.name, padding, FormatInt.{value=section.total, minimum_digits=3, padding=32});
			differential_progress.global_total += section.total;
		} else if section_is_selected(selection, section.name, index + 1) {
			differential_progress.global_total += section.total;
		}
	}

	if selection == "list" {
		print("%Total: % tests\n", PADDING, differential_progress.global_total);
		return false;
	}


	assert(differential_progress.global_total > 0, "Unknown section '%'.  Use '- list' to list sections.", selection);
	return true;
}

begin_differential_section :: (section: string, total: s64) -> bool {
	finish_differential_section();
	differential_progress.section_index += 1;
	differential_progress.section_name = section;
	differential_progress.test_index = 0;
	differential_progress.test_total = total;
	if differential_progress.planning {
		assert(differential_progress.section_index <= DIFFERENTIAL_SECTION_TOTAL);
		differential_progress.sections[differential_progress.section_index - 1] = .{name=section, total=total};
		return false;
	}


	differential_progress.section_enabled = section_is_selected(differential_progress.selection, section, differential_progress.section_index);
	return differential_progress.section_enabled;
}

finish_differential_section :: () {
	if differential_progress.planning || !differential_progress.section_enabled {
		return;
	}


	assert(differential_progress.test_depth == 0);
	assert(
		differential_progress.test_index == differential_progress.test_total,
		"Section '%' ran % tests, expected %.  Update its total.",
		differential_progress.section_name,
		differential_progress.test_index,
		differential_progress.test_total
	);
}

begin_differential_test :: () -> bool {
	if differential_progress.counting {
		differential_progress.test_total += 1;
		return false;
	}


	if differential_progress.test_depth == 0 {
		cleanup_differential_fixture();
		differential_progress.test_index += 1;
		differential_progress.global_index += 1;
		assert(differential_progress.test_index <= differential_progress.test_total, "Section '%' exceeded its total %.  Update its total.", differential_progress.section_name, differential_progress.test_total);
		print_differential_test();
	}

	differential_progress.test_depth += 1;
	return true;
}

finish_differential_test :: () {
	differential_progress.test_depth -= 1;
	if differential_progress.test_depth == 0 {
		print("%", CLEAR_PROGRESS_LINE);
	}
}

retain_differential_fixture :: () -> bool {
	if !differential_progress.fixture_source || differential_progress.fixture_path {
		return true;
	}


	path := differential_fixture_path();
	if !write_entire_file(path, differential_progress.fixture_source) {
		return false;
	}


	differential_progress.fixture_path = path;
	return true;
}

cleanup_differential_fixture :: () {
	if differential_progress.failed {
		return;
	}


	if differential_progress.fixture_path {
		file_delete(differential_progress.fixture_path);
	}
	differential_progress.fixture_path = "";
	differential_progress.fixture_source = "";
}

differential_fixture_path :: () -> string {
	serial := 1;
	path := tprint("jai_parser_differential_%_%_%.jai", differential_progress.section_index, differential_progress.test_index, serial);
	file, exists := file_open(path, log_errors=false);
	while exists {
		file_close(*file);
		serial += 1;
		path = tprint("jai_parser_differential_%_%_%.jai", differential_progress.section_index, differential_progress.test_index, serial);
		file, exists = file_open(path, log_errors=false);
	}

	return path;
}

main :: () {
	previous_assertion_handler = context.assertion_failed;
	context.assertion_failed = differential_assertion_failed;
	defer context.assertion_failed = previous_assertion_handler;

	if !prepare_differential_run(COMPILED_SECTION) {
		return;
	}


	for section, index: DIFFERENTIAL_SECTIONS {
		if index < DIFFERENTIAL_SECTION_TOTAL - 1 && section_is_selected(COMPILED_SECTION, section.name, index + 1) {
			differential_progress.global_index += section.total;
		}
	}

	differential_progress.section_index = DIFFERENTIAL_SECTION_TOTAL - 1;
	if !begin_differential_section("Runtime checks", RUNTIME_TEST_TOTAL) {
		return;
	}


	begin_differential_test();
	test_structural_difference_reporting();
	finish_differential_test();
	begin_differential_test();
	test_comparison_layers();
	finish_differential_test();
	begin_differential_test();
	assert_invalid_expression_compiler_message(
		"1 +",
		"Unable to parse an expression to the right of this binary operator."
	);
	finish_differential_test();
	begin_differential_test();
	test_compiler_related_diagnostics();
	finish_differential_test();
	begin_differential_test();
	test_asm_semantic_diagnostics();
	finish_differential_test();
	begin_differential_test();
	assert_trivia_round_trip(#string JAI
value /* comment */ + 42;
JAI
	);
	finish_differential_test();
	begin_differential_test();
	assert_trivia_round_trip(#string JAI
text :: #string END
body
END; // tail
JAI
	);
	finish_differential_test();
	begin_differential_test();
	test_differential_runner();
	finish_differential_test();
	finish_differential_section();
	cleanup_differential_fixture();
	assert(differential_progress.global_index == differential_progress.global_total);
	print("\e[92mPASS\e[0m %/% tests\n", differential_progress.global_index, differential_progress.global_total);
}

test_differential_runner :: () {
	previous_progress := differential_progress;
	defer differential_progress = previous_progress;

	assert(section_is_selected("1", DIFFERENTIAL_SECTIONS[0].name, 1));
	assert(section_is_selected("Runtime checks", DIFFERENTIAL_SECTIONS[DIFFERENTIAL_SECTION_TOTAL - 1].name, DIFFERENTIAL_SECTION_TOTAL));
	assert(!section_is_selected("1", "Runtime checks", DIFFERENTIAL_SECTION_TOTAL));
	assert(section_is_selected("all", "Runtime checks", DIFFERENTIAL_SECTION_TOTAL));
	assert(DIFFERENTIAL_SECTIONS[0].total == CONTEXT_TEST_TOTAL);
	assert(DIFFERENTIAL_SECTIONS[DIFFERENTIAL_SECTION_TOTAL - 1].total == RUNTIME_TEST_TOTAL);

	invalid_source :: "value :: ;";
	rejected := capture_compiler_error(invalid_source);
	assert(rejected.diagnostics.count > 0);
	compiler_path := differential_progress.fixture_path;
	differential_progress.failed = true;
	cleanup_differential_fixture();
	compiler_source, compiler_exists := read_entire_file(compiler_path, log_errors=false);
	defer free(compiler_source);

	assert(compiler_exists && compiler_source == invalid_source, "Completed diagnostic fixture was not retained for a caller failure.");
	assert(differential_fixture_path() != compiler_path, "A rerun would overwrite the retained diagnostic fixture.");
	differential_progress.failed = false;
	cleanup_differential_fixture();
	deleted_source, compiler_still_exists := read_entire_file(compiler_path, log_errors=false);
	defer free(deleted_source);

	assert(!compiler_still_exists, "Successful diagnostic fixture was not cleaned up.");

	workspace_source :: "fixture_retention :: 1;";
	differential_progress.fixture_source = workspace_source;
	assert(retain_differential_fixture(), "Unable to retain an in-memory workspace fixture.");
	workspace_path := differential_progress.fixture_path;
	differential_progress.failed = true;
	cleanup_differential_fixture();
	workspace_text, workspace_exists := read_entire_file(workspace_path, log_errors=false);
	defer free(workspace_text);

	assert(workspace_exists && workspace_text == workspace_source, "Workspace fixture snapshot was not retained.");
	assert(differential_fixture_path() != workspace_path, "A rerun would overwrite the retained workspace fixture.");
	differential_progress.failed = false;
	cleanup_differential_fixture();
}

capture_compiler_error :: (code: string, log_output := false) -> Compiler_Diagnostic_Result {
	begin_differential_test();
	cleanup_differential_fixture();
	fixture_path := differential_fixture_path();
	normalized_code, tab_count := replace(code, "\t", "    ");
	defer free(normalized_code);

	differential_progress.fixture_source = code;
	differential_progress.fixture_path = fixture_path;
	written := write_entire_file(fixture_path, normalized_code);
	assert(written, "Unable to write compiler diagnostic fixture '%'.", fixture_path);

	result: Compiler_Diagnostic_Result;
	result.process_result, result.standard_output, result.standard_error = run_command(
		"jai", "-x64", fixture_path,
		capture_and_return_output=true,
		print_captured_output=log_output
	);

	assert(result.process_result.type == .EXITED, "Compiler diagnostic fixture failed to run.");
	assert(result.process_result.exit_code != 0, "Compiler accepted invalid fixture:\n%", normalized_code);

	append_compiler_diagnostics(result.standard_error, *result.diagnostics);
	append_compiler_diagnostics(result.standard_output, *result.diagnostics);
	assert(result.diagnostics.count > 0, "Compiler failed without an Error diagnostic.\nstdout:\n%\nstderr:\n%", result.standard_output, result.standard_error);
	finish_differential_test();
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
	if marker_index < 0 {
		return false, .{}, "";
	}


	location_text := slice(line, 0, marker_index);
	comma_index := find_index_from_right(location_text, #char ",");
	if comma_index < 0 {
		return false, .{}, "";
	}


	line_prefix := slice(location_text, 0, comma_index);
	line_separator := find_index_from_right(line_prefix, #char ":");
	if line_separator < 0 {
		return false, .{}, "";
	}


	line_number, valid_line, line_remainder := string_to_int(advance(line_prefix, line_separator + 1), T=s64);
	column_number, valid_column, column_remainder := string_to_int(advance(location_text, comma_index + 1), T=s64);
	if !valid_line || line_remainder || !valid_column || column_remainder {
		return false, .{}, "";
	}


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

	code := tprint(#string JAI
main :: () {
    value := %;
}
JAI
	, source);
	assert_compiler_error_message(code, expected_message);
}

test_compiler_related_diagnostics :: () {
	result := capture_compiler_error(
		#string JAI
takes_integer :: (value: s64) {}
main :: () { takes_integer("text"); }
JAI,

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

assert_asm_semantic_error :: (instruction: string, expected_message: string) {
	source := tprint(#string JAI
main :: () {
    #asm { % }
}
JAI
	, instruction);
	parsed := Parser.parse_file(source);
	defer Parser.release_parser_tree(*parsed);

	assert(parsed.status == .COMPLETE && parsed.diagnostics.count == 0);
	asm_body := parsed.root.(*Parser.Parser_Block).statements[0].(*Parser.Parser_Declaration).expression.(*Parser.Parser_Procedure_Header).body_or_null.block;
	assert(asm_body.statements[0].(*Parser.Parser_Asm).statements[0].kind == .INSTRUCTION);

	result := capture_compiler_error(source);
	assert(result.diagnostics.count == 1);
	assert(result.diagnostics[0].location.l0 == 2 && result.diagnostics[0].location.c0 == 12);
	assert(result.diagnostics[0].location.c1 > result.diagnostics[0].location.c0);
	assert(starts_with(result.diagnostics[0].message, expected_message), "Unexpected compiler ASM diagnostic: %", result.diagnostics[0].message);
}

test_asm_semantic_diagnostics :: () {
	assert_asm_semantic_error("not_a_mnemonic;", "Invalid instruction mnemonic");
	assert_asm_semantic_error("mov.8 b3:, 256;", "A matching instruction form was not found.");
	assert_asm_semantic_error("add 1, 2;", "A matching instruction form was not found.");
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

test_context_modification_compiler_shape :: () {
	call := compiler_get_nodes(#code f(5, 10,, allocator = temp)).(*Code_Procedure_Call);
	assert(call.arguments_unsorted.count == 2);
	assert(call.context_modification != null);
	assert(call.context_modification.modification_expressions.count == 1);
	assert(call.context_modification.modification_expressions[0].kind == .BINARY_OPERATOR);
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
			add_normalized_field(result, path, "flags", tprint("%", call.flags));
			add_normalized_field(result, path, "argument_count", tprint("%", call.arguments_unsorted.count));
			add_normalized_field(result, path, "has_context_modification", tprint("%", call.context_modification != null));
			normalize_parser_node(call.procedure_expression, tprint("%.procedure", path), layer, result);
			for call.arguments_unsorted {
				argument_path := tprint("%.argument[%]", path, it_index);
				add_normalized_field(result, argument_path, "name", ifx it.name then it.name.name else "<positional>");
				normalize_parser_node(it.expression, tprint("%.expression", argument_path), layer, result);
			}

			if call.context_modification {
				add_normalized_field(result, path, "context_count", tprint("%", call.context_modification.modification_expressions.count));
				for call.context_modification.modification_expressions {
					normalize_parser_node(it, tprint("%.context[%]", path, it_index), layer, result);
				}
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
			add_normalized_field(result, path, "assertion_string", directive.assertion_string);
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
			if layer == .SEMANTIC {
				add_normalized_field(result, path, "name", header.name);
			}

			add_normalized_field(result, path, "foreign_name", header.foreign_function_name);
			add_normalized_field(result, path, "library", ifx header.library_identifier then header.library_identifier.name else "");
			add_normalized_field(result, path, "deprecated", header.deprecation_string);
			add_normalized_field(result, path, "using_count", tprint("%", header.parameter_usings.count));
			for header.parameter_usings {
				using_path := tprint("%.using[%]", path, it_index);
				add_normalized_field(result, using_path, "filter_type", tprint("%", it.filter_type));
				add_normalized_field(result, using_path, "no_parameters", tprint("%", it.no_parameters));
				normalize_parser_node(it.filter_expression, tprint("%.filter", using_path), layer, result);
			}

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

			for header.returns {
				normalize_parser_node(it, tprint("%.return[%]", path, it_index), layer, result);
			}

			for header.modify_directives {
				normalize_parser_node(it, tprint("%.modify[%]", path, it_index), layer, result);
			}

		case .PROCEDURE_BODY;
			body := node.(*Parser.Parser_Procedure_Body);
			normalize_parser_node(body.block, tprint("%.block", path), layer, result);

		case .STRUCT;
			aggregate := node.(*Parser.Parser_Struct);
			add_normalized_field(result, path, "flags", tprint("%", aggregate.textual_flags));
			add_normalized_field(result, path, "note_count", tprint("%", aggregate.notes.count));
			for aggregate.notes {
				add_normalized_field(result, tprint("%.note[%]", path, it_index), "text", it.text);
			}

			add_normalized_field(result, path, "modify_count", tprint("%", aggregate.modify_directives.count));
			for aggregate.modify_directives {
				normalize_parser_node(it, tprint("%.modify[%]", path, it_index), layer, result);
			}

			normalize_parser_node(aggregate.block, tprint("%.block", path), layer, result);

		case .ENUM;
			aggregate := node.(*Parser.Parser_Enum);
			add_normalized_field(result, path, "flags", tprint("%", aggregate.is_flags));
			add_normalized_field(result, path, "complete", tprint("%", aggregate.marked_as_complete));
			add_normalized_field(result, path, "specified", tprint("%", aggregate.marked_as_specified));
			add_normalized_field(result, path, "note_count", tprint("%", aggregate.notes.count));
			for aggregate.notes {
				add_normalized_field(result, tprint("%.note[%]", path, it_index), "text", it.text);
			}

			normalize_parser_node(aggregate.internal_type_inst, tprint("%.internal_type", path), layer, result);
			normalize_parser_node(aggregate.block, tprint("%.block", path), layer, result);

		case .DECLARATION;
			declaration := node.(*Parser.Parser_Declaration);
			normalize_parser_declaration(declaration, path, layer, result);

		case .COMPOUND_DECLARATION;
			declaration := node.(*Parser.Parser_Compound_Declaration);
			add_normalized_field(result, path, "argument_count", tprint("%", declaration.comma_separated_assignment.arguments.count));
			for declaration.comma_separated_assignment.arguments {
				add_normalized_field(result, tprint("%.argument[%]", path, it_index), "modifier", tprint("%", it.modifier));
				normalize_parser_node(it.node, tprint("%.argument[%]", path, it_index), layer, result);
			}

			normalize_parser_declaration(declaration.declaration_properties, tprint("%.properties", path), layer, result);
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
			for block.statements {
				normalize_parser_node(it, tprint("%.statement[%]", path, it_index), layer, result);
			}

		case .RETURN;
			return_node := node.(*Parser.Parser_Return);
			add_normalized_field(result, path, "backticked", tprint("%", (return_node.return_flags & .IS_BACKTICKED) != 0));
			add_normalized_field(result, path, "quick", tprint("%", (return_node.return_flags & .AUTO_INSERTED_FOR_QUICK_LAMBDA) != 0));
			add_normalized_field(result, path, "argument_count", tprint("%", return_node.arguments_unsorted.count));
			for return_node.arguments_unsorted {
				normalize_parser_node(it.expression, tprint("%.argument[%]", path, it_index), layer, result);
			}

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
			normalize_parser_node(for_node.want_replacement_for_expansion, tprint("%.selector", path), layer, result);
			normalize_parser_node(for_node.want_pointer_expression, tprint("%.pointer_flag", path), layer, result);
			normalize_parser_node(for_node.want_reverse_expression, tprint("%.reverse_flag", path), layer, result);
			normalize_parser_node(for_node.ident_it, tprint("%.iterator", path), layer, result);
			normalize_parser_node(for_node.ident_it_index, tprint("%.index", path), layer, result);
			normalize_parser_node(for_node.iteration_expression, tprint("%.iteration", path), layer, result);
			normalize_parser_node(for_node.iteration_expression_right, tprint("%.iteration_right", path), layer, result);
			normalize_parser_node(for_node.block, tprint("%.block", path), layer, result);

		case .IF;
			if_node := node.(*Parser.Parser_If);
			add_normalized_field(result, path, "switch", tprint("%", (if_node.if_flags & .IS_SWITCH_STATEMENT) != 0));
			add_normalized_field(result, path, "ifx", tprint("%", (if_node.if_flags & .IS_IFX) != 0));
			add_normalized_field(result, path, "static", tprint("%", (if_node.if_flags & .IS_STATIC) != 0));
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
		case .DIRECTIVE_THIS;
		case .PLACEHOLDER;
		case .ASM;

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
			add_normalized_field(result, path, "flags", tprint("%", call.flags));
			add_normalized_field(result, path, "argument_count", tprint("%", call.arguments_unsorted.count));
			add_normalized_field(result, path, "has_context_modification", tprint("%", call.context_modification != null));
			normalize_node(call.procedure_expression, tprint("%.procedure", path), layer, result);
			for call.arguments_unsorted {
				argument_path := tprint("%.argument[%]", path, it_index);
				add_normalized_field(result, argument_path, "name", ifx it.name then it.name.name else "<positional>");
				normalize_node(it.expression, tprint("%.expression", argument_path), layer, result);
			}

			if call.context_modification {
				add_normalized_field(result, path, "context_count", tprint("%", call.context_modification.modification_expressions.count));
				for call.context_modification.modification_expressions {
					normalize_node(it, tprint("%.context[%]", path, it_index), layer, result);
				}
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
			add_normalized_field(result, path, "assertion_string", directive.assertion_string);
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
			if layer == .SEMANTIC {
				add_normalized_field(result, path, "name", header.name);
			}

			add_normalized_field(result, path, "foreign_name", header.foreign_function_name);
			add_normalized_field(result, path, "library", ifx header.library_identifier then header.library_identifier.name else "");
			add_normalized_field(result, path, "deprecated", header.deprecation_string);
			add_normalized_field(result, path, "using_count", tprint("%", header.parameter_usings.count));
			for header.parameter_usings {
				using_path := tprint("%.using[%]", path, it_index);
				add_normalized_field(result, using_path, "filter_type", tprint("%", it.filter_type));
				add_normalized_field(result, using_path, "no_parameters", tprint("%", it.no_parameters));
				normalize_node(it.filter_expression, tprint("%.filter", using_path), layer, result);
			}

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

			for header.returns {
				normalize_node(it, tprint("%.return[%]", path, it_index), layer, result);
			}

			for header.modify_directives {
				normalize_node(it, tprint("%.modify[%]", path, it_index), layer, result);
			}

		case .PROCEDURE_BODY;
			body := node.(*Code_Procedure_Body);
			normalize_node(body.block, tprint("%.block", path), layer, result);

		case .STRUCT;
			aggregate := node.(*Code_Struct);
			add_normalized_field(result, path, "flags", tprint("%", aggregate.textual_flags));
			add_normalized_field(result, path, "note_count", tprint("%", aggregate.notes.count));
			for aggregate.notes {
				add_normalized_field(result, tprint("%.note[%]", path, it_index), "text", it.text);
			}

			add_normalized_field(result, path, "modify_count", tprint("%", aggregate.modify_directives.count));
			for aggregate.modify_directives {
				normalize_node(it, tprint("%.modify[%]", path, it_index), layer, result);
			}

			normalize_node(aggregate.block, tprint("%.block", path), layer, result);

		case .ENUM;
			aggregate := node.(*Code_Enum);
			add_normalized_field(result, path, "flags", tprint("%", aggregate.is_flags));
			add_normalized_field(result, path, "complete", tprint("%", aggregate.marked_as_complete));
			add_normalized_field(result, path, "specified", tprint("%", aggregate.marked_as_specified));
			add_normalized_field(result, path, "note_count", tprint("%", aggregate.notes.count));
			for aggregate.notes {
				add_normalized_field(result, tprint("%.note[%]", path, it_index), "text", it.text);
			}

			normalize_node(aggregate.internal_type_inst, tprint("%.internal_type", path), layer, result);
			normalize_node(aggregate.block, tprint("%.block", path), layer, result);

		case .DECLARATION;
			declaration := node.(*Code_Declaration);
			normalize_declaration(declaration, path, layer, result);

		case .COMPOUND_DECLARATION;
			declaration := node.(*Code_Compound_Declaration);
			add_normalized_field(result, path, "argument_count", tprint("%", declaration.comma_separated_assignment.arguments.count));
			for declaration.comma_separated_assignment.arguments {
				add_normalized_field(result, tprint("%.argument[%]", path, it_index), "modifier", tprint("%", it.modifier));
				normalize_node(it.node, tprint("%.argument[%]", path, it_index), layer, result);
			}

			normalize_declaration(declaration.declaration_properties, tprint("%.properties", path), layer, result);
			normalize_node(declaration.alignment_expression, tprint("%.alignment", path), layer, result);
			add_normalized_field(result, path, "note_count", tprint("%", declaration.notes.count));
			for declaration.notes {
				add_normalized_field(result, tprint("%.note[%]", path, it_index), "text", it.text);
			}

		case .COMMA_SEPARATED_ARGUMENTS;
			arguments := node.(*Code_Comma_Separated_Arguments);
			add_normalized_field(result, path, "argument_count", tprint("%", arguments.arguments.count));
			for arguments.arguments {
				normalize_node(it.node, tprint("%.argument[%]", path, it_index), layer, result);
			}

		case .NOTE;
			add_normalized_field(result, path, "text", node.(*Code_Note).text);

		case .BLOCK;
			block := node.(*Code_Block);
			add_normalized_field(result, path, "block_type", tprint("%", block.block_type));
			add_normalized_field(result, path, "statement_count", tprint("%", block.statements.count));
			for block.statements {
				normalize_node(it, tprint("%.statement[%]", path, it_index), layer, result);
			}

		case .RETURN;
			return_node := node.(*Code_Return);
			add_normalized_field(result, path, "backticked", tprint("%", (return_node.return_flags & .IS_BACKTICKED) != 0));
			add_normalized_field(result, path, "quick", tprint("%", (return_node.return_flags & .AUTO_INSERTED_FOR_QUICK_LAMBDA) != 0));
			add_normalized_field(result, path, "argument_count", tprint("%", return_node.arguments_unsorted.count));
			for return_node.arguments_unsorted {
				normalize_node(it.expression, tprint("%.argument[%]", path, it_index), layer, result);
			}

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
			normalize_node(for_node.want_replacement_for_expansion, tprint("%.selector", path), layer, result);
			normalize_node(for_node.want_pointer_expression, tprint("%.pointer_flag", path), layer, result);
			normalize_node(for_node.want_reverse_expression, tprint("%.reverse_flag", path), layer, result);
			normalize_node(for_node.ident_it, tprint("%.iterator", path), layer, result);
			normalize_node(for_node.ident_it_index, tprint("%.index", path), layer, result);
			normalize_node(for_node.iteration_expression, tprint("%.iteration", path), layer, result);
			normalize_node(for_node.iteration_expression_right, tprint("%.iteration_right", path), layer, result);
			normalize_node(for_node.block, tprint("%.block", path), layer, result);

		case .IF;
			if_node := node.(*Code_If);
			add_normalized_field(result, path, "switch", tprint("%", (if_node.if_flags & .IS_SWITCH_STATEMENT) != 0));
			add_normalized_field(result, path, "ifx", tprint("%", (if_node.if_flags & .IS_IFX) != 0));
			add_normalized_field(result, path, "static", tprint("%", (if_node.if_flags & .IS_STATIC) != 0));
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
		case .DIRECTIVE_THIS;
		case .PLACEHOLDER;
		case .ASM;

		case;
			add_normalized_field(result, path, "unsupported", "true");
	}
}

normalize_parser_declaration :: (declaration: *Parser.Parser_Declaration, path: string, layer: Comparison_Layer, result: *Normalized_Tree) {
	add_normalized_field(result, path, "name", declaration.name);
	add_normalized_field(result, path, "constant", tprint("%", (declaration.flags & .IS_CONSTANT) != 0));
	add_normalized_field(result, path, "as", tprint("%", (declaration.flags & .IS_MARKED_AS_AS) != 0));
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
	add_normalized_field(result, path, "as", tprint("%", (declaration.flags & .IS_MARKED_AS_AS) != 0));
	add_normalized_field(result, path, "uninitialized", tprint("%", (declaration.flags & .IS_UNINITIALIZED) != 0));
	add_normalized_field(result, path, "auto_bake", tprint("%", (declaration.flags & .AUTO_VALUE_BAKE) != 0));
	add_normalized_field(result, path, "auto_bake_required", tprint("%", (declaration.flags & .AUTO_VALUE_BAKE_IS_REQUIRED) != 0));
	add_normalized_field(result, path, "scope_modifier", tprint("%", (declaration.flags & .HAS_SCOPE_MODIFIER) != 0));
	normalize_node(declaration.type_inst, tprint("%.type", path), layer, result);
	normalize_node(declaration.expression, tprint("%.expression", path), layer, result);
	normalize_node(declaration.alignment_expression, tprint("%.alignment", path), layer, result);
	add_normalized_field(result, path, "note_count", tprint("%", declaration.notes.count));
	for declaration.notes {
		add_normalized_field(result, tprint("%.note[%]", path, it_index), "text", it.text);
	}
}

add_normalized_field :: (tree: *Normalized_Tree, path: string, name: string, value: string) {
	array_add(*tree.fields, .{path=tprint("%.%", path, name), value=value});
}

find_normalized_field :: (fields: [] Normalized_Field, path: string) -> *Normalized_Field {
	for * fields {
		if it.path == path {
			return it;
		}
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

assert_expression_matches_code :: (source: string, expected_code: Code, layer := Comparison_Layer.SYNTAX, fully_pathed_filename: string = "") {
	if !begin_differential_test() {
		return;
	}


	differential_progress.fixture_source = source;
	parsed := Parser.parse_expression(source, fully_pathed_filename);
	defer Parser.release_parser_tree(*parsed);

	assert(parsed.status == .COMPLETE, "Parser did not complete fixture '%'.", source);

	actual := normalize_parser_tree(parsed.root, layer);
	expected := normalize_tree(compiler_get_nodes(expected_code), layer);
	difference := compare_normalized_trees(actual, expected);
	assert(!difference.differences.count, "AST mismatch for '%':\n%", source, format_structural_differences(difference));
	finish_differential_test();
}

assert_expression_fixture :: ($source: string, $layer := Comparison_Layer.SYNTAX) #expand {
	#insert -> string {
		return tprint("assert_expression_matches_code(source, (#code %), layer);", source);
	}
}

assert_statement_matches_code :: (source: string, expected_code: Code, file_scope := false) {
	if !begin_differential_test() {
		return;
	}


	differential_progress.fixture_source = source;
	parsed := ifx file_scope then Parser.parse_file(source) else Parser.parse_block(tprint("{ % }", source));
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
	finish_differential_test();
}

assert_statement_fixture :: ($source: string) #expand {
	#insert -> string {
		return tprint("assert_statement_matches_code(source, #code { % });", source);
	}
}

assert_asm_block_shape :: (parsed: *Parser.Parsed_Source, actual_block: *Parser.Parser_Block, expected_block: *Code_Block, actual_origin: *Parser.Parser_Block, expected_origin: *Code_Block, index: s64) {
	assert(actual_block.statements.count == expected_block.statements.count);
	actual_asm := actual_block.statements[index].(*Parser.Parser_Asm);
	expected_asm := expected_block.statements[index].(*Code_Asm);
	assert(actual_asm.enclosing_scope == actual_block);
	assert(actual_asm.kind == expected_asm.kind);
	// Compiler branch blocks anchor after '{', so compare directive starts from the shared outer block.
	assert(actual_asm.l0 - actual_origin.l0 == expected_asm.l0 - expected_origin.l0);
	if actual_asm.l0 == actual_origin.l0 {
		assert(actual_asm.c0 - actual_origin.c0 == expected_asm.c0 - expected_origin.c0);
	} else {
		assert(actual_asm.c0 == expected_asm.c0);
	}

	// Code_Asm ends at '#asm'; Parser_Asm deliberately spans the entire assembly block.
	assert(expected_asm.l1 - expected_asm.l0 == Parser.token_at(parsed, actual_asm.first_token + 1).l1 - actual_asm.l0);
	assert(expected_asm.c1 - expected_asm.c0 == Parser.token_at(parsed, actual_asm.first_token + 1).c1 - actual_asm.c0);
	assert(actual_asm.l1 >= actual_asm.l0 && actual_asm.c1 > actual_asm.c0);
}

assert_asm_compiler_shape :: (source: string, expected_code: Code) {
	if !begin_differential_test() {
		return;
	}


	differential_progress.fixture_source = source;
	parsed := Parser.parse_block(source);
	defer Parser.release_parser_tree(*parsed);

	assert(parsed.status == .COMPLETE);
	actual_block := parsed.root.(*Parser.Parser_Block);
	expected_block := compiler_get_nodes(expected_code).(*Code_Block);
	assert_asm_block_shape(*parsed, actual_block, expected_block, actual_block, expected_block, 0);
	finish_differential_test();
}

assert_nested_asm_compiler_shape :: (source: string, expected_code: Code) {
	if !begin_differential_test() {
		return;
	}


	differential_progress.fixture_source = source;
	parsed := Parser.parse_block(source);
	defer Parser.release_parser_tree(*parsed);

	assert(parsed.status == .COMPLETE);
	actual_root := parsed.root.(*Parser.Parser_Block);
	expected_root := compiler_get_nodes(expected_code).(*Code_Block);
	assert(actual_root.statements.count == 1 && expected_root.statements.count == 1);
	actual_if := actual_root.statements[0].(*Parser.Parser_If);
	expected_if := expected_root.statements[0].(*Code_If);
	assert_asm_block_shape(*parsed, actual_if.then_block, expected_if.then_block, actual_root, expected_root, 0);
	assert_asm_block_shape(*parsed, actual_if.else_block, expected_if.else_block, actual_root, expected_root, 0);
	finish_differential_test();
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
	differential_progress.fixture_source = source;
	parsed := Parser.materialise_tokens(source);
	reconstructed := Parser.reconstruct_source(*parsed);
	assert(reconstructed == source, "Trivia round trip differed for source:\n%", source);
}

run_typechecked_workspace_fixture :: (source: string, expected_declaration: string) -> Workspace_Fixture_Result {
	begin_differential_test();
	differential_progress.fixture_source = source;
	result: Workspace_Fixture_Result;
	workspace := compiler_create_workspace("Jai_Parser differential fixture");
	assert(cast(bool) workspace, "Unable to create differential fixture workspace.");

	options := get_build_options(workspace);
	copy_commonly_propagated_fields(get_build_options(), *options);
	options.output_type = .NO_OUTPUT;
	options.write_added_strings = false;
	set_build_options(options, workspace);

	compiler_begin_intercept(workspace);
	add_build_string(source, workspace);

	while true {
		message := compiler_wait_for_message();
		if message.workspace != workspace {
			continue;
		}


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
	finish_differential_test();
	return result;
}

test_typechecked_workspace_fixture :: () {
	if !begin_differential_section("Typechecked workspace", TYPECHECKED_TEST_TOTAL) {
		return;
	}


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

assert_overload_workspace_fixture :: (first_parameters: string, second_parameters: string, expression: string, expected_index: s64, expected_declaration: string, third_parameters: string = "", setup: string = "") {
	OVERLOAD_FIELD_SOURCE :: #string JAI
Child :: struct {
	Clear: s64;
}
Other :: struct {
	PushMatrix: s64;
}
make :: (%) -> % {
	return .{1};
}
make :: (%) -> % {
	return .{1};
}
%
% :: () -> s64 {
	%
	return %;
}
JAI;
	assert(expected_index == 0 || expected_index == 1 || expected_index == 2 && third_parameters);
	first_result := ifx expected_index == 0 then "Child" else "Other";
	second_result := ifx expected_index == 1 then "Child" else "Other";
	third_source := "";
	if third_parameters {
		third_result := ifx expected_index == 2
			then "Child"
			else "Other";
		third_source = tprint("make :: (%) -> % { return .{1}; }", third_parameters, third_result);
	}

	source := tprint(OVERLOAD_FIELD_SOURCE, first_parameters, first_result, second_parameters, second_result, third_source, expected_declaration, setup, expression);
	assert_file_workspace_fixture(source, expected_declaration);
}

assert_multi_candidate_workspace_fixture :: (parameters: []string, arguments: string, selected_index: s64) {
	source := make_multi_candidate_rank_source(parameters, arguments, selected_index);
	if selected_index < 0 {
		rejected := capture_compiler_error(source);
		assert(rejected.diagnostics.count > 0);
	} else {
		assert_file_workspace_fixture(source, "fixture_multi_candidate_rank");
	}

}

test_file_workspace_fixtures :: () {
	if !begin_differential_section("File scopes", FILE_SCOPE_TEST_TOTAL) {
		return;
	}


	for scope_name: string.["file", "export", "module"] {
		declaration_name := tprint("fixture_%_scope", scope_name);
		assert_file_workspace_fixture(tprint("#scope_%\n% :: 1;", scope_name, declaration_name), declaration_name);
	}
}

test_typed_integer_fixtures :: () {
	typed_integer_cases := make_typed_integer_cases();
	defer array_free(typed_integer_cases);

	if !begin_differential_section("Typed integer conversions", typed_integer_cases.count * 2) {
		return;
	}


	for fixture: typed_integer_cases {
		for order: 0..1 {
			first := ifx order == 0
				then fixture.parameter_type
				else fixture.rival_type;
			second := ifx order == 0
				then fixture.rival_type
				else fixture.parameter_type;
			if fixture.compiler_accepts {
				assert_overload_workspace_fixture(tprint("value: %", first), tprint("value: %", second), tprint("make(%).Clear", fixture.argument), order, "fixture_typed_integer", setup=fixture.setup);
			} else {
				rejected := capture_compiler_error(tprint(TYPED_INTEGER_OVERLOAD_SOURCE, first, second, fixture.setup, fixture.argument));
				assert(rejected.diagnostics.count > 0);
			}
		}
	}

}

test_assembly_context_fixtures :: () {
	if !begin_differential_section("Assembly and context", ASSEMBLY_CONTEXT_TEST_TOTAL) {
		return;
	}


	assert_file_workspace_fixture("#no_reset fixture_no_reset: s64;", "fixture_no_reset");
	assert_file_workspace_fixture("fixture_asm_registers :: () { #asm { mov apple:, 10; mov signed:, -10; banana: gpr; mov w: gpr === 15, 10; } }", "fixture_asm_registers");
	assert_file_workspace_fixture("fixture_asm_pinning :: () { #asm { a: gpr === 9; t: gpr === a; x: gpr; x === a; } }", "fixture_asm_pinning");
	assert_file_workspace_fixture("fixture_asm_memory :: () { #asm { mov base:, 10; mov loaded:, [base]; } }", "fixture_asm_memory");
	assert_file_workspace_fixture("fixture_asm_value :: () { CONSTANT :: 10; #asm { mov destination:, CONSTANT; } }", "fixture_asm_value");
	assert_file_workspace_fixture("fixture_asm_macro :: (register_param: __reg) #expand { #asm { mov register_param, 10; } }", "fixture_asm_macro");
	assert_file_workspace_fixture("fixture_asm_immediates :: () { #asm { mov.8 byte_max:, 255; mov.8 byte_negative:, -127; } }", "fixture_asm_immediates");
	assert_file_workspace_fixture(
		#string JAI
#add_context fixture_context_value: s64;
fixture_add_context :: 1;
JAI,

		"fixture_add_context"
	);
}

test_pair_member_fixtures :: () {
	if !begin_differential_section("Pair members", PAIR_MEMBER_CASES.count) {
		return;
	}


	for fixture: PAIR_MEMBER_CASES {
		body := tprint("%\n\treturn %.Clear;", fixture.setup, fixture.receiver);
		header := tprint("% :: (%) -> s64", fixture.declaration_name, fixture.parameters);
		source := tprint(PAIR_MEMBER_SOURCE, fixture.extra_declarations, header, body);
		assert_file_workspace_fixture(source, fixture.declaration_name);
	}
}

test_member_query_fixtures :: () {
	if !begin_differential_section("Member queries", MEMBER_QUERY_TEST_TOTAL) {
		return;
	}


	assert_file_workspace_fixture(
		#string JAI
#assert true;
fixture_assert_scope :: 1;
JAI,

		"fixture_assert_scope"
	);
	assert_file_workspace_fixture(
		#string JAI
Fixture_Procs :: struct { Clear: s64; }
fixture_make :: () -> Fixture_Procs { return .{Clear=1}; }
fixture_alias_field :: () -> s64 {
	make_alias :: fixture_make;
	value := make_alias();
	return value.Clear;
}
JAI,

		"fixture_alias_field"
	);
	assert_file_workspace_fixture(
		#string JAI
Fixture_Procs :: struct { Clear: s64; }
fixture_query_field :: () -> s64 {
	original := Fixture_Procs.{Clear=1};
	value: type_of(original) = original;
	return value.Clear;
}
JAI,

		"fixture_query_field"
	);
}

test_member_access_fixtures :: () {
	Member_Access_Case :: struct {
		declaration_name: string;
		setup: string = "";
		expression: string;
	}

	member_access_cases := Member_Access_Case.[
		.{declaration_name = "fixture_member_type", expression = "Container.{Nested=Child.{Clear=1}}.Nested.Clear"},
		.{"fixture_typed_member", "container: Container = .{Nested=Child.{Clear=1}};", "container.Nested.Clear"},
		.{"fixture_inferred_member", "container := Container.{Nested=Child.{Clear=1}};", "container.Nested.Clear"},
		.{"fixture_aliased_member", "original := Container.{Nested=Child.{Clear=1}};\n\tcontainer := original;", "container.Nested.Clear"},
	];
	if !begin_differential_section("Member access", member_access_cases.count) {
		return;
	}


	for fixture: member_access_cases {
		body := tprint("%\n\treturn %;", fixture.setup, fixture.expression);
		source := tprint(CONTAINER_MEMBER_SOURCE, "", tprint("% :: () -> s64", fixture.declaration_name), body);
		assert_file_workspace_fixture(source, fixture.declaration_name);
	}

}

test_default_overload_fixtures :: () {
	if !begin_differential_section("Overloads and defaults", DEFAULT_OVERLOAD_TEST_TOTAL) {
		return;
	}


	assert_file_workspace_fixture(tprint(CONTAINER_MEMBER_SOURCE, tprint(CONTAINER_MAKER_SOURCE, ""), "fixture_called_member :: () -> s64", "return make().Nested.Clear;"), "fixture_called_member");
	assert_file_workspace_fixture(
		#string JAI
Fixture_Input :: struct { Value: s64; }
Fixture_Alternate :: struct { Value: s64; }
Fixture_Child :: struct { Clear: s64; }
Fixture_Other :: struct { PushMatrix: s64; }
fixture_make :: (input: Fixture_Input) -> Fixture_Child { return .{Clear=1}; }
fixture_make :: (input: Fixture_Alternate) -> Fixture_Other { return .{PushMatrix=1}; }
fixture_overloaded_member :: () -> s64 { return fixture_make(Fixture_Input.{Value=1}).Clear; }
JAI,

		"fixture_overloaded_member"
	);
	DEFAULTED_MEMBER_SOURCE :: #string JAI
Fixture_Input :: struct {
	Value: s64;
}
Fixture_Child :: struct {
	Clear: s64;
}
Fixture_Other :: struct {
	PushMatrix: s64;
}
fixture_make :: (input: Fixture_Input, enabled: bool = true) -> Fixture_Child {
	return .{Clear=1};
}
fixture_make :: (input: Fixture_Input, required: string) -> Fixture_Other {
	return .{PushMatrix=1};
}
% :: () -> s64 {
	return fixture_make(%).Clear;
}
JAI;

	for argument, index: string.["input=Fixture_Input.{Value=1}", "Fixture_Input.{Value=1}"] {
		declaration_name := string.["fixture_defaulted_overload", "fixture_positional_default"][index];
		assert_file_workspace_fixture(tprint(DEFAULTED_MEMBER_SOURCE, declaration_name, argument), declaration_name);
	}

	missing_overload_argument := capture_compiler_error(
		#string JAI
Child :: struct { Clear: s64; }
make :: (input: s64, required: string) -> Child { return .{Clear=1}; }
main :: () { return make(input=1).Clear; }
JAI
	);
	assert(missing_overload_argument.diagnostics.count > 0);
	unresolved_default := capture_compiler_error(
		#string JAI
Child :: struct { Clear: s64; }
make :: (input: s64, enabled: bool = Missing) -> Child { return .{Clear=1}; }
main :: () { return make(1).Clear; }
JAI
	);
	assert(unresolved_default.diagnostics.count > 0);
	assert_overload_workspace_fixture("value: s64", "value: string", "make(1).Clear", 0, "fixture_primitive_overload");
	assert_overload_workspace_fixture("value: float64", "value: s64", "make(1).Clear", 1, "fixture_exact_rank");
	assert_overload_workspace_fixture("value: float64", "value: string", "make(1).Clear", 0, "fixture_converted_rank");
	assert_overload_workspace_fixture("value: float64", "value: string", "make(1.5).Clear", 0, "fixture_float_rank");

}

test_floating_literal_fixtures :: () {
	if !begin_differential_section("Floating literals", FLOAT_LITERAL_CASES.count * 4) {
		return;
	}


	for fixture: FLOAT_LITERAL_CASES {
		expression := tprint("make(%).Clear", fixture.value);
		assert_overload_workspace_fixture("value: float64", "value: string", expression, 0, "fixture_float64_literal");
		if fixture.float32_compatible {
			assert_overload_workspace_fixture("value: float32", "value: string", expression, 0, "fixture_float32_literal");
		} else {
			rejected := capture_compiler_error(tprint(UNARY_OVERLOAD_SOURCE, "float32", "string", fixture.value));
			assert(rejected.diagnostics.count > 0, "Compiler accepted float32-incompatible literal %.", fixture.value);
		}

		preferred_index := ifx fixture.preferred_type == "float32" then 0 else 1;
		assert_overload_workspace_fixture("value: float32", "value: float64", expression, preferred_index, "fixture_float_preference");
		assert_overload_workspace_fixture("value: float64", "value: float32", expression, 1 - preferred_index, "fixture_float_reverse_preference");
	}

}

test_integer_float32_fixtures :: () {
	if !begin_differential_section("Integer to float32", INTEGER_FLOAT32_VALUES.count * 5) {
		return;
	}


	for value: INTEGER_FLOAT32_VALUES {
		expression := tprint("make(%).Clear", value);
		assert_overload_workspace_fixture("value: float32", "value: string", expression, 0, "fixture_integer_float32");
		assert_overload_workspace_fixture("value: float32", "value: s64", expression, 1, "fixture_integer_float32_rank");
		assert_overload_workspace_fixture("value: s64", "value: float32", expression, 0, "fixture_integer_float32_reverse_rank");
		assert_overload_workspace_fixture("value: float32", "value: float64", expression, 0, "fixture_integer_float_width_rank");
		assert_overload_workspace_fixture("value: float64", "value: float32", expression, 1, "fixture_integer_float_width_reverse_rank");
	}

}

test_integer_rounding_fixture :: () {
	if !begin_differential_section("Integer float32 rounding", INTEGER_ROUNDING_TEST_TOTAL) {
		return;
	}


	assert_file_workspace_fixture(
		#string JAI
#import "Basic";
fixture_integer_float32_rounding :: () {
	rounded: float32 = 16777217;
	assert(cast(s64) rounded == 16777216);
}
#run fixture_integer_float32_rounding();
JAI,
		"fixture_integer_float32_rounding"
	);

}

test_numeric_rank_fixtures :: () {
	numeric_rank_cases := make_numeric_rank_cases();
	defer array_free(numeric_rank_cases);

	if !begin_differential_section("Numeric rankings", numeric_rank_cases.count * 2) {
		return;
	}


	for fixture: numeric_rank_cases {
		for order: 0..1 {
			first := ifx order == 0
				then fixture.first_parameters
				else fixture.second_parameters;
			second := ifx order == 0
				then fixture.second_parameters
				else fixture.first_parameters;

			if fixture.selected_index < 0 {
				source := ifx fixture.third_parameters
					then tprint(THREE_ARGUMENT_RANK_SOURCE, first, second, fixture.third_parameters, fixture.arguments)
					else tprint(MULTI_ARGUMENT_RANK_SOURCE, first, second, fixture.arguments);
				ambiguous := capture_compiler_error(source);
				assert(ambiguous.diagnostics.count > 0);
			} else {
				selected_index := ifx order == 0 || fixture.selected_index == 2
					then fixture.selected_index
					else 1 - fixture.selected_index;

				assert_overload_workspace_fixture(first, second, tprint("make(%).Clear", fixture.arguments), selected_index, "fixture_numeric_conversion_rank", fixture.third_parameters);
			}

		}
	}

}

test_candidate_permutation_fixtures :: () {
	candidate_permutations_total: s64;
	for fixture: MULTI_CANDIDATE_RANK_CASES {
		permutation_count := 1;
		for factor: 1..fixture.parameters.count {
			permutation_count *= factor;
		}

		candidate_permutations_total += permutation_count;
	}

	if !begin_differential_section("Candidate permutations", candidate_permutations_total) {
		return;
	}


	check_multi_candidate_rank_cases(assert_multi_candidate_workspace_fixture);
}

test_invalid_integer_fixtures :: () {
	signed64_boundary := SIGNED_BOUNDARY_CASES[SIGNED_BOUNDARY_CASES.count - 1];
	unsigned64_boundary := UNSIGNED_BOUNDARY_CASES[UNSIGNED_BOUNDARY_CASES.count - 1];
	if !begin_differential_section("Invalid integer limits", UNSIGNED_BOUNDARY_CASES.count * 4) {
		return;
	}


	for unsigned: UNSIGNED_BOUNDARY_CASES {
		for value: string.[signed64_boundary.below, unsigned64_boundary.above] {
			for order: 0..1 {
				first := ifx order == 0
					then signed64_boundary.parameter_type
					else unsigned.parameter_type;
				second := ifx order == 0
					then unsigned.parameter_type
					else signed64_boundary.parameter_type;
				rejected := capture_compiler_error(tprint(UNARY_OVERLOAD_SOURCE, first, second, value));
				assert(rejected.diagnostics.count > 0, "Compiler accepted invalid mixed %/% literal %.", first, second, value);
			}
		}
	}

}

test_unsigned_boundary_fixtures :: () {
	if !begin_differential_section("Unsigned boundaries", UNSIGNED_BOUNDARY_CASES.count * 14 + UNSIGNED_NEGATIVE_VALUES.count * 3) {
		return;
	}


	for fixture: UNSIGNED_BOUNDARY_CASES {
		for value: string.["0", "-0", "1", fixture.upper] {
			expression := tprint("make(%).Clear", value);
			parameter := tprint("value: %", fixture.parameter_type);
			assert_overload_workspace_fixture(parameter, "value: string", expression, 0, "fixture_unsigned_bounds");
			assert_overload_workspace_fixture(parameter, "value: s64", expression, 1, "fixture_unsigned_rank");
			assert_overload_workspace_fixture("value: s64", parameter, expression, 0, "fixture_unsigned_reverse_rank");
		}

		for value: string.["-1", fixture.above] {
			rejected := capture_compiler_error(tprint(UNARY_OVERLOAD_SOURCE, fixture.parameter_type, "string", value));
			assert(rejected.diagnostics.count > 0, "Compiler accepted out-of-range % literal %.", fixture.parameter_type, value);
		}

		if fixture.parameter_type == "u64" {
			for value: UNSIGNED_NEGATIVE_VALUES {
				rejected := capture_compiler_error(tprint(UNARY_OVERLOAD_SOURCE, "u64", "string", value));
				assert(rejected.diagnostics.count > 0, "Compiler accepted negative u64 literal %.", value);
				expression := tprint("make(%).Clear", value);
				assert_overload_workspace_fixture("value: u64", "value: s64", expression, 1, "fixture_negative_unsigned_rank");
				assert_overload_workspace_fixture("value: s64", "value: u64", expression, 0, "fixture_negative_unsigned_reverse_rank");
			}
		}

	}

}

test_signed_boundary_fixtures :: () {
	SIGNED_BOUNDS_SOURCE :: #string JAI
make :: (value: %) -> s64 {
	return value;
}
make :: (value: string) -> string {
	return value;
}
fixture_signed_bounds :: () -> s64 {
	return make(%) + make(%);
}
JAI;
	SIGNED_RANK_SOURCE :: #string JAI
make :: (value: %) -> string {
	return "";
}
make :: (value: s64) -> s64 {
	return value;
}
fixture_signed_rank :: () -> s64 {
	return make(-1) + make(1);
}
JAI;

	if !begin_differential_section("Signed boundaries", SIGNED_BOUNDARY_CASES.count * 4 + 3) {
		return;
	}


	for fixture: SIGNED_BOUNDARY_CASES {
		assert_file_workspace_fixture(tprint(SIGNED_BOUNDS_SOURCE, fixture.parameter_type, fixture.lower, fixture.upper), "fixture_signed_bounds");
		for value, index: string.[fixture.below, fixture.above] {
			if index == 1 && fixture.above_matches {
				assert_overload_workspace_fixture(tprint("value: %", fixture.parameter_type), "value: string", tprint("make(%).Clear", value), 0, "fixture_signed_outside");
			} else {
				overflow := capture_compiler_error(tprint(UNARY_OVERLOAD_SOURCE, fixture.parameter_type, "string", value));
				assert(overflow.diagnostics.count > 0, "Compiler accepted out-of-range % literal %.", fixture.parameter_type, value);
			}
		}

		if fixture.parameter_type == "s64" {
			assert_overload_workspace_fixture("value: s64", "value: u64", tprint("make(%).Clear", fixture.above), 0, "fixture_unsigned_boundary");
			assert_overload_workspace_fixture("value: u64", "value: string", tprint("make(%).Clear", fixture.above), 0, "fixture_unsigned_only");
			assert_overload_workspace_fixture("value: u64", "value: string", "make(1).Clear", 0, "fixture_unsigned_small");
			assert_overload_workspace_fixture("value: u64", "value: s64", tprint("make(%).Clear + make(1).Clear", fixture.above), 1, "fixture_unsigned_small_rank");
		} else {
			assert_file_workspace_fixture(tprint(SIGNED_RANK_SOURCE, fixture.parameter_type), "fixture_signed_rank");
		}

	}

}

test_aggregate_member_fixtures :: () {
	if !begin_differential_section("Aggregate and member inference", AGGREGATE_TEST_TOTAL) {
		return;
	}


	assert_overload_workspace_fixture("first: float64, second: float64", "first: s64, second: float64", "make(1, 1).Clear", 1, "fixture_multi_argument_rank");
	assert_overload_workspace_fixture("first: s64, second: s64", "first: float64, second: float64", "make(1, 1).Clear", 0, "fixture_exact_first_rank");
	crossed_rank := capture_compiler_error(tprint(MULTI_ARGUMENT_RANK_SOURCE, "first: s64, second: float64", "first: float64, second: s64", "1, 1"));
	assert(crossed_rank.diagnostics.count > 0);
	assert_file_workspace_fixture(
		#string JAI
Base :: struct { Value: s64; }
Wrapper :: struct { #as using base: Base; }
Child :: struct { Clear: s64; }
Other :: struct { PushMatrix: s64; }
make :: (value: Base) -> Child { return .{Clear=1}; }
make :: (value: string) -> Other { return .{PushMatrix=1}; }
fixture_aggregate_conversion :: () -> s64 { return make(Wrapper.{base=Base.{Value=1}}).Clear; }
JAI,

		"fixture_aggregate_conversion"
	);
	assert_file_workspace_fixture(
		#string JAI
Base :: struct { Value: s64; }
Wrapper :: struct { #as using base: Base; }
Child :: struct { Clear: s64; }
Other :: struct { PushMatrix: s64; }
make :: (value: Base) -> Other { return .{PushMatrix=1}; }
make :: (value: Wrapper) -> Child { return .{Clear=1}; }
fixture_exact_aggregate :: () -> s64 { return make(Wrapper.{base=Base.{Value=1}}).Clear; }
JAI,

		"fixture_exact_aggregate"
	);
	ambiguous_aggregate_conversion := capture_compiler_error(
		#string JAI
First :: struct { Value: s64; }
Second :: struct { Value: s64; }
Wrapper :: struct { #as using first: First; #as using second: Second; }
Child :: struct { Clear: s64; }
Other :: struct { PushMatrix: s64; }
make :: (value: First) -> Child { return .{Clear=1}; }
make :: (value: Second) -> Other { return .{PushMatrix=1}; }
main :: () { return make(Wrapper.{first=First.{Value=1}, second=Second.{Value=2}}).Clear; }
JAI
	);
	assert(ambiguous_aggregate_conversion.diagnostics.count > 0);
	assert_file_workspace_fixture(
		#string JAI
Fixture_Input :: struct { Value: s64; }
Fixture_Alternate :: struct { Value: s64; }
Fixture_Child :: struct { Clear: s64; }
Fixture_Other :: struct { PushMatrix: s64; }
fixture_make :: (number: float64, input: Fixture_Input) -> Fixture_Other { return .{PushMatrix=1}; }
fixture_make :: (number: s64, input: Fixture_Alternate) -> Fixture_Child { return .{Clear=1}; }
fixture_later_mismatch :: () -> s64 { return fixture_make(1, Fixture_Alternate.{Value=1}).Clear; }
JAI,

		"fixture_later_mismatch"
	);
	assert_file_workspace_fixture(
		#string JAI
Fixture_Child :: struct { Clear: s64; }
Fixture_Container :: struct { Nested: Fixture_Child; }
Fixture_Other :: struct { PushMatrix: s64; }
fixture_make :: (ready: bool) -> Fixture_Container { return .{Nested=Fixture_Child.{Clear=1}}; }
fixture_make :: (ready: string) -> Fixture_Other { return .{PushMatrix=1}; }
fixture_called_alias :: () -> s64 { original := fixture_make(true); value := original; return value.Nested.Clear; }
JAI,

		"fixture_called_alias"
	);
	assert_file_workspace_fixture(
		#string JAI
Fixture_Child :: struct { Clear: s64; }
Fixture_Other :: struct { PushMatrix: s64; }
fixture_make :: (ready: bool) -> Fixture_Other { return .{PushMatrix=1}; }
fixture_shadowed_overloads :: () -> s64 {
	fixture_make :: (ready: bool) -> Fixture_Child { return .{Clear=1}; }
	fixture_make :: (ready: string) -> Fixture_Other { return .{PushMatrix=2}; }
	return fixture_make(true).Clear;
}
JAI,

		"fixture_shadowed_overloads"
	);
	assert_file_workspace_fixture(
		#string JAI
Fixture_Child :: struct { Clear: s64; }
fixture_identity :: (value: $T) -> T { return value; }
fixture_polymorphic_member :: () -> s64 {
	return fixture_identity(Fixture_Child.{Clear=1}).Clear;
}
JAI,

		"fixture_polymorphic_member"
	);
	assert_file_workspace_fixture(
		#string JAI
Fixture_Child :: struct { Clear: s64; }
fixture_poly_make :: (value: $T) -> Fixture_Child { return .{Clear=1}; }
fixture_polymorphic_explicit_return :: () -> s64 {
	return fixture_poly_make(1).Clear;
}
JAI,

		"fixture_polymorphic_explicit_return"
	);
	assert_file_workspace_fixture(
		#string JAI
Fixture_Child :: struct { Clear: s64; }
Fixture_Other :: struct { PushMatrix: s64; }
fixture_choose :: (left: $T, right: $U) -> T { return left; }
fixture_multi_polymorph :: () -> s64 {
	return fixture_choose(Fixture_Child.{Clear=1}, Fixture_Other.{PushMatrix=2}).Clear;
}
JAI,

		"fixture_multi_polymorph"
	);
	assert_file_workspace_fixture(
		#string JAI
Fixture_Child :: struct { Clear: s64; }
Fixture_Other :: struct { PushMatrix: s64; }
fixture_choose :: (left: $T, right: $U) -> T { return left; }
fixture_named_polymorph :: () -> s64 {
	return fixture_choose(right=Fixture_Other.{PushMatrix=2}, left=Fixture_Child.{Clear=1}).Clear;
}
JAI,

		"fixture_named_polymorph"
	);
	assert_file_workspace_fixture(
		#string JAI
Fixture_Child :: struct { Clear: s64; }
Fixture_Box :: struct (T: Type) { Nested: T; }
fixture_wrap :: (value: $T) -> Fixture_Box(T) { return .{Nested=value}; }
fixture_polymorphic_box :: () -> s64 { return fixture_wrap(Fixture_Child.{Clear=1}).Nested.Clear; }
JAI,

		"fixture_polymorphic_box"
	);
	assert_file_workspace_fixture(
		#string JAI
Fixture_Child :: struct { Clear: s64; }
Fixture_Other :: struct { PushMatrix: s64; }
Fixture_Pair :: struct (First: Type, Second: Type) { Left: First; Right: Second; }
fixture_wrap_pair :: (left: $T, right: $U) -> Fixture_Pair(T, U) { return .{Left=left, Right=right}; }
fixture_polymorphic_pair :: () -> s64 {
	return fixture_wrap_pair(Fixture_Other.{PushMatrix=1}, Fixture_Child.{Clear=2}).Right.Clear;
}
JAI,

		"fixture_polymorphic_pair"
	);
	assert_file_workspace_fixture(
		#string JAI
Fixture_Child :: struct { Clear: s64; }
Fixture_Other :: struct { PushMatrix: s64; }
Fixture_Pair :: struct (First: Type, Second: Type) { Left: First; Right: Second; }
fixture_wrap_pair :: (left: $T, right: $U) -> Fixture_Pair(U, T) { return .{Left=right, Right=left}; }
fixture_reordered_pair :: () -> s64 {
	return fixture_wrap_pair(right=Fixture_Other.{PushMatrix=1}, left=Fixture_Child.{Clear=2}).Right.Clear;
}
JAI,

		"fixture_reordered_pair"
	);
	assert_file_workspace_fixture(
		#string JAI
Fixture_Child :: struct { Clear: s64; }
Fixture_Other :: struct { PushMatrix: s64; }
Fixture_Pair :: struct (First: Type, Second: Type) { Left: First; Right: Second; }
fixture_wrap_named_pair :: (left: $T, right: $U) -> Fixture_Pair(Second=T, First=U) {
	return .{Left=right, Right=left};
}
fixture_named_return_pair :: () -> s64 {
	return fixture_wrap_named_pair(right=Fixture_Other.{PushMatrix=1}, left=Fixture_Child.{Clear=2}).Right.Clear;
}
JAI,

		"fixture_named_return_pair"
	);
	assert_file_workspace_fixture(
		#string JAI
Fixture_Child :: struct { Clear: s64; }
Fixture_Other :: struct { PushMatrix: s64; }
Fixture_Pair :: struct (First: Type, Second: Type) { Left: First; Right: Second; }
Fixture_Alias :: Fixture_Pair;
fixture_wrap_aliased_pair :: (left: $T, right: $U) -> Fixture_Alias(Second=T, First=U) {
	return .{Left=right, Right=left};
}
fixture_aliased_return_pair :: () -> s64 {
	return fixture_wrap_aliased_pair(right=Fixture_Other.{PushMatrix=1}, left=Fixture_Child.{Clear=2}).Right.Clear;
}
JAI,

		"fixture_aliased_return_pair"
	);
	assert_file_workspace_fixture(
		#string JAI
Fixture_Child :: struct { Clear: s64; }
Fixture_Box :: struct (T: Type) { Nested: T; }
fixture_wrap :: (value: $T) -> Fixture_Box(T) { return .{Nested=value}; }
fixture_same_box :: (choose: bool) -> s64 {
	return (ifx choose
		then fixture_wrap(Fixture_Child.{Clear=1})
		else Fixture_Box(Fixture_Child).{Nested=Fixture_Child.{Clear=2}}
	).Nested.Clear;
}
JAI,

		"fixture_same_box"
	);
	invalid_instantiation := capture_compiler_error(
		#string JAI
Child :: struct { Clear: s64; }
Other :: struct { PushMatrix: s64; }
Box :: struct (T: Type) { Nested: T; }
wrap :: (value: $T) -> Box(T) { return .{Nested=value}; }
main :: (choose: bool) {
	value := ifx choose
		then wrap(Child.{Clear=1})
		else Box(Other).{Nested=Other.{PushMatrix=2}};
	return value.Nested.Clear;
}
JAI
	);
	assert_file_workspace_fixture(
		#string JAI
Child :: struct { Clear: s64; }
Box :: struct (T: Type) { Nested: T; }
fixture_direct_receiver :: () -> s64 {
	return Box(Child).{Nested=Child.{Clear=1}}.Nested.Clear;
}
JAI,

		"fixture_direct_receiver"
	);
	assert_file_workspace_fixture(
		#string JAI
Child :: struct { Clear: s64; }
Box :: struct (T: Type) { Nested: T; }
fixture_pointer_receiver :: () -> s64 {
	box := Box(Child).{Nested=Child.{Clear=1}};
	pointer := *box;
	return pointer.*.Nested.Clear;
}
JAI,

		"fixture_pointer_receiver"
	);
	assert_file_workspace_fixture(
		#string JAI
Child :: struct { Clear: s64; }
Box :: struct (T: Type) { Nested: T; }
fixture_subscript_receiver :: () -> s64 {
	boxes: [1] Box(Child) = .[Box(Child).{Nested=Child.{Clear=1}}];
	return boxes[0].Nested.Clear;
}
JAI,

		"fixture_subscript_receiver"
	);
	scalar_member := capture_compiler_error(
		#string JAI
main :: () {
	scalar := 1;
	return scalar.Nested;
}
JAI
	);
	assert(scalar_member.diagnostics.count > 0);
	assert(invalid_instantiation.diagnostics.count > 0);
	missing_instantiation := capture_compiler_error(
		#string JAI
Child :: struct { Clear: s64; }
Pair :: struct (First: Type, Second: Type) { Right: Second; }
main :: () {
	pair: Pair(Child);
	return pair.Right.Clear;
}
JAI
	);
	assert(missing_instantiation.diagnostics.count > 0);
	unknown_instantiation := capture_compiler_error(
		#string JAI
Child :: struct { Clear: s64; }
Pair :: struct (First: Type, Second: Type) { Right: Second; }
Alias :: Pair;
main :: () {
	pair: Alias(Unknown=Child, Second=Child);
	return pair.Right.Clear;
}
JAI
	);
	assert(unknown_instantiation.diagnostics.count > 0);
	duplicate_instantiation := capture_compiler_error(
		#string JAI
Child :: struct { Clear: s64; }
Pair :: struct (First: Type, Second: Type) { Right: Second; }
main :: () {
	pair: Pair(First=Child, First=Child);
	return pair.Right.Clear;
}
JAI
	);
	assert(duplicate_instantiation.diagnostics.count > 0);
	assert_file_workspace_fixture(
		#string JAI
Fixture_Child :: struct { Clear: s64; }
Fixture_Box :: struct (T: Type) { Nested: T; }
Fixture_Instance :: Fixture_Box(Fixture_Child);
Fixture_Alias :: Fixture_Instance;
fixture_typed_alias :: () -> s64 { typed: Fixture_Alias; value := typed; return value.Nested.Clear; }
JAI,

		"fixture_typed_alias"
	);
	assert_file_workspace_fixture(
		#string JAI
Fixture_Child :: struct { Clear: s64; }
Fixture_Box :: struct (T: Type) { Nested: T; }
Fixture_Instance :: Fixture_Box(Fixture_Child);
Fixture_Alias :: Fixture_Instance;
fixture_inferred_alias :: () -> s64 {
	original := Fixture_Alias.{Nested=Fixture_Child.{Clear=1}};
	first := original;
	second := first;
	return second.Nested.Clear;
}
JAI,

		"fixture_inferred_alias"
	);
	ambiguous_alias := capture_compiler_error(
		#string JAI
Child :: struct { Clear: s64; }
Box :: struct (T: Type) { Nested: T; }
Alias :: Box(Child);
Alias :: Box(Child);
main :: () {
	typed: Alias;
	return typed.Nested.Clear;
}
JAI
	);
	assert(ambiguous_alias.diagnostics.count > 0);
	incomplete_alias := capture_compiler_error(
		#string JAI
Child :: struct { Clear: s64; }
Box :: struct (T: Type) { Nested: T; }
Alias :: Box;
main :: () {
	typed: Alias;
	return typed.Nested.Clear;
}
JAI
	);
	assert(incomplete_alias.diagnostics.count > 0);
	assert_file_workspace_fixture(
		#string JAI
Fixture_Child :: struct { Clear: s64; }
Fixture_Box :: struct (T: Type) { Nested: T; }
Fixture_Container :: struct { Item: Fixture_Box(Fixture_Child); }
fixture_instantiated_field :: () -> s64 { container: Fixture_Container; return container.Item.Nested.Clear; }
JAI,

		"fixture_instantiated_field"
	);
	assert_file_workspace_fixture(
		#string JAI
Fixture_Child :: struct { Clear: s64; }
Fixture_Box :: struct (T: Type) { Nested: T; }
Fixture_Container :: struct (T: Type) { Item: Fixture_Box(T); }
fixture_parameterized_field :: () -> s64 {
	container: Fixture_Container(Fixture_Child);
	return container.Item.Nested.Clear;
}
JAI,

		"fixture_parameterized_field"
	);
	assert_file_workspace_fixture(
		#string JAI
Fixture_Child :: struct { Clear: s64; }
Fixture_Box :: struct (T: Type) { Nested: T; }
Fixture_Container :: struct (T: Type) { Item: Fixture_Box(Fixture_Box(T)); }
fixture_nested_field :: () -> s64 {
	container: Fixture_Container(Fixture_Child);
	return container.Item.Nested.Nested.Clear;
}
JAI,

		"fixture_nested_field"
	);
	assert_file_workspace_fixture(
		#string JAI
C :: struct { Clear: s64; }
Box :: struct (T: Type) { Nested: T; }
make :: (value: C) -> Box(C) { return .{Nested=value}; }
fixture_instance_alias_call :: () -> s64 { alias :: make; return alias(C.{Clear=1}).Nested.Clear; }
JAI,

		"fixture_instance_alias_call"
	);
	assert_file_workspace_fixture(
		#string JAI
C :: struct { Clear: s64; }
O :: struct { PushMatrix: s64; }
Box :: struct (T: Type) { Nested: T; }
make :: (value: string) -> Box(C) { return .{Nested=C.{Clear=1}}; }
make :: (value: bool) -> Box(O) { return .{Nested=O.{PushMatrix=1}}; }
fixture_instance_overload :: () -> s64 { return make("a").Nested.Clear; }
JAI,

		"fixture_instance_overload"
	);
	assert_file_workspace_fixture(
		#string JAI
C :: struct { Clear: s64; }
Box :: struct (T: Type) { Nested: T; }
fixture_instance_cast :: () -> s64 {
	original := Box(C).{Nested=C.{Clear=1}};
	return (cast(Box(C)) original).Nested.Clear;
}
JAI,

		"fixture_instance_cast"
	);
	assert_file_workspace_fixture(
		#string JAI
C :: struct { Clear: s64; }
Box :: struct (T: Type) { Nested: T; }
make :: () -> Box(C) { return .{Nested=C.{Clear=1}}; }
fixture_instance_query :: () -> s64 { value: type_of(make()); return value.Nested.Clear; }
JAI,

		"fixture_instance_query"
	);
	assert_file_workspace_fixture(
		#string JAI
C :: struct { Clear: s64; }
Box :: struct (T: Type) { Nested: T; }
fixture_instance_run :: () -> s64 { return (#run Box(C).{Nested=C.{Clear=1}}).Nested.Clear; }
JAI,

		"fixture_instance_run"
	);
	assert_file_workspace_fixture(
		#string JAI
C :: struct { Clear: s64; }
Box :: struct (T: Type) { Nested: T; }
fixture_instance_block_run :: () -> s64 { return (#run -> Box(C) { return .{Nested=C.{Clear=1}}; }).Nested.Clear; }
JAI,

		"fixture_instance_block_run"
	);
	assert_file_workspace_fixture(
		#string JAI
C :: struct { Clear: s64; }
O :: struct { PushMatrix: s64; }
Box :: struct (T: Type) { Nested: T; }
fixture_instance_static :: () -> s64 {
	return (#ifx true
		then Box(C).{Nested=C.{Clear=1}}
		else Box(O).{Nested=O.{PushMatrix=2}}
	).Nested.Clear;
}
JAI,

		"fixture_instance_static"
	);
	unknown_query := capture_compiler_error(
		#string JAI
C :: struct { Clear: s64; }
Box :: struct (T: Type) { Nested: T; }
main :: () { value: type_of(missing()); return value.Nested.Clear; }
JAI
	);
	assert(unknown_query.diagnostics.count > 0);
	unknown_cast := capture_compiler_error(
		#string JAI
C :: struct { Clear: s64; }
Box :: struct (T: Type) { Nested: T; }
main :: () { original := Box(C).{Nested=C.{Clear=1}}; return (cast(Box(Missing)) original).Nested.Clear; }
JAI
	);
	assert(unknown_cast.diagnostics.count > 0);
	unknown_static := capture_compiler_error(
		#string JAI
C :: struct { Clear: s64; }
Box :: struct (T: Type) { Nested: T; }
main :: () { return (#ifx Unknown then Box(C).{Nested=C.{Clear=1}} else Box(C).{Nested=C.{Clear=2}}).Nested.Clear; }
JAI
	);
	assert(unknown_static.diagnostics.count > 0);
	assert_file_workspace_fixture(
		#string JAI
Fixture_Child :: struct { Clear: s64; }
Fixture_Other :: struct { PushMatrix: s64; }
Fixture_Pair :: struct (First: Type, Second: Type) { Left: First; Right: Second; }
Fixture_Container :: struct (T: Type, U: Type) { Item: Fixture_Pair(Second=T, First=U); }
fixture_named_field :: () -> s64 {
	container: Fixture_Container(U=Fixture_Other, T=Fixture_Child);
	return container.Item.Right.Clear;
}
JAI,

		"fixture_named_field"
	);
	incomplete_nested_field := capture_compiler_error(
		#string JAI
Child :: struct { Clear: s64; }
Box :: struct (T: Type) { Nested: T; }
Container :: struct (T: Type) { Item: Box(T); }
main :: () {
	container: Container;
	return container.Item.Nested.Clear;
}
JAI
	);
	assert(incomplete_nested_field.diagnostics.count > 0);
	assert_file_workspace_fixture(
		#string JAI
Fixture_Box :: struct (T: Type) { Clear: s64; Nested: T; }
fixture_primitive_parameter :: () -> s64 {
	box: Fixture_Box(s64);
	return box.Clear;
}
JAI,

		"fixture_primitive_parameter"
	);
	assert_file_workspace_fixture(
		#string JAI
Fixture_Child :: struct { Clear: s64; }
Fixture_Box :: struct (T: Type) { Nested: T; }
fixture_instantiated_member :: () -> s64 {
	box: Fixture_Box(Fixture_Child) = .{Nested=Fixture_Child.{Clear=1}};
	return box.Nested.Clear;
}
JAI,

		"fixture_instantiated_member"
	);
	assert_file_workspace_fixture(
		#string JAI
Fixture_Child :: struct { Clear: s64; }
Fixture_Container :: struct { Nested: Fixture_Child; }
fixture_cast_member :: () -> s64 {
	original := Fixture_Container.{Nested=Fixture_Child.{Clear=1}};
	return (cast(Fixture_Container) original).Nested.Clear;
}
JAI,

		"fixture_cast_member"
	);
	assert_file_workspace_fixture(
		#string JAI
Fixture_Child :: struct { Clear: s64; }
Fixture_Container :: struct { Nested: Fixture_Child; }
fixture_run_member :: () -> s64 {
	return (#run Fixture_Container.{Nested=Fixture_Child.{Clear=1}}).Nested.Clear;
}
JAI,

		"fixture_run_member"
	);
	assert_file_workspace_fixture(
		#string JAI
Fixture_Child :: struct { Clear: s64; }
Fixture_Container :: struct { Nested: Fixture_Child; }
fixture_ifx_member :: (ready: bool) -> s64 {
	return (ifx ready
		then Fixture_Container.{Nested=Fixture_Child.{Clear=1}}
		else Fixture_Container.{Nested=Fixture_Child.{Clear=2}}
	).Nested.Clear;
}
JAI,

		"fixture_ifx_member"
	);
	assert_file_workspace_fixture(
		#string JAI
Fixture_Run_Struct :: struct { Clear: s64; }
fixture_run_field :: () -> s64 {
	value := #run Fixture_Run_Struct.{Clear=1};
	return value.Clear;
}
JAI,

		"fixture_run_field"
	);
	assert_file_workspace_fixture(
		#string JAI
Fixture_Run_Struct :: struct { Clear: s64; }
fixture_typed_run_field :: () -> s64 {
	value := #run -> Fixture_Run_Struct {
		return .{Clear=1};
	};
	return value.Clear;
}
JAI,

		"fixture_typed_run_field"
	);
}

assert_declaration_workspace_fixture :: (source: string) {
	begin_differential_test();
	fixture_source := tprint("Fixture_Constraint :: struct { value: s64; }\nfixture_procedure :: () {\n%\n}\n", source);
	differential_progress.fixture_source = fixture_source;
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
	add_build_string(fixture_source, workspace);

	found := false;
	while true {
		message := compiler_wait_for_message();
		if message.workspace != workspace {
			continue;
		}


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

						if !matches {
							continue;
						}


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
	finish_differential_test();
}

assert_assignment_workspace_fixture :: (source: string, prelude: string, prelude_name: string) {
	begin_differential_test();
	fixture_source := tprint("fixture_pair :: () -> (s64, s64) { return 1, 2; }\nfixture_procedure :: () {\n%\n%\n}\n", prelude, source);
	differential_progress.fixture_source = fixture_source;
	parsed := Parser.parse_block(tprint("{ % }", source));
	defer Parser.release_parser_tree(*parsed);

	assert(parsed.status == .COMPLETE, "Parser did not complete assignment fixture '%'.", source);
	actual_block := parsed.root.(*Parser.Parser_Block);
	assert(actual_block.statements.count == 1);
	actual := normalize_parser_tree(actual_block.statements[0]);

	workspace := compiler_create_workspace("Jai_Parser assignment fixture");
	options := get_build_options(workspace);
	copy_commonly_propagated_fields(get_build_options(), *options);
	options.output_type = .NO_OUTPUT;
	options.write_added_strings = false;
	set_build_options(options, workspace);
	compiler_begin_intercept(workspace);
	add_build_string(fixture_source, workspace);

	found := false;
	while true {
		message := compiler_wait_for_message();
		if message.workspace != workspace {
			continue;
		}


		if message.kind == {
			case .TYPECHECKED;
				typechecked := message.(*Message_Typechecked);
				for wrapped: typechecked.procedure_bodies {
					statements := wrapped.expression.block.statements;
					if statements.count != 2 || statements[0].kind != .DECLARATION {
						continue;
					}
					if statements[0].(*Code_Declaration).name != prelude_name {
						continue;
					}


					expected := normalize_tree(statements[1]);
					difference := compare_normalized_trees(actual, expected);
					assert(!difference.differences.count, "Assignment AST mismatch for '%':\n%", source, format_structural_differences(difference));
					found = true;
				}

			case .COMPLETE;
				complete := message.(*Message_Complete);
				assert(complete.error_code == .NONE, "Compiler rejected assignment fixture '%'.", source);
				break;
		}
	}

	compiler_end_intercept(workspace);
	assert(found, "Compiler did not expose assignment fixture '%'.", source);
	finish_differential_test();
}

test_assignment_workspace_fixtures :: () {
	if !begin_differential_section("Assignments", ASSIGNMENT_TEST_TOTAL) {
		return;
	}


	assert_assignment_workspace_fixture("array[0], array[1] += fixture_pair();", "array: [4] s64;", "array");
	assert_assignment_workspace_fixture("v.x, v.y, v.z = 1, 4, 9;", "v: struct { x, y, z: s64; };", "v");
}


test_declaration_workspace_fixtures :: () {
	declarations := string.[
		"fixture_typed: **s64 = null;",
		"fixture_fixed: [4] s64;",
		"fixture_view: [] s64;",
		"fixture_resizable: [..] s64;",
		"fixture_callback: (value: s64) -> bool;",
		"fixture_unnamed: (s64) -> bool;",
		"fixture_bare: (s64);",
		"fixture_polymorphic_callback :: (value: $T, f: (T) -> $R) -> R { return f(value); }",
		"Fixture_Simple_Procedure :: #type () -> ();",
		"fixture_compound: *(**void, [3] [5] Fixture_Constraint) -> ([..] #Context);",
		"fixture_alias :: #type,distinct u32;",
		"fixture_x, fixture_y: s64 = 7;",
		"fixture_a, fixture_b := 1, 2;",
		"fixture_aligned: s64 #align 16;",
		"fixture_noted: s64; @FixtureNote",
		"fixture_inline :: inline () {}",
		"fixture_dump :: (value: s64) -> s64 #dump { return value; }",
		"fixture_assert_macro :: (value: $T) #expand { #assert true \"supported\"; }",
		"fixture_no_inline :: no_inline () {}",
		"fixture_parameter_defaults :: (width: s64 = 640, height: s64 = 480) {}",
		"Fixture_Aggregate_Defaults :: struct (width: s64 = 640, height: s64 = 480) {}",
		"fixture_polymorphic_defaults :: (value: $T = 1, fallback: T = 2) -> T { return value; }",
		"fixture_named_return_defaults :: () -> (value: s64 = 0, valid: bool = false) { return; }",
		"fixture_modify :: (value: $T) -> T #modify { return true; } { return value; }",
		"Fixture_Modified_Struct :: struct (T: Type) #modify { return true; } { value: T; }",
		"Fixture_Struct :: struct { CONSTANT :: 1; }; @Serializable",
		"Fixture_Defaulted_Field :: struct { w: s64; w = 1; }",
		"operator + :: (left: Fixture_Constraint, right: Fixture_Constraint) -> Fixture_Constraint #symmetric { return .{}; }",
		"operator - :: (value: Fixture_Constraint) -> Fixture_Constraint { return value; }",
		"operator * :: (left: Fixture_Constraint, right: Fixture_Constraint) -> Fixture_Constraint { return left; }",
		"operator / :: (left: Fixture_Constraint, right: Fixture_Constraint) -> Fixture_Constraint { return left; }",
		"operator % :: (left: Fixture_Constraint, right: Fixture_Constraint) -> Fixture_Constraint { return left; }",
		"operator < :: (left: Fixture_Constraint, right: Fixture_Constraint) -> bool { return false; }",
		"operator > :: (left: Fixture_Constraint, right: Fixture_Constraint) -> bool { return false; }",
		"operator ! :: (value: Fixture_Constraint) -> bool { return false; }",
		"operator ~ :: (value: Fixture_Constraint) -> Fixture_Constraint { return value; }",
		"operator & :: (left: Fixture_Constraint, right: Fixture_Constraint) -> Fixture_Constraint { return left; }",
		"operator | :: (left: Fixture_Constraint, right: Fixture_Constraint) -> Fixture_Constraint { return left; }",
		"operator ^ :: (left: Fixture_Constraint, right: Fixture_Constraint) -> Fixture_Constraint { return left; }",
		"operator == :: (left: Fixture_Constraint, right: Fixture_Constraint) -> bool { return true; }",
		"operator != :: (left: Fixture_Constraint, right: Fixture_Constraint) -> bool { return false; }",
		"operator <= :: (left: Fixture_Constraint, right: Fixture_Constraint) -> bool { return false; }",
		"operator >= :: (left: Fixture_Constraint, right: Fixture_Constraint) -> bool { return false; }",
		"operator && :: (left: Fixture_Constraint, right: Fixture_Constraint) -> bool { return false; }",
		"operator || :: (left: Fixture_Constraint, right: Fixture_Constraint) -> bool { return false; }",
		"operator << :: (left: Fixture_Constraint, amount: s64) -> Fixture_Constraint { return left; }",
		"operator >> :: (left: Fixture_Constraint, amount: s64) -> Fixture_Constraint { return left; }",
		"operator <<< :: (left: Fixture_Constraint, amount: s64) -> Fixture_Constraint { return left; }",
		"operator >>> :: (left: Fixture_Constraint, amount: s64) -> Fixture_Constraint { return left; }",
		"operator += :: (left: *Fixture_Constraint, right: Fixture_Constraint) {}",
		"operator -= :: (left: *Fixture_Constraint, right: Fixture_Constraint) {}",
		"operator *= :: (left: *Fixture_Constraint, right: Fixture_Constraint) {}",
		"operator /= :: (left: *Fixture_Constraint, right: Fixture_Constraint) {}",
		"operator %= :: (left: *Fixture_Constraint, right: Fixture_Constraint) {}",
		"operator <<= :: (left: *Fixture_Constraint, amount: s64) {}",
		"operator >>= :: (left: *Fixture_Constraint, amount: s64) {}",
		"operator <<<= :: (left: *Fixture_Constraint, amount: s64) {}",
		"operator >>>= :: (left: *Fixture_Constraint, amount: s64) {}",
		"operator &= :: (left: *Fixture_Constraint, right: Fixture_Constraint) {}",
		"operator |= :: (left: *Fixture_Constraint, right: Fixture_Constraint) {}",
		"operator ^= :: (left: *Fixture_Constraint, right: Fixture_Constraint) {}",
		"operator &&= :: (left: *Fixture_Constraint, right: Fixture_Constraint) {}",
		"operator ||= :: (left: *Fixture_Constraint, right: Fixture_Constraint) {}",
		"operator [] :: (value: Fixture_Constraint, index: s64) -> s64 { return value.value; }",
		"operator []= :: (value: *Fixture_Constraint, index: s64, replacement: s64) { value.value = replacement; }",
		"operator *[] :: (value: *Fixture_Constraint, index: s64) -> *s64 { return *value.value; }",
		"fixture_uninitialized: s64 = ---;",
		"fixture_character_default :: (value: u8 = #char \"A\") {}",
		"fixture_this_constant :: #this;",
		"fixture_caller_code_default :: (call := #caller_code) #expand {}",
	];
	if !begin_differential_section("Declarations", declarations.count) {
		return;
	}


	for source: declarations {
		assert_declaration_workspace_fixture(source);
	}
}

test_directive_workspace_fixtures :: () {
	directives := string.[
		"Fixture_Using_Member :: struct { using member: Fixture_Constraint; }",
		"Fixture_As_Member :: struct { #as using base: Fixture_Constraint; }",
		"Fixture_Suffix_As_Member :: struct { using #as base: Fixture_Constraint; }",
		"Fixture_Static_Member :: struct { #if true { enabled: s64; } else { disabled: s64; } }",
	];
	if !begin_differential_section("Directives", directives.count) {
		return;
	}


	for source: directives {
		assert_declaration_workspace_fixture(source);
	}
}

test_syntax_fixtures :: () {
	assert_statement_fixture("#if true { enabled := 1; } else { disabled := 2; }");
	assert_statement_fixture("#asm { nop; }");
	assert_asm_compiler_shape("{ #asm { nop; } }", #code { #asm { nop; } });
	assert_asm_compiler_shape("{ #asm AVX, AVX2 {} }", #code { #asm AVX, AVX2 {} });
	assert_asm_compiler_shape(#string JAI
{
    #asm { nop; }
}
JAI
	, #code {
    #asm { nop; }
});
	assert_nested_asm_compiler_shape("{ if true { #asm { nop; } } else { #asm { nop; } } }", #code { if true { #asm { nop; } } else { #asm { nop; } } });
	assert_all_operator_fixtures();
	assert_all_precedence_pairs();
	assert_expression_fixture("identifier");
	assert_expression_fixture("42");
	assert_expression_fixture("0xFF");
	assert_expression_fixture("0Xff");
	assert_expression_fixture("0b101");
	assert_expression_fixture("0B101");
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
	assert_expression_fixture("foo({1, 2, 3})");
	assert_expression_fixture("({1, 2, 3})");
	assert_expression_fixture(".[{3, \"Yes\"}, {2, \"No\"}]");
	assert_expression_fixture("value == {}");
	assert_statement_fixture("value := {};");
	assert_statement_fixture("return {};");
	assert_statement_fixture("if value == {} { return {}; }");
	assert_statement_fixture("if values[{1, 2}] { return {}; }");
	assert_statement_matches_code(#string JAI
if fruit == {
    // no cases
}
JAI
	, #code { if fruit == {
    // no cases
} });
	assert_statement_matches_code(
		#string JAI
if fruit == { /* case other; */ } if fruit == { /* case 1; */ } if fruit == { /* case 2; */ } trailing();
JAI,

		#code { if fruit == { /* case other; */ } if fruit == { /* case 1; */ } if fruit == { /* case 2; */ } trailing(); }
	);
	assert_expression_fixture(".member");
	assert_expression_fixture(#string JAI
#string END
body
END
JAI
	);
	assert_expression_fixture("#char \"A\"");
	assert_expression_fixture("#this");
	assert_expression_matches_code("#filepath", #code #filepath, fully_pathed_filename=tprint("%fixture.jai", #filepath));
	assert_expression_fixture("#caller_code");
	assert_expression_fixture("(identifier)");
	assert_expression_fixture("!~flag");
	assert_expression_fixture("foo()");
	assert_expression_fixture("inline foo(1)");
	assert_expression_fixture("no_inline foo(1)");
	assert_expression_fixture("foo(1, named = value)");
	assert_expression_fixture("join(strings,, allocator=temp)");
	assert_expression_fixture("f(16, 8,, allocator = pool_allocator)");
	assert_expression_fixture("f(1000, 3,, logger = my_logger)");
	assert_expression_fixture("f(5, 10,, some_value = 42)");
	assert_expression_fixture("f(16, 8,, allocator = pool_allocator, logger = my_logger)");
	assert_expression_fixture("f(5, 10,, pool_allocator, logger = my_logger)");
	assert_expression_fixture("f(1000, 3,, pool_allocator)");
	assert_expression_fixture("f(,, pool_allocator)");
	assert_expression_fixture("f(,, allocator = pool_allocator)");
	assert_expression_fixture("object.method(1)[index].*");
	assert_expression_fixture("cast(s32) value");
	assert_expression_fixture("cast,no_check(s32) value");
	assert_expression_fixture("cast(*u8) value");
	assert_expression_fixture("cast([3] int) value");
	assert_expression_fixture("New([3] int)");
	assert_expression_fixture("consume(*value)");
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
	assert_expression_fixture("#code value := 1");
	assert_expression_fixture("#code value: s64 = 1");
	assert_expression_fixture("#code VALUE :: 1");
	assert_expression_fixture("#code,typed value: s64 = 1");
	assert_expression_fixture("#code { value := 1; use(value); }");
	assert_expression_fixture("#code,typed { value := 1; use(value); }");
	assert_expression_fixture("#run compute()");
	assert_expression_fixture("#run,stallable compute()");
	assert_expression_fixture("#run,stallable { value := compute(); return value; }");
	assert_expression_fixture("#run,host compute()");
	assert_expression_fixture("#run,host { value := compute(); return value; }");
	assert_expression_fixture("#run -> string { return \"ready\"; }");
	assert_expression_fixture("#run,host -> string { return \"ready\"; }");
	assert_statement_fixture("VALUE :: #run -> string { return \"ready\"; }");
	assert_statement_fixture("VALUE :: #run,host -> string { return \"ready\"; };");
	assert_expression_fixture("#procedure_of_call foo(1)");
	assert_expression_fixture("#procedure_of_call foo(**float)");
	assert_expression_fixture("#insert generated_code");
	assert_expression_fixture("#insert,scope() generated_code");
	assert_expression_fixture("#insert -> string { return \"generated\"; }");
	assert_expression_fixture("#insert -> Code { return #code x = x + 1; }");
	assert_statement_fixture("#insert -> string { return \"generated\"; }");
	assert_statement_fixture("#insert -> Code { return #code x = x + 1; }");
	assert_expression_fixture("#insert,scope(caller) (break=break outer, continue=continue outer, remove=remove outer) body");
	assert_expression_fixture("#insert(break=break y, continue=continue y, remove=#assert(false)) body");
	assert_statement_fixture("#insert(break=break y) body;");
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
	assert_statement_fixture(#string JAI
#import,string #string END
VALUE :: 1;
END
;
JAI
	);
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
	assert_expression_fixture("ifx ready then 1");
	assert_expression_fixture("ifx ready else 1");
	assert_expression_fixture("ifx ready");
	assert_expression_fixture("ifx ready { prepare(); 1; } else { 2; }");
	assert_expression_fixture("#ifx ready then 1 else 2");
	assert_expression_fixture("#ifx ready { prepare(); 1; } else { 2; }");
	assert_expression_fixture("() { return; }");
	assert_expression_fixture("(value: $T) -> T #expand #compile_time { return value; }");
	assert_statement_fixture("for_expansion :: (holder: Holder, body: Code, flags: For_Flags) #expand {}");
	assert_statement_fixture("for_expansion :: (holder: *Holder, body: Code, flags: For_Flags) #expand {}");
	assert_statement_fixture("for_expansion :: (holder: Holder, body: Code, flags: For_Flags) #expand { `it := holder; `it_index: s64; `visited_index := 0; }");
	assert_expression_fixture("(items: ..Any) -> value: s64, found: bool { return 0, false; }");
	assert_expression_fixture("(value: $T/interface Constraint) -> T");
	assert_expression_fixture("(using value: *Thing) { return; }");
	assert_expression_fixture("() -> s64 #foreign kernel32 \"external_name\"");
	assert_expression_fixture("() #deprecated \"Use replacement instead.\" { return; }");
	assert_expression_fixture("value => value + 1");
	assert_expression_fixture("(left, right) => { return left + right; }");
	assert_expression_fixture("(using v: Vector3_With_Length, using,except(x, y, z) q: Quaternion) { return; }");
	assert_expression_fixture("struct { value: s64; }");
	assert_expression_fixture("struct { info: Ice_Cream_Info; info.flavor = \"chocolate\"; position: Vector3; position.z = 1.5; brightness: float; brightness = 101.2; }");
	assert_expression_fixture("struct { #as using base: Document; base.type = Executable_File; }");
	assert_expression_fixture("struct { using,except(length) position: Vector3_With_Length; }");
	assert_expression_fixture("struct { using,only(w, y) orientation: Quaternion; }");
	assert_expression_fixture("struct { value: u64; #overlay (value) bits: u64; }");
	assert_expression_fixture("struct (T: Type, N := 2) { value: T; CONSTANT :: N; }");
	assert_expression_fixture("struct { value: s64; } #no_padding");
	assert_expression_fixture("struct #type_info_none #type_info_no_size_complaint #type_info_procedures_are_void_pointers {}");
	assert_expression_fixture("union { integer: s64; text: string; }");
	assert_expression_fixture("enum u16 #specified { READ :: 1; WRITE :: 2; }");
	assert_expression_fixture("enum #complete { READY; DONE; }");
	assert_expression_fixture("enum_flags u32 { FAST; SAFE; }");
	assert_statement_fixture("return 1, 2;");
	assert_statement_fixture("out1, out2 = hello(1);");
	assert_statement_fixture("a=, b := proc();");
	assert_statement_fixture("a:, b = proc();");
	assert_statement_matches_code("#no_reset fixture_no_reset: s64;", #code { #no_reset fixture_no_reset: s64; }, file_scope=true);
	assert_statement_fixture("{ value := 1; }");
	assert_statement_fixture("`return 1;");
	assert_statement_fixture("while ready { break; }");
	assert_statement_fixture("while (pointer) { break; }");
	assert_statement_fixture("while loop := ready { break loop; }");

	// Ranges keep their right endpoint even when flags and selectors precede the collection.
	assert_statement_fixture("for item, index: values { continue; }");
	assert_statement_fixture("for 1..3 defer tick();");
	assert_statement_fixture("for value: first..last process(value);");
	assert_statement_fixture("for < * :utf8_iter value: 1..3 { process(value); }");
	assert_statement_fixture("for <=reverse :utf8_iter value: first..last { process(value); }");

	// These spellings occur in the for-expansion guide; compare source-owned loop fields before expansion.
	assert_statement_fixture("for holder { process(it); }");
	assert_statement_fixture("for v, n: holder { process(v); }");
	assert_statement_fixture("for :positive_vibes_only v, n: holder { process(v); }");
	assert_statement_fixture("for :extra_info v, n: holder { process(v); }");
	assert_statement_fixture("for grid { process(it); }");
	assert_statement_fixture("for :fixed_break grid { process(it); }");
	assert_statement_fixture("for dummy {}");
	assert_statement_fixture("for < dummy {}");
	assert_statement_fixture("for * dummy {}");
	assert_statement_fixture("for < * dummy {}");
	assert_statement_fixture("for :polite dummy {}");
	assert_statement_fixture("for < :polite dummy {}");
	assert_statement_fixture("for <=reversed NAMES print(it);");
	assert_statement_fixture("for *=cast(bool)(flags & .POINTER), <=cast(bool)(flags & .REVERSE) a.data { print(it); }");
	assert_statement_fixture("for my {}");
	assert_statement_fixture("for < my {}");
	assert_statement_fixture("for * my {}");
	assert_statement_fixture("for <* my {}");
	assert_statement_fixture("for `it, `it_index: a.data { process(it); }");

	// Compare implicit and renamed bindings under the default and named expansions.
	assert_statement_fixture("for values process(it);");
	assert_statement_fixture("for < values process(it);");
	assert_statement_fixture("for * values process(it);");
	assert_statement_fixture("for :utf8_iter text process(it_index);");
	assert_statement_fixture("for < :utf8_iter value: text process(value);");
	assert_statement_fixture("for :utf8_iter value, index: text process(value);");
	assert_statement_fixture("for :utf8_iter `it, `it_index: text process(it);");

	assert_statement_fixture("for < * :utf8_iter value, index: text process(value);");
	assert_statement_fixture("for <* :utf8_iter text process(it);");
	assert_statement_fixture("for <* :utf8_iter text { process(it); }");

	// The comma separates controlled flags; the body must remain outside their expressions.
	assert_statement_fixture("for *=pointer_mode, <=reverse_mode :utf8_iter value, index: text process(value);");
	assert_statement_fixture("for <=reverse :utf8_iter text process(it);");
	assert_statement_fixture("for <=reversed NAMES print(it);");
	assert_statement_fixture("for *=pointer_mode values process(it);");
	assert_statement_fixture("for *=cast(bool)(flags & .POINTER), <=cast(bool)(flags & .REVERSE) a.data { print(it); }");
	assert_statement_fixture("for *=(left == right), <=reverse values process(it);");
	assert_statement_fixture("for <=reverse, *=pointer_mode values process(it);");

	// Parenthesized operators belong to flags; bare ones belong to the collection.
	assert_statement_fixture("for <=(flag = enabled) values process(it);");
	assert_statement_fixture("for <=reverse left == right process(it);");
	assert_statement_fixture("for <=reverse target = source process(it);");

	comparison_flags := compiler_get_nodes(#code { for *=(left == right), <=reverse values process(it); }).(*Code_Block).statements[0].(*Code_For);
	assert(comparison_flags.want_pointer_expression.kind == .BINARY_OPERATOR);
	assert(comparison_flags.want_reverse_expression.(*Code_Ident).name == "reverse");
	assert(comparison_flags.iteration_expression.(*Code_Ident).name == "values");
	assert(comparison_flags.ident_decl == null);
	assert(comparison_flags.index_decl == null);
	assert(comparison_flags.macro_expansion_procedure_call == null);

	assignment_flags := compiler_get_nodes(#code { for <=(flag = enabled) values process(it); }).(*Code_Block).statements[0].(*Code_For);
	assert(assignment_flags.want_reverse_expression.kind == .BINARY_OPERATOR);
	assert(assignment_flags.iteration_expression.(*Code_Ident).name == "values");

	comparison_collection := compiler_get_nodes(#code { for <=reverse left == right process(it); }).(*Code_Block).statements[0].(*Code_For);
	assert(comparison_collection.want_reverse_expression.(*Code_Ident).name == "reverse");
	assert(comparison_collection.iteration_expression.(*Code_Binary_Operator).operator_type == .IS_EQUAL);

	assignment_collection := compiler_get_nodes(#code { for <=reverse target = source process(it); }).(*Code_Block).statements[0].(*Code_For);
	assert(assignment_collection.want_reverse_expression.(*Code_Ident).name == "reverse");
	assert(assignment_collection.iteration_expression.(*Code_Binary_Operator).operator_type == #char "=");
	assert_statement_fixture("if ready then run(); else stop();");
	assert_statement_fixture("if (mode == .ALLOCATE) && (size == 42) { run(); }");
	assert_statement_fixture("if (count % 2) { run(); }");
	assert_statement_fixture("if (pointer) { run(); }");
	assert_statement_fixture("if x > 0 then #this(x-1);");
	assert_statement_fixture("value := ifx ready { prepare(); 1; } else { 2; }");
	assert_statement_fixture("value := ifx ready then 1;");
	assert_statement_fixture("value := ifx ready else 1;");
	assert_statement_fixture("value := ifx ready;");
	assert_statement_fixture("value := ifx ready { 1; } else { 2; };");
	assert_statement_fixture("value := #ifx ready then 1 else 2;");
	assert_statement_fixture("if value == { case 1; return; case; break; }");
	assert_statement_fixture("if #complete value == { case 1; #through; case 2; return; case; return; }");
	assert_statement_fixture("#if OS == { case .WINDOWS; return; case; }");
	assert_statement_fixture("#if true { inline memcpy_v3(dest, source, bytes); }");
	assert_statement_fixture("Fixture_Static_Enum :: enum { BASE; #if true { BLORPLE; #if false { HIDDEN; } else VISIBLE; } else FALLBACK; AFTER; }");
	assert_statement_fixture("defer cleanup();");
	assert_statement_fixture("`defer cleanup();");
	assert_statement_fixture("defer { cleanup(); }");
	assert_statement_fixture("#run { compile_step(); }");
	assert_statement_fixture("#run { compile_step(); };");
	assert_statement_fixture("#run compute();");
	assert_statement_fixture("#assert(true);");
	assert_statement_fixture("#assert ready \"not ready\";");
	assert_statement_fixture("#if true { #assert !(flags & .REVERSE) \"reverse unsupported\"; }");
	assert_statement_fixture("using state;");
	assert_statement_fixture("using enum u16 { CHOCOLATE :: 0; VANILLA; }");
	assert_statement_fixture("using enum u16 { VANILLA; };");
	assert_statement_fixture(#string JAI
text :: #string END
body
END
JAI
	);
	assert_statement_fixture("using local: State;");
	assert_statement_fixture("using,except(x, y, z) orientation: Quaternion;");
	assert_statement_fixture("using,except .[\"x\", \"y\", \"z\"] orientation: Quaternion;");
	assert_statement_fixture("using,except SKIP_THESE orientation: Quaternion;");
	assert_statement_fixture("using,except #run conflicting_names(Person, Business) business: Business;");
	assert_statement_fixture("using,only(w, y) orientation: Quaternion;");
	assert_statement_fixture("using,only(w) q;");
	assert_statement_fixture("using,except(Node) Trees :: #import,file \"trees.jai\";");
	assert_statement_fixture("using,map(prefix_with_gl) procs: Procs;");
	assert_statement_fixture("push_context new_context { return; }");
	assert_statement_fixture("push_context { return; }");
	assert_statement_fixture("`push_context,defer_pop remap_context();");
}

count_syntax_tests :: () -> s64 {
	previous_progress := differential_progress;
	differential_progress = .{counting=true};
	test_syntax_fixtures();
	total := differential_progress.test_total;
	differential_progress = previous_progress;
	return total;
}

collect_differential_sections :: () -> [DIFFERENTIAL_SECTION_TOTAL] Differential_Section {
	previous_progress := differential_progress;
	differential_progress = .{planning=true};
	run_compile_time_sections();
	begin_differential_section("Runtime checks", RUNTIME_TEST_TOTAL);
	assert(differential_progress.section_index == DIFFERENTIAL_SECTION_TOTAL);
	sections := differential_progress.sections;
	differential_progress = previous_progress;
	return sections;
}

run_compile_time_sections :: () {
	if begin_differential_section("Context syntax", CONTEXT_TEST_TOTAL) {
		begin_differential_test();
		test_context_modification_compiler_shape();
		finish_differential_test();
	}
	if begin_differential_section("Syntax fixtures", SYNTAX_TEST_TOTAL) {
		test_syntax_fixtures();
	}

	test_typechecked_workspace_fixture();
	test_file_workspace_fixtures();
	test_typed_integer_fixtures();
	test_assembly_context_fixtures();
	test_pair_member_fixtures();
	test_member_query_fixtures();
	test_member_access_fixtures();
	test_default_overload_fixtures();
	test_floating_literal_fixtures();
	test_integer_float32_fixtures();
	test_integer_rounding_fixture();
	test_numeric_rank_fixtures();
	test_candidate_permutation_fixtures();
	test_invalid_integer_fixtures();
	test_unsigned_boundary_fixtures();
	test_signed_boundary_fixtures();
	test_aggregate_member_fixtures();
	test_declaration_workspace_fixtures();
	test_directive_workspace_fixtures();
	test_assignment_workspace_fixtures();
	finish_differential_section();
	assert(differential_progress.section_index == DIFFERENTIAL_SECTION_TOTAL - 1);
}

#run,stallable {
	previous_assertion_handler = context.assertion_failed;
	context.assertion_failed = differential_assertion_failed;
	defer context.assertion_failed = previous_assertion_handler;

	if prepare_differential_run(COMPILED_SECTION) {
		run_compile_time_sections();
		cleanup_differential_fixture();
		expected_total := differential_progress.global_total;
		if section_is_selected(COMPILED_SECTION, "Runtime checks", DIFFERENTIAL_SECTION_TOTAL) {
			expected_total -= RUNTIME_TEST_TOTAL;
		}

		assert(differential_progress.global_index == expected_total);
		print("\e[32mPASS\e[0m compile-time checks (%/% total tests)\n", differential_progress.global_index, differential_progress.global_total);
	} else {
		set_build_options_dc(.{do_output=false});
	}
}
