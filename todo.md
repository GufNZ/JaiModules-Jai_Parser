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
The counts in this section are historical snapshots, not the current corpus result or the checked-in comparison baseline.
Earlier claims that differential fixtures passed establish compile-time AST and workspace checks; the executable's runtime assertions were confirmed only after the diagnostic-location fixture correction in the audit follow-ups below.
Only the first diagnostic in each file should be treated as the likely grammar gap; later diagnostics are often recovery cascades.
At that snapshot, the initiating categories accounted for the full diagnostic total:

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

- [x] Extend the corpus report with aggregates by diagnostic kind, expected/actual token, recovery action, and first diagnostic per file.  The report now includes structured per-file status, diagnostic count, kind, expected/actual token, recovery action, and message fields; ASCII-backed token values use quoted source spellings and absent fields use `<none>`.  At this checkpoint the 84-file corpus report had 38 recovering files with 1,445 diagnostics.
- [x] After each grammar fix, record both newly complete files and removed diagnostics; use the first diagnostic per file to select the next fix rather than optimising the largest secondary skip-token count.  The corpus harness compares runs with a checked-in relative-path baseline, reports newly complete/recovering and improved/regressed files, and counts removed and added diagnostics independently.  Its next-candidate summary groups only one first-diagnostic signature per recovering file; at the 38-file/1,445-diagnostic checkpoint it selected the 11-file expected-`;`/actual-identifier signature rather than the 676 semicolon skip-token cascade.
- [x] Once the initiating gaps are handled, tighten expression, statement, and declaration synchronisation so one local failure does not reinterpret a procedure body as top-level declarations.  Synchronisation now tracks nested parentheses, brackets, and braces, ignores internal separators, and returns after a recovered braced region instead of restarting on its contents.  Focused expression, procedure-body, and file-declaration ownership fixtures pass; compile-time differential fixtures remain clean (runtime assertions were confirmed later).  No files regress, and recovery cascades fall by 1,064 diagnostics from 1,445 to 381 across the same 38 files.
- [x] Add focused recovery fixtures for representative section 13.1 constructs before changing synchronisation behaviour.  The runtime suite checks selected truncations of block-bodied declarations, pointer/type forms, casts, parameter defaults, `#if`/`#as`/`#placeholder`/`#asm`, aggregate assignments, operators, `using`, `#code`, `#run`, `#insert`, named iterator expansions, and default cases; it also checks a truncated `#char` and malformed trailing text after `#this`, `#filepath`, and `#caller_code`.  These fixtures assert nonfatal partial trees and selected flags, child counts, or diagnostics; separate synchronisation fixtures verify following declarations.  They do not cover every malformed variant of each construct.
- [x] Consider this compatibility backlog complete when all valid `how_to` files return `COMPLETE` with zero diagnostics, retain exact trivia round-trips, and pass focused or differential fixtures for every category above.

Audit follow-ups (2026-09-25; starting corpus snapshot: 84 files, 38 recovering, 381 diagnostics):

- [x] Fix `next_trivia` so ignored NBSP bytes produce `IGNORED` trivia without asserting; run the full `layout_test` executable.
- [x] Diagnose and fix the compiler diagnostic-location assertion in the runtime `differential_test` executable; require both compile-time AST fixtures and runtime checks to pass.  The locations were correct; only the compiler-output fixture expectations needed updating for the compiler's current message spacing.  Captured messages remain unchanged.
- [x] Surface lexer errors as structured diagnostics in `Parsed_Source`, or explicitly handle `RECOVERED` results with no diagnostics in the corpus harness; add malformed-input coverage for that case.  The corpus harness retains lexer-only recovery as a separate zero-diagnostic entry, excludes it from parser grammar candidates, and tests the report path; an overlong-identifier fixture proves the actual parser status and round-trip behaviour.
- [x] Investigate `DOUBLE_COMMA` recovery in `how_to/200_memory_management.jai` and `how_to/225_comma_comma.jai`; add grammar and differential fixtures once the compiler-accepted forms are identified.  Call context replacements now use parser-owned `context_modification` expressions, with focused named, shorthand, context-only, and malformed fixtures plus compiler AST comparisons.  `225_comma_comma.jai` is complete; `200_memory_management.jai` falls from 11 to 4 unrelated diagnostics.  Corpus recovery improves from 38 files/381 diagnostics to 37 files/357 diagnostics without regressions.
- [x] Parse and compare advanced `using,except` and `using,only` forms, including fixtures from `how_to/044_using_advanced/main.jai`.  Named lists lower to compiler-shaped string arrays; array literals, identifiers, and `#run` filters retain their expression trees.  Focused and differential fixtures cover aggregate fields, statements, named imports, and filtered procedure parameters.  Corpus recovery stays at 37 files, with diagnostics falling from 357 to 294 and no regressions against the checked-in baseline; the advanced-using guide falls from 74 to 7 diagnostics, beginning at an unrelated `#run -> [] string` form.  Unsupported `using,map` is now diagnosed rather than silently consumed.
- [x] Triage the remaining recovering `how_to` files by first diagnostic, record their unsupported source forms as separate tasks, and track zero-diagnostic progress independently of recovery-cascade counts.  The corpus report now includes the first source line and a separate zero-diagnostic count: 47/84 files (up from 46/84 at baseline) complete with zero diagnostics, 37 recover with 294 diagnostics, and none recover without a parser diagnostic.  The first-error backlog below covers all 37 recovering files; these are leads, not claims that every later diagnostic shares the same cause.

