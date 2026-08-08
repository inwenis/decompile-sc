# Task 015 — Fan out every order type, not just move

## Status

agent: 015
model: opus
pr: -

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task015 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task015-fanout-all-orders.
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

- Your inbox: `C:/git/decompile-sc/work/messages/015/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 015 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

**Every command a player issues to a >12 selection applies to all of them, not just the 12 the
engine holds.** Today the fan-out plugin replays only `0x14` (right-click) and `0x15` (targeted
order). The user's ask, their clarified words: more ORDER TYPES — "attack, patrol, hold, stop,
ability casts". Stop with 24 units selected should stop 24 units.

This is NOT "fan out every opcode". Some commands must never be duplicated (production, cancels,
anything resource-costed). The deliverable is a per-opcode policy — fan-out / passthrough — decided
from evidence of how the ENGINE applies each command across its own ≤12 selection, plus the
implementation of the fan-out set.

## Context

- Start here: `tools/plugin/src/sc_fanout.cpp` — `StartFanout` / `HkCmdactSelect` mechanism,
  `SC_CMD_RIGHT_CLICK 0x14` / `SC_CMD_TARGETED_ORDER 0x15` are the two opcodes handled now. The
  comment "the longest order command in the table is 11B" refers to the binary's command-length
  table — find it, cite it, and enumerate ALL player-issuable command opcodes from it with
  evidence. No folklore opcode lists; the table plus per-opcode handler reads are the source.
- `research/command-path.md` (task 011) — the command pipeline: builders, `CMDACT_Select`
  (`0x004C0860`) as the client commit point, turn buffer. Your replay path is already built; the
  work is deciding WHAT to replay and proving it safe.
- `research/selection-circles.md` (task 014) — shadow list + circles + the selectionIndex hazard.
  Discipline is inherited: never write `selectionIndex`, never set sprite flag `0x08`.
- Which user-visible commands already fan out via `0x15` (attack? patrol?) is the first thing to
  establish — do not re-implement what already works. Then enumerate what does not: untargeted
  opcodes (stop, hold position, siege/unsiege, burrow, cloak, unload-all, return-cargo, …) almost
  certainly bypass `StartFanout` today.
- Per-opcode hazards to decide with evidence, not guesses:
  - Spell/energy commands: how does the engine arbitrate a targeted cast across 12 selected
    casters? Whatever it does for 12 is the semantic to preserve for 24 — do not invent a better
    one. If the answer is "all 12 cast", fan-out means 24 casts; say so and let me decide.
  - Queued orders (shift): chunked replay must preserve queue semantics per unit.
  - Commands with unit-type applicability (siege needs tanks): engine behavior on mixed
    selections is the spec; match it.
  - Production/cancel/upgrade/unload-one: expected policy passthrough — justify each from the
    handler, one line + evidence.
- Self-test unattended: `tools/plugin/drive-game.ps1` primitives (posted messages; keyboard via
  PostMessage is fine, `SendInput`/`SendKeys` stay banned), `test-selection-circles.ps1` as the
  pattern. Stock maps only; `Maps\campaign\(1)Enslavers02b.scm` has 24 dragoons in one box — for
  untargeted-ability coverage pick whatever stock campaign map has suitable units and document
  the choice. The plugin can read per-unit state (CUnit order byte) to assert "all 24 stopped"
  without seeing the screen.
- Regression duty: `test-selection-circles.ps1` and `build.ps1 -Test` must still pass — circles,
  shift-click, existing move fan-out are user-visible behavior you must not break.
- Verified working-copy constants: module base `0x00400000`, delta zero, `CUnit` 336 bytes,
  active player read not hardcoded. Pristine hash `AD6B58B2…C6A46`.

## Hard rules

1. Never modify, write to, or launch `C:\sc-install\Starcraft`. Working copy only.
2. Offline, single-player only. Never Battle.net.
3. Patch memory in-process only — `StarCraft.exe` on disk stays byte-identical; the test asserts
   it (pattern already in test-selection-circles.ps1).
4. Passive mode (`-Mode observe`) must still give a stock game.
5. Commit no game content, no binaries, no logs, no screenshots.
6. Do not merge your own PR.

## Acceptance criteria

1. Evidence-backed opcode table in `research/`: every player-issuable command opcode, its length,
   its policy (fan-out / passthrough), and the evidence line for the policy. The command-length
   table's address and how you found it included.
2. Stop and Hold Position fan out: >12 units, one keypress, every unit's order state proves it —
   asserted by the unattended test, not by prose.
3. At least one untargeted ability fans out on a suitable stock map, same standard of proof.
4. Attack and patrol confirmed fanning out (whether that is "already worked via 0x15" or new code
   — state which).
5. Spell-arbitration finding reported explicitly: what the engine does at 12, what fan-out makes
   it do at 24, and if those differ in a way the user would notice, you asked before shipping.
6. Passthrough set implemented and justified per opcode; production/cancel commands demonstrably
   NOT duplicated (test or handler-evidence).
7. Regressions green: `test-selection-circles.ps1` and `build.ps1 -Test` pass; exe on disk
   byte-identical before/after every run; no game process left running; CI green.
8. PR opened, link in Status.pr.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/015-fanout-all-orders.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
