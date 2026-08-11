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

try:
    from capstone import Cs, CS_ARCH_X86, CS_MODE_32
    from capstone.x86_const import X86_REG_EFLAGS
except ImportError:  # pragma: no cover
    sys.exit("renderer_patch_sites: capstone is required (pip install capstone)")

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_EXE = r"C:\sc-work\1161-base\StarCraft.exe"

# The stock geometry every site below is declared against. A site whose current
# bytes do not carry the stock value is refused, which is what makes this table
# specific to 1.16.1 rather than hopeful.
STOCK_W = 640
STOCK_H = 480
STOCK_PF_H = 400          # playfield height; the console occupies 400..479
STOCK_TERRAIN_PITCH = 672  # 640 + 32, one tile of margin
STOCK_TERRAIN_ROWS = 448   # 400 + 48
STOCK_BLOCK = 16           # dirty-grid block size, both axes
STOCK_COLS = STOCK_W // STOCK_BLOCK   # 40
STOCK_ROWS = STOCK_H // STOCK_BLOCK   # 30

# Longest single rewrite the plugin's record can hold. The reordered windows that
# fix the EFLAGS hazard are the long ones -- 0x0042D2C7 swallows three unrelated
# stores between the compare and the branch.
SC_MAX_PATCH_LEN = 32


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


# ---------------------------------------------------------------------------
# Patch records
# ---------------------------------------------------------------------------

class Patch:
    """One instruction-level rewrite.

    `expect` is the exact original bytes; the plugin refuses the whole table if
    any site fails to match. `fixup_off`/`fixup_addend`, when set, name a dword
    inside `patch` that the plugin fills at runtime with (relocated grid base +
    addend) -- the dirty grid moves to plugin-owned memory whose address is not
    known until the process is up.
    """

    def __init__(self, va, expect, patch, name, stage, note,
                 fixup_off=None, fixup_addend=0, before="", after=""):
        assert len(expect) == len(patch), name
        assert len(patch) <= SC_MAX_PATCH_LEN,             "%s: %d-byte rewrite exceeds SC_MAX_PATCH_LEN" % (name, len(patch))
        # A site whose stock value is already correct for the chosen geometry --
        # every 480/400 site when only the width changes. Kept in the evidence
        # table (it is still a site the map has to name) but not handed to the
        # plugin: writing a byte back over itself is a patch that can only ever
        # go wrong.
        self.noop = (expect == patch and fixup_off is None)
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


class Builder:
    def __init__(self, img: Image, geom: dict):
        self.img = img
        self.geom = geom
        self.patches: list[Patch] = []
        self.errors: list[str] = []
        self.warnings: list[str] = []

    # -- immediate rewrite ---------------------------------------------------
    # -- flags safety --------------------------------------------------------
    def check_flags(self, p: "Patch"):
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
        orig = disasm_all(p.va, p.expect)
        new = disasm_all(p.va, p.patch)
        if not orig or not new:
            return
        orig_writes = any(touches_flags(i)[1] for i in orig)
        new_writes = any(touches_flags(i)[1] for i in new)
        if orig_writes and new_writes:
            # Both write flags, but not necessarily the SAME flags: changing
            # `shl r,3` to `shl r,1` changes SF/ZF/CF as well as the result. Only
            # a warning, because the window may legitimately contain the setter
            # a downstream branch wants (the reorder case) -- but every one of
            # these gets read by a human before the table ships.
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
        # NOTE the exemption is `orig_writes`, above, and nothing else. An earlier
        # version of this check also exempted a window whose LAST instruction sets
        # flags, reasoning that a deliberate reorder puts the setter last -- which
        # exempted every single-instruction `lea`->`imul` swap, i.e. exactly the
        # sites the check exists for, and it reported a clean table over a broken
        # game. A reorder is safe because the window then CONTAINS the original
        # `cmp`, which makes `orig_writes` true on its own; it needs no second rule.
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
        patched = bytearray(raw)
        patched[off:off + width] = new.to_bytes(width, "little")
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


# ---------------------------------------------------------------------------
# The site table
# ---------------------------------------------------------------------------