First-error backlog (2026-09-25; each task needs focused and compiler comparisons where the source is valid):

- [x] Reconcile semicolon insertion after `#string` declarations and multiline string boundaries: `005_strings.jai`, `018_print_functions.jai`, `400_workspaces.jai`, `600_insert.jai`, `460_code_browsing_and_generation/first.jai`, `470_running_hooks_in_the_target_workspace/target.jai`.  Here-string literals now terminate declarations without a required `;`, while ordinary strings still need one; focused round-trip and compiler AST fixtures pass.  Five of these files become complete, and `600_insert.jai` falls from 10 to 6 unrelated diagnostics (first at `<=`).  Corpus recovery improves from 37 files/294 diagnostics to 32 files/282 diagnostics, with 52/84 files now zero-diagnostic and no regressions.
- [x] Parse dotted aggregate field-default assignments such as `info.flavor = ...` and `base.type = ...`: `006_structs.jai`, `008_types.jai`.  Aggregate assignment lookahead now accepts dotted field paths and links their base identifier to the preceding field declaration.  Focused, malformed, round-trip, and compiler AST fixtures pass.  Both guides become complete; `120_polymorphic_structs.jai` also improves from 5 to 1 diagnostic.  Corpus recovery falls from 32 files/282 diagnostics to 30 files/270 diagnostics, with 54/84 files zero-diagnostic and no regressions.
- [x] Parse multi-target reassignment `out1, out2 = hello(1)` with the compiler's compound-declaration AST shape: `010_calling_procedures.jai` (1 file).  Focused AST, recovery, round-trip, and compiler differential fixtures pass.  The guide improves from 66 to 21 diagnostics; corpus recovery remains at 30 files and falls from 270 to 225 diagnostics, with 54/84 files zero-diagnostic and no regressions.
- [x] Disambiguate parenthesised conditions from procedure headers, including equality, modulo, logical operators, and a pointer truth test: `011_context.jai`, `200_memory_management.jai`, `480_custom_checks/first.jai`, `490_browsing_by_module/first.jai`, `040_import_and_load/files/specific.jai` (5 files).  Focused AST, recovery, round-trip, and compiler differential fixtures pass.  All five guides become complete; corpus recovery falls from 30 files/225 diagnostics to 25 files/199 diagnostics, with 59/84 files zero-diagnostic and no regressions.
- [x] Support unnamed procedure-type parameters and nested type-valued signatures, including `(T) -> $R`, `(T)`, `#type () -> ()`, and the compound pointer/array case type: `012_temporary_storage.jai`, `050_this.jai`, `110_polymorphic_arguments.jai`, `120_polymorphic_structs.jai`, `027_if_case.jai` (5 files).  Focused AST, recovery, round-trip, and compiler differential fixtures pass.  Four guides become complete; `050_this.jai` improves from 2 to 1 diagnostic, now at a later quick-lambda call.  Corpus recovery falls from 25 files/199 diagnostics to 21 files/189 diagnostics, with 63/84 files zero-diagnostic and no regressions.
- [x] Accept declaration initialisers with braced `ifx` value branches before the following statement: `025_ifx.jai` (1 file).  Focused recovery, round-trip, and compiler AST fixtures pass with or without an explicit semicolon.  The guide improves from 12 to 11 diagnostics; its next unsupported form omits `else`.  Corpus recovery remains at 21 files and falls from 189 to 188 diagnostics, with 63/84 files zero-diagnostic and no regressions.
- [x] Terminate block-form `#run` at its closing brace in statements and files, without requiring a semicolon: `170_modify.jai`, `560_no_reset.jai`, `497_caller_code.jai`, `950_cross-compiling/first.jai` (4 files).  Focused recovery, round-trip, and compiler AST fixtures pass, including an explicit semicolon and expression-form `#run`.  `497_caller_code.jai` and `950_cross-compiling/first.jai` become complete; `170_modify.jai` improves from 5 to 3 diagnostics and `560_no_reset.jai` from 10 to 8, both next encountering unrelated `#no_reset` syntax.  Corpus recovery falls from 21 files/188 diagnostics to 19 files/179 diagnostics, with 65/84 files zero-diagnostic and no regressions.
- [x] Parse enum members inside static `#if` branches without treating `BLORPLE;` as an unexpected statement: `095_static_if.jai` (1 file).  Focused nested, single-member, malformed, round-trip, and raw compiler AST fixtures pass.  The guide improves from 9 to 6 diagnostics, next encountering the separate `#ifx` expression form.  Corpus recovery remains at 19 files and falls from 179 to 176 diagnostics, with 65/84 files zero-diagnostic and no regressions.
- [x] Retain the source-spelled `#dump` procedure modifier as `DEBUG_DUMP`: `100_polymorphic_procedures.jai` (1 file).  Focused flag, truncated, round-trip, and compiler AST fixtures pass; the compiler fixture also emits the procedure's bytecode.  The guide improves from 25 to 19 diagnostics, next encountering `#procedure_of_call`.  Corpus recovery remains at 19 files and falls from 176 to 170 diagnostics, with 65/84 files zero-diagnostic and no regressions.
- [x] Parse `#procedure_of_call` expressions with ordinary and type-valued arguments as flagged procedure calls: `115_auto_bakes.jai`, `250_how_parameters_are_passed.jai` (2 files).  Focused AST, malformed recovery, round-trip, and compiler differential fixtures pass.  `250_how_parameters_are_passed.jai` becomes complete, `115_auto_bakes.jai` improves from 37 to 3 diagnostics, and `100_polymorphic_procedures.jai` improves from 19 to 3.  Corpus recovery falls from 19 files/170 diagnostics to 18 files/101 diagnostics, with 66/84 files zero-diagnostic and no regressions.
- [x] Parse `#assert` with optional message in procedure, static, expansion, and module scope: `160_type_restrictions.jai`, `550_is_constant.jai`, `730_for_expansions.jai`, `380_module_parameters/local_modules/Rendering.jai` (4 files).  Focused flag, message, malformed, round-trip, compiler AST, and workspace fixtures pass.  The first two guides become complete; `730_for_expansions.jai` improves from 10 to 8 diagnostics and `Rendering.jai` from 7 to 3.  Corpus recovery falls from 18 files/101 diagnostics to 15 files/85 diagnostics, with 69/84 files zero-diagnostic and no regressions.
- [x] Investigate the reported local `#code { ... }` error in `630_compiler_get_nodes.jai` (1 file).  The current first error was instead at the closing parenthesis of `#insert,scope() modified`; the local `#code` declaration already parsed.  Allow an empty scope redirection, retaining null rather than requiring an expression.  Focused local-declaration, following-statement, malformed, round-trip, and compiler AST fixtures pass.  The guide becomes complete; corpus recovery falls from 15 files/85 diagnostics to 14 files/84 diagnostics, with 70/84 files zero-diagnostic and no regressions.
- [x] Allow `#import,string` to consume a `#string` body with its required following semicolon: `040_import_and_load/main.jai` (1 file).  Focused decoded-name, import-flag, following-statement, missing-semicolon, round-trip, and compiler AST fixtures pass.  The guide becomes complete; corpus recovery falls from 14 files/84 diagnostics to 13 files/80 diagnostics, with 71/84 files zero-diagnostic and no regressions.
- [x] Parse `#run -> Return_Type { ... }` and `#run,host -> Return_Type { ... }` expression bodies: `044_using_advanced/main.jai`, `950_cross-compiling/do_things_at_compile_time_for_real.jai` (2 files).  Focused header, flag, body, optional-semicolon, truncation, round-trip, and compiler AST fixtures pass.  The cross-compiling guide becomes complete; `044_using_advanced/main.jai` improves from 7 to 4 diagnostics, next encountering the separate `using,map` form.  Corpus recovery falls from 13 files/80 diagnostics to 12 files/71 diagnostics, with 72/84 files zero-diagnostic and no regressions.
- [x] Check semicolon handling for `using enum u16 { ... }` before the next statement: `042_using.jai` (1 file).  The `using` wrapper now inherits the enum body's optional semicolon, while ordinary `using` still requires one.  Focused AST, explicit-semicolon, following-statement, round-trip, and compiler AST fixtures pass.  The guide becomes complete; corpus recovery falls from 12 files/71 diagnostics to 11 files/70 diagnostics, with 73/84 files zero-diagnostic and no regressions.
- [x] Reconcile the section 13.3 checkboxes with implemented named selectors and combined literal `<`/`*` flags; keep controlled `<=`/`*=` flags and missing fixture combinations unchecked.  The existing parser and focused/compiler fixtures cover the three source-level prefix forms marked complete below; controlled flags, malformed variants, and the full guide fixture matrix remain open.
- [x] Update historical baseline wording and the README assembly description to distinguish current instruction envelopes from unparsed operand internals; qualify past differential-suite claims until its runtime checks pass.  Dated corpus counts remain historical snapshots; compile-time fixture coverage is distinct from runtime assertions, which passed after the diagnostic-location correction.
- [x] Audit the section 13.1 malformed-variant claim against the actual fixtures and narrow it to the selected truncations and trailing-token errors exercised by the runtime suite.  Other malformed combinations remain unverified; separate synchronisation fixtures cover following declarations.

