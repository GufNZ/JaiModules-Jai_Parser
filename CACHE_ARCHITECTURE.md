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
| `ModuleInstanceID` | Resolved module source plus compiler-compatible import-request identity, ordered explicitly supplied typed module arguments, and that module's effective program settings.  E2 shows that canonical filepath plus effective values alone is insufficient. |
| `SemanticContextID` | Module instance, target/type environment, resolution configuration, evaluator policy/version, and relevant language configuration. |
| `DeclarationID` | A declaration within its owning module instance, load occurrence where applicable, and revision mapping; not just its name, physical filepath, or syntax hash. |
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
E4 below verifies that source-visible paths can retain dot/parent segments, directory casing, and link aliases; separator handling also differs between the tested load and file-import paths.
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
E1 verifies qualified access to `#scope_module` members, but not `#scope_file` members, on the tested compiler/configuration (see section 14).
Do not encode an export-only cache boundary: module-visible declarations are valid qualified lookup candidates, and file-visible declarations remain relevant to internal analysis and tooling diagnostics.

E1 also verifies that bare imports in procedures, nested blocks, and structs expose exported names in the importing program's global scope, including to another loaded file.
The reverse direction is verified too: a bare import originating in a loaded file exposes exported names to the file doing the loading, at all four tested import scopes.
Named imports do not inject unqualified names, and their namespace binding does not escape its lexical scope as a bare name.
Top-level named bindings are accessible from other procedures and loaded files; bindings nested in procedures/blocks/structs are not directly visible there.
With normal loaded-file scope, a top-level named binding in a loaded file is likewise accessible to its loading file, but a nested named binding is not directly accessible there.
Use these observed distinctions when recording lookup dependencies and invalidating cached results; E1's result scope and remaining limitations are recorded below.

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

Proposed storage layout: under the configured cache directory, keep a directory per canonical source-file/context identity, with separate filenames/artifacts for declarations belonging to that source file.
A module instantiated with different parameters must have a distinct directory identity; include other required program/semantic context discriminators rather than keying semantic storage by filepath alone.
E2 additionally requires preserving compiler-observed import-request distinctions when mapping semantic instances to directories; physical-source deduplication must not merge their nominal declarations.
Use safe encoded names or identity digests with a readable manifest mapping back to paths/parameters, not unescaped absolute paths as directory names.
Preserve artifact revisions within that layout so a new write does not overwrite data still selected by an older world.
Evaluate whether declaration files cover only top-level declarations, independently addressable nested declarations, or declarations externally reachable through supported lookup rules; externally reachable must not be equated with exported only.
Regardless of payload granularity, retain discoverability for all visibilities, ownership of non-split nested content, and complete reloadable dependencies.
This is a layout proposal to test against E10/E11, including small-file overhead and partial loading/eviction; it does not prevent sharing context-independent syntax backing across instance directories.

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
- Whether a syntax chunk store is worth maintaining after whole-file/query caching is measured.
- Numerical acceptance criteria for warm restart, steady editor edits, memory retention, and persistent-storage overhead.

### What a Completed Specification Must Define

The direction is established, but a completed specification must turn the following into explicit contracts, state transitions, and acceptance tests.
Full future semantic coverage does not mean implementing or fully specifying every Jai rule before the first migration; define the architectural contracts, a supported initial slice, and an extension/unsupported-state contract.

