#!/usr/bin/env python3
"""Decode, validate and compare FRAMEDUMP files -- the engine's own composed frame.

Task 063. The plugin's FRAMEDUMP (scplugin.cpp) copies the screen Bitmap's own
8-bit buffer (0x006CEFF0: u16 w, u16 h, u8* data, pitch == width) to a file on
each marker. That is the one instrument that sees the columns the presented
window discards (research/renderer-viewport.md 12.6/12.10) -- but an instrument
is worthless until it has been shown to reproduce a KNOWN-GOOD picture, and a
raw dump of palette indices is not a picture anyone can look at.

Both problems have the same solution, and it is this file's `check` command:

  The dump holds palette INDICES. The presented window holds the RGB those
  indices were painted as, at 1:1 for columns 0..639 (12.6, measured). So over
  the region both instruments see, every occurrence of index i must correspond
  to ONE RGB value. `check` builds that index->RGB mapping from a window
  capture and reports how consistent it is:

    - if the dump were torn, misaligned, or read with the wrong pitch, one
      index would land on many RGBs and consistency collapses -- rows shifting
      by (pitch - width) per row destroys the correspondence in the first
      handful of rows;
    - if it holds at ~100%, the dump IS the picture the window presented, and
      the mapping doubles as the scene's palette, which `render` then uses to
      turn any dump from the same scene into a viewable PNG -- including the
      columns no window has ever shown.

  Animation between the window grab and the dump would poison the mapping, so
  `check` takes TWO window captures, one before the dump and one after, and
  builds the mapping only over pixels identical in both -- a pixel the window
  shows unchanged across the whole interval was, with overwhelming likelihood,
  unchanged when the dump was read between them.

Commands (all output is `key=value` lines, one per metric, like frame-diff.py):

  info    --dump FD.bin
  check   --dump FD.bin --before B.png --after A.png [--map-w N] [--render OUT.png]
          [--save-palette PAL.json] [--search-dy N] [--search-dx N]
  render  --dump FD.bin --palette PAL.json --out OUT.png
  band    --dump FD.bin --x0 N [--x1 N] [--y0 N] [--y1 N]
  diff    --a FD.bin --b FD.bin [--x0 N] [--x1 N] [--y0 N] [--y1 N]
  mapdiff --a FD.bin --ax N --ay N --b FD.bin --bx N --by N --x0 N --y0 N --x1 N --y1 N
          (A's screen rect compared in MAP space: each dump's camera is its --ax/--ay)
  diffbox --a BASE.bin --b HOVER.bin [--x0 N] [--y0 N] [--x1 N] [--y1 N]
          (bounding box of what B shows that A does not, and how solid a BOX it is)
  unmarked-diff --a A.bin --b B.bin --marks MARKS.txt [--pad N] [--x0 N] [--y0 N] [--x1 N] [--y1 N]
          (pixels that changed OUTSIDE every rect the engine marked dirty between the dumps)
  selftest
          (synthetic frames through diffbox and unmarked-diff; exit 1 when a detector lies)

Hard rule 1: dumps and rendered PNGs reproduce game artwork. They live on the
gitignored diagnostic path and are never committed; what this tool PRINTS is
counts, fractions and indices, which reproduce nothing.
"""
import argparse
import json
import struct
import sys
from collections import Counter

try:
    from PIL import Image
except ImportError:
    sys.exit("frame-capture: Pillow is required (pip install pillow)")

MAGIC = b"SCFD"
HDR_LEN = 16


def load_dump(path):
    with open(path, "rb") as f:
        hdr = f.read(HDR_LEN)
        if len(hdr) != HDR_LEN or hdr[:4] != MAGIC:
            sys.exit("frame-capture: %s is not a FRAMEDUMP file (bad magic)" % path)
        w, h, nbytes, reads, stable = struct.unpack("<HHIHH", hdr[4:])
        px = f.read(nbytes)
    if len(px) != nbytes or nbytes != w * h:
        sys.exit("frame-capture: %s truncated (header says %d bytes, file holds %d)"
                 % (path, nbytes, len(px)))
    return {"w": w, "h": h, "reads": reads, "stable": stable, "px": px}