Remaining `how_to` first-error leads (2026-09-25; 81/84 zero-diagnostic, 3 recovering files, 15 diagnostics).
Each item starts at the current first error, not a claim that every later diagnostic in the guide has the same cause.
Confirm valid syntax with the compiler, add focused AST/recovery/round-trip and differential fixtures as appropriate, and rerun the corpus after each fix.

- [x] Parse comma-separated compound assignments to arbitrary LValues such as `array[it], array[it+1] += get_u8s()`: `010_calling_procedures.jai` (first error at line 224, expected `;` at `,`).  Focused indexed and member assignment AST, recovery, round-trip, and compiler differential fixtures pass.  The guide is zero-diagnostic; corpus improves from 73/84 to 74/84 zero-diagnostic files, 11 to 10 recovering files, and 70 to 49 diagnostics, with no regressions.
- [x] Parse value-form `ifx` without an explicit `else`, such as `mame := ifx thing then thing.name;`: `025_ifx.jai` (line 160, expected `else` at `;`).  Focused AST, following-statement, round-trip, and compiler differential fixtures pass.  The guide improves from 11 to 5 diagnostics; corpus stays at 74/84 zero-diagnostic and 10 recovering files, with diagnostics falling from 49 to 43 and no regressions.
- [x] Parse value-form `ifx` with an omitted `then` branch before `else`, such as `y2 := ifx x else 1;`: `025_ifx.jai` (first error at line 202, expected an expression at `else`).  Focused AST, recovery, following-statement, round-trip, and compiler differential fixtures pass.  The guide improves from 5 to 3 diagnostics; corpus remains at 74/84 zero-diagnostic and 10 recovering files, with diagnostics falling from 43 to 41 and no regressions.
- [x] Parse value-form `ifx` with both value branches omitted, such as `y4 := ifx is_odd(x);`: `025_ifx.jai` (first error at line 255, expected an expression at `;`).  Focused AST, recovery, following-statement, round-trip, and compiler differential fixtures pass.  The guide becomes zero-diagnostic; corpus improves from 74/84 to 75/84 zero-diagnostic files, 10 to 9 recovering files, and 41 to 38 diagnostics, with no regressions.
- [x] Investigate the call containing a block-bodied quick lambda, `call_with(5, x => { ... });`: `050_this.jai` (line 140, expected `;` at `(`).  The failure was the nested statement-leading `#this(x-1)` call: it now uses expression parsing for its postfix arguments.  Focused AST, recovery, following-statement, round-trip, and compiler differential fixtures pass.  The guide becomes zero-diagnostic; corpus improves from 75/84 to 76/84 zero-diagnostic files, 9 to 8 recovering files, and 38 to 37 diagnostics, with no regressions.
- [x] Parse expression-form `#ifx` with value branches: `095_static_if.jai` (line 270, expected an expression at `#`).  Focused AST, recovery, following-statement, round-trip, and compiler differential fixtures pass.  The guide becomes zero-diagnostic; corpus improves from 76/84 to 77/84 zero-diagnostic files, 8 to 7 recovering files, and 37 to 31 diagnostics, with no regressions.
- [x] Parse the `inline procedure_call(...)` statement inside a static branch: `115_auto_bakes.jai` (line 279, expected an expression at `inline`).  Call-level `inline` and `no_inline` retain their compiler-matching flags without changing procedure headers.  Focused AST, recovery, following-statement, round-trip, and compiler differential fixtures pass.  The guide becomes zero-diagnostic; corpus improves from 77/84 to 78/84 zero-diagnostic files, 7 to 6 recovering files, and 31 to 28 diagnostics, with no regressions.
- [x] Parse source-spelled `#no_reset` before declarations, as used at module scope in `170_modify.jai` and `560_no_reset.jai` (first errors at lines 388 and 72, both unexpected `#`).  Focused AST, malformed-prefix recovery, following-declaration, round-trip, and compiler AST/file-workspace fixtures pass.  Both guides become zero-diagnostic; corpus improves from 78/84 to 80/84 zero-diagnostic files, 6 to 4 recovering files, and 28 to 17 diagnostics, with no regressions.
- [x] Investigate the `#insert -> Code { ... }` short form and its statement boundary: `600_insert.jai` (line 419, expected `;` at `#`).  Short-form `#insert -> string` and `#insert -> Code` already parsed as implicit runs; their block bodies now terminate statements without a semicolon, while ordinary inserts still require one.  Focused AST, recovery, following-statement, round-trip, and compiler differential fixtures pass.  The guide becomes zero-diagnostic; corpus improves from 80/84 to 81/84 zero-diagnostic files, 4 to 3 recovering files, and 17 to 15 diagnostics, with no regressions.
- [x] Clear the controlled `<=` for-expansion first error by parsing `<=` and `*=` flag values and comma-separated combinations: `730_for_expansions.jai` now parses completely. Focused AST, malformed-prefix, round-trip, and raw compiler AST fixtures pass; corpus improves from 81/84 to 82/84 zero-diagnostic files, 3 to 2 recovering files, and 15 to 7 diagnostics, with no regressions. Further controlled-expression ambiguities remain in section 13.3.
- [x] Parse `using,map(prefix_with_gl) procs: Procs;` as a `.MAP` filter with a parenthesised expression, while keeping unknown modifiers diagnostic: `044_using_advanced/main.jai` now parses completely.  Focused AST, malformed-filter, round-trip, and raw compiler AST fixtures pass; corpus improves from 82/84 to 83/84 zero-diagnostic files, 2 to 1 recovering file, and 7 to 3 diagnostics, with no regressions.  Compiler semantic mapping remains unimplemented.
- [x] Parse the file-scope `#scope_module` directive as an internal-scope node: `380_module_parameters/local_modules/Rendering.jai` now parses completely.  Focused AST, following-import/declaration, exact round-trip, and top-level compiler workspace fixtures pass; corpus improves from 83/84 to 84/84 zero-diagnostic files, 1 to 0 recovering files, and 3 to 0 diagnostics, with no regressions.  Raw `#code` AST comparison is unavailable because the compiler permits scope directives only at top level.
- [x] Re-triage each guide after its first error is fixed and record newly exposed valid source forms as separate tasks.  The corpus now has 84/84 `COMPLETE` files with zero diagnostics and exact trivia round-trips; no further first-error leads remain.  Keep the compatibility completion checkbox above open until its category-by-category fixture coverage is verified.

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
- [x] Parse inferred register operands such as `apple:` and explicit declarations such as `banana: gpr` as standalone statements and inline instruction operands, including the declaration prefix in `mov w: gpr === 15, 10`. Focused kind, name, class, span, and round-trip fixtures pass; the compiler accepts the forms in a typechecked workspace. Pinning remains for the next checkbox; the 84-file corpus stays complete with zero diagnostics.
- [x] Parse register pinning with `===`, including declaration pinning (`t: gpr === a`, `v: vec === 9`) and existing-value pinning (`x === a`).  Standalone and inline forms retain source and target token spans; focused fixtures round-trip, and a typechecked compiler workspace accepts both pinning forms. More complex value expressions remain for the later operand-expression item.
- [x] Parse signed integer and floating-point immediates without imposing instruction-specific width or range rules in the syntax phase.  Numeric operands now retain exact spans and use ordinary literal/unary expression nodes; focused fixtures cover both signs, floats, wide integers, and round-tripping.  A negative integer operand passes a typechecked compiler workspace fixture; instruction-specific operand validity remains semantic.
- [x] Parse memory operands using brackets and preserve their rigid source structure: required base, optional index and scale, optional signed displacement, and parenthesised high-level constant expressions.  Focused fixtures cover `[b]`, `[base + index*8 - 10]`, vector-index spelling, constant-expression scale and displacement, malformed shapes, and exact round-tripping; a typechecked compiler workspace accepts `[base]`. Broadcast and other suffix modifiers remain for the next checkbox.
- [x] Parse memory broadcast suffix `!`, SAE and explicit rounding suffixes `!`, `!n`, `!d`, `!u`, and `!z`, plus mask merge/zero forms `& mask` and `&* mask`.  Focused fixtures verify ordered modifier kinds, mask arguments, source spans, combined memory and numeric operands, malformed-suffix preservation, and exact round-tripping.  Instruction-specific modifier validity remains semantic.
- [x] Allow high-level identifiers, constants, types, macro parameters of `__reg`, and parenthesised high-level expressions where the assembly grammar permits them, while retaining enough node distinction for later binding.  Bare names and complete parenthesised operands now have `VALUE` expression nodes distinct from declarations, pinning, and memory; pinning source/target values are populated too.  Focused AST and round-trip fixtures pass, and the compiler accepts high-level constant operands and `__reg` macro declarations in typechecked workspaces.  Binding and instruction-specific validity remain semantic.

