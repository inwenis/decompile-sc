# Prior art: StarCraft (Brood War) reverse engineering

Survey date: 2026-08-06. Scope: public material only. Unverified claims are flagged inline as **[unverified]**.
No addresses/offsets are reproduced here on purpose — link targets carry them.

---

## 1. Open-source reimplementations

| Project | Link | What it is | Alive? |
|---|---|---|---|
| OpenBW | https://github.com/OpenBW/openbw | C++ reimplementation of the 1.16.1 game *simulation*. Core is one huge header, [`bwgame.h`](https://github.com/OpenBW/openbw/blob/master/bwgame.h). Requires original MPQs for assets/data. UI optional (SDL2, `OPENBW_ENABLE_UI`). | Low activity but functional; the community's reference sim |
| OpenBW/bwapi | https://github.com/OpenBW/bwapi | BWAPI 4.2 fork using OpenBW as backend instead of the real game — headless bot matches, replay analysis at speed | Maintained enough to be used by AI community |
| tsc-bw | https://github.com/tscmoo/tsc-bw | Predecessor of OpenBW by tscmoo (Vegard Mella). README stresses that sim accuracy must be exact or replays/multiplayer desync — that constraint forced 1:1 logic reimplementation | Dead — repo redirects to OpenBW |
| Magnetar | https://github.com/joankaradimov/Magnetar | Hybrid: loads original `StarCraft.exe` into memory, layers custom C++/LuaJIT on top. Not a from-scratch engine | Niche, ~2.1k commits, small community (28 stars) |
| Stargus (Stratagus) | https://github.com/Wargus/stargus **[unverified exact repo]**, engine: https://en.wikipedia.org/wiki/Stratagus | StarCraft on the generic Stratagus RTS engine. Not faithful — different engine semantics. Lineage: FreeCraft → C&D from Blizzard (2003) → Stratagus | Effectively dead / partial; killed by C&D history + never reaching gameplay parity |
| screp / OpenBW web replay viewer | http://www.openbw.com/replay-viewer/ **[site cert broken as of survey date — could not fetch]** | OpenBW compiled to JS, plays .rep in browser | Existence verified via README references only |

