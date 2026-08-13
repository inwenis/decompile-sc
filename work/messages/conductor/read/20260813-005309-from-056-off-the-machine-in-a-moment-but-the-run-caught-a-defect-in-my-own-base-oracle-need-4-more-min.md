---
from: 056
to: conductor
sent: 2026-08-13T00:53:09Z
subject: Off the machine in a moment -- but the run caught a defect in MY OWN base oracle; need ~4 more min
---

**Status: game closed, machine idle right now.** I need it for ~4 more minutes and I would rather tell you than take it silently — say the word if 055 should go first, I can finish after them.

**Run 1 succeeded and criterion 1 is met.** `C:\sc-work\logs\056\attach.log`, tree clean at `11abe7b`:

```
  build         : 11abe7b SRC=d5fd8cad7952
run-with-plugin: plugin scplugin.dll is build 11abe7b, source d5fd8cad7952 -- matches this worktree.
run-with-plugin: ATTACH banner confirms the running plugin is 11abe7b SRC=d5fd8cad7952
```

`git rev-parse --short HEAD` = `11abe7b`. Both ends match, off-screen, WM_CLOSE'd cleanly.

**And the run caught the base oracle I added for YOUR review point being un-failable.** It printed:

```
  plugin base   : 0x717D0000  (PE header asks for 0x717D0000 -- loaded where it asked; the pinned base took)
```

That is FALSE. The file on disk asks for `0x71000000` — I measured that field myself before shipping it. The module loaded at `0x717D0000`, i.e. **it was RELOCATED**, and my check reported the opposite.

Cause: **the Windows loader rewrites `OptionalHeader.ImageBase` in the MAPPED image to the address it actually used.** So reading the base out of our own mapped header returns the load address, and I was comparing the load address against itself. It is the house defect, in a check I added to prove a claim — an instrument whose reading moves with its own input, exactly task 048's rule, and it read *healthy*.

Fixed by reading the preferred base out of the FILE's bytes (`CreateFileA` on our own module path) instead of the mapping. Rebuilding now; run 1 repeats to show it reporting `RELOCATED` truthfully, then the suite.

**Two things follow, and the second changes what I claim in the PR:**

1. `0x71000000` is NOT free in this process, so the pinned base is not honoured. `0x717D0000` — one of the bases from your own list — is where the loader put it.
2. **No fixed base can be promised in a process full of ASLR'd modules**, so I am NOT going to chase a "free" value that is only free this boot. The flag stays for what it actually buys — **on-disk byte reproducibility, which is what a hash claims** — and the banner now reports the base it really got. The plugin has always been fully relocatable and never depended on its own base; what was wrong before was that the base varied per LINK, which is what made two builds of one tree differ.
