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
- Materialise the lexer's ring-buffer output into a parser-owned `[..] Parser_Token` array.
- Copy lexer token values into `Parser_Token`. Source text, original token text, and trivia may remain string views into the retained source buffer.
- Give each parser token a stable array index. Use indices rather than next/previous pointers because growing a dynamic array can invalidate pointers to its elements.
- In trivia mode, associate each syntax node with a token span.
- Allocate AST nodes and child arrays from a `Pool` embedded in `Parsed_Source`; release them together with `release_parser_tree`.
- Synchronise recovery at context-specific expression, statement, declaration, and block boundaries, with a progress guard for every recovery loop.
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

An inclusive `end_token` is slightly more direct when asking for the final concrete token. With a half-open span that token is `tokens[one_past_last_token - 1]` for a non-empty span.  If early API prototypes show that this operation dominates and empty spans are not useful, revisit the convention before stabilising the public API.

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
3. Normalise both trees into a comparison representation.
4. Compare node kinds, child ordering, operators, literal values, syntax flags, and relevant locations.
5. Ignore semantic, resolved, export-only, and compiler-generated fields until the corresponding parser phase exists.

For constructs that require file scope, declarations, or typechecking, create a compiler workspace from a temporary build string and inspect `Message_Typechecked` results.

Raw struct memory is not a useful equality test: compiler nodes contain semantic pointers, serials, source ownership, and fields populated after parsing.

## High-Level TODO

### 1. Define Public Contracts

- [x] Define the initial `Parsed_Source` and parse status types.
- [x] Specify the lifetime of token lexemes and trivia views.
- [x] Require callers to provide immutable, long-lived borrowed source; do not provide an owned-copy mode.
- [x] Define complete, incomplete, recovered, and fatal parse statuses.
- [ ] Classify every public `Compiler.Code_*` field as syntactic, semantic, compiler-generated, or export-only.

### 2. Prototype AST Representation

- [x] Prototype trivia metadata with two leaf nodes and two container nodes.
- [x] Test aliases to compiler types when no parser-only data is required.
- [x] Define a parser-owned hierarchy whose common `Parser_Node` base embeds public `Code_Node` fields.
- [x] Verify casts, allocation, size/layout, and generic traversal with parser-owned nodes.
- [x] Verify that child pointers and generic `*Parser_Node` traversal remain type-safe.
- [x] Compare concrete-node extensions, a full parallel hierarchy, and a node-span side table; adopt the parallel hierarchy.
- [x] Store trivia-only half-open token boundaries directly in `Parser_Node`.

### 3. Materialise Tokens

- [x] Define `Parser_Token` containing the lexer token, stable index, and byte span in trivia mode; alias it to `Token` otherwise.
- [x] Drain the lexer ring buffer into `[..] Parser_Token`, including context-sensitive here-string bodies.
- [x] Retain a borrowed source reference for the lifetime of all token string views.
- [x] Preserve `original_text`, preceding trivia, and EOF trailing trivia when enabled.
- [x] Define zero-width synthetic missing tokens separately from immutable source tokens.
- [x] Add neighbour helpers using stable indices.
- [x] Test exact byte-for-byte reconstruction, including comments, ignored Unicode, here strings, and EOF trivia.

### 4. Build Parser Infrastructure

- [x] Add parser cursor, arbitrary lookahead over materialised tokens, checkpoints, and rollback.
- [x] Add progress guards for recovery loops.
- [x] Choose arena or pool ownership for nodes and child arrays.
- [x] Add node-span construction helpers.
- [x] Add structured diagnostics containing source span, expected tokens, and recovery action.
- [x] Define synchronisation points for expressions, statements, declarations, and blocks.

### 5. Build the Differential Test Harness

- [x] Normalise parser nodes and compiler `Code_*` nodes.
- [x] Produce useful structural diffs rather than boolean failures.
- [x] Add helpers for paired source/`#code` fixtures.
- [x] Add workspace-based fixtures for file-level and typechecked constructs.
- [x] Separate syntactic comparisons from future semantic comparisons.
- [x] Add round-trip helpers for trivia-enabled imports.
- [x] For invalid input rejected by the parser, shell out to the compiler, always passing `-x64` for speed, and capture its error messages for comparison.

### 6. Parse Primary Expressions

