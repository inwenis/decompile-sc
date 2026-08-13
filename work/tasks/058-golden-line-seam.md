# Task 058 — Golden-line tests for the printf-to-regex oracle seam

## Status

agent: 058
model: sonnet
pr: https://github.com/inwenis/decompile-sc/pull/88
merged: 2026-08-13

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task058 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task058-golden-line-seam.
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

- Your inbox: `C:/git/decompile-sc/work/messages/058/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 058 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

Make a change to a plugin log line fail LOUDLY at CI time instead of silently
turning a suite into one that asserts against zeros and passes. Build the Pester
file that reads each `ScLog(...)` format string out of the C++ source, renders a
line from it, and checks every parser regex that consumes that line still
matches with the group count the suite indexes.

## Context

- **Issue: https://github.com/inwenis/decompile-sc/issues/81.** Read it in full;
  it lists the log lines to cover in blast-radius order and names the throwaway
  to start from. This file does not repeat them.
- **This is the sibling of #78, which landed tonight as task 057.** Together they
  are 052's structural answer: 057 makes "watch a C++ oracle fail" a three-minute
  command; this makes the printf→regex seam refuse to drift. #78 reaches what
  hooktest reaches; this reaches the PowerShell suites, which is everything else.
- **The hazard has a fresh instance from tonight, not a hypothetical.** PR #77
  deleted five dead counters (#66), which removed `refusedCost=`,
  `mineralsSpent=` and `gasSpent=` from three log lines and broke **five**
  parsers across four suites. **Nothing found them but a grep.** Had one been
  missed, the regex simply would not have matched — and most of these parsers
  fall through to a default object of zeros or an `else` branch, so the failure
  mode is a suite that asserts against zeros and PASSES.
- **A working throwaway exists** at `work/scratch/055-check-parsers.ps1`
  (gitignored). It already covers PRODQ / PRODQSTATS / UPGQSTATS across four
  suites — 7 parsers, all matching. Generalise it into `tests/`. Read it first.
- **The fourth check in the issue is the one that makes this non-vacuous:**
  assert each regex literal is present VERBATIM in the suite it claims to come
  from. Without that, the test grades its own copy of a regex and passes while
  the shipped one rots — which is precisely the defect class this repo keeps
  producing. Do not skip it because it is awkward.
- **This must be able to fail.** Task 057 shipped `tools/plugin/build-defect-arm.ps1`
  on main tonight; the equivalent discipline here is to break a format string on
  purpose, watch the test go red, and put that transcript in the PR. A green
  golden-line test that has never been seen red is worth nothing, and this repo
  has the receipts to prove it.
- **Scope:** static analysis and Pester. **No game runs, no plugin builds** — you
  read source and run regexes. If you find yourself wanting to launch StarCraft,
  something has gone wrong with the design; say so rather than doing it.
- **This is a hobby project.** Cover the lines in the issue's order and stop when
  the remaining ones are low blast radius. A table in the PR saying "covered
  these, did not cover those, here is why" beats exhaustive coverage nobody asked
  for.

## Steps (suggested)

1. Read `work/scratch/055-check-parsers.ps1` and one of the suites it grades
   before writing anything.
2. Get ONE line end to end — `PRODQSTATS` is the one that broke tonight — with
   all four checks including the verbatim-presence one.
3. Break its format string on purpose and watch the test fail. Keep that
   transcript.
4. Then widen to the rest of the issue's list, stopping where blast radius drops.

## Acceptance criteria

1. A Pester file in `tests/` that passes on current main.
2. **A transcript of it FAILING** when a format string is changed on purpose,
   in the PR body. Say which line you broke and how.
3. The verbatim-presence check implemented, so the test cannot grade a stale copy
   of a regex. Show what it does when a suite's regex and the test's copy differ.
4. A coverage table: which log lines are covered, which are not, and why the
   uncovered ones were judged low blast radius.
5. If you find a parser that ALREADY does not match what the plugin prints, that
   is a finding — report it, do not quietly fix it. It would mean a suite is
   asserting against zeros right now.
6. `scripts/run-ci-local.ps1` PASS; PR opened with the link in Status.pr. Cloud
   CI is down on billing — note it in the body.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/058-golden-line-seam.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
