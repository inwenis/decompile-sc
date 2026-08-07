# Hook-target probe list for task 011 (fan-out plugin).
#
# label,addrHex
#
# Every address below is quoted from research/binary-selection-map.md and
# research/selection-cap.md §4.1/§4.3/§4.4/§4.5, where each was already confirmed to be a real
# function ENTRY POINT in this binary (binary-selection-map.md §7: 23 of 23 inherited addresses
# resolved exactly). This probe asks the next question those documents do not answer: what does
# each function's PROLOGUE look like, so a 5-byte detour can relocate it safely, and -- for the
# command queue -- WHO calls it, which is how the order-emitting command builders are found.

# --- the command path: the single funnel every outgoing command passes through -----------------
# binary-selection-map.md §6.3: CMDACT_Select "builds three distinct command buffers and queues
# each through 0x00485BD0". Its caller list is the inventory of command builders.
queueCommand,0x00485BD0
CMDACT_Select,0x004C0860
CMDACT_HotkeyUnit,0x004C07B0

# --- the input path: where an untruncated selection can be observed ----------------------------
# selection-cap.md §4.1.
SortAllUnits,0x0046F0F0
sortOverflowHandler,0x0046F040
combineSelectionsLists,0x0046F290
resolveClickedUnit,0x0046F3A0
applyNewSelect,0x0046FA00
CreateNewUnitSelectionsFromList,0x0049AE40
selectMultipleUnitsFromUnitList,0x0049AEF0
unit_IsStandardAndMovable,0x0047B770
unit_isUnselectable,0x0046ED80

# --- receive side + dispatch, for reference --------------------------------------------------
CMDRECV_Select,0x004C2750
CMDRECV_ShiftSelect,0x004C2560
getActivePlayerNextSelection,0x0049A850
addUnitToSelectionSlot,0x0049AF80
clearPlayerSelection,0x0049A740
updateSelectedUnitData,0x004C38B0
removeUnitFromPlayerSelection,0x0049A170
