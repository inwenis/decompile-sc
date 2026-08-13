#Requires -Version 7
<#
.SYNOPSIS
RANDOMIZED conformance testing of the shipped features, in a real game, against the
ENGINE'S OWN state. Seeded, replayable from the seed alone, and built to fail on a bug
nobody thought to look for.

.DESCRIPTION
The user asked for this in their own words (2026-08-11): "we list all the actions like
'building x' then 'scheduled unit a' then '12 times' and we verify that it build 12 units
and charged for 12. and we do this for all our features".

WHY IT EXISTS. Six bugs were reported fixed on 2026-08-11; the user played the build and
found four still broken. Two root causes, and NEITHER was exotic:

  * task 037 -- `AnchorFor` had no case for the upgrade mode, so the queue indicator was
    composed and never anchored. Invisible in every real game, on every building, while
    its test asked the composer directly and passed.
  * task 038 -- `sc_prodqueue` read `activePlayerSelection` (0x006284B8) where the engine
    gates on `playersSelections` (0x006284E8). The two arrays ABUT and agree whenever
    exactly ONE building is selected -- which was every case in both suites.

Both die instantly against a randomized sequence that VARIES THE SELECTION SIZE and counts
what the ENGINE did. That is the whole design, and it is why the selection size is the
parameter randomised hardest.

WHAT IT ASSERTS, AND WHERE EACH INVARIANT'S GROUND TRUTH COMES FROM
(AGENTS.md, "Assert the ENGINE'S OWN RESULT, not your bookkeeping")

  INV-W  every Train press reaches the wire.
         GROUND TRUTH: `CMD id=0x1F` logged INSIDE the detour on `queueCommand`
         (0x00485BD0) -- the engine's own outgoing-command funnel. This is the one that
         fails on task 038's parent: the client stops offering the button once a ring
         holds five, so presses six onward never become commands at all.

  INV-R  every selected building's ring stays inside the engine's five slots and holds
         only the type that was trained.
         GROUND TRUTH: that building's own `CUnit+0x98` buildQueue with head at `+0xA4`,
         read out of its memory and printed per building by PRODFAN/PRODQ.

  INV-M  the money. delta-minerals == (items the engine accepted) x cost, and a cancel
         refunds exactly one item's cost.
         GROUND TRUTH: the engine's per-player mineral/gas globals (`minerals=`/`gas=` on
         the PRODFAN summary, read through the engine's own per-player accessor).

  INV-B  what left the queue actually got built.
         GROUND TRUTH: the engine's per-player unit lists, walked by the WORLD scan --
         the count of the trained type owned by the player. This is the "and it built 12"
         half of the user's sentence; INV-M is the "charged for 12" half.

  INV-S  the selection the plugin acts on is the selection the ENGINE gates on.
         GROUND TRUTH: `playersSelections` via the fan-out's `simSlots`, beside the
         client's own count at 0x0059723D. Task 038's exact seam.

  INV-Q  the queue indicator actually REACHED THE SCREEN, expressed as a DIFFERENCE.
         GROUND TRUTH: `QIND ... boxDiff=` -- task 039's count of bytes inside the
         indicator's live bounds that differ from a baseline copy of that same rect, taken
         by the GAME THREAD on frames where the indicator was hidden. Plus the control's
         own `text=` and `bounds=`, read out of the live dialog.
         NOT `ink`, and this is measured rather than supposed: 039 read `ink=448 of 448`
         inside the box BEFORE anything of ours was drawn, because the pane's own art is in
         the same 8-bit surface. That number can neither fail (task 033 shipped `ink > 0`
         and it passed while the box was invisible) nor pass a difference test (our glyph
         changes WHICH bytes are set, not how many). It is printed here as a diagnostic and
         asserted on nowhere.
         The episode reads two states that differ only in our own string -- a logical queue
         of 6 against one of 15, i.e. "+1" against "+10" -- and asserts three things: the
         strings differ, the LONGER string widened the box (its width is a function of
         strlen in the indicator's own PlaceOn, so this is guaranteed by construction
         rather than by what a font happens to look like), and boxDiff > 0 in both states.
         `surfInk` over the whole dialog surface is the blindness control; `refInk` is not
         one, because it is legitimately -1 when neither reference control is visible.
         WHAT IT DOES NOT PROVE, so nobody has to infer it: that the text is legible. It
         proves the engine drew OUR string into the pixels we asked for, and that the box
         is sized from that string. Legibility is a human's judgement and stays one --
         which is why both states are also captured as frames, named for the state, under
         -ShotDir for the user to open.

  INV-P  RETIRED by task 055 (issue #66). It asserted "the plugin spent none of its own
         money" from the plugin's own `mineralsSpent=0` counter, and said so honestly --
         "SELF-CHECK, NOT AN ORACLE". It was worse than that: NOTHING in the plugin ever
         incremented that counter, so the check read its answer out of a zero-initialised
         array. Measured, not inferred: a build with a real spend added left it at 0 while
         28 balance assertions failed.
         The claim is INV-M's and always was -- the engine charged for the N items and no
         more, read off the engine's per-player mineral global, once per episode. That is
         the assertion a plugin spend breaks. A run-level restatement of the plugin's own
         bookkeeping is not a second opinion, so there is no replacement id.

REPRODUCIBILITY. The plan is a pure function of (seed, params) and is generated BEFORE the
game launches -- see random-conformance-plan.ps1, which has its own PRNG for the reason
given there. It is printed, hashed and written to disk next to the log. A failing run ends
by printing the exact command line that replays it.

WHAT A RUN DOES NOT COVER is printed at the end of every run, pass or fail. A green result
that quietly skipped a feature is the failure mode this whole task exists to prevent.

.EXAMPLE
# the gate run: one game, six episodes
./tools/plugin/test-random-conformance.ps1

.EXAMPLE
# replay a failure exactly
./tools/plugin/test-random-conformance.ps1 -Seed 1837465102

.EXAMPLE
# the longer sweep
./tools/plugin/test-random-conformance.ps1 -Episodes 40 -Seed 20260812

.EXAMPLE
# the teeth test: the same plan against a plugin built from another commit
./tools/plugin/test-random-conformance.ps1 -Seed 1837465102 -BuildDir C:\sc-work\builds\59aa50b
#>
[CmdletBinding()]
param(
    [string]$GameDir = $(if ($env:SC_TASK_GAMEDIR) { $env:SC_TASK_GAMEDIR } else { 'C:\sc-work\1161-base' }),
    [string]$LogPath = 'C:\sc-work\logs\041\random-conformance.log',
    # One folder per task, and every frame NAMED FOR THE STATE IT IS (user's standing rule,
    # 2026-08-12: "when you tell me about ui elements you show me with screenshots"). The
    # frames never enter the repo or a PR -- a game frame reproduces game artwork, which
    # hard rule 1 forbids -- so what ships is the PATH, and the read-back stays the oracle.
    [string]$ShotDir = 'C:\sc-work\logs\041-frames',
    [string]$FixtureDir,
    # 0 means "choose one and PRINT it" -- an unseeded run still has a seed, it just has
    # not been told which one yet, and a run whose seed is not on the console is a run
    # whose failures cannot be replayed.
    [int]$Seed = 0,
    [int]$Episodes = 6,
    [ValidateSet('production', 'upgrades', 'hudrow')][string]$Profile = 'production',
    # THREE Command Centers: 3 is the smallest block whose reachable drag rectangles cover
    # sizes 1, 2 AND 3 (a 2x2 grid with the last cell empty), so one fixture exercises the
    # single-building path task 025 shipped and the group path task 038 broke.
    [int]$Buildings = 3,
    [int]$QueueMax = 16,
    # 6 GAME SECONDS per SCV (task 031's -UnitBuildTime), and both directions of this
    # number matter:
    #   * the stock 20 s makes a drain episode cost a minute per building;
    #   * 1 s DESTROYS THE TEST -- the ring drains DURING a press burst, so it never fills,
    #     the client never greys the Train button, and task 038's bug cannot reproduce at
    #     all. A fixture speed-up that removes the state under test is worse than a slow
    #     fixture.
    # 6 s is above the longest burst this generator emits (12 presses x 250 ms = 3 s) and
    # far below anything that costs real time to drain.
    [int]$BuildTimeSec = 6,
    [int]$StartingMinerals = 9000,
    [int]$StartingGas = 3000,
    # Supply. Every SCV that COMPLETES costs one, and queues drain by themselves between
    # episodes, so a long run is supply-bound rather than mineral-bound. A block of depots
    # (8 each) is placed east of the buildings, well outside every drag rectangle.
    [int]$Depots = 12,
    # How far EAST of the start location the depot block sits. The generator refuses a second
    # block closer than 256 px to the player's own (a fixture whose two sides can see each
    # other on the first frame is not idle), and its default 448 leaves only 224 px against a
    # block of Command Centers spaced 160 apart -- measured, not guessed: 448 is refused, 640
    # clears it by 416 px. It is a parameter rather than a constant because -Buildings and
    # -Depots both move that number, and a caller who changes them needs the knob.
    [int]$DepotOffsetX = 640,
    [int]$ClickDelayMs = 250,
    # Point the launch at a plugin built somewhere else -- the teeth test builds task 038's
    # PARENT into a scratch directory and runs this same suite, same seed, against it.
    [string]$BuildDir,
    # The machine runs ONE game at a time behind the launch lock and other workers are
    # using it. Wait rather than fail.
    [int]$LockTimeoutMinutes = 120,
    # Write the plan and exit. No game, no lock, no fixture -- this is what makes the
    # generator itself testable without the machine.
    [switch]$DryRun,
    [string]$PlanOut,
    [switch]$KeepOpen
)

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $scriptDir '..' '..')).Path
. (Join-Path $scriptDir 'random-conformance-plan.ps1')

