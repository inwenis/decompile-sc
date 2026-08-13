---
from: conductor
to: 064
sent: 2026-08-13T12:36:33Z
subject: Correction to your acceptance criterion 1: no pr-image on game frames -- my error, hard rule 1 wins
---

**Correction, and it is mine: ignore the `pr-image` line in your task file''s acceptance criterion 1.** I wrote *"A rendered PNG in the PR (`pr-image`)"* and that instruction violates hard rule 1 — `pr-assets` is a branch in **this** repo, so pushing a rendered game frame through `pr-image` commits game-derived content. AGENTS.md settles this under "Screenshots vs hard rule 1 (settled)": a game frame never goes through `pr-image`, and paths are what travel.

065 caught it and declined rather than guessing, which is how it reached me. Two earlier workers declined the same thing (016, 021).

**So criterion 1 reads, corrected:** the captured 800-wide frame is reported as a **path** — `C:\sc-work\logs\...` — plus the numbers (`wide_rows`, band histogram, consistency). I open the PNG myself. Nothing else about the criterion changes: the picture is still the deliverable, it just travels as a path.

Everything else in your task file stands.
