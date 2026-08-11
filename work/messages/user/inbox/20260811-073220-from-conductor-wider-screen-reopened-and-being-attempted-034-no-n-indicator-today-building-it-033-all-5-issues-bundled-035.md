---
from: conductor
to: user
sent: 2026-08-11T07:32:20Z
subject: wider screen: reopened and being ATTEMPTED (034). No +N indicator today - building it (033). All 5 issues bundled (035)
---

Three answers, three tasks now running.

# 1. "Remastered managed a wider screen — can we do the same?"

**You are right that it is possible, and I have reopened it. Task 034 is attempting it now.**

How Blizzard did it: Remastered is a NEW renderer bolted onto the original game logic, shipping NEW artwork at higher resolution. Two things we cannot copy — we will not write a renderer from scratch, and we will never ship game art (that is a hard rule of this repo).

But last night`s NO-GO rested partly on a call I made, and re-reading it I think I called it wrong. The blocker was stated as "either a 160-pixel strip of nothing at the bottom, or new art" — and I let "strip of nothing" count as failure. **That was my aesthetic judgement standing in for yours.** A wider playfield with the stock console sitting under it, and some blank space beside it, is probably a trade you would happily take. So I have overruled myself and told 034 explicitly: if it works and the bottom strip is empty, that SHIPS.

What remains genuinely hard, and is the real question 034 will answer: the playfield size is not a variable anywhere — 640x400 is hardcoded in about thirty places, and one buffer cannot grow because another live variable sits immediately behind it. So this is not "change a number"; it is patching every one of those sites and making terrain, sprites and fog fill the new area.

I gave 034 a staged plan and explicit permission to STOP and report if it hits any of four named walls. **"I got to stage 2 and here is exactly what defeated it" is a good outcome** — it turns last night`s paper estimate into a measured one. What is not acceptable is quietly shipping a half-version.

If it reaches something worth looking at, I will tell you so you can judge it with your own eyes.

# 2. "When more than 5 units are queued, does anything show it?"

**No. Nothing shows it today, and you would have no way to tell.** The status strip draws exactly five icons whatever the real queue is, so nine queued looks identical to five. The same blindness applies to the new multi-building training: click Train with four Barracks selected and you see ONE queue while four buildings` worth of minerals leave.

Task 033 is building the "+N" indicator you described. I told it to do the cheapest thing that works — a small "+N" near the strip using the engine`s own text drawing — and explicitly NOT to build a full nine-slot queue display, which is a much bigger change. It will also try to make the multi-building case visible, and if that turns out to need the bigger display work, it will say so and ship the simple half.

# 3. "Are there GitHub issues we should act on?"

Yes — five were open, and I have bundled all of them into task 035 rather than spawning five workers, because they all live in the same two files and splitting them would reproduce the exact merge collisions that CAUSED three of them.

In the order I told it to work:

1. **#30 — the game steals your screen at launch.** The one you actually feel. Last night`s fix stopped the per-click grabbing; nothing covered the launch itself. Now measured precisely, and the fix is known.
2. **#39 — one test suite fails every single sweep** because of a flaw in its own retry logic. A suite that always fails is worse than no suite: it teaches everyone to ignore red.
3. **#37 — a rare file race** that kills a whole run for reasons unrelated to what was being tested.
4. **#35 — test part numbers silently collide** between branches (three times now).
5. **#29 — read the game type from memory** instead of comparing pixels. Deliberately last, because once done, a run can skip that step entirely and the final bit of window flicker disappears.

Two other issues closed themselves overnight when their fixes merged.
