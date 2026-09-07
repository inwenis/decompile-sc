#!/usr/bin/env python3
"""Generate the widescreen patch table for tools/plugin/src/sc_screen.cpp.

Task 034. `research/renderer-viewport.md` establishes that the playfield's size
is not stored anywhere -- it is an immediate in every function that clips to it.
Widening the screen therefore means rewriting a few dozen instruction operands
in the running process, and every one of them has to be found, sized and proved
to be the instruction the map says it is.

Hand-maintaining that as a C array of magic bytes would be unreviewable and
would rot the first time somebody mistyped a nibble. So this script owns it:

  * it reads the SAME StarCraft.exe the plugin will patch (default: the
    disposable working copy), maps VA -> file offset through the PE section
    table, and DISASSEMBLES each declared site;
  * for an immediate patch it LOCATES the old value inside the instruction's
    own bytes rather than trusting a hand-written offset, and refuses if the
    encoding is not exactly one unambiguous field of the declared width;
  * for a code patch it disassembles the replacement and prints it beside the
    original, so a reviewer reads two instruction listings instead of two hex
    strings;
  * it emits both `sc_screen_patches.h` (what the plugin applies) and
    `research/data/renderer-widescreen-patches.tsv` (what a human reads).

The plugin re-verifies every `expect` blob at runtime before writing anything,
exactly like the detour engine does (`sc_hook.cpp`), so a table generated
against a different build cannot silently patch the wrong bytes.

Nothing here reads or writes game DATA -- it reads code bytes out of the
executable and emits addresses and encodings. No game content is reproduced.

Usage:
  python tools/renderer_patch_sites.py [--exe PATH] [--width 800] [--height 480]
                                       [--check]     # verify only, write nothing
"""
from __future__ import annotations

import argparse
import os
import struct
import sys
from types import SimpleNamespace

try:
    from capstone import Cs, CS_ARCH_X86, CS_MODE_32, CS_GRP_JUMP, CS_GRP_CALL, CS_GRP_BRANCH_RELATIVE
    from capstone.x86_const import X86_REG_EFLAGS, X86_OP_IMM
except ImportError:  # pragma: no cover
    sys.exit("renderer_patch_sites: capstone is required (pip install capstone)")

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_EXE = r"C:\sc-work\1161-base\StarCraft.exe"

# The stock geometry every site below is declared against: a site whose current
# bytes do not carry the stock value is refused, which pins the table to 1.16.1.
STOCK_W = 640
STOCK_H = 480
STOCK_PF_H = 400          # playfield height; the console occupies 400..479
STOCK_TERRAIN_PITCH = 672  # 640 + 32, one tile of margin
STOCK_TERRAIN_ROWS = 448   # 400 + 48
STOCK_BLOCK = 16           # dirty-grid block size, both axes
STOCK_COLS = STOCK_W // STOCK_BLOCK
STOCK_ROWS = STOCK_H // STOCK_BLOCK

# Longest single rewrite the plugin's record can hold. The EFLAGS-hazard reorder
# windows are the long ones: 0x0042D2C7 swallows three stores between cmp and jg.
SC_MAX_PATCH_LEN = 32
# Longest code cave (Builder.cave): the window's instructions re-encoded with
# 32-bit fields, WITHOUT the jmp back (the plugin appends that).
SC_MAX_CAVE_LEN = 32


def le32(v: int) -> str:
    """A 32-bit little-endian field as hex, two's complement for negatives."""
    return (v & 0xFFFFFFFF).to_bytes(4, "little").hex()


class Image:
    """The on-disk PE, addressable by VA."""

    def __init__(self, path: str):
        self.path = path
        self.data = open(path, "rb").read()
        pe = struct.unpack_from("<I", self.data, 0x3C)[0]
        if self.data[pe:pe + 4] != b"PE\0\0":
            raise SystemExit("renderer_patch_sites: %s is not a PE" % path)
        nsec = struct.unpack_from("<H", self.data, pe + 6)[0]
        optsz = struct.unpack_from("<H", self.data, pe + 20)[0]
        self.imagebase = struct.unpack_from("<I", self.data, pe + 24 + 28)[0]
        self.secs = []
        for i in range(nsec):
            o = pe + 24 + optsz + i * 40
            name = self.data[o:o + 8].rstrip(b"\0").decode("ascii", "replace")
            vsize, va, rawsize, raw = struct.unpack_from("<IIII", self.data, o + 8)
            self.secs.append((name, va, vsize, raw, rawsize))

    def off(self, va: int):
        r = va - self.imagebase
        for _name, sva, vsz, raw, rawsz in self.secs:
            if sva <= r < sva + max(vsz, rawsz):
                d = r - sva
                if d < rawsz:
                    return raw + d
        return None

    def read(self, va: int, n: int) -> bytes:
        o = self.off(va)
        if o is None:
            raise SystemExit("renderer_patch_sites: VA 0x%08X is not in any section" % va)
        return self.data[o:o + n]


MD = Cs(CS_ARCH_X86, CS_MODE_32)
MD.detail = True


def touches_flags(ins):
    """(reads EFLAGS, writes EFLAGS) for one instruction."""
    try:
        read, written = ins.regs_access()
    except Exception:                      # pragma: no cover
        return (False, False)
    return (X86_REG_EFLAGS in read, X86_REG_EFLAGS in written)


def disasm_one(va: int, blob: bytes):
    for ins in MD.disasm(blob, va):
        return ins
    return None


def disasm_all(va: int, blob: bytes):
    return list(MD.disasm(blob, va))


def fmt(ins) -> str:
    return "%s %s" % (ins.mnemonic, ins.op_str)


# --------------------------- Patch records ---------------------------------

class Patch:
    """One instruction-level rewrite.

    `expect` is the exact original bytes; the plugin refuses the whole table if
    any site fails to match. `fixup_off`/`fixup_addend`, when set, name a dword
    inside `patch` that the plugin fills at runtime with (relocated grid base +
    addend) -- the dirty grid moves to plugin-owned memory whose address is not
    known until the process is up.
    """

    def __init__(self, va, expect, patch, name, stage, note,
                 fixup_off=None, fixup_addend=0, before="", after="", cave=None):
        assert len(expect) == len(patch), name
        assert len(patch) <= SC_MAX_PATCH_LEN,             "%s: %d-byte rewrite exceeds SC_MAX_PATCH_LEN" % (name, len(patch))
        assert cave is None or len(cave) <= SC_MAX_CAVE_LEN,             "%s: %d-byte cave exceeds SC_MAX_CAVE_LEN" % (name, len(cave) if cave else 0)
        # A site already correct for the chosen geometry (every 480/400 site when
        # only the width changes). Kept in the evidence table but never handed to
        # the plugin: writing a byte back over itself can only ever go wrong.
        self.noop = (expect == patch and fixup_off is None and cave is None)
        self.va = va
        self.expect = expect
        self.patch = patch
        self.name = name
        self.stage = stage
        self.note = note
        self.fixup_off = fixup_off
        self.fixup_addend = fixup_addend
        self.before = before
        self.after = after
        # Code cave (see Builder.cave): the replacement instructions the window
        # jumps out to. None for an in-place rewrite.
        self.cave = cave


