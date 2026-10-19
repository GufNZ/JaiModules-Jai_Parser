#import "Basic";
#import "Compiler";
#import "File";
#import "File_Utilities";
#import "Process";
#import "String";

OUTPUT_DIRECTORY :: ".build/module_identity";
TIMEOUT_MS :: 30_000;

PREAMBLE :: #string JAI
#import "Compiler";
#import "Basic";
#run set_build_options_dc(.{do_output=false, write_added_strings=false});
JAI

MODULE_SOURCE :: #string JAI
#module_parameters(VALUE := 3, LABEL := "same", FLAG := false)(MODE := 7, TRACE := false);
#scope_module
#import "Basic";
#run print("E2_INSTANCE\n");
#scope_export
Nominal :: struct { value: s64; }
value :: VALUE;
label :: LABEL;
flag :: FLAG;
mode :: MODE;
trace :: TRACE;
JAI

BRIDGE_SOURCE :: #string JAI
#module_parameters()(MODE := 7, TRACE := false);
#scope_export
Child :: #import "Identity_Probe";
mode :: MODE;
trace :: TRACE;
JAI

GRAND_SOURCE :: #string JAI
#module_parameters()(MODE := 7, TRACE := false);
#scope_export
Bridge :: #import "Identity_Bridge";
mode :: MODE;
trace :: TRACE;
JAI

OVERRIDE_SOURCE :: #string JAI
#module_parameters()(MODE := 7, TRACE := false);
#scope_export
Child :: #import "Identity_Probe"()(MODE=17, TRACE=false);
mode :: MODE;
trace :: TRACE;
JAI

PAIR_REPORT :: #string JAI
#run print("E2_SAME %\n", Left.Nominal == Right.Nominal);
#run print("E2_PAIR_VALUES % % % % % %\n", Left.value, Right.value, Left.mode, Right.mode, Left.trace, Right.trace);
JAI

GRAPH_REPORT :: #string JAI
#run print("E2_GRAPH % % % % % %\n", Grand.mode, Grand.Bridge.mode, Grand.Bridge.Child.mode, Direct.mode, Grand.Bridge.Child.Nominal == Direct.Nominal, Grand.Bridge.Child.trace);
JAI

Probe :: struct {
	name: string;
	source: string;
	accepted: bool = true;
	observe: bool;
	instances: s64 = 1;
	error: string;
}


SAME_INSTANCE_PAIRS :: string.["folded_integer", "same_partial_twice", "same_file_twice", "same_dir_twice", "program_defaults_explicit", "program_one_override"];
DOUBLE_INSTANCE_PROBES :: string.["explicit_defaults", "one_explicit_default", "different_label", "different_flag"];

Pair :: struct { name: string; left: string; right: string; }

PAIRS :: Pair.[
	.{"parameter_order",			"#import \"Identity_Probe\"(VALUE=4, LABEL=\"other\", FLAG=true)",	"#import \"Identity_Probe\"(FLAG=true, LABEL=\"other\", VALUE=4)"},
	.{"folded_integer",				"#import \"Identity_Probe\"(VALUE=3)",								"#import \"Identity_Probe\"(VALUE=1+2)"},
	.{"typed_integer",				"#import \"Identity_Probe\"(VALUE=3)",								"#import \"Identity_Probe\"(VALUE=(3).(s32))"},
	.{"partial_vs_full_defaults",	"#import \"Identity_Probe\"(VALUE=3)",								"#import \"Identity_Probe\"(VALUE=3, LABEL=\"same\", FLAG=false)"},
	.{"same_partial_twice",			"#import \"Identity_Probe\"(VALUE=3)",								"#import \"Identity_Probe\"(VALUE=3)"},
	.{"name_vs_file",				"#import \"Identity_Probe\"",										"#import,file \"../Identity_Probe/module.jai\""},
	.{"normalised_file_alias",		"#import,file \"../Identity_Probe/module.jai\"",					"#import,file \"../Identity_Probe/../Identity_Probe/module.jai\""},
	.{"name_vs_dir",				"#import \"Identity_Probe\"",										"#import,dir \"../Identity_Probe\""},
	.{"same_file_twice",			"#import,file \"../Identity_Probe/module.jai\"",					"#import,file \"../Identity_Probe/module.jai\""},
	.{"same_dir_twice",				"#import,dir \"../Identity_Probe\"",								"#import,dir \"../Identity_Probe\""},
	.{"identical_source_copy",		"#import \"Identity_Probe\"",										"#import \"Identity_Copy\""},
	.{"program_defaults_explicit",	"#import \"Identity_Probe\"",										"#import \"Identity_Probe\"()(MODE=7, TRACE=false)"},
	.{"program_one_override",		"#import \"Identity_Probe\"",										"#import \"Identity_Probe\"()(MODE=11, TRACE=true)"},
	.{"program_across_instances",	"#import \"Identity_Probe\"(VALUE=4)(MODE=11, TRACE=true)",			"#import \"Identity_Probe\"(VALUE=5)"},
	.{"different_program_values",	"#import \"Identity_Probe\"()(MODE=7)",								"#import \"Identity_Probe\"()(MODE=11)"},
	.{"same_program_values",		"#import \"Identity_Probe\"()(MODE=11, TRACE=true)",				"#import \"Identity_Probe\"()(MODE=11, TRACE=true)"},
];

