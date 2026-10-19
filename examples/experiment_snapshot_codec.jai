#import "Basic";
#import "Compiler";
#import "File";
#import "Hash";
#import "Hash_Table";
#import "Pool";
#import "String";
#import "Sort";
#import "Text_File_Handler";

Parser :: #import "Jai_Parser"(ENABLE_TRIVIA = true);

VERIFY_ONLY :: false;
#load "snapshot_oracle.jai";

HEX :: "0123456789ABCDEF";
MAX_ARTIFACT_BYTES :: 67108864;
MAX_OBJECTS :: 262144;
MAX_ELEMENTS :: 1048576;

Writer :: struct {
	text: String_Builder;
	objects: Table(*void, s64);
}

Reader :: struct {
	remaining: string;
	objects: [..]Object;
}

Object :: struct {
	address: *void;
	info: *Type_Info_Struct;
}

Codec :: struct {
	reading: bool;
	writer: Writer;
	reader: Reader;
	depth: s64;
	allocated: s64;
}

Owned_Snapshot :: struct {
	parsed: Parser.Parsed_Source;
	storage: Pool;
}

write_bytes :: (writer: *Writer, tag: string, bytes: []u8) {
	print(*writer.text, "% % ", tag, bytes.count);
	for byte: bytes {
		append(*writer.text, HEX[byte >> 4]);
		append(*writer.text, HEX[byte & 0xF]);
	}

	append(*writer.text, "\n");
}

read_row :: (reader: *Reader, tag: string) -> string {
	assert(!!reader.remaining.count && reader.remaining.count <= MAX_ARTIFACT_BYTES);
	ending: s64 = -1;
	for byte: reader.remaining {
		if byte == 10 {
			ending = it_index;
			break;
		}
	}

	assert(ending >= 0);
	line := slice(reader.remaining, 0, ending);
	reader.remaining = slice(reader.remaining, ending + 1, reader.remaining.count - ending - 1);
	actual, payload := break_by_spaces(line);
	assert(actual == tag, "Expected record %, got %", tag, actual);
	return payload;
}

read_decimal :: (text: *string) -> s64 {
	token, rest := break_by_spaces(text.*);
	text.* = rest;
	value, ok, trailing := string_to_int(token);
	assert(ok && !trailing.count && value >= 0);
	return value;
}

hex_digit :: (byte: u8) -> u8 {
	if byte >= #char "0" && byte <= #char "9" {
		return byte - #char "0";
	}


	assert(byte >= #char "A" && byte <= #char "F");
	return byte - #char "A" + 10;
}

read_bytes :: (reader: *Reader, tag: string) -> []u8 {
	row := read_row(reader, tag);
	count := read_decimal(*row);
	assert(count <= MAX_ARTIFACT_BYTES / 2 && row.count == count * 2);
	result := NewArray(count, u8);
	for 0..count - 1 {
		result[it] = (hex_digit(row[it * 2]) << 4) | hex_digit(row[it * 2 + 1]);
	}

	return result;
}

write_value :: (writer: *Writer, info: *Type_Info, value: *void) {
	if info.type == {
		case .STRING;
			text := value.(*string).*;
			write_bytes(writer, "S", .{count = text.count, data = text.data});

		case .INTEGER; #through;
		case .FLOAT; #through;
		case .BOOL; #through;
		case .ENUM;
			write_bytes(writer, "B", .{count = info.runtime_size, data = value.(*u8)});

		case;
			assert(false, "Unsupported snapshot value type");
	}
}

read_value :: (reader: *Reader, info: *Type_Info, value: *void) {
	if info.type == {
		case .STRING;
			bytes := read_bytes(reader, "S");
			value.(*string).* = .{count = bytes.count, data = bytes.data};

		case .INTEGER; #through;
		case .FLOAT; #through;
		case .BOOL; #through;
		case .ENUM;
			bytes := read_bytes(reader, "B");
			assert(bytes.count == info.runtime_size);
			memcpy(value, bytes.data, bytes.count);

		case;
			assert(false, "Unsupported snapshot value type");
	}
}

reserve :: (codec: *Codec, size: s64) -> *void {
	assert(size >= 0 && size <= 268435456 - codec.allocated);
	codec.allocated += size;
	memory := alloc(size);
	memset(memory, 0, size);
	return memory;
}

