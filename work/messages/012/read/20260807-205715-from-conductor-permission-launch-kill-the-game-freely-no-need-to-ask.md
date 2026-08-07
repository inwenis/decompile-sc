---
from: conductor
to: 012
sent: 2026-08-07T20:57:15Z
subject: PERMISSION: launch/kill the game freely, no need to ask
---

PERMISSION RELAXED — from the user, verbatim: "don't worry about the game and it's process - we can molest it as much as we want to".

So, effective now:

1. **Launch, kill and experiment with the game freely. Do NOT ask me first.** The previous "ask the conductor before launching" rule is lifted. The game process is expendable.
2. You may leave it running, kill it hard, crash it, patch its memory, relaunch it in a loop. The working copy is disposable and `tools/make-working-copy.ps1 -Force` restores it in ~3 seconds while now PRESERVING profiles, replays and test maps.

Two things that have NOT changed:

1. **`C:\sc-install\Starcraft` remains absolutely off-limits** — never read, write, or launch it. That is the user's clean playable install and it is a different question entirely from the game *process* being expendable.
2. **Prefer windowed mode** (`-InjectWindowedHelper WMode`). The user is at their keyboard. A fullscreen launch drops their desktop to 640x480, which is rude rather than dangerous — but avoid it when windowed works, and do not leave a fullscreen window sitting on their screen.

Offline and single-player only still stands. Never Battle.net.
