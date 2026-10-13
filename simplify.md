# Jai_Parser complexity analysis

The module is about 38.7k lines.  Production code is 11.8k of that: `parser.jai` has 6,796 lines, `resolution.jai` 2,680 and `lexer.jai` 2,350.  Tests and harness code add 24.3k: `examples/parser_tokens_test.jai` has 15,467 lines, `examples/differential_test.jai` 4,969, `examples/test_fixtures.jai` 2,674 and `examples/differential_runner.jai` 1,192.

Most of the extra size comes from three features, not from the core grammar.  Each feature carries a matching block of tests:

| Feature | Production lines | Test lines it drives |
|---|---|---|
| AST reuse after an edit | ~900 | ~6,900 in parser_tokens_test |
| Overload ranking and semantic resolution | ~2,000 | ~3,800 in parser_tokens_test, most of test_fixtures, ~82% of differential fixtures |
| Detailed `#asm` operand model | ~680 | ~500 |

---

## 1. parser.jai

### 1a. AST reuse after an edit (biggest single item)

`parse_file_edit` copies unchanged declarations from the old tree instead of reparsing them.  The code involved:

- [reuse_simple_declaration](parser.jai#L817-L1071), 255 lines.
- [find_old_declaration_block](parser.jai#L1072-L1142).
- [reusable_type_instantiation / copy_reusable_type_instantiation](parser.jai#L1143-L1219).
- [reusable_expression](parser.jai#L1220-L1403), 184 lines.
- [copy_reusable_expression](parser.jai#L1404-L1575), 172 lines.
- Hooks in `Parser` and `parse_block_node`.

That is about 780 lines.  The edit-aware path in `materialise_tokens` adds about 110 more.

The value is questionable.  Only identifiers, literals and arithmetic, call, cast or member expressions are eligible, and those are exactly the cheapest things to reparse.  Scopes, bindings and diagnostics are rebuilt on every edit anyway.

- **Option A: remove AST reuse.**  `parse_file_edit` becomes "check the prefix and suffix match, then do a full parse".  This saves about 780 parser lines and roughly 6,500 test lines.  The test region at [parser_tokens_test.jai L866-L7790](examples/parser_tokens_test.jai#L866-L7790) is 101 procedures and about 6,900 lines.
- **Option B: keep it, but test it with one oracle.**  The existing tests compare the edited tree with a fresh parse by hand, field by field: 155 `first_token == fresh...` checks, 54 `l0 == fresh...` checks, and 95 hand-built probe blocks that call the internal `reuse_simple_declaration`.  [check_binary_ast_reuse](examples/parser_tokens_test.jai#L4387) and [test_logical_ast_reuse](examples/parser_tokens_test.jai#L4437) show the pattern.
  - Instead, extend [assert_eligible_edit_matches_fresh](examples/parser_tokens_test.jai#L4719) to a deep structural tree comparison.  It could reuse the differential normaliser (§4a), mapping `resolved_declaration` by statement index.
  - Add a returned or debug count of reused declarations to replace the probe blocks.
  - Each test then becomes one table row: old source, edit range, new source, expected reuse count.  That is likely 5,000+ lines saved.

### 1b. Repeated idioms

| Idiom | Count | Simplification | Saving |
|---|---|---|---|
| `result.kind = .X;` after `new_parser_node` | 124 | Have the generated `Parser_X` structs carry a `KIND` constant and let `new_parser_node` set it | ~120 lines, and a missing-kind bug class gone |
| `.allocator = parser_node_allocator(parser.parsed)` / `New(..,, parser_node_allocator(..))` | 40 / 53 | Make the node pool `context.allocator` for the whole parse in `parseInit`, and allocate the five persistent `Parsed_Source` arrays explicitly (use `push_allocator` perhaps) | ~60 |
| `x = parse_binary(...); if !x { add_expected_expression(parser); }` | ~38 | A `parse_required(parser, parse_binary)` helper | ~110 |
| `parser_eat(parser, 2)` opening each directive case in [parse_expression_directive](parser.jai#L5857), 506 lines | 44 | Eat `#name` once before the `if name ==` switch | ~40 |
| Identical trailers in `parse_expression`, `parse_block`, `parse_declaration_block` | 3 | Shared helper | ~25 |

### 1c. Block parsers

[parse_aggregate_block](parser.jai#L4517) repeats about 70% of [parse_block_node](parser.jai#L1576): the scope push, the recovery loop, and the enum-member and static-`#if` branches.  Adding a field-default assignment mode to `parse_block_node` would save about 60 lines.

### 1d. `#asm` operand model

The types at [L17-L117](parser.jai#L17-L117) plus the parsing at [L1876-L2448](parser.jai#L1876-L2448) come to about 680 lines.  They model registers, pinning, memory operands and modifiers.

The compiler exposes `Code_Asm` only as opaque data, so none of this can be checked differentially.  The README also contradicts itself: it says operand internals "remain `UNPARSED`" but also describes register and memory records.

Keeping only the body span and the instruction/statement spans would save about 450 parser lines and about 400 test lines (`test_asm_tutorial_forms`, `test_asm_token_contract`, `test_assembly_recovery`).

### 1e. Module parameters

- `INTERN_IDENTIFIERS` is labelled experimental, and the README says benchmarks favour copying.  Dropping it removes `Identifier_Storage` and `release_parser_names`.
  - That function is called 636 times in tests, and it brings a required release order: tree before names.
- `ENABLE_TRIVIA=false` accounts for 20 `#if` blocks in parser.jai.  Spans, `reconstruct_source` and edits all need trivia on.  Making trivia always on is worth considering, at the cost of the original `Token` layout.

## 2. lexer.jai

- Two commented-out blocks of SIMD C intrinsics, [L639-L694](lexer.jai#L639-L694) and around [L1777-L1802](lexer.jai#L1777-L1802), about 80 lines.  They are dead code inherited from Jai_Lexer.  However, we are keeping them as we have a task later to translate them to jai so the lexer can be faster.
- The lexer keeps an 8-slot ring buffer (`MAX_CONCURRENT_TOKENS`), and then `materialise_tokens` copies every token into an array anyway.
  - Appending directly to the array would remove the ring indexing plus the `consume_materialised_token` / `append_materialised_token` glue, about 100 lines.
  - The cost is more divergence from Jai_Lexer.

## 3. resolution.jai - mostly semantics, not parsing

Overload ranking, aggregate conversion routes, constant evaluation and numeric literal ranks emulate the compiler's typechecker.  The largest procedures:

- `match_aggregate_call_arguments`, 324 lines.
- `resolve_complete_aggregate_type`, 185 lines.
- `infer_aggregate_expression_type`, 138 lines.
- `evaluate_constant_boolean`, 117 lines.

**Strategic point:** this layer drives most of the test volume.  The ranking and conversion sections (Numeric rankings 594, Typed integer 912, Typed floating 1,210, Aggregate 267, Candidate permutations 432) are 3,415 of the 4,175 differential fixtures.  It also accounts for about 1,900 lines of fixture generators in test_fixtures.jai, and for [test_file_import_resolution](examples/parser_tokens_test.jai#L8574-L12350), a single procedure of about 3,775 lines.

Options, in order of impact:

- Move this layer to its own module, or freeze its scope.
- Within the file:
  - Replace the per-type integer range ladder at [L1634-L1714](resolution.jai#L1634-L1714) with a table: ~40 lines.
  - Factor out the repeated "local visited array, cycle check, push/pop" guard (117 `visited` references): ~50 lines.
  - Replace the bit-packed `INTEGER_*_CONVERSION` rank encoding with a small struct, mainly for clarity.  Human does not particularly agree with this one.

## 4. differential_test.jai

### 4a. Duplicated normalisers (high value, low risk)

There are two normalisers:

- [normalise_parser_node](examples/differential_test.jai#L1729-L2154), 426 lines.
- [normalise_node](examples/differential_test.jai#L2155-L2595), 441 lines.

After mechanically renaming `Parser.Parser_X` to `Code_X`, a diff between them shows only **27 differing lines**: one wrapped call, the `#run` body unwrapping, and one Poke_Name temporary.  One polymorphic normaliser over a node family, with `#if` blocks for the two real differences, saves about 420 lines.  The same applies to `normalise_parser_declaration` / `normalise_declaration`.

### 4b. Memory-investigation cleanup (completed)

Removed the allocation-event ledger, injected probe allocators, observer storage, native phase sampling, profiling selectors, and their helper arguments.  Deleted-script references and obsolete investigation history have also been removed from [todo.md](todo.md).

Keep isolated fixture temporary storage, scoped pools, explicit diagnostic-result ownership, runtime zero-retention assertions, and the overflow/reset regression in [examples/differential_test.jai](examples/differential_test.jai).  These enforce ownership and failure preservation; fresh-process batching does not replace them.  [examples/differential_runner.jai](examples/differential_runner.jai) retains native memory caps, admission checks, deadlines, and bounded parallelism.

### 4c. Other

- Section and batch selection inside the test ([L223-L272](examples/differential_test.jai#L223-L272), [L909-L1030](examples/differential_test.jai#L909-L1030)) partly overlaps the runner's argument parsing.  Saving is small, about 50 lines.
- `assert_*_workspace_fixture` variants (declaration, assignment, overload, file, multi-candidate) share their setup, compile and COMPLETE handling; another 100-150 lines could go.

## 5. parser_tokens_test.jai (beyond §1a and §3)

| Pattern | Count | Fix | Saving |
|---|---|---|---|
| `release_parser_tree` + `release_parser_names` (+ `free(source)`) | 640 / 636 | One `release_parsed(*p)`, or a `defer`-exporting macro used at the parse site | ~650 lines |
| `.root.(*Extended.Parser_Block).statements[i].(*Extended.Parser_Declaration).expression.(*T)` | 541 / 1,024 casts | Navigation helpers such as `statement(*p, i)` and `declaration_value(*p, i, T)` | Mostly shorter lines; ~200 lines |
| Hand-built reuse probes (`materialise_tokens` -> `Parser.{...}` -> `reuse_simple_declaration`) | 95 x ~8 lines | Helper, or removal under §1a | ~650 |
| Code duplicated across Default and Extended imports | - | Fewer configurations if §1e is adopted | - |

The one 3,775-line `test_file_import_resolution` should at least be split into per-feature procedures, and its mapped-field and overload cases moved into tables.

## 6. Smaller items

- [test_fixtures.jai](examples/test_fixtures.jai): `AGGREGATE_CHAIN_CASES` is about 1,600 lines of here-strings.  That layout was an explicit choice, so no change is recommended; the generators are already compact.
- Obsolete memory-probe references have been removed from [todo.md](todo.md).  In the README, the `#asm` operand description contradicts itself and the cleanup command is still given as `bash clean_build_artifacts.sh`.

---

## Estimated savings

| Change | Parser/lexer/resolution | Tests |
|---|---|---|
| Remove AST reuse (§1a, Option A) | -780 | -6,500 |
| *or* keep it and test with one oracle (§1a, Option B) | 0 | -5,000 |
| Repeated idioms and block merge (§1b-c) | -430 | - |
| Smaller `#asm` model (§1d) | -450 | -400 |
| Drop interning (§1e) | -100 | -640 |
| Lexer dead code and ring buffer (§2) | -180 | - |
| Resolution tidy-ups (§3, not extracting it) | -100 | - |
| Single normaliser (§4a) | - | -420 |
| Memory investigation cleanup (§4b, completed) | - | Already removed; ownership checks retained |
| Release and navigation helpers (§5) | - | -850 |

The remaining low-risk changes, which keep every feature (§1b-c, §2, §4a, §5 and the §1a test oracle), could save about 600 production lines and about 6,300 test lines.  Removing AST reuse and the `#asm` operand model and moving resolution out of the module would roughly halve both the parser and the tests.

The remaining savings are estimates from the original line counts and greps.  Only the memory-investigation cleanup in §4b has been completed here; the opening counts predate it.
