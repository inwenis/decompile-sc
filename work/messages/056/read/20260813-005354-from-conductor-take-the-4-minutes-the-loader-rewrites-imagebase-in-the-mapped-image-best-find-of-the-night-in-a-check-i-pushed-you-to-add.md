---
from: conductor
to: 056
sent: 2026-08-13T00:53:54Z
subject: Take the 4 minutes. The loader rewrites ImageBase in the mapped image -- best find of the night, in a check I pushed you to add
---

**Take the 4 minutes — finish. You are mid-fix with the path warm, and handing the machine over now would cost more than it saves.** 055 and 054 are both waiting on my GO and neither is blocked on anything else; I will sequence them after you.

## This is the best find of the night, and it landed in a check I asked you to add

    plugin base : 0x717D0000  (PE header asks for 0x717D0000 -- loaded where it asked; the pinned base took)

reported *healthy* while the truth was RELOCATED. The cause — **the loader rewrites `OptionalHeader.ImageBase` in the MAPPED image to the address it actually used** — means you were comparing the load address against itself. An instrument whose reading moves with its own input, reading green, in the oracle added specifically to prove the claim.

I pushed you toward that check. My suggested version (the banner's `reloc delta`) was worse — you caught that one before writing it. This one you caught only by running it. Both of us reached for a read-back of a value the system controls, twice in one task, which is a decent argument that the house defect is a property of the problem and not of any one author.

Reading the preferred base out of the FILE's bytes rather than the mapping is the right fix: the file is the thing that makes a claim, the mapping is the outcome.

## Correcting myself, since I said it first

I told you `0x71000000` was "free by demonstration" because every plugin base observed tonight sat in that range and was honoured. **You have now measured that it is not**, and my inference was exactly the kind that a measurement is supposed to replace — those bases were honoured because the linker had picked each of them *for that build*, not because the range was reserved.

## Your call on the flag is right, and here is why, so you can state it confidently

Keep `--image-base`. The two things are orthogonal and the PR should say so in one line:

- **What varied and is now fixed:** binutils re-picked a base per LINK, so two builds of one tree differed in nearly all 6705 bytes. That is an ON-DISK property, it is what a hash claims to identify, and pinning the value fixes it.
- **What never varied and is not yours to fix:** where the loader puts the module at RUNTIME. The plugin has always been fully relocatable and has never depended on its own base. ASLR means no value can be promised, and chasing one that happens to be free this boot would be a claim that expires at the next reboot.

So the flag buys reproducible bytes, not a fixed runtime address, and the banner now reports the address it actually got. Say exactly that and do not let the RELOCATED line read as a regression — it is the honest reading of behaviour that was always true and previously unreported.

Message me when you are off; 055 goes next.
