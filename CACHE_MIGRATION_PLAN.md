# Cache Migration Plan

How the current parser becomes the signed-off syntax-first cache service.
The specification is [CACHE_ARCHITECTURE.md](CACHE_ARCHITECTURE.md) with its companions [CACHE_CONTRACTS.md](CACHE_CONTRACTS.md), [CACHE_SYNTAX_REGISTRY.md](CACHE_SYNTAX_REGISTRY.md) and [CACHE_EXPERIMENTS.md](CACHE_EXPERIMENTS.md).
Decision labels (R1-R14), milestones, gates (C1-C5, P1-P5) and traces (T, V, X, S, A, W) are defined there.

Drafted 2026-11-04 after whole-specification sign-off (R9).
The user approved this plan and authorised implementation on 2026-11-04.
Approval authorises the phases below in order; it does not approve their results, which still pass through the milestone-6 verdict rules.

## 1. Starting Point

Re-audit of the current code on 2026-11-04.

| Area. | Current state. | Consequence for the migration. |
| --- | --- | --- |
| [module.jai](module.jai) | Parameters `ENABLE_TRIVIA` (default off), `EVALUATE_STRING_ESCAPES`, `INTERN_IDENTIFIERS`, `USE_SIMD`, `TRACK_AST_REUSE`; loads the lexer, parser and resolver. | The service imports the parser with `ENABLE_TRIVIA = true`; the full-featured profile rejects non-trivia builds.  Existing default-parameter users are unaffected. |
| [parser.jai](parser.jai) (about 6,800 lines) | Entry points `parse_file`, `parse_file_edit`, `parse_expression`, `parse_declaration`, `parse_block`, `parse_declaration_block`; `release_parser_tree`.  All nodes live in one `Pool` in `Parsed_Source`; source and filename are borrowed. | The service owns source bytes and the `Parsed_Source` together and releases both on the last lease.  Only `parse_file` is needed initially (whole-file reparse, R1). |
| Compound declarations | Two builders: identifier-led in `parse_declaration_node`, expression-led in `parse_statement`.  The expression-led path discards its operator token; neither records modifier nor separator token indices. | Phase 1 merges them and records every token (R12). |
| Declaration `#export` | No producer path; `parse_declaration_metadata` stops at unknown directives. | Phase 1 adds it (R12). |
| [resolution.jai](resolution.jai) | `resolve_lexical_references` writes `resolved_declaration` into identifier nodes; scopes and bindings are built during parsing. | The service parses with `resolve_identifiers = false` (E6): published snapshots are never mutated.  Resolution stays available to existing callers and is not part of the initial slice. |
| AST reuse (`parse_file_edit`, `reuse_simple_declaration`, copier) | About 900 production lines and 6,900 test lines. | Not used by the service.  The keep/drop decision stays independent (see [simplify.md](simplify.md) 1a); this plan neither removes nor depends on it. |
| Lexer | `Token`, trivia iteration, SIMD classifiers; `Parser_Token` adds byte offsets under trivia. | Reused as-is through the parser. |
| Tests | [parser_tokens_test.jai](examples/parser_tokens_test.jai) (about 151 procedures), [differential_test.jai](examples/differential_test.jai) with its runner and fixtures, [parse_how_to.jai](examples/parse_how_to.jai), [layout_test.jai](examples/layout_test.jai), [lex_all_files.jai](examples/lex_all_files.jai), [snapshot_oracle.jai](examples/snapshot_oracle.jai), [benchmark_ast_reuse.jai](examples/benchmark_ast_reuse.jai). | All must keep passing after every phase.  `snapshot_oracle.jai` (with its `DIRECTIVE_THIS` fix) is the starting C1 fresh-parse oracle. |
| SDK support | `Pool`, `Bucket_Array`, `Thread` (mutex, semaphore, condition variable), `Text_File_Handler`, `File`, `File_Utilities`; `meow_hash` (128-bit, x64 AES), `xxHash` (32/64-bit only) and `Hash` (FNV, djb2). | Phase 2 wraps `meow_hash` as the R14 content digest. |
| Persistence/service code | None in the module; E7-E13 prototypes live under [examples/](examples/) only. | Everything in phases 2-6 is new code.  Prototypes inform it but are not promoted. |

## 2. Boundaries

| Kept unchanged. | Changed. | New. | Not touched by this plan. |
| --- | --- | --- | --- |
| Lexer; all existing public parse entry points and their tests; resolver; default module parameters. | Compound-declaration builders and their node shape; declaration metadata (`#export`); the registry text describing them. | Service code: canonical values, identities/handles, owned snapshots and projections, declaration-index adapter, provider, coordinator/worker, store, harness host, acceptance runner. | AST-copier keep/drop; semantic queries; evaluator; language server; POSIX store implementation. |

