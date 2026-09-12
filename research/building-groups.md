# Selecting buildings as a group — the gate, and what it takes to relax it

Analysis date: 2026-08-09. Target: `StarCraft.exe`, StarCraft: Brood War 1.16.1 (classic),
`C:\sc-work\1161-base\StarCraft.exe`, SHA-256
`AD6B58B27B8948845CCFA69BCFCC1B10D6AA7A27A371EE3E61453925288C6A46` — the same disposable working
copy every other document here analyses, hashed before the run. Tool: Ghidra 12.1.2 headless, the
persistent-project driver `tools/ghidra/sweep.ps1`. The user's playable install was never opened.

The question this answers: **why does a drag box over six Supply Depots select one of them, and
what is the smallest honest change that makes it select all six?**

---

## 1. The answer in one paragraph

One predicate does it: `unit_IsStandardAndMovable` (`0x0047B770`). It is consulted **twice**, once
on each side of the selection path, and the two consultations produce two different symptoms that
are easy to mistake for one. On the client, `SortAllUnits` refuses to put a building in the
selection list at all and then, if that left the list empty, puts **one** of the rejected buildings
back and returns a count of 1. In the simulation, `addUnitToSelectionSlot` refuses a building every
slot but the first, so `playersSelections[player]` — the array every order applier iterates — can
hold exactly one building no matter what arrives on the wire.

Relaxing only the first gets you a selection that looks right and commands one building. Relaxing
only the second gets you nothing, because the client never sends more than one. `selection-cap.md`
§4.1 flagged this function as "the multi-select gate … a likely blocker for buildings" on GPTP's
say-so; §8 q9 asked for its exact predicate and every caller. Both are below, from this binary.

---

## 2. Gate A — the client, `SortAllUnits` (`0x0046F0F0`)

`__stdcall(CUnit** candidates, CUnit** out12, CUnit* clicked) -> u32 count`
(`command-path.md` §3.1). `candidates` is the raw, uncapped, NULL-terminated contents of the drag
box. The loop filters it into `out12`.

### 2.1 The rejection

```
0046F194  CALL 0x0046ed80        ; unit_isUnselectable(unitId) -- type may not be selected AT ALL
0046F19B  JNZ  0x0046f226        ; ... skip it entirely, it is not even a fallback candidate
0046F1A1  MOV  ECX,ESI
0046F1A3  CALL 0x0047b770        ; unit_IsStandardAndMovable(unit)
0046F1AA  JZ   0x0046f223        ; FAILED -> jump PAST the store
0046F1AC  MOV  EAX,[0x006d0f14]
0046F1B3  JNZ  0x0046f223        ; a global that disables multi-select the same way
0046F1B5  MOV  AL,byte ptr [ESI + 0x4c]
0046F1B8  MOV  EDX,dword ptr [0x00512684]
0046F1C3  JNZ  0x0046f223        ; not the active player's unit
...
0046F206  CMP  EAX,0xc           ; the 12-cap (selection-cap.md 4.1)
0046F209  JL   0x0046f217
0046F210  CALL 0x0046f040        ; sortOverflowHandler -- past the cap
0046F217  MOV  ECX,dword ptr [EBP + 0xc]
0046F21A  MOV  dword ptr [ECX + EAX*0x4],ESI    ; out12[n] = unit
0046F21D  INC  EAX
0046F21E  MOV  dword ptr [EBP + -0x4],EAX       ; n = n + 1
```

`0x0046F223` is the branch target all three rejections share:

```
0046F223  MOV  dword ptr [EBP + -0x8],ESI    ; remember THIS unit as the fallback
```

`[EBP-8]` holds **one** unit — the *last* candidate that was a selectable type but failed the
movable/global/owner tests. Every later rejection overwrites it. `[EBP-4]` holds the count of units
actually stored.

### 2.2 The substitution — where "exactly one building" comes from

```
0046F23D  MOV  EDX,dword ptr [EBP + -0x8]   ; the fallback
0046F242  MOV  EAX,dword ptr [EBP + -0x4]   ; the count
0046F247  POP  ESI
0046F248  JNZ  0x0046f286                   ; count != 0 -> return it; the fallback is DISCARDED
0046F24A  TEST EDX,EDX
0046F24C  JNZ  0x0046f264                   ; count == 0 and a fallback exists
...
0046F264  TEST ECX,ECX                      ; ECX = `clicked`
0046F266  JZ   0x0046f27a                   ; nothing was clicked -- the DRAG BOX path
0046F27A  MOV  EAX,EDX
0046F27C  MOV  EDX,dword ptr [EBP + 0xc]
0046F27F  MOV  dword ptr [EDX],EAX          ; out12[0] = the fallback
0046F281  MOV  EAX,0x1                      ; ... and return ONE
```

So, precisely:

