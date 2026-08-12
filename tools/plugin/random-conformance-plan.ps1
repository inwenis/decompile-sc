#Requires -Version 7
<#
.SYNOPSIS
The PLAN half of the randomized conformance harness (task 041): a seeded, pure,
game-free generator of action sequences, and the deterministic PRNG behind it.

.DESCRIPTION
Split out of the runner on purpose. A random test whose failures cannot be replayed is a
rumour (task file, Context), and the only way to be sure a seed replays is for the plan to
be produced by something that touches nothing -- no game, no clock, no filesystem, no
ambient state. Everything in this file is a pure function of its arguments, so
`New-ScConformancePlan -Seed 12345` returns the same object on any machine, in any order,
before or after a game has run.

THE PRNG IS OURS ON PURPOSE. `System.Random` is seeded-deterministic today, but its
contract is "the sequence may change between .NET versions" for the parameterless form and
its seeded form has already been reimplemented once. A seed printed in a bug report has to
mean the same thing next year, so this uses SplitMix32 written out in full: eight lines,
no dependency, and the plan hash proves a replay matched.

WHAT AN EPISODE IS. One selection of buildings, some things done to it, and a read of the
engine afterwards. The parameter randomised hardest is the SIZE OF THE SELECTION, because
that is the axis both of this week's escaped bugs lived on:

  * task 038 -- `sc_prodqueue` read the client's `activePlayerSelection` where the engine
    gates on `playersSelections`. The two arrays agree whenever exactly ONE building is
    selected, which was every case in both suites.
  * task 037 -- `AnchorFor` had no case for the upgrade mode, so the indicator was composed
    and never anchored, while its test asked the composer directly.

A generator that always selected one building, or always selected all of them, would have
missed 038 exactly as the hand-written suites did.

.EXAMPLE
. ./tools/plugin/random-conformance-plan.ps1
New-ScConformancePlan -Seed 12345 -Episodes 6 -Profile production | ConvertTo-Json -Depth 8
#>

# ---------------------------------------------------------------------------
# SplitMix32. Deterministic, self-contained, and reproducible across runtimes.
# ---------------------------------------------------------------------------
class ScRng {
    [uint32]$State

    # WHY EVERY CONSTANT CARRIES AN `L`. PowerShell parses `0xFFFFFFFF` as the Int32 -1
    # and `0x9E3779B9` as a negative Int32 too, so the unsuffixed version of this code
    # silently computes something else entirely (and throws on the cast, which is the
    # lucky outcome). The `L` forces Int64 and the masks then mean what they say.
    ScRng([int]$seed) {
        # A seed of 0 is a legitimate seed and must not be special-cased into
        # something else, or `-Seed 0` in a bug report would replay a different plan
        # than the run that produced it.
        $this.State = [uint32]([uint64]([uint32]$seed) -band 0xFFFFFFFFL)
    }

    [uint32] Next() {
        $this.State = [uint32]((([uint64]$this.State + 0x9E3779B9L) -band 0xFFFFFFFFL))
        [uint64]$z = $this.State
        $z = ((($z -bxor ($z -shr 16)) * 0x85EBCA6BL) -band 0xFFFFFFFFL)
        $z = ((($z -bxor ($z -shr 13)) * 0xC2B2AE35L) -band 0xFFFFFFFFL)
        return [uint32](($z -bxor ($z -shr 16)) -band 0xFFFFFFFFL)
    }

    # Inclusive on both ends, so a caller writing 1..9 gets 1..9.
    [int] Range([int]$lo, [int]$hi) {
        if ($hi -lt $lo) { throw "ScRng.Range: hi ($hi) < lo ($lo)" }
        if ($hi -eq $lo) { return $lo }
        return $lo + [int]($this.Next() % [uint32]($hi - $lo + 1))
    }

    [object] Pick([object[]]$items) {
        if ($items.Count -eq 0) { throw 'ScRng.Pick: empty set' }
        return $items[$this.Range(0, $items.Count - 1)]
    }