No existing public API breaks.
The only deliberate shape change is the compound-declaration node in phase 1, which is checked against the official compiler through the differential tests.

### Code Location

Service code lives in this repository under `service/`, whose `module.jai` imports the parser with `ENABLE_TRIVIA = true`.
Clients use `#import "Jai_Parser/service"`; a phase-0 compile check confirmed that this nested-module import (and `#import,dir`) resolves and yields a trivia-enabled parser alongside the default-parameter instance.

### Working Rules

- Every phase ends buildable, with all existing tests and the new phase tests passing on the fast x64 backend, and the optimised LLVM build compiling.
- Every new test has an independent oracle and a deliberately broken negative control, per the milestone-6 verdict rules.
- Each phase updates the specification documents only where the code proves them wrong; such changes are listed in the phase's review.
- Commit per phase step; no step mixes a parser shape change with service code.

## 3. Phases

```mermaid
graph LR
	P0[0 Baseline and layout] --> P1[1 Parser evidence]
	P0 --> P2[2 Foundations]
	P1 --> P3[3 Owned snapshot and index]
	P2 --> P3
	P3 --> P4[4 Provider and coordinator]
	P4 --> P5[5 Worker and shutdown]
	P2 --> P6[6 Persistent store]
	P5 --> P7[7 Integration and acceptance]
	P6 --> P7
	P7 --> P8[8 Cutover review]
```

Phases 1 and 2 are independent of each other; phase 6 can proceed alongside phases 4-5 once phase 2 is done.

### Phase 0: Baseline and Layout

1. Run every existing test and record its command, backend and result as the baseline.
2. Settle the service code location with a minimal compiling entry file that imports the parser with trivia enabled.
3. Add the acceptance-case record format and verdict tally (milestone 6) as a small harness library, plus an empty runner that reports `NOT_RUN` for every listed case.

Exit: baseline recorded; empty service entry and runner compile and run.

#### Baseline (2026-11-04)

Jai beta 0.2.030 (2 July 2026), fast x64 backend, run from `examples/`.

| Suite. | Command. | Result. |
| --- | --- | --- |
| Lexer layout. | `jai layout_test.jai -x64 -quiet && ./layout_test.exe` | Pass; SIMD widths 16/32 parity, width 64 skipped (no CPU support). |
| Lexer corpus. | `jai lex_all_files.jai -x64 -quiet && ./lex_all_files.exe` | Pass; 2,239,352 tokens across 712 files. |
| Parser tokens. | `jai parser_tokens_test.jai -x64 -quiet && ./parser_tokens_test.exe` | Pass. |
| How-to corpus. | `jai parse_how_to.jai -x64 -quiet && ./parse_how_to.exe` | Pass; 84/84 files with zero diagnostics. |
| Differential. | `jai differential_runner.jai -x64 -quiet && ./differential_runner.exe --all` | Pass; 4,175/4,175 fixtures, 252 jobs, about 310 s. |
| AST reuse verification. | `jai benchmark_ast_reuse.jai -x64 -quiet -exe verify_ast_reuse - verify-only && ./verify_ast_reuse.exe ../../../examples/invaders` | Pass; deep snapshot/lifetime checks. |
| Acceptance ledger. | `jai cache_acceptance.jai -x64 -quiet && ./cache_acceptance.exe --self-test && ./cache_acceptance.exe` | Pass; 55 cases (47 `NOT_RUN`, 8 `DEFERRED`). |

Three pre-existing failures were repaired first:

- `differential_test.jai` called `free` on a `[] string`; now `array_free`.
- `lex_all_files.jai`'s default corpus walk followed a dangling E4 symlink under `examples/.build`; it now passes `visit_symlinks = false`, like its benchmark walk.
- Commit `7a52037` had turned named context-modification fixtures (`,, allocator = x`) into the unnamed shorthand (`,, x`), which the compiler keeps as a plain identifier rather than an assignment.
The named-slot tests now use `logger_data = ...` so named, and unnamed slots are both covered.

### Phase 1: Parser Evidence (R12)

1. **Unified compound builder.**  One shared tail parses comma-separated targets (expressions, with an optional per-target `:` or `=` before a following comma), then the shared operator (`:`, `=` or an assignment-precedence operator).  Both entry points call it.  Record on the compound node the shared operator token index, each target's modifier token index (or none), and each separating comma's token index.  Binding classification becomes a function of recorded tokens: declared when the target carries `:`, or carries no modifier under a shared `:`; otherwise assigned.  Declared targets must be identifiers; anything else is diagnosed.
2. Keep scope-binding registration, notes, metadata and the existing node fields working; update `reuse_simple_declaration`'s compound guard for the new shape.
3. **Declaration `#export`.**  Recognise it in `parse_declaration_metadata` (or the declaration prefix, wherever the official compiler accepts it, confirmed by a differential fixture), recording the marker token on the declaration.
4. Rewrite the registry's compound-route section (the route becomes derivable, not captured) and the reserved-`EXPORT` rule.