| the box contained | what SortAllUnits returns |
|---|---|
| any selectable movable unit | those units (capped at 12); every building is dropped and the fallback discarded |
| buildings only | **one** building — the last one rejected — and a count of 1 |
| nothing selectable | 0 |

That second row is the vanilla behaviour the user asked about, and the third column of the first row
is why a **mixed** box of units and buildings selects only the units: `count != 0` at `0x0046F248`
takes the early exit and the fallback never runs.

### 2.3 Which callers this affects

`SortAllUnits` has three call sites: `0x0046FA40` (the drag-box handler) and `0x0046FB40` twice (the
click handler). **Only `0x0046FA40` passes `clicked = 0`**, and that is checked here from both ends
rather than taken from `command-path.md` §3.3, because the whole scope boundary of §5 rests on it:

* `0x0046FA40` calls `FUN_0046f0f0(candidates, local_34, 0)` — the literal 0 is in its own decompile;
* `0x0046FB40` opens with `iVar3 = FUN_0046f3a0(...)` (`resolveClickedUnit`) and **returns
  immediately if that is 0**. Both of its `FUN_0046f0f0` calls pass that same `iVar3`, so neither
  can reach `SortAllUnits` with a null `clicked`.

The fallback substitution at `0x0046F27A` is reachable only on the drag-box path anyway —
`0x0046F264` sends the `clicked != 0` case to `0x0046F268`, which puts the *clicked* unit in slot 0
instead. So "box" and "click" are separable at this level with no state of our own, and testing
`clicked == 0` is exactly "this is a drag box".

---

## 3. Gate B — the simulation, `addUnitToSelectionSlot` (`0x0049AF80`)

Register convention, off the listing: **ESI = `CUnit*`, EDI = player, EBX = slot**, returns EAX,
`RET` with no stack arguments.

```
0049AF80  TEST ESI,ESI          / JZ  reject      ; unit != NULL
0049AF84  CMP  EDI,0x8          / JGE reject      ; player < 8
0049AF89  CMP  EBX,0xc          / JGE reject      ; slot < 12
0049AF8E  MOV  EAX,dword ptr [ESI + 0xc]
0049AF91  TEST byte ptr [EAX + 0xe],0x20 / JNZ reject   ; sprite not Hidden
0049AF97  TEST EBX,EBX
0049AF99  JLE  0x0049afb5       ; SLOT 0 -> no further test: anything may be selected ALONE
0049AF9D  CALL 0x0047b770       ; slot > 0 -> unit_IsStandardAndMovable
0049AFA4  JZ   0x0049afb2       ; ... failed -> refuse the slot
0049AFA6  MOVZX ECX,byte ptr [ESI + 0x4c]
0049AFAA  CMP  ECX,dword ptr [0x00512678]
0049AFB0  JZ   0x0049afb5       ; ... and it must be the active nation's unit
0049AFB2  XOR  EAX,EAX / RET                       ; refused
0049AFB5  LEA  EDX,[EDI + EDI*0x2]
0049AFBB  MOV  dword ptr [EAX*0x4 + 0x6284e8],ESI  ; playersSelections[player][slot] = unit
```

`binary-selection-map.md` §5.1 already matched this function against GPTP predicate by predicate;
what is new here is **what the slot number is at the call site**. In `CMDRECV_Select`
(`0x004C2750`):

```
004C27FA  CMP  word ptr [ESI + 0x64],0xe    ; not a Terran Nuclear Missile
004C2801  CALL 0x0049af80
004C2806  TEST EAX,EAX
004C2808  MOV  EDI,dword ptr [0x0051267c]   ; EDI = active player, reloaded each iteration
004C280E  JZ   0x004c2811
004C2810  INC  EBX                          ; EBX counts ACCEPTED units -- and IS the slot
```

So the slot is "how many have been accepted so far". The first building on the wire lands in slot 0
and is accepted unconditionally; the second is offered slot 1, fails the predicate, and is refused.
**A Select carrying sixteen buildings leaves the simulation holding one.**

`getActivePlayerNextSelection` (`0x0049A850`), the iterator every order applier drives, reads
`(&DAT_006284e8)[iterator + activePlayer * 0xc]` — `playersSelections`, not the client's list. That
is why gate B, not gate A, is what decides whether an order reaches more than one building.

**`0x0049AF80` is inlined into `CMDRECV_ShiftSelect`** (`binary-selection-map.md` §5.3), so a detour
on it would not cover the shift-add receive path even if one were installed.

---

## 4. The predicate itself — `selection-cap.md` §8 q9, answered

