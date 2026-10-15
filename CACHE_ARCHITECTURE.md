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
| `DocumentID` | A resolved source-document identity, including its absolute path and filesystem identity policy. |
| `SourceRevision` | Exact source bytes plus their content digest.  An unsaved editor buffer is a revision even if disk contents differ. |
| `SyntaxKey` | Document identity, source digest, syntax configuration, and parser/schema version. |
| `ModuleInstanceID` | Resolved module entrypoint identity plus canonical module-parameter values and entrypoint program-parameter values. |
| `SemanticContextID` | Module instance, target/type environment, resolution configuration, evaluator policy/version, and relevant language configuration. |
| `DeclarationID` | A declaration within its owning module instance and revision mapping; not just its name or syntax hash. |
| `TypeID` | Nominal semantic identity rooted in the defining declaration, with canonical instantiation arguments where applicable. |
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

As for cycle detection, if we reach a point where there are things waiting in pipelines, but we don't make forward progress, then we should stop with an error and do work to identify and report on the cycle, including suggestions for breaking it (e.g. use a pointer rather than an instance directly etc.).

## 6. Cache Boundaries

### 6.1 Modules: Strong Context and Lifetime Boundaries

Cache the configured module's file membership, full declaration index across all visibilities, derived export/lookup views, and query results.
Standard libraries, vendored modules, and unchanged project modules all use the same correctness rules; edit frequency may affect residency and scheduling, not validity.

Cache retention is distinct from language visibility.
Retain each declaration's visibility, defining module/file, source location, and scope provenance; do not discard non-exported declarations when constructing a module artifact.
This does not require eagerly completing semantic analysis of every retained declaration.

For a top-level bare `#import "Basic";`, exported members become directly visible in the global scope.
For `Basic :: #import "Basic";`, members are accessed through `Basic.` rather than injected as bare names.
The reported Jai behaviour also allows qualified access to non-public members; whether that includes `#scope_file` declarations as well as `#scope_module` declarations still needs compiler verification.
Do not encode the unverified distinction as an export-only cache boundary.

Also verify nested-scope imports against the compiler: the working hypothesis is that a bare import still contributes exported names to the global namespace, whereas a named import introduces only a locally scoped namespace binding.
Check access from the importing scope, outside it, and from sibling scopes for both forms; do not assume the import's lexical location is necessarily the scope receiving its members.
Keep this distinction unconfirmed until tested, and use the verified rules when recording lookup dependencies and invalidating cached results.

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

Allocation strategy is separate from logical ownership: a revision/artifact can own records allocated from a longer-lived cache service's pools without owning those pools outright.
Keep allocator state and live object addresses stable while handles or allocator data refer to them.

Consider typed pools/slabs, one per record type or suitable size class, alongside arenas.
For independently reclaimable nodes, semantic results, dependency records, and cache control records, individual frees and freelist reuse can reduce allocation churn and support partial eviction without discarding unrelated records.
Select or verify an allocator that actually supports individual frees; the name `Pool` alone does not establish its reclamation behaviour.
Variable-sized arrays, strings, and other owned payloads still need an explicit allocation and release strategy.

A hybrid is appropriate: typed pools for independently lived fixed-size records, arenas for scratch work and immutable groups normally released together, and separately owned variable-sized payloads where necessary.
Pool allocation does not itself prove that an object is safe to free: dependency ownership and request leases still govern reclamation, including records reachable from surviving snapshots.
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

## 9. Persistence and Editor Operation

Proposed setup capabilities, not final option names:

- Persistence enabled by default; explicitly disabling it retains the same in-memory semantics.
- Saved and unsaved revisions persist, with separate current-disk/active-overlay metadata, private storage, and explicit recovery/discard/cleanup behaviour.
- Optional cache-directory override, with a documented per-user default outside source repositories.  The concrete platform default needs a later API decision.
- Configurable memory/disk budgets (with unlimited (= all available space) as an option for disk) and retention policy, preferring resident validated data under ordinary conditions.
- Clear/invalidate operations, format/version inspection, cache-hit/miss reasons, and a way to recover from a damaged/outdated store, probably via reparse rather than a migration or similar.
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

