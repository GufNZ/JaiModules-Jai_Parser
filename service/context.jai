// Context registry (phase 3 step 5): the implemented schema tuple, the `jai-cache-syntax-context/1` descriptor and its admission, per CACHE_CONTRACTS.md "Syntax Context Registry and Adapter Bindings" and the milestone-2 `SchemaTuple` closure.
// Only the one tuple and producer this build implements are admitted; anything else rejects without a fallback.

SYNTAX_CONTEXT_SCHEMA :: "jai-cache-syntax-context/1";
PARSE_PROFILE :: "jai-cache-parse-profile/1";
DIAGNOSTIC_PROFILE :: "jai-cache-diagnostic-profile/1";

// What the two profile identifiers resolve to in the descriptor's `parse_profile` and `diagnostic_profile` fields.
GRAMMAR_PROFILE :: "jai-parser-grammar/1";
RECOVERY_POLICY :: "jai-parser-recovery/1";
MESSAGE_POLICY :: "jai-parser-messages/1";
PRESENTATION_LANGUAGE :: "en";

PRODUCER_NAMESPACE :: "jai-parser-service";

Schema_Tuple :: struct {
	token_tags: string;
	source_tokens: string;
	nodes: string;
	recovery: string;
	declaration_index: string;
	diagnostics: string;
	snapshot: string;
	authored_edges: string;
	syntax_adapter: string;
	parse_profile: string;
	diagnostic_profile: string;
}

operator == :: (a: Schema_Tuple, b: Schema_Tuple) -> bool {
	return a.token_tags == b.token_tags
		&& a.source_tokens == b.source_tokens
		&& a.nodes == b.nodes
		&& a.recovery == b.recovery
		&& a.declaration_index == b.declaration_index
		&& a.diagnostics == b.diagnostics
		&& a.snapshot == b.snapshot
		&& a.authored_edges == b.authored_edges
		&& a.syntax_adapter == b.syntax_adapter
		&& a.parse_profile == b.parse_profile
		&& a.diagnostic_profile == b.diagnostic_profile;
}

IMPLEMENTED_SCHEMA_TUPLE :: Schema_Tuple.{
	token_tags = TOKEN_TAGS_SCHEMA,
	source_tokens = SOURCE_TOKENS_SCHEMA,
	nodes = AUTHORED_NODES_SCHEMA,
	recovery = RECOVERY_SCHEMA,
	declaration_index = DECLARATION_INDEX_SCHEMA,
	diagnostics = SYNTAX_DIAGNOSTICS_SCHEMA,
	snapshot = SYNTAX_SNAPSHOT_SCHEMA,
	authored_edges = AUTHORED_EDGES_SCHEMA,
	syntax_adapter = SYNTAX_ADAPTER_SCHEMA,
	parse_profile = PARSE_PROFILE,
	diagnostic_profile = DIAGNOSTIC_PROFILE
};

// The `QueryKind` payloads this registry supplies, in registry order.
IMPLEMENTED_QUERY_KINDS :: string.["SYNTAX_SNAPSHOT", "SYNTAX_DIAGNOSTICS", "SYNTAX_DECLARATION_INDEX"];

// `V(SchemaTuple)`: a record of the eleven identifiers in field order.
schema_tuple_value :: (tuple: Schema_Tuple) -> bool, [] u8 {
	identifiers := string.[
		tuple.token_tags,
		tuple.source_tokens,
		tuple.nodes,
		tuple.recovery,
		tuple.declaration_index,
		tuple.diagnostics,
		tuple.snapshot,
		tuple.authored_edges,
		tuple.syntax_adapter,
		tuple.parse_profile,
		tuple.diagnostic_profile
	];
	fields: [11] [] u8;
	for identifiers {
		ok, value := v_ascii(it);
		if !ok {
			return false, .[];
		}


		fields[it_index] = value;
	}


	return true, v_record(tuple_schema(), ..fields);
}

tuple_schema :: () -> [] u8 {
	_, schema := v_ascii(interface_schema("SchemaTuple"));
	return schema;
}

