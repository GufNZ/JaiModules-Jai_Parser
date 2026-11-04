// Canonical B/K/V encodings from CACHE_CONTRACTS.md ("Canonical Identity and Payload Refinement", milestone 2 "Canonical Values").
// These bytes are equality and digest inputs; they never depend on Jai struct layout, padding or pointers.

KEY_MAGIC :: "jai-cache-key";
KEY_SCHEMA_VERSION : u32 : 1;
INTERFACE_SCHEMA_PREFIX :: "jai-cache-interface/1/";

append_bytes :: (bytes: *[..] u8, data: [] u8) {
	old_count := bytes.count;
	array_resize(bytes, old_count + data.count, initialize = false);
	memcpy(bytes.data + old_count, data.data, data.count);
}

append_u32_le :: (bytes: *[..] u8, value: u32) {
	for 0..3 {
		array_add(bytes, xx ((value >> (8 * it)) & 0xFF));
	}
}

append_u64_le :: (bytes: *[..] u8, value: u64) {
	for 0..7 {
		array_add(bytes, xx ((value >> (8 * it)) & 0xFF));
	}
}

append_framed :: (bytes: *[..] u8, value: [] u8) {
	append_u64_le(bytes, xx value.count);
	append_bytes(bytes, value);
}

little_endian :: (value: u64, width: s64) -> [] u8 {
	assert(width >= 1 && width <= 8);
	result := NewArray(width, u8, initialized = false);
	for 0..width - 1 {
		result[it] = xx ((value >> (8 * it)) & 0xFF);
	}

	return result;
}

// K(tag, fields): B("jai-cache-key"), u32 LE key-schema version, B(tag), u64 LE field count, then B(field) for each field.
make_key :: (tag: string, fields: .. [] u8) -> [] u8 {
	result: [..] u8;
	append_framed(*result, KEY_MAGIC.([] u8));
	append_u32_le(*result, KEY_SCHEMA_VERSION);
	append_framed(*result, tag.([] u8));
	append_u64_le(*result, xx fields.count);
	for fields {
		append_framed(*result, it);
	}

	return result;
}

UPPERCASE_HEX_DIGITS :: "0123456789ABCDEF";

append_uppercase_hex :: (builder: *String_Builder, bytes: [] u8) {
	for bytes {
		append(builder, UPPERCASE_HEX_DIGITS[it >> 4]);
		append(builder, UPPERCASE_HEX_DIGITS[it & 0xF]);
	}
}

is_canonical_ascii :: (text: string) -> bool {
	if !text.count {
		return false;
	}


	for text {
		if it < 0x21 || it > 0x7E {
			return false;
		}
	}


	return true;
}

interface_schema :: (type_name: string) -> string {
	return join(INTERFACE_SCHEMA_PREFIX, type_name);
}

v_bytes :: (value: [] u8) -> [] u8 {
	return make_key("bytes", value);
}

v_ascii :: (text: string) -> bool, [] u8 {
	if !is_canonical_ascii(text) {
		return false, .[];
	}


	return true, make_key("ascii", text.([] u8));
}

v_bool :: (value: bool) -> [] u8 {
	byte: [1] u8 = .[xx value];
	return make_key("bool", byte);
}

v_u8 :: (value: u8) -> [] u8 {
	return make_key("u8", little_endian(value, 1));
}

v_u16 :: (value: u16) -> [] u8 {
	return make_key("u16", little_endian(value, 2));
}

v_u32 :: (value: u32) -> [] u8 {
	return make_key("u32", little_endian(value, 4));
}

v_u64 :: (value: u64) -> [] u8 {
	return make_key("u64", little_endian(value, 8));
}

v_s32 :: (value: s32) -> [] u8 {
	bits := (*value).(*u32).*;
	return make_key("s32", little_endian(bits, 4));
}

v_s64 :: (value: s64) -> [] u8 {
	bits := (*value).(*u64).*;
	return make_key("s64", little_endian(bits, 8));
}

