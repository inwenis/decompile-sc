---
from: conductor
to: user
sent: 2026-08-16T07:20:56Z
subject: Kill + cleanup: nothing to kill (they already exited), dirs clear on reboot; root cause = statusline, issue conductor-hq#251
---

Ran the kill and the cleanup. **Neither the kill nor the prune could do anything — and the reason is the interesting part. One thing I told you earlier was wrong, correcting it below.**

## 1. The kill: there is nothing to kill

Those 64 `pwsh` processes **have already exited.** They are retained process objects, not running programs.

1. `Get-Process pwsh` lists them → looks alive.
2. `Get-Process -Id <pid>` and `Stop-Process -Id <pid>` → `Cannot find a process with the process identifier`.
3. `taskkill /PID <pid> /F` → `There is no running instance of the task`.
4. `OpenProcess` succeeds, and `GetExitCodeProcess` returns a real exit code — **not** `STILL_ACTIVE` — for all 64.
5. `TerminateProcess` called directly on all 64: **0 terminated, 64 already exited.**

I checked `Get-Process StarCraft` in the same breath before each attempt (rulebook rule) — 0 running, before and after.

**Correction to my earlier message: they are NOT holding 2.9 GB of RAM.** That figure was the working set Windows still reports for a dead process — a stale last-known value. Real memory right now: 15.4 GB total, 5.7 GB free. The zombies cost you kernel bookkeeping, nothing more. I should have checked `HasExited` before quoting the number.

## 2. The cleanup: blocked by those same dead processes

A retained process object still pins its working directory, and a directory that is some process's cwd cannot be deleted on Windows. I read each one's current directory out of its PEB — 11 of the 64 sit exactly on your seven stranded dirs:

```
  1116  C:\git\decompile-sc-task052      64844  C:\git\decompile-sc-task059
 45288  C:\git\decompile-sc-task055      87080  C:\git\decompile-sc-task062\tools\plugin
 32644  C:\git\decompile-sc-task056      97244  C:\git\decompile-sc-task062\tools\plugin
 51424  C:\git\decompile-sc-task057      98156  C:\git\decompile-sc-task062\tools\plugin
 54344  C:\git\decompile-sc-task057     103972  C:\git\decompile-sc-task062\tools\plugin
109812  C:\git\decompile-sc-task066
```

Confirmed it is a real pin and not NTFS delete-pending: `Remove-Item`, `Rename-Item` and `cmd /c rmdir` all fail, while creating a file *inside* the same directory succeeds.

**They clear on reboot.** After you next restart the machine, one command finishes it:

```powershell
cd C:/git/decompile-sc; ./scripts/prune-worktrees.ps1 -Force
```

Nothing depends on this. Seven directories, six empty, one holding 3.3 MB whose contents I already verified are a strict subset of what is committed.

## 3. How we ended up with them — and yes, issue opened

Not dead worker shells. **Statusline processes.**

| command line | count |
| ------------ | ----- |
| `pwsh -NoProfile -File C:/git/conductor/config/worker-statusline.ps1 -RepoRoot ...` | 48 |
| `pwsh -NoProfile -File C:/git/decompile-sc/config/worker-statusline.ps1` | 14 |
| a temp `wrapper-log-fixture` script | 2 |

`config/worker-settings.json` wires the statusline as a `pwsh` command. The harness runs it **once per status render**, inheriting the session's cwd — for a worker, its worktree. So every render is a fresh `pwsh` sitting in the worktree, and each retained one pins that worktree permanently. All 64 date from 08-12 and 08-13, the two heaviest worker days.

The retention is a harness-side handle leak, not ours. **The cwd is ours, and it is the half that does the damage.**

Issues:

1. [conductor-hq#251](https://github.com/inwenis/conductor-hq/issues/251) — the fix. Three options in the body; the cheap one is making `worker-statusline.ps1` `Set-Location` off the worktree on its first line, so a retained process pins `C:\` instead of something we want to delete.
2. [decompile-sc#84](https://github.com/inwenis/decompile-sc/issues/84#issuecomment-5306293554) — commented with the root cause. Its own warning text ("a shell whose cwd is inside it, an editor, antivirus") is what sent this hunt after a live holder that does not exist; worth fixing `prune-worktrees.ps1` to say `blocked by N exited-but-retained processes (clears on reboot)`.

## 4. Board unchanged and still parked

0 open tasks, 0 open PRs, 0 live workers, conductor inbox empty, `main` in sync with `origin/main`.
