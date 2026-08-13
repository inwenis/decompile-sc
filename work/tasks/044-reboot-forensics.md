# Task 044 — What restarted the laptop at 02:03Z on 2026-08-12

## Status

agent: 044
model: fable
pr: -
merged: 2026-08-13 (report-only; no PR)

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task044 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task044-reboot-forensics.
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

- Your inbox: `C:/git/decompile-sc/work/messages/044/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 044 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

Name what restarted the machine at 2026-08-12T02:03:01Z, with evidence, and
settle the user's specific fear that an agent or subagent caused it. The
restart killed all four running workers mid-task.

**This task was ALREADY EXECUTED, read-only, on 2026-08-12 07:26–07:32Z, and is
recorded here after the fact.** It ran as an in-session fable subagent rather
than a spawned worker, so it never appeared on the board — the user noticed the
gap and asked. The task file and `work/reports/044-reboot-forensics.md` exist so
the finding and its evidence live in the repo instead of only in a message.
Nothing here is outstanding work.

## Context

- The user's words (2026-08-12T07:28Z): *"the laptop restarted at night it seems
  - what happened? (check that with fable) - I'm afraid a subagent caused the
  restart"*.
- What was running: four Claude Code workers (039, 041, 042, 043) driving an
  offline StarCraft with an injected DLL. Last heartbeats 01:58:59–01:59:14Z.
  `C:\sc-work\logs\sc-launch.lock` records worker 043 launching the game at
  01:59:05Z, 12 seconds before the restart order.
- The plausible-looking suspect was task 043's cross-desktop probe
  (`CreateDesktop` / `SetThreadDesktop`, game launched onto an invisible
  desktop) — the only exotic thing running that minute.
- Read-only forensics only: Windows event logs, Setup log, hotfix list, and a
  grep of the repo's own tooling. Nothing on the machine was modified.

## Acceptance criteria

1. The initiating process is named from the log that records it, or the answer
   is "not settled" with the missing evidence named. — **MET**: User32 1074 at
   02:59:17Z names `C:\WINDOWS\uus\AMD64\MoUsoCoreWorker.exe` on behalf of
   `NT AUTHORITY\SYSTEM`.
2. Every competing hypothesis addressed with the evidence that rules it in or
   out: agent-initiated, bugcheck, power, TDR/graphics, thermal, scheduled task,
   Windows Update. — **MET**, see report § Ruled out.
3. The repo's own tooling is searched for anything that can reboot the machine,
   and the result stated including "nothing". — **MET**: every match is a
   deny-list entry in `config/guard-destructive.ps1` /
   `config/worker-settings.json`, not a call site.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/044-reboot-forensics.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
