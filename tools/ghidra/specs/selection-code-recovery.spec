# Instruction starts that Ghidra's auto-analysis left as UNDEFINED BYTES, fed back to
# DisassembleAt.java to recover them as code before the cross-reference sweep was believed.
#
# Why this file has to exist. The documented command sequence in
# research/binary-selection-map.md §1.2 is: run XrefSweep, disassemble from the addresses pass 2
# found in .text but pass 1 did not know about, re-run auto-analysis, run XrefSweep again. That
# middle step needs a seed list, and without the list committed the sequence does not reproduce
# in order -- a reviewer has to re-derive it before they can re-run anything. It is mechanical
# to re-derive and it should not have to be.
#
# Derivation, exactly:
#   1. from the FIRST XrefSweep pass-2 file (<out>.rawhits.tsv), take the rows with
#      coverage=UNCOVERED and block=.text -- 31 rows. These are little-endian dwords in
#      executable memory whose value is the address of a selection global, sitting in bytes
#      Ghidra never turned into instructions.
#   2. run RawHitDecode.java over them to get the START address of the instruction that encodes
#      each one (the hit address is the operand, so the opcode is 1-4 bytes earlier).
#   3. drop hits already inside a known function (0x004C26B6, in CMDRECV_ShiftSelect, is the one
#      such row -- it is the scaled-index write §1.1 is about) and collapse hits that share an
#      instruction or a contiguous run. 31 rows -> the 24 seeds below.
#
# Disassembling from these and re-running auto-analysis took the function count 5008 -> 5082 and
# the clientSelectionGroup instruction count 85 -> 119.
#
# Format: label,addrHex
s1,00424384
s2,004282E0
s3,00428310
s4,00428372
s5,004283C0
s6,004285E0
s7,00428610
s8,00428640
s9,00428670
s10,004286A0
s11,004286E0
s12,00428860
s13,00428D40
s14,00428DA0
s15,00428EA1
s16,00428ED1
s17,00428FF2
s18,0048DCD0
s19,004965A8
s20,0049A328
s21,0049A8B0
s22,004BF8A2
s23,004BFA40
s24,004E627D
