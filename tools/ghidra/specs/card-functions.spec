# Task 026: the command-card ("statcmd") module, round 1.
#
# Every address here was found BY THIS BINARY, not inherited: the statcmd.cpp /
# rez\statbtn%c.bin / unit\cmdbtns\cmdicons.grp strings were located by an ASCII scan of
# the file image (work/scratch/card/scan-strings.ps1) and swept for references
# (specs/card-strings.spec -> research/data/card-strings.tsv). These are the three
# functions that reference them, plus the per-frame entry hud-selection-row.md 4.1
# already names as the button-panel counterpart.
#
# label,addrHex
#
# loads rez\statbtn%c.bin, unit\cmdbtns\cmdicons.grp and unit\cmdbtns\ticon.pcx --
# the command-card dialog's init (sibling of the statdata init 0x00458570).
cardInit,0x00459B90
# passes "statcmd.cpp" to the allocator twice; second statcmd function.
cardFn2,0x004596A0
# passes "statcmd.cpp" twice; third statcmd function.
cardFn3,0x00458CF0
# the per-frame button-panel update the HUD driver 0x004D93F0 calls right before the
# status-area dispatcher (hud-selection-row.md 4.1).
cardUpdate,0x004599A0
# the "dirty" helper both modules tail into (hud-fnrefs.tsv: called from 0x004599C7).
statDirtyHelper,0x00458DE0
