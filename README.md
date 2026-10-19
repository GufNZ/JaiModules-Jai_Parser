# Jai_Parser

## Tests

Run these from `modules/Jai_Parser/examples` with `jai <file>.jai -x64 && ./<file>.exe`.

- `layout_test.jai` checks default lexer layout compatibility and focused token, trivia, here-string, and keyword behaviour across import options.
- `lex_all_files.jai` scans `.jai` files under `modules`, checking that lexer tokens and trivia account for every source byte without lexer errors.
- `parser_tokens_test.jai` checks parser-owned token spans and AST shapes, source round trips, and recovery on focused valid and invalid inputs.
- `differential_test.jai` compares parser ASTs and selected diagnostics with the Jai compiler, including contextual and typechecked fixtures.
- `parse_how_to.jai` parses the `how_to` corpus, checks nonfatal roots and exact source round trips, and reports zero-diagnostic files, first failing source lines, and diagnostic changes against its checked-in baseline.

For scalar/SIMD lexer and token-materialisation timing on Windows, run from the same directory:

```bash
jai lex_all_files.jai -o -llvm
./lex_all_files.exe --benchmark ../../../examples/invaders ../../../how_to
```

The benchmark preloads source files, verifies token parity outside timing, and alternates nine trials of 25 corpus scans after two warmups per mode.
Timing includes token allocation and cleanup, but excludes file I/O, compiler startup, and AST parsing.
It reports median and range; small changes within that variability are not established speedups.
`--benchmark` compares scalar with `USE_SIMD=true`, checks complete-token parity, and reports the widest CPU/OS-supported path selected automatically.

For deterministic workload and allocation comparisons, use the same LLVM build:

```bash
./lex_all_files.exe --benchmark-workloads
bash collect_simd_timings.sh --workloads
```

The five workloads repeat 4,096 ordinary-token records: short identifiers, long identifiers, long line comments, plain strings, and escaped strings.
Sources are generated before timing.
Each workload verifies complete scalar/SIMD materialised-token parity, then checks equal token counts in four phases: streaming or materialised tokens, each with fresh or reused pools.
Streaming still copies names and decodes strings but omits retained token arrays; contextual here strings remain covered by the real-corpus materialisation benchmark rather than this streaming comparison.

Fresh pools include backing allocation and release per source.
Reused pools are primed outside each timed trial, reset after every source, and released after timing.
`Pool.reset` retains ordinary buckets but frees oversized allocations, so large token arrays still require heap allocations.
Both modes preserve copied payloads and the same lexer settings.
The reported differences isolate storage and pool-lifecycle sensitivity, not exact additive percentages of pure scan and allocation time; cache state, copying, and reset work also differ.

Output includes median/range, MiB/s, and millions of tokens/s.
Separate untimed forwarding allocator counters report cumulative allocation/resize requests and requested bytes at both token and backing-heap levels, not live or peak retained memory.
Scalar/SIMD token-level counts and bytes must agree.
The collector's `--workloads` option includes these phases alongside both real corpora in each of its default three rounds, with compiler/host/source provenance.
Use repeated like-for-like LLVM runs; the SIMD default remains unchanged by these measurements.

On an AVX-512F/BW machine, run the focused tests under both backends before timing:

```bash
jai layout_test.jai -x64 -quiet && ./layout_test.exe
jai layout_test.jai -o -llvm -quiet && ./layout_test.exe
jai lex_all_files.jai -o -llvm -quiet
./lex_all_files.exe --benchmark ../../../examples/invaders ../../../how_to
```

The layout executable checks each supported identifier classifier directly, then compares scalar tokens and comment state against automatic SIMD dispatch at vector/scratch boundaries, newline, NUL, logical EOF, and tails.
For AVX-512, classifier checks cover all 256 byte values in each of 64 lanes at 64 alignments; unsupported widths report `SKIPPED` without executing those instructions.
On an AVX-512 machine, confirm width 64 reports `PASS` and the benchmark reports `Widest SIMD path: AVX-512`.
Benchmark timing uses `Basic.current_time_monotonic()` and does not require a direct Windows API import; the collector script below still targets Windows Bash.

To collect a single report for comparing another Windows machine, run in Cygwin, MSYS, or Git Bash from `examples`:

```bash
bash collect_simd_timings.sh
```

The script also works when invoked by path from another directory.
It builds isolated executables, runs fast/LLVM layout validation first, and collects three rounds of scalar versus automatic-SIMD corpus timings.
Scalar and SIMD trial order alternates within each round.
The report includes compiler version, host/CPU details, feature availability, source commit/status/hashes, exact commands, medians/ranges, relative speedups, and parity results.
The benchmark reports the widest selected path, so a machine without AVX-512 is clearly identified as using AVX2 or SSE2 instead.

Results are printed and stored in `examples/.build/simd_timings_<UTC>_<PID>/report.txt`, alongside the executables.
Provide that report for analysis; successful runs end with `Collection COMPLETE`, while failed validation stops collection and preserves a partial report.
Cleanup removes these generated reports.
Keep machine power settings consistent and avoid other CPU-heavy work during collection.

Use `--rounds 1` for a quick check, `--output-dir DIRECTORY` to select another output root, or supply corpus directories instead of the default Invaders/`how_to` pair.
Relative arguments resolve against the invoking directory.
Set `JAI=/path/to/jai.exe` when the compiler is not on `PATH`; `--help` lists the options.

For the separate AVX-512 frequency investigation, follow [the clock measurement handoff](examples/SIMD_CLOCKS.md).
`lex_all_files --clock-probe scalar|simd DIRECTORY` verifies token parity and runs one mode for 30 seconds for external effective-clock logging; elapsed timing alone is not a frequency measurement.

The real-file AST-reuse benchmark runs independently of that hardware collection:

```bash
jai benchmark_ast_reuse.jai -o -llvm -output_path .build -exe benchmark_ast_reuse
./.build/benchmark_ast_reuse.exe ../../../examples/invaders > .build/ast_reuse_workloads.log
```

