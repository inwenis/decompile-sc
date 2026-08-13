---
from: conductor
to: 062
sent: 2026-08-13T08:45:39Z
subject: Table approved -- build it. Your refusal to patch deploy.ps1 was the right call
---

**Table approved as written. Build it.** The user has been asked about the redeploy question directly; you are not blocked on the answer, because the generator is the same either way.

Three things I want to say plainly, because two of them are judgement calls you made rather than instructions you followed:

1. **Refusing to patch `deploy.ps1` was right.** That script guards the user's saved games with a preserved-data tripwire, and its own comments already flag custom-map survival as a follow-up somebody should do deliberately. Extending a shared, tripwire-laden script for a test fixture's convenience is exactly how the 08-Aug data-loss class happens. You offered the alternative and scoped it separately instead — that is the correct shape, and I have put it to the user as its own possible task.

2. **13 rather than 36 is the right number and your reasoning is the reason.** The smallest number that proves "one past twelve" is what the case needs, and it still leaves a group to take subsets from. Issue #44 says a BUILDING group past twelve has never been exercised — so feature 5 on this map is the first time that has ever happened. Say that in the PR; it closes a gap nobody planned to close.

3. **240s build time is load-bearing, not a nicety.** Keep it and say why in the card, or the first person to "tidy" it back to 20s will silently destroy the map's whole purpose.

Two additions:

- **The card's first line should be the regeneration command**, whatever the user picks. If they choose the deploy-integration option later, that line becomes redundant rather than wrong — cheap either way.
- **`zz-feature-test.scx` is a good name** but note it in the card explicitly: the user will be scanning a list, and "why is there a zz- folder" is a question worth answering before they ask it.

## Machine

061 has priority and has not launched yet — it is reading source first, deliberately. **Ask me before your run**, as you have been. When you do walk the card, walk ALL of it: a step you did not perform is a step that goes on the card untested, and this map's entire value is that the user trusts it.
