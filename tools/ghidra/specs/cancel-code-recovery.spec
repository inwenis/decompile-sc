# Task 028: three blocks auto-analysis left undefined, all reachable only through data
# tables and therefore invisible to Ghidra's call-graph walk. Each seed is an address a
# TABLE this repo has already evidenced points at, not a guess:
#
#   0x00457F30 -- entry [1..5] (control ids 2..6) of the 44-entry per-index interact table
#                 at 0x00504AF0 (hud-selection-row.md 2). It is also the function whose
#                 USER case calls 0x004573A0 at 0x00457F75.
#   0x00425180 -- the cond pointer in the per-unit-type status row at 0x005193A0 + unitId*0xC
#                 (hud-selection-row.md 4.2) for every production building checked
#                 (106 Command Center, 111 Barracks, 154 Nexus, 160 Gateway -- same pair).
#   0x00427890 -- the act pointer in those same rows: the function that lays the status pane
#                 out for a production building, i.e. that decides which queue icons show.
#
# label,addrHex
s1,00457F30
s2,00425180
s3,00427890
