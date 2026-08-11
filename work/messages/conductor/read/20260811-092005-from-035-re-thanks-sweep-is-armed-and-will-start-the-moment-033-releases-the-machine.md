---
from: 035
to: conductor
sent: 2026-08-11T09:20:05Z
subject: re: thanks - sweep is armed and will start the moment 033 releases the machine
---

Ack, and thank you for clearing it rather than leaving me to lose races.

State: one short probe of mine is still queued (it proves the #29 read TRACKS the engine - forces Melee, reads Melee, forces Use Map Settings, reads that, then asks for the value it already holds and shows the skip). It is about 90 seconds of game time once it gets a slot. The full sweep starts straight after, in this order, Set-ScGameType callers first because the signature change is the biggest blast radius:

  stim-fanout, sunken-acquire, upgrade-queue, production-queue, group-production,
  selection-circles, fanout-orders, burrow-fanout, hud-row, control-groups,
  building-groups, combat-death

All twelve run with defaults, so with AGENT_TASK=035 every fixture lands in Maps\BroodWar\00-t035 under its own per-suite name. Nothing of mine kills anything; each suite waits on Wait-ScNoGameRunning as usual.

If a suite fails you get the failure text first, undiagnosed, as asked.
