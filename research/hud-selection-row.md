# The bottom-HUD selection row in StarCraft 1.16.1 — structure, and how to show more than 12

Survey date: 2026-08-08 (task 017, stage A). Target: the `StarCraft.exe` in the disposable
working copy, SHA-256 `AD6B58B27B8948845CCFA69BCFCC1B10D6AA7A27A371EE3E61453925288C6A46`,
verified before analysis. Static analysis only; the game was not launched and no binary was
modified.

Everything below was read out of **this binary** with the task-005 Ghidra pipeline
(`tools/ghidra/sweep.ps1`, persistent project, code recovery replayed from
`specs/selection-code-recovery.spec` — function count 5008 → 5082, matching
[`binary-selection-map.md`](binary-selection-map.md) §1.2). Public prior art (GPTP's
`hooks/interface/status_display/*`, teippi's `dialog.h`/`offsets_hooks.h`, BWAPI's `Dialog.h`)
supplied candidate addresses and names; every address used here was re-resolved against this
binary (all resolve to exact function entries) and every load-bearing claim is backed by a
decompiled function or a referencing instruction found by sweep. Query specs:
`tools/ghidra/specs/hud-*.spec`; committed evidence tables: `research/data/hud-*.tsv`;
decompiled C and listings stay under `work/scratch/hud/` (derived game content, gitignored).

Companion documents: [`selection-cap.md`](selection-cap.md) §4.5 and §8 q7 (this document
answers q7), [`selection-circles.md`](selection-circles.md) (the selectionIndex hazard),
[`binary-selection-map.md`](binary-selection-map.md) (the selection globals),
[`command-path.md`](command-path.md) (the command funnel).

---

## 1. Verdict up front

