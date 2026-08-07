---
from: conductor
to: 011
sent: 2026-08-07T21:28:23Z
subject: PASSED - user says run A 12 moved, run B ALL moved. Finalise PR #11.
---

**THE TEST PASSED.** User's report, verbatim, sent 2026-08-07T21:21:40Z:

    run a - 12 moved
    run b - all moved

That is stage D. Put it in the PR body — criterion 4 requires the user's own account, not your logs.

I cross-checked it against your run-B log independently before believing it, and the two agree:

    SHADOW captured: 24 units (12 visible + 12 beyond the cap)
    FANOUT start: units=24 (visible 12 + overflow 12) -> 2 Select+order pairs
    FANOUT done: 2/2 chunks emitted, 72 bytes this turn
    STATS mode=fanout fanouts=4 pairs=8 deferred=0 staleSkipped=0

Four orders, eight pairs, nothing deferred and nothing skipped as stale. 72-74 bytes per turn against a 200-byte budget, so it stayed well inside the command-buffer limit rather than getting lucky. The control run matters as much as the treatment: an identical setup in observe mode moved 12, so "all moved" is attributable to the plugin and not to the map.

**Finalise the PR now:**

1. Quote the user's result verbatim, and note the map was `(1)Enslavers02b` with 24 units captured — NOT the 36-Marine map, which the game rejected as corrupt.
2. State the honest limits: this is one map, one order type pair (0x14/0x15), 24 units, single-player, one human run. Do not let a passing test imply more coverage than it has.
3. Keep whatever you already wrote about orders whose semantics depend on the whole selection — that remains untested.

**Also: hard rule 5 in your task file is now WRONG and is narrowed.** Task 012 proved a script CAN drive this game — not via `SendInput`, but by posting `WM_LBUTTONDOWN`/`WM_MOUSEMOVE` to the game's own HWND with client coordinates in `lParam`. Demonstrated live twice, focus not required, no screen coordinates involved at all, so the coordinate-failure class is designed out rather than patched. Replace rule 5 with 012's wording:

    Do not use SendInput/SendKeys (banned by config/guard-destructive.ps1).
    Posting window messages to the game's own HWND is permitted and works
    -- see research/automated-testing-options.md 4.1.

You do not need to build a driver in this PR. But stop treating one-attempt-per-round-trip as a constraint in anything you write from here.
