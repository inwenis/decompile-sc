# Queueing a unit at every selected production building — the two gates, and what it takes to open them

Analysis date: 2026-08-10 (task 030). Target: `StarCraft.exe`, StarCraft: Brood War 1.16.1
(classic), the project's disposable working copy `C:\sc-work\1161-base`, SHA-256
`AD6B58B27B8948845CCFA69BCFCC1B10D6AA7A27A371EE3E61453925288C6A46` — hashed before and after
every run below and byte-identical each time. The user's playable install was never opened.

The question this answers, in the user's words: **"can i also queu units when i have several
building selected?"**

Companion to [`building-groups.md`](building-groups.md) (task 024 — how a drag box comes to
select all six Barracks in the first place) and [`production-queue.md`](production-queue.md)
(task 025 — the five-slot ring inside the `CUnit`, and who pays for what).

---

## 1. The answer in one paragraph

**Two gates, not one, and the second is the one nobody had looked at.** The known gate is on the
receive side: `cmdrecvTrain` (`0x004C1C20`) is SINGLE-gated and does nothing unless exactly one
unit is selected, which is why a group of buildings gains nothing. The gate that actually stops
the player, though, is on the CLIENT: the Train button's condition `0x00428E60` opens with
`if (clientSelectionCount > 1 …) return 0`, and the card layout drops a button whose condition
returns 0 **entirely** — so with several buildings selected there is no Train button on the card
at all, and no command is ever emitted to be fanned out. Measured, not inferred: §2. Opening the
first gate is the existing fan-out, because a building group's chunk size is already one building
and one building is exactly what the receive handler wants. Opening the second is one detour on
one function. §5.

---

## 2. What a stock game actually does — measured first

`tools/plugin/test-group-production.ps1 -Arm baseline`, one launch, unattended, `0 failure(s)`.
Four Command Centers, boxed as a group by task 024's own mechanism, 3000 minerals, nothing
hostile on the map and one trigger that only sets resources.

| measurement | 4 buildings selected | 1 selected — the positive control, same run |
|---|---|---|
| Train button on the card | **absent** (`button=0x00000000`) | **enabled**, slot 1 |
| `0x1F` commands reaching `queueCommand` (`0x00485BD0`) | **0** | **1** — `bytes=[1F 07 00]` |
| buildings that gained a queued item | **0 of 4** | **1**, its `CUnit+0x98` going 0 → 1, type `0x7` |
| minerals moved | **0** | **50**, 3000 → 2950 |

Each of the four zeros is a separate read of a separate building's own `CUnit+0x98`, printed
per building (`engine=[0xe4,0xe4,0xe4,0xe4,0xe4]` four times) and asserted EMPTY before the click
as well as after. **The positive control is in the same run, through the same funnel watch and
the same queue read** — without it "0 commands" and "the funnel watch is broken" are the same
picture, which is the rule AGENTS.md already states about absence assertions.

So: it does not already work, and it fails earlier than expected. Not "one command, one
building" — *no command at all*.

### 2.1 The card, and the controlled comparison inside it

The card was read out of the engine's memory, never off a frame (AGENTS.md — a claim about what
a dialog HOLDS is answered by walking the dialog). Both readings are the Command Center's own
card: same `cardId=106`, same 10-button set at `0x00517F38`. What differs is which controls got
a `Button` record:

| slot | action | condition | 1 selected | 4 selected |
|---|---|---|---|---|
| 1 — Train SCV | `0x004234B0` | **`0x00428E60`** | enabled | **absent** |
| 7 — addon (param 107) | `0x00423D10` | **`0x00428E60`** | GREYED | **absent** |
| 8 — addon (param 108) | `0x00423D10` | **`0x00428E60`** | GREYED | **absent** |
| 6 — rally | `0x004244A0` | `0x00429520` | enabled | enabled |
| 9 | `0x00423230` | `0x004287D0` | enabled | enabled |

`slots=9 shown=5 greyed=2` becomes `slots=9 shown=2 greyed=0`. **Exactly the three buttons gated
by `0x00428E60` disappear and exactly the two that are not gated by it survive.** That is the
gate caught in the act, from one selection change, with everything else held fixed.

It also explains the *shape* of the stock group card exactly, via the layout rule task 026
already derived ([`command-card.md`](command-card.md) §4): the layout advances its button cursor
past any button whose condition returns 0, then hides the control if
`ctrl->index < button->slot`. With Train and both addons skipped, the next surviving button has
slot 6 — so controls 1–5 are hidden, 6 is drawn, 7–8 hidden, 9 drawn. Which is the reading.

