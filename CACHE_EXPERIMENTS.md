# Cache Architecture Experiments

Bounded experiments E1-E13 supporting the [cache architecture](CACHE_ARCHITECTURE.md); their conclusions are summarised there.
Status conventions, the decision record, the milestone index and the label glossary are in [CACHE_ARCHITECTURE.md](CACHE_ARCHITECTURE.md#document-map-and-conventions).

## Experiment Index

Each experiment uses small isolated fixtures/prototypes, not a parallel implementation of the new parser, and records its hypothesis, exact compiler/build configuration, commands, observed output, limitations, and resulting decision.
Language probes use the official compiler as the oracle, including separate expected-failure cases; prototype cache tests compare against fresh computation.
All probes ran manually on authored trusted fixtures, not by automatic evaluation of arbitrary workspace code.

E1-E13 are complete within their stated bounds.
Complete semantic editor-workflow measurements remain open, and E13 is not a production evaluator or general compilation-context extractor.

| ID. | Experiment and discriminating check. | Decision it informs. |
| --- | --- | --- |
| E1. | Completed: import/visibility matrix using bare and named imports at file, procedure, nested-block, and struct scopes; export/module/file visibility; access inside, outside, from siblings, and from another loaded file.  Each access compiled separately. | Verified scope receiving imported names, lexical namespace binding, and qualified module/file visibility; see results below. |
| E2. | Completed: repeated/aliased imports, omitted/explicit defaults, argument order/types/values, nominal assignment compatibility, two-hop imports, and program-setting constraints; 32 isolated probes and evaluation-count audit. | Canonical source plus effective parameter values is insufficient for compatible nominal identity; program configuration is per module and main-program controlled.  See results below. |
| E3. | Completed: 28 isolated loaded-file composition probes for repeated/diamond/aliased loads, order, relative paths, file scopes, module instances, collisions, missing files, and cycles; diagnostic and execution-marker audit. | Preserve load occurrences rather than deduplicating membership; share syntax without sharing contextual bindings or nominal declarations. See results below. |
| E4. | Completed: 35 isolated path/source-context probes covering casing, dot/parent/separator/absolute aliases, copied and relocated bytes, relative loads/imports, working-directory changes, junctions, and native directory/file symlinks; exact location/path, nominal identity, diagnostic, and execution-marker audit. | Keep physical document identity, source-visible path context, and compiler-compatible module identity distinct; request validation can differ even when the filesystem reaches the same source. See results below. |
| E5. | Completed: 32 compiler-evaluation compilations and five separate startup samples covering `do_output=false`, insert dumps, multiplicity, expression boundaries, context, `using,map`, multiple workspaces, stale artifacts, diagnostics, failures, and flattened-dump replay; complete artifact/log audit. | The text channel works for bounded trusted generators, but is not a fresh, self-contained semantic-result protocol.  Evaluator support remains deferrable; see results below. |
| E6. | Completed: eight syntax fixtures across 32 producer/context lifetime permutations, 32 fresh-parse oracles, 248 exact syntax checks, 96 independently owned semantic-context lifetimes, decoded-payload mutations, span/recovery validation, and a real-resolver shallow-alias control. | Owned syntax and external semantic tables survive independent teardown; current in-node bindings alias across shallow snapshots.  This establishes a bounded ownership contract, not a full overlay-replacement decision; see results below. |
| E7. | Completed: 23 edits of an 11-query model under tracked and conservative-module policies; 2,530 fresh comparisons, 1,600 link-stamp checks, exact recomputation expectations, retained old worlds, and 11 broken-policy controls. | Parent relationships and target revisions need independent validation; missing names and candidate sets are dependencies; equal observable results can stop propagation; world selection and identity/context guards are mandatory.  Conservative module invalidation is correct but recomputes more in this model; see results below. |
| E8. | Completed: 17 scheduler scenarios in both forward and reverse order, 844 authored expectation checks, 17 completion-equivalence checks, and eight broken-policy controls; independent audit of task, request, and dependency traces. | Publish individual milestones, deduplicate world-keyed work, cancel waiters independently, diagnose actual unresolved graph cycles rather than idleness, and reject duplicate/late completion after terminal states.  See results below. |
| E9. | Completed: direct `Pool`/`Bucket_Array` API probes; three allocation strategies across 54 memory phases, 5,232 handle/payload checks, 264 cleanups, three stale-generation controls, and 63 optimised rotating-order timing samples. | Typed slots enable individual record reuse, but payload ownership and bucket/group reclamation determine backing retention.  Arenas were faster in this small workload; separately freed payloads reduced sparse-eviction backing.  See results below. |
| E10. | Completed: five pointer-free text fixtures using `Text_File_Handler`; 153 exact record comparisons after producer/input teardown, 41 invalid cases, 2,872 rejected truncations, and 126 optimised decode/parse timing samples with independent wire-format/value/statistics audit. | An explicit bounded schema preserves exact bytes and numeric bits; the handler supplies line/version handling, not serialisation or validation.  Payload-heavy text can cost more than fresh parsing.  See results below. |
| E11. | Completed: filesystem store/restart/overlay model with 911 parent-process checks, 32 worker processes, five killed publishers, competing publication/retry, twelve corruption cases, real cache-directory write denial, save/reset/deletion/reappearance, lease-aware GC, four broken-policy controls, and an independent saved-evidence audit. | Immutable digest-addressed blobs plus locked manifest replacement preserve complete selected states under the tested interruptions.  Recovery is host-confirmed, exact source hashing defeats stale timestamps, and cache failures must preserve source operations and surface diagnostics.  See results below. |
| E12. | Completed (bounded baseline plus two reload follow-ups): measure fresh parse, unchanged-file reuse, and text reload with validation across many small files and large active files, transitive imports, malformed edits, body/interface changes, and repeated updates.  Include hashing/I/O, tail latency, retained worlds, and disk size; distinguish process restart from OS-cold filesystem cache. | Validated resident reuse is favoured; the verbose owned-graph text reload is slower than fresh parsing, so the graph codec is not adopted.  Informs workload selection and initial cache granularity; see results below. |
| E13. | Completed: explicit generated-array `using,map` wrapper versus real mapping, six equivalent pairs, module parameter/private-helper context, exclusions, three compiler rejections, invalid-output policy, twelve damaged-frame controls, and post-process host ownership. | The explicit wrapper works for this supported slice; preserve context and positional exclusions, require successful compilation before publication, and do not mistake a conservative identifier policy for compiler behaviour.  See results below. |

### E1 Results: Import Scope and Visibility

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

| Observed case. | Result. |
| --- | --- |
| Bare import at file/procedure/block/struct scope. | Exported markers accessible inside and at all tested outside sites, including another loaded file; module/file-visible markers not accessible as bare names. |
| Named import, binding in scope. | Qualified export/module-visible markers accessible; file-visible markers rejected.  Same result for markers from the imported module's entrypoint and its loaded file. |
| Named import, unqualified member access. | Rejected even inside the importing scope; no bare-name injection. |
| Named import at top level. | Namespace binding accessible in another procedure and another loaded file. |
| Import originating in a loaded file. | Bare-import exports accessible to its loading file, even when the import is nested; a named binding is accessible there only when top-level, with qualified export/module access but not file-visible access. |
| Named import in procedure/block/struct. | Namespace binding not directly accessible by its bare name outside that lexical scope; block-after/block-sibling and struct-sibling probes also reject it. |

Generated sources, individual `compile.log` files, and `summary.tsv` are retained under `examples/.build/import_visibility/` and can be regenerated; normal build cleanup may remove them.
The runner asserts the observed outcomes on rerun; a compiler behaviour change should fail the relevant assertion rather than silently replace the recorded rule.
An initial fixture used non-stallable compile-time calls, which masked some negative checks with scheduling diagnostics; the final results use stallable calls and have been fully re-audited.

These results are scoped to this compiler/version, backend, ordinary module-name imports, and the tested unconditional contexts.
E1's reverse-load probes use normal loaded-file scope; E3 below additionally tests an explicit `#scope_file` directive on the loaded file containing a named or bare import.
They do not establish behaviour for every directive/import modifier, transitive re-export, overload collision, disabled conditional branch, or other backend/platform.
For a struct-local named import, rejection of a bare `Probe` outside the struct does not establish whether an explicitly aggregate-qualified path such as `Container.Probe` is usable; that was not tested.
Module identity/parameter results are recorded in E2 below; loaded-file order/inclusion/cycle results are recorded in E3.
Architectural consequence: distinguish lexical binding from the scope receiving bare-import exports, and retain module/file-visible records while applying context-specific access filters.

### E2 Results: Module Identity and Program Configuration

Completed 2026-10-16 on Windows with Jai beta 0.2.030, built 2 July 2026, using the fast x64 backend.
Reproducible runner: [experiment_module_identity.jai](examples/experiment_module_identity.jai).
From the parser's examples directory:

```bash
jai experiment_module_identity.jai -x64 -quiet -no_color
```

The runner and all generated entrypoints disable executable output and added-string output.
Child compilations use `jai -x64 probe.jai -quiet -no_color -import_dir ..` in isolated named case directories.
The authored module has integer/string/`bool` module parameters, integer/`bool` program parameters, an otherwise identical nominal struct, exported effective values, and a compile-time `E2_INSTANCE` print marker.
Bridge and grandparent modules create a two-hop import chain; another bridge deliberately attempts a forbidden program-setting override.
Type equalities/inequalities, positive assignment compatibility, parameter values, and graph observations are asserted in accepted fixtures.

All 32 expected outcomes passed: 27 accepted compilations and five expected rejections.
The complete log audit matched all 40 expected module-instance evaluation markers in accepted compilations; each shared nominal instance printed once and each tested distinct pair printed twice.
Rejected compilations were not used to infer evaluation counts because compilation may stop before their `#run` directives execute.
The five rejections were two incompatible-struct assignments, one program-setting override from an imported module, and two duplicate program-setting sites (equal and unequal values).
Each negative log contained exactly its expected compiler error class; no parse/setup failure was counted as an identity result.

| Probe family. | Observed result. |
| --- | --- |
| Repeated same import. | Same nominal type and one evaluation, including repeated imports within a procedure or another loaded file. |
| Omitted versus empty module argument list. | Same instance. |
| Omitted versus explicit default arguments. | Distinct instances even though the tested effective values and integer value type match.  Assignment between omitted/default-explicit struct types is rejected. |
| Repeated same explicit argument list. | Same instance, for both partial and full lists. |
| Partial versus full default list; reordered named arguments. | Distinct instances despite equal effective parameter values. |
| Integer `3` versus `1+2`, in otherwise identical explicit lists. | Same instance: raw expression spelling alone is not the identity. |
| Integer `3` versus `(3).(s32)`; changed integer/string/`bool` values. | Distinct instances.  Preserve typed supplied arguments, not just printed values. |
| Repeated identical file/dir imports. | Same instance within each tested import form. |
| Module-name versus file/dir import; file spelling with redundant `../` traversal. | Distinct instances of the same physical source.  Do not unify nominal types through physical-path normalisation alone. |
| Byte-identical source in another module directory. | Distinct instance/type. |
| One explicit program-setting site plus ordinary imports. | All imports of that module share the configured settings and the same nominal instance for identical module arguments, including when the ordinary import appears first in source.  Explicit program defaults do not create the omitted-versus-explicit split seen with module arguments. |
| Different module-argument instances under one program setting. | Distinct nominal types, but both observe the one configured program setting. |
| Two program-setting sites for the same module. | Rejected even for identical values. |
| Program-setting site inside an imported module. | Rejected: settings may only be supplied from the main program. |

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

### E3 Results: Loaded-File Composition

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

| Probe family. | Observed result. |
| --- | --- |
| Repeated identical load; diamond load through two parents. | Public declarations are included again and produce redeclaration errors. Declaration-free controls succeed and print twice. |
| Same source through a redundant traversal. | Likewise, included twice: public declarations collide; the marker-only control prints twice. This does not establish import-style deduplication semantics for `#load`. |
| Same file loaded twice with file-private declarations. | Compiles, with each occurrence resolving its own file-private name and printing once; two prints total. |
| Same private name in two different files. | Compiles; each exported accessor resolves its own file's value, not its sibling's. |
| File-private names across a load boundary. | Hidden from loader, sibling loaded file, and in the reverse direction from a loaded file to a file-private loader declaration. |
| Relative load inside another file. | Resolves relative to the containing loaded file. A different same-named file beside the entrypoint was deliberately supplied as a discriminator. |
| Forward reference before `#load`; either order of two interdependent declaration files. | All tested pure declaration cases compile with the same values. This does not establish an order for arbitrary compile-time effects. |
| Scope directive in a loaded file. | Does not change the loader's subsequent declaration visibility; the loader's `#scope_file` also does not make an otherwise default-visible child's declarations file-private. |
| Named import in a loaded file under `#scope_file` | Its binding is hidden from the loading file. The corresponding `#scope_module` binding is visible there. |
| Bare import in a loaded file under `#scope_file` | Its exported members remain visible to the loading file, unlike the named-binding case. |
| Repeated imports of one module instance containing a load. | Same nominal loaded type and one loaded-file execution. |
| Different parameters of one module, or two different modules, loading the same source. | Separate nominal loaded types and two executions. Loaded values and private accessors observe their own module's parameters. |
| Distinct files with identical public declarations. | Redeclaration errors, not successful deduplication or first/last-wins lookup. |
| Direct self-load and two-file load cycle. | Rejected at the compiler's maximum of 100 nested loads; neither is silently deduplicated nor accepted as legal recursion. |
| Missing loaded file. | Explicit unable-to-open-file diagnostic. |

For hidden file-local names/bindings, compiler diagnostics also identified a matching file-scoped declaration and suggested `#scope_export`, consistent with the proposed tooling-candidate separation.
Generated sources, individual `compile.log` files, and `summary.tsv` remain under `examples/.build/load_composition/` and can be regenerated after cleanup.
The runner asserts every expected acceptance/rejection; the summary records exact marker and diagnostic expectations for auditing the logs.
No executable/object outputs were found in the fixture directory.

These results are limited to this compiler/version/backend/platform and the tested unconditional declaration/load graphs.
Conditional/generated loads, overload merging, dynamic filesystem changes, all path-alias forms, and arbitrary compile-time effect ordering are not established; E4 below adds bounded path-context coverage.
The 100-load limit is an observed compiler diagnostic, not a recommendation for the service's scheduler or a substitute for precise occurrence/cycle diagnostics.
Architectural consequence: cache source/syntax by document revision, but compose semantics using module instance plus load occurrence and file-local scope; do not turn a syntax cache hit into permission to suppress a language-level inclusion.

### E4 Results: Paths and Source Context

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

| Probe family. | Observed result. |
| --- | --- |
| `#filepath` and `#location(anchor)` | The former returns the containing directory, including its trailing separator; the latter reports a full filename plus line/column. Module anchor locations were line 6, column 11; entrypoint anchors were line 4, column 11. |
| Dot and parent aliases in loads/file imports/directory imports. | Accepted; the observed source-visible filename/directory retains `./` or `Branch/../`. Paired imports produce distinct nominal types and two executions. |
| Relative versus absolute file import. | The tested pair shares one nominal instance and one execution, with identical reported paths. Different textual requests are not universally distinct. |
| Repeated exact file/directory imports. | One nominal instance and one execution. |
| Backslash load path. | Accepted; reported paths use forward slashes in this load case. |
| Backslash versus forward-slash file imports. | Distinct nominal instances and two executions; the backslash spelling remains in that import's reported filename/directory. Do not infer one universal separator-normalisation stage. |
| Wrong filename case in a load/file import; wrong final directory case in a directory import. | Rejected with the Windows file-case portability diagnostic even though the filesystem can reach the existing source. |
| Lowercase containing directory in a load/file import, with exact filename case. | Accepted; reports retain `original/`. Paired file imports using `Original/` and `original/` have distinct nominal types and two executions. The observed validation is not uniform full-path case enforcement. |
| Byte-identical modules relocated beside different neighbours. | Distinct nominal types and values 11 versus 22 for both the relative load and the relative file import. Content equality does not establish dependency or result equality. |
| Byte-identical files with different filenames in the same directory. | Same `#filepath`, different filenames in `#location`, distinct nominal types, and two executions. Directory context alone is insufficient. |
| Compile `../probe.jai` with the child process working in `Branch` | Entrypoint reports its normalised source path and still finds the source-relative `Original` module, not an unrelated directory under the process working directory. |
| Missing source-relative neighbour. | Explicit missing-file error naming `Isolated/neighbor.jai`; the root decoy is not substituted. |
| Directory junction or native directory symlink, through load/file import. | Accepted; reports retain `Alias/`. Paired file imports through original and alias paths have distinct nominal types and two executions, while both relative lookups yield 11. |
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

### E5 Results: Compiler-Evaluation Feasibility

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

| Probe family. | Observed result. |
| --- | --- |
| Single insert with `do_output=false`, `write_added_strings=true` | Compilation succeeds and produces `.build/.added_strings_w2.jai`, including a workspace comment, source-file/line comment, and inserted declaration. Native output suppression does not suppress compile-time execution. |
| Multiple and nested inserts. | Multiple records share one workspace file. A nested insert leaves both the original inserted directive and the resulting declaration in that file; its provenance points back into the intermediate file. |
| Repeated identical insert text in distinct structs. | Both occurrences are retained, not content-deduplicated. Their original struct scopes are not reconstructed by the flat record format. |
| Empty insert versus no insert. | An empty insert creates a header-only artifact. A clean no-insert compilation creates none; a reused directory can instead retain an older file. |
| Expression insert. | The returned expression text needs its own semicolon: `40 + 2;` succeeds, while `40 + 2` produces a semicolon diagnostic and still leaves the returned text in the artifact. This is also documented by the compiler's insert example. |
| Header-like content inside an authored payload. | Compiles unchanged. The payload contains a comment matching the compiler's apparent insert-record header, so splitting solely on those comments cannot reliably delimit arbitrary generated text. |
| Insert in a loaded file. | Produces the expected declaration and names the loaded source file in its provenance comment. |
| Context-dependent generator, with and without its loaded input. | With the loaded `secret` value it generates 42; without that input the same generator fails. The missing-context case reports both the unavailable input and the generated declaration that never becomes available. |
| Same imported source with parameters 17 and 25 | Both contextual values compile and appear in one workspace dump as declarations with the same name and source-file/line provenance. Replaying that actual dump at a single top level rejects it as a redeclaration, reported twice. A flat dump does not preserve module-instance identity or scope; record order is not a source-order contract. |
| `using,map` | The callback receives `left`, then `right`, mutates them to `mapped_left`, then `mapped_right`, and the compiled test verifies writes through those aliases. Instrumented stdout records the ordered inputs/results, but no added-string artifact is created. The dump is not an automatic mapping-result channel. |
| Generated `#filepath` and `#location` | Observe the intermediate directory/file, not the authored insert site: the tested anchor is in `.build/.added_strings_w2.jai`, line 6, column 14. Existing textual provenance does not itself provide a structured source map. |
| Parent plus child compiler workspace. | Produces two files, `w2` and `w3` here, with distinct workspace comments. The child file contains both an `add_build_string()` record and its nested insert result. Do not assume one file, a universal workspace number, or insert-only contents. |
| Generated parse/type errors. | Both reject with diagnostics pointing into the generated file plus the originating insert directive; their artifacts still contain the invalid text. Artifact existence is not successful evaluation. |
| Deliberate assertion inside the generator. | Returns compiler exit status 1, with the authored assertion message and stack trace, and no fresh artifact in its clean directory. This is a compile-time program failure, not an induced native compiler crash. |
| Reused-directory freshness sequence. | A successful changed insert replaces old content. Removing all inserts leaves the previous file byte-identical; disabling emission also leaves it byte-identical; an early authored parse error leaves that same stale file. An error in newly generated text replaces it with the invalid new text, and a later successful run replaces that with the recovery result. |

Startup was measured separately from source compilation, around the same `run_command` path and captured-output process handling:

| Measurement. | Samples. | Minimum. | Median. | Maximum. |
| --- | --- | --- | --- | --- |
| `jai -version`, process/CLI startup only. | 5 | 173.873 ms. | 176.788 ms. | 183.992 ms. |
| No-insert compilation with Basic/Compiler imports and build-option setup. | 5 | 260.185 ms. | 282.648 ms. | 329.836 ms. |

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

### E6 Results: Syntax and Semantic Independence

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

| Fixture. | Status. | Declarations. | Tokens. | Diagnostics. | Recovery Records. | Synthetic Tokens. |
| --- | --- | --- | --- | --- | --- | --- |
| Scalar, external reference, escaped string. | `COMPLETE` | 3 | 16 | 0 | 0 | 0 |
| Here-string and external reference. | `COMPLETE` | 2 | 14 | 0 | 0 | 0 |
| Missing semicolon between declarations. | `RECOVERED` | 2 | 10 | 1 | 1 | 1 |
| Missing closing parenthesis. | `RECOVERED` | 2 | 12 | 1 | 1 | 1 |
| Error inside a procedure, followed by another declaration. | `RECOVERED` | 2 | 21 | 1 | 1 | 0 |
| Truncated procedure/declaration. | `INCOMPLETE` | 1 | 10 | 3 | 3 | 2 |
| Empty source. | `COMPLETE` | 0 | 1 | 0 | 0 | 0 |
| Empty string, full-width unsigned literal, external reference. | `COMPLETE` | 3 | 16 | 0 | 0 | 0 |

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

### E7 Results: Dependency and Revision Validation

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

### E8 Results: Pipeline Milestones and Scheduler Outcomes

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

### E9 Results: Allocation, Eviction, and Retained Snapshots

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

| Strategy. | Fixed records. | Owned payloads. | Reclamation unit. |
| --- | --- | --- | --- |
| Arena. | Per-revision `Pool` | Same per-revision pool. | Release the revision group after its last record lease ends. |
| Typed. | Eight-slot `Bucket_Array` buckets. | Individual upstream heap allocations. | Reuse each record slot and free its payload independently; reset the typed pool at final teardown. |
| Hybrid. | Same typed buckets. | Per-revision `Pool` | Reuse record slots independently, but release payload backing only when the revision group is empty. |

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

| Strategy. | Peak Backing Bytes. | Upstream Requests. | Record Address Reuses. | Median Lifecycle (us) | Batch p95 (us/lifecycle) |
| --- | ---: | ---: | ---: | ---: | ---: |
| Arena. | 32,768 | 9 | 0 | 5.214 | 6.961 |
| Typed. | 14,920 | 97 | 32 | 15.808 | 23.328 |
| Hybrid. | 34,856 | 18 | 32 | 9.689 | 14.553 |

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

### E10 Results: Bounded Text Artifact Round Trip

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

| Fixture. | Artifact Bytes. | Source Bytes. | Records Per Category. | Exact Record Comparisons. |
| --- | ---: | ---: | ---: | ---: |
| Empty. | 70 | 0 | 0 | 1 |
| Strings. | 5,783 | 112 | 8 | 33 |
| Numbers. | 2,872 | 140 | 10 | 41 |
| Recovery. | 1,057 | 16 | 3 | 13 |
| Limits. | 52,986 | 236 | 16 | 65 |

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

| Fixture. | Decode Median (us) | Decode p95 Batch (us) | Fresh Parse Median (us) | Fresh Parse p95 Batch (us) |
| --- | ---: | ---: | ---: | ---: |
| Strings. | 17.203 | 19.791 | 17.886 | 21.059 |
| Numbers. | 11.931 | 17.923 | 17.673 | 26.539 |
| Limits. | 125.608 | 170.105 | 25.128 | 38.492 |

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

### E11 Results: Store Publication, Restart, and Overlay Recovery

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

| Check. | Observed Result. |
| --- | --- |
| Kill during partial blob write. | Restart selects the old manifest/blob; staging is never selected. |
| Kill after blob publication, before manifest write. | Old selection survives; the unreferenced new blob can be collected. |
| Kill during partial manifest write. | Restart selects the complete old manifest, not the temporary prefix. |
| Kill after manifest flush/close, before replacement. | Restart still selects the old manifest. |
| Kill after manifest replacement. | Restart selects the complete new manifest/blob. |
| Competing publishers. | The second process fails open on the held lock, then retries successfully; both intended slot updates survive. |
| Identical content publication. | Both slots can name the same immutable blob without creating a duplicate. |
| Corrupt blob/manifest or mismatched context. | A fresh reader selects fresh authoritative source and records a cache diagnostic. |
| Write-denied cache directory. | Editing and saving source still work; the old manifest remains intact and write/metadata diagnostics are recorded. |
| Reachability GC. | Current roots and an explicit old-world lease survive; discarded and unleased historical blobs are removed, and crashed temporary files are cleaned. |

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

### E12 Results: Real-Source Baseline and Source-Reload Control

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

| Inventory. | Files. | Source Bytes. | Fresh Median/p95 (ms) | Resident Median/p95 (ms) | Source-Reparse Median/p95 (ms) |
| --- | ---: | ---: | ---: | ---: | ---: |
| Tutorials. | 56 | 687,364 | 18.364/19.721 | 2.004/2.789 | 24.629/28.005 |
| Invaders. | 8 | 75,331 | 4.151/5.479 | 0.280/0.597 | 5.077/6.222 |
| Parser. | 4 | 337,373 | 18.606/20.119 | 0.681/0.766 | 20.931/24.222 |
| Basic. | 18 | 348,676 | 16.524/18.436 | 0.887/1.211 | 18.981/22.274 |
| Authored Chain. | 3 | 1,163 | 0.194/0.398 | 0.047/0.082 | 0.244/0.422 |

Resident median savings are about 9-27 times on the four real inventories; their source-reparse controls are about 1.12-1.34 times slower than fresh parsing.
This supports validated whole-file retention, but does not quantify an equivalent AST reload's benefit or justify syntax chunking.
Each unchanged request reads the listed source bytes; the text control additionally reads all artifact bytes below.
Per-source headers and hex expansion make the complete text envelopes about 2.02 times source size.
The initial resident build and artifact encode/write costs are separate, single setup observations, not repeated latency statistics; writes use ordinary file APIs without a durability claim.

| Inventory. | Text Bytes. | Initial Read/Parse (ms) | Encode/Write (ms) | Resident Backing Bytes. | With Two Extra Active Snapshots. |
| --- | ---: | ---: | ---: | ---: | ---: |
| Tutorials. | 1,387,298 | 20.465 | 19.456 | 24,865,791 | 25,772,119 |
| Invaders. | 152,099 | 3.687 | 3.441 | 6,634,216 | 12,344,378 |
| Parser. | 680,148 | 17.852 | 2.781 | 34,628,496 | 79,286,796 |
| Basic. | 703,385 | 15.273 | 7.295 | 24,901,833 | 30,829,929 |
| Authored Chain. | 2,437 | 0.335 | 0.827 | 525,825 | 1,050,535 |

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
The bounded baseline is complete, but E12's full persistence/acceptance decision remains open, along with semantic transitive-dependency updates, real configured import closures, complete [architecture section 13](CACHE_ARCHITECTURE.md#13-correctness-and-benefit-criteria) editor workflows, OS-cold reads, concurrency, and cross-platform measurements.
No numerical acceptance threshold is implied by the observed milliseconds or speed ratios; approval remains a specification gate, not an automatic benchmark outcome.

#### E12 Follow-up: Equivalent Owned Graph Text Reload

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
`Pool`/table bookkeeping is outside that payload counter; these are not whole-process resource limits.
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

| Inventory. | Fresh Median/p95 (ms) | Resident Median/p95 (ms) | AST Reload Median/p95 (ms) | AST Text Bytes. |
| --- | ---: | ---: | ---: | ---: |
| Tutorials. | 25.059/28.953 | 2.984/3.894 | 111.255/145.359 | 14,826,050 |
| Invaders. | 4.209/5.070 | 0.256/0.355 | 21.926/25.803 | 3,911,306 |
| Parser. | 26.851/31.458 | 0.819/1.547 | 140.801/207.535 | 21,170,113 |
| Basic. | 14.123/15.017 | 0.789/1.081 | 82.271/85.221 | 16,079,410 |
| Authored Chain. | 0.139/0.211 | 0.033/0.045 | 0.607/0.721 | 108,262 |

This graph-text representation reloads about 4.4-5.8 times slower than fresh parsing on the four real inventories, with artifacts about 21.6-62.7 times their source size.
It preserves repeated source/token/trivia/name text rather than deduplicating strings or using source spans, and uses per-scalar text records and reflective dispatch; the result does not establish the performance of a compact field schema, binary format, or optimised decoder.
Single setup encode/write observations are approximately 288/47/285/182/2 ms in table order, not repeated request statistics or durable publication costs.

Separate untimed fresh/decoded backing profiles hold the whole inventory, then two extra largest-file copies, then release everything.
They track upstream requested bytes, including snapshot pools and decoder object-table capacity, but exclude disk/artifact input buffers, tracker bookkeeping, deep-oracle scratch, allocator-private overhead, and OS residency.
All ten fresh/decoded profiles return tracked bytes and outstanding allocation records to zero.

| Inventory. | Fresh Backing Bytes. | Decoded Backing Bytes. | Fresh With Two Extras. | Decoded With Two Extras. |
| --- | ---: | ---: | ---: | ---: |
| Tutorials. | 24,864,447 | 13,851,194 | 25,770,727 | 14,469,486 |
| Invaders. | 6,634,024 | 3,480,299 | 12,344,138 | 6,147,235 |
| Parser. | 34,628,400 | 17,809,332 | 79,286,652 | 38,220,834 |
| Basic. | 24,901,401 | 13,824,095 | 30,829,449 | 16,936,889 |
| Authored Chain. | 525,753 | 242,831 | 1,050,415 | 463,853 |

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
Semantic dependency updates and configured closures, complete editor workflows, concurrency, and cross-platform evidence remain open; OS-cold performance is excluded (R8).

#### E12 Follow-up: Fresh-Process Graph Reload Versus Fresh Parse

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

| Inventory. | Fresh Worker Median/p95 (ms) | Reload Worker Median/p95 (ms) | Fresh Process Wall Median/p95 (ms) | Reload Process Wall Median/p95 (ms) |
| --- | ---: | ---: | ---: | ---: |
| Tutorials. | 21.478/26.334 | 107.964/125.536 | 59.560/72.449 | 145.048/167.141 |
| Invaders. | 5.228/5.798 | 27.269/30.349 | 40.563/42.713 | 63.354/69.184 |
| Parser. | 20.250/24.544 | 133.164/151.995 | 53.367/72.903 | 166.709/188.215 |
| Basic. | 15.618/16.677 | 90.434/97.745 | 45.472/49.101 | 121.282/128.032 |
| Authored Chain. | 0.456/0.528 | 1.082/1.495 | 34.320/37.235 | 35.148/39.931 |

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
Semantic dependency/configured-closure and full editor-workflow measurements, concurrency, cross-platform evidence, and production contracts remain open.
No production cache API or migration plan was added.

### E13 Results: Explicit `using,map` Wrapper

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

| Check. | Observed result. |
| --- | --- |
| Six positive pairs. | All agree in cardinality, order, exact mapped bytes, and retained empty exclusion slot.  Changing the module prefix changes both paths equally; the private helper remains available in the preserved module. |
| Excluded alias. | Referencing `mapped_right` after excluding `right` rejects with `Undeclared identifier 'mapped_right'`. |
| Missing context. | Removing the private helper from the direct wrapper's module rejects with `Undeclared identifier 'decorate'`.  Copying just the callback is insufficient. |
| Duplicate mapping. | Real mapping rejects with `Redeclaration of 'same'`.  The explicit wrapper call itself succeeds, but the host rejects its colliding output. |
| Distinct punctuated names. | Real mapping accepts `not-0` and `not-1` when no source expression tries to reference them.  Both real and wrapper outputs are rejected by this experiment's deliberately narrower ASCII-identifier policy.  This is a supported-subset restriction, not evidence that the compiler rejects such names or that they are convenient source-level aliases. |
| Publication. | Fifteen compilations succeed, three reject as expected.  Three successful but unsupported/colliding outputs are not published; only the twelve positive results are retained.  Frames emitted before a compiler error are never sufficient for success. |

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

## Scope of the Evidence

E5 is a bounded feasibility probe, not a prerequisite to implementing the syntax-first service while evaluation remains explicitly unsupported.
Do not block the initial specification on optional syntax-chunk reuse, binary formats, mmap, packed sentinel optimisation, or full compiler-backed evaluation; retain a simple supported baseline and explicit extension boundaries.
