#Requires -Version 7
<#
Golden-line tests for the printf-to-regex oracle seam.

THE HAZARD: tools/plugin/src writes the ScLog(...) format strings, every suite under
tools/plugin reads them back with its OWN hand-copied regex, and nothing binds the two.
Deleting three dead counters broke five parsers across four suites, caught only by a grep.
Most such parsers fall through to a default object of zeros with no `else`, so drift does not
show as a red suite -- it is a suite asserting against zeros and PASSING.
-> AGENTS.md § "Oracles: what counts as a read-back"

So for each golden line this file reads the ScLog(...) format string out of the C++ source
(it cannot drift from what the plugin prints), renders one line with placeholder values,
asserts every parser regex reading it still matches with the group count its suite indexes,
and asserts that regex appears VERBATIM in the suite -- Contains() on the raw file text, so
this file's own copy of a regex cannot keep passing while the shipped one it stands for rots.
#>

# The line table is plain top-level script code, not inside a BeforeAll: -ForEach needs
# $script:Lines at DISCOVERY time, and BeforeAll is deferred to the run phase, so a
# BeforeAll-wrapped table discovers zero tests. The helper FUNCTIONS and the repo-root lookup
# sit the other way round, in the Describe-level BeforeAll: Pester v5 runs top-level statements
# only once, during discovery, then re-invokes just the registered block bodies in an otherwise
# fresh scope, where a top-level `$script:X = ...` or `function Foo {}` is invisible.

    # Every golden line, in blast-radius order, and every parser (suite + regex) that reads it
    # with an indexed/named capture. Bare existence checks are out of scope: they fail LOUDLY
    # (a timeout or thrown exception) instead of silently defaulting to zero.

    # Fragments = the regex EXACTLY as it appears in the suite's source, split the same way that
    # source splits it (string concatenation across lines) -- each piece is checked verbatim via
    # .Contains(); joined, they are the runnable .NET regex.
    $script:Lines = @(
        @{
            Name = 'PRODQ per-record (sc_prodqueue.cpp)'
            SourceFile = 'sc_prodqueue.cpp'; Marker = 'PRODQ [%s] unit=0x'; First = $null
            Parsers = @(
                @{ Suite = 'test-production-queue.ps1'; SuiteLine = 591; Groups = 10; ExpectMatch = $true
                   Fragments = @('PRODQ \[[^\]]+\] unit=0x([0-9A-Fa-f]+) player=(\d+) head=(\d+) engineLen=(\d+) engine=\[([^\]]*)\] overflow=(\d+) overflowTypes=\[([^\]]*)\] logical=(\d+) minerals=(\d+) gas=(\d+)') }
                @{ Suite = 'test-group-queue-over-five.ps1'; SuiteLine = 196; Groups = 10; ExpectMatch = $true
                   Fragments = @('PRODQ \[[^\]]+\] unit=0x([0-9A-Fa-f]+) player=(\d+) head=(\d+) engineLen=(\d+) engine=\[([^\]]*)\] overflow=(\d+) overflowTypes=\[([^\]]*)\] logical=(\d+) minerals=(\d+) gas=(\d+)') }
                @{ Suite = 'test-random-conformance.ps1'; SuiteLine = 498; Groups = 10; ExpectMatch = $true
                   Fragments = @('PRODQ \[[^\]]+\] unit=0x([0-9A-Fa-f]+) player=(\d+) head=(\d+) engineLen=(\d+) engine=\[([^\]]*)\] overflow=(\d+) overflowTypes=\[([^\]]*)\] logical=(\d+) minerals=(\d+) gas=(\d+)') }
            )
        }
        @{
            Name = 'PRODQ session summary (sc_prodqueue.cpp)'
            SourceFile = 'sc_prodqueue.cpp'; Marker = 'PRODQ [%s] session=%u buildings='; First = $null
            Parsers = @(
                # The gap before refusedFull= tolerates any number of extra "name=value" tokens:
                # a field inserted at that junction must not silently re-break these parsers.
                # Each suite site pairs its match with an `else` so a summary line that fails to
                # parse fails loudly instead of leaving its fields at the zeros they start from.
                @{ Suite = 'test-group-queue-over-five.ps1'; SuiteLine = 214; Groups = 7; ExpectMatch = $true
                   Fragments = @('buildings=(\d+) max=(\d+) captured=(\d+) promoted=(\d+) cancelled=(\d+) refunded=(\d+)(?:\s+\w+=\S+)*\s+refusedFull=(\d+)') }
                @{ Suite = 'test-production-queue.ps1'; SuiteLine = 606; Groups = 7; ExpectMatch = $true
                   Fragments = @('buildings=(\d+) max=(\d+) captured=(\d+) promoted=(\d+) cancelled=(\d+) refunded=(\d+)(?:\s+\w+=\S+)*\s+refusedFull=(\d+)') }
                @{ Suite = 'test-random-conformance.ps1'; SuiteLine = 511; Groups = 7; ExpectMatch = $true
                   Fragments = @('PRODQ \[[^\]]+\](?:\s+\w+=\S+)*\s+buildings=(\d+) max=(\d+) captured=(\d+) promoted=(\d+) cancelled=(\d+) refunded=(\d+)(?:\s+\w+=\S+)*\s+refusedFull=(\d+)') }
                @{ Suite = 'test-random-conformance.ps1'; SuiteLine = 519; Groups = 2; ExpectMatch = $true
                   Fragments = @('trainSeen=(\d+) trainNoUnit=(\d+)') }
                @{ Suite = 'test-save-load.ps1'; SuiteLine = 182; Groups = 1; ExpectMatch = $true
                   Fragments = @('buildings=(\d+)') }
            )
        }
        @{
            Name = 'PRODQSTATS (sc_prodqueue.cpp)'
            SourceFile = 'sc_prodqueue.cpp'; Marker = 'PRODQSTATS captured=%d'; First = $null
            Parsers = @(
                @{ Suite = 'test-production-queue.ps1'; SuiteLine = 1517; Groups = 6; ExpectMatch = $true
                   Fragments = @('captured=(\d+) promoted=(\d+) cancelled=(\d+) refunded=(\d+)(?:\s+\w+=\S+)*\s+refusedFull=(\d+) mineralsRefunded=(\d+)') }
                @{ Suite = 'test-group-queue-over-five.ps1'; SuiteLine = 776; Groups = 7; ExpectMatch = $true
                   Fragments = @('captured=(\d+) promoted=(\d+) cancelled=(\d+) refunded=(\d+)(?:\s+\w+=\S+)*\s+refusedFull=(\d+) mineralsRefunded=(\d+) gasRefunded=(\d+)') }
            )
        }
        @{
            Name = 'PRODQSEL (sc_prodqueue.cpp)'
            SourceFile = 'sc_prodqueue.cpp'; Marker = 'PRODQSEL [%s] unit=0x'; First = $null
            Parsers = @(
                @{ Suite = 'test-production-queue.ps1'; SuiteLine = 574; Groups = 10; ExpectMatch = $true
                   Fragments = @('PRODQSEL \[[^\]]+\] unit=0x([0-9A-Fa-f]+) type=0x([0-9A-Fa-f]+) player=(\d+) head=(\d+) engineLen=(\d+) engine=\[([^\]]*)\] overflow=(\d+) logical=(\d+) minerals=(\d+) gas=(\d+)') }
                @{ Suite = 'test-save-load.ps1'; SuiteLine = 174; Groups = 10; ExpectMatch = $true
                   Fragments = @('PRODQSEL \[[^\]]+\] unit=0x([0-9A-Fa-f]+) type=0x([0-9A-Fa-f]+) player=(\d+) head=(\d+) engineLen=(\d+) engine=\[([^\]]*)\] overflow=(\d+) logical=(\d+) minerals=(\d+) gas=(\d+)') }
            )
        }
        @{
            # LogUnitLine is shared by the UPGQSEL and UPGQ tags: its leading %s is the tag, a
            # runtime argument absent from the source text, so it must come in via -First.
            Name = 'UPGQSEL (sc_upgrades.cpp, LogUnitLine)'
            SourceFile = 'sc_upgrades.cpp'
            Marker = '%s [%s] unit=0x%08X type=0x%03X player=%u upg=%u tech=%u lvl=%u time=%u '
            First = 'UPGQSEL'
            Parsers = @(
                @{ Suite = 'test-upgrade-queue.ps1'; SuiteLine = 189; Groups = 13; ExpectMatch = $true
                   Fragments = @('UPGQSEL \[[^\]]+\] unit=0x([0-9A-Fa-f]+) type=0x([0-9A-Fa-f]+) player=(\d+) upg=(\d+) tech=(\d+) lvl=(\d+) time=(\d+) busy=(\d+) queued=(\d+) queue=\[([^\]]*)\] logical=(\d+) minerals=(\d+) gas=(\d+)') }
            )
        }
        @{
            Name = 'UPGQ session summary (sc_upgrades.cpp)'
            SourceFile = 'sc_upgrades.cpp'; Marker = 'UPGQ [%s] session=%u buildings='; First = $null
            Parsers = @(
                # Same tolerant gap as the PRODQ summary above: if this regex misses, the
                # suite's `RefusedFull -eq 0` assertion reads a zeroed field and is vacuous.
                @{ Suite = 'test-upgrade-queue.ps1'; SuiteLine = 220; Groups = 12; ExpectMatch = $true
                   Fragments = @('buildings=(\d+) max=(\d+) queued=(\d+) promoted=(\d+) cancelled=(\d+) dropped=(\d+)(?:\s+\w+=\S+)*\s+refusedFull=(\d+) refusedGate=(\d+) waitingCost=(\d+) unblocked=(\d+) hiddenHeld=(\d+) refusedDup=(\d+)') }
            )
        }
        @{
            Name = 'UPGQSTATS (sc_upgrades.cpp)'
            SourceFile = 'sc_upgrades.cpp'; Marker = 'UPGQSTATS queued=%d'; First = $null
            Parsers = @(
                # No tolerant gap needed: this suite indexes only the first four fields, all
                # ahead of the junction where later fields get inserted.
                @{ Suite = 'test-upgrade-queue.ps1'; SuiteLine = 736; Groups = 4; ExpectMatch = $true
                   Fragments = @('queued=(\d+) promoted=(\d+) cancelled=(\d+) dropped=(\d+)') }
            )
        }
        @{
            Name = 'HUDROW show (sc_hudrow.cpp)'
            SourceFile = 'sc_hudrow.cpp'; Marker = 'HUDROW show n=%d page=%d/%d slots=%d'; First = $null
            Parsers = @(
                @{ Suite = 'test-combat-death.ps1'; SuiteLine = 452; Groups = 6; ExpectMatch = $true
                   Fragments = @('HUDROW show n=(\d+) page=(\d+)/(\d+) slots=(\d+) \[([0-9A-F ]*)\] indicator="([^"]*)"') }
                @{ Suite = 'test-control-groups.ps1'; SuiteLine = 395; Groups = 5; ExpectMatch = $true
                   Fragments = @('HUDROW show n=(\d+) page=(\d+)/(\d+) slots=(\d+) \[([0-9A-F ]*)\]') }
                @{ Suite = 'test-hud-row.ps1'; SuiteLine = 107; Groups = 19; ExpectMatch = $true
                   Fragments = @(
                       'HUDROW show n=(?<n>\d+) page=(?<page>\d+)/(?<pages>\d+) slots=(?<slots>\d+) ',
                       '\[(?<tags>[0-9A-F ]*)\] indicator="(?<text>[^"]*)" ',
                       'indLinked=(?<linked>\d+) indVisible=(?<visible>\d+) ',
                       'indBounds=\((?<l>-?\d+),(?<t>-?\d+),(?<r>-?\d+),(?<b>-?\d+)\) indInk=(?<ink>-?\d+)',
                       '(?: indBoxDiff=(?<boxDiff>-?\d+) indRefInk=(?<refInk>-?\d+) indRefId=(?<refId>-?\d+)',
                       ' indSurfInk=(?<surfInk>-?\d+) indFontH=(?<fontH>-?\d+) indShowing=(?<showing>\d+))?') }
            )
        }
        @{
            Name = 'FANOUT select: (sc_fanout.cpp)'
            SourceFile = 'sc_fanout.cpp'; Marker = 'FANOUT select: in=%d out=%d dropped=%d tags='; First = $null
            Parsers = @(
                @{ Suite = 'test-building-groups.ps1'; SuiteLine = 490; Groups = 3; ExpectMatch = $true
                   Fragments = @('FANOUT select: in=(\d+) out=(\d+) dropped=(\d+)') }
                @{ Suite = 'test-combat-death.ps1'; SuiteLine = 927; Groups = 1; ExpectMatch = $true
                   Fragments = @('FANOUT select: in=\d+ out=\d+ dropped=\d+ tags=\[([0-9A-F ]*)\]') }
            )
        }
        @{
            Name = 'WORLD screen (scplugin.cpp)'
            SourceFile = 'scplugin.cpp'; Marker = 'WORLD [%s] screen='; First = $null
            Parsers = @(
                @{ Suite = 'test-random-conformance.ps1'; SuiteLine = 537; Groups = 2; ExpectMatch = $true
                   EscPlaceholder = $true
                   Fragments = @('WORLD \[$esc\].*screen=\((\d+),(\d+)\)') }
            )
        }
        @{
            Name = 'WORLD per-unit (scplugin.cpp)'
            SourceFile = 'scplugin.cpp'; Marker = 'WORLD [%s] p=%d i=%d unit=0x'; First = $null
            Parsers = @(
                @{ Suite = 'test-random-conformance.ps1'; SuiteLine = 523; Groups = 13; ExpectMatch = $true
                   Fragments = @('WORLD \[[^\]]+\] p=(\d+) i=(\d+) unit=0x([0-9A-Fa-f]+) owner=(\d+) type=0x([0-9A-Fa-f]+) hp=(-?\d+) order=0x([0-9A-Fa-f]+) order2=0x([0-9A-Fa-f]+) stim=(\d+) energy=(\d+) pos=\((\d+),(\d+)\) flags=0x([0-9A-Fa-f]+)') }
            )
        }
        @{
            Name = 'WORLD per-player summary (scplugin.cpp)'
            SourceFile = 'scplugin.cpp'; Marker = 'WORLD [%s] p=%d units=%d recount='; First = $null
            Parsers = @(
                @{ Suite = 'test-random-conformance.ps1'; SuiteLine = 542; Groups = 4; ExpectMatch = $true
                   EscPlaceholder = $true
                   Fragments = @('WORLD \[$esc\] p=(\d+) units=(\d+) recount=(\d+) complete=(\d+)') }
            )
        }
        @{
            Name = 'CIRCLES show (sc_circles.cpp)'
            SourceFile = 'sc_circles.cpp'; Marker = 'CIRCLES show: %d/%d units circled'; First = $null
            Parsers = @(
                @{ Suite = 'test-building-groups.ps1'; SuiteLine = 566; Groups = 2; ExpectMatch = $true
                   Fragments = @('CIRCLES show: (\d+)/(\d+)') }
                @{ Suite = 'test-control-groups.ps1'; SuiteLine = 432; Groups = 2; ExpectMatch = $true
                   Fragments = @('CIRCLES show: (\d+)/(\d+)') }
                @{ Suite = 'test-selection-circles.ps1'; SuiteLine = 222; Groups = 2; ExpectMatch = $true
                   Fragments = @('CIRCLES show: (\d+)/(\d+)') }
            )
        }
        @{
            # Both suites span "CIRCLES stats:" to "shown=" with .*, so a field inserted at the
            # front of the line cannot orphan them: a stats regex that misses leaves
            # $stats.Count at 0, which takes the "a CIRCLES stats line was written on detach"
            # failure branch and skips the three accounting assertions under it entirely.
            Name = 'CIRCLES stats (sc_circles.cpp)'
            SourceFile = 'sc_circles.cpp'; Marker = 'CIRCLES stats: session=%u shown=%u'; First = $null
            Parsers = @(
                @{ Suite = 'test-selection-circles.ps1'; SuiteLine = 377; Groups = 6; ExpectMatch = $true
                   Fragments = @('CIRCLES stats:.* shown=(\d+) hidden=(\d+) held=(-?\d+) skipped=(\d+) noImage=(\d+) lost=(\d+)') }
                @{ Suite = 'test-building-groups.ps1'; SuiteLine = 698; Groups = 6; ExpectMatch = $true
                   Fragments = @('CIRCLES stats:.* shown=(\d+) hidden=(\d+) held=(-?\d+) skipped=(\d+) noImage=(\d+) lost=(\d+)') }
            )
        }
        @{
            Name = 'QIND (sc_queueind.cpp) -- the two consumers that index its groups'
            SourceFile = 'sc_queueind.cpp'; Marker = 'QIND [%s] mode=%d linked=%d visible=%d'; First = $null
            Parsers = @(
                @{ Suite = 'test-production-queue.ps1'; SuiteLine = 357; Groups = 22; ExpectMatch = $true
                   Fragments = @(
                       'QIND \[[^\]]+\] mode=(?<mode>\d+) linked=(?<linked>\d+) visible=(?<visible>\d+) ',
                       'text="(?<text>[^"]*)" ',
                       'bounds=\((?<left>-?\d+),(?<top>-?\d+),(?<right>-?\d+),(?<bottom>-?\d+)\) ',
                       'ink=(?<ink>-?\d+) refInk=(?<refInk>-?\d+) refId=(?<refId>-?\d+) ',
                       'surfInk=(?<surfInk>-?\d+) slotDiff=(?<slotDiff>-?\d+) boxDiff=(?<boxDiff>-?\d+) ',
                       'fontH=(?<fontH>\d+) ',
                       'icons=\[(?<icons>[^\]]*)\] ',
                       'sel=(?<sel>\d+) engineLen=(?<engineLen>\d+) overflow=(?<overflow>\d+) ',
                       'upg=(?<upg>\d+) bldgs=(?<bldgs>\d+) queued=(?<queued>\d+)') }
                @{ Suite = 'test-random-conformance.ps1'; SuiteLine = 565; Groups = 10; ExpectMatch = $true
                   Fragments = @('QIND \[[^\]]+\] mode=(\d+) linked=(\d+) visible=(\d+) text="([^"]*)" bounds=\((-?\d+),(-?\d+),(-?\d+),(-?\d+)\) ink=(-?\d+) refInk=(-?\d+)') }
            )
        }
    )

