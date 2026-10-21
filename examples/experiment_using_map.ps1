param(
	[ValidateSet('Run', 'Audit')]
	[string] $Mode = 'Run',
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

function WriteText([string] $path, [string] $text) {
	[IO.File]::WriteAllText($path, $text.Replace("`r`n", "`n").TrimEnd("`n") + "`n", $Utf8)
}

function WriteJson([string] $path, $value) {
	WriteText $path ($value | ConvertTo-Json -Depth 16)
}

function ReadFrame([string] $text, [string] $request, [string[]] $original) {
	$lines = @($text.Replace("`r`n", "`n").Split("`n") | Where-Object { $_.StartsWith('E13_') })
	Require ($lines.Count -eq $original.Count + 2) 'Frame cardinality'
	Require ($lines[0] -ceq "E13_BEGIN $request $($original.Count)") 'Frame begin/request'
	Require ($lines[-1] -ceq "E13_END $request") 'Frame end/request'
	$result = [Collections.Generic.List[string]]::new()
	$seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
	for ($index = 0; $index -lt $original.Count; $index++) {
		$fields = $lines[$index + 1].Split(' ')
		Require ($fields.Count -ge 4 -and $fields[0] -ceq 'E13_ROW' -and $fields[1] -ceq $request -and $fields[2] -ceq "$index") 'Frame positional slot'
		$length = 0
		Require ([int]::TryParse($fields[3], [ref]$length) -and $length -ge 0 -and $length -le 256 -and $fields.Count -eq 4 + $length) 'Frame byte length/bound'
		$bytes = [byte[]]::new($length)
		for ($offset = 0; $offset -lt $length; $offset++) {
			$value = 0
			Require ([byte]::TryParse($fields[$offset + 4], [ref]$value)) 'Frame byte value'
			$bytes[$offset] = $value
		}

		$name = $Utf8.GetString($bytes)
		Require ($name -ceq '' -or $name -cmatch '^[A-Za-z_][A-Za-z_0-9]*$') 'Supported ASCII identifier'
		if ($name -cne '') {
			Require ($seen.Add($name)) 'Mapped-name collision'
		}

		$result.Add($name)
	}

	return ,$result.ToArray()
}

function Compile([string] $directory, [string] $diagnostic = '') {
	$info = [Diagnostics.ProcessStartInfo]::new('jai')
	$info.WorkingDirectory = $directory
	$info.UseShellExecute = $false
	$info.RedirectStandardOutput = $true
	$info.RedirectStandardError = $true
	foreach ($argument in @('probe.jai', '-x64', '-quiet', '-no_color')) {
		$info.ArgumentList.Add($argument)
	}

	$process = [Diagnostics.Process]::Start($info)
	try {
		$output = $process.StandardOutput.ReadToEndAsync()
		$errors = $process.StandardError.ReadToEndAsync()
		if (!$process.WaitForExit(30000)) {
			$process.Kill($true)
			$process.WaitForExit()
			throw 'Authored mapping probe exceeded 30 seconds'
		}

		$text = $output.GetAwaiter().GetResult() + "`n" + $errors.GetAwaiter().GetResult()
		Require ($text.Length -le 1048576) 'Captured output bound (post-capture)'
		WriteText (Join-Path $directory 'compiler.log') $text
		$script:LastExitCode = $process.ExitCode
		if ($diagnostic -ceq '') {
			Require ($process.ExitCode -eq 0) "Mapping compiler failed: $text"
		} else {
			Require ($process.ExitCode -eq 1 -and $text.Contains($diagnostic)) "Expected authored compiler rejection ($diagnostic): $text"
		}

		return $text
	} finally {
		$process.Dispose()
	}
}

$Module = @'
#module_parameters(PREFIX: string, REQUEST: string, EXCLUDE: bool, POLICY: string);

#scope_export

#import "Basic";

rename :: (names: []string) {
	print("E13_BEGIN % %\n", REQUEST, names.count);
	for *name, index: names {
		if EXCLUDE && name.* == "right" {
			name.* = "";
		} else {
			name.* = decorate(name.*);
		}

		if POLICY == "collision" {
			name.* = "same";
		}

		if POLICY == "invalid" {
			name.* = tprint("not-%", index);
		}

		print("E13_ROW % % %", REQUEST, index, name.count);
		for byte: name.* {
			print(" %", byte);
		}

		print("\n");
	}

	print("E13_END %\n", REQUEST);
}

#scope_file

decorate :: (name: string) -> string {
	return tprint("%%", PREFIX, name);
}
'@

function Run {
	$root = Join-Path $PSScriptRoot ('.build/using_map/' + [guid]::NewGuid().ToString('N'))
	[IO.Directory]::CreateDirectory($root) | Out-Null
	$records = [Collections.Generic.List[object]]::new()
	$cases = [Collections.Generic.List[object]]::new()
	foreach ($prefix in @('mapped_', 'alpha_', 'beta_')) {
		foreach ($exclude in @($false, $true)) {
			foreach ($kind in @('actual', 'wrapper')) {
				$cases.Add(@{ name="$prefix$kind-$exclude"; prefix=$prefix; exclude=$exclude; kind=$kind; policy='normal'; diagnostic=''; reject_frame=$false })
			}
		}
	}

	foreach ($policy in @('collision', 'invalid')) {
		foreach ($kind in @('actual', 'wrapper')) {
			$diagnostic = if ($kind -ceq 'actual' -and $policy -ceq 'collision') { "Redeclaration of 'same'" } else { '' }
			$cases.Add(@{ name="$kind-$policy"; prefix='mapped_'; exclude=$false; kind=$kind; policy=$policy; diagnostic=$diagnostic; reject_frame=($kind -ceq 'wrapper' -or $policy -ceq 'invalid') })
		}
	}

	$cases.Add(@{ name='excluded-alias'; prefix='mapped_'; exclude=$true; kind='excluded-alias'; policy='normal'; diagnostic="Undeclared identifier 'mapped_right'"; reject_frame=$false })
	$cases.Add(@{ name='missing-context'; prefix='mapped_'; exclude=$false; kind='missing-context'; policy='normal'; diagnostic="Undeclared identifier 'decorate'"; reject_frame=$false })
	foreach ($case in $cases) {
		$name = $case.name
		$directory = Join-Path $root $name
		[IO.Directory]::CreateDirectory($directory) | Out-Null
		$request = [guid]::NewGuid().ToString('N')
		$flag = "$($case.exclude)".ToLowerInvariant()
		$prefix = $case.prefix
		$body = if ($case.kind -in @('actual', 'excluded-alias')) {
			$left = "${prefix}left"
			$right = if ($case.exclude -and $case.kind -cne 'excluded-alias') { 'pair.right' } else { "${prefix}right" }
			$use = if ($case.policy -ceq 'normal') { "$left = 17; $right = 25; assert(pair.left + pair.right == 42);" } else { '' }
			@"
Pair :: struct {
	left: s64;
	right: s64;
}

test :: () {
	using,map(Mapping.rename) pair: Pair;
	$use
}

#run test();
"@
		} else {
				@'
Pair :: struct { left: s64; right: s64; }
#run {
	info := type_info(Pair);
	names: [..]string;
	for member: info.members {
		array_add(*names, member.name);
	}

	Mapping.rename(names);
	assert(names.count == 2);
}
'@
		}

		$moduleSource = if ($case.kind -ceq 'missing-context') { $Module.Substring(0, $Module.IndexOf('#scope_file')) } else { $Module }
		WriteText "$directory/mapping.jai" $moduleSource
		WriteText "$directory/probe.jai" @"
#import "Basic";
#import "Compiler";
#run set_build_options_dc(.{do_output=false, write_added_strings=false});
Mapping :: #import,file "mapping.jai"(PREFIX="$prefix", REQUEST="$request", EXCLUDE=$flag, POLICY="$($case.policy)");
$body
"@
		$text = Compile $directory $case.diagnostic
		$result = @()
		if ($case.diagnostic -ceq '') {
			if ($case.reject_frame) {
				ExpectReject { ReadFrame $text $request @('left', 'right') } "Wrapper $($case.policy)"
			} else {
				$result = ReadFrame $text $request @('left', 'right')
				$expected = @("${prefix}left", $(if ($case.exclude) { '' } else { "${prefix}right" }))
				Require (($result | ConvertTo-Json -Compress) -ceq ($expected | ConvertTo-Json -Compress)) 'Exact authored mapping result'
			}
		}

		$hashes = @{}
		foreach ($file in @('probe.jai', 'mapping.jai', 'compiler.log')) {
			$hashes[$file] = (Get-FileHash "$directory/$file" -Algorithm SHA256).Hash
		}

		$records.Add(@{ name=$name; request=$request; original=@('left', 'right'); result=$result; directory=$directory; case=$case; exit_code=$script:LastExitCode; sha256=$hashes })
	}

	WriteJson "$root/records.json" $records.ToArray()
	$compiler = (Get-Command jai).Source
	WriteJson "$root/provenance.json" @{ runner_sha256=(Get-FileHash $PSCommandPath -Algorithm SHA256).Hash; compiler=$compiler; compiler_sha256=(Get-FileHash $compiler -Algorithm SHA256).Hash; powershell="$($PSVersionTable.PSVersion)"; os=[Environment]::OSVersion.VersionString; flags=@('-x64', '-quiet', '-no_color'); trusted_authored_only=$true }
	Audit $root
	Write-Host "E13 evidence: $root"
}

