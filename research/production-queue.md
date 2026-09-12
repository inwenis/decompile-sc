# The production queue — where the 5 lives, and what can be done about it

Task 025. Everything here was derived from `StarCraft.exe` 1.16.1 (the working copy at
`C:\sc-work\1161-base`, SHA-256 `AD6B…6A46`) with the repo's own Ghidra pipeline. Every
address carries how it was found and how it was checked (AGENTS.md hard rule 4). Nothing is
inherited from public prior art: the two community facts that would have been tempting to
copy — "the build queue is `u16[5]` at `CUnit+0x98`" and "`buildQueueSlot` is at `+0xA4`" —
are both re-derived below off instructions in this binary, and the second half of this
document (how the cap is enforced) has no published counterpart at all.

Committed evidence tables:

| file | what it is |
|---|---|
| [`data/production-queue-fields.tsv`](data/production-queue-fields.tsv) | every instruction with displacement `0x98` or `0xA4`, 140 rows, `FieldSweep.java` |
| [`data/production-cap-sites.tsv`](data/production-cap-sites.tsv) | every immediate `5`, `4`, `0xE4`, `0x6A`, `2` in the fifteen queue functions, 100 rows, `ImmediateSweep.java` |
| [`data/production-xrefs.tsv`](data/production-xrefs.tsv) | who calls the enqueue, the cancels, the tick and the command builders, 65 rows, `XrefSweep.java` |

Specs, so the runs are repeatable: `tools/ghidra/specs/production-{functions,callees,module,buttons,cap-sites,emitters,ticksites}.spec`. Section 8 has the exact commands.

---

## 1. The short version

* The queue is a **five-slot ring buffer inside the `CUnit`** — `u16 buildQueue[5]` at `+0x98`,
  head index `u8` at `+0xA4`, empty slot sentinel `0xE4`. §2.
* The 5 is **not a bound the code reads**. It is baked as a literal into six functions —
  including one that is **unrolled five times** — and again into the building AI's two mirror
  arrays. §3.
* There is also **no room**: the array ends at `0xA1` and `0xA2` is the energy field this repo
  already evidenced in task 022. §2.3.
* So option (a), widening in place, is refuted twice over, and this task did not attempt it. §5.1.
* What ships is option (b): a **plugin-side overflow list per building** that feeds the engine's
  five as slots free up, with the money moved exactly once per item. §5.2, §6.
* **The client refuses to send a sixth Train command**, so the plugin holds the ring one item
  BELOW five rather than waiting for an over-cap command that never arrives. This was measured in
  a live game and it contradicts what §4.1 of this document said before that run; the correction
  and its evidence are in §4.1. It is the single fact the shipped design turns on.
* **Cancelling has two controls, not one**, and they reach different halves of the design: a
  **queue icon** in the status pane sends `{0x20, displayIndex}` and the ENGINE refunds it; the
  card's **Cancel button** sends `{0x20, 0xFE}` — "the last queued item" — which is the plugin's
  while it holds any, and is the only wire form that can reach an overflow item at all. Both are
  now proved in a real game, refund by refund. §8.

---

## 2. Where the queue is

### 2.1 The array, from the enqueue's own store

`addToBuildQueue` is `0x00467250`. Its whole body is 151 bytes; the store is one instruction:

```
00467250  PUSH EBP
00467251  MOV  EBP,ESP
00467253  PUSH ECX
00467254  MOV  EDX,EDI                       ; EDI is the building
00467256  CALL 0x004669b0                    ; findFreeBuildQueueSlot
0046725b  CMP  EAX,0x5                       ; <-- 5 means "there is no free slot"
0046725e  MOV  dword ptr [EBP + -0x4],EAX
00467261  JZ   0x0046728a                    ; -> XOR EAX,EAX / RET 4
...
00467292  MOV  EAX,dword ptr [EBP + 0x8]     ; the unit type, the only stack argument
00467295  MOV  ECX,dword ptr [EBP + -0x4]    ; the free slot
00467298  MOVZX EDX,AX
0046729b  MOV  word ptr [EDI + ECX*0x2 + 0x98],AX     ; <-- buildQueue[slot] = type
```

`[EDI + ECX*2 + 0x98]`: base `0x98`, element width 2, index a slot number. That is the array.

**Calling convention**, read off the same listing: `__stdcall(u16 unitType)` with **`EDI` = the
`CUnit*`**, `RET 4`, returning 1 on success and 0 when the queue is full. `EBX` and `ESI` are
pushed and popped inside, and `EDX` is loaded from `EDI` — so the only register the caller has to
set up is `EDI`. That matters in §6.

### 2.2 The head index, and the ring

`findFreeBuildQueueSlot` is `0x004669B0`, thirteen instructions end to end:

```
004669b0  MOVZX EAX,byte ptr [EDX + 0xa4]    ; start at the HEAD
004669b7  MOV   ECX,0x5                      ; five tries
004669c0  DEC   ECX
004669c1  CMP   EAX,0x5
004669c4  JC    0x004669c8
004669c6  XOR   EAX,EAX                      ; wrap
004669c8  CMP   word ptr [EDX + EAX*0x2 + 0x98],0xe4
004669d2  JZ    0x004669de                   ; free -> return this slot
004669d4  INC   EAX
004669d5  TEST  ECX,ECX
004669d7  JNZ   0x004669c0
004669d9  MOV   EAX,0x5                      ; FULL
004669de  RET
```

So: `+0xA4` is the head, the scan wraps, and `5` is simultaneously the try count, the wrap bound
and the "no free slot" sentinel. `EDX` = `CUnit*`, result in `EAX`.

Everything else that touches the array indexes it as `buildQueue[(head + k) % 5]` — `cancelBuildQueueSlot`
(`0x00466A70`), `cancelLastQueued` (`0x00466E40`), `countTypeInQueue` (`0x00466B70`),
`productionTick` (`0x00468420`). It is a ring, not a list.

### 2.3 The array is exactly five slots, and there is nothing behind it

`cancelAllAndClearQueue` (`0x00466E80`) clears the whole thing after refunding it:

```c
*(u32*)(unit + 0x98) = 0xE400E4;
*(u32*)(unit + 0x9C) = 0xE400E4;
*(u16*)(unit + 0xA0) = 0xE4;
*(u8 *)(unit + 0xA4) = 0;
```

Ten bytes, five `u16` slots, `0x98..0xA1` inclusive. That is a size measured off a write rather
than counted off a public struct listing — and it lands hard against `CUnit+0xA2`, the **energy**
field task 022 derived independently (`sc_addresses.h`, `SC_CUNIT_OFF_ENERGY`, evidence in
`research/ability-semantics.md` §3). `0xA4` is the head, `0xA5` the uniqueness byte task 011
derived, `0xA6` the secondary order id task 015 derived. **There is not one spare byte between
`0xA1` and `0xA6`.**

### 2.4 `0xE4` is the empty sentinel

Eleven instructions in the binary store `0xE4` into this array and every reader tests against it
(`data/production-queue-fields.tsv`, filter `field=0x98`, `access=w`):

```
0045D3FF  MOV word ptr [ESI + ECX*0x2 + 0x98],0xe4
0045D47B  MOV word ptr [ESI + ECX*0x2 + 0x98],0xe4
0045DF17  MOV word ptr [ESI + EDX*0x2 + 0x98],0xe4
00466860  MOV word ptr [EBX + EAX*0x2 + 0x98],0xe4
00466B2E  MOV word ptr [EDI + ESI*0x2 + 0x98],0xe4
00468102  MOV word ptr [EDI + ECX*0x2 + 0x98],0xe4
004683B5  MOV word ptr [ESI + EAX*0x2 + 0x98],0xe4
00468501  MOV word ptr [ESI + EDX*0x2 + 0x98],0xe4
004685CE  MOV word ptr [ESI + EDI*0x2 + 0x98],0xe4
0049F2DB  MOV word ptr [ESI + EAX*0x2 + 0x98],0xe4
004E4E43  MOV word ptr [EDI + EAX*0x2 + 0x98],0xe4
```

228 is one past the last real `units.dat` id, which is why it can be a sentinel in a `u16` type
field at all. The Train handler's own bound on the type is `< 0x6A` (§4.1), well below it.

### 2.5 Element format: a bare `units.dat` type id

The value stored is the command payload verbatim — `MOV AX,word ptr [EDI + 0x1]` in the Train
handler, straight into `buildQueue[slot]`. No record, no cost, no progress: **a queued item is one
`u16` unit-type id and nothing else.** Progress lives beside the queue, not in it —
`CUnit+0xE2` is the production state byte and `CUnit+0xEC` the incomplete unit being built
(§4.3).

### 2.6 The building AI carries a parallel copy

`cancelBuildQueueSlot` and `productionTick` both compact the ring, and both mirror the compaction
into a second pair of arrays hanging off `CUnit+0x134`:

```c
int ai = *(int*)(unit + 0x134);
if (ai != 0 && *(char*)(ai + 8) == 3) {          /* a BUILDING ai */
    *(u8 *)(ai + 9    + dst)     = *(u8 *)(ai + 9    + src);
    *(u32*)(ai + 0x18 + dst * 4) = *(u32*)(ai + 0x18 + src * 4);
}
```

`u8[5]` at `ai+9` and `u32[5]` at `ai+0x18`. This is a second, independent place the 5 is
structural. The plugin never touches it — §6.3 explains why it does not have to.

---

## 3. Every place the 5 is enforced

From `data/production-cap-sites.tsv` (`ImmediateSweep` over the fifteen functions, watching
`5`, `4`, `0xE4`, `0x6A`). `MOV reg,0x5` immediately before a division is the `% 5`; `RET 0x4`
rows are stack cleanup and are not cap sites.

