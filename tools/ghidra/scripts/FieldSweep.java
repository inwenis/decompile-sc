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
// with the requested displacement, on an instruction whose operand size matches -Size (0 = any).
// A displacement is not proof the base register holds the struct we care about, so the output is
// a CANDIDATE list to be read, not an answer. It is small enough to read.
//
// Script args:
//   1: output TSV path (its .manifest is the run's success signal)
//   2: displacement, hex (e.g. 0xB)
//   3: optional access filter -- "read", "write" or "any" (default any)
//
//@category Headless

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.lang.Register;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.listing.InstructionIterator;
import ghidra.program.model.scalar.Scalar;

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
                "opIndex", "baseReg", "text"));

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
                    if (!"any".equals(mode)) {
                        boolean isDest = (op == 0);
                        if ("write".equals(mode) && !isDest) {
                            continue;
                        }
                        if ("read".equals(mode) && isDest) {
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
