# Task 017 round 5: the 12-entry interact-pointer table at 0x00504B70 (all entries
# 0x004583E0, one per wireframe button) is .rdata; find the code that consumes it, and
# whatever surrounds it (the table likely covers every control of rez\statdata.bin,
# so sweep a window before and after).
#
# Format: label,startHex,byteLength
statdataInteractTable,00504A40,400
