# Marble Battle World — Architecture Seam

Godot 4.7, GDScript, GL Compatibility. Zero-player marble war simulation.
Source design: `docs/GDD.md`. This file is the **seam**: every module below
agrees on these names, arrays, and call orders. Implement against this file
exactly. If something here is wrong or missing, stop and write
`// UNDECIDED: <question>` in your report instead of inventing an answer.

## 0. Ground rules

- **No node per marble.** All marble data lives in packed arrays (SoA) on one
  `BattleState` object. Rendering reads those arrays once per frame.
- **No Godot physics bodies.** Custom fixed-step loop, circle-circle only.
- **Determinism.** Every random draw goes through `s.rng`
  (`RandomNumberGenerator`) seeded at battle creation. Same seed, same
  arrays after N ticks. Never call `randf()` / `randi()` globally.
- **Packed arrays are mutated only through the owning object**:
  `s.px[i] = v`. Never copy an array into a local and write to the copy
  (`var a := s.px; a[i] = v` is a bug — packed arrays are copy-on-write).
  Reading through a local alias is fine and preferred in hot loops:
  `var px := s.px` then `px[i]` for reads only.
- **Static-function modules.** `Forces`, `Collision`, `Weapons`, `Terrain`
  are `class_name` scripts with only `static func`s taking a `BattleState`.
- **Tests are headless.** Each `scripts/tests/test_<name>.gd` is
  `extends SceneTree`, builds state by hand, calls the module, and reports
  through `TestKit` (§7). Last line printed is `ALL_PASS (...)` or
  `FAILURES=n of m`.
- Class names registered via `class_name` need one `--import` to become
  visible. `tools/verify.sh` does this before every test run.

## 1. Files

| Path | class_name | Role |
|---|---|---|
| `scripts/sim/tuning.gd` | `Tuning` | Every constant from GDD §7 plus fiat values (§2 below). Consts only. |
| `scripts/sim/battle_state.gd` | `BattleState` | SoA arrays, allocation, spawn helpers, arena bounds, rng. |
| `scripts/sim/spatial_hash.gd` | `SpatialHash` | Uniform grid, rebuilt each tick. |
| `scripts/sim/forces.gd` | `Forces` | Attraction, cohesion, separation, retreat, slope → `s.ax/ay`. |
| `scripts/sim/collision.gd` | `Collision` | Circle-circle resolve, spin transfer. |
| `scripts/sim/weapons.gd` | `Weapons` | Weapon table, hit test, damage, knockback, xp, kills. (M2) |
| `scripts/sim/terrain_grid.gd` | `TerrainGrid` | Arena cell grid, friction / slope / obstacle sample. (M2) |
| `scripts/sim/battle_sim.gd` | `BattleSim` | `step(s, dt)`: the tick order (§5). Owns hashes. |
| `scripts/render/battle_renderer.gd` | `BattleRenderer` | `Node2D`; MultiMesh bodies/weapons/hp bars; `build_buffer` pure. |
| `shaders/marble_body.gdshader` | — | Circle SDF, fill = INSTANCE_CUSTOM.rgb, rank ring = .a |
| `scripts/tests/test_kit.gd` | — (preload) | `check`, `approx`, `finish`. |
| `scripts/tests/test_<x>.gd` | — | One per module. |
| `scripts/bench_battle.gd` | — | Headless: 500 marbles, 600 ticks, prints `SIM_MS_AVG=`. |
| `scenes/battle.tscn` | — | `BattleRenderer` root + `Camera2D`. Runs a demo battle. |
| `tools/verify.sh` | — | The membrane. `bash tools/verify.sh <test_basename> [round]`. |

## 2. Tuning (`Tuning`, all `const`)

From GDD §7 verbatim:

```
DT = 1.0/60.0
ENGAGE_RADIUS_MULT = 12.0        # engage_radius = 12 * r
K_ATTR = 40.0
K_COHESION = 15.0
K_SEPARATION = 120.0
SEPARATION_RANGE_MULT = 1.2      # range = 1.2 * r
SPIN_START = 100.0
SPIN_CAP = [120.0, 150.0, 190.0, 250.0]      # by rank
SPIN_DECAY = 4.0                 # per second
SPIN_HIT_COST = 6.0
SPIN_TRANSFER = 0.15
FRICTION = 0.92
FRICTION_MUD = 0.80
FRICTION_COBBLE = 0.98
MORALE_START = 0.8
MORALE_HIT_ALLY_DEATH = -0.02
MORALE_HIT_CAPTAIN_DEAD = -0.4
RETREAT_THRESHOLD = 0.25
RANK_MULT = [1.0, 1.25, 1.6, 2.2]
XP_PER_HIT = 1
XP_PER_KILL = 10
RANK_XP = [0, 30, 120, 500]
T_MAX_BATTLE = 120.0
```

Fiat values (GDD silent; chosen here, tagged so the Leader can veto):

```
BASE_RADIUS = 8.0                # world units, rank 0
RADIUS_RANK_MULT = [1.0, 1.1, 1.2, 1.3]
CAPTAIN_RADIUS_MULT = 1.6
HP_BASE = 100.0                  # hp_max = HP_BASE * RANK_MULT[rank]
SPIN_REF = 100.0                 # damage/knockback normaliser
SPIN_TO_RAD = TAU / 60.0         # RPM -> rad/s
RPM_MIN = 5.0                    # spin floors here; never negative
MAX_SPEED = 400.0                # velocity clamp, units/s
CRIT_CHANCE = 0.05
CRIT_MULT = 2.0
FUMBLE_CHANCE = 0.03
FUMBLE_SPIN_LOSS = 20.0
RESTITUTION = 0.9                # collision bounce
ARENA_W = 1600.0
ARENA_H = 900.0
ENGAGE_RETARGET_TICKS = 15       # attraction target refresh cadence
MAX_NEIGHBORS = 64               # SpatialHash.scratch capacity
RETREAT_HP_FRAC = 0.20
FACTION_COLORS = [Color(0.85,0.2,0.2), Color(0.2,0.4,0.9), Color(0.2,0.7,0.3),
                  Color(0.9,0.7,0.1), Color(0.6,0.3,0.8), Color(0.9,0.5,0.2),
                  Color(0.2,0.8,0.8), Color(0.5,0.5,0.5)]
# Faction home edge, by faction index mod 4: 0 = left (-1,0), 1 = right (1,0),
# 2 = top (0,-1), 3 = bottom (0,1). Retreat pulls toward this edge.
HOME_DIR = [Vector2(-1,0), Vector2(1,0), Vector2(0,-1), Vector2(0,1)]
```

Weapon table (GDD §1.3 words → numbers, fiat). Index = weapon_id.

