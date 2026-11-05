// Snapshot projection, part 1 (phase 3 step 2): source tokens (`jai-cache-source-tokens/1`), synthetic tokens, recovery records and raw diagnostics
// of `jai-cache-syntax-snapshot/1`, per CACHE_CONTRACTS.md "Recovery and Raw Diagnostics" and the registry's token sections.
// Records borrow bytes from their `Owned_Syntax`; a projection must be released before its owner.

TOKEN_TAGS_SCHEMA :: "jai-cache-token-tags/1";
SOURCE_TOKENS_SCHEMA :: "jai-cache-source-tokens/1";
RECOVERY_SCHEMA :: "jai-cache-recovery/1";

// The closed `.NAMED` registry, in the registry's table order.
TOKEN_TAG_NAMES :: string.[
	"IDENT",
	"NUMBER",
	"STRING",
	"PLUSEQUALS",
	"MINUSEQUALS",
	"TIMESEQUALS",
	"DIVEQUALS",
	"MODEQUALS",
	"ISEQUAL",
	"ISNOTEQUAL",
	"LOGICAL_AND",
	"LOGICAL_OR",
	"LESSEQUALS",
	"GREATEREQUALS",
	"RIGHT_ARROW",
	"DOUBLE_DOT",
	"DOUBLE_DOLLAR",
	"SHIFT_LEFT",
	"SHIFT_RIGHT",
	"ROTATE_LEFT",
	"ROTATE_RIGHT",
	"TRIPLE_EQUALS",
	"SHIFT_LEFT_EQUALS",
	"SHIFT_RIGHT_EQUALS",
	"ROTATE_LEFT_EQUALS",
	"ROTATE_RIGHT_EQUALS",
	"BITWISE_AND_EQUALS",
	"BITWISE_OR_EQUALS",
	"BITWISE_XOR_EQUALS",
	"LOGICAL_AND_EQUALS",
	"LOGICAL_OR_EQUALS",
	"POSTFIX_DEREFERENCE",
	"PREFIX_DEREFERENCE",
	"ISEQUAL_FOR_SWITCH_STATEMENT",
	"DOUBLE_MINUS",
	"TRIPLE_MINUS",
	"DOUBLE_COMMA",
	"BEGIN_STRUCT_LITERAL",
	"BEGIN_ARRAY_LITERAL",
	"KEYWORD_FOR",
	"KEYWORD_IF",
	"KEYWORD_IFX",
	"KEYWORD_THEN",
	"KEYWORD_ELSE",
	"KEYWORD_CASE",
	"KEYWORD_RETURN",
	"KEYWORD_STRUCT",
	"KEYWORD_WHILE",
	"KEYWORD_BREAK",
	"KEYWORD_CONTINUE",
	"KEYWORD_REMOVE",
	"KEYWORD_USING",
	"KEYWORD_DEFER",
	"KEYWORD_SIZE_OF",
	"KEYWORD_TYPE_OF",
	"KEYWORD_CODE_OF",
	"KEYWORD_INITIALIZER_OF",
	"KEYWORD_TYPE_INFO",
	"KEYWORD_NULL",
	"KEYWORD_ENUM",
	"KEYWORD_TRUE",
	"KEYWORD_FALSE",
	"KEYWORD_INLINE",
	"KEYWORD_NO_INLINE",
	"KEYWORD_CAST",
	"KEYWORD_AUTO_CAST",
	"KEYWORD_CONTEXT",
	"KEYWORD_PUSH_CONTEXT",
	"KEYWORD_OPERATOR",
	"KEYWORD_IS_CONSTANT",
	"KEYWORD_ENUM_FLAGS",
	"KEYWORD_UNION",
	"KEYWORD_INTERFACE",
	"QUICK_LAMBDA",
	"NOTE",
	"END_OF_INPUT",
	"ERROR"
];

// Producer values from 256 upwards, indexing TOKEN_TAG_NAMES or -1; aliases (`__FIRST_KEYWORD`, `__LAST_KEYWORD`) share their target's value.
NAMED_TOKEN_TAG_BASE :: 256;
NAMED_TOKEN_TAG_BY_VALUE :: #run -> [] s16 {
	info := type_info(Parser.Token_Type);
	highest: s64;
	for info.values {
		highest = max(highest, it);
	}

	table := NewArray(highest - NAMED_TOKEN_TAG_BASE + 1, s16);
	for * table {
		it.* = -1;
	}

	for name, name_index: TOKEN_TAG_NAMES {
		found := false;
		for info.names {
			if it == name {
				table[info.values[it_index] - NAMED_TOKEN_TAG_BASE] = xx name_index;
				found = true;
				break;
			}
		}

		assert(found, "Registered token tag % is not a producer Token_Type name.", name);
	}

	return table;
};

