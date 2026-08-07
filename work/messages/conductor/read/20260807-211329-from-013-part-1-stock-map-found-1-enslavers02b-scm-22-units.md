---
from: 013
to: conductor
sent: 2026-08-07T21:13:29Z
subject: Part 1: stock map found -- (1)Enslavers02b.scm, 22 units
---

## Part 1 result: stock map found

**Recommend: `Maps\campaign\(1)Enslavers02b.scm`** — Player 2 (0-based slot 1) starts with **22
real, mobile, selectable Protoss units** (12 Zealots, 4 Dragoons, 3 Scouts, 2 Observers, 1
Archon), packed into an 11×9-tile cluster — fits one drag box. Nearest actual hostile army is
44 tiles away; the only closer "hostile" (20 tiles, player 7) is 3 immobile Stasis Cell Prison
buildings, not a threat. No workers/buildings counted toward the 22 — pure combat units.

**Menu path**: Single Player → Expansion (Brood War) → Play Custom → browse into `Maps\campaign\`
→ pick `(1)Enslavers02b`. It's a stock file sitting in the working copy's Maps tree, same as any
UMS map — no unlock needed.

**What the user should see**: drops into a mission with the 22-unit Protoss squad already
selected-area-visible near the start location, no enemy on screen. Caveat: this is a scripted
Brood War bonus-campaign mission (has triggers/MBRF), so a mission-intro cutscene or forced
camera pan is possible before control is handed over — not confirmed either way (see
"not yet proven" below). If that happens, wait it out; it is not a bug.

### Alternate (second attempt only)

`Maps\campaign\(1)Enslavers03a.scm`, Player 7 (slot 6, Terran): 25 real mobile units (16
Marine, 4 SCV, 3 Siege Tank, 2 Goliath). Nearest real hostile army is a very safe 62 tiles away.
Caveat: the units are spread over a 41×28-tile area (base + a forward squad), likely needs 2-3
drag boxes rather than one — worse fit than Enslavers02b for "one drag box catches them."

### Why not a plain melee/ladder map

Scanned all 210 stock `.scm`/`.scx` files under `C:\sc-work\1161-base\Maps\` offline with
richchk (read-only, no game launch). After excluding buildings, Map Revealers (invisible
trigger helpers, id 101), beacons/flags/markers and resources, **zero standard melee/ladder map
gives any player more than 12 real mobile units** — melee starts are 4-12 workers only, by
design. Only these two scripted Brood War "Enslavers" bonus-campaign missions clear the bar.
(An earlier, less careful pass over raw UNIT-section counts turned up false positives — e.g.
"(4)Zergling Round-Up.scm" looked like 36 units but 32 of them are Map Revealers, not
selectable; excluded once identified.)

### Not yet proven

Per the task's own rule, structural reads are not proof the game loads it. I could not get
independent proof myself this round:
- Tried the command-line map-path idea (`StarCraft.exe "<map>"` launched directly, no menus):
  a valid stock map path launches cleanly with no error dialog (`check-game-windows.ps1`
  confirms zero modal dialogs); a garbage path behaves differently (process exits/relaunches
  under a new PID quickly). That's *suggestive* the argument is consumed, not proof the specific
  map loaded past the main menu — StarCraft.exe also self-relaunches under a new PID
  unpredictably in this environment, which makes window-only inspection unreliable, and this
  sandbox blocks full-screen/synthesized screen capture, so I could not visually confirm.
- **A human load is still the only thing that counts here.** Recommend Enslavers02b, one
  attempt, path above.

Full scan data and scripts (not committed — game-content-adjacent, throwaway):
`work/scratch/scan_result.json`, `work/scratch/ranked2.json`,
`work/scratch/scan_stock_maps.py`, `work/scratch/rank_candidates2.py`,
`work/scratch/inspect_candidates.py`.

Moving on to Part 2 (diagnose/fix `make_test_map.py`) now.
