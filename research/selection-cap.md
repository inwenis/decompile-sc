# The 12-unit selection cap in StarCraft 1.16.1 — recon

Survey date: 2026-08-06. Target: **StarCraft: Brood War 1.16.1** (classic). Scope: public sources only.
No binary was opened, no game file was touched, no address was derived by us — every offset below is
quoted from a named public source. Anything not verifiable is marked **[unverified]**; anything we
computed from cited numbers is marked **[inference]**.

Companion document: [`prior-art.md`](prior-art.md) — read it for the ecosystem map (OpenBW, BWAPI,
GPTP, samase, teippi, file formats, version split). This document does not repeat it; it cites into it.

## 0. Sources and how they were read

Four public code bases were cloned and grepped locally; citations are `file:line` against these commits.

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

1. **It is not one constant.** The number 12 is baked into at least **six** distinct places:
   four separate global arrays, the wire format of three network commands, the status-screen
   dialog, and roughly two dozen functions that walk those arrays with a hardcoded bound.
   The community's own answer (Heinermann, 2010, quoted in §5) says the same thing.
2. **Nobody appears to have done it on 1.16.1.** The most capable limit-removal plugin for this
   exact binary (neivv's, the teippi lineage) removes the unit/sprite/bullet/image/order limits and
   explicitly leaves selection at 12. See §5.
3. **A raised cap cannot work against vanilla multiplayer** — but that is not a real cost here.
   Everyone in a game must run the identical binary+plugin. See §6. The user only needs offline
   single-player, so this is a non-issue, and it removes the hardest constraint from the design.
4. **There is a low-risk path that delivers the user-visible feature without touching the cap at all**
   (fan out one player intent into several 12-unit `Select`+order pairs — exactly what every BWAPI bot
   already does). It is ranked #1 in §7 as the first milestone; the true cap raise is #2.
5. **The naive "patch 12 → 24" byte edit will corrupt memory**, because the arrays are fixed-size
   globals with other globals immediately behind them. See §7, candidate 5, and §3.

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
| `0x00597238` | `clientSelectionGroupEnd` | end pointer of the above | GPTP `SCBW/scbwdata.h:75` |
| `0x0059723C` | `client_selection_changed` (a.k.a. `bCanUpdateSelectedUnitData`) | `u8` | teippi `src/offsets.h:323`; GPTP `hooks/interface/selection.cpp:446` |
| `0x0059723D` | `ClientSelectionCount` | `u8` | BWAPI `BW/Offsets.h:146`; GPTP `scbwdata.h:76`; teippi `offsets.h:322` |
| `0x00597248` | `primary_selected` | `Unit*` | teippi `src/offsets.h:328` |
| `0x0059724C` | `client_selection_group2` | `Unit*[12]` | teippi `src/offsets.h:320` |
| `0x006284B6` | `selection_iterator` / `selectionIndexStart` | `u8` | teippi `offsets.h:325`; GPTP `scbwdata.h:346` |
| `0x006284B8` | `activePlayerSelection` / `client_selection_group3` | `CUnit*[12]` | GPTP `scbwdata.h:347`; teippi `offsets.h:321` |
| `0x006284E8` | `playersSelections` / `selection_groups` | `CUnit*[8][12]` | GPTP `scbwdata.h:352-353`; teippi `offsets.h:324` |
| `0x0057FE60` | `selection_hotkeys` | `[8][18][12]`, 4 bytes/entry | teippi `offsets.h:326`; GPTP `CMDRECV_Selection.cpp:28` + index math at `:38` |
| `0x0063FE40` | `recent_selection_times` | `u16[8][8]` | teippi `offsets.h:327` |
| `0x0051267C` | `select_command_user` / `ACTIVE_PLAYER_ID` | `u8`/`s32` | teippi `offsets.h:343`; GPTP `scbwdata.h:118` |

**Roles**, cross-checked between GPTP and teippi:

1. `playersSelections[player][0..11]` (`0x006284E8`) is the **authoritative, simulation-side** selection
   — one 12-slot array per playable player. All received commands write here
   (GPTP `CMDRECV_Selection.cpp:312`, `:393`, `:484`; teippi `selection.cpp:184`, `:225`, `:276`).
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

### 2.3 Memory adjacency — why the arrays cannot simply grow **[inference]**

Arithmetic on the cited addresses only:

- `0x00597208 + 12×4 = 0x00597238`, which is exactly the address GPTP names `clientSelectionGroupEnd`
  (`scbwdata.h:75`). The next named global is at `0x0059723C`, four bytes later. There is no room to
  widen this array in place.
- `0x006284B8 + 12×4 = 0x006284E8`, which is exactly where `playersSelections` starts. The
  active-player copy and the per-player table are back-to-back.
- `playersSelections` spans `8×12×4 = 384` bytes → `0x006284E8`–`0x00628668`.
- `selection_hotkeys` spans `8×18×12×4 = 6912` bytes → `0x0057FE60`–`0x00581960`.

Consequence: raising the cap means **relocating** all four arrays into plugin-allocated memory and
re-pointing every instruction that touches them — not editing a bound. This is exactly what
Heinermann said in 2010 (§5) and exactly the technique teippi uses for the object limits it does remove
(`src/limits.cpp:386` `RemoveLimits`, which hooks the allocate/delete entry points for orders, sprites
and bullets rather than resizing arrays).

### 2.4 Per-unit state that references the selection

`CSprite` carries a **`selectionIndex` at offset `0x0B`**, documented identically in two sources as
"0 <= selectionIndex <= 11. Index in the selection area at bottom of screen"
(BWAPI `BW/CSprite.h:17`; GPTP `SCBW/structures/CSprite.h:69`). It is a `u8`, so the *field* tolerates
values up to 255 — good news. But it is used for array surgery: GPTP
`hooks/interface/selection.cpp:627-635` computes a memmove length from
`(arrayIndex - clicked_unit->sprite->selectionIndex) * 4` when shift-clicking a unit out of the
selection. Any relocation must keep this field in sync.

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
| 1 | **Selection storage** (§2.2) | Four fixed-size global arrays, packed against neighbours | **Hard** — relocation, not resizing |
| 2 | **Input / client-side selection** (§4.1) | Drag-box, ctrl+click, shift+click, double-click all build 12-slot stack arrays and stop at `SELECTION_ARRAY_LENGTH` | Medium — ~6 functions, all reimplemented in GPTP already |
| 3 | **Control groups + recent selections** (§4.2) | `[8][18][12]` array, save/recall/alt-click paths | Medium — 5 functions |
| 4 | **Command send path** (§4.3) | `Select`/`SelectAdd`/`SelectRemove` packets carry `u8 count` + `u16 tag[]`; sender caps at 12 | Medium — format is count-driven, so it *stretches*; the cap is in code |
| 5 | **Command receive path** (§4.3) | `CMDRECV_Select`/`ShiftSelect` reject or truncate above 12 before touching `playersSelections` | Medium |
| 6 | **Order/action dispatch** (§4.4) | Every order handler iterates the receiving player's 12-slot array via a global iterator | Low if storage is fixed — the loop is bound-agnostic |
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

**Vanilla 1.16.1 wire format** (BWAPI constructs these packets itself, so this is authoritative for the
real client):

```
Select      (0x09) : [u8 cmdId][u8 count][u16 unitTag] × count
SelectAdd   (0x0A) : same
SelectRemove(0x0B) : same
```

- Command IDs: BWAPI `BW/OrderTypes.h:68` (`BWCommand<0x0A>`), `:81` (`BWCommand<0x09>`); screp
  `rep/repcmd/types.go:13-15`.
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

**Precedent for changing this format**: teippi already did. Its `Select` command is
`[u8 id][u8 zero][u32 count][u32 unitId × count]` — teippi `selection.cpp:159-168`, with the length
function `count * 4 + 6` at `selection.cpp:497-500` and dispatch at `commands.cpp:311-314`. It uses
32-bit ids because it removed the 1700-unit limit, so 16-bit unit tags no longer address every unit
**[inference from teippi's stated purpose]**. It also *rejects* vanilla-shaped selects
(`if (buf[1] != 0) Warning("Bad select: %d")`, `selection.cpp:175, 216, 266`). So: a 1.16.1 plugin
redefining the selection command exists in the wild, and it is incompatible with vanilla by design.

### 4.4 Order dispatch — the good news

Every received order applies itself to the receiving player's selection through one iterator:

```c
*selectionIndexStart = 0;                       // 0x006284B6
while (CUnit* u = getActivePlayerNextSelection())  // 0x0049A850
    ...apply the order to u...
```

GPTP `hooks/recv_commands/train_cmd_receive.cpp:18-19, 62, 77-80`; also
`unhooked/unit_morph_inject.cpp:35-37`. The loop is **bound-agnostic** — it terminates on NULL, not on
a count. If the storage is relocated and `getActivePlayerNextSelection` is re-pointed, most of the order
path needs no change at all. This is the single most encouraging finding in this document.

### 4.5 HUD / status screen

- `updateSelectedUnitData` copies `activePlayerSelection` → `clientSelectionGroup` with a literal
  12-iteration loop and recomputes `clientSelectionCount`
  (GPTP `hooks/interface/updateSelectedUnitData.cpp:18-56`). It also has a special case: exactly one
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

**Finding: no public project has raised the selection cap on 1.16.1.** Stated plainly because the task
asks for it: an explicit negative is the result here.

1. **neivv's "Object limits plugin"** (staredit.net thread http://staredit.net/topic/16823/), 1.16.1
   only, the teippi lineage. It removes the unit limit (1700), sprite limit (2500), fog-of-war and misc
   sprite limits (500), bullet limit (100), image limit (5000), order limit (2000), and AI structure
   limits. On selection, the author states verbatim:
   > "Selection limit is still 12. Sorry - it hasn't been an issue for the stuff I've been doing with this :("

   Corroborated by the source: teippi's README describes it as "removes several limits from the game",
   `src/limits.cpp:386 RemoveLimits` hooks the object allocators, and `src/limits.h:14` still reads
   `const unsigned Selection = 12;`. **The most capable limit-remover for this exact binary deliberately
   left this one alone.**

2. **Heinermann** (BWAPI maintainer), staredit.net thread https://staredit.net/topic/10153/#1,
   2010-04-07, the canonical community answer:
   > "You would need to create new arrays for selections and hotkeys, as well as change all their
   > references, and the hardcoded maximum value. You would also need to alter the Select, Shift Select,
   > and Shift Deselect replay/packet commands as they have their own checks as well."

   He adds that showing extra unit icons in the HUD needs further work. Our independent read of GPTP,
   teippi, BWAPI and OpenBW reproduces this list item for item (§2, §4). No one in that thread reports
   having implemented it.

3. **BWAPI** does not raise the cap — it *routes around* it. `CommandOptimizer.cpp:254-283` accumulates
   units into `groupOf12`, and every time the group fills, emits `BW::Orders::Select(groupOf12)` followed
   by the actual order. `UnitImpl.cpp:123-128 orderSelect()` does the single-unit case. This is the
   proof-of-concept for candidate #1 in §7: **thousands of bots have controlled hundreds of units at
   once on 1.16.1 by chunking selections into 12s**, on unmodified binaries, for a decade.
   Note the ecosystem distinction the task asks about: BWAPI is a *read state / issue orders* tool
   whose command path already fans out; it never changes client selection behaviour for a human.

4. **OpenBW** enforces the cap in its simulation (`actions.h:276, 293, 299`) because sim fidelity is its
   whole purpose — tsc-bw's README (cited in [`prior-art.md` §1](prior-art.md)) states that exact logic
   parity is required or replays desync. Its *viewer* has no cap (`ui/ui.h:1661`), which shows the
   client/sim split cleanly.

5. **Remastered / 1.18+** did not change it. Blizzard's stated remaster goal was gameplay preservation;
   the group-selection limit stayed at 12. A widely repeated community anecdote holds that a BlizzCon
   show-floor build of SC:R had selection unlimited; the only trail we found is the reddit thread
   https://www.reddit.com/r/starcraft/comments/ovnb9f/ , which we could not fetch — **[unverified]**.
   Either way it never shipped, and per [`prior-art.md` §6](prior-art.md) SC:R is the wrong target for us.

6. **EUD map-making** can read and write 1.16.1 memory including these arrays, but cannot enlarge them —
   EUDs operate on the existing address space (see [`prior-art.md` §3](prior-art.md)). Not a path.

---

## 6. Hard constraints, and the multiplayer verdict

### 6.1 Multiplayer: single-player only. Explicitly.

1. StarCraft 1.16.1 multiplayer is **lockstep-deterministic**: every client simulates every command.
   A client that accepts a 24-unit `Select` while its peers drop it (`bCount <= SELECTION_ARRAY_LENGTH`,
   GPTP `CMDRECV_Selection.cpp:451`) diverges immediately, and the game's sync check kills it.
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
  bytes **[inference]**; four players doing that in the same frame overflows the block.
- SC:R's 1.21+ stream uses a different select encoding (`u16 tag` + `u16` unknown per unit, screp
  `repparser.go:739-749`) — irrelevant to us, noted only to keep the version split honest.
- Practical consequence: **our replays will not play back in a vanilla client** regardless (the vanilla
  receiver drops the oversized command), and if we adopt a teippi-style widened encoding they will not
  parse in screp either. Replay compatibility is a deliberate trade, not an accident. For a
  single-player tool it costs nothing.

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
  (so one player action costs N/12 commands and N/12 selection-sound triggers), the HUD still shows 12,
  and per-unit order semantics that depend on the *whole* selection (archon merge, unload-all) need
  per-chunk care.
- **How to verify in game**: box-select 30 marines on a single-player map, right-click a distant point,
  confirm all 30 move. Save a replay, confirm it plays back in the vanilla client (it should — every
  emitted command is vanilla-shaped).
- **Confidence**: **high**. The mechanism is proven by a decade of BWAPI bots on this exact binary.
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
- Depends on #4 (binary analysis) landing first.

### #3 — Split the cap: wide client selection, chunked commands

- **What to change**: relocate and widen only the *client-side* arrays (`0x00597208`, `0x0059724C`)
  plus the input path and HUD, leaving `playersSelections` and the packet format at 12; the command
  layer fans out as in #1.
- **Blast radius**: input + HUD only. Sim untouched.
- **Risk**: medium. Gives a genuinely wide selection *display* and wide control-group storage while
  keeping every simulation invariant. But it means maintaining two notions of "the selection", which
  is where subtle bugs live.
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
- **Why it fails**: the arrays are fixed-size globals with other globals immediately behind them —
  `0x00597208 + 0x30` is exactly `clientSelectionGroupEnd` (`0x00597238`), with
  `client_selection_changed` four bytes later at `0x0059723C`; `0x006284B8 + 0x30` is exactly
  `playersSelections` (`0x006284E8`) **[inference from §2.3]**. Raising a loop bound without moving
  storage writes selection pointers over adjacent engine state.
- **Listed because** it is the answer the task warns about, and because *proving* it wrong with an
  address map is more useful than asserting it.
- **Confidence**: **high** that it corrupts memory. The one place a small in-place edit might be safe
  is a pure *policy* check with no array write behind it — none has been identified.

---

## 8. What we must learn from the binary next (contract for task 001 / Ghidra)

Everything below is a question our own analysis must answer; none can be settled from public sources.
They are ordered so that answering 1–4 unblocks candidate #2.

1. **Cross-reference sweep.** For each of `0x00597208`, `0x0059724C`, `0x006284B8`, `0x006284E8`,
   `0x0057FE60`, `0x006284B6`, `0x0059723D`: list *every* instruction in `StarCraft.exe` that
   references it. The relocation work is exactly the size of this list. Deliver it as a committed
   symbol/xref table.
2. **Immediate-constant sweep.** In the functions named in §4.1–§4.5, list every immediate `0x0C`,
   `0x0B`, `0x30` (12×4), `0x2C`, `0x12` (18) and `0x1B00` (hotkey array size) with its instruction
   address and role (loop bound / index scale / array size / comparison).
3. **Adjacency confirmation.** Confirm what actually occupies `0x00597238`–`0x0059724C`,
   `0x00628668`+, and `0x00581960`+. Is there any slack, or are these arrays hard against neighbours?
   This decides relocate-vs-extend for each array independently.
4. **Fixed-size copies.** Find every `memcpy`/`rep movsd` whose length is derived from the selection
   size — starting with the one behind GPTP's `updateSelectedUnitData` (the 12-iteration copy at
   `hooks/interface/updateSelectedUnitData.cpp:24-25`) and the shift-click compaction that uses
   `sprite->selectionIndex` (`hooks/interface/selection.cpp:627-635`).
