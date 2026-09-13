# Plinko rewards, towns and borders

## What it does
After a battle finishes, each surviving winner stack with a living captain drops a marble on
its faction's plinko board; the slots the marble crosses turn into world effects (heal, recruit,
capture a town, raze it, promote units, drill, boost the captain, replace a dead captain, or
desert some troops). Towns grow population, recruit soldiers into nearby stacks, recover from
raids/razes over time, and can be captured outright by an idle stack sitting on them. Every tile's
border colour is whichever owned town is Chebyshev-nearest to it, recomputed whenever ownership
changes.

## Where it lives
| File | Role |
|---|---|
| `scripts/world/plinko.gd` | Board layout (pegs, slot order) and the headless physics drop that returns which slots the ball crossed. |
| `scripts/world/plinko_outcomes.gd` | Applies one slot's effect to the world (towns, units, stacks, lineage/kingdom hooks) and returns a log line. |
| `scripts/world/town_sim.gd` | Per-tick town growth, recruitment into stacks, raid/raze recovery, and occupation capture. |
| `scripts/world/world.gd` | Owns the town arrays (`towns`, `town_owner`, `town_state`, `town_pop`, `town_recruit`, `town_timer`) and `recompute_borders`, the border-ownership pass. |

## How it works

### When plinko triggers and who drops
1. `scripts/world/world_sim.gd::step_battles` calls `scripts/world/battle_bridge.gd::finish` when
   a battle has a winner, then `scripts/world/world_sim.gd::_run_plinko` for that instance.
2. `_run_plinko` loops `inst.stack_ids`; a stack drops only if it is `alive`, its
   `Stacks.State` is `IDLE` (set by `finish` for winners) and its `captain_unit` is alive — a dead
   or missing captain means no drop for that stack.
3. For each qualifying stack: `Plinko.build(w.plinko_rows[f], w.plinko_bias[f], w.rng)` builds a
   fresh board, then `board.slot_order` is replaced by
   `scripts/world/kingdoms.gd::trait_favor(w.plinko_order[f], captain's ctrait)` (the captain's
   trait swaps its favoured slot to index 4), then `board.drop(PLINKO_W * 0.5, w.rng)` runs the
   physics.
4. Every returned slot is applied in crossing order via `PlinkoOutcomes.apply`; the stack id, the
   slots array, the log lines, the path and the board are appended to `w.plinko_log` (capped at 50
   entries, oldest dropped).

### Board layout and slot/outcome table
`Plinko.build(rows, bias, rng)` (`scripts/world/plinko.gd::build`) lays out `rows` rows of pegs in
a `PLINKO_W` × `PLINKO_H` box: row `r` sits at `y = 60.0 + r * ((PLINKO_H - 120.0) / rows)`; even
rows get `PLINKO_SLOTS` pegs at `x = sw/2 + k*sw` (`sw = PLINKO_W / PLINKO_SLOTS`), odd rows get
`PLINKO_SLOTS - 1` pegs at `x = sw + k*sw` (staggered). `slot_order` starts as the identity
permutation `0..PLINKO_SLOTS-1` and is Fisher-Yates shuffled with `rng`.

`Plinko.drop(x0, rng)` (`scripts/world/plinko.gd::drop`) starts the ball at
`(x0 + rng.randf_range(-2.0, 2.0), PLINKO_BALL_R)` with zero velocity. Each `PLINKO_DT` step:
`v.y += PLINKO_GRAVITY * dt`, `v.x += bias * dt`, `p += v * dt`; hitting a side wall clamps `p.x`
and reflects `v.x` scaled by `-PLINKO_RESTITUTION`; hitting a peg (`distance < peg_r + ball_r`)
pushes the ball out along the contact normal, reflects the normal velocity component scaled by
`(1 + PLINKO_RESTITUTION)`, and jitters `v.x` by `rng.randf_range(-15.0, 15.0)`. Once
`p.y >= PLINKO_H - PLINKO_SLOT_BAND`, the slot column under the ball (`slot_order[clamp(x/sw)]`) is
appended to `slots` if not already present and `slots.size() < PLINKO_MAX_OUTCOMES`. The drop ends
when `p.y >= PLINKO_H - PLINKO_BALL_R`, or at `PLINKO_MAX_STEPS` (forcing one slot in if `slots` is
still empty). `path` records `p` every 4 steps for rendering.

`Plinko.Slot` (also mirrored, not re-declared, in `scripts/world/plinko_outcomes.gd`):

