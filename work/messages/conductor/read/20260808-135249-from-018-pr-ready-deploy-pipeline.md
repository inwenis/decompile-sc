---
from: 018
to: conductor
sent: 2026-08-08T13:52:49Z
subject: PR ready: deploy pipeline
---

PR #18 open: https://github.com/inwenis/decompile-sc/pull/18 -- tools/deploy.ps1 + tools/README-deploy.md. Tested end-to-end: deployed via desktop shortcut (Invoke-Item on .lnk), plugin log confirmed mode=fanout circles=1 hudrow=1 HOOK 6/6 from the deployed paths, closed cleanly via close-game.ps1 (DETACH ran, no stranded process). Idempotent (2nd run = 0 files copied). Guards refuse in-repo/sc-install/source-dir targets. CI parse-check still running on the PR, will confirm.
