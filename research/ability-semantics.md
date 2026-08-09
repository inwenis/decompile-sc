# What an ability with a PER-UNIT COST does to a >12 selection, and two "it stopped attacking" reports

Analysis date: 2026-08-09 (task 022). Target: `StarCraft.exe`, StarCraft: Brood War 1.16.1
(classic), SHA-256 `AD6B58B27B8948845CCFA69BCFCC1B10D6AA7A27A371EE3E61453925288C6A46` — the
project's disposable working copy `C:\sc-work\1161-base`, hash checked before and after every
run in this document.

This is an AUDIT, opened by three things the user saw while playing the fan-out build:

1. *"if I apply steam to ferdinarines will all of them get steam and will all of them have HP
   decreased"* — do abilities really reach every unit of a >12 selection, **including their
   per-unit costs**?
2. *"there was a moment where sunken didn't attack my medic and I'm not sure if it's a bug that
   we introduced or I just saw something wrong."*
3. *"when i played a cloacked ghost did not attack enemies at some point - check that if we
   might have changed that behav."*

Companion to [`command-opcodes.md`](command-opcodes.md), which established the fan-out policy
and stated §6 that the engine has no spell arbitration. This document tests the part that
document could only assert: that the **costs** scale the same way the effects do.

---

## 0. Verdict up front

1. **Yes to both halves of question 1, and the engine — not the plugin — decides who is
   skipped.** At 36 selected Marines, one Stim keypress gave the effect to all 24 units that
   could afford it and charged each of them 10 hit points individually; the 12 that could not
   afford it got nothing and paid nothing. The split falls on the **hit-point** line, not on the
   visible/overflow line. §2, §5.
2. **Stim's affordability gate and its cost are the same constant, and the test is strictly
   greater** (`CMP dword [unit+8],0xa00 / JLE skip`, then `MOV EAX,0xa00`). A unit can never
   kill itself with Stim: three presses walk a Marine from 40 HP to exactly 10 and the fourth
   does nothing at all. §2, §5.1.
3. **There is a SEND-side gate as well as the receive-side one**, which nothing in this project
   had noticed: with no unit in the selection able to pay, the client's own command card does not
   emit the command at all. §5.2.
4. **The energy family (`0x21`) has exactly the same shape**: a per-unit affordability test and a
   per-unit deduction, in `0x00491B30`. A caster that cannot pay is skipped by the engine and
   never gets the secondary order. §3.
5. `CUnit+0x115` is the **stim timer** and `CUnit+0xA2` is **energy**, both derived here from
   this binary rather than inherited. §2.1, §3.
6. Questions 2 and 3 are answered by plugin-vs-stock comparison on the same fixture, with the
   same read-only oracle in both arms. §6, §7.
7. Three **harness** faults were found on the way, one of which had been silently corrupting
   every in-game suite on this machine. §8.

---

## 1. Method

Everything below is either read off instructions in this binary (Ghidra headless, persistent
project) or read out of the live process by the plugin's own read-only scans. Two oracles:

| oracle | what it walks | works in `-Mode observe`? |
|---|---|---|
| `UNITSTATE` (task 015, extended here) | the fan-out's **shadow list** — the whole pre-cap selection | no: it needs the hooks |
| `WORLD` (**new here**) | the **engine's own** per-player unit lists (`playerUnitList`, `CUnit+0x6C`) | **yes** — it installs no hook |

The `WORLD` scan exists because questions 2 and 3 are comparisons against stock, and an oracle
that only exists on one side of a comparison cannot make it. It is the task-008 observer pointed
at a different global: `SafeRead` for every field, every link bounds/stride-validated, the walk
bounded, and **the count taken twice and both reported** — so a sample torn by the game thread
editing the list while the observer walks it is visible as `units=13 recount=12` rather than
mistaken for a unit that died. One line per unit, carrying hit points and the stim timer
together, because "it gained the effect AND it paid" is a joint property of one unit and two
separate histograms can only ever imply the pairing.

`UNITSTATE` grew three fields for this task — `stimmed=n/m`, `hp=[…]`, `stim=[…]`, `energy=[…]`
— appended, never inserted, so readers written against the task-015/020 line still work.