1. **`selection-cap.md` §8 q7 is answered: the status screen is a `.bin` resource plus
   code-bound handlers.** The whole bottom-center status area is ONE dialog loaded from
   **`rez\statdata.bin`** (an MPQ asset). Its 44 controls — including the 12 wireframe
   buttons, control ids **0x21..0x2C** — arrive serialized in the file with their positions;
   code relocates them in place and binds their behaviour afterwards. Layout is data;
   behaviour is code. [§3](#3-how-the-dialog-is-created)
2. **Everything that fills, draws and clicks the row is now mapped**, with one function per
   job: layout `0x00425960`, refresh-condition `0x00424660`, per-button wireframe draw
   `0x00456F50`, button interact `0x004583E0`, click semantics `0x00458220`, dispatcher
   `0x00458120`, per-frame driver `0x004D93F0`. [§4](#4-the-pipeline-per-frame), [§5](#5-the-click-path)

   **The row's own geometry, read off the live dialog** (`QINDDLG` child dump, this install;
   all dialog-local, the pane's surface is **270 × 92** and its root rect is `(138,388,407,479)`
   in client pixels). The twelve buttons are **two rows of six, COLUMN-major** — odd ids on the
   upper row, even ids on the lower — 32 × 33 each:

   | | ids | x | y |
   |---|---|---|---|
   | upper row | `0x21 0x23 0x25 0x27 0x29 0x2B` | 30, 66, 102, 138, 174, 210 (+32) | 8 → 41 |
   | lower row | `0x22 0x24 0x26 0x28 0x2A 0x2C` | same | 45 → **78** |

   Two consequences worth stating, both load-bearing for task 048: the row's lowest edge is **78
   whether two units are selected or twelve** (column-major means any selection of ≥ 2 lights
   both rows), and **`y 79..92` — the surface's last 13 rows — is occupied by no control at all.**
   That band is where `sc_queueind`'s group line goes (task 039) and where the page indicator goes
   (task 048); a small font of height 11 fits it with two pixels to spare, and both modules refuse
   to draw rather than fall back onto the buttons if it ever does not.
3. **The row is driven by exactly one input: `clientSelectionGroup` (`0x00597208`).** The
   layout function walks it to the end sentinel `0x597238` and assigns one unit per button
   into a per-button 8-byte heap record (`statUser`: `{CUnit*, u16 unitId}`). The buttons
   themselves are unit-agnostic — they display and click **whatever unit pointer is put in
   that record**. That is the pivot the designs in §7 turn on. [§4.2](#42-the-layout-function)
4. **The HUD click path never touches `CSprite::selectionIndex`, sprite flag `0x08`, or the
   memmove.** A wireframe click builds a fresh unit list from the buttons' records and routes
   it through `CreateNewUnitSelectionsFromList` (`0x0049AE40`) + `CMDACT_Select`
   (`0x004C0860`) — the same funnel the plugin already hooks. The four dangerous
   `selectionIndex` readers ([`selection-circles.md`](selection-circles.md) §4) live in the
   *map*-click and unit-removal paths, all gated on flag `0x08`, which shadow units never
   carry. **A design that only writes `statUser` records keeps the inherited discipline
   intact by construction.** [§6](#6-hazard-analysis)
5. **Recommendation: PAGING, plus a page-indicator control (hybrid (a)+(c)).** Detour the
   two functions in point 2 that decide and fill the row, feed the buttons from the plugin's
   shadow list one 12-unit page at a time, flip pages with a right-click on the row, and add
   one native text control as the "N units — page i/j" indicator. Everything the engine does
   with buttons — drawing, borders, tooltips, clicks — is reused byte for byte. Widening the
   row (more than 12 visible portraits) is costed honestly in §7b and loses. [§7](#7-candidate-designs), [§8](#8-recommendation)

---

## 2. The dialog data structures in this binary

`BinDlg` — the control/dialog record (GPTP `SCBW/structures.h:284` names the fields; every
offset below is **confirmed by an instruction in this binary**, cited in the table):

| Offset | Field | Confirmed by |
|---|---|---|
| `0x00` | `next` | every child walk below (`puVar3 = *puVar3`) |
| `0x0C` | surface width (dialog) / `event->type` (in events) | `FUN_004c35f0` writes it from `+0x36`; `0x004583E4` reads `[EDI+0xC]` as event type |
| `0x10` | surface pixel buffer (dialog) | `FUN_004c35f0`: `SMemAlloc(w*h, "status.cpp", 0xB5)` stored at `+0x10` |
| `0x14` | `pszText` | relocator `0x004194E0` fixes it up |
| `0x18` | `flags` (u32; bit `0x8` = visible) | `0x0045845D` `TEST byte ptr [ESI+0x18],0x8`; hide/show at `0x00418700`/`0x004186A0` |
| `0x20` | `index` (s16 control id) | layout walk compares `[ctrl+0x20] == 0x21`; binder indexes table with it |
| `0x22` | `controlType` (0 = dialog) | every "is this the root" test (`[x+0x22] != 0 → parent`) |
| `0x24` | `graphic` | wireframe draw writes border ids 0x0D/0x13/0x19/0x1F here |
| `0x26` | `user` / `statUser` | button CREATE allocates 8 bytes into it; click reads `**(int**)(ctrl+0x26)` |
| `0x2A` | `fxnInteract` | relocator + binder both store here |
| `0x2E` | `fxnUpdate` | `0x0045841C` `MOV [ESI+0x2E],0x456F50` |
| `0x32` | `parent` | click handler climbs `[ctrl+0x32]` |
| `0x42` | first child (dialog) | every child walk starts at `[dlg+0x42]` |

The **statUser record of a wireframe button is 8 bytes on the heap**: allocated in the
button's CREATE case (`0x0045841A` `PUSH 0x8` → `SMemAlloc(8, "statdata.cpp", 0x307)`,
stored at `+0x26`), written by the layout function as `{+0: CUnit*, +4: u16 unitId}`
(`0x00425960`: `*piVar2 = unit; *(u16*)(piVar2+4) = unit->unitId`), read back by the click
handler (`**(int**)(ctrl+0x26)`) and by the wireframe draw (`+4` is the grp frame index).

Global state of the status module (module = the code carrying `statdata.cpp` /
`status.cpp` / `statwire.cpp` / `statres.cpp` / `statcmd.cpp` debug strings):

| Address | What | Evidence |
|---|---|---|
| `0x0068C1F0` | **the statdata dialog pointer** | written `0x004586B4` (init), `0x00456F0A` (teardown, to 0); read by dispatcher `0x00458120` |
| `0x0068C1F4` | `unit\wirefram\tranwire.grp` handle | init `0x00458585` passes the string at `0x00504AD4`; freed in `0x00456EF0` (`statdata.cpp:0x552`) |
| `0x0068C1FC` | `unit\wirefram\grpwire.grp` handle — **the row's wireframe art** | init `0x0045859B` passes the string at `0x00504AB8`; the per-button draw `0x00456F50` reads frames out of it |
| `0x0068C1F8` | status-display dirty flag (`bCanUpdateStatDataDialog`) | set by clicks (`0x00458220` tail) and binder; consumed by dispatcher |
| `0x0068C1E5` | "children currently hidden" state byte | dispatcher + layout fn |
| `0x0068C1E8`, `0x0068C1EC` | mouse-over control state | cleared in click tail; `0x0045846B` compares against `0x0068C1E8` |
| `0x006CA94C` | u32[12] per-slot HP cache | refresh-cond `0x00424660` compares `unit+0x08` against it; filled by `0x00424540` |
| `0x006CAD7C` | u16[12] per-slot unit-id cache | same pair of functions, `unit+0x64`; empty slot = 0xE4 (228, none) |
| `0x00504AF0` | **44-entry interact-fn table indexed by control id** | 12 rows at `+0x80..+0xAC` (= ids 33..44) all hold `0x004583E0` (sweep `hud-fnrefs2.tsv`; raw bytes re-decoded from the file image independently of Ghidra) |
| `0x005014AC` / `0x00501504` | default interact / update tables indexed by controlType | relocator `0x004194E0` lines 42-43; default dispatch tail `JMP [type*4+0x5014AC]` at `0x00458494` |

---

## 3. How the dialog is created

The chain, each arrow a decompiled function (`work/scratch/hud/decomp*/`):

```
0x004EED10  game-start reset
  └─ 0x004C3BB0  console init
       └─ 0x00458570  statdata init                       "statdata.cpp" 0x537..0x546
            ├─ loads unit\wirefram\tranwire.grp  → 0x0068C1F4
            ├─ loads unit\wirefram\grpwire.grp   → 0x0068C1FC
            ├─ SFileOpenFileEx / SFileReadFile "rez\statdata.bin" → one heap buffer
            ├─ 0x004194E0  IN-PLACE RELOCATOR over the serialized controls:
            │    fixes next/pszText/smk pointers by the load delta,
            │    fxnInteract = 0x005014AC[type], fxnUpdate = 0x00501504[type],
            │    parent = buffer base (the root dialog is the first record)
            ├─ buffer base = the dialog; flags |= 4;  0x0068C1F0 = it
            └─ 0x00419D20  add to the global dialog list (0x006D5E34)
```

The root dialog's own interact is `0x004584F0` (recovered from undefined bytes; listing in
`work/scratch/hud/binder2-listing.tsv`). On **BW_EVN_USER + BW_USER_CREATE** it calls the
**binder** `0x004584C0`:

```
0x004584C2  MOV ECX,0xB0            ; 176 bytes = 44 entries
0x004584C7  MOV EDI,0x504AF0        ; the per-index interact table
0x004584CE  CALL 0x00418100         ; for every control with index>0:
                                    ;   fxnInteract = table[index-1]  (if non-NULL)
0x004584D3  CALL 0x004C35F0         ; alloc the dialog surface (status.cpp:0xB5)
0x004584D9  MOV byte [0x0068C1F8],1 ; mark dirty
```

`0x00418100` is generic (EAX = dialog, ECX = table size, EDI = table): it recursively walks
children and overwrites `+0x2A` from the table by control id. Ids 33..44 → `0x004583E0`,
the wireframe-button interact. That function's own CREATE case then binds the button's
update handler and allocates its statUser record:

```
0x0045841C  MOV dword [ESI+0x2E],0x456F50   ; fxnUpdate = wireframe draw
0x00458423  MOV word  [ESI+0x24],0x0        ; graphic = 0
0x0045842E  MOV [ESI+0x26],EAX              ; statUser = SMemAlloc(8)
```

**Consequence for the designs:** control *positions* live in the asset (`rez\statdata.bin`),
which is read-only to us (game-file rules), but every *behavioural* binding happens in code
at CREATE time, against whatever controls exist in the dialog's child list — and the child
list is ordinary writable heap memory at runtime. A control spliced into that list at
runtime with a valid id/type/bounds is indistinguishable from a loaded one.

## 4. The pipeline, per frame

### 4.1 The driver

`0x004D93F0` (called from `0x004D9530` ×2 and `0x004D9840`):

```c
if (client_selection_changed /*0x0059723C*/) { updateSelectedUnitData(); /*0x004C38B0*/
                                               client_selection_changed = 0; }
...
FUN_004599A0();          // button-panel counterpart (statcmd)
statDataUpdate();        // 0x00458120 -- the status-area dispatcher
```

`updateSelectedUnitData` (`0x004C38B0`, decompiled — matches
[`binary-selection-map.md`](binary-selection-map.md) §6.2 exactly): copies
`activePlayerSelection` → `clientSelectionGroup` (12 dwords), recounts
`clientSelectionCount` (`0x0059723D`), picks the portrait unit (`0x00597248`) by rank
(`0x0049A350`), single-unit special case, then tail-calls `0x00458DE0` (dirty helper).

### 4.2 The dispatcher and the layout function

`0x00458120` (decompiled; GPTP `stats_display_main.cpp` is an exact description):

- portrait unit NULL → hide all children of `0x0068C1F0`, clear state, done;
- `clientSelectionCount == 1` → per-unit-type cond/act via the table at `0x005193A0`
  (3 dwords per unit type: `[unused, condFn, actFn]`, indexed `unitId*0xC`);
- **else (the multi-select row)** → cond `0x00424660`; if it says stale (or the dirty flag
  is set) → act `0x00425960`.

Cond (`0x00424660`, decompiled): walks `clientSelectionGroup` against the HP cache
(`0x006CA94C`, vs `unit+0x08`) and id cache (`0x006CAD7C`, vs `unit+0x64`), bounded by the
end sentinel `0x597238`. Any mismatch → refresh needed.

**Act — the layout function** (`0x00425960`, decompiled), the single place the row's
content is decided:

```c
if (!allHiddenByte_0068C1E5) { hide every child; 0x0068C1E5 = 1; }
refreshCaches();                                   // 0x00424540
ctrl = find child with index == 0x21;              // FirstSmallButton
for (slot = &clientSelectionGroup[0]; slot < 0x597238; ++slot) {
    if (*slot == NULL) continue;                   // button NOT advanced -- units pack left
    ctrl->statUser->unit   = *slot;                // +0
    ctrl->statUser->unitId = (*slot)->unitId;      // +4  (grp frame index)
    show(ctrl);                                    // 0x004186A0
    if (!(ctrl->flags & 1)) { ctrl->flags |= 1; update(ctrl); }   // 0x0041C400
    ctrl = ctrl->next;
}
for (; ctrl; ctrl = ctrl->next) { hide(ctrl); if (ctrl->index == 0x2C) break; }
```

### 4.3 The wireframe draw

Per-button `fxnUpdate` = `0x00456F50` (decompiled): reads `statUser->unit`, picks the
border id into `graphic` (+0x24) — `0x1F` hallucination (`unit+0xDC & 0x40000000`), `0x13`
hero (units.dat flags bit 0x40 at `0x00664080`), `0x19` parasited (`unit+0x121`), else
`0x0D` — draws borders (`0x00456D30`), computes the HP/shield colour remaps into the
palette registers `0x0050CE81..0x0050CE9C` (`0x004567C0`, `0x004566B0`, `0x00456730`), then
blits the **`grpwire.grp` frame indexed by `statUser->unitId`** (`0x0068C1FC`, frame count
guarded by `*grp & 0x7FFF`). Everything it needs is the 8-byte record plus static art.

## 5. The click path

Button interact `0x004583E0` (listing `work/scratch/hud/binder-listing.tsv`): a switch on
`event->type`/`dwUser`. `BW_USER_ACTIVATE` (a completed click) → `EDX = ctrl` →
**`0x00458220`**, the click semantics (decompiled; teippi `StatusScreenButton` matches):

- **plain click**: the one unit in `clicked->statUser->unit` becomes the new selection —
  `CreateNewUnitSelectionsFromList(1, &unit)` (`0x0049AE40`) then
  `CMDACT_Select(1, &unit)` (`0x004C0860`);
- **shift-click** (`0x00596A28`): collect from the 12 buttons every *visible* (`flags & 8`)
  button's unit except the clicked one → new selection (that is how "remove this one from
  the selection" is implemented — by re-selecting the rest);
- **ctrl-click** (`0x00596A29`): collect every visible button whose unit's `unitId` matches
  the clicked one → select that type;
- **alt** (`0x00596A2A`): encode the clicked unit's tag
  (`(uniqueness << 11) | index`, unit array base `0x0059CCA8`, cap `0x6A4` — same encoding
  the fan-out uses) → `0x00496D30` recalls the recent hotkey group containing it;
- tail, all paths: dirty flag `0x0068C1F8 = 1`, mouse-over state cleared,
  `client_selection_changed (0x0059723C) = 1`.

Two facts worth stating twice:

1. The collection loops read **only the buttons' statUser records** — never the selection
   arrays, never sprites. The buttons are the source of truth for what a click means.
2. Both funnels the clicks feed into (`0x0049AE40`, `0x004C0860`) are **already hooked by
   the existing plugin** (sc_circles pre-hook and sc_fanout respectively), so HUD-initiated
   selection changes flow through the shadow-list bookkeeping like any other selection
   change, with no new work.

### 5.1 How a raw mouse event reaches a wireframe button (the page-flip gesture)

The button interact `0x004583E0` branches on `event->type` (`event+0x0C`): type `3`
(`MOUSEMOVE`) and type `14` (`USER`, whose `dwUser` at `event+0` selects activate/prev/next).
It does **not** handle the raw button events — those fall through to the default. The routing
from a raw event to a control is the default dialog interact `0x00418EB0` (decompiled,
`work/scratch/hud/decomp5/`), whose `switch(event->type)` groups the mouse-button events:

```c
case 4: case 6: case 7: case 9:              // LBUTTONDOWN, LBUTTONDBLCLK, RBUTTONDOWN, RBUTTONDBLCLK
    ctrl = hitTestChildUnderCursor();        // 0x00418340
    if (ctrl) { ...; return (*(int(**)())(ctrl + 0x2A))(); }   // that control's interact, SAME event
```

So a **right-click over a wireframe button is delivered to that button's interact with
`event->type == 7`** — and the stock interact ignores type 7 (right-clicking a portrait does
nothing in vanilla), which is exactly why the gesture is free to claim. The plugin wraps the
12 buttons' interact pointers (`control+0x2A`, plain dialog-heap data — no code is patched)
with a shim that returns on type 7 after flipping the page and tail-calls `0x004583E0` for
every other event, so left/shift/ctrl/alt clicks keep their stock meaning on whatever the row
currently shows. The call convention is `__fastcall(ECX = control, EDX = event)` — the same as
the engine's own interact, confirmed by the register setup at the `0x00418EB0` call site.

## 6. Hazard analysis

The task's inherited, non-negotiable rule: shadow units must never receive
`CSprite::selectionIndex` or sprite flag `0x08`
([`selection-circles.md`](selection-circles.md) §4: four readers, all memmove-or-reattach,
all gated on flag `0x08`; no safe index value exists).

**The entire HUD row subsystem mapped above contains zero accesses to either field.** The
row's input is `clientSelectionGroup` (unit pointers), its working state is the per-button
statUser records, its output is wire commands. Specifically:

| Path | selectionIndex? | flag 0x08? |
|---|---|---|
| layout `0x00425960` | no — writes statUser only | no |
| draw `0x00456F50` + helpers | no — reads unit HP/shield/type fields | no |
| click `0x00458220` | no — reads statUser, emits Select | no |
| the four dangerous readers (`0x0046FD77`, `0x0049F7B3`, `0x0049F00B`, `0x0049F8B6`) | in the MAP-click / removal / owner-change / rebuild paths, not reachable from the HUD row, and all four gated on flag `0x08` | gate |

So the safety statement for any design that presents a shadow unit in the row **without
writing those fields** is: put its pointer in a statUser record. The engine will draw it and
click it exactly as it draws and clicks engine-selected units, because nothing in this
subsystem ever asks whether the unit is engine-selected. A click on a shadow unit's slot is
then a *fresh selection* of that unit — semantically identical to vanilla's wireframe click,
handled end-to-end by unmodified engine code.

What a shadow unit in the row does still require: the pointer must stay valid. statUser
records go stale between refreshes (a displayed unit can die). Vanilla has this exposure
too — `0x0049F7A0` clears the unit out of `clientSelectionGroup` on death, but statUser
keeps the old pointer until the next act run. It is memory-safe in vanilla because CUnit
slots are static array entries (`0x0059CCA8` + n×0x150), recycled, never freed — reads give
wrong-but-harmless pixels for a frame.

### 6.1 The stale-pointer exposure CLASS, closed structurally (stage B)

A shadow page can display an overflow unit whose state changed since it was captured —
killed, freed by a trigger, archon-consumed, or merely dropped from the visible selection
(transport-loaded, mind-controlled). The *dangerous* case is narrow: a click that hands the
engine a **freed** `CUnit*` whose tag still passes the receive-side uniqueness check, so a
no-longer-real unit enters engine selection — where vanilla self-heals in one frame. sc_hudrow
closes that class with two structural measures rather than one detector per removal path:

1. **Detection ≠ removal-path.** Death is one signal (`hitPoints == 0`, `CUnit+0x08`, the
   field the damage primitive `0x004797B0` zeroes — [`command-opcodes.md`](command-opcodes.md)
   §6); slot reuse is another (`CUnit+0xA5` bumped by `0x004A0320`). The **rest** are caught
   without a per-path signal: each dispatch compares the engine's own visible selection
   (`clientSelectionGroup`, `0x00597208`) against the shadow's visible tail, and on a
   divergence with no new commit behind it the row **hands back to stock** and stays there
   until the next `CMDACT_Select` commit. The engine then shows its own truth — removed units
   gone by construction — with no per-frame churn.

2. **The click gate.** Before the engine's click handler receives a button's statUser
   `CUnit*` (on the `BW_USER_ACTIVATE` = 2 sub-event that `0x004583E0` routes to `0x00458220`
   — jump table at `0x0045849C`), sc_hudrow validates it: displayed, uniqueness unchanged,
   `hitPoints > 0`, **and reachable in its owning player's unit list**. The unit list is
   `playerUnitList` at `0x006283F8` (per-player heads, indexed by the unit's owner), threaded
   through `CUnit+0x68`/`+0x6C` — decompiled from the unit (re)init `0x004A0320`, which
   head-inserts a unit into `playerUnitList[player]`; the removal path `0x004A0740` **unlinks**
   a unit removed from play. So a unit **removed from play** (killed-and-not-recycled, trigger
   RemoveUnit, archon-consumed) is *not reachable* from its player's list head, no matter which
   path dropped it, and its click is **swallowed** (the engine never sees the stale pointer)
   with the row latched to stock. The array's element count is not evidenced here; the gate
   reads only indices `< 8` (`SC_MAX_PLAYERS`), which is fail-closed for any size.

   Two live cases deliberately **pass** the gate, and that is correct: a **transport-loaded**
   unit stays linked in its player's list (the engine walks the list for supply, loaded units
   included), and a **mind-controlled** unit relinks under its new owner (the walk reads the
   current `CUnit+0x4C`). Both are live, identity-correct `CUnit*`s that vanilla can select, so
   handing one to the engine is harmless. The point of the gate is only the *dangerous* case —
   a **freed/removed** slot whose tag would still pass the receive-side uniqueness check. When
   the engine drops a loaded/controlled unit from the *visible* selection, measure (1)'s
   divergence latch catches it separately and the row hands back to stock, so it is never kept
   on offer.

These, plus the same bounds/stride and `CUnit+0xA5` guards the circles module uses, are what
make the shadow page safe.

## 7. Candidate designs, costed

### (a) PAGING — row still shows 12; a gesture cycles which 12 of N

**What changes.** One new plugin module (sc_hudrow), one detour, no engine data widened.
**Design note, settled during stage B:** the single clean hook is the per-frame **dispatcher
`0x00458120`** (§4.2), not the act/cond pair `0x00425960`/`0x00424660` this section first
proposed. Detouring the dispatcher is what lets the module restore stock even when a shadow
click drops the selection to *one* unit — the engine then takes its single-portrait branch
and never calls the multi-select act, so a detour on act alone could never hand back.
`0x00458120` has a 5-byte reloc-safe prologue (`MOV EAX,[0x00597248]`) and one caller. The
module reproduces the act loop's effect for a page and throttles its own re-fill exactly as
cond throttles the engine's layout.

1. **Detour `0x00458120` (dispatcher).** Shadow count ≤ 12 → tail into the original
   dispatcher (stock single-portrait and stock ≤12 multi both run untouched). Shadow count
   > 12 → run our re-implementation of the §4.2 loop (≈15 lines against the already-mapped
   primitives `0x004186A0`/`0x00418700`/`0x0041C400`), sourcing the 12 buttons from
   `displayList[page*12 .. page*12+11]` with a per-unit staleness guard, and skip the
   engine's own layout for that frame.
2. **Throttle the re-fill** the way the engine's cond throttles: re-lay-out only on a
   page-flip, a shadow-list change, a unit death on the displayed page, or HP/id drift of a
   displayed unit (own 12-entry cache, the same comparison `0x00424660` makes). On a quiet
   frame the page persists — nothing else writes the status buttons once the dispatcher is
   skipped.
3. **Page state**: current page, reset to 0 whenever the shadow list changes. sc_fanout
   exposes a version counter bumped on every selection commit (and on hotkey-recall drop),
   so the module snaps to page 1 on any selection change without diffing lists.
4. **The gesture**: right-click on any wireframe button. Implemented by wrapping the 12
   buttons' `fxnInteract` (+0x2A) with a thin shim — event type `7` (RBUTTONDOWN) → page++,
   dirty flag = 1, return 1; anything else → tail-call the engine's `0x004583E0`. The wrap
   is (re)applied idempotently from the dispatcher detour, which also survives dialog
   re-creation (the binder rebinds at every CREATE; our next paged frame re-wraps).
   Right-click is free real estate, and §5.1 confirms from the binary that a right-click over
   a wireframe button reaches the button's interact as event type 7 (the stock interact
   ignores it).
5. Calling conventions, all verified against this binary: the dispatcher takes no arguments
   (5-byte prologue splice, same `ScHookInstall` machinery as the existing hooks); the button
   shim is `__fastcall(ECX = control, EDX = event)` matching the engine's own interact (§5.1).

**selectionIndex / flag-0x08 discipline**: untouched by construction (§6) — the module
writes statUser records and two module-private globals, nothing else. The hooktest poison
assertions (task 014 part [8] pattern) extend directly.

**A click on a shadow slot**: fresh selection of that unit via unmodified engine code (§6).
After the click the engine selection is that one unit; the fan-out records the new shadow
list (of 1); the row follows. Identical to vanilla semantics.

**What can go wrong, named**: (1) a stale pointer put in statUser draws a wrong wireframe
for a frame — same exposure class as vanilla, bounded by the per-fill guards; (2) the count
== 1 dispatcher branch (portrait view) triggers on *engine* count — with fan-out holding
min(N,12) ≥ 2 whenever N ≥ 2, the multi path is taken exactly when it should be; (3) a
page showing units 13..24 while the engine's 12 are units 1..12 means shift/ctrl-click
collection (which reads visible buttons) operates on the *displayed* page — coherent, but
it must be stated in the UX: row gestures act on what the row shows; (4) mid-game plugin
unload leaves wrapped fxnInteract pointers → same policy as circles: unload mid-game is
unsupported (process exit is fine, the address space goes away… but the dialog outlives a
*detach* — the remove path must unwrap the 12 pointers and un-splice the two detours under
suspend, which IS feasible here because unlike image lists, pointer writes are atomic).

**Cost**: small. Two detours + a pointer wrap + page arithmetic; every visual element is the
engine's own.

### (b) WIDENING — more than 12 portraits drawn

**What it would take.** The buttons are heap records in a linked list, so adding 12 more is
mechanically possible without touching the asset: allocate 12 `BinDlg` clones (86 bytes +
8-byte statUser each), ids 0x2D.., copy type/flags/handlers from a real button, splice into
the child list, and extend the act/cond detours from (a) to fill 24. The engine's binder
table stops at id 44, but our clones can carry their fxnInteract directly.

**Why it loses anyway:**

1. **There is no space.** The buttons render into the dialog's own surface (allocated
   w×h from the dialog record at `0x004C35F0`); anything outside its bounds is not drawn.
   Inside the console art, the 12-button box is bounded left by the minimap and right by
   the command card; the free pixels around it are single-digit rows. Smaller portraits are
   not an option either: the draw fn blits fixed `grpwire.grp` frames — scaling would mean
   replacing `0x00456F50` and its three colour helpers with our own renderer.
