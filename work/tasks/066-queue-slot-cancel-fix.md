# Task 066 — Make the last queue slot cancellable: do not provoke the disable

## Status

agent: 066
model: opus
pr: https://github.com/inwenis/decompile-sc/pull/102

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task066 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task066-queue-slot-cancel-fix.
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

- Your inbox: `C:/git/decompile-sc/work/messages/066/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 066 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

Clicking the last production-queue slot cancels that unit, including when our
`+N` overflow text is on it. **Task 061 diagnosed this completely and did not
fix it. You are the fix.** Its diagnosis is merged, its two candidate designs are
below, and the first one is one run from being answered.

## Context

- **The user's exact words (2026-08-13T08:28Z), playing the deployed build:**
  *"bug - i can cancel a queue unit by clicking it, but it doesn't work if i
  click the last slock when it has our extra +x text"*. They confirmed the fifth
  slot and the group queue indicator both work — this is the one thing wrong
  with a feature they otherwise like.
- **READ PR #95 (merged) BEFORE ANYTHING ELSE**, plus what it added to
  `AGENTS.md` and `research/production-queue.md`. Task 061 spent a day on this
  and wrote its account specifically so a successor would not repeat it. Nothing
  below replaces reading it.

### What 061 established, measured, and is NOT yours to re-derive

1. **The cause chain, confirmed to one function.** `disableControl`
   (`0x00418640`) is a no-op when the control is already disabled → our plugin
   clearing the DISABLED bit each fill makes it fire → it sends `dwUser = 6` →
   control type 2's handler clears the PRESSED bit (`AND [ctrl+0x18],0xBFFFFFFF`
   at `0x004E1A9E`) → the mouse-up handler (`0x004E19F0`) emits ACTIVATE **only
   if PRESSED is still set**. So our own drawing destroys our own click.
2. **`queueLayout` disables on exactly one condition:**
   `buildQueue[(head + k) % 5] == 0xE4`. That is the only lever.
3. **`disableOnOwned == iconsFilled` exactly (1153974 = 1153974)** — every icon
   fill provokes exactly one disable. This is not a race to win; it is a fight
   we pick every frame.
4. **Removing the collision is NECESSARY**: paired, 30 clicks, 30 collisions,
   0 cancels, one row per click.
5. **It is a race and the rate depends on how long you hold the button**:
   0 of 18 cancels above a 60ms hold. The user loses it reliably; the harness
   used to win it sometimes. **The 17% at 60ms did not survive its own re-run** —
   quote a rate with its run, never as a property of the system.
6. **The obvious fix is dead and you must not rebuild it.** Restoring the PRESSED
   bit was built, measured rescuing the press 110,381 times, and **still never
   cancelled** — because restoring the bit does not re-deliver the mouse-up. It
   also left the press permanently armed (`disableWithPress=807134` of
   `1153974`): a stuck button. Reverted. `0x004E19F0` both clears the press AND
   emits the ACTIVATE, which is exactly why that fix reads as sufficient and is
   not.

### The two designs 061 left, in the order to try them

**Option C — never clear DISABLED at all.** `disableControl` early-outs when the
bit is already set, so if the plugin writes the icon fields and leaves the flag
alone, no `dwUser=6` is ever sent and there is no collision. **One line removed.**

- **061 half-refuted it already**: the icon's own draw at `0x00456C30` does
  `MOV BL,byte ptr [ESI+0x18]` / `TEST DL,BL` — it reads the flag byte. So the
  slot probably draws greyed, which undoes task 039's fix and returns the user to
  *"the 5th slot is empty"*. **Not dead** — nobody has measured WHICH bit that
  TEST uses.
- **The measurement is one run and the suite already has the oracles**: `art`
  stays `I`, the icons list reads `lit`, `slotDiff` stays in band. If they hold
  with the flag left set, C is the whole fix. If not, C is dead and you have the
  fact in the record either way. **Do this first.**

**Option A — make the ring slot non-empty for the length of the layout.** Hook
`queueLayout` (`0x004268D0`): pre-hook writes the overflow item's type into the
empty ring slot, post-hook restores `0xE4`. The engine then sees an occupied slot
and does the whole job itself — `enableControl` instead of `disableControl`, and
it writes icon/mode/type/grp with its own code.

- **It also deletes `FillOverflowIcons`'s field writes entirely**, including the
  GRP field whose omission was task 039's user-visible bug. We would stop
  hand-writing five fields the engine writes correctly.
- **The `+N` is untouched** — separate control, same anchor.
- **The risk, and the conductor's binding constraint on it:** for the length of
  that window the ring reads five items. Two things read the ring — the client's
  Train-button gate (**task 025 holds the ring at four precisely so that button
  stays lit**) and the observer thread (a phantom item in a `PRODQSEL` line).
  **Do NOT gate this on measuring that the call sites did not interleave.** "It
  did not happen in this run" is exactly the single-sample reasoning 061 spent a
  day retracting, and a Train button that greys once every few minutes is a bug
  the user would report next week and we would never reproduce. **Build the
  window so it CANNOT be observed, not so it merely was not.** If that is not
  available — if the pre/post pair cannot be made atomic with respect to the
  client gate — say so plainly rather than shipping it.

### The outcome that is explicitly acceptable

**If C dies and A cannot be made unobservable: stop drawing `+N` on a clickable
slot.** Task 039's goal statement sanctioned drawing nothing over drawing wrong,
and the same logic covers clicking. A feature that costs the user a working click
is worse than no feature — the user told us so by reporting it. Report that with
the evidence; do not invent a third mechanism to avoid saying it.

### The regression arm

`test-production-queue.ps1` carries an arm for this that **fails on purpose**
today and says so in its own output. Your fix turns it green — but:

- **No single-sample assertion on a race, in either direction.** Asserting "it
  cancels" on one click is the same defect with the sign flipped and it will
  flake. Use the rate harness 061 built (`-BracketSeconds`-style sweeps exist;
  read what is there before adding).
- **The hold-duration sweep is the arm that matters**: the fix must cancel at
  200ms, not only at 40ms. That is where the user lives.
- 061 deliberately did not convert the arm to a rate assertion because it had no
  measured baseline. **You do** — it is in PR #95.

### Constraints

- `StarCraft.exe` on disk byte-identical (runtime patches only); everything
  behind the existing off-by-default flag.
- **Game frames NEVER go through `pr-image`** — `pr-assets` is a branch in this
  repo and hard rule 1 wins. Screenshots travel as paths
  (`C:\sc-work\logs\...`). AGENTS.md § "Screenshots vs hard rule 1 (settled)".
- Issue #83 is a *different*, pre-existing cancel-arm bug (a read-order race).
  Do not conflate them.

## Steps (suggested)

1. Read PR #95, then `research/production-queue.md`, then the AGENTS.md
   additions. Then read `sc_queueind.cpp` as it now stands on main.
2. Run option C's measurement. It wins outright or eliminates itself.
3. Only then design A, and design the unobservability before the hook.

## Acceptance criteria

1. **Clicking the last slot with `+N` showing cancels it, at a 200ms hold**,
   demonstrated in a real game with the refund landing as the existing cancel arm
   asserts.
2. A rate, not an anecdote: N clicks across the hold-duration sweep, reported per
   duration, compared against PR #95's pre-fix numbers.
3. Every other slot still cancels; the fifth slot still draws lit with its GRP;
   the Train button never greys.
4. If the outcome is "stop drawing `+N` on a clickable slot", criteria 1–2 are
   replaced by the evidence for that decision, at PR #95's standard.
5. `scripts/run-ci-local.ps1` PASS; PR opened with the link in Status.pr. Cloud
   CI is down on billing — note it in the body. **PRs may stack and need not be
   merged immediately** (standing user instruction) — say what you branched from.

## Machine

Tasks 064 and 065 are also using it. **Message the conductor before your first
launch.** The launch lock serialises one launch, not a chain (issue #60). Option
C's measurement is one short run — ask for it early, since it may make the rest
of this task unnecessary.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/066-queue-slot-cancel-fix.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
