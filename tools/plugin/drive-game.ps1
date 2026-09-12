#Requires -Version 7
<#
.SYNOPSIS
Drive a running StarCraft 1.16.1 window with POSTED Win32 messages, and read frames back
out of it. Dot-source it; every function is a primitive, nothing here runs on import.

.DESCRIPTION
Posted messages, never synthetic input (`SendInput`/`SendKeys` drive the user's real
mouse and keyboard): this binary imports no DirectInput, never calls
`GetAsyncKeyState`, and takes the pointer position from the message's own `lParam`
(research/pe-anatomy.md § Imports). Every coordinate here is therefore a CLIENT
coordinate, independent of window position, DPI, monitor and foreground.

KNOWN LIMIT -- MODIFIER KEYS: `GetKeyState` is in the import table, and Windows never
updates a thread's key-state table for POSTED keyboard messages, so a game reading shift
that way cannot be shift-clicked from here. `Send-ScClick -Shift` sets `MK_SHIFT` in
`wParam` AND brackets the click with posted VK_SHIFT down/up; a failure means "test shift
by hand", not "shift is broken".

POSITIONAL SELECTION IS A CORRECTNESS HAZARD: a click picks a ROW, not a name, so a suite
must make its assumption TRUE before it clicks and assert what it actually got, or it
succeeds against the wrong thing (AGENTS.md § "Test fixtures").

.EXAMPLE
. ./tools/plugin/drive-game.ps1
$h = Get-ScGameWindow -ProcessId 1234
Send-ScClick -Hwnd $h -X 215 -Y 119
Send-ScDrag  -Hwnd $h -X1 60 -Y1 60 -X2 500 -Y2 300
Save-ScWindowImage -Hwnd $h -Path C:\temp\frame.png
#>

Set-StrictMode -Version Latest

# System.Drawing is deliberately NOT used from the C# below: on .NET 10 the GDI+ types
# live in a private assembly Add-Type's reference list cannot name, so the bitmap half is
# done in PowerShell and the C# stays pure Win32 P/Invoke. Its absence is tolerated so
# this file can be dot-sourced where there is no GDI+ at all (a CI runner exercising the
# browser model and the fixture registry touches no bitmap); the two functions that DO
# need it say so themselves rather than failing the load with an unrelated message.
$script:ScHaveDrawing = $true
try { Add-Type -AssemblyName System.Drawing -ErrorAction Stop | Out-Null }
catch { $script:ScHaveDrawing = $false }

# Which desktop this thread is on: the foreground gate must be able to say WHY it cannot
# have the foreground when a run is off-screen (see Assert-ScWindowActive).
. (Join-Path $PSScriptRoot 'sc-desktop.ps1')
# Get-ScWideGeometry, shared with deploy.ps1.
. (Join-Path $PSScriptRoot 'sc-geometry.ps1')

function Assert-ScDrawing {
    if (-not $script:ScHaveDrawing) {
        throw 'drive-game: System.Drawing is not available in this PowerShell, so no frame can be captured. Frame capture needs a Windows host with GDI+.'
    }
}

if (-not ('ScDrive.Native' -as [type])) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace ScDrive {
  public struct FoundWindow { public IntPtr Hwnd; public string ClassName; public int Width; public int Height; }

  public static class Native {
    [DllImport("user32.dll", SetLastError=true)]
    public static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll", SetLastError=true)]
    public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll", SetLastError=true)]
    public static extern bool IsWindow(IntPtr hWnd);
    [DllImport("user32.dll", SetLastError=true)]
    public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll", SetLastError=true)]
    private static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lParam);
    [DllImport("user32.dll", SetLastError=true)]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    private static extern int GetClassNameW(IntPtr hWnd, StringBuilder buf, int n);
    [DllImport("user32.dll", SetLastError=true)]
    private static extern bool GetClientRect(IntPtr hWnd, out RECT r);
    [DllImport("user32.dll")]
    public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdc, uint flags);

    // --- activation (task 022) ---------------------------------------------
    // Used by Set-ScWindowActive (the opt-in raise) and by probes that read the foreground.
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] private static extern bool BringWindowToTop(IntPtr h);
    [DllImport("user32.dll")] private static extern IntPtr SetActiveWindow(IntPtr h);
    [DllImport("user32.dll")] private static extern IntPtr SetFocus(IntPtr h);
    [DllImport("user32.dll")] private static extern bool AttachThreadInput(uint a, uint b, bool attach);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr pid);
    [DllImport("kernel32.dll")] private static extern uint GetCurrentThreadId();

    // Windows refuses SetForegroundWindow from a process that does not already own the
    // foreground, and returns TRUE while doing nothing (it only flashes the taskbar).
    // Attaching this thread's input queue to the current foreground thread first is the
    // documented way to be allowed to do it; the attachment is undone immediately.
    // Returns whether the window really ended up foreground -- callers assert on that
    // rather than on the API's return value.
    public static bool MakeForeground(IntPtr h) {
      IntPtr fg = GetForegroundWindow();
      if (fg == h) return true;
      uint tFg = GetWindowThreadProcessId(fg, IntPtr.Zero);
      uint tMe = GetCurrentThreadId();
      bool attached = (tFg != 0 && tFg != tMe) ? AttachThreadInput(tMe, tFg, true) : false;
      try {
        BringWindowToTop(h);
        SetForegroundWindow(h);
        SetActiveWindow(h);
        SetFocus(h);
      } finally {
        if (attached) AttachThreadInput(tMe, tFg, false);
      }
      return GetForegroundWindow() == h;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    // Every top-level window belonging to `pid`, with its class name and client size.
    // Enumerated from OUTSIDE the process -- the game's protected DACL (task 012 §4.2)
    // denies VM access but window enumeration is unaffected.
    public static FoundWindow[] WindowsOfProcess(uint pid) {
      var list = new System.Collections.Generic.List<FoundWindow>();
      EnumWindows((h, l) => {
        uint p; GetWindowThreadProcessId(h, out p);
        if (p != pid) return true;
        var sb = new StringBuilder(256);
        GetClassNameW(h, sb, sb.Capacity);
        RECT r; GetClientRect(h, out r);
        list.Add(new FoundWindow { Hwnd = h, ClassName = sb.ToString(),
                                   Width = r.Right - r.Left, Height = r.Bottom - r.Top });
        return true;
      }, IntPtr.Zero);
      return list.ToArray();
    }

    public static int[] ClientSize(IntPtr hWnd) {
      RECT r; GetClientRect(hWnd, out r);
      return new int[] { r.Right - r.Left, r.Bottom - r.Top };
    }

    [DllImport("user32.dll", SetLastError=true)]
    private static extern bool GetWindowRect(IntPtr hWnd, out RECT r);

    public static int[] WindowSize(IntPtr hWnd) {
      RECT r; GetWindowRect(hWnd, out r);
      return new int[] { r.Right - r.Left, r.Bottom - r.Top };
    }
  }
}
"@ -ReferencedAssemblies System.Runtime, System.Collections, System.Runtime.InteropServices
}

# --- Win32 message constants ------------------------------------------------
$script:WM_MOUSEMOVE   = 0x0200
$script:WM_LBUTTONDOWN = 0x0201
$script:WM_LBUTTONUP   = 0x0202
$script:WM_RBUTTONDOWN = 0x0204
$script:WM_RBUTTONUP   = 0x0205
$script:WM_KEYDOWN     = 0x0100
$script:WM_KEYUP       = 0x0101
$script:WM_CHAR        = 0x0102
# WM_COMMAND -- what an accelerator match SENDS. The window proc's case 0x111 hands its
# low word straight to the game's own key dispatcher; see Send-ScCommand.
$script:WM_COMMAND     = 0x0111

$script:MK_LBUTTON = 0x0001
$script:MK_RBUTTON = 0x0002
$script:MK_SHIFT   = 0x0004
$script:MK_CONTROL = 0x0008

function ConvertTo-ScLParam {
    param([int]$X, [int]$Y)
    # Client coordinates, low word = x, high word = y. Exactly what a real mouse
    # message carries, which is why nothing here depends on screen geometry.
    [IntPtr](($Y -band 0xFFFF) -shl 16 -bor ($X -band 0xFFFF))
}

function Get-ScGameWindow {
    <#
    .SYNOPSIS
    The game's main window handle, found by process id and window class.
    .DESCRIPTION
    Resolving by PID and not by class alone matters: another StarCraft (the user's own
    playable install) may be running, and driving the wrong one is not recoverable.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$ProcessId,
        [string]$ClassName = 'SWarClass',
        [int]$TimeoutSec = 30
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $wins = [ScDrive.Native]::WindowsOfProcess([uint32]$ProcessId)
        $hit = $wins | Where-Object { $_.ClassName -eq $ClassName -and $_.Width -gt 0 } | Select-Object -First 1
        if ($hit) {
            Write-Verbose "drive-game: hwnd=0x$('{0:X}' -f [int64]$hit.Hwnd) class=$($hit.ClassName) client=$($hit.Width)x$($hit.Height)"
            return $hit.Hwnd
        }
        Start-Sleep -Milliseconds 250
    }
    throw "drive-game: no '$ClassName' window for pid $ProcessId after ${TimeoutSec}s."
}

function Get-ScClientSize {
    param([Parameter(Mandatory)][IntPtr]$Hwnd)
    $wh = [ScDrive.Native]::ClientSize($Hwnd)
    [pscustomobject]@{ Width = $wh[0]; Height = $wh[1] }
}

function Get-ScWindowSize {
    param([Parameter(Mandatory)][IntPtr]$Hwnd)
    $wh = [ScDrive.Native]::WindowSize($Hwnd)
    [pscustomobject]@{ Width = $wh[0]; Height = $wh[1] }
}

function Assert-ScDrivable {
    <#
    .SYNOPSIS
    Refuse to post into a window that cannot receive input.
    .DESCRIPTION
    A MINIMISED window silently swallows posted mouse messages, so a test that posted
    anyway would report "the click did nothing" and send the reader hunting for a bug in
    the plugin.
    #>
    param([Parameter(Mandatory)][IntPtr]$Hwnd)
    if (-not [ScDrive.Native]::IsWindow($Hwnd)) { throw 'drive-game: window handle is dead (the game exited?).' }
    if ([ScDrive.Native]::IsIconic($Hwnd)) { throw 'drive-game: the game window is MINIMISED; posted mouse messages are ignored in that state. Restore it and retry.' }
}

function Send-ScActivationNudge {
    <#
    .SYNOPSIS
    Post WM_ACTIVATEAPP(1) + WM_ACTIVATE(WA_ACTIVE) + WM_SETFOCUS -- open the
    engine's activation-gated input path without touching the real foreground.
    .DESCRIPTION
    Measured under cnc-ddraw on the invisible desktop: a posted click at a fully
    interactive main menu NEVER registers (0/4 runs, one watched 60s), while the
    identical click under WMode registers every time; after this triple the same
    click registers in 0.4s. The gate RE-CLOSES on the next screen, so callers
    nudge before EVERY posted input, not once per run.

    The engine gates GLUE-SCREEN input on its activation state (DAT_0051bfa8
    family, written by the WM_ACTIVATEAPP case -- AGENTS.md § "Glue-screen (menu)
    input under cnc-ddraw"): WMode leaves the game believing it is active,
    cnc-ddraw's subclassed window on a desktop that can never hold the foreground
    does not. These are POSTED messages, so the real foreground, the user's focus
    and the visible desktop's cursor are untouched (the ClipCursor the handler
    runs applies to the window's own invisible desktop).
    %SCDRIVE_POST_ACTIVATE%=1 at the call sites opts a run in.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][IntPtr]$Hwnd)
    [void][ScDrive.Native]::PostMessage($Hwnd, 0x001C, [IntPtr]1, [IntPtr]0)  # WM_ACTIVATEAPP, active
    [void][ScDrive.Native]::PostMessage($Hwnd, 0x0006, [IntPtr]1, [IntPtr]0)  # WM_ACTIVATE, WA_ACTIVE
    [void][ScDrive.Native]::PostMessage($Hwnd, 0x0007, [IntPtr]0, [IntPtr]0)  # WM_SETFOCUS
    # 500ms is the measured-working settle (probe arm B); a 60ms variant of the
    # same triple failed to open the gate in the very next run.
    Start-Sleep -Milliseconds 500
}

function Send-ScMouseMove {
    <#
    .SYNOPSIS
    One posted WM_MOUSEMOVE. Does NOT need the window foreground -- only a live,
    non-minimised window. See Assert-ScWindowActive.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][IntPtr]$Hwnd,
        [Parameter(Mandatory)][int]$X, [Parameter(Mandatory)][int]$Y,
        [int]$Buttons = 0, [int]$DelayMs = 30,
        [switch]$NoActivate
    )
    Assert-ScDrivable -Hwnd $Hwnd
    if (-not $NoActivate) { Assert-ScWindowActive -Hwnd $Hwnd -Because 'a posted mouse MOVE' }
    if ($env:SCDRIVE_POST_ACTIVATE -eq '1') { Send-ScActivationNudge -Hwnd $Hwnd }
    [void][ScDrive.Native]::PostMessage($Hwnd, $script:WM_MOUSEMOVE, [IntPtr]$Buttons, (ConvertTo-ScLParam $X $Y))
    if ($DelayMs -gt 0) { Start-Sleep -Milliseconds $DelayMs }
}

function Send-ScClick {
    <#
    .SYNOPSIS
    One click at a client coordinate: move, button-down, button-up.
    .DESCRIPTION
    The leading WM_MOUSEMOVE is not decoration: the game tracks and draws a cursor position
    of its own, so moving first means the down/up pair land where the game already believes
    the pointer is, which is how a real mouse behaves. The window procedure stores that
    move's x/y unconditionally, foreground or not (see Set-ScWindowActive), so this drives
    the game while it sits behind whatever the user is doing. Never raise the window for
    it: the raise steals the user's foreground and confines their mouse without buying any
    input. Assert-ScWindowActive still runs, because a minimised or dead window DOES
    swallow posted mouse messages; -NoActivate is for a caller that has already checked.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][IntPtr]$Hwnd,
        [Parameter(Mandatory)][int]$X, [Parameter(Mandatory)][int]$Y,
        [switch]$Right, [switch]$Shift, [switch]$Ctrl,
        [int]$HoldMs = 60, [int]$SettleMs = 250,
        [switch]$NoActivate
    )
    Assert-ScDrivable -Hwnd $Hwnd
    if (-not $NoActivate) { Assert-ScWindowActive -Hwnd $Hwnd -Because 'a click, whose leading mouse MOVE' }

    if ($env:SCDRIVE_POST_ACTIVATE -eq '1') { Send-ScActivationNudge -Hwnd $Hwnd }

    $mods = 0
    if ($Shift) { $mods = $mods -bor $script:MK_SHIFT }
    if ($Ctrl)  { $mods = $mods -bor $script:MK_CONTROL }

    # Posted keyboard messages do NOT update the thread key-state table, so this half
    # only helps if the game tracks modifiers from the messages themselves. Cheap, and
    # harmless if it does not -- see the KNOWN LIMIT note at the top.
    if ($Shift) { [void][ScDrive.Native]::PostMessage($Hwnd, $script:WM_KEYDOWN, [IntPtr]0x10, [IntPtr]0x002A0001) }
    if ($Ctrl)  { [void][ScDrive.Native]::PostMessage($Hwnd, $script:WM_KEYDOWN, [IntPtr]0x11, [IntPtr]0x001D0001) }

    $down = if ($Right) { $script:WM_RBUTTONDOWN } else { $script:WM_LBUTTONDOWN }
    $up   = if ($Right) { $script:WM_RBUTTONUP }   else { $script:WM_LBUTTONUP }
    $btn  = if ($Right) { $script:MK_RBUTTON }     else { $script:MK_LBUTTON }
    $lp   = ConvertTo-ScLParam $X $Y

    [void][ScDrive.Native]::PostMessage($Hwnd, $script:WM_MOUSEMOVE, [IntPtr]$mods, $lp)
    Start-Sleep -Milliseconds 30
    [void][ScDrive.Native]::PostMessage($Hwnd, $down, [IntPtr]($btn -bor $mods), $lp)
    Start-Sleep -Milliseconds $HoldMs
    [void][ScDrive.Native]::PostMessage($Hwnd, $up, [IntPtr]$mods, $lp)

    if ($Ctrl)  { [void][ScDrive.Native]::PostMessage($Hwnd, $script:WM_KEYUP, [IntPtr]0x11, [IntPtr]0xC01D0001) }
    if ($Shift) { [void][ScDrive.Native]::PostMessage($Hwnd, $script:WM_KEYUP, [IntPtr]0x10, [IntPtr]0xC02A0001) }

    if ($SettleMs -gt 0) { Start-Sleep -Milliseconds $SettleMs }
}

