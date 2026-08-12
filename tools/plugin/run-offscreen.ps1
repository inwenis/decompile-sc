#Requires -Version 7
<#
.SYNOPSIS
Run a test suite on a Windows desktop that is never shown on the monitor. Same suite, same
arguments, same assertions -- the only difference is which desktop the process is born on.

.DESCRIPTION
Task 043. The user's ask, in their words: *"can we setup a vm so you can run tests there so
my screen doesn't get messed up?"* Task 040 found the mechanism that needs no VM at all (an
invisible Windows desktop, `work/reports/040-test-host-isolation.md`); this is the thing
that makes it how the suite actually runs.

    ./tools/plugin/run-offscreen.ps1 -Suite ./tools/plugin/test-selection-circles.ps1
    ./tools/plugin/run-offscreen.ps1 -Suite ./tools/plugin/test-selection-circles.ps1 -Visible

The second is the debugging run a human wants to watch. It is ONE FLAG and it is the SAME
CODE PATH -- the same generated child script, the same CreateProcess call, the same suite
with the same arguments; only the desktop name differs. A separate "watch mode" that
diverged from how tests really run is how you get a bug that only exists when nobody is
looking, so there is not one here.

## Why a child process rather than "just call SetThreadDesktop"

Measured, task 043, in a plain `pwsh -NoProfile`:

    main thread  : SetThreadDesktop -> False, err=170 (ERROR_BUSY)
    fresh thread : SetThreadDesktop -> OK

`SetThreadDesktop` refuses for a thread that already has a window or a hook, and
PowerShell's main thread has one before any script runs. So a running shell cannot move
itself onto the desktop, and the "make every drive-game.ps1 primitive desktop-aware"
approach has nowhere to stand.

A process is instead BORN on a desktop, named in `STARTUPINFO.lpDesktop` -- exactly what
scinject.exe's `--desktop` (task 040, PR #49) does for the game. Every thread of that
process is on that desktop by default. That is also the property worth having: window
enumeration (`EnumWindows`, used by drive-game.ps1's Get-ScGameWindow, by
check-game-windows.ps1 and by close-game.ps1) is scoped to the calling thread's desktop, so
the entire existing harness follows the game across with NO per-primitive changes and no
list of primitives to be one item short of.

Consequently the suites are unmodified. `test-selection-circles.ps1` run through this is
byte-for-byte the script that runs on the visible desktop -- which is the point: a suite
that "passes" off-screen while silently doing less is the failure mode this task has to
guard against, and the cheapest guard is that there is no off-screen variant of it.

## What this does not change

* `sc-launch-lock.ps1` still serialises launches. StarCraft is single-instance PER MACHINE
  regardless of desktops (research/automated-testing-options.md §6, re-confirmed by task
  040), so N invisible desktops still means one game at a time. Nothing here touches that.
* The game's own frames stay a diagnostic on the gitignored path. Off-screen or not, a
  frame reproduces game artwork (AGENTS.md hard rule 1 / "Screenshots vs hard rule 1").

## Output

The child's stdout and stderr are redirected to a transcript file and tailed here live, so
this behaves like running the suite directly. The transcript stays afterwards. The child's
exit code is this script's exit code.

.PARAMETER Visible
Run on the desktop that IS on the monitor -- the debugging path. Everything else is
identical.

.PARAMETER Desktop
Name the desktop explicitly instead of generating one per run. Mostly for a second process
that needs to join a run already in progress.

