# Task 017 — Show more than 12 units in the bottom HUD selection row

## Status

agent: 017
model: fable
pr: -

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task017 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task017-hud-selection-row.
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

- Your inbox: `C:/git/decompile-sc/work/messages/017/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 017 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

**The bottom HUD selection row stops lying about a >12 selection.** User's words: "can we try to
actaully show more units in the bottom TUG?" Today a 24-unit fan-out selection shows 12
wireframes; the other 12 exist (circles, commands — tasks 011/014/015) but the HUD denies them.

This task is TWO STAGES WITH A GATE. The HUD dialog is the highest-ambiguity target we have
touched and the selectionIndex memmove hazard lives exactly in its click handling — I want the
map before anyone digs.

- **Stage A — investigate, report, STOP.** How the 12-slot row actually works, what the
  candidate designs actually cost, your recommendation. Message the conductor and WAIT for the
  pick. Do not start stage B on your own judgement.
- **Stage B — implement the approved design.**

## Context

- Stage A must answer, with evidence:
  1. The selection-row dialog: which UI structure draws the 12 wireframe slots, where its
     layout lives (positions, 12-slot array), which code path fills it on selection change,
     where a click on slot N dispatches. `research/selection-cap.md` §2.4's selectionIndex
     notes ("index in the selection area at bottom of screen") are the thread to pull.
  2. Candidate designs, honestly costed — at least: (a) PAGING — row still shows 12, a
     hotkey/click cycles which 12 of N are shown; engine selection untouched, likely cheapest;
     (b) WIDENING — more than 12 portraits drawn; layout surgery, likely expensive; (c) any
     hybrid the code suggests (e.g. a "+12 more" indicator glyph). For each: what must change,
     what it does to the selectionIndex/flag-0x08 discipline, what a click on a shadow unit's
     slot should do, and what can go wrong.
  3. Your recommendation with reasoning.
- The hazard, inherited and non-negotiable: engine-selected units own selectionIndex 0..11 and
  sprite flag 0x08; the four readers and the memmove are mapped in
  `research/selection-circles.md` §4 and `sc_circles.h`. Shadow units must NEVER receive either.
  Any design that needs a shadow unit to look engine-selected inside the row must present the
  slot WITHOUT writing those fields — how, exactly, is stage-A homework.
- Prior work you build on (all merged): `research/selection-cap.md` (candidate designs for the
  cap itself — this task is the HUD half of candidate #3), `research/selection-circles.md`,
  `research/command-opcodes.md`, `research/binary-selection-map.md`, `research/prior-art.md`
  (GPTP/BWAPI dialog prior art pointers, if any).
- Tools, all merged: `FieldSweep.java` (find every reader/writer of a struct field),
  `build-opcode-policy.ps1` pattern for scripted Ghidra decompile sweeps, `drive-game.ps1`
  (drive menus/clicks/keys via posted messages), `make_test_map.py` (playable UMS fixtures —
  36 same-type units in one box, task 016), the three test suites as discipline patterns.
- You can see the screen: PrintWindow frame capture (task 014's technique, in
  `drive-game.ps1`) — read your own frames to check the row renders as designed. Frames stay
  outside the repo (gitignored path), never committed.
- Verified constants: module base `0x00400000`, delta zero, `CUnit` 336 bytes, pristine hash
  `AD6B58B2…C6A46`. Active player: read it, never hardcode.

## Hard rules

1. Never modify, write to, or launch `C:\sc-install\Starcraft`. Working copy only.
2. Offline, single-player only. Never Battle.net.
3. Patch memory in-process only; `StarCraft.exe` on disk stays byte-identical; tests assert it.
4. Passive mode (`-Mode observe`) stays stock.
5. Commit no game content, no binaries, no logs, no screenshots, no generated maps.
6. Do not merge your own PR.
7. Stage gate is hard: no stage-B code before the conductor's pick arrives in your inbox.

## Acceptance criteria

1. Stage A report: dialog structure with evidence (addresses, how found, how verified), the
   candidate table with per-design cost and hazard analysis, a recommendation. Delivered as a
   conductor message + `research/hud-selection-row.md`, and the WAIT honoured.
2. Stage B implements the approved design; behavior matches the approved spec.
3. The selectionIndex/flag-0x08 discipline provably intact: hooktest-level offline assertions
   that shadow units never receive either field, plus the existing three suites still green.
4. Unattended in-game test for the new HUD behavior with a stated oracle (propose it in stage
   A: in-process UI state read, frame analysis, or both) following the established test
   discipline (pinned ids, positive asserts, try/finally, -ProcessId, SHA-256, no vacuous
   passes).
5. Exe byte-identical before/after; no stranded processes; no committed game content; CI green.
6. PR opened, link in Status.pr. Frame-verified appearance described in the PR body (no
   screenshots committed; offer the user a live look instead).

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/017-hud-selection-row.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
