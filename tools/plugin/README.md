# StarCraft 1.16.1 plugin — observer (008), command fan-out (011), selection circles (014)

Our own code, running inside StarCraft 1.16.1.

**Task 008** built the read-only half: it reads the selection state at runtime to prove that the
addresses in [`research/binary-selection-map.md`](../../research/binary-selection-map.md) — all
verified *statically* — also hold in a live process. Findings:
[`research/runtime-selection-observations.md`](../../research/runtime-selection-observations.md).

**Task 011** added the part that writes: hooks that capture the player's selection *before* the
engine truncates it to 12, and fan a single order out into several `Select(≤12)`+order pairs so
every unit obeys. Design evidence: [`research/command-path.md`](../../research/command-path.md).

**Task 014** made those extra units *look* selected: it attaches the engine's own selection-circle
image to every unit the cap threw away, so 24 box-selected units show 24 circles instead of 12.
Design evidence: [`research/selection-circles.md`](../../research/selection-circles.md).

| | |
|---|---|
| Plugin | `scplugin.dll` — 32-bit, injected into StarCraft.exe |
| Injector | `scinject.exe` — 32-bit launcher; starts the game and injects |
| Detour test | `hooktest.exe` — offline unit test for the hook engine; no game involved |
| Files added to the game directory | **none** by the injection path — the deprecated [`-Windowed`](#windowed-mode-injected-not-proxied) switch is the one exception, and it writes `ddraw.dll` |
| Writes to `StarCraft.exe` on disk | **never**, in any mode |
| Writes to game *memory* | **only** in `-Mode hooktest/shadow/fanout`; never in the default `observe` |

---

## Modes, and the off switch

`%SCPLUGIN_MODE%` (set by `run-with-plugin.ps1 -Mode`) decides what the plugin is allowed to do.
Unset, misspelled or unrecognised means `observe`, so the plugin is passive unless something
explicitly asks for more.

| mode | hooks installed | behaviour change | what it is for |
|---|---|---|---|
| `observe` **(default)** | none | none — no byte of game memory is written | the task-008 observer, and the **off switch** |
| `hooktest` | 1 (`queueCommand`) | none; logs `CMD id=0xNN len=N` for every outgoing command | proves a hook fires, and names command ids |
| `shadow` | 4 | none; logs the pre-cap selection | proves the >12 capture without touching gameplay |
| `fanout` | 5 (4 with `-Circles 0`) | orders reach every captured unit, **and every captured unit gets a selection circle** | the feature |

**Three independent off switches**, in increasing order of bluntness:

1. `-Mode observe` (or just not setting `%SCPLUGIN_MODE%`) — the plugin loads and writes nothing.
2. Do not inject: `run-with-plugin.ps1 -NoPlugin`, or launch
   `C:\sc-work\1161-base\StarCraft.exe` directly. The game directory contains nothing of ours.
3. Unload the DLL — `DLL_PROCESS_DETACH` un-splices every hook and restores the original bytes.
   **Unloading mid-game is unsupported, and it leaves task 014's circles on screen.** Everything in
   `sc_circles.cpp` is game-thread-only; taking the circles off from the unloader's thread would
   mutate the sprite overlay list and the image free list while the game thread renders from them.
   The leftovers are self-healing, not permanent — the engine's own unit-removal path frees the
   circle on death, and `0x00497620` frees it the next time that unit is selected and deselected.
   Off switch 1 or 2 is what you want; this one is for a process that is going away anyway.

There is nothing to uninstall in any case: `StarCraft.exe` on disk is never modified, so its
SHA-256 is unchanged before and after every run.

---

## Fan-out: how it works

Three hooks, one funnel. Full derivation in
[`research/command-path.md`](../../research/command-path.md).

1. **`sortOverflowHandler` (`0x0046F040`)** is called by the engine once for every unit that
   passed every selection filter and did not fit in the 12 slots. It is the only place the units
   the cap is about to discard exist individually. The hook records them — and snapshots the
   12-slot output array on every call *before* the original runs, because that handler can also
   **evict** an already-stored unit, and the evicted one would otherwise vanish from both the
   output and our record.
2. **`CMDACT_Select` (`0x004C0860`)** is the client's selection commit point, handed the engine's
   final (truncated) list. The hook takes that as the *visible* selection, unions it with whatever
   the overflow hook accumulated since the last commit, and clears the accumulator. Hooking the
   function rather than the wire matters: the engine emits `0x0B`+`0x0A` deltas as often as a full
   `0x09`, but the function's argument is always the whole new selection.
3. **`queueCommand` (`0x00485BD0`)** is the single funnel every outgoing command passes through.
   When the command is one we fan out and the captured list is bigger than 12, the hook
   **suppresses** the engine's own command and emits `ceil(overflow/12) + 1` `Select`+order pairs
   through the trampoline instead.

A fourth hook on `SortAllUnits` (`0x0046F0F0`) only logs how many units the box actually
contained; it changes nothing.

A drag box reaches all three, and so does a shift-add — the chain is traced end to end in
[`research/command-path.md`](../../research/command-path.md) §3.3:

```
drag box -> 0x0046FA40 -> SortAllUnits -> sortOverflowHandler (per unit past the cap)
                       -> selectMultipleUnitsFromUnitList -> CMDACT_Select -> queueCommand
```

**The visible chunk is emitted last.** `research/selection-cap.md` §7 costs fan-out as
`ceil(N/12)` pairs *plus one* `Select` to put back the selection the player can see, because each
`Select` replaces `playersSelections[player]` wholesale. Ordering the overflow chunks first and
the visible one last folds that restore into the final pair.

**Liveness (task 020).** Captured units are stored as (pointer, `CUnit+0xA5` uniqueness,
`CUnit+0x4C` owner). At emit time each one is re-checked before its tag is written into a
`Select`, and the check is **not** the uniqueness byte alone. It cannot be: `CUnit+0xA5` is
written by one instruction in the whole binary, inside the unit (re)init `0x004A0320`, so it moves
on slot **reuse** and *not* on **death** ([`research/selection-circles.md`](../../research/selection-circles.md)
§4.5). A unit killed a moment ago still carries the uniqueness we captured, so its tag passes the
receive side's check (`CMDRECV_Select` `0x004C2750` validates count / decode / uniqueness / dedup /
`id != 14` and nothing else) and `addUnitToSelectionSlot` `0x0049AF80` then dereferences its
sprite pointer, unguarded. The five terms, and why each one is there, are derived in
[`research/fanout-liveness.md`](../../research/fanout-liveness.md):

