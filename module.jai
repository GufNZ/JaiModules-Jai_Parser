#module_parameters(
	ENABLE_TRIVIA := false,
	EVALUATE_STRING_ESCAPES := true,
	INTERN_IDENTIFIERS := false,
	ENABLE_SIMD := false,
	ENABLE_AVX2 := false,
	ENABLE_AVX512 := false
);

#load "lexer.jai";
#load "parser.jai";
#load "resolution.jai";
