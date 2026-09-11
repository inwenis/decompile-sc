# decompile-sc

StarCraft: Brood War 1.16.1 reverse-engineering research, and a gameplay mod built on it.

The mod is a 32-bit DLL injected at launch. The game files on disk stay byte-identical; every
change is applied in memory. Offline and single-player only.

![70 units selected on the 1280x800 playfield; the bottom row reads 70 units 1-12 (1/6)](docs/screenshot-70-units.png)

![63 units selected, mixed Zerg army, widescreen viewport](docs/screenshot-63-units.png)

## New features

1. select more than 12 units, right click to page through
2. select buildings of one type, queue units for all at once
3. queue more than 5 units in a building
4. queue upgrades
5. widescreen (ctrl or alt to free mouse)

Every feature has its own off switch (`tools/plugin/run-with-plugin.ps1` parameters); the
deployed desktop shortcut turns all of them on. How each one works, with the addresses and
how they were verified, is in `research/` and `tools/plugin/README.md`.

## Use it (play the mod)

Nothing from the game is in this repo or the download; you need your own StarCraft: Brood
War 1.16.1.

1. Download `starcraft-modded-<version>.zip` from the [latest release](https://github.com/inwenis/decompile-sc/releases/latest) and extract it anywhere.
2. Install PowerShell 7 if you do not have it: `winget install Microsoft.PowerShell`
3. Copy the contents of your StarCraft 1.16.1 folder into the extracted `game\` folder (a copy, not your only install).
4. Double-click `Launch-StarCraft-Modded.cmd`.

The launcher refuses an exe that is not the 1.16.1 build and says so. Everything the game
writes (saves, profiles, replays, screenshots) stays under `game\`. If the window does not
appear, a message box says why and `logs\launch-error.log` has the details. The README inside
the zip covers the rest: unblocking a downloaded zip, SmartScreen, a 2x window instead of
borderless full screen.

## What is in the zip

| path | what |
| --- | --- |
| `plugin\scplugin.dll`, `plugin\scinject.exe` | the mod and the injector, built by CI from the tagged commit |
| `plugin\run-with-plugin.ps1` + helper scripts | the launch logic |
| `plugin\cnc-ddraw\ddraw.dll`, `plugin\cnc-ddraw-2x.ini` | the presenter (borderless, aspect kept, cursor lock) |
| `Launch-StarCraft-Modded.cmd`, `Launch-StarCraft-Modded.ps1` | zero-argument launcher with every feature on |
| `widescreen-card.md` | one-page player card: what to expect, known cosmetic imperfections |
| `game\` | empty; your own 1.16.1 files go here |

`tools/package-release.ps1` is what CI runs to build it; `tools/deploy.ps1` assembles the
same tree from a checkout on this machine, plus a mirrored game and a desktop shortcut.

## Set up for development

You need the toolchain and a working copy of the game:

1. Windows, PowerShell 7, git. `./setup.ps1` reports the prerequisites and creates `.venv` (Python 3.11+): the test-map generator and the PE tools.
2. `./tools/plugin/install-toolchain.ps1` downloads the pinned 32-bit MinGW-w64 (283 MB, sha256-checked) to `C:\re-tools`.
3. `./tools/make-working-copy.ps1 -Source 'C:\Program Files (x86)\StarCraft'` makes the hash-checked working copy at `C:\sc-work\1161-base` from your install.
4. `./tools/plugin/fetch-cnc-ddraw.ps1` downloads the pinned presenter DLL.
5. `./tools/deploy.ps1` builds, assembles `C:\sc-deploy\starcraft-modded` and puts a **StarCraft Modded** shortcut on the desktop. `./run.ps1` launches from the checkout instead.
6. `./tools/plugin/build.ps1 -Test` builds and runs `hooktest.exe`, the offline detour-engine test. `Invoke-Pester -Path tests` runs the tooling tests (Pester 5). `python tools/check-reuse.py` is the copy-paste gate CI runs (needs Node.js).
7. **Ghidra 12.1.2 + JDK**, for the static analysis behind `research/`: `tools/ghidra/README.md`.
8. In-game suites run on an invisible desktop: `./tools/plugin/run-offscreen.ps1 -Suite ./tools/plugin/test-<name>.ps1`, with `$env:AGENT_TASK` set to a few digits first. Read [AGENTS.md](AGENTS.md) before the first one; it is short and every rule in it was paid for.

Cutting a release: push a tag `vX.Y`. `.github/workflows/release.yml` builds with the pinned
toolchain, runs hooktest, packs the zip and attaches it to the GitHub release.

## Layout

```
research/   per-subsystem findings -- the product of this repo
tools/      plugin, Ghidra automation, map + deploy + release tooling
tests/      Pester tests for the tooling
docs/       README screenshots
work/       scratch/ (ignored build output + logs), defects/ (patches for build-defect-arm.ps1)
```

Hard rule: no game binaries or assets in this repo. Research notes, scripts, and findings only.
See [AGENTS.md](AGENTS.md) for the rulebook.
