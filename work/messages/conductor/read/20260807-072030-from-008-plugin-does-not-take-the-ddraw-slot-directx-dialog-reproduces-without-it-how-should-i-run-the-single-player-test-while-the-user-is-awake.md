---
from: 008
to: conductor
sent: 2026-08-07T07:20:30Z
subject: Plugin does NOT take the ddraw slot; DirectX dialog reproduces without it. How should I run the single-player test while the user is awake?
type: question
options: Run one short fullscreen session now (~4 min, desktop drops to 640x480); Build a chain-loading ddraw proxy first to try to get windowed working; Defer the play session until the user is away
---

Acted on your message immediately: **no StarCraft process is running** and the working copy
is **reset and hash-verified** (`make-working-copy.ps1 -Force`, 242 files, purged the stray
`ddraw.dll`). Sorry the user saw that dialog.

One correction to your diagnosis, because it changes what the fix is.

## My plugin never takes the `ddraw.dll` slot

I picked the non-slot-consuming vector before any of this: a 32-bit launcher
(`scinject.exe`) that does `CreateProcess` -> `WaitForInputIdle` ->
`CreateRemoteThread(LoadLibraryA)`. **Zero files are added to the game directory.** Uninstall
is "launch `StarCraft.exe` directly instead of through the script".

The `ddraw.dll` you saw (35,812 bytes = `WMode.dll`) was installed by the `-Windowed` switch on
my run script, which just replays the recipe already documented in
`research/launch-baseline.md`. It is the windowed-mode helper, not my DLL.

## The DirectX dialog is NOT caused by my plugin — it reproduces without it

I isolated it before your message arrived:

| run | `ddraw.dll` | plugin injected | result |
|---|---|---|---|
| 1 | absent | **yes** | launches, renders, **reaches main menu**, v1.16.1 on screen |
| 2 | `WMode.dll` | yes | DirectDraw error dialog |
| 3 | `WMode.dll` | **no** | **same DirectDraw error dialog** |
| 4 | `WMode_Fix.dll` | no | window stays minimized at the `-32000` sentinel |

Run 3 is the one that matters: plugin absent, same failure. The dialog text is
*"unable to initialize your video card using DirectX ... The specified procedure could not be
found"* from `ddraw_PC.cpp` line 113 `DirDrawInitBase` — i.e. `GetProcAddress` on `ddraw.dll`
failed. That is consistent with `launch-baseline.md`'s own observation that **`WMode.dll` has no
export table**: `storm.dll` does `LoadLibraryA("ddraw.dll")` then `GetProcAddress`, and a DLL
with no exports cannot satisfy it.

**So `research/launch-baseline.md`'s windowed-mode recipe does not actually work on this
machine.** Its evidence ("desktop resolution did not change") is equally consistent with
"DirectDraw never initialised at all". I will report that as a correction in my research doc —
it is a prior-research disagreement, not something I will smooth over.

## What already works

Plugin loads and runs inside the game (run 1, fullscreen, clean menu):

```
ATTACH pid=21392 tid=30764
  host exe      : C:\sc-work\1161-base\StarCraft.exe
  module base   : 0x00400000
  preferred base: 0x00400000
  reloc delta   : +0x00000000  => static addresses are USABLE VERBATIM
  image[0..1]   : 0x5A4D ('MZ' - mapped image confirmed)
OBSERVER start pollMs=250 (read-only; no writes to game memory)
```

Toolchain is installed and pinned (MinGW-w64 GCC 16.1.0 i686, SHA-256 verified, at
`C:\re-tools\...` outside every worktree); both artifacts verified `Machine=0x014C` / PE32.

## What I need from you

Only step 5 is left: actually play a little single-player and confirm
`clientSelectionCount`/`clientSelectionGroup` track the screen. **Fullscreen works today;
windowed does not, and did not before I started.** Fullscreen switches the desktop to 640x480
for the duration, which is disruptive now that the user is at the keyboard.

I have also added out-of-process dialog detection (enumerate top-level windows after each
launch) so I am no longer blind to a modal error, per your point 2.