KNOWN_VALUE_FLAGS : u32 : 0x1070_001F;

Token_Tag :: struct {
	kind: enum u8 {
		BYTE_CHAR;
		NAMED;
	};
	byte: u8;
	// Registered name without the leading dot; empty for `.BYTE_CHAR`.
	name: string;
}

operator == :: (a: Token_Tag, b: Token_Tag) -> bool {
	return a.kind == b.kind && a.byte == b.byte && a.name == b.name;
}

// Half-open byte range of the owner's exact source.
Byte_Span :: struct {
	start: s64;
	end: s64;
}

Coordinates :: struct {
	l0: s32;
	c0: s32;
	l1: s32;
	c1: s32;
}

// Signed producer observation; not dereferenceable without a separate range check.
Token_Span_Observation :: struct {
	first: s64;
	one_past_last: s64;
}

Token_Value :: struct {
	kind: enum u8 {
		NAME;
		UNSIGNED_INTEGER;
		FLOAT64_BITS;
		STRING_BYTES;
		NO_VALUE;
	};
	bytes: [] u8;
	bits: u64;
}

Token_Record :: struct {
	tag: Token_Tag;
	origin: Byte_Span;
	coordinates: Coordinates;
	value_flags: u32;
	ident_is_backticked: bool;
	original: Byte_Span;
	preceding: Byte_Span;
	value: Token_Value;
}

Synthetic_Token_Record :: struct {
	insertion_index: s64;
	tag: Token_Tag;
	coordinates: Coordinates;
	value_flags: u32;
	ident_is_backticked: bool;
	value: Token_Value;
}

Recovery_Observation :: struct {
	kind: enum u8 {
		MISSING_TOKEN;
		EXPECTED_EXPRESSION;
		SKIPPED_TOKENS;
		ERROR_SPAN;
	};
	token_span: Token_Span_Observation;
	diagnostic_index: s64;
	synthetic_token_index: s64;
	cursor: s64;
	discarded: bool;

	// `.UNPUBLISHED` until the snapshot envelope maps the owner to a node ID; token projections alone never resolve it.
	owner: enum u8 {
		NONE;
		NODE;
		UNPUBLISHED;
	};
	owner_node_id: s64 = -1;
}

Diagnostic_Code :: enum u8 {
	EXPECTED_TOKEN;
	EXPECTED_EXPRESSION;
	UNEXPECTED_TOKEN;
	UNNECESSARY_SEMICOLON;
	LEXER_ERROR;
}

Diagnostic_Severity :: enum u8 {
	ERROR;
	WARNING;
}

Diagnostic_Recovery_Action :: enum u8 {
	NONE;
	INSERT_MISSING_TOKEN;
	SKIP_TOKENS;
}

Raw_Related_Diagnostic :: struct {
	token_span: Token_Span_Observation;
	message_bytes: [] u8;
}

Raw_Diagnostic :: struct {
	code: Diagnostic_Code;
	severity: Diagnostic_Severity;
	token_span: Token_Span_Observation;
	message_bytes: [] u8;
	expected_token: Token_Tag;
	actual_token: Token_Tag;
	recovery_action: Diagnostic_Recovery_Action;
	lexer_line: s32;
	lexer_column: s32;
	related: [] Raw_Related_Diagnostic;
}

Parse_Status_Observation :: enum u8 {
	COMPLETE;
	INCOMPLETE;
	RECOVERED;
	FATAL;
}

Projection_Failure :: enum u8 {
	NONE;
	UNREGISTERED_TOKEN_TYPE;
	UNKNOWN_VALUE_FLAGS;
	UNMAPPED_SOURCE_SLICE;
	UNKNOWN_PRODUCER_ENUM;
	UNREGISTERED_NODE_KIND;
	UNKNOWN_SOURCE_FLAGS;
	UNEXPECTED_ACTIVE_FIELD;
	UNREGISTERED_SHARING;
	UNQUALIFIED_ROUTE;
	INVALID_REFERENCE;
	INVALID_TEXT;
	CONFLICTING_EVIDENCE;
}

// Which record failed conversion; `index` is its position in the producer array.
Projection_Fault :: struct {
	failure: Projection_Failure;
	record: string;
	index: s64;
}

Token_Projection :: struct {
	owner: *Owned_Syntax;
	tokens: [] Token_Record;
	synthetic_tokens: [] Synthetic_Token_Record;
	recoveries: [] Recovery_Observation;
	diagnostics: [] Raw_Diagnostic;
	parse_status: Parse_Status_Observation;
	storage: Pool;
}

