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
click handler). **Only `0x0046FA40` passes `clicked = 0`** (`command-path.md` §3.3, re-checked here
against `0x0046FA40`'s own listing: `FUN_0046f0f0(candidates, local_34, 0)`). The fallback
substitution at `0x0046F27A` is reachable only on that path — `0x0046F264` sends the
`clicked != 0` case to `0x0046F268`, which puts the *clicked* unit in slot 0 instead. So
"box" and "click" are separable at this level without any state of our own.

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
* `-Combat` — the same turrets at 12% hit points with a computer force shooting them: a building
  dies inside the selection, the drop is counted and its reason named (`hp0` / `removed`), and no
  dead tag reaches an emitted Select.

### 6.1 What the in-game arms have actually reported so far

Stated plainly rather than left to be inferred, because these arms are the acceptance evidence and
they are not all in yet.

**The `-Stock` arm has run, and its substantive assertions passed.** With the feature off, a drag
box over sixteen buildings selected **one** (`n=1`, `visible=1`), `simSlots` reported **1**, and no
`BGROUP box:` line was written. That is vanilla §2.2 and §3, measured in the live game rather than
read off a listing.

That run also failed one assertion, and the failure was in the TEST, not in the engine or the
plugin: the box was a full-screen drag after a minimap centring, it reached **both** blocks, and
vanilla's "last rejected candidate" fallback picked a Barracks rather than a Missile Turret. Which
building vanilla picks out of a mixed box is arbitrary (§2.2) — so the run measured the right
behaviour on the wrong block. The fix is not a looser assertion: the suite now reads the viewport
origin out of the engine (`WORLD [...] screen=(left,top)`, from `0x0062848C`/`0x006284A8`), converts
each unit's map position into a client coordinate, and drags a box around exactly the block it
means. That is also what makes the mixed-building arm a deliberate case instead of an accident.

**The feature and `-Combat` arms have not been run yet.** In-game runs were suspended part-way
through this task (the harness raises the game window to the foreground for every posted mouse
move, which was interrupting the machine's user), and they are the only outstanding work here.
Everything offline — `hooktest` part [13] and `run-ci-local.ps1` — is green.

---

## 7. Open, and deliberately not done

1. **Ctrl+click "select all of this type on screen" for buildings.** It goes through `0x0046FB40`
   with `clicked != 0` and is untouched here. It is the obvious next step and needs no new
   research — only a decision about whether it should behave like the box.
2. **More than twelve buildings and the HUD row.** The row pages the shadow list (task 017) and was
   not exercised with buildings; the in-game arms run with `-HudRow 0`, as the other fan-out suites
   do.
3. **Gate B properly relaxed.** Doing it would need a relocating trampoline (a length-disassembler
   for the patched window) or an inline patch of the `JZ` at `0x0049AFA4`, and it would let the
   simulation hold a real multi-building selection instead of one-at-a-time chunks. Worth costing
   only if something needs the *simulation* to hold them — nothing in this task did.
4. **`0x006D0F14`**, the global tested at `0x0046F1AC` right beside the movable gate, disables
   multi-select wholesale when non-zero. Not identified here. **[unresolved]**
