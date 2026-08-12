---
from: 043
to: conductor
sent: 2026-08-12T07:52:16Z
subject: DONE: PR #52 open -- off-screen runs work, [5] failure proven pre-existing on main
---

PR: https://github.com/inwenis/decompile-sc/pull/52 (also in Status.pr)

## Acceptance criteria

1. **One suite, both desktops, same assertions.** `test-selection-circles.ps1`, unmodified,
   assertion-for-assertion identical off-screen and visible -- same counts (3->2, 12/12,
   12 vs 12, 12->11, 24 ordered), same circle coordinates (147,196), same final accounting
   (shown=24 hidden=12 held=12 lost=0), same single failure. Nothing on the monitor, checked
   two ways: the run asserts its own desktop is not the input desktop, and
   `watch-foreground.ps1` across the whole run says "no StarCraft window was ever foreground"
   (`C:\sc-work\logs\043\fg-offscreen.txt` -- and the trace shows the user actively using
   Chrome and File Explorer straight through it).
   Bonus: `test-stim-fanout.ps1` -- fixture generation, Game Type, keyboard, 36 units --
   also ran off-screen with **0 failures**.
2. **Runtime, measured.** 75.0s off-screen vs 75.2s visible (`time-suite.ps1` wall clock,
   same suite). Isolation costs nothing. A first off-screen sample read 84.7s; that was
   machine noise (the foreground trace shows the user working through that exact window) and
   the phase table charges it to launch and a log wait, not to anything desktop-related.
   Task 040's independent 75.03s for this suite is what makes the visible baseline solid.
3. **One flag, same code path.** `-Visible`: same generated child script, same CreateProcess,
   same suite arguments; only the desktop name differs. No separate watch mode exists.
4. **`sc-launch-lock.ps1` untouched** -- not one line. Every transcript shows acquire/release.
5. **Frames stayed off the repo.** Gitignored diagnostic paths only, no pr-image. Paths for
   the user are listed in the PR body per today's standing rule.
6. **See below.**
7. `scripts/run-ci-local.ps1`: PASS, receipt at HEAD (`5932f78`). ruff skipped, not installed.
   Actions outage noted in the PR body, not chased.

## Criterion 6 -- the "[5] more than 12 units" failure: GENUINELY PRE-EXISTING

Ran `test-selection-circles.ps1` on a clean `main` worktree at `c0b69dc` with its own fresh
plugin build, visibly, nothing of mine in the path:

    [5] a 24-unit drag box circles the 12 the engine threw away
      FAIL the box contained more than 12 units

Same single assertion, every other assertion in the suite green -- identical to both of my
arms. **We did not break it.** Task 040 was right, it just had not shown it. Not fixed here,
as instructed.

What it actually asserts, for whoever picks it up: that the plugin's
`SORT candidates=N -> selected=M` line reports `N > 12` for that drag box. Worth its own
task, and worth knowing that the box selects the RIGHT units regardless -- the shadow list,
the circle count and the fan-out all independently agree on 24 boxed / 12 over-cap in the
same run that fails this line. So the suspect is the SORT diagnostic or its regex, not the
feature.

## The one real limitation, measured not assumed

**A dropdown pick cannot work off-screen, ever.** Windows has one foreground window and it
belongs to the desktop receiving input, so a window on an invisible desktop can never hold it
(`GetForegroundWindow()` reads 0 there all run), and `Send-ScDropdownPick` needs the
foreground for the game's `SetCapture`. `probe-quiet-dropdown.ps1` through `run-offscreen.ps1`
failed ALL THREE arms -- including arm C, the foreground control that passes every time on
the monitor.

Why it is a footnote rather than a blocker for the other suites:

* `Set-ScGameType` skips the pick whenever the combo already reads the wanted value
  (issue #29), which is the common case on this machine -- `test-stim-fanout` took that path
  and ran clean off-screen.
* When a pick IS needed the run throws and NAMES THE DESKTOP as the cause, pointing at
  `-Visible`. It never silently runs a lesser test. I improved that message in this PR; the
  old one sent the reader hunting for a modal dialog that does not exist.

If you want the remaining game-type suites converted and proven one by one, that is a small
follow-up task -- the mechanism is done and two suites of different shapes are proven on it.

## One thing the CI caught that is worth your attention

`tests/deploy-runtime.Tests.ps1` failed this branch: `run-with-plugin.ps1` grew a dot-source
(`sc-desktop.ps1`) that `tools/deploy.ps1` did not copy, which would have shipped the USER a
launcher that throws on a machine with no repo -- silently, since their shortcut runs
`-WindowStyle Hidden`. Fixed in the PR. That test earned its keep.

## Machine state

Free and clean: no StarCraft process, no fixture folder left behind
(`Maps\BroodWar\00-t043` removed by the suite), the clean-main comparison worktree removed,
the launch lock released. I am idle and listening on my inbox.
