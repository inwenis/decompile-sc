---
from: 029
to: conductor
sent: 2026-08-10T21:26:40Z
subject: DESIGN for review: upgrade queue -- the client refuses to send, so it is unblock + hold + promote
---

---
from: 029
to: conductor
sent: 2026-08-10T21:25:53Z
subject: DESIGN for review: upgrade queue -- the client refuses to send, so it is unblock + hold + promote
---

Nothing is implemented yet. Full write-up with every address and its how-found/how-verified
is on the branch as `research/upgrade-queue.md`; this is the decision and the reasoning.

## 1. The wire, watched FIRST — the client REFUSES, and it does it harder than 025's did

`tools/plugin/probe-upgrade-wire.ps1`, one launch, 0 failures. Fixture: one Terran
Engineering Bay (units.dat 122), player 0, 3000/3000, nothing else in the game. It has two
INDEPENDENT level-1 upgrades — Infantry Weapons (7) and Infantry Armor (0) — so "queue a
second upgrade" can be asked without the level-N/N+1 case. Every click point is computed from
the live dialog, never hardcoded and never measured off a frame.

Idle card, read out of memory at 0x0068C148 (buttonset 122, 7 buttons, shown=3):

```
slot=1 enabled cond=0x00429450 act=0x00423310 aparam=7   Infantry Weapons
slot=2 enabled cond=0x00429450 act=0x00423310 aparam=0   Infantry Armor
slot=9 enabled cond=0x004287D0 act=0x00423230            Lift Off
```

Press slot 1:

```
[22:21:23.269] CMD id=0x32 len=2 bytes=[32 07]
```

4 s later the world scan has the building's order at 0x4C (idle was 0x17), so it really is
researching. Card again — SAME buttonset 122, same 7 buttons, shown=**1**:

```
slots 1..8 HIDDEN      (greyed=0)
slot=9 enabled cond=0x00428900 act=0x004232F0   Cancel Upgrade
refuseReason (0x0066FF60) = 5
```

Now the headline. Three presses each, at the points the IDLE card gave, i.e. the same
arithmetic that had just sent a command:

```
slot 2 (a DIFFERENT upgrade), x3  ->  0 commands on the wire
slot 1 (the running one),     x3  ->  0 commands on the wire
```

And the control, so "sent nothing" cannot mean "the clicks stopped working". Cancel, then
press the same point once:

```
[22:21:37.464] CMD id=0x33 len=1 bytes=[33]     the cancel
   order back to 0x17; card back to shown=3 with both upgrade buttons enabled
[22:21:41.054] CMD id=0x32 len=2 bytes=[32 00]  one press, one command
```

**The client refuses to send.** And note it is a stronger refusal than 025 met: 025's Train
button was drawn dark (greyed); these are not on the card at all, and the card is replaced by
a lone Cancel Upgrade. So there is no second 0x32/0x30 anywhere to catch.

## 2. Why — one field, one requirement opcode, one predicate used twice

`btnUpgradeCondition` 0x00429450 is a bare tail call to `upgradeGate` 0x0046DFC0, and
`cmdrecvUpgrade` 0x004C1B20 calls THE SAME function before it does anything. Client half and
receive half are one piece of code.

Inside it, the refusal is one case of the requirement interpreter 0x0046D610:

```c
case 0xff07:  if (isLifted())        { reason = 5; return 0; }
              if (unit->0xC8 != 44)  { reason = 5; return 0; }   /* falls through */
case 0xff0a:  if (unit->0xC9 != 61)  { reason = 5; return 0; }
case 0xff09:  if (unit->0xC8 != 44)  { reason = 5; return 0; }
```

`return 0` (not -1) is why the buttons vanish instead of greying. And reason 5 is the number
the live busy card reported, in the same run, at the same moment — static and live agreeing
on one constant.

Storage, derived from the two conditions that read it rather than from a struct listing:

| field | meaning | how found |
|---|---|---|
| CUnit+0xC9 u8 | upgrade in progress, **61** = none | `btnCancelUpgradeCondition` 0x00428900 is literally `return unit->0xC9 != '='` (61) |
| CUnit+0xC8 u8 | tech in progress, **44** = none | `btnLiftOffCondition` 0x004287D0 requires `== ','` (44) |
| CUnit+0xC6 u16 | time remaining | both starts write it, both ticks decrement it |
| CUnit+0xCD u8 | level being upgraded TO | `startUpgrade` writes currentLevel+1 |