Validate syntax separately from machine semantics:

- [x] Add focused fixtures for every source form in `how_to/900_inline_assembly.jai`, including feature headers, macros receiving registers, compile-time execution, VSIB addressing, EVEX broadcast/rounding/masking, and polymorphic mnemonic sizes.  Focused AST and round-trip fixtures cover the tutorial's basic instructions, immediate sizes, register declarations/pinning, symbolic and parenthesised memory constants, feature blocks, register macros, `#run`, VSIB gathers, EVEX modifiers, and fixed/polymorphic sizes.  The complete tutorial also parses without diagnostics and reconstructs exactly; compiler semantics remain separate.
- [x] Compare valid fixtures with the compiler for node kind, source location, and enclosing-tree placement.  Differential fixtures now compare direct and conditional-branch `Code_Asm` nodes, including feature headers and multiline source, against parser kinds, directive-token coordinates, and parent-block paths.  The compiler reports only the `#asm` directive location while the parser spans the full block; conditional block location anchors also differ, so positions are compared relative to the common outer block. `Code_Asm` exposes only opaque payload fields (`b1`/`b2`/`b3`), making payload equality impossible until the compiler exposes assembly internals.
- [x] Compile valid and intentionally invalid assembly fixtures with the Jai compiler to capture semantic diagnostics, but do not duplicate mnemonic lookup, operand-form matching, immediate ranges, feature gates, register allocation, or encoding in the parser.  Typechecked workspace fixtures include registers, pinning, memory, constants, macros, and in-range byte immediates.  Full compiler runs reject syntactically complete unknown mnemonics, out-of-range byte immediates, and invalid operand forms with captured error categories and source locations; the parser reports zero syntax diagnostics for these cases.  Feature validation, allocation, and encoding remain compiler responsibilities.
- [x] Recover malformed assembly at the next semicolon or closing `}` without handing instruction operands to the high-level statement parser.  Focused fixtures cover missing semicolons, missing commas before names or immediates, malformed and unclosed memory, invalid modifiers and masks, and EOF-truncated blocks.  Diagnostics retain source spans and partial assembly nodes; subsequent assembly instructions and high-level statements stay in their own scopes, and malformed sources reconstruct exactly.
- [x] Require `how_to/900_inline_assembly.jai` to parse as `COMPLETE` with zero diagnostics and round-trip byte-for-byte before marking inline assembly parsing complete.  The focused test reads the real tutorial file and asserts all three conditions; the full `how_to` corpus also remains 84/84 complete with zero diagnostics.

