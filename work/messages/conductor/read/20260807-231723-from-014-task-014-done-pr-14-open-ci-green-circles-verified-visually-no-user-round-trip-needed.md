---
from: 014
to: conductor
sent: 2026-08-07T23:17:23Z
subject: Task 014 DONE - PR #14 open, CI green, circles verified visually (no user round trip needed)
---

PR: https://github.com/inwenis/decompile-sc/pull/14 (CI green: Parse/lint pass, GitGuardian pass)

## Done

Box-select 24, all 24 now get a green circle. The cheap route worked, but not the way the task
guessed.

**A selection circle is not a flag the renderer consults.** It is a `CImage` (draw function `0x0D`,
id `0x231..0x23A`) linked into the sprite's overlay list; flag `0x01` only records that one is
attached. So the plugin calls the engine's own primitives instead of reimplementing anything:
`0x004D7070` attach, `0x004975D0` remove. One extra hook,
`CreateNewUnitSelectionsFromList` (`0x0049AE40`) — our circles come off at its entry, before the
engine attaches its own, which is what keeps the two sets disjoint.

## `selectionIndex` — the answer is "nothing, and here is why"

The plugin never writes it and never sets sprite flag `0x08`.

Four instructions read the field, and every one uses it as a `memmove` offset into a **12-entry
stack array**. **There is no safe value** for a unit outside the engine's 12: `>= 12` makes the
length negative and smashes a 48-byte stack buffer; `<= 11` is in bounds but deletes a *different,
genuinely selected* unit. All four readers are gated on flag `0x08`, so leaving that bit clear makes
the field unreachable for our units. That is the finding the task asked to be reported rather than
guessed at.

Corroboration it is not an abuse of the data model: `0x0049F860` (sprite rebuild) already saves flag
`0x01` independently of `0x08` and restores the circle on its own. The engine models this state.

Also: **`CSprite::flags` is at `0x0E` in this binary, not `0x06`** — BWAPI's header omits the two
list pointers at the front of the struct. `selection-cap.md` §2.4 now carries a correction banner.

## You do NOT need to spend the user round trip

The task budgeted one user question for "do the circles actually appear on screen". **I answered it
myself.** `PrintWindow(PW_*)` on the game's own window gives a PNG, and I can read a PNG — so I
looked. Six dragoons in one cluster, six green circles, exactly one health bar (the engine's one out
of that six; ours are circle-only by design). The frames are on a gitignored path outside the repo,
per hard rule 1 — which is also why the PR carries no screenshot.

Your call whether to still ask, but the premise "the one thing you cannot do is see the screen" no
longer holds, and this technique is reusable by every future task.

## Acceptance criteria

1. Circles drawn — yes, `CIRCLES show: 12/12` on a 24-unit box, confirmed visually.
2. `selectionIndex` stated — above, and `research/selection-circles.md` §4.
3. Shift-click out — tested three ways: small selection 3 → 2; an engine unit inside the 12+12
   selection → `SEL count` 12 → 11 with a 4-byte `0x0B` carrying exactly one unit; a shadow-circled
   unit → no command, count stays 12, process alive.
4. Fan-out intact — `units=24 (visible 12 + overflow 12) -> 2 Select+order pairs`, all 24 moved.
5. Self-tested — `tools/plugin/test-selection-circles.ps1` is **unattended**: launches, walks the
   menus, loads the stock map, drives the box/shift-clicks/order, asserts on the plugin log.
   0 failures. `build.ps1 -Test` part [8] adds 20 offline assertions with no game in the process.
6. `StarCraft.exe` SHA-256 `AD6B58B2…C6A46` before and after every run, identical to the pristine
   install. `-Mode observe` installs no hook at all; `-Circles 0` installs 4 instead of 5. No game
   process left running.
7. PR open, link in Status.pr.

## Worth knowing for later tasks

- `tools/plugin/drive-game.ps1` — task 012's D1 recipe as reusable primitives (find HWND by pid,
  click, drag, type, capture a frame). `PostMessage`, client coordinates, no synthetic OS input.
- `tools/ghidra/scripts/FieldSweep.java` — enumerates instructions touching a struct *displacement*.
  `XrefSweep` can only see globals; a field in a heap object has no address. This is what produced
  the four-reader table.
- Shadow units get a circle and **no health bar** — deliberate (the bar's removal is gated on flag
  `0x08`), and it doubles as the tell for which 12 are the engine's.
- The HUD wireframe row is untouched, as scoped.
