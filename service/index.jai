// Declaration index adapter (phase 3 step 4): `jai-cache-syntax-declaration-index/1` over one `Syntax_Snapshot`, per CACHE_CONTRACTS.md and the registry's declaration-index sections.
// Snapshot node IDs are authored preorder, so walking them in order yields the declaration-event order; a compound emits its whole binding group when it is reached.
// The index borrows bytes from its snapshot and must be released first.

DECLARATION_INDEX_SCHEMA :: "jai-cache-syntax-declaration-index/1";
AUTHORED_EDGES_SCHEMA :: "jai-cache-authored-edges/1";
SYNTAX_ADAPTER_SCHEMA :: "jai-cache-syntax-adapter/1";
SYNTAX_REGISTRY_BINDING :: "jai-parser-syntax-registry/1";

Adapter_Feature :: struct {
	name: string;
	method: string;
	observation_schema: string;
}

// The five capability features in the registry's table order.
SYNTAX_ADAPTER_FEATURES :: Adapter_Feature.[
	.{"authored_edges",				"CAPTURED",			AUTHORED_EDGES_SCHEMA},
	.{"builder_function_routes",	"RECONSTRUCTED",	"jai-parser-route-correlation/1"},
	.{"compound_routes",			"CAPTURED",			"jai-parser-compound-tokens/1"},
	.{"name_origins",				"RECONSTRUCTED",	"jai-parser-name-correlation/1"},
	.{"metadata_origins",			"RECONSTRUCTED",	"jai-parser-metadata-correlation/1"}
];

// `K("syntax-adapter", [schema_id, registry_binding, K(feature_name, [method_tag, observation_schema])...])`.
syntax_adapter_descriptor :: () -> [] u8 {
	fields: [SYNTAX_ADAPTER_FEATURES.count + 2] [] u8;
	fields[0] = SYNTAX_ADAPTER_SCHEMA.([] u8);
	fields[1] = SYNTAX_REGISTRY_BINDING.([] u8);
	for SYNTAX_ADAPTER_FEATURES {
		fields[it_index + 2] = make_key(it.name, it.method.([] u8), it.observation_schema.([] u8));
	}

	return make_key("syntax-adapter", ..fields);
}

Coverage_Code :: enum u8 {
	UNAVAILABLE_OBSERVATION;
	UNMAPPED_NODE_KIND;
	UNMAPPED_FIELD;
	UNCLASSIFIED_ROUTE;
	UNMAPPED_ORIGIN;
	UNMAPPED_NAME;
	UNCORRELATED_METADATA;
	UNKNOWN_VISIBILITY;
	UNPROVEN_CHILD_ORDER;
	OPAQUE_SYNTAX;
	UNREGISTERED_SHARING;
}

// A set whose bit order is the registry's impact order, so its members are nonduplicated and ordered by construction.
Coverage_Impact :: enum_flags u8 {
	DECLARATION_SET;
	CONTAINMENT;
	NAMES;
	SOURCE_MAPPING;
	VISIBILITY;
	ORDER;
	METADATA;
	RECOVERY;
}

Coverage_Subject :: struct {
	kind: enum u8 {
		DOCUMENT;
		NODE;
	};
	local_node_id: u64;
}

Coverage_Reason :: struct {
	code: Coverage_Code;
	subject: Coverage_Subject;
	field_path: [] Path_Step;
	impacts: Coverage_Impact;
	// Null when no origin is available.
	origin: *Origin;
	detail_utf8: string;
}

Entry_Name :: struct {
	kind: enum u8 {
		SPELLED;
		ANONYMOUS;
		MISSING;
		UNMAPPED;
	};
	// Always `.SOURCE` for `.SPELLED`; the insertion or unlocated origin for `.MISSING`.
	origin: Origin;
	spelling_bytes: [] u8;
	// `.SPELLED` and `.UNMAPPED`.
	producer_name_bytes: [] u8;
	form: enum u8 {
		IDENTIFIER;
		OPERATOR;
	};
	recovery_origins: [] Origin;
	// `.UNMAPPED` only.
	reason: Coverage_Reason;
}

Container :: struct {
	kind: enum u8 {
		ROOT;
		DECLARATION;
		SHARED_REGION;
	};
	// Entry ID for `.DECLARATION`, region ID for `.SHARED_REGION`.
	local_id: u64;
}

operator == :: (a: Container, b: Container) -> bool {
	return a.kind == b.kind && a.local_id == b.local_id;
}

Scope_Directive_Tag :: enum u8 {
	UNSPECIFIED;
	SCOPE_EXPORT;
	SCOPE_MODULE;
	SCOPE_FILE;
	RECOVERED_UNKNOWN;
}

