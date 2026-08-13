# Task 056 — Nothing maps a running plugin back to a commit

## Status

agent: 056
model: opus
pr: https://github.com/inwenis/decompile-sc/pull/79
merged: 2026-08-13

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task056 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task056-build-identity.
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

- Your inbox: `C:/git/decompile-sc/work/messages/056/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 056 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

Any running plugin — in a test, in a log, in the user's game — can name the
commit it was built from, and any green run can prove it tested the code it
claims to have tested. Today nothing anywhere maps a DLL back to a source tree,
and that has already cost real time twice.

## Context

- **Issue: https://github.com/inwenis/decompile-sc/issues/73**, from task 052.
  Read it for the four specific gaps with file and line; this file does not
  repeat them.
- **It has already bitten, twice, and the second time was tonight.**
  1. 2026-08-11: a user-reported regression was chased against a stale DLL.
  2. 2026-08-12, ~21:00: the user reported the queue-indicator bug still
     happening. The conductor had to hash three separate `scplugin.dll` files
     and compare mtimes against commit timestamps to establish that their
     deployed build (`B646C6A6…`) came from **main** four minutes AFTER the fix
     commit landed on a branch. Twenty minutes to answer a question a version
     string would have answered instantly.
- **The complication task 048 measured, which changes the design: the build is
  NOT reproducible.** Two builds of the same tree produce different bytes (the
  PE `TimeDateStamp` differs). So a DLL hash identifies *the binary that ran*
  and can never identify *the tree it came from*. Hashing is not the fix.
  Embedding is. Decide whether making the build deterministic is in scope — it
  may be as simple as a linker flag — but do not let it block the identity
  work, and say which you did.
- **The nastiest gap is #73's item 2, and it is silent.** `run-with-plugin.ps1`
  resolves `work/scratch/plugin-build/scplugin.dll` by `Test-Path` alone and
  `-Build` is opt-in. Edit `src/`, forget `-Build`, and every suite in that
  worktree tests the PREVIOUS DLL — green, attributed to code that never ran.
  That is the same family as this repo's dominant defect (a result that cannot
  fail to look right), and it is arguably worth more than the version string.
- **Where the identity has to show up to be useful**, in rough value order:
  1. the plugin's own ATTACH banner (`scplugin.cpp:753-770`), so every log,
     transcript and frame carries it;
  2. a suite's step 0, asserted the way the pristine-`StarCraft.exe` SHA already
     is — that turns "I tested the wrong DLL" from invisible into a failure;
  3. the local CI receipt (task 053 just landed #72's fix — extend that shape,
     do not invent a parallel one);
  4. `deploy.ps1`, which currently prints `version=<sha>` to the console and
     writes it NOWHERE. The user's deployed build should be able to say what it
     is without anyone hashing anything.
- **`+dirty` matters and must not be cosmetic.** `deploy.ps1` already appends it
  to the printed version when the tree is dirty. Whatever you embed should carry
  the same fact, because "built from a tree with uncommitted edits" is exactly
  the state where a commit id alone lies.
- **This is a hobby project.** A short string threaded from `build.ps1` through
  a `-D` define to a log line, plus one assertion and one receipt field, is the
  right size. A build-info subsystem is not.
- **No game runs are required for the mechanism**, but proving item 2 (the
  stale-DLL trap) needs one suite run. Tasks 054 and 055 are sharing the
  machine; `sc-launch-lock.ps1` serialises one launch, not a chain (issue #60).
  **Message the conductor before your first launch** and I will sequence you.

## Steps (suggested)

1. Embed and log first — `build.ps1` → `-DSC_BUILD_ID=...` → ATTACH banner. That
   alone retires most of the pain and is independently useful if the rest slips.
2. Then the stale-DLL trap: make a run that would silently test the wrong DLL
   either rebuild or refuse. Show it failing before you fix it.
3. Then the receipt and `deploy.ps1`.
4. Decide and state the determinism question rather than leaving it implied.

## Acceptance criteria

1. A plugin log from a real run showing the build id in its ATTACH banner, and
   that id verifiably matching `git rev-parse --short HEAD` of the tree it was
   built from — shown, not asserted in prose.
2. The dirty case covered: a build from a tree with uncommitted edits says so.
3. The stale-DLL trap closed, and demonstrated the honest way — a transcript of
   a run that WOULD have tested a stale DLL now failing or rebuilding. If you
   only assert the mechanism without watching it catch, it is not proved
   (AGENTS.md, and task 055 is enforcing the same rule on the suites).
4. The deployed build can report its identity without anyone hashing a file.
5. A stated decision on build determinism: in scope or not, and why. If out of
   scope, open an issue rather than leaving it in the PR body only.
6. `scripts/run-ci-local.ps1` PASS at your final sha. **Merge `origin/main`
   first** — task 053 landed tonight and receipts written before it are refused
   by the gate. Cloud CI is down on billing; note it in the PR body.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/056-build-identity.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