2. Positions for the new controls would be invented by us over Blizzard art — permanently
   wrong-looking without asset edits, which the game-file rules forbid.
3. Cost concentrates in exactly the code we otherwise reuse for free (draw + borders +
   palette), for a UI that fits at most ~6 more portraits before it collides with art.

Everything else (hazard discipline, click semantics) is identical to (a) — widening is
strictly (a) plus surgery on the draw layer, minus visual quality.

### (c) Hybrid — paging plus a "+N more / page i/j" indicator

(a) plus one runtime-created control: a text control (LSTATIC-class type, so the *default*
type tables `0x005014AC`/`0x00501504` give it draw/interact for free), id in unused space
(e.g. 0x50), bounds inside the row box's margin, `pszText` = plugin-owned buffer like
`"36 units  13-24  (2/3)"`, updated by the act detour. One heap record, engine-drawn.
Cost on top of (a): trivial. Value: the row stops *silently* paging — the count the user
asked for ("show more units") is permanently visible even without flipping.

> **This shipped, and it did not draw. (Task 033, 2026-08-11.)** The control was spliced, the
> string was written and the suite went green — asserting that string **out of the module's own
> buffer**, which proves the plugin's intent and nothing about the player's screen. The box was
> nine pixels tall, and the engine's text routine returns without drawing anything at all when
> `top + fontHeight > clip.bottom`, where the clip box is the control's own bounds
> ([`status-pane-text.md`](status-pane-text.md) §5). So for weeks the row paged silently
> anyway, and on 2026-08-11 the user asked the conductor how to page through it — a question
> a visible `(2/3)` would have answered.
>
> Fixed in task 033: the box is `SC_QIND_BOX_H` tall, and `HUDROW show` now reports
> `indLinked` / `indVisible` / `indBounds` / `indInk`, the last being a count of non-background
> bytes the engine left in the dialog's own surface inside that box. `test-hud-row.ps1` asserts
> `indInk > 0`. This is AGENTS.md's "assert the ENGINE's own result, not your bookkeeping" meeting
> a *drawing* claim: reading a control's fields says what it HOLDS; only the surface says
> anything was DRAWN.
>
> **And it STILL did not draw, for three more tasks. (Task 048, 2026-08-12.)** The box was tall
> enough after 033 and the text was still never on the screen, because the control was spliced at
> the **head** of the child list: the dialog's redraw walk `0x0041C683` takes the children from
> `[dlg+0x42]` and steps `[esi]` head to tail, so a control earlier in the list is painted *under*
> the ones after it, and the twelve wireframes it overlapped painted over it every frame. Task 039
> found and fixed exactly this in `sc_queueind` on 2026-08-12; the same defect was still here.
>
> `indInk` could not report it, and the shape of that failure is now a rule in AGENTS.md. The box
> `(32,9,180,25)` is 148 × 16 = **2368** bytes and `indInk` read **2368 — the whole area —
> identically for three different strings** in one run. Ink over a region the engine also paints
> saturates: it fails by looking healthy, never by reading zero, which is the one case the
> positive control 033 added cannot catch.
>
> What task 048 replaced it with, all on the same line and none of them an ink count:
>
> | field | what it answers |
> |---|---|
> | `indBoxDiff` | bytes of the band that differ from a copy of the SAME rect taken with none of our line on it — the only number here that says the engine drew |
> | `indRefInk` / `indSurfInk` | the two blindness checks: a control the engine fills, and the whole surface |
> | `HUDROW band after stock` | `glyphBytes` / `stranded` — how many bytes our line owned, and how many still hold its value after the row hands back |
>
> Measured, fixed build, one run: `indBounds=(30,79,184,92) indBoxDiff=268 indRefInk=1056
> indSurfInk=24840 indFontH=11`, and `glyphBytes=237 stranded=0` on each of three hand-backs.

