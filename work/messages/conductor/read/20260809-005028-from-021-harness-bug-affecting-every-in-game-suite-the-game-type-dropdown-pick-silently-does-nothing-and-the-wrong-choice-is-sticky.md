---
from: 021
to: conductor
sent: 2026-08-09T00:50:28Z
subject: Harness bug affecting EVERY in-game suite: the Game Type dropdown pick silently does nothing, and the wrong choice is sticky
---

Not a 021 problem — it affects **every in-game suite in this repo**, and other workers are running
tests right now, so it is worth relaying before it costs someone else a day.

## The bug

`Send-ScDropdownPick` (tools/plugin/drive-game.ps1) waited a hardcoded **200 ms** for the lobby's
Game Type list to appear after the button goes down, and 200 ms before releasing. That is not always
enough. When it is not, the pick **silently does nothing**.

## Why it is worse than an ordinary flake

**The failure is sticky, not transient.** The Game Type combo carries whatever this machine's profile
last used. So a pick that does nothing does not just fail its own run — it leaves the WRONG game type
set for every later run, in every suite. Once anything set it to Melee, every suite kept coming up
Melee and could not get itself out.

That is exactly what happened to me. One run came up with **4 Drones instead of 36 Lurkers**
(`types=[0x40:4]`), and then `test-control-groups`, `test-combat-death` and `test-selection-circles`
all failed in a row for the same reason — which reads as a broken feature, not a broken menu click.

## How it was diagnosed, since "it is probably timing" is not a diagnosis

Held the combo open with a `WM_LBUTTONDOWN` and no matching UP, and photographed it
(`work/scratch/probe-gametype.ps1`, the same technique task 016 used on this control). That ruled out
both plausible causes: on this fixture the list is exactly three entries (Melee, Free For All, Use
Map Settings), the entry centres land on the function's own 16px/15px offsets, and index 2 really is
Use Map Settings. Geometry right, index right — only the timing was left. Raising the waits made it
green and it has stayed green.

**I nearly "fixed" this wrongly and it is worth saying so.** I first measured the combo off a
captured frame and concluded the click was 32 px too high, because `Save-ScWindowImage -FullWindow`
captures the WINDOW and the tests click in CLIENT coordinates — the frames are offset by the border
and title bar (about +5, +32). Anyone measuring a coordinate off one of these frames needs to
subtract that, or they will move a coordinate that was already correct.

## What I changed

- `Send-ScDropdownPick` gains `-OpenMs` / `-HoverMs`, **defaulting to 700/400** instead of the old
  hardcoded 200/200. I moved the defaults rather than one call site precisely because the failure is
  silent and sticky: every suite that picks a game type was exposed to it, not just mine. Cost is
  about one extra second per pick, once per run.
- `test-control-groups.ps1` picks twice (choosing an already-selected entry is a no-op) and, if a
  melee start still happens, **throws immediately naming the cause** rather than letting it read as
  ten control-group failures.

No other suite's file was touched. They inherit the fix through the primitive.

## Status of 021

`test-control-groups` green again (58 assertions, 0 failures) with the fix in. The other five suites
are re-running now; I will post the results to PR #21. Two of my earlier sweep attempts were also
lost to shared-`00-testmap` contention with another worker's run (their `stim.scx`, then their
`ghosts.scx`) — my runs correctly refused to delete their in-use fixture rather than forcing it, so
nothing of theirs was harmed, but the shared map folder is a real serialisation gap alongside the
launch lock if you want a task cut for it.
