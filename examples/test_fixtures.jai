Typed_Numeric_Case :: struct {
	parameter_type: string;
	setup: string = "";
	globals: string = "";
	argument: string = "value";
	compiler_accepts: bool;
	parser_matches: bool;
	rival_type: string = "string";
}

TYPED_INTEGER_CASES :: Typed_Numeric_Case.[
	.{parameter_type="u16",	setup="value: u8 = 255;",										compiler_accepts=true,	parser_matches=true},
	.{parameter_type="s16",	setup="value: s8 = -128;",										compiler_accepts=true,	parser_matches=true},
	.{parameter_type="s16",	setup="value: u8 = 255;",										compiler_accepts=true,	parser_matches=true},
	.{parameter_type="u16",	setup="value: s8 = 1;",											compiler_accepts=false,	parser_matches=false},
	.{parameter_type="u8",	setup="value: u16 = 1;",										compiler_accepts=false,	parser_matches=false},
	.{parameter_type="s8",	setup="value: s16 = 1;",										compiler_accepts=false,	parser_matches=false},
	.{parameter_type="s8",	setup="value: u8 = 1;",											compiler_accepts=false,	parser_matches=false},
	.{parameter_type="u8",	setup="value: s8 = 1;",											compiler_accepts=false,	parser_matches=false},
	.{parameter_type="u8",													argument="1",	compiler_accepts=true,	parser_matches=true},
	.{parameter_type="u8",	setup="value :: 1;",											compiler_accepts=true,	parser_matches=true},
	.{parameter_type="u8",	setup="value: u16 : 1;",										compiler_accepts=false,	parser_matches=false},
	.{parameter_type="u16",	setup="value: u8 : 255;",										compiler_accepts=true,	parser_matches=true},
	.{parameter_type="u8",	setup="value: u8 = 255;",										compiler_accepts=true,	parser_matches=true,	rival_type="u16"},
	.{parameter_type="u8",	setup="value: u8 = 255;",										compiler_accepts=true,	parser_matches=true,	rival_type="s16"},
	.{parameter_type="s8",	setup="value: s8 = -128;",										compiler_accepts=true,	parser_matches=true,	rival_type="s16"},
	.{parameter_type="u16",	setup="value: u8 = 255;",										compiler_accepts=true,	parser_matches=true,	rival_type="u32"},
	.{parameter_type="s16",	setup="value: s8 = -128;",										compiler_accepts=true,	parser_matches=true,	rival_type="s32"},
	.{parameter_type="u16",	setup="value: u8 = 255;",										compiler_accepts=true,	parser_matches=true,	rival_type="s32"},
	.{parameter_type="u16",	setup="value: u8 = 255;",										compiler_accepts=false,	parser_matches=false,	rival_type="s16"},
	.{parameter_type="u8",	setup="value :: 255;",											compiler_accepts=true,	parser_matches=true},
	.{parameter_type="u8",	setup="value :: 256;",											compiler_accepts=false,	parser_matches=false},
	.{parameter_type="s8",	setup="value :: -128;",											compiler_accepts=true,	parser_matches=true},
	.{parameter_type="s8",	setup="value :: -129;",											compiler_accepts=false,	parser_matches=false},
	.{parameter_type="u8",	setup="original :: 255; middle :: original; value :: middle;",	compiler_accepts=true,	parser_matches=true},
	.{parameter_type="u8",	setup="original :: 256; value :: original;",					compiler_accepts=false,	parser_matches=false},
	.{parameter_type="u8",	setup="original: u16 : 1; value :: original;",					compiler_accepts=false,	parser_matches=false},
	.{parameter_type="u16",	setup="original: u8 : 255; value :: original;",					compiler_accepts=true,	parser_matches=true},
	.{parameter_type="u8",	setup="value := 1; value = 256;",								compiler_accepts=false,	parser_matches=false},
	.{parameter_type="u8",	setup="original := 1; value := original;",						compiler_accepts=false,	parser_matches=false},
	.{parameter_type="u8",	setup="value :: -1;",											compiler_accepts=false,	parser_matches=false},
	.{parameter_type="u64",	setup="value :: 18446744073709551615;",							compiler_accepts=true,	parser_matches=true},
	.{parameter_type="u8",	setup="value :: 1;",											compiler_accepts=true,	parser_matches=true,	rival_type="u16"},
	.{parameter_type="s64",	setup="value :: 1;",											compiler_accepts=true,	parser_matches=true,	rival_type="u8"},
	.{parameter_type="s8",	setup="value :: 1;",											compiler_accepts=false,	parser_matches=false,	rival_type="u8"},
	.{parameter_type="u8",	setup="value :: 1 + 2;",										compiler_accepts=true,	parser_matches=false},
	.{parameter_type="u8",	setup="value :: original; original :: 255;",					compiler_accepts=false,	parser_matches=false},
	.{parameter_type="u8",	setup="original :: value; value :: original;",					compiler_accepts=false,	parser_matches=false},
	.{parameter_type="u8",	setup="value :: Missing;",										compiler_accepts=false,	parser_matches=false},
	.{parameter_type="u8",	setup="value :: 1; value :: 2;",								compiler_accepts=false,	parser_matches=false},
	.{parameter_type="s64",	setup="original := 1; value := original;",						compiler_accepts=true,	parser_matches=true,	rival_type="u8"},
];

