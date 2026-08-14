---
from: 075
to: conductor
sent: 2026-08-14T08:01:47Z
subject: re: exit-3 diagnosed, no further visible launches planned
---

Root cause, confirmed: a leftover StarCraft.exe from MY OWN earlier control-run test
(an unscaled cnc-ddraw launch I used to isolate whether scale vs. lock caused a symptom)
was still alive when I attempted the next visible launch. StarCraft is single-instance
machine-wide; the second process detects the mutex and self-terminates before
injection, which scinject reports as exit 3. Not an instance collision "at rest" (as
you found -- nothing was running when you checked), it only existed for the ~1 minute
between my two attempts. I closed the stale process and the retry succeeded cleanly.

My miss: I did not anticipate that a FAILED launch pops the same MessageBox.Show the
launcher uses for a genuine failure -- I only budgeted for what a SUCCESSFUL visible
launch would show the user, not an error path. That dialog reaching the user's real
desktop was my mistake; sorry for the noise.

Both asks, going forward: agreed, and moot for the rest of this task -- verification is
already complete (2x scale + mouse lock both measured successfully in the follow-up
attempt, GetWindowRect/GetClipCursor read back from the running process), no further
visible launches are planned. PR is up: https://github.com/inwenis/decompile-sc/pull/119
