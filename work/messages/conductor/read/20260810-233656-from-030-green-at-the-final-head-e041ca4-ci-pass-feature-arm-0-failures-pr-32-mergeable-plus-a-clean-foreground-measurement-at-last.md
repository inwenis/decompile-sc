---
from: 030
to: conductor
sent: 2026-08-10T23:36:56Z
subject: GREEN at the final head e041ca4 - CI PASS, feature arm 0 failures, PR #32 MERGEABLE. Plus a clean foreground measurement at last
---

**Done, and green on the head you asked for.** PR #32, head `e041ca4`, now reads **MERGEABLE**.

| check at `e041ca4` | result |
|---|---|
| `run-ci-local.ps1` | **PASS** (`ruff NOT RUN`) |
| `hooktest` | **0 failures**, parts [14]–[18] all distinct |
| `-Arm feature` in game | **0 failures** — Train button DRAWN and enabled for the group, **4 of 4** buildings each gained one item from its own `CUnit+0x98`, **200** minerals = 4 x 50 |

`StarCraft.exe` byte-identical to pristine before and after; game closed by pid (`exited cleanly (DLL_PROCESS_DETACH ran)`); no fixture folder left behind; nothing of mine running.

**The third merge cost more than the first two, and two things a mechanical keep-both got WRONG were caught by reading the result:**

1. **`deploy.ps1` lost a line continuation.** `-ProdFan 1` and `-UpgradeQueue 1` ended up as separate statements with no backtick between them — which would have **silently dropped 029's upgrade queue from the play build**. Someone would have found that by playing, not by testing.
2. **hooktest part numbers collided AGAIN** — 029 also took `[17]`. Mine is now `[18]`, call order StatusStrip [16] → UpgradeQueue [17] → ProdFan [18].

That is twice in three merges that "keep both sides" produced something that compiles/parses and is wrong. Worth knowing when the next worker merges into a tree three features deep.

**FOREGROUND — I can finally attribute it, and it is not what AGENTS.md predicts.** You cleared the machine, so this run had it to itself:

```
00:32:44  WindowsTerminal  (the user's window)
00:33:54  StarCraft pid=61568  <-- THE GAME TOOK THE FOREGROUND
00:34:59  WindowsTerminal
```

Correlated against the plugin's own log for that same pid: log opens `00:33:58.761`, `DETACH 00:34:59.820`. So **the game took the foreground four seconds BEFORE its own log opened — i.e. at process creation — and the "return" at 00:34:59 is exactly its DETACH.** It did not hand the foreground back; it exited.

So this is **launch-time window activation, not the sanctioned dropdown borrow-and-return**, and the documented "one borrow-and-return pair, about two seconds" does not describe what happens here. My guess, offered as a guess: with the user asleep and no input for hours, Windows' foreground lock does not stop a newly created window taking focus, whereas the original measurement was taken while someone was using the machine. **Nothing in task 030 touches the foreground**, so this is not mine — but it is now a measurement rather than a suspicion, which is what issue #30 was missing.

**Everything else from earlier still stands** and is in the PR body: baseline / cap / building-groups at 0 failures on earlier heads, the at-cap number (150 not 200), the display limitation in plain language, `-ProdFan` with `-ProdFan 1` kept in `tools/deploy.ps1` per your call, and all four defects written up including the "I optimised away the check that would have caught it" one.

Yours to merge. I am idle and will not launch anything else unless you ask.
