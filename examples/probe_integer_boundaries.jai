/*
Verified with Jai beta `0.2.031` on Windows x64, 2026-11-27:
260 cases: 225 matched range expectations, 35 mismatches, 0 probe errors.

`s8`:  `-129` converted to `127`.
`s16`: `-32769` converted to `32767`.
`s32`: `-2147483649` converted to `2147483647`.
`s64`: `9223372036854775808` converted to `-9223372036854775808`.
`u8`, `u16`, `u32`: `-9223372036854775808` converted to `0`; `u64` rejected it.

Each mismatch occurs in all five forms, including assignment, so the behavior is not specific to overload resolution.
Build with `jai -x64 probe_integer_boundaries.jai` and run the executable; exit 1 denotes mismatches and exit 2 denotes a probe error.
The program prints the artifact directory containing `results.tsv` and the standalone repros and logs.
*/

#import "Basic";
#import "File";
#import "File_Utilities";
#import "Process";
#import "String";

TIMEOUT_MS :: 30_000;
REJECTED :: "rejected";

Boundary :: struct {
	target: string;
	below_min: string;
	minimum: string;
	min_plus_one: string;
	max_minus_one: string;
	maximum: string;
	above_max: string;
}

BOUNDARIES :: Boundary.[
	.{"s8", "-129", "-128", "-127", "126", "127", "128"},
	.{"s16", "-32769", "-32768", "-32767", "32766", "32767", "32768"},
	.{"s32", "-2147483649", "-2147483648", "-2147483647", "2147483646", "2147483647", "2147483648"},
	.{"s64", "-9223372036854775809", "-9223372036854775808", "-9223372036854775807", "9223372036854775806", "9223372036854775807", "9223372036854775808"},
	.{"u8", "-1", "0", "1", "254", "255", "256"},
	.{"u16", "-1", "0", "1", "65534", "65535", "65536"},
	.{"u32", "-1", "0", "1", "4294967294", "4294967295", "4294967296"},
	.{"u64", "-1", "0", "1", "18446744073709551614", "18446744073709551615", "18446744073709551616"},
];

Form :: struct {
	name: string;
	named: bool;
	overload: bool;
}

FORMS :: Form.[
	.{name = "assignment"},
	.{name = "call_literal"},
	.{name = "call_named", named = true},
	.{name = "overload_literal", overload = true},
	.{name = "overload_named", named = true, overload = true},
];

Probe :: struct {
	directory: string;
	total: int;
	mismatches: int;
	errors: int;
	rows: String_Builder;
}

main :: () {
	version, output, errors, timed_out := run_command(
		"jai", "-version",
		capture_and_return_output = true,
		timeout_ms = TIMEOUT_MS
	);
	defer free(output);
	defer free(errors);

	if timed_out || version.type != .EXITED || version.exit_code != 0 {
		print("Unable to run jai -version:\n%%", output, errors);
		exit(2);
	}

	print("%%", output, errors);
	root := tprint("%.build", #filepath);
	if !make_directory_if_it_does_not_exist(root) {
		exit(2);
	}

	directory: string;
	for 1..10_000 {
		candidate := tprint("%/integer-boundaries-jai-%", root, it);
		if !file_exists(candidate) && make_directory_if_it_does_not_exist(candidate) {
			directory = candidate;
			break;
		}
	}

	if !directory.count {
		print("Could not create a probe directory in %.\n", root);
		exit(2);
	}

	probe := Probe.{directory = directory};
	defer free_buffers(*probe.rows);

	print("Probe artifacts: %\n", directory);
	print_to_builder(*probe.rows, "type\tboundary\tvalue\tform\texpected\tobserved\tverdict\n");
	for boundary: BOUNDARIES {
		probe_boundary(*probe, boundary.target, "below_min", boundary.below_min, REJECTED);
		probe_boundary(*probe, boundary.target, "min", boundary.minimum, boundary.minimum);
		probe_boundary(*probe, boundary.target, "min_plus_one", boundary.min_plus_one, boundary.min_plus_one);
		probe_boundary(*probe, boundary.target, "max_minus_one", boundary.max_minus_one, boundary.max_minus_one);
		probe_boundary(*probe, boundary.target, "max", boundary.maximum, boundary.maximum);
		probe_boundary(*probe, boundary.target, "above_max", boundary.above_max, REJECTED);
		if boundary.target[0] == #char "u" {
			probe_boundary(*probe, boundary.target, "signed_min", BOUNDARIES[3].minimum, REJECTED);
		}
	}

	rows := builder_to_string(*probe.rows);
	defer free(rows);

	if !write_entire_file(tprint("%/results.tsv", directory), rows) {
		print("Could not write results.tsv.\n");
		exit(2);
	}

	print(
		"\n% cases: % matched range expectations, % mismatches, % probe errors.\n",
		probe.total,
		probe.total - probe.mismatches - probe.errors,
		probe.mismatches,
		probe.errors
	);

	if probe.errors {
		exit(2);
	}

	if probe.mismatches {
		exit(1);
	}
}

