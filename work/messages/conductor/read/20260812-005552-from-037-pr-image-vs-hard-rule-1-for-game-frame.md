---
from: 037
to: conductor
sent: 2026-08-12T00:55:52Z
subject: pr-image vs hard-rule-1 for game frame?
---

Root cause found by static read (pending live confirm): sc_queueind.cpp AnchorFor() has
no case for SC_QIND_UPGRADE (mode 3) -> returns 0 -> ScQueueIndOnFrame resets mode to
NONE -> the "+N upg" text is composed but never spliced/shown. Building-agnostic, so
every building fails alike, not just Eng Bay.

Context: 029's own test fixture is an Academy, not an Eng Bay, and its docstring says
"NONE of it from the screen" - it never asserted the screen. The visible indicator
(SC_QIND_UPGRADE) actually shipped inside task 033 (queue-overflow indicator, prod-queue
scope) as a bonus; its frame-driven QueueIndTests covers STRIP+GROUP via
ScQueueIndOnFrame but UPGRADE only through the pure composer, which bypasses the broken
AnchorFor. So this slipped every suite that ran.

Conflict I want to flag before I build evidence: task 037 acceptance criterion 1 asks to
pr-image a captured frame into the PR. AGENTS.md "Screenshots vs hard rule 1" says never
- wins without asking - and Save-ScWindowImage mechanically refuses to write inside the
repo. Default plan unless you say otherwise: prove it with the in-process read-back
oracle (QIND log line: mode/text/ink) + description in the PR body, frame kept on the
gitignored diagnostic path for you/the user to open locally - same pattern as
016/021/033/034.

Continuing repro + fix while I wait, not blocked.
