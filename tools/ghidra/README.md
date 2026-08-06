# Ghidra headless RE pipeline

Reproducible, no-GUI Ghidra pipeline: import a PE, auto-analyze, export a disassembly listing
and decompiled C for one function -- one command. This is the analysis backbone for the
StarCraft 1.16.1 work in `research/`.

## Pinned release

| | |
|---|---|
| Version | Ghidra 12.1.2 (tag `Ghidra_12.1.2_build`) |
| Asset | `ghidra_12.1.2_PUBLIC_20260605.zip` |
| Download URL | https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_12.1.2_build/ghidra_12.1.2_PUBLIC_20260605.zip |
| SHA-256 | `b62e81a0390618466c019c60d8c2f796ced2509c4c1aea4a37644a77272cf99d` |
| Size | ~546 MB zip, ~1.2 GB extracted |
| Install path (gitignored) | `tools/ghidra/ghidra_12.1.2_PUBLIC/` |

Hash confirmed two ways: matches the `digest` field on the GitHub release asset, and matches
the SHA-256 published in the release notes body.

## Install (fresh machine)

```powershell
cd tools/ghidra
Invoke-WebRequest -Uri 'https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_12.1.2_build/ghidra_12.1.2_PUBLIC_20260605.zip' -OutFile ghidra_12.1.2_PUBLIC_20260605.zip
$hash = (Get-FileHash ghidra_12.1.2_PUBLIC_20260605.zip -Algorithm SHA256).Hash
if ($hash -ne 'B62E81A0390618466C019C60D8C2F796CED2509C4C1AEA4A37644A77272CF99D') { throw "hash mismatch: $hash" }
Expand-Archive ghidra_12.1.2_PUBLIC_20260605.zip -DestinationPath .
```

Extracts to `tools/ghidra/ghidra_12.1.2_PUBLIC/` (note: the top-level folder inside the zip is
named after the version, not the dated asset filename). Both the zip and any `ghidra_*/`
install directory under `tools/ghidra/` are gitignored -- never commit either.

### JDK requirement

Ghidra 12.1.2's `Ghidra/application.properties` declares `application.java.min=21` with no
upper bound (`application.java.max` empty) -- any JDK 21+ 64-bit works. This machine has
JDK 24.0.1 on PATH (`java -version`) and it runs 12.1.2 cleanly; no separate JDK install was
needed. If your `java` is older than 21, install a JDK 21+ build and make sure it's first on
PATH (or point `analyze.ps1` at it via a `JAVA_HOME`-aware shell before invoking).

## Usage

```powershell
./tools/ghidra/analyze.ps1 -InputPE <path-to-pe> -FunctionName <name>
# or, for a stripped binary with no symbol:
./tools/ghidra/analyze.ps1 -InputPE <path-to-pe> -FunctionAddress 0x<hex-address>
```

Writes to `work/scratch/ghidra-out/` (default, gitignored; override with `-OutDir`):
- `<binary-name>.listing.txt` -- full disassembly listing
- `<binary-name>.<function-name>.c` -- decompiled C for the selected function

Full parameter docs: `Get-Help ./tools/ghidra/analyze.ps1 -Full`.

The wrapper creates a throwaway project under `tools/ghidra/ghidra_projects/` (gitignored,
wiped and recreated each run, and also passed `-deleteProject` so Ghidra itself removes it after
the run). It verifies the two output files actually exist before reporting success --
`analyzeHeadless` can exit 0 even when the post-script threw, so a missing output is treated as
a hard failure.

## Proof (benign, non-game PE)

Ran against `C:\Windows\SysWOW64\pngfilt.dll` (a stock Windows system DLL, 60,416 bytes,
confirmed 32-bit x86 PE via its PE header `Machine = 0x014c`) -- no StarCraft/Blizzard file
involved. Target: `DllCanUnloadNow`, one of the DLL's two real exports (verified by parsing its
export table before the run).

Command:
```powershell
./tools/ghidra/analyze.ps1 -InputPE work\scratch\test-pe\pngfilt.dll -FunctionName DllCanUnloadNow
```

Disassembly listing snippet (`pngfilt.dll.listing.txt`, function entry point):
```
10004330  XOR EAX,EAX
10004332  CMP dword ptr [0x1000e5e4],EAX
10004338  SETNZ AL
1000433b  RET
```

Decompiled C (`pngfilt.dll.DllCanUnloadNow.c`, full file):
```c
HRESULT DllCanUnloadNow(void)

{
                    /* 0x4330  1  DllCanUnloadNow */
  return (uint)(DAT_1000e5e4 != 0);
}
```

Also re-ran with `-FunctionAddress 0x10004330` (no name given) against the same binary to prove
the address-selector path used for stripped binaries; it independently resolved to
`DllCanUnloadNow` and produced identical output.

## What StarCraft.exe 1.16.1 will need beyond this

The target (`research/prior-art.md` §6, §8) is a ~2.7 MB 32-bit x86 PE from a 1998-era/2009
Blizzard build (VC6-class toolchain), no debug symbols, no public `.idb`/`.gzf`. Differences
from the benign-PE proof above:

1. **No symbols -> always use `-FunctionAddress`, not `-FunctionName`.** Ghidra will auto-name
   functions `FUN_xxxxxxxx`; there is no export/PDB table to seed real names. Function
   addresses must come from evidence (BWAPI/GPTP hook lists, `samase_scarf`, manual analysis --
   see `research/prior-art.md` §2-3) and be recorded per the repo's evidence rule (hard rule 4
   in `AGENTS.md`) before being used here.
2. **Processor/compiler spec.** In this proof, Ghidra auto-detected
   `x86:LE:32:default:windows` correctly from the PE header for a same-class (32-bit x86,
   Windows PE, no modern subsystem tricks) binary -- expect the same for `StarCraft.exe`, but
   verify the `Using Language/Compiler:` line in the run log. If it ever picks something else,
   force it with `-Processor 'x86:LE:32:default'` (the wrapper passes this straight to
   `analyzeHeadless -processor`).
3. **Image base.** Ghidra reads the PE's preferred `ImageBase` from the optional header and
   loads there by default -- this should just work for a normal PE import (unlike a raw memory
   dump, which would need `-loader BinaryLoader -loader-baseAddr`). If any offset table from
   prior art (`research/prior-art.md` §2-3) is expressed relative to a specific load base,
   confirm it matches what Ghidra reports for `ImageBase` before trusting a cross-reference; use
   `-ImageBase 0x<hex>` (-> `-loader-imagebase`) only if that ever needs to be forced.
4. **No PDB.** `PdbUniversalAnalyzer` will report "failed to locate PDB file" and skip, same as
   in the benign-PE run above -- expected and harmless; there is no public PDB for this binary.
5. **Never point the analyzed file, or anything derived from it, at Battle.net or any online
   service** (hard rule 3) -- this pipeline is offline static analysis only.
6. **Never commit `StarCraft.exe`, a Ghidra project analyzing it, or exported text that
   reproduces game content** -- only addresses/struct findings with evidence belong in
   `research/`.