def cmd_info(a):
    d = load_dump(a.dump)
    print("dump_w=%d" % d["w"])
    print("dump_h=%d" % d["h"])
    print("dump_bytes=%d" % (d["w"] * d["h"]))
    print("dump_reads=%d" % d["reads"])
    print("dump_stable=%d" % d["stable"])
    return 0


def build_mapping(d, before, after, dx, dy, map_w, step=1, x0=0, y0=0, map_h=0):
    """index -> Counter(rgb) over pixels stable across both window captures.

    Window pixel (x, y) is compared against dump pixel (x - dx, y - dy):
    dx/dy is where the frame's (0,0) sits inside the capture. (x0,y0) and
    (map_w,map_h) bound the mapped region in DUMP coordinates.
    """
    pb, pa = before.load(), after.load()
    w = min(map_w, d["w"], before.size[0] - dx, after.size[0] - dx)
    h = min(map_h if map_h else d["h"], d["h"],
            before.size[1] - dy, after.size[1] - dy)
    px, dw = d["px"], d["w"]
    mapping = {}
    stable_px = 0
    total = 0
    for y in range(y0, h, step):
        row = (y) * dw
        wy = y + dy
        for x in range(x0, w, step):
            total += 1
            rgb = pb[x + dx, wy]
            if rgb != pa[x + dx, wy]:
                continue
            stable_px += 1
            idx = px[row + x]
            c = mapping.get(idx)
            if c is None:
                mapping[idx] = c = Counter()
            c[rgb] += 1
    return mapping, stable_px, total


def score_mapping(mapping):
    total = dominant = 0
    for c in mapping.values():
        s = sum(c.values())
        total += s
        dominant += c.most_common(1)[0][1]
    return (dominant / total if total else 0.0), total


def cmd_check(a):
    d = load_dump(a.dump)
    before = Image.open(a.before).convert("RGB")
    after = Image.open(a.after).convert("RGB")
    map_w = a.map_w if a.map_w else d["w"]

    print("dump_w=%d" % d["w"])
    print("dump_h=%d" % d["h"])
    print("dump_reads=%d" % d["reads"])
    print("dump_stable=%d" % d["stable"])
    print("before_size=%dx%d" % before.size)
    print("after_size=%dx%d" % after.size)
    print("map_w=%d" % map_w)
    print("check_region=%d,%d-%d,%d" % (a.x0, a.y0, map_w, a.y1 if a.y1 else d["h"]))

    # Alignment: where does the frame's (0,0) sit inside the capture? The
    # windowed helper presents 1:1 (research/renderer-viewport.md 12.6), but a
    # capture may include a caption strip above the client pixels. Search a
    # small offset range on a sampled grid and keep the offset that maximises
    # consistency; (0,0) is in range, so needing no offset costs nothing.
    if a.align_dx is not None and a.align_dy is not None:
        # A pinned offset for callers who KNOW their capture geometry. The
        # search can mislock: sprite noise at step=4 rewards (8,36) on a
        # 36-marine scene whose true offset is (5,32), and a 3,4-px mislock
        # reads as consistency 0.34 over a perfect dump. A wrong pin collapses
        # consistency just as loudly, so it can never pass silently.
        best = (a.align_dx, a.align_dy)
    else:
        best = (0, 0)
        best_score = -1.0
        for dy in range(0, a.search_dy + 1):
            m, _, _ = build_mapping(d, before, after, 0, dy, map_w, step=4)
            s, n = score_mapping(m)
            if n and s > best_score:
                best_score, best = s, (0, dy)
        for dx in range(0, a.search_dx + 1):
            m, _, _ = build_mapping(d, before, after, dx, best[1], map_w, step=4)
            s, n = score_mapping(m)
            if n and s > best_score:
                best_score, best = s, (dx, best[1])
    dx, dy = best
    print("align_dx=%d" % dx)
    print("align_dy=%d" % dy)

    # The region matters: the screen Bitmap does NOT hold the whole presented
    # frame -- the console/HUD dialogs live in their own surfaces and the cursor
    # is absent -- so a whole-frame comparison fails structurally, not because
    # the dump is wrong. Callers pass the pure-playfield region.
    mapping, stable_px, total = build_mapping(d, before, after, dx, dy, map_w,
                                              step=1, x0=a.x0, y0=a.y0, map_h=a.y1)
    consist, mapped = score_mapping(mapping)
    clean = sum(1 for c in mapping.values() if len(c) == 1)

    # Consistency is VACUOUS over a dead capture: a black window maps every
    # index to (0,0,0), each one perfectly consistently. The window must prove
    # it holds a picture at all, so callers assert on these two beside
    # consist_frac, never on consist_frac alone.
    pb = before.load()
    rgbs = set()
    nonblack = win_n = 0
    for y in range(0, before.size[1], 2):
        for x in range(0, before.size[0], 2):
            v = pb[x, y]
            rgbs.add(v)
            win_n += 1
            if v != (0, 0, 0):
                nonblack += 1
    print("window_distinct_rgb=%d" % len(rgbs))
    print("window_nonblack_frac=%.4f" % (nonblack / win_n if win_n else 0))

    print("window_px=%d" % total)
    print("stable_px=%d" % stable_px)
    print("stable_frac=%.4f" % (stable_px / total if total else 0))
    print("consist_frac=%.5f" % consist)
    print("indices_seen=%d" % len(mapping))
    print("indices_clean=%d" % clean)

    palette = {str(i): list(c.most_common(1)[0][0]) for i, c in mapping.items()}
    if a.save_palette:
        with open(a.save_palette, "w") as f:
            json.dump(palette, f)
        print("palette_saved=%s" % a.save_palette)

    if a.render:
        render_dump(d, palette, a.render)
        print("render=%s" % a.render)
        known = sum(1 for i in d["px"] if str(i) in palette)
        print("render_mapped_frac=%.4f" % (known / len(d["px"]) if d["px"] else 0))
    return 0


