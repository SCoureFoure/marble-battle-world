# Overworld and battle bridge

## What it does
This is the strategic layer above the marble battles: a tile grid the size of a
small continent, factions marching stacks of soldiers across it, and the glue
that turns a stack-on-stack collision into an arena battle (and copies the
result back out when the battle ends). It also carries the LOD (level-of-detail)
stand-in that keeps unwatched battles moving forward statistically instead of
running the full physics sim every tick.

## Where it lives
| File | Role |
|---|---|
| `scripts/world/world_map.gd` | Tile grid: kind/owner arrays, cost/passability, tile↔world conversions. |
| `scripts/world/world_gen.gd` | One-shot procedural map fill (elevation, forest, rivers, ruins, graveyards, towns). |
| `scripts/world/pathing.gd` | `AStarGrid2D` wrapper over `WorldMap`. |
| `scripts/world/units.gd` | Every soldier in the world, persistent, SoA. |
| `scripts/world/stacks.gd` | Marching stacks of units, SoA. |
| `scripts/world/world.gd` | The `World` data object: map, towns, units, stacks, pathing, live battles, faction bookkeeping. |
| `scripts/world/world_sim.gd` | The per-tick overworld update: AI, movement, collisions, reinforcement, battle stepping. |
| `scripts/world/battle_bridge.gd` | Starts/joins/finishes arena battles from overworld stacks. |
| `scripts/world/battle_instance.gd` | `BattleInstance`, the per-battle record `BattleBridge` and `WorldSim` fill in. |
| `scripts/world/battle_lod.gd` | Statistical stand-in for `BattleSim.step` on battles nobody is watching. |

## How it works

### Map generation
1. `WorldMap` is a flat `cols*rows` grid (`WORLD_COLS` × `WORLD_ROWS` tiles,
   `TILE` world units per tile). `kind` is a `WorldMap.Kind` byte per tile;
   `cost_at` looks up `Tuning.TILE_COST[kind]` (`0.0` = impassable) and
   `passable` is `cost_at > 0.0`.
2. `WorldGen.generate(m, town_count)` is the seam; `Tuning.WORLDGEN_WFC` picks WFC (default) or `_generate_noise` (legacy). The pipeline:
   - A. Prior: Simplex elevation (frequency 0.05) and forest noise (frequency 0.08) sampled once per coarse cell.
   - B. Biome WFC: tiled WFC on a `WFC_CELL` × `WFC_CELL` tile coarse grid, 4 states: PLAINS, FOREST, HILLS, MOUNTAIN, with adjacency rules:

   |  | PLAINS | FOREST | HILLS | MOUNTAIN |
   |---|---|---|---|---|
   | PLAINS | ✓ | ✓ | ✓ | ✗ |
   | FOREST | ✓ | ✓ | ✓ | ✗ |
   | HILLS | ✓ | ✓ | ✓ | ✓ |
   | MOUNTAIN | ✗ | ✗ | ✓ | ✓ |

   Invariant: every 4-neighbour of a MOUNTAIN tile is MOUNTAIN or HILLS.

   - C. Upscale: each coarse cell becomes a `WFC_CELL` × `WFC_CELL` tile block; adjacency rules hold on the tile grid.
   - D. Rivers: flow field (Dijkstra cost-to-border) plus steepest descent; `max(2, cols/32)` rivers, paths end at the border or another river, never enter a tile 4-adjacent to MOUNTAIN.
   - E. Cleanup: remove 1-wide HILLS and FOREST slivers that rivers cut, preserving the invariant (keep HILLS if 4-adjacent to MOUNTAIN).
   - F. Props: 6 RUIN + 6 GRAVEYARD on PLAINS.
   - G. Towns: suitability-weighted placement in the largest passable component, farthest-point reorder.
3. Rng draw order (every draw from `m.rng`):
   ```
   1. elevation noise seed m.rng.randi() (forest seed = elev_seed + 1, no draw)
   2. biome WFC one m.rng.randf() per observation, per attempt (variable count)
            + one m.rng.randi_range() per observation to pick a cell from the lowest-entropy bucket
   3. rivers one m.rng.randi_range() per river to pick its source
   4. ruins two m.rng.randi_range() per attempt (x, y)
   5. graveyards same as ruins
   6. towns one m.rng.randf() per placed town
   ```
