#import "File";
#import "String";

Parser_Follow_Flags :: enum_flags u8 {
	LOAD :: 0x1;
	IMPORT :: 0x2;
	IMPORT_FILE :: 0x4;
	IMPORT_DIR :: 0x8;
	ALL_IMPORTS :: IMPORT | IMPORT_FILE | IMPORT_DIR;
	ALL :: LOAD | ALL_IMPORTS;
}

Parser_Imported_File :: struct {
	filename: string;
	source: string;
	parsed: Parsed_Source;
}

Parser_Imported_Module :: struct {
	declaration: *Parser_Declaration;
	filename: string;
	source: string;
	parsed: Parsed_Source;
	loaded_files: [..] Parser_Imported_File;
	unresolved_loads: [..] *Parser_Directive_Load;
	load_limit_reached: bool;
}

Parser_Import_Binding :: struct {
	reference: *Parser_Ident;
	declaration: *Parser_Declaration;
}

Parser_Mapped_Name :: struct {
	using_node: *Parser_Using;
	source_name: string;
	exported_name: string;
	declaration: *Parser_Declaration;
}

Parser_Map_Collision :: struct {
	using_node: *Parser_Using;
	other_using_node: *Parser_Using;
	exported_name: string;
	first: *Parser_Declaration;
	second: *Parser_Declaration;
}

Parser_File_Imports :: struct {
	modules: [..] Parser_Imported_Module;
	loaded_files: [..] Parser_Imported_File;
	unresolved_imports: [..] *Parser_Directive_Import;
	unresolved_loads: [..] *Parser_Directive_Load;
	unsupported_using_filters: [..] *Parser_Using;
	mapped_names: [..] Parser_Mapped_Name;
	map_collisions: [..] Parser_Map_Collision;
	bindings: [..] Parser_Import_Binding;
	load_limit_reached: bool;
}

resolve_file_imports :: (
	parsed: *Parsed_Source,
	import_path: [] string = .[],
	follow: Parser_Follow_Flags = .ALL,
	map_names: (using_node: *Parser_Using, names: [] string) -> bool = null,
	aggregate_fields: (using_node: *Parser_Using, bindings: *[..] Parser_Binding) -> bool = null
) -> Parser_File_Imports {
	result: Parser_File_Imports;
	if !parsed.root || parsed.root.kind != .BLOCK || follow == 0 {
		return result;
	}


	inference_pool: Pool;
	set_allocators(*inference_pool);
	defer release(*inference_pool);

	parsed.root_scope.inference_pool = *inference_pool;
	defer parsed.root_scope.inference_pool = null;

	resolve_lexical_references(parsed.root_scope);
	if follow & .LOAD != 0 {
		if parsed.fully_pathed_filename {
			root_module: Parser_Imported_Module;
			root_module.filename = parsed.fully_pathed_filename;
			load_module_files(*root_module, parsed);
			result.loaded_files = root_module.loaded_files;
			result.unresolved_loads = root_module.unresolved_loads;
			result.load_limit_reached = root_module.load_limit_reached;
		} else {
			for parsed.root.(*Parser_Block).statements {
				if it.kind == .DIRECTIVE_LOAD {
					array_add(*result.unresolved_loads, it.(*Parser_Directive_Load));
				}
			}
		}
	}

	for parsed.root.(*Parser_Block).statements {
		declaration: *Parser_Declaration;
		import: *Parser_Directive_Import;
		item := it;
		if it.kind == .USING {
			item = it.(*Parser_Using).expression;
		}

		if !item {
			continue;
		}


		if item.kind == .DECLARATION {
			declaration = item.(*Parser_Declaration);
			if declaration.expression && declaration.expression.kind == .DIRECTIVE_IMPORT {
				import = declaration.expression.(*Parser_Directive_Import);
			}
		} else if item.kind == .DIRECTIVE_IMPORT {
			import = item.(*Parser_Directive_Import);
		}

		if !import {
			continue;
		}


		if import.import_type == .FULL_TEXT {
			continue;
		}


		if import.import_type == .PATH_TO_FILE && follow & .IMPORT_FILE == 0
			|| import.import_type == .PATH_TO_DIRECTORY && follow & .IMPORT_DIR == 0
			|| import.import_type != .PATH_TO_FILE && import.import_type != .PATH_TO_DIRECTORY && follow & .IMPORT == 0 {
			continue;
		}


		filename: string;
		source: string;
		success := false;
		if import.import_type == .PATH_TO_FILE || import.import_type == .PATH_TO_DIRECTORY {
			if !parsed.fully_pathed_filename {
				array_add(*result.unresolved_imports, import);
				continue;
			}


			path := join(path_strip_filename(parsed.fully_pathed_filename), import.name);
			filename = ifx import.import_type == .PATH_TO_DIRECTORY
				then join(path, "/module.jai")
				else path;
			if filename.data != path.data {
				free(path);
			}
			source, success = read_entire_file(filename, log_errors=false);
		} else {
			for import_path {
				filename = join(it, "/", import.name, ".jai");
				source, success = read_entire_file(filename, log_errors=false);
				if success {
					break;
				}


				free(filename);
				filename = join(it, "/", import.name, "/module.jai");
				source, success = read_entire_file(filename, log_errors=false);
				if success {
					break;
				}


				free(filename);
				filename = "";
			}
		}

		if !success {
			if filename {
				free(filename);
			}

			array_add(*result.unresolved_imports, import);

			continue;
		}


		module: Parser_Imported_Module;
		module.declaration = declaration;
		module.filename = filename;
		module.source = source;
		module.parsed = parse_file(source, filename);
		array_add(*result.modules, module);
		if follow & .LOAD != 0 {
			load_module_files(*result.modules[result.modules.count - 1], *module.parsed);
		}
	}

	collect_using_mappings(parsed.root_scope, *result, map_names, aggregate_fields);
	collect_mapping_conflicts(parsed.root_scope, *result);
	resolve_bare_import_references(parsed.root_scope, *result);
	resolve_import_members(parsed.root_scope, *result);

	return result;
}

bind_import_reference :: (imports: *Parser_File_Imports, reference: *Parser_Ident, declaration: *Parser_Declaration) {
	if declaration {
		reference.resolved_declaration = declaration;
		array_add(*imports.bindings, .{reference = reference, declaration = declaration});
	}
}

resolve_import_members :: (scope: *Parser_Lexical_Scope, imports: *Parser_File_Imports) {
	for access: scope.member_accesses {
		if access.left.kind != .IDENT || access.right.kind != .IDENT {
			continue;
		}


		for module: imports.modules {
			if module.declaration && access.left.(*Parser_Ident).resolved_declaration == module.declaration {
				bind_import_reference(imports, access.right.(*Parser_Ident), lookup_import_binding(*module, access.right.(*Parser_Ident).name));
				break;
			}
		}
	}

	for scope.children {
		resolve_import_members(it, imports);
	}
}

lookup_import_binding :: (module: *Parser_Imported_Module, name: string) -> *Parser_Declaration {
	for module.parsed.root_scope.bindings {
		if it.name == name {
			return it.declaration;
		}
	}


	return lookup_loaded_binding(module.loaded_files, name);
}

lookup_loaded_binding :: (files: [] Parser_Imported_File, name: string) -> *Parser_Declaration {
	for files {
		for it.parsed.root_scope.bindings {
			if it.name == name {
				return it.declaration;
			}
		}
	}


	return null;
}

import_name_visible :: (filter: *Parser_Using, name: string) -> bool {
	if filter.filter_type == .NONE {
		return true;
	}


	if filter.filter_type != .ONLY && filter.filter_type != .EXCEPT {
		return false;
	}


	if !filter.filter_expression || filter.filter_expression.kind != .LITERAL {
		return false;
	}


	found := false;
	for filter.filter_expression.(*Parser_Literal).array_literal_info.array_members {
		if it.(*Parser_Literal)._string == name {
			found = true;
			break;
		}
	}

	return ifx filter.filter_type == .ONLY
		then found
		else !found;
}

using_targets_module :: (using_node: *Parser_Using, module: *Parser_Imported_Module) -> bool {
	if !module.declaration || !using_node.expression {
		return false;
	}


	expression := using_node.expression;
	return expression == module.declaration
		|| expression.kind == .IDENT && expression.(*Parser_Ident).resolved_declaration == module.declaration;
}

collect_using_mappings :: (
	scope: *Parser_Lexical_Scope,
	imports: *Parser_File_Imports,
	map_names: (using_node: *Parser_Using, names: [] string) -> bool,
	aggregate_fields: (using_node: *Parser_Using, bindings: *[..] Parser_Binding) -> bool
) {
	for using_node: scope.usings {
		if using_node.filter_type != .MAP {
			continue;
		}


		handled := false;
		for module: imports.modules {
			if using_targets_module(using_node, *module) {
				handled = map_names && map_import_names(imports, using_node, *module, map_names);
				break;
			}
		}

		if !handled && map_names {
			provided := false;
			if aggregate_fields && using_node.expression && using_node.expression.kind == .DECLARATION {
				bindings: [..] Parser_Binding;
				provided = aggregate_fields(using_node, *bindings);
				if provided {
					handled = map_using_names(imports, using_node, bindings, map_names);
				}

				array_free(bindings);
			}

			if !provided {
				handled = map_aggregate_names(scope, imports, using_node, map_names);
			}
		}

		if !handled {
			array_add(*imports.unsupported_using_filters, using_node);
		}
	}

	for scope.children {
		collect_using_mappings(it, imports, map_names, aggregate_fields);
	}
}

