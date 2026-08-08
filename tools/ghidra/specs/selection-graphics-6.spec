# Task 014, round 6: the displacement-0x0B candidates rounds 1-5 skipped.
#
# label,addrHex   -- NOTE: SweepUtil.readSpec does not strip trailing comments, so the note for
# each entry goes on its own line above it.
#
# PR #14 review, finding 3: research/selection-circles.md 4.1 claimed "every candidate that could
# not be dismissed by its module was decompiled and read". That was not true. These functions own
# byte accesses at [reg+0xB] in work/scratch/selgfx3/disp0b.tsv and appeared in no spec, no
# decompilation and no document -- and one of them (0x00472300) sits directly beside a function
# round 5 DID examine, so "dismissed by module" cannot cover it.
#
# Reading them is what turns "the readers are these four" from an assertion into a result.

# --- skipped READS -----------------------------------------------------------------------------
# 0x00418514  TEST byte ptr [EDI + 0xb],0x1
skippedRead418510,0x00418510
# 0x0042E9EC  MOV CL,[EDI+0xb] ; 0x0042EB97  MOV DL,[EDI+0xb]
skippedRead42E600,0x0042E600
# 0x00435227  MOV AL,[EDI+0xb]   (and the write at 0x00435235)
skippedRead435210,0x00435210
# 0x004723CC  MOVZX EAX,byte ptr [EBX + 0xb]
skippedRead472300,0x00472300

# --- skipped WRITES ----------------------------------------------------------------------------
# 0x00403DCB  MOV byte ptr [ECX + 0xb],DL
skippedWrite403DB0,0x00403DB0
# 0x00403E74  MOV byte ptr [EAX + 0xb],BL
skippedWrite403E50,0x00403E50
# 0x00433E3A  MOV byte ptr [EAX + 0xb],0x0
skippedWrite433DD0,0x00433DD0
# 0x00435B4A  MOV byte ptr [EDI + 0xb],0xa
skippedWrite435900,0x00435900
# 0x00472627  MOV byte ptr [ESI + 0xb],AL
skippedWrite472570,0x00472570
