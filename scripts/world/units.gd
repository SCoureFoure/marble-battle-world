class_name Units extends RefCounted
## Every soldier in the world, persistent. SoA per docs/ARCHITECTURE.md §11.3.

var n: int = 0
var cap: int
var faction: PackedInt32Array
var rank: PackedInt32Array
var xp: PackedInt32Array
var kills: PackedInt32Array
var weapon: PackedInt32Array
var stack: PackedInt32Array
var hp_frac: PackedFloat32Array
var alive: PackedByteArray
var is_captain: PackedByteArray
var drill: PackedByteArray          # 0..3, DRILL outcome level (M4)
var names: Dictionary = {}


func _init(capacity: int) -> void:
	cap = capacity
	n = 0

	faction.resize(capacity)
	rank.resize(capacity)
	xp.resize(capacity)
	kills.resize(capacity)
	weapon.resize(capacity)
	stack.resize(capacity)
	hp_frac.resize(capacity)
	alive.resize(capacity)
	is_captain.resize(capacity)
	drill.resize(capacity)

	faction.fill(0)
	rank.fill(0)
	xp.fill(0)
	kills.fill(0)
	weapon.fill(0)
	stack.fill(-1)
	hp_frac.fill(0.0)
	alive.fill(0)
	is_captain.fill(0)
	drill.fill(0)

	names = {}


func add(faction_: int, rank_: int, weapon_: int, captain: bool, stack_: int) -> int:
	if n >= cap:
		push_error("Units.add: capacity exceeded")
		return -1

	var idx := n
	faction[idx] = faction_
	rank[idx] = rank_
	weapon[idx] = weapon_
	stack[idx] = stack_
	is_captain[idx] = 1 if captain else 0
	hp_frac[idx] = 1.0
	alive[idx] = 1
	xp[idx] = 0
	kills[idx] = 0
	drill[idx] = 0

	n += 1
	return idx


func kill(id: int) -> void:
	alive[id] = 0
	stack[id] = -1
