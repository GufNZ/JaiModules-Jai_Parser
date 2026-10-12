param(
	[string]$Section,
	[string]$CompilerPath = (Join-Path $PSScriptRoot '../../../bin/jai.exe'),
	[string]$SourceFile = 'differential_test.jai',
	[ValidateRange(0, 1048576)]
	[long]$MemoryBudgetMiB = 0,
	[ValidateRange(1, 3600)]
	[int]$TimeoutSeconds = 300,
	[switch]$RunRuntimeChecks,
	[ValidateRange(0, 2147483647)]
	[int]$FirstFixture = 0,
	[ValidateRange(0, 2147483647)]
	[int]$LastFixture = 0
)

$ErrorActionPreference = 'Stop'
if (!$IsWindows) {
	throw 'This profiler requires Windows process-memory counters and pwsh.'
}
if ([string]::IsNullOrWhiteSpace($Section) -or $Section -in @('all', 'list')) {
	throw 'Select one differential section by exact name or number; combined runs are not supported.'
}
if ($RunRuntimeChecks -and ($SourceFile -cne 'differential_test.jai' -or $Section -cne 'Runtime checks')) {
	throw 'Runtime execution requires the differential source and exact Runtime checks selector.'
}
if ($FirstFixture -or $LastFixture) {
	if ($FirstFixture -lt 1 -or $LastFixture -lt $FirstFixture -or $RunRuntimeChecks -or $SourceFile -cne 'differential_test.jai') {
		throw 'Fixture ranges require paired positive bounds, the differential source, and compile-only execution.'
	}
}

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

[StructLayout(LayoutKind.Sequential)]
public struct DifferentialProcessMemoryCounters {
	public uint Size;
	public uint PageFaultCount;
	public UIntPtr PeakWorkingSetSize;
	public UIntPtr WorkingSetSize;
	public UIntPtr QuotaPeakPagedPoolUsage;
	public UIntPtr QuotaPagedPoolUsage;
	public UIntPtr QuotaPeakNonPagedPoolUsage;
	public UIntPtr QuotaNonPagedPoolUsage;
	public UIntPtr PagefileUsage;
	public UIntPtr PeakPagefileUsage;
}

[StructLayout(LayoutKind.Sequential)]
public struct DifferentialJobBasicLimits {
	public long ProcessTimeLimit;
	public long JobTimeLimit;
	public uint LimitFlags;
	public UIntPtr MinimumWorkingSetSize;
	public UIntPtr MaximumWorkingSetSize;
	public uint ActiveProcessLimit;
	public UIntPtr Affinity;
	public uint PriorityClass;
	public uint SchedulingClass;
}

[StructLayout(LayoutKind.Sequential)]
public struct DifferentialJobIoCounters {
	public ulong ReadOperationCount, WriteOperationCount, OtherOperationCount;
	public ulong ReadTransferCount, WriteTransferCount, OtherTransferCount;
}

[StructLayout(LayoutKind.Sequential)]
public struct DifferentialJobLimits {
	public DifferentialJobBasicLimits Basic;
	public DifferentialJobIoCounters Io;
	public UIntPtr ProcessMemoryLimit;
	public UIntPtr JobMemoryLimit;
	public UIntPtr PeakProcessMemoryUsed;
	public UIntPtr PeakJobMemoryUsed;
}

public static class DifferentialProcessMemory {
	[DllImport("psapi.dll", SetLastError = true)]
	[return: MarshalAs(UnmanagedType.Bool)]
	public static extern bool GetProcessMemoryInfo(
		IntPtr process, ref DifferentialProcessMemoryCounters counters, uint size);

	[DllImport("kernel32.dll", SetLastError = true)]
	public static extern IntPtr CreateJobObjectW(IntPtr attributes, IntPtr name);

	[DllImport("kernel32.dll", SetLastError = true)]
	[return: MarshalAs(UnmanagedType.Bool)]
	public static extern bool SetInformationJobObject(
		IntPtr job, int infoClass, ref DifferentialJobLimits limits, uint size);

