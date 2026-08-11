#!/usr/bin/env python3
"""Compare two game frames INSIDE the playfield and report structure, not a hash.

Task 034. This exists because of a specific failure: the first widescreen frame
was measured with three samplers -- the HUD band, the top strip, and the
rightmost non-black column -- all three of which sit OUTSIDE the playfield. They
agreed to 98.9%, and the playfield between them was shredded. Every number was
true and the conclusion drawn from them was false.

So this samples the playfield INTERIOR and reports:

  black       fraction of pure-black pixels in the region, per frame. Terrain has
              some black; a region that never got drawn has a lot more.
  rowmatch    per row, the fraction of sampled pixels equal to the other frame's
              same row. Reported as a median and as the count of BAD rows, because
              banding is a per-row phenomenon and an average hides it.
  badrows     the row indices themselves, so a caller can see the period. Bands
              every N rows name a block-granular cause; a single contiguous run
              names a clipping one.

It is a DIAGNOSTIC and a test oracle, never a proof of appearance -- the thing it
cannot tell you is whether a frame that matches the control looks good, only that
it looks like the control. It prints numbers and row indices; it reproduces no
game content (AGENTS.md hard rule 1), and the PNGs it reads live on the
gitignored diagnostic path.

Usage:
  python frame-diff.py CONTROL.png WIDESCREEN.png [--y0 20] [--y1 400]
                       [--x0 0] [--x1 640]
Output: `key=value` lines, one per metric, for a caller to parse.
"""
import argparse
import sys

try:
    from PIL import Image
except ImportError:
    sys.exit("frame-diff: Pillow is required (pip install pillow)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("control")
    ap.add_argument("other")
    # Defaults are the playfield interior: below the top resource strip, above
    # the console, and only as wide as the narrower of the two frames.
    ap.add_argument("--y0", type=int, default=20)
    ap.add_argument("--y1", type=int, default=400)
    ap.add_argument("--x0", type=int, default=0)
    ap.add_argument("--x1", type=int, default=640)
    ap.add_argument("--step", type=int, default=2)
    a = ap.parse_args()

    ca = Image.open(a.control).convert("RGB")
    cb = Image.open(a.other).convert("RGB")
    pa, pb = ca.load(), cb.load()

    x1 = min(a.x1, ca.size[0], cb.size[0])
    y1 = min(a.y1, ca.size[1], cb.size[1])
    x0, y0, step = a.x0, a.y0, a.step

    print("control_size=%dx%d" % ca.size)
    print("other_size=%dx%d" % cb.size)
    print("region=%d,%d-%d,%d" % (x0, y0, x1, y1))

    black = (0, 0, 0)
    tot = ablack = bblack = 0
    rowmatches = []
    badrows = []
    for y in range(y0, y1, step):
        n = same = ab = bb = 0
        for x in range(x0, x1, step):
            n += 1
            u, v = pa[x, y], pb[x, y]
            if u == v:
                same += 1
            if u == black:
                ab += 1
            if v == black:
                bb += 1
        tot += n
        ablack += ab
        bblack += bb
        m = same / n if n else 1.0
        rowmatches.append(m)
        if m < 0.90:
            badrows.append(y)

    rowmatches.sort()
    median = rowmatches[len(rowmatches) // 2] if rowmatches else 1.0
    print("control_black=%.4f" % (ablack / tot if tot else 0))
    print("other_black=%.4f" % (bblack / tot if tot else 0))
    print("black_delta=%.4f" % ((bblack - ablack) / tot if tot else 0))
    print("rowmatch_median=%.4f" % median)
    print("rowmatch_min=%.4f" % (rowmatches[0] if rowmatches else 1.0))
    print("rows_sampled=%d" % len(rowmatches))
    print("bad_rows=%d" % len(badrows))
    print("bad_row_ys=%s" % ",".join(str(y) for y in badrows[:60]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
