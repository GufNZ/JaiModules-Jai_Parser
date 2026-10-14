// Walk .jai files under modules with the trivia-enabled lexer; advance through each token and trivia slice, asserting exact byte coverage and no lexer errors.
#import "Basic";
#import "File";
#import "File_Utilities";
#import "Pool";
#import "Sort";
#import "String";

Parser_Lexer :: #import "Jai_Parser"(ENABLE_TRIVIA=true, USE_SIMD=false);
Simd_Lexer :: #import "Jai_Parser"(ENABLE_TRIVIA=true, USE_SIMD=true);

#if OS == .WINDOWS {
	Windows :: #import "Windows";
}

main :: () {
	arguments := get_command_line_arguments();
	if arguments.count > 1 && (arguments[1] == "--benchmark" || arguments[1] == "--benchmark-workloads") {
		#if Simd_Lexer.SIMD_AVAILABLE {
			features := Simd_Lexer.get_simd_features();
			backend := ifx features & .AVX512
				then "AVX-512"
				else ifx features & .AVX2
					then "AVX2"
					else "SSE2";

			print("Widest SIMD path: %\n", backend);
		} else {
			print("SIMD unavailable: using scalar fallback on this target.\n");
		}

		if arguments[1] == "--benchmark-workloads" {
			benchmark_workloads();
			return;
		}


		assert(arguments.count > 2, "Provide at least one source directory.");
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

benchmark_source_scan :: (source: string, $simd: bool, $materialise: bool) -> s64 {
	#if materialise {
		#if simd {
			parsed := Simd_Lexer.materialise_tokens(source);
			assert(parsed.status == .COMPLETE && parsed.diagnostics.count == 0);
			return parsed.tokens.count;
		} else {
			parsed := Parser_Lexer.materialise_tokens(source);
			assert(parsed.status == .COMPLETE && parsed.diagnostics.count == 0);
			return parsed.tokens.count;
		}
	} else {
		tokens: s64;
		#if simd {
			lexer: Simd_Lexer.Lexer;
			Simd_Lexer.set_input_from_string(*lexer, source);
			while true {
				token := Simd_Lexer.peek_next_token(*lexer);
				tokens += 1;
				if token.type == .END_OF_INPUT {
					break;
				}


				Simd_Lexer.eat_token(*lexer);
			}
			assert(!lexer.reported_error);
		} else {
			lexer: Parser_Lexer.Lexer;
			Parser_Lexer.set_input_from_string(*lexer, source);
			while true {
				token := Parser_Lexer.peek_next_token(*lexer);
				tokens += 1;
				if token.type == .END_OF_INPUT {
					break;
				}


				Parser_Lexer.eat_token(*lexer);
			}
			assert(!lexer.reported_error);
		}

		return tokens;
	}
}

benchmark_scan :: (sources: [] string, $simd: bool, $materialise: bool = true, storage: *Pool = null) -> s64 {
	tokens: s64;
	for source: sources {
		fresh: Pool;
		set_allocators(*fresh);
		active := ifx storage then storage else *fresh;
		defer {
			if storage {
				reset(storage);
			} else {
				release(*fresh);
			}
		}

		push_allocator(.{proc=pool_allocator_proc, data=active});
		tokens += benchmark_source_scan(source, simd, materialise);
	}

	return tokens;
}

benchmark_trial :: (sources: [] string, $simd: bool, expected_tokens: s64, frequency: s64, $materialise: bool, $reuse: bool) -> float64 {
	REPETITIONS :: 25;
	storage: Pool;
	set_allocators(*storage);
	defer release(*storage);

	active: *Pool;
	#if reuse {
		active = *storage;
		assert(benchmark_scan(sources, simd, materialise, active) == expected_tokens);
	}

	start := benchmark_ticks();
	for 1..REPETITIONS {
		assert(benchmark_scan(sources, simd, materialise, active) == expected_tokens);
	}

	return (benchmark_ticks() - start).(float64) * 1000 / frequency.(float64) / REPETITIONS;
}

assert_benchmark_token_parity :: (actual: Simd_Lexer.Parser_Token, expected: Parser_Lexer.Parser_Token, filename: string) {
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

	for filename: filenames {
		source, success := read_entire_file(filename);
		assert(success);
		array_add(*sources, source);
	}

	benchmark_sources(directory, sources);
}

benchmark_workloads :: () {
	records := string.[
		"value := other + delta; value = other + delta;\n",
		"long_identifier_with_repeated_ascii_letters_abcdefghijklmnopqrstuvwxyz_0123456789 := another_long_identifier_with_repeated_ascii_letters_abcdefghijklmnopqrstuvwxyz_0123456789;\n",
		"value := 1; // A long line comment with ASCII words, punctuation, and spaces. abcdefghijklmnopqrstuvwxyz 0123456789 abcdefghijklmnopqrstuvwxyz 0123456789 abcdefghijklmnopqrstuvwxyz 0123456789\n",
		"value := \"A long plain string with ASCII words abcdefghijklmnopqrstuvwxyz 0123456789 abcdefghijklmnopqrstuvwxyz 0123456789\";\n",
		"value := \"An escaped string with newline\\n tab\\t quote\\\" slash\\\\ and hex\\x41 repeated payload abcdefghijklmnopqrstuvwxyz\";\n"
	];

	names := string.["short-identifiers", "long-identifiers", "line-comments", "plain-strings", "escaped-strings"];

	for record, index: records {
		source: string;
		source.count = record.count * 4096;
		source.data = xx alloc(source.count);
		defer free(source);

		for block: 0..4095 {
			memcpy(source.data + block * record.count, record.data, record.count);
		}

		benchmark_sources(names[index], string.[source], true);
	}
}

