#import "Basic";
#import "Compiler";
#import "File";
#import "File_Utilities";
#import "Jai_Parser"(ENABLE_TRIVIA = true);
#import "Pool";
#import "Sort";
#import "String";
#import "Text_File_Handler";

OUTPUT_DIRECTORY :: ".build/text_artifacts";
COMPILER_VERSION :: #run compiler_get_version_info(null);

MAX_RECORDS :: 16;
MAX_STRING_BYTES :: 512;
MAX_FILE_BYTES :: 65536;
MAX_LINE_BYTES :: 2048;
MAX_LINES :: 80;
HEX_DIGITS :: "0123456789ABCDEF";

Decode_Status :: enum {
	COMPLETE;
	HEADER;
	SCHEMA;
	LIMIT;
	ROW;
	TRUNCATED;
	REFERENCE;
	SPAN;
	REVISION;
}

Node_Kind :: enum {
	DECLARATION;
	LITERAL;
	RECOVERY;
}

Query_Status :: enum {
	COMPLETE;
	MISSING;
	AMBIGUOUS;
	UNSUPPORTED;
	FAILED;
}

Node_Record :: struct {
	id: s64;
	kind: Node_Kind;
	parent: s64;
	begin: s64;
	end: s64;
	text: string;
}

Query_Record :: struct {
	id: s64;
	node: s64;
	status: Query_Status;
	revision: u64;
	signed_value: s64;
	unsigned_value: u64;
	float_value: float64;
	text: string;
}

Diagnostic_Record :: struct {
	id: s64;
	node: s64;
	severity: s64;
	begin: s64;
	end: s64;
	message: string;
}

Dependency_Record :: struct {
	parent: s64;
	target: s64;
	artifact: u64;
	checked_parent_revision: u64;
	observed_dependency_revision: u64;
}

Artifact :: struct {
	identity: u64;
	world: u64;
	source: string;
	nodes: [MAX_RECORDS]Node_Record;
	queries: [MAX_RECORDS]Query_Record;
	diagnostics: [MAX_RECORDS]Diagnostic_Record;
	dependencies: [MAX_RECORDS]Dependency_Record;
	node_count: s64;
	query_count: s64;
	diagnostic_count: s64;
	dependency_count: s64;
}

float_bits :: (value: float64) -> u64 {
	return (*value).(*u64).*;
}

write_hex :: (builder: *String_Builder, value: u64) {
	bytes: [16]u8;
	for 0..15 {
		bytes[it] = HEX_DIGITS[((value >> ((15 - it) * 4)) & 0xF).(s64)];
	}

	append(builder, string.{count = bytes.count, data = bytes.data});
}

write_blob :: (builder: *String_Builder, value: string) {
	assert(value.count <= MAX_STRING_BYTES);
	print(builder, "% ", value.count);
	if !value.count {
		append(builder, "-");
		return;
	}


	bytes: [MAX_STRING_BYTES * 2]u8;
	for byte: value {
		bytes[it_index * 2] = HEX_DIGITS[(byte >> 4).(s64)];
		bytes[it_index * 2 + 1] = HEX_DIGITS[(byte & 0xF).(s64)];
	}

	append(builder, string.{count = value.count * 2, data = bytes.data});
}

encode :: (artifact: *Artifact) -> string {
	builder: String_Builder;
	append(*builder, "[1]\nartifact ");
	write_hex(*builder, artifact.identity);
	append(*builder, " ");
	write_hex(*builder, artifact.world);
	append(*builder, "\nsource ");
	write_blob(*builder, artifact.source);
	append(*builder, "\n");

	for 0..artifact.node_count - 1 {
		node := artifact.nodes[it];
		print(*builder, "node % % % % % ", node.id, node.kind.(s64), node.parent, node.begin, node.end);
		write_blob(*builder, node.text);
		append(*builder, "\n");
	}

	for 0..artifact.query_count - 1 {
		query := artifact.queries[it];
		print(*builder, "query % % % ", query.id, query.node, query.status.(s64));

		for value: u64.[query.revision, (*query.signed_value).(*u64).*, query.unsigned_value, float_bits(query.float_value)] {
			write_hex(*builder, value);
			append(*builder, " ");
		}

		write_blob(*builder, query.text);
		append(*builder, "\n");
	}

	for 0..artifact.diagnostic_count - 1 {
		diagnostic := artifact.diagnostics[it];
		print(*builder, "diagnostic % % % % % ", diagnostic.id, diagnostic.node, diagnostic.severity, diagnostic.begin, diagnostic.end);
		write_blob(*builder, diagnostic.message);
		append(*builder, "\n");
	}

	for 0..artifact.dependency_count - 1 {
		dependency := artifact.dependencies[it];
		print(*builder, "dependency % % ", dependency.parent, dependency.target);

		for value: u64.[dependency.artifact, dependency.checked_parent_revision, dependency.observed_dependency_revision] {
			write_hex(*builder, value);
			append(*builder, " ");
		}

		append(*builder, "\n");
	}

	print(*builder, "end % % % %\n", artifact.node_count, artifact.query_count, artifact.diagnostic_count, artifact.dependency_count);
	return builder_to_string(*builder);
}