TYPED_FLOAT_CASES :: Typed_Numeric_Case.[
	.{parameter_type="u8",																	argument="1",					compiler_accepts=true,	parser_matches=true,	rival_type="float32"},
	.{parameter_type="u8",																	argument="1",					compiler_accepts=true,	parser_matches=true,	rival_type="float64"},
	.{parameter_type="s8",																	argument="1",					compiler_accepts=true,	parser_matches=true,	rival_type="float32"},
	.{parameter_type="s8",																	argument="1",					compiler_accepts=true,	parser_matches=true,	rival_type="float64"},
	.{parameter_type="u16",																	argument="1",					compiler_accepts=true,	parser_matches=true,	rival_type="float32"},
	.{parameter_type="u16",																	argument="1",					compiler_accepts=true,	parser_matches=true,	rival_type="float64"},
	.{parameter_type="s16",																	argument="1",					compiler_accepts=true,	parser_matches=true,	rival_type="float32"},
	.{parameter_type="s16",																	argument="1",					compiler_accepts=true,	parser_matches=true,	rival_type="float64"},
	.{parameter_type="u32",																	argument="1",					compiler_accepts=true,	parser_matches=true,	rival_type="float32"},
	.{parameter_type="u32",																	argument="1",					compiler_accepts=true,	parser_matches=true,	rival_type="float64"},
	.{parameter_type="s32",																	argument="1",					compiler_accepts=true,	parser_matches=true,	rival_type="float32"},
	.{parameter_type="s32",																	argument="1",					compiler_accepts=true,	parser_matches=true,	rival_type="float64"},
	.{parameter_type="u64",																	argument="1",					compiler_accepts=true,	parser_matches=true,	rival_type="float32"},
	.{parameter_type="u64",																	argument="1",					compiler_accepts=true,	parser_matches=true,	rival_type="float64"},
	.{parameter_type="s64",																	argument="1",					compiler_accepts=true,	parser_matches=true,	rival_type="float32"},
	.{parameter_type="s64",																	argument="1",					compiler_accepts=true,	parser_matches=true,	rival_type="float64"},
	.{parameter_type="s8",																	argument="-1",					compiler_accepts=true,	parser_matches=true,	rival_type="float32"},
	.{parameter_type="s16",																	argument="-1",					compiler_accepts=true,	parser_matches=true,	rival_type="float64"},
	.{parameter_type="u8",		setup="original :: 1; middle :: original; value :: middle;",								compiler_accepts=true,	parser_matches=true,	rival_type="float32"},
	.{parameter_type="Alias",	globals="Alias :: s16;",	setup="value :: -1;",											compiler_accepts=true,	parser_matches=true,	rival_type="float64"},
	.{parameter_type="float32",																argument="256",					compiler_accepts=true,	parser_matches=true,	rival_type="u8"},
	.{parameter_type="float64",																argument="128",					compiler_accepts=true,	parser_matches=true,	rival_type="s8"},
	.{parameter_type="float32",																argument="-1",					compiler_accepts=true,	parser_matches=true,	rival_type="u8"},
	.{parameter_type="u8",		setup="value :: 1 + 2;",																	compiler_accepts=true,	parser_matches=false,	rival_type="float32"},
	.{parameter_type="float64", setup="value: float32 = 1.5;",																compiler_accepts=true,	parser_matches=true},
	.{parameter_type="float32", setup="value: float64 = 1.5;",																compiler_accepts=false,	parser_matches=false},
	.{parameter_type="float64", setup="value: float32 : 1.5;",																compiler_accepts=true,	parser_matches=true},
	.{parameter_type="float32", setup="value: float64 : 1.5;",																compiler_accepts=false,	parser_matches=false},
	.{parameter_type="float64", setup="original: float32 : 1.5; value :: original;",										compiler_accepts=true,	parser_matches=true},
	.{parameter_type="float32", setup="original: float64 : 1.5; value :: original;",										compiler_accepts=false,	parser_matches=false},
	.{parameter_type="float64", setup="value := 1.5;",																		compiler_accepts=true,	parser_matches=true},
	.{parameter_type="float32", setup="value := 1.23456789;",																compiler_accepts=false,	parser_matches=false},
	.{parameter_type="float32", setup="value: float32 = 1.5;",																compiler_accepts=true,	parser_matches=true,	rival_type="float64"},
	.{parameter_type="float64", setup="value: float64 = 1.5;",																compiler_accepts=true,	parser_matches=true,	rival_type="float32"},
	.{parameter_type="float32", setup="value := 1.5;",																		compiler_accepts=true,	parser_matches=true,	rival_type="float64"},
	.{parameter_type="float64", setup="value := 1.23456789;",																compiler_accepts=true,	parser_matches=true,	rival_type="float32"},
	.{parameter_type="float32", setup="value: float64 = 1.23456789;",						argument="cast(float32) value",	compiler_accepts=true,	parser_matches=true},
	.{parameter_type="float64", setup="value: float32 = 1.5;",								argument="cast(float64) value",	compiler_accepts=true,	parser_matches=true},
	.{parameter_type="float32", setup="value: float64 = 1.23456789;",						argument="cast(float32) value",	compiler_accepts=true,	parser_matches=true,	rival_type="float64"},
	.{parameter_type="float64", setup="value: float32 = 1.5;",								argument="cast(float64) value",	compiler_accepts=true,	parser_matches=true,	rival_type="float32"},
	.{parameter_type="float64", setup="original: float32 = 1.5; value := original;",										compiler_accepts=true,	parser_matches=true},
	.{parameter_type="float32", setup="original: float64 = 1.5; value := original;",										compiler_accepts=false,	parser_matches=false},
	.{parameter_type="float32", setup="value :: 1.5;",																		compiler_accepts=true,	parser_matches=true},
	.{parameter_type="float64", setup="value :: 1.23456789;",																compiler_accepts=true,	parser_matches=true},
	.{parameter_type="float32", setup="value: u8 = 255;",																	compiler_accepts=false,	parser_matches=false},
	.{parameter_type="float64", setup="value: u8 = 255;",																	compiler_accepts=false,	parser_matches=false},
	.{parameter_type="float32", setup="value: s64 = 16777217;",																compiler_accepts=false,	parser_matches=false},
	.{parameter_type="float64", setup="value: s64 = 9007199254740993;",														compiler_accepts=false,	parser_matches=false},
	.{parameter_type="s32",		setup="value: float32 = 1.5;",																compiler_accepts=false,	parser_matches=false},
	.{parameter_type="s64",		setup="value: float64 = 1.5;",																compiler_accepts=false,	parser_matches=false},
	.{parameter_type="float32",	setup="value: s64 = 16777217;",								argument="cast(float32) value",	compiler_accepts=true,	parser_matches=true},
	.{parameter_type="s64",		setup="value: float64 = 1.5;",								argument="cast(s64) value",		compiler_accepts=true,	parser_matches=true},
	.{parameter_type="u16",		setup="value: u8 = 255;",																	compiler_accepts=true,	parser_matches=true,	rival_type="float32"},
	.{parameter_type="float64", setup="value: float32 = 1.5;",																compiler_accepts=true,	parser_matches=true,	rival_type="s64"},
	.{parameter_type="u8",		setup="value: float32 = 1.0;",																compiler_accepts=false,	parser_matches=false},
	.{parameter_type="s64",		setup="value: float64 : 1.0;",																compiler_accepts=false,	parser_matches=false},
	.{parameter_type="float32",	setup="original: u8 : 255; value :: original;",												compiler_accepts=false,	parser_matches=false},
	.{parameter_type="u8",		setup="original: float32 : 1.0; value :: original;",										compiler_accepts=false,	parser_matches=false},
	.{parameter_type="int",		setup="value: int = 1;",																	compiler_accepts=true,	parser_matches=true,	rival_type="float32"},
	.{parameter_type="float",	setup="value: float32 = 1.5;",																compiler_accepts=true,	parser_matches=true},
	.{parameter_type="float32",	setup="value: float = 1.5;",																compiler_accepts=true,	parser_matches=true},
	.{parameter_type="float64",	setup="value: float = 1.5;",																compiler_accepts=true,	parser_matches=true},
	.{parameter_type="float",	setup="value: float64 = 1.5;",																compiler_accepts=false,	parser_matches=false},
	.{parameter_type="float",	setup="value: s64 = 16777217;",								argument="cast(float) value",	compiler_accepts=true,	parser_matches=true},
	.{parameter_type="int",		setup="value: float64 = 1.5;",								argument="cast(int) value",		compiler_accepts=true,	parser_matches=true},
	.{parameter_type="float",	setup="value: float = 1.5;",																compiler_accepts=false,	parser_matches=false,	rival_type="float32"},
	.{parameter_type="int",		setup="value: int = 1;",																	compiler_accepts=false,	parser_matches=false,	rival_type="s64"},
	.{parameter_type="float32",	setup="Float_Alias :: float32; value: Float_Alias = 1.5;",									compiler_accepts=true,	parser_matches=true},
	.{parameter_type="float64",	setup="Original :: float; Alias :: Original; value: Alias = 1.5;",							compiler_accepts=true,	parser_matches=true},
	.{parameter_type="float32",	setup="Alias :: float64; value: Alias = 1.5;",												compiler_accepts=false,	parser_matches=false},
	.{parameter_type="u16",		setup="Alias :: u8; value: Alias = 255;",													compiler_accepts=true,	parser_matches=true},
	.{parameter_type="u8",		setup="Alias :: u16; value: Alias = 1;",													compiler_accepts=false,	parser_matches=false},
	.{parameter_type="float32",	setup="Alias :: float32; value: float64 = 1.5;",			argument="cast(Alias) value",	compiler_accepts=true,	parser_matches=true},
	.{parameter_type="u8",		setup="Alias :: Other; Other :: Alias; value: Alias = 1;",									compiler_accepts=false,	parser_matches=false},
	.{parameter_type="u8",		setup="Alias :: Missing; value: Alias = 1;",												compiler_accepts=false,	parser_matches=false},
	.{parameter_type="u8",		setup="Alias :: u8; Alias :: u16; value: Alias = 1;",										compiler_accepts=false,	parser_matches=false},
	.{parameter_type="u8",		setup="value: Alias = 1; Alias :: u8;",														compiler_accepts=false,	parser_matches=false},
	.{parameter_type="u8",		setup="Alias := u8; value: Alias = 1;",														compiler_accepts=false,	parser_matches=false},
	.{parameter_type="float32",	setup="Alias: Type : float32; value: Alias = 1.5;",											compiler_accepts=true,	parser_matches=true},
	.{parameter_type="u8",		setup="Alias :: u8; nested :: () { Alias :: u16; unused: Alias = 1; } value: Alias = 255;",	compiler_accepts=true,	parser_matches=true, rival_type="u16"},
	.{parameter_type="u8",		setup="Alias :: u16; nested :: () { Alias :: u8; unused: Alias = 1; } value: Alias = 1;",	compiler_accepts=false,	parser_matches=false},
];

