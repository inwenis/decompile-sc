// Applies the Magnetar table to the analyzed program: names, prototypes and global types, so
// decompiled C reads BWFXN_RefreshTarget(left, bottom, top, right) instead of
// FUN_0041e0d0(param_1) with in_EAX/in_ECX/in_EDX, and UnitNodeTable[i] instead of DAT_0059cca8.
//
// Everything lands with SourceType.IMPORTED: hypotheses from a third-party table
// (tools/ghidra/magnetar-names.ps1). A function Ghidra already named (Function ID on a CRT
// routine) keeps its name and its signature; the table only fills DEFAULT names, so it expects
// a freshly imported program (decomp-all.ps1 re-imports whenever its inputs change).
// A register-convention function gets custom storage read from Magnetar's inline-asm wrapper.
// Run ApplyTypes.java first: prototypes and globals name its structs and enums.
//
// Script args:
//   1: report path; <path>.manifest is the run's success signal
//   2: names TSV: kind \t addr \t name \t conv \t proto \t storage
//@category Headless

import generic.jar.ResourceFile;
import ghidra.app.cmd.function.ApplyFunctionSignatureCmd;
import ghidra.app.cmd.function.CreateFunctionCmd;
import ghidra.app.cmd.function.FunctionRenameOption;
import ghidra.app.script.GhidraScript;
import ghidra.app.util.cparser.C.CParser;
import ghidra.framework.Application;
import ghidra.program.model.address.Address;
import ghidra.program.model.data.*;
import ghidra.program.model.listing.*;
import ghidra.program.model.listing.Function.FunctionUpdateType;
import ghidra.program.model.symbol.SourceType;
import ghidra.program.model.symbol.Symbol;

import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.*;

public class ApplyNames extends GhidraScript {