| Slot | Value | Effect (`scripts/world/plinko_outcomes.gd`) |
|---|---|---|
| `SETTLE` | 0 | `_settle`: claims the nearest non-own town (neutral preferred) within `RAID_RANGE`, sets it INTACT and owned by the stack's faction; heals every alive unit of the stack to `hp_frac = 1.0`; recomputes borders if a town was found. |
| `RECRUIT` | 1 | `_recruit`: `n = RECRUIT_N[stack tier]`; if an own INTACT town is within `TOWN_RECRUIT_RANGE`, `n = min(n, floor(town_pop))` and that much is drained from `town_pop`; otherwise (wilds) `n = n / 2`. Adds up to `n` rank-0 units (random weapon via `Kingdoms.recruit_weapon`) to the stack, stopping at `STACK_CAP`. |
| `RAID` | 2 | `_raid`: nearest enemy town within `RAID_RANGE` → state RAIDED, `owner = -1`, `pop *= 0.5`, `town_timer = RAID_RECOVER`; every alive unit of the stack gets `xp += 5`; recomputes borders. |
| `RAZE` | 3 | `_raze`: nearest enemy town within `RAID_RANGE` → state RAZED, `owner = -1`, `pop = 0.0`, `town_timer = RAZE_RECOVER`, map tile kind → `RUIN`; recomputes borders. |
| `FORGE` | 4 | `_forge`: the `FORGE_N` lowest-rank alive units of the stack (ties broken by unit id) get `rank = min(3, rank + 1)`. |
| `DRILL` | 5 | `_drill`: every alive unit of the stack gets `drill = min(3, drill + 1)`. |
| `HERO_TRIAL` | 6 | `_hero_trial`: the stack's captain (if alive) gets `xp += HERO_XP`, `rank = min(3, rank + 1)`. |
| `HEIR` | 7 | `_heir`: if the captain slot is empty or dead, the alive unit with the most kills (first found on ties) becomes captain via `Lineage.make_captain`; a living captain means no change. |
| `CURSE` | 8 | `_curse`: kills `ceil(CURSE_FRAC * count)` non-captain units, lowest-xp first (ties by unit id). |

### How an outcome is applied to the world
`PlinkoOutcomes.apply(w, stack, slot)` (`scripts/world/plinko_outcomes.gd::apply`) matches on
`slot` and dispatches to the private `_settle`/`_recruit`/... helpers above, each returning a
one-line `String` such as `"<stack name>: RAID took <town id>"` for the plinko log. `SETTLE` and
`RAZE` also call `scripts/world/kingdoms.gd::on_event` (ktrait bumps) and
`scripts/world/lineage.gd::note_settle` / `note_raze` unconditionally, even if no town was in
range (see Gotchas). Town-owner changes call `w.recompute_borders()` inline, so borders are always
current by the time the next slot in the same drop is applied.

### Towns: ownership, capture, production/recruitment, growth
`World.add_town(tile, owner)` (`scripts/world/world.gd::add_town`) appends one entry to each town
array (`town_pop = TOWN_POP_START`, `town_recruit = 0.0`, `town_timer = 0.0`, `town_state = 0`
INTACT) and sets the map tile kind to `TOWN`.

`TownSim.step(w, dt)` (`scripts/world/town_sim.gd::step`), run once per world tick, per town:
1. **INTACT**: `town_pop = min(TOWN_POP_MAX, town_pop + TOWN_POP_GROWTH * dt)`; if owned
   (`town_owner != -1`), also runs `_recruit`.
2. **RAIDED**: `town_timer -= dt`; at `<= 0.0` the state flips back to INTACT (owner stays `-1`).
3. **RAZED**: `town_timer -= dt`; at `<= 0.0` the state flips to INTACT, `town_pop = TOWN_POP_START / 2.0`,
   `town_owner = -1`, the map tile kind reverts to `TOWN`, and borders are recomputed.
4. `_capture` then runs for every town (see below).

`_recruit(w, town_id, dt)` (`scripts/world/town_sim.gd::_recruit`) accumulates
`town_recruit += TOWN_RECRUIT_RATE * dt`; while `town_recruit >= 1.0` and `town_pop >= 1.0`, it
spends one of each and adds one rank-0 unit (weapon via `Kingdoms.recruit_weapon`) to a target
stack: the nearest alive own stack within `TOWN_RECRUIT_RANGE` (Chebyshev tiles) that is not in
`Stacks.State.BATTLE` and has `count < STACK_CAP`
(`scripts/world/town_sim.gd::_recruit_target`); if none qualifies, a new garrison stack is spawned
on the town tile with `Stacks.Goal.DEFEND` and the unit is added to it.

Occupation capture (`scripts/world/town_sim.gd::_capture`, called every tick): for each neutral
(`town_owner == -1`) INTACT town, find an alive stack that is `Stacks.State.IDLE`, has
`idle_timer <= 0.0`, and stands on that town's tile (first match by stack index wins ties); while
such a stack is present, `town_timer += dt`; once `town_timer >= CAPTURE_TIME` the town's owner
becomes that stack's faction, `town_timer` resets to 0, and borders are recomputed. RAIDED/RAZED
towns reuse `town_timer` for recovery instead, so occupation capture only ever applies to neutral
INTACT towns.