- [x] Parse identifiers, numbers, strings, and booleans.
- [x] Parse null and context.
- [x] Parse grouped expressions while preserving parenthesisation.
- [x] Parse array, struct, and unary-dot literals.
- [x] Parse placeholders and here strings.
- [x] Compare each currently supported primary form with `compiler_get_nodes`.

### 7. Parse Prefix and Postfix Expressions

- [x] Parse prefix unary operators.
- [x] Parse calls and named arguments.
- [x] Parse array subscripts, member access, and pointer dereference forms.
- [x] Parse casts, expression queries, and type queries.
- [x] Parse expression-level directives.

### 8. Implement Operator Precedence

- [x] Implement a precedence-climbing expression parser.
- [x] Cover every unary, binary, comparison, logical, shift, rotate, and assignment operator.
- [x] Use `../../print_precedences.jai` to derive the compiler's relative precedence classes rather than maintaining an assumed ordering.
- [x] Match compiler precedence with pairwise differential fixtures.
- [x] Test associativity separately by inspecting the nesting of repeated and mixed operators from the same precedence class.
- [x] Cover ambiguous prefix/postfix and parenthesised cases.

### 9. Parse Types and Declarations

- [x] Parse `:`, `::`, `:=`, compound declarations, and multiple declarations.
- [x] Parse pointer, array, view, resizable-array, and procedure types.
- [x] Parse polymorphic variables, restrictions, and `#type` forms.
- [x] Parse notes, declaration flags, scope modifiers, and alignment expressions.

### 10. Parse Statements and Blocks

- [x] Parse imperative and declaration blocks.
- [x] Parse return, while, for, if, ifx, and switch-style case forms.
- [x] Parse defer, using, push-context, and loop-control statements.
- [x] Recover at semicolons, closing delimiters, and statement starts.

### 11. Parse Procedures and Aggregate Types

- [x] Parse procedure headers, arguments, returns, bodies, and procedure flags.
- [x] Parse quick procedures and macros.
- [x] Parse structs, unions, enums, enum flags, and interfaces.
- [x] Parse aggregate parameters, constants, notes, and modifiers.

### 12. Parse Directives

- [x] Inventory every directive represented by public `Code_*` nodes.
- [x] Parse imports, loads, runs, code, insert, modify, bake, and overlay.
- [x] Parse scope, module parameters, context, location, wildcard, and existence directives.
- [x] Add differential or focused fixtures for every source-spelled directive and flag combination, documenting compiler-generated states.

### 13. Parse Complete Files

- [x] Represent the top-level source block and source metadata.
- [x] Continue after multiple syntax errors.
- [x] Produce a stable partial AST for truncated source.
- [x] Parse all files under `how_to` as an initial compatibility corpus.

#### 13.1 Close `how_to` Compatibility Gaps

Baseline measured 2026-09-23: all 84 files parse non-fatally and round-trip, but 80 files recover with 5,631 diagnostics.
Only the first diagnostic in each file should be treated as the likely grammar gap; later diagnostics are often recovery cascades.
The current initiating categories account for the full diagnostic total:

- Block-bodied declaration termination: 41 files, 2,098 diagnostics.
- Pointer, address-of, dereference, and other `*` forms: 9 files, 817 diagnostics.
- Defaulted procedure or aggregate parameter comma ambiguity: 4 files, 702 diagnostics.
- Compile-time `#if`, `#as`, `#placeholder`, and `#asm` forms: 7 files, 660 diagnostics.
- Expression directives `#char`, `#this`, `#filepath`, and `#caller_code`: 5 files, 344 diagnostics.
- Struct member assignment shorthand such as `w = 1`: 1 file, 270 diagnostics.
- `operator` declarations: 2 files, 224 diagnostics.
- Array types in expression/type-valued contexts: 2 files, 182 diagnostics.
- `using` declarations and `using #as` aggregate fields: 4 files, 115 diagnostics.
- A declaration payload inside `#code`: 1 file, 73 diagnostics.
- The `#run,host` modifier: 1 file, 73 diagnostics.
- Iterator expansion syntax such as `for :utf8_iter`: 1 file, 45 diagnostics.
- Default `case;` termination: 2 files, 28 diagnostics.

Implement and validate these gaps in leverage order:

