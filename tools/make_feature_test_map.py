#!/usr/bin/env python3
"""Generate the feature-test map: a Use Map Settings sandbox for trying every mod feature by hand.

The human (slot 0) owns a Terran, a Zerg and a Protoss base side by side, each holding every
building that researches something, supply to spare and a mixed army; 50,000 minerals and gas
arrive on the first trigger loop. A computer force of units and static defence (slot 1, no AI,
it only fights what walks into range) waits across an empty strip at the bottom. The terrain is
flattened to the ground tile under the template's start location and its doodads and resources
are dropped, so every building lands where the layout puts it. What to do on it:
tools/feature-test-map-card.md. CHK and MPQ plumbing: tools/make_test_map.py.
"""

import argparse
import math
import struct
import sys
from pathlib import Path

from richchk.model.richchk.unis.unit_id import UnitId as U

import make_test_map as m

TILE = 32
HUMAN, ENEMY = 0, 1
MINERALS = GAS = 50000
# Neither side may see the other on the first frame: the longest reach on the map is a
# sieged tank's 12 tiles, and the computer's units sit on their default order, which attacks
# whatever enters its acquisition range.
MIN_SIDE_GAP_PX = 16 * TILE

# Footprints in tiles (units.dat placement box / 32). A building is placed at the centre of
# its footprint; an add-on host keeps 2 tiles free on its right for the add-on.
FOOTPRINT = {
    U.TERRAN_COMMAND_CENTER: (4, 3), U.TERRAN_SUPPLY_DEPOT: (3, 2), U.TERRAN_BARRACKS: (4, 3),
    U.TERRAN_ACADEMY: (3, 2), U.TERRAN_FACTORY: (4, 3), U.TERRAN_STARPORT: (4, 3),
    U.TERRAN_SCIENCE_FACILITY: (4, 3), U.TERRAN_ENGINEERING_BAY: (4, 3), U.TERRAN_ARMORY: (3, 2),
    U.TERRAN_MISSILE_TURRET: (2, 2), U.TERRAN_BUNKER: (3, 2),
    U.ZERG_HATCHERY: (4, 3), U.ZERG_HIVE: (4, 3), U.ZERG_SPAWNING_POOL: (3, 2),
    U.ZERG_EVOLUTION_CHAMBER: (3, 2), U.ZERG_HYDRALISK_DEN: (3, 2), U.ZERG_GREATER_SPIRE: (2, 2),
    U.ZERG_QUEENS_NEST: (2, 2), U.ZERG_DEFILER_MOUND: (4, 2), U.ZERG_ULTRALISK_CAVERN: (3, 2),
    U.ZERG_CREEP_COLONY: (2, 2), U.ZERG_SUNKEN_COLONY: (2, 2), U.ZERG_SPORE_COLONY: (2, 2),
    U.PROTOSS_NEXUS: (4, 3), U.PROTOSS_PYLON: (2, 2), U.PROTOSS_GATEWAY: (4, 3),
    U.PROTOSS_STARGATE: (4, 3), U.PROTOSS_FORGE: (3, 2), U.PROTOSS_CYBERNETICS_CORE: (3, 2),
    U.PROTOSS_CITADEL_OF_ADUN: (3, 2), U.PROTOSS_TEMPLAR_ARCHIVES: (3, 2),
    U.PROTOSS_FLEET_BEACON: (3, 2), U.PROTOSS_ARBITER_TRIBUNAL: (3, 2),
    U.PROTOSS_ROBOTICS_FACILITY: (3, 2), U.PROTOSS_ROBOTICS_SUPPORT_BAY: (3, 2),
    U.PROTOSS_OBSERVATORY: (3, 2), U.PROTOSS_PHOTON_CANNON: (2, 2), U.PROTOSS_SHIELD_BATTERY: (3, 2),
}
ADDON_HOSTS = {U.TERRAN_COMMAND_CENTER, U.TERRAN_FACTORY, U.TERRAN_STARPORT,
               U.TERRAN_SCIENCE_FACILITY}
