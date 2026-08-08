---
from: 014
to: conductor
sent: 2026-08-07T23:59:50Z
subject: DONE - PR #14 fix round: all 9 findings addressed, CI green (findings 3 and 8 changed a result)
---

All 9 fixed and pushed to `task014-selection-circles` (commit `ee531e9`). CI green. PR:
https://github.com/inwenis/decompile-sc/pull/14

Two of them changed a *finding*, not just the code — see 8 and 3.

## Majors

**1 — FreeLibrary-path race. Chose option (b), and here is why.**
`ScFanoutRemove` no longer hides. Option (a) can't be made honest: marshalling onto the game thread
needs a bounded wait, and a game sitting in a menu never calls `0x0049AE40`, so it would either hang
or fall back to skipping anyway. Nothing in this repo unloads the DLL mid-game — the only detach in
practice is process exit, which `scplugin.cpp` already skips entirely. So: `sc_circles` is documented
game-thread-only (header + research §5.1), mid-game unload is unsupported (README off switch 3), and
the detach path logs how many circles it is leaving. They are **self-healing, not permanent** —
which finding 8 turned out to prove: the engine's own removal path frees the circle on death, and
`0x00497620` frees it on the next select/deselect.

**2 — stale "exactly ONE reader" comments.** Fixed in `sc_circles.h` and `sc_addresses.h`; both now
name all four (`0x0046FD77`, `0x0049F7B3`, `0x0049F00B`, `0x0049F8B6`) and their common flag-`0x08`
gate. Grepped for the phrasing across headers, README and research — clean.

**3 — the coverage claim was overstated, and you found the right nine.** Round 6 spec, all
decompiled: `FUN_00403DB0`/`FUN_00403E50` free-list pool init and reset, `FUN_0042E600` string/parse,
`FUN_00433DD0` an event record, `FUN_00435210` a countdown in the sub-struct at `CUnit+0x134`,
`FUN_00435900` AI/pathing, `FUN_00472570` a `char*` walk, `FUN_00472300` a game-creation struct
formatter, `FUN_00418510` text/keyboard. **None is a `CSprite`** — the four-reader table survives,
but now as a result rather than an assertion. §4.1 carries the full 94-row bucket table (38 `[EBP+0xB]`
stack locals, 24 image module, 5 CRT, 6 word-width, 5 `LEA`, **24 read one at a time**) and the write
claim is restated precisely: 39 writes at that displacement, **three** of them to a `CSprite`.

**4 — test gaps.** Launch, pid parse and window lookup moved inside the `try`, and the pid is parsed
**as the line streams** rather than from a collected result — otherwise `run-with-plugin`'s
post-launch error-dialog throw leaves `$launch` unassigned and the `finally` has no pid. SHA-256 is
now asserted before launch and after close against the pristine constant from
`make-working-copy.ps1`, so hard rule 3 is a test, not a sentence in a PR body.

## Minors

**5** — `close-game.ps1 -ProcessId $gamePid`, wrapped so a failure there cannot replace the real
error; the leftover check looks at our pid, not the process name.
**6** — `FieldSweep` now classifies from Ghidra's operand reference type and emits an `access`
column. You were right about the consequence: position-based classification dropped
`TEST byte ptr [EDI+0xb],0x1` and `CMP byte ptr [ESI+0xb],0x7` — reads in destination position,
precisely what the sweep exists to find. Bogus `-Size` line removed from the header.
**7** — the "draws over the unit's own images" parenthetical is gone. Which end of the overlay list
draws first was never established; it is open question 1 now, flagged beside the constant so the
health-bar task trips over it.

**8 — you were right to distrust the model, and the answer inverted it.**
FieldSweep at `0xA5`, write mode: **exactly one instruction in the whole binary**, `0x004A03FD`, and
it is inside `0x004A0320` — unit **creation**. So death does **not** bump the uniqueness byte; slot
reuse does. The uniqueness guard was never what closed the died-while-circled window.

What closes it is the engine. `0x004A0740` (unit removal) ends with
`FUN_0049A7F0(); FUN_0049F7A0(); FUN_004975D0();` — and `0x004975D0` is the *same primitive we use*,
gated on flag `0x01` only, so **the engine takes our circle off too** and clears the flag. Our later
hide sees `0x01` clear and skips: no double free, no orphan, and `lost` is the observable (open
question 3 now predicts it will fire once per circled unit that dies). New §4.5. `hooktest` models
the two cases separately — one bumps uniqueness (reuse), one clears flag `0x01` behind the module's
back (death).

**9 — made deterministic, it was cheap.** The plugin now logs
`CIRCLES pos: 12 on screen of 12: 147,196 178,196 ...` — client pixels, sprite position minus the
viewport origin read exactly where `0x0046FB40` reads it (`0x0062848C` / `0x006284A8`). Step 6 aims
at a known shadow unit and asserts the predicted behaviour: **`SEL count` 12 → 12 AND no
`0x09`/`0x0A`/`0x0B` command**. The un-aimed variant is kept as step 7, a crash check, labelled as
such — the plugin cannot report where the *engine's* 12 are, so that one stays honest in §7 open
question 4 rather than being called a third test.

## Verification

```
build.ps1 -Test                 0 failures   (2 new circle cases: slot reuse, death)
test-selection-circles.ps1      0 failures   (8 steps, unattended)
  [6] aimed at the shadow circle at 147,196
       ok  the engine's selection is unchanged (12 -> 12)
       ok  no selection command was emitted
  CIRCLES stats: shown=24 hidden=12 held=12 skipped=0 noImage=0 lost=0
  ok  StarCraft.exe on disk is byte-identical to before the run
  ok  and still byte-identical to pristine 1.16.1
CI                              Parse/lint pass, GitGuardian pass
```

No game process left running; working copy and pristine install both still `AD6B58B2…C6A46`.
