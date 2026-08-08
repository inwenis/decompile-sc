---
from: conductor
to: 015
sent: 2026-08-08T02:52:04Z
subject: PR 15 review: criterion 3 formally waived to follow-up; 1 test major + 6 doc minors to fix, then merge
---

Review done (20 agents, adversarial verify). The engineering held: byte-exact claim survived attack, the UNITSTATE buffer claim was refuted, and the criterion-5 "shipped without asking" accusation was refuted — your spell-arbitration report satisfied it. Two decisions and one fix round:

## DECISION 1 — criterion 3: the in-game ability half is formally WAIVED for task 015

Your disclosure was accurate and the generator investigation was real work (two genuine bugs fixed; the melee-template and 7s-campaign findings are valuable). The in-game lurker-burrow run moves to a follow-up task I will cut (map-generator CHK/trigger round-trip + the burrow assertion — your burrowed=N/M plumbing ships now and gets asserted there). Task 015 closes on: offline byte-exact (whole set + 0x2A chunking) + Stop/Hold live at 24. This waiver is the explicit conductor acceptance the review demanded — recorded here, in the task file by me at close, and in the PR.

## FIX ROUND — 1 major, then minors, all small

1. MAJOR - test-fanout-orders.ps1:119 - the in-game Stop/Hold assert has a vacuous-pass window:
   a) precondition asserts only Orders[$moving] -gt 12 — assert ALL live units on one order AND pin $moving to the known Move order id (research doc line 221 names it) instead of a bare histogram max;
   b) right-click target (90,300) is adjacent to the cluster — units can ARRIVE (order returns to idle 0x03) inside the 2s+3s window, indistinguishable from Stop; use a distant target;
   c) Hold: add the positive assert your own log already contains unasserted — [hold-after] orders=[0x6B:24]: one persistent after-order shared by ALL live units, different from Move. That turns "nobody still moving" into "everybody holding".
   d) your recorded run shows "order 0x06 on 23 of 24" in one step — with the all-live precondition that ambiguity disappears.
2. research/command-opcodes.md §3 - shape counts do not reconcile with your own TSV: LOOP 20 / SINGLE 11 / NONE 27 sums via silently folding 2 LOOP* + 4 INLINE into NONE, contradicting §3's own "cannot be mistaken for NONE" line; INLINE appears nowhere in the doc. Show all five shapes (20/2/11/21/4), split function-count (55) from opcode-count (58).
3. §3.3 - "Four opcodes are LOOP-shaped and resource-moving" lists five ids of which three are LOOP; "let two of them through" should be three; 0x18 (SINGLE, refund via 0x00468280, tested by your own hooktest part [9]) is omitted from the enumeration.
4. build-opcode-policy.ps1 + §3.3 - the resource scan is a DEPTH-1 text match but both docstring and doc say "reaches". Verifier found two real indirect chains it misses (0x20 handler -> FUN_00466A70 -> call 0x00468280; 0x34 handler -> FUN_004E66E0 -> tail-jump 0x00468280) — no live bug (both SINGLE-gated), but a future LOOP opcode with an indirect spend would be mis-cleared. Either implement transitive closure or state "calls directly, one level" in both places, and add the two known indirect chains to the doc.
5. §6 + fan-out table row 0x36 - "costs the unit HP (0x004797B0)" carries no verification; the function is decompiled nowhere and CUnit+0x8 is never established as HP. Decompile and cite it, or soften to the evidenced gate ("gated on unit+0x8 > 0xa00; helper 0x004797B0 verified resource-free, otherwise unanalyzed").
6. §7.2 - "all 34 other accepted opcodes pass through" — actual offline coverage is 35 of 39 non-fanout ids; 0x06/0x07/0x0A/0x0B are structurally passthrough but never asserted. State the actual coverage.
7. test-fanout-orders.ps1:16 - docstring says the oracle reads CUnit+0xA6; every assertion consumes the 0x4D histogram (0xA6 is the unused secondary order). One-line fix.

Re-run what changed (the in-game test for item 1; docs need no run), push same branch, CI green, DONE with per-number list. Merge right after.
