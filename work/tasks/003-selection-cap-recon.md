# Task 003 — Recon the 12-unit selection cap

## Status

agent: 003
model: opus
pr: https://github.com/inwenis/decompile-sc/pull/2

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

## ROUND 2 — review findings to fix (added by conductor 2026-08-07)

An adversarial citation verifier cloned all five repos at your pinned commits and checked
every claim line by line. Result: **zero fabricated citations.** All 41 distinct addresses
trace to a named public source at the exact `file:line` you cite, all 5 commit hashes are
real and are the actual repo HEADs, and both community quotes are verbatim. Your evidence
discipline is genuinely good. Verdict was **yes-with-fixes**.

You were spawned fresh into your existing worktree `C:/git/decompile-sc-task003`, branch
`task003-selection-cap-recon`. Your PR #2 already exists — do NOT start over, do NOT open a
second PR. Fix the items below on that branch and push.

**HIGH 1 — direct self-contradiction on replay playback.** §6.2 says "our replays will not
play back in a vanilla client **regardless**". §7 #1's verification step says "Save a replay,
confirm it plays back in the vanilla client (it should — every emitted command is
vanilla-shaped)." Both cannot be true. #1 is the correct one for the fan-out design; §6.2's
"regardless" is really scoped to the cap-raise designs but reads as universal. Fix: scope
§6.2 explicitly to candidates #2/#3 and state that #1 stays replay-compatible.

**MEDIUM 2 — "four arrays" vs five, repeated.** §1.1, §2.3 and §3 row 1 all say **four**
fixed-size global arrays. §2.2, §7 #2 and §8 q1 all enumerate **five** 12-slot arrays
(`0x00597208`, `0x0059724C`, `0x006284B8`, `0x006284E8`, `0x0057FE60`). §2.3's adjacency
bullets silently drop `client_selection_group2` (`0x0059724C`). The relocation-effort estimate
that ranks candidate #2 rests on this count. Fix: say five everywhere, and add a `0x0059724C`
adjacency bullet.