function Send-ScDrag {
    <#
    .SYNOPSIS
    A drag-selection box from (X1,Y1) to (X2,Y2).
    .DESCRIPTION
    Intermediate WM_MOUSEMOVE messages are required, not cosmetic: the engine grows the
    selection rectangle from the moves it receives while the button is held, so a
    down-then-up with no moves in between is a click, not a box.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][IntPtr]$Hwnd,
        [Parameter(Mandatory)][int]$X1, [Parameter(Mandatory)][int]$Y1,
        [Parameter(Mandatory)][int]$X2, [Parameter(Mandatory)][int]$Y2,
        [int]$Steps = 12, [int]$StepMs = 40, [int]$SettleMs = 400,
        [switch]$NoActivate
    )
    Assert-ScDrivable -Hwnd $Hwnd
    # A drag is made of mouse MOVES, and posted moves reach the engine whether or not the
    # window is foreground (measured -- see Set-ScWindowActive). What still swallows them
    # is a MINIMISED or dead window, which is what this gate catches.
    if (-not $NoActivate) {
        Assert-ScWindowActive -Hwnd $Hwnd -Because 'a drag, which is made of mouse MOVES and'
    }
    if ($Steps -lt 2) { $Steps = 2 }
    if ($env:SCDRIVE_POST_ACTIVATE -eq '1') { Send-ScActivationNudge -Hwnd $Hwnd }

    [void][ScDrive.Native]::PostMessage($Hwnd, $script:WM_MOUSEMOVE, [IntPtr]0, (ConvertTo-ScLParam $X1 $Y1))
    Start-Sleep -Milliseconds 60
    [void][ScDrive.Native]::PostMessage($Hwnd, $script:WM_LBUTTONDOWN, [IntPtr]$script:MK_LBUTTON, (ConvertTo-ScLParam $X1 $Y1))
    Start-Sleep -Milliseconds 60

    for ($i = 1; $i -le $Steps; $i++) {
        $x = [int]($X1 + ($X2 - $X1) * $i / $Steps)
        $y = [int]($Y1 + ($Y2 - $Y1) * $i / $Steps)
        [void][ScDrive.Native]::PostMessage($Hwnd, $script:WM_MOUSEMOVE, [IntPtr]$script:MK_LBUTTON, (ConvertTo-ScLParam $x $y))
        Start-Sleep -Milliseconds $StepMs
    }

    [void][ScDrive.Native]::PostMessage($Hwnd, $script:WM_LBUTTONUP, [IntPtr]0, (ConvertTo-ScLParam $X2 $Y2))
    if ($SettleMs -gt 0) { Start-Sleep -Milliseconds $SettleMs }
}

function Send-ScKey {
    <#
    .SYNOPSIS
    A key press (WM_KEYDOWN + WM_KEYUP), optionally with a WM_CHAR in between.
    .DESCRIPTION
    -Char is for anything the game reads as typed text (a map-name filter box); -VirtualKey
    alone is for hotkeys. Both are posted, so `GetKeyState` never sees them -- see the
    KNOWN LIMIT note at the top of this file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][IntPtr]$Hwnd,
        [Parameter(Mandatory)][int]$VirtualKey,
        [char]$Char = [char]0,
        [switch]$Ctrl, [switch]$Shift,
        [int]$HoldMs = 50, [int]$SettleMs = 200
    )
    Assert-ScDrivable -Hwnd $Hwnd
    # -Ctrl / -Shift bracket the key with posted modifier KEYDOWN/KEYUP. Whether that is
    # ENOUGH is a property of this binary: Windows does not update the thread key-state
    # table for posted messages, so a game resolving modifiers through `GetKeyState` will
    # not see them. research/control-groups.md holds the answer for the control-group
    # keys; treat a failure as "drive it another way", never as "the modifier is broken".
    if ($Shift) { [void][ScDrive.Native]::PostMessage($Hwnd, $script:WM_KEYDOWN, [IntPtr]0x10, [IntPtr]0x002A0001) }
    if ($Ctrl)  { [void][ScDrive.Native]::PostMessage($Hwnd, $script:WM_KEYDOWN, [IntPtr]0x11, [IntPtr]0x001D0001) }
    [void][ScDrive.Native]::PostMessage($Hwnd, $script:WM_KEYDOWN, [IntPtr]$VirtualKey, [IntPtr]1)
    if ($Char -ne [char]0) {
        [void][ScDrive.Native]::PostMessage($Hwnd, $script:WM_CHAR, [IntPtr][int]$Char, [IntPtr]1)
    }
    Start-Sleep -Milliseconds $HoldMs
    [void][ScDrive.Native]::PostMessage($Hwnd, $script:WM_KEYUP, [IntPtr]$VirtualKey, [IntPtr]0xC0000001)
    if ($Ctrl)  { [void][ScDrive.Native]::PostMessage($Hwnd, $script:WM_KEYUP, [IntPtr]0x11, [IntPtr]0xC01D0001) }
    if ($Shift) { [void][ScDrive.Native]::PostMessage($Hwnd, $script:WM_KEYUP, [IntPtr]0x10, [IntPtr]0xC02A0001) }
    if ($SettleMs -gt 0) { Start-Sleep -Milliseconds $SettleMs }
}

# =============================================================================
# THE MAP BROWSER, MODELLED FROM THE FILESYSTEM
# =============================================================================
#
# NEVER CLICK A ROW BY NUMBER. `[Up One Level]` is NOT pinned to the top -- it sorts among
# the directories by its own displayed name -- so merely creating one `00-*` folder pushes
# it down a row, and a suite that never touches that folder opens a directory where it
# meant to go up. One level down the same defect loads another worker's map, and the run
# then reports internally consistent nonsense (AGENTS.md § "Test fixtures"). So EVERY row
# this harness clicks is computed from the filesystem, and what actually opened is
# verified before the next click.
#
# THE LISTING MODEL, read off captured frames rather than assumed:
#   * directories first (with `[Up One Level]` sorted among them), then map files, each
#     group sorted: a frame reads `[Allied] [Ladder] [Up One Level] [WebMaps]
#     (2)Astral Balance.scm ...`, exactly alphabetical over the four directory names;
#   * `Maps\` is the browser's ROOT: it has no `[Up One Level]` row;
#   * six rows are visible at a 640x480 client;
#   * THE LIST IS SCROLLED WHEN IT OPENS -- measured, with entry 1 off the top of a
#     listing this harness was about to click row 1 of, and clicking the list's own UP
#     ARROW until the rows stop moving restores the filesystem order exactly. That offset
#     is not modelled: `Sync-ScBrowserToTop` puts the list in the ONE state this describes.
#
# Geometry: row 1's text is at client y=140 and the rows are 19px apart -- the numbers
# below, read off FULL-WINDOW frames whose (+5,+32) offset Save-ScWindowImage explains.
# =============================================================================

$script:ScBrowserFirstRowY   = 140
$script:ScBrowserRowPitch    = 19
$script:ScBrowserVisibleRows = 6
$script:ScBrowserRowX        = 117
$script:ScBrowserOkX         = 516
$script:ScBrowserOkY         = 393
$script:ScBrowserUpEntry     = 'Up One Level'
$script:ScBrowserMapExt      = @('.scm', '.scx')
# The list's own scroll-up arrow, read off the same frames (image (344,173), less the
# (+5,+32) window-to-client offset).
$script:ScBrowserUpArrowX    = 339
$script:ScBrowserUpArrowY    = 141
$script:ScBrowserDownArrowX  = 339
$script:ScBrowserDownArrowY  = 211
# Every coordinate above is the glue screen's own. The menu centring (sc_menu.h,
# -MenuCentre 1) translates each glue root by one (dx,dy); a walk through centred menus
# sets that origin here once, and every browser click and fingerprint follows it.
$script:ScGlueX = 0
$script:ScGlueY = 0
function Set-ScGlueOrigin { param([int]$X = 0, [int]$Y = 0) $script:ScGlueX = $X; $script:ScGlueY = $Y }

function Get-ScBrowserRowY {
    param([Parameter(Mandatory)][int]$Row)
    $script:ScGlueY + $script:ScBrowserFirstRowY + ($Row - 1) * $script:ScBrowserRowPitch
}

function Sort-ScBrowserNames {
    <#
    .SYNOPSIS
    Sort names the way the browser's list appears to: ordinal, case-insensitive.
    .DESCRIPTION
    NOT PowerShell's `Sort-Object`, which is culture-aware and weights punctuation
    differently -- and these lists are full of punctuation (`(2)Astral Balance.scm`).
    Every entry ordering visible in a captured frame is reproduced by this comparer, and
    Assert-ScBrowserMapSelected re-checks the row it lands on live, so a disagreement
    surfaces as a failed run rather than a wrong map.
    #>
    param([string[]]$Names)
    if (-not $Names -or $Names.Count -eq 0) { return @() }
    $c = [string[]]$Names
    [array]::Sort($c, [System.StringComparer]::OrdinalIgnoreCase)
    $c
}

function Get-ScBrowserListing {
    <#
    .SYNOPSIS
    What the map browser will show for a directory, in row order, computed from disk.
    .DESCRIPTION
    -MapsRoot is the directory the browser treats as its root (`<GameDir>\Maps`): the one
    listing with no `[Up One Level]` entry.

    Returns an object with .Entries (Name / Kind / Row / Y, in the browser's own order),
    .Count, .Dir and .IsRoot. Kind is 'up', 'dir' or 'file'.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Dir,
        [Parameter(Mandatory)][string]$MapsRoot
    )
    $full = [IO.Path]::GetFullPath($Dir).TrimEnd('\')
    $rootFull = [IO.Path]::GetFullPath($MapsRoot).TrimEnd('\')
    if (-not (Test-Path -LiteralPath $full -PathType Container)) {
        throw "drive-game: the map browser cannot be modelled for '$full' -- no such directory."
    }
    $isRoot = $full -ieq $rootFull

    $dirNames = @(Get-ChildItem -LiteralPath $full -Directory -ErrorAction Stop |
                  ForEach-Object { $_.Name })
    if (-not $isRoot) { $dirNames += $script:ScBrowserUpEntry }
    $fileNames = @(Get-ChildItem -LiteralPath $full -File -ErrorAction Stop |
                   Where-Object { $script:ScBrowserMapExt -contains $_.Extension.ToLowerInvariant() } |
                   ForEach-Object { $_.Name })

    $dirNames  = @(Sort-ScBrowserNames ([string[]]$dirNames))
    $fileNames = @(Sort-ScBrowserNames ([string[]]$fileNames))

    $entries = @()
    $row = 0
    foreach ($n in $dirNames) {
        $row++
        $kind = if ($n -eq $script:ScBrowserUpEntry) { 'up' } else { 'dir' }
        $entries += [pscustomobject]@{ Name = $n; Kind = $kind; Row = $row; Y = (Get-ScBrowserRowY -Row $row) }
    }
    foreach ($n in $fileNames) {
        $row++
        $entries += [pscustomobject]@{ Name = $n; Kind = 'file'; Row = $row; Y = (Get-ScBrowserRowY -Row $row) }
    }
    [pscustomobject]@{
        Dir = $full; IsRoot = $isRoot; Entries = $entries; Count = $entries.Count
        Text = (($entries | ForEach-Object { "$($_.Row):$($_.Name)" }) -join ' | ')
    }
}

function Get-ScBrowserEntry {
    <#
    .SYNOPSIS
    The row a named entry will be on, or a throw naming what is there instead.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Listing,
        [Parameter(Mandatory)][string]$Name
    )
    $hit = @($Listing.Entries | Where-Object { $_.Name -ieq $Name })
    if ($hit.Count -ne 1) {
        throw ("drive-game: '$Name' is not in the map browser's listing of $($Listing.Dir). " +
               "The browser shows: $($Listing.Text)")
    }
    $e = $hit[0]
    if ($e.Row -gt $script:ScBrowserVisibleRows) {
        throw ("drive-game: '$Name' is row $($e.Row) of $($Listing.Dir), and only " +
               "$($script:ScBrowserVisibleRows) rows are visible without scrolling -- this harness " +
               'has no scroll primitive, so clicking it is not possible. Clear the stale ' +
               "fixture folders ahead of it. The browser shows: $($Listing.Text)")
    }
    $e
}

function Get-ScBrowserRowOccupancy {
    <#
    .SYNOPSIS
    A per-row fingerprint of the six visible rows, read off the live window.
    .DESCRIPTION
    Not OCR and not a picture: Get-ScRegionFingerprint returns a hex digest of one
    rectangle, six of them in row order. They answer exactly one question -- DID THIS ROW
    CHANGE -- which is all Sync-ScBrowserToTop asks. They do NOT say whether a row has
    text on it: the list control is transparent, so a blank row shows the menu artwork
    behind it and two blank rows do not match each other.

    The strip is 18px tall (one row pitch less a pixel, so neighbouring rows cannot bleed
    into each other) and stops short of the scrollbar at client x~336.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][IntPtr]$Hwnd)
    1..$script:ScBrowserVisibleRows | ForEach-Object {
        Get-ScRegionFingerprint -Hwnd $Hwnd -X ($script:ScGlueX + 62) -Y ((Get-ScBrowserRowY -Row $_) - 9) -Width 250 -Height 18
    }
}

