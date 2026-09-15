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
