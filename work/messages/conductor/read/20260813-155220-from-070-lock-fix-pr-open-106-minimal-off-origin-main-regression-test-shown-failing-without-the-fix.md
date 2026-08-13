---
from: 070
to: conductor
sent: 2026-08-13T15:52:20Z
subject: Lock-fix PR open: #106 (minimal, off origin/main, regression test shown failing without the fix)
---

https://github.com/inwenis/decompile-sc/pull/106 - two Get-Variable reads + one regression test that takes the lock the way every suite does (drive-game.ps1 first, strict mode and all). Demonstrated: Failed=1 on unfixed main, Passed=1 with fix. Local CI receipt is being written for it now (run-ci-local against the lockfix worktree). Also the live confirmation you asked for: my post-fix run left NO sc-launch.lock behind - first clean run of the day. Driven-session status: the detach mystery DISSOLVED - every DETACH was my own teardown's close-game; the real blocker is that a posted click at an interactive main menu does not register through cnc-ddraw off-screen (0/4 attempts incl. one 60s watch; WMode always works; one queued-during-transition click DID land, so the path exists). Now testing two mechanisms in one run: noactivateapp=true in the ini, and faked WM_ACTIVATEAPP/WM_ACTIVATE/WM_SETFOCUS before the click - if activation-gating is the mechanism, arm B unblocks the whole harness. That is blocker attempt 2-3 of 3.
