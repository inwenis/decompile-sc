# Runtime observations of the selection state (task 008)

Every address in [`binary-selection-map.md`](binary-selection-map.md) was verified
**statically**: the instruction exists, it references what we claim, the neighbours are
identified. None of it had been checked against a **running** process. This document reports
what happened when we put our own code inside StarCraft 1.16.1 and read those addresses live.

Tooling, toolchain and injection design: [`tools/plugin/README.md`](../tools/plugin/README.md).

All work was done on the disposable working copy `C:\decompile-sc-data\sc-work\1161-base`, offline, single-player
only. No Battle.net, no multiplayer, no CD key. The plugin is **read-only**: it does not write
to game memory, patch code, change page protections, or hook input.

---

## 0. Summary

| question | answer |
|---|---|
| Does our code run inside the game? | **Yes** |
| Did `StarCraft.exe` load at its preferred base `0x00400000`? | **Yes — relocation delta exactly `+0`** |
| Are the static addresses usable verbatim at runtime? | **Yes, no rebasing needed** |
| Does `clientSelectionCount` track what is selected on screen? | **Yes — 1 → 2 → 4, exactly; §3** |
| Does the game still work with our DLL loaded? | **Yes** |
| Does windowed mode still work? | **Yes — and it now works for the first time; see §4** |

Two things found that were not in the static map, both worth carrying into rung 2:

- **`clientSelectionCount` is not safe to trust on its own.** At teardown it read `4` while
  `clientSelectionGroup` was already all-NULL (§3.4).
- **The client array leads the per-player array**, and the two order the same units differently
  (§3.6).

And one prior-research disagreement, which is *not* about the selection map:
[`launch-baseline.md`](launch-baseline.md)'s windowed-mode recipe is **wrong**, and our runs say
so with the plugin absent as well as present (§4).

---

## 1. The module loads at its preferred base — delta `+0`

This is the result that removes a whole class of risk from later work, so it is stated first.

The plugin does not assume the image base. On attach it takes `GetModuleHandleA(NULL)`, compares
it against the PE's preferred `ImageBase` of `0x00400000` (from
[`pe-anatomy.md`](pe-anatomy.md)), and logs the delta. Every static address it later reads is
computed as `actualBase + (staticVA - 0x00400000)`, so a relocated load would have been handled
rather than silently producing garbage.

```
[2026-08-07 08:30:19.324] ATTACH pid=26952 tid=21604
[2026-08-07 08:30:19.324]   host exe      : C:\decompile-sc-data\sc-work\1161-base\StarCraft.exe
[2026-08-07 08:30:19.324]   module base   : 0x00400000
[2026-08-07 08:30:19.324]   preferred base: 0x00400000
[2026-08-07 08:30:19.324]   reloc delta   : +0x00000000  => static addresses are USABLE VERBATIM
[2026-08-07 08:30:19.324]   image[0..1]   : 0x5A4D ('MZ' - mapped image confirmed)
```

**`StarCraft.exe` loads at `0x00400000`.** Reproduced across every launch in this task
(fullscreen and windowed, plugin injected early and late). The `MZ` read is a sanity check that
we are looking at the mapped image and not at an address that merely happens to be readable.

Why it matters: ASLR would have shifted every address in `binary-selection-map.md` by a
per-boot delta, and every hardcoded constant in rungs 2 and 3 would have needed rebasing at
runtime. It does not. The binary is a 1998-era PE with no `IMAGE_DLLCHARACTERISTICS_DYNAMIC_BASE`
flag, so Windows honours its preferred base — which is what we observed, not what we assumed.

> Caveat, stated because it is the kind of thing this task exists to catch: this is one machine,
> one Windows build (Windows 11 26200), with the EXE loaded as the *primary* image. It is not a
> claim that no configuration could ever relocate it. The plugin recomputes the delta on every
> attach and logs it, so a future run on a machine that *does* relocate will say so in its first
> five lines rather than producing silently wrong reads.

---

## 2. Our code runs inside the process

`scinject.exe` starts `StarCraft.exe` from the working copy and injects `scplugin.dll` with
`CreateRemoteThread` at `kernel32!LoadLibraryA`. The remote thread's exit code is the resulting
`HMODULE`, which is checked rather than assumed:

