#Requires -Version 7
<#
.SYNOPSIS
End-to-end, UNATTENDED proof of task 021: Ctrl+1 on a 36-unit selection stores all 36,
pressing 1 brings all 36 back, and the order that follows reaches every one of them --
asserted per unit from in-process state, never from the picture.

.DESCRIPTION
The user's words: "when I select more than 12 units I cannot create a control group of
more than 12 units I would like that to work." This is that, mechanised.

HOW THE KEYS ARE PRESSED, and why two different ways.

  recall (press 1)      an ORDINARY posted keystroke. Plain digits are not accelerators;
                        they reach the game's key dispatcher through its window
                        procedure, so drive-game.ps1's normal Send-ScKey works.

  assign (Ctrl+1)       a posted WM_COMMAND carrying the accelerator's own command id.
  add    (Shift+1)      StarCraft resolves Ctrl and Shift through TranslateAcceleratorA
                        (message pump 0x004D1BF0), which reads the calling THREAD's
                        key-state table -- and Windows never updates that for POSTED
                        messages. A posted Ctrl+1 was measured producing NO command at
                        all. What the accelerator does on a match is send WM_COMMAND with
                        its id, and the window proc's `case 0x111` hands that id straight
                        to the same dispatcher, reading nothing else from the event. So
                        this is the engine's own path with only the modifier check
                        skipped -- and the engine posts exactly such a message to itself
                        at 0x004D1BA0. Ids: research/data/accelerators.tsv.

  This is stated as a LIMIT, not hidden: the keyboard-to-accelerator mapping is the one
  layer these two steps do not exercise. Everything from the command id onwards -- the
  dispatcher, the 3-byte 0x13, the client-side recall, the receive-side store and
  recall, and our hook -- is the engine's own code.

WHY THE RESULT CANNOT BE FAKED:

  1. The count is read off the SHADOW LIST -- every unit, not the 12 the engine holds --
     and the engine's own share is asserted to still be exactly 12 (`visible=12`). A
     recall returning more than 12 is not reachable without this feature.
  2. The step that proves it is the ORDER after the recall: Burrow reaches 36/36, counted
     one unit at a time out of each unit's own CUnit+0xDC bit 0x10. A recall that only
     restored the list without restoring its usefulness would burrow 12.
  3. The selection is CLEARED between the store and the recall, and that clearing is
     asserted, so the 36 cannot be left over from the box.
  4. The map has no triggers, no enemies and one unit-less computer slot, so nothing in
     the game can burrow a Lurker except the command this test issues.

THE ORDERING CHECK. The whole design depends on the engine having already filled
activePlayerSelection (0x006284B8) by the time it queues `13 01 g` -- a claim about
RUNTIME, not about code. The plugin logs what it read there, unconditionally, as
`GROUP recall enter:`, and step [7] asserts it is the POST-recall set and not the
selection the player had a moment before.

.EXAMPLE
./tools/plugin/test-control-groups.ps1

.EXAMPLE
./tools/plugin/test-control-groups.ps1 -KeepOpen
#>
[CmdletBinding()]
param(
    [string]$GameDir = 'C:\sc-work\1161-base',
    [string]$LogPath = 'C:\sc-work\logs\021-control-groups.log',
    [string]$ShotDir = 'C:\sc-work\logs\021-control-group-frames',
    [int]$UnitCount = 36,
    [int]$Group = 1,
    [switch]$KeepOpen
)

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $scriptDir '..' '..')).Path
. (Join-Path $scriptDir 'drive-game.ps1')

$failures = 0
$step = 0

$LURKER_TYPE = '0x67'
$BURROW_CMD = '0x2C'
$BURROW_KEY = 0x55
$IDLE_ORDER = '0x03'

# Which entry of the lobby's Game Type combo is "Use Map Settings" -- MEASURED, by holding
# the combo open and photographing it (work/scratch/probe-gametype.ps1, a throwaway that
# posts WM_LBUTTONDOWN without the matching UP). On this 2-player fixture the list is
# exactly three entries -- Melee, Free For All, Use Map Settings -- and the entry centres
# land on Send-ScDropdownPick's default 16px/15px offsets, so index 2 is right and the
# geometry is right. That measurement is what rules the pick's coordinates and index OUT
# as the cause of a melee start; the remaining cause was the open/hover timing, and
# Send-ScDropdownPick's DEFAULTS were raised for it (every suite was exposed, not just
# this one), so no override is needed here.
$UMS_INDEX = 2

