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
   own pristine-install guard, so `-DeployRoot '\\?\C:\decompile-sc-data\sc-install\Starcraft'` cannot slip
   past a naive string check) and refuses a target inside this repo, under `C:\git`, under
   `C:\decompile-sc-data\sc-work`, under `-SourceGameDir`, or under `C:\decompile-sc-data\sc-install`.
2. Takes the cross-worker launch/deploy lock (`tools/plugin/sc-launch-lock.ps1`, the same
   one `run-with-plugin.ps1` uses) for the rest of the run -- guard checks through verify
   -- so a game cannot start in the window between step 3's check and the mirror actually
   running. See "Launch lock" below.
3. Refuses if StarCraft is currently running (redeploying over a locked `scplugin.dll`
   would abort mid-copy, *after* the mirror's purge had already run).
4. Refuses if `<DeployRoot>\game` contains a reparse point (symlink/junction) -- a `/MIR`
   purge follows one into its target and deletes files there.
5. Builds `scplugin.dll` + `scinject.exe` from the current checkout
   (`tools/plugin/build.ps1` -- fails the whole deploy if the build fails or either
   artifact is not PE32/x86).
6. Mirrors the working copy (`C:\decompile-sc-data\sc-work\1161-base` by default) into
   `<DeployRoot>\game` -- the same `StarCraft.exe` bytes, not a rebuild.
   `characters\`, `save\`, `Maps\Replays\`, `maps\download\` and `SCScrnShot_*.pcx` are
   excluded from the mirror entirely, so anything the deployed game itself writes there
   survives every future redeploy -- see "What survives a redeploy, and what does not"
   below. A tripwire hashes those directories before and after the mirror and throws if
   anything preserved actually changed.
7. Copies the freshly built plugin binaries, plus `run-with-plugin.ps1` and its
   `check-game-windows.ps1` / `sc-canonical-path.ps1` / `sc-audio-mute.ps1` /
   `sc-launch-lock.ps1` dependencies, into `<DeployRoot>\plugin`.
8. Writes `<DeployRoot>\Launch-StarCraft-Modded.ps1`, a zero-argument launcher with the
   feature set baked in (`-Mode fanout -InjectWindowedHelper WMode -Circles 1 -HudRow 1
   -Sound -NoLaunchLock` -- fan-out select-past-12, selection circles, HUD row paging,
   windowed, audible, structurally unable to take the worker launch lock). The launcher
   also wraps the launch in try/catch: on failure it logs to
   `<DeployRoot>\logs\launch-error.log` and shows a message box, since it runs
   `pwsh -WindowStyle Hidden` with no console for any failure to otherwise show up in.
9. Creates/updates the desktop shortcut **`StarCraft Modded.lnk`**, target
   `pwsh -WindowStyle Hidden -File <launcher>` -- double-click, the game appears, no
   console window. Every geometry preset also gets **`StarCraft Modded <WxH>.lnk`**
   (the same launcher with `-Geometry <WxH>`, presented through its own
   `plugin\cnc-ddraw-2x-<WxH>.ini`), for trying the sizes side by side.
10. Verifies: deployed `StarCraft.exe` sha256 == source's, the plugin binaries are newer
    than this run (proof they were actually rebuilt, not stale leftovers), the shortcut
    resolves to an existing target and launcher. Prints a one-line receipt:
    `deploy: OK  version=<git-short-sha>[+dirty]  date=<yyyy-mm-dd>  -> <DeployRoot>`.

Idempotent: re-running mirrors the game tree again (a no-op robocopy pass if nothing
changed), overwrites the plugin binaries/launcher, and re-saves the shortcut. Player data
already in the deploy dir is untouched by a re-run -- see "What survives a redeploy, and
what does not" below for exactly what that does and does not cover.

## What survives a redeploy, and what does not

A first version of this script mirrored the working copy into `<DeployRoot>\game` with a
plain `/MIR`, which is a *true* mirror: anything the destination has that the source does
not gets deleted. That is correct for the shipped game files and was **wrong** for player
state, which exists only in the deploy dir (the working copy is a dev scratch area, nobody
plays from it) -- a plain `/MIR` silently deleted it on every redeploy after the one that
created it.

This bug class took **three review rounds** to close, each finding a sibling the previous
one missed:
- **Round 1**: `characters\` (profiles) and `Maps\Replays\` (replays) excluded.
- **Round 2**: `save\` (single-player saved games) added -- a **sibling** of `characters\`,
  not something it already covered, missed until a live save-then-redeploy test caught it.
  Evidence it exists: `StarCraft.exe`'s own strings carry a bare `save\` fragment next to
  `** Single Player Save Format ver %d.%d`, and it has 0 occurrences in the source tree
  (purely a deploy-dir-only, destination-side directory -- exactly the shape `/MIR` purges
  without an exclusion).
- **Round 3**: `maps\download\` (Battle.net map-download cache, same 0-occurrences shape,
  excluded pre-emptively rather than waiting to catch it live a fourth time) and
  `SCScrnShot_*.pcx` (in-game screenshots, which land in the game dir **root**, not a
  subdirectory -- a `/XF` file-pattern exclusion, not `/XD`) added, and a **post-mirror
  tripwire** introduced: `deploy.ps1` hashes every file under the preserved directories
  before the mirror runs and again after, and throws if anything preserved is missing or
  changed. Three rounds of "a verifier had to notice by hand" is the argument for making a
  fourth instance of this bug fail loudly on its own instead.

**PRESERVED** (excluded from the mirror entirely, in both directions):

| what | where |
| --- | --- |
| Player profiles | `characters\` |
| Single-player saved games | `save\` |
| Replays | `Maps\Replays\` |
| Battle.net map-download cache | `maps\download\` (0 occurrences in source; excluded pre-emptively) |
| In-game screenshots (F12) | `SCScrnShot_*.pcx`, game dir root |

**PURGED** (still a true mirror of the source, same as everything else):
- `Maps\` itself, outside `\Replays\` -- a custom map dropped straight into
  `<DeployRoot>\game\Maps\` does **not** survive a redeploy.
- `Errors\` -- crash logs, same reasoning.
- anything else not in the preserved set above.

One robocopy quirk worth knowing if you touch this list: `/XD 'Maps\Replays'` (a
multi-segment relative path) silently does **not** match on this robocopy build --
verified live, it still overwrote the replay and purged a destination-only test file. A
bare directory *name* (`/XD 'Replays'`) does work and matches at any depth; safe for
`Replays`/`save`/`download` because each occurs at most once in the whole source tree
(once under `Maps\`, zero times for the other two).

**What is still not covered, deliberately**: a custom map dropped directly under
`<DeployRoot>\game\Maps\` (not `\Replays\`). The honest fix needs the same diff-based
"keep destination-only extras" logic `tools/make-working-copy.ps1` already uses for the
working copy (its `-PreservedExtraPrefixes` covers `characters\` and *all* of `Maps\`) --
`/XD` cannot do it, because `/XD`-ing all of `Maps\` would also skip copying the *shipped*
stock maps under it on a fresh deploy, breaking Single Player/Skirmish map lists entirely.
That is a real feature, not a rejected idea, but it is more code than any single fix round
here and nothing in the task's Goal asks for custom-map support in the deployed copy --
worth a follow-up task if that changes.

## Launch lock

Two workers (or a worker and a redeploy) racing StarCraft on the same machine is not
hypothetical -- it happened live during this task: a second worker's own StarCraft process
was mistaken by its cleanup logic for this one's leftover and closed mid-test, and
`deploy.ps1`'s running-game preflight check has the identical TOCTOU across its own
build+mirror window. Both `run-with-plugin.ps1` and `deploy.ps1` now take an exclusive OS
file lock (`C:\decompile-sc-data\sc-work\logs\sc-launch.lock`, `tools/plugin/sc-launch-lock.ps1`) before
touching the shared working copy or the shared game process, and hold it until the
protected section finishes.

Deliberately an **exclusive file handle**
(`[IO.File]::Open(path, OpenOrCreate, ReadWrite, FileShare.None)`), not a check-then-write
of JSON content to a plain file -- a verifier produced a concrete two-winner interleaving
against the check-then-write version. The handle is atomic (the open call itself is the
acquire) and self-healing: if the holder crashes or is killed, Windows releases the handle
the instant the process dies, so a lock that outlives its holder cannot exist -- no
separate stale-pid bookkeeping needed.

Scope: `run-with-plugin.ps1` takes it before `-RemoveWindowed`'s delete and `-Windowed`'s
copy of `ddraw.dll` (both act on the shared working copy, so both race the same way a
launch does), through the post-launch health check, and releases it there --
**deliberately not for the whole play session**. `-WaitForExit` releases the lock before
blocking on the game's exit, not after (an earlier version of this got that backwards and
would have silently turned any `-WaitForExit` call into a whole-session lock).
`deploy.ps1` takes it for its entire run, guard checks through verify.

**This lock must never be reachable from the user's own play.** It is taken only when
`$env:AGENT_TASK` is set (true for every worker, never true for a human double-clicking
the desktop shortcut) -- and the deployed launcher additionally bakes in `-NoLaunchLock`,
an independent second guard, on top of the env-var check that would already cover it. This
belt-and-suspenders approach exists because the alternative shipped once already during
this task's own review: the deployed copy of `run-with-plugin.ps1` picked up the lock code
on a routine redeploy, and since the desktop shortcut runs `pwsh -WindowStyle Hidden`, a
held or wedged lock would have meant the user double-clicking their game and getting
nothing on screen, silently, for the whole wait budget. Caught in review before it ever
reached a real deploy.

## Where things land

| what | where |
| --- | --- |
| Deployed install | `C:\decompile-sc-data\sc-deploy\starcraft-modded\` (default; `-DeployRoot` to change) |
| Game files | `<DeployRoot>\game\` -- mirror of the working copy, `StarCraft.exe` byte-identical to it |
| Player profiles | `<DeployRoot>\game\characters\` -- never touched by a redeploy |
| Single-player saves | `<DeployRoot>\game\save\` -- never touched by a redeploy |
| Replays | `<DeployRoot>\game\Maps\Replays\` -- never touched by a redeploy |
| Map-download cache | `<DeployRoot>\game\maps\download\` -- never touched by a redeploy |
| Screenshots | `<DeployRoot>\game\SCScrnShot_*.pcx` -- never touched by a redeploy |
| Plugin runtime | `<DeployRoot>\plugin\` -- `scplugin.dll`, `scinject.exe`, and copies of `run-with-plugin.ps1` / `check-game-windows.ps1` / `sc-canonical-path.ps1` / `sc-audio-mute.ps1` / `sc-launch-lock.ps1` |
| Launcher | `<DeployRoot>\Launch-StarCraft-Modded.ps1` -- zero arguments, feature set baked in |
| Desktop shortcut | `%USERPROFILE%\Desktop\StarCraft Modded.lnk`, plus `StarCraft Modded <WxH>.lnk` per geometry preset |
| Plugin log | `<DeployRoot>\logs\sc-plugin.log` (same format/rules as the dev log -- see `tools/plugin/README.md`) |
| Launcher failure log | `<DeployRoot>\logs\launch-error.log` -- only written if the launcher itself throws |
| Cross-worker lock | `C:\decompile-sc-data\sc-work\logs\sc-launch.lock` (shared, outside `<DeployRoot>`) |

None of this is committed or trackable: `<DeployRoot>` is outside the repo (`deploy.ps1`
refuses a target inside this repo, any repo/worktree under `C:\git`, `C:\decompile-sc-data\sc-work`, the
source working copy, or `C:\decompile-sc-data\sc-install`), and it is game content (project hard rule 1).

## Design: self-contained, not a thin repo pointer

`tools/plugin/run-with-plugin.ps1` already does everything the launcher needs (the
pristine-install guard, injection, the windowed helper, the post-launch dialog check) --
reimplementing that here would just be duplication risk for no benefit. The only real
question was whether the deployed launcher should call *this repo's* copy of it in place,
or its own copy.

A thin pointer into the repo is fragile for this project specifically: worker worktrees
(including the one `deploy.ps1` was built in) are disposable and get pruned after merge
(see `AGENTS.md` § Conventions). A launcher baked with a worktree path breaks the day that
worktree is cleaned up. `deploy.ps1` instead **copies** `run-with-plugin.ps1` and its
dependencies into `<DeployRoot>\plugin`, so the deployed install has everything it needs
under one root and keeps working even if every git worktree on the machine is deleted.

`sc-canonical-path.ps1`, `sc-audio-mute.ps1` and `sc-launch-lock.ps1` are all small shared
files for exactly this reason: one routine each, dot-sourced by both `run-with-plugin.ps1`
and (where relevant) `deploy.ps1`, instead of a second, driftable copy of the same logic
in each place that needs it.

The cost: a deployed install goes stale until the next `./tools/deploy.ps1` run, same as
the plugin binaries themselves already do -- not a new kind of staleness, just the same one
extended to a few more files.

Run `deploy.ps1` from the persistent checkout (`C:\git\decompile-sc`), not from a worker's
task worktree, so the git SHA in the receipt reflects `main` after the merge it's meant to
capture.

## Sound

Unattended launches through `run-with-plugin.ps1` (every test suite, and anything a
worker runs by hand without passing `-Sound`) are **silent by default** -- a `-Sound`
switch is the escape hatch for a normal, audible launch, e.g. when debugging something
audio-adjacent; it also actively **clears** any mute rather than merely skipping the mute
call, as cheap insurance (see below). **The deployed shortcut always passes `-Sound`**
(and `-NoLaunchLock` -- see "Launch lock" above): the launcher `deploy.ps1` generates
bakes both in, so the user's own play is never muted or lock-blocked by any of this.

Mechanism: `tools/plugin/sc-audio-mute.ps1` mutes the game's own Windows Core Audio
(WASAPI) session directly -- the same per-application volume the Windows Volume Mixer
controls -- across **every active render endpoint**, once the game's process id is known.
Checking every endpoint, not just the default one, is what actually fixed this: earlier
attempts checked the default endpoint only and never found StarCraft's session across
several real attempts, until a verifier found Windows' own per-app audio policy store
showing StarCraft with sessions on **three** distinct render endpoints on the machine this
was built on (onboard line-out, an HDMI output, a USB device) -- the session was almost
certainly live the whole time, on an endpoint the code never looked at.

Scope, stated exactly rather than aspirationally: `Set-ScProcessMuted` polls at launch and
then **stops** -- there is no ongoing re-check after that window. An earlier version
claimed a background timer kept re-affirming the mute for the whole game session; measured
live, that timer did not fire while the calling script was inside a `Start-Sleep` call (0
ticks across a 3s sleep) and died with the calling `pwsh` process regardless, so it did not
do what it claimed and was removed rather than left in place as a false guarantee.

Persistence: searched both known Windows per-app audio policy registry locations
(`HKCU:\...\MMDevices\Audio\Render\*\Applications\*` and the modern
`HKCU:\...\Internet Explorer\LowRegistry\Audio\PolicyConfig\PropertyStore`) for anything
referencing StarCraft after muting/unmuting a real session -- found nothing in either.
Not an exhaustive proof, so `-Sound` calls `Set-ScProcessMuted -Mute $false` explicitly
rather than just skipping the mute call, as cheap insurance against a persistence path
this search did not find.

This replaced an earlier registry-based approach (`HKCU:\SOFTWARE\Blizzard
Entertainment\Starcraft` `music`/`sfx`, save-before/restore-after) that wiped a real
user's entire StarCraft settings key on its first live run via an unguarded `New-Item
-Force` against an already-existing key -- see `run-with-plugin.ps1`'s "Sound" section for
the full incident writeup. AGENTS.md hard rule 5 governs live user state as a direct
result: that key is written only between `tools/sc-registry-baseline.ps1 -Save` and
`-Restore`, except `Custom Type`, which `run-with-plugin.ps1` sets on every agent launch and
leaves set (AGENTS.md § "Game Type / `Custom Type`").

## Re-deploy

```powershell
./tools/deploy.ps1
```

Same command every time. Pulls whatever plugin source is on disk in this checkout and
whatever game state is currently in the working copy.

## Remove

```powershell
Remove-Item "$env:USERPROFILE\Desktop\StarCraft Modded.lnk" -Force
Remove-Item C:\decompile-sc-data\sc-deploy\starcraft-modded -Recurse -Force
```

Nothing else to undo: the deployed `StarCraft.exe` was never written to (it's a mirror of
the working copy, itself never written to by the injection path -- see
`tools/plugin/README.md` "Uninstall"), and nothing outside `<DeployRoot>` and the one
shortcut file was touched. (The shared lock file at `C:\decompile-sc-data\sc-work\logs\sc-launch.lock` is
not deploy-specific -- leave it; it is reused by every future launch/deploy.)

## Debug / off-switch

The Goal for this task is zero-argument play, so there's deliberately no second desktop
shortcut for debugging -- use one of these one-liners instead, same three off switches
`tools/plugin/README.md` documents for the dev flow, applied to the deployed copy. **All
three pass `-Sound`** where relevant -- without it you would be muting the user's own
install, since `run-with-plugin.ps1` is silent by default (see "Sound" above):

```powershell
# 1. Cleanest: launch the deployed game with nothing of ours injected at all (inherently
#    audible -- nothing of ours runs, so there is nothing to mute).
Start-Process 'C:\decompile-sc-data\sc-deploy\starcraft-modded\game\StarCraft.exe'

# 2. Plugin attached but passive (read-only observer, writes nothing to game memory) --
#    useful for confirming the deployed binaries load without the fan-out/circles/HUD
#    hooks in the way. -Sound because this goes through run-with-plugin.ps1.
pwsh -File 'C:\decompile-sc-data\sc-deploy\starcraft-modded\plugin\run-with-plugin.ps1' `
    -GameDir 'C:\decompile-sc-data\sc-deploy\starcraft-modded\game' `
    -BuildDir 'C:\decompile-sc-data\sc-deploy\starcraft-modded\plugin' `
    -Mode observe -InjectWindowedHelper WMode -Sound

# 3. Never leave a game process running (hard rule) -- close it politely so the plugin's
#    DETACH/STATS line gets written:
pwsh -File 'C:\git\decompile-sc\tools\plugin\close-game.ps1'
```

## Verified

- `./tools/deploy.ps1` run repeatedly back to back: robocopy pass copies 0 files/0 dirs
  once nothing has changed, plugin binaries and shortcut rewritten identically --
  idempotent.
- **A real single-player save**, not a proxy marker: played live into the `Enslavers02b`
  campaign mission, saved via the in-game menu (typed the name through posted `WM_CHAR`
  messages, avoiding the game's hotkey dispatcher) as `save\asdf\task018.snx` (230,707
  bytes), redeployed twice, sha256 identical both times. `characters\` and
  `Maps\Replays\` markers planted earlier in the same round also survived both redeploys,
  all three classes proven together in the same runs -- this is the round-2 acceptance bar
  ("a real save survives two deploys"), not the round-1 proxy-marker test it originally
  shipped with.
- `-DeployRoot` pointed inside the repo, under `C:\git`, under `C:\decompile-sc-data\sc-work`, under the
  source working copy, and under `C:\decompile-sc-data\sc-install` all refuse before touching disk. Also
  refuses a device-prefix (`\\?\C:\decompile-sc-data\sc-install\Starcraft\evil`) and an 8.3-short-name
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
- Launch lock: unit-tested the exclusive-handle acquire/release directly (a second
  acquire attempt from the same process is correctly blocked; killing the holding process
  releases it immediately, with no staleness handling needed), then a real end-to-end
  launch through the actual script showing acquire -> launch -> release. Also verified
  `-NoLaunchLock` and the absence of `$env:AGENT_TASK` each independently skip the lock
  entirely.

### Known limitation: the running-game guard checks by name, not by path

The natural check for step 3 above is "is StarCraft running *from `<DeployRoot>`*
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
