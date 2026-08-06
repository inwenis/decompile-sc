# Best-effort live foreign-process working-directory reader (task 100 --
# conductor incident 2026-07-20: the explorer harness's headless judge call
# was misclassified as conductor-shaped). Win32_Process carries no CWD
# property (confirmed empirically -- WMI's schema only exposes
# ExecutablePath, the binary location, never the invocation cwd), so the
# only way to read it is the process's own PEB
# (ProcessParameters.CurrentDirectory), which requires reading the target
# process's memory. Inherently best-effort: access denied, an x86/x64
# mismatch, or the process exiting mid-read all fail closed to $null. NOT
# Pester-tested -- live native interop, same precedent as
# scripts/lib/agent-proc.ps1. Empirically validated against a spawned child
# process with a known cwd before this shipped (see PR).
#
# The pure caller (Test-NonConductorWorkingDirectory in
# conductor-watchdog.ps1) treats $null/unrecognizable output as "unknown,
# not excluded" -- a bad read here can only under-filter (fall back to the
# other signals), never wrongly hide a real duplicate.

if (-not ('ConductorWatchdog.NativeProcess' -as [type])) {
    Add-Type -Namespace ConductorWatchdog -Name NativeProcess -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true)]
public static extern IntPtr OpenProcess(uint dwDesiredAccess, bool bInheritHandle, int dwProcessId);

[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool CloseHandle(IntPtr hObject);

[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool ReadProcessMemory(IntPtr hProcess, IntPtr lpBaseAddress, byte[] lpBuffer, int dwSize, out IntPtr lpNumberOfBytesRead);

[DllImport("ntdll.dll")]
public static extern int NtQueryInformationProcess(IntPtr processHandle, int processInformationClass, byte[] processInformation, int processInformationLength, out int returnLength);
'@
}

function Get-ProcessWorkingDirectory {
    param([Parameter(Mandatory)][int]$ProcessId)

    $PROCESS_QUERY_INFORMATION = 0x0400
    $PROCESS_VM_READ = 0x0010
    $hProcess = [ConductorWatchdog.NativeProcess]::OpenProcess($PROCESS_QUERY_INFORMATION -bor $PROCESS_VM_READ, $false, $ProcessId)
    if ($hProcess -eq [IntPtr]::Zero) { return $null }
    try {
        # PROCESS_BASIC_INFORMATION on x64: 6 pointer-sized fields (48 bytes);
        # field[1] (offset 8) is PebBaseAddress.
        $pbi = New-Object byte[] 48
        $retLen = 0
        $status = [ConductorWatchdog.NativeProcess]::NtQueryInformationProcess($hProcess, 0, $pbi, $pbi.Length, [ref]$retLen)
        if ($status -ne 0) { return $null }
        $pebAddress = [BitConverter]::ToInt64($pbi, 8)

        # PEB.ProcessParameters lives at offset 0x20 on x64.
        $ptrBuf = New-Object byte[] 8
        $bytesRead = [IntPtr]::Zero
        if (-not [ConductorWatchdog.NativeProcess]::ReadProcessMemory($hProcess, [IntPtr]($pebAddress + 0x20), $ptrBuf, 8, [ref]$bytesRead)) { return $null }
        $paramsAddress = [BitConverter]::ToInt64($ptrBuf, 0)

        # RTL_USER_PROCESS_PARAMETERS.CurrentDirectory (a CURDIR: a
        # UNICODE_STRING DosPath then a handle) sits at offset 0x38 on x64.
        # UNICODE_STRING = { USHORT Length; USHORT MaximumLength; (4 pad);
        # PWSTR Buffer } -- 16 bytes.
        $curDirBuf = New-Object byte[] 16
        if (-not [ConductorWatchdog.NativeProcess]::ReadProcessMemory($hProcess, [IntPtr]($paramsAddress + 0x38), $curDirBuf, 16, [ref]$bytesRead)) { return $null }
        $length = [BitConverter]::ToUInt16($curDirBuf, 0)
        $bufferAddress = [BitConverter]::ToInt64($curDirBuf, 8)
        if ($length -le 0 -or $bufferAddress -eq 0) { return $null }

        $strBuf = New-Object byte[] $length
        if (-not [ConductorWatchdog.NativeProcess]::ReadProcessMemory($hProcess, [IntPtr]$bufferAddress, $strBuf, $length, [ref]$bytesRead)) { return $null }
        return [Text.Encoding]::Unicode.GetString($strBuf)
    }
    catch {
        return $null
    }
    finally {
        [ConductorWatchdog.NativeProcess]::CloseHandle($hProcess) | Out-Null
    }
}
