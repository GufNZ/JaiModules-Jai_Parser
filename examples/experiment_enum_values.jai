// E14 probe: unset/specified enum and enum_flags member values, as reported by Type_Info_Enum.
#import "Basic";

INCLUDE_B :: true;
EXCLUDE_B :: false;

E_Unset :: enum {
	A;
	B;
	C;
}

E_Mixed :: enum {
	A;
	B :: 10;
	C;
	D :: 5;
	E;
}

E_Repeated :: enum {
	A :: 3;
	B :: 3;
	C;
}

E_Equal_Generated :: enum {
	A;
	B;
	C :: 1;
	D;
}

E_Generated_Hits_Specified :: enum {
	A :: 2;
	B :: 0;
	C;
	D;
}

E_Negative :: enum s32 {
	A :: -5;
	B;
	C :: -1;
	D;
}

E_Reference :: enum {
	A :: 7;
	B :: A;
	C;
}

E_Expression :: enum {
	A :: 1 << 3;
	B;
}

E_Conditional_Included :: enum {
	A;
	#if INCLUDE_B {
		B;
	}
	C;
}

E_Conditional_Excluded :: enum {
	A;
	#if EXCLUDE_B {
		B;
	}
	C;
}

E_U8_Edge :: enum u8 {
	A :: 254;
	B;
}

E_Specified :: enum u8 #specified {
	A :: 9;
	B :: 1;
	C :: 1;
}

F_Unset :: enum_flags {
	A;
	B;
	C;
}

F_Mixed :: enum_flags {
	A;
	B :: 0x10;
	C;
	D :: 0x2;
	E;
}

F_Repeated :: enum_flags {
	A :: 0x4;
	B :: 0x4;
	C;
}

F_Equal_Generated :: enum_flags {
	A;
	B;
	C :: 0x2;
	D;
}

F_Zero :: enum_flags {
	NONE :: 0;
	A :: 0x1;
	B;
}

F_Combination :: enum_flags {
	A;
	B;
	C;
	AB :: A | B;
}

F_Conditional_Excluded :: enum_flags {
	A;
	#if EXCLUDE_B {
		B;
	}
	C;
}

dump :: ($T: Type) {
	info := type_info(T);
	print("%: flags=%", info.name, info.enum_type_flags);
	for info.names {
		print(" %=%", it, info.values[it_index]);
	}

	print("\n");
}

main :: () {
	dump(E_Unset);
	dump(E_Mixed);
	dump(E_Repeated);
	dump(E_Equal_Generated);
	dump(E_Generated_Hits_Specified);
	dump(E_Negative);
	dump(E_Reference);
	dump(E_Expression);
	dump(E_Conditional_Included);
	dump(E_Conditional_Excluded);
	dump(E_U8_Edge);
	dump(E_Specified);
	dump(F_Unset);
	dump(F_Mixed);
	dump(F_Repeated);
	dump(F_Equal_Generated);
	dump(F_Zero);
	dump(F_Combination);
	dump(F_Conditional_Excluded);
}
