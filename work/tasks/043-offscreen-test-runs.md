# Task 043 — Run the whole test suite on the invisible desktop so it stops taking the screen

## Status

agent: 043
model: opus
pr: -

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task043 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task043-offscreen-test-runs.
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

- Your inbox: `C:/git/decompile-sc/work/messages/043/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 043 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

A normal test run puts NOTHING on the user's monitor. Their words, from the
report that started this: "i want to proceeed - can we setup a vm so you can
run tests there so my screen doesn't get messed up? let's keep on
experimienting!" Task 040 found the mechanism and proved the game renders and
captures off-screen. This task makes it the way the suite actually runs.

## Context

- Read `work/reports/040-test-host-isolation.md` first. It is the whole
  design; this task is its § "What is proven vs. what is not yet".
- Already merged and available: `scinject.exe --desktop <name>` sets
  `STARTUPINFOA.lpDesktop` (task 040, PR #49). Unset = old behaviour.
- **The decisive risk, and the first thing to settle:** driving the game with
  posted window messages across desktops is NOT yet proven. 040 argued it
  should work (`PostMessage` and `PrintWindow` are both handle operations,
  and `research/automated-testing-options.md` § 4.1/§ 9 established posted
  messages need neither focus nor foreground) — but argued is not measured.
  If cross-desktop driving does not work, this task is a documented no and
  that is a perfectly good outcome; say so early rather than half-wiring it.
- The work, once that holds: every driving primitive in
  `tools/plugin/drive-game.ps1` needs the same `SetThreadDesktop` treatment
  `PrintWindow` needed, and `run-with-plugin.ps1` needs to pass a
  per-run unique desktop name through to `scinject.exe`.
- Keep the visible desktop reachable. A debugging run where the human WANTS
  to watch must stay one flag away, and it must be the same code path — a
  separate "watch mode" that diverges from how tests really run is how you
  get a bug that only exists when nobody is looking.
- Parallel workers: each run makes its own uniquely-named desktop, so N
  workers means no clutter. But StarCraft is single-instance per MACHINE
  regardless of desktops, so `sc-launch-lock.ps1` still serialises runs and
  must stay. Do not "improve" that away — 040 checked this specifically.
- Existing behaviour worth preserving: task 035 cut the screen theft to ~4
  seconds at launch (AGENTS.md § "Foreground: only ONE primitive may raise").
  If this task succeeds that becomes zero, and the foreground dance may be
  removable on this path — evaluate it, do not assume it.

## Steps (suggested)

1. Prove or refute cross-desktop driving with the smallest possible probe
   (one posted click that changes something observable). Report the result to
   the conductor before building anything on top of it.
2. Wire `--desktop` through `run-with-plugin.ps1`, then make
   `drive-game.ps1`'s primitives desktop-aware.
3. Convert ONE existing end-to-end suite and prove it passes identically on
   the invisible desktop and on the visible one. Same assertions, same
   results — a suite that "passes" off-screen while silently doing less is
   the failure mode to guard against here.
4. Then the rest of the suites.

## Acceptance criteria

1. An existing end-to-end suite runs to completion on the invisible desktop
   with the same assertions passing as on the visible desktop, and NOTHING
   appears on the monitor during the run. Both runs' outputs in the PR.
2. Runtime compared, both ways, measured not estimated.
3. A documented one-flag way to run visibly for debugging, on the same code
   path.
4. `sc-launch-lock.ps1` serialisation intact.
5. Frames stay on the gitignored diagnostic path — never `pr-image` a game
   frame (AGENTS.md § "Screenshots vs hard rule 1 (settled)").
6. Report back (a message, not a code change) on this: task 040's timing run
   of `test-selection-circles.ps1` hit a failure, "[5] the box contained more
   than 12 units", and called it pre-existing WITHOUT proving it. Run that
   suite on clean `main` and tell the conductor whether it is genuinely
   pre-existing or something we broke. Do not fix it inside this task.
7. Local checks green (`scripts/run-ci-local.ps1`); PR opened with its link in
   Status.pr.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/043-offscreen-test-runs.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