```c
undefined4 FUN_0047b770(void)      /* ECX = CUnit* */
{
  ushort id = *(ushort *)(in_ECX + 0x64);
  if (((unitsDatFlags[id] & 1) == 0) &&            /* units.dat BUILDING          */
      ((unitsDatFlags[id] & 0x800) == 0) &&        /* units.dat "single entity"   */
      ((*(uint *)(in_ECX + 0xdc) & 0x400) == 0) && /* a CUnit flag                */
      (*(char *)(in_ECX + 0x117) == '\0') &&
      (*(char *)(in_ECX + 0x119) == '\0') &&
      (*(char *)(in_ECX + 0x124) == '\0') &&
      ((id < 0xcb) || (0xd5 < id)) &&              /* 203..213: map-revealer etc. */
      (id != 0xd)  && (id != 0x24) && (id != 0x59) && (id != 0x5a) &&
      (id != 0x5d) && (id != 0x5e) && (id != 0x5f) && (id != 0x60) &&
      (id != 0xca) && (id != 0x69))
    return 1;
  return 0;
}
```

Two of those terms are per-TYPE (the units.dat flags and the id list) and four are per-UNIT
(`+0xDC`, `+0x117`, `+0x119`, `+0x124`). That split matters for anything that wants to reason "same
type ⇒ same verdict": it is true for the type terms and **not** guaranteed for the unit terms, which
is why the implementation asks the predicate about every candidate rather than about the type once.

`unitsDatFlags` is the table at **`0x00664080`**, indexed by the type id at 4 bytes per entry. Both
selection functions index it the same way — `TEST byte ptr [ECX*0x4 + 0x664080],0x10` at
`0x0046F138` (the subunit flag, which makes `SortAllUnits` follow `CUnit+0x70` to the parent) and
`DAT_00664080 + id*4` inside `0x0047B770` itself. **That it is the units.dat flags table, and that
bit `0x01` is what refuses a building, is checked at RUNTIME rather than inherited**: the plugin
logs the flags dword for the type it grouped (`BGROUP box: … flags=0x…`) and
`test-building-groups.ps1` asserts bit `0x01` is set in it for a Missile Turret, from inside the
live process.

The neighbouring predicate `unit_isUnselectable` (`0x0046ED80`) is a plain switch on the type id
returning 1 for `0x0E`, `0x55`, `0x69`, `0xCA`, `0xCD`, `0xCE`, `0xCF`, `0xD0` — those types cannot
be selected at all and are not even fallback candidates.

---

## 5. What was built, and why this shape

**The design in one line: relax gate A for exactly the box-of-one-building case, and turn gate B
from a rule into a number.**

### 5.1 Gate A, relaxed for one case only

`sc_fanout.cpp`'s existing `SortAllUnits` detour (installed since task 011, evidence-logging only)
now calls `ScFanoutGrowBuildingGroup` after the original returns. It does nothing unless **all** of:
the mode is `fanout`, `%SCPLUGIN_BUILDING_GROUPS%` is on, `clicked == 0` (so: the drag box, §2.3),
the original returned exactly 1, and that one unit fails `unit_IsStandardAndMovable` — i.e. it is
the fallback of §2.2. Then it walks the same candidate list the engine walked and appends every
candidate of the **same type and same owner**, up to the caller's twelve slots, putting any beyond
the twelfth into the overflow accumulator that `sortOverflowHandler` feeds.

The engine does everything downstream unchanged: `CreateNewUnitSelectionsFromList` (`0x0049AE40`)
writes `activePlayerSelection` and attaches a selection circle to each, the HUD row fills, and
`CMDACT_Select` puts all of them on the wire. **Nothing in this plugin writes
`CSprite::selectionIndex` or sets sprite flag `0x08`** — the engine sets them itself, for an
ordinary N ≤ 12 selection, exactly as it would for N Marines.

The lead is left as the engine chose it. That is a deliberate answer to the mixed-BUILDING box: a
box holding four Supply Depots and three Barracks already selects one building in vanilla, chosen by
whichever was rejected last, and picking a different one here would layer a second arbitrary rule on
top of the engine's. So a mixed-building box selects **vanilla's own choice, plus that building's
siblings** — asserted in game as "exactly one type, more than one of it".

### 5.2 Gate B, not patched — and why not

The first five bytes of `0x0049AF80` are `TEST ESI,ESI` / `JZ 0x0049afb2` / `CMP EDI,0x8`, and the
`JZ` is **PC-relative**. `ScHookInstall` copies the patched-over bytes into the trampoline verbatim
with no relocation (`sc_hook.cpp`), so a detour there would leave a jump pointing into the middle of
whatever follows the trampoline allocation. The function is also inlined into `CMDRECV_ShiftSelect`,
so a detour would not cover every receive path anyway.

Instead the gate becomes a **number**: `simSlots`, how many of the current selection the simulation
will hold at once. It is recomputed at every selection commit from the first visible unit —
12 normally, **1** when that unit fails the predicate — and the fan-out, which already exists to
deliver an order to more units than the simulation can hold, chunks by it:

* `ChunkBounds` divides both the overflow region and the visible region by `slots` instead of by the
  constant 12. With `slots == 12` the visible region is one chunk, which is byte-for-byte the
  previous behaviour;