class Builder:
    def __init__(self, img: Image, geom: dict):
        self.img = img
        self.geom = geom
        self.patches: list[Patch] = []
        self.errors: list[str] = []
        self.warnings: list[str] = []

    # -- flags safety --------------------------------------------------------
    def check_flags(self, p: "Patch"):
        self.check_flags_bytes(p.name, p.va, p.expect, p.patch)

    def check_flags_bytes(self, name, va, expect, patch):
        """Refuse a rewrite that destroys a live flags value.

        `lea` does not touch EFLAGS; `imul r32,r/m32,imm8` does. Swapping one for
        the other is three bytes for three bytes and looks free -- and it is not,
        wherever a `cmp`/`test` before the site is consumed by a `jcc` after it.
        Task 034 shipped exactly that mistake into a live game: the dirty-block
        marker's `cmp ecx,esi` ... `jg` pair had a new `imul` spliced between
        them, the marker took the wrong branch, blocks were never marked dirty,
        and the frame came out shredded while every read-back still said 800x400.

        So: if the replacement writes EFLAGS where the original did not, walk
        forward from the end of the patch and refuse if a flags READER is reached
        before a flags WRITER.
        """
        p = SimpleNamespace(name=name, va=va, expect=expect, patch=patch)
        orig = disasm_all(p.va, p.expect)
        new = disasm_all(p.va, p.patch)
        if not orig or not new:
            return
        orig_writes = any(touches_flags(i)[1] for i in orig)
        new_writes = any(touches_flags(i)[1] for i in new)
        if orig_writes and new_writes:
            # Both write flags, but not necessarily the SAME flags: `shl r,3` ->
            # `shl r,1` changes SF/ZF/CF too. Only a warning, because a reorder
            # window legitimately holds the setter a downstream branch wants.
            if [fmt(i) for i in orig] != [fmt(i) for i in new]:
                after = self.img.read(p.va + len(p.expect), 64)
                for ins in disasm_all(p.va + len(p.expect), after):
                    reads, writes = touches_flags(ins)
                    if reads:
                        self.warnings.append(
                            "%s @0x%08X: both old and new write EFLAGS but differently, and "
                            "`%s` @0x%08X reads them next -- check the branch by hand"
                            % (p.name, p.va, fmt(ins), ins.address))
                        break
                    if writes:
                        break
            return
        if not new_writes:
            return
        # The ONLY exemption is `orig_writes`, above. Do not also exempt a window
        # whose LAST instruction sets flags on the theory that a reorder puts the
        # setter last: that exempts every single-instruction `lea`->`imul` swap,
        # i.e. exactly the sites this check exists for, and reports a clean table
        # over a broken game. A reorder is already covered, because its window
        # CONTAINS the original `cmp` and so makes `orig_writes` true on its own.
        after = self.img.read(p.va + len(p.expect), 64)
        for ins in disasm_all(p.va + len(p.expect), after):
            reads, writes = touches_flags(ins)
            if reads:
                self.errors.append(
                    "%s @0x%08X: the replacement writes EFLAGS and `%s` @0x%08X reads "
                    "them before anything else writes them -- this rewrite would change "
                    "a branch. Extend the window and reorder so the flag setter is last."
                    % (p.name, p.va, fmt(ins), ins.address))
                return
            if writes:
                return

    def imm(self, va, old, new, width, name, stage, note):
        """Rewrite one immediate/displacement field of `width` bytes.

        The field's position is FOUND, not declared: the instruction is
        disassembled, its bytes searched for the encoded old value, and the
        site refused unless exactly one candidate of that width exists.
        """
        blob = self.img.read(va, 16)
        ins = disasm_one(va, blob)
        if ins is None:
            self.errors.append("%s @0x%08X: does not disassemble" % (name, va))
            return
        raw = bytes(ins.bytes)
        enc_old = old.to_bytes(width, "little", signed=False)
        hits = [i for i in range(len(raw) - width + 1) if raw[i:i + width] == enc_old]
        # A 2-byte field also matches inside a 4-byte one; require the operand
        # text to name the value so a coincidental match cannot pass.
        if ("0x%x" % old) not in ins.op_str.lower():
            self.errors.append("%s @0x%08X: `%s` does not carry 0x%X"
                               % (name, va, fmt(ins), old))
            return
        if len(hits) != 1:
            self.errors.append("%s @0x%08X: %d candidate fields of width %d for 0x%X in %s"
                               % (name, va, len(hits), width, old, raw.hex()))
            return
        off = hits[0]
        if new >= (1 << (8 * width)):
            self.errors.append("%s @0x%08X: new value 0x%X does not fit in %d byte(s)"
                               % (name, va, new, width))
            return
        # A ONE-BYTE field is SIGN-EXTENDED by every encoding this table declares
        # (imm8 of 83/6B/6A, disp8 of a ModRM), so a value above 127 ships NEGATIVE:
        # an unsigned-only bound passes the W=960 fog cell stride 128 as
        # `add edx,-0x80` with 0 errors. Shift counts (C1 /n ib) never exceed 31.
        if width == 1 and new > 127:
            self.errors.append("%s @0x%08X: new value %d does not fit a SIGN-EXTENDED byte "
                               "(it would ship as %d) -- use cave()" % (name, va, new, new - 256))
            return
        patched = bytearray(raw)
        patched[off:off + width] = new.to_bytes(width, "little")
        after = disasm_one(va, bytes(patched))
        self.patches.append(Patch(va, raw, bytes(patched), name, stage, note,
                                  before=fmt(ins),
                                  after=fmt(after) if after else "??"))

    def simm(self, va, old, new, width, name, stage, note):
        """Rewrite one SIGNED immediate/displacement field of `width` bytes.

        Task 064. The terrain refresh band holds its wrap arithmetic as
        NEGATIVE encodings -- `lea ecx,[eax - 0x498000]`, `and eax,0xfffb6800`
        -- which imm() cannot declare: the encoded bytes are the two's
        complement and the operand text prints the magnitude. Same location
        discipline as imm(): the field is FOUND inside the instruction's own
        bytes and refused unless exactly one candidate exists, and the operand
        text must carry the value (as magnitude or as unsigned hex).
        """
        blob = self.img.read(va, 16)
        ins = disasm_one(va, blob)
        if ins is None:
            self.errors.append("%s @0x%08X: does not disassemble" % (name, va))
            return
        raw = bytes(ins.bytes)
        mask = (1 << (8 * width)) - 1
        enc_old = (old & mask).to_bytes(width, "little")
        hits = [i for i in range(len(raw) - width + 1) if raw[i:i + width] == enc_old]
        ops = ins.op_str.lower()
        if ("0x%x" % abs(old)) not in ops and ("0x%x" % (old & mask)) not in ops:
            self.errors.append("%s @0x%08X: `%s` does not carry 0x%X"
                               % (name, va, fmt(ins), abs(old)))
            return
        if len(hits) != 1:
            self.errors.append("%s @0x%08X: %d candidate fields of width %d for %d in %s"
                               % (name, va, len(hits), width, old, raw.hex()))
            return
        lo, hi = -(1 << (8 * width - 1)), (1 << (8 * width - 1)) - 1
        if not (lo <= new <= hi):
            self.errors.append("%s @0x%08X: new value %d does not fit signed %d byte(s)"
                               % (name, va, new, width))
            return
        off = hits[0]
        patched = bytearray(raw)
        patched[off:off + width] = (new & mask).to_bytes(width, "little")
        after = disasm_one(va, bytes(patched))
        self.patches.append(Patch(va, raw, bytes(patched), name, stage, note,
                                  before=fmt(ins),
                                  after=fmt(after) if after else "??"))

    # -- raw code rewrite ----------------------------------------------------
    def code(self, va, expect_hex, patch_hex, name, stage, note,
             fixup_off=None, fixup_addend=0):
        expect = bytes.fromhex(expect_hex)
        patch = bytes.fromhex(patch_hex)
        actual = self.img.read(va, len(expect))
        if actual != expect:
            self.errors.append("%s @0x%08X: bytes are %s, table says %s"
                               % (name, va, actual.hex(), expect.hex()))
            return
        before = " ; ".join(fmt(i) for i in disasm_all(va, expect))
        after = " ; ".join(fmt(i) for i in disasm_all(va, patch))
        # A replacement that does not fully decode is a typo in the table, not a
        # clever encoding: refuse rather than write bytes nobody has read back.
        if sum(i.size for i in disasm_all(va, patch)) != len(patch):
            self.errors.append("%s @0x%08X: the replacement does not decode cleanly (%s)"
                               % (name, va, patch.hex()))
            return
        p = Patch(va, expect, patch, name, stage, note,
                  fixup_off=fixup_off, fixup_addend=fixup_addend,
                  before=before, after=after)
        self.check_flags(p)
        self.patches.append(p)

    # -- code cave: a window that jumps out to a longer replacement ----------
    def cave(self, va, expect_hex, cave_hex, name, stage, note):
        """Detour one straight-line WINDOW of whole instructions to plugin-owned code.

        For a value that does not fit the instruction's own field. The fog cell
        stride is a sign-extended imm8/disp8 at six sites, and 168 (W=1280)
        fits neither, nor does any encoding of the same length -- `add r,imm32`
        is 6 bytes where `add r,imm8` is 3. So the window (>= 5 whole bytes, no
        PC-relative operand, no branch target strictly inside it) becomes
        `jmp cave` padded with NOPs, and the cave holds the SAME instructions
        re-encoded with 32-bit fields followed by `jmp` back to the window's
        end. Both rel32s are filled by the plugin at runtime (the cave's address
        comes from VirtualAlloc); the table carries the window's original bytes
        and the cave's code, and the reviewer reads two listings as usual.
        """
        expect = bytes.fromhex(expect_hex)
        cave = bytes.fromhex(cave_hex)
        actual = self.img.read(va, len(expect))
        if actual != expect:
            self.errors.append("%s @0x%08X: bytes are %s, table says %s"
                               % (name, va, actual.hex(), expect.hex()))
            return
        if len(expect) < 5:
            self.errors.append("%s @0x%08X: a %d-byte window cannot hold a 5-byte jmp"
                               % (name, va, len(expect)))
            return
        orig = disasm_all(va, expect)
        new = disasm_all(va, cave)
        if sum(i.size for i in orig) != len(expect):
            self.errors.append("%s @0x%08X: the window does not decode into whole "
                               "instructions (%s)" % (name, va, expect.hex()))
            return
        if sum(i.size for i in new) != len(cave):
            self.errors.append("%s @0x%08X: the cave does not decode cleanly (%s)"
                               % (name, va, cave.hex()))
            return
        # The window's bytes are never executed in place again, so nothing in it
        # may be PC-relative (it would be relocated) -- and nothing outside it may
        # jump INTO it (it would land on the NOP tail or inside the jmp).
        for i in orig:
            if any(g in (CS_GRP_JUMP, CS_GRP_CALL, CS_GRP_BRANCH_RELATIVE) for g in i.groups):
                self.errors.append("%s @0x%08X: `%s` in the window is PC-relative"
                                   % (name, va, fmt(i)))
                return
        band_lo = va - 0x400
        band = self.img.read(band_lo, 0x800)
        pos = 0
        while pos < len(band):
            ins = disasm_one(band_lo + pos, band[pos:pos + 16])
            if ins is None:
                pos += 1
                continue
            if any(g in (CS_GRP_JUMP, CS_GRP_CALL) for g in ins.groups):
                for op in ins.operands:
                    if op.type == X86_OP_IMM and va < op.imm < va + len(expect):
                        self.errors.append("%s @0x%08X: `%s` @0x%08X branches INTO the "
                                           "window" % (name, va, fmt(ins), ins.address))
                        return
            pos += ins.size
        # What the plugin writes over the window: jmp rel32 (filled at runtime)
        # + NOPs -- NOP rather than int3 so a stray landing is harmless.
        window = b"\xE9\0\0\0\0" + b"\x90" * (len(expect) - 5)
        p = Patch(va, expect, window, name, stage, note,
                  before=" ; ".join(fmt(i) for i in orig),
                  after="[cave] " + " ; ".join(fmt(i) for i in new),
                  cave=cave)
        self.check_flags_bytes(name, va, expect, cave)
        self.patches.append(p)

    # -- absolute address rewrite (dirty-grid relocation) --------------------
    def rebase(self, va, old_target, addend, name, stage, note):
        """Re-point one absolute reference to the relocated dirty grid.

        `addend` is the offset INTO the relocated grid the instruction should
        end up naming, recomputed for the new stride rather than copied -- the
        two references that name a row rather than the array (`grid + 18*40`,
        `grid + 1*40 + 26`) would otherwise land in the wrong row.
        """
        blob = self.img.read(va, 16)
        ins = disasm_one(va, blob)
        if ins is None:
            self.errors.append("%s @0x%08X: does not disassemble" % (name, va))
            return
        raw = bytes(ins.bytes)
        enc = old_target.to_bytes(4, "little")
        hits = [i for i in range(len(raw) - 3) if raw[i:i + 4] == enc]
        if len(hits) != 1:
            self.errors.append("%s @0x%08X: %d candidates for 0x%08X in %s"
                               % (name, va, len(hits), old_target, raw.hex()))
            return
        patched = bytearray(raw)
        patched[hits[0]:hits[0] + 4] = b"\0\0\0\0"
        self.patches.append(Patch(va, raw, bytes(patched), name, stage, note,
                                  fixup_off=hits[0], fixup_addend=addend,
                                  before=fmt(ins),
                                  after="%s [grid+0x%X]" % (ins.mnemonic, addend)))


# --------------------------- The site table --------------------------------

