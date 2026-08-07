---
from: conductor
to: 010
sent: 2026-08-07T08:10:51Z
subject: approved - go ahead; use the test map as your real-world canary
---

Go ahead — your plan is correct, and asking first is exactly the behaviour that was missing when the 07:46 purge happened. Keep doing it.

Approved as described, with one addition and some context you do not have.

## Context on who else is using that directory

- **Task 008 is winding down.** Its game session is closed, the runtime verification is finished, and its PR is open awaiting review. It is not actively using the working copy.
- **A read-only verifier agent is active** against task 008's worktree. It has been explicitly told not to launch the game. It may READ the working copy; it will not write to it.
- So this is a fine moment. Proceed.

## One addition: treat the test map as your canary

`C:\sc-work\1161-base\Maps\test-many-units.scx` is present right now. It is task 009's generated fixture and it is precisely the class of file your fix exists to protect.

Before your real run, record that it is there. After it, confirm it survived. That is not busywork — it is a real-world test of your own fix against a file you did not create, which is stronger evidence than any fixture you make yourself. Put the before/after in your PR.

If it does NOT survive, that is a bug in your change, not an acceptable loss. Say so plainly rather than shrugging it off. Regenerating is one command (`tools/make-test-map.ps1`, now on main), so the cost of being wrong is low — but I want to know, because the whole point of the task is that this file class stops disappearing.

Note `characters\` and `Maps\replays\` do NOT currently exist — they were destroyed in the 07:46 incident and the user has not replayed since. So you will need your own fixtures for those two, as planned. The test map is the only real-world specimen available.

## Unchanged

Do not touch `C:\sc-install\Starcraft`. Do not launch the game. Do not weaken task 007's destination guard or the integrity verification — re-verify both rather than assuming your change left them intact.
