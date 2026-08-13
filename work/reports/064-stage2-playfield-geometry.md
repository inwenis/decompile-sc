# Task 064 — Stage 2: the engine draws the playfield 800 wide

## Headline

**There is map past column 640, in the engine's own framebuffer, at pitch 800,
and the playfield geometry is correct**: against stock the left 640 columns
match with `dense_rows=0`, window-vouched consistency reads 0.98900–0.99877 at
pitch 800, and the right band's terrain is byte-stable across captures and
camera moves. §12.9's "stage 2 does not decompose" was **an enumeration gap
wearing a structural costume** — the stage was 56 sites short, all in the
terrain-scratch REFRESH band, in encodings no sweep could match. 034's bisect
was correct about everything it could observe; the missing sites sat inside the
terrain group's own feeding path, so every coherent subset carried the defect.

**Two fog defects remain, measured and screen-anchored — the leak first because
it is the gameplay one:** fog is never drawn over screen px 696..799, so raw
terrain shows there even over unexplored map (the player sees a quarter of the
extra width they have not earned); and px 672..695 paint black at every origin,
even over explored map (the 25-px seam). "The right band holds MAP" and "the
right band holds map the player is entitled to see" are different claims — run
2 measured the first; run 3's moved camera exposed the second. Per the task's
own instruction the working playfield ships behind the off-by-default flag with
the fog defects stated; the conductor is cutting the fog follow-up.

Full write-up with evidence: `research/renderer-viewport.md` §14.

## 1. The 56 sites, by hiding shape (§14.2)

