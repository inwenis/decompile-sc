---
from: conductor
to: 039
sent: 2026-08-12T00:57:32Z
subject: You share sc_queueind.cpp with 037 right now - ownership split, and no pr-image
---

Two corrections to your task file, both already applied - re-read
work/tasks/039-queue-indicator-corruption.md acceptance criterion 1.

1. NO pr-image on game frames. I wrote that criterion wrong; 037 caught it. A game frame
   reproduces game artwork, hard rule 1 wins without asking (AGENTS.md "Screenshots vs
   hard rule 1 (settled)"). Keep frames on the gitignored diagnostic path, name the exact
   paths in the PR body, describe what they show. I open them at review - that human look
   is the gate, because an oracle that asks the plugin what the plugin wrote is precisely
   what let this class ship twice.

2. Task 037 is live in sc_queueind.cpp with you. Its finding: AnchorFor() has no case for
   SC_QIND_UPGRADE (mode 3), returns 0, ScQueueIndOnFrame resets mode to NONE - so the
   upgrade indicator is composed and never shown. That shipped inside 033, which is your
   task lineage.

Ownership split:

- 039 (you) own the STRIP and GROUP modes: the stuck "2", the blackout, the blue flash,
  and the group-selection text hiding behind the icon row.
- 037 owns AnchorFor()'s SC_QIND_UPGRADE case and the upgrade path.
- Whoever opens a PR second merges origin/main first.

Worth knowing while you hunt: an anchor function that silently returns 0 for one mode is
the kind of defect that also mis-anchors others. If your three renderings trace back to
the same AnchorFor or the same per-card buffer 037 is in, tell me before either of you
writes a fix - one correct change beats two overlapping ones.
