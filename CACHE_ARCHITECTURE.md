# Syntax, Semantics, and Persistent Cache Architecture

Status: design proposal, 2026-10-15.

This report describes the intended model and its trade-offs, not an approved API, implementation sequence, or migration plan.
Existing APIs have no consumers that require compatibility.
The AST-copier keep/drop decision remains separate and unresolved.

## 1. Purpose and Confirmed Direction

The primary product is a long-lived editor service: eventually ReSharper-like support for Jai, including incomplete code, navigation, diagnostics, refactoring, and progressively complete semantic understanding.
Building a replacement Jai compiler is not the objective.

The user confirmed these requirements during this design discussion:

- Full syntax and semantic coverage is the eventual goal; useful partial coverage is acceptable on the way.
- Fast syntax parsing is an advantage to exploit, not work that must always be avoided through elaborate subtree copying.
- Cache module syntax and semantic results for a configured module instance.  Absolute file location, module parameters, and the current program parameters are part of that identity.
- Retain loaded-file syntax independently of the module context in which its declarations acquire meaning.
- Consider independently cached semantic results for types, enums, procedures, and other declarations.
- Design for persistent caches now.  They should survive editor restarts, remain resident in memory when useful, and be evicted only when necessary rather than routinely discarded after requests.
- Persistence should be configurable, provisionally enabled by default, with a caller-supplied storage location option.  The exact configuration contract is still proposed below.
- Persist unsaved revisions as well as saved revisions when persistence is enabled, with explicit document-state tracking and recovery/cleanup controls.  Restoring or discarding a buffer must not accidentally select its obsolete unsaved revision.
- Eventually use isolated official-compiler subprocesses for evaluations such as `#insert` and `using,map`, where necessary.  A future bootstrapped language-service evaluator could replace that backend, but its availability and API are not assumed.
- Compiler subprocess evaluation requires explicit opt-in through a program/module parameter, plus host permission where applicable.  Workspace trust is an external integration responsibility, not something the parser can infer.
- Do not implement that evaluator simply to complete this architecture.  Expose unavailable operations honestly until they block a required feature.
- Conservative whole-module semantic invalidation is an acceptable initial baseline; finer declaration/query reuse can grow incrementally.

**Recommendation:** reuse whole immutable file snapshots first, represent semantic work as dependency-tracked queries, and persist explicit pointer-free artifacts.
Reparse changed files by default.
Add syntax chunks or finer semantic caches where they produce measured editor benefits, not merely higher reuse counts.

## 2. What Exists Today

The current implementation already has separable operations, but not independently shareable syntax and semantic ownership:

| Surface | Current behaviour | Architectural consequence |
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

| Identity | Meaning |
| --- | --- |
| `DocumentId` | A resolved source-document identity, including its absolute path and filesystem identity policy. |
| `SourceRevision` | Exact source bytes plus their content digest.  An unsaved editor buffer is a revision even if disk contents differ. |
| `SyntaxKey` | Document identity, source digest, syntax configuration, and parser/schema version. |
| `ModuleInstanceId` | Resolved module entrypoint identity plus canonical module-parameter values and entrypoint program-parameter values. |
| `SemanticContextId` | Module instance, target/type environment, resolution configuration, evaluator policy/version, and relevant language configuration. |
| `DeclarationId` | A declaration within its owning module instance and revision mapping; not just its name or syntax hash. |
| `TypeId` | Nominal semantic identity rooted in the defining declaration, with canonical instantiation arguments where applicable. |
| `QueryKey` | The semantic operation, subject identity, explicit arguments, context, and query implementation version. |
| `ArtifactKey` | A validated query or syntax result together with the versioned input/dependency fingerprints needed to reuse it. |

The names above describe responsibilities, not final Jai API declarations.

### Paths and Source Revisions

Resolve a module name or relative load against an explicit resolver configuration before looking it up in the cache.
An absolute path is necessary, but a raw path string is not sufficient: Windows casing, separator spelling, symlinks, and aliases can otherwise create accidental duplicates or conflate intended identities.

Define canonical document identity and retain the source-visible path spelling separately.
Location/path-sensitive constructs such as `#filepath`, relative loads, and diagnostics can observe the document context; identical bytes in different files are not automatically interchangeable results.
Do not merge module identities across symlinks until the language/path policy is explicit.

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

Canonicalise values by type and semantic value, not expression spelling, pointer address, iteration order, or locale-dependent printing.
For values with identity or effects that cannot yet be serialised canonically, mark the instance non-persistable or use a conservative session-local identity.
Include dependencies of default expressions and parameter evaluation.

Program parameters originate at the entrypoint and propagate consistently to imports; they are not independently overridden per imported file.
A change may conservatively invalidate the program's semantic contexts initially.
Later queries may depend only on the parameters they actually read, without weakening the module-instance ownership model.