| Area | Definition needed before migration planning |
| --- | --- |
| Scope and coverage | Initial supported platforms/compiler versions, syntax and semantic operations, malformed-code behaviour, explicit exclusions, and the route to full coverage.  Separate initial requirements from later capabilities. |
| Identity | Document/path/alias rules, module and program parameter canonicalisation, declaration/type identity, edit matching, target context, and persisted versus session-local IDs.  Specify conservative misses for uncertain matches. |
| Source and worlds | Source-provider interface, edit coordinate units/base revision, disk/overlay precedence, save/reset/rename/delete/recovery events, world capture/publication, and how newly discovered files enter a coherent world. |
| Syntax and semantic records | Owned record schemas, syntax/semantic boundary, spans/source maps, diagnostics, derived indices, versioned references, and compatibility policy for existing compiler-shaped nodes. |
| Module composition | Verified bare/named import and loaded-file scope rules, visibility, duplicate/cyclic imports, parameter propagation, and all-visibility indices versus access-filtered lookup. |
| Declaration pipeline | Initial stage/query catalogue, prerequisites and readiness milestones by declaration kind, generated-work discovery, provisional results, legal recursion, and failure/unsupported states. |
| Dependency validity | What each query observes, negative lookup/candidate-set dependencies, parent/dependency revision semantics, dirty propagation, fingerprint equality, and validation after restart. |
| Handles and ownership | Handle/state layout, per-link versus shared-target metadata, allocation generations, leases, pool/arena ownership, cycle reclamation, eviction transitions, and safe rehydration. |
| Scheduling and API | Change/update tickets, immediate-result-or-pending queries, completion milestones, supersession, cancellation, wait/notification delivery, threading/reentrancy, priorities, and shutdown. |
| Persistence | Initial text schema using `Text_File_Handler`, keys/manifests, validation/version rejection, publication/locking, corrupt-store recovery, unsaved metadata, GC, budgets, and cache/system diagnostics.  Binary encoding is not an initial requirement. |
| Evaluation boundary | Disabled/unsupported behaviour initially, opt-in parameter and host permission, request/result/provenance contract, tracked inputs/effects, and limits of compiler snippet equivalence.  Implementation may remain deferred. |
| Acceptance | Cached-versus-fresh oracles, supported-language cases, race/lifetime/restart/failure tests, representative workloads, and agreed latency/memory/disk targets. |

Some choices require product decisions rather than measurement: initial coverage, host integration style, cache defaults/budgets, recovery retention, and which performance trade-offs are acceptable.
Experiments should inform these choices, not quietly choose them.

### Experiments to Run First

Use small isolated fixtures/prototypes, not a parallel implementation of the new parser.
Record the hypothesis, exact compiler/build configuration, commands, observed output, limitations, and resulting decision for each experiment.
Language probes use the official compiler as the oracle, including separate expected-failure cases; prototype cache tests compare against fresh computation.
These are proposed manual probes on authored trusted fixtures; listing them does not authorise their execution or automatic evaluation of arbitrary workspace code.
E1-E4 have been completed as recorded below; E5-E12 remain proposed and have not yet been run.

