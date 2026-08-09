# Control-group (hotkey) code, task 021.
#
# label,addrHex
#
# Every address below is either (a) a function entry point already evidenced in
# research/binary-selection-map.md, or (b) an INSTRUCTION address quoted there, seeded
# deliberately so FuncProbe reports the containing function rather than this task guessing
# an entry point. Rows of the second kind are prefixed `in-`.
#
# Provenance, one line each:
#   CMDACT_HotkeyUnit      binary-selection-map.md 6.3 -- "builds a 3-byte command with id 0x13"
#   CMDRECV_Hotkey         binary-selection-map.md 6.4 -- "0x004C2870 is a 19-instruction
#                          dispatcher that forwards to 0x004965D0 / 0x00496940"
#   hotkeySaveOrAdd        binary-selection-map.md 6.1 -- the entry decoder is quoted from it
#   hotkeyOther            the dispatcher's OTHER forward target, unread by any prior task
#   lruPickRecentSlot      binary-selection-map.md 5.2 -- CALL 0x00496560 then ADD AL,0xa
#   in-hotkeyClear         0x004965A3 = MOV ECX,0x6C0 before REP STOSD over selectionHotkeys
#                          (binary-selection-map.md 3.5); the entry is a few bytes earlier
#   in-selectSingleUnitFromID
#                          0x00496D41 = IMUL EDI,EDI,0x360, the per-player hotkey stride
#                          (binary-selection-map.md 3.5/2.3 note 4)
#   in-gameStartHotkeyClear
#                          0x004EEC73 = the second REP STOSD over the same array
#   CreateNewUnitSelectionsFromList / selectMultipleUnitsFromUnitList
#                          sc_addresses.h; the client-side selection funnels a recall must reach
#   clearPlayerSelection / addUnitToSelectionSlot / getActivePlayerNextSelection
#                          the receive-side trio a recall's Select would land in

CMDACT_HotkeyUnit,0x004C07B0
CMDRECV_Hotkey,0x004C2870
hotkeySaveOrAdd,0x004965D0
hotkeyOther,0x00496940
lruPickRecentSlot,0x00496560
in-hotkeyClear,0x004965A3
in-selectSingleUnitFromID,0x00496D41
in-gameStartHotkeyClear,0x004EEC73
# The three entry points FuncProbe resolved for the `in-` seeds above, so later runs can
# name them directly (hotkey-funcprobe.tsv: INSIDE-FUNCTION -> funcEntry).
hotkeyClear,0x004965A0
selectSingleUnitFromID,0x00496D30
gameStartHotkeyClear,0x004EEC30
CreateNewUnitSelectionsFromList,0x0049AE40
selectMultipleUnitsFromUnitList,0x0049AEF0
clearPlayerSelection,0x0049A740
addUnitToSelectionSlot,0x0049AF80
getActivePlayerNextSelection,0x0049A850
CMDACT_Select,0x004C0860
CMDRECV_Select,0x004C2750
