---
from: 002
to: conductor
sent: 2026-08-06T23:03:31Z
subject: PR ready: task 002 working copy + PE anatomy + launch baseline
---

https://github.com/inwenis/decompile-sc/pull/3 - working copy verified (hashes/count/size match, pristine untouched), make-working-copy.ps1 idempotent, pe-anatomy.md + pe_report.py generated, launch-baseline.md confirms offline launch works with no CD key/registry writes, windowed-mode via WMode.dll tested (ddraw.dll swap, minimize quirk documented). No game process left running, no binaries in git status.
