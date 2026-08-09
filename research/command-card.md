# The command card in StarCraft 1.16.1 — how a slot becomes an ability, and why the Ghost's Cloak could not be pressed

Survey date: 2026-08-09 (task 026). Target: the `StarCraft.exe` in the disposable working copy,
SHA-256 `AD6B58B27B8948845CCFA69BCFCC1B10D6AA7A27A371EE3E61453925288C6A46`, verified before
analysis and unchanged after. Static analysis with the task-005 Ghidra pipeline
(`tools/ghidra/sweep.ps1`, persistent project), plus **one** in-game read-back run.

**Nothing here is inherited.** The module was found by locating its own `.rdata` strings in the
file image — `work/scratch/card/scan-strings.ps1`, an ASCII-run scan whose file offsets are
converted to virtual addresses through the PE section table parsed from the same file — and then
sweeping those strings for references. Query specs: `tools/ghidra/specs/card-*.spec` and
`tech-state.spec`; committed evidence tables: `research/data/card-*.tsv`. Decompiled C and raw
listings stay under `work/scratch/card/` (derived game content, gitignored).

Companion documents: [`hud-selection-row.md`](hud-selection-row.md) (the status area — the card's
sibling dialog, and the source of every `BinDlg` offset used here),
[`ability-semantics.md`](ability-semantics.md) (`0x21`'s receive-side handler and the energy
model), [`command-opcodes.md`](command-opcodes.md) (the opcode table and the mixed-selection
observation this document derives from the binary).

---

## 0. Verdict up front

