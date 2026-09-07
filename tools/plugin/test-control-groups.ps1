#Requires -Version 7
<#
.SYNOPSIS
Unattended proof that Ctrl+1 stores a 36-unit selection whole, pressing 1 brings all 36 back,
and the next order reaches every one -- asserted per unit from in-process state, not the picture.
.DESCRIPTION
Recall (plain digit) is an ordinary posted keystroke. Assign (Ctrl+1) and add (Shift+1) post a
WM_COMMAND carrying the accelerator's id (research/data/accelerators.tsv): TranslateAcceleratorA
(pump 0x004D1BF0) reads the calling THREAD's key-state table, which Windows never updates for
posted messages -- a posted Ctrl+1 was measured producing NO command. The engine posts exactly
such a message to itself at 0x004D1BA0; only the key-to-accelerator mapping stays unexercised.
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
    # Which folder under Maps\ the fixture is generated into; see test-burrow-fanout.ps1.
    [string]$FixtureDir,
    [int]$UnitCount = 36,
    [int]$Group = 1,
    [switch]$KeepOpen
)

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $scriptDir '..' '..')).Path
. (Join-Path $scriptDir 'drive-game.ps1')

. (Join-Path $scriptDir 'sc-suite.ps1')

$failures = 0
$step = 0

$LURKER_TYPE = '0x67'
$BURROW_CMD = '0x2C'
$BURROW_KEY = 0x55
$IDLE_ORDER = '0x03'

# Which entry of the lobby's Game Type combo is "Use Map Settings" -- MEASURED, by holding the
# combo open and photographing it (work/scratch/probe-gametype.ps1 posts WM_LBUTTONDOWN without
# the matching UP). On this 2-player fixture the list is exactly three entries -- Melee, Free
# For All, Use Map Settings -- and the entry centres land on Send-ScDropdownPick's default
# 16px/15px offsets, so both the index and the click geometry are right.
$UMS_INDEX = 2

# OUR OWN FIXTURE FOLDER, never the shared `00-testmap` (AGENTS.md § "Test fixtures").
# Being careful inside a shared folder does not work: workers write into it concurrently, the
# map browser is clicked by ROW, and a foreign file that sorts first silently becomes the map
# THIS test loads -- not a failure, a run that reports confident nonsense. One folder per suite
# removes that interference rather than scheduling around it:
#   * the fixture is named for its suite and only that file is ever deleted, on every path;
#   * the run REFUSES to start on any `.scx` it did not create;
#   * the folder is removed at the end ONLY IF EMPTY: an empty folder of ours pushes every
#     entry below it down a row for everybody else, and only six rows are visible.
# With $env:AGENT_TASK set the folder is THIS agent's own, so two concurrent runs of this same
# suite cannot land in one folder and overwrite each other's identically-named fixture.
if (-not $FixtureDir) { $FixtureDir = Resolve-ScFixtureDir -GameDir $GameDir -Fallback '00-t021' -Suite 'control-groups' }
$mapDir = $FixtureDir
$mapName = 'control-groups.scx'
$mapPath = Join-Path $mapDir $mapName
$fixtures = New-ScFixtureRun -Dir $mapDir -Names @($mapName)