| id | name | reach (×r) | base dmg | cooldown s | knockback | hit radius (×r) |
|---|---|---|---|---|---|---|
| 0 | dagger | 0.8 | 4.0 | 0.15 | 60.0 | 0.45 |
| 1 | sword | 1.2 | 8.0 | 0.30 | 120.0 | 0.5 |
| 2 | spear | 2.0 | 8.0 | 0.45 | 60.0 | 0.4 |
| 3 | axe | 1.3 | 14.0 | 0.50 | 220.0 | 0.55 |
| 4 | shield | 0.9 | 2.0 | 0.30 | 120.0 | 0.5 |

Stored as parallel `const` arrays: `WEAPON_REACH`, `WEAPON_DMG`,
`WEAPON_COOLDOWN`, `WEAPON_KB`, `WEAPON_HIT_R`, `WEAPON_NAMES`.
Shield: incoming damage ×0.5 when the attacker lies within 90° of the
defender's `weapon_angle` direction (dot(dir_to_attacker, facing) > 0.7071).

## 3. BattleState

```gdscript
class_name BattleState extends RefCounted

enum State { ENGAGE = 0, RETREAT = 1, DEAD = 2 }

var n: int = 0                 # marbles allocated (slots 0..n-1); never shrinks during a battle
var cap: int                   # array capacity; arrays are resized to cap once
var arena: Rect2               # Rect2(0, 0, Tuning.ARENA_W, Tuning.ARENA_H) by default
var rng: RandomNumberGenerator
var tick: int = 0
var time: float = 0.0
var faction_count: int = 0

# per-marble floats
var px, py, vx, vy: PackedFloat32Array      # position, velocity
var ax, ay: PackedFloat32Array              # force accumulator (acceleration), zeroed by BattleSim each tick
var radius, mass: PackedFloat32Array
var hp, hp_max: PackedFloat32Array
var spin, spin_cap: PackedFloat32Array
var weapon_angle: PackedFloat32Array        # radians
var hit_cd: PackedFloat32Array              # seconds until this marble may hit again
var morale, aggression: PackedFloat32Array
# per-marble ints
var weapon_id, faction_id, rank, state, captain_id, kills, xp: PackedInt32Array
var target_id: PackedInt32Array             # current attraction target, -1 none
var is_captain: PackedByteArray             # 1 if captain
# per-faction
var faction_alive: PackedInt32Array         # live count, maintained by BattleSim
var faction_cx, faction_cy: PackedFloat32Array   # centroid of live marbles, recomputed each tick
var faction_captain: PackedInt32Array       # marble index of captain, -1 none

func _init(capacity: int, seed: int) -> void
    # allocates all arrays to `capacity`, rng.seed = seed, arena default
func spawn(x: float, y: float, faction: int, rank_: int, weapon: int, captain: bool) -> int
    # writes slot n, returns index; n += 1. Fails (push_error, returns -1) when n == cap.
    # radius = BASE_RADIUS * RADIUS_RANK_MULT[rank] * (CAPTAIN_RADIUS_MULT if captain else 1)
    # mass = radius*radius * RANK_MULT[rank]
    # hp = hp_max = HP_BASE * RANK_MULT[rank]
    # spin = SPIN_START; spin_cap = SPIN_CAP[rank]; weapon_angle = rng.randf() * TAU
    # morale = MORALE_START; aggression = 1.0; state = ENGAGE; target_id = -1; hit_cd = 0
    # captain_id = -1; kills = xp = 0; vx = vy = ax = ay = 0
    # faction_count = max(faction_count, faction+1); if captain: faction_captain[faction] = idx
func alive_count() -> int              # slots with state != DEAD
func spawn_block(faction: int, count: int, rect: Rect2, weapon: int) -> void
    # count rank-0 marbles at rng-uniform positions inside rect, non-overlapping not required
```

`faction_*` arrays are sized 16 (max factions per battle). `spawn` with
`faction >= 16` is a `push_error` + return -1.

## 4. SpatialHash

```gdscript
class_name SpatialHash extends RefCounted

var cell_size: float
var origin: Vector2
var cols: int
var rows: int
var cell_start: PackedInt32Array   # size cols*rows + 1; cell c owns entries[cell_start[c] .. cell_start[c+1])
var entries: PackedInt32Array      # marble indices grouped by cell (counting sort)
var cell_of: PackedInt32Array      # size >= n; cell id per marble, -1 if excluded (DEAD)
var scratch: PackedInt32Array      # capacity Tuning.MAX_NEIGHBORS; filled by gather()

func setup(bounds: Rect2, cell: float) -> void
    # origin = bounds.position; cols = ceili(bounds.size.x / cell) max 1; rows likewise.
func build(px: PackedFloat32Array, py: PackedFloat32Array, state: PackedInt32Array, n: int) -> void
    # includes every i < n with state[i] != 2 (DEAD). Positions outside bounds clamp to edge cells.
func cell_at(x: float, y: float) -> int          # clamped to grid
func gather(x: float, y: float) -> int
    # fills scratch[0..k) with marble indices from the 3x3 cells around (x,y), returns k.
    # Includes the querying marble itself if it is in range — callers skip i == j.
    # Stops at MAX_NEIGHBORS (drops the rest; never errors).
```

Counting sort: pass 1 counts per cell, prefix-sum into `cell_start`,
pass 2 places indices. No per-cell Arrays, no Dictionaries.

## 5. Tick order (`BattleSim.step(s: BattleState, dt: float)`)

```
1. s.ax.fill(0); s.ay.fill(0)                                          (BattleSim)
2. recompute s.faction_alive, s.faction_cx/cy over live marbles          (BattleSim)
3. fine.build(...)   cell = 2 * max live radius (BattleSim tracks max radius at spawn)
   coarse.build(...) cell = Tuning.ENGAGE_RADIUS_MULT * Tuning.BASE_RADIUS
4. Forces.retarget(s, coarse, s.tick)   # marbles with (i + tick) % ENGAGE_RETARGET_TICKS == 0 pick nearest enemy within engage radius via coarse.gather; else keep target unless target DEAD → -1
5. Forces.accumulate(s, fine)           # attraction, cohesion, separation, retreat → ax/ay
6. integrate (BattleSim):
      vx += ax*dt; vy += ay*dt
      vx *= friction; vy *= friction        (M1: Tuning.FRICTION; M2: TerrainGrid sample)
      clamp speed to MAX_SPEED
      px += vx*dt; py += vy*dt
      arena walls: if px < r: px = r, vx = -vx*RESTITUTION (same for other three walls)
7. Collision.resolve(s, fine, dt)       # pairs i<j from fine.gather; DEAD skipped
8. Weapons.tick(s, fine, dt)            (M2) advance weapon_angle, cooldowns, hits
9. spin decay (BattleSim): spin = max(RPM_MIN, spin - SPIN_DECAY*dt)   for live marbles
10. state transitions (BattleSim, M2): morale/hp → RETREAT; hp <= 0 → DEAD
11. s.tick += 1; s.time += dt
```

M1 implements 1–7 and 9 and 11. Steps 8, 10 land in M2 without changing
the order.