# The fixture folder is SHARED between workers, and every suite in this repo has
# historically opened with `Remove-Item -Recurse` on it. That is how one run came within a
# step of deleting another worker's map out from under their live game (2026-08-09,
# conductor interim rule). This test therefore:
#   * names its fixture with its task id, so "mine" is decidable;
#   * deletes ONLY that file, never the folder;
#   * refuses to start at all if a fixture it did not create is present, rather than
#     removing it or risking the menu's row-2 click landing on it.
$mapDir = Join-Path $GameDir 'Maps\BroodWar\00-testmap'
$mapName = '021-lurkers.scx'
$mapPath = Join-Path $mapDir $mapName

function Remove-MyFixture {
    if (Test-Path -LiteralPath $mapPath) {
        Remove-Item -LiteralPath $mapPath -Force -ErrorAction SilentlyContinue
    }
}

function Assert-FixtureFolderIsOurs {
    if (-not (Test-Path -LiteralPath $mapDir)) { return }
    $foreign = @(Get-ChildItem -LiteralPath $mapDir -Filter *.scx -ErrorAction SilentlyContinue |
                 Where-Object { $_.Name -ne $mapName })
    if ($foreign.Count -gt 0) {
        throw ("test: $mapDir already holds a fixture this test did not create " +
               "($($foreign.Name -join ', ')). Another worker is probably mid-run. " +
               "Refusing to start rather than deleting their map or letting the menu's " +
               "row-2 click land on it -- re-run when they are done.")
    }
}

function Assert-That {
    param([string]$What, [bool]$Ok, [string]$Detail = '')
    if ($Ok) { Write-Host "  ok   $What" }
    else { Write-Host "  FAIL $What $Detail"; $script:failures++ }
}

function Step {
    param([string]$Name, [scriptblock]$Body)
    $script:step++
    Write-Host ''
    Write-Host ("[{0}] {1}" -f $script:step, $Name)
    & $Body
}

$markerPath = Join-Path (Split-Path $LogPath -Parent) 'marker.txt'
function Get-ScState {
    param([string]$Tag, [int]$TimeoutSec = 15)
    Get-ScUnitState -LogPath $LogPath -Tag $Tag -MarkerPath $markerPath -TimeoutSec $TimeoutSec
}

function Get-NewLines {
    param([int]$FromLine)
    @(Get-Content -LiteralPath $LogPath | Select-Object -Skip $FromLine)
}

function Assert-ScAllOneType {
    param([string]$What, $State, [string]$ExpectedType)
    $only = @($State.Types.Keys)
    $ok = ($only.Count -eq 1) -and ($State.Types[$only[0]] -eq $State.Live) -and
          ($only[0] -eq $ExpectedType)
    Assert-That "$What`: all $($State.Live) units are $ExpectedType" $ok "(got $($State.TypesText))"
}

