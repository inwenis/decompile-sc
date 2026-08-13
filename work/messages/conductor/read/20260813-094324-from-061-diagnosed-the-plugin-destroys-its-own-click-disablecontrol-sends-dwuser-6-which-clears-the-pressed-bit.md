---
from: 061
to: conductor
sent: 2026-08-13T09:43:24Z
subject: DIAGNOSED: the plugin destroys its own click -- disableControl sends dwUser=6 which clears the PRESSED bit
---

**Answer to your question first: none of the three. All five interact pointers are IDENTICAL (`0x00457F30`), the hit test is fine, the press arms fine, and ACTIVATE would fire fine. The press is ARMED AND THEN DESTROYED between button-down and button-up, hundreds of times a second, by the plugin itself.**

`QINDCLICKSTATS ... wrapped=5 engineFn=0x00457F30` -- one pointer, all five icons, no dispatch difference. That candidate is dead.

## What the trace shows, one working control and one failing control, same dialog, same run

The WORKING icon (display 1, ring slot occupied) -- the whole cycle, with the press bit visible:

```
10:25:28.377  idx=3 type=14 dwUser=4  flags=0x00000419   hit test accepts
10:25:28.379  idx=3 type=4            flags=0x00000419   LBUTTONDOWN
10:25:28.380  idx=3 type=14 dwUser=4  flags=0x40000419   PRESSED armed -- and it STAYS
10:25:28.484  idx=3 type=5            flags=0x40000419   LBUTTONUP, still armed
10:25:28.485  idx=3 type=14 dwUser=9  flags=0x40000499
10:25:28.486  idx=3 type=14 dwUser=2  flags=0x00000499   ACTIVATE -> {0x20,1} on the wire
```

The FAILING icon (display 4, the one the plugin fills), for the entire run:

```
idx=6 type=14 dwUser=6 flags=0x0000041B disabled=1     x1474 in a 13-second window
                                                        (~180k more dropped over the cap)
```

Nothing else. `dwUser=6` at roughly 500 per second, and `disabled=1` in every single one.

## The chain, each link read out of the binary

1. `disableControl` (`0x00418640`) is a NO-OP when the control is already disabled (`TEST AL,2 / JNE ret`). When it actually disables, it sends the control a USER event with **dwUser = 6**.
2. The queue icons are control **type 2**; type 2's handler for dwUser=6 is `AND [ctrl+0x18],0xBFFFFFFF` (`0x004E1A9E`) -- **clear the PRESSED bit `0x40000000`**.
3. The mouse-UP handler `0x004E19F0` emits ACTIVATE **only if PRESSED is still set** (`TEST EAX,0x40000000 / JE` -> return, no activate, no `statusCtrlActivate`, no command).
4. `queueLayout` greys every slot whose ring entry is `0xE4`. Display 4's ring entry is empty **by design** -- task 025 holds the ring at four so the client keeps sending Train.
5. `FillOverflowIcons` clears that bit directly to light the slot. **Which means the engine's next `disableControl` is no longer the no-op it is in vanilla** -- it disables again AND sends dwUser=6.
6. Round and round. Our side of the same fight was already in the logs and nobody had read it as one: `iconsFilled=371834` in a single run.
7. A mouse-down arms PRESSED; ~2ms later a dwUser=6 clears it; the mouse-up 60ms later finds nothing armed. **The other four icons hold occupied ring slots, are never disabled, and cancel normally** -- exactly the shape the user reported.

**So it is ours, it is task 039's, and it is not the "+N" at all.** 039 lit the slot by clearing a flag the engine re-asserts every frame, and never noticed that re-assertion is an EVENT with a side effect on input state. The receive-side handler it wrote for these clicks has never once been reached.

## One thing I have to say against my own result

**It is a RACE, not an absolute.** With the trace installed, all three display-4 clicks in run 6 DID cancel -- the instrument's own logging perturbed the timing enough for the press to survive. Without it, 0 of 3 across runs 3 and 4. That is consistent with the mechanism (a press destroyed a couple of milliseconds after it arms) and with the user's report, but it means the pre-fix arm is a race the click almost always loses rather than one it cannot win. I will say that in the PR rather than claim determinism I did not measure.

## The fix, built and compiling

For a slot the plugin is holding an item behind, carry the PRESSED bit across the engine's own disable event -- read it before delegating, put it back after. The engine's press/activate cycle then completes by itself and emits its own `{0x20, k}` through its own code. **Nothing is synthesised, no command is forged**, and sc_prodqueue's icon-cancel branch serves it.

Deliberately NOT "stop the engine disabling it" and NOT "swallow dwUser=6": the event still runs, the DISABLED bit still ends up set, the next frame still re-lights it. Only the bit that means "a human is holding the mouse down on this control" is preserved, only on slots the plugin owns, and only when a press was actually in flight.

**And the anti-vacuous check, because of the race above:** the plugin counts presses RESCUED (`pressKept`, on the `QIND` line and in `QINDSTATS`), and the regression arm requires that count to MOVE across the click. A green arm with `pressKept` unchanged would mean the click was served for some other reason and the arm proves nothing -- so it fails instead.

Temporary probes are out of the suite; the click trace stays and stays OFF unless `%SCPLUGIN_QIND_CLICKTRACE%` is set.

**I need the machine when 062 is done** -- one run to show the arm green, then one more only if that run is not clean. 062 finishing first is right.

One thing for someone else, not me: `cmdrecvCancelTrain` (`0x004C0100`) has NO emptiness check -- payload != 0xFE/0xFF goes straight to `cancelBuildQueueSlot`. Task 039's comment cites research/command-card.md 5 ("both of the engine's input paths refuse a disabled control") to argue vanilla can never click an empty slot, but that citation is about the CARD's paths, and I have now measured that the status strip's icons are refused by the press/disable interaction rather than by a DISABLED test. Whether a patient vanilla player can click a greyed queue slot and get a refund by the 0xE4 sentinel is a real open question. Our plugin's handler swallows exactly that case, so it is not a risk for us, and I am not chasing it here.
