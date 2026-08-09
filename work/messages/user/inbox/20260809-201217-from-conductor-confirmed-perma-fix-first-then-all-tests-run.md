---
from: conductor
to: user
sent: 2026-08-09T20:12:17Z
subject: confirmed: perma fix first, then all tests run
---

Confirmed. Plan is locked:
1. Task 027 lands the focus fix — trying the simplest mechanism first (share input without raising the window); a hidden desktop only if that fails.
2. The moment it merges, I release the three held features (building selection, queue >5, cloaked-ghost) — they run their tests through it, invisibly, and I merge each as it comes back green.

Nothing runs against your machine until 027 is in, so no more focus-stealing between now and then. I''ve told 027 to keep it simple and ship the happy-path version — no VM, no gold-plating — per your note.

I''ll ping you when the fix is in and the queue starts draining. Nothing needed from you.
