# Task 050 — Six suites call the raw dropdown pick and always need the screen

## Status

agent: 050
model: sonnet
pr: -

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task050 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task050-dropdown-pick-routing.
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

- Your inbox: `C:/git/decompile-sc/work/messages/050/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 050 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

Six suites call `Send-ScDropdownPick` directly, so they ALWAYS raise a window
and therefore always need the user's screen. Route them through the wrapper that
exists to avoid exactly that, so a normal test run stops taking the monitor.
Every suite that does not genuinely need a different game type should stop
needing `-Visible` at all.

## Context

- Found by task 049 (2026-08-12) while surveying which suites can run
  off-screen. It read every call site rather than guessing; take the split as a
  starting point and re-check it, since the whole task rests on it.
- **GROUP A — through `Set-ScGameType`** (the issue #29 wrapper: reads the combo
  first, SKIPS the pick and the raise when it already reads the wanted value), 9
  suites: `test-group-queue-over-five`, `test-group-production`,
  `test-widescreen`, `test-random-conformance`, `test-sunken-acquire`,
  `test-upgrade-queue`, `test-stim-fanout`, `test-production-queue`,
  `test-ability-in-combat`. On this machine the combo is almost always already
  correct, so these mostly run off-screen fine — every run today logged
  *"game type is already 'Use Map Settings' … no pick, no raise"*.
- **GROUP B — raw `Send-ScDropdownPick`, unconditional, no read-first, no skip**,
  6 suites: `test-building-parity`, `test-building-groups`, `test-burrow-fanout`,
  `test-control-groups`, `test-hud-row`, `test-combat-death`. These always
  attempt the raise, and a raise cannot land on an invisible desktop (task 043
  measured all three arms), so they need `-Visible` **by construction, every
  time** — not intermittently.
- That is why `test-combat-death` needed `-Visible` in task 047: not an unusual
  combo, simply never routed through the wrapper.
- Why this matters beyond tidiness: the user asked for test runs to stop taking
  their screen (tasks 040/043), and 049 will publish a table saying six suites
  still do. Most of those six probably do not have to.
- `Send-ScDropdownPick` remains the ONE primitive allowed to raise, and this task
  does not change that (AGENTS.md § Foreground, half 2). It changes WHO calls it
  and whether they call it when it is unnecessary.
- Task 049 is producing, per Group-B suite, whether it needs a game type OTHER
  than Use Map Settings. That answer decides whether `Set-ScGameType` is a
  drop-in or whether the wrapper needs a parameter. Ask 049 (or read its merged
  table) before designing.

## Acceptance criteria

1. Every Group-B suite either routes through `Set-ScGameType`, or keeps the raw
   pick with a stated measured reason why the wrapper cannot serve it.
2. Each converted suite RUNS off-screen, proven, with the log line showing the
   pick was skipped — not merely "it no longer calls the raw primitive".
3. Any suite that still needs `-Visible` after the change is named with its
   reason, and `tools/plugin/README.md`'s table (task 049) is updated to match.
4. No suite loses its ability to set a game type it genuinely needs; if the
   wrapper gains a parameter, say why in the PR.
5. Standing user rules apply: `-Visible` runs are announced to the conductor
   before they start and belong in the 23:00–07:00 window.
6. `scripts/run-ci-local.ps1` PASS; PR opened with its link in Status.pr. GitHub
   Actions is down on a billing error — the local receipt is the gate, note it in
   the body.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/050-dropdown-pick-routing.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
