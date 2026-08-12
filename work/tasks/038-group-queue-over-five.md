# Task 038 — Queueing past 5 when several buildings are selected

## Status

agent: 038
model: opus
pr: -

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task038 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task038-group-queue-over-five.
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

- Your inbox: `C:/git/decompile-sc/work/messages/038/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 038 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

With several production buildings selected, the player can keep queueing
past 5 — the same over-cap queueing that already works for a single selected
building. Today the queue stops at 5 in the multi-building case.

## Context

- **The user's exact words (2026-08-11T23:01Z), playing the current deploy:**
  "can't queue more than 5 units per building when multiple buildings are
  selected". They also said, in the same message, that selecting multiple
  buildings and control groups "works nicely" — so selection is fine; this
  is about what happens after the fifth click.
- Two shipped features meet here and this is probably the seam between them:
  - task 025 `sc_prodqueue.cpp` — over-cap queueing for ONE building. Its
    design is inverted on purpose: the plugin keeps the ENGINE's ring below
    its own cap so the client's Train button stays lit and keeps sending
    commands. Read AGENTS.md § "A player-input feature is unproven until the
    wire has been watched" before touching it — that section is this exact
    mechanism, and it is the reason the obvious receive-side fix is wrong.
  - task 030 `sc_prodfan.cpp` — fanout of production across all selected
    buildings.
- So the likely shape: fanout picks a target building per click, but the
  below-cap trick that keeps the button lit is only applied to one building
  (or to the wrong one). Confirm on the wire before believing it.
- Tests: `tools/plugin/test-production-queue.ps1`,
  `tools/plugin/test-group-production.ps1`.
- Charging matters as much as counting: whatever you build must also spend
  the right minerals/gas and refund correctly on cancel (task 028 shipped
  cancel/refund). A queue that grows without charging is a worse bug.

## Steps (suggested)

1. Watch the command funnel (`queueCommand` 0x00485BD0) in a real game while
   clicking Train 12 times with 3 barracks selected. Count what reaches the
   wire per building. That measurement decides the fix; guessing does not.
2. Fix so N clicks across a K-building selection produce N queued units and
   N units' worth of resources spent.
3. Prove the single-building case still works — this change is exactly where
   a regression to 025 would hide.

## Acceptance criteria

1. Real-game evidence of 12 units queued across a multi-building selection,
   with the engine's own counts asserted — not the plugin's bookkeeping
   (AGENTS.md § "Assert the ENGINE'S OWN RESULT"). A wire trace is text and
   goes in the PR body; a game **frame must NOT be `pr-image`d** — it
   reproduces game artwork and hard rule 1 wins (AGENTS.md § "Screenshots vs
   hard rule 1 (settled)"). Keep frames on the gitignored diagnostic path and
   name the exact paths in the PR body for the conductor to open at review.
2. Resources spent match the units queued; cancel still refunds.
3. Single-building over-cap queueing (task 025) still passes.
4. A test that fails on current main and passes with the fix.
5. Local checks green; PR opened with its link in Status.pr.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/038-group-queue-over-five.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
