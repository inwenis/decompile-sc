# The renderer and the viewport (StarCraft.exe 1.16.1)

Task 032. The question behind this document is a feature request: **"see more of the map at
once — a bigger playfield, like Remastered, while the HUD stays stock."** Everything below
exists to price that honestly, and the price is at the bottom (§9).

Nobody on this project had looked at the renderer before. It is also the one subsystem the
public prior art skips — BWAPI, GPTP and OpenBW all reimplement or map the *simulation* and
explicitly leave rendering alone (`research/prior-art.md` §1.2, §9). So nothing here is
inherited. Every address was derived from this binary.

## 1. How the renderer was found at all

`StarCraft.exe` carries its own source-file names. The VC6-era assert/allocator macros pass
`__FILE__`, and the strings survive in `.rdata`:

```
0x00505F50  Starcraft\SWAR\lang\gds\vidblit.cpp
0x00505E88  Starcraft\SWAR\lang\gds\vidinimo.cpp
0x00505F1C  Starcraft\SWAR\lang\gds\vidinimo_PC.cpp
0x00505E64  Starcraft\SWAR\lang\gds\image.cpp
0x00502BFC  Starcraft\SWAR\lang\Gamemap.cpp
0x005040B8  Starcraft\SWAR\lang\minimap.cpp
0x00504534  Starcraft\SWAR\lang\mask.cpp
0x005056D0  Starcraft\SWAR\lang\los.cpp
0x005045D8  Starcraft\SWAR\lang\scroll.cpp
0x00502B98  Starcraft\SWAR\lang\light.cpp
```

- **How found**: `work/scratch/032/scan-strings.py` — an ASCII scan of the file image with
  file offsets converted to VAs through the PE section table parsed from the same file
  (`ImageBase 0x00400000`, four sections, `research/pe-anatomy.md`). 110 module strings in
  total; `work/scratch/032/make-module-spec.py` turns them into an XrefSweep spec.
- **How verified**: the sweep (`work/scratch/032/module-xrefs.tsv`, 731 references) puts
  every referencing function in a contiguous address band per module, and each band's
  functions do what the module name says. `statcmd.cpp` and `statdata.cpp` land on
  0x00459B90 and 0x00458570 — the two functions `research/command-card.md` and
  `research/hud-selection-row.md` already identified by completely different means. That
  agreement is the calibration for the technique.

This is the same trick task 026 used for the command card, generalised to the whole binary.
The full module→function table is `research/data/renderer-modules.tsv`.

## 2. The one screen buffer

**There is exactly one framebuffer, and it is a plain 8-bit linear heap allocation.**

```c
// FUN_004DB060, gds\vidinimo.cpp -- the video init
DAT_006ceff0 = 0x280;                                     // width  = 640
DAT_006ceff2 = 0x1e0;                                     // height = 480
DAT_006ceff4 = 0;
DAT_006ceff4 = SMemAlloc(0x4b000, "...\\gds\\vidinimo.cpp", 0x37, 0);   // 640*480 bytes
FUN_0041d930();                                           // the DirectDraw half, §3
```

So `0x006CEFF0` is a three-field descriptor this project now calls the **screen Bitmap**:

| offset | type  | meaning |
| ------ | ----- | ------- |
| +0x00  | u16   | width  (640) |
| +0x02  | u16   | height (480) |
| +0x04  | u8*   | pixel data, `width * height` bytes, pitch == width |

- **How found**: the program-wide immediate sweep (`ProgramImmediateSweep.java`, new in this
  task) over 640/480/400/639/479/399/307200 — `0x004DB077 PUSH 0x4b000` sits two instructions
  before `0x004DB07C MOV word ptr [0x006ceff0],0x280`.
- **How verified**: a second, independent writer sets the same three fields —
  `FUN_0041E050` (`gds\image.cpp`) at 0x0041E07B/0x0041E084 — and the frame composer
  **reads** them rather than re-deriving them when it clears the screen:
  `for (n = (h * w) >> 2; ...) *p++ = 0;` at 0x0041E280. Two writers and a reader agreeing
  on the same three fields is what makes the layout a fact rather than a reading.

