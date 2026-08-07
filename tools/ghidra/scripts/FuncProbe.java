// Validates INHERITED function addresses against the binary.
//
// Every function address in research/selection-cap.md comes from a public project's source
// comment, not from this binary. Before any of them is used, the first question is the cheap
// one: is that address a function ENTRY POINT in StarCraft.exe at all? An address that lands
// mid-function, or in data, or outside any function, is a finding -- either the prior art is
// wrong or it is expressed against a different base.
//
// Per spec address this emits: whether it is an exact entry point, the enclosing function if
// not, the function's extent, instruction count, caller count and first instruction.
//
// Script args:
//   1: output TSV path (<path>.manifest is the run's success signal)
//   2: spec file -- one address per line: label,addrHex
//
//@category Headless

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.listing.InstructionIterator;
import ghidra.program.model.mem.MemoryBlock;
import ghidra.program.model.symbol.Reference;
import ghidra.program.model.symbol.ReferenceIterator;

import java.io.PrintWriter;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.List;

public class FuncProbe extends GhidraScript {

    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length < 2) {
            throw new IllegalArgumentException("usage: FuncProbe.java <outTsv> <specFile>");
        }
        String outPath = args[0];
        List<SweepUtil.Spec> specs = SweepUtil.readSpec(args[1]);

        Path out = Paths.get(outPath);
        if (out.toAbsolutePath().getParent() != null) {
            Files.createDirectories(out.toAbsolutePath().getParent());
        }

        long rows = 0;
        try (PrintWriter w = new PrintWriter(Files.newBufferedWriter(out))) {
            w.println(String.join("\t", "label", "specAddr", "block", "verdict", "funcName",
                "funcEntry", "bodyMin", "bodyMax", "bodyBytes", "instructions", "callers",
                "callingConvention", "firstInstruction"));

            for (SweepUtil.Spec s : specs) {
                Address a = addr(s.hex(0));
                MemoryBlock blk = currentProgram.getMemory().getBlock(a);
                Function exact = currentProgram.getFunctionManager().getFunctionAt(a);
                Function containing = exact != null ? exact
                    : currentProgram.getFunctionManager().getFunctionContaining(a);

                String verdict;
                if (exact != null) {
                    verdict = "ENTRY-POINT";
                }
                else if (containing != null) {
                    verdict = "INSIDE-FUNCTION";
                }
                else if (currentProgram.getListing().getInstructionContaining(a) != null) {
                    verdict = "CODE-NO-FUNCTION";
                }
                else {
                    verdict = "NOT-CODE";
                }

                long insCount = 0;
                String first = "";
                if (containing != null) {
                    InstructionIterator it =
                        currentProgram.getListing().getInstructions(containing.getBody(), true);
                    while (it.hasNext()) {
                        Instruction ins = it.next();
                        if (insCount == 0) {
                            first = SweepUtil.cell(ins);
                        }
                        insCount++;
                    }
                }

                int callers = 0;
                if (containing != null) {
                    ReferenceIterator rit = currentProgram.getReferenceManager()
                        .getReferencesTo(containing.getEntryPoint());
                    while (rit.hasNext()) {
                        Reference r = rit.next();
                        if (r.getReferenceType().isCall()) {
                            callers++;
                        }
                    }
                }

                w.println(String.join("\t",
                    s.label,
                    SweepUtil.hex(a.getOffset()),
                    blk == null ? "" : blk.getName(),
                    verdict,
                    containing == null ? "" : containing.getName(),
                    containing == null ? "" : SweepUtil.hex(containing.getEntryPoint().getOffset()),
                    containing == null ? "" : SweepUtil.hex(containing.getBody().getMinAddress().getOffset()),
                    containing == null ? "" : SweepUtil.hex(containing.getBody().getMaxAddress().getOffset()),
                    containing == null ? "" : Long.toString(containing.getBody().getNumAddresses()),
                    Long.toString(insCount),
                    Integer.toString(callers),
                    containing == null ? "" : containing.getCallingConventionName(),
                    first));
                rows++;
            }
        }

        println("FuncProbe: wrote " + rows + " rows -> " + out.toAbsolutePath());
        SweepUtil.writeManifest(outPath, rows, null);
    }

    private Address addr(long offset) {
        return currentProgram.getAddressFactory().getDefaultAddressSpace().getAddress(offset);
    }
}
