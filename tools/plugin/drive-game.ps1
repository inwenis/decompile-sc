#Requires -Version 7
<#
.SYNOPSIS
Drive a running StarCraft 1.16.1 window with POSTED Win32 messages, and read frames back
out of it. Dot-source it; every function is a primitive, nothing here runs on import.

.DESCRIPTION
This is task 012's D1 recipe (research/automated-testing-options.md §4.1) turned into
reusable primitives, so a test can load a map, drag a selection box and issue an order with
no human at the keyboard.

Why posted messages and not synthetic input:

- `SendInput`/`SendKeys` are BANNED by config/guard-destructive.ps1, and task 012 diagnosed
  why they never worked here anyway.
- StarCraft imports no DirectInput and does not call `GetAsyncKeyState`; its input arrives
  through `GetMessageA`/`PeekMessageA`/`DispatchMessageA` (research/pe-anatomy.md § Imports).
  It takes the pointer position from the message's `lParam`, which task 012 demonstrated
  live: a posted click moved the game's OWN rendered cursor to the posted point.
- **No screen coordinates are involved.** Everything below is client coordinates, so nothing
  depends on where the window sits, on DPI, or on which monitor is which.
- Focus is NOT required (task 012 probe 3). The window must not be MINIMISED (probe 2) --
  `Assert-ScDrivable` refuses in that state rather than posting into a black hole.

KNOWN LIMIT -- POSITIONAL SELECTION IS A CORRECTNESS HAZARD, not a convenience. Every
menu step in this repo clicks a ROW, not a name: "the map file is row 2, because there is
exactly one .scx in the folder". That assumption is not checkable from a click, and when
it breaks the run does not fail -- it succeeds against the wrong thing and reports
confident nonsense.

For the MAP BROWSER that is now handled rather than merely warned about: `Select-ScBrowserMap`
computes every row from the filesystem and verifies each directory it opens against the
live window before the next click (see the block comment above Get-ScBrowserListing). The
warning still stands for every other screen here -- the main menu, the lobby, the in-game
command card -- whose coordinates are fixed points read off a frame.

It has happened. On 2026-08-09 another worker's `022-ghosts.scx` appeared in the shared
fixture folder beside `combat.scx`; it sorts first, so a suite's row-2 click loaded THEIR
map and the test went on to box 36 units of type `0x01` (Ghost) where its own fixture
places Lurkers (`0x67`). The map was deleted afterwards too, but that was the lesser harm:
a deleted file is noticed, a silently substituted one is not.

So a test that selects by position must make the assumption behind the position TRUE
before it clicks -- refuse to start if anything it did not create is in that folder -- and
must assert what it actually got afterwards (unit types and counts), never just that a
click landed. AGENTS.md § "Shared test-fixture folder" carries the fixture-naming rules.

KNOWN LIMIT -- modifier keys. `GetKeyState` is in the import table, and Windows does not
update a thread's key-state table for POSTED keyboard messages. So a game that reads shift
via `GetKeyState` cannot be shift-clicked this way. `Send-ScClick -Shift` therefore does
BOTH: it sets `MK_SHIFT` in `wParam` (which is what a real click carries) and brackets the
click with posted `WM_KEYDOWN`/`WM_KEYUP` for VK_SHIFT. Whether that is enough is an
empirical question about this binary -- `Test-ScShiftClick` in the caller decides, and a
failure means "test shift by hand", not "shift is broken".

.EXAMPLE
. ./tools/plugin/drive-game.ps1
$h = Get-ScGameWindow -ProcessId 1234
Send-ScClick -Hwnd $h -X 215 -Y 119
Send-ScDrag  -Hwnd $h -X1 60 -Y1 60 -X2 500 -Y2 300
Save-ScWindowImage -Hwnd $h -Path C:\temp\frame.png
#>

Set-StrictMode -Version Latest

# System.Drawing is deliberately NOT used from the C# below. On .NET 10 the GDI+ types
# live in a private assembly that Add-Type's reference list cannot name, so the bitmap
# half is done in PowerShell (Save-ScWindowImage) after a normal Add-Type -AssemblyName.
# The C# here is pure Win32 P/Invoke, which needs no extra references at all.
# Tolerated rather than required, so this file can be dot-sourced somewhere with no GDI+
# at all -- a CI runner running the Pester tests for the browser model and the fixture
# registry, neither of which touches a bitmap. The two functions that DO need it
# (Save-ScWindowImage, Get-ScRegionFingerprint) say so themselves if it is missing,
# instead of the whole harness failing to load with an unrelated message.
$script:ScHaveDrawing = $true
try { Add-Type -AssemblyName System.Drawing -ErrorAction Stop | Out-Null }
catch { $script:ScHaveDrawing = $false }

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
    // Needed by exactly one thing: the menu dropdowns. See Set-ScWindowActive.
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
    A MINIMISED window silently swallows posted mouse messages (task 012 probe 2), so a
    test that posted anyway would report "the click did nothing" and send the reader
    hunting for a bug in the plugin.
    #>
    param([Parameter(Mandatory)][IntPtr]$Hwnd)
    if (-not [ScDrive.Native]::IsWindow($Hwnd)) { throw 'drive-game: window handle is dead (the game exited?).' }
    if ([ScDrive.Native]::IsIconic($Hwnd)) { throw 'drive-game: the game window is MINIMISED; posted mouse messages are ignored in that state. Restore it and retry.' }
}

function Send-ScMouseMove {
    <#
    .SYNOPSIS
    One posted WM_MOUSEMOVE. Needs the window FOREGROUND -- see Assert-ScWindowActive.
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
    [void][ScDrive.Native]::PostMessage($Hwnd, $script:WM_MOUSEMOVE, [IntPtr]$Buttons, (ConvertTo-ScLParam $X $Y))
    if ($DelayMs -gt 0) { Start-Sleep -Milliseconds $DelayMs }
}

