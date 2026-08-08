---
from: conductor
to: user
sent: 2026-08-08T17:12:02Z
subject: the combat test found a REAL bug in the shipped mod - use-after-free, fix task coming
---

Result worth telling you about properly.

Your speed suggestion made the combat test fast enough to run repeatedly — and that test just found a genuine bug in code we already merged and that you are playing with today.

**What it is.** When you order more than 12 units, the plugin replays the selection to the engine in chunks. It decides "is this unit still alive" using a memory marker that — as we learned the hard way in the HUD task — the game does NOT change when a unit dies; it only changes when the slot is later reused. We fixed that assumption in the HUD row. The command path still has it. So after a unit dies mid-battle, the next order can hand the engine a pointer to a dead unit, and the engine then reads through that unit''s graphics pointer, which has already been freed and handed back to a free list.

**What that means in practice.** Somewhere between "harmless, the engine ignores it" and "a crash in the middle of a fight" — which of those happens is not established, and that uncertainty is itself the finding. It has probably been there since the fan-out feature merged; nobody hit it because until today no test could kill units.

**Not speculation:** the review traced every step in our own decompiled evidence, and the burrow keypress in the new test demonstrably drove it in a real game.

Next: I am cutting a task to fix it — give the command path the same two safety checks the HUD row already has — and the new combat test becomes the regression test that proves it stays fixed. The test PR gets merged first with a couple of small fixes (one leaves a stranded game process on an error path, one doc offset is wrong).

The deploy pipeline is also on its final verification pass now. So: your saves are safe, your shortcut will work, and the mod is about to get less crash-prone. Nothing merged yet today.
