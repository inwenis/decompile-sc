# The one function task 030 detours, plus its callers. label,addrHex
#
# btnTrainCondition 0x00428E60 is the Train button's condition and the ONLY thing this
# task patches. What is wanted here is (a) its exact prologue, so ScHookInstall can
# refuse if memory disagrees, and (b) the register state at entry -- the decompile shows
# the unit arriving BOTH as a stack argument and in ESI (FUN_0046E1C0 reads it as
# unaff_ESI), the type in AX and the player in EDX, and a detour must not guess any of
# that.

btnTrainCondition,0x00428E60
requirementGate,0x0046E1C0
