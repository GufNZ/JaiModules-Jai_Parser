// R10 epoch issuer: a per-project `.jaiParserEpoch` file beside the store root, holding the authority namespace and the last reserved epoch.
// Reservation holds an exclusive sibling lock file, writes the successor to a staging file, flushes it and replaces the epoch file.
// Windows and POSIX (Linux, macOS) implementations exist (R11); only Windows has been run.  Other platforms report the issuer as unavailable.

EPOCH_ISSUER_SUPPORTED :: OS == .WINDOWS || OS == .LINUX || OS == .MACOS;

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
	#if !EPOCH_ISSUER_SUPPORTED {
		return false, 0, .UNSUPPORTED_PLATFORM;
	} else {
		assert(authority_namespace.count > 0);
		epoch_path := tprint("%/%", directory, EPOCH_FILE_NAME);
		lock_path := tprint("%.lock", epoch_path);
		staging_path := tprint("%.staging", epoch_path);

		lock_failure, lock := acquire_epoch_lock(lock_path);
		if lock_failure != .NONE {
			return false, 0, lock_failure;
		}


		defer release_epoch_lock(lock);

		last: u64;
		read_failure, existing := read_small_file(epoch_path);
		#if TEST_HOOKS {
			if epoch_test_hooks.fail_at == .READ {
				read_failure = .IO_ERROR;
			}
		}

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
		text := encode_epoch_file(authority_namespace, epoch,, temp);
		#if TEST_HOOKS {
			if epoch_test_hooks.fail_at == .STAGING_WRITE {
				write_flushed_file(staging_path, slice(text, 0, text.count / 2));
				return false, 0, .IO_ERROR;
			}
		}


		if !write_flushed_file(staging_path, text) {
			return false, 0, .IO_ERROR;
		}


		#if TEST_HOOKS {
			if epoch_test_hooks.fail_at == .REPLACE {
				return false, 0, .IO_ERROR;
			}
		}


		if !replace_epoch_file(staging_path, epoch_path, directory) {
			return false, 0, .IO_ERROR;
		}


		return true, epoch, .NONE;
	}
}

#if TEST_HOOKS && EPOCH_ISSUER_SUPPORTED {
	Epoch_Fault_Point :: enum u8 {
		NONE;
		READ;
		STAGING_WRITE;
		REPLACE;
	}

	// `shared_lock` drops the exclusion the lock provides; `lock_attempts` shortens contention waits.
	Epoch_Test_Hooks :: struct {
		fail_at: Epoch_Fault_Point;
		shared_lock: bool;
		lock_attempts := EPOCH_LOCK_ATTEMPTS;
	}

	epoch_test_hooks: Epoch_Test_Hooks;

	#if OS == .WINDOWS {
		Epoch_Lock :: HANDLE;
	} else {
		Epoch_Lock :: s32;
	}

	// Holds the lock file the way a `shared_lock` reservation would, standing in for a concurrent holder.
	hold_epoch_lock :: (directory: string) -> bool, Epoch_Lock {
		path := tprint("%/%.lock", directory, EPOCH_FILE_NAME);
		#if OS == .WINDOWS {
			lock := CreateFileW(utf8_to_wide(path,, temp), FILE_GENERIC_READ | FILE_GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, null, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, null);
			return lock != INVALID_HANDLE_VALUE, lock;
		} else {
			fd := open(temp_c_string(path), O_RDWR | O_CREAT | O_CLOEXEC, EPOCH_FILE_MODE);
			if fd >= 0 && epoch_flock(fd, LOCK_EX | LOCK_NB) {
				close(fd);
				return false, -1;
			}


			return fd >= 0, fd;
		}
	}

	drop_epoch_lock :: (lock: Epoch_Lock) {
		release_epoch_lock(lock);
	}
}

#scope_file

