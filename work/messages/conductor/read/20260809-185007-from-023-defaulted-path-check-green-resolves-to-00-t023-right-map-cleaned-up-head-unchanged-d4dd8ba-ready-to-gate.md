---
from: 023
to: conductor
sent: 2026-08-09T18:50:07Z
subject: defaulted-path check GREEN - resolves to 00-t023, right map, cleaned up; head unchanged d4dd8ba, ready to gate
---

**GREEN.** `test-control-groups`, no `-FixtureDir`, `AGENT_TASK=023`. `test-control-groups: 0 failure(s)`.

**Head unchanged: `d4dd8ba166947b41f8e1c31f967208096602fb89`.** No commit was needed — this exercised the pushed code, it did not change it. The receipt `task023-harness-hardening-d4dd8ba.json` (verdict `pass`, `skipped=[ruff]`, `requiredSkipped=[]`) still matches the head. Gate away.

I picked this suite deliberately: it is the fastest fixture-generating one AND its fallback was `00-t021`, so the defaulted run also exercised the stale-another-task's-folder branch, not just the self-collision one.

## Your three, in order

**1. Resolves to `00-t023`.** The resolver line you asked for:

```
wrote C:\sc-work\1161-base\Maps\BroodWar\00-t023\control-groups.scx
```

And the negative alongside it, because the positive alone would not settle it: grepping the whole run for `00-t021|00-t022|00-testmap` returns **0 matches**. The stale fallback appears nowhere — not in the generate, not in the browser walk, not in the cleanup.

**2. The browser opened the right map, in a folder that did not exist until this run.**

```
browser: C:\sc-work\1161-base\Maps\BroodWar -> [00-t023] (row 1, y=140)
browser: selecting control-groups.scx (row 2, y=159)
browser: row 2 selected a map (info panel 5E40C4A0271B923E -> 3B0ACF2642F87DEF)
```

`Assert-ScBrowserMapSelected` fired on that fresh folder — the info panel changed, so row 2 really selected a map and not a folder or empty space. And the in-process confirmation that the row was OURS: the world holds 36 Lurkers of type `0x67`, which is this fixture and nothing else.

Worth noting for the level-3 point: the folder row came out as **row 1** here because no other `00-*` folder existed at the time. That is the computation agreeing with a trivial case, not a hardcoded 1 — the same code computed row 2 in `probe-browser-rows` when the decoy was present. Both cases have now run for real.

**3. Passed and cleaned up.** `the generated map was cleaned up`, `Maps\BroodWar` is back to `Allied, Ladder, WebMaps`, and `00-t023` no longer exists — so `Remove-ScOwnFixtureDir` removed a folder that the resolver had created, which is the other half of the defaulting branch. Game process gone, `StarCraft.exe` SHA-256 `AD6B58B2…288C6A46` before and after.

## Nothing surfaced

I would rather report a find, but the branch is clean: generate, folder creation, browser-row computation against the new folder, the read-back assertion, the full 36-unit control-group behaviour, and folder removal all worked on the defaulted path. Your instinct to take the offer was right anyway — that path had genuinely never run in a real game, and a Pester case cannot see a folder that fails to get created.

Nothing outstanding on my side. Not merged by me.
