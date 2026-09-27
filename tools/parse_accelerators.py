#!/usr/bin/env python3
"""Dump a PE's RT_ACCELERATOR resources as (flags, key, command-id) rows.

WHY THIS EXISTS (task 021). StarCraft 1.16.1 does not read its control-group keys in
its window procedure. Its message pump (0x004D1BF0) calls TranslateAcceleratorA FIRST
and only dispatches the message normally when that returns 0, and the accelerator table
is built by 0x004D3070 out of this binary's OWN resources (LoadAcceleratorsA with ids
0x65/0x66/0x67/0x71, merged through CopyAcceleratorTableA/CreateAcceleratorTableA).

Two things follow, and both are load-bearing for this repo:

  1. The key -> command-id mapping the in-game key dispatcher 0x004846E0 switches on
     (`MOVSX EDI,word ptr [ECX + 0x8]`, then a jump table) is DATA IN THE FILE, not code.
     Dumping it is how "which key combination is the shift-add?" gets an answer instead
     of a shrug.
  2. TranslateAcceleratorA resolves FSHIFT/FCONTROL/FALT against the calling THREAD's
     key-state table, which Windows does not update for POSTED messages. So every
     accelerator carrying a modifier is undrivable by tools/plugin/drive-game.ps1, and
     every unmodified one is drivable. That is why an unattended test can press `1` but
     not Ctrl+1 (research/control-groups.md).

This reads a PE from disk and prints a table. It extracts NO game content -- an
accelerator table is a keyboard mapping, the same class of finding as an address or a
struct offset -- but it is pointed at a working copy, never at the pristine install.

Usage:
    python tools/parse_accelerators.py <path-to-pe> [--ids 65,66,67,71] [--tsv <out>]
"""

import argparse
import os
import struct
import sys

import pefile

RT_ACCELERATOR = 9

# ACCEL resource entry flags (winuser.h).
F_VIRTKEY, F_NOINVERT, F_SHIFT, F_CONTROL, F_ALT, F_LAST = 0x01, 0x02, 0x04, 0x08, 0x10, 0x80

# Only the virtual keys this binary's accelerators actually use are named; anything else
# prints as its hex code rather than as a guess.
VK_NAMES = {
    0x08: "BACK", 0x09: "TAB", 0x0D: "RETURN", 0x1B: "ESCAPE", 0x20: "SPACE",
    0x21: "PRIOR", 0x22: "NEXT", 0x23: "END", 0x24: "HOME",
    0x25: "LEFT", 0x26: "UP", 0x27: "RIGHT", 0x28: "DOWN",
    0x2D: "INSERT", 0x2E: "DELETE",
    0x60: "NUMPAD0", 0x61: "NUMPAD1", 0x62: "NUMPAD2", 0x63: "NUMPAD3", 0x64: "NUMPAD4",
    0x65: "NUMPAD5", 0x66: "NUMPAD6", 0x67: "NUMPAD7", 0x68: "NUMPAD8", 0x69: "NUMPAD9",
    0x70: "F1", 0x71: "F2", 0x72: "F3", 0x73: "F4", 0x74: "F5", 0x75: "F6",
    0x76: "F7", 0x77: "F8", 0x78: "F9", 0x79: "F10", 0x7A: "F11", 0x7B: "F12",
}


def key_name(code, flags):
    if not (flags & F_VIRTKEY):
        return repr(chr(code)) if 32 <= code < 127 else f"0x{code:02X}"
    if code in VK_NAMES:
        return VK_NAMES[code]
    if 0x30 <= code <= 0x39 or 0x41 <= code <= 0x5A:
        return chr(code)
    return f"VK_0x{code:02X}"


def mod_name(flags):
    mods = []
    if flags & F_CONTROL:
        mods.append("Ctrl")
    if flags & F_SHIFT:
        mods.append("Shift")
    if flags & F_ALT:
        mods.append("Alt")
    return "+".join(mods)


