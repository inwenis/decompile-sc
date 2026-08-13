---
from: conductor
to: user
sent: 2026-08-13T22:36:25Z
subject: DONE -- the window now shows all 800 columns of map, from the first frame. Picture inside
---

**Your goal is done. The (Wide) shortcut now shows more map.**

## The picture

`C:\sc-work\logs\074-frames\storm-present-shipped-static.png`

Open it beside `C:\sc-work\logs\070-frames\drive-ingame-after.png` — same band, same fixture. In the old one it is flat black; in the new one it is map, with the fog shroud correctly darkening into unexplored ground.

**On the first frame after loading. You do not have to scroll to make it appear.**

## What was actually wrong

The engine has been computing all 800 columns correctly for hours — geometry, fog, everything. **The step that copies the finished picture into the window was still copying 640 of them.** Four tasks measured the buffer and found it perfect; nobody compared the buffer against the glass until tonight.

Two separate caps, both now fixed:

1. the presentable region was 640 wide because its only image node was the 640-wide console art;
2. even widened, the copy never refreshed the right quarter on a static frame — so it looked black until you scrolled.

## Where it stands

| thing | state |
|---|---|
| More map on screen | **works**, first frame, shipped config |
| Fog across the full width | works |
| Minimap, keyboard scrolling | works |
| Cancel-by-click, queue features | unchanged, suites green |
| Clicking in the new right quarter | **engine widened, never watched working — your first-play check** |
| Console position | still bottom-left at 640; moving it is a separate merged experiment, off by default |

`StarCraft.exe` and `storm.dll` are byte-identical on disk — everything is runtime-only, and the normal shortcut is untouched.

## The one thing to try first

**Load a game with the (Wide) shortcut and click a unit standing in the new right quarter.** Does it select that exact unit? Then drag a box there, then right-click ground to move someone.

That is the only part no automated test could reach — our harness cannot feed a click to that region on a hidden screen. If it misbehaves, that is a finding, not a surprise.

## Still waiting on you

1. Deploy to your play copy — everything above is on main, your install is untouched.
2. `C:\sc-deploy\task067-scratch` (~1 GB) — say the word and I delete it.
3. Six leftover worktree folders need one command from you; the cause is fixed so no new ones appear.
