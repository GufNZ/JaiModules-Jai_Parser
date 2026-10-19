/*
Live differential_test output plan (not implemented yet)

Goal: show every worker's current progress lines which differential_test outputs with a \r to not flood the scrollback, while keeping diagnostics readable and raw logs intact.

[ ] Tail each worker's existing compile.log/runtime.log incrementally.
	Keep stdout and stderr redirected to the same raw log as today.
	Open a separate, non-inherited read handle with FILE_SHARE_READ | FILE_SHARE_WRITE; the reader must allow the existing writer's GENERIC_WRITE access.
	Track byte offsets per worker and phase; do not reread the whole file each tick.
	Pump inventory output during runner_wait too, not just the job loop.
	Use bounded chunks and a per-tick budget per worker for fair draining.
	File tailing avoids pipe backpressure/deadlocks.
	Visibility still depends on child flushing: measure latency and add progress flushing only if needed.

[ ] Decode a separate terminal-line state for each worker.
	Retain incomplete UTF-8 characters, ANSI sequences and pending CR across reads.
	Treat CR as cursor-to-column-zero, not a new printed line; [CR]LF commits exactly one line, even when split between chunks.
	Handle LF, backspace, tabs and the test's clear-to-end-of-line CSI K operation.
	Keep SGR colours, but consume child cursor/erase commands locally: never forward them to the shared console.
	Discard unsupported control sequences.
	Recognize differential progress prefixes in decoded text, not by colour.
	Coalesce unterminated progress rows into the worker's latest snapshot.
	Commit newline-terminated output once, including FAIL appended to progress, compiler diagnostics, retained-fixture paths and final test summaries.

[ ] Give the parent exclusive ownership of terminal rendering.
	On a VT-capable terminal, reserve one single-line row per worker slot, labelled with job number, section, fixture range and compile/runtime phase.
	Redraw only changed snapshots; repeated CR updates must overwrite these rows rather than append new scrollback lines.  Add an option to throttle redraws with a default of 100ms but a minimum of 0.
	Before any completed child line or parent START/PASS/FAIL/metrics message, clear the live rows, print the message above them, then redraw the rows.
	Prefix child lines with job/phase so simultaneous diagnostics stay attributable; keep each worker's order, without claiming a total cross-worker time order.
	Route all parent prints through this renderer, including cleanup warnings.
	Keep the normal screen buffer so completed output remains in scrollback.
	Check terminal/VT support, enable Windows VT mode if supported, and restore the original mode on exit.
	Handle resize, clamp rows to terminal height, and truncate live rows by display width without splitting UTF-8/ANSI or wrapping at the last column.
	Completed diagnostics may wrap normally.

[ ] Provide a bounded plain-output fallback.
	When redirected or VT is unavailable, omit cursor controls and SGR; print completed lines with job prefixes, but no transient progress snapshots.
	Cap in-memory partial-line/control-sequence state; stream oversized ordinary lines in labelled chunks and mark truncated progress.
	Preserve every raw byte in the logs regardless of display limits.
	Do not buffer whole phases.

[ ] Integrate draining with lifecycle and cancellation.
	Drain before polling and before reusing a worker slot.
	At phase completion, finish reading available output, emit any unterminated diagnostic once, clear the progress row and reset decoder state before the runtime phase.
	On failure/timeout/cancellation, stop all job trees, drain their final output with a finite deadline, then print status and log paths.
	A direct process exit is not proof its descendants stopped writing.
	Keep existing timeout, memory limits, kill-on-close, exact log-marker checks and summary.tsv intact.

[ ] Test decoder/renderer helpers in the existing --self-test.
	Cover split UTF-8/SGR/CRLF, repeated CR + CSI K, appended FAIL, multiline diagnostics, oversized lines, final output without LF, phase/slot reuse, two interleaved workers, resize and non-VT capture.
	Assert bounded state, no raw child cursor escapes, exactly-once committed lines, unchanged logs and no scrollback growth from thousands of progress-only updates.
	Then run two small section jobs concurrently and verify final coverage/retention.
*/

#import "Basic";
#import "Base64";
#import "File";
#import "File_Utilities";
#import "Process";
#import "String";
#import "Windows";
#import "Windows_Utf8";

runner_kernel32 :: #library,system "kernel32";
QueryInformationJobObject :: (job: HANDLE, information_class: JOBOBJECTINFOCLASS, information: *void, information_size: u32, returned_size: *u32) -> BOOL #foreign runner_kernel32;
GetTickCount64 :: () -> u64 #foreign runner_kernel32;
Runner_Control_Handler :: #type (event: u32) -> BOOL #c_call;
SetConsoleCtrlHandler :: (handler: Runner_Control_Handler, add: BOOL) -> BOOL #foreign runner_kernel32;
SetEvent :: (event: HANDLE) -> BOOL #foreign runner_kernel32;
OpenProcess :: (desired_access: u32, inherit: BOOL, process_id: u32) -> HANDLE #foreign runner_kernel32;
GetEnvironmentVariableW :: (name: *u16, value: *u16, capacity: u32) -> u32 #foreign runner_kernel32;
SetEnvironmentVariableW :: (name: *u16, value: *u16) -> BOOL #foreign runner_kernel32;

