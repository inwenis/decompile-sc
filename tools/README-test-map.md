# Test map generator (task009)

Generates a single-player StarCraft 1.16.1 map with many units already
placed for one player. It's the test fixture for the project's north star --
"select more than 12 units at once" -- so there's somewhere to box-select a
big group and issue one order in a couple of seconds.

## What it makes

- Default: 36 Terran Marines, owned by Player 1, clustered in a grid next to
  Player 1's start location.
- Single player only: the chosen player's OWNR slot is forced to
  `HUMAN_OCCUPIED`, every other slot is forced to `INACTIVE`. No computer
  players, no hostile pressure.
- Everything else (terrain, start locations, forces, races) comes unchanged
  from a real Blizzard ladder map used as a template, so the result is a
  normal, structurally valid, loadable `.scx`.

## How it works

`tools/make_test_map.py` uses [richchk](https://github.com/sethmachine/richchk)
0.3.0 (pinned in `requirements.txt`) to read and write the map's CHK data
inside its MPQ container. richchk was chosen over the alternatives surveyed
in `research/prior-art.md` because it's the only maintained library found
that round-trips a full playable `.scm`/`.scx` (CHK sections *and* the MPQ
container, via its bundled StormLib) rather than just CHK bytes.

One gap: richchk does not model the CHK `UNIT` section (the placed-unit
list) -- it has no `UNIT` transcoder, so it decodes/encodes it as an opaque
`DecodedUnknownSection` (raw bytes, passed through unchanged on a normal
read/write). Nothing else maintained does this for Python either (see
prior-art's CHK row). This generator fills that one gap by hand: it parses
and appends 36-byte `UNIT` records directly, using the documented format
(staredit.net's CHK spec) cross-checked against real bytes read out of a
Blizzard ladder map with this repo's own template-map inspection (start
location and mineral-patch records decode exactly as documented). Everything
else -- MPQ IO, CHK chunking, OWNR editing -- goes through richchk unchanged.

Steps, in order:

1. Read `staredit\scenario.chk` out of a template `.scx` (an existing 2-player
   ladder map from the working copy) via richchk.
2. Find that player's `UNIT`-section start-location record (unit id 214) to
   get spawn coordinates.
3. Append N new 36-byte `UNIT` records (chosen unit type, full HP/shield/
   energy, owned by the chosen player) in a grid starting at those
   coordinates.
4. Overwrite the OWNR section: chosen player -> `HUMAN_OCCUPIED`, everyone
   else -> `INACTIVE`.
5. Save back into a copy of the template MPQ (StormLib under the hood, via
   richchk's DLL binding but NOT richchk's own `save_chk_to_mpq` -- see
   "Why the game rejected the old output" below).
6. Read the result back and assert unit count/type/owner, start location,
   no active computer players, and terrain dimensions -- see "Validation"
   below.

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
| `-UnitType`    | `marine`                                                    | name (`marine`, `zergling`, `zealot`) or a raw units.dat integer id |
| `-Player`      | `0`                                                         | 0-based slot, 0-7 (0 = Player 1)      |
| `-TemplatePath`| `C:\sc-work\1161-base\Maps\BroodWar\Ladder\(2)Fading Realm.scx` | source map for terrain/start location |
| `-OutputPath`  | `C:\sc-work\1161-base\Maps\test-many-units.scx`            | where the generated map is written    |

The `.ps1` is a thin wrapper; the actual logic is `tools/make_test_map.py`
(same params as `--unit-count`/`--unit-type`/`--player`/`--template`/
`--output`, plus `--validate-only PATH` to just re-validate an existing map
and `--no-validate` to skip the post-generation check).

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
`--no-validate` is passed): parses the produced file back and asserts the
placed-unit count/type/owner, presence of a start location for that player,
no other active computer player slots, and non-zero terrain dimensions.
Example output:

```
wrote C:\sc-work\1161-base\Maps\test-many-units.scx
OK: C:\sc-work\1161-base\Maps\test-many-units.scx
  36 unit(s) of type 0 owned by player 0
  start location for player 0 at (864, 624)
  OWNR[0] = PlayerType.HUMAN_OCCUPIED, no other active computer players
  terrain 128x96 tiles
```

**This is structural validation only, and it is not proof the game accepts
the file** -- see the next section. It parses the output back with the same
library that wrote it, which only shows the library agrees with itself.
In-game loading needs a human (task 013 `research/`, and
`research/runtime-selection-observations.md` §5: synthetic clicks cannot
reliably drive this game's menus).

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

**Fix**: `make_test_map.py` now calls `save_chk_to_mpq_matching_blizzard()`
instead of richchk's `save_chk_to_mpq()`. It reuses richchk's own CHK
encoder and StormLib DLL binding for everything else, but calls
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

- Unit placement is a simple grid starting at the start location's pixel
  coordinates; it does not check for terrain passability/collisions with
  existing doodads. On the default template this lands in open ground, but a
  different `-TemplatePath` map could place units somewhere awkward (e.g.
  overlapping a cliff edge) -- worth an eyeball check if you swap templates.
- `-UnitType` only has three built-in names (Marine, Zergling, Zealot); any
  other unit needs its units.dat integer id passed directly.
- `-Player` is limited to 0-7 (the 8 real player slots); indices 8-11 are
  observer/unused slots in the CHK format and are not meaningful targets
  here.
- The generated `UNIT` records reuse the template's existing resource/
  start-location entries unchanged (appended after them, not replacing
  them) -- so mineral/gas patches from the template map are still present.
  This is intentional (keeps the map internally consistent) but means map
  size/complexity scales with whatever template is chosen.
