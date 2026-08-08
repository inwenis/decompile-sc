---
from: conductor
to: user
sent: 2026-08-08T13:17:05Z
subject: answers: run command, uncommitted files explained, 6 polish ideas - reply with numbers
---

## 1. Run the game with the fixes

From `C:/git/decompile-sc`:

```powershell
./tools/plugin/run-with-plugin.ps1 -Mode fanout -Build -Windowed
```

1. `-Mode fanout` is the important one — the default is `observe`, which is a fully STOCK game (that is our safety default, hard rule 4).
2. `-Build` compiles the plugin first (skip once built); `-Windowed` is optional but nicer for testing.
3. It launches the working copy at `C:\sc-work\1161-base` — your playable install `C:\sc-install` is never touched.
4. Off switches if anything acts up: `-HudRow 0` (no row paging), `-Circles 0` (no extra circles), `-Mode observe` (all off).
5. In-game: box more than 12 units → all get circles, all obey orders; right-click the bottom row to flip pages.

## 2. Why so many uncommitted files

All 23 are under `work/messages/` — the orchestration mailbox: your messages, my replies, the UI''s own state files (`.ui-state.json` + its `claims/rev-N` files churn every time the console renders), and status.json temp files. Nothing is code and nothing is lost: a `backup-messages` job snapshots and pushes them to main periodically (see the `chore(messages): snapshot` commits). Between snapshots they sit uncommitted by design — committing on every message write would generate a commit every few seconds. All research/tooling/task files are committed and pushed; main is in sync with origin.

## 3. Polish ideas (1.16.1) — reply with numbers, I''ll cut tasks

1. **Control groups >12** (Ctrl+1 assign/recall) — box 24, Ctrl+1, press 1 later → all 24 back. The hotkey path is already mapped (it is the "hotkey drop" our shadow list handles); natural completion of the selection story. Medium.
2. **HP bars for the extra units** — circles were delivered without bars (deliberate: bar removal is gated on the hazardous flag). Task 014 left the evidence trail for doing it safely. Medium, known hazard to respect.
3. **Restore paging after transport load** — today loading units into a transport while >12 selected drops the row to stock until you reselect (safe fallback from review round 3). Rebuilding the shadow from engine truth instead would keep paging alive. Small-medium.
4. **Mixed-type selections polish** — all our >12 fixtures are single-type; a mixed 24 (zealots+dragoons+scouts) exercises wireframes/paging/fan-out differently. Verify + fix whatever shows up. Small (investigation first).
5. **Combat test fixture** — generator grows an enemy force + kept triggers so tests can kill units in-game; closes the "death only proven offline" gap from PRs 14/17 permanently. Small, pure test infra.
6. **Double-click / Ctrl-click select-all-of-type beyond 12** — vanilla selects up to 12 of a type on screen; extend to grab all on screen into the shadow selection. Medium.

My pick for value/effort: **1 + 3**, then 5. But it is your game.
