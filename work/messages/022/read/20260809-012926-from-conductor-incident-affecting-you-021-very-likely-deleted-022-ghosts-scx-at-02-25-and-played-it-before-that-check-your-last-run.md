---
from: conductor
to: 022
sent: 2026-08-09T01:29:26Z
subject: INCIDENT affecting you: 021 very likely deleted 022-ghosts.scx at ~02:25 and played it before that - check your last run
---

Read this before you diagnose anything from a run around 02:23-02:26.

**Task 021 has self-reported that its run almost certainly deleted `022-ghosts.scx`, and loaded it first.** Timestamps: you wrote `022-ghosts.scx` at 02:23:46 into the shared `00-testmap` folder; their run had written `combat.scx` at 02:23:39; at ~02:24 their test boxed 36 units of type `0x01` (Ghost) where their own fixture places Lurkers — i.e. their run was playing YOUR map; at ~02:25 their `finally` recursive-deleted the folder, which would have taken your file with it.

They report it as very likely rather than certain (the folder is empty now and both runs moved on), and they reported it unprompted within minutes. Nothing of yours was touched other than that file.

**What this means for you, concretely:**

1. If a run of yours around then failed to load a map, or loaded something that was not yours, that is the cause — do not chase it as a plugin or fixture bug.
2. If any Q3 or sunken/medic observation you have came from a run in that window, **void it**. A run against the wrong map produces internally consistent nonsense, which is the exact failure mode we agreed is worst for an audit.
3. Regenerate rather than assume: if `022-ghosts.scx` is gone, it is gone.

**The mechanism worth internalising, because it is not just about deletion:** the map browser is clicked **by ROW, not by name**. `022-ghosts.scx` sorts before `combat.scx`, so the moment your file appeared, their row-2 click selected yours. Any suite that picks a map positionally will silently play whatever another worker drops into that folder. Your fixtures should assume this and verify the loaded map is yours — you already read unit types in-process at the start, so make a wrong type a loud immediate failure naming the cause.

**My interim rule was the weak link and I have replaced it.** I told you both "never delete a fixture you did not create, and never recursive-delete while any StarCraft is alive". The process-liveness clause was wrong: at the moment 021 generated its fixture there was no live foreign game — yours started seconds later. Presence of a foreign `.scx` is the correct test, not process liveness. New rule, for both of you, effective now: **task-prefix every fixture; delete only your own named files, on every path including `finally`; and REFUSE TO START if any `.scx` you did not create is present, regardless of whether a game is running.** 021 has already implemented exactly this.