NUMERIC_ALIAS_PARAMETER_CASES :: Typed_Numeric_Case.[
	.{parameter_type="Alias",	globals="Alias :: float32;",					setup="value: float32 = 1.5;",					compiler_accepts=true,	parser_matches=true},
	.{parameter_type="Alias",	globals="Original :: int; Alias :: Original;",	setup="value: s64 = 1;",						compiler_accepts=true,	parser_matches=true},
	.{parameter_type="float64",	globals="Alias :: float32;",					setup="value: Alias = 1.5;",					compiler_accepts=true,	parser_matches=true},
	.{parameter_type="float64",	globals="Alias :: float32;",					setup="Alias :: float64; value: Alias = 1.5;",	compiler_accepts=true,	parser_matches=true,	rival_type="Alias"},
	.{parameter_type="Alias",	globals="Alias :: float32;",					setup="value: float32 = 1.5;",					compiler_accepts=false,	parser_matches=false,	rival_type="float32"},
	.{parameter_type="Alias",	globals="Alias :: float32; Alias :: float64;",	setup="value: float32 = 1.5;",					compiler_accepts=false,	parser_matches=false,	rival_type="float32"},
];

FLOAT_CONSTANT_CASES :: Typed_Numeric_Case.[
	.{parameter_type="float32",									setup="value := 1.23456789;",													compiler_accepts=false,	parser_matches=false,	rival_type="string"},
	.{parameter_type="float32",									setup="original: float64 : 1.5; middle :: original; value :: middle;",			compiler_accepts=false,	parser_matches=false},
	.{parameter_type="float",									setup="value :: 1.5;",															compiler_accepts=true,	parser_matches=true,	rival_type="float64"},
	.{parameter_type="float32",									setup="value :: 1.0 + 0.5;",													compiler_accepts=true,	parser_matches=false},
	.{parameter_type="float32",									setup="value :: original; original :: 1.5;",									compiler_accepts=false,	parser_matches=false},
	.{parameter_type="float32",									setup="original :: value; value :: original;",									compiler_accepts=false,	parser_matches=false},
	.{parameter_type="float32",									setup="value :: Missing;",														compiler_accepts=false,	parser_matches=false},
	.{parameter_type="float32",									setup="value :: 1.5; value :: 1.23456789;",										compiler_accepts=false,	parser_matches=false},
	.{parameter_type="float32",									setup="value :: 1.5; nested :: () { value :: 1.23456789; unused := value; }",	compiler_accepts=true,	parser_matches=true,	rival_type="float64"},
	.{parameter_type="float32",	globals="value :: 1.23456789;",	setup="value :: 1.5;",															compiler_accepts=true,	parser_matches=true,	rival_type="float64"},
	.{parameter_type="float32",									setup="original :: cast(float32) 1.23456789; value :: original;",				compiler_accepts=true,	parser_matches=true,	rival_type="float64"},
	.{parameter_type="float32",									setup="original :: 1.23456789; value := original;",								compiler_accepts=false,	parser_matches=false},
];

make_typed_float_cases :: () -> [..] Typed_Numeric_Case {
	cases: [..] Typed_Numeric_Case;
	for fixture: TYPED_FLOAT_CASES {
		array_add(*cases, fixture);
	}

	for fixture: NUMERIC_ALIAS_PARAMETER_CASES {
		array_add(*cases, fixture);
	}

	for fixture: FLOAT_CONSTANT_CASES {
		array_add(*cases, fixture);
	}

	integer_types := string.["u8", "u16", "u32", "u64", "s8", "s16", "s32", "s64", "int"];
	float_types := string.["float32", "float64", "float"];
	for integer_type, index: integer_types {
		boundary_index := ifx integer_type == "int" then 3 else index % 4;
		value := ifx index < 4
			then UNSIGNED_BOUNDARY_CASES[boundary_index].upper
			else SIGNED_BOUNDARY_CASES[boundary_index].lower;
		integer_setup := tprint("value: % = %;", integer_type, value);
		for float_type: float_types {
			float_setup := tprint("value: % = 1.5;", float_type);
			for initializer: string.["=", ":"] {
				array_add(*cases, .{parameter_type=float_type, setup=tprint("value: % % %;", integer_type, initializer, value), compiler_accepts=false, parser_matches=false});
				array_add(*cases, .{parameter_type=integer_type, setup=tprint("value: % % 1.5;", float_type, initializer), compiler_accepts=false, parser_matches=false});
			}

			array_add(*cases, .{parameter_type=float_type, setup=integer_setup, argument=tprint("cast(%) value", float_type), compiler_accepts=true, parser_matches=true});
			array_add(*cases, .{parameter_type=integer_type, setup=float_setup, argument=tprint("cast(%) value", integer_type), compiler_accepts=true, parser_matches=true});
			array_add(*cases, .{parameter_type=integer_type, setup=integer_setup, compiler_accepts=true, parser_matches=true, rival_type=float_type});
			array_add(*cases, .{parameter_type=float_type, setup=float_setup, compiler_accepts=true, parser_matches=true, rival_type=integer_type});
		}
	}

	for fixture: FLOAT_LITERAL_CASES {
		preferred := ifx fixture.preferred_type == "float32" then "float" else "float64";
		rival := ifx fixture.preferred_type == "float32" then "float64" else "float";
		array_add(*cases, .{parameter_type=preferred, argument=fixture.value, compiler_accepts=true, parser_matches=true, rival_type=rival});
		for form: 0..2 {
			setup := ifx form == 0
				then tprint("value :: %;", fixture.value)
				else tprint("original :: %; middle :: original; value :: middle;", fixture.value);

			globals := "";
			if form == 2 {
				setup = "";
				globals = tprint("value :: original; original :: %;", fixture.value);
			}

			array_add(*cases, .{parameter_type=preferred, setup=setup, globals=globals, compiler_accepts=true, parser_matches=true, rival_type=rival});
			for target: string.["float32", "float64"] {
				compatible := target == "float64" || fixture.float32_compatible;
				array_add(*cases, .{parameter_type=target, setup=setup, globals=globals, compiler_accepts=compatible, parser_matches=compatible});
			}
		}
	}

	expected_count := TYPED_FLOAT_CASES.count + NUMERIC_ALIAS_PARAMETER_CASES.count + FLOAT_CONSTANT_CASES.count + integer_types.count * float_types.count * 8 + FLOAT_LITERAL_CASES.count * 10;
	assert(cases.count == expected_count, "Typed integer/float matrix has % cases, expected %.", cases.count, expected_count);
	return cases;
}

