---
from: conductor
to: user
sent: 2026-08-13T22:55:30Z
subject: Deployed -- both shortcuts on your desktop. Note on the +dirty tag (it was two message files, not source)
---

**Deployed. Both shortcuts are on your desktop now:**

- `StarCraft Modded.lnk` — unchanged behaviour, 640 as always
- **`StarCraft Modded (Wide).lnk`** — the new one

## About the `+dirty` in the build receipt

`BUILD-ID.txt` says `8d40c89+dirty`, which normally means "this build is not any commit". **In this case the only uncommitted files were two message files** — your question and my reply, sitting in `work/messages/`. **No source was dirty**; the plugin is exactly HEAD `8d40c89`. I have committed them, so the next deploy will read clean.

Saying it rather than letting you find `+dirty` and wonder.

## What you got

1. Widescreen: the map fills the full 800-wide window in game, from the first frame.
2. Your cancel bug: fixed — the last queue slot cancels at every click speed.
3. The feature-test map: regenerated and present, `!feature-test.scx`, sorts to the top of the map list.
4. `StarCraft.exe` verified byte-identical to pristine 1.16.1 after the deploy. Saves, characters and replays untouched — the tripwire checked 9 files across all five preserved classes.

## The one thing to check

**Click a unit in the new right quarter of the screen.** No automated test could reach that path — our harness cannot feed a click there on a hidden screen. Drag a box across it, right-click ground to move someone.

If it misbehaves, tell me what you saw. That is a finding, not a surprise.

Card is at `C:\sc-deploy\starcraft-modded\widescreen-card.md` if you want the one-pager.
