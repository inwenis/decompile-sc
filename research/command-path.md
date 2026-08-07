# The command path in StarCraft.exe 1.16.1 — how a player intent reaches the wire

Analysis date: 2026-08-07 (task 011). Target: `StarCraft.exe`, StarCraft: Brood War 1.16.1
(classic), SHA-256 `AD6B58B27B8948845CCFA69BCFCC1B10D6AA7A27A371EE3E61453925288C6A46` — the
project's disposable working copy `C:\sc-work\1161-base`, hash checked before the run.

Companions:
[`selection-cap.md`](selection-cap.md) (public-sources recon),
[`binary-selection-map.md`](binary-selection-map.md) (the selection subsystem in this binary),
[`runtime-selection-observations.md`](runtime-selection-observations.md) (those addresses in a
live process).

This document answers the question those three left open: **the selection is understood, but how
does an order actually leave the client, and where can a plugin get between the two?** It was
written because task 011 needed to emit `Select`+order pairs, and emitting a command you have not
read the encoding of is guesswork.

Everything below is static analysis of the working copy plus, where stated, values observed in a
live process. `C:\sc-install\Starcraft` was never opened.

---

## 0. Verdict up front

1. **There is exactly one funnel.** Every outgoing command in the binary — all 51 ids, from 94
   distinct call sites — is appended to the turn buffer by one function,
   **`queueCommand` at `0x00485BD0`**, `__fastcall(ECX = bytes, EDX = length)`. A plugin that
   hooks that one function sees, and can modify or suppress, every command the client sends.
2. **The unit-tag encoding is settled, from the binary, three times over.** It is
   `(unit[0xA5] << 11) | ((unitPtr - 0x0059CCA8) / 0x150 + 1)`, valid while the index is
   `<= 0x6A4`. This closes the open question in
   [`runtime-selection-observations.md`](runtime-selection-observations.md) §3.5, which could only
   call the community's `0x0059CCA8` "strong support … but unverified prior art". §4.
3. **The pre-cap selection is observable without reimplementing any selection logic.** The engine
   calls `0x0046F040` once for every unit that passed every selection filter and did not fit in
   the 12 slots. That handler is the one place the units the cap is about to discard exist
   individually. §3.
4. **Right Click is 10 bytes and Targeted Order is 11**, with layouts read instruction by
   instruction. §5. Those two are the only ids this task *names* from its own evidence; the other
   49 are tabulated with their lengths and emitters but deliberately left unnamed. §6.
5. All five function addresses this task hooks were already known to be entry points
   ([`binary-selection-map.md`](binary-selection-map.md) §7: 23 of 23 inherited addresses resolve
   exactly). What is new here is their **calling conventions, their prologue bytes, and their
   behaviour**.

---

## 1. `queueCommand` (`0x00485BD0`) — the funnel

```
00485BD0  55                 PUSH EBP
00485BD1  8BEC               MOV EBP,ESP
00485BD3  51                 PUSH ECX
00485BD4  A1A04A6500         MOV EAX,[0x00654AA0]        ; sgdwBytesInCmdQueue
00485BD9  53                 PUSH EBX
00485BDA  56                 PUSH ESI
00485BDB  8BDA               MOV EBX,EDX                 ; EDX = length
00485BDD  8BF1               MOV ESI,ECX                 ; ECX = command bytes
00485BDF  8B0DD8F05700       MOV ECX,dword ptr [0x0057F0D8]
...
00485C3D  E8FEFDFFFF         CALL 0x00485A40             ; flush the turn when full
...                          ; then: memcpy(&TurnBuffer[bytesInQueue], ECX, EDX)
                             ;       bytesInQueue += EDX
                             RET                          ; no stack args
```

Decompiled, the body is:

```c
if (DAT_0057f0d8 < DAT_00654aa0 + in_EDX) {          /* would not fit */
  if (DAT_00596904 == 4) return;                     /* DROPPED */
  if (Ordinal_115(&local_8) == 0) { ...error path...; return; }   /* DROPPED */
  if ((0x10 - DAT_0057f090) <= local_8) return;      /* DROPPED */
  FUN_00485a40();                                    /* flush and continue */
}
memcpy(&DAT_00654880 + DAT_00654aa0, in_ECX, in_EDX);
DAT_00654aa0 += in_EDX;
```

