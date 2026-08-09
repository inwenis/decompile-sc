# Task 022 — ability semantics at >12, and three "it stopped attacking" reports

Full evidence, with disassembly and log excerpts: **`research/ability-semantics.md`**.
Regression tests: `tools/plugin/test-stim-fanout.ps1`, `test-sunken-acquire.ps1`,
`test-ability-in-combat.ps1`. PR: see the task file's `pr:` line.

---

## The three questions, answered

### 1. "if I apply steam to ferdinarines will all of them get steam and will all of them have HP decreased"

**Yes to both, and every unit pays for itself.** 36 Marines selected, one Stim keypress:

| | |
|---|---|
| units that gained the stim effect | **24** — and 24 > the 12 the engine holds, so the fan-out is what reached them |
| units that paid | the same 24, **10 hit points each**, asserted per unit against `0x2800 − N×0xa00` |
| units that gained and paid nothing | the 12 that were pre-damaged to exactly 10 hit points |

The split falls along the **hit-point** line, not along the visible/overflow line — which is
what makes it evidence that the **engine** decides who is skipped, not us. That is settled by
comparing SETS per unit, not by how the fixture was laid out (an earlier draft claimed the
damaged units fell outside the engine's twelve; checking the pointers showed the engine held
8 damaged and 4 healthy, so that reason was simply wrong):

- the set that gained the effect is **exactly** the set that could afford it, and so is the set
  that paid;
- that set is **not** the set beyond the cap — they differ;
- **the engine's own twelve is itself cut 4 / 8 along the hit-point line.** A split following
  the cap would have to take those twelve whole or leave them whole.

Two further facts, both from this binary and both confirmed in game:

- **Stim can never kill.** The affordability gate and the cost are the same constant
  (`CMP dword [unit+8],0xa00 / JLE skip`, then `MOV EAX,0xa00`) and the test is strictly
  greater. Pressing Stim three times walks a Marine 40 → 30 → 20 → 10 hit points and the
  **fourth press does nothing at all**.
- **The cost is paid every press; the effect is not extended.** The timer is *raised to*
  `0x25`, never added to. Stimming twice in a row costs 20 hit points for the same duration.

**One thing nobody here knew:** the fourth press emitted **no command at all**. There is a
send-side gate as well as the receive-side one — the client's own command card refuses to issue
an ability when the selection it can see cannot pay for it. *Which* selection it consults is an
**inference, not a measurement** — presumably the engine's twelve rather than the shadow list,
which would matter for the fan-out, but by the fourth press all 36 units were identical so the
one observation available cannot separate the two. Reported, not changed: the gate is the
engine's behaviour and this was an audit.

**Energy-costed abilities have exactly the same shape**, read out of `0x00491B30`: a per-unit
affordability test (`cost × 0x100 <= CUnit+0xA2`), a per-unit deduction of exactly that, and a
caster that cannot pay is skipped by the engine and never gets the secondary order. The
in-game half of this one is **not delivered** — see "What is not finished" below.

### 2. "there was a moment where sunken didn't attack my medic"

**Not ours, and not reproducible: the Sunken attacks Medics, in stock and with the plugin
alike.** Same map, same positions, same order, run with the plugin active and again with
`-Mode observe` (which installs no hook at all), and a Marine arm as the control:

**18 units, so the fan-out actually fires** (asserted: `FANOUT start … units=18`). The first
version used six, which never exceeds the cap — review caught that it was measuring "does
loading the plugin change acquisition" rather than "does our fan-out change it".

| arm | attacked? | evidence |
|---|---|---|
| Medics, plugin | yes | lowest hit points 276480 → **271488**; Sunken order `0x12` → `0x13` |
| Medics, stock | yes | lowest hit points 276480 → **271488** — the *same* number |
| Marines, plugin / stock | yes | 3 of 18 killed in each; the Sunken destroyed in each |

So the answer to "is it a bug we introduced" is **no**. What you most likely saw is one of
these three vanilla facts, and they are worth knowing because together they make a Sunken look
idle when it is not:

1. **A Sunken appears to shoot one target at a time.** In the medic runs exactly one Medic was
   taking damage at any moment. The fixture measures only the closest unit's distance, so "the
   other five were in range and ignored" is not established — but five of six were undamaged
   while one was being shot.
2. **Medics heal each other**, so the damage is repaired between shots. The group's total hit
   points dip and climb back — after the run the block was almost back to full, and only the
   lowest sample taken during the fight shows it was ever hit at all. Watching a Medic ball
   next to a Sunken, you can easily see no health bar move.
3. **The range is short**: 7 tiles, and the Sunken's sprite is large. A Medic that follows
   other units around drifts in and out of it.

### 3. "when i played a cloacked ghost did not attack enemies at some point"

**Read this one carefully, because what was tested is not quite what was reported.**

