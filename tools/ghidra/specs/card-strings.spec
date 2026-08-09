# Task 026: the command-card ("statcmd") module's own .rdata strings, swept to find the
# code that loads the card dialog and its icon art -- the same route task 017 used to
# find the status-screen module from `rez\statdata.bin`.
#
# Every VA below was read out of THIS binary by work/scratch/card/scan-strings.ps1:
# an ASCII-run scan of the file image with each hit's file offset converted through the
# PE section table parsed from the same file (imageBase 0x00400000, .rdata raw 0x0FE000
# -> VA 0x004FE000).
#
# Format: label,startHex,byteLength
#
# "rez\statbtn%c.bin" -- the command-card dialog asset; %c is the race letter, so the
# card is a PER-RACE .bin sibling of rez\statdata.bin (the status area, hud-selection-row.md 3).
statBtnBinFmt,005049F8,18
# "unit\cmdbtns\cmdicons.grp" -- the command-card ICON art.
cmdIconsGrp,00504A24,26
# "%s%ccmdbtns.grp" and "unit\cmdbtns\" -- the icon path builder.
cmdBtnsGrpFmt,00504A40,16
cmdBtnsDir,00504A50,14
# "unit\cmdbtns\ticon.pcx" -- the card's tooltip/icon palette.
tIconPcx,00504A0C,23
# "Starcraft\SWAR\lang\statcmd.cpp" -- the module's own debug string. Every function
# that passes it to the allocator IS command-card code, which is the cheapest way to
# enumerate the module.
statCmdCpp,00504A6C,32
