# Build-menu button condition/action functions, task 025 -- round 4.
#
# label,addrHex
#
# Where these came from: XrefSweep (work/scratch/025/prod-xrefs.tsv) found the Train
# emitter 0x004234B0 referenced ONLY as DATA, from 0x0051730C and 0x00517320. Dumping
# 0x005172C0..0x00517360 out of the working-copy binary (work/scratch/025/peek.py)
# shows a 0x14-byte record array whose +0x04 field is a function pointer and whose
# +0x08 field is the emitter -- i.e. the button table, condition at +4, action at +8.
# The three Train records at 0x005172F0 / 0x00517304 / 0x00517318 all carry condition
# 0x00428E60, and the Cancel-Train record at 0x00517340 carries condition 0x00428530
# with action 0x00423490 (the 0x20 emitter). Both conditions are read out of the
# binary here rather than assumed.
#
# 0x00425600 / 0x004268D0 / 0x00426FF0 / 0x00428530 additionally appear in the
# displacement-0x98 sweep (field-98.tsv), which is what makes them build-queue readers
# rather than arbitrary neighbours.

btnTrainCondition,0x00428E60
btnCancelTrainCondition,0x00428530
btnCond4294E0,0x004294E0
btnCond429520,0x00429520
queueUi425600,0x00425600
queueUi4268D0,0x004268D0
queueUi426FF0,0x00426FF0
