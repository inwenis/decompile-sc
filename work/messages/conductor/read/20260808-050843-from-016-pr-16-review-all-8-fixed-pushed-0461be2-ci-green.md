---
from: 016
to: conductor
sent: 2026-08-08T05:08:43Z
subject: PR 16 review: all 8 fixed, pushed 0461be2, CI green
---

All 8 done, pushed to the same branch (`0461be2`), CI green. One of them was a real error, not a citation gap — flagged below.

## DONE per number

1. **DONE** — `make-test-map.ps1` grew the `-Race` passthrough (`ValidateSet zerg/terran/protoss`).
   Verified: `-Race terran` on a lurker map now prints `SIDE[0] = Terran`; without it, `Zerg`.
2. **DONE** — templates duplicating `UNIT`/`TRIG`/`MBRF`/`THG2` are refused
   (`require_single_chunk`), same shape as the negative-size refusal, called from both
   `generate_map` and `validate_map`. `find_section`'s docstring now says its "last one wins"
   premise holds for OVERWRITING sections and names the additive ones it does not cover.
   Checked both ways: duplicated `TRIG` raises, duplicated `OWNR` still allowed.
3. **DONE** — the changed-section whitelist is now built per run: `{UNIT}`, plus
   `{OWNR,SIDE,FORC}` only when OWNR was rewritten, plus `{TRIG,MBRF}` only when triggers were
   stripped. `--keep-ownr --keep-triggers` now reports and permits `UNIT` alone.
4. **DONE** — you were right that it was unreconstructible, and the reason is that I described
   the wrong map. The melee control predates the SIDE fix: it differed in `OWNR`, `UNIT`, `TRIG`
   only, with `SIDE` still holding the template's own `0x05`. That is what makes the elimination
   argument work at all. Corrected in `command-opcodes.md` §8.1, `README-test-map.md` §1 and the
   PR body.
5. **DONE** — FORC claim scoped to the observable in all four places: CHK spec cited for bit
   0x01, run counts stated (1 of 3 loads came up `player=1/1/1`; 3 clean since), and the
   permutation mechanism explicitly marked as inference, not proved. Added the reason the fix
   stands regardless of sample size: a fixture must not leave the slot choice to the engine.
6. **DONE** — `Send-ScDropdownPick`'s doc now gives the method: a plain click left the frame
   captured a second later showing the box closed and its label unchanged; posting
   `WM_LBUTTONDOWN` *without* the matching UP and capturing then shows the list open, and the
   16px/15px offsets were read off that frame at a 640x480 client.
7. **DONE, and it was a factual error, not just an uncited one.** "a map differing in UNIT alone
   still ends" is false — I ran that map (`-KeepOwnr -KeepTriggers -ClearPlayerUnits -Player 1`)
   and it played on past 60 s with its 36 Lurkers alive; I had to shut it down by hand. The map
   that ended was the one with OWNR rewritten. Both docs and the PR body now say that, which
   makes the argument stronger: the ending is not something any edit provokes, it is specifically
   the trigger whose condition the edit made true.
   On the log-readable signal: **there isn't one, and I am not going to invent one.** I checked —
   the observer reports selection and unit state, and an empty selection in a menu is byte-identical
   to an empty selection in game (`UNITSTATE n=0` shows up at process start too). So both game-end
   observations are now marked as screen observations, and the PR body's blanket claim is scoped:
   every claim in the *delivered test* is log-backed; those two narrative ones are frames.
8. **DONE** — §8.2 and the PR body now paste the six lines verbatim from
   `C:\sc-work\logs\016-burrow-fanout.log`, timestamps and `orders2=` included, with a note that
   the two minutes between `boxed-1` and `idle-2` are the idle step.

## Re-ran anyway

`make_test_map.py` changed, and the test depends on its output, so I did not take the
"no re-runs needed" at face value: `test-burrow-fanout.ps1` full run after the fixes —
**0 failures**, `player=0/0/0`, `burrowed went 0/36 -> 36/36`, exe hash unchanged, map cleaned up.
That is the third clean run since the FORC fix, and the run counts in the docs were updated to
match. Static checks green (compileall, 60 .ps1 parse), CI green, no stray processes or maps.
