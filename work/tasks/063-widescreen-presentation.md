# Task 063 — See more of the map: a presentation path that does not touch the user screen

## Status

agent: 063
model: fable
pr: -

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task063 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task063-widescreen-presentation.
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

- Your inbox: `C:/git/decompile-sc/work/messages/063/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 063 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

Two things, and the first unblocks everything else:

1. **A way to SEE the engine's composed frame at its full width, for testing**,
   without presenting it and without touching the user's display settings. Until
   this exists, nobody can tell a fixed stage 2 from a broken one.
2. **A presentation path that puts more than 640 columns on the user's monitor
   while they play**, without switching their desktop mode.

Answer (1) first and completely. (2) may turn out to be a costing exercise
rather than an implementation — say so honestly if it does.

## Context

- **This is the user's stated goal, in their own words (2026-08-13T09:18Z):**
  *"i want to be able to play and see more of the map - that's the goal - that is
  what you're going for. if need be investigate and implement sth that let's you
  test it without messing with my screen setting."* Everything else on the board
  is secondary to this.
- **READ `research/renderer-viewport.md` COVER TO COVER FIRST**, especially
  §12.6, §12.9, §12.10 and §12.12. Task 032 mapped the renderer; task 034
  executed stages 0–2 and measured where it stops. Do not re-derive any of it.
- **What is already established, and is not yours to redo:**
  - stage 0 (display mode) and stage 1 (framebuffer pitch) **pass**; the engine
    composes an 800-wide frame, descriptor and layer rects confirm it;
  - stage 2 (playfield geometry) **fails** and, per §12.9, **does not decompose** —
    153 sites, bisect established it is structural, not a bad site;
  - **`WMode.dll` presents columns 0..639 at 1:1 and discards the rest** (§12.6),
    measured in two arms at 800x480 and 800x600. Not scaling — identical HUD
    pixels rule that out.
  - the `ddraw.dll` vector throws a DirectDraw Error **in the stock arm too**, so
    it is broken on this machine independently of widescreen and is not evidence.
- **THE INSIGHT THIS TASK EXISTS TO TEST, and it may be cheap:** task 034 judged
  itself blocked because *"every frame this task has ever captured shows only the
  left 640 columns"*. But those frames were captured **through the presented
  window**. The engine's own framebuffer is a flat 8-bit surface described at
  `0x006CEFF0`, and at stage 1 it is demonstrably 800 wide (`SMemAlloc`, 384000
  bytes, verified). **Reading that surface directly should show all 800 columns
  regardless of what the window presents.** This repo already reads engine
  surfaces this way — `ScQueueIndCopyRect` / the `boxDiff` oracle read the
  dialog's own 8-bit surface, and tasks 039/048 built their entire verification
  on it. If that generalises to the main framebuffer, stage 2 becomes developable
  today with zero user impact, and 034's blocker was a property of its
  instrument rather than of the engine.
  **Test this before anything else. If it works, say so loudly — it changes the
  cost of the whole feature.**
- **For (2), the routes and what is known:**
  1. **True fullscreen, no helper** — the only route 034 could name. Switches the
     user's 3840x2160 desktop to a small mode and rearranges their icons.
     **Hard rule 5: do NOT run this unattended, on the user's desktop, ever.**
     If you want it measured, the invisible desktop (task 043, `sc-desktop.ps1`)
     is a genuinely different question — a `CreateDesktop` object is not the
     user's desktop — but whether a fullscreen mode switch is per-desktop or
     per-adapter is **unknown and must be measured, not assumed**. Measure it
     there first, where the blast radius is a desktop nobody is looking at.
  2. **A windowed helper that does not crop.** `WMode.dll` is a third-party shim
     this project did not write. Writing our own minimal `ddraw` presentation
     shim, or finding a build that honours the mode it is given, is real work but
     it is the only route that ends with the user playing wider WITHOUT giving up
     their desktop. Nobody has costed it. Costing it properly IS a deliverable.
- **Hard rules that bind this task specifically:** `StarCraft.exe` on disk stays
  byte-identical (runtime patches only, as every feature here does); everything
  behind one off-by-default flag; never write the user's display settings,
  desktop layout, or registry.
- **Stop-line.** Task 034 was given "two failed fix attempts, then report" and
  honoured it, which is why its account is trustworthy. **Same rule here**: if
  (1) does not work after two honest attempts, report that and move to costing
  (2). Do not grind on stage 2 — stage 2 is NOT this task.

## Steps (suggested)

1. Read the research doc. Then read `sc_queueind.cpp`'s surface reader and
   `probe-widescreen-present.ps1`.
2. Build the framebuffer capture and prove it on a STOCK 640-wide game first —
   if it cannot reproduce a known-good 640 frame, it cannot be trusted at 800.
   That is your positive control and it is not optional.
3. Then capture at stage 1 (which is known-good) and check you see 800 columns of
   sensible picture. That single result is the task's headline either way.
4. Only then look at (2), and prefer costing over building.

## Acceptance criteria

1. A stated, measured answer to: **can we see the full composed frame without
   presenting it?** With the stock-640 positive control shown first.
2. If yes: a captured 800-wide frame from a stage-1 build, and a plain statement
   that stage 2 is now developable without user impact.
3. If no: exactly where it fails and why, at the same standard as 034's account.
4. For (2): a costed comparison of the routes, including whether a fullscreen
   mode switch on an INVISIBLE desktop leaves the user's real desktop untouched —
   measured on the invisible desktop, never on theirs.
5. Nothing in this task changes what the user sees when they play, and
   `StarCraft.exe` stays byte-identical.
6. `scripts/run-ci-local.ps1` PASS; PR opened with the link in Status.pr. Cloud
   CI is down on billing — note it in the body. **The user has said PRs may stack
   and need not be merged immediately**, so do not block on a merge; branch from
   whatever you need and say what you branched from.

## Machine

Tasks 061 and 062 are also using it and 061 has priority (a user-reported bug).
**Message the conductor before your first launch.** The launch lock serialises
one launch, not a chain (issue #60).

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/063-widescreen-presentation.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
