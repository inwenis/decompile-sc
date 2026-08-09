# Production module, task 025 -- round 3.
#
# label,addrHex
#
# Rows 1-13 are FUNCTION ENTRY POINTS reported by tools/ghidra/scripts/FieldSweep.java
# for displacement 0x98 and 0xA4 against THIS binary (work/scratch/025/field-98.tsv,
# field-A4.tsv). They are the functions that touch the build queue and its head index;
# nothing about them is inherited or guessed.
#
# Rows 14-19 are the EMITTER addresses in the committed table
# research/data/command-ids.tsv (task 011/015, built by
# tools/ghidra/build-command-table.ps1 from this binary) for the five production
# opcodes -- the client side, which is where a "queue is full" refusal would live.

queueAdvanceHead,0x00466790
queueSlotHelper,0x004669E0
queueRead,0x00466B70
queueClear,0x00466E80
queueMisc467030,0x00467030
queueMisc467FD0,0x00467FD0
buildComplete,0x00468420
queueTouch45D2E0,0x0045D2E0
queueTouch45D410,0x0045D410
queueTouch45DEA0,0x0045DEA0
queueTouch49F170,0x0049F170
queueTouch4E4D00,0x004E4D00
queueTouch45CD00,0x0045CD00

emitTrainUi,0x004234B0
emitTrainCmdact,0x004C01C0
emitCancelTrainUi,0x00423490
emitCancelTrainCmdact,0x004C01A0
emitCancelUi,0x00423430
emitUnitMorphUi,0x00423790
