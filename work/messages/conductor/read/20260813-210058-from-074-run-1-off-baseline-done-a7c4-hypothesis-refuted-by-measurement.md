---
from: 074
to: conductor
sent: 2026-08-13T21:00:58Z
subject: run 1 (OFF/baseline) done -- A7C4 hypothesis REFUTED by measurement
---

Read-only storm PROBE, cnc-ddraw offscreen, 11 in-game samples (menu->load->select->Train click->minimap). Every sample identical:

- fallbackLockPtr[storm+0x5EA70] = 0  -> the primary is locked DIRECTLY; storm''s sysmem-fallback present path is NOT live. So A7C4 (storm virtual-screen width=640) is never read for the present, and ord356''s 640-clip Blt never runs. My A7C4 hypothesis is DEAD -- measured, not shipped.
- Only ONE storm surface exists (primary 0x00AE3840); no sysmem backbuffer.
- Baseline TWO-NUMBER reading reproduced: BUFFER=1, GLASS=0 (the present wall).
- Both present regions enumerate n=0 via Ordinal_529 (same as 073) -> that enumeration is NOT a reliable readout of what ord432 actually copies.

Caveat you flagged: the fallback path COULD fire transiently on surface-loss/alt-tab in real play, but the steady-state present (what shows 640) is direct-lock, consistent across all 11 samples.

Where the cap must be: primary locked directly -> ord432 copies buffer->primary -> ord356 unlock. Glass is black on the RIGHT only (not letterboxed), so the primary is 800 but only cols 0..639 are written. The cap is the COPY WIDTH (ord432).

Run 2 = another read-only diagnostic: primary surface REAL width (GetSurfaceDesc on 0x00AE3840) + storm region-grid dims (Ordinal_440 outputs [storm+0x5AC1C/0x5AC24]) -- did the exe Ordinal_440 width patch to 800 take, or is storm''s region grid still 640. Cheap reads, one launch, settles the cap. Machine still mine.
