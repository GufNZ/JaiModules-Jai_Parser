/*
AVX2 identifier classifier regression, extracted from the Jai_Parser lexer.
Requires x64 with AVX2 and OS support for YMM state.

	jai -x64 -quiet repro_compile_time_pmovmskb.jai
	./repro_compile_time_pmovmskb.exe

Observed on Windows x64, Jai beta 0.2.031:
	#run:   mask 4294901760 (scalar 3236954112), identifier length 16 (expected 20)
	native: mask 3236954112 (scalar 3236954112), identifier length 20 (expected 20)

The build succeeds even when the #run result is wrong.
The executable prints both results before reporting any failure and exiting with status 1.
This reproduces the classifier mismatch but does not identify a faulty instruction.
*/

#import "Basic";
Machine_X64 :: #import "Machine_X64";

SOURCE :: "Fixture_Using_Member :: struct { using member: Fixture_Constraint; }";
IDENTIFIER :: "Fixture_Using_Member";

has_avx2 :: () -> bool {
	cpu := Machine_X64.get_cpu_info();
	for Machine_X64.x86_Feature_Flag.[.XSAVE, .OSXSAVE, .AVX, .AVX2] {
		if !Machine_X64.check_feature(cpu.feature_leaves, it) {
			return false;
		}
	}

	xcr0: u32;
	#asm XSAVE {
		xor.d selector: gpr === c, selector;
		xgetbv upper: gpr === d, lower: gpr === a, selector;
		mov.d xcr0, lower;
	}

	return (xcr0 & 0x6) == 0x6;
}

avx2_stop_mask :: no_inline (data: *u8) -> u32 {
	digit_lower: u32 = 0x2F2F2F2F;
	digit_upper: u32 = 0x3A3A3A3A;
	underscore: u32 = 0x5F5F5F5F;
	alpha_lower: u32 = 0x40404040;
	alpha_upper: u32 = 0x5B5B5B5B;
	uppercase_mask: u32 = 0xDFDFDFDF;
	mask: u32;
	#asm AVX, AVX2 {
		movd lower_digits:, digit_lower;
		pbroadcastd.y lower_digits, lower_digits;
		movd upper_digits:, digit_upper;
		pbroadcastd.y upper_digits, upper_digits;
		movd underscores:, underscore;
		pbroadcastd.y underscores, underscores;
		movd lower_alpha:, alpha_lower;
		pbroadcastd.y lower_alpha, lower_alpha;
		movd upper_alpha:, alpha_upper;
		pbroadcastd.y upper_alpha, upper_alpha;
		movd case_mask:, uppercase_mask;
		pbroadcastd.y case_mask, case_mask;
		movdqu.y characters:, [data];
		pand.y uppercase:, characters, case_mask;
		pcmpgtb.y alphabetic:, uppercase, lower_alpha;
		pcmpgtb.y upper_alpha, upper_alpha, uppercase;
		pand.y alphabetic, alphabetic, upper_alpha;
		pcmpgtb.y numeric:, characters, lower_digits;
		pcmpgtb.y upper_digits, upper_digits, characters;
		pand.y numeric, numeric, upper_digits;
		pcmpeqb.y underscores, underscores, characters;
		por.y alphabetic, alphabetic, numeric;
		por.y alphabetic, alphabetic, underscores;
		pmovmskb.y mask, alphabetic;
		zeroupper;
	}

	return ~mask;
}

continues_identifier :: (byte: u8) -> bool {
	return (byte >= #char "a" && byte <= #char "z")
		|| (byte >= #char "A" && byte <= #char "Z")
		|| (byte >= #char "0" && byte <= #char "9")
		|| byte == #char "_";
}

scalar_stop_mask :: () -> u32 {
	expected_mask: u32;
	BIT : u32 : 1;
	for 0..31 {
		if !continues_identifier(SOURCE[it]) {
			expected_mask |= BIT << it;
		}
	}

	return expected_mask;
}

Scan_Result :: struct {
	mask: u32;
	length: s64;
}

scan_identifier :: () -> Scan_Result {
	mask: u64 = avx2_stop_mask(SOURCE.data);
	advance := 32;
	if mask {
		#asm {
			bsf advance, mask;
		}
	}

	return .{mask = mask.(u32), length = advance};
}

check_scan :: (label: string, result: Scan_Result, expected_mask: u32) -> bool {
	print(
		"%: mask % (scalar %), identifier length % (expected %)\n",
		label,
		result.mask,
		expected_mask,
		result.length,
		IDENTIFIER.count
	);

	return result.mask == expected_mask && result.length == IDENTIFIER.count;
}

COMPILE_TIME_HAS_AVX2 :: #run has_avx2();
COMPILE_TIME_RESULT :: #run () -> Scan_Result {
	return (ifx COMPILE_TIME_HAS_AVX2 then scan_identifier() else Scan_Result.{});
}();

main :: () {
	if !COMPILE_TIME_HAS_AVX2 || !has_avx2() {
		print("Skipped: AVX2 and OS support for YMM state are required.\n");
		return;
	}

	expected_mask := scalar_stop_mask();
	compile_time_ok := check_scan("#run  ", COMPILE_TIME_RESULT, expected_mask);
	native_ok := check_scan("native", scan_identifier(), expected_mask);
	if !native_ok {
		print("FAIL: Native identifier scan did not match the scalar reference.\n");
	}
	if !compile_time_ok {
		print("FAIL: #run identifier scan did not match the scalar reference.\n");
	}
	if !native_ok || !compile_time_ok {
		exit(1);
	}
}
