// Snapshot projection, part 2 (phase 3 step 2): node and helper records under `jai-cache-authored-nodes/1`.
// Field roles, child order and active-form guards follow CACHE_SYNTAX_REGISTRY.md's per-layout tables.
// Kinds not registered here fail conversion.
// Node IDs follow first owning-edge encounter in a depth-first preorder walk; helper IDs follow first helper-field encounter in the same walk.

AUTHORED_NODES_SCHEMA :: "jai-cache-authored-nodes/1";

Path_Step :: struct {
	kind: enum u8 {
		FIELD;
		ELEMENT;
	};
	name: string;
	index: s64;
}

Field_Value :: struct {
	kind: enum u8 {
		INACTIVE;
		BOOL;
		SIGNED;
		UNSIGNED;
		FLOAT64_BITS;
		BYTES;
		TOKEN_TAG;
		OPERATOR;
		ENUM;
		FLAGS;
		NODE;
		HELPER;
		LIST;
		TOKEN_SPAN;
		SOURCE_NULL;
	};
	relationship: enum u8 {
		OWNED;
		ALIAS;
	};
	boolean: bool;
	// `.SIGNED` value, or the referenced ID for `.NODE` and `.HELPER` (-1 when the pointer is null).
	signed: s64;
	// `.UNSIGNED` value or `.FLOAT64_BITS` bits.
	unsigned: u64;
	bytes: [] u8;
	// `.TOKEN_TAG` tag, or for `.OPERATOR` a byte character or a declared `Operator_Type` name.
	tag: Token_Tag;
	domain: string;
	name: string;
	names: [] string;
	elements: [] Field_Value;
	span: Token_Span_Observation;
}

Field_Observation :: struct {
	path: [] Path_Step;
	value: Field_Value;
}

Node_Record :: struct {
	local_node_id: u64;
	kind: string;
	coordinates: Coordinates;
	token_span: Token_Span_Observation;
	has_origin: bool;
	origin: Byte_Span;
	fields: [] Field_Observation;
}

Helper_Record :: struct {
	local_helper_id: u64;
	layout: string;
	fields: [] Field_Observation;
}

Node_Projection :: struct {
	owner: *Owned_Syntax;
	root: s64;
	nodes: [] Node_Record;
	helpers: [] Helper_Record;

	// Producer node pointer to its snapshot ID.
	node_ids: Table(*void, s64);
	storage: Pool;
}

project_nodes :: (owner: *Owned_Syntax) -> Projection_Fault, *Node_Projection {
	projection := New(Node_Projection);
	projection.owner = owner;
	set_allocators(*projection.storage, context.allocator);

	fault: Projection_Fault;
	{
		push_allocator(pool_allocator_proc, *projection.storage);
		fault = fill_node_projection(projection);
	}

	if fault.failure != .NONE {
		release_node_projection(projection);
		return fault, null;
	}


	return fault, projection;
}

release_node_projection :: (projection: *Node_Projection) {
	release(*projection.storage);
	free(projection);
}

#scope_file

Helper_Layout :: enum u8 {
	NONE;
	ARGUMENT;
	CONTEXT_MODIFICATION;
	COMMA_SEPARATED_ARGUMENT;
	STRUCT_LITERAL_INFO;
	ARRAY_LITERAL_INFO;
	ASM_FEATURE;
	ASM_STATEMENT;
	ASM_INSTRUCTION;
	ASM_MNEMONIC_SIZE;
	ASM_OPERAND;
	ASM_OPERAND_MODIFIER;
	ASM_VALUE;
	ASM_REGISTER_DECLARATION;
	ASM_REGISTER_PINNING;
	ASM_MEMORY_OPERAND;
}

HELPER_LAYOUT_NAMES :: string.[
	"",
	"Parser_Argument",
	"Parser_Context_Modification",
	"Parser_Comma_Separated_Argument",
	"Parser_Struct_Literal_Info",
	"Parser_Array_Literal_Info",
	"Parser_Asm_Feature",
	"Parser_Asm_Statement",
	"Parser_Asm_Instruction",
	"Parser_Asm_Mnemonic_Size",
	"Parser_Asm_Operand",
	"Parser_Asm_Operand_Modifier",
	"Parser_Asm_Value",
	"Parser_Asm_Register_Declaration",
	"Parser_Asm_Register_Pinning",
	"Parser_Asm_Memory_Operand"
];

Walk_Item :: struct {
	pointer: *void;
	layout: Helper_Layout;
}

Node_Projector :: struct {
	parsed: *Parser.Parsed_Source;
	recording: bool;
	node_ids: Table(*void, s64);
	helper_ids: Table(*void, s64);
	fields: [..] Field_Observation;
	children: [..] Walk_Item;
	fault: Projection_Fault;
	path_keys: Table(string, [] u8);
	// Parameter `using` node to its matching argument declaration, filled while describing the owning header.
	parameter_using_targets: Table(*void, *void);
	// Import-owned parameter call to its owning import, filled while describing the import.
	import_calls: Table(*void, *void);
}

Flag_Name :: struct {
	name: string;
	bit: u64;
}

// Closed source-flag domains from CACHE_CONTRACTS.md, with the installed SDK's bit values.  Names are in unsigned ASCII order.
NODE_FLAGS :: Flag_Name.[
	.{"ALLOWED_BY_CONTEXT",		0x4},
	.{"EXPRESSION_IS_SPREAD",	0x1},
	.{"IS_PARENTHESIZED",		0x10},
	.{"NO_ARRAY_BOUNDS_CHECK",	0x2},
	.{"STATEMENT_IS_DEFERRED",	0x8}
];

CALL_FLAGS :: Flag_Name.[
	.{"INLINE_NO",						0x2},
	.{"INLINE_YES",						0x1},
	.{"IS_MODULE_PARAMETERS",			0x200},
	.{"NO_DEBUG",						0x100},
	.{"RETURNS_PROCEDURE_POINTER_ONLY",	0x10}
];

DECLARATION_FLAGS :: Flag_Name.[
	.{"AUTO_VALUE_BAKE",				0x4000},
	.{"AUTO_VALUE_BAKE_IS_REQUIRED",	0x8000},
	.{"ELSEWHERE",						0x40000},
	.{"HAS_SCOPE_MODIFIER",				0x200000},
	.{"IS_CONSTANT",					0x1},
	.{"IS_MARKED_AS_AS",				0x2},
	.{"IS_MARKED_AS_DISCARD",			0x4},
	.{"IS_UNINITIALIZED",				0x80},
	.{"NO_RESET",						0x40},
	.{"PROGRAM_EXPORT",					0x20000}
];

BLOCK_FLAGS :: Flag_Name.[
	.{"NO_ARITHMETIC_OVERFLOW_CHECK",	0x2},
	.{"NO_ARRAY_BOUNDS_CHECK",			0x1}
];

IDENT_FLAGS :: Flag_Name.[
	.{"DEFINES_POLYMORPH_VARIABLE",	0x1},
	.{"HAS_SCOPE_MODIFIER",			0x40},
	.{"IS_RHS_OF_DOT_DEREFERENCE",	0x2}
];

TYPE_INSTANTIATION_FLAGS :: Flag_Name.[
	.{"ARRAY_VIEW",					0x40},
	.{"INTERFACE",					0x80},
	.{"RESIZABLE",					0x2},
	.{"TYPE_DIRECTIVE",				0x8},
	.{"TYPE_DIRECTIVE_DISTINCT",	0x10},
	.{"TYPE_DIRECTIVE_ISA",			0x20},
	.{"TYPE_OF_PROCEDURE",			0x4},
	.{"VARARGS",					0x1}
];