function Send-ScClick {
    <#
    .SYNOPSIS
    One click at a client coordinate: move, button-down, button-up.
    .DESCRIPTION
    The leading WM_MOUSEMOVE is not decoration. The game tracks a cursor position of its
    own and draws it; moving first means the down/up pair land where the game already
    believes the pointer is, which is how a real mouse behaves.

    WHICH IS WHY THIS ACTIVATES THE WINDOW (task 023, consolidating task 022's finding).
    The down/up pair carry their own lParam and land whatever the foreground window is --
    but the MOVE ahead of them is dropped while the window is in the background, so the
    game's own tracked cursor stays where the last processed message left it. Any handler
    that reads that tracked position rather than the message's own lParam then acts on the
    WRONG POINT, silently. The minimap centring click is the one that was caught doing it
    (task 022 listed it as one of three symptoms of the same root); rather than guess which
    other handlers do, every primitive that posts a move now goes through
    Assert-ScWindowActive. -NoActivate is for a caller that has already done it.
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
    # A DRAG IS MADE OF MOUSE MOVES, AND THE GAME DROPS POSTED MOVES WHILE ITS WINDOW IS
    # NOT FOREGROUND (task 022 -- see Set-ScWindowActive). The down and the up still land,
    # so the box opens and closes at the same point and the drag selects NOTHING, silently:
    # no error, no warning, just an empty selection. Task 021 lost 25 assertions across two
    # suites to exactly that, in a sweep where three other suites boxed fine -- which is the
    # intermittency this explains. Activation is part of dragging, not an extra;
    # -NoActivate is for a caller that has already done it.
    if (-not $NoActivate) {
        # LOUD, like every other move-dependent primitive. A drag that runs without
        # foreground selects nothing and reports nothing -- which is the failure this
        # activation exists to prevent, and the one that cost another task 25 assertions.
        # Five suites outside task 022 depend on this primitive, so silence here is the
        # worst place for it.
        Assert-ScWindowActive -Hwnd $Hwnd -Because 'a drag, which is made of mouse MOVES and'
    }
    if ($Steps -lt 2) { $Steps = 2 }

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
    # -Ctrl / -Shift bracket the key with posted modifier KEYDOWN/KEYUP, exactly as
    # Send-ScClick does. Whether that is ENOUGH is a property of this binary, not of
    # this function: Windows does not update the thread key-state table for posted
    # keyboard messages, so a game that resolves its modifiers through `GetKeyState`
    # will not see them (the KNOWN LIMIT at the top of this file). Task 021 answered it
    # for the control-group keys in the live game and recorded the result in
    # research/control-groups.md -- read that before assuming either way, and treat a
    # failure as "drive it another way", never as "the modifier is broken".
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
# THE MAP BROWSER, MODELLED FROM THE FILESYSTEM (task 023)
# =============================================================================
#
# THE BUG THIS REPLACES, in three levels -- all three observed, none hypothetical:
#
#   1. `Send-ScClick -X 117 -Y 140` opens "row 1", which was the fixture folder while
#      exactly one `00-*` folder existed. Per-task folders (`00-t021`, `00-t022`) made
#      row 1 whoever sorts first, and everyone else opened somebody else's work.
#   2. The same defect one level down: `022-ghosts.scx` sorts before `combat.scx`, so a
#      hardcoded row-2 map click loaded another worker's map. That run then boxed 36
#      Ghosts where its own fixture places Lurkers and reported internally consistent
#      nonsense (AGENTS.md § "Shared test-fixture folder").
#   3. MERELY CREATING A DIRECTORY shifts rows for a suite that does not use the shared
#      folder at all. `test-selection-circles` reaches `Maps\campaign` by clicking
#      `[Up One Level]` in `Maps\BroodWar` -- an entry that sorts among the folders, so
#      one extra `00-*` directory pushes it down a row. The click then opened a folder,
#      the map never loaded, and the suite timed out looking exactly like menu flake
#      (task 022, 2026-08-09).
#
# Level 3 is why nothing here is per-fixture-folder: EVERY row this harness clicks is
# computed from the filesystem, and what actually opened is verified before proceeding.
#
# THE LISTING MODEL, read off captured frames rather than assumed:
#
#   * `[Up One Level]` is NOT pinned to the top -- it is sorted among the directories by
#     its own displayed name. C:\sc-work\logs\016-frames\05-browse.png reads, in order:
#         [Allied]  [Ladder]  [Up One Level]  [WebMaps]  (2)Astral Balance.scm  ...
#     which is exactly alphabetical over {Allied, Ladder, Up One Level, WebMaps}. That
#     single fact IS level 3.
#   * Directories (including that entry) come first, then map files, each group sorted.
#   * `Maps\` is the browser's ROOT: it has no `[Up One Level]` row.
#   * Six rows are visible at a 640x480 client.
#
# THE LIST IS SCROLLED WHEN IT OPENS, AND THAT IS NOT A DETAIL -- it is the whole reason
# this needed a live probe rather than a directory listing. Measured on 2026-08-09
# (C:\sc-work\logs\023\scroll-frames): with `00-t000` and `00-t023` both present, the
# freshly-opened browser showed
#     [00-t023] [Allied] [Ladder] [Up One Level] [WebMaps] (2)Astral Balance.scm
# -- entry 1 was off the top. Clicking the list's own UP ARROW until the rows stop moving
# then showed
#     [00-t000] [00-t023] [Allied] [Ladder] [Up One Level] [WebMaps]
# which is the filesystem order exactly. So the harness does not model the initial scroll
# offset at all: `Sync-ScBrowserToTop` puts the list in the ONE state the model describes,
# and every row is computed from there.
#
# (An earlier reading of the same evidence had `BroodWar` "not listed" under `Maps\`,
# from a frame that starts at `[campaign]`. It was a scrolled view, not an exclusion.
# Recorded here because a harness that silently skips a directory would put every row
# below it off by one -- exactly the bug this file exists to kill.)
#
# Geometry: the frames above are FULL-WINDOW captures, offset ~(+5,+32) from the client
# coordinates every click uses (Save-ScWindowImage). Row 1's text sits at image y~172,
# i.e. client y=140, and the rows are 19px apart. Those are the numbers below; the +32
# is the trap that made task 021 "fix" a correct coordinate.
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

function Get-ScBrowserRowY {
    param([Parameter(Mandatory)][int]$Row)
    $script:ScBrowserFirstRowY + ($Row - 1) * $script:ScBrowserRowPitch
}

function Sort-ScBrowserNames {
    <#
    .SYNOPSIS
    Sort names the way the browser's list appears to: ordinal, case-insensitive.
    .DESCRIPTION
    NOT PowerShell's `Sort-Object`, which is culture-aware and weights punctuation
    differently -- and these lists are full of punctuation (`(2)Astral Balance.scm`,
    `00-t021`). Every entry ordering visible in the frames cited above is reproduced by
    this comparer, and Assert-ScBrowserMapSelected re-checks the row it lands on live, so a
    disagreement surfaces as a failed run rather than a wrong map.
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
    listing with no `[Up One Level]` entry, and the one where the exclusion above applies.

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

    # Ordinal-ignore-case, not PowerShell's culture-aware Sort-Object: a culture sort
    # weights punctuation differently, and this list is full of it ((2)Astral Balance.scm,
    # 00-t021). The frames above are consistent with ordinal-ignore-case at every entry
    # they show, and Assert-ScBrowserMapSelected re-checks the row this lands on live.
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
    Which of the six visible rows currently have TEXT on them, read off the live window.
    .DESCRIPTION
    Not OCR and not a picture: Get-ScRegionFingerprint returns a hex digest of one
    rectangle. Six digests, in row order.

    They answer exactly one question -- DID THIS ROW CHANGE -- and that is all the callers
    here ask (Sync-ScBrowserToTop: has the list stopped moving yet, i.e.
    is it at the top). They do NOT say whether a row has text on it: the list control is
    transparent, so a blank row shows whatever menu artwork is behind it and two blank rows
    do not match each other.

    The strip is 18px tall (one row pitch less a pixel, so neighbouring rows cannot bleed
    into each other) and stops short of the scrollbar at client x~336.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][IntPtr]$Hwnd)
    1..$script:ScBrowserVisibleRows | ForEach-Object {
        Get-ScRegionFingerprint -Hwnd $Hwnd -X 62 -Y ((Get-ScBrowserRowY -Row $_) - 9) -Width 250 -Height 18
    }
}

