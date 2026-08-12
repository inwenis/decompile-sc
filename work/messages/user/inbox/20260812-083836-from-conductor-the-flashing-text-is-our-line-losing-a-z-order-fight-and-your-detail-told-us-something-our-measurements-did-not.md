---
from: conductor
to: user
sent: 2026-08-12T08:38:36Z
subject: The flashing text is our line losing a z-order fight -- and your detail told us something our measurements did not
---

Good catch, and it is worth more than it looks — you saw something our measurements had NOT
told us.

## 1. What the flashing text is

It is our own line, losing a fight it should not be in. That row of 12 icons is an engine
dialog, and our text is spliced into the same list of controls the engine draws. Task 039
measured it from inside the game this morning: the control is linked, visible, holds its text —
every field says "fine" — and **`boxDiff=0`: not one byte of it reached the screen**, because the
engine's own controls paint over it in the same frame.

**Your detail adds something we did not have.** We measured it losing EVERY frame. You are
seeing it "appearing in front and behind" — so the order is UNSTABLE across frames, not simply
wrong. That is a different and more useful symptom, and I have sent it to 039 with the
instruction not to call that half fixed until it can say whether its fix wins the z-order on
every frame or merely most of them. If it were only "most", you would still see the flicker and
we would be back here in a week.

## 2. Your "find another place for it" ask

039's fix already moves the group line into the band BELOW the icon row, measured off the live
button rectangles, and draws nothing at all when it cannot place it correctly. That may already
be exactly what you are asking for — or the band may still be inside contested space. I have
asked 039 to answer that plainly against a real frame rather than assume, and to propose a
different home if the band is not good enough. It will not silently redesign it.

That before/after pair is the one piece of evidence 039 does not have yet, and it is now first
in the queue for the machine.

## 3. What I CAN show you right now — your OTHER bug, the 5th slot

Measured this morning, both of the buildings you named, before and after:

| case | before | after |
|---|---|---|
| Command Center, 8 SCVs | `art=B`, no label, slotDiff 470 | `art=I` + label, slotDiff 57 |
| Barracks, 8 Marines | `art=B`, no label, slotDiff 631 | `art=I` + label, slotDiff 57 |

`art=B` means the fifth slot was drawing its picture out of the BUTTON-BORDER art, using the
UNIT TYPE as the frame number. That is why you saw three different wrong things in three
buildings and why the Command Center's "2" never changed: it is a function of what is queued,
not of the queue length. One bug, three symptoms — the two different before-numbers (470 vs 631)
and the two identical after-numbers (57 and 57) are that argument in four figures.

Open these — before and after line up by name:

    C:\sc-work\logs\039-frames\fifth-slot-command-center-scv-defect.png
    C:\sc-work\logs\039-frames\fifth-slot-command-center-scv-fixed.png
    C:\sc-work\logs\039-frames\fifth-slot-barracks-marine-defect.png
    C:\sc-work\logs\039-frames\fifth-slot-barracks-marine-fixed.png

and the pair taken two seconds later, which is how we show the Command Center glyph was static
rather than a flicker:

    C:\sc-work\logs\039-frames\fifth-slot-command-center-scv-settled-defect.png
    C:\sc-work\logs\039-frames\fifth-slot-command-center-scv-settled-fixed.png
    C:\sc-work\logs\039-frames\fifth-slot-barracks-marine-settled-defect.png
    C:\sc-work\logs\039-frames\fifth-slot-barracks-marine-settled-fixed.png

## 4. On seeing a run at all — the honest version

I checked the game that was running when your message arrived: it is **off-screen** (its window
is not on your desktop at all, verified by enumeration, not by trusting a flag). So that one was
not on your monitor.

What you watched was very likely an earlier run. The off-screen mechanism only merged at 07:55Z
and each worker picks it up on its NEXT launch — I told them at 08:05Z, and there were several
games in between. I have asked both workers to tell me plainly whether any run of theirs since
then went to the visible desktop, and I will pass on the answer rather than a comfortable
version of it.

There is also one case where visible is unavoidable and always will be: a game-type dropdown
needs the foreground, which an invisible desktop cannot have. Task 045 is sweeping which suites
actually need that.

## 5. One thing worth knowing about the machine

Your report arrived at a good moment. A merged bug was quietly handing workers false passes —
an off-screen run whose helper process died before starting anything reported "exit 0", which
reads exactly like success. 039 caught it, nearly took it as a pass, and said so. Task 045 is
now fixing it first, ahead of its own scope. Nothing that was reported to you rested on it.