def accelerator_blobs(path):
    """(resource id, language, bytes) for every RT_ACCELERATOR in the file."""
    pe = pefile.PE(path)
    res = getattr(pe, "DIRECTORY_ENTRY_RESOURCE", None)
    return [(n.id, l.id, pe.get_data(l.data.struct.OffsetToData, l.data.struct.Size))
            for t in (res.entries if res else []) if t.id == RT_ACCELERATOR
            for n in t.directory.entries for l in n.directory.entries]


def parse_accel_blob(blob):
    """Resource-form ACCEL entries: WORD flags, WORD key, WORD id, WORD padding."""
    rows = []
    for off in range(0, len(blob) - 7, 8):
        flags, key, cmd, _pad = struct.unpack_from("<HHHH", blob, off)
        rows.append((flags, key, cmd))
        if flags & F_LAST:
            break
    return rows


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("pe")
    ap.add_argument("--ids", help="comma-separated hex resource ids to keep (default: all)")
    ap.add_argument("--tsv", help="also write the rows to this TSV")
    # The committed table (research/data/accelerators.tsv) spans TWO modules, so it needs a
    # module column the rows themselves do not carry, and a second run has to append rather
    # than overwrite. Without these the repro printed in research/control-groups.md 9 could
    # not actually rebuild the file it points at -- which review caught.
    ap.add_argument("--module", help="value for a leading `module` column (default: the "
                                     "PE's file name)")
    ap.add_argument("--append", action="store_true",
                    help="append to --tsv instead of overwriting, writing the header only "
                         "when the file is new or empty")
    args = ap.parse_args()

    if "sc-install" in args.pe.replace("\\", "/").lower():
        sys.exit("refusing to read the pristine install; point this at a working copy")

    keep = None
    if args.ids:
        keep = {int(x, 16) for x in args.ids.replace("0x", "").split(",")}

    module = args.module or os.path.basename(args.pe)

    rows = []
    for res_id, lang, blob in sorted(accelerator_blobs(args.pe)):
        if keep is not None and res_id not in keep:
            continue
        for flags, key, cmd in parse_accel_blob(blob):
            # The dispatcher sign-extends the command id (MOVSX), so report both forms.
            signed = cmd - 0x10000 if cmd & 0x8000 else cmd
            rows.append({
                "module": module,
                "resId": f"0x{res_id:02X}", "lang": lang,
                "flags": f"0x{flags:02X}", "mods": mod_name(flags) or "-",
                "key": key_name(key, flags), "keyCode": f"0x{key:02X}",
                "cmdId": f"0x{cmd:04X}", "cmdIdSigned": signed,
                "postable": "no" if (flags & (F_SHIFT | F_CONTROL | F_ALT)) else "yes",
            })

    if not rows:
        sys.exit("no RT_ACCELERATOR resources matched")

    cols = ["module", "resId", "lang", "flags", "mods", "key", "keyCode", "cmdId",
            "cmdIdSigned", "postable"]
    widths = {c: max(len(c), max(len(str(r[c])) for r in rows)) for c in cols}
    print("  ".join(c.ljust(widths[c]) for c in cols))
    for r in rows:
        print("  ".join(str(r[c]).ljust(widths[c]) for c in cols))
    print(f"\n{len(rows)} accelerator(s). `postable=no` means the entry carries a "
          f"modifier, so TranslateAcceleratorA resolves it against the thread key-state "
          f"table and a POSTED message can never match it.")

    if args.tsv:
        fresh = (not args.append) or (not os.path.exists(args.tsv)) \
                or os.path.getsize(args.tsv) == 0
        with open(args.tsv, "a" if args.append else "w", encoding="utf-8",
                  newline="\n") as fh:
            if fresh:
                fh.write("\t".join(cols) + "\n")
            for r in rows:
                fh.write("\t".join(str(r[c]) for c in cols) + "\n")
        print(f"{'appended to' if args.append and not fresh else 'wrote'} {args.tsv}")


if __name__ == "__main__":
    main()
