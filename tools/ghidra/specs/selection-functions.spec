# Function addresses asserted by GPTP / teippi and tabulated in research/selection-cap.md
# §4.1-§4.5. Every one is INHERITED from a public project's source comment; none had been
# checked against StarCraft.exe before task 005. Labels are the source's names, not ours.
# Format: label,addrHex
#
# input path (selection-cap.md §4.1)
SortAllUnits,0046F0F0
selectionOverflowHandler,0046F040
combineSelectionsLists,0046F290
resolveClickedUnit,0046F3A0
applyNewSelect,0046FA00
unit_isUnselectable,0046ED80
unit_IsStandardAndMovable,0047B770
selectSingleUnitFromID,00496D30
CreateNewUnitSelectionsFromList,0049AE40
selectMultipleUnitsFromUnitList,0049AEF0
CMDACT_Select,004C0860
CMDACT_HotkeyUnit,004C07B0
# control groups / recent selections (§4.2)
hotkeySaveOrAdd,004965D0
hotkeyRecall,00496940
hotkeyLruSlot,00496560
# command receive path (§4.3)
CMDRECV_Select,004C2750
CMDRECV_ShiftSelect,004C2560
CMDRECV_Hotkey,004C2870
addUnitToSelectionSlot,0049AF80
clearPlayerSelection,0049A740
teamSelectionAllianceCheck,0049A110
# order dispatch (§4.4) and sound (§3 row 9)
getActivePlayerNextSelection,0049A850
compareUnitRank,0049A350
# HUD copy (§4.5). selection-cap.md names the function but gives no address for it -- GPTP
# reimplements it as updateSelectedUnitData without quoting one. Found by this task instead:
# 0x004C38B0 is the ONLY function in StarCraft.exe that references both activePlayerSelection
# (0x006284B8) and clientSelectionGroup (0x00597208), which is exactly what that copy does.
updateSelectedUnitData,004C38B0
# Functions that touch the selection globals but are NOT named anywhere in selection-cap.md --
# found by the task-005 cross-reference sweep, labelled from what the code does. Included so
# the constant inventory covers the storage-owning code, not only the functions prior art
# happened to name. Labels are descriptive, not authoritative.
clearSelectionHotkeys,004965A0
hotkeyGroupCompact,004967E0
hotkeyGroupHelper,00496B40
clearAllPlayerSelections,0049A320
clearClientSelectionGroup2,004BF8A0
clientSelectionGroup2Slot0Player,004BFA40
hudTeardownClearsClientSelection,004C3780
hudConsoleInitOwns0x00597238,004C3950
clientSelectionCountWriter,004C3BB0
hotkeyStorageUser004EEC30,004EEC30
selectionResetOnGameStart,004EED10
