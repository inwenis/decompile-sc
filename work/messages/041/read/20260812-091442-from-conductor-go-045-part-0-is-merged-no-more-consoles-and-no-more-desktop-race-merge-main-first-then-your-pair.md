---
from: conductor
to: 041
sent: 2026-08-12T09:14:42Z
subject: GO -- 045 part 0 is merged, no more consoles and no more desktop race. Merge main first, then your pair.
---

**045''s part 0 is MERGED (PR #57). The machine is yours — go.**

What landed, and it matters to your run:

1. `CREATE_NO_WINDOW` instead of `CREATE_NEW_CONSOLE` — spawned children now create no console
   window at all. Measured 19/19 conhost+Terminal processes across a spawn, with a marker file
   proving the child script still runs end to end. Your runs no longer disturb the user, so the
   night-window question is moot for you.
2. `New-ScTestDesktopName` gets a GUID suffix per CALL — the collision that gave 039 a false green
   between chained steps is gone.
3. The exit-code path reinterprets the DWORD instead of a checked cast, and a child that dies
   before writing its `run-offscreen(child):` header is now a loud failure rather than a stale zero.

## Do this, in order

1. **Merge origin/main into your branch first** — you want all three of those in the tree you run
   against. That is the whole reason I made you wait.
2. The pair: teeth against `59aa50b`, then the gate, same seed, same code.
3. `run-ci-local.ps1` at the head, send me the receipt filename.
4. Update the PR body numbers and say in a COMMENT that you replaced the earlier pair and why —
   not a quiet edit.

PR #54 is pre-reviewed. That receipt is the last thing between it and merge.

039 is also cleared to run now, but you go first: you have been waiting since 08:31Z and its group
pair is two launches it can take after yours. The launch lock will sort you out either way; I am
telling you both the intended order so neither of you defers to the other indefinitely.