benchmark_sources :: (name: string, sources: [] string, isolate_allocations: bool = false) {
	bytes: s64;
	token_count: s64;

	for source: sources {
		bytes += source.count;
		push_benchmark_allocator();
		scalar := Parser_Lexer.materialise_tokens(source);
		vectorised := Simd_Lexer.materialise_tokens(source);
		assert(scalar.status == .COMPLETE && scalar.diagnostics.count == 0);
		assert(vectorised.status == .COMPLETE && vectorised.diagnostics.count == 0);
		assert(vectorised.tokens.count == scalar.tokens.count);

		for expected, index: scalar.tokens {
			actual := vectorised.tokens[index];
			assert_benchmark_token_parity(actual, expected, name);
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
	print("%: % files, % bytes, % tokens (including EOF); 9 trials x 25 scans, 2 warmups\n", name, sources.count, bytes, token_count);
	if isolate_allocations {
		benchmark_measure(sources, bytes, token_count, frequency, false, false);
		benchmark_measure(sources, bytes, token_count, frequency, false, true);
		benchmark_measure(sources, bytes, token_count, frequency, true, false);
		benchmark_measure(sources, bytes, token_count, frequency, true, true);
	} else {
		benchmark_measure(sources, bytes, token_count, frequency, true, false);
	}
}

benchmark_measure :: (sources: [] string, bytes: s64, token_count: s64, frequency: s64, $materialise: bool, $reuse: bool) {
	phase := ifx materialise then "materialised" else "streaming";
	allocator := ifx reuse then "reused-pool" else "fresh-pool";
	print("  Phase: % / %\n", phase, allocator);
	for 1..2 {
		assert(benchmark_scan(sources, false, materialise) == token_count);
		assert(benchmark_scan(sources, true, materialise) == token_count);
	}

	scalar_samples: [9] float64;
	simd_samples: [9] float64;
	for trial: 0..scalar_samples.count-1 {
		if trial % 2 == 0 {
			scalar_samples[trial] = benchmark_trial(sources, false, token_count, frequency, materialise, reuse);
			simd_samples[trial] = benchmark_trial(sources, true, token_count, frequency, materialise, reuse);
		} else {
			simd_samples[trial] = benchmark_trial(sources, true, token_count, frequency, materialise, reuse);
			scalar_samples[trial] = benchmark_trial(sources, false, token_count, frequency, materialise, reuse);
		}
	}

	quick_sort(scalar_samples, (value: float64) -> float64 { return value; });
	quick_sort(simd_samples, (value: float64) -> float64 { return value; });
	scalar_median := scalar_samples[4];
	simd_median := simd_samples[4];
	print("  Scalar ms/scan median=% range=%..%\n", scalar_median, scalar_samples[0], scalar_samples[8]);
	print("  SIMD   ms/scan median=% range=%..%\n", simd_median, simd_samples[0], simd_samples[8]);
	print("  Scalar MiB/s=% Mtokens/s=%; SIMD MiB/s=% Mtokens/s=%\n", bytes.(float64) * 1000 / scalar_median / 1048576, token_count.(float64) / scalar_median / 1000, bytes.(float64) * 1000 / simd_median / 1048576, token_count.(float64) / simd_median / 1000);
	print("  Speedup=% x, elapsed reduction=% percent; token parity PASS\n", scalar_median / simd_median, 100 * (1 - simd_median / scalar_median));
	if sources.count == 1 {
		scalar_requests, scalar_bytes := benchmark_allocation_profile(sources[0], false, token_count, materialise, reuse);
		simd_requests, simd_bytes := benchmark_allocation_profile(sources[0], true, token_count, materialise, reuse);
		assert(scalar_requests == simd_requests && scalar_bytes == simd_bytes);
	}
}

Benchmark_Allocations :: struct {
	delegate: Allocator;
	requests: s64;
	bytes: s64;
}

benchmark_count_allocator :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, data: *void) -> *void {
	counts := cast(*Benchmark_Allocations) data;
	if mode == .ALLOCATE || mode == .RESIZE {
		counts.requests += 1;
		counts.bytes += size;
	}

	return counts.delegate.proc(mode, size, old_size, old_memory, counts.delegate.data);
}

benchmark_allocation_profile :: (source: string, $simd: bool, expected_tokens: s64, $materialise: bool, $reuse: bool) -> (s64, s64) {
	backing: Benchmark_Allocations;
	backing.delegate = context.allocator;
	storage: Pool;
	set_allocators(*storage, .{proc=benchmark_count_allocator, data=*backing});
	defer release(*storage);

	#if reuse {
		assert(benchmark_scan(string.[source], simd, materialise, *storage) == expected_tokens);
		backing.requests = 0;
		backing.bytes = 0;
	}

	requests: Benchmark_Allocations;
	requests.delegate = .{proc=pool_allocator_proc, data=*storage};

	{
		push_allocator(.{proc=benchmark_count_allocator, data=*requests});
		assert(benchmark_source_scan(source, simd, materialise) == expected_tokens);
	}

	mode := ifx simd then "SIMD" else "Scalar";
	print("  % untimed allocation profile: requests=% requested_bytes=% backing_requests=% backing_bytes=%\n", mode, requests.requests, requests.bytes, backing.requests, backing.bytes);
	return requests.requests, requests.bytes;
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