5. **Resolve a source disagreement.** teippi types `selection_hotkeys` (`0x0057FE60`) as
   `Unit*[8][18][12]` (`src/offsets.h:326`); GPTP types the same address as a `u32` array of
   `StoredUnit` values (index + uniqueness) and reads it with `(u16)` casts
   (`CMDRECV_Selection.cpp:28, 215`). Both agree on 4 bytes per entry. Which is it? This changes how
   the relocated array must be written and whether stale entries are detectable.
6. **`CMDACT_Select` (`0x004C0860`).** Exactly how does it build the packet, what caps the count on the
   send side, and what is the maximum command size the queueing routine accepts before it interacts
   with the 512-byte `TurnBuffer` (`0x00654880`) / `sgdwBytesInCmdQueue` (`0x00654AA0`)?
7. **Status-screen dialog.** How are the 12 small unit buttons created — hardcoded in code, or as
   controls in a dialog `.bin` resource? Get the control IDs and the layout source. This decides
   whether a wider HUD row is a code change, a resource change, or both.
8. **`s8` vs `u8` count.** Is the received count sign-extended (GPTP types the parameter `s8`,
   `CMDRECV_Selection.cpp:327, 444`)? Determines the true protocol ceiling: 127 or 255.
9. **`unit_IsStandardAndMovable` (`0x0047B770`)** — its exact predicate, and every caller. It is the
   multi-select gate and it appears in *both* the input path and the receive path; a cap change that
   misses one caller produces "some units silently refuse to join the selection" bugs.
