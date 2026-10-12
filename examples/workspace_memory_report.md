# Workspace Creation/Destruction Memory Growth

## Environment

- Windows x64, measured 2026-10-12.
- Jai beta 0.2.030, built on 2 July 2026; compiler arguments `-x64 -quiet`.
- Each measurement starts a fresh compiler process.  Runs are serial and capped at 16 workspaces.
- `workspace_memory_repro.jai` imports only Basic, Compiler, and String.  It has no Jai_Parser, allocation debugger, native sampler, or differential fixtures.

## Reproduction

From the Jai_Parser repository root, run each command separately:

```powershell
pwsh -NoLogo -NoProfile -File examples/profile_differential_memory.ps1 -SourceFile workspace_memory_repro.jai -Section '0:create-only'
pwsh -NoLogo -NoProfile -File examples/profile_differential_memory.ps1 -SourceFile workspace_memory_repro.jai -Section '1:create-only'
pwsh -NoLogo -NoProfile -File examples/profile_differential_memory.ps1 -SourceFile workspace_memory_repro.jai -Section '16:create-only'
pwsh -NoLogo -NoProfile -File examples/profile_differential_memory.ps1 -SourceFile workspace_memory_repro.jai -Section 16
```

Create-only mode calls `compiler_create_workspace`, checks the returned handle, then calls `compiler_destroy_workspace`.  It adds no child source, changes no child options, and never intercepts messages.  Compile mode adds the same `fixture_value :: 1;` source to each child, waits for successful completion, ends interception, destroys the workspace, and asserts that the declaration was observed.  Both modes disable root output; compile mode also disables child output before adding source.

All four runs pass.  Counts above 16 and unsupported mode suffixes are rejected before creating children.

## Results

The external pwsh wrapper reads Windows `GetProcessMemoryInfo` high-water counters using a retained compiler process handle after exit.  Values are bytes for that compiler process, excluding the wrapper and separate child processes.

| Mode | Workspaces | Peak Working Set | Peak Commit |
| --- | ---: | ---: | ---: |
| Create-only | 0 | 131,096,576 | 643,133,440 |
| Create-only | 1 | 131,141,632 | 660,480,000 |
| Create-only | 16 | 135,376,896 | 924,164,096 |
| Compile | 16 | 313,409,536 | 1,211,822,080 |

The 16-workspace create-only commit peak is about 268 MiB above its zero-workspace baseline, while its resident peak changes by only about 4 MiB.  Compilation raises both peaks further.  Thus, the increasing commit high-water does not require parsing child source, receiving typechecked ASTs, or running Jai_Parser.

Earlier separate compiler-only compile-mode runs with 0, 1, 8, and 16 workspaces had commit peaks of 642,727,936; 739,917,824; 977,436,672; and 1,211,158,528 bytes respectively.  Those results also show continued growth beyond the first workspace.

## Interpretation

### Runner Allocation Events

The differential runner now has opt-in allocation-event accounting under `PROFILE_DIFFERENTIAL_MEMORY`.  With that flag enabled, the following bounded probe checks a short-lived allocation/resize/free sequence and excludes observer allocations, including an observer allocation freed after observation ends:

```powershell
pwsh -NoLogo -NoProfile -File examples/profile_differential_memory.ps1 -Section allocation-events -MemoryBudgetMiB 2048 -TimeoutSeconds 30
```

The probe records a two-allocation / 256-requested-byte peak and zero retention.  Both assignment fixtures record 160,168 API-live requested backing bytes, 131,087 above their starting baseline, and zero retention after Pool and temporary cleanup.  Actual Runtime checks pass 8/8 with zero retention per fixture; their largest event peak is 196,638 requested backing bytes.  These checks used fresh serial 2 GiB / 30-second jobs.  The flag is off by default.

These are event maxima, not sampled maxima.  They cover successful Basic allocation events, including observed Pool backing allocations, and exclude logical Pool/temporary objects, memory-debugger bookkeeping, and observer-owned allocations.  They do not measure physical allocator overhead, unobserved temporary backing/reuse, or transient old/new buffer overlap inside an allocator's resize implementation.  Recoverable allocation failures have not been validated.  A cleanup scope spanning multiple fixtures reports its aggregate peak explicitly as a shared-scope measurement, not as a per-fixture peak; the bounded unsigned range 1..2 verifies that distinction.

The runner event tracker does not identify compiler-native owners.  No new attribution to workspace storage, compiler-global caches, or VM/JIT state follows from these measurements.  The standalone reproducer above remains free of runner instrumentation.

### Native Ownership

These are whole-process high-water counters, not current memory after destruction or resettable per-workspace peaks.  They do not prove allocations are unreachable, identify their owner, or establish that all workspace storage remains live.  Compiler-global caches, reserved committed capacity, VM state, or asynchronous release may contribute.  Prior differential lifecycle samples showed current commit dropping at the end of interception but remaining higher across successive cleaned-up fixtures.

Question for compiler maintainers: is the create-only commit growth expected retained capacity, and should repeated `compiler_create_workspace` / `compiler_destroy_workspace` operations reach a bounded plateau?  Is there another supported lifetime or reclamation operation needed by a long-running metaprogram?

This is a local report draft; it has not been submitted.  The combined differential suite exhausted system memory in an earlier run and has not been retried.  Do not increase the reproducer's cap or infer a safe full-suite bound from these controls.
