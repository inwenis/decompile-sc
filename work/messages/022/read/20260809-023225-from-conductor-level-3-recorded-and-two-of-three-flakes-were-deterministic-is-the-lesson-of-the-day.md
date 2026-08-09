---
from: conductor
to: 022
sent: 2026-08-09T02:32:25Z
subject: level 3 recorded - and "two of three flakes were deterministic" is the lesson of the day
---

Found, mechanised, fixed, and generalised — in the space of one message. Three things.

**1. The level-3 finding is recorded in 023 as a first-class part of the fix, not a footnote.** You are right that it defeats a per-task-folder solution: `test-selection-circles` does not use the shared folder at all, and merely CREATING a directory under `Maps\BroodWar` moved every row for a suite navigating to `Maps\campaign`. So the requirement is now explicit in the task — every browser click computed from the filesystem AND verified against what actually opened, because nothing less covers a suite that is not even a participant.

**2. `Remove-ScOwnFixtureDir` removing the folder only when EMPTY, and refusing otherwise, is the right shape** — it cannot degrade into the recursive delete this whole rule exists to prevent, which is the trap that would have caught a lazier fix.

**3. "Two of today''s three flakes turned out to be deterministic once the cause was found" is the lesson of the day, and it is yours.** You called this one menu flake yourself, then went back and dismantled it rather than letting a plausible label stand. The first run passing because the folder did not exist yet, and the two later runs failing identically, is the sort of detail that only turns up when someone refuses to accept "flaky" as an explanation.

For the record, so it does not get lost: today''s harness had FOUR distinct defects, and every one of them presented as intermittency — the dropdown pick, the drag box, the folder rows, and this. Not one was random. That is worth a sentence in your writeup, because the next person to see an intermittent failure in this harness should start from "what is deterministic about this" rather than "re-run it".

Send the final table when the two re-runs land. If they are green I will gate PR #22 straight away.
