# Syntax, Semantics, and Persistent Cache Architecture

Status: design proposal with approved directions; last revised 2026-10-23.

This report describes the intended model and its trade-offs, not an approved API, implementation sequence, or migration plan.
Existing APIs have no consumers that require compatibility.
The AST-copier keep/drop decision remains separate and unresolved.

## Document Map and Conventions

| Document. | Contents. |
| --- | --- |
| This document. | Architecture (sections 1-13), the decision record, initial scope, correctness gates, performance comparisons, open decisions, experiment summary and TODO (sections 14-15). |
| [CACHE_CONTRACTS.md](CACHE_CONTRACTS.md) | Detailed contract drafts: core source/world contracts, persistence, semantic identity, execution, source capture, interface schema, and acceptance (milestones 3-8). |
| [CACHE_SYNTAX_REGISTRY.md](CACHE_SYNTAX_REGISTRY.md) | Projection of the current parser's nodes, helpers and tokens onto the syntax payloads (milestone 2). |
| [CACHE_EXPERIMENTS.md](CACHE_EXPERIMENTS.md) | Procedures, measurements and limits of experiments E1-E13. |

Status conventions apply to all four documents:

- **Drafted** or **proposed** text is a logical contract for review, not an approved API or implemented code.  Record names describe logical records and outcomes, not Jai declarations or persistent memory layouts.
- **Approved** means recorded in the [decision record](#decision-record).  Approval does not authorise implementation, migration or rollout.
- **Qualified** means passed executable acceptance against an implementation.  Nothing is qualified yet; all qualification and review vectors run only after separate implementation authorisation, against independent oracles (fresh parses, the official compiler, or authored expectations), with negative controls.
- Approval, implementation and qualification are independent: an approved requirement can remain unimplemented and untested.
- Experiments are bounded evidence, not qualification of a future service.

| Milestone. | Scope. | Status. |
| --- | --- | --- |
| 2. | [Current-producer syntax registry closure](CACHE_SYNTAX_REGISTRY.md#milestone-2-syntax-registry-closure). | Drafted; qualification open. |
| 3. | [Exact logical interface](CACHE_CONTRACTS.md#milestone-3-exact-logical-call-signatures): signatures, responses, provider admission, bounds and canonical values. | Drafted; API review open. |
| 4. | [Identity allocation, matching and semantic keys](CACHE_CONTRACTS.md#milestone-4-allocation-and-restart-continuity), with deferred semantic records. | Drafted; review open. |
| 5. | [Execution coordination, delivery, cancellation and shutdown](CACHE_CONTRACTS.md#milestone-5-coordination-ordering-and-reservations). | Drafted; review open. |
| 6. | [Persistent store](CACHE_CONTRACTS.md#milestone-6-store-profile-bounds-and-text-grammar): grammar, records, commit, recovery and administration. | Drafted; review open. |
| 7. | [Whole-system acceptance map](CACHE_CONTRACTS.md#milestone-7-acceptance-scope-and-requirement-map). | Drafted; workload approval open. |
| 8. | [Cross-contract review and sign-off](CACHE_CONTRACTS.md#milestone-8-cross-contract-review). | Pending sign-off. |

No milestone 1 was designated; the unnumbered initial-scope and core-contract drafts of 2026-10-20 preceded milestone 2.

| Labels. | Meaning. | Defined in. |
| --- | --- | --- |
| R1-R8. | Review decisions. | [Decision record](#decision-record). |
| C1-C5. | Correctness gates. | [Correctness gates](#correctness-gates). |
| P1-P5. | Performance comparisons. | [Performance comparisons](#performance-comparisons). |
| E1-E13. | Experiments. | [CACHE_EXPERIMENTS.md](CACHE_EXPERIMENTS.md); summary in [section 14](#experiment-summary). |
| T1-T8. | Core contract acceptance traces. | [CACHE_CONTRACTS.md](CACHE_CONTRACTS.md#acceptance-trace-drafts). |
| S1-S8. | Store acceptance traces. | [CACHE_CONTRACTS.md](CACHE_CONTRACTS.md#store-acceptance-trace-drafts). |
| D1-D8. | Semantic identity traces (deferred). | [CACHE_CONTRACTS.md](CACHE_CONTRACTS.md#semantic-acceptance-trace-drafts). |
| X1-X8. | Execution traces. | [CACHE_CONTRACTS.md](CACHE_CONTRACTS.md#execution-acceptance-trace-drafts). |
| V1-V8. | Source-capture traces. | [CACHE_CONTRACTS.md](CACHE_CONTRACTS.md#source-capture-acceptance-trace-drafts). |
| A1-A15. | Milestone-7 requirements. | [CACHE_CONTRACTS.md](CACHE_CONTRACTS.md#milestone-7-acceptance-scope-and-requirement-map). |
| W1-W6. | Milestone-7 workloads. | [CACHE_CONTRACTS.md](CACHE_CONTRACTS.md#milestone-7-workloads-and-measurement-boundaries). |

## 1. Purpose and Confirmed Direction

The primary product is a long-lived editor service: eventually ReSharper-like support for Jai, including incomplete code, navigation, diagnostics, refactoring, and progressively complete semantic understanding.
Building a replacement Jai compiler is not the objective.

The user confirmed these requirements during this design discussion:

- Full syntax and semantic coverage is the eventual goal; useful partial coverage is acceptable on the way.
- Fast syntax parsing is an advantage to exploit, not work that must always be avoided through elaborate subtree copying.
- Cache module syntax and semantic results for a configured module instance.
Absolute file location, module parameters, and the current program parameters are part of that identity.
- Retain loaded-file syntax independently of the module context in which its declarations acquire meaning.
- Consider independently cached semantic results for types, enums, procedures, and other declarations.
- Design for persistent caches now.
They should survive editor restarts, remain resident in memory when useful, and be evicted only when necessary rather than routinely discarded after requests.
- Persistence should be configurable, provisionally enabled by default, with a caller-supplied storage location option.
The exact configuration contract is still proposed below.
- Persist unsaved revisions as well as saved revisions when persistence is enabled, with explicit document-state tracking and recovery/cleanup controls.
Restoring or discarding a buffer must not accidentally select its obsolete unsaved revision.
- Eventually use isolated official-compiler subprocesses for evaluations such as `#insert`, `using,map`, `#modify` blocks and `#run`, where necessary.
A future bootstrapped language-service evaluator could replace that backend, but its availability and API are not assumed.
- Compiler subprocess evaluation requires explicit opt-in through a program/module parameter, plus host permission where applicable.
Workspace trust is an external integration responsibility, not something the parser can infer.
- Do not implement that evaluator simply to complete this architecture.
Expose unavailable operations honestly until they block a required feature.
- Conservative whole-module semantic invalidation is an acceptable initial baseline; finer declaration/query reuse can grow incrementally.

**Recommendation:** reuse whole immutable file snapshots first, represent semantic work as dependency-tracked queries, and persist explicit pointer-free artifacts.
Reparse changed files by default.
Add syntax chunks or finer semantic caches where they produce measured editor benefits, not merely higher reuse counts.

## 2. What Exists Today

The current implementation already has separable operations, but not independently shareable syntax and semantic ownership:

| Surface. | Current behaviour. | Architectural consequence. |
| --- | --- | --- |
| [Module setup](module.jai) | Loads lexer, parser, and resolution code into one module, with lexer/parser configuration parameters. | File organisation does not yet establish separate ownership or persistent artifacts. |
| [Parsing](parser.jai#L625) | `parseInit` materialises tokens, creates scopes, builds nodes, and optionally resolves lexical references. | Disabling identifier resolution does not remove scopes, binding collection, or semantic-shaped fields from the AST. |
| [Lexical scopes](parser.jai#L524) | Scopes and reference registries live in the AST node pool; resolution writes declaration pointers into identifier nodes. | A parsed tree is not currently an immutable syntax object that independent semantic worlds can safely share. |
| [Edited parsing](parser.jai#L751) | Creates independent snapshots; token reuse and an eligible-declaration AST copier can use the old snapshot as a template. | It copies, relocates, allocates, and rebuilds bindings rather than sharing unchanged syntax ownership. |
| [Import resolution](resolution.jai#L61) | Reads and parses imports per invocation, owns imported and loaded snapshots, and installs import binding pointers. | There is no persistent configured-module cache.  Resolution lifetime is coupled to dependency snapshots. |
| [Loaded files](resolution.jai#L2535) | Traverses file-level loads, parses files, and suppresses repeated filenames within that traversal. | This is traversal-local deduplication, not a reusable file-revision store or complete semantic module graph. |
| [Import release](resolution.jai#L2633) | Clears installed reference pointers and releases owned dependency trees, names, sources, and paths. | A cache cannot simply retain these results while leaving the existing owning teardown unchanged. |
| [Semantic helpers](resolution.jai) | Implement selected lookup, aggregate inference, instantiation, constant evaluation, and overload-related operations. | They are useful coverage, not a full typechecker or a dependency-tracked semantic scheduler. |
| [Compiler-shaped nodes](parser.jai#L410) | Generated parser structs overlay compiler `Code_*` layouts and add parser-owned fields. | Compiler-shaped in-memory layouts are not an appropriate persistent binary format or a reason to couple future syntax to semantic mutation. |

The [recorded benchmark](README.md) measures individual-file updates, not a project-wide import cache.
On the largest measured file, token-only lifecycle medians are about 1.08-1.11 ms; AST copying adds no demonstrated median or retained-byte benefit over that path.
This supports treating a changed-file reparse as a credible baseline.
It does not establish how much a project-level module cache will save.

## 3. Terms and Identities

Use distinct identities for distinct questions.
Combining them into one universal hash would obscure invalidation and make ordinary edits unnecessarily expensive.

| Identity. | Meaning. |
| --- | --- |
| `DocumentID`. | A resolved source-document identity, including its absolute path and filesystem identity policy. |
| `SourceRevision`. | Exact source bytes plus their content digest.  An unsaved editor buffer is a revision even if disk contents differ. |
| `SyntaxKey`. | Document identity, source digest, syntax configuration, and parser/schema version. |
| `ModuleInstanceID`. | Resolved module source plus compiler-compatible import-request identity, ordered explicitly supplied typed module arguments, and that module's effective program settings.  E2 shows that canonical filepath plus effective values alone is insufficient. |
| `SemanticContextID`. | Module instance, target/type environment, resolution configuration, evaluator policy/version, and relevant language configuration. |
| `DeclarationID`. | A declaration within its owning module instance, load occurrence where applicable, and revision mapping; not just its name, physical filepath, or syntax hash. |
| `TypeID`. | Nominal semantic identity rooted in the defining declaration, with canonical instantiation arguments where applicable. |
| `QueryKey`. | The semantic operation, subject identity, explicit arguments, context, and query implementation version. |
| `ArtifactKey`. | A validated query or syntax result together with the versioned input/dependency fingerprints needed to reuse it. |

The names above describe responsibilities, not final Jai API declarations.

### Paths and Source Revisions

Resolve a module name or relative load against an explicit resolver configuration before looking it up in the cache.
An absolute path is necessary, but a raw path string is not sufficient: Windows casing, separator spelling, symlinks, and aliases can otherwise create accidental duplicates or conflate intended identities.

Define canonical document identity and retain the source-visible path spelling separately.
Location/path-sensitive constructs such as `#filepath`, relative loads, and diagnostics can observe the document context; identical bytes in different files are not automatically interchangeable results.
Do not merge module identities across symlinks until the language/path policy is explicit.
[E4](CACHE_EXPERIMENTS.md#e4-results-paths-and-source-context) verifies that source-visible paths can retain dot/parent segments, directory casing, and link aliases; separator handling also differs between the tested load and file-import paths.
`#filepath` supplies a directory, while `#location` can distinguish filenames within that directory.
Retain the effective source-visible filename/directory and relative-resolution context per file/load occurrence in relevant query inputs or dependencies, independently of the canonical physical-document key.
Neither filesystem equivalence nor a syntax/content cache hit permits rewriting these observed values or suppressing request validation.

Use exact content digests to establish reusable revisions.
Modification time, size, and file watchers can schedule validation, but are not proof that bytes match.
A warm restart may still need to read/hash files while avoiding lexing, parsing, and analysis.
Faster trusted manifest validation, if offered, must be a separately documented weaker policy.

Unsaved buffers take precedence over disk for that editor workspace.
Save, discard, external modification, deletion, rename, and replacement must all produce explicit revision/identity events.
A path returning after deletion must not revive results based solely on an old timestamp.

Keep the disk revision and active editor-overlay revision as separate document-state references into one immutable artifact store, rather than requiring two complete caches.
Identical bytes and context can share artifacts regardless of saved status.
Resetting a document to disk clears/replaces its active overlay reference and selects the current disk revision; saving advances the disk reference and reconciles the overlay.
Outstanding requests may retain the previous world without making it current again.

Persist overlay recovery metadata scoped to the workspace/document session, but let the editor/source provider authoritatively select restored buffer contents.
A cached unsaved revision is a recovery candidate, not permission to override a newly opened disk file.
On restart, bind it to an editor-confirmed restored revision, or expose it through an explicit recovery operation; never infer the active buffer merely from the newest cache entry.
Editor backups and parser artifacts have different responsibilities and need not duplicate one another's recovery UI.

### Module Parameters and Program Parameters

Canonicalise individual argument values by type and semantic value, not expression spelling, pointer address, or locale-dependent printing.
Preserve the explicit argument list's membership and order separately: E2 finds that omission versus explicit defaults, partial versus full argument lists, and reordered named arguments can produce distinct nominal module instances despite equal effective values.
It also finds distinct instances for import-mode/path-spelling aliases of the same source; a canonical physical document identity cannot alone establish module identity.
Use a versioned compiler-compatibility policy for these request-level distinctions, while still sharing suitable source/syntax backing.
For values with identity or effects that cannot yet be serialised canonically, mark the instance non-persistable or use a conservative session-local identity.
Include dependencies of default expressions and parameter evaluation.

Program settings are configured by imports in the main program, per module, and apply to its instances and transitive imports; an imported module cannot supply its own override for a child.
They are not a flat namespace inherited by every module with a same-named parameter: setting `MODE` on one module does not set `MODE` on a different module.
Supplying program parameters twice for the same module is rejected even if both supplied settings are identical; preserve configuration-site validation independently of instance cache hits.
A change may conservatively invalidate the program's semantic contexts initially.
Later queries may depend only on the parameters they actually read, without weakening the module-instance ownership model.

A module-instance identity groups results; it does not certify that they are current.
Source/dependency revisions, target settings, resolver changes, and implementation versions must still validate every reusable artifact.
The same parameterised instance can have several immutable revisions alive simultaneously.

## 4. Syntax and Semantics Must Be Independently Owned

### Syntax Snapshot

An owned syntax snapshot contains exact source bytes, document identity, tokens/trivia, decoded token payloads as needed, syntax nodes, source spans, syntax diagnostics, and recovery information.
Its storage is immutable after publication and independent of its caller's allocation context.
[E6](CACHE_EXPERIMENTS.md#e6-results-syntax-and-semantic-independence) demonstrates that ownership boundary on a bounded projection of the existing parser's output, including recovery data and decoded strings.
Its shallow-alias control also confirms that existing in-node lexical bindings cannot supply independent semantic contexts merely by copying the snapshot descriptor.

It contains no resolved declaration pointers, inferred types, evaluated constants, target-specific layouts, or mutable import results.
Syntactic roles such as declaration names, field labels, modifiers, and the structure of `using` remain syntax.
A scope index derived solely from one file's syntax can be a separate immutable artifact, but must not embed resolved cross-file bindings.

Source-sensitive built-ins should remain syntax descriptions until their required context is supplied, or that context must be part of the syntax artifact key.
In particular, storing a computed path string as an ordinary context-free literal would undermine byte-only syntax sharing.

Malformed and incomplete files remain cacheable syntax snapshots.
A parser can produce a useful snapshot without asserting that semantic analysis is complete or that the file has no diagnostics.

### Semantic World and Query Results

A semantic world identifies an immutable selection of document/module revisions and configuration.
Results include declaration indices, visibility, bindings, type identities, instantiated signatures, enum values, layouts, constant values, generated declarations, and semantic diagnostics.
They refer to syntax through versioned handles and source maps, not through mutable fields in shared syntax.

Queries should be independently reusable: resolving a name, obtaining a procedure signature, determining a field's type, laying out a struct, or analysing a body need not have identical invalidation rules.
An editor's new world may reuse a result only when its explicit inputs and recorded dependencies still match.

Published results are immutable.
Cancellation or a later edit cannot mutate an older result still held by navigation, diagnostics, or an in-progress refactoring.
Results from an older revision must not be presented as current merely because a task finished late.

## 5. A Pipeline, Implemented as a Dependency Graph

The pipeline operates per declaration, not over the AST as a whole.
Each declaration advances through applicable stages, publishing results as individual milestones become available.
If a stage needs another declaration's result, it records that dependency, yields, and waits for the required milestone; the scheduler can advance other ready work meanwhile.
Once that prerequisite is available, the waiting work becomes eligible to resume.

The dependency graph describes these relationships between declaration stages; it is the scheduling model behind the pipeline, not an alternative to it.
Declarations can be at different stages simultaneously, without whole-AST pass barriers or a requirement that a dependency finish all its stages first.
Stage requirements differ by declaration kind: a procedure signature can be available before its body is analysed, while a struct layout may wait for a field type's layout.
`#if`, type queries, polymorphism, `#run`, `#insert`, generated declarations, and imports can introduce additional work or prerequisites as a declaration progresses.

The [typechecking guide](../../how_to/090_how_typechecking_works.jai) explains bottom-up expression inference grounded by declarations.
It is not a specification of the official compiler's complete internal scheduling order.
This design intentionally does not claim that compiler uses the exact stages below or that type resolution always precedes sizing.

Overall source-to-editor flow, within which declaration pipelines run:

```text
Source provider and editor overlays
	-> exact source revision
	-> lexing and syntax parsing
	-> declaration/scope index and dependency discovery
	-> demand-driven semantic queries
		 visibility and lookup
		 signatures, type identity and instantiation
		 constant evaluation and conditional membership
		 enum values and aggregate layout
		 body/expression analysis and diagnostics
		 external evaluation and generated syntax
	-> editor feature results
```

These are logical boundaries, not dedicated threads or mandatory materialised intermediate files.
Semantic queries request their prerequisites; generated syntax re-enters parsing and dependency discovery.
A scheduler tracks declaration-stage readiness and dependency edges, shares identical in-flight work, resumes eligible waiters, handles cancellation, and detects cycles.
Yielding is a logical suspension, not a requirement to block a worker thread or use a particular coroutine implementation.

Use explicit result states: ready/complete, ready-with-diagnostics, incomplete/unknown, unsupported, blocked-on-dependency, cancelled, and failed.
A deterministic error can be cached with valid dependencies.
A cancelled or compiler-unavailable computation must not become a persistent claim that a declaration is semantically invalid.

Cycles need domain-specific handling.
Mutually referring declarations can be indexed together; recursive pointers can refer to an incomplete type identity; an infinitely recursive by-value layout must produce a semantic error.
A generic recursion guard that labels every cycle unsupported would prevent full coverage.
Query readiness, interface fingerprints, and strongly connected groups should allow legitimate recursion without inventing an unbounded global fixed-point solver.

For stalled pipelines, distinguish unresolved external work from an actual cycle in the required dependency graph; idleness alone is not a cycle diagnostic.
When an unsupported or illegal cycle is established, report its declarations and blocking milestones, including appropriate suggestions for breaking it (e.g. use a pointer rather than a by-value instance).
Legal recursion must use the applicable identity/readiness rules rather than becoming an error merely because a query is already in flight.

## 6. Cache Boundaries

### 6.1 Modules: Strong Context and Lifetime Boundaries

Cache the configured module's file membership, full declaration index across all visibilities, derived export/lookup views, and query results.
Standard libraries, vendored modules, and unchanged project modules all use the same correctness rules; edit frequency may affect residency and scheduling, not validity.

Cache retention is distinct from language visibility.
Retain each declaration's visibility, defining module/file, source location, and scope provenance; do not discard non-exported declarations when constructing a module artifact.
This does not require eagerly completing semantic analysis of every retained declaration.

For a top-level bare `#import "Basic";`, exported members become directly visible in the global scope.
For `Basic :: #import "Basic";`, members are accessed through `Basic.` rather than injected as bare names.
E1 verifies qualified access to `#scope_module` members, but not `#scope_file` members, on the tested compiler/configuration.
Do not encode an export-only cache boundary: module-visible declarations are valid qualified lookup candidates, and file-visible declarations remain relevant to internal analysis and tooling diagnostics.

E1 also verifies that bare imports in procedures, nested blocks, and structs expose exported names in the importing program's global scope, including to another loaded file.
The reverse direction is verified too: a bare import originating in a loaded file exposes exported names to the file doing the loading, at all four tested import scopes.
Named imports do not inject unqualified names, and their namespace binding does not escape its lexical scope as a bare name.
Top-level named bindings are accessible from other procedures and loaded files; bindings nested in procedures/blocks/structs are not directly visible there.
With normal loaded-file scope, a top-level named binding in a loaded file is likewise accessible to its loading file, but a nested named binding is not directly accessible there.
Use these observed distinctions when recording lookup dependencies and invalidating cached results; E1's result scope and remaining limitations are recorded in [CACHE_EXPERIMENTS.md](CACHE_EXPERIMENTS.md#e1-results-import-scope-and-visibility).

Resolve names through an explicit access context: importing scope, bare versus qualified access, module instance, and originating file where relevant.
Derived lookup views and their cached results must depend on that context and the applicable visibility rules, including visibility changes and previous lookup misses.
Keep a separate tooling query that can inspect otherwise inaccessible candidates without silently treating them as valid bindings or ordinary completion candidates.
This supports a future unresolved-identifier hint that a matching declaration exists but is not at `#scope_export`, and an explicit fix action to make it exported where appropriate.
Such an action must validate the current source, target the intended declaration/scope, and account for the export or ambiguity impact rather than blindly changing a scope directive affecting unrelated declarations.

A source change does not necessarily require discarding every module result.
A first correct implementation may invalidate the module's semantics conservatively, while retaining all unchanged file syntax.
Later, query dependencies and separate interface/body fingerprints can prevent invalidation from propagating to consumers whose observed results did not change.

An export index is not a universal sufficient interface.
A consumer may observe procedure bodies through inlining or compile-time execution, declarations through `code_of`/reflection, generated fields, or values used by conditions.
Record which interface, body, value, or reflective view each query consumed.

Modules can have cyclic dependencies.
Publish revision-local interfaces/results only at a valid completeness boundary, and retain cyclic dependency groups through a world/root owner rather than relying on naive object-to-object reference counts.

### 6.2 Loaded Files: Syntax Boundary, Shared Semantic Environment

Cache a loaded file's syntax by its own revision and syntax context.
Do not cache one universal resolved meaning for that file.
It may participate in different module instances, program configurations, visible declaration sets, and load graphs.

`#load` membership, relative path resolution, scope directives, visibility, and any order-sensitive language rules belong to module composition.
A loader should preserve those rules rather than sort/deduplicate declarations by hash.
E3 verifies repeated inclusion even for identical load paths: preserve ordered load occurrences and their scope provenance separately from shared document/syntax identity.
Repeated public declarations can collide, while repeated file-private declarations can belong to separate occurrence-local scopes; file-local ownership cannot be keyed solely by physical filename.
The current resolver's traversal-local filename suppression is therefore not a compiler-faithful general composition rule and must not be carried into the cache architecture unchanged.
Missing files and failed resolution are dependencies too: creating the missing file must invalidate the previous result.

An unchanged loaded file can still reuse semantic queries when their complete module-context dependencies validate.
The distinction is not 'loaded files have no semantic cache'; it is 'their semantics are cached in a module world, not solely against file bytes'.

### 6.3 Structs and Enums: Hashes Are Necessary, Not Sufficient

Two identically spelled structs in different modules are not automatically the same type.
Nominal identity must come from the defining declaration and its module instance.
A syntax digest is an input fingerprint used to validate that declaration's cached results.

Split useful results where dependencies differ:

- Declared member names and syntax index.
- Active members after conditions/generation, plus name lookup and exposures.
- Resolved field/member types and instantiated generic arguments.
- Struct size, alignment, offsets, and ABI-sensitive properties.
- Enum member values, underlying representation, and exported names.

A layout key includes target/ABI and all observed field-type/value/layout dependencies.
An enum member can depend on earlier implicit values and external constants.
A `#if` or generated field can alter membership without changing the outer declaration text.
`using,map` can change exposed names without changing stored field syntax.

For example, unchanged `Record :: struct { items: [CAPACITY]Item; }` cannot reuse its layout if `CAPACITY`, `Item`'s relevant layout, or the target changes.
It can still reuse its parsed syntax.
Distinct recursive types must retain identity even if their structural fingerprints happen to match.

#### Member Order and the Completed Context Type

For ordinary structs, compare member descriptors in source declaration order, including `Context_Base`.
This is a rule for the declaration's member-shape/revision fingerprint, not a replacement for nominal `TypeID`: identical ordered members do not merge distinct defining declarations or configured instances.
Reordering ordinary members changes that fingerprint even when their names/types form the same set.

The compiler-assembled `#Context` needs a special comparison rule because `#add_context` contributions may be encountered in different orders during compilation.
Its completed logical member descriptor consists of the ordered `Context_Base` descriptor plus an order-independent collection of added fields, not the compiler's discovery/append sequence.
Canonicalise the added fields by their exact canonical member-name bytes, using unsigned bytewise lexicographic order, and compare their full descriptors: name, resolved type identity, relevant attributes/default-initialiser dependencies and validated declaring provenance.
Do not sort the base members, erase field-to-type associations, or deduplicate contributions with equal names; duplicate/conflicting names retain their language error, and incomplete contribution discovery cannot establish complete context equality.
The same qualified additions and base therefore compare equal under different encounter permutations; adding/removing/changing an added field or reordering the base does not.
This rule applies to the completed logical type/member comparison, not to a claim that every intermediate context is complete or that two unrelated nominal types become equal.

Keep layout/ABI, reflection enumeration order and initialisation/evaluation observations as separate dependency-tracked facets.
If their observable result depends on actual compiler field order, offsets, target or effect ordering, validate that result independently; equal canonical context membership does not permit reusing those results or replaying serialised raw context memory across layouts.
Unqualified compiler ordering/effect behaviour requires conservative recomputation or explicit unsupported/incomplete status, not an assumed order-independent ABI.
Future semantic acceptance cases must permute the same `#add_context` contributions, change an added field, reorder `Context_Base`, and exercise duplicate/provisional membership plus layout-sensitive consumers; this definition does not claim those compiler-backed tests have run.

### 6.4 Procedures: Separate Signature, Body, and Instantiation

Cache signature information separately from body analysis, with explicit dependencies for inferred return types, defaults, constraints, captured environment, overload membership, and generic arguments.
A body-only edit may preserve a signature, but this must be established rather than assumed when inference or compile-time uses observe the body.

Changing one overload can change selection at otherwise untouched calls.
Querying only the previously selected declaration is insufficient: depend on the candidate set and relevant scope membership.
Similarly, a previously missing local or module name must be invalidated when that name becomes available.

### 6.5 Other Top-Level Declarations and Syntax Chunks

A full changed-file parse can produce a top-level declaration index and fingerprints cheaply.
The semantic system can then reuse declaration results without the syntax parser itself being incremental within the file.
This is the preferred starting point.

If needed later, immutable declaration chunks can own relative source spans and children; a file revision holds an ordered map from chunks to current offsets and document locations.
Parent/file ownership and positions belong in a revision view rather than forcing every unchanged child node to be rewritten after a prefix insertion.

Chunk identity is not its fingerprint.
Duplicate declarations, identical anonymous procedures, overloads, reorderings, and renames make hash/name/ordinal-only matching ambiguous.
Use an explicit declaration mapping policy; when uncertain, allocate a new identity and recompute rather than transfer the wrong semantic result.
Stable identity across processes is not required for every edited declaration; correct conservative remapping is acceptable.

An arbitrary declaration slice is not always independently parseable.
Here strings, scope directives, surrounding grammar/recovery, and delimiter edits can change boundaries.
Establish boundaries from a whole-file parse first, and reject chunk reuse when their context cannot be proven.

Maintain distinct fingerprints for exact source, semantically relevant syntax, interface results, and body/evaluation inputs.
Comments or whitespace may preserve ordinary type information while changing locations or source-reflective results.
Normalising literals must retain distinctions that Jai can observe, including types and exact numeric payloads where applicable.

## 7. Dependency Tracking and Invalidation

A query cache entry records explicit arguments, the result, diagnostics, and every dependency read while computing it.
Dependencies include source revisions, other query results, scope/export membership, absence of a binding, resolution candidates, module/program parameters, target settings, evaluator version/policy, generated sources, and tracked external inputs.

On a change, mark affected results potentially stale.
Revalidate inputs/dependencies on demand; recompute invalid results and propagate only changed observable fingerprints where safe.
Reverse dependency edges accelerate invalidation, but a missed watcher notification must not be able to certify stale data after restart.

Hash equality is a lookup/validation mechanism, not permission to ignore identity, context, or collisions.
Use a specified strong content digest, domain-separated/versioned serialisation, and integrity validation; use conservative recomputation for uncertain or unrepresentable inputs.
Do not persist pointer-based or process-randomised hashes.

Illustrative invalidation matrix:

| Change. | Reusable work. | Work requiring validation/recomputation. |
| --- | --- | --- |
| Whitespace before an ordinary declaration. | Many semantic values and unchanged file snapshots. | Changed-file syntax/source map and location-sensitive results. |
| Local procedure implementation. | Other file syntax and possibly the signature. | Body analysis; inline/compile-time/reflection consumers of that body. |
| Add a module-level name or overload. | Unchanged syntax across files. | Scope/candidate-set lookups, including previous misses. |
| Change a constant used by a field dimension. | Struct syntax. | Constant-dependent field types/layout and their consumers. |
| Change a loaded file's scope directive. | Its unaffected token payloads where supported. | Module composition, visibility, bindings, and affected declarations. |
| Change module/program parameters. | Context-independent syntax. | Affected configured instances, conditions, evaluation, and semantic queries. |
| Change target architecture. | Syntax and target-independent indices. | Primitive/layout/ABI-dependent results and evaluated target conditions. |
| Change a compiler or cache schema version. | Compatible source blobs where defined. | Affected persisted artifacts and evaluator outputs. |

Keep incomplete-world results explicitly provisional.
Discovering new imports or generated declarations can change name lookup; do not publish a partial export set as a complete stable interface.

## 8. Allocation and Lifetime Model

Use owned roots and stable handles instead of an implicit caller allocator lifetime:

| Owner. | Storage and responsibility. |
| --- | --- |
| Source/syntax revision. | Owns source, token payloads, nodes, syntax diagnostics, and local immutable indices, or leases their backing mapped artifact. |
| Semantic world. | Owns the revision/configuration selection and roots the module graph for a coherent editor view. |
| Semantic artifact/group. | Owns its result arrays, values, diagnostics, and dependency handles; retains syntax/world inputs needed to interpret them. |
| Query task. | Owns scratch/inference storage, cancellation state, and uncommitted output.  Published results cannot point into its scratch arena. |
| Cache store. | Owns resident artifact records, persistence bookkeeping, and eviction decisions; it does not override live client leases. |
| Editor request. | Holds a lease to its world and requested results until completion or explicit release. |

Allocation strategy is separate from logical ownership: a revision/artifact can own records allocated from a longer-lived cache service's pools without owning those pools outright.
Keep allocator state and live object addresses stable while handles or allocator data refer to them.

Consider typed pools/slabs, one per record type or suitable size class, alongside arenas.
For independently reclaimable nodes, semantic results, dependency records, and cache control records, individual frees and freelist reuse can reduce allocation churn and support partial eviction without discarding unrelated records.
Select or verify an allocator that actually supports individual frees; the name `Pool` alone does not establish its reclamation behaviour.
Variable-sized arrays, strings, and other owned payloads still need an explicit allocation and release strategy.

A hybrid is appropriate: typed pools for independently lived fixed-size records, arenas for scratch work and immutable groups normally released together, and separately owned variable-sized payloads where necessary.
`Pool` allocation does not itself prove that an object is safe to free: dependency ownership and request leases still govern reclamation, including records reachable from surviving snapshots.
Recycled pool slots also need allocation-generation validation to prevent an old handle from accepting a different object at the same address; this generation is distinct from semantic revision stamps and does not replace reader lifetime protection; the dependency handle concept described below can mitigate that.
Define synchronisation or sharding for pools accessed by concurrent tasks.

Returning an object to a freelist makes its slot reusable but may not reduce resident/backing memory.
Releasing backing pages generally requires empty slabs or allocator-specific trimming; measure retained capacity, fragmentation, reuse, and actual memory release as well as allocation counts.
Choose pool/slab granularity with those eviction goals in mind, rather than assuming per-object frees necessarily return memory to the operating system.

Do not require every query result to retain an entire project world indefinitely.
Use appropriately scoped retained artifact groups/handles and explicit world roots; measure whether a tiny result pins an unexpectedly large graph.
Query dependency cycles require graph/group ownership or reachability-based reclamation, not mutually retaining reference-counted objects.

Unchanged syntax can be shared across worlds.
Changed files create new revisions.
Old revisions remain valid while any request uses them, then become reclaimable.
A configurable memory budget and emergency pressure policy are necessary even if normal behaviour favours keeping everything resident.
Eviction must never invalidate a leased snapshot, and retention should not grow without bound during long editing sessions.

### Residency and Eviction Priority

Retaining declarations across all visibilities means preserving their discoverability and reloadable identity/metadata, not requiring every declaration's syntax and semantic payload to stay in RAM.
A bare import does not by itself demand full analysis or residency of all exports, still less all internals; materialise results according to actual query demand.
Under memory pressure, prefer evicting cold, unreferenced internal payloads before actively used results, provided they are not pinned by live requests or required resident dependencies.
Unused exported payloads can also be evicted; visibility is a useful preference, not proof of liveness.

An internal declaration can be needed by a used export through types, constants, layout, inlining, compile-time evaluation, or reflection, even if no external call names it.
Track those dependencies rather than equating 'not externally called' with 'unused'.
Keep compact indices or reloadable index references for all visibilities so qualified lookup and inaccessible-candidate hints still work after payload eviction.
Persisted dependency edges need not pin every dependency's full payload in RAM when validated handles permit safe rehydration or recomputation.

Actual reclamation is limited by allocation granularity: individual declarations cannot be freed from a still-leased whole-file arena.
Reclaim independently owned pool records where their lifetime permits, separately owned semantic artifacts, and unleased file snapshots; finer syntax reclamation requires suitable pool/chunk ownership and remains an optional measured optimisation.
Do not claim per-declaration syntax memory savings merely because semantic work is demand-driven.

### Implementation Option: Sentinel Dependency Slots

A dependency needs to be linked via a handle that can encode if a dependency:

- does not exist (last we checked - see `checked_parent_revision` below)
- we don't know yet - go find out and generate the result
- does exist, but is not loaded
- is being worked on by something (with a mechanism/ID to wait on if this needs to be a blocking read)
- is failed/unsupported etc.

Each dependency handle can carry both revision stamps:

- `checked_parent_revision`: the parent revision against which this relationship was last validated.
- `observed_dependency_revision`: the dependency result revision last validated/consumed through this handle.

The parent carries its own revision.
If it differs from `checked_parent_revision`, recheck whether the relationship still exists, still targets the same declaration/query, and still has the same arguments/context.
If unchanged, retain the result and advance the stamp; otherwise remove, replace, or regenerate as appropriate.
Perform this check before accepting even a `null` slot as a current statement of absence.

Independently, validate the dependency for the requesting world and compare its result revision with `observed_dependency_revision`.
A mismatch requires revalidating the parent's affected result, even when the parent source has not changed.
It need not force regeneration if the observed interface/value fingerprint is unchanged; conversely, a matching stamp is insufficient if the dependency has not yet been validated against its own possibly changed inputs.
Thus parent changes check the relationship, while dependency changes check the referenced result and its effect on the consumer.

These are per-link validation stamps, separate from the target's shared residency slot: different parents can have observed different revisions of the same target.
Scope stamps by owner/target identity and semantic world; bare revision numbers alone do not establish identity or persistent validity.
Compare against the version selected by the requesting world, not unconditionally the newest version, and keep mutable validation bookkeeping outside published immutable payloads.
Neither stamp replaces dependency tracking or reader lifetime protection.

All access goes through the helper: recognise the state before dereferencing, validate the target and dependencies, share existing in-flight work, and schedule computation or rehydration as needed.
The helper may yield through the declaration pipeline; an inline fast path does not imply that a cold access is cheap, synchronous, or allowed to execute compiler code without the established opt-in/host permission.
Return a protected result/lease or an explicit pending/error state, not an unprotected pointer that eviction can invalidate immediately after lookup.

Keep mutable residency slots in cache control records or side tables, outside immutable syntax and published semantic payloads; immutable dependency handles can refer to those slots.
Prefer one authoritative slot per cached target over independently cached raw-pointer aliases, unless an explicit alias-invalidation scheme is provided.
Publication and eviction must synchronise slot transitions with reader lifetime protection; an atomic pointer load/store alone does not prevent use-after-free.
An existing snapshot must continue to select its own version even when another world computes a newer target.

Never persist these pointer values or sentinel bit patterns as the artifact format; serialise explicit states/keys and reconstruct runtime slots.
Reserve and verify the proposed sentinel representations on supported Jai backends/platforms, and centralise their definitions and checks.
An explicit state-plus-pointer wrapper remains the fallback if it is clearer or safer without a demonstrated space/performance disadvantage.
A later metaprogram can enforce accessor-only use; until then, keep the slots encapsulated and their access rules explicit.

### Persistent Representation

Persist explicit records with IDs, offsets, bounded arrays, versioned node/query kinds, and source maps.
Never dump the current pointer graph, `Allocator`, `Pool`, compiler overlays, or process-local `Type_Info` objects directly to disk.

A versioned decoder can rehydrate records into owned arenas, or selected immutable artifacts can be memory-mapped through an offset-based representation.
Memory mapping is optional: 'disk-backed memory cache' means a durable backing store with resident reusable data, not a mandate to expose mapped bytes as existing Jai structs.
Start with a simple safe format; measure deserialisation against reparsing.

Cached semantic edges must refer to persisted artifact/declaration identities and validated dependency manifests, not raw pointers that happened to be valid when the editor exited.
Cross-version or missing dependencies cause a miss, not a best-effort pointer repair.

Also, at least initially, make it a text-based format so we can more easily debug it - leverage the `Text_File_Handler` module.
Later we can consider moving to a binary format for speed.

Future derived-artifact layout proposal, not the initial milestone-6 source-only layout: under the configured cache directory, keep a directory per canonical source-file/context identity, with separate filenames/artifacts for declarations belonging to that source file.
A module instantiated with different parameters must have a distinct directory identity; include other required program/semantic context discriminators rather than keying semantic storage by filepath alone.
E2 additionally requires preserving compiler-observed import-request distinctions when mapping semantic instances to directories; physical-source deduplication must not merge their nominal declarations.
Use safe encoded names or identity digests with a readable manifest mapping back to paths/parameters, not unescaped absolute paths as directory names.
Preserve artifact revisions within that layout so a new write does not overwrite data still selected by an older world.
Evaluate whether declaration files cover only top-level declarations, independently addressable nested declarations, or declarations externally reachable through supported lookup rules; externally reachable must not be equated with exported only.
Regardless of payload granularity, retain discoverability for all visibilities, ownership of non-split nested content, and complete reloadable dependencies.
This is a layout proposal to test against E10/E11, including small-file overhead and partial loading/eviction; it does not prevent sharing context-independent syntax backing across instance directories.

## 9. Persistence and Editor Operation

Earlier setup proposals, not blanket-approved defaults or final option names; the 2026-10-23 decisions select project-relative storage and no fixed RAM/disk quota by default, with optional limits and finite effective safety bounds:

- Persistence enabled by default; explicitly disabling it retains the same in-memory semantics.
- Saved and unsaved revisions persist, with separate current-disk/active-overlay metadata, private storage, and explicit recovery/discard/cleanup behaviour.
- Optional cache-directory override; the selected default is `.jaiParserCache` beside the project's `.build`, resolved from the host-declared project root, not an inferred working directory.
- Configurable memory/disk budgets (with unlimited (= all available space) as an option for disk) and retention policy, preferring resident validated data under ordinary conditions.
- Clear/invalidate operations, format/version inspection, cache-hit/miss reasons, and a way to recover from a damaged/outdated store, probably via reparse rather than a migration or similar.
- Independent workspace-trust and external-evaluation policy.
Enabling persistence is not permission to execute source code.

On restart, load a lightweight manifest and validate relevant revisions/configuration.
The initial milestone-6 profile offers verified recovery bytes and reparses authoritative current source; lazy persisted-result rehydration is a future derived-artifact capability, not an initial hit guarantee.
Do not eagerly deserialise the entire historical graph just because its files exist.
Matching hashes can avoid reparsing, but only if reading/decoding the cached artifact is itself worthwhile.

Write artifacts transactionally with atomic publication, checksums, size limits, and interruption-safe manifests.
The approved initial store-ownership policy is exclusive ownership rather than concurrent shared readers/writers; a contending editor continues in memory and reports unavailable persistence.
Immutable content-addressed blobs with controlled manifest updates are preferable to concurrent mutation of one live arena image.

Treat persisted data as untrusted input: validate bounds, schema and dependency IDs, reject corrupt/truncated entries, and reparse/recompute on failure.
Use suitable user-private filesystem permissions and avoid writing secrets or sensitive evaluated values into broadly shared caches.
Generated source and unsaved buffers can contain private code.
Persistence must disclose that scope, provide deletion/retention controls, and remove obsolete recovery references when the host reports discard/reset; historical unreferenced blobs then follow the garbage-collection policy.
Discard is not a promise of secure erasure from storage or backups.

Disk garbage collection removes unreachable or over-budget historical artifacts, not live leased data; can be triggered manually as well as being run automatically.
Per-artifact demand loading can remain lazy while eviction remains rare; those are compatible goals.
A read-only or unwritable cache directory must degrade to correct in-memory operation rather than prevent editor features from working - we need a mechanism to report systematic errors/warnings of this nature for something to surface them to the user.

## 10. Compile-Time Execution and the Official Compiler

Provide an evaluator boundary whose input is a semantic/evaluation request, resolved context, dependency closure, target/host settings, and source provenance.
Its output is structured values or generated syntax, diagnostics, provenance/source maps, observed dependencies, and an explicit support/completeness state.

Initially the evaluator may be unavailable.
Later a subprocess backend can wrap supported `#insert`, `using,map`, `#modify` and `#run` evaluations and use the official compiler; eventually a bootstrapped language-service backend may interpret the corresponding AST.
For generated text, the proposed channel uses generated source with build options including `do_output`=false and an `#insert` in it, then reads back the `.build/.added_strings_w#.jai` file(s); this is not a universal result channel for the other evaluation kinds.
Keep frontend query/ownership contracts independent of that choice.
[E5](CACHE_EXPERIMENTS.md#e5-results-compiler-evaluation-feasibility) verifies this text channel on trusted fixtures, but not as a self-contained semantic-result protocol.
Use request-owned intermediate directories, inspect all relevant workspace outputs, and distinguish successful results from stale or failed-compilation artifacts.
The dump's comment headers are not unambiguous framing or complete scope/module provenance, and `using,map` results are not automatically emitted there.

Snippet extraction is not generically semantics-preserving.
Evaluation may depend on module state, imports, private names, parameters, `#caller_code`, source paths/locations, compiler hooks, or earlier compile-time mutations.
A backend must reproduce the required context, evaluate a larger unit, or return unsupported; do not silently run an isolated expression in a different environment and call it equivalent.

Separate computed values from action execution.
A `#run` may mutate compile-time state, read files, use environment variables, launch processes, or produce outputs.
Include it explicitly in the proposed compiler-subprocess evaluator, preserving the required compilation context and capturing supported values/diagnostics/effects through the result protocol rather than assuming an added-string dump records them.
Reusing its old return value does not reproduce those effects.
Cache/replay only explicitly supported deterministic evaluations or an action model with sufficient input/output/effect tracking.
Otherwise, re-execute under an authorised policy or retain an unknown/provisional result.

In particular, treat `using,map` callbacks with mutable name arrays as ordered computations over explicit inputs, and treat generated declarations as new syntax with provenance.
Both can alter dependencies and name lookup.
Unknown external reads or effects make a result non-persistable, not permanently valid because the Jai snippet's hash matches.

Proposed explicit `using,map` evaluator: generate an owned mutable string array from the known exported member names in compiler-compatible order, reproduce the called procedure's required compilation context, invoke that procedure on the array, and capture the resulting strings through an explicit framed result channel.
Validate result cardinality, positional correspondence to the original members, and applicable identifier/collision rules; preserve empty strings as exclusions rather than dropping array slots.
Copy returned string payloads into result-owned storage before releasing evaluator storage.
Extracting just the procedure is insufficient if it depends on imports, private helpers, parameters, compile-time state, or source/caller context; preserve the necessary dependency closure or report unsupported.
E5 observed the real callback and its instrumented names, but did not test this explicit generated-array wrapper or its result protocol.
[E13](CACHE_EXPERIMENTS.md#e13-results-explicit-usingmap-wrapper) validates a bounded generated-array wrapper against real mapping, including parameter/private-helper context, exclusions, framed results, and host-owned output after process teardown; general context extraction and production evaluation remain unsupported.
The absence of automatic mapping output in added-string dumps is not evidence against this proposed wrapper.

Include `#modify` blocks in the same proposed compiler-subprocess boundary: they can change polymorphic variables or accept/reject a procedure or struct instantiation.
Preserve the enclosing declaration, actual polymorphic arguments, call/instantiation context and required dependency closure; evaluating the block as a detached snippet is not an equivalent substitute.
Capture the supported modified parameter values/types and acceptance/rejection outcome through an explicit structured protocol; added-string dumps alone do not describe those changes, and an arbitrary compiler failure is not proof that the block rejected a polymorph.
Own returned observations independently of compiler-process storage, track context/effects as for other evaluations, and report unsupported when the required context or outcome cannot be reproduced/captured safely.
E5/E13 do not qualify `#modify` evaluation; compiler-backed checks of changed parameters, accepted/rejected instantiations and context dependence remain future authorised work, not an enabled initial semantic capability.

Keep compiler subprocess evaluation disabled unless a program/module parameter explicitly enables the capability.
That opt-in is necessary but not sufficient: the embedding host must also authorise execution and apply its workspace-trust policy.
Workspace trust is external to this code; the evaluator boundary must accept the host's decision rather than equate a source-controlled setting with trusted execution.
The exact parameter/API names remain undecided.
Neither enabling persistence nor finding an old evaluation artifact grants permission to launch a process.

Apply bounded process-tree memory, timeouts, cancellation, compiler identity, temporary workspace cleanup, and bounded diagnostic/output capture.
Limits do not sandbox arbitrary code or prevent filesystem/network side effects.
Speculative editor requests must not automatically execute untrusted project code on each keystroke; authorised automatic evaluation still needs scheduling and effect controls.

## 11. Concurrency, Publication, and Editor Consistency

Do not equate a logical pipeline stage with a worker thread.
Prioritise visible-file syntax and latency-sensitive queries; schedule dependency/background work under explicit budgets.
Deduplicate identical in-flight query keys and never hold global cache locks while invoking an evaluator or waiting on another task.

Every request captures a world/revision identity.
Publish results atomically only with that identity; the editor can discard late results from superseded revisions or show them explicitly as stale.
A semantic cache hit can still require current source-location mapping before displaying diagnostics or performing a rename.

Cross-file refactoring needs a coherent world and fresh validation before applying edits, not independent 'latest' artifacts collected at different times.
Query cancellation must leave persistent entries either complete and valid or absent.
Parallel queries cannot write binding/type fields into a shared syntax snapshot.

### Lower-Level World APIs

Provide two complementary API surfaces before higher-level editor features; the following describes their contracts, not final names or signatures.

**Change notification:** accept a document/source-provider change with revision identity (and a base revision for ranged edits), then schedule background world-model updates, including parsing and affected dependency invalidation.
Use partial reparsing where supported and worthwhile, with whole-file parsing as the baseline/fallback.
Return an operation/update ticket identifying the submitted revision, with a mechanism to observe completion or wait for it; an explicit wait option can be a convenience over the same mechanism.
Define completion milestones, such as syntax/index publication or specified semantic work, rather than promising that all possible demand-driven analysis is finished.
If rapid edits coalesce or supersede work, report that outcome explicitly instead of claiming the original revision completed.

**Information request:** ask a selected world for a particular result and receive an immediate response: an available result with its world/revision and completeness, a terminal unavailable/unsupported/error state, or a pending handle that can be awaited or observed.
If the result needs computation or rehydration, schedule it or join existing in-flight work and return the corresponding pending handle rather than blocking indefinitely.
Completion produces the result or an explicit terminal outcome; requesting information does not implicitly opt into a newer world or grant compiler-execution permission.
Callers wanting information after a notified edit can wait for the relevant update milestone, select its published world, then query it and wait again only if needed.

Define cancellation, result/handle lifetimes, and notification delivery without requiring a particular threading, coroutine, or event-loop API.
Caller/UI cancellation of one current-world waiter must not discard shared work still needed by other requests.
World supersession instead cancels unfinished obsolete-world work and all its still-pending shared query waiters with a distinct `WORLD_SUPERSEDED` reason; clients decide whether to reissue against an explicitly selected current world.

### Later Editor-Feature APIs

Build completion suggestions from a context/starting position or prefix, identifier-definition lookup, and later navigation/refactoring operations on top of the world update/query APIs.
These convenience APIs should share the same revision, pending-result, cancellation, and lifetime contracts rather than inventing separate update mechanisms.
They are a higher and later API layer, not prerequisites for defining the lower-level world model.

## 12. Trade-Offs and Alternatives

| Strategy. | Strength. | Cost/limitation. | Position in this proposal. |
| --- | --- | --- | --- |
| Full reparse of changed file. | Simple, measured fast, robust after grammar-boundary edits. | Repeats syntax construction for that file. | Default baseline. |
| Existing token reuse. | Can reduce lexing while retaining independent results. | Still materialises a full token snapshot. | Preserve as a separately measured option. |
| Existing AST copier. | Existing eligible-shape/lifetime coverage. | Copies and relocates; no demonstrated retained-byte or median advantage locally. | No decision made here; not a prerequisite for caching. |
| Whole-file snapshot cache. | Avoids all syntax work for unchanged files. | Requires owned immutable lifetime and validation. | Primary syntax reuse boundary. |
| Module/query semantic cache. | Reuses expensive meaning across files and sessions. | Needs context identities, dependencies, persistence, and invalidation. | Primary semantic direction. |
| Immutable syntax chunks. | Can share unchanged declaration storage and fingerprinting. | Boundary, identity, source-map, and ownership complexity. | Optional optimisation after measurement. |
| Persist source only and reparse. | Very simple format; source retrieval can be cheap. | Does not satisfy avoiding repeated syntax parsing by itself. | Fallback, not the complete restart cache. |

The module cache and declaration-query cache are complementary layers, not two independent copies of every AST and semantic object.
A module artifact indexes/references its files and results.
Content-addressed backing can deduplicate bytes without conflating nominal identities.

Separate syntax and semantics by data contract first.
This does not require immediately splitting the public Jai module into several packages or implementing a general-purpose incremental computation framework.
Likewise, full semantic coverage is a goal, not a claim that the present helper layer can become a full typechecker merely by adding cache lookups.

## 13. Correctness and Benefit Criteria

Correctness gates should compare cached and uncached execution over the same world, not only assert that cache hits occur:

- Equivalent syntax, diagnostics, bindings, type identities/values/layouts, generated results, and editor locations where supported.
- Correct misses for parameter, target, resolver, dependency, version, file-creation/deletion, and external-input changes.
- No cross-module nominal-type conflation or stale overload/name-lookup results.
- Compiler-verified bare/qualified import behaviour across `#scope_export`, `#scope_module`, and `#scope_file`, including nested-scope bare versus named imports, visibility edits, cached misses, and inaccessible-candidate hints that do not create false bindings.
- Independent surviving worlds after old-world release, eviction, restart, and cancellation.
- Correct update-ticket and pending-query completion, revision selection, superseded-update reporting, and independent cancellation of waiters sharing work.
- Correct incomplete/unsupported states without converting unknowns into errors or stale successful results.
- Corruption recovery, bounded deserialisation, multi-process publication, and safe handling of untrusted evaluation.

Measure cold start, validated warm restart, unchanged-project queries, a local body edit, interface/layout changes, dependency changes, malformed typing, and repeated refactoring/navigation.
Report median/tail editor latency, hashing/validation/deserialisation costs, memory high-water/residency, disk size, bytes read/written, invalidation fan-out, and retained old worlds.
Keep external compiler startup/evaluation costs visible rather than hiding them inside a generic cache metric.

The agreed policy is to measure comparable deltas and evaluate the trade-offs afterwards, not set numerical acceptance thresholds in advance.
The workload/procedure still needs approval, and future whole-project warm-restart/edit-to-result measurements must not be confused with the existing bounded experiments.
Earlier hypothetical large-file savings for a broader copier are not evidence for this architecture's performance, and syntax persistence should earn its complexity relative to simply reparsing the selected files.

## 14. Decisions, Scope and Open Items

### Decision Record

This table is the single authoritative record of review decisions; other sections and the companion documents refer to it rather than restating it.
All eight are approved as design directions.
Detailed contracts, API review and whole-specification sign-off remain pending.
The fifteen-operation interface in [CACHE_CONTRACTS.md](CACHE_CONTRACTS.md#operation-and-outcome-table) was approved as the specification baseline on 2026-10-21, subject to exact schemas and API review.

| Decision. | Direction. | Approved. | Remaining boundary. |
| --- | --- | --- | --- |
| R1: Initial coverage. | Syntax-first qualification slice: owned whole-file syntax/diagnostics/indices and revisioned source/world operations, including source/unsaved-recovery persistence, qualified on the recorded Windows x64 toolchain.  Configured semantic queries, evaluator execution and higher editor features are explicitly unsupported until qualified. | 2026-10-20. | Narrows the first deliverable, not the eventual full-syntax/full-semantics goal.  Other compilers, filesystems and platforms need their own qualification. |
| R2: Persistence and recovery. | Persistence enabled by default at `.jaiParserCache` beside the project's `.build`, with an explicit override.  Preserve current disk and latest unsaved revisions without automatic expiry or optional persistent history; the editor supplies undo/redo.  Full AST reload is not required. | 2026-10-23. | Recovery requires host confirmation; no automatic restore, source overwrite or secure-erasure guarantee. |
| R3: Source/provider protocol. | Finite explicit captures, unknown-versus-absent states, host-controlled overlays and byte-based exact-base edit batches, with declared consistency and explicit successor captures for unavailable historical discovery. | 2026-10-21. | Logical source transactions are not atomic disk/editor writes. |
| R4: Execution/delivery. | Logical serialised coordinator with token-checked worker completion, host-pulled outcomes, independent waiter cancellation and lease-safe shutdown. | 2026-10-21. | Milestone 5's worker/reaper model, reservations, FIFO/stop policies and native bindings need review and concurrent tests. |
| R5: Identity and invalidation. | Preserve configured instance/load-occurrence distinctions and nominal identity; miss conservatively on uncertain matches; invalidate semantics per whole module until finer tracked facets are qualified. | 2026-10-21. | Milestones 3-4 supply the draft encodings and algorithms; no semantic feature is enabled. |
| R6: Resources and store ownership. | No configured RAM/disk quota by default, with optional finite limits; exclusive ownership by one process/writer session per project/provider store; no optional persistent history.  Contention degrades persistence, not source analysis. | 2026-10-23. | No shared-store concurrency, eager allocation, resource-availability guarantee or unchecked decoding follows. |
| R7: Performance evaluation. | Measure comparable deltas first and evaluate the trade-offs afterwards; no preselected pass/fail percentages.  Latency, including tail latency, is the primary concern; memory and storage are secondary trade-offs (confirmed 2026-10-20). | 2026-10-23. | Correctness and leak checks remain mandatory.  The earlier 10%/5%/four-times proposals are withdrawn. |
| R8: External assumptions. | Qualify behaviour implemented by our code (interruption-safe staging/rename, complete-or-rejected publication, ownership, cleanup and graceful failure) under stated filesystem/OS primitive assumptions. | 2026-10-23. | No power-loss, hardware/filesystem durability or OS-cold claims, and no external certification campaign. |

#### R2/R6 Policy Details

Resolve the default relative `.jaiParserCache` against the host-declared project root containing the project's `.build` directory, not the service process's incidental working directory.
The host resolves it to an absolute native root for contained file operations; absence of a declared project root requires explicit configuration rather than guessing.
Project-local storage is permitted even inside the source repository; its private source/recovery bytes must not become ordinary parser input or an implicitly versioned source artifact.
The host must exclude the managed directory from source discovery/watch ingestion and arrange version-control exclusion before first creation, or request explicit user acknowledgement if exclusion cannot be established.
An override may select a host-appropriate temporary location such as `/tmp/JaiParser/cache`; temporary storage can disappear and is not a stronger recovery guarantee.
The stable default path does not weaken namespace/workspace/provider validation or authorise adopting an unrelated existing directory.

No configured quota does not mean reserving all free resources, trusting persisted lengths, unlimited nesting or a promise that a later allocation/write succeeds.
Optional finite ceilings remain enforceable.
Effective implementation/representation bounds, checked aggregate accounting and ordinary allocation/write failure handling apply in both modes.
Do not convert a transient free-space/RAM observation into a guaranteed reservation or silently evict protected recovery to satisfy another allocation.

Under R8, our code makes its best interruption-safe publication effort using parallel staging files and replacement/rename with documented assumptions; it is not responsible for proving that external storage honours them.
An excluded external guarantee is neither a passed test nor permission for our code to ignore failed calls, publish partial state or violate retained ownership.
These decisions supersede any conflicting proposal in the contract drafts.

### Initial Capability Boundary

R1 approved this boundary.
Full syntax/semantic coverage and configured-module caching remain the eventual direction; the syntax-first slice must not silently become the permanent product boundary.
Deferring semantic operations is not permission to omit the semantic ownership, identity, dependency and unsupported-state extension contracts from the specification.

| Area. | Initial capability. | Explicit boundary. |
| --- | --- | --- |
| Qualification. | Windows x64 with the recorded Jai beta 0.2.030 toolchain; fast-backend correctness and LLVM performance runs.  Test our adapter on the measured ReFS environment under stated OS/API assumptions. | Qualify our code, not the external filesystem/hardware (R8); do not generalise results to other compiler versions/platforms.  Compatibility remains versioned. |
| Source and syntax. | Disk and editor-buffer revisions, owned immutable whole-file syntax/diagnostics, exact source reconstruction, and syntax-derived declaration/span indices.  Reuse unchanged snapshots; fully parse changed files, including malformed edits. | No subtree-sharing, syntax-chunk store, or AST-copy requirement.  Syntax-derived indices are not resolved bindings, types, or a complete semantic declaration index. |
| World update/query. | Revision-tagged change tickets and syntax/index publication milestones; selected-world queries return available, pending, superseded, cancelled, failed, or unsupported outcomes as applicable.  Leases protect retained snapshots. | No promise that syntax publication completes all future semantic analysis.  Queries never switch to a newer world implicitly. |
| Composition and semantics. | Preserve authored import/load requests and context in syntax; define the extension boundary for configured module instances and semantic query results. | The initial service does not claim semantic import closure, member/type inference, overload resolution, constant/layout evaluation, or semantic navigation/refactoring.  Requests needing these return unsupported, not a guessed binding, empty successful answer, or false language error.  Existing resolver behaviour is not silently reclassified as qualified cache-backed semantics. |
| Persistence. | A versioned pointer-free text store for exact source revisions, document/recovery metadata, and manifests, with safe validation and fresh parsing as a valid reconstruction path (R2/R6).  Preserve the future syntax/semantic artifact boundaries. | Persisting a complete AST is not required; the experimental graph codec is not adopted.  Milestone 6 supplies the format/publication/recovery draft; its API review and native/runtime qualification remain open. |
| Recovery and failure. | Exact disk/overlay selection, host-confirmed unsaved recovery, explicit save/reset/rename/delete transitions, corrupt/incompatible artifacts treated as misses, and cache diagnostics separate from language diagnostics. | No automatic resurrection of an obsolete overlay or permission to overwrite a live buffer.  Cache write failures must not reject an otherwise valid source update. |
| Evaluation and later features. | Evaluator capability initially unavailable; source-controlled opt-in and host authorisation remain mandatory prerequisites for any later backend.  Later editor features build on the same world contracts. | E5/E13 are feasibility evidence, not evaluator implementation.  No automatic compiler execution, cached effect replay, semantic rename/completion, or export-fix feature is included in this initial slice. |

### Correctness Gates

Each gate is required for the corresponding initial capability.
Unsupported later capabilities must be labelled explicitly and excluded from successful-feature counts.

| Gate. | Required check and oracle. | Current evidence versus remaining work. |
| --- | --- | --- |
| C1: Syntax equivalence. | Compare retained, reparsed, and persisted/reconstructed results with independently owned fresh parses of the same exact source/context.  Check tokens, tree payloads, diagnostics, recovery, spans, and exact source bytes, including malformed edits. | E6/E12 establish bounded oracles.  Apply them to the initial implementation and its full declared supported syntax matrix; no lifetime aliases or silent mismatches are acceptable. |
| C2: Identity and source selection. | Exercise parameter/configuration/version changes, path aliases, file creation/deletion/rename, negative lookups where supported, and disk/overlay save/reset/restart transitions.  Compare selected source/context against an explicit event-trace model. | E1-E4/E7/E11 supply rules and bounded controls.  Production identities/source-provider semantics and configured-semantic coverage are not qualified.  Uncertain matches must miss. |
| C3: Ownership and publication. | Retain old worlds through edits, eviction, input release, and newer-world teardown; verify exact old/new results, stale-generation rejection, and zero owned live allocations after final release.  Force out-of-order completion and shared-waiter cancellation. | E6/E8/E9 support local models.  Real-service lease/publication/race tests remain necessary; a scheduler model is not a concurrent implementation test. |
| C4: Persistent-store failure. | Validate before dereference/allocation using explicit format/read/allocation bounds; reject incompatible, truncated and corrupt data.  Test interrupted and competing writers, denied writes, restart, and leased-entry GC; compare selected state with fresh source reconstruction. | E10/E11 inform the design, not a safe production loader.  The E12 assert-aborting graph reader and post-read limits do not satisfy this gate.  Source operations must survive cache failure. |
| C5: Honest capability states. | Trace notify, wait, world selection, query, supersession and cancellation; verify each promised milestone/terminal outcome.  For unsupported semantics/evaluation, assert explicit unsupported results and no compiler child process. | E8/E13 supply limited outcome/protocol evidence.  Host integration, untrusted-workspace behaviour and executable public-contract tests remain open. |

### Performance Comparisons

Under R7, P1-P5 identify comparisons to measure, not go/no-go thresholds, editor guarantees or runtime defaults.
Use paired same-work comparisons against an equivalent fresh/owned baseline on the same workload and hardware, not percentages of total project compilation time.
Use the E12 inventories as the starting syntax corpus, include a representative larger project before generalising, and keep synthetic authored controls separate from real-project aggregates.
Run at least 21 measured trials per mode after declared warmups, alternate/rotate order, and report per-workload median, nearest-rank p95 and raw samples in at least two separate local rounds.
This is a reproducible screening procedure, not a confidence interval or worst-case bound; mixed or noise-sized results are inconclusive rather than a pass by averaging inventories.
Include source validation, hashing, I/O, allocation, result publication, and lifecycle cleanup consistently in competing modes.

| Comparison. | What it measures. | Reporting rule. |
| --- | --- | --- |
| P1: Resident unchanged request. | End-to-end validated resident syntax/index reuse versus equivalent fresh parsing/index construction, including validation and result acquisition. | Absolute and relative median/p95 deltas per real inventory and round.  Exact-input checks and C1 still apply; a raw pointer lookup is not an equivalent competitor. |
| P2: Changed-file update. | Notify-edit through usable revision-tagged syntax/index publication versus a fresh changed-file path with identical retained-world ownership, for body/interface/layout/malformed/repair sequences. | Absolute and relative median/p95 deltas; report unrelated-file reuse separately.  Neither compiler time nor an isolated parser call substitutes for service latency. |
| P3: Optional persisted AST reload. | If later supported, fresh-process validation/load/reconstruction versus source validation/parsing, with wall/worker boundaries separate. | Report complete equivalent work and declared storage conditions.  Unsupported initially; it cannot waive required source/recovery persistence or imply OS-cold qualification. |
| P4: Retained memory. | Peak upstream backing/process memory versus an equivalent current-world-only baseline. | Report separately a stress test with two older worlds explicitly leased by clients, including sparse eviction and long edit/eviction cycles, with the same live-world set in both modes.  This is not automatic revision history.  Zero owned live allocations after final release is mandatory. |
| P5: Managed store size. | Steady-state managed bytes versus represented retained source bytes, with peak staging/cleanup space separate. | Include metadata/indices/source/artifacts, count retained source revisions consistently, and report quarantine/protected roots separately.  Evaluate alongside latency and recovery value. |

Before running acceptance measurements, agree workloads, units/timing boundaries, supported host/toolchain and equivalent baselines.
Current experiments favour resident reuse and show the verbose graph reload is slower; they do not measure the future editor service.
Semantic dependency and editor-workflow measurements in section 13 remain necessary before adopting finer semantic granularity or making ReSharper-like performance claims.

### Open Decisions

These are approvals or choices within the drafted contracts; the decision record above is not reopened.

- Approve or revise the drafted host-confirmation, recovery/clear/repair and privacy contracts, including their concrete host binding.
- Review the concrete host/store/native bindings and their enforcement of project-root resolution, discovery/version-control exclusion, permissions and contention diagnostics.
- Review the initial provider adapter's declared case/alias/link/reappearance policy and source-visible path binding against the drafted canonical encodings.
Additional-platform adapters remain deferred rather than requiring one universal path rule now.
- Approve the drafted typed parameter/context encodings and conservative identity rules (milestone 4); decide which later compiler-compatible semantic/evaluation profiles can support them.
- For a later evaluator, choose the exact program/module opt-in parameter and host permission API, supported compilation-context reproduction and structured result/effect protocols for `#insert`, `using,map`, `#modify` and `#run`.
- Approve the workload/profile matrix and larger-project (W3) manifest, then evaluate observed latency/memory/storage deltas.
- Decide whether optional syntax chunks or finer cache granularity are worthwhile only after comparable whole-file/query measurements; they do not block the initial whole-file design.
- Decide whether to adopt, defer or reject [sentinel dependency slots](#implementation-option-sentinel-dependency-slots); they remain an encapsulated implementation option until then.

### What a Completed Specification Must Define

A completed specification turns the following into explicit contracts, state transitions, and acceptance tests.
Full future semantic coverage does not mean fully specifying every Jai rule before the first migration; define the architectural contracts, a supported initial slice, and an extension/unsupported-state contract.

| Area. | Definition needed before migration planning. |
| --- | --- |
| Scope and coverage. | Initial supported platforms/compiler versions, syntax and semantic operations, malformed-code behaviour, explicit exclusions, and the route to full coverage.  Separate initial requirements from later capabilities. |
| Identity. | Document/path/alias rules, module and program parameter canonicalisation, declaration/type identity, edit matching, target context, and persisted versus session-local IDs.  Specify conservative misses for uncertain matches. |
| Source and worlds. | Source-provider interface, edit coordinate units/base revision, disk/overlay precedence, save/reset/rename/delete/recovery events, world capture/publication, and how newly discovered files enter a coherent world. |
| Syntax and semantic records. | Owned record schemas, syntax/semantic boundary, spans/source maps, diagnostics, derived indices, versioned references, and compatibility policy for existing compiler-shaped nodes. |
| Module composition. | Verified bare/named import and loaded-file scope rules, visibility, duplicate/cyclic imports, parameter propagation, and all-visibility indices versus access-filtered lookup. |
| Declaration pipeline. | Initial stage/query catalogue, prerequisites and readiness milestones by declaration kind, generated-work discovery, provisional results, legal recursion, and failure/unsupported states. |
| Dependency validity. | What each query observes, negative lookup/candidate-set dependencies, parent/dependency revision semantics, dirty propagation, fingerprint equality, and validation after restart. |
| Handles and ownership. | Handle/state layout, per-link versus shared-target metadata, allocation generations, leases, pool/arena ownership, cycle reclamation, eviction transitions, and safe rehydration. |
| Scheduling and API. | Change/update tickets, immediate-result-or-pending queries, completion milestones, supersession, cancellation, wait/notification delivery, threading/reentrancy, priorities, and shutdown. |
| Persistence. | Initial text schema using `Text_File_Handler`, keys/manifests, validation/version rejection, publication/locking, corrupt-store recovery, unsaved metadata, GC, budgets, and cache/system diagnostics.  Binary encoding is not an initial requirement. |
| Evaluation boundary. | Disabled/unsupported behaviour initially, opt-in parameter and host permission, request/result/provenance contract, tracked inputs/effects, and limits of compiler snippet equivalence.  Implementation may remain deferred. |
| Acceptance. | Cached-versus-fresh oracles, supported-language cases, race/lifetime/restart/failure tests, representative workloads, and measured latency/memory/disk deltas. |

Experiments inform product decisions (initial coverage, host integration style, cache defaults, recovery retention, acceptable performance trade-offs); they do not choose them.

### Experiment Summary

Full procedures, measurements and limits are in [CACHE_EXPERIMENTS.md](CACHE_EXPERIMENTS.md).
Each conclusion holds only within its experiment's stated bounds.

| ID. | Topic. | Conclusion. |
| --- | --- | --- |
| E1. | Import scope and visibility. | Verified which scope receives imported names, lexical namespace binding, and qualified module/file visibility. |
| E2. | Module identity and program configuration. | Canonical source plus effective parameter values is insufficient for compatible nominal identity; program configuration is per module and main-program controlled. |
| E3. | Loaded-file composition. | Preserve load occurrences rather than deduplicating membership; share syntax without sharing contextual bindings or nominal declarations. |
| E4. | Paths and source context. | Keep physical document identity, source-visible path context, and compiler-compatible module identity distinct. |
| E5. | Compiler evaluation. | The text channel works for bounded trusted generators but is not a fresh, self-contained semantic-result protocol; evaluator support remains deferrable. |
| E6. | Syntax/semantic independence. | Owned syntax and external semantic tables survive independent teardown; current in-node bindings alias across shallow snapshots. |
| E7. | Dependency and revision validation. | Parent relationships and target revisions need independent validation; missing names and candidate sets are dependencies; conservative module invalidation is correct but recomputes more. |
| E8. | Pipeline milestones and scheduling. | Publish individual milestones, deduplicate world-keyed work, cancel waiters independently, and diagnose actual unresolved cycles rather than idleness. |
| E9. | Allocation and eviction. | Typed slots enable record reuse, but payload ownership and bucket/group reclamation determine backing retention. |
| E10. | Bounded text artifacts. | An explicit bounded schema preserves exact bytes and numeric bits; payload-heavy text can cost more than fresh parsing. |
| E11. | Store publication and recovery. | Immutable digest-addressed blobs plus locked manifest replacement preserve complete selected states under the tested interruptions; recovery is host-confirmed. |
| E12. | Real-source baseline and reload. | Validated resident reuse is favoured; the verbose owned-graph text reload is slower than fresh parsing, so the graph codec is not adopted. |
| E13. | Explicit `using,map` wrapper. | The wrapper works for its supported slice if it preserves context and positional exclusions and publishes only after successful compilation. |

### Exit Criteria and Migration Planning

The specification is ready for migration planning when:

- [x] Every R1-R8 direction is recorded explicitly, without an implicit production default.
- [ ] Every initial requirement has exact schemas/protocols: owner, identity/version rule, state transition, failure behaviour and executable acceptance criterion; remaining items are explicitly deferred rather than accidental gaps.
- [ ] The contracts have been checked together for conflicts: provider versus analysis frontiers, current versus retained worlds, task versus waiter lifetime, source availability versus store durability, and logical identity versus artifact revision.
- [ ] The workload/platform matrix and measurement procedure are agreed.
- [ ] Later capabilities have extension/unsupported contracts.
- [ ] The user has signed off the whole specification.

Only then write the migration plan, mapping current code, tests, and public operations to the approved contracts.
That plan must identify replacement/reuse/removal boundaries, dependency-ordered buildable steps, temporary adapters or deliberate API breaks, test/oracle preservation, persistence rollout/version rejection, cutover criteria, and cleanup.
Audit the current implementation again at that point: the present inventory is a starting point, not a promise that every migration task is already known.
Implementation authorisation, migration sequencing and the AST-copier keep/drop decision remain separate; the copier decision is an independent measured decision, not a consequence of the new model.

## 15. High-Level TODO

These are design/capability goals, not an ordered migration plan; no production changes are authorised by this checklist.
Qualification items apply only after separate implementation authorisation, using independent oracles (see [status conventions](#document-map-and-conventions)).

### Completed Specification and Evidence Work

- [x] Record R1 (2026-10-20), R3-R5 and the fifteen-operation baseline (2026-10-21), and R2/R6-R8 (2026-10-23) in the decision record.
- [x] Draft the initial capability boundary, C1-C5 correctness gates and P1-P5 measurement procedure.
- [x] Draft the core source-event, world, ownership, ticket and query-outcome contracts with T1-T8.
- [x] Draft the source-provider capture contract with V1-V8.
- [x] Draft the source/update/query interface schema, operation/outcome table, worked edit protocol and latency mapping, and repair bootstrap/retry/shutdown gaps in a consistency pass.
- [x] Complete milestone 2: close the current-producer syntax registry for all 50 generated layouts, the base-node `DIRECTIVE_THIS` route and all auxiliary helpers.
- [x] Complete the milestone-3 draft: exact values, signatures, accessors, provider/adapter admission, optional quota requests and finite effective bounds, plus the trivia-required token registry and value encodings.
- [x] Complete the milestone-4 draft: identity allocation, restart continuity, declaration matching, typed keys, completed `#Context` comparison and deferred semantic records, with D1-D8.
- [x] Complete the milestone-5 draft: ordering, reservations, task attempts, delivery, cancellation and shutdown, with X1-X8.
- [x] Complete the milestone-6 draft: store grammar, record schemas, commit protocol, pins, recovery, collection and administration, with S1-S8.
- [x] Draft milestone 7: A1-A15, W1-W6 and evidence verdict rules.
- [x] Run and record E1-E13 and the two E12 reload follow-ups.
- [x] Exclude OS-cold and external storage guarantees from the initial scope (R8).

### Approval and Sign-Off

- [ ] Obtain explicit whole-specification sign-off (milestone 8) after the user finishes reading.
	- [ ] Resolve each [open decision](#open-decisions).
	- [ ] Obtain API review of the milestone-3 interface, including context registry and adapter descriptor/platform-policy alternatives.
	- [ ] Obtain API/identity-authority review of milestone 4.
	- [ ] Obtain detailed execution/profile/native-API approval for milestone 5, documenting effective safety minima/ceilings and optional quotas and binding provider/store finalisation to stated OS/API assumptions.
	- [ ] Review milestone 6's store/native/API/issuer contracts.
	- [ ] Approve the milestone-7 larger-project manifest and workload/profile configurations; do not infer unresolved defaults from test fixtures.
	- [ ] Specify and review the extension route to broader syntax/semantic/platform coverage.
	- [ ] Confirm that the approved drafts define owned immutable syntax snapshots, explicit ownership/reclamation, the safe versioned persistent store, cache-backed source/syntax capabilities, and update-ticket/pending-query APIs.

### Qualification After Implementation Authorisation

- [ ] Qualify the core and source-capture contracts.
	- [ ] Turn T1-T8 into executable acceptance cases.
	- [ ] Qualify V1-V8 and the host's authority/immutability claims against actual adapters.
	- [ ] Qualify the bootstrap/retry/shutdown protocol against V5/V6, X7/X8 and T8.
- [ ] Qualify the milestone-3 syntax projections against fresh lexer/parser output.
	- [ ] Token tags/aliases, field-role restrictions, trivia-enabled origins and rejection of non-trivia full-featured profiles.
	- [ ] Token value union routes, flag combinations, decoded-value ownership and exact source/trivia reconstruction.
	- [ ] Shared-region ownership, nested entry counts/containers, compound routes, and rejection of cycles/unregistered sharing.
	- [ ] `#program_export` metadata correlation and ownership; establish a declaration `#export` producer path or retain the mapping gap.
	- [ ] Assembly visit paths/order, active versus inactive fields, malformed/opaque regions and same-token identifiers.
	- [ ] Type-instantiation form/route correlation, flag conflicts, dimension/element order, recovered constraints and wrapper IDs.
	- [ ] Literal active arms, aggregate/name-list routes, null-pointer handling and owned values.
	- [ ] Procedure visit order, parameter aliases, unnamed slots, quick-body origins and suffix ownership.
	- [ ] Aggregate/enum-mode routes, enum-member entry origins, conditional branches, modifiers and default-assignment exclusions.
	- [ ] Control-flow visit order, default versus recovered conditions, branch/block observations and loop/index exclusions.
	- [ ] Call/context visit paths, cast source order, unattached arguments, folded literals and recovered operator/suffix shapes.
	- [ ] Directive routes/aliases, scalar ownership, insert clause order and partial/discarded payloads.
	- [ ] Compound metadata placement, using order/alias contexts, base-node kinds and overwritten/recovered metadata.
	- [ ] Compound route evidence: choose producer route observation versus a version-bound correlation adapter, then qualify routes, recovery, binding counts and stale/conflicting evidence.
	- [ ] Adapter build/registry identities, capability admission, adapter-only context changes and local coverage gaps.
	- [ ] Name-token correlation, source versus producer bytes, name-specific recovery and anonymous/missing distinctions.
	- [ ] Coverage aggregation/order, safe partial records, unlocated gaps and preservation across reuse.
	- [ ] Scope-basis ownership/list correlation, branch isolation and no-directive versus unavailable evidence.
	- [ ] Declaration entry/region sequences, nested target/payload ownership, partial containers and cross-result renumbering.
	- [ ] Committed recovery correlation, expected/skipped/inserted events, compound attribution and cursor-restored attempts.
	- [ ] Completeness-arm admission, outer/inner agreement and rejection of truncated snapshot/diagnostic publication.
	- [ ] Derived-only retention, reference-domain validation and independent copy/remapping of borrowed backing.
	- [ ] Selection-independent query contents, invalid filter fields and explicit output-pressure outcomes.
	- [ ] Diagnostic-summary agreement across query kinds, duplicate/related record counts and unavailable/conversion evidence.
	- [ ] Aggregate readiness/publication ordering, unsupported admission, required-task failure and delayed query packaging.
	- [ ] Document-set permutations, duplicate/foreign identity rejection, alias separation and unchanged ordered source transactions.
	- [ ] Wrong/unknown schema tuples, unsupported outcomes, legacy-store misses and retained-schema access.
	- [ ] Diagnostic/index mappings: origins, malformed messages, repeated/compound/recovered names and visibility/traversal coverage.
	- [ ] Executable identity/payload review vectors.
- [ ] Qualify milestone 4's allocation/restart/matching boundary cases, and D1-D8 for any separately authorised semantic profile, using fresh/compiler oracles.
	- [ ] Qualify context-contribution permutations, base/member changes, duplicates/provisional membership and layout-sensitive consumers.
- [ ] Implement and qualify X1-X8 under real concurrent workers and provider/allocator failures with ownership/order/deadline oracles.
- [ ] Implement and qualify S1-S8 with strict-wire, source/commit/pin/allocation oracles and our native failure/interruption paths; make no power-loss guarantee.
- [ ] Run every applicable milestone-7 case with replayable evidence; qualify compiler-backed semantic cases only under a separately admitted future profile.
- [ ] Measure P1-P5 on the agreed workloads and evaluate the deltas; extend to semantic dependency/editor workflows only under separate scope.

### Later Design Goals

- [ ] Define coherent semantic worlds, declaration/type identities, versioned handles, and query-result states through full Jai coverage.
- [ ] Define module-instance composition and canonical parameter/context keys, including entrypoint program parameters, loaded-file membership, all-visibility declaration retention, and access-context lookup views.
- [ ] Define dependency recording and invalidation for successful/failed lookup, overload sets, constants, conditions, layout, generics, generated declarations, and cycles.
- [ ] Define an optional evaluator contract with context reproduction, provenance, dependency/effect tracking, unsupported states, trust controls, and bounded subprocess execution.
- [ ] Define inaccessible-candidate diagnostics and explicit export fix actions, separate from ordinary identifier resolution and validated against current source and export impact.
- [ ] Benchmark supported editor workflows in section 13 before choosing chunk-level syntax reuse or finer cache granularity.
- [ ] Revisit the existing AST-copier decision independently, using its measured benefit and preserved correctness contracts.
- [ ] After sign-off, write a separate migration/implementation plan from the current parser.
