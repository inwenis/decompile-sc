#!/usr/bin/env python3
"""Read-only inspector for a StarCraft 1.16.1 map's scenario.chk.

This is the tool that produced task 016's root-cause evidence for why generated
maps did not play (tools/README-test-map.md, research/command-opcodes.md 8.1).
It decodes NOTHING through richchk's CHK layer -- sections are raw bytes in file
order -- so what it prints is what the engine reads, not what a library thinks
the file means.

    python tools/inspect_map.py sections MAP
    python tools/inspect_map.py diff MAP_A MAP_B
    python tools/inspect_map.py players MAP
    python tools/inspect_map.py triggers MAP

`diff` is the one that matters most: it is how "the CHK round-trip corrupted the
triggers" was disproved (TRIG came back byte-identical) and how richchk 0.3.0 was
caught rewriting UNIS/UNIx, MRGN and SWNM unasked.
"""

import argparse
import struct
import sys
from collections import Counter, defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from make_test_map import (  # noqa: E402
    OWNR_NAMES, SIDE_NAMES, START_LOCATION_UNIT_ID, parse_chk_sections,
    parse_unit_records, read_chk_bytes,
)

# --- TRIG record layout (staredit.net CHK spec) ----------------------------
# 2400 bytes per trigger: 16 conditions x 20 bytes, 64 actions x 32 bytes,
# 4 bytes execution flags, 28 bytes "executing players" (one per group slot).
_TRIGGER_SIZE = 2400
_COND_SIZE = 20
_ACTION_SIZE = 32

CONDITIONS = {
    0: "(none)", 1: "Countdown Timer", 2: "Command", 3: "Bring", 4: "Accumulate",
    5: "Kill", 6: "Command the Most", 7: "Command the Most At", 8: "Most Kills",
    9: "Highest Score", 10: "Most Resources", 11: "Switch", 12: "Elapsed Time",
    13: "(briefing only)", 14: "Opponents", 15: "Deaths", 16: "Command the Least",
    17: "Command the Least At", 18: "Least Kills", 19: "Lowest Score",
    20: "Least Resources", 21: "Score", 22: "Always", 23: "Never",
}
ACTIONS = {
    0: "(none)", 1: "Victory", 2: "Defeat", 3: "Preserve Trigger", 4: "Wait",
    5: "Pause Game", 6: "Unpause Game", 7: "Transmission", 8: "Play WAV",
    9: "Display Text Message", 10: "Center View", 11: "Create Unit with Properties",
    12: "Set Mission Objectives", 13: "Set Switch", 14: "Set Countdown Timer",
    15: "Run AI Script", 16: "Run AI Script At Location", 17: "Leader Board Control",
    18: "Leader Board Control At Location", 19: "Leader Board Resources",
    20: "Leader Board Kills", 21: "Leader Board Points", 22: "Kill Unit",
    23: "Kill Unit At Location", 24: "Remove Unit", 25: "Remove Unit At Location",
    26: "Set Resources", 27: "Set Score", 28: "Minimap Ping", 29: "Talking Portrait",
    30: "Mute Unit Speech", 31: "Unmute Unit Speech", 32: "Leaderboard Computer Players",
    33: "Leaderboard Goal Control", 34: "Leaderboard Goal Control At Location",
    35: "Leaderboard Goal Resources", 36: "Leaderboard Goal Kills",
    37: "Leaderboard Goal Points", 38: "Move Location", 39: "Move Unit",
    40: "Leaderboard Greed", 41: "Set Next Scenario", 42: "Set Doodad State",
    43: "Set Invincibility", 44: "Create Unit", 45: "Set Deaths", 46: "Order",
    47: "Comment", 48: "Give Units to Player", 49: "Modify Unit Hit Points",
    50: "Modify Unit Energy", 51: "Modify Unit Shield Points",
    52: "Modify Unit Resource Amount", 53: "Modify Unit Hangar Count",
    54: "Pause Timer", 55: "Unpause Timer", 56: "Draw", 57: "Set Alliance Status",
}
# The 28 slots a trigger's "executing players" array covers, and the same
# numbering a condition's `group` field uses.
GROUPS = {
    **{i: f"Player{i + 1}" for i in range(12)},
    13: "CurrentPlayer", 14: "Foes", 15: "Allies", 16: "NeutralPlayers",
    17: "AllPlayers", 18: "Force1", 19: "Force2", 20: "Force3", 21: "Force4",
    26: "NonAlliedVictoryPlayers",
}
# The unit-id values that mean a CLASS of unit rather than one type.
UNIT_CLASSES = {228: "[Any unit]", 229: "[Men]", 230: "[Buildings]", 231: "[Factories]"}
COMPARISONS = {0: "at least", 1: "at most", 10: "exactly"}
# A trigger action that can take the game away from the player. These are the
# reason a generated map must ship an empty TRIG.
GAME_ENDING = {1, 2, 41, 56}


