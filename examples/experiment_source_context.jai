#import "Basic";
#import "Compiler";
#import "File";
#import "File_Utilities";
#import "Process";

OUTPUT_DIRECTORY :: ".build/source_context";
TIMEOUT_MS :: 30_000;

PREAMBLE :: #string JAI
#import "Compiler";
#import "Basic";
#run set_build_options_dc(.{do_output=false, write_added_strings=false});
JAI

MODULE_SOURCE :: #string JAI
#scope_module
#import "Basic";
#scope_export
Nominal :: struct {}
source_directory :: #filepath;
anchor :: 21;
source_location :: #location(anchor);
#load "neighbor.jai";
Sibling :: #import,file "sibling.jai";
sibling_value :: Sibling.value;
#run print("E4_UNIT\n");
JAI

PAIR_REPORT :: #string JAI
#run print("E4_SAME %\n", Left.Nominal == Right.Nominal);
#run print("E4_LEFT_PATH %\n", Left.source_directory);
#run print("E4_RIGHT_PATH %\n", Right.source_directory);
#run print("E4_LEFT_LOCATION %\n", Left.source_location);
#run print("E4_RIGHT_LOCATION %\n", Right.source_location);
#run print("E4_VALUES % % % %\n", Left.neighbor_value, Right.neighbor_value, Left.sibling_value, Right.sibling_value);
#assert Left.neighbor_value == Left.sibling_value;
#assert Right.neighbor_value == Right.sibling_value;
JAI

LOAD_REPORT :: #string JAI
#run print("E4_PATH %\n", source_directory);
#run print("E4_LOCATION %\n", source_location);
#run print("E4_VALUES % %\n", neighbor_value, sibling_value);
#assert neighbor_value == sibling_value;
JAI

LINK_SCRIPT :: #string JAI
$ErrorActionPreference = "Stop"
$kind = "%"
$target = (Resolve-Path -LiteralPath "%").Path
$alias = "%"
if (!(Test-Path -LiteralPath $alias)) {
	New-Item -ItemType $kind -Path $alias -Target $target | Out-Null
}
$item = Get-Item -LiteralPath $alias
if ($item.LinkType -ne $kind -or $item.Target -ne $target) {
	throw "Existing alias does not match the required link"
}
Write-Output "LinkType=$($item.LinkType)"
Write-Output "Target=$($item.Target)"
JAI

Probe :: struct {
	name: string;
	source: string;
	accepted: bool = true;
	pair: bool;
	load_report: bool;
	absolute: bool;
	from_branch: bool;
	link: string;
	same: s64 = -1;
	units: s64 = -1;
	error: string;
	directory: string = "Original/";
	filename: string = "Original/module.jai";
	right_directory: string = "Original/";
	right_filename: string = "Original/module.jai";
	line: s64 = 6;
	values: string;
}

