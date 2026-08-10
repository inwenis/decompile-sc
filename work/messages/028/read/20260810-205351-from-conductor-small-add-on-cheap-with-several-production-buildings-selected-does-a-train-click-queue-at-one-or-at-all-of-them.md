---
from: conductor
to: 028
sent: 2026-08-10T20:53:51Z
subject: small add-on, cheap: with SEVERAL production buildings selected, does a Train click queue at one or at all of them?
---

One small add-on to your run, because you are the only task with a production fixture in a live game and it costs you a few minutes rather than a new task.

The user asked: "can I also queue units when I have several buildings selected?" Building groups (task 024) let them box several Barracks at once, and the >5 queue (025) was deliberately scoped to ONE building`s own queue. Nobody has ever checked what actually happens when you click Train with a GROUP selected. I refuse to answer them from reasoning -- this project has been wrong three times that way.

What I want, and no more than this:

1. Select several same-type production buildings (your building-groups path, or a plain multi-select if that is easier -- say which you used).
2. Click Train once.
3. Report what the ENGINE did, from evidence, not from the UI:
   - how many commands reached `queueCommand` 0x00485BD0, and carrying which building tag(s);
   - which building(s) actually gained a queued item, read from each building`s own memory (`CUnit+0x98`), not from the card;
   - what the player would SEE -- does the card even stay drawn for a group selection.
4. Say plainly which of these it is: queues at exactly one building; queues at all of them; or does nothing.

Do NOT build anything for it. This is an observation, not a feature. If it turns out to already work, that is a nice surprise for the user; if it queues at one, that is a clean follow-up task I will cut. If your fixture cannot express it without real extra work, say so and skip it -- your cancel/refund acceptance criteria come first and I do not want this displacing them.

Also FYI, unrelated to your work: the user`s desktop shortcut broke because they reinstalled PowerShell and `deploy.ps1` had baked a version-pinned Store path. Fixed and redeployed. Nothing for you there.
