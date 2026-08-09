---
from: conductor
to: user
sent: 2026-08-09T00:03:19Z
subject: re: kernel anti-cheat - why user-space is unwinnable and what the kernel actually buys
---

**The problem with a user-space anti-cheat: it is a peer, not an authority.**

Your anti-cheat runs inside the game process, as your user account. The cheat runs as the same user, with the same privileges. So everything the anti-cheat can do, the cheat can do back:

1. Anti-cheat hashes the game''s code to detect patches → the cheat hooks the hashing function and returns the correct hash.
2. Anti-cheat scans loaded modules for suspicious DLLs → the cheat unlinks itself from the loader''s module list, or never appears there (manual mapping — copying the DLL into memory without asking Windows to load it).
3. Anti-cheat reads memory to look for tampering → the cheat patches the reading routine.
4. Anti-cheat phones home → the cheat is in the same process and can intercept the report before it leaves.

There is no asymmetry. Both sides have identical power, so it reduces to who patched what first and who knows more — and the cheat only has to win once, whereas the anti-cheat has to win every time. That is what I meant by structurally losing.

**What the kernel changes.**

A kernel driver runs in **ring 0**, the privilege level where the operating system itself lives. Your game and every cheat run in **ring 3**, user space. This boundary is one the CPU enforces in hardware, and it is not symmetric:

1. **Ring 0 can read and write any ring-3 process''s memory; ring 3 cannot touch ring 0.** So the anti-cheat can inspect the game and everything around it, and the cheat cannot inspect or patch the anti-cheat back.
2. **It sees the ground truth.** Instead of asking Windows "which modules are loaded" — an answer a cheat can fake — the driver reads the kernel''s own process structures and page tables directly. Manual-mapped code that hid from the loader still occupies executable memory, and from ring 0 you can enumerate that memory.
3. **It gets there first.** A driver loads at boot, long before the game or any cheat, so it is not patching over an environment an attacker has already prepared.
4. **It can watch, not just poll.** The kernel offers notification callbacks — tell me when a process starts, when a thread is created in it, when a driver loads, when a handle to the game is opened. That last one is exactly the `OpenProcess` call we make; a driver can see it happen, or refuse it.

So the fight moves from "two equal programs patching each other" to "one side is above the other, on a line the hardware enforces."

**Why this is contentious, and worth knowing before you cheer for it:**

1. **A game vendor''s driver runs with full system privileges on your machine, permanently.** A bug in it is a system-wide vulnerability — this has happened repeatedly, and vulnerable anti-cheat drivers have been abused BY malware as a way into the kernel.
2. **It usually runs even when you are not playing.**
3. **The escalation continues.** Cheats moved to their own kernel drivers, then to hypervisors below the kernel, and then to hardware — a second PC reading the game''s screen over a capture card, or a DMA card reading memory over PCIe with no software on the gaming machine at all. Each step raises the price rather than ending the contest.

**And the reason none of this touches us:** every layer above exists to police a competitive online game where cheating harms other players. We run 1.16.1, offline, single-player, on your own copy — no server, no opponents, nothing to police. That is not a loophole we are exploiting; it is a genuinely different situation, and it is why I keep the boundary where it is.
