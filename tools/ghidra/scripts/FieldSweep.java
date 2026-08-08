// Finds every instruction that touches a STRUCT FIELD at a given displacement.
//
// XrefSweep answers "who touches this global address". That is the wrong question for a field
// inside a heap object: `CSprite::selectionIndex` has no address, it has an OFFSET, and the
// only way to enumerate its readers is to look for the displacement in the operands.
//
// Task 014 needs this because research/selection-cap.md 2.4 names selectionIndex as a HAZARD --
// GPTP computes a memcpy length from it -- and the task cannot pick a safe value for a
// shadow-selected unit without knowing every instruction in this binary that reads it.
//
// Matching is deliberately coarse: any operand of the form [reg + disp] or [reg + reg*s + disp]
// with the requested displacement, at any width. A displacement is not proof the base register
// holds the struct we care about, so the output is a CANDIDATE list to be read, not an answer.
// It is small enough to read.
//
// It is also not a proof of ABSENCE: an access that computed the field address arithmetically
// (LEA into a register, or a base already advanced past the struct start) carries no displacement
// and cannot appear here. Say so wherever a result of this sweep is quoted.
//
// The access filter classifies by Ghidra's own operand REFERENCE TYPE, not by operand position.
// An earlier version used "operand 0 == write", which is wrong for exactly the instructions this
// sweep exists to find: `TEST byte ptr [EDI+0xb],0x1` and `CMP byte ptr [ESI+0xb],0x7` are READS
// of a field written in operand position 0, and a position-based filter silently dropped them --
// under-reporting readers in a sweep whose whole purpose is to enumerate them.
//
// Script args:
//   1: output TSV path (its .manifest is the run's success signal)
//   2: displacement, hex (e.g. 0xB)
//   3: optional access filter -- "read", "write" or "any" (default any). An instruction that both
//      reads and writes the field (e.g. `OR byte ptr [ESI+0xe],BL`) matches BOTH filters, and one
//      Ghidra could not classify (access "?") matches EVERY filter rather than being dropped.
//
//@category Headless

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.lang.Register;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.listing.InstructionIterator;
import ghidra.program.model.scalar.Scalar;
import ghidra.program.model.symbol.RefType;

import java.io.PrintWriter;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;

public class FieldSweep extends GhidraScript {

    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length < 2) {
            throw new IllegalArgumentException("usage: FieldSweep.java <outTsv> <dispHex> [read|write|any]");
        }
        String outPath = args[0];
        String dispStr = args[1].trim();
        if (dispStr.startsWith("0x") || dispStr.startsWith("0X")) {
            dispStr = dispStr.substring(2);
        }
        long wantDisp = Long.parseUnsignedLong(dispStr, 16);
        String mode = args.length >= 3 ? args[2].trim().toLowerCase() : "any";

        Path out = Paths.get(outPath).toAbsolutePath();
        Files.createDirectories(out.getParent());

        long rows = 0;
        try (PrintWriter w = new PrintWriter(Files.newBufferedWriter(out))) {
            w.println(String.join("\t", "addr", "function", "funcEntry", "mnemonic",
                "opIndex", "baseReg", "access", "text"));

            InstructionIterator it = currentProgram.getListing().getInstructions(true);
            while (it.hasNext()) {
                Instruction insn = it.next();
                int nOps = insn.getNumOperands();
                for (int op = 0; op < nOps; op++) {
                    // Only memory operands can carry a struct displacement.
                    Object[] parts = insn.getOpObjects(op);
                    boolean hasReg = false;
                    boolean hasDisp = false;
                    String baseReg = "";
                    for (Object o : parts) {
                        if (o instanceof Register) {
                            if (!hasReg) {
                                baseReg = ((Register) o).getName();
                            }
                            hasReg = true;
                        }
                        else if (o instanceof Scalar) {
                            long v = ((Scalar) o).getUnsignedValue();
                            if (v == wantDisp) {
                                hasDisp = true;
                            }
                        }
                    }
                    if (!hasReg || !hasDisp) {
                        continue;
                    }
                    // An operand that is not a memory reference (e.g. `ADD EAX,0xB`) has no
                    // dynamic address; skip it, it is arithmetic, not a field access.
                    if (insn.getDefaultOperandRepresentation(op).indexOf('[') < 0) {
                        continue;
                    }
                    // Ghidra's own read/write classification for this operand. Position tells
                    // you nothing here: TEST and CMP read their operand-0 memory, and OR/AND
                    // both read AND write it.
                    RefType rt = insn.getOperandRefType(op);
                    boolean reads = rt != null && rt.isRead();
                    boolean writes = rt != null && rt.isWrite();
                    // UNKNOWN means Ghidra recorded no usable classification -- either no RefType
                    // at all, or a non-null one that claims neither (RefType.INVALID does exactly
                    // that). Such a row must never be filtered out by EITHER mode: dropping rows
                    // a classifier could not classify is the same silent under-reporting the
                    // position-based version had, just from a different direction.
                    final boolean unknown = !reads && !writes;
                    String access = unknown ? "?" : ((reads ? "r" : "") + (writes ? "w" : ""));
                    if (!unknown) {
                        if ("write".equals(mode) && !writes) {
                            continue;
                        }
                        if ("read".equals(mode) && !reads) {
                            continue;
                        }
                    }

                    Address a = insn.getAddress();
                    Function f = currentProgram.getFunctionManager().getFunctionContaining(a);
                    w.println(String.join("\t",
                        SweepUtil.hex(a.getOffset()),
                        f == null ? "" : f.getName(),
                        f == null ? "" : SweepUtil.hex(f.getEntryPoint().getOffset()),
                        insn.getMnemonicString(),
                        Integer.toString(op),
                        baseReg,
                        access,
                        SweepUtil.cell(insn.toString())));
                    rows++;
                }
            }
        }

        SweepUtil.writeManifest(outPath, rows, null);
        println("FieldSweep: " + rows + " candidate operands at displacement 0x"
            + Long.toHexString(wantDisp));
    }
}
