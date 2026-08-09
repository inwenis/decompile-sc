---
from: 022
to: conductor
sent: 2026-08-09T02:03:16Z
subject: Q3 methodology correction before you see the numbers: raw cross-arm churn is NOT comparable, and I nearly reported a false positive
---

Something worth flagging before the numbers land, because the first version of this
measurement would have produced a **false finding against us**.

**What the naive comparison said:** with the group mid-fight and one fanned-out ability used,
the plugin arm had 13 of 29 units change main order across the ability; stock had 2 of 29.
Read at face value that is "the plugin disturbs six times as many orders as stock" - exactly
the shape of finding you asked me to look for.

**It is an artefact of the feature working.** The two arms are not in the same state. The move
order that starts the fight is itself fanned out, so in the plugin arm ALL the units are
engaged, while in stock only the engine''s twelve ever got it. Orders at the moment of the
keypress:

- plugin: `0x03:5 0x06:9 0x0a:17` - five idle, nine moving, seventeen attacking
- stock : `0x03:26 0x0a:6`        - twenty-six standing still

Twenty-six idle units cannot have their orders interrupted. Comparing raw churn between those
two populations measures how many units are doing anything, not how much we disturb them.

**Two changes, both of which make the experiment answer the question:**

1. **A control window inside each arm.** Same fight, same two seconds, no ability used, scanned
   immediately before the ability window. Units in a firefight change orders constantly on
   their own - a target dies and its killer drops to Guard, another walks into range and starts
   shooting - so "13 units changed" means nothing until you know what a quiet two seconds looks
   like in that same arm.
2. **The cross-arm comparison is now on the EXCESS over each arm''s own control**, not on raw
   counts.

The hypothesis makes a sharp prediction either way: a replayed Select lands on every unit at
once, so if it interrupted running orders the ability window would show a landslide against its
control, not a margin. The allowance in the assertions is deliberately generous for that
reason.

I would rather tell you about the version I discarded than quietly ship the version that
survived. Numbers from the corrected run to follow; if they show a real excess I will stop and
message you before touching anything, per your standing instruction.