node_type :: (info: *Type_Info_Struct) -> bool {
	for entry: ORACLE_NODE_TYPES {
		if entry.info == info {
			return true;
		}
	}


	return false;
}

field :: (codec: *Codec, value: *$T) {
	transfer(codec, type_info(T), value);
}

overlay :: (codec: *Codec, root: *Type_Info_Struct, info: *Type_Info_Struct, value: *u8, offset: s64) {
	for member: info.members {
		if member.offset_in_bytes < 0 || member.flags & .CONSTANT || info.name == "Code_Literal" && member.name == "values" {
			continue;
		}


		overridden := false;
		for replacement: root.members {
			if (replacement.flags & .OVERLAY && !starts_with(replacement.name, "_Code_")
				&& replacement.offset_in_bytes == offset + member.offset_in_bytes
			) {
				overridden = true;
				break;
			}
		}

		if !overridden {
			transfer(codec, member.type, value + member.offset_in_bytes);
		}
	}
}

token :: (codec: *Codec, value: *Parser.Token) {
	field(codec, *value.type);
	field(codec, *value.l0);
	field(codec, *value.c0);
	field(codec, *value.l1);
	field(codec, *value.c1);
	field(codec, *value.value_flags);
	field(codec, *value.ident_is_backticked);
	field(codec, *value.original_text);
	field(codec, *value.preceding_trivia);
	field(codec, *value.trailing_trivia);

	if value.type == {
		case .IDENT; #through;
		case .NOTE;
			field(codec, *value.ident_value.name);
			field(codec, *value.ident_value.hash);

		case .STRING;
			field(codec, *value.string_value);

		case .NUMBER;
			field(codec, *value.integer_value);
	}
}

literal :: (codec: *Codec, value: *Parser.Parser_Literal) {
	if value.value_type == {
		case .STRING;
			field(codec, *value._string);

		case .ARRAY;
			field(codec, *value.array_literal_info);

		case .STRUCT;
			field(codec, *value.struct_literal_info);

		case .POINTER;
			field(codec, *value.pointer_literal_info);

		case .NUMBER; #through;
		case .BOOLEAN; #through;
		case .UNINITIALIZED;
			field(codec, *value._u64);

		case;
			assert(false, "Unsupported literal discriminator");
	}
}

pointer :: (codec: *Codec, info: *Type_Info_Pointer, value: **void) {
	if codec.reading {
		row := read_row(*codec.reader, "P");
		identity := read_decimal(*row);
		assert(!row.count && identity <= MAX_OBJECTS);
		if !identity {
			value.* = null;
			return;
		}


		assert(info.pointer_to.type == .STRUCT);
		expected := info.pointer_to.(*Type_Info_Struct);
		if identity <= codec.reader.objects.count {
			object := codec.reader.objects[identity - 1];
			assert(expected == object.info || expected == type_info(Parser.Parser_Node) && node_type(object.info));
			value.* = object.address;
			return;
		}


		assert(identity == codec.reader.objects.count + 1);
		row = read_row(*codec.reader, "N");
		layout := read_decimal(*row);
		assert(!row.count && layout <= ORACLE_NODE_TYPES.count);
		structure := expected;
		if node_type(expected) {
			assert(layout > 0);
			structure = ORACLE_NODE_TYPES[layout - 1].info;
			assert(expected == structure || expected == type_info(Parser.Parser_Node));
		} else {
			assert(!layout && (starts_with(expected.name, "Parser_") || expected == type_info(Code_Pointer_Literal_Info)));
		}

		value.* = reserve(codec, structure.runtime_size);
		array_add(*codec.reader.objects, .{address = value.*, info = structure});
		transfer(codec, structure, value.*);
		if layout {
			assert(value.*.(*Parser.Parser_Node).kind == ORACLE_NODE_TYPES[layout - 1].kind);
		}
	} else {
		if !value.* {
			print(*codec.writer.text, "P 0\n");
			return;
		}


		found, identity := table_find(*codec.writer.objects, value.*);
		if found {
			print(*codec.writer.text, "P %\n", identity);
			return;
		}


		assert(info.pointer_to.type == .STRUCT && codec.writer.objects.count < MAX_OBJECTS);
		structure := info.pointer_to.(*Type_Info_Struct);
		layout: s64;
		if node_type(structure) {
			for entry: ORACLE_NODE_TYPES {
				if entry.kind == value.*.(*Parser.Parser_Node).kind {
					structure = entry.info;
					layout = it_index + 1;
					break;
				}
			}

			assert(layout > 0);
		} else {
			assert(starts_with(structure.name, "Parser_") || structure == type_info(Code_Pointer_Literal_Info));
		}

		identity = codec.writer.objects.count + 1;
		table_add(*codec.writer.objects, value.*, identity);
		print(*codec.writer.text, "P %\nN %\n", identity, layout);
		transfer(codec, structure, value.*);
	}
}