function Sync-ScBrowserToTop {
    <#
    .SYNOPSIS
    Scroll the map browser's list to its first entry, and know that it got there.
    .DESCRIPTION
    THE STEP THAT MAKES THE FILESYSTEM MODEL TRUE. A freshly opened browser is already
    scrolled -- measured, not assumed (see the block comment above Get-ScBrowserListing:
    entry 1 was off the top of a listing this harness was about to click row 1 of). Rather
    than model an offset that depends on what the game remembers, this puts the list in
    the one state the model describes.

    It clicks the list's own up arrow in batches and stops when a batch changes nothing,
    which is what "the top" looks like through the only oracle available here -- the row
    fingerprints. Termination is therefore observed, not counted: a listing 95 entries long
    can need far more clicks than any constant a caller would guess, and running out of
    them silently would leave the list somewhere arbitrary. Running out THROWS instead.
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
    for ($batch = 1; $batch -le $MaxBatches; $batch++) {
        for ($i = 0; $i -lt $ClicksPerBatch; $i++) {
            Send-ScClick -Hwnd $Hwnd -X $script:ScBrowserUpArrowX -Y $script:ScBrowserUpArrowY `
                         -HoldMs 40 -SettleMs 40 -NoActivate
        }
        Start-Sleep -Milliseconds 250
        $now = @(Get-ScBrowserRowOccupancy -Hwnd $Hwnd)
        $moved = $false
        for ($r = 0; $r -lt $now.Count; $r++) { if ($now[$r] -ne $prev[$r]) { $moved = $true } }
        if (-not $moved) { return }
        $prev = $now
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
    a picture (see Get-ScRegionFingerprint).

    Rectangle in client coordinates at a 640x480 client, covering the title and the
    size/tileset/slots block.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][IntPtr]$Hwnd)
    Get-ScRegionFingerprint -Hwnd $Hwnd -X 405 -Y 60 -Width 225 -Height 200
}

function Assert-ScBrowserMapSelected {
    <#
    .SYNOPSIS
    Prove the row this run just clicked actually SELECTED A MAP.
    .DESCRIPTION
    THE CHECK THAT SURVIVED CONTACT. Two others did not, and both failures are worth
    keeping here because they are the kind that reads as working:

      * counting rows that "have text on them" -- the list control is TRANSPARENT, so a
        blank row shows menu artwork through it and two blank rows do not match each
        other (C:\sc-work\logs\023\walk-frames\5-top2.png: the fixture folder correctly
        opened, four blank rows, four different fingerprints);
      * clicking the scrollbar's down arrow to measure the list's length -- a SHORT list
        draws no scrollbar, so that click lands in the list body and selects a row, and
        the probe reports movement it caused itself.

    What is left is the browser's own read-back. Selecting a FOLDER row blanks the panel
    -- measured, not assumed: clicking `[00-t000]` while `(2)Astral Balance.scm` was
    selected changed the panel, and every folder row leaves the same blank one. So the
    caller grounds the comparison by selecting a folder row first, and then a click that
    CHANGES the panel selected a map, while a click that leaves it selected a folder or
    nothing at all.

    That catches the failure that actually costs runs -- the walk did not go where it
    thought, so the "map row" is a folder row or empty (the browser still in the parent
    listing, a stale folder shifting every row, a sort order that drifted). It does NOT
    identify WHICH map: two fixture folders each holding one map look alike here. That
    claim belongs to the suite's in-process unit assertion after the map loads, which is
    the only place it can honestly be made.
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
    another worker creating a folder in between moves every row below it, and that gap is
    exactly how task 022 lost a run. A listing that changed between the two reads is a
    throw, not a retry -- the harness has no way to know which of the two the game is
    showing.
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
    Send-ScClick -Hwnd $Hwnd -X $script:ScBrowserRowX -Y $entry.Y
    Send-ScClick -Hwnd $Hwnd -X $script:ScBrowserOkX -Y $script:ScBrowserOkY
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
    repo instead of nine copies of `-X 117 -Y 140`. Every click on the way is computed
    from the filesystem and every directory it opens is verified before the next click
    (Assert-ScBrowserMapSelected).

    Selecting only -- the caller still sets the Game Type and presses Ok, because what
    happens between selecting a map and launching it differs per suite.

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
    # Without it the check would pass on a browser sitting in the wrong folder as long as
    # the row happened to hold some map (see Assert-ScBrowserMapSelected).
    $folderRow = @($listing.Entries |
        Where-Object { $_.Kind -ne 'file' -and $_.Row -le $script:ScBrowserVisibleRows } |
        Select-Object -First 1)
    if ($folderRow.Count -gt 0) {
        Send-ScClick -Hwnd $Hwnd -X $script:ScBrowserRowX -Y $folderRow[0].Y
        Start-Sleep -Milliseconds 300
    }
    $panelBefore = Get-ScBrowserInfoPanel -Hwnd $Hwnd
    Send-ScClick -Hwnd $Hwnd -X $script:ScBrowserRowX -Y $entry.Y
    Start-Sleep -Milliseconds 500
    $panelAfter = Get-ScBrowserInfoPanel -Hwnd $Hwnd
    Assert-ScBrowserMapSelected -Hwnd $Hwnd -Before $panelBefore -After $panelAfter `
                                -Listing $listing -Entry $entry
    $entry
}

# =============================================================================
# FIXTURE OWNERSHIP: PER-SUITE-RUN, DECLARED UP FRONT (task 023)
# =============================================================================
#
# The rule stays what AGENTS.md § "Shared test-fixture folder" says -- refuse to start on
# any fixture this run did not create, delete only your own, never the folder. What
# changes is WHAT "mine" MEANS.
#
# It used to mean one filename, tested at startup. `test-combat-death.ps1` creates two
# fixtures in sequence (a placement probe, then the combat map), so on the second the rule
# counted the suite's OWN phase-A probe as foreign and the suite waited for itself. A
# self-deadlock manufactured by the safety rule, not by a collision (task 022,
# 2026-08-09).
#
# So ownership is now a RUN, not a file: a suite declares every fixture name it will ever
# create before it creates any of them, and the checks below test against that whole set.
# That fixes the deadlock without softening anything -- the set is fixed at declaration
# time and every file outside it is still foreign, so this is not "ignore anything that
# looks a bit like mine". A name has to have been declared, and declaring it is the same
# act as promising to delete it.
# =============================================================================

function Resolve-ScFixtureDir {
    <#
    .SYNOPSIS
    Where this run's fixtures go: the caller's `-FixtureDir` if given, otherwise this
    AGENT'S OWN folder, otherwise the suite's historical by-hand default.

    .DESCRIPTION
    THE HOLE THIS CLOSES (task 023 review, 2026-08-09). Ownership is keyed on the declared
    NAME set, which decides "mine" against ANOTHER suite perfectly -- and not at all
    against ANOTHER RUN OF THE SAME SUITE. Two concurrent runs of `test-combat-death` with
    no `-FixtureDir` land in the same folder and declare the same names, so each one's file
    is "mine" to the other, the foreign check never fires, and one deletes-then-rewrites the
    other's fixture underneath it. Bounded (it needs two same-suite runs both omitting the
    parameter) and forbidden by AGENTS.md already -- but this task's whole point was moving
    contention guards out of documentation and into code, and a neutral default that allows
    self-collision is the one place that was left to the convention.

    Four suites had the mirror-image bug: their defaults were nailed to `00-t021`/`00-t022`,
    the folders of the tasks that WROTE them, so any later worker running them by default
    wrote into a finished task's folder.

    A worker always has `$env:AGENT_TASK`, so the fix needs no new discipline: with it set,
    the default is that agent's own folder and two agents can never collide. Without it --
    a human at a prompt, one run at a time -- the suite's historical default is preserved
    exactly, which is what `-FixtureDir` defaulting "to current behaviour" promised.

    The task id is taken as leading digits, so `023` and `023-ghost-cloak` both give
    `00-t023` (Enter-ScLaunchLock's -TaskId convention appends a suffix to the same id).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$GameDir,
        # What this suite used before agents existed. Kept for by-hand runs.
        [Parameter(Mandatory)][string]$Fallback,
        # Injectable so Pester can exercise every branch without touching the environment.
        [AllowNull()][AllowEmptyString()][string]$AgentTask = $env:AGENT_TASK
    )
    $leaf = $Fallback
    if (-not [string]::IsNullOrWhiteSpace($AgentTask)) {
        $leaf = if ($AgentTask -match '^\s*(\d{1,4})') { "00-t$($Matches[1])" }
                else { '00-t' + ($AgentTask -replace '[^A-Za-z0-9]', '') }
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
    enough: the folder can be added to in between, and the browser row would move under
    the click. Task 022 lost a run to exactly that gap.

    Never deletes the other file -- it may belong to a game that is running right now.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][psobject]$Run)
    $foreign = @(Get-ScForeignFixture -Run $Run)
    if ($foreign.Count -gt 0) {
        throw ("drive-game: $($Run.Dir) holds $($foreign -join ', '), which this run did not " +
               "create (it declared: $($Run.Names -join ', ')). The map browser opens a ROW, so a " +
               'foreign file moves which map loads -- and playing somebody else''s map produces ' +
               'internally consistent nonsense. Refusing to start, and not deleting theirs: a ' +
               'running game may have it open.')
    }
}