collect_mapping_conflicts :: (scope: *Parser_Lexical_Scope, imports: *Parser_File_Imports) {
	for using_node: scope.usings {
		for mapping, index: imports.mapped_names {
			if mapping.using_node != using_node || !mapping.exported_name {
				continue;
			}


			for binding: scope.bindings {
				if binding.name == mapping.exported_name {
					array_add(
						*imports.map_collisions, .{
							using_node = using_node,
							exported_name = mapping.exported_name,
							first = binding.declaration,
							second = mapping.declaration,
						}
					);
				}
			}

			for prior_index: 0..index-1 {
				prior := imports.mapped_names[prior_index];
				if prior.using_node == using_node || prior.exported_name != mapping.exported_name {
					continue;
				}


				for scope.usings {
					if it == prior.using_node {
						array_add(
							*imports.map_collisions, .{
								using_node = prior.using_node,
								other_using_node = using_node,
								exported_name = prior.exported_name,
								first = prior.declaration,
								second = mapping.declaration,
							}
						);
						break;
					}
				}
			}
		}
	}

	for scope.children {
		collect_mapping_conflicts(it, imports);
	}
}

map_import_names :: (imports: *Parser_File_Imports, using_node: *Parser_Using, module: *Parser_Imported_Module, map_names: (using_node: *Parser_Using, names: [] string) -> bool) -> bool {
	bindings: [..] Parser_Binding;
	for module.parsed.root_scope.bindings {
		array_add(*bindings, it);
	}

	for module.loaded_files {
		for it.parsed.root_scope.bindings {
			array_add(*bindings, it);
		}
	}

	success := map_using_names(imports, using_node, bindings, map_names);
	array_free(bindings);
	return success;
}

resolve_struct_alias :: (declaration: *Parser_Declaration, root_scope: *Parser_Lexical_Scope) -> *Parser_Declaration {
	visited: [..]*Parser_Declaration;
	defer array_free(visited);

	while declaration && binding_is_unique(root_scope, declaration) {
		if declaration.expression && declaration.expression.kind == .STRUCT {
			return declaration;
		}


		if declaration.flags & .IS_CONSTANT == 0 || !declaration.expression || declaration.expression.kind != .IDENT {
			return null;
		}


		for visited {
			if it == declaration {
				return null;
			}
		}


		array_add(*visited, declaration);
		declaration = declaration.expression.(*Parser_Ident).resolved_declaration;
	}


	return null;
}

resolve_struct_instantiation :: (expression: *Parser_Node, root_scope: *Parser_Lexical_Scope, type_arguments: *[]Parser_Argument, visited_types: *[..]*Parser_Node = null) -> *Parser_Declaration {
	if !expression || expression.kind != .PROCEDURE_CALL {
		return null;
	}


	call := expression.(*Parser_Procedure_Call);
	if !call.procedure_expression || call.procedure_expression.kind != .IDENT || call.arguments_unsorted.count == 0 {
		return null;
	}


	declaration := resolve_struct_alias(call.procedure_expression.(*Parser_Ident).resolved_declaration, root_scope);

	if !declaration || !binding_is_unique(root_scope, declaration) || !declaration.expression || declaration.expression.kind != .STRUCT {
		return null;
	}


	structure := declaration.expression.(*Parser_Struct);
	if structure.modify_directives.count != 0 || structure.constants_block && structure.constants_block.statements.count != 0 || !structure.arguments_block || structure.arguments_block.statements.count != call.arguments_unsorted.count {
		return null;
	}


	matched: [..]bool;
	defer array_free(matched);

	for structure.arguments_block.statements {
		array_add(*matched, false);
	}

	for argument, index: call.arguments_unsorted {
		parameter_index := index;
		if argument.name {
			found := false;
			for parameter_node, candidate_index: structure.arguments_block.statements {
				if parameter_node.kind == .DECLARATION && parameter_node.(*Parser_Declaration).name == argument.name.name {
					parameter_index = candidate_index;
					found = true;
					break;
				}
			}

			if !found {
				return null;
			}
		}


		parameter_node := structure.arguments_block.statements[parameter_index];
		if parameter_node.kind != .DECLARATION || matched[parameter_index] || !argument.expression {
			return null;
		}


		matched[parameter_index] = true;


		parameter := parameter_node.(*Parser_Declaration);
		if (parameter.expression || !parameter.type_inst || !parameter.type_inst.type_valued_expression || parameter.type_inst.must_implement
			|| parameter.type_inst.type_valued_expression.kind != .IDENT
			|| parameter.type_inst.type_valued_expression.(*Parser_Ident).name != "Type"
			|| !parsed_primitive_type(argument.expression, root_scope) && !resolve_complete_aggregate_type(argument.expression, root_scope, visited_types).declaration
		) {
			return null;
		}
	}


	type_arguments.* = call.arguments_unsorted;
	return declaration;
}

resolve_struct_declaration :: (expression: *Parser_Node, root_scope: *Parser_Lexical_Scope, visited_types: *[..]*Parser_Node = null) -> *Parser_Declaration {
	query_expressions: [..]*Parser_Node;
	defer array_free(query_expressions);

	visited_values: [..]*Parser_Declaration;
	defer array_free(visited_values);

	while expression && expression.kind == .EXPRESSION_QUERY {
		for query_expressions {
			if it == expression {
				return null;
			}
		}


		array_add(*query_expressions, expression);
		query := expression.(*Parser_Expression_Query);
		if query.query_kind != .TYPE_OF {
			return null;
		}


		expression = infer_aggregate_expression_type(query.expression_to_query, *visited_values, root_scope);
	}


	if expression && expression.kind == .PROCEDURE_CALL {
		type_arguments: []Parser_Argument;
		return resolve_struct_instantiation(expression, root_scope, *type_arguments, visited_types);
	}


	if !expression || expression.kind != .IDENT {
		return null;
	}


	type_declaration := expression.(*Parser_Ident).resolved_declaration;
	visited: [..]*Parser_Declaration;
	defer array_free(visited);

	while type_declaration {
		if !binding_is_unique(root_scope, type_declaration) {
			return null;
		}


		if !type_declaration.expression || type_declaration.expression.kind != .IDENT {
			break;
		}


		if type_declaration.flags & .IS_CONSTANT == 0 {
			return null;
		}


		for visited {
			if it == type_declaration {
				return null;
			}
		}


		array_add(*visited, type_declaration);
		type_declaration = type_declaration.expression.(*Parser_Ident).resolved_declaration;
	}


	if type_declaration && type_declaration.expression && type_declaration.expression.kind == .STRUCT {
		structure := type_declaration.expression.(*Parser_Struct);
		if !structure.arguments_block || structure.arguments_block.statements.count == 0 {
			return type_declaration;
		}
	}


	return null;
}

find_binding_scope :: (scope: *Parser_Lexical_Scope, declaration: *Parser_Declaration) -> *Parser_Lexical_Scope {
	for scope.bindings {
		if it.declaration == declaration {
			return scope;
		}
	}


	for scope.children {
		found := find_binding_scope(it, declaration);
		if found {
			return found;
		}
	}


	return null;
}

binding_is_unique :: (root_scope: *Parser_Lexical_Scope, declaration: *Parser_Declaration) -> bool {
	binding_scope := find_binding_scope(root_scope, declaration);
	if !binding_scope {
		return false;
	}


	for binding_scope.bindings {
		if it.name == declaration.name && it.declaration != declaration {
			return false;
		}
	}


	return true;
}

resolve_called_procedure :: (declaration: *Parser_Declaration, root_scope: *Parser_Lexical_Scope) -> *Parser_Procedure_Header {
	visited: [..]*Parser_Declaration;
	defer array_free(visited);

	while declaration && binding_is_unique(root_scope, declaration) {
		for visited {
			if it == declaration {
				return null;
			}
		}


		array_add(*visited, declaration);
		if declaration.expression && declaration.expression.kind == .PROCEDURE_HEADER {
			return declaration.expression.(*Parser_Procedure_Header);
		}


		if declaration.flags & .IS_CONSTANT == 0 || declaration.type_inst
			|| !declaration.expression || declaration.expression.kind != .IDENT {
			return null;
		}


		declaration = declaration.expression.(*Parser_Ident).resolved_declaration;
	}


	return null;
}

