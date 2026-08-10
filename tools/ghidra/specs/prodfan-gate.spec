# The client-side gate in front of group production, task 030.
#
# label,addrHex
#
# WHY THESE. The in-game baseline run (tools/plugin/test-group-production.ps1 -Arm
# baseline) read the command card out of the engine's own memory with four Command
# Centers selected and found the Train button not merely greyed but ABSENT -- no Button
# record assigned to its control at all. The same card with ONE selected has it enabled.
# The three slots that vanish are exactly the three whose condition is 0x00428E60, and
# the two that survive are exactly the two that are not; so this function is the gate,
# measured rather than inferred. These are the functions that decision is made in.
#
#   btnTrainCondition  0x00428E60 -- the condition on the Train button AND on the two
#                      addon buttons (slots 7/8, cparam 107/108, action 0x00423D10).
#                      research/production-queue.md 4.1 quotes its multi-select refusal;
#                      what this task needs from it is its CALLING CONVENTION -- which
#                      register holds the unit and which holds the button's cparam --
#                      because a detour must relax it for Train WITHOUT relaxing it for
#                      the addons, and the cparam is what tells those apart.
#   requirementGate    0x0046E1C0 -- the condition's tail call, the player's tech check.
#                      Acceptance criterion 5 turns on whether it also refuses a building
#                      that is the wrong KIND of producer, or only checks the player.
#   trainEmitter       0x004234B0 -- the 0x1F emitter the button's action field carries.
#   addonEmitter       0x00423D10 -- the action on slots 7/8, i.e. what must NOT become
#                      clickable for a group.
#   btnCond429520      0x00429520 -- the rally button's condition, which SURVIVES a
#                      multi-selection. The control: whatever 0x00428E60 does that this
#                      one does not is the refusal.
#   btnCond4287D0      0x004287D0 -- slot 9's condition, survives likewise.

btnTrainCondition,0x00428E60
requirementGate,0x0046E1C0
trainEmitter,0x004234B0
addonEmitter,0x00423D10
btnCond429520,0x00429520
btnCond4287D0,0x004287D0
