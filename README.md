# StarCraft: Brood War 1.16.1 mod

## How to play it?

1. You need your own StarCraft: Brood War 1.16.1; nothing from the game is in this repo or
   in the download. No 1.16.1? The
   [StarCraft Classic Installer & Downgrader](http://staredit.net/topic/17625/) on
   staredit.net installs, or patches an install to, exactly that version.
2. Download `starcraft-modded-<version>.zip` from the
   [latest release](https://github.com/inwenis/decompile-sc/releases) and unzip it anywhere.
3. Copy the contents of your StarCraft folder into the unzipped `game\` folder (a copy, not
   your only install).
4. Double-click `Launch-StarCraft-Modded.cmd`.

Nothing to install. If Windows warns about a downloaded file, click More info, then Run
anyway. `README.txt` in the zip has the rest.

## New features

1. select more than 12 units, right click to page through
2. select buildings of one type, queue units for all at once
3. queue more than 5 units in a building
4. queue upgrades
5. widescreen (hold Ctrl or Right Alt to free the mouse)

Offline and single-player only.

![70 units selected on the 1280x800 playfield; the bottom row reads 70 units 1-12 (1/6)](docs/screenshot-70-units.png)

![63 units selected, mixed Zerg army, widescreen viewport](docs/screenshot-63-units.png)

## How does it work?

1. You start the game from `Launch-StarCraft-Modded.cmd`.
2. It starts StarCraft suspended.
3. It loads `scplugin.dll` into the game's memory.
4. It lets `scplugin.dll` attach itself to the game functions it changes.
5. StarCraft is resumed.
6. Enjoy StarCraft with the extra features.

The launcher is a plain batch file: open it in Notepad to see exactly what runs on your
machine. Your game files stay untouched; every change happens in memory while the game runs.
The one file the launcher writes into your game folder is cnc-ddraw's `ddraw.dll` (plus its
ini), which shows the widened frame on your screen.

## Developing

Windows, PowerShell 7, git, Python 3.11+. The scripts at the repo root follow the same
convention as every other repo here:

1. `./setup-onetime.ps1 -StarCraftDir '<your StarCraft folder>'`, once per machine: the
   pinned 32-bit MinGW-w64 toolchain (283 MB, sha256-checked, into `C:\re-tools`), the pinned
   cnc-ddraw, and a hash-checked working copy of your game at `C:\sc-work\1161-base`. Your own
   install is never written to.
2. `./setup-worktree.ps1`, once per checkout: reports the prerequisites and creates the Python
   venv the test-map generator needs.
3. `./build.ps1 -Test` builds `scplugin.dll` + `scinject.exe` and runs `hooktest.exe`, the
   offline detour-engine test.
4. `./run.ps1 -Mode fanout -Windowed -WindowedHelperDll C:\sc-work\cnc-ddraw\v7.1.0.0\ddraw.dll`
   launches the working copy with the plugin, rebuilding it first when the DLL was not built
   from the current `tools/plugin/src`. `-Mode observe` (the default) injects a read-only
   observer that changes nothing. Every feature has its own off switch:
   `tools/plugin/run-with-plugin.ps1` parameters; the launcher turns all of them on.
5. Edit `tools/plugin/src/*.cpp`, run again.
6. `./deploy.ps1` installs the modded game at `C:\sc-deploy\starcraft-modded` with a
   **StarCraft Modded** desktop shortcut. Play it.

`Invoke-Pester -Path tests` runs the tooling tests (Pester 5). How each feature works, with
the addresses and how they were verified, is in `research/` and `tools/plugin/README.md`.
Read [AGENTS.md](AGENTS.md) before running an in-game suite; every rule in it was paid for.

### In detail: what the launcher does

1. `scinject.exe` starts `StarCraft.exe` suspended (`CREATE_SUSPENDED`): no game instruction
   has run yet.
2. It loads `scplugin.dll` into the still-suspended process (`LoadLibrary` on a remote
   thread), so the DLL's `DllMain` runs before the game's entry point.
3. The DLL patches the engine in memory: the widescreen geometry before the video init, and
   inline detours on the functions behind each feature. The exe on disk is untouched.
4. The main thread is resumed and StarCraft runs as usual, with the mod inside it.
5. The feature switches are `SCPLUGIN_*` environment variables, set by
   `tools/plugin/Launch-StarCraft-Modded.cmd` for players and by `run-with-plugin.ps1` for
   development.

### Releases

`git tag v1.0 && git push origin v1.0`: CI installs the pinned toolchain and cnc-ddraw
(`setup-onetime.ps1`), builds, runs hooktest, stages the player zip
(`tools/package-release.ps1`) and attaches `starcraft-modded-v1.0.zip` to the
[GitHub release](https://github.com/inwenis/decompile-sc/releases).
`./tools/package-release.ps1` makes the same zip locally under `work\scratch\release`.

## Layout

```
research/   per-subsystem findings -- the product of this repo
tools/      plugin, Ghidra automation, map + deploy + release tooling
tests/      Pester tests for the tooling
docs/       README screenshots
work/       scratch/ (ignored build output + logs), defects/ (patches for build-defect-arm.ps1)
```

Hard rule: no game binaries or assets in this repo. Research notes, scripts, and findings only.
