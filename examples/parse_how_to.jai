// Parse every how_to .jai file, assert nonfatal roots and exact trivia round trips, then compare recovery counts with the checked-in baseline and report differences.
#import "Basic";
#import "File";
#import "File_Utilities";
#import "String";

#load "test_fixtures.jai";

Parser :: #import "Jai_Parser"(ENABLE_TRIVIA = true);

Token_Count :: struct {
	token: Parser.Token_Type;
	count: s64;
}

First_Diagnostic :: struct {
	filename: string;
	line: s64;
	source_line: string;
	status: Parser.Parse_Status;
	diagnostic_count: s64;
	has_diagnostic: bool;
	kind: type_of(Parser.Parse_Diagnostic.kind);
	expected_token: Parser.Token_Type;
	actual_token: Parser.Token_Type;
	recovery_action: Parser.Recovery_Action;
	message: string;
}

Corpus_Baseline_Entry :: struct {
	filename: string;
	diagnostic_count: s64;
}

First_Diagnostic_Signature_Count :: struct {
	kind: type_of(Parser.Parse_Diagnostic.kind);
	expected_token: Parser.Token_Type;
	actual_token: Parser.Token_Type;
	recovery_action: Parser.Recovery_Action;
	count: s64;
	representative_filename: string;
}

CORPUS_BASELINE_DATE :: "2026-10-19";

CORPUS_BASELINE :: Corpus_Baseline_Entry.[];

increment_token_count :: (counts: *[..]Token_Count, token: Parser.Token_Type) {
	for * counts.* {
		if it.token == token {
			it.count += 1;
			return;
		}
	}


	array_add(counts, .{token = token, count = 1});
}

token_spelling :: (token: Parser.Token_Type) -> string {
	value := cast(s64) token;
	if value == 0 {
		return "<none>";
	}


	if value >= 0 && value < 128 {
		character := cast(u8) value;
		return tprint("'%'", to_string(*character, 1));
	}


	return tprint("%", token);
}

print_token_counts :: (label: string, counts: []Token_Count) {
	print("%:\n", label);
	for counts {
		print("  %: %\n", token_spelling(it.token), it.count);
	}
}

find_first_diagnostic :: (diagnostics: []First_Diagnostic, filename: string) -> *First_Diagnostic {
	for * diagnostics {
		if it.filename == filename {
			return it;
		}
	}


	return null;
}

find_baseline_entry :: (filename: string) -> *Corpus_Baseline_Entry {
	for * CORPUS_BASELINE {
		if it.filename == filename {
			return it;
		}
	}


	return null;
}

increment_first_signature :: (counts: *[..]First_Diagnostic_Signature_Count, diagnostic: First_Diagnostic) {
	for * counts.* {
		if (it.kind == diagnostic.kind
			&& it.expected_token == diagnostic.expected_token
			&& it.actual_token == diagnostic.actual_token
			&& it.recovery_action == diagnostic.recovery_action
		 ) {
			it.count += 1;
			return;
		}
	}


	array_add(
		counts,
		.{
			kind = diagnostic.kind,
			expected_token = diagnostic.expected_token,
			actual_token = diagnostic.actual_token,
			recovery_action = diagnostic.recovery_action,
			count = 1,
			representative_filename = diagnostic.filename,
		}
	);
}

first_diagnostic_for_file :: (parsed: *Parser.Parsed_Source, filename: string) -> First_Diagnostic {
	entry := First_Diagnostic.{
		filename = copy_string(filename),
		status = parsed.status,
		diagnostic_count = parsed.diagnostics.count,
	};

	if parsed.diagnostics.count {
		first := parsed.diagnostics[0];
		token := Parser.token_at(parsed, first.span.first);

		entry.line = ifx first.kind == .LEXER_ERROR
			then first.lexer_line
			else token.l0;

		lines := split(parsed.source, "\n");
		if entry.line >= 1 && entry.line <= lines.count {
			entry.source_line = copy_string(lines[entry.line - 1]);
		}

		entry.has_diagnostic = true;
		entry.kind = first.kind;
		entry.expected_token = first.expected_token;
		entry.actual_token = first.actual_token;
		entry.recovery_action = first.recovery_action;
		entry.message = copy_string(first.message);
	}

	return entry;
}

test_lexer_only_recovery_report :: () {
	identifier_length :: Parser.MAX_IDENTIFIER_LENGTH + 8;
	suffix :: " :: 1;";

	source := make_long_identifier_source(identifier_length, suffix);
	defer free(source);

	parsed := Parser.parse_file(source);
	defer Parser.release_parser_tree(*parsed);

	entry := first_diagnostic_for_file(*parsed, "lexer_error.jai");
	assert(entry.status == .RECOVERED);
	assert(entry.diagnostic_count == 1);
	assert(entry.has_diagnostic && entry.kind == .LEXER_ERROR);
	assert(entry.line == 1);
	assert(entry.filename == "lexer_error.jai");
}

