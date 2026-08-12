# Task 046 — test-selection-circles [5] fails on clean main: the SORT diagnostic, not the feature

## Status

agent: 046
model: sonnet
pr: https://github.com/inwenis/decompile-sc/pull/53
merged: 2026-08-12

## Workspace

- repo: C:/git/decompile-sc (research + orchestration in one repo)
- worktree: C:/git/decompile-sc-task046 — conductor pre-created it; you were
  spawned inside it. ALL code/doc edits happen here, on branch task046-sort-candidates-diagnostic.
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

- Your inbox: `C:/git/decompile-sc/work/messages/046/inbox/` (`read/` next to it).
- Run every `.ps1` (send-message, etc.) via the PowerShell tool, NEVER the
  Bash tool — Bash invokes Windows PowerShell 5.1, `#Requires -Version 7`
  fails, NOTHING is written, and the call LOOKS sent (message-loss class,
  2026-07-18: tasks 041/054 "lost" pictures were never-written sends).
  Always check the script printed the written file path.
- FIRST duty, before any other work: arm a monitor on that inbox (harness
  `Monitor` tool + poll loop — see AGENTS.md § Messaging), then tell the
  conductor you are listening:
  `./scripts/send-message.ps1 -To conductor -From 046 -Subject READY -Body '<one line>'`
  (run from C:/git/decompile-sc)
- A from-CONDUCTOR message arrives → apply it, move it to `read/`, re-arm,
  carry on. A from-USER file is INFORMATIONAL: leave it, do not act — the
  conductor reviews every user message and relays instructions
  (AGENTS.md § Messaging).
- Questions or blockers → message `conductor`; never stall silently.

## Goal

`test-selection-circles.ps1` part [5] fails on clean `main` and has been failing
for some time. Find out whether the FEATURE is broken or the DIAGNOSTIC that
part reads is, and make the outcome unambiguous — either fix the feature, or fix
the check so it measures the thing it claims to measure. A suite with a
permanently red line teaches everyone to ignore red lines, which is the real
cost here.

## Context

- Found by task 043 while proving off-screen runs did not break anything. It ran
  the suite on a clean `main` worktree at `c0b69dc`, visibly, with its own fresh
  plugin build and nothing of 043's in the path:

      [5] a 24-unit drag box circles the 12 the engine threw away
        FAIL the box contained more than 12 units

  Every other assertion in the suite passed. Identical in 043's two arms. So this
  is genuinely pre-existing and NOT caused by 043 or by the off-screen path.
- What part [5] actually asserts: that the plugin's `SORT candidates=N ->
  selected=M` log line reports `N > 12` for that drag box.
- **The strong hint, and where to start:** the box appears to select the RIGHT
  units regardless. In the same run, the shadow list, the circle count and the
  fan-out all independently agree on 24 boxed / 12 over-cap. Three oracles agree
  with each other and disagree with this one line. So the prime suspect is the
  `SORT` diagnostic itself or the regex that parses it — not the selection
  feature.
- That makes this a direct instance of AGENTS.md § "Your DIAGNOSTICS are under
  the same rule as your assertions" (task 030): a wrong number in a log is worse
  than no number. Read that section before starting; the fix shape it prescribes
  (print WHICH branch, count every exit term, make entry distinguishable from
  refusal) probably applies here.
- Do not "fix" this by relaxing the assertion. If the diagnostic is wrong, the
  diagnostic is what changes, and the assertion must still be able to fail — prove
  it can by making it fail on purpose once.

## Steps (suggested)

1. Reproduce on clean main; capture the full `SORT` line and the surrounding log.
2. Decide from evidence which is wrong: the counter, the log's format string, the
   suite's regex, or the feature. Name the one that is wrong and say how you know.
3. Fix that one. Prove the assertion can still fail.
4. Off-screen is now available (task 043, merged) — use `run-offscreen.ps1` so
   this costs the user's screen nothing.

## Acceptance criteria

1. A named root cause with evidence — which of counter / format string / regex /
   feature was wrong, and what proves it.
2. `test-selection-circles.ps1` green on the fix, part [5] included.
3. Part [5] demonstrably CAN still fail (show the deliberate break and its output).
4. If it turns out the feature is genuinely broken rather than the diagnostic,
   stop and message the conductor before widening the fix — that is a different
   task's worth of work.
5. `scripts/run-ci-local.ps1` PASS; PR opened with its link in Status.pr. Note in
   the PR body that GitHub Actions is down on a billing error and the local
   receipt is the gate.

## Reporting

Status is DERIVED, never reported. The console works out what this task is
doing from things that already exist — the agent registry, the PR, the
`merged:` stamp, your open questions — so there is no `state:` line to keep
current and no status to update. You have exactly three duties:

- Open a PR when you have something to review, and put its link in Status.pr
  (an open PR is what makes this task read as "review").
- <either> that PR <or> a report at work/reports/046-sort-candidates-diagnostic.md — UNLESS the
  Goal/Context above says otherwise, in which case that wins. This section is
  generic scaffolding; a task-specific instruction (or a standing user rule
  quoted in it) always overrides it. Do not "satisfy both" by writing a file
  the task told you not to write.
- Blocked? Ask — `send-message.ps1 -Type question` (§ Messaging). An unanswered
  question of yours IS the blocked signal; answering it clears it. Never write
  a status instead of asking.
- UI-visible changes → screenshot → `pr-image <file>` → embed markdown in PR.
