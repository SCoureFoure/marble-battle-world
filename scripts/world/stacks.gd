class_name Stacks extends RefCounted
## Marching unit stacks on the overworld. SoA per docs/ARCHITECTURE.md §11.3.

enum State { IDLE = 0, MOVING = 1, BATTLE = 2, RETREATING = 3 }
enum Goal { HUNT_WEAK = 0, EXPAND = 1, RAID = 2, DEFEND = 3, IDLE_HEAL = 4, PILGRIMAGE = 5, AVENGE = 6, RESTOCK = 7, FOUND = 8, RALLY = 9 }

var n: int = 0
var cap: int
var x: PackedFloat32Array
var y: PackedFloat32Array
var prev_x: PackedFloat32Array
var prev_y: PackedFloat32Array
var faction: PackedInt32Array
var count: PackedInt32Array
var state: PackedInt32Array
var goal: PackedInt32Array
var battle_id: PackedInt32Array
var captain_unit: PackedInt32Array
var goal_tx: PackedInt32Array
var goal_ty: PackedInt32Array
var ai_timer: PackedFloat32Array
var immunity: PackedFloat32Array
var idle_timer: PackedFloat32Array
var path: Array = []                # per stack: PackedVector2Array
var path_i: PackedInt32Array
var names: Array = []               # per stack: String
var alive: PackedByteArray
var gold: PackedFloat32Array         # 0.0 (M9)
var rally_target: PackedInt32Array   # -1; host stack a RALLY march is heading to (§19)
var rally_cd: PackedFloat32Array     # 0.0; seconds before a refused stack may rally again (§19)
var gen: PackedInt32Array            # 0; bumped each time this slot is recycled for a new stack (render/UI use it to spot a new occupant)
var reusable: PackedByteArray        # 0; 1 = dead and unreferenced, set by SlotSweep; consumed by add() once n == cap


func _init(capacity: int) -> void:
	cap = capacity
	n = 0

	x.resize(capacity)
	y.resize(capacity)
	prev_x.resize(capacity)
	prev_y.resize(capacity)
	faction.resize(capacity)
	count.resize(capacity)
	state.resize(capacity)
	goal.resize(capacity)
	battle_id.resize(capacity)
	captain_unit.resize(capacity)
	goal_tx.resize(capacity)
	goal_ty.resize(capacity)
	ai_timer.resize(capacity)
	immunity.resize(capacity)
	idle_timer.resize(capacity)
	path_i.resize(capacity)
	alive.resize(capacity)
	gold.resize(capacity)
	rally_target.resize(capacity)
	rally_cd.resize(capacity)
	gen.resize(capacity)
	reusable.resize(capacity)

	x.fill(0.0)
	y.fill(0.0)
	prev_x.fill(0.0)
	prev_y.fill(0.0)
	faction.fill(0)
	count.fill(0)
	state.fill(State.IDLE)
	goal.fill(Goal.IDLE_HEAL)
	battle_id.fill(-1)
	captain_unit.fill(-1)
	goal_tx.fill(0)
	goal_ty.fill(0)
	ai_timer.fill(0.0)
	immunity.fill(0.0)
	idle_timer.fill(0.0)
	path_i.fill(0)
	alive.fill(0)
	gold.fill(0.0)
	rally_target.fill(-1)
	rally_cd.fill(0.0)
	gen.fill(0)
	reusable.fill(0)

	path = []
	names = []


func add(faction_: int, x_: float, y_: float, name_: String) -> int:
	var idx := n
	if n >= cap:
		idx = -1
		for i in range(cap):
			if reusable[i] == 1:
				idx = i
				break
		if idx == -1:
			push_error("Stacks.add: capacity exceeded")
			return -1
		reusable[idx] = 0
		gen[idx] += 1

	faction[idx] = faction_
	x[idx] = x_
	y[idx] = y_
	prev_x[idx] = x_
	prev_y[idx] = y_
	state[idx] = State.IDLE
	goal[idx] = Goal.IDLE_HEAL
	battle_id[idx] = -1
	captain_unit[idx] = -1
	count[idx] = 0
	goal_tx[idx] = 0
	goal_ty[idx] = 0
	ai_timer[idx] = 0.0
	immunity[idx] = 0.0
	idle_timer[idx] = 0.0
	gold[idx] = 0.0
	rally_target[idx] = -1
	rally_cd[idx] = 0.0
	if idx == n:
		path.append(PackedVector2Array())
		names.append(name_)
	else:
		path[idx] = PackedVector2Array()
		names[idx] = name_
	path_i[idx] = 0
	alive[idx] = 1

	if idx == n: n += 1
	return idx


## True when add() would succeed: space below cap, or a slot SlotSweep marked reusable.
func has_room() -> bool:
	return n < cap or reusable.find(1) != -1


func tier(i: int) -> int:
	var c := count[i]
	var t := 0
	for threshold in Tuning.TIER_COUNTS:
		if c >= threshold:
			t += 1
		else:
			break
	return t


func label(i: int) -> String:
	return "(%s)%s %d/%d" % [Tuning.TIER_NAMES[tier(i)], names[i], count[i], Tuning.STACK_CAP]


func recount(units: Units) -> void:
	for i in range(n):
		count[i] = 0
	for u in range(units.n):
		if units.alive[u] == 1 and units.stack[u] >= 0:
			count[units.stack[u]] += 1