Aggregate_Call_Match :: enum {
	UNKNOWN;
	MATCH;
	CONVERSION;
	MISMATCH;

	INTEGER_FLOAT32_CONVERSION;
	INTEGER_FLOAT64_CONVERSION;
	AGGREGATE_CONVERSION :: 8;
	FLOAT_WIDTH_CONVERSION :: 9;

	INTEGER_U8\_CONVERSION :: ( 8 << 8) | 6;
	INTEGER_U16_CONVERSION :: (16 << 8) | 6;
	INTEGER_U32_CONVERSION :: (32 << 8) | 6;
	INTEGER_U64_CONVERSION :: (64 << 8) | 6;

	INTEGER_S8\_CONVERSION :: ( 8 << 8) | 7;
	INTEGER_S16_CONVERSION :: (16 << 8) | 7;
	INTEGER_S32_CONVERSION :: (32 << 8) | 7;
	INTEGER_S64_CONVERSION :: (64 << 8) | 7;
}

TYPED_INTEGER_CONVERSION_FLAG :: 128;

Parsed_Aggregate_Type :: struct {
	declaration: *Parser_Declaration;
	type_arguments: []Parser_Argument;
	polymorphic_call: *Parser_Procedure_Call;
}

resolve_complete_aggregate_type :: (expression: *Parser_Node, root_scope: *Parser_Lexical_Scope, visited_types: *[..]*Parser_Node = null) -> Parsed_Aggregate_Type {
	if !expression {
		return .{};
	}


	local_types: [..]*Parser_Node;
	defer array_free(local_types);

	if !visited_types {
		visited_types = *local_types;
	}

	for visited_types.* {
		if it == expression {
			return .{};
		}
	}


	array_add(visited_types, expression);
	defer visited_types.count -= 1;

	queries: [..]*Parser_Node;
	defer array_free(queries);

	visited: [..]*Parser_Declaration;
	defer array_free(visited);

	while expression && expression.kind == .EXPRESSION_QUERY {
		for queries {
			if it == expression {
				return .{};
			}
		}


		array_add(*queries, expression);
		query := expression.(*Parser_Expression_Query);
		if query.query_kind != .TYPE_OF {
			return .{};
		}


		expression = infer_aggregate_expression_type(query.expression_to_query, *visited, root_scope);
	}

	aliases: [..]*Parser_Declaration;
	defer array_free(aliases);

	while expression && expression.kind == .IDENT {
		alias := expression.(*Parser_Ident).resolved_declaration;
		if !alias || !binding_is_unique(root_scope, alias) || !alias.expression || alias.expression.kind == .STRUCT {
			break;
		}


		if alias.flags & .IS_CONSTANT == 0 {
			return .{};
		}


		for aliases {
			if it == alias {
				return .{};
			}
		}


		array_add(*aliases, alias);
		expression = alias.expression;
	}


	declaration := resolve_struct_declaration(expression, root_scope, visited_types);
	polymorphic_call: *Parser_Procedure_Call;
	type_arguments: []Parser_Argument;

	if !declaration && expression && expression.kind == .PROCEDURE_CALL {
		call := expression.(*Parser_Procedure_Call);
		if call.procedure_expression && call.procedure_expression.kind == .IDENT {
			header := resolve_called_procedure(call.procedure_expression.(*Parser_Ident).resolved_declaration, root_scope);
			if (header && header.procedure_flags & .POLYMORPHIC != 0
				&& header.arguments.count > 0 && header.arguments.count == call.arguments_unsorted.count
				&& header.returns.count == 1 && header.returns[0].type_inst && !header.returns[0].type_inst.must_implement
				&& instantiate_polymorphic_aggregate_call(call, header, *visited, root_scope) == expression
			) {
				return_expression := header.returns[0].type_inst.type_valued_expression;
				if return_expression && return_expression.kind == .PROCEDURE_CALL {
					instantiation := return_expression.(*Parser_Procedure_Call);
					candidate: *Parser_Declaration;
					if instantiation.procedure_expression && instantiation.procedure_expression.kind == .IDENT {
						candidate = resolve_struct_alias(instantiation.procedure_expression.(*Parser_Ident).resolved_declaration, root_scope);
					}

					if candidate && binding_is_unique(root_scope, candidate) && candidate.expression && candidate.expression.kind == .STRUCT {
						structure := candidate.expression.(*Parser_Struct);
						if (structure.arguments_block && structure.arguments_block.statements.count == header.arguments.count
							&& instantiation.arguments_unsorted.count == header.arguments.count
						) {
							complete := true;
							return_type := Parsed_Aggregate_Type.{declaration = candidate, type_arguments = instantiation.arguments_unsorted};
							for index: 0..instantiation.arguments_unsorted.count-1 {
								argument := aggregate_argument_expression(return_type, index);
								aggregate_node := structure.arguments_block.statements[index];
								if aggregate_node.kind != .DECLARATION || !argument || argument.kind != .IDENT {
									complete = false;
									break;
								}


								aggregate_parameter := aggregate_node.(*Parser_Declaration);
								if (!aggregate_parameter.type_inst || aggregate_parameter.type_inst.must_implement || aggregate_parameter.expression
									|| !aggregate_parameter.type_inst.type_valued_expression || aggregate_parameter.type_inst.type_valued_expression.kind != .IDENT
									|| aggregate_parameter.type_inst.type_valued_expression.(*Parser_Ident).name != "Type"
								) {
									complete = false;
									break;
								}


								actual := polymorphic_argument_type(call, header, argument.(*Parser_Ident).name, *visited, root_scope);
								if !resolve_complete_aggregate_type(actual, root_scope).declaration {
									complete = false;
									break;
								}
							}

							if complete {
								declaration = candidate;
								type_arguments = instantiation.arguments_unsorted;
								polymorphic_call = call;
							}
						}
					}
				}
			}
		}
	}

	if !declaration {
		return .{};
	}


	structure := declaration.expression.(*Parser_Struct);
	if !structure.block {
		return .{};
	}


	bindings: [..]Parser_Binding;
	defer array_free(bindings);

	if !collect_aggregate_bindings(structure.block.statements, *bindings, root_scope) {
		return .{};
	}


	for binding, index: bindings {
		for prior: 0..index-1 {
			if bindings[prior].name == binding.name {
				return .{};
			}
		}
	}


	if expression && expression.kind == .PROCEDURE_CALL && !polymorphic_call {
		if !resolve_struct_instantiation(expression, root_scope, *type_arguments, visited_types) {
			return .{};
		}


		for type_arguments {
			if !parsed_primitive_type(it.expression, root_scope) && !resolve_complete_aggregate_type(it.expression, root_scope, visited_types).declaration {
				return .{};
			}
		}
	}


	return .{declaration = declaration, type_arguments = type_arguments, polymorphic_call = polymorphic_call};
}

aggregate_argument_expression :: (aggregate: Parsed_Aggregate_Type, parameter_index: s64) -> *Parser_Node {
	structure := aggregate.declaration.expression.(*Parser_Struct);
	parameter := structure.arguments_block.statements[parameter_index].(*Parser_Declaration);
	for argument, index: aggregate.type_arguments {
		if argument.name && argument.name.name == parameter.name || !argument.name && index == parameter_index {
			return argument.expression;
		}
	}


	return null;
}

substitute_aggregate_field_type :: (expression: *Parser_Node, container: Parsed_Aggregate_Type, root_scope: *Parser_Lexical_Scope, visited: *[..]*Parser_Declaration) -> *Parser_Node {
	if !expression {
		return null;
	}


	structure := container.declaration.expression.(*Parser_Struct);
	if expression.kind == .IDENT {
		for index: 0..container.type_arguments.count-1 {
			parameter := structure.arguments_block.statements[index].(*Parser_Declaration);
			if expression.(*Parser_Ident).resolved_declaration == parameter {
				argument := aggregate_argument_expression(container, index);
				if container.polymorphic_call {
					header := resolve_called_procedure(container.polymorphic_call.procedure_expression.(*Parser_Ident).resolved_declaration, root_scope);
					return polymorphic_argument_type(container.polymorphic_call, header, argument.(*Parser_Ident).name, visited, root_scope);
				}


				return argument;
			}
		}
	}


	if expression.kind != .PROCEDURE_CALL || !root_scope.inference_pool {
		return expression;
	}


	call := expression.(*Parser_Procedure_Call);
	push_allocator(pool_allocator_proc, root_scope.inference_pool);
	copy := New(Parser_Procedure_Call);
	copy.* = call.*;
	copy.arguments_unsorted = NewArray(call.arguments_unsorted.count, Parser_Argument);
	for argument, index: call.arguments_unsorted {
		copy.arguments_unsorted[index] = argument;
		copy.arguments_unsorted[index].expression = substitute_aggregate_field_type(argument.expression, container, root_scope, visited);
	}

	return copy;
}

