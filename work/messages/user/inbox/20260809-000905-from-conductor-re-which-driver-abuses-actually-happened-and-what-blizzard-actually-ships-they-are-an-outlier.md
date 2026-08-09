---
from: conductor
to: user
sent: 2026-08-09T00:09:05Z
subject: re: which driver abuses actually happened, and what Blizzard actually ships (they are an outlier)
---

**The specific cases I was referring to.** The general attack class has a name: **BYOVD — Bring Your Own Vulnerable Driver.** Windows will load any driver with a valid signature, so attackers do not need to sign malware; they ship a legitimately-signed driver that contains a flaw, load it, and use its flaw to act from the kernel. Game anti-cheat drivers are attractive because they are signed, widely distributed, and by design do powerful things like read and write other processes'' memory.

Concrete, documented examples:

1. **Capcom, 2016 — `capcom.sys`, shipped with Street Fighter V.** The driver exposed a way to run arbitrary code in kernel mode, with essentially no caller validation. Capcom pulled it after the backlash, but the signed binary still exists, and it became a standard tool in exploit and cheat toolkits precisely because it is a valid signed key to the kernel.
2. **Genshin Impact, 2022 — `mhyprot2.sys`, its anti-cheat driver.** A ransomware crew loaded it on machines that never had the game installed, and used it to terminate antivirus processes from the kernel, where user-space AV cannot defend itself. Documented publicly at the time by security vendors. This is the cleanest example of the irony: an anti-cheat driver used as a weapon against security software.
3. **The general pattern**, serious enough that Microsoft maintains a **vulnerable driver blocklist** shipped with Windows, specifically to refuse loading known-bad signed drivers. The list exists because this keeps happening.

Related, though not a driver: **ESEA, 2013**, a competitive gaming anti-cheat that was caught shipping a Bitcoin miner in a client update — a trust-abuse case rather than a vulnerability, but the same lesson about what you are consenting to run.

**Does Blizzard ship a kernel anti-cheat? Historically, no — and they are a notable outlier.**

Blizzard''s anti-cheat is **Warden**, in service since roughly 2005 across WoW, Diablo, StarCraft and Overwatch. It runs in **user mode**, inside the game process — the layer-1 memory-and-module scanning I described. It is famous for being aggressive about what it scans, and it caused a privacy argument years ago for exactly that reason, but it is not a ring-0 driver.

The companies that went to kernel drivers are mostly others: **Riot Vanguard** (Valorant, later League of Legends) is the loudest example, loading at boot; **Easy Anti-Cheat** and **BattlEye** are the widely-licensed third-party ones you will find under many shooters.

Two honest caveats on that answer:

1. My knowledge has a cutoff, and anti-cheat is a fast-moving area. I would not stake anything on the very latest Blizzard titles or a recent policy change — if it matters to you, the install directory and the driver list on your own machine are the ground truth, and I can help you look.
2. "User mode" does not mean "harmless to your privacy" — Warden reads game memory and can enumerate what is running. It means the failure mode is different: a Warden bug is not a kernel-level system compromise.

**For your actual case:** StarCraft Remastered is in the Warden family, user-mode. Which does not change my advice — layer 1 is exactly the layer that notices an injected DLL, so the risk to your account stands.