- **Tested:** the mechanism the report made us suspect — *do the `Select` commands our fan-out
  replays interrupt orders that are already running?* Plugin vs stock, on a real fight, with a
  fanned-out ability used mid-combat.
- **Not tested:** the cloaked-Ghost case itself. Nothing in this task ever cloaked a Ghost.
- **Why: unknown.** The Cloak button could not be driven, and this task does not know why.
  Pressing `C` produced no `0x21` in the runs that tried it, but "the key is not `C`" is
  **withdrawn** — an earlier draft rested it on a probe whose own log shows it never left the
  menu, and two attempts to redo that probe also failed to reach a measurable state. Clicking
  where the card's bottom-left slot was estimated to be produced a frame reading "Select
  Target", which says the estimated coordinates were wrong and nothing more. Owned by task 023,
  with the evidence attached.

On the mechanism, three pieces of evidence, none of which supports it:

- The ability handlers **do not touch the main order at all**. `0x004C0720` → `0x00491B30`
  (the cloak family) writes energy and the *secondary* order `CUnit+0xA6`; `0x004C2F30` (Stim)
  writes hit points and `CUnit+0x115`. Nothing on either path writes `CUnit+0x4D`.
- In the Stim run, four fanned-out commands went out to a 36-unit selection — twelve replayed
  `Select`s — and **every unit stayed on the order it already had** (`orders=[0x03:36]` before
  and after each press).
- In a live fight (`test-ability-in-combat.ps1`, 0 failure(s)), with the ability window
  bracketed by a no-ability control window on either side, on a fixture where **nothing dies**:

```
[fanout]  CONTROL before: 36 of 36 alive, 4 changed order, 4 stopped attacking
[fanout]  CONTROL after : 36 of 36 alive, 7 changed order, 6 stopped attacking
[fanout]  ABILITY window: 36 of 36 alive, 1 changed order, 0 stopped attacking
[observe] all three windows: 36 of 36 alive, 0 changed order, 0 stopped attacking

population 36 -> 36 in both arms, across the whole measurement
excess caused by the ability -- fanout: -3 (strict) / -6 (lenient); stock: 0 / 0
ability fired: stimmed 0 -> 36 (plugin), 0 -> 12 (stock)
```

  **The ability window is the quietest of the three** — one order change against four and seven
  either side, and **not one unit stopped attacking** while four and six did in ordinary
  two-second stretches of the same fight.

**The positive control is what makes this believable.** The same run shows **36 units stimmed
under the plugin against 12 under stock** — the feature provably firing at three times the
engine's cap, in the very measurement that finds nothing disturbed. A quiet result from a run
where nothing happened would prove nothing.

**Why a negative result here means something:** a replayed `Select` lands on every unit at
once, so a real interruption would show as a landslide against the control, not a margin.

**Two false positives I nearly reported, and three fixtures.**

1. Comparing raw order-churn *between* the arms gave 13 of 29 (plugin) against 2 of 29 (stock)
   — six times the disturbance. An artefact of the feature working: the move order that starts
   the fight is itself fanned out, so every unit is engaged in the plugin arm while twenty-six
   stand still in stock, and an idle unit cannot have its order interrupted. Fixed by comparing
   each arm against **its own** control.
2. The second fixture then produced 13 of 23 units "stopping attacking" against a control of
   zero — a landslide. It was a massacre: I chose Lurkers because an *unburrowed* Lurker has no
   weapon, and a computer-owned one **burrows on its own**. Player 0 went 36 → 2 units
   mid-measurement. The suite refused the run on its own gates (torn scan, unstable controls,
   "still fighting") rather than publishing it.

The premise has to be **"cannot attack"**, not "is not currently attacking" — hence Supply
Depots, which cannot attack, cannot move, and cannot decide to do either. The stock arm
recorded zero order changes in all three windows, which is why it is a weak corroborator rather
than an equal arm.

So: no evidence of a defect in the fan-out, and a mechanism-level answer. Not an explanation of
what the user saw with a cloaked Ghost.

## What is not finished, and what it would take

1. **Cloak, in game.** The Ghost's Cloak button is on the command card and the tech is
   researched by the fixture, but no keypress tried produced command `0x21`, and **the reason
   is not established**. Three explanations were floated during this task — the wrong key, the
   send-side gate, the wrong button coordinates — and none of them is supported by a run that
   reached a measurable state. Owned by task 023.
2. **The energy cost in game.** Same blocker, same fixture. The static answer is complete.
3. Neither gap changes the answer to question 1 or 2.

## Harness faults found on the way — one was corrupting every in-game suite