    # Weighted pick over @(@{ v = <thing>; w = <int> }, ...).
    [object] PickWeighted([object[]]$table) {
        $total = 0
        foreach ($e in $table) { $total += [int]$e.w }
        if ($total -le 0) { throw 'ScRng.PickWeighted: total weight is not positive' }
        $roll = $this.Range(1, $total)
        foreach ($e in $table) {
            $roll -= [int]$e.w
            if ($roll -le 0) { return $e.v }
        }
        return $table[-1].v
    }
}

function New-ScRng {
    [CmdletBinding()]
    param([Parameter(Mandatory)][int]$Seed)
    [ScRng]::new($Seed)
}

# ---------------------------------------------------------------------------
# WHICH SUBSETS OF THE BLOCK A DRAG BOX CAN ACTUALLY REACH
# ---------------------------------------------------------------------------
# The map generator lays a block out row-major on a grid `per_row = ceil(sqrt(n))`
# (tools/make_test_map.py, place_units), and a drag box selects everything inside a
# RECTANGLE. So the reachable subsets are exactly the axis-aligned sub-rectangles of that
# grid -- {0,2} of a 2x2 (a diagonal) is NOT reachable, and a suite that pretended it was
# would be boxing four buildings while asserting about two.
#
# Shift-click cannot rescue it either: Windows never updates the key-state table for a
# POSTED message, so a posted Shift+click carries no Shift at all (drive-game.ps1,
# Send-ScCommand). Enumerating the rectangles is the honest version.
function Get-ScGridSubsets {
    [CmdletBinding()]
    param([Parameter(Mandatory)][int]$Count)
    if ($Count -lt 1) { throw "Get-ScGridSubsets: -Count must be >= 1, got $Count" }
    $perRow = [int][math]::Ceiling([math]::Sqrt($Count))
    $rows = [int][math]::Ceiling($Count / $perRow)
    $cell = @{}
    for ($i = 0; $i -lt $Count; $i++) {
        $r = [math]::Floor($i / $perRow); $c = $i % $perRow
        $cell["$r,$c"] = $i
    }
    $out = @()
    $seen = @{}
    for ($r0 = 0; $r0 -lt $rows; $r0++) {
      for ($r1 = $r0; $r1 -lt $rows; $r1++) {
        for ($c0 = 0; $c0 -lt $perRow; $c0++) {
          for ($c1 = $c0; $c1 -lt $perRow; $c1++) {
            $members = @()
            $full = $true
            for ($r = $r0; $r -le $r1; $r++) {
              for ($c = $c0; $c -le $c1; $c++) {
                $k = "$r,$c"
                if ($cell.ContainsKey($k)) { $members += $cell[$k] } else { $full = $false }
              }
            }
            # A rectangle with a HOLE in it (the ragged last row of a non-square block) is
            # still a perfectly good box to drag -- the hole is empty ground. What it must
            # not do is claim a member that is not there.
            if ($members.Count -eq 0) { continue }
            $key = ($members -join ',')
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key] = $true
            $out += [pscustomobject]@{
                Members = @($members)
                Size    = $members.Count
                Ragged  = (-not $full)
                Rows    = @($r0, $r1)
                Cols    = @($c0, $c1)
            }
          }
        }
      }
    }
    # Sorted by size then by first member, so the group numbers a plan hands out are a
    # function of the block size alone and two runs of the same seed assign the same
    # control group to the same subset.
    @($out | Sort-Object Size, { $_.Members[0] })
}