LITERAL_FLAGS :: Flag_Name.[
	.{"BINARY",					0x20},
	.{"DEFAULTS_TO_FLOAT64",	0x100},
	.{"FLOAT",					0x4},
	.{"HERE_STRING",			0x80},
	.{"HEX",					0x2},
	.{"IS_A_NUMBER",			0x1},
	.{"MINUS_SIGN",				0x40},
	.{"REQUIRES_FLOAT64",		0x200},
	.{"SIGNIFICANT_DIGITS",		0x400}
];

BINARY_FLAGS :: Flag_Name.[
	.{"SHIFT_MARKED_AS_LOGICAL",	0x1},
	.{"SHIFT_MARKED_AS_SMALL",		0x2}
];

CAST_FLAGS :: Flag_Name.[
	.{"FORCE",					0x80},
	.{"HAS_FUNCTION_SYNTAX",	0x800},
	.{"HAS_POSTFIX_SYNTAX",		0x1000},
	.{"IS_AUTO",				0x4},
	.{"NO_BOUNDS_CHECK",		0x8},
	.{"TRUNCATE",				0x10},
	.{"VERY_FORCE",				0x100}
];

ARRAY_LITERAL_FLAGS :: Flag_Name.[
	.{"WAS_UNTYPED",	0x1}
];

NOTE_FLAGS :: Flag_Name.[];

IF_FLAGS :: Flag_Name.[
	.{"IS_IFX",					0x2},
	.{"IS_STATIC",				0x4},
	.{"IS_SWITCH_STATEMENT",	0x1},
	.{"MARKED_AS_COMPLETE",		0x8}
];

FOR_FLAGS :: Flag_Name.[
	.{"POINTER",	0x1},
	.{"REVERSE",	0x2}
];

RETURN_FLAGS :: Flag_Name.[
	.{"AUTO_INSERTED_FOR_QUICK_LAMBDA",	0x2},
	.{"IS_BACKTICKED",					0x1}
];

PUSH_CONTEXT_FLAGS :: Flag_Name.[
	.{"DEFER_POP",		0x2},
	.{"IS_BACKTICKED",	0x1}
];

STRUCT_FLAGS :: Flag_Name.[
	.{"FOREIGN",								0x1},
	.{"NO_PADDING",								0x4},
	.{"TYPE_INFO_NONE",							0x8},
	.{"TYPE_INFO_NO_SIZE_COMPLAINT",			0x10},
	.{"TYPE_INFO_PROCEDURES_ARE_VOID_POINTERS",	0x20},
	.{"UNION",									0x2}
];

BODY_FLAGS :: Flag_Name.[];

RUN_FLAGS :: Flag_Name.[
	.{"ASSERTION",					0x1},
	.{"HAS_IMPLICIT_RETURN_TYPES",	0x8},
	.{"HOST",						0x10},
	.{"STALLABLE",					0x2},
	.{"SYNTACTICALLY_IMPLICIT",		0x4}
];

IMPORT_FLAGS :: Flag_Name.[
	.{"SOURCE_PATH",	0x4},
	.{"UNSHARED",		0x1}
];

CODE_FLAGS :: Flag_Name.[
	.{"CALLER_CODE",	0x4},
	.{"NULL",			0x2},
	.{"TYPED",			0x8}
];

LIBRARY_FLAGS :: Flag_Name.[
	.{"DYNAMIC_LIBRARY_UNAVAILABLE",	0x2},
	.{"IS_SYSTEM_LIBRARY",				0x1},
	.{"LINK_ALWAYS",					0x8},
	.{"STATIC_LIBRARY_UNAVAILABLE",		0x4}
];

PROCEDURE_FLAGS :: Flag_Name.[
	.{"COMPILE_TIME_ONLY",						0x2},
	.{"C_CALL",									0x20},
	.{"DEBUG_DUMP",								0x10},
	.{"DEPRECATED",								0x100},
	.{"ELSEWHERE",								0x1},
	.{"ENTRY_POINT",							0x10000},
	.{"ENTRY_POINT_HOOK",						0x100000},
	.{"INTRINSIC",								0x80},
	.{"MACRO",									0x4000},
	.{"NO_CALL",								0x2000},
	.{"NO_DEBUG",								0x8000},
	.{"POLYMORPHIC",							0x4},
	.{"QUICK",									0x400},
	.{"QUICK_IN_BLOCK_FORM",					0x800},
	.{"SYMMETRIC",								0x40000},
	.{"SYNTACTICALLY_MARKED_AS_COMPILER",		0x400000},
	.{"SYNTACTICALLY_MARKED_AS_COMPILE_TIME",	0x200000},
	.{"SYNTACTICALLY_MARKED_AS_INLINE_NO",		0x2000000},
	.{"SYNTACTICALLY_MARKED_AS_INLINE_YES",		0x1000000},
	.{"SYNTACTICALLY_MARKED_AS_NO_CONTEXT",		0x200},
	.{"TYPE_ONLY",								0x40}
];

fill_node_projection :: (projection: *Node_Projection) -> Projection_Fault {
	projector: Node_Projector;
	projector.parsed = *projection.owner.parsed;
	root := projector.parsed.root;
	if !root {
		projection.root = -1;
		return .{};
	}


	// Phase 1 assigns IDs in preorder; phase 2 records fields once every referenced ID is known.
	order: [..] Walk_Item;
	stack: [..] Walk_Item;
	array_add(*stack, .{pointer = root});
	node_count: s64;
	helper_count: s64;
	while stack.count {
		item := pop(*stack);
		ids := ifx item.layout == .NONE
			then *projector.node_ids
			else *projector.helper_ids;
		if table_find_pointer(ids, item.pointer) {
			return .{.UNREGISTERED_SHARING, "nodes", order.count};
		}


		if item.layout == .NONE {
			table_add(ids, item.pointer, node_count);
			node_count += 1;
		} else {
			table_add(ids, item.pointer, helper_count);
			helper_count += 1;
		}

		array_add(*order, item);
		projector.children.count = 0;
		describe(*projector, item);
		if projector.fault.failure != .NONE {
			return projector.fault;
		}


		for < projector.children {
			array_add(*stack, it);
		}
	}


	projector.recording = true;
	projection.root = 0;
	projection.nodes = NewArray(node_count, Node_Record);
	projection.helpers = NewArray(helper_count, Helper_Record);
	for item: order {
		projector.fields.count = 0;
		projector.children.count = 0;
		describe(*projector, item);
		if projector.fault.failure != .NONE {
			return projector.fault;
		}


		fields := sorted_fields(*projector);
		if item.layout == .NONE {
			_, id := table_find(*projector.node_ids, item.pointer);
			node := item.pointer.(*Parser.Parser_Node);
			_, kind_name := node_kind_name(node.kind);
			span := Token_Span_Observation.{node.first_token.(s64), node.one_past_last_token.(s64)};
			record := *projection.nodes[id];
			record.* = .{
				local_node_id = xx id,
				kind = kind_name,
				coordinates = .{node.location.l0, node.location.c0, node.location.l1, node.location.c1},
				token_span = span,
				fields = fields
			};
			record.has_origin, record.origin = token_span_origin(projector.parsed, span);
		} else {
			_, id := table_find(*projector.helper_ids, item.pointer);
			projection.helpers[id] = .{
				local_helper_id = xx id,
				layout = HELPER_LAYOUT_NAMES[item.layout],
				fields = fields
			};
		}
	}


	projection.node_ids = projector.node_ids;
	return .{};
}

