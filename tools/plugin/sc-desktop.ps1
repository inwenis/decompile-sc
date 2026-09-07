<#
.SYNOPSIS
Create a Windows desktop that is never shown on the monitor, and tell whether the caller
is on it.

.DESCRIPTION
A process born on a second desktop object runs normally -- same login session, same GPU --
but is not the desktop composited to the screen, and Windows destroys the object once the
last handle closes and the last process on it exits. A desktop cannot be ENTERED after the
fact: `SetThreadDesktop` fails with err=170 (ERROR_BUSY) for a thread that already owns a
window or a hook, and PowerShell's main thread owns one before the first line of script
runs. So the PARENT creates the desktop and holds the handle, while the CHILD is born on it
via `STARTUPINFO.lpDesktop` and can only check where it is -- birth also scopes `EnumWindows`
to that desktop for every thread the child starts, so no per-primitive list can fall short.
`SwitchDesktop` is deliberately never imported and the handle is opened without
DESKTOP_SWITCHDESKTOP (see $SC_DESKTOP_ACCESS), so nothing reachable from here can put the
invisible desktop on the monitor. Dot-source it; nothing may run on import, because
run-with-plugin.ps1 -- the user's own deployed play launcher -- loads this file on every
launch.

.EXAMPLE
. ./tools/plugin/sc-desktop.ps1
$name = New-ScTestDesktop -Name (New-ScTestDesktopName)
# ... spawn the run onto $name ...
Close-ScTestDesktop
#>

Set-StrictMode -Version Latest

