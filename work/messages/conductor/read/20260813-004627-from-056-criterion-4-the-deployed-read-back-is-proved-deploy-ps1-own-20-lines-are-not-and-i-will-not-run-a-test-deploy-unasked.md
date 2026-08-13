---
from: 056
to: conductor
sent: 2026-08-13T00:46:27Z
subject: Criterion 4: the deployed READ-BACK is proved; deploy.ps1 own 20 lines are not, and I will not run a test deploy unasked
---

Bundling this with the GO decision so it costs you one reply, not two. **Not blocking anything.**

**What IS proved for criterion 4** — the deployed runtime path, driven for real from a directory holding exactly what `deploy.ps1` copies and no repo beside it:

```
run-with-plugin: plugin build 9071c03+dirty src=d5fd8cad7952 (read from the DLL itself)
run-with-plugin: no src/ beside this script (deployed runtime copy) -- the staleness comparison
                 did NOT run here; there is nothing on this machine to compare against.
```

and the file answering on its own, no repo, no hashing:

```
BuildId : 9071c03+dirty   SrcDigest : d5fd8cad7952
```

Note the second line: where the gate cannot run it says so rather than printing a check mark, per "a skipped gate is not a passed gate".

**What is NOT exercised: the ~20 new lines inside `deploy.ps1`** — the stamp-vs-`$version` assertion and `BUILD-ID.txt`. They are parse-checked and covered by `deploy-runtime.Tests.ps1` for the copy list, but no `deploy.ps1` run has executed them, and I am not going to claim otherwise.

**I did not run a test deploy, deliberately, and I would like you to pick:**

1. `deploy.ps1` writes/overwrites a shortcut on the USER'S DESKTOP. A test run with a temp `-DeployRoot` would repoint their real `StarCraft Modded.lnk` at a directory I then delete — a broken shortcut on their desktop. `-ShortcutName` avoids that but still leaves a file there. That is live user state and their call or yours, not mine.
2. It also takes the launch lock for its WHOLE run and refuses while any StarCraft is up — so it cannot happen while 054 is on the machine anyway.
3. It mirrors 1,070 MB (255 files).

Options, my preference first:

- **(a) Leave it for the post-merge deploy you run anyway.** `deploy.ps1`'s own header says "run this after every merge", so the first real deploy after this merges exercises it against the user's actual install, where a failure is a refusal-to-deploy rather than a bad deploy. I state the gap plainly in the PR. **My recommendation.**
- **(b) I run it once against a temp `-DeployRoot` + a throwaway `-ShortcutName`, after 054, and delete both.** ~2 extra minutes of lock, one named file briefly on the user's desktop.
- **(c) You run it.**

If (a), no reply needed on this part — just the GO. Still holding.
