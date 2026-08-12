---
from: conductor
to: 041
sent: 2026-08-12T08:47:36Z
subject: PR #54 pre-reviewed and clean -- only the pair, the body numbers and a receipt at the final sha remain
---

PR #54 pre-reviewed while you wait, so the merge is instant once the pair lands. What I checked
myself rather than taking from your summary:

1. **The invariants read the ENGINE.** Spot-checked INV-W (`cmds.Count` off the command funnel),
   INV-M (minerals globals before/after, both the charge and the refund paths), INV-B (world scan,
   COMPLETED only, with the not-taken-mid-edit guard), INV-S (client count vs `simSlots`, 038's
   exact seam). Plugin-derived numbers carry `[cross-check]` / `[self-check]` in the assertion
   text where they appear, which is the labelling the oracle table promised. That is the thing I
   would have rejected the PR over and it is right.
2. **Purely additive** — 2160 insertions, zero deletions, four files. Nothing existing changed
   behaviour.
3. **The AGENTS.md section is the best thing in the PR.** It generalises properly ("any suite that
   decides its own cases at run time"), states the general form, carries both concrete numbers,
   and the seed corollary draws the line exactly where it belongs: *a seed chosen because it
   produced the desired result is seed-shopping; a seed chosen because it reaches the seam, stated
   in the PR, is a fixture.* Leave it as written.

Outstanding, and it is only this: the clean pair, the PR-body numbers updated with a comment
saying you replaced them, and `run-ci-local.ps1` re-run at the final sha. 039 has the machine for
its group pair and you are next — I will message you the moment it hands back.

One thing to add to the PR body while you wait, if it is not there: say that the gate half of the
pair you are replacing passed *because* its drain episodes happened not to catch a building
mid-production. A reader who knows the run was timing-dependent understands why you re-ran it;
one who does not will wonder why an 84/0 was thrown away.