Everything — terrain, sprites, fog, the console, dialogs, the cursor — is composed into this
single buffer. There is no separate playfield surface. **That is the central structural fact
of this document.**

## 3. DirectDraw, and what WMode.dll does and does not change

`FUN_0041D930` (`gds\vidinimo_PC.cpp`) is the entire display setup. Decompiled, with the
DirectDraw vtable slots resolved from the standard `IDirectDraw` / `IDirectDrawSurface`
layouts:

```c
ShowWindow(hwnd, SW_SHOWNORMAL);
hModule = LoadLibraryA("ddraw.dll");                       // 0x0041D949
pFn     = GetProcAddress(hModule, "DirectDrawCreate");
pFn(driver, &lpDD, 0);
lpDD->SetCooperativeLevel(hwnd, 0x13);                     // +0x50; EXCLUSIVE|FULLSCREEN|ALLOWMODEX
lpDD->SetDisplayMode(0x280, 0x1e0, 8);                     // +0x54; 0x0041DA3D / 0x0041DA42
  // on failure: SetDisplayMode(GetSystemMetrics(0), GetSystemMetrics(1), 8)
lpDD->CreatePalette(0x44, entries, &lpPal, 0);             // +0x14
lpDD->CreateSurface(&ddsd /*caps only, PRIMARYSURFACE*/, &lpPrimary, 0);   // +0x18
lpPrimary->SetPalette(lpPal);                              // +0x7C
if (lpPrimary->Lock(0, &ddsd, 1, 0) != DD_OK) {            // +0x64
    // fall back to an offscreen system-memory surface, dwHeight/dwWidth written as
    // 0x0041DBA3 = 0x1e0 and 0x0041DB9C = 0x280
    lpDD->CreateSurface(&ddsd /*OFFSCREENPLAIN|SYSTEMMEMORY, 640x480*/, &lpSecondary, 0);
} else lpPrimary->Unlock(...);                             // +0x80
Ordinal_351(hwnd, lpDD, lpPrimary, 0, 0, lpSecondary, lpPal, 0);   // storm SDraw takes over
```

The frame is presented by **one blit of the whole buffer**, `FUN_0041D420`:

```c
if (Ordinal_350(0, 0, &dst, &dstPitch, 0)) {               // lock the surface
    Ordinal_432(dst, DAT_006ceff4, dstPitch, 0x280, DAT_006d5e18);
    //               ^ screen.data              ^ SOURCE PITCH, a hardcoded immediate at 0x0041D450
    Ordinal_356(0, dst, 0, 0);                             // unlock
}
```

**What this means for `WMode.dll`.** `research/launch-baseline.md` established by measurement
that dropping `WMode.dll` in as `ddraw.dll` stops the desktop resolution switching (native
3840x2160 throughout, versus a measured switch to 640x480 in the stock arm) and gives a
borderless window covering the desktop. This section says *where* that happens: WMode is the
`ddraw.dll` this function loads by name, and it intercepts `SetDisplayMode(640,480,8)` and the
surface it hands back.

So, precisely:

- **WMode is a lever for PRESENTATION only.** It changes how the finished 640x480 image
  reaches the monitor.
- **WMode changes nothing about what the engine renders.** The engine still composes 640x480
  into `0x006CEFF0`, and WMode scales that up. That upscale is exactly the outcome the user
  looked at and rejected.
- **It is not a constraint on going wider.** The display-mode call is parameterised and the
  Storm layer below it is initialised with explicit surfaces, so a different mode would pass
  through. The obstacle is entirely on the engine side of the blit, §5 onward.

Caveat, stated because it matters: `WMode.dll` and `WMode_Fix.dll` are packed
(`research/launch-baseline.md`: no export table, KERNEL32-only imports, high section entropy),
so **how WMode behaves at a different resolution is not established here** and would have to
be measured, not assumed. See §10.

## 4. The eight graphic layers — this is the playfield/HUD seam

`0x006CEF50` holds an array of eight 20-byte layer records:

| offset | type | meaning |
| ------ | ---- | ------- |
| +0x00 | u8   | in use |
| +0x01 | u8   | flags; bit 0 = needs redraw |
| +0x02 | s16  | left |
| +0x04 | s16  | top |
| +0x06 | s16  | width |
| +0x08 | s16  | height |
| +0x0C | void*| `param`, the draw callback's first argument |
| +0x10 | fn   | `void draw(void* param, s16 clip[5])` |