# ---------------------------------------------------------------------------
# THE PLAN
# ---------------------------------------------------------------------------
function New-ScConformancePlan {
    <#
    .SYNOPSIS
    A whole run's worth of random actions, as data. Pure: same arguments -> same object.
    .DESCRIPTION
    Episode kinds, and what each is for. Weights are per profile.

      queue-burst   select a subset, press Train N times, read everything back. The core
                    case and the user's own example ("building x, scheduled unit a, 12
                    times, verify it built 12 and charged for 12").
      group-recall  recall a control group instead of dragging a box, then burst. The
                    same measurement reached through the OTHER input path -- task 036
                    shipped building groups on every path, and a bug in one of them is
                    invisible to a suite that only ever drags.
      queue-cancel  burst, then cancel some of it. Cancel is the only path on which the
                    PLUGIN moves a resource, so the refund is asserted from the engine's
                    globals.
      cancel-slot   cancel by clicking a queue ICON in the status strip -- a different
                    control sending a different payload ({0x20,k} vs {0x20,0xFE}).
      queue-drain   press a small number and WAIT for the units to appear. The "and it
                    built 12" half, read out of the engine's own unit list. Rare, because
                    it is the only episode whose cost is a build time rather than a click.
      indicator     the queue indicator read in two states that differ only in our own
                    string -- a DIFFERENCE, which is the only shape of that assertion
                    worth making, and measured on task 039's boxDiff rather than on ink
                    (see Invoke-IndicatorEpisode for why ink can neither fail nor pass).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$Seed,
        [int]$Episodes = 6,
        [ValidateSet('production', 'upgrades', 'hudrow')][string]$Profile = 'production',
        [int]$Buildings = 3,
        # The plugin's logical cap per building. The plan keeps its own model of each
        # building's queue so it does not generate a burst that would be refused for a full
        # ring -- a refusal is a legitimate engine answer and would make the charge
        # assertion expect money that was correctly never spent.
        [int]$QueueMax = 16,
        # The engine's own ring size. Bursts are biased to exceed it, because a burst that
        # does not is not testing this feature at all.
        [int]$EngineSlots = 5
    )

    $rng = [ScRng]::new($Seed)
    $subsets = Get-ScGridSubsets -Count $Buildings
    # Control groups 1..9. More reachable subsets than that (a 4x4 block has 100) are
    # sampled rather than truncated silently -- the runner prints which ones got a group.
    $grouped = @()
    if ($subsets.Count -le 9) {
        $grouped = @($subsets)
    } else {
        $pool = [System.Collections.ArrayList]::new(@($subsets))
        for ($i = 0; $i -lt 9; $i++) {
            $k = $rng.Range(0, $pool.Count - 1)
            $grouped += $pool[$k]
            $pool.RemoveAt($k)
        }
    }
    $groupOf = @{}
    for ($i = 0; $i -lt $grouped.Count; $i++) { $groupOf[($grouped[$i].Members -join ',')] = $i + 1 }

    # THERE IS DELIBERATELY NO MODEL OF THE QUEUES HERE.
    #
    # The first version of this file kept one, so it would not generate a burst the engine
    # would refuse for a full ring. It made the plans WORSE: two big bursts saturated the
    # model, every later episode came out as `presses=1`, and the interesting part of the
    # run was over by episode three -- while the real game had been quietly draining those
    # queues the whole time, so the caution was against a state that did not exist.
    #
    # The headroom is a fact about the RUNNING GAME, so the RUNNER reads it from the
    # engine (each selected building's own ring plus what the plugin holds for it) and
    # clamps the burst just before it presses, printing `presses=<planned> -> <actual>`.
    # The plan stays a pure function of the seed; what the run did to honour it is
    # reported rather than pre-guessed.

    $kinds = switch ($Profile) {
        'production' { @(
            @{ v = 'queue-burst';  w = 34 },
            @{ v = 'group-recall'; w = 26 },
            @{ v = 'queue-cancel'; w = 16 },
            @{ v = 'cancel-slot';  w = 10 },
            @{ v = 'queue-drain';  w =  8 },
            @{ v = 'indicator';    w =  6 }
        ) }
        'upgrades' { @(
            @{ v = 'upgrade-burst';  w = 50 },
            @{ v = 'upgrade-cancel'; w = 25 },
            @{ v = 'upgrade-drain';  w = 25 }
        ) }
        'hudrow' { @(
            @{ v = 'row-select'; w = 60 },
            @{ v = 'row-page';   w = 40 }
        ) }
    }

    # RESERVED SLOTS, so a gate run cannot come out green having never asserted an
    # invariant. Weighted sampling alone leaves whole invariants unexercised at six
    # episodes -- seed 20260812 drew no drain and no indicator episode at all, which the
    # coverage report would have said honestly and which would still have been a weak gate.
    # Two slots are reserved for the two episode kinds that are the SOLE source of an
    # invariant (queue-drain owns INV-B, indicator owns INV-Q). Everything else stays
    # random, and the reservation itself comes out of the same seeded stream.
    $reserved = @{}
    if ($Profile -eq 'production' -and $Episodes -ge 5) {
        $a = $rng.Range(1, $Episodes)
        $b = $rng.Range(1, $Episodes)
        if ($b -eq $a) { $b = ($a % $Episodes) + 1 }
        $reserved[$a] = 'queue-drain'
        $reserved[$b] = 'indicator'
    }

    $planned = @()
    for ($e = 1; $e -le $Episodes; $e++) {
        $kind = if ($reserved.ContainsKey($e)) { $reserved[$e] } else { $rng.PickWeighted($kinds) }
        $subset = $rng.Pick($subsets)
        $key = ($subset.Members -join ',')
        $group = if ($groupOf.ContainsKey($key)) { $groupOf[$key] } else { 0 }
        # `group-recall` needs a group; if this subset never got one, it becomes an
        # ordinary box episode rather than silently recalling somebody else's group.
        if ($kind -eq 'group-recall' -and $group -eq 0) { $kind = 'queue-burst' }

        $ep = [ordered]@{
            index      = $e
            kind       = $kind
            members    = @($subset.Members)
            size       = $subset.Size
            group      = $group
            selectMode = 'box'
        }

        switch -Regex ($kind) {
            'queue-burst|group-recall|queue-cancel|cancel-slot|indicator' {
                if ($kind -eq 'group-recall') { $ep.selectMode = 'group' }
                elseif ($subset.Size -eq 1 -and $rng.Range(0, 1) -eq 1) { $ep.selectMode = 'click' }

                if ($kind -eq 'indicator') {
                    # Fixed by construction, and the GAP between the two numbers is the whole
                    # argument. The strip lights the same icons in both states, so the only
                    # thing that changes is our own string -- and the gap of 9 guarantees the
                    # two strings differ in LENGTH ("+1" against "+10"), not merely in which
                    # digit they draw.
                    #
                    # Length rather than digit, on 039's correction (2026-08-12): the box's
                    # width is a function of strlen in the indicator's own PlaceOn, so "the
                    # box grew" is guaranteed by construction. A test that instead compared
                    # two SAME-LENGTH strings would be resting on two digits happening to set
                    # a different number of pixels, and two that did not would fail a CORRECT
                    # build at random -- which AGENTS.md rates no better than a check that
                    # cannot fail.
                    #
                    # The numbers stay below -QueueMax: at the default 16, low 6 and high 15
                    # both fit, and the runner skips rather than truncates if a caller lowers
                    # it. Note the episode does not PREDICT "+1"/"+10" -- it reads whatever
                    # the plugin says and asserts the second is longer, because how many icons
                    # the strip shows is the plugin's business and not this file's.
                    $ep.selectMode = 'click'
                    $ep.members = @($subset.Members[0])
                    $ep.size = 1
                    $ep.group = 0
                    $ep.qLow = $EngineSlots + 1
                    $ep.qHigh = $EngineSlots + 10
                    $ep.presses = 0
                } else {
                    # Biased ABOVE the engine's ring: a burst of three proves nothing about
                    # a feature whose whole subject is what happens after five. A quarter of
                    # them stay below it anyway, so "the ordinary case still works" is also
                    # covered and a regression there cannot hide.
                    $lo = if ($rng.Range(1, 4) -eq 1) { 1 } else { $EngineSlots + 1 }
                    $ep.presses = $rng.Range($lo, [math]::Min($EngineSlots + 7, $QueueMax - 1))
                }

                if ($kind -eq 'queue-cancel') {
                    # Cancel is single-building in the engine and in the plugin alike, so
                    # it acts on ONE member of whatever was selected.
                    $ep.cancelUnit = $subset.Members[0]
                    $ep.cancels = $rng.Range(1, [math]::Min(3, [math]::Max(1, $ep.presses)))
                }
                if ($kind -eq 'cancel-slot') {
                    $ep.cancelUnit = $subset.Members[0]
                    # Display index of the icon to click, inside the engine's own strip.
                    $ep.display = $rng.Range(0, $EngineSlots - 1)
                }
            }
            'queue-drain' {
                # Small on purpose: this is the only episode whose cost is a BUILD TIME,
                # and the claim ("what left the queue appeared in the engine's unit list")
                # is as true of two units as of twelve.
                $ep.selectMode = if ($subset.Size -eq 1) { 'click' } else { 'box' }
                $ep.presses = $rng.Range(1, 3)
                $ep.drain = $ep.presses
            }
            'upgrade-burst|upgrade-cancel|upgrade-drain' {
                $ep.selectMode = if ($subset.Size -eq 1) { 'click' } else { 'box' }
                $ep.presses = $rng.Range(1, 4)
                if ($kind -eq 'upgrade-cancel') { $ep.cancels = $rng.Range(1, 2) }
                if ($kind -eq 'upgrade-drain') { $ep.drain = 1 }
            }
            'row-select|row-page' {
                # The hudrow profile selects UNITS, not buildings, so its "size" is a
                # count out of the block rather than a subset of it.
                $ep.members = @()
                $ep.size = $rng.Range(1, 2)
                $ep.selectMode = 'box'
                $ep.units = $rng.Range(8, 24)
                if ($kind -eq 'row-page') { $ep.flips = $rng.Range(1, 4) }
            }
        }

        # A settle between episodes, so consecutive bursts are not one long burst and the
        # engine gets a turn boundary. Randomised, because "it only works at 250ms" would
        # itself be a finding.
        $ep.settleMs = $rng.Range(400, 1600)
        $planned += [pscustomobject]$ep
    }

    [pscustomobject]@{
        schema      = 'sc-random-conformance/1'
        seed        = $Seed
        profile     = $Profile
        buildings   = $Buildings
        queueMax    = $QueueMax
        engineSlots = $EngineSlots
        subsets     = @($subsets | ForEach-Object {
            [pscustomobject]@{
                members = @($_.Members); size = $_.Size
                group = $(if ($groupOf.ContainsKey(($_.Members -join ','))) { $groupOf[($_.Members -join ',')] } else { 0 })
            }
        })
        episodes    = @($planned)
    }
}

