# Control-group storage ranges, task 021.
# Format: label,startHex,byteLength
#
# selectionHotkeys is swept in FULL (6912 bytes = [8][18][12] x 4B) so interior element
# addresses are covered, not just the base -- research/binary-selection-map.md 1.1 shows why a
# base-only sweep misses nearly all of an array's sites, and 2.3 note 4 names a real mid-array
# constant (0x005801C4 = &hotkeys[1][0][1]).
#
# recentSelectionTimes is u16[8][8] at 0x0063FE40 (binary-selection-map.md 5.2, from the
# `MOV word ptr [EAX*0x2 + 0x63fe40],CX` at 0x004C2854): 8 players x 8 recent slots x 2 bytes
# = 128 bytes. It is here because the recent-selection ring shares the hotkey array's groups
# 10..17, so anything that widens a group has to know whether it widens those too.
#
# lastHotkeyTapTime / lastHotkeyGroupId are the 500 ms double-tap-to-centre pair identified in
# binary-selection-map.md 3.2. They are swept because they sit immediately behind
# clientSelectionGroup2 and a recall path writes them.
selectionHotkeys,0057FE60,6912
recentSelectionTimes,0063FE40,128
lastHotkeyTapTime,0059727C,4
lastHotkeyGroupId,00597280,4
