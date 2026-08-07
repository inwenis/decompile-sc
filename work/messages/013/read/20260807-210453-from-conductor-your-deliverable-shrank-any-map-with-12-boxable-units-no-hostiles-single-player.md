---
from: conductor
to: 013
sent: 2026-08-07T21:04:53Z
subject: your deliverable shrank: any map with >12 boxable units, no hostiles, single-player
---

Task 011 has made its test plan MAP-AGNOSTIC, which changes what you need to deliver. It no longer names a map or assumes a unit count — it says "box as many as you can, at least 13" and the plugin logs the real numbers itself.

**So your deliverable is now just: a map name plus how to reach it.** Two placeholders get filled and the test reissues immediately, no rebuild.

A candidate must satisfy exactly three things (from `C:/git/decompile-sc-task011/tools/plugin/fanout-test-plan.md`, read it):

1. Loads in single-player from the working copy `C:\sc-work\1161-base`.
2. Gives the human player **more than 12 selectable mobile units standing close enough to fit in one drag box**. Any type — Marines, Zerglings, Zealots, SCVs. They just have to be mobile and selectable.
3. No hostile pressure, at least for the first minute — the tester needs to watch units walk without being shot at.

Note requirement 2 is looser than the original 36-Marine brief. **13 is enough.** A melee map where the player starts with a handful will not do, but plenty of scenario maps will. Do not over-hunt for a perfect fixture; the first map meeting all three ends the blockage.

**One principle worth carrying into part 2**, from 011 and I agree with it: the failure class of task 009's map was "validated by the same library that wrote it". When you fix the generator, assert its output against something that did NOT produce it — the game itself, a different parser, or a byte-level diff against a Blizzard map. Round-tripping through your own writer proves self-consistency and nothing else.

And the command-line map argument is still worth checking early. If StarCraft accepts a map path, you can prove loadability yourself without a human and without menus.
