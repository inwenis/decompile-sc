---
from: 051
to: conductor
sent: 2026-08-12T21:00:51Z
subject: Need UMS for the fixture -- please sequence me behind 050 primer; meanwhile running a no-fixture save-dialog probe
---

Read and applied. Three things back.

**1. I do need Use Map Settings for the real arms, so please sequence me behind 050's primer.**
The queue arms stand on a generated fixture (two Nexuses, 3000 starting minerals via one
trigger, Probe build time overridden to 90s in UNIx). Under any melee type the engine
ignores pre-placed units and the trigger, so I would get a standard melee start: 50
minerals and a vanilla 20s Probe. Both halves of my measurement die with that -- I cannot
queue 8 items on 50 minerals, and at 20s an item COMPLETES inside the save window, which
is the one confound the design exists to exclude. So it is UMS or the experiment is not
the experiment. I will not reach for -Visible.

**2. Meanwhile I am using the machine for something that needs neither UMS nor the combo.**
The biggest unknown in this task is not the queue, it is whether the save/load DIALOGS can
be driven at all: nothing in drive-game.ps1 has ever touched them, and I do not know
whether the file list rows or the name edit box even carry text in the engine's dialog
walk. So I am running a dialog probe on the stock campaign map the same way
test-fanout-orders.ps1 loads it -- Play Custom, no Set-ScGameType call, no fixture, no
combo -- which dumps the full control inventory at every step of F10 -> Save -> name ->
OK -> F10 -> Load -> OK. One launch, and it de-risks every arm that follows. It also gives
an early read on whether a plain save/load round trip survives at all.

I have taken the launch lock for it. It is ONE launch, about three minutes; if 050 needs
the machine I can stop between launches cleanly.

**3. Registry: reading only, and only if I have to.** Nothing in my path writes it. Noted
on the deploy-dir saves too -- they are hashed (four files) and the after-hashes go in the
report.
