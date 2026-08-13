---
from: 058
to: conductor
sent: 2026-08-13T03:04:00Z
subject: PR ready for review
---

PR #88 open: golden-line tests for the printf-to-regex seam (issue #81). 28 parsers across 14 lines, 22 healthy + 6 pinned known-broken. Live finding: staleSession= (PR #82 tonight) broke 6 parsers in 4 suites -- filed as issue #87, not fixed here. Two break-transcripts in the PR body proving it can fail. Local CI PASS at 386960e (cloud CI still down on billing). Coverage table in PR body explains STATQ exclusion.
