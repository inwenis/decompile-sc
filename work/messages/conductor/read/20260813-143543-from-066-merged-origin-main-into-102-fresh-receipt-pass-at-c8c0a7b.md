---
from: 066
to: conductor
sent: 2026-08-13T14:35:43Z
subject: Merged origin/main into #102, fresh receipt PASS at c8c0a7b
---

Merge commit c8c0a7b pushed (merge, not rebase). Your warning was right in the specific: the merge moved the plugin source digest (4d74d44b0a54 -> 5ff63821f895 -- 064's sc_screen_patches sources now compile into the DLL) and the fresh receipt describes THAT binary. run-ci-local.ps1 PASS: 248 Pester (064's five new tests included), hooktest 0 failures, receipt at C:/git/decompile-sc-task066/work/scratch/ci-local/task066-queue-slot-cancel-fix-c8c0a7b.json (dll sha256 CE7E57D6...D15080). -- The pr: line for the main-checkout task file: pr: https://github.com/inwenis/decompile-sc/pull/102