// Snapshot node IDs; -1 means not set.
Scope_Basis :: struct {
	statement_list_node_id: s64 = -1;
	preceding_directive_node_id: s64 = -1;
}

Visibility_Syntax :: struct {
	scope_directive: Scope_Directive_Tag;
	scope_basis: Scope_Basis;
	observations: [] Origin;
}

Program_Export_Name :: struct {
	origin: Origin;
	value_bytes: [] u8;
}

Program_Export_Occurrence :: struct {
	marker_origin: Origin;
	// Null when no string token follows the marker.
	name_argument: *Program_Export_Name;
}

Recovery_Status :: struct {
	kind: enum u8 {
		PARSED;
		RECOVERED;
		UNCLASSIFIED;
	};
	// `.UNCLASSIFIED` only.
	reason: Coverage_Reason;
}

Index_Entry :: struct {
	local_entry_id: u64;
	declaration_node_id: u64;
	name: Entry_Name;
	syntax_kind: enum u8 {
		DECLARATION;
		COMPOUND_BINDING;
		ENUM_MEMBER;
	};
	declaration_origin: Origin;
	container: Container;
	visibility_syntax: Visibility_Syntax;
	// Null when the declaration has no `#program_export` prefix.  Every binding of one compound shares one occurrence.
	program_export_syntax: *Program_Export_Occurrence;
	recovery_status: Recovery_Status;
}

Shared_Region :: struct {
	local_region_id: u64;
	compound_node_id: u64;
	parent_container: Container;
	binding_entries: [] u64;
}

Index_Coverage :: struct {
	kind: enum u8 {
		COMPLETE_SYNTAX_TRAVERSAL;
		PARTIAL_SYNTAX_TRAVERSAL;
	};
	reasons: [] Coverage_Reason;
}

Declaration_Index :: struct {
	snapshot: *Syntax_Snapshot;
	coverage: Index_Coverage;
	entries: [] Index_Entry;
	shared_regions: [] Shared_Region;
	storage: Pool;
}

project_declaration_index :: (snapshot: *Syntax_Snapshot) -> Projection_Fault, *Declaration_Index {
	index := New(Declaration_Index);
	index.snapshot = snapshot;
	set_allocators(*index.storage, context.allocator);

	fault: Projection_Fault;
	{
		push_allocator(pool_allocator_proc, *index.storage);
		fault = fill_declaration_index(index);
	}

	if fault.failure != .NONE {
		release_declaration_index(index);
		return fault, null;
	}


	return fault, index;
}

release_declaration_index :: (index: *Declaration_Index) {
	release(*index.storage);
	free(index);
}

#scope_file

Index_Builder :: struct {
	snapshot: *Syntax_Snapshot;

	// Owning node, top-level owning field and that field's list position (-1 when not a list element), per node ID.
	parents: [] s64;
	edges: [] string;
	edge_elements: [] s64;
	path: [..] Path_Step;

	// Container of the node itself, and the container its owned children inherit.
	outer: [] Container;
	inner: [] Container;
	region_ids: [] s64;

	// Nearest owning statement list and the position of the statement containing the node, or -1.
	anchor_lists: [] s64;
	anchor_positions: [] s64;
	enum_mode: [] bool;

	// Per statement list: the last direct scope directive reached so far in preorder.
	last_directive: [] s64;

	// Entry of an ordinary declaration or bare enum member node, or -1.
	entry_of_node: [] s64;
	entries: [..] Index_Entry;
	regions: [..] Shared_Region;
	reasons: [..] Coverage_Reason;
	fault: Projection_Fault;
}

Name_Pair :: struct {
	key: string;
	token: string;
}

// Multi-character operator-declaration names from `parse_operator_declaration_name`, with the token each consumes.
NAMED_OPERATOR_SPELLINGS :: Name_Pair.[
	.{"==",		"ISEQUAL"},
	.{"!=",		"ISNOTEQUAL"},
	.{"<=",		"LESSEQUALS"},
	.{">=",		"GREATEREQUALS"},
	.{"&&",		"LOGICAL_AND"},
	.{"||",		"LOGICAL_OR"},
	.{"<<",		"SHIFT_LEFT"},
	.{">>",		"SHIFT_RIGHT"},
	.{"<<<",	"ROTATE_LEFT"},
	.{">>>",	"ROTATE_RIGHT"},
	.{"+=",		"PLUSEQUALS"},
	.{"-=",		"MINUSEQUALS"},
	.{"*=",		"TIMESEQUALS"},
	.{"/=",		"DIVEQUALS"},
	.{"%=",		"MODEQUALS"},
	.{"<<=",	"SHIFT_LEFT_EQUALS"},
	.{">>=",	"SHIFT_RIGHT_EQUALS"},
	.{"<<<=",	"ROTATE_LEFT_EQUALS"},
	.{">>>=",	"ROTATE_RIGHT_EQUALS"},
	.{"&=",		"BITWISE_AND_EQUALS"},
	.{"|=",		"BITWISE_OR_EQUALS"},
	.{"^=",		"BITWISE_XOR_EQUALS"},
	.{"&&=",	"LOGICAL_AND_EQUALS"},
	.{"||=",	"LOGICAL_OR_EQUALS"}
];