- [x] Fix `statement_requires_semicolon` for normal procedure bodies, block-form quick procedures, expression-form quick procedures, structs, and enums.  Add top-level and nested fixtures followed by an identifier, a directive, and EOF.
- [x] Audit the lexer/parser contract for `*`.  Plain `*` remains an ASCII token for pointer types, address-of, pointer literals, cast types, pointer-valued generic arguments, loop flags, and multiplication; grammar context owns those distinctions.  Only `.*` and `(.*)` use dedicated postfix/prefix dereference tokens.  Focused token fixtures verify each spelling, so no lexer classification change is needed.
- [x] Parse type-valued cast and call arguments through `parse_type_instantiation` where appropriate, including pointer and array forms such as `cast(*u8)` and `New([3] int)`, without regressing multiplication or dereference expressions.  Cast targets and explicit type-only prefixes now parse as type instantiations; ambiguous `*identifier` call arguments remain unary syntax until semantic name resolution can distinguish pointer types from address-of expressions.  Focused and differential fixtures pass, and the corpus improves to 57 recovering files with 3,881 diagnostics.
- [x] Give parameter declarations a delimiter-aware initialiser mode, so a default value stops at the parameter comma instead of becoming a multi-value declaration expression.  Procedure, aggregate, polymorphic, and named-return lists now disable top-level multi-value initialisers while ordinary declarations retain them.  Focused and differential fixtures pass, and the corpus improves to 56 recovering files with 3,323 diagnostics.
- [x] Inventory compiler AST behaviour for `#if`, `#as`, `#placeholder`, and `#asm`; add parser-owned syntax nodes or explicitly documented preservation nodes where no public `Code_*` counterpart exists.  Static `Parser_If` nodes retain imperative or declaration block mode; prefix `#as using` fields set `IS_MARKED_AS_AS`; named `Parser_Placeholder` nodes preserve file declarations; and opaque `Parser_Asm` nodes preserve feature names plus balanced body spans while instruction parsing remains in section 13.2.  Focused and differential fixtures pass, `using #as` remains assigned to the later `using` checkbox, and the corpus improves to 52 recovering files with 2,201 diagnostics.
- [x] Add expression-directive parsing and compiler comparisons for `#char`, `#this`, `#filepath`, and `#caller_code`, including their legal constant/default-argument contexts.  These preserve the compiler's lowered shapes: numeric and path string literals, payload-free `DIRECTIVE_THIS`, and `DIRECTIVE_CODE` with the unnamed caller-code flag.  Focused and differential fixtures cover constants and default arguments, and the corpus improves to 51 recovering files with 2,065 diagnostics.
- [x] Parse aggregate member assignment shorthand such as `w = 1` and retain its relationship to the previously declared field.  Aggregate bodies now preserve these as ordered binary-expression statements and link a matching left identifier to its earlier parser-owned declaration.  Focused and differential fixtures pass, and the corpus improves to 51 recovering files with 2,055 diagnostics.
- [x] Parse `operator` declarations, including unary/binary signatures, compound declarations, procedure flags, and bodies; add differential fixtures for operator names and argument forms.  Operator punctuation is retained as the compiler-compatible declaration name, including compound assignments and `[]`, `[]=`, or `*[]`, while signatures, flags, and bodies reuse ordinary procedure parsing.  Focused and differential fixtures cover all 39 overloadable lexer spellings, excluding only the prohibited `=` and `.` declarations.  Both operator tutorial files parse completely, and the corpus improves to 49 recovering files with 1,752 diagnostics.
- [x] Parse `using` declarations and `using #as` and `#as using` aggregate fields without routing them through ordinary expression recovery.  Declaration contexts now preserve `Parser_Using` around the wrapped struct declaration; both `#as` orders set `IS_MARKED_AS_AS` for implicit casting.  Focused and differential fixtures pass, and the corpus improves to 44 recovering files with 1,630 diagnostics.
- [x] Allow declaration payloads in `#code` and preserve whether the payload was an expression, declaration, or block.  Payload dispatch now uses declaration lookahead between the existing block and expression paths, retaining ordinary declaration names, types, initialisers, and flags.  Focused and differential fixtures pass, and the corpus improves to 43 recovering files with 1,581 diagnostics.
- [x] Parse source-spelled `#run` modifiers, beginning with `#run,host`, and compare their textual flags with compiler nodes.  `stallable` retains its public flag, `host` retains the compiler's unnamed `0x10` flag, and payload classification now occurs after modifier consumption, so block runs omit `HAS_IMPLICIT_RETURN_TYPES`.  Focused and differential fixtures pass; corpus recovery remains 43 files with 1,581 diagnostics.
- [x] Parse named iterator expansions such as `for :utf8_iter expression`, including combinations with index/value names and existing pointer/reverse modifiers.  Selectors are retained in `want_replacement_for_expansion`; spaced and adjacent `< *`/`<*` set independent literal flags.  Focused and compiler-differential fixtures pass, and the corpus remains at 43 recovering files while diagnostics fall from 1,581 to 1,466 (`730_for_expansions.jai` falls from 125 to 16).
- [x] Allow a default `case;` arm to terminate at the enclosing `}` without synthesising another `case`; cover both runtime and static `#if` switch-style case blocks.  The case loop now refreshes its existing lookahead instead of shadowing it, and focused plus compiler-differential fixtures pass.  The corpus improves from 43 recovering files with 1,466 diagnostics to 38 files with 1,445 diagnostics (`027_if_case.jai` falls from 17 to 9).

