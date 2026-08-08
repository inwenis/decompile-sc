# Replaying a dead unit: the fan-out's emit-side liveness gate

*Task 020. Derived from StarCraft.exe 1.16.1 (`AD6B58B2…88C6A46`), from the plugin's own
in-process observation on the task-019 combat fixture, and from the offline core tests in
`tools/plugin/src/hooktest.cpp` part [7].*

---

## 0. Verdict up front

1. **The fan-out could replay a unit that was dead.** Its emit gate compared `CUnit+0xA5`
   (uniqueness) and nothing else. That byte is written by ONE instruction in the binary,
   `0x004A03FD` inside the unit (re)init `0x004A0320`, so it moves on slot **reuse** and *not* on
   **death** ([`selection-circles.md`](selection-circles.md) §4.5). A damage-killed unit whose slot
   has not been recycled therefore still matched, and its tag went into a replayed `Select`.
2. **No check we can NAME on the receive path catches it.** `CMDRECV_Select` (`0x004C2750`)
   validates count ≤ 12, the index/uniqueness decode, `CUnit+0xA5`, a 12-bounded dedup and
   `unit->id != 14` — every one of which a fresh corpse passes — then hands the pointer to
   `addUnitToSelectionSlot` (`0x0049AF80`), whose first act per our decompile is to dereference
   `unit->sprite` (`CUnit+0x0C`) with no null test
   ([`binary-selection-map.md`](binary-selection-map.md) §5.1/§5.2). *In practice the engine does
   reject the entry* (point 3) — but from a check we cannot yet point at.
3. **Observed, not assumed: the pre-fix path is TOLERATED, not a fault** — §4. Measured in-process
   on the combat fixture with the gate deliberately switched off, on the worst form of the input: a
   dead unit whose `CUnit+0x0C` reads **`0x00000000`** at the moment its tag is written. The game
   does not crash, and the corpse does **not** enter `playersSelections` — the receive path
   rejects exactly the stale entries of the replayed `Select` and keeps the other ten. So this is a
   **correctness defect with an unproven safety margin**, not a crash. What is *not* settled is
   *which* receive-side check does the rejecting: our reading of `0x0049AF80` puts an unguarded
   null dereference in front of every predicate that could (§4.3).
4. **The fix is a five-term gate on the emit side**, supplying exactly what the receive side does
   not check: hitpoints, owner, sprite non-null, and reachability in `playerUnitList[owner]` — on
   top of the uniqueness test that was already there (§3).
5. It is proved offline per removal path (hooktest part [7], including a **pre-fix arm that
   asserts the defect still reproduces**) and in game on the task-019 combat fixture, where the
   first fanned order after a real combat death is read back off the wire (§5).

---

## 1. The defect, end to end

```
   drag box (36 lurkers)                         a lurker is shot dead
        |                                                |
        v                                                v
   sortOverflowHandler  ──► shadow list      CUnit+0x08 (hitpoints) := 0   [0x004797B0]
   CMDACT_Select        ──► (ptr, 0xA5, 0x4C)  CUnit+0xA5  UNCHANGED       [only 0x004A0320 writes it]
        |
        |  player presses Burrow
        v
   queueCommand hook ──► EmitSelect ──► tag = (0xA5 << 11) | index  ─────► the wire
                              ^                                              |
                     the ONLY gate, pre-020:                                 v
                     "is 0xA5 still what we captured?"      CMDRECV_Select 0x004C2750
                     -> YES, because death does not move it   count<=12, decode, 0xA5,
                                                              dedup, id != 14   ── all pass
                                                                     |
                                                                     v
                                                    addUnitToSelectionSlot 0x0049AF80
                                                    (*(byte*)(*(int*)(unit+0x0C)+0x0E) & 0x20)
                                                                     ^
                                                        a sprite belonging to a unit
                                                        that has been removed from play
```

The two halves of that picture were each already established before this task, in different
documents, and the defect is what falls out of putting them next to each other:

