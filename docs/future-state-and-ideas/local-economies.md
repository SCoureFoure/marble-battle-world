# Local economies — farms, caravans, treasury, reinvestment

Status: spec only (2026-09-15). Nothing built. Each step below is meant to
become its own ARCHITECTURE section when it is picked up, one step at a time.

Leader intent: local economies in the spirit of Mount & Blade (farms, traders
moving between towns) that feed the happiness of towns and of the lords and
heroes in charge of them; later, heroes and kingdoms reinvest into towns to
grow better economies.

Design rules carried over from the dissent work:

- Emergent, not forced. The economy adds pressures and outlets; no step is
  tuned to guarantee an outcome (no "big realms must starve").
- The economy does not get its own happiness meter. It feeds the existing
  readings: `town_griev`, `town_vals`, unit `griev` per drive, `bond`,
  `Dissent.tension`.
- SoA packed arrays on `World` / `Stacks` / `Units`. Every random draw goes
  through `w.rng`, in a documented order. Tick-rate logic runs once per world
  second unless it must be per tick.
- All numbers are fiat and tunable. Each step ends with a probe on seeds 1
  and 42 over 3600 s that reports what happened, not whether it hit a target.

## What exists today (baseline)

- `World.town_pop` grows flat at `TOWN_POP_GROWTH` while INTACT, capped at
  `TOWN_POP_MAX` (`TownSim.step`).
- `Economy.accrue`: `town_gold += TOWN_TAX_PER_POP * pop * dt`, capped at
  `TOWN_GOLD_MAX`.
- Recruiting (passive trickle and RESTOCK) spends pop and raises `town_griev`
  ("levy"); a stack collecting its own town's gold raises it too ("tax").
- Raid halves pop and takes the town's gold; raze zeroes pop.
- `Stacks.gold` per stack; loot, bounty, raid gold. The hero Wealth drive
  reads stack gold per man (`WEALTH_COMFORT`).
- No production, no goods, no kingdom treasury, nothing that travels between
  towns except armies. Lords (`fate == LORD`) have values but no drives in play.

## Defaults chosen for the open calls

These were posed as questions; the spec proceeds on these defaults. Any of
them can be vetoed before its step starts.

| Call | Default | Why |
|---|---|---|
| Farms: abstract or map sites? | Abstract: yield from the terrain around the town. Villages are an optional later step (E5). | No new map entity, render or raid target needed to get the loop running. |
| Caravans: real stacks or abstract flows? | Real `Stacks` entries with a `kind` flag. | Pathing, collision, battles, loot, LOD and slot recycling are reused unchanged; caravans can be ambushed and watched. |
| Goods | Two: food (E1) and wares (E2). No price table. | A commodity market is heavy to balance and invisible to a spectator. |
| Kingdom treasury | Yes, `World.faction_gold`, from E3. | Wages and kingdom-level reinvestment both need it. |

## Step order

1. **E1 — Food and prosperity** (town-only, small)
2. **E2 — Caravans** (medium to large)
3. **E3 — Treasury, lord's cut, wages** (medium)
4. **E4 — Reinvestment: town buildings** (medium)
5. **E5 — Villages** (optional, medium)

E1 is useful before dissent step 3b (coalition revolt): hunger and lost trade
are revolt fuel. E2 onward can come after 3b.

---

## E1 — Food and prosperity

A town feeds its people from the land around it. Growth needs a food surplus;
hunger shrinks the town and angers it. Prosperity summarises how well the
town is doing and scales its tax.

### Fields (`World`, appended by `add_town`, grown by `sync_town_arrays`, saved)

- `town_food: PackedFloat32Array` — food stock, 0..`FOOD_STORE_SECONDS * consumption`.
  Starts at `FOOD_START_DAYS * consumption`.
- `town_farm: PackedFloat32Array` — food yield per second from surrounding
  tiles (cached; recomputed on `borders_version` change and when a tile kind
  changes, e.g. raze to RUIN).
- `town_prosp: PackedFloat32Array` — prosperity 0..1, starts `PROSP_INIT`.

### Tuning (fiat)