- **How found**: `FUN_0041E050` (`gds\image.cpp`) zeroes exactly `0x28` dwords = 160 bytes =
  8 × 20 starting at 0x006CEF50, and the next thing it writes is the screen Bitmap at
  0x006CEFF0 — i.e. the block ends exactly where §2's descriptor begins.
- **How verified**: the stride is in the instructions, twice. `FUN_004BD630` indexes the
  block as `(&DAT_006CEF51)[i * 0x14]` (bytes) and `(&DAT_006CEF56)[i * 10]` (u16). The frame
  composer walks it with `psVar7 -= 10` shorts. And three independent initialisers
  (0x0041A030, 0x00481330, 0x004BD630) write the same six fields at the same six offsets of
  three different records.

**Who owns which layer** — read off the writer of each record's +0x10 slot
(`work/scratch/032/surface-xrefs.tsv`):

| layer | draw fn | installed by | rect | what it is |
| ----- | ------- | ------------ | ---- | ---------- |
| 0 | 0x004BDFA0 | 0x004D1560 (`cur.cpp`) | — | the mouse cursor |
| 1 | 0x004810F0 | 0x00481330 (`mask.cpp` band) | full screen | screen mask / fade |
| 2 | 0x0041CB50 | 0x0041A030 | (0,0) 640x480 | **dialogs** — it walks `0x006D5E34`, the dialog list `sc_addresses.h` already names |
| 3 | 0x0048D5C0 | 0x0048D700 | — | build-placement preview |
| 4 | 0x0048D5C0 | 0x0048D700 | — | second placement slot |
| 5 | 0x004BD580 | 0x004BD630 | **(0,0) 640x400** | **the playfield** |
| 6 | none | — | — | unused; nothing in the binary writes its draw slot |
| 7 | none | — | — | unused |

**All of that is confirmed in a running game** — `research/data/renderer-viewport-live.md`.
Layer 5 reads `(0,0) 640x400 draw=0x004BD580` in game and `used=0` at the main menu; layer 0
is a 20x21 rectangle that moves to wherever the driver last clicked; layers 3 and 4 carry
exactly the params 0x0064095C and 0x00640964 their installer writes; layers 6 and 7 are
`used=0 draw=0` in both arms.

The frame composer `FUN_0041E280` walks **7 → 0**, so layer 7 is the bottom and layer 0 is
drawn last, on top. For each used layer it builds a six-short descriptor on the stack — a clip
rectangle plus the surface extent — and calls the callback. From the listing
(`work/scratch/032/compose-listing.tsv`), with the stack slots named by what they receive:

```
0041e2f2  MOV  EDI,0x1e0                    ; 480, held for the whole loop
0041e30b  MOV  CX,word ptr [ESI + -0x2]     ; layer->left
0041e30f  MOV  DX,word ptr [ESI]            ; layer->top
0041e312  NEG  CX
0041e315  NEG  DX
0041e318  MOV  word ptr [EBP + -0x10],CX    ; x1 = -left
0041e31c  MOV  word ptr [EBP + -0xe],DX     ; y1 = -top
0041e323  ADD  EAX,0x27f                    ; 639
0041e328  MOV  word ptr [EBP + -0xc],AX     ; x2 = -left + 639
0041e32f  ADD  ECX,0x1df                    ; 479
0041e348  MOV  word ptr [EBP + -0xa],CX     ; y2 = -top + 479
0041e33e  MOV  word ptr [EBP + -0x8],0x280  ; width  = 640
0041e344  MOV  word ptr [EBP + -0x6],DI     ; height = 480
0041e3a0  CALL dword ptr [ESI + 0xc]        ; layer->draw(layer->param, &descriptor)
```

(The `0x0041E2D5` / `0x0041E2DC` pair that also carries 640 and 480 is in the **other** branch
of this function — the whole-screen clear at `DAT_0051A0E9 != 0`, which builds a full-screen
rectangle and calls 0x0041D3A0.)

