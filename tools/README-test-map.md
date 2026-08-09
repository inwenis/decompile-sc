# Test map generator (task009)

Generates a single-player StarCraft 1.16.1 map with many units already
placed for one player. It's the test fixture for the project's north star --
"select more than 12 units at once" -- so there's somewhere to box-select a
big group and issue one order in a couple of seconds.

## What it makes

- Default: 36 Terran Marines, owned by Player 1, clustered in a grid centred
  on Player 1's start location.
- Single player only: the chosen player's OWNR slot becomes `HUMAN` (open
  slot), exactly one other slot becomes a unit-less `COMPUTER`, every other
  slot is forced to `INACTIVE`. Nothing hostile is on the map.
- Unless `-EnemyCount` is passed (task 019), which gives that computer slot a
  block of units a documented distance away, so a test can walk the player's
  group into it and prove what the plugin does when a selected unit DIES. See
  "Combat variant" below. Without the flag the output is unchanged.
- The chosen player's race (`SIDE`) is written explicitly, the "randomize start
  location" bit is cleared from every force (`FORC`), and the map's triggers
  (`TRIG`/`MBRF`) are removed. Those three are what make the result actually
  *play*, and play the same way every time -- see "Why generated maps used not
  to play" below.
- Everything else (terrain, start locations, forces, unit/upgrade/tech
  settings, strings, briefing art) comes **byte for byte** unchanged from a
  real Blizzard map used as a template.

## How it works

`tools/make_test_map.py` patches the template's CHK **in place, as raw
bytes**. A CHK file is a flat sequence of `<4-byte name><i32 size><size
bytes>` chunks; the generator reads them into a list, replaces the payload of
the handful of chunks it must change, and re-serialises. Every other chunk
comes across unmodified, in its original order, duplicates included. A template
that duplicates a chunk the engine *adds up* rather than overwrites (`UNIT`,
`TRIG`, `MBRF`, `THG2`) is refused outright, since editing one of a stacked
pair would leave the other in force.

