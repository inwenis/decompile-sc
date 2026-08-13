# Task 064 — Make the engine draw the playfield 800 columns wide

## Status

agent: 064
model: opus
pr: -

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task064 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task064-stage2-playfield-geometry.
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

- Your inbox: `C:/git/decompile-sc/work/messages/064/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 064 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

**Make the engine draw MAP into the right 160 columns.** At stage 1 the composed
framebuffer is already 800 wide — and the right 160 columns are all index 0,
blank, because the playfield renderer still thinks the world is 640 wide. This
task is stage 2: playfield geometry. Done means a captured 800-wide frame whose
right band contains terrain, sprites and fog that continue the left 640 — more
map, not more black.

## Context

- **This is the user's stated goal, in their own words (2026-08-13T09:18Z):**
  *"i want to be able to play and see more of the map - that's the goal."*
  Stage 2 is the half that produces the extra map. Task 065 (running in
  parallel) is the half that gets it onto the monitor. **Neither is worth
  anything alone** — coordinate through the conductor, do not merge into each
  other's lane.
- **Task 063 just removed the blocker that stopped 034, and you must read its
  work before anything else:**
  - `work/reports/063-widescreen-presentation.md` — the summary and run ledger;
  - `research/renderer-viewport.md` **§13** (the new section), plus the **§2
    correction** and the §12.10 note.
- **You have an instrument now. Use it; do not build another.**
  1. plugin `FRAMEDUMP` — per-marker copy of the screen Bitmap's buffer
     (`0x006CEFF0`) to `fd-<marker>.bin`, observe-safe, off by default, and it
     re-reads until two consecutive reads are byte-equal so a torn copy is
     impossible to miss;
  2. `tools/plugin/frame-capture.py` — `check` (validates a dump against the
     presented window), `diff` (the `wide_rows` row-span discriminator on raw
     indices), `band` (histogram a region), `render` (dump → PNG);
  3. `tools/plugin/probe-framebuffer-capture.ps1` — two launches under one lock,
     stock-observe positive control then stage 1, cross-arm diff at the end.
  **Run the positive control first, every time.** 063's numbers to beat:
  playfield consistency 0.98909 stock / 0.98910 stage 1, both dumps stable at
  `reads=2`, right band 76800/76800 index 0, cross-arm `wide_rows=0`.
- **`wide_rows` is your success metric and it is already wired.** Today it reads
  0 — stage 1 changes no pixel of map. **A stage-2 attempt that works makes
  `wide_rows` go positive**, and the right band stops being 76800/76800 index 0.
  That is a number, not an opinion, and it is the first thing to report.
- **What 034 found, which is NOT yours to re-derive.** Stage 0 (display mode) and
  stage 1 (framebuffer pitch) pass. Stage 2 **fails and does not decompose**:
  §12.9, 153 sites, bisect established it is structural rather than one bad
  site. **Read 034's account before forming a theory** — it is trustworthy
  precisely because it honoured its stop-line, and re-running its bisect is
  wasted days.
- **Where 034 was working blind and you are not.** Every frame 034 ever captured
  came through the presented window, so it could not tell a partially-working
  stage 2 from a completely broken one — the crop hid both identically. You can
  now see the actual composed output. **A hypothesis 034 had to reject as
  untestable may be cheap to test now.** Start by asking which of its dead ends
  died of the instrument rather than of the engine.
- **Constraints, all hard rules:** `StarCraft.exe` on disk stays byte-identical
  (runtime patches only); everything behind one off-by-default flag; never write
  the user's display settings, desktop layout, or registry. All runs off-screen
  (task 043, `sc-desktop.ps1`) — the user is at this machine.
- **This is a hobby project.** A stage 2 that works for the playfield and leaves
  the minimap or the fog seam wrong is a good result worth shipping behind the
  flag. Say what is wrong; do not withhold a working half.

## Steps (suggested)

1. Read 063's report and §13, then 034's §12.9. Then run
   `probe-framebuffer-capture.ps1` once, unchanged, to see the instrument work
   and to own its numbers yourself.
2. List 034's dead ends and mark which were "could not observe the result".
   Those are your candidates.
3. Attempt, capture, `diff`. `wide_rows` positive or it did not work.

## Acceptance criteria

1. **A captured 800-wide in-game frame whose right 160 columns contain map**,
   with `wide_rows` > 0 and the stock positive control shown passing in the same
   run. A rendered PNG in the PR (`pr-image`) — this is a visual change and the
   picture is the deliverable.
2. If it does not work: exactly which sites were changed, what the frame showed,
   and which of 034's structural claims survived contact — at 034's standard.
3. `StarCraft.exe` byte-identical; nothing the user sees changes; flag off by
   default.
4. `scripts/run-ci-local.ps1` PASS; PR opened with the link in Status.pr. Cloud
   CI is down on billing — note it in the body. **PRs may stack and need not be
   merged immediately** (standing user instruction) — say what you branched from.

## Stop-line

**Same rule 034 was given and honoured, and it is why its account is worth
reading: three honest attempts, then report.** Do not grind. A measured "stage 2
resists these three specific changes, here is the frame each produced" is a real
deliverable and the instrument makes it a cheap one. Report early rather than
late — the conductor would rather cut a follow-up than have you spend a day
inside a structural problem alone.

## Machine

Task 061 is on the machine and has priority (a user-reported bug); task 065 also
needs it. **Message the conductor before your first launch.** The launch lock
serialises one launch, not a chain (issue #60).

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/064-stage2-playfield-geometry.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