#### 13.3 Parse For-Expansion Syntax

`how_to/730_for_expansions.jai` uses the normal `Code_For` node with additional source-level controls.  The public AST already exposes `want_replacement_for_expansion`, `want_pointer_expression`, `want_reverse_expression`, and `for_flags`; parse those fields now, but defer lookup and execution of the expansion macro until semantic analysis.  `macro_expansion_procedure_call`, `ident_decl`, and `index_decl` are typechecked/generated fields and must remain unset during syntax parsing.

Parse the complete `for` prefix grammar:

- [x] Parse an optional named expansion selector immediately after `for`, as in `for :positive_vibes_only value, index: holder`, and store its expression in `want_replacement_for_expansion`.  Preserve the absence of a selector so semantic lookup can use the conventional `for_expansion` name.  Existing `:utf8_iter` and default-loop fixtures check both cases.
- [x] Parse literal reverse and pointer flags independently and in combination: `for < value`, `for * value`, `for < * value`, and `for <* value`.  Set `.REVERSE` and `.POINTER` in `for_flags`; do not use mutually exclusive parsing for the two flags.  Focused and compiler fixtures cover both individual flags and spaced/adjacent combinations.
- [x] Allow a named selector after literal flags, as in `for < :polite dummy`, and define one canonical parse order while accepting the spaced and adjacent forms shown in the guide.  Existing spaced and adjacent combined-flag fixtures retain `:utf8_iter` after the flags.
- [x] Parse controlled flags `<=expression` and `*=expression` into `want_reverse_expression` and `want_pointer_expression`.  Support either flag alone and both together, including the comma-disambiguated form `for *=pointer_expression, <=reverse_expression collection`.
- [x] Define where a controlled-flag expression stops without consuming the iteration expression.  Controlled values use prefix parsing, so comparison or assignment flags require parentheses; without them, those operators belong to the following iteration expression or produce a syntax diagnostic.  Both controlled flags require a separating comma in either order, with a missing-comma diagnostic retaining both flags and the collection.  Focused AST, compiler-differential, and round-trip fixtures cover these boundaries; the 84-file corpus remains complete with zero diagnostics.
- [x] Reject or recover duplicate literal/controlled forms of the same flag deterministically, while preserving all source tokens for round-tripping.  Repeated flags report at the duplicate token; the first spelling wins, and focused fixtures cover both flags, both mixed orders, and exact reconstruction.