fail :: (p: *Node_Projector, failure: Projection_Failure, record: string) {
	if p.fault.failure == .NONE {
		p.fault = .{failure, record, p.node_ids.count - 1};
	}
}

field :: (p: *Node_Projector, value: Field_Value, names: .. string) {
	if !p.recording {
		return;
	}


	path := NewArray(names.count, Path_Step);
	for names {
		path[it_index] = .{kind = .FIELD, name = copy_string(it)};
	}

	array_add(*p.fields, .{path, value});
}

// Records an owning edge and queues the child for the walk; returns its ID once known.
node_value :: (p: *Node_Projector, node: *$T) -> Field_Value {
	if !node {
		return .{kind = .NODE, signed = -1};
	}


	array_add(*p.children, .{pointer = node});
	found, id := table_find(*p.node_ids, node);
	return .{kind = .NODE, signed = ifx found then id else -1};
}

helper_value :: (p: *Node_Projector, pointer: *void, layout: Helper_Layout) -> Field_Value {
	if !pointer {
		return .{kind = .HELPER, signed = -1};
	}


	array_add(*p.children, .{pointer = pointer, layout = layout});
	found, id := table_find(*p.helper_ids, pointer);
	return .{kind = .HELPER, signed = ifx found then id else -1};
}

node_list :: (p: *Node_Projector, nodes: [] *$T) -> Field_Value {
	elements: [] Field_Value;
	if p.recording {
		elements = NewArray(nodes.count, Field_Value);
	}

	for nodes {
		value := node_value(p, it);
		if p.recording {
			elements[it_index] = value;
		}
	}

	return .{kind = .LIST, elements = elements};
}

flags_value :: (p: *Node_Projector, domain: string, bits: u64, names: [] Flag_Name) -> Field_Value {
	remaining := bits;
	count: s64;
	for names {
		if bits & it.bit {
			remaining &= ~it.bit;
			count += 1;
		}
	}

	if remaining {
		fail(p, .UNKNOWN_SOURCE_FLAGS, domain);
		return .{};
	}


	if !p.recording {
		return .{kind = .FLAGS, domain = domain};
	}


	selected := NewArray(count, string);
	count = 0;
	for names {
		if bits & it.bit {
			selected[count] = it.name;
			count += 1;
		}
	}

	return .{kind = .FLAGS, domain = domain, names = selected};
}

// `domain` names the producer field; every admitted value must be a declared name of its enum type.
enum_value :: (p: *Node_Projector, domain: string, value: $T) -> Field_Value {
	info := type_info(T);
	for info.values {
		if it == value.(s64) {
			return .{kind = .ENUM, domain = domain, name = info.names[it_index]};
		}
	}


	fail(p, .UNKNOWN_PRODUCER_ENUM, domain);
	return .{};
}

// Declared producer names take precedence: they lie in 131-169 and 500, so a value is a byte character only when no name declares it.
operator_value :: (p: *Node_Projector, operator_type: $T) -> Field_Value {
	value := operator_type.(s64);
	info := type_info(T);
	for info.values {
		if it == value {
			return .{kind = .OPERATOR, tag = .{kind = .NAMED, name = info.names[it_index]}};
		}
	}

	if value >= 0 && value < 256 {
		return .{kind = .OPERATOR, tag = .{kind = .BYTE_CHAR, byte = xx value}};
	}


	fail(p, .UNKNOWN_PRODUCER_ENUM, "operator_type");
	return .{};
}

bytes_value :: (text: string) -> Field_Value {
	return .{kind = .BYTES, bytes = text.([] u8)};
}

signed_value :: (value: s64) -> Field_Value {
	return .{kind = .SIGNED, signed = value};
}

bool_value :: (value: bool) -> Field_Value {
	return .{kind = .BOOL, boolean = value};
}

// A non-owning association: never queued for descent, and resolved only once IDs are known.
alias_value :: (p: *Node_Projector, node: *void) -> Field_Value {
	found, id := table_find(*p.node_ids, node);
	return .{kind = .NODE, relationship = .ALIAS, signed = ifx found then id else -1};
}

argument_list :: (p: *Node_Projector, arguments: [] Parser.Parser_Argument) -> Field_Value {
	elements: [] Field_Value;
	if p.recording {
		elements = NewArray(arguments.count, Field_Value);
	}

	for * arguments {
		value := helper_value(p, it, .ARGUMENT);
		if p.recording {
			elements[it_index] = value;
		}
	}

	return .{kind = .LIST, elements = elements};
}

// Lists that no reviewed producer route populates; a populated one has no registered owner or order.
empty_list :: (p: *Node_Projector, list: [] $T, field_name: string) -> Field_Value {
	if list.count {
		fail(p, .UNEXPECTED_ACTIVE_FIELD, field_name);
	}

	return .{kind = .LIST};
}

INACTIVE :: Field_Value.{kind = .INACTIVE};

REGISTERED_NODE_KINDS :: string.[
	"ASM",
	"BINARY_OPERATOR",
	"BLOCK",
	"CASE",
	"CAST",
	"COMMA_SEPARATED_ARGUMENTS",
	"COMPOUND_DECLARATION",
	"CONTEXT",
	"DECLARATION",
	"DEFER",
	"DIRECTIVE_ADD_CONTEXT",
	"DIRECTIVE_BAKE",
	"DIRECTIVE_BYTES",
	"DIRECTIVE_CODE",
	"DIRECTIVE_CONTEXT_TYPE",
	"DIRECTIVE_EXISTS",
	"DIRECTIVE_IMPORT",
	"DIRECTIVE_INSERT",
	"DIRECTIVE_LIBRARY",
	"DIRECTIVE_LOAD",
	"DIRECTIVE_LOCATION",
	"DIRECTIVE_MODIFY",
	"DIRECTIVE_MODULE_PARAMETERS",
	"DIRECTIVE_OVERLAY",
	"DIRECTIVE_POKE_NAME",
	"DIRECTIVE_PROCEDURE_NAME",
	"DIRECTIVE_RUN",
	"DIRECTIVE_SCOPE",
	"DIRECTIVE_THIS",
	"DIRECTIVE_THROUGH",
	"DIRECTIVE_WILDCARD",
	"ENUM",
	"EXPRESSION_QUERY",
	"FOR",
	"IDENT",
	"IF",
	"LITERAL",
	"LOOP_CONTROL",
	"NOTE",
	"PLACEHOLDER",
	"PROCEDURE_BODY",
	"PROCEDURE_CALL",
	"PROCEDURE_HEADER",
	"PUSH_CONTEXT",
	"RETURN",
	"STRUCT",
	"TYPE_INSTANTIATION",
	"TYPE_QUERY",
	"UNARY_OPERATOR",
	"USING",
	"WHILE"
];

node_kind_name :: (kind: $T) -> bool, string {
	info := type_info(T);
	for info.values {
		if it == kind.(s64) {
			name := info.names[it_index];
			return array_find(REGISTERED_NODE_KINDS, name), name;
		}
	}


	return false, "";
}