| function | address | how the 5 appears |
|---|---|---|
| `findFreeBuildQueueSlot` | `0x004669B0` | `MOV ECX,0x5` (try count), `CMP EAX,0x5` (wrap), `MOV EAX,0x5` (full sentinel) — three literals in thirteen instructions |
| `addToBuildQueue` | `0x00467250` | `CMP EAX,0x5` — the cap test itself |
| `cancelBuildQueueSlot` | `0x00466A70` | `CMP EBX,0x5` (index bound), `MOV ECX,0x5` and `MOV EBX,0x5` (two `% 5`), `MOV ECX,0x4` (`4 - idx`, the compaction length) |
| `cancelLastQueued` | `0x00466E40` | `MOV ESI,0x4` (start at display index 4), `MOV EBX,0x5` (`% 5`) |
| `cancelAllAndClearQueue` | `0x00466E80` | `MOV ESI,0x4` (five iterations 4..0), `MOV ECX,0x5` (`% 5`), plus the ten-byte literal clear of §2.3 |
| `countTypeInQueue` | `0x00466B70` | **five** `MOV EBX,0x5` at `0x00466BDB`, `0x00466C55`, `0x00466C7A`, `0x00466C94`, `0x00466CAE`, and a sixth `MOV ESI,0x5` — the loop is **fully unrolled, one `(head + k) % 5` per slot** |
| `productionTick` | `0x00468420` | `MOV ECX,0x5` ×2 and `MOV EBX,0x5` (`% 5` on the head advance and the compaction), `MOV ECX,0x4` (compaction length) |
| `interceptorTick` | `0x00466790` | `CMP AL,0x5` — the Carrier/Reaver head advance wraps with its own literal |
| `btnCancelTrainCondition` | `0x00428530` | `MOV ESI,0x5` — even the button's grey-out test does its own `% 5` |
| building AI mirror | `ai+9`, `ai+0x18` | five-element arrays, §2.6 |

`countTypeInQueue` is the one to read if only one is read. Its whole body is the same test written
out five times:

```c
u32 head = unit->buildQueueSlot;
char n =  (unit->buildQueue[(head    ) % 5] == type);
if (unit->buildQueue[(head + 1) % 5] == type) n++;
if (unit->buildQueue[(head + 2) % 5] == type) n++;
if (unit->buildQueue[(head + 3) % 5] == type) n++;
if (unit->buildQueue[(head + 4) % 5] == type) n++;
return n;
```

No loop counter, no bound, five copies. A widened array is invisible to it.

---

## 4. The paths

### 4.1 Enqueue — and where the cap really bites

> **CORRECTION, from the first in-game run.** This section used to end by claiming that the
> sixth click still puts a command on the wire and that "the whole cap is that one comparison,
> in one place". **That is wrong**, and the live run disproved it before any of it was built
> on. The static reading below is still correct as far as it goes — the button *condition* is
> genuinely queue-blind — but the client stops sending anyway. What was actually measured, and
> what it means, is at the end of this section under "What the wire says".

Wire command `0x1F` (Train) is 3 bytes: `[0x1F, typeLo, typeHi]`. Two builders emit it
(`data/command-ids.tsv`, task 011): `0x004C01C0` (`CMDACT_Train`) and `0x004234B0`. The second is
the interesting one — `XrefSweep` finds it referenced **only as DATA**, from `0x0051730C` and
`0x00517320`. Dumping `0x005172C0..0x00517360` out of the binary shows a 20-byte record array with
a function pointer at `+4` and the emitter at `+8`: the **build-menu button table**. Three records
carry the Train emitter:

```
0x005172F0  01 00  45 00  60 8E 42 00  B0 34 42 00  45 00 45 00  5B 02 00 00
0x00517304  02 00  53 00  60 8E 42 00  B0 34 42 00  53 00 53 00  60 02 D3 02
0x00517318  03 00  54 00  60 8E 42 00  B0 34 42 00  54 00 54 00  56 02 D4 02
            pos    arg    condition    action       ...
```

All three condition pointers are `0x00428E60`, and that function is:

```c
undefined4 FUN_00428e60(int unit) {
  if (clientSelectionCount > 1 && unit->id != 0x23 && unit->id != 0x2b && unit->id != 0x26)
      return 0;                       /* multi-select, not a Zerg larva-ish type */
  return FUN_0046e1c0(/* EDX = */ playerId);   /* the tech/requirement gate */
}
```

**It does not look at the queue at all** — and neither does anything else on the client that
could. That is worth stating precisely, because it is what made the wrong conclusion tempting:

* `FieldSweep` over displacements `0x98` and `0xA4` lists **every** instruction in the binary
  that touches the ring or its head (`data/production-queue-fields.tsv`, 140 rows, 42 functions).
  The only ones in the UI's own address range are `0x00425600`, `0x004268D0` and `0x00426FF0`,
  which *draw* the status area, and `0x00428530`, which is the **cancel** button's condition
  (`return queue[head] < 0x6A`, i.e. "there is something to cancel").
* Nor does one reach the ring through a helper: `XrefSweep` over the ten functions that do read
  it — `countTypeInQueue` (`0x00466B70`) included — finds callers only in the building-AI range
  `0x00433xxx`–`0x00436xxx` and in the two status-area drawers.
* `0x00428E60`'s own tail call, the requirement VM `0x0046E1C0`, is a 19-case interpreter over
  the requirement tables; it sets `0x0066FF60` to a refusal code on every failure path and none
  of its cases reads the queue.

#### What the wire says

The engine's outgoing-command funnel `queueCommand` (`0x00485BD0`) is hooked in every suite, so
every command this game sends is logged. Pressing the Train hotkey **twelve** times, 250 ms
apart, at a Command Center with an empty queue and 3000 minerals produced:

```
[22:49:18.176] CMD id=0x1F len=3 bytes=[1F 07 00]
[22:49:18.446] CMD id=0x1F len=3 bytes=[1F 07 00]
[22:49:18.715] CMD id=0x1F len=3 bytes=[1F 07 00]
[22:49:18.984] CMD id=0x1F len=3 bytes=[1F 07 00]
[22:49:19.211] CMD id=0x1F len=3 bytes=[1F 07 00]
                        ... and nothing, for the remaining seven presses
```

Five commands at exactly the press cadence, then silence for another 1.75 s of presses. The
frame captured straight afterwards shows the Command Center's queue full — five SCV icons in the
status area, minerals down by exactly `5 × 50` — and the **Train button on the command card drawn
dark**, where the frame taken before the burst has it lit.

So the cap has TWO halves, and only the second is the `CMP EAX,0x5`:

1. **The client will not send.** At five queued the Train button is not usable, so no sixth
   command is ever produced. The predicate behind it was not pinned to an instruction — by the
   sweeps above it does not read the ring, so it is reached some other way — and the design below
   does not need it: what matters is the *measured* behaviour, that the button is dark at five
   and live below five.
2. **The receiver would refuse anyway**, at `addToBuildQueue`'s `CMP EAX,0x5`, which returns 0
   without touching the array or the player's resources. This half still matters: a command that
   arrives from a replay or a network peer is refused here, which is why the plugin still counts
   that case.

The consequence for the design is decisive. A plugin **cannot** wait for over-cap intent to
arrive, because it never arrives. It has to keep the ring below five so that the intent keeps
being expressible — which is what §5.2 does.

The handler around it, `cmdrecvTrain` (`0x004C1C20`), adds three guards of its own: exactly one
unit selected (`selectionIterator = 0` then `getActivePlayerNextSelection` twice), the type
`< 0x6A`, and `FUN_0046E1C0(type, activePlayerId) == 1` — the same tech gate the button condition
calls, which is why a type the button would have greyed out can never arrive here.

### 4.2 The spend

`addToBuildQueue`, immediately after the store:

```
004672a3  TEST byte ptr [EDX*0x4 + 0x664080],0x1     ; units.dat flag, EDX = type
004672ab  JNZ  0x004672dc                            ; set -> move no resources
004672ad  MOVZX EAX,byte ptr [EDI + 0x4c]            ; the owning player
004672b1  SHL  EAX,0x2
004672b4  MOV  EDX,dword ptr [EAX + 0x57f0f0]        ; minerals[player]
004672ba  MOV  ECX,dword ptr [EAX + 0x6ca51c]        ; the pending mineral cost
004672c0  SUB  EDX,ECX
004672c2  MOV  dword ptr [EAX + 0x57f0f0],EDX
                                                     ; and the same for gas at 0x57f120
```

`0x006CA51C` / `0x006CA4EC` are per-player scratch that `setPendingCost` (`0x0042D140`) fills two
instructions earlier from the two per-type tables:

```
0042d149  MOVZX EDI,word ptr [EAX + 0x663888]   ; EAX = type*2   -> mineral cost
0042d150  MOVZX EAX,word ptr [EAX + 0x65fd00]   ;                -> gas cost
```

So the money that leaves is `mineralCost[type]` and `gasCost[type]`, once, at enqueue.

**A queued item is paid for when it is queued, not when it starts building.** That is the
semantics the plugin has to preserve (§5.3).

### 4.3 Dequeue

`productionTick` (`0x00468420`) is the secondary-order handler for production, reached from the
jump table in `FUN_004EC170` at `0x004EC1F9` — i.e. it runs **every frame for every building whose
secondary order is train**. `EAX` = `CUnit*`. State machine on `CUnit+0xE2`:

* `0/1` — if `buildQueue[head] == 0xE4` the queue is dry: clear the secondary order
  (`FUN_004743D0`) and stop. Otherwise create the unit (`FUN_00468200`), stash it at `CUnit+0xEC`,
  state `2`.
* `2` — when the unit finishes: `buildQueue[head] = 0xE4`, `head = (head + 1) % 5`, state `0`.

```
0046851E  MOV byte ptr [ESI + 0xa4],DL          ; the head advance
```

### 4.4 Cancel, and what a destroyed building does

`cmdrecvCancelTrain` (`0x004C0100`, `__stdcall(const u8* cmd)`, `RET 4`) reads the command's `u16`
payload and branches three ways:

```
004c0165  MOVZX EAX,word ptr [ECX + 0x1]
004c016b  SUB  ECX,0xfe
004c0171  JZ   0x004c0185          ; 0xFE -> cancelLastQueued(EAX = unit)
004c0173  DEC  ECX
004c0174  JZ   0x004c018c          ; 0xFF -> nothing
004c0176  CALL 0x00466a70          ; else  -> cancelBuildQueueSlot(EAX = display index, EDI = unit)
```

The build-menu's cancel button is the record at `0x00517340`: position 9, condition `0x00428530`
(§3), action `0x00423490` (the `0x20` emitter), and **`0xFE` sitting at `+0x0E`** — so the button
sends "cancel the last queued item", and clicking one of the five queue icons sends that icon's
display index.

`cancelBuildQueueSlot` refunds before it compacts: `0x00468280` for the in-progress head item,
`refundByType` (`0x0042CEC0`) otherwise. `refundByType` adds back
`mineralCost[type]` and `gasCost[type]` out of the *same two tables* §4.2 subtracted from, gated on
the *same* `units.dat` flag byte. Spend and refund are exactly symmetric, by construction.

