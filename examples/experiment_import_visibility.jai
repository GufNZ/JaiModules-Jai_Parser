#import "Basic";
#import "Compiler";
#import "File";
#import "File_Utilities";
#import "Process";
#import "String";


Scope :: enum {	FILE;	PROCEDURE;	BLOCK;	STRUCT; }
SCOPES :: Scope.[.FILE,	.PROCEDURE,	.BLOCK,	.STRUCT];

Site :: enum { INSIDE;	AFTER;	SIBLING;	OTHER_PROCEDURE;	GLOBAL;		LOADED_FILE;	LOADING_FILE; }
SITES :: Site.[.INSIDE,	.AFTER,	.SIBLING,	.OTHER_PROCEDURE,	.GLOBAL,	.LOADED_FILE,	.LOADING_FILE];

SCOPE_NAMES :: string.["file", "procedure", "block", "struct"];
SITE_NAMES :: string.["inside", "after", "sibling", "other_procedure", "global", "loaded_file", "loading_file"];

OUTPUT_DIRECTORY :: ".build/import_visibility";
TIMEOUT_MS :: 30_000;

Marker :: struct { name: string; value: s64; }
MARKERS :: Marker.[
	.{"e1_exported", 1101},
	.{"e1_module", 1102},
	.{"e1_file", 1103},
	.{"e1_loaded_exported", 1201},
	.{"e1_loaded_module", 1202},
	.{"e1_loaded_file", 1203},
];

PREAMBLE :: #string JAI
#import "Compiler";
#run set_build_options_dc(.{do_output=false, write_added_strings=false});
JAI

MODULE_SOURCE :: #string JAI
#scope_export
#load "module_loaded.jai";
e1_exported :: 1101;
#scope_module
e1_module :: 1102;
#scope_file
e1_file :: 1103;
JAI

LOADED_SOURCE :: #string JAI
#scope_export
e1_loaded_exported :: 1201;
#scope_module
e1_loaded_module :: 1202;
#scope_file
e1_loaded_file :: 1203;
JAI

site_applies :: (scope: Scope, site: Site) -> bool {
	if scope == .FILE {
		return site == .INSIDE || site == .OTHER_PROCEDURE || site == .LOADED_FILE || site == .LOADING_FILE;
	}


	if scope == .PROCEDURE {
		return site == .INSIDE || site == .OTHER_PROCEDURE || site == .GLOBAL || site == .LOADED_FILE || site == .LOADING_FILE;
	}


	if scope == .STRUCT {
		return site != .AFTER;
	}


	return true;
}

make_source :: (scope: Scope, site: Site, named: bool, expression: string, value: s64) -> string {
	prefix := "";
	if named {
		prefix = "Probe :: ";
	}

	import_text := tprint("%#import \"Visibility_Probe\";\n", prefix);
	check := "";
	if expression {
		check = tprint("#assert % == %;\n", expression, value);
	}

	if site == .LOADING_FILE {
		return tprint("%#load \"observer.jai\";\n%", PREAMBLE, check);
	}


	inside := "";
	if site == .INSIDE {
		inside = check;
	}

	body := "";
	if scope == {
		case .FILE;
			body = tprint("%%", import_text, inside);

		case .PROCEDURE;
			body = tprint("probe :: () {\n%%}\n#run,stallable probe();\n", import_text, inside);

		case .BLOCK;
			after := "";
			if site == .AFTER {
				after = check;
			}

			if site == .SIBLING {
				after = tprint("{\n%}\n", check);
			}

			body = tprint("probe :: () {\n{\n%%}\n%}\n#run,stallable probe();\n", import_text, inside, after);

		case .STRUCT;
			member := "";
			if site == .INSIDE && expression {
				member = tprint("observed :: %;\n", expression);
			}

			body = tprint("Container :: struct {\n%%}\n", import_text, member);
			if member {
				body = tprint("%#assert Container.observed == %;\n", body, value);
			}

			if site == .SIBLING {
				body = tprint("%Other :: struct { observed :: %; }\n#assert Other.observed == %;\n", body, expression, value);
			}
	}

	if site == .OTHER_PROCEDURE {
		body = tprint("%observer :: () {\n%}\n#run,stallable observer();\n", body, check);
	}

	if site == .GLOBAL {
		body = tprint("%%", body, check);
	}

	if site == .LOADED_FILE {
		body = tprint("%#load \"observer.jai\";\n", body);
	}

	return tprint("%%", PREAMBLE, body);
}