- **`CUnit+0xA5` does not move on death.** [`selection-circles.md`](selection-circles.md) §4.5,
  task 014, byte-level verified: one write site in the binary, `0x004A03FD`, inside the unit
  (re)init `0x004A0320`. Death runs `0x004A0740`, which does not touch it.
- **`0x0049AF80` dereferences the sprite unguarded.**
  [`binary-selection-map.md`](binary-selection-map.md) §5.1 tabulates its seven predicates against
  GPTP; the sprite read is
  `(*(byte*)(*(int*)(ESI+0xc)+0xe) & 0x20) != 0 → return 0`, i.e. `CUnit+0x0C` → `CSprite+0x0E`,
  bit `0x20` = *Hidden*. The only pointer test on the path is `unit != NULL`.

Task 017 closed the same exposure CLASS for the HUD row with three measures — hitpoints,
`InPlayerUnitList`, and a click gate ([`hud-selection-row.md`](hud-selection-row.md) §6.1). The
command path had none of them.

**It is reachable, and it was reached.** `tools/plugin/test-combat-death.ps1` (task 019) boxes 36
Lurkers, walks them into a computer-owned Hydralisk block, and waits for a death. Its own
pre-020 oracle was exactly this gap, stated from the other side: `UNITSTATE … live=36`
(uniqueness only) against `HUDROW show n=35` (HP-aware) at the same moment. The keypress that
test used to break off the engagement is a fanned order — so the pre-020 build replayed the dead
unit on the very next thing the fixture did.

---

## 2. What the receive side validates, and what it does not

`CMDRECV_Select` (`0x004C2750`) and `CMDRECV_ShiftSelect` (`0x004C2560`), per-entry, from
[`binary-selection-map.md`](binary-selection-map.md) §5.2/§5.3:

| # | check | what it rules out | what it does NOT rule out |
|---|---|---|---|
| 1 | `count <= 12` (`JA`, unsigned — §5.4) | a malformed count | — |
| 2 | `index & 0x7FF`, `× 0x150` into `0x0059CB58`, bounds | a pointer outside the unit array | — |
| 3 | `CUnit+0xA5 == tag >> 11` | a **recycled** slot | a **dead** unit — `0xA5` does not move on death |
| 4 | 12-bounded dedup over `playersSelections[player]` | the same unit twice | — |
| 5 | `unit->id != 14` | a Terran Nuclear Missile | — |
| 6 | → `0x0049AF80`: `unit != NULL`, `player < 8`, `slot < 12`, `!(unit->sprite->flags & 0x20)`, and for `slot > 0` `unit_IsStandardAndMovable` + `unit->playerId == ACTIVE_NATION_ID` | a hidden unit, a foreign unit in a non-first slot | **a NULL or stale `unit->sprite`** — it is dereferenced to make check 6 |

Row 3 and the last cell of row 6 are the whole of the problem. Everything the engine checks about
identity, it checks with a byte that death does not touch; and the one field it dereferences to
decide the rest, it dereferences before deciding anything about the unit's liveness.

*(That last clause is the table as decompiled. In practice the engine rejects such an entry
without faulting even when the sprite pointer is null — §4 measures it, and §4.3 says plainly
that we cannot yet name the check that saves it.)*

This is not a bug in the engine. Vanilla's own senders cannot produce that entry: the client
builds a `Select` out of `clientSelectionGroup`, and the removal path `0x004A0740` takes a dying
unit out of every selection array (`0x0049A7F0`, `0x0049F7A0`) before anything can re-send it.
**Our fan-out is a sender vanilla does not have** — it holds a list across time, which is exactly
the thing the engine's own design never does. The obligation to check therefore lands on us.

---

## 3. The gate

`tools/plugin/src/sc_fanout.cpp`, `UnitLive()`. Five terms, evaluated cheapest-first, every one of
them a field this repo has already derived:

