---
from: conductor
to: 022
sent: 2026-08-09T02:13:08Z
subject: Q3 accepted - a clean negative, and you confirmed the foreground root cause on someone else's suite
---

**Q3 accepted.** The bracketed controls do exactly what they needed to: the ability window sits BETWEEN the two controls and is quieter than the one preceding it — eight order changes against ten — which is what "no effect" looks like in a fight that is decaying on its own. And the individual changes being `0x03`/`0x06`/`0x02 -> 0x0a` (units arriving and STARTING to shoot) is the detail that turns a number into an explanation.

**My point 1 is now in the data instead of in an argument, and you said it in the right words.** The stock arm recording ZERO order changes in all three windows means that arm could never have shown an interruption even if one existed. Naming the plugin-arm-against-its-own-control as the primary evidence and stock as a weak corroborator is the honest framing, and it is stronger science than presenting two symmetric arms would have been.

So the answer is: **our replayed Selects do not interrupt running orders.** A negative result, properly powered, with the falsifiability argument stated — a landslide is what a real interruption would have produced.

**You have also confirmed the foreground root cause on someone else''s failing suite**, which is the part I most wanted. `test-selection-circles` boxing correctly with activation, after failing on `Send-ScDrag` selecting nothing in 021''s sweep, converts that from attributed to confirmed — across two tasks and three symptoms (dropdown, drag box, minimap). Put that in your PR body explicitly; it is evidence for work outside your own task and it should not be buried in a suite table.

**On the remaining `CIRCLES stats on detach` failure: you and 021 have independently produced the two halves of a complete diagnosis.** They established it is upstream of their code (the preceding `STATS` line is missing too, so the whole of `ScFanoutLogStats` never reached the log, and three other logs from the same build have all three lines). You found the mechanism (exit path switches to a TRY-lock and drops the line if another thread holds it; the observer wrote 1.4 s earlier). Together that is a benign log-write race at process exit that costs a real assertion.

I have recorded the combined diagnosis in task 023 with the fix options, so **stop investigating it** — re-run once to see whether it reproduces, report the count either way, and leave the fix to 023. Do not spend more of this task on it.

Report the remaining suites individually as planned.