describe :: (p: *Node_Projector, item: Walk_Item) {
	if item.layout == {
		case .NONE;
			describe_node(p, item.pointer);

		case .ARGUMENT;
			argument := item.pointer.(*Parser.Parser_Argument);
			field(p, node_value(p, argument.name), "name");
			field(p, node_value(p, argument.expression), "expression");

		case .CONTEXT_MODIFICATION;
			modification := item.pointer.(*Parser.Parser_Context_Modification);
			field(p, node_list(p, modification.modification_expressions), "modification_expressions");

		case .COMMA_SEPARATED_ARGUMENT;
			argument := item.pointer.(*Parser.Parser_Comma_Separated_Argument);
			field(p, node_value(p, argument.node), "node");
			field(p, enum_value(p, "Code_Comma_Separated_Argument.modifier", argument.modifier), "modifier");
			field(p, signed_value(argument.modifier_token.(s64)), "modifier_token");
			field(p, signed_value(argument.separator_token.(s64)), "separator_token");

		case .STRUCT_LITERAL_INFO;
			info := item.pointer.(*Parser.Parser_Struct_Literal_Info);
			field(p, node_value(p, info.type_expression), "type_expression");
			field(p, node_list(p, info.arguments), "arguments");

		case .ARRAY_LITERAL_INFO;
			info := item.pointer.(*Parser.Parser_Array_Literal_Info);
			// No reviewed producer route populates `alignment`.
			if info.alignment {
				fail(p, .UNEXPECTED_ACTIVE_FIELD, "Parser_Array_Literal_Info.alignment");
			}

			field(p, node_value(p, info.element_type), "element_type");
			field(p, INACTIVE, "alignment");
			field(p, node_list(p, info.array_members), "array_members");
			field(p, flags_value(p, "ARRAY_LITERAL", info.array_literal_flags.(u64), ARRAY_LITERAL_FLAGS), "array_literal_flags");

		case;
			describe_asm_helper(p, item);
	}
}

span_value :: (span: Parser.Token_Span) -> Field_Value {
	return .{kind = .TOKEN_SPAN, span = .{span.first.(s64), span.one_past_last.(s64)}};
}

helper_list :: (p: *Node_Projector, items: [] *$T, layout: Helper_Layout) -> Field_Value {
	elements: [] Field_Value;
	if p.recording {
		elements = NewArray(items.count, Field_Value);
	}

	for items {
		value := helper_value(p, it, layout);
		if p.recording {
			elements[it_index] = value;
		}
	}

	return .{kind = .LIST, elements = elements};
}

// An arm the kind does not select must hold no payload; it is recorded as inactive and never followed.
inactive_arm :: (p: *Node_Projector, populated: bool, field_name: string) -> Field_Value {
	if populated {
		fail(p, .UNEXPECTED_ACTIVE_FIELD, field_name);
	}

	return INACTIVE;
}

// Embedded value slots are distinct helper occurrences; an optional one with no expression is inactive storage.
optional_value :: (p: *Node_Projector, value: *Parser.Parser_Asm_Value) -> Field_Value {
	return ifx value.expression
		then helper_value(p, value, .ASM_VALUE)
		else INACTIVE;
}

// Assembly helpers select their active arm from the kind field; every other arm must be empty.
describe_asm_helper :: (p: *Node_Projector, item: Walk_Item) {
	if item.layout == {
		case .ASM_FEATURE;
			feature := item.pointer.(*Parser.Parser_Asm_Feature);
			field(p, span_value(feature.span), "span");
			field(p, node_value(p, feature.name), "name");

		case .ASM_STATEMENT;
			statement := item.pointer.(*Parser.Parser_Asm_Statement);
			field(p, enum_value(p, "Parser_Asm_Statement.kind", statement.kind), "kind");
			field(p, span_value(statement.span), "span");
			kind := statement.kind;
			field(
				p,
				ifx kind == .INSTRUCTION
					then helper_value(p, statement.instruction, .ASM_INSTRUCTION)
					else inactive_arm(p, !!statement.instruction, "instruction"),
				"instruction"
			);
			field(
				p,
				ifx kind == .REGISTER_DECLARATION
					then helper_value(p, statement.register_declaration, .ASM_REGISTER_DECLARATION)
					else inactive_arm(p, !!statement.register_declaration, "register_declaration"),
				"register_declaration"
			);
			field(
				p,
				ifx kind == .REGISTER_PINNING
					then helper_value(p, statement.register_pinning, .ASM_REGISTER_PINNING)
					else inactive_arm(p, !!statement.register_pinning, "register_pinning"),
				"register_pinning"
			);

		case .ASM_INSTRUCTION;
			instruction := item.pointer.(*Parser.Parser_Asm_Instruction);
			field(p, span_value(instruction.span), "span");
			field(p, node_value(p, instruction.mnemonic), "mnemonic");
			field(p, helper_value(p, instruction.size, .ASM_MNEMONIC_SIZE), "size");
			field(p, helper_list(p, instruction.operands, .ASM_OPERAND), "operands");

		case .ASM_MNEMONIC_SIZE;
			size := item.pointer.(*Parser.Parser_Asm_Mnemonic_Size);
			field(p, enum_value(p, "Parser_Asm_Mnemonic_Size.kind", size.kind), "kind");
			field(p, span_value(size.span), "span");
			field(
				p,
				ifx size.kind == .POLYMORPHIC
					then node_value(p, size.polymorphic_name)
					else inactive_arm(p, !!size.polymorphic_name, "polymorphic_name"),
				"polymorphic_name");

		case .ASM_OPERAND;
			operand := item.pointer.(*Parser.Parser_Asm_Operand);
			field(p, enum_value(p, "Parser_Asm_Operand.kind", operand.kind), "kind");
			field(p, span_value(operand.span), "span");
			kind := operand.kind;
			field(
				p,
				ifx kind == .VALUE
					then helper_value(p, *operand.value, .ASM_VALUE)
					else inactive_arm(p, !!operand.value.expression, "value"),
				"value"
			);
			field(
				p,
				ifx kind == .REGISTER_DECLARATION
					then helper_value(p, operand.register_declaration, .ASM_REGISTER_DECLARATION)
					else inactive_arm(p, !!operand.register_declaration, "register_declaration"),
				"register_declaration"
			);
			field(
				p,
				ifx kind == .REGISTER_PINNING
					then helper_value(p, operand.register_pinning, .ASM_REGISTER_PINNING)
					else inactive_arm(p, !!operand.register_pinning, "register_pinning"),
				"register_pinning"
			);
			field(
				p,
				ifx kind == .MEMORY
					then helper_value(p, operand.memory, .ASM_MEMORY_OPERAND)
					else inactive_arm(p, !!operand.memory, "memory"),
				"memory"
			);
			field(p, helper_list(p, operand.modifiers, .ASM_OPERAND_MODIFIER), "modifiers");

		case .ASM_OPERAND_MODIFIER;
			modifier := item.pointer.(*Parser.Parser_Asm_Operand_Modifier);
			field(p, enum_value(p, "Parser_Asm_Operand_Modifier.kind", modifier.kind), "kind");
			field(p, span_value(modifier.span), "span");
			has_argument := modifier.kind == .AMPERSAND || modifier.kind == .AMPERSAND_STAR;
			field(
				p,
				ifx has_argument
					then helper_value(p, *modifier.argument, .ASM_VALUE)
					else inactive_arm(p, !!modifier.argument.expression, "argument"),
				"argument"
			);

		case .ASM_VALUE;
			value := item.pointer.(*Parser.Parser_Asm_Value);
			field(p, span_value(value.span), "span");
			field(p, node_value(p, value.expression), "expression");

		case .ASM_REGISTER_DECLARATION;
			declaration := item.pointer.(*Parser.Parser_Asm_Register_Declaration);
			field(p, span_value(declaration.span), "span");
			field(p, bool_value(declaration.is_inferred), "is_inferred");
			field(p, node_value(p, declaration.name), "name");
			field(
				p,
				ifx declaration.is_inferred
					then inactive_arm(p, !!declaration.register_class, "register_class")
					else node_value(p, declaration.register_class),
				"register_class"
			);
			field(p, helper_value(p, declaration.pinning, .ASM_REGISTER_PINNING), "pinning");

		case .ASM_REGISTER_PINNING;
			pinning := item.pointer.(*Parser.Parser_Asm_Register_Pinning);
			field(p, span_value(pinning.span), "span");
			field(p, helper_value(p, *pinning.source, .ASM_VALUE), "source");
			field(p, helper_value(p, *pinning.target, .ASM_VALUE), "target");

		case .ASM_MEMORY_OPERAND;
			memory := item.pointer.(*Parser.Parser_Asm_Memory_Operand);
			field(p, span_value(memory.span), "span");
			field(p, helper_value(p, *memory.base, .ASM_VALUE), "base");
			field(p, optional_value(p, *memory.index), "index");
			field(p, optional_value(p, *memory.scale), "scale");
			field(p, optional_value(p, *memory.displacement), "displacement");
	}
}

