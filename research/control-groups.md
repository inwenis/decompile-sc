# Control groups in StarCraft.exe 1.16.1 — storage, commands, keys, and a >12 group

*Task 021. Derived from `StarCraft.exe` 1.16.1 (`AD6B58B27B8948845CCFA69BCFCC1B10D6AA7A27A371EE3E61453925288C6A46`)
and `Local.dll` from the same install, by static analysis (Ghidra 12.1.2 headless, the persistent-project
pipeline in `tools/ghidra/`), plus in-process observation and an unattended in-game run.*

The user's words, from their own play session: *"when I select more than 12 units I cannot create a
control group of more than 12 units I would like that to work."*

---

## 0. Verdict up front

1. **The engine's control-group store is `selectionHotkeys` at `0x0057FE60`** — `u32[8][18][12]`,
   6912 bytes, holding `StoredUnit` **tags** (`(uniqueness << 11) | unitIndex`), not `CUnit*`.
   Groups `0..9` are the Ctrl+N groups; `10..17` are the engine's own alt-click recent-selection
   ring. **Exactly seven functions touch it** (§1.2), and none of them is on the save/load path.
2. **Per-group capacity is 12, and it is capped twice over** (§3): the store loop returns after
   writing 12 tags, and its only source — `playersSelections[player]` — is itself 12 slots. So
   Ctrl+1 on 24 units could never have stored more than 12, whatever the player did.
3. **Wire command `0x13` is three bytes**, `[0x13][action][group]`, built at `0x004C07BF`.
   `action` is `0` = ASSIGN, `1` = RECALL, `2` = ADD — read off `CMDRECV_Hotkey`'s own dispatch
   (§2). All three are emitted by the key dispatcher `0x004846E0`, ten sites each.
4. **The keys are ACCELERATORS, not window-proc reads** (§5), and that is a load-bearing finding
   for this repo's test harness: `Ctrl+N` and `Shift+N` resolve through `TranslateAcceleratorA`,
   which reads the calling thread's key-state table — which Windows never updates for **posted**
   messages. A posted `Ctrl+1` was measured producing **no command at all**. Plain `N` is not an
   accelerator and posts fine.
   **Shift+N is the add-to-group key** — that answers the question the design left open.
5. **Vanilla control groups are memory-only.** No save/load function references the array (§6), and
   both resets (`0x004965A0`, `0x004EEC30`) zero it wholesale. A savegame does not carry them.
6. **The fix is plugin-side shadow groups** (§7): ten groups mirroring the engine's ten, stored and
   restored inside the `queueCommand` hook the fan-out already has. It adds **no hook**, patches
   **no game code**, and writes **no byte** of the engine's own selection or control-group storage.
   36 units stored and 36 recalled, in game, with the order that follows reaching all 36 (§8).

---

## 1. The storage

### 1.1 Shape, re-derived here

`binary-selection-map.md` §3.5 established `[8][18][12] × 4B` from the 1728-dword `REP STOSD` and the
864/48 strides. This task confirms it a third way, from the **store's own row arithmetic** inside
`hotkeySaveOrAdd` (`0x004965D0`):

```c
local_c = (in_EAX & 0xff) + DAT_0051267c * 0x12;      /* group + activePlayerId * 18 */
local_8 = &DAT_0057fe60 + local_c * 0xc;              /* dword arithmetic: * 12 dwords */
```

`* 0x12` is the per-player group count (18) and `* 0xc` the per-group slot count (12), in the one
place that has to get both right. The recall (`0x00496940`) and the client-side key handler
(`0x00496B40`) compute the same row identically.

**Groups 10..17 are not spare capacity.** `CMDRECV_Select` picks an LRU slot and does `ADD AL,0xa`
before saving (`binary-selection-map.md` §5.2), and the recall's own tail does the same:
`if (9 < group) { stamp recent time } else { slot = LRU(); hotkeySaveOrAdd(1); stamp }`. Those eight
rows are the engine's alt-click history. This task mirrors `0..9` only.

### 1.2 Every function that touches it — seven, and no more

Committed table: [`data/hotkey-xrefs.tsv`](data/hotkey-xrefs.tsv) (the same two-pass sweep
`binary-selection-map.md` §1.1 describes, over `tools/ghidra/specs/hotkey-globals.spec`).

