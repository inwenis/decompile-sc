---
from: 011
to: conductor
sent: 2026-08-07T20:45:24Z
subject: USER TEST NEEDED: fan-out A/B, 2 runs x ~2 min
---

Task 011 (fan-out) is built and needs the human test. **Two runs, ~2 minutes each, identical
actions** — the only difference is one flag. Run A is the control that proves the off switch;
run B is the real thing.

Everything is offline single-player on the working copy `C:\sc-work\1161-base`.
`C:\sc-install\Starcraft` is never touched, and `StarCraft.exe` on disk is byte-identical to
pristine before and after (SHA-256 `AD6B58B2…88C6A46`, verified).

---

## Run A — control (plugin passive, should behave exactly like stock)

1. From `C:\git\decompile-sc-task011`:

```powershell
./tools/plugin/run-with-plugin.ps1 -Mode observe -InjectWindowedHelper WMode -LogPath C:\sc-work\logs\task011-A-observe.log
```

2. The game opens in a ~650x517 window. Menus: **Single Player → Expansion → Play Custom**,
   pick **`test-many-units.scx`**, start the game.
   - If that map is missing or refuses to load, stop here and tell me — that is a finding by
     itself and I will fix the map rather than burn your second run.
3. You should see **36 Marines** in a block.
4. **Drag a box around all 36.** The wireframe row at the bottom will show 12 — that is expected
   and stays true in both runs.
5. **Right-click far away**, somewhere the whole group has to walk to.
6. **Watch how many Marines actually move.** Expected here: **only 12** (stock behaviour).
7. Quit the game (Esc → Quit → Exit Game). Please quit rather than killing it — the plugin writes
   its closing summary on the way out.

## Run B — fan-out (the real test)

8. Same command with **one word changed**:

```powershell
./tools/plugin/run-with-plugin.ps1 -Mode fanout -InjectWindowedHelper WMode -LogPath C:\sc-work\logs\task011-B-fanout.log
```

9. **Do exactly the same steps 2–7.**

(If you want to rebuild first: `cd C:\git\decompile-sc-task011; ./tools/plugin/build.ps1 -Test`.
Not needed — it is already built.)

---

## What success looks like

- **Full success:** in run B **all 36 Marines walk to the point**, while the wireframe row still
  shows only 12. The 12 shown are selected; the other 24 obey anyway. That "circles capped at 12,
  everything obeys" signature is exactly what the two closed-source 1.16.1 hacks in
  `research/selection-cap.md` §5 were described as doing.
- **Partial success:** more than 12 move but not all 36 (e.g. 24 of 36) — still a real result,
  and the logs will say which chunk was dropped.
- **Failure:** still only 12 move, or the game misbehaves.

Cosmetic things that are expected and are NOT failures: the unit-select sound may fire more than
once, the wireframe row still shows 12, and the group may set off in two visible waves.

## What to tell me afterwards

1. Run A: how many Marines moved?
2. Run B: how many Marines moved? (A rough count is fine — "all of them", "about half", "12".)
3. Did anything look wrong — crash, freeze, error box, units doing something odd?
4. Did the map load cleanly?

I do **not** need a screenshot (it would be game artwork, which we do not commit). The logs at
`C:\sc-work\logs\task011-A-observe.log` and `…-B-fanout.log` are written automatically and I will
read them myself — your account of what you saw on screen is the part I cannot get any other way,
and it is what goes in the PR.

## If run B misbehaves

Close the game. There is nothing to uninstall: the plugin is never copied into the game folder and
never patches `StarCraft.exe` on disk — all of it is in-process memory. Launching
`C:\sc-work\1161-base\StarCraft.exe` directly, or re-running with `-Mode observe`, is a stock
1.16.1 client.

---

### What is already proved without the user (so you know what this run is and is not for)

- The detour engine passes 30/30 checks in an offline unit test against three functions whose
  prologues match the three real StarCraft ones byte for byte (`build.ps1 -Test`, no game
  involved).
- All four hooks install into the live game with their expected prologue bytes, the game reaches
  the main menu, and it exits cleanly — I ran that unattended and closed it afterwards.
- What only a human can produce is units moving on screen.