```
scinject: launched pid=26952  C:\decompile-sc-data\sc-work\1161-base\StarCraft.exe
scinject: early-injected C:\decompile-sc-data\sc-work\1161-base\WMode.dll -> HMODULE 0x10000000
scinject: WaitForInputIdle -> 0
scinject: injected ...\scplugin.dll -> HMODULE 0x71F70000 in pid 26952
```

and the DLL's own first log lines (quoted in §1) confirm it from inside the process: correct
pid, correct host executable path, mapped image readable.

**No file is added to the game directory.** The plugin is loaded from wherever it was built.
That is a deliberate property of the injection vector, not an accident — see
[`tools/plugin/README.md`](../tools/plugin/README.md) § "Injection design, and why".

---

## 3. Runtime selection reads

### 3.1 What was done

A single-player melee game on the working copy, played by hand (synthetic mouse input was tried
first and abandoned — see §5). Three actions, in order:

1. click **one** worker,
2. **shift-click** a second,
3. **drag a box** around the starting units.

The observer was already attached and polling at 250 ms, logging only on change. Those three
actions are the only three state transitions in the log.

### 3.2 The log

```
[2026-08-07 08:35:48.210] SEL count=0 nonNullGroup=0 iter=0 player=1/1/1 ok=0x3F
                              clientSelectionGroup   (none)

[2026-08-07 08:35:58.438] SEL count=1 nonNullGroup=1 iter=0 player=1/1/1 ok=0x3F
                              clientSelectionGroup   [0]=0x00623678
                              activePlayerSelection  [0]=0x00623678
                              playersSelections[1]   [0]=0x00623678
                              clientSelectionGroup2  [0]=0x00623678

[2026-08-07 08:36:07.647] SEL count=2 nonNullGroup=2 iter=0 player=1/1/1 ok=0x3F
                              clientSelectionGroup   [0]=0x00623678 [1]=0x00623288
                              activePlayerSelection  [0]=0x00623678 [1]=0x00623288
                              playersSelections[1]   [0]=0x00623678
                              clientSelectionGroup2  [0]=0x00623678 [1]=0x00623288

[2026-08-07 08:36:07.915] SEL count=2 nonNullGroup=2 iter=0 player=1/1/1 ok=0x3F
                              playersSelections[1]   [0]=0x00623678 [1]=0x00623288

[2026-08-07 08:36:15.071] SEL count=4 nonNullGroup=4 iter=0 player=1/1/1 ok=0x3F
                              clientSelectionGroup   [0]=0x00623678 [1]=0x00623528 [2]=0x006233D8 [3]=0x00623288
                              activePlayerSelection  [0]=0x00623678 [1]=0x00623528 [2]=0x006233D8 [3]=0x00623288
                              playersSelections[1]   [0]=0x00623678 [1]=0x00623288 [2]=0x00623528 [3]=0x006233D8
                              clientSelectionGroup2  [0]=0x00623678 [1]=0x00623528 [2]=0x006233D8 [3]=0x00623288
```

`ok=0x3F` means all six read groups succeeded. At the main menu it reads `0x2F` — the
`playersSelections` row is deliberately skipped there because the active player id is `8`, the
no-active-player value.

### 3.3 Verdict per address

| global | address | verdict |
|---|---|---|
| `clientSelectionGroup` | `0x00597208` | **holds** — `CUnit*[12]`, packed from index 0 |
| `clientSelectionCount` | `0x0059723D` | **holds** — and behaves as the `u8` §7.2 resolved it to be |
| `activePlayerSelection` | `0x006284B8` | **holds** — `CUnit*[12]` |
| `playersSelections` | `0x006284E8` | **holds** — `[8][12]`; player 1's row at `+48` confirmed |
| `clientSelectionGroup2` | `0x0059724C` | **holds** — `CUnit*[12]` |
| `selectionIterator` | `0x006284B6` | readable, always `0` at our sampling rate — see §3.7 |
| player ids | `0x0051267C` / `0x00512688` / `0x00512678` | **hold**, and are distinct — see §3.8 |