| # | term | address | catches | evidence |
|---|---|---|---|---|
| 1 | `CUnit+0xA5` == captured | `0xA5` | slot **recycled** into a different unit | [`selection-circles.md`](selection-circles.md) §4.5 (single write site `0x004A03FD` in `0x004A0320`) |
| 2 | `CUnit+0x08` != 0 | `0x08` | **damage death**, slot not yet recycled | the damage primitive `0x004797B0` drives it to 0 on a kill ([`command-opcodes.md`](command-opcodes.md) §6); nothing resets it until re-init |
| 3 | `CUnit+0x4C` == captured | `0x4C` | the unit **changed hands** (mind control relinks it under a new owner) | [`hud-selection-row.md`](hud-selection-row.md) §6.1 |
| 4 | `CUnit+0x0C` != 0 | `0x0C` | nothing for the receive path to dereference | `0x0049AF80` reads `*(int*)(unit+0x0C)` unguarded ([`binary-selection-map.md`](binary-selection-map.md) §5.1) |
| 5 | reachable in `playerUnitList[CUnit+0x4C]` | `0x006283F8`, links `+0x68`/`+0x6C` | **removal from play by ANY path** | `0x004A0320` head-inserts, `0x004A0740` unlinks ([`hud-selection-row.md`](hud-selection-row.md) §6.1) |

Terms 2 and 5 divide a death between them, and the split is the reason both are needed:

```
   shot dead            death animation           removal 0x004A0740        slot re-init 0x004A0320
      |                        |                          |                          |
      v                        v                          v                          v
  hp := 0  ───────────── still linked ──────────── UNLINKED from ──────────── 0xA5 bumped,
                          in the list              playerUnitList             fresh sprite
      |<------- term 2 ------->|<--------- terms 2 and 5 --------->|<------- term 1 ------->|
```

and term 5 alone covers the removals that are **not** deaths at all — trigger `RemoveUnit`, an
archon merge consuming its two templars — which leave hitpoints and `0xA5` both untouched.

### 3.1 Why the list walk belongs here, when task 017 kept it out of the row's per-frame path

`sc_hudrow`'s `UnitAlive` is uniqueness + hitpoints only; the list walk lives in its **click gate**
([`hud-selection-row.md`](hud-selection-row.md) §6.1). That was the right call *there*, and the
argument does not carry over:

| | HUD row (task 017) | command path (task 020) |
|---|---|---|
| how often the check runs | **every frame**, per displayed unit | **once per fanned order**, per shadow unit |
| what happens if a stale unit slips through | it is drawn for one frame — "wrong-but-harmless pixels" (§6 of the row doc) | its tag reaches `0x0049AF80`, whose only predicate we can read in front of the rejection is an unguarded dereference of its sprite (§4.3) |
| structural backstops | the divergence latch (engine selection vs visible tail) **and** the click gate | **none** — `EmitSelect` writes straight to the wire |

So the row could afford to detect death and let *structure* catch every other removal path; the
command path has no structure between the shadow list and the receive side, so it has to detect.
The cost argument also inverts: a walk bounded by `SC_MAX_UNITS_WALK` (2000), for ≤ 250 units,
once per order the player types by hand, is not in the same class as the same walk per unit per
frame. Every link is bounds/stride-validated before it is followed, so a torn or corrupt list
returns `false` (fail-closed) instead of faulting or spinning.

### 3.2 What the gate deliberately lets through

A **transport-loaded** unit stays linked in its player's list (the engine walks that list for
supply, loaded units included) and keeps hitpoints and owner. It passes terms 1–5 and its tag goes
out — and that is correct, because the engine's *own* check catches it: `0x0049AF80` rejects a
unit whose `sprite->flags & 0x20` (*Hidden*) is set, which is precisely what a loaded unit is.
Term 4 is what makes that safe to rely on: the engine only gets to run its Hidden check if the
sprite pointer it reads is a real one.

---

## 4. Does the pre-fix path FAULT, or is it silently tolerated?