PROBES :: Probe.[
	.{
		name="entry_location",
		units=0,
		directory="",
		filename="probe.jai",
		line=4,
		source=#string JAI
anchor :: 21;
#run print("E4_PATH %\n", #filepath);
#run print("E4_LOCATION %\n", #location(anchor));
JAI
	},
	.{
		name="loaded_location",
		units=1,
		source=#string JAI
#load "Original/module.jai";
#assert neighbor_value == 11 && sibling_value == 11;
#run print("E4_PATH %\n", source_directory);
#run print("E4_LOCATION %\n", source_location);
JAI
	},
	.{
		name="module_location",
		units=1,
		source=#string JAI
Unit :: #import,dir "Original";
#assert Unit.neighbor_value == 11 && Unit.sibling_value == 11;
#run print("E4_PATH %\n", Unit.source_directory);
#run print("E4_LOCATION %\n", Unit.source_location);
JAI
	},
	.{
		name="relocated_location",
		units=1,
		directory="Copy/",
		filename="Copy/module.jai",
		source=#string JAI
Unit :: #import,dir "Copy";
#assert Unit.neighbor_value == 22 && Unit.sibling_value == 22;
#run print("E4_PATH %\n", Unit.source_directory);
#run print("E4_LOCATION %\n", Unit.source_location);
JAI
	},
	.{
		name="dot_load",
		units=1,
		directory="./Original/",
		filename="./Original/module.jai",
		load_report=true,
		source=#string JAI
#load "./Original/module.jai";
JAI
	},
	.{
		name="parent_load",
		units=1,
		directory="Branch/../Original/",
		filename="Branch/../Original/module.jai",
		load_report=true,
		source=#string JAI
#load "Branch/../Original/module.jai";
JAI
	},
	.{
		name="case_load",
		accepted=false,
		error="Non-matching Windows file case",
		load_report=true,
		source=#string JAI
#load "original/MODULE.JAI";
JAI
	},
	.{
		name="directory_case_load",
		units=1,
		directory="original/",
		filename="original/module.jai",
		load_report=true,
		source=#string JAI
#load "original/module.jai";
JAI
	},
	.{
		name="separator_load",
		units=1,
		load_report=true,
		source=#string JAI
#load "Original\\module.jai";
JAI
	},
	.{
		name="exact_file_pair",
		units=1,
		same=1,
		pair=true,
		source=#string JAI
Left :: #import,file "Original/module.jai";
Right :: #import,file "Original/module.jai";
JAI
	},
	.{
		name="dot_file_pair",
		units=2,
		same=0,
		right_directory="./Original/",
		right_filename="./Original/module.jai",
		pair=true,
		source=#string JAI
Left :: #import,file "Original/module.jai";
Right :: #import,file "./Original/module.jai";
JAI
	},
	.{
		name="parent_file_pair",
		units=2,
		same=0,
		right_directory="Branch/../Original/",
		right_filename="Branch/../Original/module.jai",
		pair=true,
		source=#string JAI
Left :: #import,file "Original/module.jai";
Right :: #import,file "Branch/../Original/module.jai";
JAI
	},
	.{
		name="case_file_pair",
		accepted=false,
		error="Non-matching Windows file case",
		pair=true,
		source=#string JAI
Left :: #import,file "Original/module.jai";
Right :: #import,file "original/MODULE.JAI";
JAI
	},
	.{
		name="separator_file_pair",
		units=2,
		same=0,
		right_directory="Original\\",
		right_filename="Original\\module.jai",
		pair=true,
		source=#string JAI
Left :: #import,file "Original/module.jai";
Right :: #import,file "Original\\module.jai";
JAI
	},
	.{
		name="copy_file_pair",
		units=2,
		same=0,
		right_directory="Copy/",
		right_filename="Copy/module.jai",
		values="11 22 11 22",
		pair=true,
		source=#string JAI
Left :: #import,file "Original/module.jai";
Right :: #import,file "Copy/module.jai";
JAI
	},
	.{
		name="same_directory_copy_pair",
		units=2,
		same=0,
		right_filename="Original/copy.jai",
		pair=true,
		source=#string JAI
Left :: #import,file "Original/module.jai";
Right :: #import,file "Original/copy.jai";
JAI
	},
	.{
		name="exact_dir_pair",
		units=1,
		same=1,
		pair=true,
		source=#string JAI
Left :: #import,dir "Original";
Right :: #import,dir "Original";
JAI
	},
	.{
		name="dot_dir_pair",
		units=2,
		same=0,
		right_directory="./Original/",
		right_filename="./Original/module.jai",
		pair=true,
		source=#string JAI
Left :: #import,dir "Original";
Right :: #import,dir "./Original";
JAI
	},
	.{
		name="parent_dir_pair",
		units=2,
		same=0,
		right_directory="Branch/../Original/",
		right_filename="Branch/../Original/module.jai",
		pair=true,
		source=#string JAI
Left :: #import,dir "Original";
Right :: #import,dir "Branch/../Original";
JAI
	},
	.{
		name="case_dir_pair",
		accepted=false,
		error="Non-matching Windows file case",
		pair=true,
		source=#string JAI
Left :: #import,dir "Original";
Right :: #import,dir "original";
JAI
	},
	.{
		name="copy_dir_pair",
		units=2,
		same=0,
		right_directory="Copy/",
		right_filename="Copy/module.jai",
		values="11 22 11 22",
		pair=true,
		source=#string JAI
Left :: #import,dir "Original";
Right :: #import,dir "Copy";
JAI
	},
	.{
		name="absolute_file_pair",
		units=1,
		same=1,
		pair=true,
		absolute=true,
		source=#string JAI
Left :: #import,file "Original/module.jai";
Right :: #import,file "%/Original/module.jai";
JAI
	},
	.{
		name="absolute_load",
		units=1,
		load_report=true,
		absolute=true,
		source=#string JAI
#load "%/Original/module.jai";
JAI
	},
	.{
		name="missing_relative_neighbor",
		accepted=false,
		error="Unable to open file",
		source=#string JAI
Unit :: #import,dir "Isolated";
JAI
	},
	.{
		name="entry_from_branch",
		units=1,
		directory="",
		filename="probe.jai",
		line=4,
		from_branch=true,
		source=#string JAI
anchor :: 21;
#run print("E4_PATH %\n", #filepath);
#run print("E4_LOCATION %\n", #location(anchor));
Unit :: #import,dir "Original";
#assert Unit.neighbor_value == 11 && Unit.sibling_value == 11;
JAI
	},
	.{
		name="junction_load",
		units=1,
		directory="Alias/",
		filename="Alias/module.jai",
		link="Junction",
		load_report=true,
		source=#string JAI
#load "Alias/module.jai";
JAI
	},
	.{
		name="junction_file_pair",
		units=2,
		same=0,
		right_directory="Alias/",
		right_filename="Alias/module.jai",
		link="Junction",
		pair=true,
		source=#string JAI
Left :: #import,file "Original/module.jai";
Right :: #import,file "Alias/module.jai";
JAI
	},
	.{
		name="junction_dir_pair",
		accepted=false,
		error="Non-matching Windows file case",
		link="Junction",
		pair=true,
		source=#string JAI
Left :: #import,dir "Original";
Right :: #import,dir "Alias";
JAI
	},
	.{
		name="symlink_load",
		units=1,
		directory="Alias/",
		filename="Alias/module.jai",
		link="SymbolicLink",
		load_report=true,
		source=#string JAI
#load "Alias/module.jai";
JAI
	},
	.{
		name="symlink_file_pair",
		units=2,
		same=0,
		right_directory="Alias/",
		right_filename="Alias/module.jai",
		link="SymbolicLink",
		pair=true,
		source=#string JAI
Left :: #import,file "Original/module.jai";
Right :: #import,file "Alias/module.jai";
JAI
	},
	.{
		name="symlink_dir_pair",
		accepted=false,
		error="Non-matching Windows file case",
		link="SymbolicLink",
		pair=true,
		source=#string JAI
Left :: #import,dir "Original";
Right :: #import,dir "Alias";
JAI
	},
	.{
		name="file_symlink_load",
		accepted=false,
		error="Non-matching Windows file case",
		link="FileSymbolicLink",
		load_report=true,
		source=#string JAI
#load "module_alias.jai";
JAI
	},
	.{
		name="file_symlink_pair",
		accepted=false,
		error="Non-matching Windows file case",
		link="FileSymbolicLink",
		pair=true,
		source=#string JAI
Left :: #import,file "Original/module.jai";
Right :: #import,file "module_alias.jai";
JAI
	},
	.{
		name="directory_case_file_pair",
		units=2,
		same=0,
		right_directory="original/",
		right_filename="original/module.jai",
		pair=true,
		source=#string JAI
Left :: #import,file "Original/module.jai";
Right :: #import,file "original/module.jai";
JAI
	},
	.{
		name="junction_same_leaf_dir_pair",
		units=2,
		same=0,
		right_directory="Branch/Original/",
		right_filename="Branch/Original/module.jai",
		link="JunctionSameLeaf",
		pair=true,
		source=#string JAI
Left :: #import,dir "Original";
Right :: #import,dir "Branch/Original";
JAI
	},
];

