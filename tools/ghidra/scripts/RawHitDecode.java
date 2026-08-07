// Decodes the instruction behind a raw-dword hit that Ghidra's own reference analysis missed.
//
// Why this exists: XrefSweep pass 1 trusts Ghidra's Reference database, and that database has a
// demonstrable blind spot on this binary. At 0x004C26B6 the instruction
// `MOV dword ptr [EDX*0x4 + 0x6284e8],ESI` writes into playersSelections and Ghidra recorded NO
// reference for it -- scaled-index absolute addressing, i.e. precisely the array-indexing form
// that matters most when relocating an array. A reference table built from pass 1 alone would
// silently omit that class of instruction and still look complete.
//
// So: pass 2's raw dword hits are decoded here. For each hit address P (the position of the
// encoded absolute address inside some instruction) this walks candidate instruction starts
// P-1..P-<maxBack> and pseudo-disassembles each. A candidate is accepted when the decoded
// instruction actually covers P. PseudoDisassembler is used rather than disassemble() on
// purpose -- it decodes without writing anything into the program database, so a wrong guess
// cannot corrupt the analysis that every other query in this sweep depends on.
//
// Reported per hit: whether real code already exists there, the decoded candidate, and a hex
// window so any decode can be checked by hand.
//
// Script args:
//   1: output TSV path (<path>.manifest is the run's success signal)
//   2: spec file -- one hit per line: label,addrHex[,expectedValueHex]
//   3: optional -- max bytes to walk back looking for the instruction start (default 8)
//
//@category Headless

import ghidra.app.script.GhidraScript;
import ghidra.app.util.PseudoDisassembler;
import ghidra.app.util.PseudoInstruction;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.CodeUnit;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.mem.MemoryBlock;

import java.io.PrintWriter;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.List;

public class RawHitDecode extends GhidraScript {

    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length < 2) {
            throw new IllegalArgumentException(
                "usage: RawHitDecode.java <outTsv> <specFile> [maxBack]");
        }
        String outPath = args[0];
        List<SweepUtil.Spec> specs = SweepUtil.readSpec(args[1]);
        int maxBack = args.length >= 3 ? Integer.parseInt(args[2]) : 8;

        Path out = Paths.get(outPath);
        if (out.toAbsolutePath().getParent() != null) {
            Files.createDirectories(out.toAbsolutePath().getParent());
        }

        PseudoDisassembler pd = new PseudoDisassembler(currentProgram);
        long rows = 0;

        try (PrintWriter w = new PrintWriter(Files.newBufferedWriter(out))) {
            w.println(String.join("\t", "label", "hitAddr", "block", "existingCodeUnit",
                "funcEntry", "funcName", "decodeStart", "decodeLen", "covers", "decoded",
                "hexWindow"));

            for (SweepUtil.Spec s : specs) {
                Address hit = addr(s.hex(0));
                MemoryBlock blk = currentProgram.getMemory().getBlock(hit);

                Instruction existing = currentProgram.getListing().getInstructionContaining(hit);
                CodeUnit cu = currentProgram.getListing().getCodeUnitContaining(hit);
                Function f = currentProgram.getFunctionManager().getFunctionContaining(hit);

                String decodeStart = "";
                String decodeLen = "";
                String covers = "";
                String decoded = "";

                if (existing != null) {
                    decodeStart = SweepUtil.hex(existing.getAddress().getOffset());
                    decodeLen = Integer.toString(existing.getLength());
                    covers = "true";
                    decoded = SweepUtil.cell(existing);
                }
                else {
                    // Report EVERY candidate start that decodes to an instruction spanning the
                    // encoded dword, not just the first. Taking the first (smallest back-step)
                    // is actively wrong: at 0x0048DCD2 the byte one before the hit is 0x05, so
                    // back=1 decodes a spurious `ADD EAX,0x6284b6` that happens to span the
                    // dword, while the real instruction starts at back=2
                    // (`C6 05 B6846200 00` = MOV byte ptr [0x6284B6],0x0). Longer candidates are
                    // listed first because a longer opcode prefix is the likelier true start,
                    // but the caller is expected to confirm against the hex window.
                    StringBuilder cands = new StringBuilder();
                    int found = 0;
                    for (int back = maxBack; back >= 1; back--) {
                        Address cand = addr(hit.getOffset() - back);
                        PseudoInstruction pi;
                        try {
                            pi = pd.disassemble(cand);
                        }
                        catch (Exception e) {
                            continue;
                        }
                        if (pi == null) {
                            continue;
                        }
                        long end = cand.getOffset() + pi.getLength() - 1;
                        // Require the decoded instruction to span the whole encoded dword, not
                        // just its first byte -- otherwise a 2-byte decode "covering" P is noise.
                        if (end < hit.getOffset() + 3) {
                            continue;
                        }
                        if (found == 0) {
                            decodeStart = SweepUtil.hex(cand.getOffset());
                            decodeLen = Integer.toString(pi.getLength());
                        }
                        if (cands.length() > 0) {
                            cands.append("  ||  ");
                        }
                        cands.append("-").append(back).append(": ").append(SweepUtil.cell(pi));
                        found++;
                    }
                    if (found == 0) {
                        covers = "false";
                        decoded = "(no candidate start in " + maxBack + " bytes decoded an "
                            + "instruction spanning the encoded dword)";
                    }
                    else {
                        covers = "true(" + found + " candidates)";
                        decoded = cands.toString();
                    }
                }

                w.println(String.join("\t",
                    s.label,
                    SweepUtil.hex(hit.getOffset()),
                    blk == null ? "" : blk.getName(),
                    existing != null ? "instruction" : (cu == null ? "(none)" : SweepUtil.cell(cu)),
                    f == null ? "" : SweepUtil.hex(f.getEntryPoint().getOffset()),
                    f == null ? "(none)" : f.getName(),
                    decodeStart,
                    decodeLen,
                    covers,
                    decoded,
                    hexWindow(hit, 8, 12)));
                rows++;
            }
        }

        println("RawHitDecode: wrote " + rows + " rows -> " + out.toAbsolutePath());
        SweepUtil.writeManifest(outPath, rows, null);
    }

    /** Hex dump of [addr-before, addr+after], with '|' marking the hit byte. */
    private String hexWindow(Address a, int before, int after) {
        StringBuilder sb = new StringBuilder();
        for (long i = -before; i <= after; i++) {
            try {
                byte b = currentProgram.getMemory().getByte(addr(a.getOffset() + i));
                if (i == 0) {
                    sb.append('|');
                }
                sb.append(String.format("%02X", b & 0xFF));
                if (i == 3) {
                    sb.append('|');
                }
                sb.append(' ');
            }
            catch (Exception e) {
                sb.append(".. ");
            }
        }
        return sb.toString().trim();
    }

    private Address addr(long offset) {
        return currentProgram.getAddressFactory().getDefaultAddressSpace().getAddress(offset);
    }
}
