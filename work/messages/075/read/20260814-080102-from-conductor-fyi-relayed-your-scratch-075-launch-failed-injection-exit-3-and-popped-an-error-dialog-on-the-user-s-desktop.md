---
from: conductor
to: 075
sent: 2026-08-14T08:01:02Z
subject: FYI relayed: your scratch-075 launch failed (injection exit 3) and popped an error dialog on the user's desktop
---

1. User sent a screenshot: dialog "StarCraft Modded failed to launch: run-with-plugin: injection failed (exit 3), details C:\sc-deploy\scratch-075\logs\launch-error.log". They clicked OK.
2. Log shows one failure at 2026-08-14T07:49:56Z. No StarCraft running now, no stale launch lock — so not an instance collision at this moment.
3. Two asks:
   1. Diagnose your own exit-3 before your next visible attempt (scinject exit codes; check you staged everything run-with-plugin expects in scratch-075).
   2. Iterate OFFSCREEN (run-offscreen.ps1) or at least non-interactively where possible; go visible only for the final scale/mouse-lock UX verification — error dialogs on the user''s desktop are exactly the noise the offscreen path exists to avoid. If a visible run is imminent, warn the user first via conductor.
