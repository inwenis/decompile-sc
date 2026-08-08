# The 12-unit selection cap in StarCraft 1.16.1 — recon

Survey date: 2026-08-06; revised 2026-08-07 after adversarial citation review (see §10 for what
changed). Target: **StarCraft: Brood War 1.16.1** (classic). Scope: public sources only.
No binary was opened, no game file was touched, no address was derived by us — every offset below is
quoted from a named public source. Anything not verifiable is marked **[unverified]**; anything we
computed from cited numbers is marked **[inference]**.

Companion document: [`prior-art.md`](prior-art.md) — read it for the ecosystem map (OpenBW, BWAPI,
GPTP, samase, teippi, file formats, version split). This document does not repeat it; it cites into it.

## 0. Sources and how they were read

Five public code bases were cloned and grepped locally; citations are `file:line` against these commits.

| Short name | Repo | Commit read | What it is (see [`prior-art.md` §1–§3](prior-art.md)) |
|---|---|---|---|
| **BWAPI** | https://github.com/bwapi/bwapi | `d727fed` (2026-05-08) | Injected DLL for 1.16.1; `Source/BW/` = community-validated struct + offset map |
| **GPTP** | https://github.com/BoomerangAide/GPTP | `ce321f0` (2022-05-13) | Plugin template; hooks are hand-reversed C reimplementations of named 1.16.1 functions, each carrying its address in a comment |
| **teippi** | https://github.com/neivv/teippi | `05c006c` (2018-01-30) | neivv's "removes several limits" 1.16.1 modhack; `src/offsets.h` is a large named global map |
| **OpenBW** | https://github.com/OpenBW/openbw | `8265ec4` (2026-07-16) | Behavioral reimplementation of the 1.16.1 simulation; no addresses, but authoritative on *semantics* |
| **screp** | https://github.com/icza/screp | `75fcdff` (2026-07-19) | Replay parser; the living spec for the command stream |

Method: grep for selection symbols in each, cross-check claims between at least two independent
sources, and record disagreements rather than picking a winner (see §8, open question 5).

---

## 1. Verdict up front

1. **It is not one constant.** The number 12 is baked into **five separate fixed-size global
   arrays**, the wire format of three network commands, the status-screen dialog, and roughly two
   dozen functions that walk those arrays with a hardcoded bound.
   The community's own answer (Heinermann, 2010, quoted in §5) says the same thing.