---

## 2. Stim (`0x36`): the gate and the cost are the same constant

`command-opcodes.md` §6 already said `0x36` costs the acting unit HP and gated on
`0xa00 < unit+8`. This task read the whole handler, because the audit needs the exact cost and
the exact comparison, not their existence.

`FUN_004c2f30`, decompiled:

```c
void FUN_004c2f30(void) {
  selectionIterator = 0;
  u = getActivePlayerNextSelection();
  while (u != 0) {
    if ((FUN_0046dd80(activePlayerId) == 1) && (0xa00 < *(int *)(u + 8))) {
      ...
      FUN_0048ed50(1,0);
      FUN_004797b0(0,0xffffffff,1);            /* the damage primitive */
      if (*(byte *)(u + 0x115) < 0x25) {
        *(undefined1 *)(u + 0x115) = 0x25;
        FUN_00454310();
      }
    }
    u = getActivePlayerNextSelection();
  }
}
```

The decompiler cannot show the register arguments of the damage call, and those are the whole
question, so here is the disassembly of the two places that matter
(`work/scratch/022/decomp/stim-listing*.tsv`, `ListingDump.java`):

```
0x004C2F68  81 7E 08 00 0A 00 00   CMP dword ptr [ESI + 0x8],0xa00     ; hit points vs 10.0
0x004C2F6F  0F 8E 84 00 00 00      JLE 0x004c2ff9                      ; <= 0xa00 -> skip this unit
...
0x004C2FD4  B8 00 0A 00 00         MOV EAX,0xa00                       ; the amount
0x004C2FD9  8B CE                  MOV ECX,ESI                         ; the unit
0x004C2FDB  E8 D0 67 FB FF         CALL 0x004797b0                     ; damage primitive
0x004C2FE0  8A 8E 15 01 00 00      MOV CL,byte ptr [ESI + 0x115]
0x004C2FE6  B0 25                  MOV AL,0x25
0x004C2FE8  3A C8                  CMP CL,AL
0x004C2FEA  73 0D                  JNC 0x004c2ff9                      ; already >= 0x25 -> leave it
0x004C2FEC  88 86 15 01 00 00      MOV byte ptr [ESI + 0x115],AL       ; else set the timer
```

Three facts fall out, and all three are checked in game in §5:

- **The cost is `0xa00`** — 10 hit points at the engine's 1/256 fixed point.
- **The gate is the same constant, tested strictly** (`JLE` skips on equality). So the unit that
  pays always has hit points left: **Stim cannot kill**. A unit at exactly 10 HP is skipped.
- **The effect does not stack**: the timer is *raised to* `0x25`, never added to. The cost,
  however, is paid on every press — pressing Stim twice in a row costs 20 HP and buys the same
  duration.

`0x004797B0` is the damage primitive (`command-opcodes.md` §6 decompiled it): it subtracts EAX
from `CUnit+0x08` and runs the death path if the amount is not smaller. Neither it nor the
handler touches `0x00467250`/`0x00468280`, so nothing player-global moves — this is a cost paid
by each acting unit out of its own body, which is exactly why it scales with the selection.

### 2.1 `CUnit+0x115` is the stim timer

Not inherited — derived here, three ways:

1. The `0x36` handler sets it to a fixed duration immediately after the unit pays the ability's
   cost, and only if it is currently lower (a refresh, not a stack).
2. `FieldSweep.java` over the whole binary finds **16 instructions** touching this displacement
   (`work/scratch/022/field-115.tsv`). One of them, `0x00492F70`, is a block of per-unit
   countdowns — `+0x114`, `+0x115`, `+0x116`, `+0x117`, `+0x118`, `+0x119`, `+0x11A`, `+0x11B`,
   `+0x124` — each decremented and each calling something on reaching zero:

   ```c
   if ((*(char *)(u + 0x115) != '\0') &&
      (c = *(char *)(u + 0x115) + -1, *(char *)(u + 0x115) = c, c == '\0')) {
     FUN_00454310();
   }
   ```

   **It calls the same `0x00454310` the setter calls.** A field set to a duration, ticked down,
   and passed to the same "this unit's state changed" refresh at both ends is a timer for that
   state.