It does **not** decode and re-encode the CHK through
[richchk](https://github.com/sethmachine/richchk) any more, which is what
tasks 009-015 did. Task 016 diffed both sides of that round-trip section by
section and found richchk 0.3.0 silently rewriting sections nobody asked it
to touch:

| section | what the round-trip did |
| ---------- | ------------------------------------------------------------- |
| `UNIS`/`UNIx` | 4-18 bytes changed inside the base-weapon-damage array, on every map tried |
| `MRGN`     | a 64-location vanilla-StarCraft section re-emitted padded to the 255-location Brood War size (1280 -> 5100 bytes) |
| `SWNM`     | a 1024-byte switch-names section **added** to maps that had none |

None of that turned out to be the reason generated maps did not play (see
below), but a generator whose output differs from its template in ways nobody
chose is a generator whose failures cannot be reasoned about. The raw-byte
path removes the question: the validator now asserts the output differs from
its template **only in the sections this run actually edited** — `UNIT` always,
`OWNR`/`SIDE`/`FORC` when the player slots were rewritten, `TRIG`/`MBRF` when
the triggers were stripped — and refuses otherwise.

richchk is still a dependency, and still does the half it is good at: reading
`staredit\scenario.chk` out of the MPQ and writing it back, through its
bundled StormLib binding.

The `UNIT` section (the placed-unit list) is parsed by hand either way --
richchk has no `UNIT` transcoder as of 0.3.0, and nothing else maintained
does this for Python (see `research/prior-art.md`'s CHK row). The 36-byte
record layout comes from staredit.net's CHK spec, cross-checked against real
bytes out of a Blizzard ladder map (start-location and mineral-patch records
decode exactly as documented).

Steps, in order:

1. Extract `staredit\scenario.chk` from a template `.scm`/`.scx` and split it
   into raw chunks. Assert the split round-trips to the identical bytes before
   editing anything, so a template this tool cannot represent fails loudly.
2. Find that player's `UNIT`-section start-location record (unit id 214) to
   get spawn coordinates.
3. Append N new 36-byte `UNIT` records (chosen unit type, full HP/shield/
   energy, owned by the chosen player) in a grid centred on those coordinates.
4. Rewrite `OWNR`: chosen player -> `HUMAN` (0x06), one other slot ->
   `COMPUTER` (0x05), everyone else -> `INACTIVE`.
5. Rewrite `SIDE` for those two slots to an explicit race.
6. Clear the "randomize start location" bit from every force in `FORC`.
7. Empty `TRIG` and `MBRF`.
8. Save into a copy of the template MPQ (StormLib under the hood, via
   richchk's DLL binding but NOT richchk's own `save_chk_to_mpq` -- see
   "Why the game rejected the old output" below).
9. Read the result back and assert placed unit count/type/owner, start
   location, player slots, race, empty triggers, terrain dimensions, and the
   section-level diff against the template -- see "Validation" below.

## How to run

```powershell
./setup.ps1                 # once, if you haven't -- creates .venv, installs requirements.txt
./tools/make-test-map.ps1   # bare invocation: 36 Marines for Player 1
```

With parameters:

```powershell
./tools/make-test-map.ps1 -UnitCount 50 -UnitType marine -Player 0 `
    -OutputPath C:\sc-work\1161-base\Maps\my-test.scx
```

| Param          | Default                                                   | Meaning                              |
| -------------- | ---------------------------------------------------------- | ------------------------------------- |
| `-UnitCount`   | `36`                                                        | units to place (must be comfortably > 12) |
| `-UnitType`    | `marine`                                                    | a name from the built-in table (`marine`, `goliath`, `siege-tank`, `zergling`, `hydralisk`, `ultralisk`, `zealot`, `dragoon`, `lurker`) or a raw units.dat integer id |
| `-Player`      | `0`                                                         | 0-based slot, 0-7 (0 = Player 1)      |
| `-GridSpacing` | `32`                                                        | pixels between units (32 = one tile). Units bigger than a tile need more, or the game silently drops the ones it cannot place |
| `-KeepOwnr`    | off                                                         | leave the template's player slots and races alone — for a template that is already a playable single-player scenario |
| `-ClearPlayerUnits` | off                                                    | drop the target player's existing units first, so the placed group is all one type |
| `-KeepTriggers` | off                                                        | keep the template's `TRIG`/`MBRF`. **Never for a fixture** — a stock map's own triggers end the game within seconds of loading |
| `-Race`        | the placed unit type's race                                 | `zerg`/`terran`/`protoss`, written into `SIDE` for the human and computer slots |
| `-UnitHp`      | `100`                                                       | hit points as a **percentage** of the type's maximum (1-100), applied to the `-UnitType` block **only**. Lower makes the combat variant's victims die in seconds instead of minutes. The enemy force is deliberately left at 100%: it has to survive the engagement, which is what keeps the deaths a trickle |
| `-TemplatePath`| `C:\sc-work\1161-base\Maps\BroodWar\Ladder\(2)Fading Realm.scx` | source map for terrain/start location |
| `-OutputPath`  | `C:\sc-work\1161-base\Maps\test-many-units.scx`            | where the generated map is written    |

Combat variant (task 019) — off unless `-EnemyCount` is given:

| Param            | Default      | Meaning                                                     |
| ---------------- | ------------ | ----------------------------------------------------------- |
| `-EnemyCount`    | `0`          | COMPUTER-owned units to place. `0` keeps the hostility-free map tasks 015-017 use |
| `-EnemyType`     | `hydralisk`  | same name table as `-UnitType`, or a raw units.dat id       |
| `-EnemyOffsetX`  | `448`        | map pixels east of the player's start location for the enemy block's centre (14 tiles) |
| `-EnemyOffsetY`  | `0`          | map pixels south of it                                      |
| `-EnemySpacing`  | `48`         | pixels between enemy units                                  |
| `-EnemyRace`     | the enemy type's race | written into `SIDE` for the computer slot           |
| `-EnemyOwner`    | `computer`   | `player` instead builds the **placement probe**: identical unit types at identical coordinates, owned by the human, so a test can box them and count them in-process |
| `-MinEnemyGap`   | `256`        | refuse an enemy block closer than this to the player's block |

The `.ps1` is a thin wrapper; the actual logic is `tools/make_test_map.py`
(same params as `--unit-count`/`--unit-type`/`--player`/`--grid-spacing`/
`--keep-ownr`/`--clear-player-units`/`--keep-triggers`/`--race`/`--unit-hp`/
`--enemy-count`/`--enemy-type`/`--enemy-offset-x`/`--enemy-offset-y`/
`--enemy-spacing`/`--enemy-race`/`--enemy-owner`/`--min-enemy-gap`/`--template`/
`--output`, plus `--validate-only PATH` to just re-validate an existing map and
`--no-validate` to skip the post-generation check).

The unit block is **centred on the start location**. The camera opens centred there and shows
about 20x12 tiles, so a block that grew right-and-down from that point (as it did before task 015)
put its far half off screen and behind the HUD, where no drag box can reach it.

## Looking at a map

`tools/inspect_map.py` is the read-only companion, and the tool that produced the
root-cause evidence below. It decodes nothing through richchk's CHK layer, so what
it prints is what the engine reads:

```powershell
.venv/Scripts/python tools/inspect_map.py sections MAP          # every chunk, in file order
.venv/Scripts/python tools/inspect_map.py diff MAP_A MAP_B      # section-by-section, byte for byte
.venv/Scripts/python tools/inspect_map.py players MAP           # per-slot OWNR / SIDE / force / units
.venv/Scripts/python tools/inspect_map.py triggers MAP --ending-only
```

`players` on the default ladder template shows the melee-start bug in one line
(`SIDE` = "User Selectable"); `triggers --ending-only` shows why no stock map can
be used as a fixture with its triggers left in.

## Output location

Generated maps go into `C:\sc-work\1161-base\Maps\` (the disposable working
copy), never `C:\sc-install\Starcraft` (hard rule: never touch the pristine
install). `tools/make-working-copy.ps1 -Force` preserves anything under
`Maps\` that isn't part of the pristine install (task 010), so a generated
map survives a default reset. Pass `-PurgeExtras` for a true byte-for-byte
mirror that wipes it (along with replays and player profiles) -- if you need
that, regenerate the map afterwards with `./tools/make-test-map.ps1`.
Generated `.scx` files are gitignored; only the generator is committed.

## Validation

The generator runs a structural validation pass on its own output (unless
`--no-validate` is passed): it re-reads the produced file and asserts the
placed-unit count/type/owner, a start location for that player, the player
slots (one human, exactly one unit-less computer), that neither active slot is
left on the race value "User Selectable", that `TRIG` is empty, non-zero
terrain dimensions, and that the output differs from its template in no
section other than the ones it meant to change. Example output:

```
wrote C:\sc-work\1161-base\Maps\BroodWar\00-testmap\lurkers.scx
OK: C:\sc-work\1161-base\Maps\BroodWar\00-testmap\lurkers.scx
  36 unit(s) of type 103 owned by player 0, at 100% hit points
  start location for player 0 at (864, 624)
  OWNR[0] = HUMAN(open slot); one computer slot at 1 owning 0 unit(s) -- nothing hostile in the game
  SIDE[0] = Zerg -- not 'User Selectable', so the engine adds no melee starting units
  FORC force flags 0x00 0x00 0x00 0x00 -- no force randomises start locations, so the human is always player 0
  TRIG holds 0 byte(s) -- nothing can end the game on its own
  terrain 128x96 tiles
  differs from the template ONLY in: OWNR SIDE UNIT TRIG FORC
```

With `-EnemyCount` the same pass also reports the enemy block, the player block, and
the gap between them, and refuses the map if that gap is under `-MinEnemyGap`:

```
  36 unit(s) of type 103 owned by player 0, at 30% hit points
  OWNR[0] = HUMAN(open slot); one computer slot at 1 owning 6 unit(s)
  ENEMY 6 unit(s) of type 38 owned by slot 1 (computer), spanning (1264,600)-(1360,648) px
        the player's block spans (784,544)-(944,704) px; the two are at least 320px (10.0 tiles) apart
        offset from the start location: (+448, +0) px
```

Every one of those assertions except the last is still only *structural*, and
structure was never the thing that was wrong (task 016). The proof that the
game accepts and plays the file is `tools/plugin/test-burrow-fanout.ps1`: it
generates a map with this tool, loads it unattended, and reads back from inside
the process that the 36 placed units are the units that exist, that the mission
is still running two minutes later, and that one keypress burrows all 36.

For the combat variant the same job is done by
`tools/plugin/test-combat-death.ps1`, which additionally reads back the ENEMY
block's own spawn in-process (via the placement probe below) and proves the map
does not end itself when units are lost.

## Combat variant — an enemy force that can kill our units on demand (task 019)

Every fixture up to task 018 was **combat-less by design**, and that was the whole
problem: the plugin's died-while-displayed paths (the circles module's staleness
guards, the HUD row's liveness term and click gate) could only ever be exercised
offline, in `hooktest`. `-EnemyCount` adds a second, COMPUTER-owned block of units so
a test can walk the player's group into it and get one killed for real.

```powershell
./tools/make-test-map.ps1 -UnitCount 36 -UnitType lurker -UnitHp 30 `
    -EnemyCount 6 -EnemyType hydralisk -OutputPath ...\combat.scx
```

### How the enemy is made to fight: nothing. That is the finding.

The task offered three ways to get a computer force to attack — a melee AI flag, a
synthesised `TRIG` that orders it, or unit types that attack on sight. It is the
third, and it needs **no new CHK section at all**: preplaced units on a computer slot
sit on their default order and shoot whatever walks into range. `TRIG` stays empty,
which is what keeps task 016's no-auto-end property intact.

That is a behavioural claim, so it is asserted in game, not argued.
`tools/plugin/test-combat-death.ps1` boxes the 36 Lurkers, right-clicks a move order
into the Hydralisk block, and reads back from inside the process that the player's
units start dying — while the same run asserts that **nothing** happens for the
twenty seconds before that order (the map still idles; see below).

Two CHK-level choices support it, and both are refusals rather than rewrites:

- **The two slots must not be allied.** `FORC`'s first eight bytes assign each slot to
  a force and bit `0x02` of a force's flag byte is "allied" (staredit.net CHK spec,
  the same source as the `0x01` random-start bit above). Allied units never shoot each
  other, so a combat map generated from a template whose two slots share an allied
  force is **refused**, in the generator and again in the validator. The documented
  ladder template passes: its Force 1 flag byte is `0x01`, which becomes `0x00` once
  the random-start bit is cleared.
- **The computer slot gets the enemy type's race** in `SIDE`, instead of the player's.
  Nothing observed says a Zerg slot cannot own Terran units under Use Map Settings,
  but a slot whose race matches what it owns is what every stock map does.

### Where the enemy goes, and why there

The block's centre defaults to **+448 map pixels (14 tiles) due east** of the player's
start location, and the generator refuses anything that leaves under 256px between the
two blocks' bounding boxes. Both numbers come from the 640x480 screen, not from taste:

- the camera opens centred on the start location and **never moves on its own**, so a
  right-click at client x is a move order to `start.x + x - 320` map pixels — a
  destination past about +310px cannot be clicked at all;
- so the enemy must be close enough for one right-click near the right-hand edge to
  put the player's block on top of it, and far enough that nothing is in anyone's
  acquisition range while the test is still boxing units.

The geometry is only geometry. The property that matters — *nothing engages until the
test says so* — is asserted in game: 36 units boxed, all alive, twenty seconds later
still 36 with no row line reporting a loss.

### Proving the enemy block actually spawns: `-EnemyOwner player`

The human slot's units can be counted in-process by boxing them. The computer's
cannot: a drag box does not pick up hostile units, and the enemy block is off screen
from the opening camera position. So the same generator builds a **placement probe** —
`-EnemyOwner player` puts the identical unit type, count and coordinates on the human
slot instead — and the test centres the view on it with a **minimap click**
(`Get-ScMinimapPoint` in `tools/plugin/drive-game.ps1`) and boxes it.

Result, read out of the process on 2026-08-08: `UNITSTATE n=6 types=[0x26:6]` — six
Hydralisks (units.dat 38), and nothing else, at the coordinates the file places them.
The combat map is then asserted to place the same type, the same count and the same
pixel rectangle, differing only in which slot owns them.

The minimap mapping itself was calibrated the same way rather than assumed: the
minimap box is 128x128 client pixels at (7, 348) and a map of W x H tiles is drawn one
pixel per tile, centred in it. Nine origin candidates were scanned in game; only that
one selects exactly the six placed units for every x tried, and a click four pixels
higher puts only three of them on screen.

### `-UnitHp`: why the victims are on 30% health

The `hp` byte at offset **0x11** of a UNIT record (immediately after the owner byte at
0x10) is a **percentage** of the unit type's maximum (1-100, staredit.net CHK spec),
and it applies because bit `0x02` of the valid-properties mask at 0x0E is set — which
it has been since task 009, with every fixture written at 100. A full-health 125-point
Lurker absorbs about twenty Hydralisk shots, and the first death took roughly two
minutes; the whole test took eleven.

The offset is checked, not counted by eye: packing a record through
`_UNIT_RECORD_FMT` with `hp=30` puts `30` at byte 0x11, and 0x19 — which an earlier
draft of this section named — is the **high byte of the `units in hangar` u16** at
0x18, which this tool always writes as zero. The generator never addressed the field
by a literal offset, so no generated map was ever affected.

At `-UnitHp 30` the first death arrives in about ten seconds and the test runs in
about four and a half minutes, with nothing else about the fixture changed: same unit
type, same evidence, same inability to shoot back. The effect is asserted rather than
assumed — the test fails if the first death takes longer than its deadline, which at
full health it always would.

## The per-unit-COST variant (task 022)

Every ability in vanilla StarCraft that costs the acting unit something needs research:
Stim Packs, both cloaks, Siege Mode. Burrow is the one exception, and only for Lurkers —
which is why the fixture above uses Lurkers, and why nothing this generator produced could
test a per-unit **cost** until task 022 added two flags.

### `-TechResearched <tech>`: the ability button has to exist at all

Writes `PTEx`, the Brood War player-tech section, marking a tech **available** and
**already-researched** for the chosen player, with `playerUsesDefault` cleared for that
(tech, player) pair — all three bytes, because the per-player entries are dead while the
"use default" byte is set.

The layout is the 44-tech Brood War one from the staredit.net CHK spec, and it is confirmed
by arithmetic rather than assumed: `44*12 + 44*12 + 44 + 44 + 44*12 == 1672`, which is
exactly the size of the section in `(2)Fading Realm.scx` on disk. A template without a
`PTEx` section is refused rather than guessed at.

**The per-player arrays are PLAYER-MAJOR — `player * 44 + tech` (fixed in task 026).** This
tool had them tech-major, and the section size above could not catch it: the total is right
either way. `tech * 12 + player` and `player * 44 + tech` agree at exactly two cells, `(0, 0)`
and `(43, 11)` — and the first is **Stim Packs for the human slot**, the only tech any fixture
here had ever proved worked. Every other tech was written into some other player's row and the
engine granted the human nothing. `--tech-researched personnel-cloaking` put its byte at offset
120, which the engine reads as player 2's tech 32; the Ghost's Cloak button came up greyed, and
tasks 022 and 023 spent two sessions concluding that the command card's ability row was inert.

Two things made it survive: the generator's own `read_techs_researched` used the same wrong
index, so its validator confirmed its own write and printed
`PTEx: player 0 has researched 10(personnel-cloaking)` for a map on which player 0 had nothing;
and the one fixture anybody had verified in game was the coincident cell. The order is now read
out of the engine's own PTEx applier (`0x004CB7D0`, disassembled in
[`research/command-card.md`](../research/command-card.md) §6.3), the write and the read share one
`ptex_index()`, and `tests/make-test-map.Tests.ps1` pins the literal byte offsets — including
that `(tech 10, player 0)` is byte 10 and not byte 120.