# ---------------------------------------------------------------------------
# The plan comes first, and it comes before anything that could fail.
# ---------------------------------------------------------------------------
if ($Seed -eq 0) {
    # Not Get-Random: the seed has to be printable, and a seed nobody can read off the
    # console is the failure this whole file is against.
    $Seed = [int]((Get-Date).Ticks % 2147483647)
}
$plan = New-ScConformancePlan -Seed $Seed -Episodes $Episodes -Profile $Profile `
                              -Buildings $Buildings -QueueMax $QueueMax
$planHash = Get-ScPlanHash -Plan $plan
$reproCmd = "./tools/plugin/test-random-conformance.ps1 -Seed $Seed -Episodes $Episodes -Profile $Profile -Buildings $Buildings -QueueMax $QueueMax"

Write-Host ''
Write-Host '================ RANDOMIZED CONFORMANCE ================'
Format-ScPlan -Plan $plan | ForEach-Object { Write-Host $_ }
Write-Host "repro: $reproCmd"
Write-Host '======================================================='

if (-not $PlanOut) { $PlanOut = Join-Path (Split-Path $LogPath -Parent) "plan-$Seed.json" }
New-Item -ItemType Directory -Path (Split-Path $PlanOut -Parent) -Force | Out-Null
Set-Content -LiteralPath $PlanOut -Value ($plan | ConvertTo-Json -Depth 10) -Encoding utf8
Write-Host "plan written: $PlanOut"

if ($DryRun) {
    Write-Host 'dry run: no game was launched.'
    exit 0
}

# ---------------------------------------------------------------------------
# WHAT THIS RUNNER CAN ACTUALLY DRIVE -- one list, used by the refusal below AND by the
# dispatch in the episode loop, so the two cannot drift apart (issue #68).
#
# They HAD drifted. random-conformance-plan.ps1 defines -Profile upgrades (upgrade-burst /
# -cancel / -drain) and -Profile hudrow (row-select / row-page); the dispatch had cases for
# `indicator` and a `default` that fell through to Invoke-QueueEpisode. So every upgrade-*
# episode pressed the TRAIN button and asserted production-queue invariants, and a green
# `-Profile upgrades` run exercised no line of sc_upgrades. A run that tests something other
# than what it says is worse than a run that refuses: the refusal costs a launch, the green
# lie costs whatever is built on it.
#
# The plan generator keeps both profiles -- they generate valid plans and -DryRun still
# prints them, which is where the implementations will start. It is the RUN that refuses.
$QUEUE_EPISODE_KINDS = @('queue-burst', 'group-recall', 'queue-cancel', 'cancel-slot', 'queue-drain')
$IMPLEMENTED_KINDS = $QUEUE_EPISODE_KINDS + @('indicator')
$unimplemented = @($plan.episodes | ForEach-Object { $_.kind } | Sort-Object -Unique |
                   Where-Object { $IMPLEMENTED_KINDS -notcontains $_ })
if ($unimplemented.Count -gt 0) {
    Write-Host ''
    Write-Host 'REFUSED  this runner has no episode implementation for: ' -NoNewline
    Write-Host ($unimplemented -join ', ')
    Write-Host "         -Profile $Profile generates them, but the only episode drivers that exist are"
    Write-Host "         [$($IMPLEMENTED_KINDS -join ', ')], all of which press the TRAIN button and assert"
    Write-Host '         production-queue invariants. Running anyway would test sc_prodqueue and report it'
    Write-Host "         as a green -Profile $Profile run (issue #68)."
    Write-Host '         -DryRun still prints the plan, which is where an implementation starts.'
    Write-Host ''
    Write-Host 'INCOMPLETE  no episode ran; nothing was asserted.'
    exit 2
}

. (Join-Path $scriptDir 'drive-game.ps1')
. (Join-Path $scriptDir 'sc-launch-lock.ps1')
. (Join-Path $scriptDir 'random-conformance-episodes.ps1')
. (Join-Path $scriptDir 'conformance-verdict.ps1')

# ---------------------------------------------------------------------------
# Pinned constants, asserted rather than reported.
# ---------------------------------------------------------------------------
$CC_TYPE       = 106      # units.dat 106, Terran Command Center
$SCV_TYPE      = 7        # units.dat 7,   Terran SCV
$DEPOT_TYPE    = 109      # units.dat 109, Terran Supply Depot
$EBAY_TYPE     = 122      # units.dat 122, Terran Engineering Bay
$MARINE_TYPE   = 0        # units.dat 0,   Terran Marine
$SCV_COST      = 50       # minerals
$SCV_SUPPLY    = 1
$CC_SUPPLY     = 10
$DEPOT_SUPPLY  = 8
$TRAIN_KEY     = 0x53     # 'S', the Command Center card's Train SCV hotkey
$TRAIN_CMD     = '0x1F'   # research/data/command-opcodes.tsv
$QUEUE_EMPTY   = 0xE4     # research/production-queue.md 2.4
# CUnit+0x4C bit 0: SET once the unit is FINISHED. A unit under construction is already in its
# player's list without it (sc_addresses.h 175).
$UNIT_FLAG_COMPLETED = 0x01
# SC_QIND_CHAR_W (sc_queueind.h 61): the indicator's font advance. A box narrower than
# strlen * this is drawn with the string truncated.
$QIND_CHAR_W = 7
$ENGINE_SLOTS  = 5        # the engine's own ring
$ENGINE_HOLD   = 4        # SC_PRODQ_ENGINE_HOLD: what the plugin holds the ring at
$TRAIN_ACTION  = '004234b0'   # the 0x1F emitter
$CANCEL_ACTION = '00423490'   # the 0x20 emitter; actionParam 0xFE is "cancel the last"

# ---------------------------------------------------------------------------
# Findings. A failure carries the seed, the episode and the invariant, because a
# random test's report is worthless without the coordinates to replay it.
# ---------------------------------------------------------------------------
$script:failures = @()
$script:checks = 0
$script:episodeNo = 0
$script:covered = @{}
$script:skipped = @()
$script:frames = @()
# A RUN THAT DIED IS NOT A RUN THAT PASSED, and this harness proved it needs saying: an
# incomplete rename threw immediately after the fixture step, the finally below printed the
# result of the 13 checks that had run, and the whole thing reported `PASS 13 checks, 0
# failures` having executed NOT ONE episode -- while `| Tee-Object` swallowed the exit code
# that would have given it away. A green verdict for a run that asserted nothing is precisely
# the failure this task exists to catch, so the verdict now depends on reaching the end of the
# episode loop, and the exception is caught and reported as a failure rather than unwinding
# past the summary.
#
# ...AND NEITHER IS A RUN THAT SKIPPED EVERY EPISODE (issue #68). `episodesRun` used to be
# incremented at the TOP of the loop, before the four `continue` paths below it (SELECT,
# empty selection, SUPPLY, QUEUE). So a run in which every episode bailed before acting
# still printed `episodes run: 6 of 6` and `PASS N checks, 0 failures, 6 episode(s)` --
# the task-041 disease exactly, reached without an exception and therefore invisible to
# the `finished` flag above. Two counters now, because one cannot tell those apart:
#   entered = the loop began an episode
#   acted   = the episode got past every skip and dispatched
# The verdict depends on `acted`; `entered - acted` is printed as the skip count.
$script:episodesEntered = 0
$script:episodesActed = 0
$script:finished = $false
# DID THIS RUN ACTUALLY REACH THE SEAM IT EXISTS FOR? A burst only tests task 038's bug if it
# pushes a MULTI-BUILDING selection past the engine's five slots; below that the rings never
# fill, the client never greys the button, and a buggy plugin behaves exactly like a correct
# one. Seed 20260812 did that to itself -- its indicator episode filled a building to the cap,
# every later group burst was clamped to two or three presses by the headroom check, and the
# whole run came out GREEN against the very build whose bug it was written to find. Nothing in
# the output said so. This counter is what says so.
#
# TWO counters, because the original counted the wrong thing (issue #68). It was incremented
# from the PLANNED numbers before the burst ran -- selCount and the capped press count -- which
# is an INTENT, not a reach. The presses can still be refused, the ring can still fail to fill,
# and the counter would say the seam was covered anyway. The fact is measured on the other side
# of the burst, in random-conformance-episodes.ps1: a building whose LOGICAL queue came out past
# the engine's five, with more than one building selected. `Reached` is that; `Planned` is kept
# beside it because the two disagreeing is itself worth seeing.
$script:groupOverflowPlanned = 0
$script:groupOverflowReached = 0
# DEFAULTS TO FAILURE. The verdict block sets this from Get-ScConformanceVerdict; a run that
# never reaches it -- killed inside the finally, the process torn down -- exits non-zero
# rather than 0, because "the script stopped before it could judge itself" is not a pass.
$script:exitCode = 1

