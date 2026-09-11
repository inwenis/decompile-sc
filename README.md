# StarCraft: Brood War 1.16.1 mod

## How to play it?

1. You need your own StarCraft: Brood War 1.16.1
   ([installer here](http://staredit.net/topic/17625/)).
2. Press Win+R, paste this, press Enter:

   ```
   powershell -c "irm https://raw.githubusercontent.com/inwenis/decompile-sc/main/play.ps1 | iex"
   ```

It downloads the latest release into `%LOCALAPPDATA%\StarCraft-Modded` and starts the game with the mod.

Run the same line again to update, or `Launch-StarCraft-Modded.cmd` in that folder to just play.

Rather not paste a one-liner?

Unzip [the release](https://github.com/inwenis/decompile-sc/releases) anywhere and double-click the launcher.

## New features

1. select more than 12 units, right click to page through
2. select buildings of one type, queue units for all at once
3. queue more than 5 units in a building
4. queue upgrades, shown as icons in the building's queue like units
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

Your game files stay untouched. While you play, cnc-ddraw's `ddraw.dll` (the window
presenter) sits in your StarCraft folder; the launcher removes it when you quit. Open the
launcher in Notepad to see everything it does.

## Developing

Windows, PowerShell 7, git, Python 3.11+.

1. `./setup-onetime.ps1 -StarCraftDir '<your StarCraft folder>'`, once per machine: toolchain,
   cnc-ddraw, a working copy of your game.
2. `./setup-worktree.ps1`, once per checkout: the Python venv.
3. `./build.ps1 -Test` builds the plugin and runs the offline hook test.
4. `./run.ps1 -Mode fanout -Windowed -WindowedHelperDll C:\sc-work\cnc-ddraw\v7.1.0.0\ddraw.dll`
   launches the working copy with the plugin, rebuilding it when stale.
5. `./deploy.ps1` installs the modded game with a desktop shortcut.

Release: `git tag v1.0 && git push origin v1.0`; CI builds the zip and attaches it. Tests:
`Invoke-Pester -Path tests`. How each feature works and how it was verified: `research/` and
`tools/plugin/README.md`. Read [AGENTS.md](AGENTS.md) before running an in-game suite.

## Layout

```
research/   per-subsystem findings -- the product of this repo
tools/      plugin, Ghidra automation, map + deploy + release tooling
tests/      Pester tests for the tooling
docs/       README screenshots
work/       scratch/ (ignored build output + logs), defects/ (patches for build-defect-arm.ps1)
```

Hard rule: no game binaries or assets in this repo.
