---
from: conductor
to: user
sent: 2026-08-08T00:33:07Z
subject: PR 14 merged - all 24 units get circles; task 015 started (all order types fan out)
---

**Task 014 merged.** https://github.com/inwenis/decompile-sc/pull/14 — box-select 24, all 24 show green circles, shift-click safe, fan-out intact.

The review pipeline earned its keep: 2 fix rounds, and the second verification proved a nice inversion — the death-safety mechanism the worker originally assumed (a uniqueness byte bumped at death) is wrong; the engine itself removes our circles on unit death via the same primitive we use. Now documented with byte-level evidence.

Also merged as reusable tooling: `drive-game.ps1` (script the game via posted messages), `FieldSweep.java` (find every instruction touching a struct field), and an 8-step unattended test.

**Task 015 started** (opus): every order type fans out — stop, hold, patrol, attack, abilities — per your "2. a.". Worker will enumerate the binary's own command table and decide per-opcode what is safe to duplicate (production/cancel commands must not be). Next in queue after that: bottom HUD row.
