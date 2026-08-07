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
# Added in round 2. All four reference playersSelections (0x006284E8) and so were already in the
# cross-reference table, but they were missing from THIS list, so their constants never reached
# the immediate inventory. A review found the omission via 0x180 (384 = sizeof(playersSelections))
# which occurs only in the three save/load routines below.
#   0049A170 is the shift-click removal compaction: it scans playersSelections[player] 6-way
#   unrolled for the unit, then REP MOVSDs the tail down one slot and NULLs the last. It carries
#   three cap constants (MOV EBX,0xc / CMP EAX,0xc / CMP EBX,0xc) that were absent from the
#   round-1 inventory entirely.
#   004C2910, 004D02D0 and 004CFEF0 write and read the 384-byte playersSelections block through
#   the compressed-block helpers 0x004C3450 (fwrite) and 0x004C3280 (fread). All three carry
#   Starcraft\SWAR\lang\saveload.cpp debug strings; 004C2910 and 004D02D0 quote the SAME source
#   lines (0x677, 0x67e), i.e. one source routine emitted twice.
removeUnitFromPlayerSelection,0049A170
saveGameWriteBlocks,004C2910
loadGameReadBlocks,004CFEF0
saveGameWriteBlocks2,004D02D0
# Also round 2, closing the same gap for the rest of the playersSelections owners. After these,
# EVERY function that selection-xrefs.tsv shows touching playersSelections (0x006284E8) is swept,
# so the constant inventory can no longer be silently short a cap site in that array's code.
#   004CEE00 / 004CEDA0 are the pointer<->StoredUnit converters that bracket the save/load block
#   writes: 004CEE00 walks all 0x60 dwords turning CUnit* into (uniqueness << 11) | index,
#   004CEDA0 walks them back, checking CUnit+0xA5 for staleness. They are teippi's
#   ConvertUnitPtr<true>/<false> over bw::selection_groups, confirmed in the binary. Each carries
#   a hardcoded 0x60 element count.
# Labels for the remaining four are descriptive of what their instructions do, not authoritative.
saveLoadSelectionPtrToTag,004CEE00
saveLoadSelectionTagToPtr,004CEDA0
activePlayerSelectionWalk0049A2C0,0049A2C0
activePlayerSelectionWalk004C3B40,004C3B40
activePlayerSelectionUser00499A60,00499A60
activePlayerSelectionUser0049B870,0049B870
