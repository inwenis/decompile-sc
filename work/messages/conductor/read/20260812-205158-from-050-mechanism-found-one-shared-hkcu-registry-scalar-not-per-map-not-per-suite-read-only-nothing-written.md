---
from: 050
to: conductor
sent: 2026-08-12T20:51:58Z
subject: Mechanism found: one shared HKCU registry scalar, not per-map, not per-suite -- read-only, nothing written
---

Answers, from a READ-ONLY registry check (HKCU:\SOFTWARE\Blizzard Entertainment\Starcraft), nothing written:

    Custom Type   : Free For All
    Recent Maps   : {..., C:\sc-work\1161-base\maps\campaign\(1)Enslavers02b.scm}

Q1 (sticky between runs)? YES, and it is not scoped to the test harness at all -- it is
ONE scalar value in the REAL per-Windows-user Blizzard registry key, shared by every
StarCraft launch on this machine regardless of which GameDir/working copy runs it. The
"Recent Maps" entries in the same key are real paths from actual play, which is
independent confirmation this key really is shared, live, and not something any of our
copies own.

Q2 (does the MAP decide it)? NO. The key holds one flat "Custom Type" string, not
per-map data. The combo's default is a single machine-wide last-used value, same for
every map. Ruled out by reading the key's shape, not by assumption.

Q3 (non-dropdown way to set it)? No sanctioned one. It is exactly this one registry
value, and hard rule 5 forbids writing HKCU:\SOFTWARE\Blizzard Entertainment\Starcraft\*
directly (the 2026-08-08 wipe). The ONLY legitimate writer is the game's own UI reacting
to a real pick -- which is what Set-ScGameType already does, and which needs the
foreground by construction (task 027). There is no off-screen path around this, by
design, not by gap in my conversion.

So: the wrapper is not broken and nothing needs a different mechanism. What changed is
that "Custom Type" currently reads Free For All -- almost certainly your own last game
(the Recent Maps entry is a real map, not a test fixture) overwrote what task 049's
Group-A runs had left it as earlier today. This is machine-wide state, so it is not a
hud-row-specific gap: right now, at this instant, ALL NINE Group-A suites would also
hit a real pick, not a skip -- 049's "almost always already correct" was run-order luck
across the whole fleet, test AND real play, not a property of those 9 suites. Worth a
loud note in 049's resumed table, not just mine.

test-building-parity and test-building-groups just hit the identical structural throw
off-screen (same message, same 'Free For All' -> 'Use Map Settings' mismatch) -- so this
is one shared-state finding across suites, not six separate ones.

Does this retire the "3 minutes of your screen" ask? Partially, and I want to say that
precisely rather than round it up: it turns "6 suites always need it" into "whichever
suite runs next needs it only when Custom Type is not already Use Map Settings" -- the
exact exposure the other 9 suites already carry today. One real (foreground) pick sets
it for every suite, test or off-screen, until the user's own play changes it again.

Proposal, once the 23:00 window opens: ONE -Visible run (any single Group-B suite,
announced first per acceptance criterion 5) to perform that one real pick, then
re-run all six off-screen to get the actual skip line criterion 2 asks for. Continuing
the remaining suites (control-groups, combat-death) off-screen now for consistency
while I wait for the window -- expect the same structural throw, which is expected and
not a new finding.

Want me to hold for your go before that one -Visible run, or is the window + your
acceptance criterion 5 announcement enough?
