---
from: 021
to: conductor
sent: 2026-08-09T00:30:27Z
subject: PR #21 open; all three additions in; shift-add is Shift+N and the modifier keys are ACCELERATORS (harness-wide finding)
---

PR: https://github.com/inwenis/decompile-sc/pull/21 (CI green). All three of your additions are in.

**1. New-game reset — done, but WITHOUT a hook.** You suggested hooking or piggybacking
`0x004EEC30`. I piggybacked its *effect* instead: on every `0x13` the plugin reads the engine's own
row for that group, and if it is empty NOW while the plugin has previously OBSERVED it non-empty,
the engine has restarted a game underneath us and the plugin group is dropped. That keeps the
design's "no new hook, no patched byte" property intact and deletes the same class.

The "previously observed" half is load-bearing and I nearly got it wrong: without it, the perfectly
ordinary sequence *Ctrl+1 then Shift+1 before the assign has executed* reads as a restart (the
assign is queued, not applied, so the row is legitimately still zero) and throws the player's group
away. Both cases are asserted in hooktest part [11].

**2. Ordering verified in game, and you were right to insist.** The plugin now logs its raw read of
`activePlayerSelection` at hook time, unconditionally, and the test asserts it every run. Live, on
the green run, with the selection asserted CLEARED in the step before:

```
GROUP recall enter: group=1 activePlayerSelection holds visible=12 [0E5F 0E60 0E59 ...]
                    (read at queueCommand time, BEFORE anything of ours runs)
```

12 post-recall units, not the cleared selection. The claim holds — but it is now checked rather
than assumed, on every run.

**3. Task 022.** Two things for them.

  a. **A recall emits nothing of its own.** It rebuilds a plugin-side list; the replayed `Select`s
     still happen only when the player next issues a fanned order. So recall does not add a new
     burst of replays. Asserted offline (`a recall emits no Select of its own`).
  b. **Order state across a recall is recorded** in `test-control-groups.ps1` output, marked
     `[022]`. On the green run the recall changed nothing: `orders=[0x03:36]` before the box,
     `orders=[0x03:36]` after the recall, and only the following fanned order moved them
     (`orders2` `0x17` -> `0x6D`). If 022 lands a fix, that is the before side.

**Your open question answered: shift-add is Shift+N.** And the finding is bigger than the key.
Ctrl+N and Shift+N are **accelerators**, not window-proc reads: `StarCraft.exe` resource `0x71`
holds Shift+0..9, `Local.dll` resource `0x65`/`0x66` holds Ctrl+0..9 and Alt+0..9, and the message
pump runs `TranslateAcceleratorA` before it dispatches anything. Full table committed as
`research/data/accelerators.tsv`, parsed by a new `tools/parse_accelerators.py`.

**That has a consequence for this repo's whole test harness, so it is worth flagging beyond 021.**
`TranslateAcceleratorA` resolves the modifier against the calling thread's key-state table, which
Windows never updates for POSTED messages — so `drive-game.ps1` **cannot** drive ANY Ctrl/Shift/Alt
accelerator, and a posted `Ctrl+1` was measured producing no command at all. That is not specific to
control groups: it applies to every modified key in the table. `drive-game.ps1`'s KNOWN LIMIT note
called this an open empirical question; it is now settled, with the mechanism.

The way round it, which the test uses: post the `WM_COMMAND` the accelerator itself would send. The
window proc's `case 0x111` hands its id straight to the same dispatcher and reads nothing else from
the event, and the engine posts exactly such a message to itself at `0x004D1BA0`. Stated as a limit
in both the test and the doc: the keyboard-to-accelerator layer is the one thing the automated test
does not exercise. Plain `N` recall needs none of it — plain digits are not accelerators.

**One judgement call I want you to see rather than discover.** This change is visually observable
(24 extra circles and a paged row after a recall) and the standing rule is to attach a screenshot
via `pr-image`. I did not: `pr-image` pushes to a branch in this repo, and a game frame reproduces
game artwork — project hard rule 1. The visual claims are asserted from the plugin's own in-process
read-back instead (`HUDROW show n=36 page=1/3`, `CIRCLES show: 24/24`), the same oracle tasks
014/017 used, and the frames are on disk outside the repo if you want to look. Say the word if you
would rather have the picture.

Regression suites are running now; I will report the results on the PR.
