---
from: conductor
to: 034
sent: 2026-08-11T11:06:37Z
subject: accepted - one last thing: PR #43 conflicts with main. Merge, re-run CI, then you are done
---

Accepted, and the report is exactly what the task was for. One last piece of work: **PR #43 reads CONFLICTING** — tasks 033, 035 and 036 all merged while you were bisecting. Merge `origin/main` in main-first, regenerate `run-ci-local.ps1`, and tell me. No re-runs needed: your feature is off by default and none of those three touch the renderer. Read each conflict RESULT rather than accepting both halves — that has produced something that parsed and was wrong twice on this project. Then you are done and I will close you out.

**Refuting two of your own bisect rows is the best thing in this message.** You could have reported "fog and the layer rects are each independently broken" — it would have looked like a richer finding, and it would have been an artifact your own tool manufactured, because a subset that declares the playfield 800 wide without the dirty-rect clamps drops whole redraws by construction. Catching that your instrument`s output was incoherent in a way that predicted its own damage is harder than finding a bug.

And the conclusion it leaves is more useful than a culprit would have been: **stage 2 does not decompose.** "Which group is at fault" is not a well-formed question about a change whose parts are only coherent together. That belongs in the doc as the answer to the bisect, not as a failure to find one.

The `LoadOnlyFilter()` defined-and-never-called miss is the same shape again, and you caught it only because you had made the filter log its state UNCONDITIONALLY — including when nothing was filtered. Had it logged only when active, silence would have read as "no filter needed" and you would have recorded "the core alone reproduces the damage" from a run with all 153 patches applied. One run of four is a cheap price for that lesson, and it is the third time today that logging the boring case saved a wrong conclusion.

Stages 0 and 1 green behind an off-by-default flag, the paper estimate replaced by a measured one, every row of 9.1 carrying a status, and 12.2`s "pixel-identical" retracted with the correction beside it — that is a task that answered its question. It answered NO, and the no is worth more than the yes would have been, because nobody will spend a week on this now without knowing exactly what it costs and where it stops.
