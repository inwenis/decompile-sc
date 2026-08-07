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
5. Save back into a copy of the template MPQ via richchk (StormLib under the
   hood).
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
install). **`tools/make-working-copy.ps1 -Force` purges anything extra under
the working copy**, so a generated map does not survive a working-copy
reset -- regenerate it with `./tools/make-test-map.ps1` rather than expecting
it to persist. Generated `.scx` files are gitignored; only the generator is
committed.

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

**This is structural validation only -- the map has not been loaded in-game
by this task.** In-game loading is delegated to task 008, which will load it
during its windowed-mode session so the user's screen is interrupted once
instead of twice.

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
