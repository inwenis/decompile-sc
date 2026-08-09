# Task 026: the command-card button's INTERACT handler is code auto-analysis left
# undefined -- exactly the case task 017 hit at 0x0045841C. The card-fnrefs sweep found
# `CALL 0x004596a0` (the card button's CREATE case) at 0x004598B0 with NO containing
# function, so the handler around it has to be recovered before it can be decompiled.
# DisassembleAt walks back over 0xCC filler to the entry and re-runs auto-analysis.
#
# label,addrHex
c1,004598B0
