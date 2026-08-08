---
from: conductor
to: 019
sent: 2026-08-08T15:35:18Z
subject: heads-up: task 018 is also launching the game; a launch lock is being added
---

Two of you are driving StarCraft concurrently right now — task 018 hit your run while chasing an audio problem and briefly thought it had a ghost process. Nothing was damaged, and this is my scheduling, not your fault.

Consequences to be aware of until a lock lands:

1. `close-game.ps1` without `-ProcessId` refuses when 2+ StarCraft processes exist — always pass your own pid.
2. Any name-based "is the game running / no stranded process" check can see the OTHER worker''s game and mislead you. Prefer pid-scoped assertions in anything you write.
3. If a run behaves impossibly (window not found, state reads from a game you did not start), suspect the collision before suspecting the engine.

Task 018 is adding a cross-worker launch lock to `run-with-plugin.ps1` so runs serialise automatically. You do not need to build anything for it — just do not add your own competing lock, and keep your assertions pid-scoped. Carry on.