**Nothing in [`binary-selection-map.md`](binary-selection-map.md) disagreed with the running
process.** No address was wrong, no array shape was wrong, no width was wrong. The two
differences documented in §3.6 are between arrays the map already describes as different things;
they are new behavioural facts, not errors in the map.

### 3.4 The count and the array agreed on every in-game sample — and disagreed exactly once, at teardown

`nonNullGroup` is computed independently by walking all 12 slots and counting non-null pointers,
specifically so it can be checked against the count byte rather than echoing it. Through the
whole session they agreed: `0/0`, `0/0`, `0/0`, `1/1`, `2/2`, `2/2`, `4/4`.

Populated slots were contiguous from index 0 in all three cases, with no stale pointers left
beyond the count and nothing above index 3.

**The one disagreement, and it is worth knowing about.** When the game was closed, the final
sample caught the shutdown mid-flight:

```
[2026-08-07 08:42:24.174] SEL count=4 nonNullGroup=0 iter=0 player=1/1/1 ok=0x3F
[2026-08-07 08:42:24.184]     clientSelectionGroup   (none)
[2026-08-07 08:42:24.185]     activePlayerSelection  [0]=0x00623678 [1]=0x00623528 [2]=0x006233D8 [3]=0x00623288
[2026-08-07 08:42:24.186]     playersSelections[1]   [0]=0x00623678 [1]=0x00623288 [2]=0x00623528 [3]=0x006233D8
[2026-08-07 08:42:24.188]     clientSelectionGroup2  [0]=0x00623678 [1]=0x00623528 [2]=0x006233D8 [3]=0x00623288
[2026-08-07 08:42:24.215] DETACH pid=26952
```

`clientSelectionGroup` had been zeroed while `clientSelectionCount` still read **4**, and the
other three arrays still held all four unit pointers. So on the way out, the client array is
cleared **before** the count byte, and `activePlayerSelection` is not cleared with it.

The consequence for later rungs is concrete: **`clientSelectionCount` is not safe to trust on its
own.** Anything that reads `count` and then walks that many slots can, during teardown or a game
transition, walk 4 NULLs believing it has 4 units. Read the slots and check them; do not use the
count as a promise about the array. This is precisely the class of bug that would have been
expensive to find while writing, and cost nothing to find while reading.

`count=4` for "box around the starting units" is the exact right answer rather than an
approximate one: a melee start is 4 workers plus one main building, and a drag box containing
both selects only the units. 4 rather than 5 is itself a small confirmation that the byte means
what the map says it means.

### 3.5 The pointers are 336 bytes apart — measured, not assumed

The four selected units' pointers are separated by exactly `0x150` each:

```
0x00623678 - 0x00623528 = 0x150   (336)
0x00623528 - 0x006233D8 = 0x150   (336)
0x006233D8 - 0x00623288 = 0x150   (336)
```

That stride is **our own measurement**, taken from values this task logged, with no external
constant involved. 336 is the community-documented `sizeof(CUnit)`, so this is an independent
runtime corroboration of it.

Going one step further requires a constant this repo has **not** verified, and is flagged
accordingly: *if* the community's unit-array base `0x0059CCA8` is assumed, the four pointers land
on indices **1638, 1639, 1640, 1641** — consecutive, with zero remainder on all four. Four exact
integer hits is strong support for that base, but the base itself remains unverified prior art
here and must be re-derived from the binary before anything in `research/` depends on it.

### 3.6 The client array and the per-player array are genuinely different — in two ways

`binary-selection-map.md` treats the client-side copy and the simulation-side per-player array as
distinct things. Live, they are, and the differences are worth having on record before rung 2 is
designed.

**(a) They update at different times. The client array leads.**

At `08:36:07.647` the client array already held two units while `playersSelections[1]` still held
one. It caught up 268 ms later:

```
[08:36:07.647]  clientSelectionGroup   [0]=0x00623678 [1]=0x00623288
[08:36:07.647]  playersSelections[1]   [0]=0x00623678                  <- one behind
[08:36:07.915]  playersSelections[1]   [0]=0x00623678 [1]=0x00623288   <- caught up
```

This is the command-latency/turn model visible in memory: the client copy changes on input, the
per-player array changes when the order is processed. **Rung 2 must not assume the two arrays are
coherent within a frame.**

