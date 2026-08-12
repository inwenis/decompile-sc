# Task 041 — Randomized action-sequence conformance tests across every shipped feature

## Status

agent: 041
model: opus
pr: https://github.com/inwenis/decompile-sc/pull/54
merged: 2026-08-12

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task041 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task041-randomized-conformance.
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

- Your inbox: `C:/git/decompile-sc/work/messages/041/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 041 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

A test that generates RANDOM action sequences against the shipped features,
runs them in a real game, and asserts the engine's own outcome — units built,
resources charged, refunds paid. It must be able to find a bug nobody thought
to look for. That is the entire point: every bug the user reported this week
was invisible to a suite written by the person who wrote the feature.

## Context

- **The user asked for this in their own words (2026-08-11T23:01Z):** "can we
  add some randomized testings for the mods we have so far like: we list all
  the actions like 'building x' then 'scheduled unit a' then '12 times' and we
  verify that it build 12 units and charged for 12. and we do this for all our
  features". Their shape is right — take it as the spec.
- Why this task exists at all, and it is worth reading before you design
  anything: on 2026-08-11 the conductor told the user six bugs were fixed. The
  user played the build and found four still broken. Two root causes, both
  found the next morning:
  - task 037: `AnchorFor` had no case for the upgrade mode, so the indicator
    was composed and never anchored — invisible in every real game, on every
    building, while its test asked the composer directly and passed.
  - task 038: `sc_prodqueue` read `activePlayerSelection` (`0x006284B8`) where
    the engine gates on `playersSelections` (`0x006284E8`). The two arrays
    ABUT and agree whenever exactly one building is selected — which was every
    case in both suites.
  Neither is exotic. Both die instantly against a randomized sequence that
  varies selection size and counts what the ENGINE did.
- So the design constraint that matters: **assert the engine's own result**
  (AGENTS.md § "Assert the ENGINE'S OWN RESULT, not your bookkeeping"), never
  the plugin's counters. A generator that checks our bookkeeping against our
  bookkeeping is worse than no generator, because it will be trusted.
- Features currently shipped and in scope: production queueing past 5
  (`sc_prodqueue`), production fanout across selected buildings
  (`sc_prodfan`), building control groups, the 12+ unit row and its paging
  (`sc_hudrow`), the queue indicator (`sc_queueind`), upgrades
  (`sc_upgrades`), cancel/refund. Read `research/` for each before generating
  actions against it.
- Existing suites to learn the harness from, not to duplicate:
  `tools/plugin/test-production-queue.ps1`,
  `tools/plugin/test-group-production.ps1`,
  `tools/plugin/test-group-queue-over-five.ps1` (task 038 — the newest and the
  closest in spirit; it runs 025 and 030 together in one game).
- Runtime is a real constraint: this gates merges and the machine runs ONE
  game at a time behind a launch lock. A generator that needs an hour will not
  be run. Decide a per-run budget and design the generator to fit it —
  seeded, reproducible, and able to run a longer sweep on demand.
- **A failure must be reproducible from its seed alone.** A random test that
  cannot hand you the exact sequence that broke it is a rumour, not a report.

## Steps (suggested)

1. Design the action vocabulary and the oracle FIRST, on paper, in the PR
   description or a report: what actions can be generated, what invariant is
   checked after each, and where each invariant's ground truth is read from in
   the engine. Message the conductor with that before building it — a wrong
   oracle wastes the whole task.
2. Then build the smallest generator that can express the user's own example
   (select building, queue N, assert N built and N charged) and make it find
   task 038's bug on a checkout of the commit before its fix. That is your
   proof the harness has teeth — a generator that cannot rediscover a known
   bug proves nothing.
3. Widen to the other features once that works.

## Acceptance criteria

1. A seeded generator + runner, checked in, with a documented per-run time
   budget and a way to run a longer sweep.
2. It rediscovers task 038's bug when pointed at the parent of that fix —
   evidence in the PR (this is the teeth test; without it the task fails).
3. Every assertion reads the engine's own state. Name, per invariant, where
   ground truth comes from.
4. A failing run prints a seed that reproduces it exactly, and you show that
   round-trip once.
5. Any NEW bug it finds gets reported to the conductor as its own message —
   do not fix unrelated features inside this task.
6. Local checks green (`scripts/run-ci-local.ps1`); PR opened with its link in
   Status.pr.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/041-randomized-conformance.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
