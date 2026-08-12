# Task 044 — what restarted the laptop at 2026-08-12T02:03:01Z

Read-only forensics, run 2026-08-12 07:26–07:32Z. Nothing on the machine was
modified. Local time is **UTC+1** (GMT Standard Time, currently BST) — every row
below carries both.

## Verdict

**Windows Update restarted the machine. No agent, no subagent, and nothing this
repo runs was involved.** Windows names the initiating process itself: User32
event 1074 at 01:59:17Z records
`C:\WINDOWS\uus\AMD64\MoUsoCoreWorker.exe` — the Update Orchestrator — acting on
behalf of `NT AUTHORITY\SYSTEM`, reason *"Operating System: Service pack
(Planned)"*, code `0x80020010`, finishing the install of **KB5121003 (2026-08
Security Update)**.

The four workers did not stall and then get rebooted: their last heartbeats are
01:58:59–01:59:14Z and the restart order is **01:59:17Z**. Three seconds. The
shutdown killed the agents.

## Timeline

| local (UTC+1) | UTC | log / id | what it says |
| --- | --- | --- | --- |
| Aug 11 00:41:24 | 23:41Z | Setup 1 | KB5121003 Staged → Installed initiated (UpdateAgentLCU) |
| Aug 12 00:44:25 | 23:44Z | Setup 4 | "A reboot is necessary before package KB5121003 can be changed to the Installed state" |
| 02:58:00 | 01:58:00Z | file mtime | worker 043's last write (`probe-cross-desktop-input.ps1`) |
| 02:58:59–02:59:14 | 01:58:59–01:59:14Z | agent heartbeats | all four workers, last sign of life |
| **02:59:17** | **01:59:17Z** | **User32 1074** | `MoUsoCoreWorker.exe` initiated the restart on behalf of `NT AUTHORITY\SYSTEM`; "Operating System: Service pack (Planned)", reason `0x80020010` |
| 03:00:43 | 02:00:43Z | Kernel-Power 109, Kernel-General 13 | reboot transition, OS shutting down |
| 03:00:49 | 02:00:49Z | Kernel-General 12, Kernel-Boot 20 | servicing boot 1 of 3; last shutdown's success status = true |
| 03:02:00 / 03:02:30 | 02:02:00Z / 02:02:30Z | User32 1074 ×2 | `TrustedInstaller.exe`, "Operating System: Upgrade (Planned)" `0x80020003` — servicing reboots 2 and 3 |
| 03:02:51–03:03:01 | 02:02:51–02:03:01Z | Kernel-General 12, Wininit 12 | final boot; matches `LastBootUpTime` 02:03:01Z |
| 03:03:06 | 02:03:06Z | Setup 2 | "Package KB5121003 was successfully changed to the Installed state" |
| 03:05:16 | 02:05:16Z | WindowsUpdateClient 19 | "Installation Successful: 2026-08 Security Update (KB5121003)"; `Get-HotFix` confirms InstalledOn 2026-08-12 |

## Ruled out

| hypothesis | evidence |
| --- | --- |
| an agent/subagent asked for the restart | **out** — the only 1074 initiators in the window are `MoUsoCoreWorker.exe` and `TrustedInstaller.exe`, both SYSTEM. No `pwsh`, no agent process, in any 1074. (An unrelated 1074 at Aug 11 23:41 local is `Explorer.EXE` on behalf of `laptop-asus\inwen` — the user's own earlier restart.) |
| bugcheck / BSOD | **out** — no BugCheck 1001; no `C:\Windows\MEMORY.DMP`; `Minidump\` empty; Kernel-Boot 20 reports shutdown success = true on all three boots |
| power loss | **out** — zero Kernel-Power 41, zero EventLog 6008; battery 100 %, `BatteryStatus=2` (on AC) |
| graphics driver fault (TDR) from off-screen rendering | **out** — no Display 4101, no Dxgkrnl/nvlddmkm/amdkmdag/igfx events, 20:00 Aug 11 → 03:10 Aug 12 local |
| thermal | **out** — no Kernel-Power 42, no thermal-zone events; only routine Kernel-Processor-Power 55 capability lines at each boot |
| scheduled task | **out** — no TaskScheduler/Operational events in the window (log queryable, empty there); the "Device Install Reboot Required" task exists but the 1074 names the update worker |
| Windows Update | **IN** — 1074 + Setup-log chain + hotfix record above |

## The repo cannot reboot the machine

Every match for `Restart-Computer|Stop-Computer|shutdown.exe|InitiateSystemShutdown|ExitWindowsEx`
across `C:\git\decompile-sc` and all eight task worktrees (029–043) is a **deny-list
entry**, never an invocation:

- `config/guard-destructive.ps1:173-174` and `:231-232` — hook deny patterns
- `config/worker-settings.json:46-47` — permission deny block
- identical copies in each worktree's `config/`

## Residual risk from task 043's desktop probe: none, by construction

`tools/plugin/sc-desktop.ps1` deliberately never imports `SwitchDesktop` (its own
comment at line 92 says so), and opens desktop handles with access mask `0x00FF`,
which excludes `DESKTOP_SWITCHDESKTOP` `0x0100` (lines 115–122). No code path can
put the hidden desktop on the monitor, let alone restart anything.
`probe-cross-desktop-input.ps1` only posts window messages and reads the plugin
log. Worker 043 launching StarCraft 12 seconds before the update's restart order
is the whole source of the suspicion, and it is a coincidence.

## How this was run, and the process gap it exposed

Executed as an in-session fable **subagent**, not a spawned worker — so it had no
task file, no registry entry and no PR, and therefore never appeared on the
board. The user noticed and asked where it was. Read-only machine forensics is
not code, which is why it did not obviously trip the "every ask gets a task file"
rule; the rule that matters is a different one — **work the user is waiting on
must be visible on the board**, whatever tool does it. This file and
`work/tasks/044-reboot-forensics.md` were written after the fact to close that
gap and to keep the evidence in the repo rather than in a message.
