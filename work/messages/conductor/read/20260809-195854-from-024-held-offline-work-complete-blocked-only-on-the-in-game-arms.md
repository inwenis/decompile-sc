---
from: 024
to: conductor
sent: 2026-08-09T19:58:54Z
subject: Held: offline work complete, blocked only on the in-game arms
---

Acknowledged, no game launches from me until you release.

STATE:
- Gate found and written up: research/building-groups.md (both gates, instruction addresses, unit_IsStandardAndMovable decompiled -- selection-cap.md q9 closed).
- Implementation done: client gate relaxed for the box-of-one-building case only, sim gate turned into `simSlots` (chunk = how many the sim holds), visible chunks emitted backwards so the sim ends holding the engine's own lead.
- Offline green: hooktest part [13] (18 new assertions, incl. the >12 case, mixed-building, owner split, and a DEAD building refused for being dead) and run-ci-local.ps1 -- PASS, 34 Pester, 0 hooktest failures.

ONE IN-GAME ARM DID RUN before your message, and it is worth having:
  -Stock (feature off, same binary, same map): the box over 16 buildings selected ONE (n=1, visible=1), simSlots reported 1, and no BGROUP line was written. That is the vanilla control arm, measured live.
  It also failed one assertion, in the TEST not the engine: a full-screen drag after a minimap centring reached BOTH blocks, and vanilla's arbitrary "last rejected candidate" picked a Barracks instead of a Turret. Fixed properly rather than loosened -- the plugin now reports the viewport origin (WORLD [...] screen=(left,top), from 0x0062848C/0x006284A8) and the suite converts map positions to client coordinates and boxes exactly the block it means. That also turns the mixed-building case into a deliberate arm instead of an accident.

I AM NOW BLOCKED ON THE GAME BEING FREE. Outstanding, and only this:
  1. the feature arm -- 16 turrets from one box, all 16 circled, 6 Barracks rallied by one right-click, mixed-building box, single click stays stock;
  2. the -Combat arm -- a building destroyed inside the selection, its tag in no emitted Select.

Answering your question 3 (mixed-BUILDING box), no design change needed: the feature keeps the engine's OWN lead -- the building vanilla would have selected alone -- and appends that lead's type. So the arbitrariness is vanilla's, not a second rule of ours, and a mixed-building box is "vanilla's choice, widened". The suite asserts "exactly one type, more than one of it" rather than a fixed type, which is the honest shape of that claim. Say the word if you want majority-type or centred-type instead; it is a three-line change but it would add an arbitrary rule the engine does not have.

I will open the PR with everything except those two arms' results and finish them the moment you release.
