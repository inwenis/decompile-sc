#!/usr/bin/env python3
"""Generate a single-player StarCraft 1.16.1 test map with many units pre-placed.

Purpose: a fast fixture for testing "select more than 12 units at once" (the
project's north star mod). Loading the map should drop the player next to a
cluster of units big enough that one drag-box grabs more than the classic
12-unit selection cap.

See tools/README-test-map.md for the approach and known limitations.

Usage:
    python tools/make_test_map.py
    python tools/make_test_map.py --unit-count 50 --unit-type marine --player 0
    python tools/make_test_map.py --validate-only C:\\sc-work\\1161-base\\Maps\\test-many-units.scx --unit-count 36 --unit-type marine --player 0
"""

import argparse
import collections
import math
import struct
import sys
from pathlib import Path

from richchk.editor.richchk.rich_chk_editor import RichChkEditor
from richchk.editor.richchk.rich_ownr_editor import RichOwnrEditor
from richchk.io.mpq.starcraft_mpq_io_helper import StarCraftMpqIoHelper
from richchk.io.richchk.query.chk_query_util import ChkQueryUtil
from richchk.model.chk.unknown.decoded_unknown_section import DecodedUnknownSection
from richchk.model.richchk.dim.rich_dim_section import RichDimSection
from richchk.model.richchk.ownr.player_type import PlayerType
from richchk.model.richchk.ownr.rich_ownr_section import RichOwnrSection
from richchk.model.richchk.rich_chk import RichChk
from richchk.model.richchk.trig.player_id import PlayerId

# CHK "UNIT" section: one 36-byte record per placed unit (incl. resources and
# start-location markers). richchk does not model this section (no UNIT
# transcoder as of 0.3.0 -- see requirements.txt), so it is read/written as
# raw bytes here. Layout verified two ways: (1) staredit.net's published CHK
# spec, (2) parsing a real Blizzard ladder map's UNIT bytes with this exact
# struct and confirming known-good records (start locations, mineral/gas
# patches) decode sensibly -- see tools/README-test-map.md.
_UNIT_RECORD_SIZE = 36
_UNIT_RECORD_FMT = "<IHHHHHHBBBBIHHII"
_UNIT_FIELDS = (
    "instance", "x", "y", "unit_id", "rel_type", "special_flags",
    "valid_flags", "player", "hp", "shield", "energy", "resource",
    "hangar", "state_flags", "unused", "related",
)
UnitRecord = collections.namedtuple("UnitRecord", _UNIT_FIELDS)

START_LOCATION_UNIT_ID = 214

# "Changeable properties valid" bitmask (offset 0x0E in a UNIT record):
# bit0 owner, bit1 hp, bit2 shield, bit3 energy, bit4 resource, bit5 hangar.
_VALID_OWNER_HP_SHIELD_ENERGY = 0x01 | 0x02 | 0x04 | 0x08

# A handful of common unit type names (units.dat ids). Marine is the
# documented default: small, cheap, unambiguous to count on screen. Anything
# else can be passed as a raw units.dat integer id.
UNIT_TYPE_IDS = {
    "marine": 0,
    "zergling": 37,
    "zealot": 64,
}

DEFAULT_TEMPLATE = r"C:\sc-work\1161-base\Maps\BroodWar\Ladder\(2)Fading Realm.scx"
DEFAULT_OUTPUT = r"C:\sc-work\1161-base\Maps\test-many-units.scx"
DEFAULT_UNIT_COUNT = 36
GRID_SPACING_PX = 32  # one tile; keeps the cluster inside one drag-box


def resolve_unit_id(unit_type: str) -> int:
    try:
        return int(unit_type)
    except ValueError:
        pass
    key = unit_type.strip().lower()
    if key not in UNIT_TYPE_IDS:
        raise ValueError(
            f"Unknown unit type {unit_type!r}. Use one of "
            f"{sorted(UNIT_TYPE_IDS)} or a raw units.dat integer id."
        )
    return UNIT_TYPE_IDS[key]


