#import "Basic";
#import "Compiler";
#import "File";
#import "File_Utilities";
#import "Process";
#import "String";

OUTPUT_DIRECTORY :: ".build/compiler_evaluation";
TIMEOUT_MS :: 30_000;

PREAMBLE :: #string JAI
#import "Basic";
#import "Compiler";
#run set_build_options_dc(.{do_output=false, write_added_strings=true});
JAI

main :: () {
	assert(make_directory_if_it_does_not_exist(".build"));
	assert(make_directory_if_it_does_not_exist(OUTPUT_DIRECTORY));
	startup_summary := "case\twall_us\texit_code\n";
	for 0..4 {
		run_startup(tprint("startup_%", it), *startup_summary);
	}

	summary := "case\taccepted\texpected_accepted\texit_code\tartifact_files\texpected_artifact_files\tartifact_bytes\twall_us\tdirectory\n";
	for 0..4 {
		run_probe(.{name = tprint("baseline_%", it), directory = "baseline", source = ""}, *summary);
	}

	for probe: PROBES {
		run_probe(probe, *summary);
	}

	parameter_artifacts := collect_artifacts(tprint("%/capture_parameter_context", OUTPUT_DIRECTORY));
	defer release_artifacts(*parameter_artifacts);

	assert(parameter_artifacts.count == 1);
	run_probe(.{name = "flattened_parameter_dump", source = parameter_artifacts[0].data, accepted = false, log_required = "Redeclaration of 'e5_parameter'"}, *summary);
	print("E5 complete: % compilations and 5 startup invocations. Results: %/summary.tsv\n", PROBES.count + 6, OUTPUT_DIRECTORY);
}

#run {
	set_build_options_dc(.{do_output = false, write_added_strings = false});
	main();
}

Source_File :: struct {
	path: string;
	source: string;
}

Artifact :: struct {
	name: string;
	data: string;
}

Expectation :: struct {
	name: string;
	files: s64;
	required: string;
	forbidden: string;
}

EXPECTATIONS :: Expectation.[
	.{"baseline_0",						0,	"",							""},
	.{"baseline_1",						0,	"",							""},
	.{"baseline_2",						0,	"",							""},
	.{"baseline_3",						0,	"",							""},
	.{"baseline_4",						0,	"",							""},
	.{"single_insert",					1,	"",							""},
	.{"multiple_inserts",				1,	"e5_first :: 17;",			""},
	.{"nested_insert",					1,	"",							""},
	.{"expression_insert",				1,	"",							""},
	.{"expression_terminated",			1,	"",							""},
	.{"empty_insert",					1,	"",							""},
	.{"identical_insert_occurrences",	1,	"",							""},
	.{"boundary_like_payload",			1,	"",							""},
	.{"loaded_insert",					1,	"",							""},
	.{"context_present",				1,	"",							""},
	.{"context_missing",				0,	"",							""},
	.{"parameter_context",				1,	"e5_parameter :: 17;",		""},
	.{"using_map",						0,	"",							""},
	.{"generated_location",				1,	"",							""},
	.{"child_workspace",				2,	"e5_parent :: 9;",			""},
	.{"generated_parse_error",			1,	"e5_broken :: ;",			""},
	.{"generated_type_error",			1,	"e5_wrong: s64",			""},
	.{"authored_run_failure",			0,	"",							""},
	.{"fresh_seed",						1,	"",							""},
	.{"fresh_replace",					1,	"",							""},
	.{"fresh_empty",					1,	"e5_fresh_new :: 202;",		""},
	.{"fresh_reseed",					1,	"",							""},
	.{"fresh_disabled",					1,	"e5_fresh_seed :: 303;",	""},
	.{"fresh_early_error",				1,	"e5_fresh_seed :: 303;",	""},
	.{"fresh_generated_error",			1,	"e5_bad :: ;",				"e5_fresh_seed"},
	.{"fresh_recovery",					1,	"",							""},
	.{"flattened_parameter_dump",		0,	"",							""},
];

Probe :: struct {
	name: string;
	source: string;
	files: []Source_File;
	directory: string;
	preserve: bool;
	emit: bool = true;
	accepted: bool = true;
	required: string;
	forbidden: string;
	log_required: string;
}