.EXAMPLE
./tools/plugin/run-offscreen.ps1 -Suite ./tools/plugin/test-selection-circles.ps1 `
    -SuiteArgs @{ ShotDir = 'C:\sc-work\logs\043-frames' }

.EXAMPLE
# Anything, not only a suite -- used by probe-cross-desktop-input.ps1:
./tools/plugin/run-offscreen.ps1 -Command '(Get-Process StarCraft).Count'
#>
[CmdletBinding(DefaultParameterSetName = 'Suite')]
param(
    [Parameter(ParameterSetName = 'Suite', Mandatory, Position = 0)]
    [string]$Suite,
    # Splatted into the suite -- a hashtable, spelled exactly as the suite spells its
    # parameters. Same convention as time-suite.ps1.
    [Parameter(ParameterSetName = 'Suite')]
    [hashtable]$SuiteArgs = @{},

    [Parameter(ParameterSetName = 'Command', Mandatory)]
    [string]$Command,

    [switch]$Visible,
    [string]$Desktop,
    [string]$TranscriptPath,
    [int]$TimeoutMinutes = 30
)

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
. (Join-Path $scriptDir 'sc-desktop.ps1')

if (-not ('ScSpawn.Native' -as [type])) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace ScSpawn {
  public static class Native {
    [StructLayout(LayoutKind.Sequential)]
    public struct SECURITY_ATTRIBUTES { public int nLength; public IntPtr lpSecurityDescriptor; public bool bInheritHandle; }

    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    public struct STARTUPINFO {
      public int cb; public string lpReserved; public string lpDesktop; public string lpTitle;
      public int dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute;
      public int dwFlags; public short wShowWindow; public short cbReserved2;
      public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct PROCESS_INFORMATION { public IntPtr hProcess, hThread; public int dwProcessId, dwThreadId; }

    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    private static extern bool CreateProcessW(string app, StringBuilder cmdLine,
        IntPtr procAttrs, IntPtr threadAttrs, bool inheritHandles, uint flags,
        IntPtr env, string curDir, ref STARTUPINFO si, out PROCESS_INFORMATION pi);

    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    private static extern IntPtr CreateFileW(string name, uint access, uint share,
        ref SECURITY_ATTRIBUTES sa, uint disposition, uint flags, IntPtr template);

    [DllImport("kernel32.dll", SetLastError=true)] public static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll", SetLastError=true)] public static extern uint WaitForSingleObject(IntPtr h, uint ms);
    [DllImport("kernel32.dll", SetLastError=true)] public static extern bool GetExitCodeProcess(IntPtr h, out uint code);
    [DllImport("kernel32.dll", SetLastError=true)] public static extern bool TerminateProcess(IntPtr h, uint code);

    private const uint GENERIC_WRITE = 0x40000000, GENERIC_READ = 0x80000000;
    private const uint FILE_SHARE_READ = 1, FILE_SHARE_WRITE = 2, FILE_SHARE_DELETE = 4;
    private const uint CREATE_ALWAYS = 2, OPEN_EXISTING = 3;
    private const uint STARTF_USESTDHANDLES = 0x00000100;
    private const uint CREATE_NEW_CONSOLE = 0x00000010;
    private const uint CREATE_UNICODE_ENVIRONMENT = 0x00000400;

    public static IntPtr LastProcess = IntPtr.Zero;
    public static int    LastPid     = 0;
    public static string LastError   = null;

    // Starts `cmdLine` on the named desktop with stdout+stderr going to `outPath` and
    // stdin bound to NUL. Returns the pid, or 0 with LastError set.
    //
    // The console: CREATE_NEW_CONSOLE, not DETACHED_PROCESS. A console app on a desktop
    // where nothing is displayed still wants one, and inheriting the PARENT's console
    // would put the child's console I/O on the parent's desktop -- the one thing this is
    // trying to avoid. The new console is created on the child's desktop, where nobody
    // ever sees it; its stdout/stderr are redirected to the transcript regardless.
    public static int Start(string cmdLine, string desktop, string outPath, string workDir) {
      LastError = null;
      var sa = new SECURITY_ATTRIBUTES();
      sa.nLength = Marshal.SizeOf(typeof(SECURITY_ATTRIBUTES));
      sa.lpSecurityDescriptor = IntPtr.Zero;
      sa.bInheritHandle = true;   // the whole reason for hand-rolling this: the child must inherit these

      IntPtr hOut = CreateFileW(outPath, GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                                ref sa, CREATE_ALWAYS, 0, IntPtr.Zero);
      if (hOut == (IntPtr)(-1)) { LastError = "CreateFile(" + outPath + ") failed, Win32 " + Marshal.GetLastWin32Error(); return 0; }

      IntPtr hNul = CreateFileW("NUL", GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE,
                                ref sa, OPEN_EXISTING, 0, IntPtr.Zero);
      if (hNul == (IntPtr)(-1)) { CloseHandle(hOut); LastError = "CreateFile(NUL) failed, Win32 " + Marshal.GetLastWin32Error(); return 0; }

      var si = new STARTUPINFO();
      si.cb = Marshal.SizeOf(typeof(STARTUPINFO));
      si.lpDesktop = desktop;              // <-- the entire mechanism
      si.dwFlags = (int)STARTF_USESTDHANDLES;
      si.hStdInput = hNul; si.hStdOutput = hOut; si.hStdError = hOut;

      PROCESS_INFORMATION pi;
      var cl = new StringBuilder(cmdLine, cmdLine.Length + 8);   // CreateProcessW may write to it
      bool ok = CreateProcessW(null, cl, IntPtr.Zero, IntPtr.Zero, true,
                               CREATE_NEW_CONSOLE | CREATE_UNICODE_ENVIRONMENT,
                               IntPtr.Zero, workDir, ref si, out pi);
      int err = Marshal.GetLastWin32Error();
      CloseHandle(hOut); CloseHandle(hNul);   // ours are done; the child holds its own copies
      if (!ok) { LastError = "CreateProcess failed, Win32 " + err; return 0; }

      CloseHandle(pi.hThread);
      LastProcess = pi.hProcess;
      LastPid = pi.dwProcessId;
      return pi.dwProcessId;
    }
  }
}
'@ -ReferencedAssemblies System.Runtime, System.Runtime.InteropServices
}

# --- where the run happens ----------------------------------------------------
# Outside the repo, like every other artifact of a run: transcripts of a game test are
# scratch, and the shared scratch root is the one place every launch already uses.
$runRoot = 'C:\sc-work\logs\offscreen'
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
$stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
$tag = if ($Suite) { [IO.Path]::GetFileNameWithoutExtension($Suite) } else { 'command' }
if (-not $TranscriptPath) { $TranscriptPath = Join-Path $runRoot "$stamp-$tag.txt" }

$repoRoot = (Resolve-Path (Join-Path $scriptDir '..' '..')).Path

# --- the child script ---------------------------------------------------------
# Generated as a real file rather than an -EncodedCommand so that a failed run leaves
# something a human can open and re-run by hand. It does three things: prove where it is,
# splat the caller's arguments into the suite unchanged, and propagate the exit code.
$childScript = Join-Path $runRoot "$stamp-$tag-child.ps1"
$argsFile = Join-Path $runRoot "$stamp-$tag-args.clixml"

if ($PSCmdlet.ParameterSetName -eq 'Suite') {
    if (-not (Test-Path -LiteralPath $Suite)) { throw "run-offscreen: no such suite: $Suite" }
    $suiteFull = (Resolve-Path -LiteralPath $Suite).Path
    # Clixml rather than a command line: a suite's arguments include hashtables, switches
    # and paths with spaces, and quoting them through two layers of shell is how a run ends
    # up silently testing something else.
    $SuiteArgs | Export-Clixml -LiteralPath $argsFile -Depth 8
    $payload = @"
`$a = Import-Clixml -LiteralPath '$argsFile'
& '$suiteFull' @a
exit `$(if (`$null -ne `$LASTEXITCODE) { `$LASTEXITCODE } else { 0 })
"@
}
else {
    $payload = @"
$Command
exit `$(if (`$null -ne `$LASTEXITCODE) { `$LASTEXITCODE } else { 0 })
"@
}

