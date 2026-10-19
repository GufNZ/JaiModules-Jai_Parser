// Compare default token layout with Jai_Lexer, then assert token and trivia behaviour using focused inputs under default, trivia-enabled, and raw-string imports.
#import "Basic";
#import "String";
#import "Pool";

#load "test_fixtures.jai";

Original :: #import "Jai_Lexer";

Default		:: #import "Jai_Parser";
Extended	:: #import "Jai_Parser"(ENABLE_TRIVIA = true, USE_SIMD = false);
Raw_Strings	:: #import "Jai_Parser"(ENABLE_TRIVIA = true, EVALUATE_STRING_ESCAPES = false);
Simd		:: #import "Jai_Parser"(ENABLE_TRIVIA = true, USE_SIMD = true);

for_expansion	:: Extended.for_expansion;

#assert(size_of(Default.Token) == size_of(Original.Token));

main :: () {
	default_lexer: Default.Lexer;
	extended_lexer: Extended.Lexer;

	Default.set_input_from_string(*default_lexer, "(.*) <<");
	assert(Default.peek_next_token(*default_lexer).type == .PREFIX_DEREFERENCE);
	Default.eat_token(*default_lexer);
	assert(Default.peek_next_token(*default_lexer).type == .SHIFT_LEFT);

	Default.set_input_from_string(*default_lexer, "( .*)");
	assert(Default.peek_next_token(*default_lexer).type == #char "(");

	Default.set_input_from_string(*default_lexer, "\xEF\xBB\xBFvalue");
	assert(Default.peek_next_token(*default_lexer).ident_value.name == "value");
	assert(Default.peek_next_token(*default_lexer).c0 == 1);

	input :: " \tfoo\\  bar /* outer /* inner */ end */ 1_000 (.*) ptr // tail";
	Extended.set_input_from_string(*extended_lexer, input);

	token := Extended.peek_next_token(*extended_lexer);
	assert(token.type == .IDENT);
	assert(token.ident_value.name == "foobar");
	assert(token.original_text == "foo\\  bar");
	assert(token.preceding_trivia == " \t");
	Extended.eat_token(*extended_lexer);

	token = Extended.peek_next_token(*extended_lexer);
	assert(token.type == .NUMBER);
	assert(token.integer_value == 1000);
	assert(token.original_text == "1_000");
	assert(token.preceding_trivia == " /* outer /* inner */ end */ ");
	Extended.eat_token(*extended_lexer);

	token = Extended.peek_next_token(*extended_lexer);
	assert(token.type == .PREFIX_DEREFERENCE);
	assert(token.original_text == "(.*)");
	assert(token.preceding_trivia == " ");
	Extended.eat_token(*extended_lexer);

	token = Extended.peek_next_token(*extended_lexer);
	assert(token.type == .IDENT);
	assert(token.original_text == "ptr");
	assert(token.preceding_trivia == " ");
	Extended.eat_token(*extended_lexer);

	token = Extended.peek_next_token(*extended_lexer);
	assert(token.type == .END_OF_INPUT);
	assert(token.trailing_trivia == " // tail");

	test_structured_trivia(*extended_lexer);
	test_eof_location();
	test_utf8_columns();
	test_long_identifier();
	test_here_string_bounds();
	test_here_string_percent_modifier();
	test_directive_trivia_round_trip();
	test_raw_string_tokens();
	test_keyword_table_completeness();
	test_simd_identifier_masks(16);
	test_simd_identifier_masks(32);
	test_simd_identifier_masks(64);
	test_simd_identifier_tokens();
	test_simd_line_comments();
	test_simd_diagnostics_and_truncations();
	print("Scalar/SIMD token and comment parity PASS.\n");
}

Simd_Diagnostic :: struct {
	message: string;
	line: s32;
	column: s32;
	is_detail: bool;
}

test_simd_diagnostics_and_truncations :: () {
	comparisons: s64;
	diagnostics: s64;
	for suffix: string.[
		" := \"line\\n\\x41\"; next := 1.23456789;",
		" := \"bad\\q\"; next := 1;",
		" := \"bad\\xG0\"; next := 1;",
		" := \"unterminated\nnext := 1;",
		" /* outer /* inner */ unfinished",
		" // comment with \xE2\x80\x8B bytes\r\nnext := 1;",
		" := 0x; next := 1e+;",
		"\xFF next := 1;",
		"\x00next := 1;",
		"\\  tail := \"value\";",
		" :: #string END\nbody\nEND\nnext := 1;",
		" :: () { value := \"text\"; if true { return; } }",
	] {
		for length: s64.[15, 16, 17, 31, 32, 33, 63, 64, 65, 511, 512, 513] {
			input := make_long_identifier_source(length, suffix);
			defer free(input);

			for end: 0..input.count {
				diagnostics += assert_simd_lexer_parity(slice(input, 0, end));
				comparisons += 1;
			}
		}
	}

	assert(diagnostics > 0);
	print("Scalar/SIMD diagnostic and truncation parity PASS: % inputs, % diagnostics.\n", comparisons, diagnostics);
}

assert_simd_lexer_parity :: (input: string) -> s64 {
	storage: Pool;
	set_allocators(*storage);
	defer release(*storage);

	push_allocator(.{proc = pool_allocator_proc, data = *storage});

	expected_diagnostics: [..] Simd_Diagnostic;
	actual_diagnostics: [..] Simd_Diagnostic;
	scalar: Extended.Lexer;
	vectorised: Simd.Lexer;
	scalar.user_data = *expected_diagnostics;
	vectorised.user_data = *actual_diagnostics;
	scalar.error_callback = (lexer: *Extended.Lexer, message: string, line: s32, column: s32) {
		array_add(cast(*[..] Simd_Diagnostic) lexer.user_data, .{message = copy_string(message), line = line, column = column});
	};
	vectorised.error_callback = (lexer: *Simd.Lexer, message: string, line: s32, column: s32) {
		array_add(cast(*[..] Simd_Diagnostic) lexer.user_data, .{message = copy_string(message), line = line, column = column});
	};
	scalar.detail_callback = (lexer: *Extended.Lexer, message: string) {
		array_add(cast(*[..] Simd_Diagnostic) lexer.user_data, .{message = copy_string(message), line = lexer.current_line_number, column = lexer.current_character_index, is_detail = true});
	};
	vectorised.detail_callback = (lexer: *Simd.Lexer, message: string) {
		array_add(cast(*[..] Simd_Diagnostic) lexer.user_data, .{message = copy_string(message), line = lexer.current_line_number, column = lexer.current_character_index, is_detail = true});
	};
	Extended.set_input_from_string(*scalar, input);
	Simd.set_input_from_string(*vectorised, input);

	while true {
		expected := Extended.peek_next_token(*scalar);
		actual := Simd.peek_next_token(*vectorised);
		assert(actual.type.(s64) == expected.type.(s64));
		assert(actual.value_flags.(u32) == expected.value_flags.(u32));
		assert(actual.ident_is_backticked == expected.ident_is_backticked);
		assert(actual.l0 == expected.l0 && actual.c0 == expected.c0);
		assert(actual.l1 == expected.l1 && actual.c1 == expected.c1);
		assert(actual.original_text == expected.original_text);
		assert(actual.preceding_trivia == expected.preceding_trivia);
		assert(actual.trailing_trivia == expected.trailing_trivia);

		if expected.type == {
			case .IDENT;
				assert(actual.ident_value.name == expected.ident_value.name);
				assert(actual.ident_value.hash == expected.ident_value.hash);
			case .STRING;
				assert(actual.string_value == expected.string_value);
			case .NUMBER;
				assert(actual.integer_value == expected.integer_value);
		}

		if expected.type == .END_OF_INPUT {
			break;
		}


		Extended.eat_token(*scalar);
		Simd.eat_token(*vectorised);
	}
	assert(vectorised.reported_error == scalar.reported_error);
	assert(actual_diagnostics.count == expected_diagnostics.count);
	for expected, index: expected_diagnostics {
		actual := actual_diagnostics[index];
		assert(actual.message == expected.message);
		assert(actual.line == expected.line && actual.column == expected.column);
		assert(actual.is_detail == expected.is_detail);
	}

	expected_parse := Extended.parse_file(input);
	defer Extended.release_parser_tree(*expected_parse);

	actual_parse := Simd.parse_file(input);
	defer Simd.release_parser_tree(*actual_parse);

	assert(actual_parse.status.(s64) == expected_parse.status.(s64));
	assert(actual_parse.tokens.count == expected_parse.tokens.count);
	assert(actual_parse.diagnostics.count == expected_parse.diagnostics.count);

	for expected, index: expected_parse.diagnostics {
		actual := actual_parse.diagnostics[index];
		assert(actual.kind.(s64) == expected.kind.(s64));
		assert(actual.severity.(s64) == expected.severity.(s64));
		assert(actual.span.first.(s64) == expected.span.first.(s64));
		assert(actual.span.one_past_last.(s64) == expected.span.one_past_last.(s64));
		assert(actual.message == expected.message);
		assert(actual.lexer_line == expected.lexer_line && actual.lexer_column == expected.lexer_column);
		assert(actual.expected_token.(s64) == expected.expected_token.(s64));
		assert(actual.actual_token.(s64) == expected.actual_token.(s64));
		assert(actual.recovery_action.(s64) == expected.recovery_action.(s64));
		assert(actual.related_information.count == expected.related_information.count);

		for expected_info, info_index: expected.related_information {
			actual_info := actual.related_information[info_index];
			assert(actual_info.span.first.(s64) == expected_info.span.first.(s64));
			assert(actual_info.span.one_past_last.(s64) == expected_info.span.one_past_last.(s64));
			assert(actual_info.message == expected_info.message);
		}
	}

	assert(actual_parse.recovery_records.count == expected_parse.recovery_records.count);

	for expected, index: expected_parse.recovery_records {
		actual := actual_parse.recovery_records[index];
		assert(actual.kind.(s64) == expected.kind.(s64));
		assert(actual.span.first.(s64) == expected.span.first.(s64));
		assert(actual.span.one_past_last.(s64) == expected.span.one_past_last.(s64));
		assert(actual.diagnostic_index == expected.diagnostic_index);
		assert(actual.synthetic_token_index == expected.synthetic_token_index);
	}

	assert(actual_parse.synthetic_tokens.count == expected_parse.synthetic_tokens.count);
	return expected_diagnostics.count;
}

test_simd_line_comments :: () {
	input: [192] u8;
	for offset: 0..63 {
		for length: s64.[0, 1, 15, 16, 17, 31, 32, 33, 63, 64, 65, 127, 128, 129] {
			for stop: -1..length-1 {
				for terminator: u8.[0, #char "\n"] {
					for *input {
						it.* = #char "x";
					}

					if stop >= 0 {
						input[offset + stop] = terminator;
					}

					source := string.{data = input.data, count = offset + length};
					scalar: Extended.Lexer;
					vectorised: Simd.Lexer;
					Extended.set_input_from_string(*scalar, source);
					Simd.set_input_from_string(*vectorised, source);
					scalar.input_cursor = offset;
					vectorised.input_cursor = offset;
					scalar.current_character_index = xx (offset + 1);
					vectorised.current_character_index = xx (offset + 1);
					Extended.eat_until_newline(*scalar);
					Simd.eat_until_newline(*vectorised);
					assert(vectorised.input_cursor == scalar.input_cursor);
					assert(vectorised.current_character_index == scalar.current_character_index);
					assert(vectorised.current_line_number == scalar.current_line_number);
					assert(vectorised.total_lines_processed == scalar.total_lines_processed);
				}
			}
		}
	}
}

test_simd_identifier_tokens :: () {
	for length: s64.[1, 15, 16, 17, 31, 32, 33, 63, 64, 65, 127, 128, 129, 447, 448, 449, 495, 496, 497, 510, 511, 512, 513, 520] {
		for suffix: string.["", "; next", "\\  tail next", "\xE2\x80\x8B next", "// tail\nnext", "1_9Z next"] {
			input := make_long_identifier_source(length, suffix);
			defer free(input);

			scalar: Extended.Lexer;
			vectorised: Simd.Lexer;
			scalar.error_callback = (lexer: *Extended.Lexer, message: string, line: s32, column: s32) {};
			vectorised.error_callback = (lexer: *Simd.Lexer, message: string, line: s32, column: s32) {};

			Extended.set_input_from_string(*scalar, input);
			Simd.set_input_from_string(*vectorised, input);

			while true {
				expected := Extended.peek_next_token(*scalar);
				actual := Simd.peek_next_token(*vectorised);
				assert(actual.type.(s64) == expected.type.(s64));
				assert(actual.value_flags.(u32) == expected.value_flags.(u32));
				assert(actual.ident_is_backticked == expected.ident_is_backticked);
				assert(actual.l0 == expected.l0 && actual.c0 == expected.c0);
				assert(actual.l1 == expected.l1 && actual.c1 == expected.c1);
				assert(actual.original_text == expected.original_text);
				assert(actual.preceding_trivia == expected.preceding_trivia);
				assert(actual.trailing_trivia == expected.trailing_trivia);
				if expected.type == .IDENT {
					assert(actual.ident_value.name == expected.ident_value.name);
					assert(actual.ident_value.hash == expected.ident_value.hash);
				}

				if expected.type == .END_OF_INPUT {
					break;
				}


				Extended.eat_token(*scalar);
				Simd.eat_token(*vectorised);
			}

			assert(vectorised.reported_error == scalar.reported_error);
		}
	}
}

test_simd_identifier_masks :: ($width: s64) {
	#assert(width == 16 || width == 32 || width == 64);
	#if Simd.SIMD_AVAILABLE {
		features := Simd.get_simd_features();
		if (
			(width == 32 && (features & .AVX2) == .NONE)
			|| (width == 64 && (features & .AVX512) == .NONE)
		) {
			print("SIMD classifier width % SKIPPED: CPU/OS support unavailable.\n", width);
			return;
		}


		alignments := #ifx width == 64
			then 64
			else 32;

		input: [128] u8;
		for *input {
			it.* = #char "a";
		}

		for offset: 0..alignments-1 {
			for position: 0..width-1 {
				for byte: 0..255 {
					input[offset + position] = xx byte;
					expected: u64 = 0;
					if !Extended.continues_identifier(xx byte) {
						expected = cast(u64, 1) << position;
					}

					actual: u64;
					#if width == 64 {
						actual = Simd.identifier_avx512_stop_mask(input.data + offset);
					} else #if width == 32 {
						actual = Simd.identifier_avx2_stop_mask(input.data + offset);
					} else {
						actual = Simd.identifier_simd_stop_mask(input.data + offset);
					}

					assert(actual == expected, "SIMD identifier classification differs at width %, offset %, position %, byte %.", width, offset, position, byte);
				}

				input[offset + position] = #char "a";
			}
		}
		print("SIMD classifier width % parity PASS.\n", width);
	}
}

