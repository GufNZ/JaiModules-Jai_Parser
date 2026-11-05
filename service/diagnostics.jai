// Diagnostics projection (phase 3 step 3): `jai-cache-syntax-diagnostics/1`, per CACHE_CONTRACTS.md "Diagnostic Origins and Declaration Index Records".
// Records keep parser emission order; origins map token spans through the owner's checked token byte offsets.

SYNTAX_DIAGNOSTICS_SCHEMA :: "jai-cache-syntax-diagnostics/1";

Origin :: struct {
	kind: enum u8 {
		SOURCE;
		INSERTED;
		UNLOCATED;
	};
	// `.SOURCE` span, or the zero-width anchor of an `.INSERTED` origin.
	span: Byte_Span;
	expected_token: Token_Tag;
	reason: enum u8 {
		NO_SOURCE_LOCATION;
		RECOVERED_LOCATION_UNAVAILABLE;
	};
}

Parser_Observation :: struct {
	token_span: Token_Span_Observation;
	expected_token: Token_Tag;
	actual_token: Token_Tag;
	recovery_action: Diagnostic_Recovery_Action;
	lexer_line: s32;
	lexer_column: s32;
}

Related_Diagnostic :: struct {
	origin: Origin;
	message_utf8: string;
}

Diagnostic_Record :: struct {
	code: Diagnostic_Code;
	severity: Diagnostic_Severity;
	primary_origin: Origin;
	message_utf8: string;
	related: [] Related_Diagnostic;
	parser_observation: Parser_Observation;
}

Diagnostics_Projection :: struct {
	owner: *Owned_Syntax;
	parse_status: Parse_Status_Observation;
	records: [] Diagnostic_Record;
	tokens: *Token_Projection;
	storage: Pool;
}

project_diagnostics :: (owner: *Owned_Syntax) -> Projection_Fault, *Diagnostics_Projection {
	token_fault, tokens := project_tokens(owner);
	if token_fault.failure != .NONE {
		return token_fault, null;
	}


	projection := New(Diagnostics_Projection);
	projection.owner = owner;
	projection.tokens = tokens;
	projection.parse_status = tokens.parse_status;
	set_allocators(*projection.storage, context.allocator);

	fault: Projection_Fault;
	{
		push_allocator(pool_allocator_proc, *projection.storage);
		fault = fill_diagnostics(projection);
	}

	if fault.failure != .NONE {
		release_diagnostics_projection(projection);
		return fault, null;
	}


	return fault, projection;
}

release_diagnostics_projection :: (projection: *Diagnostics_Projection) {
	release_token_projection(projection.tokens);
	release(*projection.storage);
	free(projection);
}

// Exact UTF-8: no overlong forms, surrogates or code points above U+10FFFF.
is_valid_utf8 :: (bytes: [] u8) -> bool {
	i := 0;
	while i < bytes.count {
		lead := bytes[i];
		length: s64;
		minimum: u32;
		code: u32;
		if lead < 0x80 {
			i += 1;
			continue;
		} else if lead & 0xE0 == 0xC0 {
			length, minimum, code = 2, 0x80, lead & 0x1F;
		} else if lead & 0xF0 == 0xE0 {
			length, minimum, code = 3, 0x800, lead & 0x0F;
		} else if lead & 0xF8 == 0xF0 {
			length, minimum, code = 4, 0x10000, lead & 0x07;
		} else {
			return false;
		}


		if i + length > bytes.count {
			return false;
		}


		for 1..length - 1 {
			continuation := bytes[i + it];
			if continuation & 0xC0 != 0x80 {
				return false;
			}


			code = (code << 6) | (continuation & 0x3F);
		}


		if code < minimum || code > 0x10FFFF || (code >= 0xD800 && code <= 0xDFFF) {
			return false;
		}


		i += length;
	}


	return true;
}

#scope_file

fill_diagnostics :: (projection: *Diagnostics_Projection) -> Projection_Fault {
	tokens := projection.tokens;
	raw := tokens.diagnostics;
	projection.records = NewArray(raw.count, Diagnostic_Record);
	for raw {
		if !is_valid_utf8(it.message_bytes) {
			return .{.INVALID_TEXT, "diagnostics", it_index};
		}


		failure, origin := primary_origin(tokens, it, it_index);
		if failure != .NONE {
			return .{failure, "diagnostics", it_index};
		}


		related := NewArray(it.related.count, Related_Diagnostic);
		for other: it.related {
			if !is_valid_utf8(other.message_bytes) {
				return .{.INVALID_TEXT, "related", it_index};
			}


			related[it_index] = .{span_origin(tokens, other.token_span), other.message_bytes.(string)};
		}


		projection.records[it_index] = .{
			code = it.code,
			severity = it.severity,
			primary_origin = origin,
			message_utf8 = it.message_bytes.(string),
			related = related,
			parser_observation = .{
				token_span = it.token_span,
				expected_token = it.expected_token,
				actual_token = it.actual_token,
				recovery_action = it.recovery_action,
				lexer_line = it.lexer_line,
				lexer_column = it.lexer_column
			}
		};
	}

	return .{};
}

// An inserted missing token maps through its one correlated recovery record and synthetic token; anything else maps its token span.
primary_origin :: (tokens: *Token_Projection, diagnostic: Raw_Diagnostic, diagnostic_index: s64) -> Projection_Failure, Origin {
	if diagnostic.recovery_action != .INSERT_MISSING_TOKEN {
		return .NONE, span_origin(tokens, diagnostic.token_span);
	}


	unlocated :: Origin.{kind = .UNLOCATED, reason = .RECOVERED_LOCATION_UNAVAILABLE};
	correlated: *Recovery_Observation;
	matches := 0;
	for * tokens.recoveries {
		if it.diagnostic_index < -1 || it.diagnostic_index >= tokens.diagnostics.count {
			return .INVALID_REFERENCE, .{};
		}


		if it.kind == .MISSING_TOKEN && it.diagnostic_index == diagnostic_index {
			correlated = it;
			matches += 1;
		}
	}


	if matches != 1 {
		return .NONE, unlocated;
	}


	synthetic_index := correlated.synthetic_token_index;
	if synthetic_index < -1 || synthetic_index >= tokens.synthetic_tokens.count {
		return .INVALID_REFERENCE, .{};
	}


	if synthetic_index == -1 {
		return .NONE, unlocated;
	}


	synthetic := tokens.synthetic_tokens[synthetic_index];
	insertion := synthetic.insertion_index;
	if insertion < 0 || insertion >= tokens.tokens.count {
		return .NONE, unlocated;
	}


	anchor := tokens.tokens[insertion].origin.start;
	return .NONE, .{kind = .INSERTED, span = .{anchor, anchor}, expected_token = synthetic.tag};
}

// A nonempty span covers its first token's start through its last token's end; an empty one is a zero-width anchor at its token.
span_origin :: (tokens: *Token_Projection, span: Token_Span_Observation) -> Origin {
	count := tokens.tokens.count;
	if span.first < 0 || span.one_past_last < span.first || span.one_past_last > count || span.first >= count {
		return .{kind = .UNLOCATED, reason = .NO_SOURCE_LOCATION};
	}


	start := tokens.tokens[span.first].origin.start;
	end := ifx span.one_past_last > span.first
		then tokens.tokens[span.one_past_last - 1].origin.end
		else start;

	return .{kind = .SOURCE, span = .{start, end}};
}