1. **The Game Type pick has been a silent no-op.** The game ignores a posted `WM_MOUSEMOVE`
   while its window is not the foreground window (posted *clicks* are processed either way).
   So the lobby dropdown opens, the highlight never moves, and the release commits the value
   that was already there. Because the combo remembers the last value used on this machine,
   the pick did nothing for as long as that remembered value happened to be right — and when
   this task found it, it was `Free For All`, so every generated fixture was loading as a melee
   game with the placed units never created. Fixed by activating the window (`AttachThreadInput`
   and then *verifying*, because `SetForegroundWindow` returns TRUE and does nothing for a
   background process), refusing to pick if that fails, and — the belt-and-braces that catches
   any future cause — `Set-ScGameType`, which picks a known other entry, fingerprints the
   map-information panel, picks the wanted one and requires the panel to have changed.
   *(Task 021 hit the same symptom independently and fixed it as a timing problem. Both
   changes stay; the conductor's call.)*
2. **StarCraft is single-instance, machine-wide.** A second launch exits immediately, including
   from a different working copy — a private 1.1 GB copy was made to test exactly that and made
   no difference. The launch lock only covers the launch, so a worker can hold a running game
   with the lock free. This task's suites now wait for the machine and hold the lock for as long
   as their own game lives.
3. **The shared fixture folder is a live hazard.** Every suite generates into
   `Maps\BroodWar\00-testmap` and picks its map by clicking a row, and the older suites start
   with `Remove-Item -Recurse` on it. This task came one step from deleting another worker's
   fixture out from under its running game. The new suites wait for the folder, delete only
   their own file, and name it after the task. Fixing the older suites is deliberately **not**
   in this PR (conductor's decision); the interim rule is: never delete a fixture you did not
   create, and never recursive-delete that folder while a StarCraft process is alive.

## Verification

All eight in-game suites green, plus the offline one, run on this branch:

| suite | ok | FAIL | |
|---|---|---|---|
| `test-selection-circles` | 24 | 0 | re-run after the late `Send-ScDrag` change |
| `test-fanout-orders` | 35 | 0 | re-run after the late `Send-ScDrag` change |
| `test-burrow-fanout` | 22 | 0 | |
| `test-hud-row` | 47 | 0 | |
| `test-combat-death` | 69 | 0 | |
| `test-stim-fanout` (new) | 44 | 0 | |
| `test-sunken-acquire` (new) | 24 | 0 | 18 units, fan-out asserted on the wire |
| `test-ability-in-combat` (new) | 25 | 0 | third fixture; all gates active |
| `hooktest` (offline, no game) | all | 0 | |

The two drag-heaviest suites were re-run at the very end because this task changed a shared
primitive after they were last green (`Send-ScDrag` now throws on activation failure instead of
swallowing it). A green table that predates your own last edit is not a green table.

`StarCraft.exe` byte-identical to pristine 1.16.1 before and after every run
(`AD6B58B2…288C6A46`, asserted by each suite). No stranded game processes; no fixture folders
left behind. **CI did not run** — GitHub Actions is down account-wide for billing reasons, so
these local runs are the evidence, which is why each is named with its counts rather than
summarised as "all green".

## Four harness defects in one evening, and not one was random

The dropdown pick, the drag box, the fixture-folder row, and the empty-folder row shift. Every
one presented as intermittency and every one was deterministic once the varying thing was
identified — two were called "flaky" out loud, once by me, before being dismantled. The rule
for the next one: **start from "what is deterministic about this" rather than "run it again"**.
Re-running is exactly the action that hides a positional selector over shared mutable state, or
an input path that depends on window focus.

## What changed in the repo

| | |
|---|---|
| `research/ability-semantics.md` | new — the evidence for all of the above |
| `tools/make_test_map.py`, `make-test-map.ps1` | `--tech-researched` (writes `PTEx`, so a fixture can have an ability at all), `--damaged-count/--damaged-hp/--damaged-energy` (payers and non-payers in one selection) |
| `tools/plugin/src/scplugin.cpp` | the read-only `WORLD` scan: walks the **engine's own** per-player unit lists, installs no hook, works in `-Mode observe`. Off by default (`-WorldScan 1`) |
| `tools/plugin/src/sc_fanout.cpp` | `UNITSTATE` gained `stimmed=`, `hp=`, `stim=`, `energy=`, appended so older readers still work |
| `tools/plugin/src/sc_addresses.h` | `CUnit+0x115` (stim timer) and `CUnit+0xA2` (energy), each with the instructions it was derived from |
| `tools/plugin/drive-game.ps1` | `Set-ScWindowActive`, `Set-ScGameType`, `Get-ScWorldState`, `Get-ScRegionFingerprint`, `Wait-ScNoGameRunning`, `Wait-ScTestMapDirFree` |
| three new suites | `test-stim-fanout.ps1`, `test-sunken-acquire.ps1`, `test-ability-in-combat.ps1` |

No change to the fan-out itself. No defect was found in it.
