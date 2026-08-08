// Finds every instruction that CALLs (or reads for a call) through a given struct
// displacement -- e.g. `CALL dword ptr [reg + 0x2A]`, the BinDlg fxnInteract slot.
// A struct field has no address, so XrefSweep cannot see it; this is FieldSweep's
// idea narrowed to indirect-call operands, which is what routes dialog events.
//
// Output rows are raw disassembly of a game binary (derived content, scratch only).
//
// Script args:
//   1: output TSV path (<path>.manifest is the run's success signal)
//   2: displacement hex (no 0x), e.g. 2A
//
//@category Headless

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.listing.InstructionIterator;

import java.io.PrintWriter;
import java.nio.file.Files;
import java.nio.file.Paths;

public class CallDispSweep extends GhidraScript {

    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length < 2) {
            throw new IllegalArgumentException("usage: CallDispSweep.java <outTsv> <dispHex>");
        }
        String outPath = args[0];
        String disp = args[1].toLowerCase().replace("0x", "");

        Files.createDirectories(Paths.get(outPath).toAbsolutePath().getParent());
        long rows = 0;
        String needle = "0x" + disp + "]";

        try (PrintWriter w = new PrintWriter(Files.newBufferedWriter(Paths.get(outPath)))) {
            w.println(String.join("\t", "addr", "mnemonic", "func", "funcEntry", "instruction"));
            InstructionIterator it = currentProgram.getListing().getInstructions(true);
            while (it.hasNext()) {
                Instruction ins = it.next();
                String m = ins.getMnemonicString();
                if (!(m.equals("CALL") || m.equals("JMP") || m.startsWith("MOV") || m.startsWith("LEA"))) continue;
                String text = ins.toString();
                // Match an operand of the form [reg + 0x<disp>] (with the ']' right after).
                if (!text.contains("+ " + needle) && !text.contains("+" + needle)) continue;
                // Only indirect through a register base (skip absolute [0x......]).
                Address a = ins.getAddress();
                Function f = currentProgram.getFunctionManager().getFunctionContaining(a);
                w.println(String.join("\t",
                    SweepUtil.hex(a.getOffset()), m,
                    f == null ? "(none)" : f.getName(),
                    f == null ? "" : SweepUtil.hex(f.getEntryPoint().getOffset()),
                    text));
                rows++;
            }
        }
        SweepUtil.writeManifest(outPath, rows, null);
    }
}