**So the seam is real and it is exactly one number.** The playfield is layer 5, a 640x400
rectangle at the top-left of a 640x480 screen; the HUD is not a layer at all — the console
art is drawn inside layer 5's own chain and the status/command dialogs come through layer 2's
walk of the dialog list, at the absolute coordinates `research/hud-selection-row.md` and
`research/command-card.md` already record. The HUD sits **over** the bottom of the playfield,
not beside it.

That last point is worth stating plainly because it kills the cheapest idea anyone would
have: **growing the playfield down into the console strip gains nothing**, because the
console art is opaque and covers it. To see more map, the screen itself has to get bigger.

## 5. The dirty-block grid — the hard structural obstacle

`0x006CEFF8` is a `u8[30][40]`: one byte per **16x16 pixel block** of a 640x480 screen.

```c
// FUN_0041E0D0 -- mark a rectangle dirty. EAX=x1, ECX=y1, EDX=y2, stack=x2.
if (x1 < 0) x1 = 0; else if (x1 > 0x27f) return;        // 0x0041E0F5 / 0x0041E0FD
if (x2 > 0x27f) x2 = 0x27f;
if (y1 < 0) y1 = 0; else if (y1 > 0x1df) return;        // 0x0041E11A / 0x0041E122
if (y2 > 0x1df) y2 = 0x1df;
col = x1 >> 4;  row = y1 >> 4;
n   = (x2 >> 4) - col + 1;
p   = &DAT_006ceff8 + row * 0x28 + col;                 // stride 0x28 == 40 columns
for (r = row; r <= (y2 >> 4); ++r) { memset(p, 1, n); p += 0x28; }
```

Corroboration, three ways:

1. Three separate functions clear it as **300 dwords** = 1200 bytes = 40 × 30 — the drawing
   gate 0x0041D710, the console init 0x004BD630, and the composer 0x0041E280.
2. The presentation layer is told the identical geometry explicitly: `FUN_0041D470` calls
   `Ordinal_440(0x280, 0x1e0, 0x10, 0x10)` — 640, 480, 16, 16.
3. Two consumers walk it with the geometry open-coded rather than read: the terrain blitter
   `FUN_004BCDC0` (`while (col < 0x28)`, `while (y < 400)`) and the fog draw `FUN_004808E0`
   (`while (x < 0x280)`, `while (y < 400)`).

**It cannot grow in place.** `0x006CEFF8 + 0x4B0 == 0x006CF4A8`, and 0x006CF4A8 is a live
global — the current render-target `Bitmap*`, written by 0x0041E280 and 0x0041DF40 and read
by 0x0041D260, 0x0041DEB0 and 0x0045EA30. The array is boxed in by the linker's data layout.

**62 instructions across 13 functions** reference the grid
(`work/scratch/032/dirtygrid-xrefs.tsv`): 0x0048CB80 (13), 0x004BCDC0 (11), 0x004808F8 (8),
0x0047EBF0 (5), 0x0041E0D0 (5), 0x004B1FA0 (4), 0x0041E280 (4), 0x004BD630 (3), 0x0041E050
(3), 0x0041D710 (3), and one each in 0x00497000, 0x0042D280, 0x0041DE20.

## 6. The terrain scratch surface

`FUN_004BCDC0` is the tile blitter. It walks the dirty grid and copies runs of dirty blocks
out of a pre-composed terrain surface:

```c
off = (screenTop * 0x2a0 + screenLeft) % 0x49800;      // pitch 672, size 301056
p   = &DAT_006ceff8;                                    // the dirty grid
do {                                                    // rows
  col = 0;
  do {                                                  // 40 columns
    if (*p == 1) { run = 1; while (++col < 0x28 && *++p) ++run; FUN_0040C2BD(run*0x10, off); ... }
    off += 0x10; ++col; ++p;
  } while (col < 0x28);
  off += 0x2790;                                        // 672 * 16 - 640 + 16 -> next 16 scanlines
  y += 0x10;
} while (y < 400);
```

`0x49800 = 301056 = 672 × 448`, addressed modulo its own size so scrolling wraps instead of
copying. **672 = 640 + 32 and 448 = 400 + 48** — the playfield plus one tile of margin. Both
the pitch (`0x2A0`) and the wrap size (`0x49800`) are immediates in this function.

