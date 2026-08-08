# Selection circles in StarCraft 1.16.1 — how they are drawn, and how to draw one ourselves

Survey date: 2026-08-07/08 (task 014). Target: the `StarCraft.exe` in the disposable working copy,
SHA-256 `AD6B58B27B8948845CCFA69BCFCC1B10D6AA7A27A371EE3E61453925288C6A46`, 1,220,608 bytes —
byte-identical to the pristine install and unchanged by every run below.

Everything here was read out of **this binary**. Nothing is inherited. Where a claim overlaps prior
art ([`selection-cap.md` §2.4](selection-cap.md), quoting BWAPI and GPTP) that is noted as
corroboration, and where prior art is **wrong for this binary** that is called out explicitly.

Companion documents: [`selection-cap.md`](selection-cap.md) for why the cap is 12 and what it costs
to raise; [`command-path.md`](command-path.md) for the command funnel the fan-out uses;
[`binary-selection-map.md`](binary-selection-map.md) for the selection globals.

---

## 1. Verdict up front

1. **A selection circle is not a flag the renderer consults. It is an IMAGE.** The engine allocates
   a `CImage` with draw function `0x0D` and an id in `0x231..0x23A` (ten sizes) and links it into
   the sprite's overlay list. Sprite flag `0x01` is only the bookkeeping bit that says "one is
   attached". [§3](#3-what-happens-to-a-unit-when-it-becomes-selected)
