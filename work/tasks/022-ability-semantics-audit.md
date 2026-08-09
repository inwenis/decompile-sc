# Task 022 — Verify ability fan-out semantics at >12; investigate sunken-vs-medic report

## Status

agent: 022
model: opus
pr: https://github.com/inwenis/decompile-sc/pull/22
merged: 2026-08-09

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task022 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task022-ability-semantics-audit.
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

- Your inbox: `C:/git/decompile-sc/work/messages/022/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 022 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

**Two questions from the user's play session, both answered with in-game evidence.**

1. **Do abilities really apply to ALL units when more than 12 are selected, including their
   per-unit costs?** Their example, verbatim (typos theirs): "if I apply steam to ferdinarines
   will all of them get steam and will all of them have HP decreased" — i.e. Stim Pack on a >12
   group of Marines/Firebats: does every unit get the stim effect, AND does every unit pay the HP
   cost? Stim is the sharpest test we have because it has a visible per-unit cost.
2. **Is the "sunken colony did not attack my medic" observation a bug we introduced?** Their words:
   "there was a moment where sunken didn't attack my medic and I'm not sure if it's a bug that we
   introduced or I just saw something wrong." Determine it. A clean "not ours, and here is why"
   is a perfectly good answer — so is finding a real bug.

This is an AUDIT task: the deliverable is evidence and a report, plus regression tests for whatever
you confirm. Only fix code if you find a real defect, and message me before doing so.

## Context

### Question 1 — ability semantics at >12

- `research/command-opcodes.md` is the map: the 19-opcode fan-out set, the LOOP/SINGLE/NONE
  handler classification, and §6 on per-unit costs. Task 015 established that the engine applies a
  command to EVERY unit in the receiving player's selection and that there is NO spell arbitration
  — twelve casters means twelve casts. This task tests that claim at 24+ for a cost-bearing ability.
- Stim (`0x36` in our table) is documented as costing the acting unit HP via the damage primitive
  `0x004797B0`, gated on `unit+0x08 > 0xa00`. So the assertion is two-sided: every unit gains the
  stim state AND every unit's HP drops. A unit too damaged to pay must be skipped by the ENGINE,
  not by us — if our fan-out changes who can and cannot stim, that is a finding.
- Energy-costed abilities are the harder case and worth one pass if cheap: a >12 group of casters
  told to cast — does each pay its own energy, and what happens to units without enough? State
  what you find; do not "fix" the engine's semantics.
- Build the fixture with `make_test_map.py` (`--unit-hp` lets you pre-damage units, which is how
  you test the "cannot afford the HP" branch deterministically). Marines are `0x00`; check the id
  table rather than trusting this line.

### Question 2 — the sunken/medic observation

- What we changed that could plausibly touch it: nothing in AI or targeting — our plugin hooks
  selection commit, command emission, the HUD row dispatcher, and draws circles. So the prior is
  strongly "not ours". Do not stop at the prior: test it.
- The cheap decisive experiment: reproduce the scenario with the plugin ACTIVE and with
  `-Mode observe` (fully stock), same map, same positions, and compare. If stock behaves the same,
  it is vanilla behaviour and the answer is "not ours" with evidence.
- Vanilla StarCraft has well-known targeting rules that could explain it — a medic is a
  non-attacking unit, and sunken colonies have specific acquisition behaviour. If the stock run
  reproduces it, say what the actual rule is, so the user learns something rather than just being
  told "not a bug".
- If the plugin run differs from stock, STOP and message me before going further.

## Hard rules

1. Never modify, write to, or launch `C:\sc-install\Starcraft`. Working copy only.
2. Offline, single-player only.
3. `StarCraft.exe` on disk stays byte-identical; tests assert it.
4. **Never write to live user state outside the repo and the working copy** — AGENTS.md rule 5.
   The game's settings under `HKCU:\SOFTWARE\Blizzard Entertainment\*` are OFF LIMITS (a worker
   zeroed the user's volumes there today; the user played silent for hours).
5. Commit no game content, no binaries, no logs, no generated maps.
6. Do not merge your own PR.

## Acceptance criteria

1. Question 1 answered with in-game per-unit evidence at >12: for a cost-bearing ability, every
   selected unit's effect state AND cost are read from in-process state and asserted — not
   inferred from the fact that a command went out.
2. The "cannot afford the cost" branch is exercised deterministically (pre-damaged units), and the
   report states whether skipping is done by the engine or influenced by us.
3. Question 2 answered with a plugin-vs-stock comparison on the same fixture, and — if it
   reproduces in stock — an explanation of the actual vanilla rule.
4. Findings written to `research/` with how each was observed; anything surprising called out
   rather than smoothed over.
5. Whatever you confirm becomes a regression test in the existing suites.
6. All five existing in-game suites still green; hooktest green; exe byte-identical; no stranded
   processes; CI green.
7. PR opened, link in Status.pr.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/022-ability-semantics-audit.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