`BattleSim` API:

```gdscript
class_name BattleSim extends RefCounted
var fine: SpatialHash
var coarse: SpatialHash
var max_radius: float          # recomputed from s.radius[0..n) in _init and on demand via refresh_radius(s)
func _init(s: BattleState) -> void
func step(s: BattleState, dt: float) -> void
func winner(s: BattleState) -> int     # M2: faction id with live ENGAGE marbles when all others have none; -1 while undecided; -2 on timeout (s.time >= T_MAX_BATTLE)
```

## 6. Forces — formulas

All produce accelerations (force / mass) added into `s.ax[i]`, `s.ay[i]`.
Let `r = s.radius[i]`, `d` = vector from i to the other, `dist = d.length()`.

- **Attraction**: if `target_id[i] >= 0` and target live:
  `a += K_ATTR * aggression[i] * morale[i] * d.normalized()` (unit dir toward target).
  If `state[i] == RETREAT` the sign flips: `a -= ...` (repelled).
- **Cohesion**: anchor = own faction captain position if `faction_captain[f] >= 0`
  and that captain is live, else faction centroid.
  `a += K_COHESION * d_anchor.normalized()` when `dist_anchor > 4 * r`; zero inside.
- **Separation**: for every live neighbour j (from `fine.gather`) of the same
  faction with `dist < SEPARATION_RANGE_MULT * (r_i + r_j)` and `dist > 0`:
  `a -= K_SEPARATION * (1 - dist / range) * d.normalized()`.
  Coincident marbles (`dist == 0`): push along `Vector2(1, 0)` rotated by
  `s.rng.randf() * TAU`.
- **Retreat**: when `state[i] == RETREAT`: `a += K_ATTR * HOME_DIR[faction % 4]`.
- **Retarget** (coarse hash): nearest live marble j with `faction_id[j] != faction_id[i]`
  and `dist <= ENGAGE_RADIUS_MULT * r`. None → `target_id = -1`.
  M1 has no diplomacy: every other faction is an enemy.

## 7. TestKit (`scripts/tests/test_kit.gd`, preload, no class_name)

```gdscript
extends RefCounted
var fails := 0
var count := 0
func check(cond: bool, name: String) -> void   # prints "ok   name" or "FAIL name"
func approx(a: float, b: float, eps: float = 1e-4) -> bool
func finish() -> void   # prints "ALL_PASS (%d checks)" or "FAILURES=%d of %d"
```

Test file shape:

```gdscript
extends SceneTree
const TestKit = preload("res://scripts/tests/test_kit.gd")
func _init() -> void:
    var t := TestKit.new()
    # ... t.check(...)
    t.finish()
    quit()
```

## 8. Renderer (M1: bodies only)

`BattleRenderer extends Node2D`. Child `MultiMeshInstance2D` named `Bodies`
with a `MultiMesh`: `transform_format = TRANSFORM_2D`, `use_colors = false`,
`use_custom_data = true`, mesh = `QuadMesh` size `Vector2(2, 2)`. Material =
`ShaderMaterial` with `shaders/marble_body.gdshader`.

Per instance the 2D buffer layout used by
`RenderingServer.multimesh_set_buffer(rid, buf)` is **12 floats**:
`[sx, 0, 0, tx,  0, sy, 0, ty,  cr, cg, cb, ca]` where `sx = sy = radius`,
`(tx, ty)` = position, `(cr, cg, cb)` = faction color, `ca = rank / 3.0`.
DEAD marbles: scale 0 (`sx = sy = 0`).

```gdscript
static func build_buffer(s: BattleState) -> PackedFloat32Array   # length s.n * 12, pure, tested headless
func attach(s: BattleState) -> void                              # sets instance_count = s.n
func refresh() -> void                                            # build_buffer + multimesh_set_buffer, called in _process
```

Shader: `shader_type canvas_item`. Vertex passes `INSTANCE_CUSTOM` to a
varying. Fragment: `d = length(UV - 0.5) * 2`; discard `d > 1`; fill
`custom.rgb`; rim highlight lighten where `d > 0.8`; rank ring: if
`custom.a > 0.0` draw a dark ring at `0.55 < d < 0.65` with alpha
`custom.a`.

## 9. Verify protocol

```
bash tools/verify.sh test_spatial_hash 1
  → runs godot --headless --path . --import  (quiet), then
    godot --headless --path . --script res://scripts/tests/test_spatial_hash.gd
  → VERDICT=GREEN file=... | VERDICT=RED reason=... file=...
```

Green requires: exit 0, no `Parse Error` / `SCRIPT ERROR` / `Compile Error`
/ `Failed to load script` in output, no `FAILURES=`, and `ALL_PASS` present.

## 10. M2 additions — weapons, terrain, transitions, captains, events

### 10.1 New tuning (fiat, appended to `Tuning`)

```
K_ADVANCE = 20.0                 # pull toward nearest enemy faction centroid when no target
FRICTION_ICE = 0.99
FRICTION_WATER = 0.70
TERRAIN_CELL = 40.0              # arena grid cell, world units
OBSTACLE_RADIUS_FRAC = 0.4       # rock/tree circle radius = TERRAIN_CELL * this
HAZARD_DPS = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 8.0, 15.0]   # by TerrainGrid.Kind; FIRE 8, SPIKE 15
TOWER_SPIN_REGEN = 10.0          # RPM/s to owner faction inside a tower cell
TOWER_HEAL = 5.0                 # hp/s to owner faction inside a tower cell
CAPTAIN_AURA_MULT = 6.0          # aura radius = 6 * captain radius
CAPTAIN_MORALE_REGEN = 0.05      # morale/s inside aura, capped at 1.0
KB_SPIN_RESIST_MIN = 0.5         # spin_resist = max(this, spin / SPIN_REF)
```

### 10.2 BattleState additions

```gdscript
var fled: PackedByteArray        # 1 when a RETREAT marble reached its home edge; state is then DEAD (out of the arena) but it survives the battle
var events: Array                # per-tick event list, each `[type: int, actor: int, target: int]`; BattleSim clears it at step 1; the scene reads it after step
enum Event { HIT = 0, KILL = 1, LEVEL = 2, CAPTAIN_DEAD = 3, FLED = 4 }
func survivors_count(faction: int) -> int   # marbles of faction with state != DEAD or fled == 1
```

`spawn_block(faction, count, rect, weapon)`: `weapon == -1` draws each
marble's weapon as `rng.randi_range(0, Tuning.WEAPON_COUNT - 1)`.

### 10.3 TerrainGrid (`scripts/sim/terrain_grid.gd`)

