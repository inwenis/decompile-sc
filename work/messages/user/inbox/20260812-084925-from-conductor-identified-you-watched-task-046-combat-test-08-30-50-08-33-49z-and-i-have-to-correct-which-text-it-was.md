---
from: conductor
to: user
sent: 2026-08-12T08:49:25Z
subject: Identified: you watched task 046 combat test, 08:30:50-08:33:49Z -- and I have to correct which text it was
---

Identified exactly. You watched **task 046's combat-death test**, and here is the precise
account rather than a reassuring one.

## What you saw, to the second

- On your monitor **08:30:50Z to 08:33:49Z** (09:30:50 to 09:33:49 your local time), about three
  minutes. Taken from the plugin's own attach/detach lines in the game process, not from anyone's
  memory.
- It had **closed 8 seconds before you sent your message**.
- Selection was 26-36 units the whole time, always over 12. "30 units" was the reading for the
  last ~83 seconds — 1143 log lines say exactly that, more than any other count. Your "30 units"
  is exact.

## Why it was on your screen at all, and it is the one case that can never be off-screen

That suite has to pick a game type from a dropdown, and a dropdown needs the foreground — which a
window on an invisible desktop can never have. So `-Visible` is not a slip there, it is the one
structural exception, and task 045 is currently sweeping which suites actually need it so the
number stops being folklore.

The other two, in full, since I promised the exact truth:

- **041**: two games visible 08:07Z-08:15Z. It launched them minutes before I announced the
  off-screen path and let them finish rather than kill them mid-run — which is what I had told it
  to do. Everything of its from 08:16Z on is off-screen.
- **039**: one game visible 08:00Z-08:05Z, launched before it had merged the off-screen path into
  its branch. Everything from 08:14Z on is off-screen.

So: three visible runs this morning, all in the 25 minutes around the mechanism landing, plus the
one structural case. That window is closed.

## The text itself — I have to correct something I told you an hour ago

I said the flashing text was our queue-indicator line and that your report confirmed 039's
finding. That was too quick. The text logged on screen during that run was
`36 units 1-12 (1/3)` ... `30 units 1-12 (1/3)` — the **unit-row paging indicator**, a different
module from the queue line 039 is fixing, in the same region of the dialog. Your own sentence
already said they share a place: *"it's the same place where I saw the number of units queued"*.
You were describing one region misbehaving; I collapsed it into one module too early.

What stands: something in that region loses a paint-order fight intermittently, and the mechanism
is understood — our text is spliced into the engine's own list of controls, and in frames where
the engine repaints what overlaps it, our text is painted over. The pane only repaints what is
dirty, which is exactly why you see it appear and disappear rather than simply never show.

What changed: I have told 039 to point its measuring instrument at the ROW indicator as well as
the queue line while it has the machine — six samples, ~700 ms apart, counting bytes actually on
the screen each time — so we find out which of the two you were watching, with a number rather
than a guess. If it turns out to be the row, it becomes its own task rather than being bolted onto
039's, because I would rather ship three proven fixes than four half-proven ones.

Either way your ask — *"find another place for the text so it's always displayed on top"* — is
the right requirement and is what both will be held to.
