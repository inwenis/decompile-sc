# Production-queue callees, task 025 -- round 2.
#
# label,addrHex
#
# Every address here is a CALL TARGET read out of a function already decompiled in
# round 1 (work/scratch/025/*.c, spec production-functions.spec). None is inherited.
#
#   findFreeBuildQueueSlot  0x004669B0 -- the first call in FUN_00467250 (the enqueue);
#                           its result is compared `!= 5` and then used to index
#                           CUnit+0x98. THE cap site candidate.
#   canAffordAndReserve     0x0042D140 -- FUN_00467250's second call, gating the write.
#   refundQueued            0x0042CEC0 -- the refund FUN_00466A70 calls for a queued
#                           (not yet started) item, and FUN_00468280 for a normal cancel.
#   refundQueuedAlt         0x0042CE70 -- FUN_00468280's other refund branch
#                           (CUnit+0xDC bit 1 set).
#   cancelAllQueue          0x00466E40 -- what the 0x20 handler calls when the command's
#                           u16 argument is 0xFE.
#   cancelTail              0x004C36C0 -- called by the 0x20 handler after the cancel.
#   buildQueueUiRefresh     0x00466CB0 -- placeholder: see note below.
#
# 0x00466CB0 is NOT from a round-1 decompile; it is the next function entry after
# 0x00466A70 in the address order the listing shows, seeded so FuncProbe/DecompileMany
# can say what it is. If it turns out unrelated it is dropped rather than written up.

findFreeBuildQueueSlot,0x004669B0
canAffordAndReserve,0x0042D140
refundQueued,0x0042CEC0
refundQueuedAlt,0x0042CE70
cancelAllQueue,0x00466E40
cancelTail,0x004C36C0
