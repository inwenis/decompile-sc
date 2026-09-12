#!/usr/bin/env python3
"""Generate the battle map: two big mixed-race armies facing each other, for screenshots.

The human (slot 0) and a computer (slot 1, no AI) each field the same army of all three races
in ranks: melee in front, ranged, then tanks, lurkers, reavers and casters, then the air. A
strip of empty ground separates the two front lines; nothing fires until the human moves in.
Every tech is researched for the human, so storm, plague, yamato and the rest work at once.
The ground is one flat jungle grass. How to use it: tools/feature-test-map-card.md.
"""

import argparse
import math
import struct
import sys
from pathlib import Path

from richchk.model.richchk.unis.unit_id import UnitId as U

import make_test_map as m
from make_feature_test_map import ENEMY, HUMAN, TILE, check_layout, fill_ground, unit_record

JUNGLE_ERA = 4
# Jungle tile groups 8/9 (even/odd x) with their 12 variants: the low jungle grass,
# picked by rendering every common group of the stock jungle maps from jungle.cv5/vx4/vr4.
JUNGLE_GRASS, JUNGLE_GRASS_VARIANTS = (8, 9), list(range(12))
# Front line to front line. Every unit's attack reach is shorter than this plus its rank's
# distance behind its own front, so the armies stand still until the human attacks.
NO_MANS_LAND_TILES = 10

# Ranks from the front line backwards: (rows, [(unit, count, spacing px)]).
ARMY = [
    (2, [(U.ZERG_ZERGLING, 48, 32), (U.PROTOSS_ZEALOT, 24, 32), (U.TERRAN_FIREBAT, 12, 32),
         (U.PROTOSS_DARK_TEMPLAR_UNIT, 6, 32), (U.ZERG_ULTRALISK, 6, 64)]),
    (3, [(U.TERRAN_MARINE, 36, 32), (U.TERRAN_MEDIC, 9, 32), (U.PROTOSS_DRAGOON, 12, 48),
         (U.ZERG_HYDRALISK, 24, 48), (U.TERRAN_GOLIATH, 9, 48), (U.PROTOSS_ARCHON, 6, 64)]),
    (2, [(U.TERRAN_SIEGE_TANK_TANK_MODE, 8, 48), (U.ZERG_LURKER, 8, 48), (U.PROTOSS_REAVER, 4, 48),
         (U.PROTOSS_HIGH_TEMPLAR, 8, 32), (U.TERRAN_GHOST, 6, 32), (U.ZERG_DEFILER, 4, 48),
         (U.PROTOSS_DARK_ARCHON, 2, 64)]),
    (2, [(U.ZERG_MUTALISK, 18, 48), (U.TERRAN_WRAITH, 8, 48), (U.PROTOSS_CORSAIR, 6, 48),
         (U.TERRAN_VALKYRIE_FRIGATE, 4, 64), (U.PROTOSS_SCOUT, 4, 48), (U.ZERG_DEVOURER, 4, 64),
         (U.TERRAN_SCIENCE_VESSEL, 4, 64), (U.ZERG_QUEEN, 4, 48), (U.PROTOSS_OBSERVER, 2, 32)]),
    (2, [(U.TERRAN_BATTLECRUISER, 6, 96), (U.PROTOSS_CARRIER, 4, 96), (U.ZERG_GUARDIAN, 6, 64),
         (U.PROTOSS_ARBITER, 2, 64)]),
]
# With no AI the computer never sieges or burrows, so its tanks and lurkers start that way.
ENEMY_SWAP = {U.TERRAN_SIEGE_TANK_TANK_MODE: U.TERRAN_SIEGE_TANK_SIEGE_MODE}
ENEMY_BURROWED = {U.ZERG_LURKER}
BURROW = 0x02  # the burrowed bit of both the valid-state mask and the state flags


def place_side(owner, mid_x, front_y, step):
    """The army in ranks from front_y backwards; step -1 stacks them up the map, +1 down."""
    out, y = [], front_y
    for rows, blocks in ARMY:
        widths = [math.ceil(n / rows) * s for _, n, s in blocks]
        x = mid_x - (sum(widths) + TILE * (len(blocks) - 1)) // 2
        for (unit, n, s), w in zip(blocks, widths):
            unit = ENEMY_SWAP.get(unit, unit) if owner == ENEMY else unit
            cols = math.ceil(n / rows)
            for i in range(n):
                r, c = divmod(i, cols)
                out.append((unit, owner, x + c * s + s // 2, y + step * (r * s + s // 2), 0, 0))
            x += w + TILE
        y += step * (max(rows * s for _, _, s in blocks) + TILE)
    return out


def generate(template: Path, output: Path) -> None:
    sections = m.load_template_sections(template)
    map_w, map_h = struct.unpack_from("<HH", sections[m.require_section(sections, "DIM", template)].payload)
    mid_x, mid_y, half_gap = map_w * TILE // 2, map_h * TILE // 2, NO_MANS_LAND_TILES * TILE // 2
    placed = (place_side(HUMAN, mid_x, mid_y - half_gap, -1)
              + place_side(ENEMY, mid_x, mid_y + half_gap, +1))
    gap = check_layout(placed, map_w, map_h, min_gap_px=2 * half_gap)

    # Only the start locations survive from the template; the human's opens the camera on
    # the middle of the no-man's land, both front lines in view.
    starts = [r for r in m.parse_unit_records(
        sections[m.require_section(sections, "UNIT", template)].payload)
        if r.unit_id == m.START_LOCATION_UNIT_ID]
    records = [r._replace(x=mid_x, y=mid_y) if r.player == HUMAN else r for r in starts]
    first = max(r.instance for r in starts) + 1
    for i, (unit, owner, x, y, _, _) in enumerate(placed):
        rec = unit_record(first + i, unit, owner, x, y)
        if owner == ENEMY and unit in ENEMY_BURROWED:
            rec = rec._replace(special_flags=BURROW, state_flags=BURROW)
        records.append(rec)

    ptex = sections[m.require_section(sections, "PTEx", template)].payload
    sections = m.replace_section(
        sections, "UNIT", b"".join(m.pack_unit_record(r) for r in records), template)
    sections = m.rewrite_player_slots(sections, template, HUMAN, m.SIDE_TERRAN, m.SIDE_ZERG,
                                      hostile=True)
    sections = m.replace_section(
        sections, "PTEx", m.set_techs_researched(ptex, list(range(m.PTEX_TECHS)), HUMAN), template)
    sections = m.replace_section(sections, "TRIG", b"", template)
    sections = m.replace_section(sections, "MBRF", b"", template)
    sections = m.replace_section(sections, "ERA", struct.pack("<H", JUNGLE_ERA), template)
    sections = m.replace_section(
        sections, "MTXM", fill_ground(JUNGLE_GRASS, JUNGLE_GRASS_VARIANTS, map_w, map_h), template)
    sections = m.replace_section(sections, "THG2", b"", template)  # the doodads' sprites
    output.parent.mkdir(parents=True, exist_ok=True)
    m.save_chk_bytes_to_mpq(m.serialize_chk_sections(sections), template, output)

    human = sum(1 for p in placed if p[1] == HUMAN)
    print(f"wrote {output}")
    print(f"  human (slot 0): {human} units; computer (slot 1): {len(placed) - human}; "
          f"{gap // TILE} tiles between the front ranks; camera opens at ({mid_x},{mid_y}) px")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--template", type=Path, default=Path(m.DEFAULT_TEMPLATE))
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        generate(args.template, args.output)
        return 0
    except (ValueError, FileNotFoundError, AssertionError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
