# Task 017 round 2: the status-screen dialog's creation and dispatch, found from the
# round-1 xref sweep (writers of the status dialog pointer 0x0068C1F0) and GPTP
# stats_display_main.cpp (dispatcher 0x00458120, per-unit-type table 0x005193A0).
#
# label,addrHex
#
# writes 0x0068C1F0 at 0x004586B4 -- status-screen dialog INIT candidate
statusDialogInit,0x00458570
# writes 0x0068C1F0 at 0x00456F0A -- immediately precedes wireframeSelectUpdate 0x00456F50
statusDialogSetter,0x00456EF0
# GPTP function_00458120: the per-frame stat display dispatcher (cond/act, single vs multi)
statDataUpdate,0x00458120
# touches 0x0068C1E0 (round-1 sweep); neighbour of the dispatcher
statUnknown58CF0,0x00458CF0
# GPTP function_004568B0: portrait/single-unit dialog helper
statSingleHelper,0x004568B0
# GPTP function_00457FE0: mouse-over update helper
statMouseHelper,0x00457FE0
