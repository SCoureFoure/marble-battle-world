class_name SlotSweep extends RefCounted
## Marks dead Units/Stacks slots that nothing references as reusable, so add() can recycle them once a store is full.
## A slot is referenced while any of these still name it:
##   units  - captain_unit of an alive stack, leader/mentor of an alive unit, any town_lord, an active battle (unit_of, slayers, captain_before)
##   stacks - stack of an alive unit, rally_target of an alive stack, a reinforce key, an active battle (stack_ids)

const UNIT_MARGIN := 256
const STACK_MARGIN := 16


static func maybe_sweep(w: World, dt: float) -> void:
	if int(floor(w.time)) == int(floor(w.time - dt)):
		return
	var near_units: bool = w.units.n >= w.units.cap - UNIT_MARGIN
	var near_stacks: bool = w.stacks.n >= w.stacks.cap - STACK_MARGIN
	if near_units or near_stacks:
		sweep(w)


static func sweep(w: World) -> void:
	var uref := PackedByteArray()
	uref.resize(w.units.cap)
	uref.fill(0)
	var sref := PackedByteArray()
	sref.resize(w.stacks.cap)
	sref.fill(0)

	# Stacks loop: mark referenced units and stacks
	for i in range(w.stacks.n):
		if w.stacks.alive[i] == 1:
			var c: int = w.stacks.captain_unit[i]
			if c >= 0 and c < w.units.cap:
				uref[c] = 1
			var rt: int = w.stacks.rally_target[i]
			if rt >= 0 and rt < w.stacks.cap:
				sref[rt] = 1

	# Units loop: mark referenced stacks and units
	for u in range(w.units.n):
		if w.units.alive[u] == 1:
			var st: int = w.units.stack[u]
			if st >= 0 and st < w.stacks.cap:
				sref[st] = 1
			var ld: int = w.units.leader[u]
			if ld >= 0 and ld < w.units.cap:
				uref[ld] = 1
			var mt: int = w.units.mentor[u]
			if mt >= 0 and mt < w.units.cap:
				uref[mt] = 1

	# Town lords: mark referenced units
	for t in range(w.town_lord.size()):
		var lord: int = w.town_lord[t]
		if lord >= 0 and lord < w.units.cap:
			uref[lord] = 1

	# Reinforce: mark referenced stacks
	for key in w.reinforce.keys():
		var rk: int = int(key)
		if rk >= 0 and rk < w.stacks.cap:
			sref[rk] = 1

	# Battles: mark referenced units and stacks
	for b in w.battles:
		var inst: BattleInstance = b
		for stack_id in inst.stack_ids:
			if stack_id >= 0 and stack_id < w.stacks.cap:
				sref[stack_id] = 1
		for unit_id in inst.unit_of:
			if unit_id >= 0 and unit_id < w.units.cap:
				uref[unit_id] = 1
		for slayer_id in inst.slayers:
			if slayer_id >= 0 and slayer_id < w.units.cap:
				uref[slayer_id] = 1
		for captain_id in inst.captain_before:
			if captain_id >= 0 and captain_id < w.units.cap:
				uref[captain_id] = 1

	# Write marks: 1 if dead and unreferenced, 0 otherwise
	for u2 in range(w.units.n):
		w.units.reusable[u2] = 1 if (w.units.alive[u2] == 0 and uref[u2] == 0) else 0
	for s2 in range(w.stacks.n):
		w.stacks.reusable[s2] = 1 if (w.stacks.alive[s2] == 0 and sref[s2] == 0) else 0
