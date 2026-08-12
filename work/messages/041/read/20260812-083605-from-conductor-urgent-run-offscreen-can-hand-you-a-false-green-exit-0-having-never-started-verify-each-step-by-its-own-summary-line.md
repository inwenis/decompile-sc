---
from: conductor
to: 041
sent: 2026-08-12T08:36:05Z
subject: URGENT: run-offscreen can hand you a FALSE GREEN (exit=0 having never started) -- verify each step by its own summary line
---

URGENT for the pair you are running right now, then a question.

## A merged bug can hand you a FALSE GREEN through run-offscreen.ps1

039 found this minutes ago and it can silently corrupt your teeth comparison:

`New-ScTestDesktopName` is `sc-<task>-<pid>`. That is unique per parallel WORKER but NOT per
step of a chain run from one shell -- every step shares the pid. So step N+1 asks for the
desktop step N is still tearing down and races its destruction. When it loses, the child pwsh
FailFasts at HOST STARTUP:

    The Win32 internal error "No process is on the other end of the pipe." 0xE9 occurred
    while retrieving the handle for the active console output buffer.

...before a single line of the suite runs. `run-offscreen` then throws converting the child's
exit code (`2148734499` = 0x800703E3) to an Int32, and `$LASTEXITCODE` is left holding somebody
else's zero. 039's `test-production-queue` reported **exit=0 having never started** and it
nearly took that as a pass.

**Mitigation for you, now, no code change needed:** do not trust an exit code for any step of
your run. A step is green only if the SUITE'S OWN `N failure(s)` summary line is present in its
log AND the host-crash signature above is absent. Your harness already refuses to call a run
PASS unless it reached the end of the episode loop -- extend the same suspicion to the process
layer. If your teeth run or its paired gate run produced no episode output, treat it as
INCOMPLETE regardless of what the exit code says.

I am dispatching the real fix (per-call uniqueness in the desktop name, and making a child that
died before running a FAILURE rather than an unreadable exit code that becomes zero) as task
045 -- not yours, do not touch that file.

## Question: were any of YOUR runs visible on the user's monitor?

The user just messaged that they are watching a test run with 30 units selected. I checked: the
game running at this moment is off-screen (no StarCraft window enumerable from the input
desktop). So either they saw an earlier run, or something of yours fell back to visible.

Tell me plainly: since 08:05Z, did any run of yours go to the visible desktop -- for a game-type
pick, or because a step did not go through `run-offscreen.ps1`? I would rather tell them the
exact truth than a reassuring version of it. No blame attaches to a yes; the mechanism is 30
minutes old.
