#!/usr/bin/env python3
"""Generate a single-player StarCraft 1.16.1 test map with many units pre-placed.

Purpose: a fast fixture for testing "select more than 12 units at once" (the
project's north star mod) and for testing what one order does to all of them.
Loading the map should drop the player next to a cluster of units big enough
that one drag-box grabs more than the classic 12-unit selection cap, on a map
that then sits there and does nothing until the test is over.

See tools/README-test-map.md for the approach, the two failures task 016
root-caused, and known limitations.

Usage:
    python tools/make_test_map.py
    python tools/make_test_map.py --unit-count 36 --unit-type lurker --player 0
    python tools/make_test_map.py --validate-only C:\\sc-work\\1161-base\\Maps\\test-many-units.scx --unit-count 36 --unit-type marine --player 0
"""

import argparse
import collections
import ctypes
import math
import shutil
import struct
import sys
from pathlib import Path

from richchk.io.mpq.starcraft_mpq_io_helper import StarCraftMpqIoHelper
from richchk.model.mpq.stormlib.stormlib_archive_mode import StormLibArchiveMode
from richchk.model.mpq.stormlib.stormlib_flag import StormLibFlag
from richchk.model.mpq.stormlib.stormlib_operation import StormLibOperation
from richchk.mpq.stormlib.stormlib_helper import StormLibHelper
from richchk.util.fileutils import CrossPlatformSafeTemporaryNamedFile

# ---------------------------------------------------------------------------
# CHK sections, as raw bytes
# ---------------------------------------------------------------------------
# A CHK file is a flat sequence of `<4-byte name><i32 size><size bytes>` chunks.
# This generator reads the template's chunks, replaces the payload of the two or
# three it must change, and writes the rest back BYTE FOR BYTE.
#
# It deliberately does NOT decode-and-re-encode the CHK through richchk, which
# is what task 009-015's generator did. Task 016 diffed both sides of that
# round-trip section by section and found richchk 0.3.0 rewrites sections it was
# never asked to touch:
#   * UNIS/UNIx (unit settings): 4-18 bytes differ inside the base-weapon-damage
#     array, on every map tried;
#   * MRGN (locations): a 64-location vanilla-StarCraft section is re-emitted
#     padded to the 255-location Brood War size (1280 -> 5100 bytes);
#   * SWNM (switch names): a 1024-byte section is ADDED to maps that had none.
# None of those is asked for by this tool, and a generator whose output differs
# from its template in ways nobody chose is a generator whose failures cannot be
# reasoned about. Reading the CHK out of the MPQ, and writing it back in, still
# goes through richchk's StormLib binding -- that half was never the problem.
_CHK_MPQ_PATH = "staredit\\scenario.chk"

ChkSection = collections.namedtuple("ChkSection", "name payload")


def parse_chk_sections(data: bytes) -> list[ChkSection]:
    """Every chunk in file order, duplicates included.

    Refuses maps that use the negative-size chunk trick (a map-protection
    technique that makes the cursor rewind): this tool cannot re-serialise one
    faithfully, and silently flattening it would change what the game reads.
    """
    sections: list[ChkSection] = []
    i = 0
    while i + 8 <= len(data):
        name = data[i:i + 4].decode("latin-1")
        (size,) = struct.unpack_from("<i", data, i + 4)
        if size < 0:
            raise ValueError(
                f"CHK section {name!r} at offset {i} has a negative size ({size}); "
                "this map uses the rewinding-chunk protection trick and cannot be "
                "used as a template."
            )
        start = i + 8
        if start + size > len(data):
            raise ValueError(
                f"CHK section {name!r} at offset {i} claims {size} bytes but only "
                f"{len(data) - start} remain; the file is truncated."
            )
        sections.append(ChkSection(name, data[start:start + size]))
        i = start + size
    if i != len(data):
        raise ValueError(f"{len(data) - i} trailing byte(s) after the last CHK section")
    return sections


def serialize_chk_sections(sections: list[ChkSection]) -> bytes:
    return b"".join(
        s.name.encode("latin-1") + struct.pack("<I", len(s.payload)) + s.payload
        for s in sections
    )


def chk_name(name: str) -> str:
    """CHK section names are exactly four bytes, space-padded: 'DIM ', 'VER ',
    'STR ', 'WAV '. Callers spell them without the padding."""
    if len(name) > 4:
        raise ValueError(f"CHK section name {name!r} is longer than four bytes")
    return name.ljust(4)


