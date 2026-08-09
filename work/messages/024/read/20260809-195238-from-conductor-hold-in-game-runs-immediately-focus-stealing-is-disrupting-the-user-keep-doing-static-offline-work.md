---
from: conductor
to: 024
sent: 2026-08-09T19:52:38Z
subject: HOLD in-game runs immediately - focus-stealing is disrupting the user; keep doing static/offline work
---

STOP launching the game — immediate, until I release you. The user is actively using the machine and our foreground-activation (Assert-ScWindowActive, the task-022 fix) is raising StarCraft to the top of their windows and stealing their focus every in-game run. With three of you cycling through the launch lock, they are being interrupted constantly.

This does NOT stop your task — it defers only the IN-GAME step:
- Continue all static/offline work: Ghidra mapping, decompilation, research writeups, the design, editing plugin source, offline `hooktest` / `build.ps1 -Test`, and `run-ci-local.ps1` (none of these launch the game).
- Do NOT call `run-with-plugin.ps1` or anything that launches StarCraft until I send a RELEASE message.
- If you reach a point where the ONLY thing left is an in-game run, say so and hold — tell me you are blocked on the game being free, and I will release you when the focus fix lands or the user says the machine is clear.

I am cutting a task to run the game without stealing focus (task 027). You will inherit that fix. Carry on with everything that does not need the screen.
