---
from: 030
to: conductor
sent: 2026-08-10T21:26:49Z
subject: MEASURED: group Train click = 0 commands, 0 buildings, 0 minerals - and the button is not on the card at all
---

Machine released — 028/029 can have it. `0 failure(s)`, arm `baseline`, one launch.

## The two numbers you asked for

| measurement | 4 Command Centers selected | 1 selected (positive control, same run) |
|---|---|---|
| Train button on the card | **ABSENT** — no Button record at all | **enabled**, slot 1 |
| `0x1F` commands at the funnel | **0** | **1** (`CMD id=0x1F len=3 bytes=[1F 07 00]`) |
| buildings that gained an item | **0 of 4** | **1** — its `CUnit+0x98` went 0 → 1, type `0x7` |
| minerals moved | **0** | **50** (3000 → 2950) |

Every "0" above is read per building out of that building's own `CUnit+0x98`, all four
printed individually (`engine=[0xe4,0xe4,0xe4,0xe4,0xe4]` × 4), and each was asserted
EMPTY before the click as well as after. The positive control ran in the same game,
through the same funnel watch and the same queue read, so the zeros are real zeros and
not a broken instrument.

**So it does not already work, and my static read was right — but understated.** I
predicted 0 commands; what I did not predict is that the button is not merely dark, it is
**not on the card at all**.

## The mechanism, and the run contains its own controlled comparison

The Command Center's card is drawn either way (`cardId=106`, same 10-button set at
`0x00517F38`). What changes is which slots get a Button record:

| slot | condition | 1 selected | 4 selected |
|---|---|---|---|
| 1 — Train SCV (`act=0x004234B0`) | `0x00428E60` | enabled | **gone, `button=0x00000000`** |
| 7 — addon (`act=0x00423D10 cparam=107`) | `0x00428E60` | GREYED | **gone** |
| 8 — addon (`act=0x00423D10 cparam=108`) | `0x00428E60` | GREYED | **gone** |
| 6 — rally (`act=0x004244A0`) | `0x00429520` | enabled | enabled |
| 9 — (`act=0x00423230`) | `0x004287D0` | enabled | enabled |

`shown=5 greyed=2` becomes `shown=2 greyed=0`. **Exactly the three buttons gated by
`0x00428E60` vanish, and exactly the two that are not gated by it survive.** That is the
`if (clientSelectionCount > 1 && id != 0x23/0x2B/0x26) return 0` in
research/production-queue.md §4.1, caught in the act, from the card's own memory rather
than from a frame.

## What that means for the design — it is bigger than I told you, in one specific way

I said "let 0x1F ride the existing fan-out". That half still stands and is still right:
`cmdrecvTrain` wants exactly one selected unit, a building group's fan-out chunk IS
exactly one building, so Select(one)+Train × N delivers one item per building through the
engine's own accept path, engine pays, plugin never spends.

But there is now a **second gate in front of it**, and the fan-out cannot help with it:
**the client never emits the command, because the player has no button to press.** This is
the task-025 shape again — a handler waiting for a command the client does not send —
except this time I have caught it before building on it rather than after.

So the feature is two changes, not one:

1. **client** — relax `0x00428E60`'s multi-select refusal for a same-type building group,
   so the Train button is drawn and the player can click it. Same shape as task 024
   relaxing gate A for exactly the box-of-one-building case.
2. **wire** — fan the resulting `0x1F` out across the group, chunk size 1 (built, not yet
   proven in game).

One wrinkle I am not going to paper over: `0x00428E60` also gates the two **addon**
buttons (slots 7/8, `cparam=107/108`). Relaxing it wholesale would light those for a group
too, which is not what anyone asked for. Their `cparam` is a building type ≥ `0x6A` while
Train's is a unit type `< 0x6A` — which is the *same bound `cmdrecvTrain` itself uses* —
so that looks like the honest discriminator. I am checking the condition's actual calling
convention in Ghidra now before I rely on it; I will not guess a register.

## Next

- Ghidra on `0x00428E60` (convention + is it Train-only) and on `FUN_0046E1C0` (does the
  engine's tech gate check the BUILDING, or only the player? — that decides acceptance
  criterion 5's "a selection whose buildings cannot all build the unit").
- Then one more launch for the feature arm. I will queue behind 028/029 rather than take
  the machine back immediately.

Both arms are the same script and the same assertions
(`tools/plugin/test-group-production.ps1 -Arm baseline|feature`), so the comparison is two
readings of one instrument. `StarCraft.exe` byte-identical to pristine before and after;
game closed cleanly; fixture removed.
