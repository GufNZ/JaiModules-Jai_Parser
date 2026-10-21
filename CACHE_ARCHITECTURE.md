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
- Eventually use isolated official-compiler subprocesses for evaluations such as `#insert` and `using,map`, where necessary.
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
E6 below demonstrates that ownership boundary on a bounded projection of the existing parser's output, including recovery data and decoded strings.
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
- Optional cache-directory override, with a documented per-user default outside source repositories.
The concrete platform default needs a later API decision.
- Configurable memory/disk budgets (with unlimited (= all available space) as an option for disk) and retention policy, preferring resident validated data under ordinary conditions.
- Clear/invalidate operations, format/version inspection, cache-hit/miss reasons, and a way to recover from a damaged/outdated store, probably via reparse rather than a migration or similar.
- Independent workspace-trust and external-evaluation policy.
Enabling persistence is not permission to execute source code.

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
E5 below verifies this text channel on trusted fixtures, but not as a self-contained semantic-result protocol.
Use request-owned intermediate directories, inspect all relevant workspace outputs, and distinguish successful results from stale or failed-compilation artifacts.
The dump's comment headers are not unambiguous framing or complete scope/module provenance, and `using,map` results are not automatically emitted there.

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

Proposed explicit `using,map` evaluator: generate an owned mutable string array from the known exported member names in compiler-compatible order, reproduce the called procedure's required compilation context, invoke that procedure on the array, and capture the resulting strings through an explicit framed result channel.
Validate result cardinality, positional correspondence to the original members, and applicable identifier/collision rules; preserve empty strings as exclusions rather than dropping array slots.
Copy returned string payloads into result-owned storage before releasing evaluator storage.
Extracting just the procedure is insufficient if it depends on imports, private helpers, parameters, compile-time state, or source/caller context; preserve the necessary dependency closure or report unsupported.
E5 observed the real callback and its instrumented names, but did not test this explicit generated-array wrapper or its result protocol.
E13 below now validates a bounded generated-array wrapper against real mapping, including parameter/private-helper context, exclusions, framed results, and host-owned output after process teardown; general context extraction and production evaluation remain unsupported.
The absence of automatic mapping output in added-string dumps is not evidence against this proposed wrapper.

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

### Initial Scope and Acceptance Draft

Drafted 2026-10-20 from E1-E13.
**Initial capability scope approved 2026-10-20; acceptance targets and detailed contracts remain proposed, not implemented.**
The approval covers the syntax-first initial scope and recorded Windows x64 qualification target, including source/unsaved-recovery persistence and semantic/evaluator deferrals; it does not approve cache defaults, exact APIs, implementation or a migration plan.
This remains an initial capability boundary and acceptance proposal, not the completed specification.
Full syntax/semantic coverage and configured-module caching remain the eventual direction; a syntax-first initial slice must not silently become the permanent product boundary.
The numerical candidates below are engineering proposals, not requirements supplied by the user or thresholds established by the experiments.

#### Initial Capability Boundary (Scope Approved)

| Area | Initial candidate | Explicit boundary |
| --- | --- | --- |
| Qualification | Windows x64 with the recorded Jai beta 0.2.030 toolchain; fast-backend correctness and LLVM performance runs.  Start filesystem qualification on the measured ReFS environment. | This is a first qualification target, not proof of all Windows filesystems, other compiler versions, Linux, or macOS support.  Compatibility must be versioned, and additional platforms qualified separately. |
| Source and syntax | Disk and editor-buffer revisions, owned immutable whole-file syntax/diagnostics, exact source reconstruction, and syntax-derived declaration/span indices.  Reuse unchanged snapshots; fully parse changed files, including malformed edits. | No subtree-sharing, syntax-chunk store, or AST-copy requirement.  Syntax-derived indices are not resolved bindings, types, or a complete semantic declaration index. |
| World update/query | Revision-tagged change tickets and syntax/index publication milestones; selected-world queries return available, pending, superseded, cancelled, failed, or unsupported outcomes as applicable.  Leases protect retained snapshots. | No promise that syntax publication completes all future semantic analysis.  Queries never switch to a newer world implicitly.  Exact state transitions, threading and delivery contracts still require specification. |
| Composition and semantics | Preserve authored import/load requests and context in syntax; define the extension boundary for configured module instances and semantic query results. | The initial service does not claim semantic import closure, member/type inference, overload resolution, constant/layout evaluation, or semantic navigation/refactoring.  Requests needing these return unsupported, not a guessed binding, empty successful answer, or false language error.  Existing resolver behaviour is not silently reclassified as qualified cache-backed semantics. |
| Persistence | A versioned pointer-free text store for exact source revisions, document/recovery metadata, and manifests, with safe validation and fresh parsing as a valid reconstruction path.  Preserve the future syntax/semantic artifact boundaries. | Persistence remains an initial requirement, including unsaved revisions.  Persisting a complete AST is not required for initial operation; the experimental graph codec is not adopted.  Format, identity, publication, recovery and budget contracts remain to be specified and qualified. |
| Recovery and failure | Exact disk/overlay selection, host-confirmed unsaved recovery, explicit save/reset/rename/delete transitions, corrupt/incompatible artifacts treated as misses, and cache diagnostics separate from language diagnostics. | No automatic resurrection of an obsolete overlay or permission to overwrite a live buffer.  Cache write failures must not reject an otherwise valid source update. |
| Evaluation and later features | Evaluator capability initially unavailable; source-controlled opt-in and host authorisation remain mandatory prerequisites for any later backend.  Later editor features build on the same world contracts. | E5/E13 are feasibility evidence, not evaluator implementation.  No automatic compiler execution, cached effect replay, semantic rename/completion, or export-fix feature is included in this initial slice. |

This candidate does not choose cache directory/size defaults, recovery retention, a public API shape, or a declaration-matching algorithm.
Provisionally enabled persistence remains the earlier proposal, not a newly approved default; privacy and host recovery policy need an explicit decision before rollout.
In particular, deferring semantic operations is not permission to omit the semantic ownership, identity, dependency, and unsupported-state extension contracts from the specification.

#### Proposed Correctness Gates

Each gate is required for the corresponding initial capability, not a claim that a prototype has already qualified the future implementation.
Unsupported later capabilities must be labelled explicitly and excluded from successful-feature counts, not counted as passing semantic tests.

| Gate | Required check and oracle | Current evidence versus remaining work |
| --- | --- | --- |
| C1: Syntax equivalence | Compare retained, reparsed, and persisted/reconstructed results with independently owned fresh parses of the same exact source/context.  Check tokens, tree payloads, diagnostics, recovery, spans, and exact source bytes, including malformed edits. | E6/E12 establish bounded oracles.  Apply them to the initial implementation and its full declared supported syntax matrix; no lifetime aliases or silent mismatches are acceptable. |
| C2: Identity and source selection | Exercise parameter/configuration/version changes, path aliases, file creation/deletion/rename, negative lookups where supported, and disk/overlay save/reset/restart transitions.  Compare selected source/context against an explicit event-trace model. | E1-E4/E7/E11 supply rules and bounded controls.  Production identities/source-provider semantics and configured-semantic coverage are not qualified.  Uncertain matches must miss. |
| C3: Ownership and publication | Retain old worlds through edits, eviction, input release, and newer-world teardown; verify exact old/new results, stale-generation rejection, and zero owned live allocations after final release.  Force out-of-order completion and shared-waiter cancellation. | E6/E8/E9 support local models.  Real-service lease/publication/race tests remain necessary; a scheduler model is not a concurrent implementation test. |
| C4: Persistent-store failure | Validate before dereference/allocation using explicit format/read/allocation bounds; reject incompatible, truncated and corrupt data.  Test interrupted and competing writers, denied writes, restart, and leased-entry GC; compare selected state with fresh source reconstruction. | E10/E11 inform the design, not a safe production loader.  The E12 assert-aborting graph reader and post-read limits do not satisfy this gate.  Source operations must survive cache failure. |
| C5: Honest capability states | Trace notify, wait, world selection, query, supersession and cancellation; verify each promised milestone/terminal outcome.  For unsupported semantics/evaluation, assert explicit unsupported results and no compiler child process. | E8/E13 supply limited outcome/protocol evidence.  Host integration, untrusted-workspace behaviour and executable public-contract tests remain open. |

#### Provisional Performance Candidates

These are **approval candidates only; adoption is not authorised**.
Prefer paired same-work comparisons over absolute editor promises before the actual host and service exist.
Use the E12 inventories as the starting syntax corpus, include a representative larger project before generalising, and keep synthetic authored controls separate from real-project aggregates.
Run at least 21 measured trials per mode after declared warmups, alternate/rotate order, and report per-workload median and nearest-rank p95 plus raw samples in at least two separate local rounds.
This is a reproducible screening procedure, not a confidence interval or hard tail-latency guarantee; mixed or noise-sized results are inconclusive rather than a pass by averaging inventories.
Include source validation, hashing, I/O, allocation, result publication, and lifecycle cleanup consistently in competing modes.

| Gate | Candidate numerical target | Measurement and decision rule |
| --- | --- | --- |
| P1: Resident unchanged requests | At least 10% median improvement over fresh same-world parsing/index construction, with p95 no more than 5% worse, on each real inventory in both rounds. | End-to-end request through usable syntax/index result.  Exact-input checks and C1 still apply; a raw pointer lookup is not an equivalent competitor.  E12 suggests resident reuse is promising but does not qualify this future service path. |
| P2: Changed-file updates | Median and p95 no more than 5% slower than the fresh changed-file baseline with the same retained-world policy. | Notify-edit through usable revision-tagged syntax/index publication for body/interface/layout/malformed/repair sequences.  Report unrelated-file reuse separately.  Do not substitute compiler time or an isolated parser call for service latency. |
| P3: Optional persisted syntax reload | At least 10% median improvement and p95 no more than 5% worse than fresh-process source validation/parsing on each real inventory in both rounds. | Compare complete equivalent results, process wall time and worker phases separately.  Label filesystem conditions; only an agreed isolated cold-storage procedure supports OS-cold claims.  E12's verbose graph format shows a regression, not qualification of this candidate.  Source/metadata persistence remains required even if AST reload is deferred. |
| P4: Memory retention | At most 10% additional peak upstream backing versus the owned whole-file baseline for the same live world set; zero owned live allocations after all leases/worlds are released. | Measure current world plus two retained historical revisions, sparse eviction, and long edit/eviction cycles.  Report upstream backing and process memory separately; zero live ownership does not require the OS working set to return to its starting value.  Choose an absolute host budget separately. |
| P5: Persistent overhead | At most four times the exact source bytes in the steady-state managed store for the selected current plus two retained historical revisions. | Include manifests, indices and encoded source/artifacts in the numerator; count exact source bytes once per selected retained revision in the denominator.  Measure peak temporary publication space separately.  Drop/defer optional artifact encodings that fail, not required source persistence.  Absolute disk budget and pressure/GC policy still need agreement. |

No gate above is marked passed for a future service, and no absolute interactive-latency SLA is proposed without its host workload/hardware and measurements.
Memory/disk caps, latency trade-offs, retention counts and the 10%/5%/four-times candidates require review; they are not silently selected configuration defaults.
Before running acceptance measurements, approve the workloads, units/timing boundaries, supported host/toolchain, competing baseline and targets together.
Complete semantic dependency and editor-workflow measurements in section 13 remain necessary before adopting finer semantic granularity or making ReSharper-like performance claims; they are deferred from this syntax-first qualification, not declared complete.

#### Approval and Specification Work Still Required

- [x] Approve the syntax-first initial scope, recorded Windows x64 qualification target and semantic/evaluator deferrals, without authorising implementation or approving detailed contracts/defaults.
- [ ] Specify and review the supported extension route to broader syntax/semantic/platform coverage within the remaining detailed contracts.
- [ ] Approve or replace P1-P5, workload selection, larger-project coverage, retention policy, and the measurement procedure; set absolute host memory/disk budgets separately.
- [ ] Decide path/context identity, source-provider/recovery/privacy rules, cache defaults and multi-process policy without treating the prototypes as production contracts.
- [ ] Specify record/query ownership, state transitions, safe persistence, and version/unsupported behaviour for C1-C5 with executable acceptance cases.
- [ ] Qualify the initial implementation against those approved gates; retain explicit unrun OS-cold, semantic-workflow, concurrency and additional-platform checks where applicable.

### Core Contract Draft

Drafted 2026-10-20.
**Proposed, not approved or implemented.**
This makes the source, ownership and request boundaries concrete enough to review; the names describe logical records and outcomes, not public Jai declarations.
It does not complete the semantic, persistence-format, host-policy or concurrency specifications and does not approve the preceding scope/performance candidates.

#### Source Events and World Capture

The source provider is authoritative for editor buffers and acknowledged disk events; the artifact store is not a second authority for which revision is current.
An accepted source event identifies its workspace/session, document, previous provider revision, resulting revision or absence, and source-visible resolution context.
Provider ordering tokens distinguish successive events even if their resulting bytes are equal; content identity may still permit safe artifact reuse.
Reject an invalid event explicitly without changing the current selection or reporting a successful update ticket.
Before acknowledging accepted input, acquire owned bytes or an explicit immutable provider lease; no deferred work may borrow the caller's temporary edit buffer.

Proposed ranged-edit coordinates are zero-based byte offsets into the exact base revision, with half-open ranges.
Adapters convert editor-specific UTF-16/line coordinates using that same revision, not the latest buffer.
Require matching base revision, in-range endpoints and a documented batch convention: initially one ordered sequence, with each edit applied to the result of the preceding edit.
Reject mismatched bases and invalid ranges rather than silently rebasing, clipping, or partially applying the batch; a full-replacement event is the recovery path.
These coordinate/batch rules are approval candidates, not assertions about existing parser APIs or a new UTF-8-validity restriction on source bytes.

| Event | Proposed source selection and observable result |
| --- | --- |
| Open or replace overlay | Select the host-supplied revision over disk.  Retain disk state separately; identical bytes alone do not acknowledge a save or discard. |
| External disk update | Advance the acknowledged disk reference; an active overlay remains selected.  Without an overlay, select the new disk revision and schedule its syntax milestone. |
| Save acknowledgement | Record the exact revision actually written and acknowledged by the host.  Clear/reconcile the overlay only if the host confirms that it is that saved revision; a newer overlay edit remains selected.  A failed or delayed save must not mark the newer buffer saved. |
| Reset/discard | On host confirmation, remove the active overlay and its active recovery reference, then select freshly validated disk bytes or explicit absence.  Cached history cannot reactivate the discarded overlay. |
| Delete | Mark the disk reference absent.  Preserve an active host buffer as an overlay; without one, publish source absence, not an empty parsed file or an old cached revision. |
| Rename/replacement | Accept an explicit host event and revalidate source-visible context and resolution inputs.  Do not infer declaration/module continuity or alias equivalence from matching bytes.  Exact physical identity and cross-file atomic-event policy remain decisions. |
| Restart/recovery | Validate disk/configuration; expose persisted overlays only as recovery candidates.  Activate a candidate only after host confirmation, through a new source event. |
| Cache failure | Preserve the accepted in-memory source selection, reconstruct from authoritative bytes where possible, and report a separate cache diagnostic.  Source acquisition failure is explicit unavailability/failure, not permission to use a stale revision. |

A captured world contains immutable selected document-revision/context references and the source-provider event frontier used to choose them.
Publication installs a coherent world atomically; completion of old work never rewrites an already captured world or silently makes an old world current.
If later dependency discovery requires a source not captured in that world, use an immutable provider snapshot capable of supplying that frontier's bytes, or return an explicit unavailable/incomplete result requiring a new world.
Do not read today's disk file and attach it silently to yesterday's world; the exact provider snapshot/discovery mechanism remains to be specified.
Initial syntax publication does not assert a complete import closure or semantic world.

#### Ownership and Publication

| Owner | Proposed lifetime obligation |
| --- | --- |
| Source/syntax snapshot | Own or lease exact source/path payloads, tokens, nodes, diagnostics, recovery records and syntax indices.  These are immutable after publication and cannot borrow parser scratch, evaluator memory or a released producer snapshot. |
| Captured world | Hold strong references/leases to its selected source/syntax and context records.  Reusing syntax does not share mutable semantic state.  A newer world cannot invalidate an older world's references. |
| Semantic query/group | Own derived records and dependency stamps separately from syntax; lease required syntax/context.  Cyclic group ownership/reclamation still needs its own contract before semantic implementation. |
| Pending task | Own its scratch and protected inputs until completion or acknowledged termination.  Request cancellation alone is not proof that the worker stopped reading those inputs. |
| Request/result lease | Protect the selected world and returned payload through explicit release.  Releasing a pending waiter detaches that waiter; acquiring a result must establish its protection before task/cache protection is dropped. |
| Resident/disk cache | May evict only when ownership permits; budget pressure cannot free leased backing.  Record/slot reuse changes allocation generation, and stale handles must reject rather than resolve a different record.  Raw addresses are not persistent identities. |

Publish immutable payload and its revision/context/dependency identity as one observable action; never expose a ready flag before the protected payload exists.
Cache residency, world selection, task completion, and durable-store publication are separate events.
A syntax milestone need not wait for a cache write: expose persistence failure/status separately, and do not promise durability until the required artifact and manifest commit has succeeded.
If leases prevent meeting a configured memory budget, report pressure or reject new optional work under an agreed host policy; never silently revoke a live lease.
Exact lease representation, synchronisation, pressure policy and shutdown ownership ordering remain specification work.

#### Update Tickets and Query Outcomes

An accepted change returns a ticket for its requested revision and milestone; it does not return an unqualified promise that all analysis is complete.
Proposed update lifecycle: `queued -> running -> published | superseded | cancelled | failed`, allowing direct queued-to-terminal transitions where appropriate.
`published` identifies the exact captured world and achieved syntax/index milestone, including incomplete-code diagnostics where applicable.
`superseded` means that milestone was not delivered for the requested revision; include a successor ticket only if one exists, and require explicit selection of its result.
Cancelling a wait is independent of cancelling underlying work; neither action implicitly discards accepted buffer contents or selects another source revision.
An abandoned update must report its terminal reason; retrying analysis of retained source uses an explicit new request/ticket.

| Selected-world query outcome | Required meaning |
| --- | --- |
| Available | Return a protected payload, world/revision/context identity, and completeness/diagnostic status.  Syntax with parse diagnostics may be available; incomplete semantic knowledge is not a successful negative lookup. |
| Pending | Return a waiter for work keyed by the selected world/query/context.  Deduplicate equivalent work, but track waiter cancellation independently.  Internal blocked dependencies are not a successful result. |
| Unavailable | State the reason, such as an absent source or unavailable captured provider revision, without substituting current disk bytes or fabricating a language diagnostic. |
| Unsupported | State the unsupported capability/context.  Do not schedule evaluator execution, return an empty successful answer, or leave a waiter pending forever for functionality not supplied. |
| Failed | Report computation/source/service failure separately from ordinary syntax diagnostics and cache-recovery warnings; include the selected identity where available. |
| Cancelled | Complete only the cancelled waiter/request.  Other waiters may still receive the protected result of shared work. |

Each ticket/waiter has at most one terminal transition; observation/waiting after termination returns that outcome rather than consuming it or causing another transition.
Check operation generation and terminal state at publication so duplicate/late completion cannot resurrect cancelled work, overwrite a superseded ticket or deliver a payload to a released waiter.
A query on an explicitly retained old world is not automatically superseded by a new head world; its identity remains old until the caller selects another world.
Callback delivery, reentrancy, wait primitives, worker cancellation and shutdown semantics still need an approved execution model and real concurrent tests.

#### Acceptance Trace Drafts

These are future executable acceptance cases for C1-C5, not additional experiments already run or tests already passing.
Each trace must assert the selected identities and exact fresh-oracle result where supported, not merely cache-hit counters.

| Trace | Events and required assertions | Gates |
| --- | --- | --- |
| T1: Edit and query | Capture disk world A; notify overlay B; await B's syntax milestone; query B.  Assert exact B bytes/diagnostics, no semantic-completion promise, and unchanged leased A results. | C1, C2, C3, C5 |
| T2: Stale edit batch | Submit a range based on A after B is selected, then a batch containing an invalid range.  Reject each atomically with B unchanged; a valid full replacement can subsequently succeed. | C1, C2, C5 |
| T3: Save racing edit | Submit save of B, select newer overlay C, then receive B's save acknowledgement.  Disk points to B while the active overlay remains C; neither the late acknowledgement nor equal-byte reuse discards C. | C2, C5 |
| T4: Reset and restart | With disk A and overlay B, confirm reset, release/restart, and validate disk.  Select current disk or absence, never B merely because its blob remains.  A separate confirmed recovery of B is a new explicit event. | C2, C4, C5 |
| T5: Retention and reload | Lease A, publish B, request eviction and release producer/scratch storage.  A and B remain exact until their respective leases end; freed generations reject stale handles.  Rehydration failure reconstructs or reports unavailability without changing source selection. | C1, C3, C4 |
| T6: Shared waiters | Two waiters join one world-keyed query; cancel/release one, complete the task, then attempt duplicate completion.  The survivor receives one protected result; the cancelled waiter receives no late payload. | C3, C5 |
| T7: Superseded update | Queue B then C and finish work out of order.  Each ticket gets one truthful terminal outcome; B cannot replace C as head, but an explicitly retained B world can still be queried. | C2, C3, C5 |
| T8: Cache and capability failures | Deny store writes or corrupt an artifact, then notify/query valid source and request unsupported semantics/evaluation.  Source syntax remains usable, cache warnings stay separate, unsupported is terminal, and no compiler process launches. | C1, C4, C5 |

Still open: approval of these contracts; exact record schemas and identities; semantic stage/dependency contracts; safe store format/publication/GC; source discovery and atomic multi-document capture; notification/threading/shutdown design; and executable implementation qualification.
The migration-plan gate and all scope/performance approval gates remain open.

### Persistence Contract Draft

Drafted 2026-10-20.
**Proposed, not approved or implemented.**
This refines C2-C4 and the source/world contracts using E10/E11, without adopting their experimental formats, fixed fixture limits, or filesystem guarantees as a production implementation.
Text records using `Text_File_Handler` remain the initial direction; exact grammar, schema IDs, numeric bounds, lock primitives and supported filesystem durability guarantees still require specification and approval.
Required source/recovery persistence is distinct from optional decoded-syntax or semantic artifacts.

#### Records and Persistent Identity

| Logical record | Proposed required content and boundary |
| --- | --- |
| Store descriptor | Format/schema versions, store namespace and compatibility policy.  Do not infer compatibility from the directory name or compiler version alone. |
| Source artifact | Exact source bytes, byte length and strong digest, plus encoding information needed to reconstruct those bytes without newline/Unicode normalisation.  Preserve arbitrary parser-accepted bytes; the text envelope may encode them. |
| Context descriptor | Document/path identity inputs, source-visible filename/directory, resolver/parser configuration and their versions.  Include configured module/program/import-request discriminators for semantic artifacts; physical-file equality is not semantic identity. |
| Optional derived artifact | Record kind/schema, producer/query version, source/context references, completeness/support status and validated dependency identities.  Payloads contain explicit IDs/offsets, never pointers, allocators, pools or process-local reflection objects. |
| Workspace manifest | Workspace namespace, committed generation, and roots for acknowledged disk revisions, recoverable overlay candidates and policy-retained history.  Reference immutable artifacts; record absence/reset state explicitly where needed.  A manifest is not authority that cached disk bytes are still current. |
| Recovery descriptor | Workspace/document-session association, exact source/context reference and host recovery provenance needed to present a candidate.  No automatic activation flag inferred from recency.  Save/reset/discard advance or remove the corresponding recovery reference explicitly. |

Use canonical versioned encodings for identity inputs; equal decoded values in different ad hoc spellings must not accidentally become a different key, or vice versa.
Candidate immutable artifact keys are SHA-256 of the exact encoded artifact bytes, with source-byte and logical-context validation inside the record.
This separates wire integrity from source identity and dependency validity; a matching outer digest alone is not a valid syntax/semantic hit.
Verify existing content before treating a same-key file as reusable; conflicting or invalid content is a cache fault, not permission to overwrite a blob potentially used by another reader.
Checksums/digests detect corruption, not authenticity against an attacker able to replace content and hashes together.
Persisted data never grants compiler-execution permission.

Use only validated encoded keys to form store-relative paths; never concatenate raw source paths, supplied artifact names or unvalidated dependency IDs.
The concrete directory layout must retain the source/context and module-instance distinctions described in section 8, while allowing context-independent source bytes to be shared.
Reject traversal, out-of-store redirects and unsupported link/reparse-point cases under an explicit filesystem policy; user-private permissions are necessary but not a substitute for validation.
Session tickets, raw world handles, allocation generations and live request leases are not restored as active process objects; reconstruct fresh session identities and validate persisted references.

#### Read and Validation Sequence

1. Open the configured store under the approved trust/path policy.
If unavailable or incompatible, retain correct in-memory operation and report a cache diagnostic.
2. Acquire a coherent manifest generation and protect its selected records against concurrent collection before accessing them.
The exact pin/open protocol must be shared with publishers and GC, not improvised by a reader after deletion becomes possible.
3. Check actual open-stream sizes against manifest/artifact limits before allocating or reading the declared payload.
Bound aggregate decoded bytes, record/dependency counts, nesting, temporary storage and arithmetic; recheck truncated/changing input rather than trusting a prior path stat.
4. Decode a versioned envelope with exact lengths and byte-preserving payload encoding.
Reject unsupported record kinds/versions, duplicate required fields, invalid IDs, trailing data, malformed references and unsupported extensions according to the specified grammar.
5. Verify encoded-byte digest, inner source length/digest, expected context/configuration and supported producer/schema.
Validate every dependency needed for the requested result; uncertain or unavailable dependencies cause a miss/incomplete outcome, not a stale hit.
6. Reconstruct into unpublished owned storage.
Validate structural references, ranges and object/array bounds before exposing any result.
On failure release partial ownership, report the cache fault, and use fresh authoritative source computation where available.
7. Publish only a complete protected result or an explicit unavailable/unsupported/failed outcome.
Parsing malformed source may produce an available syntax result with diagnostics; corrupt store bytes must not be converted into source-language errors.

Loading a source artifact requires exact authoritative disk/overlay selection first; a cached saved revision is not a substitute for checking current disk bytes.
Recovery candidates are a separate host-confirmed source input and may be inspected without first being activated as an overlay.
Do not eagerly decode historical graphs; validate/load only the records needed for the selected source or query, and bound each resulting dependency traversal.
Concrete numeric limits must be approved and enforced before qualifying a loader; E12's assert-aborting reader and post-read checks do not meet this contract.

#### Publication, Contention and Durability

Proposed publication sequence:

1. Construct and validate immutable candidate records in request-owned staging storage; use unique same-filesystem temporary paths.
Never expose partial bytes under a committed key or manifest name.
2. Acquire the store's cooperative mutation coordination with an explicit bounded wait/fail-open policy.
Re-read and validate the latest manifest generation before applying only this operation's intended changes, including disk/recovery slots independently.
3. Install validated immutable artifacts before any manifest references them.
Reuse a verified existing artifact, or publish a complete new one with the approved filesystem primitive.
Coordinate this step with GC so newly installed unreferenced blobs cannot be collected before commit.
4. Build a complete next-generation manifest, validate its references, then replace the committed manifest atomically under the qualified filesystem contract.
Readers must select either a complete prior generation or a complete new generation, never a mixed update.
5. Report the committed generation and release coordination/staging resources.
If publication fails before the commit point, preserve the prior selected state and report failure/contention separately from successful in-memory syntax publication.
Uncertain commit outcomes require reconciliation by re-reading the committed generation/operation identity, not blind replay.

An update racing another save/reset must validate its host event/session ordering before replacing recovery metadata; a late writer cannot resurrect an older recovery root simply because it acquired the lock later.
Lock ownership, operation identity/idempotence, crash release, retry policy and stale-session handling need exact platform contracts; process-ID reuse or a timeout alone is not proof that an owner died.
Do not hold service/world locks while waiting for store coordination, and do not make store contention block otherwise valid source selection indefinitely.
The cache never writes editor source files as a side effect of committing a manifest.

Distinguish in-memory availability, successful atomic process-visible commit, and power-loss durability in diagnostics/status.
Only claim the last after specifying and qualifying required file and directory flush/replacement guarantees on the supported filesystem; E11's killed-process checks do not establish power-loss recovery.
A corrupt committed manifest must not be overwritten by guessing its roots.
Fall back to in-memory operation and an explicit repair/reinitialisation policy that preserves recoverable candidates or reports their loss risk.

#### Recovery, Collection and Pressure

Host save/reset/discard updates the active in-memory source state independently of persistence success.
If removal of a recovery reference cannot be committed, report that cleanup is not durable; never claim the old candidate was removed from disk.
On a later restart, even a surviving candidate still requires host confirmation and cannot silently override a newly opened buffer.
Persistence disabled means no store reads/writes or recovery activation; disabling it must not change the source/world semantics or imply that previously stored private data was deleted.
Explicit clear/retention controls must explain their scope, protected roots and failures; deletion is not secure erasure from storage or backups.

GC uses validated committed roots, retained history and all live leases/pins from participating processes under the same publication/reader coordination protocol.
It may collect only artifacts proved unreachable and unprotected, plus abandoned staging proved not to belong to a live publication.
Unknown/corrupt roots or uncertain cross-process lease ownership require conservative retention/fail-closed collection, not speculative deletion.
Readers must pin the selected generation/artifacts or hold a qualified open backing handle before GC may unlink them; lazy reopening by pathname needs a surviving disk pin, not merely an in-memory pointer lease.
In-memory-only results may permit unlinking optional disk artifacts if every surviving result is independent of those bytes, but never revoke required recovery/source roots as an unnoticed optimisation.

Distinguish resident eviction, removal of optional derived artifacts, expiry of historical recovery candidates and deletion of acknowledged source/recovery roots.
Under budget pressure reclaim unleased optional/history data according to an approved retention policy; protected live data may exceed the target until released.
If required roots cannot fit or writes fail, surface pressure/persistence degradation and continue correct source operations; do not silently drop unsaved recovery while reporting persistence success.
Absolute budgets, retention defaults, cross-process pin representation, shared-store scope and clearing/privacy behaviour remain approval decisions.

#### Store Acceptance Trace Drafts

These are future executable C2-C4 qualification cases, not new passing experiments or evidence of production durability.

| Trace | Required assertions |
| --- | --- |
| S1: Bounded decoding | Reject oversized/truncated envelopes, overflowed lengths/counts, invalid IDs/ranges, wrong schemas/context and unresolved dependencies before unsafe allocation/dereference; release partial storage and compare fallback with fresh source. |
| S2: Interrupted publication | Interrupt at staging, artifact-install, manifest-write and manifest-replacement boundaries.  A fresh reader selects a complete old/new generation or explicit recoverable fault, never a partial/mixed state; label process-kill versus power-loss coverage. |
| S3: Competing slot updates | Race disk and recovery publications from one base generation.  Successful retry preserves both intended updates; a late old-session reset/save cannot replace newer recovery state. |
| S4: Reader versus GC | Pause a reader between manifest selection, pin acquisition and lazy artifact access while another process collects.  The qualified coordination protects required backing or returns a safe retry/miss; no leased result becomes dangling. |
| S5: Corrupt roots | Corrupt the manifest or make a live lease indeterminate.  Fresh source remains usable, collection retains uncertain candidates, and repair never silently guesses/deletes their roots. |
| S6: Failed discard commit | Confirm host discard/reset, deny metadata writes, then restart.  In-memory selection followed the host, failed cleanup was reported, and surviving recovery remains only a candidate requiring new host confirmation. |
| S7: Pressure and disable | Hold world/recovery pins while exceeding the configured budget, then disable persistence.  Report protected pressure/degradation without false durable success or source failure; no further store access occurs while disabled and prior data is not falsely reported deleted. |
| S8: Namespace and permission failure | Supply unsafe keys/out-of-store redirects, foreign namespace/version data and denied paths.  Reject or miss with cache diagnostics, never escape the store, modify editor source or launch a compiler. |

Still open: exact text grammar/record schemas and bounds; operation/session merge ordering; locks/pins and filesystem guarantees; repair/privacy/default policies; implementation and concurrent/platform qualification.
No store acceptance trace, power-loss claim, scope/performance approval, or migration gate is marked complete by this draft.

### Semantic Identity and Dependency Contract Draft

Drafted 2026-10-20.
**R5 direction approved 2026-10-21; detailed schemas/algorithms remain proposed and unimplemented.**
This refines the eventual semantic extension using E1-E8; it does not add semantics to the proposed syntax-first initial slice or qualify the current resolver as a cache-backed typechecker.
Identity matching, canonical parameter encodings, stage schemas and supported Jai rules still require specification, approval and executable qualification.
The following records are logical obligations, not public API names or a compiler-internal pipeline claim.

#### Identity and Revision Separation

| Identity boundary | Proposed rule |
| --- | --- |
| Configured module instance | Include resolved source plus validated compiler-compatible import-request distinctions, ordered explicitly supplied typed module arguments, and effective program/target settings.  Do not merge omitted versus explicit defaults, reordered arguments or path aliases merely because effective values/bytes match; preserve E2/E4 distinctions until a rule is qualified. |
| Loaded declaration occurrence | Distinguish each semantically relevant load occurrence and its source-visible/resolution context inside the owning module instance.  A shared physical syntax snapshot does not deduplicate repeated declarations, module-private state or nominal types. |
| Declaration identity | Identify a declaration within its configured instance/occurrence and logical owner.  Keep a separate declaration revision for its selected syntax/context.  Name, byte span, syntax hash and allocator address alone are insufficient. |
| Cross-edit matching | Retain a logical declaration identity only after a specified unambiguous match within compatible ownership/context.  Reordering/moves, overloads and identical anonymous declarations need explicit rules.  Uncertain matches get fresh identities and conservative misses, not guessed continuity. |
| Nominal and instantiated types | Root nominal identity in the owning declaration identity and configured instance; keep revision-dependent type facts separate.  Instantiations include validated typed argument identities/values and relevant context, not display names or a layout hash.  Structural layout equality cannot merge distinct nominal types. |
| Struct and completed-context member comparison | Ordinary struct member descriptors, including `Context_Base`, preserve source order.  Completed `#Context` compares that ordered base plus canonical order-independent `#add_context` fields as defined in section 6.3; compiler encounter order is not logical context identity.  Layout/reflection/initialisation facets require their own observations. |
| Query and task | A logical query key includes operation/version, subject, explicit arguments and semantic context.  In-flight work additionally captures the selected world; a new world's request cannot accidentally join computation over old inputs.  Cross-world result reuse requires validation rather than equal logical keys alone. |
| Persisted identity | Encode logical identities/revisions with a versioned schema and validated reference graph.  Restart reconstructs fresh live handles; uncertain cross-restart matching is a miss.  Do not persist pointer identity, occupied pool slots or session allocation generations as semantic identity. |

A retained old world keeps its original identities, revisions and lookup views even when a new world chooses different matches.
Matching identifies the logical subject; it does not certify that its old result remains valid after an edit.
Exact path/alias policy, typed-value canonicalisation, declaration-matching algorithm and persisted-ID allocation remain open choices, not implicit defaults selected by this table.

#### Query Records and Observed Dependencies

Every successful reusable computation publishes its protected immutable result together with the exact context and dependencies observed in that captured world.
Proposed dependency records identify the observed subject, facet/query kind, context, observed revision/fingerprint, completeness and dependency-record schema version.
An edge also records the parent's validation state independently of the target's current revision: E7's link-stamp/target-stamp distinction must not collapse into one mutable target flag.
Record dependencies during actual reads, including candidate discovery, missing-name results and configuration reads; a guessed static dependency list is not sufficient.

| Observed facet | Required dependency and invalidation boundary |
| --- | --- |
| Scope membership and visibility | Observe the complete relevant scope/import/load membership and access context, including file/module/export restrictions.  Adding/removing a name or changing visibility invalidates affected successful and negative lookups.  An all-visibility index is not an access-filtered binding result. |
| Overload candidates | Observe the eligible candidate set as well as facts used to select one candidate.  A new candidate may change the answer even when the previously selected procedure is unchanged. |
| Procedure signature/body | Separate signature and body results where their inputs permit.  Inferred signatures, defaults, inline/compile-time behaviour, reflection and caller-context operations must observe the body/context they actually use; a body edit is not universally private. |
| Types, constants and layout | Observe nominal/instantiation identity, field membership/types, constants/conditions, target/ABI and prerequisite milestones.  Equal size alone is not equal type or equal layout semantics. |
| Source locations | Track source revision and mapping/context independently of reusable semantic values.  A whitespace-only edit may preserve a value while changing the spans needed to display diagnostics or apply edits. |
| Generated membership/evaluation | Observe conditions, generated syntax and tracked evaluator inputs/effects/provenance.  Incomplete discovery is provisional; unknown effects or unavailable context are unsupported/non-persistable, not a complete stable interface. |

Never cache a definitive negative lookup from a scope whose relevant imports/conditions/generated membership are still incomplete.
If a required observation cannot be represented or tracked, conservatively depend on the whole configured module/context, recompute, or return an explicit incomplete/unsupported result.
Initial whole-module semantic invalidation remains acceptable; fine-grained reuse is an optimisation subject to these same correctness obligations.

#### Validation and Publication Sequence

1. Resolve the requested subject/context in the selected captured world, without silently attaching a newer source revision or changing configured instance.
2. Check query/producer/schema compatibility and all explicit identity/context inputs.
Equal fingerprints do not bypass these guards; unknown identity or configuration is a miss.
3. Validate every recorded dependency in that world.
Dirty means potentially stale, not automatically wrong or automatically reusable.
Missing records, changed membership/completeness and unverifiable inputs require recomputation or explicit unavailability.
4. If recomputing, capture reads against immutable world-selected inputs, collect provisional dynamic dependencies, and obtain required milestones.
Cancellation/failure must not publish a partially collected dependency set as a complete result.
5. Publish payload, completeness/diagnostics and dependency records atomically with world protection.
Use domain-separated versioned fingerprints of the observable facet, with collision/integrity safeguards; never hash process addresses or omit observable identity/status.
6. Stop downstream propagation on equal observable results only where the consumer's observed facet, identity, context and completeness remain compatible.
Refresh validation stamps for the new dependency observations even when the reusable value is unchanged; validate source maps separately.

Reverse edges accelerate dirty propagation but do not prove validity; missed watcher events must not certify a hit after restart.
Persist a deterministic language error only with its complete validated inputs/dependencies; cancellation, missing compiler capability, transient I/O failure and incomplete discovery are not persistent claims that source is invalid.
Cross-world reuse must still publish a result identified with the requesting world and its valid current source mapping; do not relabel stale diagnostic spans or expose mutable result objects shared between worlds.

#### Declaration Milestones and Cycles

| Logical milestone | Readiness and extension rule |
| --- | --- |
| Declaration/scope discovery | Syntax-backed identity and provisional membership can exist before full semantics.  Mark whether the relevant import/conditional/generated membership is complete; do not promise a closed namespace prematurely. |
| Nominal identity and signature | Publish protected identities and independently ready signatures where the declaration's rules allow it.  Recursive references may use an incomplete identity without asserting completed layout/body facts. |
| Constant/condition/instantiation | Request the precise prerequisite facts and track explicit context/arguments.  Unsupported evaluation yields an explicit outcome, not a fabricated constant or silently omitted declaration. |
| Aggregate layout and values | Wait for required field/value/layout milestones; legal pointer recursion and impossible by-value recursion require different outcomes under qualified language rules. |
| Body/expression analysis | Depend on ready signatures, lookup/candidate sets and queried type/value facts; publish independently of unrelated declaration bodies when dependencies permit. |
| Generated syntax and final diagnostics | New generated input re-enters syntax/discovery with provenance.  Consumers of changed membership must be invalidated or remain provisional; a completed earlier stage does not mean all later semantic work is complete. |

These are a query catalogue outline, not one mandatory total order: inferred types, polymorphism and generated work may introduce additional prerequisites dynamically.
Detect cycles from required unresolved graph edges and classify them using the supported declaration rules; report blocking identities/milestones for an illegal cycle.
External pending work and scheduler idleness alone do not establish a cycle.
No generic recursion guard, global fixed-point solver, or compiler evaluator is required merely to complete this draft.
Actual stage schemas, legal recursion classes, generated-work discovery and cancellation/retry ownership remain specification and implementation work.

#### Semantic Acceptance Trace Drafts

These are future executable equivalence/invalidation cases, not new passing experiments or claims of full semantic support.
Use fresh same-world computation as the cache oracle and isolated official-compiler fixtures for supported language facts; unimplemented semantic operations must return unsupported.

| Trace | Required assertions |
| --- | --- |
| D1: Instance and occurrence separation | Reuse physical syntax across distinct import requests/parameters and repeated loads.  Preserve qualified nominal/visibility distinctions and occurrence multiplicity; no false declaration/type equality. |
| D2: Ambiguous declaration matching | Reorder/move declarations and introduce identical/overloaded candidates.  Retain identities only for qualified unambiguous matches; conservative misses are acceptable, false identity reuse is not.  Old leased worlds remain unchanged. |
| D3: Negative and visibility dependencies | Cache a supported missing/inaccessible name, then add it or change scope/import visibility.  Recompute the access-filtered lookup without turning inaccessible candidates into bindings. |
| D4: Candidate-set change | Cache overload selection, then add/remove an eligible candidate while preserving the old winner's bytes.  Compare selection/ambiguity diagnostics against fresh computation. |
| D5: Signature versus body | Change a local implementation, then an inferred/default/inline or compile-time-observed body.  Reuse only unaffected observed facets; body-sensitive consumers and current diagnostic locations remain fresh-equivalent. |
| D6: Constants and target | Change a constant-driven field dimension or target context.  Revalidate layout/ABI consumers without conflating equal-sized nominal types or reusing facts from another configured instance. |
| D7: Equal result, new observation | Change an upstream revision while preserving an observed value, then change it again.  The first edit may stop propagation, but refreshed edge stamps make the second edit invalidate correctly; changed spans are remapped separately. |
| D8: Provisional work and cycles | Discover a generated/imported name after an initial miss, and contrast legal pointer recursion, illegal by-value recursion and externally pending work.  Provisional results never become false complete negatives; only qualified actual cycles produce cycle diagnostics. |

Still open: identity/canonicalisation/matching algorithms, supported semantic slice, exact query/facet schemas, generated/evaluator dependency contracts, cycle classes and executable fresh-oracle qualification.
No semantic trace is marked passed here; syntax-first deferrals, policy approvals, performance qualification and the migration-plan gate remain unchanged.

### Execution and Shutdown Contract Draft

Drafted 2026-10-20.
**R4 direction approved 2026-10-21; detailed execution/limit contracts remain proposed and unimplemented.**
This refines C3/C5 and the core ticket/lease contracts using E8's bounded scheduler evidence; E8 did not test actual concurrent workers, reentrant callbacks or stopping a running worker.
The proposed initial delivery mechanism is host-pulled completion records plus poll/wait, not arbitrary callbacks from workers.
Exact Jai signatures, lock primitives, thread counts, event-loop integration and queue/budget values remain open; this draft neither implements a scheduler nor approves an execution platform.

#### Coordinator and Worker Boundary

A logical coordinator serialises source-event acceptance, task registration, dependency readiness, waiter attachment/cancellation, terminal-state publication and head-world selection.
This is a linearisation responsibility, not a requirement for a dedicated thread or a single global lock.
Every externally visible transition must have a defined ordering against competing transitions; acquiring a payload lease is part of observing an available result, not a later unprotected operation.

| Operation | Proposed ordering and ownership rule |
| --- | --- |
| Accept source/update | Validate provider ordering and admission capacity before acknowledgement.  Own/lease the input and install the ticket coherently; no caller receives success for work the service cannot retain.  Store failure alone does not reject otherwise valid in-memory work. |
| Request/join query | Atomically inspect the selected world-keyed task, return a protected existing terminal result or register a waiter for pending work.  Completion racing registration cannot strand a waiter or create two equivalent tasks. |
| Dispatch worker | Transfer protected immutable inputs and owned scratch, plus task identity/allocation generation and attempt token.  A worker must not mutate published syntax/worlds or call host code while holding service coordination. |
| Complete worker | Validate task/world/generation/attempt and the expected nonterminal state; publish result/dependencies together before resolving surviving waiters.  Duplicate or obsolete completions are rejected, and their unpublished payloads released by their recorded owner. |
| Cancel/release waiter | Order cancellation against terminal publication.  If cancellation wins, that waiter is cancelled and gets no result payload; if completion won, its existing terminal outcome is not rewritten.  Releasing the handle retires its notification interest and protection explicitly. |
| Coalesce update work | Preserve accepted source-event ordering and each ticket's truthful milestone outcome.  Only unneeded computations may be skipped; an older completion cannot replace a newer selected head or silently satisfy a different revision's ticket. |

Do not invoke filesystem/compiler/provider callbacks, wait on dependencies, or block on store coordination while holding service state locks.
Acquire external inputs through an explicit asynchronous or bounded operation, then revalidate its captured identity at publication; returning from an external call does not make its result current.
Provider re-entry, lock ordering and cross-component ownership transfer need explicit implementation rules, not reliance on recursive locks.

#### Completion Observation and Host Delivery

An immediate terminal query response needs no later completion notification for that call.
A pending response installs a live waiter whose terminal outcome is retained until observed/released according to its handle contract, even if completion happens before the caller next polls.
Poll/wait reads that same stable outcome; it does not consume the payload, repeat the terminal transition, or implicitly select a newer world.
A timeout stops that wait attempt and reports pending/timeout, not cancellation or source failure unless the caller separately requests cancellation.

Proposed host delivery is a completion registry/queue addressed by protected handle identity and generation, with a coalescible wake signal.
Host draining emits at most one terminal completion record per live pending registration; a lost/coalesced wake must not lose the retained outcome.
Registering/inspecting completion and arming a wait must prevent the classic check-then-sleep lost wakeup; poll remains authoritative if the host delays delivery.
Queue pressure must not silently drop terminal outcomes: reserve admission/retention capacity, use a bounded indexed registry, or reject new work explicitly before acknowledgement.
The concrete representation and numeric limits still need specification.

Drain/delivery is host-owned and serialised for a subscription; the core never invokes a host callback inline from submission, task completion or cancellation.
A callback adapter, if added, runs only while the host explicitly dispatches records, outside internal locks and with callback argument/result leases held through return.
The host may submit/cancel/query again from that callback; re-entry is a new operation, not permission to recursively mutate the notification iteration or access released handles.
Release during delivery suppresses future interest, but backing used by the active delivery stays leased until it returns.
Callback exceptions/failures must not change an already committed task outcome or leak its delivery lease; the adapter's error reporting and reentrant-dispatch policy remain to be specified.
No UI thread affinity is inferred; the adapter/host must declare its dispatch thread and avoid a blocking wait that depends on progress on that same thread.

#### Cancellation, Scheduling and Pressure

Waiter cancellation is independent of computation cancellation and never undoes an accepted source event.
Cancel underlying work only after confirming there are no other waiters, required update milestones or dependency consumers that still need it, or as part of explicit service shutdown.
The initial last-consumer policy may retain or cooperatively stop an unneeded computation; it must be chosen explicitly and cannot affect correctness of surviving results.
Cancellation is a request until the worker acknowledges termination or returns; retain its inputs, scratch and completion routing throughout that interval.
If a new attempt starts, use a new attempt token; an old worker cannot complete the new attempt even when the logical query key matches.

Prioritise active-file syntax and user-requested queries over optional historical loading or GC, and propagate needed priority to prerequisite work.
Do not busy-spin on blocked dependencies or diagnose a cycle from lack of runnable workers alone.
Specify bounded admission and a fairness/progress policy for required background work; priority classes are not a measured latency guarantee or a reason to starve accepted work indefinitely.
Pressure may reject/defer new optional work or surface an explicit admission failure, but must preserve existing leases and terminal-outcome observation.
Thread-pool size, scheduling quanta, starvation bounds, cancellation check locations and compiler subprocess limits are still implementation/qualification decisions.

#### Service Shutdown and Retained Results

Proposed lifecycle: `open -> quiescing -> draining -> stopped`; shutdown is idempotent and repeated calls observe the same shutdown operation.

1. Enter quiescing at a defined coordinator transition.
Reject new work explicitly, stop new dispatch, and detach source/watch/provider registrations, so no new callback can acquire untracked service state.
Order concurrent submissions as either accepted before this point or rejected after it.
2. Resolve remaining pending tickets/waiters with truthful terminal outcomes and request cancellation of unneeded/running tasks.
Preserve already published outcomes and host-accepted source state; report unfinished persistence/recovery cleanup rather than implying a successful durable flush.
3. Drain worker/provider/store operations and in-flight host delivery under their ownership protocols.
Reject late/duplicate completion tokens without accessing destroyed state; retain a live completion sink and task input leases until every producer is known to have stopped or detached safely.
4. Enter stopped only after the declared worker/callback/resource conditions are met.
Detach scheduler-owned references and release unleased resources; result/world leases already handed to clients remain valid and releasable through a surviving owner, not a destroyed service allocator.

A shutdown wait deadline reports incomplete shutdown if a worker/provider cannot stop; it does not prove that task memory is safe to free.
Never forcibly reclaim borrowed state or report stopped merely because a timeout expired.
An optional isolated compiler backend may require a bounded process-tree stop protocol, but no compiler process is launched by initial shutdown or by persisted artifacts.
Delivery obligations for live registered handles remain observable through the shutdown handle/host drain; the host may explicitly release registrations instead, but shutdown cannot silently discard them.
The final destruction/release API must distinguish scheduler shutdown from the last external result lease and must document who owns any outstanding operations.
Blocking shutdown from inside a dispatch callback cannot wait for that same callback to return; request shutdown there and observe completion after unwinding.

#### Execution Acceptance Trace Drafts

These are future executable concurrent/interleaving cases for C3/C5, not passing E8 model scenarios or evidence that the proposed implementation is race-free.

| Trace | Required assertions |
| --- | --- |
| X1: Register versus complete | Force completion before, during and after waiter attachment/return.  Return an immediate protected result or one live pending registration with one retained terminal outcome; no lost wake or duplicate equivalent task. |
| X2: Cancel versus complete | Race one waiter's cancellation with shared completion.  Exactly one terminal outcome wins for that waiter, the other waiter remains correct, and unpublished/unused payload ownership is released once. |
| X3: Release and slot reuse | Queue a notification/completion, release its registration and reuse the slot for another generation.  Old records cannot reach the new client; an already active delivery retains its backing through return. |
| X4: Reentrant host dispatch | From host dispatch, submit another query, cancel a waiter, release a lease and request shutdown.  No callback runs under internal locks, no recursive delivery corrupts iteration, and shutdown completion does not depend on blocking its own callback. |
| X5: Pressure and delayed delivery | Delay host draining while admitted tasks finish and wake signals coalesce.  Outcomes remain pollable, and each live registration has at most one terminal record; queue/admission pressure never loses accepted work or revokes leases. |
| X6: Priority and external wait | Mix visible-file work, background dependencies and blocked external input.  Required prerequisites make progress under the approved fairness policy, optional work cannot monopolise dispatch, and external waiting is not reported as a cycle. |
| X7: Shutdown racing submission | Order submissions around quiescing, run repeated shutdown, and attempt duplicate/late completions.  Every accepted request gets a truthful observable outcome; new work rejects and preserved result leases remain readable/releasable after stopped. |
| X8: Worker outlives deadline | Hold a worker/provider operation beyond a shutdown wait deadline, then allow it to stop.  Report incomplete shutdown initially, preserve protected inputs/completion sink, and enter stopped only after safe termination without use-after-free or false durable-success status. |

Still open: approval of the execution model, lock ordering, queue/admission limits, callback adapter contract, worker stop/fairness policy, source-provider integration, exact public signatures and real concurrent/platform qualification.
No execution trace is marked passed here, and the scope/performance, implementation and migration approval gates remain open.

### Source Provider and Capture Contract Draft

Drafted 2026-10-20.
**R3 direction approved 2026-10-21; detailed provider/event schemas remain proposed and unimplemented.**
This refines C1/C2/C5 and the core source-event contract; it does not qualify a real editor adapter, an operating-system snapshot facility, or atomic cross-file refactoring.
The proposed initial provider mode captures an explicit finite set of documents, preserving unknown membership rather than pretending the workspace/import closure is already complete.
Provider capability negotiation, host integration and exact identity/event schemas remain specification and approval work.

#### Provider View and Capture Contents

The source provider exposes a workspace/session namespace, an ordered accepted-event frontier, immutable selected revision references and an explicit capability/consistency description.
A provider view distinguishes active overlay bytes, acknowledged disk bytes, confirmed absence and unobserved/unavailable source; it does not derive active selection from the cache's newest artifact.
Capture records retain the provider namespace/frontier, resolver configuration, source-visible context, requested document set, and the selected revision/state for each requested document.
All source bytes needed by a published capture must be owned or immutably leased before it is reported available, including paths/context used by diagnostics and resolution.

| Selected document state | Proposed interpretation |
| --- | --- |
| Present overlay | Exact host-selected immutable buffer revision, regardless of disk existence or equality.  Retain the separate acknowledged disk state for save/reset handling. |
| Present disk | Exact bytes acquired and acknowledged by the provider for this capture, with their context and acquisition/consistency provenance.  Do not infer their current validity from timestamp/size or a historical manifest. |
| Confirmed absent | Absence established by an authoritative provider observation for this document/request/context at the captured frontier.  This may support a negative dependency only within that qualified observation's scope. |
| Unknown/unobserved | The capture has not established this document or resolver-candidate membership.  It is not a missing file, a complete negative lookup, or permission to read the latest disk into the old world. |
| Unavailable | The provider cannot supply required protected bytes/state, for example because a lease expired, access failed or historical capture is unsupported.  Report the reason and incomplete/unavailable outcome explicitly. |

The captured frontier orders provider events; it is not proof that every physical file existed in that state at one instant.
Ordinary sequential filesystem reads do not provide an atomic multi-file snapshot, even when timestamps/stat data appear unchanged.
The provider must declare whether it supplies host-frozen revisions, another qualified immutable snapshot, or merely individually observed disk revisions.
Exact byte hashing certifies the captured bytes, not simultaneous cross-file observation or freedom from an external writer modifying a file during acquisition.
If a required read-consistency guarantee cannot be supplied, return explicit unavailability/incompleteness for that guarantee; metadata rechecks alone must not be advertised as proving it.
The syntax-first service may parse explicitly captured observed bytes without claiming a coherent compiler-equivalent cross-file disk instant or full semantic closure.

#### Initial Capture and Dependency Discovery

1. The host requests a finite document set and required provider capabilities/consistency at an explicit frontier or a newly selected provider view.
Validate namespace, identities, overlay precedence, resolver configuration and admission bounds.
2. Acquire protected exact source/state for that set, without allowing concurrent provider events to rewrite a revision already selected for the capture.
If the provider cannot freeze a required selection, retry a new capture explicitly or report unavailable; do not quietly mix old and new revisions under one claimed frontier.
3. Publish a capture descriptor with its membership/completeness and consistency limits.
Syntax/index tasks operate only over these immutable inputs; release the temporary acquisition state without releasing published leases.
4. On import/load/generated dependency discovery, resolve using the captured context and inspect only candidate membership the provider view can establish.
An unknown candidate set cannot yield a definitive missing-module diagnostic or complete export set.
5. If the provider can supply the same frontier's immutable source/membership, extend through a specified versioned capture/discovery operation without changing established observations.
Otherwise, report the missing capture requirement and request a successor capture/update ticket; an existing query does not implicitly adopt that successor world.

The proposed initial implementation may support only the finite-set path and explicitly report broader semantic discovery unsupported/unavailable.
It need not implement filesystem time travel, eager recursive import enumeration or a full resolver merely to expose syntax snapshots.
Any future lazy discovery must specify how namespace/candidate-set absence is frozen as well as how present file bytes are retained.
Resolver search paths, directory membership, newly created files and changed permissions are observations/dependencies, not incidental I/O invisible to the world model.
A physically identical path reached through a different source-visible request must still undergo the path/context identity validation required by E2/E4.

#### Multi-Document Events and Analysis Publication

A proposed host source transaction names its workspace/session and base frontier, contains explicit per-document base revisions and ordered edits/replacements/rename/absence events, and identifies the requested analysis milestone.
Validate every member's identities/ranges/context and acquire all resulting immutable bytes before committing any member to the provider's accepted selection.
Reject stale bases, conflicting duplicate document operations, ambiguous rename ownership, invalid ranges or admission failure as one rejected transaction; no member becomes an acknowledged partial success.
Initially reject multiple operations on the same logical document unless the transaction grammar defines their ordering unambiguously; the existing sequential ranged-edit convention applies within a single document's edit sequence.

Commit the accepted source transaction at one coordinator transition and frontier; all members become selected together in the provider model.
This is a logical in-memory source-selection transaction, not an atomic filesystem save, editor write operation or persistent-manifest durability guarantee.
If the host provides only unrelated single-document events, publish their actual separate frontiers; do not relabel intermediate states as one atomic change.
Source acceptance and syntax/index readiness are distinct: a later parse/allocation/provider failure does not pretend that the host's accepted edits never happened.
An aggregate analysis milestone is published only when its requested members have valid results or explicitly specified absence/diagnostic states; otherwise the ticket remains pending or terminates with its actual failure/supersession.
The initial `SYNTAX_INDEX` readiness boundary and its relation to per-query availability are specified below; valid partial index coverage is not a missing computation, and unavailable required source is not a diagnostic state that satisfies the boundary.
Do not assemble an aggregate "current" result from whichever per-file parse completed most recently.
Until that milestone exists, an older retained analysis world remains queryable only under its old identity, not relabelled as current accepted source.

Later cross-file refactoring must separately validate the host's current base revisions and apply edits through its authorised transaction protocol.
This draft does not authorise applying edits, writing disk files, or assuming that the host can atomically apply a proposed rename/refactoring.
The adapter must declare its supported atomicity; unsupported application guarantees remain explicit even if analysis capture is coherent.

#### Provider Lifetime, Failure and Diagnostics

Provider leases protect immutable revisions independently of a live editor callback; no syntax task may retain borrowed callback memory after return.
Closing/resetting a buffer changes future selection through an event but does not mutate/release bytes held by an old-world lease.
If the host cannot retain old bytes, the service must copy them before acknowledging the capture or reject that capability; expiry cannot silently turn a valid published lease into a dangling reference.
An unavailable uncaptured revision is distinct from an already published lease being invalidated, which violates the ownership contract.

Acquisition limits, retry/cancellation and shutdown follow the execution contract: external provider calls run outside internal locks, return under captured operation identity, and retain ownership until stopped/detached safely.
Provider failure, permission denial and incomplete capture are service/capability outcomes, not fabricated parse errors or successful empty source.
Expose consistency/completeness and selected identities with results, so the host can decide whether a syntax-only result is sufficient; do not bury a weakened capture guarantee in a cache hit counter.
Path-alias rules, per-document versus workspace-frontier conflict checks, snapshot capability names, retained-provider storage and absolute acquisition bounds remain approval decisions.

#### Source Capture Acceptance Trace Drafts

These are future executable source-provider cases for C1/C2/C5, not tests already run or claims of coherent filesystem snapshots.

| Trace | Required assertions |
| --- | --- |
| V1: Overlay and disk race | Capture an overlay while external disk events arrive, then save/reset through explicit host events.  Captured overlay bytes remain exact, separate disk state advances truthfully, and old-world reads do not change. |
| V2: Unknown versus absent | Request an uncaptured dependency and contrast it with a provider-confirmed absent candidate.  Unknown yields incomplete/unavailable/unsupported as appropriate, never a definitive missing-name/module result. |
| V3: Late discovery | Discover a dependency after a newer provider frontier exists.  Use qualified historical bytes/membership or require an explicit successor capture; no latest bytes are attached to the old query. |
| V4: Disk consistency limit | Mutate files during sequential acquisition and preserve timestamps where possible.  Exact captured bytes/provenance are reported, and no atomic snapshot or stable-read guarantee is inferred from hashes/stat checks alone. |
| V5: Atomic source batch rejection | Submit a multi-document transaction with one stale/invalid member or an ambiguous rename.  Reject all selection changes; a valid replacement transaction can subsequently commit one coherent frontier. |
| V6: Batch analysis ordering | Accept a valid multi-document transaction, complete parsing out of order and fail one required task.  No mixed-revision aggregate milestone is published; accepted source remains truthful and retained prior analysis stays labelled old. |
| V7: Capture lifetime | Close/reset a host buffer and release acquisition callback storage while an old capture is leased.  Published bytes remain exact; an adapter unable to protect them must have copied/rejected before acknowledgement. |
| V8: Provider failure and stop | Race delayed provider completion with permission failure, cancellation and shutdown.  Return truthful outcomes, reject obsolete completion tokens and keep inputs alive until safe stop; never execute source or write editor files. |

Still open: provider schemas/capability negotiation, namespace/path identity, snapshot and resolver-membership mechanism, transaction grammar, host application guarantees, numeric limits and executable adapter qualification.
No source-capture trace is marked passed here; policy/scope/performance approvals, production implementation and the migration-plan gate remain open.

### Source Update and Query Interface Schema Draft

Drafted 2026-10-20.
**Proposed interface schema, not approved API or implemented code.**
The fifteen-operation interface was approved as the specification baseline on 2026-10-21, subject to exact schemas and API review, not production implementation or migration.
This makes the source/update/query portion concrete under the approved initial scope and R3-R5 directions; R2/R6-R8, exact ABI, limits, persistence wire grammar and implementation authorisation remain open.
The notation below is a logical tagged-record schema, not Jai source or a persistent memory layout.
All records carry an interface schema version; unknown versions/tags are rejected before accepting work, never interpreted as an empty successful operation.

#### Record Shapes and Value Types

| Type | Proposed v1 shape and meaning |
| --- | --- |
| `InterfaceVersion` | Exact supported schema identifier.  Changes to tags, field meaning or ownership require explicit compatibility/version rules. |
| `SessionID`, `WorkspaceID`, `DocumentID`, `ProviderRevision`, `ProviderFrontier`, `SourceRevision`, `ContextID` | Distinct opaque identity types, never interchangeable strings or allocation addresses.  Use the canonical-key and authority rules below; adapter allocation/path binding remains subject to review.  Provider revisions/frontiers are namespace-scoped equality/order tokens, not wall-clock timestamps. |
| `Handle` | `{session: SessionID, kind: HandleKind, slot: u64, generation: u64}`.  Kinds: `SESSION`, `WORLD`, `TICKET`, `WAITER`, `RESULT`, `SHUTDOWN`.  Validate session/kind/generation on every operation; retire a slot before generation wrap.  A handle identifies one owning registration, not a serialisable world/declaration identity. |
| `SessionOptions` | `{version, workspace, provider_namespace, provider_capabilities, context, requested_limits, store_policy}`.  The host explicitly supplies required configuration/policy or requests a documented negotiated value; unspecified defaults are not silently chosen by this draft. |
| `SessionDescription` | `{session_identity, workspace, provider_namespace, lifecycle, accepted_frontier, tracked_document_states, capabilities, consistency, effective_limits, store_status}`.  Return one coherent caller-owned value snapshot, not mutable borrowed coordinator storage.  It reports source selection/capabilities, not a published analysis world or atomic filesystem view. |
| `SourceInput` | Tagged `INLINE_BYTES {bytes}` or `PROVIDER_LEASE {provider_identity, provider_revision, immutable_lease}`.  Inline bytes are borrowed only during submission; acceptance copies them or acquires an independent immutable lease.  The provider lease must be retained successfully before acknowledgement. |
| `ExpectedProviderState` | Tagged `UNTRACKED` or `REVISION {provider_revision}`.  `UNTRACKED` matches only a document with no accepted provider state in this session; it is not confirmed absence and never bypasses a tracked revision conflict. |
| `DiskObservation` | Tagged `PRESENT {source: SourceInput, source_revision, context: ContextID, consistency}` or `ABSENT {provider_revision, context, observation_provenance}`.  Neither unknown membership nor permission denial is `ABSENT`.  Check revision claims against captured inputs/provider authority; do not trust an arbitrary digest field. |
| `RangeEdit` | `{start_byte: u64, end_byte: u64, replacement: bytes}` with half-open endpoints into the current intermediate document bytes.  The enclosing event names the initial base revision; apply edits sequentially, checking ranges/overflow after each, then accept or reject the whole batch. |
| `DocumentEvent` | `{document: DocumentID, expected_provider_state: ExpectedProviderState, source_context: ContextID, event: EventPayload}`.  All required base/host-confirmation tokens are explicit, not inferred from timestamps or cache contents.  A first `SET_OVERLAY`, `OBSERVE_DISK` or host-confirmed `RESTORE_OVERLAY` may use `UNTRACKED`; editing, saving or resetting requires compatible tracked base state. |
| `SourceBatch` | `{version, workspace: WorkspaceID, session: SessionID, expected_frontier: ProviderFrontier, events: []DocumentEvent, milestone: SYNTAX_INDEX}`.  Initially require one event per logical document; a range-edit event may contain its sequential edit list.  Reject an empty batch or unsupported milestone explicitly. |
| `AnalysisRequest` | `{version, expected_frontier, documents: []DocumentID, milestone: SYNTAX_INDEX}`.  Request analysis of a nonempty, duplicate-free set of already tracked selected revisions under the membership rules below, without changing provider source state.  Unknown members or incompatible consistency reject explicitly; no hidden provider/disk read is implied. |
| `WorldDescription` | `{world_identity, workspace, provider_frontier, context, members: []SelectedDocument, membership_completeness, consistency}`.  `SelectedDocument` carries document/context and tagged present source revision, confirmed absence, unknown or unavailable with reason.  The `WORLD` handle protects immutable description/source/index backing. |
| `QueryRequest` | `{version, world: Handle(WORLD), document: DocumentID, kind: SYNTAX_SNAPSHOT | SYNTAX_DIAGNOSTICS | SYNTAX_DECLARATION_INDEX | SEMANTIC_QUERY | COMPILER_EVALUATION}`.  The first three request whole-document syntax-derived payloads without service-side filtering as specified below; the last two are known reserved capability tags returning `UNSUPPORTED` before task creation in this initial slice.  Unknown tags or invalid handles remain operation errors, not capability results. |
| `ResultDescription` | `{result_identity, world_identity, document, source_revision_if_present, context, kind, completeness, diagnostics_status, payload}`.  `diagnostics_status` is the protected parse summary specified below, independent of payload coverage and diagnostic presentation availability.  `RESULT` owns access to its immutable payload and source-map backing; parse diagnostics do not turn usable syntax into a service failure. |
| `CompletionRecord` | `{registration: Handle(WAITER), operation_identity, terminal_kind, world_identity_if_known}`.  A host-drained record is informational, not a payload lease.  Use its still-live registration to inspect/acquire the protected result; stale/released generations reject. |

Counts, bytes, decoded sizes and accepted registrations must have concrete checked limits before implementing this schema.
The fixed-width handle fields do not bound total allocations or authorise wrapping IDs; no client may fabricate a valid registration by copying a logical identity into a slot.

##### Analysis Membership, Duplicates and Ordering

Proposed refinement of the existing document arrays, not filesystem alias discovery or permission to reorder source events.
`AnalysisRequest.documents` has set semantics: require at least one member, reject repeated equal `DocumentID` values even when their requested state would agree, and validate every member/session/provider binding before accepting the request.
Compare the complete registered identity descriptors under the canonical rules below, not display paths, source hashes or allocation handles.
Distinct registered aliases remain distinct documents unless the provider's already admitted policy gives them the same logical identity.
Do not merge two documents merely because their source bytes match; their selected contexts and membership states remain independent.

For canonical analysis-membership comparison/description, order distinct members lexicographically by the unsigned bytes of the complete canonical `DocumentID` key, with a shorter prefix first.
Do not sort only digests or use locale/path collation.
An admitted world's `members` array uses that order for its captured member set; requested milestone membership is compared as a set, not inferred from array position or expanded to every captured member.
This representation order is not provider-event time, worker priority, completion order or language import/load order.
Swapping an analysis request's distinct input members does not change its logical membership or per-document inputs.
Repeated requests still receive their own observable operation/ticket identities under the existing contracts; equivalent membership permits sharing compatible work, not silently returning another caller's registration.

`SourceBatch.events` remains an ordered transaction with at most one event per logical document in this initial grammar.
Reject duplicate equal document identities there as already required; do not sort its events using the analysis-membership rule.
Sequential edits inside one range-edit event retain their intermediate-source order.
Diagnostic emission, declaration-event order, related messages and source-visible language lists also retain their separately specified ordering.
Any canonical captured member table is built from the validated transaction's resulting selection, not by reordering or replaying the transaction differently.

An invalid/duplicate/foreign member rejects the whole analysis request before task/ticket acceptance; it neither changes the provider frontier nor publishes the valid subset as a successful aggregate.
No numeric member limit is chosen here: enforce the separately reviewed admission bounds before allocating/sorting, and report their actual admission outcome.

The discriminating future cases compare `[A, B]` with `[B, A]` at one frontier and reject `[A, A]`: the first pair has equal logical membership but distinct caller registrations, while the duplicate request admits no partial work.
Additional independent cases cover equal source bytes in distinct documents, provider-qualified aliases, digest-collision safeguards, foreign identities, worker completion permutations and sequential source edits whose order must not change.
Assert exact canonical member order, requested sets, identity separation and unchanged source state on rejection after implementation authorisation.
This draft selects no path-alias policy or new shared-task key format.

#### Canonical Identity and Payload Refinement

Proposed 2026-10-21 under the approved specification baseline; not final API, persistent wire grammar or implementation approval.
The following defines equality and hash-input bytes independently of Jai struct padding, native pointers and text-file formatting.
Adapter namespace provisioning, complete context fields and exact syntax-node variants still require review; no store defaults or resource budgets are selected here.

Define `B(x)` as an unsigned 64-bit little-endian byte count followed by exactly the bytes of `x`.
Define `K(tag, fields)` as `B(ASCII("jai-cache-key"))`, unsigned 32-bit little-endian key-schema version `1`, `B(ASCII(tag))`, unsigned 64-bit little-endian field count, then each field encoded with `B` in declared order.
Nested keys are complete `K` byte sequences used as fields, not unframed concatenations; numeric fields have explicitly declared widths and little-endian encoding.
Lengths must be representable and checked before allocation/addition; a 64-bit length is not permission to allocate that much memory.
Hashing uses SHA-256 over the complete key bytes, but the key descriptor remains available for equality/validation; a digest alone is not a logical identity or proof of source authority.
This is a canonical fingerprint input, not a replacement for the proposed versioned text persistence format.

| Value | Proposed canonical identity and authority |
| --- | --- |
| Namespace token | Nonempty opaque bytes issued by its responsible owner, compared byte-for-byte without Unicode normalisation, case folding or separator rewriting.  The adapter must bind the token to one authority/configuration and never reassign it to a different one while references/recovery records can survive.  An unverified binding is rejected or assigned a fresh namespace, not guessed from a display path. |
| `WorkspaceID` | `K("workspace", [host_namespace, workspace_token])`.  The host decides whether a reopened workspace has the same identity; cache discovery cannot choose it.  Shared project paths do not implicitly merge separate workspaces. |
| `DocumentID` | `K("document", [provider_namespace, document_policy_version, provider_document_key])`.  The provider registers the resolved absolute-path binding and its alias/case/link policy; the service does not independently lowercase or resolve it.  Source-visible path/directory spelling remains separate context input.  Deletion/reappearance preserves or changes this key only according to the declared provider policy. |
| `SessionID` | `K("session", [service_incarnation_namespace, session_token])`, issued by the service.  The incarnation namespace is never reassigned while old references/records can survive; session tokens are not reused within it.  Neither is derived from workspace/path/content; owner routing is validated before slot lookup.  Restart creates a new incarnation and rejects every old handle even if persisted workspace/document keys match.  The allocation mechanism still requires review. |
| `ProviderRevision` | `K("provider-revision", [provider_namespace, session_identity, document_identity, provider_state_token])`.  A token identifies one accepted combined disk/overlay state, not just selected bytes.  The provider cannot reuse it for a different state; rejected batches do not install a new token. |
| `ProviderFrontier` | `K("provider-frontier", [provider_namespace, session_identity, frontier_token])`.  The coordinator records the accepted-event order; token bytes/digests are not lexicographic clocks.  Retry analysis leaves the frontier unchanged, and a rejected transaction creates no accepted successor. |
| `SourceRevision` | `K("source", [source_key_version_u32, byte_count_u64, SHA256(exact_source_bytes)])`, with source-key version `1`.  Exact bytes remain the authority; collision ambiguity rejects affected reuse rather than merging different sources.  Equal empty/present sources can share this value across documents, but confirmed absence has no source revision.  No BOM stripping, newline conversion, decoding or trailing-NUL insertion is part of identity. |
| `ContextID` | `K("context", [context_schema_identifier, canonical_context_descriptor])`.  The versioned descriptor includes syntax configuration/parser schema and all source-visible path/resolution inputs used by that result; semantic extension fields must include the section 3/semantic-contract inputs before semantic reuse is supported.  An opaque host label alone cannot establish equivalent context. |
| World/result/operation identity | Service-issued, session-scoped, typed nonreused tokens, distinct from registration handles and from content keys.  Repeated analysis may produce a distinct world/result identity at the same frontier.  Equality of those tokens never authorises restoring handles from persistence. |

For `ContextID`, descriptor records use named, versioned fields in schema-declared order; nested sequences preserve order unless that field's schema explicitly defines set semantics and canonical sorting.
This service configuration identity is not Jai's `#Context` type.
A future semantic descriptor containing the completed language context must use section 6.3's ordered-base/unordered-additions rule, not encode compiler encounter order as type identity.
Reject duplicate/unknown fields and missing required fields for the selected schema rather than dropping them during hashing.
The syntax-only descriptor registry below is proposed for API review; until its producer/adapter bindings are validated, an adapter cannot claim cross-session context equivalence or persistent derived-result reuse from this recipe alone.
Opaque provider path keys need not be UTF-8; adapters retain native source-visible spelling without lossy conversion and define its descriptor encoding explicitly.
Handle transport, if later added, must encode its fields explicitly and validate the live owner/registration; it is never a persistent identity record.

##### Syntax Context Registry and Adapter Bindings

Proposed 2026-10-21, not approved adapter/API behaviour.
The initial context schema identifier is ASCII `jai-cache-syntax-context/1`.
Its descriptor is `K("syntax-context-descriptor", fields)` with exactly the following ten fields in table order; each field is itself `K(field_name, values)`.
Field names/tags/schema identifiers are exact ASCII; booleans are one byte `0` or `1`, and version numbers explicitly marked `u32` are unsigned little-endian.
There are no omitted/default fields or generic extension maps in this schema.
Unknown schemas, duplicate/reordered fields, invalid booleans and missing required values reject before accepting a context.
The registry is closed for the syntax-first scope, not an assertion that these fields suffice for future semantic/evaluator contexts.

| Field name | Ordered values and authority |
| --- | --- |
| `producer` | Service-verified producer namespace, immutable parser implementation/build identity, compiler SDK/layout identity, lexer implementation identity, and the syntax-payload adapter build identity plus canonical capability binding specified below, in that order.  These identify the implementation actually used, not an unverified client-supplied version label.  A change conservatively misses even if output compatibility is suspected.  This refines the still-unimplemented context-registry draft; it does not reinterpret an existing qualified v1 context. |
| `syntax_schemas` | Token, node, recovery and declaration-index schema identifiers, in that order.  Each resolves to an exact supported field/variant registry; an unknown registry cannot be accepted merely because its identifier hashes successfully. |
| `parser_parameters` | `ENABLE_TRIVIA`, `EVALUATE_STRING_ESCAPES`, `INTERN_IDENTIFIERS`, `USE_SIMD`, `TRACK_AST_REUSE`, in the declaration order of the current module parameters, each as a boolean.  The full-featured initial profile requires `ENABLE_TRIVIA = true`; reject a false value at profile admission rather than supporting a second byte-mapping path.  All five remain conservatively keyed, including instrumentation/implementation choices; removing a field requires a new schema and equivalence evidence. |
| `parse_profile` | Registered grammar/language profile identifier and recovery-policy identifier.  V1 supports only explicitly implemented profiles; no unkeyed runtime parser option or hidden host default may affect results.  A newly exposed parse option requires a schema revision before reuse. |
| `diagnostic_profile` | Diagnostic schema identifier, registered message/severity-policy identifier and presentation-language identifier.  The producer validates the selected policy; changing diagnostic text/order/policy cannot reuse a result under an unchanged profile.  An unsupported localisation is rejected, not silently substituted. |
| `visible_filename` | One `PathValue` preserving the exact source-visible filename spelling supplied for this occurrence, including retained dot/parent segments and alias spelling.  It is not inferred from a canonical physical key. |
| `visible_directory` | One `PathValue` preserving the effective source-visible directory independently of filename.  This records context for `#filepath`/location-sensitive results without evaluating those constructs as context-free literals. |
| `relative_base` | One `PathValue` for the explicit absolute base used for relative-request interpretation.  No later dependence on process working directory is permitted. |
| `resolver_binding` | `K("NO_RESOLUTION", [])` for an initial syntax-only capture that does not resolve imports/loads, or `K("RESOLVER_CONFIG", [resolver_schema, canonical_registered_descriptor])` only for an explicitly supported resolver schema.  V1 baseline requires only `NO_RESOLUTION`; it is not an empty/complete search result.  Authored import/load requests remain syntax, not resolved membership. |
| `semantic_extension` | Exactly `K("UNSUPPORTED", [])` in this schema.  Module/program arguments, target/layout facts and evaluator policies are not silently ignored inputs to semantic reuse; requests requiring them return the reserved unsupported capability outcome.  A supported semantic schema must enumerate those inputs separately. |

`PathValue` is `K("path", [encoding_tag, code_units])`, where `encoding_tag` is ASCII `WINDOWS_UTF16LE` or `POSIX_BYTES`.
Windows code units are the exact little-endian 16-bit units without a terminator, BOM insertion or Unicode normalisation; their byte count must be even.
POSIX bytes are preserved without UTF-8 decoding.
Reject embedded NUL code units/bytes and unsupported host encodings; the tag is part of equality, not permission to treat a foreign path as locally openable.
The provider validates absolute-path/base requirements using its registered platform policy, while source-visible filename/directory spellings are retained without canonical rewriting.
Empty required path values are invalid; a future anonymous/virtual-document context needs an explicit alternative schema rather than an invented disk path.
Path encodings describe observed inputs, not proof of filesystem equivalence, stable file identity, permission or atomic capture.

Adapter binding is admission metadata for the existing session/source operations, not a sixteenth public operation:

1. `OpenSession` binds the host/workspace/provider namespaces to an owned descriptor `{adapter_schema, authority_identity, document_policy_version:u32, path_platform, case_alias_link_policy, reappearance_policy, consistency_capabilities, lease_capabilities}`.
Validate supported versions and explicit capability values; no policy is inferred from the current machine's filesystem or a cache manifest.
The adapter-schema field registry and platform-policy alternatives require separate review before an adapter is qualified.
2. For each first accepted document, bind its provider key to its resolved absolute-path record and that policy.
The provider attests the binding; the service checks namespace/policy/version compatibility and internal consistency before owning it with the accepted state.
Source-visible occurrence paths come from the context, not this canonical record.
Conflicting claims for an existing key reject the entire batch rather than mutating an old world's identity.
3. Default to no unproven alias merge: distinct registered keys remain distinct even if filesystem probes or bytes match.
A declared alias policy may map requests to one physical document only after the adapter's required validation; occurrence-specific contexts still remain separate.
Changed case/link/reappearance policy requires a new policy version/namespace and explicit successor capture, never reinterpretation of retained worlds.
4. Across restart, reuse workspace/document bindings only after the host/provider re-establishes the same authority and policy.
A manifest is a candidate, not that confirmation.
If continuity cannot be established, issue fresh namespace bindings and miss derived reuse; recovery remains a host-confirmed candidate and old live handles remain invalid.
5. Before batch acknowledgement, validate every supplied `ContextID` against an owned canonical descriptor, actual producer configuration and the corresponding document/occurrence binding.
Recompute the key, reject mismatches/unknown profiles, acquire all descriptors/path/source leases, then commit with the source batch.
Failed binding admission leaves both document selection and accepted frontier unchanged.
Session configuration supplies the registered producer/profile policy; per-document contexts supply occurrence-specific path inputs, not a mutable session-wide filename.

Consistency/lease capabilities describe acquisition guarantees but are not syntax-content identity fields: keep their captured provenance in world/provider records and validate query requirements separately.
Likewise, queue priority, memory/store budgets, save/overlay selection and delivery timing are not hidden parser options.
Pressure cancellation/failure cannot be cached as a successful complete syntax result; any supported output-limiting policy that changes payload contents must be keyed explicitly or return a distinct incomplete outcome.
Do not perform filesystem I/O merely to compare context descriptors, or compare arbitrary textual formatting of a descriptor instead of the canonical fields.

Registry/binding review cases to implement later: toggle each of the five module parameters; change producer/schema/profile; preserve bytes while changing visible alias/base/encoding; reject unknown fields, invalid boolean/path encodings and conflicting document bindings; restart with confirmed versus unconfirmed namespace continuity; reject one bad context in a multi-document batch with no partial admission.
These refine C1/C2, T2/T5 and V1/V4/V5 without qualifying any adapter or executing semantic evaluation.
Exact payload variant registries, policy alternatives, access signatures and admission bounds remain open; R2/R6-R8 and implementation/migration authorisation are unchanged.

All three supported query payloads use a versioned envelope `{payload_schema, world_identity, document, source_revision, context, completeness, data}`.
Identity bindings must equal the `ResultDescription` and the selected present member of the queried world; `completeness` must agree with the result description under the kind-specific rules below.
Missing/unknown/unavailable members produce their explicit query outcome rather than a fabricated empty payload.
An empty present file can produce available empty diagnostics/index results, but a syntax snapshot still represents that exact empty source revision.
Envelope access and all nested views borrow from the owning `RESULT`; an independent copy or retained result is required to outlive it.

| Payload | Required logical data and limits of meaning under the selected schema |
| --- | --- |
| Common span | `{document, source_revision, start_byte:u64, end_byte:u64}` with `0 <= start_byte <= end_byte <= exact_source.count`.  Zero-width insertion/recovery spans are permitted.  A span from another revision is not remapped implicitly; generated/unlocated items require an explicit tagged origin, not an out-of-range sentinel. |
| `SYNTAX_SNAPSHOT` | Exact owned source bytes, syntax-schema identifier, token sequence, root/node records and recovery information needed for C1 comparison.  Node references are snapshot-local IDs resolved only within this envelope, not pointers, declaration identities or global IDs.  The schema must enumerate node/token variants and every observable child/list/span field before API approval; exposing today's mutable `Parser_Node` memory is not this contract. |
| `SYNTAX_DIAGNOSTICS` | Ordered records under `jai-cache-syntax-diagnostics/1` as specified below, including code, severity, origins/messages, token details and recovery action.  Preserve parser emission order; do not deduplicate by message or location.  A malformed source diagnostic is an available syntax result, not a service failure. |
| `SYNTAX_DECLARATION_INDEX` | `{coverage, entries: []IndexEntry, shared_regions: []SharedRegion}` under the draft `jai-cache-syntax-declaration-index/2` contract below.  Entries follow declaration-event/binding-group order, not a global span sort; entry/region/node IDs occupy distinct result-local domains.  Names separate exact source spelling from producer values; visibility records same-list provenance, not resolved accessibility.  Recovery and coverage retain explicit uncertainty.  Repeated/anonymous/recovered declarations are not merged by name; this index promises neither nominal `DeclarationID` continuity nor semantic lookup/completeness. |

Messages are strict UTF-8 presentation text.
Source bytes and spelled-name bytes preserve exact parser input slices; producer-name bytes instead preserve the exact producer value, which can differ from the source spelling.
Neither byte domain is required to be valid UTF-8 for this interface.
Any line/column or editor UTF-16 conversion belongs to an explicit adapter mapping for the same source revision; byte ranges never silently become character indices.
The existing syntax payload must preserve malformed/incomplete-source observations under C1 even where a diagnostic/index presentation needs an explicit unavailable field.
The logical optional/tag records below are drafts for review, not an implemented wire format; the exhaustive snapshot node/field schema remains open.

##### Query Schema Selection and No-Fallback Binding

Proposed clarification of the existing interface version, context registries and payload envelope; no per-query schema selector is added.
`QueryRequest.version` selects the operation/record contract, not an instruction to choose the newest payload schema.
The queried world's selected document context fixes the producer/adapter, registry tuple and profiles used for its syntax results.
Session capability descriptions may advertise several supported schemas, but admission must bind one exact compatible tuple to each context before work is accepted.
An advertised alternative is not an implicit fallback for a retained world.

| Query kind | Authority for the envelope's `payload_schema` |
| --- | --- |
| `SYNTAX_SNAPSHOT` | The exact registered snapshot-envelope mapping for the context's node/token/recovery schemas and parse profile.  Its payload-schema identifier and field mappings must be registered explicitly; do not guess an envelope schema from a node-layout name or concatenate version strings. |
| `SYNTAX_DIAGNOSTICS` | The diagnostic schema selected by `diagnostic_profile`, with its bound severity/message/language policy and compatible token/origin mappings. |
| `SYNTAX_DECLARATION_INDEX` | The declaration-index schema selected by `syntax_schemas`, with the context's exact adapter/registry capability binding. |

Validate the supported cross-schema combination as a tuple, not only each identifier in isolation.
For example, an index node reference must resolve under the bound node registry, and an inserted-token observation must use the bound token/recovery mapping.
Independent schema families need not have matching version numbers: diagnostic/1 and declaration-index/2 can coexist only when their complete registered combination is supported, not because suffixes agree or disagree.
The returned envelope schema, actual payload fields and kind-specific completeness must agree with that binding and the result description's protected payload.
Reject contradictory/unknown encodings rather than skipping fields until a familiar shape remains.

If the service lacks the query implementation for the bound schema, return the existing unsupported outcome before creating work; do not serve a different schema, an empty payload or an indefinite waiter.
An admitted implementation's runtime conversion/resource failure retains its actual failure outcome, not a second attempt under a weaker unkeyed profile.
Stored artifacts from another schema are misses under the existing validation rules, not permission to reinterpret old fields.
Selecting another schema/profile requires an explicitly admitted context and analysis result; do not rewrite a retained world's tuple or relabel an old payload under the new schema.
Previously retained results remain readable under their original registered access contract.
These rules do not approve a legacy schema converter, mixed-version compatibility matrix or migration.
Such support requires its own exact registered mapping and qualification; a version-shaped identifier alone proves nothing.

The discriminating future case queries declaration-index/2 in a world whose diagnostic profile uses diagnostic/1: return each exact admitted schema, and reject an unsupported tuple without guessing a fallback.
Additional independent cases cover interface-versus-payload version confusion, changed advertised session capabilities with a retained old world, mismatched token/node/recovery registries, unknown envelope fields and a stored legacy index with unchanged source bytes.
Assert exact context/envelope bindings, unsupported-versus-failed outcomes and retained old-result access after implementation authorisation.
Exhaustive snapshot schema registration, compatibility review and public accessor signatures remain open.

##### Syntax-Index Milestone and Per-Query Readiness

Proposed refinement of the existing `SYNTAX_INDEX` ticket milestone, not a new milestone tag or promise of semantic/durable completion.
Admission must establish that the registered profile implements the required protected syntax/index contract.
A wholly unsupported index implementation cannot be admitted and later reported as an empty successful milestone; unsupported admission follows the existing rejection rules before source acceptance.
Once source acceptance succeeds, subsequent analysis failure leaves that accepted frontier/source state intact under the existing retry contract.

The readiness boundary applies to the ticket's requested member set, not every possible workspace/import member or every older document represented in a world.
For each requested present member, protect and validate its exact selected source/context, published syntax/diagnostic observations, diagnostic-status summary and declaration index, including backing references, coverage and structured reasons.
For a requested confirmed-absent member, retain the authoritative captured absence explicitly instead of parsing an empty file or manufacturing an empty index.
Later syntax queries for it return the existing absent-source outcome.
Unknown/unavailable required members, an unfinished required parse/index task or a service/conversion failure in required backing do not satisfy this boundary.
Preserve pending or the actual terminal failure/supersession outcome, not a mixed-revision published world.

A valid `PARTIAL_SYNTAX_TRAVERSAL` index satisfies readiness with its explicit gaps.
An `INCOMPLETE`, `RECOVERED` or safely representable `FATAL` parse can also satisfy readiness; none implies service failure or complete semantic knowledge by itself.
Publish the aggregate world identity, requested member bindings and achieved milestone atomically only after all required members satisfy their respective present/absent rules.
No early member completion may relabel an older aggregate world current.
Required observations remain protected by the published world's existing ownership contract.
Do not mark a ticket published while leaving its required index computation to be started by the first query.

Milestone publication need not preallocate caller `RESULT` registrations or preconvert every public payload presentation.
A subsequent supported query may still be pending for result packaging/conversion, or fail its own allocation/presentation step, without undoing a valid published world.
Such work uses only the published member's immutable backing/context; it cannot substitute a fresh parse of newer source, silently fill a retained partial index with another adapter's mappings or change its diagnostic summary.
If no extra work is needed and result protection can be acquired, the query returns immediately under the existing available-or-register-waiter rule.
Query cancellation releases only that query's obligations, not the published milestone or another consumer's backing.
Persistence, host notification dispatch and optional semantic/evaluator work remain outside this readiness boundary.
In particular, a failed optional cache write does not make syntax/index publication falsely pending or durable.

The discriminating future case finishes two requested documents out of order, one with a valid partial index: publish only after both required indices/backing are valid, preserving partial coverage, then allow independently delayed query packaging without changing that world.
Additional independent cases cover confirmed absence versus unknown source, required conversion/allocation failure after source acceptance, unsupported milestone admission, malformed-source parse statuses, query cancellation and optional diagnostic-presentation/store failures after publication.
Assert exact ticket/query outcomes, requested-member bindings, immutable coverage/summaries and absence of deferred required index work after implementation authorisation.
Scheduling, retention bounds, API signatures and real concurrent qualification remain open.

##### Whole-Document Queries and Caller-Side Selections

Proposed clarification of the current `QueryRequest`, not a range-query, completion, lookup or access-filtering API.
Each supported syntax query covers the selected present document/revision in the explicit world under its bound profile/schema.
It does not enumerate the workspace or follow imports merely because the world contains other documents.
The initial request has no name/prefix/range, container, visibility, diagnostic-severity or result-count filter.
Unknown request fields must not be silently accepted as honoured filters; unsupported versions/invalid request shapes retain their explicit admission errors.
Cursor position, current editor selection and UI visibility are not hidden query inputs.
Existing priority may affect scheduling, but never which declarations/diagnostics are present in a successful payload.

A host can derive a display selection from the owned whole-document result.
Such a selection is a view of that result, not another `jai-cache-syntax-declaration-index/2` payload with a newly asserted completeness value.
Preserve original entry/region/node IDs and parent/binding associations, and retain access to omitted ancestors/regions through the original protected result.
Do not densely renumber a filtered list while leaving references in the old namespace.
If serialising or independently owning a transformed index is later required, define its schema, reference remapping/closure and coverage rules explicitly; the original full-result contract does not grant that conversion automatically.
Display filtering neither clears partial reasons nor establishes subrange completeness.
No visible match remains no proof of absence in a partial index, and lexical name matches are not resolved bindings or accessibility decisions even with complete syntax traversal.

Do not implement count limits by returning a successful arbitrary prefix, or by labelling pressure-truncated output an ordinary observation gap.
Resource/admission failures and any future output-limiting profile retain the earlier explicit-outcome/context requirements.
Likewise, hiding non-exported-looking entries or conditionally inactive-looking branches is a caller presentation choice, not a service-side semantic filter; the source-provenance tags and both static branches remain in the original payload.
A later service-side filter needs separately reviewed request/schema/version and dependency/identity rules before it can affect shared-task equality or cached output.
No such filter or default matching/normalisation policy is approved here.

The discriminating future case issues the same world/document/kind request from two callers with different editor selections: both receive the same bound logical whole-document contents, independent of their display selections.
Additional independent cases cover repeated names, nested/shared-region entries, partial reasons outside a displayed range, hidden branches/non-exported syntax, attempted unknown filter fields and output-pressure truncation.
Assert full payload contents, unchanged IDs/references/coverage and explicit invalid-request/resource outcomes after implementation authorisation.
This draft does not implement host UI filtering or extend the fifteen-operation interface.

##### Derived Payload Backing and Node Reference Access

Proposed ownership/access refinement of the existing `RESULT` and payload envelope; no extra service operation or public snapshot handle is introduced.
Every node/token/recovery reference in a diagnostic or declaration-index payload resolves against one immutable protected syntax backing associated with that result.
Source/context equality alone does not identify its node-numbering namespace.
The derived `RESULT` must protect the transitive backing needed to interpret its references, exact source slices, producer-name bytes and diagnostic observations.
Acquiring it cannot require the caller to keep a separate `WORLD` or `SYNTAX_SNAPSHOT` query result alive.
Releasing the producer/parser, another result or the originating world registration cannot invalidate an independently retained derived result.
Existing shutdown and final-lease rules still apply.

Provide borrowed access to the referenced backing records through the result's payload access contract, with checked kind/domain/range validation.
A public full-snapshot query is not a prerequisite for resolving a supported index node or coverage-reason subject.
This borrowed view does not claim that every backing record is an index declaration or that every query kind is implemented.
Exact accessor signatures and the backing node/field schema remain required API-review work.
Do not resolve an index node ID against whichever snapshot query most recently completed.
A separately acquired snapshot result may use a different graph/numbering namespace even when document, source revision and context agree.
Only an explicit validated association can establish shared backing internally; it does not make bare numeric IDs portable between result envelopes or relax the result-local reference contract.

Retaining a result preserves its own reference namespace.
An independent deep copy must include all referenced backing or explicitly translate every affected reference into the copy's owned namespace; copying only entry arrays does not preserve valid node/source access.
Entry IDs, region IDs, snapshot node IDs and producer diagnostic/recovery indices remain distinct domains.
Invalid/cross-backing references reject validation rather than triggering a current-world lookup, lazy disk read or best-effort pointer dereference.
Backing sharing and deduplication are implementation choices only after these ownership/reference guarantees hold; this draft selects no new identity encoding, memory layout or retention budget.

The discriminating future case retains only an index result, releases the world/producer/separate snapshot result, then resolves every entry, region and reason subject and reads its source/name bytes.
Additional independent cases cover different node numbering in separately acquired results, released registrations with reused slots, independently copied payloads, diagnostics/recovery backing and intentionally cross-wired reference domains.
Assert exact records and byte lifetimes plus rejection of invalid references after implementation authorisation; no executable accessor or backing resolver is supplied here.

##### Result Diagnostic Status Summary

Proposed definition of the existing `ResultDescription.diagnostics_status`, shared by the three syntax query kinds rather than inferred from each query's displayed records.
Its logical shape is `{parse_status, error_count:u64, warning_count:u64}`.
`parse_status` is the protected producer's `COMPLETE | INCOMPLETE | RECOVERED | FATAL`; counts include every emitted diagnostic of the corresponding severity in that same parse, before any host display selection.
Count each diagnostic once, including duplicate messages/locations; related-information records are not additional diagnostics.
Counts must be checked, and their sum must equal the protected diagnostic-record count.
Unknown severities, overflow or mismatched observations reject conversion rather than producing a guessed summary.

For results derived from the same protected parse, summary values agree regardless of query kind.
A declaration index's partial reasons are not source diagnostics and do not increase these counts; cache/provider/service faults retain their separate reporting channels.
For an available diagnostic payload, counts must also equal its records grouped by severity, and the summary's parse status must equal `data.parse_status`.
The summary preserves the producer's status rather than recomputing it from counts.
Zero errors does not imply `COMPLETE`, and an incomplete/recovered parse is not a service failure merely because its count is nonzero.

Counts describe emitted observations, not diagnostic text conversion.
A safely owned snapshot/index may retain this summary even when a separate diagnostic query fails lossless message conversion; a summary is not a substitute for that failed query's payload or a claim of complete diagnostic presentation.
Conversely, unavailable summary evidence must not be encoded as zero counts or a fabricated `COMPLETE` status.
Available syntax results require a validated summary under this initial description contract; otherwise return the existing appropriate unsupported/conversion/failure outcome.
The summary and payload are immutable under the result lease.
Newer parses, clearing a UI list or a cache warning cannot rewrite a retained result's counts/status.

The discriminating future case has a partial index with zero emitted diagnostics: report partial coverage independently of the actual producer status and zero counts, without manufacturing a language error for the index gap.
Additional independent cases cover duplicate diagnostics, related messages, mixed severities, incomplete-source status, lossless-message conversion failure, inconsistent counts/status across query kinds and checked-count failure.
Assert exact summary/payload agreement and separate failure channels after implementation authorisation.
This draft defines neither a severity-filtered service query nor a compiler-validity summary.

##### Envelope Completeness and Query Availability

Proposed logical refinement of the existing envelope and `ResultDescription`, not an additional operation or a production publication mechanism.
For these three syntax query kinds, `completeness` is the closed union `EXACT_SYNTAX_CAPTURE | COMPLETE_DIAGNOSTIC_OBSERVATION | DECLARATION_INDEX_COVERAGE {coverage}`.
Select exactly the arm registered for the result's query kind and payload schema; reject unknown or wrong-kind arms rather than treating them as a generic complete/partial boolean.

| Query kind | Required completeness value and meaning |
| --- | --- |
| `SYNTAX_SNAPSHOT` | `EXACT_SYNTAX_CAPTURE`: all required source/token/node/recovery observations of this protected parse are preserved under the admitted snapshot schema.  It does not assert a successful parse, complete language coverage or semantic closure. |
| `SYNTAX_DIAGNOSTICS` | `COMPLETE_DIAGNOSTIC_OBSERVATION`: all emitted diagnostics of this protected parse are represented in emission order under the diagnostic schema, including explicit unlocated origins where required.  It does not assert that the parser detected every language error or that the source is valid. |
| `SYNTAX_DECLARATION_INDEX` | `DECLARATION_INDEX_COVERAGE {coverage}`: the enclosed value is exactly `data.coverage`, including every ordered structured reason when partial.  The existing traversal/observation contract, not query completion time, determines that value. |

The `ResultDescription` and envelope must agree on this entire value, not merely a hash, reason count or complete/partial tag.
Conflicting outer/inner index coverage is invalid publication or stored-result validation, not a choice left to clients.
An admitted query becomes `Available` when its protected, validated payload and description can be acquired atomically.
A partial index is an available final result with explicit gaps; it is not a pending registration promising that this immutable result will later fill them.
A later analysis/context can produce another result, but retained descriptions, payloads and coverage remain unchanged.
Cancellation or failure that wins before publication retains its existing request outcome instead of publishing a prefix as though the query completed normally.

Keep four questions separate: request availability, preservation of the selected payload's observations, parser status (`COMPLETE | INCOMPLETE | RECOVERED | FATAL`) and world membership/provider consistency.
For example, an `INCOMPLETE` parse can have an exact syntax capture and complete diagnostic observation; its declaration index can independently have complete or partial traversal coverage under the qualified mappings.
An empty diagnostic array means no diagnostics were emitted by this parser run, not that semantic analysis succeeded.
An empty complete index concerns only its captured syntax/profile; an empty partial index cannot prove declaration absence.
None of these arms upgrades a finite world capture to complete import membership, a coherent cross-file disk instant, semantic validity or successful negative lookup.

There is no truncated snapshot or diagnostic-prefix arm in this initial union.
If required observations cannot be represented safely, use the existing unsupported/conversion/resource outcome as appropriate; do not silently drop records and still claim exact capture or complete diagnostic observation.
This does not weaken the existing rule that safely owned malformed/recovered syntax can be available.
It distinguishes malformed source from an incomplete payload conversion, without selecting output limits or approving a new partial-payload profile.

The discriminating future case completes an index query with `PARTIAL_SYNTAX_TRAVERSAL`: `Available`, description completeness, envelope completeness and inner coverage must all agree, while parse status and world membership retain their independent values.
Additional independent cases cover an incomplete parse with fully preserved diagnostics, zero diagnostics, empty complete/partial indices, wrong-kind arms, mismatched/reordered reasons, cancelled publication and attempted snapshot/diagnostic truncation.
Assert the exact outcomes and immutable outer/inner values against independent expectations after implementation authorisation.
Detailed signatures, snapshot-schema closure, numeric limits and release qualification remain open.

##### Diagnostic Origins and Declaration Index Records

Proposed 2026-10-21 for API review, not implemented payload accessors or an approved AST schema.
This refines the actual `Parse_Diagnostic` fields rather than deriving codes from rendered messages or compiler enum ordinals.
Tags below are exact ASCII names; record fields appear in the declared order, arrays preserve order, and counts/IDs/ranges are checked before use.
Unknown tags/fields are invalid for the selected schema, not silently discarded extensions.

`Origin` is a closed tagged union for this initial slice:

- `SOURCE {span}` names an exact common byte span in the selected document/revision.
Zero-width spans, including end-of-file, are valid; token spans must be mapped through that revision's token/source data, never interpreted directly as byte offsets.
- `INSERTED {anchor_span, expected_token}` names a synthetic missing token at a zero-width `SOURCE` anchor; it does not claim that synthetic spelling exists in the source bytes.
- `UNLOCATED {reason}` uses `NO_SOURCE_LOCATION` or `RECOVERED_LOCATION_UNAVAILABLE`, retaining the diagnostic without manufacturing an in-range location.
Raw unmappable token/location observations remain in the parser observation record below for C1 checking.

Generated/evaluated-source origins are unsupported in this syntax-only schema, not `SOURCE` spans into the caller's file.
They require a future origin schema with protected provenance/source mapping.
`Optional(T)` is exactly `NONE` or `SOME {value:T}`; missing and present-empty bytes are distinct.
A payload-local ID is `u64`, zero-based, valid only in its envelope; optional references use `Optional`, not `-1`/maximum-integer sentinels.

`jai-cache-syntax-diagnostics/1` data is `{parse_status, records: []Diagnostic}`.
`parse_status` is `COMPLETE | INCOMPLETE | RECOVERED | FATAL` from the protected parse, not a judgement of semantic validity.
`Diagnostic` is `{code, severity, primary_origin, message_utf8, related: []RelatedDiagnostic, parser_observation}`; `RelatedDiagnostic` is `{origin, message_utf8}`.
Codes map one-to-one from the current parser's named kinds: `EXPECTED_TOKEN`, `EXPECTED_EXPRESSION`, `UNEXPECTED_TOKEN`, `UNNECESSARY_SEMICOLON`, `LEXER_ERROR`.
Severity is `ERROR | WARNING`; recovery action is `NONE | INSERT_MISSING_TOKEN | SKIP_TOKENS`.
`parser_observation` is `{token_span, expected_token, actual_token, recovery_action, lexer_line:s32, lexer_column:s32}`.
`token_span` preserves the parser's signed first/one-past-last token indices as observation data; it is not a dereferenceable byte span.
A mapping failure must not turn an invalid index into a valid one by clamping.
`expected_token` and `actual_token` use `TokenTag` under the exact token-schema identifier already bound by the context, not native enum ordinals.
Preserve inactive/default values as observations; only the code/recovery contract determines whether they have explanatory meaning.
Lexer line/column observations are retained verbatim, not substituted for revision-bound byte ranges or advertised as editor UTF-16 coordinates.
Related records preserve both messages and emission order.
Their original parser token spans must also be preserved in the syntax snapshot's diagnostic observations so C1 can compare unmappable locations without guessing a source span.
If producer messages cannot be represented losslessly as the required UTF-8 presentation text, report a payload-conversion failure and preserve the original bytes in the syntax snapshot; do not silently replace invalid bytes and claim exact diagnostics equivalence.
`FATAL` parse status is not automatically a service failure: publish available diagnostics/recovered syntax when safely owned; an allocation/internal parser failure remains a service failure, not a fabricated language diagnostic.

`jai-cache-syntax-declaration-index/2` data is `{coverage, entries: []IndexEntry, shared_regions: []SharedRegion}`.
`coverage` is `COMPLETE_SYNTAX_TRAVERSAL` or `PARTIAL_SYNTAX_TRAVERSAL {reasons: []CoverageReason}` under the structured reason contract below; completeness concerns traversal of this captured parse, never import closure or semantic membership.
Recovery does not automatically mean partial traversal, and a complete traversal can contain recovered entries.
`IndexEntry` is `{local_entry_id, declaration_node_id, name, syntax_kind, declaration_origin, container, visibility_syntax, program_export_syntax, recovery_status}`.
`name` is `SPELLED {origin:SOURCE, spelling_bytes, producer_name_bytes, form, recovery_origins: []Origin}`, `ANONYMOUS`, `MISSING {origin}`, or `UNMAPPED {producer_name_bytes, reason}`.
`form` is `IDENTIFIER | OPERATOR`; spelled bytes must equal their source slice, while producer-name bytes preserve the parser's possibly different name value under the rules below.
Anonymous, missing and unmapped names are distinct, not empty identifiers.
`container` is `ROOT | DECLARATION {local_entry_id} | SHARED_REGION {local_region_id}` and `recovery_status` is `PARSED | RECOVERED | UNCLASSIFIED {reason:CoverageReason}` under the attribution rules below.
The version change makes shared ownership explicit; these are replacement drafts, not compatibility promises for an implemented v1/v2 payload.
`syntax_kind` is `DECLARATION | COMPOUND_BINDING | ENUM_MEMBER`; it describes the declaration grammar, not whether an initialiser eventually denotes a procedure/type/value.  A compound declaration emits one entry per newly declared binding in authored order, sharing the declaration node/origin; assigned targets are uses, not index declarations.
`ENUM_MEMBER` is the context-qualified bare enum-member occurrence described below, not any identifier in an enum's subtree.
Preserve repeated declared names and infer no semantic category from spelling.
Entries follow the declaration-event order specified below: enclosing declarations and a compound's binding group precede their descendants, with registered authored child/binding order rather than a global span sort.
Declaration containers refer only to earlier enclosing entries.
Shared-region containers follow the acyclic ownership rules below; validate both ID domains and reject cycles, never treat an arbitrary local ID as a pointer or nominal declaration identity.
`visibility_syntax` is `{scope_directive, scope_basis, declaration_marker, observations}`.
`scope_directive` is `UNSPECIFIED | SCOPE_EXPORT | SCOPE_MODULE | SCOPE_FILE | RECOVERED_UNKNOWN`; `scope_basis` records the same-list provenance specified below.
`declaration_marker` is `UNSPECIFIED | EXPORT | RECOVERED_UNKNOWN`; `observations` preserves the ordered directive/marker source spans used to derive those syntactic tags.
These are authored `#scope_export`, `#scope_module`, `#scope_file` and `#export` observations, not a claim of resolved accessibility, valid marker placement, conditional activation or completed exports.
Unsupported/malformed observations remain recovered/partial with reasons rather than being coerced to exported or private.
Do not execute conditions, follow imports/loads, expand `#add_context`, evaluate `using,map`, or merge instantiated members while building this index.
Walk only owned authored/recovered syntax; complete traversal of it is compatible with semantic queries remaining unsupported.
Exact node/token variant registries and traversal-to-current-node mapping still need API review; this draft does not certify that the current parser exposes every marker without an adapter or lossless source observation.

Future acceptance vectors: end-of-file zero-width and inserted-token origins; unmappable lexer/token locations with preserved raw observations; duplicate diagnostics and ordered related messages; invalid message encoding; compound/repeated/anonymous/recovered names; nested containers; visibility changes; partial versus complete syntax traversal without evaluator execution.
Validate these against fresh owned parser observations under C1/C5 after implementation authorisation.
This document refinement neither implements those tests nor selects numeric admission limits, adapter defaults or a persistent payload wire format.

##### Current Parser Mapping and Known Gaps

Proposed mapping review 2026-10-21; this is a producer-adapter contract, not an implemented traversal or proof of complete coverage.

| Producer surface | Required payload mapping or explicit gap |
| --- | --- |
| `Token_Type` in `lexer.jai` | `TokenTag` is `BYTE_CHAR {value:u8}` or `NAMED {name_ascii}` under `jai-cache-token-tags/1`, registered below.  Normalise producer aliases before encoding; reject unknown/noncanonical payload names rather than serialising enum ordinals. |
| `Parser_Token` with `ENABLE_TRIVIA` | Use checked `byte_start`/`byte_end` against the owned exact source.  For a nonempty token interval, map the first token's start through the last included token's end; do not include preceding/trailing trivia implicitly.  Preserve token intervals as separate observations. |
| `Parser_Token` without `ENABLE_TRIVIA` | This aliases `Token`, which has line/column observations but no byte-offset fields.  It is outside the full-featured service profile: no non-trivia byte-mapping adapter is required.  Existing AST-compatibility mode may remain in the current parser independently; this specification does not require preserving that mode in the future owned-syntax API. |
| `add_missing_token` | Correlate the diagnostic's recovery record with `synthetic_tokens` and `insertion_index`; map the insertion position to a checked zero-width source anchor.  At end of input use the exact source length when the token/source mapping validates it.  No synthetic token bytes are inserted into the authoritative source.  Missing/ambiguous correlation remains `UNLOCATED`, not a guessed inserted origin. |
| `Parser_Declaration` / `.DECLARATION` | Emit the authored declaration with its actual name and origin, retaining recovery state and containing syntax ownership.  A synthetic helper `declaration_properties` inside a compound node is not an additional standalone declaration entry. |
| `Parser_Compound_Declaration` / `.COMPOUND_DECLARATION` | Read `comma_separated_assignment.arguments` in authored order and shared `declaration_properties`.  For a qualified `parse_declaration_node` construction, the binding predicate is `(!reassignment && modifier != ASSIGN) || modifier == DECLARE`, where reassignment is the shared `operator_type` equal to the `=` character.  Emit only arguments satisfying this predicate; `ASSIGN` targets and ordinary multi-target reassignment remain uses.  The separate expression-led construction needs route classification as described below; do not apply this predicate universally.  Do not collapse names or duplicate the shared properties node as an entry. |
| `Parser_Directive_Scope` / `.DIRECTIVE_SCOPE` | Map `scope_type` `EXPORT`, `INTERNAL`, `FILE` to `SCOPE_EXPORT`, `SCOPE_MODULE`, `SCOPE_FILE` respectively, preserving the directive origin.  Track direct same-list provenance under the rules below; conditional branches retain branch-local observations without evaluation or a guessed merged visibility state. |
| Declaration `#export` observation | The reviewed scope-directive parser does not establish a declaration-marker mapping.  `EXPORT` in `declaration_marker` is reserved until a real producer path or qualified lossless syntax adapter is identified.  Do not infer it from scope `EXPORT`, resolved visibility, string matching inside comments/literals, or absent metadata.  Unrepresentable relevant observations require `RECOVERED_UNKNOWN`/partial coverage, not a false `UNSPECIFIED` assertion. |
| Declaration `#program_export` metadata | `parse_declaration_metadata` sets `PROGRAM_EXPORT` and optionally stores a string token's value in `program_export_name`.  This requests a program/linker export, not module visibility or the reserved declaration `EXPORT` marker.  Preserve it separately as specified below; the stored string is scalar data, not an AST child. |

The index traversal follows authored syntax ownership/child edges only; it must not follow resolved declarations, lexical binding/reference tables or inferred semantic backreferences.
Snapshot-local node IDs identify syntax occurrences, not names; assign index-local entry IDs independently, preserving the declared enclosing-before-nested and per-binding order.
For nested syntax within a shared compound initialiser, use the proposed shared-region representation below rather than selecting one binding as its sole enclosing declaration.
Until that representation and the reached child mappings are reviewed and qualified, report partial coverage for that region rather than duplicate it or invent container identity.
`COMPLETE_SYNTAX_TRAVERSAL` requires a reviewed child-edge/variant registry covering every reached authored node kind and every required route, origin/name, visibility, metadata and recovery-attribution observation.
An unknown node or unmapped required field makes coverage partial with a reason; successful parsing alone is not that proof.

Mapping checks to implement after authorisation: raw punctuation versus named/aliased tokens; trivia-enabled origins and rejection of a non-trivia full-featured profile; EOF insertion/recovery correlations; `a, b := values` versus `a, b = values` and mixed declare/assign modifiers; shared compound initialiser ownership; sequential/conditional scope directives; unmapped declaration markers and unknown child variants.
These supplement C1/C5 and the payload review vectors without claiming executable adapter qualification.
The initial fifteen-operation interface and all pending policy/implementation gates are unchanged.

##### Same-List Scope Provenance and Conditional Boundaries

Proposed declaration-index/2 refinement grounded in the scope-directive builder function and `parse_static_if_statement`/`parse_statement_block`.
The builder function publishes a standalone `DIRECTIVE_SCOPE` with a `scope_type`; it does not attach effective visibility to each declaration.
Static conditionals retain their branches, including parser-created single-statement blocks, rather than selecting one during parsing.
Consequently, `scope_directive` is strictly a source-provenance summary, not an effective lexical/module visibility state.

`scope_basis` is `{statement_list_node_id: Optional(u64), preceding_directive_node_id: Optional(u64)}`; both IDs refer to nodes of this result's protected syntax snapshot.
The first identifies the nearest owning registered statement-list node on the declaration occurrence's authored ownership path; the second identifies the last qualified direct scope-directive element before the statement containing that occurrence in that same list.
Resolve this path through registered owning edges only, not block-parent/resolution pointers, token-span containment or whichever alias was visited first.
A shared compound payload uses its shared-region ownership path, not a binding selected arbitrarily as an owner.
The referenced list and directive must satisfy the registered node/field roles and actual list ordering.
An out-of-snapshot ID or a directive that is not a preceding direct element is invalid evidence, not an alternative visibility interpretation.

| Authored situation | Required provenance result |
| --- | --- |
| Qualified preceding direct directive | Record that list and directive, map its exact `scope_type`, and preserve its source observation.  A later direct directive supersedes it only for this same-list summary. |
| Qualified list with no preceding direct directive | Record the list with no directive and `UNSPECIFIED`.  This means no direct same-list observation, not private/module/export default visibility. |
| Nested block, aggregate body or conditional branch | Compute a separate list-local summary.  Do not copy an outer list's directive into the inner list's basis or leak the inner list's last directive into its parent or a sibling branch.  The owning syntax graph preserves outer/branch context independently. |
| Declaration nested in an expression/header without an intervening statement list | Use the nearest owning registered statement list and its containing statement as the ordering anchor.  Do not treat a directive inside some other child of that statement as preceding in this list. |
| No statement-list ancestor in a supported standalone syntax form | Both IDs are absent, and the tag is `UNSPECIFIED`; this does not establish a language default or prove that such syntax is semantically valid. |
| Missing ownership/list correlation or unknown relevant directive form | Preserve independently verified observations, use `RECOVERED_UNKNOWN`, and report `UNKNOWN_VISIBILITY` or `UNCLASSIFIED_ROUTE` with `VISIBILITY` impact as appropriate.  Do not confuse unavailable evidence with a qualified no-directive result. |

Traverse both static branches without executing the condition; a declaration's basis refers to its actual branch list, not a synthetic combined list of both branches.
After a conditional statement, a parent's same-list summary still refers only to preceding direct elements of that parent list.
Even if both branches spell the same directive, do not merge their observations into a parent directive or claim that a following declaration has that effective visibility.
Likewise, a known direct parent directive does not settle whether conditional directives, loaded files or language-specific scope rules alter effective visibility.
These are semantic/module-composition questions outside this payload.
Recovering a condition does not by itself invalidate an otherwise qualified list/directive association; unresolved ownership or relevant directive observations do.
Never use condition truth, symbol lookup or file following to repair the syntax summary.

Declaration markers remain separately observed under their qualified producer routes; scope provenance cannot fill the reserved declaration `EXPORT` marker.
Program/linker export metadata remains separate from both.
`COMPLETE_SYNTAX_TRAVERSAL` may include `UNSPECIFIED` same-list summaries where absence of a direct directive is established; it may not conceal an unavailable list/marker mapping as that absence.
This refinement deliberately provides no effective-visibility query, inheritance algorithm, branch-join operation or extra service operation.

The discriminating future case places different scope directives in the two static branches followed by a parent-list declaration: retain both branch-local bases without selecting a condition or manufacturing a merged parent directive.
Additional independent cases cover repeated direct directives, nested aggregates/procedures, single-statement branch blocks, shared compound payloads, header/expression declarations, a standalone supported form, recovered conditions, unknown directive evidence and invalid basis IDs/order.
Assert exact basis IDs, source observations, list-local tags and partial reasons against independent ownership/list expectations after implementation authorisation.
Compiler visibility/default/inheritance behaviour remains separate pending qualification; these are draft source-provenance rules, not that behaviour's implementation.

##### Program Export Metadata Versus Visibility

Proposed 2026-10-21 for the declaration-index/2 draft; no producer adapter or source-observation pass is implemented by this refinement.
`parse_declaration_metadata` recognises `align`, `no_reset`, `uninitialized`, `elsewhere` and `program_export`; its default branch stops without consuming an unknown directive.
That path does not recognise `export`.
This establishes a limit of the reviewed producer path, not that `#export` is supported elsewhere or that every remaining source token was inspected as declaration metadata.
Keep declaration-marker `EXPORT` reserved and the earlier unknown-observation rule intact.
Neither `PROGRAM_EXPORT` nor `program_export_name` supplies a declaration-marker or scope-directive value.

`program_export_syntax` is `{coverage, occurrences: []ProgramExportOccurrence, producer_observation}`.
Its `coverage` is `COMPLETE_METADATA_OBSERVATION | PARTIAL_METADATA_OBSERVATION {reasons: []CoverageReason}` for this declaration's metadata, not semantic export validity or whole-index traversal.
Metadata and `UNMAPPED` name reasons use the same structured record and propagate to the index's partial reasons.
`ProgramExportOccurrence` is `{marker_origin:SOURCE, name_argument: Optional(ProgramExportName)}`; `ProgramExportName` is `{origin:SOURCE, value_bytes}`.
The marker origin covers the authored `#` and `program_export` tokens; a name origin covers the consumed string token.
Trivia between tokens remains in the protected source, not in decoded `value_bytes`.
Preserve occurrences in token order, including repeats.
`NONE` means no string token was consumed for that occurrence; `SOME` with empty bytes means an explicitly present empty string.
Do not substitute the declaration's name when the argument is absent.
`value_bytes` is the exact lexer string value under the captured `EVALUATE_STRING_ESCAPES` profile, not a host-decoded or normalised linker name; raw spelling and malformed-input observations remain protected separately.
`producer_observation` is `Optional({requested:bool, stored_name_bytes})` from `PROGRAM_EXPORT` and `program_export_name`, even when source correlation is incomplete.
Use `SOME` for declaration-properties records and `NONE` for index occurrences such as bare enum members that have no such producer record; do not manufacture a false flag/empty string pair.
Copy/lease these bytes independently of producer allocator lifetime; they are not pointer identity or an identifier-interner key.

The producer loop sets the flag on every recognised occurrence and overwrites the stored name only when the following token is a string.
Thus, a later bare `#program_export` does not clear an earlier stored name.
With complete correlation, `requested` must equal whether any occurrence was consumed and the stored name must match the last consumed name, or the producer's initial empty value if none was consumed.
Do not infer occurrence count, argument presence or ordering from that final flag/string pair; it loses information, particularly for explicit empty names and repeated markers.
An adapter must correlate exact metadata tokens with the owning declaration's parse route and recovery, not search all tokens within its full span: an initialiser, nested procedure, comment or string can contain unrelated text.
A complete observation requires a qualified metadata interval and all consumed occurrences; otherwise retain verified occurrences and producer data, report partial metadata coverage and propagate a declaration-index partial reason.
A zero flag alone does not prove complete absence.

For a compound declaration, source metadata belongs to the shared region.
Each binding entry may expose the same immutable observation value, but it is one authored observation sequence, not one occurrence per binding or a claim that every target is semantically exported.
The compound with no declared bindings still retains this data in its protected syntax; a declaration index with no binding entries does not invent one to carry metadata.
No helper token span may be fabricated to recover the metadata interval; compound properties require correlation through the owning compound and actual parse boundaries.

The cheap discriminating source check is the assignment in `parse_declaration_metadata`: it copies `parser_eat(parser).string_value`, not a `Parser_Node` pointer, and only inside the `.STRING` branch.
Existing `parser_tokens_test.jai` fixtures exercise named exports and incremental owned-byte comparisons, but they are not qualification of the new occurrence schema.
Future independent acceptance vectors: absent/bare/named/explicit-empty requests; repeated named then bare and named then empty requests; evaluated versus unevaluated escapes; compound metadata; nested initialiser decoys; unknown directives and malformed/recovered string tokens; byte ownership after producer teardown.
Check exact source origins, occurrence order, absent-versus-empty names, final producer observations and partial reasons.
Leave declaration `#export` mapping open until supported producer evidence exists; do not invent a syntax adapter or change parser behaviour to close it on paper.

##### Authored Child Edges and Shared Compound Regions

Proposed 2026-10-21 for schema review; no production visitor, index conversion or acceptance test is implemented here.
The local hypothesis is that the compound node, not any one binding, owns its shared properties and initialiser: `parse_declaration_node` allocates one `declaration_properties`, parses its expression once, then records scope bindings pointing to that helper.
A discriminating future check is a compound initialiser containing a nested declaration: traversal must produce one nested entry and one shared region, even with repeated declared names, mixed declared/assigned targets or no declared bindings.
Duplicating the nested entry per binding or assigning it to the first binding falsifies this contract.

`SharedRegion` is `{local_region_id, compound_node_id, parent_container, binding_entries: []local_entry_id}`.
Region IDs are zero-based payload-local `u64` in a separate domain from entry IDs.
`parent_container` uses the same container union as `IndexEntry`; it identifies the enclosing ownership context outside this compound, never one of this region's bindings.
`binding_entries` contains exactly this compound's newly declared binding entries in authored argument order, preserving duplicate spellings as distinct entries.
Assigned targets are not members.
An empty list is valid for a pure assignment and does not fabricate a declaration.
Every listed entry must reference this `compound_node_id` and have `container == parent_container`; a binding cannot belong to two regions.
Create the region and emit all its binding entries before descending into shared properties, alignment or notes.
Direct nested declarations there use `SHARED_REGION`; descendants of a nested ordinary declaration use that declaration as usual.
A nested compound's region retains the outer container through `parent_container`.
The binding list expresses syntactic association, not value distribution, inferred tuple arity, evaluation order or semantic ownership of a type/procedure.
Even a one-binding mixed compound keeps its region; do not collapse it into a special single-owner case.
Validate container ancestry across both tables, region membership and all node references before exposure.
Containment must be acyclic; binding-list references are associations, not additional containment edges.
Do not infer ancestry from overlapping source spans or compare local IDs from different payloads.

For `jai-cache-authored-edges/1`, each reviewed producer field has exactly one traversal role: `CHILD`, `CHILD_LIST`, `HELPER`, `BACKREFERENCE`, or `NON_CHILD`.
`HELPER` is structural storage traversed through its registered fields, not an extra authored declaration; it may have no independent source origin.
Embedded base records, scalar flags/names/spans and inactive union arms are not child occurrences.
Follow only the active discriminant-selected arm; a null optional child is absent, not an unknown node.
Register field paths and variant guards against the exact producer/schema binding.
Reflection over all pointers, the compiler inventory's broad `S` category, or successful parsing is not an ownership registry.
In particular, syntactic backlinks remain backlinks even when classified `S` in `compiler_fields.md`.

The following is the candidate field-path registry for the current parser-owned shapes.
Names without a prefix refer to `Parser_*` records; grouped rows do not waive per-variant review.

| Owner | Candidate downward paths / active helpers |
| --- | --- |
| `Declaration` | `type_inst`, `expression`, `alignment_expression`, `notes[]`; compound properties use this field map without emitting a helper declaration.  `program_export_name` is scalar string metadata, not a child. |
| `Compound_Declaration` | `comma_separated_assignment` node (then its ordered argument nodes), `declaration_properties` as helper, compound `alignment_expression`, compound `notes[]`; preserve structural node IDs and visit shared payload once, not through lexical bindings. |
| `Block` | `statements[]` only; source order is authoritative. |
| `Procedure_Header`, `Procedure_Body` | Follow the procedure ownership/alias rules below: parameter segments, `returns[]`, optional `library_identifier`, `modify_directives[]`, optional `body_or_null`.  Body owns `block`, not `header`.  `foreign_function_name` and `deprecation_string` are scalar strings; header `notes[]` is not populated on the reviewed routes. |
| `Struct`, `Enum` | Struct: optional `arguments_block`, `modify_directives[]`, `block`.  Enum: optional `internal_type_inst`, `block`.  Follow the aggregate-context rules below; struct `alignment` is numeric metadata, and aggregate `notes[]` is not populated on the reviewed routes. |
| `Unary_Operator`, `Binary_Operator`, `Cast` | `subexpression`; `left`, `right`; casts use prefix/postfix/auto source-form order specified below rather than unconditional target-before-expression traversal. |
| `Procedure_Call` | `procedure_expression`, then `arguments_unsorted[]` helpers (optional `name` before `expression`), then optional `context_modification.modification_expressions[]`; use the published-helper and recovery rules below, never sorted/resolved arguments or macro output. |
| `Comma_Separated_Arguments`, `Return` | `arguments[].node`; `arguments_unsorted[]` helpers (`name`, `expression`), respectively. |
| `Expression_Query`, `Type_Query`, `Type_Instantiation` | `expression_to_query`; `type_to_query`; type-instantiation paths follow the explicit source-form guards below, not a nonnull-pointer priority chain. |
| `Literal` | Follow the literal-arm and construction-route guards below: struct `type_expression`, `arguments[]`; array `element_type`, `array_members[]` on reviewed routes.  Scalar/null literals have no authored children; array alignment is not populated by these reviewed builder functions. |
| `If`, `Case`, `While` | Follow the control-flow guards below: condition before branches/body, both authored branches without evaluation, context-qualified absent default-case conditions and normalised single-statement blocks. |
| `For` | Source-ordered `want_reverse_expression`/`want_pointer_expression`, then `want_replacement_for_expansion`, `ident_it`, `ident_it_index`, `iteration_expression`, optional `iteration_expression_right`, `block`; use the control-flow guards below and exclude implicit declarations/generated expansion. |
| `Loop_Control`, `Defer`, `Push_Context`, `Using` | `target_ident`; `block`; `to_push`, `block`; optional `filter_expression` before `expression`, respectively.  Parameter-using expression aliases follow the header-specific rule instead of a second descent. |
| `Directive_Add_Context`, `Directive_Bytes`, `Directive_Code`, `Directive_Location`, `Directive_Run` | Guarded payload descent as specified below; arrow-run source headers are a reviewed exception to excluding compiler-lowered procedure fields. |
| `Directive_Bake`, `Directive_Exists`, `Directive_Import` | `procedure_call`; `query_expression`, optional `sync_expression`; optional module/program parameter calls with import-callee backreference guards.  Import `name` is scalar string data. |
| `Directive_Insert` | Optional `scope_redirection`, published replacement statements in qualified clause order, then `expression`; not generated `expansion`. |
| `Directive_Library`, `Directive_Load`, `Directive_Modify` | Library/load names are scalar strings with no child; modify owns `block`.  Do not follow imported/loaded files. |
| `Directive_Module_Parameters`, `Directive_Overlay`, `Directive_Poke_Name`, `Directive_Procedure_Name` | `module_parameters`, `program_parameters`, `common_code`; `target_expression`, `declaration_or_using`; parser `module_expression` only (poke `name` is scalar); optional `argument`, respectively. |
| `Ident`, `Context`, `Note`, `Placeholder`, `Directive_Context_Type`, `Directive_Scope`, `Directive_Through`, `Directive_Wildcard` | No authored node children in the candidate mapping; retain source scalar observations separately. |
| Base `Parser_Node` with `.DIRECTIVE_THIS` | No authored child in the reviewed `#this` builder function; this reachable kind is not represented by a concrete entry in `TYPES`.  Preserve its source/kind observations without interpreting a nonexistent derived payload. |
| `Asm` | Parser-owned `features[]`, `statements[]` helpers, not opaque compiler `b1`/`b2`/`b3` storage.  Use the explicit assembly-helper guards and order below; `UNPARSED` base operands can still own parsed modifiers. |

Explicit `BACKREFERENCE` paths include `Block.parent`, `Block.belongs_to_struct`, `Block.owning_statement`, `Procedure_Body.header`, `Case.owning_if` and parser `Asm.enclosing_scope`.
Lexical scopes/children/bindings, identifier `resolved_declaration`, common inferred `type`, enclosing-load references, compiler constants/polymorph/expansion records and sorted/resolved call data are excluded from authored descent.
These exclusions do not delete source observations from the protected syntax snapshot or define semantic invalidation edges.

Assign snapshot-local node IDs on first registered downward encounter, retaining the same ID for explicitly registered helper aliases; never serialise pointer addresses or merge separate nodes by equal spelling/span.
An active-path revisit through a downward ownership edge is a cycle error.
Registered non-owning associations, including import callees pointing to an active ancestor, are recorded without recursive descent and are not ownership-cycle errors.
A completed-node revisit is permitted only by a registered alias rule with a specified single traversal owner; otherwise coverage is partial with an unexpected-sharing reason, not silently deduplicated by a global visited set.
Use valid source positions to interleave independent authored children in lexical order; equal/unlocated positions use a reviewed per-kind field-path order and then list index.
This candidate table is not itself that complete ordering/guard registry.
Helper nodes without a finished token span, including compound `declaration_properties`, do not gain a fabricated `SOURCE` origin from zero-initialised token fields; shared-region source identity comes from the owning compound.

There is a second compound-construction path in `parse_statement`: expression-led multi-target assignments allocate the same helper shape but do not set `operator_type` there.
Consequently, the earlier binding predicate is qualified only for the reviewed `parse_declaration_node` route; it is not a universal shape-only classifier for arbitrary compound nodes.
Until a qualified producer observation distinguishes these routes and non-identifier targets, preserve their syntax but report partial declaration-index coverage rather than emit bindings from a default operator value.
The proposed route-evidence contract below defines that requirement without claiming the current parser already supplies it.
Do not repurpose resolver bindings as authored ownership to hide this gap.

Remaining review/qualification: exact active-form guards and child order for every variant and assembly helper; producer-version drift; alias rules for shared metadata; declaration-marker mapping; and reliable compound-route classification.
Future C1/C5 vectors must cover shared initialisers with nested anonymous/ordinary/compound declarations, zero/one/multiple declared bindings, repeated names, both compound construction routes, recovered null/unlocated helpers, injected cycles/unregistered sharing, inactive literal arms and deliberately populated semantic backlinks.
Assert exact entry/region counts, IDs, association order, parent containers and coverage reasons against independently authored expectations, not only a second traversal using the same registry.
The schema/traversal proposal is drafted, not reviewed or behaviourally qualified; R2/R6-R8 and implementation/migration authorisation remain unchanged.

##### Recovery Attribution and Published Syntax

Proposed declaration-index/2 refinement grounded in `add_missing_token`, `add_expected_expression_at`, `add_unexpected_token` and the cursor-only checkpoint/restore implementation.
Recovery records retain diagnostic references and, for missing tokens, a synthetic-token reference; they do not identify an owning declaration node.
`parser_restore` restores only the cursor, so observations from an abandoned attempt cannot automatically be attributed to the syntax later published at that position.
The result-wide parse status and diagnostic/token spans are therefore insufficient by themselves to classify each entry's recovery.

For this index, recovery status concerns the entry's published authored subtree, not just its name/header and not the whole document.
Attribute recovery through a qualified construction observation or registered producer-version-bound correlation under the adapter's existing `builder_function_routes` capability; this does not add another capability feature.
Evidence must distinguish committed published syntax from discarded/speculative work and preserve the diagnostic/recovery/synthetic-token relationships.
Capturing a time interval or scanning for overlapping diagnostics alone is not that proof.

| Entry status | Required evidence |
| --- | --- |
| `RECOVERED` | At least one qualified recovery event belongs to this occurrence's published authored subtree, including a mapped inserted name token, expected-expression hole or skipped-token recovery.  Do not require `INSERT_MISSING_TOKEN`: expected-expression records can have no synthetic token and a default diagnostic recovery action. |
| `PARSED` | Attribution is complete for this occurrence's published subtree and establishes no recovery events there.  This does not assert compiler validity, semantic success or absence of lexer/language diagnostics. |
| `UNCLASSIFIED` | Neither a positive recovery attribution nor complete no-recovery evidence is available.  Retain the safe entry with a structured `UNCLASSIFIED_ROUTE` reason including `RECOVERY` impact, propagated to top-level partial coverage; do not guess either other tag. |

Propagate a qualified event through registered downward ownership to enclosing declaration entries.
An outer procedure declaration is recovered when a published nested body declaration is recovered; an unrelated following sibling is not.
Registered non-owning aliases, scope/binding tables and resolved references do not propagate recovery.
A shared compound type/initialiser/alignment/note event affects every emitted binding entry of that compound, without duplicating the event or nested syntax; a binding-specific name event affects that binding rather than all its siblings.
Events in compound target expressions propagate through their actual outer ownership context, not through an arbitrarily selected binding or the shared-properties region.
Shared regions carry no independent recovery-status tag in this schema.
Attribution to an enclosing published node does not assert that an unattached failed declaration exists.
Keep diagnostics from such failures, but never manufacture an entry or assign them to the next declaration merely because token positions coincide.

Lexer errors and non-recovery diagnostics remain preserved diagnostic observations; their presence alone is not an entry recovery event.
If a lexer failure also causes qualified parser recovery, attribute that parser event normally.
Missing/ambiguous location mapping does not erase an otherwise qualified recovery association: a recovered entry can have unlocated observations and separate source-mapping coverage gaps.
Conversely, an exact inserted-token anchor does not establish which declaration owns it.
A fully mapped recovered subtree can still have complete syntax traversal, while missing attribution makes coverage partial even when source spelling and node traversal are otherwise available.
Invalid recovery/diagnostic/synthetic-token references or conflicting attribution evidence remain validation failures, not an `UNCLASSIFIED` success containing unsafe associations.

The discriminating future case recovers a nested procedure-body declaration: both that entry and the enclosing procedure entry are `RECOVERED`, while an unaffected sibling remains `PARSED` only with complete attribution evidence.
Additional independent cases cover expected-expression recovery without a synthetic token, skipped tokens, shared-compound versus binding-name events, cursor restoration after an abandoned attempt, unattached failures, lexer-only diagnostics, unlocated but attributed events and absent/corrupt attribution.
Assert exact per-entry statuses, published ownership associations, partial reasons and retained diagnostic order against independent expectations after implementation authorisation.
This draft neither instruments the parser nor qualifies a correlation adapter.

##### Declaration Events, Local IDs and Partial Containers

Proposed declaration-index/2 ordering refinement, grounded in the compound builder functions' ordered arguments and single shared properties helper.
"Source order" means an ownership-preserving event sequence, not sorting completed records by byte start/end.
Equal spans, unlocated recovery and a compound's multiple bindings make a span-only comparator insufficient.
Visit reached nodes through the bound authored-edge/child-order registry.
At each qualifying ordinary declaration or enum-member occurrence, emit its entry before visiting its owned children; keep its container active only for those children, then restore the previous container.
Structural nodes that are not index declarations introduce no invented declaration container.
A registered non-owning alias emits neither another entry nor another descent.

For a qualified compound, create its region on encounter and emit the entire newly declared binding group in argument order before descending into its children.
Each binding uses the outer container and the compound node ID as already specified, not the preceding binding as its parent.
Then visit the compound's registered child sequence once.
Descendants of target expressions use the outer container; they are not initialiser content owned by a binding or by the shared-properties region.
When entering shared properties, alignment or notes, use this compound's `SHARED_REGION` container and restore the outer container on exit.
An ordinary declaration encountered there introduces its own declaration container for its descendants.
This grouping can place a later binding's entry before a nested declaration whose source begins in an earlier target; it is the specified binding-group precedence, not evidence of evaluation order or a reason to reorder the graph.
Expression-led assignments have no newly declared binding group under the qualified route rules, but still retain a region and the same target-versus-shared-payload distinction.

`local_entry_id` is a zero-based `u64` equal to the entry's position in `entries`; `local_region_id` likewise equals the region's position in `shared_regions` in region-creation order.
These remain separate domains even when their numeric values coincide.
Snapshot node IDs retain their separate first-downward-encounter rule; emitting a compound binding group does not assign extra node IDs or renumber the protected syntax graph.
Assign no ID for an omitted record, use no sentinel value in place of an absent reference, and check representability before publishing.
This representation does not choose numeric admission/resource defaults.
Validate declaration-container references to earlier enclosing entries, region parent ancestry and the exact ordered binding associations; numeric ID order alone is not proof of ownership.
Buffering for validation is permitted, but do not expose an incomplete table or forward/dangling reference as a completed result.

If an ancestor that must be represented as an index declaration cannot be emitted safely, do not silently reparent its descendants to `ROOT`, another binding or the next available outer entry.
Omit descendants whose required container cannot be represented and report the affected `DECLARATION_SET` and `CONTAINMENT` impacts on a safe snapshot subject.
Independently safe source/diagnostic observations and unrelated index records remain usable.
This is distinct from a reviewed non-declaration structural owner, which correctly emits no entry, or a mapped `UNMAPPED` name, which can still have an entry and a valid container under its explicit partial reason.
Do not let skipped/recovered/partial subtrees leak the active declaration/region container into the following sibling.

IDs are occurrence references inside this result only.
Inserting/removing an earlier declaration, changing traversal/mapping context or publishing a different partial subset may renumber later records; do not match results by numeric ID, equal name/span or array position.
Exact reuse retains the complete bound payload and its original IDs; it does not make those IDs portable to another snapshot/envelope or establish nominal continuity.

The discriminating future check uses a compound with multiple declared bindings and one nested shared-initialiser declaration: emit the binding group first and the nested entry once under the region, with separate entry/region/node domains.
Additional independent cases cover target-expression declarations in expression-led assignments, nested compounds, equal/unlocated spans, alias visits, zero-binding regions, omitted required ancestors, container restoration after gaps and earlier-entry insertions that renumber later records.
Assert exact entry/region arrays, IDs, event order, container paths and partial impacts against independent expectations after implementation authorisation.
This draft resolves ordering/representation rules, not a production visitor, cross-result matcher or qualified child registry.

##### Structured Coverage Reasons and Consumer Guarantees

Proposed declaration-index/2 refinement; reason records describe incomplete observations, not source-language diagnostics, successful semantic facts or service failures.
`CoverageReason` is `{code, subject, field_path: []PathStep, impacts: []CoverageImpact, origin: Optional(Origin), detail_utf8}`.
`subject` is `DOCUMENT` or `NODE {local_node_id}` in the protected syntax snapshot of this exact envelope; it is not an entry ID, pointer or cross-result reference.
`PathStep` is `FIELD {name_ascii}` or `ELEMENT {index:u64}`; field names and list steps resolve through the bound registry, with checked list indices.
An empty path refers to the whole subject; `DOCUMENT` requires an empty path.
For an unrecognised field/kind without a safe registered path, identify the containing safe node or document rather than manufacturing a dereferenceable path.
Retain unsupported raw observations in the protected snapshot only where its schema safely represents them.
An unavailable origin is `NONE`, not an invented zero-width source range; an available `Origin` must pass the common revision/span checks and indicates the known affected observation, not necessarily the full extent of missing syntax.

`CoverageImpact` is `DECLARATION_SET | CONTAINMENT | NAMES | SOURCE_MAPPING | VISIBILITY | ORDER | METADATA | RECOVERY`.
The list is nonempty, has no duplicates and follows that registry order.
State all known impacts: uncertainty about which bindings exist is not merely a display-name issue, and uncertain child ownership can affect both containment and declaration enumeration.
`detail_utf8` is explanatory text, not a machine-readable classification or an authority for coverage; clients must not parse it to recover a missing code/impact.

| Exact reason code | Intended missing observation |
| --- | --- |
| `UNAVAILABLE_OBSERVATION` | A required registered adapter feature cannot provide evidence for this reached region. |
| `UNMAPPED_NODE_KIND` | A reached syntax kind lacks a reviewed safe traversal/index mapping. |
| `UNMAPPED_FIELD` | A required field or active variant has no qualified mapping. |
| `UNCLASSIFIED_ROUTE` | Construction/source-form evidence is insufficient, including ambiguous compound binding classification. |
| `UNMAPPED_ORIGIN` | Required source/name/recovery location cannot be correlated without guessing. |
| `UNMAPPED_NAME` | Name form, source spelling or producer-value correlation is unavailable. |
| `UNCORRELATED_METADATA` | Metadata boundaries, occurrence presence/order or source/value association are not established. |
| `UNKNOWN_VISIBILITY` | Authored scope/marker observations required by the index cannot be established. |
| `UNPROVEN_CHILD_ORDER` | Children are safely known but their required authored order is not established. |
| `OPAQUE_SYNTAX` | A preserved source region, such as an unparsed assembly operand, has not been traversed for the promised observations. |
| `UNREGISTERED_SHARING` | A safe repeated node lacks a qualified alias/single-owner rule; stop the unqualified descent rather than duplicate it. |

Codes and impacts are closed ASCII tags; unknown tags reject this schema rather than silently becoming generic success.
Numeric admission/text limits remain part of the outstanding bounds review, not defaults chosen here.
Retain reasons in deterministic traversal-discovery order, with owning-node observations before descendant observations and registry/field/list order for ties.
Independent occurrences are not deduplicated by equal code/message, and a copied metadata/name reason retains its original subject/path/impacts when propagated to top-level coverage.
Top-level `PARTIAL_SYNTAX_TRAVERSAL` requires at least one reason.
`COMPLETE_SYNTAX_TRAVERSAL` requires no unresolved required observation anywhere in the traversed captured parse; an empty reason list must not be used to hide an unsupported producer route.
Local `UNMAPPED` names and partial metadata must have corresponding top-level reasons.
Propagating a reason does not promote a local partial record to complete or fabricate an entry for an unclassified declaration.

Safe positive records can still be returned when unrelated observations are incomplete.
Their explicit recovered/unknown fields remain authoritative: a partial result must not silently choose one uncertain container/name/visibility value and present it as proved.
This schema provides no subrange-completeness certificate.
A client cannot infer complete local coverage merely because no reason's known origin overlaps its requested range; an unlocated gap or uncertain container may affect that range too.
In particular, no matching entry in a partial index is not proof that a declaration is absent, and complete syntax traversal still proves nothing about imports, evaluated/generated membership, semantic lookup or accessibility.

Malformed references, conflicting snapshot-bound evidence, invalid source spans and downward ownership cycles remain validation/conversion failures under the earlier contracts, not successful partial results with unsafe graphs.
Cancellation, unsupported payload kinds and resource/internal failures retain their existing request outcomes; do not disguise them as `OPAQUE_SYNTAX` or source diagnostics.
Conversely, ordinary fully mapped parser recovery needs no coverage reason merely because diagnostics exist.
Cache/result reuse preserves the exact reasons, impacts, bindings and coverage state.
A later adapter or newer parse cannot relabel a retained partial result complete without a newly validated result under the appropriate context/world.

The discriminating future vector is an unclassified compound: return safely known syntax with a `UNCLASSIFIED_ROUTE` reason affecting `DECLARATION_SET`, not an empty complete binding list.
Additional independent cases cover unmapped names, metadata propagation, opaque assembly, unlocated/overlapping gaps, safe sharing without an owner rule, invalid paths/tags, recovered-but-complete parses, empty partial-reason lists and corrupt/cancelled/unsupported outcomes.
Assert exact reason records/order, impacts, coverage aggregation and forbidden negative inferences against independent expectations after implementation authorisation.
This draft defines the observation contract, not an implemented coverage engine or approved numeric/API bounds.

##### Name Spelling, Producer Values and Recovery

Proposed refinement of declaration-index/2 names and the adapter's `name_origins` capability, grounded in `parse_operator_declaration_name`, declaration-name capture and backticked identifier lexing.
The producer's name string is an observation, not necessarily an exact contiguous source spelling.
Keep it separate from source bytes; neither equality by name nor interner-address identity establishes a declaration occurrence or nominal identity.

For `SPELLED`, `origin` covers the actual name occurrence's source tokens, and `spelling_bytes` equals that exact half-open source slice without removing comments, whitespace or backticks.
`producer_name_bytes` is the owned exact name value stored by the producer for this occurrence; it need not equal `spelling_bytes` and is not an editor-normalised display name.
`form == IDENTIFIER` applies to ordinary/compound binding identifiers and context-qualified bare enum members; `OPERATOR` requires the qualified operator-declaration route, not punctuation anywhere in an expression.
Preserve modifier/keyword source observations outside the name separately; do not include the declaration's type, initialiser or `operator` keyword in the symbol-name slice merely because they share its node interval.

| Qualified occurrence | Spelling/value distinction |
| --- | --- |
| Ordinary identifier | Correlate the actual name token, not the declaration's first token, which may instead be `#no_reset`, `$` or another prefix.  Preserve exact producer name bytes and raw token spelling. |
| Backticked identifier | The lexer marks `ident_is_backticked` and preserves the token spelling including the leading backtick, while its identifier name comes from the identifier scanner after that prefix.  Do not strip bytes from the source slice or claim the producer value includes the backtick. |
| Single-token operator name | The operator parser returns a registered punctuation/operator string.  Correlate the consumed operator token under the operator-declaration route; declaration/operator flags do not supply its origin alone. |
| Multi-token operator name | `*[]`, `[]` and `[]=` are constructed producer strings.  The source name interval runs from the first symbol through the last actually consumed name symbol, including intervening trivia; e.g. `operator [ ] =` preserves `[ ] =` separately from producer `[]=`. |
| Recovered operator punctuation | `parser_expect` can record a missing `]` while the operator parser still returns `*[]`/`[]`/`[]=`.  Keep only the actual source bytes in the name slice and correlate missing punctuation separately; never insert expected bytes into `spelling_bytes`. |

`recovery_origins` preserves the ordered recovery observations specifically correlated to this name parse, using the existing `INSERTED`/`UNLOCATED` origin rules.
An inserted punctuation origin is not an authored name fragment or a spelling edit.
An empty list is valid for a mapped unrecovered name.
Do not attach unrelated declaration/initialiser diagnostics merely because they overlap the enclosing node span.
A mapped recovered name remains `SPELLED` with `recovery_status == RECOVERED` on its entry; producer-name bytes may include expected punctuation absent from the source.
If no trustworthy name interval or name-route/recovery correlation is available, use `UNMAPPED` with the retained producer value and a partial-index reason, not a guessed/clamped span or a false `MISSING` tag.

`ANONYMOUS` denotes a qualified grammar slot with intentionally no name, such as a supported unnamed parameter/return slot.
`MISSING` requires evidence that this grammar expected a name, but recovery did not produce one, with its insertion/unlocated origin.
A zero-length producer string alone proves neither state.
Do not fabricate an index entry for an unattached declaration parse that returned null; retained source/diagnostics still describe that failure.
Repeated names and equal interpreted operator strings retain distinct entry/node IDs and source occurrences.
No Unicode/case normalisation, concatenation of arbitrary tokens or scope lookup is permitted to manufacture the producer value.
Keep source slices under the source/result lease and copy/lease interpreted name bytes independently of parser/interner teardown; malformed non-UTF-8 source/name bytes remain exact byte observations, not lossy UTF-8 presentation text.

The discriminating future vectors are `[ ] =` versus `[]=` source spellings with the same operator value, and a backticked identifier whose spelling differs from its producer name.
Additional independent cases cover all operator-name routes, missing closing punctuation, prefixed declaration names, duplicate bindings/operators, unnamed versus missing slots, absent correlation, unrelated diagnostics and owned bytes after producer teardown.
Assert exact byte slices, producer values, name form/recovery origins, entry recovery status, local IDs and partial reasons against independent expectations.
This is a draft schema correction, not implemented name correlation, compiler-validity checking or qualification of the `name_origins` capability.

##### Syntax Adapter Capabilities and Coverage Admission

Proposed review packet for the syntax-to-payload adapter, separate from the source-provider adapter's filesystem/lease capabilities.
The existing `producer` context field must identify both the actual adapter build and its canonical observation capabilities; parser identity and output-schema names alone do not identify an index mapping implementation.
Changing a route classifier, child/alias registry, name/origin mapping or supported observation set must conservatively change this binding before reuse.
A complete index from an older binding cannot be relabelled under the new one, even when exact source and parser build are unchanged.

The proposed capability schema is `jai-cache-syntax-adapter/1`, encoded as `K("syntax-adapter", [schema_id, registry_binding, feature_records...])`.
`registry_binding` names the exact registered authored-edge, origin/name and payload mappings used by this adapter.
Feature records appear in the following table order and use `K(feature_name, [method_tag, observation_schema])`.
`method_tag` is exactly `UNAVAILABLE`, `CAPTURED` or `RECONSTRUCTED`; `observation_schema` is empty bytes only for `UNAVAILABLE`, otherwise the exact registered producer-observation or correlation schema identifier.
Reject unknown/missing/reordered/duplicate features and unsupported schemas; these are not free-form claims or a generic extension map.
The adapter build identity is a separate service-verified value in the producer context field, not inferred from this descriptor's text or a host-selected label.

| Feature name | Required evidence and current review status |
| --- | --- |
| `authored_edges` | Exact reachable-kind/field/variant/order registry, including base `DIRECTIVE_THIS`, guarded aliases and recovered holes.  Candidate rules are drafted above/below; exhaustive producer review and executable qualification remain open. |
| `builder_function_routes` | Qualified source-form/context evidence for types, literals, enum-member mode, parameter usings, import callees and arrow-run headers, plus committed published-syntax recovery attribution under the rules above.  Do not infer a universal route from equal/default field values or recovery ownership from diagnostic overlap.  Capture versus reconstruction remains review work. |
| `compound_routes` | Snapshot-bound `CompoundRoute` and separator observations under the following contract.  Current AST fields alone are insufficient; no qualified capture/reconstruction adapter is supplied yet. |
| `name_origins` | Exact spelled/anonymous/missing observations, separate source spelling and producer-name values, name-specific recovery and explicit unmapped outcomes, including operator names, unnamed slots and context-qualified enum members.  A copied/normalised producer name is not automatically a single source slice.  Full mapping remains open. |
| `metadata_origins` | Correlated metadata boundaries/order and argument presence, including repeated/bare/empty program exports and alignment/replacement clauses whose final fields lose occurrences.  Current final fields alone are insufficient. |
| `declaration_markers` | Authored declaration-marker observations distinct from scope and program exports.  The reviewed parser paths have not established declaration `#export` support; this gap must stay explicit rather than be declared captured. |

`CAPTURED` proposes retaining evidence at the owning parse/construction point; `RECONSTRUCTED` proposes a separately registered, producer-version-bound correlation.
Neither tag is qualification by itself: the service must bind the actual supported implementation/schema and its review evidence, not trust an arbitrary descriptor supplied by a caller or manifest.
An unavailable feature does not make exact source/tokens or independently supported diagnostics unavailable.
It prevents complete declaration-index coverage wherever the missing feature is required; preserve safe supported records and report the affected region/reason, not an empty complete result.
Likewise, a globally available feature does not prove that a recovered/unknown source region was mapped: coverage is computed from the observations actually obtained for that result.
If a requested query kind/schema is not implemented at all, use the existing unsupported outcome; partial index coverage is for an implemented mapping with explicit local gaps, not a substitute for an absent payload implementation.
Invalid cross-snapshot evidence, conflicting route records or unsafe references remain conversion/validation failures, not ordinary partial results containing untrusted references.

Expose the registered capability binding through the existing session description/capability reporting and retain its exact context binding on each world/result; this requires no additional service operation.
Do not upgrade an already captured world's capabilities in place when an adapter is installed or revised.
New analysis under a new context can publish a successor result; independently retained old results keep their old binding, coverage and ownership.
Do not silently replace an admitted profile's advertised guarantees with weaker ones.
Unsupported profile/schema admission must be explicit, while supported partial coverage and its reasons remain truthful under that profile.

The discriminating future check keeps source/parser identity fixed and changes only adapter build, registry binding or one observation feature: the context must change and derived index reuse must miss.
Further independent cases cover unavailable compound/marker observations with usable syntax/diagnostics; an available global capability with a local recovered gap; unknown/forged capability schemas; unsupported payload kinds versus partial supported indices; corrupt evidence; and retained old results across adapter replacement.
Assert exact binding equality/misses, admission/query outcomes and per-result coverage against independent expectations after implementation authorisation.
This matrix records the integration choices still requiring review; it does not approve instrumentation, a reconstruction adapter, policy defaults or the final API.

##### Compound Route Evidence and Binding Classification

Proposed producer-adapter refinement; neither parser instrumentation nor a reconstruction adapter is implemented here.
`parse_statement` can construct expression-led multi-target assignments for any operator reported at assignment precedence by `binary_operator_info`; it consumes that operator without storing it in the resulting compound's `operator_type`.
The declaration route instead records shared `=` reassignment, or takes the declaration-properties branch after expecting `:`.
Default `operator_type` and default target modifiers therefore cannot distinguish all produced compounds.

The proposed logical observation is `CompoundRoute`:

- `IDENTIFIER_HEAD {reassignment:bool}` records the actual `parse_declaration_node` branch decision for this compound, not a conclusion from the helper's eventual expression or scope bindings.
- `EXPRESSION_HEAD {operator_token:TokenTag}` records the assignment-precedence token consumed by the expression-led `parse_statement` builder function.
Preserve the exact token tag, including compound assignment operators; do not substitute the default stored `operator_type`.
- `UNCLASSIFIED {reason}` retains syntax with an explicit unavailable/ambiguous-route reason; it is not a declaration route with `reassignment=false`.

Bind each observation to this envelope's snapshot-local compound node ID, exact source revision and producer/context schema.
Retain the consumed/expected shared-separator origin as a separate `Origin` observation, with source-token correlation where a real token was consumed.
A missing expected `:` can be correlated to inserted-token recovery, not represented as an authored colon.
A captured branch decision may still describe recovered syntax; no observation certifies semantic validity.
Each compound has at most one coherent observation.
Reject conflicting observations or cross-snapshot IDs rather than picking the first; no raw producer pointer is an external identity.

| Qualified route | Binding and shared-region rule |
| --- | --- |
| `IDENTIFIER_HEAD`, `reassignment=false` | For each target in stored order, declare when its modifier is not `ASSIGN` (including explicit `DECLARE`); retain the declaration-properties/recovery observations. |
| `IDENTIFIER_HEAD`, `reassignment=true` | Declare only targets with explicit `DECLARE`; unmodified/`ASSIGN` targets are uses. |
| `EXPRESSION_HEAD` | No newly declared bindings.  Traverse the actual target expressions and shared RHS once; preserve the operator observation and create a shared region with an empty binding list when required to contain nested syntax. |
| `UNCLASSIFIED` or missing evidence | Preserve the compound/target/helper syntax and report partial index coverage for ambiguous binding classification.  Do not fabricate bindings or certify their absence from default fields. |

This is the existing predicate `(!reassignment && modifier != ASSIGN) || modifier == DECLARE` restricted to its owning construction route, not a new parser declaration rule.
Validate known modifier tags, target kinds/name observations and list alignment before emitting names.
An unexpected non-identifier target on the identifier-head route is a mapping mismatch, not a reason to cast an expression to `Parser_Ident` or extract a name from arbitrary spelling.
Expression-head targets can be members, subscripts or other expression shapes; labels/uses do not become declarations because their names match existing scope bindings.
Recovered names/holes preserve the common name/origin rules rather than manufacturing a well-formed spelled binding.
The route observation does not waive source-span, metadata or child-registry validation.

For producer integration, prefer recording the route at the successful construction point before the distinguishing operator/branch evidence is lost.
That would be a separately authorised capability change, not an edit authorised by this document.
An alternative adapter may reconstruct evidence only under a separately reviewed, producer-version-bound token/parse correlation that covers lookahead routing, nested delimiters, modifiers and recovery.
A raw scan for `:`/`=`, a nonnull/default-field test, or consulting lexical bindings is insufficient.
The current builder functions' comma-node intervals differ around the shared separator: the declaration builder function records its interval after consuming/expecting the separator, while the expression builder function finishes its comma node before consuming the assignment operator.
This is useful discriminating test evidence, not an approved route classifier: recovered spans, parser reuse and producer-version changes must not silently change binding meaning.

The discriminating future vector pairs `a, b := values` with an expression-headed member/subscript multi-target assignment whose compound operator field remains default; only the first can obtain implicit declared bindings.
Independent vectors must also cover ordinary identifier-head `a, b = values`, mixed explicit declare/assign modifiers, compound-assignment operators, repeated names, nested target/RHS expressions, missing separators/RHS, malformed targets, absent/conflicting route evidence and stale snapshot-bound observations.
Assert exact binding counts/order, source names/origins, empty versus populated shared-region associations, retained operator tags, recovery status and partial reasons against independent expectations and the actual fresh construction route.
This narrows the unresolved gap to route capability/correlation review and executable qualification; it does not claim that the current producer now meets it, add a service operation or authorise a parser/API migration.

##### Generated Layout Inventory and Registry Closure

Inventory baseline for the remaining exhaustive registry task, taken from `parser.jai`'s `TYPES` array.
It contains 50 distinct compiler layouts whose parser counterparts are generated; this is not a count of qualified reachable variants or a completed snapshot field schema.
Names below are exact `TYPES` members, grouped only for review.
Their `Parser_` counterparts follow the existing generator; neither a payload tag nor an active field mapping may be inferred merely from a layout name.

| Review group | Count | Exact generated-layout inputs |
| --- | --- | --- |
| Assembly | 1 | `Code_Asm` |
| Expressions/operators/types | 7 | `Code_Binary_Operator`, `Code_Cast`, `Code_Expression_Query`, `Code_Procedure_Call`, `Code_Type_Instantiation`, `Code_Type_Query`, `Code_Unary_Operator` |
| Blocks/control/using | 10 | `Code_Block`, `Code_Case`, `Code_Defer`, `Code_For`, `Code_If`, `Code_Loop_Control`, `Code_Push_Context`, `Code_Return`, `Code_Using`, `Code_While` |
| Declarations/aggregates | 5 | `Code_Comma_Separated_Arguments`, `Code_Compound_Declaration`, `Code_Declaration`, `Code_Enum`, `Code_Struct` |
| Procedure storage | 2 | `Code_Procedure_Body`, `Code_Procedure_Header` |
| Scalar/value forms | 5 | `Code_Context`, `Code_Ident`, `Code_Literal`, `Code_Note`, `Code_Placeholder` |
| Directives A-L | 10 | `Code_Directive_Add_Context`, `Code_Directive_Bake`, `Code_Directive_Bytes`, `Code_Directive_Code`, `Code_Directive_Context_Type`, `Code_Directive_Exists`, `Code_Directive_Import`, `Code_Directive_Insert`, `Code_Directive_Library`, `Code_Directive_Load` |
| Directives M-W and location | 10 | `Code_Directive_Location`, `Code_Directive_Modify`, `Code_Directive_Module_Parameters`, `Code_Directive_Overlay`, `Code_Directive_Poke_Name`, `Code_Directive_Procedure_Name`, `Code_Directive_Run`, `Code_Directive_Scope`, `Code_Directive_Through`, `Code_Directive_Wildcard` |

The direct `Parser_Node` builder function for `.DIRECTIVE_THIS` is an additional known kind route outside this list; do not invent a derived compiler-layout payload for it.
A total of 50 generated layouts plus this route is not proof that all supported parse roots/builder functions have been inventoried.
Non-node helper records also require separate field/variant coverage: struct/array literal info, call arguments/context modifications, compound arguments and assembly helpers are not extra entries in `TYPES` or automatically extra node IDs.
Generated overlays can expose compiler-only or inactive fields.
For each input, the remaining registry must bind actual constructed kind/source routes, every field's traversal role, active-form guards, null/recovery semantics, ordering and any alias owner; use the existing detailed route sections as evidence, not a substitute for that enumeration.
Mark a layout's reachability or field mapping unresolved when builder function evidence is incomplete.
Mere presence in `TYPES` cannot justify complete traversal, nor can absence from a test corpus justify excluding a builder function.

The focused inventory check compares this table's exact names with the live `TYPES` list, requiring equal sets, no duplicate names and the declared group counts.
That static check can validate inventory transcription now; it does not qualify builder function reachability, field ownership or a future visitor.
The exhaustive task remains open until the subsequent per-layout/base-kind/helper review supplies those mappings or explicit supported-profile exclusions, followed by independently authorised behavioural qualification.

##### Shared Base Fields and Direct Base-Only Kinds

Declared-field coverage for the common base, grounded in the `Code_Node` inventory, the `Parser_Node` declaration and the reviewed `#this` builder function.
These rows apply to every generated layout without duplicating its node ID or creating a base-to-derived traversal edge.

| Record / storage domain | Exact field roles |
| --- | --- |
| `Code_Node` / shared compiler base | `kind`: `NON_CHILD`, producer kind observation under the registered mapping, not a native ordinal wire tag.  `location`: `HELPER`, qualified source-location observation storage, not an authored node edge.  `node_flags`: `NON_CHILD`, registered source bits only, excluding typechecked/desugaring state.  `type`: `NON_CHILD`, inferred/compiler type excluded from syntax observations and descent.  `serial`: `NON_CHILD`, compiler bookkeeping excluded; never the snapshot node ID. |
| `Parser_Node` / parser-owned base | `first_token`: `NON_CHILD`, trivia-enabled token-interval start.  `one_past_last_token`: `NON_CHILD`, trivia-enabled exclusive end.  `code_node`: `HELPER`, embedded alternate compiler-base view of this same node, not another occurrence or an owned syntax child. |
| `Code_Node.Location` / nested compiler location | `enclosing_load`: `BACKREFERENCE`, compiler file/load provenance excluded from authored descent and owned syntax payloads.  `l0`: `NON_CHILD`, raw starting-line observation.  `c0`: `NON_CHILD`, raw starting byte-column observation.  `l1`: `NON_CHILD`, raw ending-line observation.  `c1`: `NON_CHILD`, raw exclusive ending byte-column observation.  These four producer coordinates are declared `s32`; their native representation is not a wire schema or an absolute source-byte interval. |
| Base route / `DIRECTIVE_THIS` | No additional layout-specific fields or authored children on the reviewed `#this` route.  Its builder function allocates `Parser_Node` directly, assigns the kind and finishes its source interval; it does not allocate a derived payload or attach a resolved receiver/declaration. |

The two token fields exist only under `ENABLE_TRIVIA`; the full-featured cache profile requires that configuration.
Their presence does not authorise reading nonexistent fields from a non-trivia producer, silently synthesising offsets from coordinates or treating an interval as a child edge.
Source-origin/range validation and qualified recovery/normalisation rules remain unchanged.
The nested location row enumerates all five fields of the installed compiler's `Code_Node.Location` declaration.
Its `#as using location` embedding and inherited coordinate aliases refer to the same observations, not another node, location occurrence or independently owned source range.
`finish_node` copies the four endpoint values from the first and last consumed tokens; retain those raw values under the existing source-origin/range rules rather than silently converting columns to characters or treating coordinates alone as exact byte offsets.
Empty/recovered/normalised builder functions still require their own qualified interval observations.
Do not copy the whole location record into owned syntax: that would retain compiler provenance alongside scalar coordinates.
Never dereference or serialise `enclosing_load`, and do not call compiler filename/location helpers to recover a filename during conversion; the protected source revision and captured syntax context supply qualified document/path identity.
A null load pointer is not proof of missing source, and a nonnull pointer is not proof of a captured dependency or retained compiler workspace.
Do not serialise opaque common storage, padding or overlay bytes.
Exact flag masks, location schemas and lifetime qualification remain open.
The reviewed base-only route retains an ordinary snapshot node ID at first downward encounter, even without a generated layout.
`#this` does not itself add a declaration-index entry or trigger receiver/context resolution.
Unknown base-only kinds require the established mapping outcome, not a guessed derived layout; this one reviewed builder function is not proof of a closed base-kind universe.
The focused static check compares all five inventoried compiler-base fields and all three declared parser-base fields, including the conditional token fields, and checks the direct `#this` construction shape.
This validates transcription only; exhaustive base-kind reachability, nested helper fields and executable visitor qualification remain open.
The location-specific static check separately compares all five nested declared fields and the four `finish_node` endpoint assignments.
It does not qualify other builder functions, reuse rebasing, coordinate-to-byte conversion, filename resolution or producer-teardown behaviour.

##### Direct Base-Node Builder Reachability

Bounded fresh-source audit of the literal `Parser_Node` allocation and its immediate directive-dispatch paths in `parser.jai`.
The current source has one explicit `new_parser_node(parser, Parser_Node)` call, in the `this` branch, and two direct call sites into `parse_expression_directive`.
This is a source-site inventory, not proof that generic allocation/copy paths or every supported parse root have been exhausted.

| Review site | Guard / forwarding path | Result / review boundary |
| --- | --- | --- |
| `parse_primary` / directive dispatch | After the hash token, require an identifier directive name; static-if-expression, type and here-string handling have their own routes.  Other identifier names forward to `parse_expression_directive(parser, first, directive_name.ident_value.name)`. | The `this` spelling can reach the direct base builder from primary-expression parsing.  Dispatch itself does not allocate a derived directive payload or resolve a receiver. |
| `parse_declaration_directive` / fallback dispatch | Require hash plus identifier, capture the current token index/name, then use the default directive branch to forward to `parse_expression_directive(parser, first, name)`. | The `this` spelling has no specialised declaration-directive branch in the reviewed source, so it can reach the same base builder.  This forwarding path does not make the result a declaration or prove grammar/semantic validity in every caller. |
| `parse_expression_directive` / `this` builder | Consume the two directive tokens, allocate `Parser_Node`, assign `DIRECTIVE_THIS`, call `finish_node`, then return that node. | No derived layout, attached child or resolved receiver is created by this branch.  Ordinary base-field and origin/range rules apply; only a node reached from the published syntax graph receives a snapshot-local ID. |

A returned allocation is not proof that an enclosing builder attaches it to a published root; callers may reject or discard syntax.
Do not discover declarations or node IDs by scanning the allocation pool, and do not promote an unattached directive to an index entry.
The focused static check compares the literal allocation count, both forwarding sites and the direct builder's shape with this table.
It must expose a newly added literal base allocation or forwarding site for review rather than silently assuming it has the same route.
The fresh-root attachment review below covers only its named entrypoints.
Other root-to-node paths, indirect/alternate allocation paths, fresh-versus-reuse equivalence, recovery attribution and independent behavioural qualification remain open; the 50-layout inventory plus this reviewed branch is not a closed node-kind universe.

Fresh attachment review for the bare `#this` directive follows the returned pointer through these owning paths.
This describes the parser's retained syntax, not semantic acceptance of a receiver directive in every context.

| Review site | Attachment / retention path | Result / review boundary |
| --- | --- | --- |
| `parseInit` / root assignment | Assign the selected root builder's return value to `parser.parsed.root`. | Common root retention, not a requirement that the root have declaration kind.  A null builder return remains null; allocation alone does not create a root. |
| `parse_declaration` / standalone root | Select `parse_declaration_node` as the root builder; the ordinary directive path can return the bare base node.  Terminator/notes/trailing-input handling inspects the retained result without replacing its root. | A declaration-named entrypoint can retain a non-declaration directive root.  Classify by the actual kind and registered route, not the entrypoint name; do not invent a declaration-index entry. |
| `parse_file_node` / fresh declaration fallback | After a failed reuse attempt, call `parse_declaration_node`; append each nonnull return to the statement list before `finish_statement`, then assign that list to the returned block. | The file root's owning statement list can retain the bare directive.  Later terminator diagnostics do not retroactively remove an appended node.  This does not qualify reuse admission or copy behaviour. |
| `parse_block_node` / ordinary non-enum blocks | Imperative blocks call `parse_statement`; declaration blocks use declaration parsing after any reuse attempt.  Append a nonnull return before `finish_statement`, then attach the list to the block. | The `parse_block` and `parse_declaration_block` root builders can retain the directive in the same owning list domain.  Missing opening braces return no block; enum-specific routes and all other enclosing contexts need their own review. |

For a bare hash directive, `parse_statement` returns the nonnull declaration-directive result directly.
Its explicit `#this(` exception instead enters the ordinary expression path, so the direct-leaf statement rule must not be applied to that spelling or used to discard potential expression wrappers.
The bounded simple-call attachment review below covers that exception; other expression-wrapper paths remain open.
Append-before-finish ordering is not recovery attribution: preserve exact tokens, raw node intervals and diagnostics without inferring that a missing terminator created or removed this node.
A failed builder return contributes no list entry; an allocated but discarded node remains outside the published graph.
The focused static check covers root-builder wiring, fresh file/block list attachment, the statement dispatch exception and retention through terminator handling.
It does not execute these inputs or qualify arbitrary enclosing wrappers, enum mode, incremental reuse, independent result ownership or declaration-index recovery attribution.

Fresh simple-call review for `#this(...)` in an imperative statement, without additional postfix/binary/comma wrappers:

| Review site | Forwarding / ownership path | Result / review boundary |
| --- | --- | --- |
| `parse_statement` / call-form fallback | The explicit hash/this/open-parenthesis exception skips direct declaration-directive return; the ordinary expression branch obtains `left` from `parse_binary` and returns it when no comma-led compound route is taken. | The returned expression, not a separately promoted bare directive, enters the already-reviewed imperative block statement list. |
| `parse_binary` and `parse_prefix` / simple expression forwarding | Binary parsing starts with `parse_prefix` and returns its left expression when no binary operator is selected; the ordinary non-prefix-operator case forwards to `parse_postfix`. | This restricted route introduces no extra unary/binary wrapper.  Prefix operators, explicit types, compound statements and additional operators require their own guarded routes. |
| `parse_postfix` / call suffix | Obtain the base directive from primary parsing, then pass it and the original starting-token index to postfix-suffix parsing.  An opening parenthesis replaces the current result with `parse_procedure_call(parser, result, first)`. | The call wraps the existing base node; it is not a derived payload for `DIRECTIVE_THIS` or a second parse of the directive tokens. |
| `parse_procedure_call` / callee ownership | After argument/context parsing and the closing-delimiter check, allocate `PROCEDURE_CALL`, assign the incoming node to `procedure_expression`, attach published unsorted arguments/context modification, finish and return the call. | The callee edge owns the base directive under the ordinary call mapping.  This is not the import-owned-call backlink exception, and no receiver/callee resolution is performed. |

The call and base directive have distinct snapshot-local node IDs and raw token intervals.
Follow the call's callee before its argument/context children under the registered traversal order; neither overlapping intervals nor the shared starting token justify merging nodes or emitting a declaration-index entry.
Further suffixes can wrap the call again and are outside this simple-call review.
The call builder can still publish its call after argument parsing fails, or a closing delimiter is expected.
Preserve the actual retained callee and completed argument/context records plus source/diagnostics; do not invent discarded arguments or flatten a recovered call to its bare callee.
Publication does not establish committed recovery ownership or complete index coverage.
The statement-specific exception does not alter standalone declaration or file declaration dispatch.
Do not infer the same call wrapper in those entrypoints solely from a matching source prefix.
The focused static check covers this statement-to-call forwarding and callee attachment shape, not semantic call validity, arbitrary expression roots, nested-wrapper completeness, incremental reuse or independent behavioural qualification.

The adjacent expression-reuse review establishes an exclusion, not another direct base-node builder route:

| Review site | Admission / copy rule | Result / review boundary |
| --- | --- | --- |
| `reusable_expression` / base-kind exclusion | Under `ENABLE_TRIVIA`, reject null and accept only the guarded identifier, literal, unary, expression-query, type-query, call, cast and binary shapes; unmatched kinds reach the final `false`.  There is no `DIRECTIVE_THIS` acceptance branch. | The bare directive is not admitted by this predicate.  Without trivia the predicate also returns `false`; fresh builder support does not imply reusable-expression support. |
| `reusable_expression` / call admission | Before checking arguments/context replacements, recursively test `call.procedure_expression` and reject the call if that test fails. | A simple ordinary call whose callee is the base directive is excluded by this gate as well.  Do not bypass the callee check because the outer call kind has a copier case. |
| `copy_reusable_expression` / guarded copy boundary | The call case recursively copies its callee before rebuilding argument/context storage.  There is no base-directive case; the unsupported-kind default asserts and returns null.  Supported cases then remap token endpoints and coordinates from the new token array. | This is not an opaque-node or raw-base-copy fallback.  Remapping supported nodes does not qualify copying `DIRECTIVE_THIS`, retaining old pointers, or copying pointer-bearing common fields into owned cache results. |

The current predicate/copier pair therefore supplies no approved reusable-expression clone of this base directive or its simple callee-owning call.
This is a conservative exclusion to preserve, not authorisation to add a copy case to complete the registry.
The focused static check compares the guarded kind sets, default rejection/assertion and recursive call-callee dependency.
It does not execute reuse, prove that every caller honours this gate, or close enclosing declaration admission, fresh-fallback publication, independent result ownership or recovery qualification.

##### Leaf Layout Field Roles: Context, Ident, Note and Placeholder

First field-role slice of the inventory above, using `compiler_fields.md`, the generated overlays and the current builder functions.
These four layouts have no authored downward children; `Code_Literal` is deliberately excluded because its aggregate arms have separate child/helper rules.
The following enumerates layout-specific fields, not a finished scalar/tag wire schema.
Common base fields and generated overlay storage follow the shared rules after the table.

| Parser layout / published kind | Exact layout-specific field roles and guards |
| --- | --- |
| `Parser_Context` / `CONTEXT` | No layout-specific field beyond the structural `base`.  The `KEYWORD_CONTEXT` primary builder function publishes this leaf; do not resolve or expand the current language context as a syntax child. |
| `Parser_Ident` / `IDENT` | `name`: `NON_CHILD`, exact owned producer bytes, correlated separately to token spelling/backtick state.  `flags`: `NON_CHILD`, only registered source-derived bits in syntax observations.  `resolved_declaration`: `BACKREFERENCE`, never traversed even when the parser has already populated it.  Identifier presence is not by itself an index declaration; enum-member, binding and other construction contexts remain distinct. |
| `Parser_Note` / `NOTE` | `text`: `NON_CHILD`, owned exact stored bytes.  `note_flags`: `NON_CHILD`, source-derived observations only, not processed/compiler bits.  `parse_declaration_notes` takes token identifier bytes and removes one terminal NUL when present; preserve the original token spelling separately rather than asserting that stored text equals a source slice.  Only notes attached to the published declaration/compound graph are visited. |
| `Parser_Placeholder` / `PLACEHOLDER` | Parser-added `name`: `NON_CHILD`; this field is not present in the compiler `Code_Placeholder` layout and must not be lost by copying only its embedded compiler overlay.  The declaration route consumes `#placeholder` and expects an identifier.  Qualify name bytes against that actual name token/route, not the node's first token or a zero/default identifier value after recovery.  This leaf is not an ordinary declaration-index entry. |

For each row, embedded `base` is structural `HELPER` storage of the same node, not a child occurrence or another node ID.
The parser's `code_node` and generated compiler-layout overlays are alternate storage views, not authored ownership edges; padding is not observable syntax.
Common `kind`, source locations and trivia-enabled token interval fields are `NON_CHILD` observations with the existing origin/range rules.
Common inferred `type`, `enclosing_load` and compiler identity/bookkeeping storage are excluded from authored descent; source versus processed `node_flags` still requires the exact registered mask.
No nonnull common/overlay pointer may create a child missing from these rows.
Traversal order is therefore empty for these four leaves; their own node ID still follows first registered downward encounter.

The placeholder builder function saves the peeked name token before `parser_expect`.
A missing identifier does not make the saved token's identifier union arm valid: the adapter must have qualified token-kind/construction evidence before treating the stored name as a trustworthy string.
If safe scalar conversion cannot be established, retain independently safe source/diagnostics and report the appropriate mapping/conversion outcome under the existing snapshot/index contracts; do not dereference an unqualified string value or invent an empty name.
An index-only partial state does not authorise an unsafe snapshot payload.
Likewise, the current note builder function's default flags are not proof that every possible `note_flags` bit is source syntax.
Exact `Ident.flags`, `Note.note_flags` and common flag-tag registries remain open in the payload-schema task; these field roles do not approve a raw native bitmask encoding.

The focused review vectors are `context`, a backticked identifier, an attached note with producer text distinct from spelling, and `#placeholder` with present versus missing/non-identifier name tokens.
Further qualification must preserve duplicate/equal-span identifier occurrences and reject traversal through deliberately populated `resolved_declaration`/common semantic pointers.
Independently owned name/text bytes must survive producer teardown.
This closes the draft field-role enumeration for these four layouts only.
Literal arms, exact scalar/flag schemas, exhaustive builder function reachability, producer-version review and executable visitor qualification remain open.

##### Operator, Cast and Query Layout Field Roles

Second field-role slice of the inventory: five layouts, using the compiler field inventory and the fresh builder functions in `parse_binary`, `parse_prefix`, `parse_postfix_suffixes` and `parse_primary`.
The structural base/overlay/common-field rules from the leaf slice apply unchanged.
Only the layout-specific fields below add downward edges; scalar tags/flags never imply extra children.

| Parser layout / published kind | Exact layout-specific field roles and visit order |
| --- | --- |
| `Parser_Unary_Operator` / `UNARY_OPERATOR` | `operator_type`: `NON_CHILD`, under the registered operator mapping rather than a native enum ordinal.  `subexpression`: `CHILD`, required on the reviewed published routes and visited once.  Prefix operators, leading-dot shorthand and postfix dereference use this same edge; preserve their distinct operator/source observations. |
| `Parser_Binary_Operator` / `BINARY_OPERATOR` | `operator_type`: `NON_CHILD`.  `flags`: `NON_CHILD`, registered source-derived bits only.  `left`: `CHILD`, then `right`: `CHILD`.  Ordinary binary, member-access and array-subscript routes retain their operator distinction; do not follow member-resolution/scope bookkeeping as another edge. |
| `Parser_Cast` / `CAST` | `cast_flags`: `NON_CHILD`, registered source-derived bits only.  `target_type`: `CHILD`, required for explicit casts and inactive/absent for the qualified auto-cast route.  `expression`: `CHILD`, required.  Prefix explicit order is target then expression; postfix explicit order is expression then target; auto-cast visits only expression. |
| `Parser_Expression_Query` / `EXPRESSION_QUERY` | `query_kind`: `NON_CHILD`, exactly `TYPE_OF`, `IS_CONSTANT` or `CODE_OF` on the reviewed routes.  `expression_to_query`: `CHILD`, required and visited once.  A query node records source syntax, not a computed type/constant/code result. |
| `Parser_Type_Query` / `TYPE_QUERY` | `query_kind`: `NON_CHILD`, exactly `SIZE_OF`, `TYPE_INFO` or `INITIALIZER_OF` on the reviewed routes.  `type_to_query`: `CHILD`, required and visited once; its parser-created type-instantiation wrapper retains its own node ID and then follows that layout's active-form rules. |

`parse_binary` publishes a binary node even when the right expression is missing, and array subscripts can likewise retain a null index.
Preserve a qualified required-child recovery hole and its observations; do not replace it with ordinary optional absence or dereference null.
The reviewed member-access route instead returns the existing expression when its member parse fails, with no new binary wrapper.
The same publication distinction applies to a failed postfix cast target; failed prefix/auto casts and query operands return null before allocating their result wrapper.
Retain only published graph occurrences, not a wrapper inferred from punctuation or an allocated-but-unattached intermediate operand.

Prefix `-` on a numeric literal can update and return that literal directly, so source minus does not prove a unary-node occurrence.
Grouping and equal-span wrappers likewise preserve the actual graph/IDs rather than manufacturing operator nodes.
Cast source-form order requires qualified `IS_AUTO`/`HAS_POSTFIX_SYNTAX` and construction evidence.
Conflicting/unregistered flag combinations or missing route evidence are not permission to traverse a nonnull inactive target; report the established mapping gap under the existing coverage contract.
The reviewed prefix modifiers set `NO_BOUNDS_CHECK`, `TRUNCATE`, `FORCE` and `VERY_FORCE`; preserving final source flags does not reconstruct repeated modifier occurrences.
Exact cast/binary flag masks and the complete operator-tag registry remain in the payload-schema task.
Unknown query tags are unmapped variants, not new evaluated capabilities.
Never execute these expressions, compute sizes/initialisers, follow inferred common types or use a query's eventual compiler result as an authored child.

The focused static check compares each row's role-labelled field names with its `Code_*` field inventory, excluding the shared `base`, to catch omissions/duplicates in this transcription.
It does not qualify route correlation or pointer safety.
Behavioural qualification still needs binary/index missing-right cases, failed member/cast/query publication, all six query tags, prefix/postfix/auto cast order, folded negative literals, separate wrapper IDs and semantic/inactive-pointer controls against independent expectations.
This completes draft layout-specific field-role enumeration for these five layouts, not their scalar wire registries, exhaustive builder function and reuse audit or executable visitor implementation.

##### Procedure-Call Layout and Argument Helper Field Roles

Third field-role slice: `Code_Procedure_Call` plus its parser-owned argument/context helpers, grounded in `parse_procedure_call` and the existing qualified import-parameter route.
Shared base/overlay rules apply.
The parser overlays compiler `context_modification` with `*Parser_Context_Modification`; do not decode that storage using the compiler's lowered representation.

| Parser layout / published kind | Exact layout-specific field roles |
| --- | --- |
| `Parser_Procedure_Call` / `PROCEDURE_CALL` | `procedure_expression`: `CHILD` on the ordinary call route; the registered import-parameter route instead treats its owning-import association as a non-owning backreference.  `arguments_unsorted`: `HELPER`, ordered `Parser_Argument` records.  `context_modification`: `HELPER`, optional parser-owned context storage.  `flags`: `NON_CHILD`, registered source-derived bits only.  `resolved_procedure_expression`: `BACKREFERENCE`.  `overloads`: `NON_CHILD`, semantic candidate storage.  `arguments_sorted`: `BACKREFERENCE`, post-resolution argument arrangement, not another authored list.  `num_return_values_received`: `NON_CHILD`, semantic count.  `macro_expansion_block`: `NON_CHILD`, generated syntax excluded from this authored traversal. |

| Parser helper / storage domain | Exact fields and downward order |
| --- | --- |
| `Parser_Argument` / non-node helper | `name`: `CHILD`, optional named-argument identifier, then `expression`: `CHILD`, required for each published argument.  Neither the record itself nor an absent name gets a node ID. |
| `Parser_Context_Modification` / non-node helper | `modification_expressions`: `CHILD_LIST`, in stored source order.  The helper is not a `Parser_Node` even though the builder function uses `new_parser_node` to allocate it; its expressions have ordinary node IDs. |

Ordinary call order is callee, each published argument's optional name then expression, then context-modification expressions.
The import-parameter callee association is recorded without descent under its previously specified owner/alias guard; it is not a general exemption for arbitrary call cycles.
An absent context helper is ordinary absence.
A present helper with no expressions can be the published recovered `,,` route: retain its empty list and qualified diagnostic/recovery observations instead of inventing a replacement expression or treating it as no clause.
The argument parser appends only after obtaining its expression.
A name allocated before a failed expression may remain unattached; do not emit that name through the call's argument list or infer a missing published argument from allocator contents.
Missing closing punctuation and partial context parsing follow the actual published graph/recovery evidence.
A known recovered list need not make traversal partial; missing route, child or recovery attribution still follows the existing coverage rules.
Do not reorder named arguments by spelling, replace authored arguments with sorted ones, inspect overloads to choose a callee, expand macros or apply the context modifications.
Preserve source flags such as the procedure-pointer-only request without executing it; the exact call-flag registry remains open.

The focused static check covers all nine layout-specific call fields, both argument-helper fields and the parser-only context-list field.
Builder function and ordering qualification remains separate: ordinary/named/context calls, empty recovered context, unattached failed names, import backreferences and populated semantic/generated fields require independent expectations after implementation authorisation.
This completes draft field-role enumeration for one further generated layout and two helpers, not a public accessor implementation or qualified call visitor.

##### Block Layout Field Roles

Field-registry slice grounded in `parse_block_node`, `parse_statement_block` and the parser-created quick/conditional blocks.
Shared base/overlay rules apply.

| Record / storage domain | Exact field roles |
| --- | --- |
| `Code_Block` / parser layout input | `parent`: `BACKREFERENCE`.  `block_type`: `NON_CHILD`, registered grammar-category observation.  `block_flags`: `NON_CHILD`, source-derived bits only.  `belongs_to_struct`: `BACKREFERENCE`.  `statements`: `CHILD_LIST`, published statement order.  `owning_statement`: `BACKREFERENCE`.  `members`: `NON_CHILD`, compiler member/resolution storage, not another source statement list. |

Visit `statements` once; lexical scope bindings and member tables do not supply missing statements or declaration identities.
An empty published list is valid, whereas an unattached failed statement remains described by source/diagnostics rather than an invented node.
The parser's progress/recovery loop can skip input between attached statements.
Preserve that recovery evidence and any established coverage gap without inserting skipped text as an AST statement or claiming there was no syntax there.
Parser-created single-statement, quick-body and conditional blocks retain their own node IDs and qualified origin rules; the absence of authored braces does not make them backlinks or permit deleting the block.
Do not infer authored delimiters from `IS_PARENTHESIZED` or default block flags alone.
The static check covers all seven layout-specific fields.
Exact block-category/flag schemas, complete builder function and reuse reachability and behavioural statement/alias qualification remain open.

##### Declaration Metadata, Using Order and Registry Review Gate

Proposed consolidation of the authored-edge draft, grounded in declaration properties/metadata/notes, `parse_using_statement_after_keyword`, and the base-node `#this` builder function.
This completes another draft slice, not producer review or permission to claim complete traversal.

For exhaustive layout-specific field coverage, the three generated declaration/compound layouts and their structural entry/argument records have these roles.
Shared base/overlay rules apply; embedded scope-entry storage is part of the same node, not a new node occurrence.

| Record / storage domain | Exact field roles |
| --- | --- |
| `Code_Declaration` / parser layout input | `entry`: `HELPER`, embedded scope-entry storage.  `type_inst`: `CHILD`, grammar-qualified optional or recovered required type.  `expression`: `CHILD`, grammar-qualified published initialiser.  `flags`: `NON_CHILD`, registered source bits only.  `alignment_expression`: `CHILD`, only when a qualified metadata route publishes it.  `notes`: `CHILD_LIST`, attached note nodes in stored order.  `program_export_name`: `NON_CHILD`, owned final producer bytes, distinct from correlated occurrence metadata. |
| `Code_Compound_Declaration` / parser layout input | `entry`: `HELPER`, embedded storage, not one authoritative name for the binding group.  `comma_separated_assignment`: `CHILD`, real structural comma-arguments node.  `declaration_properties`: `HELPER`, parser-node storage with its own snapshot ID but no standalone declaration-index entry.  `alignment_expression`: `CHILD`, compound-owned metadata.  `notes`: `CHILD_LIST`, compound-owned attached notes.  `operator_type`: `NON_CHILD`, qualified producer observation, not a universal binding-route classifier. |
| `Code_Comma_Separated_Arguments` / parser layout input | `arguments`: `HELPER`, ordered parser-owned compound-argument records.  The containing comma node has its own node ID; individual argument records do not. |
| `Code_Scope_Entry` / embedded structural helper | `name`: `NON_CHILD`, owned producer bytes when the qualified declaration route supplies them; do not replace a compound's per-binding names with this embedded field.  `import_target`: `BACKREFERENCE`, compiler/import association excluded from authored descent.  Its embedded base follows the shared same-node structural rule. |
| `Code_Comma_Separated_Argument` / parser-owned helper counterpart | `node`: `CHILD`, authored target occurrence, then `modifier`: `NON_CHILD`, registered per-target declaration/assignment observation, not an instruction to perform binding. |

The field rows do not override the earlier binding-group event order or route evidence.
A compound emits only the bindings justified by its qualified identifier/expression construction route, while target expressions retain their actual syntax and outer container.
The properties helper follows declaration field guards only in its compound-helper context: do not derive an independent name, scope entry or source origin from its zero/default fields.
Unexpected helper-owned alignment/notes remain the explicit mapping gap described below.
The static coverage check compares all five rows with their compiler inventory records, excluding shared `base`; role-labelled `entry` fields remain included.
This completes draft field-role enumeration for three more generated layouts and the listed helpers, not exact source-flag/modifier schemas, producer-route qualification or semantic binding.

For an ordinary declaration, traverse optional `type_inst`, published `expression`, published `alignment_expression`, then attached `notes[]` in source order.
Type and initialiser presence follow the qualified declaration grammar/recovery route: an inferred declaration legitimately omits `type_inst`, and a typed declaration without an initialiser legitimately omits `expression`.
The `---` route can clear the expression and retain `IS_UNINITIALIZED`; do not invent a literal node to fill that absence.
Names, flags and `program_export_name` are scalar observations, not extra children.

For a compound, first retain/visit the `comma_separated_assignment` structural node and its ordered target nodes; it is a real parser node even though it emits no independent index declaration.
Then descend once into the shared properties' type/expression, the compound's alignment and the compound's attached notes, under the shared-region container policy.
The reviewed builder function passes `*result.alignment_expression` to `parse_declaration_metadata` while keeping type/initialiser/export data in `declaration_properties`.
`parse_declaration_notes` attaches notes to the compound, not its properties helper.
Do not copy those fields into every binding or assume they already alias fields on the helper.
Unexpected populated helper alignment/notes require a reviewed route/alias rule or a partial mapping reason, not guessed ownership.
The properties helper remains a real parser-node observation with a snapshot-local ID, despite having no independent authored declaration entry or reliable finished source span.
Role `HELPER` does not erase the identity of storage that is itself a `Parser_Node`; non-node auxiliary helpers still have no ordinary node ID.

Repeated `#align` metadata can replace an earlier published alignment expression; note parsing also materialises note text separately from token spelling.
Preserve the final attached expression, scalar/byte observations and exact source/diagnostics.
Do not reconstruct overwritten nodes, infer all metadata occurrences from final fields, or merge note bytes with identifier-interner identity.
Unknown directive boundaries and required-child recovery need qualified correlation; do not let an absent final field prove a source clause never occurred.

For ordinary `Using`, visit the optional `filter_expression` before the target `expression`, matching the builder function's prefix filter parsing.
Keep filter kind and `#as`/marked-declaration observations without evaluating a map, resolving members or expanding names.
A using target parsed as a declaration follows declaration indexing; an expression target is not promoted to a binding.
Parameter-using targets remain the registered non-owning aliases from the procedure rules; the same field name does not imply the same role in every context.
The lexical scope's `usings` list is an auxiliary registry, not a second ownership path.
Missing consumed-filter/target expressions retain recovery observations instead of becoming equivalent to no filter/target request.

Registry review has the following concrete closure gate:

1. Inventory every node kind and auxiliary variant actually reachable from each supported parse root/route, including direct base-node allocations such as `.DIRECTIVE_THIS`.
Comparing only the 50 generated `TYPES` entries inventoried above is insufficient.
2. Classify every bound producer field as a guarded child/list/helper, a non-owning association/backreference or scalar/inactive data; retain the source observations needed to distinguish absence, recovery and discarded syntax.
Unknown fields/variants and ambiguous routes remain explicit partial reasons.
3. Review each alias with its exact owner/target guard and one downward traversal owner.
In particular, parameter usings, import callees and arrow-run block aliases are different rules, not a generic visited-set exemption.
4. Resolve or explicitly exclude compound construction-route ambiguity, unsupported declaration markers, source-slot/name origins and uncorrelated metadata/ordering routes.
A documented gap is not reviewed complete coverage; any exclusion must be reflected in the advertised profile and per-result coverage.
5. After implementation authorisation, qualify exact node/entry/region counts, paths/order, origins, alias targets, recovery/partial reasons and owned lifetimes against independently authored expectations plus fresh owned parser output under C1/C5.

The cheap discriminating vectors are a prefix-filtered using whose filter precedes its target, a compound with alignment/notes stored on the compound rather than the properties helper, and `#this` reached without a generated concrete type.
Document whitespace/diagnostics or a match against the current field inventory do not satisfy this gate.
The draft now names these cases, but no visitor, complete-coverage adapter or behavioural acceptance tests are implemented here.
R2/R6-R8, exact API/schema review and implementation/migration authorisation remain unchanged.

##### Directive Payloads and Registered Backreferences

For exhaustive field-role coverage, the directive layouts below use the shared base/overlay rules.

| Record / storage domain | Exact field roles |
| --- | --- |
| `Code_Directive_Add_Context` / parser layout input | `expression`: `CHILD`, declaration-grammar payload, with qualified recovery handling when the published directive lacks its required payload. |
| `Code_Directive_Overlay` / parser layout input | `target_expression`: `CHILD`, required parenthesised target, then `declaration_or_using`: `CHILD`, required payload traversed by its actual published kind.  Preserve required-child recovery; do not apply the overlay or resolve its target. |
| `Code_Directive_Modify` / parser layout input | `block`: `CHILD`, required authored block; retain the missing-opening-brace diagnostic and qualified missing-body observation instead of manufacturing a block. |
| `Code_Directive_Run` / compiler layout input | `flags`: `NON_CHILD`, registered source/parser bits only.  `assertion_string`: `NON_CHILD`, no populated source-message route on the reviewed builder functions; compiler-generated/evaluated messages are not source observations.  `procedure`: `CHILD` only on the qualified source arrow-header route below; unrelated lowered/compiler procedures remain excluded. |
| `Parser_Directive_Run` / parser-added storage | `expression`: `CHILD` on ordinary expression/block routes, but a non-owning body-block association on the qualified arrow-header route.  Validate that alias against this header's body identity; never descend twice or infer ownership from nonnull storage alone. |
| `Code_Directive_Insert` / parser layout input | `expression`: `CHILD`, required published payload, including a qualified implicit-run wrapper for arrow syntax.  `scope_redirection`: `CHILD`, optional source prefix.  `break_replacement`: `CHILD`, optional published replacement statement.  `continue_replacement`: `CHILD`, optional published replacement statement.  `remove_replacement`: `CHILD`, optional published replacement statement.  `expansion`: `NON_CHILD`, generated expansion excluded.  `is_internal`: `NON_CHILD`, internal generated bookkeeping excluded from source observations.  Enumeration order is not visit order: use the prefix/clause/payload ordering and recovery rules below. |
| `Code_Directive_Location` / parser layout input | `expression`: `CHILD`, optional non-caller argument, with consumed-but-missing argument recovery distinguished from empty parentheses.  `is_caller_location`: `NON_CHILD`, source route discriminator; caller syntax has no expression child. |
| `Code_Directive_Procedure_Name` / parser layout input | `argument`: `CHILD`, optional parenthesised expression; empty parentheses are legitimate absence, unlike a recovered failed expression. |
| `Code_Directive_Poke_Name` / compiler layout input | `name`: `NON_CHILD`, owned identifier-value bytes, not an identifier node.  `module_struct`: `NON_CHILD`, compiler interpretation excluded; the parser-owned overlay below is the only source view of this slot. |
| `Parser_Directive_Poke_Name` / parser overlay view | `module_expression`: `CHILD`, required postfix-expression payload with qualified recovery handling.  This overlays the compiler slot, not an additional allocation or second owning edge; never read the same storage as a resolved struct. |
| `Code_Directive_Module_Parameters` / parser layout input | `module_parameters`: `CHILD`, optional first source procedure-type header.  `program_parameters`: `CHILD`, optional second header on the consumed first-header route.  `common_code`: `CHILD`, optional trailing or block-only source block.  Visit in that order; empty/block-only forms are legitimate, while consumed-but-recovered headers retain their distinct evidence. |
| `Code_Directive_Context_Type` / parser layout input | No layout-specific fields; shared `base` only.  This is the authored `#Context` occurrence, not the completed context type or a member list. |
| `Code_Directive_Scope` / parser layout input | `scope_type`: `NON_CHILD`, source distinction among module/internal, export and file directives.  Apply the existing same-statement-list syntax rules, not inferred effective visibility or semantic scope links. |
| `Code_Directive_Through` / parser layout input | No layout-specific fields; shared `base` only.  Preserve a published standalone directive occurrence; case-parser consumption into a fallthrough marker does not manufacture another node. |
| `Code_Directive_Wildcard` / parser layout input | `index`: `NON_CHILD`, unassigned/default on the reviewed source builder function, not an inferred source ordinal or resolved binding index.  The published wildcard has no authored child. |
| `Code_Directive_Import` / parser layout input | `name`: `NON_CHILD`, owned decoded source bytes, including a qualified transient `#string` value.  `flags`: `NON_CHILD`, registered source bits only.  `module_parameters_call`: `CHILD`, optional first parameter call.  `program_parameters_call`: `CHILD`, optional second parameter call.  `import_type`: `NON_CHILD`, qualified source modifier observation where assigned by this parser, not permission to import or infer a resolved kind. |
| `Code_Directive_Load` / parser layout input | `short_name`: `NON_CHILD`, owned source string-token value.  `load_flags`: `NON_CHILD`, registered source observations only; the reviewed builder function leaves them at their defaults.  `fully_pathed_filename`: `NON_CHILD`, resolved external path excluded.  `loaded_string`: `NON_CHILD`, externally loaded content excluded. |
| `Code_Directive_Library` / parser layout input | `name`: `NON_CHILD`, owned source string-token value.  `library_flags`: `NON_CHILD`, registered source bits only, never resolved/linker state. |
| `Code_Directive_Bytes` / parser layout input | `expression`: `CHILD`, published binary-expression-grammar payload, with required-child recovery handling. |
| `Code_Directive_Exists` / parser layout input | `query_expression`: `CHILD`, required query expression.  `sync_expression`: `CHILD`, optional comma-introduced expression, required or recovered once that separator is consumed. |
| `Code_Directive_Bake` / parser layout input | `procedure_call`: `CHILD`, only the published call accepted by the bake builder function.  `bake_type`: `NON_CHILD`, source distinction between dynamic specialisation, constants bake and parameter-value bake requests. |
| `Code_Directive_Code` / parser layout input | `expression`: `CHILD`, ordinary/typed payload only; inactive on qualified null/caller routes.  `code_flags`: `NON_CHILD`, registered source observations, excluding processed/compiler state. |

The context slice enumerates one layout-specific field across two layouts.
Traverse the published add-context payload under the current authored container; do not merge contributions, resolve context membership or follow a computed type.
Preserve the directive and its recovery evidence when payload parsing fails, rather than inventing an empty declaration.
Exact schema tags, complete builder function and reuse closure and independent behavioural qualification remain open.

The bake/code slice enumerates four layout-specific fields across two layouts.
Keep the distinction between a rejected non-call bake payload and a published call with its own recovery.
Do not rediscover a rejected expression in parser pools.
Code payloads retain their actual block/declaration/expression kind; legitimate null/caller absence is not a recovered required hole, and a missing ordinary/typed payload is not a null-code request.
The exact source flag/tag encodings, full builder function and reuse closure and executable route qualification remain open.

The bytes slice enumerates its one layout-specific field.
Preserve the actual published expression and any required-payload recovery; do not evaluate it, materialise a byte sequence or infer a missing literal from the directive name.
The directive and child keep distinct node IDs even when recovery makes their source intervals overlap.
Full builder function and reuse closure and independent behavioural qualification remain open.

The exists slice enumerates two layout-specific fields, visited query then sync.
Parenthesis/comma and diagnostic correlation distinguish a missing required query, legitimate no-sync absence and a recovered missing sync expression; null fields alone do not establish these forms.
Preserve both published subtrees without executing the query, blocking for synchronisation or asserting semantic existence/absence.
Complete builder function and reuse closure and executable recovery/ordering qualification remain open.

The import/load/library slice enumerates 11 layout-specific fields across three layouts.
Import calls are visited module then program, with each call's import-callee association qualified by the identity rule below; missing/empty call arguments use ordinary call recovery rather than a fabricated imported document.
Import `file`/`dir`/`string` modifiers can set `import_type` directly on this source parser route, despite that field's general compiler-phase inventory category.
Preserve this qualified observation without reading unrelated resolved state.
Names require owned-byte and source-token correlation: an empty decoded name is not proof of a missing string token.
Consumed modifier order/repetition is not reconstructed from final flags; in particular, the reviewed library builder function accepts `link_always` but leaves `LINK_ALWAYS` clear.
Do not load content, canonicalise a requested path into a resolved result or link a library during syntax traversal.
Exact scalar/flag schemas, full builder function and reuse closure and executable alias/lifetime qualification remain open.

Proposed refinement of `jai-cache-authored-edges/1`, grounded in `parse_declaration_directive` and `parse_expression_directive`.
Directive nodes describe authored requests, not their execution, imports, evaluated values or generated expansions.
Register the route-specific exceptions below before applying generic call/header traversal.

| Directive / guarded route | Active child order and observations |
| --- | --- |
| `Directive_Add_Context`, `Directive_Bytes` | `expression`; add-context uses declaration grammar, bytes uses expression grammar.  Index authored declarations reached there without completing or modifying the language context. |
| `Directive_Overlay` | `target_expression`, then `declaration_or_using`.  The latter follows its actual node kind; do not resolve the target or apply an overlay. |
| `Directive_Modify` | `block`; retain missing-block recovery rather than creating an empty authored block. |
| `Directive_Module_Parameters` | Optional `module_parameters`, optional `program_parameters`, optional `common_code`, in that order.  Empty/block-only forms are actual builder function routes, not necessarily recovery. |
| `Directive_Import` | Optional `module_parameters_call`, then optional `program_parameters_call`; apply the import-callee association rule below.  `name`, import-kind/modifier flags and decoded source text are scalar observations, not child nodes or filesystem membership. |
| `Directive_Load`, `Directive_Library` | No authored node children on reviewed routes.  `short_name`/`name` are string token values; library flags are scalar.  Loaded strings, resolved paths and linked libraries are not descent targets. |
| `Directive_Poke_Name` | Parser-preserved `module_expression`; `name` is scalar identifier bytes, not a `Parser_Ident` child.  Do not follow the compiler-facing `module_struct` interpretation of the overlaid field. |
| `Directive_Procedure_Name`, `Directive_Exists` | Optional `argument`; `query_expression` then optional `sync_expression`, respectively.  Correlate consumed delimiters to distinguish valid absent arguments from recovered missing expressions. |
| `Directive_Location` | `expression` only when published by the non-caller route; `#location()` can be empty and `#caller_location` has no expression.  The scalar caller flag does not resolve a location. |
| `Directive_Code` | `expression` on the ordinary/typed route; no payload on the qualified `#code,null` or `#caller_code` route.  Preserve source flags and the actual block/declaration/expression payload kind without expansion. |
| `Directive_Run`, ordinary expression/block route | Parser-added `expression`; do not follow an unrelated compiler-lowered/evaluated `procedure`.  Assertion messages and execution flags, where produced, remain scalar observations. |
| `Directive_Run`, qualified arrow-header route | Source `procedure` header, then its ordinary header/body/block ownership; `expression` is a non-owning alias to `procedure.body_or_null.block` when that body exists.  Do not visit that block twice or omit source return/header syntax. |
| `Directive_Insert` | Optional `scope_redirection`, then published break/continue/remove replacement statements in authored clause order, then `expression`.  Arrow payloads use the parser-created implicit-run wrapper and its arrow-header rule; never follow generated `expansion`. |
| `Directive_Bake` | Published `procedure_call` only, retaining `bake_type`.  A parsed non-call rejected by this builder function is not an attached child to rediscover. |
| `Directive_Scope`, `Directive_Through`, `Directive_Wildcard`, `Directive_Context_Type` | No authored node children on these routes; retain scalar/source observations.  Source forms lowered to literals follow the literal registry instead of fabricated directive children. |

For an import-owned parameter call, `parse_procedure_call(parser, result, first)` sets `procedure_expression` to the owning import node itself.
Register that field as a non-owning association only when this exact call is attached as the import's module/program parameter call and its callee is pointer-identical to that import while the producer is owned.
Retain the import's existing node ID as association target, skip callee descent, then visit the call's argument/context helpers normally.
This is not an active-path cycle failure and not permission to skip arbitrary recursive call expressions.
A mismatched callee/owner requires a mapping reason; do not repair it by names, source spans or selecting another import.

For arrow `#run`, including the `SYNTACTICALLY_IMPLICIT` run allocated for an arrow `#insert` payload, qualify the source-header route through its actual construction and body/expression identity.
`procedure` here is source syntax, despite the compiler inventory's general classification of lowered run procedures.
The block alias is non-owning only when it matches this header's body block; an unexpected second expression is not silently discarded or globally deduplicated.
If the source header has no body, retain its returns/flags and missing-payload observations even though `expression` is null.
Normalisation wrappers are not authored extra `#run` tokens or missing-token recovery insertions.

Insert replacements are stored in named fields rather than a clause list; correlate their source intervals with consumed replacement clauses to establish order.
If order cannot be established, use break/continue/remove only as a deterministic fallback with an explicit partial-ordering reason, not a claim of authored order.
Repeated or unrecognised replacement clauses can parse statements without retaining each one in those fields.
Traverse published children only, preserve source/diagnostics and do not claim to have inspected discarded subtrees.
Do not sort the payload's whole-directive-start wrapper interval ahead of its prefix modifiers; the qualified construction establishes modifier-before-payload order.

Scalar directive strings/names need owned-byte lifetime and source/value correlation, not pointer traversal.
In particular, an import's `#string` expression can be parsed transiently, and only its bytes stored in `name`; do not invent an attached literal node or loaded document.
Unknown directives can remain unconsumed for caller recovery.
Preserve that recovery and any unmapped region explicitly, never infer support from an identifier's spelling in arbitrary source text.
Optional payload absence versus recovered required holes follows route/delimiter/diagnostic observations; complete parsing is not evidence that an unreviewed route or generated field is authored syntax.

The discriminating future vectors are an import with parameter calls whose callee points back to the import, and arrow `#run`/`#insert` payloads whose expression aliases the source-header body block.
Further independent cases cover both import parameter lists; decoded/here-string names; poke-name scalar spelling; null/caller/typed code routes; optional location/procedure-name/exists arguments; module-parameter header/block combinations; reordered/repeated insert clauses; missing arrow bodies; rejected bake non-calls; and populated generated/resolved fields.
Assert exact visit paths/order, node IDs and alias targets, retained source headers/scalars, excluded external work and partial reasons against independent expectations.
All route/alias qualification and executable visitor tests remain open; this specification refinement performs no directive execution or production change.

##### Call Arguments, Operators and Cast Source Order

Proposed refinement of `jai-cache-authored-edges/1`, grounded in `parse_binary`, `parse_prefix`, `parse_postfix_suffixes` and `parse_procedure_call`.
Traverse the published parse shape, not a reconstructed precedence tree, inferred evaluation order or resolved call signature.

| Form / guard | Active child order and observations |
| --- | --- |
| `Procedure_Call` | `procedure_expression`, then `arguments_unsorted[]` in stored order, then the optional `context_modification` helper's `modification_expressions[]` in stored order.  Context expressions follow the consumed `,,` boundary, not a merged or sorted argument list. |
| `Parser_Argument` in a call | Optional `name`, then `expression`.  The name is a source `Parser_Ident` for the consumed `IDENT =` label; it is not a declaration, assignment target or resolved formal-parameter reference. |
| `Unary_Operator` | `subexpression`, preserving the source operator observation.  Prefix and postfix dereference remain their actual producer operator tags; do not derive a synthetic binary child from their punctuation. |
| `Binary_Operator` | `left`, then `right`, including member access, subscripting and assignment expressions.  The right child may be a mapped recovered hole; do not turn the left subtree into a different expression merely because recovery failed on the right. |
| Prefix explicit cast | `target_type`, then `expression`, as constructed by the `cast(...)` route; retain its source cast flags. |
| Postfix explicit cast | `expression`, then `target_type` when `HAS_POSTFIX_SYNTAX` identifies the reviewed `value.(T)` route.  This reverses the prefix cast's order and therefore affects first-encounter node IDs. |
| Auto cast | `expression` only on the `IS_AUTO` route; absent `target_type` is intentional, not a missing explicit type. |

Validate cast route and reviewed source flags together.
Conflicting/unqualified auto/postfix forms or unexpected children require a partial mapping reason rather than a priority guess; inferred type data never supplies an absent target child.
`parse_prefix` folds a directly recognised negative numeric literal into the literal's numeric value/flags and source interval.
There is no published unary-minus node to visit in that case; preserve the resulting integer/float bits, flags and raw spelling without manufacturing one.
Conversely, non-folded unary expressions retain their actual `Unary_Operator` node.
Similar spelling does not justify merging these shapes or assuming a common child count.

Named-argument identifiers are attached only when their expression is successfully parsed and the argument is appended.
A failed argument may have allocated a name without publishing it; preserve source/diagnostics, not a pool-discovered phantom argument.
An absent `context_modification` is different from a published helper with an empty list after `,,` recovery.
The latter preserves the boundary and diagnostic, not an invented context argument or successful semantic replacement.
Argument and context-modification helpers are not independent `Parser_Node` occurrences and receive no ordinary node IDs; their attached identifier/expression nodes do.
No helper by itself creates an index entry/container.
Declarations reached inside expressions follow their own reviewed grammar mappings; named labels and ordinary assignment targets are not promoted to declarations.

`parse_binary` and subscripting can publish a null right child after recovery; retain the precise field-path hole and available diagnostics.
A fully mapped recovered hole does not automatically make traversal partial, whereas missing route/origin evidence does.
Some failed postfix member/cast suffixes instead return the already parsed expression without publishing an access/cast wrapper.
Do not reconstruct those missing wrappers from consumed punctuation or extend the returned node's raw span to hide the difference.
Parenthesised expressions can reuse the same expression node with an expanded interval/`IS_PARENTHESIZED`; no separate group node is implied.
Keep actual producer identities and source observations.

Exclude `arguments_sorted`, `resolved_procedure_expression`, overload collections, received-return counts, macro-expansion blocks and common inferred type pointers from authored descent.
Member-access scope registries and identifier resolution pointers are also non-owning; a member-name flag or assignment operator is not proof of a binding declaration.
Call-local context expressions are syntax only: do not activate an allocator/context, execute the call or infer the completed language `#Context` descriptor while traversing them.

The discriminating future vectors are equivalent prefix/postfix cast forms with opposite authored child order, and `f(name=value,, allocator=arena)` with separate name/value/context visits.
Further independent cases cover empty/recovered context lists, repeated argument labels, failed unattached named arguments, nested call/member/subscript chains, null recovered binary/index children, failed postfix wrappers, auto casts, folded versus non-folded negative expressions, parenthesised node reuse and populated semantic-call fields.
Assert exact visit paths/order, node IDs, recovery observations, index exclusions and partial reasons against independent expectations.
Operator/cast flag encodings and executable visitor qualification remain open; this draft changes no parser behaviour.

##### Control-Flow Forms, Prefix Expressions and Branch Blocks

Proposed refinement of `jai-cache-authored-edges/1`, grounded in the conditional/case, while/for, statement-block, defer and push-context builder functions.
For exhaustive field-role coverage, the conditional/loop layouts have the following rows.
Shared base/overlay rules apply; route-dependent order and optional-versus-recovered absence follow the form table below.

| Record / storage domain | Exact field roles |
| --- | --- |
| `Code_If` / parser layout input | `condition`: `CHILD`, required condition with recovery evidence.  `then_block`: `CHILD`, branch or switch-case block.  `else_block`: `CHILD`, route-qualified optional/required branch.  `if_flags`: `NON_CHILD`, registered source/parser bits.  `static_if_flags`: `NON_CHILD`, registered source observations only, not evaluation state.  `static_if_accepted_case`: `NON_CHILD`, evaluated selection excluded from authored traversal. |
| `Code_Case` / parser layout input | `condition`: `CHILD`, absent for a qualified default case or a recovered condition under distinct evidence.  `then_block`: `CHILD`, published case-body block.  `owning_if`: `BACKREFERENCE`.  `marked_as_fallthrough`: `NON_CHILD`, consumed source marker observation. |
| `Code_While` / parser layout input | `condition`: `CHILD`, then `block`: `CHILD`, with required-child recovery handling. |
| `Code_For` / parser layout input | `iteration_expression`: `CHILD`, required collection/range start.  `iteration_expression_right`: `CHILD`, consumed range-end route only.  `block`: `CHILD`, body.  `ident_it`: `CHILD`, optional explicit iterator occurrence.  `ident_it_index`: `CHILD`, optional explicit index occurrence.  `want_replacement_for_expansion`: `CHILD`, optional authored expansion request.  `want_pointer_expression`: `CHILD`, qualified dynamic prefix.  `want_reverse_expression`: `CHILD`, qualified dynamic prefix.  `for_flags`: `NON_CHILD`, registered source bits.  `ident_decl`: `NON_CHILD`, generated iterator declaration.  `index_decl`: `NON_CHILD`, generated index declaration.  `macro_expansion_procedure_call`: `NON_CHILD`, generated expansion storage. |
| `Code_Loop_Control` / parser layout input | `control_type`: `NON_CHILD`, source `BREAK`, `CONTINUE` or `REMOVE` distinction.  `target_ident`: `CHILD`, optional authored target reference, never a resolved loop/declaration edge. |

The static check covers all 26 layout-specific fields across these five layouts.
Table order does not replace the source-form traversal sequence, and source marker/flag observations do not authorise branch evaluation or loop expansion.
Exact scalar/flag schemas, duplicate-prefix correlation, full builder function and reuse closure and executable qualification remain open.

The remaining statement-layout slice makes return/defer/push-context/using fields explicit under the same shared rules.

| Record / storage domain | Exact field roles |
| --- | --- |
| `Code_Return` / parser layout input | `arguments_unsorted`: `HELPER`, ordered `Parser_Argument` records using the earlier helper mapping.  `return_flags`: `NON_CHILD`, registered source/parser bits including qualified quick-body normalisation.  `arguments_sorted`: `BACKREFERENCE`, post-resolution arrangement excluded from authored descent. |
| `Code_Defer` / parser layout input | `block`: `CHILD`, published deferred statement block with required-child recovery handling.  `is_backticked`: `NON_CHILD`, source keyword observation. |
| `Code_Push_Context` / parser layout input | `to_push`: `CHILD`, qualified optional source expression.  `block`: `CHILD`, non-`DEFER_POP` body route only.  `push_context_flags`: `NON_CHILD`, registered source bits; do not apply the requested context change. |
| `Code_Using` / parser layout input | `expression`: `CHILD` on the ordinary using route, but a non-owning argument association on the qualified parameter-using route.  `filter_type`: `NON_CHILD`, registered source filter observation.  `filter_expression`: `CHILD`, qualified optional or recovered filter, visited before the ordinary target.  `no_parameters`: `NON_CHILD`, producer scalar observation under its qualified route, not evidence of resolved membership. |

The reviewed return builder function appends only completed expression records, with no argument-name nodes; a populated name requires a qualified additional route rather than inference from shared helper storage.
Empty returns and the existing quick-body recovered return-argument list remain distinct source/normalisation observations.
For using parameters, the header's owning argument list supplies the target's sole descent; ordinary `Using.expression` remains owning.
The lexical scope's using registry is not a second traversal path.
The static check covers all 12 layout-specific fields in these four rows.
Optionality, `DEFER_POP`, consumed-but-missing filters/targets and helper lifetime checks follow the existing route contracts, not tests of whether any pointer happens to be nonnull.
Exact scalar/flag schemas and independent behavioural qualification remain open for this statement slice too.

The ordering below is authored traversal order, not execution order or evidence of an active compile-time branch.
Conditions can themselves be declarations through `parse_condition`; do not restrict them to expression-only leaf forms.

| Form / guarded route | Active child order and observations |
| --- | --- |
| Ordinary `If` and static `#if` | `condition`, `then_block`, optional `else_block`.  Traverse both published branches; preserve `IS_STATIC` without evaluating conditions or following `static_if_accepted_case`. |
| `ifx` and static `#ifx` | `condition`, `then_block`, `else_block` when published.  Preserve `IS_IFX`/`IS_STATIC`; expression branches may be wrapped in blocks by `parse_ifx_branch`.  A missing branch must retain grammar/recovery observations rather than become an empty fabricated expression. |
| Switch-form `If` | `condition`, then `then_block.statements[]` case nodes in stored order, reached through the block's normal ownership.  `IS_SWITCH_STATEMENT` selects this route; do not infer a switch from an equality expression alone. |
| `Case` | Optional `condition`, then `then_block`; `owning_if` is a backreference.  A consumed `case ;` is the default-case route with no condition, not necessarily recovery.  Distinguish a failed nonempty condition parse using boundary/diagnostic correlation. |
| `While` | `condition`, then `block`.  Declaration-shaped conditions use their ordinary declaration mapping; no new loop container is invented. |
| `For` prefix expressions | Visit published `want_reverse_expression` and `want_pointer_expression` in their actual token order, not a fixed field order; fallback for equal/unlocated positions is reverse then pointer, with partial ordering coverage if the authored order cannot be established.  Scalar `REVERSE`/`POINTER` flags alone have no child. |
| Remaining `For` fields | After prefix expressions: optional `want_replacement_for_expansion`, optional explicit `ident_it`, optional explicit `ident_it_index`, required `iteration_expression`, optional range `iteration_expression_right`, then `block`.  A consumed range separator with a recovered missing right expression is distinct from no range. |
| `Defer` | `block`; retain scalar backtick observation.  Body traversal is syntactic, not delayed execution or effect analysis. |
| `Push_Context` | Optional `to_push`, then `block` on the non-`DEFER_POP` route.  The builder function omits the block for `DEFER_POP`; that absence is not automatically a missing-body error.  A leading block can also legitimately omit `to_push`. |
| `Loop_Control` | Optional `target_ident` is an authored reference, not a declaration or a resolved loop edge.  Preserve `control_type` without computing control-flow targets. |

Statement blocks can wrap a single authored statement without source braces, and `ifx` branch blocks can wrap a single expression.
Keep block/node IDs and raw intervals without asserting that braces occur in the source.
Case bodies are also parser-created blocks spanning their statements; an empty case body receives a zero-width interval through `set_empty_node_location`.
Empty bodies are valid observations, not missing nodes or evidence of a fabricated token.
`Block.parent`, `Block.owning_statement` and `Case.owning_if` never become downward edges.
Do not reorder children by these backreferences or create index container entries for a control-flow/helper block.
Branch-local declaration/visibility state remains branch-local, including enum-member grammar inherited from the enum routes; no merged visibility, selected-case membership or branch activation is inferred.

For dynamic for-flags, `parse_for_statement` can parse and diagnose duplicate flag expressions without publishing those discarded expressions in `want_*` fields.
Retain published nodes plus exact source/diagnostics; do not scan allocator storage or reconstruct an attached child for each flag token.
The traversal must not claim it inspected unpublished duplicate-expression subtrees.
`want_replacement_for_expansion` is an authored source expression and must be visited even though executing the requested expansion is unsupported.
Compiler `macro_expansion_procedure_call`, `ident_decl` and `index_decl` remain excluded generated data.
Explicit `ident_it`/`ident_it_index` are visited source identifiers, not those generated declaration fields.
The current three-kind declaration index does not add loop-binding entries or implicit `it`/index bindings; exposing a separate loop-binding kind requires its own schema review rather than mislabelling these identifiers `DECLARATION`.

Case `#through` is consumed into `marked_as_fallthrough` by the case parser, not attached there as a separate `Directive_Through` child.
Preserve its scalar/source observations; repeated directive origins require source correlation, not an extra invented node.
For all forms, distinguish optional absence from a known recovered required hole using the qualified parse route, token boundaries and diagnostics.
Fully mapped recovery does not automatically make traversal partial; missing route/ordering/correlation evidence does.
Unexpected fields incompatible with a selected form require a mapping reason, not silent descent through another form or a guess from nonnull pointers.

The discriminating future vectors are dynamic for-flags authored in opposite orders and a default `case ;` versus a recovered missing nonempty condition.
Further independent cases cover declaration conditions; both static branches and enum-mode branch statements; ordinary/ifx single-statement wrappers; empty case bodies; range versus recovered missing range end; explicit versus implicit loop names; named expansion requests; duplicate discarded flag expressions; `DEFER_POP`; and deliberately populated backlinks/generated fields.
Assert exact active visit paths/order, node IDs, raw/recovery observations, index exclusions and partial reasons against independent expectations.
This draft does not implement a visitor, execute branches/expansions or qualify control-flow semantics.

##### Struct and Enum Ownership and Member Context

Proposed refinement of `jai-cache-authored-edges/1` and the declaration-index/2 draft, grounded in `parse_aggregate_definition`, `parse_aggregate_parameter_block`, `parse_aggregate_block`, `parse_struct_modifiers` and enum-mode statement parsing.
The exhaustive layout-specific field rows below use shared base/overlay rules and the source-order/recovery guards that follow.

| Record / storage domain | Exact field roles |
| --- | --- |
| `Code_Struct` / parser layout input | `modify_directives`: `CHILD_LIST`, authored modifier directives.  `block`: `CHILD`, required body with qualified recovery handling.  `arguments_block`: `CHILD`, optional parameter block.  `notes`: `CHILD_LIST`, only under a qualified attachment route; reviewed builder functions leave it empty.  `textual_flags`: `NON_CHILD`, registered source bits.  `alignment`: `NON_CHILD`, source numeric observation on the reviewed route, not an expression child or computed layout result.  `defined_type`: `NON_CHILD`, resolved type storage.  `constants_block`: `NON_CHILD`, compiler-prepared storage. |
| `Code_Enum` / parser layout input | `internal_type_inst`: `CHILD`, optional source type wrapper.  `block`: `CHILD`, required member body with qualified recovery handling.  `notes`: `CHILD_LIST`, only under a qualified attachment route.  `marked_as_complete`: `NON_CHILD`, source marker observation.  `marked_as_specified`: `NON_CHILD`, source marker observation.  `is_flags`: `NON_CHILD`, source keyword distinction.  `internal_type`: `NON_CHILD`, resolved type.  `external_type`: `NON_CHILD`, resolved type. |

Field-table order is not traversal order: struct parameters precede modifier directives and body; enum source type precedes body.
Unexpected attached notes need their own ordering/ownership route, not default placement inferred from a populated pointer.
The static check covers all 16 layout-specific fields.
Source-flag schemas, repeated modifier correlation, builder function and reuse closure and behavioural member/alias qualification remain open.

Struct/union and enum nodes are authored type expressions, not automatically extra named declaration entries or nominal type identities.
Members inherit the enclosing declaration/shared-region index container already established by traversal; do not create a container from a resolved type or invent an anonymous binding merely because an aggregate expression has a body.

| Producer route | Downward order and retained observations |
| --- | --- |
| Struct or union | Optional `arguments_block`, `modify_directives[]` in order, then `block`.  `textual_flags.UNION` distinguishes the union spelling on the same `STRUCT` node shape; it does not select a different child arm. |
| Aggregate parameter block | `statements[]` in stored order.  This is a parser block with `STRUCT_ARGUMENTS` and a parenthesised source interval, not evidence of authored braces.  Parameters are parsed through declaration grammar; do not assume every reached node is an ordinary declaration. |
| Struct/union body block | `statements[]` in stored order, including declarations, using/directive forms, conditional declarations and field-default expressions.  `block.belongs_to_struct` is a backreference, never a descent to the aggregate. |
| Enum or enum-flags | Optional `internal_type_inst`, then `block`.  `is_flags`, `marked_as_complete` and `marked_as_specified` are scalar source observations, not child nodes or completed semantic membership. |
| Enum body / enum-mode branch block | `statements[]` in stored order.  Recognise bare member occurrences only under the enum-member grammar route; conditional branch blocks preserve that route without evaluating the condition. |

`parse_struct_modifiers` stores `#align` by copying a number token's integer value into `alignment`; it does not create an alignment-expression child.
This differs from declaration `alignment_expression` and the unpopulated aggregate-literal helper alignment discussed separately.
Neither a nonzero alignment nor a source flag authorises treating numeric storage as a node pointer.
Modifiers are accepted before parameters, after parameters and after the body.
Preserve final scalar observations and exact source; repeated modifier/alignment occurrences and their positions require qualified token/parse correlation, not inference from the final value or an invented child node.
A zero/default alignment does not distinguish no modifier from an explicitly supplied value, and a malformed modifier must retain its diagnostics rather than become an inferred valid request.

The reviewed builder functions do not attach `Struct.notes` or `Enum.notes`; enclosing declaration/compound notes are separate authored ownership.
Unexpected populated aggregate-note lists require a reviewed producer route or an explicit partial mapping reason, not silent omission or assumed shared ownership.
Compiler `defined_type`, enum `internal_type`/`external_type`, constants blocks and inferred layout values are outside authored descent, even if populated later.

A direct bare enum member is produced by `parse_enum_member` as a `Parser_Ident` from `IDENT ;` under enum-member mode.
Emit one `ENUM_MEMBER` entry for that grammar occurrence, with `declaration_node_id` naming the identifier node, its spelled-name origin and its source occurrence as declaration origin; preserve repeated names without merging.
It has no declaration-properties/program-export producer observation.
The token/statement boundary establishes its grammar extent; an identifier node's own span need not include the semicolon.
Named enum declarations parsed through ordinary declaration grammar retain `DECLARATION`/`COMPOUND_BINDING` as appropriate, rather than being relabelled solely because their container is an enum.
Do not classify identifiers in initialisers, conditions, type annotations or nested expressions as bare members.
Carry enum-member mode only along the registered enum body and static-branch statement routes; a missing route/boundary observation requires partial coverage, not a name-based guess.
`parse_static_if_statement` forwards the enum mode through statement-block parsing: traverse both authored branches, including single-statement branches, with branch-local visibility observations and no guessed active branch or merged enum membership.

Struct field defaults such as `field = 1` and `info.flavor = value` are assignment expressions, not new member declarations.
Descend through their normal binary-expression children without emitting another binding for the target.
`parse_aggregate_block` can populate the target identifier's `resolved_declaration` while matching earlier members; that parser-time reference is still non-owning and excluded from authored traversal.
Do not follow it back to duplicate the member or infer valid semantic resolution.
An absent optional aggregate parameter/internal-type field is ordinary absence.
A missing required body retains its actual diagnostics/recovery: do not create an empty source block or silently certify complete field mapping without the relevant recovery observation.

The discriminating future vectors are a bare enum member versus an identifier use in its conditional expression, and a struct declaration followed by a default assignment whose target points back to that declaration.
Additional independent vectors cover struct versus union, parameter blocks, modifiers at all accepted positions, explicit/default/malformed alignment, enum versus enum-flags, duplicate members, named enum declarations, both enum-mode conditional branches, missing bodies and unexpected notes or semantic pointers.
Assert exact visit order, entry kinds/origins/containers, source scalar observations, excluded backlinks and partial reasons against independent expectations.
The new enum-member tag and optional program-export producer observation remain draft schema refinements, not an implemented API or completed producer qualification.

##### Procedure Ownership, Parameter Aliases and Quick Bodies

Proposed refinement of `jai-cache-authored-edges/1`, grounded in `parse_procedure_type_header`, `parse_arrow_procedure_header`, `parse_procedure_flags`, `parse_procedure_body` and the single-identifier quick-lambda builder function.
For exhaustive field-role coverage, the two generated procedure layouts have the following fields, with shared base/overlay rules unchanged.

| Record / storage domain | Exact field roles |
| --- | --- |
| `Code_Procedure_Header` / parser layout input | `arguments`: `CHILD_LIST`, owning parameter declarations.  `returns`: `CHILD_LIST`, owning return slots.  `parameter_usings`: `CHILD_LIST`, owning using wrappers whose target association follows the guarded alias rule below.  `foreign_function_name`: `NON_CHILD`, owned decoded bytes.  `library_identifier`: `CHILD`, optional source identifier.  `deprecation_string`: `NON_CHILD`, owned decoded bytes.  `modify_directives`: `CHILD_LIST`, source order.  `body_or_null`: `CHILD`, optional published body.  `procedure_flags`: `NON_CHILD`, registered source/parser observations only.  `notes`: `CHILD_LIST`, only with a qualified attachment route; current reviewed builder functions leave it empty.  `name`: `NON_CHILD`, owner-derived compiler/parser value, not a separate authored procedure name.  `constants_block`: `NON_CHILD`, compiler-prepared storage.  `polymorph_source_header`: `BACKREFERENCE`, compiler instantiation provenance excluded from source descent. |
| `Code_Procedure_Body` / parser layout input | `block`: `CHILD`, published body block.  `header`: `BACKREFERENCE`, owning header association.  `body_flags`: `NON_CHILD`, registered source/parser observations only. |

These rows enumerate fields, not their unconditional concatenation: parameter-using interleaving and suffix/body order remain the qualified sequence below.
Unexpected notes or alias associations require the established mapping outcome, not an extra descent or silent omission.
The static field check covers all 16 layout-specific fields.
Exact flag domains, suffix-occurrence correlation, builder function and reuse closure and independent behavioural qualification remain open.

Header/body/block nodes retain their producer identities and observations; procedure syntax does not itself create an extra declaration-index entry or a semantic scope container.
Named parameters/returns and declarations reached in a body use the nearest enclosing declaration/shared-region container already established by authored traversal.
Do not manufacture a named procedure entry from `Procedure_Header.name`, which may be copied from its enclosing declaration.

| Producer path | Ownership and order |
| --- | --- |
| Header parameter lists | Traverse `arguments[]` in stored parameter order, interleaving each matched `parameter_usings[]` wrapper and its filter immediately before that argument.  The argument declaration is owned and descended through `arguments[]` exactly once. |
| Parameter `Using.expression` | Registered non-owning alias to its matching argument, not a second descent.  Visit the `Using` node and its `filter_expression`, retain the expression association, then visit the owning argument.  Resolve the alias ID after the argument is assigned its node ID; the association does not change first downward-encounter ID assignment. |
| Header return list | After parameters, traverse `returns[]` in stored order.  Named returns and unnamed type-only slots keep their actual parser records; no inferred return declarations are added. |
| Header suffix/body | Traverse the optional `library_identifier`, then `modify_directives[]` in order, then optional `body_or_null`.  String-valued foreign/deprecation metadata is not a child.  Source positions still order any independently authored suffix observations; repeated flag occurrences require separate correlation, not inference from the final fields. |
| `Procedure_Body` | Owns `block`.  `header` is a backreference; `block.owning_statement` points back to this body and is not a descent edge. |
| Type-only/header-only forms | A null `body_or_null` is valid; do not follow an unattached allocated body or create an empty block.  `TYPE_ONLY` and other source/derived parser flags remain observations, not proof of semantic validity. |
| Expression-bodied quick form | Header -> body -> parser-created block -> parser-created return -> `arguments_unsorted[].expression`.  Follow only these published downward edges; preserve `AUTO_INSERTED_FOR_QUICK_LAMBDA` and the header's `QUICK` observation. |
| Braced quick form | Header -> body -> authored block statements; preserve `QUICK_IN_BLOCK_FORM`.  Do not add another implicit return around the block. |

The parameter alias rule is narrowly guarded by a `parameter_usings[]` node attached to this header whose `expression` is pointer-identical to exactly one entry in this header's `arguments[]` while the producer is owned.
Match the argument position using that association, not names or overlapping spans; preserve wrapper order and require associations to progress in argument order.
Missing, duplicate or unmatched associations are mapping gaps, not a reason to globally suppress `Using.expression` descent.
Ordinary non-parameter using statements still own their expression under the normal registry rule.
This registers the known cross-list sharing without permitting arbitrary revisits of completed nodes or following lexical-scope binding tables.

Unnamed type-only arguments/returns are parser declaration slots with no authored name: if emitted by the index's declaration-slot mapping, their name is `ANONYMOUS`, not `MISSING` and not a fabricated empty identifier spelling.
Bare named quick-lambda parameters are authored declarations despite having no explicit type.
Do not classify them as recovered merely because `type_inst` is null.
The header builder function's parameter/return wrapper allocation does not establish a nominal binding identity; source-slot indexing and semantic name binding remain distinct.

`parse_procedure_flags` assigns `foreign_function_name` and `deprecation_string` from a string token's value.
Preserve their owned bytes separately from raw spelling; final empty values alone do not distinguish omitted versus explicitly empty strings or retain repeated suffix occurrences.
Its `library_identifier` is an actual `Parser_Ident` child.
Resolving that identifier or importing a library is outside syntax traversal.
The reviewed routes do not attach `Procedure_Header.notes`; declaration notes are attached by `parse_declaration_notes` to the enclosing declaration/compound instead.
A populated header-notes list needs a reviewed producer route, not silent omission or assumed duplicate ownership.

For expression-bodied quick lambdas, the block/return are parser normalisation records, not evidence of authored braces or a `return` keyword.
Their `finish_node` intervals can begin at the whole procedure's `first` token; preserve those raw intervals, but do not use them to assert that synthetic keywords occur at that location or to reorder parameters after the body.
Do not label the implicit return as an inserted missing-token recovery origin: it is normalisation, not `add_missing_token` recovery.
A presentation that needs a distinct keyword origin must report it unavailable unless a separate qualified observation provides one.
On a missing quick-body expression, retain the published empty return-argument list and diagnostic; a fully mapped recovered hole is not an invented expression or an automatic traversal failure.
If no body syntax is consumed, `parse_procedure_body` leaves its newly allocated body unattached; pool allocation is never evidence of authored reachability.

The discriminating future vector is a filtered `using` parameter: visit its filter before its declaration and the declaration's subtree once, while preserving the non-owning expression association.
Additional independent vectors cover interleaved ordinary/using parameters; repeated parameter names; unnamed type-only parameters/returns; single-identifier and parenthesised quick lambdas; arrow-return shorthand; expression versus braced quick bodies; missing expressions; header-only forms; foreign/deprecation strings; header/body/block backlinks; and injected unmatched/duplicate parameter aliases.
Assert exact visit order/IDs, alias targets, index containers/names, normalisation observations and partial reasons against independent expectations.
Existing parameter-using and foreign-header parser fixtures are source evidence, not qualification of this proposed traversal.
Remaining procedure flag/value schemas, repeated-suffix origins and executable visitor qualification stay open; no parser or resolver behaviour is changed by these rules.

##### Literal Arms and Parser-Created Containers

Proposed refinement of `jai-cache-authored-edges/1`, grounded in `parse_aggregate_literal`, `parse_primary`, `parse_using_filter` and the `char`/`filepath` directive cases.
For exhaustive field-role coverage, the layout and its value/helper storage are enumerated below.
Common base/overlay rules apply; helper/union storage does not introduce additional node IDs.

| Record / storage domain | Exact field roles |
| --- | --- |
| `Code_Literal` / parser layout input | `value_type`: `NON_CHILD`, active-arm tag under the registered mapping.  `values`: `HELPER`, selected anonymous-union storage, not an unconditional list of values.  `value_flags`: `NON_CHILD`, reviewed source literal bits, never the lexer flag domain. |
| `Code_Literal.values` / active union | `_string`: `NON_CHILD`, owned active string bytes.  `_float64`: `NON_CHILD`, active floating-point bits.  `_s64`: `NON_CHILD`, signed storage view, not a second numeric value to read alongside the selected producer arm.  `_u64`: `NON_CHILD`, active integer/boolean observations under the route rules below.  `struct_literal_info`: `HELPER`, active struct payload only.  `array_literal_info`: `HELPER`, active array payload only.  `pointer_literal_info`: `HELPER`, qualified source-null payload only.  `type_info_literal_defn`: `NON_CHILD`, unsupported evaluated/type-definition payload, not authored descent. |
| `Code_Struct_Literal_Info` / parser-owned helper counterpart | `type_expression`: `CHILD`, optional typed-prefix wrapper, then `arguments`: `CHILD_LIST`, authored member-expression order. |
| `Code_Array_Literal_Info` / parser-owned helper counterpart | `element_type`: `CHILD`, optional qualified typed-prefix wrapper.  `alignment`: `CHILD`, only with a separately registered source route; inactive on the reviewed aggregate/name-list builder functions.  `array_members`: `CHILD_LIST`, authored member/name-list order.  `array_literal_flags`: `NON_CHILD`, registered source bits. |
| `Code_Pointer_Literal_Info` / qualified source-null helper | `global_symbol`: `NON_CHILD`.  `string_or_array_literal`: `NON_CHILD`.  `data_pointer`: `NON_CHILD`.  `pointer_literal_type`: `NON_CHILD`, qualified discriminator observation.  `offset_from_symbol`: `NON_CHILD`.  None supplies an authored node edge or permission to encode a process address. |

Compiler names identify the layout inputs; the aggregate helper fields are accessed through their parser-owned counterparts, not by assuming the compiler's mutable representation is an owned payload.
The pointer helper has overlapping symbol/string storage: its field-role enumeration is not permission to read inactive arms.
Preserve only safely qualified source-null observations under the existing literal rules; an unqualified address or evaluated payload requires the established unsupported/mapping outcome, not raw pointer serialisation.
The static field check covers each of these five inventory rows, counting phase-duplicate fields once and excluding shared `base`.
This closes draft field-role enumeration for one generated layout and the listed helper/union storage; exact scalar/flag schemas and independent behavioural qualification remain open.

Select the literal union arm using `value_type`, with the reviewed source-value flags and construction route where needed.
Never read a second arm to discover children or encode inactive union bytes.
The literal-value flag domain is not the lexer's `Value_Flags` domain; the token flag mask specified elsewhere must not be applied to AST literal flags.

| Literal arm / reviewed route | Downward paths and retained observations |
| --- | --- |
| `NUMBER` | No child; retain the active `_float64` bits when the literal `FLOAT` flag is set, otherwise `_u64` bits, plus reviewed source flags.  This includes parser-produced `#char` values, not only numeric tokens. |
| `BOOLEAN` | No child; retain the parser's `_u64` observation for the authored `true`/`false` token, without treating the union as a pointer. |
| `STRING` | No child; retain `_string` bytes and source flags.  Routes include quoted/here strings, `#filepath`, and parser-created using-filter names; do not require every string value to equal its full source slice. |
| `UNINITIALIZED` | No child; retain the `---` occurrence.  Declaration parsing can instead set `IS_UNINITIALIZED` and clear the expression; do not reconstruct a missing literal node in that declaration. |
| `STRUCT` from `parse_aggregate_literal` | `struct_literal_info` is helper storage: optional `type_expression`, then `arguments[]` in authored order.  A typed prefix is wrapped with `make_type_instantiation`; an untyped literal legitimately has no type wrapper. |
| `ARRAY` from `parse_aggregate_literal` | `array_literal_info` is helper storage: optional `element_type`, then `array_members[]` in authored order.  The untyped route sets `WAS_UNTYPED`; typed prefixes are wrapped rather than resolved. |
| `ARRAY` from a parenthesised `using,only` or `using,except` name list | Helper `array_members[]` contains parser-created `STRING` literals in name-list order.  There is no element-type wrapper and this builder function does not set `WAS_UNTYPED`; the source is a name list, not `.[...]`. |
| `POINTER` from the authored `null` route | No authored child.  Preserve the qualified null observation: this builder function allocates `Code_Pointer_Literal_Info` with `pointer_literal_type == CONSTANT_VALUE`.  Do not follow its symbol/data/string-or-array pointer fields as syntax edges. |

Other pointer/type-definition/evaluated literal routes are not admitted as authored children by this registry.
An unsupported value tag or unqualified pointer route requires an explicit unmapped/partial reason, not a cast into an aggregate helper or an assumed null value.
Source `null` must not be rejected merely because it uses the pointer arm; conversely, `value_type == POINTER` alone is not proof that an arbitrary producer value was authored `null`.
The current parser's aggregate and using-filter builder functions do not populate `array_literal_info.alignment`.
A nonnull alignment needs a separately reviewed producer route and ordering rule; preserve the observation and report partial mapping rather than silently traverse it or drop it.

Typed and untyped empty aggregates still own an active helper; zero members is valid, while a null helper for a selected aggregate arm is a mapping gap unless explicit producer recovery evidence accounts for it.
Missing type wrappers are ordinary absence on untyped aggregates and parser-created name lists.
Do not infer a typed form from the absence of `WAS_UNTYPED`, since the using-filter builder function provides a counterexample.
Member lists contain expression nodes, not necessarily declarations or named-argument records.
Preserve assignment expressions and repeated member spellings without promoting them to declaration-index entries or resolving field names.
Walk nested declarations only through the active expression's own reviewed child mapping and the current authored container; helper storage does not fabricate an enclosing declaration.

Parser-created using-filter string nodes have identifier-token origins and identifier value bytes, not quoted-string spellings.
`#filepath` values depend on the captured filename/directory context and are not a literal copy of the directive spelling.
Retain those source/value distinctions and source-context dependencies; do not evaluate `using,map` or derive semantic filter results during traversal.
Copy/lease active string bytes and helper lists independently of producer/interner lifetimes.
Exact source spelling remains in the protected source/token data; decoded scalar values do not replace it.
Keep wrapper and child IDs distinct even when their spans coincide, and do not discover unattached/recovery-discarded literals by scanning pool allocations.

The discriminating future vectors are source `null` versus an unsupported pointer payload, and an untyped aggregate array versus a using-filter name-list array with no `WAS_UNTYPED` flag.
Further independent cases cover typed/untyped empty and nested aggregates; repeated named member expressions; scalar/float bit preservation; `#char`, here strings and `#filepath`; standalone versus declaration `---`; missing helpers; inactive union-pointer controls; unexpected alignment; and owned bytes after producer teardown.
Assert exact active paths/order, source/value observations, local node IDs and partial reasons against independent expectations.
Exact AST flag/value payload schemas and executable qualification remain open; these traversal rules do not claim those contracts are complete.

##### Type Instantiation Source-Form Guards

Proposed refinement of `jai-cache-authored-edges/1`, grounded in `parse_type_instantiation` and `make_type_instantiation`.
For exhaustive field-registry closure, this layout has the following eight layout-specific fields; shared structural base/overlay rules apply as in the earlier slices.

| Parser layout / published kind | Exact layout-specific field roles |
| --- | --- |
| `Parser_Type_Instantiation` / `TYPE_INSTANTIATION` | `type_valued_expression`: `CHILD`, active for expression/polymorphic/procedure wrappers.  `must_implement`: `CHILD`, active only for a qualified consumed polymorphic constraint suffix.  `pointer_to`: `CHILD`, pointer form only.  `type_directive_target`: `CHILD`, type-directive form only.  `array_element_type`: `CHILD`, array/view/resizable/varargs forms only.  `array_dimension`: `CHILD`, fixed-dimension array form only.  `inst_flags`: `NON_CHILD`, registered source-derived observations.  `result`: `NON_CHILD`, inferred/compiler type storage excluded from syntax descent. |

The row enumerates possible fields, not one unconditional visit sequence.
Select the active subset and order from the source-form table below; do not visit all six child slots merely because they share this layout.
Missing required children on a published recovered route retain their qualified recovery holes.
A wrapper that was never published is not a missing-node placeholder in the syntax graph.
The focused static field check compares this row with `Code_Type_Instantiation` in the compiler field inventory, excluding shared `base`, and rejects missing/duplicate fields.
Exact source-flag encoding, complete builder function and reuse reachability and executable route qualification remain open despite complete draft field-role enumeration for this layout.

The producer has no separate source-form discriminant: the labels below are registry rules, not new producer enum values or a final payload wire union.
Select a rule from a qualified construction/source observation bound to the owned token interval, then validate its source flags and fields together.
Do not choose the first nonnull child or equate a missing recovered child with a different grammar form.
Preserve raw producer `inst_flags` separately; only reviewed source bits participate in these guards, never inferred `result` or common node `type`.

| Source form / required observation | Active child order and source flags |
| --- | --- |
| Varargs `..T` | `array_element_type`; `VARARGS` and `ARRAY_VIEW` are both set.  This is not a dimensionless array-view spelling. |
| Polymorphic `$T` with optional `/ [interface] constraint` | `type_valued_expression`, then `must_implement` only for a consumed constraint suffix.  The expression is the parser-created identifier marked `DEFINES_POLYMORPH_VARIABLE`; `INTERFACE` records the consumed `interface` keyword, not completion of constraint resolution. |
| `#type` with optional `,distinct` or `,isa` | `type_directive_target`; `TYPE_DIRECTIVE`, optionally `TYPE_DIRECTIVE_DISTINCT` or `TYPE_DIRECTIVE_ISA`.  Modifier tokens and recovery remain source observations; an unknown modifier is not silently normalised to an accepted one. |
| Pointer `*T` | `pointer_to`; no array, directive or procedure source-form flag is implied. |
| Array view `[]T` | `array_element_type`; `ARRAY_VIEW`, without `VARARGS`.  `array_dimension` is inactive. |
| Resizable array `[..]T` | `array_element_type`; `RESIZABLE`.  `array_dimension` is inactive. |
| Fixed-dimension array `[expression]T` | `array_dimension`, then `array_element_type`, including expressions that contain directives or are not semantically valid dimensions.  Neither `ARRAY_VIEW` nor `RESIZABLE` is implied. |
| Procedure type beginning `(` on this parse route | `type_valued_expression`, the parsed `Procedure_Header`; `TYPE_OF_PROCEDURE` on the wrapper and `TYPE_ONLY` on the header.  Traverse authored parameters/returns under the header rules, not its lexical scope bindings. |
| General type-valued expression wrapper | `type_valued_expression` from `make_type_instantiation`; no wrapper-specific source-form flag is added there.  This includes postfix member/call expressions and contextual aggregate-type wrappers, not only identifiers. |

For each selected rule, the other type-instantiation child fields are inactive; unexpected populated fields or conflicting source-form flags are producer-mapping mismatches, not additional children or permission to switch rules.
`must_implement` is not a globally active extra edge on all type nodes.
In particular, `$T` and a recovered `$T /` can both have a null constraint pointer; token/parse correlation must preserve the consumed suffix and diagnostic rather than assert that both are unconstrained.
An `INTERFACE` flag is not required for an ordinary `/ constraint`, and its absence does not prove the suffix was absent.
Do not treat all `ARRAY_VIEW` records as varargs or all null `array_dimension` fields as array views: a recovered fixed-dimension form can have a missing dimension, and a general wrapper has no dimension at all.

Required-child recovery is explicit: retain a recognised missing target/dimension/constraint and its diagnostic/origin correlation rather than invent a node or dereference null.
A fully mapped recovered hole need not make traversal partial; absent form/boundary/recovery evidence does, with the missing field path and reason.
Successful grammar recovery alone does not establish the form mapping.
The current pointer/varargs builder functions return null when their recursive element parse fails, whereas array and `#type` builder functions can publish a wrapper with a null required child.
Do not manufacture an unpublished wrapper from source punctuation; preserve the surrounding parse's actual recovery observations.

`make_type_instantiation` copies the expression's coordinates and token interval into a newly allocated wrapper.
Equal spans do not make wrapper and expression one node, and nested wrappers retain distinct IDs.
For aggregate literal type information the same helper can wrap an expression parsed on a different route; a leading token alone is not universal proof that the type-parser pointer/array/procedure rule was used.
Unqualified route ambiguity requires partial mapping, not a guessed source-form tag.
Traverse each qualified wrapper's active children in the table order; for fixed arrays, visiting the element before the dimension would change authored order and snapshot-local ID assignment.
Do not resolve postfix calls/member expressions, evaluate dimensions/constraints, instantiate types or follow compiler `result` while traversing these fields.

The discriminating future vectors are `..T` versus `[]T`, fixed arrays with a recovered missing dimension, and `$T` versus a consumed but missing `/` constraint.
Additional independent cases cover nested pointer/array combinations; both `#type` modifiers and malformed modifiers; procedure-type parameters/returns; postfix member/call wrappers; contextual aggregate-type wrappers; inactive populated fields; conflicting flags; and equal-span wrapper/child IDs.
Existing nested-type reuse/fallback fixtures in `parser_tokens_test.jai` contain relevant forms, including cases deliberately excluded from reuse; non-reusability does not exclude them from complete fresh-syntax traversal.
Future qualification must assert exact paths/order, retained flags, recovery holes and partial reasons against independently authored expectations.
This draft neither implements form correlation nor certifies the remaining procedure/literal child registries.

##### Assembly Helper Guards and Traversal Order

Proposed refinement of `jai-cache-authored-edges/1`, grounded in the parser's `parse_asm_instruction_span`, `add_asm_operand` and `parse_asm_*_span` builder functions.
These auxiliary records are `HELPER` storage, not additional `Parser_Node` occurrences; only their identifier/expression fields enter the ordinary node traversal and node-ID domain.
Preserve helper kinds, spans, list order and scalar observations in the protected syntax snapshot; do not reinterpret their memory as compiler `Code_Asm` payloads.

For exhaustive generated-layout field coverage, shared base/overlay rules apply to the compiler storage, while the parser generator adds separate owned syntax fields.

| Record / storage domain | Exact field roles |
| --- | --- |
| `Code_Asm` / compiler layout input | `b1`: `NON_CHILD`, opaque compiler payload excluded.  `b2`: `NON_CHILD`, opaque compiler payload excluded.  `b3`: `NON_CHILD`, opaque compiler payload excluded.  Do not inspect these slots to discover syntax, cast them to assembly helpers or serialise their raw bytes. |
| `Parser_Asm` / parser-added storage | `features`: `HELPER`, ordered feature records, then `statements`: `HELPER`, ordered statement records under the guards below.  `body_span`: `NON_CHILD`, qualified source-token interval observation.  `enclosing_scope`: `BACKREFERENCE`, never a downward syntax edge. |

`Parser_Asm` itself remains an ordinary node with its own ID; the `Asm` row below describes that node's traversal, not an extra helper allocation.
Its list elements and their auxiliary records do not acquire node IDs, while their actual identifier/expression children do.
On a missing opening brace, the builder function still publishes the node, feature list and empty statement list; preserve that recovery without treating the default `body_span` as an authored empty body.
A consumed body's empty interval and a recovered missing closing brace retain their distinct boundary/diagnostic observations.
Visit only published helper records, never discarded allocations or opaque compiler storage.
This completes draft field-role enumeration for all 50 generated layouts, including these three compiler fields and four parser-added fields.
It does not close direct base-node kinds, exhaustive auxiliary-field/variant coverage, scalar/tag schemas, builder function and reuse reachability or independent behavioural qualification.

The exact auxiliary-field rows below cover the shared span value and reviewed assembly helper slices.
These are non-node records; their fields do not introduce helper IDs or permit unguarded payload traversal.

| Record / storage domain | Exact fields / declared variants |
| --- | --- |
| `Token_Span` / shared token-coordinate value | `first`: `NON_CHILD`, inclusive token index.  `one_past_last`: `NON_CHILD`, exclusive token index.  Both use the producer's distinct `Token_Index` type, not absolute source-byte offsets. |
| `Parser_Asm_Feature` / parser-owned helper | `span`: `NON_CHILD`, qualified token-span observation.  `name`: `CHILD`, required published identifier occurrence; visit through the ordinary identifier mapping, not an assembly declaration entry. |
| `Parser_Asm_Memory_Operand` / parser-owned helper | `span`: `NON_CHILD`, published memory-address token interval.  `base`: `HELPER`, required base value, then `index`: `HELPER`, optional index value, `scale`: `HELPER`, optional scale value, and `displacement`: `HELPER`, optional signed displacement value.  Traverse published expressions in that order under the qualified memory route; default value records do not establish authored components. |
| `Parser_Asm_Operand_Modifier` / parser-owned helper | `kind`: `NON_CHILD`, registered suffix-variant observation.  `span`: `NON_CHILD`, published suffix token interval.  `argument`: `HELPER`, required identifier-valued argument only for the ampersand variants; inactive for every bang variant. |
| `Parser_Asm_Operand_Modifier_Kind` / declared variants | `BANG`, `BANG_N`, `BANG_D`, `BANG_U`, `BANG_Z`, `AMPERSAND`, `AMPERSAND_STAR`.  Native ordinals and the producer's enum width are not approved wire tags. |
| `Parser_Asm_Register_Declaration` / parser-owned helper | `span`: `NON_CHILD`, declaration-prefix token interval, not necessarily the full attached pinning interval.  `name`: `CHILD`, required source identifier.  `register_class`: `CHILD` only when the class spelling is explicit.  `is_inferred`: `NON_CHILD`, grammar observation selecting omitted versus explicit class, not semantic type inference.  `pinning`: `HELPER`, optional published pinning record after name and explicit class; distinguish a qualified omission from a rejected introduced suffix. |
| `Parser_Asm_Register_Pinning` / parser-owned helper | `span`: `NON_CHILD`, qualified full pinning token interval.  `source`: `HELPER`, required source value, then `target`: `HELPER`, required target value.  Each follows the value helper's expression/presence rules; helper records do not acquire node IDs. |
| `Parser_Asm_Operand` / parser-owned helper | `kind`: `NON_CHILD`, registered operand-variant observation.  `span`: `NON_CHILD`, full published operand token interval, including attached suffix syntax.  `value`: `HELPER`, selected value payload only.  `register_declaration`: `HELPER`, selected register-declaration payload only.  `register_pinning`: `HELPER`, selected register-pinning payload only.  `memory`: `HELPER`, selected memory payload only.  `modifiers`: `HELPER`, ordered published suffix records after the selected base, for every kind including unparsed.  Inactive base slots do not become edges. |
| `Parser_Asm_Operand_Kind` / declared variants | `UNPARSED`, `VALUE`, `REGISTER_DECLARATION`, `REGISTER_PINNING`, `MEMORY`.  Native ordinals and the producer's enum width are not approved wire tags. |
| `Parser_Asm_Value` / parser-owned helper | `span`: `NON_CHILD`, qualified value token interval.  `expression`: `CHILD`, published source expression when present; required for a selected value operand or required value component, but legitimately absent in an optional unused component under its owning helper's route. |
| `Parser_Asm_Instruction` / parser-owned helper | `span`: `NON_CHILD`, published statement-span observation.  `mnemonic`: `CHILD`, required source identifier.  `size`: `HELPER`, optional qualified mnemonic-size record.  `operands`: `HELPER`, ordered published operand records.  Visit mnemonic, selected size child, then operand children in stored order; helper records do not acquire node IDs. |
| `Parser_Asm_Mnemonic_Size` / parser-owned helper | `kind`: `NON_CHILD`, registered size-variant observation.  `span`: `NON_CHILD`, consumed size-token interval.  `polymorphic_name`: `CHILD` only on the polymorphic route; inactive for a fixed size. |
| `Parser_Asm_Mnemonic_Size_Kind` / declared variants | `FIXED`, `POLYMORPHIC`.  Native ordinals and the producer's enum width are not approved wire tags. |
| `Parser_Asm_Statement` / parser-owned helper | `kind`: `NON_CHILD`, registered statement-variant observation.  `span`: `NON_CHILD`, retained statement token interval.  `instruction`: `HELPER`, selected instruction payload only.  `register_declaration`: `HELPER`, selected register-declaration payload only.  `register_pinning`: `HELPER`, selected register-pinning payload only.  Use the kind guards below; no selected helper on the unparsed route. |
| `Parser_Asm_Statement_Kind` / declared variants | `UNPARSED`, `INSTRUCTION`, `REGISTER_DECLARATION`, `REGISTER_PINNING`.  Native ordinals and the producer's enum width are not approved wire tags. |

The span/feature/statement slice enumerates nine declared fields across three records and all four current statement kinds.
The shared span's field names describe token coordinates; validate them against the protected revision and applicable source/recovery rules, not by blindly treating a zero/default pair as an authored occurrence.
The statement builder function retains its full span before classification.
Empty/non-identifier content and rejected declaration/pinning forms can remain unparsed; retain their opaque region and partial-coverage observation rather than inventing an instruction or following a leftover inactive slot.
A selected helper follows its own required-field/recovery rules, while an unknown kind is unmapped rather than an instruction fallback.
The focused static checks compare fields and enum members with their declarations; remaining auxiliary-field coverage, builder function and reuse closure and executable variant qualification remain open.

The instruction/size slice adds seven declared fields across two records and both current size kinds.
The reviewed builder function selects a fixed size from an adjacent numeric token, or a polymorphic size from an adjacent question mark and identifier; a separated operand is not reclassified merely because its spelling looks like a size.
Fixed sizes retain source-token observations without a fabricated numeric-expression child, while a selected polymorphic size requires its published identifier under the existing missing-field rules.
Size absence is legitimate on an unsized instruction.
Preserve the actual operand list, including recovery-created boundaries, rather than resplitting source text or inventing a helper for each separator.
Exact scalar/tag schemas and executable source-route/order qualification remain open.

The operand/value slice adds nine declared fields across two records and all five current operand kinds.
Select only the kind's base helper, then visit attached modifier records in stored order; an unparsed base has no base child but can still own traversable modifiers.
Preserve its opaque region and coverage reason rather than claiming the entire operand was inspected.
An unknown kind is unmapped, not a request to select whichever payload slot is nonnull.
Only a published modifier list is inspected: a malformed suffix can return before attaching temporary records, while a missing base after successful suffix parsing can retain those modifiers on an unparsed operand.
Neither raw suffix tokens nor allocator contents justify inventing attached helpers.
Empty input intervals rejected before operand allocation do not imply missing list entries.
The value builder function parses a prefix expression over its supplied token interval and asserts full consumption before restoring the parser cursor.
That producer invariant is not independent qualification of expression presence, source origins or consumer safety.
For optional unused components, default spans do not fabricate source occurrences; for required selected components, preserve qualified missing-expression evidence or the existing mapping outcome instead of dereferencing null.
Builder function and reuse closure, scalar/tag schemas and executable variant/recovery qualification remain open.

The register declaration/pinning slice adds eight declared fields across two records.
Visit the declaration name, explicit class only when not inferred, then published pinning source and target; never reconstruct an omitted class or resolve assembly register bindings.
The reviewed pinning builder function accepts an identifier source and an identifier or numeric target at the required separator boundaries; a rejected shape does not publish a pinning helper.
An introduced but rejected pinning suffix can leave the declaration published with null pinning and no pinning-specific diagnostic.
Null alone therefore cannot establish valid omission: preserve the raw suffix and the appropriate uninspected/mapping region under the existing partial-coverage rules, rather than inventing a target or claiming that no suffix was authored.
Required expression holes in published pinning values follow the existing qualified recovery/mapping rules.
The declaration name and pinning source can be separately allocated identifier nodes for the same token.
Keep their distinct IDs and registered paths, and do not extend the declaration helper's producer span to contain its attached pinning.
Exact scalar/tag schemas, builder function and reuse reachability and independent omission/rejection/identity qualification remain open.

The memory/modifier slice adds eight declared fields across two records and all seven current modifier kinds.
Memory components follow their published value expressions: do not invent an implicit scale, zero displacement or identifier for unused storage.
A consumed operator with no represented component is not proved absent by a default value record; retain its source/recovery observations and any required uninspected/mapping coverage rather than declaring the whole address fully mapped.
Rejected memory forms do not justify reconstructing a helper from the raw operand span.
Bang suffixes have no argument child; their qualified single-letter forms require the reviewed adjacency/spelling evidence.
Ampersand-star requires adjacent punctuation, and both ampersand variants publish an identifier-valued argument rather than an arbitrary expression parsed from trailing text.
Traverse only published modifiers in stored order, including those attached to an unparsed base; unknown kinds remain unmapped, and inactive argument storage is never a child.
Declared-field enumeration now covers all ten current assembly helper records plus the shared token-span value, and all four assembly kind enums.
The focused static check compares that complete local set with the live declarations; it does not qualify all builder/reuse paths, source-form correlations, exact wire schemas, other auxiliary families or executable visitor behaviour.

| Helper / guard | Downward order and restrictions |
| --- | --- |
| `Asm` | `features[]`, then `statements[]`, each in stored source order.  `body_span` is observation data; `enclosing_scope` is a backreference. |
| `Asm_Feature` | `name`. |
| `Asm_Statement` | `INSTRUCTION`: `instruction`; `REGISTER_DECLARATION`: `register_declaration`; `REGISTER_PINNING`: `register_pinning`; `UNPARSED`: no base child.  Other arm fields are inactive regardless of pointer contents. |
| `Asm_Instruction` | `mnemonic`, optional `size` helper, then `operands[]` in stored order. |
| `Asm_Mnemonic_Size` | `FIXED`: no child; retain the size token span, not a fabricated numeric-expression node.  `POLYMORPHIC`: `polymorphic_name`. |
| `Asm_Operand` | First the selected base arm: `VALUE` -> `value`; `REGISTER_DECLARATION` -> `register_declaration`; `REGISTER_PINNING` -> `register_pinning`; `MEMORY` -> `memory`; `UNPARSED` -> no base child.  Then `modifiers[]` for every base kind, including `UNPARSED`. |
| `Asm_Value` | `expression` when present.  For optional absent memory components the zero/default span is not an authored source occurrence. |
| `Asm_Register_Declaration` | `name`, then `register_class` only when `!is_inferred`, then optional `pinning`.  Inferred class means no class child, not an empty identifier. |
| `Asm_Register_Pinning` | `source`, then `target`, both `Asm_Value` helpers. |
| `Asm_Memory_Operand` | `base`, then optional `index`, `scale`, `displacement` values in that order.  Presence comes from a nonnull expression in this producer; do not infer a component from default span indices. |
| `Asm_Operand_Modifier` | `BANG`, `BANG_N`, `BANG_D`, `BANG_U`, `BANG_Z`: no child.  `AMPERSAND`, `AMPERSAND_STAR`: `argument` value.  Preserve modifier order and individual spans. |

This is the per-helper fallback order for equal/unlocated positions; it also matches the reviewed builder function's source progression for recognised forms.
The optional-versus-required distinction is field-specific: a null optional size/pinning/memory component is ordinary absence only on a qualified omission route, whereas a null selected statement arm, instruction mnemonic, feature name, explicit register name/class, polymorphic size name or required modifier argument is an incomplete mapping.
For a `VALUE` operand or recognised pinning/memory form, missing required expressions likewise prevent a complete mapping; retain available source/diagnostic observations rather than dereference null or invent a child.
An unknown helper discriminant is an unmapped variant and makes index coverage partial.
Do not guess its arm from nonnull fields.
Inactive fields are never traversed; fresh-observation comparisons must still detect unexpected producer data without following semantic or inactive pointers.

`UNPARSED` statements and operand bases retain their exact token spans as opaque syntax and require a partial-traversal reason for the uninspected region, not a claim that the region contains no declarations.
Recognised modifiers on an unparsed base remain independently traversable: `add_asm_operand` can assign `operand.modifiers` before discovering a missing/unsupported base.
On an earlier malformed-modifier return, the producer may not attach the temporary modifier list at all; preserve only the published helper records plus raw source/diagnostics, never infer unattached records from pool allocations.
A diagnostic alone does not force partial coverage of all other assembly children; identify the actual uninspected or unmappable region.

Register-declaration/pinning helpers express assembly grammar, not ordinary `DECLARATION` or `COMPOUND_BINDING` entries.
Their names remain authored identifier occurrences; a future assembly-symbol index needs a separately reviewed kind rather than silently widening this declaration index.
Ordinary declarations reached inside a parsed value expression still follow the surrounding authored container rules; an assembly instruction/helper does not fabricate an enclosing declaration entry.
Register-declaration `name` and pinning `source.expression` may be separately allocated identifiers for the same source token.
Retain distinct producer node IDs and registered paths; equal spans/names are not a licence to merge them or emit duplicate declarations.
Do not demand that every descendant span fit inside its immediate helper span: the current register-declaration helper's span can stop before its attached pinning.
Validate all spans against the owned token/source revision and the registered construction, without silently widening producer observations.

The discriminating future vector is an `UNPARSED` operand with an attached `AMPERSAND` modifier: the base contributes an opaque/partial reason while the modifier's identifier is visited exactly once.
Additional independent vectors cover all four statement kinds, five operand kinds, both size kinds and seven modifier kinds; absent/inferred versus explicit register classes; optional memory components; separately allocated same-token identifiers; malformed suffixes; injected inactive pointers and unknown tags.
Existing assembly fixtures in `parser_tokens_test.jai` provide source forms and recovery observations, not qualification of this proposed visitor.
Assert exact visit paths/order, selected-arm exclusions, node IDs and local coverage reasons after implementation authorisation.
This closes the draft's unspecified assembly-helper field paths, not the outstanding producer review or executable qualification gates for the complete registry.

##### Token Registry and Required Trivia Profile

On 2026-10-21 the user accepted trivia handling as a requirement for full-featured API support and allowed dropping the compatibility restriction if it reduces complexity.
Accordingly, the proposed initial full-featured profile uses trivia-enabled, byte-indexed owned syntax only; dual-mode support and a non-trivia origin adapter are not acceptance requirements.
This records a scope simplification, not authorisation to remove the existing parser's AST compatibility mode or change production module defaults now.
Keep trivia/source ownership and exact byte spans in the eventual API regardless of whether the implementation later removes the compile-time switch entirely.
Performance comparisons for this profile must use an equivalent trivia-enabled fresh baseline; historical measurements with different options are not interchangeable acceptance samples.

`jai-cache-token-tags/1` has the following closed `NAMED` registry, grouped for readability only; group/row order is not token precedence or an encoded enum ordinal.

| Group | Canonical names |
| --- | --- |
| Values | `IDENT`, `NUMBER`, `STRING` |
| Operators | `PLUSEQUALS`, `MINUSEQUALS`, `TIMESEQUALS`, `DIVEQUALS`, `MODEQUALS`, `ISEQUAL`, `ISNOTEQUAL`, `LOGICAL_AND`, `LOGICAL_OR`, `LESSEQUALS`, `GREATEREQUALS`, `RIGHT_ARROW`, `DOUBLE_DOT`, `DOUBLE_DOLLAR`, `SHIFT_LEFT`, `SHIFT_RIGHT`, `ROTATE_LEFT`, `ROTATE_RIGHT`, `TRIPLE_EQUALS`, `SHIFT_LEFT_EQUALS`, `SHIFT_RIGHT_EQUALS`, `ROTATE_LEFT_EQUALS`, `ROTATE_RIGHT_EQUALS`, `BITWISE_AND_EQUALS`, `BITWISE_OR_EQUALS`, `BITWISE_XOR_EQUALS`, `LOGICAL_AND_EQUALS`, `LOGICAL_OR_EQUALS`, `POSTFIX_DEREFERENCE`, `PREFIX_DEREFERENCE`, `ISEQUAL_FOR_SWITCH_STATEMENT`, `DOUBLE_MINUS`, `TRIPLE_MINUS`, `DOUBLE_COMMA`, `BEGIN_STRUCT_LITERAL`, `BEGIN_ARRAY_LITERAL` |
| Keywords | `KEYWORD_FOR`, `KEYWORD_IF`, `KEYWORD_IFX`, `KEYWORD_THEN`, `KEYWORD_ELSE`, `KEYWORD_CASE`, `KEYWORD_RETURN`, `KEYWORD_STRUCT`, `KEYWORD_WHILE`, `KEYWORD_BREAK`, `KEYWORD_CONTINUE`, `KEYWORD_REMOVE`, `KEYWORD_USING`, `KEYWORD_DEFER`, `KEYWORD_SIZE_OF`, `KEYWORD_TYPE_OF`, `KEYWORD_CODE_OF`, `KEYWORD_INITIALIZER_OF`, `KEYWORD_TYPE_INFO`, `KEYWORD_NULL`, `KEYWORD_ENUM`, `KEYWORD_TRUE`, `KEYWORD_FALSE`, `KEYWORD_INLINE`, `KEYWORD_NO_INLINE`, `KEYWORD_CAST`, `KEYWORD_AUTO_CAST`, `KEYWORD_CONTEXT`, `KEYWORD_PUSH_CONTEXT`, `KEYWORD_OPERATOR`, `KEYWORD_IS_CONSTANT`, `KEYWORD_ENUM_FLAGS`, `KEYWORD_UNION`, `KEYWORD_INTERFACE` |
| Other | `QUICK_LAMBDA`, `NOTE`, `END_OF_INPUT`, `ERROR` |
| AST-only operators | `OPERATOR_ARRAY_SUBSCRIPT`, `OPERATOR_ASSIGNMENT_TO_ARRAY_SUBSCRIPT` |

`BYTE_CHAR` represents an unsigned byte value from `0` through `255`; representability does not claim that every byte is a valid source token.
Preserve inactive/default diagnostic token observations without fabricating source spelling.
Producer aliases `BITWISE_XOR`, `BITWISE_NOT`, `BITWISE_AND`, `BITWISE_OR` encode as `BYTE_CHAR` values `94`, `126`, `38`, `124` respectively.
`__FIRST_KEYWORD` normalises to `NAMED {KEYWORD_FOR}` and `__LAST_KEYWORD` to `NAMED {KEYWORD_INTERFACE}`.
Those six alias spellings are not accepted as canonical `NAMED` payloads; payload decoding accepts only the table's exact names or a valid byte-character value.
The two AST-only operator names may appear in registered operator fields, not as claimed lexer-emitted source tokens.
Other token-role constraints must likewise agree with the actual producer; registration alone does not prove a value can occur in every field.
Duplicate canonical names, unregistered producer values and malformed tags fail conversion.
Adding/renaming/remapping a token or alias requires an explicit registry/schema compatibility change, not reliance on a changed native enum number.
This closes the current tag-name/alias inventory; the token-value/trivia draft below and complete node/child variants still need payload-schema review and executable producer round-trip checks.

##### Token Values, Flags and Trivia Ownership

Proposed 2026-10-21 under `jai-cache-source-tokens/1`, for materialised source tokens in the required trivia-enabled profile; synthetic tokens remain separate recovery records, not fabricated source tokens.
`TokenRecord` is `{tag, origin:SOURCE, coordinates, value_flags:u32, ident_is_backticked:bool, original, preceding, value}`.
`coordinates` preserves `{l0:s32, c0:s32, l1:s32, c1:s32}` verbatim as producer observations, independently of validated byte origins; unset/error coordinates are not clamped into valid editor positions.
`original` and `preceding` are checked half-open byte slices of the envelope's exact source, not producer pointers or independently mutable strings.
Preserve empty slices and validate their offsets before exposing views.
The token origin agrees with its materialised `byte_start`/`byte_end`; `original` preserves the producer's `original_text` slice.
If a producer route makes these differ, retain both observations and qualify that mapping explicitly rather than silently rewriting either.

| Active `value` tag | Producer discriminator and exact payload |
| --- | --- |
| `NAME {bytes}` | `IDENT`, `NOTE` and materialised `KEYWORD_*` tokens carry the active `ident_value.name` bytes.  Preserve decoded/handler-produced bytes independently of source spelling; keywords use the copied name, and backticked spellings remain distinguishable through source and `ident_is_backticked`. |
| `UNSIGNED_INTEGER {bits:u64}` | `NUMBER` without `FLOAT` preserves the exact unsigned accumulator, including overflow-result bits with the producer's flags/diagnostics.  Do not reinterpret a high-bit value as a signed integer or infer representation from decimal spelling. |
| `FLOAT64_BITS {bits:u64}` | `NUMBER` with `FLOAT` preserves the exact IEEE-754 binary64 object bits of `float64_value`, even when the producer first rounded to float32.  No decimal formatting round trip, NaN canonicalisation or signed-zero folding. |
| `STRING_BYTES {bytes}` | `STRING` preserves the active `string_value` bytes under the captured `EVALUATE_STRING_ESCAPES` setting, including its intentional empty result when evaluation is disabled.  Keep exact raw source separately; a decoded value is not necessarily a source slice or UTF-8 text. |
| `NO_VALUE` | A reviewed producer route with no active union member, including punctuation and EOF.  Never read union backing bytes to fill this value; an unreviewed route needs a mapping failure, not a guessed zero/name. |

Quoted notes are still `NOTE`/`NAME`: the lexer parses a string then changes the tag and copies its resulting name.
Do not reinterpret the overlapping union as both a note name and a string value.
Identifier storage addresses, interning identity, allocator state and uninitialised union/hash bytes are not payload identity.
If a future consumer requires a derived name hash, define/recompute it from the name with a versioned algorithm rather than persisting incidental `ident_value.hash` storage.
The record retains `ident_is_backticked` and `value_flags` observations even where inactive; their semantic interpretation is controlled by token kind/producer route, not by nonzero union bytes.

The closed `Value_Flags` mask is `0x1070001F`, with names/bits: `HERE_STRING=0x1`, `NUMBER=0x2`, `HEX=0x4`, `BINARY=0x8`, `FLOAT=0x10`, `REQUIRES_FLOAT64=0x100000`, `DEFAULTS_TO_FLOAT64=0x200000`, `REQUIRES_FLOAT64_DUE_TO_SIGNIFICANT_DIGITS=0x400000`, `OVERFLOWED=0x10000000`.
Unknown bits reject conversion under this schema; preserve observed combinations without inventing extra lexical validity rules from flag names.
In particular `HEX` may be set for an integer representation reason rather than a hexadecimal source prefix.
`Note_Flags.IS_SYSTEM_LEVEL` is a separate flag domain, not another interpretation of the overlapping `Value_Flags.HERE_STRING` bit.
The reviewed note producers do not establish a note-flag payload mapping; do not fabricate one from that numeric overlap.

Trivia slice ownership follows the source, not a second concatenated copy.
Keep exactly one immutable source lease plus views; optional copied decoded names/string values belong to the snapshot and survive producer/interner teardown.
The lexer puts each inter-token gap in the following token's `preceding_trivia`, including the final gap before EOF.
EOF has empty original spelling and a byte origin at the end of the exact source.
For reconstruction, concatenate each materialised token's preceding slice then original slice, including EOF; there is no separate trailing-trivia field or EOF reconstruction branch.
Validate against the exact source; do not drop a leading BOM, comments, malformed bytes or the final gap merely because they have no semantic token value.
Trivia classification is optional derived indexing over these slices, not a replacement for them.
The closed kind registry is `WHITESPACE | LINE_COMMENT | BLOCK_COMMENT | SHEBANG | IGNORED`; each item carries a checked source slice and iterator-relative offset mapped back to the parent slice's start.
Preserve `IGNORED` bytes and nested/unterminated block-comment text; classification must not assert on arbitrary source text or discard unrecognised bytes.
A classification gap does not authorise changing the authoritative trivia/source views.
All slices/decoded values borrow through the owning syntax/result lease; no token, trivia iterator or interned name may outlive that lease without an independent copy/retain.

Future qualification vectors: each active union tag; decimal/hex/binary and overflow flags; float32-rounded values, signed zero and exact float-bit transport; quoted/unquoted notes; escaped/here strings with evaluation enabled/disabled; producer/interner teardown; BOM-only/comment-only/empty files; nested comments, ignored bytes and EOF final-gap reconstruction.
The schema does not certify every producer route or define persistent float/text encoding; those require explicit mapping/round-trip review under C1, bounded decoding and the separate persistence contract.

Local review vectors, to become executable acceptance cases only in authorised implementation:

- `K("x", ["ab", "c"]) != K("x", ["a", "bc"])`; changing tag, version, field order or field count changes the key bytes.
Compare complete key bytes, not an assumed collision-free digest.
- Equal source bytes at two document keys can have equal `SourceRevision` but cannot collapse document identity, source-visible context or world membership.
Different newline bytes produce different source descriptors; absent and present-empty remain distinct.
- Equal provider state tokens under different documents/sessions are different revisions.
Analysis retry preserves the frontier; a save observation with unchanged selected bytes may still change provider state/frontier.
- Wrong-world/revision spans, forged handle kind/session/generation, and released/restarted registrations reject before any payload is exposed.
A payload-local node/entry ID is never accepted as a handle or semantic declaration ID.

These vectors refine C1/C2/C3, T2/T3/T5, D1/D2 and V2/V5/V6 without claiming any new behavioural test has run.

#### Source Event Payloads

| Tag | Required payload and transition |
| --- | --- |
| `SET_OVERLAY` | `{source: SourceInput, resulting_provider_revision}`.  Install the exact host-selected buffer over the separately retained disk state. |
| `EDIT_OVERLAY` | `{base_source_revision, edits: []RangeEdit, resulting_provider_revision}`.  Reject base mismatch, invalid ranges or missing editable source; do not silently edit another revision. |
| `OBSERVE_DISK` | `{disk: DiskObservation, resulting_provider_revision}`.  Advance acknowledged disk state, preserving any active overlay; select disk/absence only when no overlay takes precedence. |
| `ACK_SAVE` | `{written_source_revision, disk: DiskObservation(PRESENT), expected_overlay_revision, resulting_provider_revision}`.  Record the actual written bytes and reconcile only the overlay revision the host confirms was saved; preserve a newer overlay. |
| `RESET_OVERLAY` | `{host_confirmation, disk: DiskObservation, resulting_provider_revision}`.  Clear active overlay/recovery selection and choose this acknowledged disk observation.  No hidden latest-disk read occurs during submission. |
| `RESTORE_OVERLAY` | `{host_confirmation, recovery_candidate_identity, source: SourceInput, resulting_provider_revision}`.  Activate only the exact host-confirmed bytes; a recovery blob alone never authorises this event. |

Deletion is an absent disk observation, not an empty `SourceInput`.
Rename/cross-document identity transfer is initially an unsupported event capability until its grammar/identity mapping is specified; callers may submit an explicit old-path absence plus new-path source selection only when the provider confirms those separate document identities and no semantic continuity is claimed.
Closing a buffer must be expressed by the host's chosen source transition, not an implicit reset inferred from releasing a result handle.
This proposed event subset still needs host-adapter review; it does not write editor files or implement save/recovery UI.

#### Operation and Outcome Table

Operation errors are tagged `INVALID_VERSION`, `INVALID_ARGUMENT`, `INVALID_HANDLE`, `BASE_MISMATCH`, `UNSUPPORTED_EVENT`, `ADMISSION_DENIED`, `ACTIVE_SESSION`, or `SERVICE_CLOSED`, with contextual details but no successful source transition.
Provider acquisition errors during admission return a specific unavailable/failure reason without partial acceptance; cache persistence failure alone is not admission failure.
Terminal observations are ticket outcomes `PUBLISHED | SUPERSEDED | CANCELLED | FAILED` or query outcomes `AVAILABLE | UNAVAILABLE | UNSUPPORTED | CANCELLED | FAILED`, with their original selected identities/reasons.
Shutdown observation is `PENDING {phase: QUIESCING | DRAINING}` until terminal `STOPPED {persistence_status, cleanup_diagnostics}`; a wait deadline does not create another terminal shutdown state.
`PENDING` and `TIMED_OUT_PENDING` are observation states, not terminal outcomes or permission to select newer input.

| Operation | Input | Result and exact ownership/state effect |
| --- | --- | --- |
| `OpenSession` | `SessionOptions` | `OPENED {session: Handle(SESSION), description: SessionDescription}` or `REJECTED {error}`.  Allocate a fresh session identity, return the initial accepted frontier and negotiated capability/limit policy, and start with no published analysis head.  Persisted candidates do not become active overlays or live handles.  Store failure may report degraded in-memory operation; no partial session escapes rejection. |
| `DescribeSession` | Live `SESSION` | Coherent value `SessionDescription`; does not advance source state, acquire a world/result lease or activate recovery.  Reading a frontier does not reserve it: a later submit must still validate that base. |
| `SubmitSourceBatch` | Live `SESSION` plus matching `SourceBatch` | `REJECTED {error}` or `ACCEPTED {ticket: Handle(TICKET), accepted_frontier}`.  Own all input before one atomic source-selection transition; return a ticket even if its milestone finishes quickly.  Parse/index or durable-store completion is not implied by acceptance. |
| `RequestAnalysis` | Live `SESSION` plus `AnalysisRequest` | `ACCEPTED {ticket: Handle(TICKET), analysed_frontier}` or `REJECTED {error}`.  Lease the exact selected revisions at that frontier and schedule/join analysis without advancing it.  Supports retry after failed/superseded work without an empty source batch, replayed save event or invented edit. |
| `ObserveTicket` | Live `TICKET` | Atomic terminal observation or `PENDING {waiter: Handle(WAITER)}`.  Each call creating a waiter creates a separately owned notification registration; ordinary repeated polling should use `Poll`, not repeatedly register. |
| `AcquireWorld` | Selector `PUBLISHED_UPDATE {ticket_or_update_waiter}` or `HEAD {workspace, expected_frontier}` | Owned `WORLD`, pending/unavailable, or operation error.  The ticket/update waiter must have a `PUBLISHED` outcome; `HEAD` succeeds only if the published analysis frontier matches the explicitly expected frontier.  Otherwise, report a descriptive pending/frontier-mismatch/no-head reason without creating a waiter; use the ticket or `RequestAnalysis` to obtain an observable milestone.  An omitted selector is `INVALID_ARGUMENT`; there is no implicit latest world. |
| `Query` | `QueryRequest` | `AVAILABLE {result: Handle(RESULT)}`, an immediate terminal reason, or `PENDING {waiter: Handle(WAITER)}`.  Acquire result protection or register the waiter atomically with inspection; an immediate answer creates no completion notification. |
| `Poll` | Live `TICKET`, `WAITER` or `SHUTDOWN` | Stable terminal observation or `PENDING`; no new waiter, no consuming transition and no new payload lease.  An available observation is descriptive until `AcquireResult`; a published observation is descriptive until `AcquireWorld`. |
| `Wait` | Same handle plus monotonic deadline | Same observation as `Poll`, or `TIMED_OUT_PENDING`.  Does not cancel, register another completion record, block a required host dispatch thread safely by magic, or change the selected world. |
| `AcquireResult` | Live query `WAITER` with `AVAILABLE` terminal outcome | New owned `RESULT`; pending/terminal reason otherwise.  Inspection and acquisition are atomic against registration release, so no borrowed payload escapes.  Repeated acquisition creates independent leases that must each be released. |
| `CancelWaiter` | Live `WAITER` | `CANCELLED` if it wins the terminal race, otherwise `ALREADY_TERMINAL {observation}`.  Does not undo a source event, rewrite an update ticket, release the handle or cancel other consumers. |
| `DrainCompletions` | Live `SESSION` plus checked maximum count | Bounded completion records for live pending registrations, at most one terminal record per registration.  Draining does not release registrations or transfer result ownership; records released/reused before later access are safely stale. |
| `Retain` | Live `WORLD` or `RESULT` | New independently owned handle protecting the same immutable payload; copying the original handle bits is not a retain.  Operation fails safely if release won the race. |
| `Release` | Any owned handle | Retire that registration exactly once; subsequent uses, including double release, return `INVALID_HANDLE` without touching a new generation.  A `SESSION` may be released only after `STOPPED`; otherwise return `ACTIVE_SESSION` without retiring it.  Waiter release detaches interest, not source state; active task/delivery ownership persists until its own release. |
| `RequestShutdown` | Live `SESSION` | Owned `SHUTDOWN` observation handle; repeated calls refer to the same shutdown operation through separate owned registrations.  It rejects new work at quiescing, preserves existing leases/observation/release access, and never reports stopped merely because a wait deadline elapsed. |

Payload access requires a live owning `WORLD`/`RESULT` handle.
Read-only descriptions/views borrow from that handle and cannot be used after its release; copies that must survive need their own host storage or `Retain` first.
Tickets and their pending observation waiters each protect the published world until independently released; query waiters protect their terminal result until released.
`AcquireWorld` accepts a published update waiter even after its original ticket registration was released; acquiring a child handle establishes independent protection before the parent can be retired.
Polling/draining is deliberately non-owning to avoid hidden lease growth in a UI polling loop.
No handle survives a process restart, and shutdown never turns an externally retained result into a borrowed pointer to destroyed service state.
After releasing a stopped `SESSION`, already owned child handles remain observable/releasable through their surviving owner; no operation may require borrowing the released session handle to keep a result alive.

#### Bootstrap and Retry Consistency Pass

The interface consistency review identified bootstrap, first-document admission and retry gaps; the operations above now make those paths explicit rather than assuming hidden builder functions or synthetic edits.
Initial session creation and configuration have not thereby been implemented or approved.

```text
OpenSession(explicit workspace/provider/context/limits/store policy)
	-> OPENED(owned session S, initial frontier F0, capabilities)
SubmitSourceBatch(S, expected F0, OBSERVE_DISK or SET_OVERLAY, expected document state UNTRACKED)
	-> ACCEPTED(ticket A, accepted frontier F1)
Observe/Poll/Wait and AcquireWorld for ticket A as below
	-> owned world A, or explicit terminal outcome
If analysis failed but F1 is still selected:
	RequestAnalysis(S, expected F1, tracked documents, SYNTAX_INDEX)
		-> new ticket at F1, with no source mutation
If another source event won first:
	BASE_MISMATCH; DescribeSession(S), then explicitly select/retry
RequestShutdown(S); Poll/Wait shutdown handle until STOPPED
Release observation handles and stopped session when no longer needed
	-> previously retained result/world handles remain independently valid
```

This protocol refines V5/V6 for first admission and retry, X7/X8 for open/shutdown ownership, and T8 for known unsupported capabilities without adding a claim that those tests pass.
Complete record limits, session option validation, identity allocation and real concurrent execution remain specification/qualification work.

#### Worked Edit-to-Result Protocol

```text
SubmitSourceBatch(base frontier A, overlay edit to B)
	-> ACCEPTED(ticket B, accepted frontier B)
ObserveTicket(ticket B)
	-> terminal PUBLISHED, or PENDING(waiter U)
Poll/Wait(waiter U) if created
	-> PUBLISHED(world identity B), or explicit terminal outcome
AcquireWorld(PUBLISHED_UPDATE(ticket B or live update waiter U))
	-> owned world B
Query(world B, active document, SYNTAX_SNAPSHOT)
	-> AVAILABLE(owned result), or PENDING(waiter Q)
Poll/Wait(waiter Q) if created; AcquireResult(waiter Q) when AVAILABLE
	-> owned result with exact world/source identity B
Release created waiters and ticket; use result/world while leased
Release result and world when finished
```

Handle every rejection, supersession, timeout and terminal reason rather than assuming the happy path.
On supersession, explicitly choose/request a successor ticket/world; do not query a head world and silently call it B.
Multiple queries may retain the same world, and retaining world A does not prevent publishing B or permit B to mutate A.

#### Latency Boundaries and Acceptance Mapping

Use monotonic timestamps per operation/identity; correlate pending completion with the original ticket/waiter rather than restarting the timer at every poll.

| Metric | Start and finish | Existing acceptance coverage to implement |
| --- | --- | --- |
| Admission latency | `SubmitSourceBatch` entry to accepted/rejected response.  Includes validation/input ownership/admission bookkeeping; report separately from analysis completion. | T2, V5, X7: stale/invalid/closed work rejects truthfully without partial acceptance. |
| Edit-to-usable syntax/index | Submission entry through published milestone and successful `AcquireWorld` for that exact revision, plus acquisition of the requested syntax/index result.  Include queueing, acquisition, parsing, validation and publication; also report service-ready versus host-observed timestamps. | T1, T7, V6: no mixed/old-world result, no false success for superseded/failed work.  This is the main P2/user-edit path. |
| Unchanged query latency | `Query` entry to owned `RESULT`, including `AcquireResult` if pending.  Charge validation, scheduling, rehydration and lease acquisition, not only a resident lookup or first `PENDING` response. | T5, T6, X1-X3: exact payload, safe retention, no lost completion; primary P1 comparison. |
| Restart-to-usable result | Process entry through provider/store validation, world capture/publication and owned requested result.  Report process wall and worker phases separately, with filesystem cache condition. | S1, S2, S6, V2-V4 and T4: source authority, bounded fallback, explicit absent/unknown/recovery.  Optional AST loading is the P3 competitor, not a requirement to decode the historical graph. |
| Delivery/host delay | Service terminal-ready timestamp through host observation/acquisition.  Show separately and within end-to-end totals; delayed host draining must not hide scheduler latency or inflate a claimed parser-only time. | X4, X5, X8: delayed/reentrant dispatch and shutdown retain truthful outcomes/leases. |

Report successful latency alongside rejection, supersession, cancellation, timeout and failure counts; dropping non-successful edit samples must not manufacture a faster tail.
Keep memory/backing/store measurements secondary but visible, with safety and leak obligations unchanged and no numerical P1-P5 cutoff newly approved.
Exact operation signatures, consistency/identity encodings, payload schemas, admission bounds, rename capability and ABI remain review items; these records/tables are not executable acceptance tests.

### Review Decisions and Completion Gate

Prepared 2026-10-20; updated 2026-10-21.
**R1 scope and R3-R5 design directions approved; R2 and R6-R8 remain pending explicit approval.**
E1-E13 provide bounded evidence, and the preceding sections now draft the major contract areas.
That is progress in specification coverage, not evidence that the specification is complete, the proposed policies are approved, or a service has passed acceptance.
Use this list to resolve choices rather than adding further general contract prose without a specific missing requirement.

#### Decisions for Review

| Decision | Recommendation or choice to resolve | Approval boundary and status |
| --- | --- | --- |
| R1: Initial coverage | Adopt the syntax-first qualification slice: owned whole-file syntax/diagnostics/indices and revisioned source/world operations, including source/unsaved-recovery persistence; initially qualify the recorded Windows x64 toolchain/environment.  Keep configured semantic queries, evaluator execution and higher editor features explicitly unsupported until qualified. | Scope approved 2026-10-20.  This narrows the first deliverable, not the eventual full-syntax/full-semantics goal.  Additional compiler/filesystem/platform claims require their own qualification; detailed contracts and implementation remain unapproved. |
| R2: Persistence and recovery policy | Keep source/metadata and unsaved recovery persistence required; do not require full AST reload.  Decide whether to confirm the earlier provisionally enabled default, the private default location/override rules, recovery retention and host reset/discard/clear behaviour. | Pending policy choices; persistence itself is already confirmed.  A direction approval does not choose retention durations, erase prior private data or authorise automatic recovery activation. |
| R3: Source/provider protocol | Adopt finite explicit captures, unknown-versus-absent states, host-controlled overlays and byte-based exact-base edit batches.  Require declared consistency and explicit successor captures for unavailable historical discovery. | Direction approved 2026-10-21.  Exact event schemas and adapter capabilities still need specification; logical source transactions are not atomic disk/editor writes. |
| R4: Execution/delivery | Adopt a logical serialised coordinator with token-checked worker completion, host-pulled outcomes, independent waiter cancellation and lease-safe shutdown. | Direction approved 2026-10-21.  Thread model, admission/queue limits, fairness and last-consumer worker-stop policy are not chosen by approving these invariants. |
| R5: Identity and invalidation | Preserve configured instance/load-occurrence distinctions and nominal identity; use conservative misses for uncertain matches and whole-module semantic invalidation until finer tracked facets are qualified. | Direction approved 2026-10-21.  Canonical encodings and matching algorithms are technical specifications still to write; this does not enable a semantic feature. |
| R6: Resource/store policy | Choose workspace versus shared-store scope, supported concurrent-writer policy, absolute host memory/disk/acquisition limits, retained-history defaults and pressure/repair behaviour.  Prefer no implicit cross-workspace sharing until its identity/privacy/lease rules are approved. | Pending.  No absolute values or sharing defaults are inferred from small fixture bounds or the P4/P5 screening candidates.  Safe decoding requires concrete enforced limits before implementation qualification. |
| R7: Performance acceptance | Approve, revise or replace P1-P5 and their paired workload/timing procedure.  Include a larger representative project; set any absolute interactive targets with host/hardware requirements rather than extrapolating E12. | Pending.  Existing relative targets are proposals, not achieved service results.  A syntax-store speed target cannot waive required source/recovery persistence. |
| R8: Deferred qualification | Agree which initial guarantees are required for release and which claims remain explicitly excluded: OS-cold startup, power-loss durability, broader platforms, semantic/editor workflows and production concurrency. | Pending.  Excluding an optional claim is not passing its test.  Concurrency required by an adopted store/execution model still needs qualification; no cache flush, reboot, privilege change or arbitrary source evaluation is authorised. |

The 2026-10-20 scope approval settled R1.
On 2026-10-21 the user explicitly approved R3-R5 as design directions and the fifteen-operation interface as the specification baseline, subject to exact schemas and API review.
These approvals do not settle R2/R6-R8, choose detailed encodings/algorithms/threading/limits, authorise implementation, or approve a migration plan.
The user prioritised latency over memory-related overhead on 2026-10-20; exact P1-P5 numerical cutoffs were not explicitly approved, so R7 remains pending.
Record exactly which decisions changed, their date and any exclusions; do not turn a general continuation request into blanket approval of R1-R8.
Approval, implementation status and qualification status are independent: an approved requirement can remain unimplemented and untested.

#### Reading the Performance Candidates

P1-P5 are proposed go/no-go screening criteria for future implementations/optimisations, not measured editor guarantees or runtime configuration defaults.
Percentages compare a candidate with an equivalent fresh/owned baseline on the same workload and hardware; they are not percentages of total project compilation time.
For latency, median is the middle-measured time; p95 is a tail statistic, estimated here by nearest rank across at least 21 trials, not a worst-case bound.

| Candidate | What it compares | Example of the proposed threshold, not an observation |
| --- | --- | --- |
| P1: Resident unchanged request | Reuse already-resident validated syntax/index data versus fresh parsing/index construction for the same unchanged input.  Include validation and result acquisition, not just a pointer lookup. | If fresh median/p95 are 20/30 ms, candidate median must be at most 18 ms and p95 at most 31.5 ms.  This asks for a useful typical gain without more than 5% tail regression. |
| P2: Changed-file update | Notify-to-usable-syntax/index latency versus the fresh changed-file path, with identical retained-world ownership.  This covers edits that cannot simply hit unchanged syntax. | With a 10/20 ms fresh median/p95, the candidate must be at most 10.5/21 ms.  This is an overhead/regression allowance, not a demand that edits become 5% faster. |
| P3: Optional persisted AST reload | A fresh process validates/loads/reconstructs equivalent syntax/index data versus reading/validating source and parsing it.  Process wall and worker timing stay separate; compare each timing boundary with its own equivalent baseline. | The same 20/30 ms baseline gives an 18/31.5 ms target.  This tests whether optional AST persistence is worth adopting.  Required source/metadata and unsaved recovery persistence are not rejected if AST decoding fails this speed gate. |
| P4: Retained memory | Peak upstream allocator backing versus owned whole-file parsing for the same live current/historical worlds, plus zero owned live allocations after final release. | A baseline peak of 100 MiB allows at most 110 MiB.  This is not a 110 MiB global budget, and zero owned allocations does not mean the OS process working set immediately falls to zero. |
| P5: Managed store size | Steady-state total managed artifact/manifest/index bytes versus exact source bytes represented by the selected current and retained historical revisions.  Peak temporary publication space is reported separately. | If the selected retained source revisions total 10 MiB, the proposed steady-state store limit is 40 MiB.  This is not four times the entire repository size, and it does not set an absolute disk quota. |

The 10% gain, 5% latency allowance, 10% backing allowance and four-times storage ratio are unapproved engineering candidates, not conclusions established by E1-E13.
They aim to screen out complexity that buys negligible benefit or excessive overhead; different host requirements may justify different limits.
The proposed procedure evaluates real workloads individually over two local rounds, rather than hiding a regression inside one project-wide average.
Current experiments favour resident reuse and show the verbose graph reload is slower; they do not qualify a future editor service against these targets.
Approval can be per candidate, and targets can be revised or left pending until actual host/workload requirements are known.

User priority confirmed 2026-10-20: latency is the primary performance concern; memory/storage overhead is a secondary trade-off, not an equally weighted adoption objective.
Prioritise P1-P3 and visible-file edit/query latency, including tail behaviour.
Continue reporting P4/P5 for informed trade-offs, but do not reject a useful latency improvement solely for missing their unapproved ratios.
This priority does not relax lifetime correctness, safe decoding/allocation bounds, leak checks or host resource-pressure controls, and does not approve unlimited memory/disk use.

#### Technical Specification Work After Direction Review

| Area | Concrete next artifact required, not another general principle |
| --- | --- |
| Source/API records | Versioned source/capture/ticket/result schemas, edit and multi-document transaction grammar, provider capability set, and an operation/outcome table resolving rejection, timeout and supersession cases. |
| Identity/semantic extension | Exact key canonicalisation, identity allocation/matching and query/dependency record schemas, with a supported initial catalogue and explicit unsupported extension points.  Specify semantic contracts without claiming implementation of deferred rules. |
| Ownership/execution | Handle/lease representation, transfer/release operations, coordinator ordering, lock graph, queue/admission bounds, attempt tokens and final destruction protocol. |
| Persistent store | Exact text grammar using `Text_File_Handler`, escaping/byte encoding, concrete bounds, manifest/operation/session ordering, lock/pin protocol and qualified platform commit/repair primitives. |
| Acceptance mapping | Map each approved requirement to T1-T8, S1-S8, D1-D8, X1-X8 or V1-V8 and an executable oracle/negative control; explicitly mark unsupported cases and add missing cases instead of claiming the existing trace drafts are tests. |

The tables above identify specification deliverables, not a dependency-ordered migration/implementation plan.
No production edits follow merely because a record has been described, or a review item is accepted.

#### Exit Criteria Before Migration Planning

- [ ] Record explicit initial-scope/direction decisions and resolve or explicitly defer each R1-R8 item without leaving an implicit production default.
- [ ] Complete exact schemas/protocols for every initial requirement, including its owner, identity/version rule, state transition, failure behaviour and acceptance oracle.
- [ ] Check the contracts together for conflicts: provider versus analysis frontiers, current versus retained worlds, task versus waiter lifetime, source availability versus store durability, and logical identity versus artifact revision.
- [ ] Approve the initial workload/platform matrix and acceptance thresholds; separate previously observed experimental evidence from future implementation qualification.
- [ ] Identify later capabilities and their extension/unsupported contracts, then perform the section 14 specification-completion review before writing a separate migration plan.

Production acceptance tests can only qualify an implementation that exists; this design gate requires their executable acceptance criteria and planned oracles, not false claims that unimplemented traces have passed.
Implementation authorisation, migration sequencing and the independent AST-copier keep/drop decision remain separate.

### Experiments to Run First

Use small isolated fixtures/prototypes, not a parallel implementation of the new parser.
Record the hypothesis, exact compiler/build configuration, commands, observed output, limitations, and resulting decision for each experiment.
Language probes use the official compiler as the oracle, including separate expected-failure cases; prototype cache tests compare against fresh computation.
These are proposed manual probes on authored trusted fixtures; listing them does not authorise their execution or automatic evaluation of arbitrary workspace code.
E1-E11 have been completed as recorded below.
E12's bounded real-source baseline and same-layout owned AST text-reload comparison are recorded below; performance-policy approval and complete semantic editor-workflow measurements remain open.
E13 completes the bounded explicit `using,map` wrapper follow-up, not a production evaluator or general compilation-context extractor.

| ID | Experiment and discriminating check | Decision it informs |
| --- | --- | --- |
| E1 | Completed: import/visibility matrix using bare and named imports at file, procedure, nested-block, and struct scopes; export/module/file visibility; access inside, outside, from siblings, and from another loaded file.  Each access compiled separately. | Verified scope receiving imported names, lexical namespace binding, and qualified module/file visibility; see results below. |
| E2 | Completed: repeated/aliased imports, omitted/explicit defaults, argument order/types/values, nominal assignment compatibility, two-hop imports, and program-setting constraints; 32 isolated probes and evaluation-count audit. | Canonical source plus effective parameter values is insufficient for compatible nominal identity; program configuration is per module and main-program controlled.  See results below. |
| E3 | Completed: 28 isolated loaded-file composition probes for repeated/diamond/aliased loads, order, relative paths, file scopes, module instances, collisions, missing files, and cycles; diagnostic and execution-marker audit. | Preserve load occurrences rather than deduplicating membership; share syntax without sharing contextual bindings or nominal declarations. See results below. |
| E4 | Completed: 35 isolated path/source-context probes covering casing, dot/parent/separator/absolute aliases, copied and relocated bytes, relative loads/imports, working-directory changes, junctions, and native directory/file symlinks; exact location/path, nominal identity, diagnostic, and execution-marker audit. | Keep physical document identity, source-visible path context, and compiler-compatible module identity distinct; request validation can differ even when the filesystem reaches the same source. See results below. |
| E5 | Completed: 32 compiler-evaluation compilations and five separate startup samples covering `do_output=false`, insert dumps, multiplicity, expression boundaries, context, `using,map`, multiple workspaces, stale artifacts, diagnostics, failures, and flattened-dump replay; complete artifact/log audit. | The text channel works for bounded trusted generators, but is not a fresh, self-contained semantic-result protocol.  Evaluator support remains deferrable; see results below. |
| E6 | Completed: eight syntax fixtures across 32 producer/context lifetime permutations, 32 fresh-parse oracles, 248 exact syntax checks, 96 independently owned semantic-context lifetimes, decoded-payload mutations, span/recovery validation, and a real-resolver shallow-alias control. | Owned syntax and external semantic tables survive independent teardown; current in-node bindings alias across shallow snapshots.  This establishes a bounded ownership contract, not a full overlay-replacement decision; see results below. |
| E7 | Completed: 23 edits of an 11-query model under tracked and conservative-module policies; 2,530 fresh comparisons, 1,600 link-stamp checks, exact recomputation expectations, retained old worlds, and 11 broken-policy controls. | Parent relationships and target revisions need independent validation; missing names and candidate sets are dependencies; equal observable results can stop propagation; world selection and identity/context guards are mandatory.  Conservative module invalidation is correct but recomputes more in this model; see results below. |
| E8 | Completed: 17 scheduler scenarios in both forward and reverse order, 844 authored expectation checks, 17 completion-equivalence checks, and eight broken-policy controls; independent audit of task, request, and dependency traces. | Publish individual milestones, deduplicate world-keyed work, cancel waiters independently, diagnose actual unresolved graph cycles rather than idleness, and reject duplicate/late completion after terminal states.  See results below. |
| E9 | Completed: direct `Pool`/`Bucket_Array` API probes; three allocation strategies across 54 memory phases, 5,232 handle/payload checks, 264 cleanups, three stale-generation controls, and 63 optimised rotating-order timing samples. | Typed slots enable individual record reuse, but payload ownership and bucket/group reclamation determine backing retention.  Arenas were faster in this small workload; separately freed payloads reduced sparse-eviction backing.  See results below. |
| E10 | Completed: five pointer-free text fixtures using `Text_File_Handler`; 153 exact record comparisons after producer/input teardown, 41 invalid cases, 2,872 rejected truncations, and 126 optimised decode/parse timing samples with independent wire-format/value/statistics audit. | An explicit bounded schema preserves exact bytes and numeric bits; the handler supplies line/version handling, not serialisation or validation.  Payload-heavy text can cost more than fresh parsing.  See results below. |
| E11 | Completed: filesystem store/restart/overlay model with 911 parent-process checks, 32 worker processes, five killed publishers, competing publication/retry, twelve corruption cases, real cache-directory write denial, save/reset/deletion/reappearance, lease-aware GC, four broken-policy controls, and an independent saved-evidence audit. | Immutable digest-addressed blobs plus locked manifest replacement preserve complete selected states under the tested interruptions.  Recovery is host-confirmed, exact source hashing defeats stale timestamps, and cache failures must preserve source operations and surface diagnostics.  See results below. |
| E12 | Representative project baseline: measure fresh parse, unchanged-file reuse, and text reload with validation across many small files and large active files, transitive imports, malformed edits, body/interface changes, and repeated updates.  Include hashing/I/O, tail latency, retained worlds, and disk size; distinguish process restart from OS-cold filesystem cache. | Workload selection, numerical acceptance targets, initial cache granularity, and whether syntax persistence earns its overhead.  Reuse existing benchmark/oracle infrastructure where applicable. |
| E13 | Completed: explicit generated-array `using,map` wrapper versus real mapping, six equivalent pairs, module parameter/private-helper context, exclusions, three compiler rejections, invalid-output policy, twelve damaged-frame controls, and post-process host ownership. | The explicit wrapper works for this supported slice; preserve context and positional exclusions, require successful compilation before publication, and do not mistake a conservative identifier policy for compiler behaviour.  See results below. |

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
| Direct self-load and two-file load cycle | Rejected at the compiler's maximum of 100 nested loads; neither is silently deduplicated nor accepted as legal recursion. |
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
| Byte-identical modules relocated beside different neighbours | Distinct nominal types and values 11 versus 22 for both the relative load and the relative file import. Content equality does not establish dependency or result equality. |
| Byte-identical files with different filenames in the same directory | Same `#filepath`, different filenames in `#location`, distinct nominal types, and two executions. Directory context alone is insufficient. |
| Compile `../probe.jai` with the child process working in `Branch` | Entrypoint reports its normalised source path and still finds the source-relative `Original` module, not an unrelated directory under the process working directory. |
| Missing source-relative neighbour | Explicit missing-file error naming `Isolated/neighbor.jai`; the root decoy is not substituted. |
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

#### E5 Results: Compiler-Evaluation Feasibility

Completed 2026-10-19 on Windows with Jai beta 0.2.030, built 2 July 2026, using the fast x64 backend.
Reproducible runner: [experiment_compiler_evaluation.jai](examples/experiment_compiler_evaluation.jai).
From the parser's examples directory:

```bash
jai experiment_compiler_evaluation.jai -x64 -quiet -no_color
```

Hypothesis: `do_output=false` plus enabled added-string emission can expose generated text, but artifact existence/content alone may not establish freshness, semantic completeness, or equivalent extracted execution.
The runner executes authored trusted fixtures only, with native output disabled and a 30-second child-process timeout.
Ordinary cases start with cleared added-string files; one explicit sequence deliberately preserves them across changed source revisions.
Each compilation records its input revision, captured output artifacts, log, exit status, artifact count/size, and monotonic wall time.

All 32 compilations matched their assertions: 24 accepted and eight expected rejections, with no skips, plus five successful version-only startup samples.
These include five no-insert baseline compilations and a separate replay of the actual parameterised-module dump.
The final audit checked all 24 archived artifact files, including intentionally stale snapshots, nine compiler `Error:` lines, one deliberate compile-time assertion failure, exact callback order/results, workspace boundaries, generated locations, and three SHA-256 stale-file comparisons.
No executable, object, PDB, DLL, or library output was found in the fixture tree.
Compiler identity was separately confirmed with `jai -version`; the timed version-only subprocess captures were empty despite successful exits, so they are not used as version evidence.

| Probe family | Observed result |
| --- | --- |
| Single insert with `do_output=false`, `write_added_strings=true` | Compilation succeeds and produces `.build/.added_strings_w2.jai`, including a workspace comment, source-file/line comment, and inserted declaration. Native output suppression does not suppress compile-time execution. |
| Multiple and nested inserts | Multiple records share one workspace file. A nested insert leaves both the original inserted directive and the resulting declaration in that file; its provenance points back into the intermediate file. |
| Repeated identical insert text in distinct structs | Both occurrences are retained, not content-deduplicated. Their original struct scopes are not reconstructed by the flat record format. |
| Empty insert versus no insert | An empty insert creates a header-only artifact. A clean no-insert compilation creates none; a reused directory can instead retain an older file. |
| Expression insert | The returned expression text needs its own semicolon: `40 + 2;` succeeds, while `40 + 2` produces a semicolon diagnostic and still leaves the returned text in the artifact. This is also documented by the compiler's insert example. |
| Header-like content inside an authored payload | Compiles unchanged. The payload contains a comment matching the compiler's apparent insert-record header, so splitting solely on those comments cannot reliably delimit arbitrary generated text. |
| Insert in a loaded file | Produces the expected declaration and names the loaded source file in its provenance comment. |
| Context-dependent generator, with and without its loaded input | With the loaded `secret` value it generates 42; without that input the same generator fails. The missing-context case reports both the unavailable input and the generated declaration that never becomes available. |
| Same imported source with parameters 17 and 25 | Both contextual values compile and appear in one workspace dump as declarations with the same name and source-file/line provenance. Replaying that actual dump at a single top level rejects it as a redeclaration, reported twice. A flat dump does not preserve module-instance identity or scope; record order is not a source-order contract. |
| `using,map` | The callback receives `left`, then `right`, mutates them to `mapped_left`, then `mapped_right`, and the compiled test verifies writes through those aliases. Instrumented stdout records the ordered inputs/results, but no added-string artifact is created. The dump is not an automatic mapping-result channel. |
| Generated `#filepath` and `#location` | Observe the intermediate directory/file, not the authored insert site: the tested anchor is in `.build/.added_strings_w2.jai`, line 6, column 14. Existing textual provenance does not itself provide a structured source map. |
| Parent plus child compiler workspace | Produces two files, `w2` and `w3` here, with distinct workspace comments. The child file contains both an `add_build_string()` record and its nested insert result. Do not assume one file, a universal workspace number, or insert-only contents. |
| Generated parse/type errors | Both reject with diagnostics pointing into the generated file plus the originating insert directive; their artifacts still contain the invalid text. Artifact existence is not successful evaluation. |
| Deliberate assertion inside the generator | Returns compiler exit status 1, with the authored assertion message and stack trace, and no fresh artifact in its clean directory. This is a compile-time program failure, not an induced native compiler crash. |
| Reused-directory freshness sequence | A successful changed insert replaces old content. Removing all inserts leaves the previous file byte-identical; disabling emission also leaves it byte-identical; an early authored parse error leaves that same stale file. An error in newly generated text replaces it with the invalid new text, and a later successful run replaces that with the recovery result. |

Startup was measured separately from source compilation, around the same `run_command` path and captured-output process handling:

| Measurement | Samples | Minimum | Median | Maximum |
| --- | --- | --- | --- | --- |
| `jai -version`, process/CLI startup only | 5 | 173.873 ms | 176.788 ms | 183.992 ms |
| No-insert compilation with Basic/Compiler imports and build-option setup | 5 | 260.185 ms | 282.648 ms | 329.836 ms |

These are sequential samples from one interactive Windows session, not OS-cold measurements, a representative project baseline, or an isolated per-expression evaluation cost.
They include launch, process handling, and the respective command's work; do not subtract the medians and call the difference the cost of `#insert`.
E12 remains responsible for representative end-to-end latency and acceptance targets.

Generated sources, per-revision `capture_*` directories, logs, `summary.tsv`, `startup.tsv`, the temporary PowerShell `audit.ps1`, and `audit_summary.json` remain under `examples/.build/compiler_evaluation/`; cleanup may remove them.
The Jai runner regenerates fixtures, asserts expected acceptance/exit statuses and artifact counts/content, and captures evidence; the separate audit additionally validates exact diagnostic counts/classes, occurrence/header-like counts, mapping order, locations, and stale hashes.
No native compiler crash, forced timeout/cancellation, process-tree limit, sandbox, hostile output-size case, other compiler/backend/platform, or concurrent publication protocol was tested.
The header-like payload is a deliberately authored boundary control, not permission to execute arbitrary workspace code.

Architectural consequence: this is a viable low-level text output channel for explicitly supported trusted generators, not a generic evaluator or a dump that can simply be reparsed into equivalent semantics.
A future backend needs request-owned fresh output space, successful-completion validation, all-workspace discovery, explicit result framing, context/module identity, source provenance, and a separate supported contract for mapping results.
Failed-compilation artifacts may aid diagnostics but must not be published as successful current results; unknown dependencies/effects remain unsupported or non-persistable.
Compiler-backed evaluation can remain disabled/unsupported while the syntax-first service proceeds.
Opt-in, host trust, scheduling, cancellation, and dependency/effect contracts are still required; feasibility does not settle or implement them.

#### E6 Results: Syntax and Semantic Independence

Completed 2026-10-19 on Windows with Jai beta 0.2.030, built 2 July 2026, using the fast x64 backend and a native runtime verifier.
Reproducible runner: [experiment_syntax_independence.jai](examples/experiment_syntax_independence.jai).
From the parser's examples directory:

```bash
jai experiment_syntax_independence.jai -x64 -quiet -no_color -output_path .build -exe experiment_syntax_independence
./.build/experiment_syntax_independence.exe
```

Hypothesis: a small, independently owned syntax projection can outlive the parser/input that produced it and support independent semantic side tables without mutation or lifetime coupling between those contexts.
The counter-control asks whether shallow copies of today's parser snapshot already provide that property when the existing resolver writes bindings.
This experiment calls the existing parser with trivia and identifier interning enabled and automatic identifier resolution disabled; it does not implement another parser or a second full AST.

The projection owns exact source and filename bytes, tokens with source-backed views into that owned source, token byte/line/column/trivia-start positions, top-level declaration names/spans, expression kind/spans, selected literal payloads/flags, and identifier spellings.
It also independently owns syntax diagnostic messages and related-information arrays, recovery records, restart spans, and synthetic-token metadata/text.
It retains no parser-node pointers, resolved declaration links, inferred types, or semantic-context pointers.
Unprojected expression/procedure structure remains available only as exact source/tokens and kind/span descriptions; this is deliberately a small ownership model, not complete syntax-tree coverage or a persistence schema.

| Fixture | Status | Declarations | Tokens | Diagnostics | Recovery Records | Synthetic Tokens |
| --- | --- | --- | --- | --- | --- | --- |
| Scalar, external reference, escaped string | COMPLETE | 3 | 16 | 0 | 0 | 0 |
| Here-string and external reference | COMPLETE | 2 | 14 | 0 | 0 | 0 |
| Missing semicolon between declarations | RECOVERED | 2 | 10 | 1 | 1 | 1 |
| Missing closing parenthesis | RECOVERED | 2 | 12 | 1 | 1 | 1 |
| Error inside a procedure, followed by another declaration | RECOVERED | 2 | 21 | 1 | 1 | 0 |
| Truncated procedure/declaration | INCOMPLETE | 1 | 10 | 3 | 3 | 2 |
| Empty source | COMPLETE | 0 | 1 | 0 | 0 | 0 |
| Empty string, full-width unsigned literal, external reference | COMPLETE | 3 | 16 | 0 | 0 | 0 |

Each fixture runs with producer teardown before versus after attaching the two contexts, and with the left versus right context released first: 32 scenarios in total.
All scenarios passed, comprising 16 complete, 12 recovered, and four incomplete primary snapshots.
Their summary rows contain 60 declarations, 400 tokens, 24 diagnostics, 24 recovery records, and 16 synthetic tokens; these totals exclude the additional fresh oracles and alias-control parse.
Every scenario checks initial source reconstruction, retained span/index bounds, and exact projected syntax equality through lifecycle transitions and against an independently reparsed/projected oracle.
There are 32 fresh-oracle comparisons and 248 successful exact syntax checks overall.

The original source and filename are overwritten with `0xDD` before being freed.
Parser node, builder, syntax, oracle, and semantic pools use the existing `Pool.overwrite_memory` debugging facility during teardown, rather than relying only on unmodified freed buffers.
All pools are initialised against the upstream allocator before installing their own allocator context; the stable syntax pool is not allocated through the transient builder or a semantic context.
The owned projection and live semantic context remain valid after parser tree, identifier storage, original buffers, and builder storage are released.

The two semantic contexts share one syntax pointer but own distinct symbol objects, binding arrays, and decoded-string copies.
The same external identifier binds to values 19 and 41 through different context-owned symbols; mutating the left symbol to 23 leaves the right context and syntax unchanged.
Eight explicit decoded-string mutations likewise alter only the left context's copy, then are restored for subsequent checks.
Either context can be released first while the other remains valid; after both are released, a third context with value 67 can attach to the retained syntax.
All 96 context creations have matching releases.
Releasing an independent fresh oracle's storage also leaves the original syntax unchanged.

The negative control uses the actual `resolve_lexical_references` operation on one shallow `Parsed_Source` alias.
The second alias observes the same identifier node and newly written `resolved_declaration` pointer.
This confirms the current shared-node mutation boundary without changing the production parser or resolver.

`summary.tsv`, `audit_summary.json`, and `compiler_version.txt` remain under `examples/.build/syntax_independence/`; native verifier/linker outputs are under `examples/.build/` and cleanup may remove them.
The saved-summary audit checks all four lifetime permutations per fixture, context-independent status/metadata counts, exact aggregate counts, compiler identity, and runtime completion counters.
Creation/release counters are logical ownership evidence, not a measured zero-leak, allocator high-water, or operating-system residency result.

Architectural consequence: own or lease source/decoded payloads and recovery data with the syntax revision; keep context-dependent bindings/results in separately owned side tables, with a one-way semantic reference to syntax whose backing lifetime remains valid.
Shallow snapshot copying is insufficient if the existing resolver can still mutate shared identifier fields.
Reusing current node layouts behind a frozen adapter may be possible if all such writes are redirected, but this projection does not establish the cost or completeness of that adaptation, nor require wholesale replacement of every overlay.
No production syntax/cache implementation or migration plan was added.

The prototype does not provide full syntax coverage, a real semantic typechecker, dependency tracking, lease enforcement, concurrent readers, cancellation, persistence, allocation benchmarks, or cross-backend/platform guarantees.
It deliberately does not release syntax while live semantic contexts still refer to it; enforcing that lifetime rule belongs to the owner/lease contract.
No claim of complete diagnostic-related-information variants or synthetic literal-payload coverage follows from these fixtures.
E7-E11 test the separate dependency/revision, scheduling, allocation, text-representation, and store/restart contracts below; E12 retains the representative-performance question.

#### E7 Results: Dependency and Revision Validation

Completed 2026-10-19 on Windows with Jai beta 0.2.030, built 2 July 2026, using the fast x64 backend.
Reproducible runner: [experiment_dependency_revisions.jai](examples/experiment_dependency_revisions.jai).
From `examples/`:

```bash
jai experiment_dependency_revisions.jai -x64 -quiet -no_color -output_path .build -exe experiment_dependency_revisions
./.build/experiment_dependency_revisions.exe
```

Hypothesis: validating the parent's current relationship and independently validating its target in the requesting world permits safe reuse, including when a changed target revision has an unchanged observable value.
Parent stamps alone, unvalidated target stamps, omitted negative dependencies, or a latest-world shortcut must produce stale results on discriminating fixtures.
Conservative module invalidation should agree with fresh evaluation when the module revision covers every modelled edit, at the cost of additional recomputation.

The authored graph has 11 queries: constant, signature, body, candidate membership, scope membership, derived value, call, body analysis, lookup, layout, and layout consumer.
Queries return an integer plus `COMPLETE`, `MISSING`, or `AMBIGUOUS` status.
The uncached evaluator recursively traverses the graph without reading cached records; it shares the pure arithmetic/status evaluator with the cached path.
Separately authored expected focus results and exact per-query recomputation sets check both correctness and reuse rather than relying only on that shared evaluator.

Each scenario retains an initial world and a distinct edited world.
Input source revision, owner identity, and context key gate a full comparison of the parent's definition, arguments, and target list.
The target is recursively validated in the requesting world before its result revision is compared with the link's observed revision.
Changed target identity/context forces direct consumer recomputation even when its numeric value is unchanged; an unchanged numeric result at that consumer can then stop further propagation.
Every published world-specific record contains `checked_parent_revision`, `observed_dependency_revision`, target identity/context, and the observed value.
The checked-parent stamp is verified against the record's input revision; the prototype uses that input metadata to decide when to recheck the relationship, rather than maintaining a separate mutable per-link validation cache.

The 23 scenarios cover unchanged input, parent-only revision changes, retargeting, argument changes, dependency-only changes, body-only changes, equal signature/body/constant values at new source revisions, added/ambiguous/removed overloads, missing names appearing and disappearing, absent links appearing, parent links disappearing, identity/context changes with colliding source revisions, simultaneous parent/dependency changes, and transitive constant/layout changes.
The edited focus is queried before the complete world, exposing stale transitive reuse without first refreshing unrelated leaves.
Retained old and edited worlds are then queried alternately without further computation.
The tracked cache's retained initial records are also serialised before and after edited-world publication and compared for immutability.

Observed results:

- All 23 scenarios passed under both policies, with 2,530 cached-versus-fresh comparisons and 1,600 link-stamp checks.
- The edited worlds required 50 tracked recomputations versus 242 conservative-module recomputations.
These exclude the 506 initial computations across both policies and all scenarios; they are counts, not timing measurements.
- Body-only edits recomputed body and analysis, not call/signature consumers.
New source revisions with equal signature/body/constant values required no computations, while advancing leaf result revisions and refreshing dependency observations.
- A changed constant identity with the same numeric value recomputed constant and value, but retained layout and layout-consumer computations after value validation.
- Missing and ambiguous outcomes agreed with fresh evaluation; scope/candidate dependencies invalidated them when membership changed.
- There were 46 retained-old-world requery passes across the two policies, with no extra computations and no mutation of the tracked initial records.

Eleven negative controls use deliberately broken branches in the same cache evaluator, enabled only after a correct baseline is populated.
They expose parent-only validation; trusting dependency revisions without validating their inputs; omitting candidate, missing-name, or body dependencies; ignoring owner identity or context; skipping parent retarget, absent-link, or removed-link rechecks; and returning the latest record when an older world was requested.
Every control returns a status/value different from the fresh oracle, not merely a different bookkeeping field.

Saved evidence is under `examples/.build/dependency_revisions/`: `summary.tsv`, `results.tsv`, `links.tsv`, `negative_controls.tsv`, `audit_summary.json`, and `compiler_version.txt`.
The independent PowerShell audit parses the TSV/JSON records, verifies all 1,012 unique query records and 640 dependency links, checks complete world/query membership, reconciles parent/target identity/context and both stamps, compares policy results and recomputation totals, and confirms all 11 control mismatches.
It also reconciles the runtime comparison/stamp and old-world counters
The complete executable exits successfully, including cleanup.

Architectural consequence: retain both relationship validation and recursively validated dependency observations; record unsuccessful lookup and candidate membership as dependencies; key records to the requested world and owner/context; preserve immutable published old results; and propagate changes according to the consumer's actual observable result.
Conservative module invalidation remains a viable correctness baseline only if its revision incorporates every relevant change; the additional modelled recomputations do not establish a production latency trade-off.

This is an authored acyclic integer-query model, not real Jai overload resolution, type identity, layout, dynamic dependency discovery, or a semantic typechecker.
It assumes immutable uniquely identified worlds, truthful source/module revisions, complete predeclared dependency lists, and cache-local monotonic result revisions.
The equal-value comparison is exact status/integer equality, not a hash; no collision handling or general semantic fingerprint contract was tested.
The experiment covers isolated two-world edits, not a long edit stream, concurrency, cycles, scheduling, cancellation, leases, eviction, persistence/reload, memory bounds, or performance.
No production cache implementation or migration plan was added; E8-E11 test the separate scheduling, allocation, text-representation, and store/restart contracts below, while E12 remains a separate experiment.

#### E8 Results: Pipeline Milestones and Scheduler Outcomes

Completed 2026-10-19 on Windows with Jai beta 0.2.030, built 2 July 2026, using the fast x64 backend.
Reproducible runner: [experiment_pipeline_scheduler.jai](examples/experiment_pipeline_scheduler.jai).
From `examples/`:

```bash
jai experiment_pipeline_scheduler.jai -x64 -quiet -no_color -output_path .build -exe experiment_pipeline_scheduler
./.build/experiment_pipeline_scheduler.exe
```

Hypothesis: world-keyed declaration milestones can publish independently and share one computation among multiple pending requests; legal recursion depends on which milestone is required, not merely whether declarations refer to one another.
An idle scheduler must remain pending for an unfinished external task, while an actual cycle of unresolved prerequisites must be diagnosed even when unrelated external work also exists.
Cancellation and shutdown must deliver explicit terminal outcomes without corrupting shared work, completed payloads, or world selection.

The bounded deterministic model represents signature, body, layout, and externally completed tasks with authored integer payloads.
Each task key is `(world, declaration, milestone)`; requests join that existing task and return either its immediate outcome or a pending handle.
All configured tasks are scheduled; this is not a demand-discovery implementation.
One scheduling step publishes ready work or propagates an explicit failed prerequisite, then notifies pending requests.
At quiescence, transitive reachability over unresolved prerequisite edges identifies cyclic members; mutually reachable members receive the same canonical diagnostic group, while downstream dependents receive `FAILED` with a blocking-task ID.
External tasks have no fabricated completion edge and remain pending until a simulated callback supplies a terminal result.

The 17 scenarios run under both forward and reverse task traversal:

- Signature/layout readiness before a body waiting on external work; immediate available queries and terminal unknown-milestone queries.
- Self and mutual pointer-layout references requiring signatures, and mutually recursive procedure bodies requiring signatures rather than each other's completed bodies.
- Self and mutual by-value layout cycles, with downstream failure distinct from cycle membership and unrelated external work still pending.
- Three additional idle drains while an external result is outstanding, followed by successful completion and resumption.
- Shared pending handles, cancellation of one waiter without cancelling another's work, repeat cancellation, and attempted cancellation after publication.
- Cancellation of all waiters followed by shutdown; this model deliberately retains the computation until shutdown rather than selecting a last-waiter eviction policy.
- External failure and unsupported outcomes, transitive failure propagation, and independent successful work.
- Simultaneous old/new worlds, old completion arriving after the current world changes, retained old results, and independent current-world completion.
- Idempotent shutdown, new requests after shutdown, rejected wrong-token and duplicate completions, and rejected external completion after shutdown.

All 34 scheduling runs passed, 844 authored expectation/invariant checks.
Seventeen normalised completion snapshots agreed across the two orders, including task identity, terminal/pending outcome, payload, run count, cycle group, failure provenance, dependency list, request world, and notification count.
Logical publication ticks are deliberately excluded from order equivalence because different traversal orders legitimately change readiness timing.
Successful tasks ran once; available tasks had available prerequisites; pending-on-return requests received exactly one notification upon becoming terminal, while immediate responses received none.
Cancelled waiters retained their cancellation result even if the shared task subsequently completed or shut down.

Eight negative controls deliberately treat all stalled work as cyclic, cancel shared work with one waiter, ignore the requested world, impose a declaration-wide completion barrier, notify a completed waiter repeatedly, accept completion after shutdown, omit cycle detection, or require a recursively referenced pointer's layout rather than its signature.
Each differs from an authored expected outcome or notification/value measure.
The pointer-layout control changes a prerequisite edge; the other controls select broken branches in the same scheduler operations.
These controls establish fixture discrimination, not exhaustive scheduler correctness.

Saved evidence is under `examples/.build/pipeline_scheduler/`: `summary.tsv`, `tasks.tsv`, `requests.tsv`, `dependencies.tsv`, `negative_controls.tsv`, `audit_summary.json`, and `compiler_version.txt`.
The independent PowerShell audit parses all records and reconciles 244 task records, 50 request records, and 190 dependency edges.
It checks unique task IDs and world/declaration/milestone keys, request/world agreement, exact notification and computation counts, prerequisite readiness and publication ordering, failed-prerequisite provenance, cycle membership and canonical groups derived from the saved graph, equivalence across traversal orders, all eight control mismatches, compiler identity, and the source's final newline.
The complete executable exits successfully, including cleanup.

Architectural consequence: schedule and publish individual declaration milestones rather than waiting for a declaration or whole program to finish all work.
Use actual prerequisite edges to distinguish legal signature/pointer recursion from impossible by-value layout dependencies.
Keep request cancellation separate from shared computation ownership, make pending and terminal outcomes explicit, and preserve the captured world through completion and display filtering.
Diagnose cycles from the unresolved wait graph, not lack of forward progress; unrelated externally resumable work neither proves nor disproves a particular internal cycle.
On shutdown, stop accepting work, terminally resolve pending handles, preserve already published results, and reject late completions.

This is a fixed-capacity, single-threaded event model with at most 16 tasks, 16 requests, and four prerequisites per task, not a production scheduler, semantic engine, or compiler scheduling oracle.
Integer arithmetic and manually authored prerequisite lists stand in for semantic computation; no source-language recursion rules or real layout sizes were compiler-verified here.
The graph assumes fixed mandatory prerequisites, no dependency alternatives, and external leaf tasks; dynamic/generated work discovery, actual asynchronous processes, reentrant callbacks, concurrency/races, priorities/fairness, leases/reclamation, cancellation of a running worker, update tickets/coalescing, and persistent publication are untested.
The small transitive-closure cycle detector establishes classification only, not a scalable algorithm or complete user-facing cycle diagnostic.
No latency, allocation, or throughput claims follow, and no production API, cache, or migration plan was added.
E9-E11 test allocation/reclamation, text representation, and store/restart below; E12's bounded baseline follows them.
The separate explicit `using,map` wrapper probe remains unrun.

#### E9 Results: Allocation, Eviction, and Retained Snapshots

Completed 2026-10-19 on Windows with Jai beta 0.2.030, built 2 July 2026.
Reproducible runner: [experiment_allocation_eviction.jai](examples/experiment_allocation_eviction.jai).
Both the fast x64 build and optimised LLVM build passed all lifetime checks; the saved timing evidence below is from the optimised LLVM run.
From `examples/`:

```bash
jai experiment_allocation_eviction.jai -x64 -quiet -no_color -output_path .build -exe experiment_allocation_eviction
./.build/experiment_allocation_eviction.exe
jai experiment_allocation_eviction.jai -o -llvm -quiet -no_color -output_path .build -exe experiment_allocation_eviction_llvm
./.build/experiment_allocation_eviction_llvm.exe
```

Hypothesis: independently reclaimable typed records can reuse slots during sparse eviction, but reducing retained backing additionally depends on owned-payload cleanup and the allocator's bucket/group release policy.
Live snapshot leases must prevent reclamation; after reclamation, allocation-generation checks must reject handles whose logical slots now identify different records.
Individual slot reuse, upstream allocation churn, and actual backing release are distinct measurements rather than interchangeable benefits.

Direct SDK API probes established:

- `Pool` ignores individual frees.
Reset retains its normal blocks and reuses their storage; release returns those blocks to the configured upstream allocator.
- `Bucket_Array` removes individual records and reuses their stable slots through an occupied-slot map/search, not a linked freelist.
Removal alone does not release bucket backing or clean owned payloads.
- `bucket_array_reset` releases both the buckets and its dynamic index arrays.
The SDK's `array_reset` frees storage; `array_reset_keeping_memory` is the separate retaining operation.
- The probe observed the same typed record address/locator after removal and replacement, with a different allocation generation.

`Flat_Pool` was source-inspected but not benchmarked: its virtual reserve/commit model requires different backing instrumentation and also ignores individual frees.
The arena candidate here is the actual SDK `Pool`, not a claimed comparison of every available arena implementation.

The three measured strategies use identical 32-byte records and deterministic owned payloads of 32, 128, 224, 320, or 416 bytes:

| Strategy | Fixed records | Owned payloads | Reclamation unit |
| --- | --- | --- | --- |
| Arena | Per-revision `Pool` | Same per-revision pool | Release the revision group after its last record lease ends. |
| Typed | Eight-slot `Bucket_Array` buckets | Individual upstream heap allocations | Reuse each record slot and free its payload independently; reset the typed pool at final teardown. |
| Hybrid | Same typed buckets | Per-revision `Pool` | Reuse record slots independently, but release payload backing only when the revision group is empty. |

All arena groups use 4,096-byte blocks and a 1,024-byte oversized threshold; no workload allocation reaches that threshold.
The workload creates 32 records, sparsely evicts every fourth record, refills the eight holes, and performs six eight-record edits while retaining two preceding snapshots.
Each edit briefly retains an additional snapshot before releasing the oldest one.
It then drops the current snapshot, checks the retained-only state, releases the remaining snapshots, records empty allocator capacity, and destroys the allocators.
Each strategy creates and logically cleans 88 payloads exactly once; payload bytes are poisoned only after the last lease ends, and every live snapshot's identities/generations and payload bytes are checked after each phase.
Stable control slots use monotonic allocation generations independent of semantic revisions; three controls deliberately bypass that check and observe a different live record through a stale handle.
Metadata-slot reuse is distinct from actual record-address reuse: all strategies reused 32 control slots, while the two typed strategies also reused 32 record addresses in this run.

The untimed profile wraps the upstream allocator with a pointer-size ledger, including bucket/index-array allocations, and requires zero tracked live allocations after teardown.
It records useful live record/payload bytes, retained upstream bytes, peak requested-live bytes, nonlive/overhead bytes, dead allocations pinned inside nonempty arenas, reusable typed capacity, empty buckets, requests/frees, deferred evictions, cleanup, and reuse counts.
Backing minus useful bytes includes metadata, unused slots, alignment/block slack, and dead arena allocations; it is not a claim to isolate heap-external fragmentation.

Observed optimised results:

| Strategy | Peak Backing Bytes | Upstream Requests | Record Address Reuses | Median Lifecycle (us) | Batch p95 (us/lifecycle) |
| --- | ---: | ---: | ---: | ---: | ---: |
| Arena | 32,768 | 9 | 0 | 5.214 | 6.961 |
| Typed | 14,920 | 97 | 32 | 15.808 | 23.328 |
| Hybrid | 34,856 | 18 | 32 | 9.689 | 14.553 |

Sparse eviction reduced live records from 32 to 24 in every strategy.
Arena backing stayed at 8,192 bytes with 1,952 logically dead user bytes pinned by the remaining records.
Typed backing fell from 8,320 to 6,624 bytes as 1,696 payload bytes were individually freed; eight record slots became reusable, but every bucket still contained live records.
Hybrid backing stayed at 9,440 bytes: its eight record slots were reusable, but 1,696 dead payload bytes remained in the nonempty revision arena.
At the empty phase, arena backing was zero, while both typed strategies retained 2,088 bytes across seven empty buckets and their index arrays, with 56 reusable slots.
Explicit typed-pool reset then reduced tracked backing to zero for all three strategies.
Thus even completely empty SDK typed buckets do not trim themselves on individual removal.

Timing is separate from the profile: the upstream ledger and deep handle/payload verification are compiled out of the timed path.
Each strategy has three warmup batches and 21 measured batches of 64 full lifecycles, with rotating mode order; all paths still perform the same record/payload writes, lease management, eviction, cleanup, and normal invariant assertions.
Timing includes control-state setup, snapshot-handle copying, payload poisoning, allocation, and complete teardown; it is not a pure allocator-call microbenchmark.
The recorded measurements in this section saved `QueryPerformanceCounter` ticks and frequency for every batch; the reported p95 is the nearest-rank p95 of batch averages, not an individual edit/request tail latency.
The current runner instead uses `Basic.current_time_monotonic()`, subtracts Apollo timestamps before converting the elapsed duration with `to_nanoseconds()`, and saves nanosecond ticks with a fixed frequency of 1,000,000,000 ticks per second.
Portable-clock smoke runs are kept separate from the original optimised evidence; the original timing table is not a measurement of the changed clock implementation.
This is one optimised local timing round, not a statistically established production speed ratio.

Saved evidence is under `examples/.build/allocation_eviction/`: `phases.tsv`, `profiles.tsv`, `generation_controls.tsv`, `timing_samples.tsv`, `timing_stats.tsv`, `audit_summary.json`, and `compiler_version.txt`.
The independent PowerShell audit reconstructs the logical current/retained record sets and their exact payload sizes without using allocator internals, then checks all 54 phases against those expected live/created/cleaned counts.
It reconciles 5,232 handle/payload or stale-handle checks, 264 logical payload cleanups, backing/useful/overhead accounting, reusable capacity, complete teardown request/free balance, profile totals, three generation-control mismatches, all 63 timing samples and rotating positions, and recomputed median/p95/min/max values from raw ticks.
Compiler identity and the source's final newline were also checked; both executables exit successfully.

Architectural consequence: keep arenas for genuinely co-lived revision/artifact groups; consider typed slots for independently lived fixed-size records, but specify payload ownership and empty-bucket trimming separately.
A hybrid is not automatically lower-retention: small per-revision payload arenas plus persistent typed buckets had the highest peak here despite slot reuse.
Freeing individual payloads improved sparse backing retention at the cost of more upstream requests and higher measured lifecycle time.
Leases and allocation-generation validation remain required regardless of allocator choice; allocator reuse alone provides neither safe lifetime nor semantic freshness.
The evidence supports measuring concrete ownership/group sizes, not selecting one universal allocation scheme or changing the existing AST-copier decision.

Limits: this is a bounded synthetic, single-threaded ownership workload, not parser/query production data or a general graph collector.
It covers one fixed record size, one bucket size, one arena block size, small payloads, six edits, and a two-snapshot retention window; it does not test size-class tuning, oversized/aligned allocations, allocator failure, concurrent access, graph-cycle reclamation, explicit slab trimming, OS working-set reduction, or long-running fragmentation.
Tracked backing is requested bytes retained from the upstream allocator, excluding allocator-private metadata/rounding, temporary internal resize overlap, control/ledger storage, and operating-system residency; returning memory upstream does not prove pages were returned to the OS.
No production cache, allocator API, or migration plan was added.
E10 and E11 test text representation and store/restart below; E12's bounded baseline follows them.
The explicit `using,map` wrapper probe remains unrun.

#### E10 Results: Bounded Text Artifact Round Trip

Completed on Windows with Jai beta 0.2.030, built 2 July 2026, using the fast x64 backend for correctness and optimised LLVM for the final timings.
Reproducible runner: [experiment_text_artifacts.jai](examples/experiment_text_artifacts.jai).
From the parser's examples directory:

```bash
jai experiment_text_artifacts.jai -x64 -quiet -no_color -output_path .build -exe experiment_text_artifacts && ./.build/experiment_text_artifacts.exe
jai experiment_text_artifacts.jai -o -llvm -quiet -no_color -output_path .build -exe experiment_text_artifacts_llvm && ./.build/experiment_text_artifacts_llvm.exe
pwsh -NoProfile -File .build/text_artifacts/audit.ps1
```

Hypothesis: a small explicit pointer-free text schema can preserve exact source/payload bytes, numeric values, diagnostic spans, and local dependency stamps independently of producer storage; bounded validation can reject malformed artifacts before publishing any records.
The discriminating checks release and poison producer storage before decoding, poison/free encoded input before comparing independently rebuilt fixtures, compare all active records including floating-point bits, reject every proper prefix of the numeric fixture, and independently decode the saved evidence with PowerShell.
This tests a concrete initial representation, not a generic serialised or a complete persisted AST/query engine.

The SDK API probe confirms that `Text_File_Handler.start_from_memory` borrows its input and that `deinit` does not free that borrowed buffer.
The handler supplies version and line processing; the application must implement its own row grammar, escaping, type conversion, limits, and reference validation.
Its defaults trim whitespace and strip comments; the prototype disables inline comment stripping and encodes every payload byte as hexadecimal, so literal spaces, `#`, brackets, CR/LF, tabs, NUL, and UTF-8 cannot be interpreted as row syntax.
Blank lines and whole-line comments are still skipped by the handler: accepted input is not restricted to a single canonical byte sequence.
An explicit header preflight rejects trailing text after `[version]`, which the handler's own version parser does not reject.

The version-1 wire schema is:

```text
[1]
artifact IDENTITY WORLD
source BYTE_COUNT HEX_BYTES_OR_DASH
node ID KIND PARENT BEGIN END BYTE_COUNT HEX_BYTES_OR_DASH
query ID NODE STATUS REVISION SIGNED_BITS UNSIGNED_BITS FLOAT_BITS BYTE_COUNT HEX_BYTES_OR_DASH
diagnostic ID NODE SEVERITY BEGIN END BYTE_COUNT HEX_BYTES_OR_DASH
dependency PARENT_QUERY TARGET_QUERY ARTIFACT CHECKED_PARENT_REVISION OBSERVED_TARGET_REVISION
end NODE_COUNT QUERY_COUNT DIAGNOSTIC_COUNT DEPENDENCY_COUNT
```

Identities, revisions, and numeric bit patterns use exactly 16 uppercase hexadecimal digits; other numeric fields are bounded nonnegative decimal tokens.
Strings are length-prefixed byte sequences with two uppercase hexadecimal digits per byte; empty strings use `0 -`.
Nodes/queries/diagnostics have contiguous one-based IDs; a node's parent is zero or an earlier node, and spans are half-open source-byte offsets.
Dependencies are explicitly local to the current artifact, with valid query references and exact checked-parent/observed-target revision matches.
The reader rejects a foreign artifact identity rather than pretending to resolve cross-artifact dependencies.
No pointer, allocator, pool, `Type_Info`, or native struct layout is serialised.

| Fixture | Artifact Bytes | Source Bytes | Records Per Category | Exact Record Comparisons |
| --- | ---: | ---: | ---: | ---: |
| Empty | 70 | 0 | 0 | 1 |
| Strings | 5,783 | 112 | 8 | 33 |
| Numbers | 2,872 | 140 | 10 | 41 |
| Recovery | 1,057 | 16 | 3 | 13 |
| Limits | 52,986 | 236 | 16 | 65 |

All five fixtures pass 153 grouped record comparisons, plus byte-identical re-encoding against the saved artifact after the independent oracle has also been torn down.
The string matrix includes empty and whitespace-sensitive strings, comment/header-like text, quotes/backslashes, embedded control bytes, UTF-8 for accented/CJK/supplementary characters, all 256 byte values, and 512-byte payloads.
Numeric records preserve signed 64-bit minimum/maximum, unsigned maximum/high-bit values, integers beyond exact double precision, positive/negative zero, ordinary values, a subnormal, maximum finite double, both infinities, and quiet/signalling NaN bit patterns with payloads.
The five query states and incomplete-source recovery records are authored representative records, not outputs of a semantic evaluator or a full syntax reconstruction.

The 41 invalid fixtures cover malformed/unsupported headers, missing termination, unknown/duplicate rows, extra fields/trailing rows, bad terminal counts, invalid numeric/hex/blob fields, invalid enum tags/severity, IDs/parents/references/spans, zero identity/world/revision, foreign dependencies, and stale parent/target stamps.
Resource checks reject strings over 512 bytes, more than 16 records in each of the four categories, files over 65,536 bytes, lines over 2,048 bytes including LF, and more than 80 lines.
The maximum-record/payload fixture succeeds; these limits are prototype constants, not proposed production defaults.
All 2,872 proper byte prefixes of the numeric artifact are rejected in memory, including cuts inside headers, rows, numbers, and encoded strings.
Every failure leaves the destination unpublished/zeroed; decoding uses a caller-owned pool which is reset after rejected inputs and released after successful lifetimes.
This is transactional publication, not allocator rollback: allocations made before a rejection remain in that pool until the caller resets/releases it.
Saved malformed fixtures and trace files retain final newlines; truncated buffers are not saved as separate newline-less files.

Timing compares decode plus fresh pool setup/release against `parse_file` plus `release_parser_tree` with trivia enabled on exactly the artifact's referenced source bytes.
Input artifacts/source are already in memory; encoding, file I/O, hashing, producer construction, deep comparisons, and independent auditing are outside the timed region.
Each fixture/mode has a 16-operation warmup and 21 measured batches of 64 operations, with decode/parse order alternating per batch; ordinary completion assertions remain enabled.
The p95 is the nearest-rank p95 of batch-average operation times, not individual request tail latency.

| Fixture | Decode Median (us) | Decode p95 Batch (us) | Fresh Parse Median (us) | Fresh Parse p95 Batch (us) |
| --- | ---: | ---: | ---: | ---: |
| Strings | 17.203 | 19.791 | 17.886 | 21.059 |
| Numbers | 11.931 | 17.923 | 17.673 | 26.539 |
| Limits | 125.608 | 170.105 | 25.128 | 38.492 |

These are one local optimised timing round, not equivalent-work speed ratios: decoding restores synthetic node/query/diagnostic/dependency records and deliberately large payloads, whereas parsing constructs a real syntax tree without those semantic records.
The limits artifact is about 224.5 times its tiny source size; its slower decode demonstrates payload/hex-volume cost, not a representative cache regression.
Neither the small-fixture decode wins nor that large-fixture loss decides whether real syntax persistence is worthwhile.
E12 below captures real-source inventories with I/O/validation costs and a separate owned graph-text decoder comparison; the latter is a same-layout read-only experiment, not a production syntax codec.

Saved evidence is under `examples/.build/text_artifacts/`: the five artifacts, invalid artifacts, truncation source, parser-source files, `rejections.tsv`, `truncations.tsv`, `timings.tsv`, `timing_summary.tsv`, `compiler_version.txt`, and `audit_summary.json`.
The independent ignored `audit.ps1` implements a separate wire reader, reconstructs fixture source/payload bytes and numeric bit patterns, reclassifies all 41 invalid inputs and all 2,872 prefixes, checks IDs/counts/spans/revisions, verifies all 126 raw timing samples and rotating order, recomputes the six median/p95 pairs, and checks compiler identity and final newlines.
Both compiler backends and the independent audit pass.

The timing table and saved optimised evidence above are from the original QPC-based runner.
As with E9, the current runner now uses `Basic.current_time_monotonic()` and checked elapsed-nanosecond conversion, with a fixed 1,000,000,000 frequency in the existing tick/frequency columns; portable-clock smoke output is separate from the recorded evidence.

Architectural consequence: keep the initial persisted representation explicit, versioned, bounded, and pointer-free; use owned decoded bytes and publish only after whole-artifact validation.
`Text_File_Handler` is a usable line/version layer but supplies neither escaping nor a trust boundary by itself.
Exact bit encodings avoid accidental precision loss or NaN/negative-zero normalisation, at substantial text size and decoding cost; measure a real record projection before selecting production encodings or binary alternatives.

Limits: fixed-capacity synthetic records, one artifact, local dependencies, in-memory decode, and whole-artifact loading only.
There is no complete AST reconstruction, cross-artifact/world-key validation, compiler/schema migration compatibility, checksum/authentication, allocation-failure/denial-of-service fuzzing, allocator-leak accounting, partial loading, concurrency, crash-safe publication, store restart, or OS-cold read measurement.
The convenience disk reads used for evidence are not an untrusted bounded disk-loader API: production loading must impose its byte bound before reading/allocating the file.
No production persistence API or migration plan was added.
E11 tests store/restart below; E12's bounded baseline follows it.
The explicit `using,map` wrapper probe remains unrun.

#### E11 Results: Store Publication, Restart, and Overlay Recovery

Completed 2026-10-19 on Windows 10.0.26200/ReFS with PowerShell 7.6.6 and .NET 10.0.12.
Reproducible runner: [experiment_store_restart.ps1](examples/experiment_store_restart.ps1).
From the parser's examples directory:

```bash
pwsh -NoProfile -File experiment_store_restart.ps1
pwsh -NoProfile -File experiment_store_restart.ps1 -Mode Audit -StoreRoot .build/store_restart/ebb502e0dc82477ebb24d7455a000a32
```

The second command audits the recorded run; use the run directory printed by the first command to audit a new run.
Each run creates a new isolated GUID directory under `examples/.build/store_restart/`; it does not modify workspace source files or an existing user cache.
This is a standalone PowerShell/.NET filesystem and source-selection model, not a production Jai persistence implementation or an end-to-end extension of E10's `Text_File_Handler` schema.
Separate worker processes provide actual restart boundaries, forced termination, and competing filesystem access without requiring compiler execution or executing cached source.

Hypothesis: immutable content-addressed blobs, complete validation before use, a cooperative store lock, and atomic manifest replacement can preserve a complete selected state under interrupted/competing publication, while authoritative source bytes and an explicit host recovery handshake prevent stale overlays from becoming active.
The discriminating checks kill publishers at five named write/publication boundaries, reload from fresh processes, preserve source length and timestamp while changing its bytes, deny actual writes to the cache directory, and compare cache-backed selection with fresh authored source/projection oracles.

The prototype stores exact UTF-8 source as Base64 in JSON, a SHA-256 source digest, a fixed context/schema, and a small byte/line-count projection.
The blob filename is the SHA-256 digest of its exact JSON bytes; reads validate that digest, the source digest, context/schema, and projection.
The manifest is a size-bounded JSON envelope containing a checksum of its encoded JSON body; the body has schema/context/session, monotonically advanced generation, and separate `disk` and `recovery` blob keys.
Keys are validated as uppercase 64-digit SHA-256 names before forming blob paths, and actual manifest/blob sizes are checked on an open stream before allocation: 8,192 bytes for manifests and 16,384 for blobs, with 512-byte authored source bounds.
This checks corruption, not authenticity against an attacker able to rewrite hashes and payloads together; the projection is not an AST or semantic query result.

All writers and GC acquire the same exclusive `FileStream` lock (`FileShare.None`).
A publisher writes a uniquely named same-directory temporary file, flushes file data with `Flush(true)`, closes it, and publishes it with overwrite-enabled `File.Move`; the blob is installed before its reference is committed in the manifest.
An existing digest-named blob must validate before it is reused; an identical publication reuses that blob rather than mutating it.
Readers load the manifest without the writer lock and validate whichever complete blob it selects; their read handles permit deletion, so replacement can proceed.
The tested contention policy is fail-open rather than blocking/retrying indefinitely: the losing publisher keeps correct in-memory source, reports `LOCK_BUSY`, and retries explicitly after the first publisher releases the lock.
Publication rereads the manifest under that lock, so updating one slot does not overwrite a concurrent publisher's already committed other-slot update.

| Check | Observed Result |
| --- | --- |
| Kill during partial blob write | Restart selects the old manifest/blob; staging is never selected. |
| Kill after blob publication, before manifest write | Old selection survives; the unreferenced new blob can be collected. |
| Kill during partial manifest write | Restart selects the complete old manifest, not the temporary prefix. |
| Kill after manifest flush/close, before replacement | Restart still selects the old manifest. |
| Kill after manifest replacement | Restart selects the complete new manifest/blob. |
| Competing publishers | The second process fails open on the held lock, then retries successfully; both intended slot updates survive. |
| Identical content publication | Both slots can name the same immutable blob without creating a duplicate. |
| Corrupt blob/manifest or mismatched context | A fresh reader selects fresh authoritative source and records a cache diagnostic. |
| Write-denied cache directory | Editing and saving source still work; the old manifest remains intact and write/metadata diagnostics are recorded. |
| Reachability GC | Current roots and an explicit old-world lease survive; discarded and unleased historical blobs are removed, and crashed temporary files are cleaned. |

All five interruption cases use real killed child processes, not only simulated branches.
A fresh independent reader process validates selected state after each kill; collection then removes abandoned staging without changing that selection.
The competing-writer check holds the first process inside the lock while another process attempts publication, then releases the winner and retries the loser.
The parent performs 911 successful checks; the 32 worker processes comprise eight publisher processes (five killed) and 24 separate inspection/source-selection readers.
Checks performed inside worker processes are not included in the parent's 911 count.

Startup reads only the manifest; the first source request lazily decodes its selected blob.
The lifecycle starts with disk text, persists an edited recovery revision, and verifies three separate restart choices: disk wins without host restoration, exact host-confirmed recovery can hit its artifact, and different host-restored bytes win but require fresh computation.
Saving writes the source independently of the cache, advances the disk reference, clears the recovery reference, and leaves no active overlay.
After another edit, an external same-size disk rewrite preserves its old modification time: the active overlay still wins until reset, after which the actual current disk bytes are hashed and selected rather than the cached saved revision.
Discard/reset removes the persisted recovery reference; a later restart does not revive it.
Deleting disk does not erase an active overlay; after explicit discard and deletion metadata, restart reports missing source.
A returning path with the old timestamp, but different bytes is treated as a fresh revision, not proof of historical cache validity.
Persistence-disabled sessions preserve in-memory overlay behaviour without reading blobs or writing recovery references.

Twelve corruption cases cover modified/truncated/oversized/missing blobs, an invalid inner source digest, foreign artifact context, a bad manifest checksum, truncated/oversized manifests, unsupported manifest schema, foreign state context, and an unsafe referenced key.
All reload as fresh source with explicit invalid-manifest/blob diagnostics rather than publishing cached data.
GC refuses to guess roots from corrupt manifests and leaves the existing blobs untouched.
The write-denial test installs a deny-write ACL on the isolated cache directory while keeping the source file outside that directory; it verifies actual failed persistence, continued overlay selection and disk save, and unchanged manifest contents.
The original ACL is restored in `finally`, and later publication succeeds again.
A separate cache path occupied by a regular file also degrades to in-memory operation with a directory-creation diagnostic.
No elevated shell command or modification of permissions outside the generated test directory is required.

GC is explicit reachability collection under the publication lock, with current disk/recovery roots plus an authored lease set.
A first collection keeps the old leased revision and removes discarded recovery; after lease release, a second collection removes the old revision while retaining current content.
Four negative controls discriminate automatic recovery activation, timestamp-only validation, omitted lease roots, and reuse of discarded recovery metadata.
The omitted-lease control actually runs GC without the held lease and observes the erroneous deletion; the selection controls compare observed lifecycle values under the deliberately wrong selection rule.

Saved evidence in the recorded GUID directory includes `initial_probe.json`, `process_probes.json`, `lifecycle.json`, `corruption.json`, `unwritable.json`, `negative_controls.json`, `summary.json`, and `audit_summary.json`, plus the actual isolated stores and source files.
The separate-process `-Mode Audit` path recomputes hashes from saved manifest bodies, selected blobs, and source bytes without calling the prototype's cache readers.
It checks exact old/new publication expectations, contention/retry/deduplication generations, lazy and host-authoritative selection, timestamp/size controls, GC root/lease results, all twelve fallback results, permission-failure diagnostics, and four broken-policy mismatches.
The recorded independent audit passes 172 checks and verifies final newlines in 102 evidence files plus the harness; the audit report itself is also newline-terminated.
The harness has no editor diagnostics, and its execution and saved-evidence audit both succeed.

Architectural consequence: publish blobs before references, validate exact bytes on rehydration, serialise mutable manifest updates, and define an explicit retry/fail-open policy for store contention or failure.
Keep recovery candidates distinct from active editor overlays, take restored contents from the host, and treat reset/save/deletion as metadata events rather than inference from the newest blob.
Cache failures need surfaced system diagnostics without disabling correct source operations; inability to persist cleanup must not silently imply that recovery metadata was removed.
Coordinate GC with publishers and lease roots; safe publication alone does not establish safe historical deletion.

Limits: one authored document/context/session, small JSON source/projection artifacts, cooperative processes, a local ReFS filesystem, and deterministic interruption boundaries.
This is not a Jai serialised integration, full parser/semantic cache, cache-directory/privacy default, cross-workspace identity policy, multiprocess lease registry, automatic corruption repair, byte-budget/retention implementation, or production host/editor API.
Leases are supplied explicitly to this model's GC; a production shared store still needs a complete protocol for discovering/protecting leases held by other processes.
The .NET/Linux permission branch exists but was not run; no NTFS, remote filesystem, platform-independent atomic-rename guarantee, malicious-writer defence, concurrent in-place external source mutation, or all possible timing interleavings were established.
File flush and process-kill tests do not establish power-loss durability or directory-entry durability; first-ever publication without a prior manifest and disk-full/allocator-failure behaviour remain untested.
The harness probes nonempty authored disk sources; E10's empty fixture does not establish an empty-source store workflow here.
Private-storage permissions, crash durability, richer identity/version keys, repair policy, budgets, and process-wide lease tracking still require approved production contracts.
No production persistence API or migration plan was added.
E12's bounded baseline follows; the explicit `using,map` wrapper probe remains unrun.

#### E12 Results: Real-Source Baseline and Source-Reload Control

Bounded baseline captured 2026-10-19 on Windows 10.0.26200/ReFS, Jai beta 0.2.030 (2 July 2026), PowerShell 7.6.6, and .NET 10.0.12.
Runners: [experiment_project_baseline.jai](examples/experiment_project_baseline.jai) and [experiment_project_baseline.ps1](examples/experiment_project_baseline.ps1).
From the parser's examples directory:

```bash
jai experiment_project_baseline.jai -o -llvm -quiet -no_color -output_path .build -exe experiment_project_baseline_llvm
pwsh -NoProfile -File experiment_project_baseline.ps1
pwsh -NoProfile -File experiment_project_baseline.ps1 -Mode Audit -RunDirectory .build/project_baseline/40141fe0d05141dd9709bca383c951ab
```

Each measurement run creates its own GUID directory; the audit command above reads the recorded run, not a later timing round.
Inputs are read-only real source inventories: all 56 top-level tutorials (a heterogeneous corpus, not a linked project), eight recursively inventoried Invaders files, four top-level parser implementation files, and 18 top-level Basic files.
A three-file authored `E12_Root -> E12_Middle -> E12_Leaf` import chain supplies explicit transitive syntax inputs; its module directory and complete file list are saved, but no import resolver or typechecker is run.
Inventories do not imply a complete real application's imported SDK closure or configured module-instance graph.
The largest file is first in each manifest and supplies the active-file edits and retained-snapshot profile.
Bounds are 64 files, 512 KiB per source, 2 MiB per inventory, serial workers, and a two-minute timeout per worker.

Hypothesis: retaining complete owned file snapshots avoids parsing on validated unchanged requests, whereas persisting source text alone adds I/O/decoding without eliminating real parse work.
The discriminating checks compare three modes against the same disk source and resident control snapshots, require exact bytes as well as an FNV-1a digest, and deep-compare independently owned parses using the existing snapshot oracle.
The tutorial corpus exposed a missing oracle registry entry for `DIRECTIVE_THIS`: the parser allocates it as a base `Parser_Node`, not a generated concrete node.
The oracle now compares that actual base layout and still rejects unsupported kinds.
Its existing mutation/alias negative controls and bounded three-file lifecycle verification also pass.

`FRESH` reads, hashes, copies, parses, and releases every file.
`RESIDENT` still reads and hashes every disk file and checks exact bytes before selecting its existing snapshot.
`TEXT_SOURCE_REPARSE` additionally reads a versioned text envelope, decodes exact source bytes, validates length/FNV and equality with current disk bytes, then performs the same real parse and teardown as `FRESH`.
This envelope contains uppercase hexadecimal source bytes, not serialised syntax nodes, bindings, or semantic queries.
**It is a source-reparse control, not a persisted-AST decoder.**
FNV is noncryptographic and is never sufficient for reuse by itself; the independent provenance records SHA-256 hashes for each input and the measured worker/source.
The authored codec is not E10's schema or a hardened untrusted cache reader: convenience disk reads check source size after allocation, and correctness assertions stop the worker rather than exercising production fallback.

Portable `Basic.current_time_monotonic()` timestamps are subtracted before checked nanosecond conversion.
Every mode has two warmups and 21 individual measured project requests, with rotating mode order; the p95 is nearest-rank sample 20 of 21, not a batch-average percentile.
Overall latency includes disk reads, digest/exact-byte validation, decoding where applicable, source copies/parsing, and teardown.
Separate read/hash/decode/parse/cleanup nanoseconds and actual requested byte counts are saved.
Deep graph comparisons, artifact construction, memory instrumentation, and edit-source construction are outside request timings.
Resident control snapshots remain live in every timed mode; `FRESH` is a warm in-process baseline, not an empty-process or OS-cold parse.
These are one local optimised LLVM timing round, not confidence intervals, hard latency bounds, or approved acceptance thresholds.

| Inventory | Files | Source Bytes | Fresh Median / p95 (ms) | Resident Median / p95 (ms) | Source-Reparse Median / p95 (ms) |
| --- | ---: | ---: | ---: | ---: | ---: |
| Tutorials | 56 | 687,364 | 18.364 / 19.721 | 2.004 / 2.789 | 24.629 / 28.005 |
| Invaders | 8 | 75,331 | 4.151 / 5.479 | 0.280 / 0.597 | 5.077 / 6.222 |
| Parser | 4 | 337,373 | 18.606 / 20.119 | 0.681 / 0.766 | 20.931 / 24.222 |
| Basic | 18 | 348,676 | 16.524 / 18.436 | 0.887 / 1.211 | 18.981 / 22.274 |
| Authored Chain | 3 | 1,163 | 0.194 / 0.398 | 0.047 / 0.082 | 0.244 / 0.422 |

Resident median savings are about 9-27 times on the four real inventories; their source-reparse controls are about 1.12-1.34 times slower than fresh parsing.
This supports validated whole-file retention, but does not quantify an equivalent AST reload's benefit or justify syntax chunking.
Each unchanged request reads the listed source bytes; the text control additionally reads all artifact bytes below.
Per-source headers and hex expansion make the complete text envelopes about 2.02 times source size.
The initial resident build and artifact encode/write costs are separate, single setup observations, not repeated latency statistics; writes use ordinary file APIs without a durability claim.

| Inventory | Text Bytes | Initial Read/Parse (ms) | Encode/Write (ms) | Resident Backing Bytes | With Two Extra Active Snapshots |
| --- | ---: | ---: | ---: | ---: | ---: |
| Tutorials | 1,387,298 | 20.465 | 19.456 | 24,865,791 | 25,772,119 |
| Invaders | 152,099 | 3.687 | 3.441 | 6,634,216 | 12,344,378 |
| Parser | 680,148 | 17.852 | 2.781 | 34,628,496 | 79,286,796 |
| Basic | 703,385 | 15.273 | 7.295 | 24,901,833 | 30,829,929 |
| Authored Chain | 2,437 | 0.335 | 0.827 | 525,825 | 1,050,535 |

The untimed memory pass tracks upstream requested backing for a separately allocated source/tree/token/name world, then two independently owned copies of its largest file; both copies are deep-checked and all tracked allocations return to zero.
The table's retained copies contain identical source, not distinct semantic worlds.
The edit pass below retains differing file revisions instead.
This is not RSS, physical allocator overhead, the whole process, or a residency budget: control worlds, tracker bookkeeping, and unrelated storage are excluded.
Saved peak/request counters also include deep-oracle scratch inside the tracked phase, so they are not pure snapshot-only high-water figures.
For the parser inventory, retaining two large copies increases backing from about 33.0 to 75.6 MiB; snapshot retention therefore needs an explicit policy despite cheap unchanged requests.

Six active-file variants append a body returning 1, body returning 2, changed return interface, struct layout, malformed body, and repaired body to the original largest source.
Each of 21 measured sequences follows one warmup sequence, reparses the entire active overlay, rotates two independently owned historical snapshots, and releases the overwritten oldest slot inside the timed update.
Every current version and both retained versions are compared with independent fresh syntax graphs; the malformed version must have diagnostics.
These are syntax-only in-memory edits: no editor dispatch, disk save, project update, semantic dependency fan-out, or type/layout-query recomputation is included.
Body/interface/layout labels describe authored source changes, not proved selective invalidation.
The 197,201-byte parser file's six median/p95 update times are respectively 8.895/11.758, 9.132/10.719, 11.602/14.568, 11.257/14.416, 11.671/13.981, and 11.155/15.389 ms.
The first two updates have not yet evicted an old slot; later updates include that cleanup, so their difference is not evidence of semantic interface cost.
Other inventories' per-kind medians/p95 and all 630 measured edit rows are saved rather than pooled across unlike files.

Three fresh-process reload workers per inventory perform no resident-tree warmup.
Their source-read/decode/validate/reparse totals match the project token/diagnostic and I/O totals.
For the parser inventory, worker-only times are 22.960-25.382 ms and parent-observed process wall times are 59.411-59.675 ms; tutorials are 27.744-29.533 ms worker-only and 63.285-70.945 ms wall time.
Wall time includes startup, runtime setup, output draining, and exit; three samples are reported as observations, not a meaningful tail percentile.
Filesystem caches were not flushed, and earlier artifact generation warmed them.
This is process restart, not OS-cold storage latency; no fresh-process fresh-parse competitor was measured.

The recorded run contains 89 source files, 979 deep snapshot comparisons, 315 timed project requests, 630 timed edits, and 15 fresh restart processes.
The independent PowerShell audit reimplements the envelope reader and FNV arithmetic, checks exact source bytes and SHA-256 provenance, rotating order, all row counts, parse/hit/diagnostic/token consistency, phase accounting, bytes read/written, retained counts, malformed diagnostics, zero tracked teardown, and final newlines.
It recomputes the 15 project and 30 edit median/p95 pairs from raw TSVs and separates worker clocks from parent wall clocks.
The measurement-plus-audit invocation passes 3,329 checks, including runner setup/process checks; the subsequent standalone saved-data audit passes 3,211 checks, including its prior newline-terminated report.
Evidence was recorded under `examples/.build/project_baseline/40141fe0d05141dd9709bca383c951ab/`: manifests, input paths/sizes/hashes, exact text artifacts, timing/edit/memory/setup TSVs, process outputs, runtime/worker provenance, and `audit_summary.json`.
On 2026-10-20, build cleanup had removed those raw files; the table and audit counts above are historical results, not a claim that the original audit command remains runnable.
The fresh-process follow-up below regenerates isolated manifests and graph artifacts under new identities.
Fast x64 probe validation, optimised LLVM workloads, shared oracle controls, and saved-evidence auditing pass; no production cache API or migration was added.

Architectural consequence: use validated resident whole-file snapshots and full changed-file reparsing as the initial comparison baseline; budget retained revisions explicitly.
Source-only text persistence does not earn a speed benefit in these workloads.
This source-only control does not establish the cost of real syntax persistence; the separate equivalent-work graph-text comparison follows below.
E10's synthetic records and this source envelope cannot substitute for that measurement.
Before selecting persistence or finer cache granularity, approve end-to-end median/tail/memory/disk targets and evaluate equivalent owned AST reload under the required process/storage conditions.
The bounded baseline is complete, but E12's full persistence/acceptance decision remains open, along with semantic transitive-dependency updates, real configured import closures, complete section 13 editor workflows, OS-cold reads, concurrency, and cross-platform measurements.
No numerical acceptance threshold is implied by the observed milliseconds or speed ratios; approval remains a specification gate, not an automatic benchmark outcome.

##### E12 Follow-up: Equivalent Owned Graph Text Reload

Captured 2026-10-19 on the same Windows/ReFS toolchain, using [experiment_snapshot_codec.jai](examples/experiment_snapshot_codec.jai) and [experiment_snapshot_codec.ps1](examples/experiment_snapshot_codec.ps1).
This experiment reconstructs real parser-owned syntax graphs without reparsing source.
It does not change production parser, resolver, or cache APIs.
The original source-reparse evidence above is preserved; the follow-up is a separate timing round and must be compared against its own fresh-parse competitor, not the earlier round's milliseconds.

```bash
jai experiment_snapshot_codec.jai -o -llvm -quiet -no_color -output_path .build -exe experiment_snapshot_codec_llvm
pwsh -NoProfile -File experiment_snapshot_codec.ps1
pwsh -NoProfile -File experiment_snapshot_codec.ps1 -Mode Check -RunDirectory .build/snapshot_codec/889f05af33c94f9480a9d0b03445f2fb
pwsh -NoProfile -File experiment_snapshot_codec.ps1 -Mode Audit -RunDirectory .build/snapshot_codec/889f05af33c94f9480a9d0b03445f2fb
```

The runner consumes the original five manifests and verifies their saved source SHA-256 digests before measurement; no application code or compiler evaluation is executed.
Its version-14 text format has explicit scalar/string/array/reference/layout records, contiguous object IDs, a layout fingerprint, and body length/FNV checks.
Graph IDs reconstruct cycles, scope parents, declaration references, and owned-object aliases without persisted process addresses.
Token/literal unions have explicit active-payload handling, including exact numeric bits and constant pointer literals; runtime/compiler pointers and unsupported unions are rejected.
The logical roots include source/path, retained and synthetic tokens, diagnostics/related information, recovery/restart records, status, nodes, and lexical scopes.
Allocator state, producer-private intern tables, and resizable-array spare capacity are not persisted.
Every decoded payload and graph object belongs to a new stable pool; these are read-only snapshots, not validated inputs to mutable resolver/incremental-parser operations.

The reader is an experiment-only same-layout, little-endian 64-bit implementation, driven by current reflection metadata and explicit tagged cases.
Its fingerprint catches the recorded layout differences; it is not a complete compiler/schema migration contract or a stable independent production schema.
Bounds include 64 MiB artifact bytes, 262,144 object IDs, 1,048,576 elements per array, 256 MiB explicitly reconstructed payload, and recursion depth 512.
Pool/table bookkeeping is outside that payload counter; these are not whole-process resource limits.
Convenience disk reads still impose size checks after reading, and FNV is not cryptographic authentication.
Malformed artifacts abort a bounded worker through assertions; there is no transactional fail-open reader, exhaustive enum/span/graph-consistency validation, allocator-failure recovery, malicious-input safety claim, or production publication/store integration.

Seven authored fixtures cover empty input, cyclic bindings/scopes, arrays and strings, struct literals, `#this`, null and numeric payloads, procedures, and malformed/recovery graphs.
Their 21 deep lifetime comparisons destroy/poison the producer, poison/free artifact bytes, independently decode two siblings, and destroy/poison one sibling before comparing the other with fresh syntax.
Every one of the 89 real-source artifacts is also decoded after producer teardown and deep-compared with a separate fresh parse after input poisoning.
These are 110 deep comparisons across authored and real-source checks, not full Jai feature or compiler-semantic coverage.

`FRESH`, `RESIDENT`, and `AST_RELOAD` use the same actual disk-source read, FNV/exact-byte validation, filename context, and live resident control trees.
Reload additionally reads and validates the complete artifact and reconstructs its graph; it performs zero source parses.
Fresh parsing and reload both release their temporary owned snapshots inside request latency.
There are two warmups and 21 rotating requests per mode/inventory, for 315 measured requests; read/hash/decode/parse/cleanup clocks and source/artifact byte counts are saved.
Deep comparisons, encoding/writing, memory instrumentation, and rejection checks are outside timing.
Apollo elapsed-nanosecond clocks and nearest-rank p95 are unchanged from the baseline.

| Inventory | Fresh Median / p95 (ms) | Resident Median / p95 (ms) | AST Reload Median / p95 (ms) | AST Text Bytes |
| --- | ---: | ---: | ---: | ---: |
| Tutorials | 25.059 / 28.953 | 2.984 / 3.894 | 111.255 / 145.359 | 14,826,050 |
| Invaders | 4.209 / 5.070 | 0.256 / 0.355 | 21.926 / 25.803 | 3,911,306 |
| Parser | 26.851 / 31.458 | 0.819 / 1.547 | 140.801 / 207.535 | 21,170,113 |
| Basic | 14.123 / 15.017 | 0.789 / 1.081 | 82.271 / 85.221 | 16,079,410 |
| Authored Chain | 0.139 / 0.211 | 0.033 / 0.045 | 0.607 / 0.721 | 108,262 |

This graph-text representation reloads about 4.4-5.8 times slower than fresh parsing on the four real inventories, with artifacts about 21.6-62.7 times their source size.
It preserves repeated source/token/trivia/name text rather than deduplicating strings or using source spans, and uses per-scalar text records and reflective dispatch; the result does not establish the performance of a compact field schema, binary format, or optimised decoder.
Single setup encode/write observations are approximately 288/47/285/182/2 ms in table order, not repeated request statistics or durable publication costs.

Separate untimed fresh/decoded backing profiles hold the whole inventory, then two extra largest-file copies, then release everything.
They track upstream requested bytes, including snapshot pools and decoder object-table capacity, but exclude disk/artifact input buffers, tracker bookkeeping, deep-oracle scratch, allocator-private overhead, and OS residency.
All ten fresh/decoded profiles return tracked bytes and outstanding allocation records to zero.

| Inventory | Fresh Backing Bytes | Decoded Backing Bytes | Fresh With Two Extras | Decoded With Two Extras |
| --- | ---: | ---: | ---: | ---: |
| Tutorials | 24,864,447 | 13,851,194 | 25,770,727 | 14,469,486 |
| Invaders | 6,634,024 | 3,480,299 | 12,344,138 | 6,147,235 |
| Parser | 34,628,400 | 17,809,332 | 79,286,652 | 38,220,834 |
| Basic | 24,901,401 | 13,824,095 | 30,829,449 | 16,936,889 |
| Authored Chain | 525,753 | 242,831 | 1,050,415 | 463,853 |

Lower decoded backing is evidence about this read-only materialisation, which omits producer-private intern tables and spare capacity; it is not proof of a better allocator or equal mutation/query capability.
No full-project semantic state, eviction budget, distinct semantic old worlds, or peak whole-process working set is included.

The valid artifact child-process control passes a deep fresh comparison.
Eleven corrupted variants assert-reject version/schema changes, checksum mismatch, truncation, trailing records, wrong root tag, oversized arrays, invalid object/layout IDs, and source/filename context mismatches.
Inner mutations have recomputed body digests, so the checks discriminate structural/context guards rather than only checksum rejection.
Failed workers must report the decode-probe marker and an assertion, exit nonzero, and never report success.
The `Check` path passes 57 checks and saves raw rejected artifacts and process diagnostics; it verifies assertion-based rejection, not safe production fallback or exhaustive fuzzing.

The independent PowerShell audit reimplements FNV/body framing, exact source/path reconstruction, scalar/string hex framing, contiguous/nonforward object IDs and layout placement, source SHA-256 provenance, mode order, parse/hit/load and byte totals, phase accounting, and all 15 median/p95 pairs.
It checks saved backing and child rejection evidence without using the Jai codec; it is not an independent complete typed-AST decoder.
The subsequent standalone audit passes 17,151,310 record/evidence assertions; this large number counts per-record assertions, not distinct fixtures or corruption cases.
Evidence was recorded under `examples/.build/snapshot_codec/889f05af33c94f9480a9d0b03445f2fb/`: original-manifest references, graph artifacts, raw/setup/backing TSVs, timing and follow-up worker/source hashes, compiler hash/build flags, process logs, rejection artifacts, and audit JSON.
Build cleanup had removed those raw files by 2026-10-20; retain the figures above as historical observations.
Use the regenerated preparation/startup workflow below rather than assuming those original paths still contain auditable data.
Backing/rejection modes were added and rebuilt after the saved timing round; their separate worker/source hashes are recorded rather than presented as the measured binary.
Both fast x64 authored/probe checks and the optimised LLVM real-source, memory, rejection, and saved-evidence checks pass.

Architectural consequence: the equivalent-work comparison now supports resident whole-file retention and fresh changed-file parsing over adopting this graph-text format for speed.
The backing reduction may inform a future compact read-only snapshot design, but does not offset an unapproved latency/disk budget automatically.
Keep persistence as an architectural capability, not a demonstrated performance win for this representation.
Compact encoding/decoder optimisation is an optional, measured follow-up, not a reason to begin production migration.
At this stage, graph-reload process-restart performance remained open; the next follow-up measures it.
Numerical acceptance-policy approval, OS-cold performance, semantic dependency updates and configured closures, complete editor workflows, concurrency, and cross-platform evidence remain open.

##### E12 Follow-up: Fresh-Process Graph Reload Versus Fresh Parse

Captured 2026-10-20 on Windows 10.0.26200/ReFS, PowerShell 7.6.6, .NET 10.0.12, and the optimised LLVM Jai worker.
Hypothesis: process startup can reduce the relative cost difference seen in the warm in-process comparison, but does not remove this graph-text decoder's reconstruction/I/O overhead.
The discriminating check starts a separate bounded worker for every request, with no resident control trees, and compares actual graph reload against fresh source parsing under the same manifest/source context.
Neither path executes application code or semantic/compiler evaluation.

Cleanup left the earlier evidence directories but removed their files.
A new `Prepare` mode in [experiment_project_baseline.ps1](examples/experiment_project_baseline.ps1) reuses the bounded five-inventory selector to write only fresh manifests, source SHA-256 provenance, and authored import-chain sources; it does not run unrelated baseline/edit timings or require a baseline executable.
The prepared run is `examples/.build/project_baseline/45a228d89d2f47168b0ed303c19c15a6/`.
The graph runner then regenerated artifacts under `examples/.build/snapshot_codec/4bf9ec913623496fa7ad757430dcef18/`, passing the seven authored fixtures, all 89 real-source deep producer/input-teardown comparisons, and 17,151,358 initial run/audit assertions.
Its preparation timings are a separate round, not pooled with startup or substituted for the historical tables above.
The regenerated chain's 108,264-byte artifact total differs slightly because its owned source filenames include the new absolute run path.

From the parser examples directory:

```bash
pwsh -NoProfile -File experiment_project_baseline.ps1 -Mode Prepare
jai experiment_snapshot_codec.jai -o -llvm -quiet -no_color -output_path .build -exe experiment_snapshot_codec_llvm
pwsh -NoProfile -File experiment_snapshot_codec.ps1 -BaselineDirectory .build/project_baseline/45a228d89d2f47168b0ed303c19c15a6
pwsh -NoProfile -File experiment_snapshot_codec.ps1 -Mode Startup -RunDirectory .build/snapshot_codec/4bf9ec913623496fa7ad757430dcef18
pwsh -NoProfile -File experiment_snapshot_codec.ps1 -Mode AuditStartup -RunDirectory .build/snapshot_codec/4bf9ec913623496fa7ad757430dcef18/startup_cdeffa1e9db7429283f46ea9d7aa95c9
```

The literal paths address this recorded run.
For a new run, use the new preparation and graph directories printed by the preceding commands; the original default baseline directory may no longer exist after cleanup.
`Startup` creates an isolated child evidence directory and does not overwrite graph artifacts or earlier timing rows.

Each inventory has one discarded fresh-process warmup per mode and 21 measured fresh processes per mode, with alternating order: 220 total processes, ten warmups, and 210 measured requests.
Workers have the existing two-minute timeout and process-tree cleanup; they run serially.
Each record includes the real PID, a unique invocation ID, exit status, raw worker output, and parent-observed wall nanoseconds.
The worker clock starts before manifest reading and includes manifest/source I/O, source FNV computation, parsing or artifact read/validation/reconstruction, and snapshot/source teardown.
It ends before stdout reporting and deferred manifest cleanup; runtime initialisation and process startup/exit are outside this clock.
The parent `Stopwatch` starts before `Process.Start` and ends after process completion and output draining, so wall time includes startup, runtime initialisation, worker execution, reporting/draining, and exit.
Percentiles are nearest-rank p95 of 21 individual requests per group; worker and wall percentiles are computed independently, not subtracted to claim a startup-overhead percentile.

Fresh parsing reads authoritative source and computes its digest, with no historical source to compare.
AST reload additionally validates schema/body hash, exact decoded source bytes and filename against that disk context, and constructs no fresh parse for timing or verification.
Both modes return matching token/diagnostic totals against the deep-validated preparation world.
The saved parse/load counters are all-files/zero for fresh and zero/all-files for reload.
The independent audit recomputes source digests, source/artifact SHA-256 provenance, manifest bytes and exact path order, artifact I/O totals, record framing, alternating order, invocation identity/status, syntax totals, phase sums, and parent/worker clock containment.
The XOR source digest in worker output is only a compact consistency summary; per-file SHA-256 provenance and exact decoded-source equality remain separate checks, not an authentication or race-free source-selection protocol.

| Inventory | Fresh Worker Median / p95 (ms) | Reload Worker Median / p95 (ms) | Fresh Process Wall Median / p95 (ms) | Reload Process Wall Median / p95 (ms) |
| --- | ---: | ---: | ---: | ---: |
| Tutorials | 21.478 / 26.334 | 107.964 / 125.536 | 59.560 / 72.449 | 145.048 / 167.141 |
| Invaders | 5.228 / 5.798 | 27.269 / 30.349 | 40.563 / 42.713 | 63.354 / 69.184 |
| Parser | 20.250 / 24.544 | 133.164 / 151.995 | 53.367 / 72.903 | 166.709 / 188.215 |
| Basic | 15.618 / 16.677 | 90.434 / 97.745 | 45.472 / 49.101 | 121.282 / 128.032 |
| Authored Chain | 0.456 / 0.528 | 1.082 / 1.495 | 34.320 / 37.235 | 35.148 / 39.931 |

On the four real inventories, graph-reload worker medians are about 5.0-6.6 times fresh parsing and whole-process wall medians about 1.6-3.1 times fresh parsing.
Startup dominates the tiny authored chain's wall time; its close wall medians are not evidence of equal algorithmic cost or a robust performance threshold.
This is one local timing round with ordinary scheduler/antivirus/runtime variability, not confidence intervals, a hard tail bound, or an approved adoption criterion.

Preparation and SHA-256 provenance reads warm the filesystem; no system cache flush, reboot, privileged cache eviction, or isolated cold-storage protocol was performed.
Consequently, every result is explicitly **fresh process, warm/unflushed filesystem**, not OS-cold storage or power-loss restart.
This closes the bounded process-restart comparison, not the cold-storage gate.
The same-layout read-only codec, post-read size checks, assertion-only invalid-input handling, and absence of semantic queries retain their earlier limits.

The startup-plus-audit invocation passes 3,597 checks.
A separate `AuditStartup` process reproduces all 20 worker/wall median/p95 pairs and passes 3,289 checks, excluding measurement setup/process checks and including its prior report's newline.
Evidence is under `examples/.build/snapshot_codec/4bf9ec913623496fa7ad757430dcef18/startup_cdeffa1e9db7429283f46ea9d7aa95c9/`: exact project/artifact provenance, 220 process records, compiler/worker/source/runner hashes and build flags, explicit cache condition, and independently recomputed summary JSON.
The parent graph directory and prepared source manifests are dependencies of re-auditing this run.
These remain ignored build evidence, not durable archives; cleanup may remove them again.
Fast-backend three-file probes, optimised preparation/startup, independent saved-data audit, and source/editor checks pass.

Architectural consequence: process restart does not turn this verbose graph-text format into a speed improvement over fresh parsing.
Keep resident whole-file retention and fresh changed-file parsing as the supported comparison baseline, without inferring that a compact production codec would behave identically.
OS-cold storage requires an explicitly agreed, isolated test procedure; no machine-wide cache state was changed to obtain this result.
Performance-policy approval, semantic dependency/configured-closure and full editor-workflow measurements, concurrency, cross-platform evidence, and production contracts remain open.
No production cache API or migration plan was added.

#### E13 Results: Explicit `using,map` Wrapper

Completed 2026-10-20 on Windows with the same installed Jai beta 0.2.030 compiler and fast x64 backend.
Runner: [experiment_using_map.ps1](examples/experiment_using_map.ps1).
From the examples directory:

```bash
pwsh -NoProfile -File experiment_using_map.ps1
pwsh -NoProfile -File experiment_using_map.ps1 -Mode Audit -RunDirectory .build/using_map/7123e26ddfbd4d16a824c1dfaa907127
```

Hypothesis: for an explicitly supported member set, a generated mutable name array produces the same ordered mapping as real `using,map` when the callback's module context is preserved.
The authored `Pair` has two ordinary members, `left` and `right`; the wrapper constructs its array by iterating `type_info(Pair).members`, rather than supplying literal mapped results.
Both paths call the same callback in an imported module with explicit prefix/request/exclusion/policy parameters and a file-private formatting helper.
Three prefix values, each with and without excluding `right`, give six real-mapping/wrapper pairs and twelve exact expected-result checks.
Real mapping also executes writes through the resulting aliases and checks the original fields sum to 42; excluded members remain accessible through the original object, not through the absent mapped alias.

Results from 18 separate compiler processes:

| Check | Observed result |
| --- | --- |
| Six positive pairs | All agree in cardinality, order, exact mapped bytes, and retained empty exclusion slot.  Changing the module prefix changes both paths equally; the private helper remains available in the preserved module. |
| Excluded alias | Referencing `mapped_right` after excluding `right` rejects with `Undeclared identifier 'mapped_right'`. |
| Missing context | Removing the private helper from the direct wrapper's module rejects with `Undeclared identifier 'decorate'`.  Copying just the callback is insufficient. |
| Duplicate mapping | Real mapping rejects with `Redeclaration of 'same'`.  The explicit wrapper call itself succeeds, but the host rejects its colliding output. |
| Distinct punctuated names | Real mapping accepts `not-0` and `not-1` when no source expression tries to reference them.  Both real and wrapper outputs are rejected by this experiment's deliberately narrower ASCII-identifier policy.  This is a supported-subset restriction, not evidence that the compiler rejects such names or that they are convenient source-level aliases. |
| Publication | Fifteen compilations succeed, three reject as expected.  Three successful but unsupported/colliding outputs are not published; only the twelve positive results are retained.  Frames emitted before a compiler error are never sufficient for success. |

The result channel uses request-specific begin/end records, an exact slot count, zero-based positional rows, byte counts, and decimal UTF-8 bytes rather than raw callback strings as delimiters.
The reader enforces the expected request/count/position, a 256-byte per-name bound, byte values, strict UTF-8, the supported ASCII spelling subset, and nonempty-name uniqueness.
An empty name is retained in its original array slot as an exclusion.
Twelve controls reject stale requests, truncation, missing/duplicate/reordered slots, extra frames, oversized lengths, invalid bytes/UTF-8, an encoded newline, incomplete byte payloads, and duplicate mapped names.
This is authored trusted output, not an authenticated protocol: unrelated non-frame compiler text is ignored and a callback able to forge the current request is not sandboxed by framing.

Results are decoded into host-owned strings only after compiler exit and process disposal.
Replacing the input-text variable and discarding the split rows leaves the decoded values intact; a separate audit process reloads logs and reproduces the results after all evaluator processes have gone.
This establishes host/result ownership across subprocess teardown, not a future Jai arena allocator or shared-process evaluator lifetime contract.

The final Run invocation passes 985 checks; a separate Audit passes 585 checks, including six exact pair comparisons, twelve damaged-frame controls, input/log SHA-256 checks, expected diagnostic/exit checks, and absence of native outputs.
Saved evidence is under `examples/.build/using_map/7123e26ddfbd4d16a824c1dfaa907127/`: generated source/module files, compiler logs, request/case/result/exit records, runner/compiler hashes and build flags, host versions, and the audit summary.
It is ignored, cleanup-removable build evidence, not a durable archive.
Each authored compilation has a 30-second process-tree timeout; the 1 MiB output bound is checked after capture, not a streaming memory limit.
No native program is emitted; compile-time code still executes, and the runner is not permission to evaluate arbitrary workspace source.

Limits: only this two-member struct and static parameter/private-helper context are covered, on one compiler/backend/platform.
General exported-member enumeration, overloads/imports/conditional declarations, full identifier/reserved-name and receiving-scope collision rules, mutable compile-time state, source/caller context, dependency/effect tracking, concurrency, cancellation, hostile output, and sandboxing remain unvalidated or unsupported.
No performance claim, evaluator opt-in default, production API, or migration implementation follows from this experiment.
The bounded wrapper proposal is feasible; a future evaluator must preserve a declared supported context or return unsupported, retain positional exclusions, own its results, and publish only after validated successful completion.

Suggested order is E1-E5 for language/toolchain facts, then E6-E8 for correctness contracts, then E9-E11 for representation/storage, with E12's baseline captured early and comparisons added as prototypes become available; E13 is the bounded mapping-wrapper follow-up.
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
- [x] Draft an evidence-linked initial capability boundary and proposed correctness/performance gates in section 14, keeping all approvals and implementation qualification open.
- [x] Draft core source-event, immutable-world, ownership, ticket/query-outcome contracts and eight acceptance traces in section 14; label them proposed and unimplemented.
- [x] Draft persistence record/validation/publication/recovery/GC contracts and eight store acceptance traces in section 14, preserving source persistence and explicit durability limits.
- [x] Draft semantic identity/revision, observed-dependency, validation and milestone contracts with eight semantic acceptance traces; retain syntax-first deferrals and conservative whole-module invalidation.
- [x] Draft execution, host delivery, cancellation, pressure and shutdown contracts with eight concurrent/interleaving acceptance traces; distinguish terminal request outcomes from stopped workers and retained result ownership.
- [x] Draft finite source-provider capture, unknown/absent membership, explicit dependency discovery and logical multi-document transaction contracts with eight source-capture acceptance traces.
- [x] Draft concrete v1 source/update/query record shapes, tagged event payloads, operation/outcome and handle ownership tables, worked edit protocol and latency-to-trace mapping.
- [x] Perform a bounded interface consistency pass and repair session bootstrap, first-document admission, unchanged-source analysis retry and stopped-session/result ownership gaps.
- [ ] Qualify the bootstrap/retry/shutdown protocol against V5/V6, X7/X8 and T8 in the authorised implementation; document-only operation/reference checks are not behavioural qualification.
- [x] Approve the fifteen-operation interface as the specification baseline on 2026-10-21, subject to exact schemas and API review, without authorising implementation or migration.
- [ ] Complete the interface's exact identity/payload encoding, signatures, bounds and adapter capabilities for API review, then implement its mapped acceptance cases only after implementation authorisation.
	- [x] Draft canonical key framing, namespace/revision authority, revision-bound syntax payload envelopes and local review vectors without choosing store defaults or authorising implementation.
	- [x] Draft the closed syntax-context registry, all five current parser parameters, exact path encodings and session/document binding admission/restart rules; preserve unsupported semantic extensions and pending adapter review.
	- [ ] Review the context registry and adapter descriptor/platform-policy alternatives against real adapters; qualify binding, lease and consistency claims without inferring filesystem guarantees.
	- [x] Draft diagnostic origin/code/severity/recovery observations and syntax-only declaration-index names, containers, coverage and visibility records, preserving unmappable/raw observations and semantic deferrals.
	- [x] Map current token forms, trivia-dependent byte origins, synthetic recovery, compound declared-versus-assigned bindings and scope-directive nodes; explicitly record export-marker, shared-owner and traversal-registry gaps.
	- [ ] Specify exact node/token/diagnostic/index variants, optional tags, access signatures and numeric admission bounds for API review.
	- [x] Record the accepted trivia-required full-featured scope and draft the complete current token-name/alias registry; remove the non-trivia byte-mapping requirement without changing production compatibility mode.
	- [ ] Review and qualify token-tag/alias round trips, field-role restrictions, trivia-enabled origins and rejection of non-trivia full-featured profiles after implementation authorisation.
	- [x] Draft tagged token values, exact integer/float bits, closed value/trivia flags and source-slice ownership, including quoted-note discrimination and uniform EOF preceding-trivia reconstruction.
	- [ ] Qualify active union routes, flag combinations, decoded-value ownership and exact source/trivia reconstruction against fresh lexer output after implementation authorisation.
	- [x] Draft explicit child/helper/backreference roles, candidate per-kind authored fields and index v2 shared-region containers; record the second compound-construction route that prevents a universal shape-only binding predicate.
	- [x] Separate source `#program_export` metadata from module visibility and reserved `#export`; draft ordered occurrences, optional-name presence, final producer observations and partial-correlation rules, and exclude the stored string from child descent.
	- [ ] Review and qualify metadata-interval correlation, repeated/bare/empty program-export observations and source/value ownership against independent expectations after implementation authorisation; establish an actual declaration `#export` producer path or retain the mapping gap.
	- [x] Draft explicit assembly-helper variant guards and child order, including parsed modifiers on unparsed operands, opaque-region coverage, scalar mnemonic sizes and assembly-name index exclusions.
	- [ ] Review and qualify assembly visit paths/order, active versus inactive fields, malformed/opaque regions and same-token identifier occurrences against independent expectations after implementation authorisation.
	- [x] Draft type-instantiation source-form guards and child order, separating varargs/views, constrained polymorphic forms, recovered required children and equal-span expression wrappers without semantic descent.
	- [ ] Review and qualify type-form/route correlation, flag conflicts, dimension/element order, recovered constraints and wrapper IDs against independent fresh-output expectations after implementation authorisation.
	- [x] Draft literal-arm and construction-route guards, covering source null, aggregate type/member order, parser-created using-filter containers, scalar/source distinctions and unsupported alignment routes.
	- [ ] Review and qualify literal active-arm/AST-flag mappings, aggregate/name-list route distinctions, null-pointer handling and owned values against independent fresh-output expectations after implementation authorisation.
	- [x] Draft procedure parameter ownership/using aliases, scalar suffix metadata, header/body backlinks and quick-body normalisation rules; exclude unattached bodies and unsupported header-note routes.
	- [ ] Review and qualify procedure visit order, parameter aliases, unnamed slots/index containers, quick-body origins and suffix value ownership against independent fresh-output expectations after implementation authorisation.
	- [x] Draft struct/enum child ownership, scalar alignment and modifier observations, context-qualified bare enum-member entries and field-default/backreference exclusions.
	- [ ] Review and qualify aggregate/enum-mode routes, enum-member entry origins, conditional branches, modifier observations and default-assignment exclusions against independent fresh-output expectations after implementation authorisation.
	- [x] Draft control-flow form guards and source order, including dynamic for-prefix expressions, default cases, normalised branch blocks, range recovery and loop-name/generated-field exclusions.
	- [ ] Review and qualify control-flow visit order, default versus recovered conditions, branch/block observations, discarded duplicate flags and loop/index exclusions against independent fresh-output expectations after implementation authorisation.
	- [x] Draft call argument/context helper ownership, prefix/postfix/auto cast order, operator recovery and folded/grouped expression observations without semantic-call descent.
	- [ ] Review and qualify call/context visit paths, cast source order, unattached arguments, folded literals and recovered operator/suffix shapes against independent fresh-output expectations after implementation authorisation.
	- [x] Draft directive payload guards and scalar-name exclusions, import-parameter callee backreferences, arrow-run source-header/block aliases and insert modifier-before-payload order.
	- [ ] Review and qualify directive routes/aliases, scalar ownership, insert clause order and partial/discarded payload observations against independent fresh-output expectations after implementation authorisation.
	- [x] Consolidate declaration/compound metadata ownership, filter-before-target using order, direct-base `#this` coverage and a concrete reachable-kind/field/alias review gate.
	- [ ] Review and qualify compound metadata placement, using order/alias contexts, base-node kinds and overwritten/recovered metadata observations against independent expectations after implementation authorisation.
	- [x] Draft snapshot-bound compound route evidence and route-specific binding rules, preserving consumed assignment tokens and explicit unclassified/partial outcomes instead of default-field or span heuristics.
	- [ ] Review the producer route-observation capability versus a version-bound correlation adapter; qualify identifier/expression compound routes, recovery, binding counts and stale/conflicting evidence after implementation authorisation.
	- [x] Draft the syntax-adapter capability matrix and canonical context binding, separating captured/reconstructed/unavailable observations, unsupported payloads and local partial coverage.
	- [ ] Review actual adapter build/registry identities and feature methods; qualify capability admission, adapter-only context changes, local coverage gaps and retained old results after implementation authorisation.
	- [x] Separate exact source name spelling from producer-name values, including backticks, multi-token operators, recovered punctuation and an explicit unmapped/partial name state.
	- [ ] Review and qualify name-token/route correlation, source versus producer bytes, name-specific recovery, anonymous/missing distinctions and interpreted-name ownership after implementation authorisation.
	- [x] Draft closed structured coverage reasons, subjects/field paths/impacts, metadata/name propagation and consumer limits on negative or local-completeness inferences.
	- [ ] Review and qualify coverage aggregation/order, safe partial records, unlocated gaps, invalid-evidence failures and preservation across reuse against independent expectations after implementation authorisation.
	- [x] Define same-list scope-directive provenance with snapshot-local basis IDs, conditional/nested-list boundaries and explicit separation from effective visibility or defaults.
	- [ ] Review and qualify scope-basis ownership/list correlation, branch isolation, no-directive versus unavailable evidence and invalid references against independent expectations after implementation authorisation.
	- [x] Specify declaration-event/binding-group order, dense separate local ID domains, target versus shared-payload containers and safe omission when a required ancestor cannot be represented.
	- [ ] Review and qualify exact entry/region sequences, nested target/payload ownership, partial-container restoration and cross-result renumbering against independent expectations after implementation authorisation.
	- [x] Define published-subtree recovery attribution, explicit unclassified status, ancestor/shared-binding propagation and separation from speculative records or diagnostic overlap.
	- [ ] Review and qualify committed recovery correlation, expected/skipped/inserted events, compound attribution, cursor-restored attempts and absent/conflicting evidence against independent expectations after implementation authorisation.
	- [x] Define kind-specific envelope/result completeness, exact agreement with index coverage and separation from request availability, parse status and world membership.
	- [ ] Review and qualify completeness-arm admission, atomic outer/inner agreement, partial final availability and rejection of truncated snapshot/diagnostic publication after implementation authorisation.
	- [x] Define derived-result protection and borrowed access for referenced syntax backing without requiring a separate snapshot/world lease or permitting cross-envelope numeric ID reuse.
	- [ ] Review accessor signatures/backing schemas and qualify derived-only retention, reference-domain validation and independent copy/remapping after implementation authorisation.
	- [x] Clarify whole-document syntax query scope, absence of hidden service-side filters and caller-selection limits on IDs, coverage and semantic claims.
	- [ ] Review and qualify selection-independent query contents, retained selection references, invalid filter fields and explicit output-pressure outcomes after implementation authorisation.
	- [x] Define result diagnostic status as protected parse status and checked emitted-severity counts, separate from coverage, presentation availability and service/cache faults.
	- [ ] Review and qualify diagnostic-summary agreement across query kinds, duplicate/related record counting and unavailable/conversion evidence after implementation authorisation.
	- [x] Define requested-member syntax/index milestone readiness, valid partial/absent states and separation from per-query packaging, persistence and semantic completion.
	- [ ] Review and qualify aggregate readiness/publication ordering, unsupported admission, required-task failure and independently delayed query packaging after implementation authorisation.
	- [x] Define duplicate-free analysis membership and canonical member-description order while preserving source-event, edit and payload ordering.
	- [ ] Review and qualify document-set permutations, duplicate/foreign identity rejection, alias separation and unchanged ordered source transactions after implementation authorisation.
	- [x] Bind query payload schema selection to the captured context's exact registered tuple, separate interface/payload versions and prohibit silent fallback or retained-world relabelling.
	- [ ] Review supported cross-schema mappings and qualify wrong/unknown tuples, explicit unsupported outcomes, legacy-store misses and retained-schema access after implementation authorisation.
	- [ ] Complete and review the remaining per-variant child guards/order, metadata aliases, declaration-marker mapping and compound-route classification before claiming complete index traversal; assembly's drafted helper rules still need the review and qualification above.
		- [x] Inventory all 50 current generated layout inputs and identify the separate base-node `DIRECTIVE_THIS` route without claiming reachability/field closure.
		- [ ] Enumerate builder function reachability and exact field roles/guards/order for every inventoried layout, base-node kind and auxiliary variant, recording explicit profile exclusions or unresolved mappings.
			- [x] Enumerate Context/Ident/Note/Placeholder leaf fields, scalar guards, parser-only placeholder storage and excluded resolution backlinks; retain exact flag schemas and behavioural review as open.
			- [x] Enumerate unary/binary/cast/expression-query/type-query fields, active child order and published-versus-failed recovery routes; retain exact scalar registries and behavioural review as open.
			- [x] Enumerate procedure-call fields and argument/context helpers, including import-callee backreferences, authored ordering and excluded resolved/generated storage.
			- [x] Enumerate all eight type-instantiation fields and bind child activation/order to the nine source-form guards, excluding inferred result storage and unpublished wrappers.
			- [x] Enumerate literal layout/union and aggregate/null helper fields with active-arm, ownership and unsupported-payload guards.
			- [x] Enumerate declaration/compound/comma-node fields, embedded scope-entry and compound-argument helpers, preserving metadata placement and shared-region ownership.
			- [x] Enumerate block fields, statement-list ownership, structural wrappers and excluded parent/member/owner associations.
			- [x] Enumerate procedure header/body fields with parameter-using aliases, scalar suffix values, optional bodies and excluded compiler provenance/storage.
			- [x] Enumerate struct/enum fields with parameter/body ownership, scalar alignment/markers and excluded resolved types/constants.
			- [x] Enumerate If/Case/While/For/Loop_Control fields with guarded branches/ranges/prefixes, backlinks and generated-state exclusions.
			- [x] Enumerate Return/Defer/Push_Context/Using fields with argument helpers, filter ordering, parameter aliases and valid body-absence guards.
			- [x] Enumerate Add_Context/Context_Type directive fields with declaration-payload ownership and childless context-type syntax.
			- [x] Enumerate Bake/Code directive fields with published-call guards and ordinary/typed/null/caller payload distinctions.
			- [x] Enumerate Bytes directive payload ownership and required-expression recovery without evaluated byte generation.
			- [x] Enumerate Exists query/sync fields with source order and consumed-comma recovery guards.
			- [x] Enumerate Import/Load/Library fields with parameter-call ownership, source scalar observations and external/resolved-data exclusions.
			- [x] Enumerate Overlay/Modify directive fields with target-before-payload ownership and required-body recovery.
			- [x] Enumerate Module_Parameters header/block fields with source-order ownership and valid empty/block-only forms.
			- [x] Enumerate Location/Procedure_Name/Poke_Name fields with optional arguments, source-only scalar names and the owning parser overlay.
			- [x] Enumerate Run/Insert fields with source-header/body aliases, parser-added expressions and generated-state exclusions.
			- [x] Enumerate Scope/Through/Wildcard fields with childless source forms, scalar scope kinds and non-inferred wildcard indices.
			- [x] Enumerate ASM opaque compiler slots and parser-added helper lists/span/scope fields with source-body recovery guards; all 50 generated layouts now have draft field roles.
			- [x] Enumerate declared Code_Node/Parser_Node fields and the reviewed DIRECTIVE_THIS route without claiming nested location or base-kind reachability closure.
			- [x] Enumerate nested Code_Node.Location fields with scalar endpoint observations and excluded compiler-load provenance.
			- [x] Enumerate Token_Span and assembly Feature/Statement fields plus all four statement kinds with guarded helper dispatch.
			- [x] Enumerate assembly Instruction/Mnemonic_Size fields and both size kinds with adjacency guards and ordered operand-helper traversal.
			- [x] Enumerate assembly Operand/Value fields and all five operand kinds with active-base guards, published modifier ordering and required/optional value evidence.
			- [x] Enumerate assembly Register_Declaration/Register_Pinning fields with explicit-class guards, source/target order and rejected-suffix distinctions.
			- [x] Enumerate assembly Memory_Operand/Operand_Modifier fields and all seven modifier kinds; all ten current assembly helpers now have draft field roles.
			- [x] Audit the literal direct Parser_Node allocation and both immediate directive-dispatch sites for DIRECTIVE_THIS, leaving root-publication and reuse qualification open.
			- [x] Audit bare DIRECTIVE_THIS fresh root/file/block attachment, append-before-finish retention and the separate statement-call dispatch exception.
			- [x] Audit the simple imperative #this call path through expression/postfix builders and its owning callee edge, retaining wrapper/recovery boundaries.
			- [x] Audit DIRECTIVE_THIS exclusion from reusable-expression admission and the corresponding call-callee copy boundary.
			- [ ] Trace rejected DIRECTIVE_THIS expressions through enclosing declaration reuse admission and fresh fallback, and audit any bypassing copy callers.
			- [ ] Complete any additional direct base-node routes and exhaustive auxiliary fields/variants, and finish the builder-function reachability audit before closing the exhaustive registry task.
	- [ ] Qualify shared-region ownership, exact nested entry counts/containers, compound routes and rejection of cycles/unregistered sharing against independent fresh-output expectations after implementation authorisation.
	- [ ] Review diagnostic/index mappings against current parser nodes and fresh observations; qualify origins, malformed messages, repeated/compound/recovered names and visibility/traversal coverage after implementation authorisation.
	- [ ] Turn identity/payload review vectors into executable acceptance tests after implementation authorisation; document checks do not qualify their behaviour.
- [x] Consolidate R1-R8 review decisions, concrete remaining specification artifacts and the pre-migration completion gate without implying policy approval or executed acceptance tests.
- [x] Record explicit R1 initial-scope approval on 2026-10-20 without extending that approval to other review decisions, detailed contracts, implementation or migration.
- [x] Record explicit R3-R5 design-direction approval on 2026-10-21, keeping R2/R6-R8 and detailed schemas/algorithms/limits open and implementation/migration unauthorised.
- [ ] Resolve the review packet's initial direction, policy and performance decisions explicitly; record approvals/exclusions before finalising the concrete schemas and specification-completion review.
- [ ] Complete the source-provider contract under approved R3: specify capture consistency/capabilities, resolver membership, batch grammar, leases and host atomicity, then qualify V1-V8 against real adapters.
- [ ] Complete the execution contract under approved R4: specify coordinator ordering, delivery/admission limits, reentrancy, worker stopping/fairness and final destruction, then qualify X1-X8 with real concurrent tests.
- [ ] Complete the semantic contracts under approved R5: specify identity/matching/canonicalisation, supported query facets and cycle rules, then qualify D1-D8 for implemented capabilities with fresh/compiler oracles.
	- [x] Define source-ordered ordinary/`Context_Base` member comparison and order-independent completed `#Context` additions, separate from nominal identity and layout/effect observations.
	- [ ] Qualify context-contribution permutations, base/member changes, duplicates/provisional membership and layout-sensitive consumers against fresh/compiler oracles after implementation authorisation.
- [ ] Review and approve or revise the persistence contract; specify text grammar/bounds, operation ordering, locks/pins, filesystem guarantees and repair/privacy policy, then qualify S1-S8 against the implementation.
- [ ] Review and approve or revise the core contracts, including edit coordinates/batches, provider world capture, cancellation and lease semantics; turn T1-T8 into executable acceptance cases during implementation qualification.
- [ ] Approve or revise section 14's initial scope, deferrals, C1-C5 qualification checks and P1-P5 numerical candidates before treating them as acceptance requirements.
- [x] Run and record E1's bounded compiler import/visibility matrix, including auditing expected-failure diagnostics.
- [x] Run and record E2's bounded module identity/parameter probes, including nominal compatibility, transitive configuration, expected diagnostics, and evaluation counts.
- [x] Run and record E3's bounded loaded-file composition probes, including occurrence multiplicity, scope, relative paths, contextual module values/types, cycles, and diagnostic/marker audits.
- [x] Run and record E4's bounded path/source-context probes, including case/alias validation, relative lookup, exact locations, nominal identity, native links, byte equality, and complete diagnostic/marker audits.
- [x] Run and record E5's bounded compiler-evaluation probes, including added-string freshness/boundaries, context, mapping callbacks, workspaces, failures, startup costs, and complete artifact/diagnostic audits.
- [x] Run and record E6's bounded syntax-independence probe, including owned payloads/recovery, producer teardown, independent semantic contexts, fresh oracles, and the current-node alias control.
- [x] Run and record E7's bounded dependency/revision model, including exact reuse, dual-stamp checks, missing/candidate dependencies, retained worlds, conservative invalidation, and broken-policy controls.
- [x] Run and record E8's bounded pipeline/scheduler model, including milestone readiness, legal recursion, cycle groups, pending/shared requests, cancellation, world selection, shutdown, and broken-policy controls.
- [x] Run and record E9's bounded allocation/eviction benchmark, including SDK API probes, sparse and lease-delayed reclamation, payload cleanup, generation/slot reuse, backing accounting, and separate optimised timing.
- [x] Run and record E10's bounded text-artifact experiment, including exact byte/numeric fidelity, independent lifetimes, malformed/truncated/schema/bounds rejection, transactional publication, independent audit, and separate optimised decode/parse timing.
- [x] Run and record E11's bounded store/restart/overlay experiment, including killed and competing publishers, corrupt/unwritable stores, exact-content restart selection, host-confirmed recovery, save/reset/deletion/reappearance, lease-aware GC, diagnostics, and independent audit.
- [x] Capture E12's bounded real-source baseline: validated resident reuse, fresh parsing, explicit text-source-reparse control, repeated malformed/body/interface/layout edits, retained snapshot backing, process restart, and independent saved-data audit.
- [x] Capture E12's equivalent owned AST graph-text reload comparison on the 89-source inventory, including deep producer/input/sibling-teardown checks, exact source/context validation, fresh/resident competitors, backing profiles, rejection controls, and independent saved-data audit; retain its same-layout/read-only limits.
- [x] Measure E12's actual fresh-process graph reload against fresh-process parsing, with alternating order, worker/whole-process latency, exact input/artifact provenance, no resident warmup, and independent audit; label the filesystem warm/unflushed.
- [ ] Agree and run an isolated OS-cold storage procedure before making a cold-startup claim; fresh worker processes and regenerated artifact reads do not establish cold filesystem caches.
- [ ] Approve E12's numerical median/tail/memory/disk targets and extend the baseline to semantic dependency updates and the complete section 13 editor workflows, explicitly deferring unsupported capabilities.
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
- [x] Validate E13's bounded explicit `using,map` wrapper: generated member-name arrays, contextual callback invocation, framed result capture, slot/exclusion and supported-name validation, and host-owned results after evaluator teardown; retain the documented context/enumeration/production limits.
- [ ] Define cache-equivalence, invalidation, lifetime, restart, cancellation, corruption, and incomplete-code test matrices, including compiler verification of import/visibility rules.
- [ ] Define inaccessible-candidate diagnostics and explicit export fix actions, separate from ordinary identifier resolution and validated against current source and export impact.
- [ ] Benchmark the complete editor workflows in section 13 and agree acceptance thresholds before choosing chunk-level syntax reuse or finer cache granularity.
- [ ] Revisit the existing AST-copier decision independently of the future architecture, using its measured benefit and preserved correctness contracts.
- [ ] After the target model is agreed, write a separate migration/implementation plan from the current parser; do not treat this report as that plan.
