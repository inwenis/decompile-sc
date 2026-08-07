---
from: conductor
to: user
sent: 2026-08-07T21:14:41Z
subject: UNBLOCKED: use (1)Enslavers02b (22 units) - same two runs
---

**Unblocked — we have a map. Same two runs, one thing changed: which map you pick.**

`(1)Enslavers02b` — a stock Blizzard campaign map already in your install. You start with **22 Protoss units** (Zealots, Dragoons, Scouts, an Archon) in one tight cluster, and the nearest enemy army is far away.

## RUN A - control

```
cd C:\git\decompile-sc-task011
./tools/plugin/run-with-plugin.ps1 -Mode observe -InjectWindowedHelper WMode -LogPath C:\sc-work\logs\task011-A-observe.log
```

1. **Single Player -> Expansion (Brood War) -> Play Custom -> browse into the `campaign` folder -> `(1)Enslavers02b`** -> start.
2. There may be a short mission intro or camera pan first — wait it out, that is normal for a campaign map.
3. You should see a squad of ~22 Protoss units.
4. **Drag one box around as many as you can** (13+ is enough, all 22 is ideal).
5. **Right-click somewhere far away.**
6. **Roughly how many actually walk?** Expected here: about 12.
7. Quit properly: Esc -> Quit -> Exit Game.

## RUN B - the real test

Same thing, one word changed:

```
cd C:\git\decompile-sc-task011
./tools/plugin/run-with-plugin.ps1 -Mode fanout -InjectWindowedHelper WMode -LogPath C:\sc-work\logs\task011-B-fanout.log
```

Repeat steps 1-7.

**Success = all ~22 walk, while the portrait row at the bottom still shows only 12.**

## Then tell me

1. Run A: how many moved?
2. Run B: how many moved?
3. Anything odd — crash, freeze, error box?

Rough counts are fine. The logs record exact numbers; what I need from you is what the screen did.

---

Two things worth knowing about how we got here.

**The search was thorough, not lucky.** All 210 stock maps were scanned offline. **No standard melee or ladder map gives any player more than 12 mobile units** — melee starts are workers only, by design. Just two scripted campaign missions in the entire set clear the bar. The worker also caught itself: an earlier pass flagged a map with "36 units" that turned out to be 32 invisible trigger helpers, and it excluded them.

**Honest caveat:** nobody has loaded this map yet either. It is a Blizzard-shipped file rather than something we generated, so loadability is not really in question — but I am not going to claim it is proven when it is not. If it fails, that is one more data point and not your fault.
