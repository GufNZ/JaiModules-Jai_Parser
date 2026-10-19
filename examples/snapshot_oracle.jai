#import "Hash_Table";

Oracle_Pending :: struct {
	info: *Type_Info;
	actual: *void;
	expected: *void;
	path: string;
}

Oracle_State :: struct {
	forward: Table(*void, *void);
	reverse: Table(*void, *void);
	pending: [..]Oracle_Pending;
	error: string;
}

oracle_fail :: (state: *Oracle_State, path: string, reason: string) -> bool {
	if !state.error {
		state.error = sprint("%: %", path, reason);
	}

	return false;
}

Oracle_Node_Type :: struct {
	kind: type_of(Parser.Parser_Node.kind);
	info: *Type_Info_Struct;
}

#insert -> string {
	builder: String_Builder;
	print(*builder, "ORACLE_NODE_TYPES :: Oracle_Node_Type.[\n");
	print(*builder, ".{.DIRECTIVE_THIS, type_info(Parser.Parser_Node)},\n");

	for Parser.TYPES {
		name := it.(*Type_Info_Struct).name;
		suffix := slice(name, 5, name.count - 5);
		upper := copy_string(suffix);
		defer free(upper);
		for *upper {
			if it.* >= #char "a" && it.* <= #char "z" {
				it.* -= #char "a" - #char "A";
			}
		}

		print(*builder, ".{.%, type_info(Parser.Parser_%)},\n", upper, suffix);
	}

	print(*builder, "];\n");
	return builder_to_string(*builder);
}

oracle_token :: (state: *Oracle_State, actual: *Parser.Token, expected: *Parser.Token, path: string) -> bool {
	if (actual.type != expected.type
		|| actual.value_flags != expected.value_flags
		|| actual.ident_is_backticked != expected.ident_is_backticked
		|| actual.l0 != expected.l0 || actual.c0 != expected.c0
		|| actual.l1 != expected.l1 || actual.c1 != expected.c1
		|| actual.original_text != expected.original_text
		|| actual.preceding_trivia != expected.preceding_trivia
		|| actual.trailing_trivia != expected.trailing_trivia
	) {
		return oracle_fail(state, path, "token metadata/text differs");
	}


	if actual.type == {
		case .IDENT; #through;
		case .NOTE;
			if actual.ident_value.name != expected.ident_value.name || actual.ident_value.hash != expected.ident_value.hash {
				return oracle_fail(state, path, "identifier payload differs");
			}

		case .STRING;
			if actual.string_value != expected.string_value {
				return oracle_fail(state, path, "decoded string differs");
			}

		case .NUMBER;
			if actual.integer_value != expected.integer_value {
				return oracle_fail(state, path, "numeric payload bits differ");
			}
	}


	return true;
}

oracle_overlay :: (state: *Oracle_State, root: *Type_Info_Struct, info: *Type_Info_Struct, actual: *u8, expected: *u8, base_offset: s64, path: string) -> bool {
	for member: info.members {
		if member.offset_in_bytes < 0 || member.flags & .CONSTANT {
			continue;
		}


		if info.name == "Code_Literal" && member.name == "values" {
			continue;
		}


		overridden := false;
		for replacement: root.members {
			if replacement.flags & .OVERLAY && !starts_with(replacement.name, "_Code_")
				&& replacement.offset_in_bytes == base_offset + member.offset_in_bytes {
				overridden = true;
				break;
			}
		}

		if overridden {
			continue;
		}


		child_path := tprint("%.%", path, member.name);
		if !oracle_value(state, member.type, actual + member.offset_in_bytes, expected + member.offset_in_bytes, child_path) {
			return false;
		}
	}


	return true;
}

oracle_literal :: (state: *Oracle_State, actual: *Parser.Parser_Literal, expected: *Parser.Parser_Literal, path: string) -> bool {
	if actual.value_type != expected.value_type || actual.value_flags != expected.value_flags {
		return oracle_fail(state, path, "literal discriminator/flags differ");
	}


	if actual.value_type == {
		case .STRING;
			return oracle_value(state, type_info(string), *actual._string, *expected._string, tprint("%._string", path));

		case .ARRAY;
			return oracle_value(state, type_info(*Parser.Parser_Array_Literal_Info), *actual.array_literal_info, *expected.array_literal_info, tprint("%.array_literal_info", path));

		case .STRUCT;
			return oracle_value(state, type_info(*Parser.Parser_Struct_Literal_Info), *actual.struct_literal_info, *expected.struct_literal_info, tprint("%.struct_literal_info", path));

		case .POINTER;
			return oracle_value(state, type_info(type_of(actual.pointer_literal_info)), *actual.pointer_literal_info, *expected.pointer_literal_info, tprint("%.pointer_literal_info", path));

		case .NUMBER; #through;
		case .BOOLEAN; #through;
		case .UNINITIALIZED;
			return actual._u64 == expected._u64 || oracle_fail(state, path, "literal payload bits differ");

		case;
			return oracle_fail(state, path, "unhandled literal discriminator");
	}
}