Tech ids come from richchk's own `TechId` enum — the same source, and the same provenance
discipline, as the unit ids. Named here: `stim-packs` (0), `siege-mode` (5),
`cloaking-field` (9), `personnel-cloaking` (10), `burrowing` (11); anything else can be
passed as a raw `techdata.dat` id.

Proved in game: with `--tech-researched stim-packs`, 36 generated Marines have the Stim
button and one keypress emits command `0x36`. Without it the run fails several minutes later
on "the key emitted nothing" — which is why the test asserts the generator's own `PTEx:` line
before it launches anything.

Two corrections to that paragraph, both from task 026. **The generator's `PTEx:` line is not
evidence** — it is a read-back of this tool's own write through this tool's own indexing, and it
reported success for years' worth of maps the engine never received. The evidence is the
engine's memory: launch with `-CardScan 1` and read the `CARD ... tech p=0 researched=[...]`
line ([`research/command-card.md`](../research/command-card.md) §9). And **an unresearched tech
does not remove the button from the card** — availability does that; research decides whether
the button is *enabled* or *greyed*. An ability whose tech is available but unresearched sits on
the card, greyed, and is silent to every key and every click.

### `-DamagedCount N -DamagedHp P` (and `-DamagedEnergy P`): payers and non-payers in ONE selection