function Sync-ScBrowserToTop {
    <#
    .SYNOPSIS
    Scroll the map browser's list to its first entry, and know that it got there.
    .DESCRIPTION
    THE STEP THAT MAKES THE FILESYSTEM MODEL TRUE. A freshly opened browser is already
    scrolled (see the block comment above Get-ScBrowserListing), so rather than model an
    offset that depends on what the game remembers, this puts the list in the one state
    the model describes.

    It clicks the list's own up arrow in batches and stops when a batch changes nothing,
    which is what "the top" looks like through the only oracle available here -- the row
    fingerprints. Termination is observed, not counted: a 95-entry listing needs more
    clicks than any constant a caller would guess, and running out silently would leave
    the list somewhere arbitrary, so running out THROWS.

    SELF-ANIMATING ROWS ARE MEASURED OUT, PER BATCH. Under cnc-ddraw the selected row's
    art changes BY ITSELF -- five samples 300ms apart with no clicks changed rows 4-5 every
    time, while under WMode the same screen is static -- so "did any row change" never
    settles and a single-sample test throws with the list already at the top. Each batch
    therefore takes TWO post-batch samples: rows differing between them are animating RIGHT
    NOW and say nothing about scrolling, so "the top" is when no OTHER row changed across
    the batch. Re-measured per batch rather than baselined once, because the selection sits
    at a different visible row index as the list scrolls under it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][IntPtr]$Hwnd,
        [int]$ClicksPerBatch = 8,
        [int]$MaxBatches = 20
    )
    Assert-ScDrivable -Hwnd $Hwnd
    # One activation for the whole burst; the clicks themselves skip it, because paying
    # the foreground check per click would dominate a 160-click scroll.
    Assert-ScWindowActive -Hwnd $Hwnd -Because 'scrolling the map browser, which'
    $prev = @(Get-ScBrowserRowOccupancy -Hwnd $Hwnd)
    $announcedSelfRows = $false
    for ($batch = 1; $batch -le $MaxBatches; $batch++) {
        for ($i = 0; $i -lt $ClicksPerBatch; $i++) {
            Send-ScClick -Hwnd $Hwnd -X ($script:ScGlueX + $script:ScBrowserUpArrowX) -Y ($script:ScGlueY + $script:ScBrowserUpArrowY) `
                         -HoldMs 40 -SettleMs 40 -NoActivate
        }
        Start-Sleep -Milliseconds 250
        $now = @(Get-ScBrowserRowOccupancy -Hwnd $Hwnd)
        Start-Sleep -Milliseconds 300
        $again = @(Get-ScBrowserRowOccupancy -Hwnd $Hwnd)
        $selfRows = @()
        for ($r = 0; $r -lt $now.Count; $r++) { if ($now[$r] -ne $again[$r]) { $selfRows += $r } }
        if ($selfRows.Count -gt 0 -and -not $announcedSelfRows) {
            Write-Host ("       browser: row(s) [$($selfRows -join ',')] change with NO clicks " +
                        '(self-animating art; measured under cnc-ddraw, task 070) -- top-detection ignores them')
            $announcedSelfRows = $true
        }
        if ($selfRows.Count -ge $now.Count - 1) {
            throw ("drive-game: $($selfRows.Count) of $($now.Count) browser rows change with no clicks " +
                   'at all, so no row fingerprint can distinguish scrolling from animation. ' +
                   'Refusing to click a row with no working top-detection oracle.')
        }
        $moved = $false
        for ($r = 0; $r -lt $now.Count; $r++) {
            if ($selfRows -contains $r) { continue }
            if ($now[$r] -ne $prev[$r]) { $moved = $true }
        }
        if (-not $moved) { return }
        $prev = $again
    }
    throw ("drive-game: the map browser list was still moving after $($MaxBatches * $ClicksPerBatch) " +
           'scroll-up clicks, so its top is not established and no row can be computed from ' +
           'the filesystem. Refusing to click a row.')
}

function Get-ScBrowserInfoPanel {
    <#
    .SYNOPSIS
    A fingerprint of the map-information panel -- the browser's own read-back of which map
    is selected.
    .DESCRIPTION
    The panel is blank while the selected row is a FOLDER, and shows the map's name, size,
    tileset and slot counts while it is a MAP. That is the browser telling us what it
    thinks it has, which is exactly what a positional click cannot tell us. A digest, not
    a picture (see Get-ScRegionFingerprint). The rectangle is client coordinates at a
    640x480 client, covering the title and the size/tileset/slots block.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][IntPtr]$Hwnd)
    Get-ScRegionFingerprint -Hwnd $Hwnd -X ($script:ScGlueX + 405) -Y ($script:ScGlueY + 60) -Width 225 -Height 200
}

function Assert-ScBrowserMapSelected {
    <#
    .SYNOPSIS
    Prove the row this run just clicked actually SELECTED A MAP.
    .DESCRIPTION
    TWO OTHER CHECKS ARE REFUTED, and both are the kind that reads as working:

      * counting rows that "have text on them" -- the list control is TRANSPARENT, so a
        blank row shows menu artwork through it and two blank rows do not match each
        other (measured: a correctly opened folder, four blank rows, four fingerprints);
      * clicking the scrollbar's down arrow to measure the list's length -- a SHORT list
        draws no scrollbar, so that click lands in the list body and selects a row, and
        the probe reports movement it caused itself.

    What is left is the browser's own read-back: selecting a FOLDER row blanks the panel,
    and every folder row leaves the same blank one. So the caller grounds the comparison by
    selecting a folder row first; then a click that CHANGES the panel selected a map, while
    a click that leaves it selected a folder or nothing at all. That catches the failure
    that costs runs -- the walk did not go where it thought -- but does NOT identify WHICH
    map: two fixture folders each holding one map look alike here, and that claim belongs
    to the suite's in-process unit assertion after the map loads.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][IntPtr]$Hwnd,
        [Parameter(Mandatory)][string]$Before,
        [Parameter(Mandatory)][string]$After,
        [Parameter(Mandatory)][psobject]$Listing,
        [Parameter(Mandatory)][psobject]$Entry
    )
    if ($Before -eq $After) {
        throw ("drive-game: clicking row $($Entry.Row) of $($Listing.Dir) did not select a map -- " +
               "the map-information panel did not change, which is what a FOLDER row or an EMPTY " +
               "row does. The filesystem says row $($Entry.Row) is '$($Entry.Name)' " +
               "($($Listing.Text)), so the browser is not showing what this run thinks it is. " +
               'Refusing to launch: a run that plays the wrong map reports confident nonsense.')
    }
    Write-Host "       browser: row $($Entry.Row) selected a map (info panel $Before -> $After)"
}

function Enter-ScBrowserEntry {
    <#
    .SYNOPSIS
    Open one directory entry (or `Up One Level`) of the map browser, and verify what opened.
    .DESCRIPTION
    Re-lists the CURRENT directory immediately before clicking, not once at the start:
    another worker creating a folder in between moves every row below it, and a run has
    been lost to exactly that gap. A listing that changed between the two reads is a
    throw, not a retry -- the harness cannot know which of the two the game is showing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][IntPtr]$Hwnd,
        [Parameter(Mandatory)][string]$Dir,
        [Parameter(Mandatory)][string]$MapsRoot,
        [Parameter(Mandatory)][string]$Name,
        [int]$SettleMs = 900
    )
    $before = Get-ScBrowserListing -Dir $Dir -MapsRoot $MapsRoot
    $entry = Get-ScBrowserEntry -Listing $before -Name $Name
    $again = Get-ScBrowserListing -Dir $Dir -MapsRoot $MapsRoot
    if ($again.Text -ne $before.Text) {
        throw ("drive-game: $Dir changed while the row for '$Name' was being computed " +
               "(was: $($before.Text); now: $($again.Text)). Every row below the change has moved, " +
               'so the click would open the wrong thing. Re-run.')
    }
    $target = if ($entry.Kind -eq 'up') { Split-Path $before.Dir -Parent } else { Join-Path $before.Dir $entry.Name }

    Write-Host "       browser: $Dir -> [$Name] (row $($entry.Row), y=$($entry.Y))"
    Send-ScClick -Hwnd $Hwnd -X ($script:ScGlueX + $script:ScBrowserRowX) -Y $entry.Y
    Send-ScClick -Hwnd $Hwnd -X ($script:ScGlueX + $script:ScBrowserOkX) -Y ($script:ScGlueY + $script:ScBrowserOkY)
    if ($SettleMs -gt 0) { Start-Sleep -Milliseconds $SettleMs }

    # The new listing arrives scrolled too, so put it back where the model can read it.
    Sync-ScBrowserToTop -Hwnd $Hwnd
    Get-ScBrowserListing -Dir $target -MapsRoot $MapsRoot
}

function Select-ScBrowserMap {
    <#
    .SYNOPSIS
    Walk the map browser from wherever it opened to one named map file, and SELECT it.
    .DESCRIPTION
    THE one entry point every suite uses, so there is one model of the browser in this
    repo instead of nine copies of `-X 117 -Y 140`. Every click on the way is computed from
    the filesystem and every directory it opens is verified before the next click
    (Assert-ScBrowserMapSelected). Selecting only: the caller checks the Game Type
    (Assert-ScGameType) and presses Ok, because what happens between selecting and launching
    differs per suite.

    -OpenDir is where the browser opens, which for Single Player -> Expansion -> Play
    Custom is `<GameDir>\Maps\BroodWar`. The route out of it is up to the common ancestor
    and back down; `Maps\` is the root, and the ascent stops there.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][IntPtr]$Hwnd,
        [Parameter(Mandatory)][string]$GameDir,
        [Parameter(Mandatory)][string]$MapPath,
        [string]$OpenDir
    )
    $mapsRoot = [IO.Path]::GetFullPath((Join-Path $GameDir 'Maps'))
    if (-not $OpenDir) { $OpenDir = Join-Path $mapsRoot 'BroodWar' }
    $cur = [IO.Path]::GetFullPath($OpenDir).TrimEnd('\')
    $mapFull = [IO.Path]::GetFullPath($MapPath)
    if (-not (Test-Path -LiteralPath $mapFull -PathType Leaf)) {
        throw "drive-game: $mapFull does not exist, so the browser cannot be walked to it."
    }
    $targetDir = [IO.Path]::GetFullPath((Split-Path $mapFull -Parent)).TrimEnd('\')

    Sync-ScBrowserToTop -Hwnd $Hwnd
    $listing = Get-ScBrowserListing -Dir $cur -MapsRoot $mapsRoot
    # Up to the common ancestor. `$targetDir + '\'` guards the prefix test against
    # `...\Maps\BroodWar2` looking like a child of `...\Maps\BroodWar`.
    $guard = 0
    while (-not (($targetDir + '\') -ilike (($cur + '\') + '*'))) {
        if ($cur -ieq $mapsRoot) { throw "drive-game: $targetDir is not under the browser's root $mapsRoot." }
        if (++$guard -gt 8) { throw "drive-game: the browser route from $OpenDir to $targetDir did not converge." }
        $listing = Enter-ScBrowserEntry -Hwnd $Hwnd -Dir $cur -MapsRoot $mapsRoot -Name $script:ScBrowserUpEntry
        $cur = $listing.Dir
    }
    # ...and back down, one named component at a time.
    if ($cur -ine $targetDir) {
        $rel = $targetDir.Substring($cur.Length).Trim('\')
        foreach ($component in ($rel -split '\\')) {
            $listing = Enter-ScBrowserEntry -Hwnd $Hwnd -Dir $cur -MapsRoot $mapsRoot -Name $component
            $cur = $listing.Dir
        }
    }

    $leaf = Split-Path $mapFull -Leaf
    $entry = Get-ScBrowserEntry -Listing $listing -Name $leaf
    if ($entry.Kind -ne 'file') { throw "drive-game: '$leaf' is not a map file row in $cur." }
    Write-Host "       browser: selecting $leaf (row $($entry.Row), y=$($entry.Y))"
    # GROUND THE COMPARISON FIRST. Selecting any folder row blanks the map-information
    # panel, so clicking one before the map row makes "the panel changed" mean "that row
    # was a map" rather than "that row was a different map from whatever was selected".
    # Without it the check passes on a browser sitting in the wrong folder whenever that
    # row happens to hold some map (see Assert-ScBrowserMapSelected).
    $folderRow = @($listing.Entries |
        Where-Object { $_.Kind -ne 'file' -and $_.Row -le $script:ScBrowserVisibleRows } |
        Select-Object -First 1)
    if ($folderRow.Count -gt 0) {
        Send-ScClick -Hwnd $Hwnd -X ($script:ScGlueX + $script:ScBrowserRowX) -Y $folderRow[0].Y
        Start-Sleep -Milliseconds 300
    }
    $panelBefore = Get-ScBrowserInfoPanel -Hwnd $Hwnd
    Send-ScClick -Hwnd $Hwnd -X ($script:ScGlueX + $script:ScBrowserRowX) -Y $entry.Y
    Start-Sleep -Milliseconds 500
    $panelAfter = Get-ScBrowserInfoPanel -Hwnd $Hwnd
    Assert-ScBrowserMapSelected -Hwnd $Hwnd -Before $panelBefore -After $panelAfter `
                                -Listing $listing -Entry $entry
    $entry
}

# =============================================================================
# FIXTURE OWNERSHIP: PER-SUITE-RUN, DECLARED UP FRONT
# =============================================================================
#
# AGENTS.md § "Test fixtures" is the rule: refuse to start on any fixture this run did not
# create, delete only your own, never the folder. "Mine" here is a RUN, not a file -- a
# suite declares every fixture name it will ever create before it creates any of them, and
# the checks below test against that whole set. One filename is not enough: a suite that
# creates two fixtures in sequence counts its own earlier one as foreign and waits for
# itself, a deadlock manufactured by the safety rule rather than by a collision.
#
# The set is fixed at declaration time and every file outside it is still foreign, so this
# is not "ignore anything that looks a bit like mine": a name has to have been declared,
# and declaring it is the same act as promising to delete it.
# =============================================================================

function Resolve-ScFixtureDir {
    <#
    .SYNOPSIS
    Where this run's fixtures go: the caller's `-FixtureDir` if given, otherwise this
    AGENT'S OWN folder for THIS SUITE, otherwise the suite's by-hand default.

    .DESCRIPTION
    The agent default is `00-t<task>-<suite>`, keyed on BOTH. Keyed on the task alone, two
    suites of one task share a folder, and a suite that deliberately leaves its fixture in
    place between phases then makes the next one apply the foreign-file rule correctly and
    wait forever on a file its own task wrote. Keyed on task+suite, a multi-phase suite
    keeps the SAME folder across its own phases, two suites of one task never see each
    other's files, and the foreign-file rule stays exactly as strict.

    A worker always has `$env:AGENT_TASK` (AGENTS.md § "Before any suite run: arm
    `$env:AGENT_TASK`"). Without it -- a human at a prompt, one run at a time -- the
    suite's by-hand default is used and `-Suite` is unused. The task id is its leading
    digits, so `<NNN>` and `<NNN>-<slug>` share one leaf.

    KNOWN HOLE: ownership is keyed on the declared NAME set, which decides "mine" against
    ANOTHER suite perfectly and not at all against ANOTHER RUN OF THE SAME SUITE. Two
    concurrent runs of one suite with no `-FixtureDir` land in the same folder and declare
    the same names, so the foreign check never fires and one rewrites the other's fixture
    underneath it. Bounded, and forbidden by AGENTS.md § "Test fixtures", but not closed
    by code.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$GameDir,
        # This suite's by-hand default, used when no agent task is set.
        [Parameter(Mandatory)][string]$Fallback,
        # This suite's own short name (e.g. 'save-load', 'hud-row') -- what separates it
        # from every other suite this same task might run. Mandatory: a caller that cannot
        # name its own suite cannot be given a folder that is safe from every OTHER suite.
        [Parameter(Mandatory)][string]$Suite,
        # Injectable so Pester can exercise every branch without touching the environment.
        [AllowNull()][AllowEmptyString()][string]$AgentTask = $env:AGENT_TASK
    )
    $leaf = $Fallback
    if (-not [string]::IsNullOrWhiteSpace($AgentTask)) {
        $taskLeaf = if ($AgentTask -match '^\s*(\d{1,4})') { "t$($Matches[1])" }
                    else { 't' + ($AgentTask -replace '[^A-Za-z0-9]', '') }
        $leaf = "00-$taskLeaf-$Suite"
    }
    Join-Path $GameDir (Join-Path 'Maps\BroodWar' $leaf)
}

function New-ScFixtureRun {
    <#
    .SYNOPSIS
    Declare the fixture folder and EVERY fixture name this run will create.
    .DESCRIPTION
    -Names must be complete. A suite that creates a name it did not declare will be
    refused by its own next check, which is the intended pressure: the declaration is the
    list this run cleans up, so an undeclared file is a file nobody will delete.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Dir,
        [Parameter(Mandatory)][string[]]$Names
    )
    if ($Names.Count -eq 0) { throw 'drive-game: a fixture run must declare at least one fixture name.' }
    $dupes = @($Names | Group-Object | Where-Object { $_.Count -gt 1 })
    if ($dupes.Count -gt 0) { throw "drive-game: duplicate fixture name(s) declared: $(($dupes.Name) -join ', ')" }
    [pscustomobject]@{
        Dir   = $Dir
        Names = [string[]]$Names
        Paths = [string[]]@($Names | ForEach-Object { Join-Path $Dir $_ })
    }
}

function Get-ScFixtureFolderOwnerNote {
    <#
    .SYNOPSIS
    What the fixture-folder PATH ITSELF proves about who else could own a foreign file
    found in it -- so the refusal and wait messages stop asserting "another run" as fact.
    .DESCRIPTION
    An agent's fixture folder `00-t<task>-<suite>` is unique to ONE task AND ONE suite, so
    a same-task-different-suite file cannot land there: a foreign file in a folder shaped
    that way is a genuine cross-task file, or a leftover from an earlier run of this exact
    task+suite that declared a different name. Folders that do NOT match that shape carry
    no such guarantee, and the note says ownership is unknown rather than guessing.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Dir)
    $leaf = Split-Path $Dir -Leaf
    if ($leaf -match '^00-t(\d+)-(.+)$') {
        return ("$leaf is scoped to task $($Matches[1])'s '$($Matches[2])' runs only " +
                "(task+suite folder, issue #80) -- a same-task-different-suite file is " +
                'impossible here, so this is a genuine foreign file: another task''s run, ' +
                "or a leftover this task's own earlier attempt did not declare.")
    }
    return "$leaf is not a task+suite-scoped folder (by-hand/shared default) -- its owner cannot be determined from the path."
}

function Get-ScForeignFixture {
    <#
    .SYNOPSIS
    The map files in this run's fixture folder that this run did not declare.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][psobject]$Run)
    if (-not (Test-Path -LiteralPath $Run.Dir)) { return @() }
    @(Get-ChildItem -LiteralPath $Run.Dir -File -ErrorAction SilentlyContinue |
      Where-Object { $script:ScBrowserMapExt -contains $_.Extension.ToLowerInvariant() } |
      Where-Object { $Run.Names -notcontains $_.Name } |
      ForEach-Object { $_.Name })
}

function Assert-ScFixtureFolderMine {
    <#
    .SYNOPSIS
    Refuse to go on while a fixture this run did not declare is in its folder.
    .DESCRIPTION
    Called at generate time AND again immediately before the browser walk. Once is not
    enough: the folder can be added to in between, and the browser row moves under the
    click -- a run has been lost to exactly that gap.

    Never deletes the other file -- it may belong to a game that is running right now.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][psobject]$Run)
    $foreign = @(Get-ScForeignFixture -Run $Run)
    if ($foreign.Count -gt 0) {
        $ownerNote = Get-ScFixtureFolderOwnerNote -Dir $Run.Dir
        throw ("drive-game: $($Run.Dir) holds $($foreign -join ', '), which this run did not " +
               "declare (it declared: $($Run.Names -join ', ')). $ownerNote No liveness check " +
               'was performed -- it may belong to a finished run or a running one. The map ' +
               'browser opens a ROW, so a foreign file moves which map loads -- and playing ' +
               'somebody else''s map produces internally consistent nonsense. Refusing to start, ' +
               'and not deleting theirs.')
    }
}

function Assert-ScFixtureStillMine {
    <#
    .SYNOPSIS
    The late check: this run's own fixture is still there, and nobody else's is.
    .DESCRIPTION
    Run immediately before the browser walk. Two different failures, named separately,
    because they need different reactions: a MISSING own fixture means this run has no
    map to play (regenerate, do not interpret the run), a foreign one means a
    collision (wait for them).

    The missing-fixture message names only what it observed and which prior step's output
    to read. It cannot know WHY the file is absent -- a worktree without .venv fails
    generation and writes no file at all -- and blaming another worker's cleanup for a
    plain absence sends readers hunting a fleet-coordination race that does not exist.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Run,
        [Parameter(Mandatory)][string]$MapPath
    )
    $mine = Split-Path $MapPath -Leaf
    if ($Run.Names -notcontains $mine) {
        throw "drive-game: '$mine' was never declared by this fixture run ($($Run.Names -join ', ')) -- declare it in New-ScFixtureRun so it is also cleaned up."
    }
    if (-not (Test-Path -LiteralPath $MapPath)) {
        throw ("drive-game: $mine is not in $($Run.Dir) immediately before the browser walk. " +
               'This check cannot know why from here: either it was never generated (check the generator step''s own output -- ' +
               'a worktree without .venv fails exactly this way, issue #97) or something removed it after generation. ' +
               'No evidence points at any other worker. Regenerate; do not interpret this run.')
    }
    Assert-ScFixtureFolderMine -Run $Run
}

function Remove-ScOwnFixture {
    <#
    .SYNOPSIS
    Delete this run's own declared fixtures, and nothing else. Safe on every path.
    .DESCRIPTION
    -Names narrows it to some of the declared set (the phase that is finishing); omitted,
    it takes all of them. A file that will not delete is left alone and reported -- a
    running game may be reading it, and forcing is not an option against that.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Run,
        [string[]]$Names
    )
    $want = if ($Names) { $Names } else { $Run.Names }
    foreach ($n in $want) {
        if ($Run.Names -notcontains $n) { throw "drive-game: '$n' is not one of this run's declared fixtures." }
        $p = Join-Path $Run.Dir $n
        if (-not (Test-Path -LiteralPath $p)) { continue }
        try { Remove-Item -LiteralPath $p -Force -ErrorAction Stop }
        catch { Write-Host "       could not delete $p yet ($($_.Exception.Message))" }
    }
}

function Remove-ScOwnFixtureDir {
    <#
    .SYNOPSIS
    Delete a fixture folder this run created, but only if it is EMPTY.
    .DESCRIPTION
    A suite with its own fixture folder must take it away again: rows are computed from
    the filesystem, so an empty folder left behind moves every row below it for everyone
    else. A non-empty one is never deleted -- the rule everywhere here is never to remove
    what this run did not create.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Dir)
    if (-not (Test-Path -LiteralPath $Dir)) { return }
    $left = @(Get-ChildItem -LiteralPath $Dir -Force -ErrorAction SilentlyContinue)
    if ($left.Count -eq 0) { Remove-Item -LiteralPath $Dir -Force -ErrorAction SilentlyContinue }
    else { Write-Host "       leaving $Dir in place: it still holds $($left.Count) file(s) this run did not create" }
}

function Wait-ScFixtureFolderFree {
    <#
    .SYNOPSIS
    Wait until this run's fixture folder holds nothing it did not declare, then clear out
    its own leftovers so the generator can write into a clean folder.
    .DESCRIPTION
    Two waits, for two different reasons:
      * for somebody ELSE's fixture to go: never deleted, because a running game may have
        it open, and ending another worker's run is the damage this repo guards hardest
        against (AGENTS.md § "Hard rules");
      * for OUR OWN previous file to become deletable: a stale one can still be held open
        by a game that is shutting down.

    -Names narrows the deletion to the fixtures the caller is about to (re)write, so an
    earlier phase's file survives into a later phase. Omitted, it clears all of them.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Run,
        [string[]]$Names,
        [int]$TimeoutMinutes = 20
    )
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    $ownerNote = Get-ScFixtureFolderOwnerNote -Dir $Run.Dir
    while ($true) {
        New-Item -ItemType Directory -Path $Run.Dir -Force | Out-Null
        $foreign = @(Get-ScForeignFixture -Run $Run)
        if ($foreign.Count -eq 0) { break }
        if ((Get-Date) -ge $deadline) {
            throw ("drive-game: $($Run.Dir) still holds $($foreign -join ', '), undeclared by this run " +
                   "(it declared: $($Run.Names -join ', ')), after $TimeoutMinutes minute(s) of waiting. " +
                   "$ownerNote No liveness check was performed. Two runs cannot share this folder: the map " +
                   'is chosen by clicking a row, so an extra file silently changes which map loads. Not ' +
                   'deleting it -- it may belong to a running game.')
        }
        Write-Host "       waiting for $($Run.Dir) to be free ($($foreign -join ', ') present, undeclared by this run; $ownerNote)"
        Start-Sleep -Seconds 20
    }

    $want = if ($Names) { $Names } else { $Run.Names }
    foreach ($n in $want) {
        if ($Run.Names -notcontains $n) { throw "drive-game: '$n' is not one of this run's declared fixtures." }
        $p = Join-Path $Run.Dir $n
        $deleteDeadline = (Get-Date).AddMinutes($TimeoutMinutes)
        while (Test-Path -LiteralPath $p) {
            try { Remove-Item -LiteralPath $p -Force -ErrorAction Stop; break }
            catch {
                if ((Get-Date) -ge $deleteDeadline) {
                    throw "drive-game: $n in $($Run.Dir) is locked by another process and could not be replaced within $TimeoutMinutes minute(s) -- a game is still reading it. Not forcing."
                }
                Write-Host "       waiting for $n to be released (another process has it open)"
                Start-Sleep -Seconds 15
            }
        }
    }
}

function Get-ScSelectionGroup {
    <#
    .SYNOPSIS
    The CUnit pointers the ENGINE is holding -- its capped twelve -- from the observer's
    own snapshot line.
    .DESCRIPTION
    Needed to say anything about "the engine's selection" as a SET rather than as a count.
    The pointers come back as upper-case hex without the 0x, the format Get-ScWorldState
    reports per unit, so the two can be intersected directly.

    RETURNED UNROLLED, deliberately. Do not end this in `,@(...)`: the caller already
    wraps the call in `@(...)`, and the two together give an array holding ONE element
    which is itself the array of twelve -- `.Count` reads 1, `-contains` matches nothing,
    and assertions about the ENGINE'S TWELVE fail with all twelve pointers in the log.
    PowerShell 7 gives scalars a .Count of 1, so the idiom buys nothing here anyway.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$LogPath)
    $line = @(Get-Content -LiteralPath $LogPath -ErrorAction SilentlyContinue |
              Select-String -Pattern 'clientSelectionGroup\s+\[0\]=') | Select-Object -Last 1
    if (-not $line) { return @() }
    [regex]::Matches($line.Line, '=0x([0-9A-Fa-f]+)') |
        ForEach-Object { $_.Groups[1].Value.ToUpperInvariant() }
}

function Get-ScRegionFingerprint {
    <#
    .SYNOPSIS
    A hash of one rectangle of the game window. Not a picture, a comparison key.
    .DESCRIPTION
    Frames are a diagnostic in this repo, never an oracle -- reading text off one is not
    something a script can do reliably. Comparing the SAME rectangle before and after an
    action is different: it answers "did this region change at all", which is a real
    yes/no, and the return value is a hex digest, so nothing here reproduces game artwork.

    Only use it where that IS the question -- the map-browser row reads. It cannot carry a
    dialog's VALUE: "changed" cannot separate "the pick did not take" from "the value was
    already right", and a dialog's content is readable out of the engine's own dialog list
    (AGENTS.md § "Oracles: what counts as a read-back").
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][IntPtr]$Hwnd,
        [Parameter(Mandatory)][int]$X, [Parameter(Mandatory)][int]$Y,
        [Parameter(Mandatory)][int]$Width, [Parameter(Mandatory)][int]$Height
    )
    Assert-ScDrivable -Hwnd $Hwnd
    Assert-ScDrawing
    $sz = Get-ScWindowSize -Hwnd $Hwnd
    $bmp = New-Object System.Drawing.Bitmap($sz.Width, $sz.Height,
                     [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        try {
            $hdc = $g.GetHdc()
            try { $ok = [ScDrive.Native]::PrintWindow($Hwnd, $hdc, 0) }
            finally { $g.ReleaseHdc($hdc) }
        } finally { $g.Dispose() }
        if (-not $ok) { throw "drive-game: PrintWindow failed for hwnd 0x$('{0:X}' -f [int64]$Hwnd)." }
        # The frames this repo captures are FULL-WINDOW, because the windowed-mode helper
        # leaves its caption inside the reported client rectangle -- so the caller's
        # coordinates are client ones and the offset is added here, once.
        $cs = Get-ScClientSize -Hwnd $Hwnd
        $dx = [int](($sz.Width - $cs.Width) / 2)
        $dy = $sz.Height - $cs.Height - $dx
        $rect = New-Object System.Drawing.Rectangle(($X + $dx), ($Y + $dy), $Width, $Height)
        $crop = $bmp.Clone($rect, $bmp.PixelFormat)
        try {
            $ms = New-Object System.IO.MemoryStream
            try {
                $crop.Save($ms, [System.Drawing.Imaging.ImageFormat]::Bmp)
                $sha = [System.Security.Cryptography.SHA256]::Create()
                try { return [BitConverter]::ToString($sha.ComputeHash($ms.ToArray())).Replace('-', '').Substring(0, 16) }
                finally { $sha.Dispose() }
            } finally { $ms.Dispose() }
        } finally { $crop.Dispose() }
    } finally { $bmp.Dispose() }
}

# --- the Game Type, read out of the engine's dialog memory --------------------

# Control type 13 in the engine's dialog list. Observed on the Create Game screen: the
# Game Type box, the player-name box and the race box are the three of them.
$script:SC_CTRL_COMBO = 13

function Get-ScGameTypeControl {
    <#
    .SYNOPSIS
    The Create Game screen's Game Type combo, READ OUT OF THE ENGINE'S DIALOG LIST:
    which entry is selected. $null if the screen is not up.
    .DESCRIPTION
    AGENTS.md § "Oracles: what counts as a read-back": a dialog's CONTENT comes from
    memory, never from a hash of its pixels. The active-dialog scan already walks the list
    at SC_VA_DIALOG_LIST and logs every control that carries text, and the Game Type
    combo's text IS the selected entry's label:

      DIALOGS n=1  dlg='Create' rect=0,0,639,479 ... ctrl='Game Type' rect=58,262,169,281
        type=9 flags=0x408 ctrl='Use Map Settings' rect=180,261,351,277 type=13 flags=0x20020418

    The combo is found by its ROW, not by its index among the controls and not by a fixed
    rect: the one type-13 control that starts to the RIGHT of the 'Game Type' label and
    overlaps it vertically.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$LogPath)

    $create = @(Get-ScDialogs -LogPath $LogPath | Where-Object { $_.Name -eq 'Create' })
    if ($create.Count -eq 0) { return $null }
    $dlg = $create[0]

    $label = @($dlg.Controls | Where-Object { $_.Text -eq 'Game Type' })
    if ($label.Count -ne 1) { return $null }
    $row = $label[0]

    $combo = @($dlg.Controls | Where-Object {
        $_.Type -eq $script:SC_CTRL_COMBO -and
        $_.Left -ge $row.Right -and
        $_.Top -lt $row.Bottom -and $_.Bottom -gt $row.Top
    })
    if ($combo.Count -eq 0) { return $null }
    $c = $combo[0]

    # The map-information panel, from the same read: under Use Map Settings the engine
    # SHOWS 'Human Slots'/'Computer Slots' and hides 'Number of Players' (flag 0x8 on the
    # shown ones, 0x0 on the hidden one). Reported as corroboration, never as the verdict
    # -- the combo's own text is the fact, and a second reading of the same dialog is not
    # an independent oracle. It is here so a surprising result has context beside it.
    $shown = @($dlg.Controls |
               Where-Object { $_.Text -match '^(Number of Players|Human Slots|Computer Slots)' -and ($_.Flags -band 0x8) } |
               # 'Human Slots:.2' -- the plugin sanitises the engine's separator to '.', so
               # the label is everything before it, without its colon.
               ForEach-Object { (($_.Text -split '\.')[0]).TrimEnd(':') })

    [pscustomobject]@{
        Value  = $c.Text
        PanelShows = $shown
    }
}

function Assert-ScGameType {
    <#
    .SYNOPSIS
    Throw unless the Create Game screen's Game Type reads 'Use Map Settings', read out of
    the engine's own dialog list.
    .DESCRIPTION
    The Game Type is the most consequential control in this harness: get it wrong and the
    fixture loads as a melee game, the map's placed units are never created, and the
    failure surfaces minutes later as "the wrong units are on the map".

    Nothing here picks. run-with-plugin.ps1 writes 'Use Map Settings' into HKCU
    'Custom Type' before every agent launch and the engine takes the combo's starting
    value from it, measured both ways off-screen; a dropdown pick instead needs the
    foreground, which an off-screen run never has. This is the read-back that proves the
    write reached this game.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$LogPath, [int]$TimeoutSec = 15)
    $want = 'Use Map Settings'
    # Polls the newest DIALOGS line (logged whenever the dialog set changes) rather than
    # racing the plugin's 250 ms tick.
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    do {
        $now = Get-ScGameTypeControl -LogPath $LogPath
        if ($now -and $now.Value -eq $want) {
            Write-Host ("       game type is '{0}' (read from the engine's dialog list; panel shows {1})" -f `
                $now.Value, (($now.PanelShows -join ', ') -replace '^$', 'nothing yet'))
            return
        }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)
    if (-not $now) {
        throw ("drive-game: the Create Game screen's Game Type combo is not in the engine's dialog " +
               "list (log: $LogPath). Either that screen is not up, or the plugin's dialog scan is " +
               'off (%SCPLUGIN_DIALOGS%=0).')
    }
    # PARENTHESISED BEFORE -f: `-f` binds tighter than `+`, so without the parentheses only
    # the last literal is formatted and the message silently loses what it reads.
    throw (("drive-game: Game Type reads '{0}', want '{1}'. run-with-plugin.ps1 writes it into " +
            "HKCU 'Custom Type' before every agent launch, so this game started without that write " +
            '(a launch without $env:AGENT_TASK, or another StarCraft rewrote the value on exit). ' +
            'A fixture under the wrong game type produces the wrong units.') -f $now.Value, $want)
}

function Wait-ScNoGameRunning {
    <#
    .SYNOPSIS
    Wait until no StarCraft process is running on this machine.
    .DESCRIPTION
    THE GAME IS SINGLE-INSTANCE, MACHINE-WIDE. Launching a second one -- even from a
    different working copy, with a different injector -- gets an immediate exit, which
    `scinject.exe` reports as exit 3 ("the game exited on its own before injection") and
    `run-with-plugin.ps1` turns into a thrown launch failure. Copying the install to a
    private directory does NOT help: the constraint is per machine, not per directory.

    The launch lock (sc-launch-lock.ps1) does not cover this on its own: it is held around
    the LAUNCH, not for as long as the game is alive, so a worker can be holding a running
    game with the lock free (AGENTS.md § "Launch lock"). A caller that wants a game waits
    for the machine to be free FIRST, then holds the lock for as long as its own game
    lives. Waiting, never killing: another worker's game is another worker's run.
    #>
    [CmdletBinding()]
    param([int]$TimeoutMinutes = 30, [int]$PollSeconds = 15)
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    while ($true) {
        $running = @(Get-Process -Name 'StarCraft' -ErrorAction SilentlyContinue)
        if ($running.Count -eq 0) { return }
        if ((Get-Date) -ge $deadline) {
            throw ("drive-game: StarCraft has been running (pid {0}) for $TimeoutMinutes minute(s) and this machine allows only one instance. " +
                   'Not touching it -- it belongs to another worker.') -f (($running | ForEach-Object { $_.Id }) -join ',')
        }
        Write-Host ("       waiting for another worker's StarCraft to exit (pid {0})" -f (($running | ForEach-Object { $_.Id }) -join ','))
        Start-Sleep -Seconds $PollSeconds
    }
}

function Set-ScWindowActive {
    <#
    .SYNOPSIS
    Make the game window the foreground window. NOT needed to drive it -- see
    Assert-ScWindowActive. Opt-in for a human watching a run ($env:SCDRIVE_RAISE=1); suites
    and probes must not call it (AGENTS.md § "Foreground").
    .DESCRIPTION
    DO NOT RAISE THE GAME TO DELIVER INPUT. Posted moves register while the window is in
    the background, measured two ways:

      * STATIC (Ghidra, StarCraft.exe FUN_004d1d70, the window procedure). Its
        WM_MOUSEMOVE case is three unconditional stores and a return -- no foreground
        check, no active check:
            case 0x200: DAT_006cddc0 |= 1;                  /* "the mouse moved" bit */
                        _DAT_006cddc4 = lParam & 0xffff;    /* x, clamped to 0x27f  */
                        _DAT_006cddc8 = lParam >> 16;       /* y, clamped to 0x1df  */
                        return 1;
        The binary's only GetForegroundWindow call site (0x004eddf0) is a diagnostic.
      * LIVE (tools/plugin/probe-quiet-input.ps1). With the USER'S window holding the
        foreground throughout, a posted move onto the Single Player button changed that
        button's region (FF975A03A546737B -> 271D215ABFB1EF45) and GetForegroundWindow
        never changed: the move registered AND was drawn from the background.

    Raising is WORSE than useless for input. The WM_ACTIVATEAPP case (0x1c) runs 0x004d1750
    and 0x00421730, which between them call SetCursor/GetCursorPos/SetCursorPos and
    ClipCursor(window rect), so every raise re-syncs the game's cursor to the PHYSICAL
    mouse and confines the user's mouse to the game window -- measured: after the raise the
    button region went straight back to its parked value, throwing away the position the
    posted move had just set.

    A stale FRAME is a different failure from lost input: the game gates DRAWING on
    activation (0x0041d710 returns 0 while DAT_0051bfa8, written by that same handler, is
    0), so a frame from an inactive window can be stale on a stock launch. Under the
    windowed-mode helper every suite injects it is not -- the animated main menu
    fingerprinted 3 s apart in the background gives two different frames.

    SetForegroundWindow alone is refused for a background process (it returns TRUE and
    flashes the taskbar instead), so this goes through the documented AttachThreadInput
    dance and then VERIFIES the result rather than trusting the return value.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][IntPtr]$Hwnd,
        [int]$SettleMs = 400,
        # Attempts. Foreground changes can lose a race with whatever is currently
        # foreground (an installer, a notification toast); one retry is cheap.
        [int]$Tries = 3
    )
    Assert-ScDrivable -Hwnd $Hwnd
    if ([ScDrive.Native]::GetForegroundWindow() -eq $Hwnd) { return $true }
    for ($i = 0; $i -lt $Tries; $i++) {
        if ([ScDrive.Native]::MakeForeground($Hwnd)) {
            if ($SettleMs -gt 0) { Start-Sleep -Milliseconds $SettleMs }
            return $true
        }
        Start-Sleep -Milliseconds 300
    }
    return $false
}

