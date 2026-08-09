# Task 026: the code that FILLS the per-player tech state at map load, and the two
# helpers that read it back. Found by sweeping specs/tech-state.spec: 0x004CB670 is the
# only function that writes all four arrays, and 0x004CCC80 is the STOSD.REP that clears
# them.
#
# This is the user's observation ("the ghosts didn't have the cloak ability unlocked")
# turned into a question the binary can answer: what does a CHK section have to contain
# for techResearched[player][10] to come out 1?
#
# label,addrHex
techApplyFromChk,0x004CB670
techApply2,0x004CB7D0
techReset,0x004CCC80
techIsResearched,0x004CE850
techIsAvailable,0x004CE8A0