transfer :: (codec: *Codec, info: *Type_Info, value: *void) {
	codec.depth += 1;
	defer codec.depth -= 1;
	assert(codec.depth <= 512);
	if info.type == {
		case .STRING;
			if codec.reading {
				row := read_row(*codec.reader, "S");
				count := read_decimal(*row);
				assert(count <= MAX_ARTIFACT_BYTES / 2 && row.count == count * 2);
				text := value.(*string);
				text.count = count;
				text.data = reserve(codec, count);

				for 0..count - 1 {
					text.data[it] = (hex_digit(row[it * 2]) << 4) | hex_digit(row[it * 2 + 1]);
				}
			} else {
				write_value(*codec.writer, info, value);
			}

		case .INTEGER; #through;
		case .FLOAT; #through;
		case .BOOL; #through;
		case .ENUM;
			if codec.reading {
				row := read_row(*codec.reader, "B");
				count := read_decimal(*row);
				assert(count == info.runtime_size && row.count == count * 2);

				for 0..count - 1 {
					value.(*u8)[it] = (hex_digit(row[it * 2]) << 4) | hex_digit(row[it * 2 + 1]);
				}
			} else {
				write_value(*codec.writer, info, value);
			}

		case .VARIANT;
			transfer(codec, info.(*Type_Info_Variant).variant_of, value);

		case .POINTER;
			pointer(codec, info.(*Type_Info_Pointer), value.(**void));

		case .ARRAY;
			array := info.(*Type_Info_Array);
			count := array.array_count;
			data := value.(*u8);
			if array.array_type != .FIXED {
				view := value.(*[]u8);
				if codec.reading {
					row := read_row(*codec.reader, "A");
					count = read_decimal(*row);
					assert(!row.count && count <= MAX_ELEMENTS && array.element_type.runtime_size <= 268435456 / Max(count, 1));
					view.count = count;
					view.data = reserve(codec, count * array.element_type.runtime_size);
				} else {
					count = view.count;
					assert(count <= MAX_ELEMENTS);
					print(*codec.writer.text, "A %\n", count);
				}

				data = view.data;
			}

			for 0..count - 1 {
				transfer(codec, array.element_type, data + it * array.element_type.runtime_size);
			}

		case .STRUCT;
			structure := info.(*Type_Info_Struct);
			if structure == type_info(Parser.Token) {
				token(codec, xx value);
				return;
			}


			if structure == type_info(Parser.Parser_Literal) {
				item := value.(*Parser.Parser_Literal);
				field(codec, *item.base);
				field(codec, *item.value_type);
				field(codec, *item.value_flags);
				literal(codec, item);
				return;
			}


			if structure == type_info(Code_Pointer_Literal_Info) {
				item := value.(*Code_Pointer_Literal_Info);
				field(codec, *item.pointer_literal_type);
				assert(item.pointer_literal_type == .CONSTANT_VALUE && !item.global_symbol && !item.data_pointer);
				field(codec, *item.offset_from_symbol);
				return;
			}


			assert(!(structure.textual_flags & .UNION), "Unsupported union %", structure.name);
			for member: structure.members {
				if member.offset_in_bytes < 0 || member.flags & .CONSTANT || member.name == "_padding" {
					continue;
				}


				if structure == type_info(Parser.Parser_Literal) && (member.name == "array_literal_info" || member.name == "struct_literal_info") {
					continue;
				}


				if starts_with(member.name, "_Code_") {
					overlay(codec, structure, member.type.(*Type_Info_Struct), value.(*u8) + member.offset_in_bytes, member.offset_in_bytes);
				} else {
					transfer(codec, member.type, value.(*u8) + member.offset_in_bytes);
				}
			}

		case;
			assert(false, "Unsupported snapshot graph field");
	}
}

