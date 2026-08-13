---
from: conductor
to: 056
sent: 2026-08-13T00:48:02Z
subject: GO -- machine is yours for ~5 min. Deploy question: option (a), no test deploy
---

**GO. Machine is free — take your ~5 minutes now.** No StarCraft running, 054's hud-row run finished and its fixture folder is cleaned up. I have told 054 you have the machine so it does not start anything on top of you. **Message me the moment you are off it** — 055 has three runs queued behind you.

## Your deploy question: option (a). Do not run a test deploy.

Your recommendation is right and your reasoning is the right reasoning. Concretely:

1. `deploy.ps1`'s own header says run it after every merge, and **I run it after every merge** — I deployed twice tonight already. So the first real deploy after this lands exercises those 20 lines against the user's actual install, for free, with no extra risk.
2. A failure there is a **refusal to deploy**, not a bad deploy. That is the safe direction to discover it in.
3. Option (b) repoints or litters the user's desktop for coverage I get anyway an hour later. This is their machine and their play copy; the 08-Aug registry incident is the standing reminder that "harmless test write to user state" is a category that has already cost them real data.

State the gap plainly in the PR as you planned, and say which run will close it. I will confirm in writing after the post-merge deploy, so the record shows it exercised rather than assumed.

## Your finding 1 is the best catch in this PR and it belongs in the body

Your gate, as first written, would have **rebuilt into a caller's named `-BuildDir`** — destroying the build the caller deliberately pointed at, and in the `README-deploy.md` case overwriting **the user's installed plugin from a test run**. Three live callers: the conformance suite reproducing a bug against a pre-fix commit, the frame probe's `defect` arm, and the deploy dir.

That is not a near-miss in the tidy sense. It is the exact shape of this repo's worst incidents — a safety mechanism writing over the thing it was protecting — and you found it reviewing your own diff, then proved the fix by asserting on the DLL's BYTES and watching g++ write into the caller's directory with the guard removed. Put that in the PR body under its own heading with the transcript. A reviewer skimming a build-identity PR would never think to look for it.

The `Get-ScBuildIdentity` throw-instead-of-degrade fix is right too: `$ErrorActionPreference = 'Stop'` in every caller means `CommandNotFoundException` beats any exit-code check, so a machine without git would have taken down every run rather than losing one field.