# --- on-disk binary, BEFORE anything runs --------------------------------------
$exePath = Join-Path $GameDir 'StarCraft.exe'
if (-not (Test-Path -LiteralPath $exePath)) { throw "test: $exePath not found." }
$hashBefore = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash
Write-Host "[0] StarCraft.exe SHA-256 before: $hashBefore"
$PRISTINE_SHA256 = 'AD6B58B27B8948845CCFA69BCFCC1B10D6AA7A27A371EE3E61453925288C6A46'
Assert-That 'the working copy starts out byte-identical to pristine 1.16.1' `
    ($hashBefore -eq $PRISTINE_SHA256) "(got $hashBefore)"

if (Test-Path -LiteralPath $LogPath) { Remove-Item -LiteralPath $LogPath -Force }
if (Test-Path -LiteralPath $markerPath) { Remove-Item -LiteralPath $markerPath -Force }
New-Item -ItemType Directory -Path $ShotDir -Force | Out-Null

$gamePid = 0
$hwnd = [IntPtr]::Zero
$shotN = 0
function Shot([string]$tag) {
    if ($script:hwnd -eq [IntPtr]::Zero) { return }
    $script:shotN++
    Save-ScWindowImage -Hwnd $script:hwnd -Path (Join-Path $ShotDir ("{0:d2}-{1}.png" -f $script:shotN, $tag)) -FullWindow | Out-Null
}

try {
    Step "generate the fixture: $UnitCount Lurkers, Use Map Settings, no triggers" {
        Assert-FixtureFolderIsOurs
        Remove-MyFixture
        $gen = & (Join-Path $repoRoot 'tools/make-test-map.ps1') `
            -UnitCount $UnitCount -UnitType lurker -Player 0 -OutputPath $mapPath 2>&1
        $gen = @($gen | Where-Object { "$_" -notmatch 'WARNING:StormLibFinder' })
        $gen | ForEach-Object { Write-Host "       $_" }
        Assert-That 'the generator succeeded' ($LASTEXITCODE -eq 0) "(exit $LASTEXITCODE)"
        Assert-That 'it wrote the map' (Test-Path -LiteralPath $mapPath)
        Assert-That 'nothing can end the game on its own (TRIG is empty)' `
            (@($gen | Select-String -Pattern 'TRIG holds 0 byte').Count -gt 0)
        Assert-That "the human's player id is not left to the engine to pick" `
            (@($gen | Select-String -Pattern 'no force randomises start locations').Count -gt 0)
    }

    & (Join-Path $scriptDir 'run-with-plugin.ps1') `
        -Mode fanout -InjectWindowedHelper WMode `
        -GameDir $GameDir -LogPath $LogPath 6>&1 | ForEach-Object {
            Write-Host $_
            if ("$_" -match 'scinject:\s*PID=(\d+)') { $script:gamePid = [int]$Matches[1] }
        }
    if (-not $gamePid) { throw 'test: could not parse the game pid from scinject output.' }
    $hwnd = Get-ScGameWindow -ProcessId $gamePid

    Step "menus: Single Player -> Expansion -> Play Custom -> 00-testmap\$mapName" {
        Start-Sleep -Seconds 2
        Send-ScClick -Hwnd $hwnd -X 215 -Y 119        # Single Player
        Send-ScClick -Hwnd $hwnd -X 373 -Y 300        # StarCraft: Brood War (Expansion)
        Start-Sleep -Seconds 1
        Send-ScClick -Hwnd $hwnd -X 75  -Y 111        # first entry in the Registry list
        Send-ScClick -Hwnd $hwnd -X 516 -Y 392        # Ok
        Start-Sleep -Seconds 2
        Send-ScClick -Hwnd $hwnd -X 327 -Y 415        # Play Custom
        Start-Sleep -Seconds 2
        Send-ScClick -Hwnd $hwnd -X 117 -Y 140        # [00-testmap]
        Send-ScClick -Hwnd $hwnd -X 516 -Y 393        # Ok
        Start-Sleep -Milliseconds 800
        Send-ScClick -Hwnd $hwnd -X 117 -Y 159        # our fixture: the only .scx here
        Start-Sleep -Milliseconds 500
        # Set the Game Type EXPLICITLY: the combo carries whatever this machine's profile
        # last used, and a stale "Melee" hands the slot melee starting units instead of
        # the map's own 36 (task 015/016).
        #
        # A run of this test came up Melee -- 4 Drones (`types=[0x40:4]`) instead of 36
        # Lurkers -- so this step is driven off a MEASURED list rather than a remembered
        # index. The combo was held open and photographed
        # (work/scratch/probe-gametype.ps1); $UMS_INDEX below is that measurement, and
        # the box step names a melee start explicitly if it ever slips again.
        #
        # Picked twice because these are press-and-hold controls driven by posted
        # messages, and choosing an entry that is already selected is a no-op -- so a
        # second attempt costs a second and removes a whole failure mode.
        Send-ScDropdownPick -Hwnd $hwnd -X 265 -Y 268 -Index $UMS_INDEX
        Start-Sleep -Milliseconds 400
        Send-ScDropdownPick -Hwnd $hwnd -X 265 -Y 268 -Index $UMS_INDEX
        Shot 'lobby'
        Send-ScClick -Hwnd $hwnd -X 516 -Y 393        # Ok -> mission briefing
        Start-Sleep -Seconds 6
        Send-ScClick -Hwnd $hwnd -X 544 -Y 387        # Start
        Start-Sleep -Seconds 10
        Send-ScClick -Hwnd $hwnd -X 200 -Y 261        # dismiss "StarCraft Tips"
        Start-Sleep -Seconds 2
        Shot 'in-game'
    }

    Step "box all $UnitCount Lurkers -- more than twice the engine's cap" {
        Send-ScDrag -Hwnd $hwnd -X1 10 -Y1 10 -X2 630 -Y2 340 -Steps 20
        Start-Sleep -Seconds 2
        $script:boxed = Get-ScState 'boxed'
        # DIAGNOSE THE ONE FIXTURE FAILURE THAT LOOKS LIKE TEN FEATURE FAILURES FIRST.
        # If the Game Type combo did not take, the game played as Melee and the slot got
        # standard Zerg starting units -- Drones (type 0x40), not the map's Lurkers. Left
        # undiagnosed that shows up as "stored 4, not 36" and eight more downstream
        # failures that say nothing about control groups. Throwing here stops the run at
        # its actual cause.
        if ($boxed.Types.ContainsKey('0x40') -or $boxed.N -lt 12) {
            throw ("test: this is a MELEE start, not the fixture -- the Game Type combo " +
                   "did not take (types=[$($boxed.TypesText)], n=$($boxed.N)). Re-run; " +
                   "nothing about control groups was exercised.")
        }
        Assert-That "the box holds all $UnitCount placed units ($($boxed.N))" ($boxed.N -eq $UnitCount)
        Assert-ScAllOneType 'the spawned units' $boxed $LURKER_TYPE
        Assert-That "the engine itself holds only twelve ($($boxed.Visible))" ($boxed.Visible -eq 12)
        Assert-That "the rest are beyond the cap ($($boxed.Overflow))" `
            ($boxed.Overflow -eq $UnitCount - 12)
        Assert-That "nobody is burrowed yet ($($boxed.Burrowed)/$($boxed.BurrowedOf))" `
            ($boxed.Burrowed -eq 0)
        Write-Host "       $($boxed.Line)"
        Shot 'boxed'
    }

    Step "Ctrl+$Group stores the WHOLE selection, not the engine's twelve" {
        $mark = Get-ScLogLineCount -LogPath $LogPath
        Send-ScControlGroupAssign -Hwnd $hwnd -Group $Group
        Start-Sleep -Seconds 2
        $lines = Get-NewLines $mark

        # The engine's own command, byte for byte: id 0x13, action 0 (ASSIGN), group N.
        Assert-That "the engine emitted the assign command (13 00 0$Group)" `
            (@($lines | Select-String -Pattern ("CMD id=0x13 len=3 bytes=\[13 00 {0:X2}\]" -f $Group)).Count -gt 0)

        $g = @($lines | Select-String -Pattern 'GROUP assign: group=(\d+) now holds (\d+)')
        Assert-That 'the plugin stored a group' ($g.Count -gt 0)
        if ($g.Count -gt 0) {
            $m = [regex]::Match($g[-1].Line, 'group=(\d+) now holds (\d+)')
            $storedGroup = [int]$m.Groups[1].Value
            $script:stored = [int]$m.Groups[2].Value
            Write-Host "       $($g[-1].Line.Trim())"
            Assert-That "it stored group $Group" ($storedGroup -eq $Group)
            # THE POINT OF THE WHOLE TASK, first half.
            Assert-That "it stored all $UnitCount units, not 12 ($stored)" ($stored -eq $UnitCount)
        }
        Shot 'after-ctrl-1'
    }

    Step 'clear the selection, so nothing can be left over from the box' {
        # A click on empty ground above the Lurker block.
        #
        # The assertion is "at most one", not "exactly zero", and the difference is
        # measured rather than assumed: a click on bare terrain leaves the shadow list
        # holding ONE entry that is already `live=0 removed=1` -- an artefact of the
        # engine's own click path committing a selection our capture then judges dead,
        # not a unit the player has. What matters for this test is only that the 36
        # cannot survive into the next step, and one dead entry cannot become 36.
        Send-ScClick -Hwnd $hwnd -X 320 -Y 30
        Start-Sleep -Seconds 2
        $script:cleared = Get-ScState 'cleared'
        Assert-That "the boxed $UnitCount are gone ($($cleared.N) entr(y/ies) left)" `
            ($cleared.N -le 1) "(anything above 1 means the click did not clear it)"
        Assert-That '  and nothing live is selected any more' ($cleared.Live -eq 0)
        Write-Host "       $($cleared.Line)"
        Shot 'cleared'
    }

    Step "press $Group -- ALL $UnitCount come back" {
        # Kept for the NEXT step as well as this one. The HUD-row and circle evidence has
        # to be scoped to lines written AFTER the recall keypress: the 36-unit drag box in
        # step [3] already emitted `HUDROW show n=36 page=1/3` and `CIRCLES show: 24/24`,
        # and the clear in step [5] emits neither pattern (it logs `HUDROW stock restored`,
        # and ShowOverflowCircles returns silently when there is no overflow). So a step
        # that searched the whole log would pass on the BOX's lines even if the recall
        # re-paged nothing and re-attached nothing -- and those two lines are the only
        # in-game evidence for "the row and circles reflect a >12 recall".
        $script:recallMark = Get-ScLogLineCount -LogPath $LogPath
        $mark = $script:recallMark
        Send-ScControlGroupRecall -Hwnd $hwnd -Group $Group
        Start-Sleep -Seconds 3
        $lines = Get-NewLines $mark

        Assert-That "the engine emitted the recall command (13 01 0$Group)" `
            (@($lines | Select-String -Pattern ("CMD id=0x13 len=3 bytes=\[13 01 {0:X2}\]" -f $Group)).Count -gt 0)

        # --- THE ORDERING CHECK (conductor addition 2) --------------------------
        # The design assumes the engine has ALREADY rebuilt activePlayerSelection by the
        # time it queues the recall command. This is the direct read-back of that array,
        # taken at hook time before anything of ours ran. If the engine had not run yet
        # it would still hold the CLEARED selection (0 units), which is what the previous
        # step just asserted it was.
        $enter = @($lines | Select-String -Pattern 'GROUP recall enter: group=\d+ activePlayerSelection holds visible=(\d+)')
        Assert-That 'the plugin logged what it read from activePlayerSelection' ($enter.Count -gt 0)
        if ($enter.Count -gt 0) {
            Write-Host "       $($enter[-1].Line.Trim())"
            $ev = [int][regex]::Match($enter[-1].Line, 'visible=(\d+)').Groups[1].Value
            Assert-That "ORDERING: activePlayerSelection already held the POST-recall twelve at hook time ($ev)" `
                ($ev -eq 12) "(0 would mean the engine had not rebuilt it yet -- the design's core assumption)"
            $tags = @([regex]::Match($enter[-1].Line, '\[([0-9A-F ]*)\]').Groups[1].Value -split ' ' |
                      Where-Object { $_ })
            Assert-That "  and it read $ev distinct unit tags out of it" `
                ($tags.Count -eq $ev -and (@($tags | Sort-Object -Unique).Count -eq $ev))
            # Kept for the HUD-row cross-check in the next step: these tags come from
            # activePlayerSelection, the row's come from the live dialog's button records.
            $script:engineVisibleTags = $tags
        }

        $r = @($lines | Select-String -Pattern 'GROUP recall: group=(\d+) -> (\d+) unit\(s\) \((\d+) visible from the engine \+ (\d+) restored past the cap, (\d+) dropped')
        Assert-That 'the plugin rebuilt the selection from its group' ($r.Count -gt 0)
        if ($r.Count -gt 0) {
            Write-Host "       $($r[-1].Line.Trim())"
            $m = [regex]::Match($r[-1].Line, '-> (\d+) unit\(s\) \((\d+) visible from the engine \+ (\d+) restored past the cap, (\d+) dropped')
            $total = [int]$m.Groups[1].Value; $vis = [int]$m.Groups[2].Value
            $rest = [int]$m.Groups[3].Value;  $drop = [int]$m.Groups[4].Value
            Assert-That "ALL $UnitCount ARE BACK ($total)" ($total -eq $UnitCount)
            Assert-That "  the engine still holds only twelve of them ($vis)" ($vis -eq 12)
            Assert-That "  the other $($UnitCount - 12) came from the plugin's group ($rest)" `
                ($rest -eq $UnitCount - 12)
            Assert-That "  nothing was dropped as not live ($drop)" ($drop -eq 0)
        }
        Assert-That 'no group was discarded for failing containment' `
            (@($lines | Select-String -Pattern 'GROUP discard:').Count -eq 0)

        $script:recalled = Get-ScState 'recalled'
        Assert-That "the shadow list agrees: $UnitCount units ($($recalled.N))" ($recalled.N -eq $UnitCount)
        Assert-That "  visible=12, overflow=$($UnitCount - 12)" `
            ($recalled.Visible -eq 12 -and $recalled.Overflow -eq $UnitCount - 12)
        Assert-That "  and every one of them is live ($($recalled.Live))" ($recalled.Live -eq $UnitCount)
        Assert-ScAllOneType 'the recalled units' $recalled $LURKER_TYPE
        Write-Host "       $($recalled.Line)"
        Shot 'recalled'
    }

    Step 'the HUD row and the circles reflect the recall exactly as they do a box' {
        # Merged features (tasks 014/017): a >12 recall must page the row and circle the
        # over-cap units, the same as a >12 drag box.
        #
        # SCOPED TO THE RECALL, not the whole log -- see the comment at $script:recallMark.
        # Searching the whole file would find the drag box's own lines and pass whether or
        # not the recall did anything.
        $lines = Get-NewLines $script:recallMark

        $rows = @($lines | Select-String -Pattern 'HUDROW show n=(\d+) page=(\d+)/(\d+) slots=(\d+) \[([0-9A-F ]*)\]')
        Assert-That 'the recall itself made the row re-page' ($rows.Count -gt 0) `
            '(no HUDROW show line after the recall keypress)'
        if ($rows.Count -gt 0) {
            $m = [regex]::Match($rows[-1].Line,
                'n=(\d+) page=(\d+)/(\d+) slots=(\d+) \[([0-9A-F ]*)\]')
            Write-Host "       $($rows[-1].Line.Trim())"
            Assert-That "  it lists all $UnitCount units ($($m.Groups[1].Value))" `
                ([int]$m.Groups[1].Value -eq $UnitCount)
            Assert-That "  over 3 pages, showing page 1 ($($m.Groups[2].Value)/$($m.Groups[3].Value))" `
                ([int]$m.Groups[2].Value -eq 1 -and [int]$m.Groups[3].Value -eq 3)
            # `n`/`page`/`pages` are the plugin's own counters. `slots` and the tag list
            # are the genuine read-back OUT OF the live dialog's button records
            # (sc_hudrow.cpp's `HUDROW show`), so they are the half that can disagree with
            # us -- assert those, or this step is the plugin marking its own homework.
            Assert-That "  and it really filled twelve dialog buttons (slots=$($m.Groups[4].Value))" `
                ([int]$m.Groups[4].Value -eq 12)
            $rowTags = @($m.Groups[5].Value -split ' ' | Where-Object { $_ })
            Assert-That "  reading back $($rowTags.Count) distinct tags from the buttons" `
                ($rowTags.Count -eq 12 -and (@($rowTags | Sort-Object -Unique).Count -eq 12))
            # CROSS-MODULE: page 1 always shows the engine's own twelve (task 017's rule).
            # Those twelve are exactly what the recall read out of activePlayerSelection a
            # moment earlier -- a different module, a different source. Comparing the two
            # is a real agreement check rather than a restatement.
            if ($null -ne $script:engineVisibleTags) {
                $diff = @($rowTags | Where-Object { $script:engineVisibleTags -notcontains $_ }) +
                        @($script:engineVisibleTags | Where-Object { $rowTags -notcontains $_ })
                Assert-That '  and the buttons name exactly the units the recall put in activePlayerSelection' `
                    ($diff.Count -eq 0) "(differing tags: $($diff -join ' '))"
            }
        }

        $circ = @($lines | Select-String -Pattern 'CIRCLES show: (\d+)/(\d+)')
        Assert-That 'the recall itself re-attached the circles' ($circ.Count -gt 0) `
            '(no CIRCLES show line after the recall keypress)'
        if ($circ.Count -gt 0) {
            Write-Host "       $($circ[-1].Line.Trim())"
            $m = [regex]::Match($circ[-1].Line, 'CIRCLES show: (\d+)/(\d+)')
            $got = [int]$m.Groups[1].Value      # ATTACHED
            $want = [int]$m.Groups[2].Value     # requested
            # `%d/%d` is shown/requested. The second number is the plugin echoing its own
            # input, so testing it alone would pass a run where the engine's image free
            # list was empty and nothing was drawn at all (`0/24`). Test the ATTACHED
            # count, and that it is non-zero -- the shape test-selection-circles.ps1 uses.
            Assert-That "  one attached per over-cap unit ($got attached of $want requested)" `
                ($got -eq $want -and $got -eq $UnitCount - 12 -and $got -gt 0)
        }
        Shot 'recalled-hud'
    }

    Step "an order after the recall reaches every one of the $UnitCount" {
        # Precondition, asserted not assumed: one shared order across every live unit.
        $only = @($recalled.Orders.Keys)
        Assert-That "every recalled unit shares ONE order before the keypress (must be $IDLE_ORDER)" `
            ($only.Count -eq 1 -and $only[0] -eq $IDLE_ORDER -and $recalled.Orders[$only[0]] -eq $recalled.Live) `
            "(got $($recalled.Line))"

        # CROSS-TASK RECORD (conductor addition 3b, task 022 is investigating whether
        # replayed Selects interrupt in-progress orders). The per-unit order histogram
        # across the whole recall is printed here whether or not it looks fine, so that
        # if 022 lands a fix these numbers are the before/after evidence for whether
        # control-group recall was ever affected.
        Write-Host "       [022] order histogram BEFORE the box:    $($boxed.Line -replace '^.*orders=', 'orders=')"
        Write-Host "       [022] order histogram AFTER the recall:  $($recalled.Line -replace '^.*orders=', 'orders=')"

        $mark = Get-ScLogLineCount -LogPath $LogPath
        Send-ScKey -Hwnd $hwnd -VirtualKey $BURROW_KEY
        Start-Sleep -Seconds 4
        $lines = Get-NewLines $mark

        Assert-That "the key emitted $BURROW_CMD" `
            (@($lines | Select-String -Pattern "CMD id=$BURROW_CMD ").Count -gt 0)
        $start = @($lines | Select-String -Pattern "FANOUT start: cmd=$BURROW_CMD .* units=(\d+)")
        Assert-That 'it was fanned out' ($start.Count -gt 0)
        if ($start.Count -gt 0) {
            $u = [int]([regex]::Match($start[-1].Line, 'units=(\d+)').Groups[1].Value)
            Assert-That "every RECALLED unit was commanded ($u of $UnitCount)" ($u -eq $UnitCount)
        }
        Assert-That 'every chunk went out' `
            (@($lines | Select-String -Pattern 'FANOUT done').Count -gt 0)

        $after = Get-ScState 'burrowed-after-recall'
        Assert-That "nobody died on the way ($($recalled.Live) -> $($after.Live))" `
            ($after.Live -eq $recalled.Live)
        # THE SECOND HALF OF THE TASK: the recalled group is not just a list, it obeys.
        Assert-That "burrowed went $($recalled.Burrowed)/$($recalled.BurrowedOf) -> $($after.Burrowed)/$($after.BurrowedOf)" `
            ($after.Burrowed -eq $after.BurrowedOf -and $after.BurrowedOf -eq $UnitCount)
        Assert-That "and that is far more than the twelve the engine holds ($($after.Burrowed))" `
            ($after.Burrowed -gt 12)
        Write-Host "       $($after.Line)"
        Write-Host "       [022] order histogram AFTER the fanned order: $($after.Line -replace '^.*orders=', 'orders=')"
        $script:burrowed = $after
        Shot 'after-order'
    }

    Step "Shift+$Group (add to group) -- what the engine supports, exercised" {
        # The engine's ADD action exists (CMDRECV_Hotkey dispatches [+1]==2 to the
        # append-at-first-free path) and the key is Shift+N, from the accelerator table
        # in StarCraft.exe resource 0x71. Both halves are asserted here rather than
        # asserted statically and hoped for.
        $mark = Get-ScLogLineCount -LogPath $LogPath
        Send-ScControlGroupAdd -Hwnd $hwnd -Group $Group
        Start-Sleep -Seconds 2
        $lines = Get-NewLines $mark
        Assert-That "Shift+$Group emits the ADD command (13 02 0$Group)" `
            (@($lines | Select-String -Pattern ("CMD id=0x13 len=3 bytes=\[13 02 {0:X2}\]" -f $Group)).Count -gt 0)
        $a = @($lines | Select-String -Pattern 'GROUP add: group=(\d+) now holds (\d+)')
        Assert-That 'the plugin unioned into the group' ($a.Count -gt 0)
        if ($a.Count -gt 0) {
            Write-Host "       $($a[-1].Line.Trim())"
            $held = [int][regex]::Match($a[-1].Line, 'now holds (\d+)').Groups[1].Value
            # The same 36 units are selected, so the union must DEDUPLICATE to 36 rather
            # than double to 72.
            Assert-That "adding the same selection leaves $UnitCount, not $($UnitCount * 2) ($held)" `
                ($held -eq $UnitCount)
        }
        Assert-That 'no group was reset (the engine did not restart)' `
            (@($lines | Select-String -Pattern 'GROUP reset:').Count -eq 0)
    }

    Step 'a second recall, with a >12 selection already active, is still exact' {
        # Acceptance criterion: "group recall while a >12 selection is already active".
        # 36 are selected right now, so this recall replaces a shadow list rather than
        # building one from nothing.
        $mark = Get-ScLogLineCount -LogPath $LogPath
        Send-ScControlGroupRecall -Hwnd $hwnd -Group $Group
        Start-Sleep -Seconds 3
        $lines = Get-NewLines $mark
        $r = @($lines | Select-String -Pattern 'GROUP recall: group=\d+ -> (\d+) unit\(s\)')
        Assert-That 'the recall ran' ($r.Count -gt 0)
        if ($r.Count -gt 0) {
            Write-Host "       $($r[-1].Line.Trim())"
            Assert-That "it is still $UnitCount, not doubled or halved" `
                ([int][regex]::Match($r[-1].Line, '-> (\d+) unit').Groups[1].Value -eq $UnitCount)
        }
        $s = Get-ScState 'recalled-over-active'
        Assert-That "the shadow list is still $UnitCount ($($s.N))" ($s.N -eq $UnitCount)
        Assert-That "  and still visible=12 ($($s.Visible))" ($s.Visible -eq 12)
        # The units are burrowed from the previous step, so this also shows a recall does
        # not disturb unit state.
        Assert-That "  the units are still burrowed ($($s.Burrowed)/$($s.BurrowedOf))" `
            ($s.Burrowed -eq $s.BurrowedOf)
        Write-Host "       $($s.Line)"
    }

    Step 'the run never fanned out anything outside the policy set' {
        $allowed = @('0x14', '0x15', '0x1A', '0x1B', '0x1C', '0x1D', '0x1E', '0x21',
                     '0x22', '0x25', '0x26', '0x28', '0x2A', '0x2B', '0x2C', '0x2D',
                     '0x2E', '0x36', '0x5A')
        $ids = @(Get-Content -LiteralPath $LogPath |
                 Select-String -Pattern 'FANOUT start: cmd=(0x[0-9A-F]{2})' |
                 ForEach-Object { [regex]::Match($_.Line, 'cmd=(0x[0-9A-F]{2})').Groups[1].Value } |
                 Sort-Object -Unique)
        Write-Host "       ids fanned out this run: $($ids -join ' ')"
        $stray = @($ids | Where-Object { $allowed -notcontains $_ })
        Assert-That 'every fanned-out id is in the policy set' ($stray.Count -eq 0) `
            ($stray.Count -gt 0 ? "(stray: $($stray -join ' '))" : '')
        # 0x13 must never be fanned out: it is a control-group command, not an order.
        Assert-That 'the hotkey command itself was never fanned out' `
            ($ids -notcontains '0x13')
    }
}
catch {
    Write-Host "  FAIL a test step threw: $($_.Exception.Message)"
    Write-Host "       $($_.ScriptStackTrace)"
    $failures++
}
finally {
    if (-not $KeepOpen -and $gamePid -gt 0) {
        try { & (Join-Path $scriptDir 'close-game.ps1') -ProcessId $gamePid | Write-Host }
        catch {
            Write-Host "  FAIL close-game could not shut the game down: $($_.Exception.Message)"
            $failures++
        }
        Start-Sleep -Seconds 2
    }
    elseif (-not $KeepOpen) {
        Write-Host '  FAIL no pid was ever parsed, so nothing could be closed'
        $failures++
    }
    # ONLY our own file, never the folder -- another worker's fixture may be sitting
    # beside it with their game still reading it.
    if (-not $KeepOpen) { Remove-MyFixture }
}

Write-Host ''
Write-Host '[final] the run must balance'
$left = if ($gamePid -gt 0) { Get-Process -Id $gamePid -ErrorAction SilentlyContinue } else { $null }
Assert-That 'the game process this test started is gone' ($KeepOpen -or $null -eq $left)
Assert-That 'the generated map was cleaned up' ($KeepOpen -or -not (Test-Path -LiteralPath $mapPath))

$hashAfter = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash
Write-Host "  StarCraft.exe SHA-256 after:  $hashAfter"
Assert-That 'StarCraft.exe on disk is byte-identical to before the run' ($hashAfter -eq $hashBefore)
Assert-That 'and still byte-identical to pristine 1.16.1' ($hashAfter -eq $PRISTINE_SHA256)

Write-Host ''
Write-Host "test-control-groups: $failures failure(s)"
Write-Host "frames (diagnostic, NOT committable): $ShotDir"
exit ($failures -eq 0 ? 0 : 1)
