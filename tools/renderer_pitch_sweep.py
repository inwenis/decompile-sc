#!/usr/bin/env python3
"""Sweep StarCraft.exe for FRAMEBUFFER-PITCH-shaped operands, not for "640".

Task 034. `research/renderer-viewport.md` §12.4 records that a sweep for the
literal 640 misses the sites that COMPUTE it. This is the sweep for the other
half of that lesson: the sites that hold a MULTIPLE of it.

The stage-1 failure this tool was written for: the fog draw walks the screen in
8x8 blocks and hands a framebuffer pointer to three block writers. Two of them
step with `add esi,640` and were declared. The third, `FUN_004800A0`, is
unrolled and holds its pitch as fourteen displacements -- `[ecx + k*640]` and
`[ecx + k*640 + 4]` for k=1..7 -- and the outer loop advances a block row with
`add ecx,8*640`. Of those fifteen instructions exactly ONE spells 640. The rest
are 644, 1280, 1284, ... 5120, and no search for the pitch's own value, for the
framebuffer's address, or for the dirty grid's address can reach any of them.

So the shape to search for is `k*pitch + d` for a small k and a very small d:

  * k > 1 because loops get unrolled, and an unrolled row walk holds k*pitch;
  * d > 0 because a run wider than one unit writes its second store at
    k*pitch + 4. Searching multiples alone found 7 of the 14 stores in that one
    function -- half a fix, which in this subsystem renders rather than crashes.

Ranking uses proximity to a reference to the framebuffer pointer (0x006CEFF4)
or the screen Bitmap (0x006CEFF0), found by scanning .text for the encoded
dword. That is a heuristic and is reported as one: a routine that is HANDED the
pointer never names it, which is exactly why `FUN_004800A0` sits 1405 bytes from
the nearest reference. Widen --near and read the hits.

Hits are cross-referenced against research/data/renderer-widescreen-patches.tsv
so the output is "what is not declared yet" rather than a list to re-triage.

  python tools/renderer_pitch_sweep.py                 # near a framebuffer ref
  python tools/renderer_pitch_sweep.py --near 8192     # widen the radius
  python tools/renderer_pitch_sweep.py --all           # everything, unranked

A hit is a LEAD, not a finding (§10's standing caveat): 20480 is 32*640 and is
the fog map's allocation size, 14720 is 23*640 and is a 160x92 minimap surface.
Both are in the output and neither is a pitch. Read the function.
"""
from __future__ import annotations

import argparse
import csv
import os
import struct
import sys

try:
    from capstone import Cs, CS_ARCH_X86, CS_MODE_32
    from capstone.x86_const import X86_OP_IMM, X86_OP_MEM
except ImportError:                                        # pragma: no cover
    sys.exit("renderer_pitch_sweep: capstone is required (pip install capstone)")

DEFAULT_EXE = os.environ.get("SC_EXE", r"C:\sc-work\1161-base\StarCraft.exe")
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TSV = os.path.join(REPO, "research", "data", "renderer-widescreen-patches.tsv")

FRAME_PTR = 0x006CEFF4      # the framebuffer pointer, zero until the video init
FRAME_BMP = 0x006CEFF0      # the screen Bitmap descriptor itself
STOCK_PITCH = 640


def load_image(path: str):
    with open(path, "rb") as f:
        data = f.read()
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    nsec = struct.unpack_from("<H", data, pe + 6)[0]
    optsz = struct.unpack_from("<H", data, pe + 20)[0]
    base = struct.unpack_from("<I", data, pe + 24 + 28)[0]
    secs, off = [], pe + 24 + optsz
    for _ in range(nsec):
        name = data[off:off + 8].rstrip(b"\0").decode("latin1")
        vsz, va, rsz, ptr = struct.unpack_from("<IIII", data, off + 8)
        secs.append((name, base + va, vsz, ptr, rsz))
        off += 40
    return data, secs


