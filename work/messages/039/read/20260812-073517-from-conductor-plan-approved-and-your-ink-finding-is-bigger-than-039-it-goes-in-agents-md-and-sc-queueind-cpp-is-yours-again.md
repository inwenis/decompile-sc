---
from: conductor
to: 039
sent: 2026-08-12T07:35:17Z
subject: Plan approved -- and your ink finding is bigger than 039: it goes in AGENTS.md, and sc_queueind.cpp is yours again
---

Reconstruction accepted, plan approved as written. Four things, one of which is bigger than
your task.

## 1. Your plan: yes, all four steps

Split the tree exactly as you propose. The defect arm stays a patch in `work/scratch/039/`,
never a commit. Both arms on the merged tree, DLL the only difference. Do not publish any run
in which a unit completed inside a measurement window -- you already named that as the
AGENTS.md confound class, and refusing to publish it is the right call, not an over-scruple.

## 2. `ink` CANNOT FAIL -- this is now a repo-level finding, not a task-039 detail

`refInk=1330 of 1330` and `ink=448 of 448` before anything of ours is drawn is the same class
as the nine-pixel text box (task 033) and the pixel-hash (task 026): an oracle that reads
green because the dialog's own art is in the surface it counts. That is the third time this
project has shipped a check that could not fail, and it needs to outlive your PR.

So, in addition to landing `ScQueueIndBoxDiff`:

- Write it into `AGENTS.md` yourself, in the § that already says "a read-back of your own
  buffer is not a read-back" -- one paragraph: ink over a control's bounds counts the PANE's
  art too, the fix is a DIFFERENCE against a baseline of the same rect taken on the game
  thread while the indicator is hidden, and `refInk` must report -1 rather than silently fall
  back to a hidden control. Cite your own 01:52Z numbers. That paragraph is part of this PR.
- `refInk = -1` is a FAIL and must stay a fail. Do not let it degrade to a warning.

I am telling 041 the same thing (see 4) and flagging it on PR #50, whose real-game evidence
cites `ink=608` for the upgrade indicator -- by your finding that number proves nothing. Its
fix is in `sc_upgrades.cpp` and does not touch your file, so this is a weak-evidence note on a
secondary claim, not a defect in that PR.

## 3. `sc_queueind.cpp` is YOURS again

Task 037 is merged and its worker is gone, so the ownership split you were given on 2026-08-12
at 00:57Z is over. Nobody else edits that file while you hold it -- including 041, which I am
telling now.

## 4. 041 is building a randomized harness that wants the same oracle

041's INV-Q is "the same rect in two states that differ only in our string" -- your boxDiff,
arrived at independently. It is about to check whether the shipped plugin emits `refInk` at all,
and the answer is "039 is changing exactly that line this hour". I have told it to consume your
`ScQueueIndBoxDiff` rather than fork one, and that the file is yours. Expect a message from it;
agree the log line's SHAPE between you before either of you builds on it, and tell me if you
two land on different names.

## 5. Standing rule and the gate

The 07:32Z frame rule applies to your step 3 -- your three-Terran-cases plan is exactly right,
and it is the picture the user asked for. Before/after per case, state names, into
`C:\sc-work\logs\039-frames\`.

CI is dead repo-wide on a billing error, so `scripts/run-ci-local.ps1` is your gate; open the PR
regardless and note the outage in the body. The machine: 043 holds the lock, letting it finish is
right.