Preserve iterator bindings and loop shape:

- [x] Parse implicit `it`/`it_index`, a renamed value (`for value: collection`), and renamed value/index pairs (`for value, index: collection`) with the selected expansion syntax.  Implicit names leave syntax-owned binding fields unset; focused and compiler-differential fixtures cover selected expansions with literal and controlled flags and exact round-trips.
- [x] Preserve iterator identifiers marked with Jai's backtick syntax, as in the source form `` for `it, `it_index: collection ``, by setting their source-spelled identifier flags, so expansion macros can deliberately export the bindings to their caller.  Both explicit binding nodes retain `.HAS_SCOPE_MODIFIER`; focused token/round-trip and raw compiler AST fixtures pass.
- [x] Retain existing range-loop parsing separately from for-expansion selection, including `iteration_expression_right`, and add ambiguity fixtures proving that selector/flag syntax does not consume range operators or the loop body.  Plain, literal-flag, and controlled selected ranges retain both endpoints and separate bodies/following statements; focused round-trip and compiler AST fixtures pass.
- [x] Parse both single-statement and braced bodies for all selector and flag combinations, retaining parent/owning-statement links and exact token spans.  Focused matrix fixtures cover 22 valid prefix forms with both body forms, following statements, parent/owner links, and byte-for-byte round trips; selected literal and controlled cases match compiler nodes.

Preserve syntax used inside expansion procedures:

- [x] Differentially verify the `for_expansion :: (value, body: Code, flags: For_Flags) #expand` declaration shape, including value and pointer receiver forms.  Treat the conventional procedure name and signature as ordinary declarations during syntax parsing.  Focused AST/round-trip and raw compiler comparisons cover both receivers; syntax comparison uses the source-spelled declaration name rather than the compiler's unpopulated raw header name.
- [x] Preserve declarations exported with Jai's backtick syntax, including `` `it ``, `` `it_index ``, and additional user-defined names such as `` `visited_index ``.  Existing declaration flags retain each source-spelled export; focused flag/span/round-trip and raw compiler AST fixtures pass.
- [x] Complete `#insert` replacement parsing for `#insert(break=statement, continue=statement, remove=statement) body`, populating `break_replacement`, `continue_replacement`, and `remove_replacement`.  Existing parsing retains targeted loop controls such as `break y` and rejection replacements such as `#assert(false)`; focused AST/round-trip and raw compiler differential fixtures pass.
- [x] Verify that a plain `#insert body` remains distinct from replacement-bearing insertion and that inserted expansion output remains a semantic/generated field rather than syntax-owned AST.  Focused fixtures check null replacement fields on plain insertion, populated fields on replacement-bearing insertion, null `expansion` for both, and exact reconstruction; existing compiler differential fixtures compare both source forms without generated output.

