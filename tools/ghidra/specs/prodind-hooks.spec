# Task 033 -- the queue-overflow indicator's ONE hook target, plus the two functions it
# has to run after.
#
# label,addrHex
#
# statDisplayDriver 0x004D93F0 -- the per-frame HUD driver (hud-selection-row.md 4.1):
#   it refreshes the selection data, updates the command card (0x004599A0) and then calls
#   the status-area dispatcher statDataUpdate (0x00458120). Task 033 detours THIS rather
#   than the dispatcher because (a) sc_hudrow already owns the dispatcher's 5-byte window,
#   and (b) running after the whole status pass -- single-unit branch AND multi-select
#   branch -- is what lets one indicator serve both the single-building "+N" and the
#   group-training line, and lets it re-show itself after the engine's hide-all sweep.
statDisplayDriver,0x004D93F0
#
# --- the two functions the indicator must not race, kept here for the probe's caller list ---
# statDataUpdate 0x00458120 -- the dispatcher the driver calls (sc_hudrow's target).
statDataUpdate,0x00458120
# statActBuilding 0x00427890 -- the per-unit-type status act for a producing building; it
#   is what lays out the five queue icons (via queueLayout 0x004268D0) and what hides the
#   dialog's children before doing so.
statActBuilding,0x00427890
queueLayout,0x004268D0