// `K("syntax-configuration", [V(Sequence(SchemaTuple), set)])` over a duplicate-free set of implemented tuples, in canonical byte order.
configuration_id :: (tuples: [] Schema_Tuple) -> bool, [] u8 {
	if !tuples.count {
		return false, .[];
	}


	values := NewArray(tuples.count, [] u8,, temp);
	for tuples {
		if it != IMPLEMENTED_SCHEMA_TUPLE {
			return false, .[];
		}


		_, values[it_index] = schema_tuple_value(it);
	}


	for i: 1..values.count - 1 {
		j := i;
		while j > 0 && compare_canonical(values[j - 1], values[j]) > 0 {
			values[j - 1], values[j] = values[j], values[j - 1];
			j -= 1;
		}
	}

	for 1..values.count - 1 {
		if bytes_equal(values[it - 1], values[it]) {
			return false, .[];
		}
	}


	return true, make_key("syntax-configuration", v_sequence(tuple_schema(), ..values));
}

Path_Value :: struct {
	encoding: enum u8 {
		WINDOWS_UTF16LE;
		POSIX_BYTES;
	};
	code_units: [] u8;
}

// Exact UTF-16LE code units of a UTF-8 spelling; rejects invalid UTF-8, NUL and empty input.
windows_path_value :: (spelling: string) -> bool, Path_Value {
	if !spelling.count || !is_valid_utf8(xx spelling) {
		return false, .{};
	}


	units: [..] u8;
	i := 0;
	while i < spelling.count {
		lead := spelling[i];
		length := ifx lead < 0x80
			then 1
			else ifx lead < 0xE0
				then 2
				else ifx lead < 0xF0
					then 3
					else 4;
		code: u32 = ifx length == 1
			then lead.(u32)
			else ifx length == 2
				then (lead & 0x1F).(u32)
				else ifx length == 3
					then (lead & 0x0F).(u32)
					else (lead & 0x07).(u32);
		for 1..length - 1 {
			code = (code << 6) | (spelling[i + it] & 0x3F).(u32);
		}

		if !code {
			array_free(units);
			return false, .{};
		}


		if code >= 0x10000 {
			code -= 0x10000;
			append_utf16_unit(*units, 0xD800 + (code >> 10));
			append_utf16_unit(*units, 0xDC00 + (code & 0x3FF));
		} else {
			append_utf16_unit(*units, code);
		}

		i += length;
	}

	return true, .{encoding = .WINDOWS_UTF16LE, code_units = units};
}

posix_path_value :: (bytes: string) -> bool, Path_Value {
	if !bytes.count || find_index_from_left(bytes, 0) >= 0 {
		return false, .{};
	}


	return true, .{encoding = .POSIX_BYTES, code_units = xx copy_string(bytes)};
}

// `K("path", [encoding_tag, code_units])`.
path_key :: (path: Path_Value) -> [] u8 {
	tag := ifx path.encoding == .WINDOWS_UTF16LE
		then "WINDOWS_UTF16LE"
		else "POSIX_BYTES";
	return make_key("path", tag.([] u8), path.code_units);
}

Context_Paths :: struct {
	visible_filename: Path_Value;
	visible_directory: Path_Value;
	relative_base: Path_Value;
}

// The ten descriptor fields in schema order.
SYNTAX_CONTEXT_FIELDS :: string.[
	"producer",
	"syntax_schemas",
	"parser_parameters",
	"parse_profile",
	"diagnostic_profile",
	"visible_filename",
	"visible_directory",
	"relative_base",
	"resolver_binding",
	"semantic_extension"
];

// `K("syntax-context-descriptor", [K(field_name, values)...])` for this build's producer and the occurrence's paths.
syntax_context_descriptor :: (paths: Context_Paths) -> bool, [] u8 {
	if !valid_path(paths.visible_filename) || !valid_path(paths.visible_directory) || !valid_path(paths.relative_base) {
		return false, .[];
	}


	expected := expected_field_values();
	fields: [SYNTAX_CONTEXT_FIELDS.count] [] u8;
	fields[0] = make_key("producer", ..expected.producer);
	fields[1] = make_key("syntax_schemas", ..expected.syntax_schemas);
	fields[2] = make_key("parser_parameters", ..expected.parser_parameters);
	fields[3] = make_key("parse_profile", ..expected.parse_profile);
	fields[4] = make_key("diagnostic_profile", ..expected.diagnostic_profile);
	fields[5] = make_key("visible_filename", path_key(paths.visible_filename));
	fields[6] = make_key("visible_directory", path_key(paths.visible_directory));
	fields[7] = make_key("relative_base", path_key(paths.relative_base));
	fields[8] = make_key("resolver_binding", make_key("NO_RESOLUTION"));
	fields[9] = make_key("semantic_extension", make_key("UNSUPPORTED"));
	return true, make_key("syntax-context-descriptor", ..fields);
}

