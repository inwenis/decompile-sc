---
from: conductor
to: user
sent: 2026-08-10T21:29:53Z
subject: answer: queueing at several buildings does NOTHING today (measured), and the upgrade-queue design is approved
---

# 1. Your question, measured rather than guessed

**Selecting several production buildings and clicking Train does nothing at all today.** Not "it queues at one" -- nothing.

| | 4 Command Centers selected | 1 selected (control, same game) |
| --- | --- | --- |
| Train button on the card | **not there at all** | enabled |
| commands sent to the game | **0** | 1 |
| buildings that queued a unit | **0 of 4** | 1 |
| minerals spent | **0** | 50 |

Read out of each building`s own memory, all four printed separately, checked before AND after the click. The single-building control ran in the same game through the same instruments -- so the zeros are real zeros, not a broken measurement.

**Why:** the game has a rule that hides most command-card buttons whenever more than one unit is selected. Task 030 caught it in the act: with one building the card shows 5 buttons, with four it shows 2 -- and precisely the three buttons governed by that rule disappear while the two that are not governed by it stay. So there is no button to press, and the game never sends anything.

That makes it TWO changes, not one: let the button be drawn for a same-type building group, then fan the resulting command out across the group. Task 030 is building both. Nothing is guessed -- it caught this before writing code, which is exactly the mistake the >5 unit queue made last week.

# 2. Upgrade queue -- design approved, being built now

Task 029 mapped it properly and I approved it. Short version of what you will get: **queue different upgrades at one building** -- Armor behind Weapons at an Engineering Bay, Stim behind U-238 at an Academy. Both upgrades and abilities-research are covered.

The design`s good property: **the plugin never touches your resources.** A queued upgrade is just a note saying "do this next"; the GAME pays for it when it actually starts, out of its own accounting. So it cannot be charged twice, cancelling costs nothing, and if the building dies you only lose the one actually running -- which the game refunds itself. Compare that with the unit queue, where task 028 is right now proving the refund path in a real game because that path exists.

**One limitation you should hear from me rather than discover:** you will NOT be able to queue Weapons 1, then 2, then 3. The game hides an upgrade`s own button while that upgrade is running, and 029 is not touching that rule in this version. If stacking levels of ONE upgrade is what you actually pictured when you asked for this, say so -- I have asked 029 to price it, and I will cut it as a follow-up rather than let it quietly not exist.

# 3. Small thing you might notice

Task 029 reported honestly that when it ran the game with your desktop idle, the game took the screen and kept it for the whole 72-second run. The focus fix from last night stops the game grabbing focus on every click, but the LAUNCH itself still takes it once, and if nothing else on your desktop is competing, nothing takes it back. Filed as issue #30. Practically: if you are actively using the machine your window reclaims it; if you have stepped away, a test run will own the screen until it finishes.
