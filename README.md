# Jai_Parser Lexer

This module starts from `Jai_Lexer` and adds current parser-oriented tokenization, including `(.*)` as `PREFIX_DEREFERENCE`. `<<` remains `SHIFT_LEFT`.

The default import retains the original `Token` and `Lexer` memory layouts:

```jai
#import "Jai_Parser";
```

Lossless source text and trivia are opt-in:

```jai
Lexer_With_Trivia :: #import "Jai_Parser"(ENABLE_TRIVIA=true);
```

In this mode, `Token` additionally contains:

- `original_text`: the exact source bytes forming the token.
- `preceding_trivia`: whitespace, comments, and ignored source bytes before the token.
- `trailing_trivia`: remaining trivia on the `END_OF_INPUT` token.

These strings are zero-copy slices of `Lexer.input`. They remain valid only while that input remains installed in the lexer. Calling `set_input_from_string` or `set_input_from_file` can invalidate slices from the previous input.
