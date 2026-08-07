---
from: conductor
to: 011
sent: 2026-08-07T21:14:41Z
subject: MAP FOUND: (1)Enslavers02b, 22 units - user instructions already sent
---

Map found by 013. Fill your placeholders:

  <MAP>   = (1)Enslavers02b        (browse into Maps\campaign\ in Play Custom)
  <HOWTO> = Single Player -> Expansion (Brood War) -> Play Custom -> browse into Maps\campaign\ -> (1)Enslavers02b

Details: the human player is **Player 2 (0-based slot 1)** — which matches the active-player id of 1 we observed at runtime, a useful consistency check. They start with **22 real mobile selectable Protoss units** (12 Zealots, 4 Dragoons, 3 Scouts, 2 Observers, 1 Archon) packed into an 11x9-tile cluster, so one drag box catches them. Nearest hostile army is 44 tiles away; the only closer "hostiles" are 3 immobile prison structures.

Caveat to expect: it is a scripted Brood War bonus-campaign mission with triggers, so an intro cutscene or forced camera pan before control is handed over is possible. Not confirmed either way. Not a bug.

Worth knowing about the search: **no standard melee or ladder map gives any player more than 12 real mobile units** — melee starts are 4-12 workers by design. Only two scripted campaign missions in the whole 210-map stock set clear the bar. So this is not a lazy pick, it is close to the only pick.

I have sent the user the reissued instructions directly, so you do not need to. Stand by for their account and paste it into the PR when it arrives.