SINGLE_CHARACTER_OPERATORS :: "+-*/%<>=.!~&|^";

// Compound assignment operators (`operator_type` names) and the shared operator token each records.
ASSIGNMENT_OPERATOR_TOKENS :: Name_Pair.[
	.{"PLUS_ASSIGN",			"PLUSEQUALS"},
	.{"MINUS_ASSIGN",			"MINUSEQUALS"},
	.{"TIMES_ASSIGN",			"TIMESEQUALS"},
	.{"DIV_ASSIGN",				"DIVEQUALS"},
	.{"MOD_ASSIGN",				"MODEQUALS"},
	.{"SHIFT_LEFT_ASSIGN",		"SHIFT_LEFT_EQUALS"},
	.{"SHIFT_RIGHT_ASSIGN",		"SHIFT_RIGHT_EQUALS"},
	.{"ROTATE_LEFT_ASSIGN",		"ROTATE_LEFT_EQUALS"},
	.{"ROTATE_RIGHT_ASSIGN",	"ROTATE_RIGHT_EQUALS"},
	.{"BITWISE_AND_ASSIGN",		"BITWISE_AND_EQUALS"},
	.{"BITWISE_OR_ASSIGN",		"BITWISE_OR_EQUALS"},
	.{"BITWISE_XOR_ASSIGN",		"BITWISE_XOR_EQUALS"},
	.{"LOGICAL_AND_ASSIGN",		"LOGICAL_AND_EQUALS"},
	.{"LOGICAL_OR_ASSIGN",		"LOGICAL_OR_EQUALS"}
];

RECOVERY_ATTRIBUTION_DETAIL :: "A recovery event's recorded owner is not part of the published syntax, so it cannot be attributed to declarations.";
AMBIGUOUS_RECOVERY_DETAIL :: "A recovery event at this declaration's first token may have been recorded before or after its builder began.";

fill_declaration_index :: (index: *Declaration_Index) -> Projection_Fault {
	b: Index_Builder;
	b.snapshot = index.snapshot;
	nodes := b.snapshot.nodes;
	count := nodes.count;
	b.parents = NewArray(count, s64);
	b.edges = NewArray(count, string);
	b.edge_elements = NewArray(count, s64);
	b.outer = NewArray(count, Container);
	b.inner = NewArray(count, Container);
	b.region_ids = NewArray(count, s64);
	b.anchor_lists = NewArray(count, s64);
	b.anchor_positions = NewArray(count, s64);
	b.enum_mode = NewArray(count, bool);
	b.last_directive = NewArray(count, s64);
	b.entry_of_node = NewArray(count, s64);
	for 0..count - 1 {
		b.parents[it] = -1;
		b.last_directive[it] = -1;
		b.entry_of_node[it] = -1;
	}

	for record, id: nodes {
		for record.fields {
			b.path.count = 0;
			for step: it.path {
				array_add(*b.path, step);
			}

			link(*b, it.value, id);
		}

		if b.fault.failure != .NONE {
			return b.fault;
		}
	}


	for record, id: nodes {
		parent := b.parents[id];
		edge := b.edges[id];
		parent_kind: string;
		if id == 0 {
			b.anchor_lists[id] = -1;
			b.anchor_positions[id] = -1;
		} else {
			if parent < 0 {
				return .{.INVALID_REFERENCE, "nodes", id};
			}


			parent_kind = nodes[parent].kind;
			b.outer[id] = ifx parent_kind == "COMPOUND_DECLARATION" && edge != "comma_separated_assignment"
				then Container.{kind = .SHARED_REGION, local_id = xx b.region_ids[parent]}
				else b.inner[parent];

			if parent_kind == "BLOCK" && edge == "statements" {
				b.anchor_lists[id] = parent;
				b.anchor_positions[id] = b.edge_elements[id];
			} else {
				b.anchor_lists[id] = b.anchor_lists[parent];
				b.anchor_positions[id] = b.anchor_positions[parent];
			}
		}

		b.inner[id] = b.outer[id];
		direct_statement := parent_kind == "BLOCK" && edge == "statements";
		if record.kind == {
			case "DECLARATION";
				// A compound's shared properties are a helper declaration, not an entry.
				if parent_kind != "COMPOUND_DECLARATION" || edge != "declaration_properties" {
					entry := emit_declaration(*b, id);
					b.inner[id] = .{kind = .DECLARATION, local_id = entry};
					b.entry_of_node[id] = xx entry;
				}

			case "COMPOUND_DECLARATION";
				emit_compound(*b, id);

			case "IDENT";
				if direct_statement && b.enum_mode[parent] {
					emit_enum_member(*b, id);
				}

			case "BLOCK";
				b.enum_mode[id] = is_enum_member_block(*b, id);

			case "DIRECTIVE_SCOPE";
				if direct_statement {
					b.last_directive[parent] = id;
				}
		}

		if b.fault.failure != .NONE {
			return b.fault;
		}
	}


	attribute_recoveries(*b);
	if b.fault.failure != .NONE {
		return b.fault;
	}


	index.entries = b.entries;
	index.shared_regions = b.regions;
	index.coverage = .{
		kind = ifx b.reasons.count then .PARTIAL_SYNTAX_TRAVERSAL else .COMPLETE_SYNTAX_TRAVERSAL,
		reasons = b.reasons
	};
	return .{};
}