**A destroyed building gets its whole queue refunded.** The unit-removal path `FUN_0049FD00` does:

```c
if (unit->buildQueue[unit->buildQueueSlot % 5] < 0x6A) FUN_00466e80();   /* cancel all + clear */
```

and `cancelAllAndClearQueue` calls `cancelBuildQueueSlot` for each occupied slot, i.e. refunds each
one. This is why the plugin refunds its overflow when the building goes (§6.4) — matching vanilla,
not inventing a rule.

### 4.5 The other four production opcodes

`0x23` Unit Morph, `0x27` Train Fighter, `0x35` Building Morph and `0x18`/`0x19` Cancel all reach
the same array through the same two functions (`data/production-xrefs.tsv`: ten callers of
`addToBuildQueue`, four of `cancelBuildQueueSlot`). Task 025 changes the behaviour of **`0x1F`
Train only** — that is the one the user asked about, it is the one whose over-cap intent is
unambiguous, and every other caller (including five AI-side ones at `0x004348C0`, `0x00434720`,
`0x00434FF0`, `0x00435F10`, `0x004A2450`) keeps vanilla behaviour untouched.

---

## 5. The design decision

### 5.1 (a) Widen the array in place — REFUTED, on two independent grounds

Task 021 established the standard for this: prove the surrounding code is not bounds-driven before
rejecting in-place widening. Here the answer is not close.

1. **There is nowhere to widen into.** §2.3: the array occupies `0x98..0xA1` and `0xA2` is the
   energy field, `0xA4` the head, `0xA5` the uniqueness byte, `0xA6` the secondary order. All four
   are load-bearing fields this repo has already evidenced and the plugin already reads. A
   `CUnit` is a fixed `0x150` stride inside a fixed array at `0x0059CCA8` (task 011), so the struct
   cannot grow either.
2. **The code is not bounds-driven.** §3: the 5 is a literal in six functions, the modulo is a
   literal `MOV reg,0x5` before a division in nine places, `countTypeInQueue` is unrolled five
   times with no loop at all, and the building AI keeps two more five-element arrays in step by
   hand. Relocating the array to plugin memory would additionally mean patching all 140 instruction
   sites in `data/production-queue-fields.tsv`.

Either one alone kills it. So (a) is out, and this task did not spend time on it beyond proving so.

### 5.2 (b) A plugin-side overflow list — CHOSEN

The same shadow pattern as the selection fan-out, applied per building:

* the engine keeps its ring, unchanged, and keeps deciding everything about what is in it;
* the plugin holds the tail of the logical queue and hands items over one at a time as slots free.

**Which end the plugin takes its items from is the whole design, and §4.1's correction settles
it.** The obvious arrangement — let the engine fill its five, then catch the sixth command as the
engine drops it — cannot work, because there is no sixth command: the client stops sending at
five. So the plugin works the other way round:

> **Keep the ring at four. Hold everything above it.**

Concretely, after every Train command the engine accepts, and on every production tick:

1. if the ring holds more than `SC_PRODQ_ENGINE_HOLD` (4), take the **newest** item straight back
   out of it — `buildQueue[tail] = 0xE4` — and append it to the building's record;
2. if the ring holds fewer than 4 and the record is not empty, put the **oldest** held item into
   the slot the engine's own free-slot rule picks.

The ring is therefore never full while the player is queueing, the Train button never goes dark,
and every press keeps reaching the wire. Two properties fall out of it that the "catch the sixth"
arrangement did not have:

* **The engine pays for everything, and the plugin pays for nothing.** Every item goes in through
  `addToBuildQueue`, which is also where affordability is checked and the cost deducted (§4.2).
  Taking an item back out and putting it back in are bare stores. So "paid exactly once" is not a
  discipline the plugin has to maintain — it is the only thing that can happen.
* **The cap is vanilla's own.** To stop at `SC_PRODQ_DEFAULT_MAX`, the plugin simply *stops taking
  items back*. The ring fills to five, the client greys its own button out, and the press after
  the maximum is refused by the same code that refuses the sixth press in a stock game. Nothing
  has to be swallowed, un-spent or explained.

The tail is well defined: occupied slots run contiguously from the head, because
`findFreeBuildQueueSlot` scans from the head and stops at the first `0xE4` — a gap behind the head
is unreachable and so never occurs — which makes the newest of `n` items the one at
`(head + n - 1) % 5`. Clearing exactly that slot is what `cancelLastQueued` (`0x00466E40`) does
too; the plugin does it without the refund, because nothing is being cancelled.

### 5.3 The resource hazard, and how it is answered

The three failure modes the task named, and the rule that removes each:

| hazard | answer |
|---|---|
| an item paid for **twice** | **Only the engine ever pays.** Every item enters through `addToBuildQueue` (§4.2), which deducts the cost once. Holding an item back and handing it over again are bare `buildQueue[slot] = type` stores that touch no resource global — so there is no second payer, and "exactly once" is a property of the shape of the design rather than of the plugin's bookkeeping. The plugin's own `mineralsSpent` counter is asserted to be **0** at the end of both the offline and the in-game suite. |
| a **wrong refund** on cancel | The plugin refunds with `mineralCost[type] + gasCost[type]` from tables `0x00663888` / `0x0065FD00`, gated on flag byte `0x00664080`, which is instruction-for-instruction what `refundByType` (`0x0042CEC0`) does — the same two reads the engine's own spend used, with the opposite sign, so they cancel exactly. A cancel that names an engine slot is passed straight through and the engine refunds it as always. |
| the **UI disagreeing** with reality | Every slot the status area draws holds a real item that this building really will build, in order — the plugin only ever removes the newest and re-adds the oldest, so what is on screen is a true *prefix* of the logical queue. It is incomplete, not wrong: items past the ring are not drawn. Known, stated limitation (§7). |

Two more, that the task did not name but the code does:

* **Negative resources.** Not reachable: the plugin never spends, and the engine's own
  affordability check runs on the path that does. An item the player cannot afford is refused by
  `addToBuildQueue` before the plugin sees anything, exactly as in a stock game.
* **A building that dies holding items.** Vanilla refunds the ones in its ring (§4.4). The plugin
  refunds the ones it is holding, on the same event — they were paid for, so the money has to come
  back, and this is the one place the plugin moves any.

### 5.4 How many? 16

Default `SC_PRODQ_DEFAULT_MAX = 16` — the engine's 5 plus 11 — settable per run with
`%SCPLUGIN_PRODQ_MAX%` (`run-with-plugin.ps1 -ProdQueueMax`), clamped to `[5, 24]`.

The reasoning, since the task asked for a justified number rather than a big one:

* **It has to be more than a nuisance to be worth having.** Five is one build cycle's worth; the
  complaint behind this task is having to come back to the same building. Sixteen Marines is a bit
  over three cycles, which is long enough to leave a Barracks alone and do something else.
* **It has to stay inside what the player can afford to lose.** Every item is paid up front, and a
  building that dies refunds — but a building that dies while the player is *away* is exactly the
  case this feature encourages. 16 Marines is 800 minerals; 24 (the hard ceiling) is 1200. Past
  that the feature stops being a convenience and becomes a way to lose an expansion's income to one
  raid.
* **Cancelling is tail-first and one press at a time** (§6.4), so a very deep queue is tedious to
  unwind. 11 presses is tolerable; 100 would not be.
* It is not a memory decision: a record is `unit` + `uniqueness` + `player` + `count` +
  `WORD types[24]`, i.e. about 60 bytes, times 32 tracked buildings.

---

## 6. What the plugin does

`tools/plugin/src/sc_prodqueue.{h,cpp}`. Off unless `%SCPLUGIN_PRODQ%=1`, and ignored outright in
`-Mode observe`, which stays the whole plugin's read-only off switch.

### 6.1 Three detours, all on the receive side

| target | address | patch | why there |
|---|---|---|---|
| `cmdrecvTrain` | `0x004C1C20` | 11 B / 4 instrs, `56 57 8B F8 C6 05 B6 84 62 00 00` | brackets the engine's own handling, so the ring is rebalanced the instant the engine has accepted and paid, before the player can press again |
| `cmdrecvCancelTrain` | `0x004C0100` | 11 B / 4 instrs, `55 8B EC 57 C6 05 B6 84 62 00 00` | a "cancel the last item" belongs to whoever holds the tail |
| `productionTick` | `0x00468420` | 9 B / 3 instrs, `56 8B F0 8B 86 DC 00 00 00` | the frame a slot frees is the frame the next item takes it |

Prologue bytes are dumped out of the binary and handed to `ScHookInstall`, which refuses to patch
if memory disagrees. No window contains a PC-relative instruction, so all three relocate into a
trampoline unchanged — the absolute `MOV byte ptr [0x006284B6],0` is not PC-relative. All three go
in under one thread suspension and a partial set rolls itself back.

Two of the three take their only argument in `EAX` and no C calling convention says so, so each has
a two-instruction thunk (`pushl %eax; call <C fn>; addl $4,%esp; ret`) — the same technique
`sc_fanout`'s `ScOverflowThunk` uses for `sortOverflowHandler`.

### 6.2 Which building — and WHICH SELECTION ARRAY, which is not the obvious one

> **CORRECTION, task 038.** This section used to say the plugin reads `activePlayerSelection[0]`
> and requires `[1]` null, "the same test without calling into the engine". The test is right and
> **the array was wrong**. It cost the group case outright (§10), and it was invisible for two
> tasks because the two arrays agree whenever one building is selected — which is every case
> either suite had.

Both receive handlers reset `selectionIterator` (`0x006284B6`) and then require
`getActivePlayerNextSelection` (`0x0049A850`) to yield exactly one unit (§4.1). That function
names its own array and its own index, in five instructions, dumped from this binary:

```
0049a851  MOV  BL,byte ptr [0x006284B6]            ; the selection iterator
0049a857  CMP  BL,0xC                              ; 12 slots, then stop
0049a860  MOV  EAX,dword ptr [0x0051267C]          ; activePlayerId
0049a865  MOVZX ECX,BL
0049a869  LEA  EAX,[EAX + EAX*2]                   ; player * 3
0049a86d  LEA  ESI,[ECX + EAX*4]                   ; iterator + player * 12
0049a870  MOV  EAX,dword ptr [ESI*4 + 0x006284E8]  ; playersSelections[player][iterator]
```

