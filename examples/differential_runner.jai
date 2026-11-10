/*
Live differential_test output checklist

Goal: show every worker's current progress lines which differential_test outputs with a \r to not flood the scrollback, while keeping diagnostics readable and raw logs intact.

[x] Tail each worker's existing compile.log/runtime.log incrementally.
	Keep stdout and stderr redirected to the same raw log as today.
	Open a separate, non-inherited read handle with FILE_SHARE_READ | FILE_SHARE_WRITE; the reader must allow the existing writer's GENERIC_WRITE access.
	Track byte offsets per worker and phase; do not reread the whole file each tick.
	Pump inventory output during runner_wait too, not just the job loop.
	Use bounded chunks and a per-tick budget per worker for fair draining.
	File tailing avoids pipe backpressure/deadlocks.
	Visibility still depends on child flushing: measure latency and add progress flushing only if needed.

[x] Decode a separate terminal-line state for each worker.
	Retain incomplete UTF-8 characters, ANSI sequences and pending CR across reads.
	Treat CR as cursor-to-column-zero, not a new printed line; [CR]LF commits exactly one line, even when split between chunks.
	Handle LF, backspace, tabs and the test's clear-to-end-of-line CSI K operation.
	Keep SGR colours, but consume child cursor/erase commands locally: never forward them to the shared console.
	Discard unsupported control sequences.
	Recognize differential progress prefixes in decoded text, not by colour.
	Coalesce unterminated progress rows into the worker's latest snapshot.
	Commit newline-terminated output once, including FAIL appended to progress, compiler diagnostics, retained-fixture paths and final test summaries.
	In bounded interactive mode, keep the latest committed line in its worker row; retain full diagnostics in raw logs.

[x] Give the parent exclusive ownership of terminal rendering.
	On a VT-capable terminal, reserve one single-line row per worker slot, labelled with job number, section, fixture range and compile/runtime phase.
	Redraw only changed snapshots; repeated CR updates must overwrite these rows rather than append new scrollback lines.  Add an option to throttle redraws with a default of 100ms but a minimum of 0.
	Completed child lines and parent START/PASS/FAIL/metrics messages update the existing worker rows; never append messages above or below them.
	Prefix child lines with job/phase so simultaneous diagnostics stay attributable; keep each worker's order, without claiming a total cross-worker time order.
	Route all parent prints through this renderer, including cleanup warnings.
	Keep the normal screen buffer within the configured worker rows plus one coloured summary row; redraw without a trailing extra newline.
	Show the last launched category's completed/selected fixtures, overall completed/total fixtures, completed/total jobs and launched jobs.
	At exit, clear all worker rows and leave only the final coloured summary line.
	Check native Windows consoles and Cygwin/MSYS terminal pipes; restore changed Windows console mode on exit.
	Handle resize, clamp rows to terminal height, and truncate live rows by display width without splitting UTF-8/ANSI or wrapping at the last column.
	Clip completed diagnostics to their worker row; raw logs retain the complete text.

[x] Provide a bounded plain-output fallback.
	When redirected or VT is unavailable, omit cursor controls and SGR; print completed lines with job prefixes, but no transient progress snapshots.
	Cap in-memory partial-line/control-sequence state; stream oversized ordinary lines in labelled chunks and mark truncated progress.
	Preserve every raw byte in the logs regardless of display limits.
	Do not buffer whole phases.

[x] Integrate draining with lifecycle and cancellation.
	Drain before polling and before reusing a worker slot.
	At phase completion, finish reading available output, emit any unterminated diagnostic once, clear the progress row and reset decoder state before the runtime phase.
	On failure/timeout/cancellation, stop all job trees, drain their final output with a finite deadline, then print status and log paths.
	A direct process exit is not proof its descendants stopped writing.
	Keep existing timeout, memory limits, kill-on-close, exact log-marker checks and summary.tsv intact.

[x] Test decoder/renderer helpers in the existing --self-test.
	Cover split UTF-8/SGR/CRLF, repeated CR + CSI K, appended FAIL, multiline diagnostics, oversized lines, final output without LF, phase/slot reuse, two interleaved workers, resize and non-VT capture.
	Assert bounded state, no raw child cursor escapes, exactly-once committed lines, unchanged logs and no scrollback growth from thousands of progress-only updates.
	Then run two small section jobs concurrently and verify final coverage/retention.

Verified 2026-11-10 on x64 and optimized LLVM: self-tests, two-worker/three-job slot reuse, and runtime checks (8/8, zero retention).
Live-tail first-byte latency was 31ms; existing child output needs no additional progress flushing.
VT behavior is covered by renderer capture/scrollback tests, including 2,000 completed-line/status updates.
A real Cygwin PTY run verifies four worker rows plus one summary row and a final one-line summary; redirected real-job output is checked for escapes.
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
GetFileType :: (handle: HANDLE) -> u32 #foreign runner_kernel32;
TerminateJobObject :: (job: HANDLE, exit_code: u32) -> BOOL #foreign runner_kernel32;

MIB :: 1024 * 1024;
runner_cancel_event: HANDLE;

RUNNER_LINE_LIMIT :: 2048;
RUNNER_TAIL_BUDGET :: 65536;

Runner_Cell :: struct {
	bytes: [4] u8;
	count: s64;
	width: s64;
	style: [64] u8;
	style_count: s64;
}

Runner_Line :: struct {
	cells: [RUNNER_LINE_LIMIT] Runner_Cell;
	count: s64;
	cursor: s64;
	style: [64] u8;
	style_count: s64;
	escape: [128] u8;
	escape_count: s64;
	escape_state: s64;
	utf8: [4] u8;
	utf8_count: s64;
	utf8_expected: s64;
	truncated: bool;
	dirty: bool;
	label: string;
	committed: s64;
	snapshot_count: s64;
}

Runner_Display :: struct {
	vt: bool;
	capture: *[..] u8;
	handle: HANDLE;
	original_mode: u32;
	restore_mode: bool;
	width: s64 = 80;
	height: s64 = 25;
	painted: s64;
	redraw_ms: u64 = 100;
	last_draw: u64;
	last_snapshot: string;
	workers: [5] *Runner_Worker;
	slot_count: s64;
	stopping: bool;
	bounded: bool;
	notice: string;
	summary_enabled: bool;
	summary_final: bool;
	summary_status: string = "RUN";
	category_index: s64 = -1;
	category: string;
	category_completed: s64;
	category_total: s64;
	fixtures_completed: s64;
	fixtures_total: s64;
	jobs_completed: s64;
	jobs_total: s64;
	jobs_launched: s64;
}

runner_display: Runner_Display;

runner_append :: (output: *[..] u8, text: string) {
	for text {
		array_add(output, it);
	}
}

runner_output :: (text: string) {
	plain: [..] u8;
	defer array_free(plain);
	output := text;
	if runner_display.vt {
		previous: u8;
		for text {
			if it == 10 && previous != 13 {
				array_add(*plain, 13);
			}

			array_add(*plain, it);
			previous = it;
		}

		output = .{data = plain.data, count = plain.count};
	} else {
		escape_state: s64;
		for text {
			if escape_state == 1 {
				escape_state = ifx it == #char "[" then 2 else 0;
			} else if escape_state == 2 {
				if it >= 0x40 && it <= 0x7E {
					escape_state = 0;
				}
			} else if it == 27 {
				escape_state = 1;
			} else {
				array_add(*plain, it);
			}
		}

		output = .{data = plain.data, count = plain.count};
	}

	if runner_display.capture {
		runner_append(runner_display.capture, output);
	} else {
		print("%", output);
	}
}

runner_render_clear :: () {
	if runner_display.vt && runner_display.painted {
		up := runner_display.painted - (
			ifx runner_display.bounded
				then 1
				else 0
		);
		text := ifx up
			then sprint("\e[%A\r\e[J", up)
			else copy_string("\r\e[J");
		defer free(text.data);

		runner_output(text);
		runner_display.painted = 0;
	}
}

runner_clip :: (text: string, columns: s64) -> string {
	index: s64;
	width: s64;
	while index < text.count {
		byte := text[index];
		length: s64 = ifx byte < 0x80
			then 1
			else ifx byte < 0xE0
				then 2
				else ifx byte < 0xF0
					then 3
					else 4;
		if index + length > text.count {
			break;
		}

		codepoint: u32 = xx byte;
		if length > 1 {
			codepoint &= (0x7F >> length).(u32);
			for 1..length - 1 {
				codepoint = (codepoint << 6) | (text[index + it] & 0x3F);
			}
		}

		width += runner_codepoint_width(codepoint);
		if width > columns {
			break;
		}

		index += length;
	}

	return .{data = text.data, count = index};
}

runner_summary_launch :: (section_index: s64, name: string, completed: s64, total: s64, launched: s64) {
	if runner_display.category_index != section_index {
		free(runner_display.category.data);
		runner_display.category = copy_string(name);
	}

	runner_display.category_index = section_index;
	runner_display.category_completed = completed;
	runner_display.category_total = total;
	runner_display.jobs_launched = launched;
}

runner_summary_complete :: (section_index: s64, completed: s64, fixtures: s64) {
	if runner_display.category_index == section_index {
		runner_display.category_completed = completed;
	}

	runner_display.fixtures_completed += fixtures;
	runner_display.jobs_completed += 1;
}

runner_summary_text :: (columns: s64) -> string {
	counts := sprint(
		" %/% | total %/% | jobs %/% (% launched)",
		runner_display.category_completed,
		runner_display.category_total,
		runner_display.fixtures_completed,
		runner_display.fixtures_total,
		runner_display.jobs_completed,
		runner_display.jobs_total,
		runner_display.jobs_launched
	);
	defer free(counts.data);

	status := ifx runner_display.summary_final
		then runner_display.summary_status
		else "";
	status_width := ifx status.count
		then status.count + 1
		else 0;
	category := ifx runner_display.category.count
		then runner_display.category
		else "Inventory";
	category = runner_clip(category, max(0, columns - counts.count - status_width));
	colour := ifx status == "PASS"
		then "\e[92m"
		else "\e[91m";

	return sprint(
		"%%%\e[96m%\e[0m \e[93m%\e[0m/\e[33m%\e[0m | total \e[95m%\e[0m/\e[35m%\e[0m | jobs \e[92m%\e[0m/\e[32m%\e[0m (\e[96m%\e[0m launched)",
		ifx status.count
			then colour
			else "",
		status,
		ifx status.count
			then "\e[0m "
			else "",
		category,
		runner_display.category_completed,
		runner_display.category_total,
		runner_display.fixtures_completed,
		runner_display.fixtures_total,
		runner_display.jobs_completed,
		runner_display.jobs_total,
		runner_display.jobs_launched
	);
}

runner_render :: (force := false) {
	if !runner_display.vt || (runner_display.stopping && !force) {
		return;
	}


	if runner_display.handle {
		info: CONSOLE_SCREEN_BUFFER_INFO;
		if GetConsoleScreenBufferInfo(runner_display.handle, *info) {
			runner_display.width = min(info.dwSize.x, info.srWindow.right - info.srWindow.left + 1);
			runner_display.height = info.srWindow.bottom - info.srWindow.top + 1;
		}
	}

	if !force && GetTickCount64() - runner_display.last_draw < runner_display.redraw_ms {
		return;
	}


	snapshot: [..] u8;
	defer array_free(snapshot);
	rows: s64;
	has_summary := runner_display.bounded && runner_display.summary_enabled;
	row_limit := max(0, runner_display.height - (ifx runner_display.bounded then 0 else 1));
	worker_limit := max(0, row_limit - (ifx has_summary then 1 else 0));
	for worker, slot: runner_display.workers {
		if (rows >= worker_limit
			|| has_summary && runner_display.summary_final
			|| runner_display.slot_count && slot >= runner_display.slot_count
		) {
			continue;
		}


		if !worker || !worker.line {
			if runner_display.slot_count {
				if runner_display.bounded && rows {
					runner_append(*snapshot, "\n");
				}

				label := sprint("[worker % idle] %", slot, ifx slot == 0 then runner_display.notice else "");
				defer free(label.data);

				runner_append(*snapshot, runner_clip(label, max(0, runner_display.width - 1)));
				if !runner_display.bounded {
					runner_append(*snapshot, "\n");
				}
				rows += 1;
			}

			continue;
		}


		label := sprint("[%] ", worker.line.label);
		defer free(label.data);

		prefix := runner_clip(label, max(0, runner_display.width - 1));
		if runner_display.bounded && rows {
			runner_append(*snapshot, "\n");
		}

		runner_append(*snapshot, prefix);
		columns := max(0, runner_display.width - 1 - prefix.count);
		text := ifx runner_display.stopping && slot == 0
			then copy_string(runner_clip(runner_display.notice, columns))
			else runner_line_text(worker.line, true, columns, ifx worker.line.count then worker.line.count else worker.line.snapshot_count);
		defer free(text.data);

		runner_append(*snapshot, text);
		runner_append(*snapshot, "\e[0m");
		if !runner_display.bounded {
			runner_append(*snapshot, "\n");
		}
		rows += 1;
	}

	if has_summary && row_limit {
		if rows {
			runner_append(*snapshot, "\n");
		}

		text := runner_summary_text(max(0, runner_display.width - 1));
		defer free(text.data);

		line := New(Runner_Line);
		defer free(line);

		runner_line_feed(line, text);
		clipped := runner_line_text(line, true, max(0, runner_display.width - 1));
		defer free(clipped.data);

		runner_append(*snapshot, clipped);
		rows += 1;
	}

	text := string.{data = snapshot.data, count = snapshot.count};
	if !force && text == runner_display.last_snapshot {
		return;
	}


	runner_render_clear();
	runner_output(text);
	runner_display.painted = rows;
	runner_display.last_draw = GetTickCount64();
	free(runner_display.last_snapshot.data);
	runner_display.last_snapshot = copy_string(text);
}

runner_message :: (format: string, arguments: ..Any) {
	text := sprint(format, ..arguments);
	defer free(text.data);

	if runner_display.bounded && runner_display.vt {
		notice: [..] u8;
		escape_state: s64;
		for text {
			if escape_state == 1 {
				escape_state = ifx it == #char "["
					then 2
					else 0;
			} else if escape_state == 2 {
				if it >= 0x40 && it <= 0x7E {
					escape_state = 0;
				}
			} else if it == 27 {
				escape_state = 1;
			} else if it >= 32 {
				array_add(*notice, it);
			} else if notice.count && notice[notice.count - 1] != 32 {
				array_add(*notice, 32);
			}

			if notice.count >= 4096 {
				break;
			}
		}

		free(runner_display.notice.data);
		runner_display.notice = .{data = notice.data, count = notice.count};
		runner_render(runner_display.stopping);
		return;
	}


	runner_render_clear();
	runner_output(text);
	runner_render(true);
}

runner_failure :: (format: string, arguments: ..Any) {
	runner_display.stopping = true;
	runner_display.summary_status = ifx find_index_from_left(format, "Cancelled") >= 0
		then "CANCELLED"
		else ifx find_index_from_left(format, "TIMEOUT") >= 0
			then "TIMEOUT"
			else "FAIL";
	for worker: runner_display.workers {
		if worker && worker.job {
			TerminateJobObject(worker.job, 1);
		}
	}

	for worker: runner_display.workers {
		if worker {
			runner_tail_finish(worker);
		}
	}

	runner_message(format, ..arguments);
}

runner_pty_name :: (name: string) -> bool {
	return (find_index_from_left(name, "cygwin-") >= 0 || find_index_from_left(name, "msys-") >= 0)
		&& find_index_from_left(name, "-pty") >= 0
		&& (find_index_from_left(name, "-to-master") >= 0 || find_index_from_left(name, "-from-master") >= 0);
}

runner_is_pty :: (handle: HANDLE) -> bool {
	if GetFileType(handle) != 3 {
		return false;
	}


	Name_Info :: struct {
		length: u32;
		name: [1024] u16;
	}

	info: Name_Info;
	if !GetFileInformationByHandleEx(handle, .FileNameInfo, *info, size_of(Name_Info)) || info.length > size_of(type_of(info.name)) || info.length % 2 {
		return false;
	}


	name, valid := wide_to_utf8(info.name.data, (info.length / 2).(s32));
	defer free(name.data);

	return valid && runner_pty_name(name);
}

runner_display_start :: (redraw_ms: u64) {
	runner_display.redraw_ms = redraw_ms;
	runner_display.handle = GetStdHandle(STD_OUTPUT_HANDLE);
	mode: u32;
	if GetConsoleMode(runner_display.handle, *mode) {
		runner_display.original_mode = mode;
		runner_display.vt = !!SetConsoleMode(runner_display.handle, mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING);
		runner_display.restore_mode = runner_display.vt;
	} else {
		runner_display.vt = runner_is_pty(runner_display.handle);
	}
}

runner_display_finish :: () {
	if runner_display.summary_enabled && runner_display.bounded {
		runner_display.summary_final = true;
		if runner_display.summary_status == "RUN" {
			runner_display.summary_status = "STOP";
		}
	}

	if !runner_display.bounded {
		runner_render_clear();
	} else {
		runner_render(true);
		if runner_display.summary_enabled && runner_display.vt {
			runner_output("\n");
		}
	}

	if runner_display.restore_mode {
		SetConsoleMode(runner_display.handle, runner_display.original_mode);
	}

	free(runner_display.last_snapshot.data);
	free(runner_display.notice.data);
	free(runner_display.category.data);
	runner_display = .{};
}

runner_line_text :: (line: *Runner_Line, colours := false, max_width: s64 = 0x7FFF_FFFF, count_override: s64 = -1) -> string {
	output: [..] u8;
	width: s64;
	previous_style: string;
	count := ifx count_override >= 0
		then count_override
		else line.count;
	for *cell: ([] Runner_Cell).{data = line.cells.data, count = count} {
		if width + cell.width > max_width {
			break;
		}


		style := string.{data = cell.style.data, count = cell.style_count};
		if colours && style != previous_style {
			runner_append(*output, "\e[0m");
			runner_append(*output, style);
			previous_style = style;
		}

		runner_append(*output, .{data = cell.bytes.data, count = cell.count});
		width += cell.width;
	}

	if colours {
		runner_append(*output, "\e[0m");
	}

	if line.truncated && width + 3 <= max_width {
		runner_append(*output, "...");
	}

	return .{data = output.data, count = output.count};
}

runner_line_progress :: (line: *Runner_Line) -> bool {
	text := runner_line_text(line);
	defer free(text.data);

	fixture_progress := text.count > 1 && text[0] == #char "[" && text[1] >= #char "0" && text[1] <= #char "9" && find_index_from_left(text, "] ") >= 0 && find_index_from_left(text, "(total ") >= 0;
	return find_index_from_left(text, "FAIL") < 0
		&& (begins_with(text, "Differential ") || begins_with(text, "Checking ") || fixture_progress);
}

runner_line_commit :: (line: *Runner_Line, partial := false) {
	if runner_display.bounded && runner_display.vt {
		line.snapshot_count = line.count;
		line.count = 0;
		line.cursor = 0;
		line.truncated = false;
		line.dirty = true;
		line.committed += 1;
		return;
	}


	text := runner_line_text(line, runner_display.vt);
	defer free(text.data);

	if line.label {
		runner_message(
			"[%] %%\n",
			line.label,
			text,
			ifx partial
				then " [continued]"
				else ""
		);
	} else {
		runner_message("%\n", text);
	}

	line.count = 0;
	line.cursor = 0;
	line.truncated = false;
	line.dirty = true;
	line.committed += 1;
}

runner_codepoint_width :: (codepoint: u32) -> s64 {
	if (codepoint >= 0x300 && codepoint <= 0x36F
		|| codepoint >= 0xFE00 && codepoint <= 0xFE0F
		|| codepoint == 0x200D
	 ) {
		return 0;
	}


	return (ifx codepoint >= 0x1100
		&& (
			codepoint <= 0x115F || codepoint == 0x2329 || codepoint == 0x232A
			|| codepoint >= 0x2E80 && codepoint <= 0xA4CF
			|| codepoint >= 0xAC00 && codepoint <= 0xD7A3
			|| codepoint >= 0xF900 && codepoint <= 0xFAFF
			|| codepoint >= 0xFE10 && codepoint <= 0xFE6F
			|| codepoint >= 0xFF00 && codepoint <= 0xFF60
			|| codepoint >= 0x1F300 && codepoint <= 0x1FAFF
			|| codepoint >= 0x20000
		)
			then 2
			else 1
	);
}

runner_line_character :: (line: *Runner_Line, bytes: string, codepoint: u32) {
	if line.cursor >= RUNNER_LINE_LIMIT {
		if runner_line_progress(line) {
			line.truncated = true;
			line.dirty = true;
			return;
		}


		runner_line_commit(line, true);
	}

	cell := *line.cells[line.cursor];
	cell.count = bytes.count;
	for bytes {
		cell.bytes[it_index] = it;
	}

	cell.width = runner_codepoint_width(codepoint);
	cell.style_count = line.style_count;
	for 0..line.style_count - 1 {
		cell.style[it] = line.style[it];
	}

	line.cursor += 1;
	line.count = max(line.count, line.cursor);
	line.dirty = true;
}

runner_line_escape :: (line: *Runner_Line, final: u8) {
	sequence := string.{data = line.escape.data, count = line.escape_count};
	if final == #char "m" {
		for 2..sequence.count - 2 {
			if sequence[it] < 0x30 || sequence[it] > 0x3F {
				return;
			}
		}


		if sequence == "\e[m" || sequence == "\e[0m" {
			line.style_count = 0;
		} else if sequence.count <= line.style.count {
			if line.style_count + sequence.count > line.style.count {
				line.style_count = 0;
			}

			for sequence {
				line.style[line.style_count] = it;
				line.style_count += 1;
			}
		}
	} else if final == #char "K" {
		if sequence == "\e[K" || sequence == "\e[0K" {
			line.count = min(line.count, line.cursor);
		} else if sequence == "\e[2K" {
			line.count = line.cursor;
			for 0..line.count - 1 {
				line.cells[it] = .{bytes = .[32, 0, 0, 0], count = 1, width = 1};
			}
		} else if sequence == "\e[1K" {
			for 0..min(line.cursor, line.count - 1) {
				line.cells[it] = .{bytes = .[32, 0, 0, 0], count = 1, width = 1};
			}
		}

		line.dirty = true;
	}
}

runner_line_feed :: (line: *Runner_Line, bytes: string) {
	for byte: bytes {
		if line.escape_state {
			if line.escape_count < line.escape.count {
				line.escape[line.escape_count] = byte;
				line.escape_count += 1;
			}

			if line.escape_state == {
				case 1;
					line.escape_state = ifx byte == #char "["
						then 2
						else ifx byte == #char "]" || byte == #char "P" || byte == #char "X" || byte == #char "^" || byte == #char "_"
							then 3
							else 0;

				case 2;
					if byte >= 0x40 && byte <= 0x7E {
						if line.escape_count < line.escape.count {
							runner_line_escape(line, byte);
						}

						line.escape_state = 0;
					}

				case 3;
					if byte == 7 {
						line.escape_state = 0;
					} else if byte == 27 {
						line.escape_state = 4;
					}

				case 4;
					line.escape_state = ifx byte == #char "\\"
						then 0
						else 3;
			}

			continue;
		}


		if line.utf8_count {
			if (byte & 0xC0) == 0x80 {
				line.utf8[line.utf8_count] = byte;
				line.utf8_count += 1;
				if line.utf8_count == line.utf8_expected {
					codepoint := line.utf8[0].(u32) & (0x7F >> line.utf8_expected).(u32);
					for 1..line.utf8_count - 1 {
						codepoint = (codepoint << 6) | (line.utf8[it] & 0x3F);
					}

					minimum: u32 = xx (
						ifx line.utf8_expected == 2
							then 0x80
							else ifx line.utf8_expected == 3
								then 0x800
								else 0x10000
					);
					if codepoint < minimum || codepoint > 0x10FFFF || codepoint >= 0xD800 && codepoint <= 0xDFFF {
						runner_line_character(line, "?", 63);
					} else {
						runner_line_character(line, .{data = line.utf8.data, count = line.utf8_count}, codepoint);
					}

					line.utf8_count = 0;
				}

				continue;
			}


			line.utf8_count = 0;
			runner_line_character(line, "?", 63);
		}

		if byte == {
			case 27;
				line.escape_state = 1;
				line.escape_count = 1;
				line.escape[0] = 27;

			case 13;
				line.cursor = 0;
				line.truncated = false;

			case 10;
				runner_line_commit(line);

			case 8;
				line.cursor = max(0, line.cursor - 1);

			case 9;
				width: s64;
				for 0..line.cursor - 1 {
					width += line.cells[it].width;
				}

				for 1..8 - width % 8 {
					runner_line_character(line, " ", 32);
				}

			case;
				if byte >= 0xC2 && byte <= 0xF4 {
					line.utf8[0] = byte;
					line.utf8_count = 1;
					line.utf8_expected = ifx byte < 0xE0
						then 2
						else ifx byte < 0xF0
							then 3
							else 4;
				} else if byte >= 32 && byte < 127 {
					runner_line_character(line, .{data = *byte, count = 1}, xx byte);
				}
		}
	}
}

runner_line_finish :: (line: *Runner_Line) {
	if line.utf8_count {
		runner_line_character(line, "?", 63);
		line.utf8_count = 0;
	}

	if line.count && !runner_line_progress(line) {
		runner_line_commit(line);
	}

	line.escape_count = 0;
	line.escape_state = 0;
}

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
	selected_total: s64;
	completed: s64;
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
	workers: s64 = 4;
	batch_size: s64 = 16;
	memory_mib: s64 = 2048;
	reserve_mib: s64 = 2048;
	timeout_seconds: s64 = 30;
	redraw_ms: s64 = 100;
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
	REDRAW_MS;
	UNKNOWN;
}

Runner_Self_Test_Mode :: enum {
	OK;
	FAIL;
	NATIVE_FAIL;
	MEMORY;
	WAIT;
	TREE;
	STREAM;
	CANCEL;
	UNKNOWN;
}

RUNNER_SELF_TEST_NAMES :: string.["ok", "fail", "native-fail", "memory", "wait", "tree", "stream", "cancel"];

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
	reader: HANDLE;
	read_offset: u64;
	first_output_ms: u64;
	line: *Runner_Line;
	tail_failed: bool;
	marker: string;
	marker_found: bool;
	retention_found: bool;
	marker_tail: [512] u8;
	marker_tail_count: s64;
	inventory_capture: bool;
	inventory_output: [..] u8;
}

runner_scan_output :: (worker: *Runner_Worker, text: string) {
	buffer: [4608] u8;
	for 0..worker.marker_tail_count - 1 {
		buffer[it] = worker.marker_tail[it];
	}

	for text {
		buffer[worker.marker_tail_count + it_index] = it;
	}

	window := string.{data = buffer.data, count = worker.marker_tail_count + text.count};
	if worker.marker {
		worker.marker_found |= find_index_from_left(window, worker.marker) >= 0;
	}

	worker.retention_found |= find_index_from_left(window, "Differential runtime retained: 0 allocations, 0 bytes") >= 0;
	worker.marker_tail_count = min(window.count, worker.marker_tail.count);
	for 0..worker.marker_tail_count - 1 {
		worker.marker_tail[it] = window[window.count - worker.marker_tail_count + it];
	}

	if worker.inventory_capture {
		if worker.inventory_output.count + text.count > 65536 {
			worker.tail_failed = true;
		} else {
			runner_append(*worker.inventory_output, text);
		}
	}
}

runner_tail :: (worker: *Runner_Worker) -> s64 {
	if !worker.reader || !worker.line || worker.tail_failed {
		return 0;
	}


	buffer: [4096] u8;
	total: s64;
	while total < RUNNER_TAIL_BUDGET {
		count: u32;
		if !ReadFile(worker.reader, buffer.data, buffer.count, *count) {
			worker.tail_failed = true;
			return total;
		}


		if !count {
			break;
		}


		text := string.{data = buffer.data, count = count};
		if !worker.read_offset {
			worker.first_output_ms = GetTickCount64() - worker.started;
		}

		runner_scan_output(worker, text);
		runner_line_feed(worker.line, text);
		total += count;
		worker.read_offset += count;
	}


	return total;
}

runner_tail_finish :: (worker: *Runner_Worker) {
	deadline := GetTickCount64() + 2000;
	while worker.job && GetTickCount64() < deadline {
		accounting: Runner_Accounting;
		if !QueryInformationJobObject(worker.job, .BasicAccountingInformation, *accounting, size_of(type_of(accounting)), null) || !accounting.active_processes {
			break;
		}


		runner_tail(worker);
		WaitForSingleObject(worker.info.hProcess, 10);
	}

	now := GetTickCount64();
	if worker.info.hProcess && now < deadline {
		WaitForSingleObject(worker.info.hProcess, (deadline - now).(u32));
	}

	deadline = GetTickCount64() + 1000;
	while runner_tail(worker) == RUNNER_TAIL_BUDGET && GetTickCount64() < deadline {}

	if worker.line {
		runner_line_finish(worker.line);
		worker.line.count = 0;
		worker.line.cursor = 0;
	}
}

runner_worker_label :: (worker: *Runner_Worker, label: string) {
	if worker.line {
		free(worker.line.label.data);
		worker.line.label = copy_string(label);
	}
}

runner_worker_slot :: (worker: *Runner_Worker, slot: s64) {
	for *runner_display.workers {
		if it.* == worker {
			it.* = null;
		}
	}

	runner_display.workers[slot] = worker;
}

close_worker :: (worker: *Runner_Worker) {
	if worker.job {
		TerminateJobObject(worker.job, 1);
	}

	runner_tail_finish(worker);
	if !runner_display.bounded {
		runner_render_clear();
	}

	for *runner_display.workers {
		if it.* == worker {
			it.* = null;
		}
	}

	if worker.reader {
		CloseHandle(worker.reader);
	}

	if worker.line {
		free(worker.line.label.data);
		free(worker.line);
	}

	free(worker.marker.data);
	array_free(worker.inventory_output);

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
	if runner_display.bounded {
		runner_render(runner_display.stopping);
	}
}

get_runner_environment :: (name: *u16) -> bool, *u16 {
	required := GetEnvironmentVariableW(name, null, 0);
	if !required {
		return true, null;
	}


	previous := temporary_alloc(required * size_of(u16)).(*u16);
	previous[0] = 0;
	count := GetEnvironmentVariableW(name, previous, required);
	return count < required && (count || required == 1), previous;
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


		worker.reader = CreateFileW(utf8_to_wide(log_path,, temp), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, null, OPEN_EXISTING);
		if worker.reader == INVALID_HANDLE_VALUE {
			worker.reader = null;
			close_worker(worker);
			return false;
		}


		worker.line = New(Runner_Line);
		runner_worker_label(worker, "inventory/compile");
		for *runner_display.workers {
			if !it.* {
				it.* = worker;
				break;
			}
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
		temp_valid, previous_temp = get_runner_environment(temp_name);
		tmp_valid, previous_tmp = get_runner_environment(tmp_name);
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
		restored = restored_temp && restored_tmp;
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


	worker.started = GetTickCount64();
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
	runner_message("\e[96mUsage\e[0m: differential_runner.exe \e[93mSECTION\e[0m | \e[96m--all\e[0m | \e[96m--list\e[0m | \e[96m--self-test\e[0m\n");
	runner_message("  \e[96m--workers\e[0m \e[93m1..4\e[0m       (default \e[93m4\e[0m)\n");
	runner_message("  \e[96m--batch-size\e[0m \e[93m1..16\e[0m   (default \e[93m16\e[0m; batchable sections only)\n");
	runner_message("  \e[96m--first\e[0m \e[93mN\e[0m \e[96m--last\e[0m \e[93mN\e[0m   (one batchable section, inclusive)\n");
	runner_message("  \e[96m--memory-mib\e[0m \e[93mN\e[0m       (default \e[93m2048\e[0m per process tree; safety limit)\n");
	runner_message("  \e[96m--reserve-mib\e[0m \e[93mN\e[0m      (default \e[93m2048\e[0m physical/commit headroom)\n");
	runner_message("  \e[96m--timeout\e[0m \e[93mN\e[0m          (default \e[93m30\e[0m seconds per phase/admission wait)\n");
	runner_message("  \e[96m--redraw-ms\e[0m \e[93mN\e[0m        (default \e[93m100\e[0m; minimum \e[93m0\e[0m)\n");
}

runner_integer :: (text: string) -> bool, s64 {
	value, valid, remainder := string_to_int(text, T = s64);
	return valid && !remainder, value;
}

parse_runner_options :: (arguments: [] string) -> bool, Runner_Options {
	options: Runner_Options;
	option_names :: string.["--all", "--list", "--self-test", "--workers", "--batch-size", "--memory-mib", "--reserve-mib", "--timeout", "--first", "--last", "--redraw-ms"];
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
						return false, options;
					}


					valid, value := runner_integer(arguments[index]);
					index += 1;
					if !valid {
						return false, options;
					}


					if option == {
						case .WORKERS;		options.workers = value;
						case .BATCH_SIZE;	options.batch_size = value;
						case .MEMORY_MIB;	options.memory_mib = value;
						case .RESERVE_MIB;	options.reserve_mib = value;
						case .TIMEOUT;		options.timeout_seconds = value;
						case .FIRST;		options.first = value;
						case .LAST;			options.last = value;
						case .REDRAW_MS;	options.redraw_ms = value;
						case;				return false, options;
					}
				} else if !options.selection {
					options.selection = argument;
				} else {
					return false, options;
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
		&& options.redraw_ms >= 0
		&& options.first >= 0 && options.last >= 0
		&& (
			!options.first && !options.last
			|| options.first >= 1 && options.last >= options.first && options.selection.count
		);

	return valid, options;
}

runner_memory_status :: (statistics: *Runner_Statistics) -> bool, MEMORYSTATUSEX {
	status: MEMORYSTATUSEX;
	status.dwLength = size_of(type_of(status));
	if !GlobalMemoryStatusEx(*status) {
		return false, status;
	}


	statistics.min_available_physical = min(statistics.min_available_physical, status.ullAvailPhys);
	statistics.min_commit_headroom = min(statistics.min_commit_headroom, status.ullAvailPageFile);
	statistics.max_system_commit = max(statistics.max_system_commit, status.ullTotalPageFile - status.ullAvailPageFile);
	return true, status;
}

runner_wait :: (worker: *Runner_Worker, timeout_ms: u64) -> s32 {
	deadline := GetTickCount64() + timeout_ms;
	handles: [2] HANDLE = .[worker.info.hProcess, runner_cancel_event];
	while true {
		runner_tail(worker);
		runner_render();
		if worker.tail_failed {
			return 1;
		}


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


		index_valid, index := runner_integer(fields[0]);
		total_valid, total := runner_integer(fields[2]);
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
	started := start_worker(worker, arguments, memory_bytes, directory, tprint("%/compile.log", directory));
	worker.inventory_capture = selector == "list-machine";
	return started;
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
	runner_message(
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
				runner_message("\e[93mWARNING\e[0m unable to remove \e[96m%\e[0m\n", info.full_name);
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
		runner_message("\e[93mWARNING\e[0m unable to remove \e[96m%\e[0m\n", build);
	}

	temporary_directory := tprint("%/tmp", directory);
	if file_exists(temporary_directory) && !RemoveDirectoryW(utf8_to_wide(temporary_directory,, temp)) && !delete_directory(temporary_directory) {
		runner_message("\e[93mWARNING\e[0m unable to remove \e[96m%\e[0m\n", temporary_directory);
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

runner_decoder_self_tests :: () {
	capture: [..] u8;
	defer array_free(capture);

	previous := runner_display;
	runner_display = .{capture = *capture};
	defer runner_display = previous;

	line := New(Runner_Line);
	defer free(line);

	line.label = "job 1/compile";
	runner_line_feed(line, "\e[3");
	runner_line_feed(line, "1m\xE7\x95");
	assert(line.utf8_count == 2 && !line.count);
	runner_line_feed(line, "\x8C\e[0m\r");
	assert(line.count == 1 && line.cells[0].width == 2);
	runner_line_feed(line, "\n");
	assert(capture.count && line.committed == 1);
	assert(string.{data = capture.data, count = capture.count} == "[job 1/compile] \xE7\x95\x8C\n");
	capture.count = 0;
	for 0..2999 {
		runner_line_feed(line, "\r\e[KChecking fixture 1/2");
	}

	assert(!capture.count && line.committed == 1);
	runner_line_feed(line, " FAIL\ncompiler diagnostic\nfixture path");
	runner_line_finish(line);
	assert(line.committed == 4);
	assert(find_index_from_left(string.{data = capture.data, count = capture.count}, "Checking fixture 1/2 FAIL\n") >= 0);
	capture.count = 0;
	runner_line_feed(line, "abc\x08X\tY\e[12A\e]title\x07\n");
	assert(string.{data = capture.data, count = capture.count} == "[job 1/compile] abX     Y\n");
	capture.count = 0;
	for 0..RUNNER_LINE_LIMIT + 10 {
		runner_line_feed(line, "x");
	}

	assert(line.count <= RUNNER_LINE_LIMIT && line.committed == 6);
	runner_line_finish(line);
	assert(line.committed == 7);
	line.* = .{};
	capture.count = 0;
	runner_line_feed(line, "Checking ");
	for 0..RUNNER_LINE_LIMIT * 2 {
		runner_line_feed(line, "x");
	}

	assert(line.truncated && line.count == RUNNER_LINE_LIMIT && !capture.count);
	runner_line_finish(line);
	assert(!capture.count);
	line.* = .{};
	runner_display.vt = true;
	runner_line_feed(line, "\e[31mred\e[0m\e[4A\n");
	assert(find_index_from_left(string.{data = capture.data, count = capture.count}, "\e[31m") >= 0);
	assert(find_index_from_left(string.{data = capture.data, count = capture.count}, "\e[4A") < 0);
	line.* = .{};
	capture.count = 0;
	runner_line_feed(line, "\e[");
	for 0..511 {
		runner_line_feed(line, "0");
	}

	assert(line.escape_count == line.escape.count);
	runner_line_feed(line, "m\ePdiscard\e\\ok\n");
	assert(string.{data = capture.data, count = capture.count} == "ok\e[0m\r\n");
	line.* = .{};
	capture.count = 0;
	runner_line_feed(line, "\xE0\x80\x80\n");
	assert(string.{data = capture.data, count = capture.count} == "?\e[0m\r\n");
}

runner_test_scrollback :: (text: string, height: s64) -> s64 {
	row: s64;
	scrolls: s64;
	index: s64;
	while index < text.count {
		byte := text[index];
		index += 1;
		if byte == 27 && index < text.count && text[index] == #char "[" {
			index += 1;
			amount: s64;
			while index < text.count {
				command := text[index];
				index += 1;
				if command >= #char "0" && command <= #char "9" {
					amount = amount * 10 + command - #char "0";
				} else if command >= 0x40 && command <= 0x7E {
					if command == #char "A" {
						row = max(0, row - max(1, amount));
					}

					break;
				}
			}
		} else if byte == 10 {
			if row == height - 1 {
				scrolls += 1;
			} else {
				row += 1;
			}
		}
	}

	return scrolls;
}

runner_renderer_self_tests :: () {
	capture: [..] u8;
	defer array_free(capture);

	previous := runner_display;
	runner_display = .{vt = true, capture = *capture, redraw_ms = 0, width = 32, height = 4, slot_count = 2};
	defer {
		free(runner_display.last_snapshot.data);
		runner_display = previous;
	}

	first := New(Runner_Line);
	second := New(Runner_Line);
	defer free(first);
	defer free(second);

	first.label = "job 1 compile";
	second.label = "job 2 runtime";
	workers: [2] Runner_Worker;
	workers[0].line = first;
	workers[1].line = second;
	runner_display.workers[0] = *workers[0];
	runner_display.workers[1] = *workers[1];
	runner_line_feed(first, "[1/2] A 1/2 (total 1/2): ");
	runner_line_feed(second, "[2/2] B 1/2 (total 1/2): ");
	runner_render();
	assert(runner_display.painted == 2);
	initial_count := capture.count;
	for 0..1999 {
		runner_line_feed(first, "\r\e[K[1/2] A 1/2 (total 1/2): ");
		runner_render();
	}

	assert(capture.count == initial_count && !first.committed && !second.committed);
	for 0..1999 {
		runner_line_feed(first, tprint("\r\e[KChecking %", it));
		runner_render();
	}

	assert(!first.committed && !second.committed);
	assert(runner_test_scrollback(.{data = capture.data, count = capture.count}, 4) == 0);
	initial_count = capture.count;
	runner_display.redraw_ms = 100000;
	runner_line_feed(first, "changed");
	runner_render();
	assert(capture.count == initial_count);
	runner_display.width = 18;
	runner_display.height = 2;
	runner_render(true);
	assert(runner_display.painted == 1);
	assert(runner_clip("\xE7\x95\x8C!", 1).count == 0);
	assert(runner_clip("\xE7\x95\x8C!", 2).count == 3);
	runner_line_feed(second, " FAIL\n");
	assert(second.committed == 1);
	runner_render_clear();
	runner_display.vt = false;
	capture.count = 0;
	runner_line_feed(first, "\r\e[Kdiagnostic\e[4A\n");
	runner_message("\e[31mparent\e[0m\n");
	assert(string.{data = capture.data, count = capture.count} == "[job 1 compile] diagnostic\nparent\n");
	second.* = .{label = "job 3 compile"};
	runner_line_feed(second, "fresh");
	runner_line_finish(second);
	runner_line_finish(second);
	assert(second.committed == 1);
	worker: Runner_Worker;
	worker.marker = "compile-time checks (1/1 total tests)";
	runner_scan_output(*worker, "compile-time checks (1/");
	assert(!worker.marker_found);
	runner_scan_output(*worker, "1 total tests) Differential runtime retained: 0 allocations, 0 bytes");
	assert(worker.marker_found && worker.retention_found);
}

runner_stop_output_self_tests :: (root: string, executable: string) {
	capture: [..] u8;
	defer array_free(capture);

	previous := runner_display;
	runner_display = .{capture = *capture};
	defer runner_display = previous;

	workers: [2] Runner_Worker;
	defer {
		for *workers {
			close_worker(it);
		}
	}

	for *worker: workers {
		arguments: [] string = .[executable, "--self-child", "wait"];
		assert(start_worker(worker, arguments, 1024 * MIB, root, tprint("%/stop-%.log", root, it_index)));
		runner_worker_label(worker, tprint("job %/compile", it_index + 1));
	}

	deadline := GetTickCount64() + 2000;
	while GetTickCount64() < deadline {
		for *workers {
			runner_tail(it);
		}

		if workers[0].read_offset && workers[1].read_offset {
			break;
		}


		WaitForSingleObject(workers[0].info.hProcess, 10);
	}

	assert(workers[0].read_offset && workers[1].read_offset && !capture.count);
	runner_failure("FAIL stop-test\n");
	assert(string.{data = capture.data, count = capture.count} == "[job 1/compile] unterminated diagnostic\n[job 2/compile] unterminated diagnostic\nFAIL stop-test\n");
	for *worker: workers {
		assert(WaitForSingleObject(worker.info.hProcess, 0) == WAIT_OBJECT_0);
		assert(worker.line.committed == 1);
		runner_tail_finish(worker);
		assert(worker.line.committed == 1);
		close_worker(worker);
		output, valid := read_entire_file(tprint("%/stop-%.log", root, it_index));
		defer free(output.data);

		assert(valid && output == "unterminated diagnostic");
	}
}

runner_bounded_output_self_tests :: () {
	assert(runner_pty_name("\\cygwin-123-pty0-to-master"));
	assert(runner_pty_name("\\msys-123-pty2-from-master"));
	assert(!runner_pty_name("\\ordinary-pipe"));
	assert(!runner_pty_name("D:/logs/cygwin-output.log"));
	capture: [..] u8;
	defer array_free(capture);

	previous := runner_display;
	runner_display = .{vt = true, bounded = true, capture = *capture, redraw_ms = 0, width = 80, height = 3, slot_count = 2};
	defer {
		free(runner_display.last_snapshot.data);
		free(runner_display.notice.data);
		runner_display = previous;
	}

	workers: [2] Runner_Worker;
	for *worker: workers {
		worker.line = New(Runner_Line);
		worker.line.label = "job/compile";
		runner_display.workers[it_index] = worker;
	}

	defer {
		for workers {
			free(it.line);
		}
	}

	for 0..1999 {
		worker := *workers[it % 2];
		runner_line_feed(worker.line, tprint("completed diagnostic %\n", it));
		runner_message("START/PASS job %\n", it);
		assert(runner_display.painted == 2);
	}

	assert(workers[0].line.committed == 1000 && workers[1].line.committed == 1000);
	assert(runner_test_scrollback(.{data = capture.data, count = capture.count}, 3) == 0);
	runner_failure("Cancelled; logs retained\n");
	assert(runner_display.painted == 2);
	assert(runner_test_scrollback(.{data = capture.data, count = capture.count}, 3) == 0);
}

runner_summary_self_tests :: () {
	capture: [..] u8;
	defer array_free(capture);

	previous := runner_display;
	runner_display = .{
		vt = true,
		bounded = true,
		capture = *capture,
		redraw_ms = 0,
		width = 100,
		height = 5,
		slot_count = 4,
		summary_enabled = true,
		category = copy_string("Typed integer conversions"),
		category_completed = 2,
		category_total = 3,
		fixtures_completed = 7,
		fixtures_total = 8,
		jobs_completed = 3,
		jobs_total = 4,
		jobs_launched = 4
	};
	defer runner_display = previous;

	runner_render();
	assert(runner_display.painted == 5);
	assert(runner_test_scrollback(.{data = capture.data, count = capture.count}, 5) == 0);
	runner_summary_launch(2, "Typed integer conversions", 2, 3, 4);
	runner_summary_complete(1, 5, 1);
	assert(runner_display.category_index == 2 && runner_display.category_completed == 2);
	assert(runner_display.fixtures_completed == 8 && runner_display.jobs_completed == 4);
	runner_display.category_completed = 3;
	runner_display.summary_status = "PASS";
	runner_display.summary_final = true;
	runner_render(true);
	assert(runner_display.painted == 1);
	text := runner_summary_text(99);
	defer free(text.data);

	line := New(Runner_Line);
	defer free(line);

	runner_line_feed(line, text);
	plain := runner_line_text(line);
	defer free(plain.data);

	assert(plain == "PASS Typed integer conversions 3/3 | total 8/8 | jobs 4/4 (4 launched)");
	assert(find_index_from_left(text, "\e[92mPASS") >= 0);
	assert(find_index_from_left(text, "\e[96mTyped integer conversions") >= 0);
	assert(find_index_from_left(text, "\e[93m3/3") >= 0);
	runner_display_finish();
}

run_runner_self_tests :: (root: string) -> s32 {
	runner_summary_self_tests();
	runner_bounded_output_self_tests();
	runner_decoder_self_tests();
	runner_renderer_self_tests();
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
	runner_stop_output_self_tests(root, executable);

	worker: Runner_Worker;
	defer close_worker(*worker);

	for mode, mode_index: RUNNER_SELF_TEST_NAMES {
		arguments: [] string = .[executable, "--self-child", mode, root];
		budget: u64 = xx (
			ifx mode == "memory"
				then 64 * MIB
				else 1024 * MIB
		);
		if !start_worker(*worker, arguments, budget, root, tprint("%/%.log", root, mode)) {
			return 1;
		}


		if mode == "cancel" {
			runner_control_handler(0);
		}

		if mode == "stream" {
			deadline := GetTickCount64() + 1000;
			while !worker.read_offset && GetTickCount64() < deadline {
				runner_tail(*worker);
				if worker.read_offset || WaitForSingleObject(worker.info.hProcess, 10) != WAIT_TIMEOUT {
					break;
				}
			}

			assert(worker.read_offset && runner_line_progress(worker.line));
			assert(WaitForSingleObject(worker.info.hProcess, 0) == WAIT_TIMEOUT);
			runner_message("PASS live tail visible before child exit; first_byte_ms=%\n", worker.first_output_ms);
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
			runner_failure("\e[91mFAIL\e[0m self-test \e[96m%\e[0m: expected \e[93m%\e[0m, got \e[91m%\e[0m\n", mode, expected, code);
			return 1;
		}


		descendant: HANDLE;
		defer if descendant {
			CloseHandle(descendant);
		}

		if mode == "tree" {
			pid_text, read_valid := read_entire_file(tprint("%/descendant.pid", root));
			defer free(pid_text.data);

			pid_valid, pid := runner_integer(trim(pid_text));
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
				runner_failure("\e[91mFAIL\e[0m kill-on-close cleanup\n");
				return 1;
			}
		} else {
			close_worker(*worker);
		}


		if mode == "ok" || mode == "memory" || mode == "stream" {
			output, read_valid := read_entire_file(tprint("%/%.log", root, mode));
			defer free(output.data);

			expected_output := ifx mode == "stream"
				then "\r\e[K[1/2] live 1/2 (total 1/2): \r\e[Kstream-ok\n"
				else ifx mode == "ok"
					then "child-ok"
					else "memory-denied";
			matches := ifx mode == "stream" then output == expected_output else trim(output) == expected_output;
			if !read_valid || !matches {
				return 1;
			}
		}
	}


	SetEvent(runner_cancel_event);
	if !runner_cancelled() {
		return 1;
	}


	runner_message("\e[92mPASS\e[0m decoder, renderer, native launch, logging, nonzero exit, memory cap, timeout, descendant cleanup and cancellation\n");
	return 0;
}

run_runner :: (arguments: [] string) -> s32 {
	runner_display_start(100);
	defer runner_display_finish();

	if arguments.count == 1 || (arguments.count == 2 && arguments[1] == "--help") {
		runner_usage();
		return xx (
			ifx arguments.count == 1
				then 64
				else 0
		);
	}


	valid, options := parse_runner_options(arguments);
	if !valid {
		runner_usage();
		return 64;
	}


	runner_display.redraw_ms = xx options.redraw_ms;
	runner_display.bounded = !options.self_test && !options.list;
	runner_display.summary_enabled = runner_display.bounded;
	if runner_display.bounded {
		runner_display.slot_count = options.workers;
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
		runner_failure("\e[91mUnable to create\e[0m fresh run directory: \e[96m%\e[0m\n", root);
		return 1;
	}


	runner_message("Logs: \e[96m%\e[0m\n", root);
	if options.self_test {
		return run_runner_self_tests(root);
	}


	statistics: Runner_Statistics;
	memory_valid, status := runner_memory_status(*statistics);
	if !memory_valid {
		return 1;
	}


	statistics.initial_system_commit = status.ullTotalPageFile - status.ullAvailPageFile;
	memory_bytes: u64 = xx (options.memory_mib * MIB);
	reserve_bytes: u64 = xx (options.reserve_mib * MIB);
	if status.ullAvailPhys < memory_bytes + reserve_bytes || status.ullAvailPageFile < memory_bytes + reserve_bytes {
		runner_failure("\e[93mInsufficient physical/commit headroom\e[0m for one worker and the reserve.\n");
		return 75;
	}


	compiler := tprint("%../../../bin/jai.exe", #filepath);
	if !file_exists(compiler) {
		runner_failure("\e[91mCompiler not found\e[0m: \e[96m%\e[0m\n", compiler);
		return 1;
	}


	compiler = copy_string(compiler);
	defer free(compiler.data);

	started := GetTickCount64();
	inventory_directory := tprint("%/inventory", root);
	inventory: Runner_Worker;
	defer close_worker(*inventory);

	if !start_compiler_job(*inventory, compiler, inventory_directory, "list-machine", 0, 0, memory_bytes) {
		runner_failure("\e[91mUnable to launch\e[0m inventory compiler.\n");
		return 1;
	}


	inventory.started = GetTickCount64();
	code := runner_wait(*inventory, xx (options.timeout_seconds * 1000));
	if code || !record_runner_worker(*inventory, *statistics) {
		runner_failure("Inventory \e[91mfailed\e[0m (exit \e[91m%\e[0m). See \e[96m%/compile.log\e[0m\n", code, inventory_directory);
		return xx (
			ifx code
				then code
				else 1
		);
	}


	TerminateJobObject(inventory.job, 1);
	runner_tail_finish(*inventory);
	if inventory.tail_failed {
		return 1;
	}

	output := string.{data = inventory.inventory_output.data, count = inventory.inventory_output.count};
	empty_inventory: [..] u8;
	inventory.inventory_output = empty_inventory;
	close_worker(*inventory);

	defer free(output.data);

	sections: [..] Runner_Section;
	defer {
		for sections {
			free(it.name.data);
		}

		array_free(sections);
	}

	if !collect_runner_sections(output, *sections) {
		runner_failure("\e[91mInvalid differential inventory\e[0m. See \e[96m%/compile.log\e[0m\n", inventory_directory);
		return 1;
	}


	clean_runner_job(inventory_directory);
	if options.list {
		for section, index: sections {
			runner_message("\e[93m%\e[0m\t\e[96m%\e[0m\t\e[93m%\e[0m fixtures\tbatchable=\e[93m%\e[0m\truntime=\e[93m%\e[0m\n", index + 1, section.name, section.total, section.batchable, section.runtime);
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
	selection_is_index, selection_index := runner_integer(options.selection);
	for section, index: sections {
		if !options.all && options.selection != section.name && (!selection_is_index || selection_index != index + 1) {
			continue;
		}


		selected_sections += 1;
		if options.last && (!section.batchable || options.last > section.total) {
			runner_message("Fixture range is \e[91minvalid\e[0m for section \e[96m%\e[0m.\n", section.name);
			return 64;
		}


		first := ifx options.first
			then options.first
			else 1;
		last := ifx options.last
			then options.last
			else section.total;
		expected_total += last - first + 1;
		sections[index].selected_total = last - first + 1;
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
		runner_message("\e[91mUnknown section\e[0m: \e[96m%\e[0m\n", options.selection);
		return 64;
	}


	runner_display.slot_count = options.workers;
	runner_display.fixtures_total = expected_total;
	runner_display.jobs_total = jobs.count;
	workers: [4] Runner_Worker;
	defer {
		for *workers {
			close_worker(it);
		}
	}

	runner_message(
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
		for *workers {
			runner_tail(it);
			if it.tail_failed {
				runner_failure("FAIL reading worker output. Logs: %\n", root);
				return 1;
			}
		}


		runner_render();
		if runner_cancelled() {
			runner_failure("\e[93mCancelled\e[0m; stopped all worker trees. Logs: \e[96m%\e[0m\n", root);
			return 130;
		}


		memory_valid, status = runner_memory_status(*statistics);
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


					if exit_code {
						runner_failure(
							"\e[91mFAIL\e[0m job \e[93m%\e[0m [\e[96m%\e[0m \e[93m%\e[0m..\e[93m%\e[0m] exit=\e[91m%\e[0m. Logs: \e[96m%\e[0m\n",
							worker.job_index + 1,
							section.name,
							job.first,
							job.last,
							exit_code,
							job.directory
						);
						return 1;
					}


					job_index := worker.job_index;
					runtime_phase := worker.runtime_phase;
					TerminateJobObject(worker.job, 1);
					runner_tail_finish(worker);
					phase_log := tprint("%/%.log", job.directory, ifx runtime_phase then "runtime" else "compile");
					if worker.tail_failed || !worker.marker_found || (runtime_phase && !worker.retention_found) {
						runner_failure("\e[91mFAIL\e[0m missing exact fixture/retention result in \e[96m%\e[0m\n", phase_log);
						return 1;
					}


					close_worker(worker);

					if section.runtime && !runtime_phase {
						runtime_arguments: [] string = .[tprint("%/differential_test.exe", job.directory)];
						if !start_worker(worker, runtime_arguments, memory_bytes, job.directory, tprint("%/runtime.log", job.directory)) {
							runner_failure("\e[91mUnable to launch\e[0m runtime checks. Logs: \e[96m%\e[0m\n", job.directory);
							return 1;
						}


						worker.job_index = job_index;
						worker.runtime_phase = true;
						worker.started = GetTickCount64();
						worker.marker = copy_string(tprint("%/% tests", job.expected, job.expected));
						runner_worker_slot(worker, it_index);
						runner_worker_label(worker, tprint("worker % job % % %..% runtime", it_index, job_index + 1, section.name, job.first, job.last));
						active += 1;
					} else {
						finished += 1;
						covered += job.expected;
						sections[job.section].completed += job.expected;
						runner_summary_complete(job.section, sections[job.section].completed, job.expected);
						runner_message(
							"\e[92mPASS\e[0m job \e[93m%\e[0m/\e[93m%\e[0m [\e[96m%\e[0m \e[93m%\e[0m..\e[93m%\e[0m] fixtures=\e[93m%\e[0m covered=\e[92m%\e[0m/\e[93m%\e[0m\n",
							job_index + 1,
							jobs.count,
							section.name,
							job.first,
							job.last,
							job.expected,
							covered,
							expected_total
						);
						clean_runner_job(job.directory);
					}

				case WAIT_TIMEOUT;
					if GetTickCount64() - worker.started >= xx (options.timeout_seconds * 1000) {
						runner_failure(
							"\e[93mTIMEOUT\e[0m job \e[93m%\e[0m [\e[96m%\e[0m \e[93m%\e[0m..\e[93m%\e[0m]; stopping worker trees. Logs: \e[96m%\e[0m\n",
							worker.job_index + 1,
							section.name,
							job.first,
							job.last,
							job.directory
						);
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
			if status.ullAvailPhys < reservation && status.ullAvailPageFile < reservation {
				runner_message(
					"\e[95mInsufficient resources\e[0m for job reservation. Required:\n\t\e[93m%\e[0m bytes; available:\n\t\e[95m%\e[0m RAM bytes,\n\t\e[92m%\e[0m PF bytes\n",
					reservation,
					status.ullAvailPhys,
					status.ullAvailPageFile
				);
				break;
			}


			job := jobs[next_job];
			section := sections[job.section];
			if !start_compiler_job(worker, compiler, job.directory, tprint("%", job.section + 1), job.first, job.last, memory_bytes) {
				runner_failure("\e[91mUnable to launch\e[0m job \e[93m%\e[0m. Logs: \e[96m%\e[0m\n", next_job + 1, job.directory);
				return 1;
			}


			worker.job_index = next_job;
			worker.started = GetTickCount64();
			worker.marker = copy_string(tprint("compile-time checks (%/% total tests)", ifx section.runtime then 0 else job.expected, job.expected));
			runner_worker_slot(worker, it_index);
			runner_worker_label(worker, tprint("worker % job % % %..% compile", it_index, next_job + 1, section.name, job.first, job.last));
			runner_summary_launch(job.section, section.name, section.completed, section.selected_total, next_job + 1);
			runner_message(
				"\e[96mSTART\e[0m job (on worker %) \e[93m%\e[0m/\e[93m%\e[0m [\e[96m%\e[0m \e[93m%\e[0m..\e[93m%\e[0m] pid=\e[93m%\e[0m\n",
				it_index,
				next_job + 1,
				jobs.count,
				section.name,
				job.first,
				job.last,
				worker.info.dwProcessId
			);
			next_job += 1;
			active += 1;
			admission_started = GetTickCount64();
		}


		statistics.max_active = max(statistics.max_active, active);
		if finished == jobs.count {
			break;
		}


		if !active && GetTickCount64() - admission_started >= xx (options.timeout_seconds * 1000) {
			runner_failure("\e[93mTimed out\e[0m waiting for physical/commit headroom. Logs: \e[96m%\e[0m\n", root);
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
		runner_failure("\e[91mFAIL\e[0m coverage: \e[91m%\e[0m/\e[93m%\e[0m fixtures\n", covered, expected_total);
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


	runner_display.summary_status = "PASS";
	if !runner_display.vt {
		runner_display.summary_final = true;
		text := runner_summary_text(0x7FFF_FFFF);
		defer free(text.data);

		runner_message("%\n", text);
	}

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
						valid, value := get_runner_environment(utf8_to_wide(name,, temp));
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

			case .STREAM;
				print("\r\e[K[1/2] live 1/2 (total 1/2): ");
				event := CreateEventW(null, 1, 0, null);
				WaitForSingleObject(event, 250);
				CloseHandle(event);
				print("\r\e[Kstream-ok\n");
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
				print("unterminated diagnostic");
				event := CreateEventW(null, 1, 0, null);
				WaitForSingleObject(event, INFINITE);
				CloseHandle(event);
				return;
		}


		exit(64);
	}


	code := run_runner(arguments);
	if code {
		exit(code);
	}
}
