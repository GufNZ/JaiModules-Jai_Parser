#import "File";
#import "File_Utilities";
#import "String";

Parser :: #import "Jai_Parser"(ENABLE_TRIVIA=true);

#if MEASURE_MEMORY {
	Memory_Snapshot :: struct {
		allocations: s64;
		bytes: s64;
	}

	snapshot_memory :: () -> Memory_Snapshot {
		options: Leak_Report_Options;
		options.scan_global_memory_to_remove_leaks = false;
		options.scan_leaks_to_combine = false;
		report := make_leak_report(options);
		defer deinit(*report);
		result: Memory_Snapshot;
		for report.sorted_summaries {
			result.allocations += it.count;
			result.bytes += it.bytes;
		}
		return result;
	}
}

Name_Copies :: struct {
	identifiers: s64;
	keywords: s64;
	notes: s64;
	bytes: s64;
}

count_name_copy :: (token: *Parser.Token, copies: *Name_Copies) {
	if token.type == .IDENT || token.type == .NOTE || (token.type >= .__FIRST_KEYWORD && token.type <= .__LAST_KEYWORD) {
		if token.ident_value.name.count {
			if token.type == .IDENT {
				copies.identifiers += 1;
			} else if token.type == .NOTE {
				copies.notes += 1;
			} else {
				copies.keywords += 1;
			}
			copies.bytes += token.ident_value.name.count;
		}
	}
}

make_generated_source :: (kind: string) -> string {
	builder: String_Builder;
	if kind == "keywords" append(*builder, "entry :: () {\n");
	for index: 0..999 {
		if kind == "repeated" {
			print_to_builder(*builder, "value := value + 1;\n");
		} else if kind == "unique" {
			print_to_builder(*builder, "value_% := 1;\n", index);
		} else {
			print_to_builder(*builder, "if true { while false { break; } }\n");
		}
	}
	if kind == "keywords" append(*builder, "}\n");
	return builder_to_string(*builder);
}

main :: () {
	args := get_command_line_arguments();
	assert(args.count == 3, "Usage: atom_baseline.exe repeated|unique|keywords|how_to lex|parse");
	kind := args[1];
	phase := args[2];
	assert(phase == "lex" || phase == "parse");
	assert(kind == "repeated" || kind == "unique" || kind == "keywords" || kind == "how_to");

	sources: [..]string;
	if kind == "how_to" {
		path := join(#filepath, "../../../how_to");
		directory := path_to_string(reduce_path(parse_path(path)));
		visit_jai_file :: (info: *File_Visit_Info, results: *[..]string) {
			if ends_with(info.short_name, ".jai") {
				source, success := read_entire_file(info.full_name);
				assert(success);
				array_add(results, source);
			}
		}
		visit_files(directory, true, *sources, visit_jai_file);
	} else {
		array_add(*sources, make_generated_source(kind));
	}

	#if MEASURE_MEMORY before := snapshot_memory();
	name_copies: Name_Copies;
	#if MEASURE_MEMORY peak_retained_bytes: s64;
	start := current_time_monotonic();
	for source: sources {
		if phase == "lex" {
			lexer: Parser.Lexer;
			Parser.set_input_from_string(*lexer, source);
			while true {
				token := Parser.peek_next_token(*lexer);
				if token.type == .END_OF_INPUT break;
				count_name_copy(token, *name_copies);
				Parser.eat_token(*lexer);
			}
		} else {
			parsed := Parser.parse_file(source);
			assert(parsed.status == .COMPLETE);
			for * parsed.tokens count_name_copy(*it.lexer_token, *name_copies);
		}
		#if MEASURE_MEMORY {
			checkpoint := snapshot_memory();
			peak_retained_bytes = Max(peak_retained_bytes, checkpoint.bytes - before.bytes);
		}
	}
	elapsed := to_float64_seconds(current_time_monotonic() - start);
	#if MEASURE_MEMORY {
		after := snapshot_memory();
		print("% %: files=%, identifiers=%, keywords=%, notes=%, copied_name_bytes=%, retained_allocations=%, retained_bytes=%, peak_checkpoint_bytes=%, debug_seconds=%\n",
			kind, phase, sources.count, name_copies.identifiers, name_copies.keywords, name_copies.notes, name_copies.bytes,
			after.allocations - before.allocations, after.bytes - before.bytes, peak_retained_bytes, elapsed);
	} else {
		print("% %: files=%, identifiers=%, keywords=%, notes=%, copied_name_bytes=%, seconds=%\n",
			kind, phase, sources.count, name_copies.identifiers, name_copies.keywords, name_copies.notes, name_copies.bytes, elapsed);
	}
}