run_probe :: (index: s64, scope: Scope, site: Site, named: bool, marker: Marker, access: string, expression: string, summary: *string) -> bool {
	directory := tprint("%/case_%", OUTPUT_DIRECTORY, index);
	assert(make_directory_if_it_does_not_exist(directory));
	source := make_source(scope, site, named, expression, marker.value);
	assert(write_entire_file(tprint("%/probe.jai", directory), source));
	observer := "";
	if site == .LOADED_FILE {
		observer = tprint("#assert % == %;\n", expression, marker.value);
	}

	if site == .LOADING_FILE {
		observer = make_source(scope, .INSIDE, named, "", marker.value);
	}

	assert(write_entire_file(tprint("%/observer.jai", directory), observer));
	result, output, errors, timed_out := run_command(
		"jai", "-x64", "probe.jai", "-quiet", "-no_color",
		"-import_dir", "..",
		working_directory = directory, capture_and_return_output = true, timeout_ms = TIMEOUT_MS
	);

	defer free(output);
	defer free(errors);

	assert(write_entire_file(tprint("%/compile.log", directory), tprint("%\n%", output, errors)));
	assert(!timed_out && result.type == .EXITED, "Probe % did not complete normally; inspect %/compile.log", index, directory);

	accepted := (result.exit_code == 0);
	form := "bare";
	if named {
		form = "named";
	}

	status := "rejected";
	if accepted {
		status = "accepted";
	}

	row := tprint("%\t%\t%\t%\t%\t%\t%\t%\n", index, SCOPE_NAMES[scope.(s64)], form, SITE_NAMES[site.(s64)], access, marker.name, status, result.exit_code);
	summary.* = tprint("%%", summary.*, row);
	assert(write_entire_file(tprint("%/summary.tsv", OUTPUT_DIRECTORY), summary.*));

	print("%", row);
	expected := (access == "control");
	if access == "bare" {
		expected = (marker.name == "e1_exported" || marker.name == "e1_loaded_exported");
	}

	if access == "qualified" {
		in_scope := (scope == .FILE || site == .INSIDE);
		file_private := (marker.name == "e1_file" || marker.name == "e1_loaded_file");
		expected = (in_scope && !file_private);
	}

	assert(accepted == expected, "Unexpected E1 outcome for case %; inspect %/compile.log", index, directory);
	return accepted;
}

main :: () {
	assert(make_directory_if_it_does_not_exist(".build"));
	assert(make_directory_if_it_does_not_exist(OUTPUT_DIRECTORY));
	module_directory := tprint("%/Visibility_Probe", OUTPUT_DIRECTORY);
	assert(make_directory_if_it_does_not_exist(module_directory));
	assert(write_entire_file(tprint("%/module.jai", module_directory), MODULE_SOURCE));
	assert(write_entire_file(tprint("%/module_loaded.jai", module_directory), LOADED_SOURCE));

	summary := "case\tscope\timport\tsite\taccess\tmarker\tresult\texit_code\n";
	index: s64;
	accepted_count: s64;

	for scope: SCOPES {
		for named_index: 0..1 {
			named := named_index == 1;
			control: Marker = .{"control", 0};
			index += 1;
			allowed := run_probe(index, scope, .INSIDE, named, control, "control", "", *summary);
			if allowed {
				accepted_count += 1;
			}

			if scope == .FILE {
				assert(allowed, "Top-level import control failed.");
			}

			if !allowed {
				continue;
			}


			for site: SITES {
				if !site_applies(scope, site) {
					continue;
				}


				for marker: MARKERS {
					expression := marker.name;
					access := "bare";
					if named {
						expression = tprint("Probe.%", marker.name);
						access = "qualified";
					}

					index += 1;
					accepted := run_probe(index, scope, site, named, marker, access, expression, *summary);
					if accepted {
						accepted_count += 1;
					}

					if scope == .FILE && site == .INSIDE && marker.name == "e1_exported" {
						assert(accepted, "Exported-marker positive control failed.");
					}
				}
			}

			if named {
				for marker: MARKERS {
					index += 1;
					accepted := run_probe(index, scope, .INSIDE, named, marker, "unqualified_named_control", marker.name, *summary);
					if accepted {
						accepted_count += 1;
					}
				}
			}
		}
	}

	print("E1 complete: % isolated probes, % accepted, % rejected. Results: %/summary.tsv\n", index, accepted_count, index - accepted_count, OUTPUT_DIRECTORY);
}

#run {
	set_build_options_dc(.{do_output = false, write_added_strings = false});
	main();
}
