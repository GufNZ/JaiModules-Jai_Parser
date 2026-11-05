// Type-checks the service foundations test for Linux and macOS x64 targets without producing output, so POSIX-only branches compile on Windows.
// Run from this directory: jai service_cross_check.jai -quiet   (prints `<OS> -> <error code>`; NONE means the target type-checks).
#run {
	set_build_options_dc(.{do_output = false});
	for os: Operating_System_Tag.[.LINUX, .MACOS] {
		w := compiler_create_workspace(tprint("cross %", os));
		options := get_build_options(w);
		options.os_target = os;
		options.cpu_target = .X64;
		options.output_type = .NO_OUTPUT;
		import_path: [..] string;
		array_add(*import_path, tprint("%../..", #filepath));
		array_add(*import_path, ..options.import_path);
		options.import_path = import_path;
		set_build_options(options, w);
		compiler_begin_intercept(w);
		add_build_file(tprint("%service_foundations_test.jai", #filepath), w);
		while true {
			message := compiler_wait_for_message();
			if message.kind == .COMPLETE {
				complete := message.(*Message_Complete);
				print("% -> %\n", os, complete.error_code);
				break;
			}
		}

		compiler_end_intercept(w);
	}
}

#import "Basic";
#import "Compiler";
