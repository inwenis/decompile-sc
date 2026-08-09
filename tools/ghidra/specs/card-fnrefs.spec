# Task 026: sweep command-card FUNCTION-ENTRY addresses as data, to find the instructions
# that STORE or CALL them -- i.e. which handler binds the card buttons and where the card's
# per-index interact table lives. Same technique as specs/hud-fnrefs.spec (task 017).
#
# Format: label,startHex,byteLength
#
# the card button's CREATE case: it writes fxnUpdate = 0x00458730 into the control
# (decompiled at work/scratch/card/decomp1/cardFn2.FUN_004596a0.c). Whoever CALLS it is
# the card button's interact handler.
cardBtnCreateFn,004596A0,1
# the card button's fxnUpdate (the icon/progress-bar draw).
cardBtnUpdateFn,00458730,1
# the card layout function -- its callers pin the per-frame path.
cardLayoutFn,004591D0,1
# the card dialog's init and teardown.
cardInitFn,00459B90,1
cardTeardownFn,00458CF0,1
# the tech gate every ability CONDITION funnels through (0x004294E0 is nothing but a
# tail-call to it). Its callers enumerate the tech-gated abilities.
techGateFn,0046DD80,1
# the command sender the card ACTIONS call (0x00423270 passes 0x22, 0x004234D0 passes 0x36).
queueCmdFn,00485BD0,1