So the building a production command acts on comes from **`playersSelections`
(`0x006284E8`), row `activePlayerId`, twelve slots per row** — the *simulation's* selection for
the player whose command is being dispatched. Not `activePlayerSelection` (`0x006284B8`), which
is the client's own list and which **abuts it exactly** (`0x006284B8 + 12×4 == 0x006284E8`,
[`binary-selection-map.md`](binary-selection-map.md) §3.3) — the two are adjacent, both are
`CUnit*[12]`, and they hold the same thing whenever the player has one building selected.

The plugin therefore reads that row, with that arithmetic, and applies the engine's own test to
it: slot 0 non-null, slot 1 null, then the pointer bounds/stride-validated against the unit
array. An `activePlayerId` outside `0..7` answers "not ours" rather than reading past the array.

### 6.3 Both directions are one store

```c
/* hold back: the newest item, off the tail of the ring */
int tail = (head + engineLen - 1) % 5;
types[count++] = buildQueue[tail];
buildQueue[tail] = 0xE4;

/* promote: the oldest held item, into the slot the engine would have used */
int slot = FindFreeSlot(unit);            /* the re-implementation of 0x004669B0 */
if (slot < 5) buildQueue[slot] = types[0];
```

Nothing else from `addToBuildQueue` applies: the pending-cost tables it fills are consumed by its
own deduction two instructions later and the plugin is not deducting; the secondary order is
already set, because the ring is never emptied by either move; and `addToBuildQueue` never writes
the AI mirror arrays of §2.6 either — only the *compaction* paths do, and those still run,
unchanged, on whatever the ring holds. Clearing the tail is exactly the store `cancelLastQueued`
(`0x00466E40`) makes, minus its refund. After either move the plugin sets `SC_VA_STAT_DIRTY`
(`0x0068C1F8`), the same redraw flag the Train handler's own tail writes.

`FindFreeSlot` is re-implemented rather than called because the engine's version wants its
`CUnit*` in `EDX`, and because the offline test suite has no engine to call. It is thirteen
instructions and it is quoted in §2.2 beside the C.

### 6.4 Cancel

* payload `0xFE` ("cancel the last queued item") **and** the plugin holds overflow for that
  building → the plugin pops its own tail, refunds it, and the engine's handler does not run. The
  last item of the logical queue really is the plugin's, so this is the correct owner.
* payload `0xFE` and the plugin holds nothing → straight through, vanilla.
* payload `0` … `4` (a specific queue icon) → **it depends on what the ring holds behind that
  icon, and the test is the engine's own arithmetic** (task 033; before it, this was
  unconditionally "straight through"):
  * `buildQueue[(head + payload) % 5] != 0xE4` — a real ring item → **straight through**, exactly
    as before. The engine cancels and refunds that slot as usual; the freed slot is filled from
    overflow on the next tick, so the logical queue shortens by exactly one.
  * `== 0xE4` — the ring does not hold it → **the plugin's**. It cancels its own
    `overflow[payload − engineLen]` and refunds it once, or swallows the click if it no longer
    has one. **Vanilla can never produce this click** (an empty slot's icon is drawn DISABLED and
    both of the engine's input paths refuse a disabled control,
    [`command-card.md`](command-card.md) §5) — task 033's indicator can, because it draws those
    icons from the plugin's overflow and lights them. Passing such a click through would have the
    engine refund **by the sentinel type 228**, reading `mineralCost[228]`/`gasCost[228]` past the
    end of both tables and crediting the player whatever is there.
* payload `0xFF` → straight through (it is the engine's no-op).

### 6.5 Garbage collection

A record is dropped, and its items refunded, when the building stops being the building the record
was made about: pointer no longer valid, uniqueness byte moved (slot recycled), owner changed, hit
points zero, or not reachable from `playerUnitList[player]`. The first four are four loads and run
on **every** tick; the list walk is `O(units)` and runs only on the two rare detours (a Train or a
Cancel Train command — a player action). The cost of that split is stated rather than hidden: a
building destroyed while the player is idle is refunded on their next click rather than on the next
frame.

`ScProdQueueRemove` refunds everything still held before it un-splices, so unloading the plugin
mid-game cannot strand paid-for items.

---

## 7. Known limitations

1. ~~**The status area draws at most five icons, and usually four.**~~ **FIXED by task 033** — and
   the user found it first, playing the deployed build: *"when i queue more then 5 units the 5'th
   slot is emtpy"*, and *"when more then 5 units a queued - is the info showing that? (some +x
   number somewhere in tug?)"*. Both are this limitation, seen from the outside.

   What was true, and why: everything past the ring's items is real, paid for and will be built,
   but it was not on screen — and because the plugin keeps the ring at four while the player is
   queueing, the visible count sat one below vanilla's.

   What task 033 does, on the DISPLAY side only (the ring still stops at
   `SC_PRODQ_ENGINE_HOLD` = 4 — raising it is the very thing that makes the client stop sending,
   §4.1):

   * the icons the engine leaves empty are drawn from the plugin's own overflow, so the strip
     shows five again. HOW moved twice: task 033/039 hand-wrote the occupied-slot `statUser`
     fields and cleared DISABLED (which is what destroyed the click, §8.6); task 066 replaced
     the hand-fill with the phantom bracket (§8.8), under which the ENGINE's own layout writes
     every field;
   * a `"+N"` is drawn on the last icon for whatever is queued past those five, as ENGINE-DRAWN
     TEXT through a spliced static-text control ([`status-pane-text.md`](status-pane-text.md)).
     It is a BADGE on that icon's top-right corner: a box in the pane's own black, framed in the
     icon's border blue (both palette indices read off the dialog surface), with the text handed
     to the engine's centre-justified static handler (`0x004EF9C0`). Centred on the icon's art
     it was hard to read (owner, 2026-09-12). The box stays inside the icon, so the icon's own
     repaint still erases it when the count goes away.

     **Where it is painted matters more than what.** Measured, painted only from its own
     control: the badge's fxnUpdate ran at the frame rate and the fill landed (read back right
     after it), yet by the next frame the surface held the icon's own pixels there again
     (corner back to the `0xA0` border) and the captured frame was identical to one with no
     badge. The old centred text, lower in the same icon, always survived. Hypothesis, not
     logged: the progress bar (control 7, dialog rect `(144,39,250,47)`) redraws every frame
     and `updateControl` snaps its dirty rect out to the 16-pixel grid (`0x0041C200`), a band
     that takes in the icons' top rows (to dialog row 60) but not the rows the old text used.
     Either way the answer does not depend on it: the last icon's own fxnUpdate is wrapped (a
     data write, like the interacts), the engine draws the icon, and the badge is painted over
     it in the same pass -- measured on screen at `+11`, `+9` and gone. Palette index 0 is not
     the pane's black: the pane holds it in 12 of its 24840 bytes (`surfInk=24828`);
   * and because a lit icon is a CLICKABLE icon, the cancel side moved with it: §6.4's "payload
     0…4 always passes straight through" is no longer true, and the reason is in §6.4 below.

   The `PRODQ` log line remains the read-back oracle for the queue itself; `QIND` is the one for
   what the pane is showing.

   **The same limit applies to INPUT, which task 028 measured rather than inferred**: those five
   icons are also the only queued items a click can address (§8.1), so an overflow item can be
   cancelled only through the card's Cancel button, which always means "the last one" — tail-first,
   one press each. That is enough to reach every held item, and it is what a player actually has.
2. **Train (`0x1F`) only.** Unit Morph, Train Fighter and Building Morph keep vanilla's five (§4.5).
3. **A one-frame ordering window.** If a slot frees in the same frame a Train command is processed,
   the engine can take that slot for the new item ahead of an older held item. The plugin closes
   the window as far as it can — it rebalances at the end of every Train command as well as on
   every tick — so no free slot survives a frame boundary, and no item is ever lost or
   double-paid; only the relative order of two items queued within one frame of each other can
   differ.
4. **Single-player only**, like everything in this repo (AGENTS.md hard rule 3). The plugin moves
   items in and out of a building's queue outside the command stream — deterministic locally, and
   not something to point at any online service.

---

## 8. Cancelling a queued unit — which control, and why there are two (task 028)