| ID | Experiment and discriminating check | Decision it informs |
| --- | --- | --- |
| E1 | Completed: import/visibility matrix using bare and named imports at file, procedure, nested-block, and struct scopes; export/module/file visibility; access inside, outside, from siblings, and from another loaded file.  Each access compiled separately. | Verified scope receiving imported names, lexical namespace binding, and qualified module/file visibility; see results below. |
| E2 | Completed: repeated/aliased imports, omitted/explicit defaults, argument order/types/values, nominal assignment compatibility, two-hop imports, and program-setting constraints; 32 isolated probes and evaluation-count audit. | Canonical source plus effective parameter values is insufficient for compatible nominal identity; program configuration is per module and main-program controlled.  See results below. |
| E3 | Completed: 28 isolated loaded-file composition probes for repeated/diamond/aliased loads, order, relative paths, file scopes, module instances, collisions, missing files, and cycles; diagnostic and execution-marker audit. | Preserve load occurrences rather than deduplicating membership; share syntax without sharing contextual bindings or nominal declarations. See results below. |
| E4 | Completed: 35 isolated path/source-context probes covering casing, dot/parent/separator/absolute aliases, copied and relocated bytes, relative loads/imports, working-directory changes, junctions, and native directory/file symlinks; exact location/path, nominal identity, diagnostic, and execution-marker audit. | Keep physical document identity, source-visible path context, and compiler-compatible module identity distinct; request validation can differ even when the filesystem reaches the same source. See results below. |
| E5 | Compiler-evaluation feasibility: on authored trusted fixtures, try `do_output=false` plus `#insert` and inspect `.build/.added_strings_w#.jai` production, multiplicity, freshness, extraction boundaries, diagnostics, and failures.  Include one `using,map` callback and a context-dependent case.  Measure startup cost separately. | Whether the proposed output channel works, its limitations, and whether evaluator support can remain deferred.  This is not evidence that arbitrary snippets are equivalent or safe. |
| E6 | Syntax independence probe: construct a small owned syntax-only representation covering declarations, spans, recovery, and decoded payloads; attach two different semantic contexts and release the original input/builder storage.  Verify neither binding nor release mutates the other's view. | The minimum syntax/semantic split, ownership contract, and whether current node overlays can be adapted or should be replaced.  Do not implement a second full AST. |
| E7 | Dependency/revision model: a tiny query graph with a parent-only edit, dependency-only edit, unchanged interface/body change, new overload, previous missing name, transitive constant/layout change, and simultaneous old/new worlds.  Compare every result to fresh evaluation and assert expected reuse. | Exact dual-stamp validation, negative dependencies, world selection, and safe conservative module invalidation. |
| E8 | Pipeline/scheduler model: advance declarations through signature/body/layout milestones, include valid pointer recursion and invalid by-value recursion, and simulate a slow external task, cancellation, shared waiters, and a genuinely cyclic wait. | Stage readiness, pending API semantics, cycle diagnostics, and shutdown.  No forward progress alone is not proof of a cycle while work can still complete externally. |
| E9 | Allocation/eviction benchmark: verify the actual candidate Jai pool APIs, then compare arenas, typed pools, and a hybrid under repeated edits, sparse eviction, retained old snapshots, and slot reuse.  Track allocation generations, payload cleanup, freelist reuse, backing bytes, and fragmentation. | Initial allocation units, ownership/lease mechanism, and whether partial frees deliver useful memory or churn reductions. |
| E10 | Text artifact round trip: use `Text_File_Handler` on representative node/query records, IDs, exact strings/numbers, diagnostics, and dependencies.  Decode into fresh storage after producer teardown; compare with originals.  Include Unicode, malformed/truncated records, schema mismatch, and bounds limits. | Concrete initial schema, exact-value fidelity, validation strategy, and text decoding cost relative to parsing. |
| E11 | Store/restart/overlay prototype: publish small immutable artifacts and manifests; interrupt writes, run competing publishers, corrupt an entry, make the store unwritable, and exercise unsaved restore/save/reset, external file changes, deletion, and GC.  Hash actual source rather than trusting timestamps. | Atomic publication/shared-store policy, recovery handshake, fail-open in-memory operation, system diagnostics, and durable metadata requirements. |
| E12 | Representative project baseline: measure fresh parse, unchanged-file reuse, and text reload with validation across many small files and large active files, transitive imports, malformed edits, body/interface changes, and repeated updates.  Include hashing/I/O, tail latency, retained worlds, and disk size; distinguish process restart from OS-cold filesystem cache. | Workload selection, numerical acceptance targets, initial cache granularity, and whether syntax persistence earns its overhead.  Reuse existing benchmark/oracle infrastructure where applicable. |

#### E1 Results: Import Scope and Visibility

Completed 2026-10-16 on Windows with Jai beta 0.2.030, built 2 July 2026, using the fast x64 backend.
Reproducible runner: [experiment_import_visibility.jai](examples/experiment_import_visibility.jai).
From the parser's examples directory:

```bash
jai experiment_import_visibility.jai -x64 -quiet -no_color
```

The runner executes at compile time and sets `do_output=false` and `write_added_strings=false` for itself and generated probes; it does not link/run target executables or require `+Autorun`.
Each child invocation uses `jai -x64 probe.jai -quiet -no_color -import_dir ..` in its own case directory, resolving an ordinary `#import "Visibility_Probe";` or `Probe :: #import "Visibility_Probe";`.
The synthetic module declares distinct export/module/file markers in both its entrypoint and a loaded file.
Accepted accesses assert exact marker values; procedure/block checks are forced through stallable compile-time calls.
There are 8 import-placement controls and 288 lookup probes: 296 assertions passed, with 80 compilations accepted and 216 rejected.
A separate audit of every rejected probe's log found exactly one expected diagnostic: 202 undeclared identifiers and 14 missing members, with no masked parse/scheduling errors.
This includes 48 reverse-load probes: imports originate in a loaded file, and the corresponding marker assertions are in the loading file.