```gdscript
class_name TerrainGrid extends RefCounted
enum Kind { PLAIN = 0, MUD = 1, COBBLE = 2, ICE = 3, WATER = 4, ROCK = 5, TREE = 6, TOWER = 7, FIRE = 8, SPIKE = 9 }
var cols: int; var rows: int; var cell: float; var origin: Vector2
var kind: PackedByteArray          # cols*rows, Kind
var slope_x, slope_y: PackedFloat32Array   # per-cell constant acceleration
var owner: PackedInt32Array        # tower owner faction, -1 none (only meaningful for TOWER cells)
func setup(bounds: Rect2, cell_size: float) -> void   # cols = ceili(w/cell), rows = ceili(h/cell); all PLAIN, slopes 0, owner -1
func cell_at(x: float, y: float) -> int                # clamped
func kind_at(x: float, y: float) -> int
func friction_of(k: int) -> float      # PLAIN/ROCK/TREE/TOWER/FIRE/SPIKE 0.92, MUD 0.80, COBBLE 0.98, ICE 0.99, WATER 0.70
static func is_solid(k: int) -> bool   # ROCK, TREE
func cell_center(c: int) -> Vector2
func set_cell(cx: int, cy: int, k: int) -> void
func fill_rect(cx0: int, cy0: int, cx1: int, cy1: int, k: int) -> void   # inclusive, clamped
func set_slope(cx: int, cy: int, v: Vector2) -> void
```

`TerrainGen` (`scripts/sim/terrain_gen.gd`, `class_name TerrainGen`):
`static func demo(g: TerrainGrid, rng: RandomNumberGenerator) -> void` —
two mud blobs, one cobble road strip across the middle, ~12 rock/tree
cells (never inside the spawn rects `Rect2(100,100,500,700)` /
`Rect2(1000,100,500,700)`), one TOWER at the arena centre cell, one FIRE
patch of 2x2 cells, one ICE patch 3x3, a slope band pushing +y on the top
two rows. All draws from `rng`.

### 10.4 Weapons (`scripts/sim/weapons.gd`)

```gdscript
class_name Weapons extends RefCounted
static func tick(s: BattleState, fine: SpatialHash, dt: float) -> void
```

For every marble `i` with `state != DEAD`:
1. `weapon_angle[i] = fposmod(weapon_angle[i] + spin[i] * SPIN_TO_RAD * dt, TAU)`.
2. `hit_cd[i] = max(0, hit_cd[i] - dt)`.
3. Only if `state == ENGAGE`, `hit_cd == 0`, and `target_id[i] >= 0` (a
   coarse-hash enemy exists within engage radius): hit point
   `h = p_i + (cos a, sin a) * WEAPON_REACH[w] * r_i`, hit radius
   `hr = WEAPON_HIT_R[w] * r_i`. Among `fine.gather(h.x, h.y)` pick the
   live enemy `j` (`faction != faction_i`, `state != DEAD`) minimising
   `|p_j - h|` subject to `|p_j - h| < hr + r_j`. None → `hit_cd[i] = WEAPON_RECHECK`
   so the gather is skipped next tick.
4. On a candidate: `roll = s.rng.randf()`.
   - `roll < CRIT_CHANCE` → `mult = CRIT_MULT`
   - else `roll < CRIT_CHANCE + FUMBLE_CHANCE` → fumble: `spin[i] = max(RPM_MIN, spin[i] - FUMBLE_SPIN_LOSS)`, `hit_cd[i] = WEAPON_COOLDOWN[w]`, no damage, no event. Stop.
   - else `mult = 1.0`.
5. `dmg = WEAPON_DMG[w] * (spin[i] / SPIN_REF) * RANK_MULT[rank[i]] * mult`.
   Shield: if `weapon_id[j] == 4` and `dot(normalize(p_i - p_j), (cos a_j, sin a_j)) > SHIELD_FACING_DOT` → `dmg *= SHIELD_DMG_MULT`.
6. `resist = max(KB_SPIN_RESIST_MIN, spin[j] / SPIN_REF)`;
   `kb = WEAPON_KB[w] * (spin[i] / SPIN_REF) / resist`;
   `v_j += normalize(p_j - p_i) * kb` (velocity impulse, mass-independent).
7. `hp[j] -= dmg`; `xp[i] += XP_PER_HIT`; `hit_cd[i] = WEAPON_COOLDOWN[w]`;
   push `[Event.HIT, i, j]`.
8. If `hp[j] <= 0`: `state[j] = DEAD`; `hp[j] = 0`; `kills[i] += 1`;
   `xp[i] += XP_PER_KILL`; `faction_alive[f_j] -= 1`; push `[Event.KILL, i, j]`;
   every live marble `m` of faction `f_j`: `morale[m] = max(0, morale[m] + MORALE_HIT_ALLY_DEATH)`.
   If `is_captain[j]`: additionally `morale[m] = max(0, morale[m] + MORALE_HIT_CAPTAIN_DEAD)`
   for those `m`, `faction_captain[f_j] = -1`, push `[Event.CAPTAIN_DEAD, i, j]`.
9. Rank-up check for `i` (after xp changes): while `rank[i] < 3 and xp[i] >= RANK_XP[rank[i] + 1]`:
   `rank[i] += 1`; `spin_cap[i] = SPIN_CAP[rank]`; `old = hp_max[i]`;
   `hp_max[i] = HP_BASE * RANK_MULT[rank]`; `hp[i] += hp_max[i] - old`;
   `mass[i] = radius[i]^2 * RANK_MULT[rank]` (radius unchanged mid-battle);
   push `[Event.LEVEL, i, rank[i]]`.

One hit per attacker per tick at most. Weapon hits do not cost spin
(contact cost lives in `Collision`).

### 10.5 BattleSim M2 changes

`BattleSim` gains `var terrain: TerrainGrid` (may be null → plain
everywhere) and `var captain_seen: PackedByteArray` sized MAX_FACTIONS,
set to 1 for any faction that had `faction_captain >= 0` at `_init`.

Step 1 also `s.events.clear()`.

Step 6 integrate, per live marble, after `vx += ax*dt`:
- friction = `terrain.friction_of(terrain.kind_at(px, py))` if terrain else `FRICTION`.
- slope: `vx += slope_x[c] * dt; vy += slope_y[c] * dt` (before friction).
- After the wall clamp, obstacles: for the 3x3 terrain cells around the
  marble, each `is_solid` cell is a circle at `cell_center(c)` with radius
  `TERRAIN_CELL * OBSTACLE_RADIUS_FRAC`; if `dist < R + r_i`: push the
  marble out along the normal to `R + r_i` and reflect the normal velocity
  component with `RESTITUTION` if it points into the obstacle.
- hazard: `hp[i] -= HAZARD_DPS[k] * dt`; if `hp <= 0` → `state = DEAD`,
  `faction_alive[f] -= 1`, push `[Event.KILL, -1, i]` (actor -1 = terrain).
- tower: if `k == TOWER`: `owner[c]` = the faction if exactly one faction
  has live marbles in that cell this tick (evaluate once per tick per tower
  cell, before applying auras); if `owner[c] == faction_id[i]`:
  `spin[i] = min(spin_cap, spin + TOWER_SPIN_REGEN*dt)`, `hp[i] = min(hp_max, hp + TOWER_HEAL*dt)`.

