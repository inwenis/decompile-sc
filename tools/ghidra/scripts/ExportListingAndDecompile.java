// Headless post-script: decompiles one function to C and (optionally) exports a full
// disassembly listing, writing both to text files under an output directory. Function is
// selected by exact name or by a 0x-prefixed hex address (address form is for stripped
// binaries with no symbol, e.g. a StarCraft 1.16.1 target function).
//
// On ANY failure (function not found, ambiguous name, decompile failure/timeout) this script
// throws and writes NOTHING -- no partial .c file, no manifest. The manifest file
// (.ghidra-analyze-manifest.properties) is the run's single freshness signal: analyze.ps1
// deletes any stale one before invoking analyzeHeadless and requires a new one with
// status=OK afterwards, specifically because analyzeHeadless can exit 0 even when this script
// throws (it logs "REPORT SCRIPT ERROR" and carries on) -- a leftover .c from a PRIOR run must
// never be mistaken for this run's result.
//
// Script args (see analyzeHeadless -postScript):
//   1: output directory (created if missing)
//   2: function selector -- exact function name, or 0xHHHHHHHH address
//   3: optional -- "true" to skip the full listing export (default "false")
//   4: optional -- decompile timeout in seconds (default 60)
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
import java.util.List;
import java.util.stream.Collectors;

public class ExportListingAndDecompile extends GhidraScript {

    private static final int DEFAULT_DECOMPILE_TIMEOUT_SECS = 60;
    private static final String MANIFEST_NAME = ".ghidra-analyze-manifest.properties";

    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length < 2) {
            throw new IllegalArgumentException(
                "usage: ExportListingAndDecompile.java <outDir> <functionNameOr0xAddress> [skipListing] [timeoutSecs]");
        }
        Path outDir = Paths.get(args[0]);
        Files.createDirectories(outDir);
        String selector = args[1];
        boolean skipListing = args.length >= 3 && Boolean.parseBoolean(args[2]);
        int timeoutSecs = args.length >= 4 ? Integer.parseInt(args[3]) : DEFAULT_DECOMPILE_TIMEOUT_SECS;
        String base = currentProgram.getName();

        Resolved resolved = resolveFunction(selector);
        println("Resolved '" + selector + "' -> " + resolved.function.getName()
            + " @ " + resolved.function.getEntryPoint() + " (" + resolved.via + ")");

        String code = decompile(resolved.function, timeoutSecs);
        String cFileName = base + "." + resolved.function.getName() + ".c";
        Files.writeString(outDir.resolve(cFileName), code);
        println("Wrote decompiled C: " + outDir.resolve(cFileName));

        String listingFileName = "SKIPPED";
        if (!skipListing) {
            listingFileName = base + ".listing.txt";
            writeListing(outDir.resolve(listingFileName));
            println("Wrote listing: " + outDir.resolve(listingFileName));
        }

        writeManifest(outDir, selector, resolved, cFileName, listingFileName);
    }

    private static class Resolved {
        final Function function;
        final String via; // "exact-address" | "containing-address" | "name"
        Resolved(Function function, String via) { this.function = function; this.via = via; }
    }

    private Resolved resolveFunction(String selector) {
        if (selector.startsWith("0x") || selector.startsWith("0X")) {
            Address addr = currentProgram.getAddressFactory().getAddress(selector);
            if (addr == null) {
                throw new IllegalArgumentException("Could not parse address: " + selector);
            }
            Function exact = currentProgram.getFunctionManager().getFunctionAt(addr);
            if (exact != null) {
                return new Resolved(exact, "exact-address");
            }
            Function containing = currentProgram.getFunctionManager().getFunctionContaining(addr);
            if (containing == null) {
                throw new IllegalArgumentException("No function at or containing address: " + selector);
            }
            println("WARNING: " + selector + " is not a function entry point; resolved to the "
                + "ENCLOSING function " + containing.getName() + " @ " + containing.getEntryPoint()
                + " instead. Verify this is the intended function before trusting the output.");
            return new Resolved(containing, "containing-address");
        }

        List<Function> matches = currentProgram.getListing().getGlobalFunctions(selector);
        if (matches.isEmpty()) {
            throw new IllegalArgumentException("Function not found: " + selector);
        }
        if (matches.size() > 1) {
            String addrs = matches.stream().map(f -> f.getEntryPoint().toString())
                .collect(Collectors.joining(", "));
            throw new IllegalArgumentException("Ambiguous function name '" + selector + "' -- "
                + matches.size() + " matches at: " + addrs + ". Re-run with -FunctionAddress instead.");
        }
        return new Resolved(matches.get(0), "name");
    }

    private String decompile(Function target, int timeoutSecs) throws Exception {
        DecompInterface decomp = new DecompInterface();
        try {
            decomp.setOptions(new DecompileOptions());
            if (!decomp.openProgram(currentProgram)) {
                throw new RuntimeException("Decompiler failed to open program: " + decomp.getLastMessage());
            }
            DecompileResults results =
                decomp.decompileFunction(target, timeoutSecs, new ConsoleTaskMonitor());
            if (!results.decompileCompleted()) {
                throw new RuntimeException(
                    "Decompile failed for " + target.getName() + ": " + results.getErrorMessage());
            }
            return results.getDecompiledFunction().getC();
        }
        finally {
            decomp.dispose();
        }
    }

    private void writeListing(Path listingPath) throws Exception {
        Listing listing = currentProgram.getListing();
        try (PrintWriter out = new PrintWriter(Files.newBufferedWriter(listingPath))) {
            CodeUnitIterator units = listing.getCodeUnits(true);
            while (units.hasNext() && !monitor.isCancelled()) {
                CodeUnit cu = units.next();
                out.printf("%s  %s%n", cu.getAddress(), cu.toString());
            }
        }
    }

    private void writeManifest(Path outDir, String selector, Resolved resolved, String cFileName,
            String listingFileName) throws Exception {
        Path manifestPath = outDir.resolve(MANIFEST_NAME);
        List<String> lines = List.of(
            "status=OK",
            "selector=" + selector,
            "resolvedFunctionName=" + resolved.function.getName(),
            "resolvedEntry=" + resolved.function.getEntryPoint(),
            "resolvedVia=" + resolved.via,
            "cFile=" + cFileName,
            "listingFile=" + listingFileName
        );
        Files.write(manifestPath, lines);
        println("Wrote manifest: " + manifestPath);
    }
}
