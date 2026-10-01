#import "Basic";
#import "Compiler";
#import "String";

Parser :: #import "Jai_Parser";
seen: [..] string;

main :: () {
	for Type.[
		Code_Node, Code_Argument, Code_Array_Literal_Info, Code_Comma_Separated_Argument, Code_Struct_Literal_Info,
		Code_Extract, Code_Make_Varargs, Code_Resolved_Overload
	] {
		visit(it.(*Type_Info));
	}
	for Parser.TYPES {
		visit(it.(*Type_Info));
	}
	values := type_of(Code_Literal.values).(*Type_Info_Struct);
	print("Code_Literal.values:\n");
	for values.members {
		if it.offset_in_bytes >= 0 {
			print("  %: %\n", it.name, type_to_string(it.type));
		}
	}
	for values.members {
		if it.offset_in_bytes >= 0 {
			visit(it.type);
		}
	}
}

visit :: (record_type: *Type_Info) {
	if record_type.type == .POINTER {
		visit(record_type.(*Type_Info_Pointer).pointer_to);
		return;
	}
	if record_type.type == .ARRAY {
		visit(record_type.(*Type_Info_Array).element_type);
		return;
	}
	if record_type.type != .STRUCT {
		return;
	}

	info := record_type.(*Type_Info_Struct);
	if !starts_with(info.name, "Code_") {
		return;
	}
	for seen {
		if it == info.name {
			return;
		}
	}
	array_add(*seen, info.name);
	print("%:\n", info.name);
	for info.members {
		if it.offset_in_bytes >= 0 {
			print("  %: %\n", it.name, type_to_string(it.type));
			if it.name == "" {
				for it.type.(*Type_Info_Struct).members {
					if it.offset_in_bytes >= 0 {
						print("    %: %\n", it.name, type_to_string(it.type));
					}
				}
			}
		}
	}
	for info.members {
		if it.offset_in_bytes >= 0 {
			visit(it.type);
		}
	}
}