Step 8: `Weapons.tick(s, fine, dt)`.

Step 10 transitions, per live marble `i` of faction `f`:
- captain aura: if `faction_captain[f] >= 0` and `dist(i, captain) <= CAPTAIN_AURA_MULT * radius[captain]`:
  `morale[i] = min(1.0, morale[i] + CAPTAIN_MORALE_REGEN * dt)`.
- ENGAGE → RETREAT when any of: `morale < RETREAT_THRESHOLD`,
  `hp < RETREAT_HP_FRAC * hp_max`.
  Captain death only applies its morale hit (Leader decision 2026-09-12).
  RETREAT is terminal for the battle (no rally).
- RETREAT marble at its home edge (`HOME_DIR[f % 4]`: left → `px <= arena.position.x + r`,
  right → `px >= arena.end.x - r`, top/bottom likewise on y) → `fled[i] = 1`,
  `state[i] = DEAD`, `faction_alive[f] -= 1`, push `[Event.FLED, i, -1]`.

### 10.6 Forces M2 change — advance

In `accumulate`, when `state[i] == ENGAGE` and `target_id[i] == -1`: pull
`K_ADVANCE * normalize(c - p_i)` toward the nearest enemy faction centroid
`c` over factions `g != f` with `faction_alive[g] > 0`. No enemy faction
alive → no term.

### 10.7 Renderer M2

Body custom data: `ca = rank / 3.0 + (2.0 if is_captain else 0.0)`; shader:
`cap = custom.a >= 2.0`, `rank = cap ? custom.a - 2.0 : custom.a`; captains
get a dark centre dot (`d < 0.25`).

Second `MultiMeshInstance2D` `Weapons`: quad 2x2, `use_custom_data`, per
instance transform = rotation `weapon_angle` about the marble centre,
scale `(WEAPON_REACH[w] * r, 0.25 * r)`, origin = marble pos + dir *
`0.5 * WEAPON_REACH[w] * r` (a bar from rim to reach); custom =
`(weapon_id / 4.0, 0, 0, 0)`; DEAD → scale 0. Shader draws a dark bar,
shield (`id == 4`) as a short thick bar.

Third `MultiMeshInstance2D` `HpBars`: quad 2x2, transform scale
`(r, 1.5)`, origin `(px, py - r - 4)`, custom `(hp / hp_max, 0, 0, 0)`;
shader fills left `custom.r` fraction green→red, rest dark; hidden (scale
0) when `hp == hp_max` or DEAD.

Static buffer builders, all pure and headless-tested:
`build_buffer(s)` (bodies, unchanged layout), `build_weapon_buffer(s)`,
`build_hp_buffer(s)`.

Terrain: a `TerrainLayer extends Node2D` child drawing one rect per
non-PLAIN cell in `_draw` (colours: MUD 0.55,0.42,0.28; COBBLE 0.75,0.72,0.66;
ICE 0.80,0.90,0.95; WATER 0.45,0.60,0.80; ROCK 0.45,0.45,0.45 circle;
TREE 0.30,0.50,0.30 circle; TOWER 0.35,0.30,0.40 square with owner colour
inner square; FIRE 0.95,0.45,0.10; SPIKE 0.30,0.30,0.30 with X). Redrawn
only when `queue_redraw()` is called (owner change).

Labels: pooled `Label`s (max 50) for captain names (`"Captain %d" % faction`)
following their marble, and popups from `s.events`: KILL → `"+1 kill"` at
the actor, LEVEL → `"LVL %d" % rank` at the actor, CAPTAIN_DEAD →
`"CAPTAIN DOWN"` at the target. Popups rise 30 px over 1.0 s and fade.

## 11. M3 — overworld, units, stacks, battle bridge

Files live in `scripts/world/`. Same rules as §0: SoA packed arrays,
`class_name` modules, `rng` on the owning object, headless tests.

### 11.1 Tuning additions (fiat)

```
WORLD_COLS = 96
WORLD_ROWS = 54
TILE = 32.0                       # world units per tile; map = 3072 x 1728
TILE_COST = [1.0, 1.6, 2.0, 0.0, 3.0, 1.0, 1.2, 0.8]   # by WorldMap.Kind; 0.0 = impassable
N_FACTIONS = 6
TOWNS_PER_FACTION = 1             # capitals; plus NEUTRAL_TOWNS
NEUTRAL_TOWNS = 18
TOWN_MIN_SPACING = 6              # tiles
STACKS_PER_FACTION = 3
STACK_UNITS_MIN = 60
STACK_UNITS_MAX = 120
STACK_CAP = 300
STACK_SPEED = 48.0                # world units/s on cost-1.0 tiles
STACK_RADIUS = 12.0               # collision circle, world units
TIER_COUNTS = [30, 100, 250]      # count < 30 → tier 0 ... >= 250 → tier 3
TIER_NAMES = ["Band", "Company", "Host", "Horde"]
AI_TICK = 2.0                     # seconds between goal picks for an IDLE stack
GOAL_WEIGHTS = [3.0, 3.0, 2.0, 1.0, 1.0]   # hunt_weak, expand, raid, defend, idle
IDLE_AFTER_BATTLE = 3.0           # winner stays put this long
RETREAT_TILES = 6                 # loser falls back this far along its home direction when no own town exists
RETREAT_SPEED_MULT = 1.3
RETREAT_IMMUNITY = 10.0           # seconds a RETREATING stack cannot start a battle
REINFORCE_TILES = 6
MAX_BATTLE_MARBLES = 3000
BATTLE_EXTRA_CAP = 600            # capacity headroom for reinforcements
```

### 11.2 WorldMap (`world_map.gd`)

```gdscript
class_name WorldMap extends RefCounted
enum Kind { PLAINS = 0, FOREST = 1, HILLS = 2, MOUNTAIN = 3, RIVER = 4, RUIN = 5, GRAVEYARD = 6, TOWN = 7 }
var cols: int; var rows: int
var kind: PackedByteArray           # cols*rows
var owner: PackedInt32Array         # faction id, -1 neutral; set from town ownership (M4 borders)
var rng: RandomNumberGenerator
func _init(cols_: int, rows_: int, seed: int) -> void
func idx(tx: int, ty: int) -> int                  # ty*cols + tx; -1 if out of range
func in_bounds(tx: int, ty: int) -> bool
func cost_at(tx: int, ty: int) -> float           # Tuning.TILE_COST[kind]; 0.0 out of range
func passable(tx: int, ty: int) -> bool           # cost > 0
func tile_of(x: float, y: float) -> Vector2i      # floor(x / TILE), clamped
func center_of(tx: int, ty: int) -> Vector2       # (tx + 0.5, ty + 0.5) * TILE
func reachable_count(tx: int, ty: int) -> int     # BFS over passable 4-neighbours (test helper)
```

