# Task 026: two more blocks auto-analysis left undefined in the command-card module,
# both found by disassembling around known code rather than guessed:
#   0x004598D0 -- the card BUTTON's interact handler (its jump table at 0x00459978 and
#                 index bytes at 0x0045998C decode cleanly; 0x004598B0 inside the sibling
#                 dialog-root handler calls the CREATE case 0x004596A0).
#   0x004588C0 -- the predicate the card HOTKEY handler 0x00458B30 loads into EBX before
#                 calling the child-walk 0x00417EB0. Whether it skips DISABLED controls is
#                 the whole question for "no letter A-Z reaches the ability row".
#
# label,addrHex
c1,004598D0
c2,00459890
c3,004588C0
c4,00458BB0
