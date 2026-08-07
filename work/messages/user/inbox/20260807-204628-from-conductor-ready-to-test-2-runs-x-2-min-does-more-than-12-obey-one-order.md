---
from: conductor
to: user
sent: 2026-08-07T20:46:28Z
subject: READY TO TEST: 2 runs x 2 min - does more than 12 obey one order?
---

**Ready to test. Two runs, about two minutes each, identical actions — one word differs.**

Run A is the control (proves the off switch AND shows you stock behaviour). Run B is the real thing. Doing both matters: without A, "36 moved" could be explained by the map rather than by us.

I verified before sending this: your pristine install is untouched, and the working copy's StarCraft.exe is **byte-identical to pristine** — nothing is patched on disk, it is all in-process memory.

---

## RUN A - control

From `C:\git\decompile-sc-task011`:

```
./tools/plugin/run-with-plugin.ps1 -Mode observe -InjectWindowedHelper WMode -LogPath C:\sc-work\logs\task011-A-observe.log
```

1. Game opens in a small window. **Single Player -> Expansion -> Play Custom -> `test-many-units.scx`** -> start.
2. You should see **36 Marines** in a block.
3. **Drag a box around all 36.**
4. **Right-click far away.**
5. **Count roughly how many actually walk.** Expected: **only 12.**
6. Quit properly (Esc -> Quit -> Exit Game) rather than killing it — the plugin writes its summary on the way out.

## RUN B - the real test

Same thing, one word changed (`observe` -> `fanout`):

```
./tools/plugin/run-with-plugin.ps1 -Mode fanout -InjectWindowedHelper WMode -LogPath C:\sc-work\logs\task011-B-fanout.log
```

Repeat steps 1-6 exactly.

---

## What success looks like

**All 36 walk, while the portrait row at the bottom still shows only 12.** That combination is the point — 12 are *selected*, the other 24 obey anyway. It is the same signature the two closed-source hacks we found were described as having.

Partial success (say 24 of 36 move) is still a real result; the logs will show which chunk was dropped.

**Expected and NOT failures:** the selection sound firing more than once, the portrait row showing 12, and the group setting off in two visible waves.

## Tell me afterwards

1. Run A - how many moved?
2. Run B - how many moved? (rough is fine: "all", "about half", "12")
3. Anything wrong — crash, freeze, error box, odd behaviour?
4. Did the map load cleanly?

No screenshot needed. The logs are written automatically and I read those myself — what I cannot get any other way is your account of what happened on screen.

## If run B misbehaves

Just close the game. There is nothing to uninstall — nothing was copied into the game folder and nothing on disk was patched. Launching StarCraft.exe directly, or re-running with `-Mode observe`, gives you a stock client.

**If the map does not load, stop and tell me** rather than spending your second run — that is a finding on its own and I would rather fix it than waste your time.