§4.4 established what the *receiver* does with a Cancel Train command. This section
establishes what, on the client, can ever send one — because task 025 proved its cancel path
offline only, and "a player-input feature is unproven until the wire has been watched" is a rule
this repo wrote after being wrong about exactly that (§4.1's correction). Everything in §8.1–8.3
is read out of the binary; §8.4–8.5 is one live run.

**There are exactly two controls, they send different payloads, and each reaches a different
half of the plugin's design.** Neither is where a first guess puts it.

### 8.1 The queue strip is a dialog, and its five icons are controls 2..6

`data/command-ids.tsv` lists two functions that build a `0x20` command: `0x00423490` and
`0x004C01A0`. Neither is a caller of anything interesting on its own, so the search was done the
other way round — over the **117** `E8 rel32` call sites that reach `queueCommand` (`0x00485BD0`),
decoding the `MOV byte ptr [...], imm8` that each one stores into its buffer first
(`work/scratch/028/cmdsites.py`, a byte scan over `.text` with the PE section table parsed from the
same file). Four sites store `0x20`, and only **one of them is inside the status-area module**:

```
call 0x004573E9  cmdByte=0x20   ; in FUN_004573A0
call 0x004234C4  cmdByte=0x20   ; the card button's action, §8.2
call 0x004C01B4  cmdByte=0x20   ; FUN_004C01A0 -- see below
call 0x004C01D4  cmdByte=0x20   ; the 0x1F twin next to it
```

`0x004C01A0` is a `CMDACT_CancelTrain(AX)` that **nothing calls**: an `E8` scan for its address
across `.text` and a dword scan for it across the whole image both return zero hits. It is dead
code, and no claim here rests on it.

`FUN_004573A0` is the live one. It is `__stdcall(BinDlg* control)`, called at `0x00457F75` from the
USER case of `0x00457F30` — which is entries `[1..5]` of the 44-entry per-index interact table at
`0x00504AF0` that [`hud-selection-row.md`](hud-selection-row.md) §2 already evidenced, i.e. the
interact bound at CREATE time to **control ids 2..6**. Decompiled, its whole body is a switch on
the control's own index:

```c
void FUN_004573a0(BinDlg* ctrl) {
  if (isReplay /*0x006D0F14*/ != 0) return;
  switch (ctrl->index) {                 // ctrl+0x20
    case 2: case 3: case 4: case 5: case 6:
        queueCommand({0x20, ctrl->index - 2}, 3);    // <- the five queue icons
    ...
```

with the payload visible in the listing:

```
004573D6  ADD  ECX,-0x2                ; ECX = control->index
004573D9  MOV  word ptr [EBP + 0x9],CX ; the payload
004573E5  MOV  byte ptr [EBP + 0x8],0x20
004573E9  CALL 0x00485bd0              ; queueCommand(buf, 3)
```

So **clicking queue icon k sends `{0x20, k}`**, which §4.4's third branch turns into
`cancelBuildQueueSlot(EAX = k)` — refund, then compact.

The icons are filled by `queueLayout` (`0x004268D0`), the layout the per-unit-type status act
`0x00427890` dispatches to for a producing building (`0x005193A0 + unitId*0xC`, the table
[`hud-selection-row.md`](hud-selection-row.md) §4.2 named; rows 106, 111, 154 and 160 all carry the
same cond/act pair `0x00425180` / `0x00427890`). Its loop is the whole data model:

```c
for (ctrl = firstChildWithIndex(2), k = 0; ctrl && k < 5; ctrl = ctrl->next, ++k) {
    type = portraitUnit->buildQueue[(portraitUnit->buildQueueSlot + k) % 5];   /* +0x98, +0xA4 */
    if (type == 0xE4) { statUser->icon = k + 6; statUser->mode = 6; disable(ctrl); }  /* 0x00418640 */
    else              { statUser->icon = type;  statUser->mode = 3;
                        statUser->type = type;  enable(ctrl); }                       /* 0x00418E00 */
}
```

Three facts fall out, and the test suite asserts all three from memory:

1. **The display index is head-relative**: icon k shows `buildQueue[(head + k) % 5]`, which is the
   same arithmetic `cancelBuildQueueSlot` does with the payload — so the icon and the slot it
   cancels are the same item by construction.
2. **An empty queue slot's icon is DISABLED**, by the same `0x00418640` that greys a command-card
   button, so *how many items the player can click* is a read of five flag words.

   **CORRECTED, 2026-08-13, task 061.** This bullet used to add "*both of the engine's input paths
   refuse that bit ([`command-card.md`](command-card.md) §5)*". That citation is about the CARD's
   input paths — the card button interact's LBUTTONDOWN case `0x00459947` and the hotkey predicate
   `0x004588C0` — and **it does not carry over to the status strip**, which is a different control
   type dispatched by different code. Measured, in a real game (§8.6): a queue icon's own hit-test
   answer `0x00457F82` tests `flags & 8` (VISIBLE) and *nothing else*, and neither the type-2
   button's LBUTTONDOWN path nor its LBUTTONUP path reads `0x2` at any point. What actually stops a
   click on a greyed queue slot is not a refusal at all — see §8.6 — and the difference matters,
   because a plugin that clears `0x2` to make a slot clickable is relying on a mechanism that was
   never the mechanism.
3. **The engine takes the display index from the walk POSITION and the payload from
   `index - 2`** — two numbers it never checks against each other. The read-back reports both, and
   the suite asserts `index == display + 2` rather than assuming it.

### 8.2 The card's Cancel button is the only thing that can send `0xFE`

The other live emitter is the button record at `0x00517340`, dumped from the file image:

```
00517340  slot=9  icon=0x00EC  cond=0x00428530  act=0x00423490  cparam=0  aparam=0x00FE  name=0x02B5
```

`0x00423490` is four instructions: it stores `0x20` and the button's `actionParam` (`CX`, loaded by
the click path at `0x00459918`) and calls `queueCommand`. So the button sends **`{0x20, 0xFE}`** —
"cancel the last queued item" — and its condition is one comparison:

```c
bool FUN_00428530(CUnit* u) { return u->buildQueue[u->buildQueueSlot % 5] < 0x6A; }
```

i.e. "the head slot holds a real unit type". Nothing else in the binary emits `0xFE`.

**That matters because `0xFE` is the plugin's only door.** The plugin holds the *tail* of the
logical queue, so the only cancel that is legitimately its own is "cancel the last item" (§6.4);
a payload of `0`…`4` names a slot in the engine's ring and is passed straight through. If no
control can send `0xFE`, the plugin's refund path — its one resource write anywhere — is
unreachable, and an offline proof of it proves nothing about a real game.

### 8.3 On a Terran producer that slot is SHARED — and the button table alone gets it wrong

A card control takes the **first** button whose condition survives, and slots never shift
([`command-card.md`](command-card.md) §3.2). So a slot-9 button that sorts ahead of Cancel in its
buttonset hides it whenever its own condition holds. Scanning all 250 buttonsets for the record
(`work/scratch/028/cancelbtn.py`):

| buttonset | what sits at slot 9 ahead of Cancel |
|---|---|
| 72 (Carrier), 81, 82, 83, 108, 154 (Nexus), 155, 160 (Gateway), 167 | — nothing |
| 106 (Command Center), 111 (Barracks), 113 (Factory), 114 (Starport), 130 | icon `0x011B` cond `0x004283F0` (Land), then icon `0x011A` cond `0x004287D0` (Lift Off) |

**This document originally concluded from that table that a Terran producer can never show the
Cancel button. The live card read says otherwise, and the table was not enough to see why.** Both
readings are recorded here because the shape of the mistake is the point: `0x004283F0` needs the
building **not** grounded (`CUnit+0xDC & 0x2` clear) and `0x004287D0` needs it grounded, which
looks like a partition that always leaves one of them standing. It is not, because Lift Off's
condition has three more terms:

```c
bool btnLiftOffCond(CUnit* u) {           /* 0x004287D0 */
    return (u->flags & 2)                 /* a grounded building */
        && busy(u) == 0                   /* 0x00401500 */
        && u->[0xC8] == 0x2C && u->[0xC9] == 0x3D;
}
```

and `busy` (`0x00401500`) is, in its first term, the *same test the Cancel button makes*:

```c
bool busy(CUnit* u) {                     /* 1 = this building is producing */
    return !( u->buildQueue[u->buildQueueSlot % 5] == 0xE4 && ...two morph/build cases... );
}
```

`btnCancelTrainCond` is `queue[head % 5] < 0x6A`; `busy` is `queue[head % 5] != 0xE4`. **The two
conditions are complementary**, so the control does not belong to one of them — it changes hands:
Lift Off while the queue is empty, Cancel the moment anything is queued. Which is the sensible
game rule (you cannot lift off mid-production) arrived at from the wrong end.

Measured, on the same control record, in one run (`CARD` lines, the Command Center this suite
also places):

```
idle     slot=9 enabled ctrl=0x04A5A20A icon=0x011A button=0x00517FC4 cond=0x004287D0 act=0x00423230 aparam=0
training slot=9 enabled ctrl=0x04A5A20A icon=0x00EC button=0x00517FD8 cond=0x00428530 act=0x00423490 aparam=254
```

Same `ctrl`, two buttons, and the second is the one that sends `0xFE`.

**So the Cancel button is reachable on every production building, exactly when it is useful**, and
the plugin's overflow-cancel path has a vanilla control everywhere rather than only on Protoss
producers. Task 028's fixture is a **Nexus** anyway — it carries Cancel at slot 9 unshared, trains
Probes on the same 50-minerals-1-supply arithmetic as an SCV, and needs no Pylon — but that is now
a convenience, not a necessity, and the suite reads the Terran card in the same run to keep this
section honest.

The transferable half is the one [`command-card.md`](command-card.md) §6.4 already tabulates: a
button table says which buttons *exist*; only the running dialog says which one a control *holds*.
This is the sixth time in this repo that a static answer to a "what does the player see" question
has been wrong, and the first where the check that caught it was already built into the run.

### 8.4 What the player actually sees, read from the dialogs

`sc_card.cpp`'s second walk (`ScStatusSnapshot`, `STATQ` lines, same `-CardScan 1` switch as the
card) reports the strip the way §8.1 describes it. From the live run, with the plugin holding four
items over the engine's five:

* the strip holds **five** icon controls, ids 2..6, every one `index == display + 2`;
* with a **nine-item logical queue** all five read `enabled` and every one draws a Probe (`0x040`)
  that its own ring slot holds — **the four the plugin is holding are not drawn at all**;
* with **three** queued, exactly three read `enabled` and the other two read `GREYED` with `0xE4`
  behind them.

So the answer to "can the UI address an overflow item?" is **no, not by the strip** — it draws the
ring, five slots, and nothing else. What the player sees is a queue that stops at five, and what
they can click is exactly the items in it. The **card's Cancel button** is the control that reaches
the rest: it means "the last item", the plugin owns that item, and pressing it repeatedly walks the
logical queue down tail-first. That is the same limitation §7.1 already stated about drawing, now
stated about *input* as well, and it is the honest answer rather than a workaround.

### 8.5 The proof, in a real game

`tools/plugin/test-production-queue.ps1` (extended, not forked) drives both cases unattended, on a
fixture of two Nexuses and one Command Center, all the human player's. Every number below is read
from the building's own `CUnit+0x98`, the player's resource global, or the engine's command funnel
— never from the screen. Both clicks land on a point computed from the live control rect.

**Case 1 — an item the PLUGIN holds.** Twelve Train clicks put nine commands on the wire, leaving
`engineLen=5 engine=[0x040,0x040,0x040,0x040,0x040] overflow=4 logical=9 minerals=2550`
(3000 − 9 × 50). The card's slot 9 then reads `cond=0x00428530 act=0x00423490 aparam=254 enabled`
— it read *no Cancel button at all* on the same walk before the burst, which is the negative half
of the pair. One click at its computed centre:

```
CMD id=0x20 len=3 bytes=[20 FE 00]
PRODQEV cancel-last unit=0x00623D08 type=0x040 overflowLeft=3 back=50/0
```

logical `9 → 8`, minerals `2550 → 2600` — **exactly one Probe's 50 back, once**. The plugin's
`cancelled` counter goes to 1 and its `refunded` (building-gone) counter stays 0.

**Case 2 — an item in the ENGINE's ring.** After the queue drains, three more clicks leave
`engineLen=3 overflow=0` with the plugin tracking nothing at all — so a cancel now *cannot* be the
plugin's. The strip reads three icons `enabled` and two `GREYED` with `0xE4` behind them; the icon
for display 1 carries control index 3. One click at its computed centre:

```
CMD id=0x20 len=3 bytes=[20 01 00]
```

the ring goes `3 → 2` with both survivors still Probes, minerals `2450 → 2500`, and the **plugin's
cancel counter does not move** — the engine refunded it, through `cancelBuildQueueSlot`, exactly as
§6.4 says it should.