Validate and recover at the syntax layer:

- [x] Add focused and compiler-differential fixtures for every loop spelling in `how_to/730_for_expansions.jai`: default and named selectors; renamed iterators; `<`, `*`, `< *`, and `<*`; controlled `<=` and `*=` flags; combined controlled flags; and backticked iterator bindings.  The focused body-form matrix checks spans, ownership, and exact round-trips; raw compiler AST fixtures compare the guide's named selectors, literal and controlled flags, and exported binding forms.
- [x] Compare parser fields with raw compiler `Code_For` nodes before typechecking.  Normalisation now covers both controlled pointer/reverse expressions alongside selectors, bindings, flags, iteration, and body; `ident_decl`, `index_decl`, and `macro_expansion_procedure_call` stay excluded, and focused fixtures confirm they remain null on both syntax trees.
- [x] Add malformed fixtures for a missing selector, missing controlled-flag expression, duplicate flags, missing comma between controlled flags, missing iterator after a comma, missing binding colon, and truncated body.  Focused fixtures cover both controlled-flag kinds, partial bindings, diagnostics, and exact source reconstruction; broader prefix synchronisation remains a separate item below.
- [x] Synchronise malformed prefixes at the iteration expression or loop body without reinterpreting the body as top-level declarations, and keep partial `Parser_For` nodes stable.  Focused file-level fixtures verify partial loops with malformed selectors, controlled flags, bindings, commas, and duplicate flags; braced and single-statement bodies stay attached while following procedure and file declarations retain their scopes and sources round-trip exactly.
- [x] Require `how_to/730_for_expansions.jai` to parse as `COMPLETE` with zero diagnostics and round-trip byte-for-byte before marking for-expansion syntax complete.  A dedicated focused fixture reads the real guide and checks all three conditions; expansion semantics remain deferred.

#### 13.4 Evaluate Identifier Interning Before Name Resolution

Previously `cached_make_atom` copied every identifier spelling; its commented implementation depended on the compiler's `active_load.atom_table`, which this standalone lexer does not have.  Each parsed source now owns a table to share repeated identifier spellings, while standalone lexers copy names unless given optional storage.  Pointer identity must not substitute for string equality across parses.  Table lookups and per-file retention may outweigh savings on small or mostly unique inputs.

- [x] Establish a baseline for identifier allocations, peak retained memory, and lex/parse time on repeated-name, mostly unique-name, and `how_to` inputs; measure keyword-heavy inputs separately before changing storage.  Measurements and limitations follow.

Baseline (Windows x64, current copying path): `examples/atom_baseline.jai` runs 1,000 `value := value + 1;` statements (repeated), 1,000 distinct `value_N := 1;` statements (unique), 1,000 `if true { while false { break; } }` statements inside a procedure (keywords), or all 84 `how_to/*.jai` files.  Input files/source strings are loaded before the timed region and before the memory snapshot.  Each phase runs in a fresh process; lex consumes tokens without building an AST, while parse calls `parse_file` and retains its result.  The count columns classify nonempty names copied by the lexer; the allocation column is the live Basic memory-debugger allocation delta from the `-x64` build, including non-name allocations.  Times are medians of five fresh-process runs of the `-o -llvm` build.  Keyword and note names use the same copying path and are shown separately.

| Input | Phase | Identifier / keyword / note copies | Copied name bytes | Retained allocations | Retained bytes | Peak retained bytes at file checkpoints | Median time (ms) |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Repeated | Lex | 2,000 / 0 / 0 | 10,000 | 2,000 | 10,000 | 10,000 | 0.247 |
| Repeated | Parse | 2,000 / 0 / 0 | 10,000 | 2,009 | 1,591,071 | 1,591,071 | 1.662 |
| Unique | Lex | 1,000 / 0 / 0 | 8,890 | 1,000 | 8,890 | 8,890 | 0.174 |
| Unique | Parse | 1,000 / 0 / 0 | 8,890 | 1,006 | 1,393,353 | 1,393,353 | 1.260 |
| Keywords | Lex | 1 / 5,000 / 0 | 21,005 | 5,001 | 21,005 | 21,005 | 0.390 |
| Keywords | Parse | 1 / 5,000 / 0 | 21,005 | 5,016 | 3,109,404 | 3,109,404 | 2.759 |
| `how_to` | Lex | 13,278 / 1,909 / 1 | 89,806 | 17,389 | 127,644 | 127,644 | 6.235 |
| `how_to` | Parse | 13,218 / 1,899 / 1 | 89,480 | 17,517 | 16,189,421 | 16,189,421 | 18.065 |

