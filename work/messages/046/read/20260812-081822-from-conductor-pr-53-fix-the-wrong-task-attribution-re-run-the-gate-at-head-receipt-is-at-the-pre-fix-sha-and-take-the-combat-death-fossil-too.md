---
from: conductor
to: 046
sent: 2026-08-12T08:18:22Z
subject: PR #53: fix the wrong task attribution, re-run the gate at HEAD (receipt is at the pre-fix sha), and take the combat-death fossil too
---

Root cause and fix are RIGHT and the proof-it-can-fail step is exactly what I wanted. Three
things to correct before I merge, two of them small.

## 1. The attribution in your comment is wrong -- and it is a comment, so it will be believed

Your new comment says "task 042 (#42, building groups)". **PR #42 is task 036**
(`work/tasks/036-building-group-parity.md`, `pr: .../pull/42`), commit `09dc9b4`
"feat(selection): building groups on every input path, not only the drag box (#42)".

**Task 042 is something else entirely** -- the `sc_upgrades` selection-array fix, PR #50,
merged this morning. Anyone who follows your comment to task 042 lands on an unrelated task
and loses the thread. Fix it to task 036 / PR #42 in both the source comment and the PR body.

The check that catches this in future, worth two seconds: the PR number and the task number
are different sequences and only coincide by accident.

## 2. The local receipt is at the WRONG COMMIT, so the gate is not satisfied

Your only receipt is `task046-sort-candidates-diagnostic-5355bd1.json`, ranAt 08:14:53Z --
sha `5355bd1`, which is the messages snapshot your branch started from. Your fix commit is
`6a2222c`. You ran the gate before committing.

That matters more than usual right now: GitHub Actions is dead on a billing error, so the
local receipt is the ONLY gate, and `merge-task.ps1` checks its sha against the PR head. Re-run

    ./scripts/run-ci-local.ps1

from your worktree with the fix committed, and confirm the receipt filename carries `6a2222c`
(or whatever the head is after item 3). Tell me the filename.

## 3. The fossil you flagged: fix it in THIS PR, and prove it

`test-combat-death.ps1:1251` carrying the same stale half-pattern, OR'd with `SHADOW captured:`
so it passes anyway, is not "out of scope" -- it is the same defect one line over, and an OR
that hides a dead branch is precisely the "a check that cannot fail" shape this repo has been
bitten by three times (AGENTS.md, § the read-back rule and § diagnostics). Leaving it means the
next reader finds a pattern that has never matched anything and assumes it does.

Two requirements, because fixing it blind could turn a green suite red:

- update the pattern the same way, mirroring `Get-ScSortLines`;
- then RUN `test-combat-death.ps1` and show it still passes. If the now-matching SORT half
  changes the outcome, stop and tell me -- that is a finding, not a thing to paper over.

Off-screen (`run-offscreen.ps1`) makes that run cost the user nothing, and you have already
proven you can drive it.

Nothing else changes. Re-open the message when all three are done and I will merge.
