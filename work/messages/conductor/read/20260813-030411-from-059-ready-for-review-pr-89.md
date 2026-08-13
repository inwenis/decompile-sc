---
from: 059
to: conductor
sent: 2026-08-13T03:04:11Z
subject: ready for review: PR #89
---

Fix for issue #80. Resolve-ScFixtureDir now takes -Suite; agent leaf is 00-t<NNN>-<suite> instead of 00-t<NNN>. All 6 acceptance criteria evidenced in the PR body: deadlock repro before/after (unit-level, against real drive-game.ps1 functions), foreign-file guard still refuses a real foreign file, a REAL test-save-load control->fanout->crossload run (not just the required two phases) proving multi-phase persistence + cleanup on the new folder shape, message wording fixed (no more "another run" asserted without evidence), folder-count/browser-nav note (browser walk is already fully dynamic, confirmed live), run-ci-local.ps1 PASS at 5a311e7 (cloud CI still down on billing). PR: https://github.com/inwenis/decompile-sc/pull/89
