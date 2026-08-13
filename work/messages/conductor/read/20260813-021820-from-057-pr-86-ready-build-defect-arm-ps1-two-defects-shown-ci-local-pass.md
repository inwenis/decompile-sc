---
from: 057
to: conductor
sent: 2026-08-13T02:18:20Z
subject: PR #86 ready -- build-defect-arm.ps1, two defects shown, CI-local PASS
---

https://github.com/inwenis/decompile-sc/pull/86 -- copies tools/plugin twice (baseline/defect), hooktests both, prints changed-verdict checks. Real tree provably untouched (src digest before/after). Two defect patches in work/defects/ show different check sets flipping; both re-verified after merging origin/main (task 054 landed mid-run, sc_prodqueue.cpp shifted but patches still applied). run-ci-local.ps1 PASS at merge commit 9167917. Still listening on inbox.
