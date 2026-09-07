# Widescreen (1280 wide, shown at 2x) -- quick card

One action: double-click **StarCraft Modded** on the desktop. That is the only
shortcut now: it launches the modded game with the extended viewport, in a
window twice the size (2560x960 on screen for the 1280x480 the game renders),
mouse locked to the window after your first click inside it (hold Ctrl or
Right Alt to free it). The old "(Wide)" shortcut is gone; this one is it.

## What you should see

1. A game window 2560x960: the playfield is 1280 game pixels wide -- twice the
   stock width -- shown at 2x. Height is unchanged for now (the 2x height is the
   next step).
2. **The menus look the same as always**, with a black band filling the extra
   width on the right. That is normal -- menu screens are fixed-size art; only
   the game itself is wider.
3. **In a game, the right HALF shows MORE MAP.** The playfield fills the full
   1280-wide window -- twice the world across, with correct fog, from the first
   frame (you do not have to scroll to make it appear).
4. All the usual mod features are on and unchanged: select-past-12, selection
   circles, the paging bottom row, the over-cap production queue with its `+N`
   badge, group production.

## Clicks on the right half

The map there is visible and the mouse behaves normally in it: the cursor can
enter the whole window, the edge-scroll-right zone sits at the true right edge
(the last couple of pixels), the camera stops where the 1280-wide screen meets
the map's edge, and a click on a unit there selects it (the click search rect is
1280 wide). All four were proven at 800 in real play (issue #113) and are the
same patch sites at 1280.

Two more from the first real play at 1280 (2026-09-07): **right-click orders
work on the map beside the console** (the strip level with the bottom bar, right
of it -- the game used to think that strip was console and dropped the order
while still letting you select there), and **the cursor no longer strobes or
turns into the plain arrow over the right half**. Both were one 640-wide test
inside the game plus one flag on the cursor layer; if either misbehaves, that
is news.

## Known imperfections (real, not dangerous)

1. **The bottom console (minimap, unit panel, command card) stays in its old
   place** -- it hugs the left 640 pixels, so the game reads as a normal
   console sitting in the left of a wider window. The command card is NOT at
   the window's bottom-right corner and the resource counters are NOT at the
   top-right; both end where the old screen used to. Everything on it works;
   it just does not stretch.
2. **The rectangle at the bottom-right** (right of the console, below the
   extended map: 640 wide, 80 tall in game pixels) is plain black and is NOT
   playfield: the game's playfield is 400 tall, so nothing can be selected or
   ordered there. The height step (2x tall) removes it.
3. **A minimap click centres the camera as if the screen were still 640 wide**:
   the clicked spot lands 320 game pixels left of the window's centre. The
   camera still goes where you click; it is just not centred on it. On the list
   for the height step.
4. **On space-platform maps** the starfield backdrop has a star-free band on
   the far right (the stars' positions come from a file that only covers the
   old width). Cosmetic, off-map only.

## If something goes wrong

- If the window fails to appear, a message box says why, and the details are
  in `logs\launch-error.log` next to the launcher. Closing the game yourself
  within a few seconds of launching it also trips that box (the launcher's
  health check runs 2 s after injection); that one is harmless.
- Whatever happens, your saves, characters, replays and settings are untouched.