A module-instance identity groups results; it does not certify that they are current.
Source/dependency revisions, target settings, resolver changes, and implementation versions must still validate every reusable artifact.
The same parameterised instance can have several immutable revisions alive simultaneously.

## 4. Syntax and Semantics Must Be Independently Owned

### Syntax Snapshot

An owned syntax snapshot contains exact source bytes, document identity, tokens/trivia, decoded token payloads as needed, syntax nodes, source spans, syntax diagnostics, and recovery information.
Its storage is immutable after publication and independent of its caller's allocation context.

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

Separate stages are valuable, but Jai cannot be modelled as one irreversible sequence of whole-program passes.
`#if`, type queries, polymorphism, `#run`, `#insert`, generated declarations, and imports can create new work or require information from another stage.

The [typechecking guide](../../how_to/090_how_typechecking_works.jai) explains bottom-up expression inference grounded by declarations.
It is not a specification of the official compiler's complete internal scheduling order.
This design intentionally does not claim that compiler uses the exact stages below or that type resolution always precedes sizing.

Proposed conceptual flow:

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
A scheduler records edges, shares identical in-flight work, handles cancellation, and detects cycles.

Use explicit result states: ready/complete, ready-with-diagnostics, incomplete/unknown, unsupported, blocked-on-dependency, cancelled, and failed.
A deterministic error can be cached with valid dependencies.
A cancelled or compiler-unavailable computation must not become a persistent claim that a declaration is semantically invalid.

Cycles need domain-specific handling.
Mutually referring declarations can be indexed together; recursive pointers can refer to an incomplete type identity; an infinitely recursive by-value layout must produce a semantic error.
A generic recursion guard that labels every cycle unsupported would prevent full coverage.
Query readiness, interface fingerprints, and strongly connected groups should allow legitimate recursion without inventing an unbounded global fixed-point solver.

## 6. Cache Boundaries

### 6.1 Modules: Strong Context and Lifetime Boundaries

Cache the configured module's file membership, declaration/export index, and query results.
Standard libraries, vendored modules, and unchanged project modules all use the same correctness rules; edit frequency may affect residency and scheduling, not validity.

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

| Change | Reusable work | Work requiring validation/recomputation |
| --- | --- | --- |
| Whitespace before an ordinary declaration | Many semantic values and unchanged file snapshots | Changed-file syntax/source map and location-sensitive results |
| Local procedure implementation | Other file syntax and possibly the signature | Body analysis; inline/compile-time/reflection consumers of that body |
| Add a module-level name or overload | Unchanged syntax across files | Scope/candidate-set lookups, including previous misses |
| Change a constant used by a field dimension | Struct syntax | Constant-dependent field types/layout and their consumers |
| Change a loaded file's scope directive | Its unaffected token payloads where supported | Module composition, visibility, bindings, and affected declarations |
| Change module/program parameters | Context-independent syntax | Affected configured instances, conditions, evaluation, and semantic queries |
| Change target architecture | Syntax and target-independent indices | Primitive/layout/ABI-dependent results and evaluated target conditions |
| Change a compiler or cache schema version | Compatible source blobs where defined | Affected persisted artifacts and evaluator outputs |

Keep incomplete-world results explicitly provisional.
Discovering new imports or generated declarations can change name lookup; do not publish a partial export set as a complete stable interface.

## 8. Allocation and Lifetime Model

Use owned roots and stable handles instead of an implicit caller allocator lifetime:

| Owner | Storage and responsibility |
| --- | --- |
| Source/syntax revision | Owns source, token payloads, nodes, syntax diagnostics, and local immutable indices, or leases their backing mapped artifact. |
| Semantic world | Owns the revision/configuration selection and roots the module graph for a coherent editor view. |
| Semantic artifact/group | Owns its result arrays, values, diagnostics, and dependency handles; retains syntax/world inputs needed to interpret them. |
| Query task | Owns scratch/inference storage, cancellation state, and uncommitted output.  Published results cannot point into its scratch arena. |
| Cache store | Owns resident artifact records, persistence bookkeeping, and eviction decisions; it does not override live client leases. |
| Editor request | Holds a lease to its world and requested results until completion or explicit release. |

Arena allocation still fits this model.
The change is who owns each arena and when it becomes immutable/releasable, not a requirement to allocate every node separately.
Keep addresses stable while live handles or allocator data refer to an arena.

Do not require every query result to retain an entire project world indefinitely.
Use appropriately scoped retained artifact groups/handles and explicit world roots; measure whether a tiny result pins an unexpectedly large graph.
Query dependency cycles require graph/group ownership or reachability-based reclamation, not mutually retaining reference-counted objects.