polymorphic_argument_type :: (call: *Parser_Procedure_Call, header: *Parser_Procedure_Header, variable_name: string, visited: *[..]*Parser_Declaration, root_scope: *Parser_Lexical_Scope) -> *Parser_Node {
	for parameter, index: header.arguments {
		if !parameter.type_inst || !parameter.type_inst.type_valued_expression || parameter.type_inst.type_valued_expression.kind != .IDENT {
			return null;
		}


		variable := parameter.type_inst.type_valued_expression.(*Parser_Ident);
		if variable.flags & .DEFINES_POLYMORPH_VARIABLE == 0 || variable.name != variable_name {
			continue;
		}


		for argument, argument_index: call.arguments_unsorted {
			if (argument.name && argument.name.name == parameter.name
				|| !argument.name && argument_index == index
			) {
				return infer_aggregate_expression_type(argument.expression, visited, root_scope);
			}
		}
	}


	return null;
}

compare_aggregate_types :: (left: *Parser_Node, right: *Parser_Node, root_scope: *Parser_Lexical_Scope) -> Aggregate_Call_Match {
	left_type := resolve_complete_aggregate_type(left, root_scope);
	right_type := resolve_complete_aggregate_type(right, root_scope);
	if !left_type.declaration || !right_type.declaration {
		return .UNKNOWN;
	}


	if left_type.declaration != right_type.declaration || left_type.type_arguments.count != right_type.type_arguments.count {
		return .MISMATCH;
	}


	for index: 0..left_type.type_arguments.count-1 {
		left_argument := aggregate_argument_expression(left_type, index);
		right_argument := aggregate_argument_expression(right_type, index);
		visited: [..]*Parser_Declaration;
		if left_type.polymorphic_call {
			left_header := resolve_called_procedure(left_type.polymorphic_call.procedure_expression.(*Parser_Ident).resolved_declaration, root_scope);
			left_argument = polymorphic_argument_type(left_type.polymorphic_call, left_header, left_argument.(*Parser_Ident).name, *visited, root_scope);
		}

		if right_type.polymorphic_call {
			right_header := resolve_called_procedure(right_type.polymorphic_call.procedure_expression.(*Parser_Ident).resolved_declaration, root_scope);
			right_argument = polymorphic_argument_type(right_type.polymorphic_call, right_header, right_argument.(*Parser_Ident).name, *visited, root_scope);
		}

		array_free(visited);
		left_primitive := parsed_primitive_type(left_argument, root_scope);
		right_primitive := parsed_primitive_type(right_argument, root_scope);
		if left_primitive || right_primitive {
			if !left_primitive || !right_primitive {
				return .MISMATCH;
			}


			if left_primitive != right_primitive {
				return .UNKNOWN;
			}


			continue;
		}


		match := compare_aggregate_types(left_argument, right_argument, root_scope);
		if match != .MATCH {
			return match;
		}
	}


	return .MATCH;
}

aggregate_members_hidden_by_filter :: (expression: *Parser_Node, filter: *Parser_Using, root_scope: *Parser_Lexical_Scope, visited: *[..]*Parser_Declaration = null) -> bool {
	if (filter.filter_type != .EXCEPT
		|| !filter.filter_expression || filter.filter_expression.kind != .LITERAL
	) {
		return false;
	}


	aggregate := resolve_complete_aggregate_type(expression, root_scope);
	if !aggregate.declaration {
		return false;
	}


	local_visited: [..]*Parser_Declaration;
	defer array_free(local_visited);

	if !visited {
		visited = *local_visited;
	}

	for visited.* {
		if it == aggregate.declaration {
			return false;
		}
	}

	array_add(visited, aggregate.declaration);
	defer visited.count -= 1;

	structure := aggregate.declaration.expression.(*Parser_Struct);
	if !structure.block {
		return false;
	}


	if aggregate.type_arguments.count > 0 {
		for parameter_node: structure.arguments_block.statements {
			parameter := parameter_node.(*Parser_Declaration);
			if !binding_is_unique(root_scope, parameter) || import_name_visible(filter, parameter.name) {
				return false;
			}
		}
	}


	return aggregate_statements_hidden_by_filter(structure.block.statements, filter, aggregate, root_scope, visited);
}

aggregate_statements_hidden_by_filter :: (statements: []*Parser_Node, filter: *Parser_Using, container: Parsed_Aggregate_Type, root_scope: *Parser_Lexical_Scope, visited: *[..]*Parser_Declaration) -> bool {
	for statement: statements {
		if statement.kind == .IF {
			conditional := statement.(*Parser_If);
			condition: bool;
			if (conditional.if_flags & .IS_STATIC == 0
				|| !evaluate_literal_boolean(conditional.condition, *condition, root_scope)
			) {
				return false;
			}


			branch := ifx condition
				then conditional.then_block
				else conditional.else_block;
			if branch && !aggregate_statements_hidden_by_filter(branch.statements, filter, container, root_scope, visited) {
				return false;
			}


			continue;
		}


		field: *Parser_Declaration;
		if statement.kind == .DECLARATION {
			field = statement.(*Parser_Declaration);
		} else if statement.kind == .USING {
			using_node := statement.(*Parser_Using);
			if !using_node.expression || using_node.expression.kind != .DECLARATION {
				return false;
			}


			field = using_node.expression.(*Parser_Declaration);
			if !field.type_inst || !field.type_inst.type_valued_expression {
				return false;
			}


			substitution_visited: [..]*Parser_Declaration;
			defer array_free(substitution_visited);

			field_type := substitute_aggregate_field_type(field.type_inst.type_valued_expression, container, root_scope, *substitution_visited);
			if !field_type || !aggregate_members_hidden_by_filter(field_type, using_node, root_scope, visited) {
				return false;
			}
		} else {
			return false;
		}


		if !binding_is_unique(root_scope, field) || import_name_visible(filter, field.name) {
			return false;
		}


		structure := container.declaration.expression.(*Parser_Struct);
		if container.type_arguments.count > 0 {
			for parameter_node: structure.arguments_block.statements {
				if field.name == parameter_node.(*Parser_Declaration).name {
					return false;
				}
			}
		}
	}


	return true;
}

match_aggregate_conversion :: (source: *Parser_Node, target: *Parser_Node, root_scope: *Parser_Lexical_Scope, conversion_path: *[..]*Parser_Declaration = null) -> Aggregate_Call_Match {
	source_type := resolve_complete_aggregate_type(source, root_scope);
	if !source_type.declaration {
		return .UNKNOWN;
	}


	local_path: [..]*Parser_Declaration;
	defer array_free(local_path);

	if !conversion_path {
		conversion_path = *local_path;
	}

	for conversion_path.* {
		if it == source_type.declaration {
			return .UNKNOWN;
		}
	}


	array_add(conversion_path, source_type.declaration);
	defer conversion_path.count -= 1;

	structure := source_type.declaration.expression.(*Parser_Struct);
	if !structure.block {
		return .UNKNOWN;
	}


	bindings: [..]Parser_Binding;
	defer array_free(bindings);
	if !collect_aggregate_bindings(structure.block.statements, *bindings, root_scope) {
		return .UNKNOWN;
	}


	matched := false;
	routes_hidden := true;
	for statement: structure.block.statements {
		if statement.kind != .USING {
			continue;
		}


		using_node := statement.(*Parser_Using);
		if !using_node.expression || using_node.expression.kind != .DECLARATION {
			return .UNKNOWN;
		}


		field := using_node.expression.(*Parser_Declaration);
		explicit_conversion := (field.flags & .IS_MARKED_AS_AS != 0);
		if !explicit_conversion && using_node.filter_type != .NONE {
			return .UNKNOWN;
		}


		if !field.type_inst || !field.type_inst.type_valued_expression {
			return .UNKNOWN;
		}


		visited: [..]*Parser_Declaration;
		field_type := substitute_aggregate_field_type(field.type_inst.type_valued_expression, source_type, root_scope, *visited);
		array_free(visited);

		comparison := ifx explicit_conversion
			then compare_aggregate_types(field_type, target, root_scope)
			else Aggregate_Call_Match.MISMATCH;
		if comparison == .MISMATCH {
			comparison = match_aggregate_conversion(field_type, target, root_scope, conversion_path);
		}

		if comparison == .UNKNOWN {
			return .UNKNOWN;
		}


		if comparison == .MATCH || comparison == .CONVERSION {
			hidden_route := (
				explicit_conversion && binding_is_unique(root_scope, field)
				&& aggregate_members_hidden_by_filter(field_type, using_node, root_scope)
			);
			if matched && (!routes_hidden || !hidden_route) {
				return .UNKNOWN;
			}


			routes_hidden = hidden_route;
			matched = true;
		}
	}


	return ifx matched
		then .CONVERSION
		else .MISMATCH;
}