```
FARM_RADIUS := 3                   # Chebyshev tiles around the town
FARM_YIELD := [0.05, 0.015, 0.025, 0.0, 0.0, 0.0, 0.0, 0.0]   # per tile per second, by WorldMap.Kind (PLAINS, FOREST, HILLS, ...)
FARM_RIVER_BONUS := 1.5            # yield mult for a tile 4-adjacent to RIVER
FOOD_PER_POP := 0.01               # consumption per pop per second
FOOD_STORE_SECONDS := 300.0        # max stock = this many seconds of consumption
FOOD_START_DAYS := 60.0            # seconds of consumption in stock at creation
STARVE_RATE := 0.05                # pop lost per second while stock is 0
TOWN_GRIEV_HUNGER := 0.002         # per second while stock is 0
PROSP_INIT := 0.5
PROSP_RATE := 0.002                # per second drift toward target
PROSP_TAX_MIN := 0.5               # tax mult = PROSP_TAX_MIN + prosp
RAID_FOOD_FRAC := 0.5              # raid takes this share of stock
RAID_PROSP_HIT := 0.3
```

### Rules (`TownSim`, once per world second, after raid/raze recovery)

- `town_farm[t]`: sum over tiles within `FARM_RADIUS` whose `map.owner` is
  the town's owner or -1 (land held by another realm does not feed this town)
  of `FARM_YIELD[kind]`, times `FARM_RIVER_BONUS` for river-adjacent tiles.
  Another town's tile counts once, for the nearer town (ties: lower id).
- INTACT towns: `use = pop * FOOD_PER_POP`;
  `town_food = clamp(town_food + farm - use, 0, FOOD_STORE_SECONDS * use)`.
- Growth replaces the flat rule: pop grows by `TOWN_POP_GROWTH` only while
  `town_food > 0` and yield covers use (`farm >= use`). A town that
  lives off its stock does not grow.
- Stock at 0: `pop -= STARVE_RATE`; `Dissent.on_town_event(w, "hunger", t)`
  adds `TOWN_GRIEV_HUNGER`.
- Prosperity target = mean of: food ratio `clamp(farm / max(use, eps), 0, 1)`,
  `1 - town_griev`, and `1.0` if not raided in the last `RAID_RECOVER`
  seconds else `0.0`. `town_prosp` drifts toward the target by `PROSP_RATE`.
- `Economy.accrue`: tax is multiplied by `PROSP_TAX_MIN + town_prosp`.
- RAID (`PlinkoOutcomes._raid`): `town_food *= 1 - RAID_FOOD_FRAC`,
  `town_prosp -= RAID_PROSP_HIT`. RAZE: food 0, prosp 0.
- RAIDED/RAZED towns neither eat nor grow (unchanged recovery timers).

### Links

- `Dissent.town_power` stays `town_pop`. A starving town loses power and
  gains grievance, so it weighs less but angrier in `tension`.
- No draws from `w.rng`.

### Consequences to watch (not targets)

- Towns on poor land (hills, forest) level off smaller; plains and river towns
  grow large. Recruiting from a food-capped town costs real growth.
- Border wars shrink farmland (`map.owner` flips), so a town can go hungry
  without being attacked directly.

### Tests / probe

- `scripts/tests/test_food.gd`: yield from a hand-built map; growth gated by
  surplus; starvation shrinks pop and raises grievance; raid hits stock and
  prosperity; tax scales with prosperity; save round-trip.
- Existing tests that assert pop or gold after N seconds (`test_town_sim`,
  `test_economy`) will shift and need their expectations re-derived.
- Probe: per-town food ratio, prosperity, pop; realm tension over time.

---

## E2 — Caravans

Prosperous towns send caravans carrying food and wares to towns that need
them. Deliveries enrich both ends and warm relations between realms. Caravans
are soft targets: poor armies and free companies prey on them, and war cuts
routes.

### Fields

- `Stacks.kind: PackedByteArray` — `enum Kind { ARMY = 0, CARAVAN = 1 }`,
  reset to ARMY by `add`.
