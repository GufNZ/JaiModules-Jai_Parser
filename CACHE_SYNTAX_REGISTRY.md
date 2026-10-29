# Current-Producer Syntax Registry

The projection of the current parser's nodes, helpers and tokens onto the syntax payloads in [CACHE_CONTRACTS.md](CACHE_CONTRACTS.md#source-update-and-query-interface-schema-draft).
Status conventions, the decision record, the milestone index and the label glossary are in [CACHE_ARCHITECTURE.md](CACHE_ARCHITECTURE.md#document-map-and-conventions).

## Current Parser Mapping and Known Gaps

Proposed mapping review 2026-10-21; this is a producer-adapter contract, not an implemented traversal or proof of complete coverage.

| Producer surface. | Required payload mapping or explicit gap. |
| --- | --- |
| `Token_Type` in `lexer.jai`. | `TokenTag` is `BYTE_CHAR {value:u8}` or `NAMED {name_ascii}` under `jai-cache-token-tags/1`, registered below.  Normalise producer aliases before encoding; reject unknown/noncanonical payload names rather than serialising enum ordinals. |
| `Parser_Token` with `ENABLE_TRIVIA`. | Use checked `byte_start`/`byte_end` against the owned exact source.  For a nonempty token interval, map the first token's start through the last included token's end; do not include preceding/trailing trivia implicitly.  Preserve token intervals as separate observations. |
| `Parser_Token` without `ENABLE_TRIVIA`. | This aliases `Token`, which has line/column observations but no byte-offset fields.  It is outside the full-featured service profile: no non-trivia byte-mapping adapter is required.  Existing AST-compatibility mode may remain in the current parser independently; this specification does not require preserving that mode in the future owned-syntax API. |
| `add_missing_token`. | Correlate the diagnostic's recovery record with `synthetic_tokens` and `insertion_index`; map the insertion position to a checked zero-width source anchor.  At end of input use the exact source length when the token/source mapping validates it.  No synthetic token bytes are inserted into the authoritative source.  Missing/ambiguous correlation remains `UNLOCATED`, not a guessed inserted origin. |
| `Parser_Declaration`/`.DECLARATION`. | Emit the authored declaration with its actual name and origin, retaining recovery state and containing syntax ownership.  A synthetic helper `declaration_properties` inside a compound node is not an additional standalone declaration entry. |
| `Parser_Compound_Declaration`/`.COMPOUND_DECLARATION`. | Read `comma_separated_assignment.arguments` in authored order and shared `declaration_properties`.  For a qualified `parse_declaration_node` construction, the binding predicate is `(!reassignment && modifier != ASSIGN) || modifier == DECLARE`, where reassignment is the shared `operator_type` equal to the `=` character.  Emit only arguments satisfying this predicate; `ASSIGN` targets and ordinary multi-target reassignment remain uses.  The separate expression-led construction needs route classification as described below; do not apply this predicate universally.  Do not collapse names or duplicate the shared properties node as an entry. |
| `Parser_Directive_Scope`/`.DIRECTIVE_SCOPE`. | Map `scope_type` `EXPORT`, `INTERNAL`, `FILE` to `SCOPE_EXPORT`, `SCOPE_MODULE`, `SCOPE_FILE` respectively, preserving the directive origin.  Track direct same-list provenance under the rules below; conditional branches retain branch-local observations without evaluation or a guessed merged visibility state. |
| Declaration `#export` observation. | The reviewed scope-directive parser does not establish a declaration-marker mapping.  `EXPORT` in `declaration_marker` is reserved until a real producer path or qualified lossless syntax adapter is identified.  Do not infer it from scope `EXPORT`, resolved visibility, string matching inside comments/literals, or absent metadata.  Unrepresentable relevant observations require `RECOVERED_UNKNOWN`/partial coverage, not a false `UNSPECIFIED` assertion. |
| Declaration `#program_export` metadata. | `parse_declaration_metadata` sets `PROGRAM_EXPORT` and optionally stores a string token's value in `program_export_name`.  This requests a program/linker export, not module visibility or the reserved declaration `EXPORT` marker.  Preserve it separately as specified below; the stored string is scalar data, not an AST child. |

The index traversal follows authored syntax ownership/child edges only; it must not follow resolved declarations, lexical binding/reference tables or inferred semantic backreferences.
Snapshot-local node IDs identify syntax occurrences, not names; assign index-local entry IDs independently, preserving the declared enclosing-before-nested and per-binding order.
For nested syntax within a shared compound initialiser, use the proposed shared-region representation below rather than selecting one binding as its sole enclosing declaration.
Until that representation and the reached child mappings are reviewed and qualified, report partial coverage for that region rather than duplicate it or invent container identity.

`COMPLETE_SYNTAX_TRAVERSAL` requires a reviewed child-edge/variant registry covering every reached authored node kind and every required route, origin/name, visibility, metadata and recovery-attribution observation.
An unknown node or unmapped required field makes coverage partial with a reason; successful parsing alone is not that proof.

Mapping checks to implement after authorisation: raw punctuation versus named/aliased tokens; trivia-enabled origins and rejection of a non-trivia full-featured profile; EOF insertion/recovery correlations; `a, b := values` versus `a, b = values` and mixed declare/assign modifiers; shared compound initialiser ownership; sequential/conditional scope directives; unmapped declaration markers and unknown child variants.
These supplement C1/C5 and the payload review vectors without claiming executable adapter qualification.
The initial fifteen-operation interface and all pending policy/implementation gates are unchanged.

## Same-List Scope Provenance and Conditional Boundaries

Proposed declaration-index/2 refinement grounded in the scope-directive builder function and `parse_static_if_statement`/`parse_statement_block`.
The builder function publishes a standalone `DIRECTIVE_SCOPE` with a `scope_type`; it does not attach effective visibility to each declaration.
Static conditionals retain their branches, including parser-created single-statement blocks, rather than selecting one during parsing.
Consequently, `scope_directive` is strictly a source-provenance summary, not an effective lexical/module visibility state.

`scope_basis` is `{statement_list_node_id:s64, preceding_directive_node_id:s64}`; `-1` means an ID is not set, while each nonnegative ID refers to a node of this result's protected syntax snapshot.  Values below `-1` reject before lookup.
The first identifies the nearest owning registered statement-list node on the declaration occurrence's authored ownership path; the second identifies the last qualified direct scope-directive element before the statement containing that occurrence in that same list.
Resolve this path through registered owning edges only, not block-parent/resolution pointers, token-span containment or whichever alias was visited first.
A shared compound payload uses its shared-region ownership path, not a binding selected arbitrarily as an owner.
The referenced list and directive must satisfy the registered node/field roles and actual list ordering.
An out-of-snapshot ID or a directive that is not a preceding direct element is invalid evidence, not an alternative visibility interpretation.

| Authored situation. | Required provenance result. |
| --- | --- |
| Qualified preceding direct directive. | Record that list and directive, map its exact `scope_type`, and preserve its source observation.  A later direct directive supersedes it only for this same-list summary. |
| Qualified list with no preceding direct directive. | Record the list with no directive and `UNSPECIFIED`.  This means no direct same-list observation, not private/module/export default visibility. |
| Nested block, aggregate body or conditional branch. | Compute a separate list-local summary.  Do not copy an outer list's directive into the inner list's basis or leak the inner list's last directive into its parent or a sibling branch.  The owning syntax graph preserves outer/branch context independently. |
| Declaration nested in an expression/header without an intervening statement list. | Use the nearest owning registered statement list and its containing statement as the ordering anchor.  Do not treat a directive inside some other child of that statement as preceding in this list. |
| No statement-list ancestor in a supported standalone syntax form. | Both IDs are absent, and the tag is `UNSPECIFIED`; this does not establish a language default or prove that such syntax is semantically valid. |
| Missing ownership/list correlation or unknown relevant directive form. | Preserve independently verified observations, use `RECOVERED_UNKNOWN`, and report `UNKNOWN_VISIBILITY` or `UNCLASSIFIED_ROUTE` with `VISIBILITY` impact as appropriate.  Do not confuse unavailable evidence with a qualified no-directive result. |

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
Assert exact basis IDs, source observations, list-local tags and partial reasons against independent ownership/list expectations.
Compiler visibility/default/inheritance behaviour remains separate pending qualification; these are draft source-provenance rules, not that behaviour's implementation.

## Program Export Metadata Versus Visibility

Proposed 2026-10-21 for the declaration-index/2 draft; no producer adapter or source-observation pass is implemented by this refinement.

`parse_declaration_metadata` recognises `align`, `no_reset`, `uninitialized`, `elsewhere` and `program_export`; its default branch stops without consuming an unknown directive.

That path does not recognise `export`.

This establishes a limit of the reviewed producer path, not that `#export` is supported elsewhere or that every remaining source token was inspected as declaration metadata.
Keep declaration-marker `EXPORT` reserved and the earlier unknown-observation rule intact.

Neither `PROGRAM_EXPORT` nor `program_export_name` supplies a declaration-marker or scope-directive value.

`program_export_syntax` is `{coverage, occurrences: []ProgramExportOccurrence, producer_observation}`.

Its `coverage` is `COMPLETE_METADATA_OBSERVATION. | PARTIAL_METADATA_OBSERVATION {reasons: []CoverageReason}` for this declaration's metadata, not semantic export validity or whole-index traversal.

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

## Authored Child Edges and Shared Compound Regions

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

The following is the summary of the registered draft field paths for the current parser-owned shapes; the milestone-1 closure below binds it to the detailed per-layout rules and explicit exclusions.
Names without a prefix refer to `Parser_*` records; grouped rows do not waive per-variant review.

| Owner. | Candidate downward paths/active helpers. |
| --- | --- |
| `Declaration`. | `type_inst`, `expression`, `alignment_expression`, `notes[]`; compound properties use this field map without emitting a helper declaration.  `program_export_name` is scalar string metadata, not a child. |
| `Compound_Declaration`. | `comma_separated_assignment` node (then its ordered argument nodes), `declaration_properties` as helper, compound `alignment_expression`, compound `notes[]`; preserve structural node IDs and visit shared payload once, not through lexical bindings. |
| `Block`. | `statements[]` only; source order is authoritative. |
| `Procedure_Header`, `Procedure_Body`. | Follow the procedure ownership/alias rules below: parameter segments, `returns[]`, optional `library_identifier`, `modify_directives[]`, optional `body_or_null`.  Body owns `block`, not `header`.  `foreign_function_name` and `deprecation_string` are scalar strings; header `notes[]` is not populated on the reviewed routes. |
| `Struct`, `Enum`. | Struct: optional `arguments_block`, `modify_directives[]`, `block`.  Enum: optional `internal_type_inst`, `block`.  Follow the aggregate-context rules below; struct `alignment` is numeric metadata, and aggregate `notes[]` is not populated on the reviewed routes. |
| `Unary_Operator`, `Binary_Operator`, `Cast`. | `subexpression`; `left`, `right`; casts use prefix/postfix/auto source-form order specified below rather than unconditional target-before-expression traversal. |
| `Procedure_Call`. | `procedure_expression`, then `arguments_unsorted[]` helpers (optional `name` before `expression`), then optional `context_modification.modification_expressions[]`; use the published-helper and recovery rules below, never sorted/resolved arguments or macro output. |
| `Comma_Separated_Arguments`, `Return`. | `arguments[].node`; `arguments_unsorted[]` helpers (`name`, `expression`), respectively. |
| `Expression_Query`, `Type_Query`, `Type_Instantiation`. | `expression_to_query`; `type_to_query`; type-instantiation paths follow the explicit source-form guards below, not a nonnull-pointer priority chain. |
| `Literal`. | Follow the literal-arm and construction-route guards below: struct `type_expression`, `arguments[]`; array `element_type`, `array_members[]` on reviewed routes.  Scalar/null literals have no authored children; array alignment is not populated by these reviewed builder functions. |
| `If`, `Case`, `While`. | Follow the control-flow guards below: condition before branches/body, both authored branches without evaluation, context-qualified absent default-case conditions and normalised single-statement blocks. |
| `For`. | Source-ordered `want_reverse_expression`/`want_pointer_expression`, then `want_replacement_for_expansion`, `ident_it`, `ident_it_index`, `iteration_expression`, optional `iteration_expression_right`, `block`; use the control-flow guards below and exclude implicit declarations/generated expansion. |
| `Loop_Control`, `Defer`, `Push_Context`, `Using`. | `target_ident`; `block`; `to_push`, `block`; optional `filter_expression` before `expression`, respectively.  Parameter-using expression aliases follow the header-specific rule instead of a second descent. |
| `Directive_Add_Context`, `Directive_Bytes`, `Directive_Code`, `Directive_Location`, `Directive_Run`. | Guarded payload descent as specified below; arrow-run source headers are a reviewed exception to excluding compiler-lowered procedure fields. |
| `Directive_Bake`, `Directive_Exists`, `Directive_Import`. | `procedure_call`; `query_expression`, optional `sync_expression`; optional module/program parameter calls with import-callee backreference guards.  Import `name` is scalar string data. |
| `Directive_Insert`. | Optional `scope_redirection`, published replacement statements in qualified clause order, then `expression`; not generated `expansion`. |
| `Directive_Library`, `Directive_Load`, `Directive_Modify`. | Library/load names are scalar strings with no child; modify owns `block`.  Do not follow imported/loaded files. |
| `Directive_Module_Parameters`, `Directive_Overlay`, `Directive_Poke_Name`, `Directive_Procedure_Name`. | `module_parameters`, `program_parameters`, `common_code`; `target_expression`, `declaration_or_using`; parser `module_expression` only (poke `name` is scalar); optional `argument`, respectively. |
| `Ident`, `Context`, `Note`, `Placeholder`, `Directive_Context_Type`, `Directive_Scope`, `Directive_Through`, `Directive_Wildcard`. | No authored node children in the candidate mapping; retain source scalar observations separately. |
| Base `Parser_Node` with `.DIRECTIVE_THIS`. | No authored child in the reviewed `#this` builder function; this reachable kind is not represented by a concrete entry in `TYPES`.  Preserve its source/kind observations without interpreting a nonexistent derived payload. |
| `Asm`. | Parser-owned `features[]`, `statements[]` helpers, not opaque compiler `b1`/`b2`/`b3` storage.  Use the explicit assembly-helper guards and order below; `UNPARSED` base operands can still own parsed modifiers. |

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

The milestone-1 closure below fixes the draft's current-producer guards/order, alias ownership and explicit marker/compound/metadata limitations.
Remaining qualification must exercise those rules, producer-version drift and truthful partial coverage; closing the registry does not make unavailable observations available.
Future C1/C5 vectors must cover shared initialisers with nested anonymous/ordinary/compound declarations, zero/one/multiple declared bindings, repeated names, both compound construction routes, recovered null/unlocated helpers, injected cycles/unregistered sharing, inactive literal arms and deliberately populated semantic backlinks.
Assert exact entry/region counts, IDs, association order, parent containers and coverage reasons against independently authored expectations, not only a second traversal using the same registry.
The registry has a source-reviewed draft boundary, not a behaviourally qualified implementation; exact API/schema review remains open.

## Recovery Attribution and Published Syntax

Proposed declaration-index/2 refinement grounded in `add_missing_token`, `add_expected_expression_at`, `add_unexpected_token` and the cursor-only checkpoint/restore implementation.
Recovery records retain diagnostic references and, for missing tokens, a synthetic-token reference; they do not identify an owning declaration node.

`parser_restore` restores only the cursor, so observations from an abandoned attempt cannot automatically be attributed to the syntax later published at that position.
The result-wide parse status and diagnostic/token spans are therefore insufficient by themselves to classify each entry's recovery.

For this index, recovery status concerns the entry's published authored subtree, not just its name/header and not the whole document.
Attribute recovery through a qualified construction observation or registered producer-version-bound correlation under the adapter's existing `builder_function_routes` capability; this does not add another capability feature.
Evidence must distinguish committed published syntax from discarded/speculative work and preserve the diagnostic/recovery/synthetic-token relationships.
Capturing a time interval or scanning for overlapping diagnostics alone is not that proof.

| Entry status. | Required evidence. |
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
Assert exact per-entry statuses, published ownership associations, partial reasons and retained diagnostic order against independent expectations.
This draft neither instruments the parser nor qualifies a correlation adapter.

## Declaration Events, Local IDs and Partial Containers

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
Assert exact entry/region arrays, IDs, event order, container paths and partial impacts against independent expectations.
This draft resolves ordering/representation rules, not a production visitor, cross-result matcher or qualified child registry.

## Structured Coverage Reasons and Consumer Guarantees

Proposed declaration-index/2 refinement; reason records describe incomplete observations, not source-language diagnostics, successful semantic facts or service failures.

`CoverageReason` is `{code, subject, field_path: []PathStep, impacts: []CoverageImpact, origin: Optional(Origin), detail_utf8}`.

`subject` is `DOCUMENT` or `NODE {local_node_id}` in the protected syntax snapshot of this exact envelope; it is not an entry ID, pointer or cross-result reference.

`PathStep` is `FIELD {name_ascii}` or `ELEMENT {index:u64}`; field names and list steps resolve through the bound registry, with checked list indices.

An empty path refers to the whole subject; `DOCUMENT` requires an empty path.

For an unrecognised field/kind without a safe registered path, identify the containing safe node or document rather than manufacturing a dereferenceable path.
Retain unsupported raw observations in the protected snapshot only where its schema safely represents them.
An unavailable origin is `NONE`, not an invented zero-width source range; an available `Origin` must pass the common revision/span checks and indicates the known affected observation, not necessarily the full extent of missing syntax.

`CoverageImpact` is `DECLARATION_SET. | CONTAINMENT. | NAMES. | SOURCE_MAPPING. | VISIBILITY. | ORDER. | METADATA. | RECOVERY`.

The list is nonempty, has no duplicates and follows that registry order.

State all known impacts: uncertainty about which bindings exist is not merely a display-name issue, and uncertain child ownership can affect both containment and declaration enumeration.

`detail_utf8` is explanatory text, not a machine-readable classification or an authority for coverage; clients must not parse it to recover a missing code/impact.

| Exact reason code. | Intended missing observation. |
| --- | --- |
| `UNAVAILABLE_OBSERVATION`. | A required registered adapter feature cannot provide evidence for this reached region. |
| `UNMAPPED_NODE_KIND`. | A reached syntax kind lacks a reviewed safe traversal/index mapping. |
| `UNMAPPED_FIELD`. | A required field or active variant has no qualified mapping. |
| `UNCLASSIFIED_ROUTE`. | Construction/source-form evidence is insufficient, including ambiguous compound binding classification. |
| `UNMAPPED_ORIGIN`. | Required source/name/recovery location cannot be correlated without guessing. |
| `UNMAPPED_NAME`. | Name form, source spelling or producer-value correlation is unavailable. |
| `UNCORRELATED_METADATA`. | Metadata boundaries, occurrence presence/order or source/value association are not established. |
| `UNKNOWN_VISIBILITY`. | Authored scope/marker observations required by the index cannot be established. |
| `UNPROVEN_CHILD_ORDER`. | Children are safely known but their required authored order is not established. |
| `OPAQUE_SYNTAX`. | A preserved source region, such as an unparsed assembly operand, has not been traversed for the promised observations. |
| `UNREGISTERED_SHARING`. | A safe repeated node lacks a qualified alias/single-owner rule; stop the unqualified descent rather than duplicate it. |

Codes and impacts are closed ASCII tags; unknown tags reject this schema rather than silently becoming generic success.

Numeric admission/text ceilings follow the milestone-2 `Limits` contract: documented implementation ceilings, lowered only by optional host-configured quotas under R6.

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

Assert exact reason records/order, impacts, coverage aggregation and forbidden negative inferences against independent expectations.

This draft defines the observation contract, not an implemented coverage engine or approved numeric/API bounds.

## Name Spelling, Producer Values and Recovery

Proposed refinement of declaration-index/2 names and the adapter's `name_origins` capability, grounded in `parse_operator_declaration_name`, declaration-name capture and backticked identifier lexing.
The producer's name string is an observation, not necessarily an exact contiguous source spelling.
Keep it separate from source bytes; neither equality by name nor interner-address identity establishes a declaration occurrence or nominal identity.

For `SPELLED`, `origin` covers the actual name occurrence's source tokens, and `spelling_bytes` equals that exact half-open source slice without removing comments, whitespace or backticks.

`producer_name_bytes` is the owned exact name value stored by the producer for this occurrence; it need not equal `spelling_bytes` and is not an editor-normalised display name.

`form == IDENTIFIER` applies to ordinary/compound binding identifiers and context-qualified bare enum members; `OPERATOR` requires the qualified operator-declaration route, not punctuation anywhere in an expression.

Preserve modifier/keyword source observations outside the name separately; do not include the declaration's type, initialiser or `operator` keyword in the symbol-name slice merely because they share its node interval.

| Qualified occurrence. | Spelling/value distinction. |
| --- | --- |
| Ordinary identifier. | Correlate the actual name token, not the declaration's first token, which may instead be `#no_reset`, `$` or another prefix.  Preserve exact producer name bytes and raw token spelling. |
| Backticked identifier. | The lexer marks `ident_is_backticked` and preserves the token spelling including the leading backtick, while its identifier name comes from the identifier scanner after that prefix.  Do not strip bytes from the source slice or claim the producer value includes the backtick. |
| Single-token operator name. | The operator parser returns a registered punctuation/operator string.  Correlate the consumed operator token under the operator-declaration route; declaration/operator flags do not supply its origin alone. |
| Multi-token operator name. | `*[]`, `[]` and `[]=` are constructed producer strings.  The source name interval runs from the first symbol through the last actually consumed name symbol, including intervening trivia; e.g. `operator [ ] =` preserves `[ ] =` separately from producer `[]=`. |
| Recovered operator punctuation. | `parser_expect` can record a missing `]` while the operator parser still returns `*[]`/`[]`/`[]=`.  Keep only the actual source bytes in the name slice and correlate missing punctuation separately; never insert expected bytes into `spelling_bytes`. |

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

## Syntax Adapter Capabilities and Coverage Admission

Proposed review packet for the syntax-to-payload adapter, separate from the source-provider adapter's filesystem/lease capabilities.
The existing `producer` context field must identify both the actual adapter build and its canonical observation capabilities; parser identity and output-schema names alone do not identify an index mapping implementation.
Changing a route classifier, child/alias registry, name/origin mapping or supported observation set must conservatively change this binding before reuse.
A complete index from an older binding cannot be relabelled under the new one, even when exact source and parser build are unchanged.

The proposed capability schema is `jai-cache-syntax-adapter/1`, encoded as `K("syntax-adapter", [schema_id, registry_binding, feature_records...])`.

`registry_binding` names the exact registered authored-edge, origin/name and payload mappings used by this adapter.

Feature records appear in the following table order and use `K(feature_name, [method_tag, observation_schema])`.

`method_tag` is exactly `UNAVAILABLE`, `CAPTURED` or `RECONSTRUCTED`; `observation_schema` is empty bytes only for `UNAVAILABLE`, otherwise the exact registered producer-observation or correlation schema identifier.

Reject unknown/missing/reordered/duplicate features and unsupported schemas; these are not free-form claims or a generic extension map.

The adapter build identity is a separate service-verified value in the `producer` context field, not inferred from this descriptor's text or a host-selected label.

| Feature name. | Required evidence and current review status. |
| --- | --- |
| `authored_edges`. | Exact reachable-kind/field/variant/order registry, including base `DIRECTIVE_THIS`, guarded aliases and recovered holes.  The milestone-1 closure fixes the current-producer draft and its exclusions; implementing and qualifying a bound adapter remain open. |
| `builder_function_routes`. | Qualified source-form/context evidence for types, literals, enum-member mode, parameter usings, import callees and arrow-run headers, plus committed published-syntax recovery attribution under the rules above.  Do not infer a universal route from equal/default field values or recovery ownership from diagnostic overlap.  Capture versus reconstruction remains review work. |
| `compound_routes`. | Snapshot-bound `CompoundRoute` and separator observations under the following contract.  Current AST fields alone are insufficient; no qualified capture/reconstruction adapter is supplied yet. |
| `name_origins`. | Exact spelled/anonymous/missing observations, separate source spelling and producer-name values, name-specific recovery and explicit unmapped outcomes, including operator names, unnamed slots and context-qualified enum members.  A copied/normalised producer name is not automatically a single source slice.  The draft's unavailable-evidence disposition is fixed; implementing and qualifying actual source correlation remain open. |
| `metadata_origins`. | Correlated metadata boundaries/order and argument presence, including repeated/bare/empty program exports and alignment/replacement clauses whose final fields lose occurrences.  Current final fields alone are insufficient. |
| `declaration_markers`. | Authored declaration-marker observations distinct from scope and program exports.  The reviewed parser paths have not established declaration `#export` support; this gap must stay explicit rather than be declared captured. |

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
Assert exact binding equality/misses, admission/query outcomes and per-result coverage against independent expectations.
This matrix records the integration choices still requiring review; it does not approve instrumentation, a reconstruction adapter, policy defaults or the final API.

## Compound Route Evidence and Binding Classification

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

| Qualified route. | Binding and shared-region rule. |
| --- | --- |
| `IDENTIFIER_HEAD`, `reassignment=false`. | For each target in stored order, declare when its modifier is not `ASSIGN` (including explicit `DECLARE`); retain the declaration-properties/recovery observations. |
| `IDENTIFIER_HEAD`, `reassignment=true`. | Declare only targets with explicit `DECLARE`; unmodified/`ASSIGN` targets are uses. |
| `EXPRESSION_HEAD`. | No newly declared bindings.  Traverse the actual target expressions and shared RHS once; preserve the operator observation and create a shared region with an empty binding list when required to contain nested syntax. |
| `UNCLASSIFIED` or missing evidence. | Preserve the compound/target/helper syntax and report partial index coverage for ambiguous binding classification.  Do not fabricate bindings or certify their absence from default fields. |

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

## Generated Layout Inventory and Registry Closure

Inventory baseline for the milestone-1 registry closure, taken from `parser.jai`'s `TYPES` array.
It contains 50 distinct compiler layouts whose parser counterparts are generated; this is not a count of qualified reachable variants or a completed snapshot field schema.
Names below are exact `TYPES` members, grouped only for review.
Their `Parser_` counterparts follow the existing generator; neither a payload tag nor an active field mapping may be inferred merely from a layout name.

| Review group. | Count. | Exact generated-layout inputs. |
| --- | --- | --- |
| Assembly. | 1 | `Code_Asm` |
| Expressions/operators/types. | 7 | `Code_Binary_Operator`, `Code_Cast`, `Code_Expression_Query`, `Code_Procedure_Call`, `Code_Type_Instantiation`, `Code_Type_Query`, `Code_Unary_Operator` |
| Blocks/control/using. | 10 | `Code_Block`, `Code_Case`, `Code_Defer`, `Code_For`, `Code_If`, `Code_Loop_Control`, `Code_Push_Context`, `Code_Return`, `Code_Using`, `Code_While` |
| Declarations/aggregates. | 5 | `Code_Comma_Separated_Arguments`, `Code_Compound_Declaration`, `Code_Declaration`, `Code_Enum`, `Code_Struct` |
| Procedure storage. | 2 | `Code_Procedure_Body`, `Code_Procedure_Header` |
| Scalar/value forms. | 5 | `Code_Context`, `Code_Ident`, `Code_Literal`, `Code_Note`, `Code_Placeholder` |
| Directives A-L. | 10 | `Code_Directive_Add_Context`, `Code_Directive_Bake`, `Code_Directive_Bytes`, `Code_Directive_Code`, `Code_Directive_Context_Type`, `Code_Directive_Exists`, `Code_Directive_Import`, `Code_Directive_Insert`, `Code_Directive_Library`, `Code_Directive_Load` |
| Directives M-W and location. | 10 | `Code_Directive_Location`, `Code_Directive_Modify`, `Code_Directive_Module_Parameters`, `Code_Directive_Overlay`, `Code_Directive_Poke_Name`, `Code_Directive_Procedure_Name`, `Code_Directive_Run`, `Code_Directive_Scope`, `Code_Directive_Through`, `Code_Directive_Wildcard` |

The direct `Parser_Node` builder function for `.DIRECTIVE_THIS` is an additional known kind route outside this list; do not invent a derived compiler-layout payload for it.
A total of 50 generated layouts plus this route is not proof that all supported parse roots/builder functions have been inventoried.
Non-node helper records also require separate field/variant coverage: struct/array literal info, call arguments/context modifications, compound arguments and assembly helpers are not extra entries in `TYPES` or automatically extra node IDs.
Generated overlays can expose compiler-only or inactive fields.
For each input, the remaining registry must bind actual constructed kind/source routes, every field's traversal role, active-form guards, null/recovery semantics, ordering and any alias owner; use the existing detailed route sections as evidence, not a substitute for that enumeration.
Mark a layout's reachability or field mapping unresolved when builder function evidence is incomplete.
Mere presence in `TYPES` cannot justify complete traversal, nor can absence from a test corpus justify excluding a builder function.

The focused inventory check compares this table's exact names with the live `TYPES` list, requiring equal sets, no duplicate names and the declared group counts.
That static check can validate inventory transcription now; it does not qualify builder function reachability, field ownership or a future visitor.
The milestone-1 closure below supplies the current-source builder crosswalk and explicit supported-profile limits alongside the subsequent field/variant rules.
Independently authorised behavioural qualification remains a separate gate, not a prerequisite for calling the draft specification enumerated.

## Milestone 1: Syntax Registry Closure

Draft registry closure completed 2026-10-22 for the current parser source and installed compiler declarations.
This closes the specification's layout/helper inventory, named allocation-owner crosswalk, traversal/alias rules and disposition of known mapping gaps.
It does not approve an API, provide an adapter, implement a visitor or claim complete results from every parse.
The bound producer/context must identify this exact registry; a producer change requires renewed inventory/route review rather than inheriting completeness from these counts.

The normative draft is the detailed field-role and source-form sections below, the common origin/name/recovery rules, the compound shared-region policy and the restrictions in this closure.
The summary tables are not alternative traversal algorithms.
Exact wire tags, scalar/flag encodings, public access signatures and numeric bounds belong to milestone 2; implementation and behavioural qualification belong to their separately authorised gates.

### Producer Roots and Published Graph

The reviewed producer roots are `parse_expression`, `parse_declaration`, `parse_block`, `parse_declaration_block`, `parse_file` and `parse_file_edit`.
These are producer entrypoints, not additional service operations or a claim that every root has the same declaration grammar.

| Entrypoint. | Selected root builder/admission. | Published-graph rule. |
| --- | --- | --- |
| `parse_expression`. | `parse_value_expression`. | Retain its actual returned expression, including wrappers; diagnose missing/trailing input without inventing another root. |
| `parse_declaration`. | `parse_declaration_node`, followed by terminator/notes handling. | Retain the returned kind; this entrypoint can return non-declaration directives and does not itself justify an index entry. |
| `parse_block`. | `parse_block_node`, imperative mode. | Only the returned block and attached statement list are roots/children; missing opening braces can yield no root. |
| `parse_declaration_block`. | `parse_block_node`, `DATA_DECLARATIONS` mode. | Use declaration-context statement rules.  Enum-member mode is enabled only by the separate registered enum-body route, not by this entrypoint's name. |
| `parse_file`. | `parse_file_node`. | The returned block owns successfully retained statements; even an empty file can have a block root. |
| `parse_file_edit`. | Validate edit range and unchanged prefix/suffix, then `parse_file_node` through `parseInit`. | Rejected input returns no successful replacement snapshot.  Admitted replacement syntax follows the same field registry; copied node identities are local to the new result, not the old snapshot's IDs. |

`parseInit` attaches only the root builder's returned pointer.
Starting there, follow exactly the registered active owning fields in the detailed sections, including parser-created blocks, returns, type wrappers, comma nodes and compound properties.
An allocated helper/node that is never attached contributes no descendant or index entry.
A failed child builder does not fabricate a placeholder beyond the producer's actual recovery graph.
Lexical scopes, resolver references and allocator pools are not alternate discovery paths.

### Per-Layout Allocation Owners

Each row names every current function containing a literal allocation of that generated parser layout.
Names in the copy column are the complete local copy-owner set for that layout; `NONE` means no literal allocation in those copy functions, not that the layout cannot occur below a reparsed parent.
The field-role/source-form sections determine the actual active kind, child ownership/order, required versus optional holes and publication context.
In particular, one layout can have multiple source forms, and a declaration allocation can be a compound property or anonymous procedure slot rather than an independent named declaration.

| Generated layout input. | Fresh allocation owners. | Copy allocation owners. |
| --- | --- | --- |
| `Code_Asm`. | `parse_asm_statement`. | `NONE`. |
| `Code_Binary_Operator`. | `parse_binary`, `parse_postfix_suffixes`. | `copy_reusable_expression`. |
| `Code_Block`. | `parse_aggregate_block`, `parse_aggregate_parameter_block`, `parse_block_node`, `parse_case_block`, `parse_file_node`, `parse_ifx_branch`, `parse_procedure_body`, `parse_statement_block`. | `NONE`. |
| `Code_Case`. | `parse_case_block`. | `NONE`. |
| `Code_Cast`. | `parse_postfix_suffixes`, `parse_prefix`. | `copy_reusable_expression`. |
| `Code_Comma_Separated_Arguments`. | `parse_declaration_expression`, `parse_declaration_node`, `parse_statement`. | `reuse_simple_declaration`. |
| `Code_Compound_Declaration`. | `parse_declaration_node`, `parse_statement`. | `reuse_simple_declaration`. |
| `Code_Context`. | `parse_primary`. | `NONE`. |
| `Code_Declaration`. | `parse_arrow_procedure_header`, `parse_declaration_node`, `parse_primary`, `parse_procedure_type_header`, `parse_statement`. | `reuse_simple_declaration`. |
| `Code_Defer`. | `parse_defer_statement`. | `NONE`. |
| `Code_Directive_Add_Context`. | `parse_declaration_directive`. | `NONE`. |
| `Code_Directive_Bake`. | `parse_expression_directive`. | `NONE`. |
| `Code_Directive_Bytes`. | `parse_expression_directive`. | `NONE`. |
| `Code_Directive_Code`. | `parse_expression_directive`. | `NONE`. |
| `Code_Directive_Context_Type`. | `parse_expression_directive`. | `NONE`. |
| `Code_Directive_Exists`. | `parse_expression_directive`. | `NONE`. |
| `Code_Directive_Import`. | `parse_expression_directive`. | `NONE`. |
| `Code_Directive_Insert`. | `parse_expression_directive`. | `NONE`. |
| `Code_Directive_Library`. | `parse_expression_directive`. | `NONE`. |
| `Code_Directive_Load`. | `parse_expression_directive`. | `NONE`. |
| `Code_Directive_Location`. | `parse_expression_directive`. | `NONE`. |
| `Code_Directive_Modify`. | `parse_declaration_directive`. | `NONE`. |
| `Code_Directive_Module_Parameters`. | `parse_declaration_directive`. | `NONE`. |
| `Code_Directive_Overlay`. | `parse_declaration_directive`. | `NONE`. |
| `Code_Directive_Poke_Name`. | `parse_expression_directive`. | `NONE`. |
| `Code_Directive_Procedure_Name`. | `parse_expression_directive`. | `NONE`. |
| `Code_Directive_Run`. | `parse_expression_directive`. | `NONE`. |
| `Code_Directive_Scope`. | `parse_declaration_directive`. | `NONE`. |
| `Code_Directive_Through`. | `parse_declaration_directive`. | `NONE`. |
| `Code_Directive_Wildcard`. | `parse_expression_directive`. | `NONE`. |
| `Code_Enum`. | `parse_aggregate_definition`. | `NONE`. |
| `Code_Expression_Query`. | `parse_primary`. | `copy_reusable_expression`. |
| `Code_For`. | `parse_for_statement`. | `NONE`. |
| `Code_Ident`. | `new_asm_ident`, `parse_asm_statement`, `parse_declaration_node`, `parse_enum_member`, `parse_for_statement`, `parse_loop_control_statement`, `parse_primary`, `parse_procedure_call`, `parse_procedure_flags`, `parse_type_instantiation`. | `copy_reusable_expression`. |
| `Code_If`. | `parse_if_statement`. | `NONE`. |
| `Code_Literal`. | `parse_aggregate_literal`, `parse_expression_directive`, `parse_primary`, `parse_using_filter`. | `copy_reusable_expression`. |
| `Code_Loop_Control`. | `parse_loop_control_statement`. | `NONE`. |
| `Code_Note`. | `parse_declaration_notes`. | `NONE`. |
| `Code_Placeholder`. | `parse_declaration_node`. | `NONE`. |
| `Code_Procedure_Body`. | `parse_procedure_body`. | `NONE`. |
| `Code_Procedure_Call`. | `parse_procedure_call`. | `copy_reusable_expression`. |
| `Code_Procedure_Header`. | `parse_arrow_procedure_header`, `parse_primary`, `parse_procedure_type_header`. | `NONE`. |
| `Code_Push_Context`. | `parse_push_context_statement`. | `NONE`. |
| `Code_Return`. | `parse_procedure_body`, `parse_return_statement`. | `NONE`. |
| `Code_Struct`. | `parse_aggregate_definition`. | `NONE`. |
| `Code_Type_Instantiation`. | `make_type_instantiation`, `parse_type_instantiation`. | `copy_reusable_type_instantiation`. |
| `Code_Type_Query`. | `parse_primary`. | `copy_reusable_expression`. |
| `Code_Unary_Operator`. | `parse_postfix_suffixes`, `parse_prefix`. | `copy_reusable_expression`. |
| `Code_Using`. | `parse_procedure_type_header`, `parse_using_statement_after_keyword`. | `NONE`. |
| `Code_While`. | `parse_while_statement`. | `NONE`. |

The extra base allocation is `Parser_Node` in `parse_expression_directive`, kind `DIRECTIVE_THIS`; its root/statement/call paths and reuse exclusion are reviewed separately below.
It has no derived payload.
No other literal base allocation or named indirect wrapper use is admitted by this source inventory; a new one requires registry review, not a guessed leaf rule.

### Auxiliary Storage Closure

The syntax-helper inventory is `Token_Span`; the five handwritten parser counterparts `Parser_Argument`, `Parser_Comma_Separated_Argument`, `Parser_Array_Literal_Info`, `Parser_Struct_Literal_Info`, `Parser_Context_Modification`; all ten `Parser_Asm_*` helper records; embedded `Code_Scope_Entry`; selected `Code_Literal.values`; and the qualified source-null `Code_Pointer_Literal_Info`.
Common `Code_Node`, `Parser_Node` and `Code_Node.Location` are bound by the base-field rules.
Compiler counterparts and parser overlays share the registered storage; they are not additional occurrences.

Every declared helper field is assigned a role in the detailed tables, including all eight embedded assembly-value slots.
All four assembly helper enums have closed named variant guards.
Helpers without node bases get no node IDs; real nodes used structurally, such as compound properties or comma nodes, retain their own IDs without becoming standalone index declarations.
Parser bookkeeping (`Parser`, `Parsed_Source`, lexical scopes/bindings/references), source/token/diagnostic transport records and compiler-only generated/resolved records are not additional authored AST helper families: their service schemas or semantic contracts are separate work.
Reaching one through an unregistered syntax edge is not permission to traverse it.

### Single-Owner and Alias Rules

| Association. | Sole downward owner/permitted observation. | Mismatch rule. |
| --- | --- | --- |
| Embedded base/entry and generated overlays. | The same node/storage view, with common fields classified once; never allocate an extra ID for an overlay. | Incompatible layout/context is a conversion failure, not a second interpretation of the bytes. |
| Compound properties and shared metadata. | The compound owns one comma node and one properties node; targets use the outer container, properties and compound-owned alignment/notes use the shared region.  Bindings reference this region; they do not own duplicate initialisers. | Unexpected properties-owned metadata or unclassified compound routes use the explicit partial dispositions below. |
| Header parameter using. | The matching `arguments[]` element owns the declaration.  The header owns the `Using` wrapper/filter; `Using.expression` is an association only when pointer-identical to exactly one argument in this header in the required order. | Missing/duplicate/unmatched safe associations produce `UNREGISTERED_SHARING` or `UNCLASSIFIED_ROUTE`, not generic using-target suppression. |
| Import-owned parameter call. | The import owns each parameter call; its `procedure_expression` is a non-owning association only when it is this owning import.  Ordinary calls still own their callee. | Missing/mismatched safe owner correlation is `UNCLASSIFIED_ROUTE`, not a name/span heuristic, arbitrary ancestor alias or generic cycle exemption.  Invalid references remain conversion failures. |
| Arrow-run source header/block. | The registered source header owns its body and block; `Directive_Run.expression` is a block association only when it matches that header's actual body block under the arrow route.  Insert's implicit run wrapper follows this same rule. | Without qualified route/identity evidence, do not choose between two ownership paths; report the affected partial region. |
| Other declared backlinks and semantic registries. | `Procedure_Body.header`, block/case/assembly parent/owner fields, resolved declarations/types, lexical scopes and sorted/generated storage never supply authored descent. | Do not turn populated semantic state into additional declarations or an alias capability. |

An active downward cycle, invalid reference or conflicting snapshot-bound evidence remains a conversion failure.
A safe completed-node revisit without a registered owner rule is `UNREGISTERED_SHARING` and stops that unqualified descent.
Equal spans/spellings never merge distinct node occurrences, and a global visited set cannot substitute for these contextual guards.

### Advertised Limits and Mapping Dispositions

This registry promises defined handling of the current syntax graph, not universally complete declaration indices.
A future adapter must advertise its actual methods for the existing six capability features; no `CAPTURED` or `RECONSTRUCTED` implementation is asserted here.
Missing evidence cannot be hidden by advertising the registry name.
The following are explicit supported-profile limits, not unassigned mapping TODOs.
Impacts below are minimum affected domains; add every other known impact under the common coverage contract.

| Reached condition/excluded inference. | Required disposition. | Coverage/admission consequence. |
| --- | --- | --- |
| Non-trivia full-featured profile. | Reject profile admission; preserve the separate current compatibility mode without promising byte mapping for it. | Unsupported profile, not a successful empty index. |
| Compound construction evidence unavailable or ambiguous. | Preserve safely represented targets/properties, use the specified unclassified route, and emit no guessed bindings or guessed binding absence.  A qualified future observation must obey the existing identifier-head/expression-head rules. | `UNCLASSIFIED_ROUTE`, affecting `DECLARATION_SET` and `CONTAINMENT` where binding/container association is unknown. |
| Bare enum-member, unnamed slot, type/cast or other context-sensitive source form lacks its required route evidence. | Keep the safely known syntax; do not infer membership, anonymity or an active arm from spelling/default fields alone. | `UNCLASSIFIED_ROUTE`/`UNAVAILABLE_OBSERVATION`, with the actual declaration/order/source impacts. |
| Declaration `#export` marker. | No current producer path is admitted for `declaration_marker == EXPORT`.  Scope export and program export do not supply that evidence.  A missing marker feature cannot certify marker absence. | `RECOVERED_UNKNOWN` plus `UNKNOWN_VISIBILITY` or `UNAVAILABLE_OBSERVATION` with `VISIBILITY` impact wherever marker observations are required. |
| Repeated/overwritten metadata, source-name or committed-recovery correlation unavailable. | Retain exact source/tokens, safe final fields and independently known entries.  Use unmapped names, unknown recovery or unavailable occurrence metadata rather than reconstructing discarded syntax or claiming complete absence. | `UNCORRELATED_METADATA`, `UNMAPPED_NAME`, `UNMAPPED_ORIGIN` or `UNCLASSIFIED_ROUTE`, with `METADATA`, `NAMES`, `SOURCE_MAPPING`, `ORDER` and/or `RECOVERY` as affected. |
| Unexpected compound-property metadata, procedure/aggregate notes or aggregate-literal alignment without a registered route. | Do not silently drop a required observation or treat a nonnull field as permission for new descent. | `UNMAPPED_FIELD`/`UNCLASSIFIED_ROUTE`; include `DECLARATION_SET`, `CONTAINMENT` or `ORDER` when unknown child ownership can affect them. |
| Safely represented unknown kind, active helper variant or unproved child order. | Preserve only safe observations, stop the unqualified edge/variant, and retain an explicit region reason. | `UNMAPPED_NODE_KIND`, `UNMAPPED_FIELD` or `UNPROVEN_CHILD_ORDER`; no complete traversal claim. |
| Unparsed assembly or rejected/unpublished syntax. | Published unparsed regions remain opaque with their actual modifiers; unattached temporary allocations are not syntax children. | `OPAQUE_SYNTAX` for promised but uninspected regions; do not invent nodes for discarded storage. |
| Lowered/compiler-generated/evaluated pointers, imports/loads, resolved visibility or evaluator effects. | Exclude from authored traversal.  Source request nodes and their registered payloads remain syntax; arbitrary pointer/type-definition literal arms are not reinterpreted as source-null or aggregate payloads. | Known non-authored fields stay excluded without manufacturing a source gap; an unqualified required literal/route uses `UNMAPPED_FIELD`/`UNCLASSIFIED_ROUTE`.  Semantic/evaluator queries remain unsupported initially. |
| Invalid references, out-of-range observations, conflicting evidence, incompatible layouts or downward cycles. | Reject conversion under the existing failure contract. | Not a successful partial index and not a parser diagnostic. |

Any required unavailable observation propagates to top-level `PARTIAL_SYNTAX_TRAVERSAL` with its subject/path and impacts; safe independent records remain usable.
No empty reason list, default `UNSPECIFIED`, reserved marker value or unchanged field list may certify complete coverage.
A request for an entirely unimplemented query/schema remains unsupported rather than becoming a partial implementation by declaration.
Retained results keep their original binding and coverage when a later adapter gains capabilities.

### Closure Evidence and Remaining Gates

The existing `code_field_inventory.jai` reflection probe was compiled and run against the installed compiler for this closure: all 50 generated layout field sets and eight common/helper/union inventory records agreed with the companion inventory.
The source crosswalk checks every generated layout and its fresh/copy allocation owners; the previous local allocation and copier inventories cover literal base/helper sites and named non-call references.
The helper/variant checks cover the handwritten records, spans, overlays and embedded value fields.
These are source/declaration checks, not execution of a cache visitor.

Milestone 1 is complete as a draft specification with these explicit partial/unsupported boundaries.
The existing registry review gate's inventory, field, alias and gap-disposition requirements are discharged here; its post-implementation C1/C5 behavioural requirement remains open.
Milestone 2 must finalise API/encoding/bounds and real adapter admission.
Later acceptance work must independently exercise node/entry/region IDs, order, malformed variants, aliases, lost metadata, unavailable evidence, producer drift and teardown.
This closure does not settle the AST-copier keep/drop decision or migration planning.

## Shared Base Fields and Direct Base-Only Kinds

Declared-field coverage for the common base, grounded in the `Code_Node` inventory, the `Parser_Node` declaration and the reviewed `#this` builder function.
These rows apply to every generated layout without duplicating its node ID or creating a base-to-derived traversal edge.

| Record/storage domain. | Exact field roles. |
| --- | --- |
| `Code_Node`/shared compiler base. | `kind`: `NON_CHILD`, producer kind observation under the registered mapping, not a native ordinal wire tag.  `location`: `HELPER`, qualified source-location observation storage, not an authored node edge.  `node_flags`: `NON_CHILD`, registered source bits only, excluding typechecked/desugaring state.  `type`: `NON_CHILD`, inferred/compiler type excluded from syntax observations and descent.  `serial`: `NON_CHILD`, compiler bookkeeping excluded; never the snapshot node ID. |
| `Parser_Node`/parser-owned base. | `first_token`: `NON_CHILD`, trivia-enabled token-interval start.  `one_past_last_token`: `NON_CHILD`, trivia-enabled exclusive end.  `code_node`: `HELPER`, embedded alternate compiler-base view of this same node, not another occurrence or an owned syntax child. |
| `Code_Node.Location`/nested compiler location. | `enclosing_load`: `BACKREFERENCE`, compiler file/load provenance excluded from authored descent and owned syntax payloads.  `l0`: `NON_CHILD`, raw starting-line observation.  `c0`: `NON_CHILD`, raw starting byte-column observation.  `l1`: `NON_CHILD`, raw ending-line observation.  `c1`: `NON_CHILD`, raw exclusive ending byte-column observation.  These four producer coordinates are declared `s32`; their native representation is not a wire schema or an absolute source-byte interval. |
| Base route/`DIRECTIVE_THIS` | No additional layout-specific fields or authored children on the reviewed `#this` route.  Its builder function allocates `Parser_Node` directly, assigns the kind and finishes its source interval; it does not allocate a derived payload or attach a resolved receiver/declaration. |

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
This base-field check validates transcription only; the milestone-1 closure separately binds the base-kind and nested-helper inventory.
Executable visitor qualification remains open.

The location-specific static check separately compares all five nested declared fields and the four `finish_node` endpoint assignments.
It does not qualify other builder functions, reuse rebasing, coordinate-to-byte conversion, filename resolution or producer-teardown behaviour.

## Local Allocation-Site Inventory

The regular local Jai source-file inventory, including ignored files without following symbolic links, finds 129 named references to `new_parser_node`: one definition and 128 direct calls, all in `parser.jai`.
Each call supplies `parser` and a literal type name; no named non-call reference, alias assignment or callback registration appears in that searched source set.
The 128 call sites use 55 distinct type names, classified below against the live `TYPES` list and helper declarations.

| Generic allocator argument class. | Call sites/distinct types. | Classification boundary. |
| --- | --- | --- |
| Generated parser layouts from `TYPES` | 120/50 | Every current generated layout name appears among the literal arguments.  This establishes allocation-site coverage, not every kind/variant, successful publication, source origin or independent traversal qualification. |
| `Parser_Node`. | 1/1 | The reviewed `DIRECTIVE_THIS` builder; retain its separate base-kind route rather than inventing a generated layout. |
| `Parser_Array_Literal_Info`. | 3/1 | Non-node helper storage for aggregate, using-filter and copy routes; expression/type children follow their registered field roles. |
| `Parser_Struct_Literal_Info`. | 2/1 | Non-node helper storage on aggregate/copy routes, not an additional generated node layout. |
| `Parser_Context_Modification`. | 1/1 | The reviewed fresh context helper; its direct-copy allocation is counted separately below. |
| `Code_Pointer_Literal_Info`. | 1/1 | The reviewed source-null non-node helper.  A compiler type name does not create an additional parser node kind. |

Separately, `parser.jai` contains 13 direct `New` call sites: the generic wrapper's `New(T, ...)` forwarding site and 12 concrete helper/scope sites.

| Direct allocation class. | Call sites/distinct concrete types. | Classification boundary. |
| --- | --- | --- |
| `New(T, ...)` inside `new_parser_node`. | 1/not a concrete type. | This is the wrapper implementation, not another independently constructed object per wrapper invocation.  Do not sum wrapper call sites and this forwarding site as object counts. |
| Assembly helper allocations. | 10/9 | Register pinning/declaration, memory operand, operand, modifier, instruction, mnemonic size, statement and feature records; mnemonic size has two sites.  Node children remain separate allocations under the assembly mapping. |
| `Parser_Context_Modification`. | 1/1 | The reviewed copied-call helper; direct `New` does not change its non-node identity. |
| `Parser_Lexical_Scope`. | 1/1 | Parser bookkeeping, not an authored syntax-node allocation or another downward ownership path.  This row does not close scope-field or binding/resolution qualification. |

The focused static check compares all named wrapper references, literal argument sets/counts, the 50-name `TYPES` correspondence and all direct `New` argument classes with these tables.
These are current source-site inventories, not runtime allocation counts or proof of every reachable variant.
They do not enumerate embedded/by-value helpers, array backing allocations, other allocation APIs, generated/indirect invocations, external callers, discarded nodes or builder-to-owner publication for every supported root.
Allocation counts alone do not close the auxiliary registry or publication rules; the milestone-1 closure binds those draft inventories and dispositions separately.
Executable publication and behavioural/lifetime qualification stay open.

## Direct Base-Node Builder Reachability

Bounded fresh-source audit of the literal `Parser_Node` allocation and its immediate directive-dispatch paths in `parser.jai`.
The current source has one explicit `new_parser_node(parser, Parser_Node)` call, in the `this` branch, and two direct call sites into `parse_expression_directive`.
This is a source-site inventory, not proof that generic allocation/copy paths or every supported parse root have been exhausted.

| Review site. | Guard/forwarding path. | Result/review boundary. |
| --- | --- | --- |
| `parse_primary`/directive dispatch. | After the hash token, require an identifier directive name; static-if-expression, type and here-string handling have their own routes.  Other identifier names forward to `parse_expression_directive(parser, first, directive_name.ident_value.name)`. | The `this` spelling can reach the direct base builder from primary-expression parsing.  Dispatch itself does not allocate a derived directive payload or resolve a receiver. |
| `parse_declaration_directive`/fallback dispatch. | Require hash plus identifier, capture the current token index/name, then use the default directive branch to forward to `parse_expression_directive(parser, first, name)`. | The `this` spelling has no specialised declaration-directive branch in the reviewed source, so it can reach the same base builder.  This forwarding path does not make the result a declaration or prove grammar/semantic validity in every caller. |
| `parse_expression_directive`/`this` builder. | Consume the two directive tokens, allocate `Parser_Node`, assign `DIRECTIVE_THIS`, call `finish_node`, then return that node. | No derived layout, attached child or resolved receiver is created by this branch.  Ordinary base-field and origin/range rules apply; only a node reached from the published syntax graph receives a snapshot-local ID. |

A returned allocation is not proof that an enclosing builder attaches it to a published root; callers may reject or discard syntax.
Do not discover declarations or node IDs by scanning the allocation pool, and do not promote an unattached directive to an index entry.
The focused static check compares the literal allocation count, both forwarding sites and the direct builder's shape with this table.
It must expose a newly added literal base allocation or forwarding site for review rather than silently assuming it has the same route.
The fresh-root attachment review below covers only its named entrypoints.
Other root-to-node paths, indirect/alternate allocation paths, fresh-versus-reuse equivalence, recovery attribution and independent behavioural qualification remain open; the 50-layout inventory plus this reviewed branch is not a closed node-kind universe.

Fresh attachment review for the bare `#this` directive follows the returned pointer through these owning paths.
This describes the parser's retained syntax, not semantic acceptance of a receiver directive in every context.

| Review site. | Attachment/retention path. | Result/review boundary. |
| --- | --- | --- |
| `parseInit`/root assignment. | Assign the selected root builder's return value to `parser.parsed.root`. | Common root retention, not a requirement that the root have declaration kind.  A null builder return remains null; allocation alone does not create a root. |
| `parse_declaration`/standalone root. | Select `parse_declaration_node` as the root builder; the ordinary directive path can return the bare base node.  Terminator/notes/trailing-input handling inspects the retained result without replacing its root. | A declaration-named entrypoint can retain a non-declaration directive root.  Classify by the actual kind and registered route, not the entrypoint name; do not invent a declaration-index entry. |
| `parse_file_node`/fresh declaration fallback. | After a failed reuse attempt, call `parse_declaration_node`; append each nonnull return to the statement list before `finish_statement`, then assign that list to the returned block. | The file root's owning statement list can retain the bare directive.  Later terminator diagnostics do not retroactively remove an appended node.  This does not qualify reuse admission or copy behaviour. |
| `parse_block_node`/ordinary non-enum blocks. | Imperative blocks call `parse_statement`; declaration blocks use declaration parsing after any reuse attempt.  Append a nonnull return before `finish_statement`, then attach the list to the block. | The `parse_block` and `parse_declaration_block` root builders can retain the directive in the same owning list domain.  Missing opening braces return no block; enum-specific routes and all other enclosing contexts need their own review. |

For a bare hash directive, `parse_statement` returns the nonnull declaration-directive result directly.
Its explicit `#this(` exception instead enters the ordinary expression path, so the direct-leaf statement rule must not be applied to that spelling or used to discard potential expression wrappers.
The bounded simple-call attachment review below covers that exception; other expression-wrapper paths remain open.
Append-before-finish ordering is not recovery attribution: preserve exact tokens, raw node intervals and diagnostics without inferring that a missing terminator created or removed this node.
A failed builder return contributes no list entry; an allocated but discarded node remains outside the published graph.
The focused static check covers root-builder wiring, fresh file/block list attachment, the statement dispatch exception and retention through terminator handling.
It does not execute these inputs or qualify arbitrary enclosing wrappers, enum mode, incremental reuse, independent result ownership or declaration-index recovery attribution.

Fresh simple-call review for `#this(...)` in an imperative statement, without additional postfix/binary/comma wrappers:

| Review site. | Forwarding/ownership path. | Result/review boundary. |
| --- | --- | --- |
| `parse_statement`/call-form fallback. | The explicit hash/this/open-parenthesis exception skips direct declaration-directive return; the ordinary expression branch obtains `left` from `parse_binary` and returns it when no comma-led compound route is taken. | The returned expression, not a separately promoted bare directive, enters the already-reviewed imperative block statement list. |
| `parse_binary` and `parse_prefix`/simple expression forwarding. | Binary parsing starts with `parse_prefix` and returns its left expression when no binary operator is selected; the ordinary non-prefix-operator case forwards to `parse_postfix`. | This restricted route introduces no extra unary/binary wrapper.  Prefix operators, explicit types, compound statements and additional operators require their own guarded routes. |
| `parse_postfix`/call suffix. | Obtain the base directive from primary parsing, then pass it and the original starting-token index to postfix-suffix parsing.  An opening parenthesis replaces the current result with `parse_procedure_call(parser, result, first)`. | The call wraps the existing base node; it is not a derived payload for `DIRECTIVE_THIS` or a second parse of the directive tokens. |
| `parse_procedure_call`/callee ownership. | After argument/context parsing and the closing-delimiter check, allocate `PROCEDURE_CALL`, assign the incoming node to `procedure_expression`, attach published unsorted arguments/context modification, finish and return the call. | The callee edge owns the base directive under the ordinary call mapping.  This is not the import-owned-call backlink exception, and no receiver/callee resolution is performed. |

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

| Review site. | Admission/copy rule. | Result/review boundary. |
| --- | --- | --- |
| `reusable_expression`/base-kind exclusion. | Under `ENABLE_TRIVIA`, reject null and accept only the guarded identifier, literal, unary, expression-query, type-query, call, cast and binary shapes; unmatched kinds reach the final `false`.  There is no `DIRECTIVE_THIS` acceptance branch. | The bare directive is not admitted by this predicate.  Without trivia the predicate also returns `false`; fresh builder support does not imply reusable-expression support. |
| `reusable_expression`/call admission. | Before checking arguments/context replacements, recursively test `call.procedure_expression` and reject the call if that test fails. | A simple ordinary call whose callee is the base directive is excluded by this gate as well.  Do not bypass the callee check because the outer call kind has a copier case. |
| `copy_reusable_expression`/guarded copy boundary. | The call case recursively copies its callee before rebuilding argument/context storage.  There is no base-directive case; the unsupported-kind default asserts and returns null.  Supported cases then remap token endpoints and coordinates from the new token array. | This is not an opaque-node or raw-base-copy fallback.  Remapping supported nodes does not qualify copying `DIRECTIVE_THIS`, retaining old pointers, or copying pointer-bearing common fields into owned cache results. |

The current predicate/copier pair therefore supplies no approved reusable-expression clone of this base directive or its simple callee-owning call.
This is a conservative exclusion to preserve, not authorisation to add a copy case to complete the registry.
The focused static check compares the guarded kind sets, default rejection/assertion and recursive call-callee dependency.
It does not execute reuse or prove that every caller honours this gate.
The following review covers named enclosing declaration guards and fresh-fallback publication structurally; independent result ownership and recovery qualification remain open.

Declaration reuse and fallback review for the excluded base directive and its ordinary callee-owning call:

| Review site. | Guard/fallback path. | Result/review boundary. |
| --- | --- | --- |
| `reuse_simple_declaration`/candidate kind. | Require an eligible completed old block and a source-position-matched candidate of kind `DECLARATION` or `COMPOUND_DECLARATION`, as well as the later boundary/token checks. | A bare directive or call in the old statement list is not itself an eligible declaration candidate.  Rejection is not confirmed absence from the fresh syntax graph. |
| `reuse_simple_declaration`/initialiser guards. | For scalar and compound declarations with initialisers, require `reusable_expression` on the respective expression before advancing the current token cursor or copying it.  The typed-without-initialiser exception applies only when that expression is null. | A retained `DIRECTIVE_THIS` initialiser, or ordinary call with it as callee, rejects this declaration reuse candidate.  A nonnull initialiser cannot bypass its predicate by being typed. |
| `reuse_simple_declaration`/compound target copies. | Before copying compound targets with reference registration disabled, require every target to be an unmodified, single-token identifier in its expected comma-separated slot. | These direct copier calls are not an alternate route for a base directive or call target.  This guard does not qualify arbitrary compound assignments or semantic binding identity. |
| `reusable_type_instantiation`/type-wrapper dependencies. | The declaration guards require reusable type wrappers when present.  Pointer/array wrappers recursively guard their dependencies; explicit dimensions require `reusable_expression`, and the terminal type-valued expression must be an identifier. | The corresponding type-wrapper copier's dimension and terminal-expression calls are constrained on these reviewed declaration routes.  This does not establish that every other type-wrapper caller has the same admission proof. |
| `parse_file_node` and `parse_block_node`/rejected-candidate fallback. | A null declaration-reuse return leads to `parse_declaration_node` in the file loop or the declaration-block branch.  Append a nonnull fresh result before `finish_statement`, then attach the statement list to the returned block. | A successfully reparsed declaration retains its actual fresh initialiser graph under the existing field-role mapping.  Failed fresh parsing follows the existing diagnostic/synchronisation path, not a fabricated empty declaration or a salvaged old initialiser. |

The reviewed rejection paths precede `parser.cursor += count`; candidate search may still advance `reuse_statement_index` past older source positions.
Do not describe rejection as rollback of every reuse bookkeeping field.
The imperative block branch uses `parse_statement` rather than this declaration-reuse attempt; its simple-call attachment remains the separate route above.
These source checks establish named guard/fallback wiring, not that every matching source text is semantically valid or that an executable edit actually exercises the path.
Recursive helper dependencies and named non-call references are covered by the following local source inventory; source lifetime, old-pool pointer exclusion, recovery attribution and full incremental reuse qualification are not closed by this table.

The local Jai source inventory, including ignored Jai files under this parser module, finds 26 named references to the two copier functions: two definitions and 24 direct calls.
The inventory covers regular source files without following symbolic links.
All calls occur in `reuse_simple_declaration` (five), `copy_reusable_type_instantiation` (four) or `copy_reusable_expression` (15).
No named non-call reference, alias assignment or callback registration appears in that searched source set.
These counts describe source sites, not executions, symbolic-link targets, generated code, external integrations or all possible indirect invocation mechanisms.

| Recursive copy family. | Admission dependency/copy correspondence. | Base-directive boundary. |
| --- | --- | --- |
| Aggregate literal helpers. | Array members and struct arguments must each pass `reusable_expression` before their corresponding copier loops.  Optional array element/struct type expressions must be identifiers; those direct expression-copy calls rebuild type wrappers from copied identifiers. | The helper records do not bypass expression admission for their members, and their identifier-only type edges do not admit `DIRECTIVE_THIS`.  These checks do not qualify all helper fields or old-pool pointer exclusion after whole-record assignment. |
| Unary and expression queries. | Accepted unary operators require their subexpression to pass `reusable_expression`; accepted expression-query kinds require their queried expression to pass it as well as the recorded interval checks.  Each copier rebuilds that same child. | An excluded directive nested on either edge prevents admission of the enclosing expression through this gate. |
| Type queries and casts. | Type-query admission requires `reusable_type_instantiation` for the queried type; cast admission requires it for the target type and `reusable_expression` for the value.  The copier follows those same wrapper/value dependencies. | Wrapper recursion, explicit dimensions and terminal identifier restrictions remain those reviewed above; an enclosing type-query/cast kind is not an escape from them. |
| Call children and labels. | Require reusable callee, argument expressions and context expressions.  An optional argument label must be an identifier; copy it with reference registration disabled, independently of the value's recursive copy. | Directive exclusion applies to values/context as well as callees.  Identifier label copying is not an unguarded expression-value route. |
| Binary operands. | Admitted ordinary operators and array subscripts require both operands to be reusable.  Member access instead requires a reusable left operand and an identifier right operand carrying the RHS-of-dot marker.  The copier rebuilds both operands in either case. | The right-hand identifier restriction supplies the member-access admission proof where no recursive right-operand predicate is called; do not generalise that exception to arbitrary right-hand expressions. |

This closes the named local copy-caller and recursive dependency inventory for the current source, not the overall builder-function reachability registry or executable reuse qualification.
The copier functions rely on admission performed by callers; they do not re-run every predicate before following children.
The focused static check verifies reference classification/counts and the listed predicate/copy correspondences.
It is not a proof against malformed or mutated input graphs, cycles, concurrent mutation, stale pointers, source teardown or future callers that bypass admission.

## Leaf Layout Field Roles: Context, Ident, Note and Placeholder

First field-role slice of the inventory above, using `compiler_fields.md`, the generated overlays and the current builder functions.
These four layouts have no authored downward children; `Code_Literal` is deliberately excluded because its aggregate arms have separate child/helper rules.
The following enumerates layout-specific fields, not a finished scalar/tag wire schema.
Common base fields and generated overlay storage follow the shared rules after the table.

| Parser layout/published kind. | Exact layout-specific field roles and guards. |
| --- | --- |
| `Parser_Context`/`CONTEXT`. | No layout-specific field beyond the structural `base`.  The `KEYWORD_CONTEXT` primary builder function publishes this leaf; do not resolve or expand the current language context as a syntax child. |
| `Parser_Ident`/`IDENT`. | `name`: `NON_CHILD`, exact owned producer bytes, correlated separately to token spelling/backtick state.  `flags`: `NON_CHILD`, only registered source-derived bits in syntax observations.  `resolved_declaration`: `BACKREFERENCE`, never traversed even when the parser has already populated it.  Identifier presence is not by itself an index declaration; enum-member, binding and other construction contexts remain distinct. |
| `Parser_Note`/`NOTE`. | `text`: `NON_CHILD`, owned exact stored bytes.  `note_flags`: `NON_CHILD`, source-derived observations only, not processed/compiler bits.  `parse_declaration_notes` takes token identifier bytes and removes one terminal NUL when present; preserve the original token spelling separately rather than asserting that stored text equals a source slice.  Only notes attached to the published declaration/compound graph are visited. |
| `Parser_Placeholder`/`PLACEHOLDER`. | Parser-added `name`: `NON_CHILD`; this field is not present in the compiler `Code_Placeholder` layout and must not be lost by copying only its embedded compiler overlay.  The declaration route consumes `#placeholder` and expects an identifier.  Qualify name bytes against that actual name token/route, not the node's first token or a zero/default identifier value after recovery.  This leaf is not an ordinary declaration-index entry. |

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
The milestone-2 canonical value section supplies the Ident, Note and common source-flag registries; these field roles do not approve a raw native bitmask encoding or qualify unobserved producer routes.

The focused review vectors are `context`, a backticked identifier, an attached note with producer text distinct from spelling, and `#placeholder` with present versus missing/non-identifier name tokens.
Further qualification must preserve duplicate/equal-span identifier occurrences and reject traversal through deliberately populated `resolved_declaration`/common semantic pointers.
Independently owned name/text bytes must survive producer teardown.
This closes the draft field-role enumeration for these four layouts only.
The subsequent literal-arm rules and milestone-1 crosswalk complete the current draft field/route inventory.
Exact scalar/flag schemas, producer-version drift checks and executable builder/reuse/visitor qualification remain open.

## Operator, Cast and Query Layout Field Roles

Second field-role slice of the inventory: five layouts, using the compiler field inventory and the fresh builder functions in `parse_binary`, `parse_prefix`, `parse_postfix_suffixes` and `parse_primary`.
The structural base/overlay/common-field rules from the leaf slice apply unchanged.
Only the layout-specific fields below add downward edges; scalar tags/flags never imply extra children.

| Parser layout/published kind. | Exact layout-specific field roles and visit order. |
| --- | --- |
| `Parser_Unary_Operator`/`UNARY_OPERATOR`. | `operator_type`: `NON_CHILD`, under the registered operator mapping rather than a native enum ordinal.  `subexpression`: `CHILD`, required on the reviewed published routes and visited once.  Prefix operators, leading-dot shorthand and postfix dereference use this same edge; preserve their distinct operator/source observations. |
| `Parser_Binary_Operator`/`BINARY_OPERATOR`. | `operator_type`: `NON_CHILD`.  `flags`: `NON_CHILD`, registered source-derived bits only.  `left`: `CHILD`, then `right`: `CHILD`.  Ordinary binary, member-access and array-subscript routes retain their operator distinction; do not follow member-resolution/scope bookkeeping as another edge. |
| `Parser_Cast`/`CAST`. | `cast_flags`: `NON_CHILD`, registered source-derived bits only.  `target_type`: `CHILD`, required for explicit casts and inactive/absent for the qualified auto-cast route.  `expression`: `CHILD`, required.  Prefix explicit order is target then expression; postfix explicit order is expression then target; auto-cast visits only expression. |
| `Parser_Expression_Query`/`EXPRESSION_QUERY`. | `query_kind`: `NON_CHILD`, exactly `TYPE_OF`, `IS_CONSTANT` or `CODE_OF` on the reviewed routes.  `expression_to_query`: `CHILD`, required and visited once.  A query node records source syntax, not a computed type/constant/code result. |
| `Parser_Type_Query`/`TYPE_QUERY`. | `query_kind`: `NON_CHILD`, exactly `SIZE_OF`, `TYPE_INFO` or `INITIALIZER_OF` on the reviewed routes.  `type_to_query`: `CHILD`, required and visited once; its parser-created type-instantiation wrapper retains its own node ID and then follows that layout's active-form rules. |

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

## Procedure-Call Layout and Argument Helper Field Roles

Third field-role slice: `Code_Procedure_Call` plus its parser-owned argument/context helpers, grounded in `parse_procedure_call` and the existing qualified import-parameter route.
Shared base/overlay rules apply.
The parser overlays compiler `context_modification` with `*Parser_Context_Modification`; do not decode that storage using the compiler's lowered representation.

| Parser layout/published kind. | Exact layout-specific field roles. |
| --- | --- |
| `Parser_Procedure_Call`/`PROCEDURE_CALL`. | `procedure_expression`: `CHILD` on the ordinary call route; the registered import-parameter route instead treats its owning-import association as a non-owning backreference.  `arguments_unsorted`: `HELPER`, ordered `Parser_Argument` records.  `context_modification`: `HELPER`, optional parser-owned context storage.  `flags`: `NON_CHILD`, registered source-derived bits only.  `resolved_procedure_expression`: `BACKREFERENCE`.  `overloads`: `NON_CHILD`, semantic candidate storage.  `arguments_sorted`: `BACKREFERENCE`, post-resolution argument arrangement, not another authored list.  `num_return_values_received`: `NON_CHILD`, semantic count.  `macro_expansion_block`: `NON_CHILD`, generated syntax excluded from this authored traversal. |

| Parser helper/storage domain. | Exact fields and downward order. |
| --- | --- |
| `Parser_Argument`/non-node helper. | `name`: `CHILD`, optional named-argument identifier, then `expression`: `CHILD`, required for each published argument.  Neither the record itself nor an absent name gets a node ID. |
| `Parser_Context_Modification`/non-node helper. | `modification_expressions`: `CHILD_LIST`, in stored source order.  The helper is not a `Parser_Node` even though the builder function uses `new_parser_node` to allocate it; its expressions have ordinary node IDs. |

Context-helper allocation and copy reachability review:

| Review site. | Allocation/retention path. | Identity/qualification boundary. |
| --- | --- | --- |
| `parse_procedure_call`/fresh context helper. | After consuming `DOUBLE_COMMA`, allocate the helper through `new_parser_node`, collect successful expressions in order, diagnose an empty list, assign the list and later attach the helper to the returned call. | An empty or partially parsed context list can remain published.  Failed expression parsing does not discard the helper or invent an expression to fill it. |
| `copy_reusable_expression`/rebuilt context helper. | If the old call has a helper, allocate a new one with direct `New(Parser_Context_Modification,, parser_node_allocator(parser.parsed))`, recursively copy each expression into a new list, assign that list and attach the new helper to the copied call. | The direct allocation is not a second node-builder route.  The helper pointer and list storage are rebuilt rather than left as the old call's attached helper after the initial whole-call assignment.  This does not qualify every other call field against old-pool pointers. |
| `reusable_expression`/empty-list admission. | For a present call context helper, require each stored expression to be reusable; there is no separate nonempty-list check.  An empty list performs no child checks, while the callee and ordinary argument guards still apply. | This predicate alone does not reject a present empty helper.  The copy branch still runs for its nonnull helper pointer and preserves presence even with zero expressions; do not silently normalise it to absence. |
| `Parser_Context_Modification`/helper identity. | The parser-owned declaration contains only `modification_expressions`, with no node base, kind or token/location fields.  Both allocation paths use the current parsed-source pool. | Only retained expression nodes enter ordinary node traversal and the snapshot-local ID domain.  The helper has no independent node span or diagnostic/recovery field to copy, and must not be decoded through compiler context storage. |

The two reviewed allocation sites preserve the presence/list distinction structurally, not committed recovery provenance.
Neither the recursive expression copy nor the helper allocation proves that diagnostics are rebased, that a recovered call is eligible through every enclosing reuse gate, or that owned syntax can outlive parser pools.
The focused static check compares the one-field helper declaration, fresh/copy attachment, the empty-list admission loop and both literal allocation sites; executable fresh/edit equivalence, diagnostic attribution and teardown qualification remain open.

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
Builder function and ordering qualification remains separate: ordinary/named/context calls, empty recovered context, unattached failed names, import backreferences and populated semantic/generated fields require independent expectations.
This completes draft field-role enumeration for one further generated layout and two helpers, not a public accessor implementation or qualified call visitor.

## Block Layout Field Roles

Field-registry slice grounded in `parse_block_node`, `parse_statement_block` and the parser-created quick/conditional blocks.
Shared base/overlay rules apply.

| Record/storage domain. | Exact field roles. |
| --- | --- |
| `Code_Block`/parser layout input. | `parent`: `BACKREFERENCE`.  `block_type`: `NON_CHILD`, registered grammar-category observation.  `block_flags`: `NON_CHILD`, source-derived bits only.  `belongs_to_struct`: `BACKREFERENCE`.  `statements`: `CHILD_LIST`, published statement order.  `owning_statement`: `BACKREFERENCE`.  `members`: `NON_CHILD`, compiler member/resolution storage, not another source statement list. |

Visit `statements` once; lexical scope bindings and member tables do not supply missing statements or declaration identities.
An empty published list is valid, whereas an unattached failed statement remains described by source/diagnostics rather than an invented node.
The parser's progress/recovery loop can skip input between attached statements.
Preserve that recovery evidence and any established coverage gap without inserting skipped text as an AST statement or claiming there was no syntax there.
Parser-created single-statement, quick-body and conditional blocks retain their own node IDs and qualified origin rules; the absence of authored braces does not make them backlinks or permit deleting the block.
Do not infer authored delimiters from `IS_PARENTHESIZED` or default block flags alone.
The static check covers all seven layout-specific fields.
Exact block-category/flag schemas and executable builder/reuse and statement/alias qualification remain open; the current-source allocation/root crosswalk is closed by milestone 1.

## Declaration Metadata, Using Order and Registry Review Gate

Proposed consolidation of the authored-edge draft, grounded in declaration properties/metadata/notes, `parse_using_statement_after_keyword`, and the base-node `#this` builder function.
This completes another draft slice, not producer review or permission to claim complete traversal.

For exhaustive layout-specific field coverage, the three generated declaration/compound layouts and their structural entry/argument records have these roles.
Shared base/overlay rules apply; embedded scope-entry storage is part of the same node, not a new node occurrence.

| Record/storage domain. | Exact field roles. |
| --- | --- |
| `Code_Declaration`/parser layout input. | `entry`: `HELPER`, embedded scope-entry storage.  `type_inst`: `CHILD`, grammar-qualified optional or recovered required type.  `expression`: `CHILD`, grammar-qualified published initialiser.  `flags`: `NON_CHILD`, registered source bits only.  `alignment_expression`: `CHILD`, only when a qualified metadata route publishes it.  `notes`: `CHILD_LIST`, attached note nodes in stored order.  `program_export_name`: `NON_CHILD`, owned final producer bytes, distinct from correlated occurrence metadata. |
| `Code_Compound_Declaration`/parser layout input. | `entry`: `HELPER`, embedded storage, not one authoritative name for the binding group.  `comma_separated_assignment`: `CHILD`, real structural comma-arguments node.  `declaration_properties`: `HELPER`, parser-node storage with its own snapshot ID but no standalone declaration-index entry.  `alignment_expression`: `CHILD`, compound-owned metadata.  `notes`: `CHILD_LIST`, compound-owned attached notes.  `operator_type`: `NON_CHILD`, qualified producer observation, not a universal binding-route classifier. |
| `Code_Comma_Separated_Arguments`/parser layout input. | `arguments`: `HELPER`, ordered parser-owned compound-argument records.  The containing comma node has its own node ID; individual argument records do not. |
| `Code_Scope_Entry`/embedded structural helper. | `name`: `NON_CHILD`, owned producer bytes when the qualified declaration route supplies them; do not replace a compound's per-binding names with this embedded field.  `import_target`: `BACKREFERENCE`, compiler/import association excluded from authored descent.  Its embedded base follows the shared same-node structural rule. |
| `Code_Comma_Separated_Argument`/parser-owned helper counterpart. | `node`: `CHILD`, authored target occurrence, then `modifier`: `NON_CHILD`, registered per-target declaration/assignment observation, not an instruction to perform binding. |

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

Registry review has the following concrete closure gate.
Items 1-4 govern draft specification closure and are discharged by the milestone-1 crosswalk and explicit limits above; item 5 remains the separate implementation qualification gate:

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
The milestone-1 closure binds these cases to the current producer and explicit partial dispositions, but no visitor, complete-coverage adapter or behavioural acceptance tests are implemented here.
Exact API/schema review remains open.

## Directive Payloads and Registered Backreferences

For exhaustive field-role coverage, the directive layouts below use the shared base/overlay rules.

| Record/storage domain. | Exact field roles. |
| --- | --- |
| `Code_Directive_Add_Context`/parser layout input. | `expression`: `CHILD`, declaration-grammar payload, with qualified recovery handling when the published directive lacks its required payload. |
| `Code_Directive_Overlay`/parser layout input. | `target_expression`: `CHILD`, required parenthesised target, then `declaration_or_using`: `CHILD`, required payload traversed by its actual published kind.  Preserve required-child recovery; do not apply the overlay or resolve its target. |
| `Code_Directive_Modify`/parser layout input. | `block`: `CHILD`, required authored block; retain the missing-opening-brace diagnostic and qualified missing-body observation instead of manufacturing a block. |
| `Code_Directive_Run`/compiler layout input. | `flags`: `NON_CHILD`, registered source/parser bits only.  `assertion_string`: `NON_CHILD`, no populated source-message route on the reviewed builder functions; compiler-generated/evaluated messages are not source observations.  `procedure`: `CHILD` only on the qualified source arrow-header route below; unrelated lowered/compiler procedures remain excluded. |
| `Parser_Directive_Run`/parser-added storage. | `expression`: `CHILD` on ordinary expression/block routes, but a non-owning body-block association on the qualified arrow-header route.  Validate that alias against this header's body identity; never descend twice or infer ownership from nonnull storage alone. |
| `Code_Directive_Insert`/parser layout input. | `expression`: `CHILD`, required published payload, including a qualified implicit-run wrapper for arrow syntax.  `scope_redirection`: `CHILD`, optional source prefix.  `break_replacement`: `CHILD`, optional published replacement statement.  `continue_replacement`: `CHILD`, optional published replacement statement.  `remove_replacement`: `CHILD`, optional published replacement statement.  `expansion`: `NON_CHILD`, generated expansion excluded.  `is_internal`: `NON_CHILD`, internal generated bookkeeping excluded from source observations.  Enumeration order is not visit order: use the prefix/clause/payload ordering and recovery rules below. |
| `Code_Directive_Location`/parser layout input. | `expression`: `CHILD`, optional non-caller argument, with consumed-but-missing argument recovery distinguished from empty parentheses.  `is_caller_location`: `NON_CHILD`, source route discriminator; caller syntax has no expression child. |
| `Code_Directive_Procedure_Name`/parser layout input. | `argument`: `CHILD`, optional parenthesised expression; empty parentheses are legitimate absence, unlike a recovered failed expression. |
| `Code_Directive_Poke_Name`/compiler layout input. | `name`: `NON_CHILD`, owned identifier-value bytes, not an identifier node.  `module_struct`: `NON_CHILD`, compiler interpretation excluded; the parser-owned overlay below is the only source view of this slot. |
| `Parser_Directive_Poke_Name`/parser overlay view. | `module_expression`: `CHILD`, required postfix-expression payload with qualified recovery handling.  This overlays the compiler slot, not an additional allocation or second owning edge; never read the same storage as a resolved struct. |
| `Code_Directive_Module_Parameters`/parser layout input. | `module_parameters`: `CHILD`, optional first source procedure-type header.  `program_parameters`: `CHILD`, optional second header on the consumed first-header route.  `common_code`: `CHILD`, optional trailing or block-only source block.  Visit in that order; empty/block-only forms are legitimate, while consumed-but-recovered headers retain their distinct evidence. |
| `Code_Directive_Context_Type`/parser layout input. | No layout-specific fields; shared `base` only.  This is the authored `#Context` occurrence, not the completed context type or a member list. |
| `Code_Directive_Scope`/parser layout input. | `scope_type`: `NON_CHILD`, source distinction among module/internal, export and file directives.  Apply the existing same-statement-list syntax rules, not inferred effective visibility or semantic scope links. |
| `Code_Directive_Through`/parser layout input. | No layout-specific fields; shared `base` only.  Preserve a published standalone directive occurrence; case-parser consumption into a fallthrough marker does not manufacture another node. |
| `Code_Directive_Wildcard`/parser layout input. | `index`: `NON_CHILD`, unassigned/default on the reviewed source builder function, not an inferred source ordinal or resolved binding index.  The published wildcard has no authored child. |
| `Code_Directive_Import`/parser layout input. | `name`: `NON_CHILD`, owned decoded source bytes, including a qualified transient `#string` value.  `flags`: `NON_CHILD`, registered source bits only.  `module_parameters_call`: `CHILD`, optional first parameter call.  `program_parameters_call`: `CHILD`, optional second parameter call.  `import_type`: `NON_CHILD`, qualified source modifier observation where assigned by this parser, not permission to import or infer a resolved kind. |
| `Code_Directive_Load`/parser layout input. | `short_name`: `NON_CHILD`, owned source string-token value.  `load_flags`: `NON_CHILD`, registered source observations only; the reviewed builder function leaves them at their defaults.  `fully_pathed_filename`: `NON_CHILD`, resolved external path excluded.  `loaded_string`: `NON_CHILD`, externally loaded content excluded. |
| `Code_Directive_Library`/parser layout input. | `name`: `NON_CHILD`, owned source string-token value.  `library_flags`: `NON_CHILD`, registered source bits only, never resolved/linker state. |
| `Code_Directive_Bytes`/parser layout input. | `expression`: `CHILD`, published binary-expression-grammar payload, with required-child recovery handling. |
| `Code_Directive_Exists`/parser layout input. | `query_expression`: `CHILD`, required query expression.  `sync_expression`: `CHILD`, optional comma-introduced expression, required or recovered once that separator is consumed. |
| `Code_Directive_Bake`/parser layout input. | `procedure_call`: `CHILD`, only the published call accepted by the bake builder function.  `bake_type`: `NON_CHILD`, source distinction between dynamic specialisation, constants bake and parameter-value bake requests. |
| `Code_Directive_Code`/parser layout input. | `expression`: `CHILD`, ordinary/typed payload only; inactive on qualified null/caller routes.  `code_flags`: `NON_CHILD`, registered source observations, excluding processed/compiler state. |

The context slice enumerates one layout-specific field across two layouts.
Traverse the published add-context payload under the current authored container; do not merge contributions, resolve context membership or follow a computed type.
Preserve the directive and its recovery evidence when payload parsing fails, rather than inventing an empty declaration.
Exact schema tags and independent executable builder/reuse qualification remain open.

The bake/code slice enumerates four layout-specific fields across two layouts.
Keep the distinction between a rejected non-call bake payload and a published call with its own recovery.
Do not rediscover a rejected expression in parser pools.
Code payloads retain their actual block/declaration/expression kind; legitimate null/caller absence is not a recovered required hole, and a missing ordinary/typed payload is not a null-code request.
The exact source flag/tag encodings and executable builder/reuse and route qualification remain open.

The bytes slice enumerates its one layout-specific field.
Preserve the actual published expression and any required-payload recovery; do not evaluate it, materialise a byte sequence or infer a missing literal from the directive name.
The directive and child keep distinct node IDs even when recovery makes their source intervals overlap.
Independent executable builder/reuse qualification remains open.

The exists slice enumerates two layout-specific fields, visited query then sync.
Parenthesis/comma and diagnostic correlation distinguish a missing required query, legitimate no-sync absence and a recovered missing sync expression; null fields alone do not establish these forms.
Preserve both published subtrees without executing the query, blocking for synchronisation or asserting semantic existence/absence.
Executable builder/reuse and recovery/ordering qualification remain open.

The import/load/library slice enumerates 11 layout-specific fields across three layouts.
Import calls are visited module then program, with each call's import-callee association qualified by the identity rule below; missing/empty call arguments use ordinary call recovery rather than a fabricated imported document.
Import `file`/`dir`/`string` modifiers can set `import_type` directly on this source parser route, despite that field's general compiler-phase inventory category.
Preserve this qualified observation without reading unrelated resolved state.
Names require owned-byte and source-token correlation: an empty decoded name is not proof of a missing string token.
Consumed modifier order/repetition is not reconstructed from final flags; in particular, the reviewed library builder function accepts `link_always` but leaves `LINK_ALWAYS` clear.
Do not load content, canonicalise a requested path into a resolved result or link a library during syntax traversal.
Exact scalar/flag schemas and executable builder/reuse and alias/lifetime qualification remain open.

Proposed refinement of `jai-cache-authored-edges/1`, grounded in `parse_declaration_directive` and `parse_expression_directive`.
Directive nodes describe authored requests, not their execution, imports, evaluated values or generated expansions.
Register the route-specific exceptions below before applying generic call/header traversal.

| Directive/guarded route. | Active child order and observations. |
| --- | --- |
| `Directive_Add_Context`, `Directive_Bytes`. | `expression`; add-context uses declaration grammar, bytes uses expression grammar.  Index authored declarations reached there without completing or modifying the language context. |
| `Directive_Overlay`. | `target_expression`, then `declaration_or_using`.  The latter follows its actual node kind; do not resolve the target or apply an overlay. |
| `Directive_Modify`. | `block`; retain missing-block recovery rather than creating an empty authored block. |
| `Directive_Module_Parameters`. | Optional `module_parameters`, optional `program_parameters`, optional `common_code`, in that order.  Empty/block-only forms are actual builder function routes, not necessarily recovery. |
| `Directive_Import`. | Optional `module_parameters_call`, then optional `program_parameters_call`; apply the import-callee association rule below.  `name`, import-kind/modifier flags and decoded source text are scalar observations, not child nodes or filesystem membership. |
| `Directive_Load`, `Directive_Library`. | No authored node children on reviewed routes.  `short_name`/`name` are string token values; library flags are scalar.  Loaded strings, resolved paths and linked libraries are not descent targets. |
| `Directive_Poke_Name`. | Parser-preserved `module_expression`; `name` is scalar identifier bytes, not a `Parser_Ident` child.  Do not follow the compiler-facing `module_struct` interpretation of the overlaid field. |
| `Directive_Procedure_Name`, `Directive_Exists`. | Optional `argument`; `query_expression` then optional `sync_expression`, respectively.  Correlate consumed delimiters to distinguish valid absent arguments from recovered missing expressions. |
| `Directive_Location`. | `expression` only when published by the non-caller route; `#location()` can be empty and `#caller_location` has no expression.  The scalar caller flag does not resolve a location. |
| `Directive_Code`. | `expression` on the ordinary/typed route; no payload on the qualified `#code,null` or `#caller_code` route.  Preserve source flags and the actual block/declaration/expression payload kind without expansion. |
| `Directive_Run`, ordinary expression/block route. | Parser-added `expression`; do not follow an unrelated compiler-lowered/evaluated `procedure`.  Assertion messages and execution flags, where produced, remain scalar observations. |
| `Directive_Run`, qualified arrow-header route. | Source `procedure` header, then its ordinary header/body/block ownership; `expression` is a non-owning alias to `procedure.body_or_null.block` when that body exists.  Do not visit that block twice or omit source return/header syntax. |
| `Directive_Insert`. | Optional `scope_redirection`, then published break/continue/remove replacement statements in authored clause order, then `expression`.  Arrow payloads use the parser-created implicit-run wrapper and its arrow-header rule; never follow generated `expansion`. |
| `Directive_Bake`. | Published `procedure_call` only, retaining `bake_type`.  A parsed non-call rejected by this builder function is not an attached child to rediscover. |
| `Directive_Scope`, `Directive_Through`, `Directive_Wildcard`, `Directive_Context_Type`. | No authored node children on these routes; retain scalar/source observations.  Source forms lowered to literals follow the literal registry instead of fabricated directive children. |

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

## Call Arguments, Operators and Cast Source Order

Proposed refinement of `jai-cache-authored-edges/1`, grounded in `parse_binary`, `parse_prefix`, `parse_postfix_suffixes` and `parse_procedure_call`.
Traverse the published parse shape, not a reconstructed precedence tree, inferred evaluation order or resolved call signature.

| Form/guard. | Active child order and observations. |
| --- | --- |
| `Procedure_Call`. | `procedure_expression`, then `arguments_unsorted[]` in stored order, then the optional `context_modification` helper's `modification_expressions[]` in stored order.  Context expressions follow the consumed `,,` boundary, not a merged or sorted argument list. |
| `Parser_Argument` in a call. | Optional `name`, then `expression`.  The name is a source `Parser_Ident` for the consumed `IDENT =` label; it is not a declaration, assignment target or resolved formal-parameter reference. |
| `Unary_Operator`. | `subexpression`, preserving the source operator observation.  Prefix and postfix dereference remain their actual producer operator tags; do not derive a synthetic binary child from their punctuation. |
| `Binary_Operator`. | `left`, then `right`, including member access, subscripting and assignment expressions.  The right child may be a mapped recovered hole; do not turn the left subtree into a different expression merely because recovery failed on the right. |
| Prefix explicit cast. | `target_type`, then `expression`, as constructed by the `cast(...)` route; retain its source cast flags. |
| Postfix explicit cast. | `expression`, then `target_type` when `HAS_POSTFIX_SYNTAX` identifies the reviewed `value.(T)` route.  This reverses the prefix cast's order and therefore affects first-encounter node IDs. |
| Auto cast. | `expression` only on the `IS_AUTO` route; absent `target_type` is intentional, not a missing explicit type. |

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

## Control-Flow Forms, Prefix Expressions and Branch Blocks

Proposed refinement of `jai-cache-authored-edges/1`, grounded in the conditional/case, while/for, statement-block, defer and push-context builder functions.
For exhaustive field-role coverage, the conditional/loop layouts have the following rows.
Shared base/overlay rules apply; route-dependent order and optional-versus-recovered absence follow the form table below.

| Record/storage domain. | Exact field roles. |
| --- | --- |
| `Code_If`/parser layout input. | `condition`: `CHILD`, required condition with recovery evidence.  `then_block`: `CHILD`, branch or switch-case block.  `else_block`: `CHILD`, route-qualified optional/required branch.  `if_flags`: `NON_CHILD`, registered source/parser bits.  `static_if_flags`: `NON_CHILD`, registered source observations only, not evaluation state.  `static_if_accepted_case`: `NON_CHILD`, evaluated selection excluded from authored traversal. |
| `Code_Case`/parser layout input. | `condition`: `CHILD`, absent for a qualified default case or a recovered condition under distinct evidence.  `then_block`: `CHILD`, published case-body block.  `owning_if`: `BACKREFERENCE`.  `marked_as_fallthrough`: `NON_CHILD`, consumed source marker observation. |
| `Code_While`/parser layout input. | `condition`: `CHILD`, then `block`: `CHILD`, with required-child recovery handling. |
| `Code_For`/parser layout input. | `iteration_expression`: `CHILD`, required collection/range start.  `iteration_expression_right`: `CHILD`, consumed range-end route only.  `block`: `CHILD`, body.  `ident_it`: `CHILD`, optional explicit iterator occurrence.  `ident_it_index`: `CHILD`, optional explicit index occurrence.  `want_replacement_for_expansion`: `CHILD`, optional authored expansion request.  `want_pointer_expression`: `CHILD`, qualified dynamic prefix.  `want_reverse_expression`: `CHILD`, qualified dynamic prefix.  `for_flags`: `NON_CHILD`, registered source bits.  `ident_decl`: `NON_CHILD`, generated iterator declaration.  `index_decl`: `NON_CHILD`, generated index declaration.  `macro_expansion_procedure_call`: `NON_CHILD`, generated expansion storage. |
| `Code_Loop_Control`/parser layout input. | `control_type`: `NON_CHILD`, source `BREAK`, `CONTINUE` or `REMOVE` distinction.  `target_ident`: `CHILD`, optional authored target reference, never a resolved loop/declaration edge. |

The static check covers all 26 layout-specific fields across these five layouts.
Table order does not replace the source-form traversal sequence, and source marker/flag observations do not authorise branch evaluation or loop expansion.
Exact scalar/flag schemas, actual duplicate-prefix correlation and executable builder/reuse qualification remain open under the specified partial-observation rules.

The remaining statement-layout slice makes return/defer/push-context/using fields explicit under the same shared rules.

| Record/storage domain. | Exact field roles. |
| --- | --- |
| `Code_Return`/parser layout input. | `arguments_unsorted`: `HELPER`, ordered `Parser_Argument` records using the earlier helper mapping.  `return_flags`: `NON_CHILD`, registered source/parser bits including qualified quick-body normalisation.  `arguments_sorted`: `BACKREFERENCE`, post-resolution arrangement excluded from authored descent. |
| `Code_Defer`/parser layout input. | `block`: `CHILD`, published deferred statement block with required-child recovery handling.  `is_backticked`: `NON_CHILD`, source keyword observation. |
| `Code_Push_Context`/parser layout input. | `to_push`: `CHILD`, qualified optional source expression.  `block`: `CHILD`, non-`DEFER_POP` body route only.  `push_context_flags`: `NON_CHILD`, registered source bits; do not apply the requested context change. |
| `Code_Using`/parser layout input. | `expression`: `CHILD` on the ordinary using route, but a non-owning argument association on the qualified parameter-using route.  `filter_type`: `NON_CHILD`, registered source filter observation.  `filter_expression`: `CHILD`, qualified optional or recovered filter, visited before the ordinary target.  `no_parameters`: `NON_CHILD`, producer scalar observation under its qualified route, not evidence of resolved membership. |

The reviewed return builder function appends only completed expression records, with no argument-name nodes; a populated name requires a qualified additional route rather than inference from shared helper storage.
Empty returns and the existing quick-body recovered return-argument list remain distinct source/normalisation observations.
For using parameters, the header's owning argument list supplies the target's sole descent; ordinary `Using.expression` remains owning.
The lexical scope's using registry is not a second traversal path.
The static check covers all 12 layout-specific fields in these four rows.
Optionality, `DEFER_POP`, consumed-but-missing filters/targets and helper lifetime checks follow the existing route contracts, not tests of whether any pointer happens to be nonnull.
Exact scalar/flag schemas and independent behavioural qualification remain open for this statement slice too.

The ordering below is authored traversal order, not execution order or evidence of an active compile-time branch.
Conditions can themselves be declarations through `parse_condition`; do not restrict them to expression-only leaf forms.

| Form/guarded route. | Active child order and observations. |
| --- | --- |
| Ordinary `If` and static `#if`. | `condition`, `then_block`, optional `else_block`.  Traverse both published branches; preserve `IS_STATIC` without evaluating conditions or following `static_if_accepted_case`. |
| `ifx` and static `#ifx`. | `condition`, `then_block`, `else_block` when published.  Preserve `IS_IFX`/`IS_STATIC`; expression branches may be wrapped in blocks by `parse_ifx_branch`.  A missing branch must retain grammar/recovery observations rather than become an empty fabricated expression. |
| Switch-form `If`. | `condition`, then `then_block.statements[]` case nodes in stored order, reached through the block's normal ownership.  `IS_SWITCH_STATEMENT` selects this route; do not infer a switch from an equality expression alone. |
| `Case`. | Optional `condition`, then `then_block`; `owning_if` is a backreference.  A consumed `case ;` is the default-case route with no condition, not necessarily recovery.  Distinguish a failed nonempty condition parse using boundary/diagnostic correlation. |
| `While`. | `condition`, then `block`.  Declaration-shaped conditions use their ordinary declaration mapping; no new loop container is invented. |
| `For` prefix expressions. | Visit published `want_reverse_expression` and `want_pointer_expression` in their actual token order, not a fixed field order; fallback for equal/unlocated positions is reverse then pointer, with partial ordering coverage if the authored order cannot be established.  Scalar `REVERSE`/`POINTER` flags alone have no child. |
| Remaining `For` fields. | After prefix expressions: optional `want_replacement_for_expansion`, optional explicit `ident_it`, optional explicit `ident_it_index`, required `iteration_expression`, optional range `iteration_expression_right`, then `block`.  A consumed range separator with a recovered missing right expression is distinct from no range. |
| `Defer`. | `block`; retain scalar backtick observation.  Body traversal is syntactic, not delayed execution or effect analysis. |
| `Push_Context`. | Optional `to_push`, then `block` on the non-`DEFER_POP` route.  The builder function omits the block for `DEFER_POP`; that absence is not automatically a missing-body error.  A leading block can also legitimately omit `to_push`. |
| `Loop_Control`. | Optional `target_ident` is an authored reference, not a declaration or a resolved loop edge.  Preserve `control_type` without computing control-flow targets. |

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

## Struct and Enum Ownership and Member Context

Proposed refinement of `jai-cache-authored-edges/1` and the declaration-index/2 draft, grounded in `parse_aggregate_definition`, `parse_aggregate_parameter_block`, `parse_aggregate_block`, `parse_struct_modifiers` and enum-mode statement parsing.
The exhaustive layout-specific field rows below use shared base/overlay rules and the source-order/recovery guards that follow.

| Record/storage domain. | Exact field roles. |
| --- | --- |
| `Code_Struct`/parser layout input. | `modify_directives`: `CHILD_LIST`, authored modifier directives.  `block`: `CHILD`, required body with qualified recovery handling.  `arguments_block`: `CHILD`, optional parameter block.  `notes`: `CHILD_LIST`, only under a qualified attachment route; reviewed builder functions leave it empty.  `textual_flags`: `NON_CHILD`, registered source bits.  `alignment`: `NON_CHILD`, source numeric observation on the reviewed route, not an expression child or computed layout result.  `defined_type`: `NON_CHILD`, resolved type storage.  `constants_block`: `NON_CHILD`, compiler-prepared storage. |
| `Code_Enum`/parser layout input. | `internal_type_inst`: `CHILD`, optional source type wrapper.  `block`: `CHILD`, required member body with qualified recovery handling.  `notes`: `CHILD_LIST`, only under a qualified attachment route.  `marked_as_complete`: `NON_CHILD`, source marker observation.  `marked_as_specified`: `NON_CHILD`, source marker observation.  `is_flags`: `NON_CHILD`, source keyword distinction.  `internal_type`: `NON_CHILD`, resolved type.  `external_type`: `NON_CHILD`, resolved type. |

Field-table order is not traversal order: struct parameters precede modifier directives and body; enum source type precedes body.
Unexpected attached notes need their own ordering/ownership route, not default placement inferred from a populated pointer.
The static check covers all 16 layout-specific fields.
Source-flag schemas, actual repeated-modifier correlation and executable builder/reuse and member/alias qualification remain open under the specified partial-observation rules.

Struct/union and enum nodes are authored type expressions, not automatically extra named declaration entries or nominal type identities.
Members inherit the enclosing declaration/shared-region index container already established by traversal; do not create a container from a resolved type or invent an anonymous binding merely because an aggregate expression has a body.

| Producer route. | Downward order and retained observations. |
| --- | --- |
| Struct or union. | Optional `arguments_block`, `modify_directives[]` in order, then `block`.  `textual_flags.UNION` distinguishes the union spelling on the same `STRUCT` node shape; it does not select a different child arm. |
| Aggregate parameter block. | `statements[]` in stored order.  This is a parser block with `STRUCT_ARGUMENTS` and a parenthesised source interval, not evidence of authored braces.  Parameters are parsed through declaration grammar; do not assume every reached node is an ordinary declaration. |
| Struct/union body block. | `statements[]` in stored order, including declarations, using/directive forms, conditional declarations and field-default expressions.  `block.belongs_to_struct` is a backreference, never a descent to the aggregate. |
| Enum or enum-flags. | Optional `internal_type_inst`, then `block`.  `is_flags`, `marked_as_complete` and `marked_as_specified` are scalar source observations, not child nodes or completed semantic membership. |
| Enum body/enum-mode branch block. | `statements[]` in stored order.  Recognise bare member occurrences only under the enum-member grammar route; conditional branch blocks preserve that route without evaluating the condition. |

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

## Procedure Ownership, Parameter Aliases and Quick Bodies

Proposed refinement of `jai-cache-authored-edges/1`, grounded in `parse_procedure_type_header`, `parse_arrow_procedure_header`, `parse_procedure_flags`, `parse_procedure_body` and the single-identifier quick-lambda builder function.
For exhaustive field-role coverage, the two generated procedure layouts have the following fields, with shared base/overlay rules unchanged.

| Record/storage domain. | Exact field roles. |
| --- | --- |
| `Code_Procedure_Header`/parser layout input. | `arguments`: `CHILD_LIST`, owning parameter declarations.  `returns`: `CHILD_LIST`, owning return slots.  `parameter_usings`: `CHILD_LIST`, owning using wrappers whose target association follows the guarded alias rule below.  `foreign_function_name`: `NON_CHILD`, owned decoded bytes.  `library_identifier`: `CHILD`, optional source identifier.  `deprecation_string`: `NON_CHILD`, owned decoded bytes.  `modify_directives`: `CHILD_LIST`, source order.  `body_or_null`: `CHILD`, optional published body.  `procedure_flags`: `NON_CHILD`, registered source/parser observations only.  `notes`: `CHILD_LIST`, only with a qualified attachment route; current reviewed builder functions leave it empty.  `name`: `NON_CHILD`, owner-derived compiler/parser value, not a separate authored procedure name.  `constants_block`: `NON_CHILD`, compiler-prepared storage.  `polymorph_source_header`: `BACKREFERENCE`, compiler instantiation provenance excluded from source descent. |
| `Code_Procedure_Body`/parser layout input. | `block`: `CHILD`, published body block.  `header`: `BACKREFERENCE`, owning header association.  `body_flags`: `NON_CHILD`, registered source/parser observations only. |

These rows enumerate fields, not their unconditional concatenation: parameter-using interleaving and suffix/body order remain the qualified sequence below.
Unexpected notes or alias associations require the established mapping outcome, not an extra descent or silent omission.
The static field check covers all 16 layout-specific fields.
Exact flag domains, actual suffix-occurrence correlation and independent executable builder/reuse qualification remain open under the specified partial-observation rules.

Header/body/block nodes retain their producer identities and observations; procedure syntax does not itself create an extra declaration-index entry or a semantic scope container.
Named parameters/returns and declarations reached in a body use the nearest enclosing declaration/shared-region container already established by authored traversal.
Do not manufacture a named procedure entry from `Procedure_Header.name`, which may be copied from its enclosing declaration.

| Producer path. | Ownership and order. |
| --- | --- |
| Header parameter lists. | Traverse `arguments[]` in stored parameter order, interleaving each matched `parameter_usings[]` wrapper and its filter immediately before that argument.  The argument declaration is owned and descended through `arguments[]` exactly once. |
| Parameter `Using.expression` | Registered non-owning alias to its matching argument, not a second descent.  Visit the `Using` node and its `filter_expression`, retain the expression association, then visit the owning argument.  Resolve the alias ID after the argument is assigned its node ID; the association does not change first downward-encounter ID assignment. |
| Header return list. | After parameters, traverse `returns[]` in stored order.  Named returns and unnamed type-only slots keep their actual parser records; no inferred return declarations are added. |
| Header suffix/body. | Traverse the optional `library_identifier`, then `modify_directives[]` in order, then optional `body_or_null`.  String-valued foreign/deprecation metadata is not a child.  Source positions still order any independently authored suffix observations; repeated flag occurrences require separate correlation, not inference from the final fields. |
| `Procedure_Body` | Owns `block`.  `header` is a backreference; `block.owning_statement` points back to this body and is not a descent edge. |
| Type-only/header-only forms. | A null `body_or_null` is valid; do not follow an unattached allocated body or create an empty block.  `TYPE_ONLY` and other source/derived parser flags remain observations, not proof of semantic validity. |
| Expression-bodied quick form. | Header -> body -> parser-created block -> parser-created return -> `arguments_unsorted[].expression`.  Follow only these published downward edges; preserve `AUTO_INSERTED_FOR_QUICK_LAMBDA` and the header's `QUICK` observation. |
| Braced quick form. | Header -> body -> authored block statements; preserve `QUICK_IN_BLOCK_FORM`.  Do not add another implicit return around the block. |

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

## Literal Arms and Parser-Created Containers

Proposed refinement of `jai-cache-authored-edges/1`, grounded in `parse_aggregate_literal`, `parse_primary`, `parse_using_filter` and the `char`/`filepath` directive cases.
For exhaustive field-role coverage, the layout and its value/helper storage are enumerated below.
Common base/overlay rules apply; helper/union storage does not introduce additional node IDs.

| Record/storage domain. | Exact field roles. |
| --- | --- |
| `Code_Literal`/parser layout input. | `value_type`: `NON_CHILD`, active-arm tag under the registered mapping.  `values`: `HELPER`, selected anonymous-union storage, not an unconditional list of values.  `value_flags`: `NON_CHILD`, reviewed source literal bits, never the lexer flag domain. |
| `Code_Literal.values`/active union. | `_string`: `NON_CHILD`, owned active string bytes.  `_float64`: `NON_CHILD`, active floating-point bits.  `_s64`: `NON_CHILD`, signed storage view, not a second numeric value to read alongside the selected producer arm.  `_u64`: `NON_CHILD`, active integer/boolean observations under the route rules below.  `struct_literal_info`: `HELPER`, active struct payload only.  `array_literal_info`: `HELPER`, active array payload only.  `pointer_literal_info`: `HELPER`, qualified source-null payload only.  `type_info_literal_defn`: `NON_CHILD`, unsupported evaluated/type-definition payload, not authored descent. |
| `Code_Struct_Literal_Info`/parser-owned helper counterpart. | `type_expression`: `CHILD`, optional typed-prefix wrapper, then `arguments`: `CHILD_LIST`, authored member-expression order. |
| `Code_Array_Literal_Info`/parser-owned helper counterpart. | `element_type`: `CHILD`, optional qualified typed-prefix wrapper.  `alignment`: `CHILD`, only with a separately registered source route; inactive on the reviewed aggregate/name-list builder functions.  `array_members`: `CHILD_LIST`, authored member/name-list order.  `array_literal_flags`: `NON_CHILD`, registered source bits. |
| `Code_Pointer_Literal_Info`/qualified source-null helper. | `global_symbol`: `NON_CHILD`.  `string_or_array_literal`: `NON_CHILD`.  `data_pointer`: `NON_CHILD`.  `pointer_literal_type`: `NON_CHILD`, qualified discriminator observation.  `offset_from_symbol`: `NON_CHILD`.  None supplies an authored node edge or permission to encode a process address. |

Compiler names identify the layout inputs; the aggregate helper fields are accessed through their parser-owned counterparts, not by assuming the compiler's mutable representation is an owned payload.
The pointer helper has overlapping symbol/string storage: its field-role enumeration is not permission to read inactive arms.
Preserve only safely qualified source-null observations under the existing literal rules; an unqualified address or evaluated payload requires the established unsupported/mapping outcome, not raw pointer serialisation.
The static field check covers each of these five inventory rows, counting phase-duplicate fields once and excluding shared `base`.
This closes draft field-role enumeration for one generated layout and the listed helper/union storage; exact scalar/flag schemas and independent behavioural qualification remain open.

Select the literal union arm using `value_type`, with the reviewed source-value flags and construction route where needed.
Never read a second arm to discover children or encode inactive union bytes.
The literal-value flag domain is not the lexer's `Value_Flags` domain; the token flag mask specified elsewhere must not be applied to AST literal flags.

| Literal arm/reviewed route. | Downward paths and retained observations. |
| --- | --- |
| `NUMBER`. | No child; retain the active `_float64` bits when the literal `FLOAT` flag is set, otherwise `_u64` bits, plus reviewed source flags.  This includes parser-produced `#char` values, not only numeric tokens. |
| `BOOLEAN`. | No child; retain the parser's `_u64` observation for the authored `true`/`false` token, without treating the union as a pointer. |
| `STRING`. | No child; retain `_string` bytes and source flags.  Routes include quoted/here strings, `#filepath`, and parser-created using-filter names; do not require every string value to equal its full source slice. |
| `UNINITIALIZED`. | No child; retain the `---` occurrence.  Declaration parsing can instead set `IS_UNINITIALIZED` and clear the expression; do not reconstruct a missing literal node in that declaration. |
| `STRUCT` from `parse_aggregate_literal`. | `struct_literal_info` is helper storage: optional `type_expression`, then `arguments[]` in authored order.  A typed prefix is wrapped with `make_type_instantiation`; an untyped literal legitimately has no type wrapper. |
| `ARRAY` from `parse_aggregate_literal`. | `array_literal_info` is helper storage: optional `element_type`, then `array_members[]` in authored order.  The untyped route sets `WAS_UNTYPED`; typed prefixes are wrapped rather than resolved. |
| `ARRAY` from a parenthesised `using,only` or `using,except` name list. | Helper `array_members[]` contains parser-created `STRING` literals in name-list order.  There is no element-type wrapper and this builder function does not set `WAS_UNTYPED`; the source is a name list, not `.[...]`. |
| `POINTER` from the authored `null` route. | No authored child.  Preserve the qualified null observation: this builder function allocates `Code_Pointer_Literal_Info` with `pointer_literal_type == CONSTANT_VALUE`.  Do not follow its symbol/data/string-or-array pointer fields as syntax edges. |

The source-null allocation review distinguishes generic pool allocation from node construction:

| Review site. | Allocation/attachment rule. | Identity/review boundary. |
| --- | --- | --- |
| `new_parser_node`/generic allocation. | Allocate the requested `T` with `New(T,, parser_node_allocator(parser.parsed))`; the two type-specific adjustments concern wildcard indices and struct alignment.  The function body does not require or initialise common node fields for every `T`. | The function name does not make every result a `Parser_Node`, establish a kind, or grant a snapshot-local node ID.  Classify the actual record and its owning route. |
| `parse_primary`/source-null helper attachment. | The `KEYWORD_NULL` branch consumes the token, allocates `Code_Pointer_Literal_Info`, sets its discriminator to `CONSTANT_VALUE`, then allocates a separate `Parser_Literal`, sets `LITERAL`/`POINTER`, attaches the helper and finishes/returns the literal. | The returned literal is the syntax node; the pointer helper remains non-node storage under its active literal arm.  This is one reviewed explicit helper allocation site in `parser.jai`, not proof of an exhaustive generic type/route universe. |
| `Code_Pointer_Literal_Info`/non-node layout. | The installed declaration has the five already-inventoried fields, including overlapping symbol/literal pointer storage, and no embedded `Code_Node` or `Parser_Node` base. | Do not cast it to a node, read node token/location fields from it, or traverse its pointer-valued fields as authored children.  Reuse the existing field-role inventory rather than introducing a new generated layout or helper node ID. |
| `reusable_expression`/pointer-literal exclusion. | After the separately guarded array/struct literal cases, admit only the reviewed number, boolean and qualified string literals.  A `POINTER` literal does not satisfy that final literal whitelist. | The source-null helper route is not admitted for copying through this predicate.  The copier's general literal case is not an independent admission rule or proof that a helper pointer can be retained safely. |

The focused static check verifies generic allocation shape, the source-null allocation/attachment sequence, the helper's existing declared-field inventory and literal reuse exclusion.
It does not execute allocator defaults or inspect inactive union storage, prove all possible generic instantiations, or qualify helper lifetime after source teardown.
A qualified source-null observation remains distinct from accepting arbitrary `CONSTANT_VALUE` addresses or other pointer discriminator variants.

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
The milestone-2 closure supplies AST flag/value payload schemas; executable producer mapping and traversal qualification remain open.

## Type Instantiation Source-Form Guards

Proposed refinement of `jai-cache-authored-edges/1`, grounded in `parse_type_instantiation` and `make_type_instantiation`.
For exhaustive field-registry closure, this layout has the following eight layout-specific fields; shared structural base/overlay rules apply as in the earlier slices.

| Parser layout/published kind. | Exact layout-specific field roles. |
| --- | --- |
| `Parser_Type_Instantiation`/`TYPE_INSTANTIATION`. | `type_valued_expression`: `CHILD`, active for expression/polymorphic/procedure wrappers.  `must_implement`: `CHILD`, active only for a qualified consumed polymorphic constraint suffix.  `pointer_to`: `CHILD`, pointer form only.  `type_directive_target`: `CHILD`, type-directive form only.  `array_element_type`: `CHILD`, array/view/resizable/varargs forms only.  `array_dimension`: `CHILD`, fixed-dimension array form only.  `inst_flags`: `NON_CHILD`, registered source-derived observations.  `result`: `NON_CHILD`, inferred/compiler type storage excluded from syntax descent. |

The row enumerates possible fields, not one unconditional visit sequence.
Select the active subset and order from the source-form table below; do not visit all six child slots merely because they share this layout.
Missing required children on a published recovered route retain their qualified recovery holes.
A wrapper that was never published is not a missing-node placeholder in the syntax graph.
The focused static field check compares this row with `Code_Type_Instantiation` in the compiler field inventory, excluding shared `base`, and rejects missing/duplicate fields.
Exact source-flag encoding and executable builder/reuse and route qualification remain open despite completed draft field/route enumeration for this layout.

The producer has no separate source-form discriminant: the labels below are registry rules, not new producer enum values or a final payload wire union.
Select a rule from a qualified construction/source observation bound to the owned token interval, then validate its source flags and fields together.
Do not choose the first nonnull child or equate a missing recovered child with a different grammar form.
Preserve raw producer `inst_flags` separately; only reviewed source bits participate in these guards, never inferred `result` or common node `type`.

| Source form/required observation. | Active child order and source flags. |
| --- | --- |
| Varargs `..T`. | `array_element_type`; `VARARGS` and `ARRAY_VIEW` are both set.  This is not a dimensionless array-view spelling. |
| Polymorphic `$T` with optional `/ [interface] constraint`. | `type_valued_expression`, then `must_implement` only for a consumed constraint suffix.  The expression is the parser-created identifier marked `DEFINES_POLYMORPH_VARIABLE`; `INTERFACE` records the consumed `interface` keyword, not completion of constraint resolution. |
| `#type` with optional `,distinct` or `,isa`. | `type_directive_target`; `TYPE_DIRECTIVE`, optionally `TYPE_DIRECTIVE_DISTINCT` or `TYPE_DIRECTIVE_ISA`.  Modifier tokens and recovery remain source observations; an unknown modifier is not silently normalised to an accepted one. |
| Pointer `*T`. | `pointer_to`; no array, directive or procedure source-form flag is implied. |
| Array view `[]T`. | `array_element_type`; `ARRAY_VIEW`, without `VARARGS`.  `array_dimension` is inactive. |
| Resizable array `[..]T`. | `array_element_type`; `RESIZABLE`.  `array_dimension` is inactive. |
| Fixed-dimension array `[expression]T`. | `array_dimension`, then `array_element_type`, including expressions that contain directives or are not semantically valid dimensions.  Neither `ARRAY_VIEW` nor `RESIZABLE` is implied. |
| Procedure type beginning `(` on this parse route. | `type_valued_expression`, the parsed `Procedure_Header`; `TYPE_OF_PROCEDURE` on the wrapper and `TYPE_ONLY` on the header.  Traverse authored parameters/returns under the header rules, not its lexical scope bindings. |
| General type-valued expression wrapper. | `type_valued_expression` from `make_type_instantiation`; no wrapper-specific source-form flag is added there.  This includes postfix member/call expressions and contextual aggregate-type wrappers, not only identifiers. |

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

## Assembly Helper Guards and Traversal Order

Proposed refinement of `jai-cache-authored-edges/1`, grounded in the parser's `parse_asm_instruction_span`, `add_asm_operand` and `parse_asm_*_span` builder functions.
These auxiliary records are `HELPER` storage, not additional `Parser_Node` occurrences; only their identifier/expression fields enter the ordinary node traversal and node-ID domain.
Preserve helper kinds, spans, list order and scalar observations in the protected syntax snapshot; do not reinterpret their memory as compiler `Code_Asm` payloads.

For exhaustive generated-layout field coverage, shared base/overlay rules apply to the compiler storage, while the parser generator adds separate owned syntax fields.

| Record/storage domain. | Exact field roles. |
| --- | --- |
| `Code_Asm`/compiler layout input. | `b1`: `NON_CHILD`, opaque compiler payload excluded.  `b2`: `NON_CHILD`, opaque compiler payload excluded.  `b3`: `NON_CHILD`, opaque compiler payload excluded.  Do not inspect these slots to discover syntax, cast them to assembly helpers or serialise their raw bytes. |
| `Parser_Asm`/parser-added storage. | `features`: `HELPER`, ordered feature records, then `statements`: `HELPER`, ordered statement records under the guards below.  `body_span`: `NON_CHILD`, qualified source-token interval observation.  `enclosing_scope`: `BACKREFERENCE`, never a downward syntax edge. |

`Parser_Asm` itself remains an ordinary node with its own ID; the `Asm` row below describes that node's traversal, not an extra helper allocation.
Its list elements and their auxiliary records do not acquire node IDs, while their actual identifier/expression children do.
On a missing opening brace, the builder function still publishes the node, feature list and empty statement list; preserve that recovery without treating the default `body_span` as an authored empty body.
A consumed body's empty interval and a recovered missing closing brace retain their distinct boundary/diagnostic observations.
Visit only published helper records, never discarded allocations or opaque compiler storage.
This completes draft field-role enumeration for all 50 generated layouts, including these three compiler fields and four parser-added fields.
It does not close direct base-node kinds, exhaustive auxiliary-field/variant coverage, scalar/tag schemas, builder function and reuse reachability or independent behavioural qualification.

The exact auxiliary-field rows below cover the shared span value and reviewed assembly helper slices.
These are non-node records; their fields do not introduce helper IDs or permit unguarded payload traversal.

| Record/storage domain. | Exact fields/declared variants. |
| --- | --- |
| `Token_Span`/shared token-coordinate value. | `first`: `NON_CHILD`, inclusive token index.  `one_past_last`: `NON_CHILD`, exclusive token index.  Both use the producer's distinct `Token_Index` type, not absolute source-byte offsets. |
| `Parser_Asm_Feature`/parser-owned helper. | `span`: `NON_CHILD`, qualified token-span observation.  `name`: `CHILD`, required published identifier occurrence; visit through the ordinary identifier mapping, not an assembly declaration entry. |
| `Parser_Asm_Memory_Operand`/parser-owned helper. | `span`: `NON_CHILD`, published memory-address token interval.  `base`: `HELPER`, required base value, then `index`: `HELPER`, optional index value, `scale`: `HELPER`, optional scale value, and `displacement`: `HELPER`, optional signed displacement value.  Traverse published expressions in that order under the qualified memory route; default value records do not establish authored components. |
| `Parser_Asm_Operand_Modifier`/parser-owned helper. | `kind`: `NON_CHILD`, registered suffix-variant observation.  `span`: `NON_CHILD`, published suffix token interval.  `argument`: `HELPER`, required identifier-valued argument only for the ampersand variants; inactive for every bang variant. |
| `Parser_Asm_Operand_Modifier_Kind`/declared variants. | `BANG`, `BANG_N`, `BANG_D`, `BANG_U`, `BANG_Z`, `AMPERSAND`, `AMPERSAND_STAR`.  Native ordinals and the producer's enum width are not approved wire tags. |
| `Parser_Asm_Register_Declaration`/parser-owned helper. | `span`: `NON_CHILD`, declaration-prefix token interval, not necessarily the full attached pinning interval.  `name`: `CHILD`, required source identifier.  `register_class`: `CHILD` only when the class spelling is explicit.  `is_inferred`: `NON_CHILD`, grammar observation selecting omitted versus explicit class, not semantic type inference.  `pinning`: `HELPER`, optional published pinning record after name and explicit class; distinguish a qualified omission from a rejected introduced suffix. |
| `Parser_Asm_Register_Pinning`/parser-owned helper. | `span`: `NON_CHILD`, qualified full pinning token interval.  `source`: `HELPER`, required source value, then `target`: `HELPER`, required target value.  Each follows the value helper's expression/presence rules; helper records do not acquire node IDs. |
| `Parser_Asm_Operand`/parser-owned helper. | `kind`: `NON_CHILD`, registered operand-variant observation.  `span`: `NON_CHILD`, full published operand token interval, including attached suffix syntax.  `value`: `HELPER`, selected value payload only.  `register_declaration`: `HELPER`, selected register-declaration payload only.  `register_pinning`: `HELPER`, selected register-pinning payload only.  `memory`: `HELPER`, selected memory payload only.  `modifiers`: `HELPER`, ordered published suffix records after the selected base, for every kind including unparsed.  Inactive base slots do not become edges. |
| `Parser_Asm_Operand_Kind`/declared variants. | `UNPARSED`, `VALUE`, `REGISTER_DECLARATION`, `REGISTER_PINNING`, `MEMORY`.  Native ordinals and the producer's enum width are not approved wire tags. |
| `Parser_Asm_Value`/parser-owned helper. | `span`: `NON_CHILD`, qualified value token interval.  `expression`: `CHILD`, published source expression when present; required for a selected value operand or required value component, but legitimately absent in an optional unused component under its owning helper's route. |
| `Parser_Asm_Instruction`/parser-owned helper. | `span`: `NON_CHILD`, published statement-span observation.  `mnemonic`: `CHILD`, required source identifier.  `size`: `HELPER`, optional qualified mnemonic-size record.  `operands`: `HELPER`, ordered published operand records.  Visit mnemonic, selected size child, then operand children in stored order; helper records do not acquire node IDs. |
| `Parser_Asm_Mnemonic_Size`/parser-owned helper. | `kind`: `NON_CHILD`, registered size-variant observation.  `span`: `NON_CHILD`, consumed size-token interval.  `polymorphic_name`: `CHILD` only on the polymorphic route; inactive for a fixed size. |
| `Parser_Asm_Mnemonic_Size_Kind`/declared variants. | `FIXED`, `POLYMORPHIC`.  Native ordinals and the producer's enum width are not approved wire tags. |
| `Parser_Asm_Statement`/parser-owned helper. | `kind`: `NON_CHILD`, registered statement-variant observation.  `span`: `NON_CHILD`, retained statement token interval.  `instruction`: `HELPER`, selected instruction payload only.  `register_declaration`: `HELPER`, selected register-declaration payload only.  `register_pinning`: `HELPER`, selected register-pinning payload only.  Use the kind guards below; no selected helper on the unparsed route. |
| `Parser_Asm_Statement_Kind`/declared variants. | `UNPARSED`, `INSTRUCTION`, `REGISTER_DECLARATION`, `REGISTER_PINNING`.  Native ordinals and the producer's enum width are not approved wire tags. |

The span/feature/statement slice enumerates nine declared fields across three records and all four current statement kinds.
The shared span's field names describe token coordinates; validate them against the protected revision and applicable source/recovery rules, not by blindly treating a zero/default pair as an authored occurrence.
The statement builder function retains its full span before classification.
Empty/non-identifier content and rejected declaration/pinning forms can remain unparsed; retain their opaque region and partial-coverage observation rather than inventing an instruction or following a leftover inactive slot.
A selected helper follows its own required-field/recovery rules, while an unknown kind is unmapped rather than an instruction fallback.
The focused static checks compare fields and enum members with their declarations; the milestone-1 closure completes the current auxiliary field/variant inventory, while executable builder/reuse and variant qualification remain open.

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
Scalar/tag schemas and executable builder/reuse and variant/recovery qualification remain open.

Embedded-value storage review: the current assembly helper declarations contain eight by-value `Parser_Asm_Value` fields across four owner types.
None requires a separate value-helper pool allocation or acquires a node ID merely because its containing record is allocated.

| Owner/embedded slots. | Population path. | Publication/identity boundary. |
| --- | --- | --- |
| `Parser_Asm_Register_Pinning`/`source`, `target`. | After pinning-shape validation, assign two records returned by `parse_asm_value_span`, first the identifier source interval, then the identifier/numeric target interval. | Both embedded records belong to the pinning helper; only their retained expression nodes enter the ordinary node-ID domain.  Existing pinning publication and required-expression rules still apply. |
| `Parser_Asm_Memory_Operand`/`base`, `index`, `scale`, `displacement`. | After validating the addressing form, assign base span/identifier directly; do the same for an introduced index.  Assign scale and displacement from `parse_asm_value_span` only when their respective source boundaries were found. | These are four distinct embedded slots, not four automatically authored occurrences.  Unused slots stay subject to the existing optional-component/default-span rules; visit represented children in base/index/scale/displacement order. |
| `Parser_Asm_Operand_Modifier`/`argument`. | The ampersand variants require an identifier, then assign its span and `new_asm_ident` result directly; bang variants do not populate this slot. | Inspect the slot only under its registered modifier kind and only after the modifier list is attached.  Temporary malformed-suffix records remain outside that published list. |
| `Parser_Asm_Operand`/`value`. | For a recognised standalone identifier, number, signed number or qualified parenthesised base, assign the returned `parse_asm_value_span` record and select `VALUE`. | This slot is active only for the value operand kind.  An unparsed base does not become a value because default or inactive storage exists. |

There are five explicit `parse_asm_value_span` call sites in `parser.jai`: two pinning components, two memory components and the ordinary value operand.
The memory base/index and modifier argument instead supply three direct span/identifier population sites.
The value builder returns a record containing the supplied span and parsed expression; it saves the current cursor, parses from the supplied first token, asserts the supplied endpoint and restores the saved cursor on its normal return path.
This is cursor restoration, not diagnostic/recovery rollback or a guarantee of cleanup after a failed assertion.
The focused static check compares all eight declared slots, these five call sites, the three direct population sites and the builder's sequence.
It does not qualify every enclosing publication route, source correlation, independent ownership or executable recovery behaviour, and does not add another helper type or field to the existing inventory.

The register declaration/pinning slice adds eight declared fields across two records.
Visit the declaration name, explicit class only when not inferred, then published pinning source and target; never reconstruct an omitted class or resolve assembly register bindings.
The reviewed pinning builder function accepts an identifier source and an identifier or numeric target at the required separator boundaries; a rejected shape does not publish a pinning helper.
An introduced but rejected pinning suffix can leave the declaration published with null pinning and no pinning-specific diagnostic.
Null alone therefore cannot establish valid omission: preserve the raw suffix and the appropriate uninspected/mapping region under the existing partial-coverage rules, rather than inventing a target or claiming that no suffix was authored.
Required expression holes in published pinning values follow the existing qualified recovery/mapping rules.
The declaration name and pinning source can be separately allocated identifier nodes for the same token.
Keep their distinct IDs and registered paths, and do not extend the declaration helper's producer span to contain its attached pinning.
Exact scalar/tag schemas and executable builder/reuse and omission/rejection/identity qualification remain open.

The memory/modifier slice adds eight declared fields across two records and all seven current modifier kinds.
Memory components follow their published value expressions: do not invent an implicit scale, zero displacement or identifier for unused storage.
A consumed operator with no represented component is not proved absent by a default value record; retain its source/recovery observations and any required uninspected/mapping coverage rather than declaring the whole address fully mapped.
Rejected memory forms do not justify reconstructing a helper from the raw operand span.
Bang suffixes have no argument child; their qualified single-letter forms require the reviewed adjacency/spelling evidence.
Ampersand-star requires adjacent punctuation, and both ampersand variants publish an identifier-valued argument rather than an arbitrary expression parsed from trailing text.
Traverse only published modifiers in stored order, including those attached to an unparsed base; unknown kinds remain unmapped, and inactive argument storage is never a child.
Declared-field enumeration now covers all ten current assembly helper records plus the shared token-span value, and all four assembly kind enums.
The focused static check compares that complete local set with the live declarations; it does not qualify all builder/reuse paths, source-form correlations, exact wire schemas, other auxiliary families or executable visitor behaviour.

| Helper/guard. | Downward order and restrictions. |
| --- | --- |
| `Asm`. | `features[]`, then `statements[]`, each in stored source order.  `body_span` is observation data; `enclosing_scope` is a backreference. |
| `Asm_Feature`. | `name`. |
| `Asm_Statement`. | `INSTRUCTION`: `instruction`; `REGISTER_DECLARATION`: `register_declaration`; `REGISTER_PINNING`: `register_pinning`; `UNPARSED`: no base child.  Other arm fields are inactive regardless of pointer contents. |
| `Asm_Instruction`. | `mnemonic`, optional `size` helper, then `operands[]` in stored order. |
| `Asm_Mnemonic_Size`. | `FIXED`: no child; retain the size token span, not a fabricated numeric-expression node.  `POLYMORPHIC`: `polymorphic_name`. |
| `Asm_Operand`. | First the selected base arm: `VALUE` -> `value`; `REGISTER_DECLARATION` -> `register_declaration`; `REGISTER_PINNING` -> `register_pinning`; `MEMORY` -> `memory`; `UNPARSED` -> no base child.  Then `modifiers[]` for every base kind, including `UNPARSED`. |
| `Asm_Value`. | `expression` when present.  For optional absent memory components the zero/default span is not an authored source occurrence. |
| `Asm_Register_Declaration`. | `name`, then `register_class` only when `!is_inferred`, then optional `pinning`.  Inferred class means no class child, not an empty identifier. |
| `Asm_Register_Pinning`. | `source`, then `target`, both `Asm_Value` helpers. |
| `Asm_Memory_Operand`. | `base`, then optional `index`, `scale`, `displacement` values in that order.  Presence comes from a nonnull expression in this producer; do not infer a component from default span indices. |
| `Asm_Operand_Modifier`. | `BANG`, `BANG_N`, `BANG_D`, `BANG_U`, `BANG_Z`: no child.  `AMPERSAND`, `AMPERSAND_STAR`: `argument` value.  Preserve modifier order and individual spans. |

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
Assert exact visit paths/order, selected-arm exclusions, node IDs and local coverage reasons.
This closes the draft's unspecified assembly-helper field paths, not the outstanding producer review or executable qualification gates for the complete registry.

## Token Registry and Required Trivia Profile

On 2026-10-21 the user accepted trivia handling as a requirement for full-featured API support and allowed dropping the compatibility restriction if it reduces complexity.
Accordingly, the proposed initial full-featured profile uses trivia-enabled, byte-indexed owned syntax only; dual-mode support and a non-trivia origin adapter are not acceptance requirements.
This records a scope simplification, not authorisation to remove the existing parser's AST compatibility mode or change production module defaults now.
Keep trivia/source ownership and exact byte spans in the eventual API regardless of whether the implementation later removes the compile-time switch entirely.
Performance comparisons for this profile must use an equivalent trivia-enabled fresh baseline; historical measurements with different options are not interchangeable acceptance samples.

`jai-cache-token-tags/1` has the following closed `NAMED` registry, grouped for readability only; group/row order is not token precedence or an encoded enum ordinal.

| Group. | Canonical names. |
| --- | --- |
| Values. | `IDENT`, `NUMBER`, `STRING`. |
| Operators. | `PLUSEQUALS`, `MINUSEQUALS`, `TIMESEQUALS`, `DIVEQUALS`, `MODEQUALS`, `ISEQUAL`, `ISNOTEQUAL`, `LOGICAL_AND`, `LOGICAL_OR`, `LESSEQUALS`, `GREATEREQUALS`, `RIGHT_ARROW`, `DOUBLE_DOT`, `DOUBLE_DOLLAR`, `SHIFT_LEFT`, `SHIFT_RIGHT`, `ROTATE_LEFT`, `ROTATE_RIGHT`, `TRIPLE_EQUALS`, `SHIFT_LEFT_EQUALS`, `SHIFT_RIGHT_EQUALS`, `ROTATE_LEFT_EQUALS`, `ROTATE_RIGHT_EQUALS`, `BITWISE_AND_EQUALS`, `BITWISE_OR_EQUALS`, `BITWISE_XOR_EQUALS`, `LOGICAL_AND_EQUALS`, `LOGICAL_OR_EQUALS`, `POSTFIX_DEREFERENCE`, `PREFIX_DEREFERENCE`, `ISEQUAL_FOR_SWITCH_STATEMENT`, `DOUBLE_MINUS`, `TRIPLE_MINUS`, `DOUBLE_COMMA`, `BEGIN_STRUCT_LITERAL`, `BEGIN_ARRAY_LITERAL`. |
| Keywords. | `KEYWORD_FOR`, `KEYWORD_IF`, `KEYWORD_IFX`, `KEYWORD_THEN`, `KEYWORD_ELSE`, `KEYWORD_CASE`, `KEYWORD_RETURN`, `KEYWORD_STRUCT`, `KEYWORD_WHILE`, `KEYWORD_BREAK`, `KEYWORD_CONTINUE`, `KEYWORD_REMOVE`, `KEYWORD_USING`, `KEYWORD_DEFER`, `KEYWORD_SIZE_OF`, `KEYWORD_TYPE_OF`, `KEYWORD_CODE_OF`, `KEYWORD_INITIALIZER_OF`, `KEYWORD_TYPE_INFO`, `KEYWORD_NULL`, `KEYWORD_ENUM`, `KEYWORD_TRUE`, `KEYWORD_FALSE`, `KEYWORD_INLINE`, `KEYWORD_NO_INLINE`, `KEYWORD_CAST`, `KEYWORD_AUTO_CAST`, `KEYWORD_CONTEXT`, `KEYWORD_PUSH_CONTEXT`, `KEYWORD_OPERATOR`, `KEYWORD_IS_CONSTANT`, `KEYWORD_ENUM_FLAGS`, `KEYWORD_UNION`, `KEYWORD_INTERFACE`. |
| Other. | `QUICK_LAMBDA`, `NOTE`, `END_OF_INPUT`, `ERROR`. |
| AST-only operators. | `OPERATOR_ARRAY_SUBSCRIPT`, `OPERATOR_ASSIGNMENT_TO_ARRAY_SUBSCRIPT`. |

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

## Token Values, Flags and Trivia Ownership

Proposed 2026-10-21 under `jai-cache-source-tokens/1`, for materialised source tokens in the required trivia-enabled profile; synthetic tokens remain separate recovery records, not fabricated source tokens.

`TokenRecord` is `{tag, origin:SOURCE, coordinates, value_flags:u32, ident_is_backticked:bool, original, preceding, value}`.

`coordinates` preserves `{l0:s32, c0:s32, l1:s32, c1:s32}` verbatim as producer observations, independently of validated byte origins; unset/error coordinates are not clamped into valid editor positions.

`original` and `preceding` are checked half-open byte slices of the envelope's exact source, not producer pointers or independently mutable strings.

Preserve empty slices and validate their offsets before exposing views.

The token origin agrees with its materialised `byte_start`/`byte_end`; `original` preserves the producer's `original_text` slice.

If a producer route makes these differ, retain both observations and qualify that mapping explicitly rather than silently rewriting either.

| Active `value` tag. | Producer discriminator and exact payload. |
| --- | --- |
| `NAME {bytes}`. | `IDENT`, `NOTE` and materialised `KEYWORD_*` tokens carry the active `ident_value.name` bytes.  Preserve decoded/handler-produced bytes independently of source spelling; keywords use the copied name, and backticked spellings remain distinguishable through source and `ident_is_backticked`. |
| `UNSIGNED_INTEGER {bits:u64}`. | `NUMBER` without `FLOAT` preserves the exact unsigned accumulator, including overflow-result bits with the producer's flags/diagnostics.  Do not reinterpret a high-bit value as a signed integer or infer representation from decimal spelling. |
| `FLOAT64_BITS {bits:u64}`. | `NUMBER` with `FLOAT` preserves the exact IEEE-754 binary64 object bits of `float64_value`, even when the producer first rounded to `float32`.  No decimal formatting round trip, NaN canonicalisation or signed-zero folding. |
| `STRING_BYTES {bytes}`. | `STRING` preserves the active `string_value` bytes under the captured `EVALUATE_STRING_ESCAPES` setting, including its intentional empty result when evaluation is disabled.  Keep exact raw source separately; a decoded value is not necessarily a source slice or UTF-8 text. |
| `NO_VALUE`. | A reviewed producer route with no active union member, including punctuation and EOF.  Never read union backing bytes to fill this value; an unreviewed route needs a mapping failure, not a guessed zero/name. |

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
The closed kind registry is `WHITESPACE. | LINE_COMMENT. | BLOCK_COMMENT. | SHEBANG. | IGNORED`; each item carries a checked source slice and iterator-relative offset mapped back to the parent slice's start.
Preserve `IGNORED` bytes and nested/unterminated block-comment text; classification must not assert on arbitrary source text or discard unrecognised bytes.
A classification gap does not authorise changing the authoritative trivia/source views.
All slices/decoded values borrow through the owning syntax/result lease; no token, trivia iterator or interned name may outlive that lease without an independent copy/retain.

Future qualification vectors: each active union tag; decimal/hex/binary and overflow flags; `float32`-rounded values, signed zero and exact float-bit transport; quoted/unquoted notes; escaped/here strings with evaluation enabled/disabled; producer/interner teardown; BOM-only/comment-only/empty files; nested comments, ignored bytes and EOF final-gap reconstruction.
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
