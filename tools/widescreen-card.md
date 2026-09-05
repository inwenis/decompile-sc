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
   the first frame (you do not have to scroll to make it appear). History, so
   the card stays honest: the engine has computed the wider map since
   2026-08-13, and the step that copies the finished picture into the window
   used to stop at the old 640 boundary. The wider copy was written the same
   day -- but the launcher shipped it switched OFF, which is the black right
   band you saw (issue #113). Since 2026-09-05 the (Wide) launcher turns the
   copy on by name.
4. All the usual mod features are on and unchanged: select-past-12, selection
   circles, the paging bottom row, the over-cap production queue with its `+N`
   badge, group production.

## Clicks on the right quarter

The map there is now visible and the mouse behaves normally in it. Two bugs the
first wide build had here were fixed 2026-09-05:

1. **The mouse could not enter the right band at all** -- Windows itself was
   confining the pointer to the old 640 columns (the game asks the OS to clip
   the cursor to its play area, and that area was hardcoded at 640), and the
   camera scrolled the moment the pointer hit that invisible wall, as if the
   screen were still 640 wide. Both halves are fixed together: the clip is now
   800 wide, and the edge-scroll-right zone sits at the true right edge (the
   last couple of pixels), like the stock game. An intermediate build
   (2026-09-05, first pass) moved the scroll zone before the clip and left
   mouse scroll-right dead; that is the build you reported on.
2. **A rare crash** (`0x0041DE84 ... memory could not be read`) when a menu or
   tooltip drew a hair off the screen edge. Harmless in the stock game, it began
   faulting once the widescreen build moved an internal table; it now has a
   safety margin on both sides and cannot fault there.

Whether a *click* on a unit in the far-right quarter selects it is the one thing
no automated test on this machine can check (nothing here can drive a real mouse
into that band). It is your first thing to try — the map and cursor are both
correct there now, so a click should act on what you see.

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