- `Stacks.home_town, dest_town: PackedInt32Array` — -1 for armies.
- `Stacks.cargo_food, cargo_wares: PackedFloat32Array`.
- `World.town_wares: PackedFloat32Array` — wares stock per town.
- `World.town_caravan_timer: PackedFloat32Array`.
- `Stacks.Goal` appends `TRADE = 10`, `PREY = 11`.
- Save all of the above; older saves load with ARMY / -1 / 0.

### Tuning (fiat)

```
WARES_PER_POP := 0.002             # per second, times prosp
CARAVAN_INTERVAL := 120.0          # seconds between launches per town
CARAVAN_PROSP := 0.5               # min prosperity to launch
CARAVAN_COST := 20.0               # town_gold to outfit
CARAVAN_GUARDS := 8                # rank-0 units, taken from pop without levy grievance
CARAVAN_FOOD := 40.0               # max food per trip
CARAVAN_WARES := 20.0
CARAVAN_RANGE := 30                # tiles, destination search
CARAVAN_SPEED_MULT := 0.8
FOOD_VALUE := 0.5                  # gold per food on delivery
WARES_VALUE := 1.5
TRADE_PROSP := 0.05                # prosperity bump at each end per delivery
REL_TRADE := 0.03                  # relation bump per cross-realm delivery
PREY_WEIGHT := 2.0                 # goal weight for poor armies / free companies
PREY_RANGE := 10                   # tiles
```

### Rules

- Wares: INTACT owned towns `town_wares += WARES_PER_POP * pop * prosp`.
- Launch (`Caravans.tick`, once per world second): an owned INTACT town with
  `prosp >= CARAVAN_PROSP`, `town_gold >= CARAVAN_COST`, timer elapsed, no
  live caravan with `home_town == t`, and room in `Stacks`/`Units`.
  Destination = argmax over towns within `CARAVAN_RANGE` whose owner is own,
  allied or neutral (never an enemy, never `relation < 0`) of
  `need / (1 + path_tiles / 10)`, where `need` = that town's food deficit plus
  wares shortfall. No destination → no launch, no cost.
- Caravan stack: `kind = CARAVAN`, faction = town owner, guards drawn from
  pop, cargo = surplus food above one `FOOD_START_DAYS` reserve (cap
  `CARAVAN_FOOD`) and wares (cap `CARAVAN_WARES`), goal TRADE, pathed to the
  destination. Name from `NameGen` ("The <town> caravan" style).
- Arrival: cargo added to destination stocks; destination town pays
  `food * FOOD_VALUE + wares * WARES_VALUE` from its gold (what it can afford;
  the rest is a gift). Payment goes into the caravan's `gold`. Both towns
  `prosp += TRADE_PROSP`. Different owners → `add_relation(a, b, REL_TRADE)`.
  Then the caravan paths home.
- Home: `gold` goes to `town_gold[home]`, guards return to pop, stack retires.
- Route cut: if the destination turns enemy or is raided en route, turn home
  with the cargo. If `home_town` is lost, the caravan goes to the nearest own
  town and dissolves there.
- Battle: caravans collide and fight like any stack. A caravan never starts a
  battle with another caravan. A defeated caravan loses all cargo value to
  the loot pool (`cargo * VALUE` added to its gold before `Economy.loot`) and
  returns home if anyone survived.
- PREY goal: `Economy.goal_bonus` adds `PREY_WEIGHT` when the stack is poor
  (`gold < POOR_GOLD`) or its faction owns no towns; target = nearest
  non-own, non-allied caravan within `PREY_RANGE`. Robbed caravan's home town
  gets `on_town_event("raid_caravan")` (small grievance), and a Wealth deed
  for the robbers (`on_stack_event("raid")`).

### Exclusions (every system that walks stacks must skip `kind == CARAVAN`)

`WorldSim.pick_goal`, `Rally`, `Economy.wants_restock`/`restock`,
`TownSim._recruit_target`, reinforcement pull, `Heroes.check_breakaway`,
`Settling.check_aging`, `Kingdoms.check_split` largest stack, plinko drops
(caravans have no captain, so already skipped), `HUNT_WEAK`/`AVENGE` targets
(caravans are reached through PREY only). `SlotSweep` needs no change
(town ids are not slot references). Ledger stack counts exclude caravans.

### Rendering