print_baseline_change :: (first_diagnostics: []First_Diagnostic, total_diagnostics: s64) {
	baseline_total: s64;
	newly_complete: s64;
	removed_diagnostics: s64;
	added_diagnostics: s64;
	print("Change from corpus baseline %:\n", CORPUS_BASELINE_DATE);

	for CORPUS_BASELINE {
		baseline_total += it.diagnostic_count;
		current := find_first_diagnostic(first_diagnostics, it.filename);
		if !current {
			newly_complete += 1;
			removed_diagnostics += it.diagnostic_count;
			print("  newly complete: % (% diagnostics removed)\n", it.filename, it.diagnostic_count);
		} else if current.diagnostic_count < it.diagnostic_count {
			removed := it.diagnostic_count - current.diagnostic_count;
			removed_diagnostics += removed;
			print("  improved: % (% -> %, % diagnostics removed)\n", it.filename, it.diagnostic_count, current.diagnostic_count, removed);
		} else if current.diagnostic_count > it.diagnostic_count {
			added := current.diagnostic_count - it.diagnostic_count;
			added_diagnostics += added;
			print("  regressed: % (% -> %, % diagnostics added)\n", it.filename, it.diagnostic_count, current.diagnostic_count, added);
		}
	}

	newly_recovering: s64;
	for first_diagnostics {
		if !find_baseline_entry(it.filename) {
			newly_recovering += 1;
			added_diagnostics += it.diagnostic_count;
			print("  newly recovering: % (% diagnostics)\n", it.filename, it.diagnostic_count);
		}
	}

	assert(baseline_total - total_diagnostics == removed_diagnostics - added_diagnostics);
	print("  summary: % newly complete, % newly recovering, % diagnostics removed, % diagnostics added\n", newly_complete, newly_recovering, removed_diagnostics, added_diagnostics);
}

print_next_grammar_candidate :: (first_diagnostics: []First_Diagnostic) {
	counts: [..]First_Diagnostic_Signature_Count;

	for first_diagnostics {
		if !it.has_diagnostic {
			continue;
		}


		increment_first_signature(*counts, it);
	}

	if !counts.count {
		return;
	}


	best := counts[0];
	for counts {
		if it.count > best.count {
			best = it;
		}
	}

	print("Next grammar candidate from first diagnostics only:\n");
	print(
		"  files=%, kind=%, expected=%, actual=%, recovery=%, representative=%\n",
		best.count,
		best.kind,
		token_spelling(best.expected_token),
		token_spelling(best.actual_token),
		best.recovery_action,
		best.representative_filename
	);
}

main :: () {
	test_lexer_only_recovery_report();

	path := join(#filepath, "../../../how_to");
	how_to_path := path_to_string(reduce_path(parse_path(path)));

	filenames: [..]string;

	visit_jai_file :: (info: *File_Visit_Info, results: *[..]string) {
		if ends_with(info.short_name, ".jai") {
			array_add(results, copy_string(info.full_name));
		}
	}

	visit_files(how_to_path, true, *filenames, visit_jai_file);

	files_requiring_recovery: s64;
	zero_diagnostic_files: s64;
	zero_diagnostic_recovering_files: s64;
	total_diagnostics: s64;
	diagnostic_kind_counts: [5]s64;
	recovery_action_counts: [3]s64;
	expected_token_counts: [..]Token_Count;
	actual_token_counts: [..]Token_Count;
	first_diagnostics: [..]First_Diagnostic;

	for filename: filenames {
		source, success := read_entire_file(filename);
		assert(success, "Unable to read '%'.", filename);

		parsed := Parser.parse_file(source, filename);
		root := parsed.root.(*Parser.Parser_Block);
		assert(root.block_type == .DATA_DECLARATIONS);
		assert(Parser.reconstruct_source(*parsed) == source);
		assert(parsed.status != .FATAL);

		if !parsed.diagnostics.count {
			zero_diagnostic_files += 1;
			if parsed.status != .COMPLETE {
				zero_diagnostic_recovering_files += 1;
			}
		}

		if parsed.status != .COMPLETE {
			files_requiring_recovery += 1;
			total_diagnostics += parsed.diagnostics.count;
			relative_start := how_to_path.count;
			if filename[relative_start] == #char "/" || filename[relative_start] == #char "\\" {
				relative_start += 1;
			}

			relative_filename := slice(filename, relative_start, filename.count - relative_start);
			array_add(*first_diagnostics, first_diagnostic_for_file(*parsed, relative_filename));
		}

		for parsed.diagnostics {
			diagnostic_kind_counts[it.kind.(s64)] += 1;
			recovery_action_counts[it.recovery_action.(s64)] += 1;
			if it.kind == .EXPECTED_TOKEN {
				increment_token_count(*expected_token_counts, it.expected_token);
			}

			increment_token_count(*actual_token_counts, it.actual_token);
		}

		Parser.release_parser_tree(*parsed);
		free(source);
	}

	print("Parsed % how_to files; % files required recovery and produced % diagnostics.\n", filenames.count, files_requiring_recovery, total_diagnostics);
	print(
		"Zero-diagnostic files: %/% (baseline %/%; % complete, % recovering without diagnostics).\n",
		zero_diagnostic_files,
		filenames.count,
		filenames.count - CORPUS_BASELINE.count,
		filenames.count,
		zero_diagnostic_files - zero_diagnostic_recovering_files,
		zero_diagnostic_recovering_files
	);
	print_baseline_change(first_diagnostics, total_diagnostics);

	print("Diagnostic kinds:\n");
	for diagnostic_kind_counts {
		print("  %: %\n", it_index.(type_of(Parser.Parse_Diagnostic.kind)), it);
	}

	print_token_counts("Expected tokens", expected_token_counts);
	print_token_counts("Actual tokens", actual_token_counts);

	print("Recovery actions:\n");
	for recovery_action_counts {
		print("  %: %\n", it_index.(Parser.Recovery_Action), it);
	}

	print("First diagnostic per file:\n");
	for first_diagnostics {
		if !it.has_diagnostic {
			print("  %: status=%, diagnostics=0\n", it.filename, it.status);
			continue;
		}


		print(
			"  %:%: status=%, diagnostics=%, kind=%, expected=%, actual=%, recovery=%, message=%\n    %\n",
			it.filename,
			it.line,
			it.status,
			it.diagnostic_count,
			it.kind,
			token_spelling(it.expected_token),
			token_spelling(it.actual_token),
			it.recovery_action,
			it.message,
			it.source_line
		);
	}

	print_next_grammar_candidate(first_diagnostics);
}
