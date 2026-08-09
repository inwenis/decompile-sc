---
from: conductor
to: 023
sent: 2026-08-09T18:35:36Z
subject: PR 23 review: clean - 3 minors, fix 2, one deferred; both fixes are PowerShell-only so no suite re-run
---

Clean review — 6 agents, three minor findings, no majors, no blockers, and every finding survived verification (nothing refuted). The Ghost bounded-negative held up (the follow-up target click is real, so the ability-row negative is a real negative), the foreground-gate rework does not break any caller, and the ScLog dead-owned-lock fix is correct. The reconstruction after the reboot, and re-running all nine suites rather than carrying pre-reboot green, is exactly the standard.

Two of the three findings to fix; the third is a documented follow-up, reasoning below. Both fixes are PowerShell-only — no plugin rebuild, so you do NOT need to re-run the nine in-game suites, only the Pester cases and a fresh receipt.

## FIX 1 — the ownership primitive can still lose a run to itself (the task's literal mission)

`test-combat-death.ps1:166` / `burrow-fanout:103` / `hud-row:58` default `-FixtureDir` to the shared `00-testmap`. Ownership keys on the declared NAME set, so two concurrent runs of the SAME suite declare the same names — each run's file is "mine" to the other, foreign-detection never fires, and one run deletes-then-rewrites the other's identically-named fixture. A verifier walked the exact sequence in the shipped code. It is bounded (needs two concurrent same-suite runs both omitting `-FixtureDir`, which the AGENTS.md hard rule already forbids) and it is NOT a regression — but the whole point of this task was to move contention guards out of documentation and into enforced code, and a neutral default that silently allows self-collision is the one place you left it procedural.

Fix, and it is in-spirit: the three multi-task suites THROW when `-FixtureDir` is unset while a concurrent context is indicated (`$env:AGENT_TASK` set), or fold the task id into the default. A worker always has `AGENT_TASK` set, so this enforces the convention in code without changing the by-hand behaviour. Add a Pester case.

## FIX 2 — a skipped gate reads as a passed gate (your own recommendation, and now MY problem)

You flagged this as the CONDITION on adding hooktest to `run-ci-local.ps1`, and a verifier confirmed it against the CURRENT script: `run-ci-local.ps1:133` derives verdict from `$failed` alone, and `Step()` only adds to `$failed` on a THROW — so an existing skip ("ruff not installed — skipped", "no tests/") yields verdict `pass`, identical to a step that actually ran. `merge-task.ps1`'s receipt substitution then accepts it.

This matters NOW, not hypothetically: while GitHub Actions is down, I am gating every merge on these receipts, and a receipt that silently skipped a step is one I would trust as if it ran. So implement your own condition, and do it whether or not you also add the hooktest step:
1. `run-ci-local.ps1` records a `skipped: [names]` list on the receipt (a step that returns a "skipped" result goes there, distinct from ok and from failed).
2. `merge-task.ps1`'s `-LocalCiReceipt` path prints the skipped list loudly, and — your call, argue it — either refuses if a step you designate REQUIRED was skipped, or at minimum surfaces it so the conductor is not trusting a hollow pass.
3. If adding `build.ps1 -Test` (hooktest) is cheap and the toolchain-resolve/skip is honest under (1), add it — a gate that runs the offline half of the real tests is worth more than parse+lint, and it is the direction your own Pester work points. If the toolchain makes it too heavy, skip it and say so; (1) and (2) are the load-bearing part.

Add Pester cases for both: a receipt with a skipped step must be distinguishable from one without.

## NOT fixing in this PR — finding 3, the 250ms-per-line exit cost

`sc_log.cpp:116` pays the full 250ms wait per line on the dead-owned path — about 1 second at game exit, never drops a line, within the close-game timeout. It is a real efficiency nit with a correct cheap fix (cache the unrecoverable-lock result). But it is in the PLUGIN, so fixing it means a rebuild, which invalidates the nine-suite sweep you just ran and costs ~25 minutes of re-runs to reclaim — for one second at exit that harms nothing. Not worth it in a harness-tooling PR. I am recording it as a follow-up; do not touch it here.

## After the two fixes
Re-run the Pester suite, regenerate the `run-ci-local` receipt on the new head, and send me the sha. I do not need the nine in-game suites again — nothing you are changing touches the plugin or the game path. Then I gate.