function Assert-ScWindowActive {
    <#
    .SYNOPSIS
    The gate every move-dependent primitive goes through. It does NOT raise the window --
    it only refuses to post into a window that cannot receive the message.
    .DESCRIPTION
    What it gates is Assert-ScDrivable's fact: a MINIMISED or dead window really does
    swallow posted mouse messages. It does not touch the foreground, because posted moves
    register in the background anyway (see Set-ScWindowActive for the decompiled
    WM_MOUSEMOVE case and the live probe) -- a raise buys no input, and costs the user
    their foreground window and, through the game's own ClipCursor, their mouse.

    $env:SCDRIVE_RAISE=1 is the opt-in escape hatch for a human who wants to watch a run.
    It is never set by the suites; if you find yourself reaching for it to make a test
    pass, the test is telling you something else is wrong.

    OFF-SCREEN RUNS cannot grant it at all, and the throw below names that case
    specifically. Nothing the harness drives needs it: posted moves, clicks, drags, keys
    and PrintWindow all work off-screen, measured.

    -Because is glued into the message so the failure names the operation that refused,
    not just the fact that a window cannot take input.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][IntPtr]$Hwnd,
        [string]$Because = 'this input',
        [int]$Tries = 3
    )
    Assert-ScDrivable -Hwnd $Hwnd
    if ($env:SCDRIVE_RAISE -ne '1') { return }
    if (Set-ScWindowActive -Hwnd $Hwnd -Tries $Tries) { return }

    # An OFF-SCREEN run can never satisfy this, and it must say so in those words. The
    # foreground window is a property of the desktop that is receiving input; a window on any
    # other desktop cannot hold it, and GetForegroundWindow() reads 0 there all run --
    # measured: off-screen, even the foreground control arm that passes every time on the
    # visible desktop could not raise. Without this branch the message below sends the reader
    # hunting for a modal dialog that does not exist (AGENTS.md § "Diagnostics and
    # reporting": a diagnostic must name the term that refused).
    $myDesktop = Get-ScThreadDesktopName
    $onScreen = Get-ScInputDesktopName
    if ($myDesktop -and $onScreen -and $myDesktop -ne $onScreen) {
        throw ("drive-game: `$env:SCDRIVE_RAISE=1 asked for the game window in the FOREGROUND, and this run is " +
               "on the invisible desktop '$myDesktop' while the monitor is showing '$onScreen'. " +
               'No window on a desktop that is not receiving input can be the foreground window, ' +
               'so this is structural rather than a race -- retrying will not help. Every input ' +
               'in this harness drives fine off-screen; to watch a run, re-run visibly -- same code path, one flag: ' +
               "./tools/plugin/run-offscreen.ps1 -Visible -Suite <suite>. (The input: $Because)")
    }

    throw ("drive-game: `$env:SCDRIVE_RAISE=1 asked for a raise and the game window could not be " +
           "brought to the foreground before $Because. Close whatever is holding the " +
           'foreground (a modal dialog, an installer, a lock screen) and re-run, or unset ' +
           'SCDRIVE_RAISE -- the harness does not need it.')
}