3. A second, independent site — `0x004554A0` — has the identical shape (`0xa00 <` gate, damage
   primitive, `[+0x115] = 0x25`), i.e. the engine's other route to the same ability.

The value the plugin reads back in game is `0x25` immediately after the press and lower a second
later, which is the fourth confirmation and the one that is not static (§5).

---

## 3. The energy family (`0x21`): the same shape, in a different currency

`command-opcodes.md` §6 flagged `0x21` as the untargeted family that costs the caster energy.
The audit needs its gate, because "what happens to units without enough" is half of the user's
question. `FUN_00491b30`, called per unit by the `0x21` handler `0x004C0720`:

```c
void FUN_00491b30(void) {          /* EAX = the unit */
  if ((*(uint *)(u + 0xdc) & 0x100) == 0) {          /* not already in this state */
    id = *(short *)(u + 100);                        /* unit type -> which tech */
    if (id==1 || id==0x10 || id==100 || id==99 || id==0x68 || id==0x33) tech = 10;
    else if (id==8 || id==0x15)                      tech = 9;
    else                                             tech = 0x2c;
    cost = *(short *)((int)&DAT_00656380 + tech * 2);
    if ((cheatFlag) || ((ushort)(cost * 0x100) <= *(ushort *)(u + 0xa2))) {   /* CAN IT PAY? */
      if (!cheatFlag) *(short *)(u + 0xa2) += cost * -0x100;                  /* IT PAYS */
      if (*(char *)(u + 0xa6) != 'm') {              /* 0x6D */
        *(undefined1 *)(u + 0xa6) = 0x6d;            /* the secondary order */
        ...
      }
    }
  }
}
```

So, per unit and nothing else: a type-indexed cost from a table at `0x00656380`, an
affordability test `cost * 0x100 <= CUnit+0xA2`, a deduction of exactly that, and only then the
secondary order. **A caster that cannot pay is skipped by the engine and does not get the
secondary order** — the same shape as Stim's hit-point gate, which is the answer to "what
happens to units without enough".

`CUnit+0xA2` is therefore energy in the same 1/256 fixed point (a 200-energy caster reads
`0xC800`, which is what the live scans show), and `CUnit+0xA6` is the secondary order id, which
[`command-opcodes.md`](command-opcodes.md) §7.1 had already named from a different site.

Tech ids 9 and 10 are Cloaking Field (Wraith) and Personnel Cloaking (Ghost); `0x2c` = 44 is
past the 44 techs the CHK format knows about, i.e. the "no cloak for this type" fallback.

---

## 4. Fixtures: what had to be built before any of this could be tested

Every ability in vanilla StarCraft that costs the acting unit something **needs research**:
Stim Packs, both cloaks, Siege Mode. Burrow is the single exception, and only for Lurkers —
which is exactly why task 016's fixture used Lurkers, and why no fixture in this project could
test a per-unit **cost** at all before this task.

Two additions to `tools/make_test_map.py` fix that, both asserted by its validator:

| flag | what it does | why the question needs it |
|---|---|---|
| `--tech-researched <tech>` | writes `PTEx`: marks a tech available **and** already-researched for the human slot, with `playerUsesDefault` cleared | without it the command card has no ability button on it at all |
| `--damaged-count N --damaged-hp P` (and `--damaged-energy P`) | the **last N units of the same block** are placed at P% instead | payers and non-payers must be in **one** selection, reached by **one** keypress, or "the engine skipped the poor ones" cannot be told apart from "the plugin sent a different set that time" |

`PTEx`'s layout is the Brood War 44-tech one from the staredit.net CHK spec, and it is confirmed
by arithmetic rather than assumed: `44*12 + 44*12 + 44 + 44 + 44*12 == 1672`, which is exactly
the section's size in the template on disk. The generator refuses a template without it.