The **last N units of the same block** are placed at P% instead of the block's normal value.
Same type, same grid, same owner — the only difference is what they can afford.

That "same selection" part is the whole point. An ability with a per-unit cost has a
per-unit affordability gate (Stim's is `CMP dword [unit+8],0xa00 / JLE skip` —
`research/ability-semantics.md` §2), and the only way to see whether the ENGINE or the
fan-out decides who gets skipped is to have both kinds of unit in one selection, reached by
one keypress. Two separate runs cannot tell "the engine skipped the poor ones" apart from
"the plugin sent a different set that time".

The tail is the **tail** deliberately: the fan-out emits the engine's visible twelve last and
the overflow chunks first, and this generator builds the block row-major from the top-left,
so a damaged tail lands in the part of the box the engine does **not** hold. A split along
the visible/overflow line instead of along the hit-point line would then be ours, and the
layout is what makes the two hypotheses produce different numbers.

`-DamagedEnergy` is the same idea in the other currency, for the `0x21` family whose cost is
energy (`0x00491B30` compares `cost*0x100 <= CUnit+0xA2` before deducting it).

> **Watch out for the SEND-side gate.** Task 022 found that the client's own command card
> refuses to emit an ability when the units it can see cannot pay for it. The client sees
> the engine's twelve, not the shadow list — so a low-affordability tail can disable the
> button outright and leave a run measuring nothing. Use the tail to test the gate, not as
> background scenery in a test about something else.

