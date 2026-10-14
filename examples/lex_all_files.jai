// Walk .jai files under modules with the trivia-enabled lexer; advance through each token and trivia slice, asserting exact byte coverage and no lexer errors.
#import "Basic";
#import "File";
#import "File_Utilities";
#import "Pool";
#import "Sort";
#import "String";

Parser_Lexer :: #import "Jai_Parser"(ENABLE_TRIVIA=true);
Simd_Lexer :: #import "Jai_Parser"(ENABLE_TRIVIA=true, ENABLE_SIMD=true);
Avx2_Lexer :: #import "Jai_Parser"(ENABLE_TRIVIA=true, ENABLE_SIMD=true, ENABLE_AVX2=true);
Avx512_Lexer :: #import "Jai_Parser"(ENABLE_TRIVIA=true, ENABLE_SIMD=true, ENABLE_AVX2=true, ENABLE_AVX512=true);
benchmark_avx2: bool;
benchmark_avx512: bool;

#if OS == .WINDOWS {
	Windows :: #import "Windows";
}

main :: () {
	arguments := get_command_line_arguments();
	if (
		arguments.count > 1
		&& (
			arguments[1] == "--benchmark"
			|| arguments[1] == "--benchmark-avx2"
			|| arguments[1] == "--benchmark-avx512"
		)
	) {
		benchmark_avx2 = arguments[1] == "--benchmark-avx2";
		benchmark_avx512 = arguments[1] == "--benchmark-avx512";
		assert(arguments.count > 2, "Provide at least one source directory.");
		if benchmark_avx512 {
			#if Avx512_Lexer.USE_SIMD {
				available := Avx512_Lexer.avx512_is_available();
				print("AVX-512F/BW usable with OS vector state: %\n", available);
				if !available {
					print("AVX-512 unavailable: timings measure guarded fallback, not AVX-512.\n");
				}
			} else {
				print("AVX-512 unavailable: timings measure scalar fallback on this target.\n");
			}
		}

		for index: 2..arguments.count-1 {
			benchmark_corpus(arguments[index]);
		}

		return;
	}


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

