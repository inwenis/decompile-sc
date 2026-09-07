// Dumps the disassembly listing for a raw address RANGE, function or no function.
//
// Exists because ExportListingAndDecompile needs a function selector and DecompileMany
// resolves through the function manager -- neither can show code that Ghidra defined as
// instructions but never attributed to any function body (e.g. switch-case tails reached
// only through a jump table). 0x004583DC-0x004584A0 is such a range: instructions between
// the end of statusScreenButton's body and the next function entry, inside no function.
//
// Output rows are raw disassembly of a game binary -- DERIVED GAME CONTENT, scratch only
// (same rule as DecompileMany's .c files).
//
// <outTsv>.manifest is the run's success signal.
//
//@category Headless

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.CodeUnit;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Listing;

import java.io.PrintWriter;
import java.nio.file.Files;
import java.nio.file.Paths;

public class ListingDump extends GhidraScript {

    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length < 3) {
            throw new IllegalArgumentException("usage: ListingDump.java <outTsv> <startHex> <endHex>");
        }
        String outPath = args[0];
        long start = Long.parseLong(args[1].replace("0x", ""), 16);
        long end = Long.parseLong(args[2].replace("0x", ""), 16);

        Files.createDirectories(Paths.get(outPath).toAbsolutePath().getParent());
        Listing listing = currentProgram.getListing();
        long rows = 0;
        try (PrintWriter w = new PrintWriter(Files.newBufferedWriter(Paths.get(outPath)))) {
            w.println(String.join("\t", "addr", "bytes", "instruction", "containingFunc"));
            Address a = toAddr(start);
            Address stop = toAddr(end);
            while (a.compareTo(stop) < 0) {
                CodeUnit cu = listing.getCodeUnitAt(a);
                if (cu == null) {
                    cu = listing.getCodeUnitContaining(a);
                    if (cu == null) break;
                }
                StringBuilder bytes = new StringBuilder();
                for (byte b : cu.getBytes()) {
                    bytes.append(String.format("%02X ", b));
                }
                Function f = currentProgram.getFunctionManager().getFunctionContaining(cu.getAddress());
                w.println(String.join("\t",
                    SweepUtil.hex(cu.getAddress().getOffset()),
                    bytes.toString().trim(),
                    cu.toString(),
                    f == null ? "(none)" : f.getName()));
                rows++;
                a = cu.getAddress().add(cu.getLength());
            }
        }
        SweepUtil.writeManifest(outPath, rows, null);
    }
}
