---
from: 026
to: conductor
sent: 2026-08-09T20:25:45Z
subject: PR #27 open - all three follow-throughs done; the fixture bug is a PTEx INDEX-ORDER bug that only ever worked for Stim. Blocked on the game for the last two runs.
---

PR: https://github.com/inwenis/decompile-sc/pull/27 — `pr:` is in the task file.

All three follow-throughs are done, statically, with the hold respected (no launch since your
message; nothing of mine has touched the game).

**1. Task 023's fingerprint control is retracted in the record.** `research/command-card.md` §8
states it plainly with the evidence: both fixtures hold the same nine slots, the same buttons, in
the same states, and both hashed `AC61F7A0C9244DB1` — the value 023 recorded for *no tech*. The
rule went into `AGENTS.md` next to the other hard rules: read a dialog's content from memory, never
hash its pixels; and a tool that verifies its own write with its own indexing verifies nothing.

**2. The arrays are swept, and the fixture bug is FOUND AND FIXED — it is better than "PTEx set
available but not researched".** The sweep (`research/data/card-tech-state.tsv`) confirms
`techAvailable[12][24]` at `0x0058CE24` and `techResearched[12][24]` at `0x0058CF44`, plus the
Brood-War tail, with the CHK appliers as their only writers. Decompiling the applier gave the real
cause:

- the engine reads PTEx **player-major** (`player*44 + tech`) — byte-exact at `0x004CB870`,
  `SUB EBX,0x2c` per player with the tech as the inner index;
- `make_test_map.py` wrote it **tech-major** (`tech*12 + player`);
- the two agree at exactly `(0,0)` and `(43,11)`, and `(0,0)` is **Stim Packs for the human slot** —
  the only tech any fixture in this repo had ever proved worked in game. Everything else went into
  some other player's row. `personnel-cloaking` wrote byte 120, which the engine reads as player
  2's tech 32;
- and it survived because `read_techs_researched` used the same wrong index, so the generator
  verified its own mistake and printed `PTEx: player 0 has researched 10(...)` for a map on which
  player 0 had nothing.

Fixed with one shared `ptex_index()`, `tests/make-test-map.Tests.ps1` pinning the literal applier
offsets (8 new cases, including that `(10,0)` is byte 10 and not 120), and an end-to-end check on a
generated map read at literal offsets: `player0 tech10 avail=1 researched=1`, byte 120 clear,
exactly one researched byte set anywhere. That test caught one of my own overclaims while I wrote
it — I had said the two conventions coincide only at `(0,0)`; `(43,11)` coincides too, and the case
now asserts both.

The card scan also reads the tech arrays now, so the next in-game run confirms the fix in the
engine's own memory rather than from the generator — `CARD ... tech p=0 researched=[...]` on the
same marker as the card.

**3. Scope is kept apart, in the doc and in the PR.** `command-card.md` §7 splits it explicitly:
SETTLED — why the *test* could not drive cloak, and that the user's observation was right; NOT
SETTLED — the user's actual report, a Ghost that WAS cloaked and stopped attacking. The PR says the
same in its own words and does not let the first read as the second.

**Green:** hooktest 0 failures (13 parts — part [13] reads the card twice with the same code, once
with the disabled bit set and once clear, so a stuck oracle cannot produce this result);
`run-ci-local.ps1` PASS with 42 Pester cases; `StarCraft.exe` SHA-256 byte-identical; no stray
processes; no fixture folder left behind.

**Blocked on the game, and only on that.** Two things are owed and both need a launch: (a) re-read
the card on a fixture whose researched bit the engine confirms, and show slot 7 ENABLED with `0x21`
on the wire — the probe already asserts this either way; (b) the order-stability A/B on a genuinely
cloaked Ghost, which is the user's actual question. Release me onto task 027's launch and I will
run both. Everything else on this task is finished and in review.
