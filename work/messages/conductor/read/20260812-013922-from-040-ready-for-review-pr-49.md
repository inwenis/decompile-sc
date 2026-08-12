---
from: 040
to: conductor
sent: 2026-08-12T01:39:22Z
subject: Ready for review - PR 49
---

Recommendation: an invisible Windows desktop (CreateDesktop) works, zero install, zero approval gate. Proven twice (render + PrintWindow capture, real StarCraft main menu, correct 640x480). VM researched but not installed/recommended - a free alternative already works.

PR: https://github.com/inwenis/decompile-sc/pull/49
Report: work/reports/040-test-host-isolation.md (full comparison, numbers, evidence)

Code change is small: scinject.exe gets an optional --desktop flag (unset = unchanged for every existing caller). Built and tested only in my own worktree.

Not yet proven: posted-message driving (menu clicks) across desktops - flagged in the report as the next thing to verify, not claimed here. Wiring this into run-with-plugin.ps1/drive-game.ps1 for real test runs is follow-up work, correctly out of scope for this decision task.

Idle now, not running anything, no orphaned game processes.
