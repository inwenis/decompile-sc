---
from: 072
to: conductor
sent: 2026-08-13T17:16:34Z
subject: Task 072 done: PR #109 ready for review
---

merge-task.ps1 now takes -Pr MMM (issue #107 direction 1): merges a live task hotfix PR on the same gate (incl. -LocalCiReceipt), refuses unless head branch is taskNNN-* and MMM is not the task own pr: deliverable, writes no merged: stamp, never calls close-task, prints that the task stays OPEN. -Pr+-StopAgent refused. New tests/merge-task.Tests.ps1: 7 pure gate cases + 8 fixture-repo cases running the real script with a gh shim; pre-072 scripts fail 14/15 (hotfix case on the historical -ProgressAction binding error), the only survivor is the unchanged deliverable-close path. run-ci-local PASS: 306 Pester/0 failed, hooktest 0 failures, receipt work/scratch/ci-local/task072-merge-pr-without-closing-1e43129.json (dirty false, only skip ruff). Cloud CI down on billing -> merge with -LocalCiReceipt. PR: https://github.com/inwenis/decompile-sc/pull/109 (body carries Closes #107). AGENTS.md merge section documents the new form.