parsed_primitive_type :: (expression: *Parser_Node, root_scope: *Parser_Lexical_Scope = null) -> string {
	visited: [..]*Parser_Declaration;
	defer array_free(visited);

	names: [] string = .["bool", "string", "s8", "s16", "s32", "s64", "u8", "u16", "u32", "u64", "float32", "float64"];
	while expression && expression.kind == .IDENT {
		ident := expression.(*Parser_Ident);
		if ident.name == "int" || ident.name == "float" {
			if ident.resolved_declaration {
					return "";
			}


			return ifx ident.name == "int" then "s64" else "float32";
		}


		for name: names {
			if ident.name == name {
				if ident.resolved_declaration || visited.count != 0 && (name == "bool" || name == "string") {
					return "";
				}


				return name;
			}
		}

		declaration := ident.resolved_declaration;
		if !root_scope || !declaration || !binding_is_unique(root_scope, declaration) || declaration.flags & .IS_CONSTANT == 0 {
			return "";
		}


		if declaration.type_inst {
			annotation := declaration.type_inst.type_valued_expression;
			if (!annotation || annotation.kind != .IDENT
				|| annotation.(*Parser_Ident).name != "Type" || annotation.(*Parser_Ident).resolved_declaration
			) {
				return "";
			}
		}

		if declaration.first_token > expression.first_token {
			binding_scope := find_binding_scope(root_scope, declaration);
			if binding_scope.owner && binding_scope.owner.kind == .BLOCK && binding_scope.owner.(*Parser_Block).block_type == .IMPERATIVE {
				return "";
			}
		}

		for visited {
			if it == declaration {
				return "";
			}
		}

		array_add(*visited, declaration);
		expression = declaration.expression;
	}


	return "";
}

integer_primitive_width :: (primitive: string) -> s64 {
	if primitive.count < 2 || (primitive[0] != #char "s" && primitive[0] != #char "u") {
		return 0;
	}


	if primitive[1] == {
		case #char "8";		return 8;
		case #char "1";		return 16;
		case #char "3";		return 32;
		case #char "6";		return 64;
	}

	return 0;
}

infer_primitive_expression_type :: (expression: *Parser_Node, visited: *[..]*Parser_Declaration, root_scope: *Parser_Lexical_Scope, typed: *bool = null, raw_literal: **Parser_Literal = null) -> string {
	if !expression {
		return "";
	}


	if expression.kind == .LITERAL {
		literal := expression.(*Parser_Literal);
		if raw_literal && literal.value_type == .NUMBER {
			raw_literal.* = literal;
		}

		if literal.value_type == {
			case .STRING;
				return "string";

			case .BOOLEAN;
				return "bool";

			case .NUMBER;
				if literal.value_flags & (.FLOAT | .DEFAULTS_TO_FLOAT64 | .REQUIRES_FLOAT64) != 0 {
					return ifx literal.value_flags & (.DEFAULTS_TO_FLOAT64 | .REQUIRES_FLOAT64) != 0
						then "float64"
						else "float32";
				}


				return "s64";
		}
	}


	if expression.kind == .CAST {
		cast_node := expression.(*Parser_Cast);
		if cast_node.target_type {
			primitive := parsed_primitive_type(cast_node.target_type.type_valued_expression, root_scope);
			if integer_primitive_width(primitive) != 0 || primitive == "float32" || primitive == "float64" {
				if typed {
					typed.* = true;
				}

				return primitive;
			}
		}


		return "";
	}


	if expression.kind != .IDENT {
		return "";
	}


	declaration := expression.(*Parser_Ident).resolved_declaration;
	if !declaration || !binding_is_unique(root_scope, declaration) {
		return "";
	}


	if raw_literal && declaration.first_token > expression.first_token {
		binding_scope := find_binding_scope(root_scope, declaration);
		if binding_scope.owner && binding_scope.owner.kind == .BLOCK && binding_scope.owner.(*Parser_Block).block_type == .IMPERATIVE {
			return "";
		}
	}


	for visited.* {
		if it == declaration {
			return "";
		}
	}


	array_add(visited, declaration);
	defer visited.count -= 1;

	if declaration.type_inst {
		if typed {
			typed.* = true;
		}

		return parsed_primitive_type(declaration.type_inst.type_valued_expression, root_scope);
	}


	if declaration.flags & .IS_CONSTANT == 0 {
		if typed {
			typed.* = true;
		}

		return infer_primitive_expression_type(declaration.expression, visited, root_scope, typed);
	}


	return infer_primitive_expression_type(declaration.expression, visited, root_scope, typed, raw_literal);
}

match_aggregate_call_arguments :: (call: *Parser_Procedure_Call, header: *Parser_Procedure_Header, root_scope: *Parser_Lexical_Scope, ranks: *[..]Aggregate_Call_Match = null) -> Aggregate_Call_Match {
	for parameter: header.arguments {
		if parameter.type_inst && parameter.type_inst.inst_flags & .VARARGS != 0 {
			return .UNKNOWN;
		}
	}


	if call.arguments_unsorted.count > header.arguments.count {
		return .MISMATCH;
	}


	matched_parameters: [..]bool;
	defer array_free(matched_parameters);

	for header.arguments {
		array_add(*matched_parameters, false);
	}


	unknown := false;
	converted := false;
	for argument, index: call.arguments_unsorted {
		parameter_index := index;
		if argument.name {
			found := false;
			for candidate, candidate_index: header.arguments {
				if candidate.name == argument.name.name {
					if found {
						return .UNKNOWN;
					}


					parameter_index = candidate_index;
					found = true;
				}
			}


			if !found {
				return .MISMATCH;
			}
		}


		if parameter_index >= header.arguments.count {
			return .MISMATCH;
		}


		if matched_parameters[parameter_index] {
			return .UNKNOWN;
		}


		matched_parameters[parameter_index] = true;

		parameter := header.arguments[parameter_index];
		if !parameter.type_inst || !parameter.type_inst.type_valued_expression {
			unknown = true;
			continue;
		}


		visited: [..]*Parser_Declaration;
		typed_primitive := false;
		literal_argument: *Parser_Literal;
		if argument.expression && argument.expression.kind == .LITERAL {
			literal_argument = argument.expression.(*Parser_Literal);
		}

		primitive := infer_primitive_expression_type(argument.expression, *visited, root_scope, *typed_primitive, *literal_argument);
		array_reset(*visited);
		parameter_primitive := parsed_primitive_type(parameter.type_inst.type_valued_expression, root_scope);
		if primitive && parameter_primitive {
			array_free(visited);
			if (primitive == parameter_primitive
				&& (primitive != "float32" && primitive != "float64"
					|| typed_primitive || literal_argument && literal_argument.value_type == .NUMBER
				)
			) {
				if ranks {
					array_add(ranks, .MATCH);
				}

				continue;
			}


			if primitive == "string" || primitive == "bool" || parameter_primitive == "string" || parameter_primitive == "bool" {
				return .MISMATCH;
			}


			primitive_width := integer_primitive_width(primitive);
			parameter_width := integer_primitive_width(parameter_primitive);
			if typed_primitive && primitive_width != 0 && parameter_width != 0 {
				primitive_signed := primitive[0] == #char "s";
				parameter_signed := parameter_primitive[0] == #char "s";
				if (parameter_width < primitive_width
					|| primitive_signed && !parameter_signed
					|| !primitive_signed && parameter_signed && parameter_width == primitive_width
				) {
					return .MISMATCH;
				}


				converted = true;
				if ranks {
					array_add(ranks, xx ((parameter_width << 8) | TYPED_INTEGER_CONVERSION_FLAG | (ifx parameter_signed then 7 else 6)));
				}

				continue;
			}


			if (typed_primitive
				&& (primitive_width != 0 && (parameter_primitive == "float32" || parameter_primitive == "float64")
					|| parameter_width != 0 && (primitive == "float32" || primitive == "float64")
				)
			) {
				return .MISMATCH;
			}


			if (typed_primitive
				&& (primitive == "float32" || primitive == "float64")
				&& (parameter_primitive == "float32" || parameter_primitive == "float64")
			) {
				if primitive == "float64" && parameter_primitive == "float32" {
					return .MISMATCH;
				}


				converted = true;
				if ranks {
					array_add(ranks, .FLOAT_WIDTH_CONVERSION);
				}

				continue;
			}


			if (primitive == "float64" && parameter_primitive == "float32"
				&& literal_argument && literal_argument.value_type == .NUMBER
				&& literal_argument.value_flags & .REQUIRES_FLOAT64 != 0
			) {
				return .MISMATCH;
			}


			if ((
					primitive == "s64" && (parameter_primitive == "float64" || parameter_primitive == "float32")
					|| primitive == "float32" && parameter_primitive == "float64"
					|| primitive == "float64" && parameter_primitive == "float32"
				)
				&& literal_argument && literal_argument.value_type == .NUMBER
			) {
				converted = true;
				if ranks {
					rank := Aggregate_Call_Match.FLOAT_WIDTH_CONVERSION;
					if primitive == "s64" {
						rank = ifx parameter_primitive == "float32"
							then .INTEGER_FLOAT32_CONVERSION
							else .INTEGER_FLOAT64_CONVERSION;
					}

					array_add(ranks, rank);
				}

				continue;
			}


			if (primitive == "s64"
				&& literal_argument && literal_argument.value_type == .NUMBER
				&& (parameter_primitive == "u8" && literal_argument._u64 <= 255
					|| parameter_primitive == "s8" && (
						literal_argument.value_flags & .MINUS_SIGN == 0 && literal_argument._u64 <= 127
						|| literal_argument.value_flags & .MINUS_SIGN != 0 && 0 - literal_argument._u64 <= 128
					)
					|| parameter_primitive == "u16" && literal_argument._u64 <= 65535
					|| parameter_primitive == "s16" && (
						literal_argument.value_flags & .MINUS_SIGN == 0 && literal_argument._u64 <= 32767
						|| literal_argument.value_flags & .MINUS_SIGN != 0 && 0 - literal_argument._u64 <= 32768
					)
					|| parameter_primitive == "u32" && literal_argument._u64 <= 4294967295
					|| parameter_primitive == "s32" && (
						literal_argument.value_flags & .MINUS_SIGN == 0 && literal_argument._u64 <= 2147483647
						|| literal_argument.value_flags & .MINUS_SIGN != 0 && 0 - literal_argument._u64 <= 2147483648
					)
				)
			) {
				converted = true;
				if ranks {
					rank := Aggregate_Call_Match.CONVERSION;
					if parameter_primitive.count >= 2 {
						signed_parameter := parameter_primitive[0] == #char "s";
						if parameter_primitive[1] == {
							case #char "8";
								rank = ifx signed_parameter
									then .INTEGER_S8_CONVERSION
									else .INTEGER_U8_CONVERSION;

							case #char "1";
								rank = ifx signed_parameter
									then .INTEGER_S16_CONVERSION
									else .INTEGER_U16_CONVERSION;

							case #char "3";
								rank = ifx signed_parameter
									then .INTEGER_S32_CONVERSION
									else .INTEGER_U32_CONVERSION;
						}
					}

					array_add(ranks, rank);
				}

				continue;
			}


			if (primitive == "s64" && parameter_primitive == "u64"
				&& literal_argument && literal_argument.value_type == .NUMBER
			) {
				if (literal_argument.value_flags & .MINUS_SIGN != 0
					&& literal_argument._u64 != 0
				) {
					return .MISMATCH;
				}


				converted = true;
				if ranks {
					array_add(ranks, .INTEGER_U64_CONVERSION);
				}

				continue;
			}


			if (primitive == "s64"
				&& (parameter_primitive == "u8" || parameter_primitive == "u16" || parameter_primitive == "u32"
					|| parameter_primitive == "s8" || parameter_primitive == "s16" || parameter_primitive == "s32"
				)
				&& literal_argument && literal_argument.value_type == .NUMBER
			) {
				return .MISMATCH;
			}


			unknown = true;
			continue;
		}


		argument_type := infer_aggregate_expression_type(argument.expression, *visited, root_scope);
		array_free(visited);

		if primitive && resolve_struct_declaration(parameter.type_inst.type_valued_expression, root_scope) || parameter_primitive && resolve_struct_declaration(argument_type, root_scope) {
			return .MISMATCH;
		}


		match := compare_aggregate_types(argument_type, parameter.type_inst.type_valued_expression, root_scope);
		if match == .MISMATCH {
			match = match_aggregate_conversion(argument_type, parameter.type_inst.type_valued_expression, root_scope);
		}


		if match == .MISMATCH {
			return match;
		}


		if match == .UNKNOWN {
			unknown = true;
		} else if match == .CONVERSION {
			converted = true;
		}

		if ranks {
			array_add(ranks, ifx match == .CONVERSION then .AGGREGATE_CONVERSION else match);
		}
	}


	for parameter, index: header.arguments {
		if matched_parameters[index] {
			continue;
		}


		if !parameter.expression {
			return .MISMATCH;
		}


		if !parameter.type_inst || !parameter.type_inst.type_valued_expression {
			return .UNKNOWN;
		}


		visited: [..]*Parser_Declaration;
		default_typed := false;
		default_type := infer_primitive_expression_type(parameter.expression, *visited, root_scope, *default_typed);
		array_free(visited);
		if (!default_type || default_type != parsed_primitive_type(parameter.type_inst.type_valued_expression, root_scope)
			|| (default_type == "float32" || default_type == "float64") && !default_typed
		) {
			return .UNKNOWN;
		}
	}


	return ifx unknown
		then .UNKNOWN
		else ifx converted
			then .CONVERSION
			else .MATCH;
}

