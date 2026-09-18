# Jai Parser Plan

## Goal

Build a parser for Jai source that:

- Produces a syntax tree equivalent to the compiler's user-visible `Code_*` AST where practical.
- Preserves enough information to reproduce the input byte-for-byte when `ENABLE_TRIVIA` is enabled.
- Can eventually perform semantic analysis comparable to the compiler.
- Can recover from and resume parsing incomplete source for editor use.

The first milestone is expression parsing, followed by declarations and complete files.

## Current Design Decisions

- Expose parser-owned names such as `Parser_Node` and `Parser_If`, keeping them distinct from `Compiler.Code_Node` and `Compiler.Code_If` for now.
- Materialize the lexer's ring-buffer output into a parser-owned `[..] Parser_Token` array.
- Copy lexer token values into `Parser_Token`. Source text, original token text, and trivia may remain string views into the retained source buffer.
- Give each parser token a stable array index. Use indices rather than next/previous pointers because growing a dynamic array can invalidate pointers to its elements.
- In trivia mode, associate each syntax node with a token span.
- Initially match syntactic AST information. Add name resolution, types, overload resolution, constant evaluation, and compiler-generated nodes in later semantic phases.

## Token Spans

Use half-open spans:

```text
[first_token, one_past_last_token)
```

For example, a three-token expression beginning at token 5 has the span `[5, 8)`.

Reasons to prefer this over an inclusive end-token index:

- The token count is `one_past_last_token - first_token`, including for empty spans.
- Adjacent spans meet exactly: `[a, b)` followed by `[b, c)`.
- Slicing maps directly to `tokens[first_token..one_past_last_token]` conceptually, without adding one to an inclusive end.
- Empty or missing constructs can be represented at a cursor as `[n, n)`.
- Extending a parent over a child usually means copying the child's one-past-end boundary.
- EOF and insertion points are natural boundaries, rather than requiring a special token to be considered included.

An inclusive `end_token` is slightly more direct when asking for the final concrete token. With a half-open span that token is `tokens[one_past_last_token - 1]` for a non-empty span.  If early API prototypes show that this operation dominates and empty spans are not useful, revisit the convention before stabilizing the public API.

Token records should also contain absolute byte offsets. Exact source reconstruction should use byte boundaries in the retained source, while token spans support syntax navigation and edits.

## Compiler Comparison Strategy

`compiler_get_nodes` accepts a compile-time `Code` value rather than an arbitrary runtime source string.  Differential fixtures should therefore pair source text with equivalent code:

```jai
SOURCE :: "a + b * c";
EXPECTED_CODE :: #code a + b * c;
```

For each fixture:

1. Parse `SOURCE` with this module.
2. Obtain the compiler tree with `compiler_get_nodes(EXPECTED_CODE)`.
3. Normalize both trees into a comparison representation.
4. Compare node kinds, child ordering, operators, literal values, syntax flags, and relevant locations.
5. Ignore semantic, resolved, export-only, and compiler-generated fields until the corresponding parser phase exists.

For constructs that require file scope, declarations, or typechecking, create a compiler workspace from a temporary build string and inspect `Message_Typechecked` results.

Raw struct memory is not a useful equality test: compiler nodes contain semantic pointers, serials, source ownership, and fields populated after parsing.

## High-Level TODO

### 1. Define Public Contracts

- [ ] Define `Parsed_Source`, parse results, diagnostics, and source ownership.
- [ ] Specify the lifetime of token lexemes and trivia views.
- [ ] Decide whether callers may provide immutable borrowed source or request an owned copy.
- [ ] Define complete, incomplete, recovered, and fatal parse statuses.
- [ ] Classify every public `Compiler.Code_*` field as syntactic, semantic, compiler-generated, or export-only.

### 2. Prototype AST Representation

- [ ] Prototype `Parser_Node`, two leaf nodes, and two container nodes.
- [ ] Test aliases to compiler types when no parser-only data is required.
- [ ] Test extended parser structs when `ENABLE_TRIVIA` is enabled.
- [ ] Verify `#as using`, casts, allocation, size/layout, and generic traversal.
- [ ] Verify that child pointers and generic `*Parser_Node` traversal remain type-safe.
- [ ] Compare concrete-node extensions, a full parallel hierarchy, and a node-span side table.
- [ ] Freeze the representation only after a compile-time layout and traversal test passes.

### 3. Materialize Tokens

- [ ] Define `Parser_Token` containing the lexer token, stable index, and byte span.
- [ ] Drain the lexer ring buffer into `[..] Parser_Token`.
- [ ] Retain the source buffer for the lifetime of all token string views.
- [ ] Preserve `original_text`, preceding trivia, and EOF trailing trivia when enabled.
- [ ] Define synthetic and missing tokens for error recovery.
- [ ] Add neighbour helpers using stable indices.
- [ ] Test exact byte-for-byte reconstruction, including comments, ignored Unicode, here strings, and EOF trivia.