// `ContextID = K("context", [context_schema_identifier, canonical_context_descriptor])`.
context_id :: (descriptor: [] u8) -> [] u8 {
	return make_key("context", SYNTAX_CONTEXT_SCHEMA.([] u8), descriptor);
}

Context_Failure :: enum u8 {
	NONE;
	MALFORMED;
	FIELD_ORDER;
	UNSUPPORTED_PRODUCER;
	UNSUPPORTED_SCHEMAS;
	INVALID_BOOLEAN;
	UNSUPPORTED_PARAMETERS;
	UNSUPPORTED_PROFILE;
	INVALID_PATH;
	UNSUPPORTED_RESOLVER;
	UNSUPPORTED_SEMANTICS;
	IDENTITY_MISMATCH;
}

Admitted_Context :: struct {
	identity: [] u8;
	descriptor: [] u8;
	paths: Context_Paths;
}

// Parses and validates a `ContextRegistration` against this build, then recomputes its identity; the result owns copies of both byte strings.
admit_context :: (identity: [] u8, descriptor: [] u8) -> Context_Failure, Admitted_Context {
	ok, root := parse_key(descriptor, SYNTAX_CONTEXT_FIELDS.count,, temp);
	if !ok || root.tag.(string) != "syntax-context-descriptor" || root.fields.count != SYNTAX_CONTEXT_FIELDS.count {
		return .MALFORMED, .{};
	}


	expected := expected_field_values();
	result: Admitted_Context;
	path_slots := (*Path_Value).[*result.paths.visible_filename, *result.paths.visible_directory, *result.paths.relative_base];
	for name: SYNTAX_CONTEXT_FIELDS {
		field_ok, field := parse_key(root.fields[it_index], 8,, temp);
		if !field_ok {
			return .MALFORMED, .{};
		}


		if field.tag.(string) != name {
			return .FIELD_ORDER, .{};
		}


		values := field.fields;
		if name == {
			case "producer";
				if !values_equal(values, expected.producer) {
					return .UNSUPPORTED_PRODUCER, .{};
				}

			case "syntax_schemas";
				if !values_equal(values, expected.syntax_schemas) {
					return .UNSUPPORTED_SCHEMAS, .{};
				}

			case "parser_parameters";
				if values.count != expected.parser_parameters.count {
					return .MALFORMED, .{};
				}


				for values {
					if it.count != 1 || it[0] > 1 {
						return .INVALID_BOOLEAN, .{};
					}
				}

				if !values_equal(values, expected.parser_parameters) {
					return .UNSUPPORTED_PARAMETERS, .{};
				}

			case "parse_profile";
				if !values_equal(values, expected.parse_profile) {
					return .UNSUPPORTED_PROFILE, .{};
				}

			case "diagnostic_profile";
				if !values_equal(values, expected.diagnostic_profile) {
					return .UNSUPPORTED_PROFILE, .{};
				}

			case "visible_filename"; #through;
			case "visible_directory"; #through;
			case "relative_base";
				path_ok, path := parse_path_key(values);
				if !path_ok {
					return .INVALID_PATH, .{};
				}


				path_slots[it_index - 5].* = path;

			case "resolver_binding";
				if values.count != 1 || !bytes_equal(values[0], make_key("NO_RESOLUTION",, temp)) {
					return .UNSUPPORTED_RESOLVER, .{};
				}

			case "semantic_extension";
				if values.count != 1 || !bytes_equal(values[0], make_key("UNSUPPORTED",, temp)) {
					return .UNSUPPORTED_SEMANTICS, .{};
				}
		}
	}

	if !bytes_equal(identity, context_id(descriptor,, temp)) {
		return .IDENTITY_MISMATCH, .{};
	}


	result.identity = array_copy(identity);
	result.descriptor = array_copy(descriptor);
	for path_slots {
		it.code_units = array_copy(it.code_units);
	}

	return .NONE, result;
}

