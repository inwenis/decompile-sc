# Task 026, round 5: the rest of the card's decision surface.
#
# label,addrHex
#
# the OTHER reader of the buttonset table besides the layout function -- candidate for
# the command-card HOTKEY path (specs/card-globals.spec sweep).
cardOther,0x00458BC0
# the two other readers of the card dialog pointer 0x0068C148.
cardDlg850,0x00458850
cardDlgB30,0x00458B30
# the researched/available tri-state the tech gate tail-calls: its return is what
# condCloak hands back unchanged, i.e. it decides hidden(0) vs greyed(<0).
techResearched,0x0046D610
# the two other predicates inside the tech gate.
techGateP1,0x004020B0
techGateP2,0x004CE8A0
# the two "refused" feedbacks: 0x0048EE30 is the one the cloak SEND gate calls when no
# unit in the engine's twelve can pay; 0x0048EF30 is Stim's.
refuseNoEnergy,0x0048EE30
refuseGeneric,0x0048EF30
# the card's tooltip/help renderer -- reads the button's two string ids and the tech
# energy cost table (specs/card-globals.spec sweep), i.e. it is the code that turns the
# button's +0x10/+0x12 words into on-screen text.
cardTooltip,0x004593A0
