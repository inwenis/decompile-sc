#Requires -Version 7
<#
Golden-line tests for the printf-to-regex oracle seam -- issue #81, sibling of #78 (task 057).

THE HAZARD. tools/plugin/src writes ScLog(...) format strings; every suite under tools/plugin
reads them back with its OWN, hand-copied regex. There is no contract between the two. PR #77
proved this is not hypothetical: deleting three dead counters (issue #66) broke FIVE parsers
across FOUR suites, found only by a grep. Most of those parsers fall through to a default
object of zeros with no `else` branch, so the failure mode is not a red suite -- it is a suite
that asserts against zeros and PASSES.

WHAT THIS FILE DOES, for each golden line named in issue #81 (PRODQ/PRODQSEL/PRODQSTATS,
UPGQ/UPGQSEL/UPGQSTATS, HUDROW show, FANOUT select:, WORLD, CIRCLES show) plus QIND's one
real (non-diagnostic) consumer:

  1. reads the ScLog(...) format string OUT OF THE C++ SOURCE, so it cannot drift from what
     the plugin actually prints;
  2. renders one line from it with placeholder values;
  3. asserts every parser regex that reads that line still matches, with the group count the
     suite indexes;
  4. asserts the regex is present VERBATIM in the suite it claims to come from, so this file's
     copy cannot itself go stale while the shipped one rots -- Contains() on the raw file text,
     not a normalised or re-derived comparison.

