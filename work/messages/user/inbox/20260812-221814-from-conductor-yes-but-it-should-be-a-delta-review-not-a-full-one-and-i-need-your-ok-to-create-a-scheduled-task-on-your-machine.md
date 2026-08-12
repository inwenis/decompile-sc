---
from: conductor
to: user
sent: 2026-08-12T22:18:14Z
subject: Yes -- but it should be a DELTA review, not a full one, and I need your OK to create a scheduled task on your machine
type: question
options: Task Scheduler on this laptop, monthly + every 10 merged tasks (recommended); Task Scheduler, monthly only; Scheduled cloud agent instead, accepting it cannot see local logs; Do not schedule it -- I will ask when I want one
---

Yes — but not with the thing I am currently using, and there is a design point worth settling before the cadence.

## What I am using right now does NOT count

The board sweep that runs every 17 minutes tonight is an in-session job. It lives in this Claude session's memory, is never written to disk, and dies the moment the session ends. It also auto-expires after 7 days. Fine for tonight's shift; useless as "review the architecture every month".

## Three real mechanisms, and they are not equivalent

1. **Windows Task Scheduler on this laptop** → runs a small script → cuts the task file and spawns a worker, exactly as I did by hand tonight. Durable across reboots, and crucially it can see `C:\sc-work\logs\` — the local run logs. That matters more than it sounds: tonight's single best finding, the indicator that has never been drawn, came out of a log file on your disk, not out of the repo.
2. **A scheduled cloud agent.** Durable and needs nothing running here, but it only ever sees what is pushed to GitHub. No run logs, no frames, no deploy directory. It would find duplication and unenforced invariants; it would not have found `indInk=2368`.
3. **A gate rather than a clock** — run the review every N merged tasks instead of every N days. Arguably the better trigger, since risk here accumulates per change, not per week. We merged four tasks tonight.

**My recommendation: 1, monthly, plus 3 at every 10 merged tasks, whichever comes first.**

## Before I set anything up — the shape should change after tonight

A recurring FULL review is the wrong job. The second run over 41,000 lines would spend most of its budget re-deriving findings already in the first report and already in AGENTS.md, and the noise would train us to skim it.

What the recurring version should be is a **delta review**, anchored to the previous report:

1. everything merged since the last review, read properly;
2. specifically checked against the defect classes we already know we produce — assertions that cannot fail, duplicated mental models, invariants relied on but never expressed — because a repo that has made the same mistake five times will make it a sixth;
3. and a short verdict on whether the previous report's open findings got fixed, deferred deliberately, or quietly forgotten. That third category is the one worth catching.

Task 052 is the baseline that makes all of that possible. It has to land first regardless.

## One thing I will not do without you saying so

Creating a Windows scheduled task writes state to your machine outside this repo. After the registry incident on 08 Aug that is a line I do not cross on my own initiative, even for something this harmless. So: the options on this message are the ask, and if you pick the Task Scheduler route I will show you the exact command before running it.

Everything repo-side I can prepare without touching your machine — the delta-review task template and the script that cuts it — I will have ready either way.