MIB :: 1024 * 1024;
runner_cancel_event: HANDLE;

Runner_Accounting :: struct {
	total_user_time: u64;
	total_kernel_time: u64;
	period_user_time: u64;
	period_kernel_time: u64;
	page_faults: u32;
	total_processes: u32;
	active_processes: u32;
	terminated_processes: u32;
}

Runner_Section :: struct {
	name: string;
	total: s64;
	runtime: bool;
	batchable: bool;
}

Runner_Job :: struct {
	section: s64;
	first: s64;
	last: s64;
	expected: s64;
	directory: string;
}

Runner_Options :: struct {
	selection: string;
	all: bool;
	list: bool;
	self_test: bool;
	workers: s64 = 2;
	batch_size: s64 = 16;
	memory_mib: s64 = 2048;
	reserve_mib: s64 = 2048;
	timeout_seconds: s64 = 30;
	first: s64;
	last: s64;
}

Runner_Option :: enum {
	ALL;
	LIST;
	SELF_TEST;
	WORKERS;
	BATCH_SIZE;
	MEMORY_MIB;
	RESERVE_MIB;
	TIMEOUT;
	FIRST;
	LAST;
	UNKNOWN;
}

Runner_Self_Test_Mode :: enum {
	OK;
	FAIL;
	NATIVE_FAIL;
	MEMORY;
	WAIT;
	TREE;
	CANCEL;
	UNKNOWN;
}

RUNNER_SELF_TEST_NAMES :: string.["ok", "fail", "native-fail", "memory", "wait", "tree", "cancel"];

Runner_Statistics :: struct {
	max_active: s64;
	max_job_commit: u64;
	max_active_high_water_sum: u64;
	min_available_physical: u64 = 0xFFFF_FFFF_FFFF_FFFF;
	min_commit_headroom: u64 = 0xFFFF_FFFF_FFFF_FFFF;
	max_system_commit: u64;
	initial_system_commit: u64;
	cpu_time: u64;
	page_faults: u64;
}

Runner_Worker :: struct {
	info: PROCESS_INFORMATION;
	job: HANDLE;
	log: HANDLE;
	job_index: s64 = -1;
	started: u64;
	runtime_phase: bool;
}

close_worker :: (worker: *Runner_Worker) {
	if worker.job {
		CloseHandle(worker.job);
	}

	if worker.info.hThread {
		CloseHandle(worker.info.hThread);
	}

	if worker.info.hProcess {
		WaitForSingleObject(worker.info.hProcess, 5000);
		CloseHandle(worker.info.hProcess);
	}

	if worker.log {
		CloseHandle(worker.log);
	}

	worker.* = .{};
}

get_runner_environment :: (name: *u16) -> *u16, bool {
	required := GetEnvironmentVariableW(name, null, 0);
	if !required {
		return null, true;
	}


	previous := temporary_alloc(required * size_of(u16)).(*u16);
	previous[0] = 0;
	count := GetEnvironmentVariableW(name, previous, required);
	return previous, count < required && (count != 0 || required == 1);
}

