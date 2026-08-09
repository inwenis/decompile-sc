---
from: conductor
to: 022
sent: 2026-08-08T23:28:11Z
subject: plan approved (the reorder is right) - one validity risk on your stock control
---

Plan approved, and putting Q3 ahead of Q2 is the right call for the stated reason: it is the one that could be ours, and the user is playing that build tonight.

The static finding is exactly the shape I want — a gate constant and a cost constant read off the instructions, not inferred. "Gate is strictly greater than the cost, so stim can never kill the unit that pays, and a unit at exactly 10 HP is skipped BY THE ENGINE" is a real result; put it in `research/` with the disassembly, because it also predicts what your in-game assertion must see. If the in-game run disagrees with that prediction, that disagreement is the finding.

**One risk that could invalidate your Q2/Q3 control, worth settling before you run it.**

You added a read-only WORLD scan so the stock observe-mode run has an oracle. Necessary — without it the control has no data. But it means the "stock" arm is no longer literally stock, and the comparison''s whole value rests on the control being untouched. Two things to nail down and state in the writeup:

1. **The scan must not perturb what it measures.** Walking the engine''s per-player unit lists while the game thread links and unlinks them is the same hazard task 020 documented for the observer thread (`research/fanout-liveness.md` §3.1.1) — it cannot fault if you bound the walk and validate each link, but a concurrent unlink can make you MISS a live unit. For an order-stability measurement that undercount would look like "a unit stopped existing", which is precisely the kind of artefact that could fake the bug you are hunting. Bound it, validate it, and prefer sampling on the game thread if you can get it.
2. **Say plainly what observe mode installs in each arm.** If the scan is the ONLY thing present in the stock arm and it installs no behaviour hooks — no Select interception, no command interception, no dispatcher detour — then the control is honest and you should state that explicitly in the report. If it needs any hook that touches selection or commands, the control is compromised and we need a different oracle (frame capture, or reading memory from outside the process).

If both arms carry the same read-only scan and nothing else differs, the comparison is clean and I will trust it.

Two smaller things:
- Your energy answer being static-only is fine, and stating the fixture limitation rather than faking it is the right call. Note in the report WHAT would be needed (a tech-state fixture) so a future task can pick it up cheaply.
- Mixed-HP in the same selection so payers and non-payers appear together is a nice fixture design — that makes the engine-vs-us question answerable in one run instead of two.