Key takeaways:
1. OpenBW is effectively a **behavioral decompilation** of the whole game sim — unit orders, pathing, iscript execution — validated by replay sync. It is the single best "what does this function actually do" oracle.
2. OpenBW deliberately does NOT reimplement: rendering pipeline details, Battle.net networking, menus/glue UI. Those are the least-documented parts of the binary.
3. Dead projects (Stargus) died from: non-faithful engine ⇒ perpetual "not really SC" status, plus Blizzard legal pressure era (see bnetd, https://en.wikipedia.org/wiki/Bnetd).

## 2. BWAPI and the injected-DLL ecosystem

- Main repo: https://github.com/bwapi/bwapi — DLL injected into `StarCraft.exe` 1.16.1. Works only on 1.16.1 (see §6).
- What it proves: a stable, community-validated map of 1.16.1's live memory. BWAPI reads/writes game state directly through declared structs; thousands of bots ran on it for a decade without crashes — that is strong empirical validation of the struct layouts.
- Where the knowledge lives (all in `bwapi/bwapi/BWAPI/Source/BW/`):
  1. [`Offsets.h`](https://github.com/bwapi/bwapi/blob/main/bwapi/BWAPI/Source/BW/Offsets.h) — global variable addresses.
  2. `CUnit.h`, `CSprite.h`, `CImage.h`, `CBullet.h`, `COrder.h`, `CThingy.h` — the core entity structs.
  3. `Structures.h`, `Constants.h`, `Pathing.h`, `TriggerEngine.h`, flag headers (`UnitStatusFlags.h`, `MovementFlags.h`, …).
  (Directory contents verified against the GitHub tree.)
- OpenBW's data layer (`bwdata`-style structures inside `bwgame.h`, `game_types.h`, `data_types.h`, `bwenums.h`) is the same knowledge re-expressed as portable C++ instead of raw offsets.
- Effectively: BWAPI BW/ headers + GPTP (below) + OpenBW = a partial decompilation of the data model already done. What is NOT covered: function-level code (control flow inside StarCraft.exe), renderer, sound, Battle.net/storm networking internals.

## 3. Public offset/struct/symbol sources for 1.16.1

| Source | Link | What it holds |
|---|---|---|
| BWAPI `BW/` headers | see §2 | Globals + entity structs, C++ |
| GPTP (General Plugin Template Project) | https://github.com/BoomerangAide/GPTP and older https://github.com/SCMapsAndMods/general-plugin-template-project | Hook points into `StarCraft.exe` functions + `SCBW/structures/*` (e.g. [`Cunitlayout.h`](https://github.com/BoomerangAide/GPTP-For-VS2008/blob/Update-4/GPTP/SCBW/structures/Cunitlayout.h)). Function-level hooks = partial function symbol table |
| samase ecosystem (neivv) | https://github.com/neivv/samase_plugin (API + 1.16.1 shim), https://github.com/neivv/samase_scarf (automatic address finder), https://github.com/neivv/scarf (x86 analyzer lib) | `samase_scarf` finds function/global addresses in SC binaries **automatically by code-pattern analysis** — updated Jul 2026, very alive. README carries a caveat about an exe format it can't analyze **[meaning unverified — possibly the 64-bit or protected SC:R exe]** |
| teippi | https://github.com/neivv/teippi | 1.16.1 "limitless" plugin, C++ — large body of reversed structs/logic. Dead (last update 2018) but source remains useful |
| EUD community DB | https://gist.github.com/wdcqc/54df5ad49f7d5887a8f84c2ac0cd86ef, https://staredit-network.fandom.com/wiki/EUDs | EUD mapping culture produced address tables for readable/writable game memory (deaths-table overflow arithmetic documented publicly) |
| EUD emulator talk (Blizzard-sanctioned) | https://0xeb.net/2018/02/starcraft-emulating-a-buffer-overflow-for-fun-and-profit-recon-brussels-2018/ + PDF https://0xeb.net/wp-content/uploads/2018/02/StarCraft_EUD_Emulator.pdf | REcon 2018: how SC:R **emulates the 1.16.1 memory layout** to keep EUD maps working. Authoritative confirmation that 1.16.1's memory map is a de-facto public spec |
| starcraftai.com wiki | https://www.starcraftai.com/wiki/Main_Page (e.g. https://www.starcraftai.com/wiki/CHK_Format) | Community wiki with structure/offset pages; partially bit-rotted |
| staredit.net forums | e.g. https://staredit.net/361724/ (reverse engineering thread) | Long-tail: scattered offsets, EXE-edit lists. Search per topic |

storm.dll specifically: no single public struct DB found for SC's `storm.dll` **[searched, not found — flagged]**. Practical substitutes: StormLib reimplements the MPQ half (https://github.com/ladislav-zezula/StormLib); Devilution reimplemented many Storm entry points for Diablo, same-era DLL (https://github.com/galaxyhaxz/devilution); SNP/network half of storm is partially reversed in ShieldBattery's code (§5).

Nothing like a published IDA `.idb` / Ghidra `.gzf` for `StarCraft.exe` 1.16.1 was found on GitHub or moddb **[searched multiple phrasings; absence not proven]**. The community equivalents are the header collections above.

## 4. File formats, ranked by documentation completeness

| Rank | Format | Docs quality | Canonical docs | Reusable parsers |
|---|---|---|---|---|
| 1 | MPQ archive | Excellent — fully solved for 20+ years | http://www.zezula.net/en/mpq/mpqformat.html | **StormLib** (C++, canonical) https://github.com/ladislav-zezula/StormLib; Go https://github.com/icza/mpq; Python `mpyq` **[not re-verified]**; JS extractor https://github.com/ShieldBattery/scm-extractor |
| 2 | Replay `.rep` | Excellent — legacy + modern both parsed | screp source is the living spec: https://github.com/icza/screp (`repparser/`) | **screp** (Go, legacy+modern); **jssuh** (JS) https://github.com/ShieldBattery/jssuh; screp-js https://github.com/msikma/screp-js; screparsed https://github.com/evanandrewrose/screparsed |
| 3 | CHK (scenario) | Excellent — every section documented incl. the 2400-byte TRIG records | https://staredit-network.fandom.com/wiki/Scenario.chk, mirror http://www.staredit.net/wiki/index.php/Scenario.chk, https://www.starcraftai.com/wiki/CHK_Format | **bw-chk** (JS) https://github.com/ShieldBattery/bw-chk; **broodmap** (Rust, MPQ+CHK, WIP) https://github.com/ShieldBattery/broodmap; **richchk** (Python) https://github.com/sethmachine/richchk; Chkdraft's C++ core https://github.com/jjf28/Chkdraft |
| 4 | SCM/SCX | Trivial once MPQ+CHK known (SCM/SCX = MPQ containing `staredit\scenario.chk`) | same as above | same as above |
| 5 | DAT tables (units.dat, weapons.dat, flingy/sprites/images/orders/…) | Good — field-by-field for 1.16.1, array-of-columns layout | https://www.darkenedfantasies.com/resources/?i=sc_fmt_dat; https://staredit-network.fandom.com/wiki/Modding_Files_Overview | PyMS/PyDAT (Python) https://github.com/poiuyqwert/PyMS; neivv's `tatti3` (SC:R ext dats) https://github.com/neivv/tatti3; DatEdit (binary only, old) |
| 6 | GRP sprites + PCX palettes | Good — format simple, multiple independent implementations | https://sourceforge.net/p/stratlas/wiki/GRP/; SEN wiki | libgrp (C) https://github.com/Stratagus/libgrp; PyGRP in PyMS; RetroGRP **[repo not located]** |
| 7 | iscript.bin (animation VM) | Good — opcode set fully known via IceCC/PyICE | https://staredit-network.fandom.com/wiki/IceCC; Ice-XP manual https://documentation.help/Ice-XP/documentation.pdf | IceCC (decompiler/compiler); PyICE in PyMS; **aice** (modern reimplementation of the iscript VM, Rust) https://github.com/neivv/aice — its Documentation.md doubles as a semantics spec |
| 8 | TRG (standalone triggers) | OK — same 2400-byte trigger struct as CHK TRIG, ±8-byte header quirks | https://staredit-network.fandom.com/wiki/Adding_.trg_headers_to_a_.got_template + Scenario.chk TRIG section | Chkdraft; euddraft toolchain https://github.com/phu54321/euddraft |
| 9 | SMK video | Fully solved outside SC community | https://wiki.multimedia.cx/index.php/Smacker | libsmacker (C, LGPL) https://github.com/JonnyH/libsmacker; FFmpeg demuxer/decoder |
| 10 | Audio (WAV in MPQ, ADPCM compression inside MPQ sectors) | Solved as part of MPQ spec | zezula.net MPQ pages | StormLib handles decompression |

Rule of thumb: **no file format needs original RE work.** Everything above is parse-by-copying. The open ground is executable code, not data files.

## 5. Modding-tool lineage and what it reveals

1. **StarEdit** (Blizzard) → **ScmDraft 2** (http://www.stormcoast-fortress.net/) → **Chkdraft** (https://github.com/jjf28/Chkdraft) → **ChkForge** (https://github.com/heinermann/ChkForge, uses OpenBW as live preview backend). Reveals: complete CHK semantics incl. quirks StarEdit itself gets wrong.
2. **DatEdit** → **PyMS/PyDAT** (https://github.com/poiuyqwert/PyMS, fork maintained by neivv) → **tatti3**. Reveals: full DAT schema + which fields the engine actually reads.
3. **MPQDraft** (self-executing mod patcher, in-memory MPQ priority) — **[repo not verified; historically Justin Olbrantz]** → **FireGraft**: button sets, tech requirements, and a catalog of known EXE edits for 1.16.1; loads plugins (`.qdp`). Reveals: a curated list of patchable code sites in the binary.
4. **GPTP** (§3): the standard "write C++, hook into StarCraft.exe functions" template. Its hook list is a de-facto function index of the exe.
5. **samase** (§3): modern plugin loader, works on 1.16.1 *and* SC:R by finding addresses at runtime via `samase_scarf`. The most technically advanced injection stack in the community.
6. **BWAPI injectors** (§2) + **bwapi-bot-loader** (https://github.com/tscmoo/bwapi-bot-loader): runs BWAPI bots without the real game **[scope partially verified]**.
7. **ShieldBattery** (https://github.com/ShieldBattery/ShieldBattery): full modern multiplayer platform; open-source client-side injection, network stack replacement (SNP), plus the parser family (bw-chk, jssuh, scm-extractor, broodmap). Actively developed. Reveals: how to replace storm networking and drive the game headless-ish in practice.
8. **EUD toolchain**: euddraft/eudplib (https://github.com/phu54321/euddraft), EUD Editor 3 (https://github.com/Buizz/EUD-Editor-3), LangUMS (https://github.com/LangUMS/langums). Reveals: which memory the trigger engine can reach, i.e. an address-space usage map maintained by mapmakers.

## 6. Version split: 1.16.1 vs 1.18+ vs Remastered

| Version | Date | Status for RE |
|---|---|---|
| 1.16.1 | Jan 2009 | Frozen forever. Every offset table, BWAPI, GPTP, FireGraft, teippi, OpenBW target THIS exact binary. The de-facto research substrate |
| 1.18 | Mar 2017 | Blizzard-modernized rebuild of the classic codebase (new compiler/toolchain, windowed mode, UTF-8, new backends — patch notes: https://news.blizzard.com/en-us/starcraft/20674424/starcraft-brood-war-patch-1-18-patch-notes). All 1.16.1 addresses invalid. BWAPI never ported (https://github.com/bwapi/bwapi/issues/673). Game made free |
| Remastered 1.20+ | Aug 2017– | Same modernized engine + new asset pipeline (CASC storage → CascLib https://github.com/ladislav-zezula/CascLib). Continuous patches ⇒ address churn every update |

Why the community stays on 1.16.1:
1. Static binary → offsets never rot.
2. Deep EXE edits (FireGraft-class) impossible/impractical on Remastered (community consensus: https://staredit-network.fandom.com/wiki/Format_comparison:_StarCraft_classic_vs._Remastered, http://pr0nogo.wikidot.com/rs-starter).
3. All legacy tooling (BWAPI/GPTP/plugins) simply works.
4. Remastered runs side-by-side with an installed 1.16.1, so nothing forces migration.

Modern-client protections: Remastered added an **EUD emulator** (patch 1.21: https://news.blizzard.com/en-us/starcraft/21313396/patch-1-21-0-the-return-of-eud-maps) that virtualizes reads/writes against an emulated 1.16.1 memory map, with per-address read/write permissions — designed by/with Elias Bachaalany (REcon 2018 talk, §3). No public evidence found of heavy packing/VM protection on the SC:R exe; the practical barriers are patch churn and lack of stable public offsets, and `samase_scarf` exists precisely to re-find addresses per patch **[protection status unverified beyond this]**.

Implication: target 1.16.1. Anything learned transfers conceptually (game rules identical — SC:R stays replay-compatible) but not address-wise.

## 7. Decompilation methodology from other projects

| Project | Model | Organizational lessons |
|---|---|---|
| sm64 (https://github.com/n64decomp/sm64) | **Matching decomp**: C that recompiles byte-identical with original toolchain | Splitting: binary cut into per-file/per-function units with **splat** (https://github.com/ethteck/splat); progress measured as % matched; nonmatching functions merged behind `#ifdef NON_MATCHING` so work parallelizes without blocking; verification is `sha1sum` of rebuilt ROM — zero-argument correctness |
| OpenRCT2 (https://github.com/OpenRCT2/OpenRCT2) | **Incremental replacement**: reimplemented one function at a time into a DLL that interops with the original exe; unknown globals referenced by raw address until named; original binary dependence removed only at the end | Best-fit model for a Win32 PE where the original compiler is unknown ⇒ byte-matching is impractical. The hooks-coexistence phase gives a runnable game the whole time |
| re3 / GTA III (mirror https://github.com/halpz/re3; original DMCA'd — https://archive.org/details/github.com-GTAmodding-re3_-_2021-02-15_02-11-20) | Non-matching full reversal, "replace parts one by one such that a working game is maintained at all times" | Same incremental-replacement lesson + **legal lesson: Take-Two DMCA'd and sued.** Blizzard has its own history (bnetd). Keep repo private, never ship assets, never ship original code |
| Devilution / Diablo (https://github.com/galaxyhaxz/devilution) | Non-matching reversal of a same-era Blizzard Win32 title; ~1200 h solo | Force multiplier was the **debug build with asserts/symbols shipped on the CD** (D1221A.MPQ). Action item: check old SC betas/press builds for symbol-bearing binaries **[existence of such an SC build unverified]**. Also: goal was "bug-for-bug accurate," which gave an unambiguous done-criterion per function |
| ScummVM | Clean-room engine reimplementation validated against game data + observed behavior | When byte-matching is off the table, the correctness oracle becomes *data + behavior*, i.e. exactly what OpenBW already provides for SC |
| Cross-project tooling | — | decomp.me (collab function matching), objdiff, m2c, decomp-permuter — built for console matching decomps; partially applicable to MSVC-era x86 **[tool fit for VC6-era PE not verified]**. Progress dashboards: https://decomp.dev/projects |

Organizational synthesis for cutting tasks:
1. Function = unit of work; struct/global naming = shared substrate maintained centrally (single Ghidra project or committed symbol file).
2. Every task needs a mechanical done-criterion. For SC: "decompiled function's behavior matches OpenBW's equivalent / replay stays in sync when this function is swapped in via a GPTP/samase hook."
3. Incremental-replacement (OpenRCT2 model) >> matching decomp for this binary: unknown MSVC toolchain, and OpenBW already exists as a behavior oracle — byte-matching adds cost without adding truth.
4. Keep a generated, committed address/symbol map (like OpenRCT2's early address tables; like samase_scarf's automated finder) so parallel workers never hand-collide on naming.

## 8. Tooling for a 1998-vintage 32-bit PE

1. **Ghidra** (https://github.com/NationalSecurityAgency/ghidra): free, fine on 32-bit x86 PE; headless `analyzeHeadless` scripting (Java/Python) enables scripted bulk export of decompiled C, symbol application from JSON, diffable project state — right choice for a multi-agent pipeline since every worker can run it.
2. **IDA Pro**: still the reference interactive experience + FLIRT signatures for old MSVC runtimes (useful: 1.16.1 statically links CRT era code). License cost blocks parallel agents.
3. **Binary Ninja**: good decompiler + real Python API; per-seat cost again.
4. Published SC-specific Ghidra/IDA scripts or databases: **none found** on GitHub for StarCraft **[searched; absence not proven]**. Closest public equivalents: `samase_scarf` (automated address finding, Rust — portable into a Ghidra-symbol generator), BWAPI/GPTP headers (importable as Ghidra data types via C-parser).
5. Useful adjacent: scarf (https://github.com/neivv/scarf) x86 analyzer; ia32rtools (used to run SC on ARM, https://news.ycombinator.com/item?id=7372414).

Practical stack: Ghidra project as ground truth + import BWAPI `BW/` structs as data types + seed symbols from GPTP hook list + verify semantics against `bwgame.h`.

## Highest-value first targets

Ranked. Criteria: (a) documentation density, (b) genuine interest.

1. **Unit/entity data model (CUnit, CSprite, CImage, CBullet)** — richest public prior art of any subsystem (BWAPI headers + GPTP + OpenBW types); importing it into Ghidra instantly types thousands of code references. Do first: everything else keys off it.
2. **DAT loading + game-data plumbing** — units.dat/weapons.dat schemas fully public; loader code in the exe is simple array-column reads; fast wins that name many globals.
3. **iscript VM (animation interpreter)** — closed opcode set, two independent reimplementations (IceCC semantics, neivv's aice) to diff against; a small, self-contained interpreter loop — ideal early decomp unit.
4. **Order/AI state machine (COrder + orders.dat dispatch)** — BWAPI exposes order IDs, OpenBW implements the semantics; big switch-dispatch structure decomposes naturally into one-task-per-order parallel work.
5. **Trigger engine (TRIG/EUD path)** — 2400-byte record spec is complete, EUD community mapped its memory reach, Blizzard's own EUD-emulator talk documents behavior; genuinely interesting (it's the famous exploit surface).
6. **Pathfinding (regions, contours)** — high interest (legendary subsystem), moderate docs (BWAPI `Pathing.h`, OpenBW implementation); harder, but OpenBW gives a full behavioral reference.
7. **Replay record/playback + command stream** — screp/jssuh fully document the command format; replay = deterministic input stream, making it the natural end-to-end correctness harness (swap in decompiled code, check sync) rather than just a target.
8. **MPQ/storm.dll file I/O layer** — solved by StormLib; decompiling SC's copy is mostly confirmation work. Do late; reuse StormLib knowledge for symbol naming.
9. **Renderer/sound/Battle.net glue** — least public prior art (BWAPI/OpenBW skip it); interesting only after the sim core; networking additionally carries bnetd-shaped legal shadows.