function Audit([string] $root) {
	$records = @([IO.File]::ReadAllText("$root/records.json", $Utf8) | ConvertFrom-Json -AsHashtable)
	Require ($records.Count -eq 18) 'Eighteen authored compiler probes'
	$published = @{}
	foreach ($record in $records) {
		foreach ($file in @('probe.jai', 'mapping.jai', 'compiler.log')) {
			Require ((Get-FileHash "$($record.directory)/$file" -Algorithm SHA256).Hash -ceq $record.sha256[$file]) 'Authored input/log SHA256'
		}

		$text = [IO.File]::ReadAllText("$($record.directory)/compiler.log", $Utf8)
		if ($record.case.diagnostic -cne '') {
			Require ($record.exit_code -eq 1 -and $text.Contains($record.case.diagnostic) -and $record.result.Count -eq 0) 'Failed compilation never publishes a result'
		} elseif ($record.case.reject_frame) {
			Require ($record.exit_code -eq 0 -and $record.result.Count -eq 0) 'Invalid wrapper output never published'
			ExpectReject { ReadFrame $text $record.request $record.original } "Saved wrapper $($record.case.policy)"
		} else {
			Require ($record.exit_code -eq 0) 'Successful compilation required before decode'
			$result = ReadFrame $text $record.request $record.original
			$expected = @("$($record.case.prefix)left", $(if ($record.case.exclude) { '' } else { "$($record.case.prefix)right" }))
			Require (($result | ConvertTo-Json -Compress) -ceq ($expected | ConvertTo-Json -Compress)) 'Independent authored expected result'
			Require (($result | ConvertTo-Json -Compress) -ceq ($record.result | ConvertTo-Json -Compress)) 'Decoded host-owned result after compiler teardown'
			$published[$record.name] = $result
		}
	}

	foreach ($prefix in @('mapped_', 'alpha_', 'beta_')) {
		foreach ($exclude in @($false, $true)) {
			Require (($published["${prefix}actual-$exclude"] | ConvertTo-Json -Compress) -ceq ($published["${prefix}wrapper-$exclude"] | ConvertTo-Json -Compress)) 'Actual compiler mapping equals generated-array wrapper'
		}
	}

	$control = $records[0]
	$frame = [IO.File]::ReadAllText("$($control.directory)/compiler.log", $Utf8)
	TestFrames $frame $control.request
	$native = @(Get-ChildItem $root -Recurse -File | Where-Object { $_.Extension -in @('.exe', '.obj', '.pdb', '.dll', '.lib') })
	Require ($native.Count -eq 0) 'No native output'

	WriteJson "$root/audit_summary.json" @{ checks=$script:Checks; compilations=$records.Count; successful_compilations=15; expected_compiler_rejections=3; published=12; paired_comparisons=6; frame_controls=12; result='PASS' }
	Write-Host "E13 mapping audit PASS: $script:Checks checks"
}

