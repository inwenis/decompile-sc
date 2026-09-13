# Live read-back of the renderer layout (task 032)

The static map in `research/renderer-viewport.md` predicts a set of values in the running
process. This is those values, read out of a live StarCraft.

- **Producer**: `tools/plugin/probe-screen-layout.ps1`, one run, 2026-08-10 23:39 local.
- **Oracle**: the plugin's read-only `SCREEN` scan (`%SCPLUGIN_SCREENSCAN%=1`), which installs
  no hook and calls nothing in the game. The run was `-Mode observe` and the log positively
  reports `mode : observe` and zero `HOOK ... installed` lines — proved in that order, since
  an absence check that has never been shown to match is worth nothing (AGENTS.md).
- **Arms**: two readings, `menu` (main menu) and `ingame` (a generated 128x96-tile map loaded,
  one Marine). The pair is the point: a single in-game reading cannot tell "layer 5 is the
  playfield" from "layer 5 always looks like that".
- Log kept at the gitignored diagnostic path `C:\decompile-sc-data\sc-work\logs\032-screen-layout.log`; the
  lines below are copied verbatim minus their timestamps.

## menu

```
SCREEN [menu] bitmap@0x006CEFF0 w=640 h=480 data=0x02AA0010 bytes=307200
SCREEN [menu] layer=7 used=0 flags=0x00 rect=(0,0 0x0)      param=0x00000000 draw=0x00000000 drawStatic=0x00000000
SCREEN [menu] layer=6 used=0 flags=0x00 rect=(0,0 0x0)      param=0x00000000 draw=0x00000000 drawStatic=0x00000000
SCREEN [menu] layer=5 used=0 flags=0x00 rect=(0,0 0x0)      param=0x00000000 draw=0x00000000 drawStatic=0x00000000
SCREEN [menu] layer=4 used=0 flags=0x00 rect=(0,0 0x0)      param=0x00000000 draw=0x00000000 drawStatic=0x00000000
SCREEN [menu] layer=3 used=0 flags=0x00 rect=(0,0 0x0)      param=0x00000000 draw=0x00000000 drawStatic=0x00000000
SCREEN [menu] layer=2 used=1 flags=0x20 rect=(0,0 640x480)  param=0x00000000 draw=0x0041CB50 drawStatic=0x0041CB50
SCREEN [menu] layer=1 used=1 flags=0x00 rect=(0,0 0x0)      param=0x00655C40 draw=0x004810F0 drawStatic=0x004810F0
SCREEN [menu] layer=0 used=1 flags=0x00 rect=(637,477 20x21) param=0x00000000 draw=0x004BDFA0 drawStatic=0x004BDFA0
SCREEN [menu] origin=(0,0) tile=(0,0) map=0x0 tiles (0x0 px) scrollMax=(0,0) predicted=(-640,-376) match=0
```

## ingame

```
SCREEN [ingame] bitmap@0x006CEFF0 w=640 h=480 data=0x02AA0010 bytes=307200
SCREEN [ingame] layer=7 used=0 flags=0x00 rect=(0,0 0x0)      param=0x00000000 draw=0x00000000 drawStatic=0x00000000
SCREEN [ingame] layer=6 used=0 flags=0x00 rect=(0,0 0x0)      param=0x00000000 draw=0x00000000 drawStatic=0x00000000
SCREEN [ingame] layer=5 used=1 flags=0x00 rect=(0,0 640x400)  param=0x00000000 draw=0x004BD580 drawStatic=0x004BD580
SCREEN [ingame] layer=4 used=0 flags=0x01 rect=(0,0 0x0)      param=0x00640964 draw=0x0048D5C0 drawStatic=0x0048D5C0
SCREEN [ingame] layer=3 used=0 flags=0x01 rect=(0,0 0x0)      param=0x0064095C draw=0x0048D5C0 drawStatic=0x0048D5C0
SCREEN [ingame] layer=2 used=1 flags=0x20 rect=(0,0 640x480)  param=0x00000000 draw=0x0041CB50 drawStatic=0x0041CB50
SCREEN [ingame] layer=1 used=1 flags=0x00 rect=(640,400 0x0)  param=0x00655C40 draw=0x004810F0 drawStatic=0x004810F0
SCREEN [ingame] layer=0 used=1 flags=0x00 rect=(200,262 20x21) param=0x00000000 draw=0x004BDFA0 drawStatic=0x004BDFA0
SCREEN [ingame] origin=(544,416) tile=(17,13) map=128x96 tiles (4096x3072 px) scrollMax=(3456,2696) predicted=(3456,2696) match=1
```

