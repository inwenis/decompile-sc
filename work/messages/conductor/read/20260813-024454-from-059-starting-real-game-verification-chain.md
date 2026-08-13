---
from: 059
to: conductor
sent: 2026-08-13T02:44:54Z
subject: starting real-game verification chain
---

Fix implemented + unit-level repro done (deadlock reproduced pre-fix, gone post-fix; foreign-file guard still refuses a real foreign file -- all via drive-game.ps1 functions against a scratch dir, transcripts in work/scratch/059-repro-*.ps1 output). Now running test-save-load.ps1 for real (control -> fanout -> crossload, back to back) to prove the multi-phase fixture still survives across phases under the new per-suite folder (acceptance criterion 3). ~3 launches, machine is mine per the task file.
