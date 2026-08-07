# Task 007 — Harden make-working-copy + document shared Ghidra install

## Status

agent: 007
model: sonnet
pr: https://github.com/inwenis/decompile-sc/pull/7
merged: 2026-08-07

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task007 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task007-tooling-hardening.
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

- Your inbox: `C:/git/decompile-sc/work/messages/007/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 007 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

Two small, independent pieces of debt from earlier reviews, plus one documentation gap that
already cost a worker ~10 minutes. All three are on `main` today. Small task — do not expand it.

## Context

### A. `tools/make-working-copy.ps1` — `Test-KeyBinaries` cannot report what it finds

The script sets `$ErrorActionPreference = 'Stop'`, which makes `Write-Error` a **terminating**
error. So the first hash mismatch throws immediately, and the `$ok = $false` / `continue`
accumulation below it is unreachable — the function can never actually return `$false`, and the
intended "report every problem, then fail with one clear message" behaviour never happens.

It fails in the SAFE direction (it still stops, and it stops before copying), so this is
correctness-of-reporting, not a safety hole. Fix: use `Write-Host`/`Write-Warning` for the
per-item diagnostics and let the existing explicit `throw` report the collected failures.

**This bug family has now bitten this repo three times** — the same PowerShell error/exit-code
semantics mismatch caused a CI outage where every run failed *because an optional linter was
correctly skipped* (`pip show` exits 1; the stale `$LASTEXITCODE` failed the step). While you
are in these files, grep for the pattern rather than fixing only the instance named here:
`Write-Error` under a `Stop` preference, and any `$LASTEXITCODE` read after a native command
whose non-zero result is expected/benign.

### B. `tools/make-working-copy.ps1` — `robocopy /MIR` will purge a mistyped destination

`/MIR` mirrors, which means it **deletes** anything in the destination not present in the
source. With `-Force`, a mistyped `-Destination` therefore wipes whatever is at that path. It
needs two explicit flags to reach, so it is not a default-path hazard, but the guard is cheap.

Add a sanity check before the copy: refuse unless the destination is empty, OR already looks
like a StarCraft install (e.g. contains `StarCraft.exe`), OR sits under a known scratch root.
Keep `-Force` meaningful for the normal reset case — `make-working-copy.ps1 -Force` against
`C:\sc-work\1161-base` is the documented, frequently-used way to reset the working copy and
must keep working exactly as it does now.

### C. `tools/ghidra/README.md` — document where the Ghidra install belongs

The install must live **outside every worktree and repo**. Agreed location on this machine:
`C:\re-tools\ghidra_12.1.2_PUBLIC\`, with `GHIDRA_INSTALL_DIR` set at user scope. `analyze.ps1`
already honours both `$env:GHIDRA_INSTALL_DIR` and `-GhidraInstallDir`, so this is a docs
change only — do not change the code.

Why it matters, and worth stating in the README so nobody rediscovers it: the install is
gitignored, so it is invisible to git. When a task's worktree is merged and pruned, a Ghidra
install inside that worktree is destroyed silently along with it. That happened — task 005 lost
its toolchain mid-run because the conductor pruned task 001's worktree, which held the only copy
on the machine. The README's install instructions currently extract into `tools/ghidra/`, i.e.
straight into a worktree. Update them to install to the shared path and reference it via the
environment variable.

## Constraints

1. Do NOT touch `scripts/merge-task.ps1` or `scripts/lib/merge-task.ps1`.
2. Do NOT change `analyze.ps1` behaviour for item C — docs only.
3. Do NOT modify `C:\sc-install\Starcraft`, and do not launch the game.
4. Task 005 is concurrently working in `tools/ghidra/scripts/`, `tools/ghidra/specs/`,
   `sweep.ps1` and `research/`. **Stay out of those.** Your only file under `tools/ghidra/` is
   `README.md`. If you find yourself editing anything else there, stop.
5. Do not merge your own PR.

## Acceptance criteria

1. `Test-KeyBinaries` reports every failing binary and then fails once with a clear message —
   demonstrated by running it against a deliberately wrong expected hash locally (revert after;
   commit nothing broken).
2. A grep for the same error/exit-code pattern across `tools/` and `scripts/` is reported in the
   PR, with anything else found either fixed or explicitly listed as out of scope.
3. `make-working-copy.ps1` refuses a destination that is neither empty, nor an SC install, nor
   under a known scratch root — demonstrated. And `-Force` against `C:\sc-work\1161-base` still
   resets normally — also demonstrated, with the hash verification still passing.
4. `tools/ghidra/README.md` documents the shared install path, the `GHIDRA_INSTALL_DIR`
   mechanism, and the prune-destroys-it rationale.
5. CI green on your PR. PR opened, link in Status.pr.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/007-tooling-hardening.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
