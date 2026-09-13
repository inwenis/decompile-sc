# Upgrades and research — where the ONE lives, and what can be done about it

Task 029. Everything here was derived from `StarCraft.exe` 1.16.1 (the working copy at
`C:\decompile-sc-data\sc-work\1161-base`, SHA-256 `AD6B…6A46`) with this repo's own Ghidra pipeline and its own
in-process readers. Every address carries how it was found and how it was checked (AGENTS.md
hard rule 4). Nothing is inherited from public prior art: the community fact that would have
been tempting to copy — "`building.techType` is at `CUnit+0xC8` and `building.upgradeType` at
`+0xC9`" — is re-derived below off two *button conditions* that compare those bytes against
their own sentinels, and the second half of this document (how the one-at-a-time is enforced,
and where the client refuses) has no published counterpart at all.

Committed evidence tables:

| file | what it is |
|---|---|
| [`data/upgrade-fields.tsv`](data/upgrade-fields.tsv) | every instruction with displacement `0xC6`, `0xC8`, `0xC9` or `0xCD`, `FieldSweep.java` |

Specs, so the runs are repeatable: `tools/ghidra/specs/upgrade-{functions,callees,callees2,ticksites}.spec`.
§9 has the exact commands. The live half is `tools/plugin/probe-upgrade-wire.ps1`.

---

## 1. The short version

* A building researches **one thing at a time** because it has **one field for it**:
  `CUnit+0xC9` (u8) is the upgrade in progress, `CUnit+0xC8` (u8) the tech. §2.
* The sentinels are **61** and **44** — one past the last `upgrades.dat` / `techdata.dat` id,
  the same trick the build queue's `0xE4` uses. §2.
* "One at a time" is **one predicate used twice**: `upgradeGate` `0x0046DFC0` is both the
  card's own upgrade-button condition (`0x00429450` is a bare tail call to it) *and* the first
  thing `cmdrecvUpgrade` `0x004C1B20` runs. Inside it, the refusal is a single **requirement
  opcode** — `0xFF0A` for upgrades, `0xFF09` for techs, `0xFF07` for both — which reads exactly
  those two bytes and returns 0 with reason 5. §4.
* Returning **0** (rather than −1) means the layout function *skips* the button, so the client
  does not grey it — it **removes it from the card** and replaces the card with a lone Cancel
  button. Measured in a live game. §3.
* So **the client never sends a second `0x32`/`0x30`**, and a receive-side-only design is
  impossible. §3.
* The money is in exactly two functions, `startUpgrade` `0x00454A80` and `startTech`
  `0x00454B70`, and **both take the building in a register** — which is what makes a
  plugin-side queue possible without the plugin ever spending. §5.
* What ships is: unblock the card's own button conditions, hold the extra commands, and hand
  them back to the engine's own accept path as the building frees. §7.
* Levels do NOT stack. §7.5 records the second, narrower lie that once let Weapons 2 queue
  behind Weapons 1; it was withdrawn when the same mechanism let a HELD upgrade be queued
  again on every press. The rule now is one entry per id per building: a held id is hidden
  on the card and refused on the wire. §7.7.

---

## 2. Where the state is

### 2.1 The two fields, derived from the conditions that read them

Neither field was taken from a struct listing. Each was read off a *button condition* whose
whole body is a comparison against that field's sentinel — and the two conditions cross-check
each other, because one requires "idle" and the other requires "busy".

`btnCancelUpgradeCondition` (`0x00428900`) is two instructions of meaning:

```c
bool FUN_00428900(int unit) { return *(char *)(unit + 0xc9) != '='; }
```

`'='` is `0x3D` = **61**. The Cancel Upgrade button is on the card exactly when `+0xC9` is not
61 — i.e. **`CUnit+0xC9` is the upgrade being researched, and 61 means none.**

`btnLiftOffCondition` (`0x004287D0`) requires the opposite, and names the other field:

```c
if ((unit->flags & 2) != 0) {                       /* a BUILDING */
    if (FUN_00401500() == 0 && *(char *)(unit + 200) == ','   /* 0xC8 == 44 */
                            && *(char *)(unit + 0xc9) == '=') /* 0xC9 == 61 */
        return 1;
}
return 0;
```

`','` is `0x2C` = **44**. So **`CUnit+0xC8` is the tech being researched, and 44 means none** —
and a Terran building may only lift off when *both* are at their sentinels.

61 is one past the last `upgrades.dat` id (0…60) and 44 one past the last `techdata.dat` id
(0…43), which is why they can be sentinels inside the id field itself. Same construction as
`0xE4` in the build queue (`research/production-queue.md` §2.4).

### 2.2 The other two fields, from the writers

`startUpgrade` (`0x00454A80`) writes three of the four in six instructions:

```c
unit->0xC9 = upgradeId;                       /* the id            */
unit->0xC6 = FUN_00453f70();                  /* u16 time remaining */
unit->0xCD = currentLevel(player, id) + 1;    /* the LEVEL being researched */
```

