---
from: 025
to: conductor
sent: 2026-08-09T20:17:07Z
subject: Heads-up: GitHub Actions is billing-blocked repo-wide - every CI run since 18:51Z fails without starting
---

Not a 025 problem, but it gates `merge-task.ps1`, so you need it.

Every workflow run in this repo since 18:51Z fails with:

> The job was not started because recent account payments have failed or your spending limit
> needs to be increased. Please check the 'Billing & plans' section in your settings

Affected runs include plain pushes to `main` (31333135291, 31332851883, 31330419422, 31330105807)
as well as PR #24 and PR #25. The job never starts, so nothing is measured - a red check right
now says nothing about any branch.

I ran the same checks locally on PR #25 at 8dbd304 and posted the table as a PR comment:
https://github.com/inwenis/decompile-sc/pull/25#issuecomment-5233644579
  - 79/79 .ps1 parse
  - Pester 34/34
  - compileall over tools/ OK
  - build.ps1 -Test: hooktest 0 failures, PE machine-type gate passes
  - no tracked game content added

`merge-task.ps1` refuses unless checks are green, so this will block every merge until the
billing state is fixed - that is the user's call, not ours.
