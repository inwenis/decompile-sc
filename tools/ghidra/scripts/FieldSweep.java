// Finds every instruction that touches a STRUCT FIELD at a given displacement.
//
// A field inside a heap object has no address, only an OFFSET, so XrefSweep's "who touches this
// global address" cannot enumerate its readers; the displacement in the operands can.
//
// Motivating case: the engine derives a memcpy length from `CSprite::selectionIndex` (offset 0xB),
// so no value is safe there until every instruction that reads it is enumerated
// (research/selection-cap.md).
//
// Matching is deliberately coarse: any [reg + disp] or [reg + reg*s + disp] operand carrying the
// requested displacement, at any width. A displacement is not proof the base register holds the
// struct we want, so the output is a CANDIDATE list to read, not an answer -- and not proof of
// ABSENCE: an access that computed the field address arithmetically (LEA, or a base already
// advanced past the struct start) carries no displacement and cannot appear here. Say so
// wherever a result of this sweep is quoted.
//
// Args: 1 output TSV path (its .manifest is the run's success signal); 2 displacement, hex;
// 3 access filter read|write|any (default any) -- an instruction that both reads and writes the
// field matches BOTH, and one Ghidra could not classify (access "?") matches EVERY filter.
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
                    // An operand that is not a memory reference (e.g. `ADD EAX,0xB`) is
                    // arithmetic, not a field access.
                    if (insn.getDefaultOperandRepresentation(op).indexOf('[') < 0) {
                        continue;
                    }
                    // Classify by Ghidra's RefType, never by operand position: `TEST byte ptr
                    // [EDI+0xb],0x1` and `CMP byte ptr [ESI+0xb],0x7` READ their operand-0
                    // memory, and OR/AND both read and write it, so a position-based filter
                    // silently drops the very readers this sweep exists to enumerate.
                    RefType rt = insn.getOperandRefType(op);
                    boolean reads = rt != null && rt.isRead();
                    boolean writes = rt != null && rt.isWrite();
                    // UNKNOWN means Ghidra recorded no usable classification: no RefType at all,
                    // or a non-null one claiming neither (RefType.INVALID). Such a row passes
                    // EVERY mode -- dropping what the classifier could not classify is silent
                    // under-reporting in a sweep whose whole purpose is enumeration.
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