`startTech` (`0x00454B70`) writes `0xC8` and `0xC6` and leaves `0xCD` alone (a tech has no
level). Both order handlers then decrement `0xC6` once per frame (§6).

| field | type | meaning | sentinel |
|---|---|---|---|
| `CUnit+0xC6` | u16 | research/upgrade time remaining | 0 |
| `CUnit+0xC8` | u8 | tech being researched | 44 |
| `CUnit+0xC9` | u8 | upgrade being researched | 61 |
| `CUnit+0xCD` | u8 | the level being upgraded TO | 0 |

### 2.3 These bytes are a UNION, and every read must be gated on "is a building"

`FUN_00469240`, a unit-update path, stores a **`CUnit*`** at `+0xC8` and a coordinate pair at
`+0xC4`/`+0xC6`:

```
00469... MOV dword ptr [EAX + 200], ESI      ; an ORDER TARGET pointer, not a tech id
```

So `0xC6`–`0xCD` is one arm of a union and "tech 0x2C, upgrade 0x3D" is only its meaning for a
**building**. That is not an inference: all three engine readers gate on it. `btnLiftOff`
tests `flags & 2` before touching either byte, `upgradeTick` (`0x004546A0`) opens with
`if ((unit->flags & 2) != 0 && unit->0xC9 != 0x3D)`, and `cmdrecvCancelUpgrade`
(`0x004BFFC0`) requires `flags & 1` plus the unit's own `units.dat` flag word. The plugin
does the same, for the same reason.

`CUnit+0xDC & 2` is the building flag; `& 1` is "construction complete".

### 2.4 There is exactly ONE slot, and no room beside it

`0xC6`/`0xC8`/`0xC9`/`0xCD` are single scalars, not arrays — every one of the 171 instructions
the field sweep found addresses them with a bare displacement and **no index register**
(`data/upgrade-fields.tsv`: 15 rows for `0xC6`, 100 for `0xC8`, 47 for `0xC9`, 9 for `0xCD`;
the `0xC8` rows are the noisiest because that displacement is also §2.3's union arm and lands
inside unrelated structs). `0xCA`, `0xCB`, `0xCC` are taken by the same union (the addon
build type and the larva/landing timers the sweep shows being decremented at `0x004652FD` and
`0x004662AB`), and `CUnit` is a fixed `0x150` stride inside a fixed array at `0x0059CCA8`
(task 011), so the struct cannot grow. Widening in place is not an option here for the same
two reasons it was not one for the build queue, and this task did not attempt it.

---

## 3. What the client does — measured, not inferred

`tools/plugin/probe-upgrade-wire.ps1`, one launch, `-Mode hooktest -LogCommands 1
-CardScan 1 -WorldScan 1`. Fixture: one Terran Engineering Bay (`units.dat` 122) owned by
player 0 with 3000 minerals and 3000 gas and nothing else in the game. The Engineering Bay
was chosen because it offers two INDEPENDENT level-1 upgrades — Terran Infantry Weapons
(`upgrades.dat` 7) and Terran Infantry Armor (`upgrades.dat` 0) — so "queue a second upgrade"
can be asked without dragging in the level-N/level-N+1 case (§8.2).