| Observed case | Result |
| --- | --- |
| Bare import at file/procedure/block/struct scope | Exported markers accessible inside and at all tested outside sites, including another loaded file; module/file-visible markers not accessible as bare names. |
| Named import, binding in scope | Qualified export/module-visible markers accessible; file-visible markers rejected.  Same result for markers from the imported module's entrypoint and its loaded file. |
| Named import, unqualified member access | Rejected even inside the importing scope; no bare-name injection. |
| Named import at top level | Namespace binding accessible in another procedure and another loaded file. |
| Import originating in a loaded file | Bare-import exports accessible to its loading file, even when the import is nested; a named binding is accessible there only when top-level, with qualified export/module access but not file-visible access. |
| Named import in procedure/block/struct | Namespace binding not directly accessible by its bare name outside that lexical scope; block-after/block-sibling and struct-sibling probes also reject it. |

Generated sources, individual `compile.log` files, and `summary.tsv` are retained under `examples/.build/import_visibility/` and can be regenerated; normal build cleanup may remove them.
The runner asserts the observed outcomes on rerun; a compiler behaviour change should fail the relevant assertion rather than silently replace the recorded rule.
An initial fixture used non-stallable compile-time calls, which masked some negative checks with scheduling diagnostics; the final results use stallable calls and have been fully re-audited.

These results are scoped to this compiler/version, backend, ordinary module-name imports, and the tested unconditional contexts.
E1's reverse-load probes use normal loaded-file scope; E3 below additionally tests an explicit `#scope_file` directive on the loaded file containing a named or bare import.
They do not establish behaviour for every directive/import modifier, transitive re-export, overload collision, disabled conditional branch, or other backend/platform.
For a struct-local named import, rejection of a bare `Probe` outside the struct does not establish whether an explicitly aggregate-qualified path such as `Container.Probe` is usable; that was not tested.
Module identity/parameter results are recorded in E2 below; loaded-file order/inclusion/cycle results are recorded in E3.
Architectural consequence: distinguish lexical binding from the scope receiving bare-import exports, and retain module/file-visible records while applying context-specific access filters.

#### E2 Results: Module Identity and Program Configuration

Completed 2026-10-16 on Windows with Jai beta 0.2.030, built 2 July 2026, using the fast x64 backend.
Reproducible runner: [experiment_module_identity.jai](examples/experiment_module_identity.jai).
From the parser's examples directory:

```bash
jai experiment_module_identity.jai -x64 -quiet -no_color
```

The runner and all generated entrypoints disable executable output and added-string output.
Child compilations use `jai -x64 probe.jai -quiet -no_color -import_dir ..` in isolated named case directories.
The authored module has integer/string/bool module parameters, integer/bool program parameters, an otherwise identical nominal struct, exported effective values, and a compile-time `E2_INSTANCE` print marker.
Bridge and grandparent modules create a two-hop import chain; another bridge deliberately attempts a forbidden program-setting override.
Type equalities/inequalities, positive assignment compatibility, parameter values, and graph observations are asserted in accepted fixtures.

All 32 expected outcomes passed: 27 accepted compilations and five expected rejections.
The complete log audit matched all 40 expected module-instance evaluation markers in accepted compilations; each shared nominal instance printed once and each tested distinct pair printed twice.
Rejected compilations were not used to infer evaluation counts because compilation may stop before their `#run` directives execute.
The five rejections were two incompatible-struct assignments, one program-setting override from an imported module, and two duplicate program-setting sites (equal and unequal values).
Each negative log contained exactly its expected compiler error class; no parse/setup failure was counted as an identity result.

| Probe family | Observed result |
| --- | --- |
| Repeated same import | Same nominal type and one evaluation, including repeated imports within a procedure or another loaded file. |
| Omitted versus empty module argument list | Same instance. |
| Omitted versus explicit default arguments | Distinct instances even though the tested effective values and integer value type match.  Assignment between omitted/default-explicit struct types is rejected. |
| Repeated same explicit argument list | Same instance, for both partial and full lists. |
| Partial versus full default list; reordered named arguments | Distinct instances despite equal effective parameter values. |
| Integer `3` versus `1+2`, in otherwise identical explicit lists | Same instance: raw expression spelling alone is not the identity. |
| Integer `3` versus `(3).(s32)`; changed integer/string/bool values | Distinct instances.  Preserve typed supplied arguments, not just printed values. |
| Repeated identical file/dir imports | Same instance within each tested import form. |
| Module-name versus file/dir import; file spelling with redundant `../` traversal | Distinct instances of the same physical source.  Do not unify nominal types through physical-path normalisation alone. |
| Byte-identical source in another module directory | Distinct instance/type. |
| One explicit program-setting site plus ordinary imports | All imports of that module share the configured settings and the same nominal instance for identical module arguments, including when the ordinary import appears first in source.  Explicit program defaults do not create the omitted-versus-explicit split seen with module arguments. |
| Different module-argument instances under one program setting | Distinct nominal types, but both observe the one configured program setting. |
| Two program-setting sites for the same module | Rejected even for identical values. |
| Program-setting site inside an imported module | Rejected: settings may only be supplied from the main program. |

