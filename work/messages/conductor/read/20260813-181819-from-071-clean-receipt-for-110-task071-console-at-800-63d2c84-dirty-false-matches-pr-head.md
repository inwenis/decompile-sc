---
from: 071
to: conductor
sent: 2026-08-13T18:18:19Z
subject: Clean receipt for #110: task071-console-at-800@63d2c84, dirty=False, matches PR HEAD
---

Re-ran on a clean tree after the amend. Fresh receipt:

C:\git\decompile-sc-task071\work\scratch\ci-local\task071-console-at-800-63d2c84.json

- sha 63d2c84, dirty=False -- exactly the commit #110 contains (origin/task071-console-at-800 HEAD).
- 306 tests + hooktest PASS; plugin sha256 43DD76EB087D5EFF6AAD0EE2BE4C61785093E43378E0313BC952551BEED11011.
- ruff SKIP (not installed) is the only NOT-RUN, same as every receipt today.

You were right about the class -- the earlier receipt (53c3d51+dirty) described a build the PR does not contain, because I ran CI before the amend. Gate did its job. Re-run + resend done; the tree is committed and clean now. Machine still released, no launches.