oracle_value :: (state: *Oracle_State, info: *Type_Info, actual: *void, expected: *void, path: string) -> bool {
	mark := get_temporary_storage_mark();
	defer set_temporary_storage_mark(mark);

	if info.type == {
		case .STRING;
			return actual.(*string).* == expected.(*string).* || oracle_fail(state, path, "string differs");

		case .VARIANT;
			return oracle_value(state, info.(*Type_Info_Variant).variant_of, actual, expected, path);

		case .INTEGER; #through;
		case .FLOAT; #through;
		case .BOOL; #through;
		case .ENUM;
			for 0..info.runtime_size - 1 {
				if actual.(*u8)[it] != expected.(*u8)[it] {
					return oracle_fail(state, path, "scalar bits differ");
				}
			}


			return true;

		case .ARRAY;
			array := info.(*Type_Info_Array);
			count := array.array_count;
			left := actual.(*u8);
			right := expected.(*u8);
			if array.array_type != .FIXED {
				left_view := actual.(*[]u8);
				right_view := expected.(*[]u8);
				if left_view.count != right_view.count {
					return oracle_fail(state, path, tprint("array count differs (% vs %)", left_view.count, right_view.count));
				}

				count = left_view.count;
				left = left_view.data;
				right = right_view.data;
			}

			for 0..count - 1 {
				offset := it * array.element_type.runtime_size;
				if !oracle_value(state, array.element_type, left + offset, right + offset, tprint("%[%]", path, it)) {
					return false;
				}
			}


			return true;

		case .POINTER;
			left := actual.(**void).*;
			right := expected.(**void).*;
			if !left || !right {
				return left == right || oracle_fail(state, path, "pointer presence differs");
			}

			pointee := info.(*Type_Info_Pointer).pointer_to;
			if pointee.type != .STRUCT {
				return oracle_fail(state, path, "unhandled non-null pointer type");
			}

			structure := pointee.(*Type_Info_Struct);
			is_node := structure == type_info(Parser.Parser_Node);
			for entry: ORACLE_NODE_TYPES {
				if entry.info == structure {
					is_node = true;
				}
			}

			if is_node {
				if left.(*Parser.Parser_Node).kind != right.(*Parser.Parser_Node).kind {
					return oracle_fail(state, path, "node kind differs");
				}


				structure = null;
				for entry: ORACLE_NODE_TYPES {
					if entry.kind == left.(*Parser.Parser_Node).kind {
						structure = entry.info;
						break;
					}
				}

				if !structure {
					return oracle_fail(state, path, tprint("unhandled node kind %", left.(*Parser.Parser_Node).kind));
				}
			} else if !starts_with(structure.name, "Parser_") && structure.name != "Code_Pointer_Literal_Info" {
				return oracle_fail(state, path, tprint("unhandled pointer to %", structure.name));
			}


			found, mapped := table_find(*state.forward, left);
			if found {
				return mapped == right || oracle_fail(state, path, "binding/ownership alias differs");
			}


			found_reverse, previous := table_find(*state.reverse, right);
			if found_reverse {
				return oracle_fail(state, path, "binding/ownership target is not snapshot-local");
			}


			if left == right {
				return oracle_fail(state, path, "snapshots share an owned object");
			}


			table_add(*state.forward, left, right);
			table_add(*state.reverse, right, left);
			array_add(*state.pending, Oracle_Pending.{info = structure, actual = left, expected = right, path = copy_string(path)});
			return true;

		case .STRUCT;
			structure := info.(*Type_Info_Struct);
			if structure == type_info(Parser.Token) {
				return oracle_token(state, xx actual, xx expected, path);
			}


			if structure == type_info(Code_Pointer_Literal_Info) {
				left := actual.(*Code_Pointer_Literal_Info);
				right := expected.(*Code_Pointer_Literal_Info);
				if left.pointer_literal_type != .CONSTANT_VALUE || right.pointer_literal_type != .CONSTANT_VALUE {
					return oracle_fail(state, path, "unhandled pointer-literal discriminator");
				}


				return	!left.global_symbol
						&& !right.global_symbol
						&& !left.data_pointer
						&& !right.data_pointer
						&& left.offset_from_symbol == right.offset_from_symbol
					|| oracle_fail(state, path, "constant pointer-literal payload differs");
			}


			if structure.textual_flags & .UNION {
				return oracle_fail(state, path, "unhandled union");
			}


			for member: structure.members {
				if member.offset_in_bytes < 0 || member.flags & .CONSTANT || member.name == "_padding" {
					continue;
				}


				if structure == type_info(Parser.Parser_Literal) && (member.name == "array_literal_info" || member.name == "struct_literal_info") {
					continue;
				}


				left := actual.(*u8) + member.offset_in_bytes;
				right := expected.(*u8) + member.offset_in_bytes;
				child_path := tprint("%.%", path, member.name);
				if starts_with(member.name, "_Code_") {
					if !oracle_overlay(state, structure, member.type.(*Type_Info_Struct), left, right, member.offset_in_bytes, child_path) {
						return false;
					}
				} else if !oracle_value(state, member.type, left, right, child_path) {
					return false;
				}
			}


			if structure == type_info(Parser.Parser_Literal) {
				return oracle_literal(state, xx actual, xx expected, path);
			}


			return true;

		case;
			return oracle_fail(state, path, "unhandled reflected value type");
	}
}

