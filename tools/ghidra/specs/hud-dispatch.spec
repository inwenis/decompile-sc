# Task 017: find how RAW mouse events reach the wireframe buttons -- the button
# interact 0x004583E0 only branches on event type 3 (MOUSEMOVE) and 14 (USER), so
# a right-click must be either routed to the control as type 7 or swallowed by the
# dialog pump. This decides whether the page-flip gesture reaches the shim.
#
# Format: label,startHex,byteLength
#
# The button interact itself (its callers are the dialog dispatch we want).
wireframeBtnInteract,004583E0,1
# The default interact table entries the dialog framework calls per control type;
# type 2 = button is at +8. Whoever reads THIS table routes mouse events.
defaultInteractTable,005014AC,60
