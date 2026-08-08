---
from: 016
to: conductor
sent: 2026-08-08T04:40:13Z
subject: Task 016 done — PR #16, all 6 criteria met, CI green
---

**PR: https://github.com/inwenis/decompile-sc/pull/16** (Status.pr updated). Full write-up is the PR body.

## Headline

The in-game untargeted-ability proof is delivered. `tools/plugin/test-burrow-fanout.ps1`,
unattended, `0 failure(s)`, run twice back to back:

```
CMD id=0x2C len=2 bytes=[2C 00]
FANOUT start: cmd=0x2C len=2 units=36 (visible 12 + overflow 24) -> 3 Select+order pairs
UNITSTATE [burrowed] n=36 live=36 visible=12 overflow=24 types=[0x67:36] burrowed=36/36
```

Criterion 3's waiver in `research/command-opcodes.md` §8 is now marked CLOSED, with the evidence
in a new §8.2.

## Three root causes, none of them the CHK round-trip

1. **Melee-template map played as melee: `SIDE` = 0x05 "User Selectable".** A ladder map carries
   that for its human slots; StarCraft gives such a slot the standard MELEE starting units even
   under Use Map Settings, and never creates the placed units. Ruled the lobby out by opening the
   Game Type combo properly (SC dropdowns are press-and-hold — a plain click opens and closes
   without selecting) and picking Use Map Settings from the list: identical histogram. Ruled the
   round-trip out because the raw-CHK map differs from stock in OWNR/SIDE/UNIT/TRIG and nothing
   else and still played melee. Writing a fixed race turns
   `types=[0x2A:1 0x23:3 0x29:4]` into `types=[0x67:36]`.
2. **Campaign-template map ended in ~7 s: the mission's own triggers.** TRIG comes across the old
   richchk round-trip byte-identical (measured), and a raw-CHK map from `(1)Enslavers02b.scm`
   differs from stock in UNIT alone and still ends. That map ships six game-ending triggers whose
   conditions are all about which units exist — which is what a generator changes. Predicted from
   the decoded triggers which one would fire, built it, loaded it: "Congratulations! You are
   victorious!" about nine seconds in.
3. **A third one, found by running the finished test repeatedly:** `FORC` bit 0x01 "randomize
   start location", which the ladder template sets. SC implements it by permuting participants
   among the start-location OWNERS — it changes which player id you play as. Coin flip on a
   two-slot map; losing it puts the human on player 1 while every unit belongs to player 0
   (`player=1/1/1`, `UNITSTATE n=0`, black screen). Cleared; `player=0/0/0` on both runs since.

## Also in the PR

- `make_test_map.py` now patches the CHK as **raw byte chunks** instead of round-tripping it
  through richchk, which was silently rewriting UNIS/UNIx, MRGN and SWNM. The validator asserts
  the output differs from its template only in OWNR/SIDE/UNIT/TRIG/FORC.
- `tools/inspect_map.py` — read-only CHK inspector (`sections` / `diff` / `players` /
  `triggers --ending-only`), the tool the evidence came out of.
- `Get-ScUnitState` + `Send-ScDropdownPick` factored into `drive-game.ps1`.

## Regressions

`build.ps1 -Test` 0 failures, `test-fanout-orders.ps1` 0 failures, `test-selection-circles.ps1`
0 failures, `test-burrow-fanout.ps1` 0 failures x2. StarCraft.exe SHA-256 `AD6B58B2…C6A46` before
and after every run. No stranded processes, no leftover generated maps. CI green.

## One thing to know before review

**No screenshots are attached, on purpose.** The visual evidence is game artwork (melee start,
36 Lurkers, Victory dialog); AGENTS.md hard rule 1 and this task's hard rule 5 both forbid
committing it, and `pr-image` would push it to the repo's `pr-assets` branch. Every claim is
backed by a plugin log line instead. Say the word if you want that judgement reversed.
