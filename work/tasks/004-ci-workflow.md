# Task 004 — CI workflow so merges have real evidence

## Status

agent: 004
model: sonnet
pr: https://github.com/inwenis/decompile-sc/pull/4
merged: 2026-08-06

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task004 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task004-ci-workflow.
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

- Your inbox: `C:/git/decompile-sc/work/messages/004/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 004 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

This repo has **no CI at all**, and that is now blocking every merge. Add
`.github/workflows/ci.yml` so each PR carries real evidence that the tooling still works:
PowerShell scripts parse and their tests pass, Python tooling imports and is lint-clean.
The workflow must run on a plain GitHub-hosted runner with **no game files, no Ghidra, and
no StarCraft install available** — anything that needs those is out of scope for CI.

## Context

- **Why this is urgent**: `scripts/merge-task.ps1` refuses to merge unless `gh pr checks`
  reports a green run of a workflow literally named `CI`. See
  `scripts/lib/merge-task.ps1:15-24` — it deliberately does NOT count third-party app checks
  (GitGuardian runs on every PR here) as evidence, because a secrets scan passing says
  nothing about whether the code works. With no `ci.yml`, the verdict is `none` and
  merge-task throws `no CI checks reported on PR #N`. Three PRs (#1, #2, #3) are blocked
  behind this right now.
- **The workflow's `name:` MUST be exactly `CI`** — `Get-ChecksVerdict` defaults to
  `-Workflow 'CI'` and matches on that name. Get this wrong and the gate stays shut.
- Repo contents to cover: `scripts/*.ps1` and `scripts/lib/*.ps1` (PowerShell 7, every file
  starts `#Requires -Version 7`), `config/*.ps1`, `tools/*.ps1`, `tools/*.py`, and
  `requirements.txt`. Note PR #3 (may not be merged when you start — check `origin/main`)
  adds `tools/pe_report.py` and `requirements.txt`; PR #1 adds `tools/ghidra/analyze.ps1`
  and a Java script. Write the workflow so it handles those files existing or not, rather
  than hardcoding a file list that breaks the moment one lands.
- There is currently **no test suite**. Do not invent a large one. A parse/lint/import gate
  is genuinely useful and is what this task is for. If you add any tests, they must not
  require the game, Ghidra, a JDK, or network access.
- The conductor's source system uses Pester for PowerShell tests. If (and only if) a
  `tests/` directory exists in this repo, run Pester over it; otherwise skip that step
  cleanly rather than failing.

## Hard constraints

1. CI must be **hermetic**: no StarCraft files, no `C:\sc-install`, no `C:\sc-work`, no
   Ghidra download, no game launch. Those exist only on the user's machine. A CI job that
   depends on them is a failed task.
2. Keep it **fast** (target under ~3 minutes) and cheap — it runs on every push.
3. Do not add anything that would fail on a fresh clone with no secrets configured.
4. Do not weaken or edit `scripts/merge-task.ps1` / `scripts/lib/merge-task.ps1` to get
   around the gate. The gate is correct; supply the evidence it asks for.

## Steps (suggested)

1. Create `.github/workflows/ci.yml` with `name: CI`, triggered on `pull_request` and on
   `push` to `main`.
2. Use `windows-latest` — the scripts are PowerShell 7 (`pwsh`, preinstalled) and this repo
   is Windows-only by nature.
3. PowerShell job steps:
   - Parse-check every `.ps1` in the repo (excluding `.git`) using
     `[System.Management.Automation.Language.Parser]::ParseFile(...)` and fail on any error.
     This is the single highest-value check — a copied-and-rewritten script that no longer
     parses is exactly the failure class this repo is prone to.
   - Validate every `.json` under `config/` and `.claude/` parses (`ConvertFrom-Json`).
   - If `tests/` exists, run `Invoke-Pester -CI`; otherwise print that it was skipped.
4. Python job steps (or steps in the same job):
   - Set up Python 3.11, `pip install -r requirements.txt` if that file exists.
   - Byte-compile every `.py` under `tools/` (`python -m compileall -q`), and run a linter
     if you add one to `requirements.txt` — keep it light.
5. Add a guard step that FAILS if any file with a game-content extension is tracked in git
   (`.exe`, `.dll`, `.mpq`, `.snp`, `.grp`, `.chk`, `.rep`, `.idb`, `.i64`, `.gpr`, and
   large binary blobs). This mechanises project hard rule 1 — "never commit game content" —
   instead of relying on everyone remembering it. Use `git ls-files` so it checks what is
   TRACKED, not what is merely present in the working directory.
6. Verify the workflow actually runs and goes green on your own PR before reporting done.
   A PR that adds `ci.yml` does trigger it, so you can prove this end-to-end.

## Acceptance criteria

1. `.github/workflows/ci.yml` exists, its `name:` is exactly `CI`, and it triggers on
   `pull_request` and `push` to `main`.
2. The run is **green on this task's own PR** — paste the run URL and its conclusion in the
   PR. Do not report done off a local dry run.
3. It parse-checks all `.ps1` and JSON-validates `config/`/`.claude/` JSON, and fails on a
   deliberately broken file (prove this: temporarily break one locally, show it fails, then
   revert — do NOT commit the broken file).
4. It handles `requirements.txt`, `tools/*.py`, and `tests/` being absent or present without
   erroring either way.
5. The tracked-game-content guard works — demonstrate it catching a file (e.g. `git add -f`
   a dummy `.mpq` locally, show CI logic rejects it, then remove it; nothing binary is ever
   committed).
6. Hermetic: no step references the game install, working copy, Ghidra, or the network
   beyond package installs.
7. PR opened, link in Status.pr.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/004-ci-workflow.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
