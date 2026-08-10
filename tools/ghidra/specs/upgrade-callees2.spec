# Second round of task-029 callees: the predicates and the money. Every address was read
# out of a decompile produced from tools/ghidra/specs/upgrade-callees.spec.
#
# label,addrHex
#
# From upgradeGate 0x0046DFC0 (which IS the card's upgrade-button condition, 0x00429450
# being a bare tail call to it):
#     if (FUN_004020b0())            -> reason 10
#     if (FUN_004ce7f0() <= FUN_004ce7a0()) -> reason 0x0E   (max level <= current level)
#     if (FUN_004281b0())            -> reason 0x0C          <- the one-at-a-time candidate
#     FUN_0046d610(id, player, &DAT_005145C0)                 the requirement VM
#   -> upgradeBusy    0x004281B0
#   -> upgradeMaxLvl  0x004CE7F0
#   -> upgradeCurLvl  0x004CE7A0
#   -> unitBusyOrLift 0x004020B0
#   -> requirementVM  0x0046D610
# From techGate 0x0046DE90, the same two shapes:
#   -> techBusy       0x00428240
#   -> techAvailable  0x004CE8A0   (task 026 already named this pair; re-listed so this
#   -> techResearched 0x004CE850    task's own evidence does not depend on that one)
#
# From startUpgrade 0x00454A80:
#   -> upgradeAfford  0x0042D190   sets the pending-cost globals 0x006CA51C/0x006CA4EC and
#                                  returns 0 when the player cannot pay -- the ONE place an
#                                  upgrade's money is decided
#   -> upgradeTime    0x00453F70   what goes into CUnit+0xC6
# From cancelUpgrade 0x00454280:
#   -> upgradeRefund  0x00454170   takes only the player id, so how it knows the cost is
#                                  the question this decompile answers

upgradeBusy,0x004281B0
techBusy,0x00428240
upgradeMaxLvl,0x004CE7F0
upgradeCurLvl,0x004CE7A0
techAvailable,0x004CE8A0
techResearched,0x004CE850
unitBusyOrLift,0x004020B0
requirementVM,0x0046D610
upgradeAfford,0x0042D190
upgradeTime,0x00453F70
upgradeRefund,0x00454170
