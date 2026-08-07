# Address windows for research/selection-cap.md §8 question 3 -- what actually occupies the
# space around each selection array. Each window deliberately starts BEFORE the array of
# interest and runs past its end, so "is there slack behind this array" is answered by looking
# at bytes rather than by adding 12*4 to a quoted base.
# Format: label,startHex,byteLength
#
# 0x00597200..0x0059729F: clientSelectionGroup (0x00597208+48 -> ends 0x00597238), the disputed
# 4-byte gap at 0x00597238, client_selection_changed (0x0059723C), clientSelectionCount
# (0x0059723D), primary_selected (0x00597248), clientSelectionGroup2 (0x0059724C+48 -> ends
# 0x0059727C) and the bytes after it.
clientSelGroupWindow,00597200,160
# 0x0057FE20..0x0057FE7F: what precedes selection_hotkeys (0x0057FE60).
hotkeysBefore,0057FE20,64
# 0x00581920..0x0058199F: selection_hotkeys ends at 0x00581960 (8*18*12*4 = 6912). What follows.
hotkeysAfter,00581920,128
# 0x00628480..0x006284FF: what precedes selection_iterator (0x006284B6) and
# activePlayerSelection (0x006284B8), and the start of playersSelections (0x006284E8).
activePlayerSelWindow,00628480,128
# 0x00628620..0x0062869F: playersSelections ends at 0x00628668 (8*12*4 = 384). What follows.
playersSelectionsAfter,00628620,128
# 0x0063FE20..0x0063FE9F: recent_selection_times (0x0063FE40, u16[8][8] = 128 bytes) and its
# neighbourhood -- it indexes the hotkey groups 10..17 ring, so it moves with them.
recentSelectionTimes,0063FE20,128
