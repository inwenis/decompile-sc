# Task 039 — The 5th production slot draws garbage, and the group queue text hides behind the icons

## Status

agent: 039
model: opus
pr: -

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task039 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task039-queue-indicator-corruption.
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

- Your inbox: `C:/git/decompile-sc/work/messages/039/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 039 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

The production queue indicator draws correctly, or it does not draw at all.
Right now it paints different garbage in different buildings, and in a
multi-building selection it writes text underneath the icon row. Both are
worse than showing nothing.

## Context

- **The user's exact words (2026-08-11T23:01Z), playing the current deploy:**
  - "when queuing more than 5 units to build in a single building something
    buggy happens with the 5th units placeholder:"
    - "for command center it becomes the number '2' and stays regardless of
      queue length"
    - "for one barrack it blacked out"
    - "for another barrack somehting blue flashing appeard"
  - "when i had a group of buildings selected there was some text printed in
    the spot where the 12 icons are saying sth about a queue but it was
    behind the buildings icons so couldn't rly tell"
- Three different renderings from three buildings, and one of them is a
  stuck literal "2", is the signature of drawing through a resource the
  building type indexes differently — a wrong sprite/palette/slot id, or a
  buffer the game reuses per card. It is unlikely to be three bugs.
- Source: `tools/plugin/src/sc_queueind.cpp/.h` (task 033,
  `work/tasks/033-queue-overflow-indicator.md`), with the icon strip in
  `sc_card.cpp` and the 12-icon row in `sc_hudrow.cpp`. The group-selection
  text overlap is a placement/ordering problem between the indicator and the
  row, so both files are in scope.
- Task 034's lesson applies directly (AGENTS.md § "An enumeration that
  scanned for a NAME is not exhaustive", and the nine-pixel text box it
  found): drawing code here has already fooled a passing test once.
- The user is not asking for a redesign. If a clean fix is not reachable,
  making the indicator draw nothing in the cases it cannot draw correctly is
  an acceptable outcome — say so plainly rather than shipping a half-fix.

## Steps (suggested)

1. Reproduce all three renderings from real games and capture frames:
   Command Center, and two different Barracks. The per-building difference
   is the whole clue — do not fix the first one and assume the rest follow.
2. Find the shared cause before writing a fix.
3. Then the group-selection overlap: decide where that text belongs when the
   icon row owns the space, and show it in a frame.

## Acceptance criteria

1. Before/after frames for all three reported cases, plus a frame of a
   multi-building selection where the queue text is legible (or deliberately
   absent). **Do NOT `pr-image` them** — a game frame reproduces game artwork
   and hard rule 1 wins (AGENTS.md § "Screenshots vs hard rule 1 (settled)").
   Keep them on the gitignored diagnostic path, name the exact paths in the
   PR body, and describe what they show. The conductor opens them during
   review — that human look IS the gate, because a read-back oracle asking
   the plugin what the plugin wrote is exactly what let this class of bug
   ship twice already.
2. The indicator's content is correct for a queue longer than 5 — it tracks
   the queue, it does not freeze at "2".
3. A test that fails on current main and passes with the fix, asserting what
   is on the screen (AGENTS.md § "Your DIAGNOSTICS are under the same rule as
   your assertions").
4. Local checks green; PR opened with its link in Status.pr.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/039-queue-indicator-corruption.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