* the fan-out trigger becomes `shadowCount > simSlots` rather than `shadowCount > 12`;
* the visible chunks are emitted **backwards**, so the last Select of a plan carries the *first*
  visible unit — the one the engine itself put in slot 0. With one visible chunk that reordering is
  a no-op; with `slots == 1` it is what leaves the simulation holding the building the engine chose
  rather than an arbitrary member of the group.

So a rally to six Barracks goes out as six `Select(1)` + `RightClick` pairs, and the receive path
accepts each one at slot 0 — the slot gate B never guards.

Liveness is task 020's gate, reused unchanged: `EmitSelect` runs `PassesGate` on every unit before
its tag reaches the wire, and the append in §5.1 runs the same gate before a building enters the
selection at all, counted separately (`ScFanoutGroupRefusedFor`) because "kept out of the selection"
and "kept off the wire" are different events.

### 5.3 What stays stock, stated

| case | behaviour | why |
|---|---|---|
| single click, shift-click, ctrl+click, double-click on a building | unchanged, one building | those paths call `SortAllUnits` with `clicked != 0` (§2.3) |
| a box of units and buildings mixed | unchanged, the units only | `count != 0` at `0x0046F248`; the fallback never runs, so §5.1's precondition is never met |
| shift+box onto an existing selection | unchanged | `combineSelectionsLists` (`0x0046F290`) calls `0x0047B770` on both the existing selection's first unit and the new list's, and returns the existing count untouched if either fails |
| SINGLE-gated commands (build, etc.) with a building group selected | act on one building | those handlers check "exactly one unit selected" themselves (`command-opcodes.md` §5.1); identical to what they do for a >12-unit selection today |
| `%SCPLUGIN_BUILDING_GROUPS%=0` | vanilla, one building per box | the feature's own off switch, and the control arm of the in-game run |

---

## 6. How this was verified

**Offline** (`hooktest.exe` part [13], no game in the process): the client half is driven with the
engine's own argument shapes — a NULL-terminated candidate list, a 12-slot output array, `clicked`,
and the count the original returned — and the simulation half by the exact bytes the fan-out queues.
Asserted there: four same-type buildings grow from one; the engine's lead stays in slot 0; a rally
goes out as four `Select(1)`+order pairs with each building's own tag and the LAST pair carrying the
lead; a mixed-building box takes the lead's type and nothing else; a different owner is a different
group; a destroyed building is refused **for being dead** rather than merely absent; sixteen
buildings fill the twelve slots and put four past the cap; and `clicked != 0`, a count other than 1
and a movable lead are all identities. The last case re-asserts part [7]'s 36-unit numbers
unchanged, which is the regression guard on `chunk = simSlots`.

**In game** — `tools/plugin/test-building-groups.ps1`, three arms, one game launch each. The
fixture is generated per run into this agent's own `Maps\BroodWar\00-t024\` and deleted afterwards;
`StarCraft.exe` is hashed before and after every run and asserted byte-identical to pristine 1.16.1.

* `-Stock` — `%SCPLUGIN_BUILDING_GROUPS%=0`, same map, same binary: the same box selects **one**
  building, and the `BGROUP box:` line is absent. The feature arm proves that same pattern matches,
  so this absence is worth asserting (AGENTS.md, "absence assertions must first be proved positive").
* default — 16 Missile Turrets from one box (12 held by the engine, 4 past its cap); **every one of
  the sixteen carries a selection circle**, read from each unit's own sprite flag `0x01`, which
  covers the engine's twelve and the plugin's four in one number; six Barracks rallied by one
  right-click, asserted as a single rally-point bucket over all six from each building's own
  `CUnit+0xF8/+0xFA`; a mixed-building box; and a single click still selecting one.
* `-Combat` — six **Barracks** at 60% hit points with four computer Marines shooting them: a
  building dies inside the selection, the drop is counted and its reason named (`hp0` / `removed`),
  and no dead tag reaches an emitted Select. Barracks and not turrets, for a reason worth writing
  down: **a Missile Turret accepts no right-click at all.** It is immobile and produces nothing, so
  it has neither a move order nor a rally point, and a right-click with sixteen of them selected
  queues *nothing* — measured from the engine's own command stream, which held only `0x37` syncs and
  not one `0x14`. An arm that commands a type with no command cannot observe the command path: it
  reported `dropped=0` because nothing was ever considered, and "no dead tag reached the wire" was
  true only because no wire traffic existed. Barracks are the type §5 already proves a right-click
  fans out, which is exactly what makes them the right victims.

### 6.1 What the in-game arms actually reported

All three arms have run to **0 failures** on the no-raise harness (task 027). The numbers, so the
claims above can be checked against something rather than taken:

