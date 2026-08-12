# Task 048 — The unit-row paging indicator is head-spliced and overlays repainting buttons on purpose

## Status

agent: 048
model: opus
pr: -

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task048 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task048-hudrow-indicator-placement.
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

- Your inbox: `C:/git/decompile-sc/work/messages/048/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 048 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

The HUD row's page indicator (`"36 units  13-24  (2/3)"`) is drawn somewhere a
player can read it, or it is not drawn at all. Today it is deliberately placed
ON TOP of the first buttons of the 12-icon row — the same defect the user
reported for the group production line, which task 039 fixed by moving that
line into the empty band below the row. Same module family, same mistake, and
this one is still shipping.

## Context

- **This is the LATENT twin of the bug the user actually reported.** Their words
  (2026-08-11): *"there was some text printed in the spot where the 12 icons
  are saying sth about a queue but it was behind the buildings icons so couldn't
  rly tell"*. Task 039 measured that line at box top **9** — inside the icon
  row, over the wireframes — and moved it to top **79**, one pixel below the
  row's lowest button edge at 78. PR #55, merged as `25e4c62`. The user has NOT
  complained about the HUD row indicator, because it only appears once a
  selection exceeds 12 units and pages.
- **The exact code.** `tools/plugin/src/sc_hudrow.cpp`, `EnsureIndicator()`
  (~line 493). The bounds it writes:

      ib[0] = b[0] + 2;                  // left
      ib[1] = b[1] + 1;                  // top   <-- ON the first button
      ib[2] = b[0] + 150;                // right
      ib[3] = b[1] + 1 + SC_QIND_BOX_H;  // bottom

  where `b` is the first button's bounds.
- **Read the comment above it before changing anything — the overlap is
  deliberate and it is paying for something real:**

  > It overlays the TOP EDGE of the first buttons on purpose: those rects
  > repaint whenever the buttons redraw, so leaving paged mode cannot strand
  > indicator pixels on the dialog surface.

  So the cost of moving the box into empty space is that nothing else repaints
  there, and stale indicator pixels can survive after paging ends. **That is a
  solved problem now** — task 039 hit exactly this for the group line and its
  answer is in `sc_queueind.cpp` on main. Read what it does before inventing a
  second mechanism.
- **`ib[3]` is load-bearing, not cosmetic** (comment at ~line 521): the engine's
  string draw refuses entirely when `top + fontHeight > clip.bottom`, and the
  clip box is the control's own bounds. A nine-pixel-tall box is how task 033
  shipped an indicator that was spliced, written, logged, asserted — and never
  drawn. `research/status-pane-text.md` § 3.
- **The oracle rule is absolute here** (AGENTS.md § "Assert the ENGINE'S OWN
  RESULT" and its task 033 subsection): asking the module what it wrote into its
  own buffer is NOT a read-back. Count non-background bytes (`ink`) the engine
  left in the dialog's 8-bit surface inside the control's bounds, with a
  known-drawn control as the positive control so `ink = 0` cannot be confused
  with a blind probe. Task 039's `test-group-production` measures the same thing
  as a DIFFERENCE — copy that shape.
- Related and worth reading, not necessarily fixing here: issue **#44** (a
  building group larger than 12 has never been exercised against the HUD row) —
  that is the selection size which makes this indicator appear at all, so the
  fixture you build may close it.
- `test-hud-row.ps1` is the suite. **It currently forces a visible window**
  (line ~237 calls `Send-ScDropdownPick` directly). Task **050** is in flight
  routing exactly that through `Set-ScGameType` so it runs off-screen. Check
  whether 050 has landed before you plan any run; if it has not, coordinate with
  the conductor rather than reaching for `-Visible`.

## Steps (suggested)

1. Get a selection past 12 units and CAPTURE THE CURRENT STATE first — a frame
   showing where the indicator lands today, with its measured box and ink. The
   before-picture is what makes the after-picture mean something.
2. Decide where it belongs given the row's geometry, and say what repaints that
   region when the indicator goes away.
3. Then move it, and prove it with a frame plus an ink measurement, not a log line.

## Acceptance criteria

1. Before/after frames of a >12-unit selection showing the indicator's position,
   on the gitignored diagnostic path. **Do NOT `pr-image` them** — a game frame
   reproduces game artwork and hard rule 1 wins. Name the exact paths in the PR
   body and describe what they show; the conductor opens them, and that human
   look is the gate.
2. The measured box coordinates before and after, and the row's own button
   rects, so "outside the row" is a number rather than an opinion.
3. Ink measured inside the indicator's bounds from the ENGINE'S surface, with a
   positive control, in both arms.
4. Leaving paged mode leaves no stranded indicator pixels — demonstrated, since
   that is precisely what the current placement buys and what a move puts at
   risk.
5. If the honest answer turns out to be "draw nothing rather than overlap", that
   is an acceptable outcome — say so plainly with the evidence, do not ship a
   half-move.
6. `scripts/run-ci-local.ps1` PASS; PR opened with its link in Status.pr. GitHub
   Actions is down on a billing error — the local receipt is the gate, note it
   in the body.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/048-hudrow-indicator-placement.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
