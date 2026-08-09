---
from: conductor
to: user
sent: 2026-08-09T00:14:07Z
subject: re: ESEA 2013, and why revoking Capcom's signature is harder than it sounds
---

**ESEA, 2013 — the anti-cheat that mined Bitcoin on players'' machines.**

ESEA ran a competitive Counter-Strike league whose anti-cheat client you had to install to play — software with deep access to your machine, which is the whole point of anti-cheat.

In April 2013 an employee added **Bitcoin mining code** to that client. The account at the time was that it started as an internal experiment, and it ended up in a public release. It ran on players'' machines for roughly two weeks, using their GPUs to mine for the company. Players noticed the way you would expect: fans screaming, GPU pegged at full load while idle, cards running hot.

The aftermath:

1. ESEA admitted it publicly, said the mined amount was small (a few thousand dollars'' worth of Bitcoin), and donated it — doubled — to charity.
2. It settled with the **New Jersey Division of Consumer Affairs** in 2013, in the region of **$1 million**, most of which was suspended contingent on compliance.

Treat my exact figures as approximate — the shape of the story is solid, the numbers I would want you to check.

**Why it is the canonical cautionary tale:** nothing here was a vulnerability. The software did exactly what it was built to do — run privileged code on many machines — and the trust was abused by the vendor''s own side. That is the risk you accept with every anti-cheat, and it is qualitatively different from "this driver has a bug."

**Why Windows does not simply invalidate the Capcom signature.**

Several reasons, and together they explain why BYOVD survives:

1. **Revocation is blunt.** A certificate signs everything a company ships. Revoke it and you break the legitimate software too — the actual game, other titles, unrelated products. You are punishing every user of every product signed with that key to kill one bad driver.
2. **Microsoft does not own the certificate.** It is issued by a certificate authority to the vendor. Microsoft can pressure, but the revocation lever belongs to the CA and the vendor.
3. **Timestamped signatures survive revocation by design.** Code signing normally includes a trusted timestamp so that software signed today keeps working after the certificate expires — otherwise every program would rot on a schedule. The side effect is that revoking a certificate does not automatically invalidate binaries already signed and timestamped with it.
4. **Kernel driver loading cannot depend on the network.** Checking a revocation list at boot means an online lookup before you have networking, on a path where failure means an unbootable machine. So historically that check was not performed at load.

**What Microsoft actually does instead: block by file hash.** Windows ships a **vulnerable driver blocklist** — a list of specific known-bad driver binaries, refused at load regardless of their valid signature. That is precise (it kills `capcom.sys` without touching anything else Capcom signed) and needs no cooperation from the vendor or the CA.

The catch, and the reason this class of attack persisted for years: **the blocklist was not enforced by default on most systems.** It is tied to features like memory integrity (HVCI) and Smart App Control, which historically were off on typical consumer installs. Newer Windows versions turn it on for more people, which is why this attack has become harder rather than impossible.

Worth checking on your own machine if you are curious — memory integrity is a switch in Windows Security under Device Security, and it is the setting that most directly governs this. It occasionally conflicts with older drivers, which is precisely why it was not universally on.