def disasm_all(md, blob: bytes, base: int):
    """Linear sweep that RESUMES past bytes capstone cannot decode.

    .text is full of int3 padding and jump tables, and capstone's disasm() stops
    dead at the first of them. Without this the sweep silently covers only the
    bytes before the first data island -- the first run of it reported zero hits
    over a binary that has dozens.
    """
    off, n = 0, len(blob)
    while off < n:
        last = off
        for ins in md.disasm(blob[off:], base + off):
            last = ins.address - base + ins.size
            yield ins
        off = last + 1 if last <= off else last


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--exe", default=DEFAULT_EXE)
    ap.add_argument("--pitch", type=int, default=STOCK_PITCH)
    ap.add_argument("--max-k", type=int, default=64, help="largest multiple to look for")
    ap.add_argument("--max-d", type=int, default=16, help="largest within-row offset to look for")
    ap.add_argument("--near", type=lambda s: int(s, 0), default=0x600,
                    help="how close a framebuffer reference must be to rank a hit")
    ap.add_argument("--all", action="store_true", help="also list the far hits")
    a = ap.parse_args()

    data, secs = load_image(a.exe)
    text = [s for s in secs if s[0].startswith(".text")]
    if not text:
        sys.exit("renderer_pitch_sweep: no .text section in %s" % a.exe)
    _, tva, tvsz, tptr, trsz = text[0]
    blob = data[tptr:tptr + min(trsz, tvsz)]

    refs = []
    for target in (FRAME_PTR, FRAME_BMP):
        enc = struct.pack("<I", target)
        i = blob.find(enc)
        while i != -1:
            refs.append(tva + i)
            i = blob.find(enc, i + 1)
    refs.sort()

    def distance_to_frame_ref(va: int):
        best = None
        for r in refs:
            d = abs(r - va)
            if best is None or d < best:
                best = d
        return best

    declared = {}
    if os.path.exists(TSV):
        with open(TSV, newline="") as f:
            for row in csv.DictReader(f, delimiter="\t"):
                declared[int(row["va"], 16)] = "%s/%s" % (row["stage"], row["name"])

    shapes = {}
    for k in range(1, a.max_k + 1):
        for d in range(0, a.max_d):
            shapes.setdefault(a.pitch * k + d, (k, d))

    md = Cs(CS_ARCH_X86, CS_MODE_32)
    md.detail = True

    near_hits, far_hits = [], []
    for ins in disasm_all(md, blob, tva):
        val = None
        for op in ins.operands:
            if op.type == X86_OP_IMM and op.imm in shapes:
                val = op.imm
            elif op.type == X86_OP_MEM and op.mem.disp in shapes and op.mem.base != 0:
                val = op.mem.disp
            if val is not None:
                break
        if val is None:
            continue
        k, d = shapes[val]
        dist = distance_to_frame_ref(ins.address)
        rec = (ins.address, ins.bytes.hex(), "%s %s" % (ins.mnemonic, ins.op_str),
               val, k, d, dist, declared.get(ins.address))
        if a.all or (dist is not None and dist <= a.near):
            near_hits.append(rec)
        else:
            far_hits.append(rec)

    def show(rows, title):
        print("== %s: %d ==" % (title, len(rows)))
        for (va, raw, txt, val, k, d, dist, dec) in rows:
            print("%08X  %-20s %-40s ; %d = %d*%d%s, framebuf ref %s   <= %s"
                  % (va, raw, txt, val, k, a.pitch, ("+%d" % d) if d else "",
                     ("+%d" % dist) if dist is not None else "none",
                     ("DECLARED " + dec) if dec else "UNDECLARED"))

    show(near_hits, "pitch-shaped operands near a framebuffer reference"
         if not a.all else "pitch-shaped operands")
    undeclared = [r for r in near_hits if r[7] is None]
    print("\n%d of them are not in the patch table." % len(undeclared))
    if not a.all:
        print("(%d further hits are far from any framebuffer reference; --all to list)"
              % len(far_hits))
    return 0


if __name__ == "__main__":
    sys.exit(main())
