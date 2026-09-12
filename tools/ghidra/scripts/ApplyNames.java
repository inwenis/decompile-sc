// Applies the Magnetar table to the analyzed program: names, prototypes and global types, so
// decompiled C reads BWFXN_RefreshTarget(left, bottom, top, right) instead of
// FUN_0041e0d0(param_1) with in_EAX/in_ECX/in_EDX, and UnitNodeTable[i] instead of DAT_0059cca8.
//
// Everything lands with SourceType.IMPORTED: hypotheses from a third-party table
// (tools/ghidra/magnetar-names.ps1). A function Ghidra already named from evidence (Function ID
// on a CRT routine) keeps its name and its signature; the table never overrides it.
// A register-convention function gets custom storage read from Magnetar's inline-asm wrapper.
// Run ApplyTypes.java first: prototypes and globals name its structs and enums.
//
// Script args:
//   1: report path; <path>.manifest is the run's success signal
//   2: names TSV: kind \t addr \t name \t conv \t proto \t storage
//@category Headless

import generic.jar.ResourceFile;
import ghidra.app.cmd.function.ApplyFunctionSignatureCmd;
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

        try {
            for (String line : Files.readAllLines(Paths.get(args[1]))) {
                String[] c = line.split("\t", -1);
                if (c.length < 3 || c[0].equals("kind") || c[0].startsWith("#")) {
                    continue;
                }
                count("tableRows");
                String name = c[2], conv = at(c, 3), proto = at(c, 4), storage = at(c, 5);
                Address a = toAddr(Long.parseUnsignedLong(c[1].replaceFirst("^0[xX]", ""), 16));
                if (!currentProgram.getMemory().contains(a)) {
                    count("outsideMemory");
                }
                else if (c[0].equals("func")) {
                    applyFunction(fm, a, name, conv, proto, storage);
                }
                else {
                    applyData(a, name, proto);
                }
            }
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

    private void applyFunction(FunctionManager fm, Address a, String name, String conv,
            String proto, String storage) throws Exception {
        Function f = fm.getFunctionAt(a);
        if (f == null) {
            f = createFunction(a, null);
            if (f == null) {
                count("funcNoCodeAtAddress");
                return;
            }
            count("funcCreated");
        }
        if (!name.isEmpty()) {
            if (f.getName().equals(name)) {
                // createFunction stamps USER_DEFINED; a table name is a hypothesis, IMPORTED.
                if (f.getSymbol().getSource() == SourceType.USER_DEFINED) {
                    f.setName(name, SourceType.IMPORTED);
                }
                count("funcAlreadyNamed");
            }
            else if (f.getSymbol().getSource() == SourceType.DEFAULT) {
                f.setName(name, SourceType.IMPORTED);
                count("funcRenamed");
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
                ParameterDefinition[] a = sig.getArguments();
                for (int i = 0; i < a.length; i++) {
                    s.append(';').append(a[i].getName()).append('=').append(i == 0 ? "ECX" : "S" + off);
                    off += i == 0 ? 0 : Math.max(4, (a[i].getLength() + 3) & ~3);
                }
                applyCustomStorage(f, sig, s.toString(), conv);
                count("protoAppliedThiscall");
            }
            else if (!conv.isEmpty()) {
                ApplyFunctionSignatureCmd cmd = new ApplyFunctionSignatureCmd(a, sig, SourceType.IMPORTED,
                    false, FunctionRenameOption.NO_CHANGE);
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

    private void applyData(Address a, String name, String decl) throws Exception {
        Symbol s = currentProgram.getSymbolTable().getPrimarySymbol(a);
        if (s != null && s.getName().equals(name)) {
            count("dataAlreadyNamed");
        }
        else if (s != null && s.getSource() != SourceType.DEFAULT) {
            count("dataKeptExistingName");
            return;
        }
        else {
            createLabel(a, name, true, SourceType.IMPORTED);
            count("dataLabeled");
        }
        if (decl.isEmpty()) {
            return;
        }
        // CParser never fills its declarations map; a typedef of the declarator carries the type.
        CParser p = new CParser(currentProgram.getDataTypeManager(), false, dtms);
        try {
            p.parse("typedef " + decl + ";");
            DataType dt = p.getTypes().get("__v");
            if (!(dt instanceof TypeDef)) {
                throw new IllegalArgumentException("no type parsed");
            }
            dt = ((TypeDef) dt).getDataType();
            DataUtilities.createData(currentProgram, a, dt, -1, DataUtilities.ClearDataMode.CLEAR_ALL_CONFLICT_DATA);
            count("dataTyped");
        }
        catch (Exception e) {
            count("dataTypeFailed");
            failures.add("DATA\t" + a + "\t" + name + "\t" + decl + "\t" + e.getMessage());
        }
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
