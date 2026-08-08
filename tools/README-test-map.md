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
| `-UnitType`    | `marine`                                                    | name (`marine`, `zergling`, `zealot`, `lurker`) or a raw units.dat integer id |
| `-Player`      | `0`                                                         | 0-based slot, 0-7 (0 = Player 1)      |
| `-GridSpacing` | `32`                                                        | pixels between units (32 = one tile). Units bigger than a tile need more, or the game silently drops the ones it cannot place |
| `-KeepOwnr`    | off                                                         | leave the template's player slots and races alone — for a template that is already a playable single-player scenario |
| `-ClearPlayerUnits` | off                                                    | drop the target player's existing units first, so the placed group is all one type |
| `-KeepTriggers` | off                                                        | keep the template's `TRIG`/`MBRF`. **Never for a fixture** — a stock map's own triggers end the game within seconds of loading |
| `-Race`        | the placed unit type's race                                 | `zerg`/`terran`/`protoss`, written into `SIDE` for the human and computer slots |
| `-TemplatePath`| `C:\sc-work\1161-base\Maps\BroodWar\Ladder\(2)Fading Realm.scx` | source map for terrain/start location |
| `-OutputPath`  | `C:\sc-work\1161-base\Maps\test-many-units.scx`            | where the generated map is written    |

The `.ps1` is a thin wrapper; the actual logic is `tools/make_test_map.py`
(same params as `--unit-count`/`--unit-type`/`--player`/`--grid-spacing`/
`--keep-ownr`/`--clear-player-units`/`--keep-triggers`/`--race`/`--template`/
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
  36 unit(s) of type 103 owned by player 0
  start location for player 0 at (864, 624)
  OWNR[0] = HUMAN(open slot); one unit-less computer slot at 1
  SIDE[0] = Zerg -- not 'User Selectable', so the engine adds no melee starting units
  FORC force flags 0x00 0x00 0x00 0x00 -- no force randomises start locations, so the human is always player 0
  TRIG holds 0 byte(s) -- nothing can end the game on its own
  terrain 128x96 tiles
  differs from the template ONLY in: OWNR SIDE UNIT TRIG FORC
```

Every one of those assertions except the last is still only *structural*, and
structure was never the thing that was wrong (task 016). The proof that the
game accepts and plays the file is `tools/plugin/test-burrow-fanout.ps1`: it
generates a map with this tool, loads it unattended, and reads back from inside
the process that the 36 placed units are the units that exist, that the mission
is still running two minutes later, and that one keypress burrows all 36.

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

## Known limitations

- Unit placement is a simple grid centred on the start location's pixel
  coordinates; it does not check for terrain passability/collisions with
  existing doodads. On the default template this lands in open ground, but a
  different `-TemplatePath` map could place units somewhere awkward (e.g.
  overlapping a cliff edge) -- worth an eyeball check if you swap templates.
- `-UnitType` only has four built-in names (Marine, Zergling, Zealot, Lurker);
  any other unit needs its units.dat integer id passed directly.
- A template that uses the negative-size CHK chunk trick (map protection) is
  refused outright: this tool cannot re-serialise one faithfully, and would
  rather fail than quietly change what the game reads.
- `-Player` is limited to 0-7 (the 8 real player slots); indices 8-11 are
  observer/unused slots in the CHK format and are not meaningful targets
  here.
- The generated `UNIT` records reuse the template's existing resource/
  start-location entries unchanged (appended after them, not replacing
  them) -- so mineral/gas patches from the template map are still present.
  This is intentional (keeps the map internally consistent) but means map
  size/complexity scales with whatever template is chosen.

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
