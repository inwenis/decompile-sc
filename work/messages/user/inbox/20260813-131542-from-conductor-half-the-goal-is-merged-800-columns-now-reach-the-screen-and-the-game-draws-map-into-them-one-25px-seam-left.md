---
from: conductor
to: user
sent: 2026-08-13T13:15:42Z
subject: Half the goal is merged: 800 columns now reach the screen, and the game draws map into them (one 25px seam left)
---

**Half of your goal is merged. The other half is measured working but not merged yet.**

## 1. More of the map can now reach your screen — merged

https://github.com/inwenis/decompile-sc/pull/98

`WMode.dll` — the windowed helper this project did not write — was throwing away every column past 640. **cnc-ddraw presents all 800.** Measured, with the control arm proving the probe can still detect a crop, and four predictions written down before the run.

I opened the picture myself: an **800x480 window, menu in the left 640, the right 160 presented as a black band** instead of cropped away. `C:\sc-work\logs\065-frames\present-ddraw-ws1-menu.png` if you want to look.

Black because nothing is drawing there yet. Which is the other half:

## 2. The game now draws real map past column 640

Task 064 got terrain, units and minerals into columns 640-799 — **right band 84% non-black, byte-stable across two captures.** Task 034 declared this structurally impossible in June; it turned out 034 was working with an instrument that could not see the extra columns, and its bisect was correct about everything it could observe.

**One defect outstanding**: a 25-pixel black seam at x=671..695. 064 is on the machine right now running an experiment that tells us which subsystem owns it — it moves the camera and watches whether the seam follows the map or stays on the screen. Predictions filed before the run.

Not merged yet, deliberately. It should not ship with a seam in it.

## 3. Your cancel bug

Diagnosis merged (#95). The obvious fix was built, measured, found to make things worse, and reverted. **Option C is dead** — killed by disassembly for the price of no machine time at all. Option A is being built now.

## 4. One thing you asked for is finally being done properly

You said *"Do (2) properly first, I will wait"* about the test map surviving a redeploy. **Cut and running now** — the card that currently tells you *"a redeploy deletes it"* gets rewritten as part of it.

Nothing needs you.