| arm | result | the numbers it reported |
| --- | --- | --- |
| `-Stock` | 0 failures | box over 16 turrets → `n=1 visible=1`, `simSlots=1`, no `BGROUP box:` line |
| default | 0 failures | `BGROUP box: lead=0x00623A68 type=124 owner=0 flags=0x54008101 -> selected 12 (+4 beyond the cap, 0 refused)`; `n=16 visible=12 overflow=4`, `circled=16/16`, over-cap circles `4/4`; rally `FANOUT start: cmd=0x14 units=6 slots=1 -> 6 Select+order pairs`, one rally bucket over all six; mixed box → `0x6F:2`, one type only; single click → `n=1` |
| `-Combat` | 0 failures | 6/6 boxed alive, first death 19 s later → `5 live of 6`, `hp0=1`; `FANOUT start: cmd=0x14 units=6 slots=1`; **`out=5 dropped=1`, and `6 = 5 + 1`**; the drop named its own term; rally reached the five survivors |

`StarCraft.exe` was hashed before and after every arm and came back byte-identical to pristine
1.16.1 each time; each arm closed its own game by pid and left no fixture behind.

**Focus, measured rather than asserted** (`watch-foreground.ps1` alongside each run): exactly one
borrow-and-return pair per arm, about two seconds each, around the Use-Map-Settings dropdown — the
one raise AGENTS.md then sanctioned (gone since #194, which writes `Custom Type` before launch
instead), because a dropdown is press-and-hold and Windows grants mouse capture only to the
foreground window. Focus went back to the user's own window every time; during the
`-Combat` run the user was using Search and Settings on the same machine and the run did not
disturb them.

#### What the arms cost to get right, and what that says about the tests

Three of the arms' failures were in the TEST, none in the engine or the plugin, and each one is
worth keeping written down because each was a case of an assertion that could not fail:

1. **The stock arm boxed the wrong block.** A full-screen drag after a minimap centring reached
   *both* blocks, and vanilla's "last rejected candidate" fallback picked a Barracks rather than a
   Missile Turret — the right behaviour measured on the wrong block. Fixed properly rather than
   loosened: the suite now reads the viewport origin out of the engine (`WORLD [...]
   screen=(left,top)`, from `0x0062848C`/`0x006284A8`), converts each unit's map position into a
   client coordinate, and boxes exactly the block it means. That is also what turned the
   mixed-building case into a deliberate arm instead of an accident.
2. **The combat fixture killed the group faster than the suite could command it.** Sixteen turrets
   at 12% hit points against eight Marines died in about fifty seconds; seven were already gone when
   the box landed and *all* of them by the time the right-click went out. The fan-out was handed a
   selection with nothing live in it, so "no dead tag reached the wire" passed with **zero tags on
   the wire**. Two fixes, because there were two defects: the fixture now dies as a trickle (four
   Marines, 60% hit points — first death 19 s after the box), and the suite now waits for a
   genuinely MIXED selection (`0 < live < n`) instead of merely `live < n`, so a window that never
   opens fails *there*, naming itself.
3. **The combat arm commanded a building type that accepts no command.** See §6's `-Combat` bullet:
   a right-click on Missile Turrets queues nothing at all. The arm now boxes Barracks, and — the
   part that matters for the next person — it asserts `FANOUT start:` is present *before* it asks
   what the fan-out did, so "the engine issued no command" can never again be reported as "no dead
   tag reached the wire".

The through-line is the rule AGENTS.md already states: an absence assertion is worth nothing until
the same pattern has been shown to match somewhere it should. All three failures were that rule
being violated in a new costume, and the fixes are positives placed in front of the absences.

---

## 7. Open after task 024, and what happened to each

1. **Ctrl+click "select all of this type on screen" for buildings.** ~~Untouched here.~~ Done in
   task 036 — §8.2. It needed no new research about the gate, but it did need the caller map in
   §8.1 before the change could be scoped honestly.
2. **More than twelve buildings and the HUD row.** Still open. The row pages the shadow list
   (task 017) and was not exercised with buildings; task 024's in-game arms run with `-HudRow 0`.
   Task 036's suite runs with `-HudRow 1` but its groups are six, below the twelve at which the
   plugin's row takes over, so this is still not exercised.
3. **Gate B properly relaxed.** Still open, and task 036 found a second reason to leave it alone
   (§8.4): the client-side control-group recall carries its OWN copy of the predicate, so relaxing
   the simulation without relaxing that would produce a group the simulation holds and the client
   cannot show.
4. **`0x006D0F14`**, the global tested at `0x0046F1AC` right beside the movable gate, disables
   multi-select wholesale when non-zero. Not identified here. **[unresolved]**

---

## 8. The other three input paths (task 036)

*Derived from the same binary and the same pipeline. Ghidra project `work/scratch/ghidra-036`,
spec [`tools/ghidra/specs/selection-input-paths.spec`](../tools/ghidra/specs/selection-input-paths.spec),
`DecompileMany.java` for the C and `ListingDump.java` for every instruction address quoted below.*

