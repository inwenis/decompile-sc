#!/usr/bin/env python3
"""Add a DECOY UNIS section to a Brood War map, disagreeing with its UNIx.

This is experimental apparatus, not part of the fixture generator. It exists to make one
question answerable by a single in-game read: WHICH unit-settings section does the engine
actually apply to a Brood War Use Map Settings map?

Everything else task 031 has on that question is inference -- the template carries no UNIS
at all, and the engine's Brood War CHK section table (StarCraft.exe .rdata 0x5004A8) lists
UNIx and no UNIS. Inference is what task 026 said not to trust: `make_test_map.py` once
wrote PTEx with one indexing and read it back with the same one, and its validator
cheerfully confirmed its own mistake. So this builds a map on which the two sections say
DIFFERENT things and lets the running game cast the deciding vote:

    UNIx says a Marine has 25 hit points
    UNIS says a Marine has 12 hit points
    units.dat says 40

and the number read out of CUnit+0x08 in game is a three-way answer. "Neither" is a
possible outcome and would mean the whole approach is wrong, which is the property that
makes this an experiment rather than a confirmation.

THE DECOY IS APPENDED AFTER UNIx ON PURPOSE. The engine applies overwriting sections in
file order, so a later chunk beats an earlier one. Putting UNIS last gives it every
advantage available; if the game still reads the UNIx number, no ordering argument is
left. Placing it first would have proved nothing either way.

UNIS is the VANILLA layout and is NOT the same size as UNIx: 100 weapons rather than 130,
so 4048 bytes rather than 4168. Both arrays are per-unit-type up to the weapon tables, so
the fields this script writes sit at identical offsets in both.

Usage:
    python tools/add_unis_decoy.py --map <path.scx> --unit marine --max-hp 12
"""

import argparse
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from make_test_map import (  # noqa: E402
    ChkSection,
    UNIX_OFF_HIT_POINTS,
    UNIX_OFF_USE_DEFAULT,
    UNIX_SIZE,
    UNIX_UNITS,
    HP_FIXED_POINT,
    chk_name,
    find_section,
    parse_chk_sections,
    read_chk_bytes,
    resolve_unit_id,
    save_chk_bytes_to_mpq,
    serialize_chk_sections,
)

UNIS_WEAPONS = 100
UNIS_SIZE = UNIX_SIZE - 2 * 2 * (130 - UNIS_WEAPONS)   # 4168 - 120 = 4048


def build_unis_from_unix(unix_payload: bytes, unit_id: int, max_hp: int) -> bytes:
    """A well-formed UNIS carrying the template's own numbers, bar the one decoy value.

    Built FROM the map's UNIx so that every other unit in it says exactly what the map
    already says. A decoy full of zeroes would be a second variable: if the game came up
    strange, "UNIS was applied" and "UNIS was garbage" would be indistinguishable.
    """
    if len(unix_payload) != UNIX_SIZE:
        raise ValueError(f"UNIx is {len(unix_payload)} bytes, expected {UNIX_SIZE}")
    # Everything up to the weapon tables is laid out identically in both sections.
    head_len = UNIX_SIZE - 2 * 2 * 130
    buf = bytearray(unix_payload[:head_len]) + bytearray(2 * 2 * UNIS_WEAPONS)
    # The weapon tables are copied for the first 100 weapons, which is all UNIS has.
    weapons = unix_payload[head_len:]
    base = weapons[:2 * 130]
    bonus = weapons[2 * 130:]
    buf[head_len:head_len + 2 * UNIS_WEAPONS] = base[:2 * UNIS_WEAPONS]
    buf[head_len + 2 * UNIS_WEAPONS:] = bonus[:2 * UNIS_WEAPONS]
    if len(buf) != UNIS_SIZE:
        raise AssertionError(f"built a {len(buf)}-byte UNIS, expected {UNIS_SIZE}")
    struct.pack_into("<I", buf, UNIX_OFF_HIT_POINTS + 4 * unit_id, max_hp * HP_FIXED_POINT)
    buf[UNIX_OFF_USE_DEFAULT + unit_id] = 0
    return bytes(buf)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--map", type=Path, required=True)
    ap.add_argument("--unit", type=str, default="marine")
    ap.add_argument("--max-hp", type=int, required=True,
                    help="The hit points the DECOY claims. Must differ from what UNIx "
                         "says and from the unit's real value, or the read cannot tell "
                         "the three cases apart.")
    args = ap.parse_args()

    unit_id = resolve_unit_id(args.unit)
    if unit_id >= UNIX_UNITS:
        raise SystemExit(f"unit id {unit_id} is outside UNIx")

    sections = parse_chk_sections(read_chk_bytes(args.map))
    if find_section(sections, "UNIS") >= 0:
        raise SystemExit(f"{args.map} already has a UNIS section; refusing to add a second")
    unix_idx = find_section(sections, "UNIx")
    if unix_idx < 0:
        raise SystemExit(f"{args.map} has no UNIx section -- not a Brood War map")

    unix_payload = sections[unix_idx].payload
    (unix_hp,) = struct.unpack_from("<I", unix_payload, UNIX_OFF_HIT_POINTS + 4 * unit_id)
    unix_hp //= HP_FIXED_POINT
    if unix_hp == args.max_hp:
        raise SystemExit(
            f"UNIx already says unit {unit_id} has {unix_hp} hit points, which is what "
            f"the decoy would say too -- the read could not tell them apart."
        )

    decoy = build_unis_from_unix(unix_payload, unit_id, args.max_hp)
    # APPENDED LAST. See the header: this hands UNIS the file-order advantage.
    sections = list(sections) + [ChkSection(chk_name("UNIS"), decoy)]
    save_chk_bytes_to_mpq(serialize_chk_sections(sections), args.map, args.map)

    print(f"decoy: added a {len(decoy)}-byte UNIS as the LAST chunk of {args.map}")
    print(f"  UNIS says unit {unit_id} ({args.unit}) has {args.max_hp} hit points "
          f"-> CUnit hp would read {args.max_hp * HP_FIXED_POINT}")
    print(f"  UNIx says {unix_hp} -> CUnit hp would read {unix_hp * HP_FIXED_POINT}")
    print(f"  neither applied -> the units.dat value, whatever it is")
    return 0


if __name__ == "__main__":
    sys.exit(main())
