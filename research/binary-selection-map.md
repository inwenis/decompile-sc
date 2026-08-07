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
either as an instruction operand or as an encoded absolute address. Three classes of relocation
site are therefore invisible to them, and only the first two are genuinely out of reach:

1. **Base in a register.** Code that receives the array base as a function parameter. Nothing read
   here suggests that pattern is used for these arrays (every access seen is absolute or
   `base + index*4` off an absolute), but it cannot be excluded by these methods.
2. **Base in another global.** A pointer to the array stored somewhere and dereferenced. Same
   status: not seen, not excludable.
3. **Strides encoded in addressing arithmetic.** This one is *not* out of reach, and round 1 of
   this document wrongly implied it was covered. `LEA EDX,[EDI + EDI*0x2]` followed by
   `LEA EAX,[EBX + EDX*0x4]` computes `slot + player*12` — the row stride of `playersSelections` —
   while naming no address and containing no constant. It is invisible to the cross-reference
   sweep (§2) *and* to the immediate sweep (§4), yet every such site must change to widen the
   array. These are found instead by a scale-factor chain sweep and are tabulated in §2.2. A
   review of round 1 caught this omission; it was a real hole in the relocation work list, not a
   caveat.

Where a count is quoted it is a count of *statically resolvable* references, and that is the
number the relocation work is bounded by from below.

---

## 2. §8 Q1 — cross-reference sweep

### 2.1 Instructions that name a selection address

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
work for candidate #2 in [`selection-cap.md`](selection-cap.md) §7. The arithmetic, since the
numbers do not add up at a glance: the column above sums to **343**, the file holds **345** rows,
and the headline is **342**. 343 + the 2 non-instruction rows of gap 2 below = 345 rows; 343 − 1
double-count = 342 distinct instructions, because the `REP MOVSD` at `0x004C38C2` copies
`activePlayerSelection` into `clientSelectionGroup` and so appears under both globals.

**How to read the "element offsets" column — with the caveat that matters.** The offsets in that
column are *where the instruction lands*, which is not the same as *what is literally encoded in
the instruction*. Only **63 of the 119** `clientSelectionGroup` rows carry an in-range absolute
address at all; the rest reach the array through a register base that Ghidra resolved by constant
propagation. Counting encoded dwords directly (pass 2, which knows nothing about disassembly):

| Global | Distinct element addresses literally encoded | Which |
|---|---|---|
| `clientSelectionGroup` | **7** | `+0, 4, 8, 12, 16, 20, 44` |
| `clientSelectionGroup2` | **6** | `+0, 4, 8, 12, 16, 20` |
| `selectionHotkeys` | 10 | base and mid-array walk bases |
| `playersSelections` | 2 | base and `+4` |
| `activePlayerSelection` | 1 | base only |

So the correct statement is **"≥7 literally-encoded slot addresses, plus register-base accesses
resolved by propagation"**, not "12 separate patch sites per array". Offsets 24–40 of
`clientSelectionGroup` have **zero** encoded dwords anywhere in the binary; their attribution to
slots 6–11 comes from a single 6-way-unrolled loop where the analyzer propagated a register base.
That propagation is sound as an account of what the code touches — but it is the same class of
inference §3.5 warns about, and a relocation strategy costed as "patch 12 absolute slot addresses
per array" would be costing something the binary does not contain. Round 1 of this document made
that over-read; the per-row data was always honest, the summary sentence was not.

The distinction the column still supports is real and still matters: an array with several encoded
slot addresses (`clientSelectionGroup`, `clientSelectionGroup2`) is partly addressed slot by slot,
while an array showing only its base (`activePlayerSelection`) is walked by computed index or
`REP STOSD` — one encoded patch site, many bound constants and strides. The two need different
relocation strategies.

### 2.2 Encoded row strides — the relocation sites no address sweep can find

Committed table: [`data/selection-strides.tsv`](data/selection-strides.tsv).

`playersSelections` is `[8][12]`, so stepping one player row means multiplying by 12. The compiler
does not emit a 12 for that. It emits a scale-factor chain:

