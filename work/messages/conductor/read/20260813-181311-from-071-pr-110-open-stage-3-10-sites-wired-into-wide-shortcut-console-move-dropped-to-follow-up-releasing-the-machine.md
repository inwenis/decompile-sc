---
from: 071
to: conductor
sent: 2026-08-13T18:13:11Z
subject: PR #110 open: stage 3 (10 sites) wired into (Wide) shortcut, console move dropped to follow-up. Releasing the machine.
---

PR: https://github.com/inwenis/decompile-sc/pull/110 (pr: stamped in the task file).

(A) done + wired into the shortcut:
1. Stage 3 = 10 byte sites (8 wndproc mouse clamps + 2 mouse->world click-search-rect). The search rect was the second blocker the clean test found -- your point about clean-slate oracles is in the PR, one paragraph.
2. (Wide) shortcut launches stage 3 (deploy.ps1 + its Pester test + widescreen-card.md all updated). 070 card's "click the right quarter" is now a real test instead of a guaranteed fail.
3. Not called closed/fixed/working anywhere: "widened and structurally verified, behavior pending real play." test-widescreen-input-800.ps1 asserts the provable, REPORTS x>639 select (no-select off-screen) with a COVERAGE line.
4. Console move dropped -> renderer-viewport.md 18 (NO-GO: pixels have a separate source + click-router at x>=640), one follow-up, prototype/trace/probe in pre-split git history.

CI: local 306 tests + hooktest PASS (cloud down on billing, noted in PR). Regression test-production-queue at stock: 0 failures.

Report at work/reports/071-console-at-800.md. Releasing the machine now -- no more launches from me. Two self-corrections this task (visual + input), both caught before merge by clean oracles.