The graph prints fields in this order: grandparent mode, bridge mode, child mode, direct-child-import mode, shared child nominal identity, child trace flag.

```text
Default configuration:                   7  7  7  7 true false
Configure only the grandparent module:  11  7  7  7 true false
Configure the child from the main file:  7  7 19 19 true true
```

Thus, same-named parameters on different modules are independent, while a main-program setting for the child is observed at every import of that child through the two-hop graph.
The probe named `graph_entry_defaults` configures the top imported module, not a `#module_parameters` directive in the entrypoint; an exploratory attempt at the latter was rejected and was corrected before the final run.

Generated sources, `compile.log` files, and `summary.tsv` are retained under `examples/.build/module_identity/` and may be removed by normal build cleanup.
The summary includes expected acceptance, diagnostic substring, and successful evaluation counts; compare those with the corresponding logs when auditing a rerun.
The final fixtures assert the observed nominal/graph results, not the initial hypothesis that equal effective values always imply equal instance identity.
No executable/object outputs were produced in the fixture directory.

These are compiler-observable results, not a claim to know its internal cache algorithm or that all distinctions are intentional language guarantees.
The user confirms that different filesystem traversals reaching the same file are a known compiler deduplication hole, with a fix on the compiler roadmap but probably not soon.
Treat E2's redundant-traversal result as a current compiler limitation to accommodate, not an intended permanent module-identity rule; this roadmap clarification does not establish the status of every other import/argument distinction above.
Coverage is limited to this version/backend/platform, these primitive parameters, unconditional imports, and the explicit alias forms shown; generic/type/procedure-valued arguments, default-expression dependencies, symlinks/casing, and wider resolver configurations remain unproven.
Broader path/source-context results are recorded in E4 below; neither experiment establishes an exact universal path-key algorithm.
Architectural consequence: separate physical-source/syntax reuse from nominal module-instance identity; preserve observed import form/spelling and explicit typed argument-list distinctions, and model program configuration as validated per-module settings established by the main program.
Version the relevant compatibility rules and rerun the alias probes when the compiler fixes traversal deduplication; do not bake the hole into permanent identity semantics.
Until then, merging currently distinct nominal instances requires an explicit compatibility decision rather than being presented as a transparent cache optimisation.

#### E3 Results: Loaded-File Composition

Completed 2026-10-19 on Windows with Jai beta 0.2.030, built 2 July 2026, using the fast x64 backend.
Reproducible runner: [experiment_load_composition.jai](examples/experiment_load_composition.jai).
From the parser's examples directory:

```bash
jai experiment_load_composition.jai -x64 -quiet -no_color
```

The runner and generated entrypoints disable executable and added-string output.
Each child compiles `probe.jai` in an isolated case directory with `-x64 -quiet -no_color` and a 30-second timeout; no target executable is linked/run.
Authored loaded files assert declaration values, file-local binding resolution, and module-dependent values/type identities; selected files print `E3_SHARED` at compile time to expose repeated inclusion.

All 28 expected outcomes passed: 17 accepted compilations and 11 expected rejections.
The log audit verified all 17 expected markers in accepted compilations and all 21 expected diagnostic lines across rejected cases, including repeated diagnostics emitted by this compiler build.
Every negative diagnostic matched its case's expected class/count: 14 redeclaration errors, four undeclared identifiers, two nested-load-limit errors, and one missing-file error.
Failed compilations were not used to infer stable execution counts; the declaration-free positive controls establish repeated execution independently.
No timeout, parser/setup error, or native process failure was accepted as a semantic result.

