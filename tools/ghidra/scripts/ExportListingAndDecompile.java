// Headless post-script: exports (a) a full disassembly listing and (b) decompiled C for one
// function to text files under an output directory. Function is selected by name or by a
// 0x-prefixed hex address (address form is for stripped binaries with no symbol, e.g. a
// StarCraft 1.16.1 target function).
//
// Script args (see analyzeHeadless -postScript):
//   1: output directory (created if missing)
//   2: function selector -- exact function name, or 0xHHHHHHHH address
//
// Driven by tools/ghidra/analyze.ps1 -- see tools/ghidra/README.md for usage.
//
//@category Headless

import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileOptions;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.CodeUnit;
import ghidra.program.model.listing.CodeUnitIterator;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Listing;
import ghidra.util.task.ConsoleTaskMonitor;

import java.io.PrintWriter;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Iterator;

public class ExportListingAndDecompile extends GhidraScript {

    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length < 2) {
            throw new IllegalArgumentException(
                "usage: ExportListingAndDecompile.java <outDir> <functionNameOr0xAddress>");
        }
        Path outDir = Paths.get(args[0]);
        Files.createDirectories(outDir);
        String selector = args[1];
        String base = currentProgram.getName();

        writeListing(outDir, base);
        writeDecompiledC(outDir, base, resolveFunction(selector));
    }

    private void writeListing(Path outDir, String base) throws Exception {
        Path listingPath = outDir.resolve(base + ".listing.txt");
        Listing listing = currentProgram.getListing();
        try (PrintWriter out = new PrintWriter(Files.newBufferedWriter(listingPath))) {
            CodeUnitIterator units = listing.getCodeUnits(true);
            while (units.hasNext() && !monitor.isCancelled()) {
                CodeUnit cu = units.next();
                out.printf("%s  %s%n", cu.getAddress(), cu.toString());
            }
        }
        println("Wrote listing: " + listingPath);
    }

    private Function resolveFunction(String selector) {
        Function target;
        if (selector.startsWith("0x") || selector.startsWith("0X")) {
            Address addr = currentProgram.getAddressFactory().getAddress(selector);
            if (addr == null) {
                throw new IllegalArgumentException("Could not parse address: " + selector);
            }
            target = currentProgram.getFunctionManager().getFunctionAt(addr);
            if (target == null) {
                target = currentProgram.getFunctionManager().getFunctionContaining(addr);
            }
        }
        else {
            target = null;
            Iterator<Function> it = currentProgram.getFunctionManager().getFunctions(true);
            while (it.hasNext()) {
                Function f = it.next();
                if (f.getName().equals(selector)) {
                    target = f;
                    break;
                }
            }
        }
        if (target == null) {
            throw new IllegalArgumentException("Function not found: " + selector);
        }
        return target;
    }

    private static final int DECOMPILE_TIMEOUT_SECS = 60;

    private void writeDecompiledC(Path outDir, String base, Function target) throws Exception {
        DecompInterface decomp = new DecompInterface();
        try {
            decomp.setOptions(new DecompileOptions());
            if (!decomp.openProgram(currentProgram)) {
                throw new RuntimeException("Decompiler failed to open program: " + decomp.getLastMessage());
            }
            DecompileResults results =
                decomp.decompileFunction(target, DECOMPILE_TIMEOUT_SECS, new ConsoleTaskMonitor());
            Path cPath = outDir.resolve(base + "." + target.getName() + ".c");
            String code;
            if (results.decompileCompleted()) {
                code = results.getDecompiledFunction().getC();
            }
            else {
                code = "// decompile failed for " + target.getName() + ": " + results.getErrorMessage();
            }
            Files.writeString(cPath, code);
            println("Wrote decompiled C: " + cPath);
        }
        finally {
            decomp.dispose();
        }
    }
}