function Assert-Inv {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$What,
        [Parameter(Mandatory)][bool]$Ok,
        [string]$Detail = ''
    )
    $script:checks++
    $script:covered[$Id] = $true
    $where = "ep$($script:episodeNo)"
    if ($Ok) {
        Write-Host "    ok   [$Id] $What"
    } else {
        Write-Host "    FAIL [$Id/$where] $What $Detail"
        $script:failures += [pscustomobject]@{
            Id = $Id; Episode = $script:episodeNo; What = $What; Detail = $Detail
        }
    }
}

function Note { param([string]$Text) Write-Host "         $Text" }

function Write-Skip {
    param([string]$Id, [string]$Why)
    Write-Host "    skip [$Id] $Why"
    $script:skipped += "[$Id] ep$($script:episodeNo): $Why"
}

# ---------------------------------------------------------------------------
# THE LOG TAIL. Every earlier suite re-reads the whole log for every oracle read; over a
# forty-episode sweep that is quadratic and it is the reason a long run "hangs". This
# keeps a byte position and a residue for the partial last line, so each read costs only
# the bytes the plugin has written since the previous one.
# ---------------------------------------------------------------------------
$script:logPos = 0
$script:logResidue = ''
$script:logLines = [System.Collections.Generic.List[string]]::new()

function Update-ScLogTail {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $fs = $null
    try {
        $fs = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        if ($fs.Length -lt $script:logPos) {
            # Truncated or replaced under us. Start again rather than read garbage.
            $script:logPos = 0; $script:logResidue = ''; $script:logLines.Clear()
        }
        if ($fs.Length -eq $script:logPos) { return }
        $fs.Position = $script:logPos
        $count = [int]($fs.Length - $script:logPos)
        $buf = [byte[]]::new($count)
        $read = $fs.Read($buf, 0, $count)
        $script:logPos += $read
        $text = $script:logResidue + [Text.Encoding]::UTF8.GetString($buf, 0, $read)
        $parts = $text -split "`r?`n"
        $script:logResidue = $parts[-1]
        for ($i = 0; $i -lt $parts.Count - 1; $i++) { [void]$script:logLines.Add($parts[$i]) }
    }
    finally { if ($fs) { $fs.Dispose() } }
}

function Get-ScLogMark {
    Update-ScLogTail -Path $LogPath
    $script:logLines.Count
}

function Get-ScLogSince {
    param([int]$Mark)
    Update-ScLogTail -Path $LogPath
    if ($Mark -ge $script:logLines.Count) { return @() }
    $script:logLines.GetRange($Mark, $script:logLines.Count - $Mark)
}

# ---------------------------------------------------------------------------
# THE ORACLE. One marker, every read-only dump the plugin is configured for, ONE instant.
#
# The plugin answers a marker change by writing every subsystem's state (scplugin.cpp
# PollMarker), so a single handshake returns the building memory, the engine's unit lists,
# the card, the status strip and the indicator for the same moment -- rather than five
# reads of five different moments that a test would then have to pretend were one.
#
# It waits for the SUMMARY line of each subsystem it needs. Each of those is written LAST
# and written unconditionally, so waiting for it means the whole answer has landed AND an
# empty answer is still an answer (AGENTS.md, absence assertions).
# ---------------------------------------------------------------------------
$markerPath = Join-Path (Split-Path $LogPath -Parent) 'marker.txt'
$script:oracleSeq = 0

function Read-Engine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Tag,
        [string[]]$Need = @('prodq', 'prodfan', 'world'),
        [int]$TimeoutSec = 30
    )
    $script:oracleSeq++
    $label = "rc-$Tag-$script:oracleSeq"
    $mark = Get-ScLogMark
    Set-ScMarker -MarkerPath $markerPath -Label $label
    $esc = [regex]::Escape($label)
    $want = @{
        prodq   = "PRODQ \[$esc\] buildings=\d+ max="
        prodfan = "PRODFAN \[$esc\] buildings=\d+ selected="
        world   = "WORLD \[$esc\] p=7 units="
        card    = "CARD \[$esc\] (slots=\d+ shown=|dialog=0)"
        statq   = "STATQ \[$esc\] (.*slots=\d+ shown=|dialog=0)"
        qind    = "QIND \[$esc\] (mode=|dialog=0)"
    }
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $lines = @(Get-ScLogSince -Mark $mark)
        $have = $true
        foreach ($n in $Need) {
            if (-not $want.ContainsKey($n)) { throw "test: unknown oracle '$n'" }
            if (@($lines | Select-String -Pattern $want[$n]).Count -eq 0) { $have = $false; break }
        }
        if ($have) { return ConvertFrom-EngineLines -Lines $lines -Label $label }
        Start-Sleep -Milliseconds 200
    }
    throw ("test: the plugin did not answer marker '$label' with [{0}] within ${TimeoutSec}s (log: $LogPath). " -f ($Need -join ' ')) +
          'Was the game launched with -WorldScan 1 -CardScan 1 -ProdQueue 1 -ProdFan 1 -QueueIndicator 1?'
}