# Chunks the engine ADDS UP rather than overwrites when a name appears more than
# once (staredit.net CHK spec): a second UNIT chunk places more units, a second
# TRIG chunk runs more triggers. For those, "edit the last one" is wrong -- blanking
# the last TRIG of a stacked pair would leave the first pair's victory triggers
# running while this tool's own validator reported success. This generator refuses
# such a template outright (see require_single_chunk) rather than editing it wrongly.
ADDITIVE_SECTIONS = ("UNIT", "TRIG", "MBRF", "THG2")


def count_sections(sections: list[ChkSection], name: str) -> int:
    padded = chk_name(name)
    return sum(1 for s in sections if s.name == padded)


def require_single_chunk(sections: list[ChkSection], template: Path) -> None:
    """Refuse a template that duplicates any chunk this tool edits or empties.

    Same reasoning as the negative-size refusal in parse_chk_sections: a file this
    tool cannot represent faithfully should fail loudly, not be quietly changed
    into something else.
    """
    for name in ADDITIVE_SECTIONS:
        n = count_sections(sections, name)
        if n > 1:
            raise ValueError(
                f"Template {template} has {n} {name} chunks. The engine ADDS UP repeated "
                f"{name} chunks rather than letting the last one win, so editing one of "
                f"them would leave the others in force; refusing rather than producing a "
                f"map whose contents do not match what this tool reports."
            )


def find_section(sections: list[ChkSection], name: str) -> int:
    """Index of the LAST chunk with this name, or -1.

    Last, not first, because the engine applies chunks in file order and for an
    OVERWRITING section (OWNR, SIDE, FORC, DIM ...) the final one is the one that
    wins. That premise does NOT hold for the additive sections listed in
    ADDITIVE_SECTIONS -- templates that duplicate those are refused up front by
    require_single_chunk, which is what keeps this function's answer correct for
    every file this tool will actually edit.
    """
    padded = chk_name(name)
    for i in range(len(sections) - 1, -1, -1):
        if sections[i].name == padded:
            return i
    return -1


def require_section(sections: list[ChkSection], name: str, template: Path) -> int:
    idx = find_section(sections, name)
    if idx < 0:
        raise ValueError(f"Template {template} has no {name} section; not a valid map")
    return idx


def replace_section(sections: list[ChkSection], name: str, payload: bytes,
                    template: Path) -> list[ChkSection]:
    idx = require_section(sections, name, template)
    out = list(sections)
    out[idx] = ChkSection(chk_name(name), payload)
    return out


# ---------------------------------------------------------------------------
# UNIT section: one 36-byte record per placed unit
# ---------------------------------------------------------------------------
# richchk does not model this section (no UNIT transcoder as of 0.3.0), so it is
# parsed by hand here. Layout verified two ways: (1) staredit.net's published CHK
# spec, (2) parsing a real Blizzard ladder map's UNIT bytes with this exact
# struct and confirming known-good records (start locations, mineral/gas patches)
# decode sensibly -- see tools/README-test-map.md.
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

# OWNR / IOWN slot values, as the CHK spec defines them and as every stock map on
# disk carries them (checked directly: (2)Fading Realm.scx is [6,6,0,...],
# campaign\(1)Enslavers01.scm is [5,0,0,5,5,0,6,0,...]).
OWNR_INACTIVE = 0x00
OWNR_COMPUTER_GAME = 0x01
OWNR_HUMAN_OCCUPIED = 0x02
OWNR_RESCUE_PASSIVE = 0x03
OWNR_COMPUTER = 0x05
OWNR_HUMAN = 0x06
OWNR_NEUTRAL = 0x07
OWNR_NAMES = {
    OWNR_INACTIVE: "INACTIVE", OWNR_COMPUTER_GAME: "COMPUTER_GAME",
    OWNR_HUMAN_OCCUPIED: "HUMAN_OCCUPIED", OWNR_RESCUE_PASSIVE: "RESCUE_PASSIVE",
    0x04: "UNUSED", OWNR_COMPUTER: "COMPUTER", OWNR_HUMAN: "HUMAN(open slot)",
    OWNR_NEUTRAL: "NEUTRAL", 0x08: "CLOSED",
}

