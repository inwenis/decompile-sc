# Task 061 — Clicking the last queue slot does not cancel when it carries our +N text

## Status

agent: 061
model: opus
pr: https://github.com/inwenis/decompile-sc/pull/95

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task061 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task061-queue-slot-cancel-click.
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

- Your inbox: `C:/git/decompile-sc/work/messages/061/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 061 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

Clicking the last production-queue slot cancels that unit, exactly like every
other slot, including when our `+N` overflow text is on it. Right now it does
nothing, and that is a regression our own feature introduced.

## Context

- **The user's exact words (2026-08-13T08:28Z), playing the deployed build
  `2c239e6`:** *"bug - i can cancel a queue unit by clicking it, but it doesn't
  work if i click the last slock when it has our extra +x text"*.
  They confirmed in the same message that the fifth-slot icon and the group
  queue indicator are both working — so this is the one thing wrong with the
  feature they otherwise like.
- **This is almost certainly ours, not the engine's.** Task 039 (PR #55,
  `25e4c62`) changed what the fifth slot draws and spliced a `+N` overflow
  indicator. The slot the user cannot cancel is the slot we now draw into.
- **Two candidate causes. Do not pick one by reading — measure.**
  1. Our spliced control sits in the dialog's child chain ahead of the button
     and swallows the click before the engine's own hit-test sees it.
  2. The click reaches the engine but resolves to a slot index that no longer
     means what it did, so the cancel targets nothing.
  The two look identical from the outside and have completely different fixes.
- **AGENTS.md already carries the rule that predicts this**, written by task 039
  ITSELF while fixing the drawing side: *"a card slot changes meaning under you —
  re-read before every click."* (commit `c81c429`). Nobody applied it to the
  clicking side. Quote it in the PR; this is that rule collecting.
- **The wire rule is the whole method here** (AGENTS.md § "A player-input feature
  is unproven until the wire has been watched"). A cancel is a player input:
  click → command on the wire → engine acts. **Watch `queueCommand` (0x00485BD0)
  while clicking that slot** and establish first, before any theory, whether a
  cancel command is emitted at all:
  - **no command on the wire** → the click never became a cancel (cause 1, our
    control ate it, or the engine refused the hit);
  - **command on the wire but nothing cancelled** → it became the wrong cancel
    (cause 2, index/meaning).
  That single observation splits the problem in half and costs one run.
- **`test-production-queue.ps1` already drives a cancel-by-click** and asserts
  the refund — 055 verified it live on 2026-08-13 (`the plugin served exactly 1
  cancel(s) of its own (1)`, `refunded exactly 1 x 50 minerals (50)`). So the
  harness can already click a slot and check the outcome; what it has never done
  is click the LAST slot while `+N` is showing. That is the missing arm, and it
  is the regression test.
- Relevant source: `tools/plugin/src/sc_queueind.cpp` (the splice and the `+N`
  text), `sc_card.cpp` (the icon strip), `sc_prodqueue.cpp` (what a cancel does
  to our held items). Issue #83 is a *different*, pre-existing cancel-arm bug
  (a read-order race) — do not conflate them.
- **If the honest fix is to stop drawing `+N` on a clickable slot, that is an
  acceptable outcome** — say so with the evidence. A feature that costs the user
  a working click is worse than no feature, and task 039's own goal statement
  said the same thing about drawing nothing rather than drawing wrong.

## Steps (suggested)

1. Reproduce it in a real game and watch the wire in the same run. Do not write
   a fix until you can say which half of the problem you are in.
2. Then read the dialog's child chain at the moment of the click — which control
   actually owns those pixels.
3. Fix, then add the missing arm to `test-production-queue.ps1`: cancel the last
   slot WHILE `+N` is showing, assert the refund and the ring, and show it
   failing on the pre-fix build.

## Acceptance criteria

1. A statement of which cause it was, backed by the wire observation — command
   emitted or not — rather than by reasoning about the code.
2. Clicking the last slot with `+N` showing cancels it, demonstrated in a real
   game, with the refund landing exactly as the existing cancel arm asserts.
3. A regression arm in `test-production-queue.ps1` for exactly this case, shown
   FAILING against the pre-fix plugin (`tools/plugin/build-defect-arm.ps1` and
   `-BuildDir` make that cheap now) and passing after.
4. Every other slot still cancels — do not fix the fifth by breaking the first
   four.
5. `scripts/run-ci-local.ps1` PASS; PR opened with the link in Status.pr. Cloud
   CI is down on billing — note it in the body.

## Machine

**THE USER IS PLAYING RIGHT NOW.** StarCraft is single-instance per machine, so
a launch would take the game out from under them. **Do NOT launch anything until
the conductor tells you the machine is free.** Do all the reading, the source
work and the test-writing first; message the conductor when you are ready to run
and wait for the GO.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/061-queue-slot-cancel-click.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
