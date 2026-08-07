// Byte-level probe of an address range: what is actually THERE.
//
// Built for the adjacency question -- "does clientSelectionGroup have slack behind it, or is it
// hard against a named neighbour?" cannot be answered by arithmetic on quoted addresses (that
// argument is circular; see research/selection-cap.md §2.3's own note). It is answered by
// looking at every byte between the arrays and asking whether any instruction in the binary
// reaches it.
//
// Per address in range this emits: the raw byte, the defined data item at or containing it,
// any symbol, and how many references reach it plus the first few referencing instructions.
// An address with zero references anywhere in a 1.2 MB binary is genuinely unused space; an
// address with references is an occupied neighbour, whatever the public offset maps call it.
//
// Script args:
//   1: output TSV path (<path>.manifest is the run's success signal)
//   2: spec file -- one range per line: label,startHex,byteLength
//   3: optional -- max referencing instructions to list per address (default 6)
//
//@category Headless

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Data;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.listing.Listing;
import ghidra.program.model.mem.MemoryBlock;
import ghidra.program.model.symbol.Reference;
import ghidra.program.model.symbol.ReferenceIterator;
import ghidra.program.model.symbol.Symbol;

import java.io.PrintWriter;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.List;

public class RegionProbe extends GhidraScript {

    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length < 2) {
            throw new IllegalArgumentException(
                "usage: RegionProbe.java <outTsv> <specFile> [maxRefsListed]");
        }
        String outPath = args[0];
        List<SweepUtil.Spec> specs = SweepUtil.readSpec(args[1]);
        int maxRefs = args.length >= 3 ? Integer.parseInt(args[2]) : 6;

        Path out = Paths.get(outPath);
        if (out.toAbsolutePath().getParent() != null) {
            Files.createDirectories(out.toAbsolutePath().getParent());
        }

        Listing listing = currentProgram.getListing();
        long rows = 0;

        try (PrintWriter w = new PrintWriter(Files.newBufferedWriter(out))) {
            w.println(String.join("\t", "label", "addr", "offsetInRange", "byte", "block",
                "dataAt", "dataContaining", "containingStart", "symbols", "refCount", "referrers"));

            for (SweepUtil.Spec s : specs) {
                long start = s.hex(0);
                long len = s.dec(1);
                for (long off = 0; off < len; off++) {
                    Address a = addr(start + off);
                    MemoryBlock blk = currentProgram.getMemory().getBlock(a);
                    String byteStr;
                    try {
                        byteStr = String.format("%02X", currentProgram.getMemory().getByte(a) & 0xFF);
                    }
                    catch (Exception e) {
                        byteStr = "??";
                    }

                    Data dAt = listing.getDataAt(a);
                    Data dIn = listing.getDataContaining(a);

                    StringBuilder syms = new StringBuilder();
                    for (Symbol sym : currentProgram.getSymbolTable().getSymbols(a)) {
                        if (syms.length() > 0) {
                            syms.append('|');
                        }
                        syms.append(sym.getName());
                    }

                    List<String> referrers = new ArrayList<>();
                    int refCount = 0;
                    ReferenceIterator it = currentProgram.getReferenceManager().getReferencesTo(a);
                    while (it.hasNext()) {
                        Reference r = it.next();
                        refCount++;
                        if (referrers.size() < maxRefs) {
                            Address from = r.getFromAddress();
                            Function f = currentProgram.getFunctionManager().getFunctionContaining(from);
                            Instruction ins = listing.getInstructionAt(from);
                            referrers.add(SweepUtil.hex(from.getOffset())
                                + "[" + r.getReferenceType().getName() + "]"
                                + (f == null ? "" : "{" + f.getName() + "}")
                                + (ins == null ? "" : " " + SweepUtil.cell(ins)));
                        }
                    }

                    w.println(String.join("\t",
                        s.label,
                        SweepUtil.hex(a.getOffset()),
                        Long.toString(off),
                        byteStr,
                        blk == null ? "" : blk.getName(),
                        dAt == null ? "" : SweepUtil.cell(dAt.getDataType().getName() + "(" + dAt.getLength() + ")=" + dAt.getDefaultValueRepresentation()),
                        dIn == null ? "" : SweepUtil.cell(dIn.getDataType().getName() + "(" + dIn.getLength() + ")"),
                        dIn == null ? "" : SweepUtil.hex(dIn.getMinAddress().getOffset()),
                        syms.toString(),
                        Integer.toString(refCount),
                        String.join(" ; ", referrers)));
                    rows++;
                }
            }
        }

        println("RegionProbe: wrote " + rows + " rows -> " + out.toAbsolutePath());
        SweepUtil.writeManifest(outPath, rows, null);
    }

    private Address addr(long offset) {
        return currentProgram.getAddressFactory().getDefaultAddressSpace().getAddress(offset);
    }
}
