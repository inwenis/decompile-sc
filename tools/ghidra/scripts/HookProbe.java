// Everything an inline (detour) hook needs to know about a target function, plus its callers.
//
// A 5-byte JMP detour overwrites the target's first instructions, so the bytes relocated into a
// trampoline must be known EXACTLY -- length, and whether any is position-dependent (a rel8/rel32
// jump or call moved to a different address stops pointing where it did). "Probably a standard
// prologue" is not good enough when the failure mode is a corrupted game process.
//
// The .callers file lists every reference reaching an entry point with the function containing it:
// how a shared sink's callers are enumerated -- the CMDACT_* emitters above the queue function.
//
// Output .asm/.callers files are DERIVED GAME CONTENT (whole disassembled functions) and must
// stay under a gitignored scratch path (AGENTS.md § "Hard rules"). Only findings belong in research/.
//
// Args: 1 = output TSV (<path>.manifest signals success; side files land beside it); 2 = spec file, `label,addrHex` per line.
//@category Headless

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.listing.InstructionIterator;
import ghidra.program.model.symbol.FlowType;
import ghidra.program.model.symbol.Reference;
import ghidra.program.model.symbol.ReferenceIterator;

import java.io.PrintWriter;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.List;

public class HookProbe extends GhidraScript {

    /** A detour writes a 5-byte E9 rel32; the patch window is whole instructions covering it. */
    private static final int DETOUR_BYTES = 5;

    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length < 2) {
            throw new IllegalArgumentException("usage: HookProbe.java <outTsv> <specFile>");
        }
        String outPath = args[0];
        List<SweepUtil.Spec> specs = SweepUtil.readSpec(args[1]);

        Path out = Paths.get(outPath).toAbsolutePath();
        Files.createDirectories(out.getParent());
        Path dir = out.getParent();

        long rows = 0;
        try (PrintWriter w = new PrintWriter(Files.newBufferedWriter(out))) {
            w.println(String.join("\t", "label", "specAddr", "verdict", "funcName", "funcEntry",
                "bodyBytes", "instructions", "callingConvention", "patchBytes", "patchInstrs",
                "patchRelocSafe", "callRefs", "jumpRefs", "refsTotal", "asmFile", "callersFile",
                "firstInstruction"));

            for (SweepUtil.Spec s : specs) {
                Address a = addr(s.hex(0));
                Function exact = currentProgram.getFunctionManager().getFunctionAt(a);
                Function f = exact != null ? exact
                    : currentProgram.getFunctionManager().getFunctionContaining(a);
                String verdict = exact != null ? "ENTRY-POINT"
                    : f != null ? "INSIDE-FUNCTION"
                    : currentProgram.getListing().getInstructionContaining(a) != null
                        ? "CODE-NO-FUNCTION" : "NOT-CODE";

                if (f == null) {
                    w.println(String.join("\t", s.label, SweepUtil.hex(a.getOffset()), verdict,
                        "", "", "", "0", "", "0", "0", "", "0", "0", "0", "", "", ""));
                    println("HookProbe: " + s.label + " " + verdict);
                    rows++;
                    continue;
                }

                List<Instruction> instrs = new ArrayList<>();
                InstructionIterator it =
                    currentProgram.getListing().getInstructions(f.getBody(), true);
                while (it.hasNext()) {
                    instrs.add(it.next());
                }

                String asmName = s.label + "." + f.getName() + ".asm";
                try (PrintWriter aw = new PrintWriter(Files.newBufferedWriter(dir.resolve(asmName)))) {
                    aw.println("# " + s.label + "  " + f.getName() + " @ "
                        + SweepUtil.hex(f.getEntryPoint().getOffset())
                        + "  cc=" + f.getCallingConventionName());
                    for (Instruction ins : instrs) {
                        aw.println(SweepUtil.hex(ins.getAddress().getOffset()) + "  "
                            + rawBytes(ins) + "  " + (pcRelative(ins) ? "REL " : "    ")
                            + SweepUtil.cell(ins));
                    }
                }

                // A body can extend below its entry point; only bytes at the entry are overwritten.
                int patchBytes = 0;
                int patchInstrs = 0;
                boolean relocSafe = true;
                for (Instruction ins : instrs) {
                    if (ins.getAddress().compareTo(f.getEntryPoint()) < 0) {
                        continue;
                    }
                    if (patchBytes >= DETOUR_BYTES) {
                        break;
                    }
                    patchBytes += ins.getLength();
                    patchInstrs++;
                    if (pcRelative(ins)) {
                        relocSafe = false;
                    }
                }

                int callRefs = 0;
                int jumpRefs = 0;
                int refsTotal = 0;
                String callersName = s.label + "." + f.getName() + ".callers";
                try (PrintWriter cw = new PrintWriter(Files.newBufferedWriter(dir.resolve(callersName)))) {
                    cw.println("# refFrom\trefType\tcontainingFunc\tcontainingEntry\tinstruction");
                    ReferenceIterator rit = currentProgram.getReferenceManager()
                        .getReferencesTo(f.getEntryPoint());
                    while (rit.hasNext()) {
                        Reference r = rit.next();
                        refsTotal++;
                        if (r.getReferenceType().isCall()) {
                            callRefs++;
                        }
                        else if (r.getReferenceType().isJump()) {
                            jumpRefs++;
                        }
                        Address from = r.getFromAddress();
                        Function cf = currentProgram.getFunctionManager().getFunctionContaining(from);
                        Instruction ci = currentProgram.getListing().getInstructionContaining(from);
                        cw.println(SweepUtil.hex(from.getOffset()) + "\t"
                            + r.getReferenceType().getName() + "\t"
                            + (cf == null ? "" : cf.getName()) + "\t"
                            + (cf == null ? "" : SweepUtil.hex(cf.getEntryPoint().getOffset())) + "\t"
                            + (ci == null ? "" : SweepUtil.cell(ci)));
                    }
                }

                w.println(String.join("\t",
                    s.label,
                    SweepUtil.hex(a.getOffset()),
                    verdict,
                    f.getName(),
                    SweepUtil.hex(f.getEntryPoint().getOffset()),
                    Long.toString(f.getBody().getNumAddresses()),
                    Integer.toString(instrs.size()),
                    f.getCallingConventionName(),
                    Integer.toString(patchBytes),
                    Integer.toString(patchInstrs),
                    Boolean.toString(relocSafe),
                    Integer.toString(callRefs),
                    Integer.toString(jumpRefs),
                    Integer.toString(refsTotal),
                    asmName,
                    callersName,
                    instrs.isEmpty() ? "" : SweepUtil.cell(instrs.get(0))));
                println("HookProbe: " + s.label + " " + f.getName() + " patch=" + patchBytes
                    + "B/" + patchInstrs + " relocSafe=" + relocSafe + " refs=" + refsTotal);
                rows++;
            }
        }

        SweepUtil.writeManifest(outPath, rows, null);
    }

    /** True if moving this instruction to another address would change where it points. */
    private boolean pcRelative(Instruction ins) {
        FlowType ft = ins.getFlowType();
        if (ft.isJump() || ft.isCall()) {
            // Register/indirect flows carry no displacement to fix up; everything else does.
            return !ft.isComputed();
        }
        return false;
    }

    private String rawBytes(Instruction ins) {
        StringBuilder sb = new StringBuilder();
        try {
            for (byte b : ins.getBytes()) {
                sb.append(String.format("%02X", b));
            }
        }
        catch (Exception e) {
            return "??";
        }
        // pad to a stable column width (10 bytes = 20 hex chars)
        while (sb.length() < 20) {
            sb.append(' ');
        }
        return sb.toString();
    }

    private Address addr(long offset) {
        return currentProgram.getAddressFactory().getDefaultAddressSpace().getAddress(offset);
    }
}
