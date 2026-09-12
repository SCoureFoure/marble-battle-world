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
