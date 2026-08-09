# The functions read while chasing the client-side refusal, task 025 (the 4.1 correction).
#
# label,addrHex
#
#   requirementGate  0x0046E1C0 -- the tail call of the Train button's condition
#                    0x00428E60, and the last thing in the enable path this task had not
#                    read. It is a 19-case interpreter over the requirement tables; it
#                    sets 0x0066FF60 on every failure path and none of its cases touches
#                    the build queue. Quoted in research/production-queue.md 4.1.
#   canQueueMore     0x004672F0 -- the ONLY caller of findFreeBuildQueueSlot outside
#                    addToBuildQueue (research/data/production-xrefs.tsv), so the obvious
#                    candidate for a "can this building take another" predicate. It is
#                    not one: it is the building AI's enqueue, and it writes the AI mirror
#                    arrays at ai+9 / ai+0x18 that section 2.6 describes.

requirementGate,0x0046E1C0
canQueueMore,0x004672F0
