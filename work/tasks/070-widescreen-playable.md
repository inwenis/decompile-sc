# Task 070 — One switch that makes the game playable at 800 wide

## Status

agent: 070
model: opus
pr: -

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task070 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task070-widescreen-playable.
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

- Your inbox: `C:/git/decompile-sc/work/messages/070/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 070 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

**Every piece of widescreen is now on main, and none of them are joined up.**
Stage 1, stage 2, the fog fix and a non-cropping presentation path all exist as
separate flags and probe scripts. **Nobody has ever played the game wide.**

Make one switch that starts the user's game in a window showing 800 columns of
real, correctly-fogged map — and prove it is playable, not just capturable.

## Context

- **The user's words, and the whole reason the last five tasks existed**
  (2026-08-13T09:18Z): *"i want to be able to play and see more of the map -
  that's the goal - that is what you're going for."*
  **You are the task that finishes it.**
- **What is merged and yours to assemble, not to redo:**

  | piece | task | what it does |
  |---|---|---|
  | stage 0/1 | 032/034 | display mode + 800-wide framebuffer |
  | stage 2 | 064 (#99) | playfield geometry — 56 sites, `sc_screen_patches.h` |
  | fog | 068 (#104) | 39 more sites; fog covers all 800 columns |
  | presentation | 065 (#98) | cnc-ddraw presents 800 columns (FOLLOW, control-anchored) |

- **Read `research/renderer-viewport.md` §13-§16 first.** §16.4 carries 068's
  two runs; §15 carries 064's dossier **including a correction block** — 064's
  original fog identification was wrong and 068 fixed the record. Read the
  correction, not the original.
- **`tools/renderer_patch_sites.py` is the single table** (261 sites verified at
  068's merge). `probe-framebuffer-capture.ps1 -SuiteArgs @{Stage2=$true}` is
  the existing harness.
- **The last measured numbers, so you know what "still working" looks like:**
  stock playfield consistency ~0.989, `dense_rows=0` cross-arm against stock,
  right band 100% index 0 over unexplored map at origin (704,416), and the
  defect arm RED in the same run. **If your assembled build does not reproduce
  those, something in the join is wrong.**

### What "playable" means here, and it is more than a screenshot

**Every capture this project has ever taken was a frozen frame.** Nobody has
driven a game wide for minutes. Things that a still frame cannot show:

1. **Scrolling** — 068 exercised sub-tile alignment ONCE, at origin (848,416),
   `x%32=16`. That is one sample of a dimension with 32 values.
2. **The minimap and the HUD.** The console dialogs live in their own surfaces
   (§2 correction) and were never part of the widescreen work. **Do they sit in
   the right place at 800 wide, or are they anchored to 640?** Nobody knows. This
   is the most likely thing to be wrong and it is the first thing the user will
   see.
3. **Mouse coordinates.** Clicking at x=700 must select the unit at x=700.
   Input mapping was never tested past 640.
4. **Selection boxes, unit commands, building placement** at x > 640.
5. **Stability over time** — minutes, not frames.

**Report what you find honestly.** "The map is wide and the minimap is in the
wrong place" is a real, shippable result the user can decide about. Silently
discovering it and not saying so is not.

### The line you do not cross

- **Do NOT run this on the user's desktop or against their live install**
  (`C:\sc-deploy\starcraft-modded`). All work off-screen (task 043,
  `sc-desktop.ps1`), against a scratch deploy root — task 067 (#100) shows the
  shape.
- **The user must be present for the first real play.** That is the whole point
  of the deliverable and it is theirs to trigger. Your job is to make it one
  action and to have already proved everything you can prove without them.
- `StarCraft.exe` on disk byte-identical; flag off by default; never write their
  display settings, desktop layout, or registry.
- **Game frames NEVER go through `pr-image`** (hard rule 1). Paths travel.
- cnc-ddraw is a third-party DLL at an ignored path — `fetch-cnc-ddraw.ps1` is
  in the repo, the binary is not. Do not commit it.

### Known traps, all paid for today

- **Issue #103: `sc-launch.lock` leaks on a finished run** — three times today,
  both exit codes, and `Exit-ScLaunchLock: released` prints while the file
  survives. **Task 069 is fixing it right now.** If you find a stale lock:
  verify the owning pid is dead and no `StarCraft.exe` exists, then clear it
  **with that proof in hand** — and say so.
- **Issue #97: your worktree has no `.venv`** → map generation fails → the error
  **wrongly blames another worker**. Junction the main checkout's in first. Also
  expect ~20 red Pester tests until you do.
- **Issue #60**: the launch lock serialises one launch, not a chain.
- **Defect-era oracles** (AGENTS.md, written by 068 today): an assertion
  calibrated while a bug was live can encode the bug as its expectation. 064's
  `>= 0.30 holds MAP` check went red when the fog was FIXED. **If an existing
  assertion fails on your assembled build, ask whether it is testing for the
  defect before you "fix" your build.**

## Steps (suggested)

1. Assemble and reproduce 068's run-2 numbers first. That is your positive
   control and it tells you the join is sound before you drive anything.
2. Then drive a real game for minutes off-screen: scroll the full map, click at
   x>640, select, command, place a building, open the minimap.
3. Then write the one-action switch and the one-page card for the user.

## Acceptance criteria

1. **One documented action** that starts the deployed game in a window at 800
   wide with stage 2 + fog + cnc-ddraw, off by default.
2. **068's numbers reproduced** on the assembled build, in one run, with the
   stock control passing and the defect arm red.
3. **A driven session, not a frozen frame**: scrolling across the map including
   several sub-tile origins, a click at x>640 that selects what it aimed at, and
   a stated verdict on the minimap and HUD placement at 800 wide.
4. **An honest list of what is wrong or untested**, ranked by what the user would
   notice first.
5. A one-page card: what to click, what they should see, what is known-imperfect.
   Plain language, no source references — task 062's card is the model.
6. `StarCraft.exe` byte-identical; the user's install, desktop and registry
   untouched; nothing runs on their screen.
7. `scripts/run-ci-local.ps1` PASS; PR opened with the link in Status.pr. Cloud
   CI is down on billing — note it in the body.

## Stop-line

**If the HUD or input mapping turns out to be a subsystem of its own, stop and
report it** rather than absorbing it. That is a follow-up task, and 034/064/068
all produced their best work by honouring exactly this line. Three honest
attempts at any one blocker, then write it up.

## Machine

Task 069 is live but should not need the game. **Message the conductor before
your first launch.**

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/070-widescreen-playable.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
