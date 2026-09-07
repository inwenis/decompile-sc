// Immediate-constant sweep across a named set of functions.
//
// Answers where 12 (and 12*4, 11, 18) is baked into the selection code and in what ROLE: a
// comparison is a policy check, an index scale is structural, and the two need different
// treatment when raising the cap. The script locates the constants; the role is read off the
// surrounding instructions, so each target function's instruction stream is dumped alongside.
//
// That companion dump is DERIVED GAME CONTENT -- a disassembly listing of real functions -- so
// it must never be committed and must stay under a gitignored scratch path; see AGENTS.md
// § "Hard rules". Only the distilled constant table belongs in research/.
//
// Args: 1 output TSV (companion dump <path>.body.txt, success signal <path>.manifest),
//       2 spec file of label,functionAddrHex lines, 3 optional '+'-separated hex watch values.
//
//@category Headless

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.lang.OperandType;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.listing.InstructionIterator;
import ghidra.program.model.scalar.Scalar;

import java.io.PrintWriter;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

public class ImmediateSweep extends GhidraScript {

    // 0x180 = 384 = sizeof(playersSelections): pushed as a byte length beside a materialisation
    // of 0x6284E8, the same class of array-size value as 0x30 and 0x6C0, and a relocation site.
    private static final String DEFAULT_WATCH = "c,b,30,2c,12,180,1b00";

    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length < 2) {
            throw new IllegalArgumentException(
                "usage: ImmediateSweep.java <outTsv> <specFile> [watchHexCsv]");
        }
        String outPath = args[0];
        List<SweepUtil.Spec> specs = SweepUtil.readSpec(args[1]);
        String watchCsvRaw = args.length >= 3 ? args[2] : DEFAULT_WATCH;

        // Split on '+' as well as ',': analyzeHeadless is a .bat, so cmd.exe splits the command
        // line on commas as well as spaces. A comma-separated watch list passed as ONE argument
        // arrives as several and the script then silently watches only the first value. Callers
        // should use '+'; ',' stays accepted for a list built outside cmd.
        Set<Long> watch = new LinkedHashSet<>();
        for (String t : watchCsvRaw.split("[,+]")) {
            String s = t.trim();
            if (s.isEmpty()) {
                continue;
            }
            if (s.startsWith("0x") || s.startsWith("0X")) {
                s = s.substring(2);
            }
            watch.add(Long.parseUnsignedLong(s, 16));
        }
        println("ImmediateSweep: watching " + watch);

        Path out = Paths.get(outPath);
        if (out.toAbsolutePath().getParent() != null) {
            Files.createDirectories(out.toAbsolutePath().getParent());
        }

        long rows = 0;
        List<String> unresolved = new ArrayList<>();

        try (PrintWriter w = new PrintWriter(Files.newBufferedWriter(out));
             PrintWriter body = new PrintWriter(Files.newBufferedWriter(Paths.get(outPath + ".body.txt")))) {

            w.println(String.join("\t", "label", "specAddr", "resolvedVia", "funcEntry", "funcName",
                "insAddr", "opIndex", "opKind", "valueHex", "valueDec", "mnemonic", "instruction"));

            for (SweepUtil.Spec s : specs) {
                Address want = addr(s.hex(0));
                Function f = currentProgram.getFunctionManager().getFunctionAt(want);
                String via = "exact-entry";
                if (f == null) {
                    f = currentProgram.getFunctionManager().getFunctionContaining(want);
                    via = "containing";
                }
                if (f == null) {
                    println("WARNING: no function at or containing " + want + " (" + s.label + ")");
                    unresolved.add(s.label + "@" + want);
                    body.println("### " + s.label + " " + want + " -- NO FUNCTION AT OR CONTAINING");
                    body.println();
                    continue;
                }
                if (!"exact-entry".equals(via)) {
                    println("WARNING: " + want + " (" + s.label + ") is NOT a function entry point; "
                        + "resolved to ENCLOSING function " + f.getName() + " @ " + f.getEntryPoint());
                }

                body.println("### " + s.label + "  spec=" + want + "  resolved=" + f.getName()
                    + " @ " + f.getEntryPoint() + " via " + via
                    + "  body=" + f.getBody().getMinAddress() + ".." + f.getBody().getMaxAddress()
                    + "  bytes=" + f.getBody().getNumAddresses());

                InstructionIterator it = currentProgram.getListing().getInstructions(f.getBody(), true);
                while (it.hasNext()) {
                    Instruction ins = it.next();
                    body.println("  " + ins.getAddress() + "  " + ins);
                    for (int op = 0; op < ins.getNumOperands(); op++) {
                        String opKind = operandKind(ins.getOperandType(op));
                        for (Object o : ins.getOpObjects(op)) {
                            if (!(o instanceof Scalar)) {
                                continue;
                            }
                            long v = ((Scalar) o).getUnsignedValue();
                            if (!watch.contains(v)) {
                                continue;
                            }
                            w.println(String.join("\t",
                                s.label,
                                SweepUtil.hex(want.getOffset()),
                                via,
                                SweepUtil.hex(f.getEntryPoint().getOffset()),
                                f.getName(),
                                SweepUtil.hex(ins.getAddress().getOffset()),
                                Integer.toString(op),
                                opKind,
                                "0x" + Long.toHexString(v).toUpperCase(),
                                Long.toString(v),
                                ins.getMnemonicString(),
                                SweepUtil.cell(ins)));
                            rows++;
                        }
                    }
                }
                body.println();
            }
        }

        println("ImmediateSweep: wrote " + rows + " matching immediates -> " + out.toAbsolutePath());
        SweepUtil.writeManifest(outPath, rows, List.of(
            "bodyDump=" + (outPath + ".body.txt").replace("\\", "/"),
            "unresolved=" + String.join(";", unresolved)));
    }

    /**
     * What the matched scalar IS within its operand. An x86 instruction can carry a memory
     * displacement AND an immediate at once, and they mean opposite things here: in
     * `CMP byte ptr [ESI + 0x1],0xc` the 0xc is the selection cap checked against a packet field
     * and the 0x1 is a structure offset. Instruction text cannot tell them apart, so the kind
     * comes from Ghidra's operand type at the point where the match is made.
     *
     *   immediate    a literal operand in its own right -- CMP DL,0xc / PUSH 0x180 / RET 0xc.
     *   mem-operand  part of a memory reference -- the displacement in [ECX + 0xc], or a scale
     *                factor. Never a cap for any value watched here (scales are only 1/2/4/8).
     *   other        neither; emitted rather than guessed at.
     */
    private static String operandKind(int type) {
        if (OperandType.isDynamic(type) || OperandType.isAddress(type)) {
            return "mem-operand";
        }
        if (OperandType.isScalar(type)) {
            return "immediate";
        }
        return "other";
    }

    private Address addr(long offset) {
        return currentProgram.getAddressFactory().getDefaultAddressSpace().getAddress(offset);
    }
}
