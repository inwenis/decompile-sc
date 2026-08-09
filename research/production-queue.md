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

### 4.1 Enqueue — and the cap is on the RECEIVE side, not the client

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

**It does not look at the queue at all.** So the sixth click on a full queue is *not* refused by
the UI — the button stays live, the command goes on the wire, and it dies on the receive side at
`CMP EAX,0x5` inside `addToBuildQueue`, which returns 0 without touching the array or the player's
resources. The whole cap is that one comparison, in one place.

That is the single most useful fact in this document, because it means a plugin can see the
over-cap intent **at the moment the engine drops it**, with the real queue state in front of it —
no client-side prediction, no guessing whether a slot will still be free a turn later.

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

* the engine keeps its five, unchanged, and keeps deciding everything about them;
* the plugin holds the tail of the logical queue and hands items over one at a time as slots free.

What makes it cheap here, and what §4.1 is for: the engine **already** processes an over-cap Train
command and **already** drops it in one identifiable place, so the plugin does not have to predict,
suppress or synthesise anything on the client side. It watches `cmdrecvTrain`, and when the queue
was full before the engine ran it knows — with certainty, not inference — that the engine did
nothing and the item is free to take.

### 5.3 The resource hazard, and how it is answered

The three failure modes the task named, and the rule that removes each:

| hazard | answer |
|---|---|
| an item paid for **twice** | Payment is attached to **acceptance**, never to promotion. An item the engine accepts is paid for by the engine (§4.2); an item the plugin accepts is paid for by the plugin, out of the same two tables; **promotion moves no money at all** — it is a bare `buildQueue[slot] = type` store. There is no path on which both parties pay. |
| a **wrong refund** on cancel | The plugin refunds with `mineralCost[type] + gasCost[type]` from tables `0x00663888` / `0x0065FD00`, gated on flag byte `0x00664080`, which is instruction-for-instruction what `refundByType` (`0x0042CEC0`) does. Spend and refund inside the plugin are the same two table reads with opposite signs, so they cancel exactly. A cancel that names an engine slot is passed straight through and the engine refunds it as always. |
| the **UI disagreeing** with reality | The engine's five slots always hold five real, engine-owned items, so the five icons the status area draws stay *true* — they are the next five things this building will build, in order. They are no longer *complete*: items 6..N are not drawn. That is a known, stated limitation (§7), not a discrepancy — nothing on screen claims something false. |

Two more, that the task did not name but the code does:

* **Negative resources.** The receive side checks affordability only when the free slot is the
  head slot (`setPendingCost` calls `FUN_0042CF70` only for `isHeadSlot`), and the Train button
  does no cost check at all (§4.1) — so vanilla is already relying on the queue being short. The
  plugin therefore does its own check before accepting, and refuses (logging `refuse-cost`) rather
  than letting a balance go below zero.
* **A building that dies holding paid-for items.** Vanilla refunds its five (§4.4). The plugin
  refunds its overflow, on the same event.

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
* It costs 22 bytes per tracked building, so the number is not a memory decision.

---

## 6. What the plugin does

`tools/plugin/src/sc_prodqueue.{h,cpp}`. Off unless `%SCPLUGIN_PRODQ%=1`, and ignored outright in
`-Mode observe`, which stays the whole plugin's read-only off switch.

### 6.1 Three detours, all on the receive side

| target | address | patch | why there |
|---|---|---|---|
| `cmdrecvTrain` | `0x004C1C20` | 11 B / 4 instrs, `56 57 8B F8 C6 05 B6 84 62 00 00` | brackets the engine's own handling, so "the queue was full before it ran" is sampled rather than inferred |
| `cmdrecvCancelTrain` | `0x004C0100` | 11 B / 4 instrs, `55 8B EC 57 C6 05 B6 84 62 00 00` | a "cancel the last item" belongs to whoever holds the tail |
| `productionTick` | `0x00468420` | 9 B / 3 instrs, `56 8B F0 8B 86 DC 00 00 00` | the frame a slot frees is the frame the next item takes it |

