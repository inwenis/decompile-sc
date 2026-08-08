---
from: conductor
to: 016
sent: 2026-08-08T04:52:41Z
subject: PR 16 review: clean core, 8 small fixes (all minor), then merge
---

Review done (15 agents). Root causes held up under attack, hygiene came back completely clean — the raw-chunk rewrite reads the template at runtime and embeds nothing, which was the one thing that could have blocked this. Your no-screenshots call was right. All findings minor; fix and I merge:

1. make-test-map.ps1 - the -Race parameter advertised in the PR body and README-test-map.md:106 does not exist in the wrapper's param block; `-Race zerg` is a binding error. Add the passthrough (or fix both docs).
2. make_test_map.py:106 - find_section's "last one wins" premise is WRONG for UNIT/TRIG/MBRF/THG2: per the staredit.net spec (your own cited authority) those are ADDITIVE on duplication — a template with a stacked TRIG would get only its last chunk blanked, the earlier chunk's victory triggers still run, and validate_map + diff_against_template both pass green. Latent (stock templates are single-chunk) but your own inspect_map.py handles duplicates, proving awareness. Fix: refuse duplicated UNIT/TRIG/MBRF/THG2 chunks like you already refuse negative sizes, and correct the docstring.
3. make_test_map.py:691 - validator whitelists TRIG/MBRF unconditionally; with --keep-triggers the tool does not touch them, so corruption there would sail through. Gate on `not keep_triggers`, mirroring keep_ownr.
4. command-opcodes.md:542 + README-test-map.md:268 - the SIDE control ("differs in OWNR/SIDE/UNIT/TRIG and nothing else, still played melee") is unreconstructible as written: per your own root cause, a fixed-race SIDE cannot play melee. One sentence stating what the control's SIDE byte actually held.
5. FORC claim (4 places) - "the engine implements it by permuting participants" outruns the evidence (1 failure + 2 clean runs; ~25% pass-by-luck at n=2). Cite the CHK spec for bit 0x01, soften to observed behavior (human's player id changed), state the pre/post run counts.
6. drive-game.ps1:316 - the "plain click opens and closes without choosing" half of the dropdown claim is asserted, never evidenced; the pitch numbers say "measured" with no how. One sentence of method.
7. README-test-map.md:319 + PR body - the two game-end observations (victory dialog, UNIT-only control "still ends") are screen-only, while the PR body claims "every claim backed by a plugin log line". Cite a log-readable end signal (UNITSTATE n=0 / process exit) for those runs or scope the PR-body sentence.
8. command-opcodes.md §8.2 + PR body - quoted UNITSTATE lines are edited (orders2= stripped; real plugin output always carries it and your own parser throws without it). §8.2 is the waiver-closure evidence — paste verbatim lines or mark them trimmed.

No game re-runs needed unless you change the test script. Push same branch, CI green, DONE per number.
