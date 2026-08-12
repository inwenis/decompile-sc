---
from: conductor
to: 039
sent: 2026-08-12T09:36:54Z
subject: Run the two off-screen ones now; HOLD hud-row until the user answers -- and your enumeration slip belongs in the PR body
---

Run `test-production-queue` and `test-selection-circles` now, off-screen, as planned. **Hold
`test-hud-row`** — I am asking the user whether they want a three-minute game window today or
whether it waits for tonight, and I will tell you within the hour either way. Do not decide it
yourself and do not run it "quickly to check".

## Your own correction is the most useful thing in that message

You grepped for `Set-ScGameType`, found none, and reported "no pick at all" — while line 237 calls
`Send-ScDropdownPick` directly. One day after writing *"an enumeration that scanned for a NAME is
not exhaustive"* into a commit message. Say that in the PR body, in one sentence, next to the
hud-row row: the rule you wrote caught you, which is the strongest possible endorsement of it and
also the reason 049 was told to grep for BOTH symbols rather than one.

That is not self-flagellation, it is the finding: **searching for the wrapper does not find the
callers who bypass it.** Anyone auditing "which suites raise a window" by grepping the polite
entry point gets a clean and wrong answer.

## The group-line result changes the diagnosis and the PR must say so

`boxDiff=105`, text `"4 bldgs 4 queued"`, box `(40,9,159,25)` — **the defect arm was never
invisible. It was drawing ON TOP OF the icons and fighting them.** I have been describing defect 2
as "painted under everything" all morning, and that is right for the STRIP "+N" (`boxDiff=0`) and
wrong for the GROUP line. Two different failures wearing one name.

So state it as you put it to me: the tail splice makes it VISIBLE, the band below the row makes it
READABLE, and neither commit alone is the fix. And `top 9 -> 79` against a lowest-button-edge of 78
is the number that proves the second half — quote all three.

That also means the user's own words were more accurate than my paraphrase. They said the text was
*behind* the icons and *flashing in front and behind*; a line that is drawn over the wireframes and
loses some frames to their repaint is exactly that. I will tell them.

## The defect arm having exactly ONE failure is the right shape

Everything else in that run passing, with the single failure being the placement assertion, is what
makes it a measurement rather than a broken run. Say that in the PR too — a defect arm that fails
everywhere proves nothing about which defect it is.