def render_dump(d, palette, out):
    w, h, px = d["w"], d["h"], d["px"]
    img = Image.new("RGB", (w, h))
    p = img.load()
    lut = {}
    for k, v in palette.items():
        lut[int(k)] = tuple(v)
    magenta = (255, 0, 255)
    for y in range(h):
        row = y * w
        for x in range(w):
            p[x, y] = lut.get(px[row + x], magenta)
    img.save(out)


def cmd_render(a):
    d = load_dump(a.dump)
    with open(a.palette) as f:
        palette = json.load(f)
    render_dump(d, palette, a.out)
    known = sum(1 for i in d["px"] if str(i) in palette)
    print("dump_w=%d" % d["w"])
    print("dump_h=%d" % d["h"])
    print("render=%s" % a.out)
    print("render_mapped_frac=%.4f" % (known / len(d["px"]) if d["px"] else 0))
    return 0


def cmd_band(a):
    d = load_dump(a.dump)
    x1 = a.x1 if a.x1 else d["w"]
    y1 = a.y1 if a.y1 else d["h"]
    px, w = d["px"], d["w"]
    hist = Counter()
    for y in range(a.y0, y1):
        row = y * w
        hist.update(px[row + a.x0:row + x1])
    total = sum(hist.values())
    nonzero = total - hist.get(0, 0)
    print("band_region=%d,%d-%d,%d" % (a.x0, a.y0, x1, y1))
    print("band_px=%d" % total)
    print("band_nonzero=%d" % nonzero)
    print("band_nonzero_frac=%.4f" % (nonzero / total if total else 0))
    print("band_distinct=%d" % len(hist))
    print("band_top=%s" % ",".join("%d:%d" % (i, n) for i, n in hist.most_common(8)))
    return 0


def cmd_zeroruns(a):
    """Task 064: where are the all-zero COLUMNS? The seam tracker.

    Reports maximal runs of x-columns that are index 0 over every row of
    y0..y1, inside x0..x1. Run it on each capture of a moving-camera pair:
    a screen-space defect keeps its run at the same x; a map-space defect's
    run moves with the scroll.
    """
    d = load_dump(a.dump)
    x1 = a.x1 if a.x1 else d["w"]
    y1 = a.y1 if a.y1 else d["h"]
    px, w = d["px"], d["w"]
    runs = []
    start = None
    for x in range(a.x0, x1):
        allzero = all(px[y * w + x] == 0 for y in range(a.y0, y1))
        if allzero and start is None:
            start = x
        elif not allzero and start is not None:
            runs.append((start, x - 1))
            start = None
    if start is not None:
        runs.append((start, x1 - 1))
    print("zeroruns_region=%d,%d-%d,%d" % (a.x0, a.y0, x1, y1))
    print("zeroruns_n=%d" % len(runs))
    print("zeroruns=%s" % ";".join("%d-%d" % r for r in runs))
    return 0


