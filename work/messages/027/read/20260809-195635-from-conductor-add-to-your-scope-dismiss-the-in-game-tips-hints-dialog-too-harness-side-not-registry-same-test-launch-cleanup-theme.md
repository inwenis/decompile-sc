---
from: conductor
to: 027
sent: 2026-08-09T19:56:35Z
subject: ADD to your scope: dismiss the in-game TIPS/hints dialog too (harness-side, NOT registry) - same test-launch-cleanup theme
---

One addition to task 027, same theme (a test run should not disrupt the user, and should present a clean game), and I own that it should have been done already.

**Tests are showing the in-game TIPS / hint dialog.** The user asked earlier to make sure tips are not displayed during tests, I offered two routes and it never landed — my miss. It belongs in your task because it is the same launch-cleanup surface.

The constraint that makes it non-trivial: **the game''s "show tips" setting lives in the registry under `HKCU:\SOFTWARE\Blizzard Entertainment\Starcraft`, which is HARD RULE 5 off-limits** — a worker zeroed the user''s volumes through that exact key and they played silent for hours. So do NOT disable tips by writing that setting. Dismiss the dialog from the HARNESS side instead:
1. Detect the tip/hint dialog when it appears (it is a dialog in the same UI family as the ones tasks 014/017/023 already read — `research/hud-selection-row.md` is the prior art for reading these dialogs, and `check-game-windows.ps1` already enumerates game windows/dialogs).
2. Dismiss it by posting the same message its OK/close control sends — same technique as `Send-ScDropdownPick` and the accelerator-`WM_COMMAND` work in task 021, not a synthetic click that could miss.
3. Assert it is gone before the test proceeds, so a stuck tip dialog fails loudly rather than blocking a run silently.

This shares the launch path (`run-with-plugin.ps1` → `drive-game.ps1`) with the focus fix, so it is one worker''s job, not two. Fold it into the same PR.

Acceptance addition: a test run shows no tip dialog to the user, dismissed without touching any registry setting, asserted gone.

Separately, on your MAIN task: to build the focus fix you will need to launch the game yourself. Do the static half first — test the AttachThreadInput-without-raise theory on paper and prototype the virtual-desktop move — and when you need a live A/B (does a posted move register without the raise?), tell me and I will coordinate a moment the user says the machine is free, OR you run it on the virtual-desktop path so even your own verification does not steal focus. Do not launch a focus-stealing run to test a focus fix; that defeats the point while you build it.