test_raw_string_tokens :: () {
	input :: "\"line\\n\\x41\"";

	evaluated: Extended.Lexer;
	Extended.set_input_from_string(*evaluated, input);
	evaluated_token := Extended.peek_next_token(*evaluated);
	assert(evaluated_token.type == .STRING);
	assert(evaluated_token.string_value == "line\nA");
	assert(evaluated_token.original_text == input);

	raw: Raw_Strings.Lexer;
	Raw_Strings.set_input_from_string(*raw, input);
	raw_token := Raw_Strings.peek_next_token(*raw);
	assert(raw_token.type == .STRING);
	assert(!raw_token.string_value);
	assert(raw_token.original_text == input);
}

test_keyword_table_completeness :: () {
	names := enum_names(Extended.Token_Type);
	values := enum_values_as_enum(Extended.Token_Type);
	assert(names.count == values.count);

	for name, index: names {
		KEYWORD_PREFIX :: "KEYWORD_";
		if !starts_with(name, KEYWORD_PREFIX) {
			continue;
		}

		expected := values[index];
		spelling := ifx expected == .KEYWORD_AUTO_CAST
			then "xx"
			else to_lower_copy(slice(name, KEYWORD_PREFIX.count, name.count - KEYWORD_PREFIX.count));

		lexer: Extended.Lexer;
		Extended.set_input_from_string(*lexer, spelling);
		token := Extended.peek_next_token(*lexer);
		assert(token.type == expected, "Keyword '%' lexed as %, expected %.", spelling, token.type, expected);
		assert(token.ident_value.name == spelling);
	}
}