Task 024 shipped the drag box and the user played it. Every other way of selecting a group of
buildings still did not work — their words, 2026-08-11: *"i can`t select building with double click
(simillar buildings)"*, *"i can`t use ctrl or shift to modify building group"*, *"when i create a
control group with buildings and use it to select them it only shows 1 in tug after i click the
group number"*.

Three symptoms, one cause and three different mechanisms. §5.3's table said those paths were
"unchanged, one building … those paths call `SortAllUnits` with `clicked != 0`". **The first half
of that was right and the second half was wrong for two of the three**, and the correction is what
made the fix scopeable.

### 8.1 The click handler has four branches, and only two of them call `SortAllUnits`

`0x0046FB40` resolves the unit under the cursor (`0x0046F3A0`, returns immediately if there is
none) and then splits on two bytes of the engine's own `keyDown[256]` table at `0x00596A18` —
`0x00596A28` is `VK_SHIFT`, `0x00596A29` is `VK_CONTROL` — plus a double-click flag:

| branch | condition | what it does |
|---|---|---|
| ctrl or double-click, no shift | `0x0046FE41` | `SortAllUnits(rectScan, out12, clicked)` → `applyNewSelect` — REPLACE |
| shift **and** (ctrl or dbl) | `0x0046FCAD` | `SortAllUnits(rectScan, out12, clicked)` → `combineSelectionsLists` (`0x0046FCDD`) — ADD |
| shift alone, unit not selected | `0x0046FD1B`..`0x0046FD5F` | an INLINE add gate, then `applyNewSelect` |
| shift alone, unit already selected | `0x0046FD77`.. | an INLINE remove: `memmove` by `CSprite+0x0B`, then `0x0049AE40` + `CMDACT_Select` |
| plain click | `0x0046FBD6` | `0x0049AE40(1)` and `CMDACT_Select(1)` directly |

**So a plain click and a shift-click never reach `SortAllUnits` at all.** That inverts §5.3's
scoping argument in a useful direction: `clicked != 0` at `SortAllUnits` does not mean "some click
path", it means *exactly* "ctrl-click or double-click type match". Nothing else in the binary
passes a non-zero third argument.

And with `clicked != 0` the function pre-seeds its own output before the filter loop:

```
0046F0F5  MOV EAX,dword ptr [EBP + 0x10]     ; clicked
0046F0F8  TEST EAX,EAX
0046F0FA  JZ  ...
0046F0FC  MOV ECX,dword ptr [EBP + 0xc]      ; out12
0046F0FF  MOV dword ptr [ECX],EAX            ; out12[0] = clicked
0046F103  MOV dword ptr [EBP + -0x4],1       ; ... and the count starts at ONE
```

A screen full of buildings therefore leaves `ret == 1` with the clicked building in slot 0 — the
identical shape the box's "last rejected candidate" fallback produces (§2.2). One condition
removed from `ScFanoutGrowBuildingGroup` covers both.

### 8.2 The double-click is a MESSAGE, not a timer

The click handler's double-click term is `(clickedSprite->flags & 0x08) && DAT_0066FF58` at
`0x0046FB6E` — "the unit is already selected AND the double-click flag is set". That flag is
written in exactly one function, `0x0046FF70` (the mouse-event tick), and only from the event type
at `+0x0C`: types 3 and 5 leave it alone, every other type zeroes it, and **type 6 sets it**. Type
6 is what the window procedure hands to `0x004D1A50` for message `0x0203` — `WM_LBUTTONDBLCLK`.

The engine does no double-click timing of its own; it trusts Windows. That is a load-bearing
finding for this repo's harness in the same way the accelerator finding was
([`control-groups.md`](control-groups.md) §5): **a posted `WM_LBUTTONDBLCLK` is a real double click
as far as every layer above the window procedure is concerned**, and no `GetMessageTime`,
`GetDoubleClickTime` or key-state table is consulted on the way. `test-building-parity.ps1` drives
it as an ordinary click followed by a posted `0x0203` — which is also the order Windows delivers a
real one in, and the leading click is what satisfies the "already selected" half.

### 8.3 The two paths that EXTEND a selection ask the predicate directly

Neither is a function a plugin can wrap. Both consult `unit_IsStandardAndMovable` at four
instruction addresses, and each address is quoted here with the instruction after it — the return
address, which is what scopes task 036's detour:

```
; shift-click ADD, inside the click handler
0046FD1B  CMP EDI,0xc              ; the existing selection's length
0046FD1E  JGE 0x0046fe95           ; full -> refuse
0046FD24  MOV ECX,[EBP-0x3c]       ; the existing selection's FIRST unit
0046FD27  CALL 0x0047b770          ; returns to 0046FD2C
0046FD2E  JZ  0x0046fe95           ; refuse
0046FD35  CALL 0x00401170          ; NOT a building gate: "multi-select is on AND this is mine"
0046FD42  MOV ECX,EBX              ; the CLICKED unit
0046FD44  CALL 0x0047b770          ; returns to 0046FD49
0046FD4B  JZ  0x0046fe95           ; refuse
0046FD5F  MOV [EBP+EDI*4-0x3c],EBX ; append