**Neither case double-refunds and neither loses an item.** The run's detach line reads

```
PRODQSTATS captured=5 promoted=4 cancelled=1 refunded=0 refusedFull=0 refusedCost=0
           mineralsSpent=0 mineralsRefunded=50 gasSpent=0 gasRefunded=0 tracked=0
```

`mineralsSpent=0` is the pay-once claim from the plugin's side; `mineralsRefunded=50` is one
refund, not two. `captured=5` is worth reading twice: the plugin took **five** items back over the
run though only four were ever over the cap, because cancelling one freed room under the maximum
and the next rebalance took another out of the ring. `promoted = captured − cancelled` (4 = 5 − 1)
is the conservation law for its list, and the suite asserts it in that form rather than against a
literal, which is what made the extra capture visible instead of a failure.

And the money reconciles at every point where all three terms are known — `spent = built + queued
+ cancelled`, which is the same number as `accepted`: after the burst 450 = 9 × 50; after the
plugin's cancel 400 = (9 − 1) × 50; after the engine's 500 = (12 − 2) × 50. **`built` is counted
from the wire and not from the unit list, and that is a finding rather than a convenience**: the
engine creates the unit when production *starts* (§4.3), so a unit being built is in the world and
in the ring at the same time and adding the two double-counts it. The first run of this arm read
"1 built + 9 queued + 1 cancelled" for nine accepted items and failed its own identity by exactly
that one.

### 8.6 The filled slot's click was armed and then destroyed — by the plugin (task 061)

The user, playing the deployed build `2c239e6`: *"i can cancel a queue unit by clicking it, but it
doesn't work if i click the last slock when it has our extra +x text"*. §8.1 says clicking icon k
sends `{0x20, k}`; §6.4 says the plugin's own handler serves that click when the ring slot behind
the icon is empty. Both were true, and the click still did nothing, because **no command was ever
emitted**.

**The wire said so first, and it split the problem in one run** (AGENTS.md, task 025). A click on
display 4 with the plugin holding the item behind it produced **`0` × `CMD id=0x20`** at
`queueCommand`, while the card's Cancel and a middle icon emitted normally in the same run —
`PRODQSTATS ... cancelSeen=2` for the whole run. Not a wrong cancel; no cancel. A second run then
clicked a point **inside the icon rect `(221,53,259,88)` but outside the indicator's box
`(231,65,259,81)`** and got the same nothing, which retired the `+N` text as a suspect entirely:
that control is spliced at the TAIL of the child list, the hit test `0x00418340` returns the FIRST
child that accepts a `dwUser=4` probe, and `LSTATIC`'s handler `0x00419190` refuses that code
outright (`0x004191C4[4] = 1` → `0x004191B3`, `XOR EAX,EAX`).

**What the icons are actually handed is the answer.** Wrapping all five icons' interact pointers
(`control+0x2A`, dialog heap, no code patched) with a logging shim that tail-calls the engine's own
handler gives one working control and one failing control in the same dialog, same frame:

```
idx=3  type=14 dwUser=4  flags=0x00000419      the hit test accepts
idx=3  type=4            flags=0x00000419      LBUTTONDOWN
idx=3  type=14 dwUser=4  flags=0x40000419      PRESSED armed -- and it STAYS armed
idx=3  type=5            flags=0x40000419      LBUTTONUP, still armed
idx=3  type=14 dwUser=2  flags=0x00000499      ACTIVATE -> {0x20,1} on the wire

idx=6  type=14 dwUser=6  flags=0x0000041B disabled=1    x1474 in 13 seconds, ~180k more
```

`QINDCLICKSTATS ... wrapped=5 engineFn=0x00457F30` — one interact pointer, all five icons, so there
is no dispatch difference to explain anything.

Five links, each read out of the binary:

1. `disableControl` (`0x00418640`) is a **no-op when the control is already disabled**
   (`TEST AL,2 / JNE ret`). When it does disable, it sends the control a USER event with
   **`dwUser = 6`**:
   ```
   00418685  MOV  dword ptr [EBP-0x14],6     ; dwUser
   0041867f  MOV  word  ptr [EBP-0x8],0xE    ; type = USER
   00418697  CALL dword ptr [ESI+0x2a]
   ```
2. The queue icons are control **type 2** (read off the live dialog). Type 2's handler for
   `dwUser = 6` is `AND dword ptr [EDI+0x18],0xBFFFFFFF` (`0x004E1A9E`) — **clear PRESSED
   (`0x40000000`)**.
3. The mouse-UP handler `0x004E19F0` emits the ACTIVATE **only if PRESSED is still set**
   (`TEST EAX,0x40000000 / JE 0x4e1a5e`). No press, no ACTIVATE, no `FUN_004573A0`, no command.
4. `queueLayout` greys every slot whose ring entry is `0xE4` (§8.1). Display 4's ring entry is empty
   **by design** — §5.2 holds the engine's ring at four so the client keeps sending Train.
5. `FillOverflowIcons` clears that bit directly to light the slot — **which means the engine's next
   `disableControl` is no longer a no-op**. It disables again *and sends `dwUser = 6`*. The two
   sides fight hundreds of times a second; the plugin's half was already in every log as
   `iconsFilled=371834`.

So a mouse-down arms PRESSED and a `dwUser=6` clears it about two milliseconds later; the mouse-up
sixty milliseconds after that finds nothing armed. The other four icons hold occupied ring slots,
are never disabled, and cancel normally — which is the user's report exactly.

**It is a race, not an absolute, and that is measured rather than hedged.** With the logging shim
installed, all three display-4 clicks of one run *did* cancel: the instrument's own file writes
perturbed the game thread enough for the press to survive. Without it, none of three across two
runs. So the pre-fix behaviour is a race the click almost always loses, not one it cannot win, and
a future reader who sees this work once should not conclude the fix has failed.

**THE OBVIOUS FIX WAS TRIED AND IT DOES NOT WORK. THE DEFECT IS OPEN.** For a slot the plugin holds
an item behind, restore the PRESSED bit the disable event clears — read it before delegating, put it
back after — and let the engine's own press/activate cycle complete. Measured, one click, with the
collision happening throughout:

```
across the click: disableOnOwned +136382, disableWithPress +110381, pressKept +110381
  FAIL exactly one 0x20 reached queueCommand (0)
  FAIL minerals go up by exactly one Probe's 50 (2600 -> 2600)
```

**110,381 collisions, 110,381 successful restores, no command.** Restoring the press is necessary
by the argument above and demonstrably not sufficient. It also does harm: `pressKept` went on
climbing for the six seconds between the two readings of a *sixty-millisecond* click (end of run,
807134 of 1153974 disable events arrived with a press in flight), i.e. **the press never comes back
down** — the mouse-up never clears it, which is the same fact as the up never reaching
`0x004E19F0`, the handler that both clears the press and emits the ACTIVATE. It is reverted; the
counters that measured it stay.

What that run did settle: ownership fires on every fill (`iconsFilled=1153974` and
`disableOnOwned=1153974`, one for one — the fight measured exactly), so the blocker is downstream of
the press, in the delivery of the button-UP.

**Where the next attempt starts, and it is one function.** `0x00418830` runs on button-down with the
hit control, sends it a **`dwUser = 5`** "can you take focus" query, and records
`[dlg+0x3e] = ctrl` **only if the control answers non-zero** (`TEST EAX,EAX / JE` past the store).
The dialog's focused control is what the button-up is routed to. The trace shows that query reaching
our icon — `idx=6 type=14 dwUser=5 flags=0x00000418` — so what it *answers* is the open question,
not whether it is asked.

**AND THE RESULT THAT INVALIDATES SINGLE-RUN CONCLUSIONS ABOUT ANY OF THIS, including the ones
above.** The click is a race and each build has only been sampled one run at a time:

| build | click trace | cancelled? |
|---|---|---|
| pre-fix | off | no (3 clicks) |
| pre-fix | **on** | **yes** |
| with the press-restore | off | **yes** |
| with the press-restore | **on** | no |

An instrument that flips the outcome in *both* directions is not the cause; timing is. So "0 of 3
before the fix" is an anecdote with a denominator of three, not a rate. **Anything claiming this
fixed has to click N times and assert the RATE** — a single click against a race is the
check-that-fails-at-random AGENTS.md rates no better than one that cannot fail.

The regression arm in `test-production-queue.ps1` was therefore expected to FAIL until the defect
was fixed, and said so in its own output: red was the defect reproducing, and green one flip of a
coin rather than proof the bug was gone. What it asserted unconditionally was the seam — that the
engine disabled a slot the plugin owns while the button was down — because a run in which that never
happened cannot detect this class of bug whatever its verdict says.

**THE DEFECT IS CLOSED BY §8.8 (task 066).** Everything above stands as the diagnosis and as the
record of the two fixes that do not work; the arm now asserts the fix's own signature instead of
the collision (§8.8 explains why that flip is sound).

### 8.7 Reproducing §8

`peek.py`, `cmdsites.py` and `cancelbtn.py` are throwaway PE-offset readers under
`work/scratch/028/` (gitignored, like `work/scratch/025/peek.py` in §9): each parses the PE section
table out of the same file it reads, so every VA→offset conversion is derived rather than assumed,
and none of their output is committed.

