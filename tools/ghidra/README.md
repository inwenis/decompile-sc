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
| Install path | `C:\decompile-sc-data\re-tools\ghidra_12.1.2_PUBLIC\` -- OUTSIDE every worktree and repo, see below |

Hash confirmed two ways: matches the `digest` field on the GitHub release asset, and matches
the SHA-256 published in the release notes body.

## Install location: outside every worktree and repo

The install must live **outside every worktree and repo**, at the shared path
`C:\decompile-sc-data\re-tools\ghidra_12.1.2_PUBLIC\`, with `GHIDRA_INSTALL_DIR` pointed at it (user scope, so
every new shell/agent picks it up without re-setting it). `analyze.ps1` already resolves the
install dir in this order: `-GhidraInstallDir` param, then `$env:GHIDRA_INSTALL_DIR`, then a
single auto-discovered `ghidra_*/` directory next to the script -- setting the env var once is
enough, no code change or per-invocation flag needed.

Why this matters: the install is gitignored, so it is invisible to git. If it lives inside a
worktree (e.g. the old `tools/ghidra/ghidra_12.1.2_PUBLIC/` path this doc used to document),
merging and pruning that worktree silently deletes the install along with it -- git never sees
it, so nothing warns you. This already happened: task 005 lost its toolchain mid-run when the
conductor pruned task 001's worktree, which held the only Ghidra install on the machine. Installing
to a shared path outside every worktree means no worker's worktree prune can ever take it out.

## Install (fresh machine)

```powershell
New-Item -ItemType Directory -Path C:\decompile-sc-data\re-tools -Force | Out-Null
cd C:\decompile-sc-data\re-tools
Invoke-WebRequest -Uri 'https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_12.1.2_build/ghidra_12.1.2_PUBLIC_20260605.zip' -OutFile ghidra_12.1.2_PUBLIC_20260605.zip
$hash = (Get-FileHash ghidra_12.1.2_PUBLIC_20260605.zip -Algorithm SHA256).Hash
if ($hash -ne 'B62E81A0390618466C019C60D8C2F796CED2509C4C1AEA4A37644A77272CF99D') { throw "hash mismatch: $hash" }
Expand-Archive ghidra_12.1.2_PUBLIC_20260605.zip -DestinationPath .
[Environment]::SetEnvironmentVariable('GHIDRA_INSTALL_DIR', 'C:\decompile-sc-data\re-tools\ghidra_12.1.2_PUBLIC', 'User')
```

Extracts to `C:\decompile-sc-data\re-tools\ghidra_12.1.2_PUBLIC\` (note: the top-level folder inside the zip is
named after the version, not the dated asset filename). Delete the zip once extraction is
verified -- `Remove-Item ghidra_12.1.2_PUBLIC_20260605.zip` -- there's no reason to keep an
extra 546 MB around. The `[Environment]::SetEnvironmentVariable(..., 'User')` call sets it for
future shells; the shell you ran it in needs `$env:GHIDRA_INSTALL_DIR = 'C:\decompile-sc-data\re-tools\ghidra_12.1.2_PUBLIC'`
(or a restart) to pick it up immediately. Neither the zip nor the extracted install should ever
end up under a repo or worktree path -- they'd be gitignored there too, which is exactly the
silent-prune trap above.

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

Also writes `.ghidra-analyze-manifest.properties` to `OutDir` -- the run's result record
(resolved function name/entry point, which output files belong to it). Other useful flags:
`-SkipListing` (skip the full disassembly export -- it's regenerated in full on every run, and
that's tens of MB on a StarCraft.exe-sized binary if you only need the decompiled C),
`-DecompileTimeoutSecs <n>` (default 60; raise it for large functions), `-Processor` /
`-CompilerSpec` (force the Ghidra language/compiler ID). Full parameter docs:
`Get-Help ./tools/ghidra/analyze.ps1 -Full`.

The wrapper creates a throwaway Ghidra project under `tools/ghidra/ghidra_projects/run-<id>/`
(gitignored; a fresh GUID-suffixed directory per run so concurrent invocations never collide on
Ghidra's project lock, cleaned up in a `finally` block, and also passed `-deleteProject` so
Ghidra itself removes it after the run). `OutDir` is reused across runs -- since
`analyzeHeadless` can exit 0 even when the post-script threw (it logs "REPORT SCRIPT ERROR" and
carries on), and a plain "does some `.c` file exist" check would just find a PREVIOUS run's
output, the wrapper instead deletes any old manifest before the run and requires a freshly
written `status=OK` manifest referencing output files that actually exist -- that's the only
signal that's specific to *this* run. A missing/stale manifest, or a referenced file that
doesn't exist, is a hard failure.

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

## Whole-binary decompile with names

`decomp-all.ps1` writes every function of `StarCraft.exe` as C, one file per function, after
importing the [Magnetar](https://github.com/joankaradimov/Magnetar) 1.16.1 tables (MIT, pinned
by commit in `magnetar-names.ps1`): function names, prototypes, register calling conventions,
structs, enums and typed globals. The result reads `unit->orderID != ORD_DIE` where plain
Ghidra prints `*(char *)(param_1 + 0x4d) != '\0'`.

```powershell
./tools/ghidra/decomp-all.ps1     # about 5 minutes; imports afresh every run
```

Needs the pinned Ghidra above, the working copy `C:\decompile-sc-data\sc-work\1161-base\StarCraft.exe`, and the
network once (Magnetar sources are cached under `C:\decompile-sc-data\sc-work\ghidra\magnetar`). The project lives
in `C:\decompile-sc-data\sc-work\ghidra`, outside every worktree. Output lands in `C:\decompile-sc-data\sc-work\decomp\StarCraft.exe\`:

| File | What |
|---|---|
| `0x<ENTRY>.<name>.c` | decompiled C, one file per function, named by its entry address |
| `index.tsv` | per function: `funcEntry`, `funcName`, `nameSource`, `bodyBytes`, `cFile`, `cLines`, `status`; `funcEnd` ends the entry's own chunk only |
| `ranges.tsv` | per contiguous body range: `start`, `end` (inclusive), `funcEntry`, `funcName`, `cFile` |
| `names.tsv` | the table as applied: `kind` (func/data), `addr`, `name`, `conv`, `proto`, `storage`, `origin` (magnetar/repo) |
| `types.txt` | one line per struct field (`CUnit +0x04D  1  Order  orderID`) and per enum value (`Order 0x0  ORD_DIE`) |
| `listing.asm` | the whole `.text` as `objdump -d -M intel` |
| `types-report.txt`, `names-report.txt` | what applied, what was clamped or failed, the Function ID count |

Plus one `.log` per step and the `*.manifest` success markers.

### Reading it

```powershell
$d = 'C:\decompile-sc-data\sc-work\decomp\StarCraft.exe'
Get-ChildItem $d -Filter '*updateFog*'                       # a function by name
Get-ChildItem $d -Filter '0x0041E0D0.*'                      # ... by entry address
$a = 0x004BCDF3                                              # a CODE address -> its function
Import-Csv "$d\ranges.tsv" -Delimiter "`t" | Where-Object { [uint32]$_.start -le $a -and $a -le [uint32]$_.end }
$a = 0x006284B6                                              # a DATA address -> the global at or below it
Import-Csv "$d\names.tsv" -Delimiter "`t" | Where-Object { $_.kind -eq 'data' -and [uint32]$_.addr -le $a } | Sort-Object { [uint32]$_.addr } | Select-Object -Last 1
Select-String "$d\types.txt" -Pattern '^CUnit \+0x04D '      # a struct offset -> its field
Select-String "$d\types.txt" -Pattern '^Order '              # an enum's values
Select-String "$d\listing.asm" -Pattern '^\s+4bcdf8:' -Context 3,8     # the asm: an instruction start, lower-case hex, no 0x
Select-String -Path "$d\*.c" -Pattern '\bBWFXN_RefreshTarget\b'        # references, one line per hit
Select-String tools/plugin/src/sc_addresses.h, research/*.md -Pattern '0041E0D0'   # this repo's evidence
```

- **Provenance** is `nameSource` in `index.tsv`. `USER_DEFINED` = this repo's verified name, from
  `tools/ghidra/magnetar-overrides.tsv`, one evidence line per row. `IMPORTED` = a Magnetar
  hypothesis. `ANALYSIS` = Ghidra's own Function ID (statically linked CRT) or RTTI. `DEFAULT` =
  no name anywhere (`FUN_`). Hard rule 4 applies: a name is a reading aid, not a finding.
- **References.** A name grep finds direct calls and pointer stores (`active_menu_handler = options_menu_handler;`),
  plus the function's own file. A call through a table or a register never names its target, so
  no hit is not "no callers" (AGENTS.md § "Claims about the binary"). A function that jumps into
  another's shared tail decompiles with that tail inlined, so a hit can be code it reaches rather
  than a call it contains: 21 of the 45 files naming `BWFXN_RefreshTarget` are such stubs, and its
  29 call instructions sit in 24 functions (grep `listing.asm` for `call   0x41e0d0`). A field
  name can belong to several structs (`orderID` is also in `COrder`).
- **Register conventions.** `/* WARNING: Unknown calling convention */` marks custom storage read
  from Magnetar's inline-asm wrapper. The `storage` column in `names.tsv` spells it out:
  `left=EAX;bottom=EDX;top=ECX;right=S4` means `right` is the first stack dword above the return
  address. `__thiscall` is spelled out the same way (`this_` in `ECX`), so `this_` keeps its type.
- **Partial access.** `active_players._4_4_` is 4 bytes at offset 4 inside that global.

### Where Magnetar is wrong

A cross-check of 561 addresses this repo verified (`sc_addresses.h`, `tools/ghidra/specs/*.spec`)
against the table: 391 agree, 140 have nothing to compare, 30 looked like conflicts. An adversarial
second pass left 8 real ones:

| Address | Magnetar says | The evidence says | Handled |
|---|---|---|---|
| `0x004669B0` | `getQueuedUnitCount` | returns a free slot's index: `findFreeBuildQueueSlot` | override |
| `0x004CE8A0` | `techIsResearchedSCBW` | reads the availability array: `techIsAvailable` | override |
| `0x00424BA0` | `setSpellSpecialBtnGraphic` | walks `CUnit.loadedUnitIndex[8]`: `drawStatusLoadedUnits` | override |
| `0x006284B4` / `B6` | `map_height_pixels`, an int | a u16, then the u8 `selectionIterator` | override |
| `layer+0x00` | `buffers` | the layer's in-use flag | field name kept, [#191](https://github.com/inwenis/decompile-sc/issues/191) |
| `StatDataDescriptor+0x00` | `CUnit* xxx` | the icon's GRP handle | field name kept, [#191](https://github.com/inwenis/decompile-sc/issues/191) |
| `0x00512678` | `g_ActiveNationID` | Magnetar is right: the commanding player, not the local one | repo comment fixed, [#191](https://github.com/inwenis/decompile-sc/issues/191) |
| `0x006D1218` | `loadGameFileHandle` | Magnetar is right: a `FILE*` closed by `_fclose` | repo comment fixed, [#191](https://github.com/inwenis/decompile-sc/issues/191) |

So neither side wins by default: where they disagree, read the evidence each cites.

### How it is built, and what proves it

1. `ApplyTypes.java` creates Magnetar's enums with their declared width first, then parses its
   struct header. Ghidra's C parser sizes every enum as an int and has no `enum X : T`; without
   the pre-sized enums, 70 of the 271 struct sizes come out wrong (negative control, run once).
   Every struct is checked against the header's own `static_assert(sizeof(X) == N)`: all 271
   match, `CUnit` at 336 bytes included.
2. `ApplyNames.java` names functions and globals, applies prototypes, and gives register-convention
   functions custom storage parsed from the asm wrappers (`mov ecx, top` / `push dword ptr right`).
   A table entry Ghidra never reached is disassembled and made a function; once all entries
   exist, its body and the body of the function it sat inside are recomputed. A function Ghidra's Function ID already named keeps that
   name and signature. Rows of `magnetar-overrides.tsv` replace Magnetar's before any of this.
3. `DecompileMany.java ALL` decompiles every non-thunk function.

| Result of one run | Count |
|---|---|
| Functions decompiled / failed | 6304 / 0 |
| Named by Ghidra's Function ID or RTTI (`ANALYSIS`) | 265 |
| Named by Magnetar (`IMPORTED`) / by this repo (`USER_DEFINED`) | 3840 / 3 |
| Unnamed (`FUN_`) | 2196 |
| Table entries where Ghidra had no function, disassembled and created | 1825 |
| Created functions whose body did not resolve (not a bare `RET`) | 1 |
| Prototypes: standard convention / register wrapper / `__thiscall` | 3006 / 2682 / 260 |
| Prototypes not applied | 2 |
| Structs + unions / enums imported | 277 / 63 |
| Globals named / typed (read back) / arrays clamped to the next global | 962 / 889 / 3 |

The two prototypes not applied: a varargs wrapper (`__snprintf`) has no fixed storage, and one
function takes `time_t`, which Ghidra's Windows archive sizes at 8 bytes where this binary's
compiler used 4. The clamped arrays are Magnetar declarations that run into the next global:
`ScreenLayers` is `layer[12]` but `GameScreenBuffer` starts at its ninth element, and
`Unit_AttackUnitOrder[228]` stops at 31 because `order_id` sits inside it. The clamp keeps both
declarations without deciding which one Magnetar got wrong; `names-report.txt` lists all three.

Against plain Ghidra (same binary, same decompiler, no Magnetar), counted over all output:

| | Plain Ghidra | With Magnetar |
|---|---|---|
| Functions found and decompiled | 4499 | 6304 |
| Lines reading a register the prototype does not model (`in_EAX`, `unaff_ESI`...) | 21535 | 3352 |
| Raw offset casts, `*(T *)(p + 0x4d)` | 12178 | 1915 |
| Files with struct field access (`->`) | 68 | 2986 |
| Distinct unnamed callees / globals (`FUN_` / `DAT_`) | 4233 / 2946 | 2196 / 1570 |

The remaining register reads sit in 685 functions: 612 whose Magnetar prototype leaves out a
register argument (`isUnitBurrowed` is declared `int (void)` and reads its unit from `EAX`), the 2
whose prototype was not applied, and 71 that Magnetar does not list.

Never point `build-opcode-policy.ps1` or `build-command-table.ps1` at `C:\decompile-sc-data\sc-work\ghidra`: they
parse `FUN_` names out of decompiled C and keep their own unnamed project. Ghidra locks a
project to one process, so nothing else may hold `C:\decompile-sc-data\sc-work\ghidra` while this runs.

## What StarCraft.exe 1.16.1 will need beyond this

The target (`research/prior-art.md` §6, §8) is a 32-bit x86 PE from a 1998-era/2009 Blizzard
build (VC6-class toolchain), no debug symbols, no public `.idb`/`.gzf`. Verified sizes:
`StarCraft.exe` 1,220,608 bytes (1.16 MB), `storm.dll` 409,600 bytes, `battle.snp` 557,310
bytes -- total code surface ~2.2 MB (an earlier draft of this doc said "~2.7 MB `StarCraft.exe`",
which was wrong). Differences from the benign-PE proof above:

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
   loads there by default -- this should just work for a normal PE import. If any offset table
   from prior art (`research/prior-art.md` §2-3) is expressed relative to a specific load base,
   confirm it matches what Ghidra reports for `ImageBase` before trusting a cross-reference.
   **A PE's image base cannot be forced via a loader option**: `-loader-imagebase` is an
   `ElfLoader`-only argument (confirmed against `analyzeHeadlessREADME.md`'s per-loader
   argument lists and by testing it against a PE -- Ghidra prints
   `Skipping unsupported -loader-imagebase argument` and silently keeps the header's base, which
   is why `analyze.ps1` does not expose an `-ImageBase` flag at all). If StarCraft.exe is ever
   analyzed as a raw memory dump instead of a PE, that's `-loader BinaryLoader
   -loader-baseAddr <hex>`; to rebase an already-imported PE program, that's a script calling
   `currentProgram.setImageBase(addr, true)` before analysis runs -- neither is implemented
   here since the PE-import path hasn't needed it.
4. **No PDB.** `PdbUniversalAnalyzer` will report "failed to locate PDB file" and skip, same as
   in the benign-PE run above -- expected and harmless; there is no public PDB for this binary.
5. **Never point the analyzed file, or anything derived from it, at Battle.net or any online
   service** (hard rule 3) -- this pipeline is offline static analysis only.
6. **Never commit `StarCraft.exe`, a Ghidra project analyzing it, or exported text that
   reproduces game content** -- only addresses/struct findings with evidence belong in
   `research/`.
