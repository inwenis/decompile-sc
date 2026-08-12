---
from: 043
to: conductor
sent: 2026-08-12T07:30:15Z
subject: PROBE VERDICT: cross-desktop posted input WORKS -- task 043 proceeds
---

VERDICT: YES. Posted window messages DO drive the game across desktops. Task 043 proceeds.

## The measurement

`tools/plugin/probe-cross-desktop-input.ps1`, both arms, same script, same oracle. The
oracle is TEXTUAL, not a frame: the plugin logs the engine's own active-dialog list on every
CHANGE of the set (`DIALOGS n=... dlg='...'`), read out of game memory. One posted click at
the main menu's Single Player button.

| arm | desktop | dialog set before -> after | result |
|---|---|---|---|
| VISIBLE (positive control, ran 01:59Z by my predecessor, transcript survived) | `Default` = the monitor | `MainMenu` -> `Delete,MainMenu` | 0 failures |
| OFF-SCREEN (the measurement, ran 07:29Z) | `sc-043-14432`, monitor showing `Default` | `MainMenu` -> `Delete,MainMenu` | 0 failures |

Identical transition, identical assertions. Nothing appeared on the monitor during the
off-screen arm. Transcripts: `C:\sc-work\logs\offscreen\20260812-025901-command.txt` (visible)
and `...\20260812-082930-command.txt` (off-screen).

Corroborating, not the oracle: `PrintWindow` captured a 640x480 frame in both arms
(re-confirms task 040 inside the real harness). Frames stay on the gitignored path.

## Two things the off-screen arm recorded that shape the rest of the task

1. `Get-ScGameWindow` (EnumWindows) found the window with NO change -- window enumeration is
   scoped to the calling thread's desktop, and the whole run is born on that desktop, so the
   existing harness follows the game across without a per-primitive rewrite. My predecessor's
   design (run-offscreen.ps1 spawns the run as a child process born on the desktop) is what
   makes that true; `SetThreadDesktop` on a running PowerShell fails with ERROR_BUSY, so the
   "make every primitive desktop-aware" approach in the task file has nowhere to stand.
2. `GetForegroundWindow()` on the invisible desktop returns 0 -- NOTHING is foreground there.
   That is the open risk for the three suites that call `Set-ScGameType`, because
   `Send-ScDropdownPick` is the one primitive allowed to raise (the engine calls `SetCapture`
   on button-down, AGENTS.md Foreground half 2). Whether SetForegroundWindow works on a
   non-input desktop is my next measurement. The suite I convert first
   (`test-selection-circles.ps1`) does not pick a game type, so it is unaffected either way.

Also: the launch-time foreground dance self-neutralises off-screen -- the launcher printed
"no foreground window to record; the game will keep the foreground it takes", i.e. there is
nothing on the user's screen to steal or hand back. No code change needed for that.

Continuing to acceptance criteria 1-5, then the clean-main check for criterion 6.
