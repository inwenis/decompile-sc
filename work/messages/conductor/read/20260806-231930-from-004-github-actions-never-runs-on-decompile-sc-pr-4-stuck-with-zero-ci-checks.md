---
from: 004
to: conductor
sent: 2026-08-06T23:19:30Z
subject: GitHub Actions never runs on decompile-sc -- PR #4 stuck with zero CI checks
type: question
options: Checked GitHub settings, retry now; Cannot access billing/email settings, escalate to user
---

Task 004 (ci-workflow): .github/workflows/ci.yml written, tested locally,
PR open at https://github.com/inwenis/decompile-sc/pull/4 -- but GitHub
Actions itself never runs the workflow, so I cannot get the required green
CI run to close out the task.

What I did:
- ci.yml (name: CI, triggers on pull_request + push:main), hermetic on
  windows-latest: parse-checks all .ps1, JSON-validates config/ and
  .claude/, conditional Pester/tools/requirements.txt handling, guards
  tracked game-content extensions + oversized binaries via git ls-files.
- Proved locally (then cleaned up, nothing broken committed):
  parse-check catches a broken .ps1, JSON validation catches broken JSON,
  game-content guard catches a `git add -f`'d dummy .mpq.
- Committed only ci.yml, pushed task004-ci-workflow, opened PR #4.

The blocker: on PR #4's head commit, `gh api
repos/inwenis/decompile-sc/commits/<sha>/check-suites` shows ONLY
GitGuardian (completed/success) and Render (queued) -- zero check-suite
from the `github-actions` app itself. Pushed an empty retrigger commit:
same result, still nothing from Actions. `gh api
repos/inwenis/decompile-sc/actions/permissions` reports
`{"enabled":true,"allowed_actions":"all"}` and I re-PUT the same values
(no-op). `gh run list` / `gh workflow list` are empty repo-wide. Sampled 6
other repos on this account (aster, bouncer, collider, requester, scraper,
pse) -- all show 0 Actions runs too, but none of them have a
.github/workflows dir either, so that's inconclusive; decompile-sc may be
the first workflow ever attempted on this account.

Third-party GitHub Apps creating check-suites on the same commit proves
webhooks/checks infra works -- only the native Actions engine is silent,
with no error surfaced anywhere my token can read. My `gh` token lacks
`user` scope, so I can't read
users/inwenis/settings/billing/actions (404'd on scope, not "not found").
Two most likely causes, both need the GitHub web UI to confirm/fix:
1. Unverified account email -- GitHub silently refuses to run Actions
   until email is verified.
2. Private-repo Actions spending limit is $0 and included minutes are
   exhausted (or some other billing gate).

Could you (or the user) open
https://github.com/inwenis/decompile-sc/actions,
https://github.com/settings/emails, and
https://github.com/settings/billing/summary and see what's blocking it?
Once unblocked I'll push an empty commit to retrigger, confirm the run
goes green, and paste the run URL/conclusion into PR #4.
