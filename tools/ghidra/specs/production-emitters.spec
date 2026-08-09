# Callers of the production command builders, task 025.
#
# label,startHex,byteLength  (XrefSweep takes RANGES)
#
# One 1-byte range per builder ENTRY POINT, so pass 1 reports every reference that
# reaches it. The five addresses are the `emitters` column of
# research/data/command-ids.tsv (committed, built by tools/ghidra/build-command-table.ps1
# from this binary) for opcodes 0x1F / 0x20 / 0x18. The question they answer: what code
# decides a Train command is worth sending -- i.e. where a client-side "the queue is
# full" refusal would live.

emitTrainCmdact,0x004C01C0,1
emitTrainUi,0x004234B0,1
emitCancelTrainCmdact,0x004C01A0,1
emitCancelTrainUi,0x00423490,1
addToBuildQueue,0x00467250,1
findFreeBuildQueueSlot,0x004669B0,1
cancelBuildQueueSlot,0x00466A70,1
