# The callees the four upgrade/research handlers and their button conditions reach,
# task 029. Every address here was read out of a decompile of a function in
# tools/ghidra/specs/upgrade-functions.spec -- nothing guessed, nothing inherited.
#
# label,addrHex
#
# From cmdrecvUpgrade (0x004C1B20):
#     DAT_006284b6 = 0; u = FUN_0049a850();
#     if (u && FUN_0049a850()==0 && FUN_0046dfc0(u)==1 && FUN_00454a80()) { FUN_00475310(); ... }
#   -> selNext        0x0049A850  the active player's selection iterator ("exactly one")
#   -> upgradeGate    0x0046DFC0  the predicate; ALSO the whole body of the card's own
#                                 upgrade-button condition 0x00429450, which is a tail
#                                 call to it. One function, both halves of "one at a time".
#   -> startUpgrade   0x00454A80  the act; returns non-zero on success
#   -> afterAccept    0x00475310  the common tail both handlers run once accepted
#
# From cmdrecvTech (0x004C1BA0), same shape:
#   -> techGate       0x0046DE90
#   -> startTech      0x00454B70
#
# From cmdrecvCancelUpgrade (0x004BFFC0):  FUN_00454280 -- and note the handler checks
#   only flags(+0xDC)&1 and owner(+0x4C)==activePlayer, NOT that an upgrade is running,
#   so whatever guard exists must be inside the callee.
#   -> cancelUpgrade  0x00454280
# From cmdrecvCancelTech (0x004C0070):
#   -> cancelTech     0x00453E30
#   -> cancelTechTail 0x004C36C0

selNext,0x0049A850
upgradeGate,0x0046DFC0
techGate,0x0046DE90
startUpgrade,0x00454A80
startTech,0x00454B70
cancelUpgrade,0x00454280
cancelTech,0x00453E30
cancelTechTail,0x004C36C0
afterAccept,0x00475310
