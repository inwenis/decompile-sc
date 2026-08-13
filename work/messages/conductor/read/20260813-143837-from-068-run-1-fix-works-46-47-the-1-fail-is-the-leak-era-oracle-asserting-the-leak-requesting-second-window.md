---
from: 068
to: conductor
sent: 2026-08-13T14:38:37Z
subject: Run 1: fix works -- 46/47, the 1 FAIL is the leak-era oracle asserting the leak; requesting second window
---

Run 1 (C:\sc-work\logs\068-framecap-run1.txt, transcript C:\sc-work\logs\offscreen\20260813-153254-probe-framebuffer-capture.txt). Readings against the pre-registered predictions (research/renderer-viewport.md 16.4):

1. SEAM GONE (prediction 1 confirmed): ingame (544,416) zeroruns = 788;792-799 -- no screen-anchored 671-695 run. My frac-direction guess was wrong (band nonzero ROSE 0.8438 -> 0.9251; explored coverage was bigger than my sight estimate) -- the substantive claim (seam gone) holds.
2. LEAK GONE (prediction 2 confirmed, strongest form): scrolled2 (704,416) right band = 100.0000% index 0 over provably-unexplored map (was 100.0000% nonzero pre-fix). The single FAIL [41] is 064's ">= 0.30 holds MAP" oracle AT THAT ORIGIN -- calibrated on the leak, it asserts the defect's own signature. Fixed: assertion now origin-dependent (ingame >= 0.30 map, scrolled2 <= 0.02 hidden), with the run-1 reading cited in the comment.
3. Cross-arm left 640 vs stock: dense_rows=0 (prediction 3). Defect arm dense_rows=42 RED. Stock arm all green (prediction 5). Consistency 0.98727/0.99733 at pitch 800.
4. ALL zero-runs now map-anchored: stray col + 3-gap + solid at origins 544/576/704 all sit at map x = 1332 (544+788 = 576+756 = 704+628). 064's residue-5 "628 stray" was the exploration boundary all along -- resolved, goes in 16.4.
5. ScrollMid: keyboard scroll WORKS (posted VK reaches the engine) but 420ms hold ran 704px into the left clamp -- origin (0,416), tile-aligned, alignment terms not exercised. Scroll measured >= 850 px/s. Probe now holds VK_RIGHT 100ms from (704,416) -> expect a mid-map stop off the 32-grid. Bonus from the overshoot: map-left-edge fog at 800 is correct (zeroruns 0-15;32-358, map-anchored).

Two probe-oracle edits committed on top (origin-dependent band assertion + a seam regression tooth asserting no zero-run touches x=660..700 at ingame, proved-able-to-fail against 15.4 run 3). Need: SECOND ~18 min window for the clean 47/47 acceptance run (criterion 1 wants fixed frame + stock control + dense_rows in ONE run). Machine released: lock freed, no StarCraft process (verified just now). Renders for the user at C:\sc-work\logs\063-frames\s2-ingame-render.png and s2-scrolled2-render.png.
