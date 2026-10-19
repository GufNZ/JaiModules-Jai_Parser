param(
	[ValidateSet('Run', 'Audit', 'Check')]
	[string] $Mode = 'Run',
	[string] $BaselineDirectory = (Join-Path $PSScriptRoot '.build/project_baseline/40141fe0d05141dd9709bca383c951ab'),
	[string] $RunDirectory = '',
	[string] $Worker = (Join-Path $PSScriptRoot '.build/experiment_snapshot_codec_llvm.exe')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$Utf8 = [Text.UTF8Encoding]::new($false, $true)
$Checks = 0

function Require($condition, [string] $message) {
	if (!$condition) {
		throw $message
	}


	$script:Checks++
}

function WriteJson([string] $path, $value) {
	[IO.File]::WriteAllText($path, ($value | ConvertTo-Json -Depth 16) + "`n", $Utf8)
}

function Digest([string] $path) {
	return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
}

function InvokeWorker([string[]] $arguments, [bool] $ExpectedFailure = $false) {
	$info = [Diagnostics.ProcessStartInfo]::new([IO.Path]::GetFullPath($Worker))
	$info.UseShellExecute = $false
	$info.RedirectStandardOutput = $true
	$info.RedirectStandardError = $true

	foreach ($argument in $arguments) {
		$info.ArgumentList.Add($argument)
	}

	$process = [Diagnostics.Process]::Start($info)
	try {
		$output = $process.StandardOutput.ReadToEndAsync()
		$errors = $process.StandardError.ReadToEndAsync()
		if (!$process.WaitForExit(120000)) {
			$process.Kill($true)
			$process.WaitForExit()
			throw 'Graph codec worker exceeded two minutes'
		}


		$text = $output.GetAwaiter().GetResult()
		$text += $errors.GetAwaiter().GetResult()
		$script:LastWorkerExitCode = $process.ExitCode
		if ($ExpectedFailure) {
			Require ($process.ExitCode -ne 0 -and $text.Contains('E12_DECODE_PROBE') -and $text.Contains('Assertion failed') -and !$text.Contains('E12_DECODE_PROBE_PASS')) "Corrupt input did not reach a decoder assertion: $($arguments[-1]); exit $($process.ExitCode); $text"
		} else {
			Require ($process.ExitCode -eq 0) "Graph codec failed: $($errors.GetAwaiter().GetResult()) $text"
		}
		return $text
	} finally {
		$process.Dispose()
	}
}

function InitializeHash {
	Add-Type -TypeDefinition @'
public static class E12GraphHash {
	public static ulong Fnv(byte[] bytes) {
		ulong result = 0xCBF29CE484222325UL;
		foreach (byte value in bytes) {
			result = unchecked((result ^ value) * 0x100000001B3UL);
		}
		return result;
	}
}
'@
}

function Audit([string] $root) {
	InitializeHash
	$projects = @([IO.File]::ReadAllText((Join-Path $root 'projects.json')) | ConvertFrom-Json -AsHashtable)
	$summary = [Collections.Generic.List[object]]::new()
	$totalFiles = 0

	foreach ($project in $projects) {
		$setup = @(Import-Csv "$($project.graph_prefix).setup.tsv" -Delimiter "`t")
		$rows = @(Import-Csv "$($project.graph_prefix).timings.tsv" -Delimiter "`t")
		Require ($setup.Count -eq 1 -and $rows.Count -eq 63) 'Graph evidence row count'
		$count = $project.files.Count
		$totalFiles += $count
		$artifactBytes = 0

		for ($index = 0; $index -lt $count; $index++) {
			$file = $project.files[$index]
			Require ((Digest $file.path) -ceq $file.sha256 -and (Get-Item -LiteralPath $file.path).Length -eq $file.bytes) 'Source provenance changed'
			$bytes = [IO.File]::ReadAllBytes("$($project.graph_prefix).$index.ast")
			$artifactBytes += $bytes.Length
			$text = $Utf8.GetString($bytes)
			$lines = $text.Split("`n")
			Require ($lines[0] -ceq '[14]' -and $lines[-1] -ceq '') 'Graph version/final newline'
			$schema = $lines[1] -split ' '
			$header = $lines[2] -split ' '
			Require ($schema.Count -eq 3 -and $schema[0] -ceq 'K' -and $schema[1] -ceq $setup[0].schema_high -and $schema[2] -ceq $setup[0].schema_low) 'Graph layout fingerprint'
			Require ($header.Count -eq 4 -and $header[0] -ceq 'H') 'Graph checksum header'
			$body = ($lines[3..($lines.Length - 1)] -join "`n")
			$bodyBytes = $Utf8.GetBytes($body)
			$expectedHash = [ulong]([bigint]::Parse($header[2]) * 4294967296 + [bigint]::Parse($header[3]))
			Require ($bodyBytes.Length -eq [long]$header[1] -and [E12GraphHash]::Fnv($bodyBytes) -eq $expectedHash) 'Independent graph body digest/length'
			$first = $lines[3] -split ' ', 3
			Require ($first[0] -ceq 'S' -and [long]$first[1] -eq $file.bytes -and [Convert]::ToHexString([IO.File]::ReadAllBytes($file.path)) -ceq $first[2]) 'Exact authoritative source record'
			$filename = $lines[4] -split ' ', 3
			Require ($filename[0] -ceq 'S' -and $Utf8.GetString([Convert]::FromHexString($filename[2])) -ceq $file.path) 'Exact filename context record'
			$objects = 0
			$expectLayout = $false

			for ($lineIndex = 3; $lineIndex -lt $lines.Length - 1; $lineIndex++) {
				$parts = $lines[$lineIndex] -split ' ', 3
				Require ($parts.Count -ge 2 -and $parts[0] -cmatch '^[SBAPN]$') 'Record grammar/tag'
				if ($expectLayout) {
					Require ($parts[0] -ceq 'N') 'Object layout must follow first identity'
				} else {
					Require ($parts[0] -cne 'N') 'Unexpected layout record'
				}

				$expectLayout = $false
				$value = [long]$parts[1]
				Require ($value -ge 0) 'Negative wire count'

				if ($parts[0] -ceq 'S' -or $parts[0] -ceq 'B') {
					Require ($parts.Count -eq 3 -and $parts[2].Length -eq $value * 2 -and $parts[2] -cmatch '^[0-9A-F]*$') 'Exact scalar/string hex framing'
				} else {
					Require ($parts.Count -eq 2) 'Trailing record fields'
				}

				if ($parts[0] -ceq 'P') {
					Require ($value -le $objects + 1) 'Forward/dangling object identity'
					if ($value -eq $objects + 1) {
						$objects++
						$expectLayout = $true
					}
				}
			}

			Require (!$expectLayout -and $objects -gt 0 -and $objects -le 262144) 'Complete bounded object graph'
		}

		Require ([long]$setup[0].artifact_bytes -eq $artifactBytes -and [int]$setup[0].files -eq $count -and [int]$setup[0].deep_oracles -eq $count) 'Setup/artifact/oracle totals'

		for ($trial = 0; $trial -lt 21; $trial++) {
			for ($order = 0; $order -lt 3; $order++) {
				$row = $rows[$trial * 3 + $order]
				$expected = @('FRESH', 'RESIDENT', 'AST_RELOAD')[($trial + $order) % 3]
				Require ($row.mode -ceq $expected -and [int]$row.trial -eq $trial -and [int]$row.order -eq $order) 'Rotating mode order'
				Require ([long]$row.source_bytes -eq [long]$project.source_bytes -and [long]$row.artifact_bytes -eq $(if ($expected -ceq 'AST_RELOAD') { $artifactBytes } else { 0 })) 'Source/artifact I-O totals'
				Require ([int]$row.parses -eq $(if ($expected -ceq 'FRESH') { $count } else { 0 }) -and [int]$row.hits -eq $(if ($expected -ceq 'RESIDENT') { $count } else { 0 }) -and [int]$row.loads -eq $(if ($expected -ceq 'AST_RELOAD') { $count } else { 0 })) 'Actual parse/hit/decode counts'
				Require ([long]$row.tokens -eq [long]$rows[0].tokens -and [long]$row.diagnostics -eq [long]$rows[0].diagnostics) 'Reload observable consistency'
				$phases = [long]$row.read_ns + [long]$row.hash_ns + [long]$row.decode_ns + [long]$row.parse_ns + [long]$row.cleanup_ns
				Require ($phases -le [long]$row.elapsed_ns -and [long]$row.elapsed_ns -gt 0) 'Nonoverlapping phase clocks'
			}
		}

		foreach ($modeName in @('FRESH', 'RESIDENT', 'AST_RELOAD')) {
			$times = @($rows | Where-Object mode -CEQ $modeName | ForEach-Object { [double]$_.elapsed_ns / 1000000 } | Sort-Object)
			Require ($times.Count -eq 21) 'Timing group size'
			$summary.Add([ordered]@{ project = $project.name; mode = $modeName; files = $count; source_bytes = $project.source_bytes; artifact_bytes = $artifactBytes; median_ms = $times[10]; p95_ms = $times[19]; min_ms = $times[0]; max_ms = $times[20] })
		}
	}

	$followupPath = Join-Path $root 'checks.json'
	if ([IO.File]::Exists($followupPath)) {
		$followup = [IO.File]::ReadAllText($followupPath) | ConvertFrom-Json -AsHashtable
		Require ($followup.rejected -eq 11 -and $followup.valid_control.Contains('E12_DECODE_PROBE_PASS')) 'Saved valid/rejected controls'
		$profiles = @($followup.results | Where-Object { $_.kind -ceq 'profile' })
		$rejections = @($followup.results | Where-Object { $_.kind -ceq 'rejection' })
		Require ($profiles.Count -eq 5 -and $rejections.Count -eq 11) 'Saved follow-up counts'
		foreach ($rejection in $rejections) {
			Require ($rejection.exit_code -ne 0 -and $rejection.output.Contains('E12_DECODE_PROBE') -and $rejection.output.Contains('Assertion failed') -and !$rejection.output.Contains('E12_DECODE_PROBE_PASS') -and [IO.File]::Exists($rejection.artifact)) 'Saved decoder rejection evidence'
		}

		foreach ($project in $projects) {
			$memory = @(Import-Csv "$($project.graph_prefix).memory.tsv" -Delimiter "`t")
			Require ($memory.Count -eq 6) 'Saved backing phase counts'
			foreach ($modeName in @('FRESH', 'AST_RELOAD')) {
				$phases = @($memory | Where-Object mode -CEQ $modeName)
				Require ($phases.Count -eq 3 -and [int]$phases[0].snapshots -eq $project.files.Count -and [int]$phases[1].snapshots -eq $project.files.Count + 2 -and [long]$phases[1].backing_bytes -gt [long]$phases[0].backing_bytes -and [long]$phases[2].backing_bytes -eq 0 -and [long]$phases[2].peak_bytes -ge [long]$phases[1].backing_bytes) 'Saved backing/retention/teardown totals'
			}
		}
	}

	foreach ($file in Get-ChildItem $root -Recurse -File) {
		$bytes = [IO.File]::ReadAllBytes($file.FullName)
		Require ($bytes.Length -gt 0 -and $bytes[-1] -eq 10) 'Evidence final newline'
	}

	WriteJson (Join-Path $root 'audit_summary.json') ([ordered]@{ checks = $Checks; projects = $projects.Count; source_files = $totalFiles; deep_corpus_oracles = $totalFiles; requests = $projects.Count * 63; stats = @($summary); limits = @('Same-layout LE64 read-only snapshots', 'Trusted authored reader, not a production hostile-input contract', 'No semantic queries, OS-cold filesystem or restart performance measured') })
	Write-Output "Graph codec audit: $Checks checks, $totalFiles source/artifact pairs, $($projects.Count * 63) timed requests."
	foreach ($row in $summary) {
		Write-Output ("{0} {1}: median {2:F3} ms, p95 {3:F3} ms, {4} AST bytes" -f $row.project, $row.mode, $row.median_ms, $row.p95_ms, $row.artifact_bytes)
	}
}

function Reframe([string[]] $lines) {
	$body = $lines[3..($lines.Length - 1)] -join "`n"
	$bytes = $Utf8.GetBytes($body)
	$digest = [E12GraphHash]::Fnv($bytes)
	$lines[2] = "H $($bytes.Length) $($digest -shr 32) $($digest -band 4294967295)"
	return $lines -join "`n"
}

function Check([string] $root) {
	InitializeHash
	$projects = @([IO.File]::ReadAllText((Join-Path $root 'projects.json')) | ConvertFrom-Json -AsHashtable)
	$results = [Collections.Generic.List[object]]::new()
	foreach ($project in $projects) {
		$output = InvokeWorker @($project.manifest, $project.graph_prefix, 'profile')
		$memory = @(Import-Csv "$($project.graph_prefix).memory.tsv" -Delimiter "`t")
		Require ($memory.Count -eq 6) 'Fresh/decoded memory row count'
		foreach ($modeName in @('FRESH', 'AST_RELOAD')) {
			$rows = @($memory | Where-Object mode -CEQ $modeName)
			Require ($rows.Count -eq 3 -and $rows[0].phase -ceq 'resident' -and [int]$rows[0].snapshots -eq $project.files.Count -and [long]$rows[0].backing_bytes -gt 0) 'Resident backing profile'
			Require ($rows[1].phase -ceq 'two_extra' -and [int]$rows[1].snapshots -eq $project.files.Count + 2 -and [long]$rows[1].backing_bytes -gt [long]$rows[0].backing_bytes) 'Retained backing profile'
			Require ($rows[2].phase -ceq 'released' -and [long]$rows[2].backing_bytes -eq 0 -and [long]$rows[2].peak_bytes -ge [long]$rows[1].backing_bytes) 'Tracked zero teardown'
		}

		$results.Add([ordered]@{ kind = 'profile'; project = $project.name; output = $output; rows = $memory })
	}

	$project = $projects[0]
	$source = $project.files[0].path
	$artifact = "$($project.graph_prefix).0.ast"
	$control = InvokeWorker @('verify', $source, $artifact)
	Require ($control.Contains('E12_DECODE_PROBE_PASS')) 'Valid artifact control must pass'
	$base = [IO.File]::ReadAllText($artifact).Split("`n")
	$faults = [Collections.Generic.List[object]]::new()
	$lines = $base.Clone(); $lines[0] = '[15]'
	$faults.Add([ordered]@{ name = 'VERSION'; text = $lines -join "`n" })
	$lines = $base.Clone(); $words = $lines[1] -split ' '; $lines[1] = "K $($words[1]) $(([long]$words[2]) -bxor 1)"
	$faults.Add([ordered]@{ name = 'SCHEMA'; text = $lines -join "`n" })
	$lines = $base.Clone(); $words = $lines[2] -split ' '; $lines[2] = "H $($words[1]) $($words[2]) $(([long]$words[3]) -bxor 1)"
	$faults.Add([ordered]@{ name = 'CHECKSUM'; text = $lines -join "`n" })
	$faults.Add([ordered]@{ name = 'TRUNCATED'; text = ($base[0..($base.Length - 3)] -join "`n") + "`n" })
	$lines = @($base[0..($base.Length - 2)]) + @('S 0 ', '')
	$faults.Add([ordered]@{ name = 'TRAILING_RECORD'; text = Reframe $lines })
	$lines = $base.Clone(); $lines[3] = 'B' + $lines[3].Substring(1)
	$faults.Add([ordered]@{ name = 'ROOT_TAG'; text = Reframe $lines })
	foreach ($kind in @('ARRAY_BOUND', 'DANGLING_ID', 'LAYOUT_BOUND')) {
		$lines = $base.Clone()
		$tag = switch ($kind) { 'ARRAY_BOUND' { 'A ' } 'DANGLING_ID' { 'P ' } 'LAYOUT_BOUND' { 'N ' } }
		$found = $false
		for ($index = 3; $index -lt $lines.Length - 1; $index++) {
			if ($lines[$index].StartsWith($tag) -and $lines[$index] -cne 'P 0') {
				$lines[$index] = $tag + $(if ($kind -ceq 'ARRAY_BOUND') { '1048577' } else { '262145' })
				$found = $true
				break
			}
		}

		Require $found "Missing discriminating record: $kind"
		$faults.Add([ordered]@{ name = $kind; text = Reframe $lines })
	}

	foreach ($kind in @('SOURCE_CONTEXT', 'FILENAME_CONTEXT')) {
		$lines = $base.Clone()
		$index = if ($kind -ceq 'SOURCE_CONTEXT') { 3 } else { 4 }
		$parts = $lines[$index] -split ' ', 3
		$bytes = [Convert]::FromHexString($parts[2]); $bytes[0] = $bytes[0] -bxor 1
		$lines[$index] = "S $($parts[1]) $([Convert]::ToHexString($bytes))"
		$faults.Add([ordered]@{ name = $kind; text = Reframe $lines })
	}

	$directory = Join-Path $root "checks_$([Guid]::NewGuid().ToString('N'))"
	[IO.Directory]::CreateDirectory($directory) > $null
	foreach ($fault in $faults) {
		$path = Join-Path $directory "$($fault.name).ast"
		[IO.File]::WriteAllText($path, $fault.text, $Utf8)
		$output = InvokeWorker @('verify', $source, $path) $true
		$results.Add([ordered]@{ kind = 'rejection'; name = $fault.name; artifact = $path; exit_code = $LastWorkerExitCode; output = $output })
	}

	WriteJson (Join-Path $root 'checks.json') ([ordered]@{ checks = $Checks; valid_control = $control; rejected = $faults.Count; worker_sha256 = Digest $Worker; source_sha256 = Digest (Join-Path $PSScriptRoot 'experiment_snapshot_codec.jai'); results = @($results) })
	Write-Output "Graph codec follow-up: $Checks checks; 5 fresh/decoded backing profiles, zero tracked teardown, valid control and $($faults.Count) assertion-rejected artifacts."
}

if ($Mode -ceq 'Audit') {
	Require (!!$RunDirectory) 'Provide -RunDirectory for Audit'
	Audit ([IO.Path]::GetFullPath($RunDirectory))
} elseif ($Mode -ceq 'Check') {
	Require (!!$RunDirectory) 'Provide -RunDirectory for Check'
	Check ([IO.Path]::GetFullPath($RunDirectory))
} else {
	Require ([IO.File]::Exists($Worker)) 'Build the LLVM graph codec worker first'
	$root = Join-Path $PSScriptRoot ".build/snapshot_codec/$([Guid]::NewGuid().ToString('N'))"
	[IO.Directory]::CreateDirectory($root) > $null
	$projects = @([IO.File]::ReadAllText((Join-Path $BaselineDirectory 'projects.json')) | ConvertFrom-Json -AsHashtable)
	$outputs = [Collections.Generic.List[object]]::new()
	$outputs.Add([ordered]@{ kind = 'fixtures'; output = InvokeWorker @() })

	foreach ($project in $projects) {
		foreach ($file in $project.files) {
			Require ((Digest $file.path) -ceq $file.sha256) 'Baseline source changed before measurement'
		}

		$project.graph_prefix = Join-Path $root $project.name
		Write-Output "Graph codec measuring $($project.name): $($project.files.Count) files"
		$result = InvokeWorker @($project.manifest, $project.graph_prefix)
		$outputs.Add([ordered]@{ kind = 'project'; project = $project.name; output = $result })
		Write-Output $result.Trim()
	}

	WriteJson (Join-Path $root 'projects.json') $projects
	WriteJson (Join-Path $root 'workers.json') $outputs
	WriteJson (Join-Path $root 'provenance.json') ([ordered]@{
		worker_sha256 = Digest $Worker; source_sha256 = Digest (Join-Path $PSScriptRoot 'experiment_snapshot_codec.jai'); oracle_sha256 = Digest (Join-Path $PSScriptRoot 'snapshot_oracle.jai')
		compiler_sha256 = Digest (Join-Path $PSScriptRoot '../../../bin/jai.exe'); build_flags = '-o -llvm -quiet -no_color'
		powershell = $PSVersionTable.PSVersion.ToString(); runtime = [Runtime.InteropServices.RuntimeInformation]::FrameworkDescription; os = [Runtime.InteropServices.RuntimeInformation]::OSDescription
		filesystem = [IO.DriveInfo]::new([IO.Path]::GetPathRoot($root)).DriveFormat; baseline_directory = [IO.Path]::GetFullPath($BaselineDirectory)
	})
	Audit $root
	Write-Output "Graph codec evidence: $root"
}