    private DataTypeManager[] dtms;
    private final Map<String, Integer> n = new TreeMap<>();
    private final List<String> failures = new ArrayList<>();
    private final List<Function> created = new ArrayList<>();
    private final Set<Function> touched = new LinkedHashSet<>();

    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length < 2) {
            throw new IllegalArgumentException("usage: ApplyNames.java <reportPath> <namesTsv>");
        }
        FunctionManager fm = currentProgram.getFunctionManager();
        ResourceFile gdt = Application.findDataFileInAnyModule("typeinfo/win32/windows_vs12_32.gdt");
        FileDataTypeManager win = FileDataTypeManager.openFileArchive(gdt, false);
        dtms = new DataTypeManager[] { currentProgram.getDataTypeManager(), win };

        // Function ID check: functions Ghidra's own analysis named (Function ID signatures for the
        // statically linked CRT, RTTI). Counted by source, so a re-run reports the same number.
        for (Function f : fm.getFunctions(true)) {
            if (f.getSymbol().getSource() == SourceType.ANALYSIS) {
                count("functionIdNamed");
            }
        }

        TreeMap<Address, String[]> data = new TreeMap<>();
        try {
            for (String line : Files.readAllLines(Paths.get(args[1]))) {
                String[] c = line.split("\t", -1);
                if (c.length < 3 || c[0].equals("kind") || c[0].startsWith("#")) {
                    continue;
                }
                count("tableRows");
                String name = c[2], conv = at(c, 3), proto = at(c, 4), storage = at(c, 5);
                // origin=repo: this repo's verified name (magnetar-overrides.tsv), not a hypothesis
                SourceType src = at(c, 6).equals("repo") ? SourceType.USER_DEFINED : SourceType.IMPORTED;
                Address a = toAddr(Long.parseUnsignedLong(c[1].replaceFirst("^0[xX]", ""), 16));
                if (!currentProgram.getMemory().contains(a)) {
                    count("outsideMemory");
                }
                else if (c[0].equals("func")) {
                    applyFunction(fm, a, name, src, conv, proto, storage);
                }
                else {
                    data.put(a, new String[] { name, proto, src.name() });
                }
            }
            // A body traced before a later table entry existed flowed straight through it; with
            // every entry in place, each body stops at its neighbours' entries.
            for (Function f : touched) {
                CreateFunctionCmd.fixupFunctionBody(currentProgram, f, monitor);
            }
            // A one-byte body is a bare RET stub, or code that never disassembled.
            for (Function f : created) {
                Instruction ins = getInstructionAt(f.getEntryPoint());
                if (f.getBody().getNumAddresses() <= 1 && (ins == null || !ins.getFlowType().isTerminal())) {
                    count("funcBodyUnresolved");
                    failures.add("BODY\t" + f.getEntryPoint() + "\t" + f.getName());
                }
            }
            applyData(data);
        }
        finally {
            win.close();
        }

        List<String> report = new ArrayList<>();
        report.add("program=" + currentProgram.getName());
        report.add("functionsTotal=" + fm.getFunctionCount());
        for (Map.Entry<String, Integer> e : n.entrySet()) {
            report.add(e.getKey() + "=" + e.getValue());
        }
        for (String r : report) {
            println("ApplyNames: " + r);
        }
        List<String> full = new ArrayList<>(report);
        full.add("# failures (first 50 of each kind)");
        Map<String, Integer> shown = new HashMap<>();
        for (String fl : failures) {
            if (shown.merge(fl.substring(0, fl.indexOf('\t')), 1, Integer::sum) <= 50) {
                full.add(fl);
            }
        }
        Files.createDirectories(Paths.get(args[0]).toAbsolutePath().getParent());
        Files.write(Paths.get(args[0]), full);
        SweepUtil.writeManifest(args[0], n.getOrDefault("tableRows", 0), report);
    }

    private void applyFunction(FunctionManager fm, Address a, String name, SourceType src, String conv,
            String proto, String storage) throws Exception {
        Function f = fm.getFunctionAt(a);
        if (f == null) {
            // Ghidra never reached this code: without instructions the body is one byte.
            if (getInstructionAt(a) == null) {
                disassemble(a);
            }
            Function container = fm.getFunctionContaining(a);
            if (container != null) {
                touched.add(container);
            }
            f = createFunction(a, null);
            if (f == null) {
                count("funcNoCodeAtAddress");
                return;
            }
            created.add(f);
            touched.add(f);
            count("funcCreated");
        }
        if (!name.isEmpty()) {
            if (f.getName().equals(name)) {
                count("funcAlreadyNamed");
            }
            else if (f.getSymbol().getSource() == SourceType.DEFAULT) {
                f.setName(name, src);
                count(src == SourceType.USER_DEFINED ? "funcNamedFromRepo" : "funcRenamed");
            }
            else {
                count("funcKeptExistingName");
                return;
            }
        }
        else if (f.getSymbol().getSource() == SourceType.ANALYSIS) {
            // the table has no name here but Function ID does: its evidence wins, signature too
            count("funcKeptExistingName");
            return;
        }
        if (proto.isEmpty() || storage.equals("?")) {
            count("protoSkipped");
            return;
        }
        DataType parsed = parse(proto, conv);
        FunctionDefinition sig = parsed instanceof FunctionDefinition ? (FunctionDefinition) parsed : null;
        if (sig == null) {
            count("protoParseFailed");
            failures.add("PARSE\t" + a + "\t" + proto);
            if (!conv.isEmpty()) {
                f.setCallingConvention(conv);
            }
            return;
        }
        try {
            if (conv.equals("__thiscall") && sig.getArguments().length > 0) {
                // Ghidra's __thiscall adds its own void *this, which pushes Magnetar's typed
                // this_ onto the stack. Spelled out instead: this_ in ECX, the rest from +4.
                StringBuilder s = new StringBuilder("ret=EAX");
                int off = 4;
                ParameterDefinition[] defs = sig.getArguments();
                for (int i = 0; i < defs.length; i++) {
                    s.append(';').append(defs[i].getName()).append('=').append(i == 0 ? "ECX" : "S" + off);
                    off += i == 0 ? 0 : Math.max(4, (defs[i].getLength() + 3) & ~3);
                }
                applyCustomStorage(f, sig, s.toString(), conv);
                count("protoAppliedThiscall");
            }
            else if (!conv.isEmpty()) {
                ApplyFunctionSignatureCmd cmd = new ApplyFunctionSignatureCmd(a, sig, SourceType.IMPORTED,
                    false, false, DataTypeConflictHandler.DEFAULT_HANDLER, FunctionRenameOption.NO_CHANGE);
                if (!cmd.applyTo(currentProgram)) {
                    throw new IllegalStateException(cmd.getStatusMsg());
                }
                count("protoApplied");
            }
            else {
                applyCustomStorage(f, sig, storage, null);
                count("protoAppliedCustomStorage");
            }
        }
        catch (Exception e) {
            count("protoApplyFailed");
            failures.add("APPLY\t" + a + "\t" + proto + "\t" + storage + "\t" + e.getMessage());
        }
    }

    // storage: ret=<reg>;<arg>=<reg>|S<offset from the entry stack pointer>;...
    private void applyCustomStorage(Function f, FunctionDefinition sig, String storage, String conv) throws Exception {
        Map<String, String> where = new HashMap<>();
        for (String kv : storage.split(";")) {
            if (!kv.isEmpty()) {
                String[] p = kv.split("=", 2);
                where.put(p[0], p[1]);
            }
        }
        List<Variable> params = new ArrayList<>();
        for (ParameterDefinition d : sig.getArguments()) {
            String loc = where.get(d.getName());
            if (loc == null) {
                throw new IllegalArgumentException("no storage for argument " + d.getName());
            }
            params.add(loc.matches("S\\d+")
                ? new ParameterImpl(d.getName(), d.getDataType(), Integer.parseInt(loc.substring(1)), currentProgram, SourceType.IMPORTED)
                : new ParameterImpl(d.getName(), d.getDataType(), currentProgram.getRegister(loc), currentProgram, SourceType.IMPORTED));
        }
        DataType rt = sig.getReturnType();
        ReturnParameterImpl ret = (rt == null || rt instanceof VoidDataType)
            ? new ReturnParameterImpl(VoidDataType.dataType, currentProgram)
            : new ReturnParameterImpl(rt, currentProgram.getRegister(where.getOrDefault("ret", "EAX")), currentProgram);
        f.updateFunction(conv, ret, params, FunctionUpdateType.CUSTOM_STORAGE, true, SourceType.IMPORTED);
    }

    // Magnetar's declarations overlap (ScreenLayers is layer[12], yet GameScreenBuffer starts at
    // its ninth element), and creating the later one clears the earlier array whole. In address
    // order, each array is clamped to the gap before the next typed global; a non-array that
    // overlaps is left untyped; every type is read back afterwards.
    private void applyData(TreeMap<Address, String[]> data) throws Exception {
        List<Address> typed = new ArrayList<>();
        for (Map.Entry<Address, String[]> e : data.entrySet()) {
            Address a = e.getKey();
            String name = e.getValue()[0];
            Symbol s = currentProgram.getSymbolTable().getPrimarySymbol(a);
            if (s != null && s.getName().equals(name)) {
                count("dataAlreadyNamed");
            }
            else if (s != null && s.getSource() != SourceType.DEFAULT) {
                count("dataKeptExistingName");
                continue;
            }
            else {
                createLabel(a, name, true, SourceType.valueOf(e.getValue()[2]));
                count("dataLabeled");
            }
            if (!e.getValue()[1].isEmpty()) {
                typed.add(a);
            }
        }
        Map<Address, DataType> applied = new LinkedHashMap<>();
        for (int i = 0; i < typed.size(); i++) {
            Address a = typed.get(i);
            String name = data.get(a)[0], decl = data.get(a)[1];
            try {
                DataType dt = parseDecl(decl);
                long gap = i + 1 < typed.size() ? typed.get(i + 1).subtract(a) : Long.MAX_VALUE;
                if (dt.getLength() > gap) {
                    if (dt instanceof Array && gap >= ((Array) dt).getElementLength()) {
                        Array arr = (Array) dt;
                        int elems = (int) (gap / arr.getElementLength());
                        failures.add("CLAMP\t" + a + "\t" + name + "\t" + decl + "\tto " + elems + " elements");
                        dt = new ArrayDataType(arr.getDataType(), elems, arr.getElementLength(), currentProgram.getDataTypeManager());
                        count("dataArrayClamped");
                    }
                    else {
                        failures.add("OVERLAP\t" + a + "\t" + name + "\t" + decl + "\tnext global at +" + gap);
                        count("dataTypeSkippedOverlap");
                        continue;
                    }
                }
                DataUtilities.createData(currentProgram, a, dt, -1, DataUtilities.ClearDataMode.CLEAR_ALL_CONFLICT_DATA);
                applied.put(a, dt);
            }
            catch (Exception ex) {
                count("dataTypeFailed");
                failures.add("DATA\t" + a + "\t" + name + "\t" + decl + "\t" + ex.getMessage());
            }
        }
        for (Map.Entry<Address, DataType> e : applied.entrySet()) {
            Data d = getDataAt(e.getKey());
            if (d != null && d.getDataType().isEquivalent(e.getValue())) {
                count("dataTyped");
            }
            else {
                count("dataTypeLost");
                failures.add("LOST\t" + e.getKey() + "\t" + data.get(e.getKey())[0]);
            }
        }
    }

    // CParser never fills its declarations map; a typedef of the declarator carries the type.
    private DataType parseDecl(String decl) throws Exception {
        CParser p = new CParser(currentProgram.getDataTypeManager(), false, dtms);
        p.parse("typedef " + decl + ";");
        DataType dt = p.getTypes().get("__v");
        if (!(dt instanceof TypeDef)) {
            throw new IllegalArgumentException("no type parsed");
        }
        return ((TypeDef) dt).getDataType();
    }

    // The C parser knows __cdecl/__stdcall/__fastcall but not __thiscall; the convention is set on
    // the parsed signature instead (a function-pointer argument loses only its own convention).
    private DataType parse(String proto, String conv) {
        CParser p = new CParser(currentProgram.getDataTypeManager(), false, dtms);
        try {
            DataType dt = p.parse(proto.replace("__thiscall", "") + ";");
            if (dt instanceof FunctionDefinitionDataType && !conv.isEmpty()) {
                ((FunctionDefinitionDataType) dt).setCallingConvention(conv);
            }
            return dt;
        }
        catch (Throwable t) {
            return null;
        }
    }

    private void count(String key) {
        n.merge(key, 1, Integer::sum);
    }

    private static String at(String[] c, int i) {
        return c.length > i ? c[i].trim() : "";
    }
}
