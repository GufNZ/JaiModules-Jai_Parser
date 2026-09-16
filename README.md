# Jai_Parser Lexer

This module starts from `Jai_Lexer` and adds current parser-oriented tokenization.

The default import retains the original `Token` and `Lexer` memory layouts:

```jai
#import "Jai_Parser";
```

Lossless source text and trivia are opt-in:

```jai
#import "Jai_Parser"(ENABLE_TRIVIA=true);
```

In this mode, `Token` additionally contains:

- `original_text`: the exact source bytes forming the token.
- `preceding_trivia`: whitespace, comments, and ignored source bytes before the token.
- `trailing_trivia`: remaining trivia on the `END_OF_INPUT` token.

These strings are zero-copy slices of `Lexer.input`.
They remain valid only while that input remains installed in the lexer.
Calling `set_input_from_string` or `set_input_from_file` can invalidate slices from the previous input.

Structured trivia is available through a `for_expansion`:

```jai
for trivia, offset: make_trivia_iterator(token.preceding_trivia) {
	// trivia.kind, trivia.text, trivia.offset
}
```

Trivia kinds are `WHITESPACE`, `LINE_COMMENT`, `BLOCK_COMMENT`, `SHEBANG`, and `IGNORED`.
`IGNORED` represents source bytes deliberately skipped by the lexer outside the other categories, such as NBSP, zero-width space, and bidi formatting controls.