describe_node :: (p: *Node_Projector, pointer: *void) {
	node := pointer.(*Parser.Parser_Node);
	registered, kind_name := node_kind_name(node.kind);
	if !registered {
		fail(p, .UNREGISTERED_NODE_KIND, kind_name);
		return;
	}


	field(p, flags_value(p, "NODE", node.node_flags.(u64), NODE_FLAGS), "node_flags");
	if node.kind == {
		case .DIRECTIVE_THIS;			#through;
		case .DIRECTIVE_CONTEXT_TYPE;	#through;
		case .DIRECTIVE_THROUGH;		#through;
		case .CONTEXT;

		case .IDENT;
			ident := node.(*Parser.Parser_Ident);
			field(p, bytes_value(ident.name), "name");
			field(p, flags_value(p, "IDENT", ident.flags.(u64), IDENT_FLAGS), "flags");

		case .NOTE;
			note := node.(*Parser.Parser_Note);
			field(p, bytes_value(note.text), "text");
			field(p, flags_value(p, "NOTE", note.note_flags.(u64), NOTE_FLAGS), "note_flags");

		case .PLACEHOLDER;
			describe_placeholder(p, node.(*Parser.Parser_Placeholder));

		case .UNARY_OPERATOR;
			unary := node.(*Parser.Parser_Unary_Operator);
			field(p, operator_value(p, unary.operator_type), "operator_type");
			field(p, node_value(p, unary.subexpression), "subexpression");

		case .BINARY_OPERATOR;
			binary := node.(*Parser.Parser_Binary_Operator);
			field(p, operator_value(p, binary.operator_type), "operator_type");
			field(p, flags_value(p, "BINARY", binary.flags.(u64), BINARY_FLAGS), "flags");
			field(p, node_value(p, binary.left), "left");
			field(p, node_value(p, binary.right), "right");

		case .CAST;
			describe_cast(p, node.(*Parser.Parser_Cast));

		case .EXPRESSION_QUERY;
			query := node.(*Parser.Parser_Expression_Query);
			field(p, enum_value(p, "Code_Expression_Query.query_kind", query.query_kind), "query_kind");
			field(p, node_value(p, query.expression_to_query), "expression_to_query");

		case .TYPE_QUERY;
			query := node.(*Parser.Parser_Type_Query);
			field(p, enum_value(p, "Code_Type_Query.query_kind", query.query_kind), "query_kind");
			field(p, node_value(p, query.type_to_query), "type_to_query");

		case .PROCEDURE_CALL;
			call := node.(*Parser.Parser_Procedure_Call);
			found, owning_import := table_find(*p.import_calls, call);
			if !found {
				field(p, node_value(p, call.procedure_expression), "procedure_expression");
			} else if call.procedure_expression.(*void) == owning_import {
				field(p, alias_value(p, owning_import), "procedure_expression");
			} else {
				fail(p, .UNQUALIFIED_ROUTE, "Parser_Procedure_Call.procedure_expression");
			}
			field(p, argument_list(p, call.arguments_unsorted), "arguments_unsorted");
			field(p, helper_value(p, call.context_modification, .CONTEXT_MODIFICATION), "context_modification");
			field(p, flags_value(p, "CALL", call.flags.(u64), CALL_FLAGS), "flags");

		case .BLOCK;
			block := node.(*Parser.Parser_Block);
			field(p, enum_value(p, "Code_Block.block_type", block.block_type), "block_type");
			field(p, flags_value(p, "BLOCK", block.block_flags.(u64), BLOCK_FLAGS), "block_flags");
			field(p, node_list(p, block.statements), "statements");

		case .DECLARATION;
			declaration := node.(*Parser.Parser_Declaration);
			field(p, bytes_value(declaration.entry.name), "entry", "name");
			field(p, node_value(p, declaration.type_inst), "type_inst");
			field(p, node_value(p, declaration.expression), "expression");
			field(p, node_value(p, declaration.alignment_expression), "alignment_expression");
			field(p, node_list(p, declaration.notes), "notes");
			field(p, flags_value(p, "DECLARATION", declaration.flags.(u64), DECLARATION_FLAGS), "flags");
			field(p, bytes_value(declaration.program_export_name), "program_export_name");

		case .COMPOUND_DECLARATION;
			compound := node.(*Parser.Parser_Compound_Declaration);
			field(p, node_value(p, compound.comma_separated_assignment), "comma_separated_assignment");
			field(p, node_value(p, compound.declaration_properties), "declaration_properties");
			field(p, node_value(p, compound.alignment_expression), "alignment_expression");
			field(p, node_list(p, compound.notes), "notes");
			field(p, operator_value(p, compound.operator_type), "operator_type");
			field(p, signed_value(compound.operator_token.(s64)), "operator_token");

		case .COMMA_SEPARATED_ARGUMENTS;
			comma := node.(*Parser.Parser_Comma_Separated_Arguments);
			arguments: [] Field_Value;
			if p.recording {
				arguments = NewArray(comma.arguments.count, Field_Value);
			}

			for * comma.arguments {
				value := helper_value(p, it, .COMMA_SEPARATED_ARGUMENT);
				if p.recording {
					arguments[it_index] = value;
				}
			}

			field(p, .{kind = .LIST, elements = arguments}, "arguments");

		case .LITERAL;
			describe_literal(p, node.(*Parser.Parser_Literal));

		case .TYPE_INSTANTIATION;
			describe_type_instantiation(p, node.(*Parser.Parser_Type_Instantiation));

		case .IF;
			if_node := node.(*Parser.Parser_If);
			field(p, flags_value(p, "IF", if_node.if_flags.(u64), IF_FLAGS), "if_flags");
			field(p, node_value(p, if_node.condition), "condition");
			field(p, node_value(p, if_node.then_block), "then_block");
			field(p, node_value(p, if_node.else_block), "else_block");

		case .CASE;
			case_node := node.(*Parser.Parser_Case);
			field(p, node_value(p, case_node.condition), "condition");
			field(p, node_value(p, case_node.then_block), "then_block");
			field(p, bool_value(case_node.marked_as_fallthrough), "marked_as_fallthrough");

		case .WHILE;
			while_node := node.(*Parser.Parser_While);
			field(p, node_value(p, while_node.condition), "condition");
			field(p, node_value(p, while_node.block), "block");

		case .FOR;
			describe_for(p, node.(*Parser.Parser_For));

		case .LOOP_CONTROL;
			control := node.(*Parser.Parser_Loop_Control);
			field(p, enum_value(p, "Code_Loop_Control.control_type", control.control_type), "control_type");
			field(p, node_value(p, control.target_ident), "target_ident");

		case .RETURN;
			return_node := node.(*Parser.Parser_Return);
			field(p, argument_list(p, return_node.arguments_unsorted), "arguments_unsorted");
			field(p, flags_value(p, "RETURN", return_node.return_flags.(u64), RETURN_FLAGS), "return_flags");

		case .DEFER;
			defer_node := node.(*Parser.Parser_Defer);
			field(p, node_value(p, defer_node.block), "block");
			field(p, bool_value(defer_node.is_backticked), "is_backticked");

		case .PUSH_CONTEXT;
			push := node.(*Parser.Parser_Push_Context);
			flags := push.push_context_flags.(u64);
			field(p, flags_value(p, "PUSH_CONTEXT", flags, PUSH_CONTEXT_FLAGS), "push_context_flags");
			field(p, node_value(p, push.to_push), "to_push");
			// The `.DEFER_POP` route has no body.
			if flags & 0x2 {
				if push.block {
					fail(p, .UNEXPECTED_ACTIVE_FIELD, "Parser_Push_Context.block");
				}

				field(p, INACTIVE, "block");
			} else {
				field(p, node_value(p, push.block), "block");
			}

		case .USING;
			using_node := node.(*Parser.Parser_Using);
			field(p, enum_value(p, "Code_Using.filter_type", using_node.filter_type), "filter_type");
			field(p, bool_value(using_node.no_parameters), "no_parameters");
			field(p, node_value(p, using_node.filter_expression), "filter_expression");
			found, target := table_find(*p.parameter_using_targets, using_node);
			if found {
				field(p, alias_value(p, target), "expression");
			} else {
				field(p, node_value(p, using_node.expression), "expression");
			}

		case .STRUCT;
			struct_node := node.(*Parser.Parser_Struct);
			field(p, flags_value(p, "STRUCT", struct_node.textual_flags.(u64), STRUCT_FLAGS), "textual_flags");
			field(p, signed_value(struct_node.alignment), "alignment");
			field(p, empty_list(p, struct_node.notes, "Parser_Struct.notes"), "notes");
			field(p, node_value(p, struct_node.arguments_block), "arguments_block");
			field(p, node_list(p, struct_node.modify_directives), "modify_directives");
			field(p, node_value(p, struct_node.block), "block");

		case .ENUM;
			enum_node := node.(*Parser.Parser_Enum);
			field(p, bool_value(enum_node.marked_as_complete), "marked_as_complete");
			field(p, bool_value(enum_node.marked_as_specified), "marked_as_specified");
			field(p, bool_value(enum_node.is_flags), "is_flags");
			field(p, empty_list(p, enum_node.notes, "Parser_Enum.notes"), "notes");
			field(p, node_value(p, enum_node.internal_type_inst), "internal_type_inst");
			field(p, node_value(p, enum_node.block), "block");

		case .PROCEDURE_HEADER;
			describe_procedure_header(p, node.(*Parser.Parser_Procedure_Header));

		case .PROCEDURE_BODY;
			body := node.(*Parser.Parser_Procedure_Body);
			field(p, flags_value(p, "BODY", body.body_flags.(u64), BODY_FLAGS), "body_flags");
			field(p, node_value(p, body.block), "block");

		case .ASM;
			assembly := node.(*Parser.Parser_Asm);
			field(p, span_value(assembly.body_span), "body_span");
			field(p, helper_list(p, assembly.features, .ASM_FEATURE), "features");
			field(p, helper_list(p, assembly.statements, .ASM_STATEMENT), "statements");

		case;
			describe_directive(p, node);
	}
}

