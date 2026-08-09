# Every function this task found touching the 5-slot build queue, task 025.
#
# label,addrHex
#
# ImmediateSweep over this spec produces (a) the constant table -- where 5, 4, 0xE4 and
# 0x6A are baked in and in what OPERAND ROLE -- and (b) a companion instruction-stream
# dump per function, which is what the calling conventions below are read from.
#
# Provenance of each address: FieldSweep displacement 0x98 / 0xA4 over this binary
# (work/scratch/025/field-98.tsv, field-A4.tsv), the committed dispatcher table
# research/data/command-opcodes.tsv, or a CALL/DATA reference read out of one of those
# functions. Nothing inherited.

addToBuildQueue,0x00467250
findFreeBuildQueueSlot,0x004669B0
cancelBuildQueueSlot,0x00466A70
cancelLastQueued,0x00466E40
clearBuildQueue,0x00466E80
countTypeInQueue,0x00466B70
productionTick,0x00468420
interceptorTick,0x00466790
cancelCurrent,0x00468280
setPendingCost,0x0042D140
refundByType,0x0042CEC0
cmdrecvTrain,0x004C1C20
cmdrecvCancelTrain,0x004C0100
btnCancelTrainCondition,0x00428530
queueSlotHelper,0x004669E0
