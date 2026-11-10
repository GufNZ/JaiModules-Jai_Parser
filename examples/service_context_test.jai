// Phase-3 context registry tests: the implemented schema tuple, the `jai-cache-syntax-context/1` descriptor layout and admission controls.
// Run from this directory: jai service_context_test.jai -x64 -quiet && ./service_context_test.exe
#import "Basic";
#import "File";
#import "String";

Service :: #import "Jai_Parser/service";
operator == :: Service.operator ==;

FIELDS :: string.[
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

main :: () {
	test_schema_tuples();
	test_paths();
	test_descriptor_layout();
	test_admission_controls();
	print("Service context \e[92mPASS\e[0m.\n");
}

test_schema_tuples :: () {
	implemented := Service.IMPLEMENTED_SCHEMA_TUPLE;
	assert(implemented.token_tags == "jai-cache-token-tags/1" && implemented.source_tokens == "jai-cache-source-tokens/1");
	assert(implemented.nodes == "jai-cache-authored-nodes/1" && implemented.recovery == "jai-cache-recovery/1");
	assert(implemented.declaration_index == "jai-cache-syntax-declaration-index/1" && implemented.diagnostics == "jai-cache-syntax-diagnostics/1");
	assert(implemented.snapshot == "jai-cache-syntax-snapshot/1" && implemented.authored_edges == "jai-cache-authored-edges/1");
	assert(implemented.syntax_adapter == "jai-cache-syntax-adapter/1");
	assert(Service.IMPLEMENTED_QUERY_KINDS.count == 3 && Service.IMPLEMENTED_QUERY_KINDS[2] == "SYNTAX_DECLARATION_INDEX");

	ok, single := Service.configuration_id(.[implemented]);
	assert(ok);
	duplicate_ok := Service.configuration_id(.[implemented, implemented]);
	assert(!duplicate_ok, "\e[91mA duplicated tuple is not a set.\e[0m");
	empty_ok := Service.configuration_id(.[]);
	assert(!empty_ok);

	// Changing any one identifier leaves an unimplemented tuple, which admission rejects rather than mapping to a fallback.
	info := type_info(Service.Schema_Tuple);
	for info.members {
		changed := implemented;
		field := ((*changed).(*u8) + it.offset_in_bytes).(*string);
		field.* = tprint("%1x", field.*);
		changed_ok := Service.configuration_id(.[changed]);
		assert(!changed_ok, "\e[91mA tuple with a changed % was admitted.\e[0m", it.name);
	}

	// The tuple value is a record of eleven ASCII values in field order.
	_, value := Service.schema_tuple_value(implemented);
	record_ok, record := Service.parse_key(value, 16);
	assert(record_ok && record.tag.(string) == "record" && record.fields.count == 12);
	ascii_ok, last := Service.parse_key(record.fields[11], 1);
	assert(ascii_ok && last.tag.(string) == "ascii" && last.fields[0].(string) == Service.DIAGNOSTIC_PROFILE);
	print("Schema tuples \e[92mPASS\e[0m\n");
}

test_paths :: () {
	ok, path := Service.windows_path_value("D:/jai/é😀.jai");
	assert(ok && path.encoding == .WINDOWS_UTF16LE);
	// `D`, `:`, `/`, `j`, `a`, `i`, `/`, U+00E9, a surrogate pair, `.`, `j`, `a`, `i`: fourteen units.
	assert(path.code_units.count == 28);
	assert(path.code_units[14] == 0xE9 && path.code_units[15] == 0x00);
	assert(path.code_units[16] == 0x3D && path.code_units[17] == 0xD8 && path.code_units[18] == 0x00 && path.code_units[19] == 0xDE);

	empty_ok := Service.windows_path_value("");
	nul_ok := Service.windows_path_value("a\0b");
	invalid_ok := Service.windows_path_value("a\xFFb");
	posix_nul_ok := Service.posix_path_value("a\0b");
	posix_ok, posix := Service.posix_path_value("/tmp/\xFF");
	assert(!empty_ok && !nul_ok && !invalid_ok && !posix_nul_ok && posix_ok && posix.code_units.count == 6, "\e[91mPOSIX bytes are kept without decoding.\e[0m");
	print("Path values \e[92mPASS\e[0m\n");
}

paths :: (filename := "D:/project/main.jai", directory := "D:/project", base := "D:/project") -> Service.Context_Paths {
	result: Service.Context_Paths;

	ok:, result.visible_filename = Service.windows_path_value(filename);
	assert(ok);
	ok, result.visible_directory = Service.windows_path_value(directory);
	assert(ok);
	ok, result.relative_base = Service.windows_path_value(base);
	assert(ok);

	return result;
}

// Independent decoding of the descriptor: ten named fields in order, with the producer, schema and parameter values this build uses.
test_descriptor_layout :: () {
	ok, descriptor := Service.syntax_context_descriptor(paths());
	assert(ok);
	root_ok, root := Service.parse_key(descriptor, 16);
	assert(root_ok && root.tag.(string) == "syntax-context-descriptor" && root.fields.count == FIELDS.count);
	values: [FIELDS.count] [..] [] u8;
	for FIELDS {
		field_ok, field := Service.parse_key(root.fields[it_index], 16);
		assert(field_ok && field.tag.(string) == it, "\e[91mField % is %.\e[0m", it_index, field.tag.(string));
		values[it_index] = field.fields;
	}

	producer := values[0];
	assert(producer.count == 6 && producer[0].(string) == "jai-parser-service" && producer[1].count == 16 && producer[3].count == 16 && producer[4].count == 16);
	assert(Service.bytes_equal(producer[5], Service.syntax_adapter_descriptor()), "\e[91mThe producer binds the adapter's capability descriptor.\e[0m");

	// Build identities are digests of the exact compiled sources, recomputed here from the files.
	digest_of :: (files: [] string) -> [16] u8 {
		state: Service.Digest_State;
		Service.digest_begin(*state);
		for files {
			source, read_ok := read_entire_file(tprint("%../service/%", #filepath, it));
			assert(read_ok);
			Service.digest_absorb(*state, Service.make_key("source-file", it.([] u8), source.([] u8)));
		}

		return Service.digest_end(*state).bytes;
	}

	parser_digest := digest_of(.["../module.jai", "../parser.jai", "../resolution.jai"]);
	lexer_digest := digest_of(.["../lexer.jai"]);
	assert(Service.bytes_equal(producer[1], parser_digest) && Service.bytes_equal(producer[3], lexer_digest), "\e[91mBuild digests match the sources on disk.\e[0m");

	sdk_ok, sdk := Service.parse_key(producer[2], 2);
	assert(sdk_ok && sdk.tag.(string) == "compiler-sdk" && begins_with(sdk.fields[0].(string), "beta ") && sdk.fields[1].count == 16);

	schemas := values[1];
	assert(schemas.count == 4 && schemas[0].(string) == "jai-cache-source-tokens/1" && schemas[3].(string) == "jai-cache-syntax-declaration-index/1");
	parameters := values[2];
	assert(parameters.count == 5 && parameters[0][0] == 1 && parameters[1][0] == 1 && parameters[2][0] == 0 && parameters[3][0] == 1 && parameters[4][0] == 0);
	assert(values[3].count == 2 && values[4].count == 3 && values[4][2].(string) == "en");
	path_ok, path := Service.parse_key(values[5][0], 2);
	assert(path_ok && path.tag.(string) == "path" && path.fields[0].(string) == "WINDOWS_UTF16LE" && path.fields[1].count == 2 * "D:/project/main.jai".count);
	resolver_ok, resolver := Service.parse_key(values[8][0], 0);
	semantic_ok, semantic := Service.parse_key(values[9][0], 0);
	assert(resolver_ok && resolver.tag.(string) == "NO_RESOLUTION" && semantic_ok && semantic.tag.(string) == "UNSUPPORTED");

	identity := Service.context_id(descriptor);
	failure, admitted := Service.admit_context(identity, descriptor);
	assert(failure == .NONE && Service.bytes_equal(admitted.identity, identity) && admitted.descriptor.data != descriptor.data);
	assert(Service.bytes_equal(admitted.paths.visible_filename.code_units, path.fields[1]));

	// Source-visible spelling, base and encoding are all part of identity, even for the same physical file.
	alias_ok, alias := Service.syntax_context_descriptor(paths(filename = "D:/project/./main.jai"));
	base_ok, base := Service.syntax_context_descriptor(paths(base = "D:/other"));
	posix_paths := paths();
	_, posix_paths.visible_filename = Service.posix_path_value("D:/project/main.jai");
	posix_ok, posix := Service.syntax_context_descriptor(posix_paths);
	assert(alias_ok && base_ok && posix_ok);
	for ([] u8).[alias, base, posix] {
		assert(!Service.bytes_equal(Service.context_id(it), identity), "\e[91mVariant % shares the original identity.\e[0m", it_index);
		variant_failure := Service.admit_context(Service.context_id(it), it);
		assert(variant_failure == .NONE);
	}

	invalid_paths := paths();
	invalid_paths.visible_directory.code_units.count -= 1;
	invalid_ok := Service.syntax_context_descriptor(invalid_paths);
	assert(!invalid_ok, "\e[91mAn odd UTF-16 byte count is rejected.\e[0m");
	print("Descriptor layout \e[92mPASS\e[0m\n");
}

// Rebuilds the descriptor with field `index` replaced by `K(name, values)`.
with_field :: (descriptor: [] u8, index: s64, name: string, values: .. [] u8) -> [] u8 {
	_, root := Service.parse_key(descriptor, 16);
	fields := array_copy(root.fields);
	fields[index] = Service.make_key(name, ..values);
	return Service.make_key("syntax-context-descriptor", ..fields);
}

field_values :: (descriptor: [] u8, index: s64) -> [..] [] u8 {
	_, root := Service.parse_key(descriptor, 16);
	_, field := Service.parse_key(root.fields[index], 16);
	return field.fields;
}

expect :: (descriptor: [] u8, failure: Service.Context_Failure, what: string) {
	actual := Service.admit_context(Service.context_id(descriptor), descriptor);
	assert(actual == failure, "\e[91m%: expected %, got %.\e[0m", what, failure, actual);
}

test_admission_controls :: () {
	_, descriptor := Service.syntax_context_descriptor(paths());
	identity := Service.context_id(descriptor);

	// Each of the five module parameters is keyed: flipping any one is an unsupported configuration.
	for 0..4 {
		parameters := array_copy(field_values(descriptor, 2));
		flipped := NewArray(1, u8);
		flipped[0] = 1 - parameters[it][0];
		parameters[it] = flipped;
		expect(with_field(descriptor, 2, "parser_parameters", ..parameters), .UNSUPPORTED_PARAMETERS, tprint("parameter %", it));
	}

	{
		parameters := array_copy(field_values(descriptor, 2));
		two := NewArray(1, u8);
		two[0] = 2;
		parameters[1] = two;
		expect(with_field(descriptor, 2, "parser_parameters", ..parameters), .INVALID_BOOLEAN, "boolean 2");
	}

	{
		producer := array_copy(field_values(descriptor, 0));
		forged := array_copy(producer[1]);
		forged[0] ^= 1;
		producer[1] = forged;
		expect(with_field(descriptor, 0, "producer", ..producer), .UNSUPPORTED_PRODUCER, "parser build");
		producer = array_copy(field_values(descriptor, 0));
		producer[5] = xx "forged adapter descriptor";
		expect(with_field(descriptor, 0, "producer", ..producer), .UNSUPPORTED_PRODUCER, "adapter descriptor");
	}

	{
		schemas := array_copy(field_values(descriptor, 1));
		schemas[3] = xx "jai-cache-syntax-declaration-index/2";
		expect(with_field(descriptor, 1, "syntax_schemas", ..schemas), .UNSUPPORTED_SCHEMAS, "index schema");
		profile := array_copy(field_values(descriptor, 3));
		profile[1] = xx "jai-parser-recovery/2";
		expect(with_field(descriptor, 3, "parse_profile", ..profile), .UNSUPPORTED_PROFILE, "recovery policy");
		diagnostic := array_copy(field_values(descriptor, 4));
		diagnostic[2] = xx "de";
		expect(with_field(descriptor, 4, "diagnostic_profile", ..diagnostic), .UNSUPPORTED_PROFILE, "presentation language");
	}

	{
		resolver := Service.make_key("RESOLVER_CONFIG", xx "some-resolver/1", xx "");
		expect(with_field(descriptor, 8, "resolver_binding", resolver), .UNSUPPORTED_RESOLVER, "resolver config");
		expect(with_field(descriptor, 9, "semantic_extension", Service.make_key("SUPPORTED")), .UNSUPPORTED_SEMANTICS, "semantic extension");
		expect(with_field(descriptor, 5, "visible_filename", Service.make_key("path", xx "WINDOWS_UTF16LE", xx "abc")), .INVALID_PATH, "odd UTF-16");
		expect(with_field(descriptor, 6, "visible_directory", Service.make_key("path", xx "UTF8", xx "abc")), .INVALID_PATH, "unknown encoding");
		expect(with_field(descriptor, 7, "relative_base", Service.make_key("path", xx "POSIX_BYTES", xx "")), .INVALID_PATH, "empty base");
		expect(with_field(descriptor, 7, "visible_directory", Service.make_key("path", xx "POSIX_BYTES", xx "/")), .FIELD_ORDER, "renamed field");
	}

	{
		_, root := Service.parse_key(descriptor, 16);
		fields := array_copy(root.fields);
		fields[5], fields[6] = fields[6], fields[5];
		expect(Service.make_key("syntax-context-descriptor", ..fields), .FIELD_ORDER, "reordered fields");
		missing := Service.make_key("syntax-context-descriptor", ..array_view(fields, 0, 9));
		expect(missing, .MALFORMED, "missing field");
		extra: [..] [] u8;
		array_add(*extra, ..root.fields);
		array_add(*extra, Service.make_key("extension"));
		expect(Service.make_key("syntax-context-descriptor", ..extra), .MALFORMED, "unknown extra field");
		trailing: [..] u8;
		array_add(*trailing, ..descriptor);
		array_add(*trailing, 0);
		expect(trailing, .MALFORMED, "trailing byte");
		expect(Service.make_key("other-descriptor", ..root.fields), .MALFORMED, "wrong tag");
	}

	mismatch := array_copy(identity);
	mismatch[mismatch.count - 1] ^= 1;
	failure := Service.admit_context(mismatch, descriptor);
	assert(failure == .IDENTITY_MISMATCH, "\e[91mA forged identity is rejected.\e[0m");
	print("Admission controls \e[92mPASS\e[0m\n");
}