Keep recovery measurements separate from grammar support:

- [x] Extend the corpus report with aggregates by diagnostic kind, expected/actual token, recovery action, and first diagnostic per file.  The report now includes structured per-file status, diagnostic count, kind, expected/actual token, recovery action, and message fields; ASCII-backed token values use quoted source spellings and absent fields use `<none>`.  The 84-file corpus report runs successfully at the current baseline of 38 recovering files with 1,445 diagnostics.
- [x] After each grammar fix, record both newly complete files and removed diagnostics; use the first diagnostic per file to select the next fix rather than optimising the largest secondary skip-token count.  The corpus harness compares runs with a checked-in relative-path baseline, reports newly complete/recovering and improved/regressed files, and counts removed and added diagnostics independently.  Its next-candidate summary groups only one first-diagnostic signature per recovering file; at the current 38-file/1,445-diagnostic baseline it selects the 11-file expected-`;`/actual-identifier signature rather than the 676 semicolon skip-token cascade.
- [x] Once the initiating gaps are handled, tighten expression, statement, and declaration synchronisation so one local failure does not reinterpret a procedure body as top-level declarations.  Synchronisation now tracks nested parentheses, brackets, and braces, ignores internal separators, and returns after a recovered braced region instead of restarting on its contents.  Focused expression, procedure-body, and file-declaration ownership fixtures pass; differential fixtures remain clean.  No files regress, and recovery cascades fall by 1,064 diagnostics from 1,445 to 381 across the same 38 files.
- [x] Add focused malformed and truncated variants for every new construct before changing synchronisation behaviour, preserving stable partial trees and forward progress.  The runtime suite now covers truncated block-bodied declarations, pointer/type forms, casts, parameter defaults, `#if`/`#as`/`#placeholder`/`#asm`, expression directives, aggregate assignments, operators, `using`, `#code`, `#run`, `#insert`, named iterator expansions, and default cases.  Assertions retain outer nodes and syntax flags, verify stable child arrays and diagnostics, and preserve following declarations across recovery.
- [ ] Consider this compatibility backlog complete when all valid `how_to` files return `COMPLETE` with zero diagnostics, retain exact trivia round-trips, and pass focused or differential fixtures for every category above.

Audit follow-ups (2026-09-25; corpus baseline: 84 files, 38 recovering, 381 diagnostics):

- [ ] Fix `next_trivia` so ignored NBSP bytes produce `IGNORED` trivia without asserting; run the full `layout_test` executable.
- [ ] Diagnose and fix the compiler diagnostic-location assertion in the runtime `differential_test` executable; require both compile-time AST fixtures and runtime checks to pass.
- [ ] Surface lexer errors as structured diagnostics in `Parsed_Source`, or explicitly handle `RECOVERED` results with no diagnostics in the corpus harness; add malformed-input coverage for that case.
- [ ] Investigate `DOUBLE_COMMA` recovery in `how_to/200_memory_management.jai` and `how_to/225_comma_comma.jai`; add grammar and differential fixtures once the compiler-accepted forms are identified.
- [ ] Parse and compare advanced `using,except` and `using,only` forms, including fixtures from `how_to/044_using_advanced/main.jai`.
- [ ] Triage the remaining recovering `how_to` files by first diagnostic, record their unsupported source forms as separate tasks, and track zero-diagnostic progress independently of recovery-cascade counts.
- [ ] Reconcile the section 13.3 checkboxes with implemented named selectors and combined literal `<`/`*` flags; keep controlled `<=`/`*=` flags and missing fixture combinations unchecked.
- [ ] Update historical baseline wording and the README assembly description to distinguish current instruction envelopes from unparsed operand internals; qualify past differential-suite claims until its runtime checks pass.
- [ ] Audit the section 13.1 malformed-variant claim against the actual fixtures and add missing malformed cases or narrow the claim to tested truncations.