61 and 44 are one past the last upgrades.dat / techdata.dat id — the same sentinel trick as
the build queue's 0xE4. Both bytes are a UNION arm: 0x00469240 stores a CUnit* at +0xC8, so
every read is gated on `flags & 2` (building), which is what all three engine readers do.

## 3. The money, and the one fact the design turns on

All of it lives in two functions: `startUpgrade` 0x00454A80 and `startTech` 0x00454B70. Both
check affordability first and return 0 WITHOUT touching a resource global if the player can't
pay; both then subtract from minerals 0x0057F0F0 / gas 0x0057F120. Cancel is exactly
symmetric out of the same tables.

**Both take the building as an explicit register argument** (ECX and EDX). They do not resolve
it through the selection. That is what makes a plugin-side queue possible without the plugin
ever spending a mineral.

One more thing that matters: **neither start function checks whether something is already
running.** They just overwrite 0xC9/0xC8. Everything protecting the field is upstream, in the
gate. So any design that unblocks the gate MUST also intercept the handler, or the second
command clobbers the running upgrade and pays for it twice.

## 4. THE DESIGN — which of the two shapes, and why it is neither

Neither shape in the task fits unchanged:

* **025's inversion** ("keep the engine's slot free so the button stays live") cannot
  transfer. The engine's capacity here is exactly ONE. Free slot == nothing being researched;
  "keep it free" and "make progress" are the same variable pulling opposite ways.
* **A receive-side handler** cannot work either — §1 shows the command never arrives.

So it is a third shape, taking the *unblock* idea from the first and the *hold* idea from the
second:

**(a) UNBLOCK** — detour `upgradeGate` 0x0046DFC0 and `techGate` 0x0046DE90. When the feature
is on, the unit is a building, it is currently researching, and its logical queue is below the
cap: evaluate the ORIGINAL gate with 0xC9/0xC8 temporarily set to their idle sentinels, then
restore them before returning. One call, one thread, restored before anything else can look.
The card offers the buttons again and the client starts sending. Lift Off and Cancel read the
fields directly rather than through the gate, so they keep vanilla's answer.

  **At the cap the plugin simply stops lying.** The gate tells the truth, the layout hides the
  button, the client refuses on its own — the cap is vanilla's own mechanism, which is the
  property 025 valued most and it survives intact.

**(b) HOLD** — detour `cmdrecvUpgrade` 0x004C1B20 / `cmdrecvTech` 0x004C1BA0 at entry.
Resolve the acting building the way the engine does (reset selectionIterator 0x006284B6,
selNext 0x0049A850 twice, require exactly one). Already researching + room -> append {kind,id}
to the plugin's per-building record and return WITHOUT running the engine's body. Otherwise
pass straight through and let the engine start it and pay.

**(c) PROMOTE** — detour the two order handlers, `upgradeTick` 0x004546A0 and `techTick`
0x004548B0 (these are what count 0xC6 down and, on completion, clear 0xC9/0xC8 and flip the
level / researched arrays). Run the original; if the building has just gone idle and we hold
items, pop the OLDEST and run the engine's own accept path on it — `gate(unit,id,player)==1`
then `startUpgrade`/`startTech`. That is cmdrecvUpgrade's own body with the unit supplied by
the plugin instead of by the selection.

## 5. How it avoids paying twice

**The plugin never touches a resource global, in either direction.**

* Every item is paid by startUpgrade/startTech, at the moment it actually starts, out of the
  engine's own tables. There is no second payer, so "exactly once" is the SHAPE of the design
  rather than bookkeeping the plugin has to get right. Its own `spent` counter is asserted 0.
* A held item is **unpaid** — one id and nothing else. So dropping one (cancel, building
  destroyed, plugin unloaded mid-game) strands nothing and needs no refund. The entire class
  of refund bugs 025 had to reason about does not exist here.
* Before promoting, the plugin READS the cost tables and the two resource globals and only
  calls the start when the player can afford it. A comparison, not a transaction — it exists
  so the engine doesn't play its "insufficient minerals" error every frame while we wait.

