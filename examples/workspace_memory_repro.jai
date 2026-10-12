#import "Basic";
#import "Compiler";
#import "String";

#run,stallable {
	arguments := get_build_options().compile_time_command_line;
	assert(arguments.count == 1, "Pass a workspace count from 0 to 16 after '-', optionally followed by ':create-only'.");
	workspace_count, valid, remainder := string_to_int(arguments[0], T=s64);
	create_only := remainder == ":create-only";
	assert(valid && (!remainder || create_only) && workspace_count >= 0 && workspace_count <= 16, "Workspace count must be an integer from 0 to 16, optionally followed by ':create-only'.");
	set_build_options_dc(.{do_output=false});

	print("Compiler: %\n", compiler_get_version_info(null));
	print("Mode: %\n", ifx create_only then "create-only" else "compile");
	completed: s64;
	while completed < workspace_count {
		workspace := compiler_create_workspace("workspace memory repro");
		assert(cast(bool) workspace);
		if create_only {
			compiler_destroy_workspace(workspace);
			completed += 1;
			continue;
		}


		child_options := get_build_options(workspace);
		child_options.output_type = .NO_OUTPUT;
		child_options.write_added_strings = false;
		set_build_options(child_options, workspace);
		compiler_begin_intercept(workspace);
		add_build_string("fixture_value :: 1;", workspace);

		found := false;
		while true {
			message := compiler_wait_for_message();
			if message.workspace != workspace {
				continue;
			}


			if message.kind == {
				case .TYPECHECKED;
					for declaration: message.(*Message_Typechecked).declarations {
						if declaration.expression.name == "fixture_value" {
							found = true;
						}
					}

				case .COMPLETE;
					assert(message.(*Message_Complete).error_code == .NONE);
					break;
			}
		}

		compiler_end_intercept(workspace);
		compiler_destroy_workspace(workspace);
		assert(found);
		completed += 1;
	}

	print("PASS %/% destroyed workspaces\n", completed, workspace_count);
}