// Records each node's single owner and owning field, looking through helper records.
link :: (b: *Index_Builder, value: Field_Value, owner: s64) {
	nodes := b.snapshot.nodes;
	if value.kind == {
		case .LIST;
			for value.elements {
				array_add(*b.path, .{kind = .ELEMENT, index = it_index});
				link(b, it, owner);
				b.path.count -= 1;
			}

		case .NODE;
			child := value.signed;
			if child == -1 {
				return;
			}


			if value.relationship == .ALIAS {
				if child < 0 || child >= nodes.count {
					fail(b, .INVALID_REFERENCE, "nodes", owner);
				}

				return;
			}


			if child <= owner || child >= nodes.count || b.parents[child] != -1 {
				fail(b, .INVALID_REFERENCE, "nodes", owner);
				return;
			}


			b.parents[child] = owner;
			b.edges[child] = b.path[0].name;
			b.edge_elements[child] = ifx b.path.count > 1 && b.path[1].kind == .ELEMENT
				then b.path[1].index
				else -1;

		case .HELPER;
			helper := value.signed;
			if helper == -1 {
				return;
			}


			if helper < 0 || helper >= b.snapshot.helpers.count {
				fail(b, .INVALID_REFERENCE, "helpers", owner);
				return;
			}


			saved := b.path.count;
			for b.snapshot.helpers[helper].fields {
				for step: it.path {
					array_add(*b.path, step);
				}

				link(b, it.value, owner);
				b.path.count = saved;
			}
	}
}

fail :: (b: *Index_Builder, failure: Projection_Failure, record: string, index: s64) {
	if b.fault.failure == .NONE {
		b.fault = .{failure, record, index};
	}
}

field_of :: (fields: [] Field_Observation, first: string, second := "") -> Field_Value {
	length := ifx second.count then 2 else 1;
	for fields {
		if it.path.count == length && it.path[0].name == first && (length == 1 || it.path[1].name == second) {
			return it.value;
		}
	}


	return .{kind = .INACTIVE};
}

has_name :: (value: Field_Value, name: string) -> bool {
	return array_find(value.names, name);
}

add_reason :: (b: *Index_Builder, code: Coverage_Code, subject_node: s64, impacts: Coverage_Impact, detail: string, path: .. string) -> Coverage_Reason {
	reason := Coverage_Reason.{
		code = code,
		subject = .{kind = .NODE, local_node_id = xx subject_node},
		impacts = impacts,
		detail_utf8 = detail
	};
	reason.field_path = NewArray(path.count, Path_Step);
	for path {
		reason.field_path[it_index] = .{kind = .FIELD, name = it};
	}

	array_add(*b.reasons, reason);
	return reason;
}

add_entry :: (b: *Index_Builder, entry: Index_Entry) -> u64 {
	id := b.entries.count.(u64);
	array_add(*b.entries, entry);
	b.entries[id].local_entry_id = id;
	return id;
}

token_is :: (b: *Index_Builder, index: s64, tag: Token_Tag) -> bool {
	return index >= 0 && index < b.snapshot.tokens.count && b.snapshot.tokens[index].tag == tag;
}

