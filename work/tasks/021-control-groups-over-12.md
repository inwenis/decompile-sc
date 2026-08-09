# Task 021 — Control groups can hold more than 12 units

## Status

agent: 021
model: opus
pr: https://github.com/inwenis/decompile-sc/pull/21
merged: 2026-08-09

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task021 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task021-control-groups-over-12.
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

- Your inbox: `C:/git/decompile-sc/work/messages/021/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 021 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

**Ctrl+1 on a 24-unit selection must store all 24, and pressing 1 must bring all 24 back.** From the
user's own play session, verbatim: "when I select more than 12 units I cannot create a control
group of more than 12 units I would like that to work."

## Context

- The engine's hotkey path is already partly mapped: `sc_fanout.cpp` handles opcode `0x13`
  (hotkey), and the shadow list is TRUNCATED on a hotkey recall today — find that code
  (`g_shadowVersion` bump on the 0x13 drop) and understand why it was written that way before
  changing it; it was deliberate, not an accident.
- The engine's own control-group storage is the thing to map first: where the 10 groups live,
  how many slots each has (almost certainly 12), what a Ctrl+N write does, and what an N recall
  does. Evidence rule applies to every address/offset. `research/binary-selection-map.md` is the
  starting point for the selection arrays; the control-group arrays are adjacent work.
- Design decision you must make explicitly and justify: where do units 13..N of a group LIVE?
  Options, cheapest first: (a) plugin-side shadow groups, ten of them, mirroring the engine's
  ten — recall then re-runs the fan-out select path we already have; (b) widen the engine's own
  arrays in place (only if the surrounding code is bounds-driven rather than fixed-12 — prove it);
  (c) something the code suggests. Report your choice with reasoning BEFORE building, but you do
  NOT need to wait for my reply — proceed on your recommendation and I will redirect if I disagree.
- Interactions to get right, each of which needs a test:
  - Ctrl+N with >12 selected, then N — full group returns, and a subsequent order fans out to all.
  - Shift+Ctrl+N (add to group) if the engine supports it; state what you found.
  - A unit in a >12 group dies — recall must not resurrect it. The liveness gate from task 020
    (`research/fanout-liveness.md`) is the reference: reuse it, do not reinvent it.
  - Group recall while a >12 selection is already active.
  - Saving/loading a game must not corrupt anything: state what happens to plugin-side groups
    (they are memory-only; a load with stale groups must be safe, not merely unlikely).
- The HUD row and circles must reflect a >12 recall exactly as they do a >12 drag box — those are
  merged features (tasks 014/017) and this must not regress them.
- Discipline inherited: never write `CSprite::selectionIndex`, never set sprite flag `0x08`
  (`research/selection-circles.md` §4), pinned-id assertions, positive preconditions, no vacuous
  passes, pid-scoped process handling, `run-with-plugin.ps1` takes the shared launch lock.
- Test fixtures: `make_test_map.py` builds >12 single-type maps (36 lurkers is the standard one);
  `test-hud-row.ps1` and `test-combat-death.ps1` are the pattern to copy.

## Hard rules

1. Never modify, write to, or launch `C:\sc-install\Starcraft`. Working copy only.
2. Offline, single-player only.
3. Patch memory in-process only; `StarCraft.exe` on disk stays byte-identical; tests assert it.
4. Passive mode (`-Mode observe`) stays stock; a stock-looking game must stay stock.
5. **Never write to live user state outside the repo and the working copy** — AGENTS.md rule 5.
   Specifically: the game's own settings under `HKCU:\SOFTWARE\Blizzard Entertainment\*` are
   OFF LIMITS. A worker zeroed the user's music/sfx volumes there today and the restore was lost
   in a refactor; the user played a silent game for hours. Do not go near it.
6. Commit no game content, no binaries, no logs, no generated maps.
7. Do not merge your own PR.

## Acceptance criteria

1. Control-group storage mapped with evidence (addresses, how found, how verified), including the
   engine's per-group capacity and the recall/store code paths.
2. Design choice stated with reasoning, including what happens to units 13..N and why that is safe
   against the selectionIndex/flag-0x08 hazard.
3. Unattended in-game test: box >12, Ctrl+1, clear selection, press 1 — all N return, asserted
   per-unit from in-process state, not from prose; then an order fans out to all N.
4. Death interaction tested: a unit in a >12 group dies, recall returns the survivors and never
   the corpse — asserted, using task 020's liveness gate.
5. No regressions: circles, HUD row paging, fan-out orders, burrow, combat-death suites all green;
   hooktest green.
6. Exe byte-identical; no stranded processes; CI green.
7. PR opened, link in Status.pr.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/021-control-groups-over-12.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
