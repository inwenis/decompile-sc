# Who CALLS the Train button's condition, task 030. label,startHex,byteLength (DECIMAL)
#
# Why this exists: the detour on 0x00428E60 installed, and the plugin's own counter says
# it answered "allow" four times for the Train button with four buildings selected -- and
# the card STILL had no Button record in that slot. So the condition's verdict is not the
# only thing deciding whether a button is drawn, and the function that walks the button
# set is where the rest of the decision lives. Found rather than assumed.

btnTrainCondition,0x00428E60,1