start_worker :: (worker: *Runner_Worker, arguments: [] string, memory_bytes: u64, working_directory := "", log_path := "") -> bool {
	worker.job = CreateJobObjectA(null, null);
	if !worker.job {
		return false;
	}


	limits: JOBOBJECT_EXTENDED_LIMIT_INFORMATION;
	limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE | JOB_OBJECT_LIMIT_JOB_MEMORY;
	limits.JobMemoryLimit = memory_bytes.(SIZE_T);
	if !SetInformationJobObject(worker.job, .ExtendedLimitInformation, *limits, size_of(type_of(limits))) {
		close_worker(worker);
		return false;
	}


	installed: JOBOBJECT_EXTENDED_LIMIT_INFORMATION;
	if !QueryInformationJobObject(worker.job, .ExtendedLimitInformation, *installed, size_of(type_of(installed)), null) {
		close_worker(worker);
		return false;
	}


	if installed.JobMemoryLimit != limits.JobMemoryLimit || !(installed.BasicLimitInformation.LimitFlags & JOB_OBJECT_LIMIT_JOB_MEMORY) {
		close_worker(worker);
		return false;
	}


	startup: STARTUPINFOW;
	startup.cb = size_of(type_of(startup));
	input: HANDLE;
	defer if input {
		CloseHandle(input);
	}

	inherit_handles: BOOL;
	if log_path {
		security: SECURITY_ATTRIBUTES;
		security.nLength = size_of(type_of(security));
		security.bInheritHandle = 1;
		worker.log = CreateFileW(utf8_to_wide(log_path,, temp), GENERIC_WRITE, FILE_SHARE_READ, *security, CREATE_NEW);
		if worker.log == INVALID_HANDLE_VALUE {
			worker.log = null;
			close_worker(worker);
			return false;
		}


		input = CreateFileW(utf8_to_wide("NUL",, temp), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, *security);
		if input == INVALID_HANDLE_VALUE {
			input = null;
			close_worker(worker);
			return false;
		}


		startup.dwFlags = STARTF_USESTDHANDLES;
		startup.hStdInput = input;
		startup.hStdOutput = worker.log;
		startup.hStdError = worker.log;
		inherit_handles = 1;
	}


	temp_name := utf8_to_wide("TEMP",, temp);
	tmp_name := utf8_to_wide("TMP",, temp);
	previous_temp: *u16;
	previous_tmp: *u16;
	if working_directory {
		temp_valid: bool;
		tmp_valid: bool;
		previous_temp, temp_valid = get_runner_environment(temp_name);
		previous_tmp, tmp_valid = get_runner_environment(tmp_name);
		temporary_directory := tprint("%/tmp", working_directory);
		if !temp_valid || !tmp_valid || !make_directory_if_it_does_not_exist(temporary_directory) {
			close_worker(worker);
			return false;
		}


		wide_directory := utf8_to_wide(temporary_directory,, temp);
		if !SetEnvironmentVariableW(temp_name, wide_directory) {
			close_worker(worker);
			return false;
		}


		if !SetEnvironmentVariableW(tmp_name, wide_directory) {
			SetEnvironmentVariableW(temp_name, previous_temp);
			close_worker(worker);
			return false;
		}
	}


	command := get_quoted_command_string(arguments,, temp);
	created := CreateProcessW(null, utf8_to_wide(command,, temp), null, null, inherit_handles, CREATE_SUSPENDED, null, utf8_to_wide(working_directory,, temp), *startup, *worker.info);
	restored := true;
	if working_directory {
		restored_temp := SetEnvironmentVariableW(temp_name, previous_temp);
		restored_tmp := SetEnvironmentVariableW(tmp_name, previous_tmp);
		restored = restored_temp != 0 && restored_tmp != 0;
	}

	if !created || !restored {
		if worker.info.hProcess {
			TerminateProcess(worker.info.hProcess, 1);
		}

		close_worker(worker);
		return false;
	}


	if worker.log && !SetHandleInformation(worker.log, HANDLE_FLAG_INHERIT, 0) {
		TerminateProcess(worker.info.hProcess, 1);
		close_worker(worker);
		return false;
	}


	if !AssignProcessToJobObject(worker.job, worker.info.hProcess) {
		TerminateProcess(worker.info.hProcess, 1);
		close_worker(worker);
		return false;
	}


	if ResumeThread(worker.info.hThread) == -1 {
		close_worker(worker);
		return false;
	}


	return true;
}

runner_control_handler :: (event: u32) -> BOOL #c_call {
	if event == {
		case 0; #through;
		case 1; #through;
		case 2;
			SetEvent(runner_cancel_event);
			return 1;
	}


	return 0;
}

runner_cancelled :: () -> bool {
	return WaitForSingleObject(runner_cancel_event, 0) == WAIT_OBJECT_0;
}

runner_usage :: () {
	print("\e[96mUsage\e[0m: differential_runner.exe \e[93mSECTION\e[0m | \e[96m--all\e[0m | \e[96m--list\e[0m | \e[96m--self-test\e[0m\n");
	print("  \e[96m--workers\e[0m \e[93m1..4\e[0m       (default \e[93m2\e[0m)\n");
	print("  \e[96m--batch-size\e[0m \e[93m1..16\e[0m   (default \e[93m16\e[0m; batchable sections only)\n");
	print("  \e[96m--first\e[0m \e[93mN\e[0m \e[96m--last\e[0m \e[93mN\e[0m   (one batchable section, inclusive)\n");
	print("  \e[96m--memory-mib\e[0m \e[93mN\e[0m       (default \e[93m2048\e[0m per process tree; safety limit)\n");
	print("  \e[96m--reserve-mib\e[0m \e[93mN\e[0m      (default \e[93m2048\e[0m physical/commit headroom)\n");
	print("  \e[96m--timeout\e[0m \e[93mN\e[0m          (default \e[93m30\e[0m seconds per phase/admission wait)\n");
}

runner_integer :: (text: string) -> s64, bool {
	value, valid, remainder := string_to_int(text, T = s64);
	return value, valid && !remainder;
}

parse_runner_options :: (arguments: [] string) -> Runner_Options, bool {
	options: Runner_Options;
	option_names :: string.["--all", "--list", "--self-test", "--workers", "--batch-size", "--memory-mib", "--reserve-mib", "--timeout", "--first", "--last"];
	index := 1;
	while index < arguments.count {
		argument := arguments[index];
		index += 1;
		option: Runner_Option = .UNKNOWN;
		for name, option_index: option_names {
			if argument == name {
				option = option_index.(Runner_Option);
				break;
			}
		}

		if option == {
			case .ALL;
				options.all = true;

			case .LIST;
				options.list = true;

			case .SELF_TEST;
				options.self_test = true;

			case;
				if begins_with(argument, "--") {
					if index == arguments.count {
						return options, false;
					}


					value, valid := runner_integer(arguments[index]);
					index += 1;
					if !valid {
						return options, false;
					}


					if option == {
						case .WORKERS;		options.workers = value;
						case .BATCH_SIZE;	options.batch_size = value;
						case .MEMORY_MIB;	options.memory_mib = value;
						case .RESERVE_MIB;	options.reserve_mib = value;
						case .TIMEOUT;		options.timeout_seconds = value;
						case .FIRST;		options.first = value;
						case .LAST;			options.last = value;
						case;				return options, false;
					}
				} else if !options.selection {
					options.selection = argument;
				} else {
					return options, false;
				}
		}
	}


	mode_count := options.all.(s64) + xx options.list + xx options.self_test + xx !!options.selection.count;
	valid := mode_count == 1
		&& options.workers >= 1 && options.workers <= 4
		&& options.batch_size >= 1 && options.batch_size <= 16
		&& options.memory_mib >= 1024 && options.memory_mib <= 8192
		&& options.reserve_mib >= 1024 && options.reserve_mib <= 65536
		&& options.timeout_seconds >= 1 && options.timeout_seconds <= 3600
		&& options.first >= 0 && options.last >= 0
		&& (
			(!options.first && !options.last)
			|| (options.first >= 1 && options.last >= options.first && options.selection.count)
		);

	return options, valid;
}

