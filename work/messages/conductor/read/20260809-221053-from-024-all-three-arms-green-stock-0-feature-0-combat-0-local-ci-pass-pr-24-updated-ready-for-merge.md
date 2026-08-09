---
from: 024
to: conductor
sent: 2026-08-09T22:10:53Z
subject: ALL THREE ARMS GREEN - stock 0 / feature 0 / combat 0, local CI PASS, PR #24 updated, ready for merge
---

Released, rebased, rebuilt, ran. All three in-game arms are green on the no-raise harness.

## Results

| arm | failures | headline numbers |
|---|---|---|
| `-Stock` | 0 | box over 16 turrets -> `n=1 visible=1`, `simSlots=1`, no `BGROUP box:` line |
| default (feature) | 0 | `n=16 visible=12 overflow=4`, `circled=16/16` (over-cap 4/4); rally `FANOUT start: cmd=0x14 units=6 slots=1 -> 6 Select+order pairs`, one rally bucket over all six; mixed box -> one type only (`0x6F:2`); single click -> `n=1` |
| `-Combat` | 0 | 6/6 boxed alive, first death 19s later -> `5 live of 6` `hp0=1`; `out=5 dropped=1`, identity `6 = 5 + 1`; each drop named its term; rally reached the five survivors |

- `run-ci-local.ps1`: PASS on the head (82 .ps1 parsed, 34 Pester, game-content guard 657 files, hooktest 0 failures). `ruff` NOT RUN -- not installed, as you said.
- `StarCraft.exe` hashed before/after every arm, byte-identical to pristine 1.16.1 each time.
- Fixture folder `00-t024` removed; no stranded process of mine (all six pids closed by pid).

## Foreground

`watch-foreground.ps1` ran alongside every arm. Exactly ONE borrow-and-return pair per arm, ~2s, around the Use Map Settings dropdown -- the one raise AGENTS.md sanctions. Focus back to the user`s window every time. During the combat arm the user was using Search and Settings on the same machine; the run did not disturb them.

## Three defects found, all in the TEST, none in the engine or plugin

Running the two outstanding arms was not a formality -- it found three assertions that could not fail. Details in `research/building-groups.md` 6.1 and in the PR.

1. Stock arm boxed the wrong block (full-screen drag reached both). Fixed by converting map positions to client coords through the viewport origin, not by loosening the assertion.
2. Combat fixture killed the group faster than the suite could command it: all 16 turrets dead before the right-click, so "no dead tag reached the wire" passed with ZERO tags on the wire. Fixture now dies as a trickle (4 marines, 60% HP) and the suite waits for a genuinely MIXED selection (`0 < live < n`).
3. The arm commanded a building type that accepts NO command. A Missile Turret is immobile and non-production -- no move order, no rally point -- so a right-click with 16 selected queues nothing: the engine`s command stream held only 0x37 syncs, not one 0x14. Combat arm now boxes 6 Barracks, and asserts `FANOUT start:` is present BEFORE asking what the fan-out did.

Also swapped this suite off the fixed-point tips click onto `Dismiss-ScTipsDialog` -- it was the last one still on (200,261).

## One thing to know about the branch

The remote branch still held my two commits from BEFORE the rebase onto current origin/main (same content, different hashes -- task-024 files byte-identical, verified with git diff). I did NOT force-push (ask-first rule, and your note). I absorbed the old tip with a `-s ours` merge so the tree stays the rebased one and the push was a fast-forward. Nothing discarded; the branch is a strict superset of the old tip plus current main.

## Not mine, flagging it

- GitHub Actions "Parse, lint and import checks" fails with "The job was not started because recent account payments have failed or your spending limit needs to be increased". Every recent run on `main` fails identically -- billing, not code. Local CI is the green one.
- One StarCraft process (pid 140156) is alive and is NOT from any of my arms. I left it alone.

PR #24 body rewritten with the full table and the three defects: https://github.com/inwenis/decompile-sc/pull/24

Ready for your merge. I have not merged it.
