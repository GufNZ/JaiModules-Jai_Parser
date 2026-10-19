param(
	[string] $OutputDirectory = (Join-Path $PSScriptRoot '.build/store_restart'),
	[ValidateSet('Run', 'Publish', 'Inspect', 'Select', 'Audit')]
	[string] $Mode = 'Run',
	[string] $StoreRoot = '',
	[string] $SourceBase64 = '',
	[string] $Slot = 'disk',
	[string] $PauseStage = '',
	[string] $ReadyPath = '',
	[string] $ReleasePath = '',
	[string] $DiskPath = '',
	[switch] $ConfirmRestore
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$Utf8 = [Text.UTF8Encoding]::new($false, $true)
$ArtifactLimit = 16384
$ManifestLimit = 8192
$ContextKey = 'E11-authored-context-v1'
$Checks = 0
$Workers = [Collections.Generic.List[object]]::new()

function WaitSignal([string] $path) {
	$watcher = [IO.FileSystemWatcher]::new([IO.Path]::GetDirectoryName($path), [IO.Path]::GetFileName($path))
	$eventId = [Guid]::NewGuid().ToString('N')
	$null = Register-ObjectEvent $watcher Created -SourceIdentifier $eventId
	try {
		$watcher.EnableRaisingEvents = $true
		if (![IO.File]::Exists($path)) {
			$event = Wait-Event -SourceIdentifier $eventId -Timeout 15
			Require ($null -ne $event -and [IO.File]::Exists($path)) "Signal timeout: $path"
		}
	} finally {
		Unregister-Event -SourceIdentifier $eventId
		Remove-Event -SourceIdentifier $eventId -ErrorAction SilentlyContinue
		$watcher.Dispose()
	}
}

function PauseAt([string] $stage) {
	if ($PauseStage -ceq $stage) {
		[IO.File]::WriteAllText($ReadyPath, "$stage`n", $Utf8)
		WaitSignal $ReleasePath
	}
}

function Require($condition, [string] $message) {
	if (!$condition) {
		throw $message
	}


	$script:Checks++
}

function Digest([byte[]] $bytes) {
	return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
}

function JsonBytes($value) {
	return ,($Utf8.GetBytes(($value | ConvertTo-Json -Depth 12) + "`n"))
}

function ReadBounded([string] $path, [long] $limit) {
	$stream = [IO.FileStream]::new($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::Read -bor [IO.FileShare]::Delete))
	try {
		Require ($stream.Length -gt 0 -and $stream.Length -le $limit) 'SIZE'
		$bytes = [byte[]]::new($stream.Length)
		$stream.ReadExactly($bytes)
		Require ($stream.ReadByte() -eq -1) 'SIZE_CHANGED'
		return ,$bytes
	} finally {
		$stream.Dispose()
	}
}

