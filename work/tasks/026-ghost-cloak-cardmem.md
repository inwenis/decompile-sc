# Task 026 — Name the Cloak command-card button by reading it from process memory

## Status

agent: 026
model: opus
pr: https://github.com/inwenis/decompile-sc/pull/27
merged: 2026-08-09

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task026 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task026-ghost-cloak-cardmem.
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

- Your inbox: `C:/git/decompile-sc/work/messages/026/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 026 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

**Answer the user's cloaked-ghost report by reading the command card from process memory instead of
clicking at it.** The user asked us to figure out whether a cloaked Ghost that stopped attacking was
our bug. Task 022 could not drive Cloak from a script (no key A–Z emits it, and clicking the
bottom-left card slot armed a targeted ability reading "Select Target"), so the Ghost-specific
question was left OPEN. This task closes the input gap: read the command-card button array out of the
running process — each slot's ability id and its enabled/disabled state — so we can (a) NAME the
Cloak button and its state, and then (b) drive it correctly and re-run task 022's order-stability
experiment on an actual cloaking Ghost.

## Context

- **This is primarily an investigation + probe, not a plugin feature.** The likely deliverables are
  research (the command-card structure, the Cloak button's slot and enabled flag) plus a probe/test,
  not new hooks. If you find it needs a plugin hook, that is fine — but say so and keep it minimal.
- **Where task 022 left it** (`research/ability-semantics.md` §7.x, merged): the tech reaches the
  card (the command-card region fingerprint differs with vs without Personnel Cloaking research,
  reproduced 3×), both input paths (key and click) are proven working on that same card for Move /
  Attack / Patrol / Stop / Hold, and the entire ability row is inert to keys and clicks. So Cloak is
  ON the card but not reachable by the inputs tried. The open question is WHICH slot and whether it
  is disabled.
- **The command card is a UI structure in memory.** Find it: the array of card buttons (each with an
  ability/command id, an icon, and an enabled/greyed state), where it is built per-selection, and
  how a click on slot N maps to a command. `research/hud-selection-row.md` mapped the adjacent
  status-dialog and its control/button structures and the `statUser`/interact machinery — the
  command card is a sibling UI; that doc is the closest prior art for how these dialogs are laid out
  and read. `research/command-opcodes.md` has the command/ability ids (Cloak-related opcode(s) — find
  the id, do not guess). Every offset carries how-found + how-verified (hard rule 4).
- **Task 023 left the exact next step written down** ("read the command-card button array out of the
  process instead of clicking at it — names the slot AND its enabled flag, does not depend on posted
  input") and shipped `tools/plugin/probe-ghost-cloak.ps1`, the four-arm probe. Build on that probe;
  do not restart from zero.
- **Two-part deliverable:**
  1. Name the Cloak button: its card slot, its ability id, and its enabled/disabled state on a
     cloak-capable Ghost with energy. If it is DISABLED (greyed) under some condition, that itself
     may be the whole answer to the user's report — a Ghost that cannot cloak because of an engine
     rule is not our bug. Report what you find.
  2. If it can be driven, re-run task 022's order-stability experiment (`test-ability-in-combat.ps1`
     is the pattern) with Cloak as the ability on a real Ghost, plugin-vs-stock, and answer the
     user's actual question: does anything we do make a cloaked Ghost stop attacking. Use the
     building-block fixture design task 022 converged on (an enemy that cannot itself act) so the
     measurement is not confounded by combat.
- **Concurrency:** tasks 024 and 025 may be editing `sc_fanout.cpp` / `sc_addresses.h`. You are
  mostly in research + probe + `drive-game.ps1`; if you must add an address, append to
  `sc_addresses.h` and rebase before finishing.
- Test discipline (task 023, merged): your own `Maps\BroodWar\00-t026\`, `Select-ScBrowserMap`,
  `Assert-ScWindowActive`, the shared launch lock (serialises with 024/025). Cloak needs Personnel
  Cloaking research — `make_test_map.py` set it in task 022's fixture; reuse that.

## Hard rules

1. Never modify, write to, or launch `C:\sc-install\Starcraft`. Working copy only.
2. Offline, single-player only. `StarCraft.exe` on disk stays byte-identical.
3. Never write live user state — AGENTS.md hard rule 5.
4. Commit no game content, no binaries, no logs, no generated maps, no screenshots.
5. Do not merge your own PR.

## Acceptance criteria

1. The command-card button array mapped with evidence: where it lives, its element format (ability
   id + enabled state), how a slot maps to a command. Addresses carry how-found + how-verified.
2. The Cloak button NAMED: its slot, ability id, and enabled/disabled state on a cloak-capable Ghost
   with energy, read from process memory. If disabled, the condition stated with evidence.
3. Either: Cloak driven correctly and task 022's order-stability experiment re-run on a real Ghost
   (plugin-vs-stock, confounds controlled) with a stated answer to the user's report — OR a clear
   evidenced statement of why it still cannot be driven and what the memory read establishes anyway.
4. Findings in `research/`; the four-arm probe extended, not restarted.
5. Existing suites + hooktest green; exe byte-identical; no stranded processes.
6. PR opened, link in Status.pr.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/026-ghost-cloak-cardmem.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
