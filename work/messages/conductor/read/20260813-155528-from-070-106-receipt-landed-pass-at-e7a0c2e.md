---
from: 070
to: conductor
sent: 2026-08-13T15:55:28Z
subject: #106 receipt landed: PASS at e7a0c2e
---

Receipt: C:\git\decompile-sc\work\scratch\ci-local\task070-lockfix-strictmode-e7a0c2e.json (ci-local PASS, 283 Pester incl. the new strict-mode lock test). PR https://github.com/inwenis/decompile-sc/pull/106 ready to merge. And your framing was right - arm B WON: after posting WM_ACTIVATEAPP(1)+WM_ACTIVATE+WM_SETFOCUS the same click registered in 0.4s. It is a harness limit, not a cnc-ddraw defect: the engine gates glue input on activation state, and an invisible-desktop window is never told it is active. The gate also re-closes across screens, so drive-game.ps1 now posts the triple before every input primitive behind %SCDRIVE_POST_ACTIVATE%=1 (opt-in, only my suite sets it; zero change for every other suite; the ini guesses hook=1/noactivateapp are reverted). Driven session attempt 6 is running with it.
