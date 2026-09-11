# StarCraft: Brood War 1.16.1 mod

A 32-bit DLL injected into the game at launch. The game files on disk stay byte-identical;
every change is applied in memory. Offline and single-player only.

## New features

1. select more than 12 units, right click to page through
2. select buildings of one type, queue units for all at once
3. queue more than 5 units in a building
4. queue upgrades
5. widescreen (hold Ctrl or Right Alt to free the mouse)

![70 units selected on the 1280x800 playfield; the bottom row reads 70 units 1-12 (1/6)](docs/screenshot-70-units.png)

![63 units selected, mixed Zerg army, widescreen viewport](docs/screenshot-63-units.png)

## How to play it?

You need your own StarCraft: Brood War 1.16.1 install; nothing from the game is in this repo.
No 1.16.1 around? The [StarCraft Classic Installer & Downgrader](http://staredit.net/topic/17625/)
on staredit.net installs, or patches an install to, exactly that version.

Windows only. Once:

1. PowerShell 7 (`winget install Microsoft.PowerShell`), git, Python 3.11+. Clone this repo.
2. `./setup.ps1` checks those and creates the Python venv (`deploy.ps1` generates a test map with it).
3. The pinned 32-bit MinGW-w64 toolchain, 283 MB: `tools/plugin/README.md` "Toolchain (pinned)".
4. `./tools/make-working-copy.ps1 -Source 'C:\path\to\your\StarCraft'` copies your install to
   `C:\sc-work\1161-base` and checks its hashes. Your own install is never written to.
5. `./tools/plugin/fetch-cnc-ddraw.ps1` downloads the pinned presenter DLL (window, 2x scale, mouse lock).
6. `./tools/deploy.ps1` builds the plugin, assembles a self-contained modded copy under
   `C:\sc-deploy\starcraft-modded`, and puts a **StarCraft Modded** shortcut on the desktop.

Double-click the shortcut. Saves, profiles, replays and screenshots live in the deployed copy
and survive every redeploy.

## How does it work?

1. The shortcut runs `Launch-StarCraft-Modded.ps1`, which calls `plugin\run-with-plugin.ps1`
   with every feature switched on.
2. `scinject.exe` starts `StarCraft.exe` suspended: no game instruction has run yet.
3. It loads `scplugin.dll` into the still-suspended process (`LoadLibrary` on a remote thread),
   so the DLL's `DllMain` runs before the game's entry point.
4. The DLL patches the engine in memory: the widescreen geometry before the video init, and
   inline detours on the functions behind each feature. The exe on disk is untouched.
5. The main thread is resumed. StarCraft runs as usual, with the mod inside it.
6. Play. The one file the launcher writes into the game folder is cnc-ddraw's `ddraw.dll`
   (plus its ini), which presents the widened frame in a window.

## Developing

Same setup as above, steps 1-5. Then:

1. `./run.ps1 -Mode fanout -Windowed -WindowedHelperDll C:\sc-work\cnc-ddraw\v7.1.0.0\ddraw.dll`
   rebuilds the plugin when the DLL was not built from the current `tools/plugin/src`, and
   launches the working copy with it. `-Mode observe` (the default) injects a read-only observer that changes nothing.
   Every feature has its own off switch: `tools/plugin/run-with-plugin.ps1` parameters. The
   deployed shortcut turns all of them on (`tools/deploy.ps1` has the full flag set).
2. Edit `tools/plugin/src/*.cpp`, run again.
3. `./tools/plugin/build.ps1 -Test` builds and runs `hooktest.exe`, the offline detour-engine
   test. `Invoke-Pester -Path tests` runs the tooling tests (Pester 5).
4. `./tools/deploy.ps1` refreshes the desktop install. Play it.

How each feature works, with the addresses and how they were verified, is in `research/` and
`tools/plugin/README.md`. Read [AGENTS.md](AGENTS.md) before running an in-game suite; every
rule in it was paid for.

### Releases

`git tag v1.0 && git push origin v1.0`: CI builds with the pinned toolchain, runs hooktest, and
attaches `scplugin-v1.0.zip` (`scplugin.dll` + `scinject.exe`) to the
[GitHub release](https://github.com/inwenis/decompile-sc/releases).
`./run.ps1 -BuildDir <unzipped folder>` runs a prebuilt plugin without the toolchain.

## Layout

```
research/   per-subsystem findings -- the product of this repo
tools/      plugin, Ghidra automation, map + deploy tooling
tests/      Pester tests for the tooling
docs/       README screenshots
work/       scratch/ (ignored build output + logs), defects/ (patches for build-defect-arm.ps1)
```

Hard rule: no game binaries or assets in this repo. Research notes, scripts, and findings only.
