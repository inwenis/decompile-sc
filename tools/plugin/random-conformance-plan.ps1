#Requires -Version 7
<#
.SYNOPSIS
The PLAN half of the randomized conformance harness: a seeded, pure, game-free
generator of action sequences, and the deterministic PRNG behind it.

.DESCRIPTION
A random failure that cannot be replayed is a rumour: the plan touches no game, clock or
filesystem, so a seed replays the same object anywhere, and the PRNG is ours because
`System.Random`'s seeded sequence is not contract-stable across .NET versions and has
already been reimplemented once. Selection SIZE is randomised hardest: the engine gates on
`playersSelections[activePlayerId]` while the client's `activePlayerSelection` is a
different list, and the two agree in every single-building case -- so a handler reading the
wrong one passes every suite that only ever selects one building.

.EXAMPLE
. ./tools/plugin/random-conformance-plan.ps1
New-ScConformancePlan -Seed 12345 -Episodes 6 -Profile production | ConvertTo-Json -Depth 8
#>

# --- SplitMix32: eight lines, no dependency, same sequence on every runtime ---
class ScRng {
    [uint32]$State

    # EVERY CONSTANT CARRIES AN `L`. PowerShell parses `0xFFFFFFFF` as the Int32 -1 and
    # `0x9E3779B9` as a negative Int32, so unsuffixed constants silently compute something
    # else (throwing on the cast is the lucky outcome). `L` forces Int64 and the masks
    # then mean what they say.
    ScRng([int]$seed) {
        # 0 is a legitimate seed: special-casing it would make `-Seed 0` in a bug
        # report replay a different plan than the run that produced it.
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

# --- WHICH SUBSETS OF THE BLOCK A DRAG BOX CAN ACTUALLY REACH ---
# The map generator lays a block out row-major on a grid `per_row = ceil(sqrt(n))`
# (tools/make_test_map.py, place_units) and a drag box selects a RECTANGLE, so the
# reachable subsets are exactly the axis-aligned sub-rectangles: {0,2} of a 2x2 is NOT
# reachable, and a suite pretending it is boxes four buildings while asserting about two.
# Shift-click cannot widen this -- Windows never updates the key-state table for a POSTED
# message, so a posted Shift+click carries no Shift (drive-game.ps1, Send-ScCommand).
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
            # A rectangle with a HOLE (the ragged last row of a non-square block) is still
            # a good box to drag -- the hole is empty ground; it must only never claim a
            # member that is not there.
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
    # Sorted by size then first member, so group numbers are a function of the block size
    # alone and two runs of one seed give the same control group to the same subset.
    @($out | Sort-Object Size, { $_.Members[0] })
}

# --- THE PLAN ---
function New-ScConformancePlan {
    <#
    .SYNOPSIS
    A whole run's worth of random actions, as data. Pure: same arguments -> same object.
    .DESCRIPTION
    Episode kinds and the seam each one exists to reach; weights are per profile.

      queue-burst   subset, press Train N times, read everything back: the core case.
      group-recall  the same measurement through the OTHER input path, since a bug in
                    control-group recall is invisible to a suite that only ever drags.
      queue-cancel  burst then cancel: the only path on which the PLUGIN moves a
                    resource, so the refund is asserted from the engine's globals.
      cancel-slot   cancel by clicking a queue ICON -- a different control sending a
                    different payload ({0x20,k} vs {0x20,0xFE}).
      queue-drain   press a few and WAIT for the units: the "and it built 12" half, read
                    from the engine's unit list. Rare -- its cost is a build time.
      indicator     the indicator read in two states that differ only in our own string,
                    as a DIFFERENCE measured on boxDiff rather than on ink (see
                    Invoke-IndicatorEpisode for why ink can neither fail nor pass).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$Seed,
        [int]$Episodes = 6,
        [ValidateSet('production', 'upgrades', 'hudrow')][string]$Profile = 'production',
        [int]$Buildings = 3,
        # The plugin's logical cap per building; bursts stay under it, since a refusal for
        # a full queue is a legitimate engine answer and would make the charge assertion
        # expect money that was correctly never spent.
        [int]$QueueMax = 16,
        # The engine's own ring size. Bursts are biased to exceed it, because a burst that
        # does not is not testing this feature at all.
        [int]$EngineSlots = 5
    )