snapshot_fields :: (codec: *Codec, parsed: *Parser.Parsed_Source) {
	field(codec, *parsed.source);
	field(codec, *parsed.fully_pathed_filename);
	field(codec, *parsed.tokens);
	field(codec, *parsed.synthetic_tokens);
	field(codec, *parsed.diagnostics);
	field(codec, *parsed.recovery_records);
	field(codec, *parsed.restart_points);
	field(codec, *parsed.status);
	field(codec, *parsed.root);
	field(codec, *parsed.root_scope);
}

encode_snapshot :: (parsed: *Parser.Parsed_Source) -> string {
	codec: Codec;
	defer table_reset(*codec.writer.objects);

	snapshot_fields(*codec, parsed);
	text := builder_to_string(*codec.writer.text);
	defer free(text);

	assert(text.count <= MAX_ARTIFACT_BYTES);
	digest := fnv1a_hash(text.data, text.count);
	return sprint("[14]\nK % %\nH % % %\n%", SCHEMA_DIGEST >> 32, SCHEMA_DIGEST & 0xFFFFFFFF, text.count, digest >> 32, digest & 0xFFFFFFFF, text);
}

schema_digest :: () -> u64 {
	builder: String_Builder;
	print(*builder, "E12_GRAPH_1_LE64\n");
	structures: [..]*Type_Info_Struct;
	defer array_free(structures);

	for entry: ORACLE_NODE_TYPES {
		array_add(*structures, entry.info);
	}

	array_add(*structures, type_info(Parser.Token));
	array_add(*structures, type_info(Parser.Parsed_Source));
	array_add(*structures, type_info(Parser.Parser_Lexical_Scope));
	array_add(*structures, type_info(Parser.Parse_Diagnostic));

	for structure: structures {
		print(*builder, "% %\n", structure.name, structure.runtime_size);
		for member: structure.members {
			if member.offset_in_bytes >= 0 && !(member.flags & .CONSTANT) {
				print(*builder, "% % % %\n", member.name, member.offset_in_bytes, member.type.type, member.type.runtime_size);
			}
		}
	}

	text := builder_to_string(*builder);
	defer free(text);
	return fnv1a_hash(text.data, text.count);
}

SCHEMA_DIGEST :: #run schema_digest();

decode_snapshot :: (text: string) -> *Owned_Snapshot {
	endian: u64 = 1;
	assert(size_of(*void) == 8 && (*endian).(*u8)[0] == 1 && text.count <= MAX_ARTIFACT_BYTES);
	result := New(Owned_Snapshot);
	set_allocators(*result.storage);
	push_allocator(.{proc = pool_allocator_proc, data = *result.storage});
	codec := Codec.{reading = true, reader = .{remaining = text}};
	assert(!read_row(*codec.reader, "[14]").count);
	row := read_row(*codec.reader, "K");
	schema_high := read_decimal(*row);
	schema_low := read_decimal(*row);
	assert(!row.count && schema_high.(u64) == SCHEMA_DIGEST >> 32 && schema_low.(u64) == SCHEMA_DIGEST & 0xFFFFFFFF);
	row = read_row(*codec.reader, "H");
	count := read_decimal(*row);
	high := read_decimal(*row);
	low := read_decimal(*row);
	assert(!row.count && count == codec.reader.remaining.count && high <= 0xFFFFFFFF && low <= 0xFFFFFFFF);
	assert(fnv1a_hash(codec.reader.remaining.data, count) == (high.(u64) << 32 | low.(u64)));
	snapshot_fields(*codec, *result.parsed);
	assert(!codec.reader.remaining.count);
	return result;
}

parse_owned :: (source: string, filename: string = "E12") -> *Owned_Snapshot {
	result := New(Owned_Snapshot);
	set_allocators(*result.storage);
	push_allocator(.{proc = pool_allocator_proc, data = *result.storage});
	result.parsed = Parser.parse_file(copy_string(source), copy_string(filename));
	return result;
}

release_owned :: (snapshot: *Owned_Snapshot) {
	Parser.release_parser_tree(*snapshot.parsed);
	Parser.release_parser_names(*snapshot.parsed);
	release(*snapshot.storage);
	free(snapshot);
}

