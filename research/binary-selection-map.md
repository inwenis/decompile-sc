# The selection subsystem in StarCraft.exe 1.16.1 — binary map

Analysis date: 2026-08-07. Target: `StarCraft.exe`, StarCraft: Brood War 1.16.1 (classic).
This is the **first document in this repository derived from the binary itself** rather than from
public prior art.

Companion: [`selection-cap.md`](selection-cap.md) — the public-sources recon whose §8 is this
document's contract. That file is on an unmerged branch at the time of writing; link by path.
Read it first for the data model and the candidate attack points. This document does not repeat
its reasoning; it checks it.

Everything below was produced by static analysis of a disposable working copy. The game was not
launched, no binary was modified, and the user's playable install was never opened.

---

## 0. Provenance — what was analyzed, with what

| | |
|---|---|
| Binary | `C:\sc-work\1161-base\StarCraft.exe` (the project's disposable working copy) |
| Size | 1,220,608 bytes |
| SHA-256 | `AD6B58B27B8948845CCFA69BCFCC1B10D6AA7A27A371EE3E61453925288C6A46` |
| Hash verified | **Yes**, twice — `Get-FileHash` before the run, and independently by Ghidra, which reports `executableSHA256 = ad6b58b2…88c6a46` for the imported program. The analyzed image and the expected image are the same bytes. |
| Pristine install | `C:\sc-install\Starcraft` — **never opened**. Not read, not written. |
| Tool | Ghidra 12.1.2 (`ghidra_12.1.2_PUBLIC_20260605.zip`, SHA-256 `b62e81a0…272cf99d`), headless |
| JDK | 24.0.1 |

Ghidra's own report for the import, taken from the run log rather than assumed
(`work/scratch/ghidra-sweep/program-info.txt`, gitignored):

| Property | Value |
|---|---|
| `Using Language/Compiler` | `x86:LE:32:default:windows` (auto-detected; no `-processor` override was needed) |
| Executable format | Portable Executable (PE) |
| Image base | `0x00400000` |
| Entry point | `0x00404C21` |
| Functions found by auto-analysis | 5008 (later 5082 — see §1.2) |
| Defined data / symbols | 17,810 / 23,635 |
| PDB | none, as expected |

**PE section map** (parsed from the file's own section headers, not from Ghidra):

| Section | Virtual start | Virtual size | Raw size | File-backed up to |
|---|---|---|---|---|
| `.text` | `0x00401000` | `0x0FCF85` | `0x0FD000` | `0x004FE000` |
| `.rdata` | `0x004FE000` | `0x00D52C` | `0x00E000` | `0x0050C000` |
| `.data` | `0x0050C000` | `0x1D1694` | `0x010000` | **`0x0051C000`** |
| `.rsrc` | `0x006DE000` | `0x00DC28` | `0x00E000` | `0x006EC000` |

That last row matters for §3. `.data` is 1,906,324 bytes of virtual space backed by only 65,536
bytes of file. **Every selection global is above `0x0051C000` and therefore lives in the
zero-initialized BSS tail.** So a byte at any of these addresses reads `00` in the file image no
matter what it is, and "the bytes are zero" is worth nothing as evidence of unused space. Only
*references* can distinguish an occupied global from a hole. Every adjacency claim in §3 rests on
references for exactly this reason.

---

## 1. Method, and one honest limit

### 1.1 Two passes, because neither is complete alone

The cross-reference sweep runs two independent passes over each address range:

1. **Ghidra reference pass.** Every `Reference` the analyzer recorded into the range, sweeping
   *every byte* of each array rather than only its base — an instruction touching
   `playersSelections[3][7]` references `0x00628634`, and a base-only sweep would miss nearly all
   of the relocation work.
2. **Raw dword pass.** A byte scan of every initialized block for a little-endian dword whose
   *value* lands in the range, at every offset including unaligned ones, then classified
   `COVERED` (the containing code unit already produced a pass-1 reference) or `UNCOVERED`.

Pass 2 is not belt-and-braces. It found a real hole in pass 1:

```
004C26B6   MOV dword ptr [EDX*0x4 + 0x6284e8],ESI     ; writes playersSelections[EDX]
```

Ghidra recorded **no reference at all** for that instruction. It is a scaled-index absolute write
— the single most important instruction form for an array relocation — inside `CMDRECV_ShiftSelect`.
A table built from Ghidra's reference database alone would have omitted it and still looked
complete. It is row `discovery=raw-dword-only` in the committed table.

### 1.2 Code auto-analysis missed

Pass 2 also turned up ~20 sites in `.text` that Ghidra had left as undefined bytes — reachable
only indirectly, so the function-start heuristics never got to them. They are real code:

```
004282E0   B9 08 72 59 00     MOV ECX,0x597208          ; clientSelectionGroup
0049A328   BF B8 84 62 00     MOV EDI,0x6284B8          ; activePlayerSelection
004965A8   BF 60 FE 57 00     MOV EDI,0x57FE60          ; selection_hotkeys
```

Each is preceded by `0xCC` (int3) alignment filler, i.e. sits at a function boundary. Disassembling
from those seeds and re-running auto-analysis took the function count from **5008 to 5082** and the
`clientSelectionGroup` instruction count from 85 to 119. The sweep numbers below are the post-recovery
ones.

### 1.3 The residual gap, stated plainly

Both passes find a reference only when the array's address is **materialized as a constant** —
either as an instruction operand or as an encoded absolute address. Code that receives the array
base as a function parameter, or reads it from another global, is invisible to both. Nothing in
what was read suggests that pattern is used here (every access seen so far is absolute or
`base+index*4` off an absolute), but it cannot be excluded by these methods, and no claim below
depends on excluding it. Where a count is quoted it is a count of *statically resolvable*
references, and that is the number the relocation work is bounded by from below.

---

## 2. §8 Q1 — cross-reference sweep

Committed table: [`data/selection-xrefs.tsv`](data/selection-xrefs.tsv) — one row per
(global, instruction), with the instruction address, the containing function's entry point, the
reference type, the array element indices that instruction touches, the disassembled instruction,
and which pass found it.

| Global | Claimed shape | Instructions | Distinct functions | Element offsets referenced |
|---|---|---|---|---|
| `clientSelectionGroup` `0x00597208` | `CUnit*[12]` | **119** | 52 | 0,4,8,…,44 — all 12, none beyond |
| `playersSelections` `0x006284E8` | `CUnit*[8][12]` | **49** | 20 | 0…36, 48, 96, 288, 336, 340 |
| `selectionHotkeys` `0x0057FE60` | `[8][18][12]`×4B | **41** | 7 | 0…44, 868 |
| `selectionIterator` `0x006284B6` | `u8` | **41** | 39 | 0 |
| `activePlayerSelection` `0x006284B8` | `CUnit*[12]` | **36** | 14 | 0, 4 |
| `clientSelectionGroup2` `0x0059724C` | `CUnit*[12]` | **34** | 8 | 0,4,5,8,…,44 |
| `clientSelectionCount` `0x0059723D` | `u8` | **23** | 21 | 0 |

**342 distinct instructions across 140 distinct functions.** That is the floor on the relocation
work for candidate #2 in [`selection-cap.md`](selection-cap.md) §7.

Reading the "element offsets" column: an array whose every element appears (`clientSelectionGroup`,
`clientSelectionGroup2`) is addressed *slot by slot* with absolute addresses — 12 separate patch
sites per array. An array showing only offsets 0 and 4 (`activePlayerSelection`) is walked by
computed index or `REP STOSD` from its base — one patch site, many bound constants. The two need
different relocation strategies and the table is what tells them apart.

### Gaps, stated explicitly

1. **One instruction is pass-2 only** — `0x004C26B6`, above. It is in the table.
2. **Two rows are not instructions.** `0x00500A9E` and `0x00500AC2` in `.rdata` are defined pointer
   data whose value (`0x00580002`) falls inside the 6912-byte `selectionHotkeys` span. They sit in
   a `00 56 00 01 00 57 00 02 …` virtual-key table — byte coincidence, not reference. Marked
   `discovery=data-pointer-not-instruction` and excluded from the counts above.
3. **16 further raw-dword hits were dropped** as coincidences: 9 inside `.rsrc` icon/dialog bitmaps
   and 7 inside `.rdata`/`.data` string and key tables. The drop is counted by the build script
   rather than silent.
4. **`selectionHotkeys` element offset 868** is real: `ADD EDI,0x5801c4` at `0x00496D4F` inside
   `selectSingleUnitFromID`, i.e. `&hotkeys[1][0][1]` — a mid-array pointer used as a walk base.
   Relocation must catch mid-array constants like this one, not just base addresses.
5. **The end-pointer constant is not in this table** and must not be forgotten — see §3.1. Adding it
   raises the true `clientSelectionGroup` site count from 119 to **163**.
6. Residual method gap: §1.3.

---

## 3. §8 Q3 — adjacency, answered per array

The recon document's §2.3 flagged its own argument here as partly circular and asked the binary to
settle it. It does, and **the answer is different for every array** — which is exactly why the
question was worth asking.

Supporting table: [`data/selection-neighbours.tsv`](data/selection-neighbours.tsv).

### 3.1 `clientSelectionGroup` (`0x00597208`) — no slack, and `0x00597238` is doubly occupied

`selection-cap.md` §2.3 deliberately excluded GPTP's `clientSelectionGroupEnd` (`0x00597238`) as
self-referential arithmetic, leaving "exactly 4 bytes — one pointer slot — of unidentified space"
and asking whether it is free. It is not, in **two** independent ways.

1. **It is a live end-pointer sentinel.** 44 instructions in the binary compare a register against
   the literal `0x597238`:

   ```
   004C38FA   CMP EBX,0x597238        ; inside updateSelectedUnitData, walking clientSelectionGroup
   ```

   These are the loop bounds of the walks over `clientSelectionGroup`. GPTP's constant is not an
   artefact of GPTP; the compiler baked the same one-past-the-end address into 44 sites. Every one
   of them is a relocation site.

2. **It is also a real 4-byte global, read and written as data.** Two more instructions treat it
   as storage, not as a bound: `MOV EAX,[0x00597238]` at `0x004C3880` and `MOV [0x00597238],EAX`
   at `0x004C3A09`. The writer is the HUD/console initialiser — it loads `console.pcx`, fills
   `0x00597240`/`0x00597242`/`0x00597244`, and ends with `DAT_00597238 = <handle-returning call>`.
   The binary carries the original Blizzard source paths for this module as debug strings
   (`Starcraft\SWAR\lang\status.cpp`, `statwire.cpp`, `statres.cpp`, `minimap.cpp`), which
   identifies it as status-screen/console code.

   It is *not* a 13th selection slot: the teardown routine at `0x004C3780` clears
   `clientSelectionGroup` with a **12**-iteration loop that stops before `0x00597238`, and no
   instruction addresses `0x00597238` as an element of the array.

**The window is completely packed.** Probing `0x00597200`–`0x0059729F` byte by byte, *every
4-byte-aligned slot has at least one reference* — before the array, inside it, and after it:

| Address | Refs | What |
|---|---|---|
| `0x00597200`, `0x00597204` | 2, 3 | globals in front of the array |
| `0x00597208`–`0x00597234` | 105 … 4 | the 12 slots |
| `0x00597238` | **46** | end sentinel **and** HUD/console global (above) |
| `0x0059723C` | 11 | `client_selection_changed` |
| `0x0059723D` | 23 | `clientSelectionCount` |
| `0x00597240`, `0x00597242`, `0x00597244` | 4, 1, 4 | console globals written beside `0x00597238` |
| `0x00597248` | **133** | `primary_selected` / `activePortraitUnit` |
| `0x0059724C`–`0x00597278` | 18 … 1 | `clientSelectionGroup2`'s 12 slots |
| `0x0059727C` | 2 | see §3.2 |
| `0x00597280`, `…84`, `…88`, `…8C` | 17, 6, 5, 7 | further globals |

**Verdict: zero slack. Relocate.** Not one spare pointer slot exists in front of or behind this
array.

### 3.2 `clientSelectionGroup2` (`0x0059724C`) — no slack; it is a double-tap timer behind it

The array is confirmed 12 slots: `CMDACT_HotkeyUnit` (`0x004C07B0`) clears exactly 12 dwords from
`0x0059724C` before copying the new group in, `CMDACT_Select` walks it with `MOV EBX,0xc` /
`CMP EAX,0xc` against `LEA EAX,[EAX*0x4 + 0x59724c]`, and all 12 element offsets appear in the xref
table. **teippi's `Unit*[12]` typing at `0x0059724C` is correct.**

Its one-past-the-end address `0x0059727C` is a live global, read and written in the same function:

```c
if ((lastHotkeyId == DAT_00597280) && (GetTickCount() - DAT_0059727c < 500)) { /* double tap */ }
DAT_00597280 = lastHotkeyId;
DAT_0059727c = GetTickCount();
```

So `0x0059727C` is the **last-hotkey-tap timestamp** and `0x00597280` the **last hotkey group id**
(`0xFF` = none), implementing the 500 ms double-tap-to-centre behaviour.

**Verdict: zero slack. Relocate.**

Observation, unexplained: three routines (`0x0049A320`, `0x004BF8A0`, and the game-start reset at
`0x004EED10`) clear only the *first three* slots of this array — `0x0059724C`, `0x00597250`,
`0x00597254` — rather than all twelve. The 12-slot reading is not in doubt (12 referenced offsets,
two 12-iteration clears, and an occupied neighbour at `0x0059727C` leave no room for a longer
array), but why those three are singled out is not established here. **[unresolved]**

### 3.3 `activePlayerSelection` (`0x006284B8`) — no slack, hard against `playersSelections`

Confirmed from the binary, not from arithmetic. The reset routine at `0x0049A320` is:

```
MOV ECX,0xc        MOV EDI,0x6284B8    REP STOSD     ; 12 dwords  -> activePlayerSelection
MOV ECX,0x60       MOV EDI,0x6284E8    REP STOSD     ; 96 dwords  -> playersSelections (8x12)
```

`0x006284B8 + 12×4 = 0x006284E8` exactly, and the two clears are adjacent and abutting. In front of
it, `0x006284B4` (51 refs) and `0x006284B6` (41 refs, `selectionIterator`) are both live, so there
is no room ahead either.

**Verdict: zero slack, both sides. Relocate.**

### 3.4 `playersSelections` (`0x006284E8`) — no slack; a 3 KB string buffer starts at its end

The array is 384 bytes (`8 × 12 × 4`), confirmed three times over by the `MOV ECX,0x60` +
`REP STOSD` clears at `0x0049A32F`, `0x004EED1F` and `0x004EEDE5`. It ends at `0x00628668`, and
that address is where a formatted-string buffer begins:

```c
Ordinal_578(&DAT_00628668, 0xc00, "<gameresult>%s</gameresult><playernames>%s</playernames>\r\n%s\r\n%s\r\n", …);
```

A `0xC00` = **3072-byte** buffer, written by an `snprintf`-class call. `0x00628668` is also read as
a byte (`MOV AL,[0x00628668]`, a "is the buffer non-empty" test) and pushed as a pointer. Widening
`playersSelections` in place would write selection pointers straight into that buffer.

Separately, `0x00628668` *also* serves as the one-past-the-end pointer for a reverse walk over the
8 player rows (`piVar9 = &DAT_00628668; iVar5 = 8; do { … } while(--iVar5);`) — the same dual role
`0x00597238` plays in §3.1.

**Verdict: zero slack. Relocate.** This confirms the recon document's two-source adjacency claim
for the `0x006284B8`/`0x006284E8` pair and adds the identity of the neighbour behind the table.

### 3.5 `selection_hotkeys` (`0x0057FE60`) — the one array with measurable room behind it

Size confirmed from the binary twice, independently of any public source:

- `MOV ECX,0x6C0` + `MOV EDI,0x57FE60` + `REP STOSD` at `0x004965A3` and `0x004EEC73` —
  **1728 dwords = 6912 bytes**.
- `IMUL EDI,EDI,0x360` at `0x00496D41` — per-player stride **864 = 18 × 12 × 4**, and
  `SUB EDI,0x30` at `0x00496D61` — per-group stride **48 = 12 × 4**.

So the shape is exactly `[8][18][12]` × 4 bytes, ending at `0x00581960`. **teippi's dimensions are
right.**

Behind it: **no absolute address anywhere in StarCraft.exe encodes any address in
`0x00581960`–`0x00581D5F`.** The first absolutely-addressed global after the array is
`0x00581D60` — a byte-sized global with 10+ referencing instructions — leaving a **1024-byte
(0x400) run with no static claim on it.**

Two cautions, both material:

1. Ghidra *does* report references at `0x00581C60`+ inside this run. They are constant-propagation
   artefacts: `selectSingleUnitFromID` computes `EDI = player*0x360 + 0x580194` and walks groups,
   and the analyzer propagated player values past 7. Traced by hand, the real maximum address that
   code touches is `0x00581944`, inside the array. These are **not** evidence of a neighbour.
2. Unreferenced is not the same as free. A global reached only through a computed base never has
   its address encoded anywhere and is invisible to both passes (§1.3). 1024 bytes is only 21 hotkey
   groups' worth — it would not get 8 players from 18 groups of 12 to 18 groups of 24 (that needs
   another 6912 bytes) — so this room is interesting but not sufficient.

In front of the array, `0x0057FE40` is the last referenced address, leaving 28 unclaimed bytes at
`0x0057FE44`–`0x0057FE5F`.

**Verdict: ~1 KB of unclaimed space behind it, not enough to double the array. Relocate — but this
is the one array where a small in-place extension is worth costing before deciding.**

### 3.6 Summary

| Array | Ends at | What is immediately behind it | Slack | Decision |
|---|---|---|---|---|
| `clientSelectionGroup` | `0x00597238` | end-sentinel **and** HUD/console global; `client_selection_changed` 4 B later | none | relocate |
| `clientSelectionGroup2` | `0x0059727C` | last-hotkey-tap timestamp (`GetTickCount`) | none | relocate |
| `activePlayerSelection` | `0x006284E8` | `playersSelections` itself | none | relocate |
| `playersSelections` | `0x00628668` | 3072-byte game-result string buffer | none | relocate |
| `selection_hotkeys` | `0x00581960` | nothing statically addressed for 1024 bytes | ~1 KB `[unverified as free]` | relocate |

`selection-cap.md` §7 candidate #5 ("byte-patch 12 → 24") is **confirmed to corrupt memory** for
four of the five arrays, by direct identification of the neighbour that would be overwritten in
each case. That is now demonstrated rather than inferred.

---

## 4. §8 Q2 — immediate-constant inventory

Committed table: [`data/selection-immediates.tsv`](data/selection-immediates.tsv) — 111 occurrences,
each with instruction address, value, and role. 35 functions were swept; 28 of them contain at
least one watched value.

Function list = `selection-cap.md` §4.1–§4.5, **plus** eleven functions that touch the selection
globals and are named in no public source; they were found by the Q1 sweep and are labelled from
what their code does. Watched values: `0x0C`, `0x0B`, `0x30`, `0x2C`, `0x12`, `0x1B00` (6912),
`0x6C0` (1728), `0x360` (864), `0x60` (96).

### Roles

| Role | Count | Meaning |
|---|---|---|
| `struct-or-stack-offset` | 47 | the value is a memory displacement (`[ECX + 0xc]`, `[EBP + 0xc]`) — **not** a cap |
| `comparison` | 22 | right-hand side of a `CMP` — a check |
| `loop-bound` | 14 | loaded into a register that then drives a counted loop |
| `abi-stack-cleanup` | 10 | `RET 0xc` / `ADD ESP,0xc` — calling convention, **not** a cap |
| `unit-tag-shift` | 10 | `SAR/SHL reg,0xb` — **not** a cap, see below |
| `array-size` | 5 | `REP STOS` element count — a real buffer length |
| `index-scale` | 2 | multiplies or steps an index |
| `unrelated-constant` | 1 | a unit-id comparison that happens to equal a watched value |
| `command-id` | 1 | see below |

**43 of the 111 occurrences are cap-relevant.** The other 68 are the reason this had to be a table
and not a byte search: the value 12 appears far more often as `CUnit + 0x0C` (the sprite pointer)
and as a 3-argument stack cleanup than it does as the selection limit.

### The two constants most likely to be misread

- **`0x0B` is almost never "11 slots".** Ten of its twelve occurrences are `SAR EAX,0xb` /
  `SHL EAX,0xb` — the **unit-tag split**. A `StoredUnit` is `(uniqueness << 11) | index`, so 11 is
  the width of the index field, not a selection bound. Patching it would corrupt every unit
  reference on the wire. Only `MOV ECX,0xb` at `0x004C3909` is genuinely selection-derived
  (`SELECTION_ARRAY_LENGTH - 1`: clear the 11 slots after slot 0).
- **`MOV byte ptr [EBP + -0x40],0xb` at `0x004C0A9B` is a command id**, not a count. It is the
  wire opcode `0x0B` (`SelectRemove`/`ShiftDeselect`) being written into an outgoing command
  buffer. See §6.3.

### The cap-relevant sites that matter most

| Address | Function | Value | Role | What it does |
|---|---|---|---|---|
| `0x0046F206` | `SortAllUnits` | 12 | comparison | list-full check, `JL` (signed) → overflow handler `0x0046F040` |
| `0x0049A857` | `getActivePlayerNextSelection` | 12 | comparison | **the order-dispatch iterator bound** — see §5.1 |
| `0x0049AF89` | `addUnitToSelectionSlot` | 12 | comparison | slot bound |
| `0x004C256D` | `CMDRECV_ShiftSelect` | 12 | comparison | packet count check, `JA` (**unsigned**) |
| `0x004C25E0` | `CMDRECV_ShiftSelect` | 12 | comparison | `index + count` check, `JG` (signed) |
| `0x004C275A` | `CMDRECV_Select` | 12 | comparison | packet count check straight off the wire byte, `JA` (**unsigned**) |
| `0x004C2873` | `CMDRECV_Hotkey` | 18 | comparison | group-slot check, `JA` (unsigned) — see §6.4 |
| `0x004C38B3` | `updateSelectedUnitData` | 12 | loop-bound | the 12-element HUD copy |
| `0x00496D41` | `selectSingleUnitFromID` | 864 | index-scale | hotkey per-player stride |
| `0x00496D61` | `selectSingleUnitFromID` | 48 | index-scale | hotkey per-group stride |
| `0x004965A3`, `0x004EEC73` | hotkey clears | 1728 | array-size | 6912-byte `REP STOSD` |
| `0x0049A32F`, `0x004EED1F`, `0x004EEDE5` | selection clears | 96 | array-size | 384-byte `REP STOSD` |

`0x2C` (44) does not occur as an immediate in any function swept. The last-element offset is reached
by pointer walking, not by a `+44` displacement.

---

## 5. Calibration against GPTP

GPTP `ce321f0` (the commit `selection-cap.md` §0 pins) was cloned and read alongside our decompiled
output for five addresses. Three are reported in full below; all five were decompiled successfully.

**Headline: on substance our pipeline and GPTP agree everywhere they overlap.** Every disagreement
found is either a limitation of the decompiler's type/convention recovery or an error in GPTP's
annotation — none is a disagreement about what the code does, with one exception (§5.4) where GPTP
is wrong about a type and the difference is behavioural.

### 5.1 `0x0049AF80` — `addUnitToSelectionSlot`: complete agreement

| GPTP `function_0049AF80` | our decompiled output | |
|---|---|---|
| `unit != NULL` | `unaff_ESI == 0 → return 0` | ✅ |
| `playerId < PLAYABLE_PLAYER_COUNT` | `7 < unaff_EDI → return 0` | ✅ |
| `selection_slot < SELECTION_ARRAY_LENGTH` | `0xb < unaff_EBX → return 0` | ✅ |
| `!(unit->sprite->flags & CSprite_Flags::Hidden)` | `(*(byte*)(*(int*)(ESI+0xc)+0xe) & 0x20) != 0 → return 0` | ✅ (`CUnit+0x0C` = sprite, `CSprite+0x0E` = flags, `0x20` = Hidden) |
| `selection_slot <= 0 \|\| (unit_IsStandardAndMovable(unit) && unit->playerId == *ACTIVE_NATION_ID)` | `if (0 < EBX) { if (!FUN_0047b770()) return 0; if (*(byte*)(ESI+0x4c) != DAT_00512678) return 0; }` | ✅ (`0x0047B770` and `0x00512678` both match GPTP) |
| `playersSelections->unit[playerId][selection_slot] = unit` | `(&DAT_006284e8)[EBX + EDI*0xc] = ESI` | ✅ |
| `if (function_0049A110(playerId)) _CreateDashedSelection(unit)` | `if (FUN_0049a110()) FUN_004e65c0()` | ✅ (`0x0049A110`, `0x004E65C0` both match) |

Seven predicates, seven agreements, including three inherited addresses used as call targets.

**Pipeline limitation, not a disagreement:** the arguments arrive in `ESI`/`EDI`/`EBX` and Ghidra
renders them as `unaff_*` registers because it defaulted to a stack calling convention. Blizzard's
build uses register passing widely here; GPTP's hook declarations encode the real convention.
Decompiled output for this binary should be read with that in mind, and any future automation
should set the convention explicitly rather than trust the default.

### 5.2 `0x004C2750` — `CMDRECV_Select`: agreement, plus one GPTP annotation clarified

Agreements: the `≤ 12` count gate; `StoredUnit` decode (`& 0x7FF` index, `>> 11` uniqueness,
`× 0x150` stride into the unit table at `0x0059CB58`); the staleness test against `CUnit + 0xA5`;
the 12-bounded de-duplication scan over `playersSelections[player]`; the `unit->id != 14`
(Terran Nuclear Missile) exclusion; the call to `0x0049AF80`; and the tail:

```
004C2837   CALL 0x00496560          ; pick least-recently-used recent-selection slot
004C2840   ADD AL,0xa               ; recent groups live at 10..17
004C2842   CALL 0x004965d0          ; save into that hotkey group
004C2854   MOV word ptr [EAX*0x2 + 0x63fe40],CX
```

GPTP's `function_004965D0_Helper(someValue + 10, 1)` matches the `ADD AL,0xa` exactly, confirming
from the binary that hotkey groups 10..17 are the engine's recent-selection ring, and that
`recent_selection_times` at `0x0063FE40` is `u16[8][8]` (indexed `[player*8 + slot]`, 2-byte scale).

### 5.3 `0x004C2560` — `CMDRECV_ShiftSelect`: agreement, and two structural differences

Agreements: `count ≤ 12`; the free-slot scan bounded at 12; `index + count ≤ 12` (`JG`, signed —
matching GPTP's signed expression); the `StoredUnit` decode; the 12-bounded dedup.

Two places where GPTP is a *reimplementation*, not a transcription — both harmless, both worth
knowing before treating GPTP as ground truth:

1. **The free-slot scan is 6-way unrolled in the binary.** GPTP writes
   `while (index < 12 && playersSelections->unit[player][index] != NULL) index++;` and comments
   "optimized compared to original code". Our decompilation shows the original: six explicit
   `if (piVar3[k] == 0) { iVar7 += k+1; break; }` tests followed by `piVar3 += 6`. Same semantics.
2. **`function_0049AF80` is inlined here.** GPTP shows a call; the compiler inlined the whole
   predicate and store into `CMDRECV_ShiftSelect`. Anyone hooking `0x0049AF80` expecting to
   intercept the shift-select path will not intercept it.

**A correction to GPTP's annotation:** GPTP declares
`u16* const u16_0063FE50 = (u16*)0x0063FE50; //very unknown array` and uses it in this function. It
is not a separate array. The binary walks `recent_selection_times` (`0x0063FE40`) *backwards* from
the end of a player's 16-byte row: `puVar6 = 0x0063FE50 + player*0x10` then `--puVar6` before each
read, i.e. `&recent_selection_times[player+1][0]` used as a reverse-iteration base. The LRU scan
that GPTP factors out as `function_00496560` is likewise inlined here.

### 5.4 The one behavioural disagreement: the received count is unsigned

GPTP types both receive handlers' count parameter `s8`
(`CMDRECV_Select(u8 packetId, s8 bCount, StoredUnit*)`), and `selection-cap.md` §8 q8 asks whether
that signedness is real, because it decides whether the protocol ceiling is 127 or 255.

**It is not real. The binary is unsigned.**

```
004C275A   CMP byte ptr [ESI + 0x1],0xc     ; the count byte, read straight from the packet
004C275E   JA  0x004C285E                   ; JA = unsigned above -> reject
```

`JA`, not `JG`. Same in `CMDRECV_ShiftSelect` (`CMP DL,0xc` / `JA` at `0x004C256D`). Counts 13–255
are all rejected. Under GPTP's `s8`, a count of 200 would sign-extend to −56, pass `bCount <= 12`,
and fall into the `bCount > 0` else-path — clearing the player's selection instead of rejecting the
command. The real binary rejects the command whole and clears nothing.

**§8 q8 answered: the count field is unsigned; the protocol ceiling is 255, not 127.**

### 5.5 `0x0046F0F0` — `SortAllUnits`: GPTP's site annotation decoded

GPTP annotates the cap site as `//0x0046F208 (use of SELECTION_ARRAY_LENGTH)`. The instruction is
at `0x0046F206`:

```
0046F206   83 F8 0C    CMP EAX,0xc
0046F209   7C 0C       JL  0x0046F217
```

`0x0046F208` is the third byte of that instruction — **the address of the `0x0C` immediate itself**,
i.e. the byte a patcher would edit. GPTP's annotation is not an error; it is a patch-site address
rather than an instruction address. Worth recording explicitly, because a reader comparing GPTP's
numbers to a disassembly listing will otherwise find them "off by two" throughout that file and
mistrust them.

### 5.6 `0x004C0860` — `CMDACT_Select`: the send side, confirmed

Decompiled successfully; used here to confirm the wire format rather than to compare structure. See
§6.3.

---

## 6. Other §8 questions answered en route

### 6.1 q5 — what a `selection_hotkeys` entry actually is (source disagreement resolved)

teippi types `0x0057FE60` as `Unit*[8][18][12]`; GPTP types it as a `u32` array of `StoredUnit`
values. **GPTP is right.** From `hotkeySaveOrAdd` (`0x004965D0`):

```
00496605   MOV EAX,dword ptr [EAX]      ; the stored entry
0049660B   MOV ECX,EAX
0049660D   AND ECX,0x7ff                ; low 11 bits = unit index
00496613   IMUL ECX,ECX,0x150           ; x sizeof(CUnit) = 336
00496619   MOV EDX,dword ptr [ECX + 0x59cb64]   ; unit table at 0x0059CB58
00496636   MOVZX EDX,byte ptr [ECX + 0xa5]      ; the unit's uniqueness byte
0049663D   SAR EAX,0xb                          ; entry >> 11 = stored uniqueness
00496640   CMP EDX,EAX
00496642   JNZ <treat as empty>                 ; mismatch -> stale entry
```

An entry is `(uniqueness << 11) | unitIndex`, not a pointer. **Stale entries are explicitly
detectable** and the engine detects them — which answers the practical half of q5: a relocated,
widened array must preserve the tag encoding and the `CUnit + 0xA5` check, and cannot simply store
pointers. (Incidental: `sizeof(CUnit) = 0x150 = 336`, unit table base `0x0059CB58`.)

### 6.2 q4 — the fixed-size copies

The copy GPTP describes in `updateSelectedUnitData` is confirmed, and it is at `0x004C38B0` —
an address `selection-cap.md` does not carry, found here as **the only function in the binary that
references both `activePlayerSelection` and `clientSelectionGroup`**:

```c
puVar5 = &DAT_006284b8;  puVar6 = &DAT_00597208;
for (iVar2 = 0xc; iVar2 != 0; iVar2--) { *puVar6++ = *puVar5++; }   /* 12-dword copy */
…
do { … } while ((int)piVar4 < 0x597238);      /* recount, bounded by the end sentinel */
if (DAT_0059723d == '\x01') {                  /* exactly one unit selected */
  DAT_00597208 = iVar2;
  for (iVar3 = 0xb; iVar3 != 0; iVar3--) { *puVar5++ = 0; }   /* clear the other 11 */
}
```

Every element of GPTP's description of this function (`hooks/interface/updateSelectedUnitData.cpp`)
checks out, including the single-unit special case.

Additional fixed-size block operations found, all `REP STOSD` clears rather than copies: 1728 dwords
over `selection_hotkeys` (`0x004965A3`, `0x004EEC73`), 96 dwords over `playersSelections`
(`0x0049A32F`, `0x004EED1F`, `0x004EEDE5`), 12 dwords over `activePlayerSelection` and over each of
`clientSelectionGroup` / `clientSelectionGroup2`. The `SC_memcpy_0`-based shift-click compaction
that `selection-cap.md` §2.4 flags was **not** traced in this task — still open.

### 6.3 The wire format, confirmed from the send side

`CMDACT_Select` (`0x004C0860`) builds three distinct command buffers and queues each through
`0x00485BD0`:

| Instruction | Command id | Name |
|---|---|---|
| `004C0A78  MOV byte ptr [EBP + -0x24],0x9` | `0x09` | `Select` |
| `004C0AB2  MOV byte ptr [EBP + -0x5c],0xa` | `0x0A` | `SelectAdd` |
| `004C0A9B  MOV byte ptr [EBP + -0x40],0xb` | `0x0B` | `SelectRemove` / `ShiftDeselect` |

with the count byte written immediately after the id, and the length computed as
`LEA EDX,[EDX + EDX*0x1 + 0x2]` = **`2 + count*2`** — exactly BWAPI's `2 + targCount * 2`.

This closes an evidence gap flagged in `selection-cap.md` §4.3: command `0x0B` rested on screp
alone, since BWAPI defines no `SelectRemove` class. **The binary emits it.** `CMDACT_HotkeyUnit`
(`0x004C07B0`) likewise builds a 3-byte command with id `0x13`.

### 6.4 A latent out-of-bounds in the vanilla hotkey guard `[unverified consequence]`

```
004C2873   CMP AL,0x12       ; group slot vs 18
004C2875   JA  0x004C289C    ; unsigned -> slots 0..18 pass
```

GPTP transcribes this faithfully as `if (bGroupSlot <= 18)`. But the array has **18 groups per
player** (`0..17`), proven by the 864-byte stride in §3.5. **Slot 18 passes the guard and is one
group past the end of that player's row** — it would land on the next player's group 0, or, for
player 7, past the array entirely.

What the handler then does with slot 18 was not traced (`0x004C2870` is a 19-instruction dispatcher
that forwards to `0x004965D0` / `0x00496940`), so whether the out-of-bounds write is reachable in
practice is **not established here**. Flagged because a cap change that rewrites this guard needs to
know the vanilla bound is off by one, and because it is a candidate explanation for otherwise
unexplained control-group corruption.

---

## 7. Corrections to `selection-cap.md`

Called out separately because these are inherited claims that the binary does not support.

1. **§4.4 "the loop is bound-agnostic — it terminates on NULL, not on a count" is wrong.**
   `getActivePlayerNextSelection` (`0x0049A850`) is 33 instructions and opens with:

   ```
   0049A851   MOV BL,byte ptr [0x006284b6]     ; selection_iterator
   0049A857   CMP BL,0xc
   0049A85A   JC  0x0049A860                   ; iterator < 12 -> continue
   0049A85C   XOR EAX,EAX ; POP EBX ; RET      ; else return NULL
   0049A870   MOV EAX,dword ptr [ESI*0x4 + 0x6284e8]   ; playersSelections[player*12 + iter]
   ```

   The iterator is bounded by a hardcoded 12. NULL entries are *skipped* further down, but
   termination is the count. §4.4 calls this "the single most encouraging finding in this
   document" on the basis that the order-dispatch path would need no change; that conclusion does
   not hold — this function must be changed too. It is called from **71 sites**, which is the good
   news: one function to fix, not 71.

2. **§2.2 records an unresolved disagreement on `clientSelectionCount` (`0x0059723D`)** — BWAPI and
   GPTP say `u8`, teippi types it `offset<uint32_t>`. **Resolved: it is a `u8`.** All 23 accesses in
   the binary are byte-width (`MOV CL,byte ptr [0x0059723d]`, `CMP byte ptr [0x0059723d],0x1`,
   `INC byte ptr [0x0059723d]`, `MOV byte ptr [0x0059723d],BL`). Not one dword access exists.

3. **§2.3's "4 bytes of unidentified space at `0x00597238`" is occupied** — twice over (§3.1). The
   document was right to distrust its own arithmetic and right to ask; the answer is that the
   address is both a real end sentinel used by 44 instructions and a live HUD/console global.

4. **§8 q8's open question resolves against GPTP's typing** — the wire count is unsigned (§5.4).

5. **§8 q5's open question resolves against teippi's typing** — hotkey entries are `StoredUnit`
   u32s, not `Unit*` (§6.1).

6. **`0x0059724C` is a 12-slot array, as teippi says** (§3.2) — with the caveat that three routines
   reset only its first three slots, unexplained.

7. Minor: `selection-cap.md` §2.2 names `0x0051267C` as the active player id. The binary also uses
   **`0x00512688`** (in `selectSingleUnitFromID`) and **`0x00512678`** (GPTP's `ACTIVE_NATION_ID`,
   in `addUnitToSelectionSlot`) in selection code. Three distinct player-id globals are in play in
   this subsystem; conflating them will produce bugs.

**All 23 function addresses inherited from GPTP and teippi resolve to exact function entry points
in the binary — 23 of 23, none off by even one byte.** Given the task's warning to treat a mismatch
as a finding, the absence of mismatches is itself the finding: the public prior art's *addresses*
are trustworthy on this binary. It is the *types* and one *control-flow claim* that needed
correcting.

---

## 8. Confidence and method

### Verified directly against the binary in this task

- The working copy's SHA-256, twice (host tool and Ghidra).
- Language, image base, entry point, section layout, and the BSS boundary (§0).
- 342 referencing instructions across 140 functions for the seven globals (§2).
- 111 constant occurrences with roles (§4).
- The neighbour identity behind every one of the five arrays (§3).
- Array shapes: `[8][12]` for `playersSelections`, `[8][18][12]` for `selection_hotkeys`, 12 for the
  three client/active arrays — each from at least two independent instruction sites.
- Signedness of both receive-side count checks (§5.4), the entry encoding of `selection_hotkeys`
  (§6.1), the width of `clientSelectionCount` (§7.2), and the three send-side command ids (§6.3).

### Inherited and used as-is

- The *names* of the globals and functions, from BWAPI / GPTP / teippi via `selection-cap.md`. This
  task verified the addresses and several types; it did not re-derive the naming.
- `CUnit` field offsets (`+0x0C` sprite, `+0x4C` playerId, `+0x64` unitId, `+0xA5` uniqueness) come
  from GPTP; each was *consistent* with observed use here, which is corroboration, not independent
  derivation.
- GPTP's C for the functions not decompiled in this task.

### Open

- **The `SC_memcpy_0` shift-click compaction** (`selection-cap.md` §2.4, §8 q4) — not traced.
  Whether it has `memcpy` or `memmove` overlap semantics remains unresolved, and it matters for a
  widened array.
- **Whether the ~1 KB behind `selection_hotkeys` is genuinely free** (§3.5) — unreferenced is not
  free, and computed-base globals are invisible to this method.
- **Whether hotkey slot 18 is reachable** and what it corrupts (§6.4).
- **Why three routines reset only three slots of `clientSelectionGroup2`** (§3.2).
- **§8 q6 (`CMDACT_Select` queueing vs the 512-byte TurnBuffer), q7 (status-screen dialog
  resource), q9 (`unit_IsStandardAndMovable` predicate and callers), q10 (other readers:
  triggers, AI, save/load)** — not attempted in this task.
- The residual method gap of §1.3, which applies to every count in §2.

### Reproducing this

Tooling is committed under `tools/ghidra/`:

| | |
|---|---|
| `sweep.ps1` | persistent-project driver: `-Mode Prepare` imports and analyzes once, `-Mode Run` executes a query script against the analyzed program with `-noanalysis` (seconds, not minutes) |
| `scripts/XrefSweep.java` | the two-pass range sweep (§1.1) |
| `scripts/ImmediateSweep.java` | constant sweep + per-function instruction dump |
| `scripts/RegionProbe.java` | byte-level occupancy probe (§3) |
| `scripts/FuncProbe.java` | validates inherited function addresses (§7) |
| `scripts/RawHitDecode.java` | decodes pass-2 hits Ghidra never referenced (§1.1) |
| `scripts/DisassembleAt.java` | recovers code auto-analysis missed (§1.2) |
| `scripts/DecompileMany.java` | batch decompile for calibration (§5) |
| `specs/*.spec` | the swept address ranges and function lists, with the reasoning inline |
| `build-xref-table.ps1`, `build-immediate-table.ps1` | produce the committed tables in `research/data/` |

The Ghidra install lives at `C:\re-tools\ghidra_12.1.2_PUBLIC` (outside every worktree, so that
pruning a merged worktree cannot delete it) and is found via `$env:GHIDRA_INSTALL_DIR`. The Ghidra
project, full listings, decompiled C and per-function instruction dumps are **derived game content**
and stay under `work/scratch/` (gitignored); only the finding tables in `research/data/` are
committed.
