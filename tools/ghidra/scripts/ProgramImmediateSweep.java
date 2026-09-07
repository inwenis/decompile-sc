// PROGRAM-WIDE immediate-constant sweep: every instruction, not a named function list.
// ImmediateSweep.java asks "where does constant X appear inside functions I already know";
// this asks the question before it -- "which functions mention X at all" -- for the case where
// no function list exists yet and the constant is the only handle on the target.
//
// The `opKind` column matters: in `MOV EAX,[EDX + 0x280]` the 0x280 is a structure
// displacement, in `CMP EAX,0x280` a screen width, and instruction text alone cannot tell them
// apart. No companion body dump: program-wide that is the whole disassembly listing, derived
// game content at a size nobody reads. Decompile hits with DecompileMany/analyze.ps1 instead.
//
// Args: <outTsv> <hexWatchList> [immediate]
//   <path>.manifest is the run's success signal. Separate watch values with '+': analyzeHeadless
//   is a .bat, so cmd.exe re-splits a comma-separated list into several arguments and the sweep
//   then watches only the first value while still reporting success; ',' is accepted only for a
//   list built outside cmd. 'immediate' drops the structure displacements, which for a value
//   like 0x280 are the bulk of the noise.
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
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

public class ProgramImmediateSweep extends GhidraScript {

    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length < 2) {
            throw new IllegalArgumentException(
                "usage: ProgramImmediateSweep.java <outTsv> <watchHexList> [immediate]");
        }
        String outPath = args[0];
        boolean immediatesOnly = args.length >= 3 && "immediate".equalsIgnoreCase(args[2].trim());

        Set<Long> watch = new LinkedHashSet<>();
        for (String t : args[1].split("[,+]")) {
            String s = t.trim();
            if (s.isEmpty()) {
                continue;
            }
            if (s.startsWith("0x") || s.startsWith("0X")) {
                s = s.substring(2);
            }
            watch.add(Long.parseUnsignedLong(s, 16));
        }
        println("ProgramImmediateSweep: watching " + watch + " immediatesOnly=" + immediatesOnly);

        Path out = Paths.get(outPath);
        if (out.toAbsolutePath().getParent() != null) {
            Files.createDirectories(out.toAbsolutePath().getParent());
        }

        long rows = 0;
        long scanned = 0;

        try (PrintWriter w = new PrintWriter(Files.newBufferedWriter(out))) {
            w.println(String.join("\t", "funcEntry", "funcName", "insAddr", "opIndex", "opKind",
                "valueHex", "valueDec", "mnemonic", "instruction"));

            InstructionIterator it = currentProgram.getListing().getInstructions(true);
            while (it.hasNext()) {
                Instruction ins = it.next();
                scanned++;
                for (int op = 0; op < ins.getNumOperands(); op++) {
                    String opKind = operandKind(ins.getOperandType(op));
                    if (immediatesOnly && !"immediate".equals(opKind)) {
                        continue;
                    }
                    for (Object o : ins.getOpObjects(op)) {
                        if (!(o instanceof Scalar)) {
                            continue;
                        }
                        long v = ((Scalar) o).getUnsignedValue();
                        if (!watch.contains(v)) {
                            continue;
                        }
                        Address a = ins.getAddress();
                        Function f = currentProgram.getFunctionManager().getFunctionContaining(a);
                        w.println(String.join("\t",
                            f == null ? "" : SweepUtil.hex(f.getEntryPoint().getOffset()),
                            f == null ? "" : f.getName(),
                            SweepUtil.hex(a.getOffset()),
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
        }

        println("ProgramImmediateSweep: " + scanned + " instructions scanned, " + rows
            + " matches -> " + out.toAbsolutePath());
        SweepUtil.writeManifest(outPath, rows, List.of("instructionsScanned=" + scanned));
    }

    /** Same classification ImmediateSweep uses, so the two sweeps' opKind columns compare. */
    private static String operandKind(int type) {
        if (OperandType.isDynamic(type) || OperandType.isAddress(type)) {
            return "mem-operand";
        }
        if (OperandType.isScalar(type)) {
            return "immediate";
        }
        return "other";
    }
}
