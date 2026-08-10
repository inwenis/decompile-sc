# Upgrade / research code, task 029.
#
# label,addrHex
#
# Two provenances, both from inside this repo -- nothing inherited from public prior art:
#
# (a) research/data/command-opcodes.tsv (task 015's committed dispatcher table, read out
#     of this binary's own command dispatcher) and research/data/command-ids.tsv (task
#     011's emitter table, read out of the length table + emit sites):
#
#       0x30 Tech            len 2  handler 0x004C1BA0  emitters 0x00423350, 0x004C00E0
#       0x31 Cancel Tech     len 1  handler 0x004C0070  emitters 0x00423330, 0x004C00C0
#       0x32 Upgrade         len 2  handler 0x004C1B20  emitters 0x00423310, 0x004C0050
#       0x33 Cancel Upgrade  len 1  handler 0x004BFFC0  emitters 0x004232F0, 0x004C0030
#
#     All four are SINGLE-gated (the dispatcher's own selection shape), which is why the
#     handlers below are expected to resolve the acting building through the active
#     player's selection rather than from the command payload.
#
# (b) The LIVE COMMAND CARD of an Engineering Bay, read out of the running process by
#     tools/plugin/probe-upgrade-wire.ps1 (-CardScan 1, task 026's reader). Every
#     condition/action address below is the `cond=`/`act=` field of a real Button record
#     the engine had assigned to a real card slot, in a real game, with the state named:
#
#       idle bay, buttonset 122, shown=3:
#         slot 1  enabled  cond=0x00429450 act=0x00423310 cparam=7 aparam=7   (upgrade 7)
#         slot 2  enabled  cond=0x00429450 act=0x00423310 cparam=0 aparam=0   (upgrade 0)
#         slot 9  enabled  cond=0x004287D0 act=0x00423230 (0x2F Lift Off)
#       same bay while upgrade 7 runs, same buttonset 122, shown=1:
#         slots 1..8 HIDDEN
#         slot 9  enabled  cond=0x00428900 act=0x004232F0 (0x33 Cancel Upgrade)
#
#     So 0x00429450 is the condition that stops offering an upgrade while one is running,
#     and 0x00428900 is its complement. Those two are the client half of "one at a time".

cmdrecvUpgrade,0x004C1B20
cmdrecvTech,0x004C1BA0
cmdrecvCancelUpgrade,0x004BFFC0
cmdrecvCancelTech,0x004C0070
btnUpgradeCondition,0x00429450
btnCancelUpgradeCondition,0x00428900
btnLiftOffCondition,0x004287D0
emitUpgrade,0x00423310
emitTech,0x00423350
emitCancelUpgrade,0x004232F0
emitCancelTech,0x00423330