Every click point is computed from the LIVE dialog (`Get-ScCardSlotPoint`: the dialog's own
origin plus the control's own rect, halved), never from a frame and never hardcoded.

### 3.1 The card, idle

```
CARD[idle] cardId=122 portraitType=0x7a portraitSet=122 setCount=7 shown=3 greyed=0 reason=0
  slot=1 enabled icon=0x120 bslot=1 cond=0x00429450 act=0x00423310 cparam=7 aparam=7
  slot=2 enabled icon=0x124 bslot=2 cond=0x00429450 act=0x00423310 cparam=0 aparam=0
  slot=9 enabled icon=0x11a bslot=9 cond=0x004287D0 act=0x00423230
  slots 3..8 hidden
```

`0x00423310` is the `0x32` Upgrade emitter and `0x00423230` the `0x2F` Lift Off emitter
(`research/data/command-ids.tsv`), so those are, in order, Infantry Weapons, Infantry Armor
and Lift Off. This is the read that names the two condition functions §4 then decompiles.

### 3.2 One press, one command

```
[22:00:14.905] CMD id=0x32 len=2 bytes=[32 07]
```

Three bytes short of the Train command and carrying the upgrade id verbatim. Four seconds
later the world scan shows the building's primary order moved `0x17` → `0x4C`, so the upgrade
is genuinely running — the precondition of the whole question is checked in memory rather
than assumed.

### 3.3 The card, with that upgrade running

```
CARD[busy] cardId=122 portraitType=0x7a portraitSet=122 setCount=7 shown=1 greyed=0 reason=5
  slots 1..8 HIDDEN
  slot=9 enabled icon=0xec  bslot=9 cond=0x00428900 act=0x004232F0
```

Three things worth separating:

1. **The buttonset did not change** (122 both times, 7 buttons both times). The card was not
   swapped; the same seven buttons were walked and six of them failed their conditions.
2. **The upgrade buttons are HIDDEN, not greyed.** `greyed=0`, `shown=1`. Task 025's Train
   button went *dark*; these are not on the card at all. Per `research/command-card.md` §4.1
   that is the difference between a condition returning `0` and returning `−1`.
3. **`reason` (`0x0066FF60`) reads 5** — the number §4's opcode writes, in the same run, at
   the same moment. The static reading and the live game agree on the same constant.

### 3.4 The presses that were refused

Both presses aim at the point the IDLE card put the button at — the same arithmetic, on the
same dialog, that §3.2 used to send a command successfully four seconds earlier. Each is
pressed three times, 300 ms apart, so a single press lost to a frame boundary cannot explain
a zero.

```
clicking slot 2 at client (568,374) -- idle it was enabled/aparam=0, busy it is hidden
  -> 3 presses put 0 command(s) on the wire
clicking slot 1 at client (522,374) -- idle it was enabled/aparam=7, busy it is hidden
  -> 3 presses put 0 command(s) on the wire
```

Six presses, no command. A *different* upgrade is refused exactly as hard as a repeat of the
running one.

### 3.5 The control, in the same run

A run in which nothing is sent is compatible with "the clicks stopped working", which is the
ambiguity task 022 lost a whole question to. So the probe cancels the running upgrade and
presses again:

```
clicking the busy card's only button (slot 9, cond=0x00428900, act=0x004232F0) at (614,454)
  [22:21:37.464] CMD id=0x33 len=1 bytes=[33]
  after cancel: order=0x17 order2=0x17          (it left the researching order)
  card: shown=3, slots 1 and 2 back, enabled    (busy card offered 0)
re-pressing slot 2 at the SAME client point (568,374)
  [22:21:41.054] CMD id=0x32 len=2 bytes=[32 00]
```

One press, one command, at a point that had just absorbed three presses in silence. So the
zeros above are a refusal by the client and not a missed click — and the only thing that
changed between the silence and the send is whether `CUnit+0xC9` held 7 or 61.

**Conclusion: the client refuses to send.** There is no second `0x32`/`0x30` on the wire to
catch, so a receive-side-only design — the shape task 025 originally built and had to throw
away — is impossible here too, and for a stronger reason.

---

## 4. Every place the ONE is enforced

### 4.1 One predicate, used twice

`btnUpgradeCondition` (`0x00429450`) is a single tail call:

```c
void FUN_00429450(int unit) { FUN_0046dfc0(unit); }
```

and `cmdrecvUpgrade` (`0x004C1B20`) calls the same `0x0046DFC0` before it does anything:

```c
selectionIterator = 0;                                   /* 0x006284B6 */
u = selNext();                                           /* 0x0049A850 */
if (u && selNext() == 0                                  /* EXACTLY ONE selected */
      && upgradeGate(u) == 1                             /* 0x0046DFC0 */
      && startUpgrade())                                 /* 0x00454A80 */
    { afterAccept(); /* + five redraw globals */ }
```

`cmdrecvTech` (`0x004C1BA0`) is the same function with `techGate` `0x0046DE90` and `startTech`
`0x00454B70`. So the client half and the receive half of the enforcement are **the same code**,
and anything that changes one changes both.

### 4.2 The gate's own tests

`upgradeGate` `0x0046DFC0` — `EBX` = upgrade id, `EDI` = player, stack = the unit — in order,
each writing the refuse reason first:

| test | reason | note |
|---|---|---|
| id `> 0x3C` | `0x12` | 61 upgrades |
| `player != unit->owner` (`+0x4C`) | `1` | |
| `unit->flags & 1` clear | `0x14` | not finished building |
| `FUN_004020B0(unit)` | `10` | lifted / under construction / stasis-ish |
| `maxLevel <= currentLevel` | `0x0E` | `0x004CE7F0` vs `0x004CE7A0` |
| **`upgradeBusy(player, id)`** (`0x004281B0`) | `0x0C` | **per PLAYER + per UPGRADE** |
| availability cache `0x006558C0[id] == 0` | `0x17` | |
| otherwise | — | tail into the requirement interpreter `0x0046D610` with table `0x005145C0` |

`techGate` `0x0046DE90` is the same shape with `0x00656198`, `0x004CE8A0`/`0x004CE850` and
table `0x00514908`, and `techBusy` `0x00428240`.

`upgradeBusy` is thirteen bytes and it is **not** the per-building test:

```c
uint FUN_004281b0(void) {          /* EDX = player, CL = upgrade id */
    return upgradeInProgressBits[player * 8 + (id >> 3)] & (1 << (id & 7));
}
```

`0x0058F3E0`, eight bytes per player — a bitfield of "this PLAYER is already researching this
UPGRADE, somewhere". `startUpgrade` sets that bit and `upgradeTick`/`cancelUpgrade` clear it,
all three at the identical expression. `techBusy` is its twin at `0x0058F230`, six bytes per
player. This is what stops the *same* upgrade being started at two buildings — and, usefully,
what stops level N+1 being queued behind level N (§8.2).

### 4.3 The per-building test is a REQUIREMENT OPCODE

The one-at-a-time-at-this-building refusal is not in the gate at all. It is inside the
requirement interpreter `0x0046D610`, three cases of a nineteen-case switch:

```c
case 0xff07:  if (isLifted())               { reason = 5; return 0; }
              if (unit->0xC8 != 44)         { reason = 5; return 0; }
              /* NO break -- falls through */
case 0xff0a:  if (unit->0xC9 != 61)         { reason = 5; return 0; }
              satisfied++;  break;
case 0xff09:  if (unit->0xC8 != 44)         { reason = 5; return 0; }
              satisfied++;  break;
```

`0xFF0A` is "no upgrade running here", `0xFF09` is "no tech running here", and `0xFF07` is
both plus "not lifting". `return 0` — not `−1` — is why §3.3 saw the buttons *gone* rather
than greyed.

The same three bytes are read by the *second* requirement interpreter `0x0046E1C0` (the one
task 026 met on the production side) at `0x0046E3B2`, `0x0046E411` and `0x0046E450`, so the
enforcement is duplicated across both VMs. `data/upgrade-fields.tsv` is the full list; the
sites that matter are:

| site | address | what it does with `0xC8`/`0xC9` |
|---|---|---|
| requirement VM 1 | `0x0046D610` | `0xFF07`/`0xFF09`/`0xFF0A`, reason 5, return 0 — **the refusal** |
| requirement VM 2 | `0x0046E1C0` | three more comparisons against `0x3D` |
| `btnCancelUpgradeCondition` | `0x00428900` | the complement: show Cancel iff `!= 61` |
| `btnLiftOffCondition` | `0x004287D0` | requires both sentinels |
| `cmdrecvLiftOff` | `0x004C1620` | `CMP byte ptr [ESI + 0xC9],0x3D` |
| `upgradeTick` | `0x004546A0` | refuses to run unless `!= 61`; clears to 61 on completion |
| `techTick` | `0x004548B0` | same on `0xC8`, clears to 44 |
| `startUpgrade` / `startTech` | `0x00454A80` / `0x00454B70` | **no check at all** — they simply overwrite |
| `unitRemoved` | `0x0049FD00` | `CMP [ESI+0xC9],0x3D` on the death path |
| status-area drawers | `0x00425B50`, `0x00426500`, `0x004266F0` | draw the progress bar |

The last-but-two row is the one to remember: **the two start functions do not check whether
something is already running.** Everything that protects the field is upstream of them, in the
gate. That is what makes the design in §7 safe to build and dangerous to build carelessly.

---

## 5. The money

### 5.1 Upgrades

`startUpgrade` `0x00454A80` — `AL` = upgrade id, `ECX` = the building:

```c
if (id < 0x3D && FUN_0042d190(1)) {              /* affordability + pending cost */
    player = unit->owner;
    unit->0xC9 = id;
    unit->0xC6 = upgradeTime(player, id);        /* 0x00453F70 */
    unit->0xCD = currentLevel(player, id) + 1;
    minerals[player] -= pendingMineral[player];  /* 0x0057F0F0 -= [0x006CA51C] */
    gas[player]      -= pendingGas[player];      /* 0x0057F120 -= [0x006CA4EC] */
    upgradeInProgressBits[player] |= 1 << (id & 7);
    ...
    return 1;
}
return 0;
```

`FUN_0042D190` fills the two pending-cost globals from the per-upgrade **base + factor ×
level** tables and returns 0 when the player cannot pay:

```
mineral = level * u16[0x006559C0 + id*2] + u16[0x00655740 + id*2]
gas     = level * u16[0x006557C0 + id*2] + u16[0x00655840 + id*2]
time    = level * u16[0x00655940 + id*2] + u16[0x00655B80 + id*2]
```

`upgradeRefund` `0x00454170` adds back the *same* expression out of the *same* tables, so
spend and refund cancel exactly, by construction.

### 5.2 Techs

`startTech` `0x00454B70` — `AL` = tech id, `EDX` = the building — does it inline, with flat
per-tech tables and no level:

```
mineral = u16[0x00656248 + id*2]     gas = u16[0x006561F0 + id*2]
time    = u16[0x006563D8 + id*2]
```

It checks both resources first and returns 0 without moving anything if either is short.
`cancelTech` `0x00453E30` adds the identical two values back.

### 5.3 The two facts the design needs

1. **All of it is inside those two functions.** No other code path spends an upgrade's or a
   tech's cost.
2. **Both take the building as an explicit register argument** (`ECX` and `EDX`
   respectively) rather than resolving it through the selection. So a plugin can hand an item
   to the engine at a building the player is not looking at, and the ENGINE pays for it.

---

## 6. How one finishes

The two order handlers are also the ticks. `upgradeTick` `0x004546A0` (`EAX` = the building):

```c
if ((unit->flags & 2) && unit->0xC9 != 0x3D) {
    if (unit->0xC6-- != 0 && currentLevel(player, id) < unit->0xCD && !cheat) return;
    ...
    if (currentLevel(player, id) < unit->0xCD && FUN_004033d0())
        { FUN_004ce770(); FUN_00454540(unit); }     /* raise the level, apply its effects */
    ... five redraw globals ...
}
upgradeInProgressBits[player] &= ~(1 << (id & 7));
unit->0xC9 = 0x3D;
unit->0xCD = 0;
... re-issue the building's order ...
```

`techTick` `0x004548B0` is the same on `0xC8`, and its completion writes the researched flag
straight into the arrays task 026 named:

```c
if (tech < 0x18) techResearched[player][tech]   = 1;   /* 0x0058CF44, stride 0x18 */
else             techResearchedBW[player][tech] = 1;   /* 0x0058F128, stride 0x14 */
```

So "the researched flag flipped" is a one-byte read in the engine's own memory, in the array
this repo already evidenced from the other direction — which is the oracle §8's in-game run
asserts on.

Upgrade levels live in the matching pair, read by `0x004CE7A0` (current) and `0x004CE7F0`
(max):

| address | what | stride |
|---|---|---|
| `0x0058D2B0` | `upgradeLevel[12][46]` (upgrades 0…45) | 0x2E |
| `0x0058D088` | `upgradeMaxLevel[12][46]` | 0x2E |
| `0x0058F2FE` | `upgradeLevelBW[12][15]` (upgrades 46…60) | 0x0F |
| `0x0058F24A` | `upgradeMaxLevelBW[12][15]` | 0x0F |

The four are named off `0x004CE7A0`/`0x004CE7F0`, whose whole bodies are the two-branch index
computation, and the same expression appears verbatim in `startUpgrade`, `upgradeRefund`,
`FUN_0042D190`, `upgradeTime` and requirement opcode `0xFF1F` — six independent sites, one
index rule.

---

## 7. The design

### 7.1 Why neither of the two obvious shapes fits

* **Task 025's inversion** — keep the engine's slot free so the button stays live — cannot
  transfer. The engine's capacity is exactly ONE. A free slot means nothing is being
  researched, so "keep it free" and "make progress" are the same variable pulling opposite
  ways.
* **A receive-side handler** cannot work either: §3 shows the command never arrives.

### 7.2 What ships: unblock, hold, promote

**(a) UNBLOCK.** Detour the two CARD BUTTON CONDITIONS — `btnUpgradeCondition`
`0x00429450` and `btnTechCondition` `0x00429500`, which are byte-for-byte the same 20-byte
wrapper marshalling `CL`/`EDX` into the gate. When the feature is on, the unit is a
completed building, it is currently researching, and its logical queue is below the cap:
evaluate the ORIGINAL condition with `0xC9`/`0xC8` temporarily set to their idle sentinels,
and restore them before returning. The card offers the upgrade buttons again and the client
starts sending. Everything else keeps vanilla's answer, because Lift Off and the Cancel
button read the fields directly rather than through the gate.

> **The conditions, and NOT the gates. This was the design's first choice and it was
> wrong.** `HookProbe`'s caller list settles it: each gate has THREE callers, and the third
> is in the building-AI range — `0x00434670` calls `upgradeGate`, `0x004345C0` calls
> `techGate`. A computer player told that a busy building is free would issue an upgrade,
> and §4.3's last row says what happens next: `startUpgrade` does not check, so it would
> apply the new upgrade on top of the running one and pay for it. The conditions have no
> CALL references at all — the button table reaches them as DATA — so hooking them touches
> the card and nothing else.

**At the cap the plugin stops lying.** The gate tells the truth, the layout hides the button,
and the client refuses on its own — the cap is vanilla's own mechanism, which is the property
task 025 valued most.

**(b) HOLD.** Detour `cmdrecvUpgrade` `0x004C1B20` and `cmdrecvTech` `0x004C1BA0` at entry.
Resolve the acting building the way the engine does (reset `selectionIterator` `0x006284B6`,
`selNext` twice, require exactly one). If it is already researching and there is room, append
`{kind, id}` to the plugin's per-building record and return **without running the engine's
body at all** — which matters, because §4.3's last row means the engine's body would happily
overwrite the running upgrade. Otherwise pass through untouched and let the engine start it
and pay for it.

**(c) PROMOTE.** Detour `upgradeTick` `0x004546A0` and `techTick` `0x004548B0`. Run the
original; if the building has just gone idle and the plugin holds items, pop the oldest and
run the engine's own accept path on it — `gate(unit, id, player) == 1` then
`startUpgrade`/`startTech` with the unit in the register they expect. That is
`cmdrecvUpgrade`'s own body with the unit supplied by the plugin instead of by the selection.

### 7.3 The resource hazard, and how it is answered

**The plugin never touches a resource global, in either direction.**

| hazard | answer |
|---|---|
| paid **twice** | Only the engine ever pays, in `startUpgrade`/`startTech`, at the moment the item actually starts (§5.3). Holding an item costs nothing because a held item is one id and no money. There is no second payer, so "exactly once" is the shape of the design and not a discipline. |
| a **wrong refund** | There is nothing to refund. A held item is unpaid, so dropping one — cancel, building destroyed, plugin unloaded mid-game — strands nothing. A cancel that reaches the running item is vanilla's own `0x33`/`0x31` path, untouched. |
| the **UI disagreeing** | The status area draws the running item's progress bar, which is true, and the held items as icons in queue slots 2..5 (§10). The plugin's `UPGQ` log line and the engine's own strip walk (`STATQ`) are the read-back oracles. |
| **negative resources** | Not reachable: the plugin never spends, and before promoting it compares the engine's own cost tables against `0x0057F0F0`/`0x0057F120` and simply waits when the player is short. A comparison, not a transaction. |

This is a deliberate divergence from vanilla unit training, which charges at *queue* time.
Pay-at-start is the better bargain for upgrades: it makes double payment structurally
impossible, it makes cancel exactly correct for free, and a player who queues four upgrades
and then loses the building loses only the one that was actually running — which vanilla
refunds itself.

### 7.4 Cancel

While researching, the card offers exactly one button and it means "cancel". Matching task
025's `0xFE` rule (`research/production-queue.md` §6.4):

* the plugin holds items → it drops its own **most recent** one and the running upgrade
  continues. Nothing is refunded because nothing was paid. Press again to keep unwinding.
* the plugin holds nothing → straight through to vanilla, which cancels the running item and
  refunds it exactly.

### 7.5 Stacking the levels of ONE upgrade, and the engine rule that nearly forbade it

Weapons 2 behind Weapons 1 needs a second lie, because the card refuses the running
upgrade's own button through a test §7.2(a) does not touch: `upgradeBusy` `0x004281B0`
(§4.2), the per-player-per-upgrade bitfield at `0x0058F3E0`.

**Suppressing that naively would break a real engine rule.** The same bit is what stops TWO
BUILDINGS researching the same upgrade at once, and the consequence is not cosmetic. Both
would call `startUpgrade`, both would pay, and both would set `CUnit+0xCD = currentLevel +
1` — the SAME target level. When the first finished and raised the level, the second's next
tick would find `currentLevel < unit->0xCD` already false, skip the early return, complete
immediately, and raise nothing (§6). The player would have paid twice for one level.

So the suppression is scoped by a condition a second building **cannot** satisfy:

> this building's own `CUnit+0xC9` already holds this very upgrade id.

A second Engineering Bay's `0xC9` holds 61, or a different id, so its button stays hidden
and the two-buildings rule is untouched. Only the building that already owns the upgrade is
allowed to be asked about it again. `hooktest` part [16] asserts that as a **pair** — the
running building may stack, an idle sibling and a sibling researching something else may
not — because a test making only the first claim would pass for the dangerous version too.

The LEVEL needed no work at all, and this was verified rather than assumed: `startUpgrade`
computes `0xCD = currentLevel + 1` from the level array **at the moment it runs**, and
promotion goes through that same function. A queued Weapons is not "level 2"; it is "the
next level", resolved when it starts — which is also why it pays that level's own price
(`base + factor × level`, §5.1), measured offline at 175 and 250 for a 100/75 upgrade.

A level-headroom term (`running + queued + 1 <= maxLevel`) keeps the card honest, so presses
stop at the ceiling instead of being queued and dropped at promotion. Dropping them would
have been safe — no money moves — but it would have read as the feature losing them.

**And the headroom term alone was not enough, which cost one in-game run to find out.**
An upgrade's requirements are per LEVEL. The interpreter's opcode `0xFF1F` reads the player's
current level and *jumps to that level's own requirement block*:

```c
case 0xff1f:
  cVar6 = currentLevel(player, id);
  if      (cVar6 == 1) uVar7 = 0xff20;
  else if (cVar6 == 2) uVar7 = 0xff21;
  else                 uVar7 = 0xff1f;
  while (uVar1 != uVar7) { ++in_EAX; uVar1 = stream[in_EAX]; }   /* skip to that block */
```

So evaluating the condition with the level still at its present value asks "may level N+1 be
researched?" and gets **level N's answer**. A lone Engineering Bay with Infantry Weapons
level 1 running duly offered level 2 — and the engine's own gate then refused it at
promotion, because level 2 needs a prerequisite building the fixture did not have:

```
UPGQEV promote  unit=... kind=upgrade id=0 -> started, queuedLeft=1 minerals=2800
UPGQEV drop-gate unit=... kind=upgrade id=7 -- the engine's own gate refused it,
                 queuedLeft=0 (nothing to refund)
```

Nothing was lost and nothing was paid — the promotion-time gate is the backstop and it did
its job — but the card had promised something it could not deliver. So the level array is
**also** raised, for the length of the condition call, to the level this press is asking FOR
minus one. The engine then evaluates the requirement block that will actually apply and
answers −1 (greyed) or 0 by itself, which is the same answer vanilla gives a player who tries
to research level 2 without the prerequisite.

That is three temporary, restored-before-return writes in one call — `0xC9`, `0xC8`, the
in-progress bit and the level byte — and every one of them exists so the ENGINE, not the
plugin, decides the answer.

### 7.6 `SC_VA_STAT_DIRTY` redraws the status area, NOT the command card

Measured, at a cost of one in-game run. The plugin's first version asked for a redraw after
queueing an item the way `sc_prodqueue` does — `*(BYTE*)0x0068C1F8 = 1` — and the card did
not relay. The symptom was visible in the plugin's own counters before it was visible on
screen: `unblocked=2` for a whole run in which the card layout should have evaluated the
upgrade conditions many times over. The layout had run exactly once, right after the engine's
own accept tail set its five globals, and the controls had held the buttons assigned then
ever since — so at the cap the card went on offering an upgrade the plugin would have had to
refuse.

The five globals both handlers write after a successful accept (`0x004C1B78`…`0x004C1B8F`)
are the complete set, and writing all five is what relays the card:

```
0x0068C1B0 = 1   (u32)   the card
0x0068AC74 = 1   (u8)
0x0068C1F8 = 1   (u8)    the status area -- SC_VA_STAT_DIRTY
0x0068C1E8 = 0   (u32)
0x0068C1EC = 0   (u32)
```

So anything that changes what the card should OFFER — as opposed to what the status area
should draw — has to write `0x0068C1B0` as well. This is a general fact about the engine,
not a fact about this feature.

---

### 7.7 One entry per research per building (supersedes §7.5)

The unblock of §7.2(a) tells the card the building is idle, and the engine then answers for
the running item's absence. It has no memory of what the plugin HOLDS, so a held upgrade's
button stayed lit and every further press queued another copy of it — measured live: three
presses of Infantry Armor with Infantry Weapons running, three Infantry Armor entries
(`STATQ ... disp=1..3 enabled uicon=0x124`). §7.5's level stacking was the same button press,
read as a feature. The owner asked for it to be refused.

So `CondCommon` answers **0** — hidden, the value the engine itself returns for the running
item (§4.3) — for any id the building already holds, before the trampoline runs, and
`ScUpgQueueOnCommand` refuses a `0x32`/`0x30` for an id that is running or held here
(`refuse-dup`, consumed so the engine's body cannot start it over the running item). The
running item's own button needs nothing from the plugin: the per-player in-progress bit
(§4.2) hides it, and the plugin no longer touches that bit or the level array. Two
buildings researching the same upgrade is therefore back to being the engine's own rule,
untouched.

## 8. Known limitations

1. **Held items past four are a count.** The strip's four small icons draw the first four
   held items (§10); the rest are a `+N` on the empty fourth slot. A building that went idle
   with items held (waiting for money) is in the idle layout, which owns the strip, so the
   icons return when the next item starts.
2. **`0x32` Upgrade and `0x30` Tech only.** Unit training, morphs and addons keep vanilla's
   behaviour (`research/production-queue.md` is the other half).
3. **One building.** Not cross-building, and no auto-repeat.
4. **A queued item is not reserved.** Because nothing is paid until an item starts, a player
   who queues three upgrades and then spends the money elsewhere will find the queue waiting
   rather than researching. It resumes by itself as income arrives, and the `waitingCost`
   counter says it is doing so. This is the price of pay-at-start, and it is the right way
   round: the alternative reserves money the player may need.
5. **Single-player only**, like everything in this repo (AGENTS.md hard rule 3).

---

## 9. Reproducing this (the queue)

```powershell
# once: import + analyse into a persistent project (~4 min)
./tools/ghidra/sweep.ps1 -Mode Prepare -InputPE C:\decompile-sc-data\sc-work\1161-base\StarCraft.exe `
    -ProjectDir work/scratch/029/ghidra -LogFile work/scratch/029/ghidra/import.log

# the handlers, the button conditions and the emitters
foreach ($s in 'functions','callees','callees2','ticksites') {
  ./tools/ghidra/sweep.ps1 -Mode Run -ProjectDir work/scratch/029/ghidra -ProgramName StarCraft.exe `
      -Script DecompileMany.java `
      -ScriptArgs "work/scratch/029/upg-$s.tsv", "tools/ghidra/specs/upgrade-$s.spec", 240
}

# every instruction touching the four fields
foreach ($d in '0xC6','0xC8','0xC9','0xCD') {
  ./tools/ghidra/sweep.ps1 -Mode Run -ProjectDir work/scratch/029/ghidra -ProgramName StarCraft.exe `
      -Script FieldSweep.java -ScriptArgs "work/scratch/029/field-$($d -replace '0x').tsv", $d, any
}

# the live half: the wire and the card, one launch
./tools/plugin/probe-upgrade-wire.ps1
```

The `.c` outputs are whole decompiled functions — derived game content. They stay under
`work/scratch/` (gitignored) and only the findings above are committed (hard rule 1).

---

## 10. Drawing the held items: the research layouts, and the four icons they leave hidden

Derived with the same pipeline (§9), decompiles under `work/scratch/` (hard rule 1), and the
live child dump of the status pane (`QINDDLG`, `tools/plugin/probe-upgrade-queue-indicator.ps1`).

### 10.1 Which layout a researching building gets

Every building row of the per-unit-type status table `0x005193A0` (3 dwords per type, read
out of the binary for types 106, 111, 112, 113, 120, 122) carries the same pair: cond
`0x00425180`, act `0x00427890`. Neither is reached by a CALL — the dispatcher `0x00458120`
takes them out of the table — so auto-analysis never made them functions; `DisassembleAt.java`
recovered both. The act's dispatch, in order, for the local player's completed building:

```c
if (isTraining(unit))              /* 0x00401E70 */  queueLayout(ctrl);   /* 0x004268D0 */
else if (!lifting && !landing) {
    if (unit->0xC8 != 44)          techLayout(ctrl);      /* 0x004266F0 */
    else if (unit->0xC9 != 61)     upgradeLayout(ctrl);   /* 0x00426500 */
    else ...                       /* hangar, addon, the default single-unit layout (kind 3) */
}
```

So a researching building never runs `queueLayout`, and the two research layouts are the
whole picture of its strip.

### 10.2 What the research layouts write, and what they leave alone

`upgradeLayout` `0x00426500`, decompiled:

```c
if (layoutKind != 8) { hideAll(); showThrough(15); layoutKind = 8; }   /* 0x0068C1E5 */
setProgress(((upgradeTime(unit) - unit->0xC6) * 100) / upgradeTime(unit));
ctrl15 = child with index 15;
ctrl15->graphic = 2;
ctrl15->statUser->grp  = [0x0068C1E0];                    /* cmdicons.grp            */
ctrl15->statUser->icon = u16[0x00655AC0 + unit->0xC9*2]; /* upgrades.dat icon table */
ctrl15->statUser->mode = 5;
ctrl15->statUser->type = unit->0xC9;
enableControl(ctrl15);                                    /* 0x00418E00 */
if (!(ctrl15->flags & 1)) { ctrl15->flags |= 1; updateControl(ctrl15); }
... the "Upgrading" label out of the string table ...
```

`techLayout` `0x004266F0` is the same function with kind **7**, `u16[0x00656430 +
unit->0xC8*2]` (the `techdata.dat` icon table) and mode **4**. Three things follow:

1. **The icon tables.** `0x00655AC0` and `0x00656430` are named off these two reads and
   nothing else; both feed the same `statUser->icon` the queue strip's blit `0x00456C30`
   reads for a queued unit, out of the same `cmdicons.grp`. Both tables are filled from the
   MPQ at load (zero in the file image), so the cross-check is live: the probe compares the
   strip's frame for a held upgrade against the card button's own icon for it (§10.5).
2. **The four small queue icons are never touched.** Neither layout names ids 3..6. The
   live dump of a researching Engineering Bay's pane shows them `vis=0 flags=0x410` — hidden
   and NOT disabled, because `queueLayout` never ran for this building — with their rects
   exactly where the producing layout puts them (`(104,53,142,88)`, `(143,53,181,88)`,
   `(182,53,220,88)`, `(221,53,259,88)`), and id 15 visible at slot 0's own rect
   `(104,14,142,49)`.
3. **The hide-all runs on a KIND change, not per call.** `0x0068C1E5` is compared first and
   `hideAll` `0x00457310` (every child after id -7) runs only when it differs. The dispatcher
   zeroes the byte when the pane empties; the default single-unit layout writes 3, a foreign
   player's 4. So a control shown into a research layout stays shown until the kind changes.

### 10.3 What the plugin does with that

`sc_queueind.cpp`, after the HUD driver it already detours: while `0x0068C1E5` reads 7 or 8
and the portrait building holds items, fill ids 3..6 with the first held items using the five
fields above (mode 5 or 4 by kind, the border graphic `queueLayout` gives those slots, the slot
label) and `showControl` them; compare before every write, so a settled pane costs four reads;
take them down through `hideControl` when the item behind a slot goes. Past four held, three
icons and the existing `+N` on the empty fourth. Outside a research layout the icons are the
engine's and the count covers everything held.

### 10.4 The click

`statusCtrlActivate` `0x004573A0` switches on the control's own index: cases 2..6 emit
`{0x20, index-2}` (Cancel Train), case 15 emits `0x31` or `0x33` by layout kind. So a click on
a lit icon 3..6 is a Cancel Train for display 1..4 whose ring slot holds `0xE4`.
`cancelBuildQueueSlot` `0x00466A70`, decompiled, opens with `if (ring[(head+k)%5] != 0xE4)`
and otherwise returns — an empty slot is a no-op in the engine, not an out-of-bounds refund
as `research/production-queue.md` §8 feared. `sc_prodqueue`'s detour on `cmdrecvCancelTrain`
already owns the empty-slot case; it now hands display *k* to `ScUpgQueueCancelAt(k-1)`
before swallowing.

### 10.5 The oracle

`STATQ` (`Get-ScStatusQueue`) walks the five icons out of the statdata dialog: visible bit,
`statUser` frame/mode/type, rect. The probe asserts on that walk — one enabled icon per held
item, mode 4/5, a frame past the placeholder range, display 1's frame equal to the card
button's own icon for that upgrade — then clicks display 1 through `Get-ScStatusSlotPoint`
and requires `UPGQEV cancel-icon index=0`, one fewer held, and display 2 dark.

