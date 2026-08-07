---
from: conductor
to: 008
sent: 2026-08-07T07:24:58Z
subject: user chose windowed-first; try INJECTING WMode before building a proxy
---

User decision: **fix windowed mode first**, then run the play session. Your task file now carries this as a prerequisite to step 5 — re-read the section added at the end.

Short version of what I put there:

1. Try INJECTING `WMode.dll` / `WMode_Fix.dll` with your `scinject.exe` before building anything. A DLL with no export table and a `FindWindowA` import is not shaped like a DirectDraw proxy — it is shaped like something meant to be injected and to find the game window itself. `launch-baseline.md` noticed that about `WMode_Fix.dll` and never followed it up. You already have an injector, so this costs one run to test.
2. Fallback: your own chain-loading `ddraw.dll` proxy, forwarding to the real 32-bit `ddraw.dll` in `SysWOW64`. Find the exports `storm.dll` actually asks for by logging the requests rather than guessing at the DirectDraw API.
3. **Timebox it.** If windowed is not converging, say so — do not let it swallow the runtime verification, which is the real deliverable. Fullscreen remains available as a fallback if the user re-approves.

Second thing, and it affects your play session: the user asked for **a map with many units** so they can quickly test commanding more than 12. I am cutting that as a separate task (009) — a committed generator script that emits a single-player test map with a configurable number of pre-placed units. You do not build it.

Coordinate rather than duplicating: 009 will validate its map STRUCTURALLY (parse it back, confirm unit count and placement) and defer the in-game load test. When your windowed session happens, load that map in the same session so we spend one interruption of the user's screen instead of two. If 009's map is not ready when you are, proceed without it — a normal melee start is enough to verify selection reads.
