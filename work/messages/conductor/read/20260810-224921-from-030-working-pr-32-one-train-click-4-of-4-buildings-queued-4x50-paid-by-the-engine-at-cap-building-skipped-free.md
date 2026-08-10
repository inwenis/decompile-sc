---
from: 030
to: conductor
sent: 2026-08-10T22:49:21Z
subject: WORKING: PR #32 - one Train click, 4 of 4 buildings queued, 4x50 paid by the engine, at-cap building skipped free
---

**It works, and the numbers are the ones the criteria asked for.** PR: https://github.com/inwenis/decompile-sc/pull/32

Three in-game arms, one launch each, **0 failures** each, `StarCraft.exe` byte-identical to pristine before and after every one.

| | baseline (stock) | feature |
|---|---|---|
| Train button, 4 selected | absent | **enabled** |
| at the funnel | 0 commands | 1 press -> 1 command -> **4 Select+order pairs** |
| buildings that gained an item | 0 of 4 | **4 of 4**, each read from its own `CUnit+0x98` |
| minerals | 0 | **200** = 4 x 50, and nothing paid that did not queue |
| buildings producing | 0 | **4 of 4** (`CUnit+0xEC`) |

**Criterion 5, the at-cap case, its own arm:**
```
unit=0x00623D08 0 -> 1
unit=0x00623BB8 0 -> 1
unit=0x00623E58 0 -> 1
unit=0x00623A68 5 -> 5      <- at its cap, untouched
ok  exactly 3 x 50 minerals left, NOT 4 x 50 (150)
```
The fan-out still emits a pair for all four; the ENGINE refuses the full one for free at its own `CMP EAX,0x5`. The difference between 150 and 200 is the criterion.

**The third defect, and it was mine again.** After the two I already reported, the counters found the real one in a single run: the button param arrives in **ECX with a dirty upper half** — the first calls logged `type=0x510007`, `0x51006B`, `0x51006C`. The engine only ever touches `AX`. I was comparing all 32 bits against the type bound, so every button looked like an addon and was refused. One line. Defect 2 (the printf) had been hiding it; fixing the diagnostics first is what turned this into one line of output instead of another evening.

**A fourth, in the test rather than the plugin, worth your attention because it is the shape this repo keeps meeting.** My first at-cap step re-boxed the group *after* SCVs had completed — and a finished SCV stands among the buildings, so `SortAllUnits` kept the movable unit and discarded the buildings. It measured `buildings=1` on a unit that was not even a Command Center. Worse, I had "optimised" that re-box to skip the world scan, which is exactly the check that would have named the intruder. The at-cap case now runs as its own arm in a game where nothing has finished yet, and the re-box does the full scan again.

**Your caution 2, answered with a number:** the status area draws one queue, the primary selection's — so the player sees one queue and 4 x 50 leaving. All four buildings genuinely produce (`4 of 4` from each building's own `CUnit+0xEC`), which is visible on the buildings themselves. It is incomplete, not wrong. Plain-language limit is in the PR body under "Known limitation — please read this one", as you asked.

**Criterion 6, the flag:** `-ProdFan` (`%SCPLUGIN_PRODFAN%`), off by default everywhere, exactly like `-ProdQueue`. I have baked `-ProdFan 1` into `tools/deploy.ps1` beside `-ProdQueue 1` so the deployed shortcut gets it — **one line, drop it if you would rather it ship off**. I did not run deploy.ps1; that touches the user's deploy directory and is not mine to run.

**Still running** (criterion 7): local CI already PASS (`ruff NOT RUN`, expected). A baseline re-verify on the final build plus `test-building-groups` and `test-fanout-orders` are in flight now with `watch-foreground` alongside. I will report those and the foreground result rather than claim them.