function Assert-ScFixtureStillMine {
    <#
    .SYNOPSIS
    The late check: this run's own fixture is still there, and nobody else's is.
    .DESCRIPTION
    Run immediately before the browser walk. Two different failures, named separately,
    because they need different reactions: a MISSING own fixture means another worker's
    cleanup took it (regenerate, do not interpret the run), a foreign one means a
    collision (wait for them).
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
        throw "drive-game: $mine is gone from $($Run.Dir) between generation and launch -- another worker's cleanup took it. Regenerate; do not interpret this run."
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
    A suite with its own fixture folder must take it away again: every suite in this
    directory reaches its map with a first-row folder click, so an empty folder left
    behind changes which folder that click lands on for everyone else. Refusing to delete
    a non-empty one is the same rule as everywhere else here -- never remove a file this
    run did not create.
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
    Replaces Wait-ScTestMapDirFree, whose ownership test was ONE filename -- which made a
    multi-fixture suite wait for itself (see the block comment above New-ScFixtureRun).

    Two waits, for two different reasons:
      * for somebody ELSE's fixture to go: never deleted, because a running game may have
        it open, and killing another worker's run is the 2026-07 incident class in a
        different costume;
      * for OUR OWN previous file to become deletable: a stale one can still be held open
        by a game that is shutting down.

    -Names narrows the deletion to the fixtures the caller is about to (re)write, so an
    earlier phase's file survives into a later phase. Omitted, it clears all of them.

    Throws, with the cause named, if either wait runs out.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Run,
        [string[]]$Names,
        [int]$TimeoutMinutes = 20
    )
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    while ($true) {
        New-Item -ItemType Directory -Path $Run.Dir -Force | Out-Null
        $foreign = @(Get-ScForeignFixture -Run $Run)
        if ($foreign.Count -eq 0) { break }
        if ((Get-Date) -ge $deadline) {
            throw ("drive-game: $($Run.Dir) still holds another worker's fixture ($($foreign -join ', ')) " +
                   "after $TimeoutMinutes minute(s). Two runs cannot share that folder: the map is chosen " +
                   'by clicking a row, so a second file silently changes which map loads. Not deleting ' +
                   'it -- it may belong to a running game.')
        }
        Write-Host "       waiting for $($Run.Dir) to be free (another run's fixture is in it: $($foreign -join ', '))"
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
    Task 022 used it to settle which units the twelve actually contained, after a claim in
    that task's own writeup about where a pre-damaged block landed turned out to be false
    when the pointers were cross-referenced.

    Returns the pointers as upper-case hex strings without the 0x, matching the format
    Get-ScWorldState reports for each unit, so the two can be intersected directly.

    RETURNED UNROLLED, deliberately. This used to end in `,@(...)`, the idiom that stops a
    one-element result collapsing to a scalar -- but its one caller wraps the call in
    `@(...)`, and the two together produce an array holding ONE element which is itself the
    array of twelve. `$engine.Count` then reads 1, `-contains` matches nothing, and
    test-stim-fanout failed two assertions about the ENGINE'S TWELVE while the log in front
    of it held all twelve pointers. A harness bug wearing the costume of a finding, which
    is the class this whole task is about. PowerShell 7 gives scalars a .Count of 1, so the
    idiom buys nothing here anyway.
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
    something a script can do reliably. But comparing the SAME rectangle before and after
    an action is different: it answers "did this region change at all", which is a real
    yes/no. Set-ScGameType uses it, and nothing about it reproduces game artwork: the
    return value is a hex digest.
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

function Set-ScGameType {
    <#
    .SYNOPSIS
    Set the Create Game screen's Game Type, and PROVE it changed.
    .DESCRIPTION
    The Game Type combo is the single most consequential control in this whole harness --
    get it wrong and the fixture loads as a melee game, the map's placed units are never
    created, and the failure surfaces minutes later as "the wrong units are on the map".
    It is also the least reliable one: it remembers what this machine last used (so a
    no-op pick can look like a success for months), and the pick needs the window
    foreground (Set-ScWindowActive), which another process can take away mid-drag.

    So this does not pick and hope. It picks a KNOWN OTHER entry first, fingerprints the
    map-information panel, then picks the wanted entry and requires the panel to have
    CHANGED. That panel reads "Number of Players: N" for the melee-style types and
    "Human Slots / Computer Slots" under Use Map Settings, so a real change of type is a
    real change of pixels -- and a pick that silently did nothing leaves the two
    fingerprints identical, which is a failure here instead of a mystery later.

    The list's contents and order were read off a held-open frame (task 016, re-checked
    by task 022): for the two-player maps this harness generates it is exactly
    {Melee, Free For All, Use Map Settings}, drawn below the box at +16, +31, +46 client
    pixels whatever the current value is.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][IntPtr]$Hwnd,
        [int]$Index = 2,          # Use Map Settings
        [int]$OtherIndex = 0,     # Melee -- any entry that is not $Index
        [int]$X = 265, [int]$Y = 268,
        [int]$Tries = 3
    )
    # The map-information panel, client coordinates at 640x480. Wide enough to cover both
    # the "Number of Players" line and the two-line Human/Computer Slots that replaces it.
    $panel = @{ X = 400; Y = 270; Width = 210; Height = 40 }
    for ($try = 1; $try -le $Tries; $try++) {
        Send-ScDropdownPick -Hwnd $Hwnd -X $X -Y $Y -Index $OtherIndex
        $before = Get-ScRegionFingerprint -Hwnd $Hwnd @panel
        Send-ScDropdownPick -Hwnd $Hwnd -X $X -Y $Y -Index $Index
        $after = Get-ScRegionFingerprint -Hwnd $Hwnd @panel
        if ($before -ne $after) {
            Write-Host "       game type set (panel $before -> $after, attempt $try)"
            return
        }
        Write-Host "       game type pick did not take (panel unchanged: $before), retrying"
        Start-Sleep -Milliseconds 600
    }
    throw "drive-game: could not set the Game Type after $Tries attempt(s) -- the map-information panel never changed, so the pick is not taking. A fixture loaded under the wrong game type produces the wrong units, so this refuses to continue."
}