`WorldGen` (`world_gen.gd`, `class_name WorldGen`):
`static func generate(m: WorldMap) -> Array` returns the town tile list
(`Array[Vector2i]`) and fills `m.kind`. Uses `FastNoiseLite` seeded from
`m.rng.randi()` (noise type SIMPLEX_SMOOTH, frequency 0.05): elevation
`e` in [-1,1]: `e > 0.45` MOUNTAIN, `e > 0.2` HILLS, else PLAINS. A second
noise (seed +1, frequency 0.08) `f > 0.25` → FOREST on PLAINS only. Rivers:
`max(2, cols/32)` rivers, each starting at a random HILLS tile and walking
to the lowest-elevation 4-neighbour until it reaches the map edge or 200
steps, marking RIVER (never over MOUNTAIN; stops instead). RUIN ×6,
GRAVEYARD ×6 on random PLAINS tiles. Towns: `N_FACTIONS * TOWNS_PER_FACTION + NEUTRAL_TOWNS`
tiles chosen from PLAINS with Chebyshev spacing ≥ `TOWN_MIN_SPACING`
(rejection sampling, up to 5000 attempts), set to TOWN, returned in order
(first `N_FACTIONS` are capitals for factions 0..N-1). After placement,
every town must be in the largest passable component: towns outside it are
re-rolled (up to 20 rounds). Determinism: same seed → same map.

### 11.3 Units and Stacks (`units.gd`, `stacks.gd`)

```gdscript
class_name Units extends RefCounted        # every soldier in the world, persistent
var n: int; var cap: int
var faction, rank, xp, kills, weapon, stack: PackedInt32Array   # stack = stack id or -1 (dead/unassigned)
var hp_frac: PackedFloat32Array                                  # 1.0 healthy; wounds persist until Settle (M4)
var alive, is_captain: PackedByteArray
var names: Dictionary                                            # unit id -> String, only captains/legends
func _init(capacity: int) -> void
func add(faction_: int, rank_: int, weapon_: int, captain: bool, stack_: int) -> int   # -1 when full
func kill(id: int) -> void                                       # alive = 0, stack = -1
```

```gdscript
class_name Stacks extends RefCounted
enum State { IDLE = 0, MOVING = 1, BATTLE = 2, RETREATING = 3 }
enum Goal { HUNT_WEAK = 0, EXPAND = 1, RAID = 2, DEFEND = 3, IDLE_HEAL = 4 }
var n: int; var cap: int
var x, y, prev_x, prev_y: PackedFloat32Array
var faction, count, state, goal, battle_id, captain_unit: PackedInt32Array   # battle_id -1; captain_unit -1
var goal_tx, goal_ty: PackedInt32Array
var ai_timer, immunity, idle_timer: PackedFloat32Array
var path: Array                      # per stack: PackedVector2Array of tile centres (world units), empty when none
var path_i: PackedInt32Array         # next waypoint index
var names: Array                     # String per stack
var alive: PackedByteArray           # 0 once count reaches 0 (slot retired)
func _init(capacity: int) -> void
func add(faction_: int, x_: float, y_: float, name_: String) -> int
func tier(i: int) -> int             # from count and Tuning.TIER_COUNTS
func label(i: int) -> String         # "(%s)%s %d/%d" % [TIER_NAMES[tier], name, count, STACK_CAP]
```

`NameGen` (`namegen.gd`, `class_name NameGen`):
`static func stack_name(rng) -> String` and `static func captain_name(rng) -> String`
from syllable tables; captain names carry a dynasty numeral suffix
`" I"` initially (M5 increments).

### 11.4 Pathing (`pathing.gd`)

```gdscript
class_name Pathing extends RefCounted
var grid: AStarGrid2D
func _init(m: WorldMap) -> void      # region = Rect2i(0,0,cols,rows); cell_size = Vector2(TILE,TILE);
                                     # diagonal_mode = ONLY_IF_NO_OBSTACLES; default_compute_heuristic = OCTILE;
                                     # solid where !passable; weight_scale = cost elsewhere; update()
func find(from: Vector2i, to: Vector2i) -> PackedVector2Array   # tile centres in world units, excluding `from`; empty if unreachable
```

### 11.5 BattleBridge (`battle_bridge.gd`)

```gdscript
class_name BattleInstance extends RefCounted   # (in battle_instance.gd)
var id: int
var tile: Vector2i
var state: BattleState
var sim: BattleSim
var terrain: TerrainGrid
var faction_map: PackedInt32Array   # local faction index -> world faction id
var unit_of: PackedInt32Array       # marble index -> unit id
var stack_ids: PackedInt32Array     # every stack that joined
var edge_of_faction: PackedInt32Array   # local faction -> home edge 0..3 (matches Tuning.HOME_DIR order)
var started: float                  # world time
```

Local faction index **equals** the home edge index (0 left, 1 right, 2 top,
3 bottom), so `Tuning.HOME_DIR[f % 4]` is already right. At most 4 world
factions per battle; a fifth collides later and waits.

```gdscript
class_name BattleBridge extends RefCounted
static func edge_for(tile_center: Vector2, from: Vector2, taken: PackedInt32Array) -> int
    # d = from - tile_center; dominant axis picks 0/1 (x) or 2/3 (y); if taken, the opposite edge; if both taken, the first free of the other axis
static func spawn_rect(edge: int) -> Rect2
    # 0: Rect2(40,100,360,700)  1: Rect2(1200,100,360,700)  2: Rect2(300,40,1000,240)  3: Rect2(300,620,1000,240)
static func start(world: World, stack_a: int, stack_b: int) -> BattleInstance
    # capacity = min(MAX_BATTLE_MARBLES, count_a + count_b + BATTLE_EXTRA_CAP); seed = world.rng.randi()
    # terrain = TerrainGen.from_tile(kind of tile, edges used, s.rng); join(inst, stack_a); join(inst, stack_b)
static func join(inst: BattleInstance, world: World, stack: int) -> bool
    # assigns/looks up the local faction for the stack's world faction (edge_for with the stack's prev position)
    # spawns every live unit of the stack: spawn(x,y in spawn_rect(edge), local_f, rank, weapon, is_captain); hp = hp_max * hp_frac
    # records unit_of; stack state = BATTLE, battle_id = inst.id; returns false (no spawn) when capacity would be exceeded
static func finish(inst: BattleInstance, world: World) -> Dictionary
    # for each marble i: u = unit_of[i]; xp/kills/rank copied back; hp_frac = hp/hp_max (fled marbles: their last hp);
    # DEAD and not fled -> Units.kill(u); count of each stack recomputed from units
    # winner_world = faction_map[sim.winner] or -1 for -2
    # loser stacks: state RETREATING, immunity = RETREAT_IMMUNITY, goal = nearest own TOWN tile else RETREAT_TILES back along -HOME_DIR[edge]
    # winner stacks: state IDLE, idle_timer = IDLE_AFTER_BATTLE, stay on tile
    # stacks with count 0 -> alive = 0
    # appends [tile.x, tile.y, dead_count, world.time] to world.scars
    # returns {"winner": winner_world, "tile": tile, "dead": dead_count, "duration": world.time - started}
```

