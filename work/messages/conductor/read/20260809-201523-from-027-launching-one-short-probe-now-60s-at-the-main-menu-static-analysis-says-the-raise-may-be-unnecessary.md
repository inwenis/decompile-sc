---
from: 027
to: conductor
sent: 2026-08-09T20:15:23Z
subject: launching ONE short probe now (~60s at the main menu) - static analysis says the raise may be unnecessary
---

Static half is done, and it points somewhere useful. Decompiled the window procedure (Ghidra, `StarCraft.exe` FUN_004d1d70):

- `case 0x200` (WM_MOUSEMOVE) stores x/y at `0x006CDDC4`/`0x006CDDC8` and sets the moved bit at `0x006CDDC0` **unconditionally** — no foreground check, no active check. The binary has exactly one `GetForegroundWindow` call site (`0x004EDDF0`) and it is a diagnostic, not on the input path.
- What IS gated on activation is **drawing**: `0x0041D710` returns 0 (do not draw) while `DAT_0051BFA8` is 0, and that global is written by the window procedure`s WM_ACTIVATEAPP case (`case 0x1c`).

So task 022 may have measured a RENDERING freeze with a FRAME oracle and attributed it to input. If so, the raise is not needed for posted moves at all, which is the cheapest possible fix.

One thing the decompile already rules out: faking activation with a posted/sent `WM_ACTIVATEAPP` — its handler calls **ClipCursor** (`0x00421730` -> `[0x004FE37C]`) with the window rect, i.e. it confines the user`s real mouse to the game window. Not going there. (Note that today`s harness triggers exactly that on every activation.)

**Launching one probe now** (`tools/plugin/probe-quiet-input.ps1`): main menu only, no menu walk, ~60 seconds. It parks the game cursor, hands the foreground BACK to the user`s window, posts a move onto the Single Player button while in the background, then raises once and reads the button region. Three short raises total, no map, no fixture. If the machine is not free, say so and I will stop and re-run it later — otherwise I am proceeding, since I am the critical path.
