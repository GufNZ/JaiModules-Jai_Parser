# AVX-512 Clock Measurement Handoff

Run on the Windows Ryzen 5 7600X machine, not the Core Ultra host.
A missing AVX-512 feature is a blocked measurement, not a fallback result.
This procedure compares scalar with automatic AVX-512 using the same executable and unchanged lexer dispatch.
It does not force SSE2 or AVX2, or measure a general AVX-512 downclock penalty for other processors or workloads.

## Preparation

1. Sync the parser changes and keep the same Jai distribution and corpus throughout.
In Cygwin/Git Bash, from this directory, run `bash collect_simd_timings.sh --rounds 1`.
Require both layout builds to pass the width-64 checks and the corpus benchmark to report `Widest SIMD path: AVX-512`.
Keep the resulting report for compiler, CPU, source hashes, corpus counts, and parity evidence.
2. Install/open HWiNFO in Sensors-only mode.
Enable CSV logging with a 200 ms polling interval.
Include **per-core Effective Clock**, per-core usage/utility, CPU temperature, package power, and thermal/power-limit indicators.
Record HWiNFO version, units, sensor labels, and polling interval.
Task Manager speed, requested/reported core clock alone, QPC, and invariant TSC ticks are not effective-clock measurements.
3. Choose one logical processor on an otherwise idle physical core.
Check the logical-to-physical mapping (for example with Sysinternals Coreinfo); keep the SMT sibling idle.
Record the chosen logical processor and the corresponding HWiNFO physical-core sensor.
Keep power plan, BIOS/PBO settings, cooling, and background activity unchanged.
Do not disable thermal protection or change boost settings between modes.
4. In a normal PowerShell 7 terminal (`pwsh`), run the block below from `modules/Jai_Parser/examples`.
The shell affinity is inherited by its child benchmark processes.
Change `$logicalProcessor` before running.
Start HWiNFO CSV logging first.
HWiNFO is external: no privileged register-reading driver is added to this repository.

## Collection

```powershell
$ErrorActionPreference = 'Stop'
$logicalProcessor = 2
$run = Join-Path $PWD ('.build/clock_probe_' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ'))
New-Item -ItemType Directory -Path $run | Out-Null
& jai lex_all_files.jai -o -llvm -quiet -no_color -output_path $run -exe lex_clock_probe
if ($LASTEXITCODE -ne 0) {
	throw 'Jai compilation failed'
}
$exe = Join-Path $run 'lex_clock_probe.exe'
$shell = Get-Process -Id $PID
$oldAffinity = $shell.ProcessorAffinity
$events = [System.Collections.Generic.List[object]]::new()
try {
	$shell.ProcessorAffinity = [IntPtr]([long]1 -shl $logicalProcessor)
	Get-Date -Format o | Set-Content (Join-Path $run 'local_time.txt')
	Get-TimeZone | Format-List | Out-File (Join-Path $run 'timezone.txt')
	powercfg /getactivescheme | Out-File (Join-Path $run 'power_plan.txt')
	foreach ($round in 1..4) {
		$modes = if ($round % 2) { @('scalar', 'simd') } else { @('simd', 'scalar') }
		foreach ($corpus in @('../../../examples/invaders', '../../../how_to')) {
			foreach ($mode in $modes) {
				$name = Split-Path $corpus -Leaf
				$start = [DateTime]::UtcNow
				& $exe --clock-probe $mode $corpus 2>&1 |
					Tee-Object -FilePath (Join-Path $run "$round-$name-$mode.txt")
				$status = $LASTEXITCODE
				$end = [DateTime]::UtcNow
				$events.Add([pscustomobject]@{
					Round=$round; Corpus=$name; Mode=$mode; LogicalProcessor=$logicalProcessor
					StartUTC=$start.ToString('o'); EndUTC=$end.ToString('o'); ExitCode=$status
				})
				if ($status -ne 0) {
					throw 'Clock probe failed; keep partial logs'
				}
			}
		}
	}
} finally {
	$shell.ProcessorAffinity = $oldAffinity
	$events | Export-Csv (Join-Path $run 'phases.csv') -NoTypeInformation
}
Write-Host "Collection directory: $run"
```

Each process preloads one corpus, checks complete scalar/SIMD token parity, performs two warmups, then repeatedly materialises tokens with fresh per-file pools for 30 seconds in just one mode.
Both probes execute SIMD during their untimed parity check.
Analyse only the interior of each process interval: discard at least the first and last five seconds, and inspect the traces for a stable busy interval.
If loading/parity takes longer, trim further or repeat with longer probes.
There is no deliberate idle cooldown between phases; alternating order and discarded transition samples reduce, but do not eliminate, carryover effects.
This measures sustained lexer use, not sub-millisecond transition/recovery behaviour or a pure vector-instruction stress test.

Stop HWiNFO logging after collection and retain its original CSV alongside the entire collection directory and the earlier collector report.
Match HWiNFO timestamps to UTC using the recorded time zone/local timestamp.
Retain raw samples, not just screenshots or min/max summaries.
No frequency conclusion is valid unless every probe reports AVX-512 available, parity PASS, and COMPLETE.

## Interpretation and Return Data

- For each retained phase window, summarise the selected physical core's effective-clock samples (median and range), usage, temperature, power, and limit flags.
Effective clocks include idle time; reject or separately report windows with materially different utilisation or unrelated work on the core/SMT sibling.
Confirm affinity with the observed per-core activity.
- Compare scalar/AVX-512 within the same corpus and round.
Report all four pairs and order effects, not just a pooled average.
Keep ms/scan separate from MHz; faster scanning is not itself evidence of higher or lower frequency.
- Sampling and sensor variability limit what can be concluded.
Report "no resolved effective-clock difference" when paired differences are small or inconsistent; do not claim that no frequency effect exists.
A repeatable clock difference is evidence under this workload/settings, not proof that it explains all the elapsed-time difference.
- Return `phases.csv`, every probe log, the raw HWiNFO CSV, the earlier collector report, and the recorded sensor/core/settings details.
The TODO remains open until those measurements have been reviewed.
If effective-clock telemetry is unavailable, report that limitation instead of substituting nominal clock or elapsed timing.
