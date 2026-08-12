---
from: conductor
to: user
sent: 2026-08-12T20:40:02Z
subject: Merged and deployed -- launch the shortcut, the fifth slot is an icon now
---

**Merged and deployed. Launch the shortcut and the fifth slot should be an icon, not a "2".**

## What I checked before merging, with my own eyes

The task made the human look the gate — a read-back oracle asking the plugin what the plugin drew
is what let this class of bug ship twice. So I opened all four frames myself rather than trusting
the numbers:

1. **Command Center, 8 SCVs, before** — four SCV icons and then a large blue **`2`** where the fifth
   should be. Your description was exact.
2. **After** — five SCV icons, the fifth carrying its slot number.
3. **Barracks, 8 Marines, before** — same slot, but *black*. Different unit type, different garbage,
   which is what proves it was one bug and not three.
4. **After** — five Marine icons, fifth labelled.
5. **Four Command Centers, before** — the text lands across the icon row, clipped to `ueued`,
   fighting the wireframes for the same pixels. Exactly *"behind the buildings icons so couldn't
   rly tell"*.
6. **After** — `4 bldgs  4 queued` sits in a clean band below the icons, fully readable.

The regression gate `test-production-queue` also finished with **0 failures** before the crash, and
local CI passed at the merge sha.

## The merge and the deploy

1. PR #55 — https://github.com/inwenis/decompile-sc/pull/55 — squash-merged as `25e4c62`.
2. Cloud CI still fails in 2 seconds on the billing error, so it went through on the local receipt
   as you authorised; `ruff` is not installed here and the receipt names it as not-run rather than
   pretending it passed.
3. Deployed at 21:39. The plugin your game loads is now
   `1B42626E48428E5CFCA5A26ADA86C6D24C4F5D2E7F196FCC487FB25B385D1AA6` — the pre-fix one you played
   twenty minutes ago was `B646C6A6…`. Different file, verified after the copy, not assumed.
4. Your saves, profiles and replays were excluded from the mirror and the preserved-data tripwire
   confirmed 8 files byte-identical across all five protected classes afterwards.

## Please just play it

The proof is off-screen frames from a scripted fixture. You queuing 10 SCVs by hand is a better test
than anything I can run. If the fifth slot is still wrong, or the count line reads oddly, tell me and
it goes straight back on the board.

## What is running now

1. **Task 050** — the six suites that force a visible window get routed through the wrapper that
   skips the dropdown. Dispatched now. When it lands, no test needs your screen.
2. **Task 051** — your save/load question. Cutting it next; nobody has ever tested a save written
   while the plugin is in fanout mode, so the honest answer is still "unknown".
3. One gap I am filing rather than fixing: the third rendering you saw (*"somehting blue flashing"*
   on another barracks) was never captured separately. Two unit types giving two different garbage
   frames and one identical fixed frame is enough to call it the same bug, but the third was not
   photographed and I would rather say that than imply it was.
