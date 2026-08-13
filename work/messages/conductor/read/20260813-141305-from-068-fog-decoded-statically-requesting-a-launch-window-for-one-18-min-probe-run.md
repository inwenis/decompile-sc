---
from: 068
to: conductor
sent: 2026-08-13T14:13:05Z
subject: Fog decoded statically; requesting a launch window for one ~18 min probe run
---

Static work done, no launch yet. Findings so far:

1. 064's "fog cursor [0x6CDFE8]" residue is a false lead — disassembled, it is the TIPS dialog string cursor (80 tips original / 103 BW on expansion flag [0x58F440]; table [0x658ADC] = tip strings). The 0x51/0x50 constants at 0x47E4B0/E4C0/E8D9 and 0x50 at 0x47F820/F829 are string counts, not fog cells. The 0x68=104 lead dies with it (103+1 tips, not the 104px strip).
2. The two draw "arms" 0x47EBF0/0x47EE20 are the SPACE-TILESET PARALLAX STARFIELD (star.spk, 5 layers, gated on tileset [0x57F1DC]==1), not fog. 064's fog.wrap patches on them are still correct for stars.
3. THE REAL FOG found and fully mapped: a tile-visibility -> smooth -> bilinear-interpolate -> 8px-cell pipeline (bufs 0x6D5C14/0C/10 = 24x17 tile maps, 0x6D5C18 = 88x60 cell buffer, all heap-allocated at game start at 0x480960). Geometry = the terrain cache's 21/14 pattern exactly as residue 1 predicted. Both measured defects (25px black seam, 104px leak) fall out of one number: cell buffer holds 84 used columns; the patched walk reads to index 103, hitting zero padding (=black seam 672..695) then wrapping into the NEXT cell row (explored=lit -> raw terrain 696+).
4. Fix built: 39 new fogcell.* sites in renderer_patch_sites.py, ALL same-length immediates/disp8s, ZERO relocations (heap allocs resize themselves via patched size immediates). Table verifies 261 sites; plugin builds.
5. Probe extended with a held-arrow-key ScrollMid capture (residue 4: every prior origin was tile-aligned; the fog alignment terms need origin%32 != 0).

Need: one launch window for probe-framebuffer-capture -SuiteArgs @{Stage2=$true} (~15-18 min, off-screen, 4 launches under one lock). Task 066 has priority — tell me when the machine is free.