#### 13.2 Parse Inline `#asm`

`how_to/900_inline_assembly.jai` defines a context-specific assembly grammar rather than an ordinary imperative block.  The public compiler API exposes `Code_Asm`, but deliberately keeps its three payload fields opaque; compiler comparison can therefore verify the `.ASM` envelope, location, and surrounding tree placement, but not reinterpret the opaque payload.  Preserve the source-spelled structure in parser-owned nodes and leave instruction selection, register allocation, feature validation, and machine encoding to later semantic work.

Define the representation and lexer contract first:

- [x] Add `Parser_Asm` as the parser-owned counterpart to `Code_Asm`, with parser-owned feature names and assembly statements rather than overlays for the compiler's opaque `b1`, `b2`, and `b3` fields.  The generated parser node now appends ordered `Parser_Asm_Statement` token-span envelopes after the full concrete `Code_Asm` storage, alongside feature names and the complete body span.  Top-level semicolons delimit statements, nested braces stay within one span, and truncated trailing statements are retained for recovery; mnemonic and operand structure remains deferred to the next checkbox.
- [x] Define parser-owned assembly statement and operand nodes for instructions, register declarations, register pinning, memory operands, and source-spelled operand modifiers.  Statements and operands use explicit source-role kinds; values and every nested record retain token spans; mnemonic and register-class fields are open-ended `Parser_Ident` nodes rather than x86 enums.  Existing assembly scans produce `UNPARSED` statement envelopes until the grammar is implemented.
- [x] Audit tokenisation, spans, and exact trivia round-tripping for `#asm`, `===`, mnemonic dots, `?`, `!`, `&`, `&*`, brackets, inferred declarations ending in `:`, signed immediates, and comments.  Focused trivia-enabled fixtures verify contiguous source slices and byte-for-byte reconstruction.  The existing stream is lossless: `===` is atomic, fixed mnemonic suffixes such as `.8` are leading-dot `NUMBER` tokens, signs remain separate from numeric tokens, and modifier punctuation remains ordinary tokens, so no lexer change is required.
- [x] Decide whether mnemonic suffixes are assembled from ordinary tokens or materialised as contextual assembly tokens.  Assembly parsing will consume the ordinary stream: fixed sizes such as `mov.8` and `mov.64` use the existing leading-dot `NUMBER`, while `popcnt?BITS` and `popcnt?T` use `?` followed by `IDENT`.  Focused fixtures verify these spellings and unchanged `object.member` and `value?T` tokenisation outside `#asm`; no contextual token kinds are added.

Parse the block header and its scope behaviour:

- [x] Parse `#asm { ... }` and optional comma-separated per-block feature names such as `#asm AVX, AVX2 { ... }`, preserving their order and token spans.  `Parser_Asm.features` contains ordered pool-owned `Parser_Asm_Feature` records with a fully formed `Parser_Ident` and explicit `Token_Span`; bare assembly blocks retain an empty list and an empty body span.
- [x] Represent an assembly block as belonging to the enclosing high-level scope rather than introducing a new lexical scope.  `Parser_Asm.enclosing_scope` records the surrounding `Parser_Block`; sibling blocks share that owner, while assembly nested inside a real high-level block receives the nested owner.  Statement spans preserve declarations and later uses across blocks, but no syntax-phase binding or assembly-local scope is created.
- [x] Support `#asm` wherever a statement is legal, including blocks selected directly by compile-time control flow such as `#if BITS == 8 #asm { ... } else #asm { ... }`.  Existing generic single-statement branch dispatch already accepts assembly nodes; focused coverage verifies both branches, statement spans, static-if flags, and ownership by the surrounding real scope rather than the synthetic branch wrappers.