make_typed_integer_cases :: () -> [..] Typed_Numeric_Case {
	cases: [..] Typed_Numeric_Case;
	for fixture: TYPED_INTEGER_CASES {
		array_add(*cases, fixture);
	}

	types := string.["u8", "u16", "u32", "u64", "s8", "s16", "s32", "s64"];
	for source_type, source_index: types {
		source_width := 8 << (source_index % 4);
		source_signed := source_index >= 4;
		value := ifx source_signed
			then SIGNED_BOUNDARY_CASES[source_index % 4].lower
			else UNSIGNED_BOUNDARY_CASES[source_index % 4].upper;

		for target_type, target_index: types {
			target_width := 8 << (target_index % 4);
			target_signed := target_index >= 4;
			compatible := (
				target_width >= source_width
				&& (source_signed == target_signed || !source_signed && target_signed && target_width > source_width)
			);

			for initializer: string.["=", ":"] {
				array_add(
					*cases,
					.{
						parameter_type=target_type,
						setup=tprint("value: % % %;", source_type, initializer, value),
						compiler_accepts=compatible,
						parser_matches=compatible
					}
				);
			}

			array_add(
				*cases,
				.{
					parameter_type=target_type,
					setup=tprint("value: % = %;", source_type, value),
					argument=tprint("cast(%) value", target_type),
					compiler_accepts=true,
					parser_matches=true
				}
			);
		}

		for first_index: 0..types.count - 2 {
			for second_index: first_index + 1..types.count - 1 {
				first_width := 8 << (first_index % 4);
				second_width := 8 << (second_index % 4);
				first_signed := first_index >= 4;
				second_signed := second_index >= 4;
				first_compatible := (
					first_width >= source_width
					&& (source_signed == first_signed || !source_signed && first_signed && first_width > source_width)
				);
				second_compatible := (
					second_width >= source_width
					&& (source_signed == second_signed || !source_signed && second_signed && second_width > source_width)
				);
				selected_index := -1;
				if first_compatible {
					selected_index = first_index;
					if second_compatible {
						if second_index == source_index || first_index != source_index && second_width < first_width {
							selected_index = second_index;
						} else if first_index != source_index && first_width == second_width {
							selected_index = -1;
						}
					}
				} else if second_compatible {
					selected_index = second_index;
				}

				first_type := ifx selected_index == second_index
					then types[second_index]
					else types[first_index];
				rival_type := ifx selected_index == second_index
					then types[first_index]
					else types[second_index];
				array_add(
					*cases,
					.{
						parameter_type=first_type,
						setup=tprint("value: % = %;", source_type, value),
						compiler_accepts=selected_index >= 0,
						parser_matches=selected_index >= 0,
						rival_type=rival_type
					}
				);
			}
		}
	}

	expected_count := TYPED_INTEGER_CASES.count + types.count * types.count * 3 + types.count * types.count * (types.count - 1) / 2;
	assert(cases.count == expected_count, "Typed integer matrix has % cases, expected %.", cases.count, expected_count);
	return cases;
}

Aggregate_Conversion_Case :: struct {
	globals: string;
	parameter_type: string = "Base";
	rival_type: string = "string";
	compiler_accepts: bool = true;
	parser_matches: bool = true;
	requires_error_diagnostic: bool = true;
}

