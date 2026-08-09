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
Add-Type -AssemblyName System.Drawing | Out-Null

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
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][IntPtr]$Hwnd,
        [Parameter(Mandatory)][int]$X, [Parameter(Mandatory)][int]$Y,
        [int]$Buttons = 0, [int]$DelayMs = 30
    )
    Assert-ScDrivable -Hwnd $Hwnd
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
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][IntPtr]$Hwnd,
        [Parameter(Mandatory)][int]$X, [Parameter(Mandatory)][int]$Y,
        [switch]$Right, [switch]$Shift, [switch]$Ctrl,
        [int]$HoldMs = 60, [int]$SettleMs = 250
    )
    Assert-ScDrivable -Hwnd $Hwnd

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
        [int]$Steps = 12, [int]$StepMs = 40, [int]$SettleMs = 400
    )
    Assert-ScDrivable -Hwnd $Hwnd
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
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][IntPtr]$Hwnd,
        [Parameter(Mandatory)][int]$X, [Parameter(Mandatory)][int]$Y,
        [Parameter(Mandatory)][int]$Index,
        [int]$FirstOffset = 16, [int]$Pitch = 15, [int]$SettleMs = 400,
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
                Line = $line.Line.Trim()
            }
        }
        Start-Sleep -Milliseconds 250
    }
    throw "drive-game: no UNITSTATE line for marker '$label' within ${TimeoutSec}s (log: $LogPath)."
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