**(b) They order the same units differently.**

At `count=4`, same four units, different order:

```
clientSelectionGroup   [0]=0x00623678 [1]=0x00623528 [2]=0x006233D8 [3]=0x00623288
playersSelections[1]   [0]=0x00623678 [1]=0x00623288 [2]=0x00623528 [3]=0x006233D8
```

`clientSelectionGroup` is in strict descending pointer order — i.e. rebuilt from scratch and
ordered by position in the unit array. `playersSelections[1]` keeps the two already-selected
units first, in their original selection order, then appends the new ones — an append-if-absent
update, consistent with the 12-bounded de-duplication scan over `playersSelections[player]`
described in `binary-selection-map.md` §6.

**`activePlayerSelection` follows the client copy, not `playersSelections`.** It matched
`clientSelectionGroup` exactly — element for element and order for order — on every in-game
sample, including the lagging one, despite `activePlayerSelection` and `playersSelections` being
physically adjacent (`0x006284B8 + 12×4 == 0x006284E8`, §3.3 of the map). Adjacency in memory is
not kinship in behaviour.

It does **not** follow it during teardown: §3.4's final sample has `clientSelectionGroup` zeroed
while `activePlayerSelection` still holds all four pointers. So "these two always agree" is true
during play and false during shutdown — the same caution as §3.4 applies.

`clientSelectionGroup2` (`0x0059724C`) tracked `clientSelectionGroup` exactly throughout.

### 3.7 `selectionIterator` did nothing

`0x006284B6` read `0` on every sample — before, during and after all three transitions.

Stated honestly: **this does not show it is unused.** The observer samples at 250 ms, so a value
set and cleared inside a single function call is invisible to it. The only supported claim is
that it is `0` whenever nobody is mid-operation. Settling this needs a breakpoint or a hook, not
a poller.

### 3.8 The three player-id globals really are distinct

`binary-selection-map.md` §7 note 7 warns that three distinct player-id globals are in play in
this subsystem and that conflating them produces bugs. The log caught them **actually
disagreeing**, transiently, during the transition into the game:

```
[08:35:46.659] player=8/0/8     <- 0x00512688 updates first; the other two still 8
[08:35:48.210] player=1/1/1     <- all three settle
```

(`8` is the no-active-player value seen at the menu.) In steady state in-game all three read `1`.
The warning is correct and now has live evidence behind it.

Also worth stating plainly, because it is an easy way to write a wrong test: **the active player
was `1`, not `0`.** Code that indexes `playersSelections[0]` out of habit would have read an
empty row and concluded the array was wrong.

---

## 4. Prior-research disagreement: `launch-baseline.md`'s windowed-mode recipe is wrong

This is the most valuable thing found on the way, and it is a correction to already-merged
research, so it is reported plainly.

### What the merged document says

[`launch-baseline.md`](launch-baseline.md) § "Windowed mode" gives a **"tested recipe"**: copy
`WMode.dll` to `ddraw.dll` next to `StarCraft.exe`, because `storm.dll` resolves `ddraw.dll`
through `LoadLibraryA` and the application directory is searched first. It reports the result as
working, with this as the headline evidence:

> The desktop resolution **did not change** (stayed at native 3840x2160 the whole time).
> […] This is the actual evidence that the DirectDraw exclusive-mode path is being intercepted
> rather than a guess.

### What actually happens

| run | `ddraw.dll` in game dir | our plugin | result |
|---|---|---|---|
| 1 | absent | injected | launches, renders, **reaches the main menu**, v1.16.1 on screen |
| 2 | `WMode.dll` | injected | **DirectDraw error dialog**; no game |
| 3 | `WMode.dll` | **absent** | **same DirectDraw error dialog** |
| 4 | `WMode_Fix.dll` | absent | no dialog, but the window stays minimized at the `-32000` sentinel; no visible game |
| 5 | absent | injected, **plus `WMode.dll` early-injected** | **real 650×517 window, desktop unchanged, game renders** |

The dialog reads *"StarCraft was unable to initialize your video card using DirectX"*, and names
`ddraw_PC.cpp` line 113 `DirDrawInitBase`, with the Win32 detail **"The specified procedure could
not be found"** — that is `ERROR_PROC_NOT_FOUND`, i.e. a failed `GetProcAddress`.

