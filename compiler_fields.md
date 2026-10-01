# Public Compiler AST Field Inventory

Scope: the installed Jai compiler's public `Code_*` records reachable from the parser's 49 concrete node types, `Code_Node`, their public child records, the literal-value unions, and the public records for compiler-only node kinds.
Run `examples/code_field_inventory.jai` from `examples` to repeat the reflection dump after a compiler upgrade.
Fields are declared fields only: embedded `base`/`entry` fields are listed on each owner, but their members are classified on their defining record, not duplicated for every descendant.
Anonymous union arms are listed under their containing field.
This is a syntax-parser contract, not a claim that all compiler-produced values are available before typechecking.

- `S` = syntactic: source spelling, source-derived syntax flags, locations, or AST ownership/children (including compiler-normalised syntax).
- `M` = semantic: resolution, inferred types, evaluated values, or typechecking state.
- `G` = compiler-generated: expansion/desugaring output and implicit declarations or synthetic wrappers, not the source construct that requests them.
- `E` = export-only: compiler bookkeeping or opaque public payload with no supported syntax-level comparison.

A field in two columns has phase-dependent values or flags; compare only its source-derived portion at the syntax layer.
`base` and `entry` are syntactic structural embeddings even when their inherited `type` is semantic.
A null field can still belong to a category: classification describes its role, not whether this parser currently populates it.

## Shared Records And Literals

| Record | S | M | G | E |
| --- | --- | --- | --- | --- |
| `Code_Node` | `kind`, `location`; `node_flags` (source bits) | `type`; `node_flags` (typechecked bits) | `node_flags` (desugaring bits) | `serial` |
| `Code_Scope_Entry` | `base`, `name` | `import_target` | | |
| `Code_Argument` | `expression`, `name` | | | |
| `Code_Array_Literal_Info` | `element_type`, `alignment`, `array_members`, `array_literal_flags` (source bits) | `array_literal_flags` (resolved bits) | | |
| `Code_Struct_Literal_Info` | `type_expression`, `arguments` | | | |
| `Code_Comma_Separated_Argument` | `node`, `modifier` | | | |
| `Code_Pointer_Literal_Info` | | `global_symbol`, `string_or_array_literal`, `data_pointer`, `pointer_literal_type`, `offset_from_symbol` | | |
| `Code_Type_Definition` | `base` | `info` | | |
| `Code_Extract` | | | `base`, `from`, `index` | |
| `Code_Make_Varargs` | | `element_type`, `is_for_non_native_calling_convention` | `base`, `expressions` | |
| `Code_Resolved_Overload` | `source_expression` | `result` | `base` | |
| `Code_Literal` | `base`, `value_type`, `values`, `value_flags` (source bits) | `value_flags` (evaluated bits) | | |
| `Code_Literal.values` | `_string`, `_float64`, `_s64`, `_u64`, `struct_literal_info`, `array_literal_info` | `pointer_literal_info`, `type_info_literal_defn` | | |

`Code_Literal.values` is an anonymous union: only the arm selected by `value_type` is meaningful.
`Code_Pointer_Literal_Info.global_symbol` and `string_or_array_literal` likewise share an unnamed union.
A literal may be source-spelled or produced by evaluation; that changes the origin of the node, not the role of each union arm.
Numeric/string arm values are decoded syntax for source literals, while pointer/type-definition arms require compiler processing.

## Expressions And Types