The pre-damaged tail is the **tail** on purpose. The fan-out emits the engine's visible twelve
LAST and the overflow chunks first, and the generator builds the block row-major from the
top-left, so the damaged units land in the part of the box the engine does **not** hold. If a
split ever came out along the visible/overflow line instead of along the hit-point line, that
would be ours — the layout is what makes the two hypotheses produce different numbers.

---

## 5. Question 1, in the live game, at 36 units

`tools/plugin/test-stim-fanout.ps1`, unattended, **0 failure(s)**, run of 2026-08-09. 36 Marines:
24 at full health and 12 pre-damaged to 25%, which for a 40-hit-point Marine is **exactly 10 HP
= 0xa00, the gate constant itself**. One Stim keypress, then three more.

Verbatim from `C:\sc-work\logs\022\stim-fanout.log`, nothing elided between the lines shown:

```
UNITSTATE [boxed]   n=36 live=36 visible=12 overflow=24 orders=[0x03:36] types=[0x00:36]
                    stimmed=0/36 hp=[0xA00:12 0x2800:24] stim=[0x00:36] energy=[0xC800:36]
CMD id=0x36 len=1 bytes=[36]
FANOUT start: cmd=0x36 len=1 units=36 (visible 12 + overflow 24) -> 3 Select+order pairs
FANOUT done: 3/3 chunks emitted, 81 bytes this turn
UNITSTATE [stim-1]  n=36 live=36 visible=12 overflow=24 ... stimmed=24/36 hp=[0xA00:12 0x1E00:24] stim=[0x00:12 0x1F:24]
UNITSTATE [stim-2]  n=36 live=36 visible=12 overflow=24 ... stimmed=24/36 hp=[0xA00:12 0x1400:24] stim=[0x00:12 0x20:24]
UNITSTATE [stim-3]  n=36 live=36 visible=12 overflow=24 ... stimmed=24/36 hp=[0xA00:36]          stim=[0x00:12 0x1F:24]
```

Read it as: `0x2800` (40 HP) → `0x1E00` (30) → `0x1400` (20) → `0xA00` (10), for exactly 24
units, while 12 units stay at `0xA00` throughout and never carry a timer.

The assertions that make those numbers mean something, all of them per unit and matched by
`CUnit*` across scans:

1. **24 units gained the effect, and 24 > 12.** The engine holds twelve (`visible=12`,
   `overflow=24`, both asserted), so a count above twelve is unreachable without the fan-out.
2. **Every unit that gained the effect paid**, individually, `0xa00` per press — asserted
   against `0x2800 - N*0xa00` on each of three presses, not against a group total. A group total
   is satisfied by one unit paying everything.
3. **Every unit that could not pay gained nothing and paid nothing**, and stayed at exactly the
   gate value.
4. **The split is along hit points, not along the cap.** 24 payers and 12 skipped, while the
   engine's own selection is 12 and the overflow is 24 — the two partitions are different, and
   the one the engine's gate predicts is the one that happened.
5. **Nothing drifts on its own**: 30 s of no input with the count still `0/36` and every hit
   point unchanged. Terran units do not regenerate, which is why the fixture is Marines and not
   a Zerg unit that would climb back over the gate while the test watched.

### 5.1 Stim cannot kill, and the boundary is where the disassembly says it is

Three presses land the payers on exactly `0xa00` — the gate value — and the **fourth press
changes nothing**: 36 units, all alive, all still at `0xa00`. If the gate were `JL` rather than
`JLE`, that fourth press would have taken 24 Marines to zero. This is the assertion that
separates the two, and it is also the general statement: *the amount a unit must have is the
amount it is about to spend, tested strictly*.

### 5.2 An unpredicted finding: the client refuses to send it at all

The fourth press emitted **no command**. Not "a command that did nothing" — nothing reached the
wire: the log carries `0x36` exactly three times for three effective presses, and the fourth
keypress produced only the periodic `0x37`.

So there are two gates, not one: the receive-side per-unit gate in `0x004C2F30`, and a
send-side one in the client's own command card that suppresses the ability when the selection
cannot pay for it. This project had only known about the first. It matters for the fan-out
because **the send side sees the engine's twelve, not the shadow list**: a >12 selection whose
visible twelve are all too poor to pay will not emit the command at all, even though units past
the cap could have paid. That is a real, if narrow, difference between what the player sees and
what they get — recorded here rather than smoothed over, and not fixed, because it is the
engine's own behaviour and this task audits rather than changes it.