| Function | Refs | What it is |
|---|---|---|
| `0x004965A0` `hotkeyClear` | 3 | `REP STOSD` 1728 dwords over the array, then 32 dwords over `recentSelectionTimes` (`0x0063FE40`), then `lastHotkeyGroupId := 0xFF` |
| `0x004965D0` `hotkeySaveOrAdd` | 21 | the store — both ASSIGN and ADD (§3) |
| `0x004967E0` `hotkeyDoubleTapCentre` | 16 | 500 ms double-tap-to-centre |
| `0x00496940` `hotkeyRecallRecv` | 17 | the receive-side recall — writes `playersSelections` (§4.2) |
| `0x00496B40` `hotkeyKeyHandler` | 5 | the client-side recall — writes `activePlayerSelection` (§4.1) |
| `0x00496D30` `selectSingleUnitFromID` | 1 | a mid-array walk base (`ADD EDI,0x5801C4`) |
| `0x004EEC30` `gameStartHotkeyClear` | 3 | the game-start reset |

**41 instructions across 7 functions**, which reproduces `binary-selection-map.md` §2.1's count for
this array exactly. Entry points were validated first
([`data/hotkey-funcprobe.tsv`](data/hotkey-funcprobe.tsv)): 18 rows, of which the **15 function
labels all resolve `ENTRY-POINT`** and the **3 `in-` rows resolve `INSIDE-FUNCTION` by design** —
those are instruction addresses seeded deliberately, so the probe would name the containing function
instead of this task guessing one. That is how `0x004965A0`, `0x00496D30` and `0x004EEC30` were
identified, and they are in the spec as their own labels afterwards.

The two `.rdata` hits at `0x00500A9E`/`0x00500AC2` are the byte coincidence
`binary-selection-map.md` §2.3 note 2 already identified (a virtual-key table whose bytes read as
`0x00580002`); this sweep also finds the same coincidence in `.data` at `0x0050D8D2` and
`0x0050DD4A`. None is a reference.

---

## 2. The wire command, and its three actions

`CMDACT_HotkeyUnit` (`0x004C07B0`) builds it. The buffer is three bytes and the group arrives in
**BL**, not on the stack — a mixed convention worth stating, because the decompiler shows only two
stack arguments:

```
004C07B4  MOV AL,byte ptr [EBP + 0x8]      ; arg1 = action
004C07B7  MOV EDX,0x3                      ; length
004C07BC  LEA ECX,[EBP + -0x4]             ; buffer
004C07BF  MOV byte ptr [EBP + -0x4],0x13   ; id
004C07C3  MOV byte ptr [EBP + -0x3],AL     ; action
004C07C6  MOV byte ptr [EBP + -0x2],BL     ; group   <-- register argument
004C07C9  CALL 0x00485bd0                  ; queueCommand
```

`CMDRECV_Hotkey` (`0x004C2870`, 19 instructions) is the whole of the receive-side dispatch:

```c
if (cmd[2] < 0x13) {                       /* group guard */
    if      (cmd[1] == 0) hotkeySaveOrAdd(1);        /* ASSIGN */
    else if (cmd[1] == 1) hotkeyRecallRecv(cmd[2]);  /* RECALL */
    else if (cmd[1] == 2) hotkeySaveOrAdd(0);        /* ADD    */
}
```

Note the argument **inversion**: wire action `0` (assign) calls the helper with `1`, and wire action
`2` (add) calls it with `0`. It is easy to read backwards, and reading it backwards would make a
plugin store into the wrong branch, so it is spelled out here.

**The vanilla off-by-one is still there.** The guard is `CMP AL,0x12 / JA` — unsigned, so slots
`0..18` pass while the array has `0..17`. `binary-selection-map.md` §6.4 flagged it as
`[unverified consequence]`; this task did not change that status and **does not touch the guard**.
The plugin's own group handling refuses anything outside `0..9` and hands it to the engine untouched,
so nothing here widens the exposure.

---

## 3. The store — where the 12 comes from

`hotkeySaveOrAdd` (`0x004965D0`), called with `1` for ASSIGN and `0` for ADD.

**ASSIGN** clears the group's twelve dwords first (`for (i = 0xc; i; i--) *p++ = 0;`) and starts
filling at index 0. **ADD** instead scans for the first free slot — a 6-way-unrolled loop bounded by
12, the same idiom the shift-click compaction uses (`binary-selection-map.md` §6.5) — and dedupes
each candidate against what is already there.

Then both share one fill loop, and this is the cap:

