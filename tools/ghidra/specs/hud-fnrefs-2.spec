# Task 017 round 4: find who binds the wireframe-button interact handler 0x004583E0
# (discovered in work/scratch/hud/binder-listing.tsv) and the surrounding dispatch plumbing.
#
# Format: label,startHex,byteLength
wireframeInteractFn,004583E0,1
mouseOverHelperFn,00457DE0,1
# per-control-type default interact table (JMP [type*4 + 0x5014AC] at 0x00458494)
defaultInteractTable,005014AC,60
# frame driver that calls updateSelectedUnitData then statDataUpdate
hudFrameDriverFn,004D93F0,1
# console-init caller of statusDialogInit
consoleInitFn,004C3BB0,1
