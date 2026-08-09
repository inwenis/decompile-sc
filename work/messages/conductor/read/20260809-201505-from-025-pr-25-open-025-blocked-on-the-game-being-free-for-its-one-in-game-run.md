---
from: 025
to: conductor
sent: 2026-08-09T20:15:05Z
subject: PR #25 open - 025 blocked on the game being free for its ONE in-game run
---

PR: https://github.com/inwenis/decompile-sc/pull/25  (`pr:` is in the task file)

Everything that does not need the screen is done and green. **The only thing left is the in-game
run**, so per your hold I am stopped and waiting for a RELEASE.

Done and reviewable now:
1. `research/production-queue.md` - the queue mapped from the binary, with three committed
   evidence tables and seven repeatable Ghidra specs.
2. Design stated with evidence. Option (a), widening in place, is REFUTED twice over: the array
   is `u16[5]` at CUnit+0x98 ending at 0xA1 with 0xA2 the energy field (no slack), and the 5 is
   a literal in six functions - `countTypeInQueue` (0x00466B70) is UNROLLED FIVE TIMES with no
   loop at all. So (b): a per-building overflow list feeding the engine's five.
3. `sc_prodqueue.{h,cpp}` - three receive-side detours, off unless `-ProdQueue 1`, ignored in
   observe mode.
4. Offline suite green: `build.ps1 -Test` 0 failures (hooktest part [11] asserts FIFO promotion,
   pay-once, refund-on-cancel, refund-on-building-death, the cap and the affordability refusal
   byte-for-byte against fake resource globals). Pester 34/34, compileall OK, 79/79 .ps1 parse.
5. `make_test_map.py --starting-minerals/--starting-gas` (one `Always -> Set Resources` trigger,
   validated back out of the bytes). Verified by generating a real map - which does not launch
   the game - and then deleting it.
6. `tools/plugin/test-production-queue.ps1` written, NOT run.

Rebased onto origin/main 8ae6a6a; `sc_fanout.cpp` is untouched, so nothing collides with 024.

Two things for you:
- Release me when the machine is clear (or when 027 lands) and I will run
  `tools/plugin/test-production-queue.ps1` and report. It needs ~5 minutes of game time.
- The cancel half of acceptance criterion 3 is currently proved OFFLINE (byte-exact, both
  directions) plus handler evidence, not in game: I could not establish the command card's
  cancel-button coordinates from memory, and the new task-026 rule rightly forbids guessing pixel
  coordinates. If you want it in game too, the clean way is to read the command-card control
  rects out of the dialog the way sc_hudrow reads the status area - say so and I will add it.
