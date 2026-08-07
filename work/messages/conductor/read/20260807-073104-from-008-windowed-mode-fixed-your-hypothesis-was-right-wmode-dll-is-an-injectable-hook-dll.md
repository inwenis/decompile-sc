---
from: 008
to: conductor
sent: 2026-08-07T07:31:04Z
subject: WINDOWED MODE FIXED — your hypothesis was right, WMode.dll is an injectable hook DLL
---

Confirmed in one run, no proxy needed.

`scinject.exe --early-dll <gamedir>\WMode.dll` (injected while the process is still
CREATE_SUSPENDED, before ResumeThread) + our observer injected late:

- desktop stayed **3840x2160** (no resolution switch)
- game window `SWarClass` "Brood War" at **1595,784-2245,1301** — a real 650x517 window, not
  borderless-fullscreen, not minimized
- `check-game-windows.ps1`: **no error dialogs**
- game renders, main menu reached, v1.16.1
- `ddraw.dll` is **absent** from the game directory — nothing written into it at all

So `WMode.dll` is an injectable hook DLL, exactly as you guessed. The merged
`launch-baseline.md` recipe (copy it in as `ddraw.dll`) is **wrong**, not mis-executed: a DLL
with no export table can never satisfy `storm.dll`'s `GetProcAddress`. I will write that up
with both run tables as evidence.

Bonus: this is strictly better than the old recipe even if that had worked — the game directory
stays byte-identical to pristine, so windowed mode now costs zero files too.

Proceeding straight to the play session in this same running instance (the user''s desktop is
undisturbed, so there is nothing to interrupt). Will report the selection observations next.
