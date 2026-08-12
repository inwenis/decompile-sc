---
from: conductor
to: user
sent: 2026-08-12T20:53:55Z
subject: Found it: whether a test steals your screen depends on the game type YOU last played. One visible pick fixes all 15 -- now, or at 23:00?
type: question
options: Do the one visible pick now; Wait for 23:00 per my rule; Leave it, I do not mind tests asking for the screen
---

Task 050 found why tests keep demanding your screen, and the answer is about **your** games, not our code. I verified it myself before writing this, read-only, nothing touched.

## The finding

There is one value in `HKCU:\SOFTWARE\Blizzard Entertainment\Starcraft` called `Custom Type`. It holds the game-type dropdown's last-used setting — one flat string, machine-wide, shared by every StarCraft launch on this laptop. It currently reads **`Free For All`**, and the `Recent Maps` list in the same key is full of real maps from your own play, which is how we know the key is genuinely shared and not something our copies own.

Our suites want `Use Map Settings`. When the value already says that, they skip the dropdown and run invisibly. When it does not, they must open the dropdown — and a dropdown pick is the one input that cannot work on an invisible desktop, so the run demands the screen.

So the thing that decides whether a test needs your monitor is **what game type you last played**. That is why this looked random and unfixable for days: task 049 measured nine suites running fine off-screen and concluded they were fine by nature. They were fine by luck — an earlier run had left the value on `Use Map Settings`. Right now every one of the fifteen suites would demand the screen, not just the six we thought.

## Two things you should know, and one is mildly annoying

1. **Our tests change your next game's default.** When a suite picks `Use Map Settings`, your next custom game opens with that selected instead of whatever you had. Nothing is corrupted and the game's own menu does the writing — we never write that key ourselves, and after the 08 Aug incident that rule is absolute. But it is our test harness reaching into your live settings through a side door, and you deserve to know rather than notice.
2. That key holds **22 values**. Same key, same count, as the one that got wiped on 08 Aug. 050 read it and did not write it, which is exactly right.

## What I want to ask you

To get every suite running off-screen again, someone has to make **one** real game-type pick with the window actually visible. Once done, it sticks for every suite until your own play changes it back. It is about three minutes with StarCraft on your screen.

I have told 050 to hold and not start it, because I deployed the queue-indicator fix twenty minutes ago and told you to go play — and StarCraft only runs one copy at a time, so a test run now would fight your game rather than politely wait.

Your standing rule puts this in the 23:00–07:00 window, which is about an hour away. Options are on this message.

## Correction to what I told you earlier

I said 050 would retire the "give me your monitor for three minutes" ask entirely. That was too strong and I am walking it back: it turns *"six suites always need your screen"* into *"whichever suite runs next needs it only when `Custom Type` has drifted"* — the same exposure the other nine already had. Better, honestly measured, but not gone.
