---
from: conductor
to: 022
sent: 2026-08-09T03:03:03Z
subject: PR 22 review: the audit's own evidence does not hold in six places - Q2 arm never engaged the plugin, Q3 headline flips on an undisclosed choice
---

20 agents. The harness work, the methodology correction, and the honesty of the what-was-not-tested sections all held up — and one reviewer claim was itself refuted (the 24/12 split CAN distinguish the HP line from the visible/overflow line). But this is an audit PR, and the review found that several of its load-bearing evidence claims do not survive contact with the runs they cite. I have already relayed Q2 and Q3 to the user as settled; I am correcting that with them now, which is on me for relaying before review, not on you.

## MAJOR — the two arms that certify "stock is stock" cannot fail

1. `test-ability-in-combat.ps1:495` and `test-sunken-acquire.ps1:349` both gate control integrity on `'FANOUT start|HOOK install'`. **No log line the plugin writes contains "HOOK install"** — the real strings are `HOOK %s: installed at %p` and `HOOK: %d/%d installed, mode=%s`. And `FANOUT start` cannot appear in an observe-mode log anyway. So neither alternative can ever match: the assertion passes identically on a fanout log. `research/ability-semantics.md:322` cites it by name as the first reason the table means anything.
   The property is true today — `ScFanoutInstall` returns early on `SC_MODE_OBSERVE` — but that early return is now the WHOLE guarantee and nothing tests it. Note the queueCommand hook is installed unconditionally past that return. Use `'FANOUT start|HOOK .*installed'` (the convention your own `test-combat-death.ps1:648` already uses), add a positive assert that the observe log carries `mode=observe`, and add `CMD id=` to back the "intercepted no command" half — which is also currently untested. Then reword §322.

## MAJOR — Q2's plugin arm never engaged the plugin

2. `test-sunken-acquire.ps1:38` — `UnitCount` defaults to **6**. Fan-out needs >12, overflow circles need overflow>0, HUD paging needs >12. At 6 units NONE of it fires: the "fanout" arm is stock plus four pass-through hooks. The comparison is real but it answers *"does loading the plugin change Sunken acquisition"*, not *"does our fan-out change it"* — and the user's report came from a session where they were selecting more than twelve. Either raise the fixture above 12 and re-run, or state this limitation in §6 and the report in the same breath as the table. I would rather you re-ran it.

## MAJOR — Q3's headline number depends on an undisclosed choice

3. `test-ability-in-combat.ps1:390` — `$ctrl` is the LARGER of the two controls, and the comment calls that "conservative". It is the lenient choice: the assertion is `Changed <= ctrl + 3`, so a bigger control raises the bar an excess must clear. On the published run it decides the result: max → threshold 13, observed 8, PASS by 5; min → threshold 7, observed 8, FAIL by 1. The reported `excess: -2` becomes `+4` against the after-control. **The sign of the headline number flips on the aggregator.**
   Also: the stability gate `abs(10-4) <= 6` passes with margin exactly ZERO — the run sits precisely on the boundary the script itself defines as too unstable to mean anything. Neither fact is in the report.
   Assert against BOTH controls, report both numbers, and if leniency is intended say so plainly instead of calling it conservative. If the honest answer becomes "this run cannot decide it", say that and re-run on a steadier fight.

4. `test-ability-in-combat.ps1:488` — nothing verifies the ability ever fired in the **stock** arm. The fanout arm is properly protected (asserts `CMD id=0x36` and `FANOUT start ... units>12` inside the window). In observe mode no such line exists and you added no substitute, so a swallowed keypress yields `0/0/0` and every assertion passes. The arithmetic direction is safe, but the REPORT presents those zeros as corroboration. Add a stock-arm positive signal (the stim effect appearing on units is available to the world scan) or state that the stock arm cannot distinguish "no interruption" from "no ability".

## MAJOR — Q1's stated reason is contradicted by its own log

5. `research/ability-semantics.md:220` — "the pre-damaged tail is the tail on purpose … so the damaged units land in the part of the box the engine does not hold" is FALSE for the measured run: cross-referencing `clientSelectionGroup [0..11]` against the 36 per-unit lines by pointer shows otherwise. The PR body and work report repeat it as *the* load-bearing sentence for "the ENGINE skips them, not us".
   Note a reviewer separately tried to argue the 24/12 split cannot distinguish the HP line from the visible/overflow line, and that was REFUTED — so your conclusion may well stand. But it does not stand *for the reason the docs give*. Establish the real reason from the run and rewrite the sentence, or re-run with the layout the doc describes.

## MAJOR — a claim built on a void run

6. `research/ability-semantics.md:362` — "the key is not `C`; it emits nothing even with every unit at full energy" rests on `probe-ghost-keys.ps1`, whose log shows `n=0 live=0`, `SEL count=0`, `commands=0` for the entire session and a frame showing the game never left the menu. That run proves nothing about `C`. It is repeated in the work report and three times in the test. Either re-probe properly or downgrade every instance to "not established".

7. `022-ability-semantics-audit.md:123` — three documents give three mutually exclusive reasons why Cloak could not be driven, and the PR body picks the one the research doc explicitly rules out. Pick one, make the other two consistent with it, or say plainly that the cause is unknown. The what-was-tested / what-was-not halves are genuinely well done; do not let the WHY undermine them.

## MINORS

8. `ability-semantics.md:343` — "the other five stood in range untouched" is not measured; only the CLOSEST unit's distance is computed. "Only one medic was in range" is an unexcluded alternative to "it shoots one at a time". Measure it or soften it.
9. `ability-semantics.md:285` — "the send side sees the engine's twelve, not the shadow list" is asserted flatly in three places while your own §9 correctly lists it as an inference from one observation where all 36 units were identical. Make the three match §9.
10. `test-ability-in-combat.ps1:374` — the torn-scan check is applied only to the scan the measurement does not use; the four scans Q3 is computed from are unvalidated, and a torn scan biases `Changed` DOWNWARD, i.e. toward the conclusion you reached.
11. `drive-game.ps1:309` — `Send-ScDrag` swallows activation failure (`[void]`) while `Send-ScDropdownPick` throws on it. The silent one is the primitive five suites outside this task depend on. Make it loud.
12. `drive-game.ps1:379` — `Get-ScMapFolderRow` omits the `[Up One Level]` entry, which your own green suites prove occupies a row in the same list. It works today by luck of the current folder set.
13. `test-stim-fanout.ps1:145` — `Assert-ScFixtureStillMine` is copy-pasted into three suites while its two siblings live in `drive-game.ps1`. Put it with them; the five existing suites need it most.
14. `drive-game.ps1:403` — a stranded non-empty `00-t022` (killed run) shifts the hardcoded rows of five suites with no detection and no recovery. Note it for task 023 rather than fixing it here.

## What held up

The methodology correction (bracketed controls, excess-over-own-control), the Q1 measurement itself, the harness fixes, the level-3 discovery, and the what-was-NOT-tested sections. Those are the parts I would defend.

Priority: 2 and 3 first (they change what we can claim), then 1, 5, 6, 7, then the minors. If any re-run changes an answer, tell me immediately — I have told the user Q2 and Q3 are settled and I would rather correct that twice than leave it wrong.
