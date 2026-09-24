#import "Basic";
#import "File";
#import "File_Utilities";
#import "String";

Parser :: #import "Jai_Parser"(ENABLE_TRIVIA=true);

Token_Count :: struct {
	token: Parser.Token_Type;
	count: s64;
}

First_Diagnostic :: struct {
	filename: string;
	status: Parser.Parse_Status;
	diagnostic_count: s64;
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

CORPUS_BASELINE_DATE :: "2026-09-25";
CORPUS_BASELINE :: Corpus_Baseline_Entry.[
	.{filename="005_strings.jai", diagnostic_count=3},
	.{filename="006_structs.jai", diagnostic_count=5},
	.{filename="008_types.jai", diagnostic_count=3},
	.{filename="010_calling_procedures.jai", diagnostic_count=66},
	.{filename="011_context.jai", diagnostic_count=4},
	.{filename="012_temporary_storage.jai", diagnostic_count=1},
	.{filename="018_print_functions.jai", diagnostic_count=1},
	.{filename="025_ifx.jai", diagnostic_count=12},
	.{filename="027_if_case.jai", diagnostic_count=5},
	.{filename="042_using.jai", diagnostic_count=1},
	.{filename="050_this.jai", diagnostic_count=2},
	.{filename="095_static_if.jai", diagnostic_count=9},
	.{filename="100_polymorphic_procedures.jai", diagnostic_count=27},
	.{filename="110_polymorphic_arguments.jai", diagnostic_count=2},
	.{filename="115_auto_bakes.jai", diagnostic_count=37},
	.{filename="120_polymorphic_structs.jai", diagnostic_count=5},
	.{filename="160_type_restrictions.jai", diagnostic_count=3},
	.{filename="170_modify.jai", diagnostic_count=5},
	.{filename="200_memory_management.jai", diagnostic_count=11},
	.{filename="225_comma_comma.jai", diagnostic_count=9},
	.{filename="250_how_parameters_are_passed.jai", diagnostic_count=19},
	.{filename="400_workspaces.jai", diagnostic_count=2},
	.{filename="497_caller_code.jai", diagnostic_count=1},
	.{filename="550_is_constant.jai", diagnostic_count=4},
	.{filename="560_no_reset.jai", diagnostic_count=10},
	.{filename="600_insert.jai", diagnostic_count=10},
	.{filename="630_compiler_get_nodes.jai", diagnostic_count=6},
	.{filename="730_for_expansions.jai", diagnostic_count=10},
	.{filename="040_import_and_load/main.jai", diagnostic_count=4},
	.{filename="044_using_advanced/main.jai", diagnostic_count=74},
	.{filename="460_code_browsing_and_generation/first.jai", diagnostic_count=1},
	.{filename="470_running_hooks_in_the_target_workspace/target.jai", diagnostic_count=1},
	.{filename="480_custom_checks/first.jai", diagnostic_count=4},
	.{filename="490_browsing_by_module/first.jai", diagnostic_count=2},
	.{filename="950_cross-compiling/do_things_at_compile_time_for_real.jai", diagnostic_count=10},
	.{filename="950_cross-compiling/first.jai", diagnostic_count=1},
	.{filename="040_import_and_load/files/specific.jai", diagnostic_count=4},
	.{filename="380_module_parameters/local_modules/Rendering.jai", diagnostic_count=7},
];

increment_token_count :: (counts: *[..]Token_Count, token: Parser.Token_Type) {
	for * counts.* {
		if it.token == token {
			it.count += 1;
			return;
		}
	}


	array_add(counts, .{token=token, count=1});
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


	array_add(counts, .{
		kind=diagnostic.kind,
		expected_token=diagnostic.expected_token,
		actual_token=diagnostic.actual_token,
		recovery_action=diagnostic.recovery_action,
		count=1,
		representative_filename=diagnostic.filename,
	});
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
	path := join(#filepath, "../../../how_to");
	how_to_path := path_to_string(reduce_path(parse_path(path)));

	filenames: [..]string;

	visit_jai_file :: (info: *File_Visit_Info, results: *[..]string) {
		if ends_with(info.short_name, ".jai") {
			array_add(results, copy_string(info.full_name));
		}
	}

	visit_files(how_to_path, true, *filenames, visit_jai_file);

	files_with_diagnostics: s64;
	total_diagnostics: s64;
	diagnostic_kind_counts: [3]s64;
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

		if parsed.status != .COMPLETE {
			files_with_diagnostics += 1;
			total_diagnostics += parsed.diagnostics.count;
			first := parsed.diagnostics[0];
			relative_start := how_to_path.count;
			if filename[relative_start] == #char "/" || filename[relative_start] == #char "\\" {
				relative_start += 1;
			}

			relative_filename := slice(filename, relative_start, filename.count - relative_start);
			array_add(
				*first_diagnostics,
				.{
					filename=copy_string(relative_filename),
					status=parsed.status,
					diagnostic_count=parsed.diagnostics.count,
					kind=first.kind,
					expected_token=first.expected_token,
					actual_token=first.actual_token,
					recovery_action=first.recovery_action,
					message=copy_string(first.message),
				}
			);
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

	print("Parsed % how_to files; % files produced % diagnostics.\n", filenames.count, files_with_diagnostics, total_diagnostics);
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
		print("  %: status=%, diagnostics=%, kind=%, expected=%, actual=%, recovery=%, message=%\n",
			it.filename,
			it.status,
			it.diagnostic_count,
			it.kind,
			token_spelling(it.expected_token),
			token_spelling(it.actual_token),
			it.recovery_action,
			it.message
		);
	}

	print_next_grammar_candidate(first_diagnostics);
}