function Send-ScCommand {
    <#
    .SYNOPSIS
    Fire one of the game's own ACCELERATOR commands by posting WM_COMMAND -- the only way
    to drive a MODIFIED key (Ctrl+1, Shift+1) from a script.
    .DESCRIPTION
    Evidence in research/control-groups.md. StarCraft does not read Ctrl or Shift in its
    window procedure: its message pump (0x004D1BF0) calls `TranslateAcceleratorA` FIRST
    and dispatches normally only when that returns 0, and the merged accelerator table
    comes from the binaries' own resources (`Local.dll` id 0x65 holds Ctrl+0..9 and
    Alt+0..9; `StarCraft.exe` id 0x71 holds Shift+0..9). `TranslateAcceleratorA` resolves
    FCONTROL/FSHIFT against the calling THREAD's key-state table, which Windows never
    updates for POSTED messages -- so a posted Ctrl+1 cannot match, measured as no command
    at all.

    On a match the accelerator sends `WM_COMMAND` carrying its command id, and the window
    proc's `case 0x111` puts that id straight into the game's own key dispatcher
    (`0x004846E0` via `[0x005968E0]`), which reads NOTHING from the event but that id. So
    posting the WM_COMMAND is not a simulation of the keypress: it is the same call with
    only the modifier check skipped, and the engine posts exactly such a message to itself
    at 0x004D1BA0.

    PLAIN digits are NOT accelerators -- they reach the dispatcher through the window proc
    -- so a control-group RECALL is driven with `Send-ScKey`; only assign/add need this.

    Ids come from `python tools/parse_accelerators.py <working-copy PE>`; the ones this
    repo uses are in research/data/accelerators.tsv.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][IntPtr]$Hwnd,
        [Parameter(Mandatory)][int]$CommandId,   # e.g. 0x9BDD = Ctrl+1
        [int]$SettleMs = 250
    )
    Assert-ScDrivable -Hwnd $Hwnd
    [void][ScDrive.Native]::PostMessage($Hwnd, $script:WM_COMMAND, [IntPtr]($CommandId -band 0xFFFF), [IntPtr]0)
    if ($SettleMs -gt 0) { Start-Sleep -Milliseconds $SettleMs }
}

# The control-group accelerator command ids, from research/data/accelerators.tsv.
# Group 0 is the "0" key, so index 0 of each array is group 0 and index N is group N.
$script:ScCtrlGroupAssign = @(0x9BE6, 0x9BDD, 0x9BDE, 0x9BDF, 0x9BE0, 0x9BE1, 0x9BE2, 0x9BE3, 0x9BE4, 0x9BE5)
$script:ScCtrlGroupAdd    = @(0x9BDC, 0x9BD3, 0x9BD4, 0x9BD5, 0x9BD6, 0x9BD7, 0x9BD8, 0x9BD9, 0x9BDA, 0x9BDB)

function Send-ScControlGroupAssign {
    <# .SYNOPSIS Ctrl+<group> -- store the current selection into control group 0..9. #>
    param([Parameter(Mandatory)][IntPtr]$Hwnd, [Parameter(Mandatory)][int]$Group, [int]$SettleMs = 400)
    if ($Group -lt 0 -or $Group -gt 9) { throw "drive-game: control group must be 0..9, got $Group" }
    Send-ScCommand -Hwnd $Hwnd -CommandId $script:ScCtrlGroupAssign[$Group] -SettleMs $SettleMs
}

function Send-ScControlGroupAdd {
    <# .SYNOPSIS Shift+<group> -- add the current selection to control group 0..9. #>
    param([Parameter(Mandatory)][IntPtr]$Hwnd, [Parameter(Mandatory)][int]$Group, [int]$SettleMs = 400)
    if ($Group -lt 0 -or $Group -gt 9) { throw "drive-game: control group must be 0..9, got $Group" }
    Send-ScCommand -Hwnd $Hwnd -CommandId $script:ScCtrlGroupAdd[$Group] -SettleMs $SettleMs
}

function Send-ScControlGroupRecall {
    <# .SYNOPSIS Press <group> -- recall control group 0..9. A PLAIN key: no accelerator
       is involved, so this is an ordinary posted keystroke. #>
    param([Parameter(Mandatory)][IntPtr]$Hwnd, [Parameter(Mandatory)][int]$Group, [int]$SettleMs = 400)
    if ($Group -lt 0 -or $Group -gt 9) { throw "drive-game: control group must be 0..9, got $Group" }
    Send-ScKey -Hwnd $Hwnd -VirtualKey (0x30 + $Group) -SettleMs $SettleMs
}

function Get-ScMinimapPoint {
    <#
    .SYNOPSIS
    The client pixel to click on the minimap to centre the view on a map TILE.
    .DESCRIPTION
    The view is otherwise unmovable from a script: the camera opens centred on the
    player's start location and never moves on its own, edge-scrolling needs the pointer
    parked at the very edge (which a posted WM_MOUSEMOVE does not sustain -- measured: the
    view did not move and the game exited during the attempt), and the keyboard scroll
    keys are modifier-adjacent. A LEFT click on the minimap does move the camera.

    Geometry, at a 640x480 client: the minimap box is 128x128 client pixels with its
    top-left at (7, 348) -- the console art's minimap panel, whose right edge is where the
    12-button wireframe row's root dialog begins (`HUDROW rects root=[138,...]`,
    research/hud-selection-row.md). A map of W x H tiles with both <= 128 is drawn at one
    pixel per tile and CENTRED in that box.

    Calibrated in game on a 128x96-tile fixture whose enemy block sits at tile (41,19):
    this formula gives client (48, 383), and clicking there then drag-boxing the screen
    selected exactly the six placed Hydralisks and nothing else. Clicking four pixels
    higher put only three on screen, so the vertical centring term is real and not a
    rounding accident; of nine origin candidates scanned, (7, 348) with the (128-H)/2
    offset is the one that reproduces the result for every x tried.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$MapTilesW,
        [Parameter(Mandatory)][int]$MapTilesH,
        [Parameter(Mandatory)][int]$TileX,
        [Parameter(Mandatory)][int]$TileY,
        [int]$BoxLeft = 7, [int]$BoxTop = 348, [int]$BoxSize = 128,
        # The 2x-height build moves the whole console down (Get-ScWideGeometry's
        # ConsoleShiftY); a STOCK arm passes nothing and gets the 640x480 box.
        [int]$ConsoleShiftY = 0
    )
    if ($MapTilesW -gt $BoxSize -or $MapTilesH -gt $BoxSize) {
        throw "drive-game: Get-ScMinimapPoint is calibrated for maps up to ${BoxSize}x${BoxSize} tiles; got ${MapTilesW}x${MapTilesH}. A bigger map is drawn at a smaller scale and this 1px-per-tile mapping does not hold."
    }
    if ($TileX -lt 0 -or $TileY -lt 0 -or $TileX -ge $MapTilesW -or $TileY -ge $MapTilesH) {
        throw "drive-game: tile ($TileX,$TileY) is outside a ${MapTilesW}x${MapTilesH} map."
    }
    [pscustomobject]@{
        X = $BoxLeft + [int](($BoxSize - $MapTilesW) / 2) + $TileX
        Y = $BoxTop + $ConsoleShiftY + [int](($BoxSize - $MapTilesH) / 2) + $TileY
    }
}

$script:ScMarkerSeq = 0

function Set-ScMarker {
    <#
    .SYNOPSIS
    Write one label into the plugin's marker file. The ONE place any marker is written.
    .DESCRIPTION
    NEVER `Set-Content` HERE. It opens the file with FileShare.NONE, so ANY reader holding
    it open makes the write throw -- including the plugin's own deliberately permissive
    observer, which polls this same file about four times a second. The race is only in
    the OVERLAP, not in the outcome: given overlap, the failure is certain, not rare.

    Measured, one reader held open on the flags scplugin.cpp PollMarker uses
    (GENERIC_READ, FILE_SHARE_READ|WRITE|DELETE), three writers against it:

        reader share            Set-Content   File.WriteAllText   FileShare.RW|Delete
        R|W|D (the plugin's)    FAIL          ok                  ok
        R|W   (no DELETE)       FAIL          ok                  ok
        none  (worst case)      FAIL          FAIL                FAIL

    So the fix is the SHARE MODE, not a retry: FileShare.ReadWrite|Delete is the most
    permissive there is, and -- unlike File.WriteAllText, whose default is FileShare.Read
    -- it tolerates a second driver holding the same marker too. The retry left here is a
    bounded backstop for what the share mode cannot cover: another process holding a WRITE
    handle (a second driver mid-write, an editor, a scanner).

    WRITE-TO-TEMP-THEN-RENAME is WORSE and is not used: with the marker open by that same
    permissive reader, both [IO.File]::Move(overwrite) and a raw
    MoveFileEx(MOVEFILE_REPLACE_EXISTING) fail with ERROR_ACCESS_DENIED (5) -- a rename
    cannot replace an open destination here even when the holder granted FILE_SHARE_DELETE.

    TORN READS are not a concern at this size. The write is one Write() of under ~40 bytes
    onto a truncated file, so an observer poll landing inside it sees either the empty file
    -- which PollMarker already returns from without logging -- or the whole label.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$MarkerPath,
        [Parameter(Mandatory)][string]$Label,
        [int]$Tries = 10,
        [int]$BackoffMs = 50
    )
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Label)
    $share = [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete
    $last = $null
    for ($i = 1; $i -le $Tries; $i++) {
        try {
            $fs = [System.IO.FileStream]::new($MarkerPath, [System.IO.FileMode]::Create,
                                              [System.IO.FileAccess]::Write, $share)
            try { $fs.Write($bytes, 0, $bytes.Length) } finally { $fs.Dispose() }
            return
        }
        catch [System.IO.IOException] {
            # Sharing violation or a transient lock. Anything else (a bad path, a
            # read-only directory) is not retryable and rethrows immediately.
            $last = $_
            Start-Sleep -Milliseconds ($BackoffMs * $i)
        }
    }
    throw ("drive-game: could not write the marker '$Label' to $MarkerPath after $Tries attempt(s). " +
           "Last error: $($last.Exception.Message). Something other than the game's observer is " +
           'holding that file open for writing -- another driver, an editor, or a scanner.')
}

function Get-ScUnitState {
    <#
    .SYNOPSIS
    Ask the plugin for a UNITSTATE line and parse it. THE test oracle.
    .DESCRIPTION
    Writes a unique label into the plugin's marker file and waits for the UNITSTATE
    line carrying that exact label. The plugin dumps the line when it notices the marker
    change (scplugin.cpp PollMarker), so this is a SYNCHRONOUS read of every unit's own
    state from inside the process -- not a race against the 250ms poll, and not a claim
    about the picture. It covers the whole shadow list, i.e. the entire pre-cap selection,
    not the twelve the engine holds.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LogPath,
        [Parameter(Mandatory)][string]$Tag,
        [string]$MarkerPath,
        [int]$TimeoutSec = 10
    )
    if (-not $MarkerPath) { $MarkerPath = Join-Path (Split-Path $LogPath -Parent) 'marker.txt' }
    $script:ScMarkerSeq++
    $label = "$Tag-$script:ScMarkerSeq"
    Set-ScMarker -MarkerPath $MarkerPath -Label $label
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $line = Get-Content -LiteralPath $LogPath -ErrorAction SilentlyContinue |
                Select-String -Pattern ([regex]::Escape("UNITSTATE [$label]")) |
                Select-Object -Last 1
        if ($line) {
            $m = [regex]::Match($line.Line,
                'UNITSTATE \[[^\]]*\] n=(\d+) live=(\d+) visible=(\d+) overflow=(\d+) orders=\[([^\]]*)\] orders2=\[([^\]]*)\] types=\[([^\]]*)\] burrowed=(\d+)/(\d+)')
            if (-not $m.Success) { break }
            # Every trailing field group is parsed separately and optionally, so a log
            # written by an older plugin build still parses: a missing field reads as
            # "this build did not report it", never as zero.
            $lv = [regex]::Match($line.Line,
                'uniqOnly=(\d+) recycled=(\d+) hp0=(\d+) foreign=(\d+) nosprite=(\d+) removed=(\d+) staleSkipped=(\d+) liveness=(\d+)')
            $ce = [regex]::Match($line.Line,
                'stimmed=(\d+)/(\d+) hp=\[([^\]]*)\] stim=\[([^\]]*)\] energy=\[([^\]]*)\]')
            # Rally keys are the packed (x << 16) | y the plugin logs, so ONE key means
            # every unit in the selection is rallied to the same map point -- which is
            # what "the order reached all of them" has to mean for a building.
            $bg = [regex]::Match($line.Line,
                'simSlots=(\d+) rally=\[([^\]]*)\] circled=(\d+)/(\d+)')
            $toMap = {
                param([string]$s)
                $h = @{}
                foreach ($pair in ($s -split '\s+' | Where-Object { $_ -match ':' })) {
                    $kv = $pair -split ':'
                    $h[$kv[0]] = [int]$kv[1]
                }
                $h
            }
            return [pscustomobject]@{
                N = [int]$m.Groups[1].Value; Live = [int]$m.Groups[2].Value
                Visible = [int]$m.Groups[3].Value; Overflow = [int]$m.Groups[4].Value
                Orders = (& $toMap $m.Groups[5].Value)
                Orders2 = (& $toMap $m.Groups[6].Value)
                Types = (& $toMap $m.Groups[7].Value)
                TypesText = $m.Groups[7].Value
                Burrowed = [int]$m.Groups[8].Value
                BurrowedOf = [int]$m.Groups[9].Value
                # -1 means "this build did not report it", never "it was zero".
                UniqOnly = $(if ($lv.Success) { [int]$lv.Groups[1].Value } else { -1 })
                Recycled = $(if ($lv.Success) { [int]$lv.Groups[2].Value } else { -1 })
                Hp0 = $(if ($lv.Success) { [int]$lv.Groups[3].Value } else { -1 })
                Foreign = $(if ($lv.Success) { [int]$lv.Groups[4].Value } else { -1 })
                NoSprite = $(if ($lv.Success) { [int]$lv.Groups[5].Value } else { -1 })
                Removed = $(if ($lv.Success) { [int]$lv.Groups[6].Value } else { -1 })
                StaleSkipped = $(if ($lv.Success) { [int]$lv.Groups[7].Value } else { -1 })
                Liveness = $(if ($lv.Success) { [int]$lv.Groups[8].Value } else { -1 })
                Stimmed = $(if ($ce.Success) { [int]$ce.Groups[1].Value } else { -1 })
                StimmedOf = $(if ($ce.Success) { [int]$ce.Groups[2].Value } else { -1 })
                # Keys are hex strings exactly as logged ('0x2800'), values are unit counts.
                Hp = $(if ($ce.Success) { & $toMap $ce.Groups[3].Value } else { $null })
                Stim = $(if ($ce.Success) { & $toMap $ce.Groups[4].Value } else { $null })
                Energy = $(if ($ce.Success) { & $toMap $ce.Groups[5].Value } else { $null })
                HpText = $(if ($ce.Success) { $ce.Groups[3].Value } else { '' })
                StimText = $(if ($ce.Success) { $ce.Groups[4].Value } else { '' })
                SimSlots = $(if ($bg.Success) { [int]$bg.Groups[1].Value } else { -1 })
                Rally = $(if ($bg.Success) { & $toMap $bg.Groups[2].Value } else { $null })
                RallyText = $(if ($bg.Success) { $bg.Groups[2].Value } else { '' })
                # Units carrying a selection circle right now (sprite flag 0x01),
                # engine-drawn and plugin-drawn alike, out of the live shadow list.
                Circled = $(if ($bg.Success) { [int]$bg.Groups[3].Value } else { -1 })
                CircledOf = $(if ($bg.Success) { [int]$bg.Groups[4].Value } else { -1 })
                Line = $line.Line.Trim()
            }
        }
        Start-Sleep -Milliseconds 250
    }
    throw "drive-game: no UNITSTATE line for marker '$label' within ${TimeoutSec}s (log: $LogPath)."
}

