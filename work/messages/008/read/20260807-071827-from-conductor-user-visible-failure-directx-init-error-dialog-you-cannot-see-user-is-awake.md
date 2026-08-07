---
from: conductor
to: 008
sent: 2026-08-07T07:18:27Z
subject: USER-VISIBLE FAILURE: DirectX init error dialog you cannot see + user is awake
---

USER-OBSERVED FAILURE — you cannot see this from your side, so read carefully.

The user is AWAKE and sitting at this machine right now (that changed since your task was written). They watched your test and reported:

  "the application opened meaning Starcraft opened and it closed and then I got some
   arrow window saying the direct X was unable to initialise something"

So: StarCraft launched, exited, and a GUI error dialog appeared saying DirectX could not initialise. That dialog is invisible to you — you would only see the process exit. Do not conclude "the process ran and exited cleanly" from exit codes alone.

What I observe from the conductor side:
1. `C:\sc-work\1161-base\ddraw.dll` is 35,812 bytes — byte-identical in size to `WMode.dll` in the same folder, with WMode's original timestamp. So the `ddraw.dll` slot currently holds a copy of the windowed-mode helper.
2. That is exactly the conflict called out in your task Context: `ddraw.dll` is a SINGLE slot, and both windowed mode and any proxy of yours want it. If your DLL takes the slot without forwarding, DirectDraw never initialises — which matches the reported symptom precisely. If WMode occupies it, your code never loads.
3. A StarCraft process (pid 19228) was live 30 seconds old when I checked. I deliberately did NOT kill it, since it is your active test.

Required adjustments:

1. **Resolve the slot conflict properly, do not work around it.** Either your proxy chain-loads (forward to the real 32-bit `ddraw.dll` in `SysWOW64`, and/or to `WMode.dll`), or you pick a vector that does not consume the slot at all (start the process suspended and inject, for instance). Your task says to prefer whichever keeps windowed mode working, and to justify the choice. That decision is now load-bearing, not theoretical.
2. **Verify from OUTSIDE the process, not just from exit codes.** After each launch attempt, check whether an error dialog window exists (enumerate top-level windows / look for a dialog class) before declaring the run good. A silent exit plus a modal dialog is your current failure mode and you are blind to it.
3. **The user is at the keyboard.** Keep tests SHORT, always windowed if you can get windowed working, never leave a process running, and do not spam repeated launches. A fullscreen window stealing the display is disruptive now in a way it was not overnight.
4. Reset the working copy between attempts (`tools/make-working-copy.ps1 -Force`, ~3s) so you are never debugging on top of a previous experiment's leftovers — the stray `ddraw.dll` above is exactly that class of problem.

Nothing about your acceptance criteria changes. Report progress or blockers; if the injection vector turns out to need a decision I should make, ask rather than burning attempts.
