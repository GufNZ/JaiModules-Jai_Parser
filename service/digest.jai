// R14 content digest: Meow Hash 0.5 (128-bit, default seed).
// It indexes and detects accidental corruption only; exact bytes and descriptors remain the equality authority.

#assert CPU == .X64 "The meow_hash content digest uses x64 AES instructions; another platform needs a separately registered digest.";

DIGEST_SCHEMA :: "jai-cache-digest-meow128/1";

Digest_128 :: struct {
	bytes: [16] u8;
}

operator == :: (a: Digest_128, b: Digest_128) -> bool {
	return memcmp(a.bytes.data, b.bytes.data, a.bytes.count) == 0;
}

Digest_State :: struct {
	meow: meow_state;
}

// Meow reads from the source pointer even for empty input, so empty views use this buffer.
#scope_file
empty_input: [1] u8;
#scope_export

digest_from_register :: (low: u64, high: u64) -> Digest_128 {
	result: Digest_128;
	for 0..7 {
		result.bytes[it] = xx ((low >> (8 * it)) & 0xFF);
		result.bytes[8 + it] = xx ((high >> (8 * it)) & 0xFF);
	}

	return result;
}

digest_128 :: (bytes: [] u8) -> Digest_128 {
	source := ifx bytes.count
		then bytes.data
		else empty_input.data;

	#asm { hash: vec; }
	MeowHash(MeowDefaultSeed, xx bytes.count, source, hash);
	return digest_from_register(MeowU64From(hash, 0), MeowU64From(hash, 1));
}

digest_begin :: (state: *Digest_State) {
	MeowBegin(*state.meow, MeowDefaultSeed);
}

digest_absorb :: (state: *Digest_State, bytes: [] u8) {
	if bytes.count {
		MeowAbsorb(*state.meow, xx bytes.count, bytes.data);
	}
}

digest_end :: (state: *Digest_State) -> Digest_128 {
	#asm { hash: vec; }
	MeowEnd(*state.meow, hash);
	return digest_from_register(MeowU64From(hash, 0), MeowU64From(hash, 1));
}