| term | catches | cost |
|---|---|---|
| `CUnit+0xA5` unchanged | the slot was recycled into a different unit | one byte compare |
| `CUnit+0x08` (hitpoints) `!= 0` | a **damage death** — the case `0xA5` cannot see | one dword compare |
| `CUnit+0x4C` (owner) unchanged | the unit changed hands (mind control) | one byte compare |
| `CUnit+0x0C` (sprite) `!= NULL` | the exact pointer the receive path dereferences | one compare |
| reachable in `playerUnitList[owner]` | **removal from play by any path** — trigger `RemoveUnit`, archon-consumed, the tail of a death | one bounded list walk **per fanned order**, not per frame |

Every tag that goes out is logged by `FANOUT select:`, and every unit refused a place by
`FANOUT stale drop:` with the reason and the fields the engine would have used — so an unattended
run can assert on the wire rather than on a counter. `%SCPLUGIN_FANOUT_LIVENESS%`
(`run-with-plugin.ps1 -Liveness 0`) restores the pre-task-020 gate; it is a **known-bad**
configuration that exists only to reproduce the defect on demand.

**Byte budget.** The replay format length-prefixes each frame's command block with a *single*
byte, so everything every player does in one frame must fit in 255 bytes. The plugin emits up to
`%SCPLUGIN_FANOUT_BUDGET%` (default 200) bytes of pairs per turn, never pushes past the engine's
own remaining turn-buffer room, and finishes the rest on the next command. A 36-unit selection is
3 pairs ≈ 141 bytes and never defers.

### Which commands get fanned out

**19 of the 58 opcodes the engine accepts**, chosen by one rule that is a fact about the engine
rather than a preference (task 015, full derivation in
[`research/command-opcodes.md`](../../research/command-opcodes.md), per-opcode table in
[`research/data/command-opcodes.tsv`](../../research/data/command-opcodes.tsv)):

> fan out a command **⟺** the engine's own handler applies it to **every** unit in the receiving
> player's selection, **and** the handler does not move the player's resources.

The first half is why fan-out preserves semantics: for such a command the engine already does the
thing to all twelve units it holds, so replaying it against the units the cap hid is the same
operation over more units. The second half is the safety margin — minerals and gas are
player-global, and a command that spends them is one the player issued once.

| | ids |
|---|---|
| fan out | `0x14` Right Click, `0x15` Targeted Order (Attack / Patrol / Move), `0x1A` **Stop**, `0x2B` **Hold Position**, `0x1B` `0x1C` `0x1D` `0x1E` `0x21` `0x22` `0x25` `0x26` `0x28` `0x2A` `0x2C` `0x2D` `0x2E` `0x36` `0x5A` |
| passthrough | everything else — 25 selection-independent ids, 11 that do nothing unless *exactly one* unit is selected (Train, Build, Research …), 3 that loop but move resources, and `0x54`, which the dispatcher does not accept at all |

The single-unit-gated ones are the trap worth knowing about: they are inert at twelve units, which
makes them look harmless to replay — but a fan-out chunk can be **one** unit long, so replaying
one would make it fire where the player's own selection never could.

Every command is also length-checked against the length the engine's dispatcher consumes for that
id (from the command-length table at `0x005005F8`); one that disagrees is passed through untouched
rather than replayed, because handing the receive loop an unexpected byte count would
desynchronise everything behind it in the same turn buffer.

`%SCPLUGIN_FANOUT_CMDS%` / `-FanoutCmds '14 15 1A'` replaces the set; the length check still
applies to whatever it names. The plugin logs `CMD id=0xNN len=N bytes=[…]` for every command, so
identifying an id still costs a single keypress in game.