```c
piVar1 = &playersSelections[activePlayerId * 12];
do {
    unit = *piVar1;
    if (unit == 0) return;                                   /* densely packed: first NULL ends it */
    if (unit->playerId != ACTIVE_NATION_ID) return;          /* 0x00512678 */
    index = (unit - 0x59cca8) / 0x150 + 1;
    if (index < 0x6a5 && (tag = (unit[0xa5] << 11) | index) != 0) {
        ...
        selectionHotkeys[row * 12 + n] = tag;
        if (0xb < ++n) return;                               /* <-- TWELVE TAGS, HARD */
    }
    if (0xb < ++i) return;                                   /* <-- TWELVE SOURCE SLOTS, HARD */
} while (true);
```

**Two independent 12s.** Even if the group could hold more, the source could not: the store reads
`playersSelections[player]`, which the engine has already truncated. That is why the answer cannot
be "make the group bigger" alone, and it is the reason the plugin stores from its **own** shadow
list instead (§7).

Three player-id globals are in play in this one function — `0x0051267C` indexes the group row,
`0x00512678` is the ownership test — which is exactly the trap `binary-selection-map.md` §7 note 7
warns about. The plugin reads the row with `0x0051267C` (the one the store indexes with) and logs a
warning if the three ever disagree.

---

## 4. The recall — and the seam that makes this task possible

There are **two** recall functions, and they run at different times on different state.

### 4.1 Client side — `hotkeyKeyHandler` `0x00496B40`

Runs the instant the key is pressed. It reads `selectionHotkeys[0x00512688][group]`, validates every
entry, builds a 12-slot stack list, and then:

```c
FUN_0049ae40(count);          /* CreateNewUnitSelectionsFromList -> activePlayerSelection */
FUN_0048f910(lastUnit);       /* selection sound */
DAT_0059723c = 1;             /* client_selection_changed */
DAT_0068c1f8 = 1;             /* stat-screen dirty ... */
FUN_004c07b0(1, list, count); /* CMDACT_HotkeyUnit(RECALL) -> queueCommand */
```

**`0x0049AE40` runs BEFORE the command is queued.** That is the whole seam. `0x0049AE40` clears
`activePlayerSelection` (`0x006284B8`) calling `0x004E6290` per unit, then fills it densely from the
caller's list calling `0x004E6180(slot)` per unit — which is where the engine sets sprite flag `0x08`
and `CSprite::selectionIndex` for its own twelve. So at the moment the plugin's `queueCommand` hook
sees `13 01 g`, `activePlayerSelection` **already holds the post-recall units**.

That is a claim about runtime, not about code, so it is asserted in game rather than assumed —
§8.2.

It also settles a loose end: `sc_addresses.h` says `0x0049AE40` has "10 callers, covering the drag
box, every click path, and control-group recall". The caller list
(`work/scratch/ghidra-021/*.callers`) confirms it, and names *which* recall — `0x00496CA6` inside
`0x00496B40`, the **client-side** one. The receive-side recall below does **not** call it.

### 4.2 Receive side — `hotkeyRecallRecv` `0x00496940`

Runs when the command executes, a few frames later, on the simulation's state. It counts the group's
live entries (6-way unrolled, ≤12), and if there are any:

1. calls `clearPlayerSelection` (`0x0049A740`) — wipes `playersSelections[player]`;
2. per entry, validates: the unit table slot at `0x0059CB58 + index * 0x150` is non-null, the sprite
   exists, `CUnit+0xA5 == tag >> 11`, `CUnit+0x4C == ACTIVE_NATION_ID`, `sprite->flags & 0x20`
   (*Hidden*) is clear, and `unit_IsStandardAndMovable` (`0x0047B770`);
3. **compacts the stored group in place** on a failure — swap-with-last, then zero the vacated slot,
   so a group self-heals as its units die;
4. writes each survivor to `playersSelections[player][slot]`, `slot < 12`;
5. for a group `> 9` stamps `recentSelectionTimes`; otherwise picks the LRU recent slot
   (`0x00496560`) and re-saves the selection into it.

**It never calls `CMDACT_Select`.** That is why the fan-out's shadow list went stale across a recall,
and why the pre-021 plugin dropped the list on seeing `0x13` — a deliberate, correct decision at the
time, and the direct cause of the user's symptom.

---

## 5. The keys are accelerators — and what that costs a test harness

Tool: `tools/parse_accelerators.py`. Committed table:
[`data/accelerators.tsv`](data/accelerators.tsv) (98 entries, both modules).

The message pump `0x004D1BF0` is explicit:

```c
if (((hAccel == 0) || (hwnd == 0) ||
     (TranslateAcceleratorA(hwnd, hAccel, &msg) == 0)) &&
    (DispatchMessageA(&msg), ...)) { TranslateMessage(&msg); }
```

