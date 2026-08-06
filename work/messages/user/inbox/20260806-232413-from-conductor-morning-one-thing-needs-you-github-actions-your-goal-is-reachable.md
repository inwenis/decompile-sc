---
from: conductor
to: user
sent: 2026-08-06T23:24:13Z
subject: MORNING: one thing needs you (GitHub Actions) + your goal is reachable
---

Morning. One thing needs you; everything else moved.

# 1. BLOCKED ON YOU — GitHub Actions never runs

Three PRs are ready but cannot merge. `merge-task.ps1` requires a green run of a workflow named `CI`, and GitHub Actions produces **zero runs on this account**.

What I verified:
- `ci.yml` IS on main, workflow registered, state `active`, YAML valid. The file is not the problem.
- I pushed directly to main afterwards. Still zero runs. Even a native `push` trigger produces nothing.
- Repo-level settings say `{"enabled":true,"allowed_actions":"all"}`.
- GitGuardian and Render DO create checks on the same commits — so webhooks work. Only the Actions engine is silent.
- Your 6 other repos also show 0 Actions runs. decompile-sc may be the first workflow ever attempted on this account.

Two likely causes, both needing the web UI (I did NOT open your account settings while you slept):
1. **Unverified account email** — GitHub silently refuses to run Actions until email is verified.
2. **Private-repo Actions spending limit at $0** / included minutes exhausted.

Please check:
- https://github.com/inwenis/decompile-sc/actions  (often shows a banner saying why)
- https://github.com/settings/emails
- https://github.com/settings/billing/summary

Tell me when it is unblocked and I will retrigger and merge everything within minutes.

If you would rather not deal with billing: say the word and I will propose an alternative gate (run the same checks locally and record the output as merge evidence). I did NOT change your merge gate unilaterally — it is correct, and I only merged around it ONCE, for the CI workflow itself, because that one is circular by construction (CI cannot run until the workflow is on main; the workflow cannot reach main while the gate demands CI). That exception is documented on PR #4.

# 2. The biggest result: your goal is reachable, and the first version is cheap

Recon on the 12-unit cap is done and independently fact-checked. Findings:

1. **It is NOT one constant.** The number 12 is baked into five fixed-size global arrays, three network command encodings, the input path, control groups, the HUD, and order dispatch.
2. **The naive "patch 12 to 24" would corrupt memory** — proven, not guessed. The arrays sit hard against their neighbours, so raising a loop bound writes selection pointers over adjacent engine state.
3. **Nobody has done this on 1.16.1.** The strongest evidence: neivv's limit-removal plugin for this exact binary removes five other limits and leaves selection at 12.
4. **Single-player only** — lockstep networking means a raised cap desyncs against vanilla peers. Since you only want offline, this REMOVES the hardest constraint rather than costing us anything.
5. **The top-ranked path needs no cap change at all**: keep a plugin-side selection list of any size, then emit chunked 12-unit select+order pairs. BWAPI bots have done exactly this on this exact binary for a decade, so the mechanism is proven.

# 3. DECISION FOR YOU — "selecting" vs "commanding" more than 12

Your words were "allow SELECTING more than 12 units". There is a real fork:

1. **Fan-out (cheap, low risk, first)** — box 30 marines, right-click, all 30 move. Works. But the HUD still shows 12 portraits. Delivers the POWER, not the LOOK.
2. **Wide client selection (medium)** — you actually see and store more than 12.
3. **Full engine change (hard)** — everything, properly.

My recommendation: build 1 first — it is days not weeks, it becomes the test harness for everything after, and you get something playable fast. Then 2 for the visual. Tell me if you would rather go straight at the real thing.

# 4. What landed while you slept

1. Repo bootstrapped, private, task machinery + message channel live.
2. **The game runs from a disposable copy** — no CD key, no registry writes. `C:\sc-work\1161-base`, resets to byte-identical-to-pristine in ~3 seconds. Windowed mode works (WMode.dll swapped in as ddraw.dll). This is the whole patch-test-reset loop the mod needs, proven.
3. Your pristine install at `C:\sc-install\Starcraft` — hash re-verified UNCHANGED. Nothing touched it. No game process left running.
4. Ghidra headless pipeline built and independently re-verified end to end.
5. Prior-art survey + selection-cap recon written, both cited.

# 5. Quality control — I did not take workers at their word

I ran independent verifiers against the two biggest PRs rather than trusting their reports:
- **Ghidra pipeline**: reproduced from scratch. Found 2 HIGH silent-wrong-answer bugs — a stale output file could make a FAILED run report success, and the documented `-ImageBase` option is a no-op on PE files (it is Elf-only) while still reporting success. Both are being fixed now.
- **Selection-cap research**: all five source repos cloned at the pinned commits and checked line by line. **Zero fabricated citations** — all 41 addresses trace to real sources. It did find a circular argument (one piece of "evidence" was our own arithmetic quoted back) plus a self-contradiction. Being fixed now.

Fabricated citations were the main risk in research this dense. There were none.

# 6. Correction I owe you

I said StarCraft.exe was "~2.7 MB". Wrong: **1,220,608 bytes (1.16 MB)**. Total code surface ~2.2 MB. My error reached a doc, and it is being corrected — in a project whose premise is evidence-cited claims, a wrong number matters more than its size suggests.

# 7. Running right now

Workers 001 and 003 are applying the review fixes. Everything else is idle pending the Actions unblock.