| Record | S | M | G | E |
| --- | --- | --- | --- | --- |
| `Code_Ident` | `base`, `name`, `flags` (source bits) | `resolved_declaration`, `flags` (resolved bits) | | |
| `Code_Unary_Operator` | `base`, `operator_type`, `subexpression` | | | |
| `Code_Binary_Operator` | `base`, `operator_type`, `flags` (source bits), `left`, `right` | `flags` (resolved bits) | | |
| `Code_Cast` | `base`, `target_type`, `expression`, `cast_flags` (source bits) | `cast_flags` (resolved bits) | | |
| `Code_Procedure_Call` | `base`, `procedure_expression`, `arguments_unsorted`, `context_modification`, `flags` (source bits) | `resolved_procedure_expression`, `overloads`, `arguments_sorted`, `num_return_values_received`, `flags` (resolved bits) | `macro_expansion_block` | |
| `Code_Expression_Query` | `base`, `query_kind`, `expression_to_query` | | | |
| `Code_Type_Query` | `base`, `query_kind`, `type_to_query` | | | |
| `Code_Type_Instantiation` | `base`, `type_valued_expression`, `must_implement`, `pointer_to`, `type_directive_target`, `array_element_type`, `array_dimension`, `inst_flags` (source bits) | `result`, `inst_flags` (resolved bits) | | |
| `Code_Context` | `base` | | | |

`Code_Procedure_Call.arguments_unsorted` and `Code_Return.arguments_unsorted` preserve source order; their sorted counterparts are post-resolution arrangements.
`Code_Type_Instantiation.result` and the common `Code_Node.type` are not parser syntax even when a source type annotation exists.

## Declarations And Blocks

| Record | S | M | G | E |
| --- | --- | --- | --- | --- |
| `Code_Declaration` | `entry`, `type_inst`, `expression`, `flags` (source bits), `alignment_expression`, `notes`, `program_export_name` | `flags` (scope/resolved bits) | `flags` (generated bits) | |
| `Code_Comma_Separated_Arguments` | `base`, `arguments` | | | |
| `Code_Compound_Declaration` | `entry`, `comma_separated_assignment`, `declaration_properties`, `alignment_expression`, `notes`, `operator_type` | | | |
| `Code_Block` | `base`, `parent`, `block_type`, `block_flags` (source bits), `belongs_to_struct`, `statements`, `owning_statement` | `members`, `block_flags` (resolved bits) | | |
| `Code_Procedure_Header` | `base`, `arguments`, `returns`, `parameter_usings`, `foreign_function_name`, `library_identifier`, `deprecation_string`, `modify_directives`, `body_or_null`, `procedure_flags` (source bits), `notes` | `name`, `procedure_flags` (resolved bits) | `constants_block`, `polymorph_source_header` | |
| `Code_Procedure_Body` | `base`, `block`, `header`, `body_flags` (source bits) | `body_flags` (resolved bits) | | |
| `Code_Struct` | `base`, `modify_directives`, `block`, `arguments_block`, `notes`, `textual_flags`, `alignment` (source-specified) | `defined_type`, `alignment` (computed) | `constants_block` | |
| `Code_Enum` | `base`, `internal_type_inst`, `block`, `notes`, `marked_as_complete`, `marked_as_specified`, `is_flags` | `internal_type`, `external_type` | | |
| `Code_Note` | `base`, `text`, `note_flags` (source bits) | `note_flags` (processed bits) | | |
| `Code_Placeholder` | `base` | | | |

`Code_Procedure_Header.name` is inferred from the owning declaration, not a field of the source-spelled procedure header.
`constants_block` and `polymorph_source_header` describe compiler-prepared representations.
A syntactic `arguments_block` can be a wrapper around source aggregate parameters; generated blocks are classified by what their *contents* represent, not by whether the wrapper was allocated by the compiler.

## Statements And Control Flow