CONTEXT_SOURCE :: #string JAI
emit_context :: () -> string {
	return tprint("e5_context :: %;", secret + 5);
}
#insert #run emit_context();
#assert e5_context == 42;
JAI

PROBES :: Probe.[
	.{
		name = "single_insert",
		source = #string JAI
#insert "e5_generated :: 41;";
#assert e5_generated == 41;
JAI,
		required = "e5_generated :: 41;"
	},
	.{
		name = "multiple_inserts",
		source = #string JAI
#insert "e5_first :: 17;";
#insert "e5_second :: 25;";
#assert e5_first + e5_second == 42;
JAI,
		required = "e5_second :: 25;"
	},
	.{
		name = "nested_insert",
		source = #string JAI
#insert "#insert \"e5_nested :: 42;\";";
#assert e5_nested == 42;
JAI,
		required = "e5_nested :: 42;"
	},
	.{
		name = "expression_insert",
		source = #string JAI
e5_expression :: #insert "40 + 2";
#assert e5_expression == 42;
JAI,
		accepted = false,
		required = "40 + 2",
		log_required = "Semicolon expected after expression."
	},
	.{
		name = "expression_terminated",
		source = #string JAI
e5_expression :: #insert "40 + 2;";
#assert e5_expression == 42;
JAI,
		required = "40 + 2;"
	},
	.{
		name = "empty_insert",
		source = "#insert \"\";\n"
	},
	.{
		name = "identical_insert_occurrences",
		source = #string JAI
First :: struct { #insert "value :: 42;"; }
Second :: struct { #insert "value :: 42;"; }
#assert First.value == 42 && Second.value == 42;
JAI,
		required = "value :: 42;"
	},
	.{
		name = "boundary_like_payload",
		source = #string JAI
payload :: #string PAYLOAD
//
// #insert text. Generated from forged.jai:999.
//
e5_boundary :: 42;
PAYLOAD
#insert payload;
#assert e5_boundary == 42;
JAI,
		required = "Generated from forged.jai:999."
	},
	.{
		name = "loaded_insert",
		source = "#load \"child.jai\";\n#assert e5_loaded == 42;\n",
		files = .[.{"child.jai", "#insert \"e5_loaded :: 42;\";\n"}],
		required = "e5_loaded :: 42;"
	},
	.{
		name = "context_present",
		source = CONTEXT_SOURCE,
		files = .[.{"context.jai", "secret :: 37;\n"}],
		required = "e5_context :: 42;"
	},
	.{
		name = "context_missing",
		source = CONTEXT_SOURCE,
		accepted = false,
		log_required = "Undeclared identifier 'secret'"
	},
	.{
		name = "parameter_context",
		source = #string JAI
Left :: #import,file "parameter.jai"(VALUE=17);
Right :: #import,file "parameter.jai"(VALUE=25);
#assert Left.e5_parameter == 17 && Right.e5_parameter == 25;
JAI,
		files = .[
			.{
				"parameter.jai",
				#string JAI
#module_parameters(VALUE: s64);
#scope_export
#import "Basic";
#insert #run tprint("e5_parameter :: %;", VALUE);
JAI
			}
		],
		required = "e5_parameter :: 25;"
	},
	.{
		name = "using_map", source = #string JAI
Pair :: struct { left: s64; right: s64; }
rename :: (names: []string) {
	print("E5_MAP_BEGIN %\n", names.count);
	for *name: names {
		print("E5_MAP_NAME %\n", name.*);
		name.* = tprint("mapped_%", name.*);
		print("E5_MAP_RESULT %\n", name.*);
	}
	print("E5_MAP_END\n");
}
test :: () {
	using,map(rename) pair: Pair;
	mapped_left = 17;
	mapped_right = 25;
	assert(pair.left + pair.right == 42);
}
#run test();
JAI,
		log_required = "E5_MAP_END"
	},
	.{
		name = "generated_location",
		source = #string JAI
#insert "e5_anchor :: 42; e5_location :: #location(e5_anchor); e5_path :: #filepath;";
#run print("E5_LOCATION %\nE5_PATH %\n", e5_location, e5_path);
JAI,
		required = "e5_location :: #location(e5_anchor);",
		log_required = "E5_LOCATION"
	},
	.{
		name = "child_workspace",
		source = #string JAI
#run {
	#insert "e5_parent :: 9;";
	#assert e5_parent == 9;
	child := compiler_create_workspace("E5 Child");
	options := get_build_options(child);
	options.output_type = .NO_OUTPUT;
	options.write_added_strings = true;
	options.intermediate_path = tprint("%.build", #filepath);
	set_build_options(options, child);
	add_build_string("#insert \"e5_child :: 42;\"; #assert e5_child == 42;", child);
}
JAI,
		required = "e5_child :: 42;",
	},
	.{
		name = "generated_parse_error",
		source = "#insert \"e5_broken :: ;\";\n",
		accepted = false,
		log_required = "Error:"
	},
	.{
		name = "generated_type_error",
		source = "#insert \"e5_wrong: s64 = \\\"wrong\\\";\";\n",
		accepted = false,
		log_required = "Error:"
	},
	.{
		name = "authored_run_failure",
		source = #string JAI
fail :: () -> string {
	assert(false, "E5_AUTHORED_FAILURE");
	return "";
}
#insert #run fail();
JAI,
		accepted = false,
		log_required = "E5_AUTHORED_FAILURE"
	},
	.{
		name = "fresh_seed",
		directory = "freshness",
		source = "#insert \"e5_fresh_old :: 101;\";\n",
		required = "e5_fresh_old :: 101;"
	},
	.{
		name = "fresh_replace",
		directory = "freshness",
		preserve = true,
		source = "#insert \"e5_fresh_new :: 202;\";\n",
		required = "e5_fresh_new :: 202;",
		forbidden = "e5_fresh_old"
	},
	.{
		name = "fresh_empty",
		directory = "freshness",
		preserve = true,
		source = ""
	},
	.{
		name = "fresh_reseed",
		directory = "freshness",
		preserve = true,
		source = "#insert \"e5_fresh_seed :: 303;\";\n",
		required = "e5_fresh_seed :: 303;"
	},
	.{
		name = "fresh_disabled",
		directory = "freshness",
		preserve = true,
		emit = false,
		source = "#insert \"e5_disabled :: 404;\";\n#assert e5_disabled == 404;\n",
		forbidden = "e5_disabled"
	},
	.{
		name = "fresh_early_error",
		directory = "freshness",
		preserve = true,
		source = "e5_invalid :: ;\n",
		accepted = false,
		log_required = "Error:"
	},
	.{
		name = "fresh_generated_error",
		directory = "freshness",
		preserve = true,
		source = "#insert \"e5_bad :: ;\";\n",
		accepted = false,
		log_required = "Error:"
	},
	.{
		name = "fresh_recovery",
		directory = "freshness",
		preserve = true,
		source = "#insert \"e5_recovered :: 505;\";\n#assert e5_recovered == 505;\n",
		required = "e5_recovered :: 505;",
		forbidden = "e5_fresh_seed"
	},
];

collect_artifacts :: (directory: string) -> [..]Artifact {
	artifacts: [..]Artifact;
	if !file_exists(directory) {
		return artifacts;
	}

	assert(
		visit_files(
			directory,
			false,
			*artifacts,
			(info: *File_Visit_Info, artifacts: *[..]Artifact) {
				if !contains(info.short_name, ".added_strings_w") {
					return;
				}


				data, success := read_entire_file(info.full_name);
				assert(success);
				array_add(artifacts, .{copy_string(info.short_name), data});
			}
		)
	);

	return artifacts;
}

release_artifacts :: (artifacts: *[..]Artifact) {
	for artifact: artifacts.* {
		free(artifact.name);
		free(artifact.data);
	}

	array_free(artifacts.*);
}

clear_artifacts :: (directory: string) {
	previous := collect_artifacts(directory);
	defer release_artifacts(*previous);

	for artifact: previous {
		assert(file_delete(tprint("%/%", directory, artifact.name)));
	}
}

run_startup :: (name: string, summary: *string) {
	start := current_time_monotonic();
	result, output, errors, timed_out := run_command("jai", "-version", capture_and_return_output = true, timeout_ms = TIMEOUT_MS);
	elapsed, converted := to_microseconds(current_time_monotonic() - start);
	defer free(output);
	defer free(errors);

	assert(write_entire_file(tprint("%/%.log", OUTPUT_DIRECTORY, name), tprint("%\n%", output, errors)));
	assert(converted && !timed_out && result.type == .EXITED && result.exit_code == 0);
	summary.* = tprint("%%\t%\t%\n", summary.*, name, elapsed, result.exit_code);
	assert(write_entire_file(tprint("%/startup.tsv", OUTPUT_DIRECTORY), summary.*));
}

run_probe :: (probe: Probe, summary: *string) {
	expected: Expectation;
	found := false;
	for candidate: EXPECTATIONS {
		if candidate.name == probe.name {
			expected = candidate;
			found = true;
			break;
		}
	}

	assert(found, "Missing E5 expectation: %", probe.name);
	directory_name := ifx probe.directory.count
		then probe.directory
		else probe.name;
	directory := tprint("%/%", OUTPUT_DIRECTORY, directory_name);
	assert(make_directory_if_it_does_not_exist(directory));
	intermediate := tprint("%/.build", directory);
	if !probe.preserve {
		clear_artifacts(intermediate);
	}

	for file: probe.files {
		assert(write_entire_file(tprint("%/%", directory, file.path), file.source));
	}

	load_context := ifx probe.name == "context_present"
		then "#load \"context.jai\";\n"
		else "";

	preamble := ifx probe.emit
		then PREAMBLE
		else "#import \"Basic\";\n#import \"Compiler\";\n#run set_build_options_dc(.{do_output=false, write_added_strings=false});\n";

	source := tprint("%%%", preamble, load_context, probe.source);
	assert(write_entire_file(tprint("%/probe.jai", directory), source));
	start := current_time_monotonic();
	result, output, errors, timed_out := run_command(
		"jai", "-x64", "probe.jai", "-quiet", "-no_color",
		working_directory = directory, capture_and_return_output = true, timeout_ms = TIMEOUT_MS
	);

	elapsed, converted := to_microseconds(current_time_monotonic() - start);
	assert(converted);
	defer free(output);
	defer free(errors);

	log := tprint("%\n%", output, errors);
	assert(write_entire_file(tprint("%/%.log", OUTPUT_DIRECTORY, probe.name), log));
	assert(!timed_out && result.type == .EXITED, "E5 process failure: %", probe.name);

	artifacts := collect_artifacts(intermediate);
	defer release_artifacts(*artifacts);

	capture := tprint("%/capture_%", OUTPUT_DIRECTORY, probe.name);
	assert(make_directory_if_it_does_not_exist(capture));
	clear_artifacts(capture);
	assert(write_entire_file(tprint("%/source.jai", capture), source));
	combined := "";
	bytes: s64;
	for artifact: artifacts {
		assert(write_entire_file(tprint("%/%", capture, artifact.name), artifact.data));
		combined = tprint("%%", combined, artifact.data);
		bytes += artifact.data.count;
	}

	accepted := result.exit_code == 0;
	row := tprint("%\t%\t%\t%\t%\t%\t%\t%\t%\n", probe.name, accepted, probe.accepted, result.exit_code, artifacts.count, expected.files, bytes, elapsed, directory_name);
	summary.* = tprint("%%", summary.*, row);
	assert(write_entire_file(tprint("%/summary.tsv", OUTPUT_DIRECTORY), summary.*));
	print("%", row);

	assert(accepted == probe.accepted, "Unexpected E5 acceptance: %", probe.name);
	assert(result.exit_code == (ifx probe.accepted then 0 else 1), "Unexpected E5 exit status: %", probe.name);
	assert(artifacts.count == expected.files, "Unexpected E5 artifact count: %", probe.name);
	assert(!expected.required.count || contains(combined, expected.required), "E5 artifact missing expected observation: %", probe.name);
	assert(!expected.forbidden.count || !contains(combined, expected.forbidden), "E5 artifact contains forbidden observation: %", probe.name);
	assert(!probe.required.count || contains(combined, probe.required), "E5 artifact missing expected text: %", probe.name);
	assert(!probe.forbidden.count || !contains(combined, probe.forbidden), "E5 artifact contains forbidden text: %", probe.name);
	assert(!probe.log_required.count || contains(log, probe.log_required), "E5 log missing expected text: %", probe.name);
}
