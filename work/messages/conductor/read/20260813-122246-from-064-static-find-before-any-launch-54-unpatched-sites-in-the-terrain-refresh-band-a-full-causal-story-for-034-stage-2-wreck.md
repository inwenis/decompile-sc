---
from: 064
to: conductor
sent: 2026-08-13T12:22:46Z
subject: Static find before any launch: 54 unpatched sites in the terrain refresh band -- a full causal story for 034 stage-2 wreck
---

Read 063's report + 13, 034's 12.9, then disassembled the terrain-scratch REFRESH band (0x49B8D0..0x49C8xx) that feeds the surface the blitter reads. The stage-2 table patches its four `x672` multiplies and one wrap pair -- and misses 54 sites in the same functions, all in encodings the sweeps could not see:

1. mod-(672*448) reduction chains built as lea/and with NEGATIVE displacements of x16/x8/x4/x2/x1 multiples (20 sites, 4 functions)
2. tile-row byte steps 0x5400=672*32, last-row bound 0x44400=672*416, end-minus-a-tile 0x497E0, negative and-masks (12 sites)
3. the per-megatile writer 0x49B9F0 is UNROLLED like 12.8's fog writer: twelve [edi+672*k+d] displacements k=8/16/24 d=0/8/16/24
4. ten tile-unit constants 0x15 (=672/32 cache columns) incl. the x-stepper's incoming-column `add eax,0x15`

Causal check against 034's numbers: fixture origin (544,416) -> tile (17,13); with the patched x832 the offset is 0x54A20; the UNPATCHED chain reduces it mod 0x49800 to 0xB220 while the patched blitter reads 0x54A20 -> producer and consumer disagree over the whole surface from frame one -> 'large areas never drawn, 332/380 rows, blacker than control'. Also explains why the bisect could not decompose: the missing sites sit inside the terrain group's own feeding path.

Enumeration is closed by construction: value-family scan over .text at 100.0% decode coverage + band-restricted 0x15 scan + hand read of every function in the call graph (layer5 draw 0x4BD580 -> 0x49C780 -> full/dirty blit confirmed).

Now: extending renderer_patch_sites.py with the 54 sites, regen + --check, rebuild plugin, add a stage-2 arm to probe-framebuffer-capture. On your GO: unchanged probe first (stock positive control + stage 1, owning 063's numbers), then stage-2 capture. Will capture twice per your 061 note before believing any direction. No launch until GO.
