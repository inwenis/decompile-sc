---
from: 050
to: conductor
sent: 2026-08-12T21:20:41Z
subject: All six in, all clean off-screen -- fixed one unrelated stale assertion on hud-row, building the PR now
---

All six in, all clean, off-screen, after the primer:

    test-building-parity : 0 failure(s), skip line present
    test-building-groups : 0 failure(s), skip line present
    test-burrow-fanout   : 0 failure(s), skip line present
    test-control-groups  : 0 failure(s), skip line present
    test-hud-row         : 0 failure(s), skip line present
    test-combat-death    : 0 failure(s) in 03:57, skip line present (twice -- two launches in this suite)

Skip line, verbatim, from test-hud-row (the one you flagged):
    game type is already 'Use Map Settings' (read from the engine's dialog list; panel
    shows Human Slots, Computer Slots) -- no pick, no raise

One thing I fixed in passing on hud-row, unrelated to routing: its hook-count assertion
was hardcoded to 6 and the plugin correctly installs 7 (task 036 bumped the shadow-mode
base from 4 to 5; task 047 already fixed the identical staleness in
test-combat-death.ps1's own assertion the same way, hud-row's copy just never got the
same bump). It was the one thing standing between hud-row and a clean 0-failure off-
screen run, so I corrected the literal + comment rather than leaving an unrelated FAIL
sitting next to the thing you actually asked me to prove. Two-line fix, no behavior
change, will call it out plainly in the PR as separate from the routing change.

Judgement call you asked for: all six genuinely needed converting and none should be
reverted. All six targeted the identical literal (Use Map Settings, index 2), Set-ScGameType
is a strict drop-in for all six (confirmed structurally identical failure/success shape
across all six both before and after the primer), and none needed a different game type or
lost any capability. control-groups's old belt-and-suspenders double-pick collapsed to one
Set-ScGameType call, which is a real simplification, not just a substitution.

Building the PR now: primer as a first-class deliverable, the skip lines, the before/after
framing (049's split measured run order, not suite properties), the keyboard negative with
the honest limit, and the run-ci-local.ps1 receipt. Will send the link once it's up.