function ConvertFrom-EngineLines {
    param([Parameter(Mandatory)]$Lines, [Parameter(Mandatory)][string]$Label)
    $esc = [regex]::Escape($Label)
    $o = [pscustomobject]@{
        Label = $Label
        # PRODFAN: one row per SELECTED building, tracked by the plugin or not.
        Rows = @(); Buildings = 0; SimSlots = -1; ClientCount = -1
        TotalQueued = 0; Minerals = -1; Gas = -1; Fanned = 0; Reached = 0
        # PRODQ: one row per building the plugin is HOLDING items for.
        Tracked = @{}; TrackedCount = 0; Captured = 0; Promoted = 0
        Cancelled = 0; Refunded = 0; RefusedFull = 0
        TrainSeen = -1; TrainNoUnit = -1
        # WORLD: the engine's per-player unit lists.
        Units = @(); Screen = $null; Counts = @{}
        # CARD / STATQ / QIND.
        Card = $null; Cancel = $null; CardSlots = @()
        Status = $null
        Qind = $null
        Lines = @($Lines)
    }
    foreach ($l in $Lines) {
        $t = "$l"
        if ($t -notmatch "\[$esc\]") { continue }

        $m = [regex]::Match($t, 'PRODFAN \[[^\]]+\] i=(\d+)/(\d+) unit=0x([0-9A-Fa-f]+) type=0x([0-9A-Fa-f]+) player=(\d+) head=(\d+) engineLen=(-?\d+) engine=\[([^\]]*)\] buildState=(\d+) buildUnit=0x([0-9A-Fa-f]+)(.*)$')
        if ($m.Success) {
            $o.Rows += [pscustomobject]@{
                Index = [int]$m.Groups[1].Value
                Unit = $m.Groups[3].Value
                Type = [Convert]::ToInt32($m.Groups[4].Value, 16)
                Player = [int]$m.Groups[5].Value
                EngineLen = [int]$m.Groups[7].Value
                Engine = @($m.Groups[8].Value -split ',' | Where-Object { $_ -match '^0x' } |
                           ForEach-Object { [Convert]::ToInt32(($_ -replace '^0x'), 16) })
                BuildState = [int]$m.Groups[9].Value
                BuildUnit = $m.Groups[10].Value
                Stale = ($m.Groups[11].Value -match 'STALE')
            }
            continue
        }
        $m = [regex]::Match($t, 'PRODFAN \[[^\]]+\] buildings=(\d+) selected=(\d+) visible=(\d+) simSlots=(-?\d+) clientCount=(\d+) totalQueued=(\d+) minerals=(\d+) gas=(\d+) enabled=(\d+) fanned=(\d+) refused=(\d+) reached=(\d+) lit=(\d+)')
        if ($m.Success) {
            $o.Buildings = [int]$m.Groups[1].Value
            $o.SimSlots = [int]$m.Groups[4].Value
            $o.ClientCount = [int]$m.Groups[5].Value
            $o.TotalQueued = [int]$m.Groups[6].Value
            $o.Minerals = [int]$m.Groups[7].Value
            $o.Gas = [int]$m.Groups[8].Value
            $o.Fanned = [int]$m.Groups[10].Value
            $o.Reached = [int]$m.Groups[12].Value
            continue
        }
        $m = [regex]::Match($t, 'PRODQ \[[^\]]+\] unit=0x([0-9A-Fa-f]+) player=(\d+) head=(\d+) engineLen=(\d+) engine=\[([^\]]*)\] overflow=(\d+) overflowTypes=\[([^\]]*)\] logical=(\d+) minerals=(\d+) gas=(\d+)')
        if ($m.Success) {
            $o.Tracked[$m.Groups[1].Value] = [pscustomobject]@{
                Unit = $m.Groups[1].Value
                EngineLen = [int]$m.Groups[4].Value
                Engine = @($m.Groups[5].Value -split ',' | Where-Object { $_ -match '^0x' } |
                           ForEach-Object { [Convert]::ToInt32(($_ -replace '^0x'), 16) })
                Overflow = [int]$m.Groups[6].Value
                Logical = [int]$m.Groups[8].Value
                Minerals = [int]$m.Groups[9].Value
            }
            continue
        }
        $m = [regex]::Match($t, 'PRODQ \[[^\]]+\] buildings=(\d+) max=(\d+) captured=(\d+) promoted=(\d+) cancelled=(\d+) refunded=(\d+) refusedFull=(\d+)')
        if ($m.Success) {
            $o.TrackedCount = [int]$m.Groups[1].Value
            $o.Captured = [int]$m.Groups[3].Value
            $o.Promoted = [int]$m.Groups[4].Value
            $o.Cancelled = [int]$m.Groups[5].Value
            $o.Refunded = [int]$m.Groups[6].Value
            $o.RefusedFull = [int]$m.Groups[7].Value
            $x = [regex]::Match($t, 'trainSeen=(\d+) trainNoUnit=(\d+)')
            if ($x.Success) { $o.TrainSeen = [int]$x.Groups[1].Value; $o.TrainNoUnit = [int]$x.Groups[2].Value }
            continue
        }
        $m = [regex]::Match($t, 'WORLD \[[^\]]+\] p=(\d+) i=(\d+) unit=0x([0-9A-Fa-f]+) owner=(\d+) type=0x([0-9A-Fa-f]+) hp=(-?\d+) order=0x([0-9A-Fa-f]+) order2=0x([0-9A-Fa-f]+) stim=(\d+) energy=(\d+) pos=\((\d+),(\d+)\) flags=0x([0-9A-Fa-f]+)')
        if ($m.Success) {
            $o.Units += [pscustomobject]@{
                Player = [int]$m.Groups[1].Value
                Unit = $m.Groups[3].Value
                Owner = [int]$m.Groups[4].Value
                Type = [Convert]::ToInt32($m.Groups[5].Value, 16)
                Hp = [int]$m.Groups[6].Value
                X = [int]$m.Groups[11].Value
                Y = [int]$m.Groups[12].Value
                Flags = [Convert]::ToUInt32($m.Groups[13].Value, 16)
            }
            continue
        }
        $m = [regex]::Match($t, "WORLD \[$esc\].*screen=\((\d+),(\d+)\)")
        if ($m.Success) {
            $o.Screen = [pscustomobject]@{ Left = [int]$m.Groups[1].Value; Top = [int]$m.Groups[2].Value }
            continue
        }
        $m = [regex]::Match($t, "WORLD \[$esc\] p=(\d+) units=(\d+) recount=(\d+) complete=(\d+)")
        if ($m.Success) {
            $o.Counts[[int]$m.Groups[1].Value] = [pscustomobject]@{
                Units = [int]$m.Groups[2].Value; Recount = [int]$m.Groups[3].Value
                Complete = [int]$m.Groups[4].Value
            }
            continue
        }
        $m = [regex]::Match($t, 'CARD \[[^\]]+\] slot=(\d+) (\S+) .*rect=\((-?\d+),(-?\d+),(-?\d+),(-?\d+)\).*cond=0x([0-9A-Fa-f]+) act=0x([0-9A-Fa-f]+)')
        if ($m.Success) {
            $entry = [pscustomobject]@{
                Slot = [int]$m.Groups[1].Value
                State = $m.Groups[2].Value
                Rect = @([int]$m.Groups[3].Value, [int]$m.Groups[4].Value,
                         [int]$m.Groups[5].Value, [int]$m.Groups[6].Value)
                Cond = $m.Groups[7].Value.ToLower()
                Act = $m.Groups[8].Value.ToLower()
            }
            $o.CardSlots += $entry
            if ($entry.Act -eq $TRAIN_ACTION) { $o.Card = $entry }
            elseif ($entry.Act -eq $CANCEL_ACTION) { $o.Cancel = $entry }
            continue
        }
        $m = [regex]::Match($t, 'QIND \[[^\]]+\] mode=(\d+) linked=(\d+) visible=(\d+) text="([^"]*)" bounds=\((-?\d+),(-?\d+),(-?\d+),(-?\d+)\) ink=(-?\d+) refInk=(-?\d+)')
        if ($m.Success) {
            # boxDiff is task 039's number and it is read SEPARATELY and OPTIONALLY on purpose:
            # it is being added to sc_queueind.cpp by that task while this one is being written,
            # so a plugin without it must make INV-Q SKIP with the reason printed rather than
            # silently parse as 0 -- 0 is the failing value ("our pixels equal the baseline"),
            # and a missing field that reads as a failure is how a harness reports someone
            # else's feature broken on the strength of a probe that never ran. $null here means
            # "the plugin never said", which is a different thing from every number.
            # BY NAME, never by position. 039 is inserting `surfInk` between `refId` and
            # `slotDiff` in the same commit that adds boxDiff, and both suites there parse this
            # line with one positional regex and both broke on the insertion. A named match
            # cannot break that way -- and it is also why the fields below are read as their
            # own matches rather than appended to the big one above.
            $bd = [regex]::Match($t, ' boxDiff=(-?\d+)')
            $si = [regex]::Match($t, ' surfInk=(-?\d+)')
            $o.Qind = [pscustomobject]@{
                Mode = [int]$m.Groups[1].Value
                Linked = ($m.Groups[2].Value -eq '1')
                Visible = ($m.Groups[3].Value -eq '1')
                Text = $m.Groups[4].Value
                Bounds = @([int]$m.Groups[5].Value, [int]$m.Groups[6].Value,
                           [int]$m.Groups[7].Value, [int]$m.Groups[8].Value)
                # DIAGNOSTIC ONLY, never asserted on -- see Invoke-IndicatorEpisode for the
                # measurement that says why.
                Ink = [int]$m.Groups[9].Value
                RefInk = [int]$m.Groups[10].Value
                BoxDiff = $(if ($bd.Success) { [int]$bd.Groups[1].Value } else { $null })
                SurfInk = $(if ($si.Success) { [int]$si.Groups[1].Value } else { $null })
                Line = $t
            }
            continue
        }
    }
    $o
}

# HOW MANY OF A TYPE THIS PLAYER HAS ACTUALLY BUILT.
#
# -Completed is not a refinement, it is the whole point. The engine LINKS a unit into its
# player's list the moment production starts and sets `SC_UNIT_FLAG_COMPLETED` (0x01) only when
# it finishes, so "how many SCVs exist" is not "how many have been built" (sc_addresses.h 175).
# Counting the raw list made this harness report 2 units built during a burst in which nothing
# had finished -- it was seeing the two under construction -- and that is task 031's bug
# exactly, which the header above that constant was written to prevent. Read it before
# changing this.
function Get-OwnedCount {
    param(
        [Parameter(Mandatory)]$Eng,
        [Parameter(Mandatory)][int]$Type,
        [int]$Player = 0,
        [switch]$Completed
    )
    @($Eng.Units | Where-Object {
        $_.Player -eq $Player -and $_.Type -eq $Type -and
        ((-not $Completed) -or (($_.Flags -band $UNIT_FLAG_COMPLETED) -ne 0))
    }).Count
}

