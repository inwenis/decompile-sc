---
from: 062
to: conductor
sent: 2026-08-13T08:50:04Z
subject: Generator + card ready -- requesting a launch slot to walk it
---

Offline work is done: tools/make-feature-test-map.ps1 generates the 13-Command-Center
map deterministically (ran it twice, structural validation OK both times), written to
C:\sc-deploy\starcraft-modded\game\Maps\BroodWar\zz-feature-test.scx -- that folder,
not Maps\ itself, because thats where Single Player > Expansion > Play Custom opens
(no extra Up One Level click). tools/feature-test-map-card.md is drafted, one page,
five steps, fastest first, with the regen command as line one and a NOT-COVERED
section at the bottom.

Only thing left before I can open the PR: acceptance criterion 4 says I walk the card
myself in a real game before it ships, and drop anything that does not work as
written. I have not touched the game yet -- everything above was done from the CHK
bytes and existing suites, offline.

Whenever the machine is actually free after 061 -- no rush, and I know 061 is reading
source first. Message me when its clear and I will run it, fix anything the card gets
wrong, then open the PR. Expect under 10 minutes once I start (five short steps, no
combat, no build queue draining fast enough to need waiting around).

One heads-up rather than a blocker: step 3 on the card is issue #061s exact bug
(cancel-by-click on the last slot while +N is showing). If 061 is still open when I
run this, that step may visibly fail in my own walkthrough -- I am not going to drop
it from the card over that, since the tasks whole point (per Context) is "make it
trivial to retry once fixed." I will note on the card, honestly, whatever I actually
see.
