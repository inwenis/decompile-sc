# Deploy pipeline (task018)

One command, run after every merge, that gets the latest modded build onto the desktop:
double-click, the game appears windowed with the full feature set on, no terminal, no
arguments.

```powershell
./tools/deploy.ps1
```

## What it does

1. Guards `-DeployRoot`: canonicalises it (device prefix / 8.3 short name / symlink /
   junction -- `tools/plugin/sc-canonical-path.ps1`, shared with `run-with-plugin.ps1`'s
   own pristine-install guard, so `-DeployRoot '\\?\C:\sc-install\Starcraft'` cannot slip
   past a naive string check) and refuses a target inside this repo, under `C:\git`, under
   `C:\sc-work`, under `-SourceGameDir`, or under `C:\sc-install`.
2. Refuses if StarCraft is currently running (redeploying over a locked `scplugin.dll`
   would abort mid-copy, *after* the mirror's purge had already run).
3. Refuses if `<DeployRoot>\game` contains a reparse point (symlink/junction) -- a `/MIR`
   purge follows one into its target and deletes files there.
4. Builds `scplugin.dll` + `scinject.exe` from the current checkout
   (`tools/plugin/build.ps1` -- fails the whole deploy if the build fails or either
   artifact is not PE32/x86).
5. Mirrors the working copy (`C:\sc-work\1161-base` by default) into
   `<DeployRoot>\game` -- the same `StarCraft.exe` bytes, not a rebuild.
   `characters\` (player profiles) and `Maps\Replays\` (replays) are excluded from the
   mirror entirely, so anything the deployed game itself writes there survives every
   future redeploy -- see "Player data survives redeploys" below.
6. Copies the freshly built plugin binaries, plus `run-with-plugin.ps1` and its
   `check-game-windows.ps1` / `sc-canonical-path.ps1` dependencies, into
   `<DeployRoot>\plugin`.
7. Writes `<DeployRoot>\Launch-StarCraft-Modded.ps1`, a zero-argument launcher with the
   feature set baked in (`-Mode fanout -InjectWindowedHelper WMode -Circles 1 -HudRow 1`
   -- fan-out select-past-12, selection circles, HUD row paging, windowed).
8. Creates/updates the desktop shortcut **`StarCraft Modded.lnk`**, target
   `pwsh -WindowStyle Hidden -File <launcher>` -- double-click, the game appears, no
   console window.
9. Verifies: deployed `StarCraft.exe` sha256 == source's, the plugin binaries are newer
   than this run (proof they were actually rebuilt, not stale leftovers), the shortcut
   resolves to an existing target and launcher. Prints a one-line receipt:
   `deploy: OK  version=<git-short-sha>[+dirty]  date=<yyyy-mm-dd>  -> <DeployRoot>`.

Idempotent: re-running mirrors the game tree again (a no-op robocopy pass if nothing
changed), overwrites the plugin binaries/launcher, and re-saves the shortcut. Player
profiles and replays already in the deploy dir are untouched by a re-run -- see "Player
data survives redeploys" below for exactly what that does and does not cover.

## Player data survives redeploys

A first version of this script mirrored the working copy into `<DeployRoot>\game` with a
plain `/MIR`, which is a *true* mirror: anything the destination has that the source does
not gets deleted. That is correct for the shipped game files and was **wrong** for player
state -- a save under `characters\` or a replay under `Maps\Replays\` exists only in the
deploy dir (the working copy is a dev scratch area, nobody plays from it), so a plain
`/MIR` silently deleted the user's own saves and replays on every redeploy after the one
that created them. Caught in review before this was ever called "deployed", not by a user
losing a save.

Fixed by excluding both directories from the mirror (`/XD`) entirely, so robocopy neither
copies into them nor purges them, in either direction -- they end up exactly whatever the
deployed game itself has written, forever. One robocopy quirk worth knowing if you touch
this: `/XD 'Maps\Replays'` (a multi-segment relative path) silently does **not** match on
this robocopy build -- verified live, it still overwrote the replay and purged a
destination-only test file. A bare directory *name* (`/XD 'Replays'`) does work and
matches at any depth; safe here because `Replays` occurs exactly once in the whole source
tree, under `Maps\`.

**What is not covered**: a custom map dropped directly under `<DeployRoot>\game\Maps\`
(not `\Replays\`) is not preserved -- it lives in the part of the tree that still mirrors
the source. `tools/make-working-copy.ps1` makes a similar tradeoff for the working copy
itself but draws the line differently (its `-PreservedExtraPrefixes` covers `characters\`
and *all* of `Maps\`); this script's line matches exactly what a stock client writes on
its own -- profiles and replays -- and nothing wider.

## Where things land

| what | where |
| --- | --- |
| Deployed install | `C:\sc-deploy\starcraft-modded\` (default; `-DeployRoot` to change) |
| Game files | `<DeployRoot>\game\` -- mirror of the working copy, `StarCraft.exe` byte-identical to it |
| Player saves | `<DeployRoot>\game\characters\` -- never touched by a redeploy |
| Replays | `<DeployRoot>\game\Maps\Replays\` -- never touched by a redeploy |
| Plugin runtime | `<DeployRoot>\plugin\` -- `scplugin.dll`, `scinject.exe`, and copies of `run-with-plugin.ps1` / `check-game-windows.ps1` / `sc-canonical-path.ps1` |
| Launcher | `<DeployRoot>\Launch-StarCraft-Modded.ps1` -- zero arguments, feature set baked in |
| Desktop shortcut | `%USERPROFILE%\Desktop\StarCraft Modded.lnk` |
| Plugin log | `<DeployRoot>\logs\sc-plugin.log` (same format/rules as the dev log -- see `tools/plugin/README.md`) |

None of this is committed or trackable: `<DeployRoot>` is outside the repo (`deploy.ps1`
refuses a target inside this repo, any repo/worktree under `C:\git`, `C:\sc-work`, the
source working copy, or `C:\sc-install`), and it is game content (project hard rule 1).

## Design: self-contained, not a thin repo pointer

`tools/plugin/run-with-plugin.ps1` already does everything the launcher needs (the
pristine-install guard, injection, the windowed helper, the post-launch dialog check) --
reimplementing that here would just be duplication risk for no benefit. The only real
question was whether the deployed launcher should call *this repo's* copy of it in place,
or its own copy.

A thin pointer into the repo is fragile for this project specifically: worker worktrees
(including the one `deploy.ps1` was built in) are disposable and get pruned after merge
(see `AGENTS.md` § Conventions). A launcher baked with a worktree path breaks the day that
worktree is cleaned up. `deploy.ps1` instead **copies** `run-with-plugin.ps1`,
`check-game-windows.ps1` and `sc-canonical-path.ps1` into `<DeployRoot>\plugin`, so the
deployed install has everything it needs under one root and keeps working even if every
git worktree on the machine is deleted.

`sc-canonical-path.ps1` (`Get-CanonicalPath` / `Test-PathUnder`) used to be defined inline
inside `run-with-plugin.ps1`; it was pulled out into its own file so `deploy.ps1`'s
`-DeployRoot` guard could reuse the exact same junction/8.3/device-prefix-proof routine
instead of a second, driftable copy. `run-with-plugin.ps1` now dot-sources it too, so
there's one canonicalisation routine, not two guards that could quietly disagree.

The cost: a deployed install goes stale until the next `./tools/deploy.ps1` run, same as
the plugin binaries themselves already do -- not a new kind of staleness, just the same one
extended to two more files.

Run `deploy.ps1` from the persistent checkout (`C:\git\decompile-sc`), not from a worker's
task worktree, so the git SHA in the receipt reflects `main` after the merge it's meant to
capture.

## Sound

Unattended launches through `run-with-plugin.ps1` (every test suite, and anything a
worker runs by hand without passing `-Sound`) are **silent by default** -- a `-Sound`
switch is the escape hatch for a normal, audible launch, e.g. when debugging something
audio-adjacent. **The deployed shortcut always passes `-Sound`**: the launcher
`deploy.ps1` generates bakes it in (see `Launch-StarCraft-Modded.ps1`'s own
`-InjectWindowedHelper WMode -Sound -Circles 1 ...` call), so the user's own play is never
muted by this.

Mechanism: `tools/plugin/sc-audio-mute.ps1` mutes the game's own Windows Core Audio
(WASAPI) session directly -- the same per-application volume the Windows Volume Mixer
controls -- once the game's process id is known, and keeps re-affirming it in the
background for as long as the process lives (the session is created lazily, not at
launch -- see `run-with-plugin.ps1`'s own "Sound" section for what was and was not
directly verified). Nothing is written to the registry or disk; the mute is a property of
the process's own audio session and ends when the process does -- no restore step, no
state that can be left corrupted by a crash or an overlapping run.

This replaced an earlier registry-based approach (`HKCU:\SOFTWARE\Blizzard
Entertainment\Starcraft` `music`/`sfx`, save-before/restore-after) that wiped a real
user's entire StarCraft settings key on its first live run via an unguarded `New-Item
-Force` against an already-existing key -- see `run-with-plugin.ps1`'s "Sound" section for
the full incident writeup. `config/guard-destructive.ps1` now hard-denies writes to that
registry key from any worker, and AGENTS.md carries a standing rule against writing live
user state outside the repo/working copy as a direct result.

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

- `./tools/deploy.ps1` run repeatedly back to back: robocopy pass copies 0 files/0 dirs
  once nothing has changed, plugin binaries and shortcut rewritten identically --
  idempotent.
- Planted `characters\deploy-only-marker.spc` and `Maps\Replays\deploy-only-marker.rep`
  (not present in the source working copy) plus a pre-existing save/replay
  (`characters\asdf.spc`, `Maps\Replays\LastReplay.rep`), then redeployed twice: all four
  survived byte-for-byte (sha256 compared before/after) both times -- the acceptance bar
  for the player-data fix. An unrelated stale file outside those two directories
  (`Maps\BroodWar\00-testmap\combat.scx`, not in source) was correctly purged by the same
  run, confirming the exclusion is scoped to just the two user-data directories.
- `-DeployRoot` pointed inside the repo, under `C:\git`, under `C:\sc-work`, under the
  source working copy, and under `C:\sc-install` all refuse before touching disk. Also
  refuses a device-prefix (`\\?\C:\sc-install\Starcraft\evil`) and an 8.3-short-name
  (`C:\SC-INS~1\evil`) attempt to spell a protected root differently -- both canonicalise
  to the real path before the comparison.
- A junction planted under `<DeployRoot>\game` is refused outright (reparse-point guard)
  rather than attempting `/MIR` over it.
- StarCraft running (from anywhere) makes `deploy.ps1` refuse before the build or mirror
  step runs; reproduced the failure this guards against first (redeploying over a running
  game aborted mid-copy with `scplugin.dll ... being used by another process`, after the
  mirror's purge had already run) and confirmed the guard now catches it before that point.
- Desktop shortcut launched with `Invoke-Item` (the actual double-click path): the game
  came up windowed, and the plugin log showed the deployed paths and the feature set on --
  `mode=fanout`, `circles=1`, `hudrow=1`, `HOOK: 6/6 installed`. `check-game-windows.ps1`
  reported no modal dialogs. Closed with `close-game.ps1`: `DLL_PROCESS_DETACH` ran (the
  log's `STATS`/`DETACH` lines are written from there), no stranded process afterward.

### Known limitation: the running-game guard checks by name, not by path

The natural check for finding 4 above is "is StarCraft running *from `<DeployRoot>`*
specifically" -- but that needs the process's image path, and on this machine
`Get-Process`'s `.Path`/`.MainModule`, `Get-CimInstance Win32_Process`'s
`ExecutablePath`, and even a raw `OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION)` against
the game's own pid all come back empty or access-denied for this specific process
(verified live; not root-caused -- looks like a session/token boundary between the
shell driving these tests and the desktop the game runs on, not something specific to
StarCraft). A guard that silently no-ops when path access fails is worse than a broader
one that always fires, so `deploy.ps1` checks by process name alone, the same as
`tools/plugin/close-game.ps1`'s own precedent: it refuses whenever *any* StarCraft process
is running, not only one launched from `<DeployRoot>`. Conservative, but never silently
wrong.
