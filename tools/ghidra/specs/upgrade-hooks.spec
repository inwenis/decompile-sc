# The detour targets for task 029's upgrade queue, and the callers of each.
#
# label,addrHex
#
# HookProbe emits, per address: the whole containing function as `addr rawbytes text` with a
# PC-relative flag per instruction, a TSV row carrying the calling convention and the
# cumulative byte length of the first instructions reaching >= 5 (the detour patch size), and
# a .callers file. The patch bytes sc_upgrades.cpp hands to ScHookInstall come from here and
# nowhere else -- ScHookInstall then refuses to patch if the running process disagrees.
#
# Provenance of every address is research/upgrade-queue.md 4-6:
#   upgradeGate/techGate       the predicate `cmdrecvUpgrade`/`cmdrecvTech` run AND the body
#                              of the card's own upgrade-button condition
#   btnUpgradeCondition        0x00429450, a bare tail call to upgradeGate; read live off an
#                              Engineering Bay's card by probe-upgrade-wire.ps1
#   cmdrecvUpgrade/cmdrecvTech the 0x32 / 0x30 receive handlers, command-opcodes.tsv
#   upgradeTick/techTick       the order handlers that count CUnit+0xC6 down and clear
#                              CUnit+0xC9 / +0xC8 on completion (FieldSweep)
#
# techGate's .callers file is also how the TECH button's condition wrapper is found -- the
# twin of btnUpgradeCondition, which no card this task has read yet has shown.

upgradeGate,0x0046DFC0
techGate,0x0046DE90
btnUpgradeCondition,0x00429450
cmdrecvUpgrade,0x004C1B20
cmdrecvTech,0x004C1BA0
upgradeTick,0x004546A0
techTick,0x004548B0
cmdrecvCancelUpgrade,0x004BFFC0
cmdrecvCancelTech,0x004C0070
