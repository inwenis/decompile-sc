---
from: 024
to: conductor
sent: 2026-08-09T19:16:02Z
subject: Box-select building gate found; design chosen (proceeding)
---

# 024 — the gate, and the design I am building

## The gate, from this binary (Ghidra 12.1.2, persistent project over
## C:\sc-work\1161-base\StarCraft.exe, SHA-256 AD6B58B2...88C6A46)

There are **two** gates, not one, and both are `unit_IsStandardAndMovable` (`0x0047B770`).

**A - client side, inside `SortAllUnits` (`0x0046F0F0`).** A candidate is only stored into
`out12` if the predicate passes:

```
0046F1A3  CALL 0x0047b770
0046F1AA  JZ   0x0046f223
0046F223  MOV  dword ptr [EBP + -0x8],ESI     ; remember THIS rejected unit (last wins)
```

A building fails the predicate, so **no building is ever added to the list**. The tail is
where the "exactly one" comes from:

```
0046F242  MOV  EAX,[EBP-0x4]      ; how many were accepted
0046F248  JNZ  0x0046f286         ; any accepted -> return them, fallback DISCARDED
0046F27A  MOV  EAX,EDX            ; EDX = the LAST rejected candidate
0046F27F  MOV  dword ptr [EDX],EAX
0046F281  MOV  EAX,0x1            ; ... and return a count of ONE
```

So: buildings are filtered out entirely, and if that empties the list the engine
substitutes **one** of them. That is why a box over six Supply Depots selects one, and why
a MIXED box selects only the units - any movable unit makes the count non-zero and the
fallback is never used.

**B - simulation side, `addUnitToSelectionSlot` (`0x0049AF80`)**, called from
`CMDRECV_Select` at `0x004C2801` with `EBX` = *how many have been accepted so far* (it is
`INC EBX` at `0x004C2810`), i.e. EBX is the slot:

```
0049AF97  TEST EBX,EBX
0049AF99  JLE  0x0049afb5        ; slot 0 -> no gate, anything may be selected alone
0049AF9D  CALL 0x0047b770        ; slot > 0 -> must be standard-and-movable
0049AFA4  JZ   0x0049afb2        ; ... else refuse the slot
```

`playersSelections[player]` is what every order applier iterates
(`getActivePlayerNextSelection` `0x0049A850` reads `(&DAT_006284e8)[iter + player*0xc]`),
so gate B is the one that decides whether an order reaches more than one building.

`unit_IsStandardAndMovable` itself, decompiled (this answers selection-cap.md section 8
q9): it fails on `unitsDatFlags[unitId] & 0x01` (Building) or `& 0x800`, on
`CUnit+0xDC & 0x400`, on non-zero `CUnit+0x117 / +0x119 / +0x124`, and on a list of unit
ids (`0x0D`, `0x24`, `0x59`, `0x5A`, `0x5D`-`0x60`, `0x69`, `0xCA`, `0xCB`-`0xD5`).

## Design I am building (cheapest that works; proceeding on it)

**"The unit fan-out path with the box-select filter relaxed" - plus one generalisation.**
Not a new path. Concretely:

1. **Relax gate A only for the drag box, only for a same-type group.** The plugin already
   detours `SortAllUnits` (evidence-logging only today). After the original returns, if
   `clicked == 0` (only `0x0046FA40`, the drag box, passes 0), the count is 1, and that one
   unit fails `unit_IsStandardAndMovable`, re-walk the candidate list and append every
   candidate with the **same unit id and same owner**, up to the caller's 12 slots. Extras
   go into the existing overflow accumulator. A mixed box never reaches this branch.
   The engine then does the rest natively: `CreateNewUnitSelectionsFromList` (`0x0049AE40`)
   attaches a selection circle to each, the HUD row fills, and `CMDACT_Select` sends all N.
   **We never write `CSprite::selectionIndex` and never set sprite flag `0x08`** - the
   engine sets them itself, for a normal N <= 12 selection.

2. **Gate B is NOT patched.** Its first five bytes contain a short `JZ`, and this repo's
   hook engine copies prologue bytes verbatim with no relocation, so a detour there would
   be unsafe. Instead the existing fan-out handles it: the simulation can hold exactly ONE
   building, so the fan-out's chunk size becomes **1** for a building group instead of 12.
   That is a small generalisation of `ChunkBounds`/`StartFanout` - "chunk = how many of
   these the sim will hold" - and is byte-identical to today's behaviour for units (12).
   The trigger changes from `shadowCount > 12` to `shadowCount > simSlots` for the same
   reason.

3. **Liveness is task 020's gate, unchanged.** Every emitted Select still goes through
   `EmitSelect` -> `PassesGate`, so a destroyed building is dropped from the wire; the
   append in (1) applies the same gate before it puts a building in the list.

Scope, stated: SAME-TYPE only. A mixed box stays stock (units win, buildings ignored).
Single-click and ctrl+click on a building stay stock (they call `SortAllUnits` with
`clicked != 0`). Shift+box onto an existing selection stays stock, because
`combineSelectionsLists` (`0x0046F290`) refuses the merge when either side fails the same
predicate. SINGLE-gated commands (build, etc.) still act on one building, exactly as they
do for a >12 unit selection today.

Oracle for the in-game test: right-click sets a building's rally point into
`CUnit+0xF8/+0xFA` (map x,y) and `+0xFC` (target unit) - the `0x27` branch of the Right
Click applier `0x004560D0`. So "the order reached all N" is asserted per building from
those fields, not from the picture.