self_tests :: () {
	storage: Pool;
	set_allocators(*storage);
	defer release(*storage);

	push_allocator(.{proc = pool_allocator_proc, data = *storage});
	defer reset_temporary_storage();

	writer: Writer;
	text := "owned\x00bytes\n\"\\";
	empty := "";
	number: u64 = 0x8000000000000001;
	write_value(*writer, type_info(string), *text);
	write_value(*writer, type_info(string), *empty);
	write_value(*writer, type_info(u64), *number);
	encoded := builder_to_string(*writer.text);
	reader := Reader.{remaining = encoded};
	decoded: string;
	decoded_empty: string;
	decoded_number: u64;
	read_value(*reader, type_info(string), *decoded);
	read_value(*reader, type_info(string), *decoded_empty);
	read_value(*reader, type_info(u64), *decoded_number);
	assert(decoded == text && !decoded_empty.count && decoded_number == number && !reader.remaining.count);
	assert(decoded.data != text.data);

	sources := string.[
		"",
		"value :: 1; result := value; items :: .[1, 2]; text :: \"hello\"; #if true { inner :: value; }",
		"Shape :: struct { first: s64; second: s64; } value := Shape.{first = 3, second = 4};",
		"Shape :: struct { Self :: #this; value: *Self; } empty := null; number := -0.0; wide := 0xFFFFFFFFFFFFFFFF;",
		"probe :: (value: s64) -> s64 { if value > 0 { return value + 1; } return 0; }",
		"value :: ; next :: 1",
		"probe :: () -> s64 { return 2;"
	];
	for source: sources {
		producer := parse_owned(source);
		producer.storage.overwrite_memory = true;
		producer.parsed.node_pool.overwrite_memory = true;
		artifact := encode_snapshot(*producer.parsed);
		release_owned(producer);

		snapshot := decode_snapshot(artifact);
		sibling := decode_snapshot(artifact);
		memset(artifact.data, 0xDD, artifact.count);
		free(artifact);
		fresh := parse_owned(source);
		check_snapshot(*snapshot.parsed, *fresh.parsed);
		check_snapshot(*sibling.parsed, *snapshot.parsed);
		snapshot.storage.overwrite_memory = true;
		release_owned(snapshot);
		check_snapshot(*sibling.parsed, *fresh.parsed);
		release_owned(sibling);
		release_owned(fresh);
	}

	print("E12 snapshot codec: exact primitives, % graph fixtures and % deep lifetime comparisons passed.\n", sources.count, sources.count * 3);
}

Mode :: enum {
	FRESH;
	RESIDENT;
	AST_RELOAD;
}

Entry :: struct {
	filename: string;
	artifact: string;
	current: *Owned_Snapshot;
	digest: u64;
}

Ledger :: struct {
	delegate: Allocator;
	allocations: Table(*void, s64);
	live: s64;
	peak: s64;
	requests: s64;
}

tracking_allocator :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, data: *void) -> *void {
	ledger := data.(*Ledger);
	result := ledger.delegate.proc(mode, size, old_size, old_memory, ledger.delegate.data);
	push_allocator(ledger.delegate);

	if (mode == .FREE || mode == .RESIZE && result) && old_memory {
		found, bytes := table_remove(*ledger.allocations, old_memory);
		assert(found);
		ledger.live -= bytes;
	}

	if (mode == .ALLOCATE || mode == .RESIZE) && result {
		table_add(*ledger.allocations, result, size);
		ledger.live += size;
		ledger.peak = Max(ledger.peak, ledger.live);
		ledger.requests += 1;
	}

	assert(ledger.live >= 0);
	return result;
}