	[DllImport("kernel32.dll", SetLastError = true)]
	[return: MarshalAs(UnmanagedType.Bool)]
	public static extern bool QueryInformationJobObject(
		IntPtr job, int infoClass, ref DifferentialJobLimits limits, uint size, IntPtr returnedSize);

	[DllImport("kernel32.dll", SetLastError = true)]
	[return: MarshalAs(UnmanagedType.Bool)]
	public static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);

	[DllImport("kernel32.dll", SetLastError = true)]
	[return: MarshalAs(UnmanagedType.Bool)]
	public static extern bool CloseHandle(IntPtr handle);
}
'@

$job = [IntPtr]::Zero
if ($MemoryBudgetMiB) {
	$job = [DifferentialProcessMemory]::CreateJobObjectW([IntPtr]::Zero, [IntPtr]::Zero)
	if ($job -eq [IntPtr]::Zero) {
		throw [System.ComponentModel.Win32Exception]::new([System.Runtime.InteropServices.Marshal]::GetLastWin32Error())
	}
	$limits = [DifferentialJobLimits]::new()
	$basicLimits = [DifferentialJobBasicLimits]::new()
	$basicLimits.LimitFlags = 0x200
	$limits.Basic = $basicLimits
	$limits.JobMemoryLimit = [UIntPtr]::new([ulong]($MemoryBudgetMiB * 1MB))
	$limitsSize = [System.Runtime.InteropServices.Marshal]::SizeOf([type][DifferentialJobLimits])
	if (![DifferentialProcessMemory]::SetInformationJobObject($job, 9, [ref]$limits, $limitsSize)) {
		throw [System.ComponentModel.Win32Exception]::new([System.Runtime.InteropServices.Marshal]::GetLastWin32Error())
	}
	if (![DifferentialProcessMemory]::QueryInformationJobObject($job, 9, [ref]$limits, $limitsSize, [IntPtr]::Zero)) {
		throw [System.ComponentModel.Win32Exception]::new([System.Runtime.InteropServices.Marshal]::GetLastWin32Error())
	}
	if (($limits.Basic.LimitFlags -band 0x200) -eq 0 -or $limits.JobMemoryLimit.ToUInt64() -ne [ulong]($MemoryBudgetMiB * 1MB)) {
		throw 'The requested job memory limit was not installed.'
	}
	$currentProcess = [System.Diagnostics.Process]::GetCurrentProcess()
	try {
		if (![DifferentialProcessMemory]::AssignProcessToJobObject($job, $currentProcess.Handle)) {
			throw [System.ComponentModel.Win32Exception]::new([System.Runtime.InteropServices.Marshal]::GetLastWin32Error())
		}
	} finally {
		$currentProcess.Dispose()
	}
}

$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = (Resolve-Path $CompilerPath).Path
$startInfo.WorkingDirectory = $PSScriptRoot
$startInfo.UseShellExecute = $false
foreach ($argument in @($SourceFile, '-x64', '-quiet', '-', $Section)) {
	$startInfo.ArgumentList.Add($argument)
}
if ($FirstFixture) {
	$startInfo.ArgumentList.Add("$FirstFixture")
	$startInfo.ArgumentList.Add("$LastFixture")
}

