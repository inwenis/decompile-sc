# Task 065 — Measure cnc-ddraw as the presentation path that does not crop

## Status

agent: 065
model: sonnet
pr: -

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task065 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task065-cnc-ddraw-presentation.
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

- Your inbox: `C:/git/decompile-sc/work/messages/065/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 065 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

**Get more than 640 columns onto the monitor, in a window, without touching the
user's display settings.** `WMode.dll` — a third-party shim this project did not
write — presents columns 0..639 at 1:1 and throws the rest away. That crop is
the last thing between the user and a wider view. Measure whether **cnc-ddraw**
replaces it. A costed, measured NO is a good outcome; a guessed YES is not.

## Context

- **This is the user's stated goal, in their own words (2026-08-13T09:18Z):**
  *"i want to be able to play and see more of the map - that's the goal."*
  You are the half that gets pixels onto the screen. **Task 064 (running in
  parallel) is the half that makes those pixels contain map** — at stage 1 the
  right 160 columns are blank. Neither half is worth anything alone.
  **You do not need 064 to finish.** A presentation path that shows 800 columns
  of which 160 are black is exactly the right intermediate result, and it proves
  your half independently. Do not wait for them; do not do their work.
- **Read first, in this order:**
  - `work/reports/063-widescreen-presentation.md` §3 — the presentation bill.
    **cnc-ddraw is 063's own top recommendation and it scoped this as one task.**
  - `research/renderer-viewport.md` §13.4, then §12.6 (the WMode crop, measured
    in two arms at 800x480 and 800x600 — identical HUD pixels rule out scaling).
  - `tools/plugin/probe-widescreen-present.ps1` — **it already returns a
    CROP/SCALE/FOLLOW verdict.** That is your instrument. Do not write another.
- **What is known and is not yours to re-measure:**
  - **cnc-ddraw** is MIT, source-available, a ddraw re-implementation with
    StarCraft on its supported list, and it presents the full requested surface
    by architecture. That last clause is the reason to try it and is exactly
    what your measurement must confirm rather than assume.
  - The existing `-Windowed` mechanism is the drop-in point.
  - **This adapter has no 800x480 mode** (measured: 132 mode entries, 21
    resolutions; 800x600 and 640x480 exist). So true fullscreen at the feature
    geometry is impossible on this machine — which is why the windowed route is
    the one that matters.
  - The `ddraw.dll` vector throws a DirectDraw Error **in the stock arm too** —
    broken on this machine independently of widescreen, and not evidence of
    anything.
- **Third-party binary: get this right.** Prefer building from source; if you
  take a release, record the version, the source URL and a hash. The DLL is a
  game-adjacent binary — **it does NOT go in the repo** (hard rule 1). It lands
  at an ignored path, and the repo gets the fetch/build script plus the
  provenance note.
- **Hard rules that bind this task:** `StarCraft.exe` on disk stays
  byte-identical; everything behind one off-by-default flag; **never write the
  user's display settings, desktop layout, or registry**; offline/single-player
  only. Run off-screen (task 043, `sc-desktop.ps1`) — the user is at this
  machine. Note that a presentation change is one of the few things that may not
  be fully measurable off-screen; if you hit that wall, **say so and ask** rather
  than quietly running on the user's desktop.
- **If cnc-ddraw returns CROP**, stop and cost the alternatives rather than
  fixing it: 063 estimated a ddraw shim of our own at 4–8 tasks (bounded by
  `storm.dll` importing nothing from ddraw — `pe-anatomy.md`) and a plugin-side
  presenter hooking the one present blit (`FUN_0041D420`) at 2–4 tasks, with
  palette capture as the open question. **Costing is a deliverable.**
- **This is a hobby project.** One route measured properly beats three surveyed.

## Steps (suggested)

1. Read 063 §3 and `probe-widescreen-present.ps1` before downloading anything.
2. Reproduce the WMode CROP verdict first — that is your positive control and it
   is what makes a later non-CROP verdict mean something.
3. Then swap in cnc-ddraw and run the same probe unchanged.

## Acceptance criteria

1. **A CROP/SCALE/FOLLOW verdict for cnc-ddraw from
   `probe-widescreen-present.ps1`**, with the WMode control verdict shown first
   in the same run.
2. A screenshot of the window, `pr-image`'d into the PR. This is a visual change
   and the picture is the deliverable — a verdict string is not.
3. Provenance for the binary: version, source, hash, and the fetch/build script
   in the repo. **The DLL itself is not committed.**
4. If NO: the costed comparison of the remaining routes, using 063's estimates as
   the starting point and correcting them where you learned better.
5. `StarCraft.exe` byte-identical; the user's display settings, desktop layout
   and registry untouched; flag off by default.
6. `scripts/run-ci-local.ps1` PASS; PR opened with the link in Status.pr. Cloud
   CI is down on billing — note it in the body. **PRs may stack and need not be
   merged immediately** (standing user instruction) — say what you branched from.

## Machine

Task 061 is on the machine and has priority (a user-reported bug); task 064 also
needs it. **Message the conductor before your first launch.** The launch lock
serialises one launch, not a chain (issue #60).

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/065-cnc-ddraw-presentation.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
