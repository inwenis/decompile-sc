---
from: conductor
to: user
sent: 2026-08-13T08:45:11Z
subject: Your test map: 13 Command Centers, one map, all 7 features. One decision -- how it survives a redeploy
type: question
options: Take (1) now and (2) as a follow-up task (recommended); Just (1) -- I do not mind re-running a command; Do (2) properly first, I will wait; Also make me a second map for Stim/Cloak/Burrow/combat
---

Machine taken, thank you. 062 has scoped your test map and one decision is yours.

## What it proposes: one map, 13 Command Centers

Every feature you listed reduces to *"select some subset of 13 buildings and click"*.

| # | feature | how the map gives it |
| --- | --- | --- |
| 1 | over-cap queue (8+) | one Command Center selected, Train x8 |
| 2 | `+N` indicator + 5th slot | same building, same clicks |
| 3 | **cancel-by-click incl. the last slot** — your bug | click Cancel on that card while queued |
| 4 | group queue indicator | select 2+ of the 13, Train |
| 5 | >12 paging row | select all 13 — page 1 shows 1-12, page 2 shows the 13th |
| 6 | save/load | save mid-queue, reload, check the queue survived |
| 7 | selection circles / building groups | automatic on every click above |

**13, not 36** — the smallest number that proves "one past twelve", and it still gives 1–4 a group to select subsets of. Build time set to **240 seconds**, so the queue sits still while you look at it; a normal 20-second unit finishes before you can read the indicator, which is a mistake we already made once.

**Deliberately NOT on this map:** Stim, Cloak, Burrow, combat/death. Those need a second unit type and a hostile force — a genuinely different setup. If you want them, that is a second map rather than a bigger version of this one. Say if you do.

## The decision for you

The map has to live under the game's `Maps\` folder for the in-game browser to find it. **`deploy.ps1` wipes that folder on every deploy** — it preserves only saves, profiles, replays and downloads. And I deploy after every merge; last night that was eight times.

Two options:

1. **Regenerate it when it goes missing.** The card's first line tells you: not in the list? run one command, wait two seconds, refresh. No changes to the deploy script.
2. **Make `deploy.ps1` write it after every mirror**, so it is simply always there. That is a change to the script that installs your play build — small and additive, but its own task with its own review, not folded into this one.

062 recommended (1) and refused to patch `deploy.ps1` itself, which I think was the right call for a worker to make: that script has tripwires protecting your saved games, and its own comments already flag custom-map survival as a follow-up someone should do properly.

**My recommendation is (2), as a separate task afterwards.** A tool that vanishes eight times a day is a tool you will stop using. But (1) gets you something to click today, so I would take (1) now and (2) after.

Options are on this message. Neither blocks 062 — it is building the generator either way.
