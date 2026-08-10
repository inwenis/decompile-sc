# The functions that ADVANCE and END a research/upgrade, task 029.
#
# label,addrHex
#
# Every address is a row of this task's own FieldSweep over the four fields
# startUpgrade/startTech write (work/scratch/029/field-{C9,C8,C6,CD}.tsv):
#
#   CUnit+0xC6  u16  research/upgrade time remaining   (15 rows)
#   CUnit+0xC8  u8   tech being researched, 44 = none  (100 rows, filtered)
#   CUnit+0xC9  u8   upgrade being researched, 61 = none (47 rows)
#   CUnit+0xCD  u8   the LEVEL being upgraded to        (9 rows)
#
# upgradeFinish 0x004546A0 is the one function that reads all four and writes
#   `0xC9 = 0x3D` and `0xCD = 0` -- i.e. the completion. techFinish 0x00454220 is its
#   twin on the 0xC8 side. countdown 0x004548B0 and buildingUpdate 0x00469240 are the two
#   read-modify-write sites on the time field. unitRemoved 0x0049FD00 is the death path,
#   which compares 0xC9 against its sentinel (the same shape production-queue.md 4.4
#   documents for the build queue).
#
# techZeroTime 0x00453DD0 writes only the time field and is included so the pair is
# complete rather than assumed.

upgradeFinish,0x004546A0
techFinish,0x00454220
countdown,0x004548B0
buildingUpdate,0x00469240
techZeroTime,0x00453DD0
unitRemoved,0x0049FD00
liftOffHandler,0x004C1620
