# Meta progression: lineage, traits, kingdoms

## What it does

M5 makes the world remember what happened. Soldiers keep XP, rank and wounds
across battles instead of resetting; captains form dynasties with Roman-numeral
names and pick up behaviour traits (Charger, Cautious, Tyrant, Builder) from
what they actually did; kingdoms accumulate a 5-value trait vector (aggression,
diplomacy, greed, piety, cohesion) that steers stack AI, plinko drops and
recruit weapon choice; and factions can split under civil-war pressure, die out,
and hold grudges or alliances from battle history.

## Where it lives

| File | Role |
|---|---|
| `scripts/world/lineage.gd` | Captain naming/numerals, succession (heirs), behaviour-counter traits, legend naming. |
| `scripts/world/kingdoms.gd` | Kingdom trait vector, goal-weight and recruit-weapon bias, relations/diplomacy, splits, faction death. |
| `scripts/world/namegen.gd` | Syllable-table name generator (stacks, captains, kingdoms, legends). |
| `scripts/world/units.gd` | M5 fields only: `ctrait`, `c_fights`/`c_retreats`/`c_razes`/`c_settles`, `dynasty`. Rest of `Units` (soldier arrays, stacks) is [Overworld](02-overworld.md)'s. |
| `scripts/world/world.gd` | M5 fields only: `ktraits`, `relations`, `faction_alive`, `faction_color`, `faction_names`, `border_adj`, `split_cooldown`, and the `ktrait`/`add_ktrait`/`relation`/`add_relation`/`allied` helpers. Rest of `World` is [Overworld](02-overworld.md)'s. |

## How it works

### Soldier progression across battles (XP/rank persistence)
1. `Units` (`scripts/world/units.gd`) holds `xp`, `kills`, `rank` and `hp_frac`
   per soldier as plain persistent arrays — they simply outlive any single
   battle because `Units` is part of the `World` object, not the battle.
2. Before a battle, `scripts/world/battle_bridge.gd::join` copies each
   soldier's current `rank`, `weapon`, `is_captain` and `hp_frac` (scaled to
   `hp_max`), `xp` and `kills` into the fresh `BattleState` marble it spawns.
   How XP/rank are actually earned tick-by-tick inside the fight (hits,
   kills, survival, rank-up thresholds) is the battle sim's job — see
   [Battle](01-battle.md) "XP and rank gain inside battle".
3. When the battle ends, `scripts/world/battle_bridge.gd::finish` copies
   `xp`, `kills` and `rank` back from the `BattleState` into `Units`, then
   calls `scripts/world/lineage.gd::check_legend` for every marble so a
   soldier whose rank just became `LEGEND_RANK` gets a generated legend name.
   Wounds (`hp_frac`) persist the same way until healed by the Settle plinko
   outcome (see [Plinko, towns and borders](03-plinko-towns.md)).
4. A soldier who survives their faction's total defeat is not deleted: see
   "rebirth" below and [Overworld](02-overworld.md) for `BattleBridge.finish`'s
   full rebirth/mercenary handling.

### Captains/heroes and lineage (inheritance, rebirth)
1. Every captain is created through `scripts/world/lineage.gd::make_captain`
   (called from `World.create`, the HEIR plinko outcome and town garrisons):
   sets `is_captain = 1`, `dynasty[u] = [name_base, 1]`, `names[u] = name_base + " I"`.
2. `scripts/world/lineage.gd::numeral` renders 1..3999 as Roman numerals for
   display.
3. Succession runs in `scripts/world/lineage.gd::on_battle_finished`, called
   by the bridge's `finish` for every stack that fought. If the stack's
   captain died during the battle, `scripts/world/lineage.gd::_succeed` picks
   an heir: the alive, non-captain unit of the same stack with the most
   kills (ties -> lowest unit id); no candidate -> `stacks.captain_unit = -1`
   (the stack dies once its count reaches 0). The heir inherits partial
   stats: `rank = max(1, old_rank - HEIR_RANK_DROP)`, `xp = old_xp / 2`, and
   the dead captain's `ctrait`; counters reset to 0; `dynasty = [name, old_numeral + 1]`;
   `names[heir] = "<name> <numeral>"`; a line is appended to `w.events_log`
   ("`<name> <old numeral> fell; <heir name> rises`").
