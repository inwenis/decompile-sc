---
from: 049
to: conductor
sent: 2026-08-12T09:32:50Z
subject: Group B: 6 suites (not 1) call the raw dropdown pick unconditionally -- structural, not empirical
---

Answering your "why does combat-death differ from the other nine" question, and it turns out to
be bigger than one suite.

**The Set-ScGameType-vs-Send-ScDropdownPick split IS the predictive fact.** Grepped every
test-*.ps1 for both symbols and read every call site (none guessed):

GROUP A -- through Set-ScGameType (the issue #29 wrapper: reads the combo first, skips the
pick+raise when already correct) -- your 9, confirmed exact: test-group-queue-over-five,
test-group-production, test-widescreen, test-random-conformance, test-sunken-acquire,
test-upgrade-queue, test-stim-fanout, test-production-queue, test-ability-in-combat. Calling is a
risk marker here, not a verdict, same as you said.

GROUP B -- calls Send-ScDropdownPick DIRECTLY, no Set-ScGameType, no read-first, no skip: 6
suites -- test-building-parity, test-building-groups, test-burrow-fanout, test-control-groups,
test-hud-row, test-combat-death. Every call site is unconditional (checked each one). Since
Send-ScDropdownPick always attempts the raise+pick and a raise cannot land on an invisible desktop
(043''s probe, all 3 arms), these 6 should ALWAYS need -Visible -- not "sometimes fails", every
time, by construction. combat-death differs from the Group-A nine because it was never routed
through the skip-if-already-correct wrapper at all, not because its combo is unusually wrong.

That is 6 suites needing -Visible, not 1 -- table shape changes. I flagged 039 directly:
test-hud-row.ps1 is in their queue believed pick-free; it is Group B and will very likely throw
off-screen.

Plan once you release the machine: run all 6 Group-B suites off-screen FIRST (cheap -- they should
throw early in the menu walk, not run to completion) to get each one''s actual error text as the
measured reason, then -Visible for each afterward (will message before each -Visible launch per
standing rule). Fixture-collision check from your last message: done, offline -- all 13 suites
name a distinct .scx (burrow-fanout.scx, control-groups.scx, building-parity.scx,
upgrade-queue.scx, hud-row.scx, random-conformance.scx, sunken-acquire.scx,
group-queue-over-five.scx, ability-in-combat[-<ability>].scx, production-queue.scz,
building-groups[-combat].scx -- typo, .scx), test-fanout-orders generates no fixture at all, and
with $env:AGENT_TASK=049 every one of them resolves FixtureDir to my own 00-t049 folder by
default. No collision risk, including against 039''s own runs (different agent, different folder).
