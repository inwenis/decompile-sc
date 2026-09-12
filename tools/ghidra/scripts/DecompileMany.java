// Decompiles a LIST of functions in one pass against an already-analyzed program.
// One import+analyze cycle per function (tools/ghidra/analyze.ps1) costs minutes each on a 1.2 MB
// binary, so batching against the persistent project is what makes side-by-side comparison affordable.
//
// Output .c files are DERIVED GAME CONTENT -- whole decompiled functions -- and must stay under a
// gitignored scratch path (AGENTS.md § "Hard rules"). Only findings about them belong in research/.
//
// Script args:
//   1: index TSV path; the .c files land beside it. <path>.manifest is the run's success signal.
//   2: spec file -- one function per line: label,addrHex -- or the word ALL for every
//      non-thunk function in the program, labelled by its entry address; ALL also writes
//      ranges.tsv beside the index, one row per contiguous body range, because a function body
//      can be several chunks and its first..last address then spans unrelated code
//   3: optional -- per-function decompile timeout in seconds (default 120)
//@category Headless

import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileOptions;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.address.AddressRange;
import ghidra.program.model.listing.Function;
import ghidra.util.task.ConsoleTaskMonitor;

import java.io.PrintWriter;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
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
        List<SweepUtil.Spec> specs;
        if ("ALL".equals(args[1])) {
            specs = new ArrayList<>();
            for (Function f : currentProgram.getFunctionManager().getFunctions(true)) {
                if (f.isThunk() || f.isExternal()) {
                    continue;
                }
                String hex = SweepUtil.hex(f.getEntryPoint().getOffset());
                specs.add(new SweepUtil.Spec(hex, List.of(hex)));
            }
        }
        else {
            specs = SweepUtil.readSpec(args[1]);
        }
        int timeoutSecs = args.length >= 3 ? Integer.parseInt(args[2]) : 120;

        Path index = Paths.get(outPath).toAbsolutePath();
        Files.createDirectories(index.getParent());
        Path dir = index.getParent();

        DecompInterface decomp = new DecompInterface();
        long rows = 0;
        List<String> ranges = new ArrayList<>();
        ranges.add(String.join("\t", "start", "end", "funcEntry", "funcName", "cFile"));
        try {
            decomp.setOptions(new DecompileOptions());
            if (!decomp.openProgram(currentProgram)) {
                throw new RuntimeException("decompiler failed to open program: " + decomp.getLastMessage());
            }

            try (PrintWriter w = new PrintWriter(Files.newBufferedWriter(index))) {
                // nameSource separates evidence from hypothesis: ANALYSIS = Ghidra's Function ID /
                // RTTI, USER_DEFINED = this repo's override (magnetar-overrides.tsv), IMPORTED = a
                // third-party table (Magnetar), DEFAULT = no name at all.
                // funcEnd ends the entry's own chunk; other chunks are only in ranges.tsv.
                w.println(String.join("\t", "label", "specAddr", "resolvedVia", "funcName",
                    "funcEntry", "bodyBytes", "status", "cFile", "cLines", "nameSource", "funcEnd"));

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
                            "none", "", "", "", "NO-FUNCTION", "", "0", "", ""));
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
                        // Names carry ':' (FID_conflict:__time32) and quotes (RTTI); Windows
                        // rejects both in a file name. The index keeps the real name.
                        String safe = f.getName().replaceAll("[^A-Za-z0-9_.~-]", "_");
                        fileName = s.label + "." + (safe.length() > 100 ? safe.substring(0, 100) : safe) + ".c";
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
                        Integer.toString(lines),
                        f.getSymbol().getSource().toString(),
                        SweepUtil.hex(f.getBody().getRangeContaining(f.getEntryPoint()).getMaxAddress().getOffset())));
                    for (AddressRange r : f.getBody()) {
                        ranges.add(String.join("\t", SweepUtil.hex(r.getMinAddress().getOffset()),
                            SweepUtil.hex(r.getMaxAddress().getOffset()),
                            SweepUtil.hex(f.getEntryPoint().getOffset()), f.getName(), fileName));
                    }
                    println("DecompileMany: " + s.label + " " + f.getName() + " -> " + status);
                    rows++;
                }
            }
        }
        finally {
            decomp.dispose();
        }

        if ("ALL".equals(args[1])) {
            Files.write(dir.resolve("ranges.tsv"), ranges);
        }
        SweepUtil.writeManifest(outPath, rows, null);
    }

    private Address addr(long offset) {
        return currentProgram.getAddressFactory().getDefaultAddressSpace().getAddress(offset);
    }
}