v_float64_bits :: (value: float64) -> [] u8 {
	bits := (*value).(*u64).*;
	return make_key("float64-bits", little_endian(bits, 8));
}

v_enum :: (schema: [] u8, tag: string) -> [] u8 {
	return make_key("enum", schema, tag.([] u8));
}

#scope_file
with_leading :: (leading: [] [] u8, rest: [] [] u8) -> [] [] u8 {
	all := NewArray(leading.count + rest.count, [] u8, initialized = false,, temp);
	for leading {
		all[it_index] = it;
	}

	for rest {
		all[leading.count + it_index] = it;
	}

	return all;
}
#scope_export

v_record :: (schema: [] u8, fields: .. [] u8) -> [] u8 {
	return make_key("record", ..with_leading(.[schema], fields));
}

v_variant :: (schema: [] u8, arm: string, fields: .. [] u8) -> [] u8 {
	return make_key("variant", ..with_leading(.[schema, arm.([] u8)], fields));
}

v_null :: () -> [] u8 {
	return make_key("null");
}

v_sequence :: (element_schema: [] u8, elements: .. [] u8) -> [] u8 {
	return make_key("sequence", ..with_leading(.[element_schema], elements));
}

// Canonical set order: unsigned byte comparison, shorter prefix first.
compare_canonical :: (a: [] u8, b: [] u8) -> s64 {
	common := min(a.count, b.count);
	for 0..common - 1 {
		if a[it] != b[it] {
			return ifx a[it] < b[it]
				then -1
				else 1;
		}
	}

	return ifx a.count == b.count
		then 0
		else ifx a.count < b.count
			then -1
			else 1;
}

bytes_equal :: (a: [] u8, b: [] u8) -> bool {
	return a.count == b.count && (!a.count || memcmp(a.data, b.data, a.count) == 0);
}

Key_View :: struct {
	tag: [] u8;
	fields: [..] [] u8;
}

// Bounded K decoder: views borrow `bytes`; rejects bad framing, version, counts above `maximum_fields` and trailing bytes.
parse_key :: (bytes: [] u8, maximum_fields: u64) -> bool, Key_View {
	result: Key_View;
	cursor: s64;

	read_u64 :: (bytes: [] u8, cursor: *s64) -> bool, u64 {
		if bytes.count - cursor.* < 8 {
			return false, 0;
		}


		value: u64;
		for 0..7 {
			value |= (bytes[cursor.* + it].(u64)) << (8 * it);
		}

		cursor.* += 8;
		return true, value;
	}

	read_framed :: (bytes: [] u8, cursor: *s64) -> bool, [] u8 {
		ok, length := read_u64(bytes, cursor);
		if !ok || length > xx (bytes.count - cursor.*) {
			return false, .[];
		}


		view: [] u8 = .{count = xx length, data = bytes.data + cursor.*};
		cursor.* += xx length;
		return true, view;
	}

	magic_ok, magic := read_framed(bytes, *cursor);
	if !magic_ok || !bytes_equal(magic, KEY_MAGIC.([] u8)) || bytes.count - cursor < 4 {
		return false, result;
	}


	version: u32;
	for 0..3 {
		version |= (bytes[cursor + it].(u32)) << (8 * it);
	}

	cursor += 4;
	if version != KEY_SCHEMA_VERSION {
		return false, result;
	}


	tag_ok, tag := read_framed(bytes, *cursor);
	count_ok, field_count := read_u64(bytes, *cursor);
	// Each field needs at least its 8-byte length prefix, which bounds the count before allocating.
	if !tag_ok || !count_ok || field_count > maximum_fields || field_count > xx ((bytes.count - cursor) / 8) {
		return false, result;
	}


	result.tag = tag;
	array_reserve(*result.fields, xx field_count);
	for 1..field_count {
		field_ok, field := read_framed(bytes, *cursor);
		if !field_ok {
			array_free(result.fields);
			return false, .{};
		}


		array_add(*result.fields, field);
	}

	if cursor != bytes.count {
		array_free(result.fields);
		return false, .{};
	}


	return true, result;
}
