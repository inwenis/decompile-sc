# Task 047 — test-combat-death asserts a hardcoded hook count that task 036 outgrew

## Status

agent: 047
model: sonnet
pr: -

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task047 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task047-combat-death-hook-count.
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

- Your inbox: `C:/git/decompile-sc/work/messages/047/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 047 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

`test-combat-death.ps1` part [5] asserts a hardcoded hook TOTAL that the plugin
outgrew, so the suite is red for a reason that is not a bug. Fix it so it stops
lying, and — the part that matters more — so it cannot rot the same way the next
time a hook is added.

## Context

- Found by task 046 (2026-08-12) while fixing a stale regex fossil in the same
  file. Traced from source, no launch needed — take the trace as a starting
  point, not as proof; confirm it yourself:
  - task 036 bumped the shadow-mode hook base from 4 to 5, adding
    `unit_IsStandardAndMovable`;
  - so the real expected total is `5 + circles(1) + hudrow(1) + queueind(0) = 7`;
  - the engine reports 7 correctly. The suite's hardcoded `-eq 6` was never
    bumped. **The magic number is wrong, not the plugin.**
- Task 046's PR (#53, merged) fixed two stale-pattern fossils in this same file.
  This is the third of the same family: a literal in a test that encodes a fact
  about the plugin, with nothing tying the two together.
- **The design point, and the reason this is a task rather than a one-line
  commit:** a hardcoded expected COUNT silently rots every time a hook is added,
  and it fails in the least useful way — "expected 6, got 7" names no hook.
  Prefer asserting the COMPOSITION (which hooks installed, by name) over the
  total, so a future addition either passes because it is listed or fails saying
  exactly what appeared. Only fall back to a total if reading the names is not
  available; if so, say why in the PR.
- AGENTS.md § "Your DIAGNOSTICS are under the same rule as your assertions"
  applies: prefer naming WHICH thing, over counting how many.
- Machine time is contended today (039 and 041 are running paired arms). Do the
  source work first; you need one launch to confirm, and off-screen is available
  (`tools/plugin/run-offscreen.ps1`) — but note this suite currently takes the
  game-type dropdown, which CANNOT work off-screen (one foreground window, and it
  belongs to the desktop taking input). So expect to run it `-Visible`, and keep
  it to a single launch.

## Acceptance criteria

1. The [5] assertion passes for the right reason — the plugin's real hook set —
   and you show the run.
2. The assertion still CAN fail: break it on purpose once and show the output.
3. If you assert composition rather than a total, a hook added tomorrow produces
   a message that NAMES it. Demonstrate that (a fake extra entry is enough).
4. Confirm task 046's trace independently rather than inheriting it: say which
   hooks the plugin actually installs in that arm, and where you read that from.
5. `scripts/run-ci-local.ps1` PASS; PR opened with its link in Status.pr. GitHub
   Actions is down on a billing error, so the local receipt is the gate — note it
   in the PR body.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/047-combat-death-hook-count.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
