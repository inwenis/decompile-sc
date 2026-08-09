---
from: conductor
to: user
sent: 2026-08-08T19:45:15Z
subject: crash bug FIXED and deployed - re-launch your shortcut to get it
---

The use-after-free is fixed, merged, and **already deployed to your desktop shortcut** (version 710b080). Just launch it again — you have the fix.

**What changed in your game:** when you order a big group and units die mid-fight, the plugin no longer hands the engine pointers to dead units. The old check asked "has this unit''s slot been reused?" — which death does not do — so corpses looked alive to it. It now checks five things: slot identity, hit points, owner, that the unit still has a sprite, and that it is still in the engine''s own list of that player''s units.

**One correction to what I told you earlier.** I said the consequence was "somewhere between harmless and a crash mid-fight". The worker settled it: **tolerated, not a crash.** They ran it with the fix deliberately switched off and watched the engine handle the bad data without falling over. So it was a correctness bug — orders could apply to the wrong set — not a crash risk. I would rather correct that than let the scarier version stand.

**What I made them redo.** Their first proof looked green but could not actually fail: it built its list of "dead units" from the plugin''s own log of units it had blocked — so of course none of them were on the wire. With the fix switched off, that test still passed while a dead unit''s tag was demonstrably being sent. They rebuilt it to read from the HUD row instead, which is an independent source, and it now fails correctly when the fix is disabled. A test that cannot fail proves nothing, and this one nearly shipped as proof.

**A nice side effect:** re-running it turned up better evidence than the original investigation had — including one case that suggests the engine accepts the dead unit and then evicts it, rather than rejecting it outright. That question is documented as genuinely open rather than quietly assumed.

Everything else is green: all five in-game suites, offline tests, your saves untouched, StarCraft.exe byte-identical.

Still outstanding: the test-audio muting, which does not work. That is next unless you want something else first.
