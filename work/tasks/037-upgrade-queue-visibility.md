# Task 037 — The upgrade queue is invisible in a real game (Engineering Bay)

## Status

agent: 037
model: sonnet
pr: -

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task037 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task037-upgrade-queue-visibility.
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

- Your inbox: `C:/git/decompile-sc/work/messages/037/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 037 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

The user plays the deployed build, selects a Terran Engineering Bay, queues
two or more upgrades, and SEES the queue on screen. Today they see nothing.
Task 029 shipped "the upgrade queue is shown" and its tests pass, so the
first half of this task is finding out what the tests are proving that the
screen is not.

## Context

- **The user's exact words (2026-08-11T23:01Z), after playing the current
  deploy:** "i do not see upgrade queue - tested on terran engineering bay".
  The deployed plugin is `2026-08-11 12:15:47`, built after every merge
  below — they were running current code, not a stale build.
- Prior work: task 029 (`work/tasks/029-upgrade-queue.md`, PR #29 area),
  source `tools/plugin/src/sc_upgrades.cpp/.h`, test
  `tools/plugin/test-upgrade-queue.ps1`, wire probe
  `tools/plugin/probe-upgrade-wire.ps1`.
- 029's own lesson is already in AGENTS.md § "Assert the ENGINE'S OWN RESULT,
  not your bookkeeping" — a test that asks the plugin what the plugin wrote
  proves nothing. Task 034 found the same class again: a HUD element that
  was written, tested, and invisible for weeks because its text box was nine
  pixels tall and the game refuses to draw text taller than its box. Assume
  nothing about which layer is broken until you have looked at a frame.
- Which buildings 029 actually exercised is not established. Engineering Bay
  may never have been covered; the display may be conditional on a building
  type, an upgrade count, or a card layout that differs per building.
- Hard rule: a player-input feature is unproven until the wire has been
  watched (AGENTS.md § "A player-input feature is unproven"). Queue-two-
  upgrades starts with a click on the command card.

## Steps (suggested)

1. Reproduce FIRST, in a real game, on an Engineering Bay, with your own
   eyes on a captured frame — not through the plugin's log. Then widen:
   does any other building show the queue (Academy, Armory, Command Center)?
   The answer splits "never worked" from "works, except here".
2. Only then read `sc_upgrades.cpp` and work out why that case draws nothing.
3. Fix, and make the existing test fail before it passes — a test that
   could not have caught this is not a regression test.

## Acceptance criteria

1. A captured frame from a real game shows the upgrade queue on a Terran
   Engineering Bay with 2+ upgrades queued. Embed it in the PR
   (`pr-image <file>`, per the global rules).
2. The same evidence for at least two other upgrade-producing buildings,
   or a documented statement of which buildings are covered and which are
   deliberately not.
3. A test that FAILS on current main and passes with your fix, asserting
   what is on the screen rather than what the plugin recorded.
4. Local checks green; PR opened with its link in Status.pr.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/037-upgrade-queue-visibility.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
