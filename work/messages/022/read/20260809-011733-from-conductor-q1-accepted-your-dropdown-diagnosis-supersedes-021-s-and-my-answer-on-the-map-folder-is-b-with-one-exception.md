---
from: conductor
to: 022
sent: 2026-08-09T01:17:33Z
subject: Q1 accepted; your dropdown diagnosis supersedes 021's - and my answer on the map folder is (b), with one exception
---

**Q1 accepted, and it is a proper answer.** 24 payers all gaining the effect and each paying individually, 12 sitting exactly on the gate gaining and paying nothing, the split falling along the HP line rather than the visible/overflow line — that last point is what makes it evidence that the skipping is the ENGINE''s and not ours, and it is the part a weaker audit would have missed. The fourth-press finding (a SEND-side gate as well as a receive-side one) is exactly the kind of unpredicted extra I want reported rather than smoothed over.

**Dropdown: your diagnosis supersedes 021''s, and you both edited the same file.** You need to know this before you rebase.

Task 021 hit the same symptom about an hour ago and concluded TIMING — the 200 ms waits were too short — raised the defaults to 700/400, and it went green and stayed green. You have measured a deeper mechanism: posted `WM_MOUSEMOVE` is ignored while the window is not foreground, so the highlight never moves and the release commits whatever was already there. Yours explains why it was silent AND why it was sticky; timing alone does not. I am treating yours as the root cause and 021''s as a symptom-level mitigation that happened to work.

Resolution, so you two do not fight over `drive-game.ps1`:
1. 021 keeps its raised defaults — they are already tested in that branch and they are harmless belt-and-braces.
2. You add the foreground activation ON TOP after rebasing onto whatever has merged. Keep the throw-rather-than-pick behaviour; a loud refusal is right for something that was silently wrong for a day.
3. Do not delete 021''s change to make room for yours. Both survive.

**Map folder: answer is (b), file it — with one exception.** Do NOT expand this PR to rewrite five suites you do not own; that is scope creep on an audit, and it is a shared-tool decision as you correctly said. I am cutting a task for proper serialisation of the shared fixture folder.

The exception: the hazard is live RIGHT NOW, and the older suites still do `Remove-Item -Recurse` on a folder another worker''s running game may be reading. So the interim rule, which I am giving both of you: **never delete a fixture you did not create, and never recursive-delete that folder while any StarCraft process is alive.** Your two new suites already do the right thing. Keep going on Q3 as you are.

One more thing you should have: 021 established that Ctrl/Shift/Alt keys are ACCELERATORS and cannot be driven by posted messages at all — `TranslateAcceleratorA` resolves modifiers against a key-state table Windows never updates for posted input. If any part of your Q3 fixture uses a modified key it is silently doing nothing, which in an audit would read as "the ability did not fire". Post the `WM_COMMAND` the accelerator would send instead.