```
0049AFB5   LEA EDX,[EDI + EDI*0x2]              ; player * 3
0049AFB8   LEA EAX,[EBX + EDX*0x4]              ; slot + player * 12
0049AFBB   MOV dword ptr [EAX*0x4 + 0x6284e8],ESI
```

or, in the byte-offset variant, an early `SHL` and a plain add:

```
0049A752   LEA EDI,[ESI + ESI*0x2]              ; player * 3
0049A755   SHL EDI,0x4                          ; * 16  -> player * 48 bytes
0049A758   ADD EDI,0x6284e8                     ; &playersSelections[player][0]
```

The first two instructions of each chain name no address and contain no watched constant. **They
are invisible to §2.1 and to §4 — and every one of them must change to widen the array.**

`tools/ghidra/scripts/StrideSweep.java` finds them mechanically rather than by hand: it seeds on
`LEA rD,[rA + rA*0x2]` (the only way to get an odd multiplier out of x86 scaled-index addressing),
follows `rD` forward through the function multiplying in every scale factor applied to it, and
stops at the instruction that dereferences the result. A chain that reaches **48 bytes = 12 dwords
= one selection row** is a row-stride site.

Program-wide it found **322** `×3` chains. 296 are in functions with no connection to any selection
global — `×3` is the compiler's idiom for every 3-, 6-, 12- and 24-byte structure in the binary, so
those are noise by construction and are counted, not committed. The remaining **26** are in the
selection functions, and **20 of them are row strides**:

| Array | Row-stride chains | Sites |
|---|---|---|
| `playersSelections` (12-slot player row) | **14** | `0x004966CC`, `0x00496A83`, `0x0049A185`, `0x0049A21D`, `0x0049A23B`, `0x0049A752`, `0x0049A768`, `0x0049A869`, `0x0049AFB5`, `0x004C257B`, `0x004C2655`, `0x004C26B0`, `0x004C27D3`, `0x004EEDCB` |
| `selectionHotkeys` (12-slot group row) | **6** | `0x004965F6`, `0x00496698`, `0x0049675C`, `0x004967FE`, `0x00496958`, `0x00496B56` |

Addresses are the seed `LEA`; the table carries the rest of each chain and the consuming
instruction. Every one of the 20 resolves to a named target array — 14 end at an access based on
`0x006284E8`, 6 at one based on `0x0057FE60` — so none is an unattributed guess.

The other 6 selection-relevant chains are committed too, with their multipliers (`×3` and `×12`
bytes), precisely because "this selection function contains an `×12` chain that is **not** a row
step" is the kind of near-miss a reader should be able to check rather than take on trust.

**This raises the floor on candidate #2's work list by 20 sites that round 1 did not report.** It
also changes its shape: 6 of the 20 belong to `selectionHotkeys`, so widening a control group and
widening a selection are separate stride edits.

### 2.3 Gaps, stated explicitly

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
6. **Three `playersSelections` rows are semantically `activePlayerSelection` end-pointer
   comparisons.** `CMP EDX,0x6284e8` at `0x0049A303`, `CMP ESI,0x6284e8` at `0x0049AE75` and
   `CMP ECX,0x6284e8` at `0x004C3B62` each terminate an ascending walk (`ADD reg,4`) over
   `activePlayerSelection`, whose one-past-the-end address *is* `0x006284E8` — see §3.3, where the
   two arrays are shown to abut exactly. The sweep files them under `playersSelections` because
   that is the address they encode, which is the right call for a relocation list (moving
   `playersSelections` breaks them). It is the wrong call for reading the code, so it is stated
   here. This is a labelling nuance, not an error: the same address genuinely serves both roles.
   The table's notes carry the same caveat.
7. **Encoded strides are not in this table at all** — by construction; see §2.2 for the 20 sites
   and §1.3 for why neither sweep can see them.
