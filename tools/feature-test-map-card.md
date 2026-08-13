# Feature test map -- quick card

**Not in the map list?** A redeploy is meant to put it back on its own. If it is ever
missing anyway, open a terminal in the repo and run:

```
./tools/make-feature-test-map.ps1
```

Wait two seconds, then refresh the map list (back out and back in). No game needs to
be running for this.

The file is `zz-feature-test.scx` -- named `zz-` on purpose, so it sorts to the
bottom of the list and is easy to spot among the stock maps.

## Load it

1. Main menu -> **Single Player** -> **Expansion** -> **Play Custom**.
2. Set **Game Type** to **Use Map Settings**.
3. Pick **zz-feature-test.scx** (it should be right there when the browser opens) -> **OK**.

You start facing 13 Command Centers in a 4-wide block, nothing else on the map, no
enemy anywhere.

## Walk through, fastest first

1. **Drag a box around all 13 buildings.** The bottom of the screen shows a count and
   a page indicator: `13 units 1-12 (1/2)`. **Right-click on that bottom row itself**
   (not on a building, not on the ground -- the row of little portraits at the very
   bottom of the screen) -> it flips to `13-13 (2/2)` and shows the last one. **This
   is the first time this project has ever proven a group of BUILDINGS pages past
   12** -- every earlier test used mobile units.
2. **Click empty space to deselect, then click just one Command Center.** Click its
   **Train SCV** button six to nine times, fairly quickly. Watch the production row:
   five icons fill, then a `+N` badge appears on the last one for everything past
   five. That `+N` badge and the fifth slot are both the feature.
3. **With that same building still holding a queue, click the last icon in its row**
   (the one next to the `+N` badge). It should cancel that item and refund its cost
   -- watch the mineral count go up. *(This exact click is the subject of a separate
   open bug, issue #061 -- if it looks wrong, that is expected until that issue is
   fixed, not a problem with this map.)*
4. **Drag a box around just two or three of the buildings, then click Train once.**
   Every building in the box queues one SCV from that single click -- that is the
   group queue indicator working across a multi-building selection.
5. **Save and reload.** Press **F10** -> **Save Game** -> type any name -> Save.
   Then **F10** -> **Load Game** -> pick that save. Everything -- the buildings,
   their queues, your minerals -- should come back exactly as you left it.

Selection circles are on the whole time -- every building you select in steps 1-4
should show one; there is no separate step for it.

## What this map does NOT cover, and why

- **Any ability that costs energy or hit points** (Stim Packs, Cloak, Burrow). Those
  need a second unit type and researched tech, which is a different fixture, not a
  bigger version of this one.
- **A unit dying while selected.** That needs a hostile force on the map, which
  breaks the "sits there and does nothing until you're ready" property every other
  feature here depends on.
- **Anything about mobile-unit selection specifically** (as opposed to buildings) --
  earlier fixtures already proved that; this map exists to prove the BUILDING case,
  which hadn't been.

If you want either of those too, ask for a second map -- it should not be bolted onto
this one.
