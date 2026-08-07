# StarCraft 1.16.1 observer plugin (task 008, rung 1)

Our own code, running inside StarCraft 1.16.1, reading the selection state at
runtime. **Read-only**: it does not write to game memory, patch code, change page
protections, hook input, or alter behaviour in any way. Its whole job is to prove
that the addresses in [`research/binary-selection-map.md`](../../research/binary-selection-map.md)
— all of which were verified *statically* — also hold in a live process.

Findings from actually running it: [`research/runtime-selection-observations.md`](../../research/runtime-selection-observations.md).

| | |
|---|---|
| Plugin | `scplugin.dll` — 32-bit, injected into StarCraft.exe |
| Injector | `scinject.exe` — 32-bit launcher; starts the game and injects |
| Files added to the game directory | **none** |
| Writes to game memory | **none** |

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
g++ -m32 -Wall -Wextra -static -static-libgcc -static-libstdc++ \
    -fno-exceptions -fno-rtti -O2 -s -shared src/scplugin.cpp -o scplugin.dll -I src
g++ -m32 -Wall -Wextra -static -static-libgcc -static-libstdc++ \
    -fno-exceptions -fno-rtti -O2 -s        src/scinject.cpp  -o scinject.exe
```

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
completely free, and the game directory is never modified.

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
# build + launch the working copy, windowed, with the observer injected
./tools/plugin/run-with-plugin.ps1 -Build -InjectWindowedHelper WMode

# options
./tools/plugin/run-with-plugin.ps1 -PollMs 100 -LogPath C:\sc-work\logs\run.log
./tools/plugin/run-with-plugin.ps1 -NoPlugin -InjectWindowedHelper WMode   # A/B control
```

| flag | what |
|---|---|
| `-InjectWindowedHelper WMode\|WMode_Fix\|both` | early-inject the windowed-mode helper (see above) |
| `-NoPlugin` | launch through this exact path with our observer **not** injected — the control that tells you whether a symptom is ours, and the demonstration of the uninstalled game |
| `-PollMs`, `-LogPath` | observer poll interval and log destination |
| `-Windowed` / `-RemoveWindowed` | the **old** `ddraw.dll`-swap recipe and its undo. Kept only so the failure is reproducible; it does not work — use `-InjectWindowedHelper` |
| `-WaitForExit` | block until the game exits instead of returning |

Defaults: game `C:\sc-work\1161-base` (the disposable working copy — the script
**refuses** a path under `C:\sc-install`), log `C:\sc-work\logs\sc-plugin.log`,
poll 250 ms.

After injecting, the script runs `check-game-windows.ps1`, which enumerates the
game's top-level windows from outside the process and fails the run if a modal
dialog (window class `#32770`) is open. A StarCraft launch can fail with the
process still alive and an error box on screen; exit codes alone cannot see that.

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
testing, the working copy differed from the pristine install by zero files
(see `research/runtime-selection-observations.md` §6).

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
| `src/scplugin.cpp` | the observer DLL — `SafeRead`, snapshot, log |
| `src/scinject.cpp` | the 32-bit launcher/injector |
| `build.ps1` | build + PE machine-type gate |
| `run-with-plugin.ps1` | launch wrapper (+ windowed shim helper, + dialog check) |
| `check-game-windows.ps1` | out-of-process launch health check |

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