`TranslateAcceleratorA` runs **first**, and the message only reaches the window procedure when it
returns 0. The table is built by `0x004D3070` from the binaries' own resources
(`LoadAcceleratorsA` ids `0x65`/`0x66`/`0x67`/`0x71`, merged via
`CopyAcceleratorTableA`/`CreateAcceleratorTableA`), and the control-group entries are:

| combination | module, resource | command ids | meaning |
|---|---|---|---|
| **Ctrl+0..9** | `Local.dll` `0x65`/`0x66` | `0x9BE6`, `0x9BDD`..`0x9BE5` | ASSIGN (`13 00 g`) |
| **Shift+0..9** | `StarCraft.exe` `0x71` | `0x9BDC`, `0x9BD3`..`0x9BDB` | ADD (`13 02 g`) |
| **Alt+0..9** | `Local.dll` `0x65`/`0x66` | `0x9BFA`, `0x9BF1`..`0x9BF9` | the recent-selection ring |
| plain `0..9` | **not accelerators** | — | RECALL (`13 01 g`), via the window proc |

**Shift+N is the add-to-group key.** The design note said the engine supported action `2` while the
key combination was unknown; this is the answer, and §8.1 exercises it in game.

The command id is what the game's own key dispatcher `0x004846E0` switches on
(`MOVSX EDI,word ptr [ECX + 0x8]`, `LEA EAX,[EDI + 0x642D]`, bounds `0xAE`, jump table at
`0x00484B64` indexed through the byte table at `0x00484C04`). `0x642D` is 25645, and Shift+1's id is
`-25645`, so Shift+1 is jump-table index 0 — the arithmetic closes.

Within that dispatcher, the three families are ten sites each:

| family | shape | action |
|---|---|---|
| assign | shared tail at `0x004849EB`; `[EBP-3] = BL`, and `BL` is 0 from `XOR EBX,EBX` at `0x004846EA` | `13 00 g` |
| add | ten inline blocks, `0x004848A2` and siblings, `MOV byte ptr [EBP-3],0x2` | `13 02 g` |
| recall | `MOV CL,g` / `CALL 0x004967E0` / `PUSH g` / `CALL 0x00496B40` | `13 01 g` |

### 5.1 Why a posted `Ctrl+1` does nothing — measured, then explained

`tools/plugin/drive-game.ps1` drives the game with **posted** Win32 messages. Windows does not update
a thread's key-state table for posted keyboard messages, and `TranslateAcceleratorA` resolves
`FCONTROL`/`FSHIFT`/`FALT` from exactly that table. So a modified accelerator can never match.

Measured before it was explained: a run that posted `WM_KEYDOWN VK_CONTROL` + `WM_KEYDOWN '1'` +
their ups, on a live 8-unit selection, produced **zero** `0x13` commands
(`work/scratch/021-probe.log`).

`GetKeyState` is imported and *is* called on the input path — but only once, and for
`VK_MENU`:

```
004D218A  PUSH 0x12                       ; VK_MENU
004D218C  CALL dword ptr [0x004fe2c0]     ; GetKeyState
```

Everything else the window proc tracks it does from the messages themselves, into its own
`keyDown[256]` table at `0x00596A18` (`MOV byte ptr [ESI + 0x596a18],BL`, cleared 64 dwords at a time
by `0x004D1BF0`). So the obstacle is not the game's own bookkeeping — it is `TranslateAcceleratorA`,
which runs before the window proc ever sees the key.

### 5.2 How the test drives it anyway, and what that does NOT cover

What an accelerator *does* on a match is send `WM_COMMAND` carrying its id, and the window proc's
`case 0x111` puts that id straight into the same dispatcher and reads nothing else from the event:

```c
case 0x111:
    if (DAT_005968e0 != NULL) {            /* = 0x004846E0 */
        local_10 = 0x10;
        local_14 = (ushort)wParam;         /* the command id, at event + 8 */
        (*DAT_005968e0)();
    }
    return 1;
```

The dispatcher's *only* read of that event is `word ptr [ECX + 0x8]` — verified against its full
instruction listing, not inferred. And the engine posts exactly such a message to itself at
`0x004D1BA0` (`PostMessageA(hwnd, 0x111, 0xffff9c6b, 0)`), which is the precedent.