| Probe family | Observed result |
| --- | --- |
| Repeated identical load; diamond load through two parents | Public declarations are included again and produce redeclaration errors. Declaration-free controls succeed and print twice. |
| Same source through a redundant traversal | Likewise included twice: public declarations collide; the marker-only control prints twice. This does not establish import-style deduplication semantics for `#load`. |
| Same file loaded twice with file-private declarations | Compiles, with each occurrence resolving its own file-private name and printing once; two prints total. |
| Same private name in two different files | Compiles; each exported accessor resolves its own file's value, not its sibling's. |
| File-private names across a load boundary | Hidden from loader, sibling loaded file, and in the reverse direction from a loaded file to a file-private loader declaration. |
| Relative load inside another file | Resolves relative to the containing loaded file. A different same-named file beside the entrypoint was deliberately supplied as a discriminator. |
| Forward reference before `#load`; either order of two interdependent declaration files | All tested pure declaration cases compile with the same values. This does not establish an order for arbitrary compile-time effects. |
| Scope directive in a loaded file | Does not change the loader's subsequent declaration visibility; the loader's `#scope_file` also does not make an otherwise default-visible child's declarations file-private. |
| Named import in a loaded file under `#scope_file` | Its binding is hidden from the loading file. The corresponding `#scope_module` binding is visible there. |
| Bare import in a loaded file under `#scope_file` | Its exported members remain visible to the loading file, unlike the named-binding case. |
| Repeated imports of one module instance containing a load | Same nominal loaded type and one loaded-file execution. |
| Different parameters of one module, or two different modules, loading the same source | Separate nominal loaded types and two executions. Loaded values and private accessors observe their own module's parameters. |
| Distinct files with identical public declarations | Redeclaration errors, not successful deduplication or first/last-wins lookup. |
| Direct self-load and two-file load cycle | Rejected at the compiler's maximum of 100 nested loads; neither is silently deduplicated or accepted as legal recursion. |
| Missing loaded file | Explicit unable-to-open-file diagnostic. |

For hidden file-local names/bindings, compiler diagnostics also identified a matching file-scoped declaration and suggested `#scope_export`, consistent with the proposed tooling-candidate separation.
Generated sources, individual `compile.log` files, and `summary.tsv` remain under `examples/.build/load_composition/` and can be regenerated after cleanup.
The runner asserts every expected acceptance/rejection; the summary records exact marker and diagnostic expectations for auditing the logs.
No executable/object outputs were found in the fixture directory.

These results are limited to this compiler/version/backend/platform and the tested unconditional declaration/load graphs.
Conditional/generated loads, overload merging, dynamic filesystem changes, all path-alias forms, and arbitrary compile-time effect ordering are not established; E4 below adds bounded path-context coverage.
The 100-load limit is an observed compiler diagnostic, not a recommendation for the service's scheduler or a substitute for precise occurrence/cycle diagnostics.
Architectural consequence: cache source/syntax by document revision, but compose semantics using module instance plus load occurrence and file-local scope; do not turn a syntax cache hit into permission to suppress a language-level inclusion.

#### E4 Results: Paths and Source Context

Completed 2026-10-19 on Windows/ReFS with Jai beta 0.2.030, built 2 July 2026, using the fast x64 backend.
Reproducible runner: [experiment_source_context.jai](examples/experiment_source_context.jai).
From the parser's examples directory:

```bash
jai experiment_source_context.jai -x64 -quiet -no_color
```

Hypothesis: byte-identical files and filesystem-equivalent paths need not have interchangeable resolved meaning, source-location values, or nominal module identity.
The runner creates isolated cases with identical module bytes in `Original/module.jai`, `Original/copy.jai`, `Copy/module.jai`, and `Isolated/module.jai`.
The original and relocated directories have different neighbouring loaded/imported values, while the case root deliberately supplies decoy neighbours with value 99.
Authored assertions and compile-time reports expose relative lookup, `#filepath`, `#location(anchor)`, nominal type equality, and `E4_UNIT` execution counts.
The runner and generated entrypoints disable executable/added-string output; children use `-x64 -quiet -no_color` with a 30-second timeout.

