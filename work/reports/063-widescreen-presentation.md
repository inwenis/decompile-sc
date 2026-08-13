# Task 063 — See more of the map: a presentation path that does not touch the user screen

## Headline

**Question (1) is answered YES, measured: the engine's full composed frame is readable
without presenting it and without touching the user's display.** The stage-1 build's
800x480 frame was captured out of the engine's own framebuffer — all 800 columns,
including the 160 no window has ever shown — with the stock-640 positive control passing
first. **Stage 2 is developable today with zero user impact; task 034's blocker was a
property of its instrument, not of the engine.**

Full write-up with evidence: `research/renderer-viewport.md` §13 (plus a §2 correction
and a §12.10 note). This report is the summary and the run ledger.

## 1. The instrument (commit `eb4c6de`, recalibrated in `b82024a`)

1. Plugin `FRAMEDUMP`: per-marker copy of the screen Bitmap's buffer (`0x006CEFF0`) to
   `fd-<marker>.bin`. No hook, observe-mode safe, off by default. Torn copies impossible
   to miss: repeats until two consecutive reads are byte-equal, `reads=`/`stable=` logged
   and stored in the file header.
2. `tools/plugin/frame-capture.py`: `check` validates a dump against the presented
   window (index→RGB mapping over pixels stable across two bracketing captures — a
   wrong-pitch dump collapses to 0.58 on the synthetic control, a dead window capture is
   refused); `diff` ports §12.2's `wide_rows` row-span discriminator to raw indices;
   `band` histograms a region; `render` turns a dump into a PNG via a derived palette.
3. `probe-framebuffer-capture.ps1`: two launches under one lock — stock-observe positive
   control, then stage 1 — with the cross-arm playfield diff at the end.

## 2. Measured results (run of 2026-08-13, off-screen, fixture map, both arms)

1. Positive control (stock, `-Mode observe`): dump 640x480, stable; reproduces the
   presented playfield at **consistency 0.98902** over (128,20)-(512,320); renders to a
   recognizable PNG.
2. Stage 1: dump **800x480, stable, at menu and in game**; playfield consistency 0.98912
   — which can only hold if rows are extracted at the true pitch of 800; **right 160
   columns read end to end** (all index 0: the 800-aware clear, exactly stage 1's
   prediction); cross-arm in-game diff over the playfield: **wide_rows=0**, 1252
   differing px in 6 blocks (sprite animation), same camera origin both arms (544,416).
3. Two corrections to the record (research/renderer-viewport.md §2 note), found by
   diagnosing the first run's whole-frame consistency of 0.75:
   - the main-menu glue screens do NOT compose into `0x006CEFF0` (buffer all index 0 in
     both arms);
   - in game the buffer holds the playfield + top counters but NOT the console/HUD
     dialogs (their pixels live in the dialogs' own surfaces — the ones `sc_queueind`
     reads) and NOT the cursor.
4. Artifacts (gitignored, paths travel, images never committed):
   `C:\sc-work\logs\063-frames\` — `fd-*.bin` dumps, `*-render.png` (incl. the 800-wide
   `s1-ingame-render.png`), `*-before/after.png` window captures, `*-palette.json`.

## 3. Question (2): the presentation bill (research/renderer-viewport.md §13.4)

1. **This adapter has no 800x480 mode** (measured: 132 mode entries, 21 resolutions;
   800x600 and 640x480 exist). True fullscreen at the feature geometry is impossible
   here; 800x600 (§12.1 parametric regeneration) is the only fullscreen-viable shape,
   and it is a user-attended decision (mode switch + icon shuffle).
2. **cnc-ddraw** (MIT, source-available ddraw re-implementation, StarCraft on its
   supported list, presents the full requested surface by architecture) is the
   best-value route: **one task** — build/obtain, drop in via the existing `-Windowed`
   mechanism, read `probe-widescreen-present.ps1`'s CROP/SCALE/FOLLOW verdict.
3. Own code only if that fails: a ddraw shim is bounded by **storm.dll importing nothing
   from ddraw** (pe-anatomy.md), est. 4–8 tasks; a plugin-side presenter hooking the one
   present blit (`FUN_0041D420`) est. 2–4 tasks, palette capture being the open question.
4. Fullscreen-on-invisible-desktop measurement (`probe-fullscreen-desktop.ps1`): **built,
   deliberately not run.** Question (1)'s YES removed what it blocked, and its LEAKED
   outcome would flip the user's real desktop mode for seconds (icon layout at risk).
   Conductor holds it for a user-attended GO; acceptance criterion 4 is answered by the
   built probe + this documented decision rather than by an unattended run.

**Recommendation:** cnc-ddraw measurement task next; fullscreen only as a user-attended
800x600 choice; own presentation code only if cnc-ddraw's probe returns CROP.

## 4. Compliance

- `StarCraft.exe` on disk byte-identical throughout; all patching in-process (stage-1 arm
  only), stock arm fully read-only.
- Nothing the user sees changed: all runs off-screen; the one probe that could have
  touched the real desktop was built but withheld.
- Frame dumps/renders reproduce game artwork → gitignored diagnostic path only.

## 5. Run ledger

1. Run 1 (2026-08-13 ~10:54): aborted during `Wait-ScNoGameRunning` on conductor
   instruction (062 still had the machine) — nothing held, nothing launched.
2. Run 2 (~12:08): both arms complete. 22/26 assertions OK; the 4 FAILs were the
   whole-frame trust check aimed at regions the buffer measurably does not hold (the §2
   correction above). Geometry oracles all passed.
3. Run 3 (~12:30): clean re-run after recalibration — **PASS, 0 failures, 21
   assertions** (playfield consistency 0.98909 stock / 0.98910 stage-1, both dumps
   stable at reads=2, right band 76800/76800 index 0, cross-arm `wide_rows=0` with
   span_max=20). Transcript:
   `C:\sc-work\logs\offscreen\20260813-*-probe-framebuffer-capture.txt` (run 3 is the
   latest), tee at `C:\sc-work\logs\063-framecap-run3.txt`.
