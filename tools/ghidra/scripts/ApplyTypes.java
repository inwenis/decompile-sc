// Imports the Magnetar struct/enum header into the program's data types, so decompiled C reads
// unit->orderID instead of *(char *)(param_1 + 0x4d).
//
// Ghidra's C parser sizes every enum as an int and rejects C++11 "enum X : T", so enums arrive
// pre-split with their true size (tools/ghidra/magnetar-names.ps1) and are created FIRST: the
// parser then resolves "Order orderID;" to the 1-byte enum already in the program and struct
// layouts hold. Each struct's parsed size is checked against the header's own static_assert.
//
// Script args:
//   1: report path; <path>.manifest is the run's success signal
//   2: cleaned header      3: enums TSV (enum, size, member, value)      4: sizes TSV (type, size)
//   5: layout dump: every imported struct field with its offset, every enum value (for grep)
//@category Headless

import generic.jar.ResourceFile;
import ghidra.app.script.GhidraScript;
import ghidra.app.util.cparser.C.CParserUtils;
import ghidra.framework.Application;
import ghidra.program.model.data.*;

import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;

public class ApplyTypes extends GhidraScript {

    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length < 5) {
            throw new IllegalArgumentException("usage: ApplyTypes.java <report> <header> <enumsTsv> <sizesTsv> <layoutOut>");
        }
        DataTypeManager dtm = currentProgram.getDataTypeManager();
        CategoryPath cat = new CategoryPath("/magnetar");

        Map<String, EnumDataType> enums = new LinkedHashMap<>();
        for (String[] c : tsv(args[2])) {
            EnumDataType e = enums.computeIfAbsent(c[0],
                n -> new EnumDataType(cat, n, Integer.parseInt(c[1]), dtm));
            if (c.length > 3 && !c[2].isEmpty()) {
                e.add(c[2], Long.decode(c[3]));
            }
        }
        for (EnumDataType e : enums.values()) {
            dtm.addDataType(e, DataTypeConflictHandler.REPLACE_HANDLER);
        }

        // Windows types (RECT, HWND...) resolve from Ghidra's shipped archive.
        ResourceFile gdt = Application.findDataFileInAnyModule("typeinfo/win32/windows_vs12_32.gdt");
        FileDataTypeManager win = FileDataTypeManager.openFileArchive(gdt, false);
        CParserUtils.CParseResults parsed;
        try {
            parsed = CParserUtils.parseHeaderFiles(new DataTypeManager[] { win },
                new String[] { args[1] }, new String[0], new String[0], dtm, monitor);
        }
        finally {
            win.close();
        }

        List<String> report = new ArrayList<>();
        report.add("enums=" + enums.size());
        report.add("parseSucceeded=" + parsed.successful());
        int ok = 0, missing = 0, wrong = 0;
        List<String> detail = new ArrayList<>();
        List<String> asserted = new ArrayList<>();
        for (String[] c : tsv(args[3])) {
            asserted.add(c[0]);
            int want = Integer.parseInt(c[1]);
            DataType dt = find(dtm, c[0]);
            if (dt == null) {
                missing++;
                detail.add("MISSING\t" + c[0] + "\twant " + want);
            }
            else if (dt.getLength() != want) {
                wrong++;
                detail.add("SIZE\t" + c[0] + "\twant " + want + "\tgot " + dt.getLength());
            }
            else {
                ok++;
            }
        }
        report.add("sizeAssertsOk=" + ok);
        report.add("sizeAssertsWrong=" + wrong);
        report.add("sizeAssertsMissing=" + missing);
        for (String r : report) {
            println("ApplyTypes: " + r);
        }
        report.addAll(detail);
        report.add("# parser messages");
        report.add(parsed.cParseMessages());
        report.add(parsed.cppParseMessages());
        Files.createDirectories(Paths.get(args[0]).toAbsolutePath().getParent());
        Files.write(Paths.get(args[0]), report);
        Files.write(Paths.get(args[4]), layout(dtm, Paths.get(args[1]).getFileName().toString(), asserted, enums));
        // The size asserts are the layout oracle: a failed parse or one wrong size writes no
        // manifest, so sweep.ps1 stops the pipeline instead of decompiling with broken structs.
        if (!parsed.successful() || wrong > 0 || missing > 0) {
            throw new IllegalStateException("ApplyTypes: parse or struct sizes failed, see " + args[0]);
        }
        SweepUtil.writeManifest(args[0], ok, report.subList(0, 5));
    }

    /** "struct CUnit (336 bytes)", then one self-contained line per field and per enum value, so
     *  a single grep answers "CUnit +0x04D" or "Order ORD_DIE". */
    private static List<String> layout(DataTypeManager dtm, String headerName, List<String> asserted,
            Map<String, EnumDataType> enums) {
        List<String> out = new ArrayList<>();
        Category c = dtm.getCategory(new CategoryPath("/" + headerName));
        Map<String, Composite> byName = new TreeMap<>();
        for (DataType d : c == null ? new DataType[0] : c.getDataTypes()) {
            if (d instanceof Composite) {
                byName.put(d.getName(), (Composite) d);
            }
        }
        // A header type can land outside the header's category (Location does); the size check
        // finds it by name, so the dump does too.
        for (String name : asserted) {
            DataType d = find(dtm, name);
            if (d instanceof Composite && !byName.containsKey(name)) {
                byName.put(name, (Composite) d);
            }
        }
        List<Composite> comps = new ArrayList<>(byName.values());
        for (Composite s : comps) {
            out.add((s instanceof Union ? "union " : "struct ") + s.getName() + " (" + s.getLength() + " bytes)");
            for (DataTypeComponent m : s.getDefinedComponents()) {
                out.add(String.format("%s +0x%03X  %d  %s  %s", s.getName(), m.getOffset(), m.getLength(),
                    m.getDataType().getDisplayName(), m.getFieldName()));
            }
        }
        for (EnumDataType e : enums.values()) {
            out.add("enum " + e.getName() + " (" + e.getLength() + " bytes)");
            for (long v : e.getValues()) {
                for (String name : e.getNames(v)) {
                    out.add(String.format("%s 0x%X  %s", e.getName(), v, name));
                }
            }
        }
        return out;
    }

    /** The composite (or typedef to one) the header defined under this name, wherever it landed. */
    private static DataType find(DataTypeManager dtm, String name) {
        List<DataType> hits = new ArrayList<>();
        dtm.findDataTypes(name, hits);
        for (DataType d : hits) {
            if (d instanceof Composite) {
                return d;
            }
        }
        return hits.isEmpty() ? null : hits.get(0);
    }

    private static List<String[]> tsv(String path) throws Exception {
        List<String[]> out = new ArrayList<>();
        List<String> lines = Files.readAllLines(Paths.get(path));
        for (int i = 1; i < lines.size(); i++) {
            if (!lines.get(i).isBlank()) {
                out.add(lines.get(i).split("\t", -1));
            }
        }
        return out;
    }
}