# The LOGICAL queue of one building: the engine's own occupied slots (its memory) plus what
# the plugin is holding for it. The ring half is the oracle; the overflow half is the
# plugin's own bookkeeping and is only ever used to compute HEADROOM and to explain a
# number, never to evidence one.
function Get-Logical {
    param([Parameter(Mandatory)]$Eng, [Parameter(Mandatory)][string]$Unit)
    $row = @($Eng.Rows | Where-Object { $_.Unit -eq $Unit }) | Select-Object -First 1
    $trk = $Eng.Tracked[$Unit]
    $ring = if ($row) { $row.EngineLen } elseif ($trk) { $trk.EngineLen } else { -1 }
    if ($row -and $trk -and $row.EngineLen -ne $trk.EngineLen) {
        Assert-Inv -Id 'INV-R' -Ok $false `
            -What "the two reads of 0x$Unit's own ring agree" `
            -Detail "(PRODFAN $($row.EngineLen) / PRODQ $($trk.EngineLen))"
    }
    $ov = if ($trk) { $trk.Overflow } else { 0 }
    [pscustomobject]@{
        Unit = $Unit; Ring = $ring; Overflow = $ov; Logical = $ring + $ov
        Engine = if ($row) { $row.Engine } elseif ($trk) { $trk.Engine } else { @() }
        Tracked = ($null -ne $trk)
    }
}

# ---------------------------------------------------------------------------
# Fixture. ONE FOLDER PER TASK, ONE NAME PER SUITE (AGENTS.md hard rule).
# ---------------------------------------------------------------------------
if (-not $FixtureDir) { $FixtureDir = Resolve-ScFixtureDir -GameDir $GameDir -Fallback '00-t041' }
$mapName = 'random-conformance.scx'
$mapPath = Join-Path $FixtureDir $mapName
$fixtures = New-ScFixtureRun -Dir $FixtureDir -Names @($mapName)

$exePath = Join-Path $GameDir 'StarCraft.exe'
if (-not (Test-Path -LiteralPath $exePath)) { throw "test: $exePath not found." }
$PRISTINE_SHA256 = 'AD6B58B27B8948845CCFA69BCFCC1B10D6AA7A27A371EE3E61453925288C6A46'
$hashBefore = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash

New-Item -ItemType Directory -Path (Split-Path $LogPath -Parent) -Force | Out-Null
if (Test-Path -LiteralPath $LogPath) { Remove-Item -LiteralPath $LogPath -Force }
if (Test-Path -LiteralPath $markerPath) { Remove-Item -LiteralPath $markerPath -Force }
New-Item -ItemType Directory -Path $ShotDir -Force | Out-Null

$gamePid = 0
$hwnd = [IntPtr]::Zero
$launchLock = $null
$shotN = 0
$runStart = Get-Date

# A frame of whatever is on screen, named for the STATE it is rather than for its position in
# the run -- `frame-007.png` is not a thing anyone can ask for. The path is PRINTED, because the
# frame itself can never leave this machine (hard rule 1) and the path is therefore the whole
# deliverable: the conductor hands it to the user, who opens it locally.
function Shot([string]$tag) {
    if ($script:hwnd -eq [IntPtr]::Zero) { return $null }
    $script:shotN++
    $path = Join-Path $ShotDir ("{0:d2}-{1}-seed{2}.png" -f $script:shotN, $tag, $Seed)
    Save-ScWindowImage -Hwnd $script:hwnd -Path $path -FullWindow | Out-Null
    Write-Host "    frame [$tag] $path"
    $script:frames += $path
    $path
}

function Step {
    param([string]$Name, [scriptblock]$Body)
    Write-Host ''
    Write-Host "== $Name"
    & $Body
}

# ---------------------------------------------------------------------------
# Selecting things. Positions come from the engine's own unit list, never from a
# screenshot (AGENTS.md, task 026) -- client = map - viewport is the arithmetic the
# engine's own click handler at 0x0046FB40 does.
# ---------------------------------------------------------------------------
function Move-CameraTo {
    param([Parameter(Mandatory)]$Units, [int]$MapW = 128, [int]$MapH = 96)
    $tx = [int](((($Units | Measure-Object X -Average).Average)) / 32)
    $ty = [int](((($Units | Measure-Object Y -Average).Average)) / 32)
    $p = Get-ScMinimapPoint -MapTilesW $MapW -MapTilesH $MapH -TileX $tx -TileY $ty
    Send-ScClick -Hwnd $script:hwnd -X $p.X -Y $p.Y
    Start-Sleep -Milliseconds 700
}

# Drag a rectangle around exactly these units, and REFUSE if anything else falls inside it.
# Task 025's first run boxed the play area and the engine handed back a neutral mineral
# field; here the hazard is the suite's own SCVs, which appear next to a Command Center the
# moment one finishes. Returning $false is a legitimate outcome the caller reports, not an
# error to swallow.
function Select-ByBox {
    param([Parameter(Mandatory)]$Targets, [Parameter(Mandatory)]$World, [int]$Margin = 24)
    if (-not $World.Screen) { throw 'test: the plugin did not report the viewport origin.' }
    $x1 = ($Targets | Measure-Object X -Minimum).Minimum - $World.Screen.Left - $Margin
    $x2 = ($Targets | Measure-Object X -Maximum).Maximum - $World.Screen.Left + $Margin
    $y1 = ($Targets | Measure-Object Y -Minimum).Minimum - $World.Screen.Top - $Margin
    $y2 = ($Targets | Measure-Object Y -Maximum).Maximum - $World.Screen.Top + $Margin
    if ($x1 -lt 4 -or $y1 -lt 4 -or $x2 -gt 636 -or $y2 -gt 340) {
        Note "the rect [$x1,$y1]-[$x2,$y2] is not fully on the battlefield"
        return $false
    }
    $mine = @{}
    foreach ($u in $Targets) { $mine[$u.Unit] = $true }
    $intruders = @($World.Units | Where-Object {
        -not $mine.ContainsKey($_.Unit) -and
        ($_.X - $World.Screen.Left) -ge $x1 -and ($_.X - $World.Screen.Left) -le $x2 -and
        ($_.Y - $World.Screen.Top) -ge $y1 -and ($_.Y - $World.Screen.Top) -le $y2
    })
    if ($intruders.Count -gt 0) {
        Note "the rect would also catch $($intruders.Count) other unit(s): $(($intruders | ForEach-Object { 'p{0}/0x{1:x}' -f $_.Owner, $_.Type } | Select-Object -Unique) -join ' ')"
        return $false
    }
    Send-ScDrag -Hwnd $script:hwnd -X1 $x1 -Y1 $y1 -X2 $x2 -Y2 $y2 -Steps 20
    Start-Sleep -Milliseconds 900
    return $true
}

function Select-ByClick {
    param([Parameter(Mandatory)]$Target, [Parameter(Mandatory)]$World)
    $cx = $Target.X - $World.Screen.Left
    $cy = $Target.Y - $World.Screen.Top
    if ($cx -lt 0 -or $cx -ge 640 -or $cy -lt 0 -or $cy -ge 340) {
        Note "building 0x$($Target.Unit) is off the battlefield at ($cx,$cy)"
        return $false
    }
    Send-ScClick -Hwnd $script:hwnd -X $cx -Y $cy
    Start-Sleep -Milliseconds 800
    return $true
}

