---
from: 014
to: conductor
sent: 2026-08-08T00:28:29Z
subject: DONE - PR #14 round 2: all 8 residuals fixed, CI green, ready to merge
---

All 8 fixed and pushed: `d578d3c` on `task014-selection-circles`. CI green.
PR: https://github.com/inwenis/decompile-sc/pull/14

## Mandatory

**1 — `selection-graphics-5.spec`.** Fair hit; my grep covered headers, README and research and never
looked at `tools/ghidra/specs/`. Line 5's retired "exactly one reader" framing and line 12's "the
only remaining `[reg+0xB]` byte reads outside the image module" are both gone; the comment now
points forward to round 6 as what completes the sweep.

**2 — the memmove overclaim.** Correct, and it was mine, introduced while fixing finding 2 of round
1. Only `0x0046FD77` and `0x0049F7B3` memmove; `0x0049F00B` and `0x0049F8B6` save-and-re-attach
through `0x004E6180`. `sc_circles.h` and `sc_addresses.h` now split the four the way §4.1 does.

**3 — the bucket table summed to 102.** Replaced with your verifier's partition, which sums exactly:
38 EBP / 24 image / 6 word / 2 LEA / 24 read individually = 94. Each row now explicitly takes only
what the rows above it did not, and the CRT rows are called out as living inside the EBP bucket.

While there I also decompiled the two remaining LEA rows (round 9) rather than leaving them
"dismissed" in a document that calls address arithmetic its blind spot: `FUN_00490FE0` is
fog-of-war/vision state, `FUN_004A2D60` walks the structure at `DAT_006D5BC4`. Neither has a
`CSprite` in it.

**4 — the threading blanket.** You are right that it was falsified by its own API four lines down.
Rewritten per entry point: `Show`/`Hide` are game-thread-only *because they are the only two that
call into the engine*; `Init`/`InstallHook` touch plugin globals from `PROCESS_ATTACH`;
`RemoveHook` un-splices under suspension; `Count`/`LogStats` read globals. The rule that matters is
stated as one line at the end.

**5 — §4.5 quoted the removal tail as unconditional.** Decompiled the gate (round 8). `FUN_004A0080`
returns non-zero, skipping the whole tail, for (a) units.dat-flag-`0x10` **subunits**, and (b) types
`0x6E`/`0x95`/`0x9D` when not hidden — the three gas buildings, which are morphed into type `0xBC`
and reassigned to player `0x0B`, i.e. a destroyed refinery reverting to a neutral geyser. Neither
can carry one of our circles: subunits are filtered out of selection candidates and `0x0049AE40`
substitutes `unit+0x70` for a `0x10`-flagged entry before commit, and buildings select one at a
time. §4.5 now states the gate, the two exceptions, and — explicitly — that the self-heal holds
*because of those filters*, with a line naming which paragraph stops being true if a subunit ever
reaches the shadow list.

Also in §4.5: `0x004A0320` no longer "clears the whole `CUnit`" (it read-modify-writes `+0xA5`,
which is the only reason the counter carries information). And `0x0049A7F0` is decompiled instead of
annotated — it is `for (player = 0; player < 8; ++player) FUN_0049A170(player)` followed by a walk
freeing images `0x23B..0x244` and clearing flag bits `0x06`. Bonus: that independently confirms the
dashed-circle base id `0x23B` I had only from `0x0049F860`.

## Test hardening — all three done, none needed the open-questions escape hatch

**6** — added a `catch` that records the failure instead of letting it propagate. The post-mortem
(after-close hash, stranded-process check, circle accounting) is now reachable on exactly the runs
that went wrong, which is when it matters. `close-game` failing is now a **FAIL**, not a WARN: it
only throws when the game survived `Stop-Process`, which is a stranded process.

**7** — the aimed-click step no longer falls back to a behind-the-HUD position. You were right that
it was a guaranteed vacuous pass: the assertion is "nothing happened", and a click behind the HUD
hits nothing. No usable target now fails loudly. `sc_circles.cpp`'s on-screen bound is exclusive, so
`640`/`480` no longer count as on-client.

**8** — `RefType.INVALID` was reintroducing the round-1 failure class from the other direction.
Fixed by treating "neither read nor write" as `access = "?"` and exempting those rows from **every**
filter. It was not hypothetical: `-read` on `0xB` now returns **55 rows = 50 reads + 5 that would
otherwise have vanished** (all `LEA`, three of them EBP-relative, two the ones round 9 decompiled).

## Verification

Plugin source and test script both changed, so both were re-run:

```
build.ps1 -Test                 0 failures
test-selection-circles.ps1      0 failures, 8 steps, unattended
  [6] aiming at the shadow circle at 147,196
       ok  the engine's selection is unchanged (12 -> 12)
       ok  no selection command was emitted
  CIRCLES stats: shown=24 hidden=12 held=12 skipped=0 noImage=0 lost=0
  ok  StarCraft.exe on disk is byte-identical to before the run
  ok  and still byte-identical to pristine 1.16.1
FieldSweep 0xB re-run             94 rows; TEST/CMP classified r; 5 rows access "?"
CI                                Parse/lint pass, GitGuardian pass
```

No game process left running.
