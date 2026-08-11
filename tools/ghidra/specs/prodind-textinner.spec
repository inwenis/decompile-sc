# Task 033: the last two links of the text path.
# updateControlInner 0x0041C200 -- what updateControl 0x0041C400 tail-calls once the
#   control's clipped rect is non-empty; this is what reaches the control's own fxnUpdate.
# allocDialogSurface 0x004C35F0 -- the dialog's own pixel surface (BinDlg+0x10) and the
#   width field at +0x0C; needed to read INK back out of the surface as a draw oracle.
updateControlInner,0x0041C200
allocDialogSurface,0x004C35F0
