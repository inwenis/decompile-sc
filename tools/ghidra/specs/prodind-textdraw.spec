# Task 033 -- HOW THE STATUS PANE DRAWS TEXT.
#
# label,addrHex
#
# Every address below is an entry of one of the two DEFAULT per-control-type handler
# tables the .bin relocator 0x004194E0 assigns from (hud-selection-row.md 3):
#   interact table 0x005014AC, update table 0x00501504, both indexed by controlType.
# Dumped straight out of .rdata by work/scratch/033/peek.py (which parses the PE section
# table out of the same file it reads), NOT inherited from any public map:
#
#   type  interact     update
#    8    0x00416980   0x004FA00 -> 0x004EFA00
#    9    0x00419190   0x004EF9E0     <- LSTATIC (left-aligned static text)
#   10    0x00419190   0x004EF9C0     <- same interact, different draw (alignment)
#   11    0x00419190   0x004EF9A0     <- same again
#
# Types 9/10/11 sharing ONE interact and having THREE different updates is the shape a
# left/right/centre aligned static-text triple has, and it is the runtime evidence
# sc_hudrow's indicator already leans on (it refuses to splice if either entry is null).
staticTextInteract,0x00419190
staticTextUpdateType9,0x004EF9E0
staticTextUpdateType10,0x004EF9C0
staticTextUpdateType11,0x004EF9A0
# The generic control update entry point the act calls (0x0041C400) -- how an update
# handler is reached at all.
updateControl,0x0041C400
