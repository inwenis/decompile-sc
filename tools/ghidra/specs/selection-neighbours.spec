# Neighbours, gaps and one-past-the-end addresses around the selection arrays.
# Swept the same way as the arrays themselves so research/selection-cap.md §8 question 3 gets
# an evidence answer instead of an arithmetic one: an address with zero references anywhere in
# a 1.2 MB binary is unused space; an address with references is an occupied neighbour.
# Format: label,startHex,byteLength
#
# The disputed 4-byte gap: clientSelectionGroup ends at 0x00597238 and the nearest
# independently named datum is client_selection_changed at 0x0059723C. GPTP's
# `clientSelectionGroupEnd` (0x00597238) is its own 0x00597208 + 12*4 written out as a
# constant, so it proves nothing on its own -- but if the BINARY encodes 0x00597238 as an
# end-pointer in a loop bound, that changes the answer completely.
gap_0x00597238,00597238,4
clientSelectionChanged,0059723C,1
gap_0x0059723E,0059723E,10
primarySelected,00597248,4
# one-past-the-end of each array, swept for end-pointer comparisons
end_clientSelectionGroup2,0059727C,4
end_playersSelections,00628668,4
end_selectionHotkeys,00581960,4
# (one-past-the-end of activePlayerSelection IS 0x006284E8, the base of playersSelections --
# swept as playersSelections in selection-globals.spec, not duplicated here)
# other selection-subsystem globals named in selection-cap.md §2.2 / §3
recentSelectionTimes,0063FE40,128
selectCommandUser,0051267C,4
selectionSoundCooldown,0064087C,4
