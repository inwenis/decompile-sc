# Task 017 stage B hook target for the HUD selection-row paging module.
#
# label,addrHex
#
# The per-frame status-area dispatcher (research/hud-selection-row.md 4.2): the SINGLE
# entry the HUD driver 0x004D93F0 calls each frame. It branches portrait-null /
# single-unit / multi-select; detouring it (rather than the multi-select act/cond pair
# 0x00425960/0x00424660) is what lets the module restore stock even when a shadow
# click drops the selection to exactly one unit and the engine takes its single branch.
# No arguments, returns void, one caller (0x004D940F).
statDataUpdate,0x00458120
#
# --- engine primitives the module CALLS through pointers (never hooked) ------------------------
showControl,0x004186A0
hideControl,0x00418700
updateControl,0x0041C400
# the engine's own button interact -- our per-button wrapper tail-jumps here
wireframeButtonInteract,0x004583E0
