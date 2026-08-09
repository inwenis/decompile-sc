---
from: conductor
to: user
sent: 2026-08-08T23:22:30Z
subject: re: how Battle.net/Remastered anti-cheat can tell - the network frames are the smallest part of it
---

Fair question, and the short answer is: **they are not relying on the network frames to catch a modified client — they are relying on the client to inspect itself, and on the server to judge the results rather than trust the client''s summary.** Four layers, roughly in order of how much they matter:

**1. Client-side integrity scanning (this is the big one).** Blizzard''s long-standing anti-cheat component (historically "Warden") is a small module the server sends down and the client runs. It can read the game''s own process memory and report back: hashes of code regions, lists of loaded modules, scans for known signatures. That is precisely the layer our kind of work would trip — not because we changed the file on disk (we do not), but because at runtime there is an extra DLL loaded and the first bytes of certain functions no longer hash to what they should. The check happens INSIDE your machine; the network only carries the verdict.

**2. Server-side authority over game state.** In a lockstep RTS like StarCraft, every client simulates the same game from the same command stream. Clients exchange orders, not results. So a client that lies about outcomes desynchronises from everyone else immediately and is detectable as an inconsistency, not as a suspicious packet. This is why "map hacks" historically were the popular cheat: revealing information you already possess locally does not desync anything, which is exactly why memory-scanning (layer 1) exists.

**3. Behavioural and statistical detection, server side.** Even with a pristine client, a player whose actions are impossible — perfect reaction times, actions on units they cannot see — is detectable from the command stream alone, offline, after the fact. No client cooperation needed.

**4. Signed binaries and the updater.** Remastered ships through the Battle.net launcher, which checks and repairs the installation. Patching the executable on disk is trivially detectable and self-repairing.

**Why "it is just my computer sending frames" understates it:** true, your machine chooses what to send — but your machine is also running THEIR code, which reads YOUR memory and reports what it finds. Defeating that means lying convincingly to a program running with full access to the process you are lying about, while it changes what it asks for over time. That is a fundamentally different problem from crafting network packets, and it is an arms race with a company that ships updates.

**Which is exactly why we are on 1.16.1 and offline.** Nothing above is a challenge to be worked around here — it is the reason the boundary exists. 1.16.1 offline single-player has none of these layers watching, so our DLL injection is simply a local modification of a local game. The moment the same technique points at Remastered, layer 1 applies and the plausible cost is your account, which is why I asked for an explicit yes before ever queueing that and you sensibly said no.

Curiosity fully warranted — this is genuinely interesting engineering, and understanding it is also what tells you where not to point the tools.
