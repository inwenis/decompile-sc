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

> **Corrected by task 063, which read the buffer's CONTENT rather than its descriptor
> (§13.2): the buffer holds less than "everything".** Measured at a marker instant in a
> running game, in two arms: the playfield composition and the top-strip counters are in it;
> the console/HUD dialogs are NOT (their pixels live in the dialogs' own surfaces — the ones
> `ScQueueIndCopyRect` reads), the cursor is NOT, and at the main menu the buffer is ALL
> INDEX 0 — the glue screens do not compose into it at all. How the presented frame is
> assembled from the pieces (per-layer render-target switching through `0x006CF4A8`, the
> present blit, or inside Storm) is NOT resolved; what is established is what a reader of
> this buffer sees. The two-writers argument above stands — the descriptor layout is
> correct — but "everything composes into this buffer" was an over-reading of the layer
> walk, and §12.2's row-diff results are unaffected (both its arms read the same regions of
> the same buffer).

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

> **Corrected by task 034, and the correction is the reason the relocation was affordable.**
> 62 is the count of instructions that *touch* the array, most of them stepping a pointer
> a loop already loaded. The number that matters for a relocation is how many instructions
> NAME the address, because those are the ones that have to be rewritten — and that is
> **21**, found by scanning `.text` for the encoded dword (every x86-32 absolute reference
> encodes it as a plain little-endian dword, so the scan is exhaustive by construction;
> `work/scratch/034/scan_refs.py`). Eighteen name the array's base, and three name a row
> inside it — `grid + 18*40` from 0x004B1FA0 and `grid + 1*40 + 26` from 0x0048CB80, whose
> offsets have to be RECOMPUTED for a new stride rather than rebased, or they land in the
> wrong row. §12 has the rest.

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
  off += 0x2780;                                        // 672 * 16 - 640 -> next 16 scanlines
  y += 0x10;
} while (y < 400);
```

`0x49800 = 301056 = 672 × 448`, addressed modulo its own size so scrolling wraps instead of
copying. **672 = 640 + 32 and 448 = 400 + 48** — the playfield plus one tile of margin. Both
the pitch (`0x2A0`) and the wrap size (`0x49800`) are immediates in this function.

> **Two corrections from task 034, which patched this function rather than only reading it.**
>
> 1. The row step is `0x2780`, not `0x2790` — read off the encoding at 0x004BCE6E
>    (`81 c7 80 27 00 00`). It is `672*16 - 640` with no `+ 16`, because the column loop's
>    own `add edi,0x10` has already supplied the last one. A patch built on the `+ 16`
>    reading would have skewed every terrain row by 16 bytes.
> 2. **§10 item 3's open question is answered: the producer is `FUN_0040AAE0`**, plus the
>    run-writer family at 0x0040C3E0–0x0040C4B0. It writes tiles INTO the scratch surface
>    with the same pitch (`mov ebx,0x2a0` at 0x0040AAFE) and the same wrap
>    (0x0040AAF0, 0x0040AB19, 0x0040ABAA), and it reaches the surface through the same
>    global. The surface's own allocation is `push 0x49800` at 0x004BD745 inside
>    `FUN_004BD6F0`, storing to **0x00628454** — one of four SMemAlloc calls that function
>    makes in a row, and the one whose size is 672×448.

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

> **Every row above, after task 034 executed stages 0-2.** "Confirmed" means the site was
> patched and the game ran with it; "not reached" means it belongs to stage 3+ and was never
> attempted, not that it is doubted.
>
> | # | status after execution |
> | - | ---------------------- |
> | 1 | **confirmed** — 4 sites; stage 0 runs and the game comes up |
> | 2 | **CORRECTED** — there are THREE writers of the descriptor, not two. `FUN_0041DDD0` allocates its own 0x4B000 and describes it at 0x0041DDDE/0x0041DDE7 (§12.4) |
> | 3 | **confirmed** — one immediate, exactly as described |
> | 4 | **confirmed** — declared as `storm.region.width`; applied, never independently observed |
> | 5 | **CORRECTED twice** — 21 instructions NAME the grid, not 62 (§5 note); and re-pointing them is not enough, because the stride is also open-coded as a byte count (0x004B1FA0), a walk step (0x0048CB80) and three fog row addresses (§12.5) |
> | 6 | **confirmed** |
> | 7 | **confirmed** — and its clamp is why an incoherent bisect subset drops redraws (§12.9) |
> | 8 | **CORRECTED** — the producer is `FUN_0040AAE0` (§6 note, closing §10 item 3); the row step is 0x2780 not 0x2790; and there are FOUR 8-row run-writers, not two (§12.7) |
> | 9 | **confirmed** |
> | 10 | **confirmed** |
> | 11 | **CORRECTED and split** — fog has framebuffer-ADDRESSING sites (stage 1) and playfield-CLIPPING sites (stage 2), which are the same number at 800x480 and nothing in the source distinguishes them. Plus 15 block-writer sites §9.1 did not know about (§12.8) |
> | 12-15, 17 | **not reached** — stage 3+, never attempted |
> | 16 | **confirmed** — layer 2 reads 800x480 in a running game |
> | 18 | **still not located** — §10 item 1 stands |
> | 19 | **decided, not solved** — no new art, by the user's explicit call. The strip beside the console stays blank |
> | 20 | **deliberately unmoved** — the HUD dialogs stay at stock coordinates, verified byte-identical between arms at every stage |
>
> **Not in §9.1 at all, found only by running it:** the fog 8x8 block writers (15 sites,
> §12.8), the third video-init copy, the scratch→screen copier's destination pitch, the shroud
> writer's pitch-minus-width row step, the two extra scratch run-writers, and the EFLAGS
> hazard class (§12.5) — which is not a site but a way for any of them to be wrong.

### 9.2 Verdict: NO-GO on 1.16.1, at this project's price point

> **Task 034 is executing 9.3 stages 0-2. Read §12 before this section** — the estimate
> below has been replaced by a measurement, and the measurement is larger and a different
> shape. What 032 could not know is that a read-back is not sufficient here: the layer
> rectangle and the framebuffer descriptor can all report the new size over a visibly
> broken frame, because those are the plugin's bookkeeping and the frame is the engine's
> result. §12.4 is the part worth reading even if the feature never lands.

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

> **CORRECTED BY EXECUTION — task 034. The table below is 032's plan and its stage 1/2
> boundary is wrong.** Two things force a different split, and both are in §12.5:
>
> - **items 5 and 8 cannot be separated.** The terrain blitter `FUN_004BCDC0` walks the
>   dirty grid LINEARLY — one byte per column, never re-based per row — so its column count
>   must equal the grid's stride. Widening the grid without widening the blitter's walk
>   desynchronises them by (stride − columns) bytes every row, which is a shredded frame.
> - **the framebuffer's PITCH and the playfield's WIDTH are different changes** and want
>   different stages. Everything that computes an address into the frame moves when the
>   buffer widens; everything that clips moves when the playfield widens.
>
> The staging that actually works, and the one to inherit:
>
> | stage | scope | pass condition |
> | ----- | ----- | -------------- |
> | 0 | display mode only | the game comes up; the framebuffer descriptor is still stock |
> | 1 | **the framebuffer pitch alone** — buffer size and descriptor, blit source pitch, the copier's destination pitch, the screen fill, and every fog/shroud routine that addresses the frame. No rect, clip, bound or grid moves. | **the frame is pixel-identical to the control's.** A binary condition, not a judgement |
> | 2 | the playfield: dirty grid (relocate + stride) AND terrain scratch together, Storm region, layer rects, composer clip, per-image and rect clips, fog extents, placement | layer 5 reads the new size AND the interior matches the control where both show the same map |
>
> **Outcome, measured:** stage 0 and stage 1 pass their conditions in a running game. **Stage 2
> does not** — it applies cleanly and the read-back carries the new size, and the frame is
> wrecked (§12.9). It was also shown NOT to decompose: every subset of it that leaves part of
> the geometry stock is incoherent in a way that predicts its own damage, so the stage is one
> atomic change of ~121 sites rather than a sequence.
>
> Stages 3-5 are unchanged from 032's plan and are listed below. None of them was attempted.

| stage | scope | proves |
| ----- | ----- | ------ |
| 3 | Input and camera: items 12, 13, 15, 17. | clicks land where they look, the camera reaches the map edges |
| 4 | HUD: items 16, 19, 20. | a stock HUD anchored to the bottom of a wider screen |
| 5 | Minimap viewport rectangle (item 18), once located. | the minimap agrees with the camera |

A first slice that is worth showing a human does not exist before stage 2 completes, which is
why this task took none of it — stage 0 and stage 1 produce a 640x400 image sitting in the
corner of a bigger black rectangle, which is strictly worse than what the user has now.

## 10. What this task did NOT determine

Listed because leaving it out would make the map read as more complete than it is.

> **Task 034 closed items 2 and 3 by running them.** Item 2 (how WMode behaves at another
> resolution) is answered in §12.5; item 3 (what fills the terrain scratch surface) is
> answered in the §6 note. Items 1, 4, 5 and 6 are still open.

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

## 12. Task 034 — executing §9.3, stages 0-2

§9.3 was a plan nobody had run. This section is what running it taught.

**Where it ended up, so nobody has to read to the bottom for it:**

- **stage 0 and stage 1 work.** The engine composes into an 800-pitch framebuffer and the
  picture is indistinguishable from the stock one at the resolution the instrument can
  measure (§12.2).
- **stage 2 does not.** The read-back says 800x400 and the frame says otherwise — 332 of 380
  rows damaged, 21 points blacker than the control. It was attempted twice, bisected, and left
  broken (§12.9).
- **and none of that is the blocker.** `WMode.dll` presents 640 columns whatever it is asked
  for, so a perfect stage 2 would still put zero new pixels on the monitor through the current
  launcher (§12.10). The question was never whether the engine can compose a wider frame — it
  can — but whether anything can present one.

The most transferable parts are not the site count: they are that **the read-back this project
trusts was not sufficient here** (§12.2), and that **an enumeration built by scanning for a
name is not exhaustive** (§12.8).

### 12.1 The target, and why 800x480 rather than 800x600

§9.3 suggested 800x600. 800x480 is strictly cheaper and looks better:

- the height stays 480, so the console stays exactly where it is (y=400..479) and **every
  480/400/479/399 immediate in §8 is left alone** — 13 of the declared sites are already
  correct at this geometry and are verified but never written;
- the dead space is one 160x80 block beside the console rather than an L-shape;
- 5:3 is closer to a 16:9 monitor than 4:3 is.

The generator is parametric, and the whole table was regenerated at 800x600 as an experiment
(§12.6), so this is a configuration and not a fork.

### 12.2 The read-back said 800x400 over a shredded frame

The first build that ran end to end passed seventeen assertions. The framebuffer descriptor
read 800x480. Layer 5 read 800x400 at (0,0). Every HUD dialog rectangle was byte-identical to
the control arm's. Three independent pixel samplers — the HUD band, the top strip, and the
rightmost non-black column — agreed to 98.9%.

The frame was visibly wrecked: horizontal bands across the playfield, terrain displaced in
strips, the shroud edge stepped instead of smooth. A human opened the capture and saw it in
one glance.

Every number above is true. The conclusion drawn from them was false, for two reasons worth
separating:

1. **A layer rectangle is the plugin's bookkeeping, not the engine's result.** This is
   AGENTS.md's "assert the ENGINE'S OWN RESULT" rule (task 029) meeting a subsystem whose
   result is *pixels*. `layer5.width == 800` says the record was written. It says nothing
   about what was drawn through it.
2. **The three samplers could not fail.** They covered the HUD band, the top strip and the
   right edge — all three outside the playfield. The damage was inside it. A sampler that
   never looks where the damage is has no failure mode, however precise its percentages.

So the suite now compares the **playfield interior** against the control frame row by row
(`tools/plugin/frame-diff.py`), and that check was proved able to fail before it was trusted:
pointed at the broken build it reported **184 of 190 rows bad and a median row match of 27%**.

> **The noise-floor half of that sentence was wrong, and this is the correction.** It used to
> read "calibrated against noise, which turns out to be zero: at stage 0 the two arms are
> pixel-identical — median 1.000, no bad rows, black delta 0". Measured again at FULL
> resolution, stage 0 — where both arms compose the identical 640x480 picture — differs by
> **586 of 307200 pixels in seven isolated 32x32 blocks**. Animated map doodads, caught at
> different phases, because the frame is grabbed by wall clock.
>
> The old reading came from comparing every SECOND pixel against a 90%-per-row threshold,
> which a few hundred pixels cannot move. It is the same family as the three samplers above,
> one level up: not a check looking in the wrong place, but a check too coarse to see what it
> claimed. "Pixel-identical" was never available as a pass condition and was reported as met.
>
> **What replaces it is shape, because damage and animation separate cleanly there and not in
> the count.** A wrong pitch damages whole ROWS across the whole width; animation differs in
> isolated blobs and spans no row. `frame-diff.py` now reports, at full resolution, the
> number of differing pixels, the 32x32 blocks they touch, and `wide_rows` — rows whose
> differing pixels span more than half the region. The suite asserts on `wide_rows` and
> reports the pixel count beside the measured noise floor.
>
> | | broken stage 1 | noise floor (stage 0) | stage 1 fixed | stage 2 |
> | - | - | - | - | - |
> | differing pixels of 307200 | 127k+ | 586 | 743 | 131944 |
> | 32x32 blocks touched | 215 | 7 | 7 | 215 |
> | **rows damaged across the width** | 163 of 190 | **0** | **0** | **332 of 380** |
> | widest single-row diff span | 635px | 278px | 23px | 621px |
>
> `wide_rows` fired on a real broken build before it was ever trusted — stage 2 supplied the
> positive control in the same suite on the same map, so no build had to be broken on purpose.

The frames stay on the gitignored diagnostic path and are never committed (hard rule 1,
AGENTS.md "Screenshots vs hard rule 1"); what crosses into this document is row indices and
match percentages.

### 12.3 How ~130 byte-patches were made reviewable

There is no viewport variable to set (§9.2 reason 1), so the feature is instruction-operand
rewrites. Three things carry the weight:

1. **`tools/renderer_patch_sites.py` generates the table.** For each declared site it
   disassembles the same `StarCraft.exe`, LOCATES the old value inside the instruction rather
   than trusting a hand-counted offset, refuses a site whose bytes are not what this document
   says, and emits the before/after disassembly beside every record.
2. **`sc_screen.cpp` re-verifies every site in the live process and refuses the whole table on
   the first mismatch** — `sc_hook.cpp`'s rule applied to data-sized patches. All-or-nothing
   matters: a half-applied geometry does not fail, it corrupts.
3. **It refuses to run late.** Every pitch describes a buffer allocated during startup, so the
   plugin checks the framebuffer pointer (0x006CEFF4, zero until the video init runs) and
   refuses if the game is already up.

### 12.4 The four shapes an immediate sweep cannot see

The most transferable finding here, and a permanent caveat on every immediate-sweep estimate
this project makes. **A sweep for the literal 640 finds the sites that spell 640. It does not
find the sites that compute it.**

1. **A third copy of the video init.** 032 found two writers of the screen Bitmap descriptor.
   There are three: `FUN_0041DDD0` allocates its own `0x4B000` buffer (0x0041DDD9) and
   describes it at 0x0041DDDE/0x0041DDE7, with the same `vidinimo.cpp` file and line as
   `FUN_004DB060`.
2. **`x * 640` built as `lea r,[x+x*4]` + `shl r,7`.** Five, then a shift. Four sites in the
   binary: the screen fill 0x0041D3E6, and three in fog — 0x0047EDD3, 0x0047EF3A, 0x00480635.
   All four are framebuffer row addresses.
3. **`t * 672` built as `(t<<9) + (t<<7) + (t<<5)`.** One site, 0x0040C275–0x0040C281, in the
   full-playfield terrain blit `FUN_0040C253`. No 672 appears anywhere in that function, and
   it positions every terrain row the non-dirty path draws.
4. **A pitch held as `pitch − width`.** `FUN_0047EA60`, the shroud writer, does
   `mov esi,0x280; sub esi,ebx` — the row step is the framebuffer pitch minus the run width,
   and the constant never appears in an address computation at all.

Point 4 survived longest, and its symptom is worth recording: shroud is drawn only at the
EDGES of an explored map, so leaving it at the old pitch produced a broken frame around a
perfectly intact centre. Damage in the middle of a picture is easy to see; damage at the
border is exactly what a centre-weighted check misses.

Points 2, 3 and 4 are also why the patch is possible at all: `imul r32,r/m32,imm8` is three
bytes, exactly what `lea r,[c+c*4]` costs, so x5 becomes x25 in place; a SIB scale drops from
8 to 2 for a 50-column stride; 832 is a sum of three powers of two just as 672 is; and
800 = 25<<5 just as 640 = 5<<7. A target width that broke any of those would have needed code
INSERTED, which this plugin's patcher cannot do.

### 12.5 Two corrections to §9.3's own staging

**Items 5 and 8 are not separable.** §9.3 puts the dirty grid in stage 1 and the terrain
scratch surface in stage 2. They cannot be split, and the terrain blitter is why:
`FUN_004BCDC0` walks the grid LINEARLY, advancing one byte per column and never re-basing per
row, so its column count must equal the grid's stride. Widening the grid without widening the
blitter's walk desynchronises them by (stride − columns) bytes every row.

So stage 1 here is **the framebuffer pitch and nothing else** — every rectangle, clip, dirty
bound and the grid itself stay stock, and the engine composes a 640-wide picture into an
800-pitch buffer. That is a weaker stage than §9.3 imagined and a far more checkable one: its
frame must be pixel-identical to the control's, which is a binary condition rather than a
judgement.

**And `lea` → `imul` is not a free swap.** `lea` leaves EFLAGS alone and `imul` does not. At
three grid sites a `cmp`/`test` before the splice is consumed by a `jcc` after it —
0x0041E15D (`cmp ecx,esi` … `jg`), 0x0042D2C9 (`cmp edi,eax` … `jg`) and 0x00497062
(`test eax,eax` … `je`). The first is the dirty-block MARKER, so it branched on the multiply
and whole bands of blocks were never marked dirty. The fix is a reorder inside the same byte
count, with the flag setter last and the branch left at its own address so its rel8 is
unchanged. **The generator now refuses this class outright**: if a replacement writes EFLAGS
where the original did not, it walks forward and fails on the first reader.

**And re-pointing a base pointer is not enough when the arithmetic AROUND it encodes the old
stride.** This one showed up three times in three different syntactic shapes, none of which
contains a base address to notice:

| where | shape | what it really is |
| ----- | ----- | ----------------- |
| `FUN_0047EA60` | `mov esi,0x280; sub esi,ebx` | a framebuffer row step, held as pitch − run width |
| 0x004B1FA0 | `lea ecx,[eax+eax*4-0x55]; shl ecx,3` | a byte COUNT, `40*(row-17)` |
| 0x0048CB80 | `add ecx,0x28` | a walk step of one grid row |

The relocation machinery re-points every instruction that NAMES the grid, and would have left
all three of these alone — they name nothing. A stride is a number that describes a layout
without pointing at it, which is exactly why a search for the layout's address cannot find it.

**The consequence is the reason it matters: all three produce MISSED REDRAWS, not crashes.**
A crash tells you. A block that is never marked dirty, or a row filled 40 bytes wide out of
50, simply keeps whatever was there before — and that survives into a screenshot and reads as
a rendering quirk. It is how the first round of this task produced a confident "the helper is
just cropping" verdict out of a shredded frame. The family is *damage that renders*, and the
defence is not more reading: it is the row-by-row interior diff of §12.2, calibrated against a
control that is known to be pixel-identical.

### 12.6 The presentation half — §10 item 2, answered

**`WMode.dll` presents 640x480 whatever display mode it is asked for**, measured by
`tools/plugin/probe-widescreen-present.ps1` in two arms through both vectors:

| measurement | result |
| ----------- | ------ |
| client area, both arms, at 800x480 and at 800x600 | 640x480 |
| HUD band, widescreen vs stock, sampled | 98.9% identical |
| top strip | 100% identical |
| rightmost non-black column, both arms | x=639 of 640 |

Identical pixels rule out scaling — a 0.8x squeeze moves every HUD pixel — so the helper shows
columns 0..639 at 1:1 and discards the rest. **800x600 does not rescue it**: the table was
regenerated at that size and re-run, with the same verdict, so this is not "the mode is
non-standard".

**The other vector says nothing, and a control is what established that.** `WMode.dll` copied
in as `ddraw.dll` (the `research/launch-baseline.md` recipe) brings up a "Direct Draw Error"
box — and does so in the **stock arm too**, with the geometry unpatched. That vector is not
working on this machine at present, in either arm, and is not evidence about widescreen.
Reported without the second arm it would have been a wrong finding.

**One presentation path is deliberately untested.** True fullscreen with no helper is the only
route that could put 800 columns on a monitor, and it was not run unattended: it switches the
user's 3840x2160 desktop to a small mode, and that rearranges desktop icons — live user state
that does not come back when the mode does (hard rule 5).

### 12.7 The measured bill, against §9.1's estimate

§9.1 estimated "~60 instruction sites plus two fixed-size buffers plus two data assets" for
ALL stages. For stages 0-2 alone:

| | §9.1 estimate | measured |
| - | ------------- | -------- |
| instruction sites, stages 0-2 | ~60 for all stages | **166 declared, 153 written** |
| — of those, stage 1 (framebuffer pitch alone) | — | **41 declared, 36 written** |
| — of those, stage 2 (the playfield) | — | **121 declared, 115 written** |
| of those, not in §8's table | — | **~44** |
| distinct kinds of edit | "patch a constant" | 6: imm8/imm16/imm32, SIB scale, shift count, absolute address |
| dirty-grid references to re-point | 62 instructions | **21** (see the §5 note) |
| terrain-scratch sites | "immediates in this function" | **40 across 9 functions** |

The estimate was low by **a factor of nearly three** on stages 0-2 alone, and wrong in shape:
§9.1 assumed every site was an immediate. And the count kept growing under execution rather
than converging — 140 sites when the first stage-1 build ran, 149 after a shape sweep, 164
after the fog block writers, 166 after the scratch-writer pair. **Every increment came from a
live run failing, never from re-reading.**

### 12.8 Stage 1: fifteen sites a scan for the framebuffer POINTER cannot reach

The first stage-1 build failed its own binary condition: **163 of 190 interior rows disagreed
with the control**, and the block map named the cause immediately — a perfect rectangle in the
middle with damage all around it. The explored area was pixel-perfect; everything under fog or
shroud was wrong. Numerically, nothing was displaced: identity is the best mapping (0.63) and
every stride-remap and vertical-squeeze hypothesis scores ~0.25.

`FUN_00480600` draws fog in 8x8 blocks and hands a framebuffer pointer to one of three block
writers. Two step with `add esi,640` and were declared. The third, `FUN_004800A0` (the
fully-shrouded case), is UNROLLED and holds the pitch as **fourteen displacements** —
`[ecx + k*640]` and `[ecx + k*640 + 4]` for k=1..7 — and the outer loop advances a block row
with `add ecx,8*640` at 0x004806D0. Fifteen instructions, **of which exactly one spells 640**.

**The rule this establishes, which is the one to carry forward.** The old enumeration was built
by scanning `.text` for the framebuffer pointer 0x006CEFF4, and this document claimed that made
it exhaustive. It does not:

> **A routine that is HANDED a pointer writes through it without ever naming it.** An
> enumeration built by scanning for a NAME — an address, a global, a symbol — covers only the
> routines that mention it, never the callees they pass it to. `FUN_004800A0` sits 1405 bytes
> from the nearest reference to the pointer it writes through.

`tools/renderer_pitch_sweep.py` is the generalisation: sweep for `k*pitch + d`, not for the
pitch. Two details are load-bearing:

1. **searching multiples alone finds 7 of those 14 stores.** The `+4` twins — the second dword
   of an 8-byte-wide block row — are not multiples of anything. Half a fix, in a subsystem
   where half a fix renders.
2. **capstone stops at the first byte it cannot decode**, and `.text` is full of int3 padding
   and jump tables. The first version of the sweep covered about 3% of the section and printed
   "nothing found". A sweep that scans 3% and reports zero is indistinguishable from a correct
   all-clear.

### 12.9 Stage 2: attempted, not reached — and what the bisect established

Stage 2 applies cleanly (153 sites, 0 refused) and **the read-back is entirely green**: the
framebuffer reads 800x480, the dialog layer 800x480, **layer 5 reads 800x400 at (0,0)** with
its draw callback still 0x004BD580, and the HUD dialogs are byte-identical to the control's.
The frame is wrecked: **332 of 380 rows damaged across the width, and 16-21 points more black
than the control** — large areas never drawn, at playfield scale.

Two fixes were attempted, and the second is recorded because it is instructive that it failed:
the scratch-surface sweep (§12.7's +2) found two genuine undeclared row steps, they applied
cleanly, and **the damage did not move**. A real defect that is not the defect.

A group filter (`%SCPLUGIN_WS_ONLY%`) was then added to bisect the 121 sites. What it
established, and what it deliberately does not:

| build | sites | rows damaged across width | black delta |
| ----- | ----- | ------------------------- | ----------- |
| stage 1 only | 36 | 0 | 0.000 |
| stage 2, whole | 153 | 332 | **+0.210** |
| grid + dirty + terrain (the coupled core) | 126 | 331 | **+0.185** |
| everything EXCEPT that core | 65 | 208 | +0.014 |
| ditto, minus fog | 50 | 148 | +0.000 |

**The black delta is the attributable signal, and it says the dominant defect is in the
grid/terrain core.** The core alone reproduces the +0.19 "never drawn" component; every build
without it collapses to ~0.

**The banding in the last two rows is my subset's own artifact, not evidence.** Declaring the
playfield 800 wide WITHOUT the dirty-rect clamps means `FUN_0041E0D0` still does
`if (x1 > 0x27f) return` and rejects whole dirty rects outright, so those builds drop redraws
by construction. The filter's source carries this warning and it applied to the reading of its
own output — which is the honest form of a bisect over coupled sites.

**So the real finding about stage 2 is structural: it does not decompose.** §12.5 established
that items 5 and 8 cannot be separated; the bisect extends that to the whole stage. Every
subset that excludes part of the geometry is incoherent in a way that predicts its own damage,
so "which group is at fault" is not a well-formed question here. Stage 2 is one atomic change
of ~121 sites, and it is not currently correct.

### 12.10 The gating fact is presentation, not corruption

**Every frame this task has ever captured shows only the LEFT 640 columns of an 800-wide
composition** — `WMode.dll` presents 640x480 whatever it is asked for (§12.6), so the window is
650x517 in both arms at every stage. The extra 160 columns have never been seen by anything, in
any run.

This reorders the whole problem. Even a perfectly rendering stage 2 would put **zero** new
pixels on a monitor through the current launcher. The blocker was never "can the engine compose
a wider frame" — it can, and the descriptor and every layer rect prove it — but **"can anything
present one"**. The only route that could is true fullscreen with no helper, which switches the
user's 3840x2160 desktop to a small mode and rearranges their desktop icons (hard rule 5), so
it is a decision for the user rather than a step to take unattended.

> **Split in two by task 063 (§13): presentation gates SHIPPING the feature, not DEVELOPING
> it.** "Every frame this task has ever captured shows only the left 640 columns" was a
> property of the instrument — every capture went through the presented window. Reading the
> engine's own framebuffer shows all 800 columns with no window involved (§13.3), so stage 2
> is developable today with zero user impact; and the presentation routes themselves are
> costed in §13.4, where "true fullscreen is the only route" also stops being true.

### 12.11 A negative result that is not over-read

The same shape sweep was pointed at the dirty grid's row stride (40, anchored on 0x006CEFF8)
and **the result is not usable**. 40 is small enough that its multiples are the whole binary:
200, 320, 400 and 480 all match it, and every hit read by hand was the playfield HEIGHT, a
struct field offset, or a dialog coordinate. It is recorded here as a bounded negative — the
method works for 640 and 672 and does NOT work for 40 — rather than dropped, because a sweep
whose hits are all noise looks exactly like a sweep with nothing to find.

### 12.12 How to reproduce

```powershell
python tools/renderer_patch_sites.py --check          # every site verifies against the exe
python tools/renderer_pitch_sweep.py                  # stride-shaped operands, undeclared ones flagged
python tools/renderer_pitch_sweep.py --pitch 672 --anchor 0x00628454   # the scratch surface
./tools/plugin/test-widescreen.ps1 -Stage 1           # two arms, frames compared row by row
./tools/plugin/probe-widescreen-present.ps1 -Stage 0  # what the helper actually presents