probe_boundary :: (probe: *Probe, target: string, boundary: string, value: string, expected: string) {
	for form: FORMS {
		auto_release_temp();
		source := make_source(target, value, form);
		stem := tprint("%_%_%", target, boundary, form.name);
		observed, probe_error := compile_and_run(probe.directory, stem, source);
		probe.total += 1;
		verdict := "match";
		if probe_error {
			verdict = "error";
			probe.errors += 1;
		} else if observed != expected {
			verdict = "mismatch";
			probe.mismatches += 1;
		}

		print_to_builder(
			*probe.rows,
			"%\t%\t%\t%\t%\t%\t%\n",
			target,
			boundary,
			value,
			form.name,
			expected,
			observed,
			verdict
		);

		if verdict != "match" {
			print("% % (%), %: expected %, observed %\n", target, boundary, value, form.name, expected, observed);
		}
	}
}

make_source :: (target: string, value: string, form: Form) -> string {
	preamble :: "#import \"Basic\";\n\n";
	if form.name == "assignment" {
		return tprint("%main :: () {\n\tvalue: % = %;\n\tprint(\"%\", value);\n}\n", preamble, target, value, "%");
	}

	argument := ifx form.named then "constant" else value;
	declaration := ifx form.named then tprint("\tconstant :: %;\n", value) else "";
	overload := ifx form.overload then "take :: (value: string) { print(\"unexpected string: %\", value); }\n" else "";
	return tprint(
		"%take :: (value: %) { print(\"%\", value); }\n%\nmain :: () {\n%\ttake(%);\n}\n",
		preamble,
		target,
		"%",
		overload,
		declaration,
		argument
	);
}

compile_and_run :: (directory: string, stem: string, source: string) -> observed: string, probe_error: bool {
	file := tprint("%.jai", stem);
	if !write_entire_file(tprint("%/%", directory, file), source) {
		return "source-write-error", true;
	}

	compiled, output, errors, timed_out := run_command(
		"jai", "-x64", file, "-no_color",
		working_directory = directory,
		capture_and_return_output = true,
		timeout_ms = TIMEOUT_MS
	);
	defer free(output);
	defer free(errors);

	log := tprint("%%", output, errors);
	if !write_entire_file(tprint("%/%.compile.log", directory, stem), log) {
		return "compile-log-write-error", true;
	}

	if timed_out || compiled.type != .EXITED {
		return "compile-error", true;
	}

	if compiled.exit_code != 0 {
		if contains(log, "Error:") && contains(log, tprint("%:", file)) {
			return REJECTED, false;
		}

		return "compile-error", true;
	}

	suffix :: #ifx OS == .WINDOWS then ".exe" else "";
	executable := tprint("%/%%", directory, stem, suffix);
	ran, runtime_output, runtime_errors, runtime_timed_out := run_command(
		executable,
		working_directory = directory,
		capture_and_return_output = true,
		timeout_ms = TIMEOUT_MS
	);
	defer free(runtime_output);
	defer free(runtime_errors);

	if !write_entire_file(tprint("%/%.runtime.log", directory, stem), runtime_errors) {
		return "runtime-log-write-error", true;
	}

	if runtime_timed_out || ran.type != .EXITED || ran.exit_code != 0 {
		return "runtime-error", true;
	}

	return tprint("%", trim(runtime_output)), false;
}
