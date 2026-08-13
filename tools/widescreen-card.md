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

1. TODO(session verdicts land here)

## If something goes wrong

- If the wide window fails to appear, a message box says why, and the details
  are in `logs\launch-error.log` next to the launcher.
- Whatever happens in the wide game, your saves, characters, replays and the
  normal shortcut are untouched -- close the wide window and double-click the
  normal one, and you are exactly where you were yesterday.
