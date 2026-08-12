---
from: conductor
to: user
sent: 2026-08-12T07:38:01Z
subject: The reboot was Windows Update (KB5121003), not an agent -- Windows names the process itself. And PR #50 is merged.
---

## 1. The reboot was WINDOWS UPDATE. No agent, no subagent, nothing this project runs.

Windows named the culprit itself. System log, **User32 event 1074 at 02:59:17 local**:

> The process `C:\WINDOWS\uus\AMD64\MoUsoCoreWorker.exe` (LAPTOP-ASUS) has initiated the
> restart of computer LAPTOP-ASUS on behalf of user **NT AUTHORITY\SYSTEM** ...
> "Operating System: Service pack (Planned)", Reason Code 0x80020010

That is the Windows Update orchestrator finishing **KB5121003 (2026-08 Security Update)**,
which had been staged since 00:44 local with "a reboot is necessary" already written into the
Setup log. Two further 1074s at 03:02:00 and 03:02:30 are `TrustedInstaller.exe` doing
servicing boots 2 and 3. `Get-HotFix` confirms KB5121003 installed 2026-08-12, and the update
log records "Installation Successful" at 03:05:16.

**Correction to what I told you an hour ago:** I said the boot was ~04:03 your time. It was
**03:03** — the machine is UTC+1, not UTC+2. That matters, because it deletes the gap I
described: the workers' last heartbeats are 02:58:59–02:59:14 and the restart order is
**02:59:17**. Three seconds. They did not stall and then something rebooted; the restart order
landed on four live agents and killed them.

## 2. Every other hypothesis is ruled out, with the evidence

| hypothesis | verdict |
|---|---|
| an agent/subagent asked for the restart | **ruled out** — the only 1074 initiators in the window are MoUsoCoreWorker and TrustedInstaller, both SYSTEM. No pwsh, no agent process, in any of them |
| blue screen / bugcheck | **ruled out** — no BugCheck 1001, no `C:\Windows\MEMORY.DMP`, Minidump folder empty, and all three boots record "last shutdown's success status was true" |
| power cut / battery | **ruled out** — zero Kernel-Power 41, zero EventLog 6008; battery 100%, on AC |
| graphics driver fault from the off-screen rendering | **ruled out** — no Display 4101 (TDR), no driver events at all, 20:00 Aug 11 → 03:10 Aug 12 |
| thermal | **ruled out** — no Kernel-Power 42, no thermal-zone events |
| a scheduled task | **ruled out** — no TaskScheduler events in the window, and the 1074 names the update worker |

## 3. And the specific thing you were afraid of, checked directly

Every match for `Restart-Computer` / `Stop-Computer` / `shutdown.exe` / `InitiateSystemShutdown`
/ `ExitWindowsEx` across this repo and all eight worktrees is a **deny-list entry in the guard
hooks** (`config/guard-destructive.ps1`, `config/worker-settings.json`) — a rule forbidding it,
not a call. Nothing in this project's tooling can reboot your machine.

On task 043's desktop probe specifically, which is the one doing anything exotic that minute:
`sc-desktop.ps1` **deliberately never imports `SwitchDesktop`** (its own comment says so) and
opens desktop handles with an access mask that explicitly excludes `DESKTOP_SWITCHDESKTOP`. It
cannot put the hidden desktop on your monitor, let alone restart anything. It launched the game
12 seconds before Windows Update pulled the rug — that coincidence is the entire source of the
suspicion, and it is a coincidence.

## 4. Meanwhile: PR #50 is MERGED, on your instruction

https://github.com/inwenis/decompile-sc/pull/50 — squash-merged into main, task 042 closed.

The merge script has a receipt path built for exactly this outage (`-LocalCiReceipt`), so it
verified the local run against the PR's head commit rather than being bypassed. It also printed
what the local gate does NOT cover: `ruff` (not installed on this machine). Everything else ran:
77 Pester tests, the game-content guard, 21 hooktest parts, hooktest 0 failures.

**One honest caveat, recorded on the PR itself before I merged.** That PR's "the upgrade
indicator still shows, `ink=608`" line does not prove what it says. 039 measured this morning
that `ink` **cannot fail** in that dialog — the pane's own artwork sits in the same surface the
probe counts, so it read `ink=448 of 448` inside the indicator's box *before anything of ours was
drawn*. Third check in this project that could not fail (after the pixel hash and the nine-pixel
text box). The merged fix itself is in a different file and is properly proven; it is that one
secondary sentence that was hollow, and it is now flagged in the PR rather than left standing.
039 is landing a real oracle (a difference against a hidden-state baseline) and writing the
lesson into AGENTS.md.

Your GitHub billing still needs fixing whenever you get to it — I am merging on the local gate
until then, and saying so on each PR.
