# Task 059 — A task running two suites deadlocks on its own fixture

## Status

agent: 059
model: sonnet
pr: -

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task059 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task059-fixture-folder-per-suite.
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

- Your inbox: `C:/git/decompile-sc/work/messages/059/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 059 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

A task that runs two different suites must not deadlock on its own leftover
fixture, and when the guard does refuse it must name the right culprit. Make the
fixture folder per TASK **and SUITE**, and fix the message that currently blames
"another run" for a file the same task wrote.

## Context

- **Issue: https://github.com/inwenis/decompile-sc/issues/80**, which carries the
  full diagnosis. Read it; this file summarises only what shapes the work.
- **This happened twice in one hour on 2026-08-13 and the conductor had to
  hand-delete the blocking file both times.** Task 054 ran `test-save-load`, then
  `test-hud-row`, both under `00-t054`, and the second waited forever:

      waiting for C:\sc-work\1161-base\Maps\BroodWar\00-t054 to be free
      (another run's fixture is in it: save-load.scx)

  Nothing was contended — no StarCraft running, no other worker on the machine,
  and the run that wrote the file had finished cleanly seven minutes earlier.
- **It is NOT a cleanup leak, and the obvious fix is wrong.** `test-save-load.ps1:948`
  leaves the fixture deliberately and says why: *"The fixture is left in place for
  the phases that follow; only the LAST phase removes it. Deleting it earlier
  would leave the saves pointing at a map that is no longer there."* A multi-phase
  suite genuinely cannot delete its map between phases.
- **And "treat a finished run of mine as free" is forbidden**, not merely
  awkward: it is undecidable from the filesystem, it is what AGENTS.md rule 3
  rules out (*process-liveness is NOT a sufficient test*), and it would delete a
  map a later phase's saves still reference. Worker 054 talked the conductor out
  of exactly this; do not reintroduce it.
- **The fix, from 054 who paid for it:** `Resolve-ScFixtureDir` returns
  `00-t<NNN>`; make it `00-t<NNN>-<suite>`. Then a multi-phase suite may keep its
  fixture across phases, the foreign-file rule stays strict, and two suites of
  one task can never see each other's files. `Remove-ScOwnFixtureDir` already
  removes the folder when empty, so the empty-folder-pushes-browser-rows concern
  is unchanged.
- **The second half is the message, and it is not cosmetic.** *"another run's
  fixture is in it"* names a culprit that does not exist, and that phrasing is
  what sent two people hunting for a colliding worker. It should say what it
  actually knows: the file, which task/suite owns it if the path reveals that,
  and that no liveness check was performed.
- **Why this cannot be left to nurse:** a worker inside the wait loop is DEAF —
  its inbox monitor cannot deliver while a tool call blocks (issue #59, same
  root). So the deadlock is not self-recoverable and not fixable by messaging the
  worker either. Someone has to reach in and delete a file.
- **Hard rule reminder:** the map browser must never be clicked by row number
  (AGENTS.md, task 023), and folder naming affects browser row order. If your
  change alters how many folders exist under `Maps\BroodWar`, say so and check
  the suites that navigate there.

## Steps (suggested)

1. Reproduce it first — two suites, one task id, second one waits. That is your
   failing test and it should exist before the fix.
2. Change `Resolve-ScFixtureDir` and follow the callers; `Remove-ScOwnFixture` /
   `Remove-ScOwnFixtureDir` and the foreign-file guard all read that path.
3. Then the message.
4. Then prove the guard still refuses a genuinely foreign file — the whole point
   of it — rather than having been widened into uselessness.

## Acceptance criteria

1. The deadlock is reproduced BEFORE the fix and shown gone after. A transcript
   of the wait loop, then a transcript of the same two suites running through.
2. The foreign-file guard still refuses a real foreign file, demonstrated with a
   file the run did not create. A guard that no longer guards is a worse outcome
   than the deadlock.
3. A multi-phase suite still keeps its fixture across phases — `test-save-load`
   is the case; run at least its control and fanout phases back to back.
4. The refusal message names the file and what is known about its owner, and does
   not assert "another run" without evidence.
5. Any change in the number or naming of folders under `Maps\BroodWar` is stated,
   with a check that browser navigation is unaffected.
6. `scripts/run-ci-local.ps1` PASS; PR opened with the link in Status.pr. Cloud
   CI is down on billing — note it in the body.

## Machine

**The machine is free and yours** — no other worker is launching (058 is a
static-analysis task that never starts the game). `sc-launch-lock.ps1` serialises
one launch, not a chain (issue #60), so if the conductor dispatches anyone else
you will be told first. Announce before a long chain of runs.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/059-fixture-folder-per-suite.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
