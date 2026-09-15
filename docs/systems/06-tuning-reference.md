# Tuning reference

All 148 tuning constants live in `scripts/sim/tuning.gd`. They are `const`, so a
running game (or a running test) never sees a change made while it is executing —
you must restart Godot / rerun the test after editing. Several constants are pinned
by exact-value assertions in `scripts/tests/test_tuning.gd`; changing a pinned
constant without updating the matching assertion turns that test red.

## How to change a value safely

1. Edit the constant in `scripts/sim/tuning.gd`.
2. Grep `scripts/tests/` for `Tuning.NAME` to find every test that touches it (the
   `Pinned by test` column below already lists the ones that assert an exact value).
3. Run `bash tools/verify.sh <test_basename>` for the owning test (and any other test
   the grep turned up) until it is green.
4. If the constant affects a hot loop (forces, collision, spatial hash, world tick),
   also run `godot --headless --script res://scripts/bench_battle.gd` or
   `res://scripts/bench_world.gd` to check you have not regressed frame time.
5. Run `node tools/check_guide.mjs` to refresh this guide's values and catch drift.

## Battle: movement and forces

| Constant | Value | Read by | Pinned by test | What it does |
|---|---|---|---|---|
| `ENGAGE_RADIUS_MULT` | `12.0` | forces.gd, battle_sim.gd | - | Multiplier on marble radius defining the radius within which a marble looks for an enemy to engage. |
| `K_ATTR` | `40.0` | forces.gd | - | Force strength pulling a marble toward its engaged enemy or home direction, scaled by aggression and morale. |
| `K_COHESION` | `15.0` | forces.gd | - | Force strength pulling a marble toward its faction's centroid. |
| `K_SEPARATION` | `120.0` | forces.gd | - | Force strength pushing overlapping/near marbles apart. |
| `SEPARATION_RANGE_MULT` | `1.2` | forces.gd | - | Multiplier on the sum of two marbles' radii defining the separation force's range. |
| `BASE_RADIUS` | `8.0` | battle_state.gd, battle_sim.gd | - | Base marble radius before rank/captain multipliers, px. |
| `RADIUS_RANK_MULT` | `[1.0, 1.1, 1.2, 1.3]` | battle_state.gd | - | Per-rank radius multiplier; index = rank 0..3. |
| `CAPTAIN_RADIUS_MULT` | `1.6` | battle_state.gd | - | Extra radius multiplier applied to a marble that is a captain. |
| `MAX_SPEED` | `400.0` | battle_sim.gd | - | Hard cap on marble velocity magnitude, px/s. |
| `RESTITUTION` | `0.9` | collision.gd, battle_sim.gd | - | Bounce coefficient for marble-marble collisions and wall/obstacle bounces (0..1 fraction of speed kept). |
| `ARENA_W` | `1600.0` | battle_state.gd, battle_background.gd | test_tuning | Battle arena width, px. |
| `ARENA_H` | `900.0` | battle_state.gd, battle_background.gd | test_tuning | Battle arena height, px. |
| `ENGAGE_RETARGET_TICKS` | `15` | forces.gd | - | How often (every N ticks, staggered per marble) a marble re-evaluates its engage target. |
| `MAX_NEIGHBORS` | `64` | spatial_hash.gd | - | Capacity of the scratch buffer used when gathering nearby marbles from the spatial hash. |
| `HOME_DIR` | `[Vector2(-1,0), Vector2(1,0), Vector2(0,-1), Vector2(0,1)]` | forces.gd, battle_sim.gd, battle_bridge.gd | test_tuning | Retreat/home direction per faction slot; index = faction_id % 4. |
| `K_ADVANCE` | `20.0` | forces.gd | test_tuning | Force strength pulling a marble toward the nearest contested/frontline point when advancing. |
| `FORCE_SCALE` | `12.0` | battle_sim.gd | - | Multiplier converting accumulated force/acceleration into velocity change per tick. |

## Battle: spin, HP and damage