4. Rebirth (surviving Legend founds a new kingdom) and the mercenary fallback
   run in `scripts/world/battle_bridge.gd::_process_rebirth`, out of this slice's source
   files — see [Overworld](02-overworld.md) and ARCHITECTURE.md §13.4's last
   bullet for the full mechanic; `scripts/world/kingdoms.gd::new_faction` is
   the shared bookkeeping it (and `check_split`) both call to stand up a
   fresh faction (slot, colour, name, ktraits, plinko profile).

### Traits
Every trait effect this slice's code implements, verbatim:

| Trait (`Lineage.Trait`) | Counter that sets it | Threshold | Effect |
|---|---|---|---|
| `CHARGER` (0) | `c_fights` (winning battle, captain alive) | `>= TRAIT_THRESHOLD` and strictly the largest counter | `scripts/world/kingdoms.gd::trait_favor` moves plinko slot `RECRUIT` to board index 4 (favoured centre slot) for that captain's drops. |
| `CAUTIOUS` (1) | `c_retreats` (stack ends a battle `RETREATING`) | same | `trait_favor` favours plinko slot `DRILL`. |
| `TYRANT` (2) | `c_razes` (`Lineage.note_raze`, called by `PlinkoOutcomes` RAZE) | same | `trait_favor` favours plinko slot `RAZE`. |
| `BUILDER` (3) | `c_settles` (`Lineage.note_settle`, called by `PlinkoOutcomes` SETTLE) | same | `trait_favor` favours plinko slot `SETTLE`. |

`scripts/world/lineage.gd::update_trait` runs after any counter changes and
never downgrades: a different trait only takes over when its counter
strictly exceeds the *current* trait's own counter value (a tie leaves
`ctrait` unchanged); `ctrait == -1` (no trait yet) always loses to the first
counter that crosses `TRAIT_THRESHOLD`.

### Kingdoms (formation, merge/split, relations, alliances)
1. **Trait vector.** `World.ktraits` holds 5 floats per faction (index
   `f*5+k`, k = 0 aggression, 1 diplomacy, 2 greed, 3 piety, 4 cohesion),
   clamped to `0..1` by `World.add_ktrait`, all starting at `KTRAIT_INIT`.
   `scripts/world/kingdoms.gd::on_event` nudges them per event kind: `"win"`
   -> aggression `+KT_WIN_AGGR`; `"raze"` -> greed `+KT_RAZE_GREED`, piety
   `+KT_RAZE_PIETY` (negative); `"settle"` -> cohesion `+KT_SETTLE_COH`;
   `"retreat"` -> aggression `+KT_RETREAT_AGGR`, cohesion `+KT_RETREAT_COH`
   (both negative); `"pilgrim"` -> piety `+KT_PILGRIM_PIETY`; any other kind
   is a no-op.
2. **Goal weighting.** `scripts/world/kingdoms.gd::goal_weights` returns one
   weight per `Stacks.Goal` (used by stack AI, [Overworld](02-overworld.md)):
   `HUNT_WEAK = 3*(0.5+aggr)`, `EXPAND = 3*(1.5-aggr)`, `RAID = 2*(0.5+greed)`,
   `DEFEND = 1*(0.5+coh)`, `IDLE_HEAL = 1`, `PILGRIMAGE = GOAL_PILGRIMAGE_BASE + piety`,
   `AVENGE = GOAL_AVENGE_BASE + max(0, -min relation with any alive other faction)`
   (no other alive faction -> the extra term is 0).
3. **Recruit weapon bias.** `scripts/world/kingdoms.gd::recruit_weapon` draws
   a weighted random weapon id: `[dagger 1+aggr, sword 1, spear 1+coh, axe
   1+aggr, shield 1+coh]`, drawn through the caller's `rng` (deterministic).
4. **Plinko bias.** `scripts/world/kingdoms.gd::plinko_bias` = `(greed - 0.5)
   * PLINKO_BIAS_GREED`, refreshed into `World.plinko_bias[f]` every
   `scripts/world/kingdoms.gd::tick`; see [Plinko, towns and borders](03-plinko-towns.md)
   for how it steers the board.
5. **Relations.** `World.relations` is a symmetric `MAX_FACTIONS_WORLD^2`
   grid, clamped `-1..1` via `World.add_relation`. `scripts/world/kingdoms.gd::tick`
   decays every relation toward 0 by `REL_DECAY*dt` each world tick, and
   between two alive, bordering factions that both have diplomacy `> 0.6`
   grows their relation by `REL_DIPLOMACY_RATE*dt`. Border adjacency is a
   cached `PackedByteArray` (`World.border_adj`), rebuilt by
   `scripts/world/kingdoms.gd::_rebuild_border_adj` only when
   `World.borders_version` has changed since the cache was built.
   `scripts/world/kingdoms.gd::on_battle_finished` drops every losing
   faction's relation with the winner by `REL_BATTLE_LOST`, and (once the
   bridge records a `captain_killers` pair) drops the victim's relation with
   the killer's faction by `REL_CAPTAIN_KILLED`.
