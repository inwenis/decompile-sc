# Fan-out A/B test plan (human-driven, map-agnostic)

A worker cannot reliably click in this game, so the final check is done by a person. This is the
script for that. **It names no map.** Any map works that satisfies the three requirements below, so
swapping the fixture is a parameter, not an edit.

Two runs, identical actions, one word different between them. About two minutes each.

---

## What the map has to provide

1. Loads in single-player on the working copy `C:\sc-work\1161-base`.
2. Gives the player **more than 12 units they own and can select together** — same-ish type,
   standing close enough to fit in one drag box. Marines, Zerglings, Zealots, SCVs: anything
   mobile.
3. No hostile pressure, or at least none in the first minute. The tester needs to watch units
   walk, not fight.

Nothing else matters. The test never asks how many units there are — the plugin logs that itself.

**Fill these in when sending the plan:**

| placeholder | meaning |
|---|---|
| `<MAP>` | the map to pick in the Play Custom dialog |
| `<HOWTO>` | anything unusual about reaching it (folder, expansion vs original, race choice) |

### Known-good fixture

`<MAP>` = **`(1)Enslavers02b`**, `<HOWTO>` = *Single Player → Expansion (Brood War) → Play Custom →
browse into `Maps\campaign\`*. Stock Blizzard map, so it is guaranteed loadable. The human is
**Player 2** (0-based slot 1, which matches the active-player id of 1 observed at runtime in
`research/runtime-selection-observations.md` §3.8) and starts with **22 mobile selectable units** —
12 Zealots, 4 Dragoons, 3 Scouts, 2 Observers, 1 Archon — packed into about 11×9 tiles, so one drag
box catches them all. Nearest hostile army is 44 tiles away.

At 22 units the fan-out is **2 pairs, ~68 bytes**: one `Select` of the 10 units past the cap plus
the order, then one `Select` of the visible 12 plus the order. Nowhere near any budget.

Two things to expect and not misread: it is a scripted campaign mission, so an intro cutscene or a
forced camera pan before control is handed over is normal; and a drag box takes every mobile unit
regardless of type, because the engine only applies a same-type filter to ctrl+click, not to a box.

Worth recording, from task 013's search: **no standard melee or ladder map gives any player more
than 12 real mobile units** — melee starts are 4–12 workers by design. Only two scripted campaign
missions in the whole 210-map stock set clear the bar. A future fixture is therefore a campaign map
or a generated one, not a ladder map.

### Result of the run (2026-08-07)

Run on this fixture, by the user: **run A moved 12, run B moved all of them.** Full success by the
table below.

One correction to the paragraph above, from the live run: the drag box captured **24** units, not
the 22 the static map read predicted — so the static count is a lower bound on what a box actually
takes, and the plan's rule of never asking the tester to count is the right one. 24 units is 2
pairs and 72–74 bytes.

---

## Run A — control: the plugin is passive

```powershell
cd C:\git\decompile-sc-task011
./tools/plugin/run-with-plugin.ps1 -Mode observe -InjectWindowedHelper WMode `
    -LogPath C:\sc-work\logs\fanout-A-observe.log
```

1. The game opens in a ~650×517 window.
2. **Single Player → Expansion → Play Custom**, choose **`<MAP>`**. `<HOWTO>`
3. Find the group of units you own.
4. **Drag a box around as many of them as you can — at least 13.** The wireframe row at the bottom
   of the screen will show 12. That is expected, in both runs, and stays true even when the feature
   works.
5. **Right-click somewhere far away**, far enough that walking there is obvious.
6. **Watch how many units actually move.** Expected in run A: **12**.
7. Quit properly (Esc → Quit → Exit Game) rather than killing the window — the plugin writes its
   closing summary on the way out.

## Run B — the feature

8. Same command, one word changed:

```powershell
./tools/plugin/run-with-plugin.ps1 -Mode fanout -InjectWindowedHelper WMode `
    -LogPath C:\sc-work\logs\fanout-B-fanout.log
```

9. Repeat steps 2–7 exactly.

---

## How to read the result

| outcome | meaning |
|---|---|
| **Run B moves everything you boxed, run A moves 12** | full success. The wireframe row still showing 12 is correct — the engine's cap is untouched; only 12 are *selected*, the rest obey anyway |
| Run B moves more than 12 but not all | partial. Real progress; the log says which chunk was dropped |
| Run B moves 12, same as run A | the fan-out did not fire. The log says whether the selection was captured and whether the order was recognised |
| Anything crashes or freezes | a bug worth more than the feature — say exactly when it happened |

Expected and **not** failures: the unit-select sound firing more than once, the wireframe row
capped at 12, only 12 selection circles drawn, and the group setting off in visible waves.

## What to report back

1. Run A: how many units moved?
2. Run B: how many units moved? A rough count is fine — "all of them", "about half", "12".
3. Anything that looked wrong.
4. Did the map load cleanly?

No screenshot: it would be game artwork, which this repo does not commit. The logs are written
automatically and the worker reads them. What cannot be recovered any other way is the tester's own
account of what happened on screen, and that is what goes in the PR.

## If it misbehaves

Close the game. There is nothing to uninstall — the plugin is never copied into the game folder and
never patches `StarCraft.exe` on disk. Launching `C:\sc-work\1161-base\StarCraft.exe` directly, or
re-running with `-Mode observe`, is a stock 1.16.1 client.

---

## What is already proved without a human

So the run is spent on the one thing only a human can show.

- **51 offline checks pass** (`./tools/plugin/build.ps1 -Test`, no game involved):
  - the detour engine, against three functions whose prologues match the real StarCraft ones byte
    for byte — including that a mismatched prologue is refused rather than patched;
  - the **whole fan-out core**, driven against a fake module image: 36 units and one right-click
    produce exactly 3 `Select`+order pairs, 108 bytes, with the correct unit tags, the visible
    chunk last, dead units dropped, spill-across-turns when the budget is small, and no silently
    swallowed order when the turn buffer is full.
- All four hooks install into the live game with matching prologue bytes, the game reaches the main
  menu and exits cleanly, and `StarCraft.exe` on disk is byte-identical before and after.

What no offline test can show is whether the **engine obeys** the commands. That is this run.