```powershell
# the two live emitters, and the dead one: every queueCommand call site with the command
# byte it stores first
python work/scratch/028/cmdsites.py C:\sc-work\1161-base\StarCraft.exe 0x20
python work/scratch/028/peek.py     C:\sc-work\1161-base\StarCraft.exe callers 0x004C01A0   # empty
python work/scratch/028/peek.py     C:\sc-work\1161-base\StarCraft.exe refs    0x004C01A0   # empty

# the button record, the buttonsets that carry it, and what masks it
python work/scratch/028/peek.py      C:\sc-work\1161-base\StarCraft.exe button 0x00517340
python work/scratch/028/cancelbtn.py C:\sc-work\1161-base\StarCraft.exe 0 200

# the decompiles quoted above. 0x00457F30, 0x00425180 and 0x00427890 are reachable only
# through data tables, so auto-analysis leaves them undefined -- recover them first.
./tools/ghidra/sweep.ps1 -Mode Run -ProjectDir work/scratch/ghidra-sweep -ProgramName StarCraft.exe `
    -Script DisassembleAt.java `
    -ScriptArgs work/scratch/028/recover.tsv, tools/ghidra/specs/cancel-code-recovery.spec
foreach ($s in 'cancel-controls','cancel-controls-2') {
  ./tools/ghidra/sweep.ps1 -Mode Run -ProjectDir work/scratch/ghidra-sweep -ProgramName StarCraft.exe `
      -Script DecompileMany.java -ScriptArgs "work/scratch/028/decomp/index-$s.tsv", "tools/ghidra/specs/$s.spec", 180
}
```

---

### 8.8 The fix (task 066): a phantom ring item for the length of queueLayout, and why the two bit-level fixes were never going to work

§8.6 ends with a defect diagnosed to one mechanism and two candidate designs. Task 066 killed the
first at the price of a disassembly, shipped the second, and this section records both with the
evidence.

#### Option C — "never clear DISABLED" — refuted statically, no run spent

The hope: `disableControl` (`0x00418640`) early-outs when the bit is already set, so a plugin that
writes the icon fields and leaves the flag alone provokes no `dwUser=6` and there is no collision.
061 half-refuted it — the icon's own draw reads the flag byte — but nobody had measured WHICH bit.
Now it is read, not measured, because every link is in the file image:

1. **The draw's TEST masks exactly the DISABLED bit.** `0x00456C30` — the strip-icon blit, called
   only from `0x0045748B`/`0x004574E6` in the strip module (E8 scan over 100% of `.text`):

   ```
   00456C3A  MOV  BL,byte ptr [ESI+0x18]   ; the flag byte
   00456C3D  MOV  EDX,2                    ; the mask -- SC_CTRL_FLAG_DISABLED
   00456C42  TEST DL,BL
   00456C45  MOV  CL,3                     ; colour-remap row 3
   00456C47  JNE  0x456c4f                 ; DISABLED -> row 4
   00456C49  CMP  word ptr [ESI+0x22],DX   ; +0x22 = control TYPE; type 2 keeps row 3
   00456C4D  JZ   0x456c51
   00456C4F  MOV  CL,4
   00456C51  ...  SHL ECX,4 / ADD ECX,0x68C150   ; a 16-byte row -> the blit's colour
   00456C5D  ...                                 ;   buffer at 0x0050CDC1
   ```

   The queue icons are type 2 (read off the live dialog, §8.6), so for them the row is 3 iff
   DISABLED is clear, else 4.

2. **Rows 3 and 4 are different colours — 14 of 16 entries.** The table at `0x0068C150` is loaded
   from `unit\cmdbtns\ticon.pcx` (`0x00459C1E` reads 0x60 bytes of its decoded pixels = six
   16-byte rows; extracted from StarDat.mpq with a DCL-implode decoder,
   `work/scratch/066/`, gitignored — hard rule 1). row3 vs row4: **14/16 differ**. And the CARD's
   icon draw (`0x004589A1`: `TEST AL,2` → row 1, `TEST EAX,0x40000000` → row 2, else row 0)
   selects rows 0/1 of the SAME table through the SAME buffer — also 14/16 apart — which is the
   grey-out every disabled command-card button visibly shows. Same table, same mechanism, same
   distance.

So leaving the flag set draws the right art through the disabled palette: the user's *"the 5th
slot is emtpy"* again, in different colours. C is dead. (§8.1's correction matters here twice
over: the bit never gated the CLICK — the strip's hit test reads only VISIBLE — it gates the
COLOURS. 039's clearing of it was never load-bearing for input; it was load-bearing for pixels.)

#### Option A — the phantom bracket — shipped

`queueLayout` (`0x004268D0`, `__stdcall(BinDlg*)`, `RET 4`) re-reads the portrait-unit global
`0x00597248` for every slot and greys exactly the slots whose ring entry is `0xE4` (§8.1). So the
detour on it (prologue `55 8B EC 83 EC 20`, 6 bytes, nothing PC-relative):

1. **pre**: for each display k the plugin holds an item behind, write that item's type into ring
   slot `(head + k) % 5` — saving the previous value, refusing (and counting `phantomDirty`) if
   the slot is unexpectedly non-empty;
2. run the original — which now takes its OCCUPIED branch for those slots: `grp = cmdicons`,
   icon/mode/type, the slot label, and **`enableControl` instead of `disableControl`**;
3. **post**: restore the saved sentinels, before the call returns to the engine.

Everything 039 hand-wrote is deleted — the engine writes all five fields with its own code, so
039's bug class (a hand-written subset of the layout's fields) is structurally gone. No disable
is ever provoked (`enableControl` early-outs once the slot is lit), so no `dwUser=6` exists to
clear a player's PRESSED bit: at input time the slot is byte-for-byte a vanilla occupied slot,
and the engine's own press/activate cycle emits `{0x20, k}`, which sc_prodqueue's §6.4 icon
branch — written by 039, reachable for the first time — serves and refunds.

#### Why the window cannot be observed (the binding constraint on this design)

The ring reads five items for the length of one `queueLayout` call. Two things were named as
readers that must never see it: the client's Train-button gate (task 025 holds the ring at four
precisely so that button stays lit) and the observer thread.

**Engine readers: excluded by construction, on two legs.**

*The structural leg.* The window opens and closes inside one call frame on the thread that runs
`queueLayout`; a reader on that thread cannot interleave with it. A reader on ANY OTHER thread
would race not just this window but the engine's own ring mutations — `productionTick`'s and
`cancelBuildQueueSlot`'s compactions are multi-store and unsynchronised (§2, §4) — and would have
observed torn rings in vanilla. Vanilla is not torn; therefore no such reader exists.

*The per-reader leg*, every toucher of `+0x98`/`+0xA4` from
[`data/production-queue-fields.tsv`](data/production-queue-fields.tsv) (140 rows) classified to
its dispatch root, callers found by exhaustive E8 scan (`work/scratch/066/xrefs.py`, 100% .text):

| reader | functions | what makes it game-thread |
|---|---|---|
| status-pane drawers & helpers | `0x00425600`, `0x004268D0`, `0x00426FF0`, `0x004568F0`, `0x0047B270`, `0x0047B5A0` (callers all in `0x00425xxx`–`0x00427xxx`), the blit `0x00456C30`, the overlay `0x004E9C59` | dispatched from statDisplayDriver `0x004D93F0` / the dialog redraw walk — the exact function this plugin detours; `THREADCHECK qind-driver` prints its tid |
| card button conditions (the Train gate's world) | `0x00428530` (cancel), `0x004283F0`/`0x004287D0` (land/lift-off via `busy` `0x00401500`), `0x00428E60` (train), `0x00401E70` | evaluated by the card layout and click paths under the same UI dispatch (§8.2, §8.3); the click path is the interact chain `THREADCHECK qind-interact` measures |
| command receive | `cmdrecvTrain` `0x004C1C20`, `cmdrecvCancelTrain` `0x004C0100`, client emitters behind `0x0047C9F0` (callers `0x004C7CE3`, `0x004C80D4..53`) | the plugin detours the first two — `THREADCHECK prodq-train` / `prodq-cancel` — and §8.5's traces show ACTIVATE→queueCommand→receive strictly ordered in one stream |
| secondary-order handlers | `productionTick` `0x00468420` (caller `0x004EC1F9`), `0x0045D0D0` (`0x004ECAD2`), `0x0045D500` (`0x004EC5C2`), `0x0045DEA0` (`0x004EC613`), `0x0045E090` (`0x004EC5E5`), `0x00467FD0` (`0x004EC59E`), `0x004E4D00` (`0x004EC5AA`), plus their helpers `0x0045D2E0`, `0x0045D410`, `0x0045DA40`, `0x00467030`, `0x00468280` | every caller is the ONE jump-table dispatcher `FUN_004EC170` — the same dispatcher that calls the detoured `productionTick`; `THREADCHECK prodq-tick` prints its tid |
| queue core | `0x004669B0`, `0x004669E0`, `0x00466A70`, `0x00466B70`, `0x00466E40`, `0x00466E80`, `0x00467250`, `0x00466790` | called only from the rows above (receive, tick family, AI) — `data/production-xrefs.tsv` |
| building AI | `0x00434480` (caller `0x004488D8`), `0x00435DB0`, `0x00438050` (callers `0x0043E6A6`, `0x0043EFA9`) | AI turn processing in the main loop — the same loop whose command processing task 038 measured interleaving with it deterministically |
| unit lifecycle | `0x0049F170` (callers `0x0049F6E3`, `0x0049F93E`), `0x0049FD00`, `0x004A0320` (caller `0x004A070A`), `0x004F6180`, `0x00488BF0` | sim mutators on the unit array — the state every one of the rows above reads unsynchronised |
| replay/command infra | `0x004C4A80` (caller `0x004C4FCA`) | command-apply path, same dispatch as receive |
| **not the CUnit ring at all** | CRT `_qsort`/`___free_lc_time` (ESP-based), `0x004D100A`/`0x004D1071` (winproc-area DWORD struct), `0x004D6930` (DWORD store at `+0xA4` — would smash head+uniqueness+order at once) | the displacement sweep's false positives, listed so nobody re-classifies them |

Stated at its honest strength: the sweep is displacement-shaped and task 034 showed that shape can
miss a handed-pointer access — which is what the structural leg and the live measurement below are
for; the table is corroboration, not the proof.

*The measured leg.* Every hooked game-side site logs `THREADCHECK <site> tid=` once (driver,
layout bracket, interact shim, the three prodqueue detours), the observer logs its own, and the
suite asserts the game-side ids are ONE id with the observer's differing.

**The two genuinely cross-thread readers — this plugin's own observer (`PRODQ`/`PRODQSEL`,
`STATQ`, the `QIND` view) and the test harness — are closed with a seqlock**, because *"a phantom
item in a `PRODQSEL` line"* was named as a harm in its own right: `ScQueueIndRingGen()` is
incremented before the first phantom store and after the last restore (full fence both sides), so
odd = window open and moved = straddled; every observer ring read retries against it and prints
`ringStable=` so a read that never settled is a reported fact, not a silent one.

**And the rule that took two consumers to learn once: a line carrying `ringStable=0` is NOT
CONSUMABLE.** Retries cannot make the flag impossible — an OS preemption inside even a
guarded section of six raw loads straddles every attempt — so the flag is the contract, not a
curiosity. Task 066's first two measurement runs each had one assertion consume a value its own
line had disclaimed (`engineLen=5 ringStable=0`, the phantom read mid-window), once through the
`QIND` reader and once through `PRODQSEL`, which is the house defect class — the instrument said
its reading was untrustworthy and the consumer used it anyway. Every reader (`Get-QInd`,
`Get-ProdQueue`, `Get-ScStatusQueue`) now RE-ASKS a flagged answer with a fresh marker, up to
three times, and only then returns it so the assertion fails with the flag in view. Anyone
adding a reader of these lines inherits that rule, not just the seqlock.

#### What green means now, and the numbers to compare against PR #95

Pre-fix, PR #95 measured the collision DETERMINISTIC: `disableOnOwned` moved exactly once per
click, every click, and 30 of 30 collided clicks failed; the hold sweep read **0 of 18 cancelled
above a 60 ms hold**. That determinism is what makes the flipped regression arm sound: the arm
asserts `phantom` MOVED across the click (the fix was active) and `disableOnOwned` moved by
ZERO (the collision is gone) — a green with the race merely won cannot produce that pair. The
sweep asserts every click cancels at every hold with zero collisions, per duration, against PR
#95's table; the run's own numbers are in task 066's PR.

---

## 9. Reproducing this

```powershell
# once: import + analyse into a persistent project (~3 min)
./tools/ghidra/sweep.ps1 -Mode Prepare -InputPE C:\sc-work\1161-base\StarCraft.exe `
    -ProjectDir work/scratch/025/ghidra -LogFile work/scratch/025/ghidra/import.log

# the struct: every instruction touching the array and the head index
foreach ($d in '0x98','0xA4') {
  ./tools/ghidra/sweep.ps1 -Mode Run -ProjectDir work/scratch/025/ghidra -ProgramName StarCraft.exe `
      -Script FieldSweep.java -ScriptArgs "work/scratch/025/field-$($d -replace '0x').tsv", $d, any
}