Describe 'Golden-line seam: every parser regex still matches the plugin''s own format string (issue #81)' {

    BeforeAll {
        $script:PluginRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' 'tools' 'plugin')).Path
        $script:SrcRoot    = Join-Path $script:PluginRoot 'src'
        $script:renderN    = 0

        # Concatenate the adjacent string literals of the ScLog(...) call whose first literal
        # starts with $Marker, the way the C preprocessor does. Stopping at the first ');' is
        # safe because no argument list here contains that two-character substring: every
        # intermediate call or cast closes with ',' or ' ', never ';'.
        function Get-ScLogFormat {
            param([Parameter(Mandatory)][string]$File, [Parameter(Mandatory)][string]$Marker)
            $text = Get-Content -Raw -LiteralPath $File
            $idx = $text.IndexOf("ScLog(`"$Marker")
            if ($idx -lt 0) { throw "no ScLog(`"$Marker...`") in $File -- the source moved; update the marker." }
            $tail = $text.Substring($idx)
            $end = $tail.IndexOf(');')
            if ($end -lt 0) { throw "no closing ');' found for the ScLog(`"$Marker...`") call in $File" }
            $call = $tail.Substring(0, $end)
            $lits = [regex]::Matches($call, '"((?:[^"\\]|\\.)*)"')
            if ($lits.Count -eq 0) { throw "no string literals found in the ScLog(`"$Marker...`") call in $File" }
            (($lits | ForEach-Object { $_.Groups[1].Value }) -join '') -replace '\\"', '"'
        }

        # Render one concrete line from a printf-style format string. %s -> a fixed placeholder
        # tag, %d/%u(/l-variants) -> a distinct decimal, %X/%x -> a distinct hex run. -First
        # substitutes ONLY the first %s, for a tag the caller must supply.
        function Expand-ScFormat {
            param([Parameter(Mandatory)][string]$Fmt, [string]$First)
            if ($First) {
                $i = $Fmt.IndexOf('%s')
                if ($i -lt 0) { throw 'Expand-ScFormat -First given but the format has no %s' }
                $Fmt = $Fmt.Substring(0, $i) + $First + $Fmt.Substring($i + 2)
            }
            [regex]::Replace($Fmt, '%[-0-9.]*(l?)([dusXx])', {
                param($m)
                $conv = $m.Groups[2].Value
                # Uppercase-hex-only, not e.g. 'tag1': the plugin renders some %s fields as hex
                # lists (HUDROW's bracketed tags, FANOUT's tags=[...]) whose suite regexes
                # constrain the content to [0-9A-F ]*, and a placeholder holding a 't' or 'g'
                # would make those, and only those, stop matching.
                if ($conv -eq 's') { return 'ABCD' }
                $script:renderN++
                if ($conv -eq 'X' -or $conv -eq 'x') { '{0:X}' -f ($script:renderN * 47) }
                else { "$($script:renderN * 3)" }
            })
        }

        # Some suites scope their regex to a run with "...\[$esc\]...", where $esc is always
        # [regex]::Escape() of a marker label -- the same tag Expand-ScFormat renders as the
        # literal 'ABCD', so swapping the literal text '$esc' for 'ABCD' makes the suite's own
        # pattern runnable here.
        function Resolve-EscPlaceholder { param([string]$Pattern) $Pattern -replace '\$esc', 'ABCD' }
    }

    Context '<Name>' -ForEach $script:Lines {

        BeforeAll {
            $script:renderedLine = Expand-ScFormat `
                -Fmt (Get-ScLogFormat -File (Join-Path $script:SrcRoot $SourceFile) -Marker $Marker) `
                -First $First
        }

        It 'renders a non-empty line from the C++ source' {
            $script:renderedLine | Should -Not -BeNullOrEmpty
        }

        Context '<Suite>:<SuiteLine>' -ForEach $Parsers {

            It 'the regex is present VERBATIM in the suite it claims to come from' {
                $suiteText = Get-Content -Raw -LiteralPath (Join-Path $script:PluginRoot $Suite)
                foreach ($frag in $Fragments) {
                    $suiteText.Contains($frag) | Should -BeTrue `
                        -Because "$Suite must contain this exact regex fragment, not a paraphrase:`n  $frag"
                }
            }

            It 'matches the rendered line with <Groups> capturing group(s)' {
                $pattern = $Fragments -join ''
                if ($EscPlaceholder) { $pattern = Resolve-EscPlaceholder $pattern }
                $m = [regex]::Match($script:renderedLine, $pattern)
                $detail = "rendered:`n  $script:renderedLine`npattern:`n  $pattern"
                if ($ExpectMatch) {
                    $m.Success | Should -BeTrue -Because $detail
                    ($m.Groups.Count - 1) | Should -Be $Groups
                } else {
                    # ExpectMatch = $false pins a REPORTED finding: the parser does not match
                    # the plugin's own output, and the finding is reported rather than quietly
                    # patched (AGENTS.md § "Diagnostics and reporting"). If this It starts
                    # FAILING, someone repaired the suite's regex -- flip ExpectMatch to $true
                    # so the group-count assert above confirms the fix group-for-group.
                    $m.Success | Should -BeFalse -Because "known-broken finding, issue #87, not fixed here. $detail"
                }
            }
        }
    }
}
