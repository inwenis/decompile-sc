# Task 068 — Fog must cover the full 800: kill the 25px seam and the 104px leak

## Status

agent: 068
model: opus
pr: https://github.com/inwenis/decompile-sc/pull/104
merged: 2026-08-13

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task068 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task068-fog-band-widescreen.
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

- Your inbox: `C:/git/decompile-sc/work/messages/068/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 068 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

**Fog of war must cover all 800 columns.** Stage 2 now draws the playfield 800
wide (task 064, PR #99, merged) — but the fog layer still thinks the screen is
640. Two defects, both measured:

1. **screen px 672..695 paint BLACK at every camera origin** — a 25-px dead
   stripe, fog cells 84-86 plus the last px of cell 83;
2. **screen px 696..799 never receive fog AT ALL** — 104 px of raw terrain shown
   regardless of what the player has explored.

Done means a captured 800-wide in-game frame where the fog boundary is
continuous across the full width and unexplored map is hidden out to x=799.

## Context

- **This is the last thing between the user and their stated goal**
  (2026-08-13T09:18Z): *"i want to be able to play and see more of the map."*
  The playfield half is merged and the presentation half is merged (cnc-ddraw,
  task 065, PR #98 — 800 columns reach the screen). **The fog is what stops it
  shipping as something the user would actually want to play.**
- **READ FIRST: `research/renderer-viewport.md` §15, especially §15.4** — task
  064's fog dossier, written for a cold reader. Then PR #99 and
  `work/reports/064-stage2-playfield-geometry.md`. **Do not re-derive any of it.**
- **The severity, stated the way 064 finally got it right:** the leak is not
  terrain-only. *"A mineral line or enemy base under those 104 px would be shown
  identically; this fixture just happens to hold none there."* An earlier,
  vivider claim (that the render showed unexplored minerals) was **checked
  against the map's own UNIT records and killed** — the pink was
  `frame-capture`'s magenta fallback for unmapped palette indices. Do not
  resurrect it.

### 064's head-residue handover — things in NO document but this one

1. **The fog update cursor `[0x6CDFE8]` is touched by exactly TWO functions**
   (byte-scan verified). `0x47E480` advances it with wrap into `[1..0x50]` or
   `[1..0x67]`, selected by flag `[0x58F440]`. The `0x47E8A0` band
   validates/loads it from a u16 table at `0x513BA0` indexed by something 064
   never identified. Private global; nothing else names it.
   **Architecture smell, and treat it as the working hypothesis:** this is the
   same shape as the terrain cache's steppers — a per-column update cursor over a
   ring. **Expect the fog analogue of the whole `0x49B8D0..0x49C8xx` band, not
   just a couple of clamp constants.**
2. **`[0x58F440]` has ~80 references across the UI band (`0x44C`-`0x4F8`)** — a
   pervasive mode flag. **Do NOT infer its meaning from the fog pair.** The
   `0x68 = 104` branch may serve a mode this fixture never entered.
3. **The boundary at screen cell 87 (=696 px) is DERIVED, not a constant.** No
   `87`, `696` or `0x2B8` exists anywhere in `.text` — 064 swept for it. **Do not
   burn a day sweeping for it.** §15.2's residual-failure-class note is literal
   here: the value is computed at runtime.
4. **An untested dimension.** Fog has two draw arms — scrolled (`0x47EBF0`) and
   static (`0x47EE20`). **All four of 064's captures were camera-at-rest**, so
   only the static arm's steady state is characterised. A capture taken DURING an
   active stepper scroll may show a different seam. One extra capture in your
   probe run buys this.
5. **Unexplained micro-structure, recorded nowhere else.** A stray single
   zero-column sits 1 px left of the solid band at origin 544 (x=671) but **4 px
   left at origin 704** (x=628, gap at 629-631). Probably shroud-edge
   coincidence at the second origin — **if it survives your first run it is real
   structure** and worth chasing.
6. **A lead, explicitly not a finding:** the always-lit strip is 104 px and the
   unread fog branch clamps to `0x68` = 104. Two numbers matching is where a
   hypothesis starts. This project has been bitten twice today by treating
   agreement as evidence.
7. **The suspect list from 064's scan:** unpatched cell-unit constants
   `81 = 648/8` at `0x0047E4B0`, `0x0047E8D9`; `80 = 640/8` at `0x0047E4C0`,
   `0x0047F820`, `0x0047F829`; plus the unread 104/103 sibling branch.
   **Bare `81` as an immediate is noise** — restrict by band (§12.11's lesson).

### Tools that already exist — use them, do not rebuild

- **`C:/git/decompile-sc/work/scratch/064/`** (main checkout, survives 064's
  reap): `scan_064.py` (value-family sweep, 100% byte coverage — edit the
  `VALUES` dict), `scan_fog.py` (648-family already run; extend for the
  81-family **with band restriction**), `scdis.py`/`ctx.py` (disasm),
  `zerocol.py`/`rowdiff.py` (dump analysis), `make_damaged.py` (oracle
  calibration by re-slicing a real dump), `mapunits.py` (CHK resource
  positions). `dump.py` hardcodes the exe path; everything reads game files
  read-only.
- **The probe**: `probe-framebuffer-capture.ps1 -SuiteArgs @{ Stage2 = $true }`
  gives stock + defect + the 4-capture scroll arm (~15 min). `zeroruns` runs
  standalone on any saved dump.
- **`dense_rows` is the oracle, not `wide_rows`.** 064 established `wide_rows`
  counts sprite rows as damage; `dense_rows` (differing-px count > half width)
  does not, and it has been shown RED on both synthetic and live pipeline damage.

### Constraints

- `StarCraft.exe` on disk byte-identical (runtime patches only); everything
  behind the existing off-by-default flag; never write the user's display
  settings, desktop layout, or registry. All runs off-screen (task 043).
- **Game frames NEVER go through `pr-image`** — hard rule 1; `pr-assets` is a
  branch in this repo. Pictures travel as paths.
- **Issue #97: your worktree has no `.venv`.** Junction the main checkout's in
  before generating any fixture, or map generation fails and the error **wrongly
  blames another worker**.
- **This is a hobby project.** Fixing the 104-px leak and leaving the 25-px seam
  is a good result and much more than half the value — the leak is the one that
  shows the player what they have not earned. Say what is left.

## Stop-line

**Three honest attempts, then report** — the rule 034 and 064 both honoured, and
the reason their accounts are worth reading. The fog cursor may turn out to be a
whole subsystem (see residue 1). **A measured "here is the fog architecture, here
is why it resists, here is what each attempt produced" is a real deliverable.**
Report early rather than late.

## Acceptance criteria

1. **A captured 800-wide in-game frame with a continuous fog boundary out to
   x=799**, unexplored map hidden, with the stock positive control passing in the
   same run and `dense_rows` behaving. Frame reported as a **path** plus numbers.
2. Captures at more than one camera origin, **plus at least one during an active
   scroll** (residue 4) — a fix that only holds at rest is not a fix.
3. If not fixed: the fog architecture written up at §15.4's standard, with what
   each attempt changed and what the frame showed.
4. `StarCraft.exe` byte-identical; nothing the user sees changes; flag off by
   default.
5. `scripts/run-ci-local.ps1` PASS; PR opened with the link in Status.pr. Cloud
   CI is down on billing — note it in the body. **PRs may stack** (standing user
   instruction) — say what you branched from.

## Machine

Task 066 is using it for a user-reported-bug fix and has priority. **Message the
conductor before your first launch.** The launch lock serialises one launch, not
a chain (issue #60).

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/068-fog-band-widescreen.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