UNPOWERED_OK = {U.PROTOSS_NEXUS, U.PROTOSS_PYLON}
# Interceptors and scarabs a placed Carrier or Reaver starts with; bit 0x20 of the
# valid-properties mask is what makes the engine read the count at all.
HANGAR = {U.PROTOSS_CARRIER: 4, U.PROTOSS_REAVER: 5}
HANGAR_VALID = 0x20


# A base is rows packed left to right. Every research building is here, so every upgrade and
# tech is on offer; Hive, Science Facility, Templar Archives and Fleet Beacon also unlock
# levels 2-3. The Terran add-ons are left for the player to build, with room kept for them.
# The depots and the pylons each fill a rectangle with nothing else in it: a box around two
# building types selects only one of them, chosen by the engine (building-groups.md 2.2).
TERRAN_BASE = [
    [U.TERRAN_COMMAND_CENTER] + [U.TERRAN_BARRACKS] * 4 + [U.TERRAN_ENGINEERING_BAY] * 2,
    [U.TERRAN_ACADEMY, U.TERRAN_ARMORY] + [U.TERRAN_FACTORY] * 2 + [U.TERRAN_STARPORT] * 2,
    [U.TERRAN_SUPPLY_DEPOT] * 8 + [U.TERRAN_SCIENCE_FACILITY],
    [U.TERRAN_SUPPLY_DEPOT] * 8,
    [U.TERRAN_SUPPLY_DEPOT] * 8,
]
ZERG_BASE = [
    [U.ZERG_HIVE] + [U.ZERG_HATCHERY] * 2
    + [U.ZERG_SPAWNING_POOL, U.ZERG_HYDRALISK_DEN, U.ZERG_CREEP_COLONY],
    [U.ZERG_EVOLUTION_CHAMBER] * 2
    + [U.ZERG_GREATER_SPIRE, U.ZERG_QUEENS_NEST, U.ZERG_DEFILER_MOUND, U.ZERG_ULTRALISK_CAVERN,
       U.ZERG_CREEP_COLONY],
]
# Two pylon rows between the two building rows put every building centre within 112 px
# vertically and 48 px horizontally of a pylon: inside the full-width band of the psi field.
PROTOSS_BASE = [
    [U.PROTOSS_NEXUS] + [U.PROTOSS_GATEWAY] * 4 + [U.PROTOSS_STARGATE] * 2,
    [U.PROTOSS_PYLON] * 12,
    [U.PROTOSS_PYLON] * 12,
    [U.PROTOSS_FORGE, U.PROTOSS_CYBERNETICS_CORE, U.PROTOSS_CITADEL_OF_ADUN,
     U.PROTOSS_TEMPLAR_ARCHIVES, U.PROTOSS_FLEET_BEACON, U.PROTOSS_ARBITER_TRIBUNAL,
     U.PROTOSS_ROBOTICS_FACILITY, U.PROTOSS_ROBOTICS_SUPPORT_BAY, U.PROTOSS_OBSERVATORY],
]

