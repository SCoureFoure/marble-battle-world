# Battle simulation

## What it does
Simulates one battle: a fixed-capacity pool of "marbles" (soldiers) that seek
enemies, collide, spin their weapons and hit each other, gain morale-driven
fear and routing, level up mid-fight, and eventually leave one faction (or
none) standing. Everything is data-oriented — no per-marble nodes, only
packed arrays on `BattleState` mutated in place by pure-function systems each
tick. Terrain (friction, obstacles, hazards, towers) is optional and, when
present, feeds into the same tick.

## Where it lives
| File | Role |
|---|---|
| `scripts/sim/battle_state.gd` | Per-marble/per-faction packed-array storage, spawning |
| `scripts/sim/spatial_hash.gd` | Counting-sort grid used for neighbour queries |
| `scripts/sim/collision.gd` | Marble-marble overlap resolution and spin transfer |
| `scripts/sim/forces.gd` | Retargeting and force accumulation (attraction, cohesion, separation, advance, retreat) |
| `scripts/sim/battle_sim.gd` | Orchestrates one tick, integration, terrain effects, transitions, winner check |
| `scripts/sim/weapons.gd` | Weapon swings, hit tests, damage, knockback, crits/fumbles, rank-ups |
| `scripts/sim/terrain_grid.gd` | Arena cell grid: kind, friction, slope, obstacles, tower ownership |
| `scripts/sim/terrain_gen.gd` | Deterministic terrain layouts (demo arena and per-world-tile arenas) |

## How it works

### Marble data layout
`BattleState` (`scripts/sim/battle_state.gd`) holds everything as parallel
`Packed*Array`s sized to `cap` at construction (`scripts/sim/battle_state.gd::_init`);
slot `i` across every array is one marble. No marble is ever removed — dead
or fled marbles just sit in their slot with `state[i] == DEAD`.

Per-marble floats: `px, py` (position), `vx, vy` (velocity), `ax, ay` (force
accumulator, rezeroed every tick), `radius, mass`, `hp, hp_max`, `spin,
spin_cap`, `weapon_angle` (radians), `hit_cd` (seconds until next swing),
`morale`, `aggression`.

Per-marble ints/bytes: `weapon_id, faction_id, rank, state` (`BattleState.State`:
`ENGAGE=0, RETREAT=1, DEAD=2`), `captain_id`, `kills, xp`, `target_id` (current
attraction target, `-1` none), `is_captain`, `fled` (1 once a `RETREAT` marble
reaches its home edge).

Per-faction (indexed by `faction_id`, arrays sized `Tuning.MAX_FACTIONS`):
`faction_alive` (live count, recomputed by `BattleSim` every tick),
`faction_cx, faction_cy` (centroid of live marbles), `faction_captain`
(marble index or `-1`).

`s.events` is a per-tick `Array` of `[type, actor, target]` triples
(`BattleState.Event`: `HIT=0, KILL=1, LEVEL=2, CAPTAIN_DEAD=3, FLED=4`);
`scripts/sim/battle_sim.gd::step` clears it at the start of every tick, systems
append to it, and a caller (scene/bench) reads it after `step` returns.

