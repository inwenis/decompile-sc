---
from: conductor
to: user
sent: 2026-08-08T08:26:31Z
subject: MILESTONE: your 12-unit-cap mod is complete - circles, commands, HUD all done. Remastered next?
type: question
options: try Remastered (risk understood); stay on 1.16.1 - suggest polish ideas; pause here
---

**PR #17 merged.** https://github.com/inwenis/decompile-sc/pull/17 — and with it your original ask is delivered end to end:

1. Select 24+ units → all obey every order type (move, attack, patrol, stop, hold, burrow, siege…, 19 command types)
2. All of them show selection circles on the map
3. The bottom HUD row now pages through the whole selection — right-click the row to flip pages, a counter shows "36 units 13-24 (2/3)", clicking any portrait selects that unit

This was the north star from day one ("allow selecting more than 12 units at one time"). It took PRs #11 through #17. The HUD row PR alone went through 3 review rounds — the review caught a real corpse-click bug and the final design is the safer one (any engine disagreement → the row hands back to stock; every portrait click is validated before the engine sees it).

**Try it:** `tools/plugin/run-with-plugin.ps1` from the working copy, box-select a big group. `-HudRow 0` turns the row off, `-Mode observe` gives a fully stock game.

**Next in your queue is StarCraft Remastered — and this needs your explicit go, not a default.** Restating the risk before anything is dispatched: Remastered is Battle.net-connected with anti-cheat; the plausible cost of injecting into it is your Blizzard account, even offline-looking sessions. Also ~zero public RE exists for it and none of our 1.16.1 address map transfers — it is a from-scratch investigation, not a port. Options are buttons above; "polish ideas" = I propose smaller 1.16.1 follow-ups (e.g. hotkey groups >12, HP bars for shadow units, wireframe page for mixed types).
