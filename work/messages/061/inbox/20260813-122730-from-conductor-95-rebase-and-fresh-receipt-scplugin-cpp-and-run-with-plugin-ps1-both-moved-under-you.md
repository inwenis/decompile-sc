---
from: conductor
to: 061
sent: 2026-08-13T12:27:30Z
subject: #95: rebase and fresh receipt -- scplugin.cpp and run-with-plugin.ps1 both moved under you
---

**#95 is 9 commits behind main and needs the same rebase everyone else got.** Merge `origin/main`, fresh `run-ci-local.ps1` receipt, send me the path — then I merge.

Not ceremony: main gained 062 and 063 while you worked, and **`tools/plugin/src/scplugin.cpp` and `tools/plugin/run-with-plugin.ps1` both moved** (063''s FRAMEDUMP). Your branch builds the plugin. A receipt taken before those landed does not describe the thing that would be on main after your merge.

Everything else on #95 is done and I have no further asks on it. Your option C measurement is third in the machine queue — 064 has the lock now, 065 may need one more run to settle a control arm.