if (-not ('ScDesktop.Native' -as [type])) {
    # A LITERAL here-string (@'...'@): an expandable one would interpolate anything in the
    # C# source that looks like a PowerShell variable.
    Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace ScDesktop {
  public static class Native {
    [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern IntPtr CreateDesktopW(string name, IntPtr device, IntPtr devmode,
                                               uint flags, uint access, IntPtr sa);
    [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern IntPtr OpenDesktopW(string name, uint flags, bool inherit, uint access);
    [DllImport("user32.dll", SetLastError=true)] public static extern bool CloseDesktop(IntPtr h);
    [DllImport("user32.dll", SetLastError=true)] public static extern bool SetThreadDesktop(IntPtr h);
    [DllImport("user32.dll", SetLastError=true)] public static extern IntPtr GetThreadDesktop(uint threadId);
    [DllImport("user32.dll", SetLastError=true)] public static extern IntPtr OpenInputDesktop(uint flags, bool inherit, uint access);
    [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    private static extern bool GetUserObjectInformationW(IntPtr h, int index, StringBuilder buf,
                                                         uint len, out uint needed);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();

    // NOTE: SwitchDesktop is deliberately absent. See the .DESCRIPTION above.

    private const int UOI_NAME = 2;

    public static string NameOf(IntPtr hdesk) {
      if (hdesk == IntPtr.Zero) return null;
      var sb = new StringBuilder(256);
      uint needed;
      if (!GetUserObjectInformationW(hdesk, UOI_NAME, sb, (uint)(sb.Capacity * 2), out needed)) return null;
      return sb.ToString();
    }

    // Process-global on purpose: "which desktop is this run on" is one answer per process,
    // and both run-offscreen.ps1 and run-with-plugin.ps1 dot-source this file -- possibly
    // into different PowerShell scopes, where a script-scoped variable would be two
    // variables holding two different answers.
    public static IntPtr Owned = IntPtr.Zero;
    public static string OwnedName = null;
  }
}
'@ -ReferencedAssemblies System.Runtime, System.Runtime.InteropServices
}

# Every desktop right EXCEPT DESKTOP_SWITCHDESKTOP (0x0100), enumerated rather than written
# as GENERIC_ALL so the omission stays visible:
#   0x0001 READOBJECTS    0x0002 CREATEWINDOW  0x0004 CREATEMENU  0x0008 HOOKCONTROL
#   0x0010 JOURNALRECORD  0x0020 JOURNALPLAYBACK  0x0040 ENUMERATE  0x0080 WRITEOBJECTS
# CREATEWINDOW is what a process born here needs; ENUMERATE makes EnumWindows work for a
# thread on it; READOBJECTS/WRITEOBJECTS cover message posting and the PrintWindow read.
# Without SWITCHDESKTOP -- and with `SwitchDesktop` never imported above -- no path from
# this handle can put the invisible desktop on the monitor, whatever it asks for.
$script:SC_DESKTOP_ACCESS = 0x00FF

function New-ScTestDesktopName {
    <#
    .SYNOPSIS
    A desktop name unique to this CALL, so N parallel workers never collide and neither do
    two steps of one chain run from a single shell.
    .DESCRIPTION
    Desktop names live in one flat namespace per window station, so a single fixed name
    recreates the contention a shared fixture folder has (AGENTS.md § "Test fixtures").
    Tag + pid is unique per parallel WORKER but not per step of a chain run from one shell:
    every step shares the pid, so a later step asks for the desktop an earlier one is still
    tearing down and races its destruction. The GUID suffix makes every call unique however
    many share a pid; the pid stays in the name so the owner is visible to anyone listing
    desktops.
    #>
    param([string]$Tag = $(if ($env:AGENT_TASK) { $env:AGENT_TASK } else { 'sc' }))
    # Letters and digits only -- a backslash in a desktop name would name a window station.
    $safe = ($Tag -replace '[^A-Za-z0-9]', '')
    if (-not $safe) { $safe = 'sc' }
    "sc-$safe-$PID-$([Guid]::NewGuid().ToString('N').Substring(0, 8))"
}

function Get-ScThreadDesktopName {
    <#
    .SYNOPSIS
    The name of the desktop THIS THREAD is on -- the diagnostic that makes every claim in
    this file checkable rather than asserted.
    #>
    [ScDesktop.Native]::NameOf([ScDesktop.Native]::GetThreadDesktop([ScDesktop.Native]::GetCurrentThreadId()))
}

function Get-ScInputDesktopName {
    <#
    .SYNOPSIS
    The name of the desktop actually being shown on the monitor right now.
    .DESCRIPTION
    `OpenInputDesktop` names whichever desktop is receiving physical input and compositing
    to the screen. "Invisible" is not a property to claim, it is a comparison against the
    thing Windows itself calls visible.

    Returns $null when the input desktop cannot be opened (a locked workstation, or a secure
    desktop up). A null is not evidence either way, and Assert-ScDesktopHidden treats it as
    such rather than as a pass.
    #>
    $h = [ScDesktop.Native]::OpenInputDesktop(0, $false, 0x0001)  # DESKTOP_READOBJECTS
    if ($h -eq [IntPtr]::Zero) { return $null }
    try { [ScDesktop.Native]::NameOf($h) } finally { [void][ScDesktop.Native]::CloseDesktop($h) }
}

function Assert-ScDesktopHidden {
    <#
    .SYNOPSIS
    Throw if the desktop this thread is on IS the one on the monitor.
    .DESCRIPTION
    Called by the CHILD at the top of an off-screen run, the one point where the claim can
    still be acted on: a run that quietly landed on the visible desktop looks identical in
    its output to one that did not.

    Returns the name of the desktop this thread is on.
    #>
    param([switch]$Quiet)
    $mine  = Get-ScThreadDesktopName
    $shown = Get-ScInputDesktopName
    if ($null -eq $shown) {
        if (-not $Quiet) { Write-Host "sc-desktop: on '$mine'; the input desktop could not be opened, so visibility is UNVERIFIED for this run." }
        return $mine
    }
    if ($mine -eq $shown) {
        throw "sc-desktop: this thread is on '$mine', which IS the desktop on the monitor. Refusing to call this run invisible."
    }
    if (-not $Quiet) {
        Write-Host "sc-desktop: this process is on '$mine'; the monitor is showing '$shown'. Different desktop objects, so nothing this run draws composites to the screen."
    }
    return $mine
}

function New-ScTestDesktop {
    <#
    .SYNOPSIS
    Create (or open) the named invisible desktop and HOLD it open. Returns the name.
    .DESCRIPTION
    The handle keeps the object alive between creating it and the first process actually
    starting on it; after that the processes on it hold it too, so the caller must keep this
    process alive for the run and call Close-ScTestDesktop at the end.

    CreateDesktop opens the existing object when the name is already taken, so a second
    caller in the same process cannot fight the first over it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [switch]$Quiet
    )
    if ($Name -match '[\\/]') { throw "sc-desktop: '$Name' is not a desktop name (a backslash would name a window station)." }
    if ([ScDesktop.Native]::Owned -ne [IntPtr]::Zero) {
        throw "sc-desktop: this process already holds the desktop '$([ScDesktop.Native]::OwnedName)'. Close it before creating another."
    }

    $h = [ScDesktop.Native]::CreateDesktopW($Name, [IntPtr]::Zero, [IntPtr]::Zero, 0, $script:SC_DESKTOP_ACCESS, [IntPtr]::Zero)
    if ($h -eq [IntPtr]::Zero) {
        $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw "sc-desktop: CreateDesktop('$Name') failed (Win32 error $err)."
    }
    [ScDesktop.Native]::Owned = $h
    [ScDesktop.Native]::OwnedName = $Name

    $shown = Get-ScInputDesktopName
    if ($Name -eq $shown) {
        # Unreachable with a generated name, but a caller may pass one: opening 'Default' by
        # name and calling a run on it invisible is the exact silent failure this file
        # exists to prevent.
        Close-ScTestDesktop -Quiet
        throw "sc-desktop: '$Name' is the desktop currently on the monitor. Refusing to use it as an invisible one."
    }
    if (-not $Quiet) {
        Write-Host "sc-desktop: created the invisible desktop '$Name' (the monitor is showing '$shown')."
    }
    $Name
}

function Close-ScTestDesktop {
    <#
    .SYNOPSIS
    Drop our handle to the invisible desktop.
    .DESCRIPTION
    The OBJECT outlives this call for as long as any process is still running on it, and
    Windows destroys it after that -- nothing is left on disk or in the registry. NEVER
    FATAL: this runs in `finally` after a run that has already produced its result, and a
    failed handle close must not replace a real test outcome with an unrelated exception.
    #>
    [CmdletBinding()]
    param([switch]$Quiet)
    if ([ScDesktop.Native]::Owned -eq [IntPtr]::Zero) { return }
    $name = [ScDesktop.Native]::OwnedName
    try { [void][ScDesktop.Native]::CloseDesktop([ScDesktop.Native]::Owned) }
    catch { Write-Warning "sc-desktop: closing the handle to '$name' failed ($($_.Exception.Message)). The run's result stands." }
    finally {
        [ScDesktop.Native]::Owned = [IntPtr]::Zero
        [ScDesktop.Native]::OwnedName = $null
    }
    if (-not $Quiet) { Write-Host "sc-desktop: released '$name'; Windows destroys it once nothing is running on it." }
}