# SIDE section: one byte per player, the race the map assigns that slot.
SIDE_ZERG = 0x00
SIDE_TERRAN = 0x01
SIDE_PROTOSS = 0x02
SIDE_INDEPENDENT = 0x03
SIDE_NEUTRAL = 0x04
SIDE_USER_SELECTABLE = 0x05
SIDE_NAMES = {
    SIDE_ZERG: "Zerg", SIDE_TERRAN: "Terran", SIDE_PROTOSS: "Protoss",
    SIDE_INDEPENDENT: "Independent", SIDE_NEUTRAL: "Neutral",
    SIDE_USER_SELECTABLE: "User Selectable", 0x06: "Random", 0x07: "Inactive",
}
RACE_IDS = {"zerg": SIDE_ZERG, "terran": SIDE_TERRAN, "protoss": SIDE_PROTOSS}

# FORC per-force property flags (the section's last four bytes, one per force).
FORC_RANDOM_START = 0x01
FORC_ALLIED = 0x02
FORC_ALLIED_VICTORY = 0x04
FORC_SHARED_VISION = 0x08

# A handful of common unit type names (units.dat ids). Marine is the
# documented default: small, cheap, unambiguous to count on screen. Anything
# else can be passed as a raw units.dat integer id.
UNIT_TYPE_IDS = {
    "marine": 0,
    "zergling": 37,
    "zealot": 65,
    # Lurker is the fan-out fixture for untargeted ABILITIES (task 015/016): Burrow is
    # innate for lurkers -- no research, so it works on a map with no tech set at all --
    # it takes no target, and it leaves a per-unit state a plugin can read back and
    # assert on (CUnit+0xDC bit 0x10, SC_UNIT_FLAG_BURROWED).
    "lurker": 103,
}

# Which race each named unit type belongs to. Only used to pick a sensible default
# for the placed units' owner; a Terran player can own Lurkers perfectly well under
# Use Map Settings. Anything passed as a raw id defaults to Terran and can be
# overridden with --race.
UNIT_TYPE_RACES = {
    "marine": SIDE_TERRAN, "zergling": SIDE_ZERG, "zealot": SIDE_PROTOSS,
    "lurker": SIDE_ZERG,
}

DEFAULT_TEMPLATE = r"C:\sc-work\1161-base\Maps\BroodWar\Ladder\(2)Fading Realm.scx"
DEFAULT_OUTPUT = r"C:\sc-work\1161-base\Maps\test-many-units.scx"
DEFAULT_UNIT_COUNT = 36
# One tile between units, and the block CENTRED on the start location. Both matter:
# the camera opens centred on the start location and shows about 20x12 tiles, so a block
# that grows right-and-down from that point puts its far half off screen and behind the
# HUD, where no drag box can reach it. Bigger units need more room than one tile or the
# game drops the ones that cannot be placed -- pass --grid-spacing for those.
GRID_SPACING_PX = 32


