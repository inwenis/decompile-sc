# Task 024 — Select same-type buildings as a group

## Status

agent: 024
model: opus
pr: -

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task024 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task024-building-groups.
- Task-file edits, reports, messages: directly in C:/git/decompile-sc (main
  checkout, no commits there — conductor commits; you are the only writer).
- NEVER edit tracked content in the main checkout.
- Destructive/irreversible actions beyond your own worktree (deleting user
  files, force-push, merging PRs, killing processes) → stop, ask in your tab
  or message the conductor first.
- NEVER delete/overwrite anything under C:/git/decompile-sc/work/messages/
  (2026-07-17 data-loss incident class — real user messages live there).
- C:/git/conductor and C:/git/conductor-task* are ANOTHER LIVE SYSTEM (a
  separate orchestrator with in-flight agents and real user messages).
  NEVER read, modify, cd into, or run git/gh against them — off-limits
  absolutely (guard hooks also enforce this). Your world is
  C:/git/decompile-sc and your own worktree only.

## Game-file rules (project hard rules)

- NEVER commit game binaries, MPQ archives, extracted assets, or anything
  derived from them that reproduces game content. The repo tracks findings
  and tooling only.
- The local game copy lives at an ignored path (game/) and is READ-ONLY to
  workers.
- Never point a modified binary at Battle.net or any online service. Offline
  and single-player only.
- Every claimed address/offset/struct must carry evidence: how it was found
  and how it was verified. No guessed offsets in research/.

## Messaging

- Your inbox: `C:/git/decompile-sc/work/messages/024/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 024 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

**Box-select a group of the same building type and have them act as one selection**, the way units
already do. User: "enable selecting same type of building in a group just like units." Vanilla
selects one building at a time; after this, a drag box over N same-type buildings selects all N,
they get selection circles, and a command (rally, or whatever a building accepts) reaches all of
them.

## Context

- **First establish what the engine actually does today**, with evidence, before designing:
  - Why does a box select only one building? Is it a filter in the selection-commit path
    (`CMDACT_Select` / `0x004C0860`, mapped in `research/command-path.md` and
    `research/binary-selection-map.md`), a property on the unit/building record, or the box-select
    hit-test refusing to accumulate buildings? Find the exact gate and cite it.
  - What commands does a building even accept? Rally point is the obvious one; the opcode table in
    `research/command-opcodes.md` classifies every command's handler — check which are meaningful
    for a multi-building selection and which must stay single (production, cancel — the passthrough
    set from task 015 still applies).
- **This is the same machinery you already own.** The shadow-selection list (`sc_fanout.cpp`), the
  liveness gate (`research/fanout-liveness.md`, task 020 — REUSE it, buildings die too), circles
  (`research/selection-circles.md`), the HUD row (`research/hud-selection-row.md`), and control
  groups (`research/control-groups.md`) are all built. The question is whether buildings can flow
  through that same path or whether something building-specific blocks them.
- **Design decision, stated with evidence:** is a same-type building group just "the unit fan-out
  path with the box-select building filter relaxed", or does it need its own path? Cheapest first;
  report your choice before building, but proceed on your recommendation — I will redirect if I
  disagree.
- Scope discipline: SAME-TYPE only (the user said "just like units" — a mixed box of buildings is
  not asked for and vanilla does not do it). State what happens to a mixed box.
- **Concurrency, important:** task 025 (production queue >5) may be editing `sc_fanout.cpp` /
  `sc_addresses.h` at the same time. Rebase onto `origin/main` before you finish, expect possible
  conflicts in those files, and if your change and 025's must touch the SAME function, STOP and
  message the conductor rather than guessing a merge.
- Test discipline is now enforced by tooling (task 023, merged): generate into your own
  `Maps\BroodWar\00-t024\` via `-FixtureDir`, name the fixture after the suite, declare it to
  `New-ScFixtureRun`, use `Select-ScBrowserMap` (never a hardcoded row), every move goes through
  `Assert-ScWindowActive`. `make_test_map.py` places buildings — check the unit-id table for the
  building types. `run-with-plugin.ps1` takes the shared launch lock, so your run serialises with
  024/025/026 automatically.
- Never write `CSprite::selectionIndex`, never set sprite flag `0x08` (inherited discipline).

## Hard rules

1. Never modify, write to, or launch `C:\sc-install\Starcraft`. Working copy only.
2. Offline, single-player only. `StarCraft.exe` on disk stays byte-identical; tests assert it.
3. Passive mode (`-Mode observe`) stays stock.
4. Never write live user state — AGENTS.md hard rule 5 (`HKCU:\SOFTWARE\Blizzard Entertainment\*`
   off limits).
5. Commit no game content, no binaries, no logs, no generated maps, no screenshots.
6. Do not merge your own PR.

## Acceptance criteria

1. The box-select building gate identified with evidence (address, how found, how verified), and
   the design choice stated with reasoning.
2. Unattended in-game test: a drag box over >1 same-type building selects all of them, asserted
   per-building from in-process state; circles appear; a building-valid command reaches all.
3. Liveness intact: a building in the selection is destroyed, and the selection/command path does
   not hand the engine a dead one (reuse task 020's gate); asserted.
4. Mixed-box and single-building behaviour stated and, where it must stay stock, asserted stock.
5. No regressions: all in-game suites + hooktest green (via `run-ci-local.ps1` for the offline
   half, and the in-game suites recorded with counts); exe byte-identical; no stranded processes.
6. PR opened, link in Status.pr.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/024-building-groups.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