prepare_link :: (directory: string, link: string) -> bool {
	kind := link;
	target := "Original";
	alias := "Alias";
	if link == "JunctionSameLeaf" {
		kind = "Junction";
		alias = "Branch/Original";
	}

	if link == "FileSymbolicLink" {
		kind = "SymbolicLink";
		target = "Original/module.jai";
		alias = "module_alias.jai";
	}

	result, output, errors, timed_out := run_command(
		"pwsh", "-NoProfile", "-Command", tprint(LINK_SCRIPT, kind, target, alias),
		working_directory=directory, capture_and_return_output=true, timeout_ms=TIMEOUT_MS
	);
	defer free(output);
	defer free(errors);

	assert(write_entire_file(tprint("%/link.log", directory), tprint("%\n%", output, errors)));
	assert(!timed_out && result.type == .EXITED, "E4 link setup did not complete normally: %", directory);
	return (result.exit_code == 0);
}

record_result :: (probe: Probe, accepted: string, exit_code: string, summary: *string) {
	expected := tprint("%", probe.accepted);
	error_count := ifx probe.accepted then 0 else 1;

	values := probe.values;
	if !values {
		if probe.pair {
			values = "11 11 11 11";
		} else if probe.load_report {
			values = "11 11";
		}
	}

	row := tprint("%\t%\t%\t%\t%\t%\t%\t%\t%\t%\t%\t%\t%\t%\t%\n",
		probe.name, accepted, expected, exit_code, probe.units, probe.same, probe.error, error_count,
		probe.link, probe.directory, probe.filename, probe.right_directory, probe.right_filename, probe.line, values
	);
	summary.* = tprint("%%", summary.*, row);
	assert(write_entire_file(tprint("%/summary.tsv", OUTPUT_DIRECTORY), summary.*));
	print("%", row);
}