## 8. Recommendation

**(c): paging with the native page-indicator control; right-click on the row flips pages.**
Reasons, in order:

1. It answers the user's actual complaint — the HUD lying about a >12 selection — with the
   count always on screen and every unit reachable in ≤ ⌈N/12⌉ gestures.
2. It reuses every engine element (art, borders, HP colours, tooltips, click semantics),
   so it looks native because it *is* native — the plugin only decides *which 12*.
3. Its write surface is two module-private globals + statUser records + one text buffer.
   The selectionIndex/flag-0x08 discipline is untouched by construction, provable offline
   with the existing poison-assert pattern.
4. Widening is the only design that buys "more than 12 visible at once", and §7b shows it
   buys ~6 crowded portraits for the cost of reimplementing the draw layer over art that
   has no room. If the user wants it later, (a)'s detours are its prerequisite anyway —
   nothing in (c) is throwaway.

## 9. Proposed stage-B test oracle

Following the established discipline (pinned ids, positive asserts, try/finally,
`-ProcessId`, SHA-256 before/after, no vacuous passes):

1. **Offline (hooktest)**: drive sc_hudrow against a fake dialog tree + fake shadow list —
   page math, statUser writes, wrap/unwrap idempotence, stale-unit guards — with the
   task-014 poison assertions: every fake sprite's `selectionIndex` poisoned, flag `0x08`
   asserted never set, plus (new) the fake engine act/cond called only when the shadow path
   is inactive.