Unchanged syntax can be shared across worlds.
Changed files create new revisions.
Old revisions remain valid while any request uses them, then become reclaimable.
A configurable memory budget and emergency pressure policy are necessary even if normal behaviour favours keeping everything resident.
Eviction must never invalidate a leased snapshot, and retention should not grow without bound during long editing sessions.

### Persistent Representation

Persist explicit records with IDs, offsets, bounded arrays, versioned node/query kinds, and source maps.
Never dump the current pointer graph, `Allocator`, `Pool`, compiler overlays, or process-local `Type_Info` objects directly to disk.

A versioned decoder can rehydrate records into owned arenas, or selected immutable artifacts can be memory-mapped through an offset-based representation.
Memory mapping is optional: 'disk-backed memory cache' means a durable backing store with resident reusable data, not a mandate to expose mapped bytes as existing Jai structs.
Start with a simple safe format; measure deserialisation against reparsing.

Cached semantic edges must refer to persisted artifact/declaration identities and validated dependency manifests, not raw pointers that happened to be valid when the editor exited.
Cross-version or missing dependencies cause a miss, not a best-effort pointer repair.

## 9. Persistence and Editor Operation

Proposed setup capabilities, not final option names:

- Persistence enabled by default; explicitly disabling it retains the same in-memory semantics.
- Saved and unsaved revisions persist, with separate current-disk/active-overlay metadata, private storage, and explicit recovery/discard/cleanup behaviour.
- Optional cache-directory override, with a documented per-user default outside source repositories.  The concrete platform default needs a later API decision.
- Configurable memory/disk budgets and retention policy, preferring resident validated data under ordinary conditions.
- Clear/invalidate operations, format/version inspection, cache-hit/miss reasons, and a way to recover from a damaged store.
- Independent workspace-trust and external-evaluation policy.  Enabling persistence is not permission to execute source code.

On restart, load a lightweight manifest, validate relevant revisions/configuration, and lazily rehydrate results needed for visible files or queries.
Do not eagerly deserialise the entire historical graph just because its files exist.
Matching hashes can avoid reparsing, but only if reading/decoding the cached artifact is itself worthwhile.

Write artifacts transactionally with atomic publication, checksums, size limits, and interruption-safe manifests.
Multiple editor processes need a defined shared-store locking/publication policy; immutable content-addressed blobs with controlled manifest updates are preferable to concurrent mutation of one live arena image.

Treat persisted data as untrusted input: validate bounds, schema and dependency IDs, reject corrupt/truncated entries, and reparse/recompute on failure.
Use suitable user-private filesystem permissions and avoid writing secrets or sensitive evaluated values into broadly shared caches.
Generated source and unsaved buffers can contain private code.
Persistence must disclose that scope, provide deletion/retention controls, and remove obsolete recovery references when the host reports discard/reset; historical unreferenced blobs then follow the garbage-collection policy.
Discard is not a promise of secure erasure from storage or backups.

Disk garbage collection removes unreachable or over-budget historical artifacts, not live leased data.
Per-artifact demand loading can remain lazy while eviction remains rare; those are compatible goals.
A read-only or unwritable cache directory must degrade to correct in-memory operation rather than prevent editor features from working.

## 10. Compile-Time Execution and the Official Compiler

Provide an evaluator boundary whose input is a semantic/evaluation request, resolved context, dependency closure, target/host settings, and source provenance.
Its output is structured values or generated syntax, diagnostics, provenance/source maps, observed dependencies, and an explicit support/completeness state.

Initially the evaluator may be unavailable.
Later a subprocess backend can wrap supported snippets and use the official compiler; eventually a bootstrapped language-service backend may interpret the corresponding AST.
Keep frontend query/ownership contracts independent of that choice.

Snippet extraction is not generically semantics-preserving.
Evaluation may depend on module state, imports, private names, parameters, `#caller_code`, source paths/locations, compiler hooks, or earlier compile-time mutations.
A backend must reproduce the required context, evaluate a larger unit, or return unsupported; do not silently run an isolated expression in a different environment and call it equivalent.

Separate computed values from action execution.
A `#run` may mutate compile-time state, read files, use environment variables, launch processes, or produce outputs.
Reusing its old return value does not reproduce those effects.
Cache/replay only explicitly supported deterministic evaluations or an action model with sufficient input/output/effect tracking.
Otherwise, re-execute under an authorised policy or retain an unknown/provisional result.

In particular, treat `using,map` callbacks with mutable name arrays as ordered computations over explicit inputs, and treat generated declarations as new syntax with provenance.
Both can alter dependencies and name lookup.
Unknown external reads or effects make a result non-persistable, not permanently valid because the Jai snippet's hash matches.

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
Query cancellation must leave persistent entries either complete and valid or absent.  Parallel queries cannot write binding/type fields into a shared syntax snapshot.

## 12. Trade-Offs and Alternatives

