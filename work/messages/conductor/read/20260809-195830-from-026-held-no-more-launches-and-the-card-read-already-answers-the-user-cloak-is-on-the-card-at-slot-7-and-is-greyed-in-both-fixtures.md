---
from: 026
to: conductor
sent: 2026-08-09T19:58:30Z
subject: HELD, no more launches - and the card read already answers the user: Cloak IS on the card at slot 7 and is GREYED, in BOTH fixtures
---

**Held. No further launches.** One in-game run had already finished and closed before your hold
arrived (`close-game: pid 116652 exited cleanly`, launch lock released, no stranded process). Nothing
else of mine will touch the game until you release me.

**And that run corroborates the user, from memory rather than from a frame.** I built the read-back the
task asked for — the plugin now walks the command-card dialog (`0x0068C148`) on the marker channel,
read-only, no hook, works in `-Mode observe`. On the 18-Ghost `--tech-researched personnel-cloaking`
fixture, one Ghost selected:

```
slot 7 GREYED  icon=0x00FC act=0x00423730 cond=0x004293E0 cparam=10 name=0x0158
```

- `act=0x00423730` is byte-exact Cloak: `MOV byte [EBP-4],0x21` then queueCommand (command `0x21`).
- `cparam=10` is Personnel Cloaking, the same tech id `ability-semantics.md` section 3 derived
  independently from the receive-side handler.
- **GREYED** = `control+0x18 & 0x2`. Both engine input paths test that exact bit and return: the mouse
  at `0x00459947`, the hotkey predicate at `0x004588C0`. So a greyed button is silent to every key and
  every click **by construction** - which is precisely the shape of task 022/023's negative.

**The no-tech control fixture reads IDENTICALLY** - slot 7 present, same button, also GREYED. So:

1. **The user is right, and it is stronger than "not unlocked":** researching Personnel Cloaking in the
   fixture changed *nothing* about the card. Same slots, same buttons, same states.
2. **Task 023's control is retracted.** It concluded "the researched fixture DOES draw a different
   command card" from two differing region fingerprints (`AC61F7A0...` vs `DB533167...`). On this run
   both fixtures fingerprinted `AC61F7A0C9244DB1` - the same value 023 recorded for *no tech*. A frame
   hash over a card region is not a reliable oracle for card content; the slot table is. That is exactly
   the failure class the memory read was cut to remove.
3. So task 022's "the ability row is inert" was **not** an input-path result. It was a greyed button.

**Why greyed, statically.** `condCloak` (`0x004293E0`) returns the tech gate's value unchanged whenever
it is not 1. The gate `0x0046DD80` tail-calls the requirement interpreter `0x0046D610`, whose only
-1 (= grey) exits are reason `0x15` and the terminal `if (satisfied == 0) { reason = 8; return -1; }`.
Its researched test is requirement opcode `0xFF0F`, which reads a **per-player tech-RESEARCHED byte**,
and the availability test earlier in the gate reads a **different, adjacent per-player array** - a
button whose tech is unavailable is *hidden* (returns 0), not greyed. Our button is visible, so
availability passed and **researched failed**. That is "PTEx marked it available but the engine does not
consider it researched", i.e. your item 1: the first bug is the fixture.

I am pinning those two arrays down statically right now (they look like `techAvailable[12][24]` at
`0x0058CE24` and `techResearched[12][24]` at `0x0058CF44`, with the Brood-War tail at `0x0058F038` /
`0x0058F128`; addresses being confirmed by an xref sweep before I write them down). I am adding both to
the same read-only scan, so the very next in-game run reads the player's researched bit *and* the card
in one marker and settles it without a frame or an assumption.

**What I need from you, eventually, not now:** one in-game run on task 027's non-focus-stealing launch.
Everything else - the static map, the research doc, the probe, hooktest - I can finish held.