| Constant | Value | Read by | Pinned by test | What it does |
|---|---|---|---|---|
| `SPIN_START` | `100.0` | battle_state.gd | - | Spin (acts as HP) a marble starts a battle with. |
| `SPIN_CAP` | `[120.0, 150.0, 190.0, 250.0]` | weapons.gd, battle_state.gd, battle_lod.gd | test_tuning | Max spin per rank; index = rank 0..3. |
| `SPIN_DECAY` | `4.0` | battle_sim.gd, battle_lod.gd | - | Spin lost per second passively (scaled by dt each tick). |
| `SPIN_HIT_COST` | `6.0` | collision.gd | - | Spin lost by both marbles on a marble-marble collision. |
| `SPIN_TRANSFER` | `0.15` | collision.gd | - | Fraction of spin difference transferred between colliding marbles. |
| `HP_BASE` | `100.0` | weapons.gd, battle_state.gd, battle_lod.gd | - | Base max HP before rank multiplier. |
| `SPIN_REF` | `100.0` | weapons.gd, battle_lod.gd | - | Reference spin value damage/knockback scale against (spin / SPIN_REF). |
| `SPIN_TO_RAD` | `TAU / 60.0` | weapons.gd | test_tuning | Converts spin (rpm-like unit) to radians of weapon-angle rotation per tick. |
| `RPM_MIN` | `5.0` | weapons.gd, collision.gd, battle_sim.gd, battle_lod.gd | - | Floor spin never drops below. |

## Battle: weapons