### Borders: territory and when it updates
`World.recompute_borders()` (`scripts/world/world.gd::recompute_borders`) rebuilds `map.owner` for
every tile: impassable tiles get `owner = -1`; every passable tile gets the owner of whichever
owned town (`town_owner >= 0`) is Chebyshev-nearest, provided that distance is `<= BORDER_RANGE`
(ties keep the first, lowest-id, town found), else `-1`. It also bumps `borders_version` by 1 so
renderers know to redraw. It is called once at the end of `World.create`, and inline by every
ownership-changing event: plinko `SETTLE`/`RAID`/`RAZE`, `TownSim`'s RAZED-recovery and occupation
capture, and (outside this slice's files) `Kingdoms.check_split`.

## Knobs
| Constant | Value | Raise it and... |
|---|---|---|
| `PLINKO_W` | `360.0` | Widens the board; slot columns (`PLINKO_W / PLINKO_SLOTS`) get wider, so a given bias pushes the ball across fewer slot boundaries. |
| `PLINKO_H` | `480.0` | Taller board; more vertical room for pegs before the slot band, longer drops. |
| `PLINKO_SLOTS` | `9` | More/fewer slot columns; `Plinko.Slot` still has 9 named values, so this must stay 9 or the enum and slot table drift apart. |
| `PLINKO_PEG_R` | `6.0` | Bigger pegs collide with the ball sooner and more often, adding more random `v.x` jitter per drop. |
| `PLINKO_BALL_R` | `8.0` | Bigger ball collides with walls/pegs sooner; drop ends slightly higher (`p.y >= PLINKO_H - PLINKO_BALL_R`). |
| `PLINKO_GRAVITY` | `600.0` | Faster fall, fewer steps per drop, less time for bias/jitter to spread the ball sideways. |
| `PLINKO_RESTITUTION` | `0.6` | Bouncier wall/peg collisions; the ball loses less velocity per bounce and travels further sideways. |
| `PLINKO_DT` | `1.0 / 120.0` | Coarser physics step; changes exact trajectories (breaks the seeded determinism test at other values) without changing overall drop time much. |
| `PLINKO_MAX_STEPS` | `2400` | Longer cap before a drop is forced to end; only matters for a ball that never settles into the slot band. |
| `PLINKO_SLOT_BAND` | `40.0` | Taller band at the bottom where slot crossings are recorded; the ball can cross more (or fewer) columns before landing. |
| `PLINKO_MAX_OUTCOMES` | `3` | More distinct slots can be triggered by one drop, so more outcomes get applied per winner stack. |
| `RECRUIT_N` | `[10, 20, 30, 40]` | Bigger base recruit counts per stack tier (index = tier 0..3); `RECRUIT` outcome adds more units per hit. |
| `STACK_CAP` | `300` | Raises the unit cap a stack can grow to via `RECRUIT` and town recruitment. |
| `RAID_RANGE` | `10` | Widens the Chebyshev-tile search radius for `SETTLE`/`RAID`/`RAZE` targets, so stacks can hit towns further away. |
| `FORGE_N` | `10` | More of the stack's lowest-rank units get promoted per `FORGE` outcome. |
| `HERO_XP` | `50` | More XP granted to the captain per `HERO_TRIAL` outcome. |
| `CURSE_FRAC` | `0.10` | A larger fraction of the stack (rounded up) deserts/dies per `CURSE` outcome. |
| `TOWN_POP_START` | `50.0` | Higher starting/half-recovery population for newly added and RAZED-recovered towns. |
| `TOWN_POP_MAX` | `200.0` | Raises the population growth cap for INTACT towns. |
| `TOWN_POP_GROWTH` | `0.05` | Faster population growth per second for INTACT towns. |
| `TOWN_RECRUIT_RATE` | `0.10` | Owned INTACT towns push out recruits faster (units per second). |
| `TOWN_RECRUIT_RANGE` | `8` | Widens the Chebyshev-tile radius a town's recruits (and `RECRUIT` outcome) will search for a target stack. |
| `RAID_RECOVER` | `300.0` | Longer time (seconds) a RAIDED town stays RAIDED before reverting to INTACT. |
| `RAZE_RECOVER` | `900.0` | Longer time (seconds) a RAZED town stays a ruin before reverting to INTACT. |
| `BORDER_RANGE` | `10` | Widens how far (Chebyshev tiles) a town's ownership colour reaches; tiles beyond every owned town's range stay neutral. |

## Tweak recipes
- **Want plinko drops to swing outcomes further sideways?** Change `PLINKO_BIAS_GREED` (read by
  `scripts/world/kingdoms.gd`, not this slice's files) or, more directly, raise `PLINKO_RESTITUTION`
  (current `0.6`) toward `1.0`. Watch the last-entry animation in `PlinkoView`. Re-run:
  `bash tools/verify.sh test_plinko` — cases 5/6 assert bias and spread thresholds, so extreme
  values can flip them.
- **Want towns to snowball faster once captured?** Raise `TOWN_RECRUIT_RATE` (current `0.10`)
  toward `0.25`. Watch stack `count` climb near owned towns. Re-run:
  `bash tools/verify.sh test_town_sim` — pinned by `test_town_sim` (case 2 asserts exact recruit
  counts after 10 seconds).
- **Want raids/razes to hurt less?** Lower `RAID_RECOVER` (current `300.0`) and `RAZE_RECOVER`
  (current `900.0`). Watch how long a RAIDED/RAZED town stays out of production. Re-run:
  `bash tools/verify.sh test_outcomes` — pinned by `test_outcomes` (cases 3a/4 check the exact
  timer values) and `bash tools/verify.sh test_town_sim` (cases 6/7 check recovery timing).
- **Want captured territory to reach further?** Raise `BORDER_RANGE` (current `10`). Watch the map
  overlay colours extend past town clusters. Re-run: `bash tools/verify.sh test_town_sim` (case 7
  checks `borders_version` increments) — no test in this slice pins the exact radius value.
- **Want it easier/harder to occupy a neutral town?** `CAPTURE_TIME` (current `3.0`) is a local
  const in `scripts/world/town_sim.gd`, not a `Tuning` constant. Change it there. Watch case 8 of
  `bash tools/verify.sh test_town_sim`, which occupies for exactly 3 seconds.

## Gotchas
- `CAPTURE_TIME` is hardcoded in `scripts/world/town_sim.gd`: `CAPTURE_TIME = 3.0` — seconds an
  IDLE stack must stand on a neutral INTACT town before it flips ownership. It is not a `Tuning`
  constant, so it will not show up in `docs/systems/06-tuning-reference.md`.
  `scripts/world/plinko.gd::drop` also hardcodes jitter magnitudes inline: peg bounces add
  `rng.randf_range(-15.0, 15.0)` to `v.x`, and the start position offsets `x0` by
  `rng.randf_range(-2.0, 2.0)`.
- Every random draw in these files goes through `w.rng` (plinko board build/drop, weapon rolls via
  `Kingdoms.recruit_weapon`), matching the project-wide determinism rule — seeded tests
  (`test_plinko` case 4) depend on this.
- `_settle` and `_raze` in `scripts/world/plinko_outcomes.gd` call `Kingdoms.on_event` and
  `Lineage.note_settle`/`note_raze` unconditionally, even when no target town was found in range
  (heal-only SETTLE, no-op RAZE) — see the `// UNDECIDED` comments in that file; both are treated
  as always firing here.
- Slot values on `Plinko.Slot` and `PlinkoOutcomes.Slot` are two separate enum declarations kept in
  sync by hand (`plinko_outcomes.gd` comments this as mirroring `Plinko.Slot`); changing one
  without the other silently breaks the slot table above.
- `DRILL` only sets `Units.drill` (capped at 3) here; the actual battle payoff
  (`DRILL_SPIN_BONUS` per level added to `spin_cap`) is applied outside this slice's files, in
  `scripts/world/battle_bridge.gd::join`.
- `RECRUIT` and `TownSim._recruit` both call `scripts/world/kingdoms.gd::recruit_weapon`, coupling
  weapon choice to a faction's `aggr`/`coh` ktraits (04-meta scope) — a faction with more
  aggression/cohesion skews its new recruits' weapons even off the plinko board.
- Doc drift: `docs/GDD.md` §3 describes `Forge` as "upgrade weapon of N units (sword →
  greatsword etc)" and `Raid`/`Raze` as spawning a "loot pile" / hitting "enemy morale"; the code's
  `FORGE` promotes unit rank instead of weapon, and `RAID`/`RAZE` have no loot or morale mechanic.
- Doc drift: `docs/ARCHITECTURE.md` §12.3 describes `HEIR` as also setting
  `names[u] = NameGen.captain_name(w.rng)`; the code instead calls
  `scripts/world/lineage.gd::make_captain`, which derives the new captain's name from the dead
  captain's dynasty (or a fresh `NameGen.captain_name_base` draw) rather than `NameGen.captain_name`
  directly.

See also [Overworld and battle bridge](02-overworld.md) for stacks/battle finish, and
[Meta progression](04-meta-progression.md) for kingdoms/lineage/traits touched by these outcomes.
