// Reports what Ghidra ACTUALLY resolved for the imported program -- language/compiler spec,
// image base, entry point(s), memory block map, function/symbol counts.
//
// Exists so the research write-up can state these as observations rather than assumptions
// (tools/ghidra/README.md §"What StarCraft.exe 1.16.1 will need beyond this" point 2/3 warns
// that the language and image base must be verified, not assumed).
//
// Script args:
//   1: output path (a text report; <path>.manifest is the run's success signal)
//
//@category Headless

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.mem.MemoryBlock;
import ghidra.program.model.symbol.Symbol;

import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.List;

public class ProgramInfo extends GhidraScript {

    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length < 1) {
            throw new IllegalArgumentException("usage: ProgramInfo.java <outPath>");
        }
        String outPath = args[0];

        List<String> out = new ArrayList<>();
        out.add("program                = " + currentProgram.getName());
        out.add("executablePath         = " + currentProgram.getExecutablePath());
        out.add("executableFormat       = " + currentProgram.getExecutableFormat());
        out.add("executableSHA256       = " + currentProgram.getExecutableSHA256());
        out.add("executableMD5          = " + currentProgram.getExecutableMD5());
        out.add("languageID             = " + currentProgram.getLanguageID());
        out.add("compilerSpecID         = " + currentProgram.getCompilerSpec().getCompilerSpecID());
        out.add("processor              = " + currentProgram.getLanguage().getProcessor());
        out.add("addressSize            = " + currentProgram.getLanguage().getLanguageDescription().getSize());
        out.add("endian                 = " + currentProgram.getLanguage().getLanguageDescription().getEndian());
        out.add("imageBase              = " + currentProgram.getImageBase());
        out.add("minAddress             = " + currentProgram.getMinAddress());
        out.add("maxAddress             = " + currentProgram.getMaxAddress());
        out.add("functionCount          = " + currentProgram.getFunctionManager().getFunctionCount());
        out.add("definedDataCount       = " + currentProgram.getListing().getNumDefinedData());
        out.add("symbolCount            = " + currentProgram.getSymbolTable().getNumSymbols());
        out.add("");

        out.add("# entry points");
        for (Address a : currentProgram.getSymbolTable().getExternalEntryPointIterator()) {
            Symbol[] syms = currentProgram.getSymbolTable().getSymbols(a);
            String name = syms.length > 0 ? syms[0].getName() : "(unnamed)";
            out.add("entry " + a + "  " + name);
        }
        out.add("");

        out.add("# memory blocks: name\tstart\tend\tsize\tr\tw\tx\tinitialized");
        for (MemoryBlock b : currentProgram.getMemory().getBlocks()) {
            out.add(String.join("\t",
                b.getName(),
                b.getStart().toString(),
                b.getEnd().toString(),
                Long.toString(b.getSize()),
                Boolean.toString(b.isRead()),
                Boolean.toString(b.isWrite()),
                Boolean.toString(b.isExecute()),
                Boolean.toString(b.isInitialized())));
        }

        Path p = Paths.get(outPath);
        if (p.toAbsolutePath().getParent() != null) {
            Files.createDirectories(p.toAbsolutePath().getParent());
        }
        Files.write(p, out);
        println("ProgramInfo: wrote " + p.toAbsolutePath());

        SweepUtil.writeManifest(outPath, out.size(), List.of(
            "languageID=" + currentProgram.getLanguageID(),
            "imageBase=" + currentProgram.getImageBase()));
    }
}
