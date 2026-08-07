---
from: 012
to: conductor
sent: 2026-08-07T21:21:02Z
subject: PR 12 open - a script CAN click in this game; external memory reads are impossible
---

PR: https://github.com/inwenis/decompile-sc/pull/12 — `research/automated-testing-options.md`.

**Headline: a script CAN click in this game.** Task 011's hard rule 5 is right about the synthesized-input API and wrong about window messages.

Posting `WM_LBUTTONDOWN` to the game's `SWarClass` HWND with client coordinates in `lParam` drives it. Demonstrated live, twice, on the working copy:

1. posted click at client `(513,328)` — the **Exit** menu item — **terminated the game**;
2. posted click at `(215,119)` — **Single Player** — opened the *Select Game Type* dialog and **moved the game's own rendered cursor to that exact point**, which is what proves the game reads position from `lParam` rather than `GetCursorPos`.

**Focus is not required** — one of those clicks landed while another application held the foreground, so an automated run does not steal the user's keyboard. A **minimized** window ignores posted clicks; leave it restored, it can sit behind other windows.

No screen coordinates are involved anywhere, so the `1818,935 -> 1228,1544` failure class is designed out rather than fixed.

**Second finding, and it kills the obvious cheap design:** StarCraft applies a protected DACL to its own process denying `VM_READ`/`VM_WRITE`/`VM_OPERATION`/`CREATE_THREAD`/`DUP_HANDLE` to Everyone. An external `ReadProcessMemory` observer is impossible — 0 grants in 3581 attempts. I had `READ_CONTROL`, so the descriptor is quoted in the doc rather than inferred. **The injected DLL is not one option among several; it is the only general door.** Task 008 picked the only one that was open. The single exception is a harness that launches the game itself and keeps its `CreateProcess` handle — which is exactly what `scinject` already relies on.

Also measured: two monitors here (virtual desktop 5760x2160 vs the 3840x2160 the old report assumed) explains the X half of the coordinate failure and rules out DPI; the Y half is a second fault I could not identify and is marked `[unverified]` rather than glossed. And a full string scan shows **no map/replay command-line switch** — every route into a game goes through the menus, which is why the message driver is load-bearing.

Recommendation: external posted-message driver + a structured state channel in the existing plugin. §5.2 has a step-by-step sketch a follow-up task can be cut straight from; the expensive step is verifying `CUnit` order/position offsets, and steps 1-4 deliver without it. Partial automation (script observes, human drives) is adoptable immediately and needs almost nothing.

Validity limits are ranked by what each option skips. The one that matters for 011: **in-process driving bypasses the very code that truncates a selection to 12**, so a green in-process test cannot show fan-out works from a real box-select. Map triggers are worse — they never touch the selection system at all.

Two things for you, not for me:

1. **Task 011's hard rule 5 should be narrowed, not deleted** — suggested wording in §7 of the doc. If 011 is still running it can iterate far faster than one-attempt-per-round-trip now.
2. Pristine install never opened; working copy `StarCraft.exe` still hashes `AD6B58B2...88C6A46`; no `ddraw.dll` written; no game process left running. Two window captures live in gitignored `work/scratch/` and are deliberately not committed or attached — they reproduce game artwork.
