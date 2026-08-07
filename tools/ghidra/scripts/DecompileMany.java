// Decompiles a LIST of functions in one pass against an already-analyzed program.
//
// tools/ghidra/analyze.ps1 (task 001) decompiles one function per import+analyze cycle, which
// is minutes each on a 1.2 MB binary. Calibration against GPTP needs five functions compared
// side by side, so they are decompiled together against the persistent project instead.
//
// Output .c files are DERIVED GAME CONTENT -- whole decompiled functions. They exist to be read
// during analysis and must stay under a gitignored scratch path (AGENTS.md hard rule 1). Only
// findings about them belong in research/.
//
// Script args:
//   1: index TSV path; the .c files land beside it. <path>.manifest is the run's success signal.
//   2: spec file -- one function per line: label,addrHex
//   3: optional -- per-function decompile timeout in seconds (default 120)
//
//@category Headless

import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileOptions;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.util.task.ConsoleTaskMonitor;

import java.io.PrintWriter;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.List;

public class DecompileMany extends GhidraScript {

    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length < 2) {
            throw new IllegalArgumentException(
                "usage: DecompileMany.java <indexTsv> <specFile> [timeoutSecs]");
        }
        String outPath = args[0];
        List<SweepUtil.Spec> specs = SweepUtil.readSpec(args[1]);
        int timeoutSecs = args.length >= 3 ? Integer.parseInt(args[2]) : 120;

        Path index = Paths.get(outPath).toAbsolutePath();
        Files.createDirectories(index.getParent());
        Path dir = index.getParent();

        DecompInterface decomp = new DecompInterface();
        long rows = 0;
        try {
            decomp.setOptions(new DecompileOptions());
            if (!decomp.openProgram(currentProgram)) {
                throw new RuntimeException("decompiler failed to open program: " + decomp.getLastMessage());
            }

            try (PrintWriter w = new PrintWriter(Files.newBufferedWriter(index))) {
                w.println(String.join("\t", "label", "specAddr", "resolvedVia", "funcName",
                    "funcEntry", "bodyBytes", "status", "cFile", "cLines"));

                for (SweepUtil.Spec s : specs) {
                    Address a = addr(s.hex(0));
                    Function f = currentProgram.getFunctionManager().getFunctionAt(a);
                    String via = "exact-entry";
                    if (f == null) {
                        f = currentProgram.getFunctionManager().getFunctionContaining(a);
                        via = "containing";
                    }
                    if (f == null) {
                        println("WARNING: no function at or containing " + a + " (" + s.label + ")");
                        w.println(String.join("\t", s.label, SweepUtil.hex(a.getOffset()),
                            "none", "", "", "", "NO-FUNCTION", "", "0"));
                        rows++;
                        continue;
                    }
                    if (!"exact-entry".equals(via)) {
                        println("WARNING: " + a + " (" + s.label + ") is NOT a function entry point; "
                            + "resolved to ENCLOSING function " + f.getName() + " @ " + f.getEntryPoint());
                    }

                    DecompileResults res = decomp.decompileFunction(f, timeoutSecs, new ConsoleTaskMonitor());
                    String status;
                    String fileName = "";
                    int lines = 0;
                    if (res.decompileCompleted()) {
                        String c = res.getDecompiledFunction().getC();
                        fileName = s.label + "." + f.getName() + ".c";
                        Files.writeString(dir.resolve(fileName), c);
                        lines = c.split("\n", -1).length;
                        status = "OK";
                    }
                    else {
                        status = "FAILED: " + res.getErrorMessage();
                    }

                    w.println(String.join("\t",
                        s.label,
                        SweepUtil.hex(a.getOffset()),
                        via,
                        f.getName(),
                        SweepUtil.hex(f.getEntryPoint().getOffset()),
                        Long.toString(f.getBody().getNumAddresses()),
                        SweepUtil.cell(status),
                        fileName,
                        Integer.toString(lines)));
                    println("DecompileMany: " + s.label + " " + f.getName() + " -> " + status);
                    rows++;
                }
            }
        }
        finally {
            decomp.dispose();
        }

        SweepUtil.writeManifest(outPath, rows, null);
    }

    private Address addr(long offset) {
        return currentProgram.getAddressFactory().getDefaultAddressSpace().getAddress(offset);
    }
}