# (type, count, spacing px). Supply used after placement: Terran 116, Zerg 107, Protoss 138,
# each against a full 200, so every race can still train and queue.
TERRAN_ARMY = [
    (U.TERRAN_MARINE, 24, 32), (U.TERRAN_FIREBAT, 8, 32), (U.TERRAN_MEDIC, 8, 32),
    (U.TERRAN_GHOST, 4, 32), (U.TERRAN_SCV, 4, 32), (U.TERRAN_VULTURE, 6, 48),
    (U.TERRAN_SIEGE_TANK_TANK_MODE, 6, 48), (U.TERRAN_GOLIATH, 6, 48), (U.TERRAN_WRAITH, 6, 48),
    (U.TERRAN_DROPSHIP, 2, 64), (U.TERRAN_SCIENCE_VESSEL, 2, 64),
    (U.TERRAN_BATTLECRUISER, 2, 96),
]
ZERG_ARMY = [
    (U.ZERG_ZERGLING, 48, 32), (U.ZERG_HYDRALISK, 16, 48), (U.ZERG_LURKER, 6, 48),
    (U.ZERG_MUTALISK, 8, 48), (U.ZERG_SCOURGE, 6, 32), (U.ZERG_ULTRALISK, 4, 64),
    (U.ZERG_DEFILER, 2, 48), (U.ZERG_QUEEN, 2, 48), (U.ZERG_GUARDIAN, 2, 64),
    (U.ZERG_DEVOURER, 2, 64), (U.ZERG_DRONE, 4, 32), (U.ZERG_OVERLORD, 25, 64),
]
PROTOSS_ARMY = [
    (U.PROTOSS_ZEALOT, 24, 32), (U.PROTOSS_DRAGOON, 8, 48), (U.PROTOSS_HIGH_TEMPLAR, 4, 32),
    (U.PROTOSS_DARK_TEMPLAR_UNIT, 4, 32), (U.PROTOSS_ARCHON, 2, 64),
    (U.PROTOSS_DARK_ARCHON, 1, 64), (U.PROTOSS_REAVER, 2, 48), (U.PROTOSS_OBSERVER, 2, 32),
    (U.PROTOSS_SHUTTLE, 1, 64), (U.PROTOSS_SCOUT, 2, 48), (U.PROTOSS_CORSAIR, 4, 48),
    (U.PROTOSS_CARRIER, 2, 96), (U.PROTOSS_ARBITER, 1, 64), (U.PROTOSS_PROBE, 4, 32),
]

# The enemy field, one cluster under each base: static defence in front, units behind it.
# The cannons stand beside pylons; the sunkens and the spore beside a hatchery.
ENEMY_TERRAN = ([[U.TERRAN_MISSILE_TURRET] * 3 + [U.TERRAN_BUNKER] * 2 + [U.TERRAN_BARRACKS]],
                [(U.TERRAN_SIEGE_TANK_SIEGE_MODE, 4, 48), (U.TERRAN_MARINE, 12, 32),
                 (U.TERRAN_GOLIATH, 4, 48)])
ENEMY_ZERG = ([[U.ZERG_SUNKEN_COLONY, U.ZERG_SUNKEN_COLONY, U.ZERG_HATCHERY,
                U.ZERG_SUNKEN_COLONY, U.ZERG_SPORE_COLONY, U.ZERG_SUNKEN_COLONY]],
              [(U.ZERG_HYDRALISK, 12, 48), (U.ZERG_ZERGLING, 12, 32)])
ENEMY_PROTOSS = ([[U.PROTOSS_PYLON, U.PROTOSS_PHOTON_CANNON, U.PROTOSS_PHOTON_CANNON,
                   U.PROTOSS_PYLON, U.PROTOSS_PHOTON_CANNON, U.PROTOSS_PHOTON_CANNON,
                   U.PROTOSS_PYLON, U.PROTOSS_SHIELD_BATTERY, U.PROTOSS_PYLON, U.PROTOSS_GATEWAY]],
                 [(U.PROTOSS_ZEALOT, 8, 32), (U.PROTOSS_DRAGOON, 6, 48)])

# (owner, top tile, [(base rows, army, left tile)]): three 38-tile columns across the
# 128-tile template, the human's from the top edge, the computer's from ENEMY_TOP_TILE.
COLUMN_TILES = 38
ENEMY_TOP_TILE = 48
SIDES = [
    (HUMAN, 2, [(TERRAN_BASE, TERRAN_ARMY, 2), (ZERG_BASE, ZERG_ARMY, 45),
                (PROTOSS_BASE, PROTOSS_ARMY, 88)]),
    (ENEMY, ENEMY_TOP_TILE, [(*ENEMY_TERRAN, 4), (*ENEMY_ZERG, 45), (*ENEMY_PROTOSS, 88)]),
]