function Get-ScWorldState {
    <#
    .SYNOPSIS
    Ask the plugin for a WORLD scan and parse it. THE oracle that also exists in
    -Mode observe.
    .DESCRIPTION
    Same marker handshake as Get-ScUnitState, but the plugin answers by walking the
    ENGINE's own per-player unit lists rather than the fan-out's shadow list -- so this
    works in `-Mode observe`, where no hook is installed and there is no shadow list at
    all, which is what makes a plugin-vs-stock comparison possible with the SAME oracle on
    both sides. Needs -WorldScan 1; without it no WORLD lines are written and this throws
    on the timeout.

    A .Counts entry whose Recount disagrees with its Units means the sample was taken
    while the game thread was editing the list -- discard it, do not believe it.

    .Screen is how a suite aims a click at a unit WITHOUT measuring anything off a
    screenshot (AGENTS.md § "Oracles: what counts as a read-back"):

        Send-ScClick -Hwnd $h -X ($u.X - $c.Screen.Left) -Y ($u.Y - $c.Screen.Top)

    `client = map - viewport` is the arithmetic the engine's own click handler at
    0x0046FB40 does when it builds the rectangle it hit-tests. Check the result is inside
    the play area (x < 640, y < 340) first -- below that is the console, which eats it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LogPath,
        [Parameter(Mandatory)][string]$Tag,
        [string]$MarkerPath,
        [int]$TimeoutSec = 15
    )
    if (-not $MarkerPath) { $MarkerPath = Join-Path (Split-Path $LogPath -Parent) 'marker.txt' }
    $script:ScMarkerSeq++
    $label = "$Tag-$script:ScMarkerSeq"
    Set-ScMarker -MarkerPath $MarkerPath -Label $label
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $esc = [regex]::Escape($label)
    while ((Get-Date) -lt $deadline) {
        $lines = @(Get-Content -LiteralPath $LogPath -ErrorAction SilentlyContinue |
                   Select-String -Pattern "WORLD \[$esc\]")
        # The per-player summary line is written LAST for each player, so seeing one for
        # player 7 means the whole scan for this label has landed. Waiting for that
        # instead of for "some line" is what stops a half-written scan being parsed.
        $done = @($lines | Select-String -Pattern 'p=7 units=')
        if ($done.Count -gt 0) {
            $units = @()
            $counts = @{}
            # The viewport's top-left in MAP pixels, so a caller can convert any unit's
            # pos=(x,y) into the CLIENT coordinate a posted click must carry:
            # client = map - origin. $null when the plugin build predates it.
            $screen = $null
            foreach ($l in $lines) {
                $m = [regex]::Match($l.Line,
                    'p=(\d+) i=(\d+) unit=0x([0-9A-Fa-f]+) owner=(\d+) type=0x([0-9A-Fa-f]+) hp=(-?\d+) order=0x([0-9A-Fa-f]+) order2=0x([0-9A-Fa-f]+) stim=(\d+) energy=(\d+) pos=\((\d+),(\d+)\) flags=0x([0-9A-Fa-f]+)')
                if ($m.Success) {
                    $units += [pscustomobject]@{
                        Player = [int]$m.Groups[1].Value
                        Index  = [int]$m.Groups[2].Value
                        Unit   = $m.Groups[3].Value
                        Owner  = [int]$m.Groups[4].Value
                        Type   = [Convert]::ToInt32($m.Groups[5].Value, 16)
                        Hp     = [int]$m.Groups[6].Value
                        Order  = [Convert]::ToInt32($m.Groups[7].Value, 16)
                        Order2 = [Convert]::ToInt32($m.Groups[8].Value, 16)
                        Stim   = [int]$m.Groups[9].Value
                        Energy = [int]$m.Groups[10].Value
                        X      = [int]$m.Groups[11].Value
                        Y      = [int]$m.Groups[12].Value
                        Flags  = [Convert]::ToUInt32($m.Groups[13].Value, 16)
                    }
                    continue
                }
                $o = [regex]::Match($l.Line, 'screen=\((\d+),(\d+)\)')
                if ($o.Success) {
                    $screen = [pscustomobject]@{
                        Left = [int]$o.Groups[1].Value; Top = [int]$o.Groups[2].Value
                    }
                    continue
                }
                $s = [regex]::Match($l.Line, 'p=(\d+) units=(\d+) recount=(\d+) complete=(\d+)')
                if ($s.Success) {
                    $counts[[int]$s.Groups[1].Value] = [pscustomobject]@{
                        Units    = [int]$s.Groups[2].Value
                        Recount  = [int]$s.Groups[3].Value
                        Complete = [int]$s.Groups[4].Value
                    }
                }
            }
            return [pscustomobject]@{
                Label = $label; Units = $units; Counts = $counts; Screen = $screen
            }
        }
        Start-Sleep -Milliseconds 250
    }
    throw "drive-game: no complete WORLD scan for marker '$label' within ${TimeoutSec}s (log: $LogPath). Was the game launched with -WorldScan 1?"
}

function Get-ScCardState {
    <#
    .SYNOPSIS
    Ask the plugin to READ THE COMMAND CARD out of process memory, and parse it.
    .DESCRIPTION
    DO NOT ANSWER "can this ability be issued" BY CLICKING. Posting every key A-Z and all
    nine slots at the card gives only a bounded negative: it cannot distinguish "the
    button is greyed" from "the click missed", because both produce an empty log.

    This does not click. The plugin walks the card dialog (0x0068C148) and reports, per
    slot, the control's own visible/disabled flags plus the Button record behind it --
    ability condition, action, params and strings (research/command-card.md). Both of the
    engine's input paths refuse a control with the disabled bit set (the mouse at
    0x00459947, the hotkey predicate at 0x004588C0), so that one bit is the whole answer.

    Same marker handshake as Get-ScWorldState, and like it this installs no hook and so
    works in `-Mode observe` too. Needs -CardScan 1; without it no CARD lines are written
    and this throws on the timeout.

    `Get-ScCardSlot $card 7` picks one slot out of the returned .Slots.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LogPath,
        [Parameter(Mandatory)][string]$Tag,
        [string]$MarkerPath,
        [int]$TimeoutSec = 15
    )
    if (-not $MarkerPath) { $MarkerPath = Join-Path (Split-Path $LogPath -Parent) 'marker.txt' }
    $script:ScMarkerSeq++
    $label = "$Tag-$script:ScMarkerSeq"
    Set-ScMarker -MarkerPath $MarkerPath -Label $label
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $esc = [regex]::Escape($label)
    while ((Get-Date) -lt $deadline) {
        $lines = @(Get-Content -LiteralPath $LogPath -ErrorAction SilentlyContinue |
                   Select-String -Pattern "CARD \[$esc\]")
        # The `slots=` summary is written LAST, so waiting for it is what stops a
        # half-written scan being parsed -- same rule as the WORLD p=7 line.
        $done = @($lines | Select-String -Pattern 'slots=\d+ shown=')
        $absent = @($lines | Select-String -Pattern 'dialog=0 ')
        if ($done.Count -gt 0 -or $absent.Count -gt 0) {
            $card = [pscustomobject]@{
                Label = $label; Ok = ($done.Count -gt 0); Slots = @()
                CardId = -1; OverrideSel = -1; OverrideSub = -1; Reason = -1; RootRect = @(0,0,0,0)
                PortraitType = -1; PortraitSet = -1; PortraitEnergy = -1; PortraitOwner = -1
                SetCount = -1; SetButtons = ''
                Shown = -1; Greyed = -1
                TechPlayer = -1; TechAvailable = @(); TechResearched = @()
                Lines = @($lines | ForEach-Object { $_.Line })
            }
            foreach ($l in $lines) {
                $h = [regex]::Match($l.Line,
                    'dialog=0x([0-9A-Fa-f]+) root=0x([0-9A-Fa-f]+) cardId=(\d+) ovrSel=(\d+) ovrSub=(\d+) portrait=0x([0-9A-Fa-f]+) ptype=0x([0-9A-Fa-f]+) pset=(\d+) penergy=(\d+) powner=(\d+) set=\(n=(\d+) buttons=0x([0-9A-Fa-f]+)\) reason=(\d+) rootrect=\((-?\d+),(-?\d+),(-?\d+),(-?\d+)\)')
                if ($h.Success) {
                    $card.RootRect = @([int]$h.Groups[14].Value, [int]$h.Groups[15].Value,
                                       [int]$h.Groups[16].Value, [int]$h.Groups[17].Value)
                    $card.CardId         = [int]$h.Groups[3].Value
                    $card.OverrideSel    = [int]$h.Groups[4].Value
                    $card.OverrideSub    = [int]$h.Groups[5].Value
                    $card.PortraitType   = [Convert]::ToInt32($h.Groups[7].Value, 16)
                    $card.PortraitSet    = [int]$h.Groups[8].Value
                    $card.PortraitEnergy = [int]$h.Groups[9].Value
                    $card.PortraitOwner  = [int]$h.Groups[10].Value
                    $card.SetCount       = [int]$h.Groups[11].Value
                    $card.SetButtons     = $h.Groups[12].Value
                    $card.Reason         = [int]$h.Groups[13].Value
                    continue
                }
                $s = [regex]::Match($l.Line,
                    'slot=(\d+) (\w+)\s+ctrl=0x([0-9A-Fa-f]+) flags=0x([0-9A-Fa-f]+) icon=0x([0-9A-Fa-f]+) rect=\((-?\d+),(-?\d+),(-?\d+),(-?\d+)\) button=0x([0-9A-Fa-f]+)(?: bslot=(\d+) bicon=0x([0-9A-Fa-f]+) cond=0x([0-9A-Fa-f]+) act=0x([0-9A-Fa-f]+) cparam=(\d+) aparam=(\d+) name=0x([0-9A-Fa-f]+) dis=0x([0-9A-Fa-f]+))?')
                if ($s.Success) {
                    $hasBtn = $s.Groups[11].Success
                    $rect = @([int]$s.Groups[6].Value, [int]$s.Groups[7].Value,
                              [int]$s.Groups[8].Value, [int]$s.Groups[9].Value)
                    $card.Slots += [pscustomobject]@{
                        Index     = [int]$s.Groups[1].Value
                        State     = $s.Groups[2].Value
                        Visible   = ($s.Groups[2].Value -ne 'hidden')
                        Disabled  = ($s.Groups[2].Value -eq 'GREYED')
                        Control   = $s.Groups[3].Value
                        Flags     = [Convert]::ToUInt32($s.Groups[4].Value, 16)
                        Icon      = [Convert]::ToInt32($s.Groups[5].Value, 16)
                        Rect      = $rect
                        Button    = $s.Groups[10].Value
                        HasButton = $hasBtn
                        BSlot     = $(if ($hasBtn) { [int]$s.Groups[11].Value } else { -1 })
                        BIcon     = $(if ($hasBtn) { [Convert]::ToInt32($s.Groups[12].Value, 16) } else { -1 })
                        Cond      = $(if ($hasBtn) { $s.Groups[13].Value.ToUpperInvariant() } else { '' })
                        Action    = $(if ($hasBtn) { $s.Groups[14].Value.ToUpperInvariant() } else { '' })
                        CondParam = $(if ($hasBtn) { [int]$s.Groups[15].Value } else { -1 })
                        ActParam  = $(if ($hasBtn) { [int]$s.Groups[16].Value } else { -1 })
                        NameStr   = $(if ($hasBtn) { [Convert]::ToInt32($s.Groups[17].Value, 16) } else { -1 })
                        DisStr    = $(if ($hasBtn) { [Convert]::ToInt32($s.Groups[18].Value, 16) } else { -1 })
                    }
                    continue
                }
                $k = [regex]::Match($l.Line, 'tech p=(\d+) available=\[([^\]]*)\] researched=\[([^\]]*)\]')
                if ($k.Success) {
                    $card.TechPlayer = [int]$k.Groups[1].Value
                    $card.TechAvailable  = @($k.Groups[2].Value -split '\s+' |
                                             Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ })
                    $card.TechResearched = @($k.Groups[3].Value -split '\s+' |
                                             Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ })
                    continue
                }
                $t = [regex]::Match($l.Line, 'slots=(\d+) shown=(\d+) greyed=(\d+)')
                if ($t.Success) {
                    $card.Shown  = [int]$t.Groups[2].Value
                    $card.Greyed = [int]$t.Groups[3].Value
                }
            }
            return $card
        }
        Start-Sleep -Milliseconds 250
    }
    throw "drive-game: no complete CARD scan for marker '$label' within ${TimeoutSec}s (log: $LogPath). Was the game launched with -CardScan 1?"
}

function Get-ScCardSlot {
    <#
    .SYNOPSIS
    One slot out of a Get-ScCardState result, by card slot number (1..9).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Card, [Parameter(Mandatory)][int]$Slot)
    @($Card.Slots | Where-Object Index -eq $Slot) | Select-Object -First 1
}

function Get-ScCardSlotPoint {
    <#
    .SYNOPSIS
    The CLIENT-coordinate centre of a card slot, computed from the live dialog.
    .DESCRIPTION
    Never a hardcoded coordinate. A control's rect (+0x04) is relative to its dialog's own
    origin -- the engine adds them itself at 0x00458850 (`dlg->rct.left + child->rct.left`)
    -- so the point is rootRect + rect, halved. This is the card's answer to the "never
    click a row by number" rule: a probe that clicks a guessed slot centre cannot tell "the
    button refused the click" from "the click landed between buttons", and a whole question
    has been lost to that ambiguity. Returns @{X;Y}.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Card, [Parameter(Mandatory)][int]$Slot)
    $s = Get-ScCardSlot -Card $Card -Slot $Slot
    if (-not $s) { throw "drive-game: the card read-back has no slot $Slot." }
    @{ X = [int]($Card.RootRect[0] + [math]::Floor(($s.Rect[0] + $s.Rect[2]) / 2))
       Y = [int]($Card.RootRect[1] + [math]::Floor(($s.Rect[1] + $s.Rect[3]) / 2)) }
}

function Get-ScStatusQueue {
    <#
    .SYNOPSIS
    Ask the plugin to READ THE PRODUCTION-QUEUE STRIP out of process memory, and parse it.
    .DESCRIPTION
    Cancelling a queued unit is NOT a command-card action in vanilla: the card's slot-9
    Cancel button sends "cancel the LAST queued item" (actionParam 0xFE), and the control
    that addresses a SPECIFIC queued item is one of five icons in the STATUS PANE --
    children of the statdata dialog 0x0068C1F0 with control ids 2..6, one per display index.

    This does not click. The plugin walks that strip the way the engine's own layout
    0x004268D0 does and reports, per icon: the enabled bit BOTH input paths refuse, the
    unit type the icon is drawing (its statUser record), the rect, and the type in the
    building's OWN ring at (head + display) % 5 -- so "what the player sees" and "what the
    building holds" are two independent reads a suite can compare instead of a screenshot.

    An EMPTY queue slot's icon is DISABLED by the layout (0x00418640), so `.Clickable` is
    literally how many queued items the player can cancel by clicking. Needs -CardScan 1.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LogPath,
        [Parameter(Mandatory)][string]$Tag,
        [string]$MarkerPath,
        [int]$TimeoutSec = 15
    )
    if (-not $MarkerPath) { $MarkerPath = Join-Path (Split-Path $LogPath -Parent) 'marker.txt' }
  # A walk whose header carries ringStable=0 is NOT consumable: the plugin is saying its
  # ring read never settled against the phantom bracket's seqlock (an OS preemption inside
  # the guarded section can straddle every retry), so head/engine/qtype may be mid-window.
  # Re-ask with a fresh marker, up to three times; only then return the flagged walk, so a
  # caller's assertion fails with `.RingStable = $false` in view rather than passing or
  # failing on a disclaimed value.
  for ($scAsk = 0; $scAsk -lt 3; $scAsk++) {
    $script:ScMarkerSeq++
    $label = "$Tag-$script:ScMarkerSeq"
    Set-ScMarker -MarkerPath $MarkerPath -Label $label
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $esc = [regex]::Escape($label)
    while ((Get-Date) -lt $deadline) {
        $lines = @(Get-Content -LiteralPath $LogPath -ErrorAction SilentlyContinue |
                   Select-String -Pattern "STATQ \[$esc\]")
        # The `slots=` summary is written LAST and unconditionally -- so waiting for it
        # is what stops a half-written walk being parsed, AND makes "the strip is up but
        # nothing is clickable" an answer rather than a timeout.
        $done = @($lines | Select-String -Pattern 'slots=\d+ shown=')
        $absent = @($lines | Select-String -Pattern 'dialog=0 ')
        if ($done.Count -gt 0 -and $scAsk -lt 2 -and
            @($lines | Where-Object { $_.Line -match ' ringStable=0 ' }).Count -gt 0) {
            Write-Verbose "Get-ScStatusQueue: walk '$label' carries ringStable=0 -- re-asking"
            break
        }
        if ($done.Count -gt 0 -or $absent.Count -gt 0) {
            $st = [pscustomobject]@{
                Label = $label; Ok = ($done.Count -gt 0); Slots = @()
                Dialog = ''; Root = ''; RootRect = @(0,0,0,0)
                Portrait = ''; PortraitType = -1; PortraitOwner = -1
                Head = -1; QueueOk = $false; RingStable = $true; Engine = @()
                Shown = -1; Clickable = -1
                Lines = @($lines | ForEach-Object { $_.Line })
            }
            foreach ($l in $lines) {
                $h = [regex]::Match($l.Line,
                    'dialog=0x([0-9A-Fa-f]+) root=0x([0-9A-Fa-f]+) rootrect=\((-?\d+),(-?\d+),(-?\d+),(-?\d+)\) portrait=0x([0-9A-Fa-f]+) ptype=0x([0-9A-Fa-f]+) powner=(\d+) head=(\d+) queueOk=(\d+) ringStable=(\d+) engine=\[([^\]]*)\]')
                if ($h.Success) {
                    $st.Dialog = $h.Groups[1].Value
                    $st.Root = $h.Groups[2].Value
                    $st.RootRect = @([int]$h.Groups[3].Value, [int]$h.Groups[4].Value,
                                     [int]$h.Groups[5].Value, [int]$h.Groups[6].Value)
                    $st.Portrait = $h.Groups[7].Value
                    $st.PortraitType = [Convert]::ToInt32($h.Groups[8].Value, 16)
                    $st.PortraitOwner = [int]$h.Groups[9].Value
                    $st.Head = [int]$h.Groups[10].Value
                    $st.QueueOk = ($h.Groups[11].Value -eq '1')
                    # ringStable=0: head/engine/qtype on this walk may be mid-window, so a
                    # caller re-reads rather than trusting them (see the re-ask loop above).
                    $st.RingStable = ($h.Groups[12].Value -eq '1')
                    $st.Engine = @($h.Groups[13].Value -split ',' |
                                   Where-Object { $_ -match '^0x' } |
                                   ForEach-Object { [Convert]::ToInt32(($_ -replace '^0x'), 16) })
                    continue
                }
                $s = [regex]::Match($l.Line,
                    'disp=(\d+) (\w+)\s+idx=(-?\d+) ctrl=0x([0-9A-Fa-f]+) flags=0x([0-9A-Fa-f]+) graphic=0x([0-9A-Fa-f]+) rect=\((-?\d+),(-?\d+),(-?\d+),(-?\d+)\) user=0x([0-9A-Fa-f]+) uicon=0x([0-9A-Fa-f]+) umode=(\d+) utype=0x([0-9A-Fa-f]+) qtype=0x([0-9A-Fa-f]+)')
                if ($s.Success) {
                    $st.Slots += [pscustomobject]@{
                        Display  = [int]$s.Groups[1].Value
                        State    = $s.Groups[2].Value
                        Visible  = ($s.Groups[2].Value -ne 'hidden')
                        Disabled = ($s.Groups[2].Value -eq 'GREYED')
                        Index    = [int]$s.Groups[3].Value
                        Control  = $s.Groups[4].Value
                        Flags    = [Convert]::ToUInt32($s.Groups[5].Value, 16)
                        Graphic  = [Convert]::ToInt32($s.Groups[6].Value, 16)
                        Rect     = @([int]$s.Groups[7].Value, [int]$s.Groups[8].Value,
                                     [int]$s.Groups[9].Value, [int]$s.Groups[10].Value)
                        User     = $s.Groups[11].Value
                        UIcon    = [Convert]::ToInt32($s.Groups[12].Value, 16)
                        UMode    = [int]$s.Groups[13].Value
                        UType    = [Convert]::ToInt32($s.Groups[14].Value, 16)
                        QueueType = [Convert]::ToInt32($s.Groups[15].Value, 16)
                    }
                    continue
                }
                $t = [regex]::Match($l.Line, 'slots=(\d+) shown=(\d+) clickable=(\d+)')
                if ($t.Success) {
                    $st.Shown = [int]$t.Groups[2].Value
                    $st.Clickable = [int]$t.Groups[3].Value
                }
            }
            return $st
        }
        Start-Sleep -Milliseconds 250
    }
    if ((Get-Date) -ge $deadline) {
        throw "drive-game: no complete STATQ walk for marker '$label' within ${TimeoutSec}s (log: $LogPath). Was the game launched with -CardScan 1?"
    }
  }
  throw "drive-game: Get-ScStatusQueue fell out of its re-ask loop -- unreachable"
}

