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
3. **In a game, the right quarter now shows MORE MAP.** The playfield fills the
   full 800-wide window -- about 25% more world across, with correct fog, from
   the first frame (you do not have to scroll to make it appear). This is the
   fix that landed 2026-08-13: an earlier version of this card said the right
   quarter was black in game, which was true then -- the engine computed the
   wider map but the step that copies the finished picture into the window
   stopped at the old 640 boundary. That copy now carries the whole width.
4. All the usual mod features are on and unchanged: select-past-12, selection
   circles, the paging bottom row, the over-cap production queue with its `+N`
   badge, group production.

## Clicks on the right quarter

The game's input for the right quarter is switched on AND the map there is now
visible, so it behaves like the rest of the playfield: what you click is what
you see. (Before the display fix, clicks landed on a black band on units you
could not see; that mismatch is gone.)

## Known imperfections (real, not dangerous)

1. **The bottom console (minimap, unit panel, command card) stays in its old
   place** -- it hugs the left 640 pixels, so the game reads as a normal
   console sitting in the left of a wider window. The command card is NOT at
   the window's bottom-right corner and the resource counters are NOT at the
   top-right; both end where the old screen used to. Everything on it works;
   it just does not stretch. Moving it right is being worked on separately.
2. **The small rectangle at the bottom-right** (right of the console, below the
   extended map) is plain black -- no artwork exists for a wider console. It
   stays perfectly black and never flickers.
3. **Scrolling all the way to the RIGHT edge of a map** shows a thin band of
   stale pixels at the far right while you sit at the very edge (about 2% of
   that band). Scroll one screen left and it is gone. A known, bounded
   follow-up -- now visible in game, since the right quarter is shown.
4. **On space-platform maps** the starfield backdrop has a star-free band on
   the far right (the stars' positions come from a file that only covers the
   old width). Cosmetic, off-map only.

## If something goes wrong

- If the wide window fails to appear, a message box says why, and the details
  are in `logs\launch-error.log` next to the launcher.
- Whatever happens in the wide game, your saves, characters, replays and the
  normal shortcut are untouched -- close the wide window and double-click the
  normal one, and you are exactly where you were yesterday.