def place_buildings(rows, owner, left, top):
    """[(unit, owner, cx, cy, w_px, h_px)] and the first free tile row below them."""
    out, y = [], top
    for row in rows:
        x, row_h = left, 0
        for unit in row:
            w, h = FOOTPRINT[unit]
            out.append((unit, owner, x * TILE + w * TILE // 2, y * TILE + h * TILE // 2,
                        w * TILE, h * TILE))
            x += w + 1 + (2 if unit in ADDON_HOSTS else 0)
            row_h = max(row_h, h)
        y += row_h + 1
    return out, y


def place_army(blocks, owner, left_px, top_px, width_px, gap_px=TILE):
    """Each type in its own square-ish grid; blocks packed left to right, wrapping at width_px."""
    out, x, y, row_h = [], left_px, top_px, 0
    for unit, count, spacing in blocks:
        cols = math.ceil(math.sqrt(count))
        bw, bh = cols * spacing, math.ceil(count / cols) * spacing
        if x + bw > left_px + width_px and x > left_px:
            x, y, row_h = left_px, y + row_h + gap_px, 0
        for i in range(count):
            r, c = divmod(i, cols)
            out.append((unit, owner, x + c * spacing + spacing // 2,
                        y + r * spacing + spacing // 2, 0, 0))
        x += bw + gap_px
        row_h = max(row_h, bh)
    return out


def build_layout():
    """Every placement on the map, and the centre of the Terran army (where the camera opens)."""
    placed, camera = [], None
    for owner, top, columns in SIDES:
        for base, army, left in columns:
            buildings, free_row = place_buildings(base, owner, left, top)
            units = place_army(army, owner, left * TILE, (free_row + 1) * TILE,
                               COLUMN_TILES * TILE)
            placed += buildings + units
            if camera is None:
                camera = (sum(u[2] for u in units) // len(units),
                          sum(u[3] for u in units) // len(units))
    return placed, camera


def check_layout(placed, map_w, map_h, min_gap_px=MIN_SIDE_GAP_PX):
    """What the engine will not forgive: off the map, overlapping, unpowered, in range."""
    boxes = [(p, p[2] - p[4] // 2, p[3] - p[5] // 2, p[2] + p[4] // 2, p[3] + p[5] // 2)
             for p in placed if p[4]]
    for p, x0, y0, x1, y1 in boxes:
        assert x0 >= 0 and y0 >= 0 and x1 <= map_w * TILE and y1 <= map_h * TILE, f"off the map: {p}"
    for i, (a, ax0, ay0, ax1, ay1) in enumerate(boxes):
        for b, bx0, by0, bx1, by1 in boxes[i + 1:]:
            assert ax1 <= bx0 or bx1 <= ax0 or ay1 <= by0 or by1 <= ay0, f"overlap: {a} {b}"
    for u in (p for p in placed if not p[4]):
        assert 0 < u[2] < map_w * TILE and 0 < u[3] < map_h * TILE, f"off the map: {u}"
        for b, x0, y0, x1, y1 in boxes:
            assert not (x0 - 16 < u[2] < x1 + 16 and y0 - 16 < u[3] < y1 + 16), f"on a building: {u} {b}"
    # The engine powers a building whose centre is under its owner's pylon mask; for
    # |dy| <= 112 px every row of that mask is set across |dx| < 192 px.
    pylons = [p for p in placed if p[0] == U.PROTOSS_PYLON]
    for b in placed:
        if b[4] and b[0].name.startswith("Protoss") and b[0] not in UNPOWERED_OK:
            assert any(q[1] == b[1] and abs(q[2] - b[2]) < 192 and abs(q[3] - b[3]) <= 112
                       for q in pylons), f"unpowered: {b}"
    gap = (min(p[3] - p[5] // 2 for p in placed if p[1] == ENEMY)
           - max(p[3] + p[5] // 2 for p in placed if p[1] == HUMAN))
    assert gap >= min_gap_px, f"the two sides are only {gap}px apart"
    return gap


def fill_ground(pair, variants, w, h):
    """MTXM of one ground: the tile-group pair alternating by x, its variants scattered."""
    tiles = [(pair[x & 1] << 4) | variants[((x >> 1) * 5 + y * 3) % len(variants)]
             for y in range(h) for x in range(w)]
    return struct.pack(f"<{w * h}H", *tiles)


def flat_terrain(sections, template, start_tile):
    """MTXM filled with the ground tile pair under the start location, in the template's variants."""
    w, h = struct.unpack_from("<HH", sections[m.require_section(sections, "DIM", template)].payload)
    mtxm = struct.unpack(f"<{w * h}H", sections[m.require_section(sections, "MTXM", template)].payload)
    sx, sy = start_tile
    pair = [mtxm[sy * w + (sx & ~1)] >> 4, mtxm[sy * w + (sx | 1)] >> 4]
    variants = sorted({t & 0xF for t in mtxm if t >> 4 == pair[0]})
    return fill_ground(pair, variants, w, h), (w, h)


def unit_record(instance, unit, owner, x, y):
    return m.UnitRecord(
        instance=instance, x=x, y=y, unit_id=unit.id, rel_type=0, special_flags=0,
        valid_flags=m._VALID_OWNER_HP_SHIELD_ENERGY | (HANGAR_VALID if unit in HANGAR else 0),
        player=owner, hp=100, shield=100, energy=100, resource=0,
        hangar=HANGAR.get(unit, 0), state_flags=0, unused=0, related=0,
    )


def generate(template: Path, output: Path) -> None:
    sections = m.load_template_sections(template)
    starts = [r for r in m.parse_unit_records(
        sections[m.require_section(sections, "UNIT", template)].payload)
        if r.unit_id == m.START_LOCATION_UNIT_ID]
    human_start = next(r for r in starts if r.player == HUMAN)
    mtxm, (map_w, map_h) = flat_terrain(sections, template,
                                       (human_start.x // TILE, human_start.y // TILE))
    placed, camera = build_layout()
    gap = check_layout(placed, map_w, map_h)

    # The template's minerals, geysers and critters sat on terrain that is gone; only the
    # start locations stay, the human's moved under the Terran army so the camera opens on it.
    records = [r._replace(x=camera[0], y=camera[1]) if r.player == HUMAN else r for r in starts]
    first = max(r.instance for r in starts) + 1
    records += [unit_record(first + i, *p[:4]) for i, p in enumerate(placed)]

    sections = m.replace_section(
        sections, "UNIT", b"".join(m.pack_unit_record(r) for r in records), template)
    sections = m.rewrite_player_slots(sections, template, HUMAN, m.SIDE_TERRAN, m.SIDE_ZERG,
                                      hostile=True)
    sections = m.replace_section(
        sections, "TRIG", m.build_starting_resources_trig(HUMAN, MINERALS, GAS), template)
    sections = m.replace_section(sections, "MBRF", b"", template)
    sections = m.replace_section(sections, "MTXM", mtxm, template)
    sections = m.replace_section(sections, "THG2", b"", template)  # the doodads' sprites
    output.parent.mkdir(parents=True, exist_ok=True)
    m.save_chk_bytes_to_mpq(m.serialize_chk_sections(sections), template, output)

    human = sum(1 for p in placed if p[1] == HUMAN)
    print(f"wrote {output}")
    print(f"  human (slot 0, Terran console): {human} units and buildings; computer (slot 1): "
          f"{len(placed) - human}; {gap // TILE} empty tiles between them")
    print(f"  camera opens at ({camera[0]},{camera[1]}) px; {MINERALS} minerals and {GAS} gas")


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
