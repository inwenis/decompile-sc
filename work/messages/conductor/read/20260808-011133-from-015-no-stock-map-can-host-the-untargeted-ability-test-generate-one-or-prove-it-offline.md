---
from: 015
to: conductor
sent: 2026-08-08T01:11:33Z
subject: No stock map can host the untargeted-ability test — generate one, or prove it offline?
type: question
options: Generate a map (36 High Templar, archon merge); Offline proof only, stop+hold in game; Something else
---

## The blocker

Acceptance criterion 3 asks for **one untargeted ability fanning out on a stock map**. I
scanned all 210 stock `.scm`/`.scx` files in `C:\sc-work\1161-base\Maps\` offline (richchk,
read-only) and there is **no stock map that can host that test**:

| requirement | why | best stock map |
|---|---|---|
| >12 units in one drag box, human-owned | fan-out only fires above the cap | `(1)Enslavers02b` — 22 Protoss, works today |
| the >12 must be ONE unit type | an ability button is only offered for a homogeneous selection | — |
| that type must have an untargeted ability needing no research | stim/siege/burrow/cloak all need research | — |

Across all 210 maps, exactly **one** human-owned same-type group exceeds 12 units:
`(1)Enslavers03a.scm` slot 6, **16 Marines** — and they are spread far enough apart that at
most **8** fit on one screen, so they cannot be boxed together. Every other human group over
12 units is mixed-type (`Enslavers02b`: 12 Zealots + 4 Dragoons + 3 Scouts + 2 Observers +
1 Archon; `Twilight Struggle`: 7 Marines + 7 SCVs + 4 Vultures).

The task's own note ("`(1)Enslavers02b.scm` has 24 dragoons in one box") is what the box
actually contains — 24 units, but of five different types, and no Protoss unit in it has any
untargeted ability at all. Confirmed in game: with that 24-unit box selected, sweeping the
whole alphabet as hotkeys emits exactly **two** commands, `0x1A` (Stop) and `0x2B` (Hold
Position). Nothing else.

## What is NOT blocked

Everything else in the task is on track and does not depend on this answer:

- The command-length table is found and read (`0x005005F8`), the receive-side dispatcher is
  decompiled (`0x004865D0`), and every opcode is classified by how its handler uses the
  selection — that is the whole per-opcode policy, with evidence.
- Stop (`0x1A`) and Hold Position (`0x2B`) are named from in-game keypresses, and both have
  the "applies to every selected unit" handler shape, so both are in the fan-out set.
- Attack / Patrol / Move are all `0x15` with order bytes `0x08` / `0x98` / `0x31` — already
  fanned out since task 011; criterion 4 is answered "already worked".

## The question

Criterion 3 needs a fixture the stock set does not contain. Options:

1. **Generate one** with the repo's own `tools/make_test_map.py` (task 009) — e.g. 36 High
   Templar, whose Archon Merge (`0x2A`) is untargeted and needs no research, or 36 Lurkers
   (burrow, also no research). This breaks the task's "stock maps only" line but is the only
   way to get the in-game proof criterion 3 asks for. The generator is already committed and
   its output already sits in the Maps folder from task 009.
2. **Drop the in-game half of criterion 3** and prove the untargeted-ability path offline
   instead: hooktest drives a full fan-out of an ability opcode and asserts the exact emitted
   bytes, while the in-game evidence that untargeted commands fan out at >12 comes from Stop
   and Hold. The code path is identical for every id in the fan-out set — the opcode is a
   table entry, not a branch.
3. Something else you have in mind.

I am proceeding with option 2's work regardless, because it is needed either way. Tell me if
you want option 1 and I will add the generated-map run on top.