AGGREGATE_CHAIN_CASES :: Aggregate_Conversion_Case.[
	.{
		globals=#string JAI
Base :: struct (Left: Type, Right: Type) {
	First: Left;
	Second: Right;
}
Wrapper :: struct {
	#as using,except(First, Second, Left, Right) first: Base(s64, float32);
	#as using,except(Right, Left, Second, First) second: Base(Right=float32, Left=s64);
}
JAI,
		parameter_type="Base(s64, float32)"
	},
	.{
		globals=#string JAI
Base :: struct (T: Type) {
	Value: T;
}
Target :: Base(s64);
Wrapper :: struct {
	#as using,except(Value, T) first: Target;
	#as using,except(T, Value) second: Base(T=s64);
}
JAI,
		parameter_type="Target"
	},
	.{
		globals=#string JAI
Leaf :: struct {
	Value: s64;
}
Base :: struct (T: Type) {
	using,except(Value) leaf: T;
}
Wrapper :: struct {
	#as using,except(leaf, T) first: Base(Leaf);
	#as using,except(T, leaf) second: Base(Leaf);
}
JAI,
		parameter_type="Base(Leaf)"
	},
	.{
		globals=#string JAI
Leaf :: struct (T: Type) {
	Value: T;
}
Base :: struct (T: Type) {
	using,except(Value, T) leaf: Leaf(T);
}
Wrapper :: struct {
	#as using,except(leaf, T) first: Base(s64);
	#as using,except(T, leaf) second: Base(s64);
}
JAI,
		parameter_type="Base(s64)"
	},
	.{
		globals=#string JAI
Base :: struct (T: Type) {
	Value: T;
}
Middle :: struct (T: Type) {
	#as using,except(Value, T) base: Base(T);
}
Wrapper :: struct {
	#as using,except(base, T) first: Middle(s64);
	#as using,except(T, base) second: Middle(s64);
}
JAI,
		parameter_type="Base(s64)"
	},
	.{
		globals=#string JAI
Base :: struct (T: Type) {
	Value: T;
}
Wrapper :: struct {
	#as using,except(Value, T) first: Base(s64);
	#as using,except(Value, T) second: Base(s64);
}
JAI,
		parameter_type="Wrapper",
		rival_type="Base(s64)"
	},
	.{
		globals=#string JAI
Base :: struct (T: Type) {
	Value: T;
}
Wrapper :: struct {
	#as using,except(Value, T) first: Base(s64);
	#as using,except(Value, T) second: Base(float32);
}
JAI,
		parameter_type="Base(s64)",
		parser_matches=false
	},
	.{
		globals=#string JAI
Base :: struct (T: Type) {
	Value: T;
}
Wrapper :: struct {
	#as using,except(Value) first: Base(s64);
	#as using,except(Value) second: Base(s64);
}
JAI,
		parameter_type="Base(s64)",
		compiler_accepts=false,
		parser_matches=false
	},
	.{
		globals=#string JAI
Base :: struct (T: Type) {
	Value: T;
}
Wrapper :: struct {
	#as using,except(T) first: Base(s64);
	#as using,except(T) second: Base(s64);
}
JAI,
		parameter_type="Base(s64)",
		compiler_accepts=false,
		parser_matches=false
	},
	.{
		globals=#string JAI
Base :: struct (T: Type) {
	T: s64;
}
Wrapper :: struct {
	#as using,except(T) first: Base(s64);
	#as using,except(T) second: Base(s64);
}
JAI,
		parameter_type="Base(s64)",
		parser_matches=false
	},
	.{
		globals=#string JAI
Base :: struct (T: Type) {
	Value: T;
}
Wrapper :: struct {
	#as using,except(Value, T) first: Base(Missing);
	#as using,except(Value, T) second: Base(Missing);
}
JAI,
		parameter_type="Base(s64)",
		compiler_accepts=false,
		parser_matches=false
	},
	.{
		globals=#string JAI
Base :: struct (T: Type) {
	#if T == s64 {
		Value: T;
	}
}
Wrapper :: struct {
	#as using,except(Value, T) first: Base(s64);
	#as using,except(Value, T) second: Base(s64);
}
JAI,
		parameter_type="Base(s64)",
		parser_matches=false
	},
	.{
		globals=#string JAI
Base :: struct (T: Type, T: Type) {
	Value: s64;
}
Wrapper :: struct {
	#as using,except(Value, T) first: Base(s64, s64);
	#as using,except(Value, T) second: Base(s64, s64);
}
JAI,
		parameter_type="Base(s64, s64)",
		compiler_accepts=false,
		parser_matches=false
	},
	.{
		globals=#string JAI
Base :: struct (T: Type) {
	#if true {
		Value: T;
	} else {
		Inactive: Missing;
	}
}
Wrapper :: struct {
	#as using,except(Value, T) first: Base(s64);
	#as using,except(Value, T) second: Base(s64);
}
JAI,
		parameter_type="Base(s64)"
	},
	.{
		globals=#string JAI
Leaf :: struct {
	Value: s64;
}
Base :: struct (T: Type) {
	#if false {
		Inactive: Missing;
	} else {
		using,except(Value) leaf: T;
	}
}
Wrapper :: struct {
	#as using,except(leaf, T) first: Base(Leaf);
	#as using,except(leaf, T) second: Base(Leaf);
}
JAI,
		parameter_type="Base(Leaf)"
	},
	.{
		globals=#string JAI
Base :: struct (T: Type) {}
Wrapper :: struct {
	#as using,except(T) first: Base(s64);
	#as using,except(T) second: Base(s64);
}
JAI,
		parameter_type="Base(s64)"
	},
	.{
		globals=#string JAI
Base :: struct {
	#if false {
		Inactive: s64;
	} else {
		Value: s64;
	}
}
Wrapper :: struct {
	#as using,except(Value) first: Base;
	#as using,except(Value) second: Base;
}
JAI
	},
	.{
		globals=#string JAI
Base :: struct {
	#if true {
		Value: s64;
	} else {
		Inactive: Missing;
	}
}
Wrapper :: struct {
	#as using,except(Value) first: Base;
	#as using,except(Value) second: Base;
}
JAI
	},
	.{
		globals=#string JAI
Base :: struct {
	#if true {
		#if false {
			Inactive: Missing;
		} else {
			Value: s64;
		}
	}
}
Wrapper :: struct {
	#as using,except(Value) first: Base;
	#as using,except(Value) second: Base;
}
JAI
	},
	.{
		globals=#string JAI
Original :: false;
Middle :: Original;
Enabled :: Middle;
Base :: struct {
	#if Enabled {
		Inactive: Missing;
	} else {
		Value: s64;
	}
}
Wrapper :: struct {
	#as using,except(Value) first: Base;
	#as using,except(Value) second: Base;
}
JAI
	},
	.{
		globals=#string JAI
Enabled: bool : true;
Base :: struct {
	#if Enabled {
		Value: s64;
	}
}
Wrapper :: struct {
	#as using,except(Value) first: Base;
	#as using,except(Value) second: Base;
}
JAI
	},
	.{
		globals=#string JAI
Base :: struct {
	Value: s64;
	#if false {
		Inactive: Missing;
	}
}
Wrapper :: struct {
	#as using,except(Value) first: Base;
	#as using,except(Value) second: Base;
}
JAI
	},
	.{
		globals=#string JAI
Leaf :: struct {
	Value: s64;
}
Base :: struct {
	#if true {
		using,except(Value) leaf: Leaf;
		Extra: s64;
	}
}
Wrapper :: struct {
	#as using,except(leaf, Extra) first: Base;
	#as using,except(leaf, Extra) second: Base;
}
JAI
	},
	.{
		globals=#string JAI
Base :: struct {
	#if false {
		Inactive: s64;
	} else {
		Value: s64;
		Extra: s64;
	}
}
Wrapper :: struct {
	#as using,except(Value) first: Base;
	#as using,except(Value) second: Base;
}
JAI,
		compiler_accepts=false,
		parser_matches=false
	},
	.{
		globals=#string JAI
Enabled :: 1 == 1;
Base :: struct {
	#if Enabled {
		Value: s64;
	}
}
Wrapper :: struct {
	#as using,except(Value) first: Base;
	#as using,except(Value) second: Base;
}
JAI,
		parser_matches=false
	},
	.{
		globals=#string JAI
Base :: struct {
	#if Missing {
		Value: s64;
	}
}
Wrapper :: struct {
	#as using,except(Value) first: Base;
	#as using,except(Value) second: Base;
}
JAI,
		compiler_accepts=false,
		parser_matches=false
	},
	.{
		globals=#string JAI
Enabled := true;
Base :: struct {
	#if Enabled {
		Value: s64;
	}
}
Wrapper :: struct {
	#as using,except(Value) first: Base;
	#as using,except(Value) second: Base;
}
JAI,
		compiler_accepts=false,
		parser_matches=false
	},
	.{
		globals=#string JAI
Enabled :: true;
Enabled :: false;
Base :: struct {
	#if Enabled {
		Value: s64;
	}
}
Wrapper :: struct {
	#as using,except(Value) first: Base;
	#as using,except(Value) second: Base;
}
JAI,
		compiler_accepts=false,
		parser_matches=false
	},
	.{
		globals=#string JAI
Base :: struct {
	Value: s64;
}
Left :: struct {
	#as using,except(Value) first: Base;
}
Right :: struct {
	#as using,except(Value) second: Base;
}
Wrapper :: struct {
	#as using,except(second) right: Right;
	#as using,except(first) left: Left;
}
JAI
	},
	.{
		globals=#string JAI
Base :: struct {
	Value: s64;
}
Middle :: struct {
	#as using,except(Value) base: Base;
}
Alias :: Middle;
Wrapper :: struct {
	#as using,except(base) first: Middle;
	#as using,except(base) second: Alias;
}
JAI
	},
	.{
		globals=#string JAI
Base :: struct {
	Value: s64;
}
Inner :: struct {
	#as using,except(Value) base: Base;
}
Middle :: struct {
	#as using,except(base) inner: Inner;
}
Wrapper :: struct {
	#as using,except(inner) first: Middle;
	#as using,except(inner) second: Middle;
}
JAI
	},
	.{
		globals=#string JAI
Base :: struct {
	Value: s64;
}
Middle :: struct {
	#as using,except(Value) base: Base;
}
Wrapper :: struct {
	#as using,except(Value) direct: Base;
	#as using,except(base) indirect: Middle;
}
JAI
	},
	.{
		globals=#string JAI
Base :: struct {
	Value: s64;
}
Middle :: struct {
	#as using,except(Value) base: Base;
}
Wrapper :: struct {
	#as using,except(base) first: Middle;
	#as using,except(base) second: Middle;
}
JAI,
		parameter_type="Wrapper",
		rival_type="Base"
	},
	.{
		globals=#string JAI
Base :: struct {
	Value: s64;
}
Left :: struct {
	Extra: s64;
	#as using,except(Value) first: Base;
}
Right :: struct {
	Extra: s64;
	#as using,except(Value) second: Base;
}
Wrapper :: struct {
	#as using,except(first) left: Left;
	#as using,except(second) right: Right;
}
JAI,
		compiler_accepts=false,
		parser_matches=false
	},
	.{
		globals=#string JAI
Base :: struct {
	Value: s64;
}
Middle :: struct {
	#as using,except(Value) base: Base;
	#as using,except(Value) base: Base;
}
Wrapper :: struct {
	#as using,except(base) first: Middle;
	#as using,except(base) second: Middle;
}
JAI,
		compiler_accepts=false,
		parser_matches=false
	},
	.{
		globals=#string JAI
Base :: struct (T: Type) {
	Value: T;
}
Wrapper :: struct {
	#as using,except(Value, T) first: Base(s64);
	#as using,except(Value, T) second: Base(s64);
}
JAI,
		parameter_type="Base(s64)"
	},
	.{
		globals=#string JAI
Base :: struct {
	#if true {
		Value: s64;
	}
}
Wrapper :: struct {
	#as using,except(Value) first: Base;
	#as using,except(Value) second: Base;
}
JAI
	},
	.{
		globals=#string JAI
Leaf :: struct {
	Value: s64;
}
Base :: struct {
	using,except(Value) leaf: Leaf;
	Extra: s64;
}
Wrapper :: struct {
	#as using,except(leaf, Extra) first: Base;
	#as using,except(leaf, Extra) second: Base;
}
JAI
	},
	.{
		globals=#string JAI
Base :: struct {
	Value: s64;
}
Left :: struct {
	#as using,except(Value) first: Base;
}
Right :: struct {
	#as using,except(Value) second: Base;
}
Wrapper :: struct {
	#as using,except(first) left: Left;
	#as using,except(second) right: Right;
}
JAI
	},
	.{
		globals=#string JAI
Base :: struct {
	Value: s64;
	Extra: s64;
}
Wrapper :: struct {
	#as using,except(Value, Extra) second: Base;
	#as using,except(Extra, Value) first: Base;
}
JAI
	},
	.{
		globals=#string JAI
Base :: struct {
	Value: s64;
}
Original :: Base;
Alias :: Original;
Wrapper :: struct {
	#as using,except(Value) first: Alias;
	#as using,except(Value) second: Base;
}
JAI
	},
	.{
		globals=#string JAI
Base :: struct {
	Value: s64;
}
Wrapper :: struct {
	#as using,except(Value) first: Base;
	#as using,except(Value) second: Base;
	#as using,except(Value) third: Base;
}
JAI
	},
	.{
		globals=#string JAI
Base :: struct {
	Value: s64;
}
Wrapper :: struct {
	#as using,except(Value) first: Base;
	#as using,except(Value) second: Base;
}
JAI,
		parameter_type="Wrapper",
		rival_type="Base"
	},
	.{
		globals=#string JAI
Base :: struct {
	Value: s64;
}
Alias :: Base;
Wrapper :: struct {
	#as using,except(Value) first: Base;
	#as using,except(Value) second: Base;
}
JAI,
		rival_type="Alias",
		compiler_accepts=false,
		parser_matches=false
	},
	.{
		globals=#string JAI
Base :: struct {
	Value: s64;
}
Wrapper :: struct {
	#as using first: Base;
	#as using second: Base;
}
JAI,
		compiler_accepts=false,
		parser_matches=false
	},
	.{
		globals=#string JAI
Base :: struct {
	Value: s64;
	Extra: s64;
}
Wrapper :: struct {
	#as using,except(Value) first: Base;
	#as using,except(Value) second: Base;
}
JAI,
		compiler_accepts=false,
		parser_matches=false
	},
	.{
		globals=#string JAI
Base :: struct {
	Value: s64;
}
Wrapper :: struct {
	#as using,except(Value) first: Base;
	#as using,except(Value) second: Base;
	#as using missing: Missing;
}
JAI,
		compiler_accepts=false,
		parser_matches=false
	},
	.{
		globals=#string JAI
Base :: struct {
	Value: s64;
}
Wrapper :: struct {
	#as using,except(Value) first: Base;
	#as using,except(Value) first: Base;
}
JAI,
		compiler_accepts=false,
		parser_matches=false
	},
	.{
		globals=#string JAI
Base :: struct {
	Value: s64;
}
Unrelated :: struct {
	OtherValue: s64;
}
Wrapper :: struct {
	#as using,except(Value) first: Base;
	#as using,except(Value) second: Base;
	#as using,except(OtherValue) other: Unrelated;
}
JAI,
		rival_type="Unrelated",
		compiler_accepts=false,
		parser_matches=false
	},
	.{
		globals=#string JAI
Base :: struct {
	Value: s64;
}
Wrapper :: struct {
	#as using,except(Value) first: Base;
	#as using,except(Value) second: Base;
}
JAI
	},
	.{
		globals=#string JAI
Base :: struct {
	Value: s64;
}
Inner :: struct {
	#as using base: Base;
}
Middle :: struct {
	using inner: Inner;
}
Wrapper :: struct {
	using middle: Middle;
}
JAI
	},
	.{
		globals=#string JAI
Base :: struct {
	Value: s64;
}
Middle :: struct {
	#as using base: Base;
}
Wrapper :: struct {
	using middle: Middle;
}
JAI,
		parameter_type="Middle",
		compiler_accepts=false,
		parser_matches=false
	},
	.{
		globals=#string JAI
Base :: struct {
	Value: s64;
}
Middle :: struct {
	using base: Base;
}
Wrapper :: struct {
	using middle: Middle;
}
JAI,
		compiler_accepts=false,
		parser_matches=false
	},
	.{
		globals=#string JAI
Base :: struct {
	Value: s64;
}
Middle :: struct {
	using base: Base;
}
Wrapper :: struct {
	#as using middle: Middle;
}
JAI,
		compiler_accepts=false,
		parser_matches=false
	},
	.{
		globals=#string JAI
Base :: struct {
	Value: s64;
}
Middle :: struct {
	#as using base: Base;
}
Wrapper :: struct {
	using middle: Middle;
}
JAI,
		parameter_type="Wrapper",
		rival_type="Base"
	},
	.{
		globals=#string JAI
Base :: struct {
	Value: s64;
}
Middle :: struct {
	#as using base: Base;
}
Original :: Middle;
Alias :: Original;
Wrapper :: struct {
	using middle: Alias;
}
JAI
	},
	.{
		globals=#string JAI
Base :: struct {
	Value: s64;
}
Middle :: struct (T: Type) {
	#as using base: T;
}
Wrapper :: struct {
	using middle: Middle(Base);
}
JAI
	},
	.{
		globals=#string JAI
Base :: struct {
	Value: s64;
}
Unrelated :: struct {
	OtherValue: s64;
}
Left :: struct {
	#as using base: Base;
}
Right :: struct {
	#as using other: Unrelated;
}
Wrapper :: struct {
	using left: Left;
	using right: Right;
}
JAI,
		rival_type="Unrelated",
		compiler_accepts=false,
		parser_matches=false
	},
	.{
		globals=#string JAI
Base :: struct {
	Value: s64;
}
Middle :: struct {
	using missing: Missing;
}
Wrapper :: struct {
	#as using base: Base;
	using middle: Middle;
}
JAI,
		compiler_accepts=false,
		parser_matches=false
	},
	.{
		globals=#string JAI
Base :: struct {
	Value: s64;
}
Middle :: struct {
	#as using base: Base;
}
Wrapper :: struct {
	using,except(base) middle: Middle;
}
JAI,
		compiler_accepts=false,
		parser_matches=false
	},
	.{
		globals=#string JAI
Base :: struct {
	Value: s64;
}
Middle :: struct {
	#as using base: Base;
}
Wrapper :: struct {
	using,only(Value) middle: Middle;
}
JAI,
		compiler_accepts=false,
		parser_matches=false
	},
	.{
		globals=#string JAI
Base :: struct {
	Value: s64;
}
Middle :: struct {
	using wrapper: Wrapper;
}
Wrapper :: struct {
	using middle: Middle;
}
JAI,
		compiler_accepts=false,
		parser_matches=false,
		requires_error_diagnostic=false
	},
	.{
		globals=#string JAI
Base :: struct {
	Value: s64;
}
Unrelated :: struct {
	OtherValue: s64;
}
Left :: struct {
	#as using base: Base;
}
Right :: struct {
	#as using other: Unrelated;
}
Wrapper :: struct {
	#as using left: Left;
	#as using right: Right;
}
JAI,
		rival_type="Unrelated",
		compiler_accepts=false,
		parser_matches=false
	},
	.{
		globals=#string JAI
Base :: struct {
	Value: s64;
}
Middle :: struct {
	#as using base: Base;
}
Wrapper :: struct {
	#as using middle: Middle;
}
JAI
	},
	.{
		globals=#string JAI
Base :: struct {
	Value: s64;
}
Inner :: struct {
	#as using base: Base;
}
Middle :: struct {
	#as using inner: Inner;
}
Wrapper :: struct {
	#as using middle: Middle;
}
JAI
	},
	.{
		globals=#string JAI
Base :: struct {
	Value: s64;
}
Middle :: struct {
	#as using base: Base;
}
Wrapper :: struct {
	#as using middle: Middle;
}
JAI,
		parameter_type="Wrapper",
		rival_type="Base"
	},
	.{
		globals=#string JAI
Base :: struct {
}
Left :: struct {
	#as using first: Base;
}
Right :: struct {
	#as using second: Base;
}
Wrapper :: struct {
	#as using left: Left;
	#as using right: Right;
}
JAI,
		parser_matches=false
	},
	.{
		globals=#string JAI
Base :: struct {
}
Middle :: struct {
	#as using nested: Base;
}
Wrapper :: struct {
	#as using base: Base;
	#as using middle: Middle;
}
JAI,
		parser_matches=false
	},
	.{
		globals=#string JAI
Base :: struct {
}
Middle :: struct {
	#as using first: Base;
	#as using second: Base;
}
Wrapper :: struct {
	#as using middle: Middle;
}
JAI,
		parser_matches=false
	},
	.{
		globals=#string JAI
Base :: struct {
	Value: s64;
}
Middle :: struct {
	#as using missing: Missing;
}
Wrapper :: struct {
	#as using base: Base;
	#as using middle: Middle;
}
JAI,
		compiler_accepts=false,
		parser_matches=false
	},
	.{
		globals=#string JAI
Base :: struct {
	Value: s64;
}
Middle :: struct {
	#as using wrapper: Wrapper;
}
Wrapper :: struct {
	#as using middle: Middle;
}
JAI,
		compiler_accepts=false,
		parser_matches=false,
		requires_error_diagnostic=false
	},
	.{
		globals=#string JAI
Base :: struct {
	Value: s64;
}
Middle :: struct {
	base: Base;
}
Wrapper :: struct {
	#as using middle: Middle;
}
JAI,
		compiler_accepts=false,
		parser_matches=false
	},
	.{
		globals=#string JAI
Base :: struct {
	Value: s64;
}
Middle :: struct {
	#as using base: Base;
}
Wrapper :: struct {
	using middle: Middle;
}
JAI
	},
	.{
		globals=#string JAI
Base :: struct {
	Value: s64;
}
Middle :: struct {
	#as using base: Base;
}
Middle :: struct {
	Value: s64;
}
Wrapper :: struct {
	#as using middle: Middle;
}
JAI,
		compiler_accepts=false,
		parser_matches=false
	},
	.{
		globals=#string JAI
Base :: struct {
	Value: s64;
}
Middle :: struct {
	#as using base: Base;
}
Original :: Middle;
Alias :: Original;
Wrapper :: struct {
	#as using middle: Alias;
}
JAI
	},
	.{
		globals=#string JAI
Base :: struct {
	Value: s64;
}
Middle :: struct (T: Type) {
	#as using base: T;
}
Wrapper :: struct {
	#as using middle: Middle(Base);
}
JAI
	},
	.{
		globals=#string JAI
Base :: struct {
	Value: s64;
}
Unrelated :: struct {
	OtherValue: s64;
}
Middle :: struct {
	#as using other: Unrelated;
}
Wrapper :: struct {
	#as using base: Base;
	#as using middle: Middle;
}
JAI
	},
	.{
		globals=#string JAI
Base :: struct {
	Value: s64;
}
Unrelated :: struct {
	OtherValue: s64;
}
Middle :: struct (T: Type) {
	#as using base: T;
}
Wrapper :: struct {
	#as using middle: Middle(Unrelated);
}
JAI,
		parameter_type="Unrelated"
	},
	.{
		globals=#string JAI
Base :: struct {
	Value: s64;
}
Middle :: struct (T: Type) {
	#if T == Base {
		#as using base: Base;
	} else {
		#as using next: T;
	}
}
Wrapper :: struct {
	#as using middle: Middle(Middle(Base));
}
JAI,
		compiler_accepts=false,
		parser_matches=false
	},
];