It inventories bytes, line positions (one plus LF bytes per nonempty file), tokens including EOF, parse status, diagnostics, and exact reconstruction for each independent source file.
It then reports full-lex, AST-plus-binding, and end-to-end parse/cleanup times with two warmups and 21 trials per file; p95 is the nearest-rank 20th sorted sample.
Inputs are loaded outside timing, snapshots use fresh scoped pools, and trivia/default-SIMD/copied-name/binding settings match ordinary parser imports.
It also compares three modes on the same chained prefix-comment insertion, replacement, and deletion: `FULL` re-lexes/reparses, `TOKENS` materialises incrementally but constructs the AST without an old-tree template, and `AST` additionally supplies the previous tree to the existing copier.
Real-code workloads insert a declaration, replace its initialiser, and delete it at root and procedure-body boundaries nearest 5%, 50%, and 95% of each file.
The report prints actual byte positions; available syntax boundaries need not coincide with those targets, and missing constructs are explicitly skipped.
Additional sequences edit an existing braced declaration block, wrap adjacent simple declarations in a static scope and move its closing brace across one declaration, and remove an initialiser before repairing the malformed revision by deleting the inserted declaration.
Edits are in-memory revisions of independent real files; corpus files are not modified or concatenated.
Reports separate potentially eligible declaration contexts, recovered baselines, procedure-body reparsing, scope/boundary reparsing, malformed/repair chains, and the trivia control.
These labels describe workloads, not observed copy counts: unaffected declarations may still copy during body or boundary edits, and a malformed/repair chain mixes clean and recovered snapshots.
The separate verification build below reports actual successful declaration-copy events per revision.
All modes use the same module instance, source revisions, settings, fresh independent backing pools, independently copied source buffers, and lexical binding; only token materialisation and AST-template selection differ.
Each edited snapshot becomes the next old snapshot, and the old snapshot is released after construction in every mode.
The owned lifecycle timer spans new-pool setup, acquiring an owned copy of the prebuilt revision, token materialisation, AST construction/binding, and old-source/tree/name/pool release.
Separate distributions report token materialisation (including the incremental path's internal edit validation), AST/binding, construction, new-pool/source acquisition, and old-snapshot disposal.
Initial owned-snapshot construction and final-snapshot disposal are measured separately, outside the update distribution, rather than hidden or amortised into each edit.
File I/O, compiler startup, generating the common revision strings, correctness checks, allocation profiling, and reporting are outside timed regions.
Phase timings include counter-call overhead; sub-microsecond differences should not be treated as precise savings.
Two warmup sequences precede 21 measured sequences, with trial order rotating across modes.
Each mode reports median, nearest-rank p95, and range over 63 individual edits, not three-edit sequence averages; p95 is the 60th sorted sample.
Per-edit-position lifecycle distributions also report 21 trials each (20th sorted sample for p95), so insertion, replacement/malformed, and deletion/repair tails remain visible.
Absolute and relative median/p95 lifecycle savings compare both incremental modes with full parsing and AST copying with token-only parsing; construction-only AST-versus-token savings remain separate.
Untimed checks compare status, token kinds/flags/text/trivia/byte locations, root kind and statement count, diagnostic/recovery/restart counts, and exact reconstruction, including after releasing the old snapshot.
Valid edits of clean baselines must remain diagnostic-free, malformed revisions must add a diagnostic, and final repairs must restore baseline status and diagnostic count.
The timed runner specialises on a compile-time verification flag, with those checks excluded using `#if`; declaration-copy instrumentation is also disabled.

After timing each workload, a separate untimed pass repeats all three modes with the same revisions and source ownership.
It reports allocation/resize requests and cumulative requested bytes at the caller allocator boundary, including the AST pool's backing requests, plus outer-pool backing requests and bytes.
These layers must not be added together or interpreted as one request per AST node.
A pointer-size ledger tracks outstanding backing bytes even when frees omit their size.
Its own hash-table storage and reconstruction-check pools use the independent original allocator and are excluded.
Per-edit reports include old-only retention, new retention, simultaneous old/new retention and peak, source-buffer lengths, and retention after old release; final release must leave every snapshot's ledger empty with zero outstanding bytes.
The backing counts include source copies, pool metadata/slack, and retained snapshot storage, but not the corpus/revision/anchor buffers, temporary allocator storage, ledger bookkeeping, native allocator metadata/caches, or process working set.
Peak means outstanding requested backing bytes observed at allocator returns, not transient native `realloc` memory or physical RAM.
An allocate/resize/size-less-free self-check validates the ledger before any workloads run.

Two local optimised LLVM runs on 2026-10-15 each completed all 88 workloads and 264 snapshot-release ledger checks.
The largest file's prefix-comment workload measured:

| Mode | Run 1 Lifecycle Median / p95 (ms) | Run 2 Lifecycle Median / p95 (ms) |
| --- | --- | --- |
| FULL | 1.3218 / 1.5366 | 1.2646 / 1.4964 |
| TOKENS | 1.1127 / 1.3980 | 1.0763 / 1.3724 |
| AST | 1.1409 / 1.2946 | 1.0811 / 1.3409 |

Here AST-versus-token-only median savings are -0.0282 ms (-2.53%) and -0.0048 ms (-0.45%); p95 savings are 0.1034 ms (7.40%) and 0.0315 ms (2.30%).
Ranges overlap, and these local rounds do not establish a reliable AST-copy advantage.
For the first revision, token-only and AST modes each make 1,774 caller requests totalling 2,823,866 bytes and retain 2,854,463 backing bytes; the old snapshot retains 2,854,433 bytes, giving 5,708,896 bytes of overlap.
Both modes have identical cumulative requested and retained bytes across all 264 profiled revisions, not just this example.
The same example's AST source-acquisition medians are 0.0119/0.0116 ms and old-release medians 0.2073/0.2076 ms; initial construction costs 1.1390/1.0844 ms and final disposal 0.2487/0.2406 ms, separately from updates.
Component medians need not sum to the lifecycle median.
Full reports: [run 1](examples/.build/ast_reuse_measurements.log) and [run 2](examples/.build/ast_reuse_measurements_round2.log).
The fast-backend measurement/profile run and both deep-verification backends also pass all 88 workloads.
The fast run is a harness check, not optimised performance evidence.

For deep correctness and actual reuse counts, compile a separate verification-only executable:

```bash
jai benchmark_ast_reuse.jai -o -llvm -output_path .build -exe verify_ast_reuse - verify-only
./.build/verify_ast_reuse.exe ../../../examples/invaders > .build/ast_reuse_verified.log
```

Repeat with `-x64` instead of `-o -llvm` for the fast backend.
This build skips timing trials and enables `TRACK_AST_REUSE=true`; the default module parameter is false, so both the count field and increments are compiled out of timing builds.
One successful simple or compound declaration copy is one event, including eligible children of matched declaration blocks, not every copied expression or compound target.
The [snapshot oracle](examples/snapshot_oracle.jai) compares concrete tree shape, all reflected node fields/flags/token spans/locations, active literal payloads, complete token metadata/payload bits, diagnostics and related information, synthetic tokens, recovery/restart records, scopes, bindings, ownership links, and exact reconstruction.
A bidirectional object mapping compares snapshot-independent target identities and rejects shared owned objects; allocator capacity/backing storage and generated padding are not compared.
Pointed-to objects are processed through a work queue, avoiding call depth proportional to the program's binding graph; unhandled non-null pointer types, node kinds, and union variants fail explicitly.
Every revision in every mode is compared before and after poisoning the independently owned old source and releasing its tree, names, and pool.
Negative self-checks deliberately alter same-name binding targets, ownership/sharing, child order, flags, spans, locations, literals/tokens, diagnostics/related information, and recovery/restart/synthetic records; a small fixture also verifies an exact simple/compound/nested copy count.
Local LLVM and fast verification both pass 88 sequences (792 edited snapshots and 1,584 before/after-release comparisons per backend), observing 3,705 declaration-copy events in 126 of 264 AST-mode revisions.
Full/token-only modes and recovered old snapshots assert zero copies.
These results cover the selected corpus, settings, and edits, not every possible AST shape or lifetime arrangement.
The worthwhile latency/memory threshold and keep/drop decision remain pending; neither these local measurements nor the correctness counts alone are a decision gate.
Recovered source snapshots must be reported separately because they disable AST copying.

Run `bash clean_build_artifacts.sh` from `examples` after testing to remove generated build outputs.
The script preserves tracked files, symlinks, and retained differential fixtures with their matching outputs.
Use `--dry-run` to preview deletion, or repeat `--resolved jai_parser_differential_<section>_<test>_<serial>.jai` to also remove specific dealt-with fixtures and their outputs.
It targets its own directory regardless of the caller's working directory.

## Lexer

This module starts from `Jai_Lexer` and adds current parser-oriented tokenisation.

The default import retains the original `Token` layout:

```jai
#import "Jai_Parser";
```

`USE_SIMD` defaults to `true`, enabling identifier and line-comment scanning using the widest CPU/OS-supported path on x64: AVX-512F/BW (64 bytes), AVX2 (32 bytes), then baseline SSE2 (16 bytes).
Each scan uses the widest supported width that fits the remaining source and identifier scratch capacity, falling back through narrower widths and scalar tails.
Comment scanning stops before newline and NUL, preserving trivia and location accounting.
Other CPU targets remain scalar.
Use `USE_SIMD=false` to select scalar scanning explicitly.
Benchmarks and parity tests keep their scalar reference imports disabled independently of the default.

```jai
#import "Jai_Parser"(USE_SIMD=false);
```

Runtime detection checks XSAVE, OSXSAVE, and AVX before reading XCR0.
AVX2 requires its CPUID bit and XCR0 mask `0x6` (XMM/YMM state); AVX-512 requires F/BW and XCR0 mask `0xE6` (XMM/YMM/opmask/ZMM state).
AVX-512VL and AVX-512DQ are not required.
Supported features are atomically cached per module instance and retained in one per-lexer feature mask.
Loads are bounded, `bsf` runs only on nonzero stop masks, and BMI1 is not required.
The wider no-inline helpers end with `zeroupper`; keeping the identifier classifiers out-of-line prevents LLVM from interleaving legacy SSE spills/shuffles with wide vector instructions.

AVX-512 compiles under both the fast and LLVM backends, and unsupported-host corpus fallback passes full-token parity.
Its emitted ZMM/mask instruction sequences have been inspected.
A user-provided three-round collection on Ryzen 5 7600X / Windows 10 / Cygwin (2026-10-14, Jai beta 0.2.030) confirms AVX-512 CPU/OS availability, fast and LLVM classifier/token/comment parity, and complete corpus token parity for all modes.

Historical forced-width measurements, before consolidating the options: median of the three rounds' elapsed reductions versus each mode's own scalar baseline:

| Mode | Invaders | how_to |
| --- | ---: | ---: |
| SSE2 | 2.51% | 1.66% |
| AVX2 | 0.38% | 1.24% |
| AVX-512 | 0.80% | 2.26% |

The reported trial ranges overlap, and scalar baselines vary by mode; do not interpret separate absolute timings as a controlled backend ranking.
These results validate AVX-512 execution but do not establish a worthwhile advantage over SSE2; gains remain workload-dependent even though automatic SIMD dispatch is now enabled by default.
The remote Invaders corpus matches the earlier counts (8 files, 75,331 bytes, 11,344 tokens); its `how_to` corpus differs (84 files, 823,387 bytes, 46,576 tokens), so cross-machine comparisons are not identical-corpus measurements.
Actual clock-frequency effects were not measured.

The tested Core Ultra 5 135H supports AVX2 with OS vector-state support, but not AVX-512F/BW.
Fast and LLVM builds pass direct SSE2/AVX2 classifier and automatic SIMD token/comment parity tests.
An initial large regression was traced to LLVM auto-inlining the identifier classifier and inserting legacy SSE spills/shuffles between YMM instructions, before `zeroupper`.
Function-scoped `no_inline` prevents that interleaving without disabling other inlining.
A subsequent optimised run measured scalar/AVX2 medians of 3.984/3.881 ms for Invaders and 18.459/17.742 ms for `how_to` (2.6% and 3.9% less elapsed time).
Ranges overlap, and a separate SSE2 run also shows small gains; an AVX2 advantage over SSE2 is not established.

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
By default, standalone lexers copy identifier and note names.
A caller can optionally provide `Identifier_Storage` with `set_identifier_storage(*lexer, *storage)` to intern these names without a shared table or lock.
The caller must keep the storage and borrowed source buffers supplying its names alive while those names are used.
For lexer-owned file input, identifier and note spellings are copied into the supplied storage, not the whole input.
Resetting the lexer frees its old file input: stored identifier names remain valid, but token `original_text` and trivia still point into the freed input and become invalid.
For string input, unchanged interned identifier spellings may also borrow the caller's buffer; keep it alive until the storage is released.
`release_identifier_storage(*storage)` frees the table and fallback pool after all names are no longer used.
Calling `set_identifier_storage(*lexer, null)` stops interning identifiers lexed from then on: each new identifier name is copied instead.
Names in tokens already produced keep their original ownership and lifetime.

Structured trivia is available through a `for_expansion`:

```jai
for trivia, offset: make_trivia_iterator(token.preceding_trivia) {
	// trivia.kind, trivia.text, trivia.offset
}
```

Trivia kinds are `WHITESPACE`, `LINE_COMMENT`, `BLOCK_COMMENT`, `SHEBANG`, and `IGNORED`.
`IGNORED` represents source bytes deliberately skipped by the lexer outside the other categories, such as NBSP, zero-width space, and bidi formatting controls.

## Materialised Parser Tokens

`materialise_tokens(source)` copies the lexer's ring-buffer tokens into a stable parser-owned array.
It also recognises `#string` directives, so their bodies are represented by the same string token the parser will consume.

The returned `Parsed_Source` borrows `source`. By default, its lexer copies identifier names; no per-file identifier table is populated.
Parser callers are expected to keep the source allocation alive and unchanged while using its tokens and syntax tree; the parser does not provide an owned-copy mode.
The experimental `#import "Jai_Parser"(ENABLE_TRIVIA=true, INTERN_IDENTIFIERS=true)` instead gives each parsed source an independent identifier table: unchanged spellings can borrow source bytes, while normalised spellings use a fallback pool. Benchmarks favour copying as the default because interning increases retained memory on unique-name and `how_to` inputs.
`release_parser_tree` frees only the AST node pool; the token array and identifier storage belong to `Parsed_Source` separately, so retained tokens can still be inspected after the tree is released.
With interning enabled, call `release_parser_names(*parsed)` after releasing the tree and finishing with identifier names; it frees the table and fallback pool, invalidating those names.
Neither release function frees the caller's source or makes source-backed token text and trivia independent of it.
In the default copying mode, `release_parser_names` has no names to release; copied names retain the lexer's original allocation behaviour.
Standalone lexer tokens continue to own copied names unless optional storage was supplied.

With `ENABLE_TRIVIA=false`, `Parser_Token` aliases `Token`.
With trivia enabled, it extends the lexer token with a stable index and absolute, half-open byte boundaries.
`reconstruct_source` rebuilds the original source from the materialised token and trivia views.

## Syntax Tree Source Spans

`Parser_*` syntax node types form a parser-owned hierarchy with `Parser_Node` as their common base.
`Parser_Node` embeds the public `Code_Node` fields so common compiler metadata such as kind, flags, type, and location remains directly accessible.
Concrete parser nodes intentionally have their own layouts and parser-owned child pointer types; they must not be reinterpreted as concrete compiler `Code_*` nodes.

When trivia is enabled, every parser node directly contains `first_token` and `one_past_last_token`.
Together these fields identify the node's half-open token span without a table lookup.

AST nodes and parser-created child arrays share the `Pool` embedded in `Parsed_Source`.
Use `parser_node_allocator` for child arrays and `release_parser_tree` to invalidate and release the complete tree while retaining the materialised tokens and diagnostics.

## Complete File Parsing

`parse_file(source, fully_pathed_filename="")` parses declarations through end of input and returns an unparenthesised `Parser_Block` with block type `DATA_DECLARATIONS`. `Parsed_Source.fully_pathed_filename` preserves the caller-provided source identity; like `source` and token text, it is borrowed and must outlive the parsed result.

File parsing retains successful declarations around multiple malformed regions.
Truncated declarations remain in the partial tree and produce `INCOMPLETE`; recoverable syntax errors produce `RECOVERED`.
Empty input still returns a non-null, zero-width file block.

`examples/parse_how_to.jai` is the initial compatibility corpus.
It parses every `.jai` file under `how_to`, asserts a non-fatal file root and exact trivia round trip, and reports files that currently require recovery so unsupported syntax remains visible as parser coverage expands.
Its summary aggregates diagnostic kinds, expected and actual tokens, and recovery actions, followed by the structured first diagnostic for each affected file.
Zero-diagnostic file counts are reported separately from recovery and diagnostic totals, including the count of files recovering without a parser diagnostic.
ASCII-backed token kinds are rendered as source spellings and absent token fields as `<none>`.
The checked-in corpus baseline records relative filenames and diagnostic counts. Each run reports newly complete or newly recovering files, per-file improvements and regressions, and removed and added diagnostics separately.
The suggested next grammar candidate groups only the first diagnostic from each recovering file, avoiding recovery-cascade counts when prioritising work.

## Expression Parsing

`parse_expression(source)` currently parses identifiers; primitive number, string, boolean, and null literals; typed and untyped array and struct literals; here strings; the `---` do-not-initialise indicator; `context`; grouped expressions; prefix unary operators (including unary dot); binary operators; calls with positional and named arguments; member access; array subscripts; postfix pointer dereferences; casts; and expression and type queries.
The closing delimiter of a `#string` literal also terminates its containing declaration without requiring a semicolon; ordinary string declarations still require one, and an explicit semicolon after `#string` remains accepted.
In calls, `,,` separates ordinary arguments from temporary context replacements.
`Parser_Procedure_Call.context_modification` retains the source-spelled replacement expressions separately from `arguments_unsorted`, including named assignments and shorthand allocator values.
Postfix forms compose left-to-right, so calls, access, subscripts, casts, and dereferences can be chained.

Expression directives are described in the dedicated directive section below.
The resulting parser-owned node is returned in `Parsed_Source.root`.
Empty or truncated input returns `INCOMPLETE`; unsupported or trailing syntax returns `RECOVERED` with a structured diagnostic.

The compiler exports `value := ---` with a null declaration expression and `IS_UNINITIALIZED`.
Standalone `---` is retained as a parser-owned `Parser_Literal` with `value_type == .UNINITIALIZED`; it has parser-shape tests but no direct `compiler_get_nodes` expression comparison.

Binary parsing uses the precedence classes derived by `../../print_precedences.jai`.
The expression parser preserves assignment-operator trees for compiler AST comparison and recovery; later statement parsing will own their statement-level semantics.
The differential suite covers every binary and assignment operator exposed by `Operator_Type`, compares every pair of precedence classes in both operand orders, and checks same-class associativity.
Ambiguous prefix, postfix, and parenthesised combinations are compared separately; unary dot binds to its immediate primary before later postfix access, as in `(.member).field`.

`parser_peek`, `parser_eat`, `parser_checkpoint`, and `parser_restore` provide the initial cursor API.
Materialised tokens can also be navigated with `token_at`, `previous_token`, and `next_token`.

## Type And Declaration Parsing

`parse_declaration(source)` parses typed, inferred, constant, uninitialised, and compound declarations.
Compound declarations preserve their left-hand names as parser-owned comma-separated arguments and represent multiple initialiser expressions with a `Parser_Comma_Separated_Arguments` node.
In statement blocks, `out1, out2 = hello(1)` also produces a `Parser_Compound_Declaration`, matching the compiler's AST: it has two names and one right-hand expression, unlike comma-separated declaration initialisers.
Comma-separated assignment targets may also be indexed or member expressions, including compound operators such as `+=`; these use the same compiler-matching node shape.
Multiple right-hand expressions are retained as comma-separated arguments.
Mixed forms such as `a=, b := proc()` and `a:, b = proc()` retain per-target `ASSIGN` and `DECLARE` modifiers in `comma_separated_assignment.arguments`; only targets declared by the form are added to the local scope.
A missing right-hand expression leaves a recovered compound node and allows the next statement to parse.

Supported types include named types, pointers, fixed arrays, array views, resizable arrays, procedure types, polymorphic variables with restrictions, and `#type` with `distinct` or `isa`.
Procedure types accept unnamed parameter types (including nested procedure, pointer and array types), empty `-> ()` return lists, and the source-spelled `#Context` type directive.
Procedure headers retain the source-spelled `#dump` modifier as `DEBUG_DUMP`.
The compiler emits a procedure's bytecode when compiling it; the parser only records the syntax flag.
Declaration metadata includes `$` and `$$` auto-bake flags, backticked scope modifiers, `#align` expressions, do-not-initialise flags, and trailing notes.
Source-spelled `#no_reset` is a declaration attribute, not a scope directive: the parser records it as the compiler-matching `NO_RESET` flag.
For global variables, it retains compile-time values at runtime.
Truncated prefixes report an incomplete parse.

Declaration and type normalisers compare parser nodes with compiler nodes inside intercepted child workspaces.
These comparisons include flags determined by source spelling, not flags such as `IS_GLOBAL` that the compiler assigns from a procedure's placement or later processing in the workspace.
The standalone syntax parser does not have that compiler context, so comparing those flags would report differences that do not reflect a parsing error.

## Statement And Block Parsing

`parse_block(source)` parses imperative brace blocks, while `parse_declaration_block(source)` restricts a brace block to declarations and marks it as `DATA_DECLARATIONS`.
Explicit braces carry the compiler-compatible `IS_PARENTHESIZED` node flag; single-statement control-flow bodies are represented by unparenthesised parser-owned blocks.

Supported statements include expressions, declarations, multi-value returns, `while`, collection and range `for`, `if`, expression-form `ifx`, switch-style `case` (including a terminal bare `case;`), `defer`, `using`, `push_context`, `break`, `continue`, and `remove`.
Value-form `ifx` may omit its `else` branch; its parsed node retains a null `else_block`, so the compiler can supply the result type's default value.
It may also omit the `then` branch when `else` follows the condition immediately; the parsed node then retains a null `then_block`.
Both value branches may be omitted when the condition ends at an expression boundary; the parsed `ifx` retains null `then_block` and `else_block` nodes.
Expression-form `#ifx` uses the same value branches and retains both `IS_STATIC` and `IS_IFX` flags.
Statement-leading `#this(...)` calls use expression parsing, so their postfix arguments are retained, including inside block-bodied quick lambdas.
Call-level `inline` and `no_inline` prefixes set `INLINE_YES` and `INLINE_NO` on procedure-call nodes, including calls inside static branches.
Parenthesised `if` and `while` conditions remain expressions before a braced body, including comparisons, modulo and logical operations, and bare pointer truth tests; typed procedure headers retain their own syntax.
Declarations initialised by `ifx` with braced `then` and `else` value branches can omit the trailing semicolon before the next statement.
When present, the semicolon terminates that declaration; it does not create a separate empty statement in the compiler-shaped AST.
This includes named loop conditions and iterators, named for-expansion selectors, independently combined literal reverse and pointer iteration flags, `#complete`, `#through`, backticked return/defer, and `push_context,defer_pop` forms.
Pass `warn_unnecessary_semicolons=true` to a parse entry point to report a `WARNING` diagnostic with kind `UNNECESSARY_SEMICOLON` for explicit trailing semicolons that can be omitted, including `#through;`.
The default is `false`; required terminators are not warned. Warnings point to the semicolon token and do not change parse status or create recovery records.
This option does not diagnose extra standalone semicolons.

Blocks retain parent and owning-statement links.
Statement recovery inserts missing semicolons without consuming the next statement, synchronises at statement starts and closing braces, and synthesises a closing brace for truncated input.

## Procedure And Aggregate Parsing

Procedure definitions reuse the procedure-type header parser and attach parser-owned `Parser_Procedure_Body` and `Parser_Block` nodes.
Headers preserve named, polymorphic, `using`, defaulted, and vararg parameters; named or unnamed returns; foreign library and symbol names; and written flags such as `inline`, `#expand`, `#compile_time`, `#no_context`, and `#c_call`.
Operator declarations use the same declaration and procedure nodes, retaining exact names for unary and binary operators, compound assignments, and `[]`, `[]=`, or `*[]`; procedure modifiers and bodies follow the ordinary header path.
Focused and compiler differential fixtures cover all 39 overloadable lexer spellings: the single-character arithmetic, comparison, logical, and bitwise operators; equality, ordered comparison, logical, shift, and rotate operators; every corresponding assignment token; and the three subscript forms.
User overloads of `=` and `.` are the two excluded spellings.
Quick procedures support zero, one, or multiple inferred parameters and both expression and block bodies; expression bodies contain a synthetic return marked `AUTO_INSERTED_FOR_QUICK_LAMBDA`.

`Parser_Struct` represents both structs and unions, with `.UNION` in `textual_flags`.
Parameterized aggregates retain their parameter declarations in a `STRUCT_ARGUMENTS` block, while fields and constants remain in the `DATA_DECLARATIONS` body.
Declaration-form `using` fields retain the wrapped struct declaration whose subfields become accessible in the containing scope.
Both `#as using field: Struct_Type` and `using #as field: Struct_Type` mark that declaration with `IS_MARKED_AS_AS`, preserving the field selected for implicit casts to and from the containing aggregate.
`using,except` and `using,only` retain their compiler-compatible filter type and expression on struct fields, statements, named imports, and procedure parameters.
`using enum u16 { ... }` ends at its closing brace or an explicit semicolon before the next statement; ordinary `using` expressions still require a semicolon.
Parenthesised name lists become arrays of string literals, while array literals, named arrays, and `#run` expressions remain source-spelled filter expressions.
`using,map(expression)` retains its parenthesised expression as a `.MAP` filter.
The advanced-using guide parses completely with zero syntax diagnostics.
`resolve_file_imports` applies mappings when the caller supplies `map_names`; it does not execute Jai map procedures.
For aggregate values whose fields cannot be recovered from parsed syntax, the optional `aggregate_fields` callback can supply a complete list of `Parser_Binding` records, including generated fields.
Return `true` only for a complete list; returning `false` discards the list and tries parsed struct fields.
Each binding needs a nonempty name and a declaration pointer that the caller keeps alive through `release_file_imports`.
The result copies source and exported names, but does not own declarations.
Without a usable field list, the exposure remains in `unsupported_using_filters`.
Aggregate field default assignments such as `w: float; w = 1;` and `info.flavor = "chocolate";` remain ordered binary-expression statements.
Bare assignment identifiers and the base identifiers of dotted assignments link back to their matching parser-owned field declarations, including `#as using` fields.
`Parser_Enum` represents enums and enum flags, including underlying types, `#complete`, `#specified`, explicit values, and bare members.
Bare enum members also retain their identifier nodes inside braced, nested, and single-statement static `#if` branches.
Interface constraints use the compiler's `$T/interface Constraint` type-instantiation form and set `.INTERFACE`.

Aggregate layout modifiers preserve the compiler's textual flags.
Trailing notes remain attached to the containing declaration, matching the raw compiler AST.
Direct differential comparisons omit asynchronous procedure body pointers and semantically finalised aggregate alignment; focused parser tests cover those parser-owned fields.

## Directive Parsing

The parser has a parser-owned counterpart for each of the 20 public `Code_Directive_*` structures: through, overlay, procedure name, load, bytes, code, poke name, add context, context type, location, library, wildcard, exists, insert, run, import, modify, scope, module parameters, and bake.

Source parsing covers:

- `#char "x"` as the compiler-compatible numeric `Parser_Literal`, using the lexer's evaluated string byte; `#filepath` as a string literal containing the directory of `fully_pathed_filename`; and payload-free `#this` as the compiler's `DIRECTIVE_THIS` node kind.
- `#caller_code` as `Parser_Directive_Code` with the compiler's unnamed caller-code flag and a null expression.
It is accepted as a primary expression, so legal macro default arguments retain the compiler AST shape.
- `#if` in imperative, file, and aggregate declaration contexts, represented by `Parser_If` with `IS_STATIC`; its branch blocks retain the surrounding block mode, including enum member grammar.
- `#placeholder Name` file declarations, represented by `Parser_Placeholder` with the source-spelled name.
This is distinct from the `---` do-not-initialise indicator.
- Prefix `#as using name: Type` aggregate fields and the equivalent `using #as name: Type` spelling, represented by `Parser_Using` around a declaration marked `IS_MARKED_AS_AS` for implicit casting.
- `#asm` statement blocks with optional feature names.
`Parser_Asm` stores ordered parser-owned `Parser_Asm_Feature` records, a balanced body token span, and ordered `Parser_Asm_Statement` nodes without overlaying the compiler's opaque payload fields.
Each feature retains a `Parser_Ident` and an exact token span; bare blocks retain an empty feature list.
`enclosing_scope` points to the surrounding high-level `Parser_Block`, so sibling assembly blocks share one scope while assembly braces do not create a lexical scope; register binding remains deferred to semantic analysis.
Generic statement dispatch accepts `#asm` directly in single-statement control-flow branches, including `#if ... #asm { ... } else #asm { ... }`, while retaining that surrounding scope.
Identifier-led instruction statements retain an open-ended mnemonic, optional fixed or polymorphic `Parser_Asm_Mnemonic_Size`, and top-level comma-separated operand spans; operand internals remain `UNPARSED`.
Missing terminal semicolons are diagnosed at the closing brace.
Parser-owned register declaration, register pinning, memory operand, value, and source-spelled modifier records preserve exact token spans.
The ordinary lexer stream is lossless for the assembly grammar: `===` is one token; fixed mnemonic suffixes such as `.8` and `.64` are leading-dot `NUMBER` tokens; polymorphic suffixes such as `?BITS` and `?T` are `?` plus `IDENT`; signs, `!`, `&`, `&*`, brackets, and declaration colons remain ordinary tokens; comments remain trivia.
No contextual assembly tokens are introduced, so ordinary member access and query tokenisation remain unchanged.
- `#code`, `#code,null`, and `#code,typed`, preserving expression, declaration, and block payload node kinds.
- `#run`, `#run,stallable`, and `#run,host`, with expression or block payloads, including `-> Return_Type { ... }` bodies.
Expression payloads set `HAS_IMPLICIT_RETURN_TYPES`; block payloads do not.
Typed blocks retain their procedure header and return declaration.
A block-form `#run` ends at its closing brace in a statement or declaration; a semicolon is optional there but remains required for expression-form `#run` statements.
`host` uses the compiler's unnamed `0x10` run flag and is mutually exclusive with `stallable`.
- `#assert condition` with an optional quoted message, lowered to `Parser_Directive_Run` with `ASSERTION` and `HAS_IMPLICIT_RETURN_TYPES`; the condition remains its expression and the message is retained in `assertion_string`.
This works in procedures, static branches, expansions, and module scope without executing assertions in the parser.
- `#insert`, optional scope and loop-control replacements, and `-> Return_Type { ... }` implicit-run bodies.
An empty `scope()` retains a null scope redirection; `scope(expression)` retains the expression.
Block-bodied short-form inserts terminate at the closing brace without a required semicolon; expression-form inserts still require one as statements.
- `#import` with `file`, `dir`, or `string`, plus module and program parameter calls.
`#import,string` accepts a quoted string or a `#string` here-string body; a standalone import requires a following semicolon, including after a here-string delimiter.
- `#library` with `system`, `no_static_library`, and `link_always`.
- `#load`, `#bytes`, `#procedure_name`, `#exists`, location and caller-location queries, and poke-name forms.
- `#procedure_of_call target(arguments)` as a `Parser_Procedure_Call` marked `RETURNS_PROCEDURE_POINTER_ONLY`, matching the compiler for ordinary and type-valued arguments.
- `#through`, `#overlay`, `#add_context`, `#modify`, `#scope_export`, `#scope_file`, and `#module_parameters`.
- `#bake_constants` and `#bake_arguments` call forms.

The raw compiler AST exposes a few distinctions that are not named source flags.
File and directory imports set an unnamed `0x4` bit, while string imports set `UNSHARED`. `link_always` is accepted but does not set `LINK_ALWAYS` in raw syntax trees.
`DYNAMIC_LIBRARY_UNAVAILABLE`, implicit code, run assertion metadata, insert expansion, wildcard indices, and internal scope are assigned during later compiler processing.

`Code_Asm` is public only as an opaque layout containing `b1`, `b2`, and `b3`; instruction, operand, and register data are not exposed to high-level metaprogramming.
The parser recognises instruction envelopes with mnemonics, optional size suffixes, and comma-separated operand spans; operand internals such as registers, memory addressing, and modifiers remain `UNPARSED`.
It also preserves the full assembly body as source.
Compiler comparisons cover the `.ASM` node kind and surrounding tree placement, not the opaque compiler payload or parser-owned operand internals.

`Code_Directive_Context_Type` has no source payload; its source spelling is `#Context`, while the compiler rejects `#context_type` as a source directive.
Standalone `#wildcard` and generic `#bake` are likewise rejected by the current compiler; parser-owned forms remain available for editor recovery and public-node handling.
`DIRECTIVE_THIS`, `DIRECTIVE_PLACE`, and `DIRECTIVE_COMPILE_TIME` have no corresponding public `Code_Directive_*` structure; their syntax is represented through other nodes or compiler processing.

Differential fixtures compare every compiler-accepted expression or contextual form available through `compiler_get_nodes`.
Scope and add-context use child workspaces because they are file-only.
Module parameters are validated by compiling the parser module itself, since compiler-added strings are not module-file scope.
Focused tests cover parser-owned fields that compiler messages omit, including modify ownership, poke-name source expressions, module-parameter bodies, wildcard placeholders, and implicit insert-run procedure headers.

## Error Recovery

The source token array is immutable after materialisation.
When a required token is absent, the parser records a zero-width `Synthetic_Token` at the current token boundary and adds a `Parse_Diagnostic` describing the expected and actual token and the recovery action.
Synthetic tokens are kept separately from source tokens, so token indices remain stable and `reconstruct_source` always reproduces only the original input.
`Parsed_Source.recovery_records` is the syntax recovery sidecar; it does not change the compiler-shaped AST.
`MISSING_TOKEN` points to a synthetic token, `EXPECTED_EXPRESSION` marks a missing or invalid expression, `SKIPPED_TOKENS` covers consumed source, and `ERROR_SPAN` marks erroneous source retained in the tree.
Each record has a half-open token span and a diagnostic index; `-1` means a synchronisation or progress skip without its own diagnostic.
The synthetic-token index is `-1` except for `MISSING_TOKEN`.
`release_parser_tree` frees the AST node pool and clears `root` and `root_scope`, but does not free the token, synthetic-token, diagnostic, or recovery-record arrays in `Parsed_Source`.
For example, a retained `MISSING_TOKEN` record still identifies its insertion boundary and indexes `synthetic_tokens` and `diagnostics`; a `SKIPPED_TOKENS` span still identifies the skipped source tokens.
Keep the parsed result and its arrays while following those indices, and keep the borrowed input unchanged while reading token text, trivia, or source bytes at those spans.
Tree nodes and binding links cannot be accessed after tree release.
The parser supplies the lexer's optional `error_callback` and `detail_callback` during materialisation, so lexer errors become `Parse_Diagnostic` entries with kind `LEXER_ERROR`, a token anchor, and the exact `lexer_line` and `lexer_column` of the error.
Subsequent lexer details are retained as `related_information` on the preceding lexer diagnostic.
These diagnostics do not imply a syntax recovery record; `RECOVERED` still reflects the lexer's `reported_error` state.
Standalone lexer callers can omit the callback and retain the lexer's direct error logging.
`Parsed_Source.restart_points` retains `DECLARATION` and `BLOCK` anchors as half-open spans of completed syntax nodes, including recovered nodes and the empty file root.
The first token is the candidate restart position; the end marks the node's parsed extent (a parent may consume its semicolon separately).
Nested nodes are recorded before their parents, so callers should not assume source order.
For example, after `release_parser_tree` you can still use a declaration restart point's `span.first` to find its first token in the original `Parsed_Source`; the AST node and its scope are gone.
Restart points identify locations in that parse snapshot only.
They do not store the enclosing grammar or scope needed to parse a declaration independently, and the parser currently reparses the whole source after an edit rather than reusing old tokens or AST nodes.

Each `Parse_Diagnostic` has a primary token span and message.
Its `related_information` slice can contain zero or more additional span/message pairs, matching the compiler's convention of reporting an `Error:` location followed by related `Info:` locations.
`render_diagnostic_line` expands tabs to 4-column tab stops and returns the expanded source line plus a caret line covering the diagnostic's exclusive column range.
Repeated parses of the same immutable incomplete source produce the same ordered structured diagnostics and synthetic-token positions.
Errors at already present tokens keep their locations as more source is appended; EOF insertion and expected-expression diagnostics may change when the missing input arrives.
A concrete syntax error takes precedence over EOF incompleteness in `RECOVERED` status.

Recovery loops use `parser_progress_guard` and `parser_ensure_progress`, so a failed parse cannot repeatedly inspect the same non-EOF token.
`parser_synchronise` defines restart boundaries for expression, statement, declaration, and block contexts.
Synchronisation stops before the boundary token so its enclosing parser remains responsible for consuming delimiters such as `,`, `;`, `)`, `]`, and `}`.
For example, when recovering an expression in `bad(inner; still_inner); next`, the semicolon inside `(...)` is not a restart boundary: synchronisation skips past the closing `)` and stops before the outer semicolon.
The same depth check prevents separators inside `[...]` or `{...}` from ending recovery in the surrounding context.
Completing a recovered braced region returns control to the owning expression, statement, or declaration parser, preventing its contents from being reinterpreted in an enclosing scope.

Focused recovery fixtures cover selected section 13.1 truncations and malformed trailing text after `#this`, `#filepath`, and `#caller_code`.
They check nonfatal partial trees and selected flags, child counts, or diagnostics.
Separate synchronisation fixtures check that later declarations remain in their enclosing scopes; these tests do not cover every malformed form of each construct.

## Lexical Bindings

`Parsed_Source.root_scope` owns a tree of `Parser_Lexical_Scope` records for the file, procedure headers, blocks, aggregates, and case arms.
Each scope retains its parent, owning syntax node, declarations made there, and ordinary identifier uses found there.
Named parameters and returns belong to the procedure scope; body blocks nest beneath it.
Compound declarations add their declared names to the scope; reassigned targets do not declare new names.
Once parsing has collected all names, each ordinary identifier use is matched by spelling against declarations in its own scope, then the nearest enclosing scope.
For example, `forward := later; later :: 3;` links the use of `later` to the later declaration, and an inner `local` shadows an outer `local`.
This lookup does not require a declaration to precede its use and does not check whether that use is semantically valid.
Successful matches set `Parser_Ident.resolved_declaration`.
A use with no matching local declaration remains null; names after `.` (such as `field` in `object.field`) are not looked up in lexical scopes because their meaning depends on the receiver's type.
An unmatched name is not a parse error: it could come from an import, `using`, a built-in, or generated code.
Deciding whether it actually exists requires the name-resolution and typechecking work in section 17, so this pass neither diagnoses missing names nor resolves imports, overloads, polymorphic uses, or generated names.
The scope tree, binding targets, and resolved identifier links use the node pool; `release_parser_tree` invalidates them and clears `root_scope`.
Bindings are never transferred to an edited snapshot; the old snapshot's bindings remain valid until its tree is released.

## Edit Snapshot Lifetime

There is no in-place edit.
Trivia-enabled file edits can reuse unchanged, semicolon-terminated top-level declarations whose values contain only identifiers, numeric/string/boolean literals, `!`/`~`/`-` unary operators and postfix dereferences, arithmetic binary operators, member access, array subscripts with reusable base and index expressions, calls of those expressions (including named arguments and `,,` context replacements), explicit casts with identifier or single-pointer-to-identifier targets, and array/struct literals with reusable members and at most an identifier type, outside the edited byte range when their full token spans and following semicolons still match.
The same eligible declarations can be copied inside matched nested declaration blocks when the opening brace is unchanged; each new block still receives a fresh lexical scope, and edits touching its opening brace disable that pairing.
Declarations with a one-identifier or single-pointer-to-identifier type annotation and eligible value, or with no initialiser, can also be copied; their type wrappers and references are rebuilt in the new pool.
Explicit `---` initialisers still fall back.
Exact constant compound declarations with two or more unmodified names and an eligible value are copied with new argument storage and shared binding properties.
Typed compounds with a one-identifier or single-pointer-to-identifier annotation reuse their type wrapper and bindings with an eligible value or no initialiser.
Exact compound reassignments with unmodified identifier targets and an eligible RHS reuse without declaring new bindings; explicit `---` initialisers, mixed or non-identifier targets, metadata-bearing, and richer typed compounds still parse normally.
More complex type annotations and other declaration shapes still parse normally.
For file edits, `parse_file_edit(*old, start, end, new_source, warn_unnecessary_semicolons=false)` returns `(Parsed_Source, bool)`.
`[start, end)` is a half-open byte range in `old.source`; `new_source` is the caller-owned, complete replacement buffer.
The call succeeds only if the range is in bounds and `new_source` retains the old bytes before `start` and after `end`; the bytes between them are the inserted text.
On failure, it returns an empty result and `false` without parsing.
On success, it returns a new parse and `true`, retaining the old filename; pass the warning option explicitly if it was enabled on the old parse.
With trivia enabled, a clean old parse can copy remapped prefix tokens, re-lex from before the edit, and copy a shifted suffix once tokenisation converges.
Lexer errors continue lexing to EOF; old parses with diagnostics or contextual here-string bodies, and imports without trivia byte spans, use full lexing.
Non-trivia file edits take the full lex and parse path; focused declaration-note and compound-declaration fixtures compare them with fresh parses.
Eligible declarations and their expression subtrees, including call arguments, context replacement arrays, and aggregate member/type records, are copied into the new node pool with remapped names and decoded strings plus shifted token spans; member and named-argument labels remain non-lexical.
Other AST shapes are parsed from the resulting tokens.
Scopes, bindings, references, and parser diagnostics are rebuilt in every case.
Byte offsets are canonical: editor line/column coordinates must be converted against the old source before calling this API (no conversion helper exists yet).
Retain the old buffer unchanged for as long as its parse result is used; the two results are independent and can coexist.
`source`, `fully_pathed_filename`, original token text, trivia, and some opt-in interned names are borrowed views.
Do not overwrite or free their backing bytes while the corresponding views are needed.

Token indices, byte offsets, node spans, synthetic insertions, recovery records, diagnostics, and restart points belong to exactly one snapshot.
Even if an index or byte offset has the same value after an edit, it must not be applied to the replacement's tokens without recomputing it.
An edit invalidates the *old result as a representation of the current file*, not the old allocation itself; copied tokens have new source views and identifier storage, and no nodes, scopes, or bindings are shared with the old result.

All AST nodes, child arrays, lexical scopes, binding records, and `Parser_Ident.resolved_declaration` targets are pool-owned.
`release_parser_tree` frees them together, clears `root` and `root_scope`, and invalidates any caller-retained pointers into that pool.
Materialised tokens, diagnostics, and token-based recovery/restart records remain readable after tree release while their storage and borrowed source are retained.
With opt-in interning, release the tree before the identifier storage because tree nodes can reference interned names.
Keep the caller's source alive while using any source-backed token text, trivia, or borrowed identifier names, even if the tree has already been released.
Release an old snapshot's resources independently of its replacement.

## Differential Tests

`examples/differential_test.jai` normalises parser and compiler ASTs into path-keyed syntax fields and reports every structural mismatch.
Its `assert_expression_fixture` macro accepts source text once and generates the matching `#code` argument with `#insert`, preventing the parser input and compiler oracle from drifting apart.
The harness keeps syntax and semantic normalisation separate, provides trivia round-trip fixtures, and includes intercepted child-workspace fixtures for typechecked declarations and file-level constructs.

On Windows, use the Jai-only parallel runner.
It runs batches in fresh compiler processes to avoid suite-wide memory buildup.
Do not run the whole `differential_test.jai` harness directly: that unbounded invocation can exhaust RAM.
No PowerShell is required.
Have `jai` on `PATH`; workers use the checkout's `bin/jai.exe`, and diagnostic fixtures invoke `jai`.

From `modules/Jai_Parser/examples`, build and run the full suite in Bash:

```bash
jai differential_runner.jai -x64
./differential_runner.exe --all
```

`--all` includes both compile-time fixtures and all eight runtime checks; no separate runtime command is needed.
The runner requires an explicit mode or section, not an implicit full-suite default.

For section discovery, focused runs, or runner self-tests:

```bash
./differential_runner.exe --list
./differential_runner.exe 5
./differential_runner.exe "Numeric rankings"
./differential_runner.exe "Numeric rankings" --first 17 --last 48
./differential_runner.exe --self-test
```

Select a section by number or exact, quoted name.
Fixture ranges are inclusive and supported only for batchable sections.
Selecting `"Runtime checks"` compiles and executes that section automatically.

- `--workers` accepts 1..4 (default 2); use `--workers 1` for serial scheduling.
- `--batch-size` accepts 1..16 (default 16) for the nine batchable sections; other sections run whole.
Worker count and batch size are the normal memory controls.
- `--memory-mib` defaults to 2048: a 2 GiB commit safety limit per process tree.
Hitting the cap is a failure, not a successful batch boundary.
- `--timeout` defaults to 30 seconds per compile/runtime phase or idle admission wait, not per full suite.
- `--reserve-mib` defaults to 2048 for physical/commit headroom.
Low headroom can reduce concurrency.

The first failure or Ctrl+C stops scheduling and terminates active worker trees.
Exit codes are 0 for success, 1 for test or runner failures, 64 for invalid arguments, 75 for insufficient headroom, 124 for timeouts, and 130 for cancellation.

Logs are saved under `examples/.build/differential_runs` in a fresh directory per run.
Each job has isolated working, build, fixture, and `TEMP`/`TMP` directories, plus `job.tsv`, `compile.log`, and, when applicable, `runtime.log`.
Failed fixtures and build files are preserved; successful build/temp artifacts are removed.
`summary.tsv` records coverage, elapsed time, job commit peaks, and sampled system headroom.

Verified locally on 2026-10-13 with the defaults: all 24 sections / 4,175 fixtures passed in 252 jobs in **5 minutes 12 seconds**, with no timeouts or cap failures.
The largest job commit peak was 1.75 GiB, minimum sampled available RAM was 5.14 GiB, and runtime checks retained zero allocations/bytes.
The identical 594-fixture `Numeric rankings` workload took 63.4 seconds serially versus 39.6 seconds with two workers (about 1.60x faster).
These are local measurements, not universal guarantees.

ANSI-coloured progress shows the original section number, the current test within that section, and the cumulative test count for the selected run.
A shared inventory supplies totals across compile-time and runtime checks; nested compiler calls count only once within their parent test.

On assertion failure, the harness prints the retained fixture path.
Diagnostic fixture files remain available until the next test starts, so a failure in the caller also preserves the compiler input.
In-memory workspace and syntax fixtures are saved on failure.
Retained files use `jai_parser_differential_<section>_<test>_<serial>.jai` in the working directory; retries choose an unused serial rather than overwriting an earlier failure.
Successful fixtures are cleaned up.

For invalid-source fixtures, `capture_compiler_error` writes the supplied code to a temporary fixture, invokes `jai -x64`, and returns structured primary diagnostics with their related information.
`assert_compiler_error_message` and `assert_invalid_expression_compiler_message` provide concise assertions for common cases; pass `log_output=true` to `capture_compiler_error` when the complete compiler rendering is useful.
Captured compiler locations use exclusive `l0`, `c0`, `l1`, and `c1` ranges; the redirected caret run determines the end column.
Compiler fixtures must use spaces because the compiler currently aligns carets as though each source tab occupied one column.
