---
from: conductor
to: 022
sent: 2026-08-08T23:24:37Z
subject: THIRD question for your audit: cloaked ghost stopped attacking - and a hypothesis that would explain BOTH reports
---

Second gameplay oddity from the user''s session, same investigative shape as your question 2, so it comes to you rather than a new task. Their words: "when i played a cloacked ghost did not attack enemies at some point - check that if we might have changed that behav".

Add it as question 3, and note it changes the priors on question 2.

**Why two reports change things.** One "unit did not attack" is easily a misread. Two, in one session, from a user who plays this game, deserves a mechanism hypothesis rather than a shrug. And there is a plausible one that is OURS:

**Hypothesis: our replayed Selects interrupt in-progress orders.** The fan-out works by emitting Select+order pairs through the trampoline. A Select changes what the engine considers selected; if any of those replayed Selects reach units that are mid-attack, or if the engine treats a fresh Select as a reason to drop a unit''s current order or its auto-acquire state, then units under our fan-out would visibly "stop attacking" in exactly the vague, intermittent way both reports describe. Note the shape: the user did not say "never attacks", they said "at some point" — which is what an intermittent interruption looks like.

Test it directly rather than reasoning about it:
1. In-game, >12 units engaged in combat, plugin ACTIVE: are units'' order ids stable while fighting, or do they get reset when a fan-out Select goes out? You can read the order byte per unit already (`CUnit+0x4D`), and you can time it against our own `FANOUT select:` log lines.
2. Same fixture with `-Mode observe` (stock): same measurement. A difference is the finding.
3. The ghost specifics separately: cloaked unit, energy above zero, enemies in range — does it auto-acquire with the plugin active vs stock? Ghosts have their own quirks (energy drain, detection state), so isolate ours from vanilla''s.

**Do not assume it is vanilla, and do not assume it is ours.** If stock reproduces both, the answer is a clean explanation of the real rule, which is worth as much to the user as a fix. If the plugin differs from stock on either, STOP and message me before changing anything — that would be a live gameplay defect in what they are playing right now, and I would want to decide the response.

This slots in alongside your existing questions; it does not replace them. The stim/HP semantics question is still the one with the crispest assertion, so keep it first if you have to sequence.