A LIVE FINDING, not fixed here (issue #87): six of these parsers, across four suites, no
longer match the plugin's OWN current output. PR #82 (merged tonight, efa1d8d) inserted
`staleSession=%d` between `refunded=`/`dropped=` and `refusedFull=` in the PRODQ/UPGQ summary
lines and in PRODQSTATS. Two of the six suites have an explicit `else { Assert-That ...
$false }` and would fail loudly. The other four have no `else` -- their fields silently keep
the zero the object was initialised with, and at least one shipped assertion
(`$q.RefusedFull -eq 0`, test-upgrade-queue.ps1:490) is now a tautology. AGENTS.md: report a
finding, do not quietly fix it -- see issue #87 for the repair, and the six `ExpectMatch =
$false` entries below for exactly which parsers are affected.
#>

# The line table below is plain top-level script code, not inside a BeforeAll: -ForEach
# needs $script:Lines at DISCOVERY time, and BeforeAll is deferred to the run phase -- a
# BeforeAll-wrapped table would discover zero tests. Conversely, the helper FUNCTIONS and the
# repo-root lookup live in the Describe-level BeforeAll below the table (not here): Pester v5
# runs top-level statements only once, during discovery, and re-invokes just the registered
# block bodies for the run phase in what is otherwise a fresh scope -- a plain top-level
# `$script:X = ...` or `function Foo {}` up here is invisible by the time any BeforeAll or It
# actually runs. Proved by running it both ways before settling on this split.
#
# Every golden line issue #81 names, in its blast-radius order, and every parser (suite +
    # regex) that reads it with an indexed/named capture -- not a bare existence check, which
    # fails LOUDLY (a timeout or thrown exception) rather than silently defaulting to zero, so
    # it is not this hazard (see the PR's coverage table for the suites/lines left out on that
    # basis: STATQ, and the WORLD/QIND/CARD/PRODFAN existence gates).
    #
    # Fragments = the regex EXACTLY as it appears in the suite's source, split the same way the
    # suite's own source splits it (string concatenation across lines) -- each piece is checked
    # verbatim via .Contains(). Pattern = Fragments joined into one usable .NET regex, with any
    # '$esc' placeholder swapped for the same 'ABCD' Expand-ScFormat renders.
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
                # BROKEN LIVE (issue #87): staleSession= now sits between
                # refunded= and refusedFull=, so this unprefixed pattern no longer matches --
                # and there is no `else`, so $out.{TrackedCount,Captured,Promoted,Cancelled,
                # Refunded,RefusedFull} silently keep the zero the object was initialised with.
                @{ Suite = 'test-group-queue-over-five.ps1'; SuiteLine = 214; Groups = 7; ExpectMatch = $false
                   Fragments = @('buildings=(\d+) max=(\d+) captured=(\d+) promoted=(\d+) cancelled=(\d+) refunded=(\d+) refusedFull=(\d+)') }
                @{ Suite = 'test-production-queue.ps1'; SuiteLine = 606; Groups = 7; ExpectMatch = $false
                   Fragments = @('buildings=(\d+) max=(\d+) captured=(\d+) promoted=(\d+) cancelled=(\d+) refunded=(\d+) refusedFull=(\d+)') }
                @{ Suite = 'test-random-conformance.ps1'; SuiteLine = 511; Groups = 7; ExpectMatch = $false
                   Fragments = @('PRODQ \[[^\]]+\] buildings=(\d+) max=(\d+) captured=(\d+) promoted=(\d+) cancelled=(\d+) refunded=(\d+) refusedFull=(\d+)') }
                # Unaffected: a separate match against the same rendered line, own field pair.
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
                # Also broken by the same staleSession= insertion -- but both sites below have
                # an explicit `else { Assert-That ... $false }`, so (unlike the summary line
                # above) breaking this fails LOUDLY rather than silently reading zero. Pinned
                # here as ExpectMatch=$false for the same reason: it is still wrong today.
                @{ Suite = 'test-production-queue.ps1'; SuiteLine = 1515; Groups = 6; ExpectMatch = $false
                   Fragments = @('captured=(\d+) promoted=(\d+) cancelled=(\d+) refunded=(\d+) refusedFull=(\d+) mineralsRefunded=(\d+)') }
                @{ Suite = 'test-group-queue-over-five.ps1'; SuiteLine = 774; Groups = 7; ExpectMatch = $false
                   Fragments = @('captured=(\d+) promoted=(\d+) cancelled=(\d+) refunded=(\d+) refusedFull=(\d+) mineralsRefunded=(\d+) gasRefunded=(\d+)') }
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
            # LogUnitLine, shared by the UPGQSEL and UPGQ tags -- the leading %s is the tag,
            # supplied here via -First since it is a runtime argument, not literal source text.
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
                # BROKEN LIVE, same root cause and same silent-zero shape as the PRODQ summary
                # above: staleSession= now sits between dropped= and refusedFull=. No `else` --
                # test-upgrade-queue.ps1:490's `Assert-That ... ($q.RefusedFull -eq 0)` is a
                # tautology right now, whatever the plugin actually refused.
                @{ Suite = 'test-upgrade-queue.ps1'; SuiteLine = 220; Groups = 11; ExpectMatch = $false
                   Fragments = @('buildings=(\d+) max=(\d+) queued=(\d+) promoted=(\d+) cancelled=(\d+) dropped=(\d+) refusedFull=(\d+) refusedGate=(\d+) waitingCost=(\d+) unblocked=(\d+) unblockedLevel=(\d+)') }
            )
        }
        @{
            Name = 'UPGQSTATS (sc_upgrades.cpp)'
            SourceFile = 'sc_upgrades.cpp'; Marker = 'UPGQSTATS queued=%d'; First = $null
            Parsers = @(
                # Unaffected: this suite only indexes the first four fields (queued/promoted/
                # cancelled/dropped), all BEFORE staleSession= in the format string.
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
        # starts with $Marker, the way the C preprocessor does. Finding the call's own closing
        # ');' is safe here because a C++ argument list cannot itself contain the two-character
        # substring ');' -- every intermediate call/cast in this codebase closes with ',' or
        # ' ', never ';', so the first ');' found is the call's own end.
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
        # substitutes ONLY the first %s with a literal (LogUnitLine in sc_upgrades.cpp is
        # shared by the UPGQSEL and UPGQ tags -- the tag itself is the first %s, not part of
        # the literal format text, so it cannot be read out of the source and must be supplied
        # by the caller).
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
                # Uppercase-hex-only, not e.g. 'tag1': some %s fields are rendered by the
                # plugin as hex lists (HUDROW's bracketed tag string, FANOUT's tags=[...]) and
                # their suites' regexes constrain the content to [0-9A-F ]* -- a placeholder
                # with a 't' or 'g' in it would make those, and only those, stop matching.
                if ($conv -eq 's') { return 'ABCD' }
                $script:renderN++
                if ($conv -eq 'X' -or $conv -eq 'x') { '{0:X}' -f ($script:renderN * 47) }
                else { "$($script:renderN * 3)" }
            })
        }

        # A handful of suites build their regex against a marker-scoped line with
        # "...\[$esc\]..." (a double-quoted string interpolating the escaped run label). $esc
        # is always [regex]::Escape() of a marker label, i.e. an escaped copy of the same tag
        # Expand-ScFormat renders as the literal text 'ABCD' -- so substituting the literal
        # text '$esc' for 'ABCD' turns the suite's own pattern into something this file can run.
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
                    # PINNED FINDING (see the header comment and the PR): this parser does NOT
                    # match the plugin's own current output. If this It starts FAILING, someone
                    # fixed the suite's regex -- flip ExpectMatch to $true and the group-count
                    # assert above will confirm the fix is complete, group-for-group.
                    $m.Success | Should -BeFalse -Because "known-broken finding, issue #87, not fixed here. $detail"
                }
            }
        }
    }
}
