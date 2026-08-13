# Defect patches for `tools/plugin/build-defect-arm.ps1`

Issue #78. Each `.patch` here is one deliberate, small break in `tools/plugin/src`,
meant to be applied to a throwaway copy, never to the real tree.

```powershell
./tools/plugin/build-defect-arm.ps1 -Patch work/defects/prodqueue-cap-off-by-slots.patch
```

Prints every hooktest check whose verdict changed between the unpatched (baseline) and
patched (defect) copy, grouped by the checks that caught it and the ones in the same
part that did not. Neither arm ever touches `tools/plugin/src` in the real tree.

Add a new one the same way: pick an assertion you believe is good, break the line
under it, generate the patch with `git diff --no-index` (or by hand -- see the two
here for the header shape `git apply` expects), and run it. If nothing catches it,
that is a finding about the suite, and the script says so instead of staying quiet.
