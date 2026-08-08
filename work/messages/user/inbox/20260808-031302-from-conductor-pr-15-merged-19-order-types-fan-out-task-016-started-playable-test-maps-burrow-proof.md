---
from: conductor
to: user
sent: 2026-08-08T03:13:02Z
subject: PR 15 merged - 19 order types fan out; task 016 started (playable test maps + burrow proof)
---

**PR #15 merged.** https://github.com/inwenis/decompile-sc/pull/15

What you got: with >12 units selected, 19 command types now reach all of them — move, attack, patrol, stop, hold, burrow, siege, cloak, and the rest of the untargeted abilities. Production/cancel/anything-resource-costed deliberately excluded and proven not to duplicate. The fix round closed the last test soundness gap: Hold now runs first from a moving group, so nothing but the command itself can explain the result.

Bonus research shipped: the full 58-opcode command table of the engine with per-opcode policy and evidence (`research/command-opcodes.md`), and the finding that no arbitration exists for spells — 12 selected casters means 12 casts, so 24 means 24.

**Task 016 started** (opus): make our generated test maps actually playable (root-cause the melee-template and 7-second-mission bugs) and land the in-game burrow proof that closes the waived criterion. After that: the bottom HUD row, per your queue.