TYPED_INTEGER_OVERLOAD_SOURCE :: #string JAI
make :: (value: %) {}
make :: (value: %) {}
%
main :: () {
	%
	make(%);
}
JAI;

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
	.{"0.0",				"float32",	true},
	.{"1.5",				"float32",	true},
	.{"-1.5",				"float32",	true},
	.{"1.2345678",			"float64",	true},
	.{"1.23456789",			"float64",	false},
	.{"1.0e40",				"float64",	false},
	.{"0001.5000",			"float32",	true},
	.{"1.5000",				"float32",	true},
	.{"1_234.5_000",		"float32",	true},
	.{"0001.2345678000",	"float64",	true},
	.{"1.234_567_8",		"float64",	true},
	.{"1.2345678900",		"float64",	false},
	.{"1.5e0",				"float32",	true},
	.{"1.5E+0",				"float32",	true},
	.{"1.5e-2",				"float32",	true},
	.{"12345678.0",			"float64",	true},
	.{"123456789.0",		"float64",	false},
	.{"3.0e38",				"float32",	true},
	.{"3.4e38",				"float32",	true},
	.{"3.4028235e38",		"float64",	true},
	.{"3.4028236e38",		"float64",	true},
	.{"3.4028237e38",		"float64",	false},
	.{"-3.4028235e38",		"float64",	true},
	.{"1.1754944e-38",		"float64",	true},
	.{"1.1754943e-38",		"float64",	false},
	.{"-1.1754943e-38",		"float64",	false},
	.{"1.0e-38",			"float64",	false},
	.{"1.0e-45",			"float64",	false},
	.{"1.0e-46",			"float64",	false},
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
	setup: string = "";
	globals: string = "";
	parser_matches: bool = true;
}

