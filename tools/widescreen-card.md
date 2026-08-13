# Widescreen (800 wide) -- quick card

One action: double-click **StarCraft Modded (Wide)** on the desktop.

That is the whole switch. Your normal **StarCraft Modded** shortcut is unchanged
and still launches the game exactly as before -- widescreen is only ever on when
you pick the (Wide) shortcut, and nothing needs turning back off.

## What you should see

1. A game window a bit wider than the old one (800x480 instead of 640x480).
2. **The menus look the same as always**, with a black band filling the extra
   width on the right. That is normal -- menu screens are fixed-size art; only
   the game itself is wider.
3. In a game, the map fills the full width: **25% more map on screen** than the
   normal launcher shows. Scrolling, clicking, selecting, giving orders and
   placing buildings all work across the whole width, including the new right
   quarter. Fog of war is correct everywhere, including there.
4. All the usual mod features are on and unchanged: select-past-12, selection
   circles, the paging bottom row, the over-cap production queue with its `+N`
   badge, group production.

## Known imperfections (real, not dangerous)

1. **The bottom console (minimap, unit panel, command card) stays in its old
   place** -- it hugs the left 640 pixels, so the game reads as a normal
   console sitting in the left of a wider window. The command card is NOT at
   the window's bottom-right corner, and the resource counters are NOT at the
   top-right; both end where the old screen used to. Everything works -- the
   minimap, every button, every readout -- it just does not stretch. Moving it
   right is its own future piece of work.
2. **The little rectangle right of the console** (bottom-right corner, below
   the map, about 160x80) has no artwork of its own -- no art exists for a
   wider console, and drawing new art is out of bounds for this project.
3. **Scrolling all the way to the RIGHT edge of a map** shows a band of
   stale/garbled columns at the far right for as long as you sit at the very
   edge. The camera's right-edge stop is still the old one. Scroll one screen
   left and it is gone. Fix is a known, bounded follow-up.
4. **On space-platform maps** the starfield backdrop has a star-free band on
   the far right (the stars' positions come from a file that only covers the
   old width). Cosmetic, off-map only.

## If something goes wrong

- If the wide window fails to appear, a message box says why, and the details
  are in `logs\launch-error.log` next to the launcher.
- Whatever happens in the wide game, your saves, characters, replays and the
  normal shortcut are untouched -- close the wide window and double-click the
  normal one, and you are exactly where you were yesterday.