1. **The Ghost's Personnel Cloaking button is card slot 7.** Its `Button` record carries icon
   `0x00FC`, condition `0x004293E0`, action `0x00423730` and conditionParam `10`. The action is
   byte-exact Cloak: it builds `{0x21, shiftFlag}` and queues it. The conditionParam is the same
   tech id [`ability-semantics.md`](ability-semantics.md) §3 derived independently from the
   *receive*-side handler `0x00491B30` — two derivations, one number. [§3](#3-the-buttonset-table-and-the-button-record)
2. **On both fixtures the generator could build at the time, it read GREYED**, and that is the
   whole answer to tasks 022 and 023. A card button's enabled state is one bit,
   `control+0x18 & 0x2`, and **both** of the engine's input paths test it and return: the mouse at
   `0x00459947` and the hotkey predicate at `0x004588C0`. A greyed button emits nothing, arms
   nothing, and logs nothing — which is exactly the shape of the "the entire ability row is inert"
   negative. There was never an input to find.
   [§5](#5-the-two-input-paths-and-the-one-bit-they-both-refuse-on)
2b. **With the generator fixed, the same slot reads ENABLED and both input paths fire it.** On a
   fixture whose researched bit the *engine* confirms, slot 7 comes up `enabled`, the key `C`
   emits `0x21`, and a click at the slot centre computed from the live dialog emits `0x21`. The
   unit's secondary order goes to `0x6D`. Nothing about the input path ever needed fixing.
   [§7](#7-what-this-settles-and-what-it-does-not)
3. **It was greyed because the fixture never granted the tech, and the fixture never granted the
   tech because `make_test_map.py` wrote PTEx with the wrong index order.** The engine reads the
   section **player-major** (`player * 44 + tech`); the generator wrote it **tech-major**
   (`tech * 12 + player`). Those two agree at exactly two cells, `(tech 0, player 0)` and
   `(tech 43, player 11)` — and the first of them is Stim Packs for the human slot, which is the
   only tech any fixture in this repo had ever proved worked. [§6](#6-the-tech-state-behind-the-button-and-the-fixture-bug-it-exposed)
4. **The user saw it first.** "The ghosts didn't have the cloak ability unlocked (just fyi)",
   watching a run. That is precisely what the memory read says. [§7](#7-what-this-settles-and-what-it-does-not)
5. **A merged claim is retracted.** Task 023 concluded from two differing region fingerprints that
   researching the tech "DOES draw a different command card". It does not: with and without the
   tech, the nine slots hold the same buttons in the same states, and on this run both fixtures
   hashed to the same `AC61F7A0C9244DB1`. **A frame hash is not an oracle for dialog content.**
   [§8](#8-corrections-to-merged-documents)
6. **A separate open question from task 022 closes on the way past.** The send-side gate that
   suppresses an ability the selection cannot pay for reads `clientSelectionGroup` — the engine's
   own twelve — and that is now read out of the binary rather than inferred.
   [§4.3](#43-the-send-side-gate-inside-the-action)

---

## 1. Where the card lives

The command card is the **sibling** of the status area [`hud-selection-row.md`](hud-selection-row.md)
mapped: a second `.bin` dialog in the same console, built by the same framework, using the same
`BinDlg` record. Every structural offset in this document (`+0x00 next`, `+0x04 rect`,
`+0x18 flags`, `+0x20 index`, `+0x24 graphic`, `+0x26 user`, `+0x2A fxnInteract`,
`+0x2E fxnUpdate`, `+0x32 parent`, `+0x42 first child`) is that document's, re-used rather than
re-derived.

The module's own strings (`work/scratch/card/scan-strings.ps1`, VAs read off the PE section table):

| VA | string |
|---|---|
| `0x005049F8` | `rez\statbtn%c.bin` — the card dialog asset, **per race** (`%c` is the race letter) |
| `0x00504A24` | `unit\cmdbtns\cmdicons.grp` — the card's icon art |
| `0x00504A40` / `0x00504A50` | `%s%ccmdbtns.grp`, `unit\cmdbtns\` — the icon path builder |
| `0x00504A0C` | `unit\cmdbtns\ticon.pcx` |
| `0x00504A6C` | `Starcraft\SWAR\lang\statcmd.cpp` — the module's debug string |

Sweeping those (`research/data/card-strings.tsv`) names three functions, and one of them is the
init:

| Address | What | Evidence |
|---|---|---|
| `0x00459B90` | **card init** | loads `statbtn%c.bin`, `cmdicons.grp`, `ticon.pcx`; runs the same in-place relocator `0x004194E0` the status dialog uses; stores the dialog at `0x0068C148` |
| `0x00458CF0` | card teardown | clears `0x0068C148`, frees the two GRP handles |
| `0x004596A0` | the card button's CREATE case | `MOV [EAX+0x2E],0x458730` — binds the per-button draw |
| `0x004599A0` | **per-frame card update** | already named by `hud-selection-row.md` §4.1 as "the button-panel counterpart"; the HUD driver `0x004D93F0` calls it immediately before the status dispatcher |

Module globals (`research/data/card-globals.tsv`):

| Address | What | Evidence |
|---|---|---|
| `0x0068C148` | **the card dialog** (`BinDlg*`) | written by the init, cleared by the teardown, read by the layout, the hotkey handler and the mouse router |
| `0x0068C14C` | **the current card id** — indexes the buttonset table | the update `0x004599A0` sets it from the portrait unit's `CUnit+0x94`; the layout `0x004591D0` indexes with it |
| `0x0068C1C4` | the **selection** card-id override, `0xE4` = none | computed by `0x00458BC0` (§2.1) |
| `0x0068C1C8` | the **submenu** card-id override, `0xE4` = none | read by `0x004599A0` before the portrait unit |
| `0x0068C1B4` | the control under the cursor | written by `0x00459770` and the mouse router `0x004597C0` |
| `0x0068C1B0` | "the card needs rebuilding" flag | set/consumed by `0x004599A0` |
| `0x0066FF60` | **the refuse reason** every ability condition writes | set by the tech gate `0x0046DD80` and the requirement interpreter `0x0046D610`; read by the layout, which rewrites a button's disabled-reason string to `0x2FA` when it reads `0x15` |

### 1.1 The nine slots

The layout function treats a child as a card slot when its control index is in **1..9** — the
range is the binary's, not a convention: it walks to the child with `index == 1`, returns if it
ever sees `index < 1`, and only processes children with `index < 10`. Slots run in reading order,
1-2-3 across the top row, 7-8-9 across the bottom.

## 2. How the card id is chosen

`0x004599A0`, per frame:

```c
if (rebuildFlag && (submenuOverride == 0xE4 || isReplay)) statDirtyHelper();   // 0x00458DE0
cardId = (submenuOverride != 0xE4) ? submenuOverride
       : (selectionOverride != 0xE4) ? selectionOverride
       : portraitUnit->buttonSet;                       // CUnit+0x94
if (cardId != currentCardId) { rebuild = 1; currentCardId = cardId; }
if (rebuild) { cardLayout();            // 0x004591D0
               hitTestAndTooltip(); }   // 0x00459770
```

`CUnit+0x94` is therefore **the unit's own buttonset id**, and it is used two ways in the same
binary — as the value compared across a selection and as the index into the buttonset table
(`(&PTR_005187EC)[id*3]` in `0x00458BC0`), which is what makes the identification safe rather than
a guess.

### 2.1 The mixed-selection rule, from the binary

`0x00458BC0` walks `clientSelectionGroup` and compares every unit's `CUnit+0x94`. When they do not
agree — and are not two ids that alias to the same buttonset — it writes the **selection override**
`0x0068C1C4`:

| value | meaning | buttonset table row |
|---|---|---|
| `0xE4` (228) | no override; use the portrait unit's own card | — |
| `0xF4` (244) | mixed selection → the basic card | id 244, 5 buttons |
| `0xF5` (245) | every selected unit has units.dat flag `0x8` | id 245, 5 buttons |
| `0xF6` (246) | every selected unit has flag `0x200` | id 246, 7 buttons |
| `0xF7` (247) | every selected unit is a flag-`0x100000` type, and none is `CUnit+0xDC & 4` | id 247, 7 buttons |

That is [`command-opcodes.md`](command-opcodes.md) §8's "in game a MIXED selection is offered only
the basic command card", which was an in-game observation, **derived from the code**.

## 3. The buttonset table and the Button record

The layout function's first two lines are the whole data model:

```
count   = *(u16*)   (0x005187E8 + cardId * 0xC)
buttons = *(Button**)(0x005187EC + cardId * 0xC)
```

**The buttonset table is at `0x005187E8`, 250 entries of 12 bytes.** Its length is read off the
binary rather than assumed: entry 250 would begin at `0x005193A0`, which is exactly where the
per-unit-type status cond/act table [`hud-selection-row.md`](hud-selection-row.md) §4.2 already
named begins. Rows 0..~172 are indexed by **unit id** (Marine 0 → 6 buttons, Ghost 1 → 9, Vulture
2 → 6, Goliath 3 → 5, Siege Tank 5 → 7, SCV 7 → 9, Wraith 8 → 7, Battlecruiser 12 → 6 — the real
cards, button for button); 197..249 are the submenu and group cards.

**A `Button` is 20 bytes** (the layout advances its cursor by ten `u16`s per button):

| Offset | Field | Proven by |
|---|---|---|
| `+0x00` | `slot` (u16), 1..9 | the layout compares it against the control's index: `if (ctrl->index < button->slot) hide(ctrl)` |
| `+0x02` | `icon` (u16) | the layout writes it into the control's `graphic` (+0x24) |
| `+0x04` | `condition` (fn ptr) | the layout CALLs it with the portrait unit |
| `+0x08` | `action` (fn ptr) | the click path `0x0045991C`: `CALL dword ptr [ESI+0x8]` |
| `+0x0C` | `conditionParam` (u16) | passed to the condition; for an ability button it is the **tech id** |
| `+0x0E` | `actionParam` (u16) | the click path `0x00459918`: `MOV CX,word ptr [ESI+0xE]` immediately before the call |
| `+0x10` | `nameString` (u16) | the hotkey predicate `0x004588DD`: `MOV CX,word ptr [EAX+0x10]` — the string whose hotkey letter is matched |
| `+0x12` | `disabledString` (u16) | the layout **overwrites** it with `0x2FA` when the refuse reason is `0x15` |

### 3.1 The Ghost's card, read out of the table

`work/scratch/card/dump-buttonsets.ps1` reads these records straight out of the file image. Card
id 1 (Ghost), 9 buttons at `0x00517AB8`:

| # | slot | icon | condition | action | condParam | actParam | name | dis | what it is |
|---|---|---|---|---|---|---|---|---|---|
| 0 | 1 | `0x00E4` | `0x004282D0` | `0x00424440` | 0 | 0 | `0x0298` | — | Move |
| 1 | 2 | `0x00E5` | `0x004282D0` | `0x004233F0` | 0 | 0 | `0x0299` | — | Stop |
| 2 | 3 | `0x00E6` | `0x00428F30` | `0x00424380` | 0 | 0 | `0x029A` | — | Attack |
| 3 | 4 | `0x00FE` | `0x004282D0` | `0x00424140` | 0 | 0 | `0x029B` | — | Patrol |
| 4 | 5 | `0x00FF` | `0x004282D0` | `0x00423370` | 0 | 0 | `0x029C` | — | Hold Position |
| 5 | **7** | `0x00FC` | `0x004293E0` | **`0x00423730`** | **10** | 10 | `0x0158` | `0x0163` | **Personnel Cloaking** |
| 6 | **7** | `0x00FD` | `0x00429370` | `0x00423270` | 10 | 0 | `0x0159` | — | Decloak (same slot) |
| 7 | 8 | `0x00F0` | `0x004294E0` | `0x00423F70` | 1 | 1 | `0x014F` | `0x015B` | Lockdown (tech 1) |
| 8 | 9 | `0x0137` | `0x00428810` | `0x00423A40` | 0 | 0 | `0x02AD` | `0x02F9` | Nuclear Strike |

Two independent cross-checks fall out, and they are what make the naming safe:

- the **Wraith's** card (id 8) carries the same two cloak buttons at slot 7 with conditionParam
  **9** — Cloaking Field. The two cloak techs, 10 and 9, are the two
  [`ability-semantics.md`](ability-semantics.md) §3 read out of the *receive*-side handler
  `0x00491B30` (`id==1||0x10||100||99||0x68||0x33 → tech 10; id==8||0x15 → tech 9`). The card and
  the handler agree without either being derived from the other;
- **Cloak and Decloak share slot 7.** That is the toggle, and it is why the card never shows both.

### 3.2 Slots do not shift

A button whose condition returns 0 is skipped, and the *next* surviving button is then offered to
the current control — but the control takes it only if `control->index >= button->slot`, otherwise
the control is hidden and the button waits. So a hidden ability leaves a **gap**; it never pulls
the buttons below it up. Slot 8 is Lockdown whether or not Cloak is on the card.

## 4. The layout function `0x004591D0`

```c
count   = buttonSetTable[cardId].count;
button  = buttonSetTable[cardId].buttons;
i = 0;
ctrl = first child of the card dialog with index == 1;
do {
    if (ctrl->index < 1) return;
    if (ctrl->index < 10) {
        while (i < count && (r = button->condition(portraitUnit)) == 0) { ++i; ++button; }
        if ((!replay && portraitUnit && portraitUnit->owner != localPlayer)
            || i >= count || ctrl->index < button->slot) {
            hide(ctrl); ctrl->graphic = 0xFFFF; ctrl->user = 0;
        } else {
            ctrl->user = button;                       // <- the read-back's anchor
            if (ctrl->graphic != button->icon) { ctrl->graphic = button->icon; ...; }
            show(ctrl);                                 // 0x004186A0
            if (r < 0) { disable(ctrl);                 // 0x00418640  -> flags |= 0x2
                         if (refuseReason == 0x15) { button->disabledString = 0x2FA; ... } }
            else        enable(ctrl);                   // 0x00418E00  -> flags &= ~0x2
            ++i; ++button;
        }
    }
    ctrl = ctrl->next;
} while (ctrl);
```

### 4.1 The condition is a TRI-STATE, and that is the whole mechanism

| condition returns | what the layout does | what the player sees |
|---|---|---|
| `0` | skip the button entirely | the ability is not on the card |
| `> 0` | `show` + `enable` (`0x00418E00`, clears `flags & 0x2`) | a normal, clickable button |
| `< 0` | `show` + `disable` (`0x00418640`, sets `flags & 0x2`) | a **greyed** button |

`0x00418640` and `0x00418E00` are the only writers of that bit, and they are picked purely by the
sign. So "greyed" is a fact readable from one dword of dialog memory.

`condNuke` (`0x00428810`) is the clearest example of the negative branch: it walks
`playerUnitList[owner]` for a Nuclear Silo (`type == 0x6C`) holding a nuke (`+0xD4 != 0`) and
returns **`-1`** when there is none. No silo → grey.

### 4.2 The Cloak condition

`condCloak` (`0x004293E0`), per unit of `clientSelectionGroup`:

```c
r = techGate(unit, conditionParam);      // 0x0046DD80, param = tech 10
if (r != 1) return r;                    // <- passes the gate's 0 or -1 straight out
flags = unit->flags;                     // CUnit+0xDC
if (((flags & 0x800) == 0 || (flags & 0x10) != 0) && (flags & 0x100) == 0) return 1;
```

`flags & 0x100` is the already-cloaked bit — the same test the *receive*-side handler
`0x00491B30` makes before doing anything ([`ability-semantics.md`](ability-semantics.md) §3). So
Cloak's condition is: **tech gate, then "is anybody not already cloaked"**. Energy is *not* part of
it; that is checked later, on the send side.

`condDecloak` (`0x00429370`) is the mirror image: it requires the gate to pass **and** the unit to
be cloaked, which is what makes the two share slot 7 without ever both appearing.

### 4.3 The send-side gate inside the action

`actCloak` (`0x00423730`), byte-exact (`work/scratch/card/act-listing.tsv`):

```
0x00423735  MOV BL,DL                     ; DL = shift state (0x00596A28), set by the click path
0x00423737  CALL 0x00423540               ; the send gate
0x0042373E  JZ  0x00423754                ; refused -> emit nothing at all
0x00423748  MOV byte ptr [EBP + -0x4],0x21    ; the command id
0x0042374C  MOV byte ptr [EBP + -0x3],BL      ; ... and the queued flag
0x0042374F  CALL 0x00485bd0               ; queueCommand(buf, 2)
```

so command `0x21` is `{0x21, queued}` — the second byte is the shift/queued flag, matching
[`command-opcodes.md`](command-opcodes.md) §4's reading of `0x1A`/`0x2B`, and the button's
`actionParam` is not used by this action at all.

**The gate `0x00423540` closes an open question.**
[`ability-semantics.md`](ability-semantics.md) §5.2 found that a fourth Stim press emitted nothing
and recorded a send-side gate whose input was explicitly "an inference, not a measurement". Here it
is, in the binary:

```c
for (slot = &clientSelectionGroup[0]; slot < 0x597238; ++slot) {
    if (!*slot) continue;
    tech = cloakTechFor((*slot)->unitId);                  // 10 / 9 / 0x2C
    if (cheatFlag || (techEnergyCost[tech] << 8) <= (*slot)->energy) return 1;   // CUnit+0xA2
}
refuseFeedback();                                          // 0x0048EE30
return 0;
```

and Stim's action (`0x004234D0`) walks **the same array** for a unit above `0xA00` hit points
before emitting `0x36`. So the send-side gate consults **`clientSelectionGroup` — the engine's own
twelve — and not the shadow list.** The consequence §5.2 hypothesised is now established: a >12
selection whose visible twelve cannot pay emits nothing even when units past the cap could have.

## 5. The two input paths, and the one bit they both refuse on

### 5.1 The mouse

The card button's interact handler is `0x004598D0` (`__fastcall(ECX = control, EDX = event)`; code
auto-analysis had left undefined, recovered via `specs/card-code-recovery-2.spec` and read as a
listing). It switches on `event->type` through the index table at `0x0045998C` and the jump table
at `0x00459978`:

```
0x00459947   ; type 4 (LBUTTONDOWN) / type 6 (LBUTTONDBLCLK)
    TEST byte ptr [ESI+0x18],0x2        ; the DISABLED bit
    JZ   0x0045992E                     ; not disabled -> fall through to the default dispatch
    POP EDI ; XOR EAX,EAX ; POP ESI ; RET   ; DISABLED -> return 0, the event is SWALLOWED
```

and the activation itself, on the `USER`/`dwUser == 2` sub-event:

```
0x0045990F  MOV ESI,dword ptr [ESI + 0x26]   ; ESI = control->user = the Button*
0x00459912  MOV DL,byte ptr [0x00596a28]     ; DL = shift state
0x00459918  MOV CX,word ptr [ESI + 0xe]      ; CX = button->actionParam
0x0045991C  CALL dword ptr [ESI + 0x8]       ; button->action()
```

That is the proof of `+0x08` and `+0x0E`, and of `control+0x26` being the `Button*`.

### 5.2 The hotkey

`0x00458B30` handles a key press against the card: it lowercases `event->key`, then walks the card
dialog's children with the predicate at `0x004588C0`. The predicate:

```
0x004588C0  MOV AX,word ptr [ECX + 0x20]    ; control->index
0x004588C4  CMP AX,0x9      ; JG  -> no      ; only slots 1..9
0x004588CA  TEST AX,AX      ; JL  -> no
0x004588CF  MOV EAX,dword ptr [ECX + 0x18]  ; control->flags
0x004588D2  TEST AL,0x8     ; JZ  -> no      ; NOT VISIBLE -> no hotkey
0x004588D6  TEST AL,0x2     ; JNZ -> no      ; DISABLED    -> NO HOTKEY
0x004588DA  MOV EAX,dword ptr [ECX + 0x26]  ; the Button*
0x004588DD  MOV CX,word ptr [EAX + 0x10]    ; its name string
0x004588E1  CALL 0x004c36f0                 ; -> the string's hotkey character
0x004588E6  MOV CL,byte ptr [EDX] ; SUB CL,byte ptr [EAX] ; ... ; RET   ; match?
```

**The same `flags & 0x2` test as the mouse path.** One bit closes both doors, which is why task
022's alphabet sweep and task 023's nine-slot click sweep produced *identical* silence: they were
not two independent negatives, they were one fact observed twice.

## 6. The tech state behind the button, and the fixture bug it exposed

### 6.1 The gate

`techGate` (`0x0046DD80`) runs, in order, and every failure writes `0x0066FF60` first:

| test | on failure | effect |
|---|---|---|
| tech id `> 0x2B` | reason `0x11`, return 0 | hidden |
| `unit->owner != player` | reason `1`, return 0 | hidden |
| `unit->flags & 1` clear (incomplete) | reason `0x14`, return 0 | hidden |
| `0x004020B0` (busy/under construction/etc.) | reason `10`, return 0 | hidden |
| `flags & 0x40000000` (hallucination) | reason `0x16`, return 0 | hidden |
| **not AVAILABLE** (`0x004CE8A0`) and no cheat | reason `2`, return 0 | **hidden** |
| `0x006562F8[tech] == 0` | reason `0x17`, return 0 | hidden |
| otherwise | tail-call the requirement interpreter `0x0046D610` | 1 / 0 / **-1** |

The interpreter walks a requirement opcode stream out of `0x00514A48`. Its only two `-1` exits are
opcode `0xFF22` (reason `0x15` — the one the layout rewrites the disabled string for) and the
terminal `if (satisfiedCount == 0) { reason = 8; return -1; }`. Its **researched** test is opcode
`0xFF0F`, which reads a per-player byte.

**So the two states are distinguishable, and they mean different things:**

- tech not **available** → the gate returns 0 → the button is **not on the card**;
- tech available but not **researched** → the interpreter satisfies nothing → `-1` → the button is
  on the card and **greyed**.

Which is exactly what we observed: visible, greyed.

### 6.2 The four arrays

Confirmed by sweep (`research/data/card-tech-state.tsv`): the only writer of all four is the CHK
applier pair, and `0x004CCC80` is the `REP STOSD` that clears them at game start.

| Address | What | Read by |
|---|---|---|
| `0x0058CE24` | `techAvailable[12][24]` | `0x004CE8A0` (the gate's availability test) |
| `0x0058CF44` | `techResearched[12][24]` | `0x004CE850`, and opcode `0xFF0F` inside `0x0046D610` |
| `0x0058F038` | `techAvailableBW[12][20]` (techs 24..43) | same |
| `0x0058F128` | `techResearchedBW[12][20]` | same |

The pairs are adjacent by exactly their own size — `0x0058CF44 - 0x0058CE24 = 0x120 = 12*24` and
`0x0058F128 - 0x0058F038 = 0xF0 = 12*20` — so the strides are read off the layout, not asserted.

### 6.3 PTEx is player-major, and the generator was not

`FUN_004CB7D0` applies the Brood War `PTEx` section (size `0x688` = 1672 =
`44*12 + 44*12 + 44 + 44 + 44*12`); `FUN_004CB670` does the same for the 24-tech vanilla `PTEC`
(`0x390` = 912). The loop, byte-exact:

```
0x004CB870  SUB EBX,0x2c                          ; EBX = player * 44   <- the OUTER step
0x004CB873  SUB ESI,0x18                          ; ESI = player * 24   (destination)
0x004CB879  MOV EAX,0x2c                          ; EAX = tech, 43..0   <- the INNER index
0x004CB881  LEA ECX,[EBP + EBX + -0x210]          ; playerUsesDefault + player*44
0x004CB888  CMP byte ptr [ECX + EAX],0x0          ;   ... + tech
0x004CB8CC  LEA ECX,[EBX + EAX]                   ; player*44 + tech
0x004CB8CF  MOV DL,byte ptr [EBP + ECX + -0x688]  ; playerAvailability[player][tech]
0x004CB8EE  MOV DL,byte ptr [EBP + EDX + -0x478]  ; playerAlreadyResearched[player][tech]
0x004CB8FB  MOV byte ptr [ESI + ECX + 0x58cf44],DL ; -> techResearched[player][tech]
```

The five stack bases are `0x688 / 0x478 / 0x268 / 0x23C / 0x210` below `EBP`, whose successive
differences are `0x210, 0x210, 0x2C, 0x2C` — i.e. the five sub-arrays, in the spec's order, sized
exactly. **The per-player arrays are player-major: `player * 44 + tech`.**

`tools/make_test_map.py` used `tech * 12 + player`. The two agree at `(0,0)` and `(43,11)` and
nowhere else. `--tech-researched personnel-cloaking` therefore wrote byte 120, which the engine
reads as **player 2's tech 32**; player 0's tech 10 stayed zero.

**Why nothing caught it:**

1. `read_techs_researched` used the *same* wrong index, so the generator's validator confirmed its
   own write and printed `PTEx: player 0 has researched 10(personnel-cloaking)` for a map on which
   the engine granted player 0 nothing. A wrong write verified by an equally wrong read reports
   success — the same shape as the 2026-08-09 "absence assertions must first be proved positive"
   rule, in the positive direction.
2. The only tech any fixture had ever *proved* worked is Stim Packs — tech 0, player 0 — which is
   one of the two cells where both conventions coincide.

Fixed here: one shared `ptex_index(tech, player)` so the write and the read cannot drift apart
again, and `tests/make-test-map.Tests.ps1` pins the literal offsets the applier dictates (including
that `(10, 0)` is byte 10 and not byte 120) so the arithmetic cannot regress silently.

**And the check that finally caught it was an INDEPENDENT one**: the card read-back carries the
engine's own `techResearched` array, so `probe-ghost-cloak.ps1` asks the engine what it granted
instead of asking the generator what it wrote. Both suites that research a tech now assert against
that array, not against the generator's stdout.

### 6.4 The recurring shape: a check that shares the flaw it checks

This project has now met the same failure four times, and it is worth naming so the fifth is
recognised on sight. In each case the verification could not fail:

| # | the check | the flaw it shared |
| --- | --- | --- |
| 1 | map browser clicked by row number, "verified" by the row number | both sides assumed the same stale row |
| 2 | `Get-ScSelectionGroup` asserted against the same parse it was derived from (task 023) | one parser, two roles |
| 3 | "the stock arm installed no hooks", matched on a string the plugin never logs | the pattern could not match anything |
| 4 | `read_techs_researched` verifying `write_techs_researched` at the same wrong index (§6.3) | one index function, two roles |

A fifth appeared inside this task's own probe and is the cleanest illustration of all: the probe
named the Cloak slot by its Cloak action alone, so once the probe had **successfully cloaked the
Ghost**, the slot showed its Decloak face and the probe reported "no Cloak button on the card".
A false negative manufactured by its own success. The rule that would have caught every one of
these: **the thing that verifies must not be the thing that acts, and it must be shown to give a
different answer in the failing direction** — which is why the read-back is now taken *before* any
input as well as after, and why `hooktest [14]` reads the same card twice, once with the disabled
bit set and once clear.

## 7. What this settles, and what it does not

**Settled.**

- The Ghost's Cloak button is slot 7 of buttonset 1, action `0x00423730`, command `0x21`,
  conditionParam tech 10 — named from memory, not from an icon or a screen position.
- Why tasks 022 and 023 could not drive it: the control carried `flags & 0x2`, and both input paths
  refuse that bit. The "bounded negative" was one fact, not two independent ones.
- Why it was greyed: the fixture never granted the tech, because the PTEx writer's index order
  disagreed with the engine's. The user's observation was correct and is now explained at the byte
  level.
- The send-side ability gate reads `clientSelectionGroup`
  ([`ability-semantics.md`](ability-semantics.md) §5.2's open question).
- **With the generator fixed, the button comes up enabled and both input paths fire it.** §7.1.

### 7.1 The confirming run (2026-08-09, after the PTEx fix)

The prediction the greyed reading makes is precise, so it is worth stating what was checked
against what. With `make_test_map.py` writing PTEx player-major, on the same 18-Ghost fixture:

| what was read | before the fix | after the fix |
| --- | --- | --- |
| engine's `techResearched` for player 0 | `[24 25 … 43]` — **10 absent** | `[10 24 25 … 43]` |
| card slot 7, read before any input | `GREYED`, icon `0x00FC`, act `0x00423730` | `enabled`, same icon and action |
| key `C`, 18-Ghost selection | nothing | `CMD id=0x21` |
| card slot 7 clicked at its computed centre `(522,454)` | nothing | `CMD id=0x21` |
| secondary order after it fired | — | `0x6D` on the acting units |
| the same slot with the Ghost now cloaked | — | shows its **Decloak** face, act `0x00423270`, and `C` emits `0x22` |

Three things follow, and the third is the one worth carrying:

1. **Task 022's A–Z sweep was not a keyboard result.** `C` is the Cloak hotkey and always was; the
   sweep ran against a greyed button, and `0x004588C0` refuses one before any letter is compared.
2. **The mouse path was never mis-aimed either.** The click that works is at the centre computed
   from the live control rect, which is within a few pixels of the coordinate task 022 guessed —
   the guess was not the problem.
3. **The read predicted the input, not the other way round.** The enabled/greyed bit was read out
   of memory first and the input outcome matched it in both directions. That is the standard this
   repo's UI claims should meet.

**Not settled, and deliberately kept separate.**

- **The user's actual report — a Ghost that WAS cloaked and stopped attacking — is a different
  question from all of the above**, which is about a Ghost that could not cloak at all. Nothing in
  this document speaks to it. It is answered separately, on real cloaking Ghosts, in
  [`ability-semantics.md`](ability-semantics.md) §7.6, and the answer there is **no**: a
  fanned-out Cloak issued mid-fight took zero units off their attack orders.

  **The fixture bug in §6.3 is ours and it does not explain the user's report.** Their Ghost was in
  a real game with cloak researched and working; ours was a generator writing the wrong byte. A
  tooling bug that happens to be adjacent to a user's question is not an answer to it.
- The `disabledString` rewrite path (`reason == 0x15` → `0x2FA`) is mapped but no string id in this
  document has been resolved to text; `0x004C36F0` (string → hotkey character) is named and not
  decompiled.
- `0x0066FF60` is a single global overwritten by every condition the layout runs, so the value a
  read-back sees belongs to the **last** button evaluated, not to any particular one. It is logged
  for triage, and no claim here rests on it.

## 8. Corrections to merged documents

**Task 023, PR #23 §7 — retracted.** It concluded that "the researched fixture DOES draw a
different command card, so the ability is on the card and a key/click that emits nothing is an
INPUT-path result", from two region fingerprints (`AC61F7A0C9244DB1` without the tech,
`DB533167A48C251C` with it), reproduced across three runs.

The conclusion is wrong in both halves. The memory read shows the two fixtures produce the **same
nine slots, holding the same buttons, in the same states** — slot 7 Cloak GREYED in both — and on
the 2026-08-09 run both fixtures fingerprinted `AC61F7A0C9244DB1`, the value 023 recorded for *no
tech*. The ability is on the card **regardless** of research (the button is in the Ghost's
buttonset unconditionally); what research changes is the *state*, and in that fixture it changed
nothing because the fixture never granted it. And the silence was not an input-path result.

The transferable rule, which is the reason this task existed: **read a dialog's content out of
memory; do not hash its pixels.** A frame hash over a card region answers "did any pixel change",
which is not the question, and it answered it inconsistently across sessions.

**Task 022, `ability-semantics.md` §9 Open** — two of its three open items are closed by §4.3 and
§5 above; the bullets there now point here rather than being restated.

## 9. The read-back oracle

`tools/plugin/src/sc_card.cpp` (module `sc_card`), driven on the existing marker channel next to
the world scan, `%SCPLUGIN_CARDSCAN%` / `run-with-plugin.ps1 -CardScan 1`:

- it installs **no hook**, calls nothing in the game and writes nothing, so it exists in
  `-Mode observe` — the stock arm of every plugin-vs-stock comparison;
- every read goes through the same guarded reader the observer uses, so a wrong offset yields a
  missing field rather than a fault;
- it logs, per slot: the control, its flags, `hidden` / `enabled` / `GREYED`, the icon actually
  being drawn, the control's **rect**, and the whole `Button` record; then the portrait owner's
  full tech state; then a `slots= shown= greyed=` summary the reader waits for.

The rects matter as much as the flags: `Get-ScCardSlotPoint` computes a slot's centre from the live
dialog (`dialog origin + control rect`, the sum the engine itself forms at `0x00458850`), so the
probe clicks the point the engine hit-tests instead of a coordinate read off a screenshot. That
removes the confound that made task 022's reading of "the bottom-left slot" ambiguous in the first
place, and it closes [`hud-selection-row.md`](hud-selection-row.md) §10 q1 for this dialog.

Offline coverage: `hooktest` part `[14]` drives the whole walk against a fake card dialog — the
Ghost's real button table, a hidden slot, a slot with no button, a bad `Button*`, a cyclic child
list, and a null dialog. It reads the card **twice with the same code**, once with the disabled bit
set and once clear, and requires both readings; an oracle that always answered "GREYED" would have
produced this task's headline result and is refused by construction.

## 10. Provenance

**Derived here, from this binary:** everything in §1-§6 — 25 functions decompiled
(`work/scratch/card/decomp*/index.tsv`, all `exact-entry`), two undefined blocks recovered and read
as listings (the card button interact `0x004598D0` and the hotkey predicate `0x004588C0`), the
250-entry buttonset table and the 20-byte `Button` record decoded straight out of the file image
with the PE section table parsed from the same file, and the four tech-state arrays confirmed by
xref sweep. Committed tables: `research/data/card-strings.tsv`, `card-fnrefs.tsv`,
`card-globals.tsv`, `card-tech-state.tsv`.

**Derived here, from the live game (one run, 2026-08-09):** that the Ghost's card resolves to
buttonset 1 with no override; that slot 7 holds the Cloak button; that it reads GREYED with and
without the fixture's tech; and that the two fixtures' card-region fingerprints are equal.

**Inherited:** the `BinDlg` field offsets and the dialog framework's shape, from
[`hud-selection-row.md`](hud-selection-row.md) (task 017), which derived them from this same
binary.