profile_project :: (manifest: string, prefix: string) {
	filenames := read_source(manifest);
	defer free(filenames);

	paths := split(filenames, "\n");
	defer free(paths.data);

	output: String_Builder;
	print(*output, "mode\tphase\tsnapshots\tbacking_bytes\tpeak_bytes\trequests\n");
	for mode: Mode.[.FRESH, .AST_RELOAD] {
		ledger := Ledger.{delegate = context.allocator};
		owned: [66]*Owned_Snapshot;
		count: s64;

		for filename: paths {
			if !filename.count {
				continue;
			}


			assert(count < 64);
			text: string;
			if mode == .FRESH {
				text = read_source(filename);
			} else {
				ok: bool;
				text, ok = read_entire_file(tprint("%.%.ast", prefix, count));
				assert(ok);
			}

			{
				push_allocator(.{proc = tracking_allocator, data = *ledger});
				owned[count] = ifx mode == .FRESH
					then parse_owned(text, filename)
					else decode_snapshot(text);
			}

			free(text);
			count += 1;
		}

		assert(!!count);
		print(*output, "%\tresident\t%\t%\t%\t%\n", mode, count, ledger.live, ledger.peak, ledger.requests);

		for extra: 0..1 {
			if mode == .FRESH {
				push_allocator(.{proc = tracking_allocator, data = *ledger});
				owned[count + extra] = parse_owned(owned[0].parsed.source, owned[0].parsed.fully_pathed_filename);
			} else {
				text, ok := read_entire_file(tprint("%.0.ast", prefix));
				assert(ok);
				{
					push_allocator(.{proc = tracking_allocator, data = *ledger});
					owned[count + extra] = decode_snapshot(text);
				}

				free(text);
			}
		}

		print(*output, "%\ttwo_extra\t%\t%\t%\t%\n", mode, count + 2, ledger.live, ledger.peak, ledger.requests);

		{
			push_allocator(.{proc = tracking_allocator, data = *ledger});
			for 0..count + 1 {
				release_owned(owned[it]);
			}
		}

		assert(!ledger.live && !ledger.allocations.count);
		print(*output, "%\treleased\t0\t%\t%\t%\n", mode, ledger.live, ledger.peak, ledger.requests);
		table_reset(*ledger.allocations);
	}

	text := builder_to_string(*output);
	assert(write_entire_file(tprint("%.memory.tsv", prefix), text));
	free(text);

	print("E12 graph memory: fresh/decoded worlds and two extra snapshots released all tracked backing.\n");
}

Measurement :: struct {
	elapsed: s64;
	read: s64;
	hash: s64;
	decode: s64;
	parse: s64;
	cleanup: s64;
	source_bytes: s64;
	artifact_bytes: s64;
	parses: s64;
	hits: s64;
	loads: s64;
	tokens: s64;
	diagnostics: s64;
}

elapsed_ns :: (start: Apollo_Time) -> s64 {
	value, ok := to_nanoseconds(current_time_monotonic() - start);
	assert(ok && value >= 0);
	return value;
}

read_source :: (filename: string) -> string {
	text, ok := read_entire_file(filename);
	assert(ok && text.count <= 524288);
	return text;
}

measure :: (entries: []Entry, mode: Mode) -> Measurement {
	result: Measurement;
	start := current_time_monotonic();

	for entry: entries {
		phase := current_time_monotonic();
		source := read_source(entry.filename);
		result.read += elapsed_ns(phase);
		result.source_bytes += source.count;
		phase = current_time_monotonic();
		assert(fnv1a_hash(source.data, source.count) == entry.digest && source == entry.current.parsed.source);
		result.hash += elapsed_ns(phase);
		snapshot := entry.current;

		if mode == {
			case .FRESH;
				phase = current_time_monotonic();
				snapshot = parse_owned(source, entry.filename);
				result.parse += elapsed_ns(phase);
				result.parses += 1;

			case .RESIDENT;
				result.hits += 1;

			case .AST_RELOAD;
				phase = current_time_monotonic();
				text, ok := read_entire_file(entry.artifact);
				assert(ok && text.count <= MAX_ARTIFACT_BYTES);
				result.read += elapsed_ns(phase);
				result.artifact_bytes += text.count;
				phase = current_time_monotonic();
				snapshot = decode_snapshot(text);
				assert(snapshot.parsed.source == source && snapshot.parsed.fully_pathed_filename == entry.filename);
				result.decode += elapsed_ns(phase);
				result.loads += 1;
				free(text);
		}

		result.tokens += snapshot.parsed.tokens.count;
		result.diagnostics += snapshot.parsed.diagnostics.count;
		phase = current_time_monotonic();

		if mode != .RESIDENT {
			release_owned(snapshot);
		}

		free(source);
		result.cleanup += elapsed_ns(phase);
	}

	result.elapsed = elapsed_ns(start);
	assert(result.parses + result.hits + result.loads == entries.count);
	return result;
}