def player_id_for_index(index: int) -> PlayerId:
    if not 0 <= index <= 11:
        raise ValueError(f"player index must be 0-11, got {index}")
    return PlayerId[f"PLAYER_{index + 1}"]


def find_unknown_section(chk: RichChk, name: str):
    for i, section in enumerate(chk.chk_sections):
        if isinstance(section, DecodedUnknownSection) and section.actual_section_name == name:
            return i, section
    return None, None


def parse_unit_records(data: bytes) -> list[UnitRecord]:
    if len(data) % _UNIT_RECORD_SIZE != 0:
        raise ValueError(
            f"UNIT section size {len(data)} is not a multiple of {_UNIT_RECORD_SIZE}"
        )
    return [
        UnitRecord(*struct.unpack(_UNIT_RECORD_FMT, data[i:i + _UNIT_RECORD_SIZE]))
        for i in range(0, len(data), _UNIT_RECORD_SIZE)
    ]


def pack_unit_record(rec: UnitRecord) -> bytes:
    return struct.pack(_UNIT_RECORD_FMT, *rec)


def build_new_unit_records(
    count: int, unit_id: int, player: int, center_x: int, center_y: int, next_instance: int
) -> list[UnitRecord]:
    per_row = math.ceil(math.sqrt(count))
    records = []
    for i in range(count):
        row, col = divmod(i, per_row)
        records.append(
            UnitRecord(
                instance=next_instance + i,
                x=center_x + col * GRID_SPACING_PX,
                y=center_y + row * GRID_SPACING_PX,
                unit_id=unit_id,
                rel_type=0,
                special_flags=0,
                valid_flags=_VALID_OWNER_HP_SHIELD_ENERGY,
                player=player,
                hp=100,
                shield=100,
                energy=100,
                resource=0,
                hangar=0,
                state_flags=0,
                unused=0,
                related=0,
            )
        )
    return records


def generate_map(
    template: Path, output: Path, unit_count: int, unit_type: str, player: int
) -> None:
    unit_id = resolve_unit_id(unit_type)
    if not 0 <= player <= 7:
        raise ValueError(f"player must be 0-7 (Player 1..Player 8), got {player}")
    if unit_count < 1:
        raise ValueError(f"unit-count must be >= 1, got {unit_count}")
    if not template.exists():
        raise FileNotFoundError(
            f"Template map not found: {template}\n"
            "Run tools/make-working-copy.ps1 first to populate the working copy."
        )

    mpqio = StarCraftMpqIoHelper.create_mpq_io(None)
    chk = mpqio.read_chk_from_mpq(str(template))

    unit_idx, unit_section = find_unknown_section(chk, "UNIT")
    if unit_section is None:
        raise ValueError(f"Template {template} has no UNIT section; not a valid map")
    existing_records = parse_unit_records(unit_section.chk_binary_data)

    start = next(
        (r for r in existing_records if r.unit_id == START_LOCATION_UNIT_ID and r.player == player),
        None,
    )
    if start is None:
        start = next(
            (r for r in existing_records if r.unit_id == START_LOCATION_UNIT_ID), None
        )
    if start is None:
        raise ValueError(f"Template {template} has no start location in its UNIT section")

    next_instance = max((r.instance for r in existing_records), default=0) + 1
    new_records = build_new_unit_records(unit_count, unit_id, player, start.x, start.y, next_instance)
    new_unit_bytes = unit_section.chk_binary_data + b"".join(
        pack_unit_record(r) for r in new_records
    )

    new_sections = list(chk.chk_sections)
    new_sections[unit_idx] = DecodedUnknownSection("UNIT", new_unit_bytes)
    chk = RichChk(_chk_sections=new_sections)

    # Single player, no hostile pressure: the chosen slot becomes a fixed
    # human occupant, every other slot goes inactive (no computer players).
    ownr = ChkQueryUtil.find_only_rich_section_in_chk(RichOwnrSection, chk)
    new_types = {
        player_id_for_index(i): PlayerType.INACTIVE for i in range(12) if i != player
    }
    new_types[player_id_for_index(player)] = PlayerType.HUMAN_OCCUPIED
    new_ownr = RichOwnrEditor().set_player_types(new_types, ownr)
    chk = RichChkEditor().replace_chk_section(new_ownr, chk)

    output.parent.mkdir(parents=True, exist_ok=True)
    mpqio.save_chk_to_mpq(chk, str(template), str(output), overwrite_existing=True)


