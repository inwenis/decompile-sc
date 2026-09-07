// Cross-reference sweep over ADDRESS RANGES, not single addresses.
//
// The selection globals are arrays: an instruction touching playersSelections[3][7] references
// 0x00628634, not the array base 0x006284E8, so a getReferencesTo(base) sweep misses most of the
// work -- hence every byte of every swept range is queried.
//
// Two passes, because neither alone is complete. Pass 1 (GHIDRA-REF) knows the containing
// function and the reference type, but is only as complete as the auto-analysis: code Ghidra
// never disassembled contributes nothing. Pass 2 (RAW-DWORD) finds the encoded absolute address
// even there; classifying each hit COVERED / UNCOVERED against pass 1 makes the UNCOVERED rows
// exactly pass 1's blind spots -- a completeness claim that is measured, not assumed.
//
// Args: 1 = output TSV (pass 2 -> <path>.rawhits.tsv, <path>.manifest signals success),
//       2 = spec file, one range per line: label,startHex,byteLength
//@category Headless

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.address.AddressSet;
import ghidra.program.model.listing.CodeUnit;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.listing.Listing;
import ghidra.program.model.mem.MemoryBlock;
import ghidra.program.model.symbol.Reference;
import ghidra.program.model.symbol.ReferenceIterator;
import ghidra.program.model.symbol.ReferenceManager;

import java.io.PrintWriter;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

public class XrefSweep extends GhidraScript {

    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length < 2) {
            throw new IllegalArgumentException("usage: XrefSweep.java <outTsv> <specFile>");
        }
        String outPath = args[0];
        List<SweepUtil.Spec> specs = SweepUtil.readSpec(args[1]);

        Path out = Paths.get(outPath);
        if (out.toAbsolutePath().getParent() != null) {
            Files.createDirectories(out.toAbsolutePath().getParent());
        }

        Listing listing = currentProgram.getListing();
        ReferenceManager refs = currentProgram.getReferenceManager();

        // Code-unit addresses that referenced a swept range: a pass-2 hit here is COVERED.
        Set<Address> refProducers = new HashSet<>();
        long rows = 0;

        try (PrintWriter w = new PrintWriter(Files.newBufferedWriter(out))) {
            w.println(String.join("\t", "label", "targetAddr", "byteOffset", "elemIndex",
                "fromAddr", "refType", "opIndex", "isPrimary", "funcEntry", "funcName", "instruction"));

            for (SweepUtil.Spec s : specs) {
                long start = s.hex(0);
                long len = s.dec(1);
                for (long off = 0; off < len; off++) {
                    Address target = addr(start + off);
                    ReferenceIterator it = refs.getReferencesTo(target);
                    while (it.hasNext()) {
                        Reference r = it.next();
                        Address from = r.getFromAddress();
                        Function f = currentProgram.getFunctionManager().getFunctionContaining(from);
                        Instruction ins = listing.getInstructionAt(from);
                        CodeUnit cu = listing.getCodeUnitContaining(from);
                        refProducers.add(from);
                        if (cu != null) {
                            refProducers.add(cu.getMinAddress());
                        }
                        w.println(String.join("\t",
                            s.label,
                            SweepUtil.hex(target.getOffset()),
                            Long.toString(off),
                            Long.toString(off / 4),
                            SweepUtil.hex(from.getOffset()),
                            r.getReferenceType().getName(),
                            Integer.toString(r.getOperandIndex()),
                            Boolean.toString(r.isPrimary()),
                            f == null ? "" : SweepUtil.hex(f.getEntryPoint().getOffset()),
                            f == null ? "(none)" : f.getName(),
                            ins == null ? SweepUtil.cell(cu) : SweepUtil.cell(ins)));
                        rows++;
                    }
                }
            }
        }
        println("XrefSweep: pass 1 wrote " + rows + " Ghidra references -> " + out.toAbsolutePath());

        long rawRows = rawScan(outPath + ".rawhits.tsv", specs, refProducers);

        SweepUtil.writeManifest(outPath, rows, List.of(
            "rawHits=" + rawRows,
            "rawHitsFile=" + (outPath + ".rawhits.tsv").replace("\\", "/")));
    }

    /**
     * Scans at EVERY byte offset, unaligned included: an x86 absolute displacement is rarely
     * 4-byte aligned within its instruction.
     */
    private long rawScan(String rawPath, List<SweepUtil.Spec> specs, Set<Address> refProducers)
            throws Exception {
        Path p = Paths.get(rawPath);
        Listing listing = currentProgram.getListing();
        long hits = 0;

        try (PrintWriter w = new PrintWriter(Files.newBufferedWriter(p))) {
            w.println(String.join("\t", "label", "encodedValue", "byteOffsetInRange", "atAddr",
                "block", "coverage", "codeUnitAddr", "funcEntry", "funcName", "codeUnit"));

            for (MemoryBlock b : currentProgram.getMemory().getBlocks()) {
                if (!b.isInitialized()) {
                    continue;
                }
                int size = (int) Math.min(b.getSize(), Integer.MAX_VALUE);
                byte[] buf = new byte[size];
                b.getBytes(b.getStart(), buf);
                long base = b.getStart().getOffset();

                for (int i = 0; i + 3 < size; i++) {
                    long v = (buf[i] & 0xFFL)
                        | ((buf[i + 1] & 0xFFL) << 8)
                        | ((buf[i + 2] & 0xFFL) << 16)
                        | ((buf[i + 3] & 0xFFL) << 24);
                    for (SweepUtil.Spec s : specs) {
                        long start = s.hex(0);
                        long len = s.dec(1);
                        if (v < start || v >= start + len) {
                            continue;
                        }
                        Address at = addr(base + i);
                        CodeUnit cu = listing.getCodeUnitContaining(at);
                        Address cuAddr = cu == null ? null : cu.getMinAddress();
                        boolean covered = refProducers.contains(at)
                            || (cuAddr != null && refProducers.contains(cuAddr));
                        Function f = currentProgram.getFunctionManager().getFunctionContaining(at);
                        w.println(String.join("\t",
                            s.label,
                            SweepUtil.hex(v),
                            Long.toString(v - start),
                            SweepUtil.hex(at.getOffset()),
                            b.getName(),
                            covered ? "COVERED" : "UNCOVERED",
                            cuAddr == null ? "" : SweepUtil.hex(cuAddr.getOffset()),
                            f == null ? "" : SweepUtil.hex(f.getEntryPoint().getOffset()),
                            f == null ? "(none)" : f.getName(),
                            SweepUtil.cell(cu)));
                        hits++;
                    }
                }
            }
        }
        println("XrefSweep: pass 2 wrote " + hits + " raw dword hits -> " + p.toAbsolutePath());
        return hits;
    }

    private Address addr(long offset) {
        return currentProgram.getAddressFactory().getDefaultAddressSpace().getAddress(offset);
    }
}