---

## 3. The client gate: `0x00428E60`

Its whole body, from this binary (`work/scratch/030/cond-listing.tsv`):

```
00428E60  55              PUSH EBP
00428E61  8B EC           MOV  EBP,ESP
00428E63  8B C1           MOV  EAX,ECX                      ; EAX = the type, from ECX
00428E65  80 3D 3D 72 59 00 01   CMP byte ptr [0x0059723D],0x1
00428E6C  56              PUSH ESI
00428E6D  8B 75 08        MOV  ESI,dword ptr [EBP + 0x8]    ; ESI = the unit
00428E70  57              PUSH EDI
00428E71  76 1E           JBE  0x00428E91                   ; count <= 1 -> ALLOW
00428E73  66 8B 7E 64     MOV  DI,word ptr [ESI + 0x64]
          ... CMP/JZ against 0x23, 0x2B, 0x26 -- the three types that multi-select anyway
00428E89  5F 33 C0 5E 5D C2 04 00     POP EDI / XOR EAX,EAX / POP ESI / POP EBP / RET 4
00428E91  52              PUSH EDX                          ; the player
00428E92  E8 29 53 04 00  CALL 0x0046E1C0                   ; the requirement interpreter
00428E97  5F 5E 5D C2 04 00           POP EDI / POP ESI / POP EBP / RET 4
```

So the convention is **`__stdcall(CUnit* unit)` with `ECX` = the button's type param and
`EDX` = the player**, and the count is a **byte** at `0x0059723D`. `EDX` is corroborated
independently by the neighbouring condition `0x00429520`, which compares its own `EDX` against
the unit's owner byte at `CUnit+0x4C`.

### 3.1 The type param is a `u16`, and ECX arrives with a dirty upper half

**Only `AX` is the type.** `0x00428E63` moves `ECX` into `EAX` and the requirement interpreter
reads `in_AX`; the `Button+0x0C conditionParam` it comes from is a `u16`
([`command-card.md`](command-card.md) §3). The top half of `ECX` is **not** cleared by the
caller, and this is not a theoretical point — the plugin logged its first three calls verbatim:

```
PRODFAN cond: call#1 type=0x510007 unit=0x00623D08 player=0 clientCount=4 simSlots=1
PRODFAN cond: call#2 type=0x51006B unit=0x00623D08 ...
PRODFAN cond: call#3 type=0x51006C unit=0x00623D08 ...
```

`0x0007` is the SCV, `0x006B` and `0x006C` are the two addon buttons — and every one of them
carries `0x0051` in its high half. Anything reading that param as a 32-bit value gets a number
in the millions. A plugin comparing it against a type bound must mask to sixteen bits, which is
what the engine effectively does by only ever touching `AX`.

`0x0059723D` is named for what it gates rather than from prior art, and the plugin logs it beside
the selection size so the in-game suite asserts it reads 4 with four buildings boxed — the name
is a reading, not a label.

**This condition is shared with the two ADDON buttons** (measured above: params 107 and 108,
action `0x00423D10`). Relaxing it wholesale would light those for a group too, and since nothing
here fans `0x35` out they would be buttons that look live and do nothing. Their param is a
building type; a Train button's is a unit type below `0x6A` — **the very bound `cmdrecvTrain`
applies to the type it will accept** — so that bound is the discriminator, taken from the engine
rather than invented.

---

## 4. The receive gate, and the answer to "what if the buildings differ"

`cmdrecvTrain` (`0x004C1C20`) is SINGLE-gated: `selectionIterator = 0`, then
`getActivePlayerNextSelection` twice, proceeding only if the second returns null
([`command-opcodes.md`](command-opcodes.md) §5). A fan-out chunk of exactly one building
satisfies it, which is the whole reason this feature is small.

Its gate on *what* may be built is `0x0046E1C0`, and reading it settles acceptance criterion 5's
harder half. Convention, off its own body: **`ESI` = the PRODUCING unit, `AX` = the type, the
player as its one stack argument.** It is emphatically **not** a player-only check:

```c
case 0xff02:                                   /* "requires unit of type X" */
    if (*puVar1 == *(ushort *)(unaff_ESI + 100))   /* the PRODUCER's own CUnit+0x64 */
         { bVar4 = false; bVar2 = false; local_8++; }
    else if (bVar2) { bVar4 = true; }          /* wrong kind of producer */
...
case 0xff04:                                   /* "requires addon of type X" */
    if (*(int *)(unaff_ESI + 0xc0) == 0 ||
        *(short *)(*(int *)(unaff_ESI + 0xc0) + 100) != required) { … return 0xffffffff; }
case 0xff0c:                                   /* "must have NO addon" */
    if (*(int *)(unaff_ESI + 0xc0) != 0) { … return 0; }
...
if (uVar7 == 0xffff) { if (!bVar4) return 1; DAT_0066ff60 = 0x19; return 0xffffffff; }
```