push_benchmark_allocator :: () #expand {
	`storage: Pool;
	set_allocators(*storage);
	`defer release(*storage);
	previous_allocator := context.allocator;
	context.allocator = .{proc=pool_allocator_proc, data=*storage};
	`defer context.allocator = previous_allocator;
}

benchmark_ticks :: () -> s64 {
	#if OS == .WINDOWS {
		counter: Windows.LARGE_INTEGER;
		assert(Windows.QueryPerformanceCounter(*counter) != 0);
		return counter.QuadPart;
	} else {
		assert(false, "This benchmark currently requires Windows.");
		return 0;
	}
}

benchmark_scan :: (sources: [] string, $simd: bool) -> s64 {
	tokens: s64;
	for source: sources {
		push_benchmark_allocator();
		#if simd {
			if benchmark_avx512 {
				parsed := Avx512_Lexer.materialise_tokens(source);
				assert(parsed.status == .COMPLETE && parsed.diagnostics.count == 0);
				tokens += parsed.tokens.count;
			} else if benchmark_avx2 {
				parsed := Avx2_Lexer.materialise_tokens(source);
				assert(parsed.status == .COMPLETE && parsed.diagnostics.count == 0);
				tokens += parsed.tokens.count;
			} else {
				parsed := Simd_Lexer.materialise_tokens(source);
				assert(parsed.status == .COMPLETE && parsed.diagnostics.count == 0);
				tokens += parsed.tokens.count;
			}
		} else {
			parsed := Parser_Lexer.materialise_tokens(source);
			assert(parsed.status == .COMPLETE && parsed.diagnostics.count == 0);
			tokens += parsed.tokens.count;
		}
	}

	return tokens;
}

benchmark_trial :: (sources: [] string, $simd: bool, expected_tokens: s64, frequency: s64) -> float64 {
	REPETITIONS :: 25;
	start := benchmark_ticks();
	for 1..REPETITIONS {
		assert(benchmark_scan(sources, simd) == expected_tokens);
	}

	return (benchmark_ticks() - start).(float64) * 1000 / frequency.(float64) / REPETITIONS;
}

assert_benchmark_token_parity :: (actual: $Actual, expected: Parser_Lexer.Parser_Token, filename: string) {
	assert(actual.type.(s64) == expected.type.(s64));
	assert(actual.value_flags.(u32) == expected.value_flags.(u32));
	assert(actual.ident_is_backticked == expected.ident_is_backticked);
	assert(actual.byte_start == expected.byte_start && actual.byte_end == expected.byte_end);
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
			if expected.value_flags & .FLOAT {
				assert((*actual.float64_value).(*u64).* == (*expected.float64_value).(*u64).*, "Floating token '%' differs in '%'.", expected.original_text, filename);
			} else {
				assert(actual.integer_value == expected.integer_value);
			}
	}
}

benchmark_corpus :: (directory: string) {
	filenames: [..] string;
	visit_files(directory, true, *filenames, visit, visit_symlinks=false);
	defer {
		for filenames {
			free(it);
		}

		array_free(filenames);
	}

	assert(filenames.count > 0, "No Jai files found under '%'.", directory);

	sources: [..] string;
	defer {
		for sources {
			free(it);
		}

		array_free(sources);
	}

	bytes: s64;
	token_count: s64;
	for filename: filenames {
		source, success := read_entire_file(filename);
		assert(success);
		array_add(*sources, source);
		bytes += source.count;
		push_benchmark_allocator();
		scalar := Parser_Lexer.materialise_tokens(source);
		vectorised := Simd_Lexer.materialise_tokens(source);
		assert(scalar.status == .COMPLETE && scalar.diagnostics.count == 0);
		assert(vectorised.status == .COMPLETE && vectorised.diagnostics.count == 0);
		assert(vectorised.tokens.count == scalar.tokens.count);

		for expected, index: scalar.tokens {
			actual := vectorised.tokens[index];
			assert_benchmark_token_parity(actual, expected, filename);
		}

		if benchmark_avx2 {
			wider := Avx2_Lexer.materialise_tokens(source);
			assert(wider.status == .COMPLETE && wider.diagnostics.count == 0);
			assert(wider.tokens.count == scalar.tokens.count);
			for expected, index: scalar.tokens {
				assert_benchmark_token_parity(wider.tokens[index], expected, filename);
			}
		}

		if benchmark_avx512 {
			widest := Avx512_Lexer.materialise_tokens(source);
			assert(widest.status == .COMPLETE && widest.diagnostics.count == 0);
			assert(widest.tokens.count == scalar.tokens.count);
			for expected, index: scalar.tokens {
				assert_benchmark_token_parity(widest.tokens[index], expected, filename);
			}
		}

		token_count += scalar.tokens.count;
	}

	frequency: s64;
	#if OS == .WINDOWS {
		counter: Windows.LARGE_INTEGER;
		assert(Windows.QueryPerformanceFrequency(*counter) != 0);
		frequency = counter.QuadPart;
	}

	assert(frequency > 0, "This benchmark requires Windows.");
	for 1..2 {
		assert(benchmark_scan(sources, false) == token_count);
		assert(benchmark_scan(sources, true) == token_count);
	}

	scalar_samples: [9] float64;
	simd_samples: [9] float64;
	for trial: 0..scalar_samples.count-1 {
		if trial % 2 == 0 {
			scalar_samples[trial] = benchmark_trial(sources, false, token_count, frequency);
			simd_samples[trial] = benchmark_trial(sources, true, token_count, frequency);
		} else {
			simd_samples[trial] = benchmark_trial(sources, true, token_count, frequency);
			scalar_samples[trial] = benchmark_trial(sources, false, token_count, frequency);
		}
	}

	quick_sort(scalar_samples, (value: float64) -> float64 { return value; });
	quick_sort(simd_samples, (value: float64) -> float64 { return value; });
	scalar_median := scalar_samples[4];
	simd_median := simd_samples[4];
	print("%: % files, % bytes, % tokens (including EOF); 9 trials x 25 scans, 2 warmups\n", directory, sources.count, bytes, token_count);
	print("  Scalar ms/scan median=% range=%..%\n", scalar_median, scalar_samples[0], scalar_samples[8]);
	print("  SIMD   ms/scan median=% range=%..%\n", simd_median, simd_samples[0], simd_samples[8]);
	print("  Speedup=% x, elapsed reduction=% percent; token parity PASS\n", scalar_median / simd_median, 100 * (1 - simd_median / scalar_median));
}

consume_here_string :: (lexer: *Parser_Lexer.Lexer, source_cursor: *s64, total_tokens: *s64) {
	consume_source_token(lexer, source_cursor, total_tokens);
	name := consume_source_token(lexer, source_cursor, total_tokens);
	assert(name.type == .IDENT && name.ident_value.name == "string");

	want_cr := false;
	want_percent := false;
	while Parser_Lexer.peek_next_token(lexer).type == #char "," {
		consume_source_token(lexer, source_cursor, total_tokens);
		modifier := consume_source_token(lexer, source_cursor, total_tokens);
		if modifier.type == .IDENT && modifier.ident_value.name == "cr" {
			want_cr = true;
		} else {
			assert(modifier.type == .IDENT && modifier.ident_value.name == "\\%");
			want_percent = true;
		}
	}

	delimiter := consume_source_token(lexer, source_cursor, total_tokens);
	assert(delimiter.type == .IDENT);
	body := Parser_Lexer.parse_here_string_body(lexer, delimiter.ident_value.name, want_cr, want_percent);
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