MIXED_AGGREGATE_RANK_GLOBALS :: #string JAI
Base :: struct {
	Value: s64;
}
Wrapper :: struct {
	#as using base: Base;
}
JAI;

NUMERIC_RANK_CASES :: Numeric_Rank_Case.[
	.{
		first_parameters="aggregate: Wrapper, number: float32",
		second_parameters="aggregate: Base, number: s64",
		arguments="value, 1",
		selected_index=1,
		setup="value: Wrapper;",
		globals=MIXED_AGGREGATE_RANK_GLOBALS,
		parser_matches=false
	},
	.{
		first_parameters="number: float32, aggregate: Wrapper",
		second_parameters="number: u8, aggregate: Base",
		arguments="1, value",
		selected_index=0,
		setup="value: Wrapper;",
		globals=MIXED_AGGREGATE_RANK_GLOBALS
	},
	.{
		first_parameters="aggregate: Wrapper, number: float32",
		second_parameters="aggregate: Base, number: u8",
		arguments="number=1, aggregate=value",
		selected_index=0,
		setup="value: Wrapper;",
		globals=MIXED_AGGREGATE_RANK_GLOBALS
	},
	.{
		first_parameters="aggregate: Wrapper, number: u16",
		second_parameters="aggregate: Base, number: u8",
		arguments="value, number",
		selected_index=1,
		setup="value: Wrapper; number: u8 = 1;",
		globals=MIXED_AGGREGATE_RANK_GLOBALS,
		parser_matches=false
	},
	.{
		first_parameters="aggregate: Wrapper, number: float64",
		second_parameters="aggregate: Base, number: float32",
		arguments="value, number",
		selected_index=1,
		setup="value: Wrapper; number: float32 = 1.5;",
		globals=MIXED_AGGREGATE_RANK_GLOBALS,
		parser_matches=false
	},
	.{
		first_parameters="aggregate: Wrapper, number: float64",
		second_parameters="aggregate: Base, number: float32",
		arguments="value, 1.5",
		selected_index=1,
		setup="value: Wrapper;",
		globals=MIXED_AGGREGATE_RANK_GLOBALS,
		parser_matches=false
	},
	.{
		first_parameters="aggregate: Wrapper, first: float32, second: float64",
		second_parameters="aggregate: Base, first: u8, second: u16",
		arguments="value, 1, 1",
		selected_index=0,
		setup="value: Wrapper;",
		globals=MIXED_AGGREGATE_RANK_GLOBALS
	},
	.{
		first_parameters="aggregate: Wrapper, number: float32, enabled: bool = true",
		second_parameters="aggregate: Base, number: u8, enabled: bool = false",
		arguments="number=1, aggregate=value",
		selected_index=0,
		setup="value: Wrapper;",
		globals=MIXED_AGGREGATE_RANK_GLOBALS
	},
	.{
		first_parameters="aggregate: Base, number: float32",
		second_parameters="aggregate: Base, number: u8",
		arguments="value, 1",
		selected_index=1,
		setup="value: Wrapper;",
		globals=MIXED_AGGREGATE_RANK_GLOBALS
	},
	.{
		first_parameters="aggregate: Base, number: u8",
		second_parameters="aggregate: Base, number: u16",
		arguments="value, 1",
		selected_index=0,
		setup="value: Wrapper;",
		globals=MIXED_AGGREGATE_RANK_GLOBALS
	},
	.{
		first_parameters="aggregate: Base, number: float64",
		second_parameters="aggregate: Base, number: float32",
		arguments="value, number",
		selected_index=1,
		setup="value: Wrapper; number: float32 = 1.5;",
		globals=MIXED_AGGREGATE_RANK_GLOBALS
	},
	.{
		first_parameters="first: Wrapper, second: Base",
		second_parameters="first: Base, second: Wrapper",
		arguments="value, value",
		selected_index=-1,
		setup="value: Wrapper;",
		globals=MIXED_AGGREGATE_RANK_GLOBALS
	},
	.{
		first_parameters="aggregate: Wrapper, number: u8",
		second_parameters="aggregate: Base, number: float32",
		arguments="value, 1",
		selected_index=0,
		setup="value: Wrapper;",
		globals=MIXED_AGGREGATE_RANK_GLOBALS
	},
	.{
		first_parameters="aggregate: Wrapper, number: float32",
		second_parameters="aggregate: Base, number: u8",
		arguments="value, 1",
		selected_index=0,
		setup="value: Wrapper;",
		globals=MIXED_AGGREGATE_RANK_GLOBALS
	},
	.{first_parameters="first: u8, second: s16",						second_parameters="first: float32, second: float64",						arguments="1, 1",				selected_index=0},
	.{first_parameters="first: u8, second: float32",					second_parameters="first: float32, second: u8",								arguments="1, 1",				selected_index=-1},
	.{first_parameters="first: u8, second: s16, enabled: bool = true",	second_parameters="first: float32, second: float64, enabled: bool = true",	arguments="second=1, first=1",	selected_index=0},
	.{first_parameters="first: float64, second: float64",				second_parameters="first: float32, second: float64",						arguments="1, 1.5",				selected_index=1},
	.{first_parameters="first: float64, second: s64",					second_parameters="first: float32, second: s64",							arguments="1, 1",				selected_index=1},
	.{first_parameters="first: float32, second: float64",				second_parameters="first: float64, second: float32",						arguments="1, 1",				selected_index=-1},
	.{first_parameters="value: float64, enabled: bool = true",			second_parameters="value: float32, enabled: bool = true",					arguments="value=1",			selected_index=1},
	.{first_parameters="first: s8, second: u8",							second_parameters="first: u16, second: s16",								arguments="1, 1",				selected_index=0},
	.{first_parameters="first: s8, second: u16",						second_parameters="first: u16, second: s8",									arguments="1, 1",				selected_index=-1},
	.{first_parameters="value: s8, enabled: bool = true",				second_parameters="value: u16, enabled: bool = true",						arguments="value=1",			selected_index=0},
];

