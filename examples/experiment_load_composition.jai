#import "Basic";
#import "Compiler";
#import "File";
#import "File_Utilities";
#import "Process";

OUTPUT_DIRECTORY :: ".build/load_composition";
TIMEOUT_MS :: 30_000;

PREAMBLE :: #string JAI
#import "Compiler";
#import "Basic";
#run set_build_options_dc(.{do_output=false, write_added_strings=false});
JAI

SHARED :: #string JAI
#scope_export
shared_value :: 41;
Shared_Type :: struct {}
#run print("E3_SHARED\n");
JAI

MARKER_ONLY :: #string JAI
#run print("E3_SHARED\n");
JAI

PARAMETER_MODULE :: #string JAI
#module_parameters(SETTING := 2);
#scope_module
#import "Basic";
#scope_export
#load "../shared.jai";
JAI

PARAMETER_SHARED :: #string JAI
#scope_export
loaded_value :: SETTING;
Loaded_Type :: struct {}
private_value :: () -> s64 { return hidden; }
#scope_file
hidden :: SETTING + 10;
#run print("E3_SHARED\n");
JAI

Source_File :: struct { path: string; source: string; }

Probe :: struct {
	name: string;
	entry: string;
	files: []Source_File;
	expected_accepted: s64 = -1;
	expected_shared: s64 = -1;
}

Expectation :: struct { name: string; accepted: bool; shared: s64; error: string; error_count: s64; }
EXPECTATIONS :: Expectation.[
	.{"single_load",					true,	1,	"",														0},
	.{"repeated_load",					false,	-1,	"Redeclaration of",										4},
	.{"diamond_load",					false,	-1,	"Redeclaration of",										4},
	.{"traversal_alias",				false,	-1,	"Redeclaration of",										4},
	.{"relative_to_loaded_file",		true,	0,	"",														0},
	.{"forward_reference",				true,	1,	"",														0},
	.{"order_first_second",				true,	0,	"",														0},
	.{"order_second_first",				true,	0,	"",														0},
	.{"file_private_loader",			false,	-1,	"Undeclared identifier 'hidden'",						1},
	.{"file_private_sibling",			false,	-1,	"Undeclared identifier 'hidden'",						1},
	.{"loader_private_loaded",			false,	-1,	"Undeclared identifier 'hidden'",						1},
	.{"file_private_independent",		true,	0,	"",														0},
	.{"scope_does_not_leak",			true,	0,	"",														0},
	.{"self_load",						false,	-1,	"Too many nested loads. (The maximum number is 100.)",	1},
	.{"load_cycle",						false,	-1,	"Too many nested loads. (The maximum number is 100.)",	1},
	.{"missing_load",					false,	-1,	"Unable to open file", 1},
	.{"repeated_marker",				true,	2,	"",														0},
	.{"diamond_marker",					true,	2,	"",														0},
	.{"alias_marker",					true,	2,	"",														0},
	.{"repeated_file_private",			true,	2,	"",														0},
	.{"same_module_instance",			true,	1,	"",														0},
	.{"different_module_parameters",	true,	2,	"",														0},
	.{"different_modules_same_load",	true,	2,	"",														0},
	.{"loader_private_child_default",	true,	0,	"",														0},
	.{"file_scoped_named_import",		false,	-1,	"Undeclared identifier 'Bound'",						1},
	.{"module_scoped_named_import",		true,	1,	"",														0},
	.{"file_scoped_bare_import",		true,	1,	"",														0},
	.{"public_collision",				false,	-1,	"Redeclaration of 'colliding'",							2},
];