`StackLayer`: cart glyph in faction colour for `kind == CARAVAN`; spectate
panel shows cargo, home and destination. Optional: faint trade-route lines
between towns with a delivery in the last N seconds.

### RNG

Launch and destination picks are deterministic (no draws). Guard weapons
use `Kingdoms.recruit_weapon(w, f, w.rng)`, one draw per guard, in town id
order then guard order.

### Tests / probe

- `scripts/tests/test_caravans.gd`: launch gating; destination never enemy;
  delivery pays and bumps prosperity and relations; route cut turns home;
  robbed caravan feeds loot; every exclusion above skips caravans.
- `bench_world.gd` gate (`WORLD_MS_AVG < 4`) must still pass.
- Probe: deliveries and robberies per realm, relations drift, stack slot use.

---

## E3 — Treasury, lord's cut, wages

Money flows up from towns to lords and the crown, and back down to armies as
wages. A broke realm stops paying, and unpaid heroes grow restless; a greedy
crown fills its treasury and angers its towns.

### Fields

- `World.faction_gold: PackedFloat32Array` (size `MAX_FACTIONS_WORLD`), reset
  by `Kingdoms.new_faction`; saved.
- Lords get drives in play: `Dissent.tick` extends the grievance loop to
  `fate == LORD` units (see Rules).

### Tuning (fiat)

```
TITHE_BASE := 0.3                  # share of accrued tax sent to the crown
TITHE_GREED := 0.4                 # tithe = TITHE_BASE + TITHE_GREED * (greed - 0.5)
TOWN_GRIEV_TITHE := 0.001          # per second, times tithe share above TITHE_BASE
WAGE_INTERVAL := 30.0
WAGE_PER_MAN := 0.05               # gold per unit per interval
LORD_WEALTH_COMFORT := 0.5         # town_gold per pop at or above which lord Wealth grievance drains
LORD_LAND_POP := 120.0             # fief pop at or above which lord Land grievance drains
```

### Rules

- Accrual split (`Economy.accrue`): of each town's tax, `tithe` share goes to
  `faction_gold[owner]`, the rest stays in `town_gold` (the fief's coffers,
  which the lord controls). A tithe above `TITHE_BASE` adds grievance.
- Wages (`Economy.pay_wages`, every `WAGE_INTERVAL`): each kingdom pays its
  ARMY stacks `WAGE_PER_MAN * count`, stacks in ascending id; if the treasury
  runs short, every stack is paid pro rata. Wages land in `Stacks.gold`, which
  the Wealth drive already reads, so no new hero rule is needed: an unpaid
  army drifts under `WEALTH_COMFORT` and its heroes' Wealth grievance rises.
- Free companies (no towns) have no treasury and no wages; they live on loot,
  raids and PREY, as now.
- Lord drives (in `Dissent.tick`): Wealth drains while fief
  `town_gold / pop >= LORD_WEALTH_COMFORT`, else rises; Land drains while fief
  pop `>= LORD_LAND_POP`, else rises; Glory and Faith rise as for heroes (a lord
  who wants glory is restless at home). Hunger in the fief (E1) raises the
  lord's Land grievance.
- The own-town RESTOCK path that empties `town_gold` into a stack stays, but
  now draws from the lord's coffers. It raises the fief's "tax" grievance, as
  today, and the lord's Wealth grievance by the amount taken.

### Tests / probe

- `scripts/tests/test_treasury.gd`: tithe split by greed; wages pro rata when
  short; unpaid stack's heroes gain Wealth grievance; lord drives rise and
  drain from fief state; save round-trip.
- Probe: treasury over time per realm, share of stacks under comfort, lord
  disaffection, tension.

---

## E4 — Reinvestment: town buildings

Lords and kingdoms spend gold on buildings. What gets built depends on who is
spending and what they value, and investing in a town buys its loyalty.

### Fields

- `World.town_bld: PackedByteArray` (size towns * 4, index `t*4+b`, level
  0..3). `enum Building { FARMS = 0, MARKET = 1, WALLS = 2, TEMPLE = 3 }`.
  Saved.

### Tuning (fiat)

