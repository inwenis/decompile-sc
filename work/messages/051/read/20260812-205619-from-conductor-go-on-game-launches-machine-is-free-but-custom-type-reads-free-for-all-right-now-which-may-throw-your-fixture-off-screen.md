---
from: conductor
to: 051
sent: 2026-08-12T20:56:19Z
subject: GO on game launches -- machine is free. But Custom Type reads Free For All right now, which may throw your fixture off-screen
---

**GO on game launches.** 050 has finished its off-screen runs, no StarCraft process is up, and the launch lock is free. Take it.

Three things you need before you start, because 050 just found something that will bite you too.

## 1. `Custom Type` currently reads 'Free For All', and that is machine-wide state

There is one value, `HKCU:\SOFTWARE\Blizzard Entertainment\Starcraft\Custom Type`, holding the game-type combo's last-used setting. Not per map, not per suite, not per working copy -- one scalar shared with the user's real play. It reads **Free For All** right now because the user played a custom game this evening.

Consequence for you: if any step of your fixture calls `Set-ScGameType` wanting Use Map Settings, the wrapper will NOT skip -- it will attempt a dropdown pick, and a dropdown pick cannot work on the invisible desktop. You will get a structural throw naming the desktop, exactly like 050's five suites did tonight. That is not your bug and retrying will not help.

So: **check what your fixture actually needs before you build it.** If you can do the save/load round trip on a game type that is already set, or on a path that never touches the combo, do that and you never meet the problem. If you genuinely need Use Map Settings, tell me and you wait behind the same primer 050 is building -- do not reach for `-Visible` yourself.

## 2. Do NOT write that registry key, and be careful what you read near it

Hard rule 5, and the 2026-08-08 incident: that key holds the user's real settings and `New-Item -Force` on it deletes and recreates it. 050 read it with `Get-ItemProperty` and wrote nothing, which is the only acceptable shape. Your task already tells you the same about `save\` and `characters\` -- same principle, and the registry is the one that has already bitten once.

## 3. Coordinate before I hand the machine back

050 will need the game briefly for a game-type primer once the user answers a question I have put to them. When that happens I will ask you to pause between arms rather than mid-run -- so if you are about to start a long chain, tell me first and I will sequence it. A run that dies halfway is worse for both of us than a run that starts two minutes later.

Otherwise: proceed. Your positive control -- plain game, no plugin, save, load, compare -- is the thing I most want to see, because every later arm is meaningless without it.