def cmd_diff(a):
    """frame-diff.py's full-resolution SHAPE metrics, on raw indices.

    Same discriminator, one layer down: a pitch/stride error shifts whole rows,
    so its damage SPANS the region (wide_rows large); animation is local blobs
    (wide_rows 0). Comparing indices needs no palette and no rendering, so two
    dumps from two arms compare directly.
    """
    da, db = load_dump(a.a), load_dump(a.b)
    x1 = min(a.x1 if a.x1 else min(da["w"], db["w"]), da["w"], db["w"])
    y1 = min(a.y1 if a.y1 else min(da["h"], db["h"]), da["h"], db["h"])
    x0, y0 = a.x0, a.y0
    width = x1 - x0
    pa, pb = da["px"], db["px"]
    wa, wb = da["w"], db["w"]

    print("a_size=%dx%d" % (da["w"], da["h"]))
    print("b_size=%dx%d" % (db["w"], db["h"]))
    print("region=%d,%d-%d,%d" % (x0, y0, x1, y1))

    diff_px = 0
    blocks = set()
    wide_rows = []
    dense_rows = []
    span_max = 0
    row_max = 0
    for y in range(y0, y1):
        ra, rb = y * wa, y * wb
        first = last = -1
        row_n = 0
        for x in range(x0, x1):
            if pa[ra + x] != pb[rb + x]:
                diff_px += 1
                row_n += 1
                if first < 0:
                    first = x
                last = x
                blocks.add((x // 32, y // 32))
        row_max = max(row_max, row_n)
        if first >= 0:
            span = last - first + 1
            span_max = max(span_max, span)
            if span > width // 2:
                wide_rows.append(y)
            # Span conflates "a row OF sprites" with "a damaged row": six idle
            # marines span 337px of diffs at 3-8% row coverage and read as wide.
            # A pitch/stride error FILLS rows (~70% of the row, measured in
            # research/renderer-viewport.md 12.9), so the COUNT separates where
            # the span cannot. dense is the assertable one.
            if row_n > width // 2:
                dense_rows.append(y)

    print("diff_px=%d" % diff_px)
    print("diff_px_frac=%.5f" % (diff_px / float(width * (y1 - y0)) if width and y1 > y0 else 0))
    print("diff_blocks=%d" % len(blocks))
    print("diff_span_max=%d" % span_max)
    print("diff_row_max=%d" % row_max)
    print("wide_rows=%d" % len(wide_rows))
    print("wide_row_ys=%s" % ",".join(str(y) for y in wide_rows[:40]))
    print("dense_rows=%d" % len(dense_rows))
    print("dense_row_ys=%s" % ",".join(str(y) for y in dense_rows[:40]))
    return 0


def cmd_mapdiff(a):
    """Compare a rect across two dumps taken at DIFFERENT camera positions.

    The rect is given in A's screen space; a pixel's map position is its screen
    position plus A's camera, and it is looked up in B through B's camera. Only
    pixels inside both frames count. `gained` is black (index 0) in A and not in
    B -- what a fog defect that reveals map leaves behind; `lost` is the reverse.
    """
    da, db = load_dump(a.a), load_dump(a.b)
    pa, pb = da["px"], db["px"]
    wa, ha, wb, hb = da["w"], da["h"], db["w"], db["h"]
    dx, dy = a.ax - a.bx, a.ay - a.by
    x1 = a.x1 if a.x1 else wa
    y1 = a.y1 if a.y1 else ha
    overlap = gained = lost = changed = 0
    for y in range(a.y0, min(y1, ha)):
        yb = y + dy
        if yb < 0 or yb >= hb:
            continue
        ra, rb = y * wa, yb * wb
        for x in range(a.x0, min(x1, wa)):
            xb = x + dx
            if xb < 0 or xb >= wb:
                continue
            va, vb = pa[ra + x], pb[rb + xb]
            overlap += 1
            if va != vb:
                changed += 1
                if va == 0:
                    gained += 1
                elif vb == 0:
                    lost += 1
    print("mapdiff_region=%d,%d-%d,%d" % (a.x0, a.y0, x1, y1))
    print("mapdiff_shift=%d,%d" % (dx, dy))
    print("mapdiff_overlap=%d" % overlap)
    print("mapdiff_changed=%d" % changed)
    print("mapdiff_gained=%d" % gained)
    print("mapdiff_lost=%d" % lost)
    return 0


def clip_window(a, da, db):
    """The --x0/--y0/--x1/--y1 window clamped to what BOTH dumps hold."""
    x1 = min(a.x1 if a.x1 else min(da["w"], db["w"]), da["w"], db["w"])
    y1 = min(a.y1 if a.y1 else min(da["h"], db["h"]), da["h"], db["h"])
    return a.x0, a.y0, x1, y1


def changed_pixels(da, db, x0, y0, x1, y1):
    """Yield (x, y) for every pixel that differs between the dumps inside the window."""
    pa, pb = da["px"], db["px"]
    wa, wb = da["w"], db["w"]
    for y in range(y0, y1):
        ra, rb = y * wa, y * wb
        if pa[ra + x0:ra + x1] == pb[rb + x0:rb + x1]:
            continue
        for x in range(x0, x1):
            if pa[ra + x] != pb[rb + x]:
                yield x, y


class BBox(object):
    """Running bounding box; .n counts the points, .text is 'none' or 'l,t-r,b'."""
    def __init__(self):
        self.n = 0
        self.l = self.t = 1 << 30
        self.r = self.b = -1

    def add(self, x, y):
        self.n += 1
        if x < self.l: self.l = x
        if x > self.r: self.r = x
        if y < self.t: self.t = y
        if y > self.b: self.b = y

    @property
    def text(self):
        return "none" if self.n == 0 else "%d,%d-%d,%d" % (self.l, self.t, self.r, self.b)


def diffbox(da, db, x0, y0, x1, y1):
    """Where B differs from A inside a rect, and whether that patch is a BOX.

    A tooltip is a solid fill of one palette index (0x00459030 / 0x00481510
    both `rep stos` the box with the byte at 0x006CEB2F, then draw a 1-px
    border from 0x006CEB30 and the text on top), so the diff's bounding box
    is dominated by ONE index in B. Sprite animation is not: it is many
    indices with no dominant one. mode_frac is what separates the two.
    """
    box = BBox()
    for x, y in changed_pixels(da, db, x0, y0, x1, y1):
        box.add(x, y)
    r = {"diffbox_region": "%d,%d-%d,%d" % (x0, y0, x1, y1), "diffbox_px": box.n,
         "diffbox": box.text, "diffbox_w": 0, "diffbox_h": 0, "diffbox_mode_idx": -1,
         "diffbox_mode_frac": 0, "diffbox_border_frac": 0}
    if box.n == 0:
        return r
    pb, wb = db["px"], db["w"]
    l, t, rr, b = box.l, box.t, box.r, box.b
    w, h = rr - l + 1, b - t + 1
    hist = Counter()
    for y in range(t, b + 1):
        row = y * wb
        hist.update(pb[row + l:row + rr + 1])
    idx, cnt = hist.most_common(1)[0]
    # The 1-px frame: how much of the bbox's perimeter in B is one single index.
    edge = Counter()
    for x in range(l, rr + 1):
        edge[pb[t * wb + x]] += 1
        edge[pb[b * wb + x]] += 1
    for y in range(t + 1, b):
        edge[pb[y * wb + l]] += 1
        edge[pb[y * wb + rr]] += 1
    eidx, ecnt = edge.most_common(1)[0]
    r.update({"diffbox_w": w, "diffbox_h": h, "diffbox_fill_frac": "%.4f" % (box.n / float(w * h)),
              "diffbox_mode_idx": idx, "diffbox_mode_frac": "%.4f" % (cnt / float(w * h)),
              "diffbox_border_idx": eidx,
              "diffbox_border_frac": "%.4f" % (ecnt / float(sum(edge.values())))})
    return r


def print_kv(r):
    for k, v in r.items():
        print("%s=%s" % (k, v))


def cmd_diffbox(a):
    da, db = load_dump(a.a), load_dump(a.b)
    print_kv(diffbox(da, db, *clip_window(a, da, db)))
    return 0


def read_marks(path):
    """One `x1,y1,x2,y2` rect per line (inclusive screen px); blank and # lines skipped."""
    marks = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            marks.append(tuple(int(v) for v in line.split(",")))
    return marks


def unmarked_diff(da, db, marks, pad, x0, y0, x1, y1):
    """Changed pixels split by whether a (padded) mark rect covers them.

    The oracle for the partial-redraw sprite flip: the engine repaints every
    sprite that touches a dirty cell over its WHOLE rect (0x00497CE0 draws the
    clipped rect after 0x00497000 finds one set cell), so a lower-order sprite
    lands on top of a higher one in cells nothing marked. In a correct frame
    every changed pixel lies inside a mark; a change outside every mark is the
    flip, and its bbox says where.
    """
    w = db["w"]
    covered = bytearray(len(db["px"]))
    for mx1, my1, mx2, my2 in marks:
        l, t = max(x0, mx1 - pad), max(y0, my1 - pad)
        r, b = min(x1 - 1, mx2 + pad), min(y1 - 1, my2 + pad)
        for y in range(t, b + 1):
            covered[y * w + l:y * w + r + 1] = b"\x01" * (r - l + 1)
    marked, box = 0, BBox()
    for x, y in changed_pixels(da, db, x0, y0, x1, y1):
        if covered[y * w + x]:
            marked += 1
        else:
            box.add(x, y)
    return {"unmarked_region": "%d,%d-%d,%d" % (x0, y0, x1, y1), "marks_n": len(marks),
            "pad": pad, "changed_total": marked + box.n, "marked_changed": marked,
            "unmarked_changed": box.n, "unmarked_bbox": box.text}


def cmd_unmarked_diff(a):
    da, db = load_dump(a.a), load_dump(a.b)
    print_kv(unmarked_diff(da, db, read_marks(a.marks), a.pad, *clip_window(a, da, db)))
    return 0


def cmd_selftest(a):
    """Synthetic 64x64 frames: a box (fill 3, border 5) at (10,20)-(29,29) and a
    stray pixel at (60,60) that the window excludes. Each detector must find the
    box, and unmarked-diff must attribute the stray to 'unmarked' exactly when
    no mark covers it."""
    base = {"w": 64, "h": 64, "px": bytes([7] * 4096)}
    hov = bytearray(base["px"])
    for y in range(20, 30):
        for x in range(10, 30):
            hov[y * 64 + x] = 5 if (y in (20, 29) or x in (10, 29)) else 3
    hov[60 * 64 + 60] = 9
    hov = {"w": 64, "h": 64, "px": bytes(hov)}
    r = diffbox(base, hov, 0, 0, 40, 40)
    checks = [
        ("diffbox bbox", r["diffbox"] == "10,20-29,29"),
        ("diffbox mode idx", r["diffbox_mode_idx"] == 3),
        ("diffbox border idx", r["diffbox_border_idx"] == 5),
        ("diffbox border frac", r["diffbox_border_frac"] == "1.0000"),
        ("diffbox none", diffbox(base, base, 0, 0, 64, 64)["diffbox"] == "none"),
    ]
    u = unmarked_diff(base, hov, [(12, 22, 27, 27)], 2, 0, 0, 64, 64)
    # The box is 200 px; the mark alone covers its inner 16x6 = 96, with pad 2 all of it.
    checks += [
        ("unmarked-diff pad reaches the border", u["marked_changed"] == 200),
        ("unmarked-diff stray is unmarked", u["unmarked_changed"] == 1 and u["unmarked_bbox"] == "60,60-60,60"),
        ("unmarked-diff total", u["changed_total"] == 201),
        ("unmarked-diff no pad leaves the rim", unmarked_diff(base, hov, [(12, 22, 27, 27)], 0, 0, 0, 64, 64)["unmarked_changed"] == 200 - 96 + 1),
        ("unmarked-diff identical frames", unmarked_diff(base, base, [], 0, 0, 0, 64, 64)["changed_total"] == 0),
    ]
    bad = [name for name, ok in checks if not ok]
    print("selftest_checks=%d" % len(checks))
    print("selftest_failed=%s" % (",".join(bad) if bad else "none"))
    return 1 if bad else 0


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("info")
    p.add_argument("--dump", required=True)

    p = sub.add_parser("check")
    p.add_argument("--dump", required=True)
    p.add_argument("--before", required=True)
    p.add_argument("--after", required=True)
    # Only map over this many columns of the dump -- for a wide dump against a
    # 640-wide presentation, the columns the window can vouch for.
    p.add_argument("--map-w", type=int, default=0)
    # Region top-left / bottom (dump coordinates). The alignment search always
    # runs over the full window-vouched area, so a region cannot hide a misalignment.
    p.add_argument("--x0", type=int, default=0)
    p.add_argument("--y0", type=int, default=0)
    p.add_argument("--y1", type=int, default=0)
    p.add_argument("--render", default=None)
    p.add_argument("--save-palette", default=None)
    p.add_argument("--search-dy", type=int, default=48)
    p.add_argument("--search-dx", type=int, default=8)
    # Pin the alignment instead of searching; both are required together.
    p.add_argument("--align-dx", type=int, default=None)
    p.add_argument("--align-dy", type=int, default=None)

    p = sub.add_parser("render")
    p.add_argument("--dump", required=True)
    p.add_argument("--palette", required=True)
    p.add_argument("--out", required=True)

    p = sub.add_parser("band")
    p.add_argument("--dump", required=True)
    p.add_argument("--x0", type=int, required=True)
    p.add_argument("--x1", type=int, default=0)
    p.add_argument("--y0", type=int, default=0)
    p.add_argument("--y1", type=int, default=0)

    p = sub.add_parser("diff")
    p.add_argument("--a", required=True)
    p.add_argument("--b", required=True)
    p.add_argument("--x0", type=int, default=0)
    p.add_argument("--x1", type=int, default=0)
    p.add_argument("--y0", type=int, default=0)
    p.add_argument("--y1", type=int, default=0)

    p = sub.add_parser("mapdiff")
    p.add_argument("--a", required=True)
    p.add_argument("--b", required=True)
    for k in ("ax", "ay", "bx", "by"):
        p.add_argument("--" + k, type=int, required=True)
    p.add_argument("--x0", type=int, default=0)
    p.add_argument("--x1", type=int, default=0)
    p.add_argument("--y0", type=int, default=0)
    p.add_argument("--y1", type=int, default=0)

    p = sub.add_parser("diffbox")
    p.add_argument("--a", required=True)
    p.add_argument("--b", required=True)
    p.add_argument("--x0", type=int, default=0)
    p.add_argument("--x1", type=int, default=0)
    p.add_argument("--y0", type=int, default=0)
    p.add_argument("--y1", type=int, default=0)

    p = sub.add_parser("unmarked-diff")
    p.add_argument("--a", required=True)
    p.add_argument("--b", required=True)
    p.add_argument("--marks", required=True)
    p.add_argument("--pad", type=int, default=0)
    p.add_argument("--x0", type=int, default=0)
    p.add_argument("--x1", type=int, default=0)
    p.add_argument("--y0", type=int, default=0)
    p.add_argument("--y1", type=int, default=0)

    sub.add_parser("selftest")

    p = sub.add_parser("zeroruns")
    p.add_argument("--dump", required=True)
    p.add_argument("--x0", type=int, default=0)
    p.add_argument("--x1", type=int, default=0)
    p.add_argument("--y0", type=int, default=0)
    p.add_argument("--y1", type=int, default=0)

    a = ap.parse_args()
    return {"info": cmd_info, "check": cmd_check, "render": cmd_render,
            "band": cmd_band, "diff": cmd_diff, "zeroruns": cmd_zeroruns,
            "mapdiff": cmd_mapdiff, "diffbox": cmd_diffbox,
            "unmarked-diff": cmd_unmarked_diff, "selftest": cmd_selftest}[a.cmd](a)


if __name__ == "__main__":
    sys.exit(main())
