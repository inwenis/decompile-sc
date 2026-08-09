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
        [int]$HoldMs = 50, [int]$SettleMs = 200
    )
    Assert-ScDrivable -Hwnd $Hwnd
    [void][ScDrive.Native]::PostMessage($Hwnd, $script:WM_KEYDOWN, [IntPtr]$VirtualKey, [IntPtr]1)
    if ($Char -ne [char]0) {
        [void][ScDrive.Native]::PostMessage($Hwnd, $script:WM_CHAR, [IntPtr][int]$Char, [IntPtr]1)
    }
    Start-Sleep -Milliseconds $HoldMs
    [void][ScDrive.Native]::PostMessage($Hwnd, $script:WM_KEYUP, [IntPtr]$VirtualKey, [IntPtr]0xC0000001)
    if ($SettleMs -gt 0) { Start-Sleep -Milliseconds $SettleMs }
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

function Wait-ScTestMapDirFree {
    <#
    .SYNOPSIS
    Wait until the shared generated-fixture folder holds nothing but this test's own map,
    then make sure only this test's own map is in it.
    .DESCRIPTION
    Every unattended suite in this directory generates its fixture into the SAME folder
    (Maps\BroodWar\00-testmap, whose name is what makes the two menu clicks that reach it
    deterministic) and finds it by clicking the row after [Up One Level]. That is fine for
    one worker and wrong for two: task 022 hit a live collision -- another worker's
    combat.scx was sitting in that folder, still open by its running game, while this
    suite was about to `Remove-Item -Recurse` the folder out from under it.

    So: never delete the folder, only this test's own file, and refuse to start while
    somebody else's fixture is in there rather than racing them for the second row of the
    map list. The wait is the polite half; the assertion is the half that stops a
    mis-clicked row from being diagnosed later as a mysterious wrong-unit-type failure.

    Returns nothing; throws if the folder is still shared when the timeout runs out.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Dir,
        [Parameter(Mandatory)][string]$MyMapPath,
        [int]$TimeoutMinutes = 20
    )
    $mine = Split-Path $MyMapPath -Leaf
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    while ($true) {
        New-Item -ItemType Directory -Path $Dir -Force | Out-Null
        $foreign = @(Get-ChildItem -LiteralPath $Dir -File -ErrorAction SilentlyContinue |
                     Where-Object { $_.Name -ne $mine })
        if ($foreign.Count -eq 0) { break }
        if ((Get-Date) -ge $deadline) {
            throw ("drive-game: $Dir still holds another worker's fixture ({0}) after $TimeoutMinutes minute(s). " +
                   'Two suites cannot share that folder: the map is chosen by clicking a row, so a second file ' +
                   'silently changes which map loads. Not deleting it -- it may belong to a running game.') -f `
                   (($foreign | ForEach-Object { $_.Name }) -join ', ')
        }
        Write-Host ("       waiting for {0} to be free (another worker's fixture is in it: {1})" -f `
            $Dir, (($foreign | ForEach-Object { $_.Name }) -join ', '))
        Start-Sleep -Seconds 20
    }
    # Only ever this test's own file.
    if (Test-Path -LiteralPath $MyMapPath) { Remove-Item -LiteralPath $MyMapPath -Force }
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
    Make the game window the foreground window. Needed by the menu dropdowns and by
    nothing else.
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
    queue. It steals focus, which is visible to anyone at the machine -- so it is called
    only where it is needed, not on every action.
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
    for ($i = 0; $i -lt $Tries; $i++) {
        if ([ScDrive.Native]::MakeForeground($Hwnd)) {
            if ($SettleMs -gt 0) { Start-Sleep -Milliseconds $SettleMs }
            return $true
        }
        Start-Sleep -Milliseconds 300
    }
    return $false
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
        [switch]$NoActivate
    )
    Assert-ScDrivable -Hwnd $Hwnd
    if (-not $NoActivate) {
        if (-not (Set-ScWindowActive -Hwnd $Hwnd)) {
            # Loud, not silent: a pick made in the background is the failure mode this
            # whole comment block exists about, and it would otherwise be discovered as
            # a wrong unit type several minutes later.
            throw "drive-game: could not bring the game window to the foreground, and a dropdown pick made while it is in the background does nothing (see Set-ScWindowActive). Refusing to pick."
        }
    }
    $itemY = $Y + $FirstOffset + $Index * $Pitch
    $atBox  = ConvertTo-ScLParam $X $Y
    $atItem = ConvertTo-ScLParam $X $itemY
    [void][ScDrive.Native]::PostMessage($Hwnd, $script:WM_MOUSEMOVE, [IntPtr]0, $atBox)
    Start-Sleep -Milliseconds 60
    [void][ScDrive.Native]::PostMessage($Hwnd, $script:WM_LBUTTONDOWN, [IntPtr]$script:MK_LBUTTON, $atBox)
    Start-Sleep -Milliseconds 200
    [void][ScDrive.Native]::PostMessage($Hwnd, $script:WM_MOUSEMOVE, [IntPtr]$script:MK_LBUTTON, $atItem)
    Start-Sleep -Milliseconds 200
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

function Save-ScWindowImage {
    <#
    .SYNOPSIS
    PNG of the game's CLIENT area, via PrintWindow.
    .DESCRIPTION
    A DIAGNOSTIC, never an oracle (research/automated-testing-options.md O4). The output
    reproduces game artwork, so it must stay on a gitignored path and must never be
    committed (AGENTS.md hard rule 1) -- this function refuses to write inside the repo.
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
