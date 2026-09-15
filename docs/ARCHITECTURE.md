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
`static func generate(m: WorldMap, town_count: int) -> Array` returns the town tile list
(`Array[Vector2i]`) and fills `m.kind`. Switches on `Tuning.WORLDGEN_WFC`: if true, uses the WFC pipeline (Stages A–G: prior noise → biome WFC coarse grid → upscale → flow-field rivers → cleanup → props → scored town placement); if false, falls back to legacy `_generate_noise` for byte-identical old maps. Determinism: same seed → same map.

`WorldWfc` (`scripts/world/wfc.gd`, `class_name WorldWfc`, pure static):
- `biome_allow() -> PackedInt32Array`: adjacency bitmasks per biome kind.
- `is_symmetric(allow: PackedInt32Array) -> bool`: validates adjacency table symmetry.
- `violations(grid: PackedInt32Array, cols: int, rows: int, allow: PackedInt32Array) -> int`: count of adjacency violations.
- `solve(cols: int, rows: int, allow: PackedInt32Array, prior: PackedFloat32Array, affinity: float, rng: RandomNumberGenerator, max_attempts: int) -> Dictionary`: returns `{"grid": PackedInt32Array, "attempts": int, "fallback": bool}`.

Rng draw order (every draw from `m.rng`):
```
1. elevation noise seed m.rng.randi() (forest seed = elev_seed + 1, no draw)
2. biome WFC one m.rng.randf() per observation, per attempt (variable count)
          + one m.rng.randi_range() per observation to pick a cell from the lowest-entropy bucket
3. rivers one m.rng.randi_range() per river to pick its source
4. ruins two m.rng.randi_range() per attempt (x, y)
5. graveyards same as ruins
6. towns one m.rng.randf() per placed town
```

Town list order contract: first `N_FACTIONS` entries are farthest-point reordered capitals (spread for kingdom placement); remaining entries are neutral towns in the same order.

### 11.3 Units and Stacks (`units.gd`, `stacks.gd`)

```gdscript
class_name Units extends RefCounted        # every soldier in the world, persistent
var n: int; var cap: int
var faction, rank, xp, kills, weapon, stack: PackedInt32Array   # stack = stack id or -1 (dead/unassigned)
var hp_frac: PackedFloat32Array                                  # 1.0 healthy; wounds persist until Settle (M4)
var alive, is_captain: PackedByteArray
var gen: PackedInt32Array                                         # 0; bumped each time the slot is recycled for a new unit
var reusable: PackedByteArray                                     # 0; 1 = dead and unreferenced, set by SlotSweep
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
var gen: PackedInt32Array                                         # 0; bumped each time the slot is recycled for a new unit
var reusable: PackedByteArray                                     # 0; 1 = dead and unreferenced, set by SlotSweep
var names: Array                     # String per stack
var alive: PackedByteArray           # 0 once count reaches 0 (slot retired; may be recycled, see Slot recycling)
func _init(capacity: int) -> void
func add(faction_: int, x_: float, y_: float, name_: String) -> int
func tier(i: int) -> int             # from count and Tuning.TIER_COUNTS
func label(i: int) -> String         # "(%s)%s %d/%d" % [TIER_NAMES[tier], name, count, STACK_CAP]
```

`NameGen` (`namegen.gd`, `class_name NameGen`):
`static func stack_name(rng) -> String` and `static func captain_name(rng) -> String`
from syllable tables; captain names carry a dynasty numeral suffix
`" I"` initially (M5 increments).

#### Slot recycling (`slot_sweep.gd`)

Both stores append at `n` until `n == cap`; only then does `add()` reuse the lowest slot with `reusable == 1`,
bumping `gen` and resetting every field (a recycled unit also loses `ctrait`, `c_*`, and its `names`/`looks`/`dynasty` entries).
Callers check `has_room()` (space below cap, or any reusable slot) instead of comparing `n` to `cap`.

`SlotSweep.maybe_sweep(w, dt)` runs at the end of `WorldSim.step` on each whole world second while a store is within
256 (units) / 16 (stacks) of cap. `SlotSweep.sweep(w)` recomputes `reusable` from scratch: a dead slot is reusable only if nothing references it —
units: `captain_unit` of an alive stack, `leader`/`mentor` of an alive unit, any `town_lord`, an active battle's `unit_of`/`slayers`/`captain_before`;
stacks: `stack` of an alive unit, `rally_target` of an alive stack, a `reinforce` key, an active battle's `stack_ids`. No rng is used.

Render/UI code that caches by id compares `gen` to spot a new occupant: `StackLayer` (texture cache key `"unit:gen"`, walk state reset),
`SpectatePanel` (a window whose slot was recycled shows "Fallen"), `world_scene` (follow stops).
`gen` and `reusable` are saved; older saves load with both zeroed.

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
  `pop *= 0.5`, `timer = RAID_RECOVER`; every unit of the stack `xp += 5`; recompute borders.
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

## 13. M5 — meta progression (lineage, traits, kingdoms, relations)

### 13.1 Tuning additions (fiat)

```
TRAIT_THRESHOLD = 3              # behaviour counter value that assigns a captain trait
HEIR_RANK_DROP = 1               # heir rank = max(1, captain rank - this)
LEGEND_RANK = 3
KTRAIT_INIT = 0.5                # every kingdom trait starts here; clamped 0..1
KT_WIN_AGGR = 0.02
KT_RAZE_GREED = 0.05
KT_RAZE_PIETY = -0.03
KT_SETTLE_COH = 0.03
KT_RETREAT_AGGR = -0.02
KT_RETREAT_COH = -0.02
KT_PILGRIM_PIETY = 0.05
PLINKO_BIAS_GREED = 200.0        # plinko_bias = (greed - 0.5) * this
GOAL_PILGRIMAGE_BASE = 0.5
GOAL_AVENGE_BASE = 0.5
REL_CAPTAIN_KILLED = -0.5
REL_BATTLE_LOST = -0.1
REL_ALLY_THRESHOLD = 0.5
REL_DIPLOMACY_RATE = 0.01        # per second between bordering factions both with diplomacy > 0.6
REL_DECAY = 0.002                # per second toward 0
SPLIT_UNITS = 600
SPLIT_COHESION = 0.3
MAX_FACTIONS_WORLD = 16
```

### 13.2 Units / World fields

`Units` gains: `ctrait: PackedInt32Array` (-1 none; `enum Trait { CHARGER = 0, CAUTIOUS = 1, TYRANT = 2, BUILDER = 3 }`),
`c_fights, c_retreats, c_razes, c_settles: PackedInt32Array` (behaviour
counters, captains only), `dynasty: Dictionary` unit id → `[name: String, numeral: int]`.

`World` gains: `ktraits: PackedFloat32Array` (size MAX_FACTIONS_WORLD*5:
index `f*5 + k`, k: 0 aggression, 1 diplomacy, 2 greed, 3 piety, 4 cohesion),
`relations: PackedFloat32Array` (MAX_FACTIONS_WORLD², 0.0), `faction_alive: PackedByteArray`
(1 while the faction has towns or stacks), `faction_color: PackedInt32Array`
(index into FACTION_COLORS, `f % 8` at creation), `faction_names: Array` of String
(`NameGen.kingdom_name(rng)` = onset+onset+"ia"/"mark"/"land").
Helpers: `ktrait(f, k) -> float`, `add_ktrait(f, k, d)` (clamped),
`relation(a, b) -> float`, `add_relation(a, b, d)` (symmetric, clamped -1..1),
`allied(a, b) -> bool` (`relation >= REL_ALLY_THRESHOLD`).

### 13.3 Lineage (`scripts/world/lineage.gd`, `class_name Lineage`)

- `static func numeral(n: int) -> String` — Roman numerals 1..3999.
- `static func on_battle_finished(w, inst, result)`: for every stack in the
  battle: captain alive → `c_fights += 1`; stack RETREATING → `c_retreats += 1`
  on its captain (if alive). If the stack's captain died (unit dead and
  `captain_unit` pointed at it): heir = alive unit of the stack with most
  kills (ties lowest id); `is_captain = 1`; `rank = max(1, old_rank - HEIR_RANK_DROP)`;
  `xp = old_xp / 2`; `ctrait` inherited from the dead captain; dynasty
  `[name, numeral + 1]`, `names[heir] = "%s %s" % [name, numeral(n)]`;
  `stacks.captain_unit = heir`; `events_log` line `"<name> <numeral> fell; <heir name> rises"`.
  No alive unit → `captain_unit = -1` (stack dies anyway when count 0).
- `static func note_settle(w, captain_unit)` / `note_raze(w, captain_unit)`:
  counters, called by `PlinkoOutcomes` SETTLE/RAZE.
