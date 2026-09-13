#!/usr/bin/env python3
"""Regenerate a PE-anatomy Markdown report from one or more PE files.

Every claim in the output is tagged with the exact PE header field it came
from, so the report stays reproducible instead of hand-typed (task 002).

Usage:
    python tools/pe_report.py <pe-file> [<pe-file> ...] [-o OUT.md]

Example (this repo's baseline):
    python tools/pe_report.py \
        C:/decompile-sc-data/sc-work/1161-base/StarCraft.exe \
        C:/decompile-sc-data/sc-work/1161-base/storm.dll \
        -o research/pe-anatomy.md
"""

import argparse
import hashlib
import sys
from datetime import datetime, timezone
from pathlib import Path

import pefile

SECTION_FLAGS = {
    "CODE": 0x00000020,
    "INITIALIZED_DATA": 0x00000040,
    "UNINITIALIZED_DATA": 0x00000080,
    "EXECUTE": 0x20000000,
    "READ": 0x40000000,
    "WRITE": 0x80000000,
}

SUBSYSTEMS = {
    1: "IMAGE_SUBSYSTEM_NATIVE",
    2: "IMAGE_SUBSYSTEM_WINDOWS_GUI",
    3: "IMAGE_SUBSYSTEM_WINDOWS_CUI",
    5: "IMAGE_SUBSYSTEM_OS2_CUI",
    7: "IMAGE_SUBSYSTEM_POSIX_CUI",
}

DLL_CHARACTERISTICS = {
    0x0040: "DYNAMIC_BASE (ASLR)",
    0x0080: "FORCE_INTEGRITY",
    0x0100: "NX_COMPAT (DEP)",
    0x0200: "NO_ISOLATION",
    0x0400: "NO_SEH",
    0x0800: "NO_BIND",
    0x2000: "WDM_DRIVER",
    0x8000: "TERMINAL_SERVER_AWARE",
}

HIGH_ENTROPY_THRESHOLD = 7.2  # rule of thumb: compressed/encrypted data clusters here


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest().upper()


def characteristic_flags(pe) -> list:
    return [
        name
        for name, val in pefile.retrieve_flags(pefile.IMAGE_CHARACTERISTICS, "IMAGE_FILE_")
        if pe.FILE_HEADER.Characteristics & val
    ]


def dll_characteristic_flags(pe) -> list:
    val = pe.OPTIONAL_HEADER.DllCharacteristics
    return [label for bit, label in DLL_CHARACTERISTICS.items() if val & bit]


def section_flag_letters(characteristics: int) -> str:
    r = "R" if characteristics & SECTION_FLAGS["READ"] else "-"
    w = "W" if characteristics & SECTION_FLAGS["WRITE"] else "-"
    x = "X" if characteristics & SECTION_FLAGS["EXECUTE"] else "-"
    kind = []
    if characteristics & SECTION_FLAGS["CODE"]:
        kind.append("code")
    if characteristics & SECTION_FLAGS["INITIALIZED_DATA"]:
        kind.append("data")
    if characteristics & SECTION_FLAGS["UNINITIALIZED_DATA"]:
        kind.append("bss")
    return f"{r}{w}{x} ({'/'.join(kind) or 'none'})"


def format_imports(pe) -> list:
    out = []
    if not hasattr(pe, "DIRECTORY_ENTRY_IMPORT"):
        return out
    for entry in pe.DIRECTORY_ENTRY_IMPORT:
        dll = entry.dll.decode(errors="replace")
        names = []
        for imp in entry.imports:
            if imp.name:
                names.append(imp.name.decode(errors="replace"))
            else:
                names.append(f"Ordinal#{imp.ordinal}")
        out.append((dll, sorted(names, key=str.lower)))
    return sorted(out, key=lambda t: t[0].lower())


def format_exports(pe) -> list:
    if not hasattr(pe, "DIRECTORY_ENTRY_EXPORT"):
        return []
    out = []
    for exp in pe.DIRECTORY_ENTRY_EXPORT.symbols:
        name = exp.name.decode(errors="replace") if exp.name else None
        out.append((exp.ordinal, name, exp.address))
    return sorted(out, key=lambda t: t[0])