**Run 3 is the decisive one**: the plugin is not present, so nothing of ours is involved.

### Why the recipe cannot work

`launch-baseline.md` records the cause in its own text without drawing the conclusion:

> Both `WMode.dll` and `WMode_Fix.dll` have **no export table**

`storm.dll` calls `LoadLibraryA("ddraw.dll")` and then resolves entry points **by name**. A DLL
with no export table can satisfy the `LoadLibraryA` but not the `GetProcAddress`, so DirectDraw
initialisation fails at exactly the point the error names. Dropping an export-less DLL into the
`ddraw.dll` slot cannot work, on any machine.

### Why the evidence was misread

"The desktop resolution did not change" was taken as proof that the exclusive-mode path had been
intercepted. It is equally consistent with **DirectDraw never having initialised at all** — which
is what was happening. The two hypotheses predict the same measurement, so that measurement
cannot distinguish them. The observation was accurate; the inference from it was not. The
document also reports the window arriving minimized at `-32000,-32000`, which in hindsight is the
game failing to come up rather than a quirk to be restored past.

### What does work

`WMode.dll` has no exports and `WMode_Fix.dll` imports `FindWindowA`. That is not the shape of a
DirectDraw proxy — it is the shape of a DLL meant to be **injected** into the process and to find
the game window itself. `launch-baseline.md` noticed this about `WMode_Fix.dll` and left it as an
open follow-up.

Injecting `WMode.dll` into the still-suspended process, before `ResumeThread`, works
(run 5 above):

```powershell
./tools/plugin/run-with-plugin.ps1 -InjectWindowedHelper WMode
```

```
scinject: early-injected C:\decompile-sc-data\sc-work\1161-base\WMode.dll -> HMODULE 0x10000000
check-game-windows: pid=26952  top-level windows=3
  hwnd=0x043507C8 class='SWarClass' visible=True rect=1595,784-2245,1301 style=0x94000000 title='Brood War'
check-game-windows: OK — no error dialogs
```

- desktop stayed at **3840×2160**;
- the game is a **real 650×517 window** (640×480 client) — not borderless-fullscreen, not
  minimized;
- no error dialog;
- **`ddraw.dll` is absent from the game directory** — nothing is written into it at all.

So the corrected recipe is strictly better than the one it replaces: windowed mode now costs zero
files in the game directory, and the working copy stays byte-identical to pristine.

### Corrections owed to `launch-baseline.md`

1. The `ddraw.dll`-swap recipe is **wrong**, not mis-executed. It should be replaced by early
   injection.
2. "Desktop resolution did not change" is **not** evidence of interception on its own.
3. The `WMode_Fix.dll` follow-up note was pointing the right way and should have been followed.

`launch-baseline.md` is not edited by this task — the correction belongs with the evidence that
produced it, and rewriting merged research from a different task's branch would hide the
disagreement rather than record it.

---

## 5. Method, and what this does *not* show

**How the reads are made.** `SafeRead()` `VirtualQuery`s each target address first and copies only
if the whole requested range lies inside a single committed, non-guard, readable region. A wrong
offset therefore shows up as a missing `ok` bit in the log rather than as an access violation
inside the game. Nothing in the DLL writes to game memory; the only writes it performs at all are
appends to its own log file.

**Sampling, not tracing.** The observer polls at 200–250 ms and logs only when the snapshot
changes. It therefore sees the *state* of the selection arrays, not the sequence of writes that
produced it. A transient value that appears and disappears inside one poll interval is invisible
to it. For rung 1 — "do these addresses hold the selection?" — sampling is sufficient; for rung 2,
which intercepts selection input, it will not be.

**One machine, one build.** Windows 11 26200, `StarCraft.exe` SHA-256
`AD6B58B27B8948845CCFA69BCFCC1B10D6AA7A27A371EE3E61453925288C6A46` (the hash
`tools/make-working-copy.ps1` verifies on every sync).