### 5.3 The energy half, in game

Not delivered as an in-game measurement. The static answer (§3) is complete — per-unit gate,
per-unit deduction, skip on failure — and the fixture that would prove it live now exists
(`--tech-researched personnel-cloaking` plus `--damaged-energy`), but the run needs the Ghost's
cloak keypress to actually emit `0x21`, and it did not in the attempts made here (§7). What is
missing is one line of knowledge — the key or the `WM_COMMAND` id that the Cloak button carries
— not a fixture and not a mechanism. A follow-up task can pick it up cheaply.

---

## 6. Question 2 — the Sunken and the Medic

`tools/plugin/test-sunken-acquire.ps1`, unattended, **0 failure(s)**, run of 2026-08-09. Four
arms over one fixture: six units walked into a lone Sunken Colony and watched for 30 s, with
the plugin active and again with `-Mode observe`, and the whole thing repeated with Marines in
the Medics' place.

| arm | closest unit | my hit points (start → lowest seen) | survivors | Sunken order | attacked? |
|---|---|---|---|---|---|
| Medics, `fanout` | 197px | 92160 → **88768** | 6/6 | `0x12` → `0x13` | **yes** |
| Medics, `observe` | 197px | 92160 → **88368** | 6/6 | `0x12` → `0x13` | **yes** |
| Marines, `fanout` | 131px | 61440 → **0** | 0/6 | `0x12` → `0x13` → `0x12` | **yes** |
| Marines, `observe` | 131px | 61440 → **0** | 0/6 | `0x12` → `0x13` → `0x12` | **yes** |

**The Sunken attacks Medics, and the plugin arm and the stock arm agree on every measure.**
The answer to "is this a bug we introduced" is no, and it is a measurement rather than a
restatement of the prior.

Four things make the table mean something:

1. **The stock arm is really stock.** In `-Mode observe` the plugin installs no hook at all —
   asserted from its own log (`FANOUT start` / `HOOK install` absent) — and both arms carry the
   same read-only `WORLD` oracle. If the oracle existed on only one side there would be no
   comparison to make.
2. **The Sunken's own order id is the acquisition signal**, not an inference from hit points:
   it sits on `0x12` while nothing is in range and moves to `0x13` when the block arrives, in
   every arm. The fixture asserts it was on `0x12` *before* the walk, so "it attacked" is about
   the walk and not about something that was already happening.
3. **Hit points are sampled repeatedly and the LOWEST is kept.** Medics heal each other, so a
   single reading taken afterwards shows a group at almost full health that has in fact been
   shot several times: the `fanout` Medic arm finished at 91368 having dipped to 88768. Read
   only the endpoints and the Sunken looks idle.
4. **The Marine arm is the control.** Without it a quiet Sunken is ambiguous between "it does
   not shoot Medics" and "it cannot shoot anything from there". Six Marines walked in and all
   six died — while taking the Sunken from 76800 to 23876, which is also why the Marine arms
   end back on `0x12`: nothing left to shoot.

### 6.1 What the user probably saw, and it is worth knowing

Three vanilla facts, all visible in this run's per-unit data, which together make a Sunken look
idle when it is not:

- **It shoots one target at a time.** In the Medic arms exactly one Medic was taking damage at
  any moment (`hp=12168` on one unit, `hp=15360` on the other five); the rest stood in range
  untouched.
- **Medics heal each other**, and the healer is visible doing it in the same scan — one Medic
  on order `0xB0` with its energy down at 8412 while the others sit at 51200. The damage is
  repaired between shots, so the health bar being watched may never look low.
- **The range is short**: 7 tiles, 224 map pixels, against a large sprite. The block was fired
  on at 197px and untouched further out; a Medic following other units around drifts in and out
  of that band.

## 7. Question 3 — "it stopped attacking"

### 7.1 What was tested, and what was not

