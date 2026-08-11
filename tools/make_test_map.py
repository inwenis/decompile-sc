#!/usr/bin/env python3
"""Generate a single-player StarCraft 1.16.1 test map with many units pre-placed.

Purpose: a fast fixture for testing "select more than 12 units at once" (the
project's north star mod) and for testing what one order does to all of them.
Loading the map should drop the player next to a cluster of units big enough
that one drag-box grabs more than the classic 12-unit selection cap, on a map
that then sits there and does nothing until the test is over.

See tools/README-test-map.md for the approach, the two failures task 016
root-caused, and known limitations.

Task 019 added an optional second, COMPUTER-owned force (--enemy-count) so a test can
walk the player's units into it and prove what happens when a selected unit DIES.
Without it the map is exactly the hostility-free fixture tasks 015-017 used.

Usage:
    python tools/make_test_map.py
    python tools/make_test_map.py --unit-count 36 --unit-type lurker --player 0
    python tools/make_test_map.py --unit-count 36 --unit-type lurker --enemy-count 6
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

# The `hp` byte is a PERCENTAGE of the unit type's maximum, 1-100 (staredit.net CHK
# spec, the same source as the rest of this record layout), and it only applies
# because bit 0x02 of the valid-properties mask above is set -- which it has been
# since task 009, with every generated fixture written at 100.
#
# It sits at offset 0x11 of the 36-byte record, right after the owner byte at 0x10.
# Checked rather than counted by eye: packing a record through _UNIT_RECORD_FMT with
# hp=30 puts 30 at byte 0x11, and 0x19 -- which an earlier draft of this comment
# named -- is the high byte of the `units in hangar` u16 at 0x18, which this tool
# always writes as zero. Nothing in the generator ever addresses the field by a
# literal offset (it packs the named struct field), so no map was ever wrong; the
# offset is documentation, and in this repo documentation of an offset is the
# deliverable.
#
# Task 019 exposed it as --unit-hp because a full-health 125-point Lurker takes
# roughly twenty Hydralisk shots to kill, and the combat test spent minutes waiting
# for the first one. It is the cheapest speed-up available that keeps every property
# the fixture needs: same unit type, same evidence, same inability to shoot back --
# only the number of shots each victim absorbs changes. The effect is asserted in
# game rather than assumed: tools/plugin/test-combat-death.ps1 fails if the first
# death takes longer than its deadline.
MIN_HP_PERCENT = 1
MAX_HP_PERCENT = 100

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
#
# Every id here is read off richchk's own units.dat enum
# (.venv/Lib/site-packages/richchk/model/richchk/unis/unit_id.py, `UnitId`), which
# is the source that caught task 013's zealot=64 mistake (64 is Protoss Probe;
# Zealot is 65). Printed straight out of that enum:
#     0 Terran Marine        3 Terran Goliath      5 Terran Siege Tank (Tank Mode)
#    37 Zerg Zergling       38 Zerg Hydralisk     39 Zerg Ultralisk
#    65 Protoss Zealot      66 Protoss Dragoon   103 Zerg Lurker
UNIT_TYPE_IDS = {
    "marine": 0,
    # Ghost (task 022): the only vanilla unit with an UNTARGETED, ENERGY-costed ability
    # (Personnel Cloaking, command 0x21) that a generated map can switch on -- which is
    # what makes the energy half of "does every unit pay its own cost" testable in game
    # at all. It is also the unit in the user's own report ("a cloaked ghost did not
    # attack enemies at some point").
    "ghost": 1,
    "medic": 34,
    "goliath": 3,
    "siege-tank": 5,
    "zergling": 37,
    # Hydralisk is the default ENEMY (task 019): a ranged ground attacker, so it can
    # hurt a block of units standing next to it without having to path into the
    # middle of them, and it is cheap enough that a handful of them kill a Lurker
    # slowly rather than wiping the boxed selection below the 12-unit cap.
    "hydralisk": 38,
    "ultralisk": 39,
    "zealot": 65,
    "dragoon": 66,
    # Lurker is the fan-out fixture for untargeted ABILITIES (task 015/016): Burrow is
    # innate for lurkers -- no research, so it works on a map with no tech set at all --
    # it takes no target, and it leaves a per-unit state a plugin can read back and
    # assert on (CUnit+0xDC bit 0x10, SC_UNIT_FLAG_BURROWED).
    #
    # It is ALSO the task-019 combat fixture's player unit, for a second reason: an
    # UNBURROWED Lurker has no weapon at all (its only attack, the subterranean
    # spines, is a burrowed-only weapon). A block of them walked into an enemy
    # therefore takes fire without killing the enemy back, so the enemy force
    # survives and the death trickle is steady instead of being decided by which
    # side wins a fight. Confirmed in game rather than assumed -- see
    # tools/README-test-map.md "Combat variant".
    "lurker": 103,
    # Neither of these is ever PLACED by this tool. They are named because they are what
    # the production fixtures TRAIN, and `--unit-build-time probe=8` is the fixture
    # speed-up task 031 exists for -- a flag needs a name for its target even when the
    # target only ever comes out of a building. Both cross-checked against the template's
    # own UNIx entry rather than taken from a table: SCV 60 hit points / build 300 (20 game
    # seconds) / 50 minerals, Probe 20 hit points / build 300 / 50 minerals.
    "scv": 7,
    "probe": 64,
    # Task 025's production fixture. A Command Center is the cheapest way to get a
    # building that TRAINS -- it produces SCVs (50 minerals, 1 supply) and it supplies
    # 10 of its own, so a fixture needs it plus a couple of depots and nothing else.
    "command-center": 106,
    "supply-depot": 109,
    "barracks": 111,
    # Task 029's upgrade-queue fixture. An Engineering Bay is the cheapest building
    # that RESEARCHES: it offers two independent level-1 upgrades -- Terran Infantry
    # Armor (upgrades.dat 0) and Terran Infantry Weapons (upgrades.dat 7) -- so two
    # distinct items can be queued at one building without touching the messy
    # level-N/level-N+1 case, and it needs no prerequisite building of its own.
    # An Academy is the companion fixture for the OTHER opcode: it carries techs
    # (0x30 Tech) as well as an upgrade (0x32), so a mixed queue is expressible.
    "engineering-bay": 122,
    "academy": 112,
    # Task 028's cancel fixture. Its command card carries the Cancel button -- the
    # one that emits "cancel the last queued item" (actionParam 0xFE), the only wire
    # form a plugin holding queue overflow can be asked to serve -- at slot 9 with
    # no other button sharing that slot, needs no Pylon to produce (a Gateway
    # would), and supplies 9 psi of its own, so a queue of Probes needs no second
    # building to be legal.
    #
    # A Terran producer would in fact have done: slot 9 there is shared with Land and
    # Lift Off, but their conditions are complementary to Cancel's, so the control
    # shows Cancel exactly while something is queued (research/production-queue.md
    # 8.3, measured in game after the button table suggested otherwise).
    "nexus": 154,
}

# Which race each named unit type belongs to. Only used to pick a sensible default
# for the placed units' owner; a Terran player can own Lurkers perfectly well under
# Use Map Settings. Anything passed as a raw id defaults to Terran and can be
# overridden with --race.
UNIT_TYPE_RACES = {
    "marine": SIDE_TERRAN, "ghost": SIDE_TERRAN, "medic": SIDE_TERRAN,
    "goliath": SIDE_TERRAN, "siege-tank": SIDE_TERRAN, "scv": SIDE_TERRAN,
    "zergling": SIDE_ZERG, "hydralisk": SIDE_ZERG, "ultralisk": SIDE_ZERG,
    "zealot": SIDE_PROTOSS, "dragoon": SIDE_PROTOSS,
    "lurker": SIDE_ZERG,
    "command-center": SIDE_TERRAN, "supply-depot": SIDE_TERRAN, "barracks": SIDE_TERRAN,
    "engineering-bay": SIDE_TERRAN, "academy": SIDE_TERRAN,
    "nexus": SIDE_PROTOSS, "probe": SIDE_PROTOSS,
}

# ---------------------------------------------------------------------------
# STARTING RESOURCES (task 025)
# ---------------------------------------------------------------------------
# A CHK has no "starting minerals" field. Under every game type but Use Map Settings the
# engine hands out its own melee default (50 ore, no gas); under Use Map Settings -- the
# type every suite in this repo plays its fixtures under -- a map gets whatever its own
# TRIGGERS give it. So a fixture that has to afford more than one unit needs exactly one
# trigger: "Always -> Set Resources".
#
# That is the ONLY trigger this tool will write, and it carries no Victory, Defeat or End
# Scenario action, so the property the TRIG note in generate_map() protects -- the mission
# must not be able to end itself -- still holds. validate_map re-derives that from the
# bytes rather than trusting this comment.
#
# Layout, from the same source as the rest of this file: richchk's own decoded models
# (.venv/Lib/site-packages/richchk/model/chk/trig/decoded_trigger{,_action,_condition}.py
# and .../richchk/transcoder/richchk/transcoders/trig/actions/set_resources_action_transcoder.py),
# which name every field of the 20-byte condition and 32-byte action and say exactly which
# of them Set Resources fills. CONFIRMED BY ARITHMETIC against the size the rest of this
# file already assumes for a trigger: 16*20 + 64*32 + 4 + 27 + 1 == 2400, which is the
# divisor validate_map has used since task 016.
TRIG_CONDITIONS = 16
TRIG_CONDITION_BYTES = 20
TRIG_ACTIONS = 64
TRIG_ACTION_BYTES = 32
TRIG_PLAYER_FLAGS = 27
TRIG_BYTES = (TRIG_CONDITIONS * TRIG_CONDITION_BYTES
              + TRIG_ACTIONS * TRIG_ACTION_BYTES
              + 4 + TRIG_PLAYER_FLAGS + 1)          # == 2400

TRIG_CONDITION_ALWAYS = 22       # richchk TriggerConditionId.ALWAYS
TRIG_ACTION_SET_RESOURCES = 26   # richchk TriggerActionId.SET_RESOURCES
TRIG_AMOUNT_SET_TO = 7           # richchk AmountModifier.SET_TO
TRIG_RESOURCE_ORE = 0            # richchk ResourceType.ORE
TRIG_RESOURCE_GAS = 1            # richchk ResourceType.GAS


def _trigger_condition_always() -> bytes:
    """The 20-byte `Always` condition: every field zero but the condition byte at +15."""
    cond = bytearray(TRIG_CONDITION_BYTES)
    cond[15] = TRIG_CONDITION_ALWAYS
    return bytes(cond)


def _trigger_action_set_resources(player: int, amount: int, resource: int) -> bytes:
    """The 32-byte `Set Resources` action.

    Fields, and nothing else, per the richchk transcoder cited above:
      +16 u32 first group  = the player
      +20 u32 second group = the amount
      +24 u16 argument     = the resource type
      +26 u8  action byte  = 26
      +27 u8  modifier     = 7 (Set To)
    """
    act = bytearray(TRIG_ACTION_BYTES)
    struct.pack_into("<II", act, 16, player, amount)
    struct.pack_into("<H", act, 24, resource)
    act[26] = TRIG_ACTION_SET_RESOURCES
    act[27] = TRIG_AMOUNT_SET_TO
    return bytes(act)


def build_starting_resources_trig(player: int, minerals: int, gas: int) -> bytes:
    """One trigger: `Always -> Set Resources`, executed for `player` only.

    No Preserve Trigger action, so StarCraft disables it once its actions have run --
    it fires on the first trigger loop of the game and never again.
    """
    if not 0 <= player < TRIG_PLAYER_FLAGS:
        raise ValueError(f"player {player} is outside the trigger's 0..{TRIG_PLAYER_FLAGS - 1} range")
    for name, value in (("minerals", minerals), ("gas", gas)):
        if value is not None and not 0 <= value <= 0xFFFFFFFF:
            raise ValueError(f"--starting-{name} must be a non-negative 32-bit value, got {value}")

    actions = []
    if minerals is not None:
        actions.append(_trigger_action_set_resources(player, minerals, TRIG_RESOURCE_ORE))
    if gas is not None:
        actions.append(_trigger_action_set_resources(player, gas, TRIG_RESOURCE_GAS))
    if not actions:
        raise ValueError("build_starting_resources_trig called with nothing to set")
    if len(actions) > TRIG_ACTIONS:
        raise ValueError("too many actions for one trigger")

    out = bytearray()
    out += _trigger_condition_always()
    out += bytes(TRIG_CONDITION_BYTES) * (TRIG_CONDITIONS - 1)
    for act in actions:
        out += act
    out += bytes(TRIG_ACTION_BYTES) * (TRIG_ACTIONS - len(actions))
    out += struct.pack("<I", 0)                       # execution flags: no preserve
    flags = bytearray(TRIG_PLAYER_FLAGS)
    flags[player] = 1                                 # executed for this player only
    out += bytes(flags)
    out += bytes(1)                                   # current action index
    assert len(out) == TRIG_BYTES, f"trigger is {len(out)} bytes, expected {TRIG_BYTES}"
    return bytes(out)


def read_starting_resources(trig_payload: bytes) -> list[tuple[int, int, int]]:
    """Every (player, resource, amount) a TRIG payload's Set Resources actions grant.

    Used by validate_map to check the trigger it wrote from the BYTES, and to prove the
    same payload carries no game-ending action.
    """
    out: list[tuple[int, int, int]] = []
    for base in range(0, len(trig_payload) - TRIG_BYTES + 1, TRIG_BYTES):
        acts = base + TRIG_CONDITIONS * TRIG_CONDITION_BYTES
        flags_at = acts + TRIG_ACTIONS * TRIG_ACTION_BYTES + 4
        players = [p for p in range(TRIG_PLAYER_FLAGS)
                   if trig_payload[flags_at + p] == 1]
        for i in range(TRIG_ACTIONS):
            off = acts + i * TRIG_ACTION_BYTES
            action_id = trig_payload[off + 26]
            if action_id == 0:
                break
            if action_id != TRIG_ACTION_SET_RESOURCES:
                continue
            amount = struct.unpack_from("<I", trig_payload, off + 20)[0]
            resource = struct.unpack_from("<H", trig_payload, off + 24)[0]
            for p in players:
                out.append((p, resource, amount))
    return out


def trigger_action_ids(trig_payload: bytes) -> set[int]:
    """Every non-zero action byte in a TRIG payload."""
    ids: set[int] = set()
    for base in range(0, len(trig_payload) - TRIG_BYTES + 1, TRIG_BYTES):
        acts = base + TRIG_CONDITIONS * TRIG_CONDITION_BYTES
        for i in range(TRIG_ACTIONS):
            action_id = trig_payload[acts + i * TRIG_ACTION_BYTES + 26]
            if action_id == 0:
                break
            ids.add(action_id)
    return ids


# ---------------------------------------------------------------------------
# TECH STATE (task 022)
# ---------------------------------------------------------------------------
# Every untargeted ability in vanilla that COSTS the acting unit something needs
# research: Stim Packs (HP), Cloaking Field / Personnel Cloaking (energy). Burrow is
# the one exception, and only for Lurkers -- which is why task 016's fixture used
# Lurkers and why no fixture before this one could test a per-unit COST at all.
#
# A Use Map Settings map carries the tech state in PTEx (Brood War, 44 techs). Layout,
# from the staredit.net CHK spec, and CONFIRMED BY ARITHMETIC against the template on
# disk: 44*12 + 44*12 + 44 + 44 + 44*12 == 1672, which is exactly the section's size in
# (2)Fading Realm.scx. A layout that reproduces the real section size to the byte, for a
# section this tool did not write, is not a guess.
#
# THE PER-PLAYER ARRAYS ARE PLAYER-MAJOR: index = player * 44 + tech (task 026).
#
# This tool had it TECH-major, and that was wrong in a way nothing here could catch:
# `tech * 12 + player` and `player * 44 + tech` agree at exactly one point, tech 0 for
# player 0 -- which is Stim Packs for the human slot, the only tech any fixture had ever
# proved worked. `--tech-researched personnel-cloaking` (tech 10) wrote byte 120, which
# the engine reads as player 2's tech 32; player 0's tech 10 stayed 0, the Ghost's Cloak
# button came up GREYED, and task 022's whole "the ability row is inert" reading was that
# and nothing else. The user spotted it from the screen before we spotted it from the
# code: "the ghosts didn't have the cloak ability unlocked".
#
# The indexing is now read out of THIS BINARY rather than out of prose. The PTEx applier
# 0x004CB7D0 (research/command-card.md 6) walks the section like this:
#
#     0x004CB870  SUB EBX,0x2c            ; EBX = player * 44  -- the OUTER step
#     0x004CB873  SUB ESI,0x18            ; ESI = player * 24  -- the destination array
#     0x004CB879  MOV EAX,0x2c            ; EAX = tech, 43..0  -- the INNER index
#     0x004CB881  LEA ECX,[EBP + EBX + -0x210]     ; playerUsesDefault + player*44
#     0x004CB888  CMP byte ptr [ECX + EAX],0x0     ;   ... + tech
#     0x004CB8CC  LEA ECX,[EBX + EAX]              ; player*44 + tech
#     0x004CB8CF  MOV DL,byte ptr [EBP + ECX + -0x688]  ; playerAvailability[that]
#     0x004CB8EE  MOV DL,byte ptr [EBP + EDX + -0x478]  ; playerAlreadyResearched[that]
#     0x004CB8FB  MOV byte ptr [ESI + ECX + 0x58cf44],DL ; -> techResearched[player][tech]
#
# and the five stack bases it uses are 0x688 / 0x478 / 0x268 / 0x23C / 0x210 below EBP,
# whose successive differences are 0x210, 0x210, 0x2C, 0x2C -- i.e. exactly the five
# sub-arrays below, in order. PTEC (the 24-tech vanilla section, applier 0x004CB670) has
# the same shape with 24 in place of 44.
PTEX_TECHS = 44
PTEX_PLAYERS = 12
PTEX_OFF_PLAYER_AVAILABLE = 0                                        # [player][tech]
PTEX_OFF_PLAYER_RESEARCHED = PTEX_TECHS * PTEX_PLAYERS               # 528
PTEX_OFF_DEFAULT_AVAILABLE = PTEX_OFF_PLAYER_RESEARCHED + PTEX_TECHS * PTEX_PLAYERS
PTEX_OFF_DEFAULT_RESEARCHED = PTEX_OFF_DEFAULT_AVAILABLE + PTEX_TECHS
PTEX_OFF_USES_DEFAULT = PTEX_OFF_DEFAULT_RESEARCHED + PTEX_TECHS     # [player][tech]
PTEX_SIZE = PTEX_OFF_USES_DEFAULT + PTEX_TECHS * PTEX_PLAYERS        # 1672


def ptex_index(tech: int, player: int) -> int:
    """Offset of (tech, player) inside one PTEx per-player array.

    PLAYER-MAJOR, per the applier disassembly above. One function, so the write and
    the read-back cannot drift apart -- they did, and a wrong write verified by an
    equally wrong read reported success for a fixture the engine never received.
    """
    return player * PTEX_TECHS + tech

# techdata.dat ids, printed straight out of richchk's own enum
# (.venv/Lib/site-packages/richchk/model/richchk/techs/tech_id.py, `TechId`) -- the same
# source, and the same provenance discipline, as UNIT_TYPE_IDS above. Only the ones a
# fixture in this repo has needed are named; anything else can be passed as a raw id.
TECH_IDS = {
    "stim-packs": 0,
    "siege-mode": 5,
    "cloaking-field": 9,       # Wraith; an UNTARGETED ability that costs ENERGY
    "personnel-cloaking": 10,  # Ghost; likewise
    "burrowing": 11,
}


def resolve_tech_id(tech: str) -> int:
    try:
        value = int(tech)
    except ValueError:
        key = tech.strip().lower()
        if key not in TECH_IDS:
            raise ValueError(
                f"Unknown tech {tech!r}. Use one of {sorted(TECH_IDS)} or a raw "
                f"techdata.dat integer id."
            ) from None
        value = TECH_IDS[key]
    if not 0 <= value < PTEX_TECHS:
        raise ValueError(f"tech id must be 0-{PTEX_TECHS - 1}, got {value}")
    return value


def set_techs_researched(payload: bytes, tech_ids: list[int], player: int) -> bytes:
    """PTEx with `tech_ids` marked available AND already-researched for `player`.

    Three bytes per (tech, player), and all three are needed: the per-player entries say
    what this player has, and `playerUsesDefault` has to be CLEARED or the engine reads
    the map-wide default instead and the per-player bytes are dead.
    """
    if len(payload) != PTEX_SIZE:
        raise ValueError(
            f"PTEx is {len(payload)} bytes, expected {PTEX_SIZE}; this tool only "
            f"understands the Brood War {PTEX_TECHS}-tech layout."
        )
    if not 0 <= player < PTEX_PLAYERS:
        raise ValueError(f"player must be 0-{PTEX_PLAYERS - 1}, got {player}")
    buf = bytearray(payload)
    for tech in tech_ids:
        idx = ptex_index(tech, player)
        buf[PTEX_OFF_PLAYER_AVAILABLE + idx] = 1
        buf[PTEX_OFF_PLAYER_RESEARCHED + idx] = 1
        buf[PTEX_OFF_USES_DEFAULT + idx] = 0
    return bytes(buf)


def read_techs_researched(payload: bytes, player: int) -> list[int]:
    """Which techs PTEx says `player` has already researched, per-player bytes only."""
    if len(payload) != PTEX_SIZE:
        raise ValueError(f"PTEx is {len(payload)} bytes, expected {PTEX_SIZE}")
    out = []
    for tech in range(PTEX_TECHS):
        idx = ptex_index(tech, player)
        if (payload[PTEX_OFF_PLAYER_RESEARCHED + idx]
                and payload[PTEX_OFF_PLAYER_AVAILABLE + idx]
                and not payload[PTEX_OFF_USES_DEFAULT + idx]):
            out.append(tech)
    return out


# ---------------------------------------------------------------------------
# UNIT SETTINGS (task 031)
# ---------------------------------------------------------------------------
# A Use Map Settings map may override, per unit type, its hit points, shield points,
# armor, BUILD TIME, mineral cost and gas cost. Task 031 wanted the build time: a suite
# that trains nine SCVs spends 153 of its 224 seconds waiting for them at 20 game seconds
# each, which measured out at 68% of that whole run. Set the build time to one second and
# that term goes away without changing a single thing the suite asserts on.
#
# THE SECTION THE ENGINE READS IS UNIx, NOT UNIS. The task said not to assume it, and
# there are four independent reasons, the last of which is the one that counts:
#
#  1. The Brood War template carries no UNIS AT ALL. (2)Fading Realm.scx holds UNIx (4168
#     bytes), PTEx, UPGx and TECx, and none of UNIS/PTEC/UPGS/TECS/UPGR.
#  2. StarCraft.exe holds three CHK section-application plans at .rdata 0x500560,
#     0x500588 and 0x5005B0, each a run of {section table, count} pairs. The third --
#     the Brood War one -- points at the table at 0x5004A8, whose fifteen entries are
#     STR MTXM THG2 MASK UNIx UPGx TECx PUNI PUPx PTEx UNIT UPRP MRGN TRIG COLR. There is
#     no UNIS entry in it, so on a Brood War map a UNIS section is never applied at all.
#     The other two plans list both, with UNIx AFTER UNIS, so it wins there as well.
#  3. That same table gives `PTEx -> 0x004CB7D0`, which is the exact applier address task
#     026 verified independently against the running game (research/command-card.md 6).
#     A table that is right about the one entry we already proved is a table worth
#     reading, and this is what makes 1 and 2 evidence rather than a plausible story.
#  4. AND IT WAS READ BACK OUT OF A RUNNING GAME, which is the only one of the four that
#     could have contradicted the others. tools/plugin/probe-unit-settings.ps1 builds ONE
#     map whose UNIx says a Marine has 25 hit points and whose (added) UNIS says 12, loads
#     it, and reads hp out of CUnit -- so the answer distinguishes UNIx from UNIS from
#     neither, instead of merely confirming what was expected. See that script's header
#     for the reading.
#
# THE LAYOUT, verified the same way the PTEx layout was: it reproduces, to the byte, the
# real stats of every unit anyone here can check by hand, out of a section this tool did
# not write. Marine 40hp / build 360 / 50 minerals; SCV 60 / 300 / 50; Command Center
# 1500 / 1800 / 400; Supply Depot 500 / 600 / 100; Barracks 1000 / 1200 / 150; Lurker
# 125 hp / 50 minerals / 100 gas. And the sizes: 228 + 912 + 456 + 228 + 456 + 456 + 456
# + 456 + 260 + 260 == 4168, which is exactly the section's size on disk.
#
# BUILD TIME IS IN GAME SECONDS x 15 -- 300 for the SCV's 20, 360 for the Marine's 24,
# 600 for the Supply Depot's 40, 1200 for the Barracks' 80, 1800 for the Command Center's
# 120. Five units agreeing on one divisor is what makes it a unit and not a coincidence,
# and the flags below take game seconds so nobody has to remember it.
#
# HIT POINTS ARE STORED x256, the same fixed point CUnit+0x08 uses, which is what makes
# the in-game read-back a direct comparison rather than a conversion.
UNIX_UNITS = 228
UNIX_WEAPONS = 130                 # UNIS, the vanilla section, has 100 here
UNIX_OFF_USE_DEFAULT = 0                                             # u8  [unit]
UNIX_OFF_HIT_POINTS = UNIX_UNITS                                     # u32 [unit], x256
UNIX_OFF_SHIELD_POINTS = UNIX_OFF_HIT_POINTS + 4 * UNIX_UNITS        # u16 [unit]
UNIX_OFF_ARMOR = UNIX_OFF_SHIELD_POINTS + 2 * UNIX_UNITS             # u8  [unit]
UNIX_OFF_BUILD_TIME = UNIX_OFF_ARMOR + UNIX_UNITS                    # u16 [unit], x15
UNIX_OFF_MINERAL_COST = UNIX_OFF_BUILD_TIME + 2 * UNIX_UNITS         # u16 [unit]
UNIX_OFF_GAS_COST = UNIX_OFF_MINERAL_COST + 2 * UNIX_UNITS           # u16 [unit]
UNIX_OFF_STRING_NUMBER = UNIX_OFF_GAS_COST + 2 * UNIX_UNITS          # u16 [unit]
UNIX_OFF_BASE_DAMAGE = UNIX_OFF_STRING_NUMBER + 2 * UNIX_UNITS       # u16 [weapon]
UNIX_OFF_UPGRADE_DAMAGE = UNIX_OFF_BASE_DAMAGE + 2 * UNIX_WEAPONS    # u16 [weapon]
UNIX_SIZE = UNIX_OFF_UPGRADE_DAMAGE + 2 * UNIX_WEAPONS               # 4168

BUILD_TIME_PER_GAME_SECOND = 15
HP_FIXED_POINT = 256

# The settable fields, and the WIDTH of each, because a u8 field silently truncating a
# caller's 500 is the kind of thing this tool is supposed to refuse rather than do.
# Base weapon damage is deliberately absent: it is indexed by WEAPON, not by unit, so a
# `--unit-...` flag would be lying about what it changes. Nothing here has needed it.
UNIT_SETTING_FIELDS = {
    #  name            offset                    struct  max
    "max-hp":        (UNIX_OFF_HIT_POINTS,    "<I", 0xFFFFFFFF // HP_FIXED_POINT),
    "shields":       (UNIX_OFF_SHIELD_POINTS, "<H", 0xFFFF),
    "armor":         (UNIX_OFF_ARMOR,         "<B", 0xFF),
    "build-time":    (UNIX_OFF_BUILD_TIME,    "<H", 0xFFFF // BUILD_TIME_PER_GAME_SECOND),
    "mineral-cost":  (UNIX_OFF_MINERAL_COST,  "<H", 0xFFFF),
    "gas-cost":      (UNIX_OFF_GAS_COST,      "<H", 0xFFFF),
}

# Fields whose stored value is not the value a caller types.
UNIT_SETTING_SCALE = {
    "max-hp": HP_FIXED_POINT,
    "build-time": BUILD_TIME_PER_GAME_SECOND,
}


def unit_setting_scale(field: str) -> int:
    return UNIT_SETTING_SCALE.get(field, 1)


def parse_unit_setting(spec: str) -> tuple[int, int]:
    """`scv=1` -> (7, 1). The unit half takes the same names as --unit-type."""
    if "=" not in spec:
        raise ValueError(
            f"Unit setting {spec!r} is not TYPE=VALUE (for example: scv=1)."
        )
    name, _, value = spec.partition("=")
    unit_id = resolve_unit_id(name.strip())
    if unit_id >= UNIX_UNITS:
        raise ValueError(
            f"Unit id {unit_id} is outside the {UNIX_UNITS} entries UNIx carries."
        )
    try:
        amount = int(value.strip())
    except ValueError:
        raise ValueError(f"Unit setting {spec!r}: {value!r} is not an integer.") from None
    return unit_id, amount


def set_unit_settings(payload: bytes, settings: dict[str, list[tuple[int, int]]]) -> bytes:
    """UNIx with the given per-unit overrides applied.

    `usesDefault` is CLEARED for every unit touched. That byte is the whole mechanism:
    leave it at 1 and the engine reads units.dat and the override arrays are dead --
    exactly the shape of the PTEx `playerUsesDefault` bug above, which is why it is done
    here, once, next to the write, rather than left to a caller to remember.

    Every unit's OTHER fields are left holding whatever the template had, which for a
    StarEdit-written map is that unit's real stats; clearing usesDefault therefore changes
    nothing except the field asked for. That is checked, not assumed: read_unit_settings
    reports every field of every touched unit and the validator prints them.
    """
    if len(payload) != UNIX_SIZE:
        raise ValueError(
            f"UNIx is {len(payload)} bytes, expected {UNIX_SIZE}; this tool only "
            f"understands the Brood War {UNIX_UNITS}-unit, {UNIX_WEAPONS}-weapon layout."
        )
    buf = bytearray(payload)
    for field, pairs in settings.items():
        if field not in UNIT_SETTING_FIELDS:
            raise ValueError(f"Unknown unit setting {field!r}")
        offset, fmt, limit = UNIT_SETTING_FIELDS[field]
        scale = unit_setting_scale(field)
        width = struct.calcsize(fmt)
        for unit_id, amount in pairs:
            if amount < 0:
                raise ValueError(f"--unit-{field} {unit_id}={amount}: must not be negative")
            # A build time of ZERO is refused rather than written. Nothing here knows what
            # the engine's production tick does when the remaining time starts at 0 -- it
            # may complete instantly, it may divide by it to draw the progress bar -- and
            # a fixture whose behaviour nobody has looked at is worse than a slow one. One
            # game second is ~0.7 real seconds, which is as fast as any suite has needed.
            if field == "build-time" and amount == 0:
                raise ValueError(
                    f"--unit-build-time {unit_id}=0: refusing. Nothing in this repo has "
                    f"observed what the engine does with a zero build time, and 1 game "
                    f"second (~0.7 real seconds) is already as fast as a fixture needs. "
                    f"Pass 1."
                )
            if amount > limit:
                raise ValueError(
                    f"--unit-{field} {unit_id}={amount}: the field holds at most {limit}."
                )
            struct.pack_into(fmt, buf, offset + width * unit_id, amount * scale)
            buf[UNIX_OFF_USE_DEFAULT + unit_id] = 0
    return bytes(buf)


def read_unit_settings(payload: bytes, unit_ids: list[int]) -> dict[int, dict]:
    """What UNIx says about these units, in the caller's own units rather than raw.

    The read is a SEPARATE walk of the section, not a replay of what was written, so a
    validator using it is checking the bytes rather than its own intent. It still cannot
    prove the ENGINE agrees -- only a running game can, which is what
    tools/plugin/probe-unit-settings.ps1 is for (AGENTS.md, task 026).
    """
    if len(payload) != UNIX_SIZE:
        raise ValueError(f"UNIx is {len(payload)} bytes, expected {UNIX_SIZE}")
    out = {}
    for unit_id in unit_ids:
        entry = {"uses-default": payload[UNIX_OFF_USE_DEFAULT + unit_id]}
        for field, (offset, fmt, _limit) in UNIT_SETTING_FIELDS.items():
            width = struct.calcsize(fmt)
            (raw,) = struct.unpack_from(fmt, payload, offset + width * unit_id)
            entry[field] = raw // unit_setting_scale(field)
        out[unit_id] = entry
    return out


DEFAULT_TEMPLATE = r"C:\sc-work\1161-base\Maps\BroodWar\Ladder\(2)Fading Realm.scx"
DEFAULT_OUTPUT = r"C:\sc-work\1161-base\Maps\test-many-units.scx"
DEFAULT_UNIT_COUNT = 36
# One tile between units, and the block CENTRED on the start location. Both matter:
# the camera opens centred on the start location and shows about 20x12 tiles, so a block
# that grows right-and-down from that point puts its far half off screen and behind the
# HUD, where no drag box can reach it. Bigger units need more room than one tile or the
# game drops the ones that cannot be placed -- pass --grid-spacing for those.
GRID_SPACING_PX = 32

# ---------------------------------------------------------------------------
# The COMBAT variant (task 019)
# ---------------------------------------------------------------------------
# Everything above produces a fixture with nothing hostile in it, which is exactly
# what tasks 015-017 needed and exactly why none of them could prove what happens
# when a selected unit DIES. --enemy-count turns on a second, COMPUTER-owned block
# of units, so a test can walk the player's group into it and get one killed.
#
# No AI script and no trigger is involved: a preplaced unit on a computer slot sits
# on its default order and shoots what walks into its range. That is option (c) of
# the three this task listed, and the only one that needs no new CHK section at all.
# What makes it a claim rather than a guess is the in-game run --
# tools/plugin/test-combat-death.ps1 boxes the player's units, walks them east and
# asserts FROM INSIDE THE PROCESS that they start dying while the mission carries on.
# See tools/README-test-map.md "Combat variant" for the evidence.
#
# The block goes DUE EAST of the player's start location by default: far enough that
# nothing is in anyone's acquisition range when the mission starts (the map must
# still idle until the test decides otherwise), and close enough that ONE right-click
# at the right-hand edge of a 640x480 screen orders the player's units into it. The
# camera opens centred on the start location and never moves on its own, so a
# destination further out than about +310px cannot be clicked at all without
# scrolling the view first.
ENEMY_OFFSET_X_PX = 448          # 14 tiles east of the start location
ENEMY_OFFSET_Y_PX = 0
ENEMY_SPACING_PX = 48
ENEMY_TYPE = "hydralisk"
# The two blocks must not start out on top of each other, or the "the map still
# idles" property is gone before the test begins. This is pure geometry -- the
# number that actually matters (nothing engages until the test says so) is asserted
# IN GAME, by boxing all N units alive well after the mission started.
MIN_ENEMY_GAP_PX = 256           # 8 tiles between the two blocks' bounding boxes
ENEMY_OWNER_COMPUTER = "computer"
ENEMY_OWNER_PLAYER = "player"
ENEMY_OWNERS = (ENEMY_OWNER_COMPUTER, ENEMY_OWNER_PLAYER)


def block_bounds(records: list[UnitRecord]) -> tuple[int, int, int, int]:
    """(x0, y0, x1, y1) of a list of placed units, in map pixels."""
    return (min(r.x for r in records), min(r.y for r in records),
            max(r.x for r in records), max(r.y for r in records))


def block_gap_px(a: list[UnitRecord], b: list[UnitRecord]) -> int:
    """A LOWER BOUND on the distance between two placed blocks, in map pixels.

    The larger of the two per-axis gaps between the blocks' bounding boxes. Any
    two units, one from each block, are at least this far apart, so a caller that
    demands "at least N pixels of separation" gets a number it can trust; negative
    means the bounding boxes overlap on both axes.
    """
    ax0, ay0, ax1, ay1 = block_bounds(a)
    bx0, by0, bx1, by1 = block_bounds(b)
    gx = max(bx0 - ax1, ax0 - bx1)
    gy = max(by0 - ay1, ay0 - by1)
    return max(gx, gy)


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
    spacing: int = GRID_SPACING_PX, hp_percent: int = 100,
    damaged_count: int = 0, damaged_hp_percent: int = 0,
    energy_percent: int = 100, damaged_energy_percent: int | None = None,
) -> list[UnitRecord]:
    """The block, optionally with a PRE-DAMAGED TAIL.

    Task 022 added `damaged_count`: the LAST that-many units of the block are written
    at `damaged_hp_percent` instead of `hp_percent`, same type, same grid, same owner.

    Why the same block rather than a second one: an ability with a per-unit cost has a
    per-unit AFFORDABILITY GATE (Stim's is `CMP dword [unit+8],0xa00 / JLE skip`,
    research/ability-semantics.md 2), and the only way to see whether the ENGINE or the
    fan-out decides who is skipped is to have payers and non-payers in ONE selection,
    reached by ONE keypress. Two separate runs cannot distinguish "the engine skipped
    the poor ones" from "the plugin sent a different set that time".

    The tail is the LAST units on purpose: the fan-out emits the engine's visible twelve
    LAST and the overflow chunks first (tools/plugin/README.md), and build order here is
    row-major from the top-left, so a tail-damaged block puts the damaged units in the
    part of the box the engine does NOT hold. If the split ever came out along the
    visible/overflow line instead of along the HP line, that would be ours, and this
    layout is what makes the two hypotheses produce different numbers.
    """
    if damaged_count < 0 or damaged_count > count:
        raise ValueError(
            f"damaged-count must be 0..{count} (the block size), got {damaged_count}"
        )
    if damaged_count and not MIN_HP_PERCENT <= damaged_hp_percent <= MAX_HP_PERCENT:
        raise ValueError(
            f"damaged-hp must be {MIN_HP_PERCENT}-{MAX_HP_PERCENT}, got "
            f"{damaged_hp_percent}"
        )
    # The energy half of the same idea: an ability that costs ENERGY has a per-unit
    # affordability gate too (0x00491B30 compares `cost*0x100 <= CUnit+0xA2` before it
    # deducts -- research/ability-semantics.md 3), so the same tail makes it testable.
    if damaged_energy_percent is None:
        damaged_energy_percent = energy_percent
    for name, value in (("energy", energy_percent),
                        ("damaged-energy", damaged_energy_percent)):
        if not MIN_HP_PERCENT <= value <= MAX_HP_PERCENT:
            raise ValueError(
                f"{name} must be {MIN_HP_PERCENT}-{MAX_HP_PERCENT} (a PERCENTAGE of the "
                f"unit type's maximum), got {value}"
            )
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
                hp=damaged_hp_percent if i >= count - damaged_count else hp_percent,
                shield=100,
                energy=(damaged_energy_percent if i >= count - damaged_count
                        else energy_percent),
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
    about it. One COMPUTER slot satisfies that check; by default it is given no units
    anywhere on the map, so there is still nothing hostile in the game. Under Use Map
    Settings the check does not apply, but the slot is harmless there and keeps one map
    usable under both game types.

    With --enemy-count (task 019) this same slot is the one that OWNS the enemy force:
    it already exists, it already carries an explicit race, and putting the enemy on a
    second computer slot would mean two opponents where the validator wants exactly one.
    """
    return 1 if player != 1 else 0