| Strategy | Strength | Cost / limitation | Position in this proposal |
| --- | --- | --- | --- |
| Full reparse of changed file | Simple, measured fast, robust after grammar-boundary edits | Repeats syntax construction for that file | Default baseline |
| Existing token reuse | Can reduce lexing while retaining independent results | Still materialises a full token snapshot | Preserve as a separately measured option |
| Existing AST copier | Existing eligible-shape/lifetime coverage | Copies and relocates; no demonstrated retained-byte or median advantage locally | No decision made here; not a prerequisite for caching |
| Whole-file snapshot cache | Avoids all syntax work for unchanged files | Requires owned immutable lifetime and validation | Primary syntax reuse boundary |
| Module/query semantic cache | Reuses expensive meaning across files and sessions | Needs context identities, dependencies, persistence, and invalidation | Primary semantic direction |
| Immutable syntax chunks | Can share unchanged declaration storage and fingerprinting | Boundary, identity, source-map, and ownership complexity | Optional optimisation after measurement |
| Persist source only and reparse | Very simple format; source retrieval can be cheap | Does not satisfy avoiding repeated syntax parsing by itself | Fallback, not the complete restart cache |

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
- Independent surviving worlds after old-world release, eviction, restart, and cancellation.
- Correct incomplete/unsupported states without converting unknowns into errors or stale successful results.
- Corruption recovery, bounded deserialisation, multi-process publication, and safe handling of untrusted evaluation.

Measure cold start, validated warm restart, unchanged-project queries, a local body edit, interface/layout changes, dependency changes, malformed typing, and repeated refactoring/navigation.
Report median/tail editor latency, hashing/validation/deserialisation costs, memory high-water/residency, disk size, bytes read/written, invalidation fan-out, and retained old worlds.
Keep external compiler startup/evaluation costs visible rather than hiding them inside a generic cache metric.

There is not yet an agreed numerical acceptance threshold.
Whole-project warm restart and edit-to-editor-result measurements are needed before setting one.
Earlier hypothetical large-file savings for a broader copier are not evidence for this architecture's performance, and syntax persistence should earn its complexity relative to simply reparsing the selected files.

## 14. Decisions Still Open

These should be resolved as the model is refined, not silently encoded as implementation defaults:

- Retention/cleanup defaults and the host recovery handshake for persisted unsaved revisions; persistence itself is agreed, not still an open choice.
- The default cache directory, budget defaults, shared versus workspace-local manifests, and multi-process sharing policy.
- Exact path/symlink identity and source-visible filename rules across Windows and other supported platforms.
- How much parameter canonicalisation and compiler-backed evaluation is available before full semantics exists.
- The explicit evaluation opt-in parameter and host-authorisation contract, including how an embedding editor supplies its external workspace-trust decision.
- The representation and matching policy for declaration identity across edits, moves, and restarts; uncertainty must remain a valid cache miss.
- Whether a syntax chunk store is worth maintaining after whole-file/query caching is measured.
- Numerical acceptance criteria for warm restart, steady editor edits, memory retention, and persistent-storage overhead.

## 15. High-Level TODO

These are design/capability goals derived from this report, not an ordered migration plan.
No production changes are authorised by this checklist alone.

- [ ] Agree the remaining identity, persistence/privacy, workspace-trust, residency-budget, and performance policies in section 14.
- [ ] Define owned immutable syntax snapshots and syntax diagnostics that do not depend on semantic mutation or caller allocator lifetime.
- [ ] Define coherent semantic worlds, declaration/type identities, versioned handles, and query-result states through full Jai coverage.
- [ ] Define module-instance composition and canonical parameter/context keys, including entrypoint program parameters and loaded-file membership/visibility.
- [ ] Define dependency recording and invalidation for successful/failed lookup, overload sets, constants, conditions, layout, generics, generated declarations, and cycles.
- [ ] Define explicit ownership and reclamation for source/syntax, semantic artifacts, dependency groups, request leases, task scratch storage, and superseded worlds.
- [ ] Specify a safe versioned persistent format and store: validation, pointer-free records, manifests, crash recovery, concurrent writers, lazy rehydration, and garbage collection.
- [ ] Define independent cache-backed source/syntax and semantic-query capabilities, retaining full changed-file parsing as the initial baseline.
- [ ] Define an optional evaluator contract with context reproduction, provenance, dependency/effect tracking, unsupported states, trust controls, and bounded subprocess execution.
- [ ] Define cache-equivalence, invalidation, lifetime, restart, cancellation, corruption, and incomplete-code test matrices.
- [ ] Benchmark the complete editor workflows in section 13 and agree acceptance thresholds before choosing chunk-level syntax reuse or finer cache granularity.
- [ ] Revisit the existing AST-copier decision independently of the future architecture, using its measured benefit and preserved correctness contracts.
- [ ] After the target model is agreed, write a separate migration/implementation plan from the current parser; do not treat this report as that plan.
