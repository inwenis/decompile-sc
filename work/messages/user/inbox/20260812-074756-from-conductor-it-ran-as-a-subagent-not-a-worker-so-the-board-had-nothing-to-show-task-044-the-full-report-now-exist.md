---
from: conductor
to: user
sent: 2026-08-12T07:47:56Z
subject: It ran as a subagent, not a worker -- so the board had nothing to show. Task 044 + the full report now exist.
---

Straight answer: **it was not a board task, and that was my call, not an oversight of the
tooling.** I ran it as an in-session **subagent** — a fable-model agent inside my own session,
not a spawned worker. So it had no task file, no worktree, no registry entry and no PR, and the
board derives everything it shows from exactly those. Nothing to render, so the left panel
showed nothing.

## Why I chose that

You said "check that with fable", and the work was read-only machine forensics — Windows event
logs, the Setup log, the hotfix list, and a grep of our own tooling. No repo change, no game,
no PR. The conductor rule I hold is "every code/review ask gets a task file and a worker", and
this was not code, so it did not trip.

That reasoning was too narrow. The rule that actually matters here is a different one: **work
you are waiting on has to be visible on the board, whatever tool executes it.** You asked a
question, went to look for the answer's progress, and found an empty panel. That is the failure,
regardless of which rule technically applied.

## What I have done about it

1. **Task 044 now exists** — `work/tasks/044-reboot-forensics.md`, cut after the fact and
   marked plainly as already-executed, with the acceptance criteria and how each was met.
2. **The evidence is in the repo, not just in a message** —
   `work/reports/044-reboot-forensics.md`: the full timeline in both local and UTC, the User32
   1074 entry verbatim, every ruled-out hypothesis with the log that rules it out, the
   deny-list grep, and why task 043's desktop probe cannot reboot anything by construction.
   Committed to main.
3. **Standing change, effective now:** anything I dispatch that you are waiting on gets a task
   file BEFORE it starts, even when a subagent does the work and even when there is no code and
   no PR. It costs about ten seconds and it means the board never lies about what is in flight.

What I will keep doing invisibly: my own quick lookups inside the repo — reading a file,
checking `gh pr view`, grepping for a symbol — the things that take seconds and are part of
answering you at all. If you want those on the board too, say so and I will put them there.

One thing worth knowing about the difference, since it is the real trade-off: a subagent starts
instantly and dies with my session; a spawned worker gets its own tab, its own worktree, its own
inbox, and survives me. For a five-minute read-only question the subagent is the right tool —
it just needed a task file next to it so you could see it running.
