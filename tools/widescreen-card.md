# Widescreen (1280x880, twice the base viewport) -- quick card

One action: double-click **StarCraft Modded** on the desktop. That is the only
shortcut: it launches the modded game with the extended viewport. The game
renders 1280x800 of playfield (twice the base 640x400, both across and down)
with the console below it, in a 1280x880 screen. The window fills your monitor:
if a 2x window (2560x1760) fits your screen it uses that, otherwise it fills the
screen borderless, keeping the shape (black bars top/bottom or sides as needed).
The mouse is locked to the window (Ctrl+Tab or Right Alt+Right Ctrl frees it; a click locks it again).

## What you should see

1. **Twice the map, both ways.** In a game the playfield is 1280x800 game pixels
   -- twice the base width AND twice the base height -- so you see four times the
   map area, with correct fog, from the first frame (no need to scroll to make it
   appear).
2. **The bottom console moved DOWN to the bottom of the taller screen.** The
   minimap, unit panel, command card, chat line, F10 menu button and the bronze
   rails all sit along the bottom as they always did, now below the taller map.
   The top resource bar stays at the top.
3. **The menus look the same as always**, with a black band filling the extra
   space. That is normal -- menu screens are fixed-size art; only the game itself
   is bigger.
4. All the usual mod features are on and unchanged: select-past-12, selection
   circles, the paging bottom row, the over-cap production queue with its `+N`
   badge, group production. Right-click orders and the cursor behave normally
   across the whole map, including beside the console (fixed 2026-09-07).
5. **The fog of war stays put under the mouse.** Resting or moving the cursor over
   unexplored map no longer leaves 16-pixel slivers of terrain beside it (fixed
   2026-09-09: a base-game blitter quirk the bigger screen had started to show).
6. **No hitch while ordering a big group.** The mod wrote its log to disk line by
   line on the game's own thread; a busy minute of micro (a 47-unit group recalled,
   moved, production queued) wrote enough lines that the disk's slow moments became
   100-185 ms hitches (fixed 2026-09-09: the log no longer waits for the disk).
7. **Help tooltips sit next to what you hover.** The game clamps every tooltip to
   the old 640x480 screen, so a tooltip for the moved bottom bar was pushed 300 px
   up into the map (fixed 2026-09-09: three clamps now know the bigger screen).
8. **Tooltips and overlapping map sprites no longer flicker.** Two base-game
   shortcuts that the old dirty-cell present never showed: the console art was
   repainted over the tooltip every frame, and a repainted sprite overwrote its
   neighbours in cells the game never re-showed. The bigger screen shows the whole
   frame, so both became visible (fixed 2026-09-09: the tooltip layer draws every
   frame and the map takes the game's own full-redraw path every frame; the cost
   shows as `cpu_pct` on the `STORMTIME` line).

## Clicks anywhere on the bigger map

The mouse reaches the whole window: the cursor can rest anywhere, the edge-scroll
zones sit at the true edges, the camera stops where the 1280x800 screen meets the
map's edge, and a click selects the unit under it wherever it is (the click
search rect is the full 1280x800). The minimap centres the camera on the tile you
click, scaled for the bigger viewport.

## Known imperfections (real, not dangerous)

1. **Map shows faintly through the console's edges.** The console art has
   see-through gaps around its frame; now that map is drawn under the console,
   those gaps show terrain instead of black. Subtle, cosmetic, polish-later.
2. **On very tall maps the camera stops a little short of the very bottom row**,
   the same 24-pixel overscroll margin the base game has, scaled. You can still
   reach the whole map by minimap.
3. **On space-platform maps** the starfield backdrop has a star-free band past
   the base extent (the stars' positions come from a file that only covers the
   old size). Cosmetic, off-map only.

## If the game seems to lag

The plugin log (`logs\sc-plugin.log` next to the launcher) writes one `STORMTIME`
line per minute of play: `avg_ms`/`max_ms` are the gaps between the game's own
frame presents, `stalls100` counts gaps over a tenth of a second, `hook_max_us` is
the most the mod's frame copy ever cost, and `log_max_us` the most one log line
ever cost the game thread. Every gap over a tenth of a second also gets its own
`STORMSTALL` line saying how much of it (`log_us`, `hook_us`) was the mod's own
work. A long `dt_ms` with small numbers beside it means the engine or the machine
stalled, not the mod.

## If something goes wrong

- If the window fails to appear, a message box says why, and the details are
  in `logs\launch-error.log` next to the launcher. Closing the game yourself
  within a few seconds of launching it also trips that box (the launcher's
  health check runs 2 s after injection); that one is harmless.
- Whatever happens, your saves, characters, replays and settings are untouched.
