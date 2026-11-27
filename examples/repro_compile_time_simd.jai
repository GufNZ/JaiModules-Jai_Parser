#import "Basic";
Simd :: #import "Jai_Parser"(ENABLE_TRIVIA = true, USE_SIMD = true);

first_set_bit :: (mask: u64) -> s64 {
	advance: s64 = 32;
	#asm {
		bsf advance, mask;
	}

	return advance;
}

check_masks :: () -> bool {
	SOURCE :: "Fixture_Using_Member :: struct { using member: Fixture_Constraint; }";
	IDENTIFIER :: "Fixture_Using_Member";
	lexer: Simd.Lexer;
	Simd.set_input_from_string(*lexer, SOURCE);
	first := Simd.peek_next_token(*lexer).original_text;
	features := Simd.get_simd_features();
	print("SSE2 stop mask: %; CPU flags: %; first token: %\n", Simd.identifier_simd_stop_mask(SOURCE.data), features, first);
	sse: Simd.Lexer;
	Simd.set_input_from_string(*sse, SOURCE);
	sse.simd_features = .INITIALISED;
	print("SSE2 first token: %\n", Simd.peek_next_token(*sse).original_text);
	if features & .AVX2 {
		mask := Simd.identifier_avx2_stop_mask(SOURCE.data);
		print("AVX2 stop mask: %; bsf: % (expected 20)\n", mask, first_set_bit(mask));
	}
	if features & .AVX512 {
		print("AVX-512 stop mask: %\n", Simd.identifier_avx512_stop_mask(SOURCE.data));
	}

	return first == IDENTIFIER;
}

COMPILE_TIME_OK :: #run check_masks();

main :: () {
	print("Native execution: ");
	assert(check_masks());
	assert(COMPILE_TIME_OK, "The compile-time lexer split the identifier.");
}