test_eof_location :: () {
	lexer: Extended.Lexer;
	Extended.set_input_from_string(*lexer, "x\n  ");

	token := Extended.peek_next_token(*lexer);
	assert(token.type == .IDENT);
	Extended.eat_token(*lexer);

	eof := Extended.peek_next_token(*lexer);
	assert(eof.type == .END_OF_INPUT);
	assert(eof.l0 == 2 && eof.c0 == 3);
	assert(eof.l1 == 2 && eof.c1 == 3);
	assert(eof.trailing_trivia == "\n  ");
}

test_utf8_columns :: () {
	lexer: Extended.Lexer;
	Extended.set_input_from_string(*lexer, "\xE2\x80\x8Bvalue");

	token := Extended.peek_next_token(*lexer);
	assert(token.type == .IDENT);
	assert(token.c0 == 4);
	assert(token.c1 == 9);
	assert(token.preceding_trivia == "\xE2\x80\x8B");
}

test_long_identifier :: () {
	LONG_IDENTIFIER_LENGTH :: Extended.MAX_IDENTIFIER_LENGTH + 8;
	SUFFIX :: "\\  tail next";

	input := make_long_identifier_source(LONG_IDENTIFIER_LENGTH, SUFFIX);
	defer free(input);

	lexer: Extended.Lexer;
	Extended.set_input_from_string(*lexer, input);
	token := Extended.peek_next_token(*lexer);
	assert(token.type == .IDENT);
	assert(token.ident_value.name.count == Extended.MAX_IDENTIFIER_LENGTH - 1);
	assert(token.original_text.count == LONG_IDENTIFIER_LENGTH + "\\  tail".count);
	assert(lexer.reported_error);
	Extended.eat_token(*lexer);

	token = Extended.peek_next_token(*lexer);
	assert(token.type == .IDENT);
	assert(token.ident_value.name == "next");
}

