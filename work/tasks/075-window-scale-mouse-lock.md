# Task 075 — Bring back windowed 2x scaling and mouse lock (issue #114)

## Status

agent: 075
model: sonnet
pr: -

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task075 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task075-window-scale-mouse-lock.
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

- Your inbox: `C:/git/decompile-sc/work/messages/075/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 075 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

GitHub issue #114 (read it first: `gh issue view 114`). The user's normal windowed play
used to offer two things under the old WMode presenter: scale the window up 2x, and lock
the mouse inside the window. Both disappeared when presentation moved to cnc-ddraw
(task 065 line). When this task is done, a game launched from the user's own deployed
shortcut(s) can present at 2x window scale AND confine the mouse to the game window —
and the PR says exactly how the user turns each on/off.

## Context

- User's verbatim ask (2026-08-14): "it used to run in a window that would allow me to
  control the window behaviour like scale it up twice and lock the mouse within the
  window. The last time I played this was gone and I would like it to be back."
- The presenter is cnc-ddraw: its DLL is pinned by hash in `tools/deploy.ps1`
  (`CNC_DDRAW_DLL_SHA256`, staged as `ddraw.dll` next to the game), configured by
  `cnc-ddraw.ini` (deployed to `plugin\cnc-ddraw.ini`; the deploy throws if it is
  missing). Find the ini's source of truth in this repo and change it there, not in the
  deploy dir by hand.
- cnc-ddraw upstream supports windowed scaling and mouse options, but KEY NAMES DIFFER
  BY VERSION. Identify the pinned build's version first, then read that version's
  documented ini keys (upstream README/wiki via WebFetch). Do not guess keys: an
  unrecognized key silently does nothing, which is the vacuous-assertion disease in
  config form.
- AGENTS.md § "Glue-screen input is ACTIVATION-GATED" (task 070): cnc-ddraw flags
  `hook=1` and `noactivateapp=true` were tried for a different problem, moved nothing,
  and were REVERTED. Don't re-flip them casually; if you need them, measure.
- Scope guard: the offscreen test harness must not change behaviour. Whatever you
  change must be either scoped to the user-facing launcher path or proven harmless to
  suites (run one representative suite offscreen before opening the PR).
- Hard rule 5: no registry / live-user-state writes. The deploy dir is a user-chosen
  target — but you deliver changes via the repo + `tools/deploy.ps1`, and the conductor
  deploys after merge.
- Widescreen interaction: the user also plays a wide shortcut (issue #113, right band
  currently defective). If 2x scale and wide-800 conflict (monitor too small, cnc-ddraw
  limitation), say so plainly in the PR rather than silently supporting only one.
- Game frames NEVER go through `pr-image` (hard rule 1 overrides the generic line in
  Reporting below) — describe appearance, keep PNGs under `C:\sc-work\logs\075-frames\`.

## Steps (suggested)

1. Read issue #114, AGENTS.md (esp. task 070 activation section, foreground rules),
   `tools/deploy.ps1` cnc-ddraw staging, and the current cnc-ddraw.ini in the repo.
2. Establish the pinned cnc-ddraw version; get ITS ini reference from upstream.
3. Configure 2x windowed scale + mouse lock; test with a LIVE VISIBLE launch on the
   real desktop (this is user-facing UX; offscreen cannot verify a mouse clip the user
   feels). Read back the window rect (`GetWindowRect`) and cursor clip
   (`GetClipCursor`) from the running process — assert those, not the ini contents.
4. Verify the offscreen harness is unaffected (one suite run through
   `./tools/plugin/run-offscreen.ps1`).
5. PR with: keys changed and why, the user-facing toggle story, measured read-backs,
   frame paths for the human.

## Acceptance criteria

1. Live launch from the deployed-shortcut code path: window presents at 2x
   (window client rect read back ≈ 2x the game resolution), measured, not asserted
   from config.
2. Mouse confined to the game window during play (GetClipCursor read-back equals the
   window rect while the game has focus), and the PR documents how to toggle it.
3. One representative suite still passes offscreen, unchanged.
4. No registry writes, no game/ writes, no committed game art.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/075-window-scale-mouse-lock.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
