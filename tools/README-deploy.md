# Deploy pipeline (task018)

One command, run after every merge, that gets the latest modded build onto the desktop:
double-click, the game appears windowed with the full feature set on, no terminal, no
arguments.

```powershell
./tools/deploy.ps1
```

## What it does

1. Builds `scplugin.dll` + `scinject.exe` from the current checkout
   (`tools/plugin/build.ps1` -- fails the whole deploy if the build fails or either
   artifact is not PE32/x86).
2. Mirrors the working copy (`C:\sc-work\1161-base` by default) into
   `<DeployRoot>\game` -- the same `StarCraft.exe` bytes, not a rebuild.
3. Copies the freshly built plugin binaries, plus `run-with-plugin.ps1` and its
   `check-game-windows.ps1` dependency, into `<DeployRoot>\plugin`.
4. Writes `<DeployRoot>\Launch-StarCraft-Modded.ps1`, a zero-argument launcher with the
   feature set baked in (`-Mode fanout -InjectWindowedHelper WMode -Circles 1 -HudRow 1`
   -- fan-out select-past-12, selection circles, HUD row paging, windowed).
5. Creates/updates the desktop shortcut **`StarCraft Modded.lnk`**, target
   `pwsh -WindowStyle Hidden -File <launcher>` -- double-click, the game appears, no
   console window.
6. Verifies: deployed `StarCraft.exe` sha256 == source's, the plugin binaries are newer
   than this run (proof they were actually rebuilt, not stale leftovers), the shortcut
   resolves to an existing target and launcher. Prints a one-line receipt:
   `deploy: OK  version=<git-short-sha>[+dirty]  date=<yyyy-mm-dd>  -> <DeployRoot>`.

Idempotent: re-running mirrors the game tree again (a no-op robocopy pass if nothing
changed), overwrites the plugin binaries/launcher, and re-saves the shortcut. Safe to run
after every merge without any cleanup step first.

## Where things land

| what | where |
| --- | --- |
| Deployed install | `C:\sc-deploy\starcraft-modded\` (default; `-DeployRoot` to change) |
| Game files | `<DeployRoot>\game\` -- mirror of the working copy, `StarCraft.exe` byte-identical to it |
| Plugin runtime | `<DeployRoot>\plugin\` -- `scplugin.dll`, `scinject.exe`, and copies of `run-with-plugin.ps1` / `check-game-windows.ps1` |
| Launcher | `<DeployRoot>\Launch-StarCraft-Modded.ps1` -- zero arguments, feature set baked in |
| Desktop shortcut | `%USERPROFILE%\Desktop\StarCraft Modded.lnk` |
| Plugin log | `<DeployRoot>\logs\sc-plugin.log` (same format/rules as the dev log -- see `tools/plugin/README.md`) |

None of this is committed or trackable: `<DeployRoot>` is outside the repo (`deploy.ps1`
refuses a target inside it, or under `C:\sc-install`, or under the source working copy),
and it is game content (project hard rule 1).

## Design: self-contained, not a thin repo pointer

`tools/plugin/run-with-plugin.ps1` already does everything the launcher needs (the
pristine-install guard, injection, the windowed helper, the post-launch dialog check) --
reimplementing that here would just be duplication risk for no benefit. The only real
question was whether the deployed launcher should call *this repo's* copy of it in place,
or its own copy.

A thin pointer into the repo is fragile for this project specifically: worker worktrees
(including the one `deploy.ps1` was built in) are disposable and get pruned after merge
(see `AGENTS.md` § Conventions). A launcher baked with a worktree path breaks the day that
worktree is cleaned up. `deploy.ps1` instead **copies** `run-with-plugin.ps1` and
`check-game-windows.ps1` into `<DeployRoot>\plugin`, so the deployed install has everything
it needs under one root and keeps working even if every git worktree on the machine is
deleted.

The cost: a deployed install goes stale until the next `./tools/deploy.ps1` run, same as
the plugin binaries themselves already do -- not a new kind of staleness, just the same one
extended to two more files.

Run `deploy.ps1` from the persistent checkout (`C:\git\decompile-sc`), not from a worker's
task worktree, so the git SHA in the receipt reflects `main` after the merge it's meant to
capture.

## Re-deploy

```powershell
./tools/deploy.ps1
```

Same command every time. Pulls whatever plugin source is on disk in this checkout and
whatever game state is currently in the working copy.

## Remove

```powershell
Remove-Item "$env:USERPROFILE\Desktop\StarCraft Modded.lnk" -Force
Remove-Item C:\sc-deploy\starcraft-modded -Recurse -Force
```

Nothing else to undo: the deployed `StarCraft.exe` was never written to (it's a mirror of
the working copy, itself never written to by the injection path -- see
`tools/plugin/README.md` "Uninstall"), and nothing outside `<DeployRoot>` and the one
shortcut file was touched.

## Debug / off-switch

The Goal for this task is zero-argument play, so there's deliberately no second desktop
shortcut for debugging -- use one of these one-liners instead, same three off switches
`tools/plugin/README.md` documents for the dev flow, applied to the deployed copy:

```powershell
# 1. Cleanest: launch the deployed game with nothing of ours injected at all.
Start-Process 'C:\sc-deploy\starcraft-modded\game\StarCraft.exe'

# 2. Plugin attached but passive (read-only observer, writes nothing to game memory) --
#    useful for confirming the deployed binaries load without the fan-out/circles/HUD
#    hooks in the way.
pwsh -File 'C:\sc-deploy\starcraft-modded\plugin\run-with-plugin.ps1' `
    -GameDir 'C:\sc-deploy\starcraft-modded\game' `
    -BuildDir 'C:\sc-deploy\starcraft-modded\plugin' `
    -Mode observe -InjectWindowedHelper WMode

# 3. Never leave a game process running (hard rule) -- close it politely so the plugin's
#    DETACH/STATS line gets written:
pwsh -File 'C:\git\decompile-sc\tools\plugin\close-game.ps1'
```

## Verified

- `./tools/deploy.ps1` run twice back to back: second run's robocopy pass copies 0
  files/0 dirs (nothing changed), plugin binaries and shortcut rewritten identically --
  idempotent.
- `-DeployRoot` pointed inside the repo, under `C:\sc-install`, and under the source
  working copy all refuse before touching disk.
- Desktop shortcut launched with `Invoke-Item` (the actual double-click path): the game
  came up windowed, and the plugin log showed the deployed paths and the feature set on --
  `mode=fanout`, `circles=1`, `hudrow=1`, `HOOK: 6/6 installed`. `check-game-windows.ps1`
  reported no modal dialogs. Closed with `close-game.ps1`: `DLL_PROCESS_DETACH` ran (the
  log's `STATS`/`DETACH` lines are written from there), no stranded process afterward.
