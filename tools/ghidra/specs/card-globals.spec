# Task 026: the command-card module's globals, swept to enumerate every function that
# touches the card -- in particular the HOTKEY path (task 022/023 found no letter A-Z
# reaches the ability row, and the key handler has to be found before that can be
# explained rather than restated).
#
# Format: label,startHex,byteLength
#
# The statcmd global cluster. 0x0068C148 is the card dialog pointer (written by the init
# 0x00459B90, cleared by the teardown 0x00458CF0); 0x0068C14C is the CURRENT CARD ID that
# indexes the buttonset table; 0x0068C1B4 is the control under the cursor; the rest are
# the module's caches. Swept as one range for the same reason task 017 swept
# 0x0068C1E0+0x50: anything touching one of them is command-card code.
cardState,0068C140,72
# the buttonset table itself: 250 entries x 12 bytes {u16 count, pad, Button* buttons,
# u32 unused}. Ends at 0x005193A0, which is exactly where the per-unit-type status
# cond/act table hud-selection-row.md 4.2 already named begins -- so the length is read
# off the binary, not assumed.
buttonSetTable,005187E8,3000
# the reason code every ability condition writes before returning 0 (set by the tech gate
# 0x0046DD80 and consumed by the layout function 0x004591D0, which overwrites the
# button's disabled-reason string when it is 0x15).
cardRefuseReason,0066FF60,4
# techdata: the per-tech energy cost table the cloak send-gate 0x00423540 reads
# (cost = *(u8*)(0x00656380 + techId*2), compared as cost<<8 against CUnit+0xA2), and the
# per-tech byte the tech gate 0x0046DD80 requires non-zero at 0x006562F8.
techEnergyCost,00656380,88
techAvailByte,006562F8,44