def build(img: Image, W: int, H: int, PF_H: int) -> Builder:
    PF_W = W                       # the playfield spans the full width
    TERRAIN_PITCH = PF_W + 32      # stock: 640 + 32
    TERRAIN_SIZE = TERRAIN_PITCH * STOCK_TERRAIN_ROWS
    COLS = W // STOCK_BLOCK
    # ROUNDED UP: a partial block row still needs a row and the engine's `y >> 4`
    # indexes it. 480 gives 30 exactly; 600 gives 38, not 37.
    ROWS = (H + STOCK_BLOCK - 1) // STOCK_BLOCK
    GRID_BYTES = COLS * ROWS

    geom = dict(W=W, H=H, PF_W=PF_W, PF_H=PF_H, COLS=COLS, ROWS=ROWS,
                GRID_BYTES=GRID_BYTES, TERRAIN_PITCH=TERRAIN_PITCH,
                TERRAIN_SIZE=TERRAIN_SIZE)
    b = Builder(img, geom)

    # =====================================================================
    # STAGE 0 -- the display mode, and nothing else. §9.3's cheapest possible
    # falsification: does the presentation half come up at all at a non-640x480
    # mode? Everything the engine renders is still 640x480 after this, so the
    # expected outcome is a small image in the corner of a bigger one.
    b.imm(0x0041DA3D, STOCK_H, H, 4, "displaymode.height", 0,
          "IDirectDraw::SetDisplayMode height")
    b.imm(0x0041DA42, STOCK_W, W, 4, "displaymode.width", 0,
          "IDirectDraw::SetDisplayMode width")
    b.imm(0x0041DB9C, STOCK_W, W, 4, "fallbacksurface.width", 0,
          "offscreen fallback surface dwWidth (used when the primary will not lock)")
    b.imm(0x0041DBA3, STOCK_H, H, 4, "fallbacksurface.height", 0,
          "offscreen fallback surface dwHeight")

    # =====================================================================
    # STAGE 1 -- the screen surface itself.

    # -- the one framebuffer and its descriptor (§2, item 2) ---------------
    b.imm(0x004DB077, STOCK_W * STOCK_H, W * H, 4, "screenbuffer.alloc", 1,
          "SMemAlloc size for the single 8-bit framebuffer")
    b.imm(0x004DB07C, STOCK_W, W, 2, "screenbitmap.width.vidinimo", 1,
          "screenBitmap.width, written by the video init")
    b.imm(0x004DB085, STOCK_H, H, 2, "screenbitmap.height.vidinimo", 1,
          "screenBitmap.height, written by the video init")
    b.imm(0x0041E07B, STOCK_W, W, 2, "screenbitmap.width.image", 1,
          "screenBitmap.width, second writer (gds\\image.cpp 0x0041E050)")
    b.imm(0x0041E084, STOCK_H, H, 2, "screenbitmap.height.image", 1,
          "screenBitmap.height, second writer")
    # A THIRD allocate-and-describe site: a second copy of the video init, same
    # file and same line number (vidinimo.cpp:0x37), allocating its own buffer.
    b.imm(0x0041DDD9, STOCK_W * STOCK_H, W * H, 4, "screenbuffer.alloc.third", 1,
          "SMemAlloc size, THIRD copy of the video init (new in task 034)")
    b.imm(0x0041DDDE, STOCK_W, W, 2, "screenbitmap.width.third", 1,
          "screenBitmap.width, third writer at 0x0041DDDE (new in task 034)")
    b.imm(0x0041DDE7, STOCK_H, H, 2, "screenbitmap.height.third", 1,
          "screenBitmap.height, third writer")

    # -- presentation (items 3, 4) -----------------------------------------
    b.imm(0x0041D450, STOCK_W, W, 4, "blit.sourcepitch", 1,
          "SOURCE pitch of the one blit that presents the frame")
    b.imm(0x0041D52C, STOCK_H, H, 4, "storm.region.height", 2,
          "Ordinal_440 height (Storm's dirty-region geometry)")
    b.imm(0x0041D531, STOCK_W, W, 4, "storm.region.width", 2,
          "Ordinal_440 width; the same call passes the 16x16 block size")

    # -- the screen FILL helper 0x0041D3A0 ---------------------------------
    # The composer's whole-screen-clear branch calls this. It carries the screen
    # pitch TWICE, and only one of them is an immediate: the other is
    # `lea edi,[eax+eax*4]; shl edi,7`, i.e. y*5<<7 == y*640. An immediate sweep
    # is blind to that shape. Four such multiplies exist in the whole binary;
    # the other three are the fog's framebuffer rowmuls below.
    b.imm(0x0041D3D9, STOCK_W, W, 4, "fillscreen.pitch.imm", 1,
          "0x0041D3A0: destination pitch passed to the fill")
    assert W % 32 == 0, "the x(W/32)<<5 rewrite needs a width that is a multiple of 32"
    MUL32 = W // 32
    assert MUL32 <= 127, "imul r32,r/m32,imm8 needs W/32 to fit a signed byte"
    b.code(0x0041D3E6, "8d3c80", "6bf8" + bytes([MUL32]).hex(),
           "fillscreen.rowmul", 1,
           "0x0041D3A0: edi = y * %d (was y * 5, feeding a shift of 7)" % MUL32)
    b.code(0x0041D3EF, "c1e707", "c1e705", "fillscreen.rowshift", 1,
           "0x0041D3A0: shl edi,7 -> shl edi,5, so y*%d<<5 == y*%d" % (MUL32, W))

    # -- the composer's per-layer clip rectangle (item 6) ------------------
    b.imm(0x0041E2D5, STOCK_W, W, 4, "compose.clearrect.width", 1,
          "whole-screen-clear branch: full-screen rect width")
    b.imm(0x0041E2DC, STOCK_H, H, 4, "compose.clearrect.height", 1,
          "whole-screen-clear branch: full-screen rect height")
    b.imm(0x0041E2F2, STOCK_H, H, 4, "compose.descriptor.height", 1,
          "MOV EDI,480 -- the height every layer descriptor gets")
    b.imm(0x0041E323, STOCK_W - 1, W - 1, 4, "compose.clip.x2", 2,
          "x2 = -left + 639")
    b.imm(0x0041E32F, STOCK_H - 1, H - 1, 4, "compose.clip.y2", 2,
          "y2 = -top + 479")
    b.imm(0x0041E33E, STOCK_W, W, 2, "compose.descriptor.width", 1,
          "width field of every layer descriptor")

    # -- the dirty marker's clamps (item 7) --------------------------------
    b.imm(0x0041E0E2, STOCK_W, W, 4, "dirty.reject.x", 2,
          "return early if x1 >= 640 (new in task 034; not in 032's table)")
    b.imm(0x0041E0F5, STOCK_W - 1, W - 1, 4, "dirty.clamp.x2.cmp", 2, "x2 upper bound")
    b.imm(0x0041E0FD, STOCK_W - 1, W - 1, 4, "dirty.clamp.x2.set", 2, "x2 = 639")
    b.imm(0x0041E10A, STOCK_H, H, 4, "dirty.reject.y", 2,
          "return early if y1 >= 480 (new in task 034)")
    b.imm(0x0041E11A, STOCK_H - 1, H - 1, 4, "dirty.clamp.y2.cmp", 2, "y2 upper bound")
    b.imm(0x0041E122, STOCK_H - 1, H - 1, 4, "dirty.clamp.y2.set", 2, "y2 = 479")

    # -- layer 2, the dialog layer (item 16) -------------------------------
    # Stage 1 rather than stage 4: the composer clips every layer to the screen,
    # and a dialog layer still 640 wide clips the cursor layer's redraw of the
    # right-hand strip.
    b.imm(0x0041A049, STOCK_W, W, 2, "layer2.width", 2, "dialog layer width")
    b.imm(0x0041A052, STOCK_H, H, 2, "layer2.height", 2, "dialog layer height")

    # -- the copier's DESTINATION pitch ------------------------------------
    # 0x0040C2BD computes the destination address from the screen Bitmap
    # descriptor, so it follows the new width for free -- but the row step
    # inside the copy loop it calls is a hardcoded 640, and without it every
    # terrain row lands one row-fragment further left.
    b.imm(0x0040C247, STOCK_W, W, 4, "copyrun.destpitch", 1,
          "row step of the scratch->screen copy loop (new in task 034)")

    # -- fog: FRAMEBUFFER ADDRESSING, which is stage 1, not stage 2 --------
    # The rule that sorts these: a site that computes an address INTO THE
    # FRAMEBUFFER moves when the framebuffer widens (stage 1); a site that CLIPS
    # to the playfield moves when the playfield widens (stage 2). Fog has both,
    # and at 800x480 they are the same number, so nothing in the source
    # distinguishes them -- only a live run does. Scanning .text for the
    # framebuffer pointer 0x006CEFF4 finds 19 instructions; three of them --
    # 0x0047EDCC, 0x0047EF35, 0x00480631 -- are immediately followed by a
    # `lea r,[y+y*4]` + `shl r,7`, i.e. y*640 into the frame. Left in stage 2 the
    # fog writes every row at the old pitch and the playfield comes out sheared
    # while the descriptor, the layer rects and the HUD all read correctly.
    #
    # THAT SCAN IS NOT AN EXHAUSTIVE ENUMERATION. "Every routine that writes the
    # framebuffer must load 0x006CEFF4" is false: a routine that is HANDED the
    # pointer by its caller writes the framebuffer without ever naming it. The
    # block writers below are exactly that.
    for lea_va, lea_hex, imul_hex, shl_va in [
        (0x0047EDD3, "8d0c89", "6bc9", 0x0047EDD6),
        (0x0047EF3A, "8d0cb6", "6bce", 0x0047EF3D),
        (0x00480635, "8d0c92", "6bca", 0x00480638),
    ]:
        b.code(lea_va, lea_hex, imul_hex + bytes([MUL32]).hex(),
               "fog.rowmul@%08X" % lea_va, 1,
               "fog: ecx = y * %d (was y * 5, feeding a shift of 7) -- FRAMEBUFFER row"
               % MUL32)
        b.code(shl_va, "c1e107", "c1e105", "fog.rowshift@%08X" % shl_va, 1,
               "fog: shl ecx,7 -> shl ecx,5, so y*%d<<5 == y*%d" % (MUL32, W))
    # FUN_0047EA60 is the routine all three of those callers hand a framebuffer
    # address to, and it holds the pitch itself: `mov esi,640; sub esi,ebx`, i.e.
    # "row step = pitch - run width". Left at 640 it walks the shroud down the
    # frame at the old stride, and because the shroud is only drawn at the edges
    # of an explored map the damage is a frame around the playfield with the
    # middle intact -- invisible to a centre-weighted look, plain in a block map.
    b.imm(0x0047EA6B, STOCK_W, W, 4, "fog.rowpitch.writer", 1,
          "FUN_0047EA60: dest row step is (pitch - run width) -- FRAMEBUFFER pitch")
    for va in (0x0047FFDE, 0x00480087):
        b.imm(va, STOCK_W, W, 4, "fog.rowstep@%08X" % va, 1,
              "fog blend loop: advance one FRAMEBUFFER row")

    # -- fog, the 8x8 BLOCK GRID: the sites the pointer scan cannot reach ----
    # FUN_00480600 draws fog in 8x8 blocks over the framebuffer: `add ecx,8` per
    # column (0x004806B7) and one row of blocks per outer turn. For each block it
    # calls one of three writers with ecx as the destination -- FUN_0047FF10 and
    # FUN_00480000 step with `add esi,640` (declared above), and FUN_004800A0,
    # the fully-shrouded case, is UNROLLED and holds its pitch as fourteen
    # displacements. It is §12.5's rule (a stride is a number that describes a
    # layout without pointing at it) in its best-hidden shape:
    # `mov [ecx + k*640], eax` for k=1..7 spells 640 only at k=1, the rest being
    # 1280, 1920, 2560, 3200, 3840, 4480; and each row's SECOND dword sits at
    # k*640 + 4, no multiple of the pitch at all, so a multiples-only sweep finds
    # seven of the fourteen and ships half a fix. Missing them puts every
    # shrouded 8x8 block in the wrong row of an 800-pitch frame: the EXPLORED
    # area pixel-perfect and everything under fog wrong, 163 of 190 interior rows.
    FOG_BLOCK_CLEAR = 0x004800B4          # first of 14 x 6-byte stores
    for i in range(14):
        k, d = 1 + i // 2, (i % 2) * 4
        b.imm(FOG_BLOCK_CLEAR + 6 * i, STOCK_W * k + d, W * k + d, 4,
              "fog.blockclear.r%d%s" % (k, "hi" if d else "lo"), 1,
              "FUN_004800A0: shrouded 8x8 block, row %d of 8 at (pitch*%d)+%d" % (k, k, d))
    b.imm(0x004806D0, STOCK_W * 8, W * 8, 4, "fog.blockrowstep", 1,
          "fog draw: advance 8 FRAMEBUFFER rows (one block row)")

    # -- the dirty grid (item 5): relocation ------------------------------
    # 0x006CEFF8's u8[30][40] cannot grow in place -- 0x006CF4A8 is the live
    # render-target pointer, and 126 instructions name it. So the grid moves to
    # plugin-owned memory and every absolute reference is re-pointed. A .text
    # scan for the encoded address finds 21 of them; register-derived accesses
    # inside loops are not among them, since they follow the base they were
    # loaded from.
    GRID = 0x006CEFF8
    for va, note in [
        (0x0041D755, "drawing gate 0x0041D710: clear all"),
        (0x0041E025, "Storm update-region call: the grid IS the region list"),
        (0x0041E03C, "0x0041DF80: clear all after presenting"),
        (0x0041E06F, "video init 0x0041E050: clear all"),
        (0x0041E3DF, "composer: hand the grid to Storm"),
        (0x0041E3F6, "composer: clear all after presenting"),
        (0x004808FB, "fog draw 0x004808F8: walk from the top-left"),
        (0x004BCDE4, "terrain blitter 0x004BCDC0: walk from the top-left"),
        (0x004BD656, "console init 0x004BD630: mark all dirty"),
    ]:
        b.rebase(va, GRID, 0, "grid.base@%08X" % va, 2, note)

    # References that name a ROW: the offset is recomputed, never carried across.
    b.rebase(0x0048CC00, 0x006CF03A, 1 * COLS + 26, "grid.row1col26", 2,
             "0x0048CB80 names grid[row 1][col 26]; recomputed for the new stride")
    b.rebase(0x004B2314, 0x006CF2C8, 18 * COLS, "grid.row18", 2,
             "0x004B1FA0 names grid[row 18][col 0]; recomputed for the new stride")
    # ...and the BYTE COUNT that fill uses is stride arithmetic too:
    # `lea ecx,[eax+eax*4-0x55]` then `shl ecx,3` is 40*(row-17), i.e. "every row
    # from 18 down to `row`". Re-pointing the base without rebuilding the count
    # fills 40 bytes of a 50-byte row and leaves the right of every one unmarked
    # -- a missed redraw, not a crash, which is the kind that reaches a screenshot.
    assert COLS <= 127, "imul r32,r/m32,imm8 needs the column count to fit a signed byte"
    b.code(0x004B2303, "8d4c80ab" "c1e103",
           "8d48ef" + "6bc9" + bytes([COLS]).hex() + "90",
           "grid.row18.count", 2,
           "0x004B1FA0: ecx = (row - 17) * %d, was (row - 17) * %d" % (COLS, STOCK_COLS))
    b.imm(0x0048CC1F, STOCK_COLS, COLS, 1, "grid.rowstep.48CB80", 2,
          "0x0048CB80: next row of the grid is +40 bytes")
    # 0x0048CB80's OTHER branch: the 21st named grid reference. It fills grid
    # rows 18..N with 1s via rep stos, naming grid[row 18][0] absolutely and
    # holding the byte count as the same `lea ecx,[eax+eax*4-0x55]; shl ecx,3`
    # == 40*(row-17) shape as 0x004B2303. Left stock, these dirty marks land in
    # the DEAD relocated-away array: missed console-band redraws that render
    # rather than crash. Two copies of the shape exist in .text; both are here.
    b.rebase(0x0048CBC7, 0x006CF2C8, 18 * COLS, "grid.row18.b", 2,
             "0x0048CB80 branch 1 names grid[row 18][col 0]; recomputed for the new stride")
    b.code(0x0048CBB5, "8d4c80ab" "c1e103",
           "8d48ef" + "6bc9" + bytes([COLS]).hex() + "90",
           "grid.row18.count.b", 2,
           "0x0048CB80: ecx = (row - 17) * %d, was (row - 17) * %d -- the twin of "
           "grid.row18.count" % (COLS, STOCK_COLS))
    # 0x0042D280 fills a row and steps to the next the same way. A stride names no
    # address, so the relocation pass cannot see it: only a sweep for stride-shaped
    # operands finds it (§12.5, the "damage that renders" note).
    b.imm(0x0042D305, STOCK_COLS, COLS, 1, "grid.rowstep.42D280", 2,
          "0x0042D280: next row of the grid is +40 bytes")

    # Row addressing: `lea r,[c+c*4]` (x5) feeding a SIB scale of 8 gives the
    # stock stride of 40; for 50 the multiply becomes x25 and the scale x2 -- a
    # 3-byte-for-3-byte swap plus one SIB nibble, which is why 50 is reachable.
    assert COLS % 2 == 0, "the x25/scale-2 rewrite needs an even column count"
    HALF = COLS // 2
    assert HALF <= 127, "imul r32,r/m32,imm8 needs the half-stride to fit a signed byte"

    # 0x0041E0D0, the dirty marker. THE WINDOW INCLUDES THE `cmp` AND THE `jg`
    # ON PURPOSE: `lea` leaves EFLAGS alone and `imul` does not, and here a
    # `cmp ecx,esi` two bytes earlier is consumed by a `jg` five bytes later.
    # Splicing the multiply between them makes the marker branch on the
    # multiply's flags, so whole bands of blocks are never marked dirty and never
    # redrawn -- a shredded frame while every read-back still says 800x400,
    # because the layer rect is the plugin's bookkeeping and the pixels are the
    # engine's result. So: a reorder, not a longer sequence. The same 14 bytes
    # hold imul / lea / cmp / jg, the `jg` keeps its address so its rel8 is
    # unchanged, and the flag setter is the last thing before the branch.
    b.code(0x0041E15B,
           "3bce" "8d0489" "8d9cc7f8ef6c00" "7f2a",
           "6bc1" + bytes([HALF]).hex() + "8d9c47" + "00000000" + "3bce" "7f2a",
           "grid.rowaddr.marker", 2,
           "dirty marker: eax = row * %d, ebx = grid + row*%d + col; cmp/jg moved "
           "after the multiply so the branch still reads the compare" % (HALF, COLS),
           fixup_off=6, fixup_addend=0)
    b.imm(0x0041E18A, STOCK_COLS, COLS, 1, "grid.rowstep.marker", 2,
          "dirty marker: next row is +40 bytes")

    b.code(0x0041DE4E, "8d0489", "6bc1" + bytes([HALF]).hex(),
           "grid.stride.testrect", 2, "0x0041DE20: eax = row * 25")
    b.code(0x0041DE51, "8d9cc6f8ef6c00", "8d9c46" + "00000000",
           "grid.rowaddr.testrect", 2,
           "0x0041DE20: [esi + eax*8 + grid] -> [esi + eax*2 + grid]",
           fixup_off=3, fixup_addend=0)
    b.imm(0x0041DE6B, STOCK_COLS, COLS, 4, "grid.cols.testrect", 2,
          "0x0041DE20: columns per row")

    # 0x0042D280 -- same hazard, same reorder. `cmp edi,eax` ... `jg`, with three
    # unrelated stores in between that the reorder simply steps over.
    b.code(0x0042D2C7,
           "3bf8" "8d14bf" "891e" "897e04" "89460c" "8d94d3f8ef6c00" "894dfc" "7f2c",
           "6bd7" + bytes([HALF]).hex() + "891e" "897e04" "89460c" +
           "8d9453" + "00000000" + "894dfc" "3bf8" "7f2c",
           "grid.rowaddr.42D280", 2,
           "0x0042D280: edx = row * %d, [ebx + edx*2 + grid]; cmp/jg reordered" % HALF,
           fixup_off=14, fixup_addend=0)

    # 0x00497000 -- same hazard with `test eax,eax` ... `je`.
    b.code(0x00497060,
           "85c0" "8d0c89" "8dbccff8ef6c00" "741b",
           "6bc9" + bytes([HALF]).hex() + "8dbc4f" + "00000000" + "85c0" "741b",
           "grid.rowaddr.497000", 2,
           "0x00497000: ecx = row * %d, [edi + ecx*2 + grid]; test/je reordered" % HALF,
           fixup_off=6, fixup_addend=0)
    b.imm(0x00497058, STOCK_COLS, COLS, 4, "grid.cols.497000", 2,
          "0x00497000: columns per row")

    # 0x0047EBF0, the scrolled fog arm. Three separate row computations feed five
    # reads of the grid, so they belong with the relocation, not with the rest of
    # the fog geometry. Left behind, the fog goes on reading an array nothing
    # writes any more and believes the screen is never dirty -- a bug that hides
    # at the main menu and only appears in game.
    b.code(0x0047ECEB, "8d3c80", "6bf8" + bytes([HALF]).hex(),
           "grid.stride.fog.a", 2, "0x0047EBF0: edi = row * 25")
    b.code(0x0047ECF9, "8a94f8f8ef6c00", "8a9478" + "00000000",
           "grid.rowaddr.fog.a", 2,
           "0x0047EBF0: [eax + edi*8 + grid] -> [eax + edi*2 + grid]",
           fixup_off=3, fixup_addend=0)

    b.code(0x0047ED3C, "8d1c9b", "6bdb" + bytes([HALF]).hex(),
           "grid.stride.fog.b", 2, "0x0047EBF0: ebx = row * 25 (feeding a shift)")
    b.code(0x0047ED41, "c1e303", "c1e301", "grid.strideshift.fog.b", 2,
           "0x0047EBF0: shl ebx,3 -> shl ebx,1, so row*25<<1 == row*%d" % COLS)
    b.code(0x0047ED44, "8a943bf8ef6c00", "8a943b" + "00000000",
           "grid.rowaddr.fog.b1", 2, "0x0047EBF0: [ebx + edi + grid]",
           fixup_off=3, fixup_addend=0)
    b.code(0x0047ED55, "80bc13f8ef6c0000", "80bc13" + "00000000" + "00",
           "grid.rowaddr.fog.b2", 2, "0x0047EBF0: cmp byte [ebx + edx + grid], 0",
           fixup_off=3, fixup_addend=0)

    b.code(0x0047ED5F, "8d0480", "6bc0" + bytes([HALF]).hex(),
           "grid.stride.fog.c", 2, "0x0047EBF0: eax = row * 25 (feeding a shift)")
    b.code(0x0047ED62, "c1e003", "c1e001", "grid.strideshift.fog.c", 2,
           "0x0047EBF0: shl eax,3 -> shl eax,1")
    b.code(0x0047ED65, "8a9c38f8ef6c00", "8a9c38" + "00000000",
           "grid.rowaddr.fog.c1", 2, "0x0047EBF0: [eax + edi + grid]",
           fixup_off=3, fixup_addend=0)
    b.code(0x0047ED70, "8a9c10f8ef6c00", "8a9c10" + "00000000",
           "grid.rowaddr.fog.c2", 2, "0x0047EBF0: [eax + edx + grid]",
           fixup_off=3, fixup_addend=0)

    # The `rep stosd` clears of the whole grid: 300 dwords -> COLS*ROWS/4.
    assert GRID_BYTES % 4 == 0, "the grid clears are dword-granular"
    for va, note in [
        (0x0041D750, "drawing gate 0x0041D710"),
        (0x0041E035, "0x0041DF80"),
        (0x0041E06A, "video init 0x0041E050"),
        (0x0041E3EF, "composer 0x0041E280"),
        (0x004BD64C, "console init 0x004BD630"),
    ]:
        b.imm(va, (STOCK_COLS * STOCK_ROWS) // 4, GRID_BYTES // 4, 4,
              "grid.clearcount@%08X" % va, 2, note + ": rep stosd count")

    # =====================================================================
    # STAGE 2 -- the playfield geometry: 9.3's "stage that can actually look
    # wrong", where the SHAPE of a site matters more than the count of them.

    # -- item 8: the terrain scratch surface -------------------------------
    # A second fixed-size buffer, 672x448, allocated at 0x004BD745 into
    # 0x00628454; its producer is 0x0040AAE0 and the family around it. Its pitch
    # and its wrap size are immediates in the routines that read AND write it,
    # so both move together.
    b.imm(0x004BD745, STOCK_TERRAIN_PITCH * STOCK_TERRAIN_ROWS, TERRAIN_SIZE, 4,
          "terrain.alloc", 2, "SMemAlloc size of the terrain scratch surface")

    for va, note in [
        (0x0040AAFE, "terrain WRITER 0x0040AAE0: row stride"),
        (0x0040C23A, "scratch->screen copy: source row step"),
        (0x0040C240, "scratch->screen copy: source offset row step"),
        # FOUR of these run-writers exist, not two. Each is an 8-row loop whose
        # WRAP test (`cmp edx,0x49800` / `sub edx,0x49800`) is easy to spot and
        # whose row STEP is not, so declaring the wraps alone gets the surface
        # size right everywhere and the stride right in half the writers: terrain
        # lands in the wrong rows of the scratch surface, which is every pixel of
        # the playfield -- 332 of 380 rows damaged, 16 points more black than the
        # control. `tools/renderer_pitch_sweep.py --pitch 672` is what enumerates
        # all four: it flags every stride-shaped operand this table leaves
        # undeclared.
        (0x0040C402, "scratch writer (8-pixel run, forward): row step"),
        (0x0040C44C, "scratch writer (8-pixel run, forward): row step"),
        (0x0040C495, "scratch writer (8-pixel run, reverse): row step"),
        (0x0040C4C4, "scratch writer (8-pixel run, forward 2): row step"),
        (0x004BCDD1, "terrain blitter: screenTop * pitch"),
        # Four more of the same multiply in the scroll band, reachable only by a
        # multiplier-dataflow sweep: by shape, not by the immediate 0x2A0.
        (0x0049BC51, "scroll: row * terrain pitch"),
        (0x0049BD70, "scroll: row * terrain pitch"),
        (0x0049BE2C, "scroll: row * terrain pitch"),
        (0x0049C7A8, "scroll: row * terrain pitch"),
    ]:
        b.imm(va, STOCK_TERRAIN_PITCH, TERRAIN_PITCH, 4,
              "terrain.pitch@%08X" % va, 2, note)

    # The SAME multiply, decomposed into shifts, in the full-playfield blit:
    # 672 == (t<<9)+(t<<7)+(t<<5) -- three `shl r,imm8` at 0x0040C275 (eax),
    # 0x0040C27E (ebx), 0x0040C281 (ecx), summed after. No 672 appears in that
    # function, so neither an immediate sweep nor a lea+shl scan finds it -- and
    # it positions every terrain row the non-dirty path draws. Any pitch that is
    # a sum of exactly three powers of two survives as three one-byte count edits
    # (832 = 9,8,6; 1312 = 10,8,5); anything else needs the block rewritten,
    # which is what the assert says.
    bits = [i for i in range(32) if (TERRAIN_PITCH >> i) & 1]
    assert len(bits) == 3, \
        "the shift-decomposed pitch at 0x0040C275 needs a 3-term power-of-two sum; %d is not" % TERRAIN_PITCH
    hi, mid, lo = sorted(bits, reverse=True)
    for va, reg_hex, stock_count, new_count, term in [
        (0x0040C275, "e0", 9, hi, "a"),     # shl eax,9  (the 512 term)
        (0x0040C27E, "e3", 7, mid, "b"),    # shl ebx,7  (the 128 term)
        (0x0040C281, "e1", 5, lo, "c"),     # shl ecx,5  (the 32 term)
    ]:
        b.code(va, "c1" + reg_hex + "%02x" % stock_count,
               "c1" + reg_hex + "%02x" % new_count,
               "terrain.pitch.shift.%s" % term, 2,
               "0x0040C253: shl by %d -> %d (the %d term becomes %d)"
               % (stock_count, new_count, 1 << stock_count, 1 << new_count))

    for va, note in [
        (0x0040AAF0, "terrain writer: end-of-surface pointer"),
        (0x0040AB19, "terrain writer: wrap"),
        (0x0040ABAA, "terrain writer: wrap"),
        (0x0040C20C, "copy loop: wrap test"),
        (0x0040C214, "copy loop: wrap test"),
        (0x0040C21B, "copy loop: wrap"),
        (0x0040C22A, "copy loop: wrap source"),
        (0x0040C230, "copy loop: wrap offset"),
        (0x0040C290, "full-playfield blit: wrap test"),
        (0x0040C297, "full-playfield blit: wrap"),
        (0x0040C29C, "full-playfield blit: wrap test"),
        (0x0040C3E2, "scratch writer: wrap test"),
        (0x0040C3EA, "scratch writer: wrap"),
        (0x0040C42C, "scratch writer: wrap test"),
        (0x0040C434, "scratch writer: wrap"),
        (0x0040C476, "scratch writer: wrap test"),
        (0x0040C47E, "scratch writer: wrap"),
        (0x0040C4A5, "scratch writer: wrap test"),
        (0x0040C4AD, "scratch writer: wrap"),
        (0x0049BEF0, "scroll: wrap test"),
        (0x0049BEF8, "scroll: wrap"),
        (0x004BCDDD, "terrain blitter: the modulus of the initial offset"),
        (0x004BCDF8, "terrain blitter: wrap test"),
        (0x004BCE00, "terrain blitter: wrap"),
        (0x004BCE4F, "terrain blitter: wrap test"),
        (0x004BCE5B, "terrain blitter: wrap"),
        (0x004BCE74, "terrain blitter: wrap test"),
        (0x004BCE7C, "terrain blitter: wrap"),
    ]:
        b.imm(va, STOCK_TERRAIN_PITCH * STOCK_TERRAIN_ROWS, TERRAIN_SIZE, 4,
              "terrain.wrap@%08X" % va, 2, note)

    # The terrain blitter's own walk of the dirty grid: 40 columns, and a row
    # step of `pitch*16 - width` (0x2780 == 672*16-640, read from the encoding)
    # because the column loop already advanced it by 16 per column.
    for va in (0x004BCE0E, 0x004BCE28, 0x004BCE66):
        b.imm(va, STOCK_COLS, COLS, 1, "terrain.cols@%08X" % va, 2,
              "terrain blitter: columns per row")
    b.imm(0x004BCE6E, STOCK_TERRAIN_PITCH * 16 - STOCK_W,
          TERRAIN_PITCH * 16 - PF_W, 4, "terrain.rowstep", 2,
          "terrain blitter: advance to the next 16 scanlines")
    b.imm(0x0040C25A, STOCK_W, PF_W, 4, "terrain.fullblit.runwidth", 2,
          "0x0040C253: the run width of the whole-playfield blit")

    # -- the terrain REFRESH band, 0x49B8D0..0x49C8xx ----------------------
    # The functions that FILL the scratch surface: the per-megatile writer
    # 0x49B9F0, the jump-scroll refresh 0x49BC20, the column/row refreshes
    # 0x49BD40 / 0x49BE20 (called by the steppers 0x49C0C0 / 0x49C280 and the
    # full refresh 0x49BF20), the per-frame tile updater 0x49C780 -> 0x49C620
    # (called from layer 5's own draw 0x4BD580), and the clamp helper 0x49B8D0.
    # Beside their four `x672` multiplies and one wrap pair sit 54 more sites
    # in the SAME functions, each an encoding no immediate sweep for
    # 672/0x49800 can match:
    #
    #   * the wrap arithmetic is mod-reduction CHAINS: successive
    #     `lea r,[r - k*0x49800]` for k=16,8,4,2,1, the constants encoded as
    #     NEGATIVE displacements (0xFFB68000..0xFFFB6800);
    #   * row steps are held in TILE-ROW bytes: +0x5400 (672*32), with the
    #     conditional wrap as `cmp 0x44400` (672*416, the last row's start) /
    #     `and 0xFFFB6800` (-0x49800 as a mask) or `cmp 0x497E0` (size minus
    #     one 32-byte tile column);
    #   * the megatile writer is UNROLLED exactly like 12.8's fog writer:
    #     twelve `[edi + 672*k + d]` displacements, k=8/16/24, d=0/8/16/24;
    #   * and the cache extent lives in TILE units: 0x15 == 21 == 672/32
    #     columns, ten sites (the 0xE == 14 == 448/32 row constants stay,
    #     because the height does not change at this geometry).
    #
    # Miss one and producer and consumer disagree over the whole surface from
    # frame one: at origin (544,416) the patched x832 multiply produces offset
    # 0x54A20, an unpatched chain reduces it mod 0x49800 to 0xB220, and the
    # patched blitter reads 0x54A20. Half-patching this one feeding path reads
    # under a bisect as "stage 2 does not decompose", which is an enumeration
    # gap wearing a structural costume.
    #
    # Only a value-FAMILY sweep of .text reaches these -- wrap multiples in both
    # signs, tile-row multiples, the unrolled k*pitch+d family, band-restricted
    # tile-unit immediates -- and each hit still needs reading in its function,
    # since padding and jump tables decode as junk. Such a sweep linear-decodes
    # 100% of .text BYTES, resuming past undecodable ones, and it is that "no
    # byte unexamined" which bounds the residual failure class to a constant
    # computed at runtime or split across instructions.
    TILE = 32
    assert TERRAIN_PITCH % TILE == 0
    TILE_COLS = TERRAIN_PITCH // TILE            # 26 (stock 21)
    STOCK_TILE_COLS = STOCK_TERRAIN_PITCH // TILE
    TILEROW = TERRAIN_PITCH * TILE               # 0x6800 (stock 0x5400)
    STOCK_TILEROW = STOCK_TERRAIN_PITCH * TILE
    STOCK_SIZE = STOCK_TERRAIN_PITCH * STOCK_TERRAIN_ROWS

    # The mod-reduction chains: k*size as a negative lea displacement.
    for fn, vas in [
        ("0x49BC20", (0x0049BC65, 0x0049BC74, 0x0049BC80, 0x0049BC8C, 0x0049BC98)),
        ("0x49BD40", (0x0049BD7B, 0x0049BD87, 0x0049BD93, 0x0049BD9F, 0x0049BDAB)),
        ("0x49BE20", (0x0049BE39, 0x0049BE45, 0x0049BE51, 0x0049BE5D, 0x0049BE69)),
        ("0x49C780", (0x0049C7D1, 0x0049C7DD, 0x0049C7E9, 0x0049C7F5, 0x0049C801)),
    ]:
        for va, k in zip(vas, (16, 8, 4, 2, 1)):
            b.simm(va, -(STOCK_SIZE * k), -(TERRAIN_SIZE * k), 4,
                   "terrain.modchain@%08X" % va, 2,
                   "%s: mod-reduce a scratch offset by %d*size (negative lea "
                   "displacement)" % (fn, k))

    # Column wraps inside the refresh loops, same negative-lea encoding.
    for va, fn in [(0x0049BCD7, "0x49BC20"), (0x0049BE9C, "0x49BE20")]:
        b.simm(va, -STOCK_SIZE, -TERRAIN_SIZE, 4, "terrain.colwrap@%08X" % va, 2,
               "%s: wrap after a 32-byte column step" % fn)

    # Row steps in tile-row bytes, with their conditional-wrap partners.
    for va, fn in [(0x0049BCFC, "0x49BC20"), (0x0049BE04, "0x49BD40"),
                   (0x0049C839, "0x49C780")]:
        b.imm(va, STOCK_TILEROW, TILEROW, 4, "terrain.tilerow@%08X" % va, 2,
              "%s: advance one 32px tile row of the scratch surface" % fn)
    b.simm(0x0049BD05, -STOCK_SIZE, -TERRAIN_SIZE, 4, "terrain.rowwrap.49BC20", 2,
           "0x49BC20: wrap after the tile-row step (add of -size)")
    for va, fn in [(0x0049BDF2, "0x49BD40"), (0x0049C82A, "0x49C780")]:
        b.imm(va, STOCK_SIZE - STOCK_TILEROW, TERRAIN_SIZE - TILEROW, 4,
              "terrain.lastrow@%08X" % va, 2,
              "%s: is this the last tile row (start of row %d)" % (fn, STOCK_TERRAIN_ROWS // TILE - 1))
    for va, fn in [(0x0049BDFF, "0x49BD40"), (0x0049C74B, "0x49C620"),
                   (0x0049C834, "0x49C780")]:
        b.simm(va, -STOCK_SIZE, -TERRAIN_SIZE, 4, "terrain.wrapmask@%08X" % va, 2,
               "%s: -size as an AND mask (branchless conditional wrap)" % fn)
    b.imm(0x0049C73F, STOCK_SIZE - TILE, TERRAIN_SIZE - TILE, 4,
          "terrain.endcol.49C620", 2,
          "0x49C620: size minus one 32-byte tile column (column-step wrap test)")

    # The unrolled per-megatile writer 0x49B9F0: [edi + 672*k + d] for its
    # 4x4 grid of 8x8 minitiles -- 12.8's fog-writer shape, in the producer.
    MT = [(0x0049BA45, 8, 0), (0x0049BA57, 8, 8), (0x0049BA69, 8, 16),
          (0x0049BA7B, 8, 24), (0x0049BA8D, 16, 0), (0x0049BA9F, 16, 8),
          (0x0049BAB1, 16, 16), (0x0049BAC3, 16, 24), (0x0049BAD5, 24, 0),
          (0x0049BAE7, 24, 8), (0x0049BAF9, 24, 16), (0x0049BB08, 24, 24)]
    for va, k, d in MT:
        b.imm(va, STOCK_TERRAIN_PITCH * k + d, TERRAIN_PITCH * k + d, 4,
              "terrain.mt.r%dc%d" % (k // 8, d // 8), 2,
              "0x49B9F0 (per-megatile writer): minitile row %d col %d of the "
              "unrolled 4x4" % (k // 8, d // 8))

    # The cache extent in TILE units: 21 == 672/32 columns. The matching
    # 14 == 448/32 row constants are untouched because the height is.
    assert TILE_COLS <= 127, "tile-unit rewrites use imm8 fields"
    for va, width, what in [
        (0x0049B958, 1, "0x49B8D0 (clamp helper): clamp request width to the cache"),
        (0x0049B95D, 4, "0x49B8D0: clamped request width"),
        (0x0049B99D, 1, "0x49B8D0: reject a request starting right of the cache"),
        (0x0049BE80, 4, "0x49BE20 (row refresh): columns of an off-map row"),
        (0x0049BEC4, 1, "0x49BE20: clamp an in-map row's columns (compare)"),
        (0x0049BEC9, 4, "0x49BE20: clamp an in-map row's columns (value)"),
        (0x0049C15C, 1, "0x49C0C0 (x stepper): the incoming column on a right "
                        "scroll is leftmost + cache width"),
        (0x0049C545, 1, "0x49C4C0 (whole-map tile updater): is this tile inside "
                        "the cached window"),
        (0x0049C64E, 1, "0x49C620 (per-frame row updater): clamp columns (compare)"),
        (0x0049C656, 4, "0x49C620: clamp columns (value)"),
    ]:
        b.imm(va, STOCK_TILE_COLS, TILE_COLS, width,
              "terrain.tilecols@%08X" % va, 2, what)

    # -- the playfield layer's own rectangle -------------------------------
    # What the read-back reads. Layer 5 IS the playfield (research/renderer-
    # viewport.md 4, confirmed live), so this is stage 2's success condition.
    b.imm(0x004BD638, STOCK_W - 1, PF_W - 1, 4, "playfield.setrect.right", 2,
          "SetRect(&0x005993B0, 0, 0, 639, 399) -- the playfield's clip rect")
    b.imm(0x004BD675, STOCK_W, PF_W, 2, "playfield.layer.width", 2,
          "layer 5's width -- the number the read-back proves")

    # -- item 9: the per-image screen clip ---------------------------------
    b.imm(0x004D5856, STOCK_W, PF_W, 4, "image.clip.right", 2,
          "0x004D57B0: every sprite on screen goes through this")

    # -- item 10: the generic playfield rect clip --------------------------
    b.imm(0x0045CCB1, STOCK_W, PF_W, 4, "rectclip.reject.x", 2, "reject if left >= 640")
    b.imm(0x0045CCCE, STOCK_W, PF_W, 4, "rectclip.cmp.right", 2,
          "0x0045CC90 right-edge test (new in task 034; not in 032's table)")
    b.imm(0x0045CCD6, STOCK_W, PF_W, 4, "rectclip.clamp.right", 2, "clamp right to 640")

    # -- item 11: fog of war -----------------------------------------------
    for va, note in [
        (0x004808E4, "0x004808E0: the full-extent fog draw"),
        (0x0047EC7B, "scrolled arm"),
        (0x0047ED97, "scrolled arm"),
        (0x0047EEA0, "static arm"),
        (0x0047EEFF, "static arm"),
        (0x0047EF0B, "static arm"),
        (0x0048090E, "clipping helper"),
        (0x0048092C, "clipping helper"),
        (0x00480948, "clipping helper"),
    ]:
        b.imm(va, STOCK_W, PF_W, 4, "fog.width@%08X" % va, 2, note)
    # A horizontal coordinate wraps modulo 648 == 640 + 8 in BOTH arms, with the
    # same three-instruction shape (compare, subtract, add-back) around an
    # 8-pixel-granular walk. Six sites, three per arm; the symmetry is what makes
    # "playfield width + one 8-pixel unit" a reading rather than a guess. Meaning
    # inferred from shape, so a seam here is an interior diff's first suspect --
    # which is what makes carrying the group safe.
    for va in (0x0047EC53, 0x0047EC66, 0x0047EC72, 0x0047EE83, 0x0047EE8D, 0x0047EE98):
        b.imm(va, STOCK_W + 8, PF_W + 8, 4, "fog.wrap@%08X" % va, 2,
              "fog coordinate wrap at (playfield width + 8), inferred from shape")
    # The six sites above (and the two draw "arms" 0x0047EBF0/0x0047EE20 they
    # sit in) are the SPACE-TILESET PARALLAX STARFIELD, not fog: the arms draw
    # star.spk items from lists at 0x00658AA8 in a 648x488 ring, gated on
    # tileset [0x0057F1DC] == 1 (space platform), with per-layer parallax
    # factors. The patches are still needed -- stars must cover the full width
    # on space maps -- but star POSITIONS come from star.spk, authored for 648
    # columns, so x in [648, W+8) holds no stars until somebody synthesizes
    # items. Cosmetic, space tilesets only; research/renderer-viewport.md 16.

    # -- THE FOG CELL PIPELINE ---------------------------------------------
    # The real fog of war (research/renderer-viewport.md 16). Its shape is the
    # terrain refresh band's, one subsystem over, with every buffer heap-
    # allocated at game start (0x00480960, called from the layer-5 init
    # 0x004BDA83) -- so unlike the dirty grid there is NOTHING to relocate:
    # patch the allocation sizes and every stride/count and the engine builds
    # the wider buffers itself.
    #
    # Data flow, per frame (orchestrated by layer 5's draw 0x004BD580):
    #   [0x006D1260] map-tile visibility dwords (map-sized, geometry-free)
    #     -> 0x0047FC50 fill   -> raw tile map [0x006D5C14], from tile origin
    #        [0x0057F1D0]-1;  same fn smooth -> [0x006D5C0C]
    #     -> 0x004804D0 change -> vs prev [0x006D5C10], dirty rects (or the
    #        full-redraw memcpy sync at 0x004BD5A8/0x004805E3)
    #     -> 0x0047FE10 interp -> 8px CELL buffer [0x006D5C18], LUT [0x00657AA0]
    #     -> 0x004805F0 render -> the 12.8 block writers
    #
    # WHY AN UNPATCHED STRIDE SHOWS AS TWO DEFECTS (15.4): the cell buffer holds
    # T_COVER*4 = 84 used columns at stride 88, while the dirty walk asks the
    # renderer for x up to 800, so the cell index runs to 99+3. Indices 84..86
    # read the row's zero PADDING -> a black seam at px 672..695; indices >= 88
    # wrap into the NEXT cell row's left columns, explored (31 = fully lit,
    # nothing drawn) -> raw terrain at px 696+ over unexplored map.
    #
    # Column-side derivation (mirrors the terrain cache; W=800 in parentheses):
    T_COVER = (PF_W + 31) // 32 + 1        # tiles covering the playfield at any
    #                                        sub-tile scroll; 21 (26)
    T_SMOOTH = T_COVER + 1                 # smoothed interior cols; 22 (27)
    T_FILL = T_SMOOTH + 2                  # raw cols incl. kernel border, and
    #                                        ALSO the tile-map STRIDE, an engine
    #                                        invariant kept as is, so the three
    #                                        structural pads (stride-T_SMOOTH = 2
    #                                        twice, stride-T_COVER = 3 once) never
    #                                        change and are NOT declared; 24 (29)
    CELL_STRIDE = T_COVER * 4 + 4          # 4 cells per tile + 4 pad; 88 (108).
    #                                        Renderer max index = 3 + (W-1)/8 + 1
    #                                        neighbor = T_COVER*4 - 1 exactly, in
    #                                        both geometries.
    # Row-side (noops at H=480, real if the table is ever regenerated taller):
    R_INTERP = (PF_H + 31) // 32 + 1       # 14 (14)
    R_SMOOTH = R_INTERP + 1                # 15 (15)
    R_FILL = R_SMOOTH + 2                  # 17 (17)
    CELL_ROWS = R_INTERP * 4 + 4           # 60 (60)
    TMAP_ALLOC = (T_FILL * R_FILL + 3) & ~3   # dword-rounded; 408 (496)
    CELL_ALLOC = CELL_STRIDE * CELL_ROWS      # 5280 (6480)

    # allocation sizes + clear counts, 0x00480960 (three tile maps + cells)
    for va in (0x004809A5, 0x004809D0, 0x004809F6):
        b.imm(va, 408, TMAP_ALLOC, 4, "fogcell.tmap.alloc@%08X" % va, 2,
              "SMemAlloc size of one %d-col x %d-row tile visibility map" %
              (T_FILL, R_FILL))
    for va in (0x004809CB, 0x004809F1, 0x00480A17):
        b.imm(va, 102, TMAP_ALLOC // 4, 4, "fogcell.tmap.clear@%08X" % va, 2,
              "rep stosd count clearing that tile map")
    b.imm(0x00480A1C, 5280, CELL_ALLOC, 4, "fogcell.cells.alloc", 2,
          "SMemAlloc size of the 8px cell buffer [0x006D5C18], "
          "%d stride x %d rows" % (CELL_STRIDE, CELL_ROWS))
    b.imm(0x00480A30, 1320, CELL_ALLOC // 4, 4, "fogcell.cells.clear", 2,
          "rep stosd count clearing the cell buffer")

    # fill, 0x0047FC50: T_FILL cols x R_FILL rows of raw per-tile visibility
    b.imm(0x0047FCA6, 17, R_FILL, 4, "fogcell.fill.rows", 2,
          "tile rows filled from the map visibility array")
    b.imm(0x0047FCC3, 24, T_FILL, 4, "fogcell.fill.cols", 2,
          "tile cols filled per row (writes the whole stride)")
    b.imm(0x0047FD80, 0x18, T_FILL, 1, "fogcell.fill.rowstep", 2,
          "advance the raw map's dest pointer one row (= stride)")

    # smooth (same function): 3x3 kernel, raw -> smoothed, interior only
    b.imm(0x0047FD9B, 0x19, T_FILL + 1, 1, "fogcell.smooth.base.src", 2,
          "raw map + stride + 1: start at row 1, col 1")
    b.imm(0x0047FD9E, 0x19, T_FILL + 1, 1, "fogcell.smooth.base.dst", 2,
          "smoothed map + stride + 1")
    b.imm(0x0047FDA1, 15, R_SMOOTH, 4, "fogcell.smooth.rows", 2,
          "interior tile rows smoothed")
    b.imm(0x0047FDB0, 22, T_SMOOTH, 4, "fogcell.smooth.cols", 2,
          "interior tile cols smoothed")
    b.simm(0x0047FDB5, -0x18, -T_FILL, 1, "fogcell.smooth.k.up", 2,
           "3x3 kernel: one row up")
    b.imm(0x0047FDBF, 0x18, T_FILL, 1, "fogcell.smooth.k.down", 2,
          "3x3 kernel: one row down")
    b.simm(0x0047FDD1, -0x19, -(T_FILL + 1), 1, "fogcell.smooth.k.upleft", 2,
           "3x3 kernel: up-left")
    b.imm(0x0047FDD8, 0x19, T_FILL + 1, 1, "fogcell.smooth.k.downright", 2,
          "3x3 kernel: down-right")
    b.simm(0x0047FDDE, -0x17, -(T_FILL - 1), 1, "fogcell.smooth.k.upright", 2,
           "3x3 kernel: up-right")
    b.imm(0x0047FDE4, 0x17, T_FILL - 1, 1, "fogcell.smooth.k.downleft", 2,
          "3x3 kernel: down-left")

    # interpolate, 0x0047FE10: smoothed tiles -> 4x4 cells each, via the LUT
    b.imm(0x0047FE23, 0x19, T_FILL + 1, 1, "fogcell.interp.base", 2,
          "smoothed map + stride + 1: read from row 1, col 1")
    b.imm(0x0047FE2D, 14, R_INTERP, 4, "fogcell.interp.rows", 2,
          "tile rows interpolated into the cell buffer")
    b.imm(0x0047FE40, 21, T_COVER, 4, "fogcell.interp.cols", 2,
          "tile cols interpolated (the playfield-covering band)")
    b.imm(0x0047FE53, 0x18, T_FILL, 1, "fogcell.interp.k.down", 2,
          "bilinear: the tile one row down")
    b.imm(0x0047FE6B, 0x19, T_FILL + 1, 1, "fogcell.interp.k.downright", 2,
          "bilinear: the tile down-right")
    # The cell stride lives in SIGN-EXTENDED one-byte fields at six sites (imm8
    # of `add`/`imul`, disp8 of `movzx`), so it caps at 127: 88 stock, 108 at
    # W=800, and 168 at W=1280 fits nothing of the same length. Each site is
    # therefore a CODE CAVE (Builder.cave) re-encoding the window with 32-bit
    # fields -- uniform for every width rather than "cave only when it does not
    # fit", so one geometry cannot exercise a path another never runs.
    b.cave(0x0047FEAB, "83c258" "8955fc",
           "81c2" + le32(CELL_STRIDE) + "8955fc",
           "fogcell.interp.cellrow", 2,
           "advance the cell dest one 8px row (add edx,stride; the store that "
           "follows rides along so the window reaches 5 bytes)")
    b.imm(0x0047FEC7, 0x15C, CELL_STRIDE * 4 - 4, 4, "fogcell.interp.colback", 2,
          "after 4 sub-rows: back up 4 cell rows, advance one dword of cells")
    b.imm(0x0047FEE4, 0x10C, CELL_STRIDE * 4 - T_COVER * 4, 4,
          "fogcell.interp.rowadv", 2,
          "after a tile row: cell dest to the next 4-row band's start")

    # change detector, 0x004804D0: smoothed vs previous frame, dirty rects
    b.imm(0x004804F8, 0x2C0, T_SMOOTH * 32, 4, "fogcell.change.xspan", 2,
          "compared screen span in px: T_SMOOTH tiles of 32")
    b.imm(0x00480502, 0x1E0, R_SMOOTH * 32, 4, "fogcell.change.yspan", 2,
          "compared screen span in px, vertical")
    b.simm(0x00480523, -0x2C0, -(T_SMOOTH * 32), 4, "fogcell.change.xspan.neg", 2,
           "the same span as the loop cursor's negative origin")

    # full-redraw sync copies (smoothed -> previous), two call sites
    b.imm(0x004805E3, 102, TMAP_ALLOC // 4, 4, "fogcell.sync.copy.a", 2,
          "rep movsd count, game-start sync in 0x004805D0")
    b.imm(0x004BD5A8, 102, TMAP_ALLOC // 4, 4, "fogcell.sync.copy.b", 2,
          "rep movsd count, full-redraw path in layer 5's draw 0x004BD580")

    # renderer, 0x004805F0: 2x2 cell neighborhood per 8x8 block -- four more cave
    # windows, each the stride instruction plus enough of what follows (or
    # precedes) to reach 5 bytes, the passengers copied unchanged.
    b.cave(0x00480617, "6bc958" "c1eb03",
           "69c9" + le32(CELL_STRIDE) + "c1eb03",
           "fogcell.render.rowmul", 2,
           "cell row base = cellRow * stride (imul ecx,ecx,stride; shr ebx,3 rides along)")
    b.cave(0x0048064C, "83c658" "48" "c1e803",
           "81c6" + le32(CELL_STRIDE) + "48" "c1e803",
           "fogcell.render.rowadv.pre", 2,
           "pre-loop advance so [esi-stride] is the current row (dec eax; shr eax,3 ride along)")
    b.cave(0x00480671, "0fb656a8" "0fb646a9",
           "0fb696" + le32(-CELL_STRIDE) + "0fb686" + le32(-(CELL_STRIDE - 1)),
           "fogcell.render.k.up", 2,
           "neighborhood read: this column and the next, current row "
           "([esi-stride], [esi-stride+1] as disp32)")
    # The block-row epilogue: the window starts at 0x004806C7, the `jge` target
    # that ENDS a block row (the two loads ride along), so that `add ecx,8*pitch`
    # right after it stays its own STAGE-1 immediate (fog.blockrowstep above).
    b.cave(0x004806C7, "8b75f8" "8b45f0" "83c658",
           "8b75f8" "8b45f0" "81c6" + le32(CELL_STRIDE),
           "fogcell.render.rowadv", 2,
           "advance one cell row per 8px block row (the two reloads ride along)")

    # -- item 14: build placement ------------------------------------------
    b.imm(0x0048D663, STOCK_W, PF_W, 2, "placement.reject.x", 2,
          "0x0048D660: refuse a placement at x >= 640 (a 16-bit compare)")
    b.imm(0x0048D5F2, STOCK_W, PF_W, 4, "placement.rect.right", 2,
          "0x0048D5C0's extent: right = left + 640 (new in task 034)")

    # -- the mask layer's parking spot -------------------------------------
    # 0x00481480 hides layer 1 by moving it to (640,400) -- off the bottom-right
    # of the playfield. At 800 wide, (640,400) is ON screen.
    b.imm(0x004814EA, STOCK_W, PF_W, 2, "layer1.park.x", 2,
          "parks the mask layer just off the right edge of the playfield")

    # ------------------------------------------------------------------
    # STAGE 3 -- input reaches the full width
    #
    # The window procedure clamps every mouse coordinate to the STOCK screen
    # before building an input event or writing the cursor globals
    # (research/renderer-viewport.md 8, last row of the 640x480 table), so an x
    # past 639 -- real or posted -- becomes 639 and the right 160 columns are
    # unreachable by any click. Each clamp is a PAIR: a `cmp .., 640` that
    # decides and a `mov .., 639` that replaces; patching the 639 alone turns
    # "click at 700" into "click at 799". X pairs widen to the new screen; the Y
    # clamps stay, the height is unchanged. Moving the CONSOLE into the widened
    # region is a separate, unshipped problem: relocating the console dialogs'
    # bounds moves their hit-test but NOT their on-screen pixels
    # (renderer-viewport.md 18).
    #
    # The one other consumer of the widened coordinate range that a full
    # cmp-immediate sweep of .text finds is the edge-scroll trigger 0x004D12FF
    # `cmp eax,0x27E / jl` -- scroll the camera RIGHT when the mouse x >= 638.
    # It ships below and MUST move with the clamp, being the same stage: with
    # the clamp lifted and the trigger at 638 the whole widened band
    # (x 638..799) fires the scroll, the camera slides the instant the cursor
    # crosses 638, and the right ~160px can be neither rested on nor clicked.
    # renderer-viewport.md 18.1.1.
    for cmp_va, mov_va, mov_w in (
            (0x004D1960, 0x004D196D, 2),   # 0x004D1940: cmp si,640 / mov ax,639
            (0x004D19EC, 0x004D19F9, 2),   # 0x004D19C0: same pair
            (0x004D1A7C, 0x004D1A89, 2),   # 0x004D1A50: same pair
            (0x004D24E6, 0x004D24EC, 4)):  # 0x004D1D70: cmp ax,640 /
        #                                    mov [0x6CDDC4],639 (cursor-x global)
        b.imm(cmp_va, STOCK_W, W, 2, "mouse.clamp.cmp@%08X" % cmp_va, 3,
              "window-proc mouse x clamp: the 'x >= 640' decision")
        b.imm(mov_va, STOCK_W - 1, W - 1, mov_w, "mouse.clamp.x@%08X" % mov_va, 3,
              "window-proc mouse x clamp: the replacement value 639")

    # The edge-scroll-right trigger, widened with the clamp above.
    # `cmp eax,638 / jl no-scroll` -- pan right only in the true right 2px, so
    # 638 -> W-2 (the stock screen's own margin, carried to the new width).
    b.imm(0x004D12FF, STOCK_W - 2, W - 2, 4, "scroll.right.trigger", 3,
          "0x004D12A0 edge-scroll: pan the camera right when mouse x >= "
          "screenW-2 (was 638; must widen with the mouse clamp or the whole "
          "right band scrolls)")

    # The PHYSICAL cursor clip. 0x004215E0 is the clip-rect reset every one of
    # the seven ClipCursor call sites runs first: it maps client {0,0} and client
    # {640,480} through ClientToScreen and SetRects the result into 0x006CDDB0,
    # which ClipCursor then confines the OS cursor to. The 640 is a hardcoded
    # client width, so under cnc-ddraw's 800-wide window the real mouse is pinned
    # to the left 640 columns -- it cannot ENTER the right band at all, and no
    # WM_MOUSEMOVE past x=639 is ever generated for the (already widened) wndproc
    # clamp to read. Only real play shows this wall: posted harness input is never
    # subject to ClipCursor, and the game calls it only with the foreground, which
    # an off-screen desktop never has. It is the coupled other half of
    # scroll.right.trigger -- clip at 640 plus trigger at W-2 means the cursor can
    # never reach the trigger and mouse scroll-right is dead -- so the two ship
    # together. Height stays 480. The 0x421690 explicit-rect setter takes its rect
    # from its 4 callers and is not touched here.
    b.imm(0x00421600, STOCK_W, W, 4, "cursor.clip.right", 3,
          "0x004215E0 clip-rect reset: ClientToScreen({640,480}) -> ({W,480}); "
          "ClipCursor confines the physical mouse to this, so 640 pinned the "
          "real cursor out of the right band")

    # The CAMERA'S scroll clamp. 0x0049BB90 builds the maximum screenLeft once
    # per game as (mapTileW - 20) * 32 -- 20 tiles = the stock 640-px viewport.
    # At 800 the viewport is 25 tiles, so parked at the right map edge the
    # playfield's last 5 tile columns (the whole new band) lie PAST the map: the
    # terrain cache clamps to the map and the band shows whatever scratch it last
    # held, and the fog fill reads visibility for tiles beyond the row end --
    # explored/unexplored blotches belonging to the next map row. A player parks
    # at the right map edge all the time; a fixture that keeps the camera
    # interior only ever sees this as "2.28% stale at the edge" (17.1 item 4).
    # Move the clamp with the viewport: 20 -> W/32 tiles. The vertical clamp
    # (sub eax,0xC, 12 tiles + 8) stays, the height is unchanged. The minimap
    # click-to-centre's own 20/13 (0x4A4D20, research 7) is NOT moved: it only
    # decides where a click lands on screen (80 px left of centre at 800), and
    # every suite's Get-ScMinimapPoint prediction is built on it.
    b.imm(0x0049BBE6, STOCK_W // 32, W // 32, 1, "scroll.clamp.x.tiles", 3,
          "0x0049BB90: maxScreenLeft = (mapTileW - 20) * 32 -> (mapTileW - W/32) * 32, "
          "so the playfield never extends past the map's right edge")

    # The wndproc clamp is necessary but NOT sufficient for click-SELECT past
    # x=639: the mouse->world click search rect (0x0046FB40, 9.1 item 12) is ALSO
    # 640 wide -- right = screenLeft + 640 -- so a click whose world point lands
    # past screenLeft+640 falls outside the rect and selects nothing even with the
    # cursor global carrying the true x. Widen the two x extents to
    # screenLeft + 800 (the click arm and the drag-box arm; the +400 height
    # extents beside them stay). Measured with a deselect-first select: without
    # these two sites a click at client x=672 selects NOTHING.
    b.imm(0x0046FC75, STOCK_W, PF_W, 4, "click.searchrect.right", 3,
          "0x0046FB40: click search rect right = screenLeft + 640 -> + 800")
    b.imm(0x0046FE18, STOCK_W, PF_W, 4, "click.searchrect.right.drag", 3,
          "0x0046FB40 drag-box arm: same rect, same widen")

    # The console HIT-TEST's x guard. 0x004D1140 is isPointOverUi(ecx = screen x,
    # eax = screen y) -> 1 = the console covers this point. Three tiers: y <
    # [0x596B6C] (the console art's first row, 302) -> 0; y >= [0x596B74] (its
    # first fully opaque row, 400) -> 1; otherwise a memo cache on (x,y) and then
    # storm ord442 point-in-region on the console.pcx TRANSPARENCY region
    # [0x6D5E14]. That region is built once from the 640-wide console image
    # (imgCreate 0x0041D640 has one caller, 0x004C3A03) and ord442 rejects any
    # x >= the region's width outright, so for x >= 640 and y in [302,400) -- the
    # visible map beside the console -- the answer is "over the console", and the
    # five callers that share the predicate lose their right-click order
    # (0x004564E0), their drag anchor (0x0046FF70 / 0x0048E5D0 / 0x004BD500), or
    # their contextual cursor (0x004D1460, which swaps at y=302). Guard tier 3 by
    # x: past the console image there is no console. The constant is the
    # console.pcx WIDTH (stock 640), not the screen width -- the HUD stays in the
    # left 640 columns whatever the screen is. Tiers 1 and 2 keep their bytes, so
    # the black rectangle x>=640,y>=400 stays non-playfield exactly as stock's
    # console rows do. The window is the memo probe (6 bytes, the target of tier
    # 2's `jl`, which lands on the window's START and is allowed); the cave
    # returns straight out of the predicate for x >= 640 and otherwise re-runs
    # the probe and jumps back, so the `jne` at 0x004D115F still reads its flags.
    b.cave(0x004D1159, "390d30646d00",
           "81f9" + le32(STOCK_W)      # cmp ecx, 640
           + "7c03"                    # jl  +3      (x < 640: the stock path)
           + "33c0"                    # xor eax,eax
           + "c3"                      # ret         (beyond the console image: playfield)
           + "390d30646d00",           # cmp [0x6D6430],ecx  (the displaced probe)
           "console.hittest.xguard", 3,
           "0x004D1140 isPointOverUi: x >= 640 (the console.pcx width) is bare "
           "playfield -- never ask the 640-wide console region about it (right-click "
           "orders and the contextual cursor beside the console)")

    return b


# ------------------------------- Emit --------------------------------------

HEADER_DOC = """// sc_screen_patches.h -- GENERATED by tools/renderer_patch_sites.py. DO NOT EDIT.
//
// Task 034. One record per instruction the widescreen patch rewrites, with the
// ORIGINAL bytes beside the replacement. sc_screen.cpp verifies every `expect`
// against the running image before it writes anything, and refuses the whole
// table on the first mismatch -- a table generated against a different build
// cannot half-apply.
//
// Regenerate with:
//   python tools/renderer_patch_sites.py --width %(W)d --height %(H)d
//
// Geometry in this table: screen %(W)dx%(H)d, playfield %(PF_W)dx%(PF_H)d,
// dirty grid %(COLS)dx%(ROWS)d blocks of 16x16 (%(GRID_BYTES)d bytes),
// terrain scratch pitch %(TERRAIN_PITCH)d, size %(TERRAIN_SIZE)d.
"""


def cstr(s: str) -> str:
    """Escape a note for a C string literal (the notes carry Windows paths)."""
    return s.replace("\\", "\\\\").replace('"', "'")


def emit_header(b: Builder, path: str):
    g = b.geom
    out = [HEADER_DOC % g]
    out.append("#ifndef SC_SCREEN_PATCHES_H\n#define SC_SCREEN_PATCHES_H\n")
    out.append("#include <windows.h>\n")
    out.append("#define SC_WS_SCREEN_W        %d" % g["W"])
    out.append("#define SC_WS_SCREEN_H        %d" % g["H"])
    out.append("#define SC_WS_PLAYFIELD_W     %d" % g["PF_W"])
    out.append("#define SC_WS_PLAYFIELD_H     %d" % g["PF_H"])
    out.append("#define SC_WS_GRID_COLS       %d" % g["COLS"])
    out.append("#define SC_WS_GRID_ROWS       %d" % g["ROWS"])
    out.append("#define SC_WS_GRID_BYTES      %d" % g["GRID_BYTES"])
    out.append("#define SC_WS_TERRAIN_PITCH   %d" % g["TERRAIN_PITCH"])
    out.append("#define SC_WS_TERRAIN_SIZE    %d" % g["TERRAIN_SIZE"])
    out.append("#define SC_WS_STOCK_W         %d" % STOCK_W)
    out.append("#define SC_WS_STOCK_H         %d" % STOCK_H)
    out.append("#define SC_WS_STOCK_GRID_VA   0x006CEFF8u")
    out.append("#define SC_WS_MAX_PATCH_LEN   %d" % SC_MAX_PATCH_LEN)
    out.append("#define SC_WS_MAX_CAVE_LEN    %d" % SC_MAX_CAVE_LEN)
    out.append("#define SC_WS_NO_FIXUP        0xFFu\n")
    out.append("typedef struct {")
    out.append("    DWORD       va;          // static VA, rebased by the plugin")
    out.append("    BYTE        len;")
    out.append("    BYTE        stage;       // 0..3 -- see research/renderer-viewport.md 9.3; 3 = console/input, task 071")
    out.append("    BYTE        fixupOff;    // SC_WS_NO_FIXUP, or the offset of a dword")
    out.append("    BYTE        caveLen;     // 0 = in-place rewrite; else `cave` holds the code the window jumps to")
    out.append("    DWORD       fixupAddend; // filled with (relocated grid base + this)")
    out.append("    BYTE        expect[SC_WS_MAX_PATCH_LEN];")
    out.append("    BYTE        patch[SC_WS_MAX_PATCH_LEN];  // a cave: jmp rel32 (filled at runtime) + NOPs")
    out.append("    BYTE        cave[SC_WS_MAX_CAVE_LEN];    // the re-encoded window; the plugin appends jmp back")
    out.append("    const char* name;")
    out.append("    const char* note;")
    out.append("} ScScreenPatch;\n")
    out.append("static const ScScreenPatch SC_WS_PATCHES[] = {")
    for p in b.patches:
        if p.noop:
            continue
        exp = ", ".join("0x%02X" % c for c in p.expect)
        pat = ", ".join("0x%02X" % c for c in p.patch)
        cav = ", ".join("0x%02X" % c for c in (p.cave or b"\0"))
        out.append("    // 0x%08X  %s" % (p.va, p.before))
        out.append("    //             -> %s" % p.after)
        out.append("    { 0x%08Xu, %2d, %d, %s, %d, 0x%Xu," %
                   (p.va, len(p.expect), p.stage,
                    "SC_WS_NO_FIXUP" if p.fixup_off is None else "%du" % p.fixup_off,
                    len(p.cave) if p.cave else 0,
                    p.fixup_addend))
        out.append("      { %s }," % exp)
        out.append("      { %s }," % pat)
        out.append("      { %s }," % cav)
        out.append("      \"%s\", \"%s\" }," % (cstr(p.name), cstr(p.note)))
    out.append("};\n")
    out.append("#define SC_WS_PATCH_COUNT (sizeof(SC_WS_PATCHES)/sizeof(SC_WS_PATCHES[0]))\n")
    out.append("#endif  // SC_SCREEN_PATCHES_H")
    with open(path, "w", encoding="ascii", newline="\n") as f:
        f.write("\n".join(out) + "\n")


def emit_tsv(b: Builder, path: str):
    rows = ["stage\tva\tlen\tchanged\tname\tbefore\tafter\texpect\tpatch\tcave\tnote"]
    for p in b.patches:
        rows.append("\t".join([
            str(p.stage), "0x%08X" % p.va, str(len(p.expect)),
            "0" if p.noop else "1", p.name,
            p.before, p.after, p.expect.hex().upper(), p.patch.hex().upper(),
            p.cave.hex().upper() if p.cave else "",
            p.note,
        ]))
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(rows) + "\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--exe", default=DEFAULT_EXE)
    ap.add_argument("--width", type=int, default=1280)
    ap.add_argument("--height", type=int, default=480)
    ap.add_argument("--playfield-height", type=int, default=400)
    ap.add_argument("--check", action="store_true", help="verify only; write nothing")
    a = ap.parse_args()

    img = Image(a.exe)
    b = build(img, a.width, a.height, a.playfield_height)

    if b.errors:
        print("renderer_patch_sites: %d site(s) FAILED verification" % len(b.errors))
        for e in b.errors:
            print("  " + e)
        return 1

    if b.warnings:
        print("renderer_patch_sites: %d warning(s) -- each has been read by hand" % len(b.warnings))
        for w in b.warnings:
            print("  " + w)

    live = [p for p in b.patches if not p.noop]
    caves = [p for p in b.patches if p.cave]
    print("renderer_patch_sites: %d site(s) verified against %s (%d write, %d already "
          "correct at %dx%d, %d code cave(s))"
          % (len(b.patches), a.exe, len(live), len(b.patches) - len(live), a.width, a.height,
             len(caves)))
    by_stage = {}
    for p in b.patches:
        by_stage.setdefault(p.stage, []).append(p)
    for s in sorted(by_stage):
        n = len(by_stage[s])
        w = len([p for p in by_stage[s] if not p.noop])
        print("  stage %d: %d site(s), %d written" % (s, n, w))

    if a.check:
        return 0

    hdr = os.path.join(REPO, "tools", "plugin", "src", "sc_screen_patches.h")
    tsv = os.path.join(REPO, "research", "data", "renderer-widescreen-patches.tsv")
    emit_header(b, hdr)
    emit_tsv(b, tsv)
    print("  wrote %s" % hdr)
    print("  wrote %s" % tsv)
    return 0


if __name__ == "__main__":
    sys.exit(main())