```
INVEST_INTERVAL := 60.0
BLD_COST := [60.0, 150.0, 350.0]   # gold to reach level 1, 2, 3
FARMS_YIELD_MULT := 0.25           # +25% town_farm per level
MARKET_TAX_MULT := 0.2             # +20% tax per level; also +1 concurrent caravan per level (E2)
WALLS_RAID_RESIST := 0.25          # per level: raid outcome downgraded to "no effect" with this chance
TEMPLE_CALM := 0.0005              # extra town_griev drain per second per level
LORD_HOARD := 0.6                  # skip chance = LORD_HOARD * greed
INVEST_CALM := 0.1                 # town_griev drop on completion
INVEST_VALUE_PULL := 0.05          # town_vals pulled toward the investor's values on completion
```

### Rules (`Economy.invest`, every `INVEST_INTERVAL`, towns ascending)

- Fief with an alive lord: spender = the lord, purse = `town_gold`. One draw
  `w.rng.randf() < LORD_HOARD * greed` → hoard, skip this interval.
  Otherwise pick the building with the highest weight whose next level is
  affordable:
  - FARMS: `1 - food ratio` (hungry towns build farms), plus `vals` cohesion.
  - MARKET: lord greed.
  - WALLS: lord aggression plus a recent raid flag.
  - TEMPLE: lord piety plus `town_griev`.
- Town without a lord: spender = the kingdom, purse = `faction_gold`. Once per
  interval per kingdom, the crown funds the one town with the highest
  `town_griev + (1 - prosp)`, weights from `ktraits` the same way. Cohesion and
  diplomacy scale how often the crown spends at all.
- Completion: level up, pay, `town_griev -= INVEST_CALM`, `town_vals` pulled
  toward the spender's values (lord `vals` or kingdom `ktraits`). This is the
  intended link: a crown that invests in a disaffected town pulls it back into
  line; a lord who invests pulls the town toward the lord's own values, which may be away
  from the crown.
- Effects: FARMS multiplies `town_farm`; MARKET multiplies tax and caravan
  capacity; WALLS gives the raid-resist roll (one draw in `_raid`, before the
  target changes) and makes a TOWN arena's tower heal stronger; TEMPLE drains
  grievance and makes the town a PILGRIMAGE destination.
- Loss: RAID drops the highest level of MARKET or FARMS by one (MARKET first
  on ties); RAZE clears all four.
- Heroes settling (`Settling.found_town`) seed their new town's first building
  from their top drive: Wealth → MARKET, Land → FARMS, Glory → WALLS,
  Faith → TEMPLE.

### Rendering

Town info window lists building levels; map town glyph gains a small mark per
building at level ≥ 1 (optional).

### Tests / probe

- `scripts/tests/test_invest.gd`: lord pick follows values; hoarding draw;
  crown funds the most disaffected town; completion calms and pulls values;
  raid and raze downgrade; effects apply to yield, tax, raids, grievance.
- Probe: building mix per realm vs ktraits; tension in invested vs neglected
  towns.

---

## E5 — Villages (optional)

Farm hamlets as their own map sites attached to a parent town, like Mount &
Blade villages. They give armies a raid target short of the town.

- `World.villages` arrays: tile, parent town, state (INTACT / RAIDED), food
  yield. Village tiles are placed by `WorldGen` near towns on PLAINS/RIVER
  after town placement (rng draws appended at the end of the draw order).
- A village's yield replaces part of `town_farm`: tiles inside a village's
  radius count only through the village.
- New goal option for RAID: nearest enemy village. A raided village yields
  nothing for `RAID_RECOVER / 2` and adds grievance to the parent town.
- Rendering: a small hut glyph in the owner's colour.

Only worth building if E1–E4 show that wars rarely touch the economy except
by taking whole towns.

---

## Open questions (flag before the step starts)

- E1: should an army camped on a town eat the town's food (siege pressure),
  or do armies stay outside the food economy?
- E2: should free companies ever run caravans (hired escorts) — or does that
  wait for mercenary contracts (roadmap A2)?
- E3: who is "the crown"? The kingdom's ruler is not modelled yet
  (succession is per kingdom, see the dissent design). The treasury is
  owned by the faction until a ruler exists.
- E4: can a lord spend on a town they do not hold (e.g. their old home), or
  only on their fief?