2. **In-game, unattended** (`drive-game.ps1` + a 36-unit fixture from `make_test_map.py`):
   - drag-box 36 units → assert plugin log `HUDROW n=36 pages=3 page=1/3` and the logged
     12 statUser unit tags equal shadow[0..11] (**in-process UI-state read: the module logs
     the ids straight out of the live dialog's button records after each act run** — that
     read-back, not the write path, is the oracle);
   - post a right-click at a logged button rect → assert `page=2/3` and the 12 logged tags
     equal shadow[12..23];
   - post a left-click at a logged page-2 button → assert a 1-unit `0x09 Select` carrying
     exactly that unit's tag on the wire (the existing queueCommand hook logs it), and the
     next act log shows the row following the new 1-unit selection;
   - indicator text asserted from the module's own buffer log line.
3. **Frame capture** (PrintWindow, task 014 technique): grab the row region before/after a
   page flip and assert the pixels differ; frames stay outside the repo. Corroboration,
   not the oracle.
4. Existing three suites stay green; exe SHA-256 asserted unchanged before launch and after
   close.

## 10. Provenance and open questions

**Verified directly against this binary in this task**: every address in §2-§5 — 22
functions decompiled (`work/scratch/hud/decomp*/index.tsv`, all `exact-entry` except the
two recovered orphan blocks read as listings), the 44-entry interact table (Ghidra sweep +
independent raw-byte decode of the file image with the PE section table parsed from the
file itself), the three `.rdata` strings (`rez\statdata.bin`, `unit\wirefram\grpwire.grp`,
`unit\wirefram\tranwire.grp`) and which global each feeds. Committed sweep tables:
`research/data/hud-xrefs.tsv`, `hud-fnrefs.tsv`, `hud-fnrefs2.tsv`, `hud-fnrefs3.tsv`,
`hud-fnrefs4.tsv`.

