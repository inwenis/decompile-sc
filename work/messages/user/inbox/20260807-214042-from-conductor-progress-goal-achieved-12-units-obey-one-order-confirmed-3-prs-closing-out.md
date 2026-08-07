---
from: conductor
to: user
sent: 2026-08-07T21:40:42Z
subject: PROGRESS: goal achieved - >12 units obey one order, confirmed. 3 PRs closing out.
---

**Headline: your goal is achieved.** You commanded more than 12 units with one order, and it is confirmed twice over — by you on screen, and independently by the plugin's own byte-level log.

Your result: run A twelve moved, run B all moved. The log agrees:

    SHADOW captured: 24 units (12 visible + 12 beyond the cap)
    FANOUT: units=24 -> 2 Select+order pairs, 72 bytes this turn
    STATS: fanouts=4 pairs=8 deferred=0 staleSkipped=0

Four orders became eight select-and-order pairs. Nothing deferred, nothing dropped. The engine's 12-unit cap was never raised — we worked inside it, which is why nothing on disk was patched and your install is untouched.

Your control run is what makes it conclusive. Same map, same actions, observe mode: 12 moved. So "all moved" is our code, not the map.

## Right now

  10 tasks merged. 3 PRs open, all CI-green:

  #11  the fan-out feature itself      <- being finalised with your result + honest limits
  #12  automated-testing investigation
  #13  map-generator fix

Three workers are wrapping those up. Nothing needs you.

## Two findings from today worth knowing

**A script can drive this game after all.** Not through the input API that failed earlier, but by posting window messages straight to the game's window. Proven live twice — including making the game's own cursor jump to the exact point. No screen coordinates involved, so the class of failure that wasted an earlier attempt is designed out rather than patched. **Testing no longer costs you a round trip.**

**Reading the game's memory from outside is impossible.** StarCraft locks its own process against external reads — zero successes in 3,581 attempts. So the injected-DLL approach was never one option among several; it was the only door. We happened to pick it.

**And the corrupt map is root-caused.** The library we used writes files with a compression the 1998 engine predates. Found by writing an MPQ reader from scratch rather than trusting the library under suspicion — which is the lesson from that failure actually applied.

## What is honestly NOT done

One map, one order-type pair, 24 units, single-player, one human run. Orders whose meaning depends on the whole selection — archon merge, unload-all — are untested. And *seeing* more than 12 selected, as opposed to commanding them, is a separate and harder piece of work.

Once these merge the natural next steps are widening order coverage, and your call on whether you want the visual half.