token_tag :: (type: Parser.Token_Type) -> bool, Token_Tag {
	value := type.(s64);
	if value >= 0 && value < NAMED_TOKEN_TAG_BASE {
		return true, .{kind = .BYTE_CHAR, byte = xx value};
	}


	slot := value - NAMED_TOKEN_TAG_BASE;
	if slot < 0 || slot >= NAMED_TOKEN_TAG_BY_VALUE.count || NAMED_TOKEN_TAG_BY_VALUE[slot] < 0 {
		return false, .{};
	}


	return true, .{kind = .NAMED, name = TOKEN_TAG_NAMES[NAMED_TOKEN_TAG_BY_VALUE[slot]]};
}

// On success the projection holds one record per producer record, in producer order.
project_tokens :: (owner: *Owned_Syntax) -> Projection_Fault, *Token_Projection {
	projection := New(Token_Projection);
	projection.owner = owner;
	set_allocators(*projection.storage, context.allocator);

	fault := fill_token_projection(projection);
	if fault.failure != .NONE {
		release_token_projection(projection);
		return fault, null;
	}


	return fault, projection;
}

release_token_projection :: (projection: *Token_Projection) {
	release(*projection.storage);
	free(projection);
}

#scope_file

fill_token_projection :: (projection: *Token_Projection) -> Projection_Fault {
	push_allocator(pool_allocator_proc, *projection.storage);
	parsed := *projection.owner.parsed;
	source := projection.owner.source;

	projection.tokens = NewArray(parsed.tokens.count, Token_Record, initialized = false);
	for * parsed.tokens {
		failure := project_source_token(*projection.tokens[it_index], it, source);
		if failure != .NONE {
			return .{failure, "tokens", it_index};
		}
	}


	projection.synthetic_tokens = NewArray(parsed.synthetic_tokens.count, Synthetic_Token_Record, initialized = false);
	for * parsed.synthetic_tokens {
		tag_ok, tag := token_tag(it.token.type);
		if !tag_ok {
			return .{.UNREGISTERED_TOKEN_TYPE, "synthetic_tokens", it_index};
		}


		if it.token.value_flags.(u32) & ~KNOWN_VALUE_FLAGS {
			return .{.UNKNOWN_VALUE_FLAGS, "synthetic_tokens", it_index};
		}


		// `add_missing_token` is the only producer and never sets a union member.
		projection.synthetic_tokens[it_index] = .{
			insertion_index = it.insertion_index.(s64),
			tag = tag,
			coordinates = coordinates_of(*it.token),
			value_flags = it.token.value_flags.(u32),
			ident_is_backticked = it.token.ident_is_backticked,
			value = .{kind = .NO_VALUE}
		};
	}

	projection.recoveries = NewArray(parsed.recovery_records.count, Recovery_Observation, initialized = false);
	for parsed.recovery_records {
		record := *projection.recoveries[it_index];
		record.* = .{
			token_span = span_observation(it.span),
			diagnostic_index = it.diagnostic_index,
			synthetic_token_index = it.synthetic_token_index,
			cursor = it.cursor,
			discarded = it.discarded
		};
		if it.owner {
			record.owner = .UNPUBLISHED;
		}

		if it.kind == {
			case .MISSING_TOKEN;		record.kind = .MISSING_TOKEN;
			case .EXPECTED_EXPRESSION;	record.kind = .EXPECTED_EXPRESSION;
			case .SKIPPED_TOKENS;		record.kind = .SKIPPED_TOKENS;
			case .ERROR_SPAN;			record.kind = .ERROR_SPAN;

			case;						return .{.UNKNOWN_PRODUCER_ENUM, "recoveries", it_index};
		}
	}


	projection.diagnostics = NewArray(parsed.diagnostics.count, Raw_Diagnostic, initialized = false);
	for * parsed.diagnostics {
		failure := project_raw_diagnostic(*projection.diagnostics[it_index], it);
		if failure != .NONE {
			return .{failure, "diagnostics", it_index};
		}
	}


	if parsed.status == {
		case .COMPLETE;		projection.parse_status = .COMPLETE;
		case .INCOMPLETE;	projection.parse_status = .INCOMPLETE;
		case .RECOVERED;	projection.parse_status = .RECOVERED;
		case .FATAL;		projection.parse_status = .FATAL;

		case;				return .{.UNKNOWN_PRODUCER_ENUM, "parse_status", 0};
	}


	return .{};
}

