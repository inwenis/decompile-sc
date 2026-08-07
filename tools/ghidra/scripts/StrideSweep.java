// Finds row strides that are ENCODED IN ADDRESSING ARITHMETIC rather than written as a constant.
//
// Why this script exists. The cross-reference sweep finds instructions that name a selection
// global; the immediate sweep finds instructions that contain a watched constant. An instruction
// like
//
//     0049AFB5   LEA EDX,[EDI + EDI*0x2]      ; EDX = player * 3
//     0049AFB8   LEA EAX,[EBX + EDX*0x4]      ; EAX = slot + player * 12
//     0049AFBB   MOV dword ptr [EAX*0x4 + 0x6284e8],ESI
//
// is invisible to BOTH. The first two instructions name no address and contain no watched
// constant -- the row stride of playersSelections (12 elements, 48 bytes) is carried entirely by
// the *0x2 and *0x4 scale factors. Yet every one of them must change to widen the array, so
// leaving them out understates the relocation work list, which is the whole point of the
// deliverable. Round 1 of task 005 left them out; a review caught it.
//
// Detection is a scale-factor chain, not a pattern list:
//
//   1. seed on `LEA rD,[rA + rA*0x2]` -- the compiler's x3, and the only way to get an odd
//      multiplier out of the scaled-index addressing modes.
//   2. follow rD forward inside the same function, at most MAX_HOPS uses and MAX_WINDOW
//      instructions, multiplying in each scale factor seen: `rD*0xN` in a memory operand
//      contributes N, `SHL rD,k` contributes 2^k. A LEA continues the chain in its destination
//      register; any other instruction with a memory operand ENDS it and is the consumer.
//   3. the compiler emits two shapes and both must be recognised. The INDEX shape keeps the
//      value as an element number and scales it at the point of use --
//      `LEA EDX,[ESI+ESI*2]; LEA EAX,[EDI+EDX*4]; MOV [EAX*4 + 0x6284e8],ECX`. The BYTE shape
//      converts to a byte offset early and then just adds the base --
//      `LEA EDI,[ESI+ESI*2]; SHL EDI,0x4; ADD EDI,0x6284e8`. In the second, the consumer scales
//      nothing, so it is recognised instead by naming the chain register together with an
//      absolute address that lands in a swept global.
//   4. stop early if rD is overwritten, or on a CALL (caller-saved registers).
//
// The product is the total byte multiplier of the chain. A chain of 48 bytes = 12 dwords is a
// playersSelections row step. Chains of every other multiplier are emitted too, with their
// value, so the filtering happens in the open in build-stride-table.ps1 rather than being
// baked in here.
//
// `context` says whether the containing function has any other connection to the selection
// globals: `in-spec` (named in the function spec), `refs-selection-global` (some instruction in
// it names an address inside a swept global), or `elsewhere`. x3 LEAs are common in any binary
// -- they serve every 3-, 6-, 12- and 24-byte structure -- so `elsewhere` rows are noise here
// and are counted, not committed.
//
// Script args:
//   1: output TSV path (<path>.manifest is the run's success signal)
//   2: globals spec -- label,startHex,byteLength (same file XrefSweep uses)
//   3: functions spec -- label,addrHex (same file ImmediateSweep uses)
//
//@category Headless

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionIterator;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.listing.InstructionIterator;
import ghidra.program.model.scalar.Scalar;
import ghidra.program.model.symbol.Reference;