function Wait-ScNoGameRunning {
    <#
    .SYNOPSIS
    Wait until no StarCraft process is running on this machine.
    .DESCRIPTION
    THE GAME IS SINGLE-INSTANCE, MACHINE-WIDE. Launching a second one -- even from a
    different working copy, with a different injector -- gets an immediate exit, which
    `scinject.exe` reports as exit 3 ("the game exited on its own before injection") and
    `run-with-plugin.ps1` turns into a thrown launch failure. Task 022 hit this repeatedly
    while another worker's suite was mid-run, and copying the install to a private
    directory did NOT help, which is what established that the constraint is per machine
    and not per directory.

    The launch lock (sc-launch-lock.ps1) does not cover this on its own: it is held
    around the LAUNCH, not for as long as the game is alive, so a worker can be holding a
    running game with the lock free. So a caller that wants a game waits for the machine
    to be free FIRST and then takes the lock for as long as its own game lives.

    Waiting, never killing: another worker's game is another worker's run, and ending it
    is the 2026-07 incident class in a different costume.
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
    Make the game window the foreground window. Needed by EVERY primitive that posts a
    mouse move -- click, drag, dropdown pick.
    .DESCRIPTION
    THE GAME IGNORES A POSTED WM_MOUSEMOVE WHEN ITS WINDOW IS NOT ACTIVE. Posted clicks
    are processed either way, which is why every other function in this file works with
    the window in the background and why this was invisible until task 022 went looking
    for it.

    Measured, on the Create Game screen (work/scratch/022/probe-gametype*.ps1, frames
    under C:\sc-work\logs\022-probe*-frames):

      * posting WM_MOUSEMOVE to (500,200) with the window inactive leaves the game's own
        drawn cursor exactly where the last posted CLICK left it -- the motion is not
        merely unhighlighted, it is not processed at all;
      * so a dropdown opened by a posted button-down highlights whatever row the cursor
        was on when it opened, never moves, and the button-up commits the value that was
        already selected. The pick silently does nothing;
      * the same posted sequence, with the window made foreground first, sets the value.

    That silent no-op is the dangerous part: the Game Type combo remembers the last value
    this machine used, so a suite whose pick did nothing still passed for as long as that
    remembered value happened to be the one it wanted. Task 022 found it the other way
    round -- the remembered value was "Free For All", every generated fixture loaded as a
    melee game, and the placed units were never created.

    SetForegroundWindow alone is refused for a background process (it returns TRUE and
    flashes the taskbar instead), so this goes through the documented AttachThreadInput
    dance and then VERIFIES the result rather than trusting the return value.

    This is the one place in this file that reaches outside the target window's message
    queue. It steals focus, which is visible to anyone at the machine. Task 023 widened
    the callers from "the dropdowns" to "everything that posts a move", which is every
    click -- so the ALREADY-FOREGROUND case is now the common one and must be free: it
    returns without the settle, because nothing changed and there is nothing to settle.
    Paying 400ms on every click of a menu walk would add minutes to every suite.
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
    Set-ScWindowActive, but it THROWS instead of returning false.
    .DESCRIPTION
    THE one gate every move-dependent primitive goes through, so that "the window was not
    foreground" can never be a silent no-op anywhere in this harness.

    Task 022 measured the mechanism (Set-ScWindowActive) and fixed the two primitives that
    were bleeding at the time. Task 023 consolidated it, because the three symptoms it was
    attributed to -- the Game Type pick committing the wrong value, the minimap centring
    click missing, and Send-ScDrag selecting nothing -- share one property: each is a
    handler that reads the game's OWN tracked cursor position, which a dropped move leaves
    stale. Any primitive posting a move can hit it, so none of them opts out by default.

    -Because is glued into the message so the failure names the operation that refused,
    not just the fact that a window is not in front.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][IntPtr]$Hwnd,
        [string]$Because = 'this input',
        [int]$Tries = 3
    )
    if (Set-ScWindowActive -Hwnd $Hwnd -Tries $Tries) { return }
    throw ("drive-game: could not bring the game window to the foreground, and $Because " +
           'is IGNORED while the window is in the background (see Set-ScWindowActive) -- ' +
           'it would do nothing and report nothing. Refusing to post it. Close whatever ' +
           'is holding the foreground (a modal dialog, an installer, a lock screen) and re-run.')
}

