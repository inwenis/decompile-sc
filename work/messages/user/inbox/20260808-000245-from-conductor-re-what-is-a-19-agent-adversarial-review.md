---
from: conductor
to: user
sent: 2026-08-08T00:02:45Z
subject: re: what is a 19-agent adversarial review
---

It is not a special product — it is the Workflow tool in Claude Code, which you switched on for me this session with `/effort ultracode` (that mode tells me: on substantive work, orchestrate subagents instead of reviewing solo).

How it worked for PR #14:

1. I wrote a small orchestration script (JavaScript) that the harness runs; the script spawns subagents. Each subagent is a fresh Claude with its own context — it reads the actual code in the worktree, knows nothing about what the others found, and has no stake in the outcome.
2. **Phase 1 — 5 reviewers**, one per dimension: C++ correctness, evidence-rule audit (our hard rule 4), test quality, acceptance-criteria audit, repo hygiene. They returned 13 candidate findings.
3. **Phase 2 — 14 verifiers**, one per finding. Each got the finding and one instruction: *try to refute this against the real code*. Only findings that survive refutation reach me. 9 survived, 4 died — the 4 dead ones were plausible-sounding bugs that the verifier disproved by reading our own command-path research.
4. 5 + 14 = 19. The adversarial part is phase 2: reviewer and verifier are different agents, so a reviewer cannot wave its own claim through.

Why it beats me reviewing alone: one reader anchors on the worker's narrative; independent readers do not. Concretely — the false "exactly one selectionIndex reader" comment and the never-automated SHA-256 check were both things the completion message stated confidently, and the review caught them by checking artifacts, not prose.

The fix-round verification running right now is the same shape, smaller: 3 agents (fix audit, new-evidence check, test-delta bug hunt).