| Record | S | M | G | E |
| --- | --- | --- | --- | --- |
| `Code_While` | `base`, `condition`, `block` | | | |
| `Code_If` | `base`, `condition`, `then_block`, `else_block`, `if_flags` (source bits), `static_if_flags` (source bits) | `if_flags` (resolved bits), `static_if_flags` (evaluation bits), `static_if_accepted_case` | | |
| `Code_Case` | `base`, `condition`, `then_block`, `owning_if`, `marked_as_fallthrough` | | | |
| `Code_For` | `base`, `iteration_expression`, `iteration_expression_right`, `block`, `ident_it`, `ident_it_index`, `want_replacement_for_expansion`, `want_pointer_expression`, `want_reverse_expression`, `for_flags` (source bits) | `for_flags` (evaluated bits) | `ident_decl`, `index_decl`, `macro_expansion_procedure_call` | |
| `Code_Loop_Control` | `base`, `control_type`, `target_ident` | | | |
| `Code_Return` | `base`, `arguments_unsorted`, `return_flags` (source bits) | `arguments_sorted`, `return_flags` (resolved bits) | | |
| `Code_Defer` | `base`, `block`, `is_backticked` | | | |
| `Code_Push_Context` | `base`, `to_push`, `block`, `push_context_flags` (source bits) | `push_context_flags` (resolved bits) | | |
| `Code_Using` | `base`, `expression`, `filter_type`, `filter_expression`, `no_parameters` | | | |
| `Code_Asm` | `base` | | | `b1`, `b2`, `b3` |

The three `Code_Asm` payload fields are intentionally opaque public storage, not assembly syntax fields.
The parser keeps assembly features, statements, operands, and spans in its own nodes.
`Code_For.ident_decl`/`index_decl` describe implicit/generated iterator declarations; explicit source bindings are `ident_it`/`ident_it_index`.

## Directives

| Record | S | M | G | E |
| --- | --- | --- | --- | --- |
| `Code_Directive_Add_Context` | `base`, `expression` | | | |
| `Code_Directive_Bake` | `base`, `procedure_call`, `bake_type` | | | |
| `Code_Directive_Bytes` | `base`, `expression` | | | |
| `Code_Directive_Code` | `base`, `expression`, `code_flags` (source bits) | `code_flags` (processed bits) | | |
| `Code_Directive_Context_Type` | `base` | | | |
| `Code_Directive_Exists` | `base`, `query_expression`, `sync_expression` | | | |
| `Code_Directive_Import` | `base`, `name`, `flags` (source bits), `module_parameters_call`, `program_parameters_call` | `flags` (resolved bits), `import_type` | | |
| `Code_Directive_Insert` | `base`, `expression`, `scope_redirection`, `break_replacement`, `continue_replacement`, `remove_replacement` | | `expansion`, `is_internal` | |
| `Code_Directive_Library` | `base`, `name`, `library_flags` (source bits) | `library_flags` (resolved bits) | | |
| `Code_Directive_Load` | `base`, `short_name`, `load_flags` (source bits) | `fully_pathed_filename`, `loaded_string`, `load_flags` (resolved bits) | | |
| `Code_Directive_Location` | `base`, `expression`, `is_caller_location` | | | |
| `Code_Directive_Modify` | `base`, `block` | | | |
| `Code_Directive_Module_Parameters` | `base`, `module_parameters`, `program_parameters`, `common_code` | | | |
| `Code_Directive_Overlay` | `base`, `target_expression`, `declaration_or_using` | | | |
| `Code_Directive_Poke_Name` | `base`, `name` | `module_struct` | | |
| `Code_Directive_Procedure_Name` | `base`, `argument` | | | |
| `Code_Directive_Run` | `base`, `flags` (source bits), `assertion_string` | `flags` (resolved bits) | `procedure` | |
| `Code_Directive_Scope` | `base`, `scope_type` | | | |
| `Code_Directive_Through` | `base` | | | |
| `Code_Directive_Wildcard` | `base`, `index` | | | |

`#run` source expressions are lowered into a compiler procedure, so `Code_Directive_Run.procedure` is not a source child to compare literally.
`#char` and `#filepath` may lower to literal nodes rather than directive nodes.
`program_export_name` on declarations is *source-spelled* `#program_export` metadata, not export-only compiler bookkeeping.
Export-only here means the public compiler representation does not reveal the syntax or semantics behind a field; it does not mean the source requests a program export.