function Get-ScStatusSlotPoint {
    <#
    .SYNOPSIS
    The CLIENT-coordinate centre of one production-queue icon, from the live dialog.
    .DESCRIPTION
    Same arithmetic and the same reason as Get-ScCardSlotPoint: a control's rect
    (+0x04) is dialog-relative and the engine adds the dialog origin itself, so the
    point is rootRect + rect, halved. -Display is the DISPLAY INDEX, which is both
    the walk position the layout uses and the payload the click emits
    ({0x20, display}); the caller should assert `Index == Display + 2` first, since
    the engine takes one number from each. Returns @{X;Y}.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Status, [Parameter(Mandatory)][int]$Display)
    $s = @($Status.Slots | Where-Object Display -eq $Display) | Select-Object -First 1
    if (-not $s) { throw "drive-game: the status-strip read-back has no display index $Display." }
    @{ X = [int]($Status.RootRect[0] + [math]::Floor(($s.Rect[0] + $s.Rect[2]) / 2))
       Y = [int]($Status.RootRect[1] + [math]::Floor(($s.Rect[1] + $s.Rect[3]) / 2)) }
}

function Save-ScWindowImage {
    <#
    .SYNOPSIS
    PNG of the game's CLIENT area, via PrintWindow.
    .DESCRIPTION
    A DIAGNOSTIC, never an oracle (research/automated-testing-options.md O4). It refuses to
    write inside the repo: a screenshot you publish is picked and copied in by hand
    (AGENTS.md § "Hard rules").

    READ THIS BEFORE MEASURING A COORDINATE OFF ONE OF THESE FRAMES. With -FullWindow the
    capture is the WINDOW, including the border and title bar, while every function in
    this file clicks in CLIENT coordinates. At this game's window size the two differ by
    roughly (+5, +32): a control drawn at y=300 in the image is at y~268 in the
    coordinates you must post. That trap has already produced a "fix" to an
    already-correct combo coordinate, where the real cause was timing. Subtract the offset,
    or capture without -FullWindow, before concluding a coordinate is wrong.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][IntPtr]$Hwnd,
        [Parameter(Mandatory)][string]$Path,
        # Capture the WHOLE window rather than PW_CLIENTONLY. The windowed-mode helper
        # leaves its caption inside the reported client rectangle, so a client-only
        # grab is shifted down by the caption height and loses that many rows off the
        # bottom -- which is exactly where the HUD is.
        [switch]$FullWindow,
        # The client area cut out of a WHOLE-window capture by geometry: the frame's
        # side borders are equal and everything else sits above the client rect, so
        # (windowW - clientW) / 2 and windowH - clientH - that are the client's offsets.
        # Immune to the caption's colour, which the strip detector below depends on
        # (a dark caption is never a light strip, and the game then lands shifted down
        # by the caption height with as many rows lost off the bottom).
        [switch]$ClientByGeometry
    )
    Assert-ScDrivable -Hwnd $Hwnd
    Assert-ScDrawing
    $full = [IO.Path]::GetFullPath($Path)
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    if ($full.StartsWith($repoRoot, [StringComparison]::OrdinalIgnoreCase) -and
        $full -notmatch '\\work\\scratch\\') {
        throw "drive-game: refusing to write a game frame into the repo at '$full' -- frames go under C:\sc-work\ or work/scratch/; a screenshot you publish is picked and copied in by hand (AGENTS.md hard rule 1)."
    }
    New-Item -ItemType Directory -Path (Split-Path $full -Parent) -Force | Out-Null

    $whole = $FullWindow -or $ClientByGeometry
    $sz = if ($whole) { Get-ScWindowSize -Hwnd $Hwnd } else { Get-ScClientSize -Hwnd $Hwnd }
    $flags = if ($whole) { 0 } else { 2 }
    if ($sz.Width -le 0 -or $sz.Height -le 0) { throw 'drive-game: the window has no client area.' }

    # PW_CLIENTONLY == 2. PrintWindow reads one window and the live game survives it --
    # never a screen grab.
    $bmp = New-Object System.Drawing.Bitmap($sz.Width, $sz.Height,
                     [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        try {
            $hdc = $g.GetHdc()
            try { $ok = [ScDrive.Native]::PrintWindow($Hwnd, $hdc, $flags) }
            finally { $g.ReleaseHdc($hdc) }
        } finally { $g.Dispose() }
        if (-not $ok) { throw "drive-game: PrintWindow failed for hwnd 0x$('{0:X}' -f [int64]$Hwnd)." }

        # THE SHIM-CAPTION TRAP, fixed HERE because independent readers keep
        # measuring the caption instead of the game (a "resource bar" band that read
        # the gray caption reported nonzero=1.0 forever -- a probe that could not
        # fail). cnc-ddraw leaves its caption INSIDE the reported client rectangle
        # and presents the game's H rows scaled into the (H - caption) rows below it,
        # so a raw client grab is the TITLE BAR plus a vertically squeezed game and
        # "row y" means nothing. Detect the near-uniform light strip anchored at row
        # 0, crop it, and resample the remainder back to the client height
        # (NearestNeighbor inverts the shim's own downscale, it invents no pixels).
        # WMode skins its caption outside the client area and dark game rows never
        # match the detector, so those captures pass through untouched (h=0).
        if ($ClientByGeometry) {
            $cli = Get-ScClientSize -Hwnd $Hwnd
            $bx = [int][Math]::Floor(($bmp.Width - $cli.Width) / 2)
            $by = $bmp.Height - $cli.Height - $bx
            if ($bx -lt 0 -or $by -lt 0) { throw "drive-game: the window ($($bmp.Width)x$($bmp.Height)) is smaller than its client area ($($cli.Width)x$($cli.Height))." }
            $crop = $bmp.Clone([System.Drawing.Rectangle]::new($bx, $by, $cli.Width, $cli.Height), $bmp.PixelFormat)
            try { $crop.Save($full, [System.Drawing.Imaging.ImageFormat]::Png) } finally { $crop.Dispose() }
            Write-Verbose "drive-game: client rect cut out of the whole-window capture at ($bx,$by)"
        }
        elseif (-not $FullWindow) {
            $capH = 0
            for ($y = 0; $y -lt [Math]::Min(40, $bmp.Height); $y++) {
                $light = 0; $n = 0
                for ($x = 0; $x -lt $bmp.Width; $x += 4) {
                    $c = $bmp.GetPixel($x, $y); $n++
                    $r = [int]$c.R; $gg = [int]$c.G; $b = [int]$c.B
                    if (([Math]::Abs($r - $gg) -lt 16) -and ([Math]::Abs($gg - $b) -lt 16) -and
                        (($r + $gg + $b) -gt 330)) { $light++ }
                }
                if ($n -eq 0 -or ($light / $n) -lt 0.70) { break }
                $capH = $y + 1
            }
            if ($capH -ge 10) {
                $rect = [System.Drawing.Rectangle]::new(0, $capH, $bmp.Width, $bmp.Height - $capH)
                $crop = $bmp.Clone($rect, $bmp.PixelFormat)
                try {
                    $out = New-Object System.Drawing.Bitmap($bmp.Width, $bmp.Height,
                                     [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
                    try {
                        $g2 = [System.Drawing.Graphics]::FromImage($out)
                        try {
                            $g2.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
                            $g2.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
                            $g2.DrawImage($crop, [System.Drawing.Rectangle]::new(0, 0, $out.Width, $out.Height))
                        } finally { $g2.Dispose() }
                        $out.Save($full, [System.Drawing.Imaging.ImageFormat]::Png)
                    } finally { $out.Dispose() }
                } finally { $crop.Dispose() }
                Write-Verbose "drive-game: shim caption strip of $capH rows cropped and the game rescaled to client height (065/073 trap)"
            }
            else {
                $bmp.Save($full, [System.Drawing.Imaging.ImageFormat]::Png)
            }
        }
        else {
            $bmp.Save($full, [System.Drawing.Imaging.ImageFormat]::Png)
        }
    } finally { $bmp.Dispose() }

    Write-Verbose "drive-game: frame -> $full"
    $full
}

function Wait-ScLogMatch {
    <#
    .SYNOPSIS
    Block until the plugin log contains a line matching -Pattern, or time out.
    .DESCRIPTION
    The plugin log is the test ORACLE (research/automated-testing-options.md O1/O2): it is
    written from inside the process, so it reports what the engine actually did rather than
    what a screenshot suggests. Returns the matching lines; throws on timeout.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LogPath,
        [Parameter(Mandatory)][string]$Pattern,
        [int]$TimeoutSec = 30,
        [int]$FromLine = 0
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        if (Test-Path -LiteralPath $LogPath) {
            $lines = @(Get-Content -LiteralPath $LogPath -ErrorAction SilentlyContinue)
            if ($lines.Count -gt $FromLine) {
                $hit = @($lines[$FromLine..($lines.Count - 1)] | Where-Object { $_ -match $Pattern })
                if ($hit.Count -gt 0) { return $hit }
            }
        }
        Start-Sleep -Milliseconds 300
    }
    throw "drive-game: no log line matching '$Pattern' within ${TimeoutSec}s (log: $LogPath)."
}

function Get-ScLogLineCount {
    param([Parameter(Mandatory)][string]$LogPath)
    if (-not (Test-Path -LiteralPath $LogPath)) { return 0 }
    @(Get-Content -LiteralPath $LogPath -ErrorAction SilentlyContinue).Count
}

# --- the game's own dialogs --------------------------------------------------
#
# The plugin walks the engine's active-dialog list every tick and logs one line per CHANGE
# of the set (scplugin.cpp ScanDialogs, list head SC_VA_DIALOG_LIST). That line is what
# makes "is the tips dialog up, and where is its OK button" answerable without a hardcoded
# point -- the same reason every map-browser row is computed. Line shape (one dialog per
# ' | ' chunk, controls inline):
#   DIALOGS n=13  dlg='Tips_Dlg' rect=128,32,511,287 ctrl='o.O.K' rect=20,216,123,243 type=1 flags=0x...
# Control bounds are LOCAL to their dialog's origin -- the same convention the HUD row
# uses -- so a client pixel is dialog.left + ctrl.left.

function Get-ScDialogs {
    <#
    .SYNOPSIS
    The game's currently active dialogs, as objects, from the newest DIALOGS log line.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$LogPath)

    if (-not (Test-Path -LiteralPath $LogPath)) { return @() }
    $line = @(Get-Content -LiteralPath $LogPath -ErrorAction SilentlyContinue |
              Select-String -Pattern 'DIALOGS n=' | Select-Object -Last 1)
    if ($line.Count -eq 0) { return @() }
    $text = $line[0].Line

    $out = @()
    foreach ($chunk in ($text -split ' \| ')) {
        $m = [regex]::Match($chunk, "dlg='([^']*)' rect=(-?\d+),(-?\d+),(-?\d+),(-?\d+)")
        if (-not $m.Success) { continue }
        $ctrls = @()
        foreach ($c in [regex]::Matches($chunk, "ctrl='([^']*)' rect=(-?\d+),(-?\d+),(-?\d+),(-?\d+) type=(\d+) flags=0x([0-9A-Fa-f]+)")) {
            $ctrls += [pscustomobject]@{
                Text  = $c.Groups[1].Value
                Left  = [int]$c.Groups[2].Value; Top    = [int]$c.Groups[3].Value
                Right = [int]$c.Groups[4].Value; Bottom = [int]$c.Groups[5].Value
                Type  = [int]$c.Groups[6].Value
                Flags = [Convert]::ToUInt32($c.Groups[7].Value, 16)
            }
        }
        $out += [pscustomobject]@{
            Name  = $m.Groups[1].Value
            Left  = [int]$m.Groups[2].Value; Top    = [int]$m.Groups[3].Value
            Right = [int]$m.Groups[4].Value; Bottom = [int]$m.Groups[5].Value
            Controls = $ctrls
        }
    }
    # Streamed, not returned as one array object: `,$out` would hand the whole array to a
    # downstream Where-Object AS A SINGLE ITEM, and `$_.Name -match ...` on an array is
    # truthy whenever any element matches, so every filter would return the entire list.
    $out
}

function Wait-ScDialog {
    <#
    .SYNOPSIS
    Wait for a dialog whose name matches -Name to be active (or, with -Gone, to not be).
    Returns the dialog object (or $null with -Gone). Returns $null on timeout rather
    than throwing -- the caller decides whether an absent dialog is a failure.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LogPath,
        [Parameter(Mandatory)][string]$Name,
        [int]$TimeoutSec = 15,
        [switch]$Gone
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ($true) {
        $hit = @(Get-ScDialogs -LogPath $LogPath | Where-Object { $_.Name -match $Name })
        if ($Gone) { if ($hit.Count -eq 0) { return $null } }
        elseif ($hit.Count -gt 0) { return $hit[0] }
        if ((Get-Date) -ge $deadline) { return $(if ($Gone) { $hit[0] } else { $null }) }
        Start-Sleep -Milliseconds 300
    }
}

function Dismiss-ScTipsDialog {
    <#
    .SYNOPSIS
    Close the in-game "StarCraft Tips" dialog by clicking ITS OWN OK button, and prove
    it is gone.
    .DESCRIPTION
    A fixed `Send-ScClick -X 200 -Y 261` with no check at either end is the map-browser
    row-by-number defect in a different costume: a point that is right until the day it is
    not, then failing silently into the game world underneath.

    So this reads the engine's own dialog list (the plugin's DIALOGS line): the OK
    button's centre comes from the button's OWN bounds, which are local to the dialog's
    origin (client = dialog.left + ctrl.left). A dialog that never appears is a normal
    reported outcome; one still up after the click THROWS, because a tip dialog left up
    eats every later click in the run.

    NOT the registry. The dialog's "Show Tips at Startup" checkbox is wired to
    HKCU:\SOFTWARE\Blizzard Entertainment\Starcraft, which is live user state and
    AGENTS.md § "Hard rules" territory. This dismisses the dialog for THIS run and
    leaves the user's setting exactly as it was.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][IntPtr]$Hwnd,
        [Parameter(Mandatory)][string]$LogPath,
        [int]$TimeoutSec = 20
    )
    $dlg = Wait-ScDialog -LogPath $LogPath -Name 'Tips_Dlg' -TimeoutSec $TimeoutSec
    if (-not $dlg) {
        Write-Host '       tips dialog: never appeared (nothing to dismiss)'
        return $false
    }

    # 'o.O.K' -- the plugin replaces the hotkey markers the engine stores in the
    # string with '.', so the match is on the letters that survive that.
    $ok = @($dlg.Controls | Where-Object { ($_.Text -replace '[^A-Za-z]', '') -cmatch 'OK' })
    if ($ok.Count -eq 0) {
        throw ("drive-game: the tips dialog is up but has no OK control in the engine's own " +
               "control list (controls: $(($dlg.Controls | ForEach-Object { $_.Text }) -join ', ')). " +
               'Refusing to click a guessed point.')
    }
    $x = $dlg.Left + [int](($ok[0].Left + $ok[0].Right) / 2)
    $y = $dlg.Top  + [int](($ok[0].Top + $ok[0].Bottom) / 2)
    Write-Host ("       tips dialog: up at {0},{1}; clicking its OK at {2},{3}" -f $dlg.Left, $dlg.Top, $x, $y)
    Send-ScClick -Hwnd $Hwnd -X $x -Y $y

    $still = Wait-ScDialog -LogPath $LogPath -Name 'Tips_Dlg' -TimeoutSec 10 -Gone
    if ($still) {
        throw ('drive-game: the tips dialog is STILL up after clicking its OK button. ' +
               'Every later click in this run would land on it instead of the game.')
    }
    Write-Host '       tips dialog: dismissed and gone'
    return $true
}

