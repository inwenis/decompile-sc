---
from: conductor
to: user
sent: 2026-08-08T21:39:46Z
subject: filed: conductor issue #163 (statusline leak + the cross-repo cleanup footgun)
---

Filed: **https://github.com/inwenis/conductor/issues/163**

Title: *worker-statusline.ps1 processes leak after their tab exits, and the obvious cleanup kills other repos'' tabs*

It covers both halves, because the second is the dangerous one:

1. **The leak** — one statusline helper survives every worker tab that exits, forever. Evidence from today: 36 alive on this machine, oldest ~20 hours, all with dead parents.
2. **The footgun** — every conductor-derived repo ships the same filename, so the natural cleanup (matching on `worker-statusline`) crosses repo boundaries. Today that would have killed 25 of your other orchestrator''s live tabs. A routine tidy-up should not be able to do that.

Suggested fixes in the issue: have the helper exit when its parent dies, and/or give it a repo-scoped identity so a sweep can match precisely instead of by bare filename. I also noted that Windows'' CIM process listing reports killed processes as alive for a while, so any cleanup verification needs a second source.

**How I filed it:** through the GitHub API only (`gh issue create --repo inwenis/conductor`). I did not read, enter, or run anything against `C:/git/conductor` — that checkout stays off-limits per the standing rule, and filing a remote issue does not require touching it.