**Answer: TOLERATED.** The engine does not crash, and the corpse does not enter the simulation's
selection — the receive path rejects exactly the stale entries of a replayed `Select` and keeps the
rest. That is measured, not argued, and it is measured on the *worst* form of the input: a unit
whose `CUnit+0x0C` reads **`0x00000000`** at the moment its tag is written to the wire.

It matters that this is the answer, because it sets how loudly the defect reads. It is a
**correctness defect with an unproven safety margin**, not a crash: the fan-out was sending
entries the engine had to throw away, and the one instruction our reading of that path puts in
front of the throwing-away is an unguarded null dereference.

### 4.1 How it was observed

Both arms are the same script on the same fixture, differing only in
`%SCPLUGIN_FANOUT_LIVENESS%`; the plugin logs the fields the receive path would use at the exact
moment a tag is (or is not) written, and the observer thread independently logs the engine's own
selection arrays every 250 ms.

```powershell
./tools/plugin/test-combat-death.ps1                 # gate ON  -> the unit is refused
./tools/plugin/test-combat-death.ps1 -Liveness 0 `   # gate OFF -> the unit is replayed
    -LogPath 'C:\sc-work\logs\020-defect-arm.log'
```

**Arm A — the gate ON.** 36 Lurkers boxed, walked into the Hydralisks, one dies; 1.2 s later the
Burrow keypress fans out:

```
19:05:37.930  HUDROW stock restored (n=35)
19:05:38.586  UNITSTATE [at-the-death] n=36 live=35 … uniqOnly=36 recycled=0 hp0=1 … liveness=1
19:05:39.086  FANOUT stale drop: unit=0x00621068 tag=0E4D why=hp0 hp=0 uniq=1/1 player=0/0
                                 sprite=0x00000000 spriteFlags=-1 inList=0
19:05:39.088  FANOUT select: in=12 out=11 dropped=1 tags=[0E52 0E50 0E4F 0E4E 0E53 …]
```

`uniq=1/1` is the whole point: the byte the engine checks *still matches*, so nothing on the
receive side would have questioned this tag. `sprite=0x00000000` is the field it would have
dereferenced. `inList=0` says the removal path `0x004A0740` had already run.

**Arm B — the gate OFF, same fixture, same keypress.** The tag goes out:

```
19:19:53.991  HUDROW stock restored (n=35)
19:19:55.056  FANOUT REPLAYING A STALE UNIT (gate off): unit=0x00621848 tag=0E53 why=hp0 hp=0
                                 uniq=1/1 player=0/0 sprite=0x00000000 spriteFlags=-1 inList=0
19:19:55.056  FANOUT select: in=12 out=12 dropped=0 tags=[0E52 0E50 0E4F 0E4E 0E4D 0E53 0E51
                                 0E57 0E5D 0E59 0E60 0E5F]        <- 12 tags, two of them stale
19:19:55.926  playersSelections[0] [0]=0x006216F8 [1]=0x00621458 [2]=0x00621308 [3]=0x006211B8
                                 [4]=0x006215A8 [5]=0x00621D88 [6]=0x00622568 [7]=0x00622028
                                 [8]=0x00622958 [9]=0x00622808   <- TEN entries
```

Decoding the twelve tags we sent through `unit = 0x0059CCA8 + (index − 1) × 0x150` and comparing
with the ten pointers the engine ended up holding:

| tag | index | unit | in `playersSelections` afterwards? |
|---|---|---|---|
| 0E52 0E50 0E4F 0E4E 0E51 0E57 0E5D 0E59 0E60 0E5F | 1618 1616 1615 1614 1617 1623 1629 1625 1632 1631 | `…16F8 …1458 …1308 …11B8 …15A8 …1D88 …2568 …2028 …2958 …2808` | **yes, all ten** |
| **0E53** | 1619 | `0x00621848` — the unit the forensics line names | **no** |
| **0E4D** | 1613 | `0x00621068` — alive at emit, dead by execution | **no** |

The ten survivors of our chunk are *exactly* the ten non-stale tags, in the engine's own order. So
the replayed `Select` really was executed (it is also what made 33 units burrow), and the receive
path **rejected precisely the two stale entries and nothing else**. The process ran on through the
rest of the test — a 45 s soak, another fanned order, a clean `WM_CLOSE` exit with
`DLL_PROCESS_DETACH` — and `StarCraft.exe` on disk was byte-identical before and after.

### 4.2 The window has two halves, and both were hit

```
   hitpoints := 0        removal 0x004A0740          slot re-init 0x004A0320
   (row drops it)        (unlink, CUnit+0x0C := 0)   (0xA5 bumped)
        |                          |                          |
   [-- dead, still there --][-- dead and gone --------][ recycled ]
        ^                          ^                          ^
   sprite still valid;      sprite pointer NULL;        the engine's own
   engine reads it fine     this is where the           uniqueness test
                            static model says it        finally fires
                            faults -- and it does not
