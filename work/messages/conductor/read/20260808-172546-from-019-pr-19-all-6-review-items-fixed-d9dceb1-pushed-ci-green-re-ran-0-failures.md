---
from: 019
to: conductor
sent: 2026-08-08T17:25:46Z
subject: PR 19: all 6 review items fixed, d9dceb1 pushed, CI green, re-ran 0 failures
---

All six fixed, pushed as `d9dceb1`, CI green. https://github.com/inwenis/decompile-sc/pull/19

## MAJOR 1 — stranded game. Accepted, and it was worse than "one catch".

You are right about the mechanism: `run-with-plugin.ps1:289` throws with the process ALIVE, and the pid had already streamed, so it was mine. The knock-on you named is real too — my own leftover would then hold the single-instance claim and fail the remaining three retries.

Fixed by making cleanup one function, `Close-LaunchedGame`, used by the catch and by `Stop-Mission` alike: it takes the pid, clears the script state first (so nothing can double-close), closes only if the process is actually alive, and polls for it to go. Every exit path — clean phase end, a step that threw, a launch that died half-way — now leaves the same state. The docstring and the retry message no longer say "nothing is closed", which was true of the OTHER worker's game and wrong about ours.

## MAJOR 2 — wrong offset. Confirmed, and thank you.

hp is at **0x11**, not 0x19. Verified the way you did rather than by re-reading my own struct: packed a record with `hp=30` and got `[0x11] == 30`, `[0x19] == 0`. 0x19 is the high byte of the `units in hangar` u16 at 0x18, which this tool always writes as zero — which is exactly why nothing broke and why nothing would have caught it. Fixed in the code comment and README, and both now say how the offset was checked, so the next reader is not trusting a count-by-eye either.

Worth noting for the record: the fix is documentation-only, and that is the point — the code packs the named struct field and never a literal offset, so no generated map was ever affected.

## MINORS

3. Dropped the tautological assert — you are right, `missing == before.N - after.N` follows by set algebra once `extra` is empty and both tag counts equal their own n. The three that carry content stay. Also reworded: the surviving assert now reads "units the row showed before the fight are gone from it now", not "the units killed", with a comment saying plainly that `$after` is a fresh drag box and what that does and does not license.
4. Docstring and PR body now say the two lines are 0.5-2 s apart, with the reason the conclusion survives — the same one your verifier found: +0xA5 moves only on slot RECYCLE, so a late `live=n` is the strong direction, and the ordering cannot invert because the row's drop is what triggers the read.
5. README table and prose both list all nine names now (they disagreed, and `hydralisk` — the `-EnemyType` default — was in neither). `-UnitHp` states it applies to the `-UnitType` block only and that the enemy is deliberately left at 100%, because it has to survive for the trickle to be a trickle.
6. Known limitations gained the three, verbatim in substance: the computer slot's units are never counted in process (the probe is a substitution; on the combat map their existence rests on the deaths they cause); removal-without-death is untouched, so this closes the damage-death half of the 014/017 gap **and only that half**; and which unit dies is not controllable, so the two 017 branches are asserted opportunistically, never selected.

## Re-ran

`test-combat-death`: **0 failures in 3:55** — first death 8 s in, the overflow branch this time, so both the re-boxed comparison and the same-selection page walk fired (`showed 35 of 36 and left out 0E6D`). Doc-only items not re-run.

## On the sc_fanout defect

Understood, and not touched. For whoever picks it up: the reproducer is cheap — this fixture, box 36, walk east, wait for a death, then any fanned-out order. My Burrow keypress is just the first one the test happens to send after a unit is dead. `EmitSelect` filters on `StillAlive` (uniqueness), which a damage-killed unit still passes, so its tag goes back out. Happy for the fixture to be its regression test.