So `Send-ScCommand` / `Send-ScControlGroupAssign` in `drive-game.ps1` post `WM_COMMAND` with the
accelerator's own id. **The limit, stated rather than buried: the keyboard-to-accelerator mapping is
the one layer the automated test does not exercise.** Everything from the command id onwards — the
dispatcher, the 3-byte command, both recall paths, the store, and the plugin hook — is the engine's
own code on its own path. Recall needs none of this: plain digits are not accelerators, so `1` is an
ordinary posted keystroke.

---

## 6. Save/load: control groups are memory-only, in vanilla too

`binary-selection-map.md` §4 identified the save/load block I/O by its `saveload.cpp`/`compress.cpp`
debug strings and showed `playersSelections` (384 bytes) being written and read there.
**`selectionHotkeys` is not.** None of `0x004C2910`, `0x004D02D0`, `0x004CFEF0`, `0x004C2D1D`,
`0x004D0139` or `0x004D0688` appears in the seven-function list of §1.2, and the array's 6912-byte
extent occurs nowhere as an immediate (`binary-selection-map.md` §4 already reported `0x1B00` as a
zero-occurrence value).

Both writers that touch the whole array zero it: `0x004965A0` and `0x004EEC30`. So a load does not
restore control groups — it starts from empty.

That shapes the plugin's staleness answer (§7.3): the exposure is not "a savegame carries stale
groups", it is "a *new game in the same process* leaves the plugin's groups describing units that no
longer exist while the engine's own groups are empty".

---

## 7. The fix — plugin-side shadow groups

`tools/plugin/src/sc_fanout.cpp`, the SHADOW CONTROL GROUPS block.

### 7.1 Why not widen the engine's array

Rejected on evidence, not on cost:

- there is only ~1 KB of unclaimed space behind the array and doubling it needs 6912 more
  (`binary-selection-map.md` §3.5), and "unreferenced" is not "free" there anyway;
- the store, recall and centre paths are **hand-unrolled 6-way with the 12 baked into the unroll**
  (§3, §4.2) — the code is not bounds-driven;
- `binary-selection-map.md` §2.2 lists **6 encoded `×12` row strides** for this array that no address
  or constant sweep can see, each of which would have to change;
- and even a wider group would still be filled from a 12-slot `playersSelections` (§3).

### 7.2 What it does

Ten plugin groups mirroring the engine's ten, holding the same
`(CUnit*, CUnit+0xA5, CUnit+0x4C)` triple the shadow list already uses. All of it lands inside the
`queueCommand` hook the fan-out already installs, so the feature **adds no hook and patches no game
code**:

| the player does | the engine emits | the plugin does |
|---|---|---|
| Ctrl+N | `13 00 g` | snapshot the whole shadow list into group `g` (liveness-gated on the way in) |
| Shift+N | `13 02 g` | union the shadow list into group `g`, deduplicated |
| press N | `13 01 g` | read the engine's post-recall `activePlayerSelection`, rebuild the shadow list as *(group − visible)* + *visible*, re-attach circles, drop any pending fan-out plan |

The shadow list keeps its module invariant — **overflow first, the engine's visible units last** — so
the final `Select`+order pair of the next fanned order still leaves the simulation holding exactly
what the player can see.

**Where units 13..N live: plugin memory, and nowhere else.** They are never written into
`selectionHotkeys`, `playersSelections` or `activePlayerSelection`. That is what keeps this clear of
the `selectionIndex` hazard: all four readers of `CSprite+0x0B` are gated on sprite flag `0x08`
(`selection-circles.md` §4), the engine sets `0x08` itself inside `0x004E6180` for exactly the units
it puts in `activePlayerSelection`, and units 13..N are never in that array. The plugin's circles keep
setting flag `0x01` alone, as task 014 established. A recalled over-cap unit reaches the simulation
only the way it already did — as a wire tag in a `Select(≤12)` emitted by the fan-out.

**A recall emits nothing of its own.** It rebuilds a plugin-side list; the replayed `Select`s happen
only when the player next issues a fanned order, exactly as before this task. (Asserted in
`hooktest` part [11]: `a recall emits no Select of its own`. This matters for task 022, which is
investigating whether replayed `Select`s interrupt in-progress orders — recall does not add a new
burst of them.)

### 7.3 Staleness: three gates, and what each one is actually worth

Stated per gate, because they are **not** all the same strength and an earlier version of this
section implied they were.