So a building of the wrong kind, and a Factory without its Machine Shop, are refused by the
engine's own interpreter with reason `0x19` / `0x04` — and `cmdrecvTrain` tests its result
`== 1` exactly, so a `-1` refuses **before** `addToBuildQueue` runs and therefore before any
resource moves. **A mixed group could not have cost the player anything even if the plugin let
one through.** The plugin refuses mixed groups anyway (§5.3); the two refusals are independent,
and the plugin's is the outer one.

---

## 5. What was built

### 5.1 The wire half — the fan-out already had the right shape

`research/command-opcodes.md` §3.2 keeps `0x1F` off the fan-out list for a reason worth quoting,
because this task inverts it rather than waving it away:

> a fan-out chunk can be one unit long, so replaying one would make it fire where the player's
> own selection never could.

For a **unit** selection that is a real hazard: 13 units chunk as 12 + 1, and the lone thirteenth
would train alone. For a **building group** it is not a hazard but the feature, because
`simSlots` is 1 — the simulation refuses a building every selection slot but slot 0
([`building-groups.md`](building-groups.md) §3) — so **every** chunk is exactly one building and
"one item per chunk" is "one item per building". The guard is that distinction turned into a
condition: `simSlots == 1`, at least two buildings, one type, and the dispatcher's own length.

Every item therefore enters through the engine's own `cmdrecvTrain` → `addToBuildQueue`, which is
where affordability is checked and the cost deducted. **The plugin writes no resource global on
any path**, so "N buildings, N units, N × cost, paid once each by the engine" is a property of
the shape rather than of bookkeeping — the same conclusion task 025 reached the hard way.

### 5.2 The client half — one detour, and the second design was the right one

The first attempt reproduced `0x00428E60`'s allow path by hand: ten instructions, setting `ESI`
and `EAX` itself and calling `0x0046E1C0` directly. It installed, it ran, its own counter said it
had allowed the button four times — **and the button still was not drawn.** Something in that
hand-made register state was not what the interpreter wanted, and no amount of reading the
listing was going to say which faster than changing the design.

What ships instead does not reproduce anything:

> **Show the STOCK condition a selection count of 1, for the length of one call.**

The detour decides whether this is our case, writes `1` into `0x0059723D`, calls the original
through its own trampoline, restores the byte, and returns the original's own answer. The
multi-select clause is the only thing that changes; the tail call into the requirement
interpreter runs unmodified, with the register state the engine itself set up. There is no
calling convention left for the plugin to get wrong, and the rules about what may be built stay
entirely the engine's — including §4's per-building checks, which is why a button is never lit
for a building the engine would refuse.

The write is to a UI counter, in this process only, on the game thread, restored before the
function returns and therefore before any engine code can observe it. The restore is on the
only path between the two stores; a depth guard makes "the stock condition cannot re-enter
this detour" a property of the code rather than an argument about the engine; and if the
process is torn down inside the call the restore is skipped, which is acceptable because the
address space is going with it.

### 5.2.1 Three defects, all in this task's own work, all found by running it

Worth writing down because two of them are about *diagnostics* rather than about the engine,
and this project already has the corresponding rule for assertions.

1. **A guessed calling convention.** The hand-made allow path (above). Deleted rather than
   double-checked.
2. **A `printf` with a missing argument.** The oracle's summary line grew a `lit=%d` without
   growing an argument to match, so it printed rubbish off the stack — and that rubbish read
   `lit=4`, which is exactly what a working detour would have printed. An hour went into
   explaining why the requirement gate "returned 0" when it had never been called at all.
   **A diagnostic is under the same rule as an assertion: a reading that cannot fail is worth
   nothing.** The fix was to count and print *which* of seven terms the detour returned on, so
   "it refused" names the test.
3. **The 32-bit read of a 16-bit param** (§3.1), which the counters then found in one run.

The order matters: defect 2 hid defect 3. Fixing the diagnostics first is what made the third
one a single line of output instead of another evening.

### 5.3 The awkward cases, and what happens

