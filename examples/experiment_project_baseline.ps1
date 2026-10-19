param(
	[ValidateSet('Run', 'Audit')]
	[string] $Mode = 'Run',
	[string] $Worker = (Join-Path $PSScriptRoot '.build/experiment_project_baseline_llvm.exe'),
	[string] $OutputDirectory = (Join-Path $PSScriptRoot '.build/project_baseline'),
	[string] $RunDirectory = ''
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

function HashBytes([byte[]] $bytes) {
	return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
}

function InvokeWorker([string[]] $arguments) {
	$info = [Diagnostics.ProcessStartInfo]::new([IO.Path]::GetFullPath($Worker))
	$info.UseShellExecute = $false
	$info.RedirectStandardOutput = $true
	$info.RedirectStandardError = $true
	foreach ($argument in $arguments) {
		$info.ArgumentList.Add($argument)
	}

	$watch = [Diagnostics.Stopwatch]::StartNew()
	$process = [Diagnostics.Process]::Start($info)
	try {
		$output = $process.StandardOutput.ReadToEndAsync()
		$errors = $process.StandardError.ReadToEndAsync()
		if (!$process.WaitForExit(120000)) {
			$process.Kill($true)
			$process.WaitForExit()
			throw 'E12 worker exceeded its two-minute bound'
		}


		$watch.Stop()
		Require ($process.ExitCode -eq 0) "E12 worker failed: $($errors.GetAwaiter().GetResult()) $($output.GetAwaiter().GetResult())"
		return [ordered]@{ output = $output.GetAwaiter().GetResult(); wall_ms = $watch.Elapsed.TotalMilliseconds; exit_code = $process.ExitCode }
	} finally {
		$process.Dispose()
	}
}

function MakeProject([string] $root, [string] $name, $files, [string] $description) {
	$files = @($files | Sort-Object @{ Expression = 'Length'; Descending = $true }, FullName)
	Require ($files.Count -gt 0 -and $files.Count -le 64) "Project file bound: $name"
	Require (($files | Measure-Object Length -Sum).Sum -le 2097152) "Project byte bound: $name"
	$manifest = Join-Path $root "$name.files"
	$records = [Collections.Generic.List[object]]::new()

	foreach ($file in $files) {
		Require ($file.Length -le 524288) "Source byte bound: $($file.FullName)"
		$bytes = [IO.File]::ReadAllBytes($file.FullName)
		$records.Add([ordered]@{ path = $file.FullName.Replace('\', '/'); bytes = $bytes.Length; sha256 = HashBytes $bytes })
	}

	[IO.File]::WriteAllText($manifest, (($records | ForEach-Object { $_.path }) -join "`n") + "`n", $Utf8)
	return [ordered]@{ name = $name; description = $description; manifest = $manifest; prefix = (Join-Path $root $name); files = @($records); source_bytes = ($records | ForEach-Object { [long]$_.bytes } | Measure-Object -Sum).Sum }
}

function RunBaseline([string] $root) {
	Require ([IO.File]::Exists($Worker)) 'Build experiment_project_baseline.jai with LLVM first'
	[IO.Directory]::CreateDirectory($root) > $null
	$distribution = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
	$parser = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
	$chain = Join-Path $root 'authored_modules'
	foreach ($name in @('E12_Root', 'E12_Middle', 'E12_Leaf')) {
		[IO.Directory]::CreateDirectory((Join-Path $chain $name)) > $null
	}

	[IO.File]::WriteAllText((Join-Path $chain 'E12_Root/module.jai'), "Middle :: #import `"E12_Middle`";`nmain :: () { value := Middle.Middle_value; }`n", $Utf8)
	[IO.File]::WriteAllText((Join-Path $chain 'E12_Middle/module.jai'), "Leaf :: #import `"E12_Leaf`";`nMiddle_value :: Leaf.Leaf_value + 1;`n", $Utf8)
	$leaf = "Leaf_value :: 1;`n"
	for ($index = 0; $index -lt 64; $index++) {
		$leaf += "value_$index :: $index;`n"
	}

	[IO.File]::WriteAllText((Join-Path $chain 'E12_Leaf/module.jai'), $leaf, $Utf8)
	$projects = @(
		(MakeProject $root 'tutorials' (Get-ChildItem "$distribution/how_to" -File -Filter '*.jai') 'All top-level tutorial sources; many small files'),
		(MakeProject $root 'invaders' (Get-ChildItem "$distribution/examples/invaders" -Recurse -File -Filter '*.jai') 'Real application source inventory; imported SDK closure is not inferred'),
		(MakeProject $root 'parser' (Get-ChildItem $parser -File -Filter '*.jai') 'Parser implementation; large active source'),
		(MakeProject $root 'basic' (Get-ChildItem "$distribution/modules/Basic" -File -Filter '*.jai') 'Basic module source inventory; cross-module instance semantics are not evaluated'),
		(MakeProject $root 'import_chain' (Get-ChildItem $chain -Recurse -File -Filter '*.jai') 'Authored Root -> Middle -> Leaf syntax workload; no semantic resolver fan-out measurement')
	)

	$workers = [Collections.Generic.List[object]]::new()

	foreach ($project in $projects) {
		Write-Output "E12 measuring $($project.name): $($project.files.Count) files, $($project.source_bytes) source bytes"
		$result = InvokeWorker @($project.manifest, $project.prefix)
		$workers.Add([ordered]@{ project = $project.name; kind = 'project'; result = $result })
		Write-Output $result.output.Trim()
		for ($trial = 0; $trial -lt 3; $trial++) {
			$result = InvokeWorker @($project.manifest, $project.prefix, 'restart')
			$workers.Add([ordered]@{ project = $project.name; kind = 'restart'; trial = $trial; result = $result })
		}
	}

	WriteJson (Join-Path $root 'projects.json') $projects
	WriteJson (Join-Path $root 'workers.json') $workers
	WriteJson (Join-Path $root 'provenance.json') ([ordered]@{
		worker = [IO.Path]::GetFullPath($Worker); worker_sha256 = HashBytes ([IO.File]::ReadAllBytes($Worker))
		worker_source_sha256 = HashBytes ([IO.File]::ReadAllBytes((Join-Path $PSScriptRoot 'experiment_project_baseline.jai')))
		powershell = $PSVersionTable.PSVersion.ToString(); runtime = [Runtime.InteropServices.RuntimeInformation]::FrameworkDescription
		os = [Runtime.InteropServices.RuntimeInformation]::OSDescription; filesystem = [IO.DriveInfo]::new([IO.Path]::GetPathRoot($root)).DriveFormat
		process_restart = 'fresh worker; filesystem cache not flushed'; modes = @('FRESH', 'RESIDENT', 'TEXT_SOURCE_REPARSE')
	})
}

function AuditBaseline([string] $root) {
	Add-Type -TypeDefinition @'
public static class E12ContentHash {
    public static ulong Fnv(byte[] bytes) {
        ulong result = 0xCBF29CE484222325UL;
        foreach (byte value in bytes) {
            result = unchecked((result ^ value) * 0x100000001B3UL);
        }
        return result;
    }
}
'@
	$projects = @([IO.File]::ReadAllText((Join-Path $root 'projects.json')) | ConvertFrom-Json -AsHashtable)
	$workers = @([IO.File]::ReadAllText((Join-Path $root 'workers.json')) | ConvertFrom-Json -AsHashtable)
	Require ($projects.Count -eq 5 -and $workers.Count -eq 20) 'Project/worker counts'
	$summary = [Collections.Generic.List[object]]::new()
	$editSummary = [Collections.Generic.List[object]]::new()
	$restartSummary = [Collections.Generic.List[object]]::new()
	$totalFiles = 0
	$totalOracles = 0

	foreach ($project in $projects) {
		$count = $project.files.Count
		$totalFiles += $count
		$artifactBytes = 0

		for ($index = 0; $index -lt $count; $index++) {
			$file = $project.files[$index]
			$source = [IO.File]::ReadAllBytes($file.path)
			Require ($source.Length -eq $file.bytes -and (HashBytes $source) -ceq $file.sha256) 'Input changed after measurement'
			$text = [IO.File]::ReadAllText("$($project.prefix).$index.source")
			$artifactBytes += $Utf8.GetByteCount($text)
			$lines = $text.Split("`n")
			Require ($lines[0] -ceq '[12]' -and $lines[-1] -ceq '') 'Envelope version/newline'
			$header = $lines[1] -split ' '
			Require ($header.Count -eq 3 -and [long]$header[0] -eq $source.Length) 'Envelope length'
			$hex = ($lines[2..($lines.Length - 1)] -join '')
			$decoded = [Convert]::FromHexString($hex)
			$storedHash = [ulong]([bigint]::Parse($header[1]) * 4294967296 + [bigint]::Parse($header[2]))
			Require ([Convert]::ToHexString($decoded) -ceq [Convert]::ToHexString($source) -and [E12ContentHash]::Fnv($decoded) -eq $storedHash) 'Independent source/hash oracle'
		}

		$raw = @(Import-Csv "$($project.prefix).timings.tsv" -Delimiter "`t")
		$memory = @(Import-Csv "$($project.prefix).memory.tsv" -Delimiter "`t")
		$setup = @(Import-Csv "$($project.prefix).setup.tsv" -Delimiter "`t")
		$edits = @(Import-Csv "$($project.prefix).edits.tsv" -Delimiter "`t")
		Require ($raw.Count -eq 63 -and $memory.Count -eq 3 -and $setup.Count -eq 1 -and $edits.Count -eq 126) 'Saved row counts'
		Require ([long]$setup[0].artifact_bytes -eq $artifactBytes -and [int]$setup[0].files -eq $count -and [int]$setup[0].deep_oracles -eq $count + 178) 'Setup/oracle totals'
		$totalOracles += [int]$setup[0].deep_oracles

		foreach ($row in $raw) {
			$resident = $row.mode -ceq 'RESIDENT'
			$textMode = $row.mode -ceq 'TEXT_SOURCE_REPARSE'
			Require ([long]$row.elapsed_ns -gt 0 -and [long]$row.source_bytes -eq [long]$project.source_bytes) 'Timed source/I-O total'
			Require ([int]$row.parses -eq $(if ($resident) { 0 } else { $count }) -and [int]$row.hits -eq $(if ($resident) { $count } else { 0 })) 'Parse/reuse counts'
			Require ([long]$row.artifact_bytes -eq $(if ($textMode) { $artifactBytes } else { 0 })) 'Artifact I/O count'
			Require ([long]$row.tokens -eq [long]$raw[0].tokens -and [long]$row.diagnostics -eq [long]$raw[0].diagnostics) 'Observable summary differs'
			$parts = [long]$row.read_ns + [long]$row.hash_ns + [long]$row.decode_ns + [long]$row.parse_ns + [long]$row.cleanup_ns
			Require ($parts -le [long]$row.elapsed_ns) 'Overlapping phase accounting'
		}

		for ($trial = 0; $trial -lt 21; $trial++) {
			for ($order = 0; $order -lt 3; $order++) {
				$row = $raw[$trial * 3 + $order]
				$expected = @('FRESH', 'RESIDENT', 'TEXT_SOURCE_REPARSE')[($order + $trial) % 3]
				Require ([int]$row.trial -eq $trial -and [int]$row.order -eq $order -and $row.mode -ceq $expected) 'Rotating mode order'
			}
		}

		foreach ($modeName in @('FRESH', 'RESIDENT', 'TEXT_SOURCE_REPARSE')) {
			$rows = @($raw | Where-Object mode -CEQ $modeName)
			$times = @($rows | ForEach-Object { [double]$_.elapsed_ns / 1000000 } | Sort-Object)
			Require ($times.Count -eq 21) 'Timing group count'
			$summary.Add([ordered]@{ project = $project.name; mode = $modeName; files = $count; source_bytes = $project.source_bytes; artifact_bytes = $artifactBytes; median_ms = $times[10]; p95_ms = $times[19]; min_ms = $times[0]; max_ms = $times[20] })
		}

		Require ($memory[0].phase -ceq 'resident' -and [int]$memory[0].snapshots -eq $count -and [long]$memory[0].backing_bytes -gt 0) 'Resident profile'
		Require ([int]$memory[1].snapshots -eq $count + 2 -and [long]$memory[1].backing_bytes -gt [long]$memory[0].backing_bytes) 'Retained snapshot profile'
		Require ($memory[2].phase -ceq 'released' -and [long]$memory[2].backing_bytes -eq 0 -and [long]$memory[2].peak_bytes -ge [long]$memory[1].backing_bytes) 'Complete tracked teardown'

		foreach ($name in @('BODY_1', 'BODY_2', 'INTERFACE', 'LAYOUT', 'MALFORMED', 'REPAIR')) {
			$rows = @($edits | Where-Object edit -CEQ $name)
			$times = @($rows | ForEach-Object { [double]$_.elapsed_ns / 1000000 } | Sort-Object)
			Require ($rows.Count -eq 21 -and $times[0] -ge 0) 'Edit sample group'

			foreach ($row in $rows) {
				Require ([long]$row.source_bytes -gt [long]$project.files[0].bytes -and [int]$row.retained -eq $(if ($name -ceq 'BODY_1') { 1 } else { 2 })) 'Active source/retention counts'
				if ($name -ceq 'MALFORMED') {
					Require ([long]$row.diagnostics -gt 0) 'Malformed diagnostic oracle'
				}
			}

			$editSummary.Add([ordered]@{ project = $project.name; edit = $name; active_bytes = $project.files[0].bytes; median_ms = $times[10]; p95_ms = $times[19] })
		}

		$restarts = @($workers | Where-Object { $_.project -ceq $project.name -and $_.kind -ceq 'restart' })
		Require ($restarts.Count -eq 3) 'Fresh-process restart count'

		foreach ($restart in $restarts) {
			$fields = $restart.result.output.Trim() -split "`t"
			Require ($fields.Count -eq 7 -and $fields[0] -ceq 'E12_RESTART' -and [int]$fields[1] -eq $count -and [long]$fields[2] -eq [long]$project.source_bytes -and [long]$fields[3] -eq $artifactBytes -and [long]$fields[4] -eq [long]$raw[0].tokens -and [long]$fields[5] -eq [long]$raw[0].diagnostics) 'Restart validation totals'
			$workerMs = [double]$fields[6] / 1000000
			Require ($restart.result.exit_code -eq 0 -and [double]$restart.result.wall_ms -ge $workerMs) 'Process startup accounting'
			$restartSummary.Add([ordered]@{ project = $project.name; trial = $restart.trial; worker_ms = $workerMs; process_wall_ms = $restart.result.wall_ms; filesystem = 'warm/unflushed' })
		}
	}

	foreach ($file in Get-ChildItem $root -Recurse -File) {
		$bytes = [IO.File]::ReadAllBytes($file.FullName)
		Require ($bytes.Length -gt 0 -and $bytes[-1] -eq 10) "Final newline: $($file.FullName)"
	}

	foreach ($path in @($PSCommandPath, (Join-Path $PSScriptRoot 'experiment_project_baseline.jai'))) {
		Require ([IO.File]::ReadAllBytes($path)[-1] -eq 10) "Source final newline: $path"
	}

	$report = [ordered]@{
		checks = $Checks; projects = $projects.Count; source_files = $totalFiles; deep_snapshot_oracles = $totalOracles
		project_requests = $projects.Count * 63; timed_edits = $projects.Count * 126; restart_processes = 15
		project_stats = @($summary); edit_stats = @($editSummary); restart_stats = @($restartSummary)
		limitations = @('TEXT_SOURCE_REPARSE is not persisted AST reload', 'No semantic dependency fan-out or OS-cold cache measurement', 'Tracked requested backing is not OS residency', 'No approved numerical acceptance threshold')
	}

	WriteJson (Join-Path $root 'audit_summary.json') $report
	Write-Output "E12 audit: $Checks checks; $totalFiles sources, $totalOracles deep oracles, 315 timed project requests, 630 edits and 15 restart processes."
	$summary | ForEach-Object { Write-Output ("{0} {1}: median {2:F3} ms, p95 {3:F3} ms" -f $_.project, $_.mode, $_.median_ms, $_.p95_ms) }
}

if ($Mode -ceq 'Audit') {
	Require (!!$RunDirectory) 'Provide -RunDirectory for Audit'
	AuditBaseline ([IO.Path]::GetFullPath($RunDirectory))
} else {
	$root = Join-Path ([IO.Path]::GetFullPath($OutputDirectory)) ([Guid]::NewGuid().ToString('N'))
	RunBaseline $root
	AuditBaseline $root
	Write-Output "E12 evidence: $root"
}