byte_tag :: (character: u8) -> Token_Tag {
	return .{kind = .BYTE_CHAR, byte = character};
}

named_tag :: (name: string) -> Token_Tag {
	return .{kind = .NAMED, name = name};
}

identifier_is :: (b: *Index_Builder, index: s64, name: string) -> bool {
	return token_is(b, index, named_tag("IDENT")) && b.snapshot.tokens[index].value.bytes.(string) == name;
}

// Origin from the first token's start through the last token's end, both indices already checked.
token_origin :: (b: *Index_Builder, first: s64, last: s64) -> Origin {
	tokens := b.snapshot.tokens;
	return .{kind = .SOURCE, span = .{tokens[first].origin.start, tokens[last].origin.end}};
}

node_origin :: (b: *Index_Builder, id: s64) -> Origin {
	record := *b.snapshot.nodes[id];
	return ifx record.has_origin
		then Origin.{kind = .SOURCE, span = record.origin}
		else Origin.{kind = .UNLOCATED, reason = .NO_SOURCE_LOCATION};
}

declaration_origin :: (b: *Index_Builder, id: s64) -> Origin {
	origin := node_origin(b, id);
	if origin.kind != .SOURCE {
		add_reason(b, .UNMAPPED_ORIGIN, id, .SOURCE_MAPPING, "The declaration has no mapped source span.");
	}

	return origin;
}

spelled_name :: (b: *Index_Builder, first: s64, last: s64, producer: [] u8, form: type_of(Entry_Name.form)) -> Entry_Name {
	origin := token_origin(b, first, last);
	source := b.snapshot.source;
	spelling := string.{origin.span.end - origin.span.start, source.data + origin.span.start};
	return .{kind = .SPELLED, origin = origin, spelling_bytes = xx spelling, producer_name_bytes = producer, form = form};
}

unmapped_name :: (b: *Index_Builder, id: s64, producer: [] u8, path: .. string) -> Entry_Name {
	reason := add_reason(b, .UNMAPPED_NAME, id, .NAMES | .SOURCE_MAPPING, "The name's source tokens could not be correlated with its producer value.", ..path);
	return .{kind = .UNMAPPED, producer_name_bytes = producer, reason = reason};
}

visibility_of :: (b: *Index_Builder, id: s64) -> Visibility_Syntax {
	list := b.anchor_lists[id];
	if list < 0 {
		return .{};
	}


	directive := b.last_directive[list];
	if directive < 0 {
		return .{scope_basis = .{statement_list_node_id = list}};
	}


	tag: Scope_Directive_Tag;
	scope_type := field_of(b.snapshot.nodes[directive].fields, "scope_type");
	if scope_type.name == {
		case "EXPORT";		tag = .SCOPE_EXPORT;
		case "INTERNAL";	tag = .SCOPE_MODULE;
		case "FILE";		tag = .SCOPE_FILE;

		case;
			tag = .RECOVERED_UNKNOWN;
			add_reason(b, .UNKNOWN_VISIBILITY, directive, .VISIBILITY, "The scope directive has no registered tag.", "scope_type");
	}

	observations := NewArray(1, Origin);
	observations[0] = node_origin(b, directive);
	return .{
		scope_directive = tag,
		scope_basis = .{statement_list_node_id = list, preceding_directive_node_id = directive},
		observations = observations
	};
}

