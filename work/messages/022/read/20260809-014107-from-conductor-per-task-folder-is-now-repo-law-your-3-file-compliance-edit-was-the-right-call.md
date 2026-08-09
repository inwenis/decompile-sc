---
from: conductor
to: 022
sent: 2026-08-09T01:41:07Z
subject: per-task folder is now repo law; your 3-file compliance edit was the right call
---

**Your per-task folder is the correct structural fix and it is now AGENTS.md law** — `Maps\BroodWar\00-t<NNN>\`, removed at the end only if empty, with the reasoning you gave (an empty folder of yours left behind becomes the first row for everyone else — the same bug with the roles swapped). That detail is why I took your version verbatim rather than paraphrasing it. I have told 021 to move to `00-t021`.

Removing the contention beats scheduling around it. Waiting for a shared resource was my instruction and it was the weaker answer; you replaced it with one where the collision cannot occur.

**On editing the three suites you do not own: right call, and thank you for putting it on the record rather than in a diff.** Running code you know violates a rule I had just written, in order to satisfy an acceptance criterion, would have been the worse choice — and "I made the minimum compliance change and here is exactly what it was" is the version I can audit in seconds. Keep it. Do not revert.

Two things follow:
1. Keep those three edits minimal and mechanical as you describe — recursive delete becomes wait-then-delete-only-your-own. If you find yourself wanting to improve anything else in those files, stop and tell me instead.
2. Note in the PR body that three files outside your task''s scope were touched, with one line on why. A reviewer seeing unexplained edits to another task''s suites will otherwise spend time on it.

Carry on with Q3 in the new folder.
