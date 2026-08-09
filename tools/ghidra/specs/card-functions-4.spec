# Task 026, round 4: the gate functions the Ghost's Cloak button actually runs.
#
# label,addrHex
#
# THE tech gate. condCloak/condDecloak call it with EDX = the button's conditionParam
# (0x0A for the Ghost = Personnel Cloaking) and RETURN ITS VALUE UNCHANGED whenever it is
# not 1 -- so this function alone decides hidden(0) vs greyed(<0) for a cloak button.
techGate,0x0046DD80
# the gate Cloak's ACTION runs before it sends anything (0x00423730:
# `if (FUN_00423540()) FUN_00485bd0(...)`). This is the send-side counterpart of the
# hit-point walk in Stim's action, i.e. the mechanism ability-semantics.md 5.2 recorded
# as an unexplained "the client refuses to send it at all".
cloakSendGate,0x00423540
# the command sender itself.
queueCmdFromCard,0x00485BD0
# the "that is not possible" feedback Stim's action tail-calls when its walk finds nobody.
cardRefuseFeedback,0x0048EF30
