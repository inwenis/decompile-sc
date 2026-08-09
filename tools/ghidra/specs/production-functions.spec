# Production-queue code, task 025.
#
# label,addrHex
#
# Every address below is a handler entry point already EVIDENCED in this repo --
# research/data/command-opcodes.tsv (task 015's committed 58-row dispatcher table),
# whose `handler` column was read out of this binary's own command dispatcher -- or a
# callee named in that table's `resourceFns` column. Nothing here is inherited from
# public prior art.
#
# Provenance, one line each:
#   cmdrecvTrain          command-opcodes.tsv row 0x1F: handler 0x004C1C20, SINGLE,
#                         resourceFns FUN_00467250. The 3-byte command carrying a unit
#                         type id that spends minerals+gas -- quoted in full in
#                         research/command-opcodes.md 5.1.
#   cmdrecvCancelTrain    row 0x20: handler 0x004C0100, SINGLE. command-opcodes.md 3.4
#                         records that it reaches the refund 0x00468280 through
#                         0x00466A70 -- an INDIRECT resource path, hence not in the tsv
#                         column.
#   cmdrecvUnitMorph      row 0x23: handler 0x004C1990, LOOP, spends via 0x00467250.
#   cmdrecvTrainFighter   row 0x27: handler 0x004C1800, LOOP, spends via 0x00467250.
#   cmdrecvCancel         row 0x18: handler 0x004C2EF0, SINGLE, refunds via 0x00468280.
#   cmdrecvCancelHatch    row 0x19: handler 0x004C2EC0, LOOP, refunds via 0x00468280.
#   cmdrecvBuildingMorph  row 0x35: handler 0x004C1910, SINGLE, spends via 0x00467250.
#   spendResources        the spend itself, command-opcodes.md 3.3 quotes its two
#                         per-player resource arrays (0x0057F0F0 / 0x0057F120).
#   refundResources       the cancel/refund path, same section (via 0x0042CEC0/0x0042CE70).
#   cancelIndirect        0x00466A70 -- the hop command-opcodes.md 3.4 names between the
#                         0x20 handler and the refund.
#   trainCallee           0x004743D0 -- the function the 0x1F handler calls once the spend
#                         succeeds, quoted in the decompile in command-opcodes.md 5.1.
#                         Unread by any prior task; this is the enqueue candidate.

cmdrecvTrain,0x004C1C20
cmdrecvCancelTrain,0x004C0100
cmdrecvUnitMorph,0x004C1990
cmdrecvTrainFighter,0x004C1800
cmdrecvCancel,0x004C2EF0
cmdrecvCancelHatch,0x004C2EC0
cmdrecvBuildingMorph,0x004C1910
spendResources,0x00467250
refundResources,0x00468280
cancelIndirect,0x00466A70
trainCallee,0x004743D0