| Constant | Value | Read by | Pinned by test | What it does |
|---|---|---|---|---|
| `CRIT_CHANCE` | `0.05` | weapons.gd | - | Probability (0..1 fraction) a hit rolls a critical. |
| `CRIT_MULT` | `2.0` | weapons.gd | - | Damage multiplier applied on a critical hit. |
| `FUMBLE_CHANCE` | `0.03` | weapons.gd | - | Probability (0..1 fraction) a hit rolls a fumble instead (rolled just above the crit-chance band). |
| `FUMBLE_SPIN_LOSS` | `20.0` | weapons.gd | - | Spin lost by the attacker on a fumble. |
| `WEAPON_NAMES` | `["dagger", "sword", "spear", "axe", "shield"]` | - | test_tuning | Unused. Display name per weapon id; index = weapon id 0..4. |
| `WEAPON_REACH` | `[0.8, 1.2, 2.0, 1.3, 0.9]` | battle_renderer.gd, weapons.gd | test_tuning | Weapon reach multiplier on attacker radius for hit range; index = weapon id 0..4. |
| `WEAPON_DMG` | `[4.0, 8.0, 8.0, 14.0, 2.0]` | weapons.gd, battle_lod.gd | test_tuning | Base weapon damage; index = weapon id 0..4. |
| `WEAPON_COOLDOWN` | `[0.15, 0.30, 0.45, 0.50, 0.30]` | weapons.gd, battle_lod.gd | test_tuning | Seconds between hits per weapon; index = weapon id 0..4. |
| `WEAPON_KB` | `[60.0, 120.0, 60.0, 220.0, 120.0]` | weapons.gd | test_tuning | Knockback strength per weapon; index = weapon id 0..4. |
| `WEAPON_HIT_R` | `[0.45, 0.5, 0.4, 0.55, 0.5]` | weapons.gd | test_tuning | Hit-radius multiplier on attacker radius per weapon; index = weapon id 0..4. |
| `SHIELD_DMG_MULT` | `0.5` | weapons.gd | - | Damage multiplier applied when the defender is facing the attacker with a shield. |
| `SHIELD_FACING_DOT` | `0.7071` | weapons.gd | - | Minimum facing dot-product for a shield block to count (~45 degrees). |
| `WEAPON_COUNT` | `5` | battle_state.gd | test_tuning | Number of weapon types; used to validate weapon ids and array sizes. |
| `KB_SPIN_RESIST_MIN` | `0.5` | weapons.gd | test_tuning | Minimum knockback resistance factor (from the defender's own spin) applied to incoming knockback. |
| `WEAPON_RECHECK` | `0.1` | weapons.gd | - | Seconds after a miss before a marble rechecks for a hit. |

## Battle: morale, ranks and captains

| Constant | Value | Read by | Pinned by test | What it does |
|---|---|---|---|---|
| `MORALE_START` | `0.8` | battle_state.gd | - | Morale (0..1 fraction) a marble starts a battle with. |
| `MORALE_HIT_ALLY_DEATH` | `-0.02` | weapons.gd, battle_lod.gd | - | Morale change applied to nearby allies when a marble dies. |
| `MORALE_HIT_CAPTAIN_DEAD` | `-0.4` | weapons.gd, battle_lod.gd | - | Additional morale change applied to nearby allies when the dead marble was a captain. |
| `RETREAT_THRESHOLD` | `0.25` | battle_sim.gd, battle_lod.gd | - | Morale fraction below which a marble switches to retreating. |
| `RANK_MULT` | `[1.0, 1.25, 1.6, 2.2]` | weapons.gd, battle_state.gd, battle_lod.gd | test_tuning | Per-rank multiplier applied to damage, max HP and mass; index = rank 0..3. |
| `XP_PER_HIT` | `1` | weapons.gd | - | XP gained by the attacker on a landed hit. |
| `XP_PER_KILL` | `10` | weapons.gd, battle_lod.gd | - | XP gained by the attacker on a kill. |
| `RANK_XP` | `[0, 30, 120, 500]` | weapons.gd, battle_lod.gd | test_tuning | XP threshold required to reach each rank; index = rank 0..3. |
| `RETREAT_HP_FRAC` | `0.20` | battle_sim.gd, battle_lod.gd | - | HP fraction of max HP below which a marble switches to retreating. |
| `MAX_FACTIONS` | `16` | battle_state.gd, battle_sim.gd | - | Max factions tracked per battle (sizes faction centroid/captain arrays). |
| `CAPTAIN_AURA_MULT` | `6.0` | battle_sim.gd | test_tuning | Multiplier on captain radius defining the morale-regen aura range. |
| `CAPTAIN_MORALE_REGEN` | `0.05` | battle_sim.gd | - | Morale regained per second for allies inside a captain's aura. |

## Terrain

| Constant | Value | Read by | Pinned by test | What it does |
|---|---|---|---|---|
| `FRICTION` | `0.92` | terrain_grid.gd, battle_sim.gd | - | Default ground friction multiplier applied to velocity per tick. |
| `FRICTION_MUD` | `0.80` | terrain_grid.gd | - | Friction multiplier on mud terrain (slows marbles more than default). |
| `FRICTION_COBBLE` | `0.98` | terrain_grid.gd | - | Friction multiplier on cobble terrain (less slowdown than default). |
| `FRICTION_ICE` | `0.99` | terrain_grid.gd | test_tuning | Friction multiplier on ice terrain (near-frictionless). |
| `FRICTION_WATER` | `0.70` | terrain_grid.gd | test_tuning | Friction multiplier on water terrain (heavy slowdown). |
| `TERRAIN_CELL` | `40.0` | bench_battle.gd, battle_scene.gd, battle_sim.gd, battle_bridge.gd | test_tuning | Side length of one terrain grid cell, px. |
| `OBSTACLE_RADIUS_FRAC` | `0.4` | terrain_layer.gd, battle_sim.gd | test_tuning | Fraction of a terrain cell's size used as an obstacle's collision radius. |
| `HAZARD_DPS` | `[0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 8.0, 15.0]` | battle_sim.gd | test_tuning | Damage per second by terrain type id; index = terrain type id. |
| `TOWER_SPIN_REGEN` | `10.0` | battle_sim.gd | - | Spin regained per second while standing on a tower tile. |
| `TOWER_HEAL` | `5.0` | battle_sim.gd | - | HP healed per second while standing on a tower tile. |

## Overworld and stacks

| Constant | Value | Read by | Pinned by test | What it does |
|---|---|---|---|---|
| `WORLD_COLS` | `96` | world.gd | test_tuning | World map width, tiles. |
| `WORLD_ROWS` | `54` | world.gd | - | World map height, tiles. |
| `TILE` | `32.0` | world_scene.gd, map_layer.gd, pathing.gd, world_map.gd, world_sim.gd | test_tuning | Overworld tile size, px. |
| `TILE_COST` | `[1.0, 1.6, 2.0, 0.0, 3.0, 1.0, 1.2, 0.8]` | world_map.gd | test_tuning | Movement cost per tile terrain type (0.0 = impassable); index = terrain type id. |
| `N_FACTIONS` | `6` | bench_world.gd, world_gen.gd, world.gd | - | Number of playable factions created at world start. |
| `TOWNS_PER_FACTION` | `1` | world_gen.gd | - | Starting owned towns per faction. |
| `NEUTRAL_TOWNS` | `18` | world_gen.gd | - | Number of unowned neutral towns placed at world start. |
| `TOWN_MIN_SPACING` | `6` | world_gen.gd | - | Minimum Chebyshev tile distance kept between placed towns. |
| `WORLDGEN_WFC` | `true` | world_gen.gd | - | Use the WFC generator (true) or the legacy noise-threshold generator (false). |
| `WFC_CELL` | `2` | world_gen.gd | - | Tiles per side of one coarse WFC cell; every biome region is at least this wide. |
| `WFC_MAX_ATTEMPTS` | `4` | world_gen.gd | - | WFC full restarts before the deterministic fallback fill. |
| `WFC_AFFINITY` | `2.0` | world_gen.gd | - | Weight multiplier per already-collapsed same-kind neighbour; higher = bigger clumps. |
| `RIVER_ELEV_COST` | `8.0` | world_gen.gd | - | Extra river flow cost per unit of positive elevation; higher = rivers hug valleys. |
| `RIVER_MIN_LENGTH` | `12` | world_gen.gd | - | Minimum step distance from a river source to the map border. |
| `RIVER_SOURCE_SPACING` | `4` | world_gen.gd | - | Minimum Chebyshev distance between river sources. |
| `TOWN_SCORE_RIVER` | `2.0` | world_gen.gd | - | Town suitability bonus when that terrain is within 2 tiles. |
| `TOWN_SCORE_FOREST` | `1.0` | world_gen.gd | - | Town suitability bonus when that terrain is within 2 tiles. |
| `TOWN_SCORE_HILLS` | `0.5` | world_gen.gd | - | Town suitability bonus when that terrain is within 2 tiles. |
| `TOWN_SCORE_MOUNTAIN` | `0.3` | world_gen.gd | - | Town suitability multiplier when a mountain is within 2 tiles. |
| `STACKS_PER_FACTION` | `3` | world.gd | - | Number of unit stacks created per faction at world start. |
| `STACK_UNITS_MIN` | `60` | world.gd | - | Minimum starting soldier count for a newly created stack. |
| `STACK_UNITS_MAX` | `120` | world.gd | - | Maximum starting soldier count for a newly created stack. |
| `STACK_CAP` | `300` | town_sim.gd, plinko_outcomes.gd, stacks.gd | test_tuning | Maximum soldier count a stack can hold. |
| `STACK_SPEED` | `48.0` | world_sim.gd | - | Base stack movement speed, tiles/s, before terrain cost. |
| `STACK_RADIUS` | `12.0` | world_scene.gd, world_sim.gd, stack_layer.gd | - | Stack collision/click radius, px. |
| `TIER_COUNTS` | `[30, 100, 250]` | stacks.gd | - | Soldier-count thresholds separating stack size tiers. |
| `TIER_NAMES` | `["Band", "Company", "Host", "Horde"]` | stacks.gd | test_tuning | Display name per stack tier; index = tier 0..3. |
| `AI_TICK` | `2.0` | world_sim.gd | - | Seconds between stack AI decision re-evaluations. |
| `GOAL_WEIGHTS` | `[3.0, 3.0, 2.0, 1.0, 1.0]` | - | test_tuning | Unused. Base weight per stack AI goal type; index = goal id. |
| `IDLE_AFTER_BATTLE` | `3.0` | battle_bridge.gd | - | Seconds a stack stays idle after finishing a battle before resuming AI. |
| `RETREAT_TILES` | `6` | battle_bridge.gd | - | Tiles a losing stack is pushed back toward home when retreating from a battle. |
| `RETREAT_SPEED_MULT` | `1.3` | world_sim.gd | - | Movement speed multiplier for a stack currently retreating. |
| `RETREAT_IMMUNITY` | `10.0` | world_sim.gd, kingdoms.gd, save_game.gd, battle_bridge.gd | - | Seconds a stack is immune to being re-engaged after retreating or splitting. |
| `REINFORCE_TILES` | `6` | world_sim.gd | - | Chebyshev tile range within which a stack can reinforce an ongoing battle. |
| `MAX_BATTLE_MARBLES` | `3000` | battle_bridge.gd | test_tuning | Hard cap on total marbles simulated in one battle instance. |
| `BATTLE_EXTRA_CAP` | `600` | battle_bridge.gd | - | Extra marble headroom above the two starting stacks' combined count, reserved for reinforcements. |
| `MAX_FACTIONS_WORLD` | `16` | world_sim.gd, kingdoms.gd, world.gd, save_game.gd | test_tuning | Max factions tracked at world scale (sizes relation/border/ktrait arrays). |

## Battle LOD

| Constant | Value | Read by | Pinned by test | What it does |
|---|---|---|---|---|
| `LOD_K` | `0.25` | battle_lod.gd | - | Scale-down factor applied to a faction's damage-per-second rate in the LOD (auto-resolve) model. |
| `LOD_XP_PER_DMG` | `0.125` | battle_lod.gd | - | XP granted per point of damage dealt in a LOD battle. |
| `LOD_FLEE_TIME` | `5.0` | battle_lod.gd | - | Seconds a routed marble's hit-cooldown timer must exceed before it counts as fled in a LOD battle. |

## Plinko

| Constant | Value | Read by | Pinned by test | What it does |
|---|---|---|---|---|
| `PLINKO_W` | `360.0` | plinko_view.gd, plinko.gd, world_sim.gd | - | Plinko board width, px. |
| `PLINKO_H` | `480.0` | plinko_view.gd, plinko.gd | - | Plinko board height, px. |
| `PLINKO_SLOTS` | `9` | plinko_view.gd, plinko.gd, kingdoms.gd, world.gd | test_tuning | Number of outcome slots at the bottom of the plinko board. |
| `PLINKO_ROWS_MIN` | `6` | - | - | Unused. Intended minimum peg-row count for a plinko board. |
| `PLINKO_ROWS_MAX` | `10` | - | - | Unused. Intended maximum peg-row count for a plinko board. |
| `PLINKO_PEG_R` | `6.0` | plinko.gd | - | Peg collision radius, px. |
| `PLINKO_BALL_R` | `8.0` | plinko_view.gd, plinko.gd | - | Ball collision radius, px. |
| `PLINKO_GRAVITY` | `600.0` | plinko.gd | - | Downward acceleration applied to the ball each plinko step, px/s^2. |
| `PLINKO_RESTITUTION` | `0.6` | plinko.gd | - | Bounce coefficient for ball-peg collisions. |
| `PLINKO_DT` | `1.0 / 120.0` | plinko.gd | - | Fixed timestep for the plinko physics simulation, seconds. |
| `PLINKO_MAX_STEPS` | `2400` | plinko.gd | - | Safety cap on physics steps per ball drop before forcing a stop. |
| `PLINKO_SLOT_BAND` | `40.0` | plinko_view.gd, plinko.gd | - | Height of the slot-detection band near the bottom of the board, px. |
| `PLINKO_MAX_OUTCOMES` | `3` | plinko.gd | - | Max distinct outcome slots recorded as hit during one ball drop. |
| `RECRUIT_N` | `[10, 20, 30, 40]` | plinko_outcomes.gd | test_tuning | Soldiers recruited per outcome tier; index = tier 0..3. |
| `FORGE_N` | `10` | plinko_outcomes.gd | - | Number of soldiers promoted/upgraded by a forge outcome. |
| `DRILL_SPIN_BONUS` | `20.0` | battle_bridge.gd | - | Spin cap bonus added per drill level when a battle instance is set up. |
| `HERO_XP` | `50` | plinko_outcomes.gd | - | XP granted to a captain by a hero outcome. |
| `CURSE_FRAC` | `0.10` | plinko_outcomes.gd | - | Fraction (0..1) of a stack's soldiers killed by a curse outcome. |
| `PLINKO_BIAS_GREED` | `200.0` | kingdoms.gd | test_tuning | Scale applied to a faction's greed trait to bias its plinko drop position. |

## Towns and borders

| Constant | Value | Read by | Pinned by test | What it does |
|---|---|---|---|---|
| `TOWN_POP_START` | `50.0` | town_sim.gd, world.gd | - | Starting population of a newly created/reset town. |
| `TOWN_POP_MAX` | `200.0` | town_sim.gd | - | Population cap a town's growth cannot exceed. |
| `TOWN_POP_GROWTH` | `0.05` | town_sim.gd | - | Population growth rate per second (fraction toward max). |
| `TOWN_RECRUIT_RATE` | `0.10` | town_sim.gd | - | Recruit-point accumulation rate per second for a town. |
| `TOWN_RECRUIT_RANGE` | `8` | town_sim.gd, plinko_outcomes.gd | - | Chebyshev tile range within which a stack can draw recruits from a town. |
| `RAID_RECOVER` | `300.0` | plinko_outcomes.gd | - | Seconds before a raided town can be raided/razed again. |
| `RAZE_RECOVER` | `900.0` | plinko_outcomes.gd | - | Seconds before a razed town can be raided/razed again. |
| `RAID_RANGE` | `10` | plinko_outcomes.gd | - | Chebyshev tile range within which a stack can raid/raze a town. |
| `BORDER_RANGE` | `10` | world.gd | test_tuning | Tile distance within which a tile's border ownership is attributed to the nearest town. |

## Lineage, traits and kingdoms

| Constant | Value | Read by | Pinned by test | What it does |
|---|---|---|---|---|
| `TRAIT_THRESHOLD` | `3` | lineage.gd | test_tuning | Number of qualifying events required before a trait is granted. |
| `HEIR_RANK_DROP` | `1` | lineage.gd | - | Ranks subtracted from the dead captain's rank when setting the heir's starting rank. |
| `LEGEND_RANK` | `3` | lineage.gd, battle_bridge.gd | test_tuning | Rank at which a soldier/captain is considered legendary (max rank). |
| `KTRAIT_INIT` | `0.5` | kingdoms.gd, world.gd | test_tuning | Starting value (0..1 fraction) for each kingdom trait. |
| `KT_WIN_AGGR` | `0.02` | kingdoms.gd | - | Aggression trait change applied to a faction on a battle win. |
| `KT_RAZE_GREED` | `0.05` | kingdoms.gd | - | Greed trait change applied to a faction on razing a town. |
| `KT_RAZE_PIETY` | `-0.03` | kingdoms.gd | - | Piety trait change applied to a faction on razing a town. |
| `KT_SETTLE_COH` | `0.03` | kingdoms.gd | - | Cohesion trait change applied to a faction on settling. |
| `KT_RETREAT_AGGR` | `-0.02` | kingdoms.gd | - | Aggression trait change applied to a faction on retreating from battle. |
| `KT_RETREAT_COH` | `-0.02` | kingdoms.gd | - | Cohesion trait change applied to a faction on retreating from battle. |
| `KT_PILGRIM_PIETY` | `0.05` | kingdoms.gd | - | Piety trait change applied to a faction on completing a pilgrimage. |
| `VALUE_SEED_SPREAD` | `0.15` | dissent.gd | - | Max +/- noise applied to a newly seeded unit or town value. |
| `HERO_EVENT_SCALE` | `2.0` | dissent.gd | - | Multiplier applied to kingdom event deltas when updating hero/captain values. |
| `TOWN_REALM_PULL` | `0.002` | dissent.gd | - | Per second, rate town values drift toward their owner kingdom's values. |
| `TOWN_LORD_PULL` | `0.004` | dissent.gd | - | Per second, rate town values drift toward their lord's values. |
| `BOND_INIT` | `0.5` | dissent.gd | - | Starting loyalty (0..1 fraction) when a hero/captain is seeded. |
| `BOND_SERVICE_RATE` | `0.001` | dissent.gd | - | Per second, rate active hero/captain bond drifts toward 1.0. |
| `BOND_WIN` | `0.02` | dissent.gd | - | Loyalty increase applied to hero/captain on a stack winning battle. |
| `BOND_LOSS` | `0.03` | dissent.gd | - | Loyalty decrease applied to hero/captain on a stack retreating from battle. |
| `BOND_WEIGHT` | `0.25` | dissent.gd | - | Multiplier applied to bond when computing disaffection; reduces disaffection by `BOND_WEIGHT * bond`. |
| `POWER_HERO` | `5.0` | dissent.gd | - | Political weight of a hero (not captain, not lord). |
| `POWER_LORD` | `10.0` | dissent.gd | - | Political weight of a lord. |
| `GOAL_PILGRIMAGE_BASE` | `0.5` | kingdoms.gd | - | Base weight of the pilgrimage AI goal before the piety trait is added. |
| `GOAL_AVENGE_BASE` | `0.5` | kingdoms.gd | - | Base weight of the avenge AI goal before the extra avenge-trait bonus is added. |
| `REL_CAPTAIN_KILLED` | `-0.5` | kingdoms.gd | - | Relation change applied against the killer's faction when a faction's captain is killed. |
| `REL_BATTLE_LOST` | `-0.1` | kingdoms.gd | - | Relation change applied toward the winner when a faction loses a battle. |
| `REL_ALLY_THRESHOLD` | `0.5` | world.gd | test_tuning | Relation value at or above which two factions are considered allies. |
| `REL_DIPLOMACY_RATE` | `0.01` | kingdoms.gd | - | Relation improvement per second between factions sharing a border. |
| `REL_DECAY` | `0.002` | kingdoms.gd | - | Rate relations drift back toward zero per second. |
| `SPLIT_UNITS` | `600` | kingdoms.gd | test_tuning | Total alive-unit threshold above which a faction can split into a new kingdom. |
| `SPLIT_COHESION` | `0.3` | kingdoms.gd | - | Cohesion trait threshold at/above which a faction is eligible to split. |

## Rally and contingents

| Constant | Value | Read by | Pinned by test | What it does |
|---|---|---|---|---|
| `RALLY_RANGE` | `8` | rally.gd | - | Max Chebyshev tile distance to a host army a stack will consider rallying to. |
| `RALLY_MIN_DESIRE` | `0.2` | rally.gd | - | Join desire below which a led stack gives the RALLY goal no weight. |
| `RALLY_GOAL_WEIGHT` | `6.0` | rally.gd | - | RALLY goal weight at desire 1.0 (scaled by desire) for a stack with a captain. |
| `RALLY_LEADERLESS_WEIGHT` | `50.0` | rally.gd | - | RALLY goal weight for a captainless stack with a host in range (near-certain pick). |
| `RALLY_WEAK_COUNT` | `30.0` | rally.gd | - | Unit count at/above which a stack no longer feels weak; the weakness term fades linearly to it. |
| `RALLY_THREAT_TILES` | `6` | rally.gd | - | Tile radius in which enemy (non-allied) men count as a threat. |
| `RALLY_THREAT_RATIO` | `3.0` | rally.gd | - | Enemy-to-own men ratio that makes the threat term full strength. |
| `RALLY_RENOWN_SCALE` | `20.0` | rally.gd | - | Renown gap (kills + 10 x rank) between host and joiner captains giving the full renown term. |
| `RALLY_GOLD_SCALE` | `60.0` | rally.gd | - | Gold at which the joiner's "can manage alone" term (and BUILDER host's gold appetite) is full. |
| `RALLY_W_WEAK` | `0.5` | rally.gd | - | Desire weight of having few men. |
| `RALLY_W_THREAT` | `0.4` | rally.gd | - | Desire weight of nearby enemy strength. |
| `RALLY_W_RENOWN` | `0.2` | rally.gd | - | Desire weight of the host captain's greater (or lesser, negative) renown. |
| `RALLY_W_COHESION` | `0.4` | rally.gd | - | Desire weight of kingdom cohesion above/below 0.5. |
| `RALLY_W_AMBITION` | `0.5` | rally.gd | - | Desire penalty per unit of the joiner captain's ambition. |
| `RALLY_W_AGGR` | `0.3` | rally.gd | - | Desire penalty for kingdom aggression above 0.5. |
| `RALLY_W_GOLD` | `0.2` | rally.gd | - | Desire penalty for gold in hand. |
| `RALLY_ACCEPT_BASE` | `0.5` | rally.gd | - | Host captain's base chance to accept a led joiner. |
| `RALLY_ACCEPT_TRAIT` | `0.3` | rally.gd | - | Acceptance bonus: full for TYRANT, scaled by free room for CAUTIOUS, by joiner gold for BUILDER. |
| `RALLY_ACCEPT_RIVAL` | `0.3` | rally.gd | - | Acceptance penalty when the joiner's captain out-renowns the host's. |
| `RALLY_COOLDOWN` | `60.0` | rally.gd | - | Seconds a refused stack waits before it may rally again. |
| `RALLY_PLEDGE_TIME` | `300.0` | rally.gd, heroes.gd | - | Seconds a captain who rallied in serves as a hero before they may break away with their contingent. |

