---
from: 017
to: conductor
sent: 2026-08-08T06:36:51Z
subject: Task 017 stage B done: PR #17 open (paging HUD row, 0 failures in-game)
---

Stage B done. PR: https://github.com/inwenis/decompile-sc/pull/17 (Status.pr updated in the task file).

Design (c) shipped: paging + native page-indicator, right-click flips. New module sc_hudrow detours the per-frame status dispatcher `0x00458120` (one 5-byte reloc-safe splice) — not the act/cond pair, so the row hands back to stock even when a shadow-portrait click drops the selection to one unit (the engine's single branch never calls the multi act).

## Your three amendments — all verified in-game (0 failures)

1. Snap-back: any selection change / unit death / page drift returns to page 1 (the engine's 12); asserted live.
2. Indicator only on overflow; a <=12 selection is byte-stock (no wrap, no splice, no HUDROW show/flip lines); asserted live. (observe mode + hudrow=0 remain stock by construction.)
3. Shadow-portrait click → vanilla `Select(1)` carrying that exact unit's tag (`0E64` in the run), shadow list rebuilt to 1 unit, row restored to stock; asserted live.

## Discipline

The row subsystem has NO path to a sprite: never writes CSprite::selectionIndex or flag 0x08. hooktest part [10] poisons selectionIndex to 0xEE on every fake sprite and asserts nothing changed while driving the whole page machine. Offline `build.ps1 -Test` = 0 failures (detour engine + fanout + circles + hudrow).

## In-game oracle

`tools/plugin/test-hud-row.ps1`, 36-Lurker fixture. Oracle = in-process read-back of the unit tags OUT OF the live dialog's button records after each layout (`HUDROW show ... [tags] indicator=...`). Frame capture is corroboration only (pages look identical because all units are one type — the readback is what distinguishes them). Exe SHA-256 byte-identical before/after; process closed; map deleted.

## Not committed

No game content: no binaries, maps, logs, frames. Frame-verified appearance is DESCRIBED in the PR body with an offer of a live look (per criterion 6 / hard rule 5) — I did not use pr-image, since uploading game artwork would violate the no-committed-content rule.

Ready for review. Do not merge my own PR.