function Remove-MyFixtureDirIfEmpty { Remove-ScOwnFixtureDir -Dir $mapDir }
function Remove-MyFixture { Remove-ScOwnFixture -Run $fixtures }
function Assert-FixtureFolderIsOurs { Assert-ScFixtureFolderMine -Run $fixtures }

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

    Step "menus: Single Player -> Expansion -> Play Custom -> $mapName" {
        Start-Sleep -Seconds 2
        Send-ScClick -Hwnd $hwnd -X 215 -Y 119        # Single Player
        Send-ScClick -Hwnd $hwnd -X 373 -Y 300        # StarCraft: Brood War (Expansion)
        Start-Sleep -Seconds 1
        Send-ScClick -Hwnd $hwnd -X 75  -Y 111        # first entry in the Registry list
        Send-ScClick -Hwnd $hwnd -X 516 -Y 392        # Ok
        Start-Sleep -Seconds 2
        Send-ScClick -Hwnd $hwnd -X 327 -Y 415        # Play Custom
        Start-Sleep -Seconds 2
        # Both rows are computed from the filesystem and the opened folder is verified before
        # the map row is clicked: no sort order holds once a second suite makes its own fixture
        # folder (AGENTS.md § "Map browser").
        Assert-ScFixtureStillMine -Run $fixtures -MapPath $mapPath
        Select-ScBrowserMap -Hwnd $hwnd -GameDir $GameDir -MapPath $mapPath | Out-Null
        # Set the Game Type EXPLICITLY: the combo carries whatever this machine's profile last
        # used, and a stale "Melee" hands the slot melee starting units -- 4 Drones -- instead
        # of the map's own 36 (AGENTS.md § "Game Type / `Custom Type`"). Set-ScGameType reads
        # the engine's own dialog list back after the pick and retries up to 3 times until it
        # reads $UMS_INDEX's name, so a pick that silently did not take fails here rather than
        # as ten meaningless assertions downstream.
        Set-ScGameType -Hwnd $hwnd -LogPath $LogPath -Index $UMS_INDEX
        Shot 'lobby'
        Send-ScClick -Hwnd $hwnd -X 516 -Y 393        # Ok -> mission briefing
        Start-Sleep -Seconds 6
        Send-ScClick -Hwnd $hwnd -X 544 -Y 387        # Start
        Start-Sleep -Seconds 10
        # The tips dialog is found in the engine's own dialog list and dismissed by ITS OWN OK
        # button, then asserted gone -- never a fixed point, never the registry
        # (AGENTS.md § "Tips dialog").
        Dismiss-ScTipsDialog -Hwnd $hwnd -LogPath $LogPath | Out-Null
        Start-Sleep -Seconds 2
        Shot 'in-game'
    }

    Step "box all $UnitCount Lurkers -- more than twice the engine's cap" {
        Send-ScDrag -Hwnd $hwnd -X1 10 -Y1 10 -X2 630 -Y2 340 -Steps 20
        Start-Sleep -Seconds 2
        $script:boxed = Get-ScState 'boxed'
        # DIAGNOSE THE ONE FIXTURE FAILURE THAT LOOKS LIKE TEN FEATURE FAILURES FIRST. If the
        # Game Type combo did not take, the game plays as Melee and the slot gets standard Zerg
        # starting units -- Drones (type 0x40), not the map's Lurkers. Undiagnosed that reads as
        # "stored 4, not 36" plus eight downstream failures saying nothing about control groups,
        # so throwing here stops the run at its actual cause.
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
            Assert-That "it stored all $UnitCount units, not 12 ($stored)" ($stored -eq $UnitCount)
        }
        Shot 'after-ctrl-1'
    }

    Step 'clear the selection, so nothing can be left over from the box' {
        # A click on empty ground above the Lurker block. The assertion is "at most one", not
        # "exactly zero", and the difference is measured rather than assumed: a click on bare
        # terrain leaves the shadow list holding ONE entry that is already `live=0 removed=1`,
        # an artefact of the engine's own click path committing a selection our capture then
        # judges dead. All this step needs is that the 36 cannot survive into the next one,
        # and one dead entry cannot become 36.
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
        # Scoped for the NEXT step as well: the HUD-row and circle evidence must come from lines
        # written AFTER the recall keypress. The 36-unit drag box already emitted `HUDROW show
        # n=36 page=1/3` and `CIRCLES show: 24/24`, and the clear emits neither pattern, so a
        # step searching the whole log would pass on the BOX's lines even if the recall re-paged
        # and re-attached nothing -- and those two lines are the only in-game evidence that the
        # row and circles reflect a >12 recall.
        $script:recallMark = Get-ScLogLineCount -LogPath $LogPath
        $mark = $script:recallMark
        Send-ScControlGroupRecall -Hwnd $hwnd -Group $Group
        Start-Sleep -Seconds 3
        $lines = Get-NewLines $mark

        Assert-That "the engine emitted the recall command (13 01 0$Group)" `
            (@($lines | Select-String -Pattern ("CMD id=0x13 len=3 bytes=\[13 01 {0:X2}\]" -f $Group)).Count -gt 0)

        # --- THE ORDERING CHECK -------------------------------------------------
        # The design assumes the engine has ALREADY rebuilt activePlayerSelection (0x006284B8)
        # by the time it queues the recall command -- a claim about RUNTIME, not about code.
        # This is the direct read-back of that array, taken at hook time before anything of
        # ours ran: had the engine not run yet it would still hold the CLEARED selection, the
        # 0 units the previous step asserted.
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
            # activePlayerSelection, the row's from the live dialog's button records.
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
        # A >12 recall must page the row and circle the over-cap units, exactly as a >12 drag
        # box does. Scoped to the recall, not the whole log -- see $script:recallMark.
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
            # `n`/`page`/`pages` are the plugin's own counters. `slots` and the tag list are the
            # genuine read-back OUT OF the live dialog's button records (sc_hudrow.cpp's `HUDROW
            # show`), the half that can disagree with us -- assert those, or this step is the
            # plugin marking its own homework.
            Assert-That "  and it really filled twelve dialog buttons (slots=$($m.Groups[4].Value))" `
                ([int]$m.Groups[4].Value -eq 12)
            $rowTags = @($m.Groups[5].Value -split ' ' | Where-Object { $_ })
            Assert-That "  reading back $($rowTags.Count) distinct tags from the buttons" `
                ($rowTags.Count -eq 12 -and (@($rowTags | Sort-Object -Unique).Count -eq 12))
            # CROSS-MODULE: page 1 always shows the engine's own twelve, and those twelve are
            # exactly what the recall read out of activePlayerSelection a moment earlier -- a
            # different module reading a different source, so comparing them is a real
            # agreement check rather than a restatement.
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
            # `%d/%d` is shown/requested. The requested count is the plugin echoing its own
            # input, so testing it alone would pass a run where the engine's image free list
            # was empty and nothing was drawn at all (`0/24`). Test the ATTACHED count, and
            # that it is non-zero -- the shape test-selection-circles.ps1 uses.
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

        # Printed whether or not it looks fine: the per-unit order histogram across the whole
        # recall is the evidence for whether replayed Selects ever interrupt an in-progress
        # order on a recalled group.
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
        # The recalled group is not just a list, it obeys -- and nothing else in the game can
        # burrow a Lurker, since the map has no triggers, no enemies and one unit-less
        # computer slot. Restoring the list without its usefulness would burrow 12. The count
        # is per unit, out of each unit's own CUnit+0xDC bit 0x10, never off the picture.
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
        # The engine's ADD action exists (CMDRECV_Hotkey dispatches [+1]==2 to the append-at-
        # first-free path) and its key is Shift+N, from the accelerator table in StarCraft.exe
        # resource 0x71. Both halves are asserted here rather than taken statically on trust.
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
catch { Write-ScStepFailure $_ 'a test step' }
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
    # ONLY our own file, and the folder only while it is empty -- another worker's fixture
    # may be sitting beside it with their game still reading it.
    if (-not $KeepOpen) { Remove-MyFixture; Remove-MyFixtureDirIfEmpty }
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
