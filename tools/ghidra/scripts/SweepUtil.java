// Shared helpers for the selection-sweep query scripts (XrefSweep, ImmediateSweep,
// RegionProbe, FuncProbe, DecompileMany, ProgramInfo).
//
// Not a GhidraScript -- a plain class compiled alongside them by Ghidra's script compiler
// because it lives in the same -scriptPath directory.
//
// The manifest contract: every query script writes <outPath>.manifest as its LAST action, with
// status=OK. tools/ghidra/sweep.ps1 deletes any stale manifest before the run and requires a
// fresh status=OK afterwards -- analyzeHeadless exits 0 even when a post-script throws, so the
// manifest is the only signal specific to THIS run.
//
//@category Headless

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.List;

public class SweepUtil {

    /** One line of a spec file: a label plus its comma-separated fields. */
    public static class Spec {
        public final String label;
        public final List<String> fields;

        Spec(String label, List<String> fields) {
            this.label = label;
            this.fields = fields;
        }

        public String field(int i) {
            if (i >= fields.size()) {
                throw new IllegalArgumentException("spec '" + label + "' has no field " + i);
            }
            return fields.get(i);
        }

        public long hex(int i) {
            String s = field(i).trim();
            if (s.startsWith("0x") || s.startsWith("0X")) {
                s = s.substring(2);
            }
            return Long.parseUnsignedLong(s, 16);
        }

        public long dec(int i) {
            return Long.parseLong(field(i).trim());
        }
    }

    /**
     * Reads a spec file: one record per line, comma-separated, first field is the label.
     * Blank lines and lines starting with '#' are ignored.
     */
    public static List<Spec> readSpec(String path) throws IOException {
        List<Spec> out = new ArrayList<>();
        for (String raw : Files.readAllLines(Paths.get(path))) {
            String line = raw.trim();
            if (line.isEmpty() || line.startsWith("#")) {
                continue;
            }
            String[] parts = line.split(",");
            List<String> fields = new ArrayList<>();
            for (int i = 1; i < parts.length; i++) {
                fields.add(parts[i].trim());
            }
            out.add(new Spec(parts[0].trim(), fields));
        }
        return out;
    }

    /** Writes the run's success manifest. Call this LAST, only after all output is on disk. */
    public static void writeManifest(String outPath, long rows, List<String> extra) throws IOException {
        Path p = Paths.get(outPath + ".manifest");
        List<String> lines = new ArrayList<>();
        lines.add("status=OK");
        lines.add("out=" + outPath.replace("\\", "/"));
        lines.add("rows=" + rows);
        if (extra != null) {
            lines.addAll(extra);
        }
        Files.createDirectories(p.toAbsolutePath().getParent());
        Files.write(p, lines);
    }

    /** TSV-safe: strip tabs/newlines out of a free-text cell. */
    public static String cell(Object o) {
        if (o == null) {
            return "";
        }
        return o.toString().replace('\t', ' ').replace('\n', ' ').replace('\r', ' ');
    }

    public static String hex(long v) {
        return "0x" + String.format("%08X", v);
    }
}
