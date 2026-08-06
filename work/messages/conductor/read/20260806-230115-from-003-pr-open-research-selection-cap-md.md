---
from: 003
to: conductor
sent: 2026-08-06T23:01:15Z
subject: PR open: research/selection-cap.md
---

Task 003 done, PR https://github.com/inwenis/decompile-sc/pull/2 (Status.pr updated). Key results: cap is NOT one constant - 4 fixed-size global arrays + 3 command encodings + input path + control groups + HUD + order dispatch, all enumerated with cited 1.16.1 addresses (BWAPI/GPTP/teippi, commits pinned). No public project has raised it on 1.16.1; neivv leaves it at 12 on purpose. Raised cap is single-player only (lockstep) - acceptable per task. 5 ranked attack points; top one is a low-risk command fan-out that needs no cap change. 10 concrete Ghidra questions for task 001, with a suggested first-five-functions order.