compare_aggregate_call_ranks :: (match: Aggregate_Call_Match, ranks: []Aggregate_Call_Match, best_match: Aggregate_Call_Match, best_ranks: []Aggregate_Call_Match) -> bool, bool {
	better := match == .MATCH && best_match == .CONVERSION;
	worse := match == .CONVERSION && best_match == .MATCH;
	if match == .CONVERSION && best_match == .CONVERSION {
		aggregate_conversion := false;
		best_aggregate_conversion := false;
		unproved_numeric_crossing := false;

		for ranks {
			if it == .AGGREGATE_CONVERSION {
				aggregate_conversion = true;
			}

			if best_ranks[it_index] == .AGGREGATE_CONVERSION {
				best_aggregate_conversion = true;
			}

			if (it != best_ranks[it_index]
				&& (it == .FLOAT_WIDTH_CONVERSION || best_ranks[it_index] == .FLOAT_WIDTH_CONVERSION
					|| cast(s64) it & TYPED_INTEGER_CONVERSION_FLAG != 0
					|| cast(s64) best_ranks[it_index] & TYPED_INTEGER_CONVERSION_FLAG != 0
					|| it == .MATCH && best_ranks[it_index] != .AGGREGATE_CONVERSION
					|| best_ranks[it_index] == .MATCH && it != .AGGREGATE_CONVERSION
				)
			) {
				unproved_numeric_crossing = true;
			}
		}

		if aggregate_conversion != best_aggregate_conversion {
			if unproved_numeric_crossing {
				return false, false;
			}


			return !aggregate_conversion, aggregate_conversion;
		}


		for ranks {
			width := cast(s64) it >> 8;
			best_width := cast(s64) best_ranks[it_index] >> 8;
			integer_conversions := (width != 0 && best_width != 0);

			if (it == .MATCH && best_ranks[it_index] != .MATCH
				|| it == .INTEGER_FLOAT32_CONVERSION && best_ranks[it_index] == .INTEGER_FLOAT64_CONVERSION
				|| width != 0 && (best_ranks[it_index] == .INTEGER_FLOAT32_CONVERSION || best_ranks[it_index] == .INTEGER_FLOAT64_CONVERSION)
				|| integer_conversions && width < best_width
			) {
				better = true;
			} else if (it != .MATCH && best_ranks[it_index] == .MATCH
				|| it == .INTEGER_FLOAT64_CONVERSION && best_ranks[it_index] == .INTEGER_FLOAT32_CONVERSION
				|| best_width != 0 && (it == .INTEGER_FLOAT32_CONVERSION || it == .INTEGER_FLOAT64_CONVERSION)
				|| integer_conversions && width > best_width
			) {
				worse = true;
			}
		}
	}

	return better, worse;
}

resolve_overloaded_aggregate_call :: (call: *Parser_Procedure_Call, root_scope: *Parser_Lexical_Scope) -> *Parser_Procedure_Header {
	if !call.procedure_expression || call.procedure_expression.kind != .IDENT {
		return null;
	}


	declaration := call.procedure_expression.(*Parser_Ident).resolved_declaration;
	if !declaration {
		return null;
	}


	scope := find_binding_scope(root_scope, declaration);
	if !scope {
		return null;
	}


	inference_pool: Pool;
	owns_inference_pool := !root_scope.inference_pool;
	if owns_inference_pool {
		set_allocators(*inference_pool);
		root_scope.inference_pool = *inference_pool;
	}
	defer {
		if owns_inference_pool {
			root_scope.inference_pool = null;
			release(*inference_pool);
		}
	}

	selected: *Parser_Procedure_Header;
	best_match := Aggregate_Call_Match.MISMATCH;

	best_ranks: [..]Aggregate_Call_Match;
	defer array_free(best_ranks);

	for binding: scope.bindings {
		if binding.name != declaration.name {
			continue;
		}


		candidate := binding.declaration;
		if !candidate.expression || candidate.expression.kind != .PROCEDURE_HEADER {
			return null;
		}


		header := candidate.expression.(*Parser_Procedure_Header);
		if header.procedure_flags & .POLYMORPHIC != 0 {
			return null;
		}


		ranks: [..]Aggregate_Call_Match;
		defer array_free(ranks);

		match := match_aggregate_call_arguments(call, header, root_scope, *ranks);
		if match == .UNKNOWN {
			return null;
		}


		if match == .MATCH || match == .CONVERSION {
			better := !selected;
			worse := false;
			if selected {
				better, worse = compare_aggregate_call_ranks(match, ranks, best_match, best_ranks);
			}


			if better && !worse {
				selected = header;
				best_match = match;
				best_ranks.count = 0;
				for ranks {
					array_add(*best_ranks, it);
				}
			}
		}
	}


	if !selected {
		return null;
	}


	for binding: scope.bindings {
		if binding.name != declaration.name {
			continue;
		}


		header := binding.declaration.expression.(*Parser_Procedure_Header);
		if header == selected {
			continue;
		}


		ranks: [..]Aggregate_Call_Match;
		defer array_free(ranks);

		match := match_aggregate_call_arguments(call, header, root_scope, *ranks);
		if match == .UNKNOWN {
			return null;
		}


		if match == .MATCH || match == .CONVERSION {
			better, worse := compare_aggregate_call_ranks(best_match, best_ranks, match, ranks);
			if !better || worse {
				return null;
			}
		}
	}

	return selected;
}

