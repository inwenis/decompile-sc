---
from: 046
to: conductor
sent: 2026-08-12T08:16:41Z
subject: DONE: PR #53 open -- stale SORT regex was the cause, not the feature
---

PR: https://github.com/inwenis/decompile-sc/pull/53 (also in Status.pr)

## Root cause -- the suite's regex, not the feature

Task 042 (#42, building groups) changed the plugin's SORT log line from
`candidates=%d -> selected=%u ...` to
`candidates=%d clicked=0x%08X -> engine=%u selected=%u%s ...`.
`test-selection-circles.ps1`'s regex (`SORT candidates=(\d+) -> selected=(\d+)`) was
never updated and stopped matching ANY line -- verified against a real captured log
line (old regex: False, fixed regex: True). `test-building-parity.ps1`'s
`Get-ScSortLines` already carried the post-042 shape; this suite was the one sibling
#42 never touched. Fix mirrors that pattern.

## Evidence, all off-screen (run-offscreen.ps1, task 043's mechanism)

1. Fix verified green: 0 failures, part [5] included. Real SORT line for the 24-unit
   box: `candidates=24 clicked=0x00000000 -> engine=12 selected=12 (accumulated beyond
   the cap: 24)` -- matches shadow/circle/fan-out oracles in the same run
   (shown=24 hidden=12 held=12 lost=0, same numbers as your task 043 report).
2. Assertion proved not vacuous: temporarily raised the bound to `-gt 1000`
   (impossible), reran -- FAIL at exactly part [5], everything else still green.
   Reverted before the commit; final diff is the one-line regex fix plus a comment.
3. `scripts/run-ci-local.ps1` PASS at `6a2222c` (77 Pester tests, hooktest 0 failures,
   ruff skipped -- not installed). Actions still down on the billing error; the local
   receipt is the gate.

## FYI, not touched (out of this task's scope)

`test-combat-death.ps1` line 1251 has the same stale half-pattern
(`SORT candidates=\d+ -> selected=\d+`), but it's OR'd with a `SHADOW captured:` match
so it currently still passes. Same fossil, no active bug -- flagging in case a future
task wants to clean it up alongside this one.

## Machine state

No StarCraft process of mine left running (posted WM_CLOSE, exited cleanly every run).
Launch lock acquired/released cleanly each time -- saw it briefly held then released by
other workers' launches too, nothing stuck. Idle and listening on my inbox.