Tests: new parser tests covering `a, b := v`, `a, b = v`, `a:, b = v`, `a=, b := v`, `x.y, z[0] = v`, `a, b += v`, missing separator/RHS, non-identifier declared targets; differential fixtures for the same against the compiler; `#export` positive/negative fixtures; all existing suites.
If unification breaks compiler agreement in a way that cannot be fixed cleanly, fall back to recording a route field in both builders (R12 fallback) and record the reason.

Exit: all suites pass; registry text matches the code.

### Phase 2: Foundations

1. **Canonical values.**  The milestone-2 `K`/`V` encodings, `SchemaName`/namespace/ID byte types, and canonical ordering helpers.
2. **Content digest (R14).**  One `digest_128` wrapper over `meow_hash`, with its algorithm identifier, streaming and one-shot forms, and fixed expected outputs (including the module's published `big.txt` value) plus a mutated-input negative control.
3. **Identity allocation.**  Service incarnation, per-session counters, exhaustion behaviour (milestone 3), and the generation-checked handle registry (slots, generations, retirement).
4. **Epoch issuer (R10).**  `.jaiParserEpoch` reservation: exclusive lock, increment, atomic replace, flush, head-epoch floor; `UNAVAILABLE` on any failure.
5. **Limits and reservation ledger.**  `LimitRequest` negotiation to effective `Limits`, checked arithmetic, live-plus-reserved accounting, documented implementation ceilings (milestone 2 and 4).

Tests: encoding round-trips and fixed expected bytes; digest expected outputs; allocator/generation stale-handle rejection; issuer ledger across repeated and concurrent process starts, deleted file with surviving head, injected I/O failure; ledger edge cases at exact and one-over limits.

Exit: foundations library passes its tests with negative controls.

### Phase 3: Owned Snapshot and Declaration Index

1. **Owned parse.**  Copy source and filename into a snapshot owner, parse with trivia and `resolve_identifiers = false`, and tie release of the pool, tokens, diagnostics and bytes to the owner.
2. **Snapshot projection.**  `.SYNTAX_SNAPSHOT` envelope: tokens and trivia, node records with snapshot-local IDs per the milestone-1 registry field roles, recovery/synthetic tokens, completeness; `.OPAQUE`-free or conversion failure.
3. **Diagnostics projection.**  `.SYNTAX_DIAGNOSTICS` with origins and the summary record.
4. **Declaration index adapter.**  Authored-edge traversal registry, entries and shared regions, name origins, metadata (`#program_export`, `#export`), scope-basis provenance, coverage reasons; capability descriptor (`jai-cache-syntax-adapter/1`).
5. **Context registry.**  Schema tuples, parse profile, adapter binding; admission of the implemented tuple only.

Tests (C1 and the milestone-2 qualification checklist): every W1 authored vector and the W2 inventories compare projection against an independent fresh parse via `snapshot_oracle.jai`; producer teardown and poisoning before comparison; registry-route vectors from the syntax registry's discriminating cases; coverage-reason and partial-index vectors.

Exit: C1 passes on W1 and W2; every registry route has a vector or an explicit unsupported/partial disposition.

### Phase 4: Provider and Coordinator (Deterministic)

1. **Source provider.**  Milestone-2 provider admission and the source-capture contract: in-memory and disk providers for the harness host, exact-base byte edit batches, overlay/disk branches, save/reset/delete/rename events, frontiers.
2. **Session and coordinator state.**  The fifteen operations over a session state gate, with tickets, analysis candidates, worlds, queries, waiters, completion entries and reservations.  Task execution goes through an internal executor interface; this phase supplies a deterministic step executor for tests only.
3. **Harness host.**  Implements host confirmation, project-root declaration, the epoch binding and completion draining.

Tests: T1-T8 and V1-V8 with authored event ledgers; operation/error-arm subcases from the milestone-6 API boundary list; unsupported semantic/evaluator queries create no task.

Exit: T and V traces pass under the deterministic executor.

### Phase 5: Worker, Cancellation and Shutdown

1. Replace the test executor with the service-owned compute worker and the reserved shutdown/reaper job (milestone 4), using `Thread` primitives; the deterministic executor remains as a test seam.
2. Condition-variable `Wait`, required/optional FIFOs, cooperative stop points, world supersession, last-consumer removal, mailbox-validated publication, `STOPPED` predicates and surviving-owner lifetime.

Tests: X1-X8 with barriers at each gate/registration/publication/free boundary, both orderings, duplicate and late completions, allocator and provider failures; T1-T8 rerun on the real worker; zero live owned allocations after final release.

Exit: X traces pass with attained barriers; C3 and C5 evidence recorded.

### Phase 6: Persistent Store

1. **Wire codec.**  Strict envelope preflight, typed body grammar, `Text_File_Handler` over a bounded buffer, iterative bounded decoder, canonical encoder.
2. **Records and policy.**  The seven record kinds, `StorePolicy` resolution to `.jaiParserCache`, effective `StoreLimits`.
3. **Native binding.**  `jai-cache-store-local/1` Windows implementation (R11): containment checks, owner lock, create-new staging, no-replace install, head replacement.
4. **Commit, read and recovery.**  Ordered source projection, commit/reconciliation, read pins, recovery offers, GC, maintenance actions and quarantine.
5. **Service wiring.**  Store lane, degradation status and diagnostics; persistence never blocks source acceptance.

Tests: S1-S8 with independently encoded files and root inventories, interruption at every staged/installed/head boundary, corrupt-but-rehashed records, write denial, a second-process owner contender; C4 evidence.

Exit: S traces pass; store failure never breaks source operations.

### Phase 7: Integration and Acceptance

1. Expand the milestone-6 coverage ledger to every supported registry route, operation/error arm, event variant, bound edge and fault boundary.
2. Run A1-A15 over W1-W6, with W3 manifests frozen per R13.
3. Run P1-P5 in two local rounds and assemble the measured results packet for review under R7.

Exit: no `FAIL`, `BLOCKED` or `NOT_RUN` applicable correctness case; no unexplained live ownership; results packet delivered.

### Phase 8: Cutover Review

1. Review the results packet and decide whether the service is the supported entry point for the harness (and later the language server).
2. Update [README.md](README.md) and the specification documents to describe the implemented state; mark qualified items in section 15 of the architecture.
3. Separately, revisit the AST-copier decision with its own measurements; any removal is a later plan.

Exit: user decision recorded.

## 4. Persistence Rollout and Version Rejection

- The store starts at `jai-cache-store/1`; there is no earlier production store to migrate.
- E11/E12 experiment stores are never read: their namespaces and schemas reject.
- An unknown or newer schema is a cache miss with a diagnostic, never an upgrade or overwrite; repair stays explicit (milestone 5).
- Enabling persistence by default (R2) takes effect only from phase 7 onwards; earlier phases test the store in isolated roots.

## 5. Risks and Contingencies

| Risk. | Contingency. |
| --- | --- |
| Compound unification changes compiler agreement or reuse behaviour. | R12 fallback (route field), recorded as an amendment. |
| A registry route cannot be projected exactly. | Partial coverage with its reason, per the registry's limits table; never a silent gap. |
| Threading primitives lack a needed guarantee (for example timed condition waits). | Adjust the executor implementation, keeping the deterministic seam and the X traces unchanged. |
| Native file primitives behave differently from documented assumptions. | Degrade persistence explicitly (R8); source operations continue. |
| Performance deltas are unfavourable. | Report them under R7; the cutover review decides, not this plan. |

## 6. Progress

- [x] Plan approved and implementation authorised (2026-11-04).
- [x] Phase 0: baseline and layout.
	- [x] Record the baseline test results.
	- [x] Settle the service code location.
	- [x] Add the acceptance record format and empty runner ([cache_acceptance.jai](examples/cache_acceptance.jai), with `--self-test`).
- [ ] Phase 1: parser evidence.
	- [ ] Unify the compound-declaration builders and record operator, modifier and separator tokens.
	- [ ] Add declaration `#export`.
	- [ ] Update the registry text.
- [ ] Phase 2: foundations.
	- [ ] Canonical values.
	- [ ] Content digest.
	- [ ] Identity allocation and handle registry.
	- [ ] Epoch issuer.
	- [ ] Limits and reservation ledger.
- [ ] Phase 3: owned snapshot and declaration index.
	- [ ] Owned parse.
	- [ ] Snapshot projection.
	- [ ] Diagnostics projection.
	- [ ] Declaration index adapter.
	- [ ] Context registry.
	- [ ] C1 on W1 and W2.
- [ ] Phase 4: provider and coordinator.
	- [ ] Source provider.
	- [ ] Session and coordinator with the deterministic executor.
	- [ ] Harness host.
	- [ ] T1-T8 and V1-V8.
- [ ] Phase 5: worker, cancellation and shutdown.
	- [ ] Compute worker and reaper.
	- [ ] X1-X8.
- [ ] Phase 6: persistent store.
	- [ ] Wire codec.
	- [ ] Records and policy.
	- [ ] Windows native binding.
	- [ ] Commit, read, recovery, GC and maintenance.
	- [ ] Service wiring.
	- [ ] S1-S8.
- [ ] Phase 7: integration and acceptance.
	- [ ] Coverage ledger expansion.
	- [ ] A1-A15 over W1-W6.
	- [ ] P1-P5 results packet.
- [ ] Phase 8: cutover review.
