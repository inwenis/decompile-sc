# Task 017: instruction starts auto-analysis left undefined in the status-screen module.
# Found by the hud-fnrefs sweep: 0x0045841C (MOV [ESI+0x2E],0x456F50 -- the per-button
# update-handler binding) and 0x00458450 (CALL 0x00458220) carry no containing function.
# DisassembleAt walks back over 0xCC filler to the entry and re-runs auto-analysis.
#
# label,addrHex
h1,0045841C
h2,00458450