| case | what happens | where the evidence is |
|---|---|---|
| a building already at the engine's five | the engine's `addToBuildQueue` returns 0 at its own `CMP EAX,0x5` **without touching the array or the player's resources** — so it is skipped and costs nothing | in game, §6: the full building stays at five and the payment is `(N−1) × cost`, not `N × cost` |
| a group whose buildings are not all one type | **refused outright**, and the whole command rather than the odd building, because a partial fan-out would spend the player's minerals on a subset they never chose | offline, `hooktest` part [15]; and §4 — the engine would refuse it for free anyway |
| a >12 **unit** selection | refused: `simSlots != 1`, so `0x1F` stays passthrough exactly as `command-opcodes.md` §5.1 has it | offline, `hooktest` part [15] |
| one building selected | not fanned out at all, so the path stays byte-for-byte stock — which is what makes it usable as a control arm | in game, §6, both arms |
| `%SCPLUGIN_BUILDING_GROUPS%=0` | a box selects one building, the count is 1, and the detour returns "not ours" before looking at anything else | by construction, §5.4 |

### 5.4 How it composes with task 024

Task 024 relaxed a *different* client multi-select gate (`unit_IsStandardAndMovable`, via
`SortAllUnits`) and is on by default. This is a second relaxation in overlapping circumstances,
so the composition is enforced by construction rather than argued: **the button detour and the
command path call the same function, `ScProdFanDecide`, with the same arguments.** One predicate,
two callers. Since `simSlots == 1` is computed by `sc_fanout` from the engine's own movability
predicate, a selection task 024 would not have produced cannot reach either.

---

## 6. What was proved, and how

### 6.1 Offline, with no game in the process

`hooktest.exe` part [15], `0 failure(s)`. The policy is pure, and it is the same call both the
button detour and the command path make, so testing it once tests both: a same-type building
group of two or more at chunk size 1 fans out; a **unit** selection is refused at 4 and at 13
(that 12 + 1 split being exactly the hazard); a single building and an empty selection are
vanilla's own case; a **mixed** building group is refused whether the odd one out is in the
middle or last; the wrong command length is refused at 2 and at 11; and with the feature off
even the right selection is refused.

### 6.2 In the live game, unattended, three arms

One launch each, `StarCraft.exe` hashed before and after every arm and byte-identical to pristine
1.16.1 each time, every game closed by pid, the fixture removed.

| arm | result | what it reported |
|---|---|---|
| `baseline` | **0 failures** | §2's table — 0 commands, 0 of 4 buildings, 0 minerals, with the single-building positive control firing in the same run |
| `feature` | **0 failures** | below |
| `cap` | **0 failures** | §6.3 |

The `feature` arm, in its own words:

```
Train button: slot=1 state=enabled cond=0x00428e60 act=0x004234b0
FANOUT start: cmd=0x1F len=3 units=4 (visible 4 + overflow 0) slots=1 -> 4 Select+order pairs
FANOUT done: 4/4 chunks emitted, 28 bytes this turn
  ok  building 0 (after one click) holds 1 item(s), read from its own CUnit+0x98 (1)
  ok  building 1 (after one click) holds 1 item(s), read from its own CUnit+0x98 (1)
  ok  building 2 (after one click) holds 1 item(s), read from its own CUnit+0x98 (1)
  ok  building 3 (after one click) holds 1 item(s), read from its own CUnit+0x98 (1)
  ok  minerals are down by exactly 4 x 50 and no more (2800)
  ok  nothing was paid for that did not queue
  ok  all 4 buildings are actually building something (4)
```

Four properties of that shape are deliberate:

1. **Each building is read individually, from its own `CUnit+0x98`** — four reads of four
   buildings, not one count. A count can be produced by the wrong four things.
2. **The before-state is asserted, not assumed.** Every queue is read and asserted EMPTY before
   the click, so a reading of 1 afterwards cannot be something that was already there.
3. **The money is asserted in both directions.** Exactly `4 × 50` left, and the amount that left
   equals the number of items that queued — which is what "nothing paid for that did not queue"
   means as an arithmetic statement rather than a hope.
4. **One press produces ONE command at the funnel**, not four. `CMD id=` is logged inside the
   queueCommand detour and the fan-out emits its pairs through the trampoline, so the replayed
   commands deliberately do not pass the logger again; the plan line is what names them. An
   earlier version of this suite asserted four and would have failed a working feature.

### 6.3 The at-cap case

Its own arm, and it has to be: a Command Center finishes an SCV in about ten seconds and a
finished SCV stands among the buildings, so any drag box taken after one completes selects the
SCV rather than the group (`SortAllUnits` keeps movable units and discards buildings,
[`building-groups.md`](building-groups.md) §2.2). The first attempt at this measurement boxed
exactly that and reported `buildings=1` on a unit that was not even a Command Center. So the arm
runs in a game where nothing has finished yet: click one building, fill it to five, box the group,
press once.

