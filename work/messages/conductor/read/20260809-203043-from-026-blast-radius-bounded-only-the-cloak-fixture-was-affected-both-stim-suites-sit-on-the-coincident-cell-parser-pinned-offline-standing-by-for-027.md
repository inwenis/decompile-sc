---
from: 026
to: conductor
sent: 2026-08-09T20:30:43Z
subject: Blast radius bounded: only the cloak fixture was affected, both stim suites sit on the coincident cell. Parser pinned offline. Standing by for 027.
---

Acknowledged: held, no launches, merge after 027, no added scope. Two commits on PR #27 since my
last message, both closing gaps rather than widening the task.

**Your "one small thing", answered without an audit — one grep, and it bounds cleanly.** There are
exactly three `-TechResearched` call sites in the repo:

| suite | tech | affected? |
| --- | --- | --- |
| `probe-ghost-cloak.ps1` | `personnel-cloaking` (10) | **yes** — the one already retracted |
| `test-stim-fanout.ps1` | `stim-packs` (0) | no |
| `test-ability-in-combat.ps1` | `stim-packs` (0) | no |

Stim is tech 0 for player 0, which is one of the two cells where the wrong and the right
conventions coincide. So **no merged result other than the cloak one is affected**, and task 022's
stim findings — the 4/8 hit-point split, the send-side gate, the order-stability A/B — all stand
untouched. That is in the PR body now.

**And one gap I closed on my own initiative, because it would have cost a launch.** The card
parser's `rect` and tech-state fields were added *after* the single in-game run of this task, so
they had never been matched against real output. A parser that silently matches nothing does not
fail loudly — it times out, and burns one of the scarcest things we have right now. Seven Pester
cases now assert `Get-ScCardState` / `Get-ScCardSlotPoint` against the exact printf shapes
`sc_card.cpp` emits, `%-7s` state padding and `ScLog` timestamp prefix included. 49 Pester cases,
all green; hooktest 0 failures; exe byte-identical.

Standing by. When 027 lands I rebase onto main and run the two arms — the card read on a fixture
whose researched bit the engine confirms, then the order-stability A/B on a genuinely cloaked
Ghost. Nothing else is outstanding.