    $rng = [ScRng]::new($Seed)
    $subsets = Get-ScGridSubsets -Count $Buildings
    # Control groups 1..9. More reachable subsets than that (a 4x4 block has 100) are
    # sampled, not truncated silently -- the runner prints which ones got a group.
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

    # DELIBERATELY NO MODEL OF THE QUEUES HERE. Modelling them to avoid bursts the engine
    # would refuse makes plans worse: two big bursts saturate the model, every later
    # episode comes out `presses=1`, and the run is over by episode three -- while the real
    # game has been draining those queues all along, so the caution guards a state that
    # does not exist. Headroom is a fact about the RUNNING GAME: the runner reads it from
    # the engine (each building's ring plus what the plugin holds) and clamps just before
    # pressing, printing `presses=<planned> -> <actual>`. The plan stays a pure function of
    # the seed and what the run did to honour it is reported, not pre-guessed.

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
    # invariant: at six episodes weighted sampling alone draws seeds with no drain and no
    # indicator episode at all. One slot each for the two kinds that are the SOLE source of
    # an invariant (queue-drain owns INV-B, indicator owns INV-Q). Everything else stays
    # random, and the reservation itself comes out of the same seeded stream.
    #   -> AGENTS.md § "Generated suites (random, fuzzed, property-based)"
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
                    # The GAP between the two numbers is the whole argument. The strip lights
                    # the same icons in both states, so only our own string changes, and a
                    # gap of 9 makes the two strings differ in LENGTH ("+1" against "+10").
                    # Length, not digit: box width is a function of strlen in the indicator's
                    # own PlaceOn, so "the box grew" holds by construction, while comparing
                    # two SAME-LENGTH strings rests on two digits happening to set a different
                    # number of pixels -- and two that do not fail a CORRECT build at random.
                    #   -> AGENTS.md § "Oracles: what counts as a read-back"
                    # The numbers stay below -QueueMax (at the default 16, 6 and 15 both fit;
                    # the runner skips rather than truncates if a caller lowers it), and the
                    # episode reads whatever string the plugin gives rather than predicting
                    # it, because how many icons the strip shows is the plugin's business.
                    $ep.selectMode = 'click'
                    $ep.members = @($subset.Members[0])
                    $ep.size = 1
                    $ep.group = 0
                    $ep.qLow = $EngineSlots + 1
                    $ep.qHigh = $EngineSlots + 10
                    $ep.presses = 0
                } else {
                    # Biased ABOVE the engine's ring: a burst of three proves nothing about a
                    # feature whose subject is what happens once the ring is full. A quarter
                    # stay below it, so a regression in the ordinary case cannot hide either.
                    $lo = if ($rng.Range(1, 4) -eq 1) { 1 } else { $EngineSlots + 1 }
                    $ep.presses = $rng.Range($lo, [math]::Min($EngineSlots + 7, $QueueMax - 1))
                }

                if ($kind -eq 'queue-cancel') {
                    # Cancel is single-building in engine and plugin alike, so it acts on
                    # ONE member of whatever was selected.
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
                # Small on purpose: the only episode whose cost is a BUILD TIME, and its
                # claim ("what left the queue appeared in the engine's unit list") is as
                # true of two units as of twelve.
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
                # The hudrow profile selects UNITS, not buildings, so its "size" is a count
                # out of the block rather than a subset of it.
                $ep.members = @()
                $ep.size = $rng.Range(1, 2)
                $ep.selectMode = 'box'
                $ep.units = $rng.Range(8, 24)
                if ($kind -eq 'row-page') { $ep.flips = $rng.Range(1, 4) }
            }
        }

        # A settle between episodes, so consecutive bursts are not one long burst and the
        # engine gets a turn boundary. Randomised: "it only works at 250ms" is a finding.
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
    SHA-256 of the canonical JSON: what makes "the same seed replayed the same plan" a
    checkable claim rather than an assurance.
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