def validate_map(path: Path, unit_count: int, unit_type: str, player: int) -> None:
    unit_id = resolve_unit_id(unit_type)
    mpqio = StarCraftMpqIoHelper.create_mpq_io(None)
    chk = mpqio.read_chk_from_mpq(str(path))

    _idx, unit_section = find_unknown_section(chk, "UNIT")
    if unit_section is None:
        raise AssertionError(f"{path}: no UNIT section found")
    records = parse_unit_records(unit_section.chk_binary_data)

    matching = [r for r in records if r.unit_id == unit_id and r.player == player]
    if len(matching) != unit_count:
        raise AssertionError(
            f"{path}: expected {unit_count} unit(s) of type {unit_id} owned by "
            f"player {player}, found {len(matching)}"
        )

    start = next(
        (r for r in records if r.unit_id == START_LOCATION_UNIT_ID and r.player == player),
        None,
    )
    if start is None:
        raise AssertionError(f"{path}: no start location found for player {player}")

    ownr = ChkQueryUtil.find_only_rich_section_in_chk(RichOwnrSection, chk)
    actual_type = ownr.player_types[player]
    if actual_type != PlayerType.HUMAN_OCCUPIED:
        raise AssertionError(
            f"{path}: player {player} OWNR slot is {actual_type}, expected HUMAN_OCCUPIED"
        )
    other_hostile = [
        i for i, t in enumerate(ownr.player_types)
        if i != player and t in (PlayerType.COMPUTER, PlayerType.COMPUTER_GAME)
    ]
    if other_hostile:
        raise AssertionError(f"{path}: found active computer player slot(s) {other_hostile}")

    dim = ChkQueryUtil.find_only_rich_section_in_chk(RichDimSection, chk)
    if dim.width <= 0 or dim.height <= 0:
        raise AssertionError(f"{path}: invalid terrain dimensions {dim.width}x{dim.height}")

    print(f"OK: {path}")
    print(f"  {len(matching)} unit(s) of type {unit_id} owned by player {player}")
    print(f"  start location for player {player} at ({start.x}, {start.y})")
    print(f"  OWNR[{player}] = {actual_type}, no other active computer players")
    print(f"  terrain {dim.width}x{dim.height} tiles")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--unit-count", type=int, default=DEFAULT_UNIT_COUNT)
    parser.add_argument("--unit-type", type=str, default="marine")
    parser.add_argument("--player", type=int, default=0, help="0-based player slot (0 = Player 1)")
    parser.add_argument("--template", type=Path, default=Path(DEFAULT_TEMPLATE))
    parser.add_argument("--output", type=Path, default=Path(DEFAULT_OUTPUT))
    parser.add_argument(
        "--validate-only",
        type=Path,
        default=None,
        help="Skip generation; just structurally validate the given map file.",
    )
    parser.add_argument(
        "--no-validate",
        action="store_true",
        help="Skip the post-generation structural validation pass.",
    )
    args = parser.parse_args()

    try:
        if args.validate_only is not None:
            validate_map(args.validate_only, args.unit_count, args.unit_type, args.player)
            return 0

        generate_map(args.template, args.output, args.unit_count, args.unit_type, args.player)
        print(f"wrote {args.output}")
        if not args.no_validate:
            validate_map(args.output, args.unit_count, args.unit_type, args.player)
        return 0
    except (ValueError, FileNotFoundError, AssertionError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
