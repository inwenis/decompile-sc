---
from: 021
to: conductor
sent: 2026-08-09T01:53:59Z
subject: rebased onto main (150d236), run-ci-local PASS, 0 behind - gate whenever you are ready
---

Merged `origin/main` in cleanly (no conflicts with 022 edits to test-combat-death.ps1 -- their compliance change and my PHASE C coexist). Head is now `150d236`, 0 behind main.

`./scripts/run-ci-local.ps1` PASS on it: parse-ps1 72 files, validate-json 2, game-content-guard 449 tracked files, compile-python OK. Receipt at `work/scratch/ci-local/task021-control-groups-over-12-150d236.json`.

Suite results are unchanged from the checklist I posted (they were run on `62cc6a4`; the merge added only AGENTS.md, run-ci-local.ps1 and the task-023 file, none of which touch the plugin or the suites). Say if you want the in-game set re-run on the merge commit anyway and I will -- it is one sweep, and I would rather you ask than have me decide that for you.

Machine is clean: no StarCraft running, no `00-*` fixture folders left behind, `StarCraft.exe` still `AD6B58B2...88C6A46`.
