# Wide windows past the end of each selection array, to find the FIRST referenced address
# after it. This is the measurement that decides relocate-vs-extend per array: an array whose
# next referenced neighbour sits N bytes away has N bytes of candidate slack; an array whose
# next referenced address is its own one-past-the-end has none.
#
# Read the result with care in both directions. A referenced address after the array is solid
# proof of an occupied neighbour. A RUN of unreferenced addresses is weaker evidence: a global
# that is only ever reached by computed index (base register + offset) never has its own
# absolute address encoded anywhere, so it is invisible to both an xref sweep and a byte scan.
# Unreferenced means "nothing in the binary names this address", not "provably free".
# Format: label,startHex,byteLength
slack_after_selectionHotkeys,00581960,8192
slack_before_selectionHotkeys,0057FC60,512
slack_after_playersSelections,00628668,2048
slack_after_clientSelectionGroup2,0059727C,1024
slack_after_recentSelectionTimes,0063FEC0,1024
