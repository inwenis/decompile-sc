# Task 003 — Recon the 12-unit selection cap

## Status

agent: 003
model: opus
pr: -

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task003 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task003-selection-cap-recon.
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

- Your inbox: `C:/git/decompile-sc/work/messages/003/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 003 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

Produce `research/selection-cap.md`: a rigorous, evidence-cited recon of StarCraft 1.16.1's
**12-unit selection limit** — where selection state lives, every subsystem the number 12
touches, how the public modding/RE community has approached changing it, and a **ranked list
of candidate attack points** for our own mod, each with a stated risk and a way to test it.
This is a PURE RESEARCH task: no binary analysis, no patching, no Ghidra. Its output is the
map that the eventual implementation task follows.

## Context

- **This is the project's north star.** The user's end goal, verbatim (2026-08-06): "the end
  goal of this project is to make something useful like to allow selecting more than 12 units
  at one time." Target is classic **1.16.1** (installed at `C:\sc-install\Starcraft`, which
  you must NOT touch — you do not need it for this task at all).
- Agreed strategy: read decompiled C to understand, patch bytes for tiny changes, and build
  real features as an **injected DLL written in C/C++** hooking the game — the approach the
  serious StarCraft modding scene uses. Assess candidate attack points against that plan.
- `research/prior-art.md` already exists in this repo — READ IT FIRST. It surveys OpenBW,
  BWAPI, GPTP, samase, the modding-tool lineage, and file formats. Build on it; do not
  duplicate it. Cross-link instead.
- The selection limit is almost certainly **not one constant**. Expect it to be spread across
  at least: the selection array/structure itself, per-player selection state, the UI
  (portraits/wireframes and their layout), input handling (drag-select, control groups,
  double-click, shift-click), and the **command/order path** — which on 1.16.1 also means the
  network protocol, since commands carry selections. Enumerating those surfaces honestly is
  a primary deliverable; a "just change 12 to 24" answer is almost certainly wrong and will
  be treated as a failed task unless you can prove it.
- Rich public sources exist: BWAPI's `BW/` headers (selection and unit structures), GPTP
  plugin templates, samase / samase_scarf, OpenBW's reimplementation (its source is a
  readable model of the same logic), StarCraft modding wikis and forums, and control-group /
  selection documentation. OpenBW is especially valuable — a working reimplementation shows
  the *shape* of the logic without needing the binary.
- Note the ecosystem distinction: BWAPI is built for *reading* game state and issuing orders;
  a selection-cap change is a *client behavior* change. Be explicit about which prior tools
  actually modify behavior versus merely observe it.

## Evidence rules (hard)

1. Every structural claim cites its source — repo + file (and function/struct name), or a URL.
2. Anything you could not verify is marked **[unverified]** inline. An honest unverified note
   is valuable; an unmarked guess is poison and fails the task.
3. You may quote and cite publicly published struct layouts and documented offsets **with the
   source named**. Never invent, extrapolate, or "reason out" an address. If a number is not
   in a source you can point to, it does not go in the document as fact.
4. Distinguish clearly throughout: 1.16.1 vs later patches vs Remastered. Prior art that only
   applies to Remastered (or only pre-1.16) must be labelled as such — this is the single
   easiest way for this research to become misleading.

## Steps (suggested)

1. Read `research/prior-art.md` fully. Note what it already establishes so you extend rather
   than repeat it.
2. Research the selection data model: what holds the current selection, its capacity, how
   units are added/removed, per-player vs local-player state. Use OpenBW's implementation and
   BWAPI's headers as primary readable sources.
3. Enumerate every subsystem the cap touches. For each: what it does, why 12 matters there,
   and how hard it looks to change. Cover at minimum selection storage, UI/HUD rendering,
   input/drag-select/control groups, and the command/order + network path.
4. Research how others changed or attempted to change it — plugins, hacks, alternative
   clients, mod frameworks. Record what worked, what broke, and specifically what happened in
   multiplayer/replay contexts. If nobody appears to have done it on 1.16.1, say so plainly;
   that is a real and useful finding.
5. Identify the hard constraints — places where a larger selection would break a format or
   protocol that is not ours to change (network command encoding, replay format, UI space).
   These decide whether the mod must be single-player-only. Flag that answer explicitly; the
   user only needs offline/single-player, so a single-player-only path is perfectly acceptable
   and may be far simpler.
6. Produce the ranked candidate attack points: for each — what to change, expected blast
   radius, risk, how we would verify it in-game, and the confidence level with reasoning.
7. Close with a short "what we must learn from the binary next" section: the specific open
   questions only our own Ghidra analysis (task 001) can answer. That section becomes the
   next task's contract, so make it concrete.

## Acceptance criteria

1. `research/selection-cap.md` exists, cross-links `research/prior-art.md`, and every
   structural claim is either cited or marked **[unverified]**.
2. The subsystems the cap touches are enumerated with reasoning — not a single-constant answer
   unless proven with sources.
3. Prior attempts are surveyed, including an explicit statement if none are found, with
   multiplayer/replay implications called out.
4. A ranked candidate-attack-point list with risk, verification method, and confidence.
5. An explicit verdict on whether a raised cap can work in multiplayer, or is single-player
   only (single-player-only is an acceptable and expected outcome).
6. A concrete "open questions for binary analysis" section usable as the next task's contract.
7. No binaries touched, nothing game-derived committed. PR opened, link in Status.pr.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/003-selection-cap-recon.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
