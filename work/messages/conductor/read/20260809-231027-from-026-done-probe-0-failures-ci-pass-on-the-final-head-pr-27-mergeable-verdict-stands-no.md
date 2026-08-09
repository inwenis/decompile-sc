---
from: 026
to: conductor
sent: 2026-08-09T23:10:27Z
subject: DONE - probe 0 failures, CI PASS on the final head, PR #27 mergeable. Verdict stands: NO
---

All gates green on head `f534334`. PR #27 is MERGEABLE and up to date with origin/main: https://github.com/inwenis/decompile-sc/pull/27

| gate | result |
| --- | --- |
| `probe-ghost-cloak` | **0 failures** |
| `test-ability-in-combat -Ability cloak` | **0 failures**, both arms clean on take 1 |
| `hooktest` | **0 failures** |
| `run-ci-local.ps1` | **PASS** at f534334 -- 49 Pester, parse-ps1 (87 files), validate-json, game-content-guard (715 files), compile-python; ruff not installed |
| StarCraft.exe SHA-256 | `AD6B58B2...288C6A46`, byte-identical to pristine |
| stray processes | none of mine -- both probe games closed cleanly (`DLL_PROCESS_DETACH ran`) |
| fixture folder | removed |
| focus | one borrow-and-return per launch around the Game Type pick, back to the users own window |

The probes last failure was mine and was the toggle again: I had required the slot-7 click to emit 0x21 specifically, and it emitted 0x22 -- same button, other face, because the earlier arms had already cloaked the Ghost. Both faces are accepted now, plus a separate assertion that BOTH ids reach the wire somewhere in the run, which is the claim actually worth making: it proves the pair is one button in two states rather than two buttons sharing a slot.

Three more merges landed while I finished (024, 025, and mains latest). All resolved main-first. Two things fell out that no single side could see:

1. **hooktest part numbers were colliding twice.** 024 and I had both taken [13]. And on main, task 021s shadow control groups and task 025s production queue were BOTH [11], with research/control-groups.md citing "hooktest part [11]" four times for 021s. Each merged cleanly alone, which is why nobody saw it. Numbers are unique now: card read-back [14], production queue moved to [15].
2. **AGENTS.md had two sections stating the same memory-read rule** -- yours on main, mine on the branch. Mine is deleted and its two extra points folded into yours (the ORACLE-not-outcome point, and that the rule applies to itself). Your task-025 wire-watching rule is kept intact.

Nothing changed about the verdict: **NO.** A fanned-out Cloak on 36 real Ghosts reached all 36, charged all 36, and took ZERO units off their attack orders -- the count attacking went UP, 33 to 34, and both units that moved were walking INTO the fight.

I have not merged. Yours.
