# Launch baseline

Working copy: `C:\sc-work\1161-base` (created/verified by `tools/make-working-copy.ps1`,
see Context in `work/tasks/002-working-copy-baseline.md` for the pristine fingerprint it's
checked against). All testing below was done offline, single-player scope only: no
Battle.net connection, no CD key entry, no multiplayer.

## Does it launch from the copy?

**Yes**, directly, with no modification needed.

- Command: `C:\sc-work\1161-base\StarCraft.exe` (working directory = its own folder;
  no arguments).
- Verified via `Start-Process -FilePath 'C:\sc-work\1161-base\StarCraft.exe' -WorkingDirectory 'C:\sc-work\1161-base' -PassThru`,
  polled with `Get-Process` for up to ~15s, then terminated with `taskkill /PID <pid> /F`
  (`Stop-Process -Force` returned "Access is denied" against this process — cause not
  investigated further, `taskkill` worked every time and every launch in this session was
  confirmed terminated by re-checking `Get-Process` afterward).
- Result: process `StarCraft.exe` came up, main window title **"Brood War"**, `Responding =
  True`. No CD-key dialog, no online-activation prompt, no crash/error dialog.
- No CD key was needed. Evidence: `patch.txt` in the install states *"StarCraft and
  StarCraft: BroodWar no longer require the CD while playing the game"* as of the 1.16.1
  patch, and `SFNoCD.dll` (Blizzard's own official no-CD component for that patch, not a
  third-party crack) ships in the install directory.

## Registry dependency

Read-only inspection (never wrote to the registry):

- `HKLM:\SOFTWARE\WOW6432Node\Blizzard Entertainment\Starcraft` already exists (from the
  original installer of the pristine copy) with `InstallPath` / `Program` pointing at
  `C:\sc-install\Starcraft` — i.e. the **pristine** path, not the working copy.
- `HKCU:\SOFTWARE\Blizzard Entertainment\Starcraft` holds gameplay preferences (gamma,
  scroll speed, volume, etc.), not tied to any install path.
- No `CDKey`/activation value was found in either key.
- The working copy launched fine despite `HKLM` pointing at a *different* directory —
  `StarCraft.exe` resolves its own MPQs/assets relative to itself (its own directory), not
  via the registry `InstallPath`. That value appears to matter only for auxiliary features
  (e.g. the map editor's "recent maps" list uses paths under the registered install).
- **Caveat / not tested**: this session never had a truly registry-free environment to test
  against, since deleting the pristine install's own registry entries was out of scope
  (touches the user's real, playable install's config, not just files — treated as
  off-limits under the same spirit as "never modify the pristine install"). So "no registry
  writes needed" is confirmed for *this* machine, which already has Blizzard registry keys
  from a prior install; whether a from-scratch machine with zero prior SC registry state
  also launches cleanly is unverified.

## Windowed mode (WMode.dll / WMode_Fix.dll)

**Achievable**, tested empirically in the working copy only (pristine install untouched).

Both `WMode.dll` and `WMode_Fix.dll` have no export table and a tiny KERNEL32-only-ish
import set (`LoadLibraryA`/`GetProcAddress`/`VirtualProtect`/`VirtualAlloc`) with high
section entropy — `pefile` flags both as showing signs of a packed/self-unpacking
executable (see `research/pe-anatomy.md`-style analysis via `tools/pe_report.py`). That
means static analysis alone can't show how they hook DirectDraw; behavior below is from
actually running them.

**Tested recipe**: copy one of them to `ddraw.dll` next to `StarCraft.exe` in the working
copy (`storm.dll` loads `ddraw.dll` dynamically via `LoadLibraryA`, not a static import, so
Windows' "check the app directory first" DLL search order picks up the local copy):

```powershell
Copy-Item C:\sc-work\1161-base\WMode.dll C:\sc-work\1161-base\ddraw.dll -Force
Start-Process C:\sc-work\1161-base\StarCraft.exe -WorkingDirectory C:\sc-work\1161-base
```

Result with `WMode.dll` as `ddraw.dll`:
- The desktop resolution **did not change** (stayed at native 3840x2160 the whole time).
  Contrast with the unmodified baseline launch, where the desktop was measurably switched
  to 640x480 for the duration (`GetWindowRect` on the game window returned `0,0-640,480`
  matching `Screen.PrimaryScreen.Bounds` at the time). This is the actual evidence that the
  DirectDraw exclusive-mode path is being intercepted rather than a guess.
- The game window came up **minimized** (`GWL_STYLE` had `WS_MINIMIZE` set, window rect at
  the Windows off-screen sentinel position `-32000,-32000`). Sending `ShowWindow(hwnd,
  SW_RESTORE)` via a P/Invoke call brought it to a normal, visible, borderless window
  covering the full desktop (`0,0-3840,2160`, `WS_POPUP` with no `WS_CAPTION`/`WS_BORDER`)
  — i.e. a borderless-window mode scaled to the desktop, not a bordered/resizable window
  smaller than the screen, and not an exclusive fullscreen mode switch.
- `WMode_Fix.dll` used alone as `ddraw.dll` also loads successfully (window title "Brood
  War" appeared immediately, `Responding = True`) but its window geometry/minimize state
  was not separately measured in this session — open follow-up for whoever automates this
  further. Given its single `USER32.dll` import is `FindWindowA`, a plausible read is that
  it's meant to locate and fix up the game window from a second process/injection rather
  than function as a passive drop-in `ddraw.dll` — not verified.

**Practical recipe for future windowed-mode use**:
1. `Copy-Item C:\sc-work\1161-base\WMode.dll C:\sc-work\1161-base\ddraw.dll -Force`
2. Launch `StarCraft.exe` as normal.
3. If the window is minimized on first appearance, restore it (click the taskbar icon, or
   `ShowWindow(hwnd, SW_RESTORE)` if automating).
4. To go back to a clean, pristine-mirroring working copy: delete `ddraw.dll`, or just
   re-run `tools/make-working-copy.ps1 -Force` (the `robocopy /MIR` purges anything not in
   the pristine source, including a leftover `ddraw.dll`).

All test launches were killed within the bounded wait (well under 30s) and confirmed gone
via a follow-up `Get-Process` check. The working copy itself was left in its clean,
`ddraw.dll`-free, hash-verified state (`tools/make-working-copy.ps1 -Force` was re-run after
these experiments to confirm — 0 files changed, all 242 files still hash/size-matched
source).

## How to iterate fast (for future patch tasks)

- `C:\sc-work\1161-base` is disposable and outside git — patch it freely.
- `tools/make-working-copy.ps1 -Force` resets it back to byte-identical-to-pristine in ~3
  seconds (`robocopy` measured ~350 MB/s on this machine for the 1.043 GB payload) and
  re-verifies both key-binary hashes plus whole-install file count/size.
- For windowed iteration (recommended over fullscreen — avoids the desktop resolution
  switch and its interaction with automation tooling/screenshots): drop `WMode.dll` in as
  `ddraw.dll` per the recipe above before each launch, or keep a second pre-patched copy of
  the working directory around if you don't want to redo the copy step each time.
- Always bound your wait and kill the process afterward — `Stop-Process -Force` was
  unreliable against this process (`Access is denied`) but `taskkill /PID <pid> /F` worked
  every time in this session.
