// Recovers code that auto-analysis left undefined, then re-analyzes.
//
// Ghidra's auto-analysis found 5008 functions in StarCraft.exe but left blocks of real,
// reachable-only-indirectly code as raw bytes -- including ~20 sites that load the selection
// globals into a register (`MOV ECX,0x597208` and friends). Those sites are relocation work and
// must appear in the cross-reference table, so the code has to be defined before Ghidra can
// attribute them to a function.
//
// For each seed address this walks BACK over 0xCC (int3) alignment filler to find the likely
// function entry -- MSVC pads between functions with int3, so the first byte after a filler run
// is an entry candidate -- then disassembles and creates a function there. Afterwards it runs
// auto-analysis again so the reference and function-start analyzers see the newly defined code.
//
// This MUTATES the program database. That is fine and intended here: the project is a
// throwaway under work/scratch/ (gitignored), rebuilt from the binary in ~3 minutes. Anything
// this script gets wrong is visible as a bogus function in the re-run sweep, not as a silent
// corruption of a committed result -- every finding in research/binary-selection-map.md is
// carried independently by the raw-dword scan, which never depends on disassembly at all.
//
// Script args:
//   1: output TSV path (<path>.manifest is the run's success signal)
//   2: spec file -- one seed per line: label,addrHex
//   3: optional -- "true" to re-run auto-analysis afterwards (default true)
//
//@category Headless

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Instruction;

import java.io.PrintWriter;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.List;

public class DisassembleAt extends GhidraScript {

    private static final int MAX_WALK_BACK = 512;

    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length < 2) {
            throw new IllegalArgumentException(
                "usage: DisassembleAt.java <outTsv> <specFile> [reanalyze]");
        }
        String outPath = args[0];
        List<SweepUtil.Spec> specs = SweepUtil.readSpec(args[1]);
        boolean reanalyze = args.length < 3 || Boolean.parseBoolean(args[2]);

        Path out = Paths.get(outPath);
        if (out.toAbsolutePath().getParent() != null) {
            Files.createDirectories(out.toAbsolutePath().getParent());
        }

        int before = currentProgram.getFunctionManager().getFunctionCount();
        long rows = 0;

        try (PrintWriter w = new PrintWriter(Files.newBufferedWriter(out))) {
            w.println(String.join("\t", "label", "seedAddr", "entryCandidate", "action",
                "resultFunction", "resultEntry", "firstInstruction"));

            for (SweepUtil.Spec s : specs) {
                Address seed = addr(s.hex(0));
                Address entry = walkBackToEntry(seed);
                String action;

                Instruction existing = currentProgram.getListing().getInstructionContaining(seed);
                if (existing != null) {
                    action = "already-code";
                }
                else {
                    boolean ok = disassemble(entry);
                    action = ok ? "disassembled" : "disassemble-failed";
                    if (ok && currentProgram.getFunctionManager().getFunctionAt(entry) == null) {
                        try {
                            Function created = createFunction(entry, null);
                            action += created != null ? "+function" : "+function-failed";
                        }
                        catch (Exception e) {
                            action += "+function-error";
                        }
                    }
                }

                Function f = currentProgram.getFunctionManager().getFunctionContaining(seed);
                Instruction ins = currentProgram.getListing().getInstructionAt(entry);
                w.println(String.join("\t",
                    s.label,
                    SweepUtil.hex(seed.getOffset()),
                    SweepUtil.hex(entry.getOffset()),
                    action,
                    f == null ? "(none)" : f.getName(),
                    f == null ? "" : SweepUtil.hex(f.getEntryPoint().getOffset()),
                    ins == null ? "" : SweepUtil.cell(ins)));
                rows++;
            }
        }

        if (reanalyze) {
            println("DisassembleAt: re-running auto-analysis over newly defined code...");
            analyzeAll(currentProgram);
        }
        int after = currentProgram.getFunctionManager().getFunctionCount();
        println("DisassembleAt: functions " + before + " -> " + after);

        SweepUtil.writeManifest(outPath, rows, List.of(
            "functionsBefore=" + before,
            "functionsAfter=" + after,
            "reanalyzed=" + reanalyze));
    }

    /**
     * MSVC pads between functions with 0xCC (int3). Walk back to the first byte after the
     * nearest filler run; that is the entry candidate. Stops at defined code/data or after
     * MAX_WALK_BACK bytes, in which case the seed itself is used.
     */
    private Address walkBackToEntry(Address seed) throws Exception {
        long a = seed.getOffset();
        for (int i = 0; i < MAX_WALK_BACK; i++) {
            Address prev = addr(a - 1);
            if (currentProgram.getMemory().getBlock(prev) == null) {
                return addr(a);
            }
            if (currentProgram.getListing().getCodeUnitAt(prev) != null
                && currentProgram.getListing().getInstructionAt(prev) != null) {
                return addr(a);
            }
            byte b;
            try {
                b = currentProgram.getMemory().getByte(prev);
            }
            catch (Exception e) {
                return addr(a);
            }
            if ((b & 0xFF) == 0xCC) {
                return addr(a);
            }
            a--;
        }
        return seed;
    }

    private Address addr(long offset) {
        return currentProgram.getAddressFactory().getDefaultAddressSpace().getAddress(offset);
    }
}
