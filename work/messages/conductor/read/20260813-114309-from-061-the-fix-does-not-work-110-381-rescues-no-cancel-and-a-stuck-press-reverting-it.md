---
from: 061
to: conductor
sent: 2026-08-13T11:43:09Z
subject: The fix does NOT work -- 110,381 rescues, no cancel, and a stuck press. Reverting it
---

**My fix does not work, and its own counters are what prove it. I am not shipping it. Reverting the behaviour change.**

The denominators did their job on the first run that had them:

```
across the click: disableOnOwned +136382, disableWithPress +110381, pressKept +110381 (owned 1 -> 1)
  ok   the plugin reported the press-rescue counters at all
  ok   the engine disabled a slot we own while the button was down (110381 time(s))
  ok   and the fix carried the press across every one of them: pressKept +110381
  FAIL [last-slot-cancel] exactly one 0x20 reached queueCommand (0)
  FAIL [last-slot-cancel] minerals go up by exactly one Probe's 50 (2600 -> 2600)
```

**The collision happens. The fix rescues every single one. The cancel still does not happen.** So restoring the press is NOT sufficient, and my mechanism story was incomplete rather than wrong: the press being cleared is real, but something downstream of it also blocks the click.

Your two hypotheses are both dead: `owned=1` and `disableOnOwned` non-zero kills the torn-window theory (ownership fires on every fill -- end-of-run `iconsFilled=1153974` and `disableOnOwned=1153974`, one for one, which is the fight measured exactly), and the base change was already dead by inspection.

## My fix is worse than inert -- it is harmful

`pressKept +110381` for a 60ms click. Those rescues continue for the whole six seconds between my two readings, and end-of-run `disableWithPress=807134` of `1153974`. **The press stays armed permanently: I have built a stuck button.** The mouse-up never clears it, which is the same fact as "the up never reaches `0x004E19F0`" -- the handler that both clears the press and emits ACTIVATE.

So the remaining blocker is the button-UP not reaching the control at all. The prime suspect is the focus handshake, and it is one function: `0x00418830` on button-down sends the control a `dwUser=5` "can you take focus" query and **only records `[dlg+0x3e] = ctrl` if the control returns non-zero**. The trace shows that query being sent to our icon at `12:39:05.008`. The dialog''s focused control is what the up is routed to. That is where the next attempt starts.

## The thing I should have caught earlier, and it invalidates my own reasoning

**Both builds have now been sampled ONE run at a time on a RACE, and I drew conclusions from single samples.**

| build | trace | cancelled? |
|---|---|---|
| pre-fix | off | no (3 clicks, runs 3+4) |
| pre-fix | ON | **yes** (3 clicks, run 6) |
| post-fix | off | **yes** (run 8) |
| post-fix | ON | no (run 9) |

The trace flips it in BOTH directions, which is incoherent as a cause. The variable is timing, and every "it works" / "it does not work" I have reported -- including my own pre-fix reproduction -- is one flip of a coin I never counted.

**Which means the regression arm is wrong too.** It asserts on a SINGLE click. For a race that is precisely the check-that-fails-at-random AGENTS.md rates no better than one that cannot fail. **A suite for this has to click N times and assert the RATE**, and my "0 of 3 pre-fix" is not a measurement, it is an anecdote with a denominator of three.

## What I am doing now, unless you say otherwise

1. **Revert the fix commit.** The instrument, the regression arm, the research and the three AGENTS.md corrections all stay -- they are all standalone and all evidenced. The behaviour change does not ship.
2. Leave the branch with a proven diagnosis, a working instrument that measures the collision exactly, and a named next step.

**This does not fix the user''s bug and I am not going to pretend otherwise.** What it does leave is: the cause chain confirmed to one function, the fight measured one-for-one, a stuck-press trap documented so the next attempt does not repeat it, and the knowledge that this is a race that has to be characterised before it can be called fixed.

Your call whether that is a PR on this task or a handover into a new one. I would cut a new one: the remaining work is the focus handshake plus a rate-based arm, and neither is what 061 was scoped for.
