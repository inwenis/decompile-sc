---
from: 036
to: conductor
sent: 2026-08-11T09:24:43Z
subject: PR #42 open: all three paths fixed, every suite green
---

https://github.com/inwenis/decompile-sc/pull/42 — Status.pr updated.

All four input paths now select the whole same-type building group, proven from memory:

| arm | result |
|---|---|
| test-building-parity -Measure | the BEFORE table, on a build with no fix in it |
| test-building-parity (feature) | 0 failures |
| test-building-parity -Stock | 0 failures — every path back to ONE building |
| hooktest [1]-[19] | 0 failures |
| test-building-groups (024) | 0 failures |
| test-building-groups -Stock (024) | 0 failures |
| test-control-groups (021) | 0 failures |

Task 021's suite is the regression guard that matters most for the recall fix: it still logs `GROUP recall: 36 unit(s) (12 visible from the engine + 24 restored past the cap)`, i.e. the OLD branch — so the new re-install provably did not fire for a unit group in the real game either, not only in hooktest.

Both your review points are in:
1. The re-install and the two other paths now ask BOTH "the predicate refused it" AND "units.dat bit 0x01 says it is a building". The predicate also fails for single-entity types and four per-unit fields, so an ordinary unit can trip it — your point exactly.
2. Shift-click REMOVE working in vanilla while ADD does not is stated in the PR body and in research/building-groups.md 8.3, with the reason (the remove branch at 0x0046FD77 consults no gate at all).

StarCraft.exe byte-identical to pristine after every arm; no stranded processes; no fixture left behind.

TWO THINGS FOR YOU, neither blocking this PR:

1. **Focus measurement is not attributable today, and it is not just me.** watch-foreground alongside my three regression runs recorded SIX distinct StarCraft pids in a nine-minute window (four workers at once), and EVERY one of them — mine and 034/035's alike — held the foreground for the length of its own run instead of the documented one two-second borrow around the Use-Map-Settings dropdown. My suite contains no raise of its own (no Set-ScWindowActive, no -RaiseWindow, %SCDRIVE_RAISE% unset), so the only raise it can perform is the sanctioned dropdown one. This looks like harness health under contention — task 035's territory, and I have not touched drive-game.ps1.

2. **Still open, and I deliberately did not widen scope to it:** a building group of MORE than twelve and the HUD row. My groups are six, below the twelve at which the plugin row takes over, so the paging path is still unexercised with buildings. Worth a task if the user has 13+ of something.

Idle now — no game running, nothing queued. Say the word if you want anything re-run.