| Fact | Value | How known |
|---|---|---|
| Convention | `__fastcall(ECX = const void* bytes, EDX = size_t len)`, `RET` (no stack args) | `MOV EBX,EDX` / `MOV ESI,ECX` as the only input reads; every call site sets both (e.g. `MOV EDX,0xa` / `LEA ECX,[EBP + -0xc]` at `0x004C03DE`) |
| Turn buffer | `0x00654880` | the memcpy destination is `&DAT_00654880 + DAT_00654AA0` |
| Bytes in queue | `0x00654AA0` (u32) | read at `0x00485BD4`, incremented at the tail |
| Queue capacity | `0x0057F0D8` (u32) | the bound the length is checked against |
| Callers | **94 distinct functions, 117 references** | `HookProbe.java` reference sweep |
| Prologue for a detour | `55 8B EC 51 A1 A0 4A 65 00` — 9 bytes, 4 whole instructions, none PC-relative | `HookProbe.java` |

`0x00654880` and `0x00654AA0` were inherited from BWAPI (`Offsets.h:75-76`) via
[`selection-cap.md`](selection-cap.md) §4.3. They are **re-derived here**: both appear as literals
inside `queueCommand` itself, doing exactly what BWAPI says they do.

**Three of `queueCommand`'s overflow paths return without queuing anything.** A command that does
not fit and cannot flush is dropped silently, with no error to the caller. Anything that emits
extra commands — which is precisely what fan-out does — has to check the remaining room itself
rather than trust the engine to spill.

### 1.1 `0x00485A40` — the flush

```
00485A40  MOV EAX,[0x00654AA0]        ; empty?
00485A47  JNZ ...
00485A4E  MOV byte ptr [0x00654880],0x5   ; then send a 1-byte 0x05 instead
00485A5B  PUSH 0x654880 ; CALL 0x00410202  ; hand the buffer to the network layer
00485A8B  MOV dword ptr [0x00654AA0],0x0   ; reset
00485A97  JMP 0x0047CC50                   ; which emits the 7-byte 0x37 command
```

Two things fall out. The **0x05 keep-alive is written directly into the turn buffer**, not through
`queueCommand`, which is why it never appears in a `queueCommand` hook's log. And `0x0047CC50`,
tail-called from here, is the sole emitter of the 7-byte `0x37` command — the shape of a per-turn
sync.

---

## 2. `CMDACT_Select` (`0x004C0860`) — the selection commit point

```
004C0860  55 8B EC 83 EC 5C     PUSH EBP / MOV EBP,ESP / SUB ESP,0x5C
...
004C0AC4  C20800                RET 0x8
```

`__stdcall(u32 count, CUnit** units)`. It builds up to three command buffers from `units` and
queues each through `queueCommand`:

| Instruction | id | which |
|---|---|---|
| `004C0A78  MOV byte ptr [EBP + -0x24],0x9` | `0x09` | full Select |
| `004C0AB2  MOV byte ptr [EBP + -0x5c],0xa` | `0x0A` | SelectAdd |
| `004C0A9B  MOV byte ptr [EBP + -0x40],0xb` | `0x0B` | SelectRemove |