instantiate_polymorphic_aggregate_call :: (call: *Parser_Procedure_Call, header: *Parser_Procedure_Header, visited: *[..]*Parser_Declaration, root_scope: *Parser_Lexical_Scope) -> *Parser_Node {
	if (header.arguments.count == 0 || header.arguments.count != call.arguments_unsorted.count || header.returns.count != 1
		|| header.modify_directives.count != 0
		|| header.constants_block && header.constants_block.statements.count != 0
	) {
		return null;
	}


	result := header.returns[0];
	if (!result.type_inst || result.type_inst.must_implement
		|| !result.type_inst.type_valued_expression
		|| result.type_inst.type_valued_expression.kind != .IDENT && result.type_inst.type_valued_expression.kind != .PROCEDURE_CALL
	) {
		return null;
	}


	arguments: [..]*Parser_Node;
	defer array_free(arguments);

	for header.arguments {
		array_add(*arguments, null);
	}

	for argument, index: call.arguments_unsorted {
		parameter_index := index;
		if argument.name {
			found := false;
			for parameter, candidate_index: header.arguments {
				if argument.name.name == parameter.name {
					parameter_index = candidate_index;
					found = true;
					break;
				}
			}

			if !found {
				return null;
			}
		}


		if arguments[parameter_index] || !argument.expression {
			return null;
		}


		arguments[parameter_index] = argument.expression;
	}


	return_type: *Parser_Ident;
	if result.type_inst.type_valued_expression.kind == .IDENT {
		return_type = result.type_inst.type_valued_expression.(*Parser_Ident);
	}

	returned_argument_type: *Parser_Node;
	for parameter, index: header.arguments {
		argument := arguments[index];
		if (!parameter.type_inst || parameter.type_inst.must_implement || parameter.expression || !argument
			|| !parameter.type_inst.type_valued_expression || parameter.type_inst.type_valued_expression.kind != .IDENT
		) {
			return null;
		}


		variable := parameter.type_inst.type_valued_expression.(*Parser_Ident);
		if variable.flags & .DEFINES_POLYMORPH_VARIABLE == 0 {
			return null;
		}


		for previous: 0..index-1 {
			previous_variable := header.arguments[previous].type_inst.type_valued_expression.(*Parser_Ident);
			if previous_variable.name == variable.name {
				return null;
			}
		}


		argument_type := infer_aggregate_expression_type(argument, visited, root_scope);
		if !infer_primitive_expression_type(argument, visited, root_scope) && !resolve_complete_aggregate_type(argument_type, root_scope).declaration {
			return null;
		}


		if return_type && variable.name == return_type.name {
			returned_argument_type = argument_type;
		}
	}


	if returned_argument_type {
		return returned_argument_type;
	}


	if !return_type {
		return call;
	}


	return ifx resolve_complete_aggregate_type(result.type_inst.type_valued_expression, root_scope).declaration
		then result.type_inst.type_valued_expression
		else null;
}

infer_aggregate_expression_type :: (expression: *Parser_Node, visited: *[..] *Parser_Declaration, root_scope: *Parser_Lexical_Scope) -> *Parser_Node {
	if !expression {
		return null;
	}


	if expression.kind == {
		case .LITERAL;
			literal := expression.(*Parser_Literal);
			if literal.value_type == .STRUCT && literal.struct_literal_info && literal.struct_literal_info.type_expression {
				return literal.struct_literal_info.type_expression.type_valued_expression;
			}

		case .BINARY_OPERATOR;
			member := expression.(*Parser_Binary_Operator);
			if member.operator_type != #char "." || !member.left || !member.right || member.right.kind != .IDENT {
				return null;
			}


			container_type := infer_aggregate_expression_type(member.left, visited, root_scope);
			container := resolve_complete_aggregate_type(container_type, root_scope);
			if !container.declaration {
				return null;
			}


			bindings: [..] Parser_Binding;
			defer array_free(bindings);

			structure := container.declaration.expression.(*Parser_Struct);
			if !structure.block || !collect_aggregate_bindings(structure.block.statements, *bindings, root_scope) {
				return null;
			}


			field: *Parser_Declaration;
			for bindings {
				if it.name == member.right.(*Parser_Ident).name {
					if field {
						return null;
					}


					field = it.declaration;
				}
			}


			if field && field.type_inst && field.type_inst.type_valued_expression {
				return substitute_aggregate_field_type(field.type_inst.type_valued_expression, container, root_scope, visited);
			}

		case .PROCEDURE_CALL;
			call := expression.(*Parser_Procedure_Call);
			if call.procedure_expression && call.procedure_expression.kind == .IDENT {
				header := resolve_called_procedure(call.procedure_expression.(*Parser_Ident).resolved_declaration, root_scope);
				if header && header.procedure_flags & .POLYMORPHIC != 0 {
					return instantiate_polymorphic_aggregate_call(call, header, visited, root_scope);
				}


				if header && match_aggregate_call_arguments(call, header, root_scope) != .MATCH {
					return null;
				}


				if !header {
					header = resolve_overloaded_aggregate_call(call, root_scope);
				}

				if header && header.procedure_flags & .POLYMORPHIC == 0 && header.returns.count == 1 {
					return infer_aggregate_type_expression(header.returns[0], visited, root_scope);
				}
			}

		case .DIRECTIVE_RUN;
			run := expression.(*Parser_Directive_Run);
			if run.procedure && run.procedure.procedure_flags & .POLYMORPHIC == 0 && run.procedure.returns.count == 1 {
				return infer_aggregate_type_expression(run.procedure.returns[0], visited, root_scope);
			}


			if run.flags & .HAS_IMPLICIT_RETURN_TYPES != 0 && run.flags & .ASSERTION == 0
				&& run.expression && run.expression.kind != .BLOCK {
				return infer_aggregate_expression_type(run.expression, visited, root_scope);
			}

		case .IDENT;
			value := expression.(*Parser_Ident).resolved_declaration;
			if value && binding_is_unique(root_scope, value) {
				return infer_aggregate_type_expression(value, visited, root_scope);
			}

		case .CAST;
			cast_node := expression.(*Parser_Cast);
			if cast_node.target_type {
				return cast_node.target_type.type_valued_expression;
			}

		case .IF;
			conditional := expression.(*Parser_If);
			if conditional.if_flags & .IS_IFX == 0 {
				return null;
			}


			if conditional.if_flags & .IS_STATIC != 0 {
				condition: bool;
				if !evaluate_literal_boolean(conditional.condition, *condition, root_scope) {
					return null;
				}


				branch := ifx condition then conditional.then_block else conditional.else_block;
				return ifx !branch || branch.statements.count != 1
					then null
					else infer_aggregate_expression_type(branch.statements[0], visited, root_scope);
			}


			if !conditional.then_block || !conditional.else_block
				|| conditional.then_block.statements.count != 1 || conditional.else_block.statements.count != 1 {
				return null;
			}


			then_type := infer_aggregate_expression_type(conditional.then_block.statements[0], visited, root_scope);
			else_type := infer_aggregate_expression_type(conditional.else_block.statements[0], visited, root_scope);
			if compare_aggregate_types(then_type, else_type, root_scope) == .MATCH {
				return then_type;
			}
	}


	return null;
}

infer_aggregate_type_expression :: (declaration: *Parser_Declaration, visited: *[..] *Parser_Declaration, root_scope: *Parser_Lexical_Scope) -> *Parser_Node {
	for visited.* {
		if it == declaration {
			return null;
		}
	}


	array_add(visited, declaration);
	defer visited.count -= 1;

	return ifx declaration.type_inst
		then declaration.type_inst.type_valued_expression
		else infer_aggregate_expression_type(declaration.expression, visited, root_scope);
}