# ---------------------------------------------------------------------------
try {
    Step "fixture: $Buildings Command Centers, $Depots supply depots, SCV build time ${BuildTimeSec}s" {
        Wait-ScFixtureFolderFree -Run $fixtures
        # 160 px (5 tiles) apart: a Command Center is 4x3 tiles, so this clears it with a
        # tile to spare and the whole block still fits inside one screen's battlefield --
        # which is what makes a single drag box able to hold any sub-rectangle of it.
        # The depots go on the generator's second block, -DepotOffsetX px EAST, owned by the
        # same player: far outside every drag rectangle, and there only for their supply.
        $genArgs = @{
            UnitCount = $Buildings; UnitType = 'command-center'; Player = 0
            ClearPlayerUnits = $true; GridSpacing = 160
            StartingMinerals = $StartingMinerals; StartingGas = $StartingGas
            UnitBuildTime = @("scv=$BuildTimeSec")
            OutputPath = $mapPath
        }
        if ($Depots -gt 0) {
            $genArgs.EnemyCount = $Depots
            $genArgs.EnemyType = 'supply-depot'
            $genArgs.EnemyOwner = 'player'
            $genArgs.EnemySpacing = 96
            $genArgs.EnemyOffsetX = $DepotOffsetX
        }
        $gen = & (Join-Path $repoRoot 'tools/make-test-map.ps1') @genArgs 2>&1
        $gen | ForEach-Object { Note "$_" }
        Assert-Inv -Id 'FIXTURE' -What 'the generator succeeded' -Ok ($LASTEXITCODE -eq 0) -Detail "(exit $LASTEXITCODE)"
        Assert-Inv -Id 'FIXTURE' -What 'it wrote the map' -Ok (Test-Path -LiteralPath $mapPath)
        Assert-Inv -Id 'FIXTURE' -What 'its structural validation passed' `
            -Ok (@($gen | Select-String -Pattern '^OK: ').Count -gt 0)
        Assert-Inv -Id 'FIXTURE' -What 'the working copy is byte-identical to pristine 1.16.1' `
            -Ok ($hashBefore -eq $PRISTINE_SHA256) -Detail "(got $hashBefore)"
    }

    Assert-ScFixtureStillMine -Run $fixtures -MapPath $mapPath
    Wait-ScNoGameRunning
    $launchLock = Enter-ScLaunchLock -TaskId '041-random-conformance' -TimeoutMinutes $LockTimeoutMinutes

    $runArgs = @{
        Mode = 'fanout'; LogCommands = '1'; Circles = '0'; HudRow = '0'
        WorldScan = '1'; CardScan = '1'; BuildingGroups = '1'
        ProdQueue = '1'; ProdQueueMax = $QueueMax; ProdFan = '1'; QueueIndicator = '1'
        UpgradeQueue = '1'
        InjectWindowedHelper = 'WMode'; NoLaunchLock = $true
        GameDir = $GameDir; LogPath = $LogPath
    }
    if ($BuildDir) { $runArgs.BuildDir = $BuildDir }
    & (Join-Path $scriptDir 'run-with-plugin.ps1') @runArgs 6>&1 | ForEach-Object {
        Write-Host $_
        if ("$_" -match 'scinject:\s*PID=(\d+)') { $script:gamePid = [int]$Matches[1] }
    }
    if (-not $gamePid) { throw 'test: could not parse the game pid from scinject output.' }
    $hwnd = Get-ScGameWindow -ProcessId $gamePid

    Step 'every hook this run depends on is spliced' {
        $log = @(Get-ScLogSince -Mark 0)
        Assert-Inv -Id 'ARM' -What "the production queue is enabled at max=$QueueMax" `
            -Ok (@($log | Select-String -Pattern "PRODQ config: enabled max=$QueueMax ").Count -gt 0)
        Assert-Inv -Id 'ARM' -What 'the group fan-out reports itself ENABLED' `
            -Ok (@($log | Select-String -Pattern 'PRODFAN: ENABLED').Count -gt 0)
        $prodq = @($log | Select-String -Pattern 'HOOK (cmdrecvTrain|cmdrecvCancelTrain|productionTick): installed at')
        Assert-Inv -Id 'ARM' -What "all three production detours are spliced ($($prodq.Count))" -Ok ($prodq.Count -eq 3)
        Assert-Inv -Id 'ARM' -What 'the command funnel is hooked, so every command is logged' `
            -Ok (@($log | Select-String -Pattern 'HOOK queueCommand: installed at').Count -ge 1)
        Assert-Inv -Id 'ARM' -What "the Train button's condition is detoured, so a group gets a button" `
            -Ok (@($log | Select-String -Pattern 'HOOK btnTrainCondition: installed at').Count -ge 1)
    }

    Step "menus: Single Player -> Expansion -> Play Custom -> $mapName" {
        Start-Sleep -Seconds 2
        Send-ScClick -Hwnd $hwnd -X 215 -Y 119        # Single Player
        Send-ScClick -Hwnd $hwnd -X 373 -Y 300        # StarCraft: Brood War (Expansion)
        Start-Sleep -Seconds 1
        Send-ScClick -Hwnd $hwnd -X 75 -Y 111         # first entry in the Registry list
        Send-ScClick -Hwnd $hwnd -X 516 -Y 392        # Ok
        Start-Sleep -Seconds 2
        Send-ScClick -Hwnd $hwnd -X 327 -Y 415        # Play Custom
        Start-Sleep -Seconds 2
        Assert-ScFixtureStillMine -Run $fixtures -MapPath $mapPath
        Select-ScBrowserMap -Hwnd $hwnd -GameDir $GameDir -MapPath $mapPath | Out-Null
        Set-ScGameType -Hwnd $hwnd -LogPath $LogPath -Index 2      # Use Map Settings
        Send-ScClick -Hwnd $hwnd -X 516 -Y 393        # Ok -> mission briefing
        Start-Sleep -Seconds 6
        Send-ScClick -Hwnd $hwnd -X 544 -Y 387        # Start
        Start-Sleep -Seconds 10
        Dismiss-ScTipsDialog -Hwnd $hwnd -LogPath $LogPath | Out-Null
        Start-Sleep -Seconds 2
        Shot 'in-game'
    }

    $script:ccs = @()
    $script:supplyMax = 0
    Step 'the fixture spawned what the plan assumes' {
        $w = Read-Engine -Tag 'spawned' -Need @('world')
        $mine = @($w.Units | Where-Object { $_.Player -eq 0 })
        $ccs = @($mine | Where-Object { $_.Type -eq $CC_TYPE } | Sort-Object Y, X)
        # $depotUnits, NOT $depots: PowerShell variable names are CASE-INSENSITIVE, so a local
        # `$depots` IS the `-Depots` parameter. The first version of this line wrote the unit
        # list over the count and then compared the count against it -- the assertion failed on
        # a fixture that was perfectly correct, and printed "and <twelve blanks> supply depots
        # (12)", which is the sort of diagnostic that costs an hour (AGENTS.md, task 030: your
        # diagnostics are under the same rule as your assertions).
        $depotUnits = @($mine | Where-Object { $_.Type -eq $DEPOT_TYPE })
        Assert-Inv -Id 'FIXTURE' -What "player 0 owns exactly $Buildings Command Centers ($($ccs.Count))" -Ok ($ccs.Count -eq $Buildings)
        Assert-Inv -Id 'FIXTURE' -What "and $Depots supply depots ($($depotUnits.Count))" -Ok ($depotUnits.Count -eq $Depots)
        Assert-Inv -Id 'FIXTURE' -What 'the world scan was not taken mid-edit' `
            -Ok ($w.Counts[0].Units -eq $w.Counts[0].Recount -and $w.Counts[0].Complete -eq 1)
        $script:ccs = $ccs
        $script:supplyMax = [math]::Min(200, $ccs.Count * $CC_SUPPLY + $depotUnits.Count * $DEPOT_SUPPLY)
        Note "supply ceiling for this fixture: $($script:supplyMax) (the engine's own cap is 200)"
        # The plan indexes buildings 0..N-1 in the generator's OWN row-major order, which
        # is what makes a plan's "members=[0 1]" mean the same two buildings on a replay.
        for ($i = 0; $i -lt $ccs.Count; $i++) { Note ("building {0} = 0x{1} at map ({2},{3})" -f $i, $ccs[$i].Unit, $ccs[$i].X, $ccs[$i].Y) }
    }

    if ($script:ccs.Count -ne $Buildings) {
        throw "test: the fixture produced $($script:ccs.Count) Command Centers, not $Buildings -- nothing below would mean anything."
    }

    # -----------------------------------------------------------------------
    # CONTROL GROUPS, assigned once, before a single SCV exists.
    #
    # This is not only coverage of task 036's feature -- it is what makes the rest of the
    # run possible. A drag box catches whatever is standing in the rectangle, and from the
    # first completed SCV onward that includes SCVs. A recall selects exactly the units
    # that were stored, whatever has since parked next to them.
    # -----------------------------------------------------------------------
    Step 'assign a control group to every subset the plan uses' {
        $w = Read-Engine -Tag 'groups' -Need @('world')
        Move-CameraTo -Units $script:ccs
        foreach ($s in $plan.subsets) {
            if ($s.group -le 0) { continue }
            $targets = @($s.members | ForEach-Object { $script:ccs[$_] })
            $w2 = Read-Engine -Tag "grp$($s.group)" -Need @('world')
            $ok = if ($targets.Count -eq 1) { Select-ByClick -Target $targets[0] -World $w2 }
                  else { Select-ByBox -Targets $targets -World $w2 }
            if (-not $ok) {
                Write-Skip -Id 'SETUP' -Why "could not box subset [$($s.members -join ' ')] for group $($s.group)"
                continue
            }
            $e = Read-Engine -Tag "grpchk$($s.group)" -Need @('prodfan')
            if ($e.Buildings -ne $targets.Count) {
                Write-Skip -Id 'SETUP' -Why "boxing subset [$($s.members -join ' ')] selected $($e.Buildings), not $($targets.Count) -- group $($s.group) not assigned"
                continue
            }
            Send-ScControlGroupAssign -Hwnd $hwnd -Group $s.group
            Note "group $($s.group) <- buildings [$($s.members -join ' ')] ($($e.Buildings) selected)"
        }
    }

    # -----------------------------------------------------------------------
    # THE EPISODES
    # -----------------------------------------------------------------------
    $script:builtBaseline = 0
    foreach ($ep in $plan.episodes) {
        $script:episodeNo = $ep.index
        # ENTERED, not run. The four `continue` paths below can all fire before this episode
        # asserts anything; `episodesActed` is incremented at the dispatch (issue #68).
        $script:episodesEntered++
        Write-Host ''
        Write-Host ("---- episode {0}/{1}: {2}  select={3} members=[{4}] presses={5} ----" -f `
            $ep.index, $plan.episodes.Count, $ep.kind, $ep.selectMode, ($ep.members -join ' '), $ep.presses)

        # --- SELECT ---------------------------------------------------------
        $w = Read-Engine -Tag "ep$($ep.index)-look" -Need @('world')
        $targets = @($ep.members | ForEach-Object { $script:ccs[$_] })
        $mode = $ep.selectMode
        $selected = $false
        if ($mode -eq 'group' -and $ep.group -gt 0) {
            Send-ScControlGroupRecall -Hwnd $hwnd -Group $ep.group
            Start-Sleep -Milliseconds 500
            $selected = $true
        }
        if (-not $selected -and $mode -eq 'box') {
            Move-CameraTo -Units $targets
            $w = Read-Engine -Tag "ep$($ep.index)-aim" -Need @('world')
            $selected = Select-ByBox -Targets $targets -World $w
            if (-not $selected -and $ep.group -gt 0) {
                # The box was spoiled -- almost always by this run's own SCVs standing in
                # the rectangle. Fall back to the group and SAY SO, because "it selected by
                # a different path than the plan said" is exactly the kind of quiet
                # substitution that makes a green run unreadable.
                Note "falling back to control group $($ep.group)"
                Send-ScControlGroupRecall -Hwnd $hwnd -Group $ep.group
                Start-Sleep -Milliseconds 500
                $mode = 'group(fallback)'
                $selected = $true
            }
        }
        if (-not $selected -and $mode -eq 'click') {
            Move-CameraTo -Units $targets
            $w = Read-Engine -Tag "ep$($ep.index)-aim" -Need @('world')
            $selected = Select-ByClick -Target $targets[0] -World $w
        }
        if (-not $selected) {
            Write-Skip -Id 'SELECT' -Why "episode $($ep.index) could not select [$($ep.members -join ' ')] by $($ep.selectMode)"
            continue
        }

        $before = Read-Engine -Tag "ep$($ep.index)-before" -Need @('prodq', 'prodfan', 'world', 'card')
        $selCount = $before.Buildings
        Note "selected $selCount building(s) by $mode; simSlots=$($before.SimSlots) clientCount=$($before.ClientCount) minerals=$($before.Minerals)"

        if ($selCount -lt 1) {
            Write-Skip -Id 'SELECT' -Why "the engine reports nothing selected after a $mode selection"
            continue
        }

        # INV-S -- the two selection arrays, on task 038's exact seam. The simulation holds
        # ONE building at a time (that is what makes the receive handlers' single-unit gate
        # accept at all) while the client holds the whole group; a plugin that reads the
        # wrong one is right only while those two agree.
        Assert-Inv -Id 'INV-S' -What "the engine's client selection count matches the selection ($($before.ClientCount) vs $selCount)" `
            -Ok ($before.ClientCount -eq $selCount)
        Assert-Inv -Id 'INV-S' -What "the simulation holds one building at a time (simSlots=$($before.SimSlots))" `
            -Ok ($before.SimSlots -eq 1)
        $wrong = @($before.Rows | Where-Object { $_.Type -ne $CC_TYPE -or $_.Player -ne 0 })
        Assert-Inv -Id 'INV-S' -What 'every selected unit is a Command Center owned by player 0' -Ok ($wrong.Count -eq 0)
        $stale = @($before.Rows | Where-Object { $_.Stale })
        Assert-Inv -Id 'INV-S' -What 'no selected building went stale under the selection' -Ok ($stale.Count -eq 0)

        $units = @($before.Rows | ForEach-Object { $_.Unit })
        $mineralsBefore = $before.Minerals
        $scvBefore = @($before.Units | Where-Object { $_.Player -eq 0 -and $_.Type -eq $SCV_TYPE }).Count
        $supplyUsed = $scvBefore * $SCV_SUPPLY

        # --- HEADROOM, read from the game rather than guessed offline -------
        $headroom = $QueueMax
        foreach ($u in $units) {
            $l = Get-Logical -Eng $before -Unit $u
            $headroom = [math]::Min($headroom, $QueueMax - $l.Logical)
        }
        $supplyRoom = $script:supplyMax - $supplyUsed
        $presses = [int]$ep.presses
        $capped = [math]::Max(0, [math]::Min($presses, $headroom))
        if ($capped -ne $presses) { Note "presses $presses -> $capped (queue headroom $headroom)" }
        if ($supplyRoom -lt ($capped * $selCount)) {
            Write-Skip -Id 'SUPPLY' -Why "the fixture is out of supply room ($supplyRoom left, $($capped * $selCount) wanted) -- not a failure, an exhausted fixture"
            continue
        }
        if ($capped -lt 1 -and $ep.kind -ne 'indicator') {
            Write-Skip -Id 'QUEUE' -Why "every selected building is at the plugin's cap of $QueueMax"
            continue
        }

        # The INTENT: what this episode is about to try. Kept, and printed beside the reach,
        # because "it meant to and did not" is a different diagnosis from "it never meant to"
        # -- but it is not the coverage number and no longer pretends to be (issue #68).
        if ($selCount -gt 1 -and $capped -gt $ENGINE_SLOTS) { $script:groupOverflowPlanned++ }

        # --- ACT + ASSERT ---------------------------------------------------
        # PAST EVERY SKIP. Anything above this line can `continue`; nothing below can, so this
        # is the first point at which the episode is certain to assert something.
        $script:episodesActed++
        # No silent default. A kind with no driver used to land in Invoke-QueueEpisode and be
        # reported as a pass for whatever profile asked for it (issue #68). The refusal before
        # the launch catches this for a whole plan; this catches a plan mutated after that
        # check, and it throws into the RUN catch, which records it as a failure rather than
        # letting it unwind past the verdict.
        # (PowerShell's switch has no fall-through, so the queue kinds are one condition
        # rather than five stacked labels.)
        switch ($ep.kind) {
            'indicator' { Invoke-IndicatorEpisode -Ep $ep -Unit $units[0] -Before $before }
            { $QUEUE_EPISODE_KINDS -contains $_ } {
                Invoke-QueueEpisode -Ep $ep -Units $units -Presses $capped -Before $before -SelCount $selCount
            }
            default { throw "no episode driver for kind '$($ep.kind)' (episode $($ep.index)). Implemented: $($IMPLEMENTED_KINDS -join ', ')." }
        }

        Start-Sleep -Milliseconds ([int]$ep.settleMs)
    }

    Shot 'end'
    $script:finished = $true
}
catch {
    # CAUGHT, not left to unwind. An exception that propagates past this point terminates the
    # script before its own `exit`, and under `| Tee-Object` (which every run of this uses, to
    # keep a transcript) the pipeline then reports success -- so a crashed run looked green
    # from the outside. Recording it as a failure keeps the verdict, the exit code and the
    # transcript telling the same story.
    $script:failures += [pscustomobject]@{
        Id = 'RUN'; Episode = $script:episodeNo
        What = 'the run threw and did not finish its episodes'
        Detail = "($($_.Exception.Message))"
    }
    Write-Host ''
    Write-Host "    FAIL [RUN/ep$($script:episodeNo)] the run threw: $($_.Exception.Message)"
    Write-Host ($_.ScriptStackTrace)
}
finally {
    # THE GAME CLOSES FIRST, and the results print after -- deliberately in that order.
    # close-game.ps1 sends WM_CLOSE so the plugin's DETACH path runs and writes its stats
    # line, which the ledger below prints. Printing the verdict before the game had written
    # its last word would lose it.
    if ($gamePid -and -not $KeepOpen) {
        & (Join-Path $scriptDir 'close-game.ps1') -ProcessId $gamePid 6>&1 | ForEach-Object { Write-Host $_ }
        Start-Sleep -Seconds 2
    }

    # INV-P USED TO BE ASSERTED HERE, off the plugin's own mineralsSpent/gasSpent counters,
    # and it was labelled a self-check because that is what it was. Task 055 deleted those
    # counters (issue #66) after measuring that a build which really did spend the player's
    # money left both of them reading 0 while 28 balance assertions failed.
    #
    # The claim did not go with them. It is INV-M's, asserted once per episode against the
    # ENGINE's own per-player mineral global -- `the engine charged for every one of the N
    # items and no more` -- which is exactly the assertion a plugin spend breaks, and the
    # only one that can. A run-level duplicate that could only ever restate the plugin's own
    # bookkeeping is the defect this harness exists to find, so it is not replaced in kind.
    #
    # The ledger line is still PRINTED, because its live fields (captured/promoted/refunded/
    # mineralsRefunded) are how a double refund or a swallowed item is read afterwards.
    $script:episodeNo = 0
    $tail = @(Get-ScLogSince -Mark 0)
    $stats = @($tail | Select-String -Pattern 'PRODQSTATS ') | Select-Object -Last 1
    if ($stats) {
        Write-Host ''
        Write-Host "== the plugin's own ledger (printed, not asserted -- see INV-M for the money)"
        Note $stats.Line.Trim()
    }

    $elapsed = (Get-Date) - $runStart
    Write-Host ''
    Write-Host '================ RESULT ================'
    Write-Host ("seed        : {0}" -f $Seed)
    Write-Host ("plan hash   : {0}" -f $planHash)
    Write-Host ("profile     : {0}   episodes: {1}   buildings: {2}" -f $Profile, $Episodes, $Buildings)
    Write-Host ("checks      : {0}" -f $script:checks)
    # ACTED, then entered. The first number is the one that means anything: an episode that
    # skipped before acting asserted nothing, and printing only "6 of 6" is how a run with
    # six skips read as a full one (issue #68).
    Write-Host ("episodes    : {0} acted, {1} entered, {2} planned{3}" -f `
                $script:episodesActed, $script:episodesEntered, $plan.episodes.Count,
                $(if ($script:finished) { '' } else { '   <-- THE RUN DID NOT FINISH' }))
    if ($script:episodesEntered -gt $script:episodesActed) {
        Write-Host ("              {0} episode(s) skipped before acting -- see SKIPPED below" -f `
                    ($script:episodesEntered - $script:episodesActed))
    }
    Write-Host ("wall clock  : {0:mm\:ss}" -f $elapsed)
    if ($script:skipped.Count -gt 0) {
        Write-Host ''
        Write-Host "SKIPPED ($($script:skipped.Count)) -- a skipped check is NOT a passed check:"
        $script:skipped | ForEach-Object { Write-Host "  $_" }
    }

    # The frames, listed by PATH. They are the user's standing rule (2026-08-12) and they can
    # never be attached to anything -- a game frame reproduces game artwork (hard rule 1) -- so
    # the path IS the delivery: it goes in the PR body and the conductor hands it on.
    if ($script:frames.Count -gt 0) {
        Write-Host ''
        Write-Host "FRAMES ($($script:frames.Count)) -- open locally; never committed, never attached (hard rule 1):"
        $script:frames | ForEach-Object { Write-Host "  $_" }
    }

    # WHAT THIS RUN DID NOT COVER. Printed on every run, pass or fail: a green result that
    # quietly skipped a feature is the exact failure this task exists to prevent.
    # INV-P was retired with the counter it read (issue #66); INV-M carries its claim.
    $allInv = @('INV-W', 'INV-R', 'INV-M', 'INV-B', 'INV-S', 'INV-Q')
    $missing = @($allInv | Where-Object { -not $script:covered.ContainsKey($_) })
    Write-Host ''
    Write-Host "COVERAGE  asserted: $(@($allInv | Where-Object { $script:covered.ContainsKey($_) }) -join ' ')"
    if ($missing.Count -gt 0) { Write-Host "          NOT asserted by this run: $($missing -join ' ')" }
    # The seam, named. A green run that never got here has not tested the thing this harness
    # was built for, and saying "0 episodes" is the difference between evidence and a rumour.
    Write-Host ("          seam reaches: {0} episode(s) drove a MULTI-BUILDING selection past the engine's {1} slots (planned: {2}) -- this is task 038's seam" -f `
                $script:groupOverflowReached, $ENGINE_SLOTS, $script:groupOverflowPlanned)
    if ($script:groupOverflowReached -eq 0) {
        Write-Host "          NO episode pushed a MULTI-BUILDING selection past the engine's $ENGINE_SLOTS slots."
        Write-Host "          A run that never does that CANNOT detect task 038's class of bug, whatever its verdict says."
        Write-Host '          Usually the queues were already full: pick a seed whose early episodes are group bursts, or raise -QueueMax.'
    } elseif ($script:groupOverflowPlanned -gt $script:groupOverflowReached) {
        Write-Host ("          NOTE {0} episode(s) planned to reach the seam and did not -- presses refused, or a ring that never filled." -f `
                    ($script:groupOverflowPlanned - $script:groupOverflowReached))
    }
    # Only `production` can reach this line: the other two profiles are refused before the
    # launch, because nothing implements their episode kinds (issue #68).
    Write-Host '          features NOT reached by this profile: sc_upgrades, sc_hudrow paging -- neither has an episode driver (issue #76)'

    Write-Host ''
    # THE VERDICT IS DECIDED IN ONE PLACE, conformance-verdict.ps1, and this block only
    # PRINTS what it returned. It used to be these four inline elseifs, which nothing could
    # exercise without launching StarCraft -- which is how two of its clauses came to be
    # missing for a whole task (issue #68): a run could skip every episode, or reach its
    # seam zero times, and still print PASS and exit 0 with the COVERAGE warning directly
    # above it. A warning nobody has to act on is a comment.
    $verdict = Get-ScConformanceVerdict -Finished $script:finished `
        -EpisodesEntered $script:episodesEntered -EpisodesActed $script:episodesActed `
        -SeamReached $script:groupOverflowReached -FailureCount $script:failures.Count `
        -EpisodesPlanned $plan.episodes.Count
    $script:exitCode = $verdict.ExitCode
    switch ($verdict.Clause) {
        'did-not-finish' {
            # NOT "PASS with a note". A run that stopped early has not tested the thing it
            # was asked to test, and the one word people read off the bottom of this output
            # has to say so on its own -- the transcript's last line is what gets pasted
            # into a PR.
            Write-Host "INCOMPLETE  $($verdict.Why); $($script:checks) checks ran and $($script:failures.Count) failed."
            Write-Host '            This is NOT a pass: the episodes that did not run asserted nothing.'
        }
        'nothing-acted' {
            Write-Host "INCOMPLETE  $($verdict.Why) -- none of them acted."
            Write-Host "            $($script:checks) checks ran; they are the fixture's, not the feature's."
            Write-Host '            This is NOT a pass. See SKIPPED above for which gate stopped each one.'
        }
        'failures' {
            Write-Host "FAIL  $($script:failures.Count) of $($script:checks) checks:"
            foreach ($f in $script:failures) {
                Write-Host ("  [{0}] episode {1}: {2} {3}" -f $f.Id, $f.Episode, $f.What, $f.Detail)
            }
            Write-Host ''
        }
        'seam-not-reached' {
            Write-Host "INCOMPLETE  $($verdict.Why)."
            Write-Host "            $($script:checks) checks passed, and not one of them could have failed for"
            Write-Host "            task 038's bug: below the engine's $ENGINE_SLOTS slots a buggy plugin behaves"
            Write-Host '            exactly like a correct one. Not a pass, and not a regression gate.'
            Write-Host '            Pick a seed whose early episodes are multi-building bursts, or raise -QueueMax.'
        }
        'pass' {
            Write-Host "PASS  $($script:checks) checks, 0 failures, $($script:episodesActed) episode(s) acted, $($script:groupOverflowReached) seam reach(es)."
        }
    }
    if ($verdict.ExitCode -ne 0) {
        Write-Host 'REPRODUCE THIS EXACT RUN:'
        Write-Host "  $reproCmd"
        if ($verdict.Clause -eq 'failures') {
            Write-Host "  (the plan it replays is $PlanOut, hash $planHash)"
        }
    }
    Write-Host '========================================'

    if ($launchLock) { Exit-ScLaunchLock -Lock $launchLock }
    if ($fixtures) {
        Remove-ScOwnFixture -Run $fixtures
        # -Dir, not -Run: the folder call takes a path because it removes the folder only if
        # it is EMPTY, which is a fact about the directory rather than about this run.
        Remove-ScOwnFixtureDir -Dir $fixtures.Dir
    }
    $hashAfter = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash
    if ($hashAfter -ne $hashBefore) {
        Write-Host "WARNING: StarCraft.exe changed on disk during this run ($hashBefore -> $hashAfter)"
    }
}

# THE SAME DECISION that printed the word above -- not a second copy of the rule. These were
# two independent expressions before, which is exactly how the exit code and the verdict word
# come to disagree. `$script:exitCode` defaults to 1 so a run that never reached the verdict
# block at all (the finally did not run, the process was killed inside it) cannot exit 0.
exit $script:exitCode