## Presentation and time

| Constant | Value | Read by | Pinned by test | What it does |
|---|---|---|---|---|
| `FACTION_COLORS` | `[Color(0.85,0.2,0.2), Color(0.2,0.4,0.9), Color(0.2,0.7,0.3), Color(0.9,0.7,0.1), Color(0.6,0.3,0.8), Color(0.9,0.5,0.2), Color(0.2,0.8,0.8), Color(0.5,0.5,0.5)]` | battle_renderer.gd, ledger_panel.gd, map_layer.gd, stack_layer.gd, terrain_layer.gd, world.gd | test_tuning | Display color per faction slot; index = faction_id % 8. |
| `LEDGER_REFRESH` | `0.5` | ledger_panel.gd | - | Seconds between ledger panel content refreshes. |
| `SAVE_VERSION` | `1` | save_game.gd | test_tuning | Save file format version; loads are rejected if the file's version does not match. |
| `SPEED_STEPS` | `[1, 5, 50]` | - | test_tuning | Unused. Intended game-speed multiplier steps for time controls; index = speed step slot. |
| `MAX_FRAME_MS` | `12.0` | world_scene.gd | - | Max milliseconds per frame spent running extra "MAX speed" simulation steps before yielding. |
| `TIMELINE_LINES` | `12` | timeline_panel.gd | - | Number of most-recent log lines kept/shown in the timeline panel. |

## Other

| Constant | Value | Read by | Pinned by test | What it does |
|---|---|---|---|---|
| `DT` | `1.0 / 60.0` | world_scene.gd, bench_battle.gd, bench_world.gd, battle_scene.gd, world_sim.gd | test_tuning | Fixed simulation timestep in seconds for both battle and world ticks (60 Hz). |
| `T_MAX_BATTLE` | `120.0` | battle_sim.gd | test_tuning | Battle auto-ends (draw/timeout) once elapsed battle time reaches this many seconds. |
