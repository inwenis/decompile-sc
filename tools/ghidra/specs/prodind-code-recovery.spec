# Task 033: the static-text control handlers are reachable ONLY through the default
# per-control-type tables (0x005014AC interact / 0x00501504 update, indexed by
# controlType), so Ghidra's call-graph walk never reaches them and auto-analysis leaves
# the bytes undefined. Each seed below is a table ENTRY dumped out of .rdata by
# work/scratch/033/peek.py -- a pointer the binary itself holds, not a guess.
#
# label,addrHex
s1,00419190
s2,004EF9E0
s3,004EF9C0
s4,004EF9A0