// Parser, lexer and adapter source digests; called at compile time, including from a cross-compiling build's host.
build_source_digests :: () -> [16] u8, [16] u8, [16] u8 {
	return
		source_digest(.["../module.jai", "../parser.jai", "../resolution.jai"]),
		source_digest(.["../lexer.jai"]),
		source_digest(.["canonical.jai", "context.jai", "diagnostics.jai", "digest.jai", "index.jai", "module.jai", "nodes.jai", "projection.jai", "snapshot.jai"]);
}

// Nonempty, NUL-free, and an even byte count for UTF-16LE.
path_is_valid :: (path: Path_Value) -> bool {
	return valid_path(path);
}

// UTF-8 spelling for the parser's filename; POSIX bytes are copied unchanged.
path_spelling :: (path: Path_Value) -> string {
	if path.encoding == .POSIX_BYTES {
		return copy_string(xx path.code_units);
	}


	units := path.code_units;
	bytes: [..] u8;
	i := 0;
	while i + 1 < units.count {
		code := units[i].(u32) | (units[i + 1].(u32) << 8);
		i += 2;
		if code >= 0xD800 && code < 0xDC00 && i + 1 < units.count {
			low := units[i].(u32) | (units[i + 1].(u32) << 8);
			if low >= 0xDC00 && low < 0xE000 {
				code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00);
				i += 2;
			}
		}

		if code < 0x80 {
			array_add(*bytes, xx code);
		} else if code < 0x800 {
			array_add(*bytes, (0xC0 | (code >> 6)).(u8), (0x80 | (code & 0x3F)).(u8));
		} else if code < 0x10000 {
			array_add(*bytes, (0xE0 | (code >> 12)).(u8), (0x80 | ((code >> 6) & 0x3F)).(u8), (0x80 | (code & 0x3F)).(u8));
		} else {
			array_add(*bytes, (0xF0 | (code >> 18)).(u8), (0x80 | ((code >> 12) & 0x3F)).(u8), (0x80 | ((code >> 6) & 0x3F)).(u8), (0x80 | (code & 0x3F)).(u8));
		}
	}

	return xx bytes;
}

#scope_file

append_utf16_unit :: (units: *[..] u8, unit: u32) {
	array_add(units, (unit & 0xFF).(u8));
	array_add(units, (unit >> 8).(u8));
}

valid_path :: (path: Path_Value) -> bool {
	units := path.code_units;
	if !units.count {
		return false;
	}


	if path.encoding == .POSIX_BYTES {
		for units {
			if !it {
				return false;
			}
		}


		return true;
	}


	if units.count % 2 {
		return false;
	}


	for i: 0..units.count / 2 - 1 {
		if !units[2 * i] && !units[2 * i + 1] {
			return false;
		}
	}


	return true;
}

parse_path_key :: (values: [] [] u8) -> bool, Path_Value {
	if values.count != 1 {
		return false, .{};
	}


	ok, key := parse_key(values[0], 2,, temp);
	if !ok || key.tag.(string) != "path" || key.fields.count != 2 {
		return false, .{};
	}


	path: Path_Value;
	if key.fields[0].(string) == {
		case "WINDOWS_UTF16LE";	path.encoding = .WINDOWS_UTF16LE;
		case "POSIX_BYTES";		path.encoding = .POSIX_BYTES;

		case;					return false, .{};
	}


	path.code_units = key.fields[1];
	return valid_path(path), path;
}

values_equal :: (values: [] [] u8, expected: [] [] u8) -> bool {
	if values.count != expected.count {
		return false;
	}


	for values {
		if !bytes_equal(it, expected[it_index]) {
			return false;
		}
	}


	return true;
}