Prologue bytes are dumped out of the binary and handed to `ScHookInstall`, which refuses to patch
if memory disagrees. No window contains a PC-relative instruction, so all three relocate into a
trampoline unchanged — the absolute `MOV byte ptr [0x006284B6],0` is not PC-relative. All three go
in under one thread suspension and a partial set rolls itself back.

Two of the three take their only argument in `EAX` and no C calling convention says so, so each has
a two-instruction thunk (`pushl %eax; call <C fn>; addl $4,%esp; ret`) — the same technique
`sc_fanout`'s `ScOverflowThunk` uses for `sortOverflowHandler`.

### 6.2 Which building

Both receive handlers reset `selectionIterator` (`0x006284B6`) and then require
`getActivePlayerNextSelection` to yield exactly one unit (§4.1). The plugin applies the same test
without calling into the engine: `activePlayerSelection[0]` non-null and `[1]` null, then the
pointer bounds/stride-validated against the unit array.

### 6.3 Promotion is one store

```c
int slot = FindFreeSlot(unit);            /* the re-implementation of 0x004669B0 */
if (slot < 5) buildQueue[slot] = types[0];
```

Nothing else from `addToBuildQueue` applies: the pending-cost tables it fills are consumed by its
own deduction two instructions later and the plugin is not deducting; the secondary order is
already set, because a queue that has no free slot cannot be idle; and `addToBuildQueue` never
writes the AI mirror arrays of §2.6 either — only the *compaction* paths do, and those still run,
unchanged, on whatever the ring holds. After a promotion the plugin sets `SC_VA_STAT_DIRTY`
(`0x0068C1F8`), the same redraw flag the Train handler's own tail writes.

`FindFreeSlot` is re-implemented rather than called because the engine's version wants its
`CUnit*` in `EDX`, and because the offline test suite has no engine to call. It is thirteen
instructions and it is quoted in §2.2 beside the C.

### 6.4 Cancel

* payload `0xFE` ("cancel the last queued item") **and** the plugin holds overflow for that
  building → the plugin pops its own tail, refunds it, and the engine's handler does not run. The
  last item of the logical queue really is the plugin's, so this is the correct owner.
* payload `0xFE` and the plugin holds nothing → straight through, vanilla.
* payload `0` … `4` (a specific queue icon) → **always** straight through. The engine cancels and
  refunds that slot as usual; the freed slot is filled from overflow on the next tick, so the
  logical queue shortens by exactly one, which is what the player asked for.
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

1. **The status area still draws five icons.** Items 6..N are real, paid for, and will be built,
   but they are not on screen. The plugin's `PRODQ` log line is the read-back oracle instead (and
   is what the in-game test asserts on). Extending the production panel would mean a second dialog
   splice next to task 017's, which is a larger and riskier change than this feature; it is the
   obvious follow-up.
2. **Train (`0x1F`) only.** Unit Morph, Train Fighter and Building Morph keep vanilla's five (§4.5).
3. **A one-frame ordering window.** If a slot frees in the same frame a Train command is processed,
   the engine can take that slot for the new item ahead of an older overflow item. The plugin closes
   the window as far as it can — it promotes at the end of every Train command as well as on every
   tick — so no free slot survives a frame boundary, and no item is ever lost or double-paid; only
   the relative order of two items queued within one frame of each other can differ.
4. **Single-player only**, like everything in this repo (AGENTS.md hard rule 3). The plugin moves a
   player's resources outside the command stream, which is fine for a local simulation and is not
   something to point at any online service.

---

## 8. Reproducing this

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
```

The `.c` and `.body.txt` outputs are whole decompiled functions — derived game content. They stay
under `work/scratch/` (gitignored) and only the findings above are committed (hard rule 1).

The button-table dump in §4.1 came from `work/scratch/025/peek.py`, a nine-line PE-offset reader
over the working copy; the same bytes are visible in Ghidra at `0x005172C0`.