PROBES :: Probe.[
	.{
		name = "same_module_twice",
		source = #string JAI
Left :: #import "Identity_Probe";
Right :: #import "Identity_Probe";
#assert Left.Nominal == Right.Nominal;
#run { left: Left.Nominal; right: Right.Nominal; right = left; }
JAI
	},
	.{
		name = "explicit_defaults",
		source = #string JAI
Left :: #import "Identity_Probe";
Right :: #import "Identity_Probe"(VALUE=3, LABEL="same", FLAG=false);
#assert Left.Nominal != Right.Nominal;
#assert Left.value == Right.value && Left.label == Right.label && Left.flag == Right.flag;
#assert type_of(Left.value) == type_of(Right.value);
JAI
	},
	.{
		name = "repeated_explicit_defaults",
		source = #string JAI
Left :: #import "Identity_Probe"(VALUE=3, LABEL="same", FLAG=false);
Right :: #import "Identity_Probe"(VALUE=3, LABEL="same", FLAG=false);
#assert Left.Nominal == Right.Nominal;
JAI
	},
	.{
		name = "one_explicit_default",
		source = #string JAI
Left :: #import "Identity_Probe";
Right :: #import "Identity_Probe"(VALUE=3);
#assert Left.Nominal != Right.Nominal;
#assert Left.value == Right.value;
JAI
	},
	.{
		name = "empty_parameter_list",
		source = #string JAI
Left :: #import "Identity_Probe";
Right :: #import "Identity_Probe"();
#assert Left.Nominal == Right.Nominal;
JAI
	},
	.{
		name = "different_value", instances = 2,
		source = #string JAI
Left :: #import "Identity_Probe";
Right :: #import "Identity_Probe"(VALUE=4);
#assert Left.Nominal != Right.Nominal;
#assert Left.value == 3 && Right.value == 4;
JAI
	},
	.{
		name = "different_label",
		source = #string JAI
Left :: #import "Identity_Probe";
Right :: #import "Identity_Probe"(LABEL="other");
#assert Left.Nominal != Right.Nominal;
JAI
	},
	.{
		name = "different_flag",
		source = #string JAI
Left :: #import "Identity_Probe";
Right :: #import "Identity_Probe"(FLAG=true);
#assert Left.Nominal != Right.Nominal;
JAI
	},
	.{
		name = "different_instance_assignment", accepted = false, instances = -1, error = "Type mismatch: incompatible structs",
		source = #string JAI
Left :: #import "Identity_Probe";
Right :: #import "Identity_Probe"(VALUE=4);
#run { left: Left.Nominal; right: Right.Nominal; right = left; }
JAI
	},
	.{
		name = "nested_import_alias",
		source = #string JAI
Left :: #import "Identity_Probe";
probe :: () { Right :: #import "Identity_Probe"; #assert Left.Nominal == Right.Nominal; }
#run,stallable probe();
JAI
	},
	.{
		name = "loaded_import_alias",
		source = #string JAI
Left :: #import "Identity_Probe";
#load "alias.jai";
#assert Left.Nominal == Loaded.Nominal;
JAI
	},
	.{
		name = "graph_default", observe = true,
		source = #string JAI
Grand :: #import "Identity_Grand";
Direct :: #import "Identity_Probe";
JAI
	},
	.{
		name = "graph_entry_defaults", observe = true,
		source = #string JAI
Grand :: #import "Identity_Grand"()(MODE=11, TRACE=true);
Direct :: #import "Identity_Probe";
JAI
	},
	.{
		name = "graph_import_override", observe = true,
		source = #string JAI
Grand :: #import "Identity_Grand";
Direct :: #import "Identity_Probe"()(MODE=19, TRACE=true);
JAI
	},
	.{
		name = "graph_child_override", observe = true,
		source = #string JAI
Bridge :: #import "Identity_Override";
Direct :: #import "Identity_Probe";
#run print("E2_OVERRIDE % % % %\n", Bridge.mode, Bridge.Child.mode, Direct.mode, Bridge.Child.Nominal == Direct.Nominal);
JAI
	},
	.{
		name = "default_instance_assignment", accepted = false, instances = -1, error = "Type mismatch: incompatible structs",
		source = #string JAI
Left :: #import "Identity_Probe";
Right :: #import "Identity_Probe"(VALUE=3);
#run { left: Left.Nominal; right: Right.Nominal; right = left; }
JAI
	},
];

run_probe :: (probe: Probe, summary: *string) {
	directory := tprint("%/%", OUTPUT_DIRECTORY, probe.name);
	assert(make_directory_if_it_does_not_exist(directory));

	source := probe.source;
	if probe.name == "graph_default" || probe.name == "graph_entry_defaults" || probe.name == "graph_import_override" {
		source = tprint("%%", source, GRAPH_REPORT);
	}

	if probe.name == "graph_default" {
		source = tprint(
			#string JAI
%#assert Grand.mode == 7 && Grand.Bridge.mode == 7 && Grand.Bridge.Child.mode == 7 && Direct.mode == 7;
#assert Grand.Bridge.Child.Nominal == Direct.Nominal;
#assert !Grand.Bridge.Child.trace;
JAI,
			source
		);
	}

	if probe.name == "graph_entry_defaults" {
		source = tprint(
			#string JAI
%#assert Grand.mode == 11 && Grand.trace;
#assert Grand.Bridge.mode == 7 && Grand.Bridge.Child.mode == 7 && Direct.mode == 7;
#assert Grand.Bridge.Child.Nominal == Direct.Nominal;
#assert !Grand.Bridge.Child.trace;
JAI,
			source
		);
	}

	if probe.name == "graph_import_override" {
		source = tprint(
			#string JAI
%#assert Grand.mode == 7 && Grand.Bridge.mode == 7;
#assert Grand.Bridge.Child.mode == 19 && Direct.mode == 19;
#assert Grand.Bridge.Child.Nominal == Direct.Nominal;
#assert Grand.Bridge.Child.trace;
JAI,
			source
		);
	}

	assert(write_entire_file(tprint("%/probe.jai", directory), tprint("%%", PREAMBLE, source)));
	assert(write_entire_file(tprint("%/alias.jai", directory), "Loaded :: #import \"Identity_Probe\";\n"));

	result, output, errors, timed_out := run_command(
		"jai", "-x64", "probe.jai", "-quiet", "-no_color", "-import_dir", "..",
		working_directory = directory,
		capture_and_return_output = true,
		timeout_ms = TIMEOUT_MS
	);

	defer free(output);
	defer free(errors);

	assert(write_entire_file(tprint("%/compile.log", directory), tprint("%\n%", output, errors)));
	assert(!timed_out && result.type == .EXITED, "E2 probe % did not complete normally.", probe.name);

	accepted := result.exit_code == 0;
	expected := probe.accepted;
	expected_error := probe.error;
	instances := probe.instances;
	for name: DOUBLE_INSTANCE_PROBES {
		if probe.name == name {
			instances = 2;
		}
	}

	if probe.name == "graph_child_override" {
		expected = false;
		instances = -1;
		expected_error = "Program parameters can only be supplied from the main program";
	}

	if probe.name == "different_program_values" || probe.name == "same_program_values" {
		expected = false;
		instances = -1;
		expected_error = "Cannot supply program parameters for the same module twice";
	}

	row := tprint("%\t%\t%\t%\t%\t%\n", probe.name, accepted, expected, result.exit_code, instances, expected_error);
	summary.* = tprint("%%", summary.*, row);
	assert(write_entire_file(tprint("%/summary.tsv", OUTPUT_DIRECTORY), summary.*));

	print("%", row);
	assert(accepted == expected, "Unexpected E2 outcome for %; inspect %/compile.log", probe.name, directory);
}

write_module :: (name: string, source: string) {
	directory := tprint("%/%", OUTPUT_DIRECTORY, name);
	assert(make_directory_if_it_does_not_exist(directory));
	assert(write_entire_file(tprint("%/module.jai", directory), source));
}

main :: () {
	assert(make_directory_if_it_does_not_exist(".build"));
	assert(make_directory_if_it_does_not_exist(OUTPUT_DIRECTORY));

	write_module("Identity_Probe", MODULE_SOURCE);
	write_module("Identity_Copy", MODULE_SOURCE);
	write_module("Identity_Bridge", BRIDGE_SOURCE);
	write_module("Identity_Grand", GRAND_SOURCE);
	write_module("Identity_Override", OVERRIDE_SOURCE);

	summary := "case\taccepted\texpected_accepted\texit_code\texpected_instances\texpected_error\n";
	for probe: PROBES {
		run_probe(probe, *summary);
	}

	for pair: PAIRS {
		probe: Probe = .{name = pair.name, source = tprint("Left :: %;\nRight :: %;\n%", pair.left, pair.right, PAIR_REPORT), observe = true};
		same := false;
		for name: SAME_INSTANCE_PAIRS {
			if pair.name == name {
				same = true;
			}
		}

		probe.source = tprint("%#assert (Left.Nominal == Right.Nominal) == %;\n", probe.source, same);
		probe.instances = ifx same then 1 else 2;
		if pair.name == "program_one_override" || pair.name == "program_across_instances" {
			probe.source = tprint("%#assert Left.mode == 11 && Right.mode == 11 && Left.trace && Right.trace;\n", probe.source);
		}

		run_probe(probe, *summary);
	}

	print("E2 complete: % isolated probes. Results: %/summary.tsv\n", PROBES.count + PAIRS.count, OUTPUT_DIRECTORY);
}

#run {
	set_build_options_dc(.{do_output = false, write_added_strings = false});
	main();
}