The user reported a **cloaked Ghost** that stopped attacking. What is tested below is the
**mechanism that report made us suspect**: *do the `Select` commands the fan-out replays
interrupt orders that are already running?* Those are not the same question, and this document
does not let them read as one.

The Ghost/Cloak case itself could not be driven. The key is not `C` — it emits nothing even
with every unit at full energy, so the send-side gate of §5.2 does not explain it — and when
the test fell back to clicking where the command card's bottom-left slot should be, the frame
came back reading **"Select Target"**: that slot is a *targeted* ability, i.e. Lockdown.
Naming the Cloak button is one keypress sweep on a working command card and is owned by the
harness task, with this evidence attached.

### 7.2 The static half

The handlers cannot do it. `0x004C0720` → `0x00491B30` (the cloak family) writes energy and
the SECONDARY order `CUnit+0xA6`; `0x004C2F30` (Stim) writes hit points and `CUnit+0x115`.
Neither writes `CUnit+0x4D`. A unit that was attacking has no mechanism *in the ability* to
stop — so if one stops, it is the replayed `Select` or nothing.

### 7.3 The quiet half: 36 units, four fan-outs, no order moved

Every `UNITSTATE` line in §5 reads `orders=[0x03:36]` before and after each fanned-out Stim
press: four fan-outs, **twelve emitted `Select` commands**, and not one unit changed its main
order. That is the hypothesis tested directly on a still fixture, where nothing else can move
an order.

### 7.4 The loud half: the same question during an actual firefight

`tools/plugin/test-ability-in-combat.ps1`: 36 Marines walked into 16 Hydralisks, Stim pressed
once while the fight is in progress, plugin arm and stock arm.

**A naive version of this measurement produced a false finding against our own feature, and it
is worth recording because the mistake is an easy one.** Counting units whose main order
changed across the ability gave **13 of 29 in the plugin arm against 2 of 29 in stock** — six
times as much disturbance, exactly the shape of result this audit was looking for. It is an
artefact of the feature working. The move order that starts the fight is *itself* fanned out,
so the two arms are not in the same state:

| arm | orders at the moment of the keypress |
|---|---|
| plugin | `0x03:5 0x06:9 0x0a:17` — five idle, nine moving, seventeen attacking |
| stock | `0x03:26 0x0a:6` — twenty-six standing still |

Twenty-six idle units cannot have their orders interrupted. Raw churn was measuring how many
units were doing anything.

So the measurement is **each arm against its own control**: the same fight, the same two
seconds, with no ability used — one control window immediately before the ability window and a
second immediately after, because a fight decays (fewer units alive, fewer targets) and one
control on one side of the ability is not automatically comparable to it. If the two controls
disagree with each other, the fight is too unstable to measure and the run says so rather than
averaging them.

**Why a negative result here means something.** A replayed `Select` lands on every unit in the
chunk at once. If it interrupted running orders, the ability window would show a **landslide**
against its control — most of the group knocked off what it was doing in one step — not a
margin of one or two. That is what makes the allowance in the assertions generous rather than
lax, and it is what makes "no excess" a real answer instead of a quiet one.

Run of 2026-08-09, `0 failure(s)`:

```
[fanout]  CONTROL before: 30 of 32 alive, 10 changed order, 2 stopped attacking
[fanout]  CONTROL after : 24 of 26 alive,  4 changed order, 1 stopped attacking
[fanout]  ABILITY window: 26 of 30 alive,  8 changed order, 1 stopped attacking
[observe] CONTROL before: 29 of 32 alive,  0 changed order, 0 stopped attacking
[observe] CONTROL after : 22 of 26 alive,  0 changed order, 0 stopped attacking
[observe] ABILITY window: 26 of 29 alive,  0 changed order, 0 stopped attacking

excess disturbance caused by the ability: fanout -2, stock 0
```

**The ability window is quieter than the control window that preceded it** — eight order
changes against ten — and it sits between the two controls, which is what "no effect" looks
like in a decaying fight. One unit stopped attacking across the ability; two stopped across the
control. And the individual changes are mostly `0x03`/`0x06`/`0x02 -> 0x0a`: units arriving and
*starting* to shoot, the opposite of being interrupted. No landslide, no margin, nothing.