The claim it makes is the drain-proof one, and it is the criterion itself rather than a proxy: a
unit finishing inside the measurement window shortens a queue, but it never un-spends a mineral.

```
  ok  at least one of them is at the engine cap (1)
        unit=0x00623D08 0 -> 1
        unit=0x00623BB8 0 -> 1
        unit=0x00623E58 0 -> 1
        unit=0x00623A68 5 -> 5      <- the building at its cap, untouched
  ok  exactly 3 x 50 minerals left, NOT 4 x 50 (150)
  ok  so the building at its cap cost the player nothing
  ok  no building holds more than the engine's 5 slots
```

The fan-out still emits a pair for **all four** buildings — the plugin does not pre-judge which
one can accept. The engine refuses the full one at its own `CMP EAX,0x5`, for free, and the
difference between `150` and `200` is the whole of acceptance criterion 5's first half.

---

## 6.4 What the player sees

Stated plainly because it is a real limit and not a detail: **the status area draws one queue —
the primary selection's.** Four buildings queueing shows one queue and `4 × cost` leaving the
minerals. What stops that being silent is that all four buildings genuinely begin producing, which
is visible on each building and is asserted here from each building's own `CUnit+0xEC`
(`4 of 4`). It is incomplete, not wrong. §7.1.

---

## 7. Known limitations

1. **The status area draws ONE queue — the primary selection's.** With four buildings queueing,
   the player sees one building's queue and `4 × cost` leave their minerals. What makes the
   feature legible rather than silent is that all four buildings really do begin producing, which
   is visible on each building itself; the suite asserts it from each building's own
   `CUnit+0xEC`. Extending the production panel would be a second dialog splice and a much larger
   change (`production-queue.md` §7 reaches the same conclusion for the same reason).
2. **Train (`0x1F`) only.** Unit Morph, Train Fighter and Building Morph are untouched.
3. **Same-type groups only**, by choice (§5.3).
4. **Single-player only**, like everything in this repo (AGENTS.md hard rule 3).
5. ~~**Five per building, whatever the over-cap feature is set to.**~~ **FIXED by task 038**, and
   the user found it playing the deployed build: *"can't queue more than 5 units per building
   when multiple buildings are selected"*. Nothing in this file was wrong — the fan-out put one
   Train on the wire per building exactly as it says — but this suite runs with
   `%SCPLUGIN_PRODQ%=0` on purpose (§6.2), so the seam with task 025's over-cap queueing was
   never measured. It did not hold: the over-cap feature read the CLIENT's selection to decide
   which building a Train was for, and a fanned-out Select+Train pair is precisely the moment the
   client's selection and the simulation's disagree, so it held nothing back and every ring
   filled to five. The whole story, with the wire traces on both sides,
   is [`production-queue.md`](production-queue.md) §10; the suite that covers the two features
   together is `tools/plugin/test-group-queue-over-five.ps1`.

---

## 8. Reproducing this

```powershell
$env:GHIDRA_INSTALL_DIR = 'C:\re-tools\ghidra_12.1.2_PUBLIC'
./tools/ghidra/sweep.ps1 -Mode Prepare -InputPE C:\sc-work\1161-base\StarCraft.exe `
    -ProjectDir work/scratch/030/ghidra -LogFile work/scratch/030/ghidra/import.log

# the two gates and their neighbours, decompiled
./tools/ghidra/sweep.ps1 -Mode Run -ProjectDir work/scratch/030/ghidra -ProgramName StarCraft.exe `
    -Script DecompileMany.java -ScriptArgs work/scratch/030/gate.tsv, tools/ghidra/specs/prodfan-gate.spec, 200

# the client gate's own instructions (quote the hex, or PowerShell evaluates it as a number)
./tools/ghidra/sweep.ps1 -Mode Run -ProjectDir work/scratch/030/ghidra -ProgramName StarCraft.exe `
    -Script ListingDump.java -ScriptArgs work/scratch/030/cond-listing.tsv, '0x00428E60', '0x00428EB0'

./tools/plugin/build.ps1 -Test                                  # the offline policy proofs
./tools/plugin/test-group-production.ps1 -Arm baseline          # what a stock game does
./tools/plugin/test-group-production.ps1 -Arm feature           # and what this one does
```

The `.c` decompiles are whole functions and therefore derived game content; they stay under
`work/scratch/` (gitignored) and only the findings above are committed (AGENTS.md hard rule 1).