test_here_string_bounds :: () {
	lexer: Extended.Lexer;

	Here_String_Bounds_Case :: struct {
		input: string;
		body: string;
		terminator_trivia: string;
	}

	for fixture: Here_String_Bounds_Case.[
		.{"#string END\nvalue\n   END", "value\n", "   "},
		.{"#string END\nEND", "", ""},
	] {
		Extended.set_input_from_string(*lexer, fixture.input);
		eat_expected_token(*lexer, #char "#");
		eat_expected_token(*lexer, .IDENT);
		delimiter := eat_expected_token(*lexer, .IDENT);
		token := Extended.parse_here_string_body(*lexer, delimiter.ident_value.name);
		assert(token.type == .STRING);
		assert(token.string_value == fixture.body);
		assert(token.preceding_trivia == "\n");
		assert(token.original_text == fixture.body);
		terminator := eat_expected_token(*lexer, .IDENT);
		assert(terminator.ident_value.name == "END");
		assert(terminator.preceding_trivia == fixture.terminator_trivia);
		assert(terminator.original_text == "END");
	}

	unterminated_input :: "\n    X";
	Extended.set_input_from_string(*lexer, unterminated_input);

	// Exercise the logical EOF before the end of the backing allocation.
	lexer.input.count -= 2;
	token := Extended.parse_here_string_body(*lexer, "END");
	assert(token == null);
	assert(lexer.reported_error);
}

test_here_string_percent_modifier :: () {
	lexer: Extended.Lexer;

	for want_cr: bool.[false, true] {
		input := ifx want_cr
			then "#string,cr,\\% END\nvalue % \\%\nEND"
			else "#string,\\% END\nvalue % \\% unchanged\nEND";
		expected := ifx want_cr
			then "value % \x1f\r\n"
			else "value % \x1f unchanged\n";

		Extended.set_input_from_string(*lexer, input);
		eat_expected_token(*lexer, #char "#");
		eat_expected_token(*lexer, .IDENT);
		eat_expected_token(*lexer, #char ",");
		if want_cr {
			cr_modifier := eat_expected_token(*lexer, .IDENT);
			assert(cr_modifier.ident_value.name == "cr");
			eat_expected_token(*lexer, #char ",");
		}

		modifier := eat_expected_token(*lexer, .IDENT);
		assert(modifier.ident_value.name == "\\%");
		delimiter := eat_expected_token(*lexer, .IDENT);
		token := Extended.parse_here_string_body(*lexer, delimiter.ident_value.name, want_cr = want_cr, want_percent = true);
		assert(token.type == .STRING);
		assert(token.string_value == expected);
		assert(!lexer.reported_error);
	}
}

test_directive_trivia_round_trip :: () {
	source :: "str :: #string /**/ , /**/ cr /**/ , /**/ \\% END\n123\nEND;";

	lexer: Extended.Lexer;
	Extended.set_input_from_string(*lexer, source);

	source_cursor: s64;
	eat_expected_source_token(*lexer, source, *source_cursor, .IDENT, "str", "");
	eat_expected_source_token(*lexer, source, *source_cursor, #char ":", ":", " ");
	eat_expected_source_token(*lexer, source, *source_cursor, #char ":", ":", "");
	eat_expected_source_token(*lexer, source, *source_cursor, #char "#", "#", " ");
	eat_expected_source_token(*lexer, source, *source_cursor, .IDENT, "string", "");
	eat_expected_source_token(*lexer, source, *source_cursor, #char ",", ",", " /**/ ");
	eat_expected_source_token(*lexer, source, *source_cursor, .IDENT, "cr", " /**/ ");
	eat_expected_source_token(*lexer, source, *source_cursor, #char ",", ",", " /**/ ");
	modifier := eat_expected_source_token(*lexer, source, *source_cursor, .IDENT, "\\%", " /**/ ");
	assert(modifier.ident_value.name == "\\%");
	delimiter := eat_expected_source_token(*lexer, source, *source_cursor, .IDENT, "END", " ");

	body := Extended.parse_here_string_body(*lexer, delimiter.ident_value.name, want_cr = true, want_percent = true);
	assert(body.type == .STRING);
	assert(body.string_value == "123\r\n");
	assert(body.preceding_trivia == "\n");
	assert(body.original_text == "123\n");
	assert_source_span(source, *source_cursor, body.preceding_trivia);
	assert_source_span(source, *source_cursor, body.original_text);

	terminator := eat_expected_source_token(*lexer, source, *source_cursor, .IDENT, "END", "");
	assert(terminator.ident_value.name == delimiter.ident_value.name);
	eat_expected_source_token(*lexer, source, *source_cursor, #char ";", ";", "");
	eof := Extended.peek_next_token(*lexer);
	assert(eof.type == .END_OF_INPUT);
	assert_source_span(source, *source_cursor, eof.trailing_trivia);

	assert(source_cursor == source.count);
	assert(!lexer.reported_error);
}

eat_expected_token :: (lexer: *Extended.Lexer, type: Extended.Token_Type) -> Extended.Token {
	token := Extended.peek_next_token(lexer);
	assert(token.type == type);
	result := token.*;
	Extended.eat_token(lexer);
	return result;
}

eat_expected_source_token :: (
	lexer: *Extended.Lexer,
	source: string,
	source_cursor: *s64,
	type: Extended.Token_Type,
	original_text: string,
	preceding_trivia: string,
) -> Extended.Token {
	token := Extended.peek_next_token(lexer);
	assert(token.type == type);
	assert(token.original_text == original_text);
	assert(token.preceding_trivia == preceding_trivia);
	assert_source_span(source, source_cursor, token.preceding_trivia);
	assert_source_span(source, source_cursor, token.original_text);
	result := token.*;
	Extended.eat_token(lexer);
	return result;
}

assert_source_span :: (source: string, cursor: *s64, span: string) {
	if span.count {
		assert(span.data == source.data + cursor.*);
	}

	cursor.* += span.count;
}

test_structured_trivia :: (lexer: *Extended.Lexer) {
	input :: "#!/usr/bin/env jai\r\n// line\r\n/* outer /* inner */ end */\t";
	Extended.set_input_from_string(lexer, input);

	eof := Extended.peek_next_token(lexer);
	assert(eof.type == .END_OF_INPUT);
	assert(eof.trailing_trivia == input);

	expected_kinds: [6] Extended.Trivia_Kind = .[
		Extended.Trivia_Kind.SHEBANG,
		Extended.Trivia_Kind.WHITESPACE,
		Extended.Trivia_Kind.LINE_COMMENT,
		Extended.Trivia_Kind.WHITESPACE,
		Extended.Trivia_Kind.BLOCK_COMMENT,
		Extended.Trivia_Kind.WHITESPACE,
	];
	expected_text: [6] string = .[
		"#!/usr/bin/env jai",
		"\r\n",
		"// line",
		"\r\n",
		"/* outer /* inner */ end */",
		"\t",
	];

	item_index: s64;
	expected_offset: s64;
	for trivia, offset: Extended.make_trivia_iterator(eof.trailing_trivia) {
		assert(item_index < expected_kinds.count);
		assert(trivia.kind == expected_kinds[item_index]);
		assert(trivia.text == expected_text[item_index]);
		assert(trivia.offset == expected_offset);
		assert(offset == expected_offset);

		expected_offset += trivia.text.count;
		item_index += 1;
	}

	assert(item_index == expected_kinds.count);
	assert(expected_offset == input.count);

	ignored_input :: "\xC2\xA0value";
	Extended.set_input_from_string(lexer, ignored_input);
	token := Extended.peek_next_token(lexer);
	assert(token.type == .IDENT);

	count: s64;
	for trivia: Extended.make_trivia_iterator(token.preceding_trivia) {
		assert(trivia.kind == .IGNORED);
		assert(trivia.text == "\xC2\xA0");
		count += 1;
	}

	assert(count == 1);
}
