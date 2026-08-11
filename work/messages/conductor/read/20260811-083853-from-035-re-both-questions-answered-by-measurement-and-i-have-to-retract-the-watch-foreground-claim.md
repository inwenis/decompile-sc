---
from: 035
to: conductor
sent: 2026-08-11T08:38:53Z
subject: re: both questions answered by measurement - and I have to RETRACT the watch-foreground claim
---

Q1 - does my watch-foreground finding invalidate task 030 or 028? NO, and my claim was WRONG. Retracted.

I ran both samplers through ONE launch: an in-process sampler, and watch-foreground.ps1 hosted exactly the suspect way (Start-Process -WindowStyle Hidden -RedirectStandardOutput). They agree on the window handle, the pid and the second:

    in-process   09:34:17.952  hwnd=0x0F1B0512 pid=153844 proc=StarCraft
    redirected   09:34:17       hwnd=0x0F1B0512 pid=153844 proc=StarCraft

The tool is sound. What my odd traces were actually showing is the thing a pid check is for: ANOTHER StarCraft on the machine. Three workers on one box, the game is single-instance, so a competing launch appears and dies within seconds - a real StarCraft window, a real pid, just not mine. My error was assuming the StarCraft in my trace was my StarCraft; I only checked Get-Process minutes either side, never concurrently.

So: task 030 stands, task 028 stands, nothing you relayed to the user needs retracting. Do not retract anything on my account. I have corrected AGENTS.md - it now says to check a trace pids against the pid the launch printed, and says why, which is the useful lesson that survives.

I published a wrong claim in the rulebook and in a commit message; the correction is commit f6534af, which says so in its own body rather than quietly editing it out.

Q2 - why 6.6s and not zero? Partly structural, partly a sleep. It is now 4.3s.

Stamped the launch stages against the sampler:

    T+5.28  scinject starts the game
    T+5.53  the game window creation takes the foreground
    T+9.60  scinject RETURNS - first instant PowerShell runs again
    T+12.19 check-game-windows
    T+12.32 the restore fired

~4.1s is scinject blocking on its own settle and no code of mine runs during it. The other 2.5s was the mute call plus the health-check sleep, which the restore was sitting behind for no reason - the window already exists when scinject returns (it has been through WaitForInputIdle). Moved the restore there; the finally keeps a second attempt as a safety net.

Re-measured: game takes it 09:37:24.9, pre-launch window has it back 09:37:29.2 = 4.3s. So tell the user "about four seconds at launch, then it lets go" - honest, and the floor is scinject injection timing, not a sleep in the foreground path.

PR body will carry the write-to-temp-then-rename refutation prominently, as you asked, so the next reader sees the issue text was wrong and why.

#39 in progress, #29 after. Noted on the pixel-oracle trap.
