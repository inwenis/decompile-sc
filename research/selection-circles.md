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
see it. That returns 94 candidate operands (`work/scratch/selgfx3/disp0b.tsv`). Most are stack
locals or `CImage::direction` (`CImage` also has a byte at `0x0B`). Every candidate that could not
be dismissed by its module was decompiled and read; the survivors are:

| Address | Function | What it does with the value | Guard |
|---|---|---|---|
| `0x0046FD77` | `0x0046FB40` — the click handler | `memmove(&list[i], &list[i+1], (n-1-i)*4)` on a 12-entry **stack** array, then `CreateNewUnitSelectionsFromList(n-1)` | `if (clicked->sprite->flags & 8)` |
| `0x0049F7B3` | `0x0049F7A0` — remove one unit from the client selection | the same memmove, same shape | `if (unit->sprite->flags & 8)` |
| `0x0049F00B` | `0x0049EFA0` — change a unit's owner | saves it, calls `0x004E6290`, re-attaches with `0x004E6180(saved)` | `if (unit->sprite->flags & 8)` |
| `0x0049F8B6` | `0x0049F860` — rebuild a unit's sprite | saves it, tears the sprite down, re-attaches with `0x004E6180(saved)` | `if (unit->sprite->flags & 8)` |

Writes are equally few: `0x004E61D6` and `0x004E61FD` (both inside `0x004E6180`), plus `0x004997AE`
in `0x004997A0`, a byte-identical copy of `0x004E6180`'s inner block with **zero references** — a
leftover the compiler did not fold away.

**Method limit, stated plainly.** A displacement sweep is a candidate list, not a proof of absence:
an instruction that computed the field address arithmetically (`LEA` then a later dereference, or a
base already advanced by 11) would not appear. Two independent things make that unlikely to matter
here — the writes are as few as the reads and sit in one function, and the four readers found are
exactly the four operations that can move a unit out of a selection — but the negative is
**unfalsified, not proven**.

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

### 5.1 What was deliberately left out

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
| 4 | shift-click removes exactly the clicked unit, small selection | 3 → 2 units |
| 5 | a 24-unit drag box | `SORT candidates=24 -> selected=12`, `SHADOW captured: 24 (12 visible + 12 beyond)`, `CIRCLES show: 12/12` |
| 6 | shift-click inside the 12-engine + 12-shadow selection | game alive; `SEL count` 12 → 11 with a 4-byte `0x0B` SelectRemove carrying exactly one unit |
| 7 | one right-click | `FANOUT start: units=24 -> 2 Select+order pairs`, `FANOUT done` |
| — | shutdown | `CIRCLES stats: shown=24 hidden=12 held=12 skipped=0 noImage=0 lost=0` — accounting balances; `held` is the live selection at process exit, where the plugin deliberately does not un-splice |
| — | every selection change | no `CIRCLES hide: a/b` line with `a != b` — no change ever left a circle behind |

Run by hand in the same session, in addition:

- shift-clicking a **shadow-circled** unit (circle, no health bar) in a 24-unit selection: no
  command emitted, `SEL count` stayed 12, process responding — the predicted "add-to-selection
  branch, selection already full, return".
- `-Circles 0`: `FANOUT config: ... circles=0` and **4** hooks instead of 5 — the
  `CreateNewUnitSelectionsFromList` hook is not installed at all.
- `-Mode observe`: no `HOOK` line of any kind, no `CIRCLES` line. Passive is stock.
- `StarCraft.exe` SHA-256 before and after every run: `AD6B58B2…C6A46`, and identical to the
  pristine install's copy.

Offline, with no game in the process at all: `build.ps1 -Test` part [8] drives the module against
fake sprites and fake engine primitives — attach, re-state, hide, idempotent hide, "the engine owns
this sprite" skip, unit died between attach and detach, sprite swapped underneath us, exhausted
image free list, unit with no sprite — plus the two invariant assertions in §4.3. 0 failures.

**What none of it proves is that the image is drawn.** `CIRCLES show: 12/12` means the engine
accepted the attach and returned an image. Only an eye on the frames the test captures can confirm
pixels, which is why the test says so and prints where they are.

---

## 7. Open questions

1. **Sprites the plugin never sees.** A unit whose sprite is destroyed and rebuilt while
   shadow-circled is handled by the engine (§4.4) — but a unit that is *hidden* (loaded into a
   transport, warped out) has not been tested with a circle attached.
2. **The `lost` counter has never fired.** Every guard in §5 is exercised offline against fakes;
   none has been observed firing in a real game, so the in-game behaviour of the stale-record paths
   is unverified. The counter exists precisely so that "never happens" stays a measurement.
3. **The image budget.** The engine's image pool is 5000 (teippi, `selection-cap.md` §5). A
   selection of ~250 units would add ~250 images. `noImage` has always been 0; the ceiling is
   untested.
4. **`0x004997A0` has zero references.** It is byte-for-byte the inner block of `0x004E6180`. Almost
   certainly a compiler artefact, but "unreferenced in the static call graph" is not "never reached"
   if anything dispatches indirectly.
5. **The displacement sweep's blind spot**, §4.1: a `selectionIndex` access computed arithmetically
   would not appear in it.
