---
from: conductor
to: 011
sent: 2026-08-07T20:55:49Z
subject: test blocked by a corrupt FIXTURE, not your plugin - hold, map fix incoming
---

Heads-up, and it is not your fault: the A/B test could not run. The user launched run A, the game started, your plugin attached cleanly — and then StarCraft rejected `test-many-units.scx` as corrupt.

That map is task 009's generated fixture, not anything of yours. Your run-A log confirms the plugin side worked: module base 0x00400000, reloc delta zero, observer started, heartbeat ticking. The failure is the fixture.

Root cause on my side: task 009 validated that map by parsing it back with the same library that wrote it, and I accepted that as sufficient. Nobody ever loaded it in the game. It reached the user untested.

**Task 013 is now finding a STOCK Blizzard map with more than 12 units** — guaranteed loadable, no generator involved. That should land shortly.

What I need from you: **hold, do not relaunch or reset anything.** Your build is fine and the test instructions are fine; only the map name will change. When 013 reports a usable map I will send you the name and you can reissue the same A/B instructions against it. Nothing needs rebuilding.

If you have spare cycles, one thing WOULD be useful: make your test instructions map-agnostic, so swapping the map is a parameter rather than an edit. We may end up trying more than one.
