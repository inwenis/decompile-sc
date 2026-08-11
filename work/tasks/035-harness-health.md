# Task 035 — Close the five open harness issues in one pass

## Status

agent: 035
model: opus
pr: -

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task035 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task035-harness-health.
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

- Your inbox: `C:/git/decompile-sc/work/messages/035/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 035 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

**Close all five open GitHub issues in one pass.** They are all test-harness health, they all
live in the same two or three files, and giving them to five workers would reproduce exactly the
merge collisions that produced three of them. One task, one owner of `drive-game.ps1`.

The five, in the order I would do them:

1. **#30 — the game takes the foreground at launch and keeps it.** The one the USER feels. Task
   027 removed the per-click raise; nothing covers the LAUNCH. Task 030 measured it cleanly on an
   empty machine: the game took the foreground four seconds before its own log opened (i.e. at
   window creation) and the apparent "hand back" was the process exiting. Fix named on the issue:
   record the foreground window before `run-with-plugin.ps1` launches, restore it once the game
   window exists. The per-pick borrow machinery already does this; it just never covered launch.
   Verify with `watch-foreground.ps1` on an otherwise idle machine — that is the condition under
   which it reproduces.
2. **#39 — `test-ability-in-combat` fails 2 every sweep.** It re-applies Stim on every retake and
   the effect outlives a take, so from take 2 the did-it-fire delta reads 0. A suite that always
   fails is worse than no suite: it trains everyone to ignore a red result. Probable fix is
   "apply once, retake only the measurement window"; the issue lists two others.
3. **#37 — `marker.txt` write races the plugin's observer reading it.** Rare, loud, costs a whole
   run, and can happen inside a single suite (the observer polls ~4x/sec while the driver writes).
   Suggested fix on the issue is write-to-temp-then-rename, which removes the race rather than
   retrying through it — the observer polls, so a brief absence should be fine. Confirm that.
4. **#35 — hooktest part numbers collide silently across branches.** Three occurrences, each
   invisible because both branches merge cleanly alone. Ten-line fix: a check that fails if a
   number appears twice, run in `run-ci-local.ps1`. The issue also proposes removing the manual
   numbers entirely in favour of registration order + part NAME — that is the better end state
   and if it is not much more work, prefer it.
5. **#29 — read the Game Type from dialog memory instead of a panel-pixel fingerprint.** The
   current oracle picks a known-other entry, fingerprints pixels, picks the wanted one and
   demands the pixels changed. It cannot tell "the pick failed" from "the value was already
   right", and it is the ONLY reason `Send-ScDropdownPick` still raises the window at all. Task
   026's card reader (`sc_card.cpp`, the dialog list at 0x006D5E34) is the technique. Doing this
   AFTER #30 is deliberate: if the game type can be read, a run can skip the pick when the value
   is already correct, and the last raise disappears.

## Context

- **These are worth doing before more features.** Two of them (#30, #39) actively cost the user
  or hide real failures, and #35/#37 make the merge gate untrustworthy. A gate that fails for
  reasons unrelated to the branch teaches everyone to re-run until green, which is how a real
  failure gets waved through.
- **You own `tools/plugin/drive-game.ps1` for the duration.** Tasks 033 and 034 are live but are
  in plugin/renderer territory; if either needs a change in your files they will message me and I
  will coordinate. Rebase before finishing.
- **Each issue closes with its own commit** referencing the issue number, so any one of them can
  be reverted alone. Do NOT bundle them into one commit.
- **Prove each fix the way the issue's evidence was gathered**, not by assertion:
  - #30: a foreground trace on an idle machine, before and after.
  - #39: the suite green, and shown still capable of failing (it must still catch a real
    interruption — AGENTS.md, absence assertions proved positive).
  - #37: hard to prove by waiting; a targeted reproduction (hammer the marker while the observer
    polls) is acceptable and better than "it did not happen in three runs".
  - #35: introduce a deliberate duplicate, watch the check fail, remove it.
  - #29: the read agreeing with the engine in a live game, and a run that SKIPS the pick when the
    value is already right.
- **Watch for the trap this project keeps meeting**: a fix whose verification shares the flaw it
  is fixing. #29 is the obvious risk — do not verify a memory read with the pixel oracle it
  replaces.
- Test discipline: own `Maps\BroodWar\00-t035\`, `Select-ScBrowserMap`, `run-ci-local.ps1`. You
  have `time-suite.ps1` and `--unit-build-time` (task 031) for fast fixtures. GitHub Actions is
  billing-blocked; ignore it.

## Acceptance criteria

1. All five issues closed, each by its own commit referencing its number, each with the evidence
   its issue asked for. An issue you decide NOT to fix is closed with a reasoned comment instead —
   that is allowed, but say so rather than leaving it open and silent.
2. #30 specifically: a before/after foreground trace on an idle machine, since that is the
   condition under which it reproduces and the condition the user hits.
3. Every in-game suite green afterwards, including `test-ability-in-combat`, which is currently
   the one that is not.
4. `StarCraft.exe` byte-identical; no stranded processes; fixtures removed.
5. PR opened, link in Status.pr.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/035-harness-health.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
