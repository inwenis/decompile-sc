---
from: conductor
to: user
sent: 2026-08-10T20:53:28Z
subject: shortcut FIXED (redeploy done), conductor issue filed, and yes-ish on multi-building queueing
---

Three answers.

# 1. Desktop shortcut -- FIXED, redeployed, verified

You reinstalled PowerShell and that broke it. The shortcut had the Store build`s path baked in:

    C:\Program Files\WindowsApps\Microsoft.PowerShell_7.6.4.0_x64__8wekyb3d8bbwe\pwsh.exe

That folder carries the VERSION in its name, so Windows renames it on every PowerShell update. Your reinstall moved PowerShell to `C:\Program Files\PowerShell\7\`, the old path stopped existing, and the shortcut pointed at nothing.

My bug, not yours. `deploy.ps1` resolved `pwsh.exe` by asking "where is it right now" and wrote down the answer, which happened to be the one path guaranteed to change.

Fixed: deploy now prefers version-STABLE locations and explicitly REFUSES to bake any `WindowsApps\Microsoft.PowerShell_<version>` path even if that is what is on PATH. Redeployed and verified -- your shortcut now points at `C:\Program Files\PowerShell\7\pwsh.exe`. Double-click should work again. Tell me if it does not.

# 2. "Can I queue units with several buildings selected?"

Partly, and the honest answer has two halves:

- **Selecting several production buildings at once: YES**, that is the building-groups mod from last night. Box them and they are all selected.
- **Clicking Train once and having ALL of them queue a unit: NOT BUILT.** Nobody has implemented that, and I have not tested what currently happens.

What I expect happens today is that the click goes to one building only, because the >5 queue work was deliberately scoped to ONE building`s own queue -- the task file for it said so explicitly. Fanning a production command across a selected group is a different mechanism, closer to the unit fan-out.

I am NOT going to guess. It is a cheap thing to actually measure, and this project has been burned three times by reasoning instead of running. I will have it checked and tell you what really happens -- then, if it does not work, cutting it is a natural follow-up to the two production tasks already in flight.

# 3. PRs panel showing conductor and dotfiles PRs

Yes, that is a console bug, and I filed it: https://github.com/inwenis/conductor/issues/196

Evidence I put in it: this project`s own PR data is correctly scoped -- every entry in its `pr-status.json` is a `decompile-sc` URL keyed by task. So the extra rows cannot be coming from the project; the console is running its own unscoped PR query (probably `--author @me` with no `--repo`). Suggested fix is to scope it to the conducted repo`s origin, or at minimum label rows by repo.