4. Towns: scored weighted placement (Chebyshev radius 2), candidates exclude border tiles. Score per candidate:
   `score = 1.0 + 2.0 if RIVER within 2 + 1.0 if FOREST within 2 + 0.5 if HILLS within 2`, multiplied by `0.3 if MOUNTAIN within 2`, zero if MOUNTAIN within 1.
   Weighted draw (Chebyshev spacing ≥ `TOWN_MIN_SPACING` from placed towns); candidates reordered by farthest-point distance so the first entries (drawn later as capitals by `World.create`) are spread.
5. Faction starting positions: `World.create` (`scripts/world/world.gd::create`)
   assigns `towns[fi]` as faction `fi`'s capital (`owner = fi` for `fi <
   N_FACTIONS`), then places `STACKS_PER_FACTION` stacks on the capital tile
   and its passable neighbours (`scripts/world/world.gd::_passable_neighbours`),
   each with `rng.randi_range(STACK_UNITS_MIN, STACK_UNITS_MAX)` rank-0 units
   (random weapon) plus one rank-1 sword captain.

### Units vs stacks
- `Units` (`scripts/world/units.gd`) is every soldier ever created, persistent
  across battles: `faction`, `rank`, `xp`, `kills`, `weapon`, `stack` (stack id
  or `-1`), `hp_frac` (wounds persist between battles), `alive`, `is_captain`,
  plus M4/M5 fields (`drill`, `ctrait`, behaviour counters, `dynasty`, `names`).
  `scripts/world/units.gd::add` returns `-1` when the array is full;
  `scripts/world/units.gd::kill` sets `alive = 0` and `stack = -1`.
- `Stacks` (`scripts/world/stacks.gd`) is a marching group: position (`x/y`,
  `prev_x/prev_y` for the previous tick), `faction`, `count` (live member
  count, kept in sync by `scripts/world/stacks.gd::recount`), `state`
  (`Stacks.State`: IDLE/MOVING/BATTLE/RETREATING), `goal` (`Stacks.Goal`),
  `battle_id`, `captain_unit`, path (`path`/`path_i`), timers (`ai_timer`,
  `immunity`, `idle_timer`), `names`, `alive` (0 once `count` hits 0).
  `scripts/world/stacks.gd::tier` buckets `count` against `Tuning.TIER_COUNTS`;
  `scripts/world/stacks.gd::label` formats `"(tier)name count/STACK_CAP"`.

### Stack AI / movement decisions and pathing
1. An IDLE stack with both `idle_timer` and `ai_timer` spent gets a goal from
   `scripts/world/world_sim.gd::pick_goal`: weights come from
   `Kingdoms.goal_weights` ([Meta progression](04-meta-progression.md)) and a
   goal index is drawn with `w.rng`.
2. `scripts/world/world_sim.gd::set_goal` resolves the goal to a target tile
   and a path: `HUNT_WEAK` → nearest weaker enemy stack (else any enemy stack,
   via `World.nearest_enemy_stack`); `EXPAND`/`RAID`/`DEFEND` → nearest
   neutral/enemy/own town (`World.nearest_town`); `IDLE_HEAL` → no target;
   `PILGRIMAGE` → nearest RUIN/GRAVEYARD tile
   (`scripts/world/world_sim.gd::_nearest_holy_tile`); `AVENGE` → nearest stack
   of the most-hated faction (`scripts/world/world_sim.gd::_most_hated_faction`,
   `scripts/world/world_sim.gd::_nearest_stack_of_faction`). A path is fetched
   with `Pathing.find`; no reachable target → `false`, and
   `scripts/world/world_sim.gd::pick_goal` falls back to `IDLE_HEAL`/IDLE this
   tick (see Gotchas). `RALLY` → march to a bigger same-faction army and ask to
   join it (below).
2b. Rally and contingents (`scripts/world/rally.gd`). The RALLY weight comes
   from `scripts/world/rally.gd::goal_weight`: a captainless stack with a host
   in range almost always picks it; a led stack weighs its
   `scripts/world/rally.gd::desire` — few men, nearby enemies and a more
   renowned host captain pull toward joining, the captain's ambition, kingdom
   aggression and gold in hand pull against. On arrival
   `scripts/world/rally.gd::arrive` asks the host captain
   (`scripts/world/rally.gd::host_accepts`: TYRANT absorbs readily, CAUTIOUS
   wants numbers, BUILDER wants gold, a more renowned joiner is a rival).
   Accepted → `scripts/world/rally.gd::merge`: the joiner's men become a
   contingent (`Units.leader` = their captain), the captain serves on as a
   hero, pledged for `RALLY_PLEDGE_TIME`, after which a breakaway takes exactly
   that contingent. Refused → `RALLY_COOLDOWN`.
3. `Pathing` (`scripts/world/pathing.gd`) wraps `AStarGrid2D`: `region` is the
   map's tile rect, `cell_size = Vector2(TILE, TILE)`, diagonals only when no
   obstacle blocks the corner, weight scale = `cost_at`. `find` returns tile
   centres in world units, excluding the `from` tile (empty if unreachable or
   `from == to`); `refresh` re-applies the grid after `WorldMap.kind` changes.
4. `scripts/world/world_sim.gd::move_stacks`: a MOVING/RETREATING stack steps
   toward `path[path_i]` at `speed = STACK_SPEED / cost_at(current tile)`,
   multiplied by `RETREAT_SPEED_MULT` when retreating; within `2.0` world
   units of the waypoint it snaps there and advances `path_i`; running off the
   end of the path sets state IDLE (and fires `Kingdoms.on_event(w, "pilgrim",
   ...)` first if the goal was `PILGRIMAGE`). `prev_x/prev_y` are written
   **before** the move each tick.

### One world tick in order
`scripts/world/world_sim.gd::step` calls `step_world` then `step_battles`.

`scripts/world/world_sim.gd::step_world`:
1. `w.time += dt`; `ai_timer`, `immunity`, `idle_timer` count down per stack.
2. `TownSim.step(w, dt)` and `Kingdoms.tick(w, dt)` run (towns/relations —
   [Plinko, towns and borders](03-plinko-towns.md),
   [Meta progression](04-meta-progression.md)); every accumulated world second,
   `Kingdoms.check_split` and `Kingdoms.check_death` run once.
3. Every IDLE stack whose timers are spent picks a goal (`pick_goal`, above).
4. `move_stacks` advances positions.
5. `scripts/world/world_sim.gd::check_collisions` looks for new battles (next
   section).
6. `scripts/world/world_sim.gd::reinforce` pulls nearby friendly stacks into
   ongoing battles.
7. Any stack with `alive == 1`, `count == 0` and not in a BATTLE is retired
   (`alive = 0`).

`scripts/world/world_sim.gd::step_battles`: every live `BattleInstance` steps
once — `inst.sim.step` if it is `w.watched_battle`, else `BattleLod.step`
(see below); `CAPTAIN_DEAD` events are recorded into
`inst.captain_killers`; once `inst.sim.winner(inst.state) != -1`,
`BattleBridge.finish` runs and a plinko drop follows
(`scripts/world/world_sim.gd::_run_plinko` — [Plinko](03-plinko-towns.md)),
otherwise the battle stays in `w.battles`.

### When two stacks meet -> battle
`scripts/world/world_sim.gd::check_collisions` builds a `SpatialHash` (cell
64) over every alive, non-BATTLE stack and looks for pairs within
`2 * STACK_RADIUS` world units that are on different factions and neither
immune. If either stack's tile already has a live battle
(`scripts/world/world_sim.gd::_live_battle_at`), the newcomer(s) `join` it;
otherwise `BattleBridge.start` opens a new one (at most one new battle per
tile per tick, tracked in `started_tiles`).

`scripts/world/battle_bridge.gd::start`: the battle's tile is stack A's tile;
capacity is `min(MAX_BATTLE_MARBLES, count_a + count_b + BATTLE_EXTRA_CAP)`; a
fresh `BattleState` is seeded from `world.rng.randi()`; a `TerrainGrid` is
built and filled by `scripts/sim/terrain_gen.gd::from_tile` keyed on the
tile's `WorldMap.Kind` and the edges already in use (terrain types themselves
are [Battle](01-battle.md) territory); both stacks then `join`.

`scripts/world/battle_bridge.gd::join`: finds the local faction index (0..3)
for the stack's world faction — reusing an existing index if that world
faction is already mapped, or reusing an ally's index
(`world.allied`, [Meta progression](04-meta-progression.md) §Allies) — or else
picks a free edge with `scripts/world/battle_bridge.gd::edge_for`: the
dominant axis of `from - tile_center` (a tie on `|dx| == |dy|` favours the x
axis) picks the preferred edge, falling back to the opposite edge, then the
other axis's two edges, `-1` if all four are taken. Every live unit of the
stack is spawned at a random point inside `spawn_rect(edge)` with `hp =
hp_max * hp_frac`, `xp`/`kills` carried over, and `spin_cap += DRILL_SPIN_BONUS
* drill[u]`; the stack's state becomes BATTLE and `battle_id = inst.id`; `join`
returns `false` (no spawn) if the state's capacity would be exceeded.

### Battle instances running alongside the world
`World.battles` is a plain `Array` of live `BattleInstance`
(`scripts/world/battle_instance.gd`): `id`, `tile`, `state`/`sim`/`terrain`,
`faction_map` (local index → world faction), `unit_of` (marble → unit id),
`stack_ids`, `edge_of_faction`, `started` (world time), plus M5/M6
bookkeeping (`captain_before`, `captain_killers`, `side_factions`,
`lod_xp_acc`). Several battles can be running at once; each gets exactly one
step per world tick from `step_battles`. `scripts/world/world_sim.gd::reinforce`
keeps feeding a live battle: any IDLE/MOVING stack of an involved world
faction within `REINFORCE_TILES` (Chebyshev) gets routed to the battle tile
and `join`s on arrival (refused arrivals sit out IDLE with `RETREAT_IMMUNITY`).

### Battle LOD
Only the single `w.watched_battle` (if any) gets ticked by the full
`BattleSim.step` — every other live battle is advanced by
`scripts/world/battle_lod.gd::step`, a statistical stand-in that never moves a
marble's position:
1. Per local side, a damage rate is summed over its ENGAGE marbles:
   `rate[side] = LOD_K * Σ (spin[i]/SPIN_REF) * RANK_MULT[rank[i]] *
   WEAPON_DMG[weapon[i]] / WEAPON_COOLDOWN[weapon[i]]`.
2. Each side's `rate * dt` damage is split across enemy sides in proportion to
   their live counts, then applied in chunks of up to 8 damage
   (`scripts/world/battle_lod.gd::_apply_hit`) to uniformly random
   attacker/target pairs among that side's live marbles — mirroring
   `Weapons.tick`'s damage/xp/kill/rank-up steps (`HIT`/`KILL`/`LEVEL` events,
   morale hits to allies and extra on a captain kill, `CAPTAIN_DEAD` event).
3. Spin decays (`max(RPM_MIN, spin - SPIN_DECAY*dt)`); ENGAGE marbles drop to
   RETREAT when morale/hp cross `RETREAT_THRESHOLD`/`RETREAT_HP_FRAC`; a
   RETREAT marble reuses `hit_cd` as a flee timer and, once it reaches
   `LOD_FLEE_TIME`, is marked `fled = 1` and killed off (`FLED` event).
4. This is the "auto-resolve": there is no separate result computation — the
   LOD step just keeps `BattleState` converging toward one side's
   `faction_alive` hitting zero, so the same `sim.winner(state)` check used for
   a fully-simulated battle eventually fires, and `BattleBridge.finish` reads
   the outcome exactly as it would for a watched battle.

### Writing results back to units/stacks
`scripts/world/battle_bridge.gd::finish`:
1. Snapshots each stack's `captain_unit` into `inst.captain_before` (used
   later by `Lineage.on_battle_finished`).
2. For every marble: `Units.xp/kills/rank` are copied from `BattleState`,
   `Lineage.check_legend` runs; a marble that is `DEAD` and not `fled` calls
   `Units.kill`, otherwise `hp_frac = hp / hp_max` and it counts toward its
   home stack's survivor tally (fled survivors are tracked separately).
   `Stacks.recount` then resyncs every stack's `count`.
3. `winner_side = inst.sim.winner(state)` (`-1` none/stalemate); the winning
   world faction/stack is the joined stack on that side with the most
   survivors (`scripts/world/battle_bridge.gd::_side_of`).
4. Per joined stack: winners go IDLE with `idle_timer = IDLE_AFTER_BATTLE`;
   losers go RETREATING with `immunity = RETREAT_IMMUNITY` and a path to their
   nearest own town, or `scripts/world/battle_bridge.gd::_retreat_fallback_tile`
   (`RETREAT_TILES` steps back along `-HOME_DIR[edge]`, nudged to the nearest
   passable tile) when they have none; a stack left with `count == 0` is
   retired (`alive = 0`).
5. `[tile.x, tile.y, dead_count, world.time]` is appended to `world.scars`; a
   `"<winner> beat <loser> at (x,y)"` line is appended to `world.events_log`
   when there was a winner.
6. `scripts/world/battle_bridge.gd::_process_rebirth` runs last (mercenaries /
   new-faction rebirth for a destroyed faction's last stack — [Meta
   progression](04-meta-progression.md)), then `Lineage.on_battle_finished` and
   `Kingdoms.on_battle_finished` are called before `finish` returns
   `{"winner", "winner_side", "tile", "dead", "duration"}`.

## Knobs
| Constant | Value | Raise it and... |
|---|---|---|
| `WORLD_COLS` | `96` | Widens the map; more tiles to generate, path, and render. |
| `WORLD_ROWS` | `54` | Taller map, same effect as above. |
| `TILE` | `32.0` | Bigger tiles: fewer tiles cover the same world distance, coarser pathing and borders. |
| `TILE_COST` | `[1.0, 1.6, 2.0, 0.0, 3.0, 1.0, 1.2, 0.8]` | Index = `WorldMap.Kind`; raising an entry makes that terrain slower to cross (0.0 stays impassable). |
| `N_FACTIONS` | `6` | More starting kingdoms and capitals in `World.create`. |
| `TOWNS_PER_FACTION` | `1` | More capitals seeded per faction at world creation. |
| `NEUTRAL_TOWNS` | `18` | More unclaimed towns scattered across the map. |
| `TOWN_MIN_SPACING` | `6` | Forces towns further apart (Chebyshev tiles), sparser map. |
| `WORLDGEN_WFC` | `true` | Switch to true to use the WFC generator, false for legacy noise-threshold. |
| `WFC_CELL` | `2` | Larger coarse cells make biome regions wider. |
| `WFC_MAX_ATTEMPTS` | `4` | More restarts allow WFC to find a solution before deterministic fallback. |
| `WFC_AFFINITY` | `2.0` | Higher multiplier makes clumps of the same biome bigger. |
| `RIVER_ELEV_COST` | `8.0` | Higher cost makes rivers prefer valleys and avoid high ground. |
| `RIVER_MIN_LENGTH` | `12` | Minimum distance from a river source to the map border. |
| `RIVER_SOURCE_SPACING` | `4` | Minimum Chebyshev distance between river sources. |
| `TOWN_SCORE_RIVER` | `2.0` | Bonus per town for having a river nearby (radius 2). |
| `TOWN_SCORE_FOREST` | `1.0` | Bonus per town for having forest nearby (radius 2). |
| `TOWN_SCORE_HILLS` | `0.5` | Bonus per town for having hills nearby (radius 2). |
| `TOWN_SCORE_MOUNTAIN` | `0.3` | Multiplier on town score when a mountain is nearby (radius 2). |
| `STACKS_PER_FACTION` | `3` | More starting stacks per faction. |
| `STACK_UNITS_MIN` | `60` | Raises the floor on a starting stack's headcount. |
| `STACK_UNITS_MAX` | `120` | Raises the ceiling on a starting stack's headcount. |
| `STACK_CAP` | `300` | Raises the denominator shown in `Stacks.label` and the recruit cap elsewhere. |
| `TIER_COUNTS` | `[30, 100, 250]` | Thresholds a stack's `count` must clear to reach tier 1/2/3 — raising delays tier-ups. |
| `TIER_NAMES` | `["Band", "Company", "Host", "Horde"]` | Index = tier 0..3; display text only. |
| `AI_TICK` | `2.0` | Seconds between goal re-picks for an IDLE stack — raising slows AI reaction. |
| `IDLE_AFTER_BATTLE` | `3.0` | How long a battle winner stays put before it can pick a new goal. |
| `RETREAT_TILES` | `6` | How far a loser without an own town falls back along its home direction. |
| `RETREAT_SPEED_MULT` | `1.3` | Multiplies a retreating stack's speed. |
| `RETREAT_IMMUNITY` | `10.0` | Seconds a retreating/just-joined stack cannot start a new battle. |
| `STACK_SPEED` | `48.0` | World units/s on a cost-1.0 tile — raising speeds up all marches. |
| `STACK_RADIUS` | `12.0` | Collision circle radius; raising makes stacks collide (and trigger battles) from further apart. |
| `REINFORCE_TILES` | `6` | Chebyshev range within which idle/moving friendly stacks are pulled into an ongoing battle. |
| `MAX_BATTLE_MARBLES` | `3000` | Hard cap on a `BattleState`'s capacity, regardless of stack sizes. |
| `BATTLE_EXTRA_CAP` | `600` | Headroom above the two starting stacks' combined size, for reinforcements. |
| `TERRAIN_CELL` | `40.0` | Cell size (world units) of the arena's `TerrainGrid`. |
| `HOME_DIR` | `[Vector2(-1,0), Vector2(1,0), Vector2(0,-1), Vector2(0,1)]` | Index = local faction/edge 0..3; the direction a retreat falls back along. |
| `DRILL_SPIN_BONUS` | `20.0` | Spin cap added per `Units.drill` level when a unit joins a battle. |
| `LEGEND_RANK` | `3` | Rank threshold `_process_rebirth` checks to decide a founder qualifies for a new faction instead of mercenary status. |
| `MAX_FACTIONS_WORLD` | `16` | Ceiling on how many world factions can exist (relations/ktraits array sizing, splits stop here). |
| `KTRAIT_INIT` | `0.5` | Starting value for every kingdom trait. |
| `BORDER_RANGE` | `10` | Chebyshev tiles within which a tile is claimed by the nearest owned town. |
| `REL_ALLY_THRESHOLD` | `0.5` | Relation value at/above which `World.allied` treats two factions as allies (battle-joining, LOD share). |
| `PLINKO_SLOTS` | `9` | Size of each faction's plinko slot-order permutation seeded in `World`. |
| `PLINKO_W` | `360.0` | Board width; also the drop x used by `WorldSim._run_plinko` (`PLINKO_W * 0.5`). |
| `TOWN_POP_START` | `50.0` | Starting population written by `World.add_town`/`sync_town_arrays`. |
| `FACTION_COLORS` | `[Color(0.85,0.2,0.2), Color(0.2,0.4,0.9), Color(0.2,0.7,0.3), Color(0.9,0.7,0.1), Color(0.6,0.3,0.8), Color(0.9,0.5,0.2), Color(0.2,0.8,0.8), Color(0.5,0.5,0.5)]` | Index = `faction_color[f]` (`f % 8`); the swatch used for that faction. |
| `DT` | `1.0 / 60.0` | The fixed timestep `step_battles` uses for a full-sim tick. |
| `SPIN_REF` | `100.0` | Reference spin the LOD damage-rate formula divides by. |
| `RANK_MULT` | `[1.0, 1.25, 1.6, 2.2]` | Index = rank; scales LOD damage rate and hp/mass on rank-up. |
| `WEAPON_DMG` | `[4.0, 8.0, 8.0, 14.0, 2.0]` | Index = weapon id; per-hit damage feeding the LOD rate formula. |
| `WEAPON_COOLDOWN` | `[0.15, 0.30, 0.45, 0.50, 0.30]` | Index = weapon id; divides into the LOD rate formula (faster weapon → higher rate). |
| `LOD_K` | `0.25` | Overall scale on LOD damage rate — the "how much of a side's spin/gear converts to dps" knob. |
| `RPM_MIN` | `5.0` | Floor spin decay stops at under LOD. |
| `SPIN_DECAY` | `4.0` | Per-second spin loss applied to every live marble under LOD. |
| `RETREAT_THRESHOLD` | `0.25` | Morale floor below which an ENGAGE marble flips to RETREAT under LOD. |
| `RETREAT_HP_FRAC` | `0.20` | HP fraction floor with the same effect. |
| `LOD_FLEE_TIME` | `5.0` | Seconds a RETREAT marble waits (via `hit_cd`) before it's marked fled and removed. |
| `LOD_XP_PER_DMG` | `0.125` | XP credited to the attacker per point of LOD damage dealt. |
| `XP_PER_KILL` | `10` | XP credited on a LOD kill (same constant `Weapons` uses in the full sim). |
| `MORALE_HIT_ALLY_DEATH` | `-0.02` | Morale change to every living ally on a LOD kill. |
| `MORALE_HIT_CAPTAIN_DEAD` | `-0.4` | Extra morale change to allies when the LOD kill was the captain. |
| `RANK_XP` | `[0, 30, 120, 500]` | Index = rank; xp threshold for the next rank-up under LOD. |
| `SPIN_CAP` | `[120.0, 150.0, 190.0, 250.0]` | Index = rank; new spin cap on a LOD rank-up. |
| `HP_BASE` | `100.0` | Base hp `RANK_MULT` scales on a LOD rank-up. |

## Tweak recipes
- **Want battles to start from further away?** Raise `STACK_RADIUS` (current
  `12.0`). Watch stacks colliding sooner on the map view. Re-run:
  `bash tools/verify.sh test_world_sim`.
- **Want the world map bigger?** Raise `WORLD_COLS`/`WORLD_ROWS` (current
  `96`/`54`) — pinned by `test_tuning` (`Tuning.WORLD_COLS == 96`), update the
  test too. Watch generation time and town count (`N_FACTIONS *
  TOWNS_PER_FACTION + NEUTRAL_TOWNS` stays fixed, so density drops). Re-run:
  `bash tools/verify.sh test_world_map`.
- **Want unwatched battles to resolve faster?** Raise `LOD_K` (current
  `0.25`). Watch how quickly `faction_alive` hits zero in a headless run.
  Re-run: `bash tools/verify.sh test_battle_lod`.
- **Want reinforcements to reach a fight from further off?** Raise
  `REINFORCE_TILES` (current `6`). Watch stacks outside that Chebyshev range
  in `test_world_sim` case 7 start joining instead of sitting IDLE. Re-run:
  `bash tools/verify.sh test_world_sim`.
- **Want a losing stack to retreat further when it has no town?** Raise
  `RETREAT_TILES` (current `6`) — feeds `BattleBridge._retreat_fallback_tile`.
  Watch the goal tile picked in a finish with no owned town nearby. Re-run:
  `bash tools/verify.sh test_bridge`.
- **Want a stack's cap to cover bigger battles before hitting
  `MAX_BATTLE_MARBLES`?** Raise `BATTLE_EXTRA_CAP` (current `600`) — pinned
  indirectly by `test_tuning` (`Tuning.MAX_BATTLE_MARBLES == 3000`); watch
  `BattleBridge.join` no longer refusing reinforcements in a big fight.
  Re-run: `bash tools/verify.sh test_bridge`.

## Gotchas
- Every random draw on the overworld must go through `w.rng` (or
  `w.map.rng` during generation, or `inst.state.rng` inside a battle) —
  `test_world.gd`/`test_world_sim.gd` assert `World.create` and `WorldSim.step`
  are deterministic given a seed.
- `pick_goal`'s fallback when `set_goal` fails is `UNDECIDED` in the code
  itself (`scripts/world/world_sim.gd::pick_goal`): it always writes
  `st.goal[i] = Stacks.Goal.IDLE_HEAL` rather than the goal actually drawn —
  a deliberate, marked reading, not a settled spec.
- `_retreat_fallback_tile`'s "no own town, ring search finds nothing within
  radius 4" branch is also flagged `UNDECIDED` in
  `scripts/world/battle_bridge.gd` — no test in this slice exercises it.
- LOD (`scripts/world/battle_lod.gd::step`) intentionally skips captain-aura
  morale regen (the other half of `BattleSim` step 10) — only decay and
  retreat triggers are mirrored, per another in-code `UNDECIDED` note.
- `BattleBridge.join`'s allied-reuse path and `_process_rebirth`'s
  new-faction/mercenary split depend on `Kingdoms`/`Lineage`
  ([Meta progression](04-meta-progression.md)), which this file does not
  itself implement — read that guide for `allied`, `on_event`, `new_faction`,
  `check_legend`.
- `WorldSim.step_battles` chooses `BattleSim.step` vs `BattleLod.step` purely
  by `inst.id == w.watched_battle`; positions never move for any other live
  battle, so a spectate view switching targets will see other battles frozen
  in place until watched.
- Local faction index equals the home edge index (0 west, 1 east, 2 north,
  3 south) — `Tuning.HOME_DIR[edge]` is already oriented correctly, no extra
  lookup needed.
