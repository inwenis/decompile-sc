---
from: conductor
to: user
sent: 2026-08-12T22:14:43Z
subject: Save/load bug CONFIRMED (not retracted), 051 merged. Architectural review: never been done -- task 052 started on code + tests
---

Two answers. The save/load one is now final and merged; the architectural one starts with a blunt no.

## 1. Save/load: confirmed, not retracted

I asked 051 to confirm or kill the leak before you planned around it, because one of its later runs came back clean at the same seam and I could not tell from the transcript which reading was right. It confirmed, and pointed at the line:

    FAIL arm6: the plugin holds NOTHING for a game it never queued in
               (overflow=3, tracked buildings=1) -- items held from an earlier game
               survive the load and will be promoted into this one

The clean run was a different experiment — a process with no plugin queue at all, which structurally cannot carry anything stale. The bug is a property of the loading process, not of the file. **The bug is real. The workaround stands: quit to the menu and relaunch before queuing over the cap again after a load.**

Merged as PR #64. Bug filed as [#63](https://github.com/inwenis/decompile-sc/issues/63). Full report at `work/reports/051-save-load-with-mods.md`.

**A second finding, milder but yours to know:** over-cap items are not in the save file and cannot be — they live in the plugin, not the game. Save with three items held above the engine's five, load that save without the mod, and those three are silently gone. Already paid for, never delivered. That is a design gap rather than a bug, and it is now written down.

Also worth your attention: **most of tonight's failures in that task were the harness, not the game**, and the report splits them into two explicit tables rather than letting a reader assume every red line was StarCraft misbehaving. The genuine findings are exactly two, both above.

## 2. Architectural review: no, never, and here is the shape of the problem

**Has one ever been done? No.** 51 tasks in six days, one domain audit (022, ability semantics), and no pass over the system as a whole. Current size:

| area | lines |
| --- | --- |
| plugin C++ (`tools/plugin/src/`) | 18,641 |
| test framework PowerShell (`tools/plugin/`) | 22,899 |

None of it has ever been read as a system by anyone.

I have cut **task 052** and put a fable worker on it — covering both halves, as you corrected. It is read-only: it produces a report and issues, and it does not touch code. It never launches the game, so it runs alongside 048 without competing for the machine.

What makes me think it will find things rather than produce a tidy nothing: I did not give it a generic "audit the code" brief. I gave it three named defect classes with tonight's measured instances as starting points.

1. **Assertions that cannot fail** — the dominant class here. Three found today alone: the ink count that reads the game's own artwork, the hook count that would stay green with the hook under test removed, and nine save/load checks that passed with no load having happened. Plus the two older ones already in the rulebook.
2. **Duplication, weighted toward duplicated *models* rather than duplicated code** — the expensive instance being a wrong mental model of when the engine paints, fixed in one module and still live in another, which is exactly why your page indicator was invisible.
3. **Invariants nobody enforces** — the save/load bug is one: "this record belongs to this game" was relied on everywhere and expressed nowhere.

I also told it explicitly that this is your hobby project and that a 200-item style list is a failed deliverable. Findings get ranked by whether they can make us believe something false or break something you can see; everything merely untidy goes in a clearly-labelled deferred section. And it has to state what it did NOT read — a review that implies it saw everything would be committing the same sin it is hunting.

## 3. Board

| # | task | state |
| --- | --- | --- |
| 039 | fifth slot / group line | merged, deployed, yours |
| 050 | six screen-stealing suites | merged and closed |
| 051 | save/load with the mods | **merged and closed** |
| 048 | the invisible page indicator | running both arms now, machine is free |
| 052 | architectural review, code + tests | just started |
| 049 | leftover regression check | queued |