runner_memory_status :: (statistics: *Runner_Statistics) -> MEMORYSTATUSEX, bool {
	status: MEMORYSTATUSEX;
	status.dwLength = size_of(type_of(status));
	if !GlobalMemoryStatusEx(*status) {
		return status, false;
	}


	statistics.min_available_physical = min(statistics.min_available_physical, status.ullAvailPhys);
	statistics.min_commit_headroom = min(statistics.min_commit_headroom, status.ullAvailPageFile);
	statistics.max_system_commit = max(statistics.max_system_commit, status.ullTotalPageFile - status.ullAvailPageFile);
	return status, true;
}

runner_wait :: (worker: *Runner_Worker, timeout_ms: u64) -> s32 {
	deadline := GetTickCount64() + timeout_ms;
	handles: [2] HANDLE = .[worker.info.hProcess, runner_cancel_event];
	while true {
		if runner_cancelled() {
			return 130;
		}


		if WaitForSingleObject(worker.info.hProcess, 0) == WAIT_OBJECT_0 {
			code: u32;
			if !GetExitCodeProcess(worker.info.hProcess, *code) {
				return 1;
			}


			if code > 0x7FFF_FFFF {
				return 1;
			}


			return xx code;
		}


		if GetTickCount64() >= deadline {
			return 124;
		}


		if WaitForMultipleObjects(handles.count, handles.data, 0, 50) == WAIT_FAILED {
			return 1;
		}
	}


	return 1;
}

collect_runner_sections :: (output: string, sections: *[..] Runner_Section) -> bool {
	lines := split(output, "\n");
	defer free(lines.data);

	found_header := false;
	runtime_count := 0;
	for original_line: lines {
		line := trim(original_line);
		if line == "Index\tNameBase64\tTotal\tRuntime\tBatchable" {
			if found_header {
				return false;
			}


			found_header = true;
			continue;
		}


		if !found_header || !line {
			continue;
		}


		fields := split(line, "\t");
		defer free(fields.data);

		if fields.count != 5 {
			return false;
		}


		index, index_valid := runner_integer(fields[0]);
		total, total_valid := runner_integer(fields[2]);
		name, name_valid := base64_decode(fields[1]);
		if (!index_valid
			|| index != sections.count + 1
			|| !total_valid
			|| total < 1
			|| total > 10000000
			|| !name_valid
			|| !name
			|| fields[3] != "true" && fields[3] != "false"
			|| fields[4] != "true" && fields[4] != "false"
		) {
			free(name.data);
			return false;
		}


		section: Runner_Section = .{name = name, total = total, runtime = fields[3] == "true", batchable = fields[4] == "true"};
		if section.runtime {
			runtime_count += 1;
			if section.batchable {
				free(name.data);
				return false;
			}
		}


		array_add(sections, section);
	}


	return found_header && runtime_count == 1 && sections.count && sections.*[sections.count - 1].runtime;
}

