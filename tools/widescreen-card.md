# Widescreen (1280 wide) -- quick card

One action: double-click **StarCraft Modded (Wide)** on the desktop.

That is the whole switch. Your normal **StarCraft Modded** shortcut is unchanged
and still launches the game exactly as before -- widescreen is only ever on when
you pick the (Wide) shortcut, and nothing needs turning back off.

## What you should see

1. A game window twice as wide as the old one (1280x480 instead of 640x480).
   Until 2026-09-06 this shortcut gave 800x480; the same build now gives the
   full 2x width. Height is unchanged for now (the 2x height is the next step).
2. **The menus look the same as always**, with a black band filling the extra
   width on the right. That is normal -- menu screens are fixed-size art; only
   the game itself is wider.
3. **In a game, the right HALF now shows MORE MAP.** The playfield fills the
   full 1280-wide window -- twice the world across, with correct fog, from the
   first frame (you do not have to scroll to make it appear).
4. All the usual mod features are on and unchanged: select-past-12, selection
   circles, the paging bottom row, the over-cap production queue with its `+N`
   badge, group production.

## Clicks on the right half

The map there is visible and the mouse behaves normally in it: the cursor can
enter the whole window (the OS cursor clip is 1280 wide), the edge-scroll-right
zone sits at the true right edge (the last couple of pixels), the camera stops
where the 1280-wide screen meets the map's edge, and a click on a unit there
selects it (the click search rect is 1280 wide). All four were proven at 800 in
real play (issue #113) and are the same patch sites at 1280.

Whether a *click* on a unit in the far-right half selects it with a REAL mouse
is still the one thing no automated test on this machine can check (nothing
here can drive a real mouse past x=639). It is your first thing to try.

## Known imperfections (real, not dangerous)

1. **The bottom console (minimap, unit panel, command card) stays in its old
   place** -- it hugs the left 640 pixels, so the game reads as a normal
   console sitting in the left of a wider window. The command card is NOT at
   the window's bottom-right corner and the resource counters are NOT at the
   top-right; both end where the old screen used to. Everything on it works;
   it just does not stretch.
2. **The rectangle at the bottom-right** (right of the console, below the
   extended map: 640 wide, 80 tall) is plain black -- no artwork exists for a
   wider console. It stays perfectly black and never flickers.
3. **A minimap click centres the camera as if the screen were still 640 wide**:
   the clicked spot lands 320 px left of the window's centre. The camera still
   goes where you click; it is just not centred on it. On the list for the
   height step.
4. **On space-platform maps** the starfield backdrop has a star-free band on
   the far right (the stars' positions come from a file that only covers the
   old width). Cosmetic, off-map only.

## If something goes wrong

- If the wide window fails to appear, a message box says why, and the details
  are in `logs\launch-error.log` next to the launcher.
- Whatever happens in the wide game, your saves, characters, replays and the
  normal shortcut are untouched -- close the wide window and double-click the
  normal one, and you are exactly where you were yesterday.