; combineSelectionsLists 0x0046F290 -- shift+box and shift+ctrl-click
0046F2C6  MOV ECX,[EAX]            ; the NEW list's first unit
0046F2C8  CALL 0x0047b770          ; returns to 0046F2CD
0046F2E6  MOV ECX,EBX              ; the EXISTING list's first unit
0046F2E8  CALL 0x0047b770          ; returns to 0046F2ED
0046F2FD  MOV EAX,ESI / RET 0xc    ; either failure -> return the EXISTING count, no merge
```

`0x00401170` was read rather than assumed, because a second gate in the same block would have made
the predicate relaxation useless: it is
`DAT_006D0F14 == 0 && unit->player == DAT_00512684` — the global multi-select switch and an
ownership test. A building passes it.

**Shift-click REMOVE has no gate at all.** The branch at `0x0046FD77` compacts the selection by
`CSprite+0x0B` and calls `0x0049AE40` directly. So in *vanilla*, a player can shift-click a building
OUT of a selection but not INTO one — measured, not deduced (§8.5). Worth knowing before anyone
reads a bug report: "remove works, add does not" is the stock game, not a half-finished feature.

Both callers of `combineSelectionsLists` copy `activePlayerSelection` into a local before calling
(`0x0046FA40`'s 12-dword loop; `0x0046FC9A`'s `LEA EDI,[EBP-0x6c]` + `MOVSD.REP`), and the merge
appends without touching slot 0 — so `activePlayerSelection[0]` is the lead at all four sites, and
one read answers all four.

### 8.4 The control group: the store is what is capped, and the display is honest

The recall is the one with a concrete symptom and it turned out not to be a display bug at all.

The engine's own group row is filled by `hotkeySaveOrAdd` from `playersSelections`
([`control-groups.md`](control-groups.md) §3) — and gate B has already capped that at **one**
building (§3). So the row holds one tag. The client-side recall `0x00496B40` then carries its own
copy of the predicate:

```
00496BE5  CALL 0x0047b770
00496BEC  JNZ 0x00496bf7      ; passed -> keep this entry
00496BEE  CMP ESI,0x1         ; ESI = how many tags the row holds
00496BF1  JLE 0x00496bf7      ; a ONE-entry group is kept whatever it is
00496BF3  XOR EDI,EDI         ; otherwise drop it
```

which hands that one building back, writes it into `activePlayerSelection`, and the stock status
row — which draws `clientSelectionGroup`, copied from `activePlayerSelection` by
`updateSelectedUnitData` `0x004C38B0` — shows **1**. Exactly what the user saw, and the row was
never wrong: it was faithfully drawing a genuinely one-unit engine selection.

**This is also why writing `selectionHotkeys` would be the wrong fix**, and it is worth stating
because it is the first thing anyone tries. A row holding N buildings is emptied by the gate above
(with `N > 1` every building fails it), and the receive-side recall `0x00496940` **compacts the row
in place** as it validates ([`control-groups.md`](control-groups.md) §4.2 step 3) — so the
injection would be destroyed permanently rather than merely ignored, and the player would lose the
group. The fix is instead to hand the group to the engine's own client selection through
`CreateNewUnitSelectionsFromList` (`0x0049AE40`, **EAX = `CUnit**`, one stdcall argument, `RET 4`**
— confirmed here from `PUSH EDI / LEA EAX,[EBP-0x3c] / CALL` at `0x0046FDC2`), which is the very
call `0x00496B40` made a few instructions earlier.

### 8.5 What each path actually did, measured before anything was changed

`tools/plugin/test-building-parity.ps1 -Measure`, one game, six Barracks and six Marines, all
player-owned. Three engine arrays read at each named instant through the plugin's `SELSNAP` line —
`client` = `clientSelectionGroup` (what the stock row draws), `active` = `activePlayerSelection`
(the client's selection), `sim` = `playersSelections[player]` (what every order applier iterates) —
beside the plugin's own shadow list. **A symptom does not say which layer refused; three numbers
that disagree do.**

| input | shadow | client `active` | row `client` | `sim` | diagnosis |
|---|---|---|---|---|---|
| drag box (task 024) | 6 | 6 | 6 | 1 | works — the shipped behaviour |
| **double-click** | 1 | 1 | 1 | 1 | **client refusal** |
| **ctrl-click** | 1 | 1 | 1 | 1 | **client refusal** |
| **shift-click ADD** | 1 | 1 | 1 | 1 | **client refusal** |
| shift-click REMOVE | 5 | 5 | 5 | — | already worked in vanilla |
| **shift+box** | 3 | 3 | 3 | — | **client refusal** |
| **control-group recall** | 6 | **1** | **1** | 1 | **client refusal, at the STORE** |

The last row is the one the symptom could not have told anyone: the plugin held all six the whole
time and the right-click that followed rallied all six (`rally=[0x27C01E8:6] over 6 live`), so the
*selection* was never lost — only the engine-visible half of it. `GROUP recall enter: group=1
activePlayerSelection holds visible=1` is the engine's own recall reporting what it had to give.

None of the three is an engine drop and none is a display bug.

---

## 9. What task 036 changed, and the mixed-selection decision

### 9.1 Three changes, one principle: let the engine do the work

1. **Double-click and ctrl-click** — `ScFanoutGrowBuildingGroup` lost its `clicked == 0`
   condition. §8.1 is the whole justification: the only calls with a non-zero `clicked` are the two
   type-match branches, and the result shape there is identical to the box's.
2. **Shift-click, shift+box, shift+ctrl-click** — one detour on `unit_IsStandardAndMovable`
   (`0x0047B770`; patch window seven bytes, `66 8B 41 64 0F B7 D0`, two whole instructions, neither
   PC-relative), scoped by RETURN ADDRESS to the four sites in §8.3 and inert at every other call
   site in the binary. The rule: **when the lead of the selection being extended is a building,
   membership at those four sites becomes "same type and same owner as the lead, and alive"**.
3. **Control-group recall** — when the recalled lead is a building, the group is re-installed into
   the engine's own client selection with `0x0049AE40` (§8.4). The plugin still writes no byte of
   `selectionHotkeys`, `playersSelections` or the engine's group storage.

Gate B is still not patched, and `simSlots` is still 1 for a building group — so orders still fan
out one `Select`+order pair per building, unchanged from task 024.

### 9.2 Why relaxing the predicate at those four sites cannot regress vanilla

The lead being a building is *precisely* the case in which vanilla refuses the whole operation: the
lead's own call site returns 0 and the handler bails. So every outcome under the new rule replaces
"nothing happens" with something. That is also what licenses the rule to **refuse** where the engine
would have allowed — a Marine shift-clicked onto a building group is refused here, and vanilla
refused it too, one call site earlier. The override is only ever consulted after the lead has
already failed.

### 9.3 The mixed-selection decision, stated

**A building group is ONE TYPE, on every path.** A building may join a selection whose lead is a
building of the same type and the same owner; anything else stays refused.

- the box is same-type by construction (§5.1);
- double-click and ctrl-click are same-type by the engine's own filter, which compares each
  candidate's `CUnit+0x64` against the clicked unit's (`0x0046F1E5`);
- shift-click and shift+box are made to agree by §9.1's rule.

Refusing rather than allowing is a deliberate answer to the task's constraint that no command may
fan out to a building that cannot execute it. Two reasons, and the second is the load-bearing one:

1. `simSlots` is computed from the first visible unit and its correctness rests on "same kind ⇒
   same verdict" (§4) — a selection holding both a Marine and a Barracks would report 12, and the
   Barracks would silently never receive the order.
2. The engine's per-building requirement interpreter (`0x0046E1C0`, task 030) is a real backstop
   and it would refuse cleanly — but a backstop that refuses is still a command the player issued
   and did not get. Keeping the selection homogeneous means the question never arises.

**A mixed-BUILDING box is unchanged from task 024**: vanilla's own lead, widened to that lead's
type (§5.1). What is new is only that shift can no longer produce a mixture the box cannot.

### 9.4 Two per-unit narrowings the review asked for

The predicate failing is **not** the same question as "this is a building": §4 shows it also fails
on the units.dat *single entity* flag, on four PER-UNIT fields, and on an id list. Task 024 could
lean on the predicate alone because `clicked == 0` had to hold as well, and a box that selected
exactly one non-building thing was already a vanishing case. That is no longer true once every
ctrl-click and double-click arrives at the same function, and it was never true for the recall
branch — the simulation gate exists for units too, and its refusing must not be read as "this is a
building group".

So all three new paths ask **both** questions: the predicate refused it, *and* `unitsDatFlags[type]`
carries bit `0x01`. The flag word is read from the live process and logged
(`BGROUP box: … flags=0x…`), which is what makes `0x00664080` a measured table here rather than an
inherited claim.
5. **A big building group costs more turn-buffer bytes than a big unit group, by construction.**
   `slots == 1` means one `Select` per building, so an order to N buildings is `N × (4 + orderLen)`
   bytes where the same order to N units is `ceil(N/12) × (26 + orderLen)`. Sixteen buildings and a
   10-byte right-click is 224 bytes against a 200-byte default budget, so the tail defers to the
   next command — the fan-out's existing, logged behaviour (`FANOUT defer:`), not a new failure
   mode, and it is why `DrainPlan` was built to spill across frames in the first place
   (`selection-cap.md` §6.2). Worth knowing before anyone raises the group cap: the byte cost of a
   building group grows twelve times faster than a unit group's.