Disk garbage collection removes unreachable or over-budget historical artifacts, not live leased data; can be triggered manually as well as being run automatically.
Per-artifact demand loading can remain lazy while eviction remains rare; those are compatible goals.
A read-only or unwritable cache directory must degrade to correct in-memory operation rather than prevent editor features from working - we need a mechanism to report systematic errors/warnings of this nature for something to surface them to the user.

## 10. Compile-Time Execution and the Official Compiler

Provide an evaluator boundary whose input is a semantic/evaluation request, resolved context, dependency closure, target/host settings, and source provenance.
Its output is structured values or generated syntax, diagnostics, provenance/source maps, observed dependencies, and an explicit support/completeness state.

Initially the evaluator may be unavailable.
Later a subprocess backend can wrap supported snippets and use the official compiler (on generated source with build options including do_output=false and an `#insert` in it, then reading back the `.build/.added_strings_w#.jai` file(s)); eventually a bootstrapped language-service backend may interpret the corresponding AST.
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
Cancelling one waiter must not discard shared work still needed by other requests.

### Later Editor-Feature APIs

Build completion suggestions from a context/starting position or prefix, identifier-definition lookup, and later navigation/refactoring operations on top of the world update/query APIs.
These convenience APIs should share the same revision, pending-result, cancellation, and lifetime contracts rather than inventing separate update mechanisms.
They are a higher and later API layer, not prerequisites for defining the lower-level world model.

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
- Compiler-verified bare/qualified import behaviour across `#scope_export`, `#scope_module`, and `#scope_file`, including nested-scope bare versus named imports, visibility edits, cached misses, and inaccessible-candidate hints that do not create false bindings.
- Independent surviving worlds after old-world release, eviction, restart, and cancellation.
- Correct update-ticket and pending-query completion, revision selection, superseded-update reporting, and independent cancellation of waiters sharing work.
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
- Verify whether qualified module access includes `#scope_file` declarations as well as `#scope_module` declarations; preserve both in the cache regardless of the result.
- Whether a syntax chunk store is worth maintaining after whole-file/query caching is measured.
- Numerical acceptance criteria for warm restart, steady editor edits, memory retention, and persistent-storage overhead.

## 15. High-Level TODO

These are design/capability goals derived from this report, not an ordered migration plan.
No production changes are authorised by this checklist alone.

- [ ] Agree the remaining identity, persistence/privacy, workspace-trust, residency-budget, and performance policies in section 14.
- [ ] Define owned immutable syntax snapshots and syntax diagnostics that do not depend on semantic mutation or caller allocator lifetime.
- [ ] Define coherent semantic worlds, declaration/type identities, versioned handles, and query-result states through full Jai coverage.
- [ ] Define module-instance composition and canonical parameter/context keys, including entrypoint program parameters, loaded-file membership, all-visibility declaration retention, and access-context lookup views.
- [ ] Define dependency recording and invalidation for successful/failed lookup, overload sets, constants, conditions, layout, generics, generated declarations, and cycles.
- [ ] Define explicit ownership and reclamation for source/syntax, semantic artifacts, dependency groups, request leases, task scratch storage, and superseded worlds.
- [ ] Specify a safe versioned persistent format and store: validation, pointer-free records, manifests, crash recovery, concurrent writers, lazy rehydration, and garbage collection.
- [ ] Define independent cache-backed source/syntax and semantic-query capabilities, retaining full changed-file parsing as the initial baseline.
- [ ] Define change-notification/update tickets and immediate-result-or-pending world queries, including completion milestones, waiting, supersession, cancellation, and a separate later editor-feature API layer.
- [ ] Define an optional evaluator contract with context reproduction, provenance, dependency/effect tracking, unsupported states, trust controls, and bounded subprocess execution.
- [ ] Define cache-equivalence, invalidation, lifetime, restart, cancellation, corruption, and incomplete-code test matrices, including compiler verification of import/visibility rules.
- [ ] Define inaccessible-candidate diagnostics and explicit export fix actions, separate from ordinary identifier resolution and validated against current source and export impact.
- [ ] Benchmark the complete editor workflows in section 13 and agree acceptance thresholds before choosing chunk-level syntax reuse or finer cache granularity.
- [ ] Revisit the existing AST-copier decision independently of the future architecture, using its measured benefit and preserved correctness contracts.
- [ ] After the target model is agreed, write a separate migration/implementation plan from the current parser; do not treat this report as that plan.