```

Which half a run lands in is not under the fixture's control — it depends on how long the row's
poll took to notice the death. An earlier defect-arm run landed in the **left** half (the dead
unit's pointer was still in `clientSelectionGroup` when the order went out): benign, as expected.
The run quoted in §4.1 landed in the **right** half — `sprite=0x00000000`, `inList=0` — which is
the case the static model says is a null dereference. It is not one. `-OrderDelaySec` on the test
script exists so a future run can be aimed at the right half on purpose rather than by luck.

### 4.3 What this does NOT settle

Our reading of `0x0049AF80` ([`binary-selection-map.md`](binary-selection-map.md) §5.1) puts
`!(unit->sprite->flags & 0x20)` — i.e. `*(byte*)(*(int*)(unit+0x0C)+0x0E)` — *before* every
predicate that could plausibly reject a corpse. With `CUnit+0x0C` measured at 0, that read is
`[0x0000000E]` and should fault. It did not. So one of two things is true, and this task did not
distinguish them:

1. the runtime instruction order differs from the decompiled/GPTP source order, and something
   that *does* reject a removed unit (`unit_IsStandardAndMovable` `0x0047B770`, or a null-sprite
   test the condensed decompile does not show) runs first; or
2. the entry is rejected earlier still, inside `CMDRECV_Select`, by a check we have not read.

The experiment that would settle it is a detour on `0x0049AF80` itself, logging its argument and
return per call. That is a new hook in game memory and was out of scope here.

**The fix does not depend on which it is.** A sender that hands the engine entries it has to throw
away is wrong whatever the engine does with them, and the only reading we have of that path
contains a dereference we can prove is null. The gate makes the question moot from our side.

### 4.4 A limit the gate cannot remove

`0E4D` in the table above was **alive when we wrote its tag** and dead by the time the command
executed — the engine rejected it too. Commands are queued, not executed inline, so no emit-time
check can close the window completely; a unit can always die in the few frames between
`queueCommand` and the receive dispatcher. What the gate removes is the part of the window we
control, which is the part that is *seconds* long (a unit that died before the player even pressed
the key), leaving only the part that is frames long — and which the engine demonstrably handles.

---

## 5. What was tested, and how

### 5.1 Offline, byte-exact — `hooktest.exe` part [7]

No StarCraft in the process: a fake 3 MB module image, units synthesised at the real 336-byte
stride, the three core entry points called in the order the engine calls them, and the exact bytes
the core would have queued captured and asserted. Each case breaks **exactly one** term and names
the reason the gate must report, so "it was dropped" and "it was dropped for the right reason" are
different failures:

| case | what is broken | asserted |
|---|---|---|
| slot reuse | `CUnit+0xA5` += 1 on three units | dropped, all three charged to `recycled`, byte count falls by exactly 3 tags |
| **damage death** | `CUnit+0x08` := 0, **`0xA5` left alone** | uniqueness byte verified unchanged first; the tag is in NO emitted `Select`; 35 of 36 go out; charged to `hp0` |
| **pre-fix arm** | same unit, gate switched to uniqueness-only | the dead tag **does** reach the wire, 36 of 36 go out, `staleSkipped == 0` |
| removed from play | unlinked from `playerUnitList` | HP and `0xA5` verified untouched first; tag in no `Select`; charged to `removed` |
| ownership change | `CUnit+0x4C` := 2 | tag in no `Select`; charged to `foreign` |
| no sprite | `CUnit+0x0C` := 0 | tag in no `Select`; charged to `nosprite` |
| everybody died | all 36 at HP 0 | the fan-out is **not** suppressed, so the player's own order still goes out, and no `Select` is emitted for a corpse |

The pre-fix arm is the one that makes the rest mean anything: an assertion that cannot fail is not
evidence.

### 5.2 In game — `tools/plugin/test-combat-death.ps1`

The task-019 fixture: 36 Lurkers at 30% hit points boxed as one selection, walked east into six
computer-owned Hydralisks, no triggers and no AI script. An unburrowed Lurker has no weapon, so
the deaths arrive as a trickle rather than as the outcome of a fight, and the selection stays over
the 12-unit cap throughout.

Step [8], added by this task, fires on the first fanned order after a death — the Burrow keypress
the fixture already used to break off the engagement — and reads the result **off the wire**, from
the emit path's own read-back (`FANOUT select:` carries every tag written; `FANOUT stale drop:`
every unit refused, with the fields the receive path would have used):

* the keypress fanned out through our hook;
* at least one unit was refused, **on hitpoints** (`why=hp0`), and every `hp0` drop really did read
  zero;
* **not one of those tags is in any emitted `Select`** — the regression assertion;
* the refused unit is one the HUD row itself listed before the fight, read out of the live dialog
  (so the claim is not the fan-out marking its own homework);
* from the counter side, marker-synchronised in-process: `staleSkipped > 0`, the shadow list still
  holds all 36, `uniqOnly == 36` (uniqueness alone still accepts every one) and `live < uniqOnly`.

One green run, verbatim (2026-08-08; seven units had died by the time the keypress landed):

```
[8] PHASE B: THE 020 FIX -- the first fanned order after a death does NOT replay the dead unit
     DROPPED: FANOUT stale drop: unit=0x00623528 tag=0E69 why=hp0 hp=0 uniq=1/1 player=0/0
                                 sprite=0x00000000 spriteFlags=-1 inList=0
     ... (seven of them, every one hp=0, every one uniq=1/1) ...
     emitted 29 tags across 3 Select(s)
