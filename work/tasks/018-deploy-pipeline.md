# Task 018 — One-click deployed install with desktop shortcut

## Status

agent: 018
model: sonnet
pr: https://github.com/inwenis/decompile-sc/pull/18
merged: 2026-08-08

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task018 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task018-deploy-pipeline.
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

- Your inbox: `C:/git/decompile-sc/work/messages/018/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 018 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

**The user double-clicks a desktop shortcut and plays the modded game. No terminal, no args.**
Their words: "i want the latest version of our game to be 'deployed' = installed in some location
on my laptop with a shortcut on desktop pointing to it so i can run it without running a script
with args. whenever you finish a feature - deploy it so i can play it."

Deliverable: `tools/deploy.ps1` — one command the conductor runs after every merge. It builds the
plugin from the current checkout, assembles a self-contained install at a deploy location, and
creates/updates the desktop shortcut. Idempotent: re-running overwrites the deployed version
cleanly.

## Context

- Source of the game files: the working copy `C:\sc-work\1161-base` (verified pristine,
  SHA-256 `AD6B58B2…C6A46`). The PRISTINE install `C:\sc-install\Starcraft` is read-only,
  hard rule 1 — never source from or write to it.
- Suggested deploy target: `C:\sc-deploy\starcraft-modded\` (create; not inside the repo, not
  inside C:\sc-work, absolutely not C:\sc-install). Your call if a better convention exists —
  document it.
- What the shortcut must do: launch the deployed game with the full feature set on (fanout mode,
  circles, HUD row) and windowed, with the plugin injected — the same end state
  `tools/plugin/run-with-plugin.ps1 -Mode fanout -Windowed` produces today, but rooted at the
  deploy dir and with zero user-facing arguments. Reuse run-with-plugin.ps1 (a thin launcher
  in the deploy dir that calls it with baked parameters is fine) or extract the launch logic —
  your call; state the trade-off you picked. The launcher must not require an elevated shell.
- Desktop shortcut: `StarCraft Modded.lnk` on the user's desktop, icon from the game exe.
  `pwsh -WindowStyle Hidden -File <launcher>` or equivalent — double-click, game appears,
  no console window lingering.
- The existing safety rails stay: the pristine-install guard in run-with-plugin.ps1, the
  passive off-switches (`-Mode observe`, `-Circles 0`, `-HudRow 0`) must remain reachable for
  debugging (a second shortcut is NOT needed; a documented one-liner is fine).
- `deploy.ps1` must verify before finishing: deployed `StarCraft.exe` byte-identical to the
  working copy's (which is pristine), plugin DLL freshly built from HEAD, shortcut resolves.
  Print a one-line deploy receipt (version = git short SHA + date).
- Document in `tools/README-deploy.md`: what deploys where, how to re-deploy, how to remove.
- Game files in the deploy dir are GAME CONTENT: the deploy dir must never be committed
  (it lives outside the repo) and deploy.ps1 must refuse a target inside the repo.

## Hard rules

1. Never modify, write to, or launch `C:\sc-install\Starcraft`.
2. Offline, single-player only.
3. Commit no game content, no binaries.
4. Do not merge your own PR.

## Acceptance criteria

1. `tools/deploy.ps1` run from the repo produces the deployed install + desktop shortcut;
   run twice = same result (idempotent overwrite).
2. Double-clicking the shortcut launches the modded game windowed with fanout+circles+HUD row
   active — verified by actually launching it via the shortcut path (`Invoke-Item` on the .lnk
   or the launcher directly), reading the plugin log for the feature-init lines, then closing
   cleanly (close-game.ps1 pattern; no stranded process).
3. Deployed StarCraft.exe hash == working-copy hash (asserted in deploy.ps1); deploy dir is
   outside the repo and deploy.ps1 refuses an in-repo target.
4. `tools/README-deploy.md` documents deploy/re-deploy/remove + the debug off-switch one-liner.
5. CI green; no game content committed.
6. PR opened, link in Status.pr.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/018-deploy-pipeline.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
