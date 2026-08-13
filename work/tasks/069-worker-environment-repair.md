# Task 069 — Fix the three defects that lie to every worker

## Status

agent: 069
model: sonnet
pr: -

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task069 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task069-worker-environment-repair.
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

- Your inbox: `C:/git/decompile-sc/work/messages/069/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 069 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

**Three defects in the worker environment each produce a confident, wrong
message.** Every one was found the same way — a worker believed its tooling,
was wrong, and had to correct itself. Fix all three so the tooling either tells
the truth or says nothing.

They are ranked by how much they cost, not by how hard they look.

## Context

**The pattern that unites them, and the reason this task exists:** none of these
is a crash. Each one **reports success or names a culprit**, and the report is
false. That is worse than an error, because the reader acts on it. Two of the
three sent workers or the conductor after the wrong subsystem today.

### 1. `sc-launch.lock` survives a finished run — issue #103

- **Two occurrences in one hour**, tasks 066 and 068. Both left a lock file
  naming their own dead driver pid; both had verified no `StarCraft.exe`
  existed; both had to hand-clear it.
- **It is not an error path.** 066's suite exited **0**, 068's exited **FAIL 1**,
  and both leaked the file. So it is the release itself, or a re-acquire
  replacing the handle, not error handling.
- **The worst part:** `Exit-ScLaunchLock: released` **printed** in 068's
  transcript while the file survived. The log line reports success it did not
  achieve, so nothing downstream can trust it — including the workers' own
  "machine is free" messages, both of which had to be corrected within a minute.
- **The blocking symptom is separable from the cause and worth fixing on its
  own:** a lock naming a **dead pid is not a lock**. Acquisition could reclaim
  it and say loudly that it did. That unblocks the next worker regardless of
  which cause produced the leak — but **do both**, and do not let the reclaim
  hide the leak.
- Interacts with issue #60 (the lock serialises one launch, not a chain): a
  suite launching several games in sequence is exactly where a re-acquire
  happens.

### 2. Worktrees have no `.venv`, and the failure blames another worker — issue #97

- Chain: fresh worktree has no `.venv` → `make-test-map.ps1` falls back to
  `python` on PATH → no `richchk` → map never written → **`drive-game` reports
  "gone between generation and launch — another worker's cleanup took it"**.
- **Nobody deleted anything.** The message asserts a named culprit from the
  absence of a file. A conductor reading it during a busy board would start
  hunting a cleanup race that does not exist.
- **It also fails 20 Pester tests**, so *every fresh worktree starts with a red
  local CI gate for a reason unrelated to its own work* — and the 20 failures
  point at `make-test-map` rather than at the environment. Task 065 confirmed
  its CI went FAIL → PASS (243/243) purely from creating the venv.
- Three directions, in the issue: fix the accusation, make generation fail
  loudly, close the environment gap. **The accusation is the defect; the venv is
  the trigger. Fix the accusation even if you also fix the venv.**

### 3. `prune-worktrees.ps1` strands directories it can no longer see — issue #96

- It deregisters the worktree **before** removing the directory. When removal
  fails (a lingering handle, a just-closed tab), the deregistration has already
  happened — so `git worktree list` no longer names it and the script reports
  `nothing prunable` while the directory sits on disk.
- **Six were stranded this way**, one 52 MB. Manual removal succeeded on one and
  failed on five with `being used by another process` — **including four that
  were 0 MB**, i.e. empty directories nobody could delete.
- Also in #96: `board-lint.ps1` class 2 fires on report-only tasks and asks for a
  close that `close-task.ps1` refuses **by design** ("a done task with no PR is
  already completed"). The two scripts disagree about what "done" means. Tasks
  044, 049 and 052 are all legitimately finished and all lint red forever.

## Steps (suggested)

1. Start with the lock — it is the one that can block the machine, and two
   workers hit it today.
2. Reproduce each before fixing it. All three are reproducible without the game:
   the lock via the acquire/release path, the venv chain in a fresh worktree,
   the prune by making the directory removal fail.
3. For each, ask what the tooling **said** while it was wrong, and make that
   line honest.

## Acceptance criteria

1. **Each of the three fixed, with a test that fails without the fix.** These
   are all "the code reports success it did not achieve" defects, so a test that
   only checks the happy path proves nothing — the test must catch the false
   report.
2. **No new confident-but-wrong messages.** Where the tooling cannot know
   something (why a file is absent, whether another worker touched it), it says
   what it observed, not what it concluded.
3. A stranded worktree directory that already exists on disk is cleanable by the
   tooling — five of them are sitting there now, and four are 0 MB and locked.
   If they genuinely cannot be removed, say why, and make the lint stop
   demanding it.
4. `board-lint.ps1` and `close-task.ps1` agree about report-only tasks. Either
   lint stops firing on them or there is a way to stamp them closed.
5. Issues #103, #97 and #96 closed or updated with what was actually done.
6. `scripts/run-ci-local.ps1` PASS; PR opened with the link in Status.pr. Cloud
   CI is down on billing — note it in the body. **PRs may stack** (standing user
   instruction) — say what you branched from.

## Machine

**You should not need the game at all.** If you think you do, message the
conductor first — task 068 is using it for the widescreen fog work and has
priority. Note that testing the lock's acquire/release does not require
launching StarCraft.

**Your own worktree has the `.venv` gap** (defect 2) — junction the main
checkout's in before running anything that generates a fixture, and note that
your first `run-ci-local.ps1` may be red for exactly that reason.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/069-worker-environment-repair.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
