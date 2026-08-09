---
from: 023
to: conductor
sent: 2026-08-09T18:46:22Z
subject: both review fixes in - head d4dd8ba, receipt pass, Pester 34/34; skip-tracking proved in both directions
---

Both fixes in. **New head `d4dd8ba166947b41f8e1c31f967208096602fb89`**, receipt `task023-harness-hardening-d4dd8ba.json`, verdict **pass**, `skipped=[ruff]`, `requiredSkipped=[]`. Pushed to PR #23. Finding 3 left alone as you scoped it.

## FIX 1 — self-collision (`9fb2322`)

`Resolve-ScFixtureDir`: `-FixtureDir` if given → **this agent's own folder** when `$env:AGENT_TASK` is set → the suite's historical default otherwise. I took the fold-the-task-id branch rather than the throw: a worker always has `AGENT_TASK`, so two runs of one suite can no longer resolve to one folder at all, which removes the failure instead of converting it into a runtime error. A human at a prompt gets the old default byte-for-byte, so the "defaults to current behaviour" promise still holds.

**The review named three suites; it is seven.** The other four had the mirror-image bug: `test-control-groups` defaulted to `00-t021`, and `test-stim-fanout` / `test-sunken-acquire` / `test-ability-in-combat` to `00-t022` — the folders of the tasks that WROTE them. Any later worker running those by default was writing into a finished task's folder. Same resolver, same fix, all seven.

Task id is leading digits, so `023` and `023-ghost-cloak` both give `00-t023`, matching `Enter-ScLaunchLock`'s `-TaskId` convention. Five Pester cases, including that two agent ids never resolve to one folder and that a stale `00-t02x` fallback never survives into a worker run.

## FIX 2 — a skipped gate is no longer a passed gate (`d4dd8ba`)

All three parts, plus the hooktest step.

1. **Receipt records skips by name.** Steps declare `-Required`; a step that cannot run returns `Skip-Step` instead of a detail string. Required skip (`parse-ps1`, `validate-json`, `pester`, `game-content-guard`, `compile-python`) → verdict **`incomplete`**, kept distinct from `fail` because they need different reactions: fail means the code is broken, incomplete means the evidence is missing. Optional skip (`ruff`, `hooktest`) → still `pass`, but named on the receipt and printed on every path including the pass.
2. **`merge-task.ps1` refuses, not just warns.** It refuses an `incomplete` receipt, refuses one that says `pass` while naming a skipped required step, and — you asked me to argue this one — **refuses a receipt written before skip tracking existed.** An old receipt cannot tell us whether it skipped anything, and "we cannot tell" is not "it is fine"; re-running costs seconds. Every acceptance rule now lives in one pure function, `Get-CiReceiptRefusalReason` in `scripts/lib/ci-local.ps1`, so it is testable instead of inline in the merge path. What a receipt did NOT run is printed next to the substitution and carried into the PR comment.
3. **hooktest added**, non-required. ~6 s, offline. It is the only step in that gate that can fail on a LOGIC error — parse and lint only see syntax, and case `[12]` fails against pre-023 code by construction. It resolves the toolchain first and skips by name when the pinned 32-bit MinGW is absent, which is what makes (1) load-bearing rather than decorative.

**Both directions proved end-to-end, negative after positive:**

```
toolchain hidden ->  SKIP hooktest -- no 32-bit toolchain at C:\nope\bin
                     ci-local: NOT RUN -- ruff, hooktest
                     verdict pass, skipped=[ruff, hooktest]
                     merge-task would print: NOT RUN by this receipt: ruff, hooktest

tests/ renamed   ->  SKIP pester -- no tests/ directory  (REQUIRED)
                     ci-local: INCOMPLETE -- required step(s) skipped: pester   (exit 1)
                     merge-task refuses: "the receipt verdict is 'incomplete', not pass"
```

`tests/` was restored immediately and the final receipt above is a clean run.

## Verification on the new head

- **Pester 34/34** (was 16; +5 fixture-folder, +12 receipt, +1 existing split).
- `run-ci-local.ps1` **PASS at `d4dd8ba`**, with `hooktest 0 failures` inside it this time.
- `StarCraft.exe` SHA-256 `AD6B58B2…288C6A46`, unchanged. No processes. `Maps\BroodWar` = `Allied`, `Ladder`, `WebMaps`.
- In-game suites **not** re-run, per your call — nothing here touches the plugin or the game path.

One thing to be aware of rather than a request: FIX 1 changes what a suite does **when run by an agent with no `-FixtureDir`** — it now writes to `00-t<agent>` instead of `00-testmap` / `00-t02x`. My nine-suite sweep passed `-FixtureDir` explicitly, so it exercised the same code path either way, and the resolver itself is covered by the Pester cases. If you would rather see one in-game suite re-run on the defaulted path before you gate, say which and I will run it — it is about 90 seconds.

Not merged by me.
