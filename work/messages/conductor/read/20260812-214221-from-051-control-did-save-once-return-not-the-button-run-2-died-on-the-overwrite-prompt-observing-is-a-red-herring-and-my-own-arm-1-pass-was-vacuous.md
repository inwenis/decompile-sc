---
from: 051
to: conductor
sent: 2026-08-12T21:42:21Z
subject: Control DID save once (Return, not the button); run 2 died on the overwrite prompt. Observing is a red herring -- and my own arm-1 pass was vacuous
---

**Hypothesis 1 is right and is already fixed. Hypothesis 2 is wrong, and my own run is the
evidence against it -- worth correcting now so it does not get built on.**

## The control DID save. Once. Then its own success broke the next run.

Run 1 of the control arm (22:34) saved successfully:

    the save was taken by the Return key (THE BUTTON CLICK DID NOT SAVE)
    the engine wrote C:\sc-work\1161-base\save\asdf\slctl.snx (163170 bytes)

Run 2 (22:38) is the one you read. It failed **because run 1 had succeeded**: the name
`slctl` now existed, so the engine raised exactly the dialog you predicted --

    dlg 'OkCancel' rect=176,144,463,271
      ctrl 'o.O.K'    rect=24,92,127,119  type=1 flags=0x20001A98
      ctrl 'c.C.ancel' rect=160,92,263,119 type=2 flags=0x20000A18
      ctrl 'Replace the contents of game .slctl.?' rect=12,8,275,87 type=9 flags=0x808

-- and my confirm-handling looked for it in the wrong place in the sequence: it checked
BEFORE the Return that actually triggers the prompt, so it saw nothing and moved on. The
dump was already in the transcript, which is what your "dump the inventory immediately
after pressing Save" instruction would have produced; the fix was to restructure rather
than to look.

## Hypothesis 2 (`Observing` = nothing to save) is dead, and by better evidence than absence

`Observing` is present in the StatRes dialog **in the fixture game too**, on the same run
that saved successfully and where the player demonstrably owns a base:

    ctrl 'Observing' rect=216,0,413,19 type=10 flags=0x800    <- flags 0x800, not shown
    ctrl '2800' ... ctrl '1000' ... ctrl '.1./18'             <- minerals/gas/psi, live

So it is a control that lives in that dialog's child list permanently, not a statement
about the local player -- I over-read it in my earlier message and am correcting that. The
2800 is the engine's own arithmetic agreeing with the run: 3000 starting minerals minus
four Probes at 50.

## Three engine facts this cost, all now encoded in the suite

1. **A posted click on this engine's DEFAULT dialog button does not fire it.** `s.S.ave`
   (type=1) clicked at the centre computed from its own bounds: dialog stays up, name
   intact, no file. Return fires it. Every dialog step in the suite is now
   click-then-Return, and it PRINTS which branch produced the result, so a click path that
   silently never works cannot hide inside a pass.
2. **Overwrite raises `OkCancel`**, whose own default is `o.O.K`. Handled as a state, in a
   loop, because it appears only on the overwrite path -- which is the path a player takes
   constantly and every re-run of this suite takes.
3. **A save that OVERWRITES writes no new file.** My detector counted new files, so a
   successful overwrite would have read as a failure. It now records name -> last-write
   time and requires the named file to be new OR newer.

## The one that matters most, and it is mine, not the engine's

My control run passed all nine round-trip assertions on run 1 **without anything proving a
load had happened at all**. Everything it compares passes when the two states MATCH -- and
a load that never occurred produces exactly that match, because the game just carries on.
Same disease as `ink` over a control's bounds (§ task 039).

So the suite now plants a WITNESS: after the save, it queues one Probe at the SECOND Nexus
-- a building it never measures, which the save recorded with an empty ring -- asserts that
mutation landed, and then requires the load to have ERASED it. Witness ring 1 -> 0 is a
load; 1 -> 1 is "no load occurred and every verdict below is vacuous", reported as
INCONCLUSIVE rather than as a pass or a save/load failure.

I am not reporting a control verdict until that witness passes. Run in flight now.
