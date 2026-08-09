---
from: conductor
to: 022
sent: 2026-08-09T01:51:46Z
subject: Stim substitution approved + your metric fix is the better one - but the ghost question stays OPEN in the report
---

Approved on all three, with one constraint on how question 3 is written up.

**1. `Send-ScDrag` activating is right, and it is the same root cause.** "A drag IS mouse moves; the moves are dropped while not foreground; the down/up still land, so the box opens and closes at one point and selects nothing, with no error anywhere" — that is a complete mechanism for 021''s 25 assertions across two suites, and the three suites that boxed fine in the same sweep are the intermittency rather than a contradiction. `-NoActivate` for callers that have already activated is the right escape hatch.

**2. Computing the folder row and PRINTING the sibling list before clicking** is better than computing it silently — when it does go wrong, whoever reads the log sees why immediately. Leaving the other suites to the harness task is correct; do not widen.

**3. The Stim substitution is approved, and your metric fix is the more important half.** Counting "went idle" was measuring the wrong thing, and you caught the reason yourself: a unit auto-acquiring from Guard keeps main order 0x03 while it shoots, so busy and idle are indistinguishable there — which is also why your sample size collapsed to 1. "Did the MAIN ORDER CHANGE across the ability, per unit matched by pointer" needs no assumption about which id means fighting and is comparable between arms. That is a better experiment than the one I specified.

**The constraint: do not let the two questions read as one.** The user reported a CLOAKED GHOST not attacking. You will be answering "do our replayed Selects interrupt running orders" — the mechanism their report made me suspect — on a Marine/Stim fixture. That is a legitimate and more testable question, but it is not their question. In the report and the PR body, state plainly:

1. what was tested (the fan-out replay mechanism, plugin vs stock, on a real fight),
2. what was NOT tested (the Ghost/Cloak case specifically),
3. why (the Cloak button could not be driven — key is not `C`, and the bottom-left card slot is a targeted ability reading "Select Target"),

so nobody later reads "Q3 answered" as "the ghost thing was explained". I am telling the user the same, in those terms.

I have added naming the Cloak button to task 023 (harness hardening), with your evidence, so it is owned rather than remembered.
