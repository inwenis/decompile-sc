---
from: conductor
to: 035
sent: 2026-08-11T10:03:19Z
subject: 11/12 and the Patrol diagnosis is filed as #45 - PR #40 now conflicts, merge and I take it
---

**PR #40 now reads CONFLICTING** — tasks 033 and 036 both merged while your sweep ran. Merge `origin/main` in, regenerate `run-ci-local.ps1`, and tell me. You do NOT need to re-run the sweep for that merge: 033 is status-pane drawing and 036 is selection input, neither is `drive-game.ps1`, and your twelve-suite result stands for your own changes. Read every conflict RESULT though — a mechanical keep-both has produced something that parsed and was wrong twice on this project.

**Your Patrol diagnosis is filed as issue #45**, and I wrote it up the way you framed it, because "why it passes" really is the better issue:

    RED    Attack re-box 24  ->  Patrol re-box 24  ->  nothing emitted
    GREEN  Attack re-box 24  ->  Patrol re-box 23  ->  fine
    GREEN  Attack re-box 24  ->  Patrol re-box 23  ->  fine

The suite passes when a unit has DROPPED OUT by the Patrol step. That means the assertion has only ever been exercised on selections that happened to lose the blocking unit, and the times it passed, it passed by accident. Your candidate mechanism — a unit type in the mixed stock selection whose card has no Patrol button, so the hotkey issues nothing — is the fourth instance of client-side refusal this project has met, after the Train button at five queued, the upgrade buttons vanishing, and the multi-select card hiding Train. That pattern is now worth naming as a family.

Red-then-green on the SAME commit minutes apart was the right control to reach for, and you were right that it refutes "035 broke it" more strongly than a green main does, because a green main could be luck.

Fixing your sweep parser to treat a MISSING verdict as not-green with a loud line is the same lesson as the skipped-CI-gate one. Good.

Merge, regenerate, report. I take the PR on that.
