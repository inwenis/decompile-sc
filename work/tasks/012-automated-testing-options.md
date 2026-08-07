# Task 012 — Investigation: how to test in-game without a human at the keyboard

## Status

agent: 012
model: opus
pr: -

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task012 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task012-automated-testing-options.
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

- Your inbox: `C:/git/decompile-sc/work/messages/012/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 012 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

**An investigation, not an implementation.** Answer one question with evidence: how can this
project verify in-game behaviour *without* a human at the keyboard? Produce
`research/automated-testing-options.md` — a ranked set of options, each with a feasibility
verdict, an honest cost, and what it can and cannot prove. The user asked for options; give them
a decision, not a survey.

Do **not** build the winning option here. If a cheap probe settles a feasibility question, run
it and report — but the deliverable is the document.

## Why this exists

Every in-game result so far required the user personally: load a map, box-select, right-click,
report what they saw. That is slow, it does not scale to a test suite, and it makes regressions
invisible between sessions. It has also already cost a round trip on a wrong directory.

An earlier attempt at synthetic input failed concretely: the worker asked the pointer to go to
screen `1818,935` and it landed at `1228,1544`. That is documented in
`research/runtime-selection-observations.md` §5. The display is 3840x2160, so suspect
absolute-coordinate normalisation and/or DPI scaling — but do not assume; measure.

## Split the problem in two — this is the key framing

Automating a test has two halves, and they are **not** equally hard:

1. **Driving** — making the game do a thing (select units, issue an order).
2. **Observing** — determining what actually happened, in a way a script can assert on.

**Half 2 may be the more valuable half and is probably the easier one**, because we already have
code running inside the process with a verified address map. If a script can read "these 36 units
now have a move order to point X", that is a stronger assertion than a human squinting at a
screen — and it works even if driving still needs a hand. Do not let the input problem dominate
the investigation.

## Options to evaluate (not exhaustive — add your own)

**Driving:**
1. **Fix synthetic input.** Diagnose the coordinate failure properly: `SendInput` absolute
   coordinates are normalised 0-65535 across the *virtual* desktop, which is a classic
   multi-monitor/DPI trap. Also consider window-message posting to the game window in client
   coordinates. Verdict needed: can this be made reliable, or is it inherently flaky?
2. **Drive from inside the process.** We already inject. Rather than synthesising OS input, the
   plugin could invoke the game's own selection/order paths directly, or enqueue commands. This
   sidesteps the input stack entirely. `research/selection-cap.md` §4.1/§4.3 and
   `research/binary-selection-map.md` give the relevant function addresses; task 011 is already
   hooking some of them. Assess reliability, and be explicit about the risk that a test which
   drives via internal calls **is not exercising the same path a real player takes** — that is a
   genuine validity limitation, not a footnote.
3. **Command-stream injection.** The command stream is the replay format. Feeding canned commands
   is a possible driver; note what it does and does not exercise.
4. Anything else you find — a saved game as a fixture, a scripted map with triggers that set up
   state, etc. Our own map generator (`tools/make-test-map.ps1`) can build deterministic fixtures.

**Observing:**
5. **Read outcomes from memory.** Unit positions, current orders, order targets. We already read
   selection state reliably. Assess: what would we need to map that we have not, and how hard?
6. **Assert on the command stream / replay.** A replay is a deterministic record of what was
   commanded. Worth assessing as an oracle.
7. Screenshot comparison — evaluate honestly and probably reject: brittle, and it involves game
   artwork we do not commit.

## Hard rules

1. **Never modify, write to, or launch `C:\sc-install\Starcraft`.** Working copy only.
2. Offline, single-player only. Never Battle.net.
3. **Task 011 is live and the user may be mid-test with the game open.** Do NOT launch the game
   without asking the conductor first — message and wait. Two workers fighting over one game
   window, or over the shared working copy, is exactly the class of collision that already cost
   the user their player profile once. Desk research and static analysis need no permission.
4. Commit no game content, no binaries, no logs containing game data.
5. Timebox this. A confident recommendation with two options properly assessed beats seven
   options hand-waved.
6. Do not merge your own PR.

## Acceptance criteria

1. `research/automated-testing-options.md` exists with options **ranked**, each carrying: what it
   automates (driving, observing, or both), a feasibility verdict, rough cost, what it can prove,
   and — stated plainly — **what it cannot prove**.
2. The driving/observing split is addressed explicitly, with a recommendation for each half.
   Partial automation (script observes, human drives) must be assessed as a real option rather
   than dismissed.
3. The synthetic-input failure is diagnosed rather than restated: say *why* the pointer landed
   where it did, with evidence, and whether it is fixable.
4. A clear top recommendation with reasoning, and a rough sketch of what implementing it would
   involve — enough that the follow-up task could be cut straight from the document.
5. Validity limitations called out honestly, especially for in-process driving: a test that
   bypasses the real input path proves less than one that does not, and the document must say so.
6. Anything you could not verify is marked `[unverified]`, consistent with this repo's evidence
   rules. If you ran a probe, show what it showed.
7. PR opened, link in Status.pr.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/012-automated-testing-options.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
