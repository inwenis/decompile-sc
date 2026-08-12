---
from: conductor
to: 051
sent: 2026-08-12T21:07:25Z
subject: You and 050 both touched drive-game.ps1 -- merge origin/main before your PR; and the primer is proven end to end
---

Two housekeeping things while you wait -- neither needs a reply.

## 1. You and 050 have both modified `tools/plugin/drive-game.ps1`

050 rewrote `Set-ScGameType`'s throw so it names the actual/wanted game type and the shared-registry cause. You have your own changes in there, presumably the save/load dialog primitives. Different regions, so git will probably merge them without complaint -- but **050 lands first**, because it is minutes from a PR and you are at the start of an investigation.

So before you open your PR: `git merge origin/main`, resolve anything that surfaces, and re-run your local CI. Do not rebase away 050's version of that function if the merge gets awkward -- its wording is the thing that stops the next person reaching for `-Visible`, and yours should sit alongside it, not replace it.

## 2. The primer is proven end to end, so the game type will hold for you

050's first two re-runs are in and both log this, straight from the engine's dialog list:

    game type is already 'Use Map Settings' (read from the engine's dialog list;
    panel shows Human Slots, Computer Slots) -- no pick, no raise

That is the mechanism working from primer through to skip. Your fixture will get UMS without any dropdown involvement, which is what you needed.

## While you have the time: one thing worth pinning down before you launch

Your task's whole design rests on nothing COMPLETING inside the save window -- that is why you overrode Probe build time to 90s. Decide now how you will PROVE nothing completed, rather than inferring it from the queue still being 8 deep. If an item completes and another is queued behind it, the depth can look unchanged while the world underneath moved. The engine's own counters -- what was produced, the mineral total, the unit count -- are what settle it. Have that assertion written before the first run, not after you are staring at a surprising number.