def group_name(g):
    return GROUPS.get(g, f"group{g}")


def unit_name(u):
    return UNIT_CLASSES.get(u, f"unit{u}")


def load(path: Path):
    return parse_chk_sections(read_chk_bytes(path))


def cmd_sections(args):
    secs = load(args.map)
    total = sum(len(s.payload) for s in secs) + 8 * len(secs)
    print(f"{args.map}: {total} bytes of CHK, {len(secs)} section(s), in file order")
    for s in secs:
        print(f"  {s.name} {len(s.payload)}")


def cmd_diff(args):
    a, b = load(args.map_a), load(args.map_b)
    print(f"A = {args.map_a}  ({len(a)} sections)")
    print(f"B = {args.map_b}  ({len(b)} sections)")
    names_a = [s.name for s in a]
    names_b = [s.name for s in b]
    if names_a != names_b:
        print("!! the section list itself differs")
        ca, cb = Counter(names_a), Counter(names_b)
        for n in sorted(set(ca) | set(cb)):
            if ca[n] != cb[n]:
                print(f"   {n}: A has {ca[n]}, B has {cb[n]}")

    # Compare by (name, nth occurrence of that name), so duplicated sections
    # line up with their counterparts instead of with each other.
    def keyed(secs):
        seen, out = {}, {}
        for s in secs:
            k = (s.name, seen.get(s.name, 0))
            seen[s.name] = seen.get(s.name, 0) + 1
            out[k] = s.payload
        return out

    da, db = keyed(a), keyed(b)
    print(f"\n{'section':9} {'A bytes':>9} {'B bytes':>9}  verdict")
    for k in sorted(set(da) | set(db)):
        pa, pb = da.get(k), db.get(k)
        label = f"{k[0]}#{k[1]}" if k[1] else k[0]
        if pa is None:
            print(f"{label:9} {'-':>9} {len(pb):>9}  ONLY IN B")
        elif pb is None:
            print(f"{label:9} {len(pa):>9} {'-':>9}  ONLY IN A")
        elif pa == pb:
            print(f"{label:9} {len(pa):>9} {len(pb):>9}  identical")
        else:
            first = next((i for i, (x, y) in enumerate(zip(pa, pb)) if x != y),
                         min(len(pa), len(pb)))
            ndiff = sum(1 for x, y in zip(pa, pb) if x != y)
            print(f"{label:9} {len(pa):>9} {len(pb):>9}  DIFFERS "
                  f"(first differing byte at {first}, {ndiff} differ in the common prefix)")