project_source_token :: (record: *Token_Record, token: *Parser.Parser_Token, source: string) -> Projection_Failure {
	tag_ok, tag := token_tag(token.type);
	if !tag_ok {
		return .UNREGISTERED_TOKEN_TYPE;
	}


	flags := token.value_flags.(u32);
	if flags & ~KNOWN_VALUE_FLAGS {
		return .UNKNOWN_VALUE_FLAGS;
	}


	origin := Byte_Span.{token.byte_start, token.byte_end};
	preceding := Byte_Span.{token.preceding_trivia_byte_start, token.byte_start};
	if (!source_slice_matches(source, token.original_text, origin)
		|| !source_slice_matches(source, token.preceding_trivia, preceding)
	) {
		return .UNMAPPED_SOURCE_SLICE;
	}


	value: Token_Value;
	if token.type == {
		case .IDENT; #through;
		case .NOTE;
			value = .{kind = .NAME, bytes = token.ident_value.name.(string).([] u8)};

		case .NUMBER;
			value = ifx flags & Parser.Value_Flags.FLOAT.(u32)
				then Token_Value.{kind = .FLOAT64_BITS, bits = (*token.float64_value).(*u64).*}
				else Token_Value.{kind = .UNSIGNED_INTEGER, bits = token.integer_value};

		case .STRING;
			value = .{kind = .STRING_BYTES, bytes = token.string_value.([] u8)};

		case;
			// Keywords copy their name; every other route, including `.ERROR` from `get_unused_token`, sets no union member.
			is_keyword := token.type >= .__FIRST_KEYWORD && token.type <= .__LAST_KEYWORD;
			value = ifx is_keyword
				then Token_Value.{kind = .NAME, bytes = token.ident_value.name.(string).([] u8)}
				else Token_Value.{kind = .NO_VALUE};
	}

	record.* = .{
		tag = tag,
		origin = origin,
		coordinates = coordinates_of(token),
		value_flags = flags,
		ident_is_backticked = token.ident_is_backticked,
		original = origin,
		preceding = preceding,
		value = value
	};
	return .NONE;
}

project_raw_diagnostic :: (record: *Raw_Diagnostic, diagnostic: *Parser.Parse_Diagnostic) -> Projection_Failure {
	expected_ok, expected := token_tag(diagnostic.expected_token);
	actual_ok, actual := token_tag(diagnostic.actual_token);
	if !expected_ok || !actual_ok {
		return .UNREGISTERED_TOKEN_TYPE;
	}


	record.* = .{
		token_span = span_observation(diagnostic.span),
		message_bytes = diagnostic.message.([] u8),
		expected_token = expected,
		actual_token = actual,
		lexer_line = diagnostic.lexer_line,
		lexer_column = diagnostic.lexer_column
	};

	if diagnostic.kind == {
		case .EXPECTED_TOKEN;			record.code = .EXPECTED_TOKEN;
		case .EXPECTED_EXPRESSION;		record.code = .EXPECTED_EXPRESSION;
		case .UNEXPECTED_TOKEN;			record.code = .UNEXPECTED_TOKEN;
		case .UNNECESSARY_SEMICOLON;	record.code = .UNNECESSARY_SEMICOLON;
		case .LEXER_ERROR;				record.code = .LEXER_ERROR;

		case;							return .UNKNOWN_PRODUCER_ENUM;
	}


	if diagnostic.severity == {
		case .ERROR;	record.severity = .ERROR;
		case .WARNING;	record.severity = .WARNING;

		case;			return .UNKNOWN_PRODUCER_ENUM;
	}


	if diagnostic.recovery_action == {
		case .NONE;					record.recovery_action = .NONE;
		case .INSERT_MISSING_TOKEN;	record.recovery_action = .INSERT_MISSING_TOKEN;
		case .SKIP_TOKENS;			record.recovery_action = .SKIP_TOKENS;

		case;						return .UNKNOWN_PRODUCER_ENUM;
	}


	record.related = NewArray(diagnostic.related_information.count, Raw_Related_Diagnostic, initialized = false);
	for diagnostic.related_information {
		record.related[it_index] = .{
			token_span = span_observation(it.span),
			message_bytes = it.message.([] u8)
		};
	}

	return .NONE;
}

// The view must lie inside `source` exactly at `expected`; an empty view may carry no pointer, so only its expected offsets are checked.
source_slice_matches :: (source: string, view: string, expected: Byte_Span) -> bool {
	if expected.start < 0 || expected.end < expected.start || expected.end > source.count {
		return false;
	}


	if expected.end - expected.start != view.count {
		return false;
	}


	return !view.count || view.data == source.data + expected.start;
}

coordinates_of :: (token: *$T) -> Coordinates {
	return .{token.l0, token.c0, token.l1, token.c1};
}

span_observation :: (span: Parser.Token_Span) -> Token_Span_Observation {
	return .{span.first.(s64), span.one_past_last.(s64)};
}