**Inherited and used as corroboration**: GPTP's C reimplementations (they match the
decompiles everywhere they overlap — `UnitStatCond/Act_Selection`, the wireframe fragment,
`stats_display_main`), teippi's `StatusScreenButton` semantics and control-id constants
(`FirstSmallButton = 0x21`), BWAPI's control-flag names (`CTRL_VISIBLE = 0x8`, event ids).

**Open, stated rather than hidden**:

1. ~~The exact bounds of the 12 buttons (and of usable free margin) live in
   `rez\statdata.bin`; stage B should read them from the live dialog at attach and log
   them, not hardcode.~~ **ANSWERED** — stage B logs the button rects (`HUDROW rects`), and
   task 033 added a full child dump of the same dialog (`QINDDLG`: id, type, flags, bounds,
   update handler, text, one line per control). The production strip's live bounds are
   tabulated in [`status-pane-text.md`](status-pane-text.md) §8; every position in both
   modules is computed from a control's live bounds rather than from those numbers.
2. `0x00457DE0` (mouse-over/tooltip path) was located but not decompiled; paging does not
   alter it (the buttons stay engine-owned), but the indicator control's bounds must not
   overlap a tooltip hotspot without checking.
3. The dispatcher branch for `clientSelectionCount == 1` (per-unit-type table `0x005193A0`)
   was mapped but its per-type act functions were not read; irrelevant while the multi
   path is the one being changed.
4. Whether any code other than `0x00425960` and the button CREATE case writes statUser
   records: not swept exhaustively; GPTP documents none, and the click/draw paths read
   only. A stage-B assert (log-if-changed between act runs) turns this assumption into a
   measurement.