describe_directive :: (p: *Node_Projector, node: *Parser.Parser_Node) {
	if node.kind == {
		case .DIRECTIVE_ADD_CONTEXT;
			field(p, node_value(p, node.(*Parser.Parser_Directive_Add_Context).expression), "expression");

		case .DIRECTIVE_BYTES;
			field(p, node_value(p, node.(*Parser.Parser_Directive_Bytes).expression), "expression");

		case .DIRECTIVE_OVERLAY;
			overlay := node.(*Parser.Parser_Directive_Overlay);
			field(p, node_value(p, overlay.target_expression), "target_expression");
			field(p, node_value(p, overlay.declaration_or_using), "declaration_or_using");

		case .DIRECTIVE_MODIFY;
			field(p, node_value(p, node.(*Parser.Parser_Directive_Modify).block), "block");

		case .DIRECTIVE_MODULE_PARAMETERS;
			parameters := node.(*Parser.Parser_Directive_Module_Parameters);
			field(p, node_value(p, parameters.module_parameters), "module_parameters");
			field(p, node_value(p, parameters.program_parameters), "program_parameters");
			field(p, node_value(p, parameters.common_code), "common_code");

		case .DIRECTIVE_IMPORT;
			import_node := node.(*Parser.Parser_Directive_Import);
			field(p, bytes_value(import_node.name), "name");
			field(p, flags_value(p, "IMPORT", import_node.flags.(u64), IMPORT_FLAGS), "flags");
			field(p, enum_value(p, "Code_Directive_Import.import_type", import_node.import_type), "import_type");
			for call: (*Parser.Parser_Procedure_Call).[import_node.module_parameters_call, import_node.program_parameters_call] {
				if call {
					table_set(*p.import_calls, call, import_node);
				}
			}

			field(p, node_value(p, import_node.module_parameters_call), "module_parameters_call");
			field(p, node_value(p, import_node.program_parameters_call), "program_parameters_call");

		case .DIRECTIVE_LOAD;
			load := node.(*Parser.Parser_Directive_Load);
			field(p, bytes_value(load.short_name), "short_name");
			field(p, signed_value(load.load_flags), "load_flags");

		case .DIRECTIVE_LIBRARY;
			library := node.(*Parser.Parser_Directive_Library);
			field(p, bytes_value(library.name), "name");
			field(p, flags_value(p, "LIBRARY", library.library_flags.(u64), LIBRARY_FLAGS), "library_flags");

		case .DIRECTIVE_POKE_NAME;
			poke := node.(*Parser.Parser_Directive_Poke_Name);
			field(p, bytes_value(poke.name), "name");
			field(p, node_value(p, poke.module_expression), "module_expression");

		case .DIRECTIVE_PROCEDURE_NAME;
			field(p, node_value(p, node.(*Parser.Parser_Directive_Procedure_Name).argument), "argument");

		case .DIRECTIVE_EXISTS;
			exists := node.(*Parser.Parser_Directive_Exists);
			field(p, node_value(p, exists.query_expression), "query_expression");
			field(p, node_value(p, exists.sync_expression), "sync_expression");

		case .DIRECTIVE_LOCATION;
			location := node.(*Parser.Parser_Directive_Location);
			field(p, bool_value(location.is_caller_location), "is_caller_location");
			if location.is_caller_location && location.expression {
				fail(p, .UNEXPECTED_ACTIVE_FIELD, "Parser_Directive_Location.expression");
			}

			field(p, node_value(p, location.expression), "expression");

		case .DIRECTIVE_CODE;
			code := node.(*Parser.Parser_Directive_Code);
			flags := code.code_flags.(u64);
			field(p, flags_value(p, "CODE", flags, CODE_FLAGS), "code_flags");
			// `#code,null` and `#caller_code` carry no payload.
			if flags & (0x2 | 0x4) {
				if code.expression {
					fail(p, .UNEXPECTED_ACTIVE_FIELD, "Parser_Directive_Code.expression");
				}

				field(p, INACTIVE, "expression");
			} else {
				field(p, node_value(p, code.expression), "expression");
			}

		case .DIRECTIVE_BAKE;
			bake := node.(*Parser.Parser_Directive_Bake);
			field(p, enum_value(p, "Code_Directive_Bake.bake_type", bake.bake_type), "bake_type");
			field(p, node_value(p, bake.procedure_call), "procedure_call");

		case .DIRECTIVE_SCOPE;
			scope := node.(*Parser.Parser_Directive_Scope);
			field(p, enum_value(p, "Code_Directive_Scope.scope_type", scope.scope_type), "scope_type");

		case .DIRECTIVE_WILDCARD;
			field(p, signed_value(node.(*Parser.Parser_Directive_Wildcard).index), "index");

		case .DIRECTIVE_RUN;
			describe_run(p, node.(*Parser.Parser_Directive_Run));

		case .DIRECTIVE_INSERT;
			describe_insert(p, node.(*Parser.Parser_Directive_Insert));
	}
}

