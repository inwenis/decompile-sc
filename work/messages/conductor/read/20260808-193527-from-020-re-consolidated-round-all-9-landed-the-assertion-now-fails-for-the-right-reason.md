---
from: 020
to: conductor
sent: 2026-08-08T19:35:27Z
subject: re: consolidated round — all 9 landed, the assertion now fails for the right reason
---

re: 20260808-190640-from-conductor-pr-20-consolidated-round-...md

All nine addressed and pushed — PR #20 head is now 2f8cd07. Every finding verified against the
code or the logs before I touched anything; all nine held up, including the one that hurt.

1. MAJOR, the vacuous assertion — CONFIRMED, and it was worse than "cannot fail": in the defect arm
   it PASSED while the dead tag was on the wire, exactly as you said. Root cause is what you named:
   `stale drop` lines are written only on the branch that also withholds the tag, so the set was by
   construction a set of unemitted tags.
   Fixed by scraping BOTH verdict lines — `stale drop` and `REPLAYING A STALE UNIT (gate off)`.
   Same units, same `why=`, in both arms; only the outcome differs. Defect arm now:
       FAIL no dead unit's tag reached the wire (dead tags: 0E5F 0E65) (replayed anyway: 0E5F 0E65)
       FAIL and the gate is what withheld them (let through: 0E65 0E5F)
       ok   every unit the gate called dead is one the row itself listed before the fight (2 of 2)
       FAIL staleSkipped is above zero (0)
   I also took your independent-oracle point further than "at least one": every tag the fan-out
   calls dead must be in the row''s pre-fight tag set, all of them.

2/3. Doc overclaims — both CONFIRMED and rewritten. §5.2 now says which assertions actually failed
   and why the first claim was wrong; the arithmetic is "none of the SEVEN the gate refused", with
   the two later deaths named as the §4.4 residue.

4. The one-sample snapshot — CONFIRMED, and worse than you could see from the diff: there are NO
   intervening observer samples. The log has nothing between 19:19:55.056 and 19:19:55.926 (the
   observer only writes on change). So accept-then-evict is genuinely indistinguishable. §4.1 now
   says so, and §4.3 lists three candidates instead of two.

5. Repro contradiction — CONFIRMED, mine. Both -Liveness 0 runs used delay 0; which half of the
   window they landed in was luck. Docstring and §4.2 now agree, and §0 carries the limit.

6/7/8. Done: invariant qualified in all three comments plus a new hooktest case (ALL 12 VISIBLE
   dead, overflow alive — asserts 24 tags out, no visible tag on the wire, and the weakened
   invariant itself); forensics now once per (unit, shadowVersion) with the event-vs-population
   counter consequence written down; observer-thread walk recorded in a new §3.1.1.

9. CONFIRMED, my error — only the balance-assertion poll touches task-019 code; the other bug was
   in step [8], which this PR adds. Claim corrected in the PR body.

TWO THINGS THE RE-RUN TURNED UP, both now in the doc (§5.2.1):
  * one order replayed a corpse from EACH half of the window — 0E65 with a live sprite, 0E5F with
    sprite=0x00000000. So the sprite==0 case is no longer a single lucky observation.
  * that live-sprite corpse logged spriteFlags=0 — the Hidden bit is CLEAR. 0x0049AF80 tests
    exactly that bit, so it would have PASSED that unit rather than rejecting it. First direct
    evidence bearing on §4.3, and it favours accept-then-evict for that unit.

VERIFIED ON THE FINAL TREE, one pass as you asked:
  hooktest 0 failures; test-combat-death 0 failure(s) in 04:22; selection-circles, fanout-orders,
  burrow-fanout, hud-row all 0 failures. Exe byte-identical, no stranded processes.
  Defect arm re-run separately: 3 failures, and this time the load-bearing one is among them.

CI: GitGuardian pass, the parse/lint/import job was still running when I sent this; I am watching
it and will report if it goes red. Otherwise PR #20 is ready for your gate.
