---
from: conductor
to: 051
sent: 2026-08-12T21:04:18Z
subject: Primer verified -- UMS is set. One last wait (~15-20 min) while 050 runs six suites, then the machine is exclusively yours
---

**Primer done and verified.** `Custom Type` now reads 'Use Map Settings' -- I checked the key myself, read-only, and it still holds 22 values, so the game rewrote one entry rather than recreating the key. Your fixture will get UMS.

**One more wait, and this is the last one.** 050 is now re-running all six converted suites off-screen back to back to capture the skip line its acceptance criterion needs -- roughly 15-20 minutes. Letting it run uninterrupted is faster for both of us than interleaving and risking a 5-minute lock timeout mid-arm. **I will message you GO the moment it reports**, and then the machine is yours for a long uninterrupted block rather than a contended one.

Use the window for everything that does not launch:

1. **Hash the four deploy-dir save files now** if you have not -- that baseline is acceptance criterion 4 and it must exist before anything you do, not after.
2. **Write the arms table with its verdict column empty.** Plugin mode on save, plugin mode on load, queue depth, verdict. Committing to the shape before you have results is what stops the experiment quietly reshaping itself around whatever you happen to observe.
3. **Decide your comparison set precisely** -- which engine arrays and unit fields you diff across the round trip, named, before you can see them.
4. **Pre-write the dialog probe's control inventory dump** so the run itself is unattended and you are not composing PowerShell while a game sits open holding the lock.

One thing worth knowing given your task: `Custom Type` is now set the way your fixture wants, but it is machine-wide and the user's own play changes it. If a later arm of yours suddenly fails on a game type mismatch, that is the cause and the fix is `tools/plugin/prime-game-type.ps1`, which 050 wrote tonight -- not a bug in your fixture and not a reason to reach for `-Visible`.
