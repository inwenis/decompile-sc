# Task 033 -- the three routines the static-text draw 0x004EF870 calls, in the order it
# calls them. Addresses are CALL targets read off the listing of 0x004EF870 itself
# (work/scratch/033/listing-textblit.tsv), not inherited.
#
# label,addrHex
#
# setFont      0x0041FB30 -- called twice: once with ECX = the font handle chosen from the
#              control's flag bits (flags & 0x4C00 -> one of the four handles at
#              0x006CE0F4/F8/FC/0x006CE100), and once with ECX = 0 at the tail to restore.
# setTextStyle 0x0041F610 -- called with EAX = a small style index (2 normal, 5 disabled,
#              3/4/6 for the static types) picked from the control's flags and type.
# drawString   0x004202B0 -- the blit itself: EAX = the string (control+0x14, +1 when the
#              flags carry the shortcut-prefix bits), ESI/stack = the pixel position
#              computed from the control's bounds.
setFont,0x0041FB30
setTextStyle,0x0041F610
drawString,0x004202B0