#if OS == .WINDOWS {
	MoveFileExW :: (existing: *u16, replacement: *u16, flags: u32) -> BOOL #foreign kernel32;
	MOVEFILE_REPLACE_EXISTING :: 0x1;
	MOVEFILE_WRITE_THROUGH :: 0x8;
	ERROR_SHARING_VIOLATION :: 0x20;

	// Share mode 0 is the exclusive lock; closing the handle releases it.
	acquire_epoch_lock :: (path: string) -> Epoch_Failure, HANDLE {
		attempts := EPOCH_LOCK_ATTEMPTS;
		share: u32 = 0;
		#if TEST_HOOKS {
			attempts = epoch_test_hooks.lock_attempts;
			if epoch_test_hooks.shared_lock {
				share = FILE_SHARE_READ | FILE_SHARE_WRITE;
			}
		}

		for 1..attempts {
			lock := CreateFileW(utf8_to_wide(path,, temp), FILE_GENERIC_READ | FILE_GENERIC_WRITE, share, null, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, null);
			if lock != INVALID_HANDLE_VALUE {
				return .NONE, lock;
			}


			if GetLastError() != ERROR_SHARING_VIOLATION {
				return .IO_ERROR, INVALID_HANDLE_VALUE;
			}


			sleep_milliseconds(EPOCH_LOCK_RETRY_MILLISECONDS);
		}


		return .LOCK_UNAVAILABLE, INVALID_HANDLE_VALUE;
	}

	release_epoch_lock :: (lock: HANDLE) {
		CloseHandle(lock);
	}

	// `MOVEFILE_WRITE_THROUGH` makes the directory entry durable, so `directory` needs no separate flush.
	// Scanners such as antivirus briefly open the new file without delete sharing, so retry those transient denials while still holding the lock.
	replace_epoch_file :: (staging_path: string, epoch_path: string, directory: string) -> bool {
		for 1..EPOCH_LOCK_ATTEMPTS {
			if MoveFileExW(utf8_to_wide(staging_path,, temp), utf8_to_wide(epoch_path,, temp), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH) {
				return true;
			}


			error := GetLastError();
			if error != ERROR_ACCESS_DENIED && error != ERROR_SHARING_VIOLATION {
				return false;
			}


			sleep_milliseconds(EPOCH_LOCK_RETRY_MILLISECONDS);
		}


		return false;
	}

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
} else #if OS == .LINUX || OS == .MACOS {
	// Linux bindings only declare the `flock` struct, so bind the function under another name.
	epoch_flock :: (fd: s32, operation: s32) -> s32 #foreign epoch_libc "flock";
	epoch_libc :: #library,system "libc";

	EPOCH_FILE_MODE :: S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH;

	// `flock` excludes other open descriptions, including threads of this process; `O_CLOEXEC` keeps children from inheriting the lock.
	acquire_epoch_lock :: (path: string) -> Epoch_Failure, s32 {
		fd := open(temp_c_string(path), O_RDWR | O_CREAT | O_CLOEXEC, EPOCH_FILE_MODE);
		if fd < 0 {
			return .IO_ERROR, -1;
		}


		attempts := EPOCH_LOCK_ATTEMPTS;
		#if TEST_HOOKS {
			attempts = epoch_test_hooks.lock_attempts;
			if epoch_test_hooks.shared_lock {
				return .NONE, fd;
			}
		}


		for 1..attempts {
			if !epoch_flock(fd, LOCK_EX | LOCK_NB) {
				return .NONE, fd;
			}


			error := errno();
			if error != EWOULDBLOCK && error != EINTR {
				close(fd);
				return .IO_ERROR, -1;
			}


			sleep_milliseconds(EPOCH_LOCK_RETRY_MILLISECONDS);
		}


		close(fd);
		return .LOCK_UNAVAILABLE, -1;
	}

	release_epoch_lock :: (fd: s32) {
		close(fd);
	}

	// macOS `fsync` does not flush the drive cache; `F_FULLFSYNC` does, but some filesystems reject it.
	flush_descriptor :: (fd: s32) -> bool {
		#if OS == .MACOS {
			if fcntl(fd, F_FULLFSYNC) != -1 {
				return true;
			}
		}


		return fsync(fd) == 0;
	}

	// `rename` replaces atomically; flushing the directory makes the new entry durable.
	replace_epoch_file :: (staging_path: string, epoch_path: string, directory: string) -> bool {
		if rename(temp_c_string(staging_path), temp_c_string(epoch_path)) {
			return false;
		}


		directory_fd := open(temp_c_string(directory), O_RDONLY | O_DIRECTORY | O_CLOEXEC);
		if directory_fd < 0 {
			return false;
		}


		defer close(directory_fd);
		return flush_descriptor(directory_fd);
	}

	// A missing file reads as empty; anything over the bound or unreadable is an error rather than a truncated read.
	read_small_file :: (path: string) -> Epoch_Failure, string {
		fd := open(temp_c_string(path), O_RDONLY | O_CLOEXEC);
		if fd < 0 {
			return ifx errno() == ENOENT then .NONE else .IO_ERROR, "";
		}


		defer close(fd);
		// One byte past the bound detects oversized files without `fstat`.
		buffer := talloc_string(EPOCH_FILE_MAXIMUM_BYTES + 1);
		total: s64;
		while total < buffer.count {
			got := read(fd, buffer.data + total, xx (buffer.count - total));
			if got < 0 {
				if errno() == EINTR {
					continue;
				}


				return .IO_ERROR, "";
			}


			if !got {
				break;
			}


			total += got;
		}


		if !total || total > EPOCH_FILE_MAXIMUM_BYTES {
			return .MALFORMED_FILE, "";
		}


		buffer.count = total;
		return .NONE, buffer;
	}

	write_flushed_file :: (path: string, text: string) -> bool {
		fd := open(temp_c_string(path), O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, EPOCH_FILE_MODE);
		if fd < 0 {
			return false;
		}


		defer close(fd);
		written: s64;
		while written < text.count {
			count := write(fd, text.data + written, xx (text.count - written));
			if count < 0 {
				if errno() == EINTR {
					continue;
				}


				return false;
			}


			written += count;
		}


		return flush_descriptor(fd);
	}
}
