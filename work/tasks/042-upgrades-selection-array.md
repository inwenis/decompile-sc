# Task 042 — sc_upgrades reads the client selection where the engine reads the simulation

## Status

agent: 042
model: sonnet
pr: -

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task042 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task042-upgrades-selection-array.
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

- Your inbox: `C:/git/decompile-sc/work/messages/042/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 042 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

`sc_upgrades.cpp` decides which building an upgrade command is about by
reading the CLIENT's selection array. The engine gates on the SIMULATION's.
Fix it to read what the engine reads, and prove the upgrade feature still
works. This is latent today, not user-visible — the value is that it stops
being a trap for the next feature that fans out.

## Context

- Found by task 038 while fixing the same defect in `sc_prodqueue.cpp`, and
  deliberately left alone there rather than changing a shipped feature whose
  suite that task could not re-run. Recorded in
  `research/production-queue.md` § 10.5.
- The defect, in one line: `SoleSelectedUnit` reads `activePlayerSelection`
  (`0x006284B8`); `getActivePlayerNextSelection` (`0x0049A850`) walks
  `playersSelections` (`0x006284E8`), row `activePlayerId`, stride 12. The two
  arrays ABUT and hold the same thing whenever exactly one building is
  selected — so every existing test agrees with either reading.
- Read AGENTS.md § "Take the ADDRESS from the engine's own instructions, not
  from the global next door" (task 038 wrote it) before you start. The fix in
  `sc_prodqueue.cpp` is your worked example; copy its shape, including the
  index arithmetic quoted from the binary.
- **Why it is latent and not a live bug:** no upgrade command is fanned out
  today, and the client will not offer an upgrade button for a multi-building
  selection, so the two arrays cannot disagree in the upgrade path. Do not
  oversell this in the PR — it is a correctness cleanup with a clear rationale,
  not a user-facing fix.
- Task 037 (merged) changed the upgrade INDICATOR in `sc_queueind.cpp`. That
  is a different file and a different concern; do not fold the two together.
- Suites: `tools/plugin/test-upgrade-queue.ps1`, and hooktest's upgrade parts.

## Steps (suggested)

1. Make the same correction 038 made, with the engine's own index arithmetic.
2. Add the hooktest coverage that would catch it — the two arrays disagreeing
   is constructible in hooktest without a game, exactly as 038 did for part
   [15]. That test is the real deliverable; the one-line fix is not.
3. Re-run the upgrade suite in a real game to prove nothing regressed. Frames
   stay on the gitignored diagnostic path (hard rule 1 — never `pr-image` a
   game frame); name the paths in the PR body.

## Acceptance criteria

1. `SoleSelectedUnit` in `sc_upgrades.cpp` reads `playersSelections` with the
   engine's own indexing, with the operands cited in a comment.
2. A hooktest part that fails against the old reading and passes with the new
   one.
3. `test-upgrade-queue.ps1` passes in a real game; the upgrade indicator still
   shows (task 037's "+N upg") — name the frame path for the conductor.
4. If you find any OTHER site reading the wrong array, report it to the
   conductor as a message; do not expand this task to cover it.
5. Local checks green (`scripts/run-ci-local.ps1`); PR opened with its link in
   Status.pr.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/042-upgrades-selection-array.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
