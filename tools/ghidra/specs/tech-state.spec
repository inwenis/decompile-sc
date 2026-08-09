# Task 026: the per-player TECH STATE arrays -- the memory the command card's ability
# buttons are gated on, and therefore the memory that decides whether the user's
# observation ("the ghosts didn't have the cloak ability unlocked") is a fixture bug.
#
# Found by decompiling the two predicates the tech gate 0x0046DD80 runs:
#   * availability -- 0x004CE8A0: `techId < 0x18 ? *(u8*)(0x0058CE24 + player*0x18 + techId)
#                                                : *(u8*)(0x0058F038 + player*0x14 + techId)`
#     A button whose tech is UNAVAILABLE is HIDDEN (the gate returns 0, reason 2).
#   * researched -- requirement opcode 0xFF0F inside 0x0046D610, the same shape against
#     0x0058CF44 / 0x0058F128. A researched test that fails leaves the requirement count
#     at zero, which is the interpreter's `reason = 8; return -1` exit -- i.e. GREYED.
#
# The two pairs are adjacent by exactly their own size, which is what makes the reading
# self-checking rather than asserted: 0x0058CF44 - 0x0058CE24 = 0x120 = 12 players x 24
# techs, and 0x0058F128 - 0x0058F038 = 0xF0 = 12 players x 20 techs (Brood War's 44 - 24).
#
# Format: label,startHex,byteLength
techAvailable,0058CE24,288
techResearched,0058CF44,288
techAvailableBW,0058F038,240
techResearchedBW,0058F128,240
