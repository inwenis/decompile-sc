# Task 049 — Sweep every suite off-screen and publish the verdict table

## Status

agent: 049
model: sonnet
pr: -

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task049 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task049-offscreen-suite-sweep.
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

- Your inbox: `C:/git/decompile-sc/work/messages/049/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 049 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

Every suite that can run off-screen does, and the ones that cannot are named
with the measured reason, in one table, so "which suites take the user's screen"
stops being folklore. This is part 1 of what task 045 was cut for; part 0 (the
mechanism's own defects) shipped separately as PR #57 and task 045 is closed.

## Context

- Read `work/tasks/045-offscreen-gametype-suites.md` and PR #57 first. The
  mechanism is `tools/plugin/run-offscreen.ps1` + `tools/plugin/sc-desktop.ps1`;
  `run-with-plugin.ps1` auto-detects the desktop it was born on, so normally
  nobody passes `-Desktop`.
- **Already proven off-screen, do not redo:** `test-selection-circles.ps1`
  (assertion-for-assertion identical to a visible arm, 75.0 s vs 75.2 s) and
  `test-stim-fanout.ps1` (fixture generation, Game Type, keyboard, 36 units,
  0 failures) — both task 043. Task 039 has also run its own probes and
  `test-group-production` off-screen; ask it rather than re-running.
- **The one hard limit, measured, not assumed:** a game-type DROPDOWN PICK cannot
  work off-screen. Windows has one foreground window and it belongs to the
  desktop receiving input, so a window on an invisible desktop can never hold it
  (`GetForegroundWindow()` reads 0 there all run), and `Send-ScDropdownPick`
  needs the foreground for the game's `SetCapture` (AGENTS.md § Foreground,
  half 2). Task 043 proved this properly: all three arms failed off-screen,
  including the foreground control arm that passes every time on the monitor.
  Do not try to defeat it; measure around it.
- But most suites never hit it: `Set-ScGameType` SKIPS the pick when the combo
  already reads the wanted value (issue #29), which is the common case on this
  machine. So the question per suite is empirical — does it EVER actually need a
  pick? `test-combat-death.ps1` is a known yes (task 047 had to run it
  `-Visible`).
- Part 0 fixed three things you now depend on: `CREATE_NO_WINDOW` (a spawned
  child creates no console window — measured 19/19 conhost+Terminal processes),
  a per-CALL GUID in the desktop name (chained steps no longer race), and a
  child that dies before writing its `run-offscreen(child):` header being a loud
  failure rather than a stale exit 0. **Trust none of your runs' exit codes
  anyway** — take a run as green only when the suite's own `N failure(s)` line
  is in its log.
- **User standing rules, both live:** anything that disturbs their screen waits
  for 23:00–07:00 local; and any run that must go `-Visible` is announced to the
  conductor BEFORE it starts. Off-screen runs no longer disturb anything, so most
  of this task is unrestricted — but every `-Visible` run you need is a message
  to the conductor first, not a judgement call.

## Steps (suggested)

1. Enumerate every `tools/plugin/test-*.ps1` and the probe scripts a worker
   actually runs. That list is the deliverable's spine.
2. Run each off-screen, unmodified. If a suite needs an edit to pass off-screen,
   the edit is the finding — report it, do not quietly make it.
3. Bucket each: PASSES off-screen / NEEDS `-Visible` because it takes a pick /
   fails for some OTHER reason. That third bucket is a bug: report it to the
   conductor, do not fix it inside this task.
4. Write the table into `tools/plugin/README.md` beside task 043's section.

## Acceptance criteria

1. A table in `tools/plugin/README.md`: every suite, its verdict, and for
   anything needing `-Visible`, the measured reason (not an assumed one).
2. Each "passes off-screen" row is backed by an actual run with its log path
   named — not by reading the script.
3. `watch-foreground.ps1` across at least one full multi-suite off-screen run,
   reporting no StarCraft window ever foreground.
4. `sc-launch-lock.ps1` unchanged — the game is single-instance per MACHINE
   regardless of desktops, so runs still serialise (043 and 040 both checked
   this).
5. Anything in the third bucket reported as a message, not fixed here.
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
- <either> that PR <or> a report at work/reports/049-offscreen-suite-sweep.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