1. **Liveness — structural.** Every entry is re-run through task 020's five-term gate
   ([`fanout-liveness.md`](fanout-liveness.md) §3) at recall, and again on the way in at store time.
   A dead, removed, changed-hands or recycled unit is dropped, not resurrected.

   Its one probabilistic term is uniqueness: `CUnit+0xA5` is a **5-bit counter** — the re-init at
   `0x004A0320` writes `(previous + 1) & 0x1F` — so a record whose slot has been re-used passes the
   uniqueness test whenever the number of re-inits of that slot is a multiple of 32. The other four
   terms (hitpoints, owner, sprite, player-list reachability) are absolute, and a *live* unit sitting
   in a recycled slot passes all four. So term 1 alone is 31/32 per unit, not certainty. That is why
   gate 2 exists and why it compares the pair.

2. **Containment — structural, and it compares (pointer, uniqueness), not the pointer.** The engine's
   own post-recall list must be a subset of the plugin group. Store and add maintain that by
   construction — we store a superset of what the engine stores, and the engine's recall can only
   ever *drop* entries (§4.2 step 3) — so a violation *means* the group does not describe this
   selection, and the plugin discards it and falls back to pre-021 behaviour (shadow = the engine's
   twelve) rather than guessing.

   The pair matters: a `CUnit*` is a slot in a fixed 1700-entry global the engine reuses game after
   game, so comparing bare pointers would let a stale record whose slot now holds a *different* live
   unit read as contained — passing on exactly the input this gate exists to catch. Review found the
   first version doing precisely that; `hooktest` part [11] now recycles the uniqueness bytes of the
   recalled slots and asserts the group is discarded.

3. **New game in the same process — an ADD into an empty engine row is an ASSIGN.** `0x004EEC30`
   zeroes the engine's groups at game start while the plugin's survive. *Recall* is already covered
   (an empty engine group makes `0x00496B40` return before it queues anything, so the plugin's recall
   path never runs; a non-empty one is covered by gate 2). **ADD** is the exposed one, and the rule
   is a mirror of the engine rather than a guess about the player: `hotkeySaveOrAdd`'s ADD branch
   scans for the first free slot, so on an empty row it starts at index 0 — in the engine, an add
   into an empty group already *is* an assign. The plugin does the same.

   **The first version of this got it wrong, and the review caught it.** It tried to be cleverer —
   "the row is empty now AND I have previously observed it non-empty" — to avoid resetting on the
   legitimate *Ctrl+N then shift-add before the assign has executed* sequence. But the store is
   receive-side, so on a **first** Ctrl+N the row is always still empty at that instant and the
   observation was never recorded: a group assigned once and not touched again was **permanently
   immune to the reset**. Assign a group, start a new mission, shift-add into it, and the new units
   were unioned into the previous game's records — after which gate 2 was being maintained against a
   poisoned baseline. That is ordinary play. The rule above has no memory to get wrong, and
   `hooktest` part [11] carries the sequence with no extra command in it (the case the old test could
   not see, because it issued one).

   **What it costs**, stated because it is a real behaviour difference: if the player queues Ctrl+N
   and a shift-add in the *same turn* and changes the selection between them, the engine ends up with
   `sel1 ∪ sel2` while the plugin keeps only `sel2`. Nothing is corrupted — the next recall's
   containment check sees the engine hand back units the group does not hold, discards it and falls
   back to the engine's twelve. A lost >12 group in a two-commands-in-one-turn case, not a wrong one.

**One asymmetry worth knowing**, since it can cost a group with nothing wrong: `GroupStore` gates
units on the way IN, and the engine's own store does not. A unit skipped at assign time for
`hitpoints == 0` can still be stored by the engine (its store checks owner and the tag encoding, not
hit points) and handed back by its recall — where it reads as foreign to gate 2, and the whole group
is discarded rather than partly used. Narrow (it needs a unit that is dead-but-not-yet-removed at the
exact moment of the Ctrl+N) and it fails safe, but it is a real path from "one unlucky unit" to "the
player loses the group".

A `0x13` the plugin does not understand — wrong length, a group outside `0..9`, an action
`CMDRECV_Hotkey` does not dispatch — falls back to exactly the pre-021 behaviour: drop the over-cap
part of the shadow list rather than fan out against a selection the engine rebuilt elsewhere.

---

## 8. What was tested

### 8.1 In game — `tools/plugin/test-control-groups.ps1`

36 Lurkers on a generated Use-Map-Settings map (no triggers, no enemies, one unit-less computer
slot), boxed as one selection. Unattended; the oracle is in-process state, never the picture.
Green on 2026-08-09:

| step | asserted |
|---|---|
| box | `n=36 visible=12 overflow=24`, all type `0x67` |
| **Ctrl+1** | the engine emitted `13 00 01`; the plugin stored **36**, not 12 |
| clear | the boxed 36 are gone (`n≤1`, nothing live selected) |
| **press 1** | the engine emitted `13 01 01`; **all 36 back**, `visible=12`, 24 restored past the cap, 0 dropped; no group discarded |
| ordering | `activePlayerSelection` already held the **post**-recall twelve at hook time, 12 distinct tags — §4.1's claim, checked at runtime |
| HUD row | `HUDROW show n=36 page=1/3` — the row pages a recall exactly as it pages a box (task 017 not regressed) |
| circles | `CIRCLES show: 24/24` — one per over-cap unit (task 014 not regressed) |
| order after recall | Burrow fanned to **36 of 36**, `burrowed 0/36 → 36/36`, counted from each unit's own `CUnit+0xDC` bit `0x10` |
| **Shift+1** | emitted `13 02 01`; the union of the same selection deduplicates to 36, not 72 |
| recall over a live >12 selection | still exactly 36, still `visible=12`, units still burrowed |
| policy | only `0x2C` was ever fanned out; `0x13` never was |
| binary | `StarCraft.exe` SHA-256 unchanged, still pristine; no process left behind |

### 8.2 Offline, byte-exact — `hooktest.exe` part [11]

No StarCraft in the process: a fake 3 MB module image, units synthesised at the real 336-byte stride,
and both engine reads the feature makes (`activePlayerSelection`, `selectionHotkeys`) faked inside it.
Every emitted byte is asserted on the wire.

