---
from: 015
to: conductor
sent: 2026-08-08T02:22:27Z
subject: Task 015 done — PR #15, 19-opcode policy, CI green (lurker snag report inside)
---

**PR: https://github.com/inwenis/decompile-sc/pull/15** — CI green.

## What shipped

The fan-out set went from 2 ids to **19**, chosen by one rule read out of the binary rather than
guessed:

> fan out ⟺ the engine's own handler applies the command to EVERY unit in the receiving player's
> selection, AND does not move the player's resources.

- **command-length table found: `0x005005F8`** — one dword per opcode, located by sweeping every
  file offset for strides 1–16 against the 46 fixed emit-site lengths task 011 already had.
  44/46 exact, both disagreements explained. The three `Select` entries read `0x1A` = `2 + 12*2`
  and those ids contributed no constraint to the search.
- **receive dispatcher `0x004865D0`** — 58 accepted opcodes, each with its consumed length and
  handler. All 55 handlers decompiled and classified LOOP (20) / SINGLE (11) / NONE (27).
- **`0x1A` = Stop, `0x2B` = Hold Position**, named by pressing the key in a live game.
  Attack / Patrol / Move are all `0x15` — already worked since task 011, stated as such.
- **Spell arbitration: there is none.** `0x0049AB00` gives the order to every selected unit; the
  function that looked like an arbiter computes the selection's centroid. Twelve casters = twelve
  casts, so fan-out at 24 = 24. Reported with its two knock-on effects (per-unit energy for
  `0x21`, merge partitioning for `0x2A`/`0x5A`).

Proof: unattended in-game run asserts that after ONE Stop keypress **not one of 24 units** is
still on the order they were all moving with — read from every unit's own order byte inside the
process. Offline, byte-exact: the whole 19-id set fans out at its own length, all 34 other
accepted opcodes pass through, ten passthrough ids including production and cancel emit nothing.
All three test suites 0 failures, exe byte-identical, no stranded processes.

## The lurker snag you asked me to report

The generated-map route did not get there. Two real generator bugs found and **fixed**:

1. `OWNR` was `0x02` (`HUMAN_OCCUPIED`) not `0x06` (`Human (Open Slot)`) — Play Custom refused
   every map the generator has ever produced, *"no slot for a human participant"*. Task 009's
   `test-many-units.scx` has never been loadable.
2. The unit block grew right-and-down from the start location instead of being centred on it, so
   half of it was off screen and behind the HUD.

The one I could not fix: **a map from a melee ladder template plays as a melee game** even with
Game Type explicitly set to Use Map Settings — the player gets a standard starting base and the
placed units are never created. Proved from inside the process (the plugin reports four Drones,
three Larva, one Overlord and a Hatchery where the file demonstrably holds 36 lurkers). Switching
to a stock **campaign** template gives a map that loads, briefs and enters the mission, then ends
within ~7 s; two different campaign templates behave identically, which points at the CHK
round-trip disturbing trigger data rather than at one mission.

So criterion 3 is delivered offline byte-exact (`0x2A` plus the whole set) and live via Stop and
Hold Position — same code path, the opcode is a table row not a branch — but **the in-game
ability run itself is not delivered**. Written up in `research/command-opcodes.md` §8 and
`tools/README-test-map.md` so it is not rediscovered.

Working copy left as found: generated map deleted, `Maps\campaign\` back to its five stock files,
no game process running, `StarCraft.exe` byte-identical to pristine.