function WriteAtomic([string] $path, [byte[]] $bytes) {
	$temp = "$path.$([Guid]::NewGuid().ToString('N')).tmp"
	$stream = [IO.FileStream]::new($temp, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
	$kind = if ([IO.Path]::GetFileName($path) -ceq 'manifest.json') { 'manifest' } else { 'blob' }
	try {
		if ($PauseStage -ceq "$kind-partial") {
			$prefix = [Array]::IndexOf($bytes, [byte]10) + 1
			Require ($prefix -gt 0 -and $prefix -lt $bytes.Length) 'Partial-write boundary'
			$stream.Write($bytes, 0, $prefix)
			$stream.Flush($true)
			PauseAt "$kind-partial"
			$stream.Write($bytes, $prefix, $bytes.Length - $prefix)
		} else {
			$stream.Write($bytes)
		}

		$stream.Flush($true)
	} finally {
		$stream.Dispose()
	}

	PauseAt "$kind-ready"
	[IO.File]::Move($temp, $path, $true)
	PauseAt "$kind-published"
}

function OpenStore([string] $root) {
	$store = [pscustomobject]@{ Root = $root; Diagnostics = [Collections.Generic.List[string]]::new(); Reads = 0 }
	try {
		[IO.Directory]::CreateDirectory((Join-Path $root 'blobs')) > $null
	} catch {
		$store.Diagnostics.Add('CACHE_DIRECTORY_FAILED')
	}

	return $store
}

function LockStore($store) {
	try {
		$stream = [IO.FileStream]::new((Join-Path $store.Root 'store.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
	} catch [IO.IOException] {
		$_.Exception.Data['cache_code'] = 'LOCK_BUSY'
		throw
	}
	if (!$stream.Length) {
		$stream.WriteByte(10)
		$stream.Flush($true)
	}

	return $stream
}

function EmptyState() {
	return [ordered]@{ schema = 1; context = $ContextKey; generation = 0; disk = ''; recovery = ''; session = 'authored-session' }
}

function ReadState($store) {
	$bytes = ReadBounded (Join-Path $store.Root 'manifest.json') $ManifestLimit
	$envelope = $Utf8.GetString($bytes) | ConvertFrom-Json -AsHashtable -Depth 16
	Require ($envelope.schema -eq 1) 'SCHEMA'
	$body = [Convert]::FromBase64String($envelope.body)
	Require ((Digest $body) -ceq $envelope.digest) 'MANIFEST_CHECKSUM'
	$state = $Utf8.GetString($body) | ConvertFrom-Json -AsHashtable -Depth 16
	Require ($state.schema -eq 1 -and $state.context -ceq $ContextKey -and $state.generation -ge 0) 'STATE'
	foreach ($key in @($state.disk, $state.recovery)) {
		Require ($key -ceq '' -or $key -cmatch '^[0-9A-F]{64}$') 'KEY'
	}

	return $state
}

function WriteState($store, $state) {
	$body = JsonBytes $state
	$envelope = JsonBytes ([ordered]@{ schema = 1; digest = Digest $body; body = [Convert]::ToBase64String($body) })
	Require ($envelope.Length -le $ManifestLimit) 'MANIFEST_LIMIT'
	WriteAtomic (Join-Path $store.Root 'manifest.json') $envelope
}

function MakeArtifact([string] $source) {
	$bytes = $Utf8.GetBytes($source)
	Require ($bytes.Length -le 512) 'SOURCE_LIMIT'
	return [ordered]@{
		schema = 1
		context = $ContextKey
		source_digest = Digest $bytes
		source = [Convert]::ToBase64String($bytes)
		projection = [ordered]@{ bytes = $bytes.Length; lines = @($bytes | Where-Object { $_ -eq 10 }).Count }
	}
}

function ReadArtifact($store, [string] $key) {
	Require ($key -cmatch '^[0-9A-F]{64}$') 'KEY'
	$store.Reads++
	$bytes = ReadBounded (Join-Path $store.Root "blobs/$key.json") $ArtifactLimit
	Require ((Digest $bytes) -ceq $key) 'BLOB_CHECKSUM'
	$artifact = $Utf8.GetString($bytes) | ConvertFrom-Json -AsHashtable -Depth 16
	Require ($artifact.schema -eq 1 -and $artifact.context -ceq $ContextKey) 'ARTIFACT_SCHEMA'
	$source = [Convert]::FromBase64String($artifact.source)
	Require ($source.Length -le 512 -and (Digest $source) -ceq $artifact.source_digest) 'SOURCE_CHECKSUM'
	Require ($artifact.projection.bytes -eq $source.Length -and $artifact.projection.lines -eq @($source | Where-Object { $_ -eq 10 }).Count) 'PROJECTION'
	return $artifact
}

function Publish($store, [string] $source, [string] $slot = 'disk') {
	Require ($slot -in @('disk', 'recovery')) 'SLOT'
	$artifact = MakeArtifact $source
	$bytes = JsonBytes $artifact
	$key = Digest $bytes
	$lock = LockStore $store
	try {
		PauseAt 'locked'
		$path = Join-Path $store.Root "blobs/$key.json"
		if ([IO.File]::Exists($path)) {
			$null = ReadArtifact $store $key
		} else {
			WriteAtomic $path $bytes
		}

		$state = if ([IO.File]::Exists((Join-Path $store.Root 'manifest.json'))) { ReadState $store } else { EmptyState }
		$state[$slot] = $key
		$state.generation++
		WriteState $store $state
	} finally {
		$lock.Dispose()
	}

	return $key
}

function TryPersist($store, [string] $source, [string] $slot) {
	try {
		return Publish $store $source $slot
	} catch {
		$store.Diagnostics.Add('CACHE_WRITE_FAILED')
		return ''
	}
}

function ChangeReferences($store, [bool] $clearDisk = $false) {
	try {
		$lock = LockStore $store
		try {
			$state = ReadState $store
			$state.recovery = ''
			if ($clearDisk) {
				$state.disk = ''
			}

			$state.generation++
			WriteState $store $state
		} finally {
			$lock.Dispose()
		}
	} catch {
		$store.Diagnostics.Add('CACHE_METADATA_FAILED')
	}
}

function NewSession($store, [string] $diskPath, [bool] $enabled = $true, [bool] $restore = $false, [string] $restored = '') {
	$candidate = ''
	$state = $null
	if ($enabled -and [IO.File]::Exists((Join-Path $store.Root 'manifest.json'))) {
		try {
			$state = ReadState $store
			$candidate = $state.recovery
		} catch {
			$store.Diagnostics.Add('CACHE_MANIFEST_INVALID')
		}
	}

	return [pscustomobject]@{
		Store = $store
		DiskPath = $diskPath
		Enabled = $enabled
		HasOverlay = $restore
		Overlay = $restored
		Candidate = $candidate
		State = $state
	}
}

function SelectCurrent($session) {
	if ($session.HasOverlay) {
		$source = $session.Overlay
	} elseif ([IO.File]::Exists($session.DiskPath)) {
		$source = $Utf8.GetString((ReadBounded $session.DiskPath 512))
	} else {
		return [ordered]@{ status = 'MISSING'; source = ''; key = ''; artifact = $null }
	}

	$fresh = MakeArtifact $source
	if ($session.Enabled -and $null -ne $session.State) {
		$key = if ($session.HasOverlay) { $session.State.recovery } else { $session.State.disk }
		if ($key) {
			try {
				$cached = ReadArtifact $session.Store $key
				if ($cached.source_digest -ceq $fresh.source_digest) {
					Require ($cached.projection.bytes -eq $fresh.projection.bytes -and $cached.projection.lines -eq $fresh.projection.lines) 'Fresh projection mismatch'
					return [ordered]@{ status = 'HIT'; source = $source; key = $key; artifact = $cached }
				}

				$session.Store.Diagnostics.Add('CACHE_SOURCE_CHANGED')
			} catch {
				$session.Store.Diagnostics.Add('CACHE_BLOB_INVALID')
			}
		}
	}

	return [ordered]@{ status = 'FRESH'; source = $source; key = ''; artifact = $fresh }
}

function RefreshSession($session) {
	$session.State = $null
	try {
		$session.State = ReadState $session.Store
	} catch {
		$session.Store.Diagnostics.Add('CACHE_MANIFEST_INVALID')
	}
}

function EditOverlay($session, [string] $source) {
	$session.HasOverlay = $true
	$session.Overlay = $source
	if ($session.Enabled) {
		$null = TryPersist $session.Store $source 'recovery'
		RefreshSession $session
	}
}

function SaveOverlay($session) {
	Require ($session.HasOverlay) 'No overlay to save'
	WriteAtomic $session.DiskPath ($Utf8.GetBytes($session.Overlay))
	if ($session.Enabled) {
		$null = TryPersist $session.Store $session.Overlay 'disk'
		ChangeReferences $session.Store
		RefreshSession $session
	}

	$session.HasOverlay = $false
	$session.Overlay = ''
}

function ResetOverlay($session) {
	$session.HasOverlay = $false
	$session.Overlay = ''
	if ($session.Enabled) {
		ChangeReferences $session.Store
		RefreshSession $session
	}
}

function CollectStore($store, [string[]] $leases) {
	$lock = LockStore $store
	try {
		$state = ReadState $store
		$roots = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
		foreach ($key in @($state.disk, $state.recovery) + $leases) {
			if ($key) {
				$null = $roots.Add($key)
			}
		}

		$removed = [Collections.Generic.List[string]]::new()
		foreach ($file in Get-ChildItem (Join-Path $store.Root 'blobs') -Filter '*.json') {
			if (!$roots.Contains($file.BaseName)) {
				[IO.File]::Delete($file.FullName)
				$removed.Add($file.BaseName)
			}
		}

		$temps = @(Get-ChildItem $store.Root -Recurse -Filter '*.tmp' -File)
		foreach ($file in $temps) {
			[IO.File]::Delete($file.FullName)
		}

		return [ordered]@{ roots = @($roots | Sort-Object); removed = @($removed | Sort-Object); temporary_files = $temps.Count }
	} finally {
		$lock.Dispose()
	}
}

function RunInitialProbe([string] $root) {
	$store = OpenStore $root
	$first = Publish $store "answer :: 41;`n"
	$firstState = ReadState $store
	$artifact = ReadArtifact $store $first
	Require ($Utf8.GetString([Convert]::FromBase64String($artifact.source)) -ceq "answer :: 41;`n") 'Exact source roundtrip'
	$unpublished = Join-Path $root 'manifest.json.authored.tmp'
	[IO.File]::WriteAllText($unpublished, "{`n", $Utf8)
	Require ((ReadState $store).disk -ceq $first) 'Unpublished temporary manifest selected'
	$second = Publish $store "answer :: 42;`n"
	$secondState = ReadState $store
	Require ($first -cne $second -and $firstState.generation -eq 1 -and $secondState.generation -eq 2) 'Content identity/generation'
	Require ((ReadArtifact $store $first).source_digest -cne (ReadArtifact $store $second).source_digest) 'Retained immutable blob'
	return [ordered]@{ checks = $Checks; first = $first; second = $second; generation = $secondState.generation }
}

function StartWorker([string[]] $arguments) {
	$info = [Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path)
	$info.UseShellExecute = $false
	$info.RedirectStandardOutput = $true
	$info.RedirectStandardError = $true
	foreach ($argument in @('-NoProfile', '-File', $PSCommandPath) + $arguments) {
		$info.ArgumentList.Add($argument)
	}

	$process = [Diagnostics.Process]::Start($info)
	$worker = [pscustomobject]@{ Process = $process; Output = $process.StandardOutput.ReadToEndAsync(); Errors = $process.StandardError.ReadToEndAsync() }
	$Workers.Add($worker)
	return $worker
}

function AwaitWorker($worker, [bool] $killed = $false) {
	Require ($worker.Process.WaitForExit(20000)) 'Worker timeout'
	$output = $worker.Output.GetAwaiter().GetResult()
	$errors = $worker.Errors.GetAwaiter().GetResult()
	if ($killed) {
		Require ($worker.Process.ExitCode -ne 0) 'Killed worker unexpectedly succeeded'
		return
	}

	Require ($worker.Process.ExitCode -eq 0) "Worker failed: $errors"
	return ($output | ConvertFrom-Json -AsHashtable -Depth 16)
}

function PublishWorker([string] $root, [string] $source, [string] $slot = 'disk', [string] $stage = '') {
	$arguments = @('-Mode', 'Publish', '-StoreRoot', $root, '-SourceBase64', [Convert]::ToBase64String($Utf8.GetBytes($source)), '-Slot', $slot)
	if ($stage) {
		$arguments += @('-PauseStage', $stage, '-ReadyPath', (Join-Path $root 'ready'), '-ReleasePath', (Join-Path $root 'release'))
	}

	return StartWorker $arguments
}

function InspectWorker([string] $root) {
	return AwaitWorker (StartWorker @('-Mode', 'Inspect', '-StoreRoot', $root))
}

function SelectWorker([string] $root, [string] $diskPath, [bool] $restore = $false, [string] $source = '') {
	$arguments = @('-Mode', 'Select', '-StoreRoot', $root, '-DiskPath', $diskPath)
	if ($restore) {
		$arguments += @('-ConfirmRestore', '-SourceBase64', [Convert]::ToBase64String($Utf8.GetBytes($source)))
	}

	return AwaitWorker (StartWorker $arguments)
}

function RunLifecycle([string] $root) {
	$store = OpenStore $root
	$diskPath = Join-Path $root 'document.jai'
	$first = "answer :: 41;`n"
	$second = "answer :: 42;`n"
	$third = "answer :: 43;`n"
	[IO.File]::WriteAllText($diskPath, $first, $Utf8)
	$firstKey = Publish $store $first
	$session = NewSession $store $diskPath
	Require ($store.Reads -eq 0) 'Manifest startup eagerly decoded a blob'
	$initial = SelectCurrent $session
	Require ($initial.status -ceq 'HIT' -and $initial.source -ceq $first -and $store.Reads -eq 1) 'Lazy initial selection'
	EditOverlay $session $second
	$overlayKey = (ReadState $store).recovery
	Require ((SelectCurrent $session).source -ceq $second) 'Unsaved overlay precedence'
	$normal = SelectWorker $root $diskPath
	$restored = SelectWorker $root $diskPath $true $second
	$mismatched = SelectWorker $root $diskPath $true $third
	Require ($normal.source -ceq $first -and $normal.status -ceq 'HIT' -and $normal.candidate -ceq $overlayKey) 'Recovery candidate automatically activated'
	Require ($restored.source -ceq $second -and $restored.status -ceq 'HIT') 'Confirmed recovery not restored'
	Require ($mismatched.source -ceq $third -and $mismatched.status -ceq 'FRESH') 'Host restore bytes did not override recovery candidate'
	SaveOverlay $session
	$state = ReadState $store
	Require ($state.disk -ceq $overlayKey -and !$state.recovery -and !$session.HasOverlay) 'Save did not reconcile disk/overlay'
	Require ((SelectWorker $root $diskPath).source -ceq $second) 'Saved restart'
	$saved = SelectCurrent $session
	EditOverlay $session $third
	$discardedKey = (ReadState $store).recovery
	$stamp = [IO.File]::GetLastWriteTimeUtc($diskPath)
	[IO.File]::WriteAllText($diskPath, $first, $Utf8)
	[IO.File]::SetLastWriteTimeUtc($diskPath, $stamp)
	Require ((SelectCurrent $session).source -ceq $third) 'External change overrode active overlay'
	ResetOverlay $session
	$reset = SelectCurrent $session
	Require ($reset.source -ceq $first -and $reset.status -ceq 'FRESH') 'Reset did not hash current disk'
	Require ([IO.File]::GetLastWriteTimeUtc($diskPath) -eq $stamp -and $first.Length -eq $second.Length) 'Timestamp/length control'
	$afterReset = SelectWorker $root $diskPath
	Require ($afterReset.source -ceq $first -and !$afterReset.candidate) 'Discarded recovery revived at restart'
	$null = Publish $store $first
	$session = NewSession $store $diskPath
	EditOverlay $session $third
	[IO.File]::Delete($diskPath)
	Require ((SelectCurrent $session).source -ceq $third) 'Deleting disk lost active overlay'
	ResetOverlay $session
	ChangeReferences $store $true
	Require ((SelectWorker $root $diskPath).status -ceq 'MISSING') 'Deleted disk resurrected cached source'
	[IO.File]::WriteAllText($diskPath, $second, $Utf8)
	[IO.File]::SetLastWriteTimeUtc($diskPath, $stamp)
	$reappeared = SelectWorker $root $diskPath
	Require ($reappeared.source -ceq $second -and $reappeared.status -ceq 'FRESH') 'Reappearing disk selected historical revision'
	$null = Publish $store $second
	$gcLeased = CollectStore $store @($firstKey)
	Require ([IO.File]::Exists((Join-Path $root "blobs/$firstKey.json")) -and $discardedKey -cin $gcLeased.removed) 'Lease or discarded recovery GC'
	$gcReleased = CollectStore $store @()
	Require ($firstKey -cin $gcReleased.removed -and [IO.File]::Exists((Join-Path $root "blobs/$overlayKey.json"))) 'Released lease/current root GC'
	$disabled = NewSession $store $diskPath $false
	$reads = $store.Reads
	EditOverlay $disabled $third
	Require ((SelectCurrent $disabled).source -ceq $third -and $store.Reads -eq $reads) 'Disabled persistence semantics'
	Require (!(ReadState $store).recovery) 'Disabled persistence wrote recovery metadata'
	return [ordered]@{
		initial = $initial; normal_restart = $normal; confirmed_restore = $restored; changed_restore = $mismatched; saved = $saved
		reset = $reset; reappeared = $reappeared; gc_leased = $gcLeased; gc_released = $gcReleased
		discarded = $discardedKey; leased = $firstKey; current = $overlayKey; diagnostics = @($store.Diagnostics)
		same_timestamp = ([IO.File]::GetLastWriteTimeUtc($diskPath) -eq $stamp); equal_source_sizes = ($first.Length -eq $second.Length)
	}
}

function RunCorruption([string] $root) {
	$results = [Collections.Generic.List[object]]::new()
	foreach ($kind in @('BLOB_BYTES', 'BLOB_TRUNCATED', 'BLOB_LIMIT', 'BLOB_MISSING', 'INNER_SOURCE', 'INNER_CONTEXT', 'MANIFEST_DIGEST', 'MANIFEST_TRUNCATED', 'MANIFEST_LIMIT', 'MANIFEST_SCHEMA', 'STATE_CONTEXT', 'STATE_KEY')) {
		$caseRoot = Join-Path $root $kind
		$store = OpenStore $caseRoot
		$source = "answer :: 41;`n"
		$diskPath = Join-Path $caseRoot 'document.jai'
		[IO.File]::WriteAllText($diskPath, $source, $Utf8)
		$key = Publish $store $source
		$blobPath = Join-Path $caseRoot "blobs/$key.json"
		$manifestPath = Join-Path $caseRoot 'manifest.json'
		switch ($kind) {
			'BLOB_BYTES' {
				$bytes = [IO.File]::ReadAllBytes($blobPath)
				$bytes[0] = [byte][char]'X'
				[IO.File]::WriteAllBytes($blobPath, $bytes)
			}
			'BLOB_TRUNCATED' { [IO.File]::WriteAllText($blobPath, "{`n", $Utf8) }
			'BLOB_LIMIT' { [IO.File]::WriteAllText($blobPath, ('X' * $ArtifactLimit) + "`n", $Utf8) }
			'BLOB_MISSING' { [IO.File]::Delete($blobPath) }
			{ $_ -in @('INNER_SOURCE', 'INNER_CONTEXT') } {
				$artifact = ReadArtifact $store $key
				if ($kind -ceq 'INNER_SOURCE') {
					$artifact.source_digest = '0' * 64
				} else {
					$artifact.context = 'foreign-context'
				}

				$bytes = JsonBytes $artifact
				$newKey = Digest $bytes
				WriteAtomic (Join-Path $caseRoot "blobs/$newKey.json") $bytes
				$state = ReadState $store
				$state.disk = $newKey
				WriteState $store $state
			}
			'MANIFEST_DIGEST' {
				$envelope = [IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json -AsHashtable
				$envelope.digest = '0' * 64
				[IO.File]::WriteAllBytes($manifestPath, (JsonBytes $envelope))
			}
			'MANIFEST_TRUNCATED' { [IO.File]::WriteAllText($manifestPath, "{`n", $Utf8) }
			'MANIFEST_LIMIT' { [IO.File]::WriteAllText($manifestPath, ('X' * $ManifestLimit) + "`n", $Utf8) }
			'MANIFEST_SCHEMA' {
				$envelope = [IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json -AsHashtable
				$envelope.schema = 2
				[IO.File]::WriteAllBytes($manifestPath, (JsonBytes $envelope))
			}
			{ $_ -in @('STATE_CONTEXT', 'STATE_KEY') } {
				$state = ReadState $store
				if ($kind -ceq 'STATE_CONTEXT') {
					$state.context = 'foreign-context'
				} else {
					$state.disk = '../outside-store'
				}

				WriteState $store $state
			}
		}

		$selected = SelectWorker $caseRoot $diskPath
		Require ($selected.status -ceq 'FRESH' -and $selected.source -ceq $source -and $selected.diagnostics.Count -gt 0) "Corrupt store did not fail open: $kind"
		Require ($selected.artifact.source_digest -ceq (Digest $Utf8.GetBytes($source))) "Corrupt store fresh oracle: $kind"
		if ($kind.StartsWith('MANIFEST') -or $kind.StartsWith('STATE')) {
			$before = @(Get-ChildItem (Join-Path $caseRoot 'blobs') -Filter '*.json').Count
			$refused = $false
			try {
				$null = CollectStore $store @()
			} catch {
				$refused = $true
			}

			Require ($refused -and @(Get-ChildItem (Join-Path $caseRoot 'blobs') -Filter '*.json').Count -eq $before) "GC guessed roots from corrupt manifest: $kind"
		}

		$results.Add([ordered]@{ case = $kind; selected = $selected })
	}

	return ,$results
}

function RunUnwritable([string] $root) {
	[IO.Directory]::CreateDirectory($root) > $null
	$cache = Join-Path $root 'cache'
	$store = OpenStore $cache
	$source = "answer :: 41;`n"
	$edited = "answer :: 42;`n"
	$diskPath = Join-Path $root 'document.jai'
	[IO.File]::WriteAllText($diskPath, $source, $Utf8)
	$oldKey = Publish $store $source
	$session = NewSession $store $diskPath
	if ($IsWindows) {
		$original = (Get-Acl -LiteralPath $cache).Sddl
		$restricted = Get-Acl -LiteralPath $cache
		$identity = [Security.Principal.WindowsIdentity]::GetCurrent().User
		$rule = [Security.AccessControl.FileSystemAccessRule]::new($identity, [Security.AccessControl.FileSystemRights]::Write, [Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit', [Security.AccessControl.PropagationFlags]::None, [Security.AccessControl.AccessControlType]::Deny)
		$restricted.AddAccessRule($rule)
		Set-Acl -LiteralPath $cache -AclObject $restricted
	} else {
		$original = [IO.File]::GetUnixFileMode($cache)
		[IO.File]::SetUnixFileMode($cache, [IO.UnixFileMode]'UserRead,UserExecute')
	}

	try {
		EditOverlay $session $edited
		$selected = SelectCurrent $session
		Require ($selected.source -ceq $edited -and $selected.status -ceq 'FRESH') 'Unwritable cache lost active source'
		Require ('CACHE_WRITE_FAILED' -cin $store.Diagnostics -and !(ReadState $store).recovery) 'Cache directory was not actually unwritable'
		SaveOverlay $session
		Require (!$session.HasOverlay -and (SelectCurrent $session).source -ceq $edited) 'Saving source depended on cache writes'
		Require ((ReadState $store).disk -ceq $oldKey -and [IO.File]::ReadAllText($diskPath) -ceq $edited) 'Failed cache publish altered manifest or blocked disk save'
	} finally {
		if ($IsWindows) {
			$restore = [Security.AccessControl.DirectorySecurity]::new()
			$restore.SetSecurityDescriptorSddlForm($original)
			Set-Acl -LiteralPath $cache -AclObject $restore
		} else {
			[IO.File]::SetUnixFileMode($cache, $original)
		}
	}

	$session = NewSession $store $diskPath
	EditOverlay $session $edited
	Require ((SelectCurrent $session).status -ceq 'HIT') 'Persistence did not recover after permissions restored'
	ResetOverlay $session
	Require (!(ReadState $store).recovery) 'Recovery cleanup after permissions restored'
	$blockedRoot = Join-Path $root 'not-a-directory'
	[IO.File]::WriteAllText($blockedRoot, "blocked`n", $Utf8)
	$blocked = OpenStore $blockedRoot
	$disabled = NewSession $blocked $diskPath
	EditOverlay $disabled $source
	Require ((SelectCurrent $disabled).source -ceq $source -and 'CACHE_DIRECTORY_FAILED' -cin $blocked.Diagnostics) 'Unavailable cache path broke in-memory operation'
	return [ordered]@{ selected = $selected; diagnostics = @($store.Diagnostics); unavailable_path_diagnostics = @($blocked.Diagnostics); permissions_restored = $true }
}

function RunControls([string] $root, $lifecycle) {
	$store = OpenStore $root
	$lease = Publish $store $lifecycle.normal_restart.source
	$current = Publish $store $lifecycle.saved.source
	$brokenGc = CollectStore $store @()
	$leaseOutcome = if ([IO.File]::Exists((Join-Path $root "blobs/$lease.json"))) { 'retained' } else { 'deleted' }
	Require ($lease -cne $current -and $lease -cin $brokenGc.removed) 'Omitted-lease control did not collect leased blob'
	$results = @(
		[ordered]@{ policy = 'AUTO_RESTORE'; expected = $lifecycle.normal_restart.source; broken = $lifecycle.confirmed_restore.source },
		[ordered]@{ policy = 'TIMESTAMP_ONLY'; expected = $lifecycle.reset.source; broken = $lifecycle.saved.source },
		[ordered]@{ policy = 'IGNORE_LEASE'; expected = 'retained'; broken = $leaseOutcome; lease = $lease; removed = $brokenGc.removed },
		[ordered]@{ policy = 'REVIVE_DISCARDED'; expected = ''; broken = $lifecycle.discarded }
	)
	foreach ($result in $results) {
		Require ($result.expected -cne $result.broken) "Undetected broken policy: $($result.policy)"
	}

	return ,$results
}

function RunProcessProbes([string] $root) {
	$results = [Collections.Generic.List[object]]::new()
	foreach ($stage in @('blob-partial', 'blob-published', 'manifest-partial', 'manifest-ready', 'manifest-published')) {
		$caseRoot = Join-Path $root $stage
		$store = OpenStore $caseRoot
		$old = Publish $store "answer :: 41;`n"
		$worker = PublishWorker $caseRoot "answer :: 42;`n" 'disk' $stage
		WaitSignal (Join-Path $caseRoot 'ready')
		$before = ReadState $store
		$expected = if ($stage -ceq 'manifest-published') { "answer :: 42;`n" } else { "answer :: 41;`n" }
		$null = ReadArtifact $store $before.disk
		$worker.Process.Kill($true)
		$null = AwaitWorker $worker $true
		$after = InspectWorker $caseRoot
		Require ($after.source -ceq $expected -and $after.disk -ceq $before.disk) "Interrupted publication: $stage"
		Require (($after.disk -ceq $old) -eq ($stage -cne 'manifest-published')) "Publication visibility: $stage"
		$gc = CollectStore $store @($old)
		Require ((ReadState $store).disk -ceq $after.disk -and @(Get-ChildItem $caseRoot -Recurse -Filter '*.tmp').Count -eq 0) 'Crash cleanup changed selection or retained staging'
		$results.Add([ordered]@{ case = $stage; generation = $after.generation; disk = $after.disk; source = $after.source; killed = $true; gc = $gc })
	}

	$caseRoot = Join-Path $root 'competing'
	$store = OpenStore $caseRoot
	$null = Publish $store "answer :: 41;`n"
	$first = PublishWorker $caseRoot "answer :: 42;`n" 'disk' 'locked'
	WaitSignal (Join-Path $caseRoot 'ready')
	$loser = AwaitWorker (PublishWorker $caseRoot "answer :: 43;`n" 'recovery')
	Require ($loser.status -ceq 'MEMORY_ONLY' -and $loser.diagnostic -ceq 'LOCK_BUSY') 'Competing publisher must fail open'
	Require ($loser.source -ceq "answer :: 43;`n" -and (ReadState $store).generation -eq 1) 'Lock loser changed manifest or lost source'
	[IO.File]::WriteAllText((Join-Path $caseRoot 'release'), "release`n", $Utf8)
	$winner = AwaitWorker $first
	$retry = AwaitWorker (PublishWorker $caseRoot "answer :: 43;`n" 'recovery')
	$state = ReadState $store
	Require ($winner.status -ceq 'PUBLISHED' -and $retry.status -ceq 'PUBLISHED' -and $state.generation -eq 3) 'Retry publication'
	Require ($state.disk -ceq $winner.key -and $state.recovery -ceq $retry.key) 'Lost manifest slot update'
	$blobCount = @(Get-ChildItem (Join-Path $caseRoot 'blobs') -Filter '*.json').Count
	$same = Publish $store "answer :: 43;`n"
	Require ($same -ceq $retry.key -and @(Get-ChildItem (Join-Path $caseRoot 'blobs') -Filter '*.json').Count -eq $blobCount) 'Identical blob reuse'
	$results.Add([ordered]@{ case = 'competing'; lock_loser = $loser; winner = $winner; retry = $retry; generation = $state.generation; blobs = $blobCount })
	return ,$results
}

function AuditEvidence([string] $root) {
	$summary = [IO.File]::ReadAllText((Join-Path $root 'summary.json')) | ConvertFrom-Json -AsHashtable
	$processes = @([IO.File]::ReadAllText((Join-Path $root 'process_probes.json')) | ConvertFrom-Json -AsHashtable)
	$lifecycle = [IO.File]::ReadAllText((Join-Path $root 'lifecycle.json')) | ConvertFrom-Json -AsHashtable
	$corruptions = @([IO.File]::ReadAllText((Join-Path $root 'corruption.json')) | ConvertFrom-Json -AsHashtable)
	$controls = @([IO.File]::ReadAllText((Join-Path $root 'negative_controls.json')) | ConvertFrom-Json -AsHashtable)
	$permission = [IO.File]::ReadAllText((Join-Path $root 'unwritable.json')) | ConvertFrom-Json -AsHashtable
	Require ($processes.Count -eq 6 -and $corruptions.Count -eq 12 -and $controls.Count -eq 4) 'Audit scenario counts'
	Require ($summary.workers -eq 32 -and $summary.killed_publishers -eq 5 -and $summary.main_process_checks -gt 800) 'Audit process/check totals'
	foreach ($case in $processes) {
		$caseRoot = Join-Path $root $case.case
		$envelope = [IO.File]::ReadAllText((Join-Path $caseRoot 'manifest.json')) | ConvertFrom-Json -AsHashtable
		$body = [Convert]::FromBase64String($envelope.body)
		$hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($body))
		Require ($envelope.schema -eq 1 -and $hash -ceq $envelope.digest) 'Audit manifest digest'
		$state = $Utf8.GetString($body) | ConvertFrom-Json -AsHashtable
		foreach ($key in @($state.disk, $state.recovery)) {
			if (!$key) {
				continue
			}

			Require ($key -cmatch '^[0-9A-F]{64}$') 'Audit safe artifact key'
			$bytes = [IO.File]::ReadAllBytes((Join-Path $caseRoot "blobs/$key.json"))
			Require ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)) -ceq $key) 'Audit blob digest'
			$artifact = $Utf8.GetString($bytes) | ConvertFrom-Json -AsHashtable
			$source = [Convert]::FromBase64String($artifact.source)
			Require ($artifact.schema -eq 1 -and $artifact.context -ceq $ContextKey -and [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($source)) -ceq $artifact.source_digest) 'Audit source/context'
			Require ($artifact.projection.bytes -eq $source.Length -and $artifact.projection.lines -eq @($source | Where-Object { $_ -eq 10 }).Count) 'Audit projection oracle'
		}

		if ($case.case -ceq 'competing') {
			Require ($case.lock_loser.status -ceq 'MEMORY_ONLY' -and $case.lock_loser.diagnostic -ceq 'LOCK_BUSY' -and $case.generation -eq 3 -and $state.generation -eq 4) 'Audit lock/retry/deduplication'
			Require ($case.winner.key -cne $case.retry.key -and $state.disk -ceq $case.retry.key -and $state.recovery -ceq $case.retry.key) 'Audit final competing slots'
			$winner = [IO.File]::ReadAllText((Join-Path $caseRoot "blobs/$($case.winner.key).json")) | ConvertFrom-Json -AsHashtable
			Require ($Utf8.GetString([Convert]::FromBase64String($winner.source)) -ceq "answer :: 42;`n") 'Audit retained winning blob'
		} else {
			$newVisible = $case.case -ceq 'manifest-published'
			$expected = if ($newVisible) { "answer :: 42;`n" } else { "answer :: 41;`n" }
			Require ($case.killed -and $case.source -ceq $expected -and $state.disk -ceq $case.disk -and $state.generation -eq $(if ($newVisible) { 2 } else { 1 })) 'Audit killed writer visibility'
			Require (@(Get-ChildItem $caseRoot -Recurse -Filter '*.tmp').Count -eq 0) 'Audit crashed temporary cleanup'
		}
	}

	Require ($lifecycle.normal_restart.source -ceq "answer :: 41;`n" -and $lifecycle.confirmed_restore.source -ceq "answer :: 42;`n" -and $lifecycle.changed_restore.source -ceq "answer :: 43;`n") 'Audit authoritative restore'
	Require ($lifecycle.normal_restart.reads -eq 1 -and $lifecycle.changed_restore.status -ceq 'FRESH' -and $lifecycle.reset.status -ceq 'FRESH' -and $lifecycle.same_timestamp -and $lifecycle.equal_source_sizes) 'Audit lazy/content validation'
	Require ($lifecycle.leased -cin $lifecycle.gc_leased.roots -and $lifecycle.leased -cnotin $lifecycle.gc_leased.removed -and $lifecycle.leased -cin $lifecycle.gc_released.removed -and $lifecycle.discarded -cin $lifecycle.gc_leased.removed) 'Audit lease/discard roots'
	foreach ($case in $corruptions) {
		Require ($case.selected.status -ceq 'FRESH' -and $case.selected.source -ceq "answer :: 41;`n" -and $case.selected.diagnostics.Count -gt 0) 'Audit corrupt-input fallback'
	}

	Require ($permission.permissions_restored -and 'CACHE_WRITE_FAILED' -cin $permission.diagnostics -and 'CACHE_DIRECTORY_FAILED' -cin $permission.unavailable_path_diagnostics) 'Audit real unwritable store'
	foreach ($control in $controls) {
		Require ($control.expected -cne $control.broken) 'Audit broken-policy mismatch'
	}

	$checkedFiles = 0
	foreach ($file in Get-ChildItem $root -Recurse -File) {
		$bytes = [IO.File]::ReadAllBytes($file.FullName)
		Require ($bytes.Length -gt 0 -and $bytes[-1] -eq 10) "Final newline: $($file.FullName)"
		$checkedFiles++
	}

	$sourceBytes = [IO.File]::ReadAllBytes($PSCommandPath)
	Require ($sourceBytes[-1] -eq 10) 'Harness final newline'
	$result = [ordered]@{ independent_checks = $Checks; worker_processes = $summary.workers; interrupted_publishers = 5; corruptions = 12; negative_controls = 4; newline_files = $checkedFiles; publication_digests = 'passed'; source_oracles = 'passed' }
	[IO.File]::WriteAllBytes((Join-Path $root 'audit_summary.json'), (JsonBytes $result))
	return $result
}

if ($Mode -ceq 'Audit') {
	AuditEvidence $StoreRoot | ConvertTo-Json -Depth 12
	return
}

if ($Mode -ceq 'Publish') {
	$store = OpenStore $StoreRoot
	$source = $Utf8.GetString([Convert]::FromBase64String($SourceBase64))
	try {
		$key = Publish $store $source $Slot
		$result = [ordered]@{ status = 'PUBLISHED'; key = $key; source = $source }
	} catch [IO.IOException] {
		$code = if ($_.Exception.Data['cache_code']) { $_.Exception.Data['cache_code'] } else { 'CACHE_WRITE_FAILED' }
		$result = [ordered]@{ status = 'MEMORY_ONLY'; diagnostic = $code; source = $source }
	}

	Write-Output ($result | ConvertTo-Json -Depth 12 -Compress)
	return
}

if ($Mode -ceq 'Select') {
	$store = OpenStore $StoreRoot
	$restored = if ($ConfirmRestore) { $Utf8.GetString([Convert]::FromBase64String($SourceBase64)) } else { '' }
	$session = NewSession $store $DiskPath $true $ConfirmRestore.IsPresent $restored
	Require ($store.Reads -eq 0) 'Restart reader eagerly decoded artifacts'
	$result = SelectCurrent $session
	$result.candidate = $session.Candidate
	$result.reads = $store.Reads
	$result.diagnostics = @($store.Diagnostics)
	Write-Output ($result | ConvertTo-Json -Depth 12 -Compress)
	return
}

if ($Mode -ceq 'Inspect') {
	$store = OpenStore $StoreRoot
	$state = ReadState $store
	$artifact = ReadArtifact $store $state.disk
	Write-Output ([ordered]@{ generation = $state.generation; disk = $state.disk; source = $Utf8.GetString([Convert]::FromBase64String($artifact.source)) } | ConvertTo-Json -Compress)
	return
}

$runRoot = Join-Path ([IO.Path]::GetFullPath($OutputDirectory)) ([Guid]::NewGuid().ToString('N'))
try {
	$report = RunInitialProbe (Join-Path $runRoot 'initial')
	[IO.File]::WriteAllBytes((Join-Path $runRoot 'initial_probe.json'), (JsonBytes $report))
	$processResults = RunProcessProbes $runRoot
	[IO.File]::WriteAllBytes((Join-Path $runRoot 'process_probes.json'), (JsonBytes $processResults))
	$lifecycle = RunLifecycle (Join-Path $runRoot 'lifecycle')
	[IO.File]::WriteAllBytes((Join-Path $runRoot 'lifecycle.json'), (JsonBytes $lifecycle))
	$corruptions = RunCorruption (Join-Path $runRoot 'corruption')
	[IO.File]::WriteAllBytes((Join-Path $runRoot 'corruption.json'), (JsonBytes $corruptions))
	$unwritable = RunUnwritable (Join-Path $runRoot 'unwritable')
	[IO.File]::WriteAllBytes((Join-Path $runRoot 'unwritable.json'), (JsonBytes $unwritable))
	$controls = RunControls (Join-Path $runRoot 'controls') $lifecycle
	[IO.File]::WriteAllBytes((Join-Path $runRoot 'negative_controls.json'), (JsonBytes $controls))
	$summary = [ordered]@{
		main_process_checks = $Checks; workers = $Workers.Count; killed_publishers = 5; corruption_cases = $corruptions.Count; negative_controls = $controls.Count
		powershell = $PSVersionTable.PSVersion.ToString(); runtime = [Runtime.InteropServices.RuntimeInformation]::FrameworkDescription
		os = [Runtime.InteropServices.RuntimeInformation]::OSDescription; filesystem = [IO.DriveInfo]::new([IO.Path]::GetPathRoot($runRoot)).DriveFormat
	}
	[IO.File]::WriteAllBytes((Join-Path $runRoot 'summary.json'), (JsonBytes $summary))
	Write-Output "E11: $Checks checks; publication, restart/overlay, corruption, unwritable cache and GC passed.  Evidence: $runRoot"
} finally {
	foreach ($worker in $Workers) {
		if (!$worker.Process.HasExited) {
			$worker.Process.Kill($true)
			$worker.Process.WaitForExit()
		}

		$worker.Process.Dispose()
	}
}
