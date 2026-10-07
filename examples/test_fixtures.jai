UNARY_OVERLOAD_SOURCE :: #string JAI
make :: (value: %) {
}
make :: (value: %) {
}
main :: () {
	make(%);
}
JAI;

MULTI_ARGUMENT_RANK_SOURCE :: #string JAI
make :: (%) {
}
make :: (%) {
}
main :: () {
	make(%);
}
JAI;

CONTAINER_MEMBER_SOURCE :: #string JAI
Child :: struct {
	Clear: s64;
}
Container :: struct {
	Nested: Child;
}
%
% {
	%
}
JAI;

CONTAINER_MAKER_SOURCE :: #string JAI
make :: (%) -> Container {
	return .{
		Nested = Child.{
			Clear = 1
		}
	};
}
JAI;

PAIR_MEMBER_SOURCE :: #string JAI
Child :: struct {
	Clear: s64;
}
Other :: struct {
	PushMatrix: s64;
}
Pair :: struct (First: Type, Second: Type) {
	Left: First;
	Right: Second;
}
%
% {
	%
}
JAI;

Pair_Member_Case :: struct {
	declaration_name: string;
	extra_declarations: string;
	parameters: string;
	setup: string;
	receiver: string;
}

PAIR_MEMBER_CASES :: Pair_Member_Case.[
	.{"fixture_multi_parameter", "", "", "pair: Pair(Other, Child);", "pair.Right"},
	.{"fixture_named_parameter", "", "", "pair: Pair(Second=Child, First=Other);", "pair.Right"},
	.{"fixture_aliased_parameter", "Alias :: Pair;\nAliasAgain :: Alias;", "", "pair: AliasAgain(Second=Child, First=Other);", "pair.Right"},
	.{"fixture_aliased_instance", "Instance :: Pair(Second=Child, First=Other);\nAlias :: Instance;", "", "pair: Alias;", "pair.Right"},
	.{"fixture_equivalent_instance", "Instance :: Pair(Second=Child, First=Other);", "choose: bool", "", "(ifx choose then Instance.{Right=Child.{Clear=1}} else Pair(Other, Child).{Right=Child.{Clear=2}}).Right"},
	.{"fixture_nested_parameter", "", "", "pair: Pair(Pair(Child, Other), Other);", "pair.Left.Left"},
	.{"fixture_nested_alias", "Inner :: Pair(Child, Other);", "", "pair: Pair(Inner, Other);", "pair.Left.Left"},
];

Signed_Boundary_Case :: struct {
	parameter_type: string;
	lower: string;
	upper: string;
	below: string;
	above: string;
	above_matches: bool;
	below_is_negatable: bool;
}

SIGNED_BOUNDARY_CASES :: Signed_Boundary_Case.[
	.{"s8", "-128", "127", "-129", "128", false, true},
	.{"s16", "-32768", "32767", "-32769", "32768", false, true},
	.{"s32", "-2147483648", "2147483647", "-2147483649", "2147483648", false, true},
	.{"s64", "-9223372036854775808", "9223372036854775807", "-9223372036854775809", "9223372036854775808", true, false},
];

Rejected_Integer_Case :: struct {
	parameter_type: string;
	value: string;
}

REJECTED_INTEGER_CASES :: Rejected_Integer_Case.[
	.{"u8", "256"},
	.{"u16", "65536"},
];

make_long_identifier_source :: (identifier_length: s64, suffix: string) -> string {
	source := alloc_string(identifier_length + suffix.count);
	for index: 0..identifier_length-1 {
		source.data[index] = #char "a";
	}

	memcpy(source.data + identifier_length, suffix.data, suffix.count);
	return source;
}