start_compiler_job :: (worker: *Runner_Worker, compiler: string, directory: string, selector: string, first: s64, last: s64, memory_bytes: u64) -> bool {
	if !make_directory_if_it_does_not_exist(directory, recursive = true) {
		return false;
	}


	source := tprint("%/differential_test.jai", directory);
	if !write_entire_file(tprint("%/job.tsv", directory), tprint("Selector\tFirst\tLast\n%\t%\t%\n", selector, first, last)) {
		return false;
	}


	if !write_entire_file(source, tprint("#load \"%differential_test.jai\";\n", #filepath)) {
		return false;
	}


	arguments: [..] string;
	defer array_free(arguments);

	array_add(*arguments, compiler, source, "-x64", "-quiet", "-", selector);
	if last {
		array_add(*arguments, tprint("%", first), tprint("%", last));
	}

	array_add(*arguments, tprint("runner-dir=%", directory));
	return start_worker(worker, arguments, memory_bytes, directory, tprint("%/compile.log", directory));
}

record_runner_worker :: (worker: *Runner_Worker, statistics: *Runner_Statistics) -> bool {
	limits: JOBOBJECT_EXTENDED_LIMIT_INFORMATION;
	accounting: Runner_Accounting;
	if (!QueryInformationJobObject(worker.job, .ExtendedLimitInformation, *limits, size_of(type_of(limits)), null)
		|| !QueryInformationJobObject(worker.job, .BasicAccountingInformation, *accounting, size_of(type_of(accounting)), null)
	) {
		return false;
	}


	statistics.max_job_commit = max(statistics.max_job_commit, xx limits.PeakJobMemoryUsed);
	statistics.cpu_time += accounting.total_user_time + accounting.total_kernel_time;
	statistics.page_faults += accounting.page_faults;
	print(
		"  phase=\e[96m%\e[0m elapsed_ms=\e[93m%\e[0m peak_commit_bytes=\e[93m%\e[0m cpu_100ns=\e[93m%\e[0m page_faults=\e[93m%\e[0m\n",
		ifx worker.runtime_phase
			then "runtime"
			else "compile",
		GetTickCount64() - worker.started,
		limits.PeakJobMemoryUsed,
		accounting.total_user_time + accounting.total_kernel_time,
		accounting.page_faults
	);

	return true;
}

clean_runner_artifact :: (info: *File_Visit_Info, ignored: s64) {
	directory, basename, extension := path_decomp(info.full_name);
	for artifact: string.["exe", "pdb", "rdi", "obj", "lib", "exp", "ilk"] {
		if extension == artifact {
			if !file_delete(info.full_name) {
				print("\e[93mWARNING\e[0m unable to remove \e[96m%\e[0m\n", info.full_name);
			}

			return;
		}
	}
}

clean_runner_job :: (directory: string) {
	visit_files(directory, recursive = false, user_data = 0, proc = clean_runner_artifact, visit_symlinks = false);
	file_delete(tprint("%/differential_test.jai", directory));
	build := tprint("%/.build", directory);
	if file_exists(build) && !delete_directory(build) {
		print("\e[93mWARNING\e[0m unable to remove \e[96m%\e[0m\n", build);
	}

	temporary_directory := tprint("%/tmp", directory);
	if file_exists(temporary_directory) && !RemoveDirectoryW(utf8_to_wide(temporary_directory,, temp)) && !delete_directory(temporary_directory) {
		print("\e[93mWARNING\e[0m unable to remove \e[96m%\e[0m\n", temporary_directory);
	}
}

runner_self_test_mode :: (name: string) -> Runner_Self_Test_Mode {
	for mode_name, index: RUNNER_SELF_TEST_NAMES {
		if name == mode_name {
			return index.(Runner_Self_Test_Mode);
		}
	}

	return .UNKNOWN;
}

run_runner_self_tests :: (root: string) -> s32 {
	executable_wide: [32768] u16;
	length := GetModuleFileNameW(null, executable_wide.data, executable_wide.count);
	if length <= 0 || length >= executable_wide.count {
		return 1;
	}


	executable, valid := wide_to_utf8(executable_wide.data, length);
	if !valid {
		return 1;
	}


	defer free(executable.data);

	worker: Runner_Worker;
	defer close_worker(*worker);

	for mode, mode_index: RUNNER_SELF_TEST_NAMES {
		arguments: [] string = .[executable, "--self-child", mode, root];
		budget: u64 = xx (ifx mode == "memory" then 64 * MIB else 1024 * MIB);
		if !start_worker(*worker, arguments, budget, root, tprint("%/%.log", root, mode)) {
			return 1;
		}


		if mode == "cancel" {
			runner_control_handler(0);
		}

		code := runner_wait(*worker, 500);
		expected: s32;
		if mode_index.(Runner_Self_Test_Mode) == {
			case .FAIL;			expected = 7;

			case .NATIVE_FAIL;	expected = 1;

			case .WAIT;			#through;
			case .TREE;			expected = 124;

			case .CANCEL;		expected = 130;
		}

		if code != expected {
			print("\e[91mFAIL\e[0m self-test \e[96m%\e[0m: expected \e[93m%\e[0m, got \e[91m%\e[0m\n", mode, expected, code);
			return 1;
		}


		descendant: HANDLE;
		defer if descendant {
			CloseHandle(descendant);
		}

		if mode == "tree" {
			pid_text, read_valid := read_entire_file(tprint("%/descendant.pid", root));
			defer free(pid_text.data);

			pid, pid_valid := runner_integer(trim(pid_text));
			if !read_valid || !pid_valid || pid <= 0 || pid > 0xFFFF_FFFF {
				return 1;
			}


			descendant = OpenProcess(0x00100000, 0, xx pid);
			if !descendant || WaitForSingleObject(descendant, 0) != WAIT_TIMEOUT {
				return 1;
			}
		}


		if expected == 124 || expected == 130 {
			process := worker.info.hProcess;
			worker.info.hProcess = null;
			close_worker(*worker);
			defer CloseHandle(process);

			if WaitForSingleObject(process, 5000) != WAIT_OBJECT_0 || (descendant && WaitForSingleObject(descendant, 5000) != WAIT_OBJECT_0) {
				print("\e[91mFAIL\e[0m kill-on-close cleanup\n");
				return 1;
			}
		} else {
			close_worker(*worker);
		}


		if mode == "ok" || mode == "memory" {
			output, read_valid := read_entire_file(tprint("%/%.log", root, mode));
			defer free(output.data);

			if !read_valid || trim(output) != (ifx mode == "ok" then "child-ok" else "memory-denied") {
				return 1;
			}
		}
	}


	SetEvent(runner_cancel_event);
	if !runner_cancelled() {
		return 1;
	}


	print("\e[92mPASS\e[0m native launch, logging, nonzero exit, memory cap, timeout, descendant cleanup and cancellation\n");
	return 0;
}

run_runner :: (arguments: [] string) -> s32 {
	if arguments.count == 1 || (arguments.count == 2 && arguments[1] == "--help") {
		runner_usage();
		return xx (ifx arguments.count == 1 then 64 else 0);
	}


	options, valid := parse_runner_options(arguments);
	if !valid {
		runner_usage();
		return 64;
	}


	runner_cancel_event = CreateEventW(null, 1, 0, null);
	if !runner_cancel_event {
		return 1;
	}


	defer {
		SetConsoleCtrlHandler(runner_control_handler, 0);
		CloseHandle(runner_cancel_event);
		runner_cancel_event = null;
	}

	if !SetConsoleCtrlHandler(runner_control_handler, 1) {
		return 1;
	}


	root := copy_string(tprint("%.build/differential_runs/run-%-%", #filepath, GetCurrentProcessId(), GetTickCount64()));
	defer free(root.data);

	if file_exists(root) || !make_directory_if_it_does_not_exist(root, recursive = true) {
		print("\e[91mUnable to create\e[0m fresh run directory: \e[96m%\e[0m\n", root);
		return 1;
	}


	print("Logs: \e[96m%\e[0m\n", root);
	if options.self_test {
		return run_runner_self_tests(root);
	}


	statistics: Runner_Statistics;
	status, memory_valid := runner_memory_status(*statistics);
	if !memory_valid {
		return 1;
	}


	statistics.initial_system_commit = status.ullTotalPageFile - status.ullAvailPageFile;
	memory_bytes: u64 = xx (options.memory_mib * MIB);
	reserve_bytes: u64 = xx (options.reserve_mib * MIB);
	if status.ullAvailPhys < memory_bytes + reserve_bytes || status.ullAvailPageFile < memory_bytes + reserve_bytes {
		print("\e[93mInsufficient physical/commit headroom\e[0m for one worker and the reserve.\n");
		return 75;
	}


	compiler := tprint("%../../../bin/jai.exe", #filepath);
	if !file_exists(compiler) {
		print("\e[91mCompiler not found\e[0m: \e[96m%\e[0m\n", compiler);
		return 1;
	}


	compiler = copy_string(compiler);
	defer free(compiler.data);

	started := GetTickCount64();
	inventory_directory := tprint("%/inventory", root);
	inventory: Runner_Worker;
	defer close_worker(*inventory);

	if !start_compiler_job(*inventory, compiler, inventory_directory, "list-machine", 0, 0, memory_bytes) {
		print("\e[91mUnable to launch\e[0m inventory compiler.\n");
		return 1;
	}


	inventory.started = GetTickCount64();
	code := runner_wait(*inventory, xx (options.timeout_seconds * 1000));
	if code != 0 || !record_runner_worker(*inventory, *statistics) {
		print("Inventory \e[91mfailed\e[0m (exit \e[91m%\e[0m). See \e[96m%/compile.log\e[0m\n", code, inventory_directory);
		return xx (ifx code != 0 then code else 1);
	}


	close_worker(*inventory);
	output, read_valid := read_entire_file(tprint("%/compile.log", inventory_directory));
	if !read_valid {
		return 1;
	}


	defer free(output.data);

	sections: [..] Runner_Section;
	defer {
		for sections {
			free(it.name.data);
		}
		array_free(sections);
	}

	if !collect_runner_sections(output, *sections) {
		print("\e[91mInvalid differential inventory\e[0m. See \e[96m%/compile.log\e[0m\n", inventory_directory);
		return 1;
	}


	clean_runner_job(inventory_directory);
	if options.list {
		for section, index: sections {
			print("\e[93m%\e[0m\t\e[96m%\e[0m\t\e[93m%\e[0m fixtures\tbatchable=\e[93m%\e[0m\truntime=\e[93m%\e[0m\n", index + 1, section.name, section.total, section.batchable, section.runtime);
		}
		return 0;
	}


	jobs: [..] Runner_Job;
	defer {
		for jobs {
			free(it.directory.data);
		}
		array_free(jobs);
	}

	expected_total: s64;
	selected_sections: s64;
	selection_index, selection_is_index := runner_integer(options.selection);
	for section, index: sections {
		if !options.all && options.selection != section.name && (!selection_is_index || selection_index != index + 1) {
			continue;
		}


		selected_sections += 1;
		if options.last && (!section.batchable || options.last > section.total) {
			print("Fixture range is \e[91minvalid\e[0m for section \e[96m%\e[0m.\n", section.name);
			return 64;
		}


		first := ifx options.first
			then options.first
			else 1;
		last := ifx options.last
			then options.last
			else section.total;
		expected_total += last - first + 1;
		while first <= last {
			batch_last := ifx section.batchable
				then min(last, first + options.batch_size - 1)
				else last;

			job: Runner_Job = .{
				section = index,
				first = ifx section.batchable
					then first
					else 0,
				last = ifx section.batchable
					then batch_last
					else 0,
				expected = batch_last - first + 1
			};

			job.directory = copy_string(tprint("%/job-%", root, jobs.count + 1));
			array_add(*jobs, job);
			first = batch_last + 1;
		}
	}

	if !selected_sections {
		print("\e[91mUnknown section\e[0m: \e[96m%\e[0m\n", options.selection);
		return 64;
	}


	workers: [4] Runner_Worker;
	defer {
		for *workers {
			close_worker(it);
		}
	}

	print(
		"\e[96mPlan\e[0m: \e[93m%\e[0m sections, \e[93m%\e[0m fixtures, \e[93m%\e[0m jobs; workers=\e[93m%\e[0m, batch_size=\e[93m%\e[0m, safety_mib=\e[93m%\e[0m, reserve_mib=\e[93m%\e[0m\n",
		selected_sections,
		expected_total,
		jobs.count,
		options.workers,
		options.batch_size,
		options.memory_mib,
		options.reserve_mib
	);
	finished: s64;
	next_job: s64;
	covered: s64;
	admission_started := GetTickCount64();
	while finished < jobs.count {
		reset_temporary_storage();
		if runner_cancelled() {
			print("\e[93mCancelled\e[0m; stopping all worker trees. Logs: \e[96m%\e[0m\n", root);
			return 130;
		}


		status, memory_valid = runner_memory_status(*statistics);
		if !memory_valid {
			return 1;
		}


		active: s64;
		high_water_sum: u64;
		for *worker: workers {
			if !worker.info.hProcess {
				continue;
			}


			limits: JOBOBJECT_EXTENDED_LIMIT_INFORMATION;
			if !QueryInformationJobObject(worker.job, .ExtendedLimitInformation, *limits, size_of(type_of(limits)), null) {
				return 1;
			}


			high_water_sum += xx limits.PeakJobMemoryUsed;
			job := jobs[worker.job_index];
			section := sections[job.section];
			wait_status := WaitForSingleObject(worker.info.hProcess, 0);
			if wait_status == {
				case WAIT_OBJECT_0;
					exit_code: u32;
					if !GetExitCodeProcess(worker.info.hProcess, *exit_code) || !record_runner_worker(worker, *statistics) {
						return 1;
					}


					if exit_code != 0 {
						print("\e[91mFAIL\e[0m job \e[93m%\e[0m [\e[96m%\e[0m \e[93m%\e[0m..\e[93m%\e[0m] exit=\e[91m%\e[0m. Logs: \e[96m%\e[0m\n", worker.job_index + 1, section.name, job.first, job.last, exit_code, job.directory);
						return 1;
					}


					job_index := worker.job_index;
					runtime_phase := worker.runtime_phase;
					close_worker(worker);
					phase_log := tprint("%/%.log", job.directory, ifx runtime_phase then "runtime" else "compile");
					phase_output, phase_valid := read_entire_file(phase_log);
					if !phase_valid {
						return 1;
					}


					defer free(phase_output.data);

					marker := ifx runtime_phase
						then tprint("%/% tests", job.expected, job.expected)
						else tprint("compile-time checks (%/% total tests)", ifx section.runtime then 0 else job.expected, job.expected);

					if find_index_from_left(phase_output, marker) < 0 || (runtime_phase && find_index_from_left(phase_output, "Differential runtime retained: 0 allocations, 0 bytes") < 0) {
						print("\e[91mFAIL\e[0m missing exact fixture/retention result in \e[96m%\e[0m\n", phase_log);
						return 1;
					}


					if section.runtime && !runtime_phase {
						runtime_arguments: [] string = .[tprint("%/differential_test.exe", job.directory)];
						if !start_worker(worker, runtime_arguments, memory_bytes, job.directory, tprint("%/runtime.log", job.directory)) {
							print("\e[91mUnable to launch\e[0m runtime checks. Logs: \e[96m%\e[0m\n", job.directory);
							return 1;
						}


						worker.job_index = job_index;
						worker.runtime_phase = true;
						worker.started = GetTickCount64();
						active += 1;
					} else {
						finished += 1;
						covered += job.expected;
						print("\e[92mPASS\e[0m job \e[93m%\e[0m/\e[93m%\e[0m [\e[96m%\e[0m \e[93m%\e[0m..\e[93m%\e[0m] fixtures=\e[93m%\e[0m covered=\e[92m%\e[0m/\e[93m%\e[0m\n", job_index + 1, jobs.count, section.name, job.first, job.last, job.expected, covered, expected_total);
						clean_runner_job(job.directory);
					}

				case WAIT_TIMEOUT;
					if GetTickCount64() - worker.started >= xx (options.timeout_seconds * 1000) {
						print("\e[93mTIMEOUT\e[0m job \e[93m%\e[0m [\e[96m%\e[0m \e[93m%\e[0m..\e[93m%\e[0m]; stopping worker trees. Logs: \e[96m%\e[0m\n", worker.job_index + 1, section.name, job.first, job.last, job.directory);
						return 124;
					}


					active += 1;

				case;
					return 1;
			}
		}


		statistics.max_active_high_water_sum = max(statistics.max_active_high_water_sum, high_water_sum);

		for *worker: workers {
			if worker.info.hProcess || next_job == jobs.count || active >= options.workers {
				continue;
			}


			reservation := (active + 1).(u64) * memory_bytes + reserve_bytes;
			if status.ullAvailPhys < reservation || status.ullAvailPageFile < reservation {
				break;
			}


			job := jobs[next_job];
			section := sections[job.section];
			if !start_compiler_job(worker, compiler, job.directory, tprint("%", job.section + 1), job.first, job.last, memory_bytes) {
				print("\e[91mUnable to launch\e[0m job \e[93m%\e[0m. Logs: \e[96m%\e[0m\n", next_job + 1, job.directory);
				return 1;
			}


			worker.job_index = next_job;
			worker.started = GetTickCount64();
			print("\e[96mSTART\e[0m job \e[93m%\e[0m/\e[93m%\e[0m [\e[96m%\e[0m \e[93m%\e[0m..\e[93m%\e[0m] pid=\e[93m%\e[0m\n", next_job + 1, jobs.count, section.name, job.first, job.last, worker.info.dwProcessId);
			next_job += 1;
			active += 1;
			admission_started = GetTickCount64();
		}


		statistics.max_active = max(statistics.max_active, active);
		if finished == jobs.count {
			break;
		}


		if !active && GetTickCount64() - admission_started >= xx (options.timeout_seconds * 1000) {
			print("\e[93mTimed out\e[0m waiting for physical/commit headroom. Logs: \e[96m%\e[0m\n", root);
			return 75;
		}


		handles: [5] HANDLE;
		handle_count: u32 = 1;
		handles[0] = runner_cancel_event;
		for worker: workers {
			if worker.info.hProcess {
				handles[handle_count] = worker.info.hProcess;
				handle_count += 1;
			}
		}

		if WaitForMultipleObjects(handle_count, handles.data, 0, 50) == WAIT_FAILED {
			return 1;
		}
	}


	if covered != expected_total {
		print("\e[91mFAIL\e[0m coverage: \e[91m%\e[0m/\e[93m%\e[0m fixtures\n", covered, expected_total);
		return 1;
	}


	elapsed := GetTickCount64() - started;
	summary := tprint(
		"Sections\tFixtures\tJobs\tElapsedMs\tMaxActive\tMaxJobCommitBytes\tMaxActiveJobHighWaterSumBytes\tMinAvailablePhysicalBytes\tMinCommitHeadroomBytes\tInitialSystemCommitBytes\tMaxSystemCommitBytes\tCpu100ns\tPageFaults\n%\t%\t%\t%\t%\t%\t%\t%\t%\t%\t%\t%\t%\n",
		selected_sections,
		covered,
		finished,
		elapsed,
		statistics.max_active,
		statistics.max_job_commit,
		statistics.max_active_high_water_sum,
		statistics.min_available_physical,
		statistics.min_commit_headroom,
		statistics.initial_system_commit,
		statistics.max_system_commit,
		statistics.cpu_time,
		statistics.page_faults
	);
	if !write_entire_file(tprint("%/summary.tsv", root), summary) {
		return 1;
	}


	print(
		"\e[92mPASS\e[0m \e[93m%\e[0m sections, \e[92m%\e[0m/\e[93m%\e[0m fixtures, \e[92m%\e[0m/\e[93m%\e[0m jobs; elapsed_ms=\e[93m%\e[0m, max_active=\e[93m%\e[0m, max_job_commit_bytes=\e[93m%\e[0m\n",
		selected_sections,
		covered,
		expected_total,
		finished,
		jobs.count,
		elapsed,
		statistics.max_active,
		statistics.max_job_commit
	);
	print("Summary: \e[96m%/summary.tsv\e[0m\n", root);

	return 0;
}

main :: () {
	arguments := get_command_line_arguments();
	defer free(arguments.data);

	if (arguments.count == 3 || arguments.count == 4) && arguments[1] == "--self-child" {
		if runner_self_test_mode(arguments[2]) == {
			case .OK;
				if arguments.count == 4 {
					for name: string.["TEMP", "TMP"] {
						value, valid := get_runner_environment(utf8_to_wide(name,, temp));
						if !valid || !value {
							exit(7);
						}


						text, converted := wide_to_utf8(value,, temp);
						if !converted || text != tprint("%/tmp", arguments[3]) {
							exit(7);
						}
					}
				}

				print("child-ok\n");
				return;

			case .FAIL;
				exit(7);

			case .NATIVE_FAIL;
				exit(-1);

			case .MEMORY;
				allocation := VirtualAlloc(null, 128 * MIB, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE);
				if allocation {
					VirtualFree(allocation, 0, MEM_RELEASE);
					exit(7);
				}


				print("memory-denied\n");
				return;

			case .TREE;
				if arguments.count != 4 {
					exit(64);
				}


				child: Runner_Worker;
				defer close_worker(*child);

				child_arguments: [] string = .[arguments[0], "--self-child", "wait"];
				assert(start_worker(*child, child_arguments, 1024 * MIB));
				assert(write_entire_file(tprint("%/descendant.pid", arguments[3]), tprint("%", child.info.dwProcessId)));
				WaitForSingleObject(child.info.hProcess, INFINITE);
				return;

			case .WAIT; #through;
			case .CANCEL;
				event := CreateEventW(null, 1, 0, null);
				WaitForSingleObject(event, INFINITE);
				CloseHandle(event);
				return;
		}


		exit(64);
	}


	code := run_runner(arguments);
	if code != 0 {
		exit(code);
	}
}