6. **Alliance.** `World.allied(a, b)` is just `relation(a, b) >= REL_ALLY_THRESHOLD`.
7. **Split.** `scripts/world/kingdoms.gd::check_split`, once per faction per
   30 s (`split_cooldown`): an alive faction with more than `SPLIT_UNITS`
   alive units and cohesion `< SPLIT_COHESION` (and room under
   `MAX_FACTIONS_WORLD`) spins its single largest stack off into a brand-new
   faction (`scripts/world/kingdoms.gd::new_faction`: next faction slot,
   `faction_color = g % 8`, `NameGen.kingdom_name`, ktraits copied from the
   parent with cohesion reset to `KTRAIT_INIT`, fresh plinko profile). Any
   town the old faction owns within 6 tiles (Chebyshev) of the split stack
   flips to the new faction; `add_relation(old, new, -0.6)`; the split
   stack and every other still-alive stack of the old faction get
   `immunity = RETREAT_IMMUNITY`; an event line is logged and
   `World.recompute_borders` runs.
8. **Death.** `scripts/world/kingdoms.gd::check_death`: an alive faction
   with zero towns and zero alive stacks flips `faction_alive = 0` and logs
   `"Kingdom <name> fell"` (never re-logged, since the flag flip guards it).
9. `scripts/world/kingdoms.gd::tick` also counts down `World.split_cooldown`
   toward 0 every world tick.

### Allies joining battles
Per ARCHITECTURE.md §13.5, `scripts/world/battle_bridge.gd::join` puts a
newly-joining stack on the same local side as an already-joined faction it
is `World.allied` with (same edge, same side), instead of assigning it a
fresh edge. `scripts/world/battle_bridge.gd::finish` then treats every stack
on the winning local side as a winner (`IDLE`) and every stack on the other
sides as a loser (`result["winner_side"]` records which local side won).
The bridge itself is out of this slice's source files — full mechanics in
[Overworld](02-overworld.md).

### Dissent and allegiance (observe only)

Heroes, captains, lords and towns hold values on the same 5 axes (aggression,
diplomacy, greed, piety, cohesion) as their faction's kingdom traits. Each has
a loyalty (bond) to their own kingdom (0..1 fraction for living members; towns
have no bond). Three readings are computed from these values:

- **Unit disaffection** (`scripts/world/dissent.gd::unit_disaffection`):
  distance between a unit's values and its kingdom's, reduced by the unit's bond.
  Negative values mean the unit is more loyal than its values would suggest.
- **Town disaffection** (`scripts/world/dissent.gd::town_disaffection`):
  distance between a town's values and its owner kingdom's; 0.0 if unowned.
- **Faction tension** (`scripts/world/dissent.gd::tension`):
  population-weighted average of positive disaffection across a faction's
  members and towns. High tension means substantial disagreement exists;
  low tension means the realm is aligned.

Nothing in the simulation currently acts on these readings — they are observe-only.

**Drives and grievance.** Each hero and captain has a grievance meter per drive
(Glory, Wealth, Faith, Land), driven by their unit value on the corresponding
axis (aggression, greed, piety, cohesion). Grievance rises over time when a
drive has no outlet (no recent deeds of that type); it drains when a deed is
performed (battle win, raid, raze, pilgrimage, settlement). Towns accumulate
grievance from raids, razes, levies and taxes, and calm down slowly in peace
when owned and intact. A unit's overall grievance is a strength-weighted
average of its four per-drive grievances. Grievance raises disaffection
(adding to distance) and erodes bond over time. Like disaffection, grievance
is a reading only: no outcome depends on its values.

`tools/stall_probe.gd` prints the values `top_griev top_glory top_wealth top_faith top_land top_town_griev top_tension top_members top_bond
top_town_dis max_tension max_tension_f` for debugging and tuning.

Units are seeded when created (captain promotion, lineage succession) from
their kingdom's values plus small randomness. Towns are seeded from their lord's
values at settlement. During each world tick, members' bond drifts toward 1.0
(service accumulation), and towns' values drift toward their lord's values and
their owner kingdom's values. Deeds (battles, raids, razes, pilgrimages) shift
values based on the kind of event and scaled by `HERO_EVENT_SCALE`. Bond also
adjusts: winning battles increase bond, retreating decreases it.

