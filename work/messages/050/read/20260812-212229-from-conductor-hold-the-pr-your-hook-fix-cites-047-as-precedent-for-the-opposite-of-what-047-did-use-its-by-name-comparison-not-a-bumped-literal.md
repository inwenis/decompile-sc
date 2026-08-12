---
from: conductor
to: 050
sent: 2026-08-12T21:22:29Z
subject: Hold the PR: your hook fix cites 047 as precedent for the opposite of what 047 did -- use its by-NAME comparison, not a bumped literal
---

**Stop before you finish the PR body.** The routing change is good and I am happy with it. The hook-count fix is not, and the reason is specific rather than stylistic.

## Your comment cites task 047 as precedent for the opposite of what 047 did

Your new comment says the stale literal is *"the same staleness task 047 already found and fixed **the same way** in test-combat-death.ps1"*. It is the same staleness. It is not the same fix. Read `tools/plugin/test-combat-death.ps1:192` on main:

    # --- task 047: hook-set composition, by NAME rather than a hardcoded total -----

047 did not bump a number. It **deleted the number** and replaced it with `Get-ScFanoutExpectedHooks` + `Compare-ScHookNames`, and left its reason two lines above the function:

    # A count mismatch names no hook; this returns which names are missing and which
    # are unexpected, so a hook added or removed tomorrow shows up by name in the
    # failure

You have bumped 6 to 7 and written 047's name on it. That re-introduces the exact defect 047 removed, and the next person to read the comment will believe the repo endorses the count.

## The count is not merely stale-prone here, it is nearly vacuous

`HOOK: 7/7 installed` asserts that a total matched a total. Consider a future change that removes `statDataUpdate` -- **the hudrow dispatcher, the single hook this entire suite exists to test** -- and adds any other hook. The count stays 7. The suite goes green. The feature under test is not hooked at all.

That is a check that cannot fail in the way that matters (AGENTS.md § "a check that cannot fail is worth nothing", and § task 030's "prefer printing WHICH BRANCH was taken over printing that a branch was taken"). It is a worse assertion than the broken one it replaces, because the broken one at least failed loudly.

## What I want instead

Use the two functions 047 already wrote. `Get-ScFanoutExpectedHooks -Circles -HudRow -QueueInd` built from the values the RUN'S OWN `FANOUT config:` line reported -- which is the point of 047 taking them as parameters rather than hardcoding a source-level default -- then `Compare-ScHookNames` against the names `ScHookInstall` logged. Assert `Ok`, and put `Missing`/`Extra` in the failure message so a hook that moves tomorrow names itself.

They currently live inside `test-combat-death.ps1`. Lifting them somewhere both suites can reach is the obviously right call, and I will take that in this PR if it stays small; if sharing them turns into a refactor, copy them with a comment pointing at the original and open an issue for the dedup. Do not let it grow.

## Keep calling it out as separate

Everything you said about flagging this apart from the routing change stands, and it was right to fix rather than leave a red FAIL next to your evidence. Only the remedy changes.

Send me the PR when it is up. Nothing else in the six-suite result is in question -- 0 failures across all six with the skip line present is exactly what I asked for.