**A human drove the game, not the harness.** Automating the three selections through synthetic
mouse input was attempted first and abandoned: the injected pointer landed at screen `1228,1544`
when it was aimed at `1818,935`, so the absolute-coordinate normalisation was wrong for this
display and no click ever reached the game. The selections were then performed by hand. This does
not weaken the result — who moves the mouse is irrelevant to whether the values read from memory
match the screen — but it does mean **there is no scripted end-to-end reproduction of §3**. A
future run needs a human at the keyboard, or a fixed input path.

**Not shown by this task**: anything about *writing* to these arrays, about the 12-unit cap
itself, or about what happens when more than 12 units are selected by other means. This rung was
read-only by design.

**More than 12 units was not tested.** A 36-Marine test map (`Maps\test-many-units.scx`, task
009) exists but was not loaded — the game session was already closed, and driving the menus to
load it is exactly the thing that did not work. Every count observed here is ≤ 4. Nothing in this
document says anything about behaviour at or past the cap.

---

## 6. The game still works, and there is nothing to uninstall

**With the plugin loaded**, the user played a real single-player melee game: menus, map load,
unit selection, all normal. That is the strongest available evidence for "remains fully playable"
— it is not a launch-and-look-at-the-menu check, it is someone playing.

**Windowed mode works** with the plugin loaded (§4, run 5) and the desktop resolution is left
alone.

**Uninstall is a no-op, and that is verifiable rather than asserted.** The plugin is never copied
into the game directory; `scinject.exe` loads it from wherever it was built. After every test in
this task, the working copy differs from the pristine install by exactly one file — and that file
belongs to task 009, not to this one:

```
pristine files: 242   working copy files: 243
--- present in working copy but NOT pristine ---
  + Maps\test-many-units.scx
--- missing from working copy ---
  (none)
```

`ddraw.dll`, `scplugin.dll`, `scinject.exe`: none present in the game directory.

A **control run** confirms the uninstalled state behaves normally — same launcher, windowed, our
observer deliberately not injected (`run-with-plugin.ps1 -NoPlugin`):

```
scinject: --no-plugin, our observer was NOT injected (control run)
check-game-windows: pid=8892  top-level windows=3
  hwnd=0x00F0053C class='SWarClass' visible=True rect=1595,784-2245,1301 style=0x94000000 title='Brood War'
check-game-windows: OK — no error dialogs
scplugin loaded: 0
```

It reached the main menu and rendered normally, with `scplugin.dll` absent from the module list.

**Clean unload.** Closing the game with `WM_CLOSE` exited it cleanly and the DLL's
`DLL_PROCESS_DETACH` ran — `DETACH pid=26952` is the last line of the log. The plugin does not
have to be force-killed out of the process.

---

## 7. Housekeeping

- **Pristine install.** Nothing in this task wrote to `C:\decompile-sc-data\sc-install\Starcraft`. It was read
  twice, both times read-only and both times for verification: by
  `tools/make-working-copy.ps1`, which uses it as the `robocopy` source and hash-verifies it, and
  by a directory listing (file names only, no contents) to produce the diff in §6. Stated
  explicitly because the task's hard rule 1 says "never modify or even read from" it — the
  listing is a read, it was done deliberately to prove non-modification, and it is disclosed
  here rather than glossed over. The source-side hash check passed on every run
  (`[source] StarCraft.exe sha256 OK`, `[source] storm.dll sha256 OK`).
- **Working copy.** Verified by `tools/make-working-copy.ps1 -Force`: 242 files, 1,068.5 MB, both
  key-binary hashes matching. One caution learned the hard way: `/MIR` purges *everything* not in
  the pristine install, and it removed the user's freshly-created player profile
  (`characters\asdf.spc`), their replay, and another task's scratch map. The working copy is a
  shared resource; a reset is not free.
- **No game process left running.** Verified after every launch.
- **No game content committed.** Logs live under `C:\decompile-sc-data\sc-work\logs\` (outside the repo;
  `C:/decompile-sc-data/sc-work/` is gitignored) and only excerpts appear here. Screenshots taken during testing
  were used for verification and are deliberately **not** committed or attached to the PR: they
  reproduce game artwork, which project hard rule 1 forbids. Built binaries are likewise not
  committed (`.gitignore` blocks `*.dll`/`*.exe`).
- **Offline, single-player only.** No Battle.net, no multiplayer, no CD key, at any point.
