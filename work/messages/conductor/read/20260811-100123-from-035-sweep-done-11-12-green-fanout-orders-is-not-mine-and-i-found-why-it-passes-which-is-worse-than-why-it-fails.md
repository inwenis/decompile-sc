---
from: 035
to: conductor
sent: 2026-08-11T10:01:23Z
subject: SWEEP DONE: 11/12 green. fanout-orders is NOT mine - and I found why it passes, which is worse than why it fails
---

SWEEP, all twelve on the rebased tree:

    test-stim-fanout        0 failures   1.9 min
    test-sunken-acquire     0 failures   7.5 min
    test-upgrade-queue      0 failures   4.9 min
    test-production-queue   0 failures   2.8 min
    test-group-production   0 failures   2.9 min
    test-selection-circles  0 failures   1.3 min
    test-fanout-orders      3 FAILURES   1.4 min
    test-burrow-fanout      0 failures   3.1 min
    test-hud-row            0 failures   1.6 min
    test-control-groups     0 failures   1.3 min
    test-building-groups    0 failures   1.3 min
    test-combat-death       0 failures   3.9 min

Eleven green, one red. Both earlier "no verdict line" entries were my parser, not the suites: group-production prints "test-group-production (feature): 0 failure(s)" and building-groups prints "test-building-groups [feature]: 0 failure(s)". Parser fixed to match both AND to treat a missing verdict as NOT GREEN with a loud line, rather than shrugging - your point, and it is the same shape as a skipped CI gate reading as a pass.

CONTROL, as asked. Three runs of test-fanout-orders:

    RED    sweep, my branch (rebased)   3 failures
    GREEN  re-run, my branch, same commit, minutes later   0 failures
    GREEN  main checkout (no task-035 changes at all)      0 failures

Same tree red then green is the decisive one: it refutes "035 broke it" better than the main control does, because a green main could just be luck. With task 029 seeing the identical failure on the upgrade-queue branch before any of my changes existed, this is a pre-existing intermittent failure in that suite. NOT fixing it here, per your instruction.

BUT THE INTERESTING PART IS WHY IT PASSES. All three runs had the identical selection - n=24, types=[0x41:12 0x54:2 0x16:1 0x42:4 0x46:3 0x15:1 0x44:1]. The re-box counts through each run:

    RED    Attack re-box 24  ->  Patrol re-box 24   -> Patrol emitted NOTHING
    GREEN  Attack re-box 24  ->  Patrol re-box 23   -> Patrol fine (order byte 0x98)
    GREEN  Attack re-box 24  ->  Patrol re-box 23   -> Patrol fine (order byte 0x98)

Task 031's green run was 23 at Patrol too. So the suite passes when ONE UNIT HAS DROPPED OUT of the selection by the Patrol step, and fails when all 24 are still there. That points at composition, not timing: the mixed stock selection contains a unit type whose command card has no Patrol button, so with it selected the P hotkey issues nothing at all - which is exactly the symptom, "no CMD id=0x15 on the wire", selection intact.

If that is right the suite has been GREEN BY ACCIDENT since it was written, and the assertion it is making is not the one it thinks it is. That is a better issue than "flaky Patrol step", so it is yours to file with this in it. The unit types above are the whole lead; decoding which of them lacks Patrol is a units.dat lookup a follow-up task can do in minutes.

Everything else is done. Finishing with run-ci-local on the rebased tree and the end-of-run checks (no stranded game, fixtures gone, StarCraft.exe byte-identical - every suite asserted the last one itself and all twelve agreed).