$header = @"
# Generated by run-offscreen.ps1 at $stamp. Safe to read, safe to re-run by hand
# (it will then run on whatever desktop your shell is on).
`$ErrorActionPreference = 'Stop'
. '$(Join-Path $scriptDir 'sc-desktop.ps1')'
$(if ($Visible) {
'# -Visible: this run is SUPPOSED to be on the monitor, so there is nothing to assert --
# only to report, in the same words, so the two transcripts are comparable.'
} else {
'# Proves from INSIDE the run that it is where it was supposed to be. An off-screen run that
# quietly landed on the visible desktop produces identical output otherwise.
Assert-ScDesktopHidden | Out-Null'
})
Write-Host "run-offscreen(child): desktop='`$(Get-ScThreadDesktopName)' monitor='`$(Get-ScInputDesktopName)' pid=`$PID"

"@
Set-Content -LiteralPath $childScript -Value ($header + $payload) -Encoding UTF8

# --- the desktop --------------------------------------------------------------
$desktopName = $null
$owned = $false
try {
    if ($Visible) {
        # THE SAME CODE PATH. Not a branch that skips the spawn -- the same CreateProcess
        # with the same redirection, named at the desktop the monitor is showing.
        $desktopName = Get-ScInputDesktopName
        if (-not $desktopName) { $desktopName = 'Default' }
        Write-Host "run-offscreen: -Visible — running on '$desktopName', the desktop on the monitor. You will see this run."
    }
    else {
        if (-not $Desktop) { $Desktop = New-ScTestDesktopName }
        $desktopName = New-ScTestDesktop -Name $Desktop
        $owned = $true
    }

    $pwsh = (Get-Process -Id $PID).Path      # the same PowerShell that is running this
    $cmdLine = '"{0}" -NoProfile -NoLogo -ExecutionPolicy Bypass -File "{1}"' -f $pwsh, $childScript

    Write-Host "run-offscreen: $(if ($Suite) { $Suite } else { 'command' }) -> desktop '$desktopName'"
    Write-Host "run-offscreen: transcript $TranscriptPath"

    $childPid = [ScSpawn.Native]::Start($cmdLine, $desktopName, $TranscriptPath, $repoRoot)
    if ($childPid -eq 0) { throw "run-offscreen: could not start the run — $([ScSpawn.Native]::LastError)" }
    $hProc = [ScSpawn.Native]::LastProcess
    Write-Host "run-offscreen: child pid $childPid"
    Write-Host ('-' * 70)

    # --- tail the transcript while the child runs -----------------------------
    # FileShare.ReadWrite|Delete so this read can never be the thing that fails the child's
    # write, and so the child's own handle stays usable.
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    $pos = 0L
    $exit = $null
    while ($true) {
        $running = ([ScSpawn.Native]::WaitForSingleObject($hProc, 300) -ne 0)   # WAIT_OBJECT_0 == 0
        if (Test-Path -LiteralPath $TranscriptPath) {
            $fs = $null
            try {
                $fs = [IO.File]::Open($TranscriptPath, [IO.FileMode]::Open, [IO.FileAccess]::Read,
                                      [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
                if ($fs.Length -gt $pos) {
                    [void]$fs.Seek($pos, [IO.SeekOrigin]::Begin)
                    $sr = [IO.StreamReader]::new($fs)
                    $chunk = $sr.ReadToEnd()
                    $pos = $fs.Length
                    foreach ($l in ($chunk -split "`r?`n")) { if ($l -ne '') { Write-Host $l } }
                }
            }
            catch { }   # a momentarily-locked transcript is not a failed run; the next tick re-reads
            finally { if ($fs) { $fs.Dispose() } }
        }
        if (-not $running) { break }
        if ((Get-Date) -ge $deadline) {
            Write-Warning "run-offscreen: the run exceeded -TimeoutMinutes $TimeoutMinutes; terminating child pid $childPid."
            # The child's own `finally` closes the game; killing it skips that, so say so
            # loudly rather than leaving a reader to assume a clean teardown happened.
            Write-Warning 'run-offscreen: the suite''s teardown did NOT run — check for a surviving StarCraft process before starting another run.'
            [void][ScSpawn.Native]::TerminateProcess($hProc, 258)
            break
        }
    }

    $code = 0
    [void][ScSpawn.Native]::GetExitCodeProcess($hProc, [ref]$code)
    $exit = [int]$code
    Write-Host ('-' * 70)
    Write-Host "run-offscreen: child pid $childPid exited $exit (desktop '$desktopName')"
    Write-Host "run-offscreen: transcript $TranscriptPath"
    exit $exit
}
finally {
    if ([ScSpawn.Native]::LastProcess -ne [IntPtr]::Zero) {
        [void][ScSpawn.Native]::CloseHandle([ScSpawn.Native]::LastProcess)
        [ScSpawn.Native]::LastProcess = [IntPtr]::Zero
    }
    if ($owned) { Close-ScTestDesktop }
}