2. **No open-source project has raised it on 1.16.1** — but closed-source Battle.net hack tools
   apparently did, by fanning out commands rather than widening the engine. The most capable
   *open* limit-removal plugin for this exact binary (neivv's, the teippi lineage) removes the
   unit/sprite/bullet/image/order limits and explicitly leaves selection at 12. Two 1.16.1 hack
   tools (Zynastor's *Oblivion*, salvinger's *Selection Hack*) are described as selecting and
   commanding up to ~252–255 units while the on-screen selection circles stay at 12 — the exact
   signature of candidate #1 below. See §5.
3. **A raised cap cannot work against vanilla multiplayer** — but that is not a real cost here.
   Everyone in a game must run the identical binary+plugin. See §6. The user only needs offline
   single-player, so this is a non-issue, and it removes the hardest constraint from the design.
4. **There is a low-risk path that delivers the user-visible feature without touching the cap at all**
   (fan out one player intent into several 12-unit `Select`+order pairs — exactly what every BWAPI bot
   already does). It is ranked #1 in §7 as the first milestone; the true cap raise is #2.
5. **The naive "patch 12 → 24" byte edit will corrupt memory**, because the arrays are fixed-size
   globals with other globals hard behind them — `playersSelections` starts at the exact byte
   `activePlayerSelection` ends, and the largest gap we can measure anywhere is 4 bytes (one slot).
   See §7, candidate 5, and §2.3.

---

## 2. The selection data model

### 2.1 The constant

| Source | Symbol | Value |
|---|---|---|
| BWAPI `bwapi/BWAPI/Source/BW/Constants.h:23` | `MAX_SELECTION_COUNT` | 12 |
| GPTP `GPTP/SCBW/structures.h:12` | `SELECTION_ARRAY_LENGTH` | 12 |
| teippi `src/limits.h:14` | `Limits::Selection` | 12 |
| OpenBW `actions.h:20` | `static_vector<unit_t*, 12>` | 12 (literal) |

Four independent reversers agree. This is the single most-cited number in the subsystem, and every
one of them expresses it as an *array length*, not as a policy check.

### 2.2 The globals (1.16.1 addresses, all quoted, none derived by us)

| Address | Name (source) | Shape | Cited at |
|---|---|---|---|
| `0x00597208` | `ClientSelectionGroup` / `clientSelectionGroup` / `client_selection_group` | `CUnit*[12]` | BWAPI `BW/Offsets.h:145`; GPTP `SCBW/scbwdata.h:74`; teippi `src/offsets.h:319` |
| `0x00597238` | `clientSelectionGroupEnd` | GPTP's symbol is a compile-time constant, not an observed datum (`#define SCBW_DATA(type,name,offset) type const name = (type)offset;`, `scbwdata.h:11`) — but **the binary settles what is there, and it is occupied twice over**: 44 instructions compare a register against the literal `0x597238` as a loop end-sentinel, and two more read and write it as a HUD/console global (`MOV EAX,[0x00597238]` at `0x004C3880`, `MOV [0x00597238],EAX` at `0x004C3A09`). Not a spare slot | GPTP `SCBW/scbwdata.h:11, 75`; [`binary-selection-map.md`](binary-selection-map.md) §3.1 |
| `0x0059723C` | `client_selection_changed` (a.k.a. `bCanUpdateSelectedUnitData`) | `u8` | teippi `src/offsets.h:323`; GPTP `hooks/interface/selection.cpp:446` |
| `0x0059723D` | `ClientSelectionCount` | `u8`. BWAPI and GPTP say `u8`, teippi types it `offset<uint32_t>` (`offsets.h:322`); **resolved from the binary in favour of `u8`** — all 23 accesses are byte-width, not one dword access exists | BWAPI `BW/Offsets.h:146`; GPTP `scbwdata.h:76`; teippi `offsets.h:322`; [`binary-selection-map.md`](binary-selection-map.md) §7.2 |
| `0x00597248` | `primary_selected` / `activePortraitUnit` | `Unit*` | teippi `src/offsets.h:328`; GPTP `scbwdata.h:425` |
| `0x0059724C` | `client_selection_group2` | `Unit*[12]` | teippi `src/offsets.h:320` |
| `0x006284B6` | `selection_iterator` / `selectionIndexStart` | `u8` | teippi `offsets.h:325`; GPTP `scbwdata.h:346` |
| `0x006284B8` | `activePlayerSelection` / `client_selection_group3` | `CUnit*[12]` | GPTP `scbwdata.h:347`; teippi `offsets.h:321` |
| `0x006284E8` | `playersSelections` / `selection_groups` | `CUnit*[8][12]` | GPTP `scbwdata.h:352-353`; teippi `offsets.h:324` |
| `0x0057FE60` | `selection_hotkeys` | `[8][18][12]`, 4 bytes/entry. Shape **confirmed from the binary** (864-byte per-player stride, 48-byte per-group stride, 1728-dword clear); entries are `StoredUnit` u32s `(uniqueness << 11) \| index`, **not** `Unit*` — see §8 q5 | teippi `offsets.h:326`; GPTP `CMDRECV_Selection.cpp:28` + index math at `:38`; [`binary-selection-map.md`](binary-selection-map.md) §3.5, §6.1 |
| `0x0063FE40` | `recent_selection_times` | `u16[8][8]` | teippi `offsets.h:327` |
| `0x0051267C` | `select_command_user` / `ACTIVE_PLAYER_ID` | `u8`/`s32` | teippi `offsets.h:343`; GPTP `scbwdata.h:118` |

**Roles**, cross-checked between GPTP and teippi:

1. `playersSelections[player][0..11]` (`0x006284E8`) is the **authoritative, simulation-side** selection
   — one 12-slot array per playable player. All received commands write here
   (GPTP `CMDRECV_Selection.cpp:238`, `:312`, `:393`; teippi `selection.cpp:184`, `:225`, `:276`).
   It is also *read* back for de-duplication before an add (GPTP `CMDRECV_Selection.cpp:484`).
   `PLAYABLE_PLAYER_COUNT = 8` (GPTP `structures.h:8`, BWAPI `Constants.h:7`).
2. `ClientSelectionGroup` (`0x00597208`) is the **HUD copy** for the local viewer. GPTP
   `hooks/interface/updateSelectedUnitData.cpp:24-25` shows it being filled by a literal
   `for (i < SELECTION_ARRAY_LENGTH) clientSelectionGroup->unit[i] = activePlayerSelection->unit[i]`,
   and `clientSelectionCount` (`0x0059723D`) is recomputed there.
3. `client_selection_group2` (`0x0059724C`) is the **last-sent selection**, used to diff the current
   selection against what the network already knows so the game can send `SelectionAdd`/`SelectionRemove`
   deltas instead of a full `Select` (teippi `selection.cpp:57-115`).
4. `selection_hotkeys` (`0x0057FE60`) is **8 players × 18 groups × 12 units**. Ten of the eighteen are
   the user's control groups; groups 10..17 are the engine's "recent selections" ring, recalled by
   Alt+click (teippi `selection.cpp:474` loops `group_id` 10..17 against
   `recent_selection_times[player][group_id-10]`; GPTP `CMDRECV_Selection.cpp:529` bounds the hotkey
   command with `bGroupSlot <= 18`). OpenBW models only the ten user groups
   (`actions.h:21`, `[8][10][12]`) because the recent-selection ring has no effect on simulation
   outcome **[inference]**.
5. `selection_iterator` (`0x006284B6`) + `getActivePlayerNextSelection` (`0x0049A850`, GPTP
   `scbwdata.h:348-349`) is the **iterator every order handler uses** to walk the receiving player's
   selection. See §4.4.
6. `activePlayerSelection` / `client_selection_group3` (`0x006284B8`) is the **active player's
   selection on the sim side** — GPTP declares it `const UnitsSel*` (`scbwdata.h:347`), teippi
   `array_offset<Unit*, 12>` (`offsets.h:321`). It sits directly in front of `playersSelections`
   and is the *source* the HUD copy is taken from every frame (§4.5), and the array the order
   iterator in role 5 walks. It is on the simulation side of the split, not the client side —
   which matters for candidate #3 (§7).

### 2.3 Memory adjacency — why the arrays cannot simply grow **[inference]**

> **Superseded 2026-08-07 by direct evidence.** This section reasons from arithmetic on cited
> addresses and flags its own weak points. [`binary-selection-map.md`](binary-selection-map.md) §3
> answers the same question from the binary, per array, and identifies the actual neighbour behind
> each one. Headline: **four of the five arrays have zero slack** and the fifth
> (`selection_hotkeys`) has ~1 KB behind it — not enough to widen it. The 4-byte gap this section
> could not resolve is occupied twice over. Read that section for the answer; this one is kept for
> the reasoning and the sourcing.

Arithmetic on the cited addresses only:

Note on method: `clientSelectionGroupEnd` (`0x00597238`) is **deliberately excluded** from this
argument. It is GPTP's own `0x00597208 + 12×4` written out as a constant (§2.2), not an
independently observed datum — citing it as evidence of adjacency would be citing our own
arithmetic back at ourselves. Every bullet below rests on an address some source independently
named.

- `client_selection_group` (`0x00597208`) spans `12×4 = 48` bytes → it ends at `0x00597238`. The
  nearest *independently named* datum after it is `client_selection_changed` at `0x0059723C`
  (teippi `offsets.h:323`; GPTP `hooks/interface/selection.cpp:446`). That leaves exactly **4 bytes
  — one pointer slot — of unidentified space** at `0x00597238`–`0x0059723B`. No source we read
  names anything there. So: room for at most one extra slot, and only if that gap is truly unused.
  §8 q3 asks the binary to settle it.
- `client_selection_group2` (`0x0059724C`, teippi `offsets.h:320`) starts exactly 4 bytes after
  `primary_selected` / `activePortraitUnit` (`0x00597248`) — an address teippi (`offsets.h:328`)
  and GPTP (`scbwdata.h:425`) name independently of each other. It spans `12×4 = 48` bytes →
  `0x0059724C`–`0x0059727C`. Nothing is named immediately before or after it in any source we read,
  so **the space behind it is unmeasured** rather than known-free.
- `0x006284B8 + 12×4 = 0x006284E8`, which is exactly where `playersSelections` starts. Both
  addresses are independently named by GPTP (`scbwdata.h:347, 353`) and teippi
  (`offsets.h:321, 324`), so this one is genuine two-source adjacency: the active-player copy and
  the per-player table are back-to-back with zero slack.
- `playersSelections` spans `8×12×4 = 384` bytes → `0x006284E8`–`0x00628668`.
- `selection_hotkeys` spans `8×18×12×4 = 6912` bytes → `0x0057FE60`–`0x00581960`.

Consequence: raising the cap means **relocating** all five arrays into plugin-allocated memory and
re-pointing every instruction that touches them — not editing a bound. This is exactly what
Heinermann said in 2010 (§5) and exactly the technique teippi uses for the object limits it does remove
(`src/limits.cpp:386` `RemoveLimits`, which hooks the allocate/delete entry points for orders, sprites
and bullets rather than resizing arrays).

### 2.4 Per-unit state that references the selection

`CSprite` carries a **`selectionIndex` at offset `0x0B`**, documented identically in two sources as
"0 <= selectionIndex <= 11. Index in the selection area at bottom of screen"
(BWAPI `BW/CSprite.h:17`; GPTP `SCBW/structures/CSprite.h:69`). It is a `u8`, so the *field* tolerates
values up to 255 — good news. But it is used for array surgery: GPTP
`hooks/interface/selection.cpp:627-635` computes a length from
`(arrayIndex - clicked_unit->sprite->selectionIndex) * 4` and passes it to the game's own
`SC_memcpy_0` (declared `hooks/interface/selection.cpp:9`, address `0x…08FD0` in GPTP's comment;
body at `:944`) to shift the tail of the array down when shift-clicking a unit out of the
selection. The source's own name is used here deliberately — whether that routine has
`memcpy` or `memmove` overlap semantics is unresolved from public sources and matters for a
widened array **[unverified]**. Any relocation must also keep `selectionIndex` in sync.

> **Answered 2026-08-08 from the binary by task 014 — read
> [`selection-circles.md`](selection-circles.md) instead of this paragraph.** Both flag meanings
> below are confirmed, and `selectionIndex` really is at `0x0B`. But **the flags byte is at `0x0E`
> in this binary, not at `0x06`** — its `CSprite` starts with the two list pointers, which shifts
> everything after `spriteID` by 8 relative to the published headers. And the hazard is worse than
> "keep `selectionIndex` in sync": FOUR instructions read it, all as a `memmove` offset into a
> 12-entry stack array, so **no value is safe for a unit outside the engine's 12** — a value ≥ 12
> smashes the stack, a value ≤ 11 deletes a different, genuinely selected unit. All four are gated
> on flag `0x08`, which is why task 014's plugin sets only flag `0x01` and never writes the index.
> ([`selection-circles.md` §2, §4](selection-circles.md).)

Also on the sprite: `flags & 0x08 = Selected`, `flags & 0x01 = draw selection circle`
(BWAPI `CSprite.h:20-29`; GPTP `structures/CSprite.h:14-22`), plus a
**`DashedSelectionMask = 0x6`** two-bit counter for allied ("dashed") selection circles, which teippi
annotates `// Team can have max 4 players, so max 0..3 dashed circles` (`src/sprite.h:27`). That
counter is per-sprite and per-team, not per-selection-size, so it is *not* a cap constraint —
but it is touched by the same code paths (teippi `selection.cpp:195-205`).

---

## 3. Every subsystem the cap touches

| # | Subsystem | Why 12 matters there | Change difficulty |
|---|---|---|---|
| 1 | **Selection storage** (§2.2) | Five fixed-size global arrays (`0x00597208`, `0x0059724C`, `0x006284B8`, `0x006284E8`, `0x0057FE60`), at most one spare slot behind any of them | **Hard** — relocation, not resizing |
| 2 | **Input / client-side selection** (§4.1) | Drag-box, ctrl+click, shift+click, double-click all build 12-slot stack arrays and stop at `SELECTION_ARRAY_LENGTH` | Medium — ~6 functions, all reimplemented in GPTP already |
| 3 | **Control groups + recent selections** (§4.2) | `[8][18][12]` array, save/recall/alt-click paths | Medium — 5 functions |
| 4 | **Command send path** (§4.3) | `Select`/`SelectAdd`/`SelectRemove` packets carry `u8 count` + `u16 tag[]`; sender caps at 12 | Medium — format is count-driven, so it *stretches*; the cap is in code |
| 5 | **Command receive path** (§4.3) | `CMDRECV_Select`/`ShiftSelect` reject or truncate above 12 before touching `playersSelections` | Medium |
| 6 | **Order/action dispatch** (§4.4) | Every order handler iterates the receiving player's 12-slot array via a global iterator | Low — but **not zero**: the iterator has a hardcoded `CMP BL,0xc` (`0x0049A857`). One function to fix, reached from 73 sites |
| 7 | **HUD / status screen** (§4.5) | 12 wireframe buttons in the dialog; `clientSelectionGroup[12]` copied per frame; screen real estate | **Hard** (art/layout), easy (code) |
| 8 | **Selection circles / sprite overlays** (§2.4) | Per-sprite, count-independent | Low |
| 9 | **Sound** | One "selected" sound per selection change, gated by `selection_sound_cooldown` (`0x0064087C`, teippi `offsets.h:583`); rank comparison over the selection picks the speaker (`compareUnitRank` `0x0049A350`, GPTP `selection.cpp:1239`) | Low |
| 10 | **Replay format** (§6.2) | Command stream is the replay; per-frame command block length is a **single byte** | Constraint, not code |

Detail follows.

### 4.1 Input path (local client)

All addresses from GPTP `GPTP/hooks/interface/selection.cpp`, which reimplements these functions in C
with the original address in a comment.

| Address | Function | Cap involvement |
|---|---|---|
| `0x0046F0F0` | `SortAllUnits` — builds the candidate list for drag-box **and** ctrl+click | `if (current_index_in_unit_list >= SELECTION_ARRAY_LENGTH)` at source `:202`, annotated as binary site **`0x0046F208`** |
| `0x0046F040` | overflow handler called when that list is already full | called at `:203` |
| `0x0046F290` | `combineSelectionsLists` — merges a new list into the existing selection for shift-add | caps twice, `:302` and `:360` |
| `0x0046F3A0` | resolve clicked unit | — |
| `0x0046FA00` | `applyNewSelect` | takes (list, length) |
| — | `getSelectedUnitsInBox` (drag-select) | two `static CUnit*[SELECTION_ARRAY_LENGTH]` scratch arrays, `:387-388` |
| — | `getSelectedUnitsAtPoint` (click / shift / ctrl / alt / double-click) | two `CUnit*[SELECTION_ARRAY_LENGTH]` stack arrays, `:453-454`; shift-add bound at `:594` |
| `0x0046ED80` | `unit_isUnselectable(unitId)` | which unit types can be selected at all |
| `0x0047B770` | `unit_IsStandardAndMovable` | **the multi-select gate** — the reason buildings and disabled units can only be selected alone. GPTP's comment at `:283-284` flags it as "a likely blocker for buildings and other special selections" |
| `0x00496D30` | `selectSingleUnitFromID` | Alt+click recall of the recent group containing a unit |
| `0x0049AE40` | `CreateNewUnitSelectionsFromList` | applies a list as the new client selection |
| `0x0049AEF0` | `selectMultipleUnitsFromUnitList` | ditto, multi path |
| `0x004C0860` | `CMDACT_Select` | **builds and queues the network command** |
| `0x004C07B0` | `CMDACT_HotkeyUnit` | queues the hotkey command |

OpenBW corroborates the *semantics* independently: `ui/ui.h:1749-1800` implements the same
drag / shift / ctrl / double-click matrix, and `ui.h:457` `unit_can_be_selected` mirrors
`unit_isUnselectable`. Note OpenBW's **viewer** selection (`ui.h:1661` `a_vector<unit_id> current_selection`)
is *unbounded* — because that UI never converts a selection into an order. The cap in OpenBW lives
strictly in `actions.h` (§4.3), which is the sim side. That split is a useful design hint.

### 4.2 Control groups and recent selections

teippi `src/selection.cpp` reimplements these; GPTP gives the addresses.

| Address | Function | Cap involvement |
|---|---|---|
| `0x004965D0` | save-to / add-to hotkey group | walks 12 slots per group; GPTP `CMDRECV_Selection.cpp:26-180` |
| `0x00496940` | recall hotkey group | `:186-289`; teippi `Command_LoadHotkeyGroup`, `selection.cpp:380-417` |
| `0x00496560` | pick least-recently-used "recent selection" slot | `:571` |
| — | `TrySelectRecentHotkeyGroup` | teippi `selection.cpp:470-495`, groups 10..17 |
| — | `RemoveFromHotkeyGroups` on unit death | teippi `selection.cpp:502-523`, loops `group < 0x12` and shifts the 12-slot array down |

The last one matters: **unit death compacts every hotkey group array**, so a wider array changes the
cost and the code of a very hot path.

### 4.3 The command / network path

**Vanilla 1.16.1 wire format.** For `0x09` and `0x0A` this is authoritative: BWAPI constructs those
two packets itself, byte for byte, and they are accepted by the unmodified client. `0x0B` rests on
**screp alone** — BWAPI defines only `Select` (`BWCommand<0x09>`) and `SelectAdd`
(`BWCommand<0x0A>`); there is no `SelectRemove`/`ShiftDeselect` class anywhere in that repo. screp
does confirm the id and the same count-then-tags shape.

```
Select      (0x09) : [u8 cmdId][u8 count][u16 unitTag] × count   (BWAPI + screp)
SelectAdd   (0x0A) : same                                        (BWAPI + screp)
SelectRemove(0x0B) : same                                        (screp only -> confirmed 2026-08-07)
```

**`0x0B` no longer rests on screp alone.** `CMDACT_Select` (`0x004C0860`) builds three command
buffers and writes the id byte into each: `0x09` at `0x004C0A78`, `0x0A` at `0x004C0AB2`, and
**`0x0B` at `0x004C0A9B`** (`MOV byte ptr [EBP + -0x40],0xb`). The length is computed as
`LEA EDX,[EDX + EDX*0x1 + 0x2]` = `2 + count*2`, matching BWAPI's size function exactly. The binary
emits the command screp alone documented.
([`binary-selection-map.md`](binary-selection-map.md) §6.3.)

- Command IDs: BWAPI `BW/OrderTypes.h:68` (`BWCommand<0x0A>`), `:81` (`BWCommand<0x09>`); screp
  `rep/repcmd/types.go:13-15` (`TypeIDSelect 0x09`, `TypeIDSelectAdd 0x0a`,
  `TypeIDSelectRemove 0x0b`) and `:107-109`.
- Layout: `u8 targCount; UnitTarget targets[MAX_SELECTION_COUNT];` — BWAPI `OrderTypes.h:76-77, 90-91`.
- Size function: `return 2 + targCount * 2;` — BWAPI `OrderTypes.cpp:84, 109-111`.
- `UnitTarget` is exactly 2 bytes (`static_assert(sizeof(UnitTarget) == 2)`, BWAPI `BW/UnitTarget.h:34`),
  encoding unit index plus a uniqueness bit pattern (`UnitTarget.h:16-18`).
- Sender caps at 12: `for (int i = 0; i < count && i < MAX_SELECTION_COUNT; ++i)` — BWAPI
  `OrderTypes.cpp:67, 76, 90, 99`.

**Receiver**, from GPTP `hooks/recv_commands/CMDRECV_Selection.cpp`:

| Address | Handler | Cap check |
|---|---|---|
| `0x004C2750` | `CMDRECV_Select(packetId, s8 bCount, StoredUnit* units)` | `if (bCount <= SELECTION_ARRAY_LENGTH)` at `:451` — **a command carrying more than 12 is silently dropped entirely** |
| `0x004C2560` | `CMDRECV_ShiftSelect` | `if (bCount <= SELECTION_ARRAY_LENGTH)` `:334` **and** `if (index + bCount <= SELECTION_ARRAY_LENGTH)` `:342` — an add that would overflow is rejected wholesale, not truncated |
| `0x004C2870` | `CMDRECV_Hotkey` | `bGroupSlot <= 18` `:529` |
| `0x0049AF80` | add-one-unit-to-slot helper | `selection_slot < SELECTION_ARRAY_LENGTH` `:304` |
| `0x0049A740` | clear a player's selection | — |
| `0x0049A110` | team-selection / alliance check (dashed circles) | — |

OpenBW independently reproduces both semantics: `actions.h:293`
`if (selection.size() + units.size() > 12) return false;` (shift-select rejects the whole batch) and
`actions.h:276, 299` `error("attempt to select more than 12 units")`. Two independent reversers
agreeing on the *all-or-nothing* rejection rule is a strong signal.

Note the count field is a **`u8`**, and the receive-side parameter is typed `s8` in GPTP
(`CMDRECV_Selection.cpp:327, 444`). If that signedness is real in the binary, counts above 127 would go
negative — an issue only for very large caps **[unverified; GPTP's typing may be the reverser's choice]**.

**Turn buffer**: commands accumulate in a 512-byte per-turn buffer —
`TURN_BUFFER_SIZE = 512` (BWAPI `Constants.h:20`), `TurnBuffer` at `0x00654880`,
`sgdwBytesInCmdQueue` at `0x00654AA0` (BWAPI `Offsets.h:75-76`).
A 12-unit select is 26 bytes; a 24-unit select is 50 **[inference]**. Not a binding constraint for a
modest cap raise; it *is* one at the protocol maximum (255 units → `2 + 510 = 512` bytes, the entire
buffer) **[inference]**.

**Two sizes for the same command, and why.** These 26/50-byte figures are the *network command*
size — BWAPI's `2 + targCount * 2` (`OrderTypes.cpp:84, 109-111`), i.e. `[cmdId][count][tags…]`.
The replay stream adds a **one-byte player id in front of every command** inside the frame block
(screp `repparser.go:474-475` reads `base.PlayerID` then `base.Type`), so the same 24-unit select
costs 50 bytes on the wire and **51 bytes in a replay**. §6.2 uses the 51-byte figure because the
constraint there is the replay frame block; §4.3 uses 50 because the constraint here is the
`TurnBuffer`. Both are correct in their own context.

**Precedent for changing this format**: teippi already did. Its `Select` command is
`[u8 id][u8 zero][u32 count][u32 unitId × count]` — teippi `selection.cpp:159-168`, with the length
function `count * 4 + 6` at `selection.cpp:497-500` and dispatch at `commands.cpp:311-314`. It uses
32-bit ids because it removed the 1700-unit limit, so 16-bit unit tags no longer address every unit
**[inference from teippi's stated purpose]**. It also *rejects* vanilla-shaped selects
(`if (buf[1] != 0) Warning("Bad select: %d")`, `selection.cpp:175, 216, 266`). So: a 1.16.1 plugin
redefining the selection command exists in the wild, and it is incompatible with vanilla by design.

### 4.4 Order dispatch — one function to fix

Every received order applies itself to the receiving player's selection through one iterator:

```c
*selectionIndexStart = 0;                       // 0x006284B6
while (CUnit* u = getActivePlayerNextSelection())  // 0x0049A850
    ...apply the order to u...
```

GPTP `hooks/recv_commands/train_cmd_receive.cpp:18-19, 62, 77-80`; also
`unhooked/unit_morph_inject.cpp:35-37`.

**Corrected 2026-08-07 from the binary.** This section previously read that the loop is
"bound-agnostic — it terminates on NULL, not on a count", and called that "the single most
encouraging finding in this document". **That is false on this binary.**
`getActivePlayerNextSelection` is 33 instructions and opens with a hardcoded 12:

```
0049A851   MOV BL,byte ptr [0x006284b6]     ; selection_iterator
0049A857   CMP BL,0xc                       ; 80 FB 0C
0049A85A   JC  0x0049A860                   ; iterator < 12 -> continue
0049A85C   XOR EAX,EAX ; POP EBX ; RET      ; else return NULL
```

NULL entries *are* skipped further down, but **termination is the count**. The gate was decoded
both by our Ghidra pipeline and, independently, by hand from the file's bytes.

The finding is still good news, just a smaller kind: the bound lives in **one function**, and that
function is reached from **73 sites** (72 `CALL` + one tail `JMP` at `0x0049A8B7`, confirmed two
independent ways). So the order-dispatch path costs one function to fix, not 73 — but it is not
free, and any plan that assumed it needed no change is wrong.

Source: [`binary-selection-map.md`](binary-selection-map.md) §7.1, with the site listed in
`research/data/selection-immediates.tsv` (`0x0049A857`, role `comparison`, cap-relevant) and the
reference counts in `research/data/selection-function-probe.tsv`.

### 4.5 HUD / status screen

- `updateSelectedUnitData` copies `activePlayerSelection` (`0x006284B8`, §2.2 role 6) →
  `clientSelectionGroup` (`0x00597208`) with a literal 12-iteration loop and recomputes
  `clientSelectionCount` (GPTP `hooks/interface/updateSelectedUnitData.cpp:18-56`).
  **The HUD's source is a sim-side array**, not a client-side one — which is why widening only the
  client arrays does not by itself widen the HUD (see §7 candidate #3). It also has a special case: exactly one
  unit selected → put the portrait unit in slot 0 and NULL the rest (`:49-56`).
- The status screen's small unit buttons are dialog controls in a linked list, walked 12 times:
  teippi `selection.cpp:529-561` loops `for (int i = 0; i < 12; i++)` twice (shift and ctrl paths) over
  `StatusScreen::FirstSmallButton` and its `->next` chain, reading each control's `val` as a `CUnit*`.
  So the wireframe row is **dialog-resource driven**: the buttons exist as controls, and the code walks
  as many as it expects. Whether the count lives only in code or also in the dialog `.bin` resource is
  **open** (§8, question 7).
- Physical space: at 640×480 the wireframe row holds 12 portraits. Above 12 the HUD needs either
  smaller icons, a second row, or scrolling — this is the only part of the job that is design work
  rather than reversing. Heinermann flagged exactly this in 2010 (§5).

---

## 5. Prior attempts — who tried, what happened

**Finding: no *open-source* project has raised the selection cap on 1.16.1
[searched multiple phrasings; absence not proven]** — but two closed-source Battle.net hack tools
for exactly this version are described as doing it, apparently by the fan-out route rather than by
widening the engine (entry 1 below). That reverses the flat negative this section carried in the
first draft.

Searches run for this section (2026-08-06/07), all returning no open-source counterexample:

1. `StarCraft 1.16.1 plugin increase selection limit more than 12 units`
2. `github starcraft broodwar plugin "selection limit" patch remove 12 unit cap 1.16.1 source code`
3. `"samase" OR "GPTP" starcraft plugin hooks selection more than 12 units attempt failed desync`
4. `staredit.net selecting more than 12 units topic 10153 selection limit arrays hotkeys`
5. `"selection hack" starcraft 1.16.1 select 255 units ghoztcraft`
6. `Zynastor selection hack Oblivion starcraft select more than 12 units`
7. `StarCraft Remastered 12 unit selection limit Blizzard preserve original gameplay statement`

plus local greps of all five cloned repos (§0) for `selection`, `Selection`, `MAX_SELECTION`,
`SELECTION_ARRAY_LENGTH` and `Limits::Selection`. Absence of evidence in seven searches and five
repos is not proof of absence, and closed-source tooling is by definition hard to search — treat
the negative as **unfalsified, not verified**.

**Prior art, entry by entry:**

1. **Closed-source 1.16.1 hack tools — the one real counterexample.** Two artefacts, both for this
   exact version, are publicly described as selecting and commanding far more than 12 units:
   - **Oblivion** (author Zynastor), a general-purpose 1.16.1 hack. Its feature list is described
     as: *"allows you to group and select up to 252 units or buildings of the same type and
     displays an on-screen unit counter when selecting over 12 units."*
   - **Selection Hack** (author salvinger), hosted at
     https://www.ghoztcraft.net/forums/files/file/1291-selection-hack/ — *"allows you to select up
     to 255 units at once… similar to Zynastor's selection hack in oblivion"*, with
     *"the circles that go around the units selected is limited to 12, so if you selected 50 units,
     only 12 will actually appear to be selected, but when you command them all 50 will move"*, a
     `~` key that selects all units of the same type, and an update that changed the over-12 count
     from being *"sent like a text message"* to being displayed.

   **Evidence status — [unverified].** The Ghoztcraft file page and the mirrored Oblivion feature
   lists are behind a sign-in wall or 403 (`ghoztcraft.net` returns its login page to an
   unauthenticated fetch; `tapatalk.com/groups/keopsfr/broodwar-oblivion-v4-0-6f-t255.html` returns
   403). Everything quoted above is what a web search engine returned as its summary of those
   pages; we could not read the primary pages ourselves, no source is published, and no binary was
   downloaded or examined (and none will be — these are Battle.net cheat tools, out of bounds under
   [`AGENTS.md` hard rule 3](../AGENTS.md)). Treat authorship, version and exact numbers as
   second-hand.

   **Why it matters anyway.** The reported *symptoms* are diagnostic. Circles capped at 12 while
   all 50 units obey the order, and a count rendered as text rather than as wireframes, is
   precisely what you get from a plugin-side wide selection list that fans the order out into
   ≤12-unit `Select` chunks (§7 candidate #1) — **not** from relocating the five global arrays.
   Nobody appears to have done the relocation; somebody appears to have done the fan-out, in a
   human-driven client, on this binary. That is direct precedent for our #1 and a mild warning that
   #2 remains untrodden ground. **[unverified inference from third-party descriptions]**

2. **neivv's "Object limits plugin"** (staredit.net thread http://staredit.net/topic/16823/), 1.16.1
   only, the teippi lineage. It removes the unit limit (1700), sprite limit (2500), fog-of-war and misc
   sprite limits (500), bullet limit (100), image limit (5000), order limit (2000), and AI structure
   limits. On selection, the author states verbatim:
   > "Selection limit is still 12. Sorry - it hasn't been an issue for the stuff I've been doing with this :("

   Corroborated by the source: teippi's README describes it as "removes several limits from the game",
   `src/limits.cpp:386 RemoveLimits` hooks the object allocators, and `src/limits.h:14` still reads
   `const unsigned Selection = 12;`. **The most capable open-source limit-remover for this exact
   binary did not attempt this one, by his own statement** — the quote says it was never needed for
   his work, not that he tried and failed, and not that he judged it impossible.

3. **Heinermann** (BWAPI maintainer), staredit.net thread https://staredit.net/topic/10153/#1,
   2010-04-07, the canonical community answer:
   > "You would need to create new arrays for selections and hotkeys, as well as change all their
   > references, and the hardcoded maximum value. You would also need to alter the Select, Shift Select,
   > and Shift Deselect replay/packet commands as they have their own checks as well."

   He adds that showing extra unit icons in the HUD needs further work. Our independent read of GPTP,
   teippi, BWAPI and OpenBW reproduces this list item for item (§2, §4). No one in that thread reports
   having implemented it.

4. **BWAPI** does not raise the cap — it *routes around* it. `CommandOptimizer.cpp:254-283` accumulates
   units into `groupOf12`, and every time the group fills, emits `BW::Orders::Select(groupOf12)` followed
   by the actual order. `UnitImpl.cpp:123-128 orderSelect()` does the single-unit case. This is the
   proof-of-concept for candidate #1 in §7: **thousands of bots have controlled hundreds of units at
   once on 1.16.1 by chunking selections into 12s**, on unmodified binaries, for a decade.
   Note the ecosystem distinction the task asks about: BWAPI is a *read state / issue orders* tool
   whose command path already fans out; it never changes client selection behaviour for a human.

5. **OpenBW** enforces the cap in its simulation (`actions.h:276, 293, 299`) because sim fidelity is its
   whole purpose — tsc-bw's README (cited in [`prior-art.md` §1](prior-art.md)) states that exact logic
   parity is required or replays desync. Its *viewer* has no cap (`ui/ui.h:1661`), which shows the
   client/sim split cleanly.

6. **Remastered / 1.18+ did not change it.** The preservation intent is documented: SC:R
   *"retains the gameplay of the original StarCraft, but features ultra-high-definition graphics
   (ultra HD), re-recorded audio, and Blizzard's modern online feature suite"*
   (https://en.wikipedia.org/wiki/StarCraft:_Remastered). That the **selection limit specifically**
   stayed at 12 is reported only by press and community coverage, not by any Blizzard patch note we
   located — e.g. a launch review describing SC:R as keeping *"all of the anachronistic
   restrictions and quirks of the original… from the painfully low unit selection limit to the
   comically bad pathfinding AI"*
   (https://na.alienwarearena.com/ucf/show/1750843/ — retrieved via search summary; we did not read
   the page directly). **[unverified — no primary Blizzard source found for the selection limit
   specifically; searched, see the search list above]**. A widely repeated community anecdote holds
   that a BlizzCon show-floor build of SC:R had selection unlimited; the only trail we found is the
   reddit thread https://www.reddit.com/r/starcraft/comments/ovnb9f/ , which we could not fetch —
   **[unverified]**. Either way it never shipped, and per [`prior-art.md` §6](prior-art.md) SC:R is
   the wrong target for us.

7. **EUD map-making** can read and write 1.16.1 memory including these arrays, but cannot enlarge them —
   EUDs operate on the existing address space (see [`prior-art.md` §3](prior-art.md)). Not a path.

---

## 6. Hard constraints, and the multiplayer verdict

### 6.1 Multiplayer: single-player only. Explicitly.

1. StarCraft 1.16.1 multiplayer is **lockstep-deterministic**: every client simulates every command.
   A client that accepts a 24-unit `Select` while its peers drop it (`bCount <= SELECTION_ARRAY_LENGTH`,
   GPTP `CMDRECV_Selection.cpp:451`) diverges immediately. The receiver-drop half of that sentence is
   well-evidenced; the *consequence* is only partly so. What we can cite: the command stream carries a
   dedicated `Sync` command (teippi `commands.cpp:307`, `case commands::Sync: return 7;`), and teippi's
   handler compares the local sync data against the received bytes and sets a desync flag on mismatch
   (`commands.cpp:243-252`: `if (sync_data[8] != data[5] || !bw::Command_Sync_Main(data))` →
   `if (*bw::desync_happened == 0) LogSyncData()`). What the vanilla client then *does* — drop the
   player, halt the game, or show the "players are out of sync" dialog — we did not verify from a
   source. **[unverified: the exact vanilla failure action]**. The divergence itself is certain; only
   its presentation is not.
2. Therefore: a raised cap works in multiplayer **only if every participant runs the identical
   modified client**. Against Battle.net or any vanilla peer it cannot work, and per the project rules
   ([`AGENTS.md` hard rule 3](../AGENTS.md)) we do not point a modified binary at an online service
   anyway.
3. **Verdict: build this as offline / single-player only.** The user's stated goal needs nothing more.
   This is not a limitation we are conceding — it *removes* the hardest design constraint, because we
   no longer have to keep the wire format vanilla-compatible.

### 6.2 Replay format

- The `.rep` command stream is the same command stream as the network path. screp's parser is
  **count-driven**: `count := sr.getByte(); for i := 0; i < count; i++ { UnitTag(sr.getUint16()) }`
  (screp `repparser/repparser.go:488-497`). So a 24-unit select written in the vanilla shape would
  actually **still parse correctly in screp** — the third-party tooling is more permissive than the game.
- The binding limit is elsewhere: **each frame's command block is prefixed by a single-byte length**
  (`cmdBlockSize := sr.getByte()`, screp `repparser.go:464-465`). All commands from all players in one
  frame must fit in 255 bytes. A 24-unit select costs `1 (playerID) + 1 (type) + 1 (count) + 48 = 51`
  bytes **[inference]** — see §4.3 for why this is 51 here and 50 there; four players doing that in
  the same frame overflows the block.
- SC:R's 1.21+ stream uses a different select encoding (`u16 tag` + `u16` unknown per unit, screp
  `repparser.go:739-749`) — irrelevant to us, noted only to keep the version split honest.
- **Practical consequence, split by design** — this differs per candidate and the distinction is the
  whole point:
  - **Candidate #1 (fan-out, §7) stays replay-compatible.** Every command it emits is a vanilla
    `Select` of ≤12 units followed by a vanilla order. A vanilla client replays it correctly and
    screp parses it. The only visible difference is that one human intent appears as several
    Select+order pairs. This is the one place the ranking's #1 buys something real beyond low risk.
  - **Candidates #2 and #3 (cap raise) do not.** A replay containing a >12 `Select` is dropped by
    the vanilla receiver (`bCount <= SELECTION_ARRAY_LENGTH`, GPTP `CMDRECV_Selection.cpp:451`), so
    the replay desyncs from the moment of that command; and if we adopt a teippi-style widened
    encoding it stops parsing in screp too. For those two designs replay compatibility is a
    deliberate trade, not an accident — and for a single-player tool it costs nothing.

### 6.3 UI space

640×480 (or whatever `resolution::game_width/height` the plugin sets — teippi `selection.cpp:317`
already parameterises this) gives 12 wireframe slots. This is the one genuinely *design*-shaped
constraint; everything else is engineering.

---

## 7. Ranked candidate attack points

Ranked by (user-visible value × confidence) ÷ risk, for the agreed approach — an injected C/C++ DLL
hooking 1.16.1, offline only ([`prior-art.md` §5](prior-art.md) for the injection stack).

### #1 — Command fan-out ("shadow selection"), no engine cap change

- **What to change**: keep a plugin-side selection list of arbitrary size. Hook the input functions
  (`getSelectedUnitsInBox`, `getSelectedUnitsAtPoint`, and the hotkey recall path) to record the full
  set. When the player issues an order, emit `Select(chunk of ≤12)` + the order, repeatedly, exactly as
  BWAPI `CommandOptimizer.cpp:254-283` does. Restore the visible selection afterwards.
- **Blast radius**: none inside the engine. No global is resized, no packet is redefined.
- **Risk**: **low**. Failure modes are behavioural, not memory-corrupting: several orders per intent
  (so one player action costs ⌈N/12⌉ Select+order pairs, **plus one final `Select` to restore the
  selection the player can see** — the receiver's `Select` *replaces* `playersSelections[player]`
  wholesale, so after the last chunk the visible selection is that chunk, not the player's real
  set — and one selection-sound trigger per chunk), the HUD still shows 12, and per-unit order
  semantics that depend on the *whole* selection (archon merge, unload-all) need per-chunk care.
- **Sizing — this is the real constraint on #1, so cost it honestly.** Using the byte counts from
  §4.3/§6.2: one chunk is a `Select` of 12 (`2 + 12×2 = 26` bytes) plus the order (a
  `TargetedOrder` is 11 bytes, teippi `commands.cpp:316`) = 37 bytes on the wire, 39 in a replay
  (playerID byte on each command). For **N = 100 units**: ⌈100/12⌉ = 9 chunks + 1 restore `Select`
  ≈ **9×37 + 26 = 359 bytes** in a single frame from a single player.
  - Against the **512-byte `TurnBuffer`** (BWAPI `Constants.h:20`) that fits, but leaves little room
    for anything else that frame.
  - Against the **255-byte replay frame block** (screp `repparser.go:464-465`) it does **not** fit —
    a 100-unit intent is roughly 380 replay bytes and blows the single-byte block length. The
    ceiling is about **6 chunks ≈ 72 units** per player per frame, and less when another player
    acts in the same frame.
  - **Therefore: chunk across frames.** Emit at most ~4–5 Select+order pairs per frame and spill the
    rest into the following frames. At 24 fps a 200-unit order completes in ~2 frames of game time —
    imperceptible — and it keeps both the turn buffer and the replay block inside spec. Build the
    queue-and-drain with this in mind from the start; retrofitting it later is the kind of thing that
    only shows up as a corrupt replay after a long game. **[inference from cited sizes]**
- **How to verify in game**: box-select 30 marines on a single-player map, right-click a distant point,
  confirm all 30 move. Save a replay, confirm it plays back in the vanilla client (it should — every
  emitted command is vanilla-shaped; see §6.2, which scopes replay compatibility to this candidate).
  Then repeat with ~100 units and re-check the replay, which is where the frame-block sizing above
  gets tested for real.
- **Confidence**: **high**. The mechanism is proven by a decade of BWAPI bots on this exact binary,
  and — per §5 entry 1 — the reported behaviour of two closed-source 1.16.1 hacks (all units obey,
  only 12 circles drawn) is the signature of this same approach driven by a human player
  **[unverified]**.
- **Why #1**: it delivers "command more than 12 units at once" — the user's actual goal — in a fraction
  of the work, and it is the natural harness for testing everything below.

### #2 — Full relocation: widen the data model and every function that touches it

- **What to change**: allocate replacements for `ClientSelectionGroup` (`0x00597208`),
  `client_selection_group2` (`0x0059724C`), `activePlayerSelection` (`0x006284B8`),
  `playersSelections` (`0x006284E8`) and `selection_hotkeys` (`0x0057FE60`) in plugin memory;
  reimplement the ~20 functions in §4.1–§4.5 against the new arrays; extend the `Select`/`SelectAdd`/
  `SelectRemove` encoding (or keep the shape and simply allow `count > 12`, which stays screp-parsable
  up to 255); rework the HUD row.
- **Blast radius**: the entire subsystem. This is Heinermann's prescription verbatim (§5).
- **Risk**: **high but bounded and precedented** — teippi does exactly this class of surgery for five
  other limits (`src/limits.cpp:386`). Specific hazards: `CSprite::selectionIndex` bookkeeping
  (§2.4), the hotkey-group compaction on unit death (§4.2), and any code path we fail to find that
  still reads the old addresses (EUD maps, triggers, AI).
- **How to verify**: select 24 units and issue move/attack/stop; save and recall a control group of 24;
  kill units mid-selection and confirm no corruption; alt+click recent-group recall; verify the HUD
  matches; run a long AI-vs-AI single-player game for stability.
- **Confidence**: **medium-high** that it works offline. **Certain** that it breaks vanilla MP/replay.
- **Depends on the binary analysis in §8 (task 001) landing first** — specifically §8 questions 1–4,
  the xref sweep and the adjacency confirmation. Candidate #4 (OpenBW prototype) is independent of
  it and can run in parallel.

### #3 — Split the cap: wide client selection, chunked commands

- **What to change**: relocate and widen only the *client-side* arrays (`0x00597208`, `0x0059724C`)
  plus the input path and HUD, leaving `playersSelections` and the packet format at 12; the command
  layer fans out as in #1.
- **Blast radius**: input + HUD, **plus one sim-side array whether we like it or not**. The earlier
  claim that "sim is untouched" was wrong: the HUD does not read the client arrays directly, it
  reads a *copy* made every frame from `activePlayerSelection` (`0x006284B8`) by the 12-iteration
  loop at GPTP `hooks/interface/updateSelectedUnitData.cpp:24-25` (§2.2 role 6, §4.5). `0x006284B8`
  sits immediately in front of `playersSelections` on the sim side. So a wide HUD requires either
  relocating/widening `0x006284B8` too, or hooking `updateSelectedUnitData` outright to fill the
  widened client array from the plugin's own list — otherwise the engine overwrites the first 12
  entries every frame and ignores the rest.
- **Risk**: medium, and higher than the first draft implied for the reason above. Gives a genuinely
  wide selection *display* and wide control-group storage while keeping the command/order
  invariants. But it means maintaining two notions of "the selection" across a per-frame copy that
  the engine also writes, which is where subtle bugs live.
- **How to verify**: same as #2 minus the sim checks.
- **Confidence**: **medium**. Attractive as a stepping stone between #1 and #2; the HUD work is shared
  with #2 and is a prerequisite for either.

### #4 — Prototype in OpenBW first

- **What to change**: `actions.h:20` `static_vector<unit_t*, 12>` → N, and the three checks at
  `actions.h:276, 293, 299`; optionally wire `ui/ui.h`'s already-unbounded `current_selection` to issue
  actions.
- **Blast radius**: none — it is a separate program.
- **Risk**: **near zero**, and it desyncs OpenBW from real replays by construction (expected).
- **How to verify**: run an OpenBW game, select >12, issue orders, watch for semantic surprises
  (order dispatch order, per-unit filters, archon merge, transports).
- **Confidence**: **high** that it compiles and runs; the value is *learning what breaks semantically*
  for near-zero cost, before spending effort in the binary.
- **Why it is ranked here and not lower**: it is the cheapest way to discover gameplay-level
  consequences, and it costs a day, not a week.

### #5 — Byte-patch the constant (the naive answer) — **expected to fail**

- **What it would be**: find the immediates (`12`, `0xC`, `0x30` = 12×4) in the selection functions and
  bump them.
- **Why it fails**: the arrays are fixed-size globals with other globals close behind them.
  `0x006284B8 + 0x30` lands exactly on `playersSelections` (`0x006284E8`) — two independent sources
  name both addresses, so that array has **zero** slack. `client_selection_group` (`0x00597208`)
  ends at `0x00597238` and the next independently named datum is `client_selection_changed` at
  `0x0059723C`, leaving **4 bytes — one slot — of unidentified space**, which is not a budget worth
  spending a memory-corruption bug on **[inference from §2.3]**. Raising a loop bound without moving
  storage writes selection pointers over adjacent engine state.
- **Listed because** it is the answer the task warns about, and because *proving* it wrong with an
  address map is more useful than asserting it.
- **Confidence**: ~~**high** that it corrupts memory~~ — **demonstrated 2026-08-07, not inferred.**
  Four of the five arrays have a live neighbour identified by name immediately behind them:
  `clientSelectionGroup` → a loop end-sentinel used by 44 instructions *and* a HUD/console global;
  `clientSelectionGroup2` → the hotkey double-tap timestamp; `activePlayerSelection` →
  `playersSelections` itself; `playersSelections` → a 3072-byte game-result string buffer. Only
  `selection_hotkeys` has room behind it, ~1 KB, which is 21 hotkey groups — nowhere near the 6912
  bytes doubling it would need. ([`binary-selection-map.md`](binary-selection-map.md) §3.)
- **And the constant list in this candidate is incomplete anyway**: the `×12` row stride of
  `playersSelections` is not written as an immediate at all, it is encoded in `LEA` scale factors at
  20 further sites, so a byte-patch of the visible immediates would miss them silently
  ([`binary-selection-map.md`](binary-selection-map.md) §2.2). The one place a small in-place edit
  might be safe is a pure *policy* check with no array write behind it — none has been identified.

---

## 8. What we must learn from the binary next (contract for task 001 / Ghidra)

Everything below is a question our own analysis must answer; none can be settled from public sources.
They are ordered so that answering 1–4 unblocks candidate #2.

**Status as of 2026-08-07:** task 005 answered **q1, q2, q3, q4, q5 and q8** against
`StarCraft.exe` 1.16.1 and part of q10. The answers, the evidence and the committed tables are in
[`binary-selection-map.md`](binary-selection-map.md); the per-question notes below say where.
**q6, q7 and q9 are still open**, and so is the rest of q10 (triggers, AI, sync/checksum).

1. ~~**Cross-reference sweep.**~~ **ANSWERED** — 342 instructions across 140 functions touch the
   seven globals (`research/data/selection-xrefs.tsv`), plus **20 encoded row strides** that name no
   address at all and are therefore invisible to any cross-reference sweep
   (`research/data/selection-strides.tsv`). The relocation work list is the union of the two.
   ([`binary-selection-map.md`](binary-selection-map.md) §2.)
2. ~~**Immediate-constant sweep.**~~ **ANSWERED** — 139 occurrences across 45 functions, each with
   a role; 60 are cap-relevant (`research/data/selection-immediates.tsv`). Two watched values occur
   nowhere as immediates: `0x2C` (44) and `0x1B00` (6912) — the hotkey array's size is expressed as
   the dword count `0x6C0`, never as a byte total.
   ([`binary-selection-map.md`](binary-selection-map.md) §4.)
3. ~~**Adjacency confirmation — the 4-byte gap first.**~~ **ANSWERED, per array, and the answer
   differs per array** — see [`binary-selection-map.md`](binary-selection-map.md) §3 and the
   supersession note at §2.3 above. The 4-byte gap at `0x00597238` is occupied twice over.
   Original question follows. No public source names anything at
   `0x00597238`–`0x0059723B`, the four bytes between the end of `client_selection_group` and
   `client_selection_changed` (`0x0059723C`). (Do not be misled by GPTP's `clientSelectionGroupEnd`:
   per §2.2 that symbol is a compile-time constant equal to that address, not evidence about what
   lives there.) Is that gap padding, or an unnamed datum? Same question for `0x0059727C`+ (behind
   `client_selection_group2`), `0x00628668`+ (behind `playersSelections`) and `0x00581960`+ (behind
   `selection_hotkeys`). This decides relocate-vs-extend for each array independently.
4. ~~**Fixed-size copies.**~~ **ANSWERED for both copies this question names.** The
   `updateSelectedUnitData` copy is at `0x004C38B0` (`REP MOVSD`, 12 dwords, `0x004C38C2`). The
   shift-click compaction is `0x0049A170`: a 6-way-unrolled scan bounded by 12, then an **inline
   `REP MOVSD`** — *not* a call to `SC_memcpy_0`, so hooking a memcpy would not intercept it. Its
   overlap question is settled: `dst = src − 4`, ascending, which is exactly the direction that
   makes a downward shift correct. Still open: whether any *other* `REP MOVSD` in the binary has a
   selection-derived length. ([`binary-selection-map.md`](binary-selection-map.md) §6.2, §6.5.)
5. ~~**Resolve a source disagreement.**~~ **ANSWERED 2026-08-07 — GPTP is right.** teippi typed
   `selection_hotkeys` (`0x0057FE60`) as `Unit*[8][18][12]` (`src/offsets.h:326`); GPTP typed the
   same address as a `u32` array of `StoredUnit` values. The binary stores
   `(uniqueness << 11) | unitIndex`, not pointers: `hotkeySaveOrAdd` (`0x004965D0`) masks
   `AND ECX,0x7ff` for the index, `IMUL ECX,ECX,0x150` into the unit table at `0x0059CB58`, and
   compares `CUnit + 0xA5` against `entry >> 11` to detect a stale entry. **Stale entries are
   explicitly detectable and the engine detects them** — so a relocated, widened array must
   preserve the tag encoding and that check, and cannot simply store pointers.
   ([`binary-selection-map.md`](binary-selection-map.md) §6.1.)
6. **`CMDACT_Select` (`0x004C0860`).** Exactly how does it build the packet, what caps the count on the
   send side, and what is the maximum command size the queueing routine accepts before it interacts
   with the 512-byte `TurnBuffer` (`0x00654880`) / `sgdwBytesInCmdQueue` (`0x00654AA0`)?
7. **Status-screen dialog.** How are the 12 small unit buttons created — hardcoded in code, or as
   controls in a dialog `.bin` resource? Get the control IDs and the layout source. This decides
   whether a wider HUD row is a code change, a resource change, or both.
8. ~~**`s8` vs `u8` count, and the width of `ClientSelectionCount`.**~~ **BOTH ANSWERED
   2026-08-07.**
   (a) The received count is **unsigned**; GPTP's `s8` typing (`CMDRECV_Selection.cpp:327, 444`) is
   wrong, and the difference is behavioural. `CMDRECV_Select` reads the count straight off the
   packet and gates it with `CMP byte ptr [ESI + 0x1],0xc` / **`JA`** at `0x004C275A` — unsigned
   above, not `JG`. Same in `CMDRECV_ShiftSelect` (`0x004C256D`). Counts 13–255 are all rejected
   outright. Under GPTP's `s8`, a count of 200 would sign-extend to −56, pass `bCount <= 12` and
   fall into the `bCount > 0` else-path, clearing the player's selection instead of rejecting the
   command; the real binary clears nothing. **The protocol ceiling is 255, not 127.**
   (b) `0x0059723D` is a **`u8`** — BWAPI and GPTP are right, teippi's `offset<uint32_t>` is wrong.
   All 23 accesses in the binary are byte-width (`MOV CL,byte ptr [0x0059723d]`,
   `CMP byte ptr [0x0059723d],0x1`, `INC byte ptr [0x0059723d]`, `MOV byte ptr [0x0059723d],BL`);
   not one dword access exists, so nothing overlaps `0x0059723E`–`0x00597240`.
   ([`binary-selection-map.md`](binary-selection-map.md) §5.4 and §7.2.)
9. **`unit_IsStandardAndMovable` (`0x0047B770`)** — its exact predicate, and every caller. It is the
   multi-select gate and it appears in *both* the input path and the receive path; a cap change that
   misses one caller produces "some units silently refuse to join the selection" bugs.
10. **Other readers.** Does anything outside §4 read `playersSelections` — trigger engine (give units,
    run AI script), AI code, save/load, or the sync/checksum path? Any of these would extend the
    relocation surface. Save/load is **confirmed, not suspected**: teippi `src/save.cpp:1046-1057`
    packs `Limits::Selection * Limits::ActivePlayers` unit pointers out of `bw::selection_groups`
    through `ConvertUnitPtr<true>` and writes them with `WriteCompressed`, and `:1916-1919` reads the
    same block back and converts them the other way. `save.cpp:1022` and `:1886` do the same for
    `bw::selection_hotkeys`. So the savegame format embeds both the selection and the control groups
    at their 12-wide sizes: **a widened array changes the save format**, and saves written by the mod
    will not load in vanilla (and vice versa).

    **Save/load confirmed in the binary 2026-08-07** — the teippi-sourced half of this question is
    now first-hand. `playersSelections` is written and read as a 384-byte block (`PUSH 0x180` at
    `0x004C2D1D`, `0x004D0139`, `0x004D0688`) through compressed-block helpers `0x004C3450`
    (`_fwrite`) and `0x004C3280` (`_fread`), inside routines carrying
    `Starcraft\SWAR\lang\saveload.cpp` debug strings. `ConvertUnitPtr` is real too: `0x004CEE00`
    walks all 96 dwords turning `CUnit*` into `(uniqueness << 11) | index` before the write, and
    `0x004CEDA0` walks them back afterwards, rejecting entries whose `CUnit + 0xA5` no longer
    matches. **Triggers, AI and the sync/checksum path remain unexamined.**
    ([`binary-selection-map.md`](binary-selection-map.md) §4.)

Suggested first Ghidra target order: `0x004C2750` (`CMDRECV_Select`) → `0x004C2560`
(`CMDRECV_ShiftSelect`) → `0x0049AF80` → `0x0046F0F0` (`SortAllUnits`) → `0x004C0860`
(`CMDACT_Select`). Those five contain the cap logic for receive, add, store, input and send
respectively; GPTP already provides a C reference implementation for four of them, so each is a
*verification* exercise rather than a blind decompile — which makes them ideal calibration targets for
the Ghidra pipeline itself.

---

## 9. Source index

Every file listed here is cited somewhere in the body above; nothing is listed for completeness only.

Code (commits pinned in §0):

- BWAPI — `bwapi/BWAPI/Source/BW/{Constants,Offsets,OrderTypes,UnitTarget,CSprite}.h`,
  `Source/BW/OrderTypes.cpp`, `Source/BWAPI/{CommandOptimizer,UnitImpl}.cpp`
- GPTP — `GPTP/SCBW/{structures.h,scbwdata.h,structures/CSprite.h}`,
  `GPTP/hooks/recv_commands/{CMDRECV_Selection.cpp,train_cmd_receive.cpp}`,
  `GPTP/hooks/interface/{selection.cpp,updateSelectedUnitData.cpp}`,
  `GPTP/unhooked/unit_morph_inject.cpp`
- teippi — `src/{limits.h,limits.cpp,offsets.h,selection.h,selection.cpp,commands.cpp,save.cpp,sprite.h}`
- OpenBW — `actions.h`, `ui/ui.h`
- screp — `repparser/repparser.go`, `rep/repcmd/types.go`

Community:

- https://staredit.net/topic/10153/#1 — Heinermann, 2010: what a cap change requires (quoted §5)
- http://staredit.net/topic/16823/ — neivv, object limits plugin: "Selection limit is still 12" (§5)
- https://www.ghoztcraft.net/forums/files/file/1291-selection-hack/ — salvinger, "Selection Hack"
  for 1.16.1 (**[unverified]** — page behind sign-in; content read only via search-engine summary, §5)
- https://www.tapatalk.com/groups/keopsfr/broodwar-oblivion-v4-0-6f-t255.html — Zynastor, *Oblivion*
  v4.0.6f feature list (**[unverified]** — HTTP 403; same caveat, §5)
- https://en.wikipedia.org/wiki/StarCraft:_Remastered — SC:R "retains the gameplay of the original" (§5)
- https://na.alienwarearena.com/ucf/show/1750843/ — SC:R launch coverage, "painfully low unit
  selection limit" (**[unverified]** — read via search summary, §5)
- https://www.reddit.com/r/starcraft/comments/ovnb9f/ — BlizzCon SC:R anecdote (**[unverified]**, §5)

Repository cross-links: [`research/prior-art.md`](prior-art.md) §1 (OpenBW), §2 (BWAPI/injection),
§3 (offset sources incl. teippi and GPTP), §5 (modding-tool lineage), §6 (version split),
§7 (incremental-replacement methodology).

---

## 10. Revision log

**2026-08-07 — first corrections from the binary itself (task 005).** Everything in this document
was read out of public projects; task 005 checked it against `StarCraft.exe` 1.16.1 and produced
[`binary-selection-map.md`](binary-selection-map.md). What that overturned or settled here:

1. **§4.4 was wrong, and it was this document's headline optimism.** "The loop is bound-agnostic —
   it terminates on NULL, not on a count", called "the single most encouraging finding in this
   document", is false on this binary. `getActivePlayerNextSelection` (`0x0049A850`) opens with
   `CMP BL,0xc` at `0x0049A857` and returns NULL once the iterator reaches 12. Rewritten: it is one
   function to fix, reached from **73 sites** (72 `CALL` + one tail `JMP`), not a path that needs no
   change. §3's risk table row 6 corrected to match.
2. **§8 q5 answered** — hotkey entries are `StoredUnit` u32s `(uniqueness << 11) | index`, as GPTP
   says, not teippi's `Unit*`. Stale entries are detectable and the engine detects them.
3. **§8 q8 answered, both halves** — the received count is **unsigned** (`JA`, not `JG`), so GPTP's
   `s8` typing is wrong and the protocol ceiling is 255, not 127; and `0x0059723D` is a **`u8`**, so
   teippi's `offset<uint32_t>` is wrong. §2.2 updated for the second.
4. **§8 q1, q2, q3 and q4 answered**, and q10's save/load half is now first-hand rather than
   teippi-sourced. Per-question notes added in §8; §2.3 marked superseded by the per-array adjacency
   answer, which found the 4-byte gap at `0x00597238` occupied twice over.
5. **§4.3's `0x0B` command id no longer rests on screp alone** — the binary emits it at
   `0x004C0A9B` inside `CMDACT_Select`.
6. **§7 candidate #5 upgraded from "expected to fail" to demonstrated**, by naming the neighbour
   that each in-place widening would overwrite; and its constant list noted as incomplete, since the
   `×12` row stride is encoded in addressing arithmetic rather than written as an immediate.

**2026-08-07 — round 2, after adversarial citation review.** The review re-cloned all five repos at
the pinned commits and re-checked every address, commit hash and quote line by line; none were
fabricated. What it *did* find, and what changed here:

1. **Reversed the headline negative in §5.** Two closed-source 1.16.1 hack tools appear to have
   raised the commandable selection (Oblivion, Selection Hack). The section now leads with the
   house phrasing `[searched multiple phrasings; absence not proven]`, lists the seven searches
   run, and scopes the negative to *open-source* projects.
2. **Removed a circular argument.** GPTP's `clientSelectionGroupEnd` is a compile-time constant
   equal to `0x00597208 + 12×4`, not an observed datum; §2.3's adjacency case now rests on
   `client_selection_changed` (`0x0059723C`) and states the 4-byte unidentified gap plainly.
3. **Four arrays → five.** `client_selection_group2` (`0x0059724C`) was counted in some places and
   dropped in others; it now appears in §1, §2.3, §3 and §7 consistently, with its own adjacency
   bullet.
4. **Resolved a self-contradiction on replay playback** (§6.2): candidate #1 stays replay-compatible;
   only #2/#3 break it.
5. **Costed candidate #1 against the buffer limits** (§7 #1): ⌈N/12⌉ **+1** commands, ~359 bytes for
   a 100-unit intent, over the 255-byte replay frame block → chunk across frames.
6. **Corrected candidate #3's blast radius** (§7 #3): the HUD's source array `0x006284B8` is
   sim-side, so "sim untouched" was wrong.
7. Smaller fixes: `0x006284B8` added to §2.2's roles; `SC_memcpy_0` called by its own name;
   `SelectRemove` (0x0B) attributed to screp alone; §5 neivv wording softened to "did not attempt
   it, by his own statement"; §5 Remastered claim given a source and an `[unverified]` tag;
   §6.1 sync mechanism cited to teippi `commands.cpp:243-252, :307` with the vanilla failure action
   tagged `[unverified]`; §8 q10 grounded in `save.cpp:1046-1057` / `:1916-1919` instead of a grep
   count; the `0x0059723D` width disagreement recorded (§2.2, §8 q8b); the 50-vs-51-byte discrepancy
   explained (§4.3); §7 #2's wrong cross-reference fixed; §9 pruned to files actually cited.