def build(img: Image, W: int, H: int, PF_H: int) -> Builder:
    PF_W = W                       # the playfield spans the full width
    TERRAIN_PITCH = PF_W + 32      # stock: 640 + 32
    TERRAIN_SIZE = TERRAIN_PITCH * STOCK_TERRAIN_ROWS
    COLS = W // STOCK_BLOCK
    # ROUNDED UP: a height that is not a multiple of the 16-pixel block still needs
    # a row for the partial one, and the engine's `y >> 4` will index it. 480 gives
    # 30 exactly; 600 gives 38, not 37.
    ROWS = (H + STOCK_BLOCK - 1) // STOCK_BLOCK
    GRID_BYTES = COLS * ROWS

    geom = dict(W=W, H=H, PF_W=PF_W, PF_H=PF_H, COLS=COLS, ROWS=ROWS,
                GRID_BYTES=GRID_BYTES, TERRAIN_PITCH=TERRAIN_PITCH,
                TERRAIN_SIZE=TERRAIN_SIZE)
    b = Builder(img, geom)

    # =====================================================================
    # STAGE 0 -- the display mode, and nothing else.
    #
    # §9.3's cheapest possible falsification: does the presentation half come
    # up at all at a non-640x480 mode? Everything the engine renders is still
    # 640x480 after this, so the expected outcome is a small image in the
    # corner of a bigger one.
    # =====================================================================
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
    # =====================================================================

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
    # A THIRD allocate-and-describe site, not in 032's table -- found by this
    # task's own sweep. It is a second copy of the video init, same file and
    # same line number (vidinimo.cpp:0x37), and it allocates its own buffer.
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

    # -- the screen FILL helper 0x0041D3A0 (new in task 034) ---------------
    # The composer's whole-screen-clear branch calls this. It carries the screen
    # pitch TWICE, and only one of them is an immediate: the other is
    # `lea edi,[eax+eax*4]; shl edi,7`, i.e. y*5<<7 == y*640. An immediate sweep
    # is blind to that shape, which is why 032's table does not have it and why
    # this task went looking for it (work/scratch/034/scan_mul.py found four
    # such multiplies in the whole binary; the other three are stage 2 fog).
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
    # Stage 1 rather than stage 4: the composer clips every layer to the screen
    # and a dialog layer still 640 wide would clip the cursor layer's redraw of
    # the right-hand strip.
    b.imm(0x0041A049, STOCK_W, W, 2, "layer2.width", 2, "dialog layer width")
    b.imm(0x0041A052, STOCK_H, H, 2, "layer2.height", 2, "dialog layer height")

    # -- the copier's DESTINATION pitch (new in task 034) ------------------
    # 0x0040C2BD computes the destination address from the screen Bitmap
    # descriptor, so it follows the new width for free -- but the row step
    # inside the copy loop it calls is a hardcoded 640. Not in 032's §8 table;
    # without it every terrain row lands one row-fragment further left.
    b.imm(0x0040C247, STOCK_W, W, 4, "copyrun.destpitch", 1,
          "row step of the scratch->screen copy loop (new in task 034)")

    # -- fog: FRAMEBUFFER ADDRESSING, which is stage 1, not stage 2 --------
    #
    # These were in stage 2 with the rest of the fog and that was WRONG, in a way
    # a live run caught and no amount of reading would have. The rule that sorts
    # them is: a site that computes an address INTO THE FRAMEBUFFER moves when the
    # framebuffer widens (stage 1); a site that CLIPS to the playfield moves when
    # the playfield widens (stage 2). Fog has both, and at 800x480 they are the
    # same number, so nothing in the source distinguishes them.
    #
    # The enumeration is exhaustive rather than hopeful: every routine that writes
    # the framebuffer must load the pointer at 0x006CEFF4, and a scan of .text for
    # that address finds 19 instructions. Three of them -- 0x0047EDCC, 0x0047EF35,
    # 0x00480631 -- are immediately followed by a `lea r,[y+y*4]` + `shl r,7`, i.e.
    # y*640 into the frame. Left at stage 1 the fog wrote every row at the old
    # pitch, and the playfield came out sheared while the descriptor, the layer
    # rects and the HUD all still read correctly.
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
    # "row step = pitch - run width". Left at 640 it walked the shroud down the
    # frame at the old stride while everything else used the new one -- and
    # because the shroud is only drawn at the edges of an explored map, the damage
    # was a frame around the playfield with the middle perfectly intact. That is
    # what made it survive a centre-weighted look and what the block map found.
    b.imm(0x0047EA6B, STOCK_W, W, 4, "fog.rowpitch.writer", 1,
          "FUN_0047EA60: dest row step is (pitch - run width) -- FRAMEBUFFER pitch")
    # The inner blend loops step one framebuffer row at a time.
    for va in (0x0047FFDE, 0x00480087):
        b.imm(va, STOCK_W, W, 4, "fog.rowstep@%08X" % va, 1,
              "fog blend loop: advance one FRAMEBUFFER row")

    # -- the dirty grid (item 5): relocation ------------------------------
    # 0x006CEFF8's u8[30][40] cannot grow in place -- 0x006CF4A8 is the live
    # render-target pointer, and 126 instructions name it. So the grid moves to
    # plugin-owned memory and every absolute reference is re-pointed. The
    # references were enumerated by scanning .text for the encoded address
    # (work/scratch/034/scan_refs.py): 21 in total, not the 62 instructions
    # 032 counted -- that count included register-derived accesses inside loops,
    # which follow the base they were loaded from.
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

    # References that name a ROW rather than the array: their offset is
    # recomputed for the new stride instead of carried across.
    b.rebase(0x0048CC00, 0x006CF03A, 1 * COLS + 26, "grid.row1col26", 2,
             "0x0048CB80 names grid[row 1][col 26]; recomputed for the new stride")
    b.rebase(0x004B2314, 0x006CF2C8, 18 * COLS, "grid.row18", 2,
             "0x004B1FA0 names grid[row 18][col 0]; recomputed for the new stride")

    # Row addressing: `lea r,[c+c*4]` (x5) feeding a SIB scale of 8 gives the
    # stock stride of 40. For 50 the multiply becomes x25 and the scale becomes
    # x2 -- a 3-byte-for-3-byte swap plus one SIB nibble, which is why the
    # stride is reachable at all.
    assert COLS % 2 == 0, "the x25/scale-2 rewrite needs an even column count"
    HALF = COLS // 2
    assert HALF <= 127, "imul r32,r/m32,imm8 needs the half-stride to fit a signed byte"

    # 0x0041E0D0, the dirty marker.
    #
    # THE WINDOW INCLUDES THE `cmp` AND THE `jg` ON PURPOSE. `lea` leaves EFLAGS
    # alone and `imul` does not, and here a `cmp ecx,esi` two bytes earlier is
    # consumed by a `jg` five bytes later. Splicing the multiply between them --
    # which is what the first version of this table did -- makes the marker branch
    # on the multiply's flags, so whole bands of blocks are never marked dirty and
    # never redrawn. The frame comes out shredded while every read-back still says
    # 800x400, because the layer rect is the plugin's bookkeeping and the pixels
    # are the engine's result.
    #
    # The fix is a reorder, not a longer sequence: the same 14 bytes hold
    # imul / lea / cmp / jg, the `jg` keeps its address so its rel8 is unchanged,
    # and the flag setter is now the last thing before the branch that reads it.
    b.code(0x0041E15B,
           "3bce" "8d0489" "8d9cc7f8ef6c00" "7f2a",
           "6bc1" + bytes([HALF]).hex() + "8d9c47" + "00000000" + "3bce" "7f2a",
           "grid.rowaddr.marker", 2,
           "dirty marker: eax = row * %d, ebx = grid + row*%d + col; cmp/jg moved "
           "after the multiply so the branch still reads the compare" % (HALF, COLS),
           fixup_off=6, fixup_addend=0)
    b.imm(0x0041E18A, STOCK_COLS, COLS, 1, "grid.rowstep.marker", 2,
          "dirty marker: next row is +40 bytes")

    # 0x0041DE20, the "is this rectangle dirty" test.
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
    # reads of the grid. These are grid references, so they belong to stage 1 with
    # the relocation -- NOT to stage 2 with the rest of the fog geometry. Leaving
    # them behind is a bug that hides at the main menu and only appears in game:
    # the fog would go on reading an array nothing writes any more, so it would
    # believe the screen was never dirty. (Found exactly that way: stage 1 passed
    # its menu-only run with these missing.)
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

    # The three `rep stosd` clears of the whole grid: 300 dwords -> COLS*ROWS/4.
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
    # STAGE 2 -- the playfield geometry. 9.3 calls this "the stage that can
    # actually look wrong", and it is where the count stops being the problem
    # and the SHAPE of each site starts being the problem.
    # =====================================================================

    # -- item 8: the terrain scratch surface -------------------------------
    # A second fixed-size buffer, 672x448, allocated at 0x004BD745 into
    # 0x00628454 (task 032 3 10 item 3 records its producer as unread; it is
    # 0x0040AAE0, and the family around it). Its pitch and its wrap size are
    # immediates in the routines that read AND write it, so both move together.
    b.imm(0x004BD745, STOCK_TERRAIN_PITCH * STOCK_TERRAIN_ROWS, TERRAIN_SIZE, 4,
          "terrain.alloc", 2, "SMemAlloc size of the terrain scratch surface")

    for va, note in [
        (0x0040AAFE, "terrain WRITER 0x0040AAE0: row stride"),
        (0x0040C23A, "scratch->screen copy: source row step"),
        (0x0040C240, "scratch->screen copy: source offset row step"),
        (0x0040C402, "scratch writer (8-pixel run): row step"),
        (0x0040C44C, "scratch writer (8-pixel run): row step"),
        (0x004BCDD1, "terrain blitter: screenTop * pitch"),
    ]:
        b.imm(va, STOCK_TERRAIN_PITCH, TERRAIN_PITCH, 4,
              "terrain.pitch@%08X" % va, 2, note)

    # The SAME multiply, decomposed into shifts, in the full-playfield blit:
    # 672 == (t<<9)+(t<<7)+(t<<5). No 672 appears in that function, so neither an
    # immediate sweep nor a lea+shl scan finds it -- and it positions every
    # terrain row the non-dirty path draws. 832 == (t<<9)+(t<<8)+(t<<6), so the
    # decomposition survives with two single-byte edits; a pitch that was not a
    # sum of three powers of two would have needed the whole block rewritten.
    assert TERRAIN_PITCH == 832, \
        "the shift-decomposed pitch at 0x0040C275 is only a 3-term sum for 832"
    b.code(0x0040C27E, "c1e307", "c1e308", "terrain.pitch.shift.b", 2,
           "0x0040C253: shl ebx,7 -> shl ebx,8 (the 128 term becomes 256)")
    b.code(0x0040C281, "c1e105", "c1e106", "terrain.pitch.shift.c", 2,
           "0x0040C253: shl ecx,5 -> shl ecx,6 (the 32 term becomes 64)")

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
    # step that is `pitch*16 - width` because the column loop already advanced it
    # by 16 per column. (032 read this as 0x2790 == 672*16-640+16; the instruction
    # is 0x2780 == 672*16-640. Corrected here from the encoding.)
    for va in (0x004BCE0E, 0x004BCE28, 0x004BCE66):
        b.imm(va, STOCK_COLS, COLS, 1, "terrain.cols@%08X" % va, 2,
              "terrain blitter: columns per row")
    b.imm(0x004BCE6E, STOCK_TERRAIN_PITCH * 16 - STOCK_W,
          TERRAIN_PITCH * 16 - PF_W, 4, "terrain.rowstep", 2,
          "terrain blitter: advance to the next 16 scanlines")
    b.imm(0x0040C25A, STOCK_W, PF_W, 4, "terrain.fullblit.runwidth", 2,
          "0x0040C253: the run width of the whole-playfield blit")

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

    return b