### Why the player's units are Lurkers — two reasons, both load-bearing

An **unburrowed Lurker has no weapon at all** (its only attack is a burrowed-only
weapon), so the enemy force survives the engagement. The deaths therefore arrive as a
steady trickle instead of being decided by which side wins a fight, and the boxed
group stays over the 12-unit cap — the only state in which the HUD-row assertion means
anything. It is also the unit type tasks 015-017 already use, so the fixture is the
one those suites are written against.

And a **burrowed** Lurker cannot be targeted by a Hydralisk, which is not a detector.
That is how the test ends the engagement: one keypress, the same untargeted-ability
fan-out `test-burrow-fanout.ps1` proves reaches all 36 units, and the fight stops
where it stands without moving anybody. Walking away does **not** work — the enemy
pursues, the Lurkers keep dying all the way home, and five disengage-by-retreat
attempts in a row failed to produce a population that held still long enough to
compare the row with itself. Burrowing produced one on the first attempt, and took the
whole test from 5:11 to 3:43.

## Why the game rejected the old output (task 013)

Task 009's original map (36 Marines, otherwise identical to today's default)
passed the structural validation above and was still rejected by the game as
corrupt. The cause: richchk 0.3.0's `StarCraftMpqIo.save_chk_to_mpq()` writes
`staredit\scenario.chk` back into the archive via a hardcoded call in
`StormLibWrapper.add_file()` (`mpq/stormlib/stormlib_wrapper.py`) --
`MPQ_FILE_COMPRESS` only (never `MPQ_FILE_ENCRYPTED`) and
`MPQ_COMPRESSION_ZLIB`, with no parameter to change either.

Checked independently -- an MPQ reader written from scratch against the
public MoPaQ format spec (not richchk, not StormLib, not anything that wrote
the file under test) -- every stock map inspected
(`C:\sc-work\1161-base\Maps\BroodWar\Ladder\(2)Fading Realm.scx`, the
template this generator uses, and a scenario map,
`Maps\campaign\(1)Enslavers02b.scm`) stores `staredit\scenario.chk`
**encrypted** and **PKWARE-compressed** (sector data starts with byte
`0x08`). richchk's output was **unencrypted** and **zlib-compressed** (byte
`0x02`) -- the only structural difference this diff found between our output
and two independently-sourced Blizzard maps. Classic 1.16.1 predates zlib
support in `Storm.dll`; PKWARE ("implode") is the original method every
build understands. That mismatch is the most likely reason the file loads
into richchk fine (round-trips through zlib+its own decoder) but the real
game's older decompressor rejects it.