oracle_field :: (state: *Oracle_State, actual: *$T, expected: *T, path: string) -> bool {
	return oracle_value(state, type_info(T), actual, expected, path);
}

check_snapshot :: (actual: *Parser.Parsed_Source, expected: *Parser.Parsed_Source, expect_match: bool = true) {
	storage: Pool;
	set_allocators(*storage);
	defer release(*storage);

	push_allocator(.{proc = pool_allocator_proc, data = *storage});
	state: Oracle_State;

	matched := oracle_field(*state, *actual.source, *expected.source, "source")
		&& oracle_field(*state, *actual.fully_pathed_filename, *expected.fully_pathed_filename, "filename")
		&& oracle_field(*state, *actual.status, *expected.status, "status")
		&& oracle_field(*state, *actual.tokens, *expected.tokens, "tokens")
		&& oracle_field(*state, *actual.synthetic_tokens, *expected.synthetic_tokens, "synthetic_tokens")
		&& oracle_field(*state, *actual.diagnostics, *expected.diagnostics, "diagnostics")
		&& oracle_field(*state, *actual.recovery_records, *expected.recovery_records, "recovery")
		&& oracle_field(*state, *actual.restart_points, *expected.restart_points, "restart")
		&& oracle_field(*state, *actual.root, *expected.root, "root")
		&& oracle_field(*state, *actual.root_scope, *expected.root_scope, "root_scope");

	cursor: s64;
	while matched && cursor < state.pending.count {
		entry := state.pending[cursor];
		matched = oracle_value(*state, entry.info, entry.actual, entry.expected, entry.path);
		cursor += 1;
	}

	if !matched && expect_match {
		print("Snapshot mismatch: %\n", state.error);
	}

	assert(matched == expect_match, "Snapshot oracle self-check or comparison failed.");
	if expect_match {
		assert(Parser.reconstruct_source(actual) == expected.source);
	}
}

