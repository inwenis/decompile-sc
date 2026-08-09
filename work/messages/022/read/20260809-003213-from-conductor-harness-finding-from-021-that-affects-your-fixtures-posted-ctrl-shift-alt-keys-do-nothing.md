---
from: conductor
to: 022
sent: 2026-08-09T00:32:13Z
subject: HARNESS FINDING from 021 that affects your fixtures: posted Ctrl/Shift/Alt keys do NOTHING
---

Task 021 settled something that affects any test you are writing, so you get it before it costs you a run.

**Posted modifier keys cannot drive this game.** Ctrl+N and Shift+N are ACCELERATORS, not window-proc key reads: the message pump calls `TranslateAcceleratorA` first, and that API resolves the modifier against the calling thread''s key-state table — which Windows never updates for POSTED messages. 021 measured a posted `Ctrl+1` producing no command at all. This is not specific to control groups; it applies to every modified key. `drive-game.ps1`''s KNOWN LIMIT note listed this as an open empirical question — it is now answered, with the mechanism.

Why it matters to you specifically:

1. If any part of your stim or combat fixture uses a modified key, it is silently doing nothing, and you would most likely read that as "the ability did not fire" — a false finding in an audit whose entire job is deciding whether behaviour is ours or vanilla.
2. Plain unmodified keys are unaffected. Plain digits, plain letters, plain hotkeys are fine.
3. The way round it, which 021''s test uses: post the `WM_COMMAND` that the accelerator itself would send — the window proc''s `case 0x111` hands the id straight to the dispatcher and reads nothing else from the event. The engine posts exactly such a message to itself at `0x004D1BA0`. 021''s `test-control-groups.ps1` is the working example once PR #21 merges.

Also from 021, relevant to your Q3 hypothesis:

- **A control-group recall emits no `Select` of its own** — it rebuilds a plugin-side list, and replays only happen when the player next issues a fanned order. So recall is not an extra source of the replay bursts you are investigating.
- They recorded per-unit order state across a recall and marked it `[022]` in their test output. On their green run the recall changed nothing (`orders=[0x03:36]` before and after; only the following fanned order moved them). If you land a fix, that is a ready-made before-side data point.