function Send-ScCommand {
    <#
    .SYNOPSIS
    Fire one of the game's own ACCELERATOR commands by posting WM_COMMAND -- the only way
    to drive a MODIFIED key (Ctrl+1, Shift+1) from a script.
    .DESCRIPTION
    Task 021, evidence in research/control-groups.md. StarCraft does not read Ctrl or
    Shift in its window procedure. Its message pump (0x004D1BF0) calls
    `TranslateAcceleratorA` FIRST and only dispatches the message normally when that
    returns 0, and the merged accelerator table comes from the binaries' own resources
    (`Local.dll` id 0x65 holds Ctrl+0..9 and Alt+0..9; `StarCraft.exe` id 0x71 holds
    Shift+0..9). `TranslateAcceleratorA` resolves FCONTROL/FSHIFT against the calling
    THREAD's key-state table, which Windows never updates for POSTED messages -- so a
    posted Ctrl+1 cannot match, and one was measured producing no command at all.

    What the accelerator does on a match is send `WM_COMMAND` carrying its command id,
    and the window proc's `case 0x111` puts that id straight into the game's own key
    dispatcher (`0x004846E0` via `[0x005968E0]`), which reads NOTHING from the event but
    that id. So posting the WM_COMMAND is not a simulation of the keypress: it is the
    same call, with only `TranslateAcceleratorA`'s modifier check skipped. The engine
    posts exactly such a message to itself at 0x004D1BA0, which is the precedent.

    PLAIN digits are NOT accelerators -- they reach the dispatcher through the window
    proc -- so a plain control-group RECALL is driven with `Send-ScKey` as normal, and
    only the assign/add halves need this.

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

function Send-ScDropdownPick {
    <#
    .SYNOPSIS
    Pick the Nth entry of one of the game's menu dropdowns (Game Type, race, ...).
    .DESCRIPTION
    These are press-and-hold controls, not click-to-open ones: the entry under the
    cursor at button-UP is the one selected, and the list is on screen only while the
    button is held.

    How that was established (task 016, Game Type combo on the Create Game screen):
    a plain Send-ScClick on the box left the frame captured a second later showing the
    box closed with its label unchanged, and the game behaved the same as with no click
    at all -- so a click is not a way to choose, and the label alone says nothing about
    what is set. Posting WM_LBUTTONDOWN *without* the matching UP and capturing the frame
    then shows the list open; the offsets below were read off that frame, at a 640x480
    client: first entry 16px below the closed box's own centre line, 15px apart after
    that. -Index 0 is that first entry.

    IT ALSO NEEDS THE WINDOW TO BE ACTIVE (task 022): the mouse MOVE that walks down the
    open list is dropped when the window is in the background, so the pick becomes a
    silent no-op that leaves the previous value in place. Set-ScWindowActive explains the
    measurement. Activation happens here rather than at every call site, so that every
    existing caller is fixed by having this function do it; -NoActivate opts out.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][IntPtr]$Hwnd,
        [Parameter(Mandatory)][int]$X, [Parameter(Mandatory)][int]$Y,
        [Parameter(Mandatory)][int]$Index,
        [int]$FirstOffset = 16, [int]$Pitch = 15, [int]$SettleMs = 400,
        [switch]$NoActivate,
        # How long to wait for the list to APPEAR after the button goes down, and how long
        # to sit on the chosen entry before releasing.
        #
        # These were hardcoded at 200ms each, and 200 is not enough. Task 021 had a Game
        # Type pick silently do nothing: the lobby stayed on Melee and the map played as a
        # melee game -- 4 Drones instead of the fixture's 36 Lurkers, and eight downstream
        # assertions failing about something else entirely. Holding the combo open and
        # photographing it (work/scratch/probe-gametype.ps1) ruled out the two obvious
        # suspects: on that fixture the list is exactly three entries, the entry centres
        # land on the 16px/15px offsets below, and index 2 really is "Use Map Settings".
        # What was left was the timing, and raising these made it reproducible-green.
        #
        # THIS FAILURE IS SILENT AND STICKY, which is why the defaults moved rather than
        # one caller: the combo remembers the last choice in the machine's profile, so a
        # pick that does nothing leaves the WRONG game type set for every later run too.
        # Every suite that picks a game type was exposed to it, not just this task's.
        [int]$OpenMs = 700, [int]$HoverMs = 400
    )
    Assert-ScDrivable -Hwnd $Hwnd
    if (-not $NoActivate) {
        # Loud, not silent: a pick made in the background is the failure mode this
        # whole comment block exists about, and it would otherwise be discovered as
        # a wrong unit type several minutes later.
        Assert-ScWindowActive -Hwnd $Hwnd -Because 'a dropdown pick, whose walk down the open list is a mouse MOVE and'
    }
    $itemY = $Y + $FirstOffset + $Index * $Pitch
    $atBox  = ConvertTo-ScLParam $X $Y
    $atItem = ConvertTo-ScLParam $X $itemY
    [void][ScDrive.Native]::PostMessage($Hwnd, $script:WM_MOUSEMOVE, [IntPtr]0, $atBox)
    Start-Sleep -Milliseconds 60
    [void][ScDrive.Native]::PostMessage($Hwnd, $script:WM_LBUTTONDOWN, [IntPtr]$script:MK_LBUTTON, $atBox)
    Start-Sleep -Milliseconds $OpenMs
    [void][ScDrive.Native]::PostMessage($Hwnd, $script:WM_MOUSEMOVE, [IntPtr]$script:MK_LBUTTON, $atItem)
    Start-Sleep -Milliseconds $HoverMs
    [void][ScDrive.Native]::PostMessage($Hwnd, $script:WM_LBUTTONUP, [IntPtr]0, $atItem)
    if ($SettleMs -gt 0) { Start-Sleep -Milliseconds $SettleMs }
}

