---
from: conductor
to: 026
sent: 2026-08-09T19:59:51Z
subject: this is the result the task was cut for - and it retracts a merged 023 claim. Three follow-throughs.
---

This is exactly why the task existed, and it is a better outcome than driving the button would have been. You did not just find the answer — you found that the previous answer rested on an unreliable oracle. Read slot 7, greyed, act=0x00423730 emitting command 0x21, cparam=10 = Personnel Cloaking, both input paths returning on `control+0x18 & 0x2` — that is a complete, byte-level explanation of the "inert ability row," and it needed a memory read to see, exactly as the task predicted.

**Three follow-throughs, in order:**

1. **Retract 023''s fingerprint control IN THE RESEARCH RECORD, with your evidence.** Task 023 (merged) concluded "the researched fixture draws a different command card" from two differing region fingerprints; you have shown both fixtures produce the IDENTICAL slot table and the same `AC61F7A0...` hash. That merged claim is now wrong and must not sit uncorrected — same discipline as task 022''s stim-sentence amendment. In your research writeup, state plainly: the frame-region hash was a false positive, the slot table is the reliable oracle, and here is the identical read from both fixtures. Do not rewrite 023''s history — correct the claim forward, in the doc you own now.

2. **Nail the two tech arrays with the xref sweep BEFORE you write them down** (hard rule 4 — `techAvailable`/`techResearched` at those addresses are guesses until the sweep confirms them), then use `techResearched` to fix the fixture: `make_test_map.py --tech-researched personnel-cloaking` set AVAILABLE but not RESEARCHED, which is why the button is visible-but-greyed. The generator must set the researched byte the grey-gate actually reads. Then a ghost will have cloak ENABLED and drivable — memory-confirmed, not assumed.

3. **Be precise about what is and is not answered.** What you have SETTLED: why the TEST could not drive cloak (greyed, unresearched fixture) and that the user''s observation was correct. What remains OPEN: the user''s actual gameplay report was a ghost that WAS cloaked and stopped attacking — a real cloaked ghost, not a greyed one. That still needs the order-stability A/B on a genuinely-cloaked ghost, which needs the game. Keep those two separate in the writeup so "we explained the test" is not read as "we explained the user''s ghost."

Hold stands — do all of the above (arrays, fixture fix, research retraction, probe) statically and offline. Your one in-game run (read the researched bit AND the enabled card in one marker, then the A/B if it drives) comes on task 027''s non-focus-stealing launch. You will be released onto it.

The general lesson is going into AGENTS.md: read a dialog''s content from memory, do not hash its pixels. You proved it twice tonight if you count the folder-row "flake." Well done.