---

## Selection circles: how they work

Full derivation in [`research/selection-circles.md`](../../research/selection-circles.md).

A selection circle in this engine is **not a flag the renderer consults** — it is a `CImage` with
draw function `0x0D` and an id in `0x231..0x23A` (ten sizes), linked into the sprite's overlay list.
Sprite flag `0x01` (at `CSprite+0x0E`, *not* `+0x06` as BWAPI's header says) is just the bookkeeping
bit that records one is attached.

So the plugin does not reimplement anything. It calls the engine's own primitives:

| | |
|---|---|
| attach | `0x004D7070(colourTable[player], 0x231)` with `EAX = CSprite*`, then `flags \|= 0x01` |
| detach | `0x004975D0` with `ECX = CSprite*` — the engine's own remove-just-the-circle |

**One extra hook, `CreateNewUnitSelectionsFromList` (`0x0049AE40`)**, the client's
"replace the whole selection" funnel (10 callers: the drag box, every click path, control-group
recall). Our circles come off at its **entry**, before the engine attaches its own — which is what
keeps the two sets disjoint at every instant.

### Why it never sets the "selected" flag

`CSprite::selectionIndex` (`+0x0B`) is read by four instructions in the binary, every one of them
using it as a `memmove` offset into a **12-entry stack array**:

- a value ≥ 12 makes the length negative and smashes a 48-byte stack buffer;
- a value ≤ 11 is in bounds but deletes a *different, genuinely selected* unit from the selection.

There is no safe value for a unit that is fan-out-selected but not engine-selected. All four readers
are gated on sprite flag `0x08` ("selected"), so the plugin **sets only flag `0x01`, never `0x08`,
and never writes `selectionIndex` at all** — the field is then never read for our units.
`hooktest.exe` part [8] asserts both invariants against fake sprites.

The visible cost: a shadow-selected unit gets a circle and **no health bar** (the bar is the other
half of the engine's attach, and its removal is gated on `0x08`). That is also a useful tell —
circle *with* a bar is one of the engine's 12, circle *without* is one of ours.

### Known limitations

| | |
|---|---|
| Passthrough orders | reach the visible ≤12 as in stock. That is the policy, not a gap — see "Which commands get fanned out" |
| Merge-shaped commands (`0x2A`, `0x5A`) | **are** fanned out, and the effect scales: they pair units of one type inside each chunk, so 24 units of the right type merge into 12 rather than 6. Same semantics per chunk, twice the effect overall |
| Per-unit costs scale with the unit count | a fanned-out command that costs the acting unit energy (`0x21`) or HP (`0x36`) spends it for every unit reached, which is what "the order applies to all of them" means. Nothing player-global is ever spent twice |
| Shift-add past 12 | the shift path goes through `combineSelectionsLists`, which the overflow hook does cover, but a shift-add re-commits through `CMDACT_Select`; whatever the engine ends up holding is what gets captured. Not tested |
| Control-group recall (`0x13`) | rebuilds the selection outside `CMDACT_Select`, so the captured list is **dropped** on seeing that command rather than fanned out stale |
| The HUD | still shows 12 wireframes. Not a bug: the engine's cap is never raised. **The on-screen circles no longer stay at 12** (task 014) — but the wireframe row is a fixed 12-slot dialog and is a separate job |
| Health bars | shadow-selected units get a circle and no health bar, deliberately — see "Selection circles" above |
| Sound | each emitted `Select` can trigger the selection sound |
| Recent-selection ring | each emitted `Select` pushes an entry into the engine's alt-click recent-selection groups |
| Replays | every emitted command is vanilla-shaped, so a replay still parses; but one human intent appears as several `Select`+order pairs, and a very large selection can still exceed the 255-byte frame block if the budget is raised |
| Multiplayer | never. Offline single-player only, per the project's hard rules |

---

## Toolchain (pinned)

There was no C++ compiler on this machine at all (`setup.ps1` reports no `cl`, no
`gcc`, no `clang`). The pin below is the one this task installed.

| | |
|---|---|
| Toolchain | MinGW-w64 GCC **16.1.0**, i686 (32-bit), POSIX threads, DWARF EH, msvcrt runtime |
| Distributor | [winlibs](https://winlibs.com/) standalone build by Brecht Sanders |
| Release tag | `16.1.0posix-14.0.0-msvcrt-r4` |
| Asset | `winlibs-i686-posix-dwarf-gcc-16.1.0-mingw-w64msvcrt-14.0.0-r4.zip` (283,287,220 bytes) |
| Download URL | https://github.com/brechtsanders/winlibs_mingw/releases/download/16.1.0posix-14.0.0-msvcrt-r4/winlibs-i686-posix-dwarf-gcc-16.1.0-mingw-w64msvcrt-14.0.0-r4.zip |
| SHA-256 | `a5817469f554314b03cd5298c0b247057d7a7da5b85a01d89d9fc9feb7adbc19` |
| Install path | `C:\re-tools\mingw32-gcc-16.1.0-i686-msvcrt\` — **outside every worktree** |
| Target triple | `i686-w64-mingw32` (`g++ -dumpmachine`) |

The SHA-256 above is GitHub's own `digest` field on the release asset; `build.ps1`
does not re-check it, the install step does.

### Why MinGW-w64 and not MSVC

- **It is pinnable.** A single zip with a published SHA-256, extracted to a fixed
  path — exactly the shape `tools/ghidra/README.md` already uses. MSVC Build Tools
  ship as a bootstrapping installer that resolves component versions at install
  time; "reproducible from the committed docs" is much harder to honour.
- **No installer, no admin, no license click-through.**
- **32-bit x86 is a first-class target** (`-m32`), which is the hard requirement:
  StarCraft.exe is `Machine = 0x014C` (`research/pe-anatomy.md`), so a 64-bit DLL
  simply cannot load into it.
- The plugin imports **only `KERNEL32.dll` and `msvcrt.dll`** (verified with
  `objdump -p`), both present on every Windows. Built with `-static
  -static-libgcc -static-libstdc++ -fno-exceptions -fno-rtti`, so there is no
  `libgcc_s_*.dll`/`libstdc++-6.dll` to ship alongside it and no C++ unwinder
  inside a foreign 1998-era process.

### Install (fresh machine)

```powershell
New-Item -ItemType Directory -Path C:\re-tools -Force | Out-Null
$zip = 'C:\re-tools\winlibs-i686-posix-dwarf-gcc-16.1.0-mingw-w64msvcrt-14.0.0-r4.zip'
Invoke-WebRequest -Uri 'https://github.com/brechtsanders/winlibs_mingw/releases/download/16.1.0posix-14.0.0-msvcrt-r4/winlibs-i686-posix-dwarf-gcc-16.1.0-mingw-w64msvcrt-14.0.0-r4.zip' -OutFile $zip
$h = (Get-FileHash $zip -Algorithm SHA256).Hash
if ($h -ne 'A5817469F554314B03CD5298C0B247057D7A7DA5B85A01D89D9FC9FEB7ADBC19') { throw "hash mismatch: $h" }
Expand-Archive -LiteralPath $zip -DestinationPath C:\re-tools\mingw32-gcc-16.1.0-i686-msvcrt
Remove-Item $zip
```

The zip's top-level folder is `mingw32/`, so the compiler lands at
`C:\re-tools\mingw32-gcc-16.1.0-i686-msvcrt\mingw32\bin\g++.exe` — which is
`build.ps1`'s default. Override with `-ToolchainBin` or `$env:SC_MINGW32_BIN`.

**The install must not live inside a worktree.** It is gitignored, so git cannot
see it, so pruning the worktree deletes it with no warning. That has already cost
this project once (task 005 lost Ghidra when task 001's worktree was pruned — see
`tools/ghidra/README.md`). `C:\re-tools\` is shared by every worker.

---

## Build

```powershell
./tools/plugin/build.ps1
```

No arguments needed, no paths baked in: the script resolves the repo root from
its own location and the toolchain from `-ToolchainBin` → `$env:SC_MINGW32_BIN` →
the documented default. Output goes to `work/scratch/plugin-build/` (gitignored —
`.gitignore` blocks `*.dll`/`*.exe` anyway; built binaries are never committed).

The exact compile is:

```
g++ -m32 -Wall -Wextra -static -static-libgcc -static-libstdc++ -fno-exceptions -fno-rtti -O2 -s \
    -shared src/scplugin.cpp src/sc_log.cpp src/sc_hook.cpp src/sc_fanout.cpp \
    -o scplugin.dll -I src
g++ ...same flags...    src/scinject.cpp  -o scinject.exe
g++ ...same flags...    src/hooktest.cpp src/sc_log.cpp src/sc_hook.cpp -o hooktest.exe   # -Test only
```

### `-Test`: prove the detour engine before it touches the game

```powershell
./tools/plugin/build.ps1 -Test
```

builds and **runs** `hooktest.exe`, and fails the build on a non-zero exit. The detour engine is
the one piece that writes executable memory inside a foreign process, and the only place a bug in
it shows up is a user's single hand-driven test run — so it is proved here first, against three
throwaway functions whose prologues are hand-written to match the three real StarCraft ones byte
for byte:

```
55 8B EC 51 A1 <abs32>   9 bytes, 4 instrs  -- queueCommand shape (fastcall)
55 8B EC 83 EC 5C        6 bytes, 3 instrs  -- CMDACT_Select shape (stdcall, RET 8)
55 8B EC 53 56           5 bytes, 4 instrs  -- sortOverflowHandler shape (EAX/ECX + stack, RET 8)
```

30 checks: baseline behaviour, that a mismatched prologue is refused, that all three install, that
the detours run while the trampolines still compute the original results, that the
register-convention thunk sees EAX/ECX *and* the stack arguments, that 200 consecutive calls keep
the stack balanced, and that removal restores the originals exactly. No StarCraft file is opened
and the game is not launched.

> The very first run of this test failed, usefully: GNU as assembles `mov %esp,%ebp` as `89 E5`
> while StarCraft's VC6-era build uses `8B EC`, and the prologue check refused to patch. That is
> the check doing its job on a one-byte encoding difference.

`build.ps1` then **fails the build** unless both artifacts read
`Machine = 0x014C` and optional-header magic `0x010B` (PE32), parsed straight out
of the file bytes. This is not ceremony: if `-m32` ever silently produced an x64
image, the only symptom would be "the DLL will not load" discovered much later,
inside the game, with nothing pointing at the cause.

```
verify: scplugin.dll   Machine=0x014C  OptMagic=0x010B  DLL
verify: scinject.exe   Machine=0x014C  OptMagic=0x010B  EXE
```

`-DebugBuild` swaps `-O2 -s` for `-O0 -g`.

---

## Injection design, and why

### Chosen: launcher + `CreateRemoteThread(LoadLibraryA)`

`scinject.exe <game-exe> <plugin-dll>`:

1. `CreateProcessA(..., CREATE_SUSPENDED, workingDir = game dir)` — suspended only
   so the pid is known before a single instruction runs.
2. `ResumeThread`, then `WaitForInputIdle` plus a settle wait, so the game has
   finished loading its own modules (`storm.dll`, `ddraw.dll`, …).
3. `VirtualAllocEx` + `WriteProcessMemory` of the DLL path.
4. `CreateRemoteThread` at `kernel32!LoadLibraryA`. Injector and target are both
   32-bit, so `LoadLibraryA`'s address in our own kernel32 is valid in the target.
5. Read the remote thread's exit code — that is the `HMODULE`, and a `0` there is
   a hard failure rather than a silent no-op.

**Failure policy: never leave a game process behind.** Every exit path after
`CreateProcess` goes through one `Bail()` helper that terminates the game if it
is still alive and closes both handles. `ResumeThread`'s return value is checked,
because an unchecked failure there leaves `StarCraft.exe` *suspended forever*,
holding the working copy, while the injector exits 0. A failed late injection
also terminates rather than leaving the game running unobserved — the caller is
going to report a failed run either way, and a half-launched game the caller has
no handle on is worse than none.

| `scinject.exe` exit | meaning |
|---|---|
| `0` | launched and injected |
| `1` | bad arguments, missing file, or a path under `C:\sc-install` |
| `2` | a Win32 call failed before the process existed |
| `3` | the game exited on its own before injection |
| `4` | late injection failed — game terminated |
| `5` | `--early-dll` injection failed — game terminated |
| `6` | `ResumeThread` failed — game terminated rather than left suspended |

Injecting *after* init rather than into a never-run process is deliberate. A
passive observer gains nothing from being present before the entry point, and
`CreateRemoteThread` into a process whose loader has not initialised is the
fragile variant of this technique.

### Rejected: proxy `ddraw.dll`

`research/launch-baseline.md` established that `storm.dll` resolves `ddraw.dll`
through `LoadLibraryA`, so a `ddraw.dll` next to `StarCraft.exe` gets picked up by
the application-directory-first search order. It is a proven load vector. It was
still the wrong choice here:

1. **It is a single slot, and windowed mode wants it too.** Taking it means
   chain-loading correctly forever after; getting that wrong breaks rendering.
2. **There is nothing clean to chain to on the windowed-mode side.**
   `launch-baseline.md` records that `WMode.dll` has *no export table*, so a proxy
   cannot forward exports to it — only `LoadLibrary` it and hope its `DllMain`
   hooks at the right moment, from inside our own `DllMain`, under the loader lock.
3. **It puts a file in the game directory**, so "clean uninstall" becomes a step
   that can be forgotten or half-done.
4. **It buys nothing we need.** We are not hooking DirectDraw; we just want code
   in the process.

The launcher vector has none of those properties: the `ddraw.dll` slot stays
completely free, and the game directory is not modified by anything on this path.
(The deprecated `-Windowed` switch still performs the rejected `ddraw.dll` swap —
it is kept only so the failure stays reproducible, and it is the sole thing in
this tool that writes into the game directory.)

### Windowed mode: injected, not proxied

`research/launch-baseline.md`'s recipe — copy `WMode.dll` in as `ddraw.dll` —
**does not work**, on this or any machine: `storm.dll` resolves entry points from
`ddraw.dll` by name, and `WMode.dll` has no export table, so `GetProcAddress`
fails and DirectDraw never initialises. Full evidence, including a run with our
plugin absent that reproduces the same failure, is in
[`research/runtime-selection-observations.md`](../../research/runtime-selection-observations.md) §4.

What does work is injecting it, which is what a DLL with no exports and a
`FindWindowA` import is shaped for:

```powershell
./tools/plugin/run-with-plugin.ps1 -InjectWindowedHelper WMode
```

That passes `--early-dll <gamedir>\WMode.dll` to the injector, which loads it into
the **still-suspended** process before `ResumeThread` — so its `DllMain` hooks
before DirectDraw initialises. Result: a real 640×480-client window, the desktop
resolution untouched, no error dialog, and **still nothing written into the game
directory**.

This is why the launcher vector was worth having beyond our own plugin: the same
mechanism that gets our observer in also fixes windowed mode, and neither costs a
file in the game folder.

---

## Run

```powershell
# build + launch the working copy, windowed, read-only observer (writes nothing)
./tools/plugin/run-with-plugin.ps1 -Build -InjectWindowedHelper WMode

# the feature: fan one order out over more than 12 units
./tools/plugin/run-with-plugin.ps1 -Mode fanout -InjectWindowedHelper WMode `
    -LogPath C:\sc-work\logs\fanout.log

# options
./tools/plugin/run-with-plugin.ps1 -PollMs 100 -LogPath C:\sc-work\logs\run.log
./tools/plugin/run-with-plugin.ps1 -NoPlugin -InjectWindowedHelper WMode   # A/B control

# never leave a game process running (hard rule); WM_CLOSE so DETACH/STATS get written
./tools/plugin/close-game.ps1
```

| flag | what |
|---|---|
| `-Mode observe\|hooktest\|shadow\|fanout` | what the plugin may do. **Default `observe` — read-only, the off switch.** See "Modes" above |
| `-InjectWindowedHelper WMode\|WMode_Fix\|both` | early-inject the windowed-mode helper (see above) |
| `-NoPlugin` | launch through this exact path with our observer **not** injected — the control that tells you whether a symptom is ours, and the demonstration of the uninstalled game |
| `-PollMs`, `-LogPath` | observer poll interval and log destination |
| `-LogCommands 0\|1` | log every outgoing command id (default 1) |
| `-FanoutBudget <bytes>` | per-turn byte budget for emitted pairs (default 200; the replay frame block is 255) |
| `-FanoutCmds '14 15 1A'` | replace the set of command ids that get fanned out |
| `-Circles 0\|1` | task 014's selection circles under the over-cap units (default 1; only meaningful in `-Mode fanout`). `0` is the feature's own off switch and drops the hook count from 5 to 4 |
| `-Liveness 0\|1` | task 020's emit-side liveness gate (default **1**). `0` restores the pre-020 uniqueness-only test and will replay a dead unit's tag into a `Select` — a **defect-reproduction** switch, not an off switch; the launcher prints a warning when it is used |
| `-Windowed` / `-RemoveWindowed` | the **old** `ddraw.dll`-swap recipe and its undo. Kept only so the failure is reproducible; it does not work — use `-InjectWindowedHelper` |
| `-WaitForExit` | block until the game exits instead of returning |

Defaults: game `C:\sc-work\1161-base` (the disposable working copy), log
`C:\sc-work\logs\sc-plugin.log`, poll 250 ms.

**The pristine install is guarded on the canonical path, not on how it was
spelled.** `-GameDir` is first canonicalised — `/` → `\`, `\\?\` and `\\.\`
device prefixes stripped, `.`/`..` resolved, 8.3 short names expanded, symlinks
and junctions followed — and the run is refused if the result is at or under
`C:\sc-install`. Everything afterwards uses that canonical path, so the guard
cannot test one spelling while `Copy-Item`/`Remove-Item` act on another. All of
`C:\sc-install\Starcraft`, `C:/sc-install/Starcraft`, `\\?\C:\sc-install\x` and
`C:\sc-work\..\sc-install` are rejected. `scinject.exe` carries the same check
independently, so calling the injector by hand does not get past it.

After injecting, the script runs `check-game-windows.ps1` **against the pid
`scinject.exe` printed** (`scinject: PID=<n>`), which enumerates that process's
top-level windows from outside and fails the run if a modal dialog (window class
`#32770`) is open. A StarCraft launch can fail with the process still alive and
an error box on screen; exit codes alone cannot see that. The pid is passed
explicitly because resolving by process name would throw whenever any other
StarCraft happens to be running — after a launch that in fact succeeded.

```powershell
./tools/plugin/check-game-windows.ps1        # standalone; exit 1 == dialog open
```

### Log

`%SCPLUGIN_LOG%`, default `C:\sc-work\logs\sc-plugin.log`. Outside the repo, and
`C:/sc-work/` is gitignored — captured game state is never committed (project hard
rule 1). `%SCPLUGIN_POLL_MS%` sets the poll interval (default 250, clamped 20–5000).

`%SCPLUGIN_MARKER%` (default `marker.txt` beside the log) is a correlation channel:
write a one-line label into that file and the observer stamps
`---- MARK: <label> ----` into the log between snapshots. Timestamps alone are
ambiguous at 250 ms granularity when you are trying to line "what I did on screen"
up with "what the log says". It is a read of a file the observer owns — not a hook
into, or a write to, the game.

The log is written **only when the observed state changes**, so quiet stretches are
normal. The 60-second `HEARTBEAT` line is the liveness signal.

Attach banner, then one block per observed change:

```
ATTACH pid=21392 tid=30764
  host exe      : C:\sc-work\1161-base\StarCraft.exe
  module base   : 0x00400000
  preferred base: 0x00400000
  reloc delta   : +0x00000000  => static addresses are USABLE VERBATIM
  image[0..1]   : 0x5A4D ('MZ' - mapped image confirmed)
OBSERVER start pollMs=250 (read-only; no writes to game memory)
SEL count=0 nonNullGroup=0 iter=0 player=8/8/8 ok=0x2F
    clientSelectionGroup   (none)
    activePlayerSelection  (none)
    playersSelections[8]   (none)
    clientSelectionGroup2  (none)
```

`ok` is a bitmask of which reads succeeded — `0x01` count, `0x02`
clientSelectionGroup, `0x04` clientSelectionGroup2, `0x08` activePlayerSelection,
`0x10` playersSelections row, `0x20` the player-id globals. A missing bit means
`SafeRead` refused the address, not that the value was zero. `player=a/b/c` is the
three distinct player-id globals `0x0051267C` / `0x00512688` / `0x00512678`, logged
separately because `binary-selection-map.md` §7 warns that conflating them produces
bugs.

## Uninstall

**Nothing to uninstall.** The plugin is never copied into the game directory; it is
loaded from wherever it was built. Launch `C:\sc-work\1161-base\StarCraft.exe`
directly and the game is a stock, unmodified 1.16.1 client. Verified: after all
testing, the working copy differed from the pristine install by exactly one file —
`Maps\test-many-units.scx`, which belongs to task 009, not to this task (242
pristine files vs 243 in the working copy; see
`research/runtime-selection-observations.md` §6). Nothing this task added remained.

The one exception is the deprecated `-Windowed` switch, which *does* write
`ddraw.dll` into the game directory. Remove it with `-RemoveWindowed`, or reset:

```powershell
./tools/make-working-copy.ps1 -Force     # ~3s, robocopy /MIR + hash verify
```

> **`-Force` is a `/MIR`, so it purges everything not in the pristine install** —
> including player profiles, replays, and any test map another task generated. It
> is not a free operation on a shared working copy.

---

## Source layout

| file | what |
|---|---|
| `src/sc_addresses.h` | the static VAs, each with its provenance in `research/` |
| `src/scplugin.cpp` | `DllMain`, the read-only observer — `SafeRead`, snapshot, log |
| `src/sc_log.h/.cpp` | the shared log file and its lock |
| `src/sc_hook.h/.cpp` | the inline-detour engine — prologue check, trampoline, thread suspension |
| `src/sc_fanout.h/.cpp` | the shadow selection and the fan-out |
| `src/sc_circles.h/.cpp` | task 014's selection circles: one hook, two engine calls, and the reasoning for never touching `selectionIndex` |
| `src/hooktest.cpp` | offline unit tests for the detour engine, the fan-out core and the circles (`build.ps1 -Test`) |
| `src/scinject.cpp` | the 32-bit launcher/injector |
| `build.ps1` | build + PE machine-type gate (+ `-Test`) |
| `run-with-plugin.ps1` | launch wrapper (+ windowed shim helper, + dialog check, + `-Mode`) |
| `drive-game.ps1` | posted-window-message driver: find the HWND, click, drag, type, capture a frame. No synthetic OS input, no screen coordinates |
| `test-selection-circles.ps1` | **unattended** end-to-end test: launches, walks the menus, loads a stock map, drives a drag box and an order, asserts on the plugin log |
| `test-fanout-orders.ps1` | **unattended** end-to-end test of the per-opcode policy: Stop and Hold Position reach all 24 units of a >12 selection, asserted from every unit's own order byte, not from the picture |
| `test-burrow-fanout.ps1` | **unattended** end-to-end test of an untargeted ABILITY: generates a 36-Lurker Use-Map-Settings map, boxes it, presses Burrow once, asserts `burrowed` goes 0/36 → 36/36 from each unit's own flags. Deletes the map afterwards |
| `test-stim-fanout.ps1` | **unattended** end-to-end test of an ability with a PER-UNIT COST (task 022): 36 Marines, 24 healthy and 12 pre-damaged to exactly the gate value, one Stim press — every unit's effect state AND hit points read per unit. Also proves the cost cannot kill |
| `test-ability-in-combat.ps1` | **unattended** PLUGIN-vs-STOCK test (task 022): >12 units mid-fight, one ability keypress, every unit's order compared across it. Answers "do our replayed Selects interrupt orders that are already running" |
| `test-sunken-acquire.ps1` | **unattended** PLUGIN-vs-STOCK test (task 022): does a Sunken Colony attack a Medic that walks into range? Same map in both modes, plus a Marine arm as the control that the Sunken can shoot from there at all |
| `check-game-windows.ps1` | out-of-process launch health check |
| `close-game.ps1` | WM_CLOSE the game and verify it exited (hard rule: never leave one running) |

### Testing it without a human

```powershell
./tools/plugin/test-selection-circles.ps1            # circles on
./tools/plugin/test-selection-circles.ps1 -NoCircles # the off-switch run
./tools/plugin/test-fanout-orders.ps1                # Stop / Hold / Attack / Patrol at >12
./tools/plugin/test-burrow-fanout.ps1                # Burrow (an untargeted ABILITY) at 36
./tools/plugin/test-stim-fanout.ps1                  # Stim at 36: the EFFECT and the per-unit COST
./tools/plugin/test-ability-in-combat.ps1            # plugin vs stock: an ability used mid-fight
./tools/plugin/test-sunken-acquire.ps1               # plugin vs stock: does a Sunken shoot a Medic
```

`test-burrow-fanout.ps1` is the one that needs no stock map: no `.scm`/`.scx` Blizzard shipped can
put more than twelve same-type units with an ability button on one screen
([`research/command-opcodes.md`](../../research/command-opcodes.md) §8), so it **generates** its
fixture with `tools/make-test-map.ps1`, plays it, and deletes it. Two properties of that generator
are what make the map playable at all, and both were root-caused by task 016: the human slot's
race must be explicit rather than the ladder template's "User Selectable" (otherwise the engine
hands out melee starting units even under Use Map Settings), and the template's triggers must be
stripped (otherwise they end the game within seconds). See
[`tools/README-test-map.md`](../README-test-map.md).

`test-fanout-orders.ps1` adds a second oracle on top of the log: the plugin's `UNITSTATE` line,
which walks the **shadow list** — all 24 units, not the 12 the engine holds — and reports a
histogram of their current order ids read from `CUnit+0x4D`. The driver asks for one by writing a
label into the marker file and waiting for the line carrying that label back, so "every unit
obeyed" is a synchronous read of all 24 units' own state. The assertion that matters is the
negative one: after one Stop keypress, **not one** of the 24 is still on the order they were all
moving with. A command that only reached the engine's twelve would leave twelve still walking.

It drives the game with `PostMessage` and **client** coordinates in `lParam` — the technique task
012 demonstrated live
([`research/automated-testing-options.md`](../../research/automated-testing-options.md) §4.1).
Focus is not required; the
window must not be minimised. The oracle is the plugin's own log, because it is written from inside
the process. Frames are captured at every step into `-ShotDir` (default `C:\sc-work\logs\014-frames`,
outside the repo) as a **diagnostic only** — they reproduce game artwork and must never be committed.

It also asserts hard rule 3 rather than attesting to it: `StarCraft.exe` is SHA-256'd before launch
and after close and compared against the pristine 1.16.1 constant from `tools/make-working-copy.ps1`
both times.

The one thing it cannot assert is whether the circles are actually *drawn*: `CIRCLES show: N/N` only
proves the engine accepted the attach. Look at the `shadow-selection` frame for that.

**Aiming a click at one of the plugin's own circles** is possible because the plugin logs their
screen positions:

```
CIRCLES pos: 12 on screen of 12: 147,196 178,196 209,196 ...
```

client pixels, computed as the sprite's map position minus the viewport origin the game's own click
handler uses. Without it the >12 shift-click test cannot tell "clicked one of ours" from "clicked
one of the engine's" and has to accept either outcome.

### How memory is written safely

`sc_hook.cpp` is deliberately narrow:

- **No length disassembler.** The caller passes the exact number of whole instruction bytes to
  relocate, as a constant taken from a disassembly of *this* binary
  (`HookProbe.java` prints it, and prints whether any instruction in that window is PC-relative
  and therefore not relocatable). Guessing an instruction length inside a foreign process is the
  fastest way to corrupt it.
- **Prologue signature check.** The caller also passes the bytes it expects to find, and install
  *refuses* on any mismatch. A wrong address, a different build or an already-hooked target fails
  loudly instead of executing spliced garbage. The log records the bytes it found.
- **Allocate and re-protect before suspending threads.** `VirtualAlloc`/`VirtualProtect` take
  process-wide locks; taking one while another thread is suspended holding it would deadlock the
  game. Only the `memcpy` happens under suspension, and all four hooks go in under one suspension
  so a partially installed set is never observable.
- **All-or-nothing.** If fewer hooks install than the mode needs, the plugin rolls back and runs
  passive for that session rather than fanning out against a list nothing fills.
- **`force_align_arg_pointer` on every entry point the game calls.** GCC at `-O2` assumes a
  16-byte-aligned incoming stack and will emit aligned SSE spills on that assumption; StarCraft is
  a VC6-class build that guarantees 4. Without it a detour can fault on a `movaps` with no symptom
  but the game vanishing.
- **Trampolines are leaked on removal, on purpose.** Another thread may be executing inside one;
  64 bytes per hook once per process is strictly better than a use-after-free in the game.

### How addresses are used

Every constant in `sc_addresses.h` is a preferred-image-base VA. Nothing
dereferences one directly:

```c
runtime = GetModuleHandleA(NULL) + (staticVA - 0x00400000)
```

so a relocated load is handled rather than assumed away — and the delta is logged,
because "did it actually load at `0x00400000`?" is one of the questions this task
exists to answer.

### How reads are made safe

`SafeRead()` `VirtualQuery`s the target first and copies only if the whole range
sits inside one committed, non-guard, readable region. A wrong offset therefore
produces a log line with a missing `ok` bit instead of an access violation inside
the game. It only ever `memcpy`s *out* of the process — there is no code path in
this DLL that writes to game memory.