# ---------------------------------------------------------------------------
# Emit
# ---------------------------------------------------------------------------

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
    out.append("#define SC_WS_NO_FIXUP        0xFFu\n")
    out.append("typedef struct {")
    out.append("    DWORD       va;          // static VA, rebased by the plugin")
    out.append("    BYTE        len;")
    out.append("    BYTE        stage;       // 0, 1 or 2 -- see research/renderer-viewport.md 9.3")
    out.append("    BYTE        fixupOff;    // SC_WS_NO_FIXUP, or the offset of a dword")
    out.append("    DWORD       fixupAddend; // filled with (relocated grid base + this)")
    out.append("    BYTE        expect[SC_WS_MAX_PATCH_LEN];")
    out.append("    BYTE        patch[SC_WS_MAX_PATCH_LEN];")
    out.append("    const char* name;")
    out.append("    const char* note;")
    out.append("} ScScreenPatch;\n")
    out.append("static const ScScreenPatch SC_WS_PATCHES[] = {")
    for p in b.patches:
        if p.noop:
            continue
        exp = ", ".join("0x%02X" % c for c in p.expect)
        pat = ", ".join("0x%02X" % c for c in p.patch)
        out.append("    // 0x%08X  %s" % (p.va, p.before))
        out.append("    //             -> %s" % p.after)
        out.append("    { 0x%08Xu, %2d, %d, %s, 0x%Xu," %
                   (p.va, len(p.expect), p.stage,
                    "SC_WS_NO_FIXUP" if p.fixup_off is None else "%du" % p.fixup_off,
                    p.fixup_addend))
        out.append("      { %s }," % exp)
        out.append("      { %s }," % pat)
        out.append("      \"%s\", \"%s\" }," % (cstr(p.name), cstr(p.note)))
    out.append("};\n")
    out.append("#define SC_WS_PATCH_COUNT (sizeof(SC_WS_PATCHES)/sizeof(SC_WS_PATCHES[0]))\n")
    out.append("#endif  // SC_SCREEN_PATCHES_H")
    with open(path, "w", encoding="ascii", newline="\n") as f:
        f.write("\n".join(out) + "\n")


def emit_tsv(b: Builder, path: str):
    rows = ["stage\tva\tlen\tchanged\tname\tbefore\tafter\texpect\tpatch\tnote"]
    for p in b.patches:
        rows.append("\t".join([
            str(p.stage), "0x%08X" % p.va, str(len(p.expect)),
            "0" if p.noop else "1", p.name,
            p.before, p.after, p.expect.hex().upper(), p.patch.hex().upper(),
            p.note,
        ]))
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(rows) + "\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--exe", default=DEFAULT_EXE)
    ap.add_argument("--width", type=int, default=800)
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
    print("renderer_patch_sites: %d site(s) verified against %s (%d write, %d already "
          "correct at %dx%d)"
          % (len(b.patches), a.exe, len(live), len(b.patches) - len(live), a.width, a.height))
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