## 7. The viewport in map coordinates

`0x0062848C` / `0x006284A8` (`SC_VA_SCREEN_LEFT` / `SC_VA_SCREEN_TOP`, already in
`sc_addresses.h` from `research/selection-circles.md`) are the viewport origin in map pixels.
Their clamp is established once, in `FUN_0049BB90`:

```c
DAT_006284a4 = mapTileW << 5;                      // map width  in pixels
DAT_006284a6 = mapTileH << 5;                      // map height in pixels
DAT_00628488 = (mapTileW - 0x14) * 0x20;           // MAX screenLeft; 0x14 = 20 tiles = 640 px
DAT_006284b0 = (mapTileH - 0x0C) * 0x20 + 8;       // MAX screenTop;  0x0C = 12 tiles = 384 px
DAT_0062848c = screenTileX << 5;
DAT_006284a8 = screenTileY << 5;
```

**Measured in a running game** on a 128x96-tile map: `scrollMax=(3456,2696)`, and
`(128-20)*32 = 3456`, `(96-12)*32+8 = 2696` — the probe computes the prediction from the map's
own dimensions and reports `match=1` (`research/data/renderer-viewport-live.md`).

The clamp is enforced by the two steppers, `FUN_0049C0C0` (x) and `FUN_0049C280` (y), each of which
clamps against exactly one of those maxima and then republishes the tile-granular origin
`0x0057F1D0` / `0x0057F1D2`. **The viewport's size in tiles — 20 across, 12 down — is baked
into the clamp**, and the same pair of steppers refresh a terrain row cache in strides of
`+0x15` (21 columns) and `+0x0E` (14 rows), i.e. the viewport plus margin again.

The minimap's click-to-centre `FUN_004A4D20` bakes it a third time, and disagrees by one:

```c
x = mouseX - ((0x14 << zoomShift) / (scale * 2));   // 20 tiles
y = mouseY - ((0x0d << zoomShift) / (scale * 2));   // 13 tiles
```

Mouse-to-world goes through the same origin. The click handler `FUN_0046FB40` builds its
search rectangle as `{ left, top, left + 0x280, top + 400 }` — twice, at 0x0046FC75/0x0046FC87
and 0x0046FE18/0x0046FE2A. Task 024 already read this rectangle for a different reason
(`research/building-groups.md`); this is where its 640 and 400 come from.

## 8. Every 640x400 in the draw path

The playfield's size is **not stored anywhere**. It is an immediate in every function that
clips to it. These are the ones read for this document — each is an independent copy of the
same two numbers:

| function | instructions | what it does |
| -------- | ------------ | ------------ |
| 0x004BD630 | 0x004BD633, 0x004BD638, 0x004BD675, 0x004BD67E | layer 5's rect, and `SetRect(&DAT_005993B0, 0, 0, 639, 399)` beside it |
| 0x004D57B0 | 0x004D5856, 0x004D5887 | **per-IMAGE screen clip**: `if (0x280 - x <= w) w = 0x280 - x;` and the same with 400. Every sprite on screen goes through this |
| 0x0045CC90 | 0x0045CCB1, 0x0045CCBC, 0x0045CCD6, 0x0045CCF0 | generic "clip this rect to the playfield" |
| 0x0046FB40 | 0x0046FC75, 0x0046FC87, 0x0046FE18, 0x0046FE2A | the click/drag-box search rect |
| 0x0048D660 | 0x0048D663, 0x0048D66D | build placement: refuses x ≥ 640 or y ≥ 400 |
| 0x004808E0 | 0x004808E4, 0x004808EB | fog draw's dirty-grid walk |
| 0x004BCDC0 | inline loop bounds | terrain blitter's dirty-grid walk |
| 0x0047EBF0 | 0x0047EC7B, 0x0047ECBC, 0x0047ED97, 0x0047EDB8, 0x0047EDC0 | fog of war, scrolled arm |
| 0x0047EE20 | 0x0047EEA0, 0x0047EEDD, 0x0047EEFF, 0x0047EF0B, 0x0047EF24, 0x0047EF2C | fog of war, static arm |
| 0x004808F8 | 0x0048090E, 0x0048092C, 0x00480948, 0x00480953 | fog of war clipping |
| 0x00481480 | 0x004814EA, 0x004814F3 | parks layer 1 at (640,400) to hide it |

