# Task 014, round 2: the per-unit selection-GRAPHICS primitives themselves.
#
# label,addrHex
#
# Round 1 (specs/selection-graphics.spec) decompiled CreateNewUnitSelectionsFromList
# (0x0049AE40) and found the engine's own answer to "what does the engine do to a unit when
# it becomes selected". It does exactly two things per unit, and neither of them is a flag
# the plugin was hoping for:
#
#     for each old entry in activePlayerSelection: entry = 0; FUN_004E6290()   // detach
#     for each new unit:  activePlayerSelection[i] = u; FUN_004E6180(i)        // attach, i = slot
#
# FUN_004E6180 takes the SLOT INDEX as its argument -- i.e. this is where selectionIndex is
# written, and where whatever makes the circle appear is done. These four addresses are the
# ones that transition actually calls.
selGfxAttach,0x004E6180
selGfxDetach,0x004E6290
selGfxAllied,0x004E65C0
allianceCheck,0x0049A110
