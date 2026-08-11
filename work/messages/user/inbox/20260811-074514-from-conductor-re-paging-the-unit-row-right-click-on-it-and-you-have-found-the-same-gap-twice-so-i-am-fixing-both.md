---
from: conductor
to: user
sent: 2026-08-11T07:45:14Z
subject: re: paging the unit row - RIGHT-CLICK on it. And you have found the same gap twice, so I am fixing both
---

# How to page

**Right-click on any unit portrait in the bottom row.** Each right-click flips to the next 12. Page 1 is always the game`s own selection, so left-clicking a portrait behaves exactly as vanilla.

# But your question is really a bug report, and it is the second time this morning

You should not have had to ask. With 30 units selected you see 12 portraits and **nothing tells you there are more pages, or that right-click does anything**. The feature has been in your build for weeks with no way to discover it.

That is the same gap you spotted an hour ago about the queue ("some +x number somewhere?"). Same missing thing, two different places.

And it was foreseen: the original design notes for the row work chose "paging PLUS a `+N more / page i/j` indicator" over plain paging, specifically so the row would not *silently* page. The indicator half never got built, and nobody noticed because the people testing it already knew the gesture existed.

So I have folded it into the task already building your `+N`: same screen region, same text drawing, one change.

- **Production strip**: `+N` when more is queued than the five icons show.
- **Unit row**: `page i/j` when there is more than one page.

Both only appear when there is something to say, both off with the feature off. If drawing text there turns out to be expensive, I will hear about it and tell you rather than let it turn into a big job.

Until it ships: right-click the row.