PROBES :: Probe.[
	.{
		name = "single_load",
		expected_accepted = 1,
		expected_shared = 1,
		files = .[.{"shared.jai", SHARED}],
		entry = #string JAI
#load "shared.jai";
#assert shared_value == 41;
JAI
	},
	.{
		name = "repeated_load",
		files = .[.{"shared.jai", SHARED}],
		entry = #string JAI
#load "shared.jai";
#load "shared.jai";
#assert shared_value == 41;
JAI
	},
	.{
		name = "diamond_load",
		files = .[
			.{"shared.jai", SHARED},
			.{
				"first.jai",
				#string JAI
#load "shared.jai";
JAI
			},
			.{
				"second.jai",
				#string JAI
#load "shared.jai";
JAI
			},
		],
		entry = #string JAI
#load "first.jai";
#load "second.jai";
#assert shared_value == 41;
JAI
	},
	.{
		name = "traversal_alias",
		files = .[.{"shared.jai", SHARED}],
		entry = #string JAI
#load "shared.jai";
#load "branch/../shared.jai";
#assert shared_value == 41;
JAI
	},
	.{
		name = "relative_to_loaded_file",
		files = .[
			.{
				"branch/parent.jai",
				#string JAI
#load "child.jai";
JAI
			},
			.{
				"branch/child.jai",
				#string JAI
#scope_export
relative_value :: 52;
JAI
			},
			.{
				"child.jai",
				#string JAI
#scope_export
relative_value :: 99;
JAI
			},
		],
		entry = #string JAI
#load "branch/parent.jai";
#assert relative_value == 52;
JAI
	},
	.{
		name = "forward_reference",
		files = .[.{"shared.jai", SHARED}],
		entry = #string JAI
#assert shared_value == 41;
#load "shared.jai";
JAI
	},
	.{
		name = "order_first_second",
		files = .[
			.{
				"first.jai",
				#string JAI
#scope_export
answer :: input + 1;
JAI
			},
			.{
				"second.jai",
				#string JAI
#scope_export
input :: 41;
JAI
			},
		],
		entry = #string JAI
#load "first.jai";
#load "second.jai";
#assert answer == 42;
JAI
	},
	.{
		name = "order_second_first",
		files = .[
			.{
				"first.jai",
				#string JAI
#scope_export
answer :: input + 1;
JAI
			},
			.{
				"second.jai",
				#string JAI
#scope_export
input :: 41;
JAI
			},
		],
		entry = #string JAI
#load "second.jai";
#load "first.jai";
#assert answer == 42;
JAI
	},
	.{
		name = "file_private_loader",
		files = .[
			.{
				"private.jai",
				#string JAI
#scope_file
hidden :: 61;
JAI
			},
		],
		entry = #string JAI
#load "private.jai";
#assert hidden == 61;
JAI
	},
	.{
		name = "file_private_sibling",
		files = .[
			.{
				"private.jai",
				#string JAI
#scope_file
hidden :: 61;
JAI
			},
			.{
				"observer.jai",
				#string JAI
#assert hidden == 61;
JAI
			},
		],
		entry = #string JAI
#load "private.jai";
#load "observer.jai";
JAI
	},
	.{
		name = "loader_private_loaded",
		files = .[
			.{
				"observer.jai",
				#string JAI
#assert hidden == 61;
JAI
			},
		],
		entry = #string JAI
#scope_file
hidden :: 61;
#load "observer.jai";
JAI
	},
	.{
		name = "file_private_independent",
		files = .[
			.{
				"first.jai",
				#string JAI
#scope_export
first_value :: () -> s64 { return hidden; }
#scope_file
hidden :: 11;
JAI
			},
			.{
				"second.jai",
				#string JAI
#scope_export
second_value :: () -> s64 { return hidden; }
#scope_file
hidden :: 22;
JAI
			},
		],
		entry = #string JAI
#load "first.jai";
#load "second.jai";
#assert first_value() == 11 && second_value() == 22;
JAI
	},
	.{
		name = "scope_does_not_leak",
		files = .[
			.{
				"private.jai",
				#string JAI
#scope_file
hidden :: 61;
JAI
			},
			.{
				"observer.jai",
				#string JAI
#assert loader_value == 73;
JAI
			},
		],
		entry = #string JAI
#scope_export
#load "private.jai";
loader_value :: 73;
#load "observer.jai";
JAI
	},
	.{
		name = "self_load",
		files = .[
			.{
				"shared.jai",
				#string JAI
#scope_export
#load "shared.jai";
shared_value :: 41;
#run print("E3_SHARED\n");
JAI
			},
		],
		entry = #string JAI
#load "shared.jai";
#assert shared_value == 41;
JAI
	},
	.{
		name = "load_cycle",
		files = .[
			.{
				"first.jai",
				#string JAI
#scope_export
#load "second.jai";
first_value :: 11;
#run print("E3_SHARED\n");
JAI
			},
			.{
				"second.jai",
				#string JAI
#scope_export
#load "first.jai";
second_value :: 22;
JAI
			},
		],
		entry = #string JAI
#load "first.jai";
#assert first_value == 11 && second_value == 22;
JAI
	},
	.{
		name = "missing_load",
		files = .[],
		entry = #string JAI
#load "absent.jai";
JAI
	},
	.{
		name = "repeated_marker",
		files = .[.{"shared.jai", MARKER_ONLY}],
		entry = #string JAI
#load "shared.jai";
#load "shared.jai";
JAI
	},
	.{
		name = "diamond_marker",
		files = .[
			.{"shared.jai", MARKER_ONLY},
			.{
				"first.jai",
				#string JAI
#load "shared.jai";
JAI
			},
			.{
				"second.jai",
				#string JAI
#load "shared.jai";
JAI
			},
		],
		entry = #string JAI
#load "first.jai";
#load "second.jai";
JAI
	},
	.{
		name = "alias_marker",
		files = .[.{"shared.jai", MARKER_ONLY}],
		entry = #string JAI
#load "shared.jai";
#load "branch/../shared.jai";
JAI
	},
	.{
		name = "repeated_file_private",
		files = .[
			.{
				"shared.jai",
				#string JAI
#scope_file
hidden :: 11;
#assert hidden == 11;
#run print("E3_SHARED\n");
JAI
			},
		],
		entry = #string JAI
#load "shared.jai";
#load "shared.jai";
JAI
	},
	.{
		name = "same_module_instance",
		files = .[
			.{"First/module.jai", PARAMETER_MODULE},
			.{"shared.jai", PARAMETER_SHARED}
		],
		entry = #string JAI
Left :: #import,dir "First";
Right :: #import,dir "First";
#assert Left.Loaded_Type == Right.Loaded_Type;
#assert Left.loaded_value == 2 && Right.private_value() == 12;
JAI
	},
	.{
		name = "different_module_parameters",
		files = .[
			.{"First/module.jai", PARAMETER_MODULE},
			.{"shared.jai", PARAMETER_SHARED}
		],
		entry = #string JAI
Left :: #import,dir "First"(SETTING=2);
Right :: #import,dir "First"(SETTING=5);
#assert Left.Loaded_Type != Right.Loaded_Type;
#assert Left.loaded_value == 2 && Right.loaded_value == 5;
#assert Left.private_value() == 12 && Right.private_value() == 15;
JAI
	},
	.{
		name = "different_modules_same_load",
		files = .[
			.{"First/module.jai", PARAMETER_MODULE},
			.{"Second/module.jai", PARAMETER_MODULE},
			.{"shared.jai", PARAMETER_SHARED}
		],
		entry = #string JAI
Left :: #import,dir "First";
Right :: #import,dir "Second";
#assert Left.Loaded_Type != Right.Loaded_Type;
#assert Left.loaded_value == 2 && Right.loaded_value == 2;
#assert Left.private_value() == 12 && Right.private_value() == 12;
JAI
	},
	.{
		name = "loader_private_child_default",
		files = .[
			.{
				"child.jai",
				#string JAI
child_value :: 87;
JAI
			},
			.{
				"observer.jai",
				#string JAI
#assert child_value == 87;
JAI
			},
		],
		entry = #string JAI
#scope_file
#load "child.jai";
#load "observer.jai";
JAI
	},
	.{
		name = "file_scoped_named_import",
		files = .[
			.{
				"binding.jai",
				#string JAI
#scope_file
Bound :: #import,dir "First";
JAI
			},
			.{"First/module.jai", PARAMETER_MODULE},
			.{"shared.jai", PARAMETER_SHARED},
		],
		entry = #string JAI
#load "binding.jai";
#assert Bound.loaded_value == 2;
JAI
	},
	.{
		name = "module_scoped_named_import",
		files = .[
			.{
				"binding.jai",
				#string JAI
#scope_module
Bound :: #import,dir "First";
JAI
			},
			.{"First/module.jai", PARAMETER_MODULE},
			.{"shared.jai", PARAMETER_SHARED},
		],
		entry = #string JAI
#load "binding.jai";
#assert Bound.loaded_value == 2;
JAI
	},
	.{
		name = "file_scoped_bare_import",
		files = .[
			.{
				"binding.jai",
				#string JAI
#scope_file
#import,dir "First";
JAI
			},
			.{"First/module.jai", PARAMETER_MODULE},
			.{"shared.jai", PARAMETER_SHARED},
		],
		entry = #string JAI
#load "binding.jai";
#assert loaded_value == 2;
JAI
	},
	.{
		name = "public_collision",
		files = .[
			.{
				"first.jai",
				#string JAI
#scope_export
colliding :: 1;
JAI
			},
			.{
				"second.jai",
				#string JAI
#scope_export
colliding :: 1;
JAI
			},
		],
		entry = #string JAI
#load "first.jai";
#load "second.jai";
JAI
	},
];

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

	assert(found, "Missing E3 expectation for %", probe.name);
	directory := tprint("%/%", OUTPUT_DIRECTORY, probe.name);
	assert(make_directory_if_it_does_not_exist(directory));
	assert(make_directory_if_it_does_not_exist(tprint("%/branch", directory)));
	assert(make_directory_if_it_does_not_exist(tprint("%/First", directory)));
	assert(make_directory_if_it_does_not_exist(tprint("%/Second", directory)));

	for file: probe.files {
		assert(write_entire_file(tprint("%/%", directory, file.path), file.source));
	}

	assert(write_entire_file(tprint("%/probe.jai", directory), tprint("%%", PREAMBLE, probe.entry)));
	result, output, errors, timed_out := run_command(
		"jai", "-x64", "probe.jai", "-quiet", "-no_color",
		working_directory = directory, capture_and_return_output = true, timeout_ms = TIMEOUT_MS
	);

	defer free(output);
	defer free(errors);

	assert(write_entire_file(tprint("%/compile.log", directory), tprint("%\n%", output, errors)));
	assert(!timed_out && result.type == .EXITED, "E3 case % did not complete normally; inspect its compile.log", probe.name);
	accepted := result.exit_code == 0;
	row := tprint("%\t%\t%\t%\t%\t%\t%\n", probe.name, accepted, expected.accepted, result.exit_code, expected.shared, expected.error, expected.error_count);
	summary.* = tprint("%%", summary.*, row);
	assert(write_entire_file(tprint("%/summary.tsv", OUTPUT_DIRECTORY), summary.*));
	print("%", row);

	if probe.expected_accepted >= 0 {
		assert(accepted == (probe.expected_accepted == 1), "Unexpected E3 outcome for %", probe.name);
	}

	assert(accepted == expected.accepted, "Unexpected E3 outcome for %; inspect its compile.log", probe.name);
}

main :: () {
	assert(make_directory_if_it_does_not_exist(".build"));
	assert(make_directory_if_it_does_not_exist(OUTPUT_DIRECTORY));
	assert(PROBES.count == EXPECTATIONS.count);
	summary := "case\taccepted\texpected_accepted\texit_code\texpected_shared\texpected_error\texpected_error_count\n";
	for probe: PROBES {
		run_probe(probe, *summary);
	}

	print("E3 complete: % isolated probes. Results: %/summary.tsv\n", PROBES.count, OUTPUT_DIRECTORY);
}

#run {
	set_build_options_dc(.{do_output = false, write_added_strings = false});
	main();
}