function Invoke-ScClickUntilDialog {
    <#
    .SYNOPSIS
    Click a menu point and wait for the dialog it opens, clicking again when the dialog
    does not appear. Returns the dialog, or $null after the last try.
    .DESCRIPTION
    NEVER replace the wait with a sleep: a glue screen still animating in swallows a click
    posted on a schedule, and under load any schedule is early (measured: with another
    process pegging the CPU the title screen was still up at attach, and clicks timed by
    sleeps stuck at the Original/Expansion chooser three runs in a row). The engine's own
    dialog list says when the screen is there.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][IntPtr]$Hwnd, [Parameter(Mandatory)][string]$LogPath,
        [Parameter(Mandatory)][int]$X, [Parameter(Mandatory)][int]$Y,
        # A regex on the dialog NAME (Wait-ScDialog matches with -match).
        [Parameter(Mandatory)][string]$Name,
        # The wait stays long on every try: a retry fired while a slow screen is still
        # sliding in lands on THAT screen, which is worse than a slow walk.
        [int]$Tries = 3, [int]$WaitSec = 12, [string]$Noun = 'walk'
    )
    for ($i = 1; $i -le $Tries; $i++) {
        Send-ScClick -Hwnd $Hwnd -X $X -Y $Y
        $d = Wait-ScDialog -LogPath $LogPath -Name $Name -TimeoutSec $WaitSec
        if ($d) { return $d }
        Write-Host ("       ${Noun}: '$Name' not up ${WaitSec}s after click $i/$Tries at ($X,$Y)" + $(if ($i -lt $Tries) { '; retrying' } else { '' }))
    }
    $null
}

function Enter-ScCustomGame {
    <#
    .SYNOPSIS
    Main menu -> Single Player -> Expansion -> the first registry entry -> Play Custom ->
    the fixture map -> Use Map Settings read back -> Ok -> Start -> tips dismissed: THE
    walk into a loaded custom game, every screen waited for in the engine's own dialog list
    and its click retried (Invoke-ScClickUntilDialog). The short sleeps left cover a
    screen's slide-in after it is listed, which the list does not show as a separate state.
    .DESCRIPTION
    -AtBrowser runs once the map browser is up, before the map is selected; -BeforeStart
    runs with the map selected and the game type read back, before Ok, for a suite that
    captures the lobby. Both run in a child scope: a value they must hand back goes through
    $script:. -Fixtures is omitted only for a stock map this run did not generate.
    -ActivationNudge posts the activation nudge before every input, which the
    off-screen cnc-ddraw glue screens need and WMode does not (AGENTS.md § "Glue-screen
    (menu) input under cnc-ddraw"); the walk always leaves the nudge OFF, whatever the
    shell had, because it re-syncs the cursor and is fatal before an in-game click.
    The dialog names are the engine's own: the Original/Expansion chooser is 'Delete', the
    registry is 'Login', the briefing is the race's screen ('TerranRR', 'ReadyZ', ...), and
    the console's 'Minimap' root is the first sign of a loaded game.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][IntPtr]$Hwnd,
        [Parameter(Mandatory)][string]$LogPath,
        $Fixtures,
        [Parameter(Mandatory)][string]$MapPath,
        [Parameter(Mandatory)][string]$GameDir,
        [scriptblock]$AtBrowser,
        [scriptblock]$BeforeStart,
        [switch]$ActivationNudge,
        [string]$Noun = 'walk'
    )
    if ($ActivationNudge) { $env:SCDRIVE_POST_ACTIVATE = '1' }
    try {
        if (-not (Wait-ScDialog -LogPath $LogPath -Name '^MainMenu$' -TimeoutSec 60)) { throw "${Noun}: the main menu never appeared." }
        Start-Sleep -Seconds 2
        if (-not (Invoke-ScClickUntilDialog -Hwnd $Hwnd -LogPath $LogPath -X 215 -Y 119 -Name '^Delete$' -Noun $Noun)) { throw "${Noun}: the Original/Expansion chooser never appeared." }
        if (-not (Invoke-ScClickUntilDialog -Hwnd $Hwnd -LogPath $LogPath -X 373 -Y 300 -Name '^Login$' -Noun $Noun)) { throw "${Noun}: the registry never appeared." }
        # The registry's list slides in for ~0.8 s after its dialog is listed and takes no
        # click before that, and Ok without a selected entry does nothing, so the entry
        # click and Ok are retried as a PAIR against the screen they open.
        Start-Sleep -Seconds 1
        $race = $null
        for ($try = 1; $try -le 3 -and -not $race; $try++) {
            Send-ScClick -Hwnd $Hwnd -X 75 -Y 111
            $race = Invoke-ScClickUntilDialog -Hwnd $Hwnd -LogPath $LogPath -X 516 -Y 392 -Name '^RaceSelection$' -Tries 1 -WaitSec 15 -Noun $Noun
            if (-not $race -and $try -lt 3) { Write-Host "       ${Noun}: retrying the registry entry + Ok pair ($($try + 1)/3)" }
        }
        if (-not $race) { throw "${Noun}: RaceSelection never appeared." }
        Start-Sleep -Seconds 1
        if (-not (Invoke-ScClickUntilDialog -Hwnd $Hwnd -LogPath $LogPath -X 327 -Y 415 -Name '^Create$' -WaitSec 15 -Noun $Noun)) { throw "${Noun}: the map browser never appeared." }
        Start-Sleep -Seconds 2
        if ($AtBrowser) { & $AtBrowser }
        if ($Fixtures) { Assert-ScFixtureStillMine -Run $Fixtures -MapPath $MapPath }
        Select-ScBrowserMap -Hwnd $Hwnd -GameDir $GameDir -MapPath $MapPath | Out-Null
        Assert-ScGameType -LogPath $LogPath
        if ($BeforeStart) { & $BeforeStart }
        $briefing = '^(\w+RR|Ready\w*)$'
        if (-not (Invoke-ScClickUntilDialog -Hwnd $Hwnd -LogPath $LogPath -X 516 -Y 393 -Name $briefing -WaitSec 20 -Noun $Noun)) { throw "${Noun}: the mission briefing never appeared." }
        Start-Sleep -Seconds 3
        if (-not (Invoke-ScClickUntilDialog -Hwnd $Hwnd -LogPath $LogPath -X 544 -Y 387 -Name '^Minimap$' -WaitSec 10 -Tries 1 -Noun $Noun)) {
            # Start is clicked again only while the briefing is still the screen. An accepted
            # Start closes it within a second and the list stays empty while the map loads,
            # so a second click then would land in the game when it arrives.
            if (@(Get-ScDialogs -LogPath $LogPath | Where-Object { $_.Name -match $briefing }).Count -gt 0) {
                Write-Host "       ${Noun}: the briefing is still up 10 s after Start; clicking Start once more"
                Send-ScClick -Hwnd $Hwnd -X 544 -Y 387
            }
            if (-not (Wait-ScDialog -LogPath $LogPath -Name '^Minimap$' -TimeoutSec 60)) { throw "${Noun}: the game never loaded (no Minimap root in the dialog list 70 s after Start)." }
        }
        # The tips dialog, when the player has it on, is listed in the same dialog scan
        # as the Minimap root or the next one (measured across every log that had it),
        # so a short wait decides it; the default would idle 20 s in every walk without it.
        Dismiss-ScTipsDialog -Hwnd $Hwnd -LogPath $LogPath -TimeoutSec 3 | Out-Null
        Start-Sleep -Seconds 2
    }
    finally {
        $env:SCDRIVE_POST_ACTIVATE = '0'
    }
}

# =============================================================================
# ANY DIALOG, BY ITS OWN CONTROLS
# =============================================================================
#
# The general form of Dismiss-ScTipsDialog: find the control by what the ENGINE says it
# says, compute the click point from that control's OWN bounds, and print the whole
# inventory when it is not there rather than clicking a guessed point. Shared here so the
# in-game menu and the Save/Load dialogs need no per-suite copy of it.
#
# Control text is what the plugin's DIALOGS line carries, and the plugin renders the
# engine's hotkey markers as '.' -- so every match here is made on the LETTERS of the
# text ('o.O.K' -> 'OK'), never on the raw string.

function Show-ScDialogInventory {
    <#
    .SYNOPSIS
    Print every active dialog and every control that carries text. The thing to look at
    when a click cannot find its target.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$LogPath, [string]$What = '')
    Write-Host "       dialog inventory$(if ($What) { " ($What)" }):"
    $any = $false
    foreach ($d in (Get-ScDialogs -LogPath $LogPath)) {
        $any = $true
        Write-Host ("         dlg '{0}' rect={1},{2},{3},{4}" -f $d.Name, $d.Left, $d.Top, $d.Right, $d.Bottom)
        foreach ($c in $d.Controls) {
            Write-Host ("           ctrl '{0}' rect={1},{2},{3},{4} type={5} flags=0x{6:X}" -f `
                $c.Text, $c.Left, $c.Top, $c.Right, $c.Bottom, $c.Type, $c.Flags)
        }
    }
    if (-not $any) { Write-Host '         (the engine reports no active dialog)' }
}

function Find-ScDialogControl {
    <#
    .SYNOPSIS
    Every (dialog, control) pair whose control text's LETTERS match -Pattern, each with
    the client-coordinate centre of that control computed from its own bounds.
    .DESCRIPTION
    client = dialog.left + ctrl.left, which is the addition the engine itself does at
    0x00458850 -- the same arithmetic Get-ScCardSlotPoint uses for a card slot.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$LogPath, [Parameter(Mandatory)][string]$Pattern)
    $out = @()
    foreach ($d in (Get-ScDialogs -LogPath $LogPath)) {
        foreach ($c in $d.Controls) {
            $letters = ($c.Text -replace '[^A-Za-z]', '')
            if ($letters -match $Pattern) {
                $out += [pscustomobject]@{
                    Dialog = $d; Control = $c; Letters = $letters
                    X = $d.Left + [int](($c.Left + $c.Right) / 2)
                    Y = $d.Top + [int](($c.Top + $c.Bottom) / 2)
                }
            }
        }
    }
    $out
}

function Wait-ScDialogControl {
    <#
    .SYNOPSIS
    Wait for a control whose letters match -Pattern. $null on timeout -- the caller
    decides whether that is a failure.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$LogPath, [Parameter(Mandatory)][string]$Pattern,
          [int]$TimeoutSec = 15)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ($true) {
        $hit = @(Find-ScDialogControl -LogPath $LogPath -Pattern $Pattern)
        if ($hit.Count -gt 0) { return $hit[0] }
        if ((Get-Date) -ge $deadline) { return $null }
        Start-Sleep -Milliseconds 300
    }
}

function Invoke-ScDialogControl {
    <#
    .SYNOPSIS
    Click the control whose letters match -Pattern, at its own centre. THROWS with the
    full dialog inventory if it is not there -- never a guessed point.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][IntPtr]$Hwnd, [Parameter(Mandatory)][string]$LogPath,
        [Parameter(Mandatory)][string]$Pattern, [string]$What, [int]$TimeoutSec = 15,
        [int]$SettleMs = 700
    )
    if (-not $What) { $What = $Pattern }
    $hit = Wait-ScDialogControl -LogPath $LogPath -Pattern $Pattern -TimeoutSec $TimeoutSec
    if (-not $hit) {
        Show-ScDialogInventory -LogPath $LogPath -What "looking for $What"
        throw ("drive-game: no control whose letters match '$Pattern' ($What) is in the engine's " +
               'own dialog list. Refusing to click a guessed point.')
    }
    Write-Host ("       {0}: control '{1}' of dlg '{2}' -> click ({3},{4})" -f `
        $What, $hit.Control.Text, $hit.Dialog.Name, $hit.X, $hit.Y)
    Send-ScClick -Hwnd $Hwnd -X $hit.X -Y $hit.Y
    if ($SettleMs -gt 0) { Start-Sleep -Milliseconds $SettleMs }
    $hit
}

function Open-ScGameMenu {
    <#
    .SYNOPSIS
    Open the in-game menu with the engine's own key (F10) and prove it is up by ITS OWN
    CONTENT -- a control whose letters contain 'Save' -- rather than by a dialog name.
    .DESCRIPTION
    Retries the key: the menu is a posted-input dialog like every other, and one lost
    keypress must not read as "this build has no menu". Throws with the inventory after
    three tries.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][IntPtr]$Hwnd, [Parameter(Mandatory)][string]$LogPath,
          [int]$Tries = 3)
    for ($try = 1; $try -le $Tries; $try++) {
        Send-ScKey -Hwnd $Hwnd -VirtualKey 0x79      # VK_F10
        Start-Sleep -Milliseconds 800
        $hit = Wait-ScDialogControl -LogPath $LogPath -Pattern 'Save' -TimeoutSec 5
        if ($hit) {
            Write-Host "       game menu is up (dlg '$($hit.Dialog.Name)') after $try F10 press(es)"
            return $hit.Dialog
        }
    }
    Show-ScDialogInventory -LogPath $LogPath -What "after $Tries F10 presses"
    throw "drive-game: the in-game menu never appeared after $Tries F10 presses."
}

function Send-ScText {
    <#
    .SYNOPSIS
    Type a string into whatever edit control has the engine's focus: ONE WM_CHAR per
    character, and nothing else.
    .DESCRIPTION
    ONE MESSAGE PER CHARACTER, AND THAT IS THE WHOLE POINT. `Send-ScKey -Char` posts
    WM_KEYDOWN, then WM_CHAR, then WM_KEYUP -- and this engine's dialog edit control
    takes BOTH the key-down and the char as an insertion. Measured, typing into the Save
    dialog: the string 'slprobe' arrived in the box as

        ctrl 'ssllpprroobbee' rect=32,44,351,61 type=8

    read straight out of the engine's own control text. A suite trusting its own variable
    for the filename would save to a name it never chose and then look for the wrong file
    (AGENTS.md § "Oracles: what counts as a read-back").

    So the character path posts WM_CHAR alone. -ClearCount sends that many VK_BACK presses
    first (a key with no char, which the box takes exactly once), because this box opens
    pre-filled with the last save's name and would otherwise produce a string the caller
    cannot predict. Nothing here proves the text landed: the CALLER checks the engine's
    own result -- the control's text on the next dialog read, or the file on disk.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][IntPtr]$Hwnd, [Parameter(Mandatory)][string]$Text,
          [int]$ClearCount = 0, [int]$PerCharMs = 40)
    Assert-ScDrivable -Hwnd $Hwnd
    for ($i = 0; $i -lt $ClearCount; $i++) {
        Send-ScKey -Hwnd $Hwnd -VirtualKey 0x08 -HoldMs 15 -SettleMs 25
    }
    foreach ($ch in $Text.ToCharArray()) {
        [void][ScDrive.Native]::PostMessage($Hwnd, $script:WM_CHAR, [IntPtr][int][char]$ch, [IntPtr]1)
        Start-Sleep -Milliseconds $PerCharMs
    }
}

# --- hook-set composition, by NAME rather than a hardcoded total ---------------

# The five hooks sc_fanout.cpp installs unconditionally in fanout mode plus the three
# optional single-hook features, named exactly as ScHookInstall logs them
# (sc_circles.cpp:340, sc_hudrow.cpp:828, sc_queueind.cpp:788). Callers pass what the
# RUN'S OWN `FANOUT config:` line reported, never a source-level default, so this stays
# right even if a default changes.
#
# THIS FUNCTION RETURNS SC_FANOUT'S OWN INSTALLS AND NOTHING ELSE, and that scope is
# load-bearing rather than tidy: sc_fanout logs its own `HOOK: n/n installed` summary
# counting only the hooks IT installed, and the suites corroborate the named set against
# that number, so a hook another module splices must not be in here. The union, for the
# by-NAME comparison against a log that sees every module, is Get-ScPluginExpectedHooks.
function Get-ScFanoutExpectedHooks {
    param([bool]$Circles, [bool]$HudRow, [bool]$QueueInd)
    $names = @('queueCommand', 'CMDACT_Select', 'sortOverflowHandler', 'SortAllUnits',
               'unit_IsStandardAndMovable')
    if ($Circles) { $names += 'CreateNewUnitSelectionsFromList' }
    if ($HudRow) { $names += 'statDataUpdate' }
    if ($QueueInd) { $names += 'statDisplayDriver' }
    $names
}

# Hooks that are NOT sc_fanout's, so they never appear in its `HOOK: n/n installed`
# summary, but which every non-observe run does splice and which therefore DO appear in
# the log the by-name comparison reads.
#
# The GAME-SESSION EPOCH (sc_session.cpp): one hook is the epoch bump, the other the load
# witness. Neither is optional and neither has a config flag -- the epoch is what stops
# every module's records following the player into a game they do not belong to -- so a
# run missing either one is a run whose whole cross-game defence is off, and naming them
# here is what makes that visible rather than silent.
function Get-ScSessionExpectedHooks {
    @('gameStartClear+7', 'loadSavedGame')
}

# Everything a non-observe run installs, for comparing against the log's own
# `HOOK <name>: installed at` lines -- which carry every module's, not just sc_fanout's.
function Get-ScPluginExpectedHooks {
    param([bool]$Circles, [bool]$HudRow, [bool]$QueueInd)
    @(Get-ScFanoutExpectedHooks -Circles $Circles -HudRow $HudRow -QueueInd $QueueInd) +
    @(Get-ScSessionExpectedHooks)
}

# A count mismatch names no hook; this returns which names are missing and which
# are unexpected, so a hook added or removed tomorrow shows up by name in the
# failure, in whichever suite calls it.
function Compare-ScHookNames {
    param([string[]]$Expected, [string[]]$Actual)
    $expSet = @($Expected | Sort-Object -Unique)
    $actSet = @($Actual | Sort-Object -Unique)
    $missing = @($expSet | Where-Object { $actSet -notcontains $_ })
    $extra = @($actSet | Where-Object { $expSet -notcontains $_ })
    @{ Ok = ($missing.Count -eq 0 -and $extra.Count -eq 0); Missing = $missing; Extra = $extra
       Expected = $expSet; Actual = $actSet }
}