def cmd_players(args):
    secs = {s.name: s.payload for s in load(args.map)}
    ownr = secs.get("OWNR", b"")
    side = secs.get("SIDE", b"")
    forc = secs.get("FORC", b"")
    assign = list(forc[:8]) if len(forc) >= 8 else []
    flags = list(forc[16:20]) if len(forc) >= 20 else []

    print(f"{args.map}")
    print("  FORC force flags: " + " ".join(f"Force{i + 1}=0x{f:02X}" for i, f in enumerate(flags)))
    print("    (bit 0x01 random start location, 0x02 allied, 0x04 allied victory, 0x08 shared vision)")

    owned = defaultdict(Counter)
    for rec in parse_unit_records(secs.get("UNIT", b"")):
        if rec.unit_id == START_LOCATION_UNIT_ID:
            owned[rec.player]["<start location>"] += 1
        else:
            owned[rec.player][f"unit{rec.unit_id}"] += 1

    print(f"\n  {'slot':>4} {'OWNR':<16} {'SIDE':<16} {'force':<7} units")
    for p in range(12):
        o = ownr[p] if p < len(ownr) else None
        s = side[p] if p < len(side) else None
        f = f"Force{assign[p] + 1}" if p < len(assign) else "-"
        n = sum(v for k, v in owned[p].items() if k != "<start location>")
        if o == 0 and n == 0 and not owned[p]:
            continue
        print(f"  {p:>4} {OWNR_NAMES.get(o, o):<16} {SIDE_NAMES.get(s, s):<16} {f:<7} {n}")
        for name, count in owned[p].most_common(12):
            print(f"         {count:>4} {name}")


def cmd_triggers(args):
    secs = {s.name: s.payload for s in load(args.map)}
    trig = secs.get("TRIG", b"")
    n = len(trig) // _TRIGGER_SIZE
    print(f"{args.map}: TRIG is {len(trig)} bytes = {n} trigger(s)")
    if n == 0:
        print("  nothing here can end the game -- this is what a generated fixture must look like")
        return
    for t in range(n):
        rec = trig[t * _TRIGGER_SIZE:(t + 1) * _TRIGGER_SIZE]
        who = [group_name(i) for i, v in enumerate(rec[2372:2400]) if v]
        conds, acts, ends = [], [], False
        for c in range(16):
            cb = rec[c * _COND_SIZE:(c + 1) * _COND_SIZE]
            loc, grp, qty = struct.unpack_from("<III", cb, 0)
            unit, comp, ctype, _res, _fl, _mask = struct.unpack_from("<HBBBBH", cb, 12)
            if ctype == 0:
                continue
            conds.append(f"{CONDITIONS.get(ctype, ctype)}: {group_name(grp)} "
                         f"{COMPARISONS.get(comp, comp)} {qty} {unit_name(unit)}"
                         + (f" @loc{loc}" if loc else ""))
        base = 320
        for a in range(64):
            ab = rec[base + a * _ACTION_SIZE:base + (a + 1) * _ACTION_SIZE]
            atype = ab[26]
            if atype == 0:
                continue
            if atype in GAME_ENDING:
                ends = True
            acts.append(ACTIONS.get(atype, atype))
        if args.ending_only and not ends:
            continue
        mark = "  *** ENDS THE GAME" if ends else ""
        print(f"\n-- trigger {t}  executed by {who}{mark}")
        for c in conds:
            print(f"     IF   {c}")
        print(f"     THEN {', '.join(acts)}")


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("sections", help="every CHK chunk, in file order, with its size")
    p.add_argument("map", type=Path)
    p.set_defaults(func=cmd_sections)

    p = sub.add_parser("diff", help="compare two maps' CHK sections byte for byte")
    p.add_argument("map_a", type=Path)
    p.add_argument("map_b", type=Path)
    p.set_defaults(func=cmd_diff)

    p = sub.add_parser("players", help="per-slot OWNR/SIDE/force and unit inventory")
    p.add_argument("map", type=Path)
    p.set_defaults(func=cmd_players)

    p = sub.add_parser("triggers", help="decode TRIG into readable conditions and actions")
    p.add_argument("map", type=Path)
    p.add_argument("--ending-only", action="store_true",
                   help="only the triggers that can end the game (Victory/Defeat/Draw/"
                        "Set Next Scenario)")
    p.set_defaults(func=cmd_triggers)

    args = parser.parse_args()
    try:
        args.func(args)
        return 0
    except (ValueError, FileNotFoundError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