// The `parse_declaration_node` prefix: `#program_export ["name"]`, `#no_reset`, then `$` or `$$`.
// Returns the first token after it, the export occurrence and whether the prefix agrees with the recorded flags.
// An uncorrelated export marker reports partial metadata.
correlate_prefix :: (b: *Index_Builder, id: s64, first: s64, flags: Field_Value, export_name: [] u8) -> (next_token: s64, program_export: *Program_Export_Occurrence, prefix_ok: bool) {
	i := first;
	export: *Program_Export_Occurrence;
	marked := token_is(b, i, byte_tag(#char "#")) && identifier_is(b, i + 1, "program_export");
	if marked {
		export = New(Program_Export_Occurrence);
		export.marker_origin = token_origin(b, i, i + 1);
		i += 2;
		if token_is(b, i, named_tag("STRING")) {
			export.name_argument = New(Program_Export_Name);
			export.name_argument.* = .{origin = token_origin(b, i, i), value_bytes = b.snapshot.tokens[i].value.bytes};
			i += 1;
		}
	}

	argument: [] u8;
	if export && export.name_argument {
		argument = export.name_argument.value_bytes;
	}

	if marked != has_name(flags, "PROGRAM_EXPORT") || !bytes_equal(argument, export_name) {
		add_reason(b, .UNCORRELATED_METADATA, id, .METADATA, "The program-export flag, marker tokens and name value disagree.", "program_export_name");
		export = null;
	}

	if token_is(b, i, byte_tag(#char "#")) && identifier_is(b, i + 1, "no_reset") {
		if !has_name(flags, "NO_RESET") {
			return i, export, false;
		}


		i += 2;
	}

	required := has_name(flags, "AUTO_VALUE_BAKE_IS_REQUIRED");
	baked := has_name(flags, "AUTO_VALUE_BAKE");
	if token_is(b, i, byte_tag(#char "$")) {
		return i + 1, export, required;
	}


	if token_is(b, i, named_tag("DOUBLE_DOLLAR")) {
		return i + 1, export, baked && !required;
	}


	return i, export, !baked;
}

// The last name token of an operator declaration starting at `first`, or -1 when the tokens do not spell the producer's name.
operator_name_end :: (b: *Index_Builder, first: s64, name: string) -> s64 {
	open := token_is(b, first, byte_tag(#char "[")) && token_is(b, first + 1, byte_tag(#char "]"));
	if name == {
		case "*[]";
			star := token_is(b, first, byte_tag(#char "*")) && token_is(b, first + 1, byte_tag(#char "[")) && token_is(b, first + 2, byte_tag(#char "]"));
			return ifx star then first + 2 else -1;

		case "[]=";
			return ifx open && token_is(b, first + 2, byte_tag(#char "=")) then first + 2 else -1;

		case "[]";
			return ifx open && !token_is(b, first + 2, byte_tag(#char "=")) then first + 1 else -1;
	}


	if name.count == 1 && find_index_from_left(SINGLE_CHARACTER_OPERATORS, name[0]) >= 0 {
		return ifx token_is(b, first, byte_tag(name[0])) then first else -1;
	}


	for NAMED_OPERATOR_SPELLINGS {
		if it.key == name {
			return ifx token_is(b, first, named_tag(it.token)) then first else -1;
		}
	}


	return -1;
}

// Each kept event marks the entries on its owner's ownership path.
// A compound's target subtree reaches only its outer context; its own syntax and shared payload reach every binding.
// Events outside every published node affect no entry.
attribute_recoveries :: (b: *Index_Builder) {
	nodes := b.snapshot.nodes;
	recoveries := b.snapshot.recoveries;
	for recoveries {
		if !it.discarded && it.owner == .UNPUBLISHED {
			// Without a published owner no entry can be shown free of this event.
			if b.entries.count {
				reason := Coverage_Reason.{code = .UNCLASSIFIED_ROUTE, impacts = .RECOVERY, detail_utf8 = RECOVERY_ATTRIBUTION_DETAIL};
				array_insert_at(*b.reasons, reason, 0);
				for * b.entries {
					it.recovery_status = .{kind = .UNCLASSIFIED, reason = reason};
				}
			}

			return;
		}
	}


	for recoveries {
		if it.discarded || it.owner != .NODE {
			continue;
		}


		if it.owner_node_id < 0 || it.owner_node_id >= nodes.count {
			fail(b, .INVALID_REFERENCE, "recoveries", it_index);
			return;
		}


		child := -1;
		node := it.owner_node_id;
		while node >= 0 {
			entry := b.entry_of_node[node];
			if entry >= 0 {
				b.entries[entry].recovery_status.kind = .RECOVERED;
			}

			if nodes[node].kind == "COMPOUND_DECLARATION" && (child < 0 || b.edges[child] != "comma_separated_assignment") {
				for binding: b.regions[b.region_ids[node]].binding_entries {
					b.entries[binding].recovery_status.kind = .RECOVERED;
				}
			}

			child = node;
			node = b.parents[node];
		}
	}


	// An event recorded at a descendant declaration's first token, without covering earlier tokens, may belong to either builder.
	for event: recoveries {
		if event.discarded || event.owner != .NODE || event.token_span.first < event.cursor {
			continue;
		}


		for * entry: b.entries {
			node := entry.declaration_node_id.(s64);
			if entry.recovery_status.kind != .PARSED || nodes[node].token_span.first != event.cursor || node == event.owner_node_id {
				continue;
			}


			ancestor := b.parents[node];
			while ancestor >= 0 && ancestor != event.owner_node_id {
				ancestor = b.parents[ancestor];
			}

			if ancestor >= 0 {
				reason := add_reason(b, .UNCLASSIFIED_ROUTE, node, .RECOVERY, AMBIGUOUS_RECOVERY_DETAIL);
				entry.recovery_status = .{kind = .UNCLASSIFIED, reason = reason};
			}
		}
	}
}

emit_declaration :: (b: *Index_Builder, id: s64) -> u64 {
	record := *b.snapshot.nodes[id];
	parent := b.parents[id];
	edge := b.edges[id];
	producer := field_of(record.fields, "entry", "name").bytes;
	flags := field_of(record.fields, "flags");
	header_slot := parent >= 0 && b.snapshot.nodes[parent].kind == "PROCEDURE_HEADER" && (edge == "arguments" || edge == "returns");

	name: Entry_Name;
	export: *Program_Export_Occurrence;
	if !producer.count {
		if header_slot && is_anonymous_slot(b, id) {
			name.kind = .ANONYMOUS;
			if has_name(flags, "PROGRAM_EXPORT") {
				add_reason(b, .UNCORRELATED_METADATA, id, .METADATA, "An unnamed slot carries a program-export flag.", "flags");
			}
		} else {
			name = unmapped_name(b, id, producer, "entry", "name");
		}
	} else {
		first := record.token_span.first;
		next, occurrence, prefix_ok := correlate_prefix(b, id, first, flags, field_of(record.fields, "program_export_name").bytes);
		export = occurrence;

		last := -1;
		form: type_of(Entry_Name.form);
		start := next;
		if prefix_ok && token_is(b, next, named_tag("KEYWORD_OPERATOR")) {
			form = .OPERATOR;
			start = next + 1;
			last = operator_name_end(b, start, producer.(string));
		} else if prefix_ok && identifier_is(b, next, producer.(string)) {
			last = next;
		}

		// `parse_declaration_node` requires `:` after the name; a quick-lambda parameter is a bare identifier with no prefix.
		quick := header_slot && edge == "arguments" && next == first && form == .IDENTIFIER;
		if last >= 0 && (token_is(b, last + 1, byte_tag(#char ":")) || quick) {
			name = spelled_name(b, start, last, producer, form);
		} else {
			name = unmapped_name(b, id, producer, "entry", "name");
		}
	}

	return add_entry(
		b,
		.{
			declaration_node_id = xx id,
			name = name,
			syntax_kind = .DECLARATION,
			declaration_origin = declaration_origin(b, id),
			container = b.outer[id],
			visibility_syntax = visibility_of(b, id),
			program_export_syntax = export
		}
	);
}

// An unnamed type-only parameter or return slot: its declaration starts at its type and has no value.
is_anonymous_slot :: (b: *Index_Builder, id: s64) -> bool {
	record := *b.snapshot.nodes[id];
	type_inst := field_of(record.fields, "type_inst");
	expression := field_of(record.fields, "expression");
	return type_inst.kind == .NODE && type_inst.signed > id && expression.kind == .NODE && expression.signed == -1
		&& b.snapshot.nodes[type_inst.signed].token_span.first == record.token_span.first;
}

// Declared targets follow the recorded tokens: `.DECLARE`, or no modifier under a shared `:`.
emit_compound :: (b: *Index_Builder, id: s64) {
	nodes := b.snapshot.nodes;
	tokens := b.snapshot.tokens;
	record := *nodes[id];
	comma := field_of(record.fields, "comma_separated_assignment").signed;
	properties := field_of(record.fields, "declaration_properties").signed;
	if comma <= id || properties <= id || comma >= nodes.count || properties >= nodes.count {
		fail(b, .INVALID_REFERENCE, "nodes", id);
		return;
	}


	shared := field_of(record.fields, "operator_type").tag;
	operator_token := field_of(record.fields, "operator_token").signed;
	declares := shared == byte_tag(0);
	expected: Token_Tag;
	if declares {
		expected = byte_tag(#char ":");
	} else if shared == byte_tag(#char "=") {
		expected = shared;
	} else {
		for ASSIGNMENT_OPERATOR_TOKENS {
			if shared == named_tag(it.key) {
				expected = named_tag(it.token);
			}
		}
	}

	// -1 means recovery inserted the shared `:`.
	if (operator_token == -1 && !declares) || (operator_token != -1 && !token_is(b, operator_token, expected)) {
		fail(b, .CONFLICTING_EVIDENCE, "operator_token", id);
		return;
	}


	properties_record := *nodes[properties];
	flags := field_of(properties_record.fields, "flags");
	_, export := correlate_prefix(b, properties, record.token_span.first, flags, field_of(properties_record.fields, "program_export_name").bytes);

	region_id := b.regions.count;
	b.region_ids[id] = region_id;
	bindings: [..] u64;
	arguments := field_of(nodes[comma].fields, "arguments").elements;
	for value: arguments {
		if value.kind != .HELPER || value.signed < 0 || value.signed >= b.snapshot.helpers.count {
			fail(b, .INVALID_REFERENCE, "helpers", id);
			return;
		}


		helper := b.snapshot.helpers[value.signed].fields;
		target := field_of(helper, "node").signed;
		modifier := field_of(helper, "modifier").name;
		modifier_token := field_of(helper, "modifier_token").signed;
		separator_token := field_of(helper, "separator_token").signed;
		modifier_ok := ifx modifier == "DECLARE"
			then token_is(b, modifier_token, byte_tag(#char ":"))
			else ifx modifier == "ASSIGN"
				then token_is(b, modifier_token, byte_tag(#char "="))
				else modifier_token == -1;

		// The last target has no separator unless recovery stopped after its comma.
		separator_ok := (
			token_is(b, separator_token, byte_tag(#char ","))
			|| (separator_token == -1 && it_index == arguments.count - 1)
		);
		if !modifier_ok || !separator_ok || target <= comma || target >= nodes.count {
			fail(b, .CONFLICTING_EVIDENCE, "Parser_Comma_Separated_Argument", value.signed);
			return;
		}


		declared := modifier == "DECLARE" || (modifier == "NONE" && declares);
		// The builder diagnoses a declared target that is not an identifier and binds nothing for it.
		if !declared || nodes[target].kind != "IDENT" {
			continue;
		}


		target_record := *nodes[target];
		producer := field_of(target_record.fields, "name").bytes;
		span := target_record.token_span;
		name := ifx span.one_past_last == span.first + 1 && identifier_is(b, span.first, producer.(string))
			then spelled_name(b, span.first, span.first, producer, .IDENTIFIER)
			else unmapped_name(b, target, producer, "name");

		entry := add_entry(b, .{
			declaration_node_id = xx id,
			name = name,
			syntax_kind = .COMPOUND_BINDING,
			declaration_origin = node_origin(b, id),
			container = b.outer[id],
			visibility_syntax = visibility_of(b, id),
			program_export_syntax = export
		});
		array_add(*bindings, entry);
	}

	if !record.has_origin {
		add_reason(b, .UNMAPPED_ORIGIN, id, .SOURCE_MAPPING, "The compound declaration has no mapped source span.");
	}

	array_add(*b.regions, .{
		local_region_id = xx region_id,
		compound_node_id = xx id,
		parent_container = b.outer[id],
		binding_entries = bindings
	});
}

// `parse_enum_member` builds a bare member from exactly `IDENT ;`.
emit_enum_member :: (b: *Index_Builder, id: s64) {
	record := *b.snapshot.nodes[id];
	producer := field_of(record.fields, "name").bytes;
	first := record.token_span.first;
	if record.token_span.one_past_last != first + 1 || !identifier_is(b, first, producer.(string)) || !token_is(b, first + 1, byte_tag(#char ";")) {
		add_reason(b, .UNCLASSIFIED_ROUTE, id, .DECLARATION_SET | .NAMES, "An identifier statement in an enum body lacks bare-member evidence.");
		return;
	}


	add_entry(
		b,
		.{
			declaration_node_id = xx id,
			name = spelled_name(b, first, first, producer, .IDENTIFIER),
			syntax_kind = .ENUM_MEMBER,
			declaration_origin = declaration_origin(b, id),
			container = b.outer[id],
			visibility_syntax = visibility_of(b, id)
		}
	);

	b.entry_of_node[id] = b.entries.count - 1;
}

// Enum-member mode runs along the enum body and the branches of non-switch static ifs that are direct statements of such a block.
is_enum_member_block :: (b: *Index_Builder, id: s64) -> bool {
	parent := b.parents[id];
	if parent < 0 {
		return false;
	}


	nodes := b.snapshot.nodes;
	edge := b.edges[id];
	if nodes[parent].kind == "ENUM" {
		return edge == "block";
	}


	if nodes[parent].kind != "IF" || (edge != "then_block" && edge != "else_block") {
		return false;
	}


	flags := field_of(nodes[parent].fields, "if_flags");
	statement_list := b.parents[parent];
	return has_name(flags, "IS_STATIC") && !has_name(flags, "IS_SWITCH_STATEMENT")
		&& statement_list >= 0 && nodes[statement_list].kind == "BLOCK" && b.edges[parent] == "statements"
		&& b.enum_mode[statement_list];
}