run_project :: (manifest: string, prefix: string) {
	filenames := read_source(manifest);
	defer free(filenames);

	paths := split(filenames, "\n");
	defer free(paths.data);

	entries: [..]Entry;
	defer {
		for entry: entries {
			release_owned(entry.current);
			free(entry.artifact);
		}

		array_free(entries);
	}

	encode_ns: s64;
	artifact_bytes: s64;

	for filename: paths {
		if !filename.count {
			continue;
		}


		assert(entries.count < 64);
		source := read_source(filename);
		defer free(source);

		producer := parse_owned(source, filename);
		phase := current_time_monotonic();
		text := encode_snapshot(*producer.parsed);
		artifact := sprint("%.%.ast", prefix, entries.count);
		assert(write_entire_file(artifact, text));
		encode_ns += elapsed_ns(phase);
		artifact_bytes += text.count;
		producer.storage.overwrite_memory = true;
		producer.parsed.node_pool.overwrite_memory = true;
		release_owned(producer);
		decoded := decode_snapshot(text);
		memset(text.data, 0xDD, text.count);
		free(text);

		fresh := parse_owned(source, filename);
		check_snapshot(*decoded.parsed, *fresh.parsed);
		release_owned(decoded);
		array_add(*entries, .{filename = filename, artifact = artifact, current = fresh, digest = fnv1a_hash(source.data, source.count)});
		reset_temporary_storage();
	}

	assert(!!entries.count);
	output: String_Builder;
	print(*output, "mode\ttrial\torder\telapsed_ns\tread_ns\thash_ns\tdecode_ns\tparse_ns\tcleanup_ns\tsource_bytes\tartifact_bytes\tparses\thits\tloads\ttokens\tdiagnostics\n");

	for trial: -2..20 {
		for order: 0..2 {
			mode := ((order + trial + 3) % 3).(Mode);
			result := measure(entries, mode);
			if trial >= 0 {
				print(
					*output,
					"%\t%\t%\t%\t%\t%\t%\t%\t%\t%\t%\t%\t%\t%\t%\t%\n",
					mode,
					trial,
					order,
					result.elapsed,
					result.read,
					result.hash,
					result.decode,
					result.parse,
					result.cleanup,
					result.source_bytes,
					result.artifact_bytes,
					result.parses,
					result.hits,
					result.loads,
					result.tokens,
					result.diagnostics
				);
			}

			reset_temporary_storage();
		}
	}

	text := builder_to_string(*output);
	assert(write_entire_file(tprint("%.timings.tsv", prefix), text));
	free(text);

	assert(write_entire_file(tprint("%.setup.tsv", prefix), tprint("files\tencode_write_ns\tartifact_bytes\tdeep_oracles\tschema_high\tschema_low\n%\t%\t%\t%\t%\t%\n", entries.count, encode_ns, artifact_bytes, entries.count, SCHEMA_DIGEST >> 32, SCHEMA_DIGEST & 0xFFFFFFFF)));
	print("E12 graph reload: % files; % AST text bytes; % deep teardown oracles and 63 timed requests passed.\n", entries.count, artifact_bytes, entries.count);
}

main :: () {
	defer reset_temporary_storage();

	arguments := get_command_line_arguments();
	assert(arguments.count == 1 || arguments.count == 3 || arguments.count == 4, "Usage: experiment_snapshot_codec [MANIFEST OUTPUT_PREFIX [profile] | verify SOURCE ARTIFACT]");

	if arguments.count == 4 {
		if arguments[1] == "verify" {
			print("E12_DECODE_PROBE\n");
			text, ok := read_entire_file(arguments[3]);
			assert(ok);
			defer free(text);

			source := read_source(arguments[2]);
			defer free(source);

			snapshot := decode_snapshot(text);
			defer release_owned(snapshot);

			assert(snapshot.parsed.source == source && snapshot.parsed.fully_pathed_filename == arguments[2]);
			fresh := parse_owned(source, arguments[2]);
			defer release_owned(fresh);

			check_snapshot(*snapshot.parsed, *fresh.parsed);
			print("E12_DECODE_PROBE_PASS\n");
		} else {
			assert(arguments[3] == "profile");
			profile_project(arguments[1], arguments[2]);
		}

		return;
	}


	if arguments.count == 1 {
		self_tests();
		return;
	}


	run_project(arguments[1], arguments[2]);
}