All 35 final cases matched their assertions: 27 accepted compilations and eight expected rejections, with no skips after user-assisted symlink setup.
The full audit verified 38 successful execution markers, 15 nominal comparisons, 42 exact source-visible path/location pairs, expected relative-lookup values, and all eight error lines.
Path comparisons were case-sensitive and did not normalise separators or dot segments before comparison.
SHA-256 checks confirmed all four module copies were byte-identical in every case.
Seven rejections report `Non-matching Windows file case`; one reports an unable-to-open-file error for the missing relative neighbour.
No native process failure, timeout, or unrelated error was accepted as a semantic outcome; no executable/object outputs were found.

| Probe family | Observed result |
| --- | --- |
| `#filepath` and `#location(anchor)` | The former returns the containing directory, including its trailing separator; the latter reports a full filename plus line/column. Module anchor locations were line 6, column 11; entrypoint anchors were line 4, column 11. |
| Dot and parent aliases in loads/file imports/directory imports | Accepted; the observed source-visible filename/directory retains `./` or `Branch/../`. Paired imports produce distinct nominal types and two executions. |
| Relative versus absolute file import | The tested pair shares one nominal instance and one execution, with identical reported paths. Different textual requests are not universally distinct. |
| Repeated exact file/directory imports | One nominal instance and one execution. |
| Backslash load path | Accepted; reported paths use forward slashes in this load case. |
| Backslash versus forward-slash file imports | Distinct nominal instances and two executions; the backslash spelling remains in that import's reported filename/directory. Do not infer one universal separator-normalisation stage. |
| Wrong filename case in a load/file import; wrong final directory case in a directory import | Rejected with the Windows file-case portability diagnostic even though the filesystem can reach the existing source. |
| Lowercase containing directory in a load/file import, with exact filename case | Accepted; reports retain `original/`. Paired file imports using `Original/` and `original/` have distinct nominal types and two executions. The observed validation is not uniform full-path case enforcement. |
| Byte-identical modules relocated beside different neighbors | Distinct nominal types and values 11 versus 22 for both the relative load and the relative file import. Content equality does not establish dependency or result equality. |
| Byte-identical files with different filenames in the same directory | Same `#filepath`, different filenames in `#location`, distinct nominal types, and two executions. Directory context alone is insufficient. |
| Compile `../probe.jai` with the child process working in `Branch` | Entrypoint reports its normalised source path and still finds the source-relative `Original` module, not an unrelated directory under the process working directory. |
| Missing source-relative neighbor | Explicit missing-file error naming `Isolated/neighbor.jai`; the root decoy is not substituted. |
| Directory junction or native directory symlink, through load/file import | Accepted; reports retain `Alias/`. Paired file imports through original and alias paths have distinct nominal types and two executions, while both relative lookups yield 11. |
| Directory import through junction/symlink named `Alias` targeting `Original` | Rejected with the same file-case diagnostic, naming `Original` as the almost-matching basename. This is an observed alias validation result, not proof that all directory links are unsupported. |
| Junction named `Branch/Original` targeting `Original` | Directory import succeeds; paired with the original it has a distinct nominal type and two executions. This control discriminates the basename-dependent rejection above. |
| Native file symlink named `module_alias.jai` targeting `Original/module.jai` | Both load and file import reject it with the file-case diagnostic, naming `module.jai`. Its relative-lookup semantics therefore remain unobserved. |

Native directory/file symlink creation initially failed with `Administrator privilege required for this operation`; those cases were recorded as setup skips, not compiler rejections.
The user ran a narrowly scoped self-elevating PowerShell setup script, with transcript and JSON results written to the fixture directory, and all five native symlink cases then ran unelevated.
Junction creation worked unelevated on this ReFS volume.
The runner never auto-elevates; it records `link.log` and skips a case if the required link cannot be prepared.
Fixture setup permission does not authorise an editor service or evaluator to elevate arbitrary work.

For a full rerun after cleanup, first run the runner to create targets; if native symlink setup is denied, the user can prepare these five links in an elevated PowerShell opened in the examples directory, then rerun the compiler command normally:

```powershell
$root = Join-Path $PWD '.build/source_context'
foreach ($name in 'symlink_load', 'symlink_file_pair', 'symlink_dir_pair') {
    New-Item -ItemType SymbolicLink -Path "$root/$name/Alias" -Target "$root/$name/Original"
}
foreach ($name in 'file_symlink_load', 'file_symlink_pair') {
    New-Item -ItemType SymbolicLink -Path "$root/$name/module_alias.jai" -Target "$root/$name/Original/module.jai"
}
```

