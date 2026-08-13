#Requires -Version 7
<#
Pester coverage for tools/plugin/sc-oracle-guard.ps1 -- issues #69 and #70.

EVERY CONTEXT BELOW IS A FIXTURE THAT MAKES A REAL SUITE'S CLAIM FALSE, and asserts two
things about it: that the assertion AS IT SHIPPED scored it a pass, and that the repaired
one does not. The first half is the part that matters. This task is about checks that
cannot fail, so a fix nobody watched fail is the same defect -- and for a suite that needs
StarCraft, a fixture is the only place the failure can be watched at all.

The `Old*` functions are the shipped expressions, transcribed from the line numbers named
in each context. They are here to be shown passing on data where the claim is false.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..' 'tools' 'plugin' 'sc-oracle-guard.ps1')
}

Describe 'Test-ScReached -- a comparison that can be skipped must count what reached it' {

    Context 'test-sunken-acquire.ps1:329 -- the whole plugin-vs-stock comparison skipped' {
        # `-Modes fanout` alone leaves $arms['<type>-observe'] unset, so the foreach body
        # hits `if (-not $f -or -not $o) { continue }` for every unit type, no assertion
        # runs, and the suite exits 0. There was no "arms compared: N" line to notice.
        It 'the OLD arm-loop asserted nothing and the run passed -- the defect' {
            $armsCompared = 0            # what the loop above produced
            $failures = 0                # what the suite reported
            $failures | Should -Be 0 -Because 'this is what a run with -Modes fanout printed'
            $armsCompared | Should -Be 0 -Because 'and nothing anywhere said so'
        }
        It 'zero arms compared is not a pass' {
            Test-ScReached -Count 0 | Should -BeFalse
        }
        It 'one arm pair compared is' {
            Test-ScReached -Count 1 | Should -BeTrue
        }
    }

    Context 'test-upgrade-queue.ps1:508 -- "the engine never ran two at once (0 of N samples)"' {
        # $bothAtOnce -eq 0 over an EMPTY sample list. If the drain loop never got a
        # reading -- the oracle timed out, the building was gone -- N is 0 and the
        # assertion passes having watched nothing.
        It 'the OLD expression passed with no samples at all -- the defect' {
            $seen = @(); $bothAtOnce = 0
            ($bothAtOnce -eq 0) | Should -BeTrue
            $seen.Count | Should -Be 0
        }
        It 'no samples is not a pass' { Test-ScReached -Count @() | Should -BeFalse }
        It 'and a sample list is counted, not just an int' {
            Test-ScReached -Count @('s1', 's2') | Should -BeTrue
        }
        It 'a single sample fails -AtLeast 2, for a min-over-samples reading' {
            # test-sunken-acquire.ps1:284: SunkenOrderAfter is one sample from the last
            # watch scan, while HP correctly uses min-over-samples. A Sunken that acquired
            # mid-window and went idle again reads "never acquired" in BOTH arms.
            Test-ScReached -Count 1 -AtLeast 2 | Should -BeFalse
            Test-ScReached -Count 2 -AtLeast 2 | Should -BeTrue
        }
        It 'a null count is a missing reading, not a zero' {
            Test-ScReached -Count $null | Should -BeFalse
        }
    }
}

