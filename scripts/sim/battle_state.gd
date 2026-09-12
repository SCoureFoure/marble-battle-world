class_name BattleState extends RefCounted

enum State { ENGAGE = 0, RETREAT = 1, DEAD = 2 }
enum Event { HIT = 0, KILL = 1, LEVEL = 2, CAPTAIN_DEAD = 3, FLED = 4 }

var n: int = 0
var cap: int
var arena: Rect2
var rng: RandomNumberGenerator
var tick: int = 0
var time: float = 0.0
var faction_count: int = 0

# per-marble floats
var px: PackedFloat32Array
var py: PackedFloat32Array
var vx: PackedFloat32Array
var vy: PackedFloat32Array
var ax: PackedFloat32Array
var ay: PackedFloat32Array
var radius: PackedFloat32Array
var mass: PackedFloat32Array
var hp: PackedFloat32Array
var hp_max: PackedFloat32Array
var spin: PackedFloat32Array
var spin_cap: PackedFloat32Array
var weapon_angle: PackedFloat32Array
var hit_cd: PackedFloat32Array
var morale: PackedFloat32Array
var aggression: PackedFloat32Array

# per-marble ints
var weapon_id: PackedInt32Array
var faction_id: PackedInt32Array
var rank: PackedInt32Array
var state: PackedInt32Array
var captain_id: PackedInt32Array
var kills: PackedInt32Array
var xp: PackedInt32Array
var target_id: PackedInt32Array
var is_captain: PackedByteArray
var fled: PackedByteArray

var events: Array = []

# per-faction
var faction_alive: PackedInt32Array
var faction_cx: PackedFloat32Array
var faction_cy: PackedFloat32Array
var faction_captain: PackedInt32Array


func _init(capacity: int, seed: int) -> void:
	cap = capacity
	n = 0
	tick = 0
	time = 0.0
	faction_count = 0

	rng = RandomNumberGenerator.new()
	rng.seed = seed

	arena = Rect2(0.0, 0.0, Tuning.ARENA_W, Tuning.ARENA_H)

	# Resize per-marble arrays to capacity
	px.resize(capacity)
	py.resize(capacity)
	vx.resize(capacity)
	vy.resize(capacity)
	ax.resize(capacity)
	ay.resize(capacity)
	radius.resize(capacity)
	mass.resize(capacity)
	hp.resize(capacity)
	hp_max.resize(capacity)
	spin.resize(capacity)
	spin_cap.resize(capacity)
	weapon_angle.resize(capacity)
	hit_cd.resize(capacity)
	morale.resize(capacity)
	aggression.resize(capacity)
	weapon_id.resize(capacity)
	faction_id.resize(capacity)
	rank.resize(capacity)
	state.resize(capacity)
	captain_id.resize(capacity)
	kills.resize(capacity)
	xp.resize(capacity)
	target_id.resize(capacity)
	is_captain.resize(capacity)
	fled.resize(capacity)

	# Fill integer arrays with -1
	captain_id.fill(-1)
	target_id.fill(-1)

	# Fill everything else with 0
	px.fill(0.0)
	py.fill(0.0)
	vx.fill(0.0)
	vy.fill(0.0)
	ax.fill(0.0)
	ay.fill(0.0)
	radius.fill(0.0)
	mass.fill(0.0)
	hp.fill(0.0)
	hp_max.fill(0.0)
	spin.fill(0.0)
	spin_cap.fill(0.0)
	weapon_angle.fill(0.0)
	hit_cd.fill(0.0)
	morale.fill(0.0)
	aggression.fill(0.0)
	weapon_id.fill(0)
	faction_id.fill(0)
	rank.fill(0)
	state.fill(0)
	kills.fill(0)
	xp.fill(0)
	is_captain.fill(0)
	fled.fill(0)
	events = []

	# Resize faction arrays to MAX_FACTIONS
	faction_alive.resize(Tuning.MAX_FACTIONS)
	faction_cx.resize(Tuning.MAX_FACTIONS)
	faction_cy.resize(Tuning.MAX_FACTIONS)
	faction_captain.resize(Tuning.MAX_FACTIONS)

	# Fill faction arrays
	faction_alive.fill(0)
	faction_cx.fill(0.0)
	faction_cy.fill(0.0)
	faction_captain.fill(-1)


func spawn(x: float, y: float, faction: int, rank_: int, weapon: int, captain: bool) -> int:
	# Error checks
	if n >= cap:
		push_error("BattleState.spawn: capacity exceeded")
		return -1

	if faction < 0 or faction >= Tuning.MAX_FACTIONS:
		push_error("BattleState.spawn: faction out of range")
		return -1

	if rank_ < 0 or rank_ > 3:
		push_error("BattleState.spawn: rank out of range")
		return -1

	if weapon < 0 or weapon >= Tuning.WEAPON_COUNT:
		push_error("BattleState.spawn: weapon out of range")
		return -1

	var idx := n

	# Set position
	px[idx] = x
	py[idx] = y

	# Set faction and other basic properties
	faction_id[idx] = faction
	weapon_id[idx] = weapon
	rank[idx] = rank_

	# Calculate radius with multipliers
	var base_radius: float = Tuning.BASE_RADIUS * Tuning.RADIUS_RANK_MULT[rank_]
	if captain:
		base_radius *= Tuning.CAPTAIN_RADIUS_MULT
	radius[idx] = base_radius

	# Calculate mass
	mass[idx] = radius[idx] * radius[idx] * Tuning.RANK_MULT[rank_]

	# Set HP
	hp_max[idx] = Tuning.HP_BASE * Tuning.RANK_MULT[rank_]
	hp[idx] = hp_max[idx]

	# Set spin
	spin[idx] = Tuning.SPIN_START
	spin_cap[idx] = Tuning.SPIN_CAP[rank_]

	# Set weapon angle
	weapon_angle[idx] = rng.randf() * TAU

	# Set morale and aggression
	morale[idx] = Tuning.MORALE_START
	aggression[idx] = 1.0

	# Set state
	state[idx] = State.ENGAGE

	# Set target and captain info
	target_id[idx] = -1
	captain_id[idx] = -1
	hit_cd[idx] = 0.0

	# Initialize combat stats
	kills[idx] = 0
	xp[idx] = 0

	# Initialize velocity and acceleration
	vx[idx] = 0.0
	vy[idx] = 0.0
	ax[idx] = 0.0
	ay[idx] = 0.0

	# Set captain flag
	if captain:
		is_captain[idx] = 1
		faction_captain[faction] = idx
	else:
		is_captain[idx] = 0

	# Initialize fled
	fled[idx] = 0

	# Update faction tracking
	faction_alive[faction] += 1
	faction_count = max(faction_count, faction + 1)

	# Increment marble count and return index
	n += 1
	return idx


func alive_count() -> int:
	var count := 0
	for i in range(n):
		if state[i] != State.DEAD:
			count += 1
	return count


func survivors_count(faction: int) -> int:
	var count := 0
	for i in range(n):
		if faction_id[i] == faction and (state[i] != State.DEAD or fled[i] == 1):
			count += 1
	return count


func spawn_block(faction: int, count: int, rect: Rect2, weapon: int) -> void:
	for _i in range(count):
		var x := rect.position.x + rng.randf() * rect.size.x
		var y := rect.position.y + rng.randf() * rect.size.y
		var w := weapon
		if weapon == -1:
			w = rng.randi_range(0, Tuning.WEAPON_COUNT - 1)
		var result := spawn(x, y, faction, 0, w, false)
		if result == -1:
			break
