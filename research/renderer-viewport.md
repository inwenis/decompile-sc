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

## 15. Task 064 — stage 2 decomposed: the refresh band the sweeps could not see

§12.9 left stage 2 as "one atomic change of ~121 sites, and it is not currently correct",
with the damage attributed to the grid/terrain core and the stage declared structural. Task
064 re-opened it with 063's instrument and closed it the other way: **the stage was not
structurally broken, it was 56 sites short, all in the six functions that FILL the terrain
scratch surface** — a band none of the sweeps could see and no window capture could
attribute. With those declared, stage 2 composes a correct 800-wide playfield (§15.5).

### 15.1 The dead-end audit: which of 034's dead ends died of the instrument

The task's own first question, asked before any theory. 034's stage-2 record contains three
verdicts, and they fail for two different reasons that its instrument could not separate:

| 034's verdict | what it actually was |
| ------------- | -------------------- |
| "the scratch sweep found two real row steps, they applied, **the damage did not move**" (§12.9) | true, and correctly read as "a real defect that is not the defect" — the two sites were 2 of a 56-site deficit, so the frame stayed wrecked. Nothing here died of the instrument; it died of the enumeration. |
| "**stage 2 does not decompose**" (§12.9's bisect) | an enumeration gap wearing a structural costume. The missing sites sit inside the terrain group's own FEEDING path, so every coherent subset — including the whole stage — carried the defect, and no subset's damage could name it. The bisect was correct about everything it could observe; what it could not observe was that the terrain group itself was half-patched. |
| "every frame shows only the left 640 columns" (§12.10) | died of the instrument, and 063 already killed it: the window crop was WMode's, not the engine's. |

The transferable rule: **a bisect over a set can only indict members of the set.** When every
subset of a stage misbehaves, "the stage is atomic" and "the defect is outside the set" are
indistinguishable from inside the bisect — and the second one was true here.

### 15.2 The refresh band, and why every sweep missed it

The scratch surface (§6) has two sides. Its READERS — the blitter `FUN_004BCDC0`, the copy
loop, the full-playfield blit `FUN_0040C253` — and its low-level run-writers
(0x0040C3B0–0x0040C4C4) were in 034's table. Its FILLING side was not, except for the four
`imul ..., 0x2A0` multiplies the shape sweep happened to match. That side is six functions,
0x49B8D0..0x49C8xx, plus the per-megatile writer they all call:

| function | role (read from the code, this task) |
| -------- | ------------------------------------ |
| 0x0049B8D0 | clamp a refresh request to the cached window |
| 0x0049B9F0 | write ONE 32x32 megatile into scratch: 4x4 minitiles via 0x0040C3B0 |
| 0x0049BC20 | refresh an arbitrary tile rectangle (map-area invalidate, e.g. 0x0047D972) |
| 0x0049BD40 / 0x0049BE20 | refresh one tile COLUMN / one tile ROW |
| 0x0049BF20 | full-cache refresh: 14 rows x one row-refresh — the game-start fill, via the origin-change handler 0x0049C030 |
| 0x0049C0C0 / 0x0049C280 | the §7 steppers: scroll one tile, refresh the incoming column/row |
| 0x0049C780 → 0x0049C620 | per-frame tile updater, called from layer 5's own draw 0x004BD580 |
| 0x0049C4C0 | whole-map tile updater (creep): skips tiles inside the cached window |

The 56 sites it holds, by the encoding that hid each family:

| family | sites | what hides it |
| ------ | ----- | ------------- |
| mod-reduction chains: `lea r,[r − k·0x49800]`, k = 16,8,4,2,1 | 20 (4 functions × 5) | the constants are ×16/×8/×4/×2/×1 MULTIPLES of the wrap, encoded as NEGATIVE displacements — a sweep for `0x49800` matches neither the value nor the bytes |
| column wraps, same negative-lea shape | 2 | ditto |
| row steps in tile-row bytes: `+0x5400` (= 672·32) | 3 | carries neither 672 nor 0x49800 |
| last-row bound `0x44400` (= 672·416) and end-minus-a-column `0x497E0` (= 0x49800 − 32) | 3 | derived values |
| `−0x49800` as an AND mask or an ADD immediate (branchless conditional wrap) | 4 | two's-complement bytes `00 68 FB FF` |
| the per-megatile writer's UNROLLED displacements `[edi + 672k + d]`, k = 8,16,24, d = 0,8,16,24 | 12 | §12.8's fog-writer shape, in the producer: only k=1 would spell the pitch, and no k=1 exists |
| the cache extent in TILE units: `0x15` = 21 = 672/32 columns | 10 | a stride divided by the tile size; same class as §12.11's un-sweepable 40 |
| grid row 18, named absolutely + its `40·(row−17)` byte count in 0x0048CB80 | 2 | **found by 034's own scan and lost in transcription** — scan_refs counted 21 named grid references and "three name a row"; the table carried two. A different defect class from every row above: the information existed. |

(The matching 14-row constants — `0xE` = 448/32 — are untouched because the height does not
change at this geometry; the margin convention is pitch = playfield width + one 32px tile,
832 = 800 + 32 exactly as 672 = 640 + 32.)

- **How found**: `work/scratch/064/scan_064.py` — a value-FAMILY sweep of `.text` for the
  wrap's multiples in both signs, tile-row multiples, the unrolled `k·pitch + d` family and
  band-restricted tile-unit immediates, PLUS a `call rel32` scan that put a caller graph
  over the band; then every function in that graph read end to end. The two 0x0048CB80
  sites came from the byte-pattern check that there are exactly two copies of the
  `lea ecx,[eax+eax*4-0x55]; shl ecx,3` count shape in the binary.
- **How verified**: the generator relocates each declared value inside its instruction's own
  bytes and refuses the site on any mismatch (222 sites verified against the exe); the
  plugin re-verifies all of them in the live process before writing; and the outcome oracle
  is §15.5's frame, which no read-back touches.
- **What the sweep's "100.0% coverage" means, stated at its true strength**: the linear
  decoder resumed past every undecodable byte, so no BYTE of `.text` went unexamined — but
  padding and jump tables decode as junk instructions, so coverage does not mean every
  decoded instruction is real. Every hit was therefore read in its function before it was
  declared (one discarded: a `jne` whose branch TARGET spelled 0x498000). The residual
  failure class this method cannot see is a constant computed at runtime or split across
  instructions.

### 15.3 The mechanism of §12.9's wreck, arithmetic and all

The scratch cell of a tile is a linear hash of its absolute map position:
`off = (tileY·pitch + tileX)·32 mod size` — computed independently by every reader and
every writer. 034's table widened the multiplies (×672→×832) in four writers and the
modulus in none of them, so from the first fill of the first frame:

```
fixture camera origin (544,416) → tile (17,13)
patched multiply:   (13·832 + 17)·32 = 0x54A20
unpatched chain:    0x54A20 ≥ 0x49800 → reduces to 0xB220     (WRONG: 0x54A20 < 0x5B000)
patched blitter:    reads 0x54A20
```

Producer and consumer disagree on every cell whose pre-wrap offset exceeds the OLD size —
which at ×832 is most of the surface — so the blitter reads bytes nothing wrote this game:
§12.9's "large areas never drawn, 332 of 380 rows, 16–21 points blacker than the control",
mechanism attached. The megatile writer's stale unrolled displacements and the 21-vs-26
column extents scatter what IS written, which is the rest of the wreck. None of it is
observable through a window that crops to 640, and none of it is attributable from a bisect
whose every subset contains the half-patched feeding path.

### 15.4 Measured results (runs of 2026-08-13, off-screen, 36-marine fixture)

**Run 1b — the positive control, unchanged probe (stock + stage 1): PASS 21/21.**
Stock playfield consistency 0.98909 — identical to 063's run 3 on a different
build — s1 800x480 stable both scenes, right band 76800/76800 index 0, cross-arm
`wide_rows=0`. The instrument reads the same on a different day before it is
asked a new question.

**Run 2 — stock + stage 2, captured twice 4s apart. The headline: THERE IS MAP
PAST COLUMN 640.** The right band x=640..799 over playfield rows: **nonzero
fraction 0.8438, 52 distinct indices, byte-identical across the two captures (a
right-band-only diff between them: 0 differing pixels)**; window-vouched
consistency at pitch 800: **0.99296**. The fixture matters and is itself a
finding: with 063's single marine the right band is legitimately shroud-black,
so a correct and a broken stage 2 read identically — the 36-marine grid at 64px
spacing explores the terrain under the band, closing the vacuous-fail direction
before it could bite. Three FAILs in the run, every one decomposed offline to
the instrument or the fixture (each measured, none waved):

1. consistency 0.34164 on capture 1 — the checker's auto-alignment mislocked at
   (8,36); every other check locked the true (5,32), and capture 1's dump
   differs from the 0.99296 capture 2 by only 12172 px, all in sprite rows.
2. `wide_rows`=56 vs stock / 15 between captures — every flagged row differs in
   **17–101 px of its 640/800** (3–8%), far-apart blobs: idle-pose diffs on a
   337-px ROW of marines plus doodad phase. §12.9's real damage ran ~70% of the
   row. The span heuristic cannot separate a row OF sprites from a damaged row;
   the per-row COUNT can — hence `dense_rows`.
3. the same regions read `dense_rows=0`.

**`dense_rows` was seen RED before its green was trusted** (the 055 condition,
set by the conductor): offline, the real s2 dump re-sliced at stride 640 —
§12.9's exact damage class, judged through frame-capture.py itself — reads
**dense_rows=380 of 380** (diff_px=245816); and live, run 3's defect arm
(`SCPLUGIN_WS_ONLY=terrain`, incoherent by §12.5's coupling, writes bounded
because terrain.alloc is in the subset) reads **dense_rows=16, wide_rows=235**
against stock. Red on the synthetic, red on the pipeline, green on the fix.

**Run 3 — stock + defect arm + stage 2 with the camera moved between captures:
42/43.** Same-origin pair (two identical minimap clicks → origin (704,416)
twice): `dense_rows=0, wide_rows=0`, diff_px=9564. Cross-arm left 640 vs stock:
`dense_rows=0` (wide_rows=130, all sprite rows, widest row 122 px of 640).
Consistency pinned: 0.98900 / 0.99877. The one FAIL is the stock arm's UNPINNED
alignment check mislocking again — 0.33867 auto, **0.98477 re-run offline with
the pin on the same bracket captures** — after which the pin went into the
stock arm's check too.

**The seam, discriminated by the moving camera** (zeroruns per capture, origin
beside it, predictions §15.2 registered before the run):

| capture | origin | all-zero column runs (y=20..320) |
| ------- | ------ | -------------------------------- |
| ingame | (544,416) | 671–695 |
| mid | (576,416) | 671–695 |
| scrolled / scrolled2 | (704,416) | 628; 632–695 — identical twice |

**Verdict: P1, screen-anchored — in two parts, the LEAK first because it is the
gameplay defect and the bigger one:**

1. **screen px 696..799 (fog cells 87–99) never receive fog at all**: at origin
   (704,416) that region reads **100.0000% non-zero terrain over map the
   fixture provably never explored** (band 696..800 × 20..320: 31200/31200
   nonzero). The player sees terrain they have not explored — a quarter of the
   extra width. And it re-reads run 2: *"the right band holds MAP"* and *"the
   right band holds map the player is entitled to see"* are different claims —
   run 2 measured only the first, and part of its healthy-looking band was the
   fixture's explored area happening to cover that screen region.
2. **screen px 672..695 (fog cells 84–86) + the last px of cell 83 paint BLACK
   at every origin**, including over map that is certainly explored — the
   25-px seam.

(The extra black at origin (704,416), x=632..671, is consistent with legitimate
shroud at the fixture's sight boundary and is not claimed as defect.)

The suspect list the verdict selects: the fog band's CELL-unit constants — the
terrain cache's 0x15 pattern one subsystem over — `cmp/mov 0x51/0x50`
(81 = 648/8 ring cells, 80 = 640/8 visible cells) at 0x0047E4B0/0x0047E4C0/
0x0047E8D9/0x0047F820/0x0047F829, plus an unread sibling branch clamping to
0x68/0x67 (104/103) on the mode flag 0x58F440. Reading that subsystem properly
is bounded follow-up work of exactly this task's refresh-band kind; per the
task's own instruction the working playfield ships behind the flag with the
fog defect stated rather than withheld.

> **CORRECTED by task 068 — every entry on that suspect list is misidentified,
> and the defects live elsewhere.** Read §16.1 before following any of it:
> 0x0047E4B0/0x0047E4C0/0x0047E8D9 count TIPS DIALOG strings (80 original /
> 103 Brood War on the EXPANSION flag 0x58F440 — the 0x68/0x67 "sibling
> branch" is 103+1 tips, not the 104-px strip); 0x0047F820/0x0047F829 are
> string-format code; and the two "fog arms" 0x0047EBF0/0x0047EE20 draw the
> space-tileset parallax starfield (their fog.wrap patches remain correct —
> for stars). The real fog is the four-buffer cell pipeline in §16.2, and
> both defects here fall out of its one stride (§16.3). The values in THIS
> section's measurements are all still good; only the attribution was wrong.

Artifacts (gitignored diagnostic path; paths travel, images never):
`C:\sc-work\logs\063-frames\fd-{stock,s2}-*.bin`, `*-render.png`,
`fd-synthetic-stride640.bin`; transcripts
`C:\sc-work\logs\064-framecap-run{1b,2,3}.txt` and
`C:\sc-work\logs\offscreen\20260813-*-probe-framebuffer-capture.txt`.

### 15.5 What stage 2 still does not cover, stated so nobody over-reads

1. **The scroll clamp is still stock** (§9.1 item 12, stage 3): the camera's maximum is
   `(mapTileW − 20)·32`, so at the RIGHT map edge the playfield's last 5 tile columns read
   scratch cells the refresh never fills (the cache clamps to the map, 0x0049BEBB). The
   fixture keeps the camera interior; a player scrolling to the right edge will see stale
   right-band columns until stage 3 moves the clamp (20 → 25 tiles, plus the ±equivalents
   for mouse→world 0x0046FB40, the window-procedure clamps, and the minimap 20/13).
2. **The minimap knows nothing of any of this** (items 17, 18 — stage 5; the viewport
   rectangle is still not even located, §10 item 1).
3. **The console-right dead strip** (160×80 at the bottom right) is blank by design — no
   art exists for it and hard rule 1 forbids shipping any (§9.1 item 19, user's call).

### 15.6 How to reproduce

```powershell
python tools/renderer_patch_sites.py --check      # 222 sites verify against the exe
./tools/plugin/run-offscreen.ps1 -Suite ./tools/plugin/probe-framebuffer-capture.ps1
#   unchanged: stock positive control + stage 1 (063's numbers, re-owned)
./tools/plugin/run-offscreen.ps1 -Suite ./tools/plugin/probe-framebuffer-capture.ps1 `
    -SuiteArgs @{ Stage2 = $true }
#   stock + stage 2, the stage-2 arm captured twice; asserts the WIDESCREEN
#   ACTIVE line (a refused table would run stock and pass vacuously), the
#   window-vouched pitch-800 consistency, the right band holding map, the
#   cross-arm left-640 identity, and no drift between the two captures
```

## 16. Task 068 — the fog cell pipeline: both 15.4 defects are one number

§15.4 left two measured fog defects (the 25-px black seam at 672..695, the
104-px always-lit strip at 696..799) and a suspect list. Task 068 read the
subsystem instead of patching the suspects, and every entry on that list died
of the reading — the defects live somewhere none of them pointed.

### 16.1 The suspect list audited: all of it was numerology

Every claim below is from disassembly of the on-disk exe (byte-verified
addresses; `work/scratch/064/scdis.py`).

1. **The "fog update cursor" `[0x6CDFE8]` is the TIPS DIALOG's string cursor.**
   `0x47E480` — the function holding the suspect constants `0x51`/`0x50` at
   `0x47E4B0`/`0x47E4C0` — walks a dialog child list (control id −10), indexes a
   count-prefixed u16 offset table through `[0x658ADC]`, measures the resulting
   STRING against the font height `[0x6CE111]`, and sets control flags
   0x800/0x400 ("text fits / scrolls"). The wrap `[1..0x50]` vs `[1..0x67]` on
   flag `[0x58F440]` is **80 tips in original StarCraft, 103 in Brood War** —
   `[0x58F440]` is the expansion flag, which is why it has ~80 references
   across the whole UI band (residue 2's warning, answered). The `0x47E8A0`
   band and its u16 table `0x513BA0` are the same dialog's init path.
2. **The `0x68 = 104` lead (residue 6) dies with it**: 0x68 is 103 Brood War
   tips + 1, not the 104-px strip. The project's own rule — two numbers
   agreeing is where a hypothesis starts, not evidence — held for the third
   time in two days.
3. **`0x47F820`/`0x47F829` (`cmp esi,0x50` / `push 0x50`) sit in string-format
   code** (offset-table string lookup + sprintf at `0x41F1B0` around
   `0x47F84B`), not fog.
4. **The two "fog arms" `0x47EBF0` (scrolled) / `0x47EE20` (static) draw the
   SPACE-TILESET PARALLAX STARFIELD, not fog.** They render item lists at
   `[0x658AA8]` — five layers, per-layer parallax scroll factors from
   `[0x62846C-4k]`/`[0x628484-4k]` (>>8 fixed point), items of
   `{x:u16, y:u16, data*}` in a 648×488 ring — and the whole block is gated on
   `word [0x57F1DC] == 1`, the space-platform tileset id. The item positions
   are PARSED FROM A FILE (`0x47F390`: count table + pointer fixups into a
   loaded blob — star.spk). Consequence for 064's six `fog.wrap` patches
   (648→808): still correct and still needed — stars must cover the wider
   ring — but the FILE's positions only span x < 648, so **space-tileset maps
   show a star-free band at x ≥ 648 until somebody synthesizes items**.
   Cosmetic, off-map backdrop only, deliberately not fixed here.

The transferable rule: §15.4's suspect list was assembled from a VALUE sweep
(81 = 648/8, 80 = 640/8). Every hit was real arithmetic on those values — in
three unrelated subsystems that happen to count to 80. A value family names
candidates; only the function around the hit names the subsystem.

### 16.2 The real fog: a four-buffer pipeline, all heap, terrain-cache geometry

Per frame, orchestrated by layer 5's own draw `0x4BD580` (read end to end,
as were all functions below):

| step | function | reads → writes |
| ---- | -------- | -------------- |
| fill | `0x47FC50` | map-tile visibility dwords `[0x6D1260]` (map-sized), from tile origin `[0x57F1D0/D2]`−1 → raw tile map `[0x6D5C14]`: 24 cols × 17 rows of {0, 15, 31} (hidden / explored / visible), row stride 24 |
| smooth | same fn, `0x47FD90` | 3×3 kernel over the raw map → smoothed map `[0x6D5C0C]`, interior 22 cols × 15 rows (the fill's border feeds the kernel) |
| change | `0x4804D0` | smoothed vs previous frame `[0x6D5C10]`, compared in screen space over 22 tiles × 32 px = 704 px (`0x2C0`) × 480 px; per differing run → dirty rects via the marker `0x41E0D0`; the full-redraw path instead memcpys smoothed→prev (`0x66` dwords, two call sites `0x4805E3`/`0x4BD5A8`) |
| interpolate | `0x47FE10` | 21 cols × 14 tile rows of the smoothed map, bilinear 4×4 sub-cells per tile through the 32×32 LUT `[0x657AA0]` (built by `0x480430`, value-space only) → the 8-px CELL buffer `[0x6D5C18]`, one dword = 4 cells, cell stride `0x58` = 88 |
| render | `0x4805F0` (from the dirty walk `0x4808F8` / full draw `0x4808E0`) | per 8×8 block reads a 2×2 cell neighborhood (`[esi−0x58]`, `[esi−0x57]`, `[esi]`, `[esi+1]`); all-equal 0 → the §12.8 black writer `0x4800A0`, all-equal 0x1F → nothing, all-equal other → uniform blend `0x480000`, else gradient `0x47FF10` |

All four buffers are allocated at GAME START by `0x480960` (called from the
layer-5 init `0x4BDA83`): three tile maps of 408 bytes (24 × 17) and the cell
buffer of 5280 bytes (88 × 60), freed by `0x480380` at game end. **Nothing here
needs relocation** — unlike the dirty grid, the buffers are heap blocks whose
sizes are `push` immediates in one init function; patch the immediates before a
game loads and the engine builds the wider buffers itself.

The geometry is the terrain cache's, one subsystem over, exactly as 064's
residue 1 predicted (against different globals than it named): covering band
21 tiles × 14 (= §7's 20+1 / §6's 448/32), tile-map stride 24 = covering + 1
smoothing border each side + 1, cell stride 88 = 21·4 + 4 pad, cell rows
60 = 14·4 + 4.

- **How found**: named-ref byte scan for the buffer globals
  (`work/scratch/068/scan_refs68.py` — every x86-32 absolute ref encodes the
  address as a plain dword, so the scan is exhaustive for NAMED refs, §5's
  method) — 5/8/6/5 refs for `0x6D5C18/0C/10/14`, every one read in its
  function; plus a stride-family sweep (88·k both signs, 100.0% byte
  coverage) whose in-band hits are all accounted for above.
- **How verified**: the generator relocates each declared value inside its own
  instruction bytes and refuses on mismatch (§16.3's 39 sites verify against
  the exe); the outcome oracle is §16.4's frames.

### 16.3 Why the two defects are one number, and the fix

The cell buffer holds `21·4 = 84` used columns (cells for screen x up to
671 at a tile-aligned origin). Stage 2's (already correct) dirty walk asks the
renderer for x up to 799, so the cell index — `((originX>>3)&3) + (x>>3)` —
runs to 99..102:

- indices 84..86 land in the row's zero PADDING (stride 88) → uniform 0 →
  the black writer: **the 25-px seam at 672..695, at every origin, screen-
  anchored** — §15.4 defect 2, including the gradient clipping the last px
  of cell 83;
- index 87 straddles pad and the wrap below → gradient, not black — which is
  why the seam measures 3 cells wide, not 4;
- indices ≥ 88 wrap into the NEXT cell row's LEFT columns — cells for the
  left of the screen one 8-px row down, which the fixture had explored
  (value 0x1F = fully visible = draw nothing) → **raw terrain over
  unexplored map at 696.., §15.4 defect 1**. "The boundary at 87 cells is
  derived, not a constant" (residue 3) — it is stride 88 wearing the walk's
  clip: 84 used cells, 3 all-zero pad cells, one straddling block, then the
  wrap.

Fix (`tools/renderer_patch_sites.py`, family `fogcell.*`, stage 2, 39 sites):
widen the covering band 21→26 tiles (the terrain cache's own 26), which
derives everything else — tile maps 29 cols stride (smoothed interior 27,
compare span 27·32 = 864 px), cell stride 108 = 26·4+4, allocations
408→496 / 5280→6480. Keeping the engine's own invariant "stride = fill
count" keeps the three structural pads (+2, +2, +3) invariant, so they are
not sites at all. Every site is a same-length immediate or disp8 rewrite
(the kernel's ±0x17/0x18/0x19 displacements become ±0x1C/0x1D/0x1E, the
renderer's −0x58/−0x57 become −0x6C/−0x6B); no EFLAGS hazards (no lea→imul
class anywhere). Row-side counts (14/15/17 rows, the 480-px vertical span,
60 cell rows) are declared as parametric sites that are no-ops at height 480.

### 16.4 Measured results (runs of 2026-08-13, off-screen, 36-marine fixture)

Predictions were registered before the first patched run (065's rule); each
is scored below, misses included.

**Run 1** (`C:\sc-work\logs\068-framecap-run1.txt`) — stock + defect + s2
with scroll captures, 46/47, the one FAIL being the most informative reading
of the run:

1. *Predicted:* ingame (544,416) loses the 671..695 zero-column runs, and
   the right band's nonzero fraction drops from §15.4-run-2's 0.8438.
   *Measured:* **seam GONE** — zeroruns `788; 792-799`, nothing
   screen-anchored — and the fraction **ROSE to 0.9251** (52 indices). The
   direction call was WRONG: the pre-fix number had the 24-px black seam
   subtracting more than the leak added, and the fixture's explored region
   reaches further right than the sight estimate behind the prediction
   (measured explored edge: map x 1332). The substantive half (seam gone,
   screen-anchored structure gone) holds; the fraction guess is recorded as
   the miss it was.
2. *Predicted:* scrolled2 (704,416) flips x=696..799 from 100.0000% nonzero
   to ~100% zero. *Measured:* **the whole band x=640..799 reads 100.0000%
   index 0** (48000/48000) over map the fixture provably never explored —
   the same origin, fixture and region §15.4 measured at 100.0000% NONZERO
   pre-fix. As clean as a before/after gets. This is also the run's one
   FAIL: 064's "band holds MAP (>= 0.30)" assertion — written while the
   leak was live — could only ever be satisfied AT THIS ORIGIN by the leak
   itself. The oracle encoded the defect as its expectation (AGENTS.md,
   2026-08-13); it is now origin-dependent (`>= 0.30` at the start origin,
   `<= 0.02` at the scrolled one), with these readings cited beside it.
3. *Predicted:* cross-arm left 640 vs stock keeps dense_rows=0.
   *Measured:* dense_rows=0 (wide_rows=120, all sprite rows, diff 6.5%).
   Same-origin pair dense_rows=0, wide_rows=0. Defect arm
   (`SCPLUGIN_WS_ONLY=terrain`): **dense_rows=42 RED** — the oracle still
   fails on real damage in the same run it passes the fix.
4. *Predicted:* zero-runs move with the origin, none screen-anchored.
   *Measured:* at origins 544/576/704 the runs sit at screen x 788/756/628
   — **all three are map x 1332**, the exploration boundary, with the same
   stray-column + 3-px-gap edge shape at each. **This resolves 064's
   residue-5 mystery**: the "628 stray, 4 px left of the band at origin
   704" was the map-anchored explored edge all along, not fog structure —
   it moved with the camera the moment more origins existed to compare.
5. *Predicted:* stock arm unchanged. *Measured:* all stock checks green,
   consistency 0.98952 (the §15.4 family of values), s2 window-vouched
   pitch-800 consistency 0.98727/0.99733.

The scrollmid capture moved the camera (posted VK reaches the engine's
scroll — measured rate >= 850 px/s, 420 ms ran 704 px into the left clamp)
but landed tile-aligned at origin (0,416), so the sub-tile alignment terms
were not exercised by run 1; the probe now holds VK_RIGHT for 100 ms. The
overshoot bought one thing free: map-LEFT-edge fog at 800 is correct
(zeroruns `0-15; 32-358`, both map-anchored).

**Run 2** (`C:\sc-work\logs\068-framecap-run2.txt`) — same probe, oracles
repaired per the above, scrollmid at 100 ms: **48/48 PASS**, stock positive
control and the defect arm's RED (`dense_rows=59`) in the same run as the
fix's green (`dense_rows=0` cross-arm, `0/0` same-origin).

- The scrollmid capture stopped at **origin (848,416) — x%32 = 16, sub-tile**
  (the 100 ms hold moved 144 px; the scroll runs ~1440 px/s here). The
  alignment terms `((originX>>3)&3)` / `&0x1F` are exercised at 800 for the
  first time, and the reading is clean: zeroruns `484-484; 488-799`, i.e.
  **848+484 = map x 1332 again** — the same map-anchored exploration
  boundary as at every tile-aligned origin, stray-plus-3-px-gap edge shape
  included. Fog is continuous to x=799 off the tile grid.
- Both new oracles green on the fix and proved able to fail: the seam tooth
  (`no zero run intersects 660..700` — fails 671-695 on the pre-fix build,
  §15.4 run 3) and the origin-dependent band (`0.9251 >= 0.30` explored /
  `0.0000 <= 0.02` unexplored — the latter fails at 1.0000 on the pre-fix
  build, §15.4's leak measurement).
- Window-vouched consistency at pitch 800: 0.99277 (ingame) / 0.99679
  (scrolled2); stock arm 0.99196.

Artifacts (gitignored diagnostic path; paths travel, images never):
dumps + renders `C:\sc-work\logs\063-frames\fd-s2-*.bin`,
`s2-ingame-render.png` (800-wide, fog boundary continuous, no seam),
`s2-scrolled2-render.png` (unexplored right band correctly black);
transcripts `C:\sc-work\logs\068-framecap-run{1,2}.txt`,
`C:\sc-work\logs\offscreen\20260813-{153254,154014}-probe-framebuffer-capture.txt`.

One operational residue, not this task's to fix: `sc-launch.lock` leaked
after BOTH runs (exit 1 and exit 0) with `Exit-ScLaunchLock: released`
printed — cleared each time against a verified-dead owner pid; three data
points in one day with 066's — issue #103.

### 16.5 How to reproduce

```powershell
python tools/renderer_patch_sites.py --check      # 261 sites verify against the exe
./tools/plugin/run-offscreen.ps1 -Suite ./tools/plugin/probe-framebuffer-capture.ps1 `
    -SuiteArgs @{ Stage2 = $true }
#   as 15.6, plus: a held-arrow-key ScrollMid capture (non-tile-aligned
#   origin -- the fog alignment terms (origin>>3)&3 / &0x1F are exercised by
#   no minimap origin, they are all multiples of 32), asserted moved, its
#   x%32 printed beside the seam tracker
```

## 17. Task 070 — the assembly driven, not captured: what a wide GAME does, and the one path that failed honestly

Tasks 032-068 each proved one piece frozen. Task 070 assembled them — stage 2 +
fog (in-process, `renderer_patch_sites.py`) presented through cnc-ddraw — and
drove a real game for minutes (`tools/plugin/probe-widescreen-drive.ps1`, both
presenters, 36-marine fixture, off-screen). Positive control first: the
unchanged 16.5 probe on the assembled HEAD reproduced 068's run-2 numbers
EXACTLY (band 0.9251 explored / 0.0000 unexplored, seam zeroruns `788;792-799`,
scrollmid (848,416) x%32=16, defect arm RED dense_rows=24, WIDESCREEN ACTIVE
244/0 refused).

### 17.1 What the driven session proved (51 green steps, wmode arm; 50, cnc arm)

1. **The presentation joint holds in game**: through cnc-ddraw the in-game
   client is 800x480 (FOLLOW, `GetClientRect`), dumps read 800x480 stable at
   every camera stop, and the window PNGs beside them show the composed wide
   frame the user would see.
2. **Fog stays correct while DRIVEN**: the seam tooth held at every origin the
   session visited (minimap jumps, held-key scrolls, the map edge and back);
   the sub-tile alignment terms were exercised at x%32=16 again. A rider,
   measured 5/5 stops across two runs plus 16.4's: **the keyboard stepper
   lands only on 16px multiples**, so x%32∈{0,16} is all a held arrow can
   reach — an oracle demanding two distinct nonzero phases is unsatisfiable.
3. **The minimap works at 800 and sits where it always sat**: engine dialog
   rects in game — `Minimap` (0,315)-(137,479), command card `StatBtn`
   (496,354)-(639,479), resource bar `StatRes` (220,0)-(639,19). The WHOLE
   console is anchored to the 640 frame; nothing extends past x=639, and
   nothing overlaps the new map columns. Minimap click-to-centre steers the
   camera at 800 (re-proven driven, both presenters).
4. **The console-right dead strip (640..799 x 400..479) is pure black and
   BYTE-STABLE**: nonzero_frac 0.0000, distinct=1 at every sample across the
   session, first-vs-last diff_px=0 of 12800. A footnote, not a flicker.
5. **The right MAP edge, measured**: the camera clamps at the stock 20-tile
   stop; the off-map right band there read 2.28% nonzero (stale cells, 15.5
   item 1) — visible only while parked at the very edge.
6. **Stability**: 3+ minutes of continuous driving per arm, WORLD scans
   complete throughout, the frame still 800x480 with the seam tooth green at
   the end.

### 17.2 The honest failure: playfield MOUSE input past x=640 is not proven on any path

- **Under cnc-ddraw (the shipping presenter), posted playfield clicks never
  reach a selection** — 0/8 across three mechanisms tried (activation nudge
  on, off, cnc-ddraw `devmode=true`) — while the menus (nudged), the minimap
  and the keyboard all work. Posted input into an invisible-desktop cnc-ddraw
  window is a HARNESS limit (see AGENTS.md "Glue-screen input is
  ACTIVATION-GATED"): a real player's real mouse takes the normal foreground
  path this harness cannot exercise off-screen.
- **Under WMode, clicks below 640 select exactly the aimed unit; clicks past
  640 select the WRONG one**: at origin (320,448), static through the whole
  exchange, a click posted at screen (704,272) selected the marine at screen
  (576,272) — map positions from the WORLD scan, cross-referenced by CUnit
  pointer — and a click at 768 landed ~640 (a repeat selected 12, the
  double-click-same-spot artifact). Effective x ≈ posted x − 128±16, only
  past 640; a seam-spanning drag box collapsed to 1 of 12 units. BUT a real
  mouse cannot reach x>640 in WMode's 640 window, so posted coordinates there
  are out of the shim's contract: this measurement proves NOT-PROVEN, it does
  not name the owner (engine window-proc clamp / mouse→world 0x0046FB40 —
  9.1 item 12's untouched sites — vs WMode's own transform).
- **Consequence**: the wide build is VIEW-complete and INPUT-unverified past
  column 640. Reading the engine's wndproc mouse path and 0x0046FB40 at 800
  is its own bounded task, the 9.1-item-12 shape; the first real play (real
  mouse, real desktop, cnc-ddraw) is the cheapest decisive measurement and
  is the user's to trigger.

### 17.3 How to reproduce

```powershell
./tools/plugin/run-offscreen.ps1 -Suite ./tools/plugin/probe-widescreen-drive.ps1
#   the assembled cnc-ddraw arm: menu walk (activation-nudged), HUD read-back,
#   minimap steering, sub-tile scrolls, dead-strip watch, 3-min stability
./tools/plugin/run-offscreen.ps1 -Suite ./tools/plugin/probe-widescreen-drive.ps1 `
    -SuiteArgs @{ Presenter = 'wmode' }
#   the engine-input arm: same session; the click/box/command steps carry the
#   17.2 readings (posted coords reach the engine there)
./tools/deploy.ps1 -DeployRoot C:\sc-deploy\scratch-task070 -NoShortcut
#   the one-action switch, proven against a scratch root: stages pinned
#   cnc-ddraw, writes Launch-StarCraft-Modded-Wide.ps1 + widescreen-card.md
```

Artifacts (gitignored diagnostic path; paths travel, images never):
`C:\sc-work\logs\070-frames\drive-*.png` / `fd-drive-*.bin`, transcripts
`C:\sc-work\logs\offscreen\20260813-*-probe-widescreen-drive.txt`.


## 18. Task 071 — input reaches the full width; the console move is a measured NO-GO

§15.5.3's dead strip and 070's HUD verdict ("a 640 console sitting in the left
of a wide window": `StatRes` (220,0)-(639,19), `StatBtn` (496,354)-(639,479),
both ending at x=639) were the target. Task 071 shipped the HALF that works —
input can now reach x=640..799 — and MEASURED that the other half, moving the
console into that region, cannot be done by relocating dialog geometry. Both
results are below; the console move is a follow-up.

### 18.1 Shipped: the window-proc mouse clamps (stage 3)

The window procedure clamps every mouse x to the stock screen before building
an input event or writing the cursor globals (§8's last row), so at 800 wide a
real or posted x past 639 was pinned to 639 and the right 160 columns were
unclickable. The clamps are four `cmp 640` / `mov 639` PAIRS, read from the
base exe (task 071):

| function | the decision | the replacement value |
|---|---|---|
| 0x004D1940 | 0x004D1960 `cmp si,0x280`  | 0x004D196D `mov ax,0x27F` |
| 0x004D19C0 | 0x004D19EC `cmp si,0x280`  | 0x004D19F9 `mov ax,0x27F` |
| 0x004D1A50 | 0x004D1A7C `cmp si,0x280`  | 0x004D1A89 `mov ax,0x27F` |
| 0x004D1D70 | 0x004D24E6 `cmp ax,0x280`  | 0x004D24EC `mov dword [0x6CDDC4],0x27F` |

The shape is `if (x >= 640) x = 639`. The 032 sweep's distillation
(`renderer-viewport-sites.tsv` rows 74-81) lists only the `mov` sites, because
639 was the swept value — **patching those alone turns "click at 700" into
"click at 799"** (the compare still fires and installs the widened constant).
Stage 3 moves all eight X sites together (`mouse.clamp.*` in the generated
table); the four Y clamps stay, the height is unchanged.

The clamps are **necessary but not sufficient**, and a clean test is what
showed it: the mouse→world click SEARCH RECT (0x0046FB40, §9.1 item 12) is also
640 wide — `add eax, 0x280` for `right = screenLeft + 640` at 0x0046FC75 (click
arm) and 0x0046FE18 (drag-box arm) — so even with the cursor global carrying
x>639, a click whose world point lands past `screenLeft + 640` falls OUTSIDE the
rect and selects nothing. Stage 3 widens those two extents to `screenLeft + 800`
as well (`click.searchrect.*`), for 10 stage-3 sites total. The +400 height
extents beside them stay.

**Verified, and the behavioural half honestly NOT verified
(`test-widescreen-input-800.ps1`, off-screen WMode, one-Nexus fixture):** all 10
stage-3 sites are present with the right constants, the console stays at its
stock 640 rect, and at 640 (flag off) selection at x<640 is unbroken. But
**whether a click past x=639 SELECTS is not provable in this harness** — and it
is the same wall 070 hit for its own item 1. A posted playfield click past x=639
does not reach the engine: under WMode the window is 640 wide and posted
coordinates past it are out of the shim's contract (070 §17.2, verbatim); under
cnc-ddraw off-screen no posted playfield click registers at all (070 measured
0/8). So the suite REPORTS x>639 selection (measured `no-select` off-screen) and
does not assert it; the behavioural proof is a real mouse on a real desktop, the
user's first play — **exactly the deferral 070 recorded**, not a closed item.

A caution paid for here, worth its own note: an earlier run reported "click at
672 selects" and it was a CONTAMINATED oracle — the Nexus was already selected
from a prior step, so `ptype` stayed 154 whether or not the click did anything
(the 023/026 shape: the read did not depend on the act). The clean test
deselects first; then it reads `no-select`. **A select-state read is only an
oracle for a select if the target was provably deselected before the click.**

070's §17.2 found the same wall from the world side and named these same sites
(9.1 item 12: the wndproc mouse path, mouse→world 0x0046FB40); this task
supplied their concrete owners (the 10 byte-patches) and confirmed the harness
cannot behaviourally test them. 070's "128 px offset" was the
nearest-unit-in-fixture artefact of clamp-to-639, not a second offset.

#### 18.1.1 What else consumes the widened coordinate range — full-coverage sweep

A resuming `cmp`-immediate sweep of the whole `.text` (100.0% coverage —
1036039 of 1036288 bytes decoded; the §12.4 Capstone-halt lesson applied) for
compares against 638/639/640 finds, beyond the four pairs and the geometry
sites:

- **0x004D12FF `cmp eax,0x27E / jl`** — the edge-scroll trigger (scroll right
  when `x >= 638`). **This paragraph was WRONG and is corrected here (2026-09-05,
  issue #113 follow-up).** It read "IDENTICAL before and after the clamp patch
  (today every physical x >= 638 already reads as 639 >= 638), so it is left
  alone." That reasoning holds only if x is still pinned to 639 — but the clamp
  and this trigger ship in the SAME stage 3, so once the clamp is lifted the
  cursor reaches x = 638..799 and the ENTIRE widened band fires the scroll: the
  camera slides the instant the cursor crosses 638, and the right ~160px cannot
  be rested on or clicked. That is the user's *"I see more on screen, can't move
  my mouse there, it starts moving screen as if the viewport is still smaller."*
  It was not detectable in the harness — no test feeds a real-desktop mouse into
  the right band (the standing 070/071 limit), the same blind spot as the crash
  below. The trigger now moves with the clamp: `638 -> screenW-2` (the stock 2px
  right margin, carried to the new width), `scroll.right.trigger` in the
  generated table, and `test-widescreen-input-800.ps1` asserts the moved bytes.
  "Moving it would CHANGE behaviour the user has" was true and was the point —
  the behaviour it had was the bug.
- **0x004F7C94, 0x004F9376, 0x004F942E, 0x004F943F, 0x004F9498** — `cmp ..,0x27F`
  beside `fnstcw`/`fldcw`: the x87 FPU CONTROL WORD's default value (0x27F). CRT
  float code, not coordinates (the §16.1 trap: a value match names a candidate,
  the function around it names the subsystem).
- **0x004DCDE2 `cmp word [edi+4],0x280`** — the glue-screen dialog SLIDE
  animation. Glue transitions only; untouched.

#### 18.1.2 The relocated dirty grid faults on an off-edge dialog rect (2026-09-05, issue #113 crash)

The user's wide session died with `The instruction at 0x0041DE84 referenced
memory at 0x026DFFFF. The memory could not be read.` The session's own log names
the grid: `dirty grid relocated 0x006CEFF8 -> 026E0000`, so the faulting address
is exactly **`grid_base − 1`**.

`0x0041DE84 mov dl,[ebx]` is the read loop of `0x0041DE20` (the "is this rect's
region dirty" test, the `grid.stride.testrect` patch group). Its start pointer is
`ebx = grid + col + row*stride`, `col = x1>>4` **signed** — and unlike the mark
path `0x0041E0D0`, which clamps `if (x1 < 0) x1 = 0` (§5), the test path does
**not** clamp. Its three callers (`0x0041C7EE`, `0x0041E1C1`, `0x0041E37B`) walk
the dialog list and pass each control's bounds with `movsx`, so a control sitting
a pixel or two off the left edge yields `col = −1`, and the loop reads `grid − 1`.

Stock never faulted here because the grid was a `.data` array boxed by live
globals on both sides (§5): `grid − 1` read a neighbouring mapped byte, garbage
but harmless (it only gates a redraw). Relocating the grid to a bare
`VirtualAlloc` page (task 034) put an **unmapped guard page** immediately before
it, turning that harmless neighbour read into an access violation. The bug had
been latent since the first stage-1 relocation; it needed a dialog composed with
an off-edge rect to fire, and the widened play surface is where the user finally
hit one.

Fix (`sc_screen.cpp`, `SC_WS_GRID_GUARD`): commit `0x10000` bytes on each side of
the grid and point the patches at the middle, re-creating stock's "boxed in"
padding, so a small out-of-range index reads zeroed scratch (= "not dirty") just
as stock read a harmless neighbour. It is a one-allocation change with no new
byte patch, and it covers **every** unclamped grid consumer at once rather than
clamping them one at a time. Install logs `grid guard OK` with a `VirtualQuery`
of both guard edges as the oracle (it prints `MISSING` and refuses on the
pre-fix bare allocation), and `test-widescreen-input-800.ps1` asserts the line.

### 18.2 NO-GO: moving the console by relocating dialog bounds moves the HIT-TEST, not the PIXELS

The plan was to translate the `StatRes` and `StatBtn` root dialog bounds
(+0x04) by +160. A prototype did exactly that and the **engine's own dialog
list confirmed the move**: `StatRes` read (380,0)-(799,19), `StatBtn`
(656,354)-(799,479). Every memory oracle agreed the console had moved.

**The picture did not.** Captured through cnc-ddraw at 800 (070's presentation
vector + `%SCDRIVE_POST_ACTIVATE%`; `C:\sc-work\logs\071-frames\console-800-*.png`),
the console still reads as a 640 console with a black strip on the right: the
bronze frame, the command-card panel, the MENU button and the minimap all sit
in the left ~640, x=640..799 at the bottom is black, and the resource number
sits at its STOCK position (~x600), not the far right a moved (380..799) bar
would put it. Cross-checked against 070's stage-2 frame
(`070-frames/drive-ingame-after.png`): both show the console left-anchored, same
resource band. **The bounds moved; the pixels did not.**

Why: the console dialogs' ON-SCREEN pixels come from fixed draw positions — the
640-wide console art (`console.pcx`, §9.1 item 19 / §15.5.3) and each status
dialog's own draw constants — NOT from the `BinDlg` bounds. The bounds govern
the HIT-TEST region only (0x00418340 subtracts root+0x04). This is what §9.1
items 19/20 anticipated ("a bottom-anchored stock HUD means moving loaded
dialog geometry" AND "the console art is a fixed-width image; at 800 there is no
console art for the extra 160 px") — moving the geometry is necessary and not
sufficient, and the art half is the fixed-width game-content wall the user
already ruled on (black, §15.5.3). Moving a fixed-width console to the edge just
RELOCATES the black gap (right → left); it cannot be done without new art, which
hard rule 1 forbids shipping.

> **CORRECTED by task 073 (§19), with a capture on each side.** The
> "fixed draw positions" mechanism above is wrong: the layer-2 composite blits
> every dialog surface to the screen at its LIVE `+0x04` bounds, per dirty rect
> (§19.1, read instruction by instruction). What 071's picture actually showed
> is that **no repaint of the affected rects could ever be MARKED**: the one
> function that adds a dialog rect to the layer-2 dirty region clamps it
> against a `.data` clip box `{0,0,640,480}` with no writer anywhere in the
> binary (§19.3). One dword widened plus the same bounds move puts the COMMAND
> CARD at the right edge — measured, with the art travelling in the dialog's
> own surface (§19.2), so no art ships. The resource bar composites at its new
> position too but rides the buffer PRESENT, which has a second, storm-side
> 640 (§19.8) — so the observation above (the bounds moved, the picture did
> not) was correct twice over; only the mechanism inferred from it was not.

**The oracle lesson, stated generally because it cost a merge-ready result:**
the engine dialog list is the right oracle for *hit-test* position, and it was
used — in good faith, with the geometry confirmed — to support a *visual*
claim. It was necessary and not sufficient. This is the frame-vs-memory rule of
tasks 023/033 inverted: there, a pixel hash answered a question memory should
have; here, a memory read answered a question only pixels could. **An oracle can
be correct, authoritative, and about a different question than the one you are
answering.** The picture — the standing "UI ships as a picture" rule — is what
settled it before merge rather than after.

### 18.3 NO-GO, the second half: even a console that DREW at the edge could not be clicked there

Separately measured on the prototype (before the pixel finding), and it folds
into the same follow-up: a click on the MOVED card at x>639 produced nothing on
the wire, while the HOTKEY trained normally and x<640 clicks reached the console
dialogs. An interact trace (every root dialog's `+0x2A` wrapped and named)
showed the card's own interact (`StatBtn` root 0x00459B00) **never invoked for
any x>639 click**; the event-type handler table (0x006D5E40) is all-null so the
generic dispatcher 0x00419FD0 is not short-circuiting; the card's own handling
is sound (generic interact 0x00418EB0 → hit test 0x00418340, both reading LIVE
bounds). So the drop is UPSTREAM of the card, in a stock console-input router
that offers nothing at x≥640 because it was written when the console was 640
wide — one layer up from the wndproc clamps §18.1 moved, same shape.

So the console move needs BOTH: the pixels relocated (the composite / art path,
§18.2) AND the console click-router widened (§18.3). A console that draws at the
edge but cannot be clicked, or one that can be clicked but does not draw, is
half a feature either way — which is why they are one follow-up task, not two,
and why the console move was dropped from what shipped. The trace instrument and
the click probe that produced §18.3 live in git history (task071 branch,
pre-split commits) as that task's starting tools.

> **RESOLVED by task 073 (§19.4): no stock router refuses x>=640 — the moved
> card claims its own clicks.** Under cnc-ddraw, whose window really is 800
> wide, the moved card's interact claims a Train click at (682,374) and
> returns 1, the wire carries 0x1F, and the building's ring fills — clean
> slate first (§19.4, one run, rebuilt trace). What §18.3's runs measured is
> therefore not an engine router. The likeliest cause — stated as hypothesis,
> not measurement — is the same WMode posted-input contract §18.1 names for
> the playfield (a posted x>639 under a 640-wide shim window), which produces
> exactly this trace: no interact invoked, hotkey fine. Nobody has re-run
> §18.3's arm to confirm that attribution, and with the engine measured clean
> under an honest presenter, nothing depends on it.

### 18.4 How to reproduce

```powershell
python tools/renderer_patch_sites.py --check      # 269 sites verify against the exe
./tools/plugin/run-offscreen.ps1 -Suite ./tools/plugin/test-widescreen-input-800.ps1
#   stock arm (640 unchanged + baseline select) then the stage-3 arm:
#   table ACTIVE + 8 clamp sites, the console STILL at its stock 640 rect,
#   a click past x=639 selecting the aimed unit, a seam-crossing drag,
#   minimap steering
./tools/plugin/test-production-queue.ps1 -Widescreen 1 -WidescreenStage 3
#   the production-queue suite on the input-widened build (console at stock 640)
```

The NO-GO capture (§18.2) is 070's vector at stage 3 with the move prototype
(git history); the picture is `C:\sc-work\logs\071-frames\console-800-*.png`
(gitignored; paths travel, images never).

## 19. Task 073 — the console moves after all: the composite follows live bounds, and one .data clip box was the wall

§18 briefed this task with two blockers. Both dissolve into named causes — and a
third wall, older and structural, comes out from under them. The COMMAND CARD
half is proven end to end: its pixels were stopped by a four-dword `.data` clip
box nobody had found (§19.3), the click drop was never in the engine (§19.4),
and with the box widened the card draws at (656,354)-(799,479) and takes its
own Train click on the wire. The RESOURCE BAR half composites at its new
position and can never be PRESENTED — the buffer→glass copy has a storm-side
640 that five instrumented runs could not reach from the exe (§19.8) — so by
this task's own both-or-neither rule the move ships NOWHERE:
`%SCPLUGIN_CONSOLE_EDGE%` (sc_console.cpp) remains an off-by-default experiment
flag carrying the instruments, wired into nothing. No art shipped,
byte-identical binary throughout.

Captures (gitignored diagnostic path; paths travel, images never):
`C:\sc-work\logs\073-frames\console-800-edge-selected.png` (the card with its
buttons at the right edge, Nexus selected) against 071's
`console-800-ingame.png` as the before. Everything below was read out of
`StarCraft.exe` 1.16.1 by this task (Ghidra decompiles + capstone listings,
`work/scratch/073/`) and then confirmed in the driven run
(`probe-console-edge.ps1`, off-screen cnc-ddraw).

### 19.1 The dialog composite, instruction level — pixels follow `+0x04`

Layer 2's draw `0x0041CB50` per frame:

1. Builds the visible-dialog list (`flags & 8`) from `0x006D5E34`.
2. Converts the layer-2 dirty REGION — a storm region handle at `0x006D5E2C` —
   into a rect list: `Ordinal_529(region, &count@0x006CF4B4, rects@0x006CF4C0)`,
   each rect `{int l,t,r,b}`, right/bottom made inclusive in place.
3. Per (visible dialog, rect): `0x0041C5D0` tests intersection against the
   dialog's LIVE bounds (`+0x04..+0x0A`) and queues the dialog and its
   intersecting children; `0x0041C080` then draws each queued control with the
   render target switched to the ROOT'S OWN SURFACE (`0x006CF4A8 = root+0x36`,
   §"status-pane-text" already had this half) and the clip converted to
   root-relative coordinates — so a dialog's CONTENT is position-independent.
4. Per (dialog, rect) the surface is COMPOSITED: `0x0041C810` clips the rect to
   the dialog bounds (`0x0041BF60`), then `0x004EF440` builds
   `dest = {rect.l, rect.t, min(rect.l+surfW, rect.r+1), ...}` and
   `src = {rect.l - bounds.l, rect.t - bounds.t, ...}` and `0x004172F0` blits
   `surface(src) -> target(dest)`. **Surface pixel (0,0) lands at
   `(bounds.left, bounds.top)` — the live bounds are the position source, every
   frame a dirty rect covers them.**

Two target selections inside `0x0041C810`, both measured live this task:

- `flags & 0x10000000` → target = the screen BUFFER `[0x006D5E20]`. StatRes is
  such a dialog (`flags=0x7000200D` read live); layer2Prep (`0x0041C7B0`)
  re-marks exactly these dialogs into the region whenever the dirty GRID under
  them is touched — it sits on the playfield, which is why it needs that
  bridge (terrain repaints under its transparent glyphs).
- default (StatBtn, `flags=0x4000000D`) → target = whatever the frame composer
  set, and `DAT_006D05A0=1` makes `0x004172F0` lock the DirectDraw surface
  (`Ordinal_350`) and blit STRAIGHT INTO THE PRESENTED FRAME. This is why §12.10
  measured the console band BLACK in the 800-wide buffer while the window showed
  art: normal console dialogs never pass through the buffer at all.

### 19.2 The art travels with the dialog — copied into its surface at creation

`game\<race>console.pcx` is loaded ONCE into a bare descriptor
`{u16 w, u16 h, u8* bits}` at `0x00597240` (loader `0x004C3950`; the race char
comes from `0x00512700[raceId]`). Its only `.text` consumers by address are the
loader and the freer (`0x004C35C0`) — no draw path names it. It reaches the
screen through the DIALOGS: when a console dialog's surface is allocated
(`0x004C35F0`, `status.cpp:0xB5`), the allocator copies the art rectangle UNDER
THE DIALOG'S BOUNDS AT THAT MOMENT into the fresh surface
(`MOV ECX,0x597240 / LEA EAX,[bounds] / CALL 0x0041D260` with the target
switched to the new surface — listing in `work/scratch/073/listing-c35f0.tsv`).

So each console dialog OWNS its slice of the art, at surface-relative (0,0) —
which is what makes the runtime move shippable: translated bounds carry the
bronze panel along, nothing is extracted, and the 160 columns nobody owns stay
black exactly as §15.5.3 ruled. (It is also the ordering constraint:
sc_console moves a dialog only once its surface EXISTS — bounds moved first
would make this copy read the 640-wide art out of range.)

The `+0x36` / `+0x0C` descriptor question §"status-pane-text" left open is now
measured: BOTH exist. StatBtn carries two distinct live surfaces
(`+0x36 bits=0x0B2C619C`, `+0x0C bits=0x0B29008C`, both 144x126); StatRes has
only `+0x36` (420x20, `+0x0C` bits NULL). The draw walk and the composite use
`+0x36`; `0x004C35F0`'s art copy fills the `+0x0C` one where it exists.

### 19.3 Finding one: the dirty-mark clip box `{0,0,640,480}` — no writer exists

`0x0041C200` is the ONE function that adds a dialog rect to the layer-2 region
(every `updateControl 0x0041C400` and hide/show sweep funnels through it). It
16-aligns the rect and clamps it against four globals before
`Ordinal_523(region, &rect, 0, 2)`:

| global | read at | stock value (file image) |
|---|---|---|
| `0x0051A16C` | 0x0041C21B | 0 |
| `0x0051A170` | 0x0041C24D | 0 |
| `0x0051A174` | 0x0041C240 | **640** |
| `0x0051A178` | 0x0041C25C | 480 |

Each is referenced by EXACTLY that one instruction in all of `.text`
(byte-scan, `work/scratch/073/findrefs.py`) — **no instruction writes them**;
they are link-time constants read out of `.data`
(`work/scratch/073/readdata.py`). So no dialog repaint could ever be MARKED
past x=639: 071's moved bounds, and this task's first run, both drew nothing
in the new region for exactly this reason, while the hit-test (which never
consults the region) moved perfectly — the whole of §18.2's mystery.

Live proof, one variable, two runs of `probe-console-edge.ps1`: with the box
stock, the moved StatBtn's new region read `nonzero=0`; with `0x0051A174`
widened `640 -> 800` — one dword, and stable, because nothing re-asserts a
value nothing writes — the same region read `nonzero=0.7295` and the capture
shows the card, buttons and all, at the window's right edge. (The RESOURCE BAR
did not follow in the same run — its buffer-path PRESENT is the separate,
structural wall of §19.8.) The sibling box `{0,0,639,479}` at
`0x0051A15C..0x0051A168` is the DRAW-time clip inside `0x0041C080`, applied in
ROOT-RELATIVE coordinates after the draw rect is rebased — a 144- or 420-wide
console dialog never reaches it, so it is recorded and left alone (it DOES have
a writer, `0x0041C325..34C`).

### 19.4 Blocker 2 dissolved: the card claims its own clicks at x>639

Rebuilt 071's interact trace (every root's `+0x2A` wrapped and named,
`%SCPLUGIN_CONSOLE_TRACE%`) and ran the Train click under cnc-ddraw — the
presenter whose window really is 800 wide, where console-DIALOG clicks
demonstrably register off-screen (probe-widescreen-drive's minimap clicks).
With the slate verified EMPTY first, the Nexus selected through the engine's
own funnel (§19.5), and the card drawn at (656,354)-(799,479):

    CTRACE dlg='StatBtn' type=4 x=682 y=374 -> ret=1
    CMD id=0x1F (0 -> 1 across the click); ring [64,228,228,228,228]

The dispatcher walk (`0x00419FD0`: per-type override table `0x006D5E40`, else
every root's interact in list order until one returns non-zero) reaches the
moved card and the card takes the click. Nothing upstream filters by x.
§18.3's contrary measurement is annotated in place with the surviving
hypothesis (the WMode posted-input contract), at the strength the evidence
supports.

Instrument note, for the next reader of a quiet trace: this task's FIRST trace
produced "no interact ever invoked" for every in-game click — because its
600-line cap had been eaten in the MENUS by two flood event types (type 13, a
timer tick, and the type-14 `dwUser=8` sweep, both arriving ~10/s per dialog).
A capped trace reads exactly like a dead route (task 048's blind-instrument
class). The shipped trace drops both floods and carries `traceDropped` in
CONSOLESTATS so a saturated run names itself.

### 19.5 The select aid — the client half of a selection is a FLAG away

Off-screen cnc-ddraw cannot feed a posted playfield click (070: 0/8), so the
probe selects through the engine's own pair — `0x0049AE40` then
`CMDACT_Select 0x004C0860` (the click handler's own order). Measured: that
pair alone yields `active=1 sim=1 client=0` — wire `0x09` sent, sim selection
filled, and the status area still empty, because `CMDACT_Select` writes only
`clientSelectionGroup2` and the wire. The client half is
`updateSelectedUnitData 0x004C38B0` — copies `activePlayerSelection` into
`clientSelectionGroup`, recounts, elects `activePortraitUnit`, refreshes the
pane — and its per-frame caller is the stat display driver `0x004D93F0`, GATED
on its first instruction's read of `client_selection_changed 0x0059723C`.
Setting that one byte after the funnel completes the selection exactly as a
real click does. (`sc_addresses.h SC_VA_CLIENT_SEL_CHANGED` carries the
evidence chain.)

### 19.6 The in-game root-dialog inventory at 800, measured

From the DIALOGS oracle in the passing run — the first complete inventory with
rects; dispatch order is list order:

| root | rect | interact |
|---|---|---|
| Minimap | (0,315)-(137,479) | 0x004A5900 |
| TextBox | (190,338)-(447,355) | 0x004F36C0 |
| Stat_F10 | (408,388)-(495,407) | 0x004F5240 |
| StatBtn | (656,354)-(799,479) MOVED | 0x00459B00 |
| StatData | (138,388)-(407,479) | 0x004584F0 |
| StatRes | (380,0)-(799,19) MOVED | 0x004E5910 |
| StatLB | (0,0)-(199,111) | 0x004BECF0 |
| StatPort | (408,408)-(495,479) | 0x0045F290 |
| StatFluf x4 | (453,330)-(639,353) / (138,354)-(495,387) / (138,315)-(184,353) / (0,302)-(147,314) | 0x004F4D60 |

The four StatFluf dialogs are the bronze RAIL segments — none underlies the
card, which is how "the card's art is in its own surface" (§19.2) was
corroborated from the outside.

### 19.7 Reproduce

```powershell
./tools/plugin/run-offscreen.ps1 -Suite ./tools/plugin/probe-console-edge.ps1
#   stage 3 + %SCPLUGIN_CONSOLE_EDGE% + %SCPLUGIN_CONSOLE_TRACE% through
#   cnc-ddraw: the move logged with flags and both surface descriptors, the
#   dialog-list rects asserted at (380,0,799,19)/(656,354,799,479), the window
#   captured and pixel-counted (positive control: the unmoved minimap), the
#   clean-slate select through the engine funnel, the Train click on the wire,
#   the ring read back, minimap steering
python work/scratch/073/findrefs.py C:\sc-work\1161-base\StarCraft.exe 0x0051A174
python work/scratch/073/readdata.py C:\sc-work\1161-base\StarCraft.exe 0x0051A16C 0x0051A170 0x0051A174 0x0051A178
```

### 19.8 Finding two, STRUCTURAL: in game, GLASS has never shown x>639 through the buffer path — the last clamp is inside storm.dll

The repaired StatBtn exposed a second, older wall. With the dirty-mark clip
widened (§19.3), the moved resource bar COMPOSITED — the 800-wide buffer dump
shows its supply counter at the new x~748..782 (rendered and read by eye as
well as by band count) — and the GLASS stayed black there. Wider still: **no
buffer pixel past x~648 has ever reached the glass in game.** 070's own window
capture (`C:\sc-work\logs\070-frames\drive-ingame-after.png`) shows the right
band BLACK ON GLASS, top to bottom, while its 800-wide FRAMEDUMPS held map —
every right-band assertion 064/068/070 made was measured from the DUMP (the
buffer), and the window PNGs were "for the human", whom nobody asked about the
band. The 800-wide MENUS present fine because glue screens are dialogs, and
normal dialogs blit DIRECT to the locked surface (§19.1) — which is also why
the moved command card shows on glass while the bar does not. Each content
class rides a different presenter, and each had been proven on a different
instrument.

The present path, and what five instrumented runs ruled out (all patched or
measured; `probe-console-edge.ps1` runs 2–5):

- The buffer reaches the screen only through `0x0041D420`:
  `lock; Ordinal_432(locked, buffer@0x006CEFF4, srcPitch, REGION@0x006D5E18);
  unlock` — a storm-REGION-driven copy. The srcPitch immediate is patched
  (`blit.sourcepitch`), and the region is rebuilt per frame at the composer
  tail and at `0x0041E000`: `SRgn*([0x006D5E14], grid, 3, &out@0x006D5E18)`.
- Every instruction NAMING the grid is in the relocation table (both `SRgn*`
  call sites included: `grid.base@0041E025`, `grid.base@0041E3DF`), the grid
  itself is 800-wide, its markers' 639-clamps are patched, and storm's
  region geometry is re-registered at `Ordinal_440(0x320, 0x1E0, 0x10, 0x10)`
  (`storm.region.width`).
- `[0x006D5E14]` — the first argument of the region rebuild — was suspected of
  being a 640-wide base clip built from the screen-image list (`imgCreate
  0x0041D640` has exactly one caller, the console.pcx loader, node
  `(0,0,640,480)`). MEASURED WRONG twice over: the region enumerates EMPTY
  (Ordinal_529: `n=0` rects, before and after intervention), and adding a
  second image node `(640,0)-(800,480)` through the engine's own `imgCreate` —
  accepted, storm handle non-null, node fields read back correct — changed
  nothing on glass.

So every 640-era constant on the exe side of the present is accounted for, and
the residual clamp lives in storm.dll's OWN state — seeded by some
initialisation this project has not yet mapped (the `Ordinal_432`/`SRgn`
family's internal screen bound is the open question, stated as such). That is
where the next task starts, and it starts with an instrument this task leaves
behind: the buffer-vs-glass pair (`Get-BufferDump` band + the caption-corrected
window capture) that turns "is it presented" into two numbers.

**Consequence for what ships: nothing of the console move.** The task's own
rule — a console drawn at the edge that cannot be clicked, or clicked but not
drawn, is half a feature — cuts the other way here: the CARD half is fully
proven (drawn, claimed its own click, wire + ring verified) and the BAR half
cannot present, so `%SCPLUGIN_CONSOLE_EDGE%` stays an experiment flag, wired
into nothing. And the standing (Wide) experience has a defect nobody had seen:
the right 160 columns of the PLAYFIELD are black on glass in game (the input
widening still works — clicks there act on the world the player cannot see).
That defect exists on main today, independent of this task's changes.

## 20. Task 074 — the storm present clip found, and CLOSED: the window shows all 800 columns

§19.8 handed this task an open question ("the Ordinal_432/SRgn family's internal
screen bound") and one dead theory (add an image node). Both are now settled by
measurement, and the wall is down: in the shipped config the playfield presents
all 800 columns on glass, buffer and glass agreeing for the first time. Read out
of `StarCraft.exe`/`storm.dll` 1.16.1 this task (`work/scratch/074/*.py`; capstone
listings + pefile), then confirmed in driven cnc-ddraw runs
(`probe-storm-present.ps1`, `probe-console-edge.ps1 -StormPresent`, off-screen).

### 20.1 The present pipeline, named

The exe's per-frame present `0x0041D420` is three storm calls (exe IAT →
`work/scratch/074/iat.py`): `ord350` (lock, IAT 0x4FE5A0) → `ord432` (copy the
framebuffer `0x6CEFF4` → the locked surface, IAT 0x4FE5A4) → `ord356` (unlock /
flip, IAT 0x4FE59C). It locks surface index 0 (the primary) with a **NULL rect**.

### 20.2 §19.8's suspected clamp is NOT the live one — measured

`ord350` with a NULL rect either locks the primary DIRECTLY (returns its pointer,
never reads storm's geometry) or FALLS BACK to a system-memory surface, building a
clip `(0,0,[storm+0x5A7C4]=640,[storm+0x5A7C8]=480)` that `ord356` then Blts. §19.8
suspected that fallback clip. **It is not live under cnc-ddraw**: across 11 in-game
samples (menu→load→select→click→minimap), the fallback pointer `[storm+0x5EA70]`
read `0` every time — the primary is locked directly, `ord356`'s clip Blt never
runs, and `[storm+0x5A7C4]` (storm's virtual-screen width) is never read for the
present. So the storm-side geometry global is a **red herring for the present**.
(Caveat at the strength of an 11-sample result: the fallback could fire transiently
on surface-loss/alt-tab; the steady-state present — what shows 640 — is direct-lock.)
And the surfaces are not the cap either: `GetSurfaceDesc` on the primary reads
`dwWidth=800 lPitch=800`, and storm's region grid (`Ordinal_440` outputs at
`[storm+0x5AC10]`) is 50×30 cells of 16×16 = 800×480. Both 800.

### 20.3 The real cap: the presentable region is 640 wide, and ord432 obeys it

`ord432` copies only the per-frame REGION `[0x6D5E18]`. Read out of the SRgn struct
directly (allocator `storm 0x1A7E0`, size 0x30; `+0x18` = row-width, `+0x1C` = row
count, `+0x20..0x2C` = bounding rect), that region is **`+0x18 = 640`, bounds
`(…,640,…)`**. In `ord432` the destination step is `dstPitch(800) − [region+0x18](640)
= 160`: it copies a 640-wide run per row and skips 160, so the 800-pitch primary is
written only in columns 0..639 and stays black on the right. The frame region
inherits `+0x18` from the BASE region `[0x6D5E14]`, which is the union of the
screen-image-list nodes — and the only node is `console.pcx`, created by `imgCreate`
`0x0041D640` at `(0,0,640,480)`. **The presentable region is 640 wide because its
sole image node is 640 wide.** That is §19.8's "SRgn internal screen bound" turned
from a name into a mechanism.

### 20.4 CORRECTION to §19.8: adding an image node cannot widen the present

§19.8 (and task 073) tried widening the base by adding a `(640,0)-(800,480)` image
node, and it "changed nothing." §19.8 left it ambiguous whether 073's node failed
because its mask was the framebuffer bytes (a garbage shape) or for a deeper reason.
**Measured (this task, a GENUINELY solid opaque-mask node): the base region's
`+0x18` stays 640 → 640 after the node is combined in.** The SRgn combine (`ord443`)
preserves the FIRST node's `+0x18`; unioning a node extends the shape but never
raises the region's row-width, which is the field `ord432` uses. So **073's
add-a-node theory is DEAD at the mechanism level**, mask quality irrelevant. The
lever is the base region's primary width itself, not the node list.

### 20.5 QUALIFICATION to §19.8: Ordinal_529's rect count is a broken instrument here

Both §19.8 and this task's first probes read the present region through
`Ordinal_529` and got `n=0` rects — while the copy demonstrably happens (the game
renders). **`Ordinal_529` enumeration is not a reliable readout of what `ord432`
copies**; read the SRgn struct's `+0x18`/`+0x20` bounding rect instead (§20.3). Any
§19.8 reasoning that leaned on that `n=0` should be read with this caveat.

### 20.6 TWO caps, not one — the second is the dirty-rect present

Widening the base region to 800 (built fresh via the engine's own `ord445`,
installed at `[0x6D5E14]`) makes the frame region inherit `+0x18 = 800` — measured,
`(0,0,800,480)`. But that alone does NOT fill the glass: **the present is
dirty-rect**, so with an 800 base the primary's x>639 is copied only on frames that
re-mark those cells dirty. On a STATIC load frame nothing does, and the far quarter
stays black even with `+0x18 = 800` (run 7: base 800, glass map = 0). Task 073's
console-edge run only ever showed the wide map because its probe SCROLLED first —
a scroll marks all cells dirty and forces a full copy. A fix validated only in runs
that happen to scroll early would appear to work and ship black for the very common
case of a player who loads a map and does not immediately scroll. So name the two
caps separately: **(1)** the presentable region width (§20.3); **(2)** the dirty-rect
present never re-copying x>639 on a static frame. Fixing (1) without (2) still shows
black.

### 20.7 The fix: copy the far quarter every present

`sc_stormpresent.cpp` hooks `ord432` (resolved from the loaded `storm.dll`, RVA
0x1A520) and, after the engine's own dirty-region copy runs, copies the x=640..799
strip straight from the 800-wide framebuffer to the primary, **every present**, using
`ord432`'s own dst/src/pitch arguments. It touches ONLY x≥640 — where in the shipped
config there is no console/HUD (the console is 640 wide) — so it overwrites nothing
the engine draws and is not a full-frame copy (which WOULD overwrite the direct-blit
console at x<640, §19.1). It holds no engine state, so a save/load or a menu return
needs no re-assertion — there is nothing to revert; it simply copies the next frame.

Measured, shipped config (`ConsoleEdge` off, cnc-ddraw off-screen, `probe-storm-present.ps1`):

| | MAP right band x=660..790 y=80..300 |
|---|---|
| static load frame (no scroll) | BUFFER=0.73  **GLASS=0.63** |
| after a scroll | BUFFER=1  **GLASS=1** |

`stripFrames=1082 stripSkipped=0` — the strip copied every present. Buffer and glass
agree for the first time in this project. On disk `storm.dll` and `StarCraft.exe`
are byte-identical (the copy is a runtime hook; every address resolved from the
loaded module).

### 20.8 The one interaction: mutually exclusive with the console-edge move

Task 073's `%SCPLUGIN_CONSOLE_EDGE%` (merged, unshipped) direct-blits the moved
resource bar and command card at x>640 (§19.1). The strip copy would overwrite them
with terrain every frame, so the two are **mutually exclusive for now**: when
`CONSOLE_EDGE` is on the storm present widen DISARMS to read-only and logs it. The
present widen ships on its own (it needs no part of the console work): the MAP band
at GLASS=0.63 on the static frame with `ConsoleEdge` OFF is the playfield widening,
not any console dialog.

### 20.9 Shipping and reproduce

The widen is PART of the widescreen feature: `sc_stormpresent.cpp` auto-arms it when
widescreen is active at stage ≥ 2 (an 800-wide playfield buffer), off otherwise, so
at 640 / widescreen-off the game is byte-for-byte stock. `%SCPLUGIN_STORM_PRESENT%`
overrides: `0` off, `probe` read-only diagnostics, `widen` force on.

```powershell
# shipped config, the two-number proof + the window capture:
./tools/plugin/run-offscreen.ps1 -Suite ./tools/plugin/probe-storm-present.ps1
# read-only diagnostics only (the instrument that settled §20.2–20.5):
./tools/plugin/run-offscreen.ps1 -Suite ./tools/plugin/probe-console-edge.ps1 `
    -SuiteArgs @{ StormPresent = 'probe' }
```

Captures (gitignored diagnostic path; paths travel, images never — hard rule 1):
`C:\sc-work\logs\074-frames\storm-present-shipped-static.png` (map past x=648 on the
static load frame) and `…-shipped-scrolled.png`.

### 20.10 CORRECTION (2026-09-05, issue #113): the shipped config never armed the widen

The user's only wide session (deployed log `C:\sc-deploy\starcraft-modded\logs\sc-plugin.log`,
2026-08-13 23:56, build `8d40c89+dirty`, which contains §20's PR) reads:

```
WIDESCREEN ACTIVE: 254 patch(es) applied, 0 refused, stage<=3
STORM present: off (%SCPLUGIN_STORM_PRESENT% unset/0)
```

The right band was black on glass and the cursor — drawn into the framebuffer past x=640
and never presented — "could not enter it". Both halves of issue #113 are this one line.

Cause, read in source: `run-with-plugin.ps1` declared
`[ValidateSet('0','probe','widen')][string]$StormPresent = '0'` and exported it verbatim
(`$env:SCPLUGIN_STORM_PRESENT = $StormPresent`), so `ScStormPresentModeWanted()`'s "unset ⇒
widen iff widescreen stage ≥ 2" branch was unreachable on every launch through that script.
§20.9's "auto-arms" was true of the DLL and false of every launcher. The offscreen proofs
passed `-StormPresent widen` explicitly (`probe-storm-present.ps1`), and
`test-widescreen-input-800.ps1` never passed it at all, so its "auto-arm exercised" reading
in the task-074 PR was vacuous: it asserted input, not glass. The log line itself is of the
house class — it could not say which half ("unset" or "0") had decided.

Fix: the launcher default is `auto`, exported as UNSET (`''` removes the variable); the
deployed (Wide) launcher names `-StormPresent widen` explicitly and the deploy Pester test
asserts it; the DLL's off line now prints which half decided
(`off -- %SCPLUGIN_STORM_PRESENT%=0 (explicit)` vs `unset and no widescreen playfield
(widescreen=%d stage=%d)`); `probe-storm-present.ps1 -StormPresent auto` exercises the
DLL's own decision (pre-fix it reads `off`, post-fix `WIDEN armed`).