function Get-ScMinimapPoint {
    <#
    .SYNOPSIS
    The client pixel to click on the minimap to centre the view on a map TILE.
    .DESCRIPTION
    The view is otherwise unmovable from a script: the camera opens centred on the
    player's start location and never moves on its own, edge-scrolling needs the
    pointer parked at the very edge (which posted WM_MOUSEMOVE does not sustain --
    task 019 tried it, the view did not move and the game exited during the attempt),
    and the keyboard scroll keys are modifier-adjacent. A LEFT click on the minimap
    does move the camera, and it is one posted click.

    Geometry, at a 640x480 client: the minimap box is 128x128 client pixels with its
    top-left at (7, 348) -- the console art's minimap panel, whose right edge is where
    the 12-button wireframe row's root dialog begins (`HUDROW rects root=[138,...]`,
    research/hud-selection-row.md). A map of W x H tiles with both <= 128 is drawn at
    one pixel per tile and CENTRED in that box.

    Calibrated in game (task 019) on the generated 128x96-tile fixture, whose enemy
    block sits at tile (41,19): this formula gives client (48, 383), and clicking
    there then drag-boxing the screen selected exactly the six placed Hydralisks and
    nothing else (`UNITSTATE n=6 types=[0x26:6]`). Clicking four pixels higher put
    only three of them on screen, so the vertical centring term is real and not a
    rounding accident. Nine origin candidates were scanned; (7, 348) with the
    (128-H)/2 offset is the one that reproduces the result for every x tried.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$MapTilesW,
        [Parameter(Mandatory)][int]$MapTilesH,
        [Parameter(Mandatory)][int]$TileX,
        [Parameter(Mandatory)][int]$TileY,
        [int]$BoxLeft = 7, [int]$BoxTop = 348, [int]$BoxSize = 128
    )
    if ($MapTilesW -gt $BoxSize -or $MapTilesH -gt $BoxSize) {
        throw "drive-game: Get-ScMinimapPoint is calibrated for maps up to ${BoxSize}x${BoxSize} tiles; got ${MapTilesW}x${MapTilesH}. A bigger map is drawn at a smaller scale and this 1px-per-tile mapping does not hold."
    }
    if ($TileX -lt 0 -or $TileY -lt 0 -or $TileX -ge $MapTilesW -or $TileY -ge $MapTilesH) {
        throw "drive-game: tile ($TileX,$TileY) is outside a ${MapTilesW}x${MapTilesH} map."
    }
    [pscustomobject]@{
        X = $BoxLeft + [int](($BoxSize - $MapTilesW) / 2) + $TileX
        Y = $BoxTop  + [int](($BoxSize - $MapTilesH) / 2) + $TileY
    }
}

$script:ScMarkerSeq = 0