**Which arm is the evidence.** The plugin arm's comparison against its own control is the
primary result: it is the only arm with enough units actually doing something for an
interruption to be visible. The stock arm is the corroborator and a weak one, and this run
shows exactly why — it recorded **zero** order changes in every window, including the two
controls. A population that never changes an order cannot demonstrate that something failed to
change one. Reported as a corroborator, not as an equal arm.

### 7.5 What this does and does not answer

It answers: the fan-out's replayed `Select`s do not interrupt orders that are already running,
on a still fixture and in a live fight, statically and dynamically.

It does not answer: why a cloaked Ghost appeared to stop attacking. That remains open, most
likely vanilla (the plugin has no AI, targeting or acquisition code in it at all), and the
honest state of it is "not reproduced, and not yet reproducible with this harness".

---

## 8. Harness faults found on the way, and why they matter to every result in this repo

### 8.1 The Game Type pick has been a silent no-op — and it is a foreground problem

**The game ignores a posted `WM_MOUSEMOVE` when its window is not the foreground window.**
Posted clicks are processed either way, which is why every other part of `drive-game.ps1` works
with the window in the background, and why this went unseen.

Measured (`work/scratch/022/probe-gametype*.ps1`, frames under `C:\sc-work\logs\022*-frames`):
posting a move to (500,200) with the window inactive leaves the game's own drawn cursor exactly
where the last posted **click** left it. So a dropdown opened by a posted button-down highlights
whatever row the cursor was on when it opened, never moves, and the button-up commits the value
that was already selected.

The consequence is worse than a failure. The Game Type combo **remembers the last value used on
this machine**, so a pick that does nothing still produces the right game for as long as that
remembered value happens to be right. It was `Use Map Settings` for months. When this task found
it, it was `Free For All`, and every generated fixture was loading as a melee game: the map's
placed units are never created, the player gets a standard starting base, and the run looks
normal while measuring nothing. (Task 021 found the same silent no-op from a different cause — a
200 ms wait for the list to open — which is the same lesson twice: this control fails quietly.)

**The same cause has at least three symptoms**, which is what makes it worth this much text.
Task 021 independently lost 25 assertions across two suites in one sweep to `Send-ScDrag`
"selecting nothing": a drag IS a sequence of moves, and with the moves dropped the button-down
and button-up land at the same point, so the box opens and closes on one pixel and selects
nothing — silently, with three other suites in the same sweep boxing fine, which is exactly the
intermittency you would expect from something that depends on which window happens to be
foreground. Their minimap-centring click is a third candidate with the same shape. So
activation is now part of dragging as well as of picking (`Send-ScDrag -NoActivate` opts out).

Four changes, in `drive-game.ps1`:

- `Set-ScWindowActive` — `AttachThreadInput` and then **verify**, because a plain
  `SetForegroundWindow` from a background process returns TRUE and does nothing.
- `Send-ScDropdownPick` activates the window itself and **throws** rather than picking blind, so
  every existing caller is fixed without being edited.
- `Set-ScGameType` — picks a known *other* entry, fingerprints the map-information panel, picks
  the wanted entry, and requires the panel to have **changed**. That panel reads
  "Number of Players" for the melee types and "Human Slots / Computer Slots" under Use Map
  Settings, so a real change of type is a real change of pixels, and a pick that did nothing is
  a loud failure at the menu instead of a mystery ten assertions later.
- `Send-ScDrag` activates before dragging, for the reason above.

### 8.2 StarCraft is single-instance, machine-wide

A second launch exits immediately (`scinject` exit 3), **including from a different working copy**
— a private 1.1 GB copy was made specifically to test that, and it made no difference. The launch
lock is held only around the launch, so a worker can be holding a running game with the lock
free. `Wait-ScNoGameRunning` waits for the machine to be free, and this task's suites then hold
the lock for as long as their own game lives.

### 8.3 The generated-fixture folder was shared, and that is a data-loss bug, not an annoyance

