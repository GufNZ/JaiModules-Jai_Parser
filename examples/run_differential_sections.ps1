param(
	[ValidateNotNullOrEmpty()]
	[string[]]$Sections = @(),
	[ValidateRange(512, 1048576)]
	[long]$MemoryBudgetMiB = 2048,
	[ValidateRange(1, 3600)]
	[int]$TimeoutSeconds = 300,
	[string]$CompilerPath = (Join-Path $PSScriptRoot '../../../bin/jai.exe'),
	[switch]$ListSections,
	[switch]$AllSections,
	[ValidateRange(1, 2147483647)]
	[int]$BatchSize = 16,
	[ValidateRange(0, 2147483647)]
	[int]$FirstFixture = 0,
	[ValidateRange(0, 2147483647)]
	[int]$LastFixture = 0
)

$ErrorActionPreference = 'Stop'
if (!$IsWindows) {
	throw 'This runner requires Windows job limits and pwsh.'
}
if (($Sections.Count -and ($ListSections -or $AllSections)) -or ($ListSections -and $AllSections)) {
	throw 'Choose explicit Sections, ListSections, or AllSections, not a combination.'
}
if (!$Sections.Count -and !$ListSections -and !$AllSections) {
	throw 'Provide Sections, use ListSections, or explicitly request AllSections.'
}
if ($FirstFixture -or $LastFixture) {
	if ($Sections.Count -ne 1 -or $ListSections -or $AllSections -or $FirstFixture -lt 1 -or $LastFixture -lt $FirstFixture) {
		throw 'Fixture ranges require one explicit section and paired positive bounds.'
	}
}
foreach ($section in $Sections) {
	if ([string]::IsNullOrWhiteSpace($section) -or $section -in @('all', 'list')) {
		throw 'Provide individual section names or numbers; combined selection is not supported.'
	}
}

$pwshPath = Join-Path $PSHOME 'pwsh.exe'
$profilePath = Join-Path $PSScriptRoot 'profile_differential_memory.ps1'
$inventoryOutput = @(& $pwshPath -NoLogo -NoProfile -File $profilePath -Section list-machine -CompilerPath $CompilerPath -MemoryBudgetMiB $MemoryBudgetMiB -TimeoutSeconds $TimeoutSeconds)
if ($LASTEXITCODE -ne 0) {
	$inventoryOutput | ForEach-Object { Write-Host $_ }
	exit $LASTEXITCODE
}
$records = @($inventoryOutput | Where-Object { $_.Contains("`t") } | ConvertFrom-Csv -Delimiter "`t")
if (!$records.Count) {
	throw 'The compiler returned no machine section inventory.'
}
$inventory = @($records | ForEach-Object {
	[pscustomobject]@{
		Index = [int]::Parse($_.Index)
		Name = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_.NameBase64))
		Total = [int]::Parse($_.Total)
		Runtime = [bool]::Parse($_.Runtime)
		Batchable = [bool]::Parse($_.Batchable)
	}
})
if (@($inventory | Where-Object Runtime).Count -ne 1) {
	throw 'The inventory must identify exactly one runtime section.'
}
if ($ListSections) {
	$inventory | Format-Table -AutoSize
	return
}
$selected = @()
if ($AllSections) {
	$selected = $inventory
} else {
	foreach ($selector in $Sections) {
		$matches = @($inventory | Where-Object { $_.Name -ceq $selector -or "$($_.Index)" -ceq $selector })
		if ($matches.Count -ne 1) {
			throw "Unknown or ambiguous section '$selector'; use ListSections."
		}
		$selected += $matches[0]
	}
}
$completed = 0
foreach ($section in $selected) {
	Write-Host "Section $($completed + 1)/$($selected.Count): $($section.Name) ($($section.Total) tests)"
	if ($FirstFixture -and (!$section.Batchable -or $LastFixture -gt $section.Total)) {
		throw 'The selected section does not support that fixture range.'
	}
	$rangeFirst = if ($FirstFixture) { $FirstFixture } else { 1 }
	$rangeLast = if ($LastFixture) { $LastFixture } else { $section.Total }
	$step = if ($section.Batchable) { [long]$BatchSize } else { [long]$section.Total }
	for ($batchFirst = [long]$rangeFirst; $batchFirst -le $rangeLast; $batchFirst += $step) {
		$runtimeOptions = @{}
		if ($section.Runtime) {
			$runtimeOptions.RunRuntimeChecks = $true
		}
		if ($section.Batchable) {
			$batchLast = [Math]::Min($rangeLast, $batchFirst + $step - 1)
			Write-Host "Fixtures $batchFirst-$batchLast of $($section.Total)"
			$runtimeOptions.FirstFixture = $batchFirst
			$runtimeOptions.LastFixture = $batchLast
		}
		& $pwshPath -NoLogo -NoProfile -File $profilePath -Section $section.Name -CompilerPath $CompilerPath -MemoryBudgetMiB $MemoryBudgetMiB -TimeoutSeconds $TimeoutSeconds @runtimeOptions
		$exitCode = $LASTEXITCODE
		if ($exitCode -ne 0) {
			Write-Host "Stopped at '$($section.Name)' with status $exitCode; later batches and sections were not started."
			exit $exitCode
		}
	}
	$completed += 1
}

Write-Host "PASS $completed/$($selected.Count) isolated sections"