function ExpectReject([scriptblock] $action, [string] $name) {
	$rejected = $false
	try {
		$null = & $action
	} catch {
		$rejected = $true
	}

	Require $rejected "Negative control accepted: $name"
}

function TestFrames([string] $frame, [string] $request) {
	$lines = @($frame.Replace("`r`n", "`n").Split("`n") | Where-Object { $_.StartsWith('E13_') })
	Require ($lines.Count -eq 4) 'Control frame shape'
	$mutations = @(
		@{ name='request'; text=$frame.Replace($request, 'stale') },
		@{ name='truncation'; text=($lines[0..2] -join "`n") },
		@{ name='missing-slot'; text=(@($lines[0], $lines[1], $lines[3]) -join "`n") },
		@{ name='duplicate-slot'; text=(@($lines[0], $lines[1], $lines[1], $lines[3]) -join "`n") },
		@{ name='reordered-slots'; text=(@($lines[0], $lines[2], $lines[1], $lines[3]) -join "`n") },
		@{ name='extra-frame'; text=($frame + "`n" + $lines[0]) },
		@{ name='length-bound'; text=(@($lines[0], "E13_ROW $request 0 257", $lines[2], $lines[3]) -join "`n") },
		@{ name='byte-bound'; text=(@($lines[0], "E13_ROW $request 0 1 256", $lines[2], $lines[3]) -join "`n") },
		@{ name='invalid-utf8'; text=(@($lines[0], "E13_ROW $request 0 1 255", $lines[2], $lines[3]) -join "`n") },
		@{ name='payload-newline'; text=(@($lines[0], "E13_ROW $request 0 1 10", $lines[2], $lines[3]) -join "`n") },
		@{ name='truncated-bytes'; text=(@($lines[0], "E13_ROW $request 0 2 65", $lines[2], $lines[3]) -join "`n") },
		@{ name='collision'; text=(@($lines[0], $lines[1], $lines[1].Replace("ROW $request 0 ", "ROW $request 1 "), $lines[3]) -join "`n") }
	)

	foreach ($mutation in $mutations) {
		ExpectReject { ReadFrame $mutation.text $request @('left', 'right') } $mutation.name
	}

	$owned = ReadFrame $frame $request @('left', 'right')
	$frame = 'input buffer replaced after decode'
	$lines = @()
	Require ($owned[0] -ceq 'mapped_left' -and $owned[1] -ceq 'mapped_right') 'Result survives input replacement and process disposal'
}

if ($Mode -ceq 'Run') {
	Run
} else {
	Require ($RunDirectory -cne '') 'Audit requires RunDirectory'
	Audit ([IO.Path]::GetFullPath($RunDirectory))
}