`TerrainGen.from_tile(g, kind, edges: PackedInt32Array, rng)` (fiat table;
obstacles/hazards never inside the spawn rects of the edges given):
PLAINS: 1 mud 5x5, 3 rocks. FOREST: 20 trees, 1 mud. HILLS: rows 0..7 slope
(0,+40), rows 15..22 slope (0,-40), 6 rocks. RIVER: WATER cols 19..20 all
rows except a COBBLE ford rows 10..12, 4 rocks. RUIN: 3 FIRE 2x2, 6 rocks,
cobble rows 11..12. GRAVEYARD: 4 SPIKE cells, 2 mud 5x5. TOWN: TOWER at
(20,11), COBBLE rows 11..12 and cols 19..20, 4 trees. MOUNTAIN: never.

### 11.6 World + WorldSim (`world.gd`, `world_sim.gd`)

```gdscript
class_name World extends RefCounted
var rng: RandomNumberGenerator
var map: WorldMap
var towns: PackedVector2Array       # tile coords as Vector2 (x, y); index = town id
var town_owner: PackedInt32Array    # faction or -1
var units: Units
var stacks: Stacks
var pathing: Pathing
var battles: Array                  # live BattleInstance
var next_battle_id: int
var scars: Array
var time: float
var faction_count: int
static func create(seed: int) -> World
    # map + WorldGen; towns; capitals owned by faction i; STACKS_PER_FACTION stacks per faction placed on
    # the capital tile and its passable neighbours; each stack gets rng.randi_range(STACK_UNITS_MIN, STACK_UNITS_MAX)
    # units rank 0, weapon rng 0..4, plus one captain (rank 1, sword) named by NameGen
```

`WorldSim.step(w: World, dt: float)`:
1. `w.time += dt`; timers (`ai_timer`, `immunity`, `idle_timer`) decrease.
2. AI: every alive stack with state IDLE and `idle_timer <= 0` and
   `ai_timer <= 0`: pick a goal by `GOAL_WEIGHTS` via `w.rng`:
   HUNT_WEAK → nearest enemy stack with `count <= own count` (else any
   enemy stack); EXPAND → nearest neutral town; RAID → nearest enemy town;
   DEFEND → nearest own town; IDLE_HEAL → stay. If a target exists:
   `path = pathing.find(...)`, `path_i = 0`, state MOVING. `ai_timer = AI_TICK`.
   RETREATING stacks that reach their goal become IDLE.
3. Movement: MOVING/RETREATING stacks advance toward `path[path_i]` at
   `STACK_SPEED / cost_at(current tile)` (× `RETREAT_SPEED_MULT` when
   retreating); on reaching a waypoint (distance < 2) advance `path_i`;
   at the end → IDLE (`prev_x/y` are updated **before** the move each tick).
4. Collisions: `SpatialHash` over alive stacks (cell 64, bounds = map);
   pairs with distance < `2 * STACK_RADIUS`, different factions, neither
   in BATTLE, neither with `immunity > 0`: if one of them is on a tile that
   already has a live battle → `BattleBridge.join`; else
   `BattleBridge.start`. At most one new battle per tile per tick.
5. Reinforcements: for each live battle, every stack of an involved world
   faction that is IDLE/MOVING (not RETREATING, not BATTLE) within
   `REINFORCE_TILES` (Chebyshev, tile coords) gets goal = battle tile,
   state MOVING (path recomputed once); when a MOVING stack's tile equals a
   live battle tile of its faction's battle → `join`.
6. Battles: `inst.sim.step(inst.state, Tuning.DT)` for every live battle
   (one sim tick per world tick); when `winner != -1` → `finish`, remove.
7. Retire stacks with `count == 0`.

Tests build a tiny world by hand (`World.new()` with a 12x8 map filled
PLAINS, two stacks placed by the test) rather than through `create` where
possible; `create(seed)` is tested for determinism and counts only.

## 12. M4 — plinko, towns, borders, ledger

### 12.1 Tuning additions (fiat)

```
PLINKO_W = 360.0
PLINKO_H = 480.0
PLINKO_SLOTS = 9
PLINKO_ROWS_MIN = 6
PLINKO_ROWS_MAX = 10
PLINKO_PEG_R = 6.0
PLINKO_BALL_R = 8.0
PLINKO_GRAVITY = 600.0
PLINKO_RESTITUTION = 0.6
PLINKO_DT = 1.0 / 120.0
PLINKO_MAX_STEPS = 2400          # 20 s cap
PLINKO_SLOT_BAND = 40.0          # bottom band height where slot crossings count
PLINKO_MAX_OUTCOMES = 3
RECRUIT_N = [10, 20, 30, 40]     # by stack tier
FORGE_N = 10
DRILL_SPIN_BONUS = 20.0          # spin_cap per drill level, max level 3
HERO_XP = 50
CURSE_FRAC = 0.10
TOWN_POP_START = 50.0
TOWN_POP_MAX = 200.0
TOWN_POP_GROWTH = 0.05           # per second
TOWN_RECRUIT_RATE = 0.10         # units per second while INTACT and owned
TOWN_RECRUIT_RANGE = 8           # tiles: nearest own stack to receive recruits
RAID_RECOVER = 300.0             # s until RAIDED -> INTACT (neutral)
RAZE_RECOVER = 900.0             # s until RAZED -> INTACT (neutral), tile RUIN -> TOWN
RAID_RANGE = 10                  # tiles for RAID/RAZE target search
BORDER_RANGE = 10                # tiles: a tile belongs to the nearest owned town within this
LEDGER_REFRESH = 0.5
```

### 12.2 Plinko (`scripts/world/plinko.gd`)

```gdscript
class_name Plinko extends RefCounted
enum Slot { SETTLE = 0, RECRUIT = 1, RAID = 2, RAZE = 3, FORGE = 4, DRILL = 5, HERO_TRIAL = 6, HEIR = 7, CURSE = 8 }
var rows: int
var pegs: PackedVector2Array          # board space, (0,0) top-left, width PLINKO_W, height PLINKO_H
var slot_order: PackedInt32Array      # length PLINKO_SLOTS, a permutation of Slot values; slot k at x in [k*sw, (k+1)*sw)
var bias: float                       # constant horizontal acceleration, world units/s^2
static func build(rows_: int, bias_: float, rng: RandomNumberGenerator) -> Plinko
    # pegs: row r (0..rows-1) at y = 60 + r * ((PLINKO_H - 120) / rows); columns spaced sw = PLINKO_W / PLINKO_SLOTS,
    # staggered by sw/2 on odd rows; x from sw/2 (even) or sw (odd) up to PLINKO_W - sw/2; slot_order = identity then
    # Fisher-Yates shuffled with rng.
func drop(x0: float, rng: RandomNumberGenerator) -> Dictionary
    # {"path": PackedVector2Array, "slots": PackedInt32Array (distinct Slot values in crossing order, max PLINKO_MAX_OUTCOMES)}
    # ball starts at (x0 + rng.randf_range(-2, 2), PLINKO_BALL_R), v = 0; each PLINKO_DT: v.y += GRAVITY*dt, v.x += bias*dt,
    # p += v*dt; walls x in [R, W-R] reflect with RESTITUTION; peg collision: circle-circle with radius PEG_R + BALL_R,
    # push out along normal, reflect normal velocity with RESTITUTION, and add rng.randf_range(-15, 15) to v.x;
    # once p.y >= PLINKO_H - PLINKO_SLOT_BAND, every slot column k the ball is in is appended (if not already) to slots;
    # ends when p.y >= PLINKO_H - BALL_R or steps == PLINKO_MAX_STEPS (then the slot under the ball is appended if none).
    # path records p every 4 steps (for rendering).
```

