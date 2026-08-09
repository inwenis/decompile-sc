---
from: 023
to: conductor
sent: 2026-08-09T17:16:22Z
subject: READY - reconstructed: all suites green and PR body drafted; only the Ghost Cloak item + rebase/CI/PR remain
---

Re-read task file, my three uncommitted diffs, and work/scratch/023/pr-body.md. Inbox monitor re-armed. Where I actually am:

DONE and committed (db294a6..5e92836):
- Select-ScBrowserMap: every browser click computed from disk, browser scrolled to a known top (Sync-ScBrowserToTop), row verified by the browser own map-information read-back (Assert-ScBrowserMapSelected). Covers level 3 - probe-browser-rows.ps1 demonstrates it with two 00-t* folders present, decoy sorting first.
- New-ScFixtureRun: per-run ownership over a declared set of names (kills the combat-death self-deadlock without softening the rule). -FixtureDir on every suite. One fixture name per suite (burrow-fanout.scx / hud-row.scx).
- Assert-ScWindowActive as the single foreground gate on click/move/drag/dropdown; throws rather than posting into a no-op.
- ScLog exit path: waits 250 ms then writes anyway (the detach loss was a DEAD-owned lock, not a transient race - no wait can win it). hooktest [12] reproduces it and fails against pre-023 code.
- Get-ScSelectionGroup nested-array bug (test-stim-fanout was reporting a fake engine finding).
- tests/ with 16 Pester cases.

THE CONFIRMING EXPERIMENT IS RUN AND IT CONFIRMS: test-fanout-orders 0 failures, test-selection-circles 0 failures, first attempt. All eight in-game suites green pre-reboot.

UNCOMMITTED, finished: doc-comment fixes in drive-game.ps1 / probe-browser-rows.ps1 naming the assertion that replaced Assert-ScBrowserListing, plus probe-ghost-cloak.ps1 extended with sweep B (single Ghost control) and sweep C (the nine command-card slots clicked).

REMAINING, in order:
1. rebase onto origin/main (I am at 5e92836, behind 176b4f9).
2. untrack testResults.xml - Invoke-Pester -CI wrote it and I committed it by accident; gitignore it.
3. run probe-ghost-cloak sweep C. Sweep A+B are DONE and negative: no key A-Z emits Personnel Cloaking (0x21) at either selection size, and the keyboard path is proved live by H=0x2B and S=0x1A. Sweep C clicks the card slots to name the button - that is the only open question left.
4. run-ci-local.ps1 receipt on the final head sha, then PR.

No blockers. No StarCraft running, launch lock free - will verify again before the run.