run_probe :: (probe: Probe, summary: *string) {
	directory := tprint("%/%", OUTPUT_DIRECTORY, probe.name);
	assert(make_directory_if_it_does_not_exist(directory));

	for name: string.["Original", "Copy", "Branch", "Isolated"] {
		assert(make_directory_if_it_does_not_exist(tprint("%/%", directory, name)));
	}

	for name: string.["Original", "Copy", "Isolated"] {
		assert(write_entire_file(tprint("%/%/module.jai", directory, name), MODULE_SOURCE));
	}

	assert(write_entire_file(tprint("%/Original/copy.jai", directory), MODULE_SOURCE));
	assert(write_entire_file(tprint("%/Original/neighbor.jai", directory), "#scope_export\nneighbor_value :: 11;\n"));
	assert(write_entire_file(tprint("%/Copy/neighbor.jai", directory), "#scope_export\nneighbor_value :: 22;\n"));
	assert(write_entire_file(tprint("%/neighbor.jai", directory), "#scope_export\nneighbor_value :: 99;\n"));
	assert(write_entire_file(tprint("%/Original/sibling.jai", directory), "#scope_export\nvalue :: 11;\n"));
	assert(write_entire_file(tprint("%/Copy/sibling.jai", directory), "#scope_export\nvalue :: 22;\n"));
	assert(write_entire_file(tprint("%/sibling.jai", directory), "#scope_export\nvalue :: 99;\n"));
	source := probe.source;
	if probe.absolute {
		absolute_directory := tprint("%%", #filepath, directory);
		source = tprint(source, absolute_directory);
	}

	if probe.pair {
		source = tprint("%%", source, PAIR_REPORT);
		if probe.same >= 0 {
			source = tprint("%#assert (Left.Nominal == Right.Nominal) == %;\n", source, probe.same == 1);
		}
	}

	if probe.load_report {
		source = tprint("%%", source, LOAD_REPORT);
	}

	assert(write_entire_file(tprint("%/probe.jai", directory), tprint("%%", PREAMBLE, source)));
	if probe.link && !prepare_link(directory, probe.link) {
		record_result(probe, "skipped", "", summary);
		return;
	}

	working_directory := directory;
	entry := "probe.jai";
	if probe.from_branch {
		working_directory = tprint("%/Branch", directory);
		entry = "../probe.jai";
	}

	result, output, errors, timed_out := run_command(
		"jai", "-x64", entry, "-quiet", "-no_color",
		working_directory=working_directory, capture_and_return_output=true, timeout_ms=TIMEOUT_MS
	);
	defer free(output);
	defer free(errors);

	assert(write_entire_file(tprint("%/compile.log", directory), tprint("%\n%", output, errors)));
	assert(!timed_out && result.type == .EXITED, "E4 case % did not complete normally; inspect its compile.log", probe.name);
	accepted := result.exit_code == 0;
	record_result(probe, tprint("%", accepted), tprint("%", result.exit_code), summary);
	assert(accepted == probe.accepted, "Unexpected E4 outcome for %; inspect its compile.log", probe.name);
}

main :: () {
	assert(make_directory_if_it_does_not_exist(".build"));
	assert(make_directory_if_it_does_not_exist(OUTPUT_DIRECTORY));
	summary := "case\taccepted\texpected_accepted\texit_code\texpected_units\texpected_same\texpected_error\texpected_error_count\tlink\texpected_directory\texpected_filename\texpected_right_directory\texpected_right_filename\texpected_line\texpected_values\n";

	for probe: PROBES {
		run_probe(probe, *summary);
	}

	print("E4 complete: % isolated probes. Results: %/summary.tsv\n", PROBES.count, OUTPUT_DIRECTORY);
}

#run {
	set_build_options_dc(.{do_output=false, write_added_strings=false});
	main();
}
