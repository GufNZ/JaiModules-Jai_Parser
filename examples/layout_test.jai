#import "Basic";
#import "String";

Original :: #import "Jai_Lexer";

Default		:: #import "Jai_Parser";
Extended	:: #import "Jai_Parser"(ENABLE_TRIVIA=true);
Raw_Strings	:: #import "Jai_Parser"(ENABLE_TRIVIA=true, EVALUATE_STRING_ESCAPES=false);
for_expansion	:: Extended.for_expansion;

#assert(size_of(Default.Token) == size_of(Original.Token));
#assert(size_of(Default.Lexer) == size_of(Original.Lexer));

main :: () {
	default_lexer: Default.Lexer;
	extended_lexer: Extended.Lexer;

	Default.set_input_from_string(*default_lexer, "(.*) <<");
	assert(Default.peek_next_token(*default_lexer).type == .PREFIX_DEREFERENCE);
	Default.eat_token(*default_lexer);
	assert(Default.peek_next_token(*default_lexer).type == .SHIFT_LEFT);

	Default.set_input_from_string(*default_lexer, "( .*)");
	assert(Default.peek_next_token(*default_lexer).type == #char "(");

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
		if !starts_with(name, KEYWORD_PREFIX)	continue;

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

	input := alloc_string(LONG_IDENTIFIER_LENGTH + SUFFIX.count);
	defer free(input);
	for index: 0..LONG_IDENTIFIER_LENGTH-1 {
		input.data[index] = #char "a";
	}
	memcpy(input.data + LONG_IDENTIFIER_LENGTH, SUFFIX.data, SUFFIX.count);

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
	input :: "#string END\nvalue\n   END";
	Extended.set_input_from_string(*lexer, input);

	eat_expected_token(*lexer, #char "#");
	eat_expected_token(*lexer, .IDENT);
	delimiter := eat_expected_token(*lexer, .IDENT);
	token := Extended.parse_here_string_body(*lexer, delimiter.ident_value.name);
	assert(token.type == .STRING);
	assert(token.string_value == "value\n");
	assert(token.preceding_trivia == "\n");
	assert(token.original_text == "value\n");
	terminator := eat_expected_token(*lexer, .IDENT);
	assert(terminator.ident_value.name == "END");
	assert(terminator.preceding_trivia == "   ");
	assert(terminator.original_text == "END");

	empty_input :: "#string END\nEND";
	Extended.set_input_from_string(*lexer, empty_input);
	eat_expected_token(*lexer, #char "#");
	eat_expected_token(*lexer, .IDENT);
	delimiter = eat_expected_token(*lexer, .IDENT);
	token = Extended.parse_here_string_body(*lexer, delimiter.ident_value.name);
	assert(token.type == .STRING);
	assert(token.string_value == "");
	assert(token.preceding_trivia == "\n");
	assert(token.original_text == "");
	terminator = eat_expected_token(*lexer, .IDENT);
	assert(terminator.ident_value.name == "END");
	assert(terminator.preceding_trivia == "");
	assert(terminator.original_text == "END");

	unterminated_input :: "\n    X";
	Extended.set_input_from_string(*lexer, unterminated_input);
	lexer.input.count -= 2;
	token = Extended.parse_here_string_body(*lexer, "END");
	assert(token == null);
	assert(lexer.reported_error);
}

test_here_string_percent_modifier :: () {
	lexer: Extended.Lexer;
	input :: "#string,\\% END\nvalue % \\% unchanged\nEND";
	Extended.set_input_from_string(*lexer, input);

	eat_expected_token(*lexer, #char "#");
	eat_expected_token(*lexer, .IDENT);
	eat_expected_token(*lexer, #char ",");
	modifier := eat_expected_token(*lexer, .IDENT);
	assert(modifier.ident_value.name == "\\%");
	delimiter := eat_expected_token(*lexer, .IDENT);
	token := Extended.parse_here_string_body(*lexer, delimiter.ident_value.name);
	assert(token.type == .STRING);
	assert(token.string_value == "value % \\% unchanged\n");
	assert(!lexer.reported_error);

	combined_input :: "#string,cr,\\% END\nvalue %\nEND";
	Extended.set_input_from_string(*lexer, combined_input);
	eat_expected_token(*lexer, #char "#");
	eat_expected_token(*lexer, .IDENT);
	eat_expected_token(*lexer, #char ",");
	eat_expected_token(*lexer, .IDENT);
	eat_expected_token(*lexer, #char ",");
	modifier = eat_expected_token(*lexer, .IDENT);
	assert(modifier.ident_value.name == "\\%");
	delimiter = eat_expected_token(*lexer, .IDENT);
	token = Extended.parse_here_string_body(*lexer, delimiter.ident_value.name, want_cr=true);
	assert(token.type == .STRING);
	assert(token.string_value == "value %\r\n");
	assert(!lexer.reported_error);
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

	body := Extended.parse_here_string_body(*lexer, delimiter.ident_value.name, want_cr=true);
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
