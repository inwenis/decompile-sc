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

Nothing from the game is in this repo, and no prebuilt plugin is published yet, so playing
means building once. About 15 minutes on a fresh machine.

You need:

1. **Your own StarCraft: Brood War 1.16.1 install.** The scripts hash-check `StarCraft.exe` and refuse any other version (Remastered is a different program).
2. **Windows, PowerShell 7, git.** `winget install Microsoft.PowerShell Git.Git`
3. **The pinned 32-bit compiler** (MinGW-w64 GCC 16.1.0, i686). One-time download to `C:\re-tools`:

   ```powershell
   New-Item -ItemType Directory -Force C:\re-tools | Out-Null
   $zip = 'C:\re-tools\winlibs-i686-posix-dwarf-gcc-16.1.0-mingw-w64msvcrt-14.0.0-r4.zip'
   Invoke-WebRequest -Uri 'https://github.com/brechtsanders/winlibs_mingw/releases/download/16.1.0posix-14.0.0-msvcrt-r4/winlibs-i686-posix-dwarf-gcc-16.1.0-mingw-w64msvcrt-14.0.0-r4.zip' -OutFile $zip
   Expand-Archive -LiteralPath $zip -DestinationPath C:\re-tools\mingw32-gcc-16.1.0-i686-msvcrt
   ```

Then, in PowerShell 7:

```powershell
git clone https://github.com/inwenis/decompile-sc C:\git\decompile-sc
cd C:\git\decompile-sc
./tools/make-working-copy.ps1 -Source 'C:\Program Files (x86)\StarCraft'   # your install; hash-checked copy lands in C:\sc-work\1161-base
./tools/plugin/fetch-cnc-ddraw.ps1                                          # pinned presenter DLL, sha256-verified, to C:\sc-work\cnc-ddraw
./tools/deploy.ps1                                                          # builds the plugin, assembles C:\sc-deploy\starcraft-modded, desktop shortcut
```

Double-click **StarCraft Modded** on the desktop. Your original install is never written to.
Saves, profiles, replays and screenshots live under `C:\sc-deploy\starcraft-modded\game` and
survive every redeploy. To update: `git pull`, then `./tools/deploy.ps1` again.

If the window does not appear, the launcher shows a message box and writes
`C:\sc-deploy\starcraft-modded\logs\launch-error.log`.

## What gets deployed

`tools/deploy.ps1` assembles a self-contained install. The mod itself is the `plugin` folder
plus the launcher, a few MB; everything else is your own game files, mirrored.

| path under `C:\sc-deploy\starcraft-modded` | what |
| --- | --- |
| `plugin\scplugin.dll`, `plugin\scinject.exe` | the mod and the injector, built from the checkout |
| `plugin\run-with-plugin.ps1` + 4 helper scripts | the launch logic, copied so nothing points back at the repo |
| `plugin\cnc-ddraw\ddraw.dll`, `plugin\cnc-ddraw-2x.ini` | the presenter (windowed, 2x scale, cursor lock) |
| `Launch-StarCraft-Modded.ps1` | zero-argument launcher with every feature switched on |
| `widescreen-card.md` | one-page player card: what to expect, known cosmetic imperfections |
| `game\` | mirror of your working copy, `StarCraft.exe` byte-identical, plus `!feature-test.scx` for trying the features |
| desktop shortcut **StarCraft Modded** | `pwsh -WindowStyle Hidden -File Launch-StarCraft-Modded.ps1` |

## Set up for development

Everything in "Use it", plus what you need for the part you work on:

1. `./setup.ps1` reports the prerequisites and creates `.venv` (Python 3.11+): the test-map generator and the PE tools.
2. **Ghidra 12.1.2 + JDK**, for the static analysis behind `research/`: `tools/ghidra/README.md`.
3. **Node.js**, for the copy-paste gate CI runs: `python tools/check-reuse.py`.
4. **Pester 5**, for the tooling tests: `Invoke-Pester -Path tests`.
5. `./tools/plugin/build.ps1 -Test` builds the plugin and runs `hooktest.exe`, the offline detour-engine test.
6. `./run.ps1` launches the game from this checkout with the plugin injected (`-Mode fanout` and the feature switches; see `tools/plugin/README.md` "Run").
7. In-game suites run on an invisible desktop: `./tools/plugin/run-offscreen.ps1 -Suite ./tools/plugin/test-<name>.ps1`, with `$env:AGENT_TASK` set to a few digits first. Read [AGENTS.md](AGENTS.md) before the first one; it is short and every rule in it was paid for.

## Layout

```
research/   per-subsystem findings -- the product of this repo
tools/      plugin, Ghidra automation, map + deploy tooling
tests/      Pester tests for the tooling
docs/       README screenshots
work/       scratch/ (ignored build output + logs), defects/ (patches for build-defect-arm.ps1)
```

Hard rule: no game binaries or assets in this repo. Research notes, scripts, and findings only.
See [AGENTS.md](AGENTS.md) for the rulebook.
