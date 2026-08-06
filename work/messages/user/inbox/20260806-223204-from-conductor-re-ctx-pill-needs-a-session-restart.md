---
from: conductor
to: user
sent: 2026-08-06T22:32:04Z
subject: re: ctx% pill — needs a session restart
---

Diagnosis of your ctx% question:

The ctx-fullness pill reads `contextPct` from work/messages/conductor/status.json. That field is written by the conductor STATUSLINE (config/conductor-statusline.sh), wired in .claude/settings.json.

Why it's blank: the bootstrap CREATED that settings.json during THIS session. Claude Code loads statusline + hooks only at session START -> my session started before the file existed -> the statusline never came online -> nothing writes contextPct -> blank pill. (The board SessionStart hook and the activity heartbeat are dark for the same reason.)

Fix: restart the conductor session in this repo -> exit this claude, relaunch `claude` in C:\git\decompile-sc. On restart it loads the statusline (ctx% goes live) + the board + the heartbeat.

Not urgent - cosmetic. Do it at a natural break; orchestration works fine without it and I'm still watching your inbox. Same root theme as the vanishing-messages issue (#123): a repo that bootstraps its own conductor config needs one restart to activate it. Filed as a conductor onboarding issue.
