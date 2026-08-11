# Task 036 — Make building groups behave like unit groups

## Status

agent: 036
model: opus
pr: https://github.com/inwenis/decompile-sc/pull/42
merged: 2026-08-11

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task036 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task036-building-group-parity.
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

- Your inbox: `C:/git/decompile-sc/work/messages/036/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 036 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

**A selected group of buildings must behave like a selected group of units.** Task 024 shipped
box-select for same-type buildings, and the user played it and found every OTHER way of selecting
a group still does not work. Verbatim, 2026-08-11:

- "i can`t select building with double click (simillar buildings)"
- "i can`t use ctrl or shift to modify building group"
- "when i create a control group with buildings and use it to select them it only shows 1 in tug
  after i click the group number"

Three different input paths, one theme: the box works, nothing else does. Fix all three.

## Context

- **This is finishing task 024, not a new feature.** 024 relaxed the client half of
  `unit_IsStandardAndMovable` (0x0047B770) for exactly the drag-box case — see
  `research/building-groups.md` and `sc_fanout.cpp`. Every other selection path still hits the
  vanilla gate that keeps buildings to one at a time. Read that research FIRST; the gate, its
  call sites and the reason 024 scoped itself to the box are all written down.
- **Three paths, and they may not share a mechanism — establish that before designing:**
  1. **Double-click** selects all same-type units on screen in vanilla. Find where that path
     decides what to include and whether it consults the same gate.
  2. **Shift/Ctrl click** adds or removes from an existing selection. Same question.
  3. **Control-group recall** is the one with a concrete symptom: the group RECALLS but the row
     shows 1. So the recall may be storing all N and the display collapsing, or the recall itself
     may be dropping to one. `sc_ctrlgroup`/task 021`s shadow control groups and
     `research/control-groups.md` are the prior art — 021 already made >12 UNITS work through
     control groups, so compare what it does with what buildings do and the difference should be
     visible.
- **MEASURE EACH ONE BEFORE FIXING IT** (AGENTS.md, "a player-input feature is unproven until the
  wire has been watched"): for each of the three, watch the engine`s command funnel
  (`queueCommand` 0x00485BD0) and read the resulting selection out of memory. That tells you
  whether the client refuses to send, the engine drops it, or the selection is right and only the
  DISPLAY is wrong. Those three have completely different fixes and the symptom does not
  distinguish them. The control-group one especially — "shows 1 in tug" may be a display bug, and
  task 033 owns the display.
- **Coordinate, do not collide.** Task 033 owns `sc_hudrow.cpp` and the status pane for its
  indicator work, INCLUDING a stale-row bug. If your control-group finding turns out to be a
  display problem, it is 033`s, not yours — tell me and I will route it. You own the selection
  paths: `sc_fanout.cpp`, the gate relaxation, `sc_ctrlgroup`. Task 035 owns `drive-game.ps1`.
  Append to `sc_addresses.h` at the END. Rebase before finishing.
- **Compose with 024`s relaxation rather than adding a second one.** 024`s box is same-type by
  construction. Double-click is naturally same-type too. Shift-click is NOT — a player can
  shift-click a Barracks and a Factory. Decide what a mixed building selection does and say so;
  refusing is acceptable if stated, but whatever you choose must not let a command fan out to a
  building that cannot execute it (task 030 found the engine`s own requirement interpreter is
  per-building, `0x0046E1C0`, which is a free backstop — use it).
- **The user plays with these on.** `-BuildingGroups 1` is ON in the deployed build. Whatever you
  change ships to them, so a regression here is a regression in their game, not in a test.
- Test discipline: own `Maps\BroodWar\00-t036\`, `Select-ScBrowserMap`, `New-ScFixtureRun`,
  `run-ci-local.ps1`. Use `--unit-build-time` and `time-suite.ps1` (task 031) — fixtures no longer
  need to wait 20s per unit. GitHub Actions is billing-blocked; ignore it.

## Acceptance criteria

1. Each of the three paths measured BEFORE any fix: commands at the funnel, and the resulting
   selection read from memory. State for each whether it is a client refusal, an engine drop, or
   a display problem.
2. Double-click selects all same-type buildings on screen, proven in game by reading the
   selection from memory.
3. Shift/Ctrl click adds and removes buildings from a selection, proven the same way. The mixed
   selection decision stated with evidence.
4. A control group of N buildings recalls all N — assert the selection from memory, and separately
   state what the row displays (if the row is wrong, that is task 033`s and must be reported, not
   silently worked around).
5. No regression in what 024 shipped: the drag box still selects same-type buildings, and stock
   behaviour is unchanged with the feature off.
6. In-game suites + hooktest green; `StarCraft.exe` byte-identical; no stranded processes.
7. PR opened, link in Status.pr.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/036-building-group-parity.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