The baseline above was recorded before interning; rerunning the harness on the current revision measures the new implementation, not the copying baseline.  From `modules/Jai_Parser/examples`, build with `jai atom_baseline_debug.jai -x64` and `jai atom_baseline_time.jai -o -llvm`, then run `./atom_baseline_debug.exe repeated lex` (substitute `unique`, `keywords`, or `how_to`, and `lex` or `parse`) for allocations and retained bytes.  Run each `./atom_baseline_time.exe repeated lex` combination five times in separate processes for a median uninstrumented time.  `-o` selects the same very-optimised build as the deprecated `-release` flag; `-llvm` makes the backend explicit.  The debug build uses Basic's `MEMORY_DEBUGGER`; its time is not a performance baseline.  Sub-millisecond synthetic runs are sensitive to timing noise; compare like-for-like builds and environments.  The reported peak is the maximum live-allocation delta sampled after each file, not a true in-file high-water mark; it equals final retained bytes for these inputs.  Basic does not expose a peak allocator counter through its public leak-report API, and pool-managed allocations are represented by their backing allocations.  The `how_to` lex run emits existing lexer diagnostics for source forms in the corpus; the parse run completes.

- [x] Define the lifetime and ownership of canonical names across lexer reuse, materialised tokens, AST nodes, `release_parser_tree`, and borrowed source changes.  Keep token text and trivia lossless; do not attach the table to compiler `active_load` or free names while retained tokens or nodes still reference them.  Contract below.

Canonical-name ownership contract for the identifier interning implementation:

- Each `Parsed_Source` owns an independent identifier table and fallback pool, separate from its AST node pool.  Its local lexer borrows that storage through an optional identifier callback; lexers without supplied storage retain the copying path.  Concurrent parses use separate tables, with no shared lock or compiler `active_load` dependency.  The public token layout remains unchanged.
- An identifier token's `ident_value.name` is the canonical value of its parsed spelling (including the existing backtick interpretation).  Unchanged contiguous spellings borrow caller-owned source; normalised spellings and names from lexer-owned file input live in the fallback pool, never in lexer scratch space.  `ident_value.hash` and all name comparisons retain value semantics; equal names within one parse may share storage, but pointer identity across parses is never required.  Resolve hash collisions by comparing spelling bytes.  Keywords and `NOTE` names retain the copying path.
- Resetting a lexer may overwrite its ring-buffer slots and, for file input, free the old `Lexer.input`.  Callers supplying identifier storage must retain borrowed sources referenced by its table until the table is released; file-input names are copied, so those names survive reset, though borrowed trivia does not.  Materialised tokens and AST names remain valid after the parser's local lexer goes away.  `release_parser_tree` frees only AST nodes and child arrays; after callers finish with retained tokens, `release_parser_names` releases table and fallback pool storage and invalidates token identifier names.  Separate parses do not share ownership.
- `source`, `fully_pathed_filename`, `original_text`, and trivia remain borrowed; token byte spans are offsets into the borrowed source.  Keep the input alive and unchanged while using materialised tokens or reconstruction, even after tree release.  Original bytes (including backticks and spacing) are reconstructed from source views, not from normalised names.  String literal payloads and note spelling remain outside the identifier table.

- [x] Replace per-occurrence identifier copies with a parser-owned atom table and stable name storage only after the lifetime contract is implemented; retain value-based lookup semantics, handle collisions, and keep the existing public token layout and keyword recognition correct.  `intern_identifier` looks up by string value (including spelling checks on hash collisions) and retains a source view or a pool-backed normalised spelling.  Standalone lexers copy by default; keywords and notes stay copied.  The parser's repeated-name parse probe dropped from 2,009 to 10 retained allocations and from 1,591,071 to 1,582,351 retained bytes.  Unique-name parse retained 1,466,383 bytes versus 1,393,353 in the copying baseline; the later comparison gate must decide whether to keep this implementation.
- [ ] Add focused tests for repeated and distinct names, hash collisions, backticked identifiers, notes, keywords, lexer reset, separate parse lifetimes, and exact trivia round-trips; run the existing parser, differential, and corpus suites.
- [ ] Compare allocation, peak memory, and elapsed time with the baseline; keep interning only if it provides a measurable benefit without regressions, otherwise document the result and retain the copying path.

### 14. Add Semantic Analysis

- [ ] Build lexical scopes and bind declarations.
- [ ] Resolve identifiers and imports.
- [ ] Instantiate and infer types.
- [ ] Evaluate constants required by language semantics.
- [ ] Resolve overloads and polymorphs.
- [ ] Model desugaring and compiler-generated nodes where observable.

Implement for-expansion semantics after scopes, types, constants, overloads, and generated-node support:

- [ ] During name resolution, resolve the default `for_expansion` or selected expansion procedure using the iteration value's pointer form and Jai's auto-dereference rules.
- [ ] Evaluate controlled pointer/reverse expressions as compile-time booleans, combine them with literal `for_flags`, and provide the resulting `For_Flags` value to the expansion macro.
- [ ] Expand the loop body as `Code`, remap exported `it` and `it_index` to the source-spelled iterator names, retain additional exported names, and populate `macro_expansion_procedure_call` plus generated declaration fields.
- [ ] Apply `#insert` break/continue/remove replacements to loop-control nodes in the inserted body, preserving labelled targets such as `break y`; report unsupported controls when the expansion deliberately substitutes a compile-time assertion.
- [ ] Add semantic fixtures using value and pointer receivers, nested-loop break replacement, extra exported variables, and the real `Unicode.utf8_iter`, `Bit_Array`, `Hash_Table`, and `Bucket_Array` expansions.

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