`scripts/sim/battle_state.gd::spawn` writes one marble into slot `n` and
returns its index (`-1` and a `push_error` if `n >= cap`, faction/rank/weapon
out of range). It derives `radius = BASE_RADIUS * RADIUS_RANK_MULT[rank] *
(CAPTAIN_RADIUS_MULT if captain else 1)`, `mass = radius^2 * RANK_MULT[rank]`,
`hp = hp_max = HP_BASE * RANK_MULT[rank]`, `spin = SPIN_START`, `spin_cap =
SPIN_CAP[rank]`, a random `weapon_angle`, `morale = MORALE_START`,
`aggression = 1.0`, `state = ENGAGE`. `scripts/sim/battle_state.gd::spawn_block`
spawns `count` rank-0 marbles at uniform-random points in a `Rect2`
(`weapon == -1` draws each one's weapon via `s.rng`).
`scripts/sim/battle_state.gd::alive_count` counts `state != DEAD`;
`scripts/sim/battle_state.gd::survivors_count` counts a faction's marbles with
`state != DEAD or fled == 1` (fled marbles count as survivors of the battle).

### One tick in order
`scripts/sim/battle_sim.gd::step(s, dt)` runs, in order (numbers match the
`phase_us` profiling buckets):
1. Clear: zero `s.ax`/`s.ay`, clear `s.events`, recompute `faction_alive` and
   `faction_cx/cy` (mean position of live marbles) for every faction.
2. Hash: rebuild `fine` (cell = `2 * max_radius`, tracked by
   `scripts/sim/battle_sim.gd::refresh_radius`) and `coarse` (cell =
   `ENGAGE_RADIUS_MULT * BASE_RADIUS`) spatial hashes over all live marbles.
3. Retarget: `scripts/sim/forces.gd::retarget`.
4. Forces: `scripts/sim/forces.gd::accumulate`.
5. Integrate: per live marble, apply acceleration, terrain slope/friction,
   speed clamp, move, clamp to arena walls, push out of terrain obstacles,
   apply terrain hazard damage, then (if any marble stands in a `TOWER`
   cell) resolve tower ownership and apply its aura.
6. Collision: `scripts/sim/collision.gd::resolve`.
7. Weapons: `scripts/sim/weapons.gd::tick`.
8. Spin decay: every live marble's `spin` decays toward `RPM_MIN`.
9. Transitions: captain aura morale regen, `ENGAGE -> RETREAT`, and
   `RETREAT` marbles reaching their home edge become `fled` and `DEAD`.

`s.tick += 1` and `s.time += dt` finish the step. If a `TerrainGrid` is
attached and `dirty`, `scripts/sim/terrain_grid.gd::finalize` runs first.

### Forces
`scripts/sim/forces.gd::retarget` runs a coarse-hash nearest-enemy search for
one fifteenth of the marbles each tick (`(i + tick) % ENGAGE_RETARGET_TICKS
== 0`, so the whole roster is refreshed on a rolling schedule); all other
factions count as enemies. Others keep their `target_id` unless it just died,
in which case it is cleared to `-1`.

`scripts/sim/forces.gd::accumulate` sums accelerations into `s.ax[i]`,
`s.ay[i]` for every live marble (`r = radius[i]`, `d` = vector toward the
other point, `dist = d.length()`):
- **Attraction/engage**: if `target_id[i]` is live,
  `a += K_ATTR * aggression[i] * morale[i] * d.normalized()`; the sign flips
  (`a -= ...`) while `state[i] == RETREAT`.
- **Advance**: only when `state == ENGAGE` and `target_id == -1` — pulls
  `K_ADVANCE * normalize(c - p_i)` toward the nearest enemy faction's live
  centroid `c` (skips factions with `faction_alive <= 0`).
- **Cohesion**: anchor is the faction's live captain position if any, else the
  faction centroid (the captain itself gets no cohesion term at all);
  `a += K_COHESION * d_anchor.normalized()` only when `dist_anchor > 4 * r`.
- **Separation** (`scripts/sim/forces.gd::_accumulate_separation`, a second
  pass over the fine hash's near pairs, same-faction only): for `dist <
  SEPARATION_RANGE_MULT * (r_i + r_j)`, `a -= K_SEPARATION * (1 - dist /
  range) * d.normalized()` applied to both marbles at once, in opposite
  directions; exactly-coincident pairs push apart along one random direction
  drawn from `s.rng`.
- **Retreat pull**: while `state[i] == RETREAT`, `a += K_ATTR *
  HOME_DIR[faction_id % 4]` (a fixed unit vector toward that faction's
  home edge).

Friction and advance-to-move integration (step 5 above) then turn `ax/ay`
into velocity: `v += a * FORCE_SCALE * dt`, plus terrain slope
(`slope_x/y[cell] * FORCE_SCALE * dt`), then `v *= friction` (terrain cell's
`friction` or `Tuning.FRICTION`), then clamp `|v|` to `MAX_SPEED`, then
`p += v * dt`. Arena walls clamp position and reflect the crossed velocity
component by `-RESTITUTION`.

### Collision and spin transfer
`scripts/sim/collision.gd::resolve` walks the fine hash cell by cell,
checking each cell against itself and its 4 forward neighbours (so every
unordered near pair is visited once). For overlapping marbles (`dist <
radius[i] + radius[j]`, coincident pairs pick a random normal from `s.rng`):
- Position correction splits the overlap by inverse mass along the contact
  normal.
- If approaching (`vrel < 0`), an impulse of restitution `RESTITUTION` is
  applied, split by inverse mass.
- Spin transfer: the faster spinner steals `SPIN_TRANSFER * spin[slower]`
  from the slower one, capped at the faster one's `spin_cap`.
- If the pair is from different factions, both marbles additionally lose
  `SPIN_HIT_COST * dt` of spin (floored at `RPM_MIN`) — the "contact cost" of
  fighting.

### Spin as HP/decay
Spin (RPM) is not a marble's health — `hp` is — but it gates weapon damage,
knockback resistance and recheck rate, and decays every tick like a
resource: `scripts/sim/battle_sim.gd::step` reduces every live marble's
`spin` by `SPIN_DECAY * dt`, floored at `RPM_MIN` (spin never fully stops).
Landing a weapon hit costs the attacker no spin at all (only enemy contact
during a collision and fumbling a swing cost spin — see Collision and
Weapons above). Spin is topped up by standing inside a friendly `TOWER`
(`TOWER_SPIN_REGEN * dt`, capped at `spin_cap`) and by spin transfer during
collisions. `spin_cap` rises with rank (`SPIN_CAP[rank]`)
and is re-applied on rank-up.

### Weapons
`scripts/sim/weapons.gd::tick` runs per live marble, in order:
1. Advance `weapon_angle` by `spin[i] * SPIN_TO_RAD * dt` (wrapped to `TAU`).
   `DEAD` marbles are skipped entirely by the whole function; `RETREAT`
   marbles still spin their weapon angle but never hit (step 3 requires
   `state == ENGAGE`).
2. Decrement `hit_cd` toward 0.
3. If `state == ENGAGE`, `hit_cd == 0` and `target_id >= 0` (an enemy exists
   within engage radius per the coarse hash), compute the weapon tip
   `h = p_i + (cos a, sin a) * WEAPON_REACH[w] * r_i` and hit radius
   `hr = WEAPON_HIT_R[w] * r_i`; among `fine.gather(h)` pick the nearest live
   enemy `j` with `|p_j - h| < hr + r_j`. No candidate → `hit_cd =
   WEAPON_RECHECK` (a short delay before regathering).
4. Roll `s.rng.randf()` (or `Weapons.force_roll` when a test pins it):
   `< CRIT_CHANCE` → crit (`mult = CRIT_MULT`); next `FUMBLE_CHANCE` slice →
   fumble: lose `FUMBLE_SPIN_LOSS` spin, pay the full cooldown, no damage, no
   event, stop; else `mult = 1.0`.
5. Damage: `dmg = WEAPON_DMG[w] * (spin[i] / SPIN_REF) * RANK_MULT[rank[i]]
   * mult`. Shield facing: if the target's weapon is `4` (shield) and the
   attack direction is within the shield's facing cone
   (`dot(normalize(p_i - p_j), (cos a_j, sin a_j)) > SHIELD_FACING_DOT`),
   `dmg *= SHIELD_DMG_MULT`.
6. Knockback (velocity impulse, independent of mass): `resist = max(
   KB_SPIN_RESIST_MIN, spin[j] / SPIN_REF)`, `kb = WEAPON_KB[w] * (spin[i] /
   SPIN_REF) / resist`, applied along `normalize(p_j - p_i)`.
7. Apply `dmg` to `hp[j]`, `xp[i] += XP_PER_HIT`, pay `hit_cd = 
   WEAPON_COOLDOWN[w]`, push a `HIT` event.
8. If `hp[j] <= 0`: kill — `state[j] = DEAD`, `kills[i] += 1`, `xp[i] +=
   XP_PER_KILL`, `faction_alive[f_j] -= 1`, push `KILL`; every live marble of
   `f_j` takes `MORALE_HIT_ALLY_DEATH`, plus `MORALE_HIT_CAPTAIN_DEAD` and a
   `CAPTAIN_DEAD` event and `faction_captain[f_j] = -1` if `j` was a captain.
9. Rank-up: while `xp[i] >= RANK_XP[rank[i] + 1]` and `rank[i] < 3`,
   `rank[i] += 1`, `spin_cap` and `hp_max` jump to the new rank's values
   (the `hp_max` delta is added to current `hp`, so ranking up heals),
   `mass` is recomputed from the unchanged `radius`, and a `LEVEL` event is
   pushed. At most one hit per attacker per tick.

Weapon kinds, by `weapon_id` (`Tuning.WEAPON_NAMES`, index-matched into
`WEAPON_REACH`, `WEAPON_DMG`, `WEAPON_COOLDOWN`, `WEAPON_KB`, `WEAPON_HIT_R`):
`0 dagger, 1 sword, 2 spear, 3 axe, 4 shield`. Only weapon `4` has special
behaviour (the shield-facing damage cut above); it has the lowest damage and
reach.

### Terrain types and their friction/effects
`TerrainGrid` (`scripts/sim/terrain_grid.gd`) is a `cols x rows` grid of
`Kind`: `PLAIN=0, MUD=1, COBBLE=2, ICE=3, WATER=4, ROCK=5, TREE=6, TOWER=7,
FIRE=8, SPIKE=9`. Friction per cell
(`scripts/sim/terrain_grid.gd::friction_of`): `PLAIN/ROCK/TREE/TOWER/FIRE/SPIKE
= FRICTION (0.92)`, `MUD = 0.80`, `COBBLE = 0.98`, `ICE = 0.99`, `WATER =
0.70`. `ROCK` and `TREE` are solid (`scripts/sim/terrain_grid.gd::is_solid`):
`scripts/sim/battle_sim.gd::step` treats every solid cell within a 3x3
neighbourhood of a marble's cell as a circle (`TERRAIN_CELL *
OBSTACLE_RADIUS_FRAC` radius at `cell_center`) it cannot pass through,
pushing it out along the normal and reflecting inward velocity by
`RESTITUTION` (gated by a precomputed `near_solid` flag so most cells skip
the check). `FIRE` and `SPIKE` are hazards (`HAZARD_DPS`: `8.0` and `15.0`
per second respectively; every other kind is `0.0`) applied after the
marble's position for the tick is final, killing it (`KILL` event, actor
`-1`) if `hp` drops to 0. `TOWER` cells give their sole occupying faction
(evaluated once per tower cell per tick, before auras apply) `TOWER_SPIN_REGEN`
spin/s and `TOWER_HEAL` hp/s while any of that faction's live marbles stand
in it; a tower with more than one faction present that tick keeps its
previous owner. `slope_x/y` (set per-cell, e.g. by
`scripts/sim/terrain_gen.gd::demo`'s top-row band or the hills layout in
`scripts/sim/terrain_gen.gd::from_tile`) add a constant acceleration before
friction is applied. `scripts/sim/terrain_gen.gd::demo` lays out a fixed demo
arena (two mud blobs, an ice patch, a cobble road, a fire patch, ~12
rock/tree cells, a top slope band, one central tower); `from_tile` builds a
per-world-tile arena keyed by `WorldMap.Kind`, skipping obstacle/hazard cells
that fall inside any battle edge's spawn rect.

### Morale, retreat and routing
`morale` starts at `MORALE_START (0.8)` and scales the attraction force. It
drops on an ally's death (`MORALE_HIT_ALLY_DEATH`) and further on a captain's
death (`MORALE_HIT_CAPTAIN_DEAD`), floored at 0; it regenerates
(`CAPTAIN_MORALE_REGEN * dt`, capped at 1.0) for any marble within
`CAPTAIN_AURA_MULT * captain_radius` of its living faction captain. An
`ENGAGE` marble becomes `RETREAT` (terminal — no rallying back) once `morale
< RETREAT_THRESHOLD` or `hp < RETREAT_HP_FRAC * hp_max`. While `RETREAT`, the
attraction force repels from its target and a constant pull
(`K_ATTR * HOME_DIR[faction_id % 4]`) drags it toward its faction's home
arena edge; reaching that edge (position within its radius of the edge) sets
`fled = 1` and `state = DEAD` (it leaves the arena but still counts toward
`survivors_count`), pushing a `FLED` event.

### Captains
A captain is a marble spawned with `captain = true`
(`scripts/sim/battle_state.gd::spawn`): its radius is multiplied by
`CAPTAIN_RADIUS_MULT` and its index is recorded in
`faction_captain[faction]`. Every other marble in the faction anchors its
cohesion force on the live captain's position instead of the faction
centroid, and heals morale while inside its aura (see above). Killing a
captain (`is_captain[j] == 1` in `scripts/sim/weapons.gd::tick`) clears
`faction_captain[f] = -1`, hits the whole faction's morale, and pushes a
`CAPTAIN_DEAD` event; nothing replaces a dead captain mid-battle.
`scripts/sim/battle_sim.gd::_init` records which factions started the battle
with a captain into `captain_seen`, so a caller can tell "this faction never
had a captain" apart from "its captain died".

### XP and rank gain inside battle
Every landed hit gives the attacker `XP_PER_HIT`; a kill adds `XP_PER_KILL`
on top. `scripts/sim/weapons.gd::tick` checks rank-up immediately after xp
changes: while `xp >= RANK_XP[rank + 1]` and `rank < 3`, rank increases by
one, `spin_cap` and `hp_max` jump to the new rank's `Tuning.SPIN_CAP` /
`HP_BASE * RANK_MULT` values (current `hp` gains the `hp_max` delta), `mass`
is recomputed (`radius` does not change mid-battle), and a `LEVEL` event is
pushed. Multiple rank-ups in one hit are possible if xp jumps far enough.

### How a battle ends and what result it returns
`scripts/sim/battle_sim.gd::winner` looks at which factions still have any
marble with `state == ENGAGE`. Zero such factions → `-2` (everyone dead,
fled or retreating: a draw). Exactly one → that faction's id (win). Two or
more → `-1` (undecided) unless `s.time >= T_MAX_BATTLE`, in which case it is
also `-2` (timeout draw). Callers are expected to call `winner` after each
`step` (or periodically) and stop simulating once it is not `-1`.

## Knobs
| Constant | Value | Raise it and... |
|---|---|---|
| `ARENA_W` | `1600.0` | Widens the battle arena; more room to maneuver, farther to retreat. |
| `ARENA_H` | `900.0` | Taller arena, same trade-off on the other axis. |
| `MAX_FACTIONS` | `16` | Raises how many factions one `BattleState` can track (array sizing only). |
| `WEAPON_COUNT` | `5` | Only meaningful together with new entries in every `WEAPON_*` array; alone it just widens `spawn`'s valid range. |
| `BASE_RADIUS` | `8.0` | Bigger marbles: more mass, bigger hitboxes, bigger fine-hash cells. |
| `RADIUS_RANK_MULT` | `[1.0, 1.1, 1.2, 1.3]` | Higher-rank marbles grow more (index = rank 0..3). |
| `CAPTAIN_RADIUS_MULT` | `1.6` | Captains get visibly and physically bigger relative to their rank. |
| `RANK_MULT` | `[1.0, 1.25, 1.6, 2.2]` | Higher ranks get proportionally more mass, hp and damage (index = rank 0..3). |
| `HP_BASE` | `100.0` | Every marble's baseline max HP scales up. |
| `SPIN_START` | `100.0` | Marbles begin combat spinning faster (more starting damage/knockback). |
| `SPIN_CAP` | `[120.0, 150.0, 190.0, 250.0]` | Raises the spin ceiling for that rank (index = rank 0..3). |
| `MORALE_START` | `0.8` | Marbles begin braver; takes more losses to trigger a retreat. |
| `RESTITUTION` | `0.9` | Bouncier collisions and wall/obstacle hits. |
| `SPIN_TRANSFER` | `0.15` | Faster spinners steal more spin per collision from slower ones. |
| `RPM_MIN` | `5.0` | Raises the floor spin never decays below (weapons keep hitting a little harder even exhausted). |
| `SPIN_HIT_COST` | `6.0` | Enemy contact drains spin faster. |
| `ENGAGE_RETARGET_TICKS` | `15` | Each marble re-picks its nearest enemy less often (staler targeting, cheaper). |
| `ENGAGE_RADIUS_MULT` | `12.0` | Marbles see and engage enemies from farther away (also sizes the coarse hash cell). |
| `K_ATTR` | `40.0` | Stronger pull toward the current target (and toward home while retreating). |
| `K_ADVANCE` | `20.0` | Targetless marbles push toward the enemy centroid more eagerly. |
| `K_COHESION` | `15.0` | Marbles cling to their captain/centroid harder, staying more clustered. |
| `HOME_DIR` | `[Vector2(-1,0), Vector2(1,0), Vector2(0,-1), Vector2(0,1)]` | Changes which arena edge each faction (index = `faction_id % 4`) retreats toward. |
| `SEPARATION_RANGE_MULT` | `1.2` | Same-faction marbles start pushing apart from farther away. |
| `K_SEPARATION` | `120.0` | Same-faction marbles push apart harder (less clumping/overlap). |
| `MAX_NEIGHBORS` | `64` | Raises how many marbles a single `gather()` can return before it stops (denser fights stay accurate longer, costs more). |
| `FORCE_SCALE` | `12.0` | Every accumulated force accelerates velocity more per tick — snappier, twitchier movement. |
| `FRICTION` | `0.92` | Marbles keep more velocity per tick on plain ground (drift more, decelerate slower). |
| `MAX_SPEED` | `400.0` | Raises the hard speed cap. |
| `TERRAIN_CELL` | `40.0` | Coarser terrain grid (fewer, bigger cells); also scales obstacle circle radius. |
| `OBSTACLE_RADIUS_FRAC` | `0.4` | Rock/tree obstacle circles get bigger relative to the terrain cell. |
| `HAZARD_DPS` | `[0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 8.0, 15.0]` | Raises damage-per-second for that `TerrainGrid.Kind` index (only `FIRE`=8 and `SPIKE`=9 are nonzero). |
| `TOWER_SPIN_REGEN` | `10.0` | A tower's owning faction regains spin faster while standing in it. |
| `TOWER_HEAL` | `5.0` | A tower's owning faction heals faster while standing in it. |
| `SPIN_DECAY` | `4.0` | Spin drains faster every tick regardless of combat. |
| `CAPTAIN_AURA_MULT` | `6.0` | Widens the captain's morale-regen aura radius (multiple of captain radius). |
| `CAPTAIN_MORALE_REGEN` | `0.05` | Marbles near their captain regain morale faster. |
| `RETREAT_THRESHOLD` | `0.25` | Marbles rout at a higher morale floor (routs sooner). |
| `RETREAT_HP_FRAC` | `0.20` | Marbles rout at a higher HP fraction (routs sooner). |
| `T_MAX_BATTLE` | `120.0` | Battles are allowed to run longer before `winner()` forces a timeout draw. |
| `SPIN_TO_RAD` | `TAU / 60.0` | Faster weapon-angle rotation per unit of spin. |
| `WEAPON_REACH` | `[0.8, 1.2, 2.0, 1.3, 0.9]` | That weapon's hit point reaches farther from the wielder (index = weapon id, see Weapons). |
| `WEAPON_HIT_R` | `[0.45, 0.5, 0.4, 0.55, 0.5]` | That weapon's hit circle gets bigger (easier to land, index = weapon id). |
| `WEAPON_RECHECK` | `0.1` | Longer pause before re-searching for a target after a miss. |
| `CRIT_CHANCE` | `0.05` | More rolls land as crits. |
| `CRIT_MULT` | `2.0` | Crits hit harder. |
| `FUMBLE_CHANCE` | `0.03` | More rolls land as fumbles (wasted swing + spin loss). |
| `FUMBLE_SPIN_LOSS` | `20.0` | Fumbles cost more spin. |
| `WEAPON_COOLDOWN` | `[0.15, 0.30, 0.45, 0.50, 0.30]` | That weapon swings less often (index = weapon id). |
| `WEAPON_DMG` | `[4.0, 8.0, 8.0, 14.0, 2.0]` | That weapon hits harder before the spin/rank/crit multipliers (index = weapon id). |
| `SPIN_REF` | `100.0` | Raises the spin value damage/knockback/resist are normalized against (effectively nerfs damage/knockback at a given spin). |
| `SHIELD_FACING_DOT` | `0.7071` | Narrows/widens the shield's blocking facing cone (dot-product threshold). |
| `SHIELD_DMG_MULT` | `0.5` | A shield facing the attacker blocks more damage. |
| `KB_SPIN_RESIST_MIN` | `0.5` | Raises the floor on a defender's knockback resistance even at low spin. |
| `WEAPON_KB` | `[60.0, 120.0, 60.0, 220.0, 120.0]` | That weapon knocks its target back harder (index = weapon id: dagger, sword, spear, axe, shield). |
| `XP_PER_HIT` | `1` | Attackers level up faster from landed hits alone. |
| `XP_PER_KILL` | `10` | Attackers level up faster from kills. |
| `MORALE_HIT_ALLY_DEATH` | `-0.02` | Each ally death costs the faction more morale (make more negative to lower). |
| `MORALE_HIT_CAPTAIN_DEAD` | `-0.4` | A captain's death costs the faction more morale. |
| `RANK_XP` | `[0, 30, 120, 500]` | Raises the xp needed to reach that rank (index = rank 0..3). |
| `FRICTION_MUD` | `0.80` | Mud drains velocity less per tick (less sticky). |
| `FRICTION_COBBLE` | `0.98` | Cobble keeps even more velocity (faster travel). |
| `FRICTION_ICE` | `0.99` | Ice keeps even more velocity (more sliding). |
| `FRICTION_WATER` | `0.70` | Water drains velocity less per tick (less of a slog). |

## Tweak recipes
- **Want faster, more decisive battles?** Lower `T_MAX_BATTLE` (current
  `120.0`) toward `60.0`, or raise `RETREAT_THRESHOLD` (current `0.25`) so
  routs start sooner. Watch how often `winner()` returns `-2` (timeout draw).
  Re-run: `bash tools/verify.sh test_battle_sim`.
- **Want weapons to feel heavier?** Raise `WEAPON_DMG` (current `[4.0, 8.0,
  8.0, 14.0, 2.0]`) or `WEAPON_KB` for the weapon you care about. Watch hp
  bars drop faster / bigger knockback pops. `test_weapons` pins the exact
  post-hit `hp`, `spin`, `xp` and `mass` values for several of these
  constants (including `WEAPON_DMG[1]`, `CRIT_MULT`, `FUMBLE_SPIN_LOSS`,
  `WEAPON_COOLDOWN[1]`, `RANK_XP[1]`, `SPIN_CAP[1]`, `HP_BASE`,
  `RANK_MULT[1]`) — update the test too. Re-run:
  `bash tools/verify.sh test_weapons`.
- **Want tighter, more clumped formations?** Raise `K_COHESION` (current
  `15.0`) or lower `SEPARATION_RANGE_MULT` (current `1.2`). Watch marbles
  bunch closer around their captain in-game. Re-run:
  `bash tools/verify.sh test_forces`.
- **Want spinnier, harder-hitting late fights?** Raise `SPIN_CAP` for the
  ranks you care about, or lower `SPIN_DECAY` (current `4.0`) so spin stays
  high longer. Watch `spin` values in a running battle and weapon damage
  scale with them (`dmg` is `spin / SPIN_REF`-scaled in
  `scripts/sim/weapons.gd::tick`). Re-run: `bash tools/verify.sh test_collision`
  and `bash tools/verify.sh test_weapons`.
- **Want a rougher/slower arena underfoot?** Lower `FRICTION_MUD` (current
  `0.80`) or raise `HAZARD_DPS` for `FIRE`/`SPIKE`. Watch marbles bog down or
  die faster on those tiles. Re-run: `bash tools/verify.sh test_terrain_grid`
  and `bash tools/verify.sh test_battle_sim`.

## Gotchas
- Doc drift: `docs/ARCHITECTURE.md` §5 step 6's integration pseudocode
  (`vx += ax*dt`) omits the `Tuning.FORCE_SCALE` multiplier that
  `scripts/sim/battle_sim.gd::step` actually applies (`vx += ax * FORCE_SCALE
  * dt`).
- Everything random in this system goes through `s.rng`
  (`RandomNumberGenerator`, seeded in `scripts/sim/battle_state.gd::_init`) —
  coincident-collision normals, coincident-separation directions, spawn
  positions/weapons, and `s.rng.randf()` weapon rolls. Tests rely on this for
  determinism (`test_weapons` case 14); `Weapons.force_roll` is a static
  test-only override that bypasses the roll entirely when `>= 0.0`.
- `BattleSim` keeps two independent `SpatialHash` instances (`fine` for
  collision/weapons/separation, sized `2 * max_radius`; `coarse` for
  retargeting, sized `ENGAGE_RADIUS_MULT * BASE_RADIUS`, fixed for the whole
  battle even if `max_radius` changes). `refresh_radius` only resizes `fine`.
- `SpatialHash.gather` silently drops candidates past `MAX_NEIGHBORS` rather
  than erroring — very dense pileups (many marbles in one 3x3 cell block)
  can miss neighbours.
- Rank-up in `scripts/sim/weapons.gd::tick` recomputes `mass` from the
  marble's `radius`, which never changes mid-battle even for a rank-0 captain
  that ranks up — only newly spawned marbles get `RADIUS_RANK_MULT`/
  `CAPTAIN_RADIUS_MULT` applied.
- A `TOWER` cell's `owner` only changes when exactly one faction has live
  marbles in it that tick; a contested tower (two+ factions present) keeps
  its previous owner rather than going neutral.
- `is_captain`/`faction_captain` do not get a replacement when a captain
  dies — cohesion falls back to the faction centroid for the rest of the
  battle, and there is no mid-battle promotion.