`PlinkoProfile` per faction on `World`: `plinko_rows: PackedInt32Array`
(init 7), `plinko_bias: PackedFloat32Array` (init 0), `plinko_order: Array`
of PackedInt32Array (init from `build` with the world rng). Boards are
rebuilt from the profile when a drop happens (`Plinko.build` then
`slot_order = profile order`).

### 12.3 Outcomes (`scripts/world/plinko_outcomes.gd`)

`class_name PlinkoOutcomes`, `static func apply(w: World, stack: int, slot: int) -> String`
returns a one-line log text. Rules (fiat):

- SETTLE: nearest town (any state) whose owner is not `f`, preferring
  neutral, within RAID_RANGE → `owner = f`, state INTACT; all units of the
  stack `hp_frac = 1.0`; `w.recompute_borders()`. No town → heal only.
- RECRUIT: `n = RECRUIT_N[tier]`; nearest own INTACT town within
  TOWN_RECRUIT_RANGE: `n = min(n, floor(pop))`, `pop -= n`; else (wilds)
  `n = n / 2`. Adds `n` units (rank 0, weapon rng, stack = this) up to STACK_CAP.
- RAID: nearest enemy town within RAID_RANGE → state RAIDED, `owner = -1`,
  `pop *= 0.5`; every unit of the stack `xp += 5`; recompute borders.
- RAZE: nearest enemy town within RAID_RANGE → state RAZED, `owner = -1`,
  `pop = 0`, `raze_timer = RAZE_RECOVER`, map tile kind → RUIN; recompute borders.
- FORGE: the FORGE_N lowest-rank alive units of the stack get `rank += 1` (cap 3).
- DRILL: `Units.drill[u] = min(3, drill + 1)` for every unit of the stack.
- HERO_TRIAL: captain unit `xp += HERO_XP`, `rank = min(3, rank + 1)`.
- HEIR: if `captain_unit == -1` or the captain is dead: the alive unit with
  most kills becomes captain (`is_captain = 1`, `names[u] = NameGen.captain_name(w.rng)`,
  `captain_unit = u`); else no effect.
- CURSE: kill `ceil(CURSE_FRAC * count)` non-captain units (desertion, lowest xp first).

`BattleBridge.join` applies `state.spin_cap[i] += DRILL_SPIN_BONUS * drill[u]`.

After `BattleBridge.finish` with a winner: for each winner stack, one drop
per alive captain in it (`drops = 1 if captain alive else 0`); `World`
records `[stack, slots_array, log_lines]` into `w.plinko_log` (Array, last
50 kept) and applies every slot in order. Drops are simulated headlessly
inside `WorldSim` (no rendering dependency); the scene animates the last
entry of `plinko_log` when it changes.

### 12.4 Towns (`scripts/world/town_sim.gd`)

`World` gains parallel town arrays: `town_state: PackedInt32Array`
(0 INTACT, 1 RAIDED, 2 RAZED), `town_pop: PackedFloat32Array`,
`town_recruit: PackedFloat32Array`, `town_timer: PackedFloat32Array`,
plus `plinko_rows/bias/order` and `plinko_log`. `create` and
`setup_blank` initialise them; `add_town(tile, owner)` helper appends to
every array and sets the map tile kind TOWN.

`TownSim.step(w, dt)` (static):
- `pop = min(POP_MAX, pop + POP_GROWTH*dt)` for INTACT towns.
- Owned INTACT towns: `recruit += RECRUIT_RATE*dt`; while `recruit >= 1`
  and `pop >= 1`: `recruit -= 1`, `pop -= 1`, add one unit (rank 0,
  weapon rng) to the nearest own stack within TOWN_RECRUIT_RANGE that is
  not in BATTLE and has `count < STACK_CAP`; if none, create a garrison
  stack on the town tile (`Stacks.add(f, cx, cy, NameGen.stack_name)`,
  goal DEFEND) and add the unit there.
- RAIDED: `timer -= dt`; at 0 → INTACT. RAZED: `timer -= dt`; at 0 →
  INTACT, `pop = TOWN_POP_START/2`, map tile kind → TOWN.
- Ownership by occupation: an alive stack IDLE on a neutral INTACT town
  tile for ≥ 3 s (`idle_timer` finished and state IDLE) captures it
  (`owner = f`, recompute borders).

### 12.5 Borders

`World.recompute_borders()`: for every passable tile, `map.owner` = owner of
the nearest owned town (Chebyshev distance ≤ BORDER_RANGE, ties → lowest
town id), else -1. MOUNTAIN tiles stay -1. Called on every ownership change
(SETTLE/RAID/RAZE/capture/finish) and once in `create`.

### 12.6 Rendering

- `MapLayer`: after the base texture, an ownership overlay texture
  (per-tile owner colour at alpha 0.28, transparent for -1) rebuilt only
  when `w.borders_version` (int, incremented by `recompute_borders`)
  changes; plus border lines: for each tile whose east or south neighbour
  has a different owner, a 2 px line in the darker owner colour (drawn in
  `_draw`, redrawn on version change only). Town markers: a house glyph
  (square + triangle) in owner colour; RAIDED → grey; RAZED → black with a
  small orange flame triangle.
- `LedgerPanel` (`scripts/render/ledger_panel.gd`, `CanvasLayer` child
  `PanelContainer` at top-right, width 260): one row per faction sorted by
  power = units alive + 50 × towns: colour swatch, `♛` for the current
  leader, `units`, `towns`, `stacks`. Refresh every LEDGER_REFRESH s.
- `PlinkoView` (`scripts/render/plinko_view.gd`, `CanvasLayer` child at
  bottom-left, 360×480 scaled 0.5): draws the last board (pegs, slot labels
  from `Plinko.Slot` names, slot_order) and animates the recorded path
  over 2 s, then shows the outcome text for 3 s. Only the newest
  `plinko_log` entry is shown; older ones are skipped.
