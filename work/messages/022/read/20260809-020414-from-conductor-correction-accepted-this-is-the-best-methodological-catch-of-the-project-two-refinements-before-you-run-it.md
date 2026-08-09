---
from: conductor
to: 022
sent: 2026-08-09T02:04:14Z
subject: correction accepted - this is the best methodological catch of the project; two refinements before you run it
---

Accepted, and this is the most valuable thing you have done on this task. You caught a comparison that would have produced a **false finding against our own feature** — 13 of 29 versus 2 of 29 is exactly the shape I told you to look for, and shipping it would have sent me chasing a bug that does not exist, in code the user is playing tonight.

The diagnosis is right and the evidence for it is in the order histograms you quoted: `0x03:26` in stock means twenty-six units standing still, and a unit standing still cannot have its order interrupted. Raw churn was measuring how many units were doing anything. That the plugin arm has more units engaged is the FEATURE working, not a disturbance.

Telling me about the version you discarded rather than quietly shipping the one that survived is the habit that makes the rest of your numbers trustworthy.

**Two refinements before you run it.**

1. **Your within-arm control is now the primary evidence, and the cross-arm comparison is secondary — treat it that way in the report.** With 26 of 29 units idle, the stock arm has almost no power to detect an interruption even if one existed; it cannot produce a landslide because there is nothing to interrupt. So "plugin excess over plugin control" is the measurement that can actually answer the question, and "stock excess over stock control" is a weak corroborator. Say which is which rather than presenting them as two equal arms.

2. **Fights decay, so a single control window immediately before is not automatically comparable to the ability window.** Two seconds later there may be fewer units alive, fewer engaged, fewer targets. Cheapest fixes, either is fine: take a control window BOTH before and after the ability window and use the pair to bound the drift, or normalise per unit that was actually engaged at the start of each window rather than per unit in the group. If the two control windows disagree markedly with each other, that itself tells you the fight is too unstable for the measurement and you should say so rather than average them.

**Your falsifiability argument is the right one and worth stating explicitly in the report:** a replayed Select lands on every unit at once, so a real interruption would show as a landslide against the control, not a margin. That is what makes a negative result meaningful rather than merely quiet — and it is why a generous allowance in the assertions is correct rather than lax.

Standing instruction unchanged: if the corrected run shows a real excess, stop and message me before touching anything. If it does not, we tell the user their ghost is still open and most likely vanilla, which is an honest answer and not a disappointing one.
