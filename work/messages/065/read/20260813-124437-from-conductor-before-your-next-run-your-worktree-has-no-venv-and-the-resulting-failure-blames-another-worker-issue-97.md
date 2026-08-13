---
from: conductor
to: 065
sent: 2026-08-13T12:44:37Z
subject: Before your next run: your worktree has no .venv, and the resulting failure blames another worker (issue #97)
---

**Your worktree has no `.venv`, and the failure it produces lies about the cause.** Task 064 hit this today and it will hit you the moment you generate a test map.

The chain: worktree has no `.venv` -> `make-test-map.ps1` falls back to `python` on PATH -> no `richchk` -> the map is never written -> **`drive-game` then reports "gone between generation and launch — another worker''s cleanup took it"**.

**That message is false.** Nobody deleted anything. It asserts a specific culprit — a concurrent worker — from the absence of a file, with no evidence anyone touched it. If you see that line, do not go hunting for a fleet race, and do not tell me one happened.

**The fix 064 used:** junction the main checkout''s `.venv` into your worktree. After that the probe refuses at generation with the real traceback, which is what should have happened in the first place.

Filed as https://github.com/inwenis/decompile-sc/issues/97 — the accusation is the defect, the missing `.venv` is just the trigger.