And the 640x480 screen-size sites, same treatment:

| function | instructions | what it does |
| -------- | ------------ | ------------ |
| 0x0041D930 | 0x0041DA3D, 0x0041DA42, 0x0041DB9C, 0x0041DBA3 | `SetDisplayMode` and the fallback surface |
| 0x004DB060 | 0x004DB077, 0x004DB07C, 0x004DB085 | the buffer allocation and its descriptor |
| 0x0041E050 | 0x0041E07B, 0x0041E084 | the descriptor again |
| 0x0041D420 | 0x0041D450 | **the blit's source pitch** |
| 0x0041D470 | 0x0041D52C, 0x0041D531 | `Ordinal_440(640, 480, 16, 16)` |
| 0x0041A030 | 0x0041A049, 0x0041A052 | layer 2 (dialogs) |
| 0x0041E0D0 | 0x0041E0F5, 0x0041E0FD, 0x0041E11A, 0x0041E122 | the dirty marker's clamps |
| 0x0041E280 | 0x0041E323, 0x0041E32F, 0x0041E2D5 | the composer's per-layer clip rect |
| 0x0048CB80 | 0x0048CB97, 0x0048CB9E, 0x0048CBE8, 0x0048CBEF | 479 clamps |
| 0x004B1FA0 | 0x004B22E9, 0x004B22F0 | 479 clamp |
| 0x00481510 | 0x004815E6, 0x00481620 | 639/479 |
| 0x004D1940, 0x004D19C0, 0x004D1A50, 0x004D1D70 | 0x004D196D, 0x004D198E, 0x004D19F9, 0x004D1A1A, 0x004D1A89, 0x004D1AAA, 0x004D24EC, 0x004D250C | the window procedure's mouse clamps to (639,479) |

Raw sweep output: `work/scratch/032/res-immediates.tsv` (program-wide, 15 watched values,
every instruction in the binary). The distilled table is
`research/data/renderer-viewport-sites.tsv`.

## 9. The breakage list, and the verdict

### 9.1 What would have to change, with confidence

| # | thing | function / global | confidence | note |
| - | ----- | ----------------- | ---------- | ---- |
| 1 | display mode | 0x0041D930 @ 0x0041DA3D/0x0041DA42 | **high** | two immediates; the fallback path at 0x0041DB9C/0x0041DBA3 too |
| 2 | screen buffer size + descriptor | 0x004DB060, 0x0041E050 | **high** | one Storm alloc and two 3-field writes; genuinely easy |
| 3 | blit source pitch | 0x0041D420 @ 0x0041D450 | **high** | one immediate |
| 4 | Storm update-region geometry | 0x0041D470 @ 0x0041D52C/0x0041D531 | **high** | one call's arguments |
| 5 | **dirty-block grid** | 0x006CEFF8; 62 instructions in 13 functions | **high** | §5. Cannot grow in place — 0x006CF4A8 is live. Needs relocation + every reference re-pointed, and the stride 0x28 is open-coded in at least 0x0041E0D0, 0x004BCDC0 and 0x004808E0 |
| 6 | frame composer clip rect | 0x0041E280 @ 0x0041E323/0x0041E32F/0x0041E2D5 | **high** | 639/479 and a packed 0x01E00280 |
| 7 | dirty-marker clamps | 0x0041E0D0 | **high** | four immediates |
| 8 | **terrain scratch surface** | 0x004BCDC0, pitch 0x2A0, size 0x49800 | **high** | §6. A second fixed-size buffer with its geometry inlined, plus whatever fills it |
| 9 | per-image screen clip | 0x004D57B0 | **high** | every sprite; two immediates |
| 10 | generic playfield rect clip | 0x0045CC90 | **high** | four immediates |
| 11 | fog of war extents | 0x0047EBF0, 0x0047EE20, 0x004808F8, 0x004808E0 | **high** | ~17 immediates across four functions |
| 12 | scroll clamp | 0x0049BB90 (bounds), 0x0049C0C0 / 0x0049C280 (enforcement + the 21/14 row cache) | **high** | the 20 and 12 tile extents |
| 13 | mouse → world | 0x0046FB40 | **high** | four immediates; task 024 depends on this rectangle |
| 14 | build placement | 0x0048D660 | **high** | two immediates |
| 15 | window-procedure mouse clamp | 0x004D1940, 0x004D19C0, 0x004D1A50, 0x004D1D70 | **medium** | eight immediates; read but not traced to a visible symptom |
| 16 | layer 2 (dialogs) rect | 0x0041A030 | **high** | two immediates |
| 17 | minimap click-to-centre | 0x004A4D20 | **high** | the 20/13 tile half-extent |
| 18 | minimap **viewport rectangle** | `minimap.cpp` band 0x004A3720–0x004A5D10 | **LOW — not located** | see §10 |
| 19 | **console art** `console.pcx` | MPQ data, string at 0x00502A7C | **high** | a fixed-width image. At 800 wide there is no console art for the extra 160 px |
| 20 | **HUD dialog coordinates** | `rez\statbtn%c.bin`, `statdata`, MPQ data | **high** | absolute coordinates, already documented in `research/hud-selection-row.md` and `research/command-card.md`. A bottom-anchored stock HUD means moving them, which means patching loaded dialog geometry at runtime |

