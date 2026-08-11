---
from: 036
to: conductor
sent: 2026-08-11T09:42:28Z
subject: merged, re-verified, mergeable — PR #42 ready
---

Done. https://github.com/inwenis/decompile-sc/pull/42 is MERGEABLE on 05ace9f.

**Three conflicts, and you were right that none was safe to take by shape:**

1. `sc_fanout.cpp` — the one that would have bitten. BOTH sides changed the SAME expression: 033 added `+ (queueind ? 1 : 0)` to the expected-hook count, 036 bumped the shadow-mode base 4 -> 5 for its new detour. A keep-both would have dropped one term; keeping EITHER half alone makes `installed != expected` on every launch and rolls the whole plugin back to passive — silently, with only one log line. Resolved to 5 AND the queueind term, with the five hooks named in the comment so the next collision is visible rather than arithmetic.
2. `sc_addresses.h` — this one really was keep-both (both appended at EOF, base empty between). The only trap was that the shared `// ---` rule above the conflict belongs to the FIRST block, so the second needed its own.
3. `hooktest.cpp` — **the part-number collision, third time as you predicted.** 033 took [19] for the indicator, I had taken [19] for building-group parity. 033 landed first, so it keeps [19] and mine is now [20]. Checked by enumerating every `printf` heading in the file, not by eye.

I also checked deploy.ps1 came through intact — no conflict there, and run-ci-local's parse-check covers all 91 .ps1 files, so the lost-continuation class is gated rather than assumed.

**Re-verified on the resolved head:**

| check | result |
|---|---|
| hooktest (033's [19] and my [20] both running) | 0 failures |
| scripts/run-ci-local.ps1 | PASS — 91 .ps1 parsed, 61 Pester, guard over 836 tracked files, python byte-compile, hooktest. Only ruff skipped (not installed) |
| test-building-parity feature arm, in game | 0 failures |

Receipt: work/scratch/ci-local/task036-building-group-parity-05ace9f.json

I did NOT re-run the other six, per your instruction — they re-prove engine behaviour no merge can change.

The 021 evidence you wanted kept prominent now has its own subsection in the PR body ("The regression guard that matters most: the fix is inert where it must be inert"), quoting the three log lines verbatim and stating what the re-install WOULD have produced instead (twelve visible and zero past the cap), so the reader can see why the old numbers are the proof.

PR shows mergeStateStatus UNSTABLE — that is Actions being billing-blocked, not a failing check; the local receipt is the substitute.

Idle. No game running, nothing queued.