**Fix**: `make_test_map.py` now calls its own `save_chk_bytes_to_mpq()`
instead of richchk's `save_chk_to_mpq()`. It reuses richchk's StormLib DLL
binding, but calls
`SFileAddFileEx` directly with `MPQ_FILE_COMPRESS | MPQ_FILE_ENCRYPTED` and
`MPQ_COMPRESSION_PKWARE` -- the flags the independent reader found on every
stock map checked. Verified (again with the same from-scratch reader, not
richchk) that regenerated output now reports `flags=0x80010200`
(COMPRESS+ENCRYPTED+EXISTS) and leading sector byte `0x08` (PKWARE),
matching stock exactly. See `work/scratch/raw_mpq_inspect.py` (not
committed -- throwaway diagnostic script) for the reader used.

**Not yet closed**: this is still round-tripping-adjacent proof -- an
independent *parser* agrees the container now looks like a real one, but
per this task's own rule, only an actual game load proves the game accepts
it. That confirmation was not spent on this fix; task 013's one human
verification attempt went to unblocking task 011 with a stock map instead
(see task 013's PR/report). Re-running `./tools/make-test-map.ps1` and
getting one human load is the remaining step to fully close this out.

Also fixed in passing: `-UnitType zealot` mapped to unit id `64`, which is
Protoss Probe, not Zealot (id `65`) -- confirmed against richchk's own
`unis/unit_id.py` enum. Unrelated to the corruption bug; would have placed
the wrong unit, not broken the file.

## Starting resources — `-StartingMinerals` / `-StartingGas` (task 025)

A CHK carries **no starting-resources field**. Under Melee/FFA the engine hands out its own
default; under **Use Map Settings** — the game type every suite in this repo plays its fixtures
under — a map gets whatever its own *triggers* give it, and this generator strips the template's
triggers on purpose (see "Why generated maps used not to play"). So until task 025 every fixture
started on effectively nothing, and a producing building could afford about one unit.

`-StartingMinerals N` (and `-StartingGas N`) writes **one** trigger back into the
otherwise-emptied `TRIG` section:

```
condition[0]  Always                          (condition byte 22)
action[0]     Set Resources  player, N, Ore   (action byte 26, modifier 7 = Set To)
action[1]     Set Resources  player, N, Gas   (only if -StartingGas was passed)
executed for  the -Player slot only
preserve      NO  -- StarCraft disables the trigger once its actions have run
```

The 2400-byte layout (16 x 20-byte conditions, 64 x 32-byte actions, 4 + 27 + 1 bytes of player
execution) and the field positions of Set Resources come from richchk's own decoded models and
its `set_resources_action_transcoder`, cited in the source. It is confirmed by arithmetic against
the divisor this tool already used: `16*20 + 64*32 + 4 + 27 + 1 == 2400`.

**It still cannot end the game**, and that is checked rather than asserted. `validate_map` reads
the trigger back out of the generated file and requires two things of the BYTES: that the grants
are exactly what was asked for, and that the only action byte present anywhere in the payload is
26 (Set Resources) — so no Victory, Defeat or End Scenario action can have slipped in. The
"TRIG holds 0 bytes" check becomes "TRIG holds exactly one trigger" only when resources were
requested; without the flags it is unchanged.

Incompatible with `-KeepTriggers`, which is refused with a message rather than silently appending
to a stock map's victory triggers.

```powershell
# task 025's production fixture: one Command Center, 3000 minerals, 1000 gas
./tools/make-test-map.ps1 -UnitCount 1 -UnitType command-center -Player 0 `
    -ClearPlayerUnits -GridSpacing 160 -StartingMinerals 3000 -StartingGas 1000 `
    -OutputPath 'C:\sc-workN1-base\Maps\BroodWar -t025\production-queue.scx'
```

Three building names were added to the unit table for that fixture: `command-center` (106),
`supply-depot` (109) and `barracks` (111). A Command Center is the cheapest producing building
to test with — it trains SCVs at 50 minerals and 1 supply each **and** provides 10 supply of its
own, so a queue of nine needs no Supply Depot to have landed on buildable ground.

## Known limitations

- Unit placement is a simple grid centred on the start location's pixel
  coordinates; it does not check for terrain passability/collisions with
  existing doodads. On the default template this lands in open ground, but a
  different `-TemplatePath` map could place units somewhere awkward (e.g.
  overlapping a cliff edge) -- worth an eyeball check if you swap templates.
- `-UnitType` and `-EnemyType` have a handful of built-in names between them
  (Marine, Ghost, Medic, Goliath, Siege Tank (Tank Mode), Zergling, Hydralisk,
  Ultralisk, Zealot, Dragoon, Lurker, and the three task-025 buildings
  Command Center, Supply Depot and Barracks); any other unit needs its
  units.dat integer id passed directly.
- A template that uses the negative-size CHK chunk trick (map protection) is
  refused outright: this tool cannot re-serialise one faithfully, and would
  rather fail than quietly change what the game reads.
- `-Player` is limited to 0-7 (the 8 real player slots); indices 8-11 are
  observer/unused slots in the CHK format and are not meaningful targets
  here.
- `-StartingMinerals`/`-StartingGas` set a player's balance ONCE, on the first
  trigger loop. There is no way here to grant resources over time, and no other
  trigger of any kind can be written -- deliberately, since the whole point of
  an emptied `TRIG` is that a fixture cannot end itself.
- The generated `UNIT` records reuse the template's existing resource/
  start-location entries unchanged (appended after them, not replacing
  them) -- so mineral/gas patches from the template map are still present.
  This is intentional (keeps the map internally consistent) but means map
  size/complexity scales with whatever template is chosen.

### …and specifically for the combat variant

Worth stating plainly, because the in-game evidence is easy to read as covering
more than it does:

- **The COMPUTER slot's units are never counted in process.** A drag box does not
  pick up hostile units and the enemy block is off screen from the opening camera,
  so `-EnemyOwner player` is a *substitution*: it proves the engine creates exactly
  that many units of that type at those coordinates **for the human slot**. On the
  combat map itself, the enemy force's existence is proved only by the deaths it
  causes. The generator's structural read-back is what pins the count and the owner
  there.
- **This closes the damage-death half of the 014/017 gap, and only that half.**
  Removal *without* death -- trigger `RemoveUnit`, transport load, mind control,
  archon merge, a recycled slot -- leaves hit points and `+0xA5` untouched, is
  handled structurally rather than by the liveness term, and is still proved offline
  in `hooktest` alone. Nothing in this fixture exercises those.
- **Which unit dies first is not controllable.** Whether the first casualty is one
  of the engine's own visible twelve (row hands back to stock) or one of the
  overflow (row keeps paging) depends on what the enemy shoots. Both are asserted
  when they occur, but the test *selects* neither, and the same-selection page walk
  is therefore opportunistic -- the run-to-run proof is the re-boxed comparison.

## Why generated maps used not to play (task 015 found it, task 016 root-caused it)

Three separate failures kept every generated map from being usable, and **none of them was the
CHK round-trip everyone suspected.** All three are now fixed, and all three are asserted by the
validator.

### 1. A melee-template map played as a MELEE game — `SIDE` said "User Selectable"

Load a map generated from the default `(2)Fading Realm.scx` ladder template, with Game Type set
to **Use Map Settings**, and the player got a **standard starting base**; the placed units were
never created. Read from inside the process rather than off the screen: with a generated
36-Lurker map loaded, the plugin's `UNITSTATE` reported
`types=[0x29:4 0x23:3 0x2A:1]` — four Drones, three Larva, one Overlord — a Zerg melee start
containing none of the 36 units the file holds.

It was not the lobby. Re-run on 2026-08-08 with the Game Type combo opened and *"Use Map
Settings"* picked explicitly from its list (SC's dropdowns are press-and-hold: the entry under
the cursor at button-*up* is what gets chosen, so a plain click cannot select anything and the
box's label is not evidence of what is set — `Send-ScDropdownPick` in `drive-game.ps1`), the
result was byte-for-byte the same histogram.

It was not the round-trip either. The map that produced that histogram came from the raw-CHK
patcher above, at a point where the tool did not touch `SIDE` yet: it differed from the stock
ladder map in `OWNR`, `UNIT` and `TRIG` **and nothing else**, with `SIDE` still carrying the
template's own `0x05` for every slot — and it still played as melee. So no section outside those
three could be responsible, and `SIDE` was the untouched one left holding the bag.

The cause is the `SIDE` section — one byte per player, that slot's race. A Blizzard **ladder**
map carries `0x05` "**User Selectable**" for its human slots, because a ladder player picks a
race in the lobby. StarCraft hands a User-Selectable slot the standard **melee starting units**
for whichever race is picked, *even under Use Map Settings*, and the map's own placed units for
that player never appear. A stock **campaign** map, which plays correctly through exactly the
same menu path, carries a fixed race instead — `(1)Enslavers02b.scm` has `0x02` (Protoss) for its
human slot.

Writing an explicit race into `SIDE` is the whole fix. Same map, same menus, one byte per slot
changed:

```
before   UNITSTATE ... n=8  live=8  visible=8  overflow=0  types=[0x2A:1 0x23:3 0x29:4]
after    UNITSTATE ... n=36 live=36 visible=12 overflow=24 types=[0x67:36]      (0x67 = Lurker)
```

A visible tell in the lobby, for anyone debugging this again: a User-Selectable slot shows a
**race dropdown** ("Random") next to the player name on the Create Game screen. A fixed-race map
shows none.

### 2. A campaign-template map ended within seconds — the mission's own triggers

Generating from a stock **campaign** template produced a map that loaded, briefed, entered the
mission and then ended within about seven seconds. The suspicion was that the CHK round-trip had
disturbed trigger data. It had not:

- Diffed field by field across the old richchk round-trip, `TRIG` came back **byte-identical**
  (50400 bytes for `(1)Enslavers01.scm`), and so did `MBRF`, `STR` and `UPRP`. Whatever the
  round-trip did to that file, it did not touch a single trigger byte.
- And the ending is not something *any* edit provokes: with the raw-CHK patcher, a map from
  `(1)Enslavers02b.scm` differing from the stock file in the `UNIT` section **alone**
  (`-KeepOwnr -KeepTriggers -ClearPlayerUnits -Player 1`) played on past 60 s with its 36 Lurkers
  alive and had to be shut down by hand.

A campaign map is a *mission*, and it ships the triggers that end it. Which one fires depends on
exactly which units the generator added or removed. `(1)Enslavers02b.scm` has 30 triggers, six of
which end the game, all executed by Force 1 (the human's force):

| trigger | condition | action |
| ------- | ---------------------------------------------- | ------------------------------- |
| 0       | current player commands at most 0 [Men]         | Defeat |
| 10      | **all players** command at most 0 of unit 168   | Wait, Pause Game, Wait, Set Next Scenario, **Victory** |
| 15-19   | current player commands at most 0 of unit 21 / 22 / 80 / 81 / 86 (the mission's protected units) | Wait, Pause Game, Play WAV, Display Text, Wait, **Defeat** |

Every one of those conditions is about *which units exist*, and changing which units exist is the
generator's entire job. Point it at the human slot with `-ClearPlayerUnits` and triggers 0/15/16
fire; let it rewrite `OWNR` and every other player's units are never created, so trigger 10's
"all players command at most 0 of unit 168" is true on the first frame — the map's only three
unit-168s belong to player 6. The leading `Wait` + `Pause Game` in those action chains is why it
takes seconds rather than being instant.

Predicted from the trigger dump before the run, then watched happen on 2026-08-08: the same
template with `-KeepTriggers` but `OWNR` rewritten (so players 3-6 are inactive and their
unit-168s never exist) put *"Congratulations! You are victorious!"* on screen about nine seconds
after the mission started. The same template with the triggers stripped — the default — runs
indefinitely.

That one is a **screen** observation, from a captured frame, and it is the only claim in this
document that is: the plugin log has no line that says "the mission ended", because the observer
reports selection and unit state, and an empty selection in a menu looks the same as an empty
selection in game. The log-backed version of the same property is in
`tools/plugin/test-burrow-fanout.ps1`, which after 120 s re-boxes and asserts
`live=36` — a claim you cannot make from a menu.

So: **a test fixture must carry no triggers at all.** A ladder template is no safer than a
campaign one; decoded out of `(2)Fading Realm.scx`, a Blizzard melee map ships the three standard
melee triggers, and the third of them — *"all players: non-allied victory players command at most
0 [unit class 231] → Victory"* — reads as true on the first frame of a generated map, because the
only other participant is the unit-less computer opponent. (That one is read from the file, not
watched in game: the fix landed before it was ever loaded with its triggers intact. The campaign
case above is the one confirmed on screen.)

### 3. The human did not always land on the slot that owns the units — `FORC` randomised it

Found while running the finished test repeatedly, which is the only way this one shows up. Of
three in-game loads of an otherwise-finished fixture — same map file, same menu path, same lobby
— **one** came up on a black screen with an empty minimap, the plugin reporting `player=1/1/1`
and `UNITSTATE n=0`; the other two reported player 0 and the expected 36 Lurkers.

`FORC`'s last four bytes are per-force property flags, and bit `0x01` is *randomize start
location* (staredit.net CHK spec). `(2)Fading Realm.scx` sets it on Force 1, which every slot
belongs to.

What that run shows is the **observable**: with the bit set, the human's own player id is not
fixed, and when it comes out as slot 1 they own none of the units, which are all on slot 0. The
mechanism inside the engine — presumably a permutation of participants across the
start-location owners — is an inference from that and is not claimed here as proved.

The generator now clears the bit on every force (leaving allied / allied-victory / shared-vision
alone) and the validator refuses a map that still carries it. Three full test runs since, all
`player=0/0/0` — a small sample, and deliberately not the argument: the point is that a fixture
must not depend on which slot the engine picks at all.

### Still true, from task 015 — do not re-introduce

1. `OWNR` must be `0x06` ("Human (Open Slot)"), **not** `0x02` (`HUMAN_OCCUPIED`). `0x02` is what
   the game writes at runtime for a slot a human has already taken; with it, Play Custom refuses
   the map — *"This map does not have a slot for a human participant."*, Human Slots: 0.
2. Single-player Play Custom refuses a **melee-type** launch with no computer slot at all — *"You
   must have at least one computer opponent."* — so exactly one slot is set to `COMPUTER` and
   given no units anywhere on the map. The validator asserts both halves.
3. The unit block is centred on the start location, or its far half sits off screen where no drag
   box can reach it.