$env:SCPLUGIN_WS_ONLY = 'grid,dirty,terrain'          # bisect stage 2 by group (read the
./tools/plugin/test-widescreen.ps1 -Stage 2           #   coupling warning in sc_screen.cpp)
```

The suite reads the target geometry out of the generated header, so regenerating at another
size cannot leave it asserting the old numbers.

## 13. Task 063 — reading the composed frame without presenting it, and the presentation bill

§12.10 ends on "the extra 160 columns have never been seen by anything, in any run". Task 063
tested the one sentence in that verdict that was about the INSTRUMENT rather than the engine —
every frame 034 captured went through the presented window — and it falls: **the engine's own
framebuffer, read out of process memory, shows all 800 columns.** Stage 2 is developable today
with zero user impact.

### 13.1 The instrument

The plugin's `FRAMEDUMP` (scplugin.cpp, task 063) copies the screen Bitmap's buffer — the
descriptor at `0x006CEFF0`, §2 — to `fd-<marker>.bin` on each marker. Same family as the
`SCREEN` scan: no hook, nothing called in the game, works in `-Mode observe`, off by default
(`%SCPLUGIN_FRAMEDUMP%` / launcher `-FrameDump <dir>`, gitignored paths only — a dump
reproduces game artwork, hard rule 1). Tearing is handled by construction, not hope: the copy
repeats until two CONSECUTIVE copies are byte-equal, and `reads=` / `stable=` go on the log
line and into the 16-byte file header (`SCFD`, u16 w, u16 h, u32 bytes, u16 reads, u16
stable), so an unsettled copy cannot pass silently.

**How a pile of palette indices is validated** (`tools/plugin/frame-capture.py check`): the
presented window shows the RGB those indices were painted as, at 1:1 for columns 0..639
(§12.6). Over window pixels that are IDENTICAL in two captures bracketing the dump, every
occurrence of index *i* must land on one RGB. A torn, misaligned or wrong-pitch dump collapses
that mapping — proved offline before any live run, against synthetic dumps: a correct dump
scores `consist_frac=1.000`, the same dump with rows shifted 160 bytes (the wrong-pitch
signature) scores `0.583`. The check also refuses a dead window capture (a black window maps
every index to black, each one perfectly "consistently" — `window_distinct_rgb >= 32` guards
the vacuous pass), and auto-finds the capture's caption offset (measured live: the game's
(0,0) sits at (5,32) inside the client capture — drive-game.ps1's PW_CLIENTONLY warning,
quantified).

### 13.2 The positive control, and what it taught about the buffer

`probe-framebuffer-capture.ps1`, stock arm, `-Mode observe`, off-screen, 2026-08-13. The
first run's whole-frame consistency read 0.75 with the dump entirely correct, and diagnosing
that number produced the section-2 correction — the buffer holds LESS than "everything":

| where | measured | meaning |
| ----- | -------- | ------- |
| main menu, both arms | buffer is ALL index 0 (307200/307200, 384000/384000) | glue screens do not compose into `0x006CEFF0` |
| in game, console band y=320..447 | consistency 0.49; dump renders black where the window shows console art | the HUD dialogs' pixels are NOT in this buffer — they live in the dialogs' own surfaces, the ones `ScQueueIndCopyRect` reads |
| in game, cursor | absent from the dump, present in the window | layer 0's result is not in the buffer at the marker instant |
| in game, pure playfield (128,20)-(512,320) | **consistency 0.98902 (stock) / 0.98912 (stage 1)**, 115k mapped px, 121 indices | the buffer IS the playfield picture, index for index |
| the ~1.1% residue | 1265 px in isolated 32x32 blobs (mineral fields, the marine), no row spanned; per-index spread = two near RGBs | sprites animating A→B→A across the capture bracket — the same animation family as §12.2's 586-pixel noise floor |

So the suite's trust check asserts the pure-playfield region at threshold 0.97 — far above
the 0.58 a wrong-pitch dump scores, below the animation ceiling — and reports the menu
buffer's content instead of asserting a picture that is not there.

### 13.3 The 800-wide frame — §12.10's blocker was the instrument

Stage-1 arm (`-Widescreen 1 -WidescreenStage 1`), same run:

- the dump reads **800x480, 384000 bytes, stable** — at the menu and in game;
- the playfield consistency (0.989) holds **only if rows are extracted at the true pitch of
  800** — a 640-pitch misread shifts row *y* by 160·*y* bytes and scores 0.58 on the
  synthetic control — so the full-width geometry is read correctly, not merely more bytes;
- **the right 160 columns read end to end**: 76800/76800 px, all index 0 in both scenes —
  exactly what stage 1 predicts (the 800-aware screen clear writes them, nothing else does);
- cross-arm, in game, same fixture, same origin (544,416 both arms): stage-1's left 640
  columns agree with the stock arm's INDEX FOR INDEX over the playfield interior —
  `wide_rows=0`, 1252 differing px in 6 blocks (animation), widest row span 75 px;
- the dump renders to a recognizable 800x480 PNG through the palette the check derives
  (gitignored diagnostic path; the path travels, never the image).

**Consequence, stated plainly: stage 2 is now developable without presenting a single frame
and without touching the user's display.** The row-diff oracle §12.2 built on window captures
ports directly to dumps (`frame-capture.py diff` implements the same `wide_rows`
discriminator on raw indices, no palette involved), and it sees all 800 columns instead of
the left 640. §12.10's fact still stands for SHIPPING: a user playing wider still needs a
presentation route — that bill is §13.4.

### 13.4 The presentation bill (task 063's costing of §12.10's routes)

Facts measured or established this task, then the routes they price:

1. **This adapter has no 800x480 mode.** `EnumDisplaySettingsA` walk, 2026-08-13: 132 mode
   entries, 21 distinct resolutions; 640x480 and 800x600 present, 800x480 absent. True
   fullscreen at the feature's own geometry is impossible on this machine — the only
   fullscreen-viable widescreen shape is the parametric 800x600 regeneration (§12.1, the
   L-shaped dead space).
2. **storm.dll imports nothing from ddraw.dll** (research/pe-anatomy.md import table: six
   DLLs, no ddraw) — every DirectDraw call below the exe flows through the three interface
   pointers `0x0041D930` creates and hands to SDraw's Ordinal_351. A replacement `ddraw.dll`
   therefore has one client worth of surface area: the exe's calls (§3, enumerated) plus
   whatever methods Storm invokes on those objects (bounded, readable out of storm.dll's
   export RVAs).
3. **A source-available non-cropping helper already exists**: cnc-ddraw
   (github.com/FunkyFr3sh/cnc-ddraw, MIT) — a GDI/OpenGL/D3D9 re-implementation of
   DirectDraw, windowed/borderless, upscaling, StarCraft on its supported-games list. Its
   documented architecture presents the full surface the game asks for — the opposite of
   WMode's measured crop — but that is documentation, not measurement.

| route | cost to a decision | cost to done | user impact while testing |
| ----- | ------------------ | ------------ | ------------------------- |
| WMode.dll (current) | decided: presents 640 whatever it is asked (§12.6) | — | — |
| true fullscreen, user's desktop | decided for 800x480: impossible (no mode). 800x600: user-attended decision | regenerate at 800x600 + user accepts mode switch + icon shuffle | switches their desktop; never unattended |
| true fullscreen, invisible desktop (test vehicle) | one probe run (`probe-fullscreen-desktop.ps1`, **built and deliberately NOT run**: parent samples the REAL desktop mode 4x/s while the child launches fullscreen off-screen; restore-on-leak; CONTAINED/LEAKED/REFUSED verdict). Withheld because §13.3's YES removed what it blocked, and its LEAKED outcome spends the user's icon layout — the conductor holds it for a user-attended GO | n/a — it is a measurement, not a shipping route | none if CONTAINED/REFUSED; seconds of mode flip if LEAKED |
| **cnc-ddraw** | **one task**: build/obtain, drop in via the existing `-Windowed` mechanism, run `probe-widescreen-present.ps1` and read CROP/SCALE/FOLLOW | config + the same stage-2 work the engine side always needed | none (windowed, off-screen testable) |
| own ddraw shim | bounded by facts 2–3 but strictly dominated by cnc-ddraw unless it fails its probe | est. 4–8 tasks | none |
| plugin-side presenter (hook the ONE present blit `FUN_0041D420`, StretchDIBits the engine's buffer at its true pitch) | design known; palette capture is the open question (Storm's GDI palette imports / the §12.6-adjacent palette registers) | est. 2–4 tasks | none |

**Recommendation:** cnc-ddraw measurement task first; fullscreen only ever as a user-attended
800x600 choice; own code only if cnc-ddraw's probe comes back CROP. And note what the
cnc-ddraw probe also answers for free: WMode-as-`ddraw.dll` throws a DirectDraw Error in both
arms on this machine (§12.6) — a helper that IMPLEMENTS DirectDraw instead of forwarding to
it separates "the proxy loading path is broken" from "WMode is".

### 13.5 How to reproduce

```powershell
python tools/plugin/frame-capture.py --help                     # dump decode/check/diff/band
./tools/plugin/run-offscreen.ps1 -Suite ./tools/plugin/probe-framebuffer-capture.ps1
#   two launches: stock-observe positive control, then stage 1; asserts the
#   playfield consistency, the 800x480 read, the right band, the cross-arm diff
./tools/plugin/probe-fullscreen-desktop.ps1   # the §13.4 desktop measurement -- ONLY with a
#   user-attended GO: its LEAKED outcome flips the real desktop's mode for seconds
```

Dumps and rendered PNGs land in `C:\sc-work\logs\063-frames\` (gitignored); the suite prints
their paths for a human to open. Nothing in any of it changes what the user sees when they
play, and `StarCraft.exe` on disk stays byte-identical.

## 14. Task 065 — cnc-ddraw measured: the ddraw vector presents all 800 columns

§13.4's recommendation executed: cnc-ddraw dropped in through the EXISTING `-Windowed`
vector and measured with the §12.6 instrument, WMode control in the same run. **Verdict:
FOLLOW — the client area is itself 800 wide, the menu draws 1:1 in columns 0..639, and the
right 160 columns are presented as the stage-1 blank band.** The crop is gone from the
presentation path; what fills those columns is task 064's half (stage 2).

### 14.1 Provenance and mechanism

- **Binary:** cnc-ddraw v7.1.0.0 (github.com/FunkyFr3sh/cnc-ddraw, MIT, published
  2024-12-28), release asset `cnc-ddraw.zip`,
  zip sha256 `0b13ab89a64c9918189b1dadd449ef6ed3cb3b7b19cabd96d8adbd95505bb908`,
  ddraw.dll sha256 `85e0f7d530dfda134793a57cb3e76b0287dcc96892ee57162dd68f47283b03a9`,
  x86 PE confirmed (machine 0x14C). Fetched and pinned by
  `tools/plugin/fetch-cnc-ddraw.ps1` to `C:\sc-work\cnc-ddraw\v7.1.0.0\` — a
  game-adjacent binary, never committed (hard rule 1); a hash mismatch on re-fetch is a
  hard stop, not a re-pin.
- **Install:** `run-with-plugin.ps1 -Windowed -WindowedHelperDll <path>` copies it in as
  `$GameDir\ddraw.dll` exactly where the WMode recipe copies WMode.dll, plus the repo's
  `tools/plugin/cnc-ddraw.ini` as `$GameDir\ddraw.ini` (windowed=true, width/height=0 so
  the window IS the requested surface, renderer=gdi for the invisible desktop,
  savesettings=0 so nothing rewrites the shared game dir). `-RemoveWindowed` removes both.
  Empty `-WindowedHelperDll` is the WMode recipe, unchanged.
- **The probe is §12.6's, parameterised, not replaced:** `-WindowedHelperDll` passes
  through, and `-Vector both` is the whole experiment in one run — inject arm = WMode
  (control), ddraw arm = cnc-ddraw (candidate).

### 14.2 Run 1 (2026-08-13 ~13:24, off-screen, stage 1, four launches under one lock)

| arm | client (API) | capture | probe verdict line |
| --- | ------------ | ------- | ------------------ |
| inject ws1 / ws0 (WMode) | 640x480 both | 640x480 both | "SCALE (or something else)" at 93.5% band match |
| ddraw ws1 / ws0 (cnc-ddraw) | **800x480** / 640x480 | 800x480 / 640x480 | **FOLLOW** |

Both cnc-ddraw arms launched healthy — no DirectDraw Error box. §12.6's error was
therefore WMode's own, not the proxy loading path's: a helper that IMPLEMENTS DirectDraw
loads fine where the forwarding one died, which is the separation §13.4 predicted the
probe would answer for free.

**The control's verdict string missed its threshold and the structural analysis is what
anchors it** (`tools/plugin/analyze_present_frames.py`, readings from the run-1 PNGs):

- inject ws1 vs ws0: 19,949 px differ (6.5%) — and **0 of 640 columns have >50% of rows
  differing** (a 0.8x rescale moves every pixel and damages every column), max column
  fraction 0.32, all differences in **5 clusters** (16px cells, 8-connected). The 6.5% is
  spatially local — animation's shape, not a rescale's. WMode still presents columns
  0..639 at 1:1 and discards the rest; the 95% line simply sits inside the menu's
  animation noise (the same animated menu §"Foreground" measured changing in background,
  two fingerprints 3 s apart).
- ddraw ws1: green menu text occupies the same rows (138) as in every other arm — no
  vertical shift or scale — and the right band x≥640 below row 31 is **99.86% visually
  black** (100 of 71,840 px above channel-sum 12, all dim seam pixels x≤645). The band's
  "black" is palette-mapped game output, not the window's background brush: it carries a
  sparse speckle of (0,4,0) and (16,0,0) — GDI's rendering of near-black palette entries —
  where a brush fill would be literal (0,0,0).

### 14.3 Two capture artifacts, found and bounded (they contaminate one probe metric)

1. **cnc-ddraw window captures carry a caption-colored strip in rows 0..30** — in ws0 AND
   ws1, so it is not a widescreen effect. It is the §13.1 chrome-in-capture problem in a
   new skin: `Save-ScWindowImage` grabs window pixels (the game's (0,0) measured at (5,32)
   for the WMode window), and cnc-ddraw's window has a standard Windows caption where
   WMode draws its own dark StarCraft-styled one — so the same inclusion is cream and
   obvious in one helper and dark and invisible in the other. First seen as "right band
   11.14% non-black"; excluded (rows 0..30), the band is black.
2. **The probe's "content right edge" metric reads chrome, not content**, for the same
   reason: the caption strip runs to the last column, so `edge=799/800 (100%)` is true of
   the caption in the cnc-ddraw arms and of WMode's skinned caption art in the inject
   arms. The FOLLOW branch keys on capture WIDTH and is unaffected; the right-edge
   percentages should not be quoted as scale evidence. The per-column locality analysis
   replaces them: window chrome is identical between the arms of a vector, so it
   contributes zero to the cross-arm diff.

### 14.4 Run 2 — same-arm brackets (the animation theory measured, not assumed)

Four predictions were filed with the conductor BEFORE the run, each with its
falsification reading (message
`20260813-123723-from-065-prediction-on-record-for-the-bracketed-re-run.md`). Run 2
(2026-08-13 ~12:58, same four launches plus `-BracketSeconds 4`): **all four confirmed,
none falsified.**

1. **Same-arm delta (same window, nothing changed but time, 4 s):** inject ws1 94.3%,
   ws0 93.7% identical — the same order as the 93.5% cross-arm number, inside the
   predicted 90–98%, nowhere near the ≥99.5% that would have meant the menu is static
   and the control's 6.5% real signal. **The cross-arm difference is fully accounted for
   by time alone; the WMode control is anchored as CROP.** Stated precisely: the
   cross-arm figure (93.5%) sits a hair BELOW both same-arm figures (93.7%, 94.3%) —
   two windows differing by slightly more than one window differs from itself, inside
   the same noise band, which is what "the arms differ by animation phase and nothing
   else" looks like. The same-arm diffs have animation's shape too: 0 damaged columns,
   6–7 clusters.
2. **Fresh cross-arm inject pair:** 93.5% again (6.5% differ), verdict string again
   "SCALE (or something else)" — the 95% line sits inside animation noise, as predicted —
   and the locality analysis reproduces on the new pair: 0 of 640 columns damaged, max
   column fraction 0.30, 5 clusters.
3. **cnc-ddraw ws1:** FOLLOW again at client 800x480, and the right band below row 31 is
   **99.86% black in BOTH bracket captures** — the same 100 dim seam pixels — while the
   left 640 columns changed 10.9% between the same two captures. A repainting window
   whose band stays black is a PRESENTED black surface; unpainted leftover garbage was
   the alternative and it is excluded.
4. **Caption strip rows 0..30:** present in every cnc-ddraw capture (ws0 and ws1),
   absent from every WMode capture. The artifact is the helper's window style, §14.3.

One residual worth recording: cnc-ddraw's same-arm delta (10.9–11.8%) runs higher than
WMode's (5.7–6.4%) over the same menu. Not load-bearing for any claim above — both are
animation-shaped and column-undamaged — but a future probe that compares ACROSS helpers
should not expect their noise floors to match.

### 14.5 How to reproduce

```powershell
./tools/plugin/fetch-cnc-ddraw.ps1     # pinned v7.1.0.0 -> C:\sc-work\cnc-ddraw\ + hashes
./tools/plugin/run-offscreen.ps1 -Suite ./tools/plugin/probe-widescreen-present.ps1 `
  -SuiteArgs @{ Vector='both'; Stage='1'; BracketSeconds=4;
                WindowedHelperDll='C:\sc-work\cnc-ddraw\v7.1.0.0\ddraw.dll';
                FrameDir='C:\sc-work\logs\065-frames' }
.\.venv\Scripts\python.exe tools/plugin/analyze_present_frames.py   # the structural readings
```

Frames land in `C:\sc-work\logs\065-frames\` (gitignored, paths travel, never
`pr-image`d — hard rule 1). `StarCraft.exe` byte-identical throughout; the user's display
mode, desktop and registry untouched; everything behind `-WindowedHelperDll`, which no
suite passes by default.
