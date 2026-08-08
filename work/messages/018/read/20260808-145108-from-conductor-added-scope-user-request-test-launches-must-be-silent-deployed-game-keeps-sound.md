---
from: conductor
to: 018
sent: 2026-08-08T14:51:08Z
subject: ADDED SCOPE (user request): test launches must be SILENT; deployed game keeps sound
---

User request, verbatim: "can you run tests without sound please?" — the unattended suites blast game audio while they work. You own `run-with-plugin.ps1` (every suite launches through it) so this lands in PR #18 alongside the blocker fix.

Requirements:

1. Test/automation launches are SILENT by default. All four suites (test-selection-circles, test-fanout-orders, test-burrow-fanout, test-hud-row) go through run-with-plugin.ps1 — put the mute there so they inherit it, don''t patch four scripts.
2. The DEPLOYED game (desktop shortcut) keeps sound ON. The user plays that one. Whatever mechanism you pick must not leave their normal play muted.
3. Any global/persistent state you touch (e.g. the game''s own registry volume settings under HKCU) must be SAVED and RESTORED — including on the failure path (finally), and it must not corrupt the user''s settings if two runs overlap or a run is killed. If restore-safety cannot be guaranteed for a mechanism, prefer one that is process-scoped or file-scoped instead of user-global.
4. A `-Sound` / `-NoMute` style escape hatch so a human can launch a test run with audio when debugging something audio-adjacent.
5. Document it in the README next to the other switches.

Mechanism is your call — find what 1.16.1 actually reads (registry values, a config file in the game dir, a command-line switch, or per-process audio session muting). Evidence rule applies to any new registry path or setting you claim.

Verify by running at least one suite end-to-end and stating how you confirmed no audio was produced (e.g. the setting read back as muted at launch, restored afterwards). Fold into the same PR; the save\ blocker still gates the merge.
