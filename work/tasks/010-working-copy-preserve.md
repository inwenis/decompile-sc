# Task 010 — Stop working-copy resets from destroying profiles, replays and test maps

## Status

agent: 010
model: sonnet
pr: -

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task010 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task010-working-copy-preserve.
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

- Your inbox: `C:/git/decompile-sc/work/messages/010/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 010 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

Make `tools/make-working-copy.ps1 -Force` stop silently destroying things people care about.
Today it runs `robocopy /MIR`, which deletes everything in the destination that is not in the
pristine install — including the player's profile, replays, and generated test maps. Rung-3
testing will reset the working copy frequently, so this needs fixing before it becomes a
recurring annoyance.

## What actually happened (the incident this task exists for)

A reset at 07:46 UTC on 2026-08-07 purged:

```
*EXTRA Dir              C:\sc-work\1161-base\characters\
*EXTRA File       36    C:\sc-work\1161-base\characters\asdf.spc
*EXTRA Dir              C:\sc-work\1161-base\Maps\replays\
*EXTRA File    42685    C:\sc-work\1161-base\Maps\replays\LastReplay.rep
*EXTRA File    59630    C:\sc-work\1161-base\Maps\_smoke_test_out.scx
```

The `.spc` was **the user's player profile**, created minutes earlier for a live test — so the
next single-player game asks for a name again. The `.rep` was the replay of that same game. The
`.scx` belonged to a *different concurrently-running task*.

Two distinct problems, and the second is the more interesting one:

1. **The purge is invisible.** It happens inside robocopy's output, so nobody sees what was
   deleted until they go looking. The script reports success either way.
2. **The working copy is a SHARED resource.** Two tasks were writing into it at once, and a
   mirroring reset has no idea another task is mid-use. That was a conductor orchestration
   error rather than a tooling bug — but tooling can make it much harder to cause harm, and
   that is what this task is for.

## What to build

Preserve by default; require an explicit opt-in to destroy. Concretely:

- **Preserve across a reset**, unless explicitly told otherwise: player profiles
  (`characters\`), replays (`Maps\replays\`), and generated test maps in `Maps\`. These are
  user- or test-created artifacts, not game files, and none of them affect whether the copy is a
  faithful reproduction of the binary.
- **Add an explicit switch** (something like `-Pristine` or `-PurgeExtras`) that does the current
  true byte-for-byte mirror, for when someone genuinely wants a clean slate. Name it so the
  destructive one is the one you have to ask for.
- **Report what is about to be removed, plainly**, before removing it — a short list on stdout,
  not buried in robocopy's log. Anyone watching should be able to see "these 3 files will be
  deleted" without reading a copy transcript.
- **Preserve the integrity guarantee.** The whole point of this script is that the working copy's
  game binaries are byte-identical to the pristine install. Preserving a profile must NOT weaken
  that: the hash verification of `StarCraft.exe` / `storm.dll` / `battle.snp` and the file-count
  and size comparison must still run and still be meaningful. Think carefully about how the
  count/size comparison should treat preserved extras — reporting them separately is likely
  cleaner than silently excluding them.

Design freedom is yours. A backup-then-restore around `/MIR`, robocopy exclusion flags, or a
different copy strategy are all acceptable if the result is correct and the integrity check
still means something. Justify the choice in one line.

## Context

- `tools/make-working-copy.ps1` is on `main`. Task 007 recently hardened it: it now refuses a
  destination that is not empty, not a StarCraft install, and not under a known scratch root,
  and its `Test-KeyBinaries` reports every failure before throwing once. **Do not regress
  either of those.**
- The normal reset path — `tools/make-working-copy.ps1 -Force` against `C:\sc-work\1161-base` —
  is documented and frequently used. It must keep working. A guard that breaks the everyday
  path is worse than the bug it fixes.
- `tools/README-test-map.md` currently tells the reader that a reset purges generated maps.
  If you change that, update the doc.
- Beware the PowerShell error/exit-code trap that has now bitten this repo three times:
  `Write-Error` under `$ErrorActionPreference = 'Stop'` is terminating, and a stale
  `$LASTEXITCODE` from a native command whose non-zero result is expected will fail a step or a
  CI job. `robocopy` is exactly such a command — exit codes 0-7 are success. The existing script
  handles that correctly; keep it correct.

## Hard rules

1. **Never modify or read from `C:\sc-install\Starcraft`.** It is the user's pristine install.
2. Do not weaken the integrity verification, and do not regress task 007's destination guard.
3. Commit no game content — no `.scm`/`.scx`/`.rep`/`.spc`, no binaries. Test with fixtures you
   create and delete.
4. Do not launch the game. The user is at the keyboard and another task may be mid-session.
5. Do not merge your own PR.

## Acceptance criteria

1. A reset with the default flags **preserves** a player profile, a replay, and a generated test
   map — demonstrated by creating all three, resetting, and showing they survive.
2. The explicit destructive switch still produces a true mirror — demonstrated the same way,
   showing they are removed when asked for.
3. The purge list is printed plainly before deletion. Show the output.
4. Integrity verification still runs and still means something: key-binary hashes verified,
   file-count/size comparison still sane with preserved extras present. State how you handled
   the count comparison.
5. The everyday path `tools/make-working-copy.ps1 -Force` against `C:\sc-work\1161-base` still
   resets normally and still passes hash verification — demonstrated, not assumed.
6. Task 007's destination guard still refuses an unsafe destination — re-verify it, do not
   assume your change left it intact.
7. Docs updated where they describe the old purge behaviour. CI green. PR opened, link in
   Status.pr.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/010-working-copy-preserve.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