// On the arrow route the source header owns its body block, and `expression` may only alias that block.
describe_run :: (p: *Node_Projector, run: *Parser.Parser_Directive_Run) {
	field(p, flags_value(p, "RUN", run.flags.(u64), RUN_FLAGS), "flags");
	field(p, bytes_value(run.assertion_string), "assertion_string");
	header := run.procedure;
	field(p, node_value(p, header), "procedure");
	if !header || !run.expression {
		field(p, node_value(p, run.expression), "expression");
		return;
	}


	body := header.body_or_null;
	if !body || run.expression.(*void) != body.block.(*void) {
		fail(p, .UNQUALIFIED_ROUTE, "Parser_Directive_Run.expression");
		return;
	}


	field(p, alias_value(p, run.expression), "expression");
}

// Replacement clauses follow their source order (break, continue, remove on a tie), between the scope prefix and the payload.
describe_insert :: (p: *Node_Projector, insert: *Parser.Parser_Directive_Insert) {
	if insert.expansion {
		fail(p, .UNEXPECTED_ACTIVE_FIELD, "Parser_Directive_Insert.expansion");
		return;
	}


	field(p, node_value(p, insert.scope_redirection), "scope_redirection");
	replacements: [3] *Parser.Parser_Node = .[insert.break_replacement, insert.continue_replacement, insert.remove_replacement];
	names :: string.["break_replacement", "continue_replacement", "remove_replacement"];
	order: [3] s64 = .[0, 1, 2];
	for i: 1..2 {
		j := i;
		while j > 0 && replacements[order[j]] && replacements[order[j - 1]] && replacements[order[j]].first_token < replacements[order[j - 1]].first_token {
			order[j - 1], order[j] = order[j], order[j - 1];
			j -= 1;
		}
	}

	for order {
		field(p, node_value(p, replacements[it]), names[it]);
	}

	field(p, node_value(p, insert.expression), "expression");
}

// Dynamic prefixes follow their token order (reverse first on a tie), then expansion, explicit names, range and body.
describe_for :: (p: *Node_Projector, for_node: *Parser.Parser_For) {
	field(p, flags_value(p, "FOR", for_node.for_flags.(u64), FOR_FLAGS), "for_flags");
	reverse := for_node.want_reverse_expression;
	pointer := for_node.want_pointer_expression;
	pointer_first := reverse && pointer && pointer.first_token < reverse.first_token;
	if pointer_first {
		field(p, node_value(p, pointer), "want_pointer_expression");
		field(p, node_value(p, reverse), "want_reverse_expression");
	} else {
		field(p, node_value(p, reverse), "want_reverse_expression");
		field(p, node_value(p, pointer), "want_pointer_expression");
	}

	field(p, node_value(p, for_node.want_replacement_for_expansion), "want_replacement_for_expansion");
	field(p, node_value(p, for_node.ident_it), "ident_it");
	field(p, node_value(p, for_node.ident_it_index), "ident_it_index");
	field(p, node_value(p, for_node.iteration_expression), "iteration_expression");
	field(p, node_value(p, for_node.iteration_expression_right), "iteration_expression_right");
	field(p, node_value(p, for_node.block), "block");
}

// Each parameter `using` precedes its argument; its expression is an alias to exactly one argument, in argument order.
describe_procedure_header :: (p: *Node_Projector, header: *Parser.Parser_Procedure_Header) {
	field(p, flags_value(p, "PROCEDURE", header.procedure_flags.(u64), PROCEDURE_FLAGS), "procedure_flags");
	field(p, bytes_value(header.name), "name");
	field(p, bytes_value(header.foreign_function_name), "foreign_function_name");
	field(p, bytes_value(header.deprecation_string), "deprecation_string");
	field(p, empty_list(p, header.notes, "Parser_Procedure_Header.notes"), "notes");

	usings := header.parameter_usings;
	targets := NewArray(usings.count, s64,, temp);
	previous := -1;
	for using_node, using_index: usings {
		target := -1;
		matches := 0;
		if using_node {
			for header.arguments {
				if it.(*void) == using_node.expression.(*void) {
					target = it_index;
					matches += 1;
				}
			}
		}

		if matches != 1 || target <= previous {
			fail(p, .UNQUALIFIED_ROUTE, "Parser_Procedure_Header.parameter_usings");
			return;
		}


		previous = target;
		targets[using_index] = target;
		table_set(*p.parameter_using_targets, using_node, using_node.expression);
	}


	argument_values: [] Field_Value;
	using_values: [] Field_Value;
	if p.recording {
		argument_values = NewArray(header.arguments.count, Field_Value);
		using_values = NewArray(usings.count, Field_Value);
	}

	cursor := 0;
	for argument, argument_index: header.arguments {
		while cursor < usings.count && targets[cursor] == argument_index {
			value := node_value(p, usings[cursor]);
			if p.recording {
				using_values[cursor] = value;
			}

			cursor += 1;
		}

		value := node_value(p, argument);
		if p.recording {
			argument_values[argument_index] = value;
		}
	}

	field(p, .{kind = .LIST, elements = argument_values}, "arguments");
	field(p, .{kind = .LIST, elements = using_values}, "parameter_usings");
	field(p, node_list(p, header.returns), "returns");
	field(p, node_value(p, header.library_identifier), "library_identifier");
	field(p, node_list(p, header.modify_directives), "modify_directives");
	field(p, node_value(p, header.body_or_null), "body_or_null");
}

// The name is safe only when it is the identifier payload of a token inside this node's interval.
describe_placeholder :: (p: *Node_Projector, placeholder: *Parser.Parser_Placeholder) {
	first := placeholder.first_token.(s64);
	last := placeholder.one_past_last_token.(s64);
	tokens := p.parsed.tokens;
	if first >= 0 && last <= tokens.count {
		for index: first..last - 1 {
			token := *tokens[index];
			if token.type == .IDENT && token.ident_value.name.(string).data == placeholder.name.data && token.ident_value.name.count == placeholder.name.count {
				field(p, bytes_value(placeholder.name), "name");
				return;
			}
		}
	}


	fail(p, .UNQUALIFIED_ROUTE, "Parser_Placeholder.name");
}

// Explicit prefix casts visit the target first, postfix casts the expression first; auto casts have no target.
describe_cast :: (p: *Node_Projector, cast_node: *Parser.Parser_Cast) {
	flags := cast_node.cast_flags.(u64);
	field(p, flags_value(p, "CAST", flags, CAST_FLAGS), "cast_flags");
	is_auto := !!(flags & 0x4);
	is_postfix := !!(flags & 0x1000);
	if is_auto {
		if cast_node.target_type || is_postfix {
			fail(p, .UNEXPECTED_ACTIVE_FIELD, "Parser_Cast.target_type");
		}

		field(p, INACTIVE, "target_type");
		field(p, node_value(p, cast_node.expression), "expression");
	} else if is_postfix {
		field(p, node_value(p, cast_node.expression), "expression");
		field(p, node_value(p, cast_node.target_type), "target_type");
	} else {
		field(p, node_value(p, cast_node.target_type), "target_type");
		field(p, node_value(p, cast_node.expression), "expression");
	}
}

