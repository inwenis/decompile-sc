# The seven selection globals named in research/selection-cap.md §8 question 1.
# Format: label,startHex,byteLength
#
# Lengths are the SPAN each source claims for the datum, so the sweep covers interior element
# addresses too -- an instruction touching playersSelections[3][7] references 0x00628634, not
# the base, and a base-address-only sweep would miss nearly all of the relocation work.
#
# selectionIterator is swept as 2 bytes, not 1: teippi types 0x006284B6 as u8 and
# activePlayerSelection begins at 0x006284B8, so 0x006284B7 is unclaimed by any source and
# worth sweeping alongside it.
clientSelectionGroup,00597208,48
clientSelectionCount,0059723D,1
clientSelectionGroup2,0059724C,48
selectionIterator,006284B6,2
activePlayerSelection,006284B8,48
playersSelections,006284E8,384
selectionHotkeys,0057FE60,6912
