---
from: 046
to: conductor
sent: 2026-08-12T08:39:32Z
subject: PR #53: all three fixed -- attribution, receipt at 6ebe7b4, combat-death fossil fixed + a new finding
---

All three done, PR #53 updated: https://github.com/inwenis/decompile-sc/pull/53

## 1. Attribution fixed
Task 042 -> task 036 (#42, commit 09dc9b4), in both the source comment
(test-selection-circles.ps1) and the PR body.

## 2. Receipt re-run at the fix HEAD
`task046-sort-candidates-diagnostic-6ebe7b4.json` -- ran after both follow-up commits,
PASS (77 Pester, hooktest 0 failures, ruff skipped -- not installed).

## 3. test-combat-death.ps1 fossil fixed and proven
Same one-line pattern fix, mirroring Get-ScSortLines. Ran it live (dropdown pick needs
foreground, so -Visible, not off-screen) -- the touched assertion ("the selection still
ran through our own hooks after the losses") passes both before and after; the
now-matching SORT half does not change the outcome.

**New finding while running it, not fixed here:** the SAME suite also fails
`[5] all hooks installed (7/7)` against a hardcoded `-eq 6`. Traced source-only (no
extra launch): task 036 also bumped the shadow-mode hook base 4->5
(`unit_IsStandardAndMovable`), so this suite's real expected total is now
`5+circles(1)+hudrow(1)+queueind(0)=7` -- which the engine reports correctly. The
test's magic number was never bumped. Same shape as this PR, same file, different
check, a different task's (036's) miss -- flagged in the PR body rather than folded in,
partly because confirming a fix needs a game launch and those are on hold for 041.
Want it as a follow-up one-liner once released, or fold into this PR?

Also hit one unrelated one-off flake mid-verification: test-combat-death.ps1's very
first launch this session had its Phase A box-select read 0 units (tips dialog never
appeared that one time). Reran clean -- not reproduced, not investigated further, not
in the PR.

## Machine / launch-hold state
Holding as instructed -- no new game launches from me since the retry that was already
in flight when your message landed. That retry (test-combat-death.ps1, visible) is the
one referenced in item 3 above. Nothing of mine left running; launch lock clean. Idle
and listening.
