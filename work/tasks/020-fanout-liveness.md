# Task 020 — Fix stale-unit replay in the command path (use-after-free)

## Status

agent: 020
model: opus
pr: https://github.com/inwenis/decompile-sc/pull/20
merged: 2026-08-08

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task020 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task020-fanout-liveness.
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

- Your inbox: `C:/git/decompile-sc/work/messages/020/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 020 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

**Stop the fan-out command path handing the engine units that are dead.** `sc_fanout`'s
`StillAlive()` is uniqueness-only (`CUnit+0xA5` vs the captured value). Task 014 proved that byte
moves only on slot RE-INIT (`0x004A03FD` inside `0x004A0320`) — death does not touch it. So a
damage-killed unit stays "alive" to the shadow list, `EmitSelect` packs its tag into a replayed
Select, and the engine's receive path accepts it: `research/binary-selection-map.md` §5.1/§5.2 show
the per-entry validation is count/decode/uniqueness/dedup/`id != 14` and then
`addUnitToSelectionSlot`, which reads `unit->sprite->flags & 0x20` — through a sprite that is on
the free list by then (`research/selection-circles.md` §5).

Task 017 closed exactly this class for the HUD row with three terms: HP `!= 0`, `InPlayerUnitList`,
and a click gate. The command path has none of them. Give it what it needs, and prove the fix with
the fixture that exposed it.

## Context

- **The defect, already traced end to end** (do not re-derive, verify and extend):
  `tools/plugin/src/sc_fanout.cpp` — `StillAlive()` ~line 246, `EmitSelect()` ~line 329 (filters on
  `StillAlive` + tag bounds only), order emitted right behind it ~line 374. Compare with
  `tools/plugin/src/sc_hudrow.cpp` `UnitAlive()` ~line 182 and `InPlayerUnitList` ~line 207, plus
  the 40-line rationale comment above them — that comment is the design you are porting.
- **It is reachable and was demonstrated in a real game.** `tools/plugin/test-combat-death.ps1`
  (merged, task 019): box 36 lurkers, walk east into the hydralisks, wait for a death, then any
  fanned-out order. Its Burrow keypress is simply the first fanned order after a death. The test
  already asserts the symptom from the other side: `UNITSTATE live=36` (uniqueness-only) against
  `HUDROW n=35` (HP-aware) at the same point.
- **What is NOT established, and you must settle:** whether the engine currently faults on that
  path or silently tolerates it. `addUnitToSelectionSlot` dereferences the freed sprite; a verifier
  could not determine from static evidence whether that is a crash, a read of recycled memory, or
  benign. Find out — in-process observation on the combat fixture is now possible. The answer
  changes how loudly this must be reported, and it belongs in the research doc either way.
- Keep the existing `g_statStale` counter as the observable; it should start firing.
- Prior art you are matching: `research/hud-selection-row.md` §6.1 (why each term exists and what
  each one costs), `research/selection-circles.md` §4.5 (the 0xA5 evidence), `research/command-opcodes.md` §6.
- Do not widen scope: this is the liveness/validation fix plus its proof. No new features, no
  changes to the opcode policy table, no HUD work.

## Hard rules

1. Never modify, write to, or launch `C:\sc-install\Starcraft`. Working copy only.
2. Offline, single-player only.
3. Patch memory in-process only; `StarCraft.exe` on disk stays byte-identical; tests assert it.
4. Passive mode (`-Mode observe`) stays stock.
5. Commit no game content, no binaries, no logs, no generated maps.
6. Do not merge your own PR.
7. **Another worker (task 018) may be running the game.** `run-with-plugin.ps1` on main takes a
   cross-worker launch lock — use it, keep every assertion pid-scoped, and never close a process
   you did not start.

## Acceptance criteria

1. `StillAlive()` (or its replacement) rejects a unit that is dead-but-not-recycled, using terms
   evidenced the way `sc_hudrow`'s are — at minimum HP `!= 0`; justify whether the player-unit-list
   walk is also needed here or argue why not, with evidence either way.
2. Whether the pre-fix path faults or is silently tolerated is DETERMINED and written up in
   `research/` with how it was observed.
3. Offline: hooktest cases covering damage-death (uniqueness UNCHANGED, HP zero) and slot reuse
   (uniqueness bumped) separately, asserting the dead unit is dropped from the emitted Select.
4. In-game regression proof using the task-019 fixture: after a combat death, a fanned-out order
   emits a Select that does NOT carry the dead unit's tag, and `staleSkipped` (or equivalent)
   is asserted `> 0`. This assertion is the point of the task — it must be able to fail.
5. Fan-out still works: >12 units still obey one order; all five suites green
   (selection-circles, fanout-orders, burrow-fanout, hud-row, combat-death); hooktest green.
6. Exe byte-identical before/after; no stranded processes; CI green.
7. PR opened, link in Status.pr.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/020-fanout-liveness.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
