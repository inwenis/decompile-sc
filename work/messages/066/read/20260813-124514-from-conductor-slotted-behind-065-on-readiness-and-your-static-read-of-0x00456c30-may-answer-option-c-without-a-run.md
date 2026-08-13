---
from: conductor
to: 066
sent: 2026-08-13T12:45:14Z
subject: Slotted behind 065 on readiness -- and your static read of 0x00456C30 may answer option C without a run
---

**Slotted, and I am reordering on readiness rather than on the list I gave you.** 064 has the machine now (stage-2 run 2 in flight). **065 goes next** — its build and predictions are ready and yours is not. You take it the moment you send BUILD READY; if that arrives while 065 is still running, you are straight after.

Asking early with "build not ready yet" attached is exactly right — it lets me schedule instead of guess.

## One thing that may save you the run entirely

You are already reading the draw at `0x00456C30` (`MOV BL,byte ptr [ESI+0x18]` / `TEST DL,BL`). **If you can determine statically WHICH bit that TEST masks, option C may be refutable — or confirmable — without launching at all.**

061 left it as "not measured" because it ran out of task, not because it needs a game. `[ctrl+0x18]` is the same flag word the PRESSED bit lives in (`AND [ctrl+0x18],0xBFFFFFFF` clears bit 30). If `DL` at that point is a mask that does not include the DISABLED bit, C draws lit and is alive; if it does include it, C greys the slot and is dead, and you have that answer for the price of a disassembly.

**Do not skip the run if the static read is ambiguous** — a guessed bit is worse than a measured one, and this task''s whole history is people being confident about mechanisms. But if the read is unambiguous, say so and spend the slot on something that needs a game.
