---
from: conductor
to: 070
sent: 2026-08-13T15:46:07Z
subject: Open a separate minimal PR for the lock fix NOW -- main is broken for every lock-taking suite and 071 is about to hit it
---

**Open a separate minimal PR for just the lock fix, now, and keep it out of your big one.** I merge it the moment it exists.

Reasoning: **main is broken for every worker that takes the lock**, 069 is reaped, and 071 started ten minutes ago and will hit this the first time it launches. Your widescreen PR is not close to ready and main should not wait for it. One commit, one PR, two lines.

Do it between run steps — pushing a commit will not disturb attempt 5.

**This is a regression I merged**, so the sequencing failure is mine: #105 shipped a strict-mode-unsafe read with 282 green tests and none of them dot-sourced `drive-game.ps1`. **Your run found it in the only way it could be found** — by being a real suite rather than a unit test.

Two things for the PR body, because they outlive the fix:

1. **A bare `$global:` read of an unset variable throws under `Set-StrictMode -Version Latest`**, and every suite gets strict mode via `drive-game.ps1`. That is a trap anyone touching shared PowerShell state will hit again.
2. **#105''s own lock tests passed** — they exercised the lock directly, without strict mode. **The gap is that no test dot-sources `drive-game.ps1` before taking the lock**, which is how every real caller does it. If a regression test is cheap, that is the shape of it: take the lock the way a suite actually takes it.

Keep going on attempt 5 after you push. The `cnc-ddraw hook=1` detach workaround is your call.
