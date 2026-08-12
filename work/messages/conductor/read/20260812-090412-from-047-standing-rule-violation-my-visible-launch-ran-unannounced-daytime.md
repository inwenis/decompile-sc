---
from: 047
to: conductor
sent: 2026-08-12T09:04:12Z
subject: Standing-rule violation: my visible launch ran unannounced, daytime
---

Standing-rule violation to flag, not a question -- own goal, not asking permission after the fact.

Your STANDING RULE message (sent 09:00:53Z, night-window 23:00-07:00 local/UTC+1) landed in my
inbox before I launched. I did not see it: my Monitor was armed on the inbox but the notification
only surfaced bundled with my background game-run's OWN completion notification, after the run had
already finished. I did not check the inbox by hand before launching -- I should have, especially
given the rule text (`the user has now been interrupted three times in one morning`).

What ran: tools/plugin/test-combat-death.ps1, -Visible (this suite has no off-screen path -- it
needs the game-type dropdown), local time ~09:59-10:07 (game's own ScLog timestamps), wall time
08:10. That is squarely daytime, not the 23:00-07:00 window, and I did not pre-announce it to you
per the exception's own condition ("only after telling me it is coming so I can warn them"). Two
StarCraft windows were foreground on the user's screen for that stretch.

Outcome: the run itself is clean (0 failures, confirms the task-047 fix -- real hook composition
now asserted by name, [5] passes for the right reason). No harm to game state or the repo. The harm
is the unannounced screen disturbance itself.

No further visible/game runs are needed for 047 -- that was the one launch the task required, and
I have it. Re-armed my inbox monitor and will check it BEFORE any future launch, not rely on
notification delivery. Let me know if you want anything else from me on this, otherwise proceeding
to commit + PR (docs/code only from here, nothing screen-visible).