evaluate_constant_boolean :: (expression: *Parser_Node, result: *bool, visited: *[..]*Parser_Declaration, root_scope: *Parser_Lexical_Scope) -> bool {
	if !expression {
		return false;
	}


	if expression.kind == {
		case .LITERAL;
			literal := expression.(*Parser_Literal);
			if literal.value_type != .BOOLEAN {
				return false;
			}


			result.* = literal._u64 != 0;
			return true;

		case .UNARY_OPERATOR;
			unary := expression.(*Parser_Unary_Operator);
			if unary.operator_type != #char "!" || !evaluate_constant_boolean(unary.subexpression, result, visited, root_scope) {
				return false;
			}


			result.* = !result.*;
			return true;

		case .BINARY_OPERATOR;
			binary := expression.(*Parser_Binary_Operator);
			if binary.operator_type != .LOGICAL_AND && binary.operator_type != .LOGICAL_OR {
				return false;
			}


			left: bool;
			right: bool;
			if !evaluate_constant_boolean(binary.left, *left, visited, root_scope) || !evaluate_constant_boolean(binary.right, *right, visited, root_scope) {
				return false;
			}


			result.* = ifx binary.operator_type == .LOGICAL_AND
				then left && right
				else left || right;

			return true;

		case .IDENT;
			declaration := expression.(*Parser_Ident).resolved_declaration;
			if !declaration || declaration.flags & .IS_CONSTANT == 0 || !binding_is_unique(root_scope, declaration) {
				return false;
			}


			for visited.* {
				if it == declaration {
					return false;
				}
			}


			array_add(visited, declaration);
			defer visited.count -= 1;

			return evaluate_constant_boolean(declaration.expression, result, visited, root_scope);
	}


	return false;
}

evaluate_literal_boolean :: (expression: *Parser_Node, result: *bool, root_scope: *Parser_Lexical_Scope) -> bool {
	visited: [..]*Parser_Declaration;
	defer array_free(visited);

	return evaluate_constant_boolean(expression, result, *visited, root_scope);
}

collect_aggregate_bindings :: (statements: []*Parser_Node, bindings: *[..] Parser_Binding, root_scope: *Parser_Lexical_Scope) -> bool {
	for statement: statements {
		if statement.kind == .DECLARATION {
			field := statement.(*Parser_Declaration);
			array_add(bindings, .{name = field.name, declaration = field});
		} else if statement.kind == .IF {
			conditional := statement.(*Parser_If);
			condition: bool;
			if conditional.if_flags & .IS_STATIC == 0 || !evaluate_literal_boolean(conditional.condition, *condition, root_scope) {
				return false;
			}


			branch := ifx condition
				then conditional.then_block
				else conditional.else_block;
			if branch && !collect_aggregate_bindings(branch.statements, bindings, root_scope) {
				return false;
			}
		} else if statement.kind == .DIRECTIVE_INSERT || statement.kind == .DIRECTIVE_RUN {
			return false;
		}
	}


	return true;
}

map_aggregate_names :: (scope: *Parser_Lexical_Scope, imports: *Parser_File_Imports, using_node: *Parser_Using, map_names: (using_node: *Parser_Using, names: [] string) -> bool) -> bool {
	if !using_node.expression || using_node.expression.kind != .DECLARATION {
		return false;
	}


	visited: [..] *Parser_Declaration;
	defer array_free(visited);

	root_scope := scope;
	while root_scope.parent {
		root_scope = root_scope.parent;
	}

	type_expression := infer_aggregate_type_expression(using_node.expression.(*Parser_Declaration), *visited, root_scope);

	aggregate_type := resolve_complete_aggregate_type(type_expression, root_scope);
	if !aggregate_type.declaration {
		return false;
	}


	structure := aggregate_type.declaration.expression.(*Parser_Struct);
	if !structure.block {
		return false;
	}


	bindings: [..] Parser_Binding;
	if !collect_aggregate_bindings(structure.block.statements, *bindings, root_scope) {
		array_free(bindings);
		return false;
	}


	success := map_using_names(imports, using_node, bindings, map_names);
	array_free(bindings);
	return success;
}

map_using_names :: (imports: *Parser_File_Imports, using_node: *Parser_Using, bindings: [] Parser_Binding, map_names: (using_node: *Parser_Using, names: [] string) -> bool) -> bool {
	names: [..] string;
	for bindings {
		array_add(*names, it.name);
	}

	success := map_names(using_node, names);
	if success {
		for binding, index: bindings {
			mapped := names[index];
			if mapped {
				for existing: imports.mapped_names {
					if existing.using_node == using_node && existing.exported_name == mapped {
						array_add(
							*imports.map_collisions,
							.{
								using_node = using_node,
								exported_name = existing.exported_name,
								first = existing.declaration,
								second = binding.declaration,
							}
						);
						break;
					}
				}
			}

			array_add(
				*imports.mapped_names,
				.{
					using_node = using_node,
					source_name = copy_string(binding.name),
					exported_name = ifx mapped
						then copy_string(mapped)
						else "",
					declaration = binding.declaration,
				}
			);
		}
	}

	array_free(names);
	return success;
}

lookup_mapped_name :: (imports: *Parser_File_Imports, using_node: *Parser_Using, name: string) -> *Parser_Declaration {
	for imports.map_collisions {
		if (it.using_node == using_node || it.other_using_node == using_node) && it.exported_name == name {
			return null;
		}
	}


	for imports.mapped_names {
		if it.using_node == using_node && it.exported_name && it.exported_name == name {
			return it.declaration;
		}
	}


	return null;
}

lookup_using_import_binding :: (scope: *Parser_Lexical_Scope, imports: *Parser_File_Imports, module: *Parser_Imported_Module, name: string) -> *Parser_Declaration {
	lookup := scope;
	while lookup {
		for using_node: lookup.usings {
			if !using_targets_module(using_node, module) {
				continue;
			}


			if using_node.filter_type == .MAP {
				declaration := lookup_mapped_name(imports, using_node, name);
				if declaration {
					return declaration;
				}
			} else if import_name_visible(using_node, name) {
				return lookup_import_binding(module, name);
			}
		}


		lookup = lookup.parent;
	}


	return null;
}

load_module_files :: (module: *Parser_Imported_Module, parsed: *Parsed_Source, depth: s64 = 0) {
	if depth >= 64 {
		module.load_limit_reached = true;
		return;
	}


	for parsed.root.(*Parser_Block).statements {
		if it.kind != .DIRECTIVE_LOAD {
			continue;
		}


		load := it.(*Parser_Directive_Load);
		filename := join(path_strip_filename(parsed.fully_pathed_filename), load.short_name);
		if filename == module.filename {
			free(filename);
			continue;
		}


		seen := false;
		for module.loaded_files {
			if it.filename == filename {
				seen = true;
				break;
			}
		}


		if seen {
			free(filename);
			continue;
		}


		source, success := read_entire_file(filename, log_errors=false);
		if !success {
			free(filename);
			array_add(*module.unresolved_loads, load);
			continue;
		}


		file := Parser_Imported_File.{filename = filename, source = source, parsed = parse_file(source, filename)};
		array_add(*module.loaded_files, file);
		load_module_files(module, *file.parsed, depth + 1);
	}
}

resolve_bare_import_references :: (scope: *Parser_Lexical_Scope, imports: *Parser_File_Imports) {
	for reference: scope.references {
		if reference.resolved_declaration || reference.flags & .IS_RHS_OF_DOT_DEREFERENCE != 0 {
			continue;
		}


		bind_import_reference(imports, reference, lookup_loaded_binding(imports.loaded_files, reference.name));
		if reference.resolved_declaration {
			continue;
		}


		lookup := scope;
		while lookup && !reference.resolved_declaration {
			for using_node: lookup.usings {
				if using_node.filter_type != .MAP || !using_node.expression || using_node.expression.kind != .DECLARATION {
					continue;
				}


				bind_import_reference(imports, reference, lookup_mapped_name(imports, using_node, reference.name));
			}
			lookup = lookup.parent;
		}

		if reference.resolved_declaration {
			continue;
		}


		for module: imports.modules {
			declaration := ifx module.declaration
				then lookup_using_import_binding(scope, imports, *module, reference.name)
				else lookup_import_binding(*module, reference.name);

			bind_import_reference(imports, reference, declaration);
			if reference.resolved_declaration {
				break;
			}
		}
	}

	for scope.children {
		resolve_bare_import_references(it, imports);
	}
}

release_file_imports :: (imports: *Parser_File_Imports) {
	for imports.bindings {
		if it.reference.resolved_declaration == it.declaration {
			it.reference.resolved_declaration = null;
		}
	}

	array_free(imports.bindings);
	for imports.mapped_names {
		free(it.source_name);
		if it.exported_name {
			free(it.exported_name);
		}
	}

	array_free(imports.mapped_names);
	array_free(imports.map_collisions);

	for imports.loaded_files {
		release_parser_tree(*it.parsed);
		release_parser_names(*it.parsed);
		free(it.source);
		free(it.filename);
	}

	array_free(imports.loaded_files);
	array_free(imports.unresolved_loads);
	array_free(imports.unsupported_using_filters);

	for imports.modules {
		for it.loaded_files {
			release_parser_tree(*it.parsed);
			release_parser_names(*it.parsed);
			free(it.source);
			free(it.filename);
		}

		array_free(it.loaded_files);
		array_free(it.unresolved_loads);
		release_parser_tree(*it.parsed);
		release_parser_names(*it.parsed);
		free(it.source);
		free(it.filename);
	}

	array_free(imports.modules);
	array_free(imports.unresolved_imports);
}