That is **~60 instruction sites plus two fixed-size buffers plus two data assets**, and items
5, 8, 19 and 20 are not "patch a constant" work at all.

### 9.2 Verdict: NO-GO on 1.16.1, at this project's price point

Stated plainly, because the task explicitly allows this answer and it is the honest one:

**A wider viewport with a stock HUD is not a runtime-patch feature on 1.16.1. It is a
renderer rewrite wearing a smaller hat, and I do not recommend building it.**

The reasons, in order of how much they matter:

1. **There is no viewport abstraction to widen.** The playfield's size exists as ~30 copies of
   the literals 640 and 400 scattered across fog, sprites, terrain, placement, input and
   clipping. Nothing reads a variable. Patching a constant that is written thirty times is
   thirty patches, each of which has to be found, sized and reloc-corrected.
2. **Two fixed-size buffers cannot grow where they are.** The dirty grid is boxed in by a live
   neighbour and reached by 62 instructions; the terrain scratch surface has its pitch and
   wrap size inlined in the blitter that reads it. Relocating either means rewriting every
   reference, and this plugin's detour engine patches *functions*, not data layouts.
3. **"Stock HUD" is the expensive half, not the cheap half.** The console is a fixed-width
   image in the MPQ and the HUD dialogs carry absolute coordinates. Widening the screen and
   keeping the HUD stock means either a 160-pixel strip of nothing at the bottom, or new art
   plus runtime relocation of every dialog — and hard rule 1 means this repo cannot ship art.
4. **Growing the playfield into the console strip gains nothing** (§4): the console is opaque
   and drawn over it. There is no free space to reclaim inside 640x480.
5. **WMode is not the lever it looked like** (§3). It changes presentation only. What it
   already does — scale 640x480 to the desktop — *is* the upscale the user rejected.

**What I would build instead, if the goal is "see more map":** nothing in the renderer. The
outcome the user wants exists on Remastered, which reached it by rebuilding this layer
(`research/prior-art.md` §6). On 1.16.1 the good-value work stays where this project has been
winning — game logic and HUD behaviour, where a hook is a hook and the data model is public.

### 9.3 If it is built anyway: the staged plan

Ordered so each stage is independently verifiable and the game still runs after each one.