def packing_signals(pe, sections) -> list:
    signals = []
    high_entropy = [s for s in sections if s["entropy"] >= HIGH_ENTROPY_THRESHOLD]
    if high_entropy:
        names = ", ".join(s["name"] for s in high_entropy)
        signals.append(
            f"High entropy (>= {HIGH_ENTROPY_THRESHOLD}) in section(s) {names} — "
            "consistent with compressed/encrypted data, but also normal for "
            ".rsrc icon/bitmap resources. Evidence: pefile section.get_entropy()."
        )
    std_names = {".text", ".data", ".rdata", ".rsrc", ".reloc", ".idata", ".edata", ".bss"}
    unusual = [s["name"] for s in sections if s["name"].lower() not in std_names]
    if unusual:
        signals.append(
            f"Non-standard section name(s): {', '.join(unusual)} — "
            "packers/custom linkers often rename sections. Evidence: IMAGE_SECTION_HEADER.Name."
        )
    n_imported_dlls = len(format_imports(pe))
    if n_imported_dlls <= 1:
        signals.append(
            f"Only {n_imported_dlls} imported DLL(s) — a single-import-thunk pattern "
            "(commonly just KERNEL32.dll: LoadLibrary/GetProcAddress) is typical of packed "
            "binaries that resolve the rest at runtime. Evidence: IMAGE_DIRECTORY_ENTRY_IMPORT."
        )
    warnings = pe.get_warnings()
    if warnings:
        signals.append(
            "pefile parser warnings (malformed/unusual header structure): "
            + "; ".join(warnings[:5])
            + (" ..." if len(warnings) > 5 else "")
        )
    computed_checksum = pe.generate_checksum()
    stored_checksum = pe.OPTIONAL_HEADER.CheckSum
    if stored_checksum != 0 and stored_checksum != computed_checksum:
        signals.append(
            f"OPTIONAL_HEADER.CheckSum (0x{stored_checksum:X}) does not match the recomputed "
            f"checksum (0x{computed_checksum:X}) — file was modified after link, or checksum "
            "was never set correctly."
        )
    if not signals:
        signals.append(
            "No packing/obfuscation signals found by these heuristics (entropy, section "
            "naming, import count, parser warnings, checksum). Consistent with a standard "
            "MSVC-linked binary; does not rule out manual protection schemes not covered here."
        )
    return signals


