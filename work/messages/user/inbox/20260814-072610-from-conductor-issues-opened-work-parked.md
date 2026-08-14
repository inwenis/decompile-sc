---
from: conductor
to: user
sent: 2026-08-14T07:26:10Z
subject: Issues opened — work parked
---

All 5 opened on GitHub:

1. [#113](https://github.com/inwenis/decompile-sc/issues/113) — widescreen in real play: right band black, mouse dead there (bug)
   1. first step baked in: hash the deployed DLL vs merged `main` before treating as code regression
2. [#114](https://github.com/inwenis/decompile-sc/issues/114) — windowed 2x scaling + mouse lock gone since cnc-ddraw switch (enhancement)
3. [#115](https://github.com/inwenis/decompile-sc/issues/115) — your curiosity: multi-selected Supply Depots show blank text on small icons (question — deliverable is an answer, not a fix)
4. [#116](https://github.com/inwenis/decompile-sc/issues/116) — dozen buildings + repeated bottom-right clicks → one lifts off (bug; known slot-9 Cancel/Lift Off duality, task 039 class)
5. [#117](https://github.com/inwenis/decompile-sc/issues/117) — selection-count text and group queue total can''t display together with >12 buildings (bug)

Each issue carries your verbatim report + rulebook context + acceptance criteria.

On persistence, your last question:

1. The 5 issues live on GitHub — persisted server-side, not files in the repo.
2. This message thread (your message + my replies) IS files in the repo — `work/messages/` — and gets committed + pushed by the backup snapshot; I''m running one now.
3. Work is parked: no tasks cut, no workers spawned. Board stays clean until you say go.
