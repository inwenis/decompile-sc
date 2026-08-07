# StarCraft 1.16.1 plugin — observer (task 008) and command fan-out (task 011)

Our own code, running inside StarCraft 1.16.1.

**Task 008** built the read-only half: it reads the selection state at runtime to prove that the
addresses in [`research/binary-selection-map.md`](../../research/binary-selection-map.md) — all
verified *statically* — also hold in a live process. Findings:
[`research/runtime-selection-observations.md`](../../research/runtime-selection-observations.md).

**Task 011** added the part that writes: hooks that capture the player's selection *before* the
engine truncates it to 12, and fan a single order out into several `Select(≤12)`+order pairs so
every unit obeys. Design evidence: [`research/command-path.md`](../../research/command-path.md).

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
| `fanout` | 4 | orders reach every captured unit | the feature |

**Three independent off switches**, in increasing order of bluntness:

1. `-Mode observe` (or just not setting `%SCPLUGIN_MODE%`) — the plugin loads and writes nothing.
2. Do not inject: `run-with-plugin.ps1 -NoPlugin`, or launch
   `C:\sc-work\1161-base\StarCraft.exe` directly. The game directory contains nothing of ours.
3. Unload the DLL — `DLL_PROCESS_DETACH` un-splices every hook and restores the original bytes.

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

**Staleness.** Captured units are stored as (pointer, `CUnit+0xA5` uniqueness). At emit time the
uniqueness byte is re-checked and a unit that no longer matches is dropped — the engine's own
staleness test for stored unit tags.

**Byte budget.** The replay format length-prefixes each frame's command block with a *single*
byte, so everything every player does in one frame must fit in 255 bytes. The plugin emits up to
`%SCPLUGIN_FANOUT_BUDGET%` (default 200) bytes of pairs per turn, never pushes past the engine's
own remaining turn-buffer room, and finishes the rest on the next command. A 36-unit selection is
3 pairs ≈ 141 bytes and never defers.

### Which commands get fanned out

**By default only two: `0x14` Right Click and `0x15` Targeted Order** — the only two ids whose
payload layout this project has read out of the binary. Between them they carry move, attack,
attack-move, patrol, gather, repair and every right-click.

`research/command-path.md` §6 tabulates all 51 ids the binary emits with their lengths, but does
**not** name 45 of them, and fanning out a command whose meaning is guessed is how a plugin ends
up quietly duplicating a build order. Extend the set with
`-FanoutCmds '14 15 1A'` once an id has been identified — the plugin logs `CMD id=0xNN len=N` for
every command, so identifying one costs a single keypress in game.

### Known limitations

| | |
|---|---|
| Orders other than `0x14`/`0x15` | not fanned out by default; the selection still works, the order just reaches the visible ≤12 as in stock |
| Whole-selection orders (archon merge, unload-all, building morph) | **not handled, and not attempted.** Their semantics depend on the entire selection at once, so splitting into 12-unit chunks would change what they mean — an archon merge chunked into threes merges the wrong pairs. They are not in the default id set, so they behave exactly as stock |
| Shift-add past 12 | the shift path goes through `combineSelectionsLists`, which the overflow hook does cover, but a shift-add re-commits through `CMDACT_Select`; whatever the engine ends up holding is what gets captured. Not tested |
| Control-group recall (`0x13`) | rebuilds the selection outside `CMDACT_Select`, so the captured list is **dropped** on seeing that command rather than fanned out stale |
| The HUD | still shows 12 wireframes. Not a bug: the engine's cap is never raised, and the on-screen selection circles stay at 12 |
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
| `src/sc_fanout.h/.cpp` | the shadow selection and the fan-out; the only code that writes to game memory |
| `src/hooktest.cpp` | offline unit test for the detour engine (`build.ps1 -Test`) |
| `src/scinject.cpp` | the 32-bit launcher/injector |
| `build.ps1` | build + PE machine-type gate (+ `-Test`) |
| `run-with-plugin.ps1` | launch wrapper (+ windowed shim helper, + dialog check, + `-Mode`) |
| `check-game-windows.ps1` | out-of-process launch health check |
| `close-game.ps1` | WM_CLOSE the game and verify it exited (hard rule: never leave one running) |

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
