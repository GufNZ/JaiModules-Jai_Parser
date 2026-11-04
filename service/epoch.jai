// R10 epoch issuer: a per-project `.jaiParserEpoch` file beside the store root, holding the authority namespace and the last reserved epoch.
// Reservation holds an exclusive sibling lock file, writes the successor to a staging file, flushes it and replaces the epoch file.
// Only the Windows implementation exists so far (R11); other platforms report the issuer as unavailable.

EPOCH_FILE_NAME :: ".jaiParserEpoch";
EPOCH_FILE_SCHEMA :: "jai-cache-epoch/1";
EPOCH_FILE_MAXIMUM_BYTES :: 4096;
EPOCH_LOCK_ATTEMPTS :: 500;
EPOCH_LOCK_RETRY_MILLISECONDS :: 10;

Epoch_Failure :: enum u8 {
	NONE;
	UNSUPPORTED_PLATFORM;
	LOCK_UNAVAILABLE;
	IO_ERROR;
	MALFORMED_FILE;
	AUTHORITY_MISMATCH;
	EXHAUSTED;
}

encode_epoch_file :: (authority_namespace: [] u8, epoch: u64) -> string {
	builder: String_Builder;
	print(*builder, "%\n", EPOCH_FILE_SCHEMA);
	append_uppercase_hex(*builder, authority_namespace);
	print(*builder, "\n%\n", epoch);
	return builder_to_string(*builder);
}

// Strict: the exact schema line, the matching uppercase-hex namespace and a canonical decimal epoch, each LF-terminated, nothing else.
decode_epoch_file :: (text: string, authority_namespace: [] u8) -> Epoch_Failure, u64 {
	lines := split(text, "\n",, temp);
	if lines.count != 4 || lines[3] != "" || lines[0] != EPOCH_FILE_SCHEMA {
		return .MALFORMED_FILE, 0;
	}


	expected := encode_epoch_file(authority_namespace, 0,, temp);
	expected_namespace_line := split(expected, "\n",, temp)[1];
	if lines[1] != expected_namespace_line {
		return .AUTHORITY_MISMATCH, 0;
	}


	digits := lines[2];
	if !digits.count || digits.count > 20 || (digits.count > 1 && digits[0] == #char "0") {
		return .MALFORMED_FILE, 0;
	}


	value: u64;
	for digits {
		if it < #char "0" || it > #char "9" {
			return .MALFORMED_FILE, 0;
		}


		digit: u64 = it - #char "0";
		if value > (U64_MAX - digit) / 10 {
			return .MALFORMED_FILE, 0;
		}


		value = value * 10 + digit;
	}


	return .NONE, value;
}

// Reserves a fresh epoch greater than both the last recorded one and `floor` (the highest writer epoch in any readable store head).
reserve_epoch :: (directory: string, authority_namespace: [] u8, floor: u64 = 0) -> bool, u64, Epoch_Failure {
	#if OS != .WINDOWS {
		return false, 0, .UNSUPPORTED_PLATFORM;
	} else {
		assert(authority_namespace.count > 0);
		epoch_path := tprint("%/%", directory, EPOCH_FILE_NAME);
		lock_path := tprint("%.lock", epoch_path);
		staging_path := tprint("%.staging", epoch_path);

		lock := INVALID_HANDLE_VALUE;
		for 1..EPOCH_LOCK_ATTEMPTS {
			lock = CreateFileW(utf8_to_wide(lock_path,, temp), FILE_GENERIC_READ | FILE_GENERIC_WRITE, 0, null, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, null);
			if lock != INVALID_HANDLE_VALUE || GetLastError() != ERROR_SHARING_VIOLATION {
				break;
			}


			sleep_milliseconds(EPOCH_LOCK_RETRY_MILLISECONDS);
		}

		if lock == INVALID_HANDLE_VALUE {
			return false, 0, .LOCK_UNAVAILABLE;
		}


		defer CloseHandle(lock);

		last: u64;
		read_failure, existing := read_small_file(epoch_path);
		if read_failure != .NONE {
			return false, 0, read_failure;
		}


		if existing.count {
			failure, decoded := decode_epoch_file(existing, authority_namespace);
			if failure != .NONE {
				return false, 0, failure;
			}


			last = decoded;
		}


		base := max(last, floor);
		if base >= U64_MAX - 1 {
			return false, 0, .EXHAUSTED;
		}


		epoch := base + 1;
		if !write_flushed_file(staging_path, encode_epoch_file(authority_namespace, epoch,, temp)) {
			return false, 0, .IO_ERROR;
		}


		if !MoveFileExW(utf8_to_wide(staging_path,, temp), utf8_to_wide(epoch_path,, temp), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH) {
			return false, 0, .IO_ERROR;
		}


		return true, epoch, .NONE;
	}
}

#scope_file

#if OS == .WINDOWS {
	MoveFileExW :: (existing: *u16, replacement: *u16, flags: u32) -> BOOL #foreign kernel32;
	MOVEFILE_REPLACE_EXISTING :: 0x1;
	MOVEFILE_WRITE_THROUGH :: 0x8;
	ERROR_SHARING_VIOLATION :: 0x20;

	// A missing file reads as empty; anything over the bound or unreadable is an error rather than a truncated read.
	read_small_file :: (path: string) -> Epoch_Failure, string {
		handle := CreateFileW(utf8_to_wide(path,, temp), FILE_GENERIC_READ, FILE_SHARE_READ, null, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, null);
		if handle == INVALID_HANDLE_VALUE {
			return ifx GetLastError() == ERROR_FILE_NOT_FOUND then .NONE else .IO_ERROR, "";
		}


		defer CloseHandle(handle);
		size: LARGE_INTEGER;
		if !GetFileSizeEx(handle, *size) || size.QuadPart < 0 || size.QuadPart > EPOCH_FILE_MAXIMUM_BYTES {
			return .MALFORMED_FILE, "";
		}


		if !size.QuadPart {
			return .MALFORMED_FILE, "";
		}


		buffer := talloc_string(size.QuadPart);
		read: DWORD;
		if !ReadFile(handle, buffer.data, xx buffer.count, *read) || read != xx buffer.count {
			return .IO_ERROR, "";
		}


		return .NONE, buffer;
	}

	write_flushed_file :: (path: string, text: string) -> bool {
		handle := CreateFileW(utf8_to_wide(path,, temp), FILE_GENERIC_WRITE, 0, null, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, null);
		if handle == INVALID_HANDLE_VALUE {
			return false;
		}


		defer CloseHandle(handle);
		written: DWORD;
		return WriteFile(handle, text.data, xx text.count, *written, null) && written == xx text.count && FlushFileBuffers(handle);
	}
}