Expected_Values :: struct {
	producer: [6] [] u8;
	syntax_schemas: [4] [] u8;
	parser_parameters: [5] [] u8;
	parse_profile: [2] [] u8;
	diagnostic_profile: [3] [] u8;
}

expected_field_values :: () -> Expected_Values {
	result: Expected_Values;
	result.producer = .[
		PRODUCER_NAMESPACE.([] u8),
		parser_build_digest,
		make_key("compiler-sdk", COMPILER_VERSION.([] u8), compiler_layout_digest,, temp),
		lexer_build_digest,
		adapter_build_digest,
		syntax_adapter_descriptor(,, temp)
	];
	result.syntax_schemas = .[
		SOURCE_TOKENS_SCHEMA.([] u8),
		AUTHORED_NODES_SCHEMA.([] u8),
		RECOVERY_SCHEMA.([] u8),
		DECLARATION_INDEX_SCHEMA.([] u8)
	];
	result.parser_parameters = .[
		boolean_byte(Parser.ENABLE_TRIVIA),
		boolean_byte(Parser.EVALUATE_STRING_ESCAPES),
		boolean_byte(Parser.INTERN_IDENTIFIERS),
		boolean_byte(Parser.USE_SIMD),
		boolean_byte(Parser.TRACK_AST_REUSE)
	];
	result.parse_profile = .[GRAMMAR_PROFILE.([] u8), RECOVERY_POLICY.([] u8)];
	result.diagnostic_profile = .[SYNTAX_DIAGNOSTICS_SCHEMA.([] u8), MESSAGE_POLICY.([] u8), PRESENTATION_LANGUAGE.([] u8)];
	return result;
}

FALSE_BYTE :: u8.[0];
TRUE_BYTE :: u8.[1];

boolean_byte :: (value: bool) -> [] u8 {
	return ifx value then TRUE_BYTE else FALSE_BYTE;
}

#assert Parser.ENABLE_TRIVIA "The full-featured syntax profile requires a trivia-enabled parser.";

// Build identities: digests of the exact sources compiled into this build, taken at compile time.
source_digest :: (files: [] string) -> [16] u8 {
	state: Digest_State;
	digest_begin(*state);
	for files {
		source, ok := read_entire_file(tprint("%1%2", #filepath, it));
		assert(ok, "Unable to read % for the build identity.", it);
		digest_absorb(*state, make_key("source-file", it.([] u8), source.([] u8)));
	}

	return digest_end(*state).bytes;
}

#if IS_CROSS_COMPILING {
	// A cross-target `#run` cannot call the target's file bindings; `#run,host` lambdas run outside this module's scope, so they import it.
	PARSER_BUILD_DIGEST_BYTES, LEXER_BUILD_DIGEST_BYTES, ADAPTER_BUILD_DIGEST_BYTES :: #run,host -> [16] u8, [16] u8, [16] u8 {
		#import "Jai_Parser/service";
		parser, lexer, adapter := build_source_digests();
		return parser, lexer, adapter;
	};
} else {
	PARSER_BUILD_DIGEST_BYTES, LEXER_BUILD_DIGEST_BYTES, ADAPTER_BUILD_DIGEST_BYTES :: #run build_source_digests();
}

// The compiler layouts the parser overlays, by name, size and member offsets.
COMPILER_LAYOUT_DIGEST_BYTES :: #run -> [16] u8 {
	builder: String_Builder;
	for Parser.TYPES {
		info := it.(*Type_Info_Struct);
		print(*builder, "% %\n", info.name, info.runtime_size);
		for member: info.members {
			print(*builder, "  % % %\n", member.name, member.offset_in_bytes, member.type.runtime_size);
		}
	}

	return digest_128(xx builder_to_string(*builder)).bytes;
};

COMPILER_VERSION :: #run compiler_get_version_info(null);

// File-scope storage, so the views in `expected_field_values` stay valid.
parser_build_digest := PARSER_BUILD_DIGEST_BYTES;
lexer_build_digest := LEXER_BUILD_DIGEST_BYTES;
adapter_build_digest := ADAPTER_BUILD_DIGEST_BYTES;
compiler_layout_digest := COMPILER_LAYOUT_DIGEST_BYTES;

#import "Compiler";
#import "File";
