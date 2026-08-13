---
from: 056
to: conductor
sent: 2026-08-13T01:03:38Z
subject: Task 056 done -- PR #79 ready for review at af6d7e0, all six criteria
---

**PR #79: https://github.com/inwenis/decompile-sc/pull/79** — head `af6d7e0`, body rewritten with tonight's evidence. Machine still free; I need nothing more from it.

| # | criterion | evidence |
|---|---|---|
| 1 | plugin log naming its build, id = `git rev-parse --short HEAD` | `C:\sc-work\logs\056\attach2.log` → `build : af6d7e0 SRC=a634fe20f088`; HEAD `af6d7e0`, tree clean |
| 2 | dirty case says so | `f014981+dirty` / `9071c03+dirty` stamped and read back out of the DLL; `+dirty` survives into the banner |
| 3 | stale-DLL trap closed AND watched catching | `C:\sc-work\logs\056\stale-trap-demo.txt` — before/refuse/rebuild/reverse, four arms |
| 4 | deployed build reports itself, nothing hashed | deployed runtime path driven for real; `Get-ScDllBuildStamp` answers off the file with no repo. **`deploy.ps1`'s own 20 lines still unexercised — option (a), your post-merge deploy** |
| 5 | determinism decision | IN scope, done, two flags, byte-identical builds; 048's `TimeDateStamp` correction stated in the body |
| 6 | `run-ci-local.ps1` PASS at final sha | `PASS task056-build-identity@af6d7e0`, 115 Pester, hooktest 0 failures, `origin/main` merged first, cloud-CI-on-billing noted |

**Two things I would review first if I were you**, both in §6 of the body — they are defects I introduced and removed, and both are house shapes:

1. the gate rebuilding into a caller's named `-BuildDir` (a safety mechanism overwriting the thing it protects, including the user's deployed binary);
2. the base check that could not fail, which only the run exposed.

On (2), for the record and because it generalises past this task: **the Windows loader rewrites `OptionalHeader.ImageBase` in the MAPPED image to the address it actually used.** Any future check of "did my module land where it asked" must read the file, not the mapping — the mapping answers with its own input. Worth a line in AGENTS.md next to task 048's rule if you agree; I have not edited AGENTS.md myself since that is orchestration data.

Also worth recording somewhere durable: `--image-base` buys ON-DISK reproducibility only. The runtime address is ASLR's to choose, the plugin has always been relocatable, and the banner's `RELOCATED` line is the honest reading rather than a regression.
