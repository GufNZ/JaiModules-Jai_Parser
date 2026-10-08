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

THREE_ARGUMENT_RANK_SOURCE :: #string JAI
make :: (%) {
}
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
	extra_declarations: string = "";
	parameters: string = "";
	setup: string = "";
	receiver: string;
}

PAIR_MEMBER_CASES :: Pair_Member_Case.[
	.{
		declaration_name = "fixture_multi_parameter",
		setup = "pair: Pair(Other, Child);",
		receiver = "pair.Right"
	},
	.{
		declaration_name = "fixture_named_parameter",
		setup = "pair: Pair(Second=Child, First=Other);",
		receiver = "pair.Right"
	},
	.{
		declaration_name = "fixture_aliased_parameter",
		extra_declarations = "Alias :: Pair;\nAliasAgain :: Alias;",
		setup = "pair: AliasAgain(Second=Child, First=Other);",
		receiver = "pair.Right"
	},
	.{
		declaration_name = "fixture_aliased_instance",
		extra_declarations = "Instance :: Pair(Second=Child, First=Other);\nAlias :: Instance;",
		setup = "pair: Alias;",
		receiver = "pair.Right"
	},
	.{
		declaration_name = "fixture_equivalent_instance",
		extra_declarations = "Instance :: Pair(Second=Child, First=Other);",
		parameters = "choose: bool",
		receiver = "(ifx choose then Instance.{Right=Child.{Clear=1}} else Pair(Other, Child).{Right=Child.{Clear=2}}).Right"
	},
	.{
		declaration_name = "fixture_nested_parameter",
		setup = "pair: Pair(Pair(Child, Other), Other);",
		receiver = "pair.Left.Left"
	},
	.{
		declaration_name = "fixture_nested_alias",
		extra_declarations = "Inner :: Pair(Child, Other);",
		setup = "pair: Pair(Inner, Other);",
		receiver = "pair.Left.Left"
	},
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

Unsigned_Boundary_Case :: struct {
	parameter_type: string;
	upper: string;
	above: string;
	above_is_representable: bool;
}

UNSIGNED_BOUNDARY_CASES :: Unsigned_Boundary_Case.[
	.{"u8", "255", "256", true},
	.{"u16", "65535", "65536", true},
	.{"u32", "4294967295", "4294967296", true},
	.{"u64", "18446744073709551615", "18446744073709551616", false},
];

UNSIGNED_NEGATIVE_VALUES :: string.["-1", "-9223372036854775808"];

Float_Literal_Case :: struct {
	value: string;
	preferred_type: string;
	float32_compatible: bool;
}

FLOAT_LITERAL_CASES :: Float_Literal_Case.[
	.{"0.0", "float32", true},
	.{"1.5", "float32", true},
	.{"-1.5", "float32", true},
	.{"1.2345678", "float64", true},
	.{"1.23456789", "float64", false},
	.{"1.0e40", "float64", false},
];

INTEGER_FLOAT32_VALUES :: string.[
	"0", "-0", "1", "-1",
	"16777215", "-16777215", "16777216", "-16777216",
	"16777217", "-16777217", "16777218", "-16777218",
	"9223372036854775807", "-9223372036854775808", "18446744073709551615",
];

Numeric_Rank_Case :: struct {
	first_parameters: string;
	second_parameters: string;
	arguments: string;
	selected_index: s64;
	third_parameters: string = "";
}

NUMERIC_RANK_CASES :: Numeric_Rank_Case.[
	.{first_parameters = "first: float64, second: float64",			second_parameters = "first: float32, second: float64",		arguments = "1, 1.5",	selected_index = 1},
	.{first_parameters = "first: float64, second: s64",				second_parameters = "first: float32, second: s64",			arguments = "1, 1",		selected_index = 1},
	.{first_parameters = "first: float32, second: float64",			second_parameters = "first: float64, second: float32",		arguments = "1, 1",		selected_index = -1},
	.{first_parameters = "value: float64, enabled: bool = true",	second_parameters = "value: float32, enabled: bool = true",	arguments = "value=1",	selected_index = 1},
	.{first_parameters = "first: s8, second: u8",					second_parameters = "first: u16, second: s16",				arguments = "1, 1",		selected_index = 0},
	.{first_parameters = "first: s8, second: u16",					second_parameters = "first: u16, second: s8",				arguments = "1, 1",		selected_index = -1},
	.{first_parameters = "value: s8, enabled: bool = true",			second_parameters = "value: u16, enabled: bool = true",		arguments = "value=1",	selected_index = 0},
];

THREE_CANDIDATE_RANK_CASES :: Numeric_Rank_Case.[
	.{"value: u8",					"value: u16",				"1",	0,	"value: u32"},
	.{"value: u8",					"value: u16",				"256",	1,	"value: u32"},
	.{"value: s8",					"value: u8",				"1",	2,	"value: s64"},
	.{"first: u8, second: u16",		"first: u16, second: u8",	"1, 1",	2,	"first: u8, second: u8"},
	.{"first: u8, second: u16",		"first: u16, second: u8",	"1, 1",	-1,	"first: u32, second: u32"},
	.{"first: u16, second: u32",	"first: u32, second: u8",	"1, 1",	-1,	"first: u8, second: u32"},
	.{"value: s8",					"value: u8",				"1",	-1,	"value: u16"},
];

Multi_Candidate_Rank_Case :: struct {
	parameters: []string;
	arguments: string;
	selected_index: s64;
}

MULTI_CANDIDATE_RANK_CASES :: Multi_Candidate_Rank_Case.[
	.{parameters = string.["value: u8", "value: u16", "value: u32", "value: u64"],																				arguments = "1",			selected_index = 0},
	.{parameters = string.["value: u8", "value: u16", "value: u32", "value: u64"],																				arguments = "256",			selected_index = 1},
	.{parameters = string.["value: u8", "value: u16", "value: u32", "value: u64"],																				arguments = "4294967296",	selected_index = 3},
	.{parameters = string.["value: u8", "value: u16", "value: u32", "value: u64"],																				arguments = "-1",			selected_index = -1},
	.{parameters = string.["value: s8", "value: u8", "value: s16", "value: s64"],																				arguments = "1",			selected_index = 3},
	.{parameters = string.["first: u8, second: u32", "first: u32, second: u8", "first: u16, second: u16", "first: u8, second: u8"],								arguments = "1, 1",			selected_index = 3},
	.{parameters = string.["first: u8, second: u16", "first: u16, second: u8", "first: u32, second: u32", "first: u64, second: u64"],							arguments = "1, 1",			selected_index = -1},
	.{parameters = string.["first: u16, second: u32", "first: u32, second: u8", "first: u8, second: u32", "first: u64, second: u64"],							arguments = "1, 1",			selected_index = -1},
	.{parameters = string.["first: s8, second: u16", "first: u8, second: u16", "first: u16, second: s8", "first: u16, second: u8", "first: s8, second: u8"],	arguments = "1, 1",			selected_index = 4},
	.{parameters = string.["first: s8, second: u16", "first: u8, second: u16", "first: u16, second: s8", "first: u16, second: u8", "first: u32, second: u32"],	arguments = "1, 1",			selected_index = -1},
];

make_multi_candidate_rank_source :: (parameters: []string, arguments: string, selected_index: s64 = -1) -> string {
	declarations := "";
	for parameter, index: parameters {
		if selected_index >= 0 {
			result := ifx index == selected_index
				then "Child"
				else "Other";
			declarations = tprint("%make :: (%) -> % { return .{1}; }\n", declarations, parameter, result);
		} else {
			declarations = tprint("%make :: (%) {}\n", declarations, parameter);
		}
	}

	if selected_index >= 0 {
		return tprint("Child :: struct { Clear: s64; }\nOther :: struct { PushMatrix: s64; }\n%fixture_multi_candidate_rank :: () -> s64 { return make(%).Clear; }", declarations, arguments);
	}


	return tprint("%main :: () { make(%); }", declarations, arguments);
}

visit_multi_candidate_rank_permutations :: (parameters: []string, arguments: string, selected_index: s64, depth: s64, check: (parameters: []string, arguments: string, selected_index: s64)) -> s64 {
	if depth == parameters.count {
		check(parameters, arguments, selected_index);
		return 1;
	}


	checked := 0;
	for swap_index: depth..parameters.count-1 {
		next_selected := selected_index;
		if selected_index == depth {
			next_selected = swap_index;
		} else if selected_index == swap_index {
			next_selected = depth;
		}

		temporary := parameters[depth];
		parameters[depth] = parameters[swap_index];
		parameters[swap_index] = temporary;
		checked += visit_multi_candidate_rank_permutations(parameters, arguments, next_selected, depth + 1, check);
		temporary = parameters[depth];
		parameters[depth] = parameters[swap_index];
		parameters[swap_index] = temporary;
	}

	return checked;
}

check_multi_candidate_rank_cases :: (check: (parameters: []string, arguments: string, selected_index: s64)) {
	for fixture: MULTI_CANDIDATE_RANK_CASES {
		parameters := NewArray(fixture.parameters.count, string);
		defer free(parameters.data);

		for parameter, index: fixture.parameters {
			parameters[index] = parameter;
		}

		checked := visit_multi_candidate_rank_permutations(parameters, fixture.arguments, fixture.selected_index, 0, check);
		assert(checked == ifx parameters.count == 4 then 24 else 120);
	}
}

make_numeric_rank_case :: (first: string, second: string, arguments: string, selected_index: s64) -> Numeric_Rank_Case {
	return .{first_parameters = first, second_parameters = second, arguments = arguments, selected_index = selected_index};
}

make_numeric_rank_cases :: () -> [..] Numeric_Rank_Case {
	cases: [..] Numeric_Rank_Case;
	for fixture: NUMERIC_RANK_CASES {
		array_add(*cases, fixture);
	}

	for fixture: THREE_CANDIDATE_RANK_CASES {
		parameters := string.[fixture.first_parameters, fixture.second_parameters, fixture.third_parameters];
		for rotation: 0..2 {
			selected_index := ifx fixture.selected_index < 0
				then -1
				else (fixture.selected_index + 3 - rotation) % 3;
			array_add(*cases, .{
				parameters[rotation], parameters[(rotation + 1) % 3],
				fixture.arguments, selected_index, parameters[(rotation + 2) % 3]
			});
		}
	}

	for narrow, narrow_index: UNSIGNED_BOUNDARY_CASES {
		for wide, wide_index: UNSIGNED_BOUNDARY_CASES {
			if wide_index <= narrow_index {
				continue;
			}


			first := tprint("value: %", narrow.parameter_type);
			second := tprint("value: %", wide.parameter_type);
			for value, index: string.["0", "-0", "1", narrow.upper, narrow.above, wide.upper] {
				array_add(*cases, make_numeric_rank_case(first, second, value, ifx index < 4 then 0 else 1));
			}

			for value: UNSIGNED_NEGATIVE_VALUES {
				array_add(*cases, make_numeric_rank_case(first, second, value, -1));
			}

			if wide.above_is_representable {
				array_add(*cases, make_numeric_rank_case(first, second, wide.above, -1));
			}
		}
	}

	for narrow, narrow_index: SIGNED_BOUNDARY_CASES {
		for wide, wide_index: SIGNED_BOUNDARY_CASES {
			if wide_index <= narrow_index || wide.parameter_type == "s64" {
				continue;
			}


			first := tprint("value: %", narrow.parameter_type);
			second := tprint("value: %", wide.parameter_type);
			for value: string.["0", "-0", "1", "-1", narrow.lower, narrow.upper] {
				array_add(*cases, make_numeric_rank_case(first, second, value, 0));
			}

			for value: string.[narrow.below, narrow.above, wide.lower, wide.upper] {
				array_add(*cases, make_numeric_rank_case(first, second, value, 1));
			}

			for value: string.[wide.below, wide.above] {
				array_add(*cases, make_numeric_rank_case(first, second, value, -1));
			}
		}
	}

	for signed, index: SIGNED_BOUNDARY_CASES {
		if signed.parameter_type == "s64" {
			continue;
		}


		unsigned := UNSIGNED_BOUNDARY_CASES[index];
		first := tprint("value: %", signed.parameter_type);
		second := tprint("value: %", unsigned.parameter_type);
		for value: string.["0", "-0", "1", signed.upper] {
			array_add(*cases, make_numeric_rank_case(first, second, value, -1));
		}

		for value: string.["-1", signed.lower] {
			array_add(*cases, make_numeric_rank_case(first, second, value, 0));
		}

		for value: string.[signed.above, unsigned.upper] {
			array_add(*cases, make_numeric_rank_case(first, second, value, 1));
		}

		for value: string.[signed.below, unsigned.above] {
			array_add(*cases, make_numeric_rank_case(first, second, value, -1));
		}
	}

	for signed, signed_index: SIGNED_BOUNDARY_CASES {
		if signed.parameter_type == "s64" {
			continue;
		}


		for unsigned, unsigned_index: UNSIGNED_BOUNDARY_CASES {
			if signed_index == unsigned_index {
				continue;
			}


			first := tprint("value: %", signed.parameter_type);
			second := tprint("value: %", unsigned.parameter_type);
			signed_is_narrower := signed_index < unsigned_index;
			preferred := ifx signed_is_narrower
				then 0
				else 1;
			overlap_upper := ifx signed_is_narrower
				then signed.upper
				else unsigned.upper;

			for value: string.["0", "-0", "1", overlap_upper] {
				array_add(*cases, make_numeric_rank_case(first, second, value, preferred));
			}

			for value: string.["-1", signed.lower] {
				array_add(*cases, make_numeric_rank_case(first, second, value, 0));
			}

			if signed_is_narrower {
				for value: string.[signed.above, unsigned.upper] {
				array_add(*cases, make_numeric_rank_case(first, second, value, 1));
				}

				array_add(*cases, make_numeric_rank_case(first, second, signed.below, -1));
				if unsigned.above_is_representable {
					array_add(*cases, make_numeric_rank_case(first, second, unsigned.above, -1));
				}
			} else {
				for value: string.[unsigned.above, signed.upper] {
					array_add(*cases, make_numeric_rank_case(first, second, value, 0));
				}

				for value: string.[signed.below, signed.above] {
					array_add(*cases, make_numeric_rank_case(first, second, value, -1));
				}
			}
		}
	}

	signed64 := SIGNED_BOUNDARY_CASES[SIGNED_BOUNDARY_CASES.count - 1];
	unsigned64 := UNSIGNED_BOUNDARY_CASES[UNSIGNED_BOUNDARY_CASES.count - 1];
	for unsigned: UNSIGNED_BOUNDARY_CASES {
		first := tprint("value: %", signed64.parameter_type);
		second := tprint("value: %", unsigned.parameter_type);
		for value: string.[
			"0", "-0", "1", "-1",
			signed64.lower, signed64.upper, signed64.above,
			unsigned.upper, unsigned64.upper
		] {
			array_add(*cases, make_numeric_rank_case(first, second, value, 0));
		}

		if unsigned.above_is_representable {
			array_add(*cases, make_numeric_rank_case(first, second, unsigned.above, 0));
		}
	}

	return cases;
}

make_long_identifier_source :: (identifier_length: s64, suffix: string) -> string {
	source := alloc_string(identifier_length + suffix.count);
	for index: 0..identifier_length-1 {
		source.data[index] = #char "a";
	}

	memcpy(source.data + identifier_length, suffix.data, suffix.count);
	return source;
}