2. **So a plugin does not have to reimplement anything.** It can call the engine's own attach
   (`0x004D7070`) and remove (`0x004975D0`) primitives on the units the 12-cap threw away. That is
   what task 014 does, and it is a much smaller change than the "set the flag ourselves" route the
   task proposed. [§5](#5-the-implementation)
3. **The prior-art offsets are half right.** `CSprite::selectionIndex` really is at `0x0B`, as
   [`selection-cap.md` §2.4](selection-cap.md) quoted — but **`flags` is at `0x0E`, not `0x06`**.
   BWAPI's `CSprite.h` omits the two linked-list pointers this binary puts at the front of the
   struct, so every field from `spriteID` onward is shifted by 8. [§2](#2-csprite-in-this-binary)
4. **The `selectionIndex` hazard is real, and it is worse than "pick a safe value" — there is no
   safe value.** Four instructions read the field. Every one of them uses it as a `memmove` offset
   into a 12-entry stack array. A value ≥ 12 makes the length negative and smashes a 48-byte stack
   buffer; a value of 0..11 is in bounds but silently deletes a *different, genuinely selected*
   unit. [§4](#4-the-selectionindex-hazard-settled)
5. **All four readers sit behind the same gate: sprite flag `0x08` ("selected").** The plugin
   therefore never sets `0x08` and never writes `selectionIndex` at all. The field is never read for
   our units, so it never has to hold anything. That is the whole of what task 014 "did about
   selectionIndex". [§4.3](#43-what-this-task-did-about-it)
6. **The engine already models "has a circle but is not selected".** `0x0049F860` (sprite rebuild)
   saves flag `0x01` independently of flag `0x08` and restores the circle on its own if only the
   former was set. The state the plugin creates is one the engine maintains for itself.
   [§4.4](#44-corroboration-the-engine-already-maintains-this-exact-state)

---

## 2. `CSprite` in this binary

### 2.1 The layout

Recovered from the instructions that use it, not from a header. Each row names an instruction in
this binary that proves the offset and the width.

| Offset | Field | Width | Proof |
|---|---|---|---|
| `0x00` | `prev` | 4 | list walks in `0x004975D0` (`MOV ESI,[ESI]` chains) |
| `0x04` | `next` | 4 | same |
| `0x08` | `sprite_id` | 2 | `0x004D6810` indexes `DAT_00665A3E[sprite_id]` and `DAT_00665F56[sprite_id]` off `[EAX+8]` |
| `0x0B` | **`selectionIndex`** | 1 | written `0x004E61D6` `MOV byte ptr [EDI + 0xb],CL`; read `0x0046FD77` |
| `0x0C` | `visibility_mask` | 1 | `0x0046F3A0`: `DAT_0057F0B0 & [sprite+0x0C]` — the fog/vision test |
| `0x0D` | `elevation` | 1 | `0x0046F3A0`: `if ([sprite+0x0D] < 5)` in the draw-order comparison |
| `0x0E` | **`flags`** | 1 | `0x004E61A3` `TEST byte ptr [ESI + 0xe],BL`; `0x004975D0` `MOV AL,byte ptr [ECX + 0xe]` |
| `0x0F` | `selection_flags` | 1 | saved/restored across a rebuild in `0x0049F860` |
| `0x10` | `index` | 2 | `0x0046F3A0` draw-order comparison uses `[sprite+0x10]` as the low bits |
| `0x12`,`0x13` | `width`, `height` | 1,1 | `0x0046F3A0`: `[sprite+0x13] * [sprite+0x12]` as a size for the smallest-unit tie-break |
| `0x16` | `position.y` | 2 | `0x0046F3A0` draw-order comparison |
| `0x18` | `main_image` | 4 | `0x004E6140` reads `[[unit+0x0C]+0x18]` then that image's fields |
| `0x1C` | `first_overlay` | 4 | `0x004D6420` links a new image in at `[sprite+0x1C]` |
| `0x20` | `last_overlay` | 4 | `0x004D7070` links a new image in at `[sprite+0x20]` |

`CUnit+0x0C` is the `CSprite*`; every function above reaches the sprite that way.

> **Correction to prior art.** [`selection-cap.md` §2.4](selection-cap.md) quotes BWAPI `CSprite.h`
> and GPTP `structures/CSprite.h` for `selectionIndex` at `0x0B` — correct — but those headers put
> `flags` at `0x06`. In this binary `flags` is at **`0x0E`**. Both published layouts start the
> struct at `spriteID` and place `pPrev`/`pNext` at `0x0C`/`0x10`; the binary puts the list pointers
> first, which moves everything else forward by 8 and happens to leave `selectionIndex` where the
> headers say. Anyone who trusted `0x06` for the flags byte would be reading `sprite_id`'s high half.

### 2.2 The flag bits we use

| Bit | Meaning | Proof |
|---|---|---|
| `0x01` | a selection-circle image is attached | `0x004975D0` clears exactly this bit and frees exactly the `0x231..0x23A` image; `0x004E61C5` sets it only when `0x004D7070` returned non-NULL |
| `0x08` | "selected" | `0x004E61D1` sets it beside the `selectionIndex` write; `0x00497620` clears it; it gates all four `selectionIndex` reads (§4) |
| `0x06` | a 2-bit counter of allied ("dashed") circles | `0x0049F860` reads `([sprite+0x0E] >> 1) & 3` and rebuilds that many `0x23B`-based images. Corroborates teippi's `DashedSelectionMask = 0x6` |

---

## 3. What happens to a unit when it becomes selected

`CreateNewUnitSelectionsFromList` (`0x0049AE40`, EAX = `CUnit**`, `__stdcall(count)`, RET 4) is the
client-side "replace the whole selection" funnel — 10 callers, covering the drag box, every click
path and control-group recall. It does exactly two things per unit:

```c
for (p = &activePlayerSelection; *p; ++p) { *p = 0; FUN_004E6290(/*EAX = unit*/); }   // detach
for (i = 0; i < count; ++i) { activePlayerSelection[i] = list[i]; FUN_004E6180(i); }  // attach
```

`FUN_004E6180` takes the **slot index** as its argument. That single fact is what makes it the right
function to read: it is where `selectionIndex` is written, and where whatever draws the circle is
created.

### 3.1 `0x004E6180` — attach selection graphics

EAX = `CUnit*`, one `__stdcall` byte argument (the slot), RET 4.

```c
sprite = unit->sprite;                                   // [unit+0x0C]
if (unitsDatFlags[unit->unitId] & 0x20000000) {          // Invincible (mineral field, geyser)
    if (!(sprite->flags & 1))
        if (FUN_004D7070(colourTable[unit->player], 0x231)) sprite->flags |= 1;
    sprite = unit->sprite;
    sprite->flags |= 8;
    sprite->selectionIndex = slot;
    return;
}
colour = colourTable[unit->player];                      // BYTE[0x00581D6A + player]
if (!(sprite->flags & 8)) {
    sprite->selectionIndex = slot;                       // 0x004E61FD
    sprite->flags |= 8;
    FUN_004D6420();                                      // overlay A -- the health bar
    if (!(sprite->flags & 1))
        if (FUN_004D7070(colour, 0x231)) sprite->flags |= 1;   // overlay B -- the CIRCLE
}
```

Two things are worth pulling out.

**The whole body is guarded by `!(flags & 8)`.** A sprite that already has that bit gets neither a
new index nor a new circle. That is what makes "set flag 0x08 yourself" dangerous in a second,
quieter way: a unit the plugin marked selected would be *skipped* when the engine genuinely selects
it, leaving a stale index and, if the plugin had since removed its own circle, no circle at all.

**Invincible units get overlay B and not overlay A**, which is how the two are told apart: a mineral
field draws a selection circle and no health bar.

### 3.2 Which overlay is the circle

`0x004D7070` — EAX = `CSprite*`, `__stdcall(colourByte, baseImageId)`, RET 8 — allocates an image
from the free list, links it at the sprite's `last_overlay`, and initialises it through
`0x004D6810`, which settles it:

```c
// 0x004D6810: EAX = sprite, ECX = the new image, args (colourByte, baseImageId)
image->image_id = baseImageId + spritesDatCircleIndex[sprite->sprite_id];   // 0x231 + 0..9
image->grp      = grpTable[image->image_id];
image->parent   = sprite;
image->yOffset  = spritesDatCircleOffset[sprite->sprite_id];
image->[0x30]   = colourByte;
image->drawfunc = 0x0D;
```

The base `0x231` plus a per-sprite-type size index lands in `0x231..0x23A` — ten consecutive image
ids, the ten circle sizes. The remover confirms the range independently:

```c
// 0x004975D0: ECX = sprite. The engine's own "remove just the circle".
if (!(sprite->flags & 1)) return 0;
sprite->flags &= ~1;
for (img = sprite->last_overlay; img; img = img->prev)
    if (img->image_id > 0x230 && img->image_id < 0x23B) { FUN_004D4FA0(); return img->colour; }
```

The other overlay, `0x004D6420`, links at `first_overlay` and its image has draw function `0x0B`;
`0x00497620` (the full deselect) removes that one and *then* the `0x231..0x23A` one. `0x0049F860`
rebuilds the allied/dashed circles from base `0x23B`, one per bit-pair, which places the whole
selection-graphics image block at `0x231..0x23B+`.

### 3.3 The primitives, as a table

| Address | Convention | What |
|---|---|---|
| `0x0049AE40` | EAX = `CUnit**`, `__stdcall(count)`, RET 4 | replace the client selection; detaches then attaches graphics |
| `0x004E6180` | EAX = `CUnit*`, `__stdcall(u8 slot)`, RET 4 | attach selection graphics + write `selectionIndex` + set flags `0x08`/`0x01` |
| `0x004E6290` | EAX = `CUnit*` | detach selection graphics (health bar + circle), clear `0x08`/`0x01` |
| `0x004D7070` | EAX = `CSprite*`, `__stdcall(colour, baseId)`, RET 8 | **attach one overlay at the tail** — with `0x231`, the selection circle. NULL if the image free list is empty |
| `0x004975D0` | ECX = `CSprite*` | **remove the selection circle only**, clear flag `0x01` |
| `0x00497620` | EDI = `CSprite*` | remove health bar + circle, clear `0x08` and `0x01` |

Prologues, patch windows and caller lists for all of these are in
`work/scratch/selhooks/*.asm` / `*.callers`, produced by
`tools/ghidra/specs/selection-circle-hooks.spec`.

---

## 4. The `selectionIndex` hazard, settled

[`selection-cap.md` §2.4](selection-cap.md) flagged this from GPTP's source: a memcpy length is
computed from `selectionIndex` when shift-clicking a unit out of the selection. Task 014's contract
asked what a safe value would be for a unit that is fan-out-selected but not engine-selected.

### 4.1 Every instruction that reads it

Found with `tools/ghidra/scripts/FieldSweep.java` (new in this task), which enumerates every
instruction whose operand is `[reg + 0x0B]` — a struct field has no address, so `XrefSweep` cannot
see it. That returns **94 candidate operands** (`work/scratch/selgfx6/disp0b.tsv`; 50 reads, 39
writes, the rest address-only `LEA`). They break down as:

They partition — each row takes only what the rows above it did not, so the counts add to 94 exactly:

| # | Bucket | Count | How it was dismissed |
|---|---|---|---|
| 1 | `[EBP + 0xB]` | 38 | a frame-pointer-relative byte is a stack local, not a struct field. (This bucket absorbs the 5 named CRT rows — `___sbh_alloc_block`, `__ismbcspace`, … — which are all EBP-relative too) |
| 2 | the image module, `0x004D5xxx`–`0x004D7xxx` | 24 | `CImage` also has a byte at `0x0B` (`direction`); these are all image-list code |
| 3 | `word ptr [reg + 0xB]` | 6 | 16-bit, so not this byte field at all |
| 4 | `LEA` | 2 | computes an address rather than accessing the field — **both read anyway**, see below |
| 5 | **everything else** | **24** | **decompiled and read, one function at a time** |
| | | **94** | |

Row 4 is only two rows, and leaving them merely "dismissed" would be having it both ways: this
document calls address arithmetic the sweep's blind spot, so a visible instance of it has to be
looked at. `FUN_00490FE0` (`LEA ECX,[EDX+0xb]`) is fog-of-war/vision state around `DAT_0057F0B0`;
`FUN_004A2D60` (`LEA EDX,[EAX+EDX*1+0xb]`) walks the structure at `DAT_006D5BC4`. Neither has a
`CSprite` anywhere in it (round 9, `work/scratch/selgfx9/`).

All 24 of the last row are accounted for. Nine of them were missed by the first draft of this
document and are the subject of round 6
(`tools/ghidra/specs/selection-graphics-6.spec`, `work/scratch/selgfx6/`): `FUN_00403DB0` and
`FUN_00403E50` initialise and reset an object free-list pool; `FUN_0042E600` is string/parse code;
`FUN_00433DD0` builds an event record; `FUN_00435210` decrements a countdown in the sub-struct at
`CUnit+0x134`; `FUN_00435900` is AI/pathing state; `FUN_00472570` walks a `char*`; `FUN_00472300`
formats a game-creation struct; `FUN_00418510` is text/keyboard handling. **None of them is a
`CSprite`.** `FUN_00458B30` and `FUN_00472500` (round 5) are likewise unrelated, and `FUN_004E6140`
and `FUN_00499210` read `CImage::direction` off an image, not a sprite.

That leaves, as the only instructions in the binary that touch `CSprite::selectionIndex`:

| Address | Function | What it does with the value | Guard |
|---|---|---|---|
| `0x0046FD77` | `0x0046FB40` — the click handler | `memmove(&list[i], &list[i+1], (n-1-i)*4)` on a 12-entry **stack** array, then `CreateNewUnitSelectionsFromList(n-1)` | `if (clicked->sprite->flags & 8)` |
| `0x0049F7B3` | `0x0049F7A0` — remove one unit from the client selection | the same memmove, same shape | `if (unit->sprite->flags & 8)` |
| `0x0049F00B` | `0x0049EFA0` — change a unit's owner | saves it, calls `0x004E6290`, re-attaches with `0x004E6180(saved)` | `if (unit->sprite->flags & 8)` |
| `0x0049F8B6` | `0x0049F860` — rebuild a unit's sprite | saves it, tears the sprite down, re-attaches with `0x004E6180(saved)` | `if (unit->sprite->flags & 8)` |

Of the 39 writes at this displacement, exactly **three** are to a `CSprite`: `0x004E61D6` and
`0x004E61FD` (both inside `0x004E6180`), plus `0x004997AE` in `0x004997A0`, a byte-identical copy of
`0x004E6180`'s inner block with **zero references** — a leftover the compiler did not fold away. The
other 36 fall into the buckets in the table above.

**Method limit, stated plainly.** A displacement sweep is a candidate list, not a proof of absence:
an instruction that computed the field address arithmetically (`LEA` then a later dereference, or a
base already advanced by 11) would not appear. Two independent things make that unlikely to matter
here — the sprite writes are as few as the reads and sit in one function, and the four readers found
are exactly the four operations that can move a unit out of a selection — but the negative is
**unfalsified, not proven**.

> **The read/write classifier was wrong twice, and both failures were the same class: silently
> dropping rows.** It first keyed off operand *position* ("operand 0 is the destination"), which
> dropped `TEST byte ptr [EDI+0xb],0x1` and `CMP byte ptr [ESI+0xb],0x7` — reads written in
> destination position, i.e. exactly the shape this sweep exists to find. The fix classified from
> Ghidra's operand reference type, but then dropped any row whose type claimed *neither* read nor
> write. On this displacement that is 5 rows, all `LEA`. `FieldSweep.java` now emits an `access`
> column (`r`, `w`, `rw`, `?`) and a `?` row passes **every** filter rather than none: `-read` on
> `0xB` returns 55 rows = 50 reads + those 5. A sweep that quietly under-reports is worse than no
> sweep, because the result still looks like an answer.

### 4.2 There is no safe value

Take the fan-out case: 12 units in `activePlayerSelection`, and the plugin has marked a 13th as
selected with index `i`. `0x0046FB40` runs:

```
n = 12                                   // units found in activePlayerSelection, capped at 12
n = n - 1 = 11
memmove(&list[i], &list[i+1], (11 - i) * 4)
list[11] = 0
```

`list` is 12 dwords — 48 bytes — on the stack.

- **`i >= 12`** (the unit's true position in a wide selection): `(11 - i)` is negative, and the
  length argument is a `size_t`. That is a ~4 GB `memmove` into a 48-byte stack buffer.
- **`i <= 11`** (any value the engine itself could have produced): in bounds, no corruption — and it
  **deletes `list[i]`, which is a real, genuinely selected unit**. The player shift-clicks unit A
  and unit B disappears from their selection.

Neither is acceptable, and there is no third option: the field is only ever consumed as an index
into a 12-entry array that our unit is not in. **That is the finding the task asked for — reported
rather than guessed at.**

### 4.3 What this task did about it

**Nothing. The plugin never writes `CSprite::selectionIndex`, and never sets sprite flag `0x08`.**

All four readers are behind `flags & 0x08`. A unit carrying only flag `0x01` never enters any of
them, so the field is never read for it and never has to hold a value. Concretely, for the four
operations:

| Operation on a shadow-circled unit | What happens |
|---|---|
| shift-click it | `0x0046FB40` takes the *other* branch (add-to-selection), finds the selection already holds 12, and returns. Identical to stock behaviour for a 13th unit |
| it is removed from the selection (`0x0049F7A0`) | returns immediately at the guard |
| its owner changes (`0x0049EFA0`) | the graphics save/restore block is skipped; the circle is untouched |
| its sprite is rebuilt (`0x0049F860`) | flag `0x01` is saved and the circle is rebuilt by the engine itself — see below |

This is enforced, not just intended: `hooktest.exe` part [8] poisons `selectionIndex` to `0xEE` on
every fake sprite and asserts, after driving the whole attach/detach state machine, that no byte
changed and that flag `0x08` was never set on any sprite.

### 4.4 Corroboration: the engine already maintains this exact state

`0x0049F860` rebuilds a unit's sprite (unit morph / type change). It saves the two bits separately
and restores them separately:

```c
wasSelected = (sprite->flags & 8) >> 3;
hadCircle   =  sprite->flags & 1;
dashedCount = (sprite->flags >> 1) & 3;
if (wasSelected) { savedIndex = sprite->selectionIndex; FUN_004E6290(); }
colour = FUN_004975D0();               // take the circle off, keep its colour byte
... rebuild the sprite ...
if (!wasSelected) {
    if (hadCircle && !(sprite->flags & 1))                       // <-- circle, no "selected"
        if (FUN_004D7070(colour, 0x231)) sprite->flags |= 1;
} else {
    FUN_004E6180(savedIndex);
}
```

The `!wasSelected && hadCircle` branch exists in the shipped binary. A sprite that carries a
selection circle without being selected is a state the engine writes code to preserve — so the
plugin is not inventing a configuration the data model does not support.

### 4.5 What actually happens when a circled unit dies

The plugin's stale-record guards (§5) were written against a *model*: "the engine bumps
`CUnit+0xA5` when a unit goes away, so a mismatch means the record is stale". That model was never
checked, and it turns out to be wrong in a way that does not matter — but only because something
else covers it.

**`CUnit+0xA5` is written by exactly one instruction in the entire binary**: `0x004A03FD`,

```c
unit->uniqueness = (unit->uniqueness + 1) & 0x1F;
```

and it lives inside `0x004A0320`, which is unit **initialisation on (re)use** — it resets the
CUnit's fields one by one, links the unit into `playerUnitList[player]` (`0x006283F8`) and gives it a
sprite. Note it *does not* zero the struct wholesale: `+0xA5` is read-modify-written by the line
above, which is the only reason the counter carries information at all. (FieldSweep at displacement
`0xA5`, write mode: one row, `work/scratch/selgfx6/dispA5.tsv`. The 5-bit mask is also why the wire
tag packs as `(uniqueness << 11) | index` — 5 + 11 = 16.)

**So death does not bump it. Slot REUSE does.** A unit that has died but whose slot has not been
recycled still carries its old uniqueness byte, and the uniqueness guard would not fire.

What closes the window instead is the engine itself. `0x004A0740`, the unit-removal path, ends with
this — **inside a guard**, which the first draft of this section wrongly quoted as unconditional:

```c
if (FUN_004A0080() == 0) {                   // <-- the gate; see below
    ...
    FUN_0049A7F0();     // drop the unit from all 8 players' selections, and take off the
                        //   dashed/allied circles (ids 0x23B..0x244)
    FUN_0049F7A0();     // drop it from the CLIENT selection   (guarded by sprite flag 0x08)
    FUN_004975D0();     // <<-- REMOVE THE SELECTION CIRCLE     (guarded by sprite flag 0x01 only)
    ...
}
```

`0x0049A7F0` is a loop `for (player = 0; player < 8; ++player) FUN_0049A170(player)` —
`removeUnitFromPlayerSelection`, the function §3 already quotes — followed by a walk of the sprite's
overlay list freeing any image in `0x23B..0x244` and clearing flag bits `0x06`. That both justifies
the label and independently confirms the dashed-circle image base `0x23B` seen in `0x0049F860`
(§4.4).

`0x004975D0` is the same primitive the plugin uses, and it does **not** consult flag `0x08` — so the
engine takes *our* circle off too, frees the image, and clears flag `0x01`. A later `ScCirclesHide`
then sees flag `0x01` clear, skips the unit, and counts it in `lost`. No double free, no orphaned
circle, and the counter is the observable.

**The gate, and why it does not break the argument.** `FUN_004A0080` returns non-zero — skipping the
whole tail — in exactly two cases:

1. the unit's type carries units.dat flag `0x10` (**Subunit**: turrets). It is unlinked from the
   player's unit list and returns 1.
2. the unit is *not* hidden (`sprite->flags & 0x20` clear) **and** its type is `0x6E`, `0x95` or
   `0x9D` — the three gas buildings. They are not removed at all; they are morphed into type `0xBC`
   and reassigned to player `0x0B`, i.e. a destroyed refinery reverting to a neutral vespene geyser.

Neither can be a shadow-circled unit. Subunits are filtered out of selection candidates
(`unit_isUnselectable` / `unit_IsStandardAndMovable`, [`selection-cap.md` §4.1](selection-cap.md)),
and `0x0049AE40` substitutes `unit+0x70` for a `0x10`-flagged entry before the selection is ever
committed; buildings can only be selected one at a time, so a gas building cannot be in a >12 box
selection. A hidden unit falls through the gate and the tail runs normally.

So the self-heal holds for every unit that can carry one of our circles — but it holds *because of
those filters*, not because the tail is unconditional. If a future change ever lets a subunit into
the shadow list, this is the paragraph that stops being true.

The guards therefore do close the window, but the load-bearing one is the **flag `0x01` check**, not
the uniqueness check. Uniqueness earns its place for the *other* case: a recycled slot, where
`0x004A0320` bumps the byte and hands the unit a fresh sprite, so both that guard and the
`unit->sprite == recorded sprite` guard fire.

`hooktest.exe` part [8] now models both cases separately — one test bumps the uniqueness byte (slot
reuse), the other clears flag `0x01` behind the module's back (death) — and asserts the survivor is
the only unit touched in each.

---

## 5. The implementation

`tools/plugin/src/sc_circles.{h,cpp}`. One hook, two calls.

```
0x0049AE40 CreateNewUnitSelectionsFromList   <- the client's "replace the selection" funnel
|
|  [OUR PRE-HOOK]  ScCirclesHide()             our circles come off FIRST, while the
|                                              engine's old ones are still on
|  detach loop over activePlayerSelection      the engine takes its own off
|  attach loop over the new list               the engine puts its own on
v
0x004C0860 CMDACT_Select                     <- the fan-out's existing hook
   [OUR HOOK]  ScCirclesShow(over-cap units)   our circles go on LAST
```

Because our detach runs before the engine's attach, the two sets can never overlap: at the moment we
let go of a unit the engine has not taken it yet, and at the moment we take one the engine has
already finished. That ordering is the entire correctness argument, and it is why the hook is on
`0x0049AE40` rather than anywhere cheaper — `0x0049AE40` is reached by all ten client paths that
change a selection, including control-group recall and every click.

Attach is `0x004D7070(colourTable[player], 0x231)` with EAX = sprite, then `flags |= 0x01` — the
same three lines `0x004E6180` runs, minus the two that would set `0x08` and the index. Detach is
`0x004975D0` with ECX = sprite, the engine's own remove-just-the-circle primitive.

Guards, each ruling out a distinct way a record goes bad between attach and detach:

- the unit pointer is bounds- and stride-checked against the unit array, and the sprite pointer is
  `VirtualQuery`d before any dereference;
- `CUnit+0xA5` (uniqueness) must still match — the engine's own stale-tag test;
- `unit->sprite` must still be the sprite we attached to — a unit that died and came back gets a
  different one, and the old one is on the sprite free list;
- flag `0x01` must still be set, and flag `0x08` must **not** be — if the engine has since taken the
  unit, the circle is its property and removing it would leave a selected unit with a health bar and
  no circle.

`%SCPLUGIN_CIRCLES%` (`run-with-plugin.ps1 -Circles 0`) is the feature's own off switch on top of
the mode; circles are only ever active in `fanout` mode, because `shadow` mode's contract is
"capture and log, change nothing".

### 5.1 Threading, and why unloading mid-game is unsupported

Everything in `sc_circles.cpp` runs on the **game's own thread** — the `0x0049AE40` detour and
sc_fanout's `CMDACT_Select` detour are both called by the game. Nothing takes a lock, and nothing
may be reached from the observer thread or from `DllMain`.

That rules out one thing the first draft did: taking the circles off from `ScFanoutRemove`, which
runs on the **unloader's** thread during `DLL_PROCESS_DETACH`. The engine is alive there — but
liveness is not the question. `0x004975D0` unlinks an image from the sprite's overlay list and
pushes it onto the image free list, and the game thread may be walking exactly those lists to render
the frame; worse, the `0x0049AE40` hook is still installed at that point, so the game thread can be
inside `ScCirclesHide()` at the same time.

So the detach path does **not** hide, and **unloading the plugin mid-game is unsupported**. The
circles left behind are self-healing rather than permanent: the engine's own unit-removal path calls
`0x004975D0` on death (§4.5), and `0x00497620` takes the circle off the next time that unit is
selected and deselected. (Process exit is unaffected — `scplugin.cpp` already skips `ScFanoutRemove`
entirely on that path.)

### 5.2 What was deliberately left out

**The health bar.** It is `0x004D6420`, the other half of `0x004E6180` — but `0x00497620` will only
take it off again when flag `0x08` is set, so attaching one would mean either setting `0x08` (§4.2)
or reimplementing the removal. A shadow-selected unit therefore shows a circle and no health bar.
That is within task 014's stated scope ("the green circles on the battlefield only") and it has a
small side benefit: circle-with-bar and circle-without-bar is exactly how a reader can tell the
engine's 12 from ours in a screenshot.

**The HUD wireframe row.** Out of scope by the task; it is a fixed 12-slot dialog
([`selection-cap.md` §4.5](selection-cap.md)) and is layout work, not data.

---

## 6. What was tested, and how

Unattended, by posting window messages to the game's `SWarClass` HWND with client coordinates in
`lParam` — task 012's D1 recipe ([`automated-testing-options.md` §4.1](automated-testing-options.md)),
now packaged as
`tools/plugin/drive-game.ps1` and driven by `tools/plugin/test-selection-circles.ps1`. No synthetic
OS input, no screen coordinates, focus not required. The oracle is the plugin's own log, written
from inside the process.

`./tools/plugin/test-selection-circles.ps1` — launches, walks the menus, loads the stock map
`Maps\campaign\(1)Enslavers02b.scm`, and asserts. Last run: **0 failures.**

| # | Step | Result |
|---|---|---|
| 0 | `StarCraft.exe` SHA-256 before launch | `AD6B58B2…C6A46`, asserted equal to the pristine 1.16.1 constant in `tools/make-working-copy.ps1` |
| 4 | shift-click removes exactly the clicked unit, small selection | 3 → 2 units |
| 5 | a 24-unit drag box | `SORT candidates=24 -> selected=12`, `SHADOW captured: 24 (12 visible + 12 beyond)`, `CIRCLES show: 12/12`, and `CIRCLES pos:` reporting all 12 on screen |
| 6 | shift-click **aimed at a known shadow-circled unit** (first reported position, `147,196`) | `SEL count` 12 → 12 **and no `0x09`/`0x0A`/`0x0B` command emitted** — the predicted "add-to-selection branch, selection already full, return" |
| 7 | an un-aimed shift-click in the same selection | landed on an engine-selected unit: `SEL count` 12 → 11. Not a behavioural assertion — see §7 |
| 8 | one right-click | `FANOUT start: units=24 -> 2 Select+order pairs`, `FANOUT done` |
| — | shutdown | `CIRCLES stats: shown=24 hidden=12 held=12 skipped=0 noImage=0 lost=0` — accounting balances; `held` is the live selection at process exit, where the plugin deliberately does not un-splice |
| — | every selection change | no `CIRCLES hide: a/b` line with `a != b` — no change ever left a circle behind |
| — | `StarCraft.exe` SHA-256 after close | unchanged, and still equal to the pristine constant |

Step 6 is aimed rather than hopeful because the plugin logs where its circles are on screen
(`CIRCLES pos:`, client pixels, computed as sprite position minus the viewport origin the click
handler itself uses). Without that a test cannot distinguish "clicked one of ours" from "clicked one
of the engine's", and the assertion collapses to "either branch is acceptable".

Run by hand in the same session, in addition:

- shift-clicking an engine-selected unit inside the 12+12 selection: `SEL count` 12 → 11 with a
  4-byte `0x0B` SelectRemove carrying exactly one unit.
- `-Circles 0`: `FANOUT config: ... circles=0` and **4** hooks instead of 5 — the
  `CreateNewUnitSelectionsFromList` hook is not installed at all.
- `-Mode observe`: no `HOOK` line of any kind, no `CIRCLES` line. Passive is stock.

Offline, with no game in the process at all: `build.ps1 -Test` part [8] drives the module against
fake sprites and fake engine primitives — attach, re-state, hide, idempotent hide, "the engine owns
this sprite" skip, unit died between attach and detach, sprite swapped underneath us, exhausted
image free list, unit with no sprite — plus the two invariant assertions in §4.3. 0 failures.

**What none of it proves is that the image is drawn.** `CIRCLES show: 12/12` means the engine
accepted the attach and returned an image. Only an eye on the frames the test captures can confirm
pixels, which is why the test says so and prints where they are.

---

## 7. Open questions

1. **Which end of the overlay list draws first is not established.** `0x004D6420` links the health
   bar at `CSprite+0x1C` and `0x004D7070` links the circle at `CSprite+0x20`, and on screen the
   circle plainly renders *under* the unit while the bar renders over it — but this task never
   decompiled the renderer's walk, so the mapping from list end to draw order is inferred from
   pixels, not read. A health-bar task must settle it before relying on either end.
   (`sc_addresses.h` carries the same warning beside the constant.)
2. **Sprites the plugin never sees.** A unit whose sprite is destroyed and rebuilt while
   shadow-circled is handled by the engine (§4.4), and one that dies is handled by `0x004975D0` in
   the removal path (§4.5) — but a unit that is *hidden* (loaded into a transport, warped out) has
   not been tested with a circle attached.
3. **The `lost` counter has never fired.** Every guard in §5 is exercised offline against fakes;
   none has been observed firing in a real game, so the in-game behaviour of the stale-record paths
   is unverified. The counter exists precisely so that "never happens" stays a measurement. §4.5
   predicts it *will* fire, once per circled unit that dies.
4. **A shift-click aimed at a specific ENGINE-selected unit is not automated.** The plugin can
   report where its own circles are, so step 6 is deterministic; it has no way to report the
   engine's 12, so step 7 clicks a fixed coordinate and accepts either branch. The engine's sprites
   are ones this plugin never writes, so the behaviour there is stock by construction — but that is
   an argument, not a test.
5. **The image budget.** The engine's image pool is 5000 (teippi, `selection-cap.md` §5). A
   selection of ~250 units would add ~250 images. `noImage` has always been 0; the ceiling is
   untested.
6. **`0x004997A0` has zero references.** It is byte-for-byte the inner block of `0x004E6180`. Almost
   certainly a compiler artefact, but "unreferenced in the static call graph" is not "never reached"
   if anything dispatches indirectly.
7. **The displacement sweep's blind spot**, §4.1: a `selectionIndex` access computed arithmetically
   would not appear in it.
8. **Unloading the plugin mid-game leaves its circles on screen.** Documented as unsupported rather
   than fixed — see §5.2.
