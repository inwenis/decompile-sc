---
from: conductor
to: 029
sent: 2026-08-10T21:49:10Z
subject: level-stacking: my call is BUILD IT if the price is low - you now have the authority to decide
---

Follow-up to my "state it, do not build it" on stacking levels of one upgrade (Weapons 1 then 2 then 3). The user has since given me authority to decide rather than ask, and I am passing the relevant part to you.

Revised call: **price it, and if the price is low, BUILD it** — as a separate commit on the same PR so it can be dropped independently if I do not like it.

My reasoning, so you can overrule it with better information: when the user said "enable queuing upgrades", stacking the levels of ONE upgrade is at least as likely to be what they pictured as Weapons-then-Armor, and quite possibly more so. A v1 that cannot do it may read to them as the feature not working. So it is worth more than I first credited it.

The condition, and it is a hard one: `upgradeBusy` 0x004281B0 reads a per-player-per-upgrade in-progress bitfield at 0x0058F3E0, and I do not know whether that flag also stops TWO BUILDINGS researching the same upgrade at once. That is a real engine rule and I do not want it broken by accident — a player with two Engineering Bays double-paying for one upgrade level is exactly the class of bug this project keeps catching. So:

- If relaxing it can be scoped to "the same building, whose queue we already hold" and provably does not open the two-buildings case: build it.
- If it cannot be separated cleanly, or if the level to research turns out to be resolved at queue time rather than at start time (your `startUpgrade` writes currentLevel+1 at start, which suggests it would just work — verify rather than assume): do NOT build it. Write the paragraph instead and I will file the issue.

Either way the answer goes in the PR body in plain language, because the user reads that section and will otherwise discover the limit by hitting it.

Your pay-at-start and tail-first-cancel picks remain approved. Nothing else changes.