describe_literal :: (p: *Node_Projector, literal: *Parser.Parser_Literal) {
	field(p, enum_value(p, "Code_Literal.value_type", literal.value_type), "value_type");
	flags := literal.value_flags.(u64);
	field(p, flags_value(p, "LITERAL", flags, LITERAL_FLAGS), "value_flags");
	if literal.value_type == {
		case .NUMBER;
			if flags & 0x4 {
				field(p, .{kind = .FLOAT64_BITS,	unsigned = literal._u64}, "values", "_float64");
			} else {
				field(p, .{kind = .UNSIGNED,		unsigned = literal._u64}, "values", "_u64");
			}

		case .BOOLEAN;
			field(p, .{kind = .UNSIGNED,		unsigned = literal._u64}, "values", "_u64");

		case .STRING;
			field(p, bytes_value(literal._string), "values", "_string");

		case .UNINITIALIZED;

		case .STRUCT;
			if !literal.struct_literal_info {
				fail(p, .UNQUALIFIED_ROUTE, "Parser_Literal.struct_literal_info");
			}

			field(p, helper_value(p, literal.struct_literal_info, .STRUCT_LITERAL_INFO), "values", "struct_literal_info");

		case .ARRAY;
			if !literal.array_literal_info {
				fail(p, .UNQUALIFIED_ROUTE, "Parser_Literal.array_literal_info");
			}

			field(p, helper_value(p, literal.array_literal_info, .ARRAY_LITERAL_INFO), "values", "array_literal_info");

		case .POINTER;
			// Only the authored `null` route is qualified: a constant-value helper with no symbol, data or offset.
			info := literal.pointer_literal_info;
			if !info || info.pointer_literal_type != .CONSTANT_VALUE || info.global_symbol || info.data_pointer || info.offset_from_symbol {
				fail(p, .UNQUALIFIED_ROUTE, "Parser_Literal.pointer_literal_info");
				return;
			}


			field(p, .{kind = .SOURCE_NULL}, "values", "pointer_literal_info");

		case;
			fail(p, .UNQUALIFIED_ROUTE, "Parser_Literal.value_type");
	}
}

TYPE_CHILD_FIELDS :: string.["type_valued_expression", "must_implement", "pointer_to", "type_directive_target", "array_element_type", "array_dimension"];

// Selects one source form from flags and the leading token, then visits only that form's children in registry order.
describe_type_instantiation :: (p: *Node_Projector, wrapper: *Parser.Parser_Type_Instantiation) {
	flags := wrapper.inst_flags.(u64);
	field(p, flags_value(p, "TYPE_INSTANTIATION", flags, TYPE_INSTANTIATION_FLAGS), "inst_flags");
	children: [6] *Parser.Parser_Node = .[
		wrapper.type_valued_expression,
		wrapper.must_implement,
		xx wrapper.pointer_to,
		xx wrapper.type_directive_target,
		xx wrapper.array_element_type,
		wrapper.array_dimension
	];
	TYPE_VALUED :: 0;
	MUST_IMPLEMENT :: 1;
	POINTER_TO :: 2;
	DIRECTIVE_TARGET :: 3;
	ELEMENT :: 4;
	DIMENSION :: 5;

	// A parenthesised type's interval starts at `(`; the form's own leading token follows.
	leading: Parser.Token_Type = .ERROR;
	first := wrapper.first_token.(s64);
	while first >= 0 && first < wrapper.one_past_last_token.(s64) && first < p.parsed.tokens.count {
		leading = p.parsed.tokens[first].type;
		if leading != #char "(" {
			break;
		}


		first += 1;
	}

	active: [2] s64 = .[-1, -1];
	if flags & 0x1 {
		active[0] = ELEMENT;
	} else if flags & 0x8 {
		active[0] = DIRECTIVE_TARGET;
	} else if flags & (0x40 | 0x2) {
		active[0] = ELEMENT;
	} else if flags & 0x4 {
		active[0] = TYPE_VALUED;
	} else if wrapper.type_valued_expression {
		active[0] = TYPE_VALUED;
		expression := wrapper.type_valued_expression;
		is_polymorphic := expression.kind == .IDENT && !!(expression.(*Parser.Parser_Ident).flags & 0x1);
		if is_polymorphic && (wrapper.must_implement || consumed_constraint(p, expression)) {
			active[1] = MUST_IMPLEMENT;
		}
	} else if wrapper.pointer_to || leading == #char "*" {
		active[0] = POINTER_TO;
	} else if wrapper.array_dimension || wrapper.array_element_type || leading == #char "[" {
		active[0] = DIMENSION;
		active[1] = ELEMENT;
	} else {
		active[0] = TYPE_VALUED;
	}

	for children {
		if it && it_index != active[0] && it_index != active[1] {
			fail(p, .UNEXPECTED_ACTIVE_FIELD, TYPE_CHILD_FIELDS[it_index]);
			return;
		}
	}


	for slot: 0..TYPE_CHILD_FIELDS.count - 1 {
		if slot != active[0] && slot != active[1] {
			field(p, INACTIVE, TYPE_CHILD_FIELDS[slot]);
		}
	}

	for slot: active {
		if slot >= 0 {
			field(p, node_value(p, children[slot]), TYPE_CHILD_FIELDS[slot]);
		}
	}
}

// A `/` directly after the polymorphic name means the constraint suffix was consumed, even when its expression is missing.
consumed_constraint :: (p: *Node_Projector, expression: *Parser.Parser_Node) -> bool {
	next := expression.one_past_last_token.(s64);
	return next >= 0 && next < p.parsed.tokens.count && p.parsed.tokens[next].type == #char "/";
}

token_span_origin :: (parsed: *Parser.Parsed_Source, span: Token_Span_Observation) -> bool, Byte_Span {
	if span.first < 0 || span.first >= span.one_past_last || span.one_past_last > parsed.tokens.count {
		return false, .{};
	}


	return true, .{parsed.tokens[span.first].byte_start, parsed.tokens[span.one_past_last - 1].byte_end};
}

// Observations sort by the canonical bytes of their complete paths.
sorted_fields :: (p: *Node_Projector) -> [] Field_Observation {
	fields := array_copy(p.fields);
	keys := NewArray(fields.count, [] u8);
	for fields {
		keys[it_index] = path_key(p, it.path);
	}

	// Insertion sort: records have only a handful of fields.
	for i: 1..fields.count - 1 {
		j := i;
		while j > 0 && compare_canonical(keys[j - 1], keys[j]) > 0 {
			keys[j - 1], keys[j] = keys[j], keys[j - 1];
			fields[j - 1], fields[j] = fields[j], fields[j - 1];
			j -= 1;
		}
	}

	return fields;
}

path_key :: (p: *Node_Projector, path: [] Path_Step) -> [] u8 {
	joined := path[0].name;
	for 1..path.count - 1 {
		joined = tprint("%.%", joined, path[it].name);
	}

	found, key := table_find(*p.path_keys, joined);
	if found {
		return key;
	}


	schema := interface_schema("PathStep");
	steps := NewArray(path.count, [] u8);
	for path {
		ok, name := v_ascii(it.name);
		assert(ok);
		steps[it_index] = v_variant(schema.([] u8), "FIELD", name);
	}

	key = v_sequence(schema.([] u8), ..steps);
	table_add(*p.path_keys, copy_string(joined), key);
	return key;
}
