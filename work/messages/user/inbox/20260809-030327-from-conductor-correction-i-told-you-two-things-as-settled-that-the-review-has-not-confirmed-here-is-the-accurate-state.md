---
from: conductor
to: user
sent: 2026-08-09T03:03:27Z
subject: CORRECTION: I told you two things as settled that the review has not confirmed - here is the accurate state
---

I have to walk back part of what I told you tonight. Both messages were mine, sent before review, and the review found the evidence underneath them is weaker than I represented.

**1. "The sunken/medic thing is not our bug, tested four ways" — the test did not exercise the mod.**

The fixture used **6 units**. Every feature we have built needs more than twelve to activate: the fan-out, the extra circles, the paged row. At 6 units none of them ran. So the comparison genuinely was plugin-vs-stock, but with the plugin''s actual behaviour dormant on both sides — it answers "does loading our DLL change how a sunken acquires targets", not "does our fan-out change it". And your report came from a session where you were selecting more than twelve.

The three vanilla explanations still stand on their own — one target at a time, medics healing each other, the range geometry — and they do explain what you described. But I should not have told you it was cleared as a plugin question. It is being re-run above twelve units.

**2. "Our mod is cleared, our commands do not interrupt units" — the headline number flips depending on an undisclosed choice.**

The measurement compares the ability window against control windows either side of it. There were two controls and they disagreed by a factor of two and a half. The script silently used the LARGER one, which is the lenient choice — and with the smaller one the same run would have FAILED the threshold instead of passing. The reported "quieter than the control" figure changes sign depending on which control you pick. The run also sat exactly on the boundary the script itself defines as "too unstable to measure".

So the honest state is: **not established either way**, on that run. It is not evidence that we DO interrupt orders — but it is not the clean negative I gave you.

**What I am doing:** the worker is re-running Q2 above twelve units, asserting against both controls and reporting both numbers, and re-running Q3 on a steadier fight if the current one cannot decide it. If any answer changes I will tell you immediately.

**What still holds:** your stim question (all units get it, each pays its own HP, the split falls on the health line) survived review — one reviewer attacked exactly that and was refuted. The harness fixes hold. The control-groups feature you are playing is unaffected by any of this.

I would rather correct this twice than leave you believing a cleaner story than the evidence supports. The mistake was mine: I relayed both answers to you when they arrived rather than waiting for the review that exists precisely to catch this.
