# Task 009 — Generate a single-player test map with many units

## Status

agent: 009
model: sonnet
pr: https://github.com/inwenis/decompile-sc/pull/8
merged: 2026-08-07

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task009 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task009-test-map-generator.
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

- Your inbox: `C:/git/decompile-sc/work/messages/009/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 009 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

A committed, parameterised generator that produces a **single-player StarCraft 1.16.1 test map
with many units already placed** for the human player, so the user can select a large group and
issue one order in a couple of seconds. This is the test fixture for the project's north star —
commanding more than 12 units at once — and it needs to exist before that feature can be
judged working.

User's request, verbatim (2026-08-07): *"can you also get a map with many units so i can quickly
test the commanding of more than 12 units"*.

## What "good" looks like

Loading the map should drop the player straight into a situation where a box-select grabs far
more than 12 units and there is somewhere obvious to order them to. Concretely:

- A configurable unit count, defaulting to something comfortably over the cap — 36 or 50
  Marines is ideal (small, fast, cheap to render, unambiguous to count on screen).
- Units clustered so a single drag-box catches all of them, on open terrain with room to move.
- Single player, no hostile pressure. Either no enemy at all or a passive one that will not
  interrupt the test. The user must be able to load, select, right-click and observe — nothing
  else competing for attention.
- Loads on **1.16.1 vanilla**, offline, with no mod or plugin required. The map must be usable
  as a plain baseline as well as with our plugin injected.

## Context

- `research/prior-art.md` surveys the file-format landscape, including CHK (the map format
  inside an `.scm`/`.scx` MPQ) and the Python/JS libraries that read and write it. **Read that
  section before choosing a library** — do not start by writing a CHK serialiser from scratch.
  Pin whatever you choose (version + source), consistent with how this repo pins Ghidra and the
  C++ toolchain.
- An `.scm`/`.scx` is an MPQ archive containing a `scenario.chk`. Placed units live in the CHK
  unit section. A minimal playable map also needs terrain, player/force setup and a start
  location — a map missing a start location will not load as single player.
- The install ships `StarEdit.exe`, the original editor. It is a GUI tool, so it is a poor fit
  for a scripted, reproducible generator — but it is a legitimate way to *sanity-check* a
  produced map if you want a second opinion on validity.
- Target directory for produced maps: `C:\sc-work\1161-base\Maps\` (the disposable working
  copy). Note `tools/make-working-copy.ps1 -Force` mirrors from the pristine install and will
  **purge** anything extra there, so treat generated maps as disposable and regenerate them
  rather than expecting them to survive a reset.

## Hard rules

1. **Never modify or read from `C:\sc-install\Starcraft`** beyond what already-committed tooling
   does. Work against the working copy.
2. **Commit the GENERATOR, never the map.** `.scm`/`.scx` are in `.gitignore` and the CI
   game-content guard will fail the build if one is tracked. The script is the deliverable; the
   map is disposable output. Do not commit extracted game assets either.
3. Offline, single-player only. Never Battle.net.
4. **Do not launch the game in this task** unless the conductor tells you the screen is free —
   the user is at the keyboard, and task 008 is separately negotiating a windowed-mode session.
   Validate structurally instead (see below). Coordinate, do not compete for the display.
5. Do not merge your own PR.

## Steps (suggested)

1. Read `research/prior-art.md` on map formats and parser/writer libraries. Choose one, pin it,
   add it to `requirements.txt` if it is a Python package.
2. Write `tools/make-test-map.ps1` (or a Python equivalent driven by a thin `.ps1`) taking at
   least: unit count, unit type, player, and output path — with sensible defaults so a bare
   invocation produces the standard fixture.
3. Generate the default map into the working copy's `Maps\` directory.
4. **Validate structurally, without launching the game**: parse the produced file back and
   assert the unit count, unit type, owner, start location and terrain dimensions are what you
   asked for. A map that parses correctly and contains N units of the right type owned by the
   right player is strong evidence before anyone loads it.
5. Document in `tools/README-test-map.md`: what it makes, how to run it, where the output goes,
   the fact that a working-copy reset purges it, and any known limitation.
6. Report to the conductor that the map is ready for in-game verification. **Task 008 will load
   it during its windowed session** so we spend one interruption of the user's screen rather
   than two. Do not run that test yourself unless told.

## Acceptance criteria

1. `tools/make-test-map.ps1` (plus any Python helper) is committed, parameterised, and produces
   a map from a single documented command with no hardcoded worktree paths.
2. The default invocation yields a single-player map with **more than 12** units — 36 or 50 —
   clustered for one drag-box selection, with a valid start location.
3. Structural validation is demonstrated in the PR: the produced file parsed back, with unit
   count, type, owner and start location asserted. State plainly that in-game loading is NOT
   yet verified and is delegated to task 008.
4. Library choice is pinned and justified in one line; nothing hand-rolled that an existing
   maintained library already does correctly.
5. No `.scm`/`.scx`/`.chk`, no game assets, and no binaries committed — `git status` checked
   before commit, CI green.
6. PR opened, link in Status.pr.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/009-test-map-generator.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
