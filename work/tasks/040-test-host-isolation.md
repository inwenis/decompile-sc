# Task 040 — Stop test runs from taking over the screen (VM or equivalent)

## Status

agent: 040
model: sonnet
pr: -

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task040 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task040-test-host-isolation.
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

- Your inbox: `C:/git/decompile-sc/work/messages/040/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 040 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

Answer, with a working demonstration or a measured no, whether our test runs
can stop taking over the user's screen — by running the game in a VM, or by
any equivalent that isolates it from their desktop session.

**This task installs nothing on the user's machine without their explicit
approval.** It produces a recommendation plus the exact steps and costs; the
conductor relays it and the user decides. That approval gate is the one hard
boundary here (project hard rule 5: their machine is not a test bench).

## Context

- **The user's exact words (2026-08-11T23:01Z):** "as for the screen - i want
  to proceeed - can we setup a vm so you can run tests there so my screen
  doesn't get messed up? let's keep on experimienting!"
- Today every test run launches StarCraft on their desktop. Task 035 cut the
  theft down to ~4 seconds at launch (AGENTS.md § "Foreground: only ONE
  primitive may raise"), but it is still their screen, and the fanout of
  parallel workers makes it worse.
- Machine facts you must check rather than assume: the host is **Windows 11
  Home**. Hyper-V's management stack is not offered on Home editions, which
  rules out the first answer most people reach for. Free alternatives exist
  (VirtualBox, VMware Workstation Player) and each has its own cost in guest
  licensing and 2D/DirectDraw performance for a 1.16.1-era game.
- Non-VM routes are in scope and may well win — a second Windows session, a
  separate desktop/window station, or anything else that gives the game its
  own foreground to steal. Evaluate them honestly against the VM.
- What "works" means here: `tools/plugin/run-with-plugin.ps1` and the test
  scripts run to completion, the screenshots/frame captures the tests depend
  on are still valid, and nothing appears on the user's monitor. A route that
  runs the game but breaks frame capture is not a route — our whole
  verification method is looking at frames.
- Speed is a real constraint, not a nicety: the suite already gates every
  merge. Measure the slowdown; a correct answer that triples run time needs
  to say so.
- Related open issue: #29 (last window flicker).

## Steps (suggested)

1. Enumerate the candidate routes with their real blockers on THIS machine
   (edition, licensing, GPU/DirectDraw, capture path). Cheap desk research
   first — do not install anything yet.
2. Pick the most promising one or two and prove the decisive risk before the
   convenient parts: can the game render and can we capture a frame from it.
   If a route needs an install to test that, stop and ask the conductor for
   approval, naming exactly what gets installed and where.
3. Report a recommendation with numbers: setup cost, per-run cost, what
   breaks, what the user must do once.

## Acceptance criteria

1. A written comparison of the routes with the Windows 11 Home constraint
   verified rather than assumed, at `work/reports/040-test-host-isolation.md`.
2. For the recommended route: either a demonstration (the game running and a
   frame captured off the user's screen, evidence embedded) or an explicit,
   evidenced statement of what blocks it.
3. Measured runtime impact on at least one existing test script.
4. The exact approval-gated steps the user would take, written so they can
   say yes or no in one read.
5. Nothing installed or configured on the host without conductor-relayed
   user approval. No writes to live user state (project hard rule 5).

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/040-test-host-isolation.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
