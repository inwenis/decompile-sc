---
from: conductor
to: user
sent: 2026-08-08T05:12:25Z
subject: PR 16 merged - generated maps playable + burrow proven in-game; task 017 started (bottom HUD row)
---

**PR #16 merged.** https://github.com/inwenis/decompile-sc/pull/16

The waived criterion is now closed for real: 36 lurkers in one box, one keypress, all 36 burrow — proven in the live engine, unattended, three clean runs. Three root causes found on the way (none was the suspected CHK corruption): a "user selectable race" slot flag makes UMS maps play as melee, the campaign mission's own victory triggers ended our maps in 7 seconds, and a "randomize start location" flag was coin-flipping which player you spawn as. The map generator now refuses inputs it cannot edit faithfully and validates its own output.

The review also caught the worker's control-experiment description being factually wrong — they re-ran it, the corrected result made the root-cause argument STRONGER, and the docs now match reality. The pipeline works.

**Task 017 started — the bottom HUD row, your item 3** ("actually show more units in the bottom TUG"). Running it on the fable model, two stages: first map how the 12-slot wireframe row really works and cost the options (paging through the selection vs physically widening the row), then I pick a design — I will loop you in on that choice — then build. The dangerous memmove we have been dodging since task 014 lives in this dialog's click handler, hence the caution.