**MEDIUM 3 — `clientSelectionGroupEnd` is misread, making part of your adjacency argument
circular.** This is the most important fix. §2.2 presents `0x00597238` as a global holding an
"end pointer". GPTP's macro is `#define SCBW_DATA(type,name,offset) type const name =
(type)offset;` — so `clientSelectionGroupEnd` is a **compile-time constant sentinel** that
GPTP produced by adding 12×4 to `0x00597208`. It is not a datum living at that address. So
when §2.3 and §7 candidate 5 argue "`0x00597208 + 0x30` is exactly `clientSelectionGroupEnd`,
therefore the neighbour is packed", that is circular — you are citing your own arithmetic back
as independent evidence.

Your conclusion still stands, but the load-bearing evidence is `0x0059723C`
(`client_selection_changed`, teippi `offsets.h:323`), which leaves exactly **4 bytes — one
extra slot — of unidentified slack**. Fix: drop `clientSelectionGroupEnd` from the adjacency
argument, rest it on `0x0059723C`, and state plainly that the 4-byte gap is unidentified.
Your own §8 q3 already asks the right question about this. Note the
`0x006284B8 + 0x30 = 0x006284E8` bullet IS genuine two-source adjacency — keep that one.

**MEDIUM 4 — §5.5 breaks the repo's own evidence rule.** "Remastered / 1.18+ did not change
it. Blizzard's stated remaster goal was gameplay preservation" carries no citation and no
`[unverified]` tag, in a section otherwise scrupulous about both. Fix: cite a patch note or
Blizzard statement, or tag it `[unverified]`.

**MEDIUM 5 — wrong internal cross-reference.** §7 #2 says "Depends on #4 (binary analysis)
landing first." Your #4 is "Prototype in OpenBW first"; binary analysis is §8 / task 001. Fix
the reference.

**MEDIUM 6 — the headline negative is absence-of-evidence stated as a finding.** §5 opens
"Finding: no public project has raised the selection cap on 1.16.1." flat, with no account of
what was searched. The verifier ran its own independent search and also found no
counterexample, so it is probably true — but it is unfalsified, not verified. Your own
`prior-art.md` handles this correctly with "[searched multiple phrasings; absence not
proven]". Adopt that house phrasing and list the searches you ran. §1.2's hedged "Nobody
*appears* to have done it" is fine as-is.

**MEDIUM 7 — candidate #1 is never costed against the buffer limits you yourself establish.**
This matters because #1 is the first milestone we intend to build. You note fan-out costs
"N/12 commands" but never cross that with §6.2's single-byte (255) per-frame command block or
§4.3's 512-byte `TurnBuffer`. A 100-unit intent is ~9 Select+order pairs in one frame, roughly
250+ bytes from one player — right at the replay block ceiling. Also: each `Select`
**replaces** `playersSelections[player]`, so restoring the visible selection costs an extra
command, making it N/12 **+1**. Fix: add a sizing paragraph to #1 and a "chunk across frames
if needed" note.

**LOW 8 — `0x006284B8` has no entry in §2.2's Roles list**, despite being the source of the
HUD copy (§4.5) and the array the order iterator walks (§4.4). This weakens candidate #3,
which claims blast radius "input + HUD only. Sim untouched" — but the HUD's source array sits
at `0x006284B8`, adjacent to `playersSelections`, on the sim side, and would be overwritten
every frame by the 12-iteration copy at `updateSelectedUnitData.cpp:24-25`. Fix: add the role,
and correct #3's blast-radius claim.

**LOW 9 — "deliberately" overstates neivv.** The verified quote says only that it "hasn't been
an issue for the stuff I've been doing" — he did not need it, rather than chose against it.
Change "deliberately left this one alone" to "did not attempt it, by his own statement".
§1.2's "explicitly leaves selection at 12" is accurate; keep that.

**LOW 10 — wrong count in §8 q10.** "save.cpp has 19 selection hits" — actual is 16 matching
lines / 22 occurrences. Your conclusion (selection is serialised into saves) is right and
better supported by citing `save.cpp:1046-1057` (writes `Limits::Selection *
Limits::ActivePlayers` pointers) and `:1916-1919` (reads them back). Cite those instead of a
grep count.

**LOW 11 — unrecorded source disagreement on `0x0059723D`.** You give shape `u8` citing BWAPI,
GPTP and teippi, but teippi types it `offset<uint32_t>` (`offsets.h:322`). Same class of
disagreement as your §8 q5, which you correctly record. Note it or drop the teippi citation
from that row.

**LOW 12 — §0 says "Four public code bases were cloned" above a five-row table** (screp).

**LOW 13 — §2.2 role 1 cites a read as a write.** `CMDRECV_Selection.cpp:484` is a read in the
dedup loop; the third write is `:238`. Use `:238, :312, :393`.

**LOW 14 — §4.3 over-reaches on `SelectRemove` (0x0B).** BWAPI defines `Select` (0x09) and
`SelectAdd` (0x0A) only — there is no `SelectRemove`/`ShiftDeselect` class in that repo. The
0x0B row rests on screp alone (which does confirm the shape). Attribute it to screp explicitly
rather than to "BWAPI constructs these packets itself, so this is authoritative".

**LOW 15 — §2.4 calls GPTP's `SC_memcpy_0` a "memmove".** Overlapping-copy semantics matter
here; use the source's own name.

**LOW 16 — same command, two sizes, unexplained.** §4.3 says a 24-unit select is 50 bytes;
§6.2 says 51 (adding the replay playerID byte). Both are right; say why they differ.

**LOW 17 — §6.1's "the game's sync check kills it" carries no citation.** The receiver-drop
half is well-evidenced (GPTP `:451`); the sync-kill mechanism is asserted. teippi
`commands.cpp:307` (`commands::Sync`) is available as at least partial evidence — cite it or
tag the mechanism `[unverified]`.

**VERY LOW 18 — §9 index lists files never cited in the body**: BWAPI `GameInternals.cpp`,
teippi `constants/image.h`, OpenBW `game_types.h`.

Note on merging: the repo now has `.github/workflows/ci.yml` on main, but GitHub Actions is
blocked at the ACCOUNT level (zero runs repo-wide, likely unverified email or a $0 spending
limit) and is escalated to the user. So your PR cannot go green yet — that is not your
problem and not a reason to delay. Push your fixes and report.

Do NOT merge your own PR. Message the conductor when pushed.

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