def resolve_race(race: str | None, unit_type: str) -> int:
    if race:
        key = race.strip().lower()
        if key not in RACE_IDS:
            raise ValueError(f"Unknown race {race!r}; use one of {sorted(RACE_IDS)}.")
        return RACE_IDS[key]
    return UNIT_TYPE_RACES.get(unit_type.strip().lower(), SIDE_TERRAN)


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
    count: int, unit_id: int, player: int, center_x: int, center_y: int, next_instance: int,
    spacing: int = GRID_SPACING_PX,
) -> list[UnitRecord]:
    per_row = math.ceil(math.sqrt(count))
    rows = math.ceil(count / per_row)
    # Centre the block on (center_x, center_y) -- see GRID_SPACING_PX.
    origin_x = center_x - (per_row - 1) * spacing // 2
    origin_y = center_y - (rows - 1) * spacing // 2
    records = []
    for i in range(count):
        row, col = divmod(i, per_row)
        records.append(
            UnitRecord(
                instance=next_instance + i,
                x=origin_x + col * spacing,
                y=origin_y + row * spacing,
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


# ---------------------------------------------------------------------------
# MPQ IO
# ---------------------------------------------------------------------------
def read_chk_bytes(map_path: Path) -> bytes:
    """The raw staredit\\scenario.chk out of a map, via richchk's StormLib binding."""
    mpqio = StarCraftMpqIoHelper.create_mpq_io(None)
    with CrossPlatformSafeTemporaryNamedFile() as temp_chk_file:
        mpqio.extract_chk_from_mpq(str(map_path), temp_chk_file, overwrite_existing=True)
        return Path(temp_chk_file).read_bytes()


def _add_scenario_chk_like_blizzard(
    stormlib_wrapper, open_result, infile: str, path_in_archive: str
) -> None:
    """Write staredit\\scenario.chk into the archive with the flags/compression a
    real 1.16.1 client actually wrote, instead of richchk 0.3.0's hardcoded
    values.

    richchk's StormLibWrapper.add_file() (mpq/stormlib/stormlib_wrapper.py)
    hardcodes MPQ_FILE_COMPRESS + MPQ_COMPRESSION_ZLIB and never sets
    MPQ_FILE_ENCRYPTED, with no parameter to override either. Verified
    independently (task 013: an MPQ reader written from scratch against the
    public MoPaQ format spec, not richchk/StormLib) that every stock map checked
    stores this file ENCRYPTED and PKWARE-compressed (leading sector byte 0x08),
    while richchk's output is unencrypted and ZLIB-compressed (leading byte
    0x02). Classic 1.16.1 predates zlib support in Storm.dll; PKWARE
    ("implode") is the original, universally-supported method. This calls the
    same SFileAddFileEx export richchk uses, just with the flags that match every
    Blizzard-built map on disk.
    """
    flags = (
        StormLibFlag.MPQ_FILE_COMPRESS.value
        | StormLibFlag.MPQ_FILE_ENCRYPTED.value
        | StormLibFlag.MPQ_FILE_REPLACEEXISTING.value
    )
    compression = StormLibFlag.MPQ_COMPRESSION_PKWARE.value
    func = getattr(
        stormlib_wrapper.stormlib.stormlib_dll, StormLibOperation.S_FILE_ADD_FILE_EX.value
    )
    result = func(
        open_result.handle,
        infile,
        path_in_archive.encode("ascii"),
        flags,
        compression,
        compression,
    )
    if result == 0:
        get_last_error = getattr(stormlib_wrapper.stormlib.stormlib_dll, "GetLastError")
        get_last_error.restype = ctypes.c_uint
        raise ValueError(f"SFileAddFileEx failed, GetLastError={get_last_error()}")


def save_chk_bytes_to_mpq(chk_bytes: bytes, template: Path, output: Path) -> None:
    """Copy the template archive and drop the given scenario.chk into the copy,
    with Blizzard-matching flags/compression (see _add_scenario_chk_like_blizzard).
    Every other file in the archive is carried over untouched."""
    stormlib_wrapper = StormLibHelper.load_stormlib(None)
    with (
        CrossPlatformSafeTemporaryNamedFile() as temp_chk_file,
        CrossPlatformSafeTemporaryNamedFile() as temp_mpq_file,
    ):
        Path(temp_chk_file).write_bytes(chk_bytes)
        shutil.copyfile(str(template), temp_mpq_file)
        open_result = stormlib_wrapper.open_archive(
            temp_mpq_file, StormLibArchiveMode.STORMLIB_WRITE_ONLY
        )
        _add_scenario_chk_like_blizzard(
            stormlib_wrapper, open_result, temp_chk_file, _CHK_MPQ_PATH
        )
        stormlib_wrapper.close_archive(stormlib_wrapper.compact_archive(open_result))
        shutil.copyfile(temp_mpq_file, str(output))


def pick_opponent_slot(player: int) -> int:
    """The slot that becomes the (unit-less) computer opponent.

    Single-player Play Custom refuses to start a MELEE game with no computer slot at
    all -- "You must have at least one computer opponent." -- so a map with exactly one
    human and eleven inactive slots cannot be launched that way, whatever else is right
    about it. One COMPUTER slot satisfies that check; it is given no units anywhere on
    the map, so there is still nothing hostile in the game. Under Use Map Settings the
    check does not apply, but the slot is harmless there and keeps one map usable under
    both game types.
    """
    return 1 if player != 1 else 0


def generate_map(
    template: Path, output: Path, unit_count: int, unit_type: str, player: int,
    spacing: int = GRID_SPACING_PX, keep_ownr: bool = False,
    clear_player_units: bool = False, keep_triggers: bool = False,
    race: int = SIDE_TERRAN,
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

    template_chk = read_chk_bytes(template)
    sections = parse_chk_sections(template_chk)
    # The parser is only trustworthy if it can put the file back together
    # unchanged. Assert that before editing anything, so a template this tool
    # cannot represent fails loudly here instead of producing a subtly wrong map.
    if serialize_chk_sections(sections) != template_chk:
        raise ValueError(
            f"Template {template}: this tool's CHK parser does not round-trip it "
            "byte-for-byte; refusing to edit a file it does not fully understand."
        )
    require_single_chunk(sections, template)

    unit_idx = require_section(sections, "UNIT", template)
    existing_records = parse_unit_records(sections[unit_idx].payload)

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

    # Placing on top of the player's own units gives a mixed selection, and in game a
    # mixed selection is offered only the basic command card -- no unit ability button at
    # all. Clearing them first is what makes the generated map able to test an ability.
    kept_records = existing_records
    if clear_player_units:
        kept_records = [
            r for r in existing_records
            if r.player != player or r.unit_id == START_LOCATION_UNIT_ID
        ]

    next_instance = max((r.instance for r in existing_records), default=0) + 1
    new_records = build_new_unit_records(
        unit_count, unit_id, player, start.x, start.y, next_instance, spacing
    )
    sections = replace_section(
        sections, "UNIT",
        b"".join(pack_unit_record(r) for r in kept_records + new_records),
        template,
    )

    # Single player, no hostile pressure: the chosen slot becomes a human slot, every
    # other slot goes inactive (no computer players) bar one unit-less computer.
    #
    # OWNR 0x06 ("Human (Open Slot)"), NOT 0x02 (HUMAN_OCCUPIED). An earlier version
    # wrote 0x02 and the Play Custom dialog refused every map this generator produced
    # with "This map does not have a slot for a human participant" (Human Slots: 0).
    # 0x02 is what the game writes at RUNTIME for a slot a human has already taken;
    # what makes a slot available in the lobby is 0x06, which is what every stock
    # playable map carries for its human slots.
    # keep_ownr is for a template that is ALREADY a playable single-player scenario -- a
    # stock campaign mission, say. Rewriting its slots would delete the mission's own
    # actors and leave a map whose triggers reference players that no longer exist.
    if not keep_ownr:
        ownr_idx = require_section(sections, "OWNR", template)
        old = sections[ownr_idx].payload
        if len(old) != 12:
            raise ValueError(f"Template {template}: OWNR is {len(old)} bytes, expected 12")
        slots = [OWNR_INACTIVE] * 12
        slots[player] = OWNR_HUMAN
        slots[pick_opponent_slot(player)] = OWNR_COMPUTER
        sections = replace_section(sections, "OWNR", bytes(slots), template)

        # THE SLOT'S RACE MUST BE AN EXPLICIT ONE, NOT "User Selectable" (task 016).
        #
        # This is what made every melee-template map play as a melee game no matter what
        # the lobby's Game Type said. A Blizzard LADDER map carries SIDE = 0x05 "User
        # Selectable" for its human slots, because a ladder player picks a race in the
        # lobby. Load such a map under Use Map Settings and StarCraft still hands that
        # slot the standard melee starting units for whichever race got picked -- proved
        # in-process on 2026-08-08: the plugin's UNITSTATE reported
        # types=[0x29:4 0x23:3 0x2A:1] (four Drones, three Larva, one Overlord) on a
        # 36-Lurker map, with the Game Type combo explicitly set to Use Map Settings from
        # its list. A stock campaign map, which plays correctly under exactly the same
        # menu path, carries a FIXED race for its human slot (Enslavers02b: 0x02 Protoss).
        # Writing a fixed race here is the difference.
        side_idx = require_section(sections, "SIDE", template)
        old_side = sections[side_idx].payload
        if len(old_side) != 12:
            raise ValueError(f"Template {template}: SIDE is {len(old_side)} bytes, expected 12")
        sides = list(old_side)
        sides[player] = race
        # The computer slot gets a fixed race too, for the same reason: a slot left on
        # "User Selectable" is a slot the engine may hand a melee base to, and a computer
        # with a base is hostile pressure this fixture must not have.
        sides[pick_opponent_slot(player)] = race
        sections = replace_section(sections, "SIDE", bytes(sides), template)

        # AND THE HUMAN MUST LAND ON THE SLOT THAT OWNS THE UNITS (task 016).
        #
        # FORC's last four bytes are per-force property flags; bit 0x01 is "randomize
        # start location" (staredit.net CHK spec). A Blizzard ladder map sets it --
        # (2)Fading Realm.scx carries 0x01 on Force 1, which every slot belongs to.
        #
        # What was OBSERVED, not what the engine is assumed to do internally: across
        # three in-game loads of an otherwise-finished fixture, one came up with the
        # plugin logging `player=1/1/1` and `UNITSTATE n=0` on a black screen, while the
        # other two logged player 0 and the expected 36 units -- same map file, same menu
        # path, same lobby. So with this bit set the human's own player id is not fixed,
        # and when it is not slot 0 they own none of the placed units. Three runs since
        # clearing it, all `player=0/0/0`; that is a small sample, and the reason to
        # clear the bit is that a fixture must not depend on which slot the engine picks
        # at all. The other three bits (allied, allied victory, shared vision) are left
        # alone.
        forc_idx = require_section(sections, "FORC", template)
        forc = bytearray(sections[forc_idx].payload)
        if len(forc) != 20:
            raise ValueError(f"Template {template}: FORC is {len(forc)} bytes, expected 20")
        for i in range(16, 20):
            forc[i] &= ~FORC_RANDOM_START & 0xFF
        sections = replace_section(sections, "FORC", bytes(forc), template)

    # THE MISSION MUST NOT BE ABLE TO END ITSELF (task 016).
    #
    # Under Use Map Settings the engine runs no melee win/lose logic of its own: a game
    # ends when a trigger says Victory, Defeat or End Scenario, and otherwise never. Stock
    # maps all ship triggers that do exactly that. Decoded straight out of the files:
    #   (2)Fading Realm.scx (LADDER) carries the three standard melee triggers, the third
    #   being "All players: non-allied-victory-players command at most 0 [231] -> Victory",
    #   which reads as TRUE for the human on the first frame of a generated map, since the
    #   only other participant is the unit-less computer opponent;
    #   (1)Enslavers02b.scm (CAMPAIGN) carries 30 triggers, six of which end the game --
    #   "Force 1: current player commands at most 0 [Men] -> Defeat" and five more on
    #   specific unit ids the mission requires.
    # The campaign case was also confirmed in game (task 016, 2026-08-08): with triggers
    # kept, "Congratulations! You are victorious!" about nine seconds in. None of it has
    # anything to do with the CHK round-trip that was previously suspected -- task 016
    # diffed a campaign template's TRIG across that round-trip and it is byte-identical.
    #
    # An empty TRIG section is a legal, common thing for a CHK to hold -- (2)Fading
    # Realm.scx ships a zero-length MBRF -- and it is what makes a generated map sit
    # there indefinitely, which is the whole point of a test fixture.
    if not keep_triggers:
        for name in ("TRIG", "MBRF"):
            if find_section(sections, name) >= 0:
                sections = replace_section(sections, name, b"", template)

    new_chk = serialize_chk_sections(sections)
    output.parent.mkdir(parents=True, exist_ok=True)
    save_chk_bytes_to_mpq(new_chk, template, output)


def diff_against_template(output: Path, template: Path) -> list[str]:
    """Names of the CHK sections whose bytes differ between template and output.

    The generator changes UNIT, OWNR and TRIG/MBRF and nothing else; anything
    else in this list is a bug, and the validator fails on it. This is the
    assertion that the old richchk round-trip could not have passed.
    """
    a = parse_chk_sections(read_chk_bytes(template))
    b = parse_chk_sections(read_chk_bytes(output))
    changed = []
    for i in range(max(len(a), len(b))):
        sa = a[i] if i < len(a) else None
        sb = b[i] if i < len(b) else None
        if sa is None:
            changed.append(f"+{sb.name}")
        elif sb is None:
            changed.append(f"-{sa.name}")
        elif sa.name != sb.name:
            changed.append(f"{sa.name}->{sb.name}")
        elif sa.payload != sb.payload:
            changed.append(sa.name)
    return changed


def validate_map(
    path: Path, unit_count: int, unit_type: str, player: int, keep_ownr: bool = False,
    keep_triggers: bool = False, template: Path | None = None,
) -> None:
    unit_id = resolve_unit_id(unit_type)
    sections = parse_chk_sections(read_chk_bytes(path))
    # Duplicated additive chunks would make every count below a half-truth: the
    # numbers would describe one chunk while the game reads them all.
    require_single_chunk(sections, path)

    unit_idx = find_section(sections, "UNIT")
    if unit_idx < 0:
        raise AssertionError(f"{path}: no UNIT section found")
    records = parse_unit_records(sections[unit_idx].payload)

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

    ownr_idx = find_section(sections, "OWNR")
    if ownr_idx < 0:
        raise AssertionError(f"{path}: no OWNR section found")
    slots = list(sections[ownr_idx].payload)
    actual = slots[player]

    dim_idx = find_section(sections, "DIM")
    if dim_idx < 0 or len(sections[dim_idx].payload) < 4:
        raise AssertionError(f"{path}: no usable DIM section")
    width, height = struct.unpack_from("<HH", sections[dim_idx].payload, 0)
    if width <= 0 or height <= 0:
        raise AssertionError(f"{path}: invalid terrain dimensions {width}x{height}")

    # Nothing may be able to end the game on its own -- the property that makes this a
    # fixture rather than a mission. See the TRIG note in generate_map().
    trig_idx = find_section(sections, "TRIG")
    trig_len = len(sections[trig_idx].payload) if trig_idx >= 0 else 0
    if not keep_triggers and trig_len != 0:
        raise AssertionError(
            f"{path}: TRIG holds {trig_len} bytes ({trig_len // 2400} trigger(s)); a "
            "generated fixture must carry none, or the map's own victory/defeat "
            "triggers end the game within seconds of loading"
        )

    if keep_ownr:
        if actual not in (OWNR_HUMAN, OWNR_HUMAN_OCCUPIED):
            raise AssertionError(
                f"{path}: --keep-ownr was used but player {player}'s slot is "
                f"{OWNR_NAMES.get(actual, actual)}, which no human can occupy"
            )
    else:
        if actual != OWNR_HUMAN:
            raise AssertionError(
                f"{path}: player {player} OWNR slot is {OWNR_NAMES.get(actual, actual)}, "
                f"expected HUMAN (0x06 'Human (Open Slot)' -- 0x02 HUMAN_OCCUPIED makes "
                f"the Play Custom dialog report 'no slot for a human participant')"
            )
        # Exactly one computer slot, and it must own nothing: that is what keeps "at
        # least one computer opponent" satisfied for a melee-type launch while leaving
        # nothing hostile in the game. More than one, or one with units, is a bug.
        opponent = pick_opponent_slot(player)
        computers = [
            i for i, t in enumerate(slots)
            if i != player and t in (OWNR_COMPUTER, OWNR_COMPUTER_GAME)
        ]
        if computers != [opponent]:
            raise AssertionError(
                f"{path}: computer slots are {computers}, expected exactly [{opponent}]"
            )
        opponent_units = [
            r for r in records
            if r.player == opponent and r.unit_id != START_LOCATION_UNIT_ID
        ]
        if opponent_units:
            raise AssertionError(
                f"{path}: the computer opponent owns {len(opponent_units)} unit(s); it "
                f"must own none, or the map is not hostility-free"
            )
        # No active slot may be left on "User Selectable" -- that is what makes the
        # engine hand out melee starting units under Use Map Settings. See the SIDE
        # note in generate_map().
        side_idx = find_section(sections, "SIDE")
        if side_idx < 0:
            raise AssertionError(f"{path}: no SIDE section found")
        sides = list(sections[side_idx].payload)
        for slot in (player, opponent):
            if sides[slot] == SIDE_USER_SELECTABLE:
                raise AssertionError(
                    f"{path}: SIDE[{slot}] is 0x05 'User Selectable'; the engine gives "
                    f"such a slot the standard MELEE starting units even under Use Map "
                    f"Settings, and the map's own placed units are never created"
                )
        # No force may randomise start locations: that shuffles which player id the human
        # actually plays as, and half the time they are not the one owning the units. See
        # the FORC note in generate_map().
        forc_idx = find_section(sections, "FORC")
        if forc_idx < 0:
            raise AssertionError(f"{path}: no FORC section found")
        random_start = [
            i for i, f in enumerate(sections[forc_idx].payload[16:20])
            if f & FORC_RANDOM_START
        ]
        if random_start:
            raise AssertionError(
                f"{path}: force(s) {[i + 1 for i in random_start]} still carry the FORC "
                f"'randomize start location' bit (0x01); with it set the human's player "
                f"id is not fixed, and on a slot other than {player} they own none of the "
                f"placed units"
            )

    changed = None
    if template is not None and template.exists():
        changed = diff_against_template(path, template)
        # Only the sections this run actually edited may differ. With --keep-triggers
        # the tool does not touch TRIG/MBRF at all, so whitelisting them there would
        # let a real difference in them pass unnoticed -- same reasoning as keep_ownr.
        expected = {"UNIT"}
        if not keep_ownr:
            expected |= {"OWNR", "SIDE", "FORC"}
        if not keep_triggers:
            expected |= {"TRIG", "MBRF"}
        unexpected = [c for c in changed if c not in expected]
        if unexpected:
            raise AssertionError(
                f"{path}: the output differs from its template in section(s) "
                f"{unexpected}, which this tool never asked to change. Every other "
                f"section must come across byte-for-byte."
            )

    print(f"OK: {path}")
    print(f"  {len(matching)} unit(s) of type {unit_id} owned by player {player}")
    print(f"  start location for player {player} at ({start.x}, {start.y})")
    side_idx = find_section(sections, "SIDE")
    side = list(sections[side_idx].payload)[player] if side_idx >= 0 else None
    if keep_ownr:
        print(f"  OWNR left as the template had it; player {player} = "
              f"{OWNR_NAMES.get(actual, actual)}")
    else:
        print(f"  OWNR[{player}] = {OWNR_NAMES.get(actual, actual)}; one unit-less "
              f"computer slot at {pick_opponent_slot(player)}")
    print(f"  SIDE[{player}] = {SIDE_NAMES.get(side, side)}"
          + ("" if side == SIDE_USER_SELECTABLE else " -- not 'User Selectable', so the "
             "engine adds no melee starting units"))
    forc_idx = find_section(sections, "FORC")
    if forc_idx >= 0:
        flags = list(sections[forc_idx].payload[16:20])
        print("  FORC force flags " + " ".join(f"0x{f:02X}" for f in flags)
              + (" -- no force randomises start locations, so the human's player id is "
                 f"not left to the engine to pick"
                 if not any(f & FORC_RANDOM_START for f in flags) else ""))
    print(f"  TRIG holds {trig_len} byte(s)"
          + ("" if keep_triggers else " -- nothing can end the game on its own"))
    print(f"  terrain {width}x{height} tiles")
    if changed is not None:
        print(f"  differs from the template ONLY in: {' '.join(changed) or '(nothing)'}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--unit-count", type=int, default=DEFAULT_UNIT_COUNT)
    parser.add_argument("--unit-type", type=str, default="marine")
    parser.add_argument("--player", type=int, default=0, help="0-based player slot (0 = Player 1)")
    parser.add_argument(
        "--grid-spacing",
        type=int,
        default=GRID_SPACING_PX,
        help="pixels between placed units (32 = one tile). Units bigger than a tile "
             "need more, or the game drops the ones it cannot place.",
    )
    parser.add_argument(
        "--race", type=str, default=None, choices=sorted(RACE_IDS),
        help="Race written into SIDE for the human and computer slots. Defaults to the "
             "race the placed unit type belongs to. It must not be left as the "
             "template's 'User Selectable' -- see the SIDE note in generate_map.",
    )
    parser.add_argument("--template", type=Path, default=Path(DEFAULT_TEMPLATE))
    parser.add_argument("--output", type=Path, default=Path(DEFAULT_OUTPUT))
    parser.add_argument(
        "--keep-ownr",
        action="store_true",
        help="Do not rewrite the player slots. Use when the template is already a "
             "playable single-player scenario (a stock campaign mission).",
    )
    parser.add_argument(
        "--clear-player-units",
        action="store_true",
        help="Remove the target player's existing units first, so the placed group is "
             "all one type (a mixed selection gets no ability buttons in game).",
    )
    parser.add_argument(
        "--keep-triggers",
        action="store_true",
        help="Keep the template's TRIG/MBRF sections. NOT for a test fixture: every "
             "stock map ships triggers that end the game, and they fire within seconds "
             "of loading a generated map (see the TRIG note in generate_map).",
    )
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
            validate_map(
                args.validate_only, args.unit_count, args.unit_type, args.player,
                args.keep_ownr, args.keep_triggers,
            )
            return 0

        generate_map(
            args.template, args.output, args.unit_count, args.unit_type, args.player,
            args.grid_spacing, args.keep_ownr, args.clear_player_units, args.keep_triggers,
            resolve_race(args.race, args.unit_type),
        )
        print(f"wrote {args.output}")
        if not args.no_validate:
            validate_map(
                args.output, args.unit_count, args.unit_type, args.player, args.keep_ownr,
                args.keep_triggers, args.template,
            )
        return 0
    except (ValueError, FileNotFoundError, AssertionError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