| case | asserted |
|---|---|
| store → recall | group holds 36; recall restores 36 with `visible=12`; the following order emits **3 pairs, 36 tags**, chunked overflow-first with the **visible chunk last** |
| a recall emits nothing itself | `0` commands queued by the recall; the engine's own `0x13` is not suppressed |
| **death** | a unit past the cap killed by damage (`hitpoints := 0`, uniqueness verified *unchanged* first): 35 come back, the group compacts to 35, and **the corpse's tag is in no emitted `Select`** |
| **removal** | a unit unlinked from `playerUnitList` (HP and uniqueness verified untouched): 35 come back |
| containment | a group whose units the engine did not recall is discarded; the shadow list falls back to the engine's twelve; the poisoned group is forgotten |
| new game | the engine's rows zeroed under us → a shift-add into an empty row behaves as an assign and the stale group is dropped |
| **new game after a group used exactly ONCE** | the sequence the first implementation got wrong (§7.3 gate 3): assign, never touch the group again, new mission, shift-add. Asserted with **no** extra command in it, which is what the version that shipped broken could not see |
| **recycled slots** | the engine recalls the same pointers with new uniqueness bytes → not contained → group discarded. Bare-pointer containment passed this |
| shift-add | a second overlapping selection unions to 32, not 40 |
| unknown `0x13` | group 12 (the engine's own recent ring) and a wrong-length command both fall back to pre-021 behaviour |
| already-dead unit | never enters a group at store time |

**Both cases added after review were confirmed capable of failing**, by reverting each fix and
re-running: with the ADD-into-empty-row rule disabled the new-game case reports the group holding
**41** units (36 from the previous game unioned with 5 fresh ones — the exact defect), and with
containment back on bare pointers the recycled-slots case reports a shadow list of **36**, i.e. the
previous game's units handed to the player. An assertion that cannot fail is not evidence, and this
part had two of them before.

### 8.3 Not regressed

`hooktest` parts [1]–[10] and the in-game suites listed in §9 of the PR/report.

---

## 9. Confidence and method

### Derived here, from these binaries
* The seven functions that touch `selectionHotkeys`, and the absence of save/load among them (§1.2,
  §6) — two-pass sweep, committed table.
* The row arithmetic confirming `[8][18][12]` from the store itself (§1.1).
* The `0x13` byte layout and the action → helper mapping, including the argument inversion (§2).
* Both 12-caps in the store, and that the source array is itself 12 (§3).
* Both recall paths, and the ordering of `0x0049AE40` before `queueCommand` (§4).
* The accelerator tables, the command ids, and that Shift+N is the add key (§5) — parsed from the
  files by `tools/parse_accelerators.py`.
* That `GetKeyState` is called on the input path exactly once, for `VK_MENU` (§5.1).
* That the key dispatcher reads only `[ECX+8]` from its event (§5.2).

### Derived here, from the live game
* A posted `Ctrl+1` produces no command at all (§5.1).
* A posted `WM_COMMAND` with the accelerator's id produces `13 00 01`, and a plain posted `1`
  produces `13 01 01` (§5.2, §8.1).
* `activePlayerSelection` already holds the post-recall twelve when the recall command is queued
  (§8.1) — the design's one runtime assumption, checked rather than assumed.

### Inherited and used as-is
* The `StoredUnit` encoding, the unit array base `0x0059CCA8`/`0x0059CB58` and stride `0x150`, the
  `CUnit` field offsets, and the five liveness terms — from `binary-selection-map.md`,
  `command-path.md`, `selection-circles.md` and `fanout-liveness.md`.
* The `0x004E6180`/`0x004E6290` selection-graphics pair and the flag-`0x08` argument, from
  `selection-circles.md` §4.

### Open
* **What `0x00499A10` is.** The receive-side recall calls it with `selectionColorTable[owner]` when
  `0x0049A110` says the view is the active player's. It is plainly selection-graphics-adjacent and
  it is *not* `0x004E65C0` (the call `addUnitToSelectionSlot` makes in the same position). Not
  traced; nothing here depends on it.
* **Whether hotkey slot 18 is reachable** — `binary-selection-map.md` §6.4's off-by-one is
  untouched and still `[unverified consequence]` (§2).
* **Which key the Alt+0..9 accelerators drive.** Their ids sit in the same dispatcher block and the
  engine's recent-selection ring is groups 10..17, which is a strong hint and not a derivation. Not
  traced.
* **The keyboard-to-accelerator layer is unexercised by the automated test** (§5.2), by construction.
  A human pressing Ctrl+1 exercises it; nothing in this repo can.
* **Group `0`.** The plugin mirrors groups `0..9` and the test drives group `1`. Group 0 is the same
  code path with a different index and is not separately exercised in game.
* **The store-side / engine-side gate asymmetry** in §7.3 — a unit skipped at assign time for
  `hitpoints == 0` that the engine stores anyway can cost the whole group at the next recall. Not
  observed; reasoned from the two stores' differing checks.

### Reproducing this

```powershell
# static: import + analyze once, then the queries
./tools/ghidra/sweep.ps1 -Mode Prepare -InputPE C:\sc-work\1161-base\StarCraft.exe `
    -ProjectDir work/scratch/ghidra-021 -LogFile work/scratch/ghidra-021/import.log
./tools/ghidra/sweep.ps1 -Mode Run -ProjectDir work/scratch/ghidra-021 -ProgramName StarCraft.exe `
    -Script DisassembleAt.java -ScriptArgs work/scratch/ghidra-021/recovery.tsv, tools/ghidra/specs/selection-code-recovery.spec
./tools/ghidra/sweep.ps1 -Mode Run -ProjectDir work/scratch/ghidra-021 -ProgramName StarCraft.exe `
    -Script XrefSweep.java -ScriptArgs work/scratch/ghidra-021/hotkey-xrefs.tsv, tools/ghidra/specs/hotkey-globals.spec
./tools/ghidra/sweep.ps1 -Mode Run -ProjectDir work/scratch/ghidra-021 -ProgramName StarCraft.exe `
    -Script FuncProbe.java -ScriptArgs work/scratch/ghidra-021/hotkey-funcprobe.tsv, tools/ghidra/specs/hotkey-functions.spec

# the accelerator tables (working copy only, never the pristine install). Two modules go
# into one file, so the first call writes and the second appends; --module defaults to the
# PE's file name, which is what the committed table's `module` column holds. This
# reproduces research/data/accelerators.tsv byte-identically.
python tools/parse_accelerators.py C:\sc-work\1161-base\StarCraft.exe `
    --tsv research/data/accelerators.tsv --append
python tools/parse_accelerators.py C:\sc-work\1161-base\Local.dll `
    --tsv research/data/accelerators.tsv --append

# offline core tests, then the in-game run
./tools/plugin/build.ps1 -Test
./tools/plugin/test-control-groups.ps1
```

The code-recovery step is not optional: auto-analysis leaves `0x004965A0` as undefined bytes (its
seed `0x004965A8` is row `s19` of `specs/selection-code-recovery.spec`), so a sweep run without it
reports six functions touching the array, not seven.

Ghidra project, decompiled C and listings are derived game content and stay under `work/scratch/`
(gitignored); only the finding tables in `research/data/` are committed.

---

## 10. Revision log

* **2026-08-09 (task 021)** — first version: the storage map, the command and its three actions, both
  recall paths, the accelerator finding and its consequence for the test harness, the save/load
  answer, and the plugin-side shadow groups with their three staleness gates.
