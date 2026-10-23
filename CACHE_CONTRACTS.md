# Cache Service Contract Drafts

The detailed source, store, identity, execution, interface and acceptance contracts for the [cache architecture](CACHE_ARCHITECTURE.md).
Status conventions, the decision record, the milestone index and the label glossary are in [CACHE_ARCHITECTURE.md](CACHE_ARCHITECTURE.md#document-map-and-conventions).
The current-producer syntax projection is in [CACHE_SYNTAX_REGISTRY.md](CACHE_SYNTAX_REGISTRY.md).

## Core Contract Draft

Drafted 2026-10-20.
This makes the source, ownership and request boundaries concrete enough to review.
The semantic, persistence-format, host-policy and concurrency details are in the later sections.

### Source Events and World Capture

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

| Event. | Proposed source selection and observable result. |
| --- | --- |
| Open or replace overlay. | Select the host-supplied revision over disk.  Retain disk state separately; identical bytes alone do not acknowledge a save or discard. |
| External disk update. | Advance the acknowledged disk reference; an active overlay remains selected.  Without an overlay, select the new disk revision and schedule its syntax milestone. |
| Save acknowledgement. | Record the exact revision actually written and acknowledged by the host.  Clear/reconcile the overlay only if the host confirms that it is that saved revision; a newer overlay edit remains selected.  A failed or delayed save must not mark the newer buffer saved. |
| Reset/discard. | On host confirmation, remove the active overlay and its active recovery reference, then select freshly validated disk bytes or explicit absence.  Cached history cannot reactivate the discarded overlay. |
| Delete. | Mark the disk reference absent.  Preserve an active host buffer as an overlay; without one, publish source absence, not an empty parsed file or an old cached revision. |
| Rename/replacement. | Accept an explicit host event and revalidate source-visible context and resolution inputs.  Do not infer declaration/module continuity or alias equivalence from matching bytes.  Exact physical identity and cross-file atomic-event policy remain decisions. |
| Restart/recovery. | Validate disk/configuration; expose persisted overlays only as recovery candidates.  Activate a candidate only after host confirmation, through a new source event. |
| Cache failure. | Preserve the accepted in-memory source selection, reconstruct from authoritative bytes where possible, and report a separate cache diagnostic.  Source acquisition failure is explicit unavailability/failure, not permission to use a stale revision. |

A captured world contains immutable selected document-revision/context references and the source-provider event frontier used to choose them.
Publication installs a coherent world atomically; completion of old work never rewrites an already captured world or silently makes an old world current.
If later dependency discovery requires a source not captured in that world, use an immutable provider snapshot capable of supplying that frontier's bytes, or return an explicit unavailable/incomplete result requiring a new world.
Do not read today's disk file and attach it silently to yesterday's world; the exact provider snapshot/discovery mechanism remains to be specified.
Initial syntax publication does not assert a complete import closure or semantic world.

### Ownership and Publication

| Owner. | Proposed lifetime obligation. |
| --- | --- |
| Source/syntax snapshot. | Own or lease exact source/path payloads, tokens, nodes, diagnostics, recovery records and syntax indices.  These are immutable after publication and cannot borrow parser scratch, evaluator memory or a released producer snapshot. |
| Captured world. | Hold strong references/leases to its selected source/syntax and context records.  Reusing syntax does not share mutable semantic state.  A newer world cannot invalidate an older world's references. |
| Semantic query/group. | Own derived records and dependency stamps separately from syntax; lease required syntax/context.  Cyclic group ownership/reclamation still needs its own contract before semantic implementation. |
| Pending task. | Own its scratch and protected inputs until completion or acknowledged termination.  Request cancellation alone is not proof that the worker stopped reading those inputs. |
| Request/result lease. | Protect the selected world and returned payload through explicit release.  Releasing a pending waiter detaches that waiter; acquiring a result must establish its protection before task/cache protection is dropped. |
| Resident/disk cache. | May evict only when ownership permits; budget pressure cannot free leased backing.  Record/slot reuse changes allocation generation, and stale handles must reject rather than resolve a different record.  Raw addresses are not persistent identities. |

Publish immutable payload and its revision/context/dependency identity as one observable action; never expose a ready flag before the protected payload exists.
Cache residency, world selection, task completion, and durable-store publication are separate events.
A syntax milestone need not wait for a cache write: expose persistence failure/status separately, and do not promise durability until the required artifact and manifest commit has succeeded.
If leases prevent meeting a configured memory budget, report pressure or reject new optional work under an agreed host policy; never silently revoke a live lease.
Exact lease representation, synchronisation, pressure policy and shutdown ownership ordering remain specification work.

### Update Tickets and Query Outcomes

An accepted change returns a ticket for its requested revision and milestone; it does not return an unqualified promise that all analysis is complete.
Proposed update lifecycle: `queued -> running -> published. | superseded. | cancelled. | failed`, allowing direct queued-to-terminal transitions where appropriate.
`published` identifies the exact captured world and achieved syntax/index milestone, including incomplete-code diagnostics where applicable.
`superseded` means that milestone was not delivered for the requested revision; include a successor ticket only if one exists, and require explicit selection of its result.
Cancelling a wait is independent of cancelling underlying work; neither action implicitly discards accepted buffer contents or selects another source revision.
An abandoned update must report its terminal reason; retrying analysis of retained source uses an explicit new request/ticket.

| Selected-world query outcome. | Required meaning. |
| --- | --- |
| Available. | Return a protected payload, world/revision/context identity, and completeness/diagnostic status.  Syntax with parse diagnostics may be available; incomplete semantic knowledge is not a successful negative lookup. |
| Pending. | Return a waiter for work keyed by the selected world/query/context.  Deduplicate equivalent work, but track waiter cancellation independently.  Internal blocked dependencies are not a successful result. |
| Unavailable. | State the reason, such as an absent source or unavailable captured provider revision, without substituting current disk bytes or fabricating a language diagnostic. |
| Unsupported. | State the unsupported capability/context.  Do not schedule evaluator execution, return an empty successful answer, or leave a waiter pending forever for functionality not supplied. |
| Failed. | Report computation/source/service failure separately from ordinary syntax diagnostics and cache-recovery warnings; include the selected identity where available. |
| Cancelled. | `CALLER` completes only the cancelled waiter/request; other current-world waiters may still receive the shared result.  `WORLD_SUPERSEDED` cancels unfinished obsolete-world work and every still-pending attached query waiter, leaving each client to decide whether to reissue. |

Each ticket/waiter has at most one terminal transition; observation/waiting after termination returns that outcome rather than consuming it or causing another transition.
Check operation generation and terminal state at publication so duplicate/late completion cannot resurrect cancelled work, overwrite a superseded ticket or deliver a payload to a released waiter.
A retained old world and its already published results remain readable, but its unfinished work is cancelled when its captured source frontier becomes obsolete; it is not kept running by retained-world waiters.
Never silently switch the selected world or automatically reissue a cancelled query; already terminal results and independent leases remain unchanged.
Milestone 5 specifies the draft execution/delivery/ownership model; its approval, native bindings and real concurrent qualification remain open.

### Acceptance Trace Drafts

These are future executable acceptance cases for C1-C5, not additional experiments already run or tests already passing.
Each trace must assert the selected identities and exact fresh-oracle result where supported, not merely cache-hit counters.

| Trace. | Events and required assertions. | Gates. |
| --- | --- | --- |
| T1: Edit and query. | Capture disk world A; notify overlay B; await B's syntax milestone; query B.  Assert exact B bytes/diagnostics, no semantic-completion promise, and unchanged leased A results. | C1, C2, C3, C5 |
| T2: Stale edit batch. | Submit a range based on A after B is selected, then a batch containing an invalid range.  Reject each atomically with B unchanged; a valid full replacement can subsequently succeed. | C1, C2, C5 |
| T3: Save racing edit. | Submit save of B, select newer overlay C, then receive B's save acknowledgement.  Disk points to B while the active overlay remains C; neither the late acknowledgement nor equal-byte reuse discards C. | C2, C5 |
| T4: Reset and restart. | With disk A and overlay B, confirm reset, release/restart, and validate disk.  Select current disk or absence, never B merely because its blob remains.  A separate confirmed recovery of B is a new explicit event. | C2, C4, C5 |
| T5: Retention and reload. | Lease A, publish B, request eviction and release producer/scratch storage.  A and B remain exact until their respective leases end; freed generations reject stale handles.  Rehydration failure reconstructs or reports unavailability without changing source selection. | C1, C3, C4 |
| T6: Shared waiters. | Two waiters join one current-world query; cancel/release one through the UI/caller path, complete the task, then attempt duplicate completion.  The survivor receives one protected result, the cancelled waiter reports `CALLER` and receives no late payload, and only one task was dispatched. | C3, C5 |
| T7: Superseded update and query. | Keep two waiters on shared B work, accept newer source C and delay B's producer return.  B's unfinished update is `SUPERSEDED`, all still-pending B query waiters receive `WORLD_SUPERSEDED`, B cannot publish a late result/head and its pins survive until safe stop.  Already acquired B results remain readable; each client independently decides whether to request C, with no automatic reissue. | C2, C3, C5 |
| T8: Cache and capability failures. | Deny store writes or corrupt an artifact, then notify/query valid source and request unsupported semantics/evaluation.  Source syntax remains usable, cache warnings stay separate, unsupported is terminal, and no compiler process launches. | C1, C4, C5 |

Milestones 2-6 supply the syntax/API/provider/identity/execution/persistence drafts, including finite capture rather than implicit broader source discovery.
Milestone 7 supplies the whole-system acceptance mapping/workload/evidence draft; policy/detailed contract and workload approval, cross-contract sign-off, native bindings and executable implementation qualification remain open.
Unsupported discovery/semantic capabilities do not become implemented by this draft closure.
The migration-plan gate and all scope/performance approval gates remain open.

## Persistence Contract Draft

Drafted 2026-10-20.
This refines C2-C4 and the source/world contracts using E10/E11, without adopting their experimental formats, fixed fixture limits, or filesystem guarantees as a production implementation.
The milestone-6 sections below close the draft text grammar, record schemas, bounds, coordination, publication and maintenance protocol using `Text_File_Handler`.
The 2026-10-23 decisions select project-relative storage, optional quotas, measurement-first evaluation and testing our code under external primitive assumptions; remaining policy details and implementation qualification are still open.
Required source/recovery persistence is distinct from optional decoded-syntax or semantic artifacts.

### Milestone 6: Store Profile, Bounds and Text Grammar

The proposed initial profile is `jai-cache-store/1`: a private, workspace/provider-scoped store with one owning process and one writer session at a time, immutable content-addressed records and one replaceable head.
Other processes/sessions do not concurrently read, publish or collect through this profile; a contending opener reports store unavailability/degradation while correct in-memory source work continues.
Cross-workspace sharing, multi-process reader/writer leases, mmap-backed retained payloads and semantic archive loading are unsupported until separately specified and qualified.
Exclusive ownership and the initial persistence/resource defaults were approved under R2/R6 on 2026-10-23; detailed profile sign-off and implementation qualification remain open, and E11 does not qualify this service.
The existing fifteen public source/scheduling operations are unchanged; persistence runs through the registered store binding and its bounded lane, never while a service state gate is held.

`StoreLimits` has exactly twelve required positive `u64` fields in this order: `file_bytes`, `manifest_bytes`, `line_bytes`, `value_bytes`, `key_bytes`, `records`, `elements`, `depth`, `decoded_bytes`, `transaction_bytes`, `disk_bytes`, `files`.
These are effective technical bounds, not twelve mandatory user-configured resource quotas.
`StoreLimitRequest` has the same twelve names in the same order, each `s64`; omitted fields mean `-1`, the default with no configured quota, while a positive value indicates that value.
Zero and values below `-1` reject; check a positive request before converting it to the effective unsigned bound.
Implementation ceilings must reflect documented representation/algorithm constraints, not disguise an arbitrary fixed RAM/disk quota as the all-available default.
No infinite integer/sentinel or unlimited decoder nesting follows from `-1`; allocation/write failure remains possible at any point, and a free-space observation is not a reservation.
`file_bytes` bounds each opened file; `manifest_bytes` additionally bounds descriptor/head/manifest records; `line_bytes` bounds every raw line before line allocation.
`value_bytes` and `key_bytes` bound individual decoded byte values and complete keys; `records` counts all value/field/chunk rows, `elements` bounds every list/record/variant field count and `depth` bounds nested values/references.
`decoded_bytes` bounds the entire owned reconstruction, including reference maps; `transaction_bytes` includes simultaneous input/decoded/staged/output/cleanup backing, not only the final payload.
`disk_bytes` and `files` bound managed logical file lengths/counts, including staging, metadata, old heads and protected records; filesystem allocation/free-space failures remain independently possible and explicit.
Check additions, multiplication, hex expansion, counts, depth and aggregate reservations before allocation or read; a small declared byte value never permits an unbounded backing file.
Optional history/expiry choices do not weaken these bounds.
Document implementation ceilings and supported descriptor/head/source minima during implementation; optional user quotas below those minima reject explicitly instead of being silently increased.

All store files use this exact ASCII envelope; the angle-bracket items below are grammar metavariables, not Jai type notation or literal text:

```text
[1]
JAI_CACHE_TEXT
KIND <registered-kind>
SCHEMA <registered-schema>
BODY
<one typed value>
END
HASH <64 uppercase hexadecimal digits>
```

Each line ends in one LF, including the last; reject CR, BOM, tabs, blank/comment lines, leading/trailing spaces, missing final LF and any bytes after the hash line.
Tokens are separated by exactly one ASCII space.
The first line is exactly `[1]`; no ignored version-line suffix or implicit future version is accepted.
The hash is SHA-256 of all exact preceding bytes through `END` and its LF, not decoded/reformatted text; it detects corruption, not malicious replacement with a recomputed hash.
`StoreBlobKey` is the 32 SHA-256 bytes of the complete encoded file, including the hash line; its path spelling is exactly 64 uppercase hexadecimal digits.
It is a wire-content key, distinct from `SourceRevision`, `ContextID`, `SyntaxArtifactKey` and `SemanticArtifactKey`.
Schema/kind tokens are exact registered ASCII identifiers; unknown schemas/kinds/fields/arms and extra/trailing rows fail closed.

The body is the following typed preorder grammar.
Counts determine exactly how many following rows belong to a value; there are no inferred delimiters, optional fields or native-memory dumps.

| Row. | Exact interpretation. |
| --- | --- |
| `U <decimal>` | One unsigned `u64`; canonical decimal has no sign or leading zero except `0`. |
| `S <decimal>` | One signed `s64`; optional minus only for a negative nonzero value, no plus/leading zeros/negative zero. |
| `T 0` or `T 1` | One boolean, not an arbitrary integer. |
| `B <byte-count> <chunk-count>` | One byte string followed by exactly that many `H <hex>` rows.  Empty is exactly `B 0 0`; otherwise chunk count is checked ceiling of byte count divided by 64. |
| `E <tag>` | One exact enum tag from the declared field's closed registry, not its native ordinal. |
| `R <field-count>` | One record followed by that many `F <field-name>` rows, each immediately followed by its typed value, in declared schema order. |
| `V <arm> <field-count>` | One tagged union followed by the declared active arm's ordered field/value pairs, with the same `F` rule.  Inactive fields are forbidden. |
| `A <element-count>` | One ordered sequence followed by exactly that many typed values. |

Every `H` row except the last encodes exactly 64 bytes as 128 uppercase hex digits; the last encodes the remaining 1-64 bytes, with no whitespace within the hex.
Chunk size 64 is a wire-canonicalisation constant, not a production resource budget.
A byte count/chunk count mismatch, odd/lowercase/invalid hex or an extra `H` row rejects.
Field names and enum/arm tags are any valid jai identifier.
Raw float observations use their declared `u64` bit-pattern field with `U`, never host float parsing or a decimal approximation.
Opaque canonical identities/descriptors use `B`; records, optionals and arrays preserve the existing logical schema's types/order rather than guessing a type from equal-looking scalar bytes.
This grammar is a text encoding of the canonical values, not a replacement for the milestone-3 `V`/`K` identity recipes; readers reconstruct and validate those logical values before comparing identity.

First bound/read the actual open stream into protected storage, check raw line/envelope grammar and the exact checksum, then use `start_from_memory` with a `Text_File_Handler` over that same bounded immutable buffer.
Do not call `start_file` for an untrusted store record: its whole-file read precedes application bounds.
Set `strip_comments_from_ends_of_lines = false` and `auto_skip_blank_lines = false`; keep version processing enabled only after the strict `[1]` preflight and require `version == 1` with `failed == false`.
The handler still trims spaces/skips full-line comments and its version parser tolerates a suffix, so its successful parse is not the canonical-input validator.
Retain input/name buffers for the handler lifetime; `deinit` does not free the borrowed `start_from_memory` buffer.
Release both handler and separately owned input on every failure/return.
Use checked iterative value/reference stacks under `depth`; malformed input returns a cache fault/miss with complete partial cleanup, never an assertion-aborting process or source-language diagnostic.

### Records and Persistent Identity

| Logical record. | Proposed required content and boundary. |
| --- | --- |
| Store descriptor. | Format/schema versions, store namespace and compatibility policy.  Do not infer compatibility from the directory name or compiler version alone. |
| Source artifact. | Exact source bytes, byte length and strong digest, plus encoding information needed to reconstruct those bytes without newline/Unicode normalisation.  Preserve arbitrary parser-accepted bytes; the text envelope may encode them. |
| Context descriptor. | Document/path identity inputs, source-visible filename/directory, resolver/parser configuration and their versions.  Include configured module/program/import-request discriminators for semantic artifacts; physical-file equality is not semantic identity. |
| Optional derived artifact. | Record kind/schema, producer/query version, source/context references, completeness/support status and validated dependency identities.  Payloads contain explicit IDs/offsets, never pointers, allocators, pools or process-local reflection objects. |
| Workspace manifest. | Workspace namespace, committed generation, and roots for acknowledged disk revisions, recoverable overlay candidates and policy-retained history.  Reference immutable artifacts; record absence/reset state explicitly where needed.  A manifest is not authority that cached disk bytes are still current. |
| Recovery descriptor. | Workspace/document-session association, exact source/context reference and host recovery provenance needed to present a candidate.  No automatic activation flag inferred from recency.  Save/reset/discard advance or remove the corresponding recovery reference explicitly. |

Use canonical versioned encodings for identity inputs; equal decoded values in different ad hoc spellings must not accidentally become a different key, or vice versa.
Candidate immutable artifact keys are SHA-256 of the exact encoded artifact bytes, with source-byte and logical-context validation inside the record.
This separates wire integrity from source identity and dependency validity; a matching outer digest alone is not a valid syntax/semantic hit.
Verify existing content before treating a same-key file as reusable; conflicting or invalid content is a cache fault, not permission to overwrite a blob potentially used by another reader.
Checksums/digests detect corruption, not authenticity against an attacker able to replace content and hashes together.
Persisted data never grants compiler-execution permission.

Use only validated encoded keys to form store-relative paths; never concatenate raw source paths, supplied artifact names or unvalidated dependency IDs.
The concrete directory layout must retain the source/context and module-instance distinctions described in [architecture section 8](CACHE_ARCHITECTURE.md#8-allocation-and-lifetime-model), while allowing context-independent source bytes to be shared.
Reject traversal, out-of-store redirects and unsupported link/reparse-point cases under an explicit filesystem policy; user-private permissions are necessary but not a substitute for validation.
Session tickets, raw world handles, allocation generations and live request leases are not restored as active process objects; reconstruct fresh session identities and validate persisted references.

### Read and Validation Sequence

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

### Milestone 6: Record Schemas and Configured Policy

`StoreRef` is `{kind:StoreRecordKind, schema:bytes, key:StoreBlobKey, wire_bytes:u64}`; each reference carries the full expected kind/schema and actual complete encoded length, not only a filename digest.
`StoreRecordKind` has exactly seven tags in the following table.
Its schemas use the exact written field order and the milestone-3 logical encodings/types, with the milestone-6 text grammar for their wire representation.
Canonical document/history arrays are duplicate-free and sorted by complete canonical identity/value bytes, never display paths, hash alone or native table iteration order.

| Kind and exact schema. | Body record and validation. |
| --- | --- |
| `DESCRIPTOR`, `jai-cache-store-descriptor/1` | `StoredDescriptor {profile:bytes, store_namespace:bytes, workspace:WorkspaceID, provider_namespace:bytes, document_policy_version:u32, ownership:WORKSPACE_EXCLUSIVE, wire_schema:bytes}`.  Profile/wire schema are `jai-cache-store/1` and `jai-cache-store-text/1`; compare namespace/workspace/provider/policy to the trusted binding, not to another claim read from this store. |
| `SOURCE`, `jai-cache-store-source/1` | `StoredSource {source_revision:SourceRevision, source_bytes:bytes}`.  Recompute the canonical revision from exact bytes/length and require full identity equality; source bytes are never newline/Unicode normalised or interpreted as a path. |
| `CONTEXT`, `jai-cache-store-context/1` | `StoredContext {context:ContextID, descriptor:bytes}`.  Decode/recompute the canonical context key and check the actual registered producer/adapter/profile tuple when reused.  Unsupported producer/schema becomes a miss, not inferred compatibility. |
| `RECOVERY`, `jai-cache-store-recovery/1` | `StoredRecovery {workspace:WorkspaceID, document:DocumentID, source:StoreRef, context:StoreRef, provenance:RecoveryProvenance, created_unix_seconds:s64}`.  `created_unix_seconds == -1` means not set; set times are nonnegative, and values below `-1` reject.  Source/context references have exactly those kinds; bind document/path/context through the validated document record and current host continuity before offering a candidate. |
| `DOCUMENT`, `jai-cache-store-document/1` | `StoredDocument {document:DocumentID, binding:DocumentBinding, disk:StoredDiskSlot, recovery:StoredRecoverySlot}`.  Binding/namespace/policy must agree; independently stamped disk/recovery slots preserve save-versus-overlay/reset ordering. |
| `MANIFEST`, `jai-cache-store-manifest/1` | `StoredManifest {store_namespace:bytes, descriptor:StoreRef, commit:StoreCommitID, previous_commit:Optional(StoreCommitID), writer_epoch:u64, source_sequence:u64, accepted_frontier:Optional(ProviderFrontier), documents:[]StoreRef, history:[]StoredHistory}`.  Descriptor/documents have the corresponding exact kinds, document identities are unique, and all required roots must exist and validate before commit. |
| `HEAD`, `jai-cache-store-head/1` | `StoredHead {store_namespace:bytes, commit:StoreCommitID, generation:u64, manifest:StoreRef}`.  Manifest kind/schema/namespace/commit must agree; generation starts at 1, increments with checked arithmetic and never wraps.  The head is a complete envelope, not a partial pointer file or source authority. |

`StoreCommitID = K("store-commit", [store_namespace, owner_epoch_u64_LE, commit_sequence_u64_LE])`.
Reserve a fresh owner epoch through the trusted `ReserveEpoch` before opening a writer; its positive commit sequence starts at 1 and never repeats/wraps, including failed/uncertain publications.
Head generation is useful local predecessor information, not global uniqueness: restoring an old cache may repeat its numeric generation but cannot reissue a commit identity under a fresh owner epoch.
`previous_commit` is descriptive provenance, not a strong reference that recursively keeps every historical manifest/source alive.
The trusted epoch issuer is outside the disposable cache and its clear/repair/rollback scope; no counter, PID, clock, lock-file contents or restored manifest replaces its durable nonreassignment contract.
This profile supplies no unqualified local issuer fallback.
The host must bind a reservation authority satisfying the declared durable nonreassignment contract under documented external assumptions, or `OpenSession` retains the specified configuration failure; process-atomic cache commits do not weaken that identity prerequisite.
Test our authority/adapter logic and failure handling, not independent certification of the OS/storage that supplies those assumed primitives.

- `StoreEventStamp` is `{writer_epoch:u64, source_sequence:u64, origin:StoreEventOrigin}`.
- `StoreEventOrigin` is `SOURCE {session:SessionID, operation:OperationID}` or `BOOTSTRAP` or `MAINTENANCE {action:CLEAR_HISTORY|CLEAR_RECOVERY|CLEAR_ALL|EXPIRE|REINITIALISE, host_confirmation:bytes}`.
- `SOURCE` requires a positive source sequence; bootstrap uses 0, and maintenance preserves the relevant committed source sequence under its fresh owner epoch and explicit head precondition.
Neither bootstrap nor offline maintenance fabricates a live session/operation identity to stamp a tombstone.
- `RecoveryProvenance` is `{origin:StoreEventStamp, installation_revision:ProviderRevision, accepted_frontier:ProviderFrontier}`; these archived IDs are descriptive provenance, never revived registrations or proof of current host intent.
- `StoredDiskSlot` is `{stamp:StoreEventStamp, state:StoredDiskState}`.
- `StoredDiskState` is `UNKNOWN` or `ABSENT {context:StoreRef, provenance:ObservationProvenance}` or `PRESENT {source:StoreRef, context:StoreRef, provenance:ObservationProvenance}`.
Unknown remains unknown; absence has no source reference, and a present empty source is a real `SOURCE` record, not absence.
- `StoredRecoverySlot` is `EMPTY {stamp:StoreEventStamp}` or `CANDIDATE {stamp:StoreEventStamp, candidate:StoreRef}`; the candidate must be a matching `RECOVERY` record.
An empty stamped slot is the committed reset/discard/save-removal tombstone.
Do not infer it from a missing/corrupt candidate file or drop its ordering stamp while required roots remain.
- `StoredHistory` is `{document:DocumentID, source:StoreRef, context:StoreRef, origin:DISK|OVERLAY, created_unix_seconds:s64}`; `-1` means the time is not set, nonnegative times are set, and values below `-1` reject.  History is not an active recovery slot or permission to restore a buffer.

The initial persistent catalogue intentionally contains no syntax-graph, declaration, semantic or evaluator record kind.
Source/context/metadata/recovery persistence is required; optional AST persistence may remain disabled without failing that requirement.
On a valid source hit the initial reader reparses authoritative selected bytes under the exact current context; it never treats an E12 graph or a reserved semantic archive as a supported record.
Future derived-record registration must specify the exact detached payload/backing/dependency schema, validate its artifact key and producer, and rebind fresh live world/result associations without restoring old handles.
This closes the initial wire catalogue through explicit unsupported capability, not an unspecified AST serialiser or claim that source reload passed P3.

The trusted host resolves `SessionOptions.store_policy` to `StorePolicy` with fields `{profile:bytes, store_namespace:bytes, workspace:WorkspaceID, provider_namespace:bytes, root:PathValue, enabled:bool, ownership:WORKSPACE_EXCLUSIVE, required_guarantee:PROCESS_ATOMIC|POWER_LOSS_DURABLE, limits:StoreLimitRequest, recovery_retention:RecoveryRetention, automatic_repair:DISABLED, platform_binding:bytes}` in that order.
The selected defaults are enabled persistence at project-relative `.jaiParserCache`, no configured RAM/disk quota, `RecoveryRetention.UNTIL_HOST_DISCARD`, with exclusive store ownership.
Resolve the relative root against the declared project root into an absolute contained native root; source-repository placement is allowed, with discovery/version-control exclusion and privacy handling as specified in the 2026-10-23 decision record.
Do not infer a path from an opaque policy key, automatically share an incompatible namespace or silently fall back to a different storage location.
`RecoveryRetention` is `UNTIL_HOST_DISCARD` or `EXPIRE {max_age_seconds:u64}`.
All present counts/durations are positive finite values bounded by the store limits.
Initial policy selects no automatic recovery expiry and no optional persistent revision archive; the editor owns undo/redo.
The host materialises these selected defaults in its resolved policy; alternate history/expiry choices are not silently enabled by their presence in the schema.
Keep the current disk and latest required unsaved recovery, with save/reset/discard/replacement following the existing exact-stamp/host-authority rules; do not deliberately retain superseded revisions for undo/redo.
This does not revoke live leased worlds or promise immediate/secure deletion of unreferenced blobs, staging or quarantined data.
Age expiry requires a trusted host current-time observation and a valid stored creation time; missing/backward/inconsistent time retains the candidate and reports the inability to expire rather than guessing.
Expiry removes only unprotected eligible roots in a committed manifest, never active required recovery, current disk roots or live pins; policy pressure cannot silently turn protected recovery into successful persistence loss.
The initial profile implements only `PROCESS_ATOMIC`; `POWER_LOSS_DURABLE` is a reserved requirement that needs a separately registered/qualified binding, otherwise store access degrades explicitly without weakening the request.
The initial native binding identifier is `jai-cache-store-windows-local/1`; our adapter must correctly use documented root/lock/replacement primitives and handle their failures, without an independent filesystem/volume certification requirement.
An enabled but inaccessible/contended/unsupported store reports degradation; a disabled binding performs no store reads/writes, lock acquisition, enumeration or automatic cleanup.

### Milestone 6: Layout, Ownership and Commit Protocol

Within the trusted workspace/provider-specific root, the exact relative names are `owner.lock`, `descriptor.txt`, `head.txt`, `blobs/HH/<StoreBlobKey>.txt` and `staging/<owner-epoch>-<commit-sequence>-<ordinal>.tmp`.
`HH` is the first two uppercase hex digits of the complete blob key; staging components are fixed-width 16-digit uppercase hex for checked `u64` values, with a positive per-commit ordinal.
Only these validated fixed ASCII components form paths.
Raw source filenames, schema text, host tokens and dependency IDs never become path components.
All immutable kinds except `HEAD` are installed in the blob tree; `descriptor.txt` is the same exact immutable descriptor envelope named by the manifest, installed once at explicit initialisation.
`head.txt` is the sole replaceable root; `owner.lock` is coordination metadata, not a text artifact or dead-owner authority.
This fixes the earlier directory-layout proposal for the initial source-only profile: document/context grouping and readable original paths live in validated `DOCUMENT`/`CONTEXT` records, while identical source bytes can share one immutable blob.
Per-declaration/semantic-instance files are not silently introduced into this catalogue; a later semantic store must retain their separate configured identities.

The native binding must implement the following rules under explicitly documented local Windows API assumptions; test our use/error/interruption paths rather than independently qualifying the volume or extrapolating E11's ReFS result into a hardware guarantee.

| Boundary. | Required primitive/ownership rule. |
| --- | --- |
| Root and child paths. | Trusted private ACL plus checked handle-relative containment/identity.  Reject reparse/link escapes, unexpected hard-linked artifacts, remote/unsupported volumes and changed root/parent identity.  A path precheck followed by an unchecked reopen is insufficient. |
| Process ownership. | Open the stable `owner.lock` with `CreateFileW`/`OPEN_ALWAYS` and zero sharing, hold that handle for the entire store owner lifetime, and close it only after all store jobs/read pins stop.  Do not delete/recreate the lock file to steal ownership; a PID/timestamp timeout is not a lock break. |
| In-process serialisation. | One store mutex/lane orders manifest reads, publication, pin acquisition and GC.  Never hold it together with a service state gate or owner-directory gate; stage/pin service inputs first, then submit store work. |
| Staging/install. | Same-volume `CREATE_NEW` temporary files; exact checked writes/close before publication.  Install an immutable blob without replacing an existing name; verify any existing complete content before reuse, and report a conflicting same-key file as a cache fault. |
| Head replacement. | First head publication uses a no-replace same-volume install; later publication uses documented complete-file replacement, such as `ReplaceFileW`, assuming the OS honours its documented semantics.  Test our ordering/failure handling; copy/delete fallback or cross-volume move is forbidden. |
| Durability. | Use interruption-safe staging/replacement and report failures; do not claim power-loss durability from `FlushFileBuffers` or a successful process-visible replacement.  External durability certification is outside the selected initial scope. |
| Failure/close. | Report definite noncommit versus possibly committed outcome, preserve all owned handles/staging on the uncertainty path until reconciliation, and let OS handle closure after real process exit release ownership.  No callback can touch a freed store owner. |

Failure to supply/use these primitives makes the binding unavailable/degraded; it is not permission to follow an unsafe redirect, guess stale roots or substitute a knowingly non-atomic copy/delete publication.
The exclusive process handle deliberately rejects concurrent reader/collector/editor processes instead of pretending to implement cross-process pin files or stale-lease detection.
The descriptor/head namespace must match the host's configured binding; an incompatible/nonempty uninitialised directory is not automatically overwritten or adopted.
Fresh initialisation requires a host-authorised empty private root, a validated descriptor and an initial empty manifest/head; interruption before the first valid head is an explicit incomplete store, not an invented empty prior state.

#### Ordered Source Projection and Publication

An accepted source transaction creates a bounded owned store intent, independently of its analysis milestone/cancellation, with the writer epoch/session, accepted frontier, operation identity and a checked increasing `source_sequence`.
The sequence orders accepted transactions only within that live writer; bootstrap sequence is 0 with no operation/frontier, and real source transactions start at 1.
Provider tokens/frontiers are compared by their registered equality/predecessor relation, never lexical/numeric token order.
The intent protects exact bytes/context for the entire required disk/recovery projection; failure to retain/copy a required source is persistence degradation, not permission to save a partial manifest or reinterpret it as absence.
Store-lane coalescing may use a later complete projection, but cannot lose an intermediate required removal by replaying an older partial patch afterwards.
Do not roll back accepted source state or a ticket outcome because its store intent failed; report process-visible/confirmed durable progress separately.

| Source event. | Projected persistent-slot change. |
| --- | --- |
| `SET_OVERLAY`, `EDIT_OVERLAY`, `RESTORE_OVERLAY`. | Replace recovery with a candidate for the resulting overlay installation revision/source/context; preserve the independently acknowledged disk branch.  Restore is a fresh host-confirmed installation, not activation by scanning the store. |
| `OBSERVE_DISK`. | Replace the acknowledged disk slot only; retain the existing overlay candidate/installation stamp.  Absence stays an explicit disk state. |
| `ACK_SAVE`. | Record the supplied written disk observation; clear recovery only when both the saved overlay installation revision and exact source revision match the still-selected overlay, exactly as in milestone 3.  A newer byte-identical overlay survives. |
| `RESET_OVERLAY`. | Record the supplied host-confirmed disk state and stamped empty recovery slot together.  Missing disk bytes/failed persistence cannot stand in for a committed empty slot. |
| Explicit candidate discard/expiry. | Remove only the authorised, precondition-matched candidate/history root in a new manifest; it does not edit an active buffer, acknowledge a save or select cached disk bytes. |

Before each write, reserve simultaneous staging/next-head/input backing and managed disk/file capacity; a required-root/quota conflict degrades persistence without evicting protected source or silently expiring recovery.
Build and validate immutable source/context/recovery/document records outside the store mutex while their source pins and staging reservations remain live.
Under the store lane/mutex, reread the complete head, validate predecessor/namespace/writer ownership, and compare the proposed source sequence against that writer's last committed sequence.
Reject a lower sequence, treat the same sequence with conflicting content as a fault, and apply disk/recovery changes to one complete validated next manifest; different-writer takeover requires all former jobs to be stopped under the ownership protocol.
An accepted newer source event may be ahead of the disk head until its own commit; this lag is reported, not authority to select the older cached source.
Install all referenced immutable records, then the immutable manifest, then stage and atomically replace the full head while publication/GC remain excluded.
Only the head replacement is the process-visible commit point; installed unreferenced blobs are not committed recovery and remain protected from collection until the transaction resolves.
Joining/retrying a source intent compares its immutable `StoreCommitID` and complete desired projection against the observed head, not only an incremented generation number.

On definite precommit failure, keep the old head and release this transaction's staging/unused reservations after its operations stop.
On an uncertain replacement, stop new mutation and reread `head.txt` under ownership: an exact matching commit/manifest means committed; the exact recorded predecessor means not committed and permits an explicit retry with a fresh commit identity; any other valid head is reconciled as a different commit, never blindly overwritten.
An unreadable/corrupt head keeps mutation/GC disabled until explicit repair; do not scan blobs to guess which source/recovery projection was committed.
Repeated commit acknowledgement never schedules source events again, revives old writer jobs or republishes an earlier recovery slot over a newer committed tombstone.
Close/drop the process ownership handle only after the lane, uncertain commit reconciliation and all file-backed pins have returned or safely detached; an M5 shutdown deadline cannot free a still-running store operation.

`StoreCommitReceipt` is `{commit:StoreCommitID, generation:u64, frontier:Optional(ProviderFrontier), guarantee:PROCESS_ATOMIC|POWER_LOSS_DURABLE}` for the registered host/store binding, not a new public scheduling operation or live handle.
The initial profile reports `PROCESS_ATOMIC` only and leaves `StoreStatus.acknowledged_frontier` `NONE`: that existing field promises confirmed durable progress, not merely a process-visible head.
Source/recovery may survive ordinary process restart under the stated primitive assumptions; the 2026-10-23 R8 direction accepts best-effort interruption safety in our code without an external power-loss guarantee.

### Publication, Contention and Durability

Proposed publication sequence:

1. Construct and validate immutable candidate records in request-owned staging storage; use unique same-filesystem temporary paths.
Never expose partial bytes under a committed key or manifest name.
2. Acquire the store's cooperative mutation coordination with an explicit bounded wait/fail-open policy.
Re-read and validate the latest manifest generation before applying only this operation's intended changes, including disk/recovery slots independently.
3. Install validated immutable artifacts before any manifest references them.
Reuse a verified existing artifact, or publish a complete new one with the approved filesystem primitive.
Coordinate this step with GC so newly installed unreferenced blobs cannot be collected before commit.
4. Build a complete next-generation manifest, validate its references, then replace the committed manifest atomically under the documented filesystem primitive assumptions; test our ordering/error paths rather than certifying the external system.
Readers must select either a complete prior generation or a complete new generation, never a mixed update.
5. Report the committed generation and release coordination/staging resources.
If publication fails before the commit point, preserve the prior selected state and report failure/contention separately from successful in-memory syntax publication.
Uncertain commit outcomes require reconciliation by re-reading the committed generation/operation identity, not blind replay.

An update racing another save/reset must validate its host event/session ordering before replacing recovery metadata; a late writer cannot resurrect an older recovery root simply because it acquired the lock later.
The milestone-6 owner/commit protocol supplies lock ownership, idempotence, crash release and stale-writer rules; native implementation/qualification remains open, and process-ID reuse or a timeout alone is never proof that an owner died.
Do not hold service/world locks while waiting for store coordination, and do not make store contention block otherwise valid source selection indefinitely.
The cache never writes editor source files as a side effect of committing a manifest.

Distinguish in-memory availability, successful atomic process-visible commit, and power-loss durability in diagnostics/status.
Only claim the last after specifying and qualifying required file and directory flush/replacement guarantees on the supported filesystem; E11's killed-process checks do not establish power-loss recovery.
A corrupt committed manifest must not be overwritten by guessing its roots.
Fall back to in-memory operation and an explicit repair/reinitialisation policy that preserves recoverable candidates or reports their loss risk.

### Recovery, Collection and Pressure

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
Milestone 6 below specifies the single-owner pin/maintenance draft under the approved enabled/recovery/no-history/no-fixed-quota policy; detailed contract/privacy review and tests of our native implementation remain open.

### Milestone 6: Read Pins, Recovery and Collection

At open, validate the trusted binding/root/ownership and the exact descriptor/head before offering any persisted state; mismatches report a bounded cache fault/degradation, not source absence.
A missing head in a nonempty or partially initialised store is a fault requiring explicit maintenance, not an automatic empty store that discards surviving recovery.
At restart, require the milestone-4 trusted `ContinuityProof` and current document/binding validation; no descriptor, archived `SessionID` or stored disk observation authorises current source selection.
Reusing syntax requires the current admitted producer/context, but an unavailable old producer does not invalidate otherwise verified recovery source bytes.
Keep a readable old canonical context as provenance and require a freshly admitted current context for restoration rather than executing or silently reusing the old producer.
Current disk/overlay bytes or confirmed absence come from the authoritative host/provider.
Recovery discovery is a separate offer path and cannot advance a source frontier or publish a world.

Under the store mutex, select the exact validated head/manifest and install an internal generation/record pin before opening any referenced file.
That pin roots the manifest's validated transitive closure, including old generations while a read is active; GC cannot race the interval between selection and first open.
Read actual bounded open-stream bytes into owned storage, verify the complete file key/length/schema and release file pins only after all returned backing is independent of the files.
Decoding/conversion may proceed outside the store mutex under the pin and its charged ownership; returning to the lane revalidates the captured record identity, never a newer path-selected file.
The initial profile returns resident owned copies, so retained M5 `WORLD`/`RESULT` access after `STOPPED` does not lazily reopen a blob or require a surviving store worker.
Pins, reference maps and decoded copies all count against the configured byte/record/file limits; failure returns a miss/fault without exposing partial backing or revoking an earlier successful copy.
There are no cross-process lease records to expire: another process must acquire the real exclusive owner handle before reading or collecting, and contention fails safely.

`RecoveryOffer` is `{candidate:RecoveryCandidateRef, document:DocumentID, context:ContextID, context_descriptor:bytes, source_bytes:bytes, provenance:RecoveryProvenance}` returned as a complete bounded host-owned copy by the registered store adapter.
`RecoveryCandidateRef.candidate_key` is exactly the candidate `RECOVERY` record's 32-byte `StoreBlobKey`; its namespace/source revision must match the validated offer/source record.
The offer owns exact bytes and context/provenance descriptions, not a borrowed file mapping, live overlay, ticket or provider lease.
Host confirmation of `RESTORE` must bind that same candidate/document/revision and supplied byte copy under the existing `HostConfirmation`/`RESTORE_OVERLAY` rules; the event creates a fresh provider installation stamp.
The offer's exact canonical context descriptor is copied provenance, not automatic context admission; the restore batch supplies/references its current supported context under the existing atomic registration rules.
The host must retain the offer bytes until that call has copied/leased them.
Later blob collection does not invalidate an already copied offer, and missing/corrupt candidate bytes never produce an offer in the first place.
Reset/save/discard tombstones suppress candidate enumeration from the committed slot even when identical source/recovery blobs remain physically present; arbitrary orphan scanning cannot resurrect them.

GC snapshots validated current manifest roots, policy-retained history, pinned older manifests/records, unresolved publication/staging records and preserved quarantine under the same store mutex.
Mark every required reference with checked visited-key/type/schema tracking under the bounds, then delete only proved unreferenced/unpinned managed entries after a final pin/root recheck under that mutex.
Do not follow `previous_commit` as a retention root or infer an extra root from every leftover file; it is descriptive provenance, not infinite history retention.
Unknown/corrupt current or pinned roots disable destructive collection; inability to complete a bounded mark is not permission to collect the unvisited tail.
In the exclusive-owner profile, abandoned staging is eligible only after all current owner jobs are accounted for and its encoded owner epoch is from a stopped former owner; a filesystem timestamp alone proves nothing.
Enumeration is itself bounded by `files`/`disk_bytes`; unexpected entries, unsafe links, quota overflow or indeterminate containment stop automatic destructive work and report a fault.
Deleting a file does not change live source selection or invalidate any owned decoded copy; failures retain accounting until actual deletion succeeds and remain visible in cleanup diagnostics.

Expiry/history pruning first commits the smaller authorised root set with exact current-head/candidate preconditions, then schedules unreachable-byte GC; it does not delete a candidate file out from under an unchanged manifest.
Keep current acknowledged disk roots and active/protected recovery; under pressure first reclaim proved orphan/staging/expired-unprotected history, never silently drop required roots to make a success receipt fit.
If no safe reclamation fits the budget, reject/defer optional store work and report persistence pressure/degradation while source analysis remains correct.
The approved default has no fixed disk quota; this does not authorise automatic quarantine deletion, increasing a configured quota, changing retention or bypassing effective technical bounds.

### Milestone 6: Clear, Repair and Administration

Administrative requests belong to a trusted host/store-management binding, not persisted input or a sixteenth source/scheduling operation in `jai-cache-interface/1`.
Their logical schema is `StoreMaintenanceRequest {version:bytes, store_namespace:bytes, expected_commit:Optional(StoreCommitID), damage_fingerprint:Optional(bytes), action:StoreMaintenanceAction, quarantine_epochs:[]u64, host_confirmation:bytes}` with version `jai-cache-store-admin/1`.
`StoreMaintenanceAction` is `INSPECT. | CLEAR_HISTORY. | CLEAR_RECOVERY. | CLEAR_ALL. | REINITIALISE. | DELETE_QUARANTINE`.
`quarantine_epochs` is empty except for `DELETE_QUARANTINE`, which requires a nonempty strictly increasing duplicate-free list of positive epochs bounded by `StoreLimits.elements`; derive only fixed contained quarantine names from those epochs and bind the exact list into confirmation.
The host confirmation is action/namespace/precondition-bound; a source-controlled configuration, filename or cached token cannot authorise loss of recovery data.
`StoreMaintenanceOutcome` is `{state:NO_CHANGE|COMMITTED|PARTIAL|REJECTED, receipt:Optional(StoreCommitReceipt), cleanup_complete:bool, quarantine:[]PathValue, diagnostics:[]ServiceDiagnostic}`.
These are bounded caller-owned values.
A process-visible receipt is not a power-loss/durable-erase acknowledgement, and a root commit with failed physical deletion reports `PARTIAL` with its receipt and `cleanup_complete == false`.

`INSPECT` runs read-only under normal owner/pin coordination and reports the supported profile, last validated process commit, corruption/unavailable roots and configured retention/bounds without selecting cached source.
All destructive actions require scheduler `STOPPED`, closed former store jobs, no file/read pins and no remaining session/child registration depending on the store owner; otherwise reject without changing it.
Acquire fresh exclusive ownership/epoch before offline maintenance, and hold it through precondition validation, commit/reconciliation and cleanup.
For a valid head, require `SOME` expected commit exactly matching it; for a damaged/missing head, require a matching `damage_fingerprint` computed over the bounded exact bad bytes or the canonical missing-head marker, plus explicit reinitialisation confirmation.
The fingerprint is `K("store-damage", [store_namespace, V(MISSING)])` for a missing head or `K("store-damage", [store_namespace, V(PRESENT {head_bytes:bytes})])` for exact bounded head bytes; unreadable/oversized bytes cannot be fingerprinted by truncation and require rejection or separately authorised external administration.
An unrelated newer head or changed damage observation rejects; do not reinterpret it as permission to clear the newly observed state.

| Action. | Exact mutation/retention contract. |
| --- | --- |
| `CLEAR_HISTORY`. | Commit an empty history list while preserving all current disk/recovery roots and their ordering; then collect only proved unreferenced records. |
| `CLEAR_RECOVERY`. | Commit stamped empty recovery slots under explicit maintenance origins while preserving current disk roots; historical overlay roots are also removed, so history cannot silently reoffer discarded candidates.  It neither changes an editor buffer nor acknowledges a save. |
| `CLEAR_ALL`. | Commit an empty document/history manifest under the same trusted descriptor/namespace, then collect unreferenced managed records.  Keep `owner.lock` and identity-authority state; future provider source capture is still authoritative. |
| `REINITIALISE`. | Preserve the old head/descriptor/blob tree in quarantine before installing a new empty descriptor/manifest/head from trusted configuration.  Never guess roots from corrupt metadata; require explicit acknowledgement that quarantined recovery is not automatically usable. |
| `DELETE_QUARANTINE`. | Delete only the explicitly confirmed, verified-contained quarantine set while no pins/jobs depend on it; unknown recovery-loss risk must be acknowledged, not inferred from age or quota pressure. |

Quarantine uses `quarantine/<maintenance-epoch>/` with the same checked 16-digit uppercase epoch spelling and fixed original entry names; add no raw source path or host-supplied child filename.
Quarantined bytes are diagnostic/recovery-preservation data, not active roots to decode automatically, source authority or a normal hit; keep them charged against disk/file limits until explicit deletion succeeds.
Offline reinitialisation keeps the stable root/owner lock in place, moves the old head out before moving old descriptor/blob/staging entries, and does not release ownership between steps.
Only handle-verified contained entries may move; a suspicious reparse/link is reported and left untouched rather than followed into another directory.
Install the new valid descriptor/head only after the preserved old set is accounted for.
If capacity or a move/install fails, report `PARTIAL`/`REJECTED` as appropriate and retain the surviving old/quarantined data without automatic deletion.
An interruption with no valid head leaves an incomplete store requiring explicit repeat inspection/authorisation; the next opener must not invent a committed empty state.
Automatic repair is `DISABLED`; a corrupt record may cause a cache miss/fresh parse, but repair/reinitialisation, recovery deletion and clearing never happen as hidden side effects of that fallback.
Disable is not clear: while disabled perform no store access, and require explicit separate enable/maintenance to inspect or remove previously stored private data.
All deletion is best-effort removal from this managed store, never secure erasure from filesystem snapshots, backups or other host copies.

### Store Acceptance Trace Drafts

These are future executable C2-C4 qualification cases.
Use independently encoded expected bytes/roots, external commit/source/ownership ledgers and barrier/crash controls; the store's own manifest/GC implementation is not its test oracle.

| Trace. | Required assertions. | Discriminating workload and independent oracle. | Negative control that must fail. |
| --- | --- | --- | --- |
| S1: Bounded decoding. | Reject oversized/truncated envelopes, overflowed lengths/counts, invalid IDs/ranges, wrong schemas/context and unresolved dependencies before unsafe allocation/dereference; release partial storage and compare fallback with fresh source. | Empty/arbitrary bytes; 63/64/65-byte chunk boundaries; all scalar/optional/record arms; invalid version suffix/CR/BOM/comments/hex/count/order/trailing data; exact and one-over limits.  An independent strict encoder/decoder and allocation ledger verify exact bytes and complete rollback. | Normalising with `Text_File_Handler`, trusting declared sizes, accepting a duplicate/reordered field or decoding before bounds/checksum lets an invalid frame through. |
| S2: Interrupted publication. | Interrupt at staging, artifact-install, manifest-write and manifest-replacement boundaries.  A fresh reader selects a complete old/new generation or explicit recoverable fault, never a partial/mixed state. | Interrupt before first head and around every blob/manifest/head staging/install/replace/receipt step; independently read raw files in a fresh process and compare complete commit/required-root sets.  Report process-kill coverage separately; power loss is excluded (R8). | Treat an installed orphan as committed, blindly retry an uncertain commit, invent an empty state after partial first initialisation or set a durable frontier from process visibility. |
| S3: Competing slot updates. | Interleave complete disk/recovery projections under one owner and retry an uncertain commit.  Successful publication preserves both branches; an older sequence/writer cannot replace a newer recovery/tombstone.  A second process/session is denied ownership, not qualified as a concurrent publisher. | Interleave old/new full projections, `ACK_SAVE` racing a newer byte-identical overlay, reset tombstones, same-sequence conflicts and stale-owner jobs.  An external accepted-event ledger computes both expected branches; a real second opener must fail exclusivity. | Merge by file timestamp/provider-token lexicographic order, let old recovery overwrite a committed tombstone or permit two owners. |
| S4: Reader versus GC. | Pause one owner's read job around manifest selection/pinning/file access while its collector runs.  Pin-before-open protects required backing and copied output; a second process is denied ownership before collection rather than exercising unsupported cross-process leases. | Barrier manifest selection, pin creation, open/read/owned-copy transfer and GC marking/deletion; poison/remove producer backing after copy.  Independent pin/file/free ledgers prove no protected file deletion or borrowed-data escape. | Pin after releasing coordination, reopen a retired path lazily, collect an unvisited mark tail or pretend a second-process collector has a live lease. |
| S5: Corrupt roots. | Corrupt the manifest or make a live lease indeterminate.  Fresh source remains usable, collection retains uncertain candidates, and repair never silently guesses/deletes their roots. | Damage head/descriptor/references, exceed enumeration bounds and introduce unsafe links; compare before/after file/root inventory and preserved recovery/quarantine.  Explicit repair requires a matching damage observation and host action. | Guess roots from blobs, auto-reinitialise a nonempty broken store, delete unknown quarantine for quota space or follow a reparse redirect. |
| S6: Failed discard commit. | Confirm host discard/reset, deny metadata writes, then restart.  In-memory selection followed the host, failed cleanup was reported, and surviving recovery remains only a candidate requiring new host confirmation. | Accept reset/discard, deny commit writes, restart and inspect offers; compare live source selection and old committed recovery separately.  Repeat with producer/profile change and missing candidate/context records. | Claim durable removal on failed commit, autoactivate an orphan, suppress valid copied recovery merely because the old producer is unavailable, or restore without current host/context admission. |
| S7: Pressure and disable. | Hold world/recovery pins while exceeding the configured budget, then disable persistence.  Report protected pressure/degradation without false durable success or source failure; no further store access occurs while disabled and prior `data` is not falsely reported deleted. | Hold read/transaction/recovery pins at quota, expire only explicitly eligible roots, fail deletes, disable, then explicitly maintain/re-enable.  External file/I/O/accounting logs prove bounded usage/retention, complete diagnostics and no hidden disabled-store access. | Revoke a pin, silently prune active recovery, omit staging/quarantine from quotas, equate disable with clear, or claim secure erasure. |
| S8: Namespace and permission failure. | Supply unsafe keys/out-of-store redirects, foreign namespace/version data and denied paths.  Reject or miss with cache diagnostics, never escape the store, modify editor source or launch a compiler. | Foreign namespaces/versions, forged maintenance actions/commit preconditions, denied private paths, root replacement and required-but-unqualified durability.  Independently monitor touched paths/processes and require correct in-memory fallback with no source writes/compiler launch. | Trust a source-controlled token, adopt an unrelated directory/head, weaken requested durability, use an unsafe copy/delete replacement or clear the epoch issuer. |

### Milestone 6: Closure and Review Checks

Milestone 6 is complete as a draft initial persistence specification on 2026-10-22.
It specifies the canonical text grammar, seven record kinds, twelve finite store bounds, trusted policy binding, exclusive ownership/native primitive requirements, immutable-blob/atomic-head publication, independent source/recovery slot ordering, bounded read pins/GC, recovery offers and explicit clear/repair/quarantine.
The supported initial catalogue stores exact source/context/document/recovery metadata and reparses selected bytes; optional AST/semantic persistence remains unsupported, not an unfinished implicit codec.
It applies the R2/R6/R8 decisions; S1-S8 above carry its discriminating controls.

Remaining gates are unresolved policy/profile/API review, documented effective safety bounds and issuer/native adapter assumptions, and real S1-S8 tests of our concurrency/interruption/failure handling.
The selected scope does not require independent certification of the OS/filesystem/volume/issuer; our code must respect the documented nonreuse/locking/replacement assumptions, handle failed calls and avoid unsupported durability claims.
Milestone 7 supplies whole-system acceptance/workloads/oracles as a draft; milestone 8 must review the cross-contract/policy/claim boundaries before sign-off, without adding unsupported sharing/derived-artifact guarantees.
No store acceptance trace, power-loss claim, scope/performance approval, or migration gate is marked complete by this draft.

## Semantic Identity and Dependency Contract Draft

Drafted 2026-10-20.
**R5 direction approved 2026-10-21; detailed schemas/algorithms remain proposed and unimplemented.**
This refines the eventual semantic extension using E1-E8; it does not add semantics to the proposed syntax-first initial slice or qualify the current resolver as a cache-backed typechecker.
Milestone 4 below specifies allocation, restart continuity, conservative matching, typed parameter/context encodings and semantic query/dependency/unsupported-state boundaries.
API approval and executable qualification remain open; no language-specific semantic rule or stage implementation is enabled by the draft.
The following records are logical obligations, not public API names or a compiler-internal pipeline claim.

### Identity and Revision Separation

| Identity boundary. | Proposed rule. |
| --- | --- |
| Configured module instance. | Include resolved source plus validated compiler-compatible import-request distinctions, ordered explicitly supplied typed module arguments, and effective program/target settings.  Do not merge omitted versus explicit defaults, reordered arguments or path aliases merely because effective values/bytes match; preserve E2/E4 distinctions until a rule is qualified. |
| Loaded declaration occurrence. | Distinguish each semantically relevant load occurrence and its source-visible/resolution context inside the owning module instance.  A shared physical syntax snapshot does not deduplicate repeated declarations, module-private state or nominal types. |
| Declaration identity. | Identify a declaration within its configured instance/occurrence and logical owner.  Keep a separate declaration revision for its selected syntax/context.  Name, byte span, syntax hash and allocator address alone are insufficient. |
| Cross-edit matching. | Retain a logical declaration identity only after a specified unambiguous match within compatible ownership/context.  Reordering/moves, overloads and identical anonymous declarations need explicit rules.  Uncertain matches get fresh identities and conservative misses, not guessed continuity. |
| Nominal and instantiated types. | Root nominal identity in the owning declaration identity and configured instance; keep revision-dependent type facts separate.  Instantiations include validated typed argument identities/values and relevant context, not display names or a layout hash.  Structural layout equality cannot merge distinct nominal types. |
| Struct and completed-context member comparison. | Ordinary struct member descriptors, including `Context_Base`, preserve source order.  Completed `#Context` compares that ordered base plus canonical order-independent `#add_context` fields as defined in [architecture section 6.3](CACHE_ARCHITECTURE.md#member-order-and-the-completed-context-type); compiler encounter order is not logical context identity.  Layout/reflection/initialisation facets require their own observations. |
| Query and task. | A logical query key includes operation/version, subject, explicit arguments and semantic context.  In-flight work additionally captures the selected world; a new world's request cannot accidentally join computation over old inputs.  Cross-world result reuse requires validation rather than equal logical keys alone. |
| Persisted identity. | Encode logical identities/revisions with a versioned schema and validated reference graph.  Restart reconstructs fresh live handles; uncertain cross-restart matching is a miss.  Do not persist pointer identity, occupied pool slots or session allocation generations as semantic identity. |

A retained old world keeps its original identities, revisions and lookup views even when a new world chooses different matches.
Matching identifies the logical subject; it does not certify that its old result remains valid after an edit.
The provider's explicit admitted path/alias policy remains a host configuration input, not a hidden default.
Milestone 4 below supplies typed-value canonicalisation, conservative declaration matching and persisted-versus-live ID allocation/validation; approval and implementation qualification remain separate.

### Milestone 4: Allocation and Restart Continuity

Draft identity contract `jai-cache-identity/1`, completed for review under R5, not implementation or store-policy approval.
This section fixes the allocation/continuity rules left open by the logical keys in milestone 3.
K/V retain their exact existing framing.
Full descriptors and their authority bindings remain equality evidence; matching digests, source text, paths or allocator addresses cannot establish an allocated subject's identity.

#### Live Identity Allocation

The service bootstrap binds one `IdentityAuthority` record `{authority_namespace:bytes, issuer_schema:bytes}` to a trusted host issuer.
The namespace is nonempty, nonreassigned host authority, not a workspace display path or cache-directory name.
Its initial issuer schema is `jai-cache-epoch-issuer/1`.
The host hook `ReserveEpoch(authority_namespace) -> RESERVED {epoch:u64} | UNAVAILABLE` reserves a positive, strictly increasing epoch before returning it, exclusively across all service processes sharing that authority.
A returned epoch is never reissued, including after crash, aborted startup, cache clearing or restore of an older cache backup.
Persistent reservation may be supplied by the host's existing durable authority; this contract does not choose a cache file, writer policy or filesystem commit primitive.
An issuer unable to prove reservation returns `UNAVAILABLE`, never an old epoch, timestamp, process ID or probabilistic substitute.
Bootstrap/`OpenSession` then fails `ADMISSION_DENIED`/`CONFIGURATION_REQUIRED` without exposing a session.
Native reservation/locking qualification is an implementation obligation, coordinated with milestone 6, not performed by writing this contract.

`service_incarnation_namespace = K("service-incarnation", [authority_namespace, epoch_u64_LE])`.
Each successful service bootstrap obtains a new epoch even if no session was opened.
Within that incarnation the service owns independent positive `u64` monotonic counters for `SESSION`, `WORLD`, `RESULT` and `OPERATION`.
A token in the existing session/world/result/operation K recipes is exactly that counter's eight little-endian bytes; `SESSION` uses the incarnation counter, and child domains use separate counters within their `SessionID`.
Start at 1, issue once under coordinator ownership, never decrement/recycle, and retire the allocator at `0xFFFFFFFFFFFFFFFF` rather than wrap.
Failed/staged allocations may burn numbers; gaps do not imply accepted work.
Exhaustion rejects new allocation with `ADMISSION_DENIED`/`RESOURCE_EXHAUSTED` before source acceptance, and cannot overwrite an old registration.
This chooses allocation semantics, not the coordinator's thread/locking implementation.

| Identity domain. | Allocator, scope and non-interchangeability. |
| --- | --- |
| `SessionID` | Fresh `SESSION` counter under one service incarnation; independent of `WorkspaceID` and persisted artifacts.  Closing/reopening the same workspace in the same process still creates another `SessionID`. |
| `WorldID`, `ResultID`, `OperationID` | Separate session-local counters and the milestone-3 typed K recipes.  Equal numeric tokens across domains/sessions are distinct.  Retry at the same frontier gets a fresh `OperationID`, and exact result reuse never imports a foreign `ResultID` into the requesting session. |
| `ClockIdentity` | `K("service-clock", [service_incarnation_namespace])`, bound to that service's actual monotonic clock and returned as `Capabilities.clock_identity`.  It is not comparable to another incarnation's clock or wall time. |
| `ProviderRevision` | Nonempty provider-issued state token scoped by provider namespace, `SessionID` and `DocumentID` as already keyed.  The registered provider must attest nonreassignment and the exact disk/overlay state.  A new combined state uses a new token even with equal bytes; the overlay installation stamp remains the earlier installing `ProviderRevision` until replaced/cleared. |
| `ProviderFrontier` | The registered provider/coordinator issues a fresh nonempty frontier token for the empty initial state and every accepted transaction.  Its accepted predecessor relation is coordinator state, not lexicographic token order.  Rejection and `RequestAnalysis` do not advance it. |
| Live handle registration. | Scope is `SessionID` plus kind/slot/generation.  Slots are zero-based; a fresh slot starts at generation 1.  A new independent registration in a reused slot increments its generation; retired generations never return, and wrap retires the slot permanently.  Token allocation and slot reuse are separate counters; neither proves payload equality nor authorises adopting persisted handles. |
| Payload-local IDs. | Dense zero-based IDs in their protected result/backing and distinct node/helper/token/recovery/entry/region domains.  They are not allocated `DeclarationID`/`TypeID` values, and matching an old node to a new node cannot make bare IDs portable. |

Workspace/provider/document namespaces continue to come from the responsible host/provider, not the service's session allocator.
A caller cannot choose another authority merely to reinterpret an existing key: namespace changes create a new binding and conservative misses.
The service validates the complete owner/session/domain before slot access, then generation and liveness.
`SyntaxKey = K("syntax", [DocumentID, SourceRevision, ContextID])`; the context already binds the exact parser/lexer/adapter/schema/profile configuration and source-visible occurrence paths.
`SyntaxArtifactKey = K("syntax-artifact", [SyntaxKey, query_kind_ASCII, payload_schema_ASCII, canonical_observation_descriptor])`.
The observation descriptor contains the complete registered payload/backing observations, completeness and diagnostic summary, excluding live world/result/operation/handle associations.
Those associations are recreated for the requesting world after validation; they are not restored from an artifact key.
`ArtifactKey` is the domain-separated union of `SyntaxArtifactKey` and `SemanticArtifactKey`, not one digest shared across source and semantic record kinds.
Collision/contradictory evidence is quarantined as invalid input/artifact or rejected conversion; never silently merge two known unequal descriptors sharing a digest.
A process cannot use an untrusted manifest as an `IdentityAuthority` or a request for a particular live token.

#### Restart and Reuse Admission

`ContinuityProof` is `{workspace:WorkspaceID, provider_namespace:bytes, document_policy_version:u32, provider_descriptor:bytes, document_bindings:[]DocumentBinding}` supplied by the trusted host/provider for the current opening.
The descriptor is the exact canonical milestone-3 provider descriptor, and bindings are duplicate-free in canonical `DocumentID` order.
This is an admission attestation, not an authentication token self-certified by cache contents.
An omitted, unverifiable or unequal field means fresh binding/no identity continuity for that scope; it does not authorise best-effort matching by path.
Availability of the host's authority channel is separate from source hashes and cache integrity.

Validate restart candidates in this order: supported schema/framing/bounds; host-confirmed workspace/provider/policy continuity; exact relevant document bindings; source bytes or confirmed absence from the authoritative current capture; exact context/producer/adapter tuple; then the artifact's references/dependencies and payload validation.
A failure gives a miss or the explicit source/service outcome, not a resurrected handle.
Validated source artifacts may be reparsed under fresh live identities; persistence of syntax does not require persistence of an AST graph.
The service incarnation, all `SessionID`/handle registrations, provider combined-state revisions/frontiers and overlay installation stamps are newly established.
Old stamps remain historical observation data only, never the expected base of a new session's batch.
Host-confirmed `RESTORE_OVERLAY` installs a new current stamp; a recovery candidate cannot confirm its own activation.

`DocumentID` and source/context descriptors can remain equal across restart only under their already specified authority/equality rules.
`WorldID`/`ResultID`/`OperationID` never continue across sessions.
Deferred `DeclarationID`/`TypeID` continuity additionally requires the semantic archive validation below, not merely this source continuity proof.
Unavailable/corrupt archives do not make authoritative source unavailable.
Required source/recovery persistence, disabled/degraded store behaviour and reset/discard policy remain R2/R6 and milestone 6; none may reset a nonreassignment authority or turn a candidate into current source.

### Milestone 4: Declaration Matching and Semantic Keys

This is the deferred semantic identity schema `jai-cache-semantic-identity/1`, not a `DeclarationID` field added to declaration-index/2.
Its record schema identifiers are that ASCII prefix followed by `/` and the exact case-sensitive record name, unless a separately named schema or explicit K recipe is given; typed values use `jai-cache-typed-value/1`.
Parameterised type identifiers retain milestone 3's framed parameterised-type recipe, with no ambiguous concatenation or open extension fields.
The syntax-first API still publishes only result-local syntax/index references.
A future admitted semantic producer owns the following immutable records; no current resolver or parser node pointer is implicitly that producer.

#### Subject Allocation and Ownership

At each semantic-producer activation, reserve a fresh epoch through the same trusted issuer and define `AllocationNamespace = K("semantic-allocation", [authority_namespace, epoch_u64_LE])`.
Newly allocated `DeclarationID` values are `K("declaration", [AllocationNamespace, positive_counter_u64_LE])`, with the same nonreuse/exhaustion rules as live counters.
The declaration counter is scoped to that allocation namespace.
Owner identity is validated in the immutable binding record rather than recursively encoded into the allocated token.
This avoids recursive keys and permits references to a nominal identity before its body/layout exists.
An ID never changes owner just because its token's bytes omit that owner.

`DeclarationBinding` is `{declaration:DeclarationID, module:ModuleInstanceID, occurrence:LoadOccurrenceID, owner:ROOT|DECLARATION {id:DeclarationID}, role:DECLARATION|COMPOUND_BINDING|ENUM_MEMBER|PARAMETER|RETURN_SLOT|GENERATED, syntax:SemanticSyntax, revision:DeclarationRevision}`.
`SyntaxOccurrence` is `{document:DocumentID, source_revision:SourceRevision, context:ContextID, backing_identity:bytes, node_id:u64, binding_ordinal:s64}`.
`binding_ordinal == -1` means not set; a set ordinal is nonnegative and range-checked against the authored binding list, and values below `-1` reject.
`backing_identity` names the protected semantic producer's exact source graph/numbering association, not a freestanding query result chosen by equal source hash.
Compound bindings require their authored ordinal; independent bindings and repeated names are not merged.
The source graph and all referenced identities remain protected by that semantic world's lifetime.
Generated syntax additionally requires the provenance contract below and never pretends to be a source declaration-index entry.

`SemanticSyntax` is `SOURCE {occurrence:SyntaxOccurrence}` or `GENERATED {provenance:bytes, output_ordinal:u64, backing_identity:bytes, node_id:u64}`.
The `GENERATED` arm references the exact canonical `GeneratedProvenance` key and its checked output ordinal, never an authored `DocumentID` or fabricated `SOURCE` span; its source revision/context come from the protected generated output's separately admitted source/origin schema.
`DeclarationRevision = K("declaration-revision", [DeclarationID, SourceRevision, ContextID, V(SemanticSyntax, syntax), canonical_source_projection, semantic_producer_binding])`.
`canonical_source_projection` contains the exact registered authored subtree observations and qualified declaration-route/metadata evidence, not semantic mutation or allocation addresses.
A retained declaration can therefore keep its `DeclarationID` while its source mapping/revision changes.
Equal IDs do not validate old type/body/diagnostic facts.
Duplicate bindings assigning one ID different owners or independent occurrences in the same world reject publication.
Out-of-range/cross-backing references fail validation rather than being repaired by matching source spans.

`TypeID` has exactly three identity families: `NOMINAL {declaration:DeclarationID}`, `BUILTIN {type_profile:bytes, name_ascii:bytes}`, and `INSTANTIATED {definition:DeclarationID, arguments:[]TypedArgument, specialisation_policy:bytes}`.
Their canonical forms are K with tags `nominal-type`, `builtin-type`, `instantiated-type` and fields in the written order, using V for the typed argument sequence.
Builtin names resolve under the exact registered type profile; no universal host ABI is assumed.
Structural, pointer, procedure, context and other language types require an explicitly registered type-profile descriptor, represented only as `TypedTypeRef` below; unsupported type families return `UNSUPPORTED` rather than being merged by size or display name.
Type facts/revisions/layout keys additionally bind `SemanticContextID` and observed dependencies; `TypeID` equality alone is not fact validity.

#### Deterministic Conservative Matching

Matching is a partial, one-to-one mapping from a selected predecessor semantic world to a candidate successor.
It is never a mutation of the predecessor.
`MatchRecord` is `{old:Optional(DeclarationID), new:DeclarationID, disposition:REUSED|FRESH, reason:EXACT_CONTINUATION|UNIQUE_UNCHANGED|NEW_SUBJECT|OWNER_CHANGED|CONTENT_CHANGED|ANONYMOUS|AMBIGUOUS|EVIDENCE_UNAVAILABLE}`.
`REUSED` requires `SOME` with old == new and one of the first two reasons; `FRESH` requires a newly allocated ID, `NONE` and one of the remaining six reasons, not an arbitrary guessed predecessor.
Fresh reasons are cache bookkeeping, not source-language diagnostics.

1. Admit a predecessor only with equal workspace/provider/document policies, semantic producer/compatibility profile, configured `ModuleInstanceID` and `LoadOccurrenceID`.
Match owners outer-before-inner through the registered authored ownership graph.
Different instances, load occurrences, generated provenance or unmatched owners cannot share declaration identity through this algorithm.
2. For an exact continuation, reuse an already validated complete association table only when the entire selected source/context and protected canonical syntax graph association are equal.
Validate every binding/reference and role, not merely a source digest or equal local node numbers.
This may preserve anonymous/unnamed slots in the same graph.
Repeated queries and restoration of a validated archive can take this path; a fresh parse with unverified numbering cannot.
3. Otherwise, form candidates only for named, safely mapped, non-generated declarations beneath the same matched logical owner and the same declaration role.
Candidate equality requires exact producer-name bytes and name form, exact source subtree bytes, and equal canonical authored syntax/route/metadata/recovery observations after replacing local IDs with their registered relative owning paths and replacing absolute locations with checked subtree-relative positions.
References leaving the subtree must target the same matched logical owner/qualified alias or disqualify the candidate.
No unchecked raw-pointer, span-only, token-count or text-hash match is permitted.
Compare full bytes/records after a fingerprint shortlist.
4. Group equal candidates within that owner, ignoring list position.
Reuse only when there is exactly one predecessor and exactly one successor candidate in the group.
A unique unchanged declaration can survive an insertion/reordering in the same owner; moved declarations under another owner, renamed/edited bodies, identical duplicates and anonymous/unnamed slots receive fresh IDs.
A new duplicate makes the whole ambiguous group fresh, even if one range happens to be unchanged.
Never use a longest-common-subsequence tie-break, nearest span, allocator reuse or old ordinal to choose an ambiguous identity.
5. Install the new immutable binding/revision table only after all matches are injective, owner-compatible and reference-valid.
Recompute descendant matches only under matched owners; if an outer declaration changed and became fresh, all descendants become fresh in this baseline.
Pure insertions/reorders that leave the outer declaration's full subtree different can therefore conservatively lose its identity.
No body-edit continuity is promised.
A future finer matching policy needs a new policy binding and independent qualification.

Partial index coverage is not evidence that the semantic declaration set is complete.
Missing name/route/owner/recovery evidence prevents a match, never certifies that an old subject disappeared.
Removal from the successor cannot invalidate an old world's retained bindings.
Fresh cache IDs due to uncertainty are not proof of language-level type inequality or assignment incompatibility across worlds.
Within a supported same-world language rule, nominal equality must come from the qualified semantic producer; when that proof is absent the extension returns an explicit unproven/unsupported outcome, not false type errors.

#### Typed Arguments and Configured Instances

`TypedTypeRef` is `{profile:bytes, descriptor:bytes}`; descriptor is a canonical registered type-profile record, which may reference the `TypeID` families above.
It includes nominal identity and required type parameters/qualifiers, never only a display name or byte size.
Unknown profiles/recursive descriptor encodings are unsupported; legal recursive nominal references use allocated `DeclarationID`/`TypeID` references, not infinitely nested structural keys.
No arbitrary pointer-valued compiler `Type_Info` bytes are encoded.

`TypedArgument` is `{name:Optional(bytes), type:TypedTypeRef, value:TypedValue}`.
Explicit arguments retain authored argument order and membership, including named-argument order; `NONE` name differs from an explicit name.
Binding/default evaluation is validated separately.
`TypedValue` is the following closed transport/equality observation union under `jai-cache-typed-value/1`:

| Arm. | Exact payload and restriction. |
| --- | --- |
| `BOOL` | `{value:bool}` with its registered `bool` type. |
| `INTEGER` | `{signed:bool, bit_width:u32, little_endian:bytes}`.  `bit_width` is positive, byte count equals checked `(bit_width + 7)/8`, signed values use two's complement, and unused high bits are zero for unsigned or sign extension for signed.  The type profile fixes width/signedness; no decimal string or minimal-byte ambiguity. |
| `FLOAT` | `{format:BINARY32|BINARY64, little_endian_bits:bytes}` of exactly four/eight bytes.  Preserve every bit, signed zero and NaN payload; semantic/compiler argument equivalence still needs its qualified policy, not host floating-point ==. |
| `BYTES` | `{value:bytes}` with the registered string/byte-sequence type and exact bytes, including empty/non-UTF-8 values. |
| `TYPE` | `{value:TypedTypeRef}`.  Types are identities/descriptors, not source-spelling strings. |
| `ENUM` | `{type_identity:TypeID, representation:TypedValue(INTEGER)}`; aliases retain their actual typed value, and named spelling is not a new nominal identity. |
| `AGGREGATE` | `{components:[]TypedArgument}` under the type profile's declared member/element order, preserving names and nested types.  Do not sort ordinary struct fields or inspect padding. |
| `SUBJECT` | `{declaration:DeclarationID}` only where the registered parameter profile admits a declaration/procedure identity value; not an address to compiled code. |
| `SESSION_LOCAL` | `{session:SessionID, token:bytes}` for a producer-owned uncanonicalisable identity/effect value.  Nonempty token is nonreassigned in that session; it is never persistable or equal across sessions. |

These encodings preserve observations; they do not define Jai comparison operators or prove that every arm is an admissible compile-time module argument.
A profile must qualify canonical argument equivalence before using values to establish a language instance/type equality.
An unsupported/noncanonical value may produce a session-local, explicitly nonpersistable result only if the semantic profile supports it; otherwise return unsupported.
No hidden evaluation is performed merely to build a key.
Integer widths, aggregate counts/depth and canonical key sizes obey the existing explicit limits, with overflow checked before `(bit_width + 7)` or allocation.
No pointer, evaluator effect, resource handle or lossy printed value silently becomes a persistent key.

`ImportRequestIdentity` is `{compatibility_policy:bytes, request_mode:ROOT|MODULE_NAME|SOURCE_PATH, request_bytes:bytes, resolution_base:PathValue, resolver_binding:bytes, compiler_request_class:bytes}`.
Preserve the exact request bytes observed by that compiler policy, not a rewritten canonical path or import alias variable name.
`compiler_request_class` is the canonical class record produced by the registered, independently qualified compiler-compatibility adapter; it cannot be an arbitrary caller label.
The adapter must establish both required distinctions and permitted sharing under E2/E4.
Unknown grouping returns unsupported; different conservative cache keys alone cannot prove language-level nominal incompatibility.

`ProgramSettings` is `{program_identity:bytes, targets:[]ProgramTargetSettings}`; `ProgramTargetSettings` is `{module_target:bytes, explicit_arguments:[]TypedArgument, effective_arguments:[]TypedArgument, configuration_site:SyntaxOccurrence}`.
`program_identity` and `module_target` are service-verified canonical records under the compatibility policy.
Targets have set semantics, sorted by complete `module_target` bytes; duplicate target configuration rejects even with identical values.
Argument sequences preserve their declared order.
Main-program authority and per-module applicability are validated before any instance cache hit; an imported module cannot set its child's program parameters.
Default-expression/source/evaluation dependencies remain required even when effective argument values match.

`EffectiveModuleProgramKey` is `{program_identity:bytes, module_target:bytes, explicit_arguments:[]TypedArgument, effective_arguments:[]TypedArgument}` from the validated `ProgramSettings`/`ProgramTargetSettings` pair.
The `configuration_site` is required validation/dependency provenance but is deliberately excluded from that identity key: moving a configuration site or changing its source revision alone must not manufacture another module instance.
`program_identity` is a service-verified canonical host-program binding under the compatibility policy, stable for the selected program lineage rather than a freshly issued `WorldID` or an unchecked caller label.
`ModuleInstanceID = K("module-instance", [compatibility_policy, resolved_DocumentID, V(ImportRequestIdentity, request), V(Sequence(TypedArgument), explicit_module_arguments), V(EffectiveModuleProgramKey, effective_module_program_settings)])`.
The compatibility policy validates the program target's applicability; unrelated modules' same-named parameters are not merged.
Separate instance revisions bind selected source/context and dependencies; including settings in identity does not validate their current inputs.
Root module creation uses `request_mode` `ROOT` with empty `request_bytes` and the registered explicit `ROOT` request class, never a forged import string; imported modes require a nonempty validated request.
The same module request may share an instance only after the compatibility adapter proves equivalence; omitting arguments, explicitly supplying defaults, changing argument order/mode/spelling or relevant resolution base must not be erased without qualification.

`LoadOccurrenceID = K("load-occurrence", [ModuleInstanceID, parent_occurrence_or_ROOT, load_site_identity, loaded_DocumentID, ContextID])`.
A load site's identity is its matched `DeclarationID` when it is a qualified declaration occurrence, otherwise an allocated source-site token under the same conservative matching policy; it is never just a token offset.
Repeated loads, diamond paths and two sibling sites have different occurrence paths even when bytes match.
Root is `K("load-root", [ModuleInstanceID, DocumentID, ContextID])`, not an omitted/null parent.
Cyclic load discovery must expose unresolved graph edges under the cycle contract, not recursively expand an unbounded key; if a finite qualified occurrence graph cannot be constructed, the requested semantic operation is unsupported.
Moving or ambiguously matching a load site creates a new occurrence and fresh descendant declaration identities.

`SemanticContextID = K("semantic-context", [semantic_schema, module_instance, load_occurrence, target_descriptor, type_environment_descriptor, resolver_descriptor, language_profile, compiler_and_semantic_producer_binding, program_configuration_descriptor, evaluator_policy_descriptor])`.
Every descriptor is a complete registered canonical value, not a digest-only claim.
Target includes architecture/ABI/data layout and language-relevant target options; type environment includes the nominal/type-profile bindings actually supplied.
An unavailable required descriptor prevents semantic reuse; do not reuse the syntax-only `ContextID` or ignore a changed target because the source bytes match.
The completed `#Context` descriptor retains the ordered base and canonical name-sorted additions from [architecture section 6.3](CACHE_ARCHITECTURE.md#member-order-and-the-completed-context-type), with duplicate/conflicting additions rejected and incomplete discovery explicitly incomplete; layout/reflection/effect ordering remain separate facets.

### Milestone 4: Deferred Semantic Query and Archive Boundary

The supported initial semantic query catalogue is empty.
`SEMANTIC_QUERY` and `COMPILER_EVALUATION` still return `UNSUPPORTED` before task creation under interface/1, and syntax-context/1 still has exactly `semantic_extension` = `UNSUPPORTED`.
The records below specify the future extension boundary; registering a descriptor-shaped string is not authorisation to enable semantics, change the fifteen operations, or bypass a separate profile/API review.
Semantic admission needs a new context schema that supplies every field above, a versioned query binding and qualified language rules; no fallback from missing semantics to declaration-index names is allowed.

`SemanticQueryRecord` is `{schema:bytes, implementation:bytes, kind:SemanticFacet, subject:SemanticSubject, arguments:[]TypedArgument, context:SemanticContextID}`.
`SemanticFacet` is the closed reserved catalogue `DECLARATION_SET. | NAME_LOOKUP. | OVERLOAD_CANDIDATES. | NOMINAL_IDENTITY. | SIGNATURE. | CONSTANT_VALUE. | INSTANTIATION. | LAYOUT. | BODY. | GENERATED_MEMBERSHIP. | DIAGNOSTICS`.
`SemanticSubject` is `MODULE {id:ModuleInstanceID}`, `OCCURRENCE {id:LoadOccurrenceID}`, `DECLARATION {id:DeclarationID}`, or `TYPE {id:TypedTypeRef}`.
`QueryKey = K("semantic-query", [V(SemanticQueryRecord, record)])`.
Unknown schema/facet/subject combinations are unsupported, not newly discovered functionality.
Exact language-specific request and payload schemas must be registered before a reserved facet is admitted; this milestone does not claim every Jai rule has been specified.

`SemanticAttemptKey = K("semantic-attempt", [QueryKey, WorldID])`; execution adds its separately checked generation/attempt token under milestone 5.
Equivalent logical queries can share work only within the same immutable selected semantic world/qualified inputs.
Cross-world hits require full dependency validation and a new result association for the requesting world; they do not join an old attempt by `QueryKey` alone.

`DependencyRecord` is `{query:QueryKey, subject:SemanticSubject, facet:SemanticFacet, context:SemanticContextID, observed_revision:bytes, observation:SemanticObservation, validation_world:WorldID, parent_attempt:bytes}`.
`SemanticObservation` is `{schema:bytes, completeness:COMPLETE|PROVISIONAL {blocking:[]QueryKey}, value_descriptor:bytes, source_mapping:Optional(SemanticSyntax)}`; `value_descriptor` is the exact registered immutable canonical facet value, not merely its hash.
The registered revision domain validates `observed_revision`.
Provisional blocking is nonempty and cannot certify a complete missing-name result.
Parent validation stamps and target observed revisions remain separate fields; if downstream propagation stops on equal observations, install the newly validated edge stamps atomically nonetheless.
Payload/dependency/completeness publication is atomic; no partial dependency set escapes a cancelled/failed attempt.
`SemanticArtifactKey = K("semantic-artifact", [QueryKey, producer_binding, V(SemanticObservation, observation), V(Sequence(DependencyRecord), validated_dependencies)])`; dependency sequences preserve first-observation order with repeated reads retained, not locale-sorted or guessed static inputs.
Revision/identity/source-map validation is mandatory even when this key's digest matches.

`GeneratedProvenance` is `{producer_query:QueryKey, producer_revision:bytes, generator_binding:bytes, context:SemanticContextID, inputs:[]DependencyRecord, effects:[]EffectObservation, outputs:[]GeneratedOutput}`.
`EffectObservation` is `{schema:bytes, subject:bytes, observation:bytes}` under an explicitly supported effect tracker; unknown/untracked effects prevent persistent reuse, not an empty complete effect set.
`GeneratedOutput` is `{ordinal:u64, source_revision:SourceRevision, source_bytes:bytes, origin:GENERATED}`; ordinals are dense in producer emission order.
Its provenance key is `K("generated-provenance", [V(GeneratedProvenance, provenance)])`; generated output source/context/origin schemas must be admitted separately before a `GENERATED` binding is supported.
Re-enter syntax/discovery with this protected provenance and a separate origin schema, never spans into an authored source file.
Evaluator trust, permissions and execution limits remain required and unsupported initially.
A failed/compiler-rejected generator cannot publish a successful output prefix.

`CycleObservation` is `{schema:bytes, required_edges:[]CycleEdge, classification:EXTERNAL_PENDING|UNCLASSIFIED|LEGAL_RECURSION|ILLEGAL_CYCLE, rule:Optional(bytes)}`; `CycleEdge` is `{from:QueryKey, to:QueryKey, milestone:SemanticFacet}`.
Actual required unresolved edges are reported in deterministic `QueryKey`-byte order with duplicate edges rejected.
`LEGAL_RECURSION` and `ILLEGAL_CYCLE` require `SOME` registered independently qualified language rule; `EXTERNAL_PENDING`/`UNCLASSIFIED` have `NONE` and cannot manufacture a language error.
Layout by-value cycles, legal pointer recursion and evaluator re-entry cannot be classified from scheduler idleness or a generic recursion depth guard.
This closes the unsupported/rule-admission boundary, not the catalogue of future language recursion rules.

`SemanticArchive` is `{schema:bytes, workspace:WorkspaceID, provider_continuity:ContinuityProof, producer_binding:bytes, compatibility_policy:bytes, declarations:[]DeclarationBinding, matches:[]MatchRecord, artifacts:[]ArchivedArtifact}`; `ArchivedArtifact` is `{key:bytes, query:SemanticQueryRecord, observation:SemanticObservation, dependencies:[]DependencyRecord}`.
Only profiles with canonical, tracked, persistable values may write such an archive.
It is a candidate graph, not live handles or authority to evaluate arbitrary stored code.
Validate all typed references, ownership, one-to-one matches, source/context/configuration proofs and dependencies before reusing identities/results.
Session-local values, stale source mappings and incomplete authority/producer continuity invalidate the affected candidate; independently verified source persistence stays usable.
Nonpersistability propagates transitively through arguments, type descriptors, module/context keys and dependencies; omitting a `SESSION_LOCAL` field to obtain a persistent key is forbidden.
Archived `validation_world`/`parent_attempt` identities are historical provenance, not live registrations to restore or a reason to skip validation against the new requesting world.

Never resume an archived declaration allocator/high-water counter.
A restarted producer allocates new subjects in its fresh `AllocationNamespace`; it may retain individually validated old `DeclarationID`/`TypeID` bindings from the archive, but cannot reissue one as a different subject.
A stale/rolled-back/forked archive therefore cannot make new declarations collide with previously issued tokens.
Conflicting bindings for the same old ID reject that archive scope; do not choose the newest timestamp or reconcile by name.
Full missing/unverifiable semantic continuity creates fresh IDs and conservative recomputation, not an implicit same-owner match.
Archive publication/locking/GC/text encoding remain milestone 6, with no initial requirement to persist these deferred semantic records.

### Milestone 4: Identity Closure and Review Checks

Milestone 4 is complete as a draft identity and deferred-semantic-extension specification on 2026-10-22.
It covers allocation, restart continuity, cross-edit matching and semantic-extension boundaries; it does not reopen the milestone-2 syntax registry.
The initial service still exposes no semantic query implementation or `DeclarationID` in its syntax index.
API review and host issuer qualification remain open.

The draft now fixes live allocation authority/counters/exhaustion; typed source/provider/session versus allocated semantic identities; document/overlay/restart authority; deterministic injective declaration matching; canonical typed arguments and instance/load/target/context keys; nominal type separation; query/world/dependency stamp rules; and archive/generated/cycle nonpersistable or unsupported outcomes.
No initial cache hit is allowed to infer semantic identity from a name, path, source digest, result-local ID or untrusted archived token.
Unknown semantic language behaviour remains explicit unsupported, not an unfinished implicitly enabled algorithm.

| Identity case/independent negative control. | Future acceptance mapping and required oracle. |
| --- | --- |
| Two processes reserve epochs; crash after reservation; restore an older cache; clear the cache; force token/generation exhaustion. | X7/X8, S2/S8, T5/T6.  An independently recorded issuance ledger checks our authority/adapter against the declared nonreuse contract, including locally detectable repeated/invalid responses.  Global nonreassignment is an explicit authority assumption, not something a restored cache can prove about a dishonest issuer; test our logic without external platform certification. |
| Reopen the same workspace with and without host-confirmed provider/policy/source/context continuity. | V2/V4, S1/S2, C2.  Expected equal document/source bindings versus fresh session/live IDs are authored independently; manifests cannot establish authority. |
| Save an older overlay after a newer byte-identical overlay; restore a candidate after restart. | V5/V7, S3/S4.  Check installation stamps independently of content identity; restore creates a new current stamp only after host confirmation. |
| Keep a unique declaration unchanged while inserting/reordering siblings; rename/change a body; move ownership; introduce identical candidates or unnamed slots. | D2, T6.  Hand-authored old/new association tables assert exact reused/fresh IDs and descendant consequences.  Do not use the production matcher as its own oracle. |
| Reparse equal source with different local numbering, or inject duplicate ownership/cross-backing references. | C1/C5, D2.  Require a validated full association or relative-path match; compare full projections and reject corrupt references. |
| Omit versus explicitly supply defaults; reorder named arguments; change request mode/path/base or one module's program configuration. | D1/D6, E2/E4 extension fixtures.  The official compiler/profile establishes language equivalence; key equality alone cannot manufacture it.  Configuration-site relocation alone does not enter module identity. |
| Permute identical #`add_context` additions, change a member/type, reorder the base, duplicate a name or inspect target-sensitive layout. | D1/D6/D8, architecture section 6.3.  Independent logical-member descriptors preserve ordered base/unordered qualified additions; compiler-backed layout/reflection remain distinct or unsupported. |
| Change an observed revision without changing its value, then change it again; use a query with the same `QueryKey` in another world. | D3-D7.  Fresh same-world observations and independently tracked edge stamps detect stale negatives, candidate sets and old-attempt joins. |
| Roll back/fork an archive, inject conflicting old `DeclarationID` bindings, or hide `SESSION_LOCAL` inside an aggregate/type/dependency. | S2/S8, D1/D2/D7.  New allocation uses a fresh namespace; transitive nonpersistability and ownership validation reject unsafe semantic reuse without losing verified source. |
| Supply generated output with authored spans; classify idleness as a cycle; request a reserved semantic/evaluator facet in the initial service. | T8, D8.  Explicit unsupported/unclassified outcomes, no evaluator/task creation or fabricated complete negatives/language errors; qualified future provenance/rule tests remain separate. |

Document-only record/catalogue/reference checks are not executed acceptance cases.
Milestones 5-7 supply execution/ownership, initial store and whole-system requirement/oracle/workload drafts; tests of our native issuer/store adapters and remaining policy/whole-contract approval stay open under the 2026-10-23 external-assumption boundary.
A host's unimplemented durable issuer or a deferred semantic adapter remains unimplemented after this specification is complete.

### Query Records and Observed Dependencies

Every successful reusable computation publishes its protected immutable result together with the exact context and dependencies observed in that captured world.
Proposed dependency records identify the observed subject, facet/query kind, context, observed revision/fingerprint, completeness and dependency-record schema version.
An edge also records the parent's validation state independently of the target's current revision: E7's link-stamp/target-stamp distinction must not collapse into one mutable target flag.
Record dependencies during actual reads, including candidate discovery, missing-name results and configuration reads; a guessed static dependency list is not sufficient.

| Observed facet. | Required dependency and invalidation boundary. |
| --- | --- |
| Scope membership and visibility. | Observe the complete relevant scope/import/load membership and access context, including file/module/export restrictions.  Adding/removing a name or changing visibility invalidates affected successful and negative lookups.  An all-visibility index is not an access-filtered binding result. |
| Overload candidates. | Observe the eligible candidate set as well as facts used to select one candidate.  A new candidate may change the answer even when the previously selected procedure is unchanged. |
| Procedure signature/body. | Separate signature and body results where their inputs permit.  Inferred signatures, defaults, inline/compile-time behaviour, reflection and caller-context operations must observe the body/context they actually use; a body edit is not universally private. |
| Types, constants and layout. | Observe nominal/instantiation identity, field membership/types, constants/conditions, target/ABI and prerequisite milestones.  Equal size alone is not equal type or equal layout semantics. |
| Source locations. | Track source revision and mapping/context independently of reusable semantic values.  A whitespace-only edit may preserve a value while changing the spans needed to display diagnostics or apply edits. |
| Generated membership/evaluation. | Observe conditions, generated syntax and tracked evaluator inputs/effects/provenance.  Incomplete discovery is provisional; unknown effects or unavailable context are unsupported/non-persistable, not a complete stable interface. |

Never cache a definitive negative lookup from a scope whose relevant imports/conditions/generated membership are still incomplete.
If a required observation cannot be represented or tracked, conservatively depend on the whole configured module/context, recompute, or return an explicit incomplete/unsupported result.
Initial whole-module semantic invalidation remains acceptable; fine-grained reuse is an optimisation subject to these same correctness obligations.

### Validation and Publication Sequence

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

### Declaration Milestones and Cycles

| Logical milestone. | Readiness and extension rule. |
| --- | --- |
| Declaration/scope discovery. | Syntax-backed identity and provisional membership can exist before full semantics.  Mark whether the relevant import/conditional/generated membership is complete; do not promise a closed namespace prematurely. |
| Nominal identity and signature. | Publish protected identities and independently ready signatures where the declaration's rules allow it.  Recursive references may use an incomplete identity without asserting completed layout/body facts. |
| Constant/condition/instantiation. | Request the precise prerequisite facts and track explicit context/arguments.  Unsupported evaluation yields an explicit outcome, not a fabricated constant or silently omitted declaration. |
| Aggregate layout and values. | Wait for required field/value/layout milestones; legal pointer recursion and impossible by-value recursion require different outcomes under qualified language rules. |
| Body/expression analysis. | Depend on ready signatures, lookup/candidate sets and queried type/value facts; publish independently of unrelated declaration bodies when dependencies permit. |
| Generated syntax and final diagnostics. | New generated input re-enters syntax/discovery with provenance.  Consumers of changed membership must be invalidated or remain provisional; a completed earlier stage does not mean all later semantic work is complete. |

These are a query catalogue outline, not one mandatory total order: inferred types, polymorphism and generated work may introduce additional prerequisites dynamically.
Detect cycles from required unresolved graph edges and classify them using the supported declaration rules; report blocking identities/milestones for an illegal cycle.
External pending work and scheduler idleness alone do not establish a cycle.
No generic recursion guard, global fixed-point solver, or compiler evaluator is required merely to complete this draft.
Milestone 4 fixes the reserved facet, generated provenance and rule-admission records with an empty supported semantic catalogue.
Language-specific stage payloads/legal recursion rules are explicitly deferred until a future semantic profile is separately specified and qualified; cancellation/retry execution ownership remains milestone 5.

### Semantic Acceptance Trace Drafts

These are future executable equivalence/invalidation cases, not new passing experiments or claims of full semantic support.
Use fresh same-world computation as the cache oracle and isolated official-compiler fixtures for supported language facts; unimplemented semantic operations must return unsupported.

| Trace. | Required assertions. |
| --- | --- |
| D1: Instance and occurrence separation. | Reuse physical syntax across distinct import requests/parameters and repeated loads.  Preserve qualified nominal/visibility distinctions and occurrence multiplicity; no false declaration/type equality. |
| D2: Ambiguous declaration matching. | Reorder/move declarations and introduce identical/overloaded candidates.  Retain identities only for qualified unambiguous matches; conservative misses are acceptable, false identity reuse is not.  Old leased worlds remain unchanged. |
| D3: Negative and visibility dependencies. | Cache a supported missing/inaccessible name, then add it or change scope/import visibility.  Recompute the access-filtered lookup without turning inaccessible candidates into bindings. |
| D4: Candidate-set change. | Cache overload selection, then add/remove an eligible candidate while preserving the old winner's bytes.  Compare selection/ambiguity diagnostics against fresh computation. |
| D5: Signature versus body. | Change a local implementation, then an inferred/default/inline or compile-time-observed body.  Reuse only unaffected observed facets; body-sensitive consumers and current diagnostic locations remain fresh-equivalent. |
| D6: Constants and target. | Change a constant-driven field dimension or target context.  Revalidate layout/ABI consumers without conflating equal-sized nominal types or reusing facts from another configured instance. |
| D7: Equal result, new observation. | Change an upstream revision while preserving an observed value, then change it again.  The first edit may stop propagation, but refreshed edge stamps make the second edit invalidate correctly; changed spans are remapped separately. |
| D8: Provisional work and cycles. | Discover a generated/imported name after an initial miss, and contrast legal pointer recursion, illegal by-value recursion and externally pending work.  Provisional results never become false complete negatives; only qualified actual cycles produce cycle diagnostics. |

Milestone 4 supplies identity/canonicalisation/matching algorithms, the empty initial semantic catalogue, reserved query/dependency/facet records and generated/evaluator/cycle admission boundaries.
Future language profiles must supply their exact payload/rule mappings before admission; API approval and executable fresh/compiler-oracle qualification remain open.

## Execution and Shutdown Contract Draft

Drafted 2026-10-20.
**R4 direction approved 2026-10-21; detailed execution/limit contracts remain proposed and unimplemented.**
This refines C3/C5 and the core ticket/lease contracts using E8's bounded scheduler evidence; E8 did not test actual concurrent workers, reentrant callbacks or stopping a running worker.
The proposed initial delivery mechanism is host-pulled completion records plus poll/wait, not arbitrary callbacks from workers.
Milestone 3 supplies the exact logical signatures; the milestone-5 closure below supplies the draft execution model, ordering, reservations, delivery and destruction rules.
Native Jai bindings and our use of platform primitives still require review/testing; optional host quotas must be honoured without imposing fixed resource defaults.
This draft does not implement a scheduler.

### Coordinator and Worker Boundary

A logical coordinator serialises source-event acceptance, task registration, dependency readiness, waiter attachment/cancellation, terminal-state publication and head-world selection.
This is a linearisation responsibility, not a requirement for a dedicated thread or a single global lock.
Every externally visible transition must have a defined ordering against competing transitions; acquiring a payload lease is part of observing an available result, not a later unprotected operation.

| Operation. | Proposed ordering and ownership rule. |
| --- | --- |
| Accept source/update. | Validate provider ordering and admission capacity before acknowledgement.  Own/lease the input and install the ticket coherently; no caller receives success for work the service cannot retain.  Store failure alone does not reject otherwise valid in-memory work. |
| Request/join query. | Atomically inspect the selected world-keyed task, return a protected existing terminal result or register a waiter for pending work.  Completion racing registration cannot strand a waiter or create two equivalent tasks. |
| Dispatch worker. | Transfer protected immutable inputs and owned scratch, plus task identity/allocation generation and attempt token.  A worker must not mutate published syntax/worlds or call host code while holding service coordination. |
| Complete worker. | Validate task/world/generation/attempt and the expected nonterminal state; publish result/dependencies together before resolving surviving waiters.  Duplicate or obsolete completions are rejected, and their unpublished payloads released by their recorded owner. |
| Cancel/release waiter. | Order cancellation against terminal publication.  If cancellation wins, that waiter is cancelled and gets no result payload; if completion won, its existing terminal outcome is not rewritten.  Releasing the handle retires its notification interest and protection explicitly. |
| Coalesce update work. | Preserve accepted source-event ordering and each ticket's truthful milestone outcome.  Only unneeded computations may be skipped; an older completion cannot replace a newer selected head or silently satisfy a different revision's ticket. |

Do not invoke filesystem/compiler/provider callbacks, wait on dependencies, or block on store coordination while holding service state locks.
Acquire external inputs through an explicit asynchronous or bounded operation, then revalidate its captured identity at publication; returning from an external call does not make its result current.
Provider re-entry, lock ordering and cross-component ownership transfer follow the milestone-5 rules below, not recursive locks.

### Milestone 5: Coordination, Ordering and Reservations

The initial execution profile is `jai-cache-execution/1`.
Its baseline is one nonrecursive state gate per session, entered briefly by public callers and completion producers, plus one service-owned compute worker per session that progresses independently of host polling/draining.
There is no dedicated coordinator thread, host-dispatch progress requirement, inline parsing on a public-call thread, or work stealing between sessions.
The compute worker runs only already protected immutable inputs and cannot perform provider acquisition, filesystem/store access or host dispatch.
`OpenSession` also reserves an independently progressing service-owned shutdown/reaper job and its execution/control backing; first shutdown makes it runnable without ordinary admission or host polling.
That job drives stop/detachment, joins the compute worker outside the state gate and publishes the shutdown observation; it is not a coordinator thread on which ordinary calls/worker completions depend.
Provider hooks run synchronously on their acquiring/releasing call path outside the state gate, with at most `concurrent_acquisitions` admitted acquisitions; optional store work uses a separately progressing, bounded lane whose publication protocol remains milestone 6.
Neither a provider/store stall nor a host that stops draining may hold the state gate or prevent unrelated ready compute work from progressing.
One compute worker is a conservative draft baseline, not a throughput qualification or approval of a multi-session resource budget; any parallel-compute profile needs separate scheduling/ownership qualification.

The state gate protects session lifecycle, counters/reservations, source/frontier/head selection, task/dependency indexes, registration slots and completion readiness.
Do not nest state gates from different sessions, acquire payload/store/provider locks under a state gate, wait/join, allocate through a host callback, or run destructors/provider hooks while holding it.
Stage fallible allocation and external acquisition outside the gate under a reservation, then re-enter and revalidate before installing state.
State inspection and intrusive-link/counter updates under the gate must use already reserved storage; preallocated control records support failure/retirement paths without reentrant allocation.
Lock-free immutable reads still require the caller's live registration; an unprotected pointer is never an alternative to gate-checked acquisition.
The owner directory has its own gate, never nested with a session state gate: lookup acquires an owner pin under directory protection, drops that protection, then validates the registration under the session gate.
Directory removal prevents new lookup pins; existing pins finish against a marked retiring owner before its storage is freed.
Do not hold directory protection while calling a session operation, running cleanup or waiting for the last pin.

Every admitted call pins its session owner and each input registration before leaving the gate; concurrent `Release` may retire a public registration but cannot free memory used by that call.
This pin ends at return and does not extend a returned `Borrowed(T)` lifetime.
Re-entry from a provider hook is a new call, with no gate held by its caller: it may advance the frontier or request shutdown, after which the outer call must fail its final revalidation and release its staged ownership.
Hooks must not synchronously wait for the operation that invoked them; synchronous provider hooks already cannot depend on host dispatch.
The service invokes neither provider nor host code merely to compare a canonical key while under the gate.

The following table is the exhaustive ordering map for the fifteen public operations.
An operation may have a reservation phase and a later decisive transition; only the latter acknowledges acceptance or returns an owned registration.
No source/frontier/head change occurs at reservation, and staged IDs consumed by rejection are never recycled.

| Operation. | Decisive ordering point and race result. |
| --- | --- |
| `OpenSession`. | After host authority/configuration validation and successful baseline reservations, install the new owner, initial frontier and `SESSION` registration together.  Otherwise, release staged resources and expose no session. |
| `DescribeSession`. | Pin and copy one coherent bounded state under the gate into pre-reserved caller-return storage.  Later changes do not alter the copy or reserve its frontier. |
| `SubmitSourceBatch`. | After all protected staging, recheck `OPEN`, exact frontier/document/overlay bases, bindings and reservations; install selected source states, one successor frontier, operation and ticket together with old-frontier task invalidation and `WORLD_SUPERSEDED` query notifications.  Shutdown/base change winning that recheck rejects the whole staged batch. |
| `RequestAnalysis`. | Recheck `OPEN` and the exact requested frontier/member bindings, then attach an independently owned ticket to the existing matching candidate or install a new candidate.  Source state and frontier do not change. |
| `ObserveTicket`. | Inspect terminal state or atomically attach one separately reserved update waiter.  Completion before attachment returns terminal; completion afterwards resolves that waiter, including before the call returns. |
| `AcquireWorld`. | Validate the live selector, outcome/frontier and backing, then install the new `WORLD` registration and its protection under the same gate.  If selector release or head replacement won, return the specified error/unavailability, never an unprotected pointer. |
| `Query`. | Validate the retained world and implemented kind/schema; under the gate acquire an already available protected result, return an immediate terminal reason, or join/install its current-world task with one reserved waiter.  An obsolete world needing fresh work returns `WORLD_SUPERSEDED` without task/waiter creation; reserved unsupported kinds create no task. |
| `Poll`. | Snapshot the pinned registration's current stable observation.  Terminal state does not consume completion interest or allocate a result/world registration. |
| `Wait`. | Inspect the pinned observation and arm the condition wait under the same gate and registration generation; release the gate while waiting and recheck on every wake/deadline.  The deadline observation orders terminal-versus-timeout; no check-then-sleep window exists. |
| `AcquireResult`. | Validate the live query waiter and `AVAILABLE` backing, then install independent `RESULT` protection atomically.  A concurrently retired waiter cannot lend its pointer to a new registration. |
| `CancelWaiter`. | Change only a still-nonterminal waiter to `CANCELLED`/`CALLER` and detach its consumer link.  If terminal publication already won, return that existing observation; do not rewrite the task or update ticket. |
| `DrainCompletions`. | Copy up to the checked maximum of ready, live-generation entries and mark only those copied entries delivered in the same gate transition.  Allocation/copy failure before that transition consumes nothing. |
| `Retain`. | Validate/pin the original `WORLD`/`RESULT` and install a distinct reserved registration before a competing release can remove its backing.  If retirement won first, return `INVALID_HANDLE`. |
| `Release`. | Mark the validated registration retired, detach interest and move unreferenced resources to deferred cleanup; advance its reusable-slot generation before any new registration is installed.  A non-`STOPPED` `SESSION` instead returns `ACTIVE_SESSION` with no retirement. |
| `RequestShutdown`. | First acquire an owned shutdown registration, then atomically change `OPEN` to `QUIESCING` and publish the one shutdown operation.  Later successful calls acquire distinct registrations for that same operation; no call acknowledges shutdown without an observable handle. |

Allocation failure on a descriptive call returns `ADMISSION_DENIED` without changing source or consuming observations.
Caller-return copies are bounded by the negotiated value/list limits and charged while being constructed; after transfer their host-owned backing is not retained service memory.
`Poll`, `Wait`, `CancelWaiter`, `Release` and the first shutdown request have bounded preallocated minimal response paths; optional explanatory diagnostic allocation is never needed to report failure or release ownership.

#### Reservation Ledger and Cleanup Capacity

The ledger uses the nineteen existing `Limits` fields, not an unbounded side queue or new default budget.
For every count/byte dimension, require checked `live + reserved + requested <= effective_limit` before reserving it.
Reservations count against the same limit as installed state and transfer to live usage at commit; cancellation/rejection returns unused portions exactly once after the protected external operation actually stops.
Allocate neither staged replacement bytes nor an acquisition job before charging its worst permitted backing; a lease reference does not hide its retained exact-source charge.
Intermediate edit buffers, conversion scratch, candidate worlds and deferred cleanup remain charged while physically owned, even after their public operation has become terminal.

| Reservation owner. | Required capacity before acknowledgement/dispatch. | Release point. |
| --- | --- | --- |
| Session baseline. | `SESSION` plus the first `SHUTDOWN` slot, one shutdown operation/control record and reaper-job execution backing, condition/readiness state and fixed emergency failure/cleanup records, all within `live_handles` and `owned_bytes`. | Transfer the shutdown slot on first request; retain cleanup/owner storage until the last call, producer, registration and borrowed-owner obligation ends. |
| Accepted update/analysis. | One `TICKET` slot, operation/candidate/task bookkeeping, input/source protection and a bounded terminal observation.  Charge `in_flight_operations` before accepting, including an independent joined operation. | Terminal bookkeeping can transfer to its surviving ticket/waiters; active producer/task storage keeps its reservation until returned/stopped. |
| Pending waiter. | One `WAITER` slot, `pending_registrations` slot, one `completion_records` slot and `owned_bytes` for its terminal/cancellation/readiness record. | Pending charge ends at its terminal transition; completion charge ends when drained or released.  The waiter retains terminal observation/backing until release, even after drain. |
| Running task/acquisition. | Exact protected inputs, bounded scratch allowance, one preallocated completion/stop mailbox and producer reference; acquire the provider concurrency slot before any hook. | Coordinator consumes the returned/stop-acknowledged producer state and all associated cleanup finishes, not when a caller times out or cancels. |
| New payload registration. | `WORLD`/`RESULT` handle slot and ownership-link bytes; protect transitive backing before returning it.  Shared backing remains charged once per protecting session. | Last owning link and active call/producer pin release it; eviction cannot revoke it. |
| Descriptive drain/copy. | Checked bounded return storage reserved before selecting delivery entries. | Transfer the complete copy or roll back without consuming entries. |

The `SESSION` and reserved first `SHUTDOWN` slot mean `OpenSession` rejects configurations that cannot fit at least those two live/reserved registrations plus the fixed control backing.
The permanently reserved shutdown operation/control record is unavailable to ordinary work and charged against `in_flight_operations`/`owned_bytes` from open until shutdown stops.
No optional work can consume those reservations; an implementation must compute/check its actual minimum, not silently raise a host ceiling or borrow from another session.
If every ordinary slot is occupied, the first `RequestShutdown` transfers the reserved slot and succeeds without increasing live-plus-reserved usage.
Repeated requests need ordinary new-handle capacity and may return `ADMISSION_DENIED`; they neither restart shutdown nor invalidate its first handle.
If that handle was released early, ordinary release frees a slot through which a later call can acquire a new observation of the same operation.
Public `Release`, cancellation, completion consumption and transition to `STOPPED` need no fresh ordinary admission; all use their owners' already charged control/mailbox records.

A worker may allocate only within its reserved scratch allowance and checked session total; failure terminates that attempt with the preallocated `FAILED`/`RESOURCE_LIMIT` observation, not truncated successful output.
Unknown output size does not justify reserving an unbounded result: grow through checked reservations outside the gate, or fail honestly when either limit/allocation fails.
State installing a payload, dependency links and all terminal observations must have sufficient reservations for the whole transition before publishing any of it.
Memory pressure rejects new work; the initial profile does not pressure-cancel already accepted required work or revoke retained results.
The `PRESSURE` cancellation reason remains reserved for a separately approved policy, not this profile's ordinary admission failure.

### Completion Observation and Host Delivery

An immediate terminal query response needs no later completion notification for that call.
A pending response installs a live waiter whose terminal outcome is retained until observed/released according to its handle contract, even if completion happens before the caller next polls.
`Poll`/wait reads that same stable outcome; it does not consume the payload, repeat the terminal transition, or implicitly select a newer world.
A timeout stops that wait attempt and reports pending/timeout, not cancellation or source failure unless the caller separately requests cancellation.

Proposed host delivery is a completion registry/queue addressed by protected handle identity and generation, with a coalescible wake signal.
Host draining emits at most one terminal completion record per live pending registration; a lost/coalesced wake must not lose the retained outcome.
Registering/inspecting completion and arming a wait must prevent the classic check-then-sleep lost wakeup; poll remains authoritative if the host delays delivery.
Queue pressure must not silently drop terminal outcomes: reserve admission/retention capacity, use a bounded indexed registry, or reject new work explicitly before acknowledgement.
The indexed representation, reservation/consumption rules and wait predicate are specified by the milestone-5 closure; the 2026-10-23 R6 decision makes configured ceilings optional without weakening those rules.

Drain/delivery is host-owned and serialised for a subscription; the core never invokes a host callback inline from submission, task completion or cancellation.
A callback adapter, if added, runs only while the host explicitly dispatches records, outside internal locks and with callback argument/result leases held through return.
The host may submit/cancel/query again from that callback; re-entry is a new operation, not permission to recursively mutate the notification iteration or access released handles.
`Release` during delivery suppresses future interest, but backing used by the active delivery stays leased until it returns.
Callback exceptions/failures must not change an already committed task outcome or leak its delivery lease; the host-helper rules below define failure isolation and nonrecursive dispatch without introducing core callbacks.
No UI thread affinity is inferred; the adapter/host must declare its dispatch thread and avoid a blocking wait that depends on progress on that same thread.

### Cancellation, Scheduling and Pressure

Waiter cancellation is independent of computation cancellation and never undoes an accepted source event.
Distinguish waiter-local `CALLER` cancellation from task-wide `WORLD_SUPERSEDED` cancellation and service shutdown.
A caller/UI stop on current-world work detaches only that waiter; other consumers keep the deduplicated task.
When the selected world becomes out of date, cancel its unfinished shared task and every still-pending attached query waiter with `WORLD_SUPERSEDED`, regardless of how many consumers remain.
The initial last-consumer policy removes unneeded current-world queued work but lets already running current-world work finish; world supersession and shutdown request cooperative stopping of running work, as specified below.
Cancellation is a request until the worker acknowledges termination or returns; retain its inputs, scratch and completion routing throughout that interval.
If a new attempt starts, use a new attempt token; an old worker cannot complete the new attempt even when the logical query key matches.

Prioritise active-file syntax and user-requested queries over optional historical loading or GC, and propagate needed priority to prerequisite work.
Do not busy-spin on blocked dependencies or diagnose a cycle from lack of runnable workers alone.
Bound admission by the reservation ledger and use the required/optional readiness policy below; priority classes are not a measured latency guarantee or a reason to starve accepted work indefinitely.
Pressure may reject/defer new optional work or surface an explicit admission failure, but must preserve existing leases and terminal-outcome observation.
The one-compute-worker baseline, FIFO readiness and cooperative boundaries are specified below; their actual latency, native primitives and concurrent/platform behaviour still require qualification.
Compiler subprocess execution remains unsupported, so this initial profile admits no compiler-process budget or kill protocol.

### Service Shutdown and Retained Results

Proposed lifecycle: `open -> quiescing -> draining -> stopped`; shutdown is idempotent and repeated calls observe the same shutdown operation.

1. Enter quiescing at a defined coordinator transition.
Reject new work explicitly, stop ordinary compute dispatch, and detach source/watch/provider registrations, so no new callback can acquire untracked service state.
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
The owner/destruction rules below distinguish scheduler shutdown from the last external result lease without adding a public destroy operation.
Blocking shutdown from inside a dispatch callback cannot wait for that same callback to return; request shutdown there and observe completion after unwinding.

### Milestone 5: Task Attempts and Publication

An analysis candidate has `CaptureKey = K("execution-capture", [SessionID, ProviderFrontier, canonical_selected_members, milestone_ASCII])`.
`canonical_selected_members` is the canonical value of the exact ordered selected-document bindings, including source/absence/context and consistency evidence, not only a document-name list or hash.
At admission, a matching pending or successfully published candidate can be joined; a failed/superseded/cancelled candidate is not an implicit retry.
Joining an already published candidate resolves the new ticket and, if it is the current head target/frontier, installs its head at that same admission transition; it does not wait for a nonexistent new worker completion.
An explicit later `RequestAnalysis` may create a fresh candidate for the same capture after terminal failure, with a fresh `WorldID` and task stamps.
Allocate a new candidate's `WorldID` before publication under the milestone-4 allocator; that internal identity grants no readable `WORLD` handle or published-head status.

`TaskKey = K("execution-task", [SessionID, WorldID, task_kind_ASCII, canonical_task_descriptor])`.
The initial task kinds are `PARSE_INDEX` and `QUERY_PAYLOAD`; the descriptor binds exact document/source/context, producer/schema tuple and query kind where applicable.
`PARSE_INDEX` includes the whole required per-member source/syntax/diagnostic/index closure; `QUERY_PAYLOAD` performs only conversion/acquisition against an already published world's protected observations.
No task key omits its candidate/selected world or silently joins a newer world; cross-world artifact reuse requires the separate fully validated artifact-key path, not live-task identity equality.
The task index admits at most one current task for an equal full key; independent public operation identities and waiter/ticket reservations are not collapsed by sharing that task.
Initial semantic/evaluator query kinds still return `UNSUPPORTED` before either task kind is created.

`AttemptStamp` is `{session:SessionID, world:WorldID, task_key:bytes, slot:u64, generation:u64, attempt:u64}`.
`task_key` is the complete canonical key; `slot`/`generation` identify the live task record, not a public handle, and `attempt` is a positive checked counter local to that allocation.
Start `generation`/`attempt` at 1; advance `attempt` before a permitted replacement dispatch, never reuse it, and retire the task allocation on exhaustion rather than wrap.
A fresh allocation uses a fresh nonreassigned slot/generation association; milestone-4 generation retirement rules apply.
Replacing a running attempt is not allowed until that producer returned or acknowledged stop, so retries cannot create an unbounded tail of abandoned workers/mailboxes.
The initial profile does not silently retry failures: a later explicit request can establish a new attempt/candidate after the old producer is safe, while previously observed terminal outcomes stay terminal.
Task phases are `WAITING_INPUTS. | READY. | RUNNING. | STOP_REQUESTED. | TERMINAL. | REAPED`; a prerequisite failure can terminate `WAITING_INPUTS` without worker dispatch.
Public `QUEUED` covers `WAITING_INPUTS`/`READY`; public `RUNNING` covers dispatched work until its public outcome is terminal, not permission to expose the internal task record.

Each dispatch owns a single-use completion mailbox, its immutable inputs/scratch and a producer pin on the owner independently of the task-index slot.
The producer transfers at most one owned returned payload or stop acknowledgement into that mailbox, then wakes the coordinator; a duplicate signal is not another payload transfer.
The mailbox remains alive until producer relinquishment and coordinator consumption are both recorded.
Consuming it checks the full `AttemptStamp`, expected `RUNNING`/`STOP_REQUESTED` phase, source/context/schema evidence and every referenced payload/dependency before one terminal installation.
Perform fallible/large payload validation outside the gate under the mailbox/owner pin, then recheck the stamp and reserved state under the gate for the final installation.
A stale/duplicate signal cannot address a recycled task/registration through its old slot; it routes only through its still-protected mailbox/owner and performs no second release of a transferred payload.
Any distinct rejected unpublished payload remains owned by its recorded producer/cleanup record and is released once outside the gate.
Worker scratch can become immutable payload backing only by explicit ownership transfer with complete accounting; no published record borrows a temporary allocator or worker stack.

Successful publication installs validated payload/backing, complete dependency observations and retained terminal outcomes atomically, then marks the relevant waiter entries ready.
An error/cancellation is likewise one terminal transition; partial state/dependency links never escape a failed publication.
The state gate orders caller cancellation-versus-completion per waiter; `CALLER` winning does not remove another consumer's payload or rewrite the shared task outcome.
Publication also revalidates that the captured world's source frontier is still current; an unfinished obsolete-world attempt cannot publish merely because its inputs and retained world remain readable.
Already terminal outcomes and already acquired immutable results remain valid; cancellation of unfinished work does not revoke their backing.

The session's head target is the candidate named by its latest accepted source/analysis request, including an explicit join of an existing candidate.
Only that target, at the currently accepted frontier, may install the head; other successful same-frontier candidates can publish their own ticket worlds without replacing it.
A newly accepted source frontier terminally SUPERSEDES still-pending older-frontier update operations and their still-pending observation waiters at the same source commit.
Their successor is the new accepted operation identity; already terminal tickets/outcomes and already published worlds are not rewritten.
Detach those superseded consumers, retain any running producers until safe, and never let their late completions install the head.
At that same source commit, invalidate unfinished old-frontier tasks and terminally cancel all their still-pending query waiters with `WORLD_SUPERSEDED`, independently of the older update tickets' `SUPERSEDED` outcome.
Source acceptance itself is not undone; retaining an old world protects its published data but does not exempt its unfinished computations from task-wide supersession.
Requests at one frontier with different finite membership sets do not supersede each other's ticket outcomes merely because one became the head target.

#### World Supersession versus Caller Stop

For this cancellation policy, a world is current while its captured `ProviderFrontier` equals the session's latest accepted source frontier under the provider's registered equality relation.
Do not use a numeric/lexical token comparison or the possibly lagging published head; a different `WorldID` or head target at the same frontier is not by itself stale.
The source-commit gate orders invalidation against task completion, joins and caller cancellation: once the frontier advances, no pending old-frontier work remains publishable or joinable.
Remove obsolete `WAITING_INPUTS`/`READY` work from dispatch; mark running attempts `STOP_REQUESTED`, close their publication path and request cooperative stop of their prerequisite/dependent work in that obsolete world.
Required consumers and shared waiters cannot keep obsolete computation running as useful work; the producer may still physically run until its next cooperative boundary or return.
Keep its mailbox, inputs, scratch, task reservation and owner pins charged until safe producer/cleanup completion; reject and release any late payload exactly once without replacing the cancellation outcome.

Every still-pending waiter attached to that shared work receives one terminal `CANCELLED {reason:WORLD_SUPERSEDED}` through ordinary poll/wait/completion delivery.
Store intents protecting accepted source/recovery are independent of these compute-task cancellations and retain their milestone-6 commit/coalescing obligations.
This tells each client to decide whether to submit a fresh request against an explicitly acquired current world, wait, or abandon the request; do not automatically reissue, rebind or transfer old waiters to a successor task.
If `CALLER` or successful completion won before the source commit, preserve that already terminal observation; a later world change does not rewrite it.
If supersession won first, a subsequent `CancelWaiter` returns the existing `ALREADY_TERMINAL` observation, preserving `WORLD_SUPERSEDED` rather than relabelling it `CALLER`.
New queries against a retained obsolete world may acquire already available protected results, but requests needing fresh work return `WORLD_SUPERSEDED` cancellation without scheduling/joining a task or registering a pending waiter.
Current-world `CancelWaiter` remains waiter-specific even when several clients share one task; cancellation must never be inferred from a UI label or implemented by stopping that shared producer while another current consumer needs it.

### Milestone 5: Delivery, Cancellation and Progress

Completion storage is a bounded index of reserved `WAITER` entries, not a dynamically growing message stream.
Each entry owns its generation-checked registration link, terminal-ready flag, `delivered` flag and intrusive ready-list link; its immutable terminal observation/backing is separately protected by the waiter owner.
Append once at the terminal transition in coordinator commit order, including explicit waiter cancellation; immediate terminal responses and `TICKET`/`SHUTDOWN` handles do not create completion records.
`Poll`/`Wait`/`AcquireResult`/`AcquireWorld` do not set `delivered`, remove a ready entry or release its protection.
Drain selects ready live entries in that order, copies at most `maximum` records to pre-reserved caller-owned storage, and marks exactly that successful copy delivered.
Concurrent drain calls are serialised at the gate and cannot both emit one entry; `maximum` 0 touches no entry, and a failed call consumes nothing.
Drain or waiter release returns its `completion_records` reservation, but drain does not release the waiter, its outcome or its terminal result/world backing.
`Release` before drain unlinks the entry and suppresses delivery; release after drain makes the returned descriptive handle safely stale.
No entry for an old generation is repointed to a newly reused slot, and an optional wake signal carries no payload ownership.

`Wait` uses an owner-lived condition variable paired with the state gate and the pinned registration's terminal/retired predicate.
Atomically release the gate while arming/sleeping, tolerate spurious/coalesced wakes and always reacquire/reinspect; notify on terminal publication, cancellation, registration retirement and shutdown phase change.
Registration retirement while sleeping wakes the call and returns `INVALID_HANDLE` if it wins that observation point; the call pin prevents use-after-free while it unwinds.
A valid terminal predicate observed at the deadline returns the terminal observation, otherwise `TIMED_OUT_PENDING`; wall time and a foreign clock cannot decide it.
Notify-all/coalescing is permitted because the predicate is authoritative; neither a wake nor an empty drain implies successful completion or `STOPPED`.
Progress comes from the service worker/completion producers, not the presence of a waiting/draining host thread.

The initial core has no callback adapter or callback-delivery capability.
A host may build a helper over caller-owned `CompletionBatch` values: it serialises dispatch for that session and defers nested drain/dispatch requests to the outer dispatch loop's next turn.
Before invoking user code, the helper explicitly acquires/retains any `WORLD`/`RESULT` arguments it intends to expose, skips safely stale registrations and runs outside all service locks.
The helper holds those independent handles through return even if the callback releases the original waiter/result/session registration.
Use unconditional cleanup on every normal/error return; an explicit transfer to the callback must leave a named new owner rather than both parties releasing the same registration.
The host catches/reports callback failures outside the service; the already delivered record is not requeued, its stable outcome remains pollable, and no task outcome is rewritten.
Reentrant query/cancel/release/shutdown calls follow the ordinary operation table; blocking waits must be deferred until the dispatch stack unwinds whenever progress/cleanup depends on that stack.
Thread affinity and user exception conventions belong to the host helper; they cannot add inline callbacks to this profile or weaken its ownership rules.

#### Last-Consumer and Fairness Policy

A task consumer is a live nonterminal waiter, required accepted analysis/head-target obligation, or protected dependency edge needed by another accepted task.
Public handle release alone does not undo the session's accepted source or an analysis obligation that is still needed for its head target.
After the last consumer/required obligation detaches from current-world work, remove `WAITING_INPUTS`/`READY` tasks from dispatch and release their protected inputs through deferred cleanup; already running current-world tasks finish with their mailbox/inputs intact.
A new matching current-world consumer may join that still-running task before it completes; do not join obsolete/stop-requested work or launch a duplicate attempt merely because a current task temporarily had no external waiter.
Unconsumed successful output may be discarded or held only under an explicitly bounded optional retention policy; this profile selects discard unless an existing protected consumer or approved store obligation owns it.
No extra task is launched solely to populate history, and an unapproved retention policy is not a hidden default.
World supersession and shutdown request cooperative stopping of running tasks; neither those requests nor a last-consumer/pressure path pretend that a producer has already released its inputs.

There are two ready FIFOs: `REQUIRED` and `OPTIONAL`.
Every accepted update/analysis/query and all of its required prerequisites are `REQUIRED`, including background documents; a shared optional prerequisite is promoted to the tail of `REQUIRED` when it becomes needed.
Preserve an already required task's place; newly ready or resumed work enters the tail, so a stream of later submissions cannot overtake an existing ready required task.
Dispatch the `REQUIRED` head whenever nonempty, otherwise at most one bounded `OPTIONAL` chunk, then recheck `REQUIRED`.
Optional work is limited to separately admitted maintenance/store preparation and must yield between bounded record/source-value chunks; it never monopolises a ready required queue.
This chooses no active-file hint or priority field absent from the public API; finer within-required priority requires a separately reviewed extension rather than guessed UI state.
Required background work therefore makes FIFO progress whenever earlier dispatched chunks return and its prerequisites become ready; optional work may starve under sustained required demand.
This is a scheduling-order guarantee, not a wall-clock bound or permission to preempt an arbitrary parser/native call.

Blocked prerequisites/external input occupy no ready slot and must not busy-spin; completion/failure/stop events make them ready or terminal through the gate.
The initial finite syntax graph does not admit semantic cycles; future semantic profiles must use their registered cycle rules and dependency graph, not worker idleness or a wait timeout.
Check stop intent before dispatch, between documents/task phases, before each bounded conversion/maintenance chunk and before publication.
An indivisible parser/foreign call may only observe stop when it returns; the scheduler cannot claim a finer cancellation bound without an instrumented, separately qualified producer.
Optional store work and synchronous provider hooks have their own registered return/stop ownership; they cannot block the compute worker waiting for host dispatch.
The single compute worker never waits on a task queued behind itself: suspend `WAITING_INPUTS` and dispatch its ready prerequisite instead; all initial parse inputs are already protected before becoming ready.

### Milestone 5: Shutdown and Final Ownership

The first reserved shutdown request publishes one shutdown operation and changes lifecycle at the same transition that rejects new submissions/analysis/queries/`ObserveTicket` registrations.
Already available `WORLD`/`RESULT` access, `Poll`/`Wait`, `CancelWaiter`, bounded drain, `AcquireWorld` from surviving publication, `AcquireResult`, `Retain`, `Release`, `DescribeSession` and repeated shutdown observation remain supported under ordinary limits.
After `QUIESCING`, `HEAD` can acquire an existing matching published head but cannot schedule or wait for a new one.
An operation staged before quiescing either committed before it or rejects `SERVICE_CLOSED` on revalidation; any acquired provider references still unwind under their recorded owner.
No provider callback may revive a retired registration or admit source work after that transition.

Preserve every existing terminal observation; terminally cancel unfinished update/query interests with `SHUTDOWN`, remove their queued tasks and request cooperative stop of running producers.
Keep accepted source state and published payloads intact; cancellation of an update milestone is not reset/discard or a persistence acknowledgement.
Detach acquisition/watch ingress under the registered adapter's no-future-entry protocol, retaining a producer pin for every already entered call until return/acknowledged detachment.
The initial provider boundary admits only the synchronous hooks specified in milestone 3; no unstated asynchronous callback source is registered by this profile.
An adapter unable to establish safe detachment cannot report that ingress stopped; shutdown remains pending rather than freeing its completion sink.
After closing ingress and recording stop/terminal intents, enter `DRAINING`; internal shutdown/cleanup/store-finalisation steps may progress there, but ordinary compute dispatch does not resume.

`STOPPED` requires all the following together under the gate: all pre-quiesce admission/acquisition calls have unwound; compute worker exit is acknowledged/joined outside the gate; all task mailboxes and external producer pins are consumed/detached safely; and scheduler-owned cleanup/store-finalisation operations have returned with a truthful bounded status.
Stop/join outside the state gate, then publish the checked exit fact under it; never wait for a worker that needs the gate while retaining that gate.
The pre-reserved reaper, not a polling host or the compute worker joining itself, drives that sequence.
`STOPPED` denotes compute/ingress/store quiescence, not destruction of the surviving owner control infrastructure: the reaper's own final control pin ends after publishing the observation and unwinding its job.
Pure observers and a `Wait` on shutdown do not count as producers whose return is required for `STOPPED`, or shutdown could wait for its own observer.
Undrained completion entries and client `WORLD`/`RESULT`/`TICKET`/`WAITER`/`SHUTDOWN` registrations do not prevent `STOPPED`; their observations/backing migrate to the surviving owner and remain charged until independently released.
A host helper is outside the core: its already acquired callback-argument handles protect backing through callback return without requiring `STOPPED` to wait for host dispatch.
Deadline expiry changes none of these predicates; a stuck producer leaves `DRAINING` and its owned bytes/pins live indefinitely until it actually returns or safely detaches.
There is no forced thread termination, unsafe detach, implicit compiler launch or false durable-success fallback in this profile.

Store finalisation may report `DISABLED`/`DEGRADED` and a bounded aggregate service diagnostic; only genuinely confirmed persistence progress enters `acknowledged_frontier`.
Durable flush/reset/discard and store-lane stop primitives remain the milestone-6/R2/R6 contract, not a new guarantee derived from `STOPPED`.
Failure to finish a still-running store call remains pending shutdown; a returned store failure is a truthful degraded status and does not revoke surviving source/result leases.

The session owner has a surviving control lifetime distinct from the stopped scheduler and released `SESSION` registration.
It owns the generation-checked slot table, immutable payload graph, terminal observations, provider binding/leases needed by retained sources and allocator/accounting state required for their final release.
The initial profile requires resident protected backing for acquired payloads; it does not reopen a store file or restart a parser/worker from a retained result after shutdown.
Host/provider allocator and immutable-release bindings must remain valid through that owner's last reference, not merely through `SESSION` release; a host unable to promise that must supply independently owned source copies before admission.
Releasing a stopped `SESSION` removes only that registration; surviving child handles continue to route through the owner directory by their nonreassigned `SessionID`.
At `STOPPED`, detach scheduler/task-index roots that are no longer needed for observation; at `SESSION` release, also detach session-private head/source/history roots without touching the transitive closure owned by surviving child registrations.
Accepted identities/terminal descriptions retained by those children remain immutable; an unused session-private root must not form an owner self-reference that prevents final reclamation.

Final destruction occurs only after `STOPPED`, no public registrations/reservations remain, all active call/producer/cleanup pins are zero and all payload/provider ownership has been released exactly once.
Detach objects under the gate, run recursive cleanup/provider releases outside it with an owner pin, and remove/free the directory entry only after those cleanup pins return.
No final destroy API, extra caller action or implicit retain hidden in `Poll`/drain is added: the last ordinary `Release` and outstanding cleanup returns drive destruction.
Old handle lookups after directory removal return `INVALID_HANDLE` without dereferencing freed memory; never keep an unbounded per-dead-session tombstone list or recycle a `SessionID` to make lookup possible.
The caller must not race its own borrowed-view use with release of its sole owning registration; retain first, as required by the unchanged accessor contract.

### Execution Acceptance Trace Drafts

These are future executable concurrent/interleaving cases for C3/C5; E8's model scenarios do not show the implementation is race-free.
Use independently owned expected state/issuance/allocation ledgers and barrier-controlled producers rather than making the future scheduler's own task/completion lists the test oracle.
Each trace must run both winning orders, the delayed-producer/host case and its listed negative control.

| Trace. | Required assertions. | Controlled interleaving and independent oracle. | Negative control that must fail. |
| --- | --- | --- | --- |
| X1: Register versus complete. | Force completion before, during and after waiter attachment/return.  Return an immediate protected result or one live pending registration with one retained terminal outcome; no lost wake or duplicate equivalent task. | Gate completion around registration, before pending return, and between observation/wait arming; compare returned registrations/outcomes to an external call ledger, check one live task per exact key, then independently acquire/validate bytes. | Split check/register or check/sleep loses the ready outcome/wake; joining a different world/schema fails exact binding. |
| X2: Cancel versus complete. | Race current-world caller cancellation, source-frontier supersession and shared completion.  Caller stop affects one waiter; supersession affects every still-pending obsolete-world waiter.  Preserve the first terminal reason and release unpublished/unused payload ownership once. | Run two-consumer current-world UI stop separately from source-frontier supersession; barrier source commit, joins, completion, cancellation and late producer return in both orders.  An independent consumer/attempt/free ledger checks `CALLER` only on its winning waiter, `WORLD_SUPERSEDED` on every remaining pending old-world waiter, no duplicate dispatch/reissue and pins retained until safe stop.  Reissuing explicitly against current C may deduplicate a new C task, never revive B's attempt. | A UI stop kills the shared current-world task, one surviving consumer prevents obsolete-task cancellation, a terminal reason is rewritten, old work remains joinable/publishes late, a retry is silently rebound or scratch is freed before producer return. |
| X3: `Release` and slot reuse. | Queue a notification/completion, release its registration and reuse the slot for another generation.  Old records cannot reach the new client; an already active delivery retains its backing through return. | Poison/reuse public and task slots, deliver old mailbox signals and use a drained stale handle; compare generation/attempt issuance to a separate ledger and keep a callback's independently acquired payload alive. | Accepting an old generation/attempt, freeing a mailbox before producer return, or borrowing callback backing from a released waiter is detected. |
| X4: Reentrant host dispatch. | From host dispatch, submit another query, cancel a waiter, release a lease and request shutdown.  No callback runs under internal locks, no recursive delivery corrupts iteration, and shutdown completion does not depend on blocking its own callback. | Host-helper dispatch re-enters query/cancel/release/shutdown, requests nested dispatch and throws before/after explicit ownership transfer; a separate dispatch-depth/owner ledger proves deferral, stable terminal outcomes and balanced cleanup. | Inline callback under the gate, recursive list mutation, retry of an already delivered record or waiting for the current callback's return deadlocks or changes counts. |
| X5: Pressure and delayed delivery. | Delay host draining while admitted tasks finish and wake signals coalesce.  Outcomes remain pollable, and each live registration has at most one terminal record; queue/admission pressure never loses accepted work or revokes leases. | Fill each count/byte ceiling at exact boundary, then hold host drain while all reserved waiters finish; independently reconcile live/reserved/backing counts and retry failed drains without consumption.  At full ordinary handle/operation capacity the first shutdown still obtains its reserved handle/job. | Removing the shutdown reservation, charging only queued rather than reserved completions, consuming a failed copy or freeing running scratch on public cancellation violates the ledger. |
| X6: Priority and external wait. | Mix visible-file work, background dependencies and blocked external input.  Required prerequisites make progress under the approved fairness policy, optional work cannot monopolise dispatch, and external waiting is not reported as a cycle. | Inject a long stream of later required work around a recorded ready background prerequisite, optional chunks and a blocked provider; a separate readiness FIFO/dispatch log proves no overtaking and independent compute progress after each bounded chunk returns. | Priority starvation, optional monopolisation, blocking the compute worker on its own queued dependency, or treating external wait as a cycle fails order/progress/classification checks. |
| X7: Shutdown racing submission. | Order submissions around quiescing, run repeated shutdown, and attempt duplicate/late completions.  Every accepted request gets a truthful observable outcome; new work rejects and preserved result leases remain readable/releasable after stopped. | Barrier submissions and provider re-entry around quiescing; compare every acknowledged source frontier/ticket against a separate acceptance ledger.  Join an already published candidate, reorder older candidate completion, release `SESSION` after `STOPPED` and read/release retained child payloads. | A post-quiesce commit, old-head overwrite, published-join ticket left pending, restarted shutdown operation or destruction with live children is rejected. |
| X8: Worker outlives deadline. | Hold a worker/provider operation beyond a shutdown wait deadline, then allow it to stop.  Report incomplete shutdown initially, preserve protected inputs/completion sink, and enter stopped only after safe termination without use-after-free or false durable-success status. | Fake monotonic deadlines and hold provider/compute/store completion beyond expiry, with no host polling to drive shutdown; an independent liveness/allocator ledger observes `DRAINING` and live pins, then completion, worker join, `STOPPED` and final release. | Timeout-as-stop, self-join, dependence on host drain, premature owner/provider release or an unconfirmed durable frontier fails. |

### Milestone 5: Closure and Review Checks

Milestone 5 is complete as a draft execution and ownership specification on 2026-10-22.
It closes the fifteen-call ordering map, nonrecursive state-gate boundary, full-key task/capture/attempt checks, reservation/cleanup protocol, indexed delivery/wait predicate, host-helper re-entry, current-world queued-discard/running-finish policy, required FIFO progress, independently driven shutdown and surviving-owner destruction.
The 2026-10-23 cancellation clarification adds task-wide obsolete-world cooperative stop and `WORLD_SUPERSEDED` outcomes for all still-pending query waiters, distinct from waiter-local `CALLER` stop; producer safety and already terminal results remain unchanged.
The one-compute-worker/reaper baseline and policies are proposals for detailed R4 review, not claims added to the 2026-10-21 direction approval.
X1-X8 above carry its discriminating controls; milestone 7 consolidates the requirement/workload/oracle draft.

Required detailed review remains: native mutex/condition/thread/reaper/allocator bindings and minimum reservation sizing, actual provider ownership/stop compliance, R6 finite ceilings, R2/R6 store-lane/finalisation policy and the exact public API/profile approval.
Unsupported async provider ingress, semantic/evaluator work, callback core delivery, parallel compute, cross-session sharing and forced thread termination gain no capability from this closure.

## Source Provider and Capture Contract Draft

Drafted 2026-10-20.
**R3 direction approved 2026-10-21; detailed provider/event schemas remain proposed and unimplemented.**
This refines C1/C2/C5 and the core source-event contract; it does not qualify a real editor adapter, an operating-system snapshot facility, or atomic cross-file refactoring.
The proposed initial provider mode captures an explicit finite set of documents, preserving unknown membership rather than pretending the workspace/import closure is already complete.
Provider capability negotiation, host integration and exact identity/event schemas remain specification and approval work.

### Provider View and Capture Contents

The source provider exposes a workspace/session namespace, an ordered accepted-event frontier, immutable selected revision references and an explicit capability/consistency description.
A provider view distinguishes active overlay bytes, acknowledged disk bytes, confirmed absence and unobserved/unavailable source; it does not derive active selection from the cache's newest artifact.
Capture records retain the provider namespace/frontier, resolver configuration, source-visible context, requested document set, and the selected revision/state for each requested document.
All source bytes needed by a published capture must be owned or immutably leased before it is reported available, including paths/context used by diagnostics and resolution.

| Selected document state. | Proposed interpretation. |
| --- | --- |
| Present overlay. | Exact host-selected immutable buffer revision, regardless of disk existence or equality.  Retain the separate acknowledged disk state for save/reset handling. |
| Present disk. | Exact bytes acquired and acknowledged by the provider for this capture, with their context and acquisition/consistency provenance.  Do not infer their current validity from timestamp/size or a historical manifest. |
| Confirmed absent. | Absence established by an authoritative provider observation for this document/request/context at the captured frontier.  This may support a negative dependency only within that qualified observation's scope. |
| Unknown/unobserved. | The capture has not established this document or resolver-candidate membership.  It is not a missing file, a complete negative lookup, or permission to read the latest disk into the old world. |
| Unavailable. | The provider cannot supply required protected bytes/state, for example because a lease expired, access failed or historical capture is unsupported.  Report the reason and incomplete/unavailable outcome explicitly. |

The captured frontier orders provider events; it is not proof that every physical file existed in that state at one instant.
Ordinary sequential filesystem reads do not provide an atomic multi-file snapshot, even when timestamps/stat data appear unchanged.
The provider must declare whether it supplies host-frozen revisions, another qualified immutable snapshot, or merely individually observed disk revisions.
Exact byte hashing certifies the captured bytes, not simultaneous cross-file observation or freedom from an external writer modifying a file during acquisition.
If a required read-consistency guarantee cannot be supplied, return explicit unavailability/incompleteness for that guarantee; metadata rechecks alone must not be advertised as proving it.
The syntax-first service may parse explicitly captured observed bytes without claiming a coherent compiler-equivalent cross-file disk instant or full semantic closure.

### Initial Capture and Dependency Discovery

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

### Multi-Document Events and Analysis Publication

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

### Provider Lifetime, Failure and Diagnostics

Provider leases protect immutable revisions independently of a live editor callback; no syntax task may retain borrowed callback memory after return.
Closing/resetting a buffer changes future selection through an event but does not mutate/release bytes held by an old-world lease.
If the host cannot retain old bytes, the service must copy them before acknowledging the capture or reject that capability; expiry cannot silently turn a valid published lease into a dangling reference.
An unavailable uncaptured revision is distinct from an already published lease being invalidated, which violates the ownership contract.

Acquisition limits, retry/cancellation and shutdown follow the execution contract: external provider calls run outside internal locks, return under captured operation identity, and retain ownership until stopped/detached safely.
Provider failure, permission denial and incomplete capture are service/capability outcomes, not fabricated parse errors or successful empty source.
Expose consistency/completeness and selected identities with results, so the host can decide whether a syntax-only result is sufficient; do not bury a weakened capture guarantee in a cache hit counter.
Path-alias rules, per-document versus workspace-frontier conflict checks, snapshot capability names, retained-provider storage and absolute acquisition bounds remain approval decisions.

### Source Capture Acceptance Trace Drafts

These are future executable source-provider cases for C1/C2/C5, not tests already run or claims of coherent filesystem snapshots.

| Trace. | Required assertions. |
| --- | --- |
| V1: Overlay and disk race. | Capture an overlay while external disk events arrive, then save/reset through explicit host events.  Captured overlay bytes remain exact, separate disk state advances truthfully, and old-world reads do not change. |
| V2: Unknown versus absent. | Request an uncaptured dependency and contrast it with a provider-confirmed absent candidate.  Unknown yields incomplete/unavailable/unsupported as appropriate, never a definitive missing-name/module result. |
| V3: Late discovery. | Discover a dependency after a newer provider frontier exists.  Use qualified historical bytes/membership or require an explicit successor capture; no latest bytes are attached to the old query. |
| V4: Disk consistency limit. | Mutate files during sequential acquisition and preserve timestamps where possible.  Exact captured bytes/provenance are reported, and no atomic snapshot or stable-read guarantee is inferred from hashes/stat checks alone. |
| V5: Atomic source batch rejection. | Submit a multi-document transaction with one stale/invalid member or an ambiguous rename.  Reject all selection changes; a valid replacement transaction can subsequently commit one coherent frontier. |
| V6: Batch analysis ordering. | Accept a valid multi-document transaction, complete parsing out of order and fail one required task.  No mixed-revision aggregate milestone is published; accepted source remains truthful and retained prior analysis stays labelled old. |
| V7: Capture lifetime. | Close/reset a host buffer and release acquisition callback storage while an old capture is leased.  Published bytes remain exact; an adapter unable to protect them must have copied/rejected before acknowledgement. |
| V8: Provider failure and stop. | Race delayed provider completion with permission failure, cancellation and shutdown.  Return truthful outcomes, reject obsolete completion tokens and keep inputs alive until safe stop; never execute source or write editor files. |

The milestone-3 closure below specifies provider schemas/capability admission, namespace/path bindings, finite captures, transaction grammar, host attestations and checked limit negotiation.
Resolver discovery remains explicitly unsupported in this initial interface.
Real adapter/host guarantees and executable qualification remain open; no document schema proves filesystem/editor atomicity.
No source-capture trace is marked passed here; policy/scope/performance approvals, production implementation and the migration-plan gate remain open.

## Source Update and Query Interface Schema Draft

Drafted 2026-10-20.
The fifteen-operation interface is the approved specification baseline (2026-10-21), subject to exact schemas and API review.
This makes the source/update/query portion concrete under R1 and R3-R5; the milestone-3 closure fixes logical signatures, values and bounds.
Native ABI review remains open.
The notation below is a logical tagged-record schema, not Jai source or a persistent memory layout.
Outer request/session records carry the interface schema version, inherited by nested records; unknown versions/tags are rejected before accepting work, never interpreted as an empty successful operation.

### Record Shapes and Value Types

| Type. | Proposed v1 shape and meaning. |
| --- | --- |
| `InterfaceVersion`. | Exact supported schema identifier.  Changes to tags, field meaning or ownership require explicit compatibility/version rules. |
| `SessionID`, `WorkspaceID`, `DocumentID`, `ProviderRevision`, `ProviderFrontier`, `SourceRevision`, `ContextID`. | Distinct opaque identity types, never interchangeable strings or allocation addresses.  Use the canonical-key and authority rules below; adapter allocation/path binding remains subject to review.  Provider revisions/frontiers are namespace-scoped equality/order tokens, not wall-clock timestamps. |
| `Handle`. | `{session: SessionID, kind: HandleKind, slot: u64, generation: u64}`.  Kinds: `SESSION`, `WORLD`, `TICKET`, `WAITER`, `RESULT`, `SHUTDOWN`.  Validate session/kind/generation on every operation; retire a slot before generation wrap.  A handle identifies one owning registration, not a serialisable world/declaration identity. |
| `SessionOptions`. | `{version, workspace, provider_namespace, provider_capabilities, context, requested_limits, store_policy}`.  The host explicitly supplies required configuration/policy or requests a documented negotiated value; unspecified defaults are not silently chosen by this draft. |
| `SessionDescription`. | `{session_identity, workspace, provider_namespace, lifecycle, accepted_frontier, tracked_document_states, capabilities, consistency, effective_limits, store_status}`.  Return one coherent caller-owned value snapshot, not mutable borrowed coordinator storage.  It reports source selection/capabilities, not a published analysis world or atomic filesystem view. |
| `SourceInput`. | Tagged `INLINE_BYTES {bytes}` or `PROVIDER_LEASE {provider_identity, provider_revision, immutable_lease}`.  Inline bytes are borrowed only during submission; acceptance copies them or acquires an independent immutable lease.  The provider lease must be retained successfully before acknowledgement. |
| `ExpectedProviderState`. | Tagged `UNTRACKED` or `REVISION {provider_revision}`.  `UNTRACKED` matches only a document with no accepted provider state in this session; it is not confirmed absence and never bypasses a tracked revision conflict. |
| `DiskObservation`. | Tagged `PRESENT {source: SourceInput, source_revision, context: ContextID, observation_provenance:ObservationProvenance}` or `ABSENT {provider_revision, context, observation_provenance:ObservationProvenance}`.  Neither unknown membership nor permission denial is `ABSENT`.  Check revision claims against captured inputs/provider authority; do not trust an arbitrary digest field. |
| `RangeEdit`. | `{start_byte: u64, end_byte: u64, replacement: bytes}` with half-open endpoints into the current intermediate document bytes.  The enclosing event names the initial base revision; apply edits sequentially, checking ranges/overflow after each, then accept or reject the whole batch. |
| `DocumentEvent`. | `{document: DocumentID, expected_provider_state: ExpectedProviderState, source_context: ContextID, binding:Optional(DocumentBinding), event: EventPayload}`.  All required base/host-confirmation tokens are explicit, not inferred from timestamps or cache contents.  A first `SET_OVERLAY`, `OBSERVE_DISK` or host-confirmed `RESTORE_OVERLAY` may use `UNTRACKED`; editing, saving or resetting requires compatible tracked base state. |
| `SourceBatch`. | `{version, workspace: WorkspaceID, session: SessionID, expected_frontier: ProviderFrontier, contexts:[]ContextRegistration, events: []DocumentEvent, milestone: SYNTAX_INDEX}`.  Initially require one event per logical document; a range-edit event may contain its sequential edit list.  Reject an empty batch or unsupported milestone explicitly. |
| `AnalysisRequest`. | `{version, expected_frontier, documents: []DocumentID, milestone: SYNTAX_INDEX}`.  Request analysis of a nonempty, duplicate-free set of already tracked selected revisions under the membership rules below, without changing provider source state.  Unknown members or incompatible consistency reject explicitly; no hidden provider/disk read is implied. |
| `WorldDescription`. | `{world_identity, workspace, provider_frontier, configuration:ConfigurationID, members: []SelectedDocument, membership_completeness, consistency}`.  `SelectedDocument` carries document/context and tagged present source revision, confirmed absence, unknown or unavailable with reason.  The `WORLD` handle protects immutable description/source/index backing. |
| `QueryRequest`. | `{version, world: Handle(WORLD), document: DocumentID, kind: SYNTAX_SNAPSHOT. | SYNTAX_DIAGNOSTICS. | SYNTAX_DECLARATION_INDEX. | SEMANTIC_QUERY. | COMPILER_EVALUATION}`.  The first three request whole-document syntax-derived payloads without service-side filtering as specified below; the last two are known reserved capability tags returning `UNSUPPORTED` before task creation in this initial slice.  Unknown tags or invalid handles remain operation errors, not capability results. |
| `ResultDescription`. | `{result_identity, world_identity, document, source_revision_if_present, context, kind, completeness, diagnostics_status, payload}`.  `diagnostics_status` is the protected parse summary specified below, independent of payload coverage and diagnostic presentation availability.  `RESULT` owns access to its immutable payload and source-map backing; parse diagnostics do not turn usable syntax into a service failure. |
| `CompletionRecord`. | `{registration: Handle(WAITER), operation_identity, terminal_kind, world_identity_if_known}`.  A host-drained record is informational, not a payload lease.  Use its still-live registration to inspect/acquire the protected result; stale/released generations reject. |

Counts, bytes, decoded sizes and accepted registrations must have concrete checked limits before implementing this schema.
The fixed-width handle fields do not bound total allocations or authorise wrapping IDs; no client may fabricate a valid registration by copying a logical identity into a slot.

#### Analysis Membership, Duplicates and Ordering

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
The milestone-3 `Limits` contract requires explicit `capture_documents` and `elements_per_list` ceilings before allocating/sorting; their absolute host values remain an R6 policy input, not a default chosen here.

The discriminating future cases compare `[A, B]` with `[B, A]` at one frontier and reject `[A, A]`: the first pair has equal logical membership but distinct caller registrations, while the duplicate request admits no partial work.
Additional independent cases cover equal source bytes in distinct documents, provider-qualified aliases, digest-collision safeguards, foreign identities, worker completion permutations and sequential source edits whose order must not change.
Assert exact canonical member order, requested sets, identity separation and unchanged source state on rejection.
This draft selects no path-alias policy or new shared-task key format.

### Canonical Identity and Payload Refinement

Proposed 2026-10-21 under the approved specification baseline; not final API, persistent wire grammar or implementation approval.
The following defines equality and hash-input bytes independently of Jai struct padding, native pointers and text-file formatting.
The milestone-3 closure supplies logical provider and node/value records; milestone 4 supplies live namespace allocation/continuity and conservative semantic identity matching.
Adapter/API approval and executable qualification remain separate.
No store defaults or resource budgets are selected here.

Define `B(x)` as an unsigned 64-bit little-endian byte count followed by exactly the bytes of `x`.
Define `K(tag, fields)` as `B(ASCII("jai-cache-key"))`, unsigned 32-bit little-endian key-schema version `1`, `B(ASCII(tag))`, unsigned 64-bit little-endian field count, then each field encoded with `B` in declared order.
Nested keys are complete `K` byte sequences used as fields, not unframed concatenations; numeric fields have explicitly declared widths and little-endian encoding.
Lengths must be representable and checked before allocation/addition; a 64-bit length is not permission to allocate that much memory.
Hashing uses SHA-256 over the complete key bytes, but the key descriptor remains available for equality/validation; a digest alone is not a logical identity or proof of source authority.
This is a canonical fingerprint input, not a replacement for the proposed versioned text persistence format.

| Value. | Proposed canonical identity and authority. |
| --- | --- |
| Namespace token. | Nonempty opaque bytes issued by its responsible owner, compared byte-for-byte without Unicode normalisation, case folding or separator rewriting.  The adapter must bind the token to one authority/configuration and never reassign it to a different one while references/recovery records can survive.  An unverified binding is rejected or assigned a fresh namespace, not guessed from a display path. |
| `WorkspaceID`. | `K("workspace", [host_namespace, workspace_token])`.  The host decides whether a reopened workspace has the same identity; cache discovery cannot choose it.  Shared project paths do not implicitly merge separate workspaces. |
| `DocumentID`. | `K("document", [provider_namespace, document_policy_version, provider_document_key])`.  The provider registers the resolved absolute-path binding and its alias/case/link policy; the service does not independently lowercase or resolve it.  Source-visible path/directory spelling remains separate context input.  Deletion/reappearance preserves or changes this key only according to the declared provider policy. |
| `SessionID`. | `K("session", [service_incarnation_namespace, session_token])`, issued by the service.  The incarnation namespace is never reassigned while old references/records can survive; session tokens are not reused within it.  Neither is derived from workspace/path/content; owner routing is validated before slot lookup.  Restart creates a new incarnation and rejects every old handle even if persisted workspace/document keys match.  Milestone 4 specifies the reserved-epoch/checked-counter allocator; issuer qualification and API review remain open. |
| `ProviderRevision`. | `K("provider-revision", [provider_namespace, session_identity, document_identity, provider_state_token])`.  A token identifies one accepted combined disk/overlay state, not just selected bytes.  The provider cannot reuse it for a different state; rejected batches do not install a new token. |
| `ProviderFrontier`. | `K("provider-frontier", [provider_namespace, session_identity, frontier_token])`.  The coordinator records the accepted-event order; token bytes/digests are not lexicographic clocks.  Retry analysis leaves the frontier unchanged, and a rejected transaction creates no accepted successor. |
| `SourceRevision`. | `K("source", [source_key_version_u32, byte_count_u64, SHA256(exact_source_bytes)])`, with source-key version `1`.  Exact bytes remain the authority; collision ambiguity rejects affected reuse rather than merging different sources.  Equal empty/present sources can share this value across documents, but confirmed absence has no source revision.  No BOM stripping, newline conversion, decoding or trailing-NUL insertion is part of identity. |
| `ContextID`. | `K("context", [context_schema_identifier, canonical_context_descriptor])`.  The versioned descriptor includes syntax configuration/parser schema and all source-visible path/resolution inputs used by that result; semantic extension fields must include the `SemanticContextID` inputs from [architecture section 3](CACHE_ARCHITECTURE.md#3-terms-and-identities) before semantic reuse is supported.  An opaque host label alone cannot establish equivalent context. |
| World/result/operation identity. | Service-issued, session-scoped, typed nonreused tokens, distinct from registration handles and from content keys.  Repeated analysis may produce a distinct world/result identity at the same frontier.  Equality of those tokens never authorises restoring handles from persistence. |

For `ContextID`, descriptor records use named, versioned fields in schema-declared order; nested sequences preserve order unless that field's schema explicitly defines set semantics and canonical sorting.
This service configuration identity is not Jai's `#Context` type.
A future semantic descriptor containing the completed language context must use [architecture section 6.3](CACHE_ARCHITECTURE.md#member-order-and-the-completed-context-type)'s ordered-base/unordered-additions rule, not encode compiler encounter order as type identity.
Reject duplicate/unknown fields and missing required fields for the selected schema rather than dropping them during hashing.
The syntax-only descriptor registry below is proposed for API review; until its producer/adapter bindings are validated, an adapter cannot claim cross-session context equivalence or persistent derived-result reuse from this recipe alone.
Opaque provider path keys need not be UTF-8; adapters retain native source-visible spelling without lossy conversion and define its descriptor encoding explicitly.
Handle transport, if later added, must encode its fields explicitly and validate the live owner/registration; it is never a persistent identity record.

#### Syntax Context Registry and Adapter Bindings

Proposed 2026-10-21, not approved adapter/API behaviour.
The initial context schema identifier is ASCII `jai-cache-syntax-context/1`.
Its descriptor is `K("syntax-context-descriptor", fields)` with exactly the following ten fields in table order; each field is itself `K(field_name, values)`.
Field names/tags/schema identifiers are exact ASCII; booleans are one byte `0` or `1`, and version numbers explicitly marked `u32` are unsigned little-endian.
There are no omitted/default fields or generic extension maps in this schema.
Unknown schemas, duplicate/reordered fields, invalid booleans and missing required values reject before accepting a context.
The registry is closed for the syntax-first scope, not an assertion that these fields suffice for future semantic/evaluator contexts.

| Field name. | Ordered values and authority. |
| --- | --- |
| `producer`. | Service-verified producer namespace, immutable parser implementation/build identity, compiler SDK/layout identity, lexer implementation identity, and the syntax-payload adapter build identity plus canonical capability binding specified below, in that order.  These identify the implementation actually used, not an unverified client-supplied version label.  A change conservatively misses even if output compatibility is suspected.  This refines the still-unimplemented context-registry draft; it does not reinterpret an existing qualified v1 context. |
| `syntax_schemas`. | Token, node, recovery and declaration-index schema identifiers, in that order.  Each resolves to an exact supported field/variant registry; an unknown registry cannot be accepted merely because its identifier hashes successfully. |
| `parser_parameters`. | `ENABLE_TRIVIA`, `EVALUATE_STRING_ESCAPES`, `INTERN_IDENTIFIERS`, `USE_SIMD`, `TRACK_AST_REUSE`, in the declaration order of the current module parameters, each as a boolean.  The full-featured initial profile requires `ENABLE_TRIVIA = true`; reject a false value at profile admission rather than supporting a second byte-mapping path.  All five remain conservatively keyed, including instrumentation/implementation choices; removing a field requires a new schema and equivalence evidence. |
| `parse_profile`. | Registered grammar/language profile identifier and recovery-policy identifier.  V1 supports only explicitly implemented profiles; no unkeyed runtime parser option or hidden host default may affect results.  A newly exposed parse option requires a schema revision before reuse. |
| `diagnostic_profile`. | Diagnostic schema identifier, registered message/severity-policy identifier and presentation-language identifier.  The producer validates the selected policy; changing diagnostic text/order/policy cannot reuse a result under an unchanged profile.  An unsupported localisation is rejected, not silently substituted. |
| `visible_filename`. | One `PathValue` preserving the exact source-visible filename spelling supplied for this occurrence, including retained dot/parent segments and alias spelling.  It is not inferred from a canonical physical key. |
| `visible_directory`. | One `PathValue` preserving the effective source-visible directory independently of filename.  This records context for `#filepath`/location-sensitive results without evaluating those constructs as context-free literals. |
| `relative_base`. | One `PathValue` for the explicit absolute base used for relative-request interpretation.  No later dependence on process working directory is permitted. |
| `resolver_binding`. | `K("NO_RESOLUTION", [])` for an initial syntax-only capture that does not resolve imports/loads, or `K("RESOLVER_CONFIG", [resolver_schema, canonical_registered_descriptor])` only for an explicitly supported resolver schema.  V1 baseline requires only `NO_RESOLUTION`; it is not an empty/complete search result.  Authored import/load requests remain syntax, not resolved membership. |
| `semantic_extension`. | Exactly `K("UNSUPPORTED", [])` in this schema.  Module/program arguments, target/layout facts and evaluator policies are not silently ignored inputs to semantic reuse; requests requiring them return the reserved unsupported capability outcome.  A supported semantic schema must enumerate those inputs separately. |

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
Exact payload projection, provider-policy alternatives, access signatures and admission-bound negotiation are supplied by the milestone-3 closure below.

All three supported query payloads use a versioned envelope `{payload_schema, world_identity, document, source_revision, context, completeness, data}`.
Identity bindings must equal the `ResultDescription` and the selected present member of the queried world; `completeness` must agree with the result description under the kind-specific rules below.
Missing/unknown/unavailable members produce their explicit query outcome rather than a fabricated empty payload.
An empty present file can produce available empty diagnostics/index results, but a syntax snapshot still represents that exact empty source revision.
Envelope access and all nested views borrow from the owning `RESULT`; an independent copy or retained result is required to outlive it.

| Payload. | Required logical data and limits of meaning under the selected schema. |
| --- | --- |
| Common span. | `{document, source_revision, start_byte:u64, end_byte:u64}` with `0 <= start_byte <= end_byte <= exact_source.count`.  Zero-width insertion/recovery spans are permitted.  A span from another revision is not remapped implicitly; generated/unlocated items require an explicit tagged origin, not an out-of-range sentinel. |
| `SYNTAX_SNAPSHOT`. | Exact owned source bytes, syntax-schema identifier, token sequence, root/node records and recovery information needed for C1 comparison.  Node references are snapshot-local IDs resolved only within this envelope, not pointers, declaration identities or global IDs.  The schema must enumerate node/token variants and every observable child/list/span field before API approval; exposing today's mutable `Parser_Node` memory is not this contract. |
| `SYNTAX_DIAGNOSTICS`. | Ordered records under `jai-cache-syntax-diagnostics/1` as specified below, including code, severity, origins/messages, token details and recovery action.  Preserve parser emission order; do not deduplicate by message or location.  A malformed source diagnostic is an available syntax result, not a service failure. |
| `SYNTAX_DECLARATION_INDEX`. | `{coverage, entries: []IndexEntry, shared_regions: []SharedRegion}` under the draft `jai-cache-syntax-declaration-index/2` contract below.  Entries follow declaration-event/binding-group order, not a global span sort; entry/region/node IDs occupy distinct result-local domains.  Names separate exact source spelling from producer values; visibility records same-list provenance, not resolved accessibility.  Recovery and coverage retain explicit uncertainty.  Repeated/anonymous/recovered declarations are not merged by name; this index promises neither nominal `DeclarationID` continuity nor semantic lookup/completeness. |

Messages are strict UTF-8 presentation text.
Source bytes and spelled-name bytes preserve exact parser input slices; producer-name bytes instead preserve the exact producer value, which can differ from the source spelling.
Neither byte domain is required to be valid UTF-8 for this interface.
Any line/column or editor UTF-16 conversion belongs to an explicit adapter mapping for the same source revision; byte ranges never silently become character indices.
The existing syntax payload must preserve malformed/incomplete-source observations under C1 even where a diagnostic/index presentation needs an explicit unavailable field.
The logical optional/tag records below and the milestone-3 snapshot projection are drafts for review, not an implemented wire format or qualified adapter.

#### Query Schema Selection and No-Fallback Binding

Proposed clarification of the existing interface version, context registries and payload envelope; no per-query schema selector is added.
`QueryRequest.version` selects the operation/record contract, not an instruction to choose the newest payload schema.
The queried world's selected document context fixes the producer/adapter, registry tuple and profiles used for its syntax results.
Session capability descriptions may advertise several supported schemas, but admission must bind one exact compatible tuple to each context before work is accepted.
An advertised alternative is not an implicit fallback for a retained world.

| Query kind. | Authority for the envelope's `payload_schema`. |
| --- | --- |
| `SYNTAX_SNAPSHOT`. | The exact registered snapshot-envelope mapping for the context's node/token/recovery schemas and parse profile.  Its payload-schema identifier and field mappings must be registered explicitly; do not guess an envelope schema from a node-layout name or concatenate version strings. |
| `SYNTAX_DIAGNOSTICS`. | The diagnostic schema selected by `diagnostic_profile`, with its bound severity/message/language policy and compatible token/origin mappings. |
| `SYNTAX_DECLARATION_INDEX`. | The declaration-index schema selected by `syntax_schemas`, with the context's exact adapter/registry capability binding. |

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
Assert exact context/envelope bindings, unsupported-versus-failed outcomes and retained old-result access.
The milestone-3 closure supplies the snapshot schema and public accessor signatures.
Implemented registry/compatibility validation and executable retained-schema qualification remain open.

#### Syntax-Index Milestone and Per-Query Readiness

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
Assert exact ticket/query outcomes, requested-member bindings, immutable coverage/summaries and absence of deferred required index work.
The milestone-3 closure supplies API signatures and explicit retention-bound inputs.
The scheduling draft is supplied by milestone 5; optional R6 quotas, effective technical bounds and real concurrent implementation tests must respect the 2026-10-23 no-fixed-quota decision.

#### Whole-Document Queries and Caller-Side Selections

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
Assert full payload contents, unchanged IDs/references/coverage and explicit invalid-request/resource outcomes.
This draft does not implement host UI filtering or extend the fifteen-operation interface.

#### Derived Payload Backing and Node Reference Access

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
Exact accessor signatures and the backing node/helper projection are supplied by the milestone-3 closure; API approval and executable backing/lifetime qualification remain open.
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
Assert exact records and byte lifetimes plus rejection of invalid references; no executable accessor or backing resolver is supplied here.

#### Result Diagnostic Status Summary

Proposed definition of the existing `ResultDescription.diagnostics_status`, shared by the three syntax query kinds rather than inferred from each query's displayed records.
Its logical shape is `{parse_status, error_count:u64, warning_count:u64}`.
`parse_status` is the protected producer's `COMPLETE. | INCOMPLETE. | RECOVERED. | FATAL`; counts include every emitted diagnostic of the corresponding severity in that same parse, before any host display selection.
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
Assert exact summary/payload agreement and separate failure channels.
This draft defines neither a severity-filtered service query nor a compiler-validity summary.

#### Envelope Completeness and Query Availability

Proposed logical refinement of the existing envelope and `ResultDescription`, not an additional operation or a production publication mechanism.
For these three syntax query kinds, `completeness` is the closed union `EXACT_SYNTAX_CAPTURE. | COMPLETE_DIAGNOSTIC_OBSERVATION. | DECLARATION_INDEX_COVERAGE {coverage}`.
Select exactly the arm registered for the result's query kind and payload schema; reject unknown or wrong-kind arms rather than treating them as a generic complete/partial boolean.

| Query kind. | Required completeness value and meaning. |
| --- | --- |
| `SYNTAX_SNAPSHOT`. | `EXACT_SYNTAX_CAPTURE`: all required source/token/node/recovery observations of this protected parse are preserved under the admitted snapshot schema.  It does not assert a successful parse, complete language coverage or semantic closure. |
| `SYNTAX_DIAGNOSTICS`. | `COMPLETE_DIAGNOSTIC_OBSERVATION`: all emitted diagnostics of this protected parse are represented in emission order under the diagnostic schema, including explicit unlocated origins where required.  It does not assert that the parser detected every language error or that the source is valid. |
| `SYNTAX_DECLARATION_INDEX`. | `DECLARATION_INDEX_COVERAGE {coverage}`: the enclosed value is exactly `data.coverage`, including every ordered structured reason when partial.  The existing traversal/observation contract, not query completion time, determines that value. |

The `ResultDescription` and envelope must agree on this entire value, not merely a hash, reason count or complete/partial tag.
Conflicting outer/inner index coverage is invalid publication or stored-result validation, not a choice left to clients.
An admitted query becomes `Available` when its protected, validated payload and description can be acquired atomically.
A partial index is an available final result with explicit gaps; it is not a pending registration promising that this immutable result will later fill them.
A later analysis/context can produce another result, but retained descriptions, payloads and coverage remain unchanged.
Cancellation or failure that wins before publication retains its existing request outcome instead of publishing a prefix as though the query completed normally.

Keep four questions separate: request availability, preservation of the selected payload's observations, parser status (`COMPLETE. | INCOMPLETE. | RECOVERED. | FATAL`) and world membership/provider consistency.
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
Assert the exact outcomes and immutable outer/inner values against independent expectations.
The milestone-3 closure supplies detailed signatures, snapshot-schema projection and required numeric-limit negotiation.
Concrete R6 values, API approval and release qualification remain open.

#### Diagnostic Origins and Declaration Index Records

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

`jai-cache-syntax-diagnostics/1` `data` is `{parse_status, records: []Diagnostic}`.
`parse_status` is `COMPLETE. | INCOMPLETE. | RECOVERED. | FATAL` from the protected parse, not a judgement of semantic validity.
`Diagnostic` is `{code, severity, primary_origin, message_utf8, related: []RelatedDiagnostic, parser_observation}`; `RelatedDiagnostic` is `{origin, message_utf8}`.
Codes map one-to-one from the current parser's named kinds: `EXPECTED_TOKEN`, `EXPECTED_EXPRESSION`, `UNEXPECTED_TOKEN`, `UNNECESSARY_SEMICOLON`, `LEXER_ERROR`.
Severity is `ERROR. | WARNING`; recovery action is `NONE. | INSERT_MISSING_TOKEN. | SKIP_TOKENS`.
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

`jai-cache-syntax-declaration-index/2` `data` is `{coverage, entries: []IndexEntry, shared_regions: []SharedRegion}`.
`coverage` is `COMPLETE_SYNTAX_TRAVERSAL` or `PARTIAL_SYNTAX_TRAVERSAL {reasons: []CoverageReason}` under the structured reason contract below; completeness concerns traversal of this captured parse, never import closure or semantic membership.
Recovery does not automatically mean partial traversal, and a complete traversal can contain recovered entries.
`IndexEntry` is `{local_entry_id, declaration_node_id, name, syntax_kind, declaration_origin, container, visibility_syntax, program_export_syntax, recovery_status}`.
`name` is `SPELLED {origin:SOURCE, spelling_bytes, producer_name_bytes, form, recovery_origins: []Origin}`, `ANONYMOUS`, `MISSING {origin}`, or `UNMAPPED {producer_name_bytes, reason}`.
`form` is `IDENTIFIER. | OPERATOR`; spelled bytes must equal their source slice, while producer-name bytes preserve the parser's possibly different name value under the rules below.
Anonymous, missing and unmapped names are distinct, not empty identifiers.
`container` is `ROOT. | DECLARATION {local_entry_id} | SHARED_REGION {local_region_id}` and `recovery_status` is `PARSED. | RECOVERED. | UNCLASSIFIED {reason:CoverageReason}` under the attribution rules below.
The version change makes shared ownership explicit; these are replacement drafts, not compatibility promises for an implemented v1/v2 payload.
`syntax_kind` is `DECLARATION. | COMPOUND_BINDING. | ENUM_MEMBER`; it describes the declaration grammar, not whether an initialiser eventually denotes a procedure/type/value.
A compound declaration emits one entry per newly declared binding in authored order, sharing the declaration node/origin; assigned targets are uses, not index declarations.
`ENUM_MEMBER` is the context-qualified bare enum-member occurrence described below, not any identifier in an enum's subtree.
Preserve repeated declared names and infer no semantic category from spelling.
Entries follow the declaration-event order specified below: enclosing declarations and a compound's binding group precede their descendants, with registered authored child/binding order rather than a global span sort.
Declaration containers refer only to earlier enclosing entries.
Shared-region containers follow the acyclic ownership rules below; validate both ID domains and reject cycles, never treat an arbitrary local ID as a pointer or nominal declaration identity.
`visibility_syntax` is `{scope_directive, scope_basis, declaration_marker, observations}`.
`scope_directive` is `UNSPECIFIED. | SCOPE_EXPORT. | SCOPE_MODULE. | SCOPE_FILE. | RECOVERED_UNKNOWN`; `scope_basis` records the same-list provenance specified below.
`declaration_marker` is `UNSPECIFIED. | EXPORT. | RECOVERED_UNKNOWN`; `observations` preserves the ordered directive/marker source spans used to derive those syntactic tags.
These are authored `#scope_export`, `#scope_module`, `#scope_file` and `#export` observations, not a claim of resolved accessibility, valid marker placement, conditional activation or completed exports.
Unsupported/malformed observations remain recovered/partial with reasons rather than being coerced to exported or private.
Do not execute conditions, follow imports/loads, expand `#add_context`, evaluate `using,map`, or merge instantiated members while building this index.
Walk only owned authored/recovered syntax; complete traversal of it is compatible with semantic queries remaining unsupported.
Exact node/token variant registries and traversal-to-current-node mapping still need API review; this draft does not certify that the current parser exposes every marker without an adapter or lossless source observation.

Future acceptance vectors: end-of-file zero-width and inserted-token origins; unmappable lexer/token locations with preserved raw observations; duplicate diagnostics and ordered related messages; invalid message encoding; compound/repeated/anonymous/recovered names; nested containers; visibility changes; partial versus complete syntax traversal without evaluator execution.
Validate these against fresh owned parser observations under C1/C5.
This document refinement neither implements those tests nor selects numeric admission limits, adapter defaults or a persistent payload wire format.

### Source Event Payloads

| Tag. | Required payload and transition. |
| --- | --- |
| `SET_OVERLAY`. | `{source: SourceInput, resulting_provider_revision}`.  Install the exact host-selected buffer over the separately retained disk state. |
| `EDIT_OVERLAY`. | `{base_source_revision, edits: []RangeEdit, resulting_provider_revision}`.  Reject base mismatch, invalid ranges or missing editable source; do not silently edit another revision. |
| `OBSERVE_DISK`. | `{disk: DiskObservation, resulting_provider_revision}`.  Advance acknowledged disk state, preserving any active overlay; select disk/absence only when no overlay takes precedence. |
| `ACK_SAVE`. | `{written_source_revision:SourceRevision, disk: DiskObservation(PRESENT), expected_overlay_revision:ProviderRevision, resulting_provider_revision}`.  Record the actual written bytes and reconcile only the overlay installation revision the host confirms was saved; preserve a newer overlay even when its bytes are identical. |
| `RESET_OVERLAY`. | `{host_confirmation, disk: DiskObservation, resulting_provider_revision}`.  Clear active overlay/recovery selection and choose this acknowledged disk observation.  No hidden latest-disk read occurs during submission. |
| `RESTORE_OVERLAY`. | `{host_confirmation, recovery_candidate_identity, source: SourceInput, resulting_provider_revision}`.  Activate only the exact host-confirmed bytes; a recovery blob alone never authorises this event. |

Deletion is an absent disk observation, not an empty `SourceInput`.
Rename/cross-document identity transfer is initially an unsupported event capability until its grammar/identity mapping is specified; callers may submit an explicit old-path absence plus new-path source selection only when the provider confirms those separate document identities and no semantic continuity is claimed.
Closing a buffer must be expressed by the host's chosen source transition, not an implicit reset inferred from releasing a result handle.
This proposed event subset still needs host-adapter review; it does not write editor files or implement save/recovery UI.

### Operation and Outcome Table

Operation errors are tagged `INVALID_VERSION`, `INVALID_ARGUMENT`, `INVALID_HANDLE`, `BASE_MISMATCH`, `UNSUPPORTED_EVENT`, `ADMISSION_DENIED`, `ACTIVE_SESSION`, or `SERVICE_CLOSED`, with contextual details but no successful source transition.
Provider acquisition errors during admission return a specific unavailable/failure reason without partial acceptance; cache persistence failure alone is not admission failure.
Terminal observations are ticket outcomes `PUBLISHED. | SUPERSEDED. | CANCELLED. | FAILED` or query outcomes `AVAILABLE. | UNAVAILABLE. | UNSUPPORTED. | CANCELLED. | FAILED`, with their original selected identities/reasons.
Shutdown observation is `PENDING {phase: QUIESCING. | DRAINING}` until terminal `STOPPED {persistence_status, cleanup_diagnostics}`; a wait deadline does not create another terminal shutdown state.
`PENDING` and `TIMED_OUT_PENDING` are observation states, not terminal outcomes or permission to select newer input.

| Operation. | Input. | Result and exact ownership/state effect. |
| --- | --- | --- |
| `OpenSession`. | `SessionOptions`. | `OPENED {session: Handle(SESSION), description: SessionDescription}` or `REJECTED {error}`.  Allocate a fresh session identity, return the initial accepted frontier and negotiated capability/limit policy, and start with no published analysis head.  Persisted candidates do not become active overlays or live handles.  Store failure may report degraded in-memory operation; no partial session escapes rejection. |
| `DescribeSession`. | Live `SESSION`. | Coherent value `SessionDescription`; does not advance source state, acquire a world/result lease or activate recovery.  Reading a frontier does not reserve it: a later submit must still validate that base. |
| `SubmitSourceBatch`. | Live `SESSION` plus matching `SourceBatch`. | `REJECTED {error}` or `ACCEPTED {ticket: Handle(TICKET), accepted_frontier}`.  Own all input before one atomic source-selection transition; return a ticket even if its milestone finishes quickly.  Parse/index or durable-store completion is not implied by acceptance. |
| `RequestAnalysis`. | Live `SESSION` plus `AnalysisRequest`. | `ACCEPTED {ticket: Handle(TICKET), analysed_frontier}` or `REJECTED {error}`.  Lease the exact selected revisions at that frontier and schedule/join analysis without advancing it.  Supports retry after failed/superseded work without an empty source batch, replayed save event or invented edit. |
| `ObserveTicket`. | Live `TICKET`. | Atomic terminal observation or `PENDING {waiter: Handle(WAITER)}`.  Each call creating a waiter creates a separately owned notification registration; ordinary repeated polling should use `Poll`, not repeatedly register. |
| `AcquireWorld`. | Selector `PUBLISHED_UPDATE {ticket_or_update_waiter}` or `HEAD {workspace, expected_frontier}`. | Owned `WORLD`, pending/unavailable, or operation error.  The ticket/update waiter must have a `PUBLISHED` outcome; `HEAD` succeeds only if the published analysis frontier matches the explicitly expected frontier.  Otherwise, report a descriptive pending/frontier-mismatch/no-head reason without creating a waiter; use the ticket or `RequestAnalysis` to obtain an observable milestone.  An omitted selector is `INVALID_ARGUMENT`; there is no implicit latest world. |
| `Query`. | `QueryRequest`. | `AVAILABLE {result: Handle(RESULT)}`, an immediate terminal reason, or `PENDING {waiter: Handle(WAITER)}`.  Acquire result protection or register a current-world waiter atomically with inspection; an obsolete world needing fresh work returns `CANCELLED {reason:WORLD_SUPERSEDED}` without task/waiter creation.  An immediate answer creates no completion notification. |
| `Poll`. | Live `TICKET`, `WAITER` or `SHUTDOWN`. | Stable terminal observation or `PENDING`; no new waiter, no consuming transition and no new payload lease.  An available observation is descriptive until `AcquireResult`; a published observation is descriptive until `AcquireWorld`. |
| `Wait`. | Same handle plus monotonic deadline. | Same observation as `Poll`, or `TIMED_OUT_PENDING`.  Does not cancel, register another completion record, block a required host dispatch thread safely by magic, or change the selected world. |
| `AcquireResult`. | Live query `WAITER` with `AVAILABLE` terminal outcome. | New owned `RESULT`; pending/terminal reason otherwise.  Inspection and acquisition are atomic against registration release, so no borrowed payload escapes.  Repeated acquisition creates independent leases that must each be released. |
| `CancelWaiter`. | Live `WAITER`. | `CANCELLED` with reason `CALLER` if it wins the terminal race, otherwise `ALREADY_TERMINAL {observation}`, including an earlier `WORLD_SUPERSEDED`.  Does not undo source, release the handle or cancel other consumers; task-wide supersession is generated by source acceptance, not a caller-supplied task-stop flag. |
| `DrainCompletions`. | Live `SESSION` plus checked maximum count. | Bounded completion records for live pending registrations, at most one terminal record per registration.  Draining does not release registrations or transfer result ownership; records released/reused before later access are safely stale. |
| `Retain`. | Live `WORLD` or `RESULT`. | New independently owned handle protecting the same immutable payload; copying the original handle bits is not a retain.  Operation fails safely if release won the race. |
| `Release`. | Any owned handle. | Retire that registration exactly once; subsequent uses, including double release, return `INVALID_HANDLE` without touching a new generation.  A `SESSION` may be released only after `STOPPED`; otherwise return `ACTIVE_SESSION` without retiring it.  Waiter release detaches interest, not source state; active task/delivery ownership persists until its own release. |
| `RequestShutdown`. | Live `SESSION`. | Owned `SHUTDOWN` observation handle; repeated calls refer to the same shutdown operation through separate owned registrations.  It rejects new work at quiescing, preserves existing leases/observation/release access, and never reports stopped merely because a wait deadline elapsed. |

### Milestone 3: Exact Logical Call Signatures

The following is the closed logical interface `jai-cache-interface/1`, drafted for API review, not a machine ABI, generated Jai module or transport protocol.
`Call(T)` is exactly `OK {value:T} | REJECTED {error:OperationError}`.
Operation rejection is distinct from a successfully observed terminal failure, unavailability or unsupported capability.
All arguments and nested input arrays/bytes are borrowed only until the call returns; any accepted asynchronous work must already own its required copies/leases.
Returned handles are independently owned registrations; returned description/observation/completion values are caller-owned copies, never borrowed coordinator storage.

```text
OpenSession(options: SessionOptions) -> Call(Opened)
DescribeSession(session: Handle(SESSION)) -> Call(SessionDescription)
SubmitSourceBatch(session: Handle(SESSION), batch: SourceBatch) -> Call(AcceptedBatch)
RequestAnalysis(session: Handle(SESSION), request: AnalysisRequest) -> Call(AcceptedAnalysis)
ObserveTicket(ticket: Handle(TICKET)) -> Call(TicketObservation)
AcquireWorld(selector: WorldSelector) -> Call(WorldAcquisition)
Query(request: QueryRequest) -> Call(QueryStart)
Poll(observable: ObservableHandle) -> Call(Observation)
Wait(observable: ObservableHandle, deadline: Deadline) -> Call(WaitObservation)
AcquireResult(waiter: Handle(WAITER)) -> Call(ResultAcquisition)
CancelWaiter(waiter: Handle(WAITER)) -> Call(CancelOutcome)
DrainCompletions(session: Handle(SESSION), maximum: u64) -> Call(CompletionBatch)
Retain(payload: RetainableHandle) -> Call(Retained)
Release(owned: Handle) -> Call(Released)
RequestShutdown(session: Handle(SESSION)) -> Call(ShutdownRequested)
```

`ObservableHandle` is a live `TICKET. | WAITER. | SHUTDOWN`; `RetainableHandle` is a live `WORLD. | RESULT`.
These are checked handle-kind restrictions, not unchecked casts.
`WorldSelector` is `PUBLISHED_UPDATE {registration:Handle(TICKET)|Handle(WAITER)}` or `HEAD {session:Handle(SESSION), workspace:WorkspaceID, expected_frontier:ProviderFrontier}`.
The first arm requires an update ticket/waiter, not a query waiter; its surviving registration routes to its owner even after the original session registration is released.
The second requires the named live session and its workspace; there is no implicit process-wide current workspace/head.

The exact response records, payload access family, adapter descriptors, canonical value grammar and checked bound negotiation are specified by the milestone-3 closure below.
They refine this unimplemented draft and do not add a sixteenth scheduling/source operation.
An implementation may expose equivalent typed Jai procedures, but must not change ownership, invent success defaults, or claim binary ABI compatibility from this notation.
Disk serialisation, store policy defaults, scheduling policy and semantic query implementation remain their separate milestones.

Payload access requires a live owning `WORLD`/`RESULT` handle.
Read-only descriptions/views borrow from that handle and cannot be used after its release; copies that must survive need their own host storage or `Retain` first.
Tickets and their pending observation waiters each protect the published world until independently released; query waiters protect their terminal result until released.
`AcquireWorld` accepts a published update waiter even after its original ticket registration was released; acquiring a child handle establishes independent protection before the parent can be retired.
Polling/draining is deliberately non-owning to avoid hidden lease growth in a UI polling loop.
No handle survives a process restart, and shutdown never turns an externally retained result into a borrowed pointer to destroyed service state.
After releasing a stopped `SESSION`, already owned child handles remain observable/releasable through their surviving owner; no operation may require borrowing the released session handle to keep a result alive.

### Milestone 3: Response Catalogue and Borrowed Access

The records in this section complete the call signatures above.
Record field order is the order written here; unions have exactly the listed arms, including explicit empty arms.
`Optional(T)` retains the previously defined `NONE. | SOME {value:T}` convention.
`WorldID`, `ResultID` and `OperationID` mean the distinct session-scoped world/result/operation identities already specified, not new handle kinds.
Their canonical recipes are respectively `K("world", [SessionID, token])`, `K("result", [SessionID, token])` and `K("operation", [SessionID, token])`, with a nonempty service-issued token never reassigned within its typed session domain; milestone 4 specifies allocation/continuity mechanics, with implementation qualification still open.
`QueryKind` has the five tags listed in `QueryRequest`, in that registry order.
`ResultDescription.source_revision_if_present` is `Optional(SourceRevision)` and is always `SOME` for an available syntax result; no `RESULT` is acquired for absent/unknown/unavailable input.
Its `payload` is exactly the registered envelope, whose `data` is typed by `payload_schema`; protected backing is reachable only through its registered views/resolvers, not a second mutable `payload`.
`CompletionRecord.world_identity_if_known` is `Optional(WorldID)`, and `terminal_kind` is `UPDATE {kind:PUBLISHED|SUPERSEDED|CANCELLED|FAILED}` or `QUERY {kind:AVAILABLE|UNAVAILABLE|UNSUPPORTED|CANCELLED|FAILED}`, matching the registration's terminal outcome.
`Unit` has no fields.
A field named `observation` never transfers a result/world lease.

| Response type. | Exact logical value. |
| --- | --- |
| `Opened`. | `{session:Handle(SESSION), description:SessionDescription}`. |
| `AcceptedBatch`. | `{ticket:Handle(TICKET), accepted_frontier:ProviderFrontier}`. |
| `AcceptedAnalysis`. | `{ticket:Handle(TICKET), analysed_frontier:ProviderFrontier}`. |
| `TicketTerminal`. | `PUBLISHED {world_identity:WorldID, milestone:SYNTAX_INDEX}` or `SUPERSEDED {successor:Optional(OperationID)}` or `CANCELLED {reason:CancellationReason}` or `FAILED {failure:Failure}`.  A successor identity is descriptive, not an acquired ticket. |
| `QueryTerminal`. | `AVAILABLE {result_identity:ResultID}` or `UNAVAILABLE {reason:UnavailableReason}` or `UNSUPPORTED {reason:UnsupportedReason}` or `CANCELLED {reason:CancellationReason}` or `FAILED {failure:Failure}`. |
| `ShutdownTerminal`. | `STOPPED {persistence_status:StoreStatus, cleanup_diagnostics:[]ServiceDiagnostic}`. |
| `TicketObservation`. | `TERMINAL {observation:UpdateObservation}` or `PENDING {waiter:Handle(WAITER)}`.  Only the pending arm allocates a notification registration. |
| `UpdateObservation`. | `{operation_identity:OperationID, provider_frontier:ProviderFrontier, documents:[]DocumentID, outcome:TicketTerminal}`; documents are the exact requested milestone set in canonical membership order. |
| `QueryObservation`. | `{operation_identity:OperationID, world_identity:WorldID, document:DocumentID, context:ContextID, kind:QueryKind, outcome:QueryTerminal}`. |
| `Observation`. | `UPDATE {value:UpdateObservation}` or `QUERY {value:QueryObservation}` or `SHUTDOWN {value:ShutdownTerminal}` or `PENDING {operation_identity:OperationID, phase:QUEUED|RUNNING|QUIESCING|DRAINING}`.  Update/query handles admit only `QUEUED`/`RUNNING`; shutdown admits only `QUIESCING`/`DRAINING`. |
| `WaitObservation`. | `OBSERVED {value:Observation}` or `TIMED_OUT_PENDING {operation_identity:OperationID}`.  Timeout is not a terminal state. |
| `WorldAcquisition`. | `ACQUIRED {world:Handle(WORLD)}` or `PENDING {operation_identity:OperationID}` or `UNAVAILABLE {reason:WorldUnavailable}`.  No arm creates a waiter. |
| `WorldUnavailable`. | `NO_HEAD`, `FRONTIER_MISMATCH {expected:ProviderFrontier, published:ProviderFrontier}`, or `UPDATE_TERMINAL {observation:UpdateObservation}` with a non-`PUBLISHED` outcome. |
| `QueryStart`. | `AVAILABLE {result:Handle(RESULT)}` or `PENDING {waiter:Handle(WAITER)}` or `TERMINAL {observation:QueryObservation}` whose outcome is not `AVAILABLE`. |
| `ResultAcquisition`. | `ACQUIRED {result:Handle(RESULT)}` or `PENDING {operation_identity:OperationID}` or `TERMINAL {observation:QueryObservation}` whose outcome is not `AVAILABLE`.  An update waiter is `INVALID_HANDLE` for this operation. |
| `CancelOutcome`. | `CANCELLED` or `ALREADY_TERMINAL {observation:Observation}` with a terminal arm. |
| `CompletionBatch`. | `{records:[]CompletionRecord}` with length at most `maximum`; `maximum == 0` returns an empty array without draining.  An empty array does not assert session shutdown or absence of future completions. |
| `Retained`. | `WORLD {handle:Handle(WORLD)}` or `RESULT {handle:Handle(RESULT)}`, matching the input kind. |
| `Released`. | `Unit`. |
| `ShutdownRequested`. | `{shutdown:Handle(SHUTDOWN)}`. |

`OperationError` is `{code, detail:ErrorDetail}` with exactly the eight codes from the operation table.
Its detail arm must match the code: `INVALID_VERSION {supplied:bytes, supported:[]bytes}`, `INVALID_ARGUMENT {path:FieldPath, rule:ArgumentRule}`, `INVALID_HANDLE {kind:HandleKind}`, `BASE_MISMATCH {scope:FRONTIER|DOCUMENT|SOURCE|OVERLAY, document:Optional(DocumentID)}`, `UNSUPPORTED_EVENT {event_tag:bytes}`, `ADMISSION_DENIED {reason:AdmissionReason}`, `ACTIVE_SESSION`, or `SERVICE_CLOSED`.
Expected/current source states are obtained through `DescribeSession`, not an unbounded error dump.
`ArgumentRule` is `MISSING. | UNKNOWN_FIELD. | UNKNOWN_TAG. | DUPLICATE. | WRONG_KIND. | OUT_OF_RANGE. | INVALID_ENCODING. | INCONSISTENT_BINDING. | INVALID_CONFIRMATION`.
Field paths use the registry's `FIELD {name_ascii}`/`ELEMENT {index:u64}` segments, rooted at the operation input.
An unrecognised incoming tag can be quoted as bounded raw bytes; it does not extend a closed response union.

- `AdmissionReason` is `LIMIT {name:LimitName}` or `CONFIGURATION_REQUIRED {field:FieldPath}` or `CAPABILITY {schema:bytes}` or `SOURCE_ACQUISITION {failure:Failure}` or `RESOURCE_EXHAUSTED`.
- `Failure` is `{stage:ADMISSION|PROVIDER|PARSER|CONVERSION|PUBLICATION|SERVICE, code:IO|PERMISSION|REVISION_UNAVAILABLE|INVALID_EVIDENCE|INVALID_REFERENCE|INVALID_TEXT|RESOURCE_LIMIT|INTERNAL, diagnostic:Optional(ServiceDiagnostic)}`.
- `ServiceDiagnostic` is `{severity:WARNING|ERROR, message_utf8:bytes}` with strict UTF-8; it is not a language diagnostic and has no inferred source span.
- `UnavailableReason` is `NOT_CAPTURED. | SOURCE_ABSENT. | SOURCE_UNKNOWN. | REVISION_UNAVAILABLE. | PROVIDER_UNAVAILABLE`.
- `UnsupportedReason` is `{capability:SEMANTIC_QUERY|COMPILER_EVALUATION|QUERY_SCHEMA|CONTEXT_PROFILE|CONSISTENCY, schema:Optional(bytes)}`.
- `CancellationReason` is `CALLER | WORLD_SUPERSEDED | SHUTDOWN | PRESSURE`; cancellation never relabels a failed conversion as successful partial output.
- `CALLER` identifies waiter-local UI/client stop; `WORLD_SUPERSEDED` identifies cancellation of unfinished work against an obsolete source frontier and is delivered to every still-pending query waiter sharing it.
Cancellation observations preserve the original selected-world identity; clients can inspect the accepted frontier and explicitly acquire/request current analysis before reissuing, but no successor world or retry is selected automatically.

`Deadline` is `AT {clock_identity:bytes, nanoseconds:u64}` in the monotonic clock advertised by the owning service in `Capabilities.clock_identity`.
A foreign clock is `INVALID_ARGUMENT`.
It is neither wall time nor a persisted timestamp; wrap/overflow rejects, and no infinite-wait sentinel is reserved.
`Wait` first makes the same atomic observation as `Poll`; a terminal outcome already visible is returned even for an expired deadline.
Otherwise, expiry returns `TIMED_OUT_PENDING` without changing work/registration state.
Host dispatch-thread suitability and actual wait primitives remain milestone 5, not a promise that blocking a host thread is safe.

The following read-only accessor family is part of payload interpretation, not additional source/scheduling operations.
It performs no provider read, parsing, registration, waiting or implicit retain:

```text
ReadWorld(world: Handle(WORLD)) -> Call(Borrowed(WorldDescription))
ReadResult(result: Handle(RESULT)) -> Call(Borrowed(ResultDescription))
ReadSource(result: Handle(RESULT), start_byte: u64, end_byte: u64) -> Call(Borrowed(bytes))
ResolveNode(result: Handle(RESULT), node_id: u64) -> Call(Borrowed(NodeRecord))
ResolveToken(result: Handle(RESULT), token_id: u64) -> Call(Borrowed(TokenRecord))
ResolveRecovery(result: Handle(RESULT), recovery_id: u64) -> Call(Borrowed(RecoveryRecord))
```

`Borrowed(T)` is an immutable view tied to that exact live `WORLD`/`RESULT` registration.
All nested arrays/bytes inherit that lifetime.
The caller must keep the owning registration alive for the whole use, including across threads; retain a separate handle before concurrent release can race a view's use.
The accessor validates the live registration and kind/domain/range before returning; it cannot make a borrowed view safe after its owner is released.
`ReadResult.payload` contains the registered envelope and its protected syntax backing; diagnostic/index results support the same resolvers without acquiring a separate snapshot result.
IDs resolve only in the passed result's backing, never in a later world.
Out-of-range slices/IDs return `INVALID_ARGUMENT`; unknown/wrong-kind/released handles return `INVALID_HANDLE`.
`ReadSource` accepts zero-width slices through exact-source length.
No public deep-copy API or mutable field accessor is implied; a host copy must include/translate all referenced backing as already required.

### Milestone 3: Provider Admission and Bounded Values

The provider schema identifier is ASCII `jai-cache-source-provider/1`.
`SessionOptions.provider_capabilities` is the following exact `ProviderAdapterDescriptor`, not a free-form capability map.
Its fields are `{adapter_schema, authority_identity:bytes, document_policy_version:u32, path_platform, case_alias_link_policy, reappearance_policy, consistency_capabilities, lease_capabilities}` in that order.
`adapter_schema` must equal this identifier; authority bytes must be nonempty and bind to the actual host/provider registration, not a claim trusted from persistence.

| Descriptor field. | Closed alternatives and admission rule. |
| --- | --- |
| `path_platform`. | `WINDOWS_UTF16LE`. | `POSIX_BYTES`, matching the admitted provider's native path validator and every canonical document binding.  Cross-platform capability is not inferred from decoding a path. |
| `case_alias_link_policy`. | `DISTINCT_KEYS` or `HOST_VALIDATED_ALIASES {policy_identity:bytes}`.  `DISTINCT_KEYS` performs no service-side case folding, link resolution or alias merging; keys are host-issued, not inferred from path strings.  The second arm requires a registered version-bound host validator and evidence before two requests share a key.  It is unsupported if that validator is absent. |
| `reappearance_policy`. | `SAME_KEY`. | `FRESH_KEY`, chosen explicitly by the provider.  `SAME_KEY` retains the registered document identity across confirmed absence/reappearance; `FRESH_KEY` requires a new document key and leaves historical identity untouched. |
| `consistency_capabilities`. | Nonempty canonical set of `IMMUTABLE_CAPTURE`. | `COHERENT_CAPTURE`, in this order.  `IMMUTABLE_CAPTURE` guarantees each retained observation, not a common filesystem instant.  `COHERENT_CAPTURE` additionally requires one provider-attested capture token for the whole participating set.  There is no `BEST_EFFORT` arm permitting mutable bytes under an accepted revision. |
| `lease_capabilities`. | `COPY_ONLY` or `IMMUTABLE_RETAIN_RELEASE {lease_schema:bytes}`.  `COPY_ONLY` admits `INLINE_BYTES` only.  The second requires the registered provider's retain/read/release contract below; arbitrary pointers or an unregistered lease schema reject. |

`DocumentBinding` is `{document:DocumentID, absolute_path:PathValue, provider_policy_version:u32}`.
It must match the document's provider namespace/key and the session's policy.
Refine `DocumentEvent` to `{document, expected_provider_state, source_context, binding:Optional(DocumentBinding), event}`: first admission requires `SOME`; a tracked document accepts `NONE` or an exactly equal repeated binding.
A changed binding under the same key rejects the complete batch.
This is a provider attestation plus registered policy validation, not independent physical-file discovery by the service.

`ContextRegistration` is `{identity:ContextID, descriptor:bytes}` where descriptor bytes are exactly the previously specified canonical syntax-context `K` descriptor.
The service parses, validates and recomputes that identity against the actual registered producer/profile tuple before accepting it.
`SessionOptions.context` is `{supported_tuples:[]SchemaTuple, contexts:[]ContextRegistration}`.
Refine `SourceBatch` to `{version, workspace, session, expected_frontier, contexts:[]ContextRegistration, events:[]DocumentEvent, milestone}`.
Empty contexts are permitted; a context used by the batch must already be owned by the session or appear once in this array.
Reject duplicate identities, conflicting descriptors and unreferenced registrations; all new contexts commit atomically with source selection and are discarded on rejection.
This is not a mutable parser-configuration operation.
Later profile/adapter choices must already belong to the session's admitted tuple set; otherwise open another explicitly configured session.
Occurrence-specific paths may be registered by later batches without reopening the session.

`SchemaTuple` is `{token_tags, source_tokens, nodes, recovery, declaration_index, diagnostics, snapshot, authored_edges, syntax_adapter, parse_profile, diagnostic_profile}`, each an exact registered ASCII identifier.
Required initial schema values are respectively `jai-cache-token-tags/1`, `jai-cache-source-tokens/1`, `jai-cache-authored-nodes/1`, `jai-cache-recovery/1`, `jai-cache-syntax-declaration-index/2`, `jai-cache-syntax-diagnostics/1`, `jai-cache-syntax-snapshot/1`, `jai-cache-authored-edges/1`, and `jai-cache-syntax-adapter/1`; profile identifiers resolve to the explicitly registered producer policies already required by the context.
The context's four syntax-schema fields refer to `source_tokens`, `nodes`, `recovery` and `declaration_index`; `source_tokens` binds `token_tags`, and its `snapshot` mapping binds the remaining tuple.
The diagnostic context field binds `diagnostics` and `diagnostic_profile` independently.
No version-number coincidence establishes compatibility.
Admission accepts only a whole implemented tuple; the registry must expose which of the three `QueryKind` payload implementations it actually supplies.
Advertising all three remains a requirement for the syntax-first qualification slice, not a claim that an adapter exists today.

`Consistency` is `IMMUTABLE_CAPTURE` or `COHERENT_CAPTURE {provider_namespace:bytes, capture_token:bytes}`; `capture_token` is nonempty and provider-attested.
`ObservationProvenance` is `{provider_identity:bytes, observation_token:bytes, consistency:Consistency}`.
Refine `DiskObservation`'s `PRESENT` arm to `{source, source_revision, context, observation_provenance:ObservationProvenance}` and its `ABSENT` arm to `{provider_revision, context, observation_provenance:ObservationProvenance}`.
The provenance is required in both arms; selected consistency comes from that value, not a timestamp.
Permission/I/O/revision acquisition failure is never an `ABSENT` observation.
A world uses `COHERENT_CAPTURE` only if every participating observation has the same validated token covering that exact set; otherwise its truthful guarantee is `IMMUTABLE_CAPTURE`.
The baseline requests no stronger guarantee than immutable capture.
A host needing coherent capture must supply/validate it, not upgrade a mixed capture after analysis.

`ProviderLeaseRef` is `{lease_schema:bytes, lease_token:bytes}`; source input's `immutable_lease` has exactly this type.
The registered provider exposes synchronous `RetainSource(ref) -> RETAINED {byte_count:u64} | FAILED {failure:Failure}`, `ReadSourceLease(ref) -> immutable byte view`, and `ReleaseSource(ref) -> Unit`.
These are host-adapter hooks, not public service operations.
Retain must independently protect the exact bytes/revision before acknowledgement; reading a retained lease cannot reopen the current path, silently change bytes, or require a dispatch callback to complete.
The service validates all byte counts and source revision claims while protected.
If the provider cannot meet that contract it must submit an owned inline copy instead.
Each successful retain has exactly one release after its last service owner, including rejected staged batches.
A lease token copied from storage establishes no live provider ownership.
Adapter acquisition failure rejects the batch atomically; later loss of an allegedly immutable retained source is a provider failure, never permission to substitute new bytes.

`HostConfirmation` is `{host_authority:bytes, confirmation_token:bytes, document:DocumentID, expected_provider_state:ExpectedProviderState, action:RESET|RESTORE, source_revision:Optional(SourceRevision), recovery_candidate:Optional(RecoveryCandidateRef)}`.
It is accepted only from the registered authoritative host channel and must match the enclosing event/base.
- `RESET` has `NONE` for both optional fields and selects its supplied disk observation.
- `RESTORE` has `SOME` for both and must match the restored bytes/candidate exactly; `UNTRACKED` is permitted only under the first-admission rules.
Tokens are nonempty, action-bound attestations, not user-interface prompts issued by the cache or proof inferred from a recovery file.

`RecoveryCandidateRef` is `{store_namespace:bytes, candidate_key:bytes, source_revision:SourceRevision}` issued by the supported store reader; candidate-key bytes are opaque to this API and interpreted only by the milestone-6 store schema.
No path or live handle is reconstructed from them.
- `ACK_SAVE.expected_overlay_revision` is the `ProviderRevision` of the event that installed that overlay, not its content `SourceRevision` or the latest combined disk/overlay state.
- `SET_OVERLAY`, `EDIT_OVERLAY` and `RESTORE_OVERLAY` assign their `resulting_provider_revision` as the new overlay installation stamp, even for unchanged bytes; `OBSERVE_DISK` preserves the existing overlay stamp.
- `written_source_revision` must equal the supplied present disk bytes, but need not equal a newer active overlay.
Clear the overlay only when its installation stamp equals `expected_overlay_revision` and its `SourceRevision` equals `written_source_revision`; otherwise preserve it, or reject inconsistent claims about that matching stamp.
- `EDIT_OVERLAY` requires at least one edit.
Every event's `resulting_provider_revision` is checked against its provider/session/document authority; every accepted event, including a byte-identical save observation, gets a nonreassigned combined-state token.
The frontier advances once per accepted batch, never once per event or context registration.

`SelectedDocument` is `{document:DocumentID, provider_revision:Optional(ProviderRevision), context:ContextID, state}` with state `PRESENT {source_revision:SourceRevision, selection:OVERLAY|DISK|RESTORED_OVERLAY, overlay_revision:Optional(ProviderRevision), provenance:Optional(ObservationProvenance)}` or `ABSENT {provenance:ObservationProvenance}` or `UNKNOWN` or `UNAVAILABLE {reason:UnavailableReason}`.
Tracked provider states require `SOME` `provider_revision`; an explicitly unobserved captured member may have `NONE`.
Present `DISK` and `ABSENT` require validated provenance; host overlays may have `NONE`, which cannot support a coherent disk-capture claim.

`WorldDescription.membership_completeness` is exactly `FINITE_EXPLICIT_CAPTURE`; it makes no import/search-closure promise.
Its top-level configuration is `ConfigurationID = K("syntax-configuration", [V(Sequence(SchemaTuple), canonical_supported_tuple_set)])`, not a filename-bearing document `ContextID`; per-member context remains the sole occurrence authority and binds the actual verified producer/adapter build.
Rename, implicit resolver discovery and semantic membership remain `UNSUPPORTED` in this schema; no placeholder resolver callback is admitted.

`Capabilities` is `{interface_version:InterfaceVersion, provider:ProviderAdapterDescriptor, tuples:[]SchemaTuple, syntax_adapters:[]bytes, queries:[]QueryKind, clock_identity:bytes}`.
Adapter bytes are exact canonical syntax-adapter descriptors, not host claims.
Tuple/adapter lists are duplicate-free canonical sets sorted by their complete canonical bytes; queries appear in registry order and list implemented kinds only.

`SessionDescription.tracked_document_states` is `[]TrackedDocument` in canonical `DocumentID` order.

`TrackedDocument` is `{document:DocumentID, provider_revision:ProviderRevision, binding:DocumentBinding, disk:DiskState, overlay:Optional(OverlayState), selected:SelectedDocument}`.

`DiskState` is `UNKNOWN` or `PRESENT {source_revision:SourceRevision, context:ContextID, provenance:ObservationProvenance}` or `ABSENT {context:ContextID, provenance:ObservationProvenance}` or `UNAVAILABLE {reason:UnavailableReason}`.

`OverlayState` is `{installation_revision:ProviderRevision, source_revision:SourceRevision, context:ContextID, origin:ACTIVE|RESTORED}`.
Selected overlay states require `SOME` `overlay_revision` equal to `installation_revision`, while selected disk states require `NONE`.
The event's `source_context` must equal the resulting selected state's context; an acknowledged older disk context may differ while a newer overlay remains selected.

`DescribeSession` reports both branches without source-byte copies or live provider leases, so an overlay does not hide the acknowledged disk revision.
Its lifecycle is `OPEN. | QUIESCING. | DRAINING. | STOPPED`.

`StoreStatus` is `{mode:ENABLED|DISABLED|DEGRADED, acknowledged_frontier:Optional(ProviderFrontier), diagnostics:[]ServiceDiagnostic}`; an acknowledged frontier reports confirmed durable progress only, never source admission alone.

`SessionOptions.store_policy` is `{policy_schema:bytes, policy_key:bytes}` identifying explicit host configuration resolved by the registered store-policy implementation.
Missing required policy returns `ADMISSION_DENIED`/`CONFIGURATION_REQUIRED`; unknown policy schemas return `ADMISSION_DENIED`/`CAPABILITY`.
This API cannot interpret an opaque key as a path or choose persistence defaults.
Required source/recovery persistence (R2) and the exact store configuration/grammar (milestone 6) are unchanged.

#### Required Limit Negotiation

`effective_limits` is `Limits`: a record with exactly the following nineteen named positive `u64` fields in table order.

`requested_limits` is `LimitRequest`, with those same nineteen names/order, each `s64`; omitted fields or an omitted request mean all corresponding fields are `-1`, with no configured quota.
Set values must be positive and at most `0x7FFFFFFFFFFFFFFF` and the relevant native representation ceiling; zero, values below `-1` and unknown/malformed fields reject before input acquisition.
For a positive configured field report `effective = min(requested, implementation_ceiling)` after checked conversion to the unsigned bound; for `-1` report the implementation ceiling, rejecting only if the supported safe minimum cannot fit.
Implementation ceilings express documented representation/algorithm bounds, not arbitrary hidden RAM budgets; no quota is reserved or guaranteed by reporting them.
Default memory use may grow into available RAM; actual allocator/OS failure still returns the defined resource outcome without leaking ownership or corrupting admitted state.
There is no infinite numeric sentinel or wraparound; optional quotas do not weaken checked decoding, bounded native recursion, aggregate accounting or shutdown reservations.
The name column is the closed `LimitName` registry.

| `LimitName`. | Quantity checked before allocation/admission/publication. |
| --- | --- |
| `value_bytes`. | Bytes in any individual opaque/name/decoded/presentation byte value. |
| `source_bytes`. | Exact bytes per source, including every intermediate sequential-edit result. |
| `path_bytes`. | Encoded code-unit bytes per `PathValue`, also subject to `value_bytes`. |
| `key_bytes`. | Bytes in any complete identity/context/canonical descriptor key. |
| `message_bytes`. | Strict UTF-8 bytes per language/service message, also subject to `value_bytes`. |
| `request_bytes`. | Total logical input bytes/count framing per call, including inline replacements/descriptors; retained source bytes are separately checked rather than hidden in a small lease reference. |
| `batch_events`. | Events per source batch. |
| `edits_per_event`. | Sequential edits in one `EDIT_OVERLAY`. |
| `capture_documents`. | Tracked documents per session and members per captured world/request. |
| `records_per_payload`. | Total node/helper/token/recovery/diagnostic/index/coverage records in one protected payload and its required backing, counted once per local record, not merely top-level array length. |
| `elements_per_list`. | Elements of every individual array, including nested arrays, contexts, paths and diagnostic related records. |
| `nesting_depth`. | Value/helper/field-path nesting and authored owning-edge traversal depth; use checked iterative traversal if native recursion cannot meet this ceiling. |
| `live_handles`. | All owned session and child registrations, including independent retains. |
| `pending_registrations`. | Live pending waiter registrations. |
| `completion_records`. | Reserved/queued terminal completion records, including undrained delivery. |
| `retained_source_bytes`. | Aggregate protected exact-source backing attributed to this session, including historical sources/overlays; shared backing is charged once per session that protects it. |
| `owned_bytes`. | Aggregate service-owned backing attributed to this session, including source, decoded bytes, records, handles, queue entries and temporary/staged allocations. |
| `concurrent_acquisitions`. | Active provider acquisitions/retains staged for this session. |
| `in_flight_operations`. | Nonterminal accepted operations, including work whose external ticket/waiter was released, plus their still-draining producer/cleanup reservations and the reserved shutdown operation.  Public cancellation/terminal publication does not free a slot still needed by its producer. |

The service checks count multiplication, length-prefix additions, sequential edit subtraction/addition, reference ranges and aggregate accounting before committing/allocating.
Two individually valid values can still exceed request/aggregate limits.
Validate cheap structural/version/base checks before provider acquisition, reserve the complete admission bookkeeping and stage ownership, then revalidate the authoritative base before one commit.
Reserve completion capacity before creating a pending waiter; a later full queue cannot drop its only terminal record.
Shutdown/cleanup must remain possible at the handle/resource ceiling through the milestone-5 reservation protocol, including its charged first shutdown slot/operation/reaper and fixed cleanup capacity; this is not an exception that permits unbounded allocation.
Failure before commit is `ADMISSION_DENIED`/`LIMIT` or `RESOURCE_EXHAUSTED` and changes no source/frontier.
A post-admission limit failure is `FAILED` with `RESOURCE_LIMIT`, never a successfully truncated snapshot/diagnostic payload or a partial index missing records solely because of pressure.
A bounded emergency failure record must not depend on allocating an unbounded diagnostic string.

Limits apply to descriptions, completion copies and borrowed-view validation as well as source submission.
Drain maximum greater than `elements_per_list` is `INVALID_ARGUMENT`, not an implicit clamp.
Retained immutable leases are not evicted or rewritten to meet a lowered pressure target; reject/defer new acquisition with its explicit outcome.
This schema has no limit-changing operation.
Optional host quotas, effective technical ceilings and resource failures must be documented/enforced in both modes; no fixed production RAM/disk budget is selected.
Cross-workspace sharing/history details remain for review; the default all-available policy does not approve those separate choices.

### Milestone 3: Canonical Values and Snapshot Records

`InterfaceVersion` is exactly ASCII `jai-cache-interface/1`.
Version is explicit on outer session/request/batch/query records and inherited by nested records; it is not duplicated into every span/array element.
Unknown versions, fields, tags and trailing data reject the selected schema.
There is no implicit latest version, optional-field elision, lossy converter or open extension map.
A change to field order/type, enum registry, active guard, ownership or meaning requires a new schema identifier and an explicitly reviewed compatibility mapping.
Previously retained results keep their admitted schema/access contract.
This specifies logical values and canonical descriptor/fingerprint bytes, not a network transport, native layout or the milestone-6 text-file format.

For canonical values not already assigned a specific K recipe, define `V(schema, value)` by the following grammar.
K and B retain their exact earlier definitions; these rules do not rewrite existing source/path/context key recipes.
A schema identifier resolves to its complete ordered field/variant/type registry before decoding; hashing an unknown identifier does not register it.

| Value type. | Canonical bytes. |
| --- | --- |
| `bytes`. | `K("bytes", [exact_bytes])`; empty bytes are valid unless the owning field forbids them. |
| ASCII tag/schema. | `K("ascii", [exact_ASCII_bytes])`; nonempty, bytes 0x21 through 0x7E only, case-sensitive.  The owning registry further restricts the spelling. |
| `bool`. | `K("bool", [one_byte])`, exactly 0 or 1. |
| `u8`, `u16`, `u32`, `u64`. | `K(type_name, [fixed_width_little_endian_bytes])`; no decimal text, variable-width integers or narrowing. |
| `s32`, `s64`. | `K(type_name, [fixed_width_twos_complement_little_endian_bytes])`; reject a value outside that signed width. |
| IEEE-754 binary64 observation. | `K("float64-bits", [eight_little_endian_object_bytes])`; preserve negative zero, NaN payload and every producer bit. |
| Registered enum. | `K("enum", [schema_identifier, exact_tag_ASCII])`; enum ordinals are never encoded. |
| Record. | `K("record", [schema_identifier, V(field_0), ..., V(field_n)])` in its declared field order, with every field present exactly once.  Empty `Unit` is the zero-field record. |
| Tagged union/`Optional`. | `K("variant", [schema_identifier, exact_arm_ASCII, V(active_field_0), ...])`; only active arm fields occur.  `NONE` and `SOME`(empty bytes) differ. |
| Sequence. | `K("sequence", [element_schema_identifier, V(element_0), ...])`; the `K` field count determines element count after the first schema field.  Preserve order; canonical sets use only the explicitly specified byte-sort/duplicate rules. |
| Typed identity. | The complete earlier K identity bytes, validated against its expected identity domain/authority; not its digest or a presentation label. |
| Live handle. | `K("handle", [complete_SessionID_key, ASCII(kind), slot_u64_bytes, generation_u64_bytes])` for canonical live-call comparison only; not a persistent/restart handle format or permission to send handles across processes. |

Schema identifiers for nested logical records are `jai-cache-interface/1/` followed by the exact case-sensitive type name used in this document, unless a separately named payload/context/provider schema is specified.
A parameterised schema identifier is `K("parameterised-type", [base_schema_ASCII, parameter_schema_identifier_0, ...])`, not ambiguous concatenated version strings or a claim that those framed bytes are ASCII.
A bounded decoder rejects an incorrect field count, duplicate/reordered field, malformed tag, overflow, invalid UTF-8 presentation text or extra trailing bytes before exposing a value.
Opaque source/name/path bytes do not acquire a UTF-8 requirement.
Canonical set order compares complete canonical bytes, shorter prefix first.
In-memory implementations may avoid materialising V/K buffers but must compare/hash exactly these logical bytes and retain the equality authority; a matching SHA-256 alone never proves equivalence.

#### Node and Helper Projection

`jai-cache-syntax-snapshot/1` `data` is `{source:bytes, root:s64, nodes:[]NodeRecord, helpers:[]HelperRecord, tokens:[]TokenRecord, synthetic_tokens:[]SyntheticTokenRecord, recoveries:[]RecoveryRecord, diagnostics:[]RawDiagnostic, parse_status:ParseStatus}`.
Source is exactly the envelope's revision bytes.
Its node schema is `jai-cache-authored-nodes/1`, source token schema is `jai-cache-source-tokens/1`, recovery schema is `jai-cache-recovery/1`, and all four bind to the admitted `SchemaTuple`.
The initial whole-document service uses the registered `FILE` root; the six parser entrypoints audited in milestone 2 are not six implicit `QueryRequest` root selectors.
A root of `-1` records a safely retained failed parse, never a fabricated empty file node; a nonnegative root is a checked local node ID, and values below `-1` reject.
Materialised token IDs follow lexer order including EOF; node IDs follow first registered owning-edge encounter; helper IDs follow first active helper-field encounter.
Each domain is dense zero-based `u64` and independent of every other domain.
Inline/by-value helpers have distinct helper occurrences, not extra node identities.

`NodeRecord` is `MAPPED {local_node_id:u64, kind:bytes, coordinates:Coordinates, token_span:TokenSpan, origin:Optional(Origin), fields:[]FieldObservation}` or `OPAQUE {local_node_id:u64, producer_kind:u64, coordinates:Coordinates, token_span:TokenSpan, origin:Optional(Origin)}`.
`Coordinates` is `{l0:s32,c0:s32,l1:s32,c1:s32}`; `TokenSpan` is `{first:s64,one_past_last:s64}` retaining signed producer observations.
Neither record authorises dereferencing invalid token indices.
Only qualified origin mapping produces `SOME`.
`MAPPED` kind is exactly a named published kind in the milestone-2 50-layout registry plus base `DIRECTIVE_THIS`; compiler-only kinds are not additional supported syntax variants.
`OPAQUE` is permitted only in the safe backing of a partial derived result, with its required coverage reason and no unqualified child/scalar reads.
An exact `SYNTAX_SNAPSHOT` contains no `OPAQUE` records; encountering an unrepresentable active kind/field fails that conversion, not a falsely exact snapshot.

`HelperRecord` is `{local_helper_id:u64, layout:bytes, fields:[]FieldObservation}`.
Its layout is one of the active non-node helper layouts in the milestone-2 auxiliary/shared-record inventory; assembly helpers retain their full `Parser_Asm_`* layout names.
Structural base/entry/compiler-overlay embeddings flatten into the same node's qualified field paths and do not allocate helper IDs.
Pointer-literal null has the dedicated `SOURCE_NULL` scalar arm below, not a serialised compiler pointer helper.
Lexical scopes, allocation pools and the excluded semantic/generated/compiler-export fields do not appear.

`FieldObservation` is `{path:[]PathStep, value:FieldValue}`.
Paths are nonempty qualified field paths from that node/helper's registered layout, not display labels or raw byte offsets; `INDEX` is not a second list-step spelling.
`FieldPath` in operation errors is an alias for `[]PathStep`, using the same `FIELD`/`ELEMENT` arms already specified for [coverage reasons](CACHE_SYNTAX_REGISTRY.md#structured-coverage-reasons-and-consumer-guarantees).
Field observations are unique and sorted by complete canonical path bytes; this representation order does not replace the separately registered authored child traversal order.
Base kind/location/token-span observations already in the node header are not duplicated as fields.
M2's per-layout/shared/helper field tables define the exact required paths, active guards, owning edges, aliases, scalar domains and excluded fields; the field projection is normative reuse of that registry, not a fresh walk over every public compiler field.
Changing those tables changes this schema and must revise its binding.

`FieldValue` is exactly `INACTIVE`, `BOOL {value:bool}`, `SIGNED {value:s64}`, `UNSIGNED {value:u64}`, `FLOAT64_BITS {bits:u64}`, `BYTES {value:bytes}`, `TOKEN_TAG {value:TokenTag}`, `ENUM {domain:bytes, name_ascii:bytes}`, `FLAGS {domain:bytes, names:[]bytes}`, `NODE {local_node_id:s64, relationship:OWNED|ALIAS}`, `HELPER {local_helper_id:s64}`, `LIST {elements:[]FieldValue}`, `TOKEN_SPAN {value:TokenSpan}`, or `SOURCE_NULL`.
Guard-inactive fields use `INACTIVE` without reading their backing memory; a missing active pointer is `NODE` with `local_node_id == -1` or `HELPER` with `local_helper_id == -1`, not `INACTIVE`.
Set node/helper references are nonnegative, range-checked IDs in the correct protected backing; values below `-1` reject before lookup.  Producers must reject unrepresentable references rather than wrapping/truncating an unsigned ID into `s64`.
These signed not-set fields use the canonical signed scalar encoding, including `-1`, not an optional-value wrapper; other optional record/identity types retain their existing encodings.
A recovered required-child hole retains its actual absence/recovery observations.
Safe source strings are `BYTES`; narrow native integers extend without losing sign/bits and must fit their registered field range when validated.
Numeric literal union selection follows the existing literal-route rules, using `UNSIGNED` for the accumulator and `FLOAT64_BITS` for the float arm; scalar byte strings, `BOOLEAN` and `SOURCE_NULL` remain distinct.
Never read multiple overlapping arms.
`ENUM` domain is the exact qualified producer enum type at that field; `name_ascii` is its declared canonical name, including a declared zero/default where observed, under the bound compiler SDK identity.
The registry excludes native aliases unless explicitly normalised; operator fields instead use `TokenTag`.
Unknown integer enum values reject conversion, not a guessed name.
Flags use the following closed source-only domains, never generic enum ordinal/mask serialisation.

| Flag domain/owning field. | Canonical source flag names. |
| --- | --- |
| `NODE`/common `node_flags`. | `EXPRESSION_IS_SPREAD`, `NO_ARRAY_BOUNDS_CHECK`, `ALLOWED_BY_CONTEXT`, `STATEMENT_IS_DEFERRED`, `IS_PARENTHESIZED`. |
| `CALL`/`Code_Procedure_Call.flags`. | `INLINE_YES`, `INLINE_NO`, `RETURNS_PROCEDURE_POINTER_ONLY`, `NO_DEBUG`, `IS_MODULE_PARAMETERS`. |
| `RETURN`/`Code_Return.return_flags`. | `IS_BACKTICKED`, `AUTO_INSERTED_FOR_QUICK_LAMBDA`. |
| `FOR`/`Code_For.for_flags`. | `REVERSE`, `POINTER`. |
| `DECLARATION`/`Code_Declaration.flags`. | `IS_CONSTANT`, `IS_MARKED_AS_AS`, `IS_MARKED_AS_DISCARD`, `NO_RESET`, `IS_UNINITIALIZED`, `AUTO_VALUE_BAKE`, `AUTO_VALUE_BAKE_IS_REQUIRED`, `PROGRAM_EXPORT`, `ELSEWHERE`, `HAS_SCOPE_MODIFIER`. |
| `BLOCK`/`Code_Block.block_flags`. | `NO_ARRAY_BOUNDS_CHECK`, `NO_ARITHMETIC_OVERFLOW_CHECK`. |
| `IDENT`/`Code_Ident.flags`. | `DEFINES_POLYMORPH_VARIABLE`, `IS_RHS_OF_DOT_DEREFERENCE`, `HAS_SCOPE_MODIFIER`. |
| `TYPE_INSTANTIATION`/`Code_Type_Instantiation.inst_flags`. | `VARARGS`, `RESIZABLE`, `TYPE_OF_PROCEDURE`, `TYPE_DIRECTIVE`, `TYPE_DIRECTIVE_DISTINCT`, `TYPE_DIRECTIVE_ISA`, `ARRAY_VIEW`, `INTERFACE`. |
| `LITERAL`/`Code_Literal.value_flags`. | `IS_A_NUMBER`, `HEX`, `FLOAT`, `BINARY`, `MINUS_SIGN`, `HERE_STRING`, `DEFAULTS_TO_FLOAT64`, `REQUIRES_FLOAT64`, `SIGNIFICANT_DIGITS`. |
| `PROCEDURE`/`Code_Procedure_Header.procedure_flags`. | `ELSEWHERE`, `COMPILE_TIME_ONLY`, `POLYMORPHIC`, `DEBUG_DUMP`, `C_CALL`, `TYPE_ONLY`, `INTRINSIC`, `DEPRECATED`, `SYNTACTICALLY_MARKED_AS_NO_CONTEXT`, `QUICK`, `QUICK_IN_BLOCK_FORM`, `NO_CALL`, `MACRO`, `NO_DEBUG`, `ENTRY_POINT`, `SYMMETRIC`, `ENTRY_POINT_HOOK`, `SYNTACTICALLY_MARKED_AS_COMPILE_TIME`, `SYNTACTICALLY_MARKED_AS_COMPILER`, `SYNTACTICALLY_MARKED_AS_INLINE_YES`, `SYNTACTICALLY_MARKED_AS_INLINE_NO`. |
| `BODY`/`Code_Procedure_Body.body_flags`. | Empty source flag set; `ALREADY_MODIFIED` is excluded processed state. |
| `CAST`/`Code_Cast.cast_flags`. | `IS_AUTO`, `NO_BOUNDS_CHECK`, `TRUNCATE`, `FORCE`, `VERY_FORCE`, `HAS_FUNCTION_SYNTAX`, `HAS_POSTFIX_SYNTAX`. |
| `IF`/`Code_If.if_flags`. | `IS_SWITCH_STATEMENT`, `IS_IFX`, `IS_STATIC`, `MARKED_AS_COMPLETE`; `static_if_flags` is excluded evaluated state. |
| `BINARY`/`Code_Binary_Operator.flags`. | `SHIFT_MARKED_AS_LOGICAL`, `SHIFT_MARKED_AS_SMALL`. |
| `RUN`/`Code_Directive_Run.flags`. | `ASSERTION`, `STALLABLE`, `SYNTACTICALLY_IMPLICIT`, `HAS_IMPLICIT_RETURN_TYPES`, `HOST`. |
| `IMPORT`/`Code_Directive_Import.flags`. | `UNSHARED`, `SOURCE_PATH`. |
| `CODE`/`Code_Directive_Code.code_flags`. | `NULL`, `TYPED`, `CALLER_CODE`; `IMPLICITLY_GENERATED` is excluded generated state. |
| `LIBRARY`/`Code_Directive_Library.library_flags`. | `IS_SYSTEM_LIBRARY`, `DYNAMIC_LIBRARY_UNAVAILABLE`, `STATIC_LIBRARY_UNAVAILABLE`, `LINK_ALWAYS`. |
| `PUSH_CONTEXT`/`Code_Push_Context.push_context_flags`. | `IS_BACKTICKED`, `DEFER_POP`. |
| `ARRAY_LITERAL`/`Code_Array_Literal_Info.array_literal_flags`. | `WAS_UNTYPED`. |
| `STRUCT`/`Code_Struct.textual_flags`. | `UNION`, `FOREIGN`, `NO_PADDING`, `TYPE_INFO_NONE`, `TYPE_INFO_NO_SIZE_COMPLAINT`, `TYPE_INFO_PROCEDURES_ARE_VOID_POINTERS`. |
| `NOTE`/`Code_Note.note_flags`. | Empty admitted source flag set; a nonzero unqualified observation fails conversion, not a fabricated lexer `Value_Flags` interpretation. |

Names are sorted by unsigned ASCII bytes with no duplicates; an empty set is explicitly empty, not missing.
Native named bits map by those exact names under the verified SDK; four compatibility names map explicitly to parser constants: `LITERAL`/`SIGNIFICANT_DIGITS` = `0x400`, `CODE`/`CALLER_CODE` = `0x4`, `IMPORT`/`SOURCE_PATH` = `0x4`, `RUN`/`HOST` = `0x10`.
The lexer token `Value_Flags` mask remains its separate `0x1070001F` domain.
Known semantic/generated bits classified out by the M2 registry are excluded, not copied into source flags; an otherwise unknown bit or an unsupported source bit fails conversion rather than being silently discarded.
A name being in this registry does not prove it is active in every producer route.
This is conservative source projection, not acceptance of compiler-processed nodes or instrumenting a missing parser path.
Guarded aliases encode `NODE`/`ALIAS` only under the six M2 alias rules; other backreferences are absent.
Owning edges are acyclic and in range; permitted alias cycles do not become traversal edges.
Conflicting IDs, unsafe pointers or unregistered active helpers fail conversion.

#### Recovery and Raw Diagnostics

`RecoveryRecord` is `{kind:MISSING_TOKEN|EXPECTED_EXPRESSION|SKIPPED_TOKENS|ERROR_SPAN, token_span:TokenSpan, diagnostic_index:s64, synthetic_token_index:s64}` in producer append order.
Retain signed indices verbatim for C1 observation, including the producer's -1 no-synthetic sentinel; do not turn them directly into dereferenceable local IDs.
Correlated index/name recovery uses checked `Optional` references instead.
`TokenValue` is the five-arm `NAME`/`UNSIGNED_INTEGER`/`FLOAT64_BITS`/`STRING_BYTES`/`NO_VALUE` union already defined by source-tokens/1, with exactly those payload fields.
`SyntheticTokenRecord` is `{insertion_index:s64, tag:TokenTag, coordinates:Coordinates, value_flags:u32, ident_is_backticked:bool, value:TokenValue}` preserving the active union under the same token-value rules, without original/preceding source slices or a fabricated `SOURCE` origin.
Its active value must be qualified from the actual producer route; unavailable/unsafe union observations fail exact conversion.
`ResolveRecovery` indexes the recovery array by its checked array position, not by its signed diagnostic/synthetic observations.

`RawDiagnostic` is `{code:DiagnosticCode, severity:ERROR|WARNING, token_span:TokenSpan, message_bytes:bytes, expected_token:TokenTag, actual_token:TokenTag, recovery_action:RecoveryAction, lexer_line:s32, lexer_column:s32, related:[]RawRelatedDiagnostic}`; `RawRelatedDiagnostic` is `{token_span:TokenSpan, message_bytes:bytes}`.
`DiagnosticCode` and `RecoveryAction` are the five codes and three actions already fixed by diagnostic/1.
Raw messages preserve exact producer bytes even when not valid UTF-8; the presentation diagnostic query then fails `INVALID_TEXT` rather than rewriting them.
Raw token spans/indices retain observations even when not valid source maps, while every exposed `SOURCE` slice/origin must validate independently.
`ParseStatus` has exactly `COMPLETE`, `INCOMPLETE`, `RECOVERED`, `FATAL`.
Diagnostic counts, order and recovery relationships agree with the protected producer; a well-owned fatal parse can still have available observations.

The three envelope schemas and backing resolvers are now fixed by these records plus the existing diagnostic/1, declaration-index/2, token, origin, coverage and M2 field registries.
An implementation lacking one mapping must truthfully reject its tuple/query or fail the affected conversion; partial declaration coverage cannot launder an inexact snapshot.
Full snapshot access is not required for an independently supported partial index with safe `OPAQUE` backing.
Executable producer round trips, adapter observation correlation and lifetime/concurrency qualification remain future implementation work.

### Milestone 3: Closure and Review Checks

Milestone 3 is complete as a draft logical API/source/payload specification on 2026-10-22.
The fifteen scheduling/source operations, six read-only accessors, response/error catalogue, six-event transaction grammar, provider and syntax-adapter admission, node/helper/token/recovery projections, canonical value encodings, nineteen effective bound fields and optional quota requests are specified above.
This is not final API approval, a native ABI, a store format, an adapter implementation or production qualification.
The 2026-10-23 R2/R6-R8 decisions select location/enablement/recovery/no-history/exclusive-ownership/resource policy and measurement-first/external-assumption boundaries; whole-contract approval stays pending.

For source batches, the requested milestone document set is exactly the distinct event documents; context registration does not add members.
`AnalysisRequest` retains its explicit requested set.
`AcquireWorld`/`HEAD` first acquires an exact-frontier published head; otherwise it reports `PENDING` only if an identified nonterminal accepted update targets that frontier, `FRONTIER_MISMATCH` if another published head exists, or `NO_HEAD`.
It creates no hidden waiter or analysis request.
World identity remains distinct from configuration, document context and provider frontier.

| Closure check/future independent negative control. | Existing acceptance mapping and boundary. |
| --- | --- |
| Match all fifteen signatures to response records; reject foreign/released/wrong-kind handles; retain a result/world after session release. | T5/T6, X1-X3, X7/X8.  The six accessors borrow only; acquiring/retaining still creates independent registrations. |
| Canonical encode empty/present/absent, signed widths, float bits, all 79 token names, aliases, all closed flags, all field-value arms, nested lengths and wrong schema/field counts. | C1/C2/C5, T2/T5.  Compare exact authored expected bytes/observations, not only encode/decode through the same mapping. |
| Stage a first binding/new context alongside a bad second event; reject without installing either; permute analysis membership but preserve sequential edit order. | V1/V5/V6, T2/T3.  No hidden provider read, partial transaction or invented membership. |
| Save B after newer overlay C, including B/C with identical bytes but different installation revisions; preserve C and report disk/overlay branches separately. | V5/V7, T3, S3/S4.  Content equality does not establish overlay identity; store/runtime qualification remains separate. |
| Change only a provider/adapter policy, schema tuple or feature binding; reject unsupported combinations and never relabel retained results. | C2/C5, T5/T8, V2/V4.  Declared capabilities require actual registered implementations, not manifests or client assertions. |
| Exceed each finite limit at admission, intermediate edit, nested decode, publication and completion registration; exercise checked arithmetic and exact-boundary values. | T2, X4/X6-X8, V5.  No silent clamp, lost terminal notification, false partial output or invalidated retained payload. |
| Resolve every derived-result reference after releasing producer/world/snapshot siblings; inject cross-domain IDs, unknown flags, unsafe helpers and unmappable message bytes. | C1/C5, T6, X1-X3.  Exact snapshot/diagnostic conversion fails truthfully; safe partial index backing does not claim exact capture. |

Document-only catalogue/source checks validate that these definitions are present and consistent; they do not execute these future acceptance cases.
Milestones 4-7 supply separate identity/deferred-semantic, execution/ownership, store and complete acceptance-mapping drafts; milestone 8 owns cross-contract review/sign-off, not automatic implementation approval.
Migration and implementation require separate authorisation.
No pending policy, qualification checkbox or release claim is completed by this closure.

### Bootstrap and Retry Consistency Pass

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
Milestone 3 supplies record limits and session-option validation.
Milestone 4 supplies identity allocation.
Optional host quotas and tests of our issuer/concurrent adapters remain implementation work; no fixed resource budget or independent external-system certification is a prerequisite under the 2026-10-23 decisions.

### Worked Edit-to-Result Protocol

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

### Latency Boundaries and Acceptance Mapping

Use monotonic timestamps per operation/identity; correlate pending completion with the original ticket/waiter rather than restarting the timer at every poll.

| Metric. | Start and finish. | Existing acceptance coverage to implement. |
| --- | --- | --- |
| Admission latency. | `SubmitSourceBatch` entry to accepted/rejected response.  Includes validation/input ownership/admission bookkeeping; report separately from analysis completion. | T2, V5, X7: stale/invalid/closed work rejects truthfully without partial acceptance. |
| Edit-to-usable syntax/index. | Submission entry through published milestone and successful `AcquireWorld` for that exact revision, plus acquisition of the requested syntax/index result.  Include queueing, acquisition, parsing, validation and publication; also report service-ready versus host-observed timestamps. | T1, T7, V6: no mixed/old-world result, no false success for superseded/failed work.  This is the main P2/user-edit path. |
| Unchanged query latency. | `Query` entry to owned `RESULT`, including `AcquireResult` if pending.  Charge validation, scheduling, rehydration and lease acquisition, not only a resident lookup or first `PENDING` response. | T5, T6, X1-X3: exact payload, safe retention, no lost completion; primary P1 comparison. |
| Restart-to-usable result. | Process entry through provider/store validation, world capture/publication and owned requested result.  Report process wall and worker phases separately, with filesystem cache condition. | S1, S2, S6, V2-V4 and T4: source authority, bounded fallback, explicit absent/unknown/recovery.  Optional AST loading is the P3 competitor, not a requirement to decode the historical graph. |
| Delivery/host delay. | Service terminal-ready timestamp through host observation/acquisition.  Show separately and within end-to-end totals; delayed host draining must not hide scheduler latency or inflate a claimed parser-only time. | X4, X5, X8: delayed/reentrant dispatch and shutdown retain truthful outcomes/leases. |

Report successful latency alongside rejection, supersession, cancellation, timeout and failure counts; dropping non-successful edit samples must not manufacture a faster tail.
Keep memory/backing/store measurements secondary but visible, with safety and leak obligations unchanged and no numerical P1-P5 cutoff newly approved.
Milestone 3 supplies logical operation signatures, syntax/source encodings, payload schemas and admission bounds for API review; rename is explicitly unsupported.
The milestone-4 semantic identity/allocation draft, native ABI decisions and implementation qualification remain separate concerns; these records/tables are not executable acceptance tests.

### Milestone 7: Acceptance Scope and Requirement Map

Drafted 2026-10-23 against the milestone-2 through milestone-6 contracts and the [decision record](CACHE_ARCHITECTURE.md#decision-record).
This is an executable-test specification for a future implementation, not new passing evidence, approval of unresolved policies or authorisation to build/run the service.
Acceptance checks our code under documented OS/provider/identity-authority assumptions, not external storage certification or performance percentages chosen before measurement.
The approved initial scope remains syntax-first; source/recovery persistence is required, persisted AST reuse and semantic/evaluator execution are not.

Every requirement row below needs direct assertions at its named boundary; listing a related trace does not prove coverage of every field or transition.
T1-T8, S1-S8, X1-X8 and V1-V8 are initial trace families, with the capability-specific restrictions below; D1-D8 are deferred semantic cases, not initial feature passes.
Where a trace describes a later capability, test its explicit rejection now and retain the successful-feature branch as deferred.
The acceptance runner must enumerate all cases/subcases with exact contract/schema versions and independent expected outcomes; no family can pass merely because one happy-path example passed.

| Requirement. | Initial obligation and mapped cases. | Independent oracle and discriminating failure control. |
| --- | --- | --- |
| A1: Exact owned syntax. | C1/C3; T1/T5, V7 and the milestone-2 allocation/field/helper registry.  Exercise every registered supported route, token/value/flag domain, source/recovery/span/diagnostic/index field and explicit partial disposition. | An independently owned fresh parse of the same exact bytes/context plus authored structural expectations; destroy/poison producer, input and sibling backing.  A shallow alias, omitted field, wrong active union or falsely complete partial result must fail. |
| A2: Source selection and atomic admission. | C1/C2/C5; T1-T4, V1/V2/V4-V6.  Cover empty/present/absent/unknown/unavailable, sequential edits, multi-document/context binding and stale/invalid rejection. | An external accepted-event ledger computes exact disk/overlay branches and one frontier per batch.  Inject failure at each staged member; any partial selection, accidental absence or old-base commit must fail. |
| A3: Identity and context isolation. | C2/C3; T5, X3, S8 and direct milestone-4 identity vectors.  Check all live identity domains, fresh epochs, generation reuse/exhaustion, canonical key bytes and exact producer/context separation. | Authored canonical bytes and a separately controlled issuer ledger, including rollback/fork simulations under the issuer assumptions.  Reused live IDs, wrapped counters, cross-context hits or revived archive handles must fail; semantic declaration matching stays deferred. |
| A4: Save/reset/recovery authority. | C2/C4/C5; T3/T4, S3/S6, V1.  Include a newer byte-identical overlay, failed removal commit and copied recovery with an unavailable old producer. | The host-event ledger distinguishes installation revision from content revision and committed recovery from live selection.  An old save clearing the newer overlay, orphan resurrection, automatic restore or restore without current admitted context must fail. |
| A5: World/task publication. | C1/C2/C3/C5; T1/T6/T7, V6, X1/X2/X7.  Cover complete multi-document worlds, joins, attempt/mailbox tokens, supersession and exact selected-world queries. | An external accepted-request/attempt ledger and barrier-controlled completions.  Publish duplicate/out-of-order attempts deliberately; mixed revisions, old-head overwrite, duplicate ownership transfer or an already-complete join left pending must fail. |
| A6: Delivery and progress. | C3/C5; T6, X1-X6.  Cover all fifteen calls, six borrowed accessors, poll/wait/drain semantics, terminal errors, host-helper re-entry and required/optional readiness. | Authored response/state tables, independent registration/completion ledgers and controlled wake/drain barriers.  A lost wake, double drain, consumed-on-failed-copy record, callback under a gate or starvation by optional work must fail. |
| A7: Shutdown and final ownership. | C3/C5; T5, V7/V8, X3/X7/X8.  Cover first reserved/repeated shutdown, a producer beyond deadline, retained children after `STOPPED` and final owner release. | Provider/worker barriers and independent pin/free/join ledgers.  A wait timeout treated as termination, self-dependent shutdown, leaked scheduler root, lazy store reopen after stop or freed retained payload must fail. |
| A8: Store wire and reconstruction. | C1/C4; S1/S5/S8 and direct milestone-6 grammar/schema vectors.  Check all seven record kinds, exact envelope/chunks/field order, references and implementation bounds before unsafe allocation. | Independently encoded expected files/keys plus a strict test decoder and allocation ledger; recompute outer hashes on structurally invalid inner values.  A normalised invalid frame, trusted count, unresolved reference or assertion abort must fail. |
| A9: Store ordering and interruption. | C2/C4; T4, S2/S3/S6.  Cover first initialisation, every staged/install/head boundary, exact predecessor reconciliation and stale writer/sequence rejection. | Independently recorded intents/commit IDs and raw fresh-process file inspection under stated rename assumptions.  An orphan reported committed, blindly retried uncertain commit, stale tombstone overwrite or false durable frontier must fail. |
| A10: Pins, collection and administration. | C3/C4; T5, S4-S7.  Cover old manifest/read pins, failed deletion, history/expiry, explicit maintenance preconditions and partial quarantine/reinitialisation. | Independent root/pin/file inventories with mark/open/delete barriers and action-bound host confirmations.  Deleting protected/unknown roots, inferring permission from pressure or age, fabricated offline session IDs or false secure-erasure success must fail. |
| A11: Honest capabilities and diagnostics. | C4/C5; T8, V2/V3/V8, S8 and rejection branches corresponding to D1-D8.  Check unsupported semantic/evaluator/discovery/AST capabilities before task creation. | Authored capability/error tables plus child-process, source-write and task-creation monitors.  A guessed successful binding, silent empty answer, false language error, compiler launch or source-file mutation must fail. |
| A12: Default resources and configured quotas. | C3/C4/C5; S1/S7, X5/X7/X8, V5/V8 and direct `LimitRequest`/`StoreLimitRequest` vectors.  Exercise omitted/`-1`, positive configured values, malformed/zero/below-`-1` values and exact/one-over effective bounds. | Independent allocation/reservation/file accounting and fail-on-requested-allocation/write controls.  A hidden fixed RAM/disk quota, unchecked count, silently raised user limit, revoked lease or failed emergency shutdown reservation must fail. |
| A13: Project-relative/private store placement. | C2/C4/C5; S8 plus direct policy-binding/host-discovery cases.  Resolve `.jaiParserCache` from the declared project root; test changed working directories, overrides, foreign namespaces and unavailable exclusion/privacy setup. | A controlled host root/discovery model and independent touched-path inventory.  Wrong-root fallback, source/watch ingestion of managed files, escape/adoption of a foreign store or implicit source/VCS edits must fail. |
| A14: Failures and retry isolation. | C1-C5; T2/T8, S1-S8, X2/X5/X8, V5/V8.  Fail each ownership-transfer/admission/store boundary and repeat the request from its permitted state. | Independent before/after source/registration/root ledgers and exact allocation/free counts.  Source rollback after acceptance, partially acquired ownership, duplicated terminal outcomes or retry replay of a committed source event must fail. |
| A15: Measured trade-offs. | P1/P2/P4/P5 on the workload matrix below; P3 successful AST reload is deferred.  Compare equivalent admitted work, retained worlds, source validation and cleanup. | Raw paired wall/worker/allocation/store observations with independently checked result equality.  An inequivalent baseline, omitted failure/sample, excluded cleanup cost or historical percentage used as a gate invalidates the comparison. |

The map includes both approved scope/policy requirements and proposed detailed contract obligations; final sign-off must adopt or revise the latter before implementation planning.
Test configurations must name the approved enabled/recovery/no-history/exclusive-owner defaults or an explicitly admitted alternative; the runner must not invent another policy.

#### API Boundary Subcases

These mandatory subcases expand A3/A5-A7/A11/A12/A14 against the normative milestone-3 signatures and milestone-5 ordering table; they neither add operations nor change their error/ownership semantics.
For every row, include wrong kind/version/session, stale registration/generation, quota/allocation failure and release races where the operation admits them; record unchanged state and exact ownership on every rejection.

| Operation. | Required direct assertion beyond the related trace family. |
| --- | --- |
| `OpenSession`. | Missing authority/policy and failed baseline reservations expose no partial session; omitted optional quotas negotiate technical bounds, store-only failure can degrade, and archived candidates cannot become active state. |
| `DescribeSession`. | Coherent copied source/store/frontier/limit state without advancing admission or acquiring a payload lease; a later source submission still validates its base. |
| `SubmitSourceBatch`. | Atomically accept all bytes/context/document changes and one frontier with an owned ticket, or reject all; analysis/store completion and a quickly finished ticket do not alter that ownership. |
| `RequestAnalysis`. | Analyse/join the exact selected frontier without advancing it, replaying a source event or leaving an already-published join pending. |
| `ObserveTicket`. | Terminal observation is atomic; each pending observation creates one independently owned waiter, not an implicit poll or shared registration. |
| `AcquireWorld`. | Require an explicit valid published/head selector and exact expected frontier; mismatch creates neither an implicit latest world nor a hidden waiter, and successful acquisition protects backing atomically. |
| `Query`. | Exact-world immediate result/terminal/pending arms, with protection or waiter installation atomic against completion and source supersession; stale-world misses return `WORLD_SUPERSEDED` without new work.  Immediate results emit no completion record and unsupported requests create no analysis task. |
| `Poll`. | Observe terminal/pending state without consuming delivery, registering another waiter or acquiring result/world ownership. |
| `Wait`. | The same observation semantics plus deadline/clock validation; timeout remains pending, and neither cancels work nor proves a producer stopped. |
| `AcquireResult`. | Require the live available query waiter and install independent result ownership against release; repeated success creates separately releasable leases. |
| `CancelWaiter`. | Caller/UI stop has one waiter-local terminal winner; preserve other current-world consumers, source state and the registration until release.  Separately exercise task-wide supersession of every pending old-world waiter, including first-terminal reason preservation and explicit client retry. |
| `DrainCompletions`. | Enforce checked maximum and once-only terminal records; a failed copy consumes none, and a successful drain neither releases registrations nor transfers result leases. |
| `Retain`. | Create a distinct world/result registration protecting identical immutable backing; copying bits does not retain, and a lost release race rejects safely. |
| `Release`. | Retire exactly once, reject stale/double release without reaching a reused generation, and preserve an active session on `ACTIVE_SESSION`; release detached client interest separately from producer ownership. |
| `RequestShutdown`. | First call reserves an observable shutdown and quiesces atomically; repeats observe the same operation through distinct registrations, and surviving payloads remain readable until their own release. |

- For `ReadWorld`, check the exact protected world description/membership rather than a newer head; for `ReadResult`, check exact selected-world payload/query association and explicit completeness.
- For `ReadSource`, check exact selected source bytes/bounds with no path-based recapture; for `ResolveNode`, check backing/world-local IDs, registry kind and owned-edge validation.
- For `ResolveToken`, check token range/source attribution and exact bytes; for `ResolveRecovery`, check recovery kind/references/span ownership without inventing authored source for synthetic content.

All six are borrowed read-only accessors under the existing owner protection, not new registrations or scheduling calls; test invalid/cross-backing references, retained-owner access after stop and rejection before any unsafe dereference.
Do not use a borrowed view after releasing its last protecting owner and call that a valid lifetime test; instead verify the required owner survives in-flight access and poison backing only after its contract permits release.

### Milestone 7: Workloads and Measurement Boundaries

Use a frozen read-only source manifest for every workload: canonical relative names, exact source bytes/lengths and SHA-256, selected contexts, toolchain/adapter/schema revisions and explicit inclusion/exclusion rules.
Never infer semantic import closure, execute source, edit project inputs or follow filesystem links merely to build a workload.
Fixture creation, failure injection and staged store writes belong only to an explicitly authorised isolated test root; a host-declared project/cache root is not blanket test-write permission.

| Workload. | Required coverage and selection. | Measurement/claim boundary. |
| --- | --- | --- |
| W1: Authored contract vectors. | Minimal independently expected fixtures covering every milestone-2 registry route/field/helper/flag/value disposition, canonical identity/optional arms, source transactions, exact limit edges and malformed wire bytes. | Correctness/negative-control corpus, reported separately from real-project performance.  Missing supported-route vectors block that route's qualification rather than being hidden by corpus averages. |
| W2: Recorded real-source inventories. | E12's 56 top-level tutorials, eight recursive Invaders files, four top-level parser files and 18 top-level Basic files, each separately frozen for the new run.  Keep the three-file authored import chain separate. | These are historical selections, not guaranteed current counts or complete linked programs.  Record changed inventories rather than relabelling a new checkout as the old 89-file experiment; do not inherit its old fixture limits or timing results. |
| W3: Larger project candidate. | The regular `.jai` source tree recursively under `modules/Jai_Parser`, excluding `.git`, `.build`, the configured cache root, generated/test-run output and filesystem links.  Freeze the exact manifest, active-file selection and size distribution. | Proposed larger parser-development workload, not an already approved/measured application.  Review its actual file/byte/active-file distribution against W2 and the intended host use before generalising; inadequate scale/representativeness requires an explicit replacement or a narrower claim. |
| W4: Stateful edit workload. | For each selected real workload, authored body/interface/trivia/layout changes, malformed edit/repair, multi-file batch, save race, reset and repeated unchanged requests, with only the current world retained normally.  In a separate ownership stress variant, clients explicitly lease two older worlds across edits. | Log exact input batches and independently computed accepted states; do not write edits into original project files.  Report normal and stress results separately, compare equal ownership in paired modes, and release the older leases when their checks finish.  These temporary live leases are not persistent history, editor undo/redo or evidence of semantic invalidation. |
| W5: Interleaving/failure workload. | T1-T8, S1-S8, X1-X8, V1-V8 and direct A1-A14 vectors under controlled barriers, duplicate tokens, allocation/provider/store failures and configured-quota/no-quota modes. | Record each attained barrier/fault and expected outcome.  Stress schedules supplement reproducible cases; a random run that never reaches the intended race is not its test.  Process interruption tests are distinct from external power-loss guarantees. |
| W6: Restart and resource workload. | Fresh service/process with existing source/recovery metadata; source changed without trusted timestamps; unavailable old producer; preserved recovery; staging/quarantine/failed deletion and optional quotas. | Compare authoritative source validation/reparse with equivalent required metadata/recovery work.  No persisted-AST/P3 success, OS-cold condition or durable frontier is implied by fresh-process startup. |

For P1/P2, time host request/edit submission through acquisition of the exact usable syntax/index result, including admission, acquisition/validation, hashing, queueing, parsing/reuse and publication.
Report worker phases separately; an isolated parser call or pointer lookup is not the end-to-end competitor.
For W6, report process wall time separately from worker validation/read/reparse time and separate setup/artifact creation from the measured request; perform equivalent required store/recovery work in both modes.
Keep equal retained ownership and cleanup boundaries in paired modes, report teardown separately where outside request latency, and include it in complete lifecycle/resource totals.
Record monotonic clock identity/frequency/units, ordered raw samples, mode order, warmups, environment/compiler/build options and declared storage conditions; checked timestamp differences precede unit conversion.
Use the existing plan of at least 21 measured trials per mode, alternating/rotating order, in two separate local rounds; nearest-rank p95 is a sample statistic, not a hard latency guarantee.
Report per-workload median/p95, absolute/relative deltas, failed/cancelled samples and reason codes; do not silently trim failures, average away a regressing inventory or manufacture a percentage when a baseline is zero.
Report peak owned/upstream backing and process memory separately, final live-owned allocations, logical managed file bytes/counts and peak staging/quarantine/cleanup overhead.
Instrumentation/oracle work excluded from a timed boundary must be excluded equivalently and still run for every compared result; a correctness failure invalidates that sample's performance comparison.
Evaluate measured results afterwards under the 2026-10-23 direction; no historical percentage/byte ratio is an implicit pass/fail threshold or default quota.

### Milestone 7: Case Records, Controls and Verdicts

An acceptance case is identified by its requirement row, trace/subcase, fixture manifest, contract/build/profile versions and named policy configuration.
Its record must contain the following independently auditable information; these are test-evidence obligations, not a new public API or adopted persistent schema.

| Record part. | Required content and validity rule. |
| --- | --- |
| Preconditions and scope. | Initial successful feature, initial rejection, deferred successful feature or excluded claim; exact host authority/context, quota mode, retention/enablement/ownership configuration, isolated root and external assumptions.  A missing unresolved policy binding blocks that configuration; the runner cannot choose it silently. |
| Planned schedule. | Authored ordered calls/events, expected admission/frontier/terminal transitions, retained registrations and exact barrier/fault sites.  Each call/error/accessor arm must have explicit expected ownership on success and failure. |
| Independent expectations. | Fresh-owned syntax and authored field/route expectations, canonical expected bytes, host event/issuer/attempt ledgers and expected root/pin/allocation accounting as appropriate.  Do not derive expected values from the production coordinator, matcher, wire decoder or collector being checked. |
| Observed evidence. | Actual calls/outcomes/tokens, barrier/fault acknowledgements, diagnostics, allocation/free/pin/worker events, touched-file/process inventory and raw measurements.  Preserve complete ordering/provenance and distinguish source acceptance, syntax publication and store commit. |
| Negative control. | One named deliberately broken implementation path or independently mutated fixture/result per distinct invariant/oracle.  It must produce the expected mismatch/failure without depending on the production assertion that is being tested. |
| Cleanup and rerun. | Close the test's workers/handles, reconcile uncertainty, release all owned registrations/backing and verify the expected isolated-store inventory; retain only explicitly recorded evidence.  Record seed/schedule/build, so the failure can be replayed. |
| Verdict and review. | One explicit verdict, expected-versus-observed differences, links/keys to immutable evidence and reviewer/decision.  Record performance observations separately from correctness outcomes and final adoption decisions. |

Use only `NOT_RUN`, `BLOCKED`, `PASS`, `FAIL`, `DEFERRED` or `EXCLUDED` as correctness/coverage verdicts; unresolved measurement trade-offs use a separate review decision, not a fabricated correctness pass.
`NOT_RUN` means the applicable case has no executed evidence; `BLOCKED` means a named missing implementation/configuration/fixture/barrier/oracle prevents a valid run.
`PASS` requires every expected assertion, the attained planned interleaving/fault, a detecting negative control and clean ownership/cleanup; any wrong observable result, undetected broken control or missing required cleanup is `FAIL`.
If the planned barrier/fault was not reached, report `BLOCKED`/`NOT_RUN` as appropriate, never a race pass from the absence of a crash.
`DEFERRED` is a later supported-feature test not enabled initially; its initial unsupported-rejection case has a separate ordinary verdict.
`EXCLUDED` is a documented claim outside the agreed scope, such as external power-loss/OS-cold guarantees; neither verdict contributes to initial successful-feature counts.
All cases in this document begin `NOT_RUN`, except explicitly classified deferred/excluded branches; E1-E13 retain their historical experimental evidence but do not change future-service case verdicts.

For T/V source traces, author the event ledger before executing the calls and compare each admission/rejection, exact source branch and frontier, not only the final tree.
For X traces, place barriers around each relevant gate/registration/publication/free boundary and run both orderings and duplicate/late callbacks where admitted; a scheduler model alone cannot qualify real concurrent service code.
For S traces, use independently encoded files and root inventories, check corrupt-but-rehashed records and interrupt our code at each staged/installed/head boundary; only our handling under the documented primitive assumptions is tested.
For syntax/identity vectors, mutate an expected field/tag/reference/epoch or poison released backing and demonstrate that the independent oracle rejects it; fresh and cached results sharing the same faulty converter are not independent proof of complete syntax projection.
Fault injection uses bounded fail-at-boundary cases with recorded allocation indices and expected release counts, not an attempt to exhaust the real machine's RAM/disk to test the all-available default.
A stuck worker test must have an external test-owned release/abort mechanism; a missed test deadline cannot authorise freeing service backing still used by that worker.
Where delete/cleanup failure is intentionally injected, the expected surviving file/accounting inventory is part of the assertion rather than an unexplained leak exemption.

### Milestone 7: Coverage Ledger and Closure

Milestone 7 is complete as a draft whole-system acceptance specification on 2026-10-23: A1-A15 map initial obligations to direct checks and trace families; W1-W6 define workloads; case records, independent controls and verdict rules define executable qualification evidence.
Before accepting an implementation, expand the ledger by every supported registry route, public operation/accessor/error arm, source-event/optional variant, bound edge and fault boundary; retain explicit unimplemented/unsupported dispositions instead of claiming coverage from a family label.
Every T1-T8, S1-S8, X1-X8 and V1-V8 case must have initial positive/rejection subcases as applicable, mapped requirement IDs and attained controls; D1-D8 successful semantic branches and P3 AST reload remain deferred, with initial rejection checks retained.
Coverage totals must separately list applicable/passed/failed/blocked/not-run cases, deferred successes and excluded claims; no denominator may hide missing supported syntax, unexecuted concurrency or required source/recovery persistence.
Acceptance requires no `FAIL`, `BLOCKED` or `NOT_RUN` applicable correctness obligation and no unexplained live ownership; performance remains a measured results packet for later evaluation, not a percentage gate.
Workload/profile approval and whole-contract sign-off remain milestone 8 responsibilities; the selected enablement/recovery/no-history/exclusive-owner policy is recorded in the [decision record](CACHE_ARCHITECTURE.md#decision-record), and the W3 manifest must be reviewed before a generalised performance claim.
No production/service test, benchmark, interruption run or new compiler experiment is executed by this documentation milestone; no implementation/migration permission or final release approval is implied.

### Milestone 8: Cross-Contract Review

Document review performed 2026-10-23 against the milestone-2 through milestone-7 drafts and the recorded scope/policy decisions.
The review checks the following controlling boundaries, not an implemented service or externally certified platform; acceptance verdicts remain unchanged.

| Boundary. | Reconciled rule and required evidence. | Review disposition. |
| --- | --- | --- |
| B1: Admission versus analysis. | A source batch commits exact bindings/bytes and one frontier before syntax/index readiness.  Parse/store failure cannot undo admission; a retry uses `RequestAnalysis`, not replayed edits/saves.  A2/A5/A14, T1/T2/T7, V5/V6. | Drafts distinguish accepted source, published analysis and failed/retried work; implementation tests remain required. |
| B2: Disk versus overlay/recovery. | Save removal compares installation and content revisions; a newer byte-identical overlay survives.  Reset/removal requires a committed tombstone, and a failed removal leaves only a host-confirmed recovery candidate on restart.  A4/A9, T3/T4, S3/S6. | Enabled recovery without automatic expiry or optional revision history is selected; no disk timestamp, orphan blob or copied offer selects live source or replaces editor undo/redo. |
| B3: Identity versus archived content. | Content/context/artifact identity never revives session/world/result/operation registrations; source reuse reparses under the admitted current context.  Epoch authority lives outside disposable cache/clear scope.  A1/A3/A8, T5, X3, S8. | Preserve nonreuse assumptions and conservative misses; stale external-certification wording corrected without claiming that a cache can verify a dishonest global issuer. |
| B4: Task versus observer ownership. | Shared tasks have generation/attempt-checked single publication; current-world UI stop is waiter-local, while source-frontier supersession cancels obsolete shared work and all still-pending query waiters with a distinct reason.  Observation/acquisition/drain ownership stays separate.  A5/A6, T6/T7, X1-X5. | No automatic world switch/retry or revoked published result; retain cancelled producer ownership until safe stop.  Fifteen operations and six borrowed accessors remain unchanged; detailed updated contracts still await sign-off. |
| B5: Terminal versus stopped versus destroyed. | Cancellation/deadline is not producer termination.  `STOPPED` requires safe compute/provider/store finalisation, while retained resident child backing survives session release until final ordinary release.  A7/A12, X7/X8, V7/V8. | Reserved shutdown/reaper and surviving-owner lifetime agree; neither a wait timeout nor store degradation frees in-use backing. |
| B6: Store commit versus durability. | Immutable records precede complete-file head replacement; uncertain replacement reconciles exact predecessor/proposed commit.  `PROCESS_ATOMIC` receipts leave durable `StoreStatus.acknowledged_frontier` at `NONE`.  A8-A10, S1-S6. | Our interruption/error handling is required under stated primitive assumptions; no power-loss/external filesystem guarantee is promoted to an initial release gate. |
| B7: Quotas versus safety. | Omitted `LimitRequest`/`StoreLimitRequest` fields mean no configured quota; effective `Limits`/`StoreLimits` remain checked technical bounds.  Allocator/write failure preserves source, protection and shutdown reservations.  A12/A14, S7, X5/X8. | No mandatory fixed RAM/disk budget or infinite numeric sentinel; optional ceilings must be enforced without silently increasing them. |
| B8: Location/privacy versus ownership. | Resolve `.jaiParserCache` from the declared project root, exclude managed data from source/watch/VCS ingestion and reject incompatible namespaces/unsafe paths.  Exclusive ownership is approved; contention degrades only persistence.  A10/A13, S4/S8. | No concurrent shared-store/multiwriter approval; the contending editor must report that its recovery is not being persisted. |
| B9: Supported versus reserved capability. | Initial owned syntax/source/recovery is required; semantic/evaluator/discovery and persisted-AST successful-feature paths remain unsupported/deferred.  Initial rejection checks remain required and create no compiler/task side effects.  A1/A11, T8, V2/V3/V8. | D1-D8/P3 success is not initial coverage; no implementation of deferred semantics is inferred from its extension schema. |
| B10: Draft/evidence versus approval. | A1-A15/W1-W6 specify future cases and measured comparisons; E1-E13 remain bounded historical evidence.  Negative controls, attained barriers, independent oracles and clean ownership are required for applicable correctness passes. | No document audit passes a runtime case; workload/profile acceptance, complete specification sign-off and implementation/migration permission are separate decisions. |

The identified local inconsistencies were stale external-authority certification language, not a reason to drop nonreuse or independent tests of our adapters.
No runtime race/lifetime/durability/performance claim follows from these review dispositions.
### Milestone 8: Policy Answers and Pending Sign-Off

Recorded 2026-10-23: persistence is enabled by default; the initial project/provider store has one owning process/writer session; recovery is enabled, but optional persistent history is not, because the editor handles undo/redo.
Recovery protects current unsaved content until it is superseded or removed through the established host save/reset/discard protocol; it is not a time-expiring revision archive or an automatic restore command.
Older live leased versions remain protected, while unreachable physical files follow safe GC rather than a promise of immediate erasure.
The user explicitly kept overall specification sign-off pending and paused to finish reading; these policy answers do not approve planning, implementation, migration or runtime acceptance.
No further review questions or approval requests are implied by recording this clarification.
The subsequent cancellation clarification distinguishes current-world caller/UI stop from obsolete-world shared-task cancellation; all still-pending shared query waiters receive `WORLD_SUPERSEDED` and independently choose whether to reissue.
This changes the execution/cancellation draft and its acceptance controls, not the pending whole-specification sign-off or implementation permission.
The larger-project W3 exact manifest/representativeness must still be recorded before a generalised performance claim; accepting a workload selection/procedure is not approving an unrecorded measurement result.
