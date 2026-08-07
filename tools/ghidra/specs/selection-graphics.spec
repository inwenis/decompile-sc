# Selection-GRAPHICS probe list for task 014 (draw circles under the fan-out units).
#
# label,addrHex
#
# Task 014 asks a question none of the earlier sweeps asked: what does the engine do to a UNIT
# when it becomes selected, and is any of it per-sprite state a plugin could set itself?
# research/selection-cap.md §2.4 records a CSprite `selectionIndex` and sprite flags
# `0x01 = draw selection circle` / `0x08 = selected` -- but both are INHERITED from BWAPI/GPTP
# and have never been checked against this binary. The functions below are the ones that own
# the transition, so their disassembly is where the answer has to come from.
#
# Every address is already established as a real function entry point in this binary
# (research/binary-selection-map.md §7: 23 of 23 inherited addresses resolved exactly) and is
# quoted from research/selection-cap.md §4.1-§4.5.

# --- becoming / ceasing to be selected -------------------------------------------------------
CreateNewUnitSelectionsFromList,0x0049AE40
selectMultipleUnitsFromUnitList,0x0049AEF0
addUnitToSelectionSlot,0x0049AF80
removeUnitFromPlayerSelection,0x0049A170
clearPlayerSelection,0x0049A740

# --- the receive side, which is what actually mutates playersSelections ----------------------
CMDRECV_Select,0x004C2750
CMDRECV_ShiftSelect,0x004C2560

# --- HUD refresh: reads the sim-side array every frame ---------------------------------------
updateSelectedUnitData,0x004C38B0

# --- the shift-click-out path selection-cap.md §2.4 names as the selectionIndex hazard --------
# GPTP hooks/interface/selection.cpp:627-635 computes a memcpy length from
# clicked_unit->sprite->selectionIndex here.
getSelectedUnitsAtPoint,0x0046F3A0
combineSelectionsLists,0x0046F290
