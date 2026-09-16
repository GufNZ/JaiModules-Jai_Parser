#import "Basic";
#import "File_Utilities";
#import "String";

Parser_Lexer :: #import "Jai_Parser"(ENABLE_TRIVIA=true);

main :: () {
	path := join(#filepath, "../..");
	reduced := path_to_string(reduce_path(parse_path(path)));

	filenames: [..] string;
	visit_files(reduced, true, *filenames, visit);

	lexer: Parser_Lexer.Lexer;
	total_tokens: s64;

	for name: filenames {
		success := Parser_Lexer.set_input_from_file(*lexer, name);
		assert(success);

		source_cursor: s64;
		while 1 {
			token := Parser_Lexer.peek_next_token(*lexer);
			if token.type == .END_OF_INPUT {
				consume_source_span(lexer.input, *source_cursor, token.trailing_trivia);
				break;
			}


			if token.type == #char "#" {
				next := Parser_Lexer.peek_token(*lexer, 1);
				if next.type == .IDENT && next.ident_value.name == "string" {
					consume_here_string(*lexer, *source_cursor, *total_tokens);
					continue;
				}
			}


			consume_source_span(lexer.input, *source_cursor, token.preceding_trivia);
			consume_source_span(lexer.input, *source_cursor, token.original_text);

			Parser_Lexer.eat_token(*lexer);
			total_tokens += 1;
		}

		assert(source_cursor == lexer.input.count);
		assert(!lexer.reported_error);
	}

	print("Validated % tokens across % files.\n", total_tokens, filenames.count);
}

consume_here_string :: (lexer: *Parser_Lexer.Lexer, source_cursor: *s64, total_tokens: *s64) {
	consume_source_token(lexer, source_cursor, total_tokens);
	name := consume_source_token(lexer, source_cursor, total_tokens);
	assert(name.type == .IDENT && name.ident_value.name == "string");

	want_cr := false;
	while Parser_Lexer.peek_next_token(lexer).type == #char "," {
		consume_source_token(lexer, source_cursor, total_tokens);
		modifier := consume_source_token(lexer, source_cursor, total_tokens);
		if modifier.type == .IDENT && modifier.ident_value.name == "cr" {
			want_cr = true;
		} else {
			assert(modifier.type == .IDENT && modifier.ident_value.name == "\\%");
		}
	}

	delimiter := consume_source_token(lexer, source_cursor, total_tokens);
	assert(delimiter.type == .IDENT);
	body := Parser_Lexer.parse_here_string_body(lexer, delimiter.ident_value.name, want_cr);
	assert(body != null);
	consume_source_span(lexer.input, source_cursor, body.preceding_trivia);
	consume_source_span(lexer.input, source_cursor, body.original_text);
	total_tokens.* += 1;

	terminator := consume_source_token(lexer, source_cursor, total_tokens);
	assert(terminator.type == .IDENT);
	assert(terminator.ident_value.name == delimiter.ident_value.name);
}

consume_source_token :: (lexer: *Parser_Lexer.Lexer, source_cursor: *s64, total_tokens: *s64) -> Parser_Lexer.Token {
	token := Parser_Lexer.peek_next_token(lexer);
	consume_source_span(lexer.input, source_cursor, token.preceding_trivia);
	consume_source_span(lexer.input, source_cursor, token.original_text);
	result := token.*;
	Parser_Lexer.eat_token(lexer);
	total_tokens.* += 1;
	return result;
}

consume_source_span :: (input: string, cursor: *s64, span: string) {
	if span.count {
		assert(span.data == input.data + cursor.*);
	}

	cursor.* += span.count;
}

visit :: (info: *File_Visit_Info, results: *[..] string) {
	if ends_with(info.short_name, ".jai") {
		array_add(results, copy_string(info.full_name));
	}
}
