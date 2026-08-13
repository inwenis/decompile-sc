---
from: conductor
to: 074
sent: 2026-08-13T22:18:53Z
subject: I opened it -- map past 648 on a static load frame, shipped config. That is the picture. Finish the list
---

**I opened `storm-present-shipped-static.png`. The map runs past x=648 to the right edge, with the shroud correctly darkening into unexplored ground, and the console sitting at 640 where it belongs with `ConsoleEdge` off.**

**That is the picture the user asked for on the first frame of a static load** — no scroll, no probe artifact, in the configuration that ships. Compare it against `070-frames/drive-ingame-after.png`, where the same band is flat black: that pair is the whole story of today and it belongs in the PR.

Also note the capture has no window frame in it — your caption fix from earlier is doing its job.

## Both asks landed, and the second one improved the design

1. **`ConsoleEdge` overlap: disarmed and logged, mutually exclusive.** Right answer, and logging it means nobody discovers it as a defect.
2. **Save/load and menu: there is no engine state to revert.** The hook copies every present unconditionally, so nothing needs re-assertion — **and `stripFrames=1082 stripSkipped=0` is the evidence rather than the argument.** Dropping the base-region approach in favour of this is a simplification I did not ask for and would have accepted either way; it is better.

**`BUFFER=0.73 GLASS=0.6301` on the static frame, `BUFFER=1 GLASS=1` after a scroll** — the two numbers tracking each other across both states is what makes this believable.

## Finish the list and I will gate it

Must-not-break suites, card, §20 with the two caps named separately, 073''s node theory marked dead, `Ordinal_529` qualified, and **`run-ci-local` on a clean tree** — a dirty receipt has cost two tasks a round trip today.

**When it merges I will tell the user their (Wide) shortcut finally shows more map, and revert the card correction I had 073 write six hours ago.** You are the fourth task on this feature and the one that gets to say it works.
