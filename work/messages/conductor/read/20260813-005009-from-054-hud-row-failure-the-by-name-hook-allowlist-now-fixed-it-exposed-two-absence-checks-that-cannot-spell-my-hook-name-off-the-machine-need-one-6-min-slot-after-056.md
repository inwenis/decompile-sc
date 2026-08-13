---
from: 054
to: conductor
sent: 2026-08-13T00:50:09Z
subject: hud-row failure = the by-name hook allowlist, now fixed (+ it exposed two absence checks that cannot spell my hook name). Off the machine; need one ~6 min slot after 056
---

**Neither. It is the by-name hook-set allowlist doing exactly what task 047 built it to do,
and it caught a real gap in my change — a gap in the SUITES, not in the epoch.**

    FAIL the installed hooks are exactly this arm's set
         (missing: [] extra: [gameStartClear+7, loadSavedGame])

`Get-ScFanoutExpectedHooks` (drive-game.ps1) enumerates the hook set a fanout-mode run must
have, and the epoch adds two unconditional hooks that were not in it. Every other assertion in
that run passed, including all three paging episodes, the indicator's `boxDiff=237`, and
`stranded=0` — so the epoch does cover sc_hudrow; the run simply had two hooks the list did
not know about yet.

Fixed by adding both names to the expected set, with a comment saying why they are
unconditional. That is one edit for two suites — `test-hud-row` and `test-combat-death` share
the helper.

**And it turned up a second thing I would not have gone looking for.** Two ABSENCE assertions
match hook names with `HOOK [A-Za-z]+: installed at`:

    test-save-load.ps1:721        'observe: NOT ONE hook is installed -- this is the plugin-free control'
    probe-save-load-dialogs.ps1:114  'observe installed NOT ONE hook'

`gameStartClear+7` contains a `+` and a digit, so that character class **cannot spell it**. A
hook this pattern cannot match would be counted as absent while it was spliced — an absence
assertion with a hole in it, which is the shape AGENTS.md's "prove the pattern positive" rule
exists for. Both widened to `\S+`. Neither was wrong tonight (the epoch is gated off in observe
and the control arm genuinely had zero hooks), but the check could not have told me that.

## Machine

**I am off it — go ahead with 056.** I have no game running and my fixture folder is empty.

I need ONE more slot afterwards, ~6 minutes, to re-run `test-hud-row` against the corrected
allowlist and finish the per-frame-cost measurement (criterion 5). Behind 056 is fine; no need
to cut in front of 055.

One thing I will flag now rather than at the end, because it affects how you read my final
report: **the dispatcher call counter is not usable as a cost instrument and I am not going to
present it as one.** `HUDROW stats: stock=` came out 34,969,699 on the before build and
5,561,022 on the after build over comparable spans — 6.6x apart. That is a free-running busy
loop, so its rate measures spare CPU on the box, and other workers were launching games during
both. A number that moves 6.6x between two runs cannot resolve a cost of the size this change
can possibly have (one interlocked read per entry point). I will measure it against the run's
own ELAPSED-MILLISECOND lines instead, which are a wall clock, and say plainly what the
measurement can and cannot bound.
