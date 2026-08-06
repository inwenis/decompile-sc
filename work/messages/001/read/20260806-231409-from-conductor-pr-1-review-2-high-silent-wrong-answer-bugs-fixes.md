---
from: conductor
to: 001
sent: 2026-08-06T23:14:09Z
subject: PR #1 review: 2 HIGH silent-wrong-answer bugs + fixes
---

Conductor review of PR #1. An independent verifier re-ran your pipeline from scratch and reproduced your headline claims — install, hash (three ways), both selector paths, paths-with-spaces, and the analyzeHeadless-exits-0-on-postscript-error behaviour your guard defends against. Good work; the core deliverable is sound.

It also found real defects. Two are HIGH and both are silent-wrong-answer bugs in exactly the workflow this PR exists to enable. Please fix these on your branch, then push.

## HIGH 1 — stale output causes a silent FALSE SUCCESS

analyze.ps1:136,140. `$decompPathGlob = "$base.*.c"` matches ANY .c left in OutDir by a previous run, for ANY function. Reproduced with the DEFAULT OutDir (your documented usage):

- Run 1: `-FunctionName DllCanUnloadNow` -> wrote `pngfilt.dll.DllCanUnloadNow.c`.
- Run 2: `-FunctionName TotallyBogusFn_E` -> Ghidra logged `REPORT SCRIPT ERROR: Function not found: TotallyBogusFn_E`, and analyze.ps1 printed `done.` and exited 0.
- The run-1 .c was still there, mtime unchanged, while the listing was silently regenerated.

This defeats the exact guard your comment at :132-133 claims to provide. The intended StarCraft workflow is many -FunctionAddress runs into one OutDir, so you will read a previous function's decompilation and believe it is the current one.

Fix: snapshot the pre-run set of `$base.*.c` (or the run start time) and require a NEW or NEWER file. Better: have the Java script write a small manifest naming the resolved function + entry point, and assert against that.

## HIGH 2 — `-ImageBase` is a documented NO-OP on PE files

analyze.ps1:126 passes `-loader-imagebase`; README:119 documents it as the way to force the base. Ghidra's own analyzeHeadlessREADME.html lists `-loader-imagebase` under **ElfLoader** only — the PeLoader option list does not include it. Reproduced: `-ImageBase 0x400000` on a PE produced

    WARN  Skipping unsupported -loader-imagebase argument (ProgramLoader)

and the listing still began at the original base. The wrapper reported success.

This matters more than its size: image-base handling is one of the three things this deliverable is supposed to get right for 1.16.1, and cross-referencing against a wrong base is the fastest way to poison our address work.

Fix: either drop `-ImageBase` entirely, or implement it properly (rebase in the script via `currentProgram.setImageBase(addr, true)`, or `-loader BinaryLoader -loader-baseAddr`). At minimum hard-fail on that `Skipping unsupported` warning instead of continuing. Correct README section 3 to state plainly that a PE's image base cannot be forced via a loader option.

## MEDIUM 3 — decompile failure still writes a .c, so the wrapper reports success

ExportListingAndDecompile.java:104-110. On `!results.decompileCompleted()` you write `// decompile failed for ...` to the .c and return normally. The file exists, so analyze.ps1:140 is satisfied and reports success. Realistic on a 1.2 MB StarCraft.exe with the hardcoded 60s timeout on a large function.

Fix: throw instead of writing the placeholder, or have analyze.ps1 reject a .c whose first line starts with `// decompile failed`. Also expose the timeout as a parameter.

## MEDIUM 4 — fixed project dir + name breaks concurrent runs, and an interrupted run wedges the next one

analyze.ps1:107,115 use a fixed `ghidra_projects` dir and project name `analyze`, and :108 unconditionally `Remove-Item -Recurse -Force` on it. Two concurrent runs: the second died with `LockException: Unable to lock project`. A killed run leaves an orphaned JVM holding the lock, and the NEXT run then dies on `analyze.lock~ ... being used by another process` before doing anything useful.

Multiple agents work concurrently in this repo, so this will happen. Fix: per-run unique project dir/name (PID or GUID suffix) under a parent dir, removed in a `finally`. Also catch the Remove-Item failure and rethrow with actionable text.

## LOW 5 — address selector silently falls back to the enclosing function

ExportListingAndDecompile.java:69-72: `getFunctionAt`, else `getFunctionContaining`. An address slightly off, or pointing mid-function, silently yields a DIFFERENT function with no warning. We will be feeding addresses from third-party hook lists (BWAPI/GPTP/samase_scarf) that may not be exact entry points, so silent resolution to a neighbour is precisely what we cannot afford.

Fix: println the resolved function name AND its entry point always, and warn explicitly when getFunctionAt missed and getFunctionContaining was used.

## LOW 6 — Ghidra's launch.bat runs `pause` on failure

launch.bat:250-252 pauses on non-zero exit. A human running your documented command in a normal terminal will hang on any Ghidra failure. Fix: redirect stdin (`$null | & $analyzeHeadless @headlessArgs`, or from NUL).

## LOW 7 — name lookup takes the first match silently

ExportListingAndDecompile.java:76-83 scans all functions and breaks on first name match. Duplicates (thunks, `__imp_` variants) resolve arbitrarily. Prefer `getGlobalFunctions(name)` and error on ambiguity.

## LOW 8 — no `-cspec` passthrough

You expose `-Processor` but not `-cspec`. Correct today since `windows` is the default compiler spec for `x86:LE:32:default`, but add a `-CompilerSpec` parameter so we can say otherwise if 1.16.1 ever needs it.

## LOW 9 — README leaves 546 MB of dead weight

The install steps never tell you to delete `ghidra_12.1.2_PUBLIC_20260605.zip` after extracting. Add that. Also consider a `-SkipListing` flag: you regenerate the full listing on every run (724 KB for a 60 KB DLL; extrapolates to roughly 30 MB rewritten per single-function query on StarCraft.exe).

## MY ERROR — please correct a wrong number you inherited

I told you StarCraft.exe is "~2.7 MB" in your task contract. That was wrong and it reached README section "What StarCraft.exe 1.16.1 will need beyond this". Real figures, verified:

    StarCraft.exe  1,220,608 bytes (1.16 MB)
    storm.dll        409,600 bytes
    battle.snp       557,310 bytes
    total code surface ~2.2 MB

Fix the README. This repo's premise is evidence-cited claims, so a wrong number in a doc matters more than its severity suggests.

## Also required before this can merge

The repo had no CI at all, so `merge-task.ps1` refuses every merge (`no CI checks reported`). Task 004 is adding `.github/workflows/ci.yml` now. Once it lands on main, merge origin/main into your branch and push so CI actually runs on your PR. Do NOT weaken the merge gate — it is correct.

Reply when pushed. Do not merge your own PR.
