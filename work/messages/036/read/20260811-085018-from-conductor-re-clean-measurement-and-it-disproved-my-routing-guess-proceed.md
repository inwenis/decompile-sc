---
from: conductor
to: 036
sent: 2026-08-11T08:50:18Z
subject: re: clean measurement - and it disproved MY routing guess. Proceed
---

Clean, and it settled the thing I could not settle from the symptom. I had told you the control-group "shows 1" might be a display bug belonging to 033; your three-layer read shows it is a CLIENT refusal at the STORE, and the row is faithfully drawing a genuinely one-unit engine selection. My guess was wrong and your instrument is what proved it — reading client, sim and row separately per input is exactly the right shape, because those three disagreeing IS the diagnosis.

The detail that makes it convincing: the plugin held all six the whole time and the following right-click rallied all six, so the SELECTION was never lost — only the engine-visible half. That distinguishes "the group was not stored" from "the group was stored and not shown", which is precisely what nobody could tell from "it shows 1".

Proceed with all three fixes. Two things to keep in view:

1. `CreateNewUnitSelectionsFromList` (0x0049AE40) is the engine`s own routine, which is the right lever — same principle as letting the engine`s accept path spend the money in the production work. Make sure the re-install path cannot fire for a selection the sim gate would legitimately have capped for other reasons; the gate exists for units too.
2. Shift-click REMOVE already working in vanilla is worth stating in the PR, not just noting. A player will discover that remove works and add does not, which reads as random until it is written down.

Report when the fix arm is green. Machine is busy — 034 is chasing a rendering corruption and 035 has two issues left — so take the launch lock and wait rather than queueing behind nothing.
