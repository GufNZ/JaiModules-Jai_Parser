// Owned syntax snapshot (CACHE_MIGRATION_PLAN.md phase 3 step 1): one owner for source bytes, filename and every parse allocation.
// Parsed with `resolve_identifiers = false` (E6), so nothing writes into the published tree after parsing.

Owned_Syntax :: struct {
	source: string;
	filename: string;
	parsed: Parser.Parsed_Source;
	// Backs the copies, the token/diagnostic arrays, decoded token values and the parser's node pool chunks.
	storage: Pool;
}

// Copies `source` and `filename` first, so the caller's buffers can be released or overwritten immediately afterwards.
own_parse :: (source: string, filename: string) -> *Owned_Syntax {
	owned := New(Owned_Syntax);
	set_allocators(*owned.storage, context.allocator);
	push_allocator(pool_allocator_proc, *owned.storage);

	owned.source = copy_string(source);
	owned.filename = copy_string(filename);
	owned.parsed = Parser.parse_file(owned.source, owned.filename, resolve_identifiers = false);
	return owned;
}

// Must run on the allocator that was current when `own_parse` created the owner.
release_owned_syntax :: (owned: *Owned_Syntax) {
	Parser.release_parser_tree(*owned.parsed);
	Parser.release_parser_names(*owned.parsed);
	release(*owned.storage);
	free(owned);
}

SYNTAX_SNAPSHOT_SCHEMA :: "jai-cache-syntax-snapshot/1";

// The `jai-cache-syntax-snapshot/1` envelope: one exact capture, or no envelope at all if any part fails conversion.
Syntax_Snapshot :: struct {
	owner: *Owned_Syntax;
	source: string;
	// -1 only for a safely retained parse with no root, never a fabricated empty file.
	root: s64;
	nodes: [] Node_Record;
	helpers: [] Helper_Record;
	tokens: [] Token_Record;
	synthetic_tokens: [] Synthetic_Token_Record;
	recoveries: [] Recovery_Observation;
	diagnostics: [] Raw_Diagnostic;
	parse_status: Parse_Status_Observation;
	token_projection: *Token_Projection;
	node_projection: *Node_Projection;
}

project_snapshot :: (owner: *Owned_Syntax) -> Projection_Fault, *Syntax_Snapshot {
	token_fault, tokens := project_tokens(owner);
	if token_fault.failure != .NONE {
		return token_fault, null;
	}


	node_fault, nodes := project_nodes(owner);
	if node_fault.failure != .NONE {
		release_token_projection(tokens);
		return node_fault, null;
	}


	for * tokens.recoveries {
		if it.owner == .UNPUBLISHED {
			found, id := table_find(*nodes.node_ids, owner.parsed.recovery_records[it_index].owner);
			if found {
				it.owner = .NODE;
				it.owner_node_id = id;
			}
		}
	}


	snapshot := New(Syntax_Snapshot);
	snapshot.* = .{
		owner = owner,
		source = owner.source,
		root = nodes.root,
		nodes = nodes.nodes,
		helpers = nodes.helpers,
		tokens = tokens.tokens,
		synthetic_tokens = tokens.synthetic_tokens,
		recoveries = tokens.recoveries,
		diagnostics = tokens.diagnostics,
		parse_status = tokens.parse_status,
		token_projection = tokens,
		node_projection = nodes
	};

	return .{}, snapshot;
}

release_snapshot :: (snapshot: *Syntax_Snapshot) {
	release_node_projection(snapshot.node_projection);
	release_token_projection(snapshot.token_projection);
	free(snapshot);
}