| family | sites | example |
| ------ | ----- | ------- |
| mod-reduction chains, k·0x49800 as NEGATIVE lea displacements | 20 | `lea ecx,[eax-0x498000]` |
| column wraps, same encoding | 2 | `lea eax,[edi-0x49800]` |
| row steps in tile-row bytes | 3 | `add ecx,0x5400` (=672·32) |
| derived bounds | 3 | `cmp edi,0x44400` (=672·416), `cmp eax,0x497E0` (=size−32) |
| −0x49800 as AND mask / ADD imm (branchless wrap) | 4 | `and eax,0xfffb6800` |
| unrolled per-megatile writer (§12.8's shape, in the producer) | 12 | `lea edx,[edi+0x1500]` (=672·8) |
| cache extent in TILE units (21 = 672/32) | 10 | `add eax,0x15` (x-stepper incoming column) |
| grid row 18 named absolutely + its 40·(row−17) count — **found by 034's scan, LOST IN TRANSCRIPTION** (a different defect class: the information existed) | 2 | `mov edi,0x6cf2c8` |

Named-grid-reference accounting closes **21/21** (12 rebases + 9 code fixups).
Table: 222 sites verify against the exe; 209 written (171 at stage 2).
Margin convention, stated for the next reader: scratch pitch = playfield width
+ one 32px tile (832 = 800+32 as 672 = 640+32); rows stay 448, so every
14-row (0xE) constant stays.

Mechanism of §12.9's wreck: at fixture origin (544,416) the patched ×832
multiply yields scratch offset 0x54A20; the unpatched chain reduces it mod
0x49800 to 0xB220 while the patched blitter reads 0x54A20 — producer and
consumer disagree over the whole surface from frame one.

## 2. Run ledger (all 2026-08-13, off-screen)

1. **Run 1** (aborted): fixture never generated — worktrees carry no `.venv`,
   fallback python lacks richchk — and the walk's re-check blamed *"another
   worker's cleanup"*: a wrong culprit asserted from no evidence. Issue #97;
   the probe now refuses at generation with the real traceback. Nothing
   launched, nobody's fixture was touched.
2. **Run 1b**: unchanged probe, stock + stage 1 — **PASS 21/21**. Control
   owned: stock consistency 0.98909 (=063 run 3), s1 800x480 stable, right
   band 76800/76800 index 0, cross-arm wide_rows=0.
3. **Run 2**: stock + stage 2, s2 captured twice, 36-marine fixture (single
   marine leaves the right band legitimately shroud-black — correct and broken
   stage 2 would read identically; vacuous-fail direction closed in the
   fixture). 27 OK / 3 FAIL, all three decomposed offline: one auto-align
   mislock ((8,36) vs the true (5,32); capture 2 read 0.99296), two span-
   heuristic artifacts (flagged rows differ in 17–101 px of 640/800 — sprite
   rows — vs §12.9 damage at ~70% of the row). Right band between captures:
   0 differing px.
4. **Run 3**: stock + defect arm + stage 2 with the camera moved by minimap
   clicks — **42/43**; the 1 FAIL is the stock arm's unpinned align check
   mislocking again (0.33867 auto; 0.98477 re-run offline with the pin on the
   same brackets — the recurring artifact, now pinned in the committed probe).
   - Defect arm (`SCPLUGIN_WS_ONLY=terrain`, incoherent by §12.5's coupling,
     writes bounded): ACTIVE 140 applied / 69 skipped, **dense_rows=16 RED on
     live pipeline damage** (wide_rows=235).
   - Cross-arm left 640 vs stock: **dense_rows=0** (wide_rows=130, all sprite
     rows, widest row 122 px of 640). Same-origin pair (identical clicks →
     (704,416) twice): dense_rows=0, wide_rows=0.
   - Seam tracker (zeroruns, y=20..320): origin (544,416) → 671–695; (576,416)
     → 671–695; (704,416) → 628;632–695 with px 696..799 **100.0000% non-zero
     over provably-unexplored map**. Verdict **P1 screen-anchored**, two parts
     as in the headline. (Black at 632..671/origin-704 is consistent with
     legitimate shroud at the fixture's sight boundary; not claimed.)

## 3. Instrument work (each proved before trusted)

1. **`dense_rows`** (frame-capture.py diff): rows whose differing-px COUNT
   exceeds half the width. Seen RED before green: synthetic stride-640
   re-slice of the real dump → **380/380** through the real tool; live defect
   arm → **16**; the sprite-row false positives wide_rows counts at 130/235 →
   **0**.
2. **Pinned check alignment** (5,32) on asserted checks; auto-search kept on
   the render pass, disagreement printed as a FINDING naming both values.
3. **`zeroruns`**: all-zero column runs over a region — the seam tracker.
4. Probe: stage-2 mode (stock + defect + scroll captures), fixture generation
   asserted (#97 class), WIDESCREEN ACTIVE + filter lines asserted in both
   directions (a refused table runs stock and passes every diff vacuously).

## 4. Compliance

- `StarCraft.exe` on disk byte-identical; patches in-process behind
  `%SCPLUGIN_WIDESCREEN%`, off by default; observe mode ignores it entirely.
- All runs off-screen; the user's screen, focus, and settings untouched.
- Frames/dumps on the gitignored diagnostic path; paths travel, images never
  (corrected criterion 1 — no `pr-image` on game frames, hard rule 1 wins).

## 5. Not covered, so nobody over-reads

1. **Fog cell band** (the two defects above) — follow-up task, suspect list:
   unpatched CELL-unit constants 81=648/8, 80=640/8 at 0x0047E4B0, 0x0047E4C0,
   0x0047E8D9, 0x0047F820, 0x0047F829, plus an unread sibling branch clamping
   0x68/0x67 (104/103) on mode flag 0x58F440. research/renderer-viewport.md
   §14.4 carries the full dossier for a reader starting cold.
2. Scroll clamp stock (stage 3): at the right map edge the last 5 tile columns
   read unfilled scratch; mouse→world, window-proc clamps, minimap untouched
   (stages 3/5).
3. The console-right 160x80 strip is blank by design (no art; user's call).

## 6. Artifacts (gitignored; open locally)

- `C:\sc-work\logs\063-frames\s2-ingame2-render.png` — the 800-wide frame,
  run 2 (origin 544,416; seam visible at x≈672)
- `C:\sc-work\logs\063-frames\s2-scrolled2-render.png` — run 3, origin
  (704,416): the fog leak past x=696 over unexplored map
- dumps `fd-s2-*.bin`, `fd-stock-ingame.bin`, `fd-synthetic-stride640.bin`
- transcripts `C:\sc-work\logs\064-framecap-run{1b,2,3}.txt`
