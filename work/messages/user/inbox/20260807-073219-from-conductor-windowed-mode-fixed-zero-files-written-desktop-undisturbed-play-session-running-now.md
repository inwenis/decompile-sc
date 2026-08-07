---
from: conductor
to: user
sent: 2026-08-07T07:32:19Z
subject: WINDOWED MODE FIXED - zero files written, desktop undisturbed; play session running now
---

**Windowed mode works. Your desktop will not be disturbed.**

The hypothesis paid off in one run. `WMode.dll` is not a DirectDraw proxy at all — it is an injectable hook DLL. Injecting it into the suspended process before the game starts, instead of copying it in as `ddraw.dll`, gives:

  desktop stays 3840x2160    (no resolution switch)
  real 650x517 game window   (not borderless-fullscreen, not minimized)
  no error dialogs
  main menu reached, v1.16.1
  ddraw.dll ABSENT           (nothing written into the game directory at all)

That last line is the bit I like most: this is strictly better than the old recipe even if the old one had worked. The game directory stays byte-identical to your pristine install, so windowed mode now costs zero files. Nothing to clean up, nothing to reset.

**And it is another correction to our own merged research.** `launch-baseline.md` says to copy the helper in as `ddraw.dll`. That is wrong, not merely mis-executed — a DLL with no export table can never satisfy the game's `GetProcAddress` call. Being written up with both run tables as evidence. That is now the second false conclusion in that document, both from the same overnight task; I will treat its remaining claims with more suspicion.

## The play session is happening now, in that window

The worker is proceeding straight into it — no interruption needed since the desktop is untouched.

**If you would rather drive it yourself, say so and I will have the worker hand you the controls.** A human selecting units is stronger verification than synthetic clicks, and you would get to watch the plugin read the selection live. Otherwise it will drive itself and report. Either is fine — just do not both drive at once, so tell me before you grab the mouse.

What it is checking: select one unit, select several, box-select a group, and confirm the values our plugin reads from memory track exactly what is highlighted on screen. If our address map is wrong anywhere, this is where it shows up — cheaply, read-only, before anything writes.
