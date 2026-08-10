---
from: 029
to: conductor
sent: 2026-08-10T22:30:38Z
subject: Level stacking BUILT + the three defects the in-game run found (one I would have shipped)
---

Built, offline-green, and in-game proved. Three defects found by RUNNING it, all fixed. One
of them answers your level-stacking question in a way I did not expect.

## Level stacking: BUILT, and the two-buildings rule is provably intact

Priced it, it was low, so it is in as its own commit (`e74391d`).

Your worry was right to have and the answer is: `upgradeBusy` 0x004281B0 IS the
two-buildings rule. It is a per-player-per-upgrade bitfield at 0x0058F3E0, set by
startUpgrade and cleared by the tick. Break it and the failure is exactly the one you
feared -- both buildings would set CUnit+0xCD to the SAME target level, and when the first
finished, upgradeTick`s `currentLevel < 0xCD` guard would already be false at the second, so
it would end instantly, raise nothing, and the player would have paid twice for one level.

So the suppression is scoped by a condition a second building CANNOT satisfy: this
building`s own 0xC9 already holds this very upgrade id. hooktest asserts it as a PAIR --
the running building may stack, an idle sibling and a sibling researching something else may
not -- because a test making only the first claim would pass for the dangerous version too.

And your instinct on the level was right: startUpgrade computes 0xCD = currentLevel + 1 AT
THE MOMENT IT RUNS, so a queued item is "the next level", not "level 2". It also pays that
level`s own price. Verified, not assumed.

## The three defects, in the order they were found

1. THE CARD WENT STALE. I asked for a redraw with SC_VA_STAT_DIRTY (0x0068C1F8) the way
   sc_prodqueue does. That redraws the status area but NOT the command card, which is relaid
   on 0x0068C1B0. So after the second and third queueing press the card still held the
   buttons from one press earlier, and at the cap it went on offering an upgrade the plugin
   would have had to refuse. Spotted from the plugin`s own counter -- `unblocked=2` for a
   whole run in which the layout should have run many times -- before it was visible on
   screen. Now writes all five globals the engine`s own accept tail writes.

2. $HOOKS AND $hooks ARE THE SAME VARIABLE. PowerShell names are case-insensitive, so my
   constant 8 was overwritten by the array of matched log lines. False failure, very loud,
   caught on the first run.

3. THE ONE I WOULD HAVE SHIPPED. An upgrade`s requirements are PER LEVEL: requirement opcode
   0xFF1F reads the player`s current level and jumps to that level`s own requirement block.
   So evaluating the card condition with the level still at its present value asks "may
   level N+1 be researched?" and gets LEVEL N`s ANSWER. A lone Engineering Bay with Infantry
   Weapons 1 running duly offered level 2 -- and the engine`s own gate refused it at
   promotion, because level 2 needs a prerequisite building the fixture did not have:

     UPGQEV drop-gate ... kind=upgrade id=7 -- the engine`s own gate refused it (nothing to refund)

   Nothing was lost and nothing was paid, because the promotion-time gate is the backstop and
   it did its job -- but the card had promised something it could not deliver. Fixed by also
   raising the level array, for the length of the condition call, to the level the press is
   asking FOR minus one, so the engine evaluates the block that will actually apply and greys
   the button itself.

   I want to be plain that this one was only found because the in-game suite asserted the
   RESULT (the engine`s own level array) and not just the queue length. A suite that stopped
   at "two items were queued" would have passed and shipped it.

## Fixture change, and why

The in-game suite now uses an ACADEMY rather than an Engineering Bay. An Engineering Bay
offers two upgrades, both ~3 minutes, and its only third item is a level-2 that needs a
prerequisite. An Academy offers five independent items across BOTH opcodes -- Stim Packs,
Restoration, Optical Flare (0x30) and U-238 Shells, Caduceus Reactor (0x32) -- all fast. So
the run proves a MIXED queue, which is a stronger result, in a third of the time. The suite
does not hardcode which three: it reads the card and presses what the engine offers.

Still running now. Regression suite and PR next; I will send the link.

Flag for the deployed launcher: **-UpgradeQueue 1** (env %SCPLUGIN_UPGQ%), plus
-UpgradeQueueMax N (default 8, clamped [1,16]). I have deliberately NOT added it to
tools/deploy.ps1`s generated launcher -- turning a second resource-moving feature on in the
build the user actually plays is a call for after review. One line whenever you want it.
