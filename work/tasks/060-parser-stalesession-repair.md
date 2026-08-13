# Task 060 — Repair the six parsers staleSession broke, using 058 pins as the oracle

## Status

agent: 060
model: sonnet
pr: -

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task060 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task060-parser-stalesession-repair.
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

- Your inbox: `C:/git/decompile-sc/work/messages/060/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 060 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

Repair the six parsers that PR #82 broke, and flip the six pins in
`tests/golden-line-seam.Tests.ps1` that currently assert they are broken. When
you are done, no suite is silently reading zeros, and the golden-line test says
so by passing on a match rather than on a non-match.

## Context

- **Issue: https://github.com/inwenis/decompile-sc/issues/87.** It carries the
  table of six sites with file, line, regex and effect. Read it; this file does
  not repeat the table.
- **This is a live defect on main right now.** PR #82 (the session epoch,
  merged 2026-08-13) inserted `staleSession=%d` between `refunded=`/`dropped=`
  and `refusedFull=` in three `ScLog` format strings. Six parsers across four
  suites assumed those fields were adjacent and no longer match.
- **Your oracle already exists and it is already committed.** Task 058's
  `tests/golden-line-seam.Tests.ps1` pins each of the six with

      $m.Success | Should -BeFalse -Because "known-broken finding, issue #87, not fixed here."

  So the moment you repair a regex, that pin goes RED and forces you to flip it.
  **That is the whole test plan** — you do not need to invent one. A repaired
  parser with its pin still asserting non-match means you fixed the suite and
  not the test, or the reverse; the pair only goes green together.
- **Two different failure shapes, and the distinction matters for how you
  verify** (both are in #87):
  1. **Silent zero — four summary-line sites.** No `else` on the
     `if ($s.Success)`, so a non-match leaves the field at its initialised zero.
     `test-upgrade-queue.ps1:490` is a live tautology today:
     `Assert-That '...' ($q.RefusedFull -eq 0)` cannot fail, because
     `$q.RefusedFull` can no longer be anything but zero.
  2. **Loud fail — the two PRODQSTATS sites.** Both already have
     `else { Assert-That '...the stats line parsed...' $false }`, so they break
     visibly. Still wrong, lower risk.
  Fixing the regex is not enough for shape 1: **add the missing `else`** so the
  next format-string change fails loudly instead of silently. That is the actual
  defect; the regex is just today's trigger.
- **Do not make the regexes brittle in a new way.** Matching the exact field
  order is what broke. Consider named captures or field-wise extraction so an
  inserted field cannot break a parser again — but keep it readable, and if you
  change the approach, change it everywhere or nowhere rather than leaving two
  idioms.
- **This is a hobby project.** Six regexes, four `else` branches, six pin flips.
  Resist rewriting the parsing layer.

## Steps (suggested)

1. Run `tests/golden-line-seam.Tests.ps1` first and read the six pinned cases —
   they tell you exactly which line in which file, and what the rendered line
   looks like.
2. Fix one, watch its pin go red, flip the pin, watch both go green. Then repeat.
3. Add the missing `else` branches to the four silent-zero sites.
4. Re-check `test-upgrade-queue.ps1:490` specifically: with the parser fixed,
   is that assertion still a tautology? If it is, say so — it may need its own
   repair beyond the parser.

## Acceptance criteria

1. All six parsers match the line the plugin actually prints, verified by the
   golden-line test passing on a MATCH rather than on a pinned non-match.
2. The four silent-zero sites gain an `else` that fails loudly, so the next
   inserted field cannot produce a stuck zero.
3. A statement on `test-upgrade-queue.ps1:490` — fixed, still tautological, or
   deliberately left. Do not leave it unmentioned.
4. **No in-game run is required and none is expected.** This is regexes against
   rendered format strings; the golden-line test is the proof. If you believe a
   game run is needed, say why before starting one — the machine is free but a
   run you cannot justify is a run that proves nothing.
5. `scripts/run-ci-local.ps1` PASS; PR opened with the link in Status.pr. Cloud
   CI is down on billing — note it in the body.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/060-parser-stalesession-repair.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
