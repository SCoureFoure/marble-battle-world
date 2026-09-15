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
var looks: Dictionary = {}          # unit id -> CharLooks look Dictionary (captains/heroes), kept until the slot is recycled
var hero: PackedByteArray           # 0 (M9)
var career_start: PackedFloat32Array # 0.0, world time unit became hero or captain (M9)
var ambition: PackedFloat32Array     # 0.0 (M9)
var mentor: PackedInt32Array         # -1, captain of stack hero broke away from (M9)
var fate: PackedByteArray            # ACTIVE, see Fate enum (M9)
var leader: PackedInt32Array         # -1 = the stack's own men; else the unit id of the hero whose contingent this unit belongs to (§19)
var pledge_t: PackedFloat32Array     # 0.0; world time before which a hero who rallied into a stack will not break away (§19)
var gen: PackedInt32Array            # 0; bumped each time this slot is recycled for a new unit (render/UI use it to spot a new occupant)
var reusable: PackedByteArray        # 0; 1 = dead and unreferenced, set by SlotSweep; consumed by add() once n == cap
var vals: PackedFloat32Array        # cap*5, index u*5+k, same axes as World.ktraits; 0.0 until Dissent.seed_unit (§20)
var bond: PackedFloat32Array        # 0.0; loyalty to own kingdom 0..1 (§20)


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
	gen.resize(capacity)
	reusable.resize(capacity)
	vals.resize(capacity * 5)
	bond.resize(capacity)

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
	gen.fill(0)
	reusable.fill(0)
	vals.fill(0.0)
	bond.fill(0.0)

	names = {}
	looks = {}
	dynasty = {}


func add(faction_: int, rank_: int, weapon_: int, captain: bool, stack_: int) -> int:
	var idx := n
	if n >= cap:
		idx = -1
		for i in range(cap):
			if reusable[i] == 1:
				idx = i
				break
		if idx == -1:
			push_error("Units.add: capacity exceeded")
			return -1
		reusable[idx] = 0
		gen[idx] += 1
		ctrait[idx] = -1
		c_fights[idx] = 0
		c_retreats[idx] = 0
		c_razes[idx] = 0
		c_settles[idx] = 0
		names.erase(idx)
		looks.erase(idx)
		dynasty.erase(idx)

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
	for k in range(5):
		vals[idx*5 + k] = 0.0
	bond[idx] = 0.0

	if idx == n: n += 1
	return idx


## True when add() would succeed: space below cap, or a slot SlotSweep marked reusable.
func has_room() -> bool:
	return n < cap or reusable.find(1) != -1


func kill(id: int) -> void:
	alive[id] = 0
	stack[id] = -1
