# Task 025 — Queue more than 5 units at a production building

## Status

agent: 025
model: opus
pr: https://github.com/inwenis/decompile-sc/pull/25
merged: 2026-08-09

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task025 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task025-production-queue-over-5.
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

- Your inbox: `C:/git/decompile-sc/work/messages/025/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 025 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

**A production building can hold more than 5 queued items.** User: "enable queuing more then 5
units." Vanilla caps the production queue at 5 slots. After this, you can queue more (target a
sensible number — pick one, justify it) and they build in order.

This is a DIFFERENT subsystem from everything built so far. Nothing here is selection or fan-out —
it is the per-building production queue. Start by mapping it; do not assume it resembles the
selection work.

## Context

- **Map the production queue first, with evidence:**
  - Where does a building store its queue? It is an array inside the `CUnit` (or a sub-struct it
    points to). Find its address/offset, its slot count (the 5), and the element format (what a
    queued item actually is — a unit-id? a build-order record?). `research/binary-selection-map.md`
    and `sc_addresses.h` are the offset conventions; the queue is new territory — every claim
    carries how-found + how-verified (hard rule 4).
  - Find every place the 5 is enforced: the enqueue path (clicking a unit in the build menu — is it
    a command opcode? cross-ref `research/command-opcodes.md`), the "queue full" check, the UI that
    draws the 5 slots, and the dequeue/build-complete path. The cap may be baked into several of
    them, exactly like the 12-unit selection cap was — a stride, an unrolled loop, a literal 5.
- **Design decision, cheapest first, stated with evidence before building:**
  - (a) Widen the in-place array IF the surrounding code is bounds-driven rather than hardcoded-5 —
    prove it the way task 021 proved the control-group array was NOT bounds-driven before rejecting
    that option. If the code is written around a fixed 5 (unrolled, fixed strides), in-place
    widening is out and you say so.
  - (b) A plugin-side overflow queue that feeds the engine's 5 as slots free up — the same shadow
    pattern as the selection work, applied to production. Likely the safe route if (a) is refuted.
  - (c) something the code suggests.
  - The HAZARD to reason about explicitly: production spends resources. Whatever you do must not
    let a queued item be paid for twice, or refund wrong on cancel, or desync what the UI shows
    from what the building will actually build. The resource-cost discipline from task 015's
    passthrough analysis applies — production/cancel were passthrough for a reason.
- **You do NOT need to fan out anything.** This is one building's own queue. If you find yourself
  editing the selection/fan-out path, stop — you have probably taken a wrong turn.
- **Concurrency, important:** task 024 (building groups) may be editing `sc_fanout.cpp` /
  `sc_addresses.h` at the same time. You will more likely be in NEW files or the production path,
  but if you must touch a function 024 also touches, rebase onto `origin/main` before finishing and
  STOP and message the conductor rather than guessing a merge. Add new addresses to
  `sc_addresses.h` at the end to minimise conflict surface.
- Test discipline (task 023, merged): your own `Maps\BroodWar\00-t025\` via `-FixtureDir`, fixture
  named for the suite, declared to `New-ScFixtureRun`, `Select-ScBrowserMap` for the browser, moves
  through `Assert-ScWindowActive`. A test needs a building that produces units and enough resources
  to queue >5 — `make_test_map.py` can set starting resources; check what it supports and extend it
  minimally if it cannot. Read the queue back from the building's own memory to assert length.

## Hard rules

1. Never modify, write to, or launch `C:\sc-install\Starcraft`. Working copy only.
2. Offline, single-player only. `StarCraft.exe` on disk stays byte-identical; tests assert it.
3. Passive mode (`-Mode observe`) stays stock.
4. Never write live user state — AGENTS.md hard rule 5.
5. Commit no game content, no binaries, no logs, no generated maps.
6. Do not merge your own PR.

## Acceptance criteria

1. Production queue mapped with evidence: address, slot count, element format, and every site that
   enforces the 5. The design choice stated with reasoning, including why (a) is or is not viable.
2. Unattended in-game test: queue more than 5 at a real building, read the queue length from its own
   memory (not from the UI), and confirm they build in order. Assert per-item.
3. Resource safety demonstrated: a queued-over-5 item is paid for exactly once, and a cancel refunds
   correctly — asserted or shown from the handler with evidence.
4. No regressions: existing in-game suites + hooktest green; exe byte-identical; no stranded
   processes; the on-disk exe unchanged.
5. PR opened, link in Status.pr.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/025-production-queue-over-5.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
