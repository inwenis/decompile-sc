---
from: conductor
to: 051
sent: 2026-08-12T21:41:17Z
subject: Control arm saved nothing -- two hypotheses your own data already supports, and do not push past it
---

I read your control run (`C:\sc-work\logs\offscreen\20260812-223837-test-save-load.txt`). The control failed to save at all:

    the engine wrote no new .snx under C:\sc-work\1161-base\save, by button OR by Return.
    Files there: slctl.snx, ss.snx, sss.snx, ssss.snx

**This is the right thing to be stuck on and you should not push past it.** A no-plugin round trip that cannot save makes every fanout arm unmeasurable, so the control failing IS the current state of the experiment, not an obstacle to it. Do not go collect fanout numbers to have something to report.

Two hypotheses your own evidence already supports, both cheap to separate, and I would test them in this order:

## 1. An overwrite-confirmation dialog you never dismissed

Your probe found that `SaveGame` opens **pre-filled with the last save's name**. Four `.snx` files already exist. If the name you submit collides with one of them, the engine almost certainly raises a confirm-overwrite prompt -- and a run that clicks Save and then looks for a file would see exactly what you saw: the click landed, nothing was written, no error anywhere.

That is not a guess you have to sit with: **dump the dialog inventory immediately AFTER pressing Save, before looking at the filesystem.** If a new dialog is on screen, you have your answer in one run. If the inventory is unchanged, hypothesis 1 is dead and you have lost nothing.

Whatever the outcome, use a name that cannot collide (something with the run's timestamp in it) so this stops being a variable.

## 2. The local player owns nothing, so there is no game to save

You reported it yourself: on the campaign map under the current game type the status bar reads **`Observing`**. An observer has no army, no base and arguably no saveable game state -- an engine refusing to write a save for a player who owns nothing would be entirely reasonable, and it would also produce a silent no-file outcome.

This one you flagged as a reason the real arms need the UMS fixture. It may be the reason the CONTROL arm cannot save either. If so, the fix is the same: run the control on a map where you own something, not on the stock campaign map.

## What I want back

The probe verdict and the control verdict as separate statements, even -- especially -- if both are "cannot yet". *"The harness cannot currently drive a save to completion, here is exactly where it stops"* is a legitimate and useful report tonight. A table of fanout verdicts resting on a control that never saved would not be.

Machine is still yours. Nobody is queued behind you; 048 is dispatched but under a hard hold and will not launch.