- `static func update_trait(w, u)`: after any counter change: the largest
  counter ≥ TRAIT_THRESHOLD sets `ctrait` (fights → CHARGER, retreats →
  CAUTIOUS, razes → TYRANT, settles → BUILDER); never downgrades (only
  changes when a different counter exceeds the current ctrait's counter).
- Legend naming (`static func check_legend(w, u)`), called by the bridge
  copy-back when `rank` becomes LEGEND_RANK: `names[u] = NameGen.legend_name(w.rng, kills)`
  = `"<Adjective> <Name>, killer of <kills>"` (adjectives fiat: Mudslide,
  Ironhand, Redspin, Grim, Quiet, Wolfish, Brassbound, Hollow).
- Captain creation everywhere (`World.create`, HEIR outcome, town garrisons)
  goes through `Lineage.make_captain(w, u, name_base)` which sets dynasty
  `[name_base, 1]` and `names[u] = name_base + " I"`.

### 13.4 Kingdoms (`scripts/world/kingdoms.gd`, `class_name Kingdoms`)

- `static func on_event(w, kind: String, faction: int)`: applies the
  KT_* deltas: "win" (aggression), "raze" (greed +, piety −), "settle"
  (cohesion), "retreat" (aggression −, cohesion −), "pilgrim" (piety).
- `static func goal_weights(w, f) -> PackedFloat32Array` (7 entries, Goal
  order below): `[HUNT_WEAK: 3*(0.5+aggr), EXPAND: 3*(1.5-aggr), RAID: 2*(0.5+greed),
  DEFEND: 1*(0.5+coh), IDLE_HEAL: 1, PILGRIMAGE: GOAL_PILGRIMAGE_BASE + piety,
  AVENGE: GOAL_AVENGE_BASE + max(0, -min relation with any alive faction)]`.
  `Stacks.Goal` gains `PILGRIMAGE = 5` (nearest RUIN or GRAVEYARD tile;
  arrival → `on_event("pilgrim")`, then IDLE) and `AVENGE = 6` (nearest stack
  of the most-hated faction, i.e. lowest relation < 0; none → falls back).
- `static func recruit_weapon(w, f, rng) -> int`: weights per weapon id
  `[dagger 1+aggr, sword 1, spear 1+coh, axe 1+aggr, shield 1+coh]`.
  Used by TownSim recruits and RECRUIT outcome.
- `static func plinko_bias(w, f) -> float` = `(greed - 0.5) * PLINKO_BIAS_GREED`
  (written into `w.plinko_bias[f]` by `tick`).
- `static func trait_favor(order: PackedInt32Array, trait: int) -> PackedInt32Array`:
  copy with the favoured slot moved to index 4 (CHARGER → RECRUIT, CAUTIOUS →
  DRILL, TYRANT → RAZE, BUILDER → SETTLE); -1 → unchanged. WorldSim applies
  it to the board's `slot_order` using the dropping stack's captain ctrait.
- `static func tick(w, dt)` (every world tick, cheap): relations decay
  toward 0 by REL_DECAY*dt; bordering factions (some tile owned by a has a
  4-neighbour owned by b — recomputed only when `borders_version` changes,
  cached as a PackedByteArray adjacency) with both diplomacy > 0.6 gain
  REL_DIPLOMACY_RATE*dt; refresh `plinko_bias`.
- Relations on battle finish (`static func on_battle_finished(w, inst, result)`):
  each losing world faction `add_relation(loser, winner, REL_BATTLE_LOST)`;
  each captain killed → `add_relation(victim_faction, killer_faction, REL_CAPTAIN_KILLED)`
  (killer faction = world faction of the marble whose KILL event targeted the captain:
  the bridge records `captain_killers: Array` of `[victim_world_f, killer_world_f]` from
  `CAPTAIN_DEAD` events during the battle).
- `static func check_split(w)`: for each alive faction with alive units >
  SPLIT_UNITS and cohesion < SPLIT_COHESION and `faction_count < MAX_FACTIONS_WORLD`:
  the largest stack becomes a new faction `g = faction_count++` (its units
  re-flagged, `faction_color[g] = g % 8`, name new, ktraits copied with
  cohesion reset to KTRAIT_INIT), the nearest town owned by the old faction
  within 6 tiles (if any) flips to `g`, `add_relation(f, g, -0.6)`, both
  stacks get `immunity = RETREAT_IMMUNITY`, event logged, borders recomputed.
  Once per 30 s of world time per faction at most (`split_cooldown` array).
- `static func check_death(w)`: an alive faction with zero towns and zero
  alive stacks → `faction_alive = 0`, event `"Kingdom <name> fell"`.
- Rebirth + mercenaries live in `BattleBridge.finish`: when a losing
  faction's last stack is destroyed (count 0) and that faction has zero
  towns: units that survived (fled) are re-homed — if any survivor has
  `rank >= LEGEND_RANK`: they form a new stack of a **new faction** at the
  nearest RUIN tile (name from NameGen, colour `g % 8`, ktraits init),
  event `"<legend name> founds <kingdom>"`; else they join the winner stack
  (faction re-flagged, `stack` reassigned) as mercenaries, event logged.

### 13.5 Allies in battle

`BattleBridge.join`: if some already-joined local faction's world faction is
allied with the joining stack's world faction, the stack joins **that**
local index (same edge, same side). `finish`: the winning local side's
world faction = the world faction of the joined stack with the most
survivors on that side; every stack on the winning side is a winner
(IDLE), every stack on other sides a loser. Plinko drops go to every winner
stack with a captain. `result` gains `"winner_side": local index`.

## 14. M6 — battle LOD, save/load, time controls, spectate, timeline

### 14.1 Tuning additions (fiat)

```
LOD_K = 0.25                     # Lanchester damage scale: dmg/s per side = K * Σ(spin/SPIN_REF * RANK_MULT * WEAPON_DMG / WEAPON_COOLDOWN) (≈ contact fraction of a side)
LOD_XP_PER_DMG = 0.125           # xp credited per damage point dealt (≈ XP_PER_HIT per 8 dmg)
LOD_FLEE_TIME = 5.0              # seconds in RETREAT before a marble counts as fled under LOD
SAVE_VERSION = 1
SPEED_STEPS = [1, 5, 50]         # steps per frame for x1 / x5 / x50; "max" fits steps into MAX_FRAME_MS
MAX_FRAME_MS = 12.0
TIMELINE_LINES = 12
```

### 14.2 BattleLod (`scripts/world/battle_lod.gd`, `class_name BattleLod`)

`static func step(inst: BattleInstance, dt: float) -> void` — the
statistical stand-in for `BattleSim.step` when a battle is not being
watched. Operates on the same `BattleState`; positions are left untouched
(they stay where the last full-sim tick or the spawn put them).

1. Per local side `s` (0..3): `rate[s] = LOD_K * Σ_{i live, ENGAGE, faction i == s} spin[i]/SPIN_REF * RANK_MULT[rank[i]] * WEAPON_DMG[w]/WEAPON_COOLDOWN[w]`.
2. For each side `s` with `rate[s] > 0`: total damage `D = rate[s] * dt`
   distributed over enemy sides in proportion to their live counts; within
   an enemy side pick targets with `state.rng.randi_range` among live
   marbles (ENGAGE or RETREAT), one random attacker `a` of side `s` per
   target; apply `hp[t] -= chunk` (chunk = D / max(1, ceil(D / 8)) so
   several marbles take damage per step), `xp[a] += chunk * LOD_XP_PER_DMG`
   (accumulate in a float side array and floor into xp), push `[HIT, a, t]`.
   Death: `state = DEAD`, `hp = 0`, `kills[a] += 1`, `xp[a] += XP_PER_KILL`,
   `faction_alive[side] -= 1`, `[KILL, a, t]`, morale hits to that side
   (ally −0.02; captain −0.4 + `faction_captain = -1` + `[CAPTAIN_DEAD, a, t]`),
   rank-up check on `a` exactly as `Weapons` does it.
3. Spin decay, morale/hp retreat triggers as `BattleSim` step 10; a RETREAT
   marble accumulates `hit_cd` as a flee timer (reuse the field): after
   `LOD_FLEE_TIME` seconds → `fled = 1, state = DEAD, faction_alive -= 1, [FLED, i, -1]`.
4. `s.tick += 1; s.time += dt`; `s.events` is cleared at the start of the step.

`WorldSim.step_battles` steps each battle with `BattleSim.step` when
`inst.id == w.watched_battle` (new `World` field, -1 none; set by the
scene when the battle view opens) and with `BattleLod.step` otherwise.
`winner()` and `finish()` are unchanged.

### 14.3 SaveGame (`scripts/world/save_game.gd`, `class_name SaveGame`)

`static func save(w: World, path: String) -> Error` writes one file:
header Dictionary `{version, seed_state, time, faction_count, next_battle_id,
cols, rows, borders_version}` via `store_var`, then every packed array of
`WorldMap`, `Units`, `Stacks` (including `path` as an Array of
PackedVector2Array), the town arrays, plinko profile, `ktraits`,
`relations`, `faction_alive/color/names`, `dynasty`, `names`, `events_log`,
`plinko_log` (last 10 only), `scars` — each as `store_var` of a Dictionary
`{field: value}` per object (packed arrays serialise natively; no per-unit
dictionaries). Live battles are **not** saved: before writing, every
stack in BATTLE is set IDLE with `immunity = RETREAT_IMMUNITY` on a
**copy** of the state? — no copies: `save` first calls
`BattleBridge.finish` on nothing; instead it records battles as absent and
the loader restores those stacks as IDLE with immunity. `w.rng.state` is
saved so the sequence continues.

`static func load(path: String) -> World` rebuilds `World` from the file,
recreates `Pathing`, calls `sync_town_arrays` and `recompute_borders`.
Round-trip test: `create(42)` → 300 steps → save → load → `stacks.x`,
`units.xp`, `map.kind`, `town_owner`, `ktraits`, `relations`, `events_log`
equal; then 300 more steps on both (original and loaded) yield equal
`stacks.x` (determinism across save/load).

### 14.4 Scene additions

- Time controls (`CanvasLayer` `HBoxContainer` bottom-centre): buttons
  `⏸ 1x 5x 50x MAX`; keys `space, 1, 2, 3, 4`. MAX runs steps until
  `MAX_FRAME_MS` elapsed in that frame.
- `SpectatePanel` (`scripts/render/spectate_panel.gd`): left-click on a
  stack (world view) → panel at bottom-right: stack label, faction name,
  captain name + dynasty numeral + trait name, top 5 units by kills with
  names when present, goal name; in the battle view a left-click on a
  marble (nearest within 12 px) shows that unit. `Esc` closes.
- `TimelinePanel`: top-left under the HUD, last `TIMELINE_LINES` lines of
  `events_log`, newest at the bottom, refreshed when the log length changes.
- `LedgerPanel` anchored to the right edge with `anchor_right = 1,
  offset_left = -270` so it never clips; faction rows show `faction_names`.
- Save/load: `F5` saves `user://save1.bin`, `F9` loads it (scene rebuilds
  layers from the new `World`).
- `w.watched_battle` set on battle view open, -1 on close.

## 15. M7 — bounce, RPM economy, damage variance, spin legibility

Goal (Leader, 2026-09-12): battles must *look* like spinning tops bouncing
off obstacles, enemies and allies. RPM is the resource: hits and clashes
drain it, ally bounces and good terrain raise it, swamps drain it, and RPM
scales damage. The viewer has no input, so every effect must be legible
with little clutter. Root cause of the old "grinding blob": `FRICTION`
0.92 applied **per tick** kept 0.7% of speed per second, so every bounce
died within ~0.2 s.

Rule for every slice: §15 **extends** §10; anything §15 does not mention
stays as §10 says. Old constants (`SPIN_TRANSFER`, `SPIN_HIT_COST`,
`FUMBLE_*`, `CRIT_CHANCE`, `FRICTION_MUD/COBBLE/ICE/WATER`) stay defined
until a cleanup slice removes them; new code must not read them.
`SPIN_DECAY` stays (BattleLod uses it). `CRIT_MULT` stays and is reused.

### 15.1 Tuning additions (fiat, all tunable in the feel pass)

```
# velocity fraction kept after 1 s, index = TerrainGrid.Kind (10 = FLOWERS)
DRAG_KEEP_PER_S = [0.12, 0.02, 0.20, 0.60, 0.01, 0.12, 0.12, 0.12, 0.12, 0.12, 0.12]  # M8 pace
# RPM per second by Kind: grass/good ground spins up, swamp (MUD, WATER) drains, FLOWERS is a speed zone
SPIN_RATE = [3.0, -15.0, 3.0, 3.0, -20.0, 0.0, 0.0, 3.0, 3.0, 3.0, 12.0]
HAZARD_DPS = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 8.0, 15.0, 0.0]   # replaces the M2 value: +FLOWERS entry
WEAPON_DMG_MULT = 1.5            # weapons pack the bigger punch
WEAPON_CRIT_CHANCE = [0.15, 0.0, 0.0, 0.0, 0.0]   # by weapon_id; dagger only; crit = x CRIT_MULT
DMG_SIGMA = 0.20                 # damage multiplier ~ normal(1.0, DMG_SIGMA)
DMG_MULT_MIN = 0.4
DMG_MULT_MAX = 1.6
HIT_SPIN_COST_ATTACKER = 6.0     # RPM lost by the attacker per weapon hit
HIT_SPIN_COST_DEFENDER = 10.0    # RPM lost by the victim per weapon hit
RECOIL_FRAC = 0.5                # attacker velocity kick = -dir * kb * this
BODY_DMG = 3.0                   # body clash base damage (smaller than any weapon x WEAPON_DMG_MULT)
CLASH_MIN_VREL = 20.0            # approach speed (u/s) needed for an enemy clash
CLASH_KICK = 110.0               # extra separating speed at average spin == SPIN_REF  # M8 pace
CLASH_SPIN_COST = 4.0            # RPM lost by a marble when it deals body clash damage
BUMP_COOLDOWN = 0.35             # s between body-clash damage dealt by one marble
ALLY_MIN_VREL = 80.0             # approach speed needed for an ally spin boost (r2: was 30 -> 3000 boosts/s flood)
BOOST_COOLDOWN = 1.5             # s before a marble can receive another ally boost
ALLY_SPIN_GAIN = 0.05            # RPM gained per u/s of approach speed, each ally
ALLY_SPIN_GAIN_MAX = 8.0         # per bounce cap
```

### 15.2 BattleState additions

```gdscript
var bump_cd: PackedFloat32Array   # per marble, allocated to cap, spawn sets 0.0
var boost_cd: PackedFloat32Array  # per marble, allocated to cap, spawn sets 0.0
enum Event { HIT = 0, KILL = 1, LEVEL = 2, CAPTAIN_DEAD = 3, FLED = 4, BUMP = 5, BOOST = 6 }
```

Event shapes: `HIT` becomes `[HIT, attacker, victim, dmg]` (4 elements;
BattleLod still pushes 3 — consumers read `ev[3]` only when
`ev.size() > 3`). `BUMP = [BUMP, dealer, victim, dmg]`.
`BOOST = [BOOST, i, j, gain]` (both allies gained `gain`). KILL / LEVEL /
CAPTAIN_DEAD / FLED unchanged.

### 15.3 Damage (`scripts/sim/damage.gd`, `class_name Damage`, new)

```gdscript
static var force_mult: float = -1.0
static func roll(s: BattleState, crit_chance: float) -> float
    # force_mult >= 0.0 -> return force_mult (no rng draws at all).
    # m = clampf(s.rng.randfn(1.0, Tuning.DMG_SIGMA), DMG_MULT_MIN, DMG_MULT_MAX)
    # if crit_chance > 0.0 and s.rng.randf() < crit_chance: m *= Tuning.CRIT_MULT
    # (randf is drawn only when crit_chance > 0.0)
static func apply(s: BattleState, attacker: int, victim: int, dmg: float, event_type: int) -> void
    # hp[victim] -= dmg; xp[attacker] += XP_PER_HIT; push [event_type, attacker, victim, dmg]
    # then the §10.4 step 8 kill block (DEAD, hp 0, kills, XP_PER_KILL, faction_alive,
    # KILL event, morale hits, captain -> CAPTAIN_DEAD) and the §10.4 step 9 rank-up
    # loop on attacker, verbatim in behaviour and event order.
```

### 15.4 Weapons changes (replaces §10.4 steps 4-9)

After a candidate `j` is found:
4. `m = Damage.roll(s, WEAPON_CRIT_CHANCE[w])`. No fumble branch exists any more.
5. `dmg = WEAPON_DMG[w] * WEAPON_DMG_MULT * (spin[i] / SPIN_REF) * RANK_MULT[rank[i]] * m`; shield ×`SHIELD_DMG_MULT` exactly as before.
6. Knockback on `j` exactly as §10.4 step 6 (uses spins **before** step 7).
   Recoil: `v_i -= normalize(p_j - p_i) * kb * RECOIL_FRAC` (skipped when the distance is 0, like the knockback).
7. `spin[i] = max(RPM_MIN, spin[i] - HIT_SPIN_COST_ATTACKER)`;
   `spin[j] = max(RPM_MIN, spin[j] - HIT_SPIN_COST_DEFENDER)`.
8. `hit_cd[i] = WEAPON_COOLDOWN[w]`; `Damage.apply(s, i, j, dmg, Event.HIT)`.

`Weapons.force_roll` is deleted; tests use `Damage.force_mult`.

### 15.5 Collision changes (replaces the spin block of §7-step collision)

Per pair `i, j`: first, `if state[i] == DEAD or state[j] == DEAD: continue`
(a clash may kill mid-loop). Position correction unchanged. Compute
`vrel = (v_j - v_i) · n` **before** the restitution impulse; the
restitution impulse is unchanged. Then:

- **Enemy clash** (`faction_id` differ, `vrel < -CLASH_MIN_VREL`):
  `dv = CLASH_KICK * (spin[i] + spin[j]) / (2 * SPIN_REF)`;
  `v_i -= n * dv * wi / wsum`; `v_j += n * dv * wj / wsum`.
  Then for `(a, b)` in order `(i, j)`, `(j, i)`: if `state[a] == ENGAGE`,
  `bump_cd[a] == 0.0` and `state[b] != DEAD`:
  `dmg = BODY_DMG * (spin[a] / SPIN_REF) * RANK_MULT[rank[a]] * Damage.roll(s, 0.0)`;
  `spin[a] = max(RPM_MIN, spin[a] - CLASH_SPIN_COST)`; `bump_cd[a] = BUMP_COOLDOWN`;
  `Damage.apply(s, a, b, dmg, Event.BUMP)`.
- **Ally bounce** (same `faction_id`, `vrel < -ALLY_MIN_VREL`, and
  `boost_cd[i] == 0.0` **and** `boost_cd[j] == 0.0`):
  `gain = min(ALLY_SPIN_GAIN_MAX, ALLY_SPIN_GAIN * -vrel)`; both
  `spin = min(spin_cap, spin + gain)`; both `boost_cd = BOOST_COOLDOWN`;
  push `[BOOST, i, j, gain]`.
- Old spin transfer ("faster steals") and per-`dt` enemy contact cost are removed.

### 15.6 BattleSim changes

- Integrate, no terrain: friction = `pow(DRAG_KEEP_PER_S[0], dt)` (computed once per step). With terrain: `terrain.friction[c]` as before (TerrainGrid now fills it from drag, §15.7).
- Step 9 replaced, per live marble: `k = terrain.kind[terrain.cell_at(px, py)]` if terrain else `TerrainGrid.Kind.PLAIN`;
  `spin = clampf(spin + SPIN_RATE[k] * dt, RPM_MIN, spin_cap)`; `bump_cd = maxf(0.0, bump_cd - dt)`; `boost_cd = maxf(0.0, boost_cd - dt)`.
  Tower regen in step 6 unchanged.

### 15.7 TerrainGrid / TerrainGen / TerrainLayer

- `enum Kind { ..., SPIKE = 9, FLOWERS = 10 }`. Not solid.
- `friction_of(k) = pow(Tuning.DRAG_KEEP_PER_S[k], Tuning.DT)` for every kind.
- `TerrainGen.from_tile` / `demo` add FLOWERS patches (square, only over PLAIN cells, never inside the given spawn rects, all draws from `rng`):
  PLAINS 2×3x3, FOREST 1×3x3, HILLS 1×4x4, RIVER 2×3x3, TOWN 2×2x2, demo 1×3x3; RUIN, GRAVEYARD none.
- `TerrainLayer`: FLOWERS = rect `Color(0.62, 0.78, 0.42)` plus three pink dots `Color(0.95, 0.60, 0.80)`, radius 3, at cell offsets (0.25,0.3), (0.7,0.45), (0.4,0.75) × cell.

### 15.8 Renderer — spin glow and sparks

Bodies MultiMesh: `use_colors = true`; per instance **16 floats**
`[sx,0,0,tx, 0,sy,0,ty, g,0,0,1, cr,cg,cb,ca]`, `g = clampf(spin / spin_cap, 0, 1)`
(0 when DEAD or `spin_cap <= 0`); custom unchanged. Body shader: vertex
passes `COLOR.r` as `glow` and does not tint by it; fragment:
`dull = clamp((0.35 - glow) / 0.35, 0, 1)`; fill = `mix(fill, vec3(luma(fill) * 0.7), 0.6 * dull)`;
rim (`d > 0.8`) = `mix(fill, vec3(1), 0.1 + 0.6 * glow)` (replaces the fixed
rim lighten); rank ring and captain dot unchanged. Weapons/HpBars layouts unchanged.

Sparks: fourth `MultiMeshInstance2D` `Sparks` (added after HpBars), quad
2x2, `use_custom_data`, shader `shaders/spark.gdshader`, fixed
`instance_count = SPARK_POOL`. Render-only state on `BattleRenderer`
(consts on the class, not `Tuning`):

```gdscript
const SPARK_POOL := 256
var spark_x, spark_y, spark_r, spark_age, spark_life: PackedFloat32Array   # size SPARK_POOL; life 0 = inactive
var spark_kind: PackedInt32Array      # 0 hit, 1 bump, 2 boost
var spark_head: int = 0               # ring-buffer write index (oldest overwritten)
var _last_tick: int = -1
func ingest(s: BattleState) -> void
    # return if s.tick == _last_tick (paused views must not respawn sparks); _last_tick = s.tick.
    # for ev in s.events with ev[0] in {HIT, BUMP, BOOST} and ev[1] >= 0 and ev[2] >= 0:
    #   pos = midpoint of marbles ev[1], ev[2]; dmg = ev[3] if ev.size() > 3 else 8.0
    #   HIT:   r = clampf(6 + 1.2 * dmg, 6, 28), life 0.25, kind 0
    #   BUMP:  r = clampf(4 + 1.0 * dmg, 4, 14), life 0.25, kind 1
    #   BOOST: r = 6, life 0.18, kind 2
    #   write at spark_head (age 0), spark_head = (spark_head + 1) % SPARK_POOL
func advance(dt: float) -> void       # age += dt on active; age >= life -> life = 0
func build_spark_buffer() -> PackedFloat32Array
    # SPARK_POOL * 12 floats. Active: grow = 0.4 + 0.6 * age / life; sx = sy = r * grow; (tx, ty) = pos;
    # custom = (kind / 2.0, 1 - age / life, 0, 0). Inactive: all 12 floats 0.
```

`_process(dt)`: `advance(dt)` then `refresh()`; `refresh` also uploads the
spark buffer. Spark shader: `d = length(UV - 0.5) * 2`, discard `d > 1`;
kind 0 = warm ring `(1.0, 0.45, 0.05)` band `0.6..1.0`, 1.0 × fade; kind 1 =
dark grey ring `(0.2, 0.2, 0.2)` band `0.8..1.0`, 0.7 × fade; kind 2 = soft cyan disc `(0.2, 0.85, 1.0)`, 0.9 × fade;
alpha × `custom.g`. Callers: `BattleView._process` and `battle_scene.gd`
call `renderer.ingest(state)` once per frame before reading events. No
damage numbers.

### 15.9 Feel bench (`scripts/bench_bounce.gd`)

Headless `extends SceneTree`. Seeds 1..5: `BattleState.new(400, seed)`;
`TerrainGrid.setup(arena, TERRAIN_CELL)` + `TerrainGen.demo(g, s.rng)`;
`spawn_block(0, 150, Rect2(100,100,500,700), -1)`,
`spawn_block(1, 150, Rect2(1000,100,500,700), -1)`; `BattleSim.new(s)`,
`set_terrain(g)`; step `Tuning.DT` until `winner != -1` or
`T_MAX_BATTLE / DT` ticks. Every 30 ticks sample over live ENGAGE marbles:
mean speed, mean spin, `contact_frac` = share of live marbles with a live
enemy centre within `r_i + r_j + 1.0`. Count events by int type 0, 5, 6.
Prints per seed
`SEED=%d winner=%d duration=%.1f mean_speed=%.1f contact_frac=%.3f hits_per_s=%.1f bumps_per_s=%.1f boosts_per_s=%.1f mean_spin=%.1f`
then `SUMMARY` with the same keys averaged. Uses only APIs that exist at M6
(so it runs on the old code for a baseline).

## 16. M8 — battle instincts, pace, visible weapons

Leader (2026-09-13): keep M7. Marbles should want to attack but not shoot
across the field like bullets; prefer 1:1 targets and double up when it
makes sense; battles more chaotic, not two blobs smashing into one ball.
Weapons must be visible, and their hitboxes readable. §16 layers a
decision layer on §6/§10.6 forces; anything unmentioned stays as is.

### 16.1 Tuning (fiat, tunable)

```
SEPARATION_RANGE_MULT = 2.0      # changed from 1.2: allies keep ~1 marble-width gap
CRUISE_SPEED = 50.0              # self-propelled speed cap while not near the target  # M8 pace
CHARGE_SPEED = 160.0             # cap while within strike range of the target, or recoiling  # M8 pace
RETREAT_SPEED = 80.0             # cap while RETREAT  # M8 pace
STRIKE_RANGE_MULT = 6.0          # near target when centre distance < this * r_i
RECOIL_TIME = 0.45               # s of back-off after dealing a HIT or BUMP
K_RECOIL = 25.0                  # back-off acceleration (same units as K_ATTR)
OUTMATCH_RATIO = 1.25            # target power > this * own power -> want 2 attackers
CROWD_PENALTY = 8.0              # score cost (radius units) per attacker beyond wanted
FINISH_HP_FRAC = 0.35            # target below this hp fraction is a finish-off target
FINISH_BONUS = 4.0               # score reduction for finish-off targets
STICKY_BONUS = 2.0               # score reduction for keeping the current target
SPREAD_KEEP = 1.0                # advance keeps this share of lateral offset (line, not wedge)
```

Power of marble k: `power(k) = hp[k] * (spin[k] / SPIN_REF + 0.25) * RANK_MULT[rank[k]]`.

### 16.2 BattleState additions

```gdscript
var attackers: PackedInt32Array   # per marble: ENGAGE marbles whose target_id is this marble; rebuilt by Forces.retarget
var recoil_t: PackedFloat32Array  # per marble: seconds of back-off left; spawn 0.0
```

Both allocated to capacity like `hit_cd`.

### 16.3 Forces changes

**retarget(s, coarse, tick)** — at the very start, every tick: `attackers.fill(0)`;
for every live marble `i` with `state == ENGAGE`, `target_id[i] >= 0` and that
target not DEAD: `attackers[target_id[i]] += 1`. Then the staggered loop
as today, except for ENGAGE marbles on their retarget tick:

```
for each candidate enemy j (live, other faction, dist <= ENGAGE_RADIUS_MULT * r_i):
    att   = attackers[j] - (1 if target_id[i] == j else 0)
    want  = 2 if power(j) > OUTMATCH_RATIO * power(i) else 1
    if is_captain[j] == 1: want += 1
    score = dist / r_i + CROWD_PENALTY * max(0, att + 1 - want)
    if hp[j] < FINISH_HP_FRAC * hp_max[j]: score -= FINISH_BONUS
    if j == target_id[i]: score -= STICKY_BONUS
pick minimum score; ties -> lower j; none -> -1
```

When the pick differs from the old target, update counts immediately
(`attackers[old] -= 1` if old was a live counted target, `attackers[new] += 1`)
so later marbles in the same tick see it. RETREAT marbles keep the old
nearest-enemy rule and are never counted.

**accumulate(s, fine)** — per live marble, self-propelled terms are summed
into a local drive `(dx, dy)` instead of straight into `ax/ay`:

1. ENGAGE with a live target `t` (`d` = vector to t, `dist` = |d|):
   - `recoil_t[i] > 0`: drive `-= K_RECOIL * d / dist` (back off; no attraction).
   - else: drive `+= K_ATTR * aggression * morale * d / dist` (attraction as §6).
2. ENGAGE with no target: advance with spread. `g` = nearest live enemy faction
   by centroid (as §10.6), `cg`, `cf` = enemy / own centroid, `u = normalize(cg - cf)`,
   `w = (-u.y, u.x)`, `lat = dot(p_i - cf, w)`, `aim = cg + w * lat * SPREAD_KEEP`;
   drive `+= K_ADVANCE * normalize(aim - p_i)`. If `|cg - cf| < 1e-3`, fall back to
   §10.6 (aim = cg). No enemy faction alive: no term.
3. Cohesion (§6) only when `target_id[i] == -1`.
4. RETREAT: attraction sign flip (§6) and home pull (§6) go into the drive.
5. Cap: `cap = RETREAT_SPEED` if RETREAT; else `CHARGE_SPEED` if
   (`recoil_t[i] > 0` or (target live and `dist < STRIKE_RANGE_MULT * r_i`)); else
   `CRUISE_SPEED`. If `|drive| > 0`: `dir = drive / |drive|`,
   `v_par = vx[i]*dir.x + vy[i]*dir.y`; if `v_par >= cap` the drive is dropped,
   otherwise `ax += dx; ay += dy`.
6. Separation (§6, now range 2.0) is unchanged and never capped.

### 16.4 Damage / BattleSim

- `Damage.apply`: when `event_type` is `Event.HIT` or `Event.BUMP` and
  `attacker >= 0`: `recoil_t[attacker] = RECOIL_TIME` (set before the kill block).
- `BattleSim` step 9: `recoil_t = maxf(0.0, recoil_t - dt)` beside bump_cd/boost_cd.

### 16.5 Renderer — weapon silhouettes = hitboxes

Weapon instance per live marble, rotation `weapon_angle`:
`L = (WEAPON_REACH[w] + WEAPON_HIT_R[w]) * r` (centre to far edge of the hit
circle), `H = WEAPON_HIT_R[w] * r` (half thickness = hit radius). Transform:
x axis = `dir * L/2` (half length), y axis = `perp * H`, origin =
`p + dir * L/2`. Custom: `(w / 4.0, flash, head_u, aspect)` with
`head_u = WEAPON_REACH[w] / (WEAPON_REACH[w] + WEAPON_HIT_R[w])` (hit-circle
centre along the quad, 0 = marble centre, 1 = far end) and
`aspect = L / (2 * H)`. DEAD: all transform floats 0 except origin.

`static func build_weapon_buffer(s, flash := PackedFloat32Array()) -> PackedFloat32Array`
(12 floats per marble; `flash[i]` used when `i < flash.size()`, else 0).
Renderer keeps `weapon_flash: PackedFloat32Array` sized `s.n` (grown in
`attach`/`refresh`); `ingest` sets `weapon_flash[actor] = 0.15` for HIT
events; `advance` decays it by dt to 0; `refresh` passes it.

Weapon shader (`shaders/marble_weapon.gdshader`): UV.x along length (0 at the
marble centre), UV.y across. With `aspect` correcting circles, the **head
exactly fills the hit circle** (centre `head_u`, radius = the quad's half
height), so the visible head IS the hitbox. Shaft from marble rim
(`u = 1 / (REACH + HIT_R)` of length) to the head, thin dark
`(0.15, 0.12, 0.10)`. Head silhouette per id, metal `(0.80, 0.82, 0.86)`
with a dark outline, lerped to orange `(1.0, 0.55, 0.1)` by `flash`:
dagger = short leaf blade, sword = long blade from rim to tip with a point,
spear = diamond point on a thin pole, axe = crescent on one side,
shield = thick arc across the head circle (no shaft). Distinct silhouettes
are required; exact curves are the implementer's.

### 16.6 Bench additions (`bench_bounce.gd`)

Appended keys (same sampling, live ENGAGE marbles):
`march_speed` = mean speed of ENGAGE marbles with `target_id == -1`;
`crowd` = mean number of other live marbles within centre distance `3.0 * r_i`;
`mean_attackers` = over live marbles targeted by >= 1 ENGAGE marble, mean count;
`pile_frac` = share of those with more than 2 attackers (counts computed from
`target_id`, not `attackers`). Uses only pre-M8 APIs.

## 17. M9 — free companies, gold, heroes, aging, settling, follow

Leader intent (2026-09-13, `docs/future-state-and-ideas/hero-progression-and-settling-down.md`):
random starting towns and free companies; stacks carry gold and recruit at towns;
soldiers rise to named heroes and break away loyal or as a new free company;
captains age, then found towns (rich/big) or retire; camera can follow a hero's
legacy. Leader picks: faction cap raised with slot recycling; per-stack purse;
hybrid recruiting (slow passive trickle + active RESTOCK trips); weighted defect
roll; ~15 min career; rich/big founds else retires; founded-town allegiance by
context; follow legacy (heir, then offshoot, then free camera).

All numbers below are `fiat` (tunable). Every random draw goes through `w.rng`
unless stated; draw order is part of the spec (determinism).

### 17.1 Tuning (append to `Tuning`; edits marked)

```
# edits
const MAX_FACTIONS_WORLD := 64          # was 16
const TOWN_RECRUIT_RATE := 0.05         # was 0.10 (passive trickle slowed)
const SAVE_VERSION := 2                 # was 1
# FACTION_COLORS: append 8 entries (16 total):
#   Color(0.95,0.4,0.6), Color(0.4,0.25,0.1), Color(0.6,0.9,0.3), Color(0.1,0.3,0.4),
#   Color(0.95,0.95,0.6), Color(0.5,0.1,0.2), Color(0.7,0.7,1.0), Color(0.3,0.5,0.2)
# population
const KINGDOMS_MIN := 2
const KINGDOMS_MAX := 5
const COMPANIES_MIN := 3
const COMPANIES_MAX := 8
const TOWNS_MIN := 16
const TOWNS_MAX := 30
const COMPANY_UNITS_MIN := 12
const COMPANY_UNITS_MAX := 30
const COMPANY_SPAWN_MIN_DIST := 4
const COMPANY_START_GOLD := 80.0
const KINGDOM_STACK_GOLD := 40.0
const START_AGE_SPREAD := 0.5
# economy
const TOWN_TAX_PER_POP := 0.002
const TOWN_GOLD_MAX := 500.0
const RECRUIT_COST := 2.0
const PRICE_MULT_OWN := 1.0
const PRICE_MULT_ALLY := 1.25
const PRICE_MULT_NEUTRAL := 1.5
const HEAL_COST := 0.2
const LOOT_FRAC := 0.5
const BOUNTY_PER_KILL := 0.5
const RAID_GOLD_FRAC := 1.0
const RESTOCK_WEIGHT := 4.0
const RESTOCK_BELOW := 0.4
const RESTOCK_MIN_BUY := 5
const POOR_GOLD := 20.0
const POOR_RAID_BONUS := 2.0
# heroes
const HERO_KILLS := 25
const BREAKAWAY_MIN_STACK := 40
const BREAKAWAY_DELAY := 30.0
const BREAKAWAY_RATE := 0.02
const FOLLOW_FRAC := 0.15
const FOLLOW_PER_KILL := 0.5
const BREAKAWAY_MIN_FOLLOWERS := 8
const DEFECT_BASE := 0.15
const DEFECT_AMBITION := 0.6
const DEFECT_COHESION := 0.5
const DEFECT_PIETY := 0.3
const DEFECT_OUTSHINE := 0.2
const DEFECT_RELATION := -0.4
# aging / settling
const HERO_LIFESPAN := 900.0
const FOUND_GRACE := 120.0
const FOUND_SCORE := 200.0
const FOUND_UNIT_VALUE := 1.0
const FOUND_SEARCH := 8
const FOUND_MIN_SPACING := 4
const FOUND_IDLE := 30.0
```

`NameGen.hero_epithet(rng) -> String`: one draw, `LEGEND_ADJECTIVES[rng.randi_range(0, size-1)]`.

Every `f % 8` colour index becomes `f % Tuning.FACTION_COLORS.size()`.

### 17.2 Fields

`Units` (all sized `capacity`, reset by `Units.add`):
`enum Fate { ACTIVE = 0, LORD = 1, RETIRED = 2 }`;
`hero: PackedByteArray` (0), `career_start: PackedFloat32Array` (0.0, world time the
unit became hero or captain), `ambition: PackedFloat32Array` (0.0), `mentor:
PackedInt32Array` (-1, captain of the stack a hero broke away from), `fate:
PackedByteArray` (ACTIVE). A LORD/RETIRED unit has `alive == 1`, `stack == -1`,
`is_captain == 0`; nothing may treat "alive" as "has a stack".

`Stacks`: `gold: PackedFloat32Array` (0.0; `add` sets 0.0). `Goal` appends
`RESTOCK = 7, FOUND = 8`.

`World`: `town_gold: PackedFloat32Array` (0.0), `town_lord: PackedInt32Array` (-1) —
appended by `add_town`, grown by `sync_town_arrays`, reset in `_init`/`setup_blank`/`create`.
`history: Dictionary` — int counters, keys `"promotions", "breakaways", "defections",
"foundings", "retirements", "restocks"`, all 0 at `_init`/`setup_blank`/`create`.
Helper `World.bump(key: String)`: `history[key] = int(history.get(key, 0)) + 1`.

`BattleInstance`: `slayers: PackedInt32Array` — unit ids that killed a captain or hero
this battle (empty at `_init`).

`SaveGame`: units dict gains `hero, career_start, ambition, mentor, fate`; stacks dict
gains `gold`; towns dict gains `town_gold, town_lord`; logs dict gains `history`.

### 17.3 Economy (`scripts/world/economy.gd`, `class_name Economy`, static)

- `accrue(w, dt)`: `w.sync_town_arrays()`; for each town with `town_state == 0`:
  `town_gold[t] = minf(TOWN_GOLD_MAX, town_gold[t] + TOWN_TAX_PER_POP * town_pop[t] * dt)`.
- `price(w, f, t) -> float`: owner `== f` → `RECRUIT_COST*PRICE_MULT_OWN`; owner `== -1` →
  `*PRICE_MULT_NEUTRAL`; `w.allied(f, owner)` → `*PRICE_MULT_ALLY`; else `-1.0`.
- `_buy_floor() = RECRUIT_COST * PRICE_MULT_NEUTRAL * RESTOCK_MIN_BUY` (15.0);
  `_tax_floor() = RECRUIT_COST * RESTOCK_MIN_BUY` (10.0).
- `wants_restock(w, s) -> bool`: `wounded` = alive units of `s` with `hp_frac < 0.5`.
  True when (`count[s] < RESTOCK_BELOW * STACK_CAP` and (`gold[s] >= _buy_floor()` or some
  town has owner `== f`, state 0, `town_gold >= _tax_floor()`)) or (`wounded >= maxi(1,
  count[s] / 4)` and `gold[s] >= HEAL_COST * wounded`).
- `restock_target(w, s) -> int`: candidates = towns with state 0 and `price > 0` and
  `town_pop >= 1.0`; if `gold[s] < _buy_floor()` the candidates narrow to owner `== f` with
  `town_gold >= _tax_floor()`. Nearest by world distance stack→town centre (strict `<`,
  so lowest id wins ties). None → -1.
- `goal_bonus(w, s, weights) -> PackedFloat32Array`: copy of the 7 input weights; if
  `gold[s] < POOR_GOLD`: `[RAID] += POOR_RAID_BONUS`, `[HUNT_WEAK] += POOR_RAID_BONUS * 0.5`;
  append `RESTOCK_WEIGHT if wants_restock else 0.0` (index 7) and `0.0` (index 8, FOUND is
  never drawn). Returns size 9.
- `restock(w, s, t) -> String`: `f = faction[s]`, `p = price(w, f, t)`; if `p < 0` or state
  != 0 → return `""`. (1) owner `== f`: `gold[s] += town_gold[t]; town_gold[t] = 0`.
  (2) heal: alive units of `s` in ascending id with `hp_frac < 1.0`: if `gold[s] >= HEAL_COST`
  → pay, `hp_frac = 1.0`, `healed += 1`; else stop. (3) `n = mini(int(gold[s] / p),
  mini(int(town_pop[t]), STACK_CAP - count[s]))`; add up to `n` units
  `units.add(f, 0, Kingdoms.recruit_weapon(w, f, w.rng), false, s)` (stop at -1); `added`
  = successful adds; `count[s] += added; gold[s] -= added * p; town_pop[t] -= added`; if
  owner != f: `town_gold[t] = minf(TOWN_GOLD_MAX, town_gold[t] + added * p)`. (4) if
  `added + healed > 0`: `w.bump("restocks")`. Return `"%s restocks at town %d: +%d recruits, %d healed" % [names[s], t, added, healed]`.
- `loot(w, winners: Array, losers: Array, kills_by_stack: Dictionary)`: if `winners` has no
  stack with `alive == 1` → return, nothing changes. `pool = Σ_losers gold*LOOT_FRAC`, each
  loser `gold -= gold*LOOT_FRAC`. Alive winners: `total = Σ count`; share `= pool * count /
  total` (if `total == 0`: `pool / n_alive_winners`); plus `BOUNTY_PER_KILL *
  kills_by_stack.get(stack, 0)`.
- `raid_gold(w, s, t) -> float`: `g = town_gold[t] * RAID_GOLD_FRAC`; `town_gold[t] -= g;
  gold[s] += g`; return `g`.

### 17.4 Heroes (`scripts/world/heroes.gd`, `class_name Heroes`, static)

- `check_promote(w, u, slew_leader: bool) -> bool`: false if `alive == 0`, `hero == 1` or
  `is_captain == 1`. If `kills >= HERO_KILLS` or `rank >= LEGEND_RANK` or `slew_leader` →
  `promote(w, u)`, true. Else false.
- `promote(w, u)`: draws in order `ambition[u] = w.rng.randf()`, `base =
  NameGen.captain_name_base(w.rng)`, `adj = NameGen.hero_epithet(w.rng)`. `hero = 1`,
  `career_start = w.time`, `dynasty[u] = [base, 1]`, `names[u] = "%s the %s" % [base, adj]`.
  Log `"%s rises from the ranks of %s" % [names[u], stack name or "the wilds" if stack < 0]`;
  `w.bump("promotions")`.
- `defect_chance(w, u) -> float`: `f = faction[u]`, `cap = captain_unit[stack[u]]`;
  `outshine = 1.0 if cap >= 0 and kills[u] > kills[cap] else 0.0`;
  `clampf(DEFECT_BASE + DEFECT_AMBITION*ambition - DEFECT_COHESION*(ktrait(f,4)-0.5)
  - DEFECT_PIETY*(ktrait(f,3)-0.5) + DEFECT_OUTSHINE*outshine, 0.05, 0.95)`.
- `check_breakaway(w)` (once per world second): `n0 = units.n`; for `u` in `0..n0-1`
  ascending, eligible when `alive == 1, hero == 1, is_captain == 0, fate == ACTIVE`,
  `s = stack[u] >= 0`, `stacks.alive[s] == 1`, `state[s]` IDLE or MOVING,
  `count[s] >= BREAKAWAY_MIN_STACK`, `w.time - career_start[u] >= BREAKAWAY_DELAY`
  (evaluated at that moment, so earlier breakaways this pass count). Eligible →
  `if w.rng.randf() < BREAKAWAY_RATE: breakaway(w, u)`.
- `breakaway(w, u, force_defect := -1) -> int` (new stack id, or -1 with no change and no
  draws when `stacks.n >= stacks.cap`). `force_defect` 0/1 overrides the roll's result in
  step 4 (the roll is still drawn); -1 uses it. Only tests pass it.
  1. `s = stack[u]`, `f = faction[s]`, `c = count[s]`, `parent_cap = captain_unit[s]`.
  2. `want = mini(maxi(int(round(c*FOLLOW_FRAC + kills[u]*FOLLOW_PER_KILL)), BREAKAWAY_MIN_FOLLOWERS), c / 2)`.
  3. pool = alive units of `s`, `is_captain == 0`, `hero == 0`, ascending id. Partial
     Fisher–Yates: for `k` in `0..mini(want, pool.size())-1`: `j = w.rng.randi_range(k, pool.size()-1)`, swap `k,j`. Followers = first `mini(want, pool.size())`.
  4. `defect = w.rng.randf() < defect_chance(w, u)`. `g = f`; if defect: `g2 =
     Kingdoms.new_faction(w, f)`; if `g2 != -1`: `g = g2`, `w.add_relation(f, g, DEFECT_RELATION)`.
     (`defect` with `g2 == -1` behaves as loyal.)
  5. Tile: first of `World._passable_neighbours(w.map, stack_tile(s))`, else `stack_tile(s)`.
     `ns = stacks.add(g, centre.x, centre.y, NameGen.stack_name(w.rng))`.
  6. `u` and followers: `stack = ns`, `faction = g`. `is_captain[u] = 1`, `mentor[u] =
     parent_cap`, `captain_unit[ns] = u`.
  7. `moved = followers.size() + 1`; `share = gold[s] * moved / c`; `gold[s] -= share;
     gold[ns] += share`. `stacks.recount(units)`.
  8. `immunity[ns] = RETREAT_IMMUNITY`; if `g != f` also `immunity[s] = RETREAT_IMMUNITY`.
  9. Loyal: log `"%s leaves %s with %d men" % [names[u], stacks.names[s], followers.size()]`,
     `bump("breakaways")`. Defected: log `"%s breaks from %s, founding the free company %s"
     % [names[u], faction_names[f], faction_names[g]]`, `bump("breakaways")` and `bump("defections")`.
- `successor(w, u, last_stack) -> int` (follow legacy):
  1. `u >= 0`, `alive == 1`, `fate == ACTIVE`, `stack >= 0` → `u`.
  2. `0 <= last_stack < stacks.n`, `stacks.alive == 1`, `c = captain_unit[last_stack]`,
     `c >= 0`, `c != u`, `alive[c] == 1` → `c`.
  3. alive, ACTIVE, `stack >= 0`, `mentor == u`: most kills, strict `>` ascending id → that unit.
  4. `-1`.

### 17.5 Settling (`scripts/world/settling.gd`, `class_name Settling`, static) + Lineage

Lineage edits: `make_captain` also sets `career_start[u] = w.time`.
`_succeed(w, stack, dead)` becomes `succeed(w, stack, old_captain, verb := "fell")`
(keep `_succeed` as a one-line wrapper); log `"%s %s %s; %s rises" % [name,
numeral(old), verb, names[heir]]`; heir also gets `career_start = w.time`.

- `found_site(w, s) -> Vector2i`: `o = stack_tile(s)`; for `r` in `0..FOUND_SEARCH`: tiles
  with Chebyshev distance exactly `r` from `o`, scanned `ty` ascending then `tx` ascending;
  first tile that is in bounds, `kind == PLAINS`, and Chebyshev `>= FOUND_MIN_SPACING` from
  every entry of `w.towns`. None → `Vector2i(-1, -1)`.
- `check_aging(w)` (once per world second), `n0 = stacks.n`, `s` ascending: skip unless
  `stacks.alive == 1`, `state != BATTLE`, `cap = captain_unit >= 0`, `units.alive[cap] == 1`.
  `age = w.time - career_start[cap]`.
  1. `goal == FOUND`: if `age >= HERO_LIFESPAN + FOUND_GRACE` → `retire`. Else if `state ==
     IDLE`: at `(goal_tx, goal_ty)` → `found_town`; else re-path there (`Pathing.find`;
     empty → `retire`; else `path, path_i = 0, state = MOVING`). Continue.
  2. `age < HERO_LIFESPAN` → continue.
  3. `score = gold + count * FOUND_UNIT_VALUE`. If `score >= FOUND_SCORE` and `site =
     found_site != (-1,-1)`: at site → `found_town(w, s, site)`; else path non-empty →
     `goal = FOUND, goal_tx/ty = site, path, path_i = 0, state = MOVING`. Otherwise → `retire(w, s)`.
- `found_town(w, s, tile) -> int`: `f = faction[s]`, `cap = captain_unit[s]`. Guard: if
  `w.town_at(tile) != -1` or any town is within Chebyshev `< FOUND_MIN_SPACING` → return -1,
  no change. `cap < 0` → steps 4–5 use the stack name in the log and skip lord/succession.
  1. Owner: if any `town_owner == f` → `f`. Else `o = map.owner[idx(tile)]`; if `o >= 0,
     o != f, w.allied(f, o)` → `o`; else `f`.
  2. `t = w.add_town(tile, owner)`; `town_gold[t] = minf(TOWN_GOLD_MAX, gold[s])`; `gold[s] = 0`;
     `town_lord[t] = cap`.
  3. `owner != f`: `stacks.faction[s] = owner` and every unit with `stack == s` → `faction = owner`.
  4. Log `"%s settles at (%d,%d), founding a town of %s" % [names[cap], x, y,
     faction_names[owner]]`; `bump("foundings")`.
  5. `fate[cap] = LORD; is_captain[cap] = 0; units.stack[cap] = -1`;
     `Lineage.succeed(w, s, cap, "settles")`.
  6. `goal = DEFEND, state = IDLE, idle_timer = FOUND_IDLE, path = empty, path_i = 0`;
     `stacks.recount(units)`; `Kingdoms.on_event(w, "settle", owner)`;
     `w.recompute_borders()`; `w.pathing.refresh(w.map)`. Return `t`.
- `retire(w, s)`: `cap < 0` → return. Log `"%s retires" % names[cap]`; `bump("retirements")`;
  `fate = RETIRED, is_captain = 0, stack = -1`; `Lineage.succeed(w, s, cap, "retires")`;
  `goal = IDLE_HEAL, state = IDLE`; `stacks.recount(units)`.

### 17.6 Kingdoms: slot recycling

- `has_free_slot(w) -> bool`: some `f < faction_count` with `faction_alive == 0`, or
  `faction_count < MAX_FACTIONS_WORLD`.
- `new_faction(w, from_f) -> int`: `g` = lowest `f < faction_count` with `faction_alive == 0`;
  else `faction_count` (then `faction_count += 1`) if `< MAX_FACTIONS_WORLD`; else return -1
  with no change and no draws. Reset `g`: `faction_alive = 1`, `faction_color = g %
  FACTION_COLORS.size()`, name drawn exactly as before (grow `faction_names` to `g+1` with
  `""` if short, then assign index `g`), ktraits copied from `from_f` with cohesion
  `KTRAIT_INIT`, `relations[g*M+b] = relations[b*M+g] = 0.0` for all `b`, `split_cooldown[g]
  = 0.0`, plinko row/bias/order as before (same draw order: name, then shuffle).
- `check_split`: replace the `faction_count >= MAX_FACTIONS_WORLD` guard with `not has_free_slot(w)`.
- Loops over faction slots in `Kingdoms.tick`, `goal_weights` and
  `WorldSim._most_hated_faction` run to `w.faction_count`, not `MAX_FACTIONS_WORLD`
  (slots above `faction_count` are never used; indexing still uses `MAX_FACTIONS_WORLD`).

### 17.7 World.create population

`WorldGen.generate(m, town_count := -1)`: `-1` keeps the old formula; else places `town_count`.

`World.create(seed)`:
1. `map` as before. `pop = RandomNumberGenerator.new(); pop.seed = seed + 2`;
   `kingdoms = pop.randi_range(KINGDOMS_MIN, KINGDOMS_MAX)`; `companies =
   pop.randi_range(COMPANIES_MIN, COMPANIES_MAX)`; `n_towns = pop.randi_range(maxi(TOWNS_MIN,
   kingdoms), TOWNS_MAX)`; `companies = mini(companies, MAX_FACTIONS_WORLD - kingdoms)`.
2. `town_tiles = WorldGen.generate(map, n_towns)`; `kingdoms = mini(kingdoms, town_tiles.size())`.
   Towns `ti < kingdoms` owned by `ti`, rest neutral. `faction_count = kingdoms + companies`.
3. `w.rng` seed+1. Kingdom stacks exactly as before for `fi < kingdoms`; each stack `gold =
   KINGDOM_STACK_GOLD`; after `make_captain`: `career_start[cap] = -w.rng.randf() *
   HERO_LIFESPAN * START_AGE_SPREAD`.
4. Companies `ci` ascending, `f = kingdoms + ci`: up to 200 tries of `tx =
   w.rng.randi_range(0, cols-1)`, `ty = w.rng.randi_range(0, rows-1)`; accept when `kind ==
   PLAINS`, Chebyshev `>= COMPANY_SPAWN_MIN_DIST` from every town, and `w.pathing.find(tile,
   town_tiles[0]).size() > 0`. No accept → first `_passable_neighbours` of
   `town_tiles[ci % town_tiles.size()]`, else that town tile. Stack named
   `NameGen.stack_name`; `randi_range(COMPANY_UNITS_MIN, COMPANY_UNITS_MAX)` rank-0 units,
   weapon `randi_range(0, 4)`; captain rank 1 sword via `make_captain(captain_name_base)`;
   then `hero[cap] = 1`, `ambition[cap] = w.rng.randf()`, `career_start[cap] =
   -w.rng.randf() * HERO_LIFESPAN * START_AGE_SPREAD`; `gold = COMPANY_START_GOLD`; `count` set.
   (`w.pathing` must exist before this step.)
5. Plinko profiles, names, alive flags, colours loop to `faction_count` (`% FACTION_COLORS.size()`).

### 17.8 Hookup

`WorldSim.step_world`: after `TownSim.step`: `Economy.accrue(w, dt)`. In the per-second
block after `check_death`: `Heroes.check_breakaway(w)`, then `Settling.check_aging(w)`.
Goal-pick loop skips stacks with `goal == FOUND`.
`pick_goal`: `weights = Economy.goal_bonus(w, i, Kingdoms.goal_weights(w, fi))`.
`set_goal`: `RESTOCK` → `t = Economy.restock_target`; -1 → false; if the stack already stands
on town `t`'s tile → `Economy.restock(w, i, t)`, `goal = IDLE_HEAL`, `state = IDLE`, return
true; else path as other goals. `FOUND` → false.
`move_stacks` path end (both places): after `state = IDLE`: `PILGRIMAGE` → pilgrim event (as
now); `RESTOCK` → `t = w.town_at(tile)`, `t != -1` → `Economy.restock`, then `goal = IDLE_HEAL`;
`FOUND` → tile `== (goal_tx, goal_ty)` → `Settling.found_town(w, i, tile)`.
`step_battles` event loop: `KILL` with `ev[1] != -1`: `vu = unit_of[ev[2]]`; if
`is_captain[vu] == 1 or hero[vu] == 1` → `inst.slayers.append(unit_of[ev[1]])`.

`BattleBridge.finish`: in the copy-back loop, before overwriting kills,
`kills_gain[units.stack[u]] += state.kills[i] - units.kills[u]`; `Lineage.check_legend` is no
longer called. After `stacks.recount`: for marbles ascending, `u` alive →
`Heroes.check_promote(world, u, inst.slayers.has(u))`. After the winner/loser loop, when
`winner_side != -1`: `Economy.loot(world, winner_stacks, loser_stacks, kills_gain)`.
`_process_rebirth`: founder path only when `new_faction` returns `!= -1` (call it only after
the founder and ruin checks pass); `-1` → mercenary path.

`PlinkoOutcomes._raid` / `_raze`: once a target town is chosen, `Economy.raid_gold(w, stack,
t)` before its pop/state changes. Log lines unchanged.

### 17.9 Follow + panels (scene)

`world_scene.gd`: `followed_unit := -1`, `followed_stack := -1`. Key `F`: if following →
stop; else if the spectate panel shows stack `s` with `captain_unit >= 0` → follow it.
Each `_process` after stepping: `nu = Heroes.successor(world, followed_unit, followed_stack)`;
`-1` → `world.log_event("The tale of %s ends" % name)`, stop; `nu != followed_unit` →
`world.log_event("The tale passes to %s" % names[nu])`; `followed_unit = nu`,
`followed_stack = units.stack[nu]`, `camera.position` = that stack's position, spectate
panel shows that stack. Label (top centre) `"Following: <name> — <stack label>"`, hidden
when not following. Spectate panel adds `Gold`, captain `Age <s>/<HERO_LIFESPAN>`, hero
count, and `Free company` when the faction owns no town. Map layer draws a gold ring on
towns with `town_lord >= 0`. `terrain_layer` colour index uses `% FACTION_COLORS.size()`.

## 18. Battle aftermath (watched battles only)

Purely cosmetic; changes no world state and no determinism.

- `BattleSim.integrate(s, dt, apply_hazards: bool)`: §5 step 6 (forces →
  velocity, slope/friction, speed clamp, move, walls, obstacles) extracted
  from `step`; hazard damage runs only when `apply_hazards`. `step` calls it
  with `true` (behaviour unchanged); tower ownership/aura stays in `step`.
- `BattleAftermath` (`scripts/render/battle_aftermath.gd`, RefCounted):
  `_init(state, sim, winner_side)` (`winner_side` = `BattleSim.winner`,
  `< 0` stalemate), `step(dt)`, `static banner_lines(inst, world, side) ->
  [title, subtitle]`. Roles: celebrant = `faction_id == winner`; fleer = not
  celebrant and (winner >= 0 or state RETREAT); stalemate ENGAGE marbles
  idle. At init every live fleer, in index order, takes up to
  `CHASERS_PER_FLEER` nearest unassigned non-captain celebrants within
  `CHASE_RANGE`. Per step: pin `bump_cd = NO_DAMAGE_CD`; chasers drive at
  their fleer until `CHASE_TIME` or it is gone; other celebrants (not the
  captain) orbit the live winning captain, else the celebrants' start
  centroid, on a ring radius fixed at first orbit tick to
  `clamp(dist, RING_MIN_MULT * rally radius, RING_BASE + RING_PER_SQRT *
  sqrt(celebrants))`; celebrants twirl `weapon_angle` and pulse `spin`
  (glow only); fleers drive toward `HOME_DIR` and become `DEAD` + `fled` at
  the home edge. Then `sim.integrate(s, dt, false)`, `sim.fine.build`,
  `Collision.resolve`, `boost_cd` decay, `tick += 1`. `Weapons.tick` never
  runs. Drives use the Forces step 5 cap pattern. Constants live in the
  class, not `Tuning`.
- `BattleView`: `_process` starts the aftermath when
  `not world.battles.has(inst)`; steps it at `Tuning.DT` on real frame time
  (≤ 4 steps/frame, skipped while `paused`, mirrored from `world_scene`
  each frame); shows a top banner (title in the winner's palette colour,
  winning stack names, close hint). `open`/`close` end any aftermath.
  Captain labels hide once the captain is `DEAD`.

## 19. Rally and contingents

Stacks merge by choice. Tuning `RALLY_*` (see docs/systems/06).

- Fields: `Units.leader` (-1 = the stack's own men, else unit id of the hero
  whose contingent the unit is), `Units.pledge_t` (world time before which a
  rallied hero will not break away); `Stacks.rally_target` (-1 / host),
  `Stacks.rally_cd` (seconds, decremented in `step_world`). `Stacks.Goal.RALLY
  = 9`. All four saved; older saves load with defaults (`SAVE_VERSION`
  unchanged).
- `Rally` (`scripts/world/rally.gd`, static):
  - `desire(w, s, host, threat) -> 0..1`: leaderless -> 1; else
    `W_WEAK*(1 - count/WEAK_COUNT) + W_THREAT*threat + W_RENOWN*clamp(gap/RENOWN_SCALE)
    + W_COHESION*(coh - 0.5) - W_AMBITION*ambition - W_AGGR*(aggr - 0.5)
    - W_GOLD*clamp(gold/GOLD_SCALE)`, clamped; renown = kills + 10*rank.
  - `threat(w, s)`: non-allied enemy men within `RALLY_THREAT_TILES` /
    own count / `RALLY_THREAT_RATIO`, clamped 0..1.
  - `can_host(w, host, s)`: alive, same faction, live captain, IDLE/MOVING,
    goal != RALLY, `count sum <= STACK_CAP`, strictly bigger (tie: lower id).
  - `best_host(w, s)`: `-1` on `rally_cd > 0`; else highest desire among
    hosts within `RALLY_RANGE` (Chebyshev), ties nearest then lowest id.
  - `goal_weight(w, s)`: appended to `pick_goal` weights at index RALLY: 0
    without host; leaderless `RALLY_LEADERLESS_WEIGHT`; else
    `RALLY_GOAL_WEIGHT * desire` if `desire >= RALLY_MIN_DESIRE`.
  - `host_accepts(w, host, s)`: leaderless -> true (no draw); else one
    `w.rng.randf() < clamp(BASE + trait bonus - rival penalty)`; TYRANT
    +TRAIT, CAUTIOUS +TRAIT*(1 - count/STACK_CAP), BUILDER
    +TRAIT*clamp(joiner gold/GOLD_SCALE), RIVAL when joiner renown > host's.
  - `merge(w, host, s)`: alive units move; led joiner's men with leader -1
    get leader = its captain; captain -> `is_captain 0, hero 1, leader -1,
    pledge_t = time + PLEDGE_TIME`, keeps name/dynasty; leaderless joiner's
    men get leader -1. Gold moves, `reinforce.erase(s)`, recount, `s` dies.
    Logs "<captain> brings <stack> (<n>) under <host>" / "<stack> (<n>)
    folds into <host>".
  - `arrive(w, s)`: clears target, goal IDLE_HEAL; host still hostable and
    within 1 tile -> accept ? merge : `rally_cd = RALLY_COOLDOWN` + log
    "<host> turns away <stack>".
- `WorldSim.set_goal(RALLY)`: host = `best_host`; within 1 tile -> `arrive`
  now; else path to the host's tile. `_on_arrive(RALLY)` -> `Rally.arrive`.
- `Heroes`: `check_breakaway` skips `time < pledge_t`. `breakaway` takes the
  hero's contingent (alive units of the stack with `leader == u`) as
  followers with no rng draws when it has any, else the old random draw;
  movers get `leader = -1`.

## 20. Dissent and allegiance (step 1: values, bond, readings)

Heroes, captains, lords and towns hold values on the same 5 axes as
`World.ktraits` (k: 0 aggression, 1 diplomacy, 2 greed, 3 piety, 4 cohesion)
and can disagree with their kingdom. This step records values and computes
readings (disaffection, power, tension); nothing acts on them yet. No outcome
is a target — a realm that stays united is as valid as one that breaks.

- **Fields:**
  - `Units.vals` (`PackedFloat32Array`, size units.capacity * 5, index `u*5+k`):
    value on axis k for unit u; 0.0 until seeded.
  - `Units.bond` (`PackedFloat32Array`, size units.capacity): loyalty to own
    kingdom, 0..1, clamped; 0.0 until seeded.
  - `World.town_vals` (`PackedFloat32Array`, size towns.size() * 5, index
    `t*5+k`): value on axis k for town t.
  - Save dict: `"vals"` and `"bond"` under Units; `"town_vals"` under World.

- **Dissent (`scripts/world/dissent.gd`, `class_name Dissent`, all static):**
  - `enum Drive { GLORY = 0, WEALTH = 2, FAITH = 3, LAND = 4 }`: names the
    value axes a hero's drives live on (diplomacy, axis 1, has no drive).
    Informational.
  - `event_deltas(kind: String) -> PackedFloat32Array` (5 entries): per-event
    value changes: "win" → `[KT_WIN_AGGR, 0, 0, 0, 0]`; "raze" →
    `[0, 0, KT_RAZE_GREED, KT_RAZE_PIETY, 0]`; "settle" →
    `[0, 0, 0, 0, KT_SETTLE_COH]`; "retreat" → `[KT_RETREAT_AGGR, 0, 0, 0, KT_RETREAT_COH]`;
    "pilgrim" → `[0, 0, 0, KT_PILGRIM_PIETY, 0]`; else `[0, 0, 0, 0, 0]`.
  - `kingdom_vals(w, f) -> PackedFloat32Array`: `w.ktraits[f*5+k]` for each k;
    invalid f → five `KTRAIT_INIT`.
  - `unit_vals(w, u) -> PackedFloat32Array`: `w.units.vals[u*5+k]` for each k.
  - `town_vals(w, t) -> PackedFloat32Array`: `w.town_vals[t*5+k]` for each k.
  - `distance(a, b) -> float`: mean absolute difference = `(Σ|a[k]−b[k]|) / 5`.
  - `noise(w, u) -> PackedFloat32Array`: local `RandomNumberGenerator` seeded
    by `hash([w.rng.state if w.rng else 0, u, w.units.gen[u]])`, five values
    `r.randf() * 2.0 - 1.0`. Never touches `w.rng` beyond reading `.state`.
  - `seed_unit(w, u, src)`: sets `vals[u*5+k] = clamp(src[k] + VALUE_SEED_SPREAD * noise[k], 0, 1)`
    for each k; sets `bond[u] = BOND_INIT`.
  - `member(w, u) -> bool`: alive and (lord or (active and (hero or captain))).
  - `on_stack_event(w, kind, stack)`: for every hero/captain u in stack, alive:
    `vals[u*5+k] += event_deltas(kind)[k] * HERO_EVENT_SCALE`, clamped; "win"
    → `bond[u] += BOND_WIN`, "retreat" → `bond[u] -= BOND_LOSS`.
  - `tick(w)`: called once per world second. Every active hero/captain:
    `bond[u]` drifts toward 1.0 by `BOND_SERVICE_RATE`. Every owned town t:
    if lord u exists and alive, `town_vals[t*5+k]` drifts toward
    `units.vals[u*5+k]` by `TOWN_LORD_PULL`; then toward kingdom owner's vals
    by `TOWN_REALM_PULL`.
  - `unit_disaffection(w, u) -> float`: `distance(unit_vals, kingdom_vals) - BOND_WEIGHT * bond`,
    may be negative.
  - `town_disaffection(w, t) -> float`: `distance(town_vals, kingdom_vals)`;
    0.0 if unowned.
  - `unit_power(w, u) -> float`: lord → `POWER_LORD`; captain with stack →
    `count[stack]`; else `POWER_HERO`.
  - `town_power(w, t) -> float`: `town_pop[t]`.
  - `tension(w, f) -> float`: population-weighted average of positive
    disaffection: `Σ(power * max(0, disaffection)) / Σpower`, per members and
    towns of faction f; 0.0 if denominator zero.

- **Seeding sites:**
  - `Lineage.make_captain`: last line, `Dissent.seed_unit` from kingdom values.
  - `Lineage.succeed`: if heir is not already a hero, `Dissent.seed_unit` from
    old captain's values.
  - `Heroes.promote`: last line, `Dissent.seed_unit` from kingdom values.
  - `Settling.found_town`: after lord set, direct copy of captain's values into
    town `vals` (for k 0..4: `town_vals[t*5+k] = units.vals[cap*5+k]`).

- **Deed events** (each calls `Dissent.on_stack_event`):
  - `PlinkoOutcomes._settle`: after `note_settle`, `on_stack_event(w, "settle", stack)`.
  - `PlinkoOutcomes._raze`: after `note_raze`, `on_stack_event(w, "raze", stack)`.
  - `WorldSim._on_arrive PILGRIMAGE`: after kingdom event, `on_stack_event(w, "pilgrim", i)`.
  - `BattleBridge.finish`: winner stacks, `on_stack_event(world, "win", stack)`;
    loser stacks, `on_stack_event(world, "retreat", stack)`.

- **Tick order:** `WorldSim.step_world`, after `Settling.check_aging`, call
  `Dissent.tick(w)` once per world second.

- **RNG:** no draws from `w.rng`. Noise is deterministic, seeded from
  `w.rng.state` (or 0 if null) and unit identity, via a local hash-seeded `RandomNumberGenerator`.

### 20.2 Drives and grievance (step 2)

Heroes, captains and towns accumulate GRIEVANCE per drive axis when deeds
are unavailable and it drains when deeds are performed. Grievance raises
disaffection and erodes bond. Still a readings-only step: no outcome depends
on grievance values.

- **Fields:**
  - `Units.griev` (`PackedFloat32Array`, size units.capacity * 4, index
    `u*4+d` where d = 0 GLORY, 1 WEALTH, 2 FAITH, 3 LAND): grievance per
    drive for unit u, 0..1 clamped; 0.0 until seeded.
  - `World.town_griev` (`PackedFloat32Array`, size towns.size()): grievance
    per town, 0..1 clamped; 0.0 until seeded.
  - Save dict: `"griev"` under Units; `"town_griev"` under World. Load with
    `has` guard (slots may not exist in older saves).

- **Dissent additions (`scripts/world/dissent.gd`, all static):**
  - `const DRIVE_AXES := [0, 2, 3, 4]`: maps grievance index d (0=GLORY,
    1=WEALTH, 2=FAITH, 3=LAND) to value axis k (0=aggression, 2=greed,
    3=piety, 4=cohesion; diplomacy axis 1 has no drive).
  - `drive_strength(w, u, d) -> float`: unit u's value-axis strength for drive d
    = `w.units.vals[u*5 + DRIVE_AXES[d]]`.
  - `grievance(w, u) -> float`: unit u's overall grievance, drive-strength-weighted
    average of its four per-drive grievances. Sum of all drive strengths ≤
    0.0001 returns 0.0; else `Σ_d (strength_d * griev[u*4+d]) / Σ_d strength_d`.
  - `on_town_event(w, kind, t, amount=1.0) -> void`: applies grievance delta
    to town t. "raid" → `+TOWN_GRIEV_RAID`; "raze" → `+TOWN_GRIEV_RAZE`;
    "levy" → `+TOWN_GRIEV_LEVY * amount`; "tax" → `+TOWN_GRIEV_TAX`;
    any other → no-op. All clamped 0..1. No draws from `w.rng`.

- **Tuning constants** (appended to Tuning after `POWER_LORD`):
  ```
  GRIEV_RISE := 0.0017                # per second at drive strength 1.0 (Glory, Land, Wealth while poor)
  GRIEV_RISE_FAITH := 0.0008          # per second at drive strength 1.0
  WEALTH_COMFORT := 1.0               # stack gold per man at or above which Wealth grievance drains
  WEALTH_COMFORT_DRAIN := 0.0017
  GLORY_WIN := 0.5
  GLORY_FOUGHT := 0.15                # a lost battle still drains a little Glory
  WEALTH_RAID := 0.4
  FAITH_PILGRIM := 0.6
  FAITH_SACRILEGE := 0.5              # razing adds this * faith strength
  LAND_SETTLE := 0.3
  GRIEV_WEIGHT := 0.5                 # disaffection += GRIEV_WEIGHT * grievance
  BOND_GRIEV_DECAY := 0.003           # per second, bond -= this * grievance
  TOWN_GRIEV_RAID := 0.4
  TOWN_GRIEV_RAZE := 0.8
  TOWN_GRIEV_LEVY := 0.002            # per recruit taken from the town
  TOWN_GRIEV_TAX := 0.05              # per tax collection
  TOWN_GRIEV_CALM := 0.0005           # per second while owned and INTACT
  ```

- **Grievance rise/drain rules per drive (in `tick`, once per world second):**
  Every alive, active hero or captain u (same filter as bond service):
  - Glory (d=0): `griev[u*4+0] += GRIEV_RISE * drive_strength(u, 0)` (clamped 0..1).
  - Wealth (d=1): if stack u is in has gold per man `gpm < WEALTH_COMFORT`,
    `griev[u*4+1] += GRIEV_RISE * drive_strength(u, 1)`;
    else (comfortable) `griev[u*4+1] -= WEALTH_COMFORT_DRAIN` (clamped 0..1).
  - Faith (d=2): `griev[u*4+2] += GRIEV_RISE_FAITH * drive_strength(u, 2)` (clamped 0..1).
  - Land (d=3): `griev[u*4+3] += GRIEV_RISE * drive_strength(u, 3)` (clamped 0..1).
  - After all four per-unit grievance lines, bond is updated:
    `bond[u] = clampf(bond[u] - BOND_GRIEV_DECAY * grievance(w, u), 0, 1)`.

  Every owned town t (after the `owner < 0: continue` guard):
  - If `town_state[t] == 0` (INTACT): `town_griev[t] = max(0, town_griev[t] - TOWN_GRIEV_CALM)`.
  - Then existing realm-pull logic.

  **Note on raze timing:** a raze applies Faith spike value change (via `event_deltas`)
  *before* the `grievance` rising logic reads faith strength in that same tick;
  the spike affects the value that feeds `drive_strength`, and grievance deltas
  from the deed (see below) apply in `on_stack_event` earlier in the deed's
  timeline (M4 plinko path).

- **Deed grievance deltas (in `on_stack_event`, per hero/captain in the stack):**
  - "win": `griev[u*4+0] -= GLORY_WIN` (clamped 0..1).
  - "retreat": `griev[u*4+0] -= GLORY_FOUGHT` (clamped 0..1).
  - "raze": `griev[u*4+1] -= WEALTH_RAID`, `griev[u*4+2] += FAITH_SACRILEGE * drive_strength(u, 2)` (clamped 0..1).
  - "raid": `griev[u*4+1] -= WEALTH_RAID` (clamped 0..1).
  - "pilgrim": `griev[u*4+2] -= FAITH_PILGRIM` (clamped 0..1).
  - "settle": `griev[u*4+3] -= LAND_SETTLE` (clamped 0..1).
  - "raid" event_deltas (values on axes) stays five zeros.

- **Town calm:** an INTACT town (state==0) owned by a faction gradually calms
  each world tick via `town_griev[t] -= TOWN_GRIEV_CALM` (clamped to 0).

- **Updated disaffection formulas:**
  - `unit_disaffection(w, u) = distance(unit_vals, kingdom_vals) - BOND_WEIGHT * bond + GRIEV_WEIGHT * grievance(w, u)`
    (was: `distance(...) - BOND_WEIGHT * bond` in §20).
  - `town_disaffection(w, t) = distance(town_vals, kingdom_vals) + GRIEV_WEIGHT * town_griev[t]` if owned, else 0.0
    (was: `distance(...)` if owned, 0.0 else in §20).

- **Hook sites** (each calls `Dissent.on_stack_event` or `Dissent.on_town_event`):
  - `scripts/world/plinko_outcomes.gd::_raid`: inside `if town != -1:`, before
    `w.town_owner[town] = -1`: check `if w.town_owner[town] >= 0:`
    `Dissent.on_town_event(w, "raid", town)`. Last line of same `if` block:
    `Dissent.on_stack_event(w, "raid", stack)`.
  - `scripts/world/plinko_outcomes.gd::_raze`: inside `if town != -1:`, before
    `w.town_owner[town] = -1`: check `if w.town_owner[town] >= 0:`
    `Dissent.on_town_event(w, "raze", town)`.
  - `scripts/world/town_sim.gd::_recruit`: right after `w.town_pop[town_id] -= 1.0`:
    `Dissent.on_town_event(w, "levy", town_id)`.
  - `scripts/world/economy.gd::restock`: inside `if w.town_owner[t] == f:` (step 1),
    first line: `if w.town_gold[t] > 0.0:` `Dissent.on_town_event(w, "tax", t)`.
    After `w.town_pop[t] -= added`: `if w.town_owner[t] == f and added > 0:`
    `Dissent.on_town_event(w, "levy", t, float(added))`.
  - `scripts/world/settling.gd::found_town`: inside the `if cap >= 0:` block that
    copies vals into town_vals, add after the loop: `w.units.griev[cap * 4 + 3] = 0.0`
    (clear LAND grievance when a captain settles, as the deed is complete).

- **RNG:** no draws from `w.rng`. Noise and randomness use none; all
  grievance changes are deterministic deltas.
