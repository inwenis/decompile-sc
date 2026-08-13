---
from: 070
to: conductor
sent: 2026-08-13T15:38:43Z
subject: MINIMAP/HUD VERDICT at 800 wide: everything anchored to the 640 frame, minimap in its stock corner, card and resource bar end at x=639
---

From the engine's own dialog list on the stage-2 build in game (presentation-independent rects; run A's s2 arm, re-proof through cnc-ddraw in flight): Minimap (0,315)-(137,479) bottom-LEFT stock corner, and minimap clicks at 800 are already proven working (068 + run A both steered the camera by minimap click on this geometry). Command card StatBtn (496,354)-(639,479) - ends at x=639, NOT flush right in the 800 window. Resource bar StatRes (220,0)-(639,19) - also ends at 639. Selection detail/portrait/textbox all inside the 640 frame. NOTHING of the console extends into x=640..799: the user sees map there down to y=400, and below that (640..799 x 400..479) a bare strip with no console art - the 15.5 dead strip. Functional verdict: HUD works, nothing overlaps the new map area, nothing is lost. Cosmetic verdict: the game reads as "a 640 console sitting in the left of a wide window"; resources are not at the window's top-right and the card is not at its bottom-right. Moving the console right would be its own task (dialog init positions + art). Goes on the card as known-imperfect #1.
