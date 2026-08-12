---
from: conductor
to: user
sent: 2026-08-12T20:55:46Z
subject: Correction to the question I just sent: under a minute, not three, and it does not steal your keyboard
---

The question I just sent you overstated the cost. Read this before you answer it — the ask is smaller than I made it sound, in two ways.

## It is under a minute, not three

I asked for "three minutes with StarCraft on your screen" because 050's plan was to run a whole test suite visibly. But only one step of that run — the dropdown pick — needs the screen at all. The other three minutes are a generated map, a real game and a teardown, all of which run perfectly well invisibly.

So I have told 050 to build a small primer instead: launch, walk to the Create Game screen, make the one pick, check the engine's own combo value, quit. Nothing else. Well under a minute, and re-runnable whenever your own play knocks the setting off again — which we now know will keep happening.

## It does not steal your keyboard

`Send-ScDropdownPick` raises the window for exactly the length of one pick and then hands the foreground back to whatever had it (task 035, issue #30). So during the primer a StarCraft window appears on your screen, takes focus for about two seconds, and gives it back. Whatever you are typing in goes back to being where your typing goes. It is a window appearing, not a hijack.

## And there is a chance this goes away entirely

The reason the pick needs the screen is narrow: the game calls `SetCapture` when you press and hold the mouse on that control, and Windows only grants capture to the foreground window. Every other input in our harness — including keystrokes — already works fine on the invisible desktop.

Which raises a question nobody has asked: **can that dropdown be driven with the keyboard instead?** Arrow keys and Enter involve no capture. If it works, the "one input that cannot run off-screen" rule stops being permanent and this whole problem disappears rather than being managed forever. I have asked 050 to spend one cheap probe on it — and to write the answer into the rulebook either way, so nobody re-derives it.

## So the options on the previous message still stand, just cheaper

Answer it whenever. If you pick "wait for 23:00" nothing is lost; the primer will be built by then anyway and it will take under a minute when it runs.
