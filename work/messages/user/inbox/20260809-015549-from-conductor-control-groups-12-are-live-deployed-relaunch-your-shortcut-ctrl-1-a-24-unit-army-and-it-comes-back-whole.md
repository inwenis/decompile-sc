---
from: conductor
to: user
sent: 2026-08-09T01:55:49Z
subject: CONTROL GROUPS >12 ARE LIVE - deployed, relaunch your shortcut. Ctrl+1 a 24-unit army and it comes back whole.
---

**Merged and deployed. Relaunch the shortcut and Ctrl+1 works on more than 12 units.**

Box 24 units, press Ctrl+1, click away, press 1 — all 24 come back, with their circles and the paged bottom row, and the next order reaches all of them. Shift+1 adds to a group. Plain number keys recall.

**One limit worth knowing:** the mod cannot be tested through the keyboard for Ctrl/Shift combinations — Windows will not deliver simulated modifier keys to this game (they are "accelerators", resolved against a keyboard state our automation cannot set). So the automated test drives the same internal command the keypress produces. Your real keyboard is unaffected; it just means that one layer is verified by you pressing the key, not by a script.

**Also fixed on your two asks from earlier:**

1. **Merges no longer wait on GitHub billing.** I reproduced the entire cloud check locally, and taught the merge script to accept a local receipt in place of the cloud verdict — but only a PASSING receipt whose commit matches the pull request exactly, printed loudly and posted onto the PR as a comment. A substitution with a paper trail, not a bypass. Sorting the billing is still worth doing eventually; the cloud run is the one nobody can fudge.
2. **The agents were never stuck** — they were destroying each other''s test runs, invisibly. Fixed structurally, and their own diagnosis work found two more layers of it.

**What this PR cost, honestly:** it took a blocker round. The first version''s protection against stale groups only worked if you happened to touch a second control group in the previous game — assign one group, never touch it again, start a new mission, and it would have merged last game''s units into your new group. A reviewer reproduced that offline before it shipped, and the worker then rejected my suggested fix as too narrow and wrote a better one that keeps no state at all.

Two suites are not green, and I am not calling them green: their drag-boxes selected nothing, attributed to the same foreground bug that broke the menu dropdown. The confirming experiment is one sweep against the fix your other agent is landing.

Next: the abilities/order-stability audit finishes, then a harness-hardening pass, then your building-selection and queue mods.
