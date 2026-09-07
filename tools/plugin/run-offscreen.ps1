#Requires -Version 7
<#
.SYNOPSIS
Run a test suite on a Windows desktop that is never shown on the monitor. Same suite, same
arguments, same assertions -- the only difference is which desktop the process is born on.

.DESCRIPTION
A process is BORN on the desktop named in `STARTUPINFO.lpDesktop` and every thread of it is
on that desktop by default -- the same mechanism scinject.exe's `--desktop` uses for the
game. Window enumeration (`EnumWindows`, under drive-game.ps1's Get-ScGameWindow,
check-game-windows.ps1 and close-game.ps1) is scoped to the calling thread's desktop, so the
whole harness follows the game across with no per-primitive change. A running shell cannot
move itself instead: `SetThreadDesktop` refuses for a thread that already has a window or a
hook, which PowerShell's main thread does before any script runs (in a plain
`pwsh -NoProfile`: main thread -> False, err=170 ERROR_BUSY; a fresh thread -> OK).

The suites are unmodified, byte for byte the scripts that run on the visible desktop: a
suite that "passes" off-screen while silently doing less is the failure mode to guard
against, and the cheapest guard is that no off-screen variant of it exists. Launches stay
serialised by sc-launch-lock.ps1 either way -- StarCraft is single-instance PER MACHINE
regardless of desktops (research/automated-testing-options.md §6, AGENTS.md § "Launch
lock"), so N invisible desktops still mean one game at a time.

The child's stdout and stderr are redirected to a transcript file and tailed here live; the
transcript stays afterwards, and the child's exit code is this script's exit code.

.PARAMETER Visible
Run on the desktop that IS on the monitor -- the debugging run a human watches. Identical
in every other respect, cursor-clip watch included.

.PARAMETER Desktop
Name the desktop explicitly instead of generating one per run. Mostly for a second process
that needs to join a run already in progress.

.EXAMPLE
./tools/plugin/run-offscreen.ps1 -Suite ./tools/plugin/test-selection-circles.ps1 `
    -SuiteArgs @{ ShotDir = 'C:\sc-work\logs\frames' }
A frame reproduces game artwork, so a suite's frames stay a diagnostic on a gitignored path
under C:\sc-work\ whatever desktop the run is on (AGENTS.md § "Screenshots").

.EXAMPLE
# Anything, not only a suite -- used by probe-cross-desktop-input.ps1:
./tools/plugin/run-offscreen.ps1 -Command '(Get-Process StarCraft).Count'
#>
[CmdletBinding(DefaultParameterSetName = 'Suite')]
param(
    [Parameter(ParameterSetName = 'Suite', Mandatory, Position = 0)]
    [string]$Suite,
    # Splatted into the suite, so the keys are spelled exactly as the suite spells its
    # parameters (the convention time-suite.ps1 uses too).
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

    // The cursor clip (issue #135). ClipCursor confines the PHYSICAL cursor for the whole
    // session whatever desktop the caller's window sits on, so a game on the invisible
    // desktop that clips (cnc-ddraw's button-up lock, the engine's activation clip) pins
    // the user's real mouse to a rectangle nobody can see. Read from here, released from here.
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int left, top, right, bottom; }
    [DllImport("user32.dll", SetLastError=true)] public static extern bool GetClipCursor(out RECT r);
    [DllImport("user32.dll", SetLastError=true)] public static extern bool ClipCursor(IntPtr r);
    [DllImport("user32.dll")] public static extern int GetSystemMetrics(int n);

    private const uint GENERIC_WRITE = 0x40000000, GENERIC_READ = 0x80000000;
    private const uint FILE_SHARE_READ = 1, FILE_SHARE_WRITE = 2, FILE_SHARE_DELETE = 4;
    private const uint CREATE_ALWAYS = 2, OPEN_EXISTING = 3;
    private const uint STARTF_USESTDHANDLES = 0x00000100;
    private const uint CREATE_NO_WINDOW = 0x08000000;
    private const uint CREATE_UNICODE_ENVIRONMENT = 0x00000400;

    public static IntPtr LastProcess = IntPtr.Zero;
    public static int    LastPid     = 0;
    public static string LastError   = null;

    // Starts `cmdLine` on the named desktop with stdout+stderr going to `outPath` and
    // stdin bound to NUL. Returns the pid, or 0 with LastError set.
    //
    // The console: CREATE_NO_WINDOW, not CREATE_NEW_CONSOLE (2026-08-12, task 045). The old
    // CREATE_NEW_CONSOLE flag was assumed to keep its console on the child's own (invisible)
    // desktop because STARTUPINFO.lpDesktop names that desktop -- but on Windows 11, with the
    // per-user console delegation at its default (`HKCU:\Console\%%Startup`
    // DelegationConsole/DelegationTerminal both the all-zero "let Windows decide" GUID), a
    // new console is handed off to Windows Terminal, a GUI app running on the user's own
    // INTERACTIVE desktop that does not honour lpDesktop for where it draws. Measured live: a
    // tight loop of spawns put a flashing, focus-stealing terminal on the user's screen even
    // though every child's `GetInputDesktopName()` genuinely differed from its own desktop
    // the whole time (work/messages/conductor -- "I killed your 50x repro loop").
    //
    // DETACHED_PROCESS (no console at all) was tried first and rejected: pwsh's ConsoleHost
    // queries real console APIs (screen buffer info, window size) during its OWN startup,
    // before user script code runs at all, and with no console object to answer them the host
    // never reaches the script -- confirmed with a marker file written by the child's own
    // first line, which never appeared, while GetExitCodeProcess still reported a clean 0. A
    // child that never ran and reports success is the exact false-green shape this task
    // exists to kill, from a second direction. CREATE_NO_WINDOW is what MSDN documents as
    // "console app, no window" -- proof in this task's PR rests on two measurements, not on
    // that description: a marker file confirms the script itself ran end to end, and
    // conhost.exe/WindowsTerminal.exe process counts are unchanged across the spawn (19/19).
    // (The child's own GetConsoleWindow() reads NULL under this flag, which is a further
    // observation, not the mechanism the claim rests on -- the process counts are.)
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
                               CREATE_NO_WINDOW | CREATE_UNICODE_ENVIRONMENT,
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
# Outside the repo, like every other artifact of a run: a transcript is scratch, and the
# shared scratch root is the one place every launch already uses.
$runRoot = 'C:\sc-work\logs\offscreen'
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
$stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
$tag = if ($Suite) { [IO.Path]::GetFileNameWithoutExtension($Suite) } else { 'command' }
if (-not $TranscriptPath) { $TranscriptPath = Join-Path $runRoot "$stamp-$tag.txt" }

$repoRoot = (Resolve-Path (Join-Path $scriptDir '..' '..')).Path

# --- the child script ---------------------------------------------------------
# Generated as a real file rather than an -EncodedCommand so that a failed run leaves
# something a human can open and re-run by hand.
$childScript = Join-Path $runRoot "$stamp-$tag-child.ps1"
$argsFile = Join-Path $runRoot "$stamp-$tag-args.clixml"

if ($PSCmdlet.ParameterSetName -eq 'Suite') {
    if (-not (Test-Path -LiteralPath $Suite)) { throw "run-offscreen: no such suite: $Suite" }
    $suiteFull = (Resolve-Path -LiteralPath $Suite).Path
    # Clixml rather than a command line: a suite's arguments include hashtables, switches
    # and paths with spaces, and quoting those through two layers of shell is how a run ends
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
        # THE SAME CODE PATH: not a branch that skips the spawn, but the same CreateProcess
        # with the same redirection, named at the desktop the monitor is showing. A watch
        # mode that diverged here would hide bugs that only exist when nobody is looking.
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
    # The virtual screen is what an UNCLIPPED cursor reads back (SM_XVIRTUALSCREEN 76,
    # SM_YVIRTUALSCREEN 77, SM_CXVIRTUALSCREEN 78, SM_CYVIRTUALSCREEN 79). Anything smaller
    # is a clip a window of the run placed on the user's real mouse: cnc-ddraw re-arms its
    # mouse lock on every button-up, i.e. on every posted click, and the engine's own clip
    # reset at 0x004215E0 runs on activation, which the menu walk's WM_ACTIVATEAPP nudges
    # fake -- pinning a physical cursor to a rectangle on a desktop nobody can see. Counting
    # what it releases makes the summary a measurement: a 0 is believable only because runs
    # that did clip print their rects.
    $vs = [ScSpawn.Native]::GetSystemMetrics(76), [ScSpawn.Native]::GetSystemMetrics(77),
          [ScSpawn.Native]::GetSystemMetrics(78), [ScSpawn.Native]::GetSystemMetrics(79)
    $vsRect = @{ left = $vs[0]; top = $vs[1]; right = $vs[0] + $vs[2]; bottom = $vs[1] + $vs[3] }
    $clipsFound = 0
    $clipLines = 0
    while ($true) {
        $running = ([ScSpawn.Native]::WaitForSingleObject($hProc, 100) -ne 0)   # WAIT_OBJECT_0 == 0
        $rc = New-Object 'ScSpawn.Native+RECT'
        if ([ScSpawn.Native]::GetClipCursor([ref]$rc) -and
            ($rc.left -gt $vsRect.left -or $rc.top -gt $vsRect.top -or
             $rc.right -lt $vsRect.right -or $rc.bottom -lt $vsRect.bottom)) {
            $clipsFound++
            [void][ScSpawn.Native]::ClipCursor([IntPtr]::Zero)
            $after = New-Object 'ScSpawn.Native+RECT'
            [void][ScSpawn.Native]::GetClipCursor([ref]$after)
            $freed = ($after.left -le $vsRect.left -and $after.top -le $vsRect.top -and
                      $after.right -ge $vsRect.right -and $after.bottom -ge $vsRect.bottom)
            if ($clipLines -lt 20 -or -not $freed) {
                $clipLines++
                Write-Host ("run-offscreen: cursor clip #{0} found ({1},{2})-({3},{4}) -> {5}" -f $clipsFound,
                    $rc.left, $rc.top, $rc.right, $rc.bottom,
                    ($freed ? 'released (reads the full virtual screen again)' : "NOT released: still ($($after.left),$($after.top))-($($after.right),$($after.bottom))"))
            }
        }
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
            # The child's own `finally` closes the game, and killing it skips that teardown.
            Write-Warning 'run-offscreen: the suite''s teardown did NOT run — check for a surviving StarCraft process before starting another run.'
            [void][ScSpawn.Native]::TerminateProcess($hProc, 258)
            break
        }
    }

    $code = 0
    [void][ScSpawn.Native]::GetExitCodeProcess($hProc, [ref]$code)
    # GetExitCodeProcess returns a DWORD, and a checked `[int]` cast throws OverflowException
    # above Int32.MaxValue -- exactly what a host FailFast exit code is (a PowerShell host
    # crash, or `[Environment]::FailFast()`, exits 2148734499 / 0x80131623). That throw would
    # escape this script without reaching `exit`, leaving $LASTEXITCODE holding whatever ran
    # before -- often a stale 0 that reads as a pass. Reinterpreting the bits cannot throw and
    # is a no-op for any code that fits in Int32 (every ordinary suite exit).
    $exit = [BitConverter]::ToInt32([BitConverter]::GetBytes($code), 0)
    # A clip placed between the final tick and the child's exit outlives the run otherwise,
    # leaving the user to free their own mouse with an Alt-Tab.
    [void][ScSpawn.Native]::ClipCursor([IntPtr]::Zero)
    Write-Host ('-' * 70)
    Write-Host "run-offscreen: cursor clip: $clipsFound clip(s) of the real mouse found and released during the run (issue #135; 0 = never confined)"
    Write-Host "run-offscreen: child pid $childPid exited $exit (desktop '$desktopName')"
    Write-Host "run-offscreen: transcript $TranscriptPath"

    # The child's very first act, before any suite or command payload, is to print its own
    # "run-offscreen(child):" header line. A missing line means the child died at HOST
    # STARTUP -- e.g. racing a desktop still being torn down makes PowerShell FailFast at
    # console-buffer setup with Win32 0xE9, "No process is on the other end of the pipe."
    # Nothing it was asked to test ran, so that is a FAILURE, never a silent zero.
    $transcriptText = if (Test-Path -LiteralPath $TranscriptPath) { Get-Content -LiteralPath $TranscriptPath -Raw -ErrorAction SilentlyContinue } else { $null }
    $childStarted = $transcriptText -and ($transcriptText -match 'run-offscreen\(child\):')
    if (-not $childStarted) {
        Write-Error "run-offscreen: child pid $childPid exited $exit WITHOUT running any suite code -- no 'run-offscreen(child):' line in the transcript. This is the host-startup-crash signature (e.g. Win32 0xE9, 'No process is on the other end of the pipe.'), not a test result. Transcript: $TranscriptPath"
        exit $(if ($exit -ne 0) { $exit } else { 1 })
    }

    exit $exit
}
finally {
    if ([ScSpawn.Native]::LastProcess -ne [IntPtr]::Zero) {
        [void][ScSpawn.Native]::CloseHandle([ScSpawn.Native]::LastProcess)
        [ScSpawn.Native]::LastProcess = [IntPtr]::Zero
    }
    if ($owned) { Close-ScTestDesktop }
}