Parse assembly statements and operands:

- [x] Parse instruction statements as a mnemonic, optional fixed or polymorphic size, comma-separated operands, and a required semicolon.  Identifier-led statements now produce `Parser_Asm_Instruction` with an open-ended mnemonic, optional `Parser_Asm_Mnemonic_Size` (`FIXED` token span or `POLYMORPHIC` identifier), and ordered operand envelopes split at top-level commas while respecting nested delimiters.  Operand internals remain `UNPARSED` for the following checkboxes, and nonterminated trailing instructions produce an expected-`;` diagnostic without escaping the assembly block.
- [ ] Parse inferred register operands such as `apple:` and explicit register declarations such as `banana: gpr`, both as standalone statements and inline instruction operands such as `mov w: gpr === 15, 10`.
- [ ] Parse register pinning with `===`, including declaration pinning (`t: gpr === a`, `v: vec === 9`) and existing-value pinning (`x === a`).
- [ ] Parse signed integer and floating-point immediates without imposing instruction-specific width or range rules in the syntax phase.
- [ ] Parse memory operands using brackets and preserve their rigid source structure: required base, optional index and scale, optional signed displacement, and parenthesised high-level constant expressions.  Cover forms from `[b]` through `[base + index*8 - 10]` and vector-index forms used by gathers.
- [ ] Parse memory broadcast suffix `!`, SAE and explicit rounding suffixes `!`, `!n`, `!d`, `!u`, and `!z`, plus mask merge/zero forms `& mask` and `&* mask`.
- [ ] Allow high-level identifiers, constants, types, macro parameters of `__reg`, and parenthesised high-level expressions where the assembly grammar permits them, while retaining enough node distinction for later binding.

Validate syntax separately from machine semantics:

- [ ] Add focused fixtures for every source form in `how_to/900_inline_assembly.jai`, including feature headers, macros receiving registers, compile-time execution, VSIB addressing, EVEX broadcast/rounding/masking, and polymorphic mnemonic sizes.
- [ ] Compare valid fixtures with the compiler for node kind, source location, and enclosing-tree placement.  Document that `Code_Asm` payload equality is impossible while its public fields remain opaque.
- [ ] Compile valid and intentionally invalid assembly fixtures with the Jai compiler to capture semantic diagnostics, but do not duplicate mnemonic lookup, operand-form matching, immediate ranges, feature gates, register allocation, or encoding in the parser.
- [ ] Recover malformed assembly at the next semicolon or closing `}` without handing instruction operands to the high-level statement parser.  Add missing-semicolon, missing-comma, malformed memory operand, malformed modifier, and truncated-block tests with stable partial assembly nodes.
- [ ] Require `how_to/900_inline_assembly.jai` to parse as `COMPLETE` with zero diagnostics and round-trip byte-for-byte before marking inline assembly parsing complete.

#### 13.3 Parse For-Expansion Syntax

`how_to/730_for_expansions.jai` uses the normal `Code_For` node with additional source-level controls.  The public AST already exposes `want_replacement_for_expansion`, `want_pointer_expression`, `want_reverse_expression`, and `for_flags`; parse those fields now, but defer lookup and execution of the expansion macro until semantic analysis.  `macro_expansion_procedure_call`, `ident_decl`, and `index_decl` are typechecked/generated fields and must remain unset during syntax parsing.

Parse the complete `for` prefix grammar:

- [ ] Parse an optional named expansion selector immediately after `for`, as in `for :positive_vibes_only value, index: holder`, and store its expression in `want_replacement_for_expansion`.  Preserve the absence of a selector so semantic lookup can use the conventional `for_expansion` name.
- [ ] Parse literal reverse and pointer flags independently and in combination: `for < value`, `for * value`, `for < * value`, and `for <* value`.  Set `.REVERSE` and `.POINTER` in `for_flags`; do not use mutually exclusive parsing for the two flags.
- [ ] Allow a named selector after literal flags, as in `for < :polite dummy`, and define one canonical parse order while accepting the spaced and adjacent forms shown in the guide.
- [ ] Parse controlled flags `<=expression` and `*=expression` into `want_reverse_expression` and `want_pointer_expression`.  Support either flag alone and both together, including the comma-disambiguated form `for *=pointer_expression, <=reverse_expression collection`.
- [ ] Define where a controlled-flag expression stops without consuming the iteration expression.  Use the separating comma when both controlled flags are present and add targeted ambiguity tests for comparison and assignment operators.
- [ ] Reject or recover duplicate literal/controlled forms of the same flag deterministically, while preserving all source tokens for round-tripping.