def analyze(path: Path) -> dict:
    pe = pefile.PE(str(path), fast_load=False)
    pe.parse_data_directories()

    machine = pe.FILE_HEADER.Machine
    machine_name = pefile.MACHINE_TYPE.get(machine, f"UNKNOWN(0x{machine:X})")
    bitness = 64 if pe.OPTIONAL_HEADER.Magic == 0x20B else 32

    timestamp = pe.FILE_HEADER.TimeDateStamp
    try:
        ts_str = datetime.fromtimestamp(timestamp, tz=timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    except (OverflowError, OSError, ValueError):
        ts_str = f"unparseable raw value 0x{timestamp:X}"

    subsystem = pe.OPTIONAL_HEADER.Subsystem
    subsystem_name = SUBSYSTEMS.get(subsystem, f"UNKNOWN({subsystem})")

    sections = []
    for s in pe.sections:
        name = s.Name.rstrip(b"\x00").decode(errors="replace")
        sections.append(
            {
                "name": name,
                "virtual_address": s.VirtualAddress,
                "virtual_size": s.Misc_VirtualSize,
                "raw_size": s.SizeOfRawData,
                "flags": section_flag_letters(s.Characteristics),
                "entropy": s.get_entropy(),
            }
        )

    result = {
        "path": path,
        "size": path.stat().st_size,
        "sha256": sha256_of(path),
        "is_dll": pe.is_dll(),
        "is_exe": pe.is_exe(),
        "machine": machine,
        "machine_name": machine_name,
        "bitness": bitness,
        "image_base": pe.OPTIONAL_HEADER.ImageBase,
        "entry_point_rva": pe.OPTIONAL_HEADER.AddressOfEntryPoint,
        "timestamp_raw": timestamp,
        "timestamp_str": ts_str,
        "subsystem": subsystem,
        "subsystem_name": subsystem_name,
        "linker_version": f"{pe.OPTIONAL_HEADER.MajorLinkerVersion}.{pe.OPTIONAL_HEADER.MinorLinkerVersion}",
        "os_version": f"{pe.OPTIONAL_HEADER.MajorOperatingSystemVersion}.{pe.OPTIONAL_HEADER.MinorOperatingSystemVersion}",
        "size_of_image": pe.OPTIONAL_HEADER.SizeOfImage,
        "size_of_headers": pe.OPTIONAL_HEADER.SizeOfHeaders,
        "num_sections": pe.FILE_HEADER.NumberOfSections,
        "characteristics": characteristic_flags(pe),
        "dll_characteristics": dll_characteristic_flags(pe),
        "sections": sections,
        "imports": format_imports(pe),
        "exports": format_exports(pe),
    }
    result["packing_signals"] = packing_signals(pe, sections)
    pe.close()
    return result


def render_markdown(results: list) -> str:
    lines = []
    lines.append("# PE anatomy")
    lines.append("")
    lines.append(
        "Generated by `tools/pe_report.py` — regenerate with:\n\n"
        "```\n"
        "python tools/pe_report.py <path-to-StarCraft.exe> <path-to-storm.dll> "
        "-o research/pe-anatomy.md\n"
        "```\n\n"
        "Every field below is read directly from the PE headers via `pefile`; "
        "the field name is given as evidence next to each claim."
    )
    lines.append("")

    for r in results:
        lines.append(f"## `{r['path'].name}`")
        lines.append("")
        lines.append(f"- File: `{r['path']}`")
        lines.append(f"- Size: {r['size']:,} bytes")
        lines.append(f"- sha256: `{r['sha256']}`")
        if r["is_dll"]:
            type_evidence = "FILE_HEADER.Characteristics IMAGE_FILE_DLL bit set / pefile.is_dll()"
        elif r["is_exe"]:
            type_evidence = "FILE_HEADER.Characteristics IMAGE_FILE_DLL bit clear / pefile.is_exe()"
        else:
            type_evidence = "neither IMAGE_FILE_DLL nor a recognized EXE characteristic set"
        type_name = "DLL" if r["is_dll"] else "EXE" if r["is_exe"] else "unknown"
        lines.append(f"- Type: {type_name} (evidence: {type_evidence})")
        lines.append("")

        lines.append("### Machine / bitness")
        lines.append(
            f"- Machine: `{r['machine_name']}` (evidence: FILE_HEADER.Machine = "
            f"0x{r['machine']:04X})"
        )
        lines.append(
            f"- Bitness: {r['bitness']}-bit (evidence: OPTIONAL_HEADER.Magic = "
            f"0x{'20B (PE32+)' if r['bitness'] == 64 else '10B (PE32)'})"
        )
        lines.append("")

        lines.append("### Load / entry")
        lines.append(f"- Image base: `0x{r['image_base']:08X}` (evidence: OPTIONAL_HEADER.ImageBase)")
        lines.append(
            f"- Entry point RVA: `0x{r['entry_point_rva']:08X}` "
            f"(evidence: OPTIONAL_HEADER.AddressOfEntryPoint; absolute VA = ImageBase + RVA = "
            f"`0x{r['image_base'] + r['entry_point_rva']:08X}`)"
        )
        lines.append(
            f"- SizeOfImage: {r['size_of_image']:,} bytes / SizeOfHeaders: "
            f"{r['size_of_headers']:,} bytes (evidence: OPTIONAL_HEADER.SizeOfImage / SizeOfHeaders)"
        )
        lines.append("")

        lines.append("### Timestamp / linker / subsystem")
        lines.append(
            f"- Link timestamp: {r['timestamp_str']} (evidence: FILE_HEADER.TimeDateStamp = "
            f"0x{r['timestamp_raw']:X}, raw COFF header field — self-reported by the linker, "
            f"not independently verified)"
        )
        lines.append(
            f"- Linker version: {r['linker_version']} (evidence: "
            f"OPTIONAL_HEADER.MajorLinkerVersion.MinorLinkerVersion)"
        )
        lines.append(
            f"- Target OS version: {r['os_version']} (evidence: "
            f"OPTIONAL_HEADER.MajorOperatingSystemVersion.MinorOperatingSystemVersion)"
        )
        lines.append(
            f"- Subsystem: `{r['subsystem_name']}` (evidence: OPTIONAL_HEADER.Subsystem = "
            f"{r['subsystem']})"
        )
        lines.append(
            f"- FILE_HEADER.Characteristics flags: {', '.join(r['characteristics']) or '(none)'}"
        )
        dll_char_text = ", ".join(r["dll_characteristics"]) or (
            "(none set — no ASLR/DEP/SafeSEH opt-in, consistent with a pre-2006 linker "
            "that predates these mitigations)"
        )
        lines.append(f"- OPTIONAL_HEADER.DllCharacteristics flags: {dll_char_text}")
        lines.append("")

        lines.append("### Sections")
        lines.append(
            f"{r['num_sections']} sections (evidence: FILE_HEADER.NumberOfSections). "
            "Flags column: R/W/X = readable/writable/executable "
            "(IMAGE_SCN_MEM_READ/WRITE/EXECUTE), kind = code/data/bss "
            "(IMAGE_SCN_CNT_CODE/INITIALIZED_DATA/UNINITIALIZED_DATA)."
        )
        lines.append("")
        lines.append("| Name | VirtualAddress | VirtualSize | SizeOfRawData | Flags | Entropy |")
        lines.append("|---|---|---|---|---|---|")
        for s in r["sections"]:
            lines.append(
                f"| `{s['name']}` | 0x{s['virtual_address']:08X} | {s['virtual_size']:,} | "
                f"{s['raw_size']:,} | {s['flags']} | {s['entropy']:.2f} |"
            )
        lines.append("")

        lines.append("### Packing / obfuscation / linker anomalies")
        for sig in r["packing_signals"]:
            lines.append(f"- {sig}")
        lines.append("")

        lines.append("### Imports")
        if r["imports"]:
            lines.append(
                f"{len(r['imports'])} DLL(s) imported (evidence: IMAGE_DIRECTORY_ENTRY_IMPORT):"
            )
            lines.append("")
            for dll, names in r["imports"]:
                lines.append(f"- **{dll}** ({len(names)}): {', '.join(names)}")
        else:
            lines.append("(no import table)")
        lines.append("")

        lines.append("### Exports")
        if r["exports"]:
            lines.append(
                f"{len(r['exports'])} export(s) (evidence: IMAGE_DIRECTORY_ENTRY_EXPORT):"
            )
            lines.append("")
            lines.append("| Ordinal | Name | RVA |")
            lines.append("|---|---|---|")
            for ordinal, name, addr in r["exports"]:
                lines.append(f"| {ordinal} | {name or '(no name, ordinal-only)'} | 0x{addr:08X} |")
        else:
            lines.append("(no export table)")
        lines.append("")

    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pe_files", nargs="+", type=Path, help="PE file(s) to analyze")
    parser.add_argument("-o", "--out", type=Path, help="write Markdown to this file (default: stdout)")
    args = parser.parse_args()

    results = []
    for p in args.pe_files:
        if not p.exists():
            print(f"error: not found: {p}", file=sys.stderr)
            sys.exit(1)
        results.append(analyze(p))

    md = render_markdown(results)
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(md, encoding="utf-8")
        print(f"wrote {args.out}")
    else:
        print(md)


if __name__ == "__main__":
    main()