| stage | scope | proves |
| ----- | ----- | ------ |
| 0 | Measure WMode at a non-640x480 mode before anything else: patch only 0x0041DA42/0x0041DA3D to 800x600 and confirm the window still comes up under the injected helper. Expect a 640x480 image in the corner of an 800x600 mode. | that the presentation half survives at all — the cheapest possible falsification, and it is where I would stop if it failed |
| 1 | Screen surface: items 2, 3, 4 + relocate the dirty grid (item 5) into plugin-owned memory and re-point all 62 references, + composer/marker clamps (6, 7). | a correctly presented 800x600 frame with a 640x400 playfield in the corner. Nothing looks better yet |
| 2 | Playfield geometry: items 8, 9, 10, 11, 14 + the terrain scratch surface. | terrain, sprites and fog fill the new area. **This is the stage that can actually look wrong**, and the one I would expect to consume most of the budget |
| 3 | Input and camera: items 12, 13, 15, 17. | clicks land where they look, the camera reaches the map edges |
| 4 | HUD: items 16, 19, 20. | a stock HUD anchored to the bottom of a wider screen |
| 5 | Minimap viewport rectangle (item 18), once located. | the minimap agrees with the camera |

A first slice that is worth showing a human does not exist before stage 2 completes, which is
why this task took none of it — stage 0 and stage 1 produce a 640x400 image sitting in the
corner of a bigger black rectangle, which is strictly worse than what the user has now.

## 10. What this task did NOT determine

Listed because leaving it out would make the map read as more complete than it is.

1. **The minimap's viewport rectangle** — the white box. `FUN_004A4D20` (click-to-centre) is
   located and read; the function that *draws* the rectangle is not. No function in the
   minimap band 0x004A3xxx–0x004A6xxx references `screenLeft`/`screenTop`, so it must derive
   from the tile-granular origin, but which function does it is unresolved. The one candidate
   the immediate sweep offered (0x004A6030, `ADD EAX,0x190`) was decompiled and is a **sound
   timer**, not the minimap — recorded here because it is exactly the kind of plausible
   false positive an unverified sweep hit would have become.
2. **How WMode behaves at a resolution other than 640x480.** Not measured. Both helper DLLs
   are packed, so this can only be answered by running one.
3. **What fills the terrain scratch surface** (§6). The blitter that reads it is decompiled;
   the producer is not, so "the scratch surface would have to be resized" names a buffer whose
   writer has not been read.
4. **Whether `storm.dll` imposes any further limit.** Every claim here stops at the exe's side
   of the Storm ordinals. The ordinal→name mapping used in §3 (350/356 lock/unlock, 351 manual
   init, 432 blit, 440 create-region) is inferred from argument shapes and from public Storm
   knowledge, **not** derived from `storm.dll` itself. The argument *values* are read out of
   this binary and are what the claims rest on; the names are a convenience.
5. **Layers 6 and 7.** No writer of their draw slots exists in the binary. Recorded as unused
   rather than proven unused — the sweep covers static references only.
6. **The 399/400 immediates in 0x00452900, 0x004696D0, 0x004BED70 and 0x00488F90.** Found by
   the sweep, not read. 0x00488F90's six `IMUL ...,0x190` were read and are AI score scaling,
   not screen geometry — a reminder that the raw sweep table is a lead list, not a finding
   list, and that only the rows in §8 have been read.

## 11. Live read-back

`research/data/renderer-viewport-live.md` carries the in-process read-back of everything in
§2, §4 and §7 from a running game — the screen Bitmap's three fields, all eight layers with
their rectangles and draw callbacks, and the scroll maxima beside the value §7 predicts them
to be. **13 of 13 assertions passed on the first run**, including the two that could have
falsified the map: layer 5 is 640x400 and appears only when a game loads, and the scroll
maxima are exactly `(mapTiles − viewportTiles) × 32`.

Produced by `tools/plugin/probe-screen-layout.ps1`, which drives one game to a loaded map and
reads twice (main menu, then in game). The reading itself is the plugin's read-only `SCREEN`
scan — `%SCPLUGIN_SCREENSCAN%` / `run-with-plugin.ps1 -ScreenScan 1`, **off by default**,
installs no hook, calls nothing in the game, and works in `-Mode observe`. The run's log
positively reports `mode : observe` and zero installed hooks, in that order.

This exists because AGENTS.md's standing rule is to read the engine's own memory rather than
reason about it, and because a static map of a subsystem with no prior art is precisely the
kind of claim this project has been burned by before. It earned its keep on the first run in a
small way: the two-arm design is what turns "layer 5 is 640x400" into "layer 5 is the
playfield", and the parked layer 1 at `(640,400)` confirmed a reading of two `MOV`s that would
otherwise have been an inference.