function Get-ScUnitState {
    <#
    .SYNOPSIS
    Ask the plugin for a UNITSTATE line and parse it. THE test oracle.
    .DESCRIPTION
    Writes a unique label into the plugin's marker file and waits for the UNITSTATE
    line carrying that exact label. The plugin dumps the line when it notices the
    marker change (scplugin.cpp PollMarker), so this is a SYNCHRONOUS read of every
    unit's own state from inside the process -- not a race against the 250ms poll,
    and not a claim about the picture.

    The line covers the whole shadow list, i.e. the entire pre-cap selection, not the
    twelve the engine holds.
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
    Set-Content -LiteralPath $MarkerPath -Value $label -NoNewline
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $line = Get-Content -LiteralPath $LogPath -ErrorAction SilentlyContinue |
                Select-String -Pattern ([regex]::Escape("UNITSTATE [$label]")) |
                Select-Object -Last 1
        if ($line) {
            $m = [regex]::Match($line.Line,
                'UNITSTATE \[[^\]]*\] n=(\d+) live=(\d+) visible=(\d+) overflow=(\d+) orders=\[([^\]]*)\] orders2=\[([^\]]*)\] types=\[([^\]]*)\] burrowed=(\d+)/(\d+)')
            if (-not $m.Success) { break }
            # Task 020 appended the liveness breakdown to the same line. Parsed
            # separately and optionally, so this reader still works against a log
            # written by an older plugin build (the fields are absent, not wrong).
            $lv = [regex]::Match($line.Line,
                'uniqOnly=(\d+) recycled=(\d+) hp0=(\d+) foreign=(\d+) nosprite=(\d+) removed=(\d+) staleSkipped=(\d+) liveness=(\d+)')
            # Task 022 appended the per-unit COST/EFFECT histograms. Same rule as the
            # task-020 block above: parsed separately and optionally, so a reader written
            # against an older plugin build still works and a missing field reads as
            # "this build did not report it", never as zero.
            $ce = [regex]::Match($line.Line,
                'stimmed=(\d+)/(\d+) hp=\[([^\]]*)\] stim=\[([^\]]*)\] energy=\[([^\]]*)\]')
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
    all. That is what makes a plugin-vs-stock comparison possible with the SAME oracle
    on both sides.

    Needs the plugin launched with -WorldScan 1; without it the plugin logs no WORLD
    lines and this throws on the timeout.

    Returns one object with .Units (one entry per unit, with Player/Type/Hp/Order/
    Order2/Stim/Energy/X/Y/Flags) and .Counts (per player: Units, Recount, Complete).
    A Recount that disagrees with Units means the sample was taken while the game
    thread was editing the list -- the caller should discard it, not believe it.
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
    Set-Content -LiteralPath $MarkerPath -Value $label -NoNewline
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
                $s = [regex]::Match($l.Line, 'p=(\d+) units=(\d+) recount=(\d+) complete=(\d+)')
                if ($s.Success) {
                    $counts[[int]$s.Groups[1].Value] = [pscustomobject]@{
                        Units    = [int]$s.Groups[2].Value
                        Recount  = [int]$s.Groups[3].Value
                        Complete = [int]$s.Groups[4].Value
                    }
                }
            }
            return [pscustomobject]@{ Label = $label; Units = $units; Counts = $counts }
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
    Task 026. Tasks 022 and 023 tried to reach the Ghost's Cloak by posting input at
    the card -- every key A-Z and all nine slots -- and got a bounded negative: input
    reaches the card, the ability is on the card, and neither path issues it. That
    experiment could not distinguish "the button is greyed" from "the click missed",
    because both produce an empty log.

    This does not click. The plugin walks the card dialog (0x0068C148) and reports,
    per slot, the control's own visible/disabled flags plus the Button record behind
    it -- ability condition, action, params and strings (research/command-card.md).
    Both of the engine's input paths refuse a control with the disabled bit set
    (the mouse at 0x00459947, the hotkey predicate at 0x004588C0), so that one bit
    is the whole answer, and it is a READ.

    Same marker handshake as Get-ScWorldState, and like it this installs no hook and
    therefore works in `-Mode observe` too. Needs the plugin launched with
    -CardScan 1; without it no CARD lines are written and this throws on the timeout.

    Returns .Slots (one entry per card control, Index/Visible/Disabled/State/Icon/
    Button/BSlot/BIcon/Cond/Action/CondParam/ActParam/NameStr/DisStr), plus the header
    fields (CardId, PortraitType, PortraitSet, PortraitEnergy, SetCount, Reason) and
    .Shown / .Greyed. `Get-ScCardSlot $card 7` picks one slot out.
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
    Set-Content -LiteralPath $MarkerPath -Value $label -NoNewline
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
    Never a hardcoded coordinate. A control's rect (+0x04) is relative to its
    dialog's own origin -- the engine adds them itself at 0x00458850
    (`dlg->rct.left + child->rct.left`) -- so the point is rootRect + rect, halved.

    This is the card's answer to the "never click a browser row by number" rule:
    a probe that clicks a guessed slot centre cannot tell "the button refused the
    click" from "the click landed between buttons", and task 022 lost the whole
    Ghost question to exactly that ambiguity. Returns @{X;Y}.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Card, [Parameter(Mandatory)][int]$Slot)
    $s = Get-ScCardSlot -Card $Card -Slot $Slot
    if (-not $s) { throw "drive-game: the card read-back has no slot $Slot." }
    @{ X = [int]($Card.RootRect[0] + [math]::Floor(($s.Rect[0] + $s.Rect[2]) / 2))
       Y = [int]($Card.RootRect[1] + [math]::Floor(($s.Rect[1] + $s.Rect[3]) / 2)) }
}

function Save-ScWindowImage {
    <#
    .SYNOPSIS
    PNG of the game's CLIENT area, via PrintWindow.
    .DESCRIPTION
    A DIAGNOSTIC, never an oracle (research/automated-testing-options.md O4). The output
    reproduces game artwork, so it must stay on a gitignored path and must never be
    committed (AGENTS.md hard rule 1) -- this function refuses to write inside the repo.

    READ THIS BEFORE MEASURING A COORDINATE OFF ONE OF THESE FRAMES.

    With -FullWindow the capture is the WINDOW, including the border and title bar, while
    every function in this file clicks in CLIENT coordinates. At this game's window size
    the two differ by roughly (+5, +32): a control drawn at y=300 in the image is at
    y~268 in the coordinates you must post.

    That is not a footnote. Task 021 measured the lobby's Game Type combo off exactly such
    a frame, concluded every suite had been clicking 32 px too high for months, and
    "fixed" a coordinate that was already correct -- which made the failure worse, not
    better. The real cause was timing (see Send-ScDropdownPick). Subtract the offset, or
    capture without -FullWindow, before concluding a coordinate is wrong.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][IntPtr]$Hwnd,
        [Parameter(Mandatory)][string]$Path,
        # Capture the WHOLE window rather than PW_CLIENTONLY. The windowed-mode helper
        # leaves its caption inside the reported client rectangle, so a client-only
        # grab is shifted down by the caption height and loses that many rows off the
        # bottom -- which is exactly where the HUD is.
        [switch]$FullWindow
    )
    Assert-ScDrivable -Hwnd $Hwnd
    Assert-ScDrawing
    $full = [IO.Path]::GetFullPath($Path)
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    if ($full.StartsWith($repoRoot, [StringComparison]::OrdinalIgnoreCase) -and
        $full -notmatch '\\work\\scratch\\') {
        throw "drive-game: refusing to write a game frame to '$full' -- screenshots reproduce game artwork and must not land in the repo (AGENTS.md hard rule 1). Use a path outside the repo, or work/scratch/."
    }
    New-Item -ItemType Directory -Path (Split-Path $full -Parent) -Force | Out-Null

    $sz = if ($FullWindow) { Get-ScWindowSize -Hwnd $Hwnd } else { Get-ScClientSize -Hwnd $Hwnd }
    $flags = if ($FullWindow) { 0 } else { 2 }
    if ($sz.Width -le 0 -or $sz.Height -le 0) { throw 'drive-game: the window has no client area.' }

    # PW_CLIENTONLY == 2. Task 012 called PrintWindow twice against the live game and
    # the game survived both -- it is a read of one window, never a screen grab.
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
        $bmp.Save($full, [System.Drawing.Imaging.ImageFormat]::Png)
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
