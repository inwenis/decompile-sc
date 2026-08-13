# Task 052 — The first architectural review: duplication, invariants, and checks that cannot fail

## Status

agent: 052
model: fable
pr: -
merged: 2026-08-13 (report-only; no PR)

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task052 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task052-architecture-review.
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

- Your inbox: `C:/git/decompile-sc/work/messages/052/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 052 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

The first architectural review this repo has ever had, of **both** the plugin
(`tools/plugin/src/*.cpp|h`) and the testing framework
(`tools/plugin/*.ps1`, `scripts/`, `tests/`). Produce a REPORT, not a refactor:
what is duplicated, which invariants are stated-but-unenforced or
enforced-in-one-place-only, and — the one the evidence says matters most here —
which assertions cannot fail. Ranked by whether it can cause a WRONG CONCLUSION
or a user-visible bug, not by whether it offends a style guide.

## Context

- **The user asked, 2026-08-12T22:08Z:** *"have we ever done an architectural
  review of our code? do we have clean code? do we have duplicataions? do we
  handle invarians correctly?"* — then immediately: *"of our code and of our
  testing framework*"*. Both halves are in scope, and the second half is not an
  afterthought: most of this repo's damage has come from tests that passed.
- **The honest answer to "have we ever": no.** 51 tasks in six days, one audit
  (022, ability semantics — a domain audit, not architecture), and no pass over
  the whole. Current size: **18,641 lines** of C++ under `tools/plugin/src/`,
  **22,899 lines** of PowerShell under `tools/plugin/`. None of it has ever been
  looked at as a system.
- **This is a hobby project and the user has said so explicitly** (memory,
  2026-08-09): *"I'd rather have it work in the happy path, have less complexity
  and care about quality, and later we can do the polishing."* So this review is
  NOT a purity sweep. A 200-item list of style findings is a failed deliverable.
  Rank ruthlessly; put anything that is merely untidy into a single "deferred"
  section or an issue, and spend the report on things that can make us believe
  something false.

### Start from these, they are real and they are from the last 24 hours

Not hypotheticals — each is a measured instance of the class:

1. **Checks that cannot fail — the dominant defect class in this repo.**
   - `indInk` in `sc_hudrow.cpp`: the box is 148×16 = 2368 and the ink count
     reads **2368 for every string**, because the wireframe art saturates the
     region. The page indicator has NEVER been drawn and the assertion written to
     catch that has been counting the game's own pictures (task 048, tonight).
   - `test-hud-row.ps1`'s hook assertion was `-eq 6`, a total matching a total;
     it would stay green if `statDataUpdate` — the hook that suite exists to test
     — were swapped for any other (task 050, tonight).
   - `test-save-load.ps1`'s first control run passed **nine** round-trip
     assertions with no load having occurred: everything it compared matches when
     the two states are the same (task 051, tonight).
   - The ancestors: task 033 asserting a string out of the module's own buffer,
     task 029 asserting queue length instead of the engine's level array.
   **Ask: how many more are there, and is there a structural reason this keeps
   happening rather than five unlucky authors?**
2. **Duplication that has already cost something.**
   - `Get-ScFanoutExpectedHooks` / `Compare-ScHookNames` lived inside one suite
     until task 050 lifted them into `drive-game.ps1` — the second suite had
     grown its own worse version instead.
   - Two modules each grew their own "read this dialog's surface" code; task 048
     is extracting one reader as a side effect of an unrelated fix.
   - **A wrong MENTAL MODEL duplicated across modules is the expensive kind:**
     the dialog redraw walk paints children head-first, task 039 found and fixed
     that in `sc_queueind.cpp`, and `sc_hudrow.cpp` still carries a comment
     asserting the opposite — which is why its indicator is invisible.
3. **Invariants that are not enforced where they are relied on.**
   - `RecordStillLive` (`sc_prodqueue.cpp`) answers "is my building still alive?"
     with unit id + player + hp — all of which a save restores VERBATIM into the
     same static slot, so a record from a different game reads as alive
     (issue #63, tonight). The invariant "a record belongs to this game" was
     never expressed anywhere.
   - Look for the same shape elsewhere: what else keys on an address or a value
     that the engine may legitimately reuse?
4. **The test framework's own seams.** `drive-game.ps1` is ~5k lines and every
   suite depends on it; `run-offscreen.ps1`, the launch lock (issue #60 — it
   serialises one launch, not a chain), the fixture generators, the log-scraping
   oracles. Ask what a new suite is forced to re-invent, and what a suite can get
   wrong silently.

### Constraints

- **Read-only on product code.** Do NOT refactor, do not "fix while you are
  there". The deliverable is the report plus issues. If something is a one-line
  obvious bug, name it and open an issue; the fix is a later task with its own
  evidence.
- **No game runs, no launches at all.** Two workers (048, 051) are using the
  machine and StarCraft is single-instance. Everything here is reading code,
  logs and history.
- Prior art worth reading before judging anything: `AGENTS.md` in full — most of
  its dated sections are postmortems of exactly these classes, and a finding it
  already documents should be cited rather than rediscovered.

## Steps (suggested)

1. Read `AGENTS.md` end to end first. It is the repo's own account of how it has
   been wrong before, and it will stop you reporting known lessons as news.
2. Do the "cannot fail" sweep before anything else — it is the highest-value
   axis and it is mechanically searchable (assertions on counts, on `> 0`, on a
   value the module itself wrote, on totals rather than composition).
3. Then duplication, weighting duplicated MODELS above duplicated code.
4. Then invariants: for each module, what does it assume that nothing checks?
5. Rank. Cut anything that cannot change a conclusion or a user-visible outcome.

## Acceptance criteria

1. A report at `work/reports/052-architecture-review.md`, opening with a plain
   answer to the user's four questions in a few sentences: has a review been
   done, is the code clean, is there duplication, are invariants handled.
2. Findings ranked, each with: the file and line, what it means concretely, and
   what it would cost if left. No finding without a location.
3. A separate, explicitly-labelled DEFERRED section for everything that is
   merely untidy, so the ranked list stays trustworthy.
4. Each finding at rank "would cause a wrong conclusion or a user-visible bug"
   gets a GitHub issue opened, so the report does not become the only record.
5. An explicit statement of COVERAGE: what you read, what you did not, and what
   a second pass should start with. A review that implies it saw everything is
   the same defect class as the assertions it is hunting.
6. No product code modified. `pr: -` — this task reports, it does not merge.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/052-architecture-review.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
