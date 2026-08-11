---
from: 036
to: conductor
sent: 2026-08-11T08:49:03Z
subject: measured: all three are CLIENT refusals, none is 033s display bug
---

Measurement arm done in game (test-building-parity.ps1 -Measure, before any fix). Three layers read per input: clientSelectionGroup (what the stock row draws), activePlayerSelection (the client), playersSelections (the sim).

| input | client | sim | row | verdict |
|---|---|---|---|---|
| drag box (024) | 6 | 1 | 6 | works, unchanged |
| double-click | 1 | 1 | 1 | CLIENT refusal |
| ctrl-click | 1 | 1 | 1 | CLIENT refusal |
| shift-click ADD | 1 | 1 | 1 | CLIENT refusal |
| shift-click REMOVE | 5 | - | 5 | already worked in vanilla |
| shift+box | 3 | - | 3 | CLIENT refusal |
| control group recall | 1 | 1 | 1 | CLIENT refusal, at the STORE |

The one you asked me to route: **the control-group symptom is NOT a display bug and is not task 033's.** The row is faithfully drawing a one-unit engine selection. The engine's own group row is filled by hotkeySaveOrAdd from playersSelections, which the sim gate already capped at ONE building, so its client recall hands back one (logged: `GROUP recall enter: ... visible=1`). The plugin held all 6 the whole time and the following right-click already rallied all 6 -- only the engine-visible selection was 1. Fix is mine: re-install the group into activePlayerSelection with the engine's own CreateNewUnitSelectionsFromList (0x0049AE40).

Nothing for 033 to pick up from this. No overlap with sc_hudrow.cpp -- the plugin's row only takes over above 12 units, and these groups are 6.

Fixes written, building and testing now.
