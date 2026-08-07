---
from: conductor
to: user
sent: 2026-08-07T08:22:00Z
subject: near-miss on the pristine-install guard (nothing happened, being fixed) + resets are now safe
---

Two quick things, then I will stop interrupting.

**A near-miss worth knowing about.** Rung 1's PR went through independent verification. The important claim held: the plugin genuinely only READS game memory, proven three ways including dumping the compiled binary's symbols to show the memory-writing APIs are not referenced at all.

But the verifier found the guard meant to stop our tooling ever touching your pristine install can be walked past. It matches the literal text `C:\sc-install`, so a forward-slash spelling slips through. That alone would just mean launching the wrong copy — except the windowed-mode switch copies a file INTO the game folder and its counterpart deletes one. So a bypassed path could have written into or deleted from your clean install.

Nothing happened. Every real run used the working copy, and your install's hash is unchanged as always. But "you would have to type it unusually" is not a safeguard, and that install is your only clean copy — so it is being fixed before that PR merges.

**Also merged:** resets no longer destroy things. Profiles, replays and generated test maps now survive by default, and you have to explicitly ask for a true wipe. I tested both directions by hand rather than trusting the report — your test map survived untouched, and the destructive mode still works when asked for. So the profile loss from earlier will not repeat.

Eleven tasks merged. Rung 1 is one fix away from done; then rung 2 (intercept selection input) and rung 3 (fan out orders so more than 12 units obey).
