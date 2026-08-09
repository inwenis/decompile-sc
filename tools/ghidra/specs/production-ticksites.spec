# Who calls the production tick, task 025.
#
# label,startHex,byteLength  (XrefSweep takes RANGES)
#
# 0x00468420 is the function FieldSweep found writing BOTH CUnit+0x98 and CUnit+0xA4
# (field-98.tsv 0x004685A0/0x004685CE/0x00468501, field-A4.tsv 0x0046851E) -- i.e. the
# code that finishes a queued item and advances the head. This asks what drives it, so
# a plugin that wants a game-thread moment "a slot just freed" knows what it is hooking.
#
# 0x00468200 is the unit-creation call inside it (`FUN_00468200(state == 0)` in the
# round-3 decompile) and 0x004743D0 the secondary-order setter it calls when the queue
# runs dry; both are listed so their other callers are visible too.

productionTick,0x00468420,1
interceptorTick,0x00466790,1
createQueuedUnit,0x00468200,1
setSecondaryOrder,0x004743D0,1
statDataUpdate,0x00458120,1
