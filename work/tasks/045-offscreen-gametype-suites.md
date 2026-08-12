# Task 045 — Convert the remaining game-type suites to off-screen, or document the boundary

## Status

agent: 045
model: sonnet
pr: -

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task045 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task045-offscreen-gametype-suites.
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

- Your inbox: `C:/git/decompile-sc/work/messages/045/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 045 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

Every suite that can run off-screen does, and the ones that cannot are named
with the reason, in one place, so nobody has to rediscover it. Task 043 built
the mechanism and proved two suites of different shapes on it; this finishes the
sweep. The user's ask behind all of it: *"i want to proceed - can we setup a vm
so you can run tests there so my screen doesn't get messed up?"* — a normal run
should put nothing on their monitor.

## Context

- Read `work/tasks/043-offscreen-test-runs.md` and PR #52 (merged) first. The
  mechanism is `tools/plugin/run-offscreen.ps1` + `tools/plugin/sc-desktop.ps1`,
  and `run-with-plugin.ps1` auto-detects the desktop it was born on — normally
  nobody passes `-Desktop`.
- **Proven off-screen already** (do not redo): `test-selection-circles.ps1`
  (assertion-for-assertion identical to the visible arm, 75.0 s vs 75.2 s) and
  `test-stim-fanout.ps1` (fixture generation, Game Type, keyboard, 36 units,
  0 failures).
- **The one hard limit, measured by 043, not assumed:** a DROPDOWN PICK cannot
  work off-screen, ever. Windows has one foreground window and it belongs to the
  desktop receiving input, so a window on an invisible desktop can never hold it
  (`GetForegroundWindow()` reads 0 there for the whole run), and
  `Send-ScDropdownPick` needs the foreground for the game's `SetCapture`
  (AGENTS.md § Foreground, half 2). `probe-quiet-dropdown.ps1` failed ALL THREE
  arms through `run-offscreen.ps1` — including arm C, the foreground control that
  passes every time on the monitor. Do not try to defeat this; measure around it.
- Why most suites are unaffected anyway: `Set-ScGameType` SKIPS the pick when the
  combo already reads the wanted value (issue #29), which is the common case on
  this machine — that is the path `test-stim-fanout` took. So the question per
  suite is empirical: does it ever actually need a pick?
- When a pick IS needed the run throws and names the desktop as the cause,
  pointing at `-Visible`. It must keep doing that. A suite that silently runs a
  lesser test off-screen is the failure mode to avoid (AGENTS.md § "a check that
  cannot fail is worth nothing").

## Steps (suggested)

1. Enumerate every suite under `tools/plugin/test-*.ps1` and probe scripts a
   worker actually runs. That list is the deliverable's spine.
2. Run each off-screen. Same suite, same assertions, no edits to the suite to
   make it pass — if it needs an edit, the edit is the finding.
3. For each: PASSES off-screen / NEEDS `-Visible` because it picks a game type /
   fails for some OTHER reason (that third bucket is a bug, report it, do not
   fix it inside this task).
4. Write the table into `tools/plugin/README.md` next to 043's section, and make
   the default for a worker run be off-screen wherever the table says it works.

## Acceptance criteria

1. A table in `tools/plugin/README.md`: every suite, its verdict, and for
   anything needing `-Visible`, the measured reason.
2. Each "passes off-screen" row is backed by an actual run, with the log path
   named — not by inspection of the script.
3. `watch-foreground.ps1` across at least one full multi-suite off-screen run,
   reporting no StarCraft window ever foreground.
4. Nothing in `sc-launch-lock.ps1` changes — the game is single-instance per
   MACHINE regardless of desktops, so runs still serialise (043 checked this;
   040 checked it before that).
5. Any suite in the third bucket is reported to the conductor as a message with
   what failed, not fixed here.
6. `scripts/run-ci-local.ps1` PASS; PR opened with its link in Status.pr. Note in
   the PR body that GitHub Actions is down on a billing error and the local
   receipt is the gate.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/045-offscreen-gametype-suites.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