Describe 'Test-ScWitnessed -- a claim needs the thing that makes it meaningful to have landed' {

    Context 'test-sunken-acquire.ps1:334 -- two arms that both did nothing agree' {
        # THE FIXTURE: neither arm's block ever got within the Sunken's range, so neither
        # was attacked, so the two "agree".
        BeforeAll {
            $script:fanout  = [pscustomobject]@{ Attacked = $false; InRange = $false }
            $script:observe = [pscustomobject]@{ Attacked = $false; InRange = $false }
        }
        It 'the OLD assertion passed on two no-ops -- the defect' {
            ($script:fanout.Attacked -eq $script:observe.Attacked) | Should -BeTrue
        }
        It 'is not a pass once the provocation has to have landed' {
            Test-ScWitnessed -Claim ($script:fanout.Attacked -eq $script:observe.Attacked) `
                             -Witness ($script:fanout.InRange -and $script:observe.InRange) |
                Should -BeFalse
        }
        It 'and IS a pass when both arms really got in range and agreed' {
            Test-ScWitnessed -Claim $true -Witness $true | Should -BeTrue
        }
        It 'a real DISAGREEMENT still fails even with the witness -- the witness only gates' {
            Test-ScWitnessed -Claim $false -Witness $true | Should -BeFalse
        }
    }

    Context 'test-building-parity.ps1:614 -- a refusal asserted with no evidence the click landed' {
        # after.N -eq before.N for a shift-click that was supposed to be REFUSED. A click
        # on empty ground produces the identical reading.
        It 'the OLD assertion passed for a click that hit nothing -- the defect' {
            $before = [pscustomobject]@{ N = 3 }
            $after  = [pscustomobject]@{ N = 3 }
            ($after.N -eq $before.N) | Should -BeTrue
        }
        It 'is not a pass unless the click is known to have reached the Barracks' {
            Test-ScWitnessed -Claim ($true) -Witness $false | Should -BeFalse
        }
    }
}

Describe 'Test-ScChanged -- the operation has to have moved something' {

    Context 'test-building-parity.ps1:734 -- the rally bucket "must have MOVED"' {
        # Its own comment says so; the assertion checked one-bucket + bucket == live.
        # UNRALLIED buildings share the same default packed value, so they are also one
        # bucket -- test-building-groups.ps1:613 has the guard this suite dropped.
        It 'the OLD assertion passed for buildings that were never rallied -- the defect' {
            $before = [pscustomobject]@{ RallyText = '(0,0)'; Buckets = 1 }
            $after  = [pscustomobject]@{ RallyText = '(0,0)'; Buckets = 1 }
            ($after.Buckets -eq 1) | Should -BeTrue
        }
        It 'is not a pass when the rally point did not move' {
            Test-ScChanged -Before '(0,0)' -After '(0,0)' | Should -BeFalse
        }
        It 'and IS a pass when it did' {
            Test-ScChanged -Before '(0,0)' -After '(1216,832)' | Should -BeTrue
        }
        It 'a missing reading on either side is not a change' {
            Test-ScChanged -Before $null -After '(1216,832)' | Should -BeFalse
            Test-ScChanged -Before '(0,0)' -After $null | Should -BeFalse
        }
    }
}

Describe 'Test-ScExactRefund -- "the money came back" is not "refunds EXACTLY"' {

    Context 'test-upgrade-queue.ps1:615' {
        It 'the OLD assertion passed for a refund of the wrong size -- the defect' {
            $paid = 150; $back = 25
            ($back -gt 0) | Should -BeTrue
        }
        It 'a partial refund is not an exact one' {
            Test-ScExactRefund -Paid 150 -Refunded 25 | Should -BeFalse
        }
        It 'an over-refund is not either' {
            Test-ScExactRefund -Paid 150 -Refunded 300 | Should -BeFalse
        }
        It 'the exact refund passes' {
            Test-ScExactRefund -Paid 150 -Refunded 150 | Should -BeTrue
        }
        It 'nothing charged and nothing returned is the vacuity, not the pass' {
            # The trap in the obvious repair: `$back -eq $paid` reads 0 -eq 0 as agreement
            # for an arm in which the start was never paid for at all.
            Test-ScExactRefund -Paid 0 -Refunded 0 | Should -BeFalse
        }
    }
}

Describe 'Get-ScOverlap -- a negative must be intersected with its positive' {

    Context 'test-combat-death.ps1:1098 -- "gone from the row" was never intersected with "dead"' {
        # THE FIXTURE, issue #45's shape exactly: unit t4 did not die. It walked out of the
        # drag box, so a fresh box does not list it, so it counts as "missing".
        BeforeAll {
            $script:beforeTags = @('t1', 't2', 't3', 't4')
            $script:afterTags  = @('t1', 't2')            # t3 died; t4 merely left the box
            $script:deadTags   = @('t3')
            $script:missing    = @($script:beforeTags | Where-Object { $script:afterTags -notcontains $_ })
        }
        It 'the OLD assertion passed on a survivor that only left the box -- the defect' {
            $script:missing | Should -Be @('t3', 't4')
            ($script:missing.Count -ge 1) | Should -BeTrue
        }
        It 'the intersection with the dead list names only the unit that really died' {
            $confirmed = Get-ScOverlap -Set $script:missing -Against $script:deadTags
            $confirmed | Should -Be @('t3')
        }
        It 'and a run where NOTHING that vanished had died has an empty intersection' {
            # Which is the state the repaired assertion must fail on, and the old one passed.
            (Get-ScOverlap -Set @('t4') -Against $script:deadTags).Count | Should -Be 0
        }
        It 'survives an empty or null side without throwing' {
            (Get-ScOverlap -Set @() -Against $script:deadTags).Count | Should -Be 0
            (Get-ScOverlap -Set $null -Against $null).Count | Should -Be 0
        }
    }

    Context 'test-combat-death.ps1:977 -- disjoint by construction, in BOTH directions' {
        # A unit the gate DROPS never reaches the FANOUT select: tag list (sc_fanout.cpp:759
        # continues before the tag append), and a unit the gate WRONGLY PASSES produces no
        # drop verdict at all. So $deadTags and $emitted can never intersect, whatever the
        # gate does -- the assertion is structurally unable to fail in the shipped arm.
        It 'the OLD assertion passed with the two lists drawn from disjoint sources' {
            $deadTags = @('t7', 't8')          # only ever populated from DROP verdicts
            $emitted  = @('t1', 't2', 't3')    # only ever populated from emitted Selects
            @($deadTags | Where-Object { $emitted -contains $_ }).Count | Should -Be 0
        }
        It 'the repair is a POSITIVE control on the same operator and namespace' {
            # If LIVE tags do not appear in $emitted either, the comparison is not
            # measuring membership -- it is comparing two vocabularies that never meet, and
            # its zero means nothing. AGENTS.md: prove the pattern positive first.
            $liveTags = @('t1', 't2')
            $emitted  = @('t1', 't2', 't3')
            (Get-ScOverlap -Set $liveTags -Against $emitted).Count | Should -BeGreaterThan 0
        }
        It 'and it FAILS when the tag namespaces really are unrelated' {
            $liveTags = @('unit-1', 'unit-2')       # e.g. a parser change to the tag format
            $emitted  = @('0x0A1B2C3D')
            (Get-ScOverlap -Set $liveTags -Against $emitted).Count | Should -Be 0
        }
    }
}