# the cap sites: constants AND a companion instruction dump per function
./tools/ghidra/sweep.ps1 -Mode Run -ProjectDir work/scratch/025/ghidra -ProgramName StarCraft.exe `
    -Script ImmediateSweep.java `
    -ScriptArgs work/scratch/025/cap-sites.tsv, tools/ghidra/specs/production-cap-sites.spec, '5+4+e4+6a+2'

# who calls what
./tools/ghidra/sweep.ps1 -Mode Run -ProjectDir work/scratch/025/ghidra -ProgramName StarCraft.exe `
    -Script XrefSweep.java -ScriptArgs work/scratch/025/prod-xrefs.tsv, tools/ghidra/specs/production-emitters.spec

# the decompiles quoted above
foreach ($s in 'functions','callees','module','buttons') {
  ./tools/ghidra/sweep.ps1 -Mode Run -ProjectDir work/scratch/025/ghidra -ProgramName StarCraft.exe `
      -Script DecompileMany.java -ScriptArgs "work/scratch/025/prod-$s.tsv", "tools/ghidra/specs/production-$s.spec", 180
}

# 4.1's correction: hunting the client-side refusal. Each of these came back NEGATIVE, which
# is what the section reports -- no button condition reads the ring, directly or through a
# helper. XrefSweep takes DECIMAL lengths.
#   specs/production-clientgate.spec   the ten helpers that DO read the ring
#   specs/production-errcode.spec      0x0066FF60, the requirement VM's refusal-code global
foreach ($s in 'clientgate','errcode') {
  ./tools/ghidra/sweep.ps1 -Mode Run -ProjectDir work/scratch/025/ghidra -ProgramName StarCraft.exe `
      -Script XrefSweep.java -ScriptArgs "work/scratch/025/$s-xrefs.tsv", "tools/ghidra/specs/production-$s.spec"
}
./tools/ghidra/sweep.ps1 -Mode Run -ProjectDir work/scratch/025/ghidra -ProgramName StarCraft.exe `
    -Script DecompileMany.java `
    -ScriptArgs work/scratch/025/gate.tsv, tools/ghidra/specs/production-gate.spec, 180
```

The positive half of §4.1's correction is not a sweep at all — it is the wire, and the run that
produced it is `tools/plugin/test-production-queue.ps1`, whose step 6 now asserts the command count
directly.

The `.c` and `.body.txt` outputs are whole decompiled functions — derived game content. They stay
under `work/scratch/` (gitignored) and only the findings above are committed (hard rule 1).

The button-table dump in §4.1 came from `work/scratch/025/peek.py`, a nine-line PE-offset reader
over the working copy; the same bytes are visible in Ghidra at `0x005172C0`.

---

## 10. Queueing past five with SEVERAL buildings selected (task 038)

The user, playing the deployed build, 2026-08-11: *"can't queue more than 5 units per building
when multiple buildings are selected"* — and, in the same message, that selecting several
buildings "works nicely", so the selection half was fine.

Two shipped features meet here and neither was wrong on its own: this one (over-cap queueing at
ONE building, §5–§6) and the group fan-out ([`group-production.md`](group-production.md), one
Train press → one Select+Train pair per selected building). The seam between them was §6.2's
selection array, and the failure is a textbook case of a predicate evaluated in the wrong state.

### 10.1 What the wire said, before

`tools/plugin/test-group-queue-over-five.ps1`, three Command Centers boxed, nine presses,
`%SCPLUGIN_PRODQ%=1` and `%SCPLUGIN_PRODFAN%=1` (the deployed configuration), 2026-08-12:

```
5 of 9 presses reached the funnel; 5 were fanned out
  [02:06:15.993] CMD id=0x1F len=3 bytes=[1F 07 00]
  [02:06:16.312] CMD id=0x1F len=3 bytes=[1F 07 00]
  [02:06:16.628] CMD id=0x1F len=3 bytes=[1F 07 00]
  [02:06:16.930] CMD id=0x1F len=3 bytes=[1F 07 00]
  [02:06:17.211] CMD id=0x1F len=3 bytes=[1F 07 00]
                       ... and nothing, for the remaining four presses

unit=0x00623D08 ring=5 overflow=0 logical=5 engine=[0x7,0x7,0x7,0x7,0x7]
unit=0x00623BB8 ring=5 overflow=0 logical=5 engine=[0x7,0x7,0x7,0x7,0x7]
unit=0x00623E58 ring=5 overflow=0 logical=5 engine=[0x7,0x7,0x7,0x7,0x7]
minerals down 750 (15 units), plugin tracking 0 buildings, captured=0
```

That is §4.1's measurement again, exactly: five commands at the press cadence and then silence,
because every ring reached five and the client greys its own button out there. The plugin, whose
entire job is to stop that happening, had held nothing back.

### 10.2 Why — the two selection arrays

The fan-out replays one `Select` + one `Train` per building, which is what lets `cmdrecvTrain`'s
single-unit gate accept at all. So while a fan-out is in flight the **simulation's** selection
holds ONE building at a time, and the **client's** still holds the whole group. The plugin read
the client's list (`activePlayerSelection`, `0x006284B8`), found `[1]` non-null, and concluded
"not a single selected building" for every replayed Train — so `ScProdQueueOnTrain` ran with no
unit, nothing was taken back out of any ring, and all three filled to five.

The two arrays are `CUnit*[12]`, they hold the same thing whenever the player has one building
selected, and **they abut** (`0x006284B8 + 12×4 == 0x006284E8`). The engine's own gate reads the
other one, row `activePlayerId` — its five instructions are quoted in §6.2. That is the whole
defect and the whole fix: one read, moved to the array the engine reads.

### 10.3 What the wire says after

Same suite, same fixture, same nine presses, after the one-line change:

```
9 of 9 presses reached the funnel; 9 were fanned out
  [02:17:40.618] CMD id=0x1F ... through ... [02:17:43.165] CMD id=0x1F     (nine, at the cadence)
  FANOUT start: cmd=0x1F len=3 units=3 (visible 3 + overflow 0) slots=1 -> 3 Select+order pairs   x9

unit=0x00623D08 ring=4 overflow=5 logical=9 engine=[0x7,0x7,0x7,0x7,0xe4]
unit=0x00623BB8 ring=4 overflow=5 logical=9 engine=[0x7,0x7,0x7,0x7,0xe4]
unit=0x00623E58 ring=4 overflow=5 logical=9 engine=[0x7,0x7,0x7,0x7,0xe4]

minerals 3000 -> 1650: 27 units x 50, charged by the ENGINE, once each
PRODQSTATS captured=18 promoted=3 cancelled=1 refunded=0 refusedFull=0 refusedCost=0
           mineralsSpent=0 mineralsRefunded=50 ... trainSeen=30 trainNoUnit=0
```

Nine per building, four of them in the engine's own ring and five with the plugin, three
buildings, 27 units, 1350 minerals — and the plugin still spent nothing of its own (§5.3). The
card's Cancel button was pressed once afterwards with one building selected: logical 9 → 8 and
exactly 50 minerals back, refunded by the plugin because the tail of that queue was its item.

### 10.4 The diagnostic that would have named it

Nothing in the log distinguished "the plugin is holding nothing" from "the plugin was never
asked" — both print zeros — which is why a passing single-building suite and a silent log could
coexist with a feature that did nothing at all for a group. `PRODQ`/`PRODQSTATS` now carry
`trainSeen` / `trainNoUnit` (and the same pair for cancel): the number of times each detour ran,
and how many of those found no single selected building. The counters did not exist during the
broken run above, so the only number measured for them is the fixed one — `trainSeen=30
trainNoUnit=0`, i.e. 27 fanned-out Trains plus the 3 of the single-building step, every one of
which found its building. Under the old reading `trainNoUnit` would have equalled `trainSeen` for
the group burst, and *that* is the line worth having: it separates "the plugin had nothing to
hold" from "the plugin was never handed a building", which AGENTS.md's rule about diagnostics
("no log line appeared" and "the function refused" must not look alike) is exactly about.

### 10.5 One more place with the same reading

`sc_upgrades.cpp`'s own `SoleSelectedUnit` (task 029's upgrade queue) still reads
`activePlayerSelection`. It is not reachable today — no upgrade command is fanned out, and the
client will not offer an upgrade button for a multi-building selection — so it is **latent**, not
a live bug, and it is left alone here rather than changed under a task that cannot re-run that
feature's own suite. It is the same defect the moment anything fans an upgrade command out.

### 10.6 Reproducing

```powershell
./tools/plugin/build.ps1 -Test          # the offline half: the selection read, both arrays disagreeing
./tools/plugin/test-group-queue-over-five.ps1
./tools/plugin/test-production-queue.ps1   # task 025's own suite: the single-building case
```