Generated sources, `compile.log`/`link.log`, expected-observation `summary.tsv`, setup evidence, and `audit_summary.json` remain under `examples/.build/source_context/`; cleanup may remove them.
The summary records exact expected directory/filename spellings, line numbers, relative values, evaluation counts, nominal equality, and error classes/counts for log auditing; failed compilations do not establish stable evaluation counts.
The runner asserts acceptance and supported nominal/value results; exact printed observations and rejection diagnostics were separately audited against the summary.

These are compiler-observable facts for this version/backend/platform/filesystem, not a universal path canonicalisation algorithm or permanent language guarantees.
E2's user-confirmed traversal-deduplication hole remains a compatibility limitation, not a cache design to preserve forever; E4 adds both further alias distinctions and a relative/absolute sharing counterexample.
Directory-link results establish visible spelling, nominal duplication, and successful relative lookups, not the compiler's unique internal path-resolution algorithm.
Relocation was tested with independent copied fixtures, not live rename/replacement while caches remain resident.
Hardlinks, UNC/network paths, drive-letter aliases, case-sensitive volumes, other platforms, link chains/retargeting, generated source maps, and arbitrary location-sensitive constructs remain unproven.
Architectural consequence: physical-source/content reuse, source-visible location/resolution context, and compiler-compatible request/nominal identity need separate validation rules.
Do not canonicalise away observable location strings, bypass case/link request diagnostics on a cache hit, or key contextual relative lookup solely by source bytes.

Suggested order is E1-E5 for language/toolchain facts, then E6-E8 for correctness contracts, then E9-E11 for representation/storage, with E12's baseline captured early and comparisons added as prototypes become available.
E5 is a bounded feasibility probe, not a prerequisite to implementing the syntax-first service if evaluation remains explicitly unsupported.
Do not block the initial specification on optional syntax-chunk reuse, binary formats, mmap, packed sentinel optimisation, or full compiler-backed evaluation; retain a simple supported baseline and explicit extension boundaries.

### From Evidence to a Completed Migration Plan

The specification is ready when each initial requirement has a defined owner, identity/version rule, state transition, failure behaviour, and executable acceptance criterion; remaining open items must be explicitly deferred rather than accidental gaps.
Include representative traces: notify-edit then await/query, parent/dependency changes, old-world retention, evict/reload, unsaved reset/restart, and a blocked/cancelled/unsupported query.
Approve the coverage/defaults and performance criteria after reviewing the experimental evidence and before judging adoption of competing optimisations.

Only then complete the migration plan by mapping current code, tests, and public operations to the approved contracts.
That plan must identify replacement/reuse/removal boundaries, dependency-ordered buildable steps, temporary adapters or deliberate API breaks, test/oracle preservation, persistence rollout/version rejection, cutover criteria, and cleanup.
Audit the current implementation again at that point: the present inventory is a starting point, not a promise that every migration task is already known.
The AST-copier keep/drop decision remains an independent measured decision, not an automatic consequence of the new model.

## 15. High-Level TODO

These are design/capability goals derived from this report, not an ordered migration plan.
No production changes are authorised by this checklist alone.

- [ ] Agree the remaining identity, persistence/privacy, workspace-trust, residency-budget, and performance policies in section 14.
- [x] Run and record E1's bounded compiler import/visibility matrix, including auditing expected-failure diagnostics.
- [x] Run and record E2's bounded module identity/parameter probes, including nominal compatibility, transitive configuration, expected diagnostics, and evaluation counts.
- [x] Run and record E3's bounded loaded-file composition probes, including occurrence multiplicity, scope, relative paths, contextual module values/types, cycles, and diagnostic/marker audits.
- [x] Run and record E4's bounded path/source-context probes, including case/alias validation, relative lookup, exact locations, nominal identity, native links, byte equality, and complete diagnostic/marker audits.
- [ ] Run and record the remaining bounded experiments E5-E12 in section 14, distinguishing initial specification blockers from explicitly deferred capabilities.
- [ ] Turn the evidence into approved initial contracts and acceptance criteria using the specification-completion gate in section 14, before writing the migration plan.
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
