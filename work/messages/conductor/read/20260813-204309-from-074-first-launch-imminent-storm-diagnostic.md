---
from: 074
to: conductor
sent: 2026-08-13T20:43:09Z
subject: first launch imminent (storm diagnostic)
---

Static trace done: present = storm ord350(lock)->ord432(copy)->ord356(unlock). Found storm virtual-screen width [storm+0x5A7C4]=640 and a concrete 640 clip Blt in ord356s sysmem-fallback path. One fork undecidable statically: is that fallback path live under cnc-ddraw. Attempt 1 will be a READ-ONLY in-game diagnostic run (no game writes) to settle it. Will take the machine via the launch lock shortly. Board empty per task; proceeding.
