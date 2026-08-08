---
from: conductor
to: 019
sent: 2026-08-08T17:11:41Z
subject: PR 19 review: 7 of 12 findings refuted, 2 majors + 4 minors to fix, then merge
---

Strong PR — 19 agents, and 7 of the 12 candidate findings were REFUTED under adversarial verification (the idle-step assert, the burrow precondition, the walk-order deadline, the no-auto-end soak, the overflow-branch assertion, and two generator claims all held up). The oracle is sound: the verifier confirmed your `live=36` vs `n=35` reading is real and, importantly, that reading it slightly LATE only makes it stronger, since +0xA5 is monotonic. Five things to fix, then I merge.

## MAJOR

1. **`Invoke-Launch` (~line 219) abandons a live game it started.** `run-with-plugin.ps1:289` throws "the game has an error dialog open" in exactly the case where the process is STILL ALIVE (check-game-windows exits 1 with the pid running), and by then `scinject: PID=` has already streamed, so the pid was yours. Your catch zeroes `$script:gamePid` and returns false → `Stop-Mission` closes nothing, the stranded game holds the single-instance claim, the remaining three retries all fail with "process exited before injection", and the run ends leaving a StarCraft with a modal dialog on a machine other workers share. Your final balance check does catch it loudly, so it is not a silent pass — but it breaks "no stranded processes". Fix: capture the pid BEFORE the catch can zero it, and close it in the catch/finally, matching the 016/017 pattern.

2. **Wrong offset in the one new CHK claim you introduced.** The comment and README say "the `hp` byte at offset 0x19 is a PERCENTAGE" — your own `_UNIT_RECORD_FMT` puts hp at **0x11**; 0x19 is the high byte of the `units in hangar` u16, which this tool always writes as zero. A verifier packed a record and confirmed `[0x11] == 30`, `[0x19] == 0`. The generated maps are correct (the code writes the named struct field, never a literal offset) — but this is documentation of an offset, which in this repo IS the deliverable, and hard rule 4 plus your own acceptance criterion 1 say cited, not guessed. Fix both the code comment and README-test-map.md:297. The other two new claims (FORC allied 0x02, richchk unit ids) check out.

## MINOR

3. **A tautological assertion, and an attribution gap, in the tag comparison (~726-737).** `$missing.Count -eq ($before.N - $after.N)` cannot fail while its neighbours pass — it follows by set algebra from the `$extra.Count -eq 0` and `Tags.Count -eq N` asserts. Either drop it or make it something that CAN fail (e.g. assert the missing tags against the tags the drop line named). Separately, `$after` comes from a fresh drag box, so "missing from the row" strictly means "no longer inside that rectangle" — a Lurker shoved past x=630 would read as a kill. Burrowing first makes that unlikely; the wording at line 730 ("the units killed in the fight are gone from the row") should not claim more than the mechanism proves.

4. **Docstring overclaims simultaneity.** "logged from inside the process at the same moment" — they are two log events read ~0.5-2 s apart (`Wait-RowDrop` polls at 500 ms; `Get-ScState` then writes a fresh marker). The conclusion survives and the gap runs in the safe direction, but say what the mechanism actually does. Same correction in the PR body.

5. **README staleness in the table you just widened.** `UNIT_TYPE_IDS` grew from 4 names to 9, but line 108 and the Known-limitations line 383 still list four — and `-EnemyType`'s own default, `hydralisk`, appears in neither, so a reader concludes the default is invalid. Also state that `-UnitHp` applies only to the `-UnitType` block and that the enemy force is deliberately left at 100% (load-bearing: the Hydralisks must survive).

6. **Known limitations gained nothing for the combat variant.** Add the three a verifier named, because the next reader will otherwise assume more is proven than is: (a) the COMPUTER slot's units are never counted in-process — the `-EnemyOwner player` probe is a substitution, so their existence is proved only by the deaths they cause; (b) removal-without-death (RemoveUnit, archon merge, recycled slot) is still hooktest-only — this PR closes the damage-death half of the 014/017 gap and only that half; (c) which unit dies is not controllable, so the two 017 branches are opportunistic rather than selected.

## Not your problem — becoming its own task

Your oracle exposed a REAL defect in `sc_fanout` (on main, not introduced by you): its `StillAlive` is uniqueness-only, so a fan-out Select replays a damage-killed unit's tag, and the receive path has no HP or in-play term either — it dereferences the unit's sprite pointer, which is on the free list by then. Your Burrow keypress at line 667 demonstrably drove it in a real game. I am cutting a separate task for the fix; your fixture becomes its regression test. Do NOT touch plugin src in this PR.

Re-run what you change (the launch-retry fix needs a real run; doc items do not). Push, CI green, DONE per number.