## What each line settles

| claim in `renderer-viewport.md` | predicted from | measured |
| ------------------------------- | -------------- | -------- |
| §2 the screen Bitmap is `{u16 w; u16 h; u8* data}` at 0x006CEFF0, 640x480, `w*h` bytes | 0x004DB07C / 0x004DB085 / `SMemAlloc(0x4B000)` | `w=640 h=480 data=0x02AA0010 bytes=307200` — the pointer is a live heap address and the size is exactly `w*h` |
| §4 the layer stride is 20 bytes and there are eight of them | 0x004BD630's `[i * 0x14]` indexing | eight records read at that stride, all eight fields plausible in both arms |
| §4 **layer 5 is the playfield, 640x400 at (0,0)** | 0x004BD675 / 0x004BD67E | `used=1 rect=(0,0 640x400) draw=0x004BD580` in game, `used=0` at the menu — the layer appears when a game loads |
| §4 layer 2 is the dialog layer at 640x480 | 0x0041A049 / 0x0041A052, and 0x0041CB50 walking the dialog list | `used=1 rect=(0,0 640x480) draw=0x0041CB50` in **both** arms — dialogs exist at the menu too, which is what a dialog layer should do |
| §4 layer 0 is the cursor | draw slot written by 0x004D1560, a `cur.cpp` function | `rect=(637,477 20x21)` at the menu and `(200,262 20x21)` in game — a 20x21 rectangle that **moved to where the driver last clicked** (the tips dialog's OK button, which `Dismiss-ScTipsDialog` reported at 200,262). Nothing else in the layer table tracks the mouse |
| §4 layers 3 and 4 are the placement preview, installed together by 0x0048D700 with params 0x0064095C and 0x00640964 | the installer's `puVar2 = &DAT_0064095C; puVar2 += 8` loop | `param=0x0064095C` and `param=0x00640964`, both `draw=0x0048D5C0`, both `used=0` (nothing was being placed) — the exact two addresses, in order |
| §4 layer 1's param is 0x00655C40 | 0x004813B3 | `param=0x00655C40` in both arms |
| §8 0x00481480 **parks layer 1 at (640,400) to hide it** | 0x004814EA / 0x004814F3 | in game, layer 1 reads `rect=(640,400 0x0)` — the park is visible in memory, which is what turns a reading of two `MOV`s into a fact |
| §4 layers 6 and 7 are unused | no writer of their draw slots anywhere in the binary | `used=0 draw=0x00000000` in both arms |
| §7 `maxScreenLeft = (mapTileW - 20) * 32` and `maxScreenTop = (mapTileH - 12) * 32 + 8` | 0x0049BB90 | on a 128x96-tile map: `scrollMax=(3456,2696)`, predicted `(3456,2696)`, **match=1**. `(128-20)*32 = 3456` and `(96-12)*32+8 = 2696` |
| §7 the tile origin is the pixel origin >> 5 | every scroll stepper | `origin=(544,416) tile=(17,13)`; `544>>5 = 17`, `416>>5 = 13` |

The `menu` arm's `match=0` is correct and expected: no map is loaded, so `mapTileW/H` are 0 and
the predicted maxima go negative. It is included rather than filtered because a check that only
ever runs where it passes is not a check.

## What this does NOT verify

- The dirty-block grid (§5) and the terrain scratch surface (§6). Both are read from
  disassembly only. The probe does not dump them — a 1200-byte grid and a 294 KB surface are
  pixel-adjacent data, and reading them back would be reproducing frame content rather than
  layout.
- Anything about a resolution other than 640x480. Nothing in this task ran the game at a
  different size; see `renderer-viewport.md` §10.
