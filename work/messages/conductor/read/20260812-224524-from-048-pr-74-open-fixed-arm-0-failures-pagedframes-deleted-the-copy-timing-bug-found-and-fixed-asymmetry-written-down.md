---
from: 048
to: conductor
sent: 2026-08-12T22:45:24Z
subject: PR #74 open, fixed arm 0 failures. pagedFrames deleted, the copy-timing bug found and fixed, asymmetry written down
---

**PR #74 — https://github.com/inwenis/decompile-sc/pull/74** — and `Status.pr` is filled in.
Both arms run, `run-ci-local.ps1` PASS at `26bb47e`. Machine is FREE from me: game closed,
launch lock released, fixture `00-t048` removed, nothing of mine running.

## The headline

Fixed arm: **0 failures**, `indBounds=(30,79,184,92)`, `indBoxDiff=268`, `glyphBytes=237
stranded=0` on all three hand-backs, COVERAGE 24 layouts / 3 episodes.

## Your three notes, all three actioned

**1. `pagedFrames` was fiction — you were right and it is gone.** It was a real count (paged
dispatcher calls, incremented once per call) but the value is unusable: this detour runs at
~46 calls per MILLISECOND, so seven digits over 37 seconds is indistinguishable from a tick
global read by mistake. I replaced it with `pagedEpisodes` (entries into the >12 state: 3)
beside `acts` (11) — both small, both cross-checkable against the run's own `HUDROW show`
lines. The one call count left prints its own elapsed milliseconds next to it:

    HUDROW band inked: the line landed 1425 dispatcher call(s) / 31 ms after the show asked for it

**2. Two instruments disagreed, and `indBoxDiff` was the honest one.** `glyphBytes=0` was the
bug. The band copies were sequenced by counting dispatcher calls -- "take the inked copy one
call after the show" -- on my assumption that this detour runs once per rendered frame. The
line above is that assumption being measured and killed: the paint landed 1425 calls later, so
the inked copy was of the pane BEFORE our text and came out identical to the clean one.
Both copies are now taken on evidence rather than on a counter: `clean` once the band has read
byte-identical for 100 ms, `inked` the first time it is seen to DIFFER from clean. I did not
touch the guard.

**3. The asymmetry is written down, in the table's own section.** The before/after table says in
as many words that the defect arm's `-1`s and 7 failures are an UNINSTRUMENTED build and not
seven defects, that the measurement lives in the plugin (unlike 039's, which lived in the
suite), and that the before-column rests on the old build's own log line plus the frames.

## The frames, for your human look (do NOT pr-image -- game artwork)

    C:\sc-work\logs\048-frames\defect\03-page2.png     <- merged main
    C:\sc-work\logs\048-frames\fixed\03-page2.png      <- this branch

I opened both myself. **The defect frame has no text anywhere on the pane** -- twelve wireframes
and nothing else, which is the invisibility `indInk=2368` could not report. The fixed frame reads
`36 units  13-24  (2/3)` across the bottom of the pane, below both rows of icons, on console art
rather than on a wireframe. It sits on the pane's last thirteen rows with two pixels of headroom
under an eleven-pixel font, because that is the only unoccupied band in the dialog -- the same one
the group line has used since 039. Four more pairs in the same folders; `05-stock-small-selection`
is the after-the-hand-back state.

## The AGENTS.md amendment is in the PR (§8), as an amendment not a replacement

The general form, in one line: **an instrument whose reading does not move when its input moves is
not measuring its input.** Written for a reader who has not seen the PR, as you asked, with the
2368-for-three-strings line as its evidence, and with the check that finds this in any log without
source: vary the input and watch the number. Two riders came out of my own mistakes above (a
reverse-direction difference must carry the SIZE of what it looks for; a wall clock and not a call
count decides when a surface has settled), plus the standing instruction task 052 is already
acting on -- when an instrument turns out to be blind, audit every other place it is load-bearing
in the same sitting. Change the wording freely; the rule is the point, not my sentences.

## Three things I am NOT claiming

1. **Issue #44 stays open.** It wants a BUILDING group past twelve; my fixture is 36 Lurkers. The
   placement and the oracles are unit-type-agnostic, but that case is unexercised.
2. **The plugin build is not reproducible** -- measured, two builds of the same tree differ (PE
   TimeDateStamp). So the DLL hashes in the PR identify the binaries that RAN, not the trees they
   came from. Your "which tree did that DLL come from" problem from tonight is not solved by
   hashing; it wants a deterministic build. Worth an issue, out of scope here.
3. **`indInk` is still on the line.** Kept as corroboration, no longer asserted on. Removing it
   would delete the evidence for the rule.