$process = [System.Diagnostics.Process]::Start($startInfo)
try {
	$handle = $process.Handle
	$timedOut = !$process.WaitForExit($TimeoutSeconds * 1000)
	if ($timedOut) {
		$process.Kill($true)
		$process.WaitForExit()
	}
	$exitCode = if ($timedOut) { 124 } else { $process.ExitCode }
	$counters = [DifferentialProcessMemoryCounters]::new()
	$counters.Size = [System.Runtime.InteropServices.Marshal]::SizeOf([type][DifferentialProcessMemoryCounters])
	if (![DifferentialProcessMemory]::GetProcessMemoryInfo($handle, [ref]$counters, $counters.Size)) {
		throw [System.ComponentModel.Win32Exception]::new([System.Runtime.InteropServices.Marshal]::GetLastWin32Error())
	}
	if ($counters.PeakWorkingSetSize.ToUInt64() -eq 0) {
		throw 'The operating system did not return a valid peak working set.'
	}
	$compilerExitCode = $process.ExitCode
	$runtimeExitCode = $null
	$runtimePeakCommit = $null
	if ($exitCode -eq 0 -and $RunRuntimeChecks) {
		$runtimeInfo = [System.Diagnostics.ProcessStartInfo]::new()
		$runtimeInfo.FileName = (Resolve-Path (Join-Path $PSScriptRoot 'differential_test.exe')).Path
		$runtimeInfo.WorkingDirectory = $PSScriptRoot
		$runtimeInfo.UseShellExecute = $false
		$runtimeProcess = [System.Diagnostics.Process]::Start($runtimeInfo)
		try {
			$runtimeHandle = $runtimeProcess.Handle
			$runtimeTimedOut = !$runtimeProcess.WaitForExit($TimeoutSeconds * 1000)
			if ($runtimeTimedOut) {
				$runtimeProcess.Kill($true)
				$runtimeProcess.WaitForExit()
			}
			$runtimeExitCode = $runtimeProcess.ExitCode
			$timedOut = $timedOut -or $runtimeTimedOut
			$exitCode = if ($runtimeTimedOut) { 124 } else { $runtimeExitCode }
			$runtimeCounters = [DifferentialProcessMemoryCounters]::new()
			$runtimeCounters.Size = $counters.Size
			if (![DifferentialProcessMemory]::GetProcessMemoryInfo($runtimeHandle, [ref]$runtimeCounters, $runtimeCounters.Size)) {
				throw [System.ComponentModel.Win32Exception]::new([System.Runtime.InteropServices.Marshal]::GetLastWin32Error())
			}
			$runtimePeakCommit = $runtimeCounters.PeakPagefileUsage.ToUInt64()
		} finally {
			if (!$runtimeProcess.HasExited) {
				$runtimeProcess.Kill($true)
				$runtimeProcess.WaitForExit()
			}
			$runtimeProcess.Dispose()
		}
	}
	$jobPeakCommit = $null
	if ($job -ne [IntPtr]::Zero) {
		if (![DifferentialProcessMemory]::QueryInformationJobObject($job, 9, [ref]$limits, $limitsSize, [IntPtr]::Zero)) {
			throw [System.ComponentModel.Win32Exception]::new([System.Runtime.InteropServices.Marshal]::GetLastWin32Error())
		}
		$jobPeakCommit = $limits.PeakJobMemoryUsed.ToUInt64()
	}

	[Console]::Out.WriteLine()
	[Console]::Error.WriteLine()
	[pscustomobject]@{
		SourceFile = $SourceFile
		Section = $Section
		FirstFixture = $FirstFixture
		LastFixture = $LastFixture
		ExitCode = $exitCode
		CompilerExitCode = $compilerExitCode
		RuntimeExitCode = $runtimeExitCode
		RuntimePeakCommitBytes = $runtimePeakCommit
		TimedOut = $timedOut
		TimeoutSeconds = $TimeoutSeconds
		PeakWorkingSetBytes = $counters.PeakWorkingSetSize.ToUInt64()
		PeakCommitBytes = $counters.PeakPagefileUsage.ToUInt64()
		MemoryBudgetMiB = $MemoryBudgetMiB
		JobPeakCommitBytes = $jobPeakCommit
	} | ConvertTo-Json -Compress
	exit $exitCode
} finally {
	if (!$process.HasExited) {
		$process.Kill($true)
		$process.WaitForExit()
	}
	$process.Dispose()
	if ($job -ne [IntPtr]::Zero) {
		[void][DifferentialProcessMemory]::CloseHandle($job)
	}
}
