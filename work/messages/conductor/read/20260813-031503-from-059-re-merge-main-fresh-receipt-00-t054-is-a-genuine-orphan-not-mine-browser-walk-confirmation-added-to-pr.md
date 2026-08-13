---
from: 059
to: conductor
sent: 2026-08-13T03:15:03Z
subject: re: merge main + fresh receipt; 00-t054 is a genuine orphan, not mine; browser-walk confirmation added to PR
---

Merged origin/main (fast-forward wasn't possible -- merge commit a14439a, task-file-only diff as you said). Pushed. Fresh receipt:

```
ci-local: NOT RUN -- ruff
ci-local: plugin built in this run -- a14439a src=4826dd35bd0e sha256=5AD4F6E64CDAD96F429E3E660E90CC0015B95AE7D348A70BC8010AEBB71F8551
ci-local: PASS  task059-fixture-folder-per-suite@a14439a  -> work/scratch/ci-local/task059-fixture-folder-per-suite-a14439a.json
```
173/173 Pester still green.

Both answers:

1. **00-t054/save-load.scx is not mine.** I never set AGENT_TASK=054 or wrote there -- my repros used $env:TEMP with fake id 999, my real run resolved to 00-t059-save-load off this worker's own AGENT_TASK=059. Its mtime (03:00:00) predates my first real launch tonight (03:45). It's a genuine orphan: task 054 merged and was reaped, so nothing will ever visit that folder again to run its crossload/cleanup. Added a note to the PR body citing it as a second, distinct symptom of the old scheme -- a stranded folder from a task that never ran its own last phase. Flagging: my fix does NOT clean this up or prevent it recurring for a single-suite task that skips its cleanup phase; it only stops two DIFFERENT suites of one task from colliding. Worth a line in #80 if you want it recorded there too, your call.

2. **How the browser walk was confirmed, added to the PR body (criterion 5):** not staged -- 00-t054 sat there the whole time as a genuine second 00-t* folder alongside my 00-t059-save-load (00-t054 sorts first alphabetically). All three phases' transcripts independently recomputed the listing fresh each launch and landed on row 2 correctly:
```
browser: C:\sc-work\1161-base\Maps\BroodWar -> [00-t059-save-load] (row 2, y=159)
browser: selecting save-load.scx (row 2, y=159)
browser: row 2 selected a map (info panel 5E40C4A0271B923E -> 3B0ACF2642F87DEF)
```
The info-panel hash changing is Assert-ScBrowserMapSelected's own live check that row 2 opened a map, not a folder -- across 3 separate real launches, never a hardcoded row. What I did NOT do: synthesize a 3+-folder case on purpose. Two folders is what existed naturally; said so in the PR rather than implying more than that.

PR body updated: https://github.com/inwenis/decompile-sc/pull/89
