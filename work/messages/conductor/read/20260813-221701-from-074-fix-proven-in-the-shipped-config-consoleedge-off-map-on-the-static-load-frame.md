---
from: 074
to: conductor
sent: 2026-08-13T22:17:01Z
subject: FIX PROVEN in the SHIPPED config (ConsoleEdge OFF) -- map on the static load frame
---

probe-storm: PASS (0 failures). Strip-copy fix, ConsoleEdge OFF (the config that ships):

- STATIC load frame (no scroll): MAP right band x=660..790 y=80..300 BUFFER=0.73 GLASS=0.6301 -> [4] OK. This is exactly run 7s failure, now fixed: the map presents past x=648 on the FIRST frame, without a scroll.
- must-not-break: a minimap click still steers the camera at 800 -> [5] OK.
- after a scroll: BUFFER=1 GLASS=1 -> [6] OK (holds).
- STORMSTATS: stripFrames=1082 stripSkipped=0 -- the strip copied every present.

Captures (paths, not pr-image): storm-present-shipped-static.png, storm-present-shipped-scrolled.png in C:\sc-work\logs\074-frames\.

Your ConsoleEdge overlap: handled -- the storm widen now DISARMS when %SCPLUGIN_CONSOLE_EDGE% is on (they are mutually exclusive; logged so nobody discovers it as a defect). x>640 has no HUD only when ConsoleEdge is off, which is exactly when the strip runs.

Save/load + menu: with the strip copy there is NO engine state to revert -- the hook copies every present unconditionally, so a reload or menu return needs no re-assertion (stronger than the base-region approach, which is dropped). stripFrames climbing continuously is the evidence.

Remaining before PR: must-not-break suites (running test-widescreen-input-800 both arms now, + test-production-queue), card update, §20 in renderer-viewport.md (two caps named separately; 073 node theory corrected to dead; Ordinal_529 qualified), run-ci-local on a clean tree. Machine mine.
