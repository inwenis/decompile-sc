# Task 026, round 2: the two functions the per-frame card update 0x004599A0 calls to
# REBUILD the card, plus the helpers around them. Found by decompiling 0x004599A0
# (work/scratch/card/decomp1/cardUpdate.FUN_004599a0.c): LAB_00459A12 calls
# FUN_004591d0 then FUN_00459770, and both branches call FUN_00458d50.
#
# label,addrHex
cardBuildA,0x004591D0
cardBuildB,0x00459770
cardHelperD50,0x00458D50
cardFn3,0x00458CF0
cardFn2,0x004596A0
# 0x00427A80 -- called on the replay/observer path (DAT_006d0f14 != 0).
cardReplayExtra,0x00427A80