test_snapshot_oracle :: () {
	storage: Pool;
	set_allocators(*storage);
	defer release(*storage);

	push_allocator(.{proc = pool_allocator_proc, data = *storage});
	SOURCE :: "value :: 1; value :: 1; result := value; items :: .[1, 2]; text :: \"hello\"; access := result.member; #if true { inner :: value; }";
	actual := Parser.parse_file(SOURCE);
	expected := Parser.parse_file(SOURCE);
	defer Parser.release_parser_tree(*actual);
	defer Parser.release_parser_tree(*expected);

	assert(actual.status == .COMPLETE && expected.status == .COMPLETE);
	check_snapshot(*actual, *expected);
	root := actual.root.(*Parser.Parser_Block);
	declaration := root.statements[0].(*Parser.Parser_Declaration);
	second_declaration := root.statements[1].(*Parser.Parser_Declaration);
	reference := root.statements[2].(*Parser.Parser_Declaration).expression.(*Parser.Parser_Ident);
	saved_binding := reference.resolved_declaration;
	reference.resolved_declaration = ifx saved_binding == declaration
		then second_declaration
		else declaration;

	assert(saved_binding != reference.resolved_declaration);
	check_snapshot(*actual, *expected, false);
	reference.resolved_declaration = saved_binding;
	root.statements[0] = expected.root.(*Parser.Parser_Block).statements[0];
	check_snapshot(*actual, *expected, false);
	root.statements[0] = declaration;
	root.statements[0] = root.statements[1];
	root.statements[1] = declaration;
	check_snapshot(*actual, *expected, false);
	root.statements[0] = declaration;
	root.statements[1] = second_declaration;
	declaration.node_flags ^= .IS_PARENTHESIZED;
	check_snapshot(*actual, *expected, false);
	declaration.node_flags ^= .IS_PARENTHESIZED;
	declaration.first_token += 1;
	check_snapshot(*actual, *expected, false);
	declaration.first_token -= 1;
	declaration.l0 += 1;
	check_snapshot(*actual, *expected, false);
	declaration.l0 -= 1;
	literal := declaration.expression.(*Parser.Parser_Literal);
	literal._u64 ^= 1;
	check_snapshot(*actual, *expected, false);
	literal._u64 ^= 1;
	text := root.statements[4].(*Parser.Parser_Declaration).expression.(*Parser.Parser_Literal);
	saved_text := text._string;
	text._string = "different";
	check_snapshot(*actual, *expected, false);
	text._string = saved_text;
	array := root.statements[3].(*Parser.Parser_Declaration).expression.(*Parser.Parser_Literal).array_literal_info;
	array.array_members.count -= 1;
	check_snapshot(*actual, *expected, false);
	array.array_members.count += 1;
	actual.tokens[0].ident_value.hash ^= 1;
	check_snapshot(*actual, *expected, false);
	actual.tokens[0].ident_value.hash ^= 1;
	actual.tokens[0].byte_end += 1;
	check_snapshot(*actual, *expected, false);
	actual.tokens[0].byte_end -= 1;
	actual.tokens[3].integer_value ^= 1;
	assert(actual.tokens[3].type == .NUMBER);
	check_snapshot(*actual, *expected, false);
	actual.tokens[3].integer_value ^= 1;
	actual.tokens[0].preceding_trivia = " ";
	check_snapshot(*actual, *expected, false);
	actual.tokens[0].preceding_trivia = "";
	actual.root_scope.member_accesses.count -= 1;
	check_snapshot(*actual, *expected, false);
	actual.root_scope.member_accesses.count += 1;
	child := actual.root_scope.children[0];
	saved_parent := child.parent;
	child.parent = child;
	check_snapshot(*actual, *expected, false);
	child.parent = saved_parent;
	actual.restart_points[0].span.first += 1;
	check_snapshot(*actual, *expected, false);
	actual.restart_points[0].span.first -= 1;
	check_snapshot(*actual, *expected);

	broken := Parser.parse_file("value :: ; next :: 1");
	broken_fresh := Parser.parse_file("value :: ; next :: 1");
	defer Parser.release_parser_tree(*broken);
	defer Parser.release_parser_tree(*broken_fresh);

	assert(broken.diagnostics.count && broken.recovery_records.count && broken.synthetic_tokens.count);
	check_snapshot(*broken, *broken_fresh);
	saved_message := broken.diagnostics[0].message;
	broken.diagnostics[0].message = "different";
	check_snapshot(*broken, *broken_fresh, false);
	broken.diagnostics[0].message = saved_message;
	broken.diagnostics[0].span.first += 1;
	check_snapshot(*broken, *broken_fresh, false);
	broken.diagnostics[0].span.first -= 1;
	broken.recovery_records[0].diagnostic_index += 1;
	check_snapshot(*broken, *broken_fresh, false);
	broken.recovery_records[0].diagnostic_index -= 1;
	broken.synthetic_tokens[0].insertion_index += 1;
	check_snapshot(*broken, *broken_fresh, false);
	broken.synthetic_tokens[0].insertion_index -= 1;
	check_snapshot(*broken, *broken_fresh);
	actual_related := Parser.Parse_Diagnostic_Info.[.{span = broken.diagnostics[0].span, message = "related"}];
	expected_related := Parser.Parse_Diagnostic_Info.[.{span = broken_fresh.diagnostics[0].span, message = "related"}];
	broken.diagnostics[0].related_information = actual_related;
	broken_fresh.diagnostics[0].related_information = expected_related;
	check_snapshot(*broken, *broken_fresh);
	actual_related[0].message = "changed related information";
	check_snapshot(*broken, *broken_fresh, false);
	actual_related[0].message = "related";
	actual_related[0].span.first += 1;
	check_snapshot(*broken, *broken_fresh, false);
	actual_related[0].span.first -= 1;
	check_snapshot(*broken, *broken_fresh);

	#if VERIFY_ONLY {
		COUNTER_SOURCE :: "object :: 1; left, right :: object.field; work :: () { return; } #if true { nested :: object; }";
		PREFIX :: "// inserted\n";
		old := Parser.parse_file(COUNTER_SOURCE);
		updated, ok := Parser.parse_file_edit(*old, 0, 0, sprint("%%", PREFIX, COUNTER_SOURCE));
		defer Parser.release_parser_tree(*old);
		defer Parser.release_parser_tree(*updated);

		assert(ok && old.status == .COMPLETE && updated.status == .COMPLETE);
		assert(old.reused_declarations == 0 && updated.reused_declarations == 3);
		fresh := Parser.parse_file(updated.source);
		defer Parser.release_parser_tree(*fresh);

		check_snapshot(*updated, *fresh);
	}

	print("Snapshot oracle negative checks and exact simple/compound/nested reuse count PASS\n");
}