**This is a deliberate divergence from vanilla, and I want you to see it before I build it:**
vanilla charges for a queued UNIT at queue time; this charges for a queued UPGRADE at start
time. I think that is the better bargain here — double payment becomes structurally
impossible, cancel becomes exactly correct for free, and a player who queues four upgrades and
then loses the building loses only the one actually running (which vanilla refunds itself).
Say so if you'd rather it charged up front and I'll do it that way instead; it costs a refund
path and a building-death path, i.e. 025's shape, and I'd rather not carry those without a
reason.

## 6. Cancel

While researching the card offers exactly one button and it means cancel. Matching 025's 0xFE
rule:

* plugin holds items -> drop its own MOST RECENT one, running upgrade continues, nothing
  refunded because nothing was paid. Press again to keep unwinding.
* plugin holds nothing -> straight through to vanilla, which cancels the running one and
  refunds it exactly.

No strong view; happy to make cancel always hit the running item instead if you prefer.

## 7. Scope, and what is refused

* One building. Not cross-building, not auto-repeat.
* **Queueing the SAME upgrade twice is refused, by the ENGINE and not by me.** The gate's
  other test, `upgradeBusy` 0x004281B0, reads a per-player-per-upgrade in-progress bitfield at
  0x0058F3E0 and hides that upgrade's own button while it runs, and I do not touch that test.
  So level N+1 cannot be lined up behind level N. The task said that was an acceptable answer
  if stated — stating it.
* BOTH opcodes covered: 0x32 Upgrade and 0x30 Tech. So an Academy can queue Stim behind U-238
  Shells, and an Engineering Bay Armor behind Weapons.

## 8. The flag, for the deployed launcher

**`-UpgradeQueue 1`** on run-with-plugin.ps1 / `%SCPLUGIN_UPGQ%=1`. OFF by default, ignored
outright in -Mode observe. Depth: `-UpgradeQueueMax` / `%SCPLUGIN_UPGQ_MAX%`, default 8 total
(the engine's 1 plus 7 held), clamped [1,16].

## 9. Files, and the 028 collision

Touched so far: `tools/plugin/probe-upgrade-wire.ps1` (new), four new Ghidra specs,
`research/upgrade-queue.md` + `research/data/upgrade-fields.tsv` (new), and two dict entries in
`tools/make_test_map.py` so a fixture can carry an Engineering Bay or an Academy.

To come: `tools/plugin/src/sc_upgrades.{h,cpp}` (new), `test-upgrade-queue.ps1` (new),
sc_addresses.h appended at the end, and the flag wired through run-with-plugin.ps1 +
scplugin.cpp. **I have not touched sc_prodqueue.cpp, test-production-queue.ps1 or
drive-game.ps1 and do not expect to** — every detour above is on a function 028 has no
interest in.

## 10. Foreground, as asked — and it is NOT clean, so here it is straight

watch-foreground.ps1 ran alongside both launches, and the two came out differently:

* **First launch (22:00).** Three brief game-foreground intervals, ~9 s total, all inside the
  menu walk; zero during the measurement phase.
* **The reported launch (22:20).** The game took the foreground at 22:20:32 — as its window
  was created — and **held it for 72 s, until it exited at 22:21:44**, i.e. across the whole
  run including the measurements.

The difference is what else was competing. In the first run my terminal and the user's Chrome
kept reclaiming it; in the second the desktop was idle, so nothing took it back.
`Send-ScDropdownPick` hands the foreground back to *whoever had it before the pick* — and by
then that was the game itself, because the launch had already raised it. So the "borrow and
return" is doing what it says; it just returns to the game when the game already had it.

I am not claiming this run did not steal focus. It did. It is pre-existing harness/launch
behaviour rather than anything this probe adds (the only raise it can cause is the
Set-ScGameType pick every suite makes), but the AGENTS.md expectation of "exactly one
borrow-and-return pair" does not hold on an idle desktop and someone should decide whether
that is worth a task.

Unrelated but worth you knowing: a **second** StarCraft (pid 2328) took the foreground at
22:22:43, a minute after mine exited — another worker's game. The launch lock did its job;
the two runs did not overlap.

Waiting on your nod before I write a line of sc_upgrades.
