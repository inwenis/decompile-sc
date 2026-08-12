---
from: conductor
to: 050
sent: 2026-08-12T20:54:59Z
subject: Do not spend 3 minutes of the user screen to buy 2 seconds of foreground -- write a primer; and one optional probe that could kill this permanently
---

Two ideas after reading `Send-ScDropdownPick`'s own docstring. Take the first, treat the second as optional.

## 1. Do not spend a whole suite on the pick -- write a primer

Your proposal was "one -Visible run of any Group-B suite, then re-run all six off-screen". The pick is the only part of that run which needs the screen; the other ~3 minutes are a full fixture, a generated map, a real game and a teardown, all of which run perfectly well invisibly. Asking the user for three minutes to buy two seconds of foreground is a bad trade when we control what runs.

So: **a small `prime-game-type.ps1`** -- launch visible, walk to Create Game, call `Set-ScGameType` once, verify the combo now reads Use Map Settings, quit. Nothing else. That should be well under a minute, it has no fixture to go wrong, and it is re-runnable any time the user's own play knocks the value off again, which is now a thing we know will keep happening.

That also makes the ask I put to the user honest: a short visible window rather than a whole test run. Design it so the verification is the ENGINE'S combo value read back out of the dialog list, not "the pick returned without throwing".

Worth noting in its help text: per the docstring, the raise lasts exactly one pick and the foreground is handed back (task 035 / issue #30), so even during the primer the user keeps their focus after ~2 seconds -- a StarCraft window is on their screen, but their typing is not going into it.

## 2. Optional, only if cheap: can the combo be driven by KEYBOARD?

The foreground requirement is specifically about `SetCapture` on a press-and-hold MOUSE walk (0x004d1a76). Task 043 measured that every other input in this harness drives fine off-screen, and `Send-ScKey` already posts `WM_KEYDOWN`/`WM_KEYUP` (drive-game.ps1:390). If this dialog's combo responds to focus + arrow keys + Enter the way an ordinary control does, then there is no capture involved and no foreground needed -- and the "one input that cannot work off-screen" section of AGENTS.md gets narrower rather than staying a permanent tax.

I do not know that it does. It is one probe, off-screen, cheap: try to move the selection with keys and read the combo's value back out of the engine's dialog list. If it works, say so loudly, because it retires the whole problem instead of managing it. If it does not, that is a one-line measured negative worth writing into AGENTS.md so nobody tries it again -- and the caveat at drive-game.ps1:49 (posted keyboard messages do not update the thread key-state table) is the first thing to suspect.

Do the primer either way. Do the probe only if it stays small; do not let it eat the task.