ok   the gate refused at least one unit, and did it on HITPOINTS (7 of 7 drops were hp0)
ok   no dead unit's tag reached the wire (dead tags: 0E53 0E5F 0E60 0E65 0E67 0E69 0E6D)
ok   the dead unit is one the row itself listed before the fight (7 of 7)
     UNITSTATE [after-the-fanned-order] n=36 live=27 ... uniqOnly=36 hp0=9 staleSkipped=7 liveness=1
ok   staleSkipped is above zero (7)
ok   uniqueness alone still accepts them all (uniqOnly=36) -- the case CUnit+0xA5 cannot see
test-combat-death: 0 failure(s) in 04:06
```

`uniqOnly=36` against `live=27` in one line, from one read of one list, is the defect and the fix
in the same sentence: the test the fan-out used to apply accepts all 36 of them; the one it applies
now does not; and the 29 tags that went out contain none of the nine.

It is capable of failing, and was shown to fail: the same script with `-Liveness 0` fails exactly
the three assertions that carry the claim (`the gate refused at least one unit`, `the dead unit is
one the row itself listed`, `staleSkipped is above zero`) while every other assertion in the file
still passes — `test-combat-death: 3 failure(s)`. That run is §4's arm B.

### 5.3 The gate does not break the feature

A liveness test that is too eager costs the fan-out its whole point, so every in-game suite was
re-run against it. All five green on 2026-08-08:

| suite | what it holds down | result |
|---|---|---|
| `test-selection-circles.ps1` | circles under the over-cap units; one order still reaches every unit | 0 failures |
| `test-fanout-orders.ps1` | Hold Position, Stop, Targeted Order each reach all 36; nothing outside the policy set fans out | 0 failures |
| `test-burrow-fanout.ps1` | one untargeted-ability keypress reaches all 36 | 0 failures |
| `test-hud-row.ps1` | the paged row over the shadow list | 0 failures |
| `test-combat-death.ps1` | the death path, and §5.2 | 0 failures |

The idle phase of each is the direct check that no term is a false-positive machine: 36 boxed
units, `UNITSTATE … live=36 … uniqOnly=36 recycled=0 hp0=0 foreign=0 nosprite=0 removed=0`. All
five terms agree with the uniqueness test when nothing has happened, which is the only time they
should.

---

## 6. Confidence and method

### Derived here, from this binary
* Nothing new. Every address and offset this task acts on was already derived and evidenced by
  tasks 011, 014, 015 and 017; what is new is the **consequence** of putting `0x004A03FD`'s
  write-on-reuse-only behaviour next to `0x0049AF80`'s unguarded sprite dereference, and the gate
  that follows from it.

### Derived here, from the live game (in-process, on the combat fixture)
* A unit removed from play reads `CUnit+0x0C == 0` while `CUnit+0xA5` still matches its captured
  value — §4.1. The instruction that zeroes `+0x0C` was **not** traced; only the value was observed.
* The receive path **rejects** a replayed tag for such a unit and does not fault: the ten
  non-stale tags of a twelve-tag chunk land in `playersSelections` and the two stale ones do not
  — §4.1. Which check rejects them is open (§4.3).
* The dead-but-still-linked window and the removed-but-not-recycled window are both real, both
  short, and both were replayed into (§4.2).
* The five-term gate accepts 36 of 36 live units in a real mission (the fixture's idle phase
  reports `live=36`), so no term of it is a false-positive machine.
* A unit can die between `queueCommand` and execution, and the engine handles that on its own
  (§4.4) — no emit-time gate can be complete.

### Inherited and used as-is
* `playerUnitList` at `0x006283F8` with links `+0x68`/`+0x6C`, and the claim that `0x004A0740`
  unlinks — from task 017 ([`hud-selection-row.md`](hud-selection-row.md) §6.1). The array's
  element count is still not evidenced; the walk reads only indices `< 8`, which is fail-closed
  for any size.
* `CUnit+0x08` = hitpoints — GPTP, corroborated by `0x004797B0`
  ([`command-opcodes.md`](command-opcodes.md) §6).

### Open
* **Which receive-side check rejects a removed unit`s tag** — §4.3. The decisive experiment is a
  detour on `0x0049AF80` logging its argument and return per call. Until then, the claim "the
  sprite read is unguarded" rests on a decompile whose predicate ORDER the runtime contradicts.
* **Which instruction zeroes `CUnit+0x0C`.** Observed, not traced. It does not change the gate —
  term 4 is a value test — but it would settle whether the null is written by `0x004A0740` itself
  or by the sprite-free path it calls.
* **How long the dead-but-linked window is, in frames.** Measured only as "under ~1.2 s" on one
  fixture (§4.2). It decides which half of the window a given replay lands in.
* **Whether `0x0049AF80` is the only unguarded dereference on the receive path.** The other
  receive handlers were not re-read for this task; `CMDRECV_ShiftSelect` inlines `0x0049AF80`
  ([`binary-selection-map.md`](binary-selection-map.md) §5.3) and so carries the same read, but the
  non-selection opcodes were not audited.

### Reproducing this

```powershell
./tools/plugin/build.ps1 -Test                      # offline: hooktest part [7]
./tools/plugin/test-combat-death.ps1                # in game: the fix, green
./tools/plugin/test-combat-death.ps1 -Liveness 0 `  # in game: the defect, RED by design
    -LogPath 'C:\sc-work\logs\020-defect-arm.log'
```

---

## 7. Revision log

* **2026-08-08 (task 020)** — first version: the defect, the receive-side audit, the five-term
  gate, and the in-process determination of what the pre-fix path actually does.