8. Residual method gap: §1.3.

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
   004C38F2   81 FB 38 72 59 00    CMP EBX,0x597238   ; in updateSelectedUnitData, walking clientSelectionGroup
   ```

   These are the loop bounds of the walks over `clientSelectionGroup`. GPTP's constant is not an
   artefact of GPTP; the compiler baked the same one-past-the-end address into 44 sites. Every one
   of them is a relocation site.

   The 44/2 split was re-derived from raw bytes without Ghidra, by scanning `.text` for the
   little-endian dword `38 72 59 00` and decoding the opcode in front of each hit: **46 occurrences
   — 37 `81 /7` (`CMP r32,imm32`), 7 `3D` (`CMP EAX,imm32`), 1 `A1` (`MOV EAX,[abs]`) and 1 `A3`
   (`MOV [abs],EAX`)**. 44 comparisons, 2 data accesses, no third category.

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

Committed table: [`data/selection-immediates.tsv`](data/selection-immediates.tsv) — **139
occurrences**, each with instruction address, value, operand kind, and role. 45 functions were
swept; 37 of them contain at least one watched value.

Function list = the 24 functions of `selection-cap.md` §4.1–§4.5, **plus** 21 that touch the
selection globals and are named in no public source; they were found by the Q1 sweep and are
labelled from what their code does. Watched values: `0x0C`, `0x0B`, `0x30`, `0x2C`, `0x12`,
`0x180` (384), `0x1B00` (6912), `0x6C0` (1728), `0x360` (864), `0x60` (96).

### The classification rule, and the bug that was in it

An x86 instruction can carry a memory displacement and an immediate at the same time, and for this
analysis they mean opposite things:

```
004C275A   80 7E 01 0C    CMP byte ptr [ESI + 0x1],0xc
```

`0x0C` is the selection cap the received packet count is checked against; `0x1` is merely where
that count byte sits in the packet. Round 1 classified rows from instruction *text*, matched the
`[reg + 0x..]` displacement form first, and filed this row as `struct-or-stack-offset`,
`capRelevant=False` — while §5.4 of this same document used it as the evidence that the wire count
is unsigned. Anyone filtering the file on `capRelevant=True`, which is its obvious programmatic
use, would have missed the `CMDRECV_Select` packet-count cap entirely.

`ImmediateSweep.java` now records **`opKind`** — whether the scalar it matched was the immediate or
part of a memory operand — at the point of match, from Ghidra's operand type, and the classifier
keys off that. Re-running over the identical 35-function set produced exactly **two** role changes
in 111 rows, both of them this bug:

| Instruction | was | now |
|---|---|---|
| `0x004C275A  CMP byte ptr [ESI + 0x1],0xc` | `struct-or-stack-offset`, not cap-relevant | **`comparison`, cap-relevant** |
| `0x004C0A9B  MOV byte ptr [EBP + -0x40],0xb` | `struct-or-stack-offset` | **`command-id`** (see below) |

No other row in the file had the same shape. On the unchanged function set the headline becomes
**44 of 111 cap-relevant**, not 43.

### Roles

Over the full 45-function sweep:

| Role | Count | Meaning |
|---|---|---|
| `struct-or-stack-offset` | 53 | the matched scalar is a memory displacement (`[ECX + 0xc]`, `[EBP + 0xc]`) — **not** a cap |
| `comparison` | 31 | right-hand side of a `CMP` — a check |
| `loop-bound` | 15 | loaded into a register that then drives a counted loop |
| `abi-stack-cleanup` | 12 | `RET 0xc` / `ADD ESP,0xc` / `SUB ESP,0xc` — calling convention and frame arithmetic, **not** a cap |
| `unit-tag-shift` | 12 | `SAR/SHL reg,0xb` — **not** a cap, see below |
| `array-size` | 10 | a real buffer extent: a `REP STOS` element count, or a byte length passed to a call |
| `index-scale` | 4 | multiplies or steps an index (`IMUL`, or `ADD/SUB reg,0x30` walking one row) |
| `command-id` | 1 | a wire opcode that happens to equal a watched value |
| `unrelated-constant` | 1 | a unit-id comparison that happens to equal a watched value |

Nine roles, **139 rows, summing exactly**, and no row left `unclassified-review`. (Round 1's table
listed nine roles summing to 112 against a 111-row file, because `command-id` was in the prose but
unreachable in the classifier — the displacement rule caught `0x004C0A9B` first.)

**60 of the 139 occurrences are cap-relevant.** The other 79 are the reason this had to be a table
and not a byte search: the value 12 appears far more often as `CUnit + 0x0C` (the sprite pointer)
and as a 3-argument stack cleanup than it does as the selection limit.

### Values that do not occur — an absence is a finding

Two of the ten watched values produce **zero** rows across all 45 functions, and both absences are
load-bearing:

- **`0x2C` (44)** — the last-element offset of a 12-pointer array. It appears as an immediate
  nowhere. The last element is reached by pointer walking, not by a `+44` displacement.
- **`0x1B00` (6912)** — the byte size of `selection_hotkeys`. Nowhere either: the array's extent is
  expressed as the `REP STOSD` **element** count `0x6C0` (1728 dwords) at `0x004965A3` and
  `0x004EEC73`, never as a byte total. A patcher searching for the byte size would find nothing and
  might conclude the array size is not hardcoded. It is; it is just counted in dwords.

`build-immediate-table.ps1` reports the zero-occurrence values on every run, so this cannot silently
stop being true.

### `0x180` — the array's byte size, and ten functions the round-1 spec missed

`0x180` = 384 = `sizeof(playersSelections)` was not among round 1's watched values, although `0x30`
(48, a 12-pointer row) and `0x6C0` (1728 dwords) already were — the same class of value. It occurs
three times, in a form that also matters:

```
004C2D1D   PUSH 0x180                 ; length
004C2D22   MOV EAX,0x6284e8           ; buffer
004C2D27   CALL 0x004c3450
```

and at `0x004D0139` (`PUSH 0x180` / `PUSH 0x6284e8` / `CALL 0x004C3280`) and `0x004D0688`. All three
are `array-size`, cap-relevant, and all three are **relocation sites that also change the on-disk
format**.

**What they are, checked rather than assumed.** `0x004C3450` and `0x004C3280` are a compressed-block
write/read pair — `_fwrite`/`_fread` in 0x2000-byte chunks, both carrying the debug string
`Starcraft\SWAR\lang\compress.cpp`. Their three callers all carry
`Starcraft\SWAR\lang\saveload.cpp` strings, and `0x004CFEF0` is unambiguously the load path (it
`_fread`s the block at `saveload.cpp:0x78d`–`0x7a9` alongside the unit and sprite blocks). So **all
three `0x180` sites are the save/load path** — which confirms, from this binary, `selection-cap.md`
§8 q10's claim that the savegame format embeds `playersSelections` at its 12-wide size, previously
carried by teippi's source alone. (`0x004C2910` and `0x004D02D0` quote the *same* `saveload.cpp`
line numbers, `0x677` and `0x67e`, i.e. one source routine emitted twice.)

These functions were in the Q1 cross-reference table from the start — they materialise `0x6284E8` —
but were absent from the immediate sweep's **function list**, so their constants never reached the
inventory. Chasing `0x180` exposed the gap; closing it properly meant adding every remaining
`playersSelections` owner, ten functions in all:

| Function | Why it belongs |
|---|---|
| `0x0049A170` `removeUnitFromPlayerSelection` | the shift-click removal compaction — see §6.5. Carries three cap constants (`MOV EBX,0xc`, `CMP EAX,0xc`, `CMP EBX,0xc`) that were missing from the inventory entirely |
| `0x004C2910` `saveGameWriteBlocks` | writes the 384-byte block |
| `0x004D02D0` `saveGameWriteBlocks2` | writes the 384-byte block (second emission of the same source routine) |
| `0x004CFEF0` `loadGameReadBlocks` | reads it back |
| `0x004CEE00` `saveLoadSelectionPtrToTag` | walks all `0x60` dwords converting `CUnit*` → `(uniqueness << 11) \| index` before the write |
| `0x004CEDA0` `saveLoadSelectionTagToPtr` | walks them back after the read, rejecting entries whose `CUnit + 0xA5` no longer matches |
| `0x0049A2C0`, `0x004C3B40` | walk `activePlayerSelection` to its end sentinel |
| `0x00499A60`, `0x0049B870` | index `activePlayerSelection` and read `playersSelections` |

The converter pair is a second confirmation of §6.1's entry encoding, and it is teippi's
`ConvertUnitPtr<true>`/`<false>` over `bw::selection_groups` — cited in `selection-cap.md` §8 q10
from teippi's source, now seen in this binary. Each carries a hardcoded `0x60` element count, so
each is also a cap site.

**The lesson is about the method, not the constant.** The immediate sweep is only as complete as its
function list, and that list was hand-assembled from prior art plus a first look at the Q1 output.
Any function in `selection-xrefs.tsv` that is not in `specs/selection-functions.spec` is an
inventory blind spot by construction. **Coverage is now complete for `playersSelections` — all 20
functions that touch it are swept — and deliberately incomplete elsewhere**: of the 140 functions
that touch any selection global, 45 are swept. The largest remaining gap is `clientSelectionGroup`
(52 touching functions, 3 swept), most of which are HUD/status-screen readers of a single slot. That
gap is stated rather than closed, because it is a scope decision: the cap constants live in the
storage-owning code, and the inventory's purpose is to find them, not to enumerate every reader.

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
| `0x0049A1EF`, `0x0049A213` | `removeUnitFromPlayerSelection` | 12 | comparison | bounds of the shift-click compaction scan — see §6.5 |
| `0x0049A18C` | `removeUnitFromPlayerSelection` | 12 | loop-bound | "not found" sentinel for that scan |
| `0x004C2D1D`, `0x004D0139`, `0x004D0688` | save/load block I/O | 384 | array-size | `sizeof(playersSelections)` written to and read from disk |
| `0x004CEE08`, `0x004CEDA7` | save/load pointer↔tag converters | 96 | array-size | 96-dword walks over the same array |

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
`clientSelectionGroup` / `clientSelectionGroup2`. The shift-click compaction that
`selection-cap.md` §2.4 flags is traced in **§6.5** — it turns out to be an inline `REP MOVSD`, not
a call to `SC_memcpy_0`.

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

### 6.5 q4, second half — the shift-click compaction, found and read

`selection-cap.md` §2.4 and §8 q4 ask about the shift-click compaction that "uses
`SC_memcpy_0`", and round 1 of this document listed it as **not traced**. Following the stride
sweep into `0x0049A170` found it. The function takes a `CUnit*` in `EAX` and a player index, and:

1. scans `playersSelections[player]` **6-way unrolled**, bounded by 12, recording both the index of
   the unit (`iVar4`) and the index of the first NULL (`iVar2` — the live count);
2. if the unit was found and is not the last live slot, shifts the tail down one:

   ```
   0049A21D   LEA ECX,[EDI + EDI*0x2]      ; player * 3
   0049A220   LEA ECX,[EBX + ECX*0x4]      ; found + player * 12
   0049A223   SHL ECX,0x2                  ; -> byte offset
   0049A226   LEA EDI,[ECX + 0x6284e8]     ; dst = &slot[found]
   0049A22C   LEA ESI,[ECX + 0x6284ec]     ; src = &slot[found + 1]
   0049A236   MOVSD.REP ES:EDI,ESI
   ```

3. NULLs the vacated last slot (`0x0049A241`).

Two things follow. **It is not a call to `SC_memcpy_0`** — it is an inline `REP MOVSD`, so hooking a
memcpy would not intercept it. And the overlap question q4 raises is settled for this site: `dst`
is `src − 4` and the copy runs **ascending**, which is exactly the direction that makes a
downward shift correct; there is no `memmove` semantics to preserve because the copy never needs
them. A widened array does not change that, but the `0xC` bounds at `0x0049A18C`, `0x0049A1EF` and
`0x0049A213`, the unrolled scan's step, and the two stride sites above all change.

The first fixed-size copy of q4 (`updateSelectedUnitData`) was already confirmed in §6.2. **q4 is
answered for both copies it names**; what remains open is whether any *other* `REP MOVSD` in the
binary is selection-length-derived, which the stride sweep does not answer because a copy length is
not an addressing scale.

---

## 7. Corrections to `selection-cap.md`

Called out separately because these are inherited claims that the binary does not support.

**All of these have been applied to [`selection-cap.md`](selection-cap.md) itself** (its §10
revision log records them), so that document no longer states the corrected claims. They are kept
here because this is where the evidence lives.

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
   not hold — this function must be changed too. It is reached from **73 sites**, which is the good
   news: one function to fix, not 73.

   The gate itself was re-decoded by hand from the file bytes, without Ghidra:
   `0x0049A857` holds `80 FB 0C` (`CMP BL,0x0C`) followed by `72 04` (`JB +4`). The 73 is sourced
   two independent ways and they agree:

   | Source | Result |
   |---|---|
   | `FuncProbe.java` over the entry point (committed: [`data/selection-function-probe.tsv`](data/selection-function-probe.tsv)) | `refsTotal` **73** |
   | Raw `rel32` scan of `.text` in the file image, no Ghidra involved | **72** `E8` (`CALL`) **+ 1** `E9` (`JMP`) = **73** |

   The one `JMP` is a tail call at `0x0049A8B7` — inside a block that auto-analysis had left as
   undefined bytes and that §1.2's code recovery brought back (seed `0x0049A8B0`). Ghidra files it
   as a call-type reference, which is why `callRefs` reads 73 rather than 72; the raw scan is what
   separates the two forms. Round 1 of this document said "71 sites" and cited nothing — it was the
   only unsourced number in it.

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

The evidence is committed as [`data/selection-function-probe.tsv`](data/selection-function-probe.tsv)
— all 45 swept functions, with the verdict (`ENTRY-POINT` for 45 of 45), body extent, instruction
count and reference breakdown for each. The 23 inherited addresses are the rows whose labels come
from public sources; the rest are this task's own, so they are entry points by construction and
prove nothing on their own.

---

## 8. Confidence and method

### Verified directly against the binary in this task

- The working copy's SHA-256, twice (host tool and Ghidra), on every run including round 2's.
- Language, image base, entry point, section layout, and the BSS boundary (§0).
- 342 referencing instructions across 140 functions for the seven globals (§2.1).
- 20 encoded row strides in the selection functions, out of 322 `×3` chains program-wide (§2.2).
- 139 constant occurrences with roles, across 45 functions (§4).
- The neighbour identity behind every one of the five arrays (§3).
- Array shapes: `[8][12]` for `playersSelections`, `[8][18][12]` for `selection_hotkeys`, 12 for the
  three client/active arrays — each from at least two independent instruction sites.
- Signedness of both receive-side count checks (§5.4), the entry encoding of `selection_hotkeys`
  (§6.1), the width of `clientSelectionCount` (§7.2), and the three send-side command ids (§6.3).
- Four headline claims were additionally **re-decoded by hand from the file's own bytes with no
  tooling in the loop**, because they are the ones the rest of the document leans on:
  `0x0049A857 = 80 FB 0C` (`CMP BL,0xC`, the §7.1 gate); `0x004C275A = 80 7E 01 0C` +
  `0F 87` (`CMP byte ptr [ESI+1],0xC` / `JA`, the §5.4 unsignedness); `0x004C38F2 =
  81 FB 38 72 59 00` (`CMP EBX,0x597238`, the §3.1 sentinel) against `0x004C38FA =
  80 3D 3D 72 59 00 01` (`CMP byte ptr [0x59723D],1`); and the 46 encoded `0x00597238` dwords
  splitting 44 `CMP` / 2 `MOV`. All four agree with the pipeline's output.

### Inherited and used as-is

- The *names* of the globals and functions, from BWAPI / GPTP / teippi via `selection-cap.md`. This
  task verified the addresses and several types; it did not re-derive the naming.
- `CUnit` field offsets (`+0x0C` sprite, `+0x4C` playerId, `+0x64` unitId, `+0xA5` uniqueness) come
  from GPTP; each was *consistent* with observed use here, which is corroboration, not independent
  derivation.
- GPTP's C for the functions not decompiled in this task.

### Open

- **Whether the ~1 KB behind `selection_hotkeys` is genuinely free** (§3.5) — unreferenced is not
  free, and computed-base globals are invisible to this method.
- **Whether hotkey slot 18 is reachable** and what it corrupts (§6.4).
- **Why three routines reset only three slots of `clientSelectionGroup2`** (§3.2).
- **Whether any `REP MOVSD` outside the two now identified has a selection-derived length** (§6.5).
  A copy length is not an addressing scale, so the stride sweep does not answer it.
- **The constant inventory is deliberately partial outside `playersSelections`** (§4): 45 of the 140
  functions that touch a selection global are swept. Coverage is complete for `playersSelections`
  and thin for `clientSelectionGroup` (3 of 52).
- **§8 q6 (`CMDACT_Select` queueing vs the 512-byte TurnBuffer), q7 (status-screen dialog
  resource), q9 (`unit_IsStandardAndMovable` predicate and callers)** — not attempted in this task.
  q10 (other readers) is now **partly answered**: save/load is confirmed in this binary (§4, §6.5),
  triggers and AI are not examined.
- The residual method gap of §1.3 — base-in-register and base-in-global — which applies to every
  count in §2. The third class it used to hide, encoded strides, is now covered by §2.2.

### Reproducing this

Tooling is committed under `tools/ghidra/`:

| | |
|---|---|
| `sweep.ps1` | persistent-project driver: `-Mode Prepare` imports and analyzes once, `-Mode Run` executes a query script against the analyzed program with `-noanalysis` (seconds, not minutes) |
| `scripts/XrefSweep.java` | the two-pass range sweep (§1.1) |
| `scripts/ImmediateSweep.java` | constant sweep + per-function instruction dump; records `opKind` per match (§4) |
| `scripts/StrideSweep.java` | scale-factor chain sweep for encoded row strides (§2.2) |
| `scripts/RegionProbe.java` | byte-level occupancy probe (§3) |
| `scripts/FuncProbe.java` | validates inherited function addresses, with a call/jump/total reference breakdown (§7) |
| `scripts/RawHitDecode.java` | decodes pass-2 hits Ghidra never referenced (§1.1) |
| `scripts/DisassembleAt.java` | recovers code auto-analysis missed (§1.2) |
| `scripts/DecompileMany.java` | batch decompile for calibration (§5) |
| `specs/*.spec` | the swept address ranges and function lists, with the reasoning inline |
| `specs/selection-code-recovery.spec` | the 24 disassembly seeds §1.2's code recovery is driven from, so the documented command order actually replays |
| `build-xref-table.ps1`, `build-immediate-table.ps1`, `build-stride-table.ps1` | produce the committed tables in `research/data/` |

Committed data, all of it findings rather than derived game content:
[`selection-xrefs.tsv`](data/selection-xrefs.tsv) (§2.1),
[`selection-strides.tsv`](data/selection-strides.tsv) (§2.2),
[`selection-neighbours.tsv`](data/selection-neighbours.tsv) (§3),
[`selection-immediates.tsv`](data/selection-immediates.tsv) (§4),
[`selection-function-probe.tsv`](data/selection-function-probe.tsv) (§7).

The Ghidra install lives at `C:\re-tools\ghidra_12.1.2_PUBLIC` (outside every worktree, so that
pruning a merged worktree cannot delete it) and is found via `$env:GHIDRA_INSTALL_DIR`. The Ghidra
project, full listings, decompiled C and per-function instruction dumps are **derived game content**
and stay under `work/scratch/` (gitignored); only the finding tables in `research/data/` are
committed.

---

## 9. Revision log

**2026-08-07 — round 2, after adversarial verification.** A reviewer re-derived the headline claims
from raw bytes without this document's tooling, and separately re-ran the pipeline: the sweep chain
reproduced `selection-xrefs.tsv` byte-identically (5008 → 5082 functions), 17 randomly sampled rows
across the three tables each decoded to the claimed instruction, and all inherited addresses
resolved to entry points. What the review found wrong, and what changed:

1. **The constant classifier used instruction text and could not tell a displacement from an
   immediate** (§4). `CMP byte ptr [ESI + 0x1],0xc` at `0x004C275A` — the `CMDRECV_Select` packet
   count cap, the site §5.4 rests on — was filed `struct-or-stack-offset`, `capRelevant=False`.
   `ImmediateSweep.java` now records the operand kind from Ghidra's operand type. Exactly two rows
   in 111 changed; on the unchanged function set the headline is **44 of 111**, not 43.
2. **The `×12` row stride appeared in neither table** (§2.2, §1.3). It is encoded in scale factors,
   so it is invisible to an address sweep and to a constant sweep alike — yet every site must change
   to widen the array. New `StrideSweep.java`; **20 row-stride sites** now committed, 14 for
   `playersSelections` and 6 for `selectionHotkeys`. §1.3 previously described the residual gap as
   base-in-register / base-in-global only, which implied this class was covered. It was not.
3. **`0x180` (384 = `sizeof(playersSelections)`) was not watched** (§4). Added; it occurs three
   times, all in save/load. Chasing it exposed that the immediate sweep's function list was missing
   ten functions that the cross-reference table already showed touching `playersSelections` — those
   are now swept, and coverage for that array is complete. The table grew 111 → 139 rows.
4. **§3.1 quoted `0x004C38FA` for `CMP EBX,0x597238`.** The instruction is at `0x004C38F2`;
   `0x004C38FA` is `CMP byte ptr [0x0059723D],0x1`. Prose error only — the committed table was
   always right. Both re-decoded by hand.
5. **"called from 71 sites" (§7.1) was wrong and unsourced.** It is **73**, confirmed by
   `FuncProbe` (`refsTotal 73`, now committed) and by an independent raw `rel32` scan (72 `CALL` +
   1 tail `JMP` at `0x0049A8B7`).
6. **§4's role table did not match the file it summarised** — nine roles summing to 112 against a
   111-row file, with a `command-id` role that the classifier could never assign. Fixed at the
   source: the role is now reachable, and the table sums exactly.
7. **§2 over-read the element-offset column.** "12 separate patch sites per array" is not what the
   binary shows: only **7** `clientSelectionGroup` slot addresses are literally encoded anywhere,
   and only 63 of its 119 rows carry a literal address at all. Restated, with the propagation
   caveat §3.5 already gave for `selectionHotkeys`.
8. **The code-recovery seed list was not committed**, so §1.2's documented command order did not
   replay. Now `specs/selection-code-recovery.spec`, with its derivation written out.
9. **A watched value with zero occurrences was reported for `0x2C` but not for `0x1B00`.** Both are
   now reported, and `build-immediate-table.ps1` prints the zero-occurrence list on every run.
10. **Three `playersSelections` rows are `activePlayerSelection` end-pointer comparisons.** The
    filing is right for a relocation list and misleading for reading the code; both the table (new
    `note` column) and §2.3 now say so.

One review claim did **not** hold up, and is recorded here rather than quietly dropped: it stated
that `0x004C2D1D` is not save/load. It is. That function carries
`Starcraft\SWAR\lang\saveload.cpp` debug strings and reaches `playersSelections` through the same
compressed-block writer (`0x004C3450`, `compress.cpp`) whose read counterpart the load path
`0x004CFEF0` uses on the identical block list. The instruction to watch `0x180` was right; the
reason given for it was not. (Also minor: the review's third `PUSH 0x180` site is at `0x004D0688`,
not `0x004D0685`.)
