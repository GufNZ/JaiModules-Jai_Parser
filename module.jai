#module_parameters(
	ENABLE_TRIVIA			:= false,
	EVALUATE_STRING_ESCAPES	:= true,
	INTERN_IDENTIFIERS		:= false,
	USE_SIMD				:= true,
	TRACK_AST_REUSE			:= false
);

#load "lexer.jai";		// digest: lexer
#load "parser.jai";		// digest: parser
#load "resolution.jai";	// digest: parser
