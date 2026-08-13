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
   normal launcher shows, with fog of war correct everywhere, including the new
   right quarter. Scrolling (keyboard, minimap, screen edge) covers the whole
   width.
4. All the usual mod features are on and unchanged: select-past-12, selection
   circles, the paging bottom row, the over-cap production queue with its `+N`
   badge, group production.

## The ONE thing to test first, because we could not

**Click a unit standing in the new right quarter of the screen** (right of
where the old screen used to end). Does it select that exact unit? Then drag a
box across that area, and right-click ground there to move someone.

Our test rig drives the game with synthetic input on a hidden screen, and that
kind of input cannot reach this one code path in the wide window -- so mouse
clicks in the right quarter are the one thing nobody has been able to verify.
A real mouse may be entirely fine. If clicks there select the wrong unit or
nothing, say so and play on: everything left of the old boundary behaves
exactly as it always did, and a separate fix for the click mapping is already
being worked on.

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
   follow-up.
4. **On space-platform maps** the starfield backdrop has a star-free band on
   the far right (the stars' positions come from a file that only covers the
   old width). Cosmetic, off-map only.

## If something goes wrong

- If the wide window fails to appear, a message box says why, and the details
  are in `logs\launch-error.log` next to the launcher.
- Whatever happens in the wide game, your saves, characters, replays and the
  normal shortcut are untouched -- close the wide window and double-click the
  normal one, and you are exactly where you were yesterday.