Preserve iterator bindings and loop shape:

- [ ] Parse implicit `it`/`it_index`, a renamed value (`for value: collection`), and renamed value/index pairs (`for value, index: collection`) with the selected expansion syntax.
- [ ] Preserve iterator identifiers marked with Jai's backtick syntax, as in the source form `` for `it, `it_index: collection ``, by setting their source-spelled identifier flags, so expansion macros can deliberately export the bindings to their caller.
- [ ] Retain existing range-loop parsing separately from for-expansion selection, including `iteration_expression_right`, and add ambiguity fixtures proving that selector/flag syntax does not consume range operators or the loop body.
- [ ] Parse both single-statement and braced bodies for all selector and flag combinations, retaining parent/owning-statement links and exact token spans.

Preserve syntax used inside expansion procedures:

- [ ] Differentially verify the `for_expansion :: (value, body: Code, flags: For_Flags) #expand` declaration shape, including value and pointer receiver forms.  Treat the conventional procedure name and signature as ordinary declarations during syntax parsing.
- [ ] Preserve declarations exported with Jai's backtick syntax, including `` `it ``, `` `it_index ``, and additional user-defined names such as `` `visited_index ``.
- [ ] Complete `#insert` replacement parsing for `#insert(break=statement, continue=statement, remove=statement) body`, populating `break_replacement`, `continue_replacement`, and `remove_replacement`.  Cover targeted loop controls such as `break y` and explicit rejection replacements such as `#assert(false)`.
- [ ] Verify that a plain `#insert body` remains distinct from replacement-bearing insertion and that inserted expansion output remains a semantic/generated field rather than syntax-owned AST.

Validate and recover at the syntax layer:

- [ ] Add focused and compiler-differential fixtures for every loop spelling in `how_to/730_for_expansions.jai`: default and named selectors; renamed iterators; `<`, `*`, `< *`, and `<*`; controlled `<=` and `*=` flags; combined controlled flags; and backticked iterator bindings.
- [ ] Compare parser fields with raw compiler `Code_For` nodes before typechecking.  Exclude `ident_decl`, `index_decl`, and `macro_expansion_procedure_call` until semantic expansion is implemented.
- [ ] Add malformed fixtures for a missing selector, missing controlled-flag expression, duplicate flags, missing comma between controlled flags, missing iterator after a comma, missing binding colon, and truncated body.
- [ ] Synchronise malformed prefixes at the iteration expression or loop body without reinterpreting the body as top-level declarations, and keep partial `Parser_For` nodes stable.
- [ ] Require `how_to/730_for_expansions.jai` to parse as `COMPLETE` with zero diagnostics and round-trip byte-for-byte before marking for-expansion syntax complete.

Implement expansion semantics later:

- [ ] During name resolution, resolve the default `for_expansion` or selected expansion procedure using the iteration value's pointer form and Jai's auto-dereference rules.
- [ ] Evaluate controlled pointer/reverse expressions as compile-time booleans, combine them with literal `for_flags`, and provide the resulting `For_Flags` value to the expansion macro.
- [ ] Expand the loop body as `Code`, remap exported `it` and `it_index` to the source-spelled iterator names, retain additional exported names, and populate `macro_expansion_procedure_call` plus generated declaration fields.
- [ ] Apply `#insert` break/continue/remove replacements to loop-control nodes in the inserted body, preserving labelled targets such as `break y`; report unsupported controls when the expansion deliberately substitutes a compile-time assertion.
- [ ] Add semantic fixtures using value and pointer receivers, nested-loop break replacement, extra exported variables, and the real `Unicode.utf8_iter`, `Bit_Array`, `Hash_Table`, and `Bucket_Array` expansions.

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
2. Materialise tokens with stable indices and byte spans.
3. Prove exact round-tripping in trivia mode.
4. Parse identifiers and literals.
5. Add prefix, postfix, and binary expression parsing.
6. Compare those expression trees against `compiler_get_nodes` fixtures.
