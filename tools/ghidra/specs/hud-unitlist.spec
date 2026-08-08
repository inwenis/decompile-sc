# Task 017 round 3: evidence the player unit list, so the HUD click gate can verify
# a clicked overflow unit is still in play (not freed/removed/transferred). The
# unit-(re)init 0x004A0320 links the unit into playerUnitList[player] (0x006283F8,
# selection-circles.md 4.5) -- decompile it to read the list-head base and the
# CUnit link-pointer offsets.
#
# label,addrHex
unitInitLink,0x004A0320
# the removal path, to confirm what it does to the list links (unlink)
unitRemove,0x004A0740
