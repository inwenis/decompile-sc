# Task 021 detour/caller probe for the control-group path.
#
# label,addrHex
#
# HookProbe emits, per address: the prologue bytes and the detour patch window (so a 5-byte
# splice can relocate whole instructions), plus a .callers file. The callers are the point of
# half these rows:
#
#   CMDACT_HotkeyUnit  -- its ONE caller is the client-side key handler, which is where the
#                         Ctrl/Shift modifier is read. That decides whether an unattended test
#                         can drive Ctrl+1 with POSTED messages at all (drive-game.ps1's KNOWN
#                         LIMIT: Windows does not update the key-state table for posted keys).
#   CreateNewUnitSelectionsFromList
#                      -- sc_addresses.h claims its 10 callers cover "control-group recall".
#                         The recall decompiled here (0x00496940) writes playersSelections
#                         directly and calls no such funnel, so the claim needs checking
#                         against the actual caller list rather than restating.
#   hotkeyRecall / hotkeySaveOrAdd / CMDRECV_Hotkey
#                      -- candidate detour targets for the plugin-side shadow groups.
#
# The three helpers at the bottom are called BY the recall and are unread by any prior task.
CMDACT_HotkeyUnit,0x004C07B0
CMDRECV_Hotkey,0x004C2870
hotkeyRecall,0x00496940
hotkeySaveOrAdd,0x004965D0
CreateNewUnitSelectionsFromList,0x0049AE40
clearPlayerSelection,0x0049A740
updateSelectedUnitData,0x004C38B0
isActivePlayerView,0x0049A110
recallSelectGraphics,0x00499A10
hotkeyDoubleTapCentre,0x004967E0