The implementation uses no draws from `w.rng` — noise is deterministic, seeded
from `w.rng.state` (or 0 if null) and unit identity via a local `RandomNumberGenerator`.

The Dissent constants (`VALUE_SEED_SPREAD`, `BOND_*`, `TOWN_*_PULL`, `*_POWER`,
`HERO_EVENT_SCALE`) are tuned knobs you can adjust to change how quickly values
drift, how much bond matters, and how much political weight different roles carry.

`scripts/world/namegen.gd` builds every generated name from three syllable
tables (`ONSETS`, `CODAS`, plus `KINGDOM_SUFFIXES` or `LEGEND_ADJECTIVES`),
always drawn through the caller's `RandomNumberGenerator` (deterministic):
`stack_name` = onset+onset+coda; `captain_name_base` = onset+coda (
`Lineage.make_captain` appends `" I"`, so `captain_name` — onset+coda+" I" —
is unused by the current call sites, which go through `make_captain`
instead); `kingdom_name` = onset+onset+suffix; `legend_name(rng, kills)` =
`"<adjective> <onset+coda>, killer of <kills>"`.

## Knobs

| Constant | Value | Raise it and... |
|---|---|---|
| `TRAIT_THRESHOLD` | `3` | A behaviour counter needs more (or fewer) occurrences before it can set/replace a captain's trait. |
| `HEIR_RANK_DROP` | `1` | A succeeding heir starts at a lower rank relative to the fallen captain. |
| `LEGEND_RANK` | `3` | A soldier needs a higher rank before `check_legend` gives them a generated legend name. |
| `KTRAIT_INIT` | `0.5` | Every new kingdom trait (and a split-off faction's cohesion) starts higher/lower — shifts all goal weights, recruit bias and plinko bias at faction creation. |
| `KT_WIN_AGGR` | `0.02` | Winning a battle raises aggression faster. |
| `KT_RAZE_GREED` | `0.05` | Razing a town raises greed faster. |
| `KT_RAZE_PIETY` | `-0.03` | Razing a town drops piety faster (more negative). |
| `KT_SETTLE_COH` | `0.03` | Settling raises cohesion faster. |
| `KT_RETREAT_AGGR` | `-0.02` | Retreating drops aggression faster. |
| `KT_RETREAT_COH` | `-0.02` | Retreating drops cohesion faster. |
| `KT_PILGRIM_PIETY` | `0.05` | Completing a pilgrimage raises piety faster. |
| `PLINKO_BIAS_GREED` | `200.0` | A greedy kingdom's plinko drops get pushed toward gold-heavy slots harder. |
| `GOAL_PILGRIMAGE_BASE` | `0.5` | Stacks pick the PILGRIMAGE goal more often even at zero piety. |
| `GOAL_AVENGE_BASE` | `0.5` | Stacks pick the AVENGE goal more often even with no grudge. |
| `REL_CAPTAIN_KILLED` | `-0.5` | A captain's death drops the victim's relation with the killer's faction further. |
| `REL_BATTLE_LOST` | `-0.1` | Losing a battle drops relation with the winner further. |
| `REL_ALLY_THRESHOLD` | `0.5` | Two factions need a higher relation before `World.allied` (and battle-join-side-sharing) treats them as allies. |
| `REL_DIPLOMACY_RATE` | `0.01` | Bordering high-diplomacy factions warm toward each other faster per second. |
| `REL_DECAY` | `0.002` | All relations drift back toward 0 faster per second. |
| `SPLIT_UNITS` | `600` | A faction needs more alive units before it is eligible to split. |
| `SPLIT_COHESION` | `0.3` | A faction needs even lower cohesion before it is eligible to split. |
| `MAX_FACTIONS_WORLD` | `16` | More faction slots exist in total (`ktraits`/`relations`/`border_adj` size, and the cap `check_split` respects). |
| `RETREAT_IMMUNITY` | `10.0` | The stacks involved in a split get a longer no-forced-retreat grace period (seconds). |
| `PLINKO_SLOTS` | `9` | `Kingdoms.new_faction` builds a longer shuffled slot order for a freshly split faction; see [Plinko, towns and borders](03-plinko-towns.md) for the board itself. |

## Tweak recipes

- **Want captains to earn traits faster/slower?** Change `TRAIT_THRESHOLD`
  (current `3`) toward a lower/higher count. Watch how quickly
  `w.units.ctrait` stops being `-1` for active captains. Re-run:
  `bash tools/verify.sh test_lineage`.
- **Want heirs to keep more of the fallen captain's strength?** Change
  `HEIR_RANK_DROP` (current `1`) toward `0`. Watch the heir's `rank` right
  after succession. Pinned by `test_lineage` (`case2 rank[B] == 1` assumes
  `HEIR_RANK_DROP == 1`) — update the test too. Re-run:
  `bash tools/verify.sh test_lineage`.
- **Want kingdoms to lock into an identity faster (aggressive, greedy,
  etc.)?** Raise the `KT_*` deltas (current `0.02`-`0.05`). Watch
  `w.ktrait(f, k)` after a handful of wins/razes/settles/retreats/pilgrimages.
  Pinned by `test_kingdoms` (`on_event` cases assert exact post-event
  values) — update the test too. Re-run: `bash tools/verify.sh test_kingdoms`.
- **Want grudges/alliances to last longer?** Lower `REL_DECAY` (current
  `0.002`) toward `0`. Watch `w.relation(a, b)` over world time in the
  ledger/spectate panel. Pinned by `test_kingdoms` (`tick: relation(0,1)
  approx -0.58 after decay`) — update the test too. Re-run:
  `bash tools/verify.sh test_kingdoms`.
- **Want civil wars (splits) to happen sooner?** Lower `SPLIT_UNITS` (current
  `600`) or raise `SPLIT_COHESION` (current `0.3`). Watch `faction_count` and
  the events log for "splits from" lines. Pinned by `test_kingdoms` and
  `test_m5_hookup` (both assert `faction_count` increases under specific
  unit counts/cohesion) — update both tests too. Re-run:
  `bash tools/verify.sh test_kingdoms` and `bash tools/verify.sh test_m5_hookup`.
- **Want more factions possible at once (bigger worlds)?** Raise
  `MAX_FACTIONS_WORLD` (current `16`). Watch memory (`ktraits`/`relations`/
  `border_adj` all scale with it) and `test_m5_fields`
  (`blank world: ktraits.size() == 80` assumes `16*5`) — update that test
  too. Re-run: `bash tools/verify.sh test_m5_fields`.

## Gotchas

- All randomness here goes through a caller-supplied `RandomNumberGenerator`
  (`w.rng` in practice) — `NameGen`, `Kingdoms.recruit_weapon`, and the
  shuffle inside `Kingdoms.new_faction` never call the global RNG, so seeded
  tests and seeded worlds stay deterministic.
  `trait` is a reserved word in GDScript 4: the Units field is `ctrait`
  and `Kingdoms.trait_favor`'s parameter is named `tr` (see CLAUDE.md).
- `Kingdoms.update_trait` is a "sticky max" rule, not a live recompute: a
  captain's trait can lag behind their current highest counter if an
  earlier trait's counter was never itself beaten (a tie never changes it).
- `Kingdoms.on_battle_finished`'s `captain_killers` read
  (`inst.get("captain_killers")`) is defensive against the field not
  existing on `BattleInstance` — it is a real field populated by
  `scripts/world/battle_bridge.gd` (owned by [Overworld](02-overworld.md)), so this is not
  dead code in the running game, only in a hand-built `BattleInstance` that
  omits it.
- `Kingdoms.check_split`'s "which stacks get immunity" reading is literal,
  not proven by name in ARCHITECTURE.md: the split stack plus every other
  still-alive stack of the *old* faction all get `RETREAT_IMMUNITY`
  (`scripts/world/kingdoms.gd::check_split`).
  Open question: ARCHITECTURE.md §13.4 says "both stacks get immunity" without
  naming which second stack when the old faction has more than one
  remaining stack; the code (and this doc) applies it to every remaining
  stack of the old faction, which may not be the intended single "other"
  stack.
- Rebirth and mercenary handling (`scripts/world/battle_bridge.gd::_process_rebirth`) is
  the other half of "kingdoms formation" — it creates factions via the same
  `Kingdoms.new_faction` this file owns, but the decision logic (legend
  survivor -> found; otherwise -> mercenary) lives outside this slice's
  source files; see [Overworld](02-overworld.md).
- Doc drift: ARCHITECTURE.md §13.4's `on_battle_finished` relation write-up
  doesn't mention that `Kingdoms.on_battle_finished` is explicitly called
  out in the code as "not covered by a numbered test in this slice" and
  implemented best-effort — treat its relation-on-loss behaviour as less
  hardened than `Lineage.on_battle_finished`'s.
