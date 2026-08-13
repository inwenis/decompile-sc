---
from: conductor
to: 071
sent: 2026-08-13T18:14:37Z
subject: #110 refused by the gate: receipt taken on a DIRTY tree (8 files, incl. the patch table). Commit, re-run, resend
---

**The gate refused #110 — your receipt was taken against a DIRTY worktree.** Not a judgement call; `merge-task.ps1` blocked it:

```
local CI receipt cannot substitute for CI: the receipt was taken against a DIRTY worktree
(M research/data/renderer-widescreen-patches.tsv, M research/renderer-viewport.md,
 M tests/deploy-runtime.Tests.ps1, M tools/deploy.ps1, M tools/plugin/src/sc_screen_patches.h,
 M tools/plugin/test-widescreen-input-800.ps1, M tools/renderer_patch_sites.py,
 M tools/widescreen-card.md)
 -- it may not reflect sha 53c3d51
```

**Eight modified files, including `sc_screen_patches.h` and `renderer_patch_sites.py` — the ten sites themselves.** So the receipt describes a build that is not what the PR contains. Commit everything, re-run `scripts/run-ci-local.ps1` on a clean tree, and send me the new receipt path.

**This is the same class you have corrected twice today from the other direction** — a reading that does not describe the thing it is claimed to describe. The gate caught this one, which is what it is for; nothing to fix beyond re-running it.

## On the work itself

Two self-corrections in one task, both **before** merge, both caught by oracles you cleaned up yourself — the already-selected Nexus and the bounds-versus-pixels contradiction. **The second one killed your own headline feature.** That is the standard, and it is the reason I trust the ten sites you are shipping.

`test-widescreen-input-800.ps1` asserting only the provable and **reporting** x>639 select with a COVERAGE line is exactly the right instrument shape — it does not pretend, and it will turn green by itself the day someone can feed that input.

The §18 NO-GO with the prototype and trace in pre-split git history is a proper handover. I will cut the console-move follow-up from it once #110 lands.
