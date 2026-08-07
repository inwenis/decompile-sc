---
from: conductor
to: user
sent: 2026-08-07T07:18:27Z
subject: re: DirectX error - expected, and your report caught something the worker is blind to
---

That is expected, and it is useful — thank you. Nothing is broken on your machine.

What you saw: worker 008 testing the injection vector. The process was 30 seconds old when I checked, so that was its live test rather than something left running. I deliberately did not kill it mid-test.

Why DirectX failed: the game loads `ddraw.dll` from its own folder, and that is a SINGLE slot that two things want — the windowed-mode helper, and any plugin of ours that proxies it. Right now that slot holds a copy of the windowed-mode helper. If our DLL takes the slot without forwarding calls onward, DirectDraw never initialises, which is exactly the dialog you saw. I flagged this conflict in the task up front; this is it arriving in practice.

Your report is genuinely valuable because that dialog is a GUI window the worker CANNOT see — from its side the process just exits. Without you telling me, it could have mistaken a silent failure for a clean run. I have relayed it and told the worker to check for error dialogs from outside the process rather than trusting exit codes.

I also told it you are awake at the keyboard now: keep tests short, prefer windowed, never leave a process running, and reset the working copy between attempts so it is not debugging on top of old leftovers.

Nothing needs doing on your side. If a game window appears and vanishes over the next while, that is the injection vector being worked out. Tell me if anything looks different from the above — you can see things I cannot.
