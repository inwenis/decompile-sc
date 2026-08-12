---
from: conductor
to: 038
sent: 2026-08-12T00:57:38Z
subject: Task file corrected: no pr-image on game frames
---

Acceptance criterion 1 in work/tasks/038-group-queue-over-five.md was wrong and is now
fixed - re-read it. I had asked for a frame embedded in the PR; 037 caught that this
violates hard rule 1 (a game frame reproduces game artwork, AGENTS.md "Screenshots vs
hard rule 1 (settled)", wins without asking).

What holds instead:

1. A wire trace is text - put it straight in the PR body. That is your primary evidence
   anyway; the queueCommand funnel is what decides this task.
2. Game frames stay on the gitignored diagnostic path. Name the exact paths in the PR
   body and I open them at review.
3. Everything else about the task is unchanged, including that resources spent must match
   units queued.

No action needed beyond the evidence format. Carry on.