Every suite generated into `Maps\BroodWar\00-testmap` and picks its map **by clicking a row**,
so a second file in that folder silently changes which map loads — and every suite started with
`Remove-Item -Recurse` on it. Four runs were lost to this in one evening, twice in each
direction: another worker's suite played this task's 36 Ghosts (their fixture places Lurkers),
and this task's suite boxed 36 of their Lurkers. Two more runs died when a fixture was deleted
out from under them mid-run.

Three fixes, in increasing order of how much they actually help:

1. **Wait, and never delete what you did not create** (`Wait-ScTestMapDirFree`). Necessary, and
   not sufficient: it checks once, before generating, and the folder can change between that
   check and the browser click.
2. **Re-check immediately before the launch** (`Assert-ScFixtureStillMine`). This is the one
   that caught the live incident and named it, instead of producing numbers about the wrong map.
3. **A folder per task** (`Maps\BroodWar\00-t022`), removed at the end and only when empty.
   This is the structural fix: the collision cannot happen in either direction, so there is
   nothing to wait for. The "only when empty" half matters as much as the rest — an empty
   folder left behind becomes the first row of every other suite's folder click, which is the
   same bug with the roles swapped.

The general lesson is worth more than the fix: **a positional selector over shared mutable
state fails silently and produces a run that looks normal.** Anything that picks by row, index
or ordering has to verify what it got — which is why the fixtures assert their unit types
in-process and name "melee start" and "another worker's map" as the causes rather than reporting
a count that does not match.

---

### 8.4 Four defects in one evening, and not one of them was random

The harness faults found while doing this work were, in order: the Game Type pick (a posted
mouse MOVE ignored while the window is not foreground), the drag box (the same cause, found on
another task's failing suites), the fixture-folder row (two workers' maps in one folder, chosen
positionally), and the folder row one level up — where merely leaving an **empty** directory
behind moved every row for a suite that navigates somewhere else entirely and does not use the
shared folder at all.

**Every one of them presented as intermittency, and none of them was random.** Each looked like
flake for a good reason: the dropdown remembered a value that was sometimes right, the drag box
depended on which window happened to be foreground, and the folder rows depended on what
another run had left on disk a minute earlier. Two were labelled "flaky" out loud — once by
this task — before someone went back and dismantled them.

The rule that falls out, for whoever meets the next one: **in this harness, start from "what is
deterministic about this" rather than from "run it again".** A positional selector over shared
mutable state, and an input path that depends on window focus, both produce failures that are
perfectly reproducible once you know what varies — and re-running is precisely the action that
hides them.

---

## 9. Confidence and method

### Derived here, from this binary

- Stim's per-unit gate constant, its cost constant, and that the test is strictly greater (§2).
- `CUnit+0x115` = stim timer, with its setter, its per-frame decrementer and the shared refresh
  call (§2.1); `CUnit+0xA2` = energy, from the compare-then-deduct pair (§3).
- The `0x21` family's per-unit affordability gate, its type-indexed cost table at `0x00656380`,
  and that a caster which cannot pay is skipped (§3).

### Derived here, from the live game

- That one Stim keypress on a 36-unit selection gives the effect to, and charges, every one of
  the 24 units that can afford it, and skips the 12 that cannot (§5).
- That the skip is the engine's: the partition follows hit points, not the cap (§5).
- That Stim cannot kill, at the exact boundary (§5.1).
- That there is a **send-side** gate as well (§5.2).
- That a posted mouse MOVE is ignored unless the game window is active (§8.1).
- That the game is single-instance machine-wide, per machine and not per directory (§8.2).

### Open

- **The Ghost's Cloak keypress.** The button is on the card and the tech is researched, but no
  key tried emitted `0x21`; task 021's finding that posted modifier keys cannot work
  (`TranslateAcceleratorA` reads a key-state table Windows never updates for posted messages)
  suggests the same `WM_COMMAND` route they used for control groups. §5.3.
- **Which selection the send-side gate consults** — presumably the engine's twelve, but that is
  an inference from one observation where all 36 units were identical (§5.2).
- The cost table at `0x00656380` is read but not enumerated; only the two cloak entries matter
  here.