def generate_map(
    template: Path, output: Path, unit_count: int, unit_type: str, player: int,
    spacing: int = GRID_SPACING_PX, keep_ownr: bool = False,
    clear_player_units: bool = False, keep_triggers: bool = False,
    race: int = SIDE_TERRAN,
    enemy_count: int = 0, enemy_type: str = ENEMY_TYPE,
    enemy_offset: tuple[int, int] = (ENEMY_OFFSET_X_PX, ENEMY_OFFSET_Y_PX),
    enemy_spacing: int = ENEMY_SPACING_PX, enemy_race: int | None = None,
    enemy_owner: str = ENEMY_OWNER_COMPUTER, min_enemy_gap: int = MIN_ENEMY_GAP_PX,
    unit_hp_percent: int = MAX_HP_PERCENT,
    damaged_count: int = 0, damaged_hp_percent: int = 0,
    tech_researched: list[int] | None = None,
    damaged_energy_percent: int | None = None,
    starting_minerals: int | None = None,
    starting_gas: int | None = None,
    unit_settings: dict[str, list[tuple[int, int]]] | None = None,
) -> None:
    unit_id = resolve_unit_id(unit_type)
    if not 0 <= player <= 7:
        raise ValueError(f"player must be 0-7 (Player 1..Player 8), got {player}")
    if unit_count < 1:
        raise ValueError(f"unit-count must be >= 1, got {unit_count}")
    if not MIN_HP_PERCENT <= unit_hp_percent <= MAX_HP_PERCENT:
        raise ValueError(
            f"unit-hp must be {MIN_HP_PERCENT}-{MAX_HP_PERCENT} (it is a PERCENTAGE of "
            f"the unit type's maximum hit points, not an absolute value), got "
            f"{unit_hp_percent}"
        )
    if enemy_count < 0:
        raise ValueError(f"enemy-count must be >= 0, got {enemy_count}")
    if enemy_owner not in ENEMY_OWNERS:
        raise ValueError(f"enemy-owner must be one of {ENEMY_OWNERS}, got {enemy_owner!r}")
    if enemy_count and keep_ownr and enemy_owner == ENEMY_OWNER_COMPUTER:
        # --keep-ownr leaves the template's slots as they are, so this tool does not
        # know which of them is a computer, whether it is active, or what race it is.
        # Placing a hostile force on a slot it did not configure would produce a map
        # whose behaviour this tool cannot describe.
        raise ValueError(
            "--enemy-count with --keep-ownr is refused: with the template's own player "
            "slots left alone there is no slot this tool has made into a known, active, "
            "fixed-race computer opponent to own the enemy force. Drop --keep-ownr, or "
            "pass --enemy-owner player for the placement-probe variant."
        )
    enemy_id = resolve_unit_id(enemy_type) if enemy_count else 0
    if (enemy_count and enemy_owner == ENEMY_OWNER_PLAYER and enemy_id == unit_id):
        # Both blocks would land on the same slot with the same type, and neither
        # block's count could be read back on its own -- in the file or in game.
        raise ValueError(
            f"--enemy-owner player puts both blocks on player {player}, so --unit-type "
            f"and --enemy-type must differ (both resolve to unit id {unit_id})"
        )
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
        unit_count, unit_id, player, start.x, start.y, next_instance, spacing,
        unit_hp_percent, damaged_count, damaged_hp_percent,
        damaged_energy_percent=damaged_energy_percent,
    )

    # THE ENEMY FORCE (task 019). Placed relative to the SAME start location the
    # player's block is centred on, so the two are a documented, fixed distance apart
    # whatever template supplied the coordinates.
    enemy_records: list[UnitRecord] = []
    if enemy_count:
        enemy_slot = player if enemy_owner == ENEMY_OWNER_PLAYER else pick_opponent_slot(player)
        ex = start.x + enemy_offset[0]
        ey = start.y + enemy_offset[1]
        dim_idx = require_section(sections, "DIM", template)
        map_w, map_h = struct.unpack_from("<HH", sections[dim_idx].payload, 0)
        enemy_records = build_new_unit_records(
            enemy_count, enemy_id, enemy_slot, ex, ey,
            next_instance + unit_count, enemy_spacing,
        )
        # Off the map is not "somewhere awkward", it is a record the engine cannot
        # place at all -- and a silently dropped enemy force is a fixture that looks
        # like a combat map and behaves like the old idle one.
        bx0, by0, bx1, by1 = block_bounds(enemy_records)
        if bx0 < 0 or by0 < 0 or bx1 >= map_w * 32 or by1 >= map_h * 32:
            raise ValueError(
                f"the enemy block would span ({bx0},{by0})-({bx1},{by1}) map pixels, "
                f"outside this {map_w}x{map_h}-tile map (0-{map_w * 32 - 1}, "
                f"0-{map_h * 32 - 1}). Move it with --enemy-offset-x/--enemy-offset-y."
            )
        gap = block_gap_px(new_records, enemy_records)
        if gap < min_enemy_gap:
            raise ValueError(
                f"the enemy block is only {gap}px ({gap / 32:.1f} tiles) from the "
                f"player's block, under the {min_enemy_gap}px minimum. A fixture whose "
                f"two sides can see each other on the first frame is not idle, and the "
                f"test that boxes the player's units has nothing left to box. Move it "
                f"with --enemy-offset-x/--enemy-offset-y."
            )

    sections = replace_section(
        sections, "UNIT",
        b"".join(pack_unit_record(r) for r in kept_records + new_records + enemy_records),
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
        #
        # In the COMBAT variant it gets the race the ENEMY units belong to instead of the
        # player's own. Nothing observed says a Zerg slot cannot own Terran units under
        # Use Map Settings, but a slot whose race matches what it owns is the arrangement
        # every stock map uses, and it costs nothing to match it.
        sides[pick_opponent_slot(player)] = (
            enemy_race if (enemy_count and enemy_owner == ENEMY_OWNER_COMPUTER
                           and enemy_race is not None)
            else race
        )
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

        # AND, FOR A COMBAT MAP, THE TWO SLOTS MUST NOT BE ALLIES.
        #
        # FORC's first eight bytes are the per-slot force assignment; bit 0x02 of a
        # force's flag byte is "allied" (staredit.net CHK spec, same source as the
        # 0x01 above). Two slots in the SAME force with that bit set start the game
        # allied, and allied units do not shoot each other -- the map would load, the
        # enemy would sit there politely, and the test would time out waiting for a
        # death with nothing to point at. Refused rather than rewritten: clearing
        # another map's alliance settings is an edit nobody asked for, and every
        # template this tool is documented against (the ladder map, whose Force 1
        # flag byte is 0x01 and becomes 0x00 above) already passes.
        if enemy_count and enemy_owner == ENEMY_OWNER_COMPUTER:
            opponent = pick_opponent_slot(player)
            f_player, f_enemy = forc[player], forc[opponent]
            if f_player == f_enemy and (forc[16 + f_player] & FORC_ALLIED):
                raise ValueError(
                    f"Template {template}: player {player} and the computer opponent "
                    f"{opponent} are both in force {f_player + 1}, whose FORC flag byte "
                    f"0x{forc[16 + f_player]:02X} has the 'allied' bit (0x02) set. "
                    f"Allied units never fight, so an enemy force placed here would "
                    f"never attack. Refusing rather than rewriting the template's own "
                    f"alliance settings."
                )
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

        # STARTING RESOURCES (task 025). The template's own triggers have just been
        # dropped, so the ONE trigger written back here is the only trigger the fixture
        # carries -- see the STARTING RESOURCES block at the top of this file for why a
        # UMS fixture needs it at all and why it cannot end the game.
        if starting_minerals is not None or starting_gas is not None:
            sections = replace_section(
                sections, "TRIG",
                build_starting_resources_trig(player, starting_minerals, starting_gas),
                template,
            )
    elif starting_minerals is not None or starting_gas is not None:
        raise ValueError(
            "--starting-minerals/--starting-gas cannot be combined with --keep-triggers: "
            "the resource trigger is written into a TRIG section this tool has just "
            "emptied, and appending it to a stock map's triggers would keep that map's "
            "victory/defeat triggers as well."
        )

    # TECH STATE (task 022). Without it a fixture cannot test any ability with a
    # per-unit COST -- see the PTEx block at the top of this file.
    if tech_researched:
        ptex_idx = find_section(sections, "PTEx")
        if ptex_idx < 0:
            raise ValueError(
                f"Template {template} has no PTEx section, so this tool cannot give a "
                f"player a researched tech. Use a Brood War template."
            )
        sections = replace_section(
            sections, "PTEx",
            set_techs_researched(sections[ptex_idx].payload, tech_researched, player),
            template,
        )

    # UNIT SETTINGS (task 031). Opt-in and additive: with no --unit-* flag this block does
    # not run, no section is touched, and the file this tool writes is byte-for-byte what
    # it wrote before. That property is not decoration -- three other tasks were mid-run
    # against this generator when it was added.
    if unit_settings:
        unix_idx = find_section(sections, "UNIx")
        if unix_idx < 0:
            # NOT quietly falling back to UNIS. The Brood War section-application table at
            # 0x5004A8 has no UNIS entry, so on a map the engine treats as Brood War a
            # UNIS override is never applied -- a fallback here would write bytes that
            # look right in the file and do nothing in the game, which is precisely the
            # class of failure the PTEx bug was.
            raise ValueError(
                f"Template {template} has no UNIx section, so this tool cannot override "
                f"unit settings on it. Use a Brood War template: the engine's Brood War "
                f"CHK section table (StarCraft.exe 0x5004A8) lists UNIx and no UNIS, so "
                f"writing UNIS instead would produce a map whose settings the engine "
                f"never reads."
            )
        sections = replace_section(
            sections, "UNIx",
            set_unit_settings(sections[unix_idx].payload, unit_settings),
            template,
        )

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
    enemy_count: int = 0, enemy_type: str = ENEMY_TYPE,
    enemy_owner: str = ENEMY_OWNER_COMPUTER, min_enemy_gap: int = MIN_ENEMY_GAP_PX,
    unit_hp_percent: int = MAX_HP_PERCENT,
    damaged_count: int = 0, damaged_hp_percent: int = 0,
    tech_researched: list[int] | None = None,
    damaged_energy_percent: int | None = None,
    starting_minerals: int | None = None,
    starting_gas: int | None = None,
    unit_settings: dict[str, list[tuple[int, int]]] | None = None,
) -> None:
    unit_id = resolve_unit_id(unit_type)
    enemy_id = resolve_unit_id(enemy_type) if enemy_count else 0
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

    # The hit-point percentage is what makes the combat fixture's victims die in
    # seconds rather than minutes, so a run that silently kept the default would look
    # like a slow map rather than a broken flag.
    #
    # With a pre-damaged tail (task 022) the check is on the COUNT AT EACH VALUE, not
    # on the set of values: the whole point of that fixture is that some units can
    # afford an ability's cost and some cannot, and "10 healthy + 26 damaged" would
    # satisfy a set-based check while testing something entirely different from
    # "24 healthy + 12 damaged".
    healthy_wanted = unit_count - damaged_count
    got = collections.Counter(r.hp for r in matching)
    want = collections.Counter()
    if healthy_wanted:
        want[unit_hp_percent] += healthy_wanted
    if damaged_count:
        want[damaged_hp_percent] += damaged_count
    if got != want:
        raise AssertionError(
            f"{path}: placed units carry hit-point percentages "
            f"{dict(sorted(got.items()))}, expected {dict(sorted(want.items()))}"
        )

    if damaged_energy_percent is not None and damaged_count:
        got_e = collections.Counter(r.energy for r in matching)
        want_e = collections.Counter()
        if healthy_wanted:
            want_e[MAX_HP_PERCENT] += healthy_wanted
        want_e[damaged_energy_percent] += damaged_count
        if got_e != want_e:
            raise AssertionError(
                f"{path}: placed units carry energy percentages "
                f"{dict(sorted(got_e.items()))}, expected {dict(sorted(want_e.items()))}"
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
    trig_payload = sections[trig_idx].payload if trig_idx >= 0 else b""
    trig_len = len(trig_payload)
    wants_resources = starting_minerals is not None or starting_gas is not None
    allowed_trig = TRIG_BYTES if wants_resources else 0
    if not keep_triggers and trig_len != allowed_trig:
        raise AssertionError(
            f"{path}: TRIG holds {trig_len} bytes ({trig_len // TRIG_BYTES} trigger(s)), "
            f"expected {allowed_trig}; a generated fixture must carry none, or the "
            "map's own victory/defeat triggers end the game within seconds of loading"
        )
    if not keep_triggers and wants_resources:
        # The single trigger is checked from its BYTES, both ways round: it grants what
        # was asked for, AND its only action is Set Resources -- so it cannot end the
        # game. Reading back only the grants would leave the second half unproved.
        ids = trigger_action_ids(trig_payload)
        if ids != {TRIG_ACTION_SET_RESOURCES}:
            raise AssertionError(
                f"{path}: the resource trigger carries action id(s) {sorted(ids)}; only "
                f"{TRIG_ACTION_SET_RESOURCES} (Set Resources) is allowed in a fixture"
            )
        granted = read_starting_resources(trig_payload)
        want = []
        if starting_minerals is not None:
            want.append((player, TRIG_RESOURCE_ORE, starting_minerals))
        if starting_gas is not None:
            want.append((player, TRIG_RESOURCE_GAS, starting_gas))
        if sorted(granted) != sorted(want):
            raise AssertionError(
                f"{path}: the resource trigger grants {sorted(granted)}, expected "
                f"{sorted(want)}"
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
        want_opponent_units = enemy_count if enemy_owner == ENEMY_OWNER_COMPUTER else 0
        if len(opponent_units) != want_opponent_units:
            raise AssertionError(
                f"{path}: the computer opponent owns {len(opponent_units)} unit(s), "
                f"expected {want_opponent_units}"
                + ("" if want_opponent_units else
                   " -- with no --enemy-count the map must be hostility-free")
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

    # --- the enemy force (task 019) -------------------------------------------
    # Everything asserted here is STRUCTURE, read back out of the finished file: the
    # right number of the right unit type on the right slot, far enough from the
    # player's block that neither side is in the other's lap on the first frame, and
    # not allied with the player. That the engine then CREATES those units and that
    # they actually shoot is a behavioural claim, and is asserted in game by
    # tools/plugin/test-combat-death.ps1 -- not here.
    enemy_records: list[UnitRecord] = []
    if enemy_count:
        enemy_slot = player if enemy_owner == ENEMY_OWNER_PLAYER else pick_opponent_slot(player)
        if enemy_owner == ENEMY_OWNER_PLAYER and enemy_id == unit_id:
            raise AssertionError(
                f"{path}: the placement-probe variant (--enemy-owner player) puts both "
                f"blocks on player {player}, so they must be different unit types or "
                f"neither block's count can be read back on its own (both are type "
                f"{unit_id})"
            )
        enemy_records = [
            r for r in records if r.unit_id == enemy_id and r.player == enemy_slot
        ]
        if len(enemy_records) != enemy_count:
            raise AssertionError(
                f"{path}: expected {enemy_count} enemy unit(s) of type {enemy_id} owned "
                f"by slot {enemy_slot}, found {len(enemy_records)}"
            )
        gap = block_gap_px(matching, enemy_records)
        if gap < min_enemy_gap:
            raise AssertionError(
                f"{path}: the enemy block is {gap}px ({gap / 32:.1f} tiles) from the "
                f"player's block, under the {min_enemy_gap}px minimum -- the two sides "
                f"would be engaged before the test has boxed anything"
            )
        # Allies never shoot each other, and a combat fixture whose enemy is an ally is
        # a fixture that times out. Same FORC bit the generator refuses on.
        if enemy_owner == ENEMY_OWNER_COMPUTER:
            forc_idx = find_section(sections, "FORC")
            if forc_idx < 0 or len(sections[forc_idx].payload) < 20:
                raise AssertionError(f"{path}: no usable FORC section")
            forc = sections[forc_idx].payload
            if forc[player] == forc[enemy_slot] and (forc[16 + forc[player]] & FORC_ALLIED):
                raise AssertionError(
                    f"{path}: player {player} and enemy slot {enemy_slot} are both in "
                    f"force {forc[player] + 1}, which carries the FORC 'allied' bit "
                    f"(0x02). Allied units do not fight."
                )

    # THE TECH STATE IS THE FIXTURE, NOT A DETAIL (task 022). Every ability with a
    # per-unit cost needs research, so a map that quietly lost this byte produces a
    # command card with no ability button on it -- a run that fails on "the key emitted
    # nothing", minutes later and several steps away from the cause.
    if tech_researched:
        ptex_idx = find_section(sections, "PTEx")
        if ptex_idx < 0:
            raise AssertionError(f"{path}: no PTEx section, so no tech state to check")
        have = read_techs_researched(sections[ptex_idx].payload, player)
        missing = sorted(set(tech_researched) - set(have))
        if missing:
            raise AssertionError(
                f"{path}: PTEx does not mark tech id(s) {missing} as available AND "
                f"already-researched (with playerUsesDefault cleared) for player "
                f"{player}; it lists {have}"
            )

    # THE UNIT SETTINGS ARE READ BACK OUT OF THE FILE (task 031), never replayed from
    # what the caller asked for. That distinction is the whole of the PTEx lesson: a tool
    # that verifies its own write with its own intent verifies nothing. It is still only
    # the FILE's word -- what the ENGINE does with these bytes is proved in a running game
    # by tools/plugin/probe-unit-settings.ps1, and nowhere here.
    unix_read: dict[int, dict] = {}
    if unit_settings:
        unix_idx = find_section(sections, "UNIx")
        if unix_idx < 0:
            raise AssertionError(f"{path}: no UNIx section, so no unit settings to check")
        touched = sorted({u for pairs in unit_settings.values() for u, _ in pairs})
        unix_read = read_unit_settings(sections[unix_idx].payload, touched)
        for field, pairs in unit_settings.items():
            for unit_id_, want in pairs:
                got = unix_read[unit_id_][field]
                if got != want:
                    raise AssertionError(
                        f"{path}: UNIx says unit {unit_id_} has {field}={got}, asked for "
                        f"{want}"
                    )
                # usesDefault is the byte that decides whether ANY of it is read. A map
                # with the right numbers and this byte still set is a map on which every
                # override is dead, and it would otherwise validate perfectly.
                if unix_read[unit_id_]["uses-default"] != 0:
                    raise AssertionError(
                        f"{path}: UNIx still has usesDefault set for unit {unit_id_}, so "
                        f"the engine would read units.dat and ignore every override on it"
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
        if tech_researched:
            expected |= {"PTEx"}
        if unit_settings:
            expected |= {"UNIx"}
        unexpected = [c for c in changed if c not in expected]
        if unexpected:
            raise AssertionError(
                f"{path}: the output differs from its template in section(s) "
                f"{unexpected}, which this tool never asked to change. Every other "
                f"section must come across byte-for-byte."
            )

    print(f"OK: {path}")
    print(f"  {len(matching)} unit(s) of type {unit_id} owned by player {player}, "
          f"at {unit_hp_percent}% hit points")
    if damaged_count:
        print(f"  of those, the LAST {damaged_count} are pre-damaged to "
              f"{damaged_hp_percent}% -- so one selection holds units that can afford a "
              f"per-unit ability cost and units that cannot")
        if damaged_energy_percent is not None:
            print(f"  and that same tail starts at {damaged_energy_percent}% energy, "
                  f"for the energy-costed half of the same question")
    if unix_read:
        unit_names = {v: k for k, v in UNIT_TYPE_IDS.items()}
        for unit_id_, entry in sorted(unix_read.items()):
            asked = {f for f, pairs in unit_settings.items() if any(u == unit_id_ for u, _ in pairs)}
            shown = " ".join(
                ("*" if f in asked else "") + f"{f}={entry[f]}"
                for f in UNIT_SETTING_FIELDS
            )
            print(f"  UNIx: {unit_names.get(unit_id_, unit_id_)} ({unit_id_}) "
                  f"usesDefault={entry['uses-default']} {shown}")
        print("        (* = overridden by this run; build-time is in GAME seconds, and "
              "every other field is left as the template had it)")
    if tech_researched:
        names = {v: k for k, v in TECH_IDS.items()}
        print("  PTEx: player {} has researched {}".format(
            player,
            " ".join(f"{t}({names.get(t, '?')})" for t in sorted(tech_researched))))
    print(f"  start location for player {player} at ({start.x}, {start.y})")
    side_idx = find_section(sections, "SIDE")
    side = list(sections[side_idx].payload)[player] if side_idx >= 0 else None
    if keep_ownr:
        print(f"  OWNR left as the template had it; player {player} = "
              f"{OWNR_NAMES.get(actual, actual)}")
    else:
        opp = pick_opponent_slot(player)
        opp_units = enemy_count if enemy_owner == ENEMY_OWNER_COMPUTER else 0
        print(f"  OWNR[{player}] = {OWNR_NAMES.get(actual, actual)}; one computer slot "
              f"at {opp} owning {opp_units} unit(s)"
              + ("" if opp_units else " -- nothing hostile in the game"))
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
    if enemy_count:
        ex0, ey0, ex1, ey1 = block_bounds(enemy_records)
        px0, py0, px1, py1 = block_bounds(matching)
        gap = block_gap_px(matching, enemy_records)
        slot = player if enemy_owner == ENEMY_OWNER_PLAYER else pick_opponent_slot(player)
        print(f"  ENEMY {len(enemy_records)} unit(s) of type {enemy_id} owned by slot "
              f"{slot} ({enemy_owner}), spanning ({ex0},{ey0})-({ex1},{ey1}) px")
        print(f"        the player's block spans ({px0},{py0})-({px1},{py1}) px; the two "
              f"are at least {gap}px ({gap / 32:.1f} tiles) apart")
        print(f"        offset from the start location: "
              f"({(ex0 + ex1) // 2 - start.x:+d}, {(ey0 + ey1) // 2 - start.y:+d}) px")
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
    # --- the combat variant (task 019) ---------------------------------------
    parser.add_argument(
        "--enemy-count", type=int, default=0,
        help="Place this many COMPUTER-owned units near the player's block, so the "
             "fixture can kill the player's units on demand. 0 (the default) keeps the "
             "hostility-free map tasks 015-017 use.",
    )
    parser.add_argument(
        "--enemy-type", type=str, default=ENEMY_TYPE,
        help=f"Unit type for the enemy force (default {ENEMY_TYPE}): a name from the "
             f"same table as --unit-type, or a raw units.dat integer id.",
    )
    parser.add_argument(
        "--enemy-offset-x", type=int, default=ENEMY_OFFSET_X_PX,
        help=f"Map pixels EAST of the player's start location for the enemy block's "
             f"centre (default {ENEMY_OFFSET_X_PX} = {ENEMY_OFFSET_X_PX // 32} tiles).",
    )
    parser.add_argument(
        "--enemy-offset-y", type=int, default=ENEMY_OFFSET_Y_PX,
        help=f"Map pixels SOUTH of the player's start location for the enemy block's "
             f"centre (default {ENEMY_OFFSET_Y_PX}).",
    )
    parser.add_argument(
        "--enemy-spacing", type=int, default=ENEMY_SPACING_PX,
        help=f"Pixels between enemy units (default {ENEMY_SPACING_PX}).",
    )
    parser.add_argument(
        "--enemy-race", type=str, default=None, choices=sorted(RACE_IDS),
        help="Race written into SIDE for the computer slot in a combat map. Defaults to "
             "the race the enemy unit type belongs to.",
    )
    parser.add_argument(
        "--enemy-owner", type=str, default=ENEMY_OWNER_COMPUTER, choices=list(ENEMY_OWNERS),
        help="Who owns the enemy block. 'computer' (default) is the combat fixture. "
             "'player' is the PLACEMENT PROBE: the same unit types at the same "
             "coordinates, owned by the human, so a test can box them and count them "
             "in-process -- which is how the combat map's enemy block is proved to be on "
             "ground the engine will actually place units on.",
    )
    parser.add_argument(
        "--min-enemy-gap", type=int, default=MIN_ENEMY_GAP_PX,
        help=f"Refuse an enemy block closer than this many pixels to the player's block "
             f"(default {MIN_ENEMY_GAP_PX} = {MIN_ENEMY_GAP_PX // 32} tiles).",
    )
    parser.add_argument(
        "--unit-hp", type=int, default=MAX_HP_PERCENT,
        help=f"Hit points for the placed units, as a PERCENTAGE of the unit type's "
             f"maximum ({MIN_HP_PERCENT}-{MAX_HP_PERCENT}, default {MAX_HP_PERCENT}). "
             f"Lower is how the combat fixture makes its victims die in seconds rather "
             f"than minutes without changing anything else about them.",
    )
    parser.add_argument(
        "--damaged-count", type=int, default=0,
        help="Pre-damage the LAST this-many units of the player's block (same type, "
             "same grid, same owner) to --damaged-hp instead of --unit-hp. This is the "
             "fixture for an ability with a PER-UNIT COST: one selection then holds "
             "units that can afford it and units that cannot, so one keypress shows "
             "who the ENGINE skips.",
    )
    parser.add_argument(
        "--damaged-hp", type=int, default=0,
        help=f"Hit points for the --damaged-count tail, as a PERCENTAGE of the unit "
             f"type's maximum ({MIN_HP_PERCENT}-{MAX_HP_PERCENT}). Required whenever "
             f"--damaged-count is non-zero.",
    )
    parser.add_argument(
        "--damaged-energy", type=int, default=None,
        help=f"Energy for the --damaged-count tail, as a PERCENTAGE of the unit type's "
             f"maximum ({MIN_HP_PERCENT}-{MAX_HP_PERCENT}). The energy counterpart of "
             f"--damaged-hp: an ability that costs energy has a per-unit affordability "
             f"gate too, and this is what puts units on both sides of it in ONE "
             f"selection. Omitted means the tail keeps full energy.",
    )
    parser.add_argument(
        "--tech-researched", type=str, action="append", default=None,
        metavar="TECH",
        help="Mark a tech as available AND already-researched for --player, by writing "
             "PTEx. Repeatable. Names: " + ", ".join(sorted(TECH_IDS)) + "; or a raw "
             "techdata.dat id. Without this, no unit on a generated map has any ability "
             "that needs research -- which is every ability with a per-unit cost.",
    )
    parser.add_argument(
        "--starting-minerals", type=int, default=None,
        help="Give --player this many minerals at game start, by writing ONE "
             "`Always -> Set Resources` trigger into the (otherwise emptied) TRIG "
             "section. A CHK has no starting-resources field and Use Map Settings hands "
             "out none, so without this a fixture starts on the melee default and can "
             "afford almost nothing. Incompatible with --keep-triggers.",
    )
    parser.add_argument(
        "--starting-gas", type=int, default=None,
        help="The vespene counterpart of --starting-minerals; same single trigger.",
    )
    # --- unit settings, the map's own UNIx override (task 031) ---------------
    # One flag per field rather than one --unit-setting FIELD:TYPE=VALUE, because the
    # fields are NOT interchangeable in the way that matters: build time is setup and is
    # safe almost everywhere, while hit points are frequently the thing a suite measures.
    # Separate flags let each carry its own warning, and make a risky one greppable.
    parser.add_argument(
        "--unit-build-time", type=str, action="append", default=None, metavar="TYPE=SECONDS",
        help="Override a unit type's BUILD TIME, in GAME seconds, for this map only "
             "(TYPE=SECONDS, repeatable; e.g. scv=1, default 20). This is the fixture "
             "speed-up: it is SETUP, not measurement, so it is safe in every suite that "
             "waits for something to be built. Written to UNIx, which is the section the "
             "Brood War engine reads. 0 is refused -- see set_unit_settings.",
    )
    parser.add_argument(
        "--unit-max-hp", type=str, action="append", default=None, metavar="TYPE=HP",
        help="Override a unit type's MAXIMUM hit points (TYPE=HP, repeatable). DANGEROUS "
             "in any suite that measures combat or liveness: task 026 lost a run to a "
             "target dying inside a two-second measurement window, and the signature was "
             "identical to the effect being measured. Prefer --unit-hp, which sets the "
             "PLACED units' starting percentage and leaves the type alone.",
    )
    parser.add_argument(
        "--unit-mineral-cost", type=str, action="append", default=None, metavar="TYPE=N",
        help="Override a unit type's mineral cost (TYPE=N, repeatable). Only useful with "
             "the calling suite's own arithmetic updated in the same change -- "
             "test-production-queue asserts 2550 = 3000 - 9 x 50 -- and it saves no time, "
             "since nothing waits on a resource.",
    )
    parser.add_argument(
        "--unit-gas-cost", type=str, action="append", default=None, metavar="TYPE=N",
        help="The vespene counterpart of --unit-mineral-cost. Same caveat.",
    )
    parser.add_argument(
        "--unit-shields", type=str, action="append", default=None, metavar="TYPE=N",
        help="Override a unit type's shield points (TYPE=N, repeatable). Protoss only; "
             "same measurement hazard as --unit-max-hp.",
    )
    parser.add_argument(
        "--unit-armor", type=str, action="append", default=None, metavar="TYPE=N",
        help="Override a unit type's armor (TYPE=N, repeatable). Same measurement hazard "
             "as --unit-max-hp -- it changes how long a fight takes.",
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
        techs = [resolve_tech_id(t) for t in (args.tech_researched or [])]
        # Field name -> [(unit id, value)]. Empty when no --unit-* flag was passed, which
        # is what keeps the generator's output byte-identical for every existing caller.
        unit_settings = {
            field: [parse_unit_setting(s) for s in specs]
            for field, specs in (
                ("build-time", args.unit_build_time),
                ("max-hp", args.unit_max_hp),
                ("mineral-cost", args.unit_mineral_cost),
                ("gas-cost", args.unit_gas_cost),
                ("shields", args.unit_shields),
                ("armor", args.unit_armor),
            )
            if specs
        }
        if args.validate_only is not None:
            validate_map(
                args.validate_only, args.unit_count, args.unit_type, args.player,
                args.keep_ownr, args.keep_triggers, None,
                args.enemy_count, args.enemy_type, args.enemy_owner, args.min_enemy_gap,
                args.unit_hp, args.damaged_count, args.damaged_hp, techs,
                args.damaged_energy, args.starting_minerals, args.starting_gas,
                unit_settings,
            )
            return 0

        generate_map(
            args.template, args.output, args.unit_count, args.unit_type, args.player,
            args.grid_spacing, args.keep_ownr, args.clear_player_units, args.keep_triggers,
            resolve_race(args.race, args.unit_type),
            args.enemy_count, args.enemy_type,
            (args.enemy_offset_x, args.enemy_offset_y), args.enemy_spacing,
            resolve_race(args.enemy_race, args.enemy_type) if args.enemy_count else None,
            args.enemy_owner, args.min_enemy_gap, args.unit_hp,
            args.damaged_count, args.damaged_hp, techs, args.damaged_energy,
            args.starting_minerals, args.starting_gas, unit_settings,
        )
        print(f"wrote {args.output}")
        if not args.no_validate:
            validate_map(
                args.output, args.unit_count, args.unit_type, args.player, args.keep_ownr,
                args.keep_triggers, args.template,
                args.enemy_count, args.enemy_type, args.enemy_owner, args.min_enemy_gap,
                args.unit_hp, args.damaged_count, args.damaged_hp, techs,
                args.damaged_energy, args.starting_minerals, args.starting_gas,
                unit_settings,
            )
        return 0
    except (ValueError, FileNotFoundError, AssertionError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