import java.io.PrintWriter;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class StrideSweep extends GhidraScript {

    /** `LEA rD,[rA + rA*0x2]` -- the x3 seed. Group 1 = rD, group 2 = rA. */
    private static final Pattern MUL3 =
        Pattern.compile("^LEA\\s+(E[A-Z]{2}),\\[(E[A-Z]{2})\\s*\\+\\s*\\2\\*0x2\\]$");

    /** `SHL rD,k` -- a power-of-two step in the chain. */
    private static final Pattern SHL = Pattern.compile("^SHL\\s+(E[A-Z]{2}),0x([0-9a-fA-F]+)$");

    /** Any absolute address literal big enough to be a .data global. */
    private static final Pattern ABS = Pattern.compile("0x([0-9a-fA-F]{5,8})");

    private static final int MAX_WINDOW = 24;
    private static final int MAX_HOPS = 4;

    private static class Range {
        final String label;
        final long start;
        final long end; // exclusive

        Range(String label, long start, long len) {
            this.label = label;
            this.start = start;
            this.end = start + len;
        }

        boolean has(long v) {
            return v >= start && v < end;
        }
    }

    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length < 3) {
            throw new IllegalArgumentException(
                "usage: StrideSweep.java <outTsv> <globalsSpec> <functionsSpec>");
        }
        String outPath = args[0];

        List<Range> ranges = new ArrayList<>();
        for (SweepUtil.Spec s : SweepUtil.readSpec(args[1])) {
            ranges.add(new Range(s.label, s.hex(0), s.dec(1)));
        }
        Set<Long> specFuncs = new HashSet<>();
        for (SweepUtil.Spec s : SweepUtil.readSpec(args[2])) {
            specFuncs.add(s.hex(0));
        }
        println("StrideSweep: " + ranges.size() + " global ranges, " + specFuncs.size()
            + " spec functions");

        Path out = Paths.get(outPath);
        if (out.toAbsolutePath().getParent() != null) {
            Files.createDirectories(out.toAbsolutePath().getParent());
        }

        long rows = 0;
        long functions = 0;
        try (PrintWriter w = new PrintWriter(Files.newBufferedWriter(out))) {
            w.println(String.join("\t", "context", "funcEntry", "funcName", "seedAddr", "seedIns",
                "chainAddrs", "chainIns", "consumerAddr", "consumerIns", "strideBytes",
                "strideElements", "targetGlobal", "terminated"));

            FunctionIterator fit = currentProgram.getFunctionManager().getFunctions(true);
            while (fit.hasNext()) {
                Function f = fit.next();
                functions++;

                List<Instruction> body = new ArrayList<>();
                InstructionIterator it =
                    currentProgram.getListing().getInstructions(f.getBody(), true);
                while (it.hasNext()) {
                    body.add(it.next());
                }

                String context = specFuncs.contains(f.getEntryPoint().getOffset()) ? "in-spec"
                    : (touchesGlobal(body, ranges) ? "refs-selection-global" : "elsewhere");

                for (int i = 0; i < body.size(); i++) {
                    Matcher m = MUL3.matcher(SweepUtil.cell(body.get(i)));
                    if (!m.matches()) {
                        continue;
                    }
                    Chain c = follow(body, i, m.group(1), ranges);
                    w.println(String.join("\t",
                        context,
                        SweepUtil.hex(f.getEntryPoint().getOffset()),
                        f.getName(),
                        SweepUtil.hex(body.get(i).getAddress().getOffset()),
                        SweepUtil.cell(body.get(i)),
                        String.join(";", c.addrs),
                        String.join(" ; ", c.text),
                        c.consumerAddr,
                        c.consumerIns,
                        Long.toString(c.bytes),
                        c.bytes % 4 == 0 ? Long.toString(c.bytes / 4) : "",
                        globalFor(c.consumerIns, ranges),
                        c.terminated));
                    rows++;
                }
            }
        }

        // Report both counts: getFunctions() iterates functions with a body, while
        // getFunctionCount() also counts external/imported entries. Quoting the wrong one would
        // make the sweep look like it skipped part of the program.
        int total = currentProgram.getFunctionManager().getFunctionCount();
        println("StrideSweep: scanned " + functions + " functions with bodies (program function"
            + " count including externals: " + total + "), wrote " + rows + " x3 chains -> "
            + out.toAbsolutePath());
        SweepUtil.writeManifest(outPath, rows, List.of(
            "functionsScanned=" + functions,
            "programFunctionCount=" + total));
    }

    private static class Chain {
        long bytes = 3;
        List<String> addrs = new ArrayList<>();
        List<String> text = new ArrayList<>();
        String consumerAddr = "";
        String consumerIns = "";
        String terminated = "";
    }

    /**
     * Follows the value in {@code reg} forward through the function, multiplying in every scale
     * factor applied to it, until it is consumed by a memory access, overwritten, or the window
     * runs out. Deliberately conservative: it gives up rather than guess, and says why in
     * {@code terminated}, so a chain reported with a stride is one whose whole arithmetic was
     * seen.
     */
    private Chain follow(List<Instruction> body, int seedIdx, String reg, List<Range> ranges) {
        Chain c = new Chain();
        String cur = reg;
        int hops = 0;

        for (int i = seedIdx + 1; i < body.size() && i <= seedIdx + MAX_WINDOW; i++) {
            Instruction ins = body.get(i);
            String txt = SweepUtil.cell(ins);
            String mnem = ins.getMnemonicString().toUpperCase();

            if ("CALL".equals(mnem)) {
                c.terminated = "call-clobber";
                return c;
            }

            Matcher shl = SHL.matcher(txt);
            if (shl.matches() && shl.group(1).equals(cur)) {
                c.bytes *= 1L << Long.parseLong(shl.group(2), 16);
                c.addrs.add(SweepUtil.hex(ins.getAddress().getOffset()));
                c.text.add(txt);
                if (++hops >= MAX_HOPS) {
                    c.terminated = "hop-limit";
                    return c;
                }
                continue;
            }

            Matcher use = Pattern.compile("\\b" + cur + "\\*0x([0-9a-fA-F]+)\\b").matcher(txt);
            if (use.find()) {
                c.bytes *= Long.parseLong(use.group(1), 16);
                c.addrs.add(SweepUtil.hex(ins.getAddress().getOffset()));
                c.text.add(txt);
                if ("LEA".equals(mnem)) {
                    // Address arithmetic: the chain continues in this LEA's destination.
                    String dst = ins.getDefaultOperandRepresentation(0);
                    if (!dst.matches("E[A-Z]{2}")) {
                        c.terminated = "lea-dest-not-register";
                        return c;
                    }
                    cur = dst;
                    if (++hops >= MAX_HOPS) {
                        c.terminated = "hop-limit";
                        return c;
                    }
                    continue;
                }
                // Anything else that scales the value is dereferencing it: the chain ends here.
                c.consumerAddr = SweepUtil.hex(ins.getAddress().getOffset());
                c.consumerIns = txt;
                c.terminated = "consumed";
                return c;
            }

            // Byte-offset shape: the chain register is added to an absolute base rather than
            // scaled again. `ADD EDI,0x6284e8` / `LEA EAX,[ESI + 0x57fe60]`.
            if (txt.matches(".*\\b" + cur + "\\b.*") && !globalFor(txt, ranges).isEmpty()) {
                c.consumerAddr = SweepUtil.hex(ins.getAddress().getOffset());
                c.consumerIns = txt;
                c.terminated = "consumed-base-add";
                return c;
            }

            if (writes(ins, cur)) {
                c.terminated = "overwritten";
                return c;
            }
        }
        c.terminated = "window-exhausted";
        return c;
    }

    /** True if {@code ins} writes {@code reg} as its destination operand. */
    private boolean writes(Instruction ins, String reg) {
        if (ins.getNumOperands() == 0) {
            return false;
        }
        return reg.equals(ins.getDefaultOperandRepresentation(0))
            && !"CMP".equals(ins.getMnemonicString().toUpperCase())
            && !"TEST".equals(ins.getMnemonicString().toUpperCase())
            && !"PUSH".equals(ins.getMnemonicString().toUpperCase());
    }

    /** Does any instruction in this function name an address inside a swept global? */
    private boolean touchesGlobal(List<Instruction> body, List<Range> ranges) {
        for (Instruction ins : body) {
            for (Reference r : ins.getReferencesFrom()) {
                if (inAny(r.getToAddress().getOffset(), ranges) != null) {
                    return true;
                }
            }
            for (int op = 0; op < ins.getNumOperands(); op++) {
                for (Object o : ins.getOpObjects(op)) {
                    if (o instanceof Scalar
                        && inAny(((Scalar) o).getUnsignedValue(), ranges) != null) {
                        return true;
                    }
                }
            }
        }
        return false;
    }

    /** The global whose range contains an absolute address literal in {@code text}, if any. */
    private String globalFor(String text, List<Range> ranges) {
        if (text == null || text.isEmpty()) {
            return "";
        }
        Matcher m = ABS.matcher(text);
        while (m.find()) {
            String hit = inAny(Long.parseLong(m.group(1), 16), ranges);
            if (hit != null) {
                return hit;
            }
        }
        return "";
    }

    private String inAny(long v, List<Range> ranges) {
        for (Range r : ranges) {
            if (r.has(v)) {
                return r.label;
            }
        }
        return null;
    }
}