function Get-ScPlanJson {
    <# .SYNOPSIS The plan's canonical JSON -- one text, so a hash of it means something. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Plan)
    $Plan | ConvertTo-Json -Depth 10 -Compress
}

function Get-ScPlanHash {
    <#
    .SYNOPSIS
    SHA-256 of the canonical JSON. This is what makes "the same seed replayed the same
    plan" a checkable claim rather than an assurance.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Plan)
    $bytes = [Text.Encoding]::UTF8.GetBytes((Get-ScPlanJson -Plan $Plan))
    $sha = [Security.Cryptography.SHA256]::Create()
    try { ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join '' }
    finally { $sha.Dispose() }
}

function Format-ScPlan {
    <# .SYNOPSIS One line per episode, for the console and for a PR body. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Plan)
    $out = @()
    $out += "plan seed=$($Plan.seed) profile=$($Plan.profile) buildings=$($Plan.buildings) episodes=$($Plan.episodes.Count) hash=$(Get-ScPlanHash -Plan $Plan)"
    foreach ($s in $Plan.subsets) {
        if ($s.group -gt 0) { $out += ("  group {0} = buildings [{1}]" -f $s.group, ($s.members -join ' ')) }
    }
    foreach ($e in $Plan.episodes) {
        $bits = @("[$($e.index)] $($e.kind)", "select=$($e.selectMode)", "members=[$($e.members -join ' ')]")
        foreach ($f in 'group', 'presses', 'cancels', 'display', 'drain', 'units', 'flips', 'qLow', 'qHigh') {
            $v = $e.PSObject.Properties[$f]
            if ($v -and $null -ne $v.Value -and $v.Value -ne 0) { $bits += "$f=$($v.Value)" }
        }
        $out += ('  ' + ($bits -join ' '))
    }
    $out
}