take_token :: (cursor: *string) -> string {
	token, rest := break_by_spaces(cursor.*);
	cursor.* = rest;
	return token;
}

read_decimal :: (cursor: *string, value: *s64) -> bool {
	token := take_token(cursor);
	if !token.count || token.count > 9 {
		return false;
	}


	for byte: token {
		if byte < #char "0" || byte > #char "9" {
			return false;
		}
	}

	parsed, ok, rest := string_to_int(token);
	value.* = parsed;
	return ok && !rest.count;
}

hex_digit :: (byte: u8) -> (u64, bool) {
	if byte >= #char "0" && byte <= #char "9" {
		return (byte - #char "0").(u64), true;
	}


	valid := (byte >= #char "A" && byte <= #char "F");
	value := ifx valid then (byte - #char "A" + 10).(u64);
	return value, valid;
}

read_hex :: (cursor: *string, value: *u64) -> bool {
	token := take_token(cursor);
	if token.count != 16 {
		return false;
	}


	result: u64;
	for byte: token {
		digit, ok := hex_digit(byte);
		if !ok {
			return false;
		}


		result = (result << 4) | digit;
	}

	value.* = result;
	return true;
}

read_blob :: (cursor: *string, value: *string) -> Decode_Status {
	count: s64;
	if !read_decimal(cursor, *count) {
		return .ROW;
	}


	if count > MAX_STRING_BYTES {
		return .LIMIT;
	}


	token := take_token(cursor);
	if !count {
		return ifx token == "-"
			then .COMPLETE
			else .ROW;
	}


	if token.count != count * 2 {
		return .ROW;
	}


	result := string.{count = count, data = alloc(count)};
	for 0..count - 1 {
		high, high_ok := hex_digit(token[it * 2]);
		low, low_ok := hex_digit(token[it * 2 + 1]);
		if !high_ok || !low_ok {
			return .ROW;
		}


		result[it] = ((high << 4) | low).(u8);
	}

	value.* = result;
	return .COMPLETE;
}

validate :: (artifact: *Artifact) -> Decode_Status {
	if !artifact.identity || !artifact.world {
		return .REFERENCE;
	}


	for 0..artifact.node_count - 1 {
		node := artifact.nodes[it];
		if node.id != it + 1 || node.parent < 0 || node.parent >= node.id {
			return .REFERENCE;
		}


		if node.begin > node.end || node.end > artifact.source.count {
			return .SPAN;
		}
	}

	for 0..artifact.query_count - 1 {
		query := artifact.queries[it];
		if query.id != it + 1 || query.node < 1 || query.node > artifact.node_count {
			return .REFERENCE;
		}


		if !query.revision {
			return .REVISION;
		}
	}

	for 0..artifact.diagnostic_count - 1 {
		diagnostic := artifact.diagnostics[it];
		if diagnostic.id != it + 1 || diagnostic.node < 1 || diagnostic.node > artifact.node_count {
			return .REFERENCE;
		}


		if diagnostic.begin > diagnostic.end || diagnostic.end > artifact.source.count {
			return .SPAN;
		}
	}

	for 0..artifact.dependency_count - 1 {
		dependency := artifact.dependencies[it];
		if (dependency.artifact != artifact.identity
			|| dependency.parent < 1 || dependency.parent > artifact.query_count
			|| dependency.target < 1 || dependency.target > artifact.query_count
		) {
			return .REFERENCE;
		}


		if (dependency.checked_parent_revision != artifact.queries[dependency.parent - 1].revision
			|| dependency.observed_dependency_revision != artifact.queries[dependency.target - 1].revision
		) {
			return .REVISION;
		}
	}

	return .COMPLETE;
}

decode :: (data: string, destination: *Artifact) -> Decode_Status {
	destination.* = .{};
	if data.count > MAX_FILE_BYTES {
		return .LIMIT;
	}


	if !data.count || data[data.count - 1] != 10 {
		return .TRUNCATED;
	}


	line_bytes: s64;
	lines: s64;
	for byte: data {
		line_bytes += 1;
		if line_bytes > MAX_LINE_BYTES {
			return .LIMIT;
		}


		if byte == 10 {
			lines += 1;
			line_bytes = 0;
		}
	}

	if lines > MAX_LINES {
		return .LIMIT;
	}


	header_cursor := data;
	header, found := consume_next_line(*header_cursor);
	if !found || header.count < 3 || header[0] != #char "[" || header[header.count - 1] != #char "]" {
		return .HEADER;
	}


	version_text := slice(header, 1, header.count - 2);
	version: s64;
	if !read_decimal(*version_text, *version) || version_text.count {
		return .HEADER;
	}


	if version != 1 {
		return .SCHEMA;
	}


	handler := Text_File_Handler.{strip_comments_from_ends_of_lines = false};
	defer deinit(*handler);

	start_from_memory(*handler, "E10", "memory.artifact", data);
	if handler.failed || handler.version != 1 {
		return .HEADER;
	}


	artifact: Artifact;
	have_identity := false;
	have_source := false;
	ended := false;

	while true {
		line, has_line := consume_next_line(*handler);
		if !has_line {
			break;
		}


		if ended {
			return .ROW;
		}


		kind := take_token(*line);
		status := Decode_Status.COMPLETE;
		if kind == {
			case "artifact";
				if have_identity || have_source || !read_hex(*line, *artifact.identity) || !read_hex(*line, *artifact.world) {
					return .ROW;
				}


				have_identity = true;

			case "source";
				if !have_identity || have_source {
					return .ROW;
				}


				status = read_blob(*line, *artifact.source);
				have_source = true;

			case "node";
				if !have_source || artifact.node_count >= MAX_RECORDS {
					return .LIMIT;
				}


				node: Node_Record;
				kind_value: s64;
				if (!read_decimal(*line, *node.id) || !read_decimal(*line, *kind_value)
					|| !read_decimal(*line, *node.parent) || !read_decimal(*line, *node.begin) || !read_decimal(*line, *node.end)
					|| kind_value >= (#run enum_names(Node_Kind).count)
				) {
					return .ROW;
				}


				node.kind = kind_value.(Node_Kind);
				status = read_blob(*line, *node.text);
				artifact.nodes[artifact.node_count] = node;
				artifact.node_count += 1;

			case "query";
				if !have_source || artifact.query_count >= MAX_RECORDS {
					return .LIMIT;
				}


				query: Query_Record;
				status_value: s64;
				signed_bits: u64;
				bits: u64;
				if (!read_decimal(*line, *query.id) || !read_decimal(*line, *query.node) || !read_decimal(*line, *status_value)
					|| status_value >= (#run enum_names(Query_Status).count)
					|| !read_hex(*line, *query.revision) || !read_hex(*line, *signed_bits)
					|| !read_hex(*line, *query.unsigned_value) || !read_hex(*line, *bits)
				) {
					return .ROW;
				}


				query.status = status_value.(Query_Status);
				query.signed_value = (*signed_bits).(*s64).*;
				query.float_value = (*bits).(*float64).*;
				status = read_blob(*line, *query.text);
				artifact.queries[artifact.query_count] = query;
				artifact.query_count += 1;

			case "diagnostic";
				if !have_source || artifact.diagnostic_count >= MAX_RECORDS {
					return .LIMIT;
				}


				diagnostic: Diagnostic_Record;
				if (!read_decimal(*line, *diagnostic.id) || !read_decimal(*line, *diagnostic.node)
					|| !read_decimal(*line, *diagnostic.severity) || diagnostic.severity > 1
					|| !read_decimal(*line, *diagnostic.begin) || !read_decimal(*line, *diagnostic.end)
				) {
					return .ROW;
				}


				status = read_blob(*line, *diagnostic.message);
				artifact.diagnostics[artifact.diagnostic_count] = diagnostic;
				artifact.diagnostic_count += 1;

			case "dependency";
				if !have_source || artifact.dependency_count >= MAX_RECORDS {
					return .LIMIT;
				}


				dependency: Dependency_Record;
				if (!read_decimal(*line, *dependency.parent) || !read_decimal(*line, *dependency.target)
					|| !read_hex(*line, *dependency.artifact) || !read_hex(*line, *dependency.checked_parent_revision)
					|| !read_hex(*line, *dependency.observed_dependency_revision)
				) {
					return .ROW;
				}


				artifact.dependencies[artifact.dependency_count] = dependency;
				artifact.dependency_count += 1;

			case "end";
				if !have_source {
					return .ROW;
				}


				for expected: s64.[artifact.node_count, artifact.query_count, artifact.diagnostic_count, artifact.dependency_count] {
					count: s64;
					if !read_decimal(*line, *count) || count != expected {
						return .ROW;
					}
				}

				ended = true;

			case;
				return .ROW;
		}

		if status != .COMPLETE {
			return status;
		}


		if line.count {
			return .ROW;
		}
	}

	if !ended {
		return .TRUNCATED;
	}


	status := validate(*artifact);
	if status == .COMPLETE {
		destination.* = artifact;
	}

	return status;
}

probe_handler :: () {
	source := copy_string("[1]\ntext 6 2023200D0AFF\nend\n");
	defer free(source);

	handler := Text_File_Handler.{strip_comments_from_ends_of_lines = false};
	defer deinit(*handler);

	start_from_memory(*handler, "E10", "memory.artifact", source);
	assert(!handler.failed && handler.version == 1);
	line, found := consume_next_line(*handler);
	assert(found && line == "text 6 2023200D0AFF");
	line, found = consume_next_line(*handler);
	assert(found && line == "end");
	line, found = consume_next_line(*handler);
	assert(!found);
	print("E10 Text_File_Handler API probe passed.\n");
}

Fixture_Kind :: enum {
	EMPTY;
	STRINGS;
	NUMBERS;
	RECOVERY;
	LIMITS;
}

FLOAT_PATTERNS :: u64.[
	0x0000000000000000,
	0x8000000000000000,
	0x3FF0000000000000,
	0x3FF199999999999A,
	0x0000000000000001,
	0x7FEFFFFFFFFFFFFF,
	0x7FF0000000000000,
	0xFFF0000000000000,
	0x7FF8000000001234,
	0x7FF0000000000001
];

fixture_text :: (index: s64, maximum: bool) -> string {
	if maximum {
		value := string.{count = MAX_STRING_BYTES, data = alloc(MAX_STRING_BYTES)};
		memset(value.data, #char "X", value.count);
		return value;
	}


	if index % 8 == {
		case 0;
			return "";

		case 1;
			return copy_string(" \t leading and trailing \t ");

		case 2;
			return copy_string("# comments [1] end 0 0 0 0");

		case 3;
			return copy_string("quotes \" and backslash \\ and CRLF\r\n");

		case 4;
			bytes := u8.[65, 0, 66, 10, 13, 9];
			return copy_string(string.{count = bytes.count, data = bytes.data});

		case 5;
			bytes := u8.[0xC3, 0xA9, 0xE6, 0xBC, 0xA2, 0xF0, 0x9F, 0x98, 0x80];
			return copy_string(string.{count = bytes.count, data = bytes.data});

		case 6;
			value := string.{count = 256, data = alloc(256)};
			for 0..255 {
				value[it] = it.(u8);
			}

			return value;

		case;
			return fixture_text(index, true);
	}
}

make_fixture :: (kind: Fixture_Kind) -> Artifact {
	artifact := Artifact.{identity = 0xFFFFFFFFFFFFFFFF, world = 0x8000000000000001};
	count: s64;
	if kind == {
		case .EMPTY;
			count = 0;

		case .STRINGS;
			count = 8;

		case .NUMBERS;
			count = FLOAT_PATTERNS.count;

		case .RECOVERY;
			count = 3;

		case .LIMITS;
			count = MAX_RECORDS;
	}

	builder: String_Builder;
	for 0..count - 1 {
		print(*builder, "value_% :: %;\n", it, it);
	}

	artifact.source = builder_to_string(*builder);
	if kind == .RECOVERY {
		artifact.source = copy_string("incomplete :: (\n");
	}

	signed_values := s64.[-0x8000000000000000, 0x7FFFFFFFFFFFFFFF, -1, 0, 1, -9007199254740993, 9007199254740993, 42];
	unsigned_values := u64.[0, 1, 0xFFFFFFFFFFFFFFFF, 0x8000000000000000, 9007199254740993, 42];
	for 0..count - 1 {
		bits := FLOAT_PATTERNS[it % FLOAT_PATTERNS.count];
		text := ifx kind == .NUMBERS then "" else fixture_text(it, kind == .LIMITS);
		artifact.nodes[it] = .{
			id = it + 1,
			kind = (ifx kind == .RECOVERY then Node_Kind.RECOVERY else Node_Kind.DECLARATION),
			parent = it,
			end = artifact.source.count,
			text = text
		};

		artifact.queries[it] = .{
			id = it + 1,
			node = it + 1,
			status = (it % (#run enum_names(Query_Status).count)).(Query_Status),
			revision = (it + 1).(u64),
			signed_value = signed_values[it % signed_values.count],
			unsigned_value = unsigned_values[it % unsigned_values.count],
			float_value = (*bits).(*float64).*,
			text = copy_string(text)
		};

		artifact.diagnostics[it] = .{
			id = it + 1,
			node = it + 1,
			severity = it % 2,
			end = artifact.source.count,
			message = (ifx kind == .LIMITS then fixture_text(it, true) else copy_string("unexpected token # note\r\n\t"))
		};

		artifact.dependencies[it] = .{
			parent = it + 1,
			target = (it + 1) % count + 1,
			artifact = artifact.identity,
			checked_parent_revision = (it + 1).(u64),
			observed_dependency_revision = ((it + 1) % count + 1).(u64)
		};
	}

	artifact.node_count = count;
	artifact.query_count = count;
	artifact.diagnostic_count = count;
	artifact.dependency_count = count;
	return artifact;
}

operator == :: (left: Node_Record, right: Node_Record) -> bool {
	return left.id == right.id && left.kind == right.kind && left.parent == right.parent
		&& left.begin == right.begin && left.end == right.end && left.text == right.text;
}

operator == :: (left: Query_Record, right: Query_Record) -> bool {
	return left.id == right.id && left.node == right.node && left.status == right.status && left.revision == right.revision
		&& left.signed_value == right.signed_value && left.unsigned_value == right.unsigned_value
		&& float_bits(left.float_value) == float_bits(right.float_value) && left.text == right.text;
}

operator == :: (left: Diagnostic_Record, right: Diagnostic_Record) -> bool {
	return left.id == right.id && left.node == right.node && left.severity == right.severity
		&& left.begin == right.begin && left.end == right.end && left.message == right.message;
}

operator == :: (left: Dependency_Record, right: Dependency_Record) -> bool {
	return left.parent == right.parent && left.target == right.target && left.artifact == right.artifact
		&& left.checked_parent_revision == right.checked_parent_revision
		&& left.observed_dependency_revision == right.observed_dependency_revision;
}

compare_artifacts :: (actual: *Artifact, expected: *Artifact) -> s64 {
	assert(actual.identity == expected.identity && actual.world == expected.world && actual.source == expected.source);
	assert(actual.node_count == expected.node_count && actual.query_count == expected.query_count);
	assert(actual.diagnostic_count == expected.diagnostic_count && actual.dependency_count == expected.dependency_count);
	checks: s64 = 1;
	for 0..actual.node_count - 1 {
		assert(actual.nodes[it] == expected.nodes[it]);
		checks += 1;
	}

	for 0..actual.query_count - 1 {
		assert(actual.queries[it] == expected.queries[it]);
		checks += 1;
	}

	for 0..actual.diagnostic_count - 1 {
		assert(actual.diagnostics[it] == expected.diagnostics[it]);
		checks += 1;
	}

	for 0..actual.dependency_count - 1 {
		assert(actual.dependencies[it] == expected.dependencies[it]);
		checks += 1;
	}

	return checks;
}

Mutation :: enum {
	NONE;
	ZERO_IDENTITY;
	ZERO_WORLD;
	DUPLICATE_NODE;
	PARENT_SELF;
	NODE_SPAN;
	QUERY_NODE;
	QUERY_REVISION;
	DIAGNOSTIC_NODE;
	DIAGNOSTIC_SPAN;
	DIAGNOSTIC_SEVERITY;
	DEPENDENCY_PARENT;
	DEPENDENCY_TARGET;
	DEPENDENCY_ARTIFACT;
	PARENT_REVISION;
	TARGET_REVISION;
	NODE_KIND;
	QUERY_STATUS;
}

mutate :: (artifact: *Artifact, mutation: Mutation) -> Decode_Status {
	if mutation == {
		case .NONE;
			return .COMPLETE;

		case .ZERO_IDENTITY;
			artifact.identity = 0;

		case .ZERO_WORLD;
			artifact.world = 0;

		case .DUPLICATE_NODE;
			artifact.nodes[1].id = 1;

		case .PARENT_SELF;
			artifact.nodes[0].parent = 1;

		case .NODE_SPAN;
			artifact.nodes[0].end = artifact.source.count + 1;
			return .SPAN;

		case .QUERY_NODE;
			artifact.queries[0].node = 0;

		case .QUERY_REVISION;
			artifact.queries[0].revision = 0;
			return .REVISION;

		case .DIAGNOSTIC_NODE;
			artifact.diagnostics[0].node = MAX_RECORDS + 1;

		case .DIAGNOSTIC_SPAN;
			artifact.diagnostics[0].begin = 1;
			artifact.diagnostics[0].end = 0;
			return .SPAN;

		case .DIAGNOSTIC_SEVERITY;
			artifact.diagnostics[0].severity = 2;
			return .ROW;

		case .DEPENDENCY_PARENT;
			artifact.dependencies[0].parent = 0;

		case .DEPENDENCY_TARGET;
			artifact.dependencies[0].target = MAX_RECORDS + 1;

		case .DEPENDENCY_ARTIFACT;
			artifact.dependencies[0].artifact = 1;

		case .PARENT_REVISION;
			artifact.dependencies[0].checked_parent_revision = 0;
			return .REVISION;

		case .TARGET_REVISION;
			artifact.dependencies[0].observed_dependency_revision = 0;
			return .REVISION;

		case .NODE_KIND;
			artifact.nodes[0].kind = xx 99;
			return .ROW;

		case .QUERY_STATUS;
			artifact.queries[0].status = xx 99;
			return .ROW;
	}

	return .REFERENCE;
}

produce_fixture :: (kind: Fixture_Kind, mutation: Mutation = .NONE) -> string {
	upstream := context.allocator;
	storage := Pool.{overwrite_memory = true};
	set_allocators(*storage, upstream);
	defer release(*storage);

	encoded: string;
	{
		push_allocator(Allocator.{proc = pool_allocator_proc, data = *storage});
		artifact := make_fixture(kind);
		mutate(*artifact, mutation);
		text := encode(*artifact);
		{
			push_allocator(upstream);
			encoded = copy_string(text);
		}
	}

	return encoded;
}

decode_owned :: (data: string, destination: *Artifact, storage: *Pool) -> Decode_Status {
	push_allocator(Allocator.{proc = pool_allocator_proc, data = storage});
	return decode(data, destination);
}

run_roundtrip :: (kind: Fixture_Kind) -> s64 {
	encoded := produce_fixture(kind);
	assert(write_entire_file(tprint("%/%.artifact", OUTPUT_DIRECTORY, kind), encoded));
	storage := Pool.{overwrite_memory = true};
	set_allocators(*storage);
	defer release(*storage);

	decoded: Artifact;
	assert(decode_owned(encoded, *decoded, *storage) == .COMPLETE);
	memset(encoded.data, 0xDD, encoded.count);
	free(encoded);
	checks: s64;
	oracle := Pool.{overwrite_memory = true};
	set_allocators(*oracle);
	{
		push_allocator(Allocator.{proc = pool_allocator_proc, data = *oracle});
		expected := make_fixture(kind);
		checks += compare_artifacts(*decoded, *expected);
	}

	release(*oracle);
	canonical := encode(*decoded);
	defer free(canonical);

	file_data, ok := read_entire_file(tprint("%/%.artifact", OUTPUT_DIRECTORY, kind));
	assert(ok && file_data == canonical);
	defer free(file_data);

	print("E10 %: % exact record comparisons after producer/input teardown.\n", kind, checks);
	return checks;
}

MINIMAL_PREFIX :: "[1]\nartifact 0000000000000001 0000000000000001\nsource 0 -\n";

Invalid_Case :: struct {
	name: string;
	data: string;
	expected: Decode_Status;
}

check_rejected :: (data: string, expected: Decode_Status, storage: *Pool) -> Decode_Status {
	artifact := Artifact.{identity = 42, node_count = 1};
	status := decode_owned(data, *artifact, storage);
	assert(status != .COMPLETE && status == expected, "E10 rejection mismatch: expected %, got %", expected, status);
	assert(!artifact.identity && !artifact.world && !artifact.source.count);
	assert(!artifact.node_count && !artifact.query_count && !artifact.diagnostic_count && !artifact.dependency_count);
	reset(storage);
	return status;
}

run_invalid_case :: (test: Invalid_Case, summary: *String_Builder) {
	storage := Pool.{overwrite_memory = true};
	set_allocators(*storage);
	defer release(*storage);

	status := check_rejected(test.data, test.expected, *storage);
	assert(test.data.count && test.data[test.data.count - 1] == 10);
	assert(write_entire_file(tprint("%/invalid_%.artifact", OUTPUT_DIRECTORY, test.name), test.data));
	print(summary, "%\t%\t%\t%\n", test.name, test.data.count, test.expected, status);
}

run_rejections :: (summary: *String_Builder, prefixes: *String_Builder) -> (s64, s64) {
	cases := Invalid_Case.[
		.{name = "HEADER",				data = "[1]garbage\n",														expected = .HEADER},
		.{name = "SCHEMA",				data = "[2]\n",																expected = .SCHEMA},
		.{name = "VERSION_OVERFLOW",	data = "[999999999999999999999]\n",											expected = .HEADER},
		.{name = "MISSING_END",			data = MINIMAL_PREFIX,														expected = .TRUNCATED},
		.{name = "UNKNOWN_ROW",			data = tprint("%bogus\n", MINIMAL_PREFIX),									expected = .ROW},
		.{name = "EXTRA_FIELD",			data = tprint("%end 0 0 0 0 extra\n", MINIMAL_PREFIX),						expected = .ROW},
		.{name = "TRAILING_ROW",		data = tprint("%end 0 0 0 0\njunk\n", MINIMAL_PREFIX),						expected = .ROW},
		.{name = "BAD_COUNTS",			data = tprint("%end 1 0 0 0\n", MINIMAL_PREFIX),							expected = .ROW},
		.{name = "DUPLICATE_SOURCE",	data = tprint("%source 0 -\n", MINIMAL_PREFIX),								expected = .ROW},
		.{name = "MISSING_ARTIFACT",	data = "[1]\nsource 0 -\n",													expected = .ROW},
		.{name = "INVALID_HEX",			data = "[1]\nartifact FFFFFFFFFFFFFFFG 0000000000000001\n",					expected = .ROW},
		.{name = "SHORT_HEX",			data = "[1]\nartifact 1234 0000000000000001\n",								expected = .ROW},
		.{name = "NEGATIVE_ID",			data = tprint("%node -1 0 0 0 0 0 -\n",	MINIMAL_PREFIX),					expected = .ROW},
		.{name = "DECIMAL_OVERFLOW",	data = tprint("%node 999999999999999999999 0 0 0 0 0 -\n", MINIMAL_PREFIX),	expected = .ROW},
		.{name = "BLOB_LENGTH",			data = tprint("%node 1 0 0 0 0 2 41\n", MINIMAL_PREFIX),					expected = .ROW},
		.{name = "BLOB_HEX",			data = tprint("%node 1 0 0 0 0 1 GG\n", MINIMAL_PREFIX),					expected = .ROW},
		.{name = "STRING_LIMIT",		data = tprint("%node 1 0 0 0 0 513 -\n", MINIMAL_PREFIX),					expected = .LIMIT}
	];

	count: s64;
	for test: cases {
		run_invalid_case(test, summary);
		count += 1;
	}

	for mutation: enum_values_as_enum(Mutation) {
		if mutation == .NONE {
			continue;
		}


		data := produce_fixture(.STRINGS, mutation);
		defer free(data);

		artifact: Artifact;
		expected := mutate(*artifact, mutation);
		run_invalid_case(.{name = tprint("%", mutation), data = data, expected = expected}, summary);
		count += 1;
	}

	for category: string.["node", "query", "diagnostic", "dependency"] {
		builder: String_Builder;
		append(*builder, MINIMAL_PREFIX);
		for 0..MAX_RECORDS {
			if category == {
				case "node";
					print(*builder, "node % 0 0 0 0 0 -\n", it + 1);

				case "query";
					print(*builder, "query % 1 0 0000000000000001 0000000000000000 0000000000000000 0000000000000000 0 -\n", it + 1);

				case "diagnostic";
					print(*builder, "diagnostic % 1 0 0 0 0 -\n", it + 1);

				case "dependency";
					append(*builder, "dependency 1 1 0000000000000001 0000000000000001 0000000000000001\n");
			}
		}

		data := builder_to_string(*builder);
		defer free(data);

		run_invalid_case(.{name = tprint("%_LIMIT", category), data = data, expected = .LIMIT}, summary);
		count += 1;
	}

	for limit: string.["FILE_LIMIT", "LINE_LIMIT", "LINE_COUNT_LIMIT"] {
		builder: String_Builder;
		append(*builder, "[1]\n");
		if limit == {
			case "FILE_LIMIT";
				for 0..MAX_FILE_BYTES {
					append(*builder, "A");
				}

			case "LINE_LIMIT";
				for 0..MAX_LINE_BYTES {
					append(*builder, "A");
				}

			case "LINE_COUNT_LIMIT";
				for 0..MAX_LINES {
					append(*builder, "\n");
				}
		}

		append(*builder, "\n");
		data := builder_to_string(*builder);
		defer free(data);

		run_invalid_case(.{name = limit, data = data, expected = .LIMIT}, summary);
		count += 1;
	}

	data := produce_fixture(.NUMBERS);
	defer free(data);

	assert(write_entire_file(tprint("%/truncation_source.artifact", OUTPUT_DIRECTORY), data));
	storage := Pool.{overwrite_memory = true};
	set_allocators(*storage);
	defer release(*storage);

	for 0..data.count - 1 {
		prefix := string.{count = it, data = data.data};
		artifact := Artifact.{identity = 42};
		status := decode_owned(prefix, *artifact, *storage);
		assert(status != .COMPLETE && !artifact.identity && !artifact.node_count && !artifact.source.count);
		print(prefixes, "%\t%\n", it, status);
		reset(*storage);
	}

	return count, data.count;
}

write_output :: (name: string, builder: *String_Builder) {
	text := builder_to_string(builder);
	defer free(text);

	assert(write_entire_file(tprint("%/%", OUTPUT_DIRECTORY, name), text));
}

Timing_Mode :: enum {
	DECODE;
	PARSE;
}

time_batch :: (mode: Timing_Mode, encoded: string, source: string, iterations: s64) -> s64 {
	start := current_time_monotonic();
	for 0..iterations - 1 {
		if mode == .DECODE {
			storage: Pool;
			set_allocators(*storage);
			artifact: Artifact;
			status := decode_owned(encoded, *artifact, *storage);
			assert(status == .COMPLETE && artifact.source.count == source.count);
			release(*storage);
		} else {
			parsed := parse_file(source);
			assert(parsed.status == .COMPLETE && !parsed.diagnostics.count);
			release_parser_tree(*parsed);
		}
	}

	elapsed, ok := to_nanoseconds(current_time_monotonic() - start);
	assert(ok);
	return elapsed;
}

run_timings :: (raw: *String_Builder, summary: *String_Builder) {
	BATCHES :: 21;
	ITERATIONS :: 64;
	frequency :: 1000000000;
	print(raw, "fixture\tmode\tbatch\titerations\tartifact_bytes\tsource_bytes\tticks\tfrequency\n");
	print(summary, "fixture\tmode\tmedian_us\tp95_batch_us\n");
	for kind: Fixture_Kind.[.STRINGS, .NUMBERS, .LIMITS] {
		encoded := produce_fixture(kind);
		defer free(encoded);

		storage: Pool;
		set_allocators(*storage);
		defer release(*storage);

		artifact: Artifact;
		assert(decode_owned(encoded, *artifact, *storage) == .COMPLETE);
		assert(write_entire_file(tprint("%/%.jai", OUTPUT_DIRECTORY, kind), artifact.source));
		for mode: enum_values_as_enum(Timing_Mode) {
			time_batch(mode, encoded, artifact.source, 16);
		}

		samples: [#run enum_names(Timing_Mode).count][BATCHES]s64;
		for batch: 0..BATCHES - 1 {
			for 0..(#run enum_names(Timing_Mode).count) - 1 {
				mode := ((it + batch) % (#run enum_names(Timing_Mode).count)).(Timing_Mode);
				ticks := time_batch(mode, encoded, artifact.source, ITERATIONS);
				samples[mode.(s64)][batch] = ticks;
				print(raw, "%\t%\t%\t%\t%\t%\t%\t%\n", kind, mode, batch, ITERATIONS, encoded.count, artifact.source.count, ticks, frequency);
			}
		}

		for mode: enum_values_as_enum(Timing_Mode) {
			values := samples[mode.(s64)];
			quick_sort(values, (value: s64) -> s64 { return value; });
			median := values[BATCHES / 2].(float64) * 1000000 / frequency.(float64) / ITERATIONS;
			p95 := values[(BATCHES * 95 + 99) / 100 - 1].(float64) * 1000000 / frequency.(float64) / ITERATIONS;
			print(summary, "%\t%\t%\t%\n", kind, mode, median, p95);
			print("E10 % %: median % us, p95 batch % us per operation.\n", kind, mode, median, p95);
		}
	}
}

main :: () {
	probe_handler();
	assert(make_directory_if_it_does_not_exist(".build"));
	assert(make_directory_if_it_does_not_exist(OUTPUT_DIRECTORY));
	defer reset_temporary_storage();

	checks: s64;
	rejections: String_Builder;
	prefixes: String_Builder;
	defer reset(*rejections);
	defer reset(*prefixes);

	print(*rejections, "case\tbytes\texpected\tactual\n");
	print(*prefixes, "bytes\tstatus\n");
	for kind: enum_values_as_enum(Fixture_Kind) {
		checks += run_roundtrip(kind);
	}

	invalid_count, prefix_count := run_rejections(*rejections, *prefixes);
	write_output("rejections.tsv", *rejections);
	write_output("truncations.tsv", *prefixes);
	print("E10: % record comparisons, % invalid cases, % rejected truncations.\n", checks, invalid_count, prefix_count);

	raw: String_Builder;
	summary: String_Builder;
	defer reset(*raw);
	defer reset(*summary);

	run_timings(*raw, *summary);
	write_output("timings.tsv", *raw);
	write_output("timing_summary.tsv", *summary);
	assert(write_entire_file(tprint("%/compiler_version.txt", OUTPUT_DIRECTORY), tprint("%\n", COMPILER_VERSION)));
}
