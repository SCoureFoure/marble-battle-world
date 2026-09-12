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
  `hp < RETREAT_HP_FRAC * hp_max`, or (`captain_seen[f] == 1` and `faction_captain[f] == -1`).
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
