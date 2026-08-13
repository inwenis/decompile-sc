---
from: 066
to: conductor
sent: 2026-08-13T13:40:16Z
subject: BUILD READY (ci PASS at 3c6c3c0) + the per-reader single-thread evidence; awaiting your GO
---

**BUILD READY.** Fix built, hooktest 0 failures, `run-ci-local.ps1` PASS at `3c6c3c0` (origin/main incl. 065's merge already merged in). Waiting for your GO per the 067 hold; I will message ON and OFF around the run.

**What ships (option A, the phantom bracket):** detour on `queueLayout` (`0x004268D0`, prologue `55 8B EC 83 EC 20`, 6B/3 instr, nothing PC-relative). Pre: write each held item's type into ring slot `(head+k)%5` (saved, and REFUSED+counted if unexpectedly non-empty). Original runs, takes its OCCUPIED branch: grp/icon/mode/type, slot label, `enableControl`. Post: restore `0xE4`. The hand-fill and its DISABLED-clear are deleted entirely -- no disable is ever provoked, nothing exists to clear a press. `sc_prodqueue`'s cancel-icon branch (039's, never reachable before) serves the click.

**The single-thread evidence you asked for -- every ring toucher from `data/production-queue-fields.tsv` (140 rows), callers by exhaustive E8 scan (100% .text), one line each. Full table + addresses now in research/production-queue.md 8.8:**

1. Status-pane drawers/helpers (`0x00425600`, `0x004268D0`, `0x00426FF0`, `0x004568F0`, `0x0047B270/B5A0`, blit `0x00456C30`, overlay `0x004E9C59`) -> dispatched from statDisplayDriver `0x004D93F0`, the function this plugin already detours.
2. Card button conditions incl. the Train gate's world (`0x00428530`, `0x004283F0`/`0x004287D0` via `busy 0x00401500`, `0x00428E60`, `0x00401E70`) -> card layout + click paths, same UI dispatch.
3. Command receive (`cmdrecvTrain 0x004C1C20`, `cmdrecvCancelTrain 0x004C0100`, emitters behind `0x0047C9F0`) -> the plugin detours the first two; 061's traces show ACTIVATE->queueCommand->receive strictly ordered in one stream.
4. Secondary-order handlers (`productionTick 0x00468420` at `0x004EC1F9`, plus `0x0045D0D0/D500/DEA0/E090`, `0x00467FD0`, `0x004E4D00` -- every caller is the ONE dispatcher `FUN_004EC170`, the same one that calls the detoured tick).
5. Queue core (`0x004669B0/69E0/6A70/6B70/6E40/6E80`, `0x00467030/7250`, `0x00466790`) -> called only from 3/4/6 (`data/production-xrefs.tsv`).
6. Building AI (`0x00434480` <- `0x004488D8`, `0x00435DB0`, `0x00438050` <- `0x0043Exxx`) -> AI turn processing in the main loop, whose interleaving with command processing 038 measured deterministic.
7. Unit lifecycle (`0x0049F170`, `0x0049FD00`, `0x004A0320`, `0x004F6180`, `0x00488BF0`) -> sim mutators on the unit array.
8. Replay/command infra (`0x004C4A80` <- `0x004C4FCA`) -> command apply.
9. NOT the CUnit ring (sweep false positives, listed so nobody re-classifies): CRT `_qsort`/`__free_lc_time`, winproc-area dword structs `0x004D100A/1071`, `0x004D6930` (dword store at +0xA4 would smash head+uniqueness+order at once).

Two honest caveats, both closed: (a) the sweep is displacement-shaped and task 034 showed that shape can miss a handed-pointer access -- covered by the STRUCTURAL leg (the engine's own ring compactions are multi-store and unsynchronised, so any cross-thread reader would have seen torn rings in VANILLA) and by (b) the run MEASURES the claim: every hooked game-side site logs `THREADCHECK <site> tid=` once (driver, layout, interact shim, three prodq detours) and the observer logs its own -- one id game-side, observer differing, or the line says CHANGED loudly.

**Cross-thread readers closed with a seqlock**: `ScQueueIndRingGen()` bumps before first phantom store and after last restore; PRODQ/PRODQSEL/STATQ/QIND ring reads retry against it and print `ringStable=` -- a phantom can never reach a log line, and a read that never settled is reported, not swallowed.

**The regression arm flipped on the deterministic pre-fix baseline**: green now requires `phantom` moved across the click AND `disableOnOwned` +0 (pre-fix: exactly +1 per click, PR #95) -- a race merely won cannot produce that pair. Sweep asserts 100% cancel at every hold, 0 collisions, vs PR #95's 0/18 above 60ms.

**The run I want the slot for**: `test-production-queue.ps1 -HoldSweepClicks 6` (holds 40,60,80,120,200ms), off-screen, one launch. Ready to go on your GO.
