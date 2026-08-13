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
3. **CORRECTED (2026-08-13): in a game, the right quarter of the window is
   currently BLACK.** The engine really does compute the wider map -- more
   world, correct fog, the whole width scrollable -- but the step that copies
   the finished picture into the window still stops at the old 640 boundary
   while a game is running. So in play you see the normal-width map with a
   black band on the right, not 25% more map. An earlier version of this card
   said the map fills the full width; that was measured wrong on 2026-08-13
   (the wider picture exists internally, the window just never shows it), and
   fixing the copy step is being worked on as its own task. The menus are not
   affected.
4. All the usual mod features are on and unchanged: select-past-12, selection
   circles, the paging bottom row, the over-cap production queue with its `+N`
   badge, group production.

## One thing to know about clicks on the black band

The game's input for the right quarter IS switched on: clicks past the old
boundary reach the engine and act on the world there. Until the display fix
lands, that means a click on the black band can select or order units you
cannot currently see. Nothing breaks -- but if you notice "empty" clicks doing
things, that is what it is. Everything left of the old boundary behaves
exactly as it always did.

## Known imperfections (real, not dangerous)

1. **The bottom console (minimap, unit panel, command card) stays in its old
   place** -- it hugs the left 640 pixels, so the game reads as a normal
   console sitting in the left of a wider window. The command card is NOT at
   the window's bottom-right corner and the resource counters are NOT at the
   top-right; both end where the old screen used to. Everything on it works;
   it just does not stretch. Moving it right is being worked on separately.
2. **The small rectangle right of the console** (bottom-right, under the map)
   is plain black -- no artwork exists for a wider console. Measured across a
   whole session: it stays perfectly black and never flickers.
3. **Scrolling all the way to the RIGHT edge of a map** shows a thin band of
   stale pixels at the far right while you sit at the very edge (about 2% of
   that band). Scroll one screen left and it is gone. A known, bounded
   follow-up. (Until the display fix above lands, this one is academic -- the
   affected band sits inside the region the window does not show in game.)
4. **On space-platform maps** the starfield backdrop has a star-free band on
   the far right (the stars' positions come from a file that only covers the
   old width). Cosmetic, off-map only.

## If something goes wrong

- If the wide window fails to appear, a message box says why, and the details
  are in `logs\launch-error.log` next to the launcher.
- Whatever happens in the wide game, your saves, characters, replays and the
  normal shortcut are untouched -- close the wide window and double-click the
  normal one, and you are exactly where you were yesterday.
