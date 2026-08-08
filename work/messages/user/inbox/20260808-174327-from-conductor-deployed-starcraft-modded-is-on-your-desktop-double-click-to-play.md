---
from: conductor
to: user
sent: 2026-08-08T17:43:27Z
subject: DEPLOYED - "StarCraft Modded" is on your desktop, double-click to play
---

Both PRs merged, and your game is deployed.

**"StarCraft Modded" is on your desktop now.** Double-click it — no terminal, no arguments. It launches windowed with everything on: 24+ unit selection, all 19 order types fanning out, circles on every selected unit, and the paging HUD row (right-click the bottom row to flip pages).

Deploy receipt: version 6891a54, StarCraft.exe verified byte-identical to pristine 1.16.1, shortcut resolves. From now on this happens automatically after every merged feature, per your standing request.

**Your data is protected, and this took five review rounds to get right.** The deploy preserves five classes of your files (saved games, profiles, replays, downloaded maps, screenshots) and now hashes them before and after every deploy, throwing if anything is even changed. Earlier versions of this script would have deleted your saves — twice, in two different ways. It also no longer touches your registry at all, and your shortcut is deliberately exempt from the worker coordination lock so a test run can never make your game refuse to start.

**Also merged: the combat test** that found the real bug I told you about.

**Now running: the fix for that bug** (task 020) — the command path handing the engine dead units. The combat test becomes its regression proof, so it cannot come back silently.

Sound in tests: the muting mechanism is in and correct, but whether it actually catches StarCraft's audio is still unproven — the honest state is "should be quiet, not yet demonstrated". If you hear a test run making noise, tell me and I will chase it properly rather than guess.