10. **Other readers.** Does anything outside §4 read `playersSelections` — trigger engine (give units,
    run AI script), AI code, save/load (`teippi/src/save.cpp` has 19 selection hits, suggesting the
    selection is serialised into saves), or the sync/checksum path? Any of these would extend the
    relocation surface.

Suggested first Ghidra target order: `0x004C2750` (`CMDRECV_Select`) → `0x004C2560`
(`CMDRECV_ShiftSelect`) → `0x0049AF80` → `0x0046F0F0` (`SortAllUnits`) → `0x004C0860`
(`CMDACT_Select`). Those five contain the cap logic for receive, add, store, input and send
respectively; GPTP already provides a C reference implementation for four of them, so each is a
*verification* exercise rather than a blind decompile — which makes them ideal calibration targets for
the Ghidra pipeline itself.

---

## 9. Source index

Code (commits pinned in §0): BWAPI `bwapi/BWAPI/Source/BW/{Constants,Offsets,OrderTypes,UnitTarget,CSprite}.h`,
`Source/BWAPI/{CommandOptimizer,UnitImpl,GameInternals}.cpp`; GPTP `GPTP/SCBW/{structures.h,scbwdata.h,structures/CSprite.h}`,
`GPTP/hooks/recv_commands/CMDRECV_Selection.cpp`, `GPTP/hooks/interface/{selection.cpp,updateSelectedUnitData.cpp}`,
`GPTP/hooks/recv_commands/train_cmd_receive.cpp`; teippi `src/{limits.h,limits.cpp,offsets.h,selection.h,selection.cpp,commands.cpp,sprite.h,constants/image.h}`;
OpenBW `actions.h`, `game_types.h`, `ui/ui.h`; screp `repparser/repparser.go`, `rep/repcmd/types.go`.

Community: https://staredit.net/topic/10153/#1 (Heinermann, 2010 — what a cap change requires),
http://staredit.net/topic/16823/ (neivv — object limits plugin, "Selection limit is still 12"),
https://www.reddit.com/r/starcraft/comments/ovnb9f/ (**[unverified]**, BlizzCon SC:R anecdote).

Repository cross-links: [`research/prior-art.md`](prior-art.md) §1 (OpenBW), §2 (BWAPI/injection),
§3 (offset sources incl. teippi and GPTP), §5 (modding-tool lineage), §6 (version split),
§7 (incremental-replacement methodology).
