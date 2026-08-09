---
from: conductor
to: user
sent: 2026-08-09T01:17:50Z
subject: your stim question: ANSWERED, and the answer is yes to both halves
---

Your question — "if I apply stim to marines, will all of them get stim and will all of them have HP decreased" — is now answered in game, at 36 units, with per-unit measurement rather than inference.

**Yes to both halves, and every unit pays for itself.**

The test: 36 Marines, one Stim press. 24 of them healthy, 12 deliberately pre-damaged to sit EXACTLY on the game''s cutoff (10 HP).

1. **24 units gained the stim effect, and each one paid its own 10 HP.** 24 is more than 12, so the engine''s own selection cap cannot explain it — the fan-out really did reach them all.
2. **The 12 on the cutoff gained nothing and paid nothing.** This is the important detail: the split fell along the HEALTH line, not along the "first 12 versus the rest" line. That is what proves the skipping is the game''s own rule and not something our mod is doing.
3. **Stim cannot kill.** The health you need to stim and the health it costs are the same number, and the check is "greater than", so the last stim is always survivable. Press it repeatedly and your marines walk down to the floor and stop.
4. **An unexpected find:** press it a fourth time with nobody able to pay and the game emits no command at all — there is a second gate on the sending side, not just on the receiving side. Not something we were looking for; recorded as a finding rather than tidied away.

So: the ability behaves correctly across a >12 selection, and the per-unit cost is genuinely per-unit.

The other two questions — the order-stability hypothesis behind your "units stopped attacking" reports, and the sunken/medic one — are still running. Those are the ones that could implicate us, so they get the plugin-versus-stock comparison rather than a single run.
