---
from: conductor
to: user
sent: 2026-08-16T06:58:09Z
subject: Parked: everything is committed, deployed build is current, widescreen defect is filed (#113)
---

Short answer: **yes to all three** — conductor files are committed, the mods are deployed and working, and the widescreen work is merged into `main` with its one open defect filed as an issue. Nothing lives only on disk.

## 1. Are conductor files committed?

Yes. `main` is `0 ahead / 0 behind origin/main`, working tree clean (I committed + pushed your parking message itself just now).

| tracked dir | files |
| ----------- | ----- |
| `work/` (tasks + reports + messages) | 1252 |
| `tools/` | 215 |
| `research/` | 50 |
| `scripts/` | 34 |
| `config/` | 12 |

Only two things are deliberately NOT committed, per `.gitignore`:

1. `work/scratch/` — throwaway logs + agent registry.
2. `game/`, `C:\sc-work\`, `*.exe/*.dll/*.mpq` — game binaries (hard project rule).

Every task file, every report, every message you sent and every worker answer is in git and pushed.

## 2. Do the mods still work?

Yes, and the deployed build is current.

1. Deploy root: `C:\sc-deploy\starcraft-modded`, deployed `2026-08-14T08:16Z`.
2. `BUILD-ID.txt` says `version 2fe7295`, and the DLL's own stamp agrees (`SCPLUGIN_BUILD_ID=2fe7295`).
3. Only ONE commit sits above that on `main` — `33275a8`, a messages snapshot touching 2 files, zero source. **So the deployed binary IS merged `main`.**
4. Both desktop shortcuts exist, stamped `2026-08-14 09:16`:
   - **StarCraft Modded** — now presented through cnc-ddraw at 2x scale with cursor lock (task 075 / issue #114 — the feature you asked to have back).
   - **StarCraft Modded (Wide)** — 800x480.
5. To rebuild + redeploy from scratch at any time: `./tools/deploy.ps1`.

Feature set baked into the normal shortcut: select-past-12 fan-out, selection circles, HUD row paging, over-cap production queue with `+N` badge, group production, sound on, windowed.

## 3. Is the widescreen work saved?

Yes — **merged, not finished**, and the unfinished part is written down.

Merged and stamped in `work/tasks/`:

| task | subject | PR |
| ---- | ------- | -- |
| 063 | widescreen presentation | [#94](https://github.com/inwenis/decompile-sc/pull/94) |
| 064 | stage-2 playfield geometry | [#99](https://github.com/inwenis/decompile-sc/pull/99) |
| 065 | cnc-ddraw presentation | [#98](https://github.com/inwenis/decompile-sc/pull/98) |
| 068 | fog band widescreen | [#104](https://github.com/inwenis/decompile-sc/pull/104) |
| 070 | widescreen playable | [#108](https://github.com/inwenis/decompile-sc/pull/108) |
| 071 | console at 800 | [#110](https://github.com/inwenis/decompile-sc/pull/110) |
| 073 | console composite at 800 | [#111](https://github.com/inwenis/decompile-sc/pull/111) |
| 074 | storm present clip | [#112](https://github.com/inwenis/decompile-sc/pull/112) |

The open defect is [issue #113](https://github.com/inwenis/decompile-sc/issues/113) — right band black + mouse dead in real play. Your "did we deploy the wrong DLL?" question is **answered on the issue**: the deployed DLL was hashed against merged `main` and matched, so you played the current build. It is a real defect, not a stale deploy.

Human-readable state of the wide build, including the known imperfections: `C:\sc-deploy\starcraft-modded\widescreen-card.md`.

## 4. Board state at park

1. Open tasks: **0** (075 was the last, merged + closed).
2. Open PRs: **0**.
3. Live workers: **0**.
4. Conductor inbox: **empty**.
5. Open issues: **24**, including the four you dictated on 08-14 — [#115](https://github.com/inwenis/decompile-sc/issues/115) supply-depot blank text (question), [#116](https://github.com/inwenis/decompile-sc/issues/116) lift-off on repeated bottom-right clicks, [#117](https://github.com/inwenis/decompile-sc/issues/117) HUD text collision past 12 buildings, [#118](https://github.com/inwenis/decompile-sc/issues/118) map-browser row 4.

## 5. Two bits of debris — your call, neither blocks anything

1. **7 stranded worktree directories**: `C:\git\decompile-sc-task{052,055,056,057,059,062,066}`. All belong to merged tasks. `prune-worktrees.ps1 -Force` refused — open file handles. Six are empty; 062 holds 3.3 MB, and I verified its leftover `work/messages` is a strict subset of the canonical tree (0 unique files), so nothing is lost by removing it. Already tracked as [issue #84](https://github.com/inwenis/decompile-sc/issues/84).
2. **68 leftover `pwsh` processes** from dead worker sessions, holding **2.9 GB** of RAM — they are what holds those handles. No StarCraft is running and no worker is registered live.

Say the word and I kill the 68 and re-run the prune. I have not touched them, since killing processes is not reversible.
