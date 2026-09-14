class_name Units extends RefCounted
## Every soldier in the world, persistent. SoA per docs/ARCHITECTURE.md §11.3.

enum Fate { ACTIVE = 0, LORD = 1, RETIRED = 2 }

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
var ctrait: PackedInt32Array         # -1 none; Lineage.Trait { CHARGER=0, CAUTIOUS=1, TYRANT=2, BUILDER=3 } (M5)
var c_fights: PackedInt32Array      # behaviour counters, captains only (M5)
var c_retreats: PackedInt32Array
var c_razes: PackedInt32Array
var c_settles: PackedInt32Array
var dynasty: Dictionary = {}        # unit id -> [name: String, numeral: int] (M5)
var names: Dictionary = {}
var hero: PackedByteArray           # 0 (M9)
var career_start: PackedFloat32Array # 0.0, world time unit became hero or captain (M9)
var ambition: PackedFloat32Array     # 0.0 (M9)
var mentor: PackedInt32Array         # -1, captain of stack hero broke away from (M9)
var fate: PackedByteArray            # ACTIVE, see Fate enum (M9)
var leader: PackedInt32Array         # -1 = the stack's own men; else the unit id of the hero whose contingent this unit belongs to (§19)
var pledge_t: PackedFloat32Array     # 0.0; world time before which a hero who rallied into a stack will not break away (§19)


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
	ctrait.resize(capacity)
	c_fights.resize(capacity)
	c_retreats.resize(capacity)
	c_razes.resize(capacity)
	c_settles.resize(capacity)
	hero.resize(capacity)
	career_start.resize(capacity)
	ambition.resize(capacity)
	mentor.resize(capacity)
	fate.resize(capacity)
	leader.resize(capacity)
	pledge_t.resize(capacity)

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
	ctrait.fill(-1)
	c_fights.fill(0)
	c_retreats.fill(0)
	c_razes.fill(0)
	c_settles.fill(0)
	hero.fill(0)
	career_start.fill(0.0)
	ambition.fill(0.0)
	mentor.fill(-1)
	fate.fill(Fate.ACTIVE)
	leader.fill(-1)
	pledge_t.fill(0.0)

	names = {}
	dynasty = {}


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
	hero[idx] = 0
	career_start[idx] = 0.0
	ambition[idx] = 0.0
	mentor[idx] = -1
	fate[idx] = Fate.ACTIVE
	leader[idx] = -1
	pledge_t[idx] = 0.0

	n += 1
	return idx


func kill(id: int) -> void:
	alive[id] = 0
	stack[id] = -1