THREE_CANDIDATE_RANK_CASES :: Numeric_Rank_Case.[
	.{first_parameters="value: u8",					second_parameters="value: u16",				arguments="1",		selected_index=0,	third_parameters="value: u32"},
	.{first_parameters="value: u8",					second_parameters="value: u16",				arguments="256",	selected_index=1,	third_parameters="value: u32"},
	.{first_parameters="value: s8",					second_parameters="value: u8",				arguments="1",		selected_index=2,	third_parameters="value: s64"},
	.{first_parameters="first: u8, second: u16",	second_parameters="first: u16, second: u8",	arguments="1, 1",	selected_index=2,	third_parameters="first: u8, second: u8"},
	.{first_parameters="first: u8, second: u16",	second_parameters="first: u16, second: u8",	arguments="1, 1",	selected_index=-1,	third_parameters="first: u32, second: u32"},
	.{first_parameters="first: u16, second: u32",	second_parameters="first: u32, second: u8",	arguments="1, 1",	selected_index=-1,	third_parameters="first: u8, second: u32"},
	.{first_parameters="value: s8",					second_parameters="value: u8",				arguments="1",		selected_index=-1,	third_parameters="value: u16"},
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

make_numeric_rank_source :: (fixture: Numeric_Rank_Case, first: string, second: string) -> string {
	SOURCE :: #string JAI
%
%
main :: () {
	%
	make(%);
}
JAI;
	declarations := tprint("make :: (%) {}\nmake :: (%) {}\n", first, second);
	if fixture.third_parameters {
		declarations = tprint("%make :: (%) {}\n", declarations, fixture.third_parameters);
	}

	return tprint(SOURCE, declarations, fixture.globals, fixture.setup, fixture.arguments);
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

			rotated := fixture;
			rotated.first_parameters = parameters[rotation];
			rotated.second_parameters = parameters[(rotation + 1) % 3];
			rotated.third_parameters = parameters[(rotation + 2) % 3];
			rotated.selected_index = selected_index;
			array_add(*cases, rotated);
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