### 4. Build Parser Infrastructure

- [ ] Add parser cursor, arbitrary lookahead over materialized tokens, checkpoints, rollback, and progress guards.
- [ ] Choose arena or pool ownership for nodes and child arrays.
- [ ] Add node-span construction helpers.
- [ ] Add structured diagnostics containing source span, expected tokens, and recovery action.
- [ ] Define synchronization points for expressions, statements, declarations, and blocks.

### 5. Build the Differential Test Harness

- [ ] Normalize parser nodes and compiler `Code_*` nodes.
- [ ] Produce useful structural diffs rather than boolean failures.
- [ ] Add helpers for paired source/`#code` fixtures.
- [ ] Add workspace-based fixtures for file-level and typechecked constructs.
- [ ] Separate syntactic comparisons from future semantic comparisons.
- [ ] Add round-trip helpers for trivia-enabled imports.

### 6. Parse Primary Expressions

- [ ] Parse identifiers, numbers, strings, booleans, null, and context.
- [ ] Parse grouped expressions while preserving parenthesisation.
- [ ] Parse array, struct, and unary-dot literals.
- [ ] Parse placeholders and here strings.
- [ ] Compare each form with `compiler_get_nodes`.

### 7. Parse Prefix and Postfix Expressions

- [ ] Parse unary operators.
- [ ] Parse calls and named arguments.
- [ ] Parse array subscripts, member access, and pointer dereference forms.
- [ ] Parse casts, expression queries, and type queries.
- [ ] Parse expression-level directives.

### 8. Implement Operator Precedence

- [ ] Implement a Pratt or precedence-climbing expression parser.
- [ ] Cover every unary, binary, comparison, logical, shift, rotate, and assignment operator.
- [ ] Match compiler precedence and associativity with differential fixtures.
- [ ] Cover ambiguous prefix/postfix and parenthesized cases.

### 9. Parse Types and Declarations

- [ ] Parse `:`, `::`, `:=`, compound declarations, and multiple declarations.
- [ ] Parse pointer, array, view, resizable-array, and procedure types.
- [ ] Parse polymorphic variables, restrictions, and `#type` forms.
- [ ] Parse notes, declaration flags, scope modifiers, and alignment expressions.

### 10. Parse Statements and Blocks

- [ ] Parse imperative and declaration blocks.
- [ ] Parse return, while, for, if, ifx, and switch-style case forms.
- [ ] Parse defer, using, push-context, and loop-control statements.
- [ ] Recover at semicolons, closing delimiters, and statement starts.

### 11. Parse Procedures and Aggregate Types

- [ ] Parse procedure headers, arguments, returns, bodies, and procedure flags.
- [ ] Parse quick procedures and macros.
- [ ] Parse structs, unions, enums, enum flags, and interfaces.
- [ ] Parse aggregate parameters, constants, notes, and modifiers.

### 12. Parse Directives

- [ ] Inventory every directive represented by public `Code_*` nodes.
- [ ] Parse imports, loads, runs, code, insert, modify, bake, and overlay.
- [ ] Parse scope, module parameters, context, location, wildcard, and existence directives.
- [ ] Add a differential fixture for each directive and flag combination.

### 13. Parse Complete Files

- [ ] Represent the top-level source block and source metadata.
- [ ] Continue after multiple syntax errors.
- [ ] Produce a stable partial AST for truncated source.
- [ ] Parse all files under `how_to` as an initial compatibility corpus.

### 14. Add Semantic Analysis

- [ ] Build lexical scopes and bind declarations.
- [ ] Resolve identifiers and imports.
- [ ] Instantiate and infer types.
- [ ] Evaluate constants required by language semantics.
- [ ] Resolve overloads and polymorphs.
- [ ] Model desugaring and compiler-generated nodes where observable.
- [ ] Compare semantic output with typechecked compiler workspace messages.

### 15. Support Incremental and Resumable Parsing

- [ ] Define explicit missing/error nodes or equivalent recovery records.
- [ ] Record restart points at declarations and blocks.
- [ ] Re-lex only the affected source region where possible.
- [ ] Reuse unchanged token and AST regions after edits.
- [ ] Keep diagnostics deterministic while source is incomplete.

### 16. Harden and Measure

- [ ] Parse the `how_to`, `examples`, and `modules` trees.
- [ ] Round-trip every supported file with trivia enabled.
- [ ] Track unsupported constructs explicitly.
- [ ] Fuzz malformed and truncated source.
- [ ] Measure parse time, allocations, retained source size, and incremental update cost.

## First Implementation Slice

1. Complete the public-contract and AST-layout prototypes.
2. Materialize tokens with stable indices and byte spans.
3. Prove exact round-tripping in trivia mode.
4. Parse identifiers and literals.
5. Add prefix, postfix, and binary expression parsing.
6. Compare those expression trees against `compiler_get_nodes` fixtures.