(These three were already established in [`binary-selection-map.md`](binary-selection-map.md)
§6.3; they are repeated because §2's point is *which function* they come out of.)

It decides between the full form and the add/remove delta pair by diffing `units` against
`clientSelectionGroup2` (`0x0059724C`, the last-sent selection) — `if (count <= added + removed)`
send the full `0x09`, else send `0x0B` then `0x0A`.

**Consequence for anything that wants to know the client's current selection: watch the FUNCTION,
not the wire.** A hook on `queueCommand` sees `0x0B`+`0x0A` deltas about as often as it sees a
`0x09`, and would have to mirror the engine's delta logic to reconstruct the selection.
`CMDACT_Select`'s `units` argument *is* the new selection, in one place, whatever wire form is
chosen.

Prologue for a detour: `55 8B EC 83 EC 5C` — 6 bytes, 3 whole instructions, none PC-relative.

---

## 3. The input path, and where the cap discards units

### 3.1 `SortAllUnits` (`0x0046F0F0`)

`__stdcall(CUnit** candidates, CUnit** out12, CUnit* clicked) -> u32 count`, `RET 0xC`.
`candidates` is a **NULL-terminated, uncapped** list — the raw contents of the drag box (or the
ctrl+click type match). The function filters it and fills `out12`:

```c
if ((int)local_8 < 0xc) {          /* the cap, at 0x0046F206 */
  param_2[local_8] = iVar5;
  local_8 = local_8 + 1;
}
else {
  FUN_0046f040(iVar5, param_3);    /* the overflow handler, called at 0x0046F210 */
}
```

The filters above that branch are the reason a plugin should not try to rebuild the list itself:
`unit_isUnselectable` (`0x0046ED80`), `unit_IsStandardAndMovable` (`0x0047B770`), an owner check
against `DAT_00512684`, a sprite-visibility flag, and — when a unit was clicked — same-owner,
same-type and several flag comparisons against it. Reimplementing that is a bug farm.

Prologue: `55 8B EC 83 EC 08` — 6 bytes, 3 instructions.

Called from `0x0046FA40` (once) and `0x0046FB40` (twice).

**A fourth player-id global appears here.** `SortAllUnits`'s owner test reads **`0x00512684`**,
which is none of the three that [`binary-selection-map.md`](binary-selection-map.md) §7 note 7
warns about (`0x0051267C`, `0x00512688`, `0x00512678`). That makes four distinct player-id globals
in this subsystem, and the warning applies with more force than it was written with.

### 3.2 `sortOverflowHandler` (`0x0046F040`) — the one place the discarded units exist

Called once for **every** unit that passed every filter but did not fit. It ranks the incoming
unit against the ones already stored and, if the newcomer ranks higher, **overwrites a stored
slot**:

```
0046F0D5  MOV EAX,dword ptr [EBP + 0x8]
0046F0D8  MOV dword ptr [EDI],EAX        ; out12[i] = newcomer  -- EVICTION
```

Convention, read off the prologue: **EAX = current count, ECX = `CUnit** out12`, stack `[EBP+8]` =
the unit, `[EBP+0xC]` = the clicked unit, `RET 8`.** No standard C calling convention describes
that, which is why task 011's detour for it is a hand-written assembly thunk.

Prologue: `55 8B EC 53 56` — 5 bytes, 4 instructions.

Called from `0x0046F210` (inside `SortAllUnits`) and `0x0046F34C` (inside
`combineSelectionsLists`, `0x0046F290` — the shift-add path), so a hook on the handler covers both
without hooking either parent.

**The eviction is the trap.** Recording only the unit passed in is not enough: a unit that was in
`out12` and then got evicted is in neither the final output nor the recorded overflow set.
Snapshotting `out12` on entry, *before* the original runs, is what closes that hole — every
eviction is preceded by a snapshot that still contains the victim.

---

## 4. The unit tag — settled

Three independent instruction sequences compute it identically. The Right Click builder's copy,
in full:

```
004C039E  8BCE                MOV ECX,ESI                 ; ESI = CUnit*
004C03A0  81E9A8CC5900        SUB ECX,0x59cca8            ; - unit array base
004C03A6  B887611886          MOV EAX,0x86186187          ; reciprocal of 0x150
004C03AB  F7E1                MUL ECX
004C03AD  2BCA                SUB ECX,EDX
004C03AF  D1E9                SHR ECX,0x1
004C03B1  03CA                ADD ECX,EDX
004C03B3  C1E908              SHR ECX,0x8                 ; ECX = (ptr - base) / 0x150
004C03B6  41                  INC ECX                     ; +1  -> the wire index is 1-BASED
004C03B7  81F9A4060000        CMP ECX,0x6a4
004C03BD  7604                JBE 0x004c03c3
004C03BF  33C0                XOR EAX,EAX                 ; out of range -> tag 0
004C03C1  EB0C                JMP 0x004c03cf
004C03C3  0FB686A5000000      MOVZX EAX,byte ptr [ESI + 0xa5]   ; uniqueness
004C03CA  C1E00B              SHL EAX,0xb
004C03CD  0BC1                OR EAX,ECX
```

So:

```
index = (unitPtr - 0x0059CCA8) / 0x150 + 1
tag   = (index > 0x6A4) ? 0 : ((unit[0xA5] << 11) | index)
```

The same sequence appears at `0x004C0919` inside `CMDACT_Select` and at `0x004C0323` inside the
Targeted Order builder.

| Claim | Status before this task | Status now |
|---|---|---|
| unit array base `0x0059CCA8` | community prior art; [`runtime-selection-observations.md`](runtime-selection-observations.md) §3.5 called it "strong support … but unverified" and forbade depending on it | **in the binary, three times** |
| `sizeof(CUnit)` = `0x150` | measured live (§3.5, four pointers 336 apart) | corroborated by the reciprocal-division constant `0x86186187` |
| index is 1-based on the wire | not stated anywhere in this repo | `INC ECX` |
| ceiling `0x6A4` = 1700 | BWAPI's unit limit, inherited | `CMP ECX,0x6a4 / JBE` |
| tag = `(uniqueness << 11) \| index` | [`binary-selection-map.md`](binary-selection-map.md) §6.1, from the hotkey path | same encoding on the send path |

The `0x0059CB58` that §6.1 of the binary map quotes for the *hotkey* decode is `0x0059CCA8 -
0x150`, i.e. the same array addressed one element earlier, which is the other half of why the wire
index is 1-based. The two are consistent, not contradictory.

---

## 5. Right Click (`0x14`) and Targeted Order (`0x15`)

These two are the only ids this task claims a *name* and a *layout* for, because they are the only
two whose builders it disassembled in full.

**Right Click, 10 bytes**, built by `0x004C0380` (and identically by `0x004563A0`), buffer at
`EBP-0xC`, `MOV EDX,0xa` before the call:

| offset | size | from | meaning |
|---|---|---|---|
| 0 | u8 | `MOV byte ptr [EBP + -0xc],0x14` | command id |
| 1 | u16 | `[EBP+0x8]` | x |
| 3 | u16 | `[EBP+0xc]` | y |
| 5 | u16 | computed from `ESI` | target unit tag (0 = ground) |
| 7 | u16 | `[EBP+0x10]` | target unit type |
| 9 | u8 | `[EBP+0x14]` | queued (shift) flag |

**Targeted Order, 11 bytes**, built by `0x004C0300`, buffer at `EBP-0xC`, `MOV EDX,0xb`: identical
through offset 8, then `[9] = DL` (the order id, passed in a register) and `[10] = [EBP+0x14]`
(queued).

`2 + count*2` for the select family, 10 for right click, 11 for targeted order — these are the
numbers [`selection-cap.md`](selection-cap.md) §7 costs the fan-out with, now measured rather than
inferred.

---

## 6. Every command id the binary emits

Committed table: [`data/command-ids.tsv`](data/command-ids.tsv), regenerated by
`tools/ghidra/build-command-table.ps1`.

**51 command ids across 103 emit sites.** For each `CALL 0x00485BD0` the build script walks
backwards (stopping at any intervening `CALL`, and after 14 instructions) for the `MOV EDX,<imm>`
that sets the length, the `LEA/MOV ECX,[EBP + disp]` that sets the buffer, and the
`MOV byte ptr [EBP + disp],<imm>` that writes `buffer[0]`. Widening the window to 40 instructions
produces a byte-identical table — that agreement is the check that a length is attributed to the
call it actually precedes and not to a neighbour.

| id | bytes | emitters | id | bytes | emitters |
|---|---|---|---|---|---|
| `0x06` | computed | 1 | `0x25` | 2 | 2 |
| `0x07` | computed | 3 | `0x26` | 2 | 2 |
| `0x08` | 1 | 2 | `0x27` | 1 | 2 |
| `0x09` | computed | 1 | `0x28` | 2 | 2 |
| `0x0A` | computed | 1 | `0x29` | 3 | 1 |
| `0x0B` | computed | 1 | `0x2A` | 1 | 2 |
| `0x0C` | 8 | 2 | `0x2B` | 2 | 2 |
| `0x0D` | 3 | 2 | `0x2C` | 2 | 2 |
| `0x0E` | 5 | 2 | `0x2D` | 2 | 2 |
| `0x0F` | 2 | 2 | `0x2E` | 1 | 2 |
| `0x10` | 1 | 1 | `0x2F` | 5 | 2 |
| `0x11` | 1 | 1 | `0x30` | 2 | 2 |
| `0x12` | 5 | 1 | `0x31` | 1 | 2 |
| `0x13` | 3 | 2 | `0x32` | 2 | 2 |
| **`0x14`** | **10** | 2 | `0x33` | 1 | 2 |
| **`0x15`** | **11** | 1 | `0x34` | 1 | 2 |
| `0x18` | 1 | 2 | `0x35` | 3 | 2 |
| `0x19` | 1 | 2 | `0x36` | 1 | 2 |
| `0x1A` | 2 | 2 | `0x37` | 7 | 1 |
| `0x1B` | 1 | 2 | `0x54` | 1 | 1 |
| `0x1C` | 1 | 2 | `0x55` | 2 | 2 |
| `0x1E` | 2 | 2 | `0x56` | 10 | 4 |
| `0x1F` | 3 | 2 | `0x58` | 5 | 2 |
| `0x20` | 3 | 2 | `0x5A` | 1 | 2 |
| `0x21` | 2 | 2 | | | |
| `0x22` | 2 | 2 | | | |
| `0x23` | 3 | 2 | | | |

`computed` means the length is not an immediate at the call site — the select family's is
`2 + count*2`, and `0x06`/`0x07` compute a string length.

**Names are deliberately absent for 45 of the 51.** Public prior art (screp's `repcmd/types.go`,
cited in [`selection-cap.md`](selection-cap.md) §4.3) names most of these ids, and the temptation
to paste that list in is strong. This task did not verify those names against this binary, two of
the lengths measured here do not match what a casual reading of that list would predict, and a
plugin that fans out a command whose meaning it guessed is a plugin that can quietly duplicate a
build order. So: ids and lengths are ours and are evidence; names beyond the six established here
(`0x09`, `0x0A`, `0x0B`, `0x13`, `0x14`, `0x15`) are **not claimed**.

Identifying the rest is cheap and does not need any new tooling: task 011's plugin logs
`CMD id=0xNN len=N` for every command, so pressing one key in game names one id.

### 6.1 Two parallel builder families

Nearly every id has **two** emitters, one in `0x00423xxx` and one in `0x004BFxxx`–`0x004C0xxx`,
producing byte-identical commands. Both families funnel into `queueCommand`. What distinguishes
them (button panel vs hotkey, or UI vs trigger) was not established. It matters only in that a
hook placed on one *builder* would miss half the traffic — another reason to hook the funnel.

### 6.2 What the table does not cover

- **14 emit sites build their command buffer somewhere other than an `[EBP + disp]` local** (12 of
  them inside `0x00471A50`, which emits at least 12 different lengths and looks like a generic
  table-driven emitter). They are counted and reported by the build script, not silently dropped,
  and they are absent from the table. They are *not* a gap for anything that hooks `queueCommand`
  — that hook sees them like any other command; they are a gap only in this static id table.
- The 0x05 keep-alive, written straight into the turn buffer by the flush (§1.1).

---

## 7. Confidence and method

### Derived here, from this binary

- The convention, body and globals of `queueCommand` (§1) and the flush (§1.1).
- The conventions and prologue bytes of `CMDACT_Select`, `SortAllUnits` and
  `sortOverflowHandler`, plus the eviction behaviour of the last (§2, §3).
- The unit-tag encoding, from three independent sites (§4).
- The Right Click and Targeted Order payload layouts (§5).
- 51 command ids, their lengths and their emitters (§6).
- The fourth player-id global `0x00512684` (§3.1).

### Inherited and used as-is

- The five function addresses, from GPTP/BWAPI/teippi via
  [`selection-cap.md`](selection-cap.md); each was already confirmed an entry point in
  [`binary-selection-map.md`](binary-selection-map.md) §7 and each is confirmed again here by its
  prologue matching at runtime before the plugin will patch it.
- `CUnit` field offsets `+0x4C` (player), `+0x64` (type), `+0xA5` (uniqueness) — GPTP's, each
  *used* by an instruction read here, which is corroboration and not independent derivation.

### Open

- **The names of 45 command ids** (§6).
- **What the 14 non-`[EBP + disp]` emit sites send**, in particular `0x00471A50` (§6.2).
- **What distinguishes the two builder families** (§6.1).
- **Whether `0x0047CC50`'s 7-byte `0x37` is emitted in single-player** — the tail jump to it is
  conditional on `[0x006556E0]`, which was not traced.
- The residual static-analysis gap of [`binary-selection-map.md`](binary-selection-map.md) §1.3
  (base-in-register, base-in-global) applies to the caller counts here too.

### Reproducing this

```powershell
$env:GHIDRA_INSTALL_DIR = 'C:\re-tools\ghidra_12.1.2_PUBLIC'
./tools/ghidra/sweep.ps1 -Mode Prepare -InputPE C:\sc-work\1161-base\StarCraft.exe `
    -ProjectDir work/scratch/ghidra-sweep -LogFile work/scratch/ghidra-sweep/import.log
./tools/ghidra/sweep.ps1 -Mode Run -ProjectDir work/scratch/ghidra-sweep `
    -ProgramName StarCraft.exe -Script HookProbe.java `
    -ScriptArgs work/scratch/hookprobe/hook-targets.tsv, tools/ghidra/specs/hook-targets.spec
./tools/ghidra/build-command-table.ps1
```

`tools/ghidra/scripts/HookProbe.java` is new in this task. Per spec address it emits the
containing function's full disassembly with raw bytes and a PC-relative flag per instruction, the
byte length of the whole instructions covering a 5-byte detour, whether any of them is
PC-relative, and the complete caller list. The `.asm`/`.callers` files it writes are **derived game
content** and stay under gitignored `work/scratch/`; only
[`data/command-ids.tsv`](data/command-ids.tsv) is committed.
