// Applies an address -> name table to the analyzed program so decompiled C reads
// updateFog(...) instead of FUN_004805f0(...) and unitTable instead of DAT_0059cca8.
//
// Names land with SourceType.IMPORTED: hypotheses from a third-party table
// (tools/ghidra/magnetar-names.ps1). A function Ghidra already named from evidence (Function ID
// on a CRT routine, an import) keeps its name; the table never overrides it.
//
// Script args:
//   1: report path; <path>.manifest is the run's success signal
//   2: names TSV: kind \t addr \t name \t conv   (kind = func | data; conv may be empty)
//@category Headless

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionManager;
import ghidra.program.model.symbol.SourceType;
import ghidra.program.model.symbol.Symbol;

import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.List;

public class ApplyNames extends GhidraScript {

    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length < 2) {
            throw new IllegalArgumentException("usage: ApplyNames.java <reportPath> <namesTsv>");
        }
        FunctionManager fm = currentProgram.getFunctionManager();

        // Function ID check: functions Ghidra's own analysis named (Function ID signatures for the
        // statically linked CRT, RTTI). Counted by source, so a re-run reports the same number.
        int analysisNamed = 0;
        for (Function f : fm.getFunctions(true)) {
            if (f.getSymbol().getSource() == SourceType.ANALYSIS) {
                analysisNamed++;
            }
        }

        int funcRenamed = 0, funcCreated = 0, funcKept = 0, funcAlready = 0, funcNoCode = 0, funcBadName = 0;
        int convSet = 0, convFailed = 0, dataLabeled = 0, dataAlready = 0, dataKept = 0, outside = 0, rows = 0;
        for (String line : Files.readAllLines(Paths.get(args[1]))) {
            String[] c = line.split("\t", -1);
            if (c.length < 3 || c[0].equals("kind") || c[0].startsWith("#")) {
                continue;
            }
            rows++;
            String kind = c[0], name = c[2], conv = c.length > 3 ? c[3].trim() : "";
            Address a = toAddr(Long.parseUnsignedLong(c[1].replaceFirst("^0[xX]", ""), 16));
            if (!currentProgram.getMemory().contains(a)) {
                outside++;
                continue;
            }
            if (kind.equals("func")) {
                Function f = fm.getFunctionAt(a);
                if (f == null) {
                    f = createFunction(a, name.isEmpty() ? null : name);
                    if (f == null) {
                        funcNoCode++;
                        continue;
                    }
                    funcCreated++;
                }
                else if (name.isEmpty()) {
                    // convention-only row: an auto-name in the table, nothing to rename
                }
                else if (f.getName().equals(name)) {
                    funcAlready++;
                }
                else if (isAutoName(f.getName())) {
                    try {
                        f.setName(name, SourceType.IMPORTED);
                        funcRenamed++;
                    }
                    catch (Exception e) {
                        funcBadName++;
                        println("ApplyNames: cannot name " + a + " " + name + ": " + e.getMessage());
                    }
                }
                else {
                    funcKept++;
                }
                if (!conv.isEmpty()) {
                    try {
                        f.setCallingConvention(conv);
                        convSet++;
                    }
                    catch (Exception e) {
                        convFailed++;
                    }
                }
            }
            else {
                Symbol s = currentProgram.getSymbolTable().getPrimarySymbol(a);
                if (s != null && s.getName().equals(name)) {
                    dataAlready++;
                    continue;
                }
                if (s != null && s.getSource() != SourceType.DEFAULT) {
                    dataKept++;
                    continue;
                }
                createLabel(a, name, true, SourceType.IMPORTED);
                dataLabeled++;
            }
        }

        List<String> report = new ArrayList<>();
        report.add("program=" + currentProgram.getName());
        report.add("functionsTotal=" + fm.getFunctionCount());
        report.add("functionIdNamed=" + analysisNamed);
        report.add("tableRows=" + rows);
        report.add("funcRenamed=" + funcRenamed);
        report.add("funcCreated=" + funcCreated);
        report.add("funcAlreadyNamed=" + funcAlready);
        report.add("funcKeptExistingName=" + funcKept);
        report.add("funcNoCodeAtAddress=" + funcNoCode);
        report.add("funcBadName=" + funcBadName);
        report.add("convSet=" + convSet);
        report.add("convFailed=" + convFailed);
        report.add("dataLabeled=" + dataLabeled);
        report.add("dataAlreadyNamed=" + dataAlready);
        report.add("dataKeptExistingName=" + dataKept);
        report.add("outsideMemory=" + outside);
        Files.createDirectories(Paths.get(args[0]).toAbsolutePath().getParent());
        Files.write(Paths.get(args[0]), report);
        for (String r : report) {
            println("ApplyNames: " + r);
        }
        SweepUtil.writeManifest(args[0], rows, report);
    }

    private static boolean isAutoName(String n) {
        return n.startsWith("FUN_") || n.startsWith("thunk_FUN_");
    }
}
