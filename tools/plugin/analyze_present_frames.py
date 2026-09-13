"""Task 065: structural analysis of probe-widescreen-present.ps1 captures.

The probe's cross-arm band-match threshold (95%) carries menu-animation noise
inside it, so its CROP/SCALE verdict string can read "SCALE (or something
else)" on a pair that is geometrically identical. This tool applies the
discriminators that do NOT depend on that line:

1. shape: per-column differing fraction between two same-size captures. A 0.8x
   rescale moves every pixel, damaging EVERY column; animation damages isolated
   blobs (AGENTS.md: assert the thing that distinguishes damage from noise).
2. band: how black the widescreen right band (x>=640) is, excluding the
   caption-compositing artifact (see below) and counting "visually black"
   (channel sum <= 12) rather than literal (0,0,0), because GDI palette
   mapping renders index 0 as e.g. (0,4,0) for some pixels.
3. align: the row band of bright-green menu text per capture. Vertical scale
   or shift moves it; 1:1 presentation keeps it at the same rows in every arm.
4. caption: rows whose majority is caption-cream (all channels > 200).
   Measured 2026-08-13: cnc-ddraw window captures carry a caption-colored
   strip in rows 0..30 in BOTH arms (ws0 and ws1) -- a capture artifact of the
   standard-frame window, not a widescreen effect; WMode skins its own caption
   so its captures never show it. Any band arithmetic must exclude those rows.

Usage:
    python tools/plugin/analyze_present_frames.py [frame_dir]

Reads present-<arm>-menu.png (and -menu2.png brackets if present) from
frame_dir (default C:\\decompile-sc-data\\sc-work\\logs\\065-frames) and prints readings; it
asserts nothing itself -- the numbers go into research/renderer-viewport.md
with the run they came from.
"""
import sys
from pathlib import Path

from PIL import Image

BLACK_SUM = 12          # channel sum at or below this is "visually black"
CAPTION_MIN = 200       # all channels above this is caption-cream
SCALE_COL_FRAC = 0.5    # a column with more rows differing than this is "damaged"


def load(path):
    return Image.open(path).convert("RGB")


def per_column_shape(a, b):
    w, h = min(a.width, b.width), min(a.height, b.height)
    pa, pb = a.load(), b.load()
    col = [0] * w
    pts = []
    for y in range(h):
        for x in range(w):
            if pa[x, y] != pb[x, y]:
                col[x] += 1
                pts.append((x, y))
    frac = [c / h for c in col]
    cells = {(x // 16, y // 16) for x, y in pts}
    seen = set()
    blobs = 0
    for c in cells:
        if c in seen:
            continue
        blobs += 1
        stack = [c]
        while stack:
            cx, cy = stack.pop()
            if (cx, cy) in seen:
                continue
            seen.add((cx, cy))
            stack.extend(
                (cx + dx, cy + dy)
                for dx in (-1, 0, 1)
                for dy in (-1, 0, 1)
                if (cx + dx, cy + dy) in cells
            )
    return {
        "size": (w, h),
        "diff_px": len(pts),
        "diff_pct": 100 * len(pts) / (w * h),
        "damaged_cols": sum(1 for f in frac if f > SCALE_COL_FRAC),
        "max_col_frac": max(frac) if frac else 0.0,
        "clusters": blobs,
    }


def band_blackness(im, x0=640, y0=31):
    p = im.load()
    total = bad = 0
    for y in range(y0, im.height):
        for x in range(x0, im.width):
            total += 1
            if sum(p[x, y]) > BLACK_SUM:
                bad += 1
    return {"px": total, "non_black": bad,
            "black_pct": 100 * (total - bad) / total if total else 0.0}


def green_text_rows(im):
    p = im.load()
    rows = []
    for y in range(im.height):
        n = sum(
            1
            for x in range(0, min(640, im.width), 2)
            if p[x, y][1] > 180 and p[x, y][0] < 180 and p[x, y][2] < 160
            and p[x, y][1] - p[x, y][0] > 60
        )
        if n > 8:
            rows.append(y)
    return rows


def caption_rows(im):
    p = im.load()
    out = []
    for y in range(im.height):
        n = sum(1 for x in range(0, im.width, 2)
                if all(c > CAPTION_MIN for c in p[x, y]))
        if n > im.width / 2 * 0.3:
            out.append(y)
    return out


def main():
    d = Path(sys.argv[1] if len(sys.argv) > 1 else r"C:\decompile-sc-data\sc-work\logs\065-frames")
    frames = {f.stem.removeprefix("present-").removesuffix("-menu"): f
              for f in sorted(d.glob("present-*-menu.png"))}
    brackets = {f.stem.removeprefix("present-").removesuffix("-menu2"): f
                for f in sorted(d.glob("present-*-menu2.png"))}

    for name, path in frames.items():
        im = load(path)
        g = green_text_rows(im)
        c = caption_rows(im)
        line = (f"{name}: {im.width}x{im.height}  green-text rows "
                f"{g[0] if g else '-'}..{g[-1] if g else '-'}  caption rows "
                f"{c[0] if c else '-'}..{c[-1] if c else '-'} ({len(c)})")
        if im.width > 640:
            b = band_blackness(im)
            line += (f"  band(x>=640,y>=31) black {b['black_pct']:.2f}% "
                     f"({b['non_black']}/{b['px']} non-black)")
        print(line)

    for pair in (("inject-ws1", "inject-ws0"), ("ddraw-ws1", "ddraw-ws0")):
        if pair[0] in frames and pair[1] in frames:
            s = per_column_shape(load(frames[pair[0]]), load(frames[pair[1]]))
            print(f"\ncross-arm {pair[0]} vs {pair[1]} over {s['size'][0]}x{s['size'][1]}: "
                  f"{s['diff_px']} px differ ({s['diff_pct']:.1f}%), "
                  f"damaged columns {s['damaged_cols']} (rescale predicts ~all), "
                  f"max col fraction {s['max_col_frac']:.2f}, clusters {s['clusters']}")

    for name, path2 in brackets.items():
        if name in frames:
            s = per_column_shape(load(frames[name]), load(path2))
            print(f"same-arm {name} bracket: {s['diff_px']} px differ "
                  f"({s['diff_pct']:.1f}%), damaged columns {s['damaged_cols']}, "
                  f"clusters {s['clusters']}")
            im2 = load(path2)
            if im2.width > 640:
                b = band_blackness(im2)
                print(f"  bracket band(x>=640,y>=31) black {b['black_pct']:.2f}%")


if __name__ == "__main__":
    main()
