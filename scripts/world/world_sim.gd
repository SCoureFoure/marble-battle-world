class_name WorldSim extends RefCounted
## Overworld tick: AI, movement, collisions, reinforcements, battles.
## Source: docs/ARCHITECTURE.md §11.6.

static func step_world(w: World, dt: float) -> void:
	w.time += dt
	var st := w.stacks

	for i in range(st.n):
		if st.alive[i] == 0:
			continue
		if st.ai_timer[i] > 0.0:
			st.ai_timer[i] -= dt
		if st.immunity[i] > 0.0:
			st.immunity[i] -= dt
		if st.idle_timer[i] > 0.0:
			st.idle_timer[i] -= dt

	for i in range(st.n):
		if st.alive[i] == 0:
			continue
		if st.state[i] == Stacks.State.IDLE and st.idle_timer[i] <= 0.0 and st.ai_timer[i] <= 0.0:
			pick_goal(w, i)

	move_stacks(w, dt)
	check_collisions(w)
	reinforce(w)

	for i in range(st.n):
		if st.alive[i] == 1 and st.count[i] == 0 and st.state[i] != Stacks.State.BATTLE:
			st.alive[i] = 0


static func step(w: World, dt: float) -> void:
	step_world(w, dt)
	step_battles(w)


static func pick_goal(w: World, i: int) -> void:
	var st := w.stacks
	var total := 0.0
	for wgt in Tuning.GOAL_WEIGHTS:
		total += wgt
	var draw: float = w.rng.randf() * total
	var acc := 0.0
	var goal := 0
	for g in range(Tuning.GOAL_WEIGHTS.size()):
		acc += Tuning.GOAL_WEIGHTS[g]
		if draw < acc:
			goal = g
			break

	if not set_goal(w, i, goal):
		# UNDECIDED: whether a failed set_goal should still write st.goal[i] = goal
		# (the goal actually drawn) before falling back — the fiat text only says
		# "falls back to IDLE_HEAL for this tick", so IDLE_HEAL is written here.
		st.goal[i] = Stacks.Goal.IDLE_HEAL
		st.state[i] = Stacks.State.IDLE
	st.ai_timer[i] = Tuning.AI_TICK


# Applies one named goal to stack `i`. Returns false (no change besides the
# attempt) when the goal has no reachable target.
static func set_goal(w: World, i: int, goal: int) -> bool:
	var st := w.stacks
	var fi := st.faction[i]
	var target_tile := Vector2i(-1, -1)

	match goal:
		Stacks.Goal.HUNT_WEAK:
			var j := w.nearest_enemy_stack(i, true)
			if j == -1:
				j = w.nearest_enemy_stack(i, false)
			if j == -1:
				return false
			target_tile = w.stack_tile(j)
		Stacks.Goal.EXPAND:
			var town_e := w.nearest_town(st.x[i], st.y[i], fi, 2)
			if town_e == -1:
				return false
			target_tile = Vector2i(int(w.towns[town_e].x), int(w.towns[town_e].y))
		Stacks.Goal.RAID:
			var town_r := w.nearest_town(st.x[i], st.y[i], fi, 1)
			if town_r == -1:
				return false
			target_tile = Vector2i(int(w.towns[town_r].x), int(w.towns[town_r].y))
		Stacks.Goal.DEFEND:
			var town_d := w.nearest_town(st.x[i], st.y[i], fi, 0)
			if town_d == -1:
				return false
			target_tile = Vector2i(int(w.towns[town_d].x), int(w.towns[town_d].y))
		Stacks.Goal.IDLE_HEAL:
			return false
		_:
			return false

	var from_tile := w.stack_tile(i)
	var p := w.pathing.find(from_tile, target_tile)
	if p.size() == 0:
		return false

	st.goal[i] = goal
	st.goal_tx[i] = target_tile.x
	st.goal_ty[i] = target_tile.y
	st.path[i] = p
	st.path_i[i] = 0
	st.state[i] = Stacks.State.MOVING
	return true


static func move_stacks(w: World, dt: float) -> void:
	var st := w.stacks
	var map := w.map
	for i in range(st.n):
		if st.alive[i] == 0:
			continue
		if st.state[i] != Stacks.State.MOVING and st.state[i] != Stacks.State.RETREATING:
			continue

		st.prev_x[i] = st.x[i]
		st.prev_y[i] = st.y[i]

		var p: PackedVector2Array = st.path[i]
		if st.path_i[i] >= p.size():
			st.state[i] = Stacks.State.IDLE
			continue

		var target: Vector2 = p[st.path_i[i]]
		var tile := map.tile_of(st.x[i], st.y[i])
		var cost: float = map.cost_at(tile.x, tile.y)
		if cost <= 0.0:
			cost = 1.0
		var speed: float = Tuning.STACK_SPEED / cost
		if st.state[i] == Stacks.State.RETREATING:
			speed *= Tuning.RETREAT_SPEED_MULT

		var to_target := target - Vector2(st.x[i], st.y[i])
		var dist := to_target.length()
		if dist < 2.0:
			st.x[i] = target.x
			st.y[i] = target.y
			st.path_i[i] += 1
			if st.path_i[i] >= p.size():
				st.state[i] = Stacks.State.IDLE
		else:
			var dir := to_target / dist
			st.x[i] += dir.x * speed * dt
			st.y[i] += dir.y * speed * dt


static func check_collisions(w: World) -> void:
	var st := w.stacks

	var hash := SpatialHash.new()
	hash.setup(Rect2(0.0, 0.0, w.map.cols * Tuning.TILE, w.map.rows * Tuning.TILE), 64.0)

	var hstate := PackedInt32Array()
	hstate.resize(st.n)
	for i in range(st.n):
		hstate[i] = 0 if (st.alive[i] == 1 and st.state[i] != Stacks.State.BATTLE) else 2
	hash.build(st.x, st.y, hstate, st.n)

	var started_tiles := {}
	var min_dist: float = 2.0 * Tuning.STACK_RADIUS

	for i in range(st.n):
		if hstate[i] != 0:
			continue
		var k := hash.gather(st.x[i], st.y[i])
		for idx in range(k):
			var j: int = hash.scratch[idx]
			if j <= i:
				continue
			if hstate[j] != 0:
				continue
			if st.faction[i] == st.faction[j]:
				continue
			if st.immunity[i] > 0.0 or st.immunity[j] > 0.0:
				continue

			var dx: float = st.x[i] - st.x[j]
			var dy: float = st.y[i] - st.y[j]
			if dx * dx + dy * dy >= min_dist * min_dist:
				continue

			var tile_i := w.stack_tile(i)
			var tile_j := w.stack_tile(j)
			var existing: BattleInstance = _live_battle_at(w, tile_i)
			if existing == null:
				existing = _live_battle_at(w, tile_j)

			if existing != null:
				if st.state[i] != Stacks.State.BATTLE:
					BattleBridge.join(existing, w, i)
				if st.state[j] != Stacks.State.BATTLE:
					BattleBridge.join(existing, w, j)
			else:
				var key := "%d_%d" % [tile_i.x, tile_i.y]
				if started_tiles.has(key):
					continue
				var inst := BattleBridge.start(w, i, j)
				if inst != null:
					if not w.battles.has(inst):
						w.battles.append(inst)
					started_tiles[key] = true


static func reinforce(w: World) -> void:
	var st := w.stacks

	for battle in w.battles:
		var inst: BattleInstance = battle
		var involved := {}
		for lf in range(inst.faction_map.size()):
			involved[inst.faction_map[lf]] = true

		for i in range(st.n):
			if st.alive[i] == 0:
				continue
			if not involved.has(st.faction[i]):
				continue
			if st.state[i] != Stacks.State.IDLE and st.state[i] != Stacks.State.MOVING:
				continue

			var tile := w.stack_tile(i)
			var cheb: int = max(abs(tile.x - inst.tile.x), abs(tile.y - inst.tile.y))
			if cheb > Tuning.REINFORCE_TILES:
				continue
			if w.reinforce.get(i, -1) == inst.id:
				continue

			var p := w.pathing.find(tile, inst.tile)
			if p.size() == 0:
				continue

			st.goal_tx[i] = inst.tile.x
			st.goal_ty[i] = inst.tile.y
			st.path[i] = p
			st.path_i[i] = 0
			st.state[i] = Stacks.State.MOVING
			w.reinforce[i] = inst.id

	# Arrival: a MOVING stack whose tile equals a live battle tile joins it
	# (or, on refusal, sits out IDLE with retreat immunity).
	for i in range(st.n):
		if st.alive[i] == 0 or st.state[i] != Stacks.State.MOVING:
			continue
		var tile2 := w.stack_tile(i)
		for battle2 in w.battles:
			var inst2: BattleInstance = battle2
			if inst2.tile != tile2:
				continue
			var joined := BattleBridge.join(inst2, w, i)
			if not joined:
				st.state[i] = Stacks.State.IDLE
				st.immunity[i] = Tuning.RETREAT_IMMUNITY
			break


static func step_battles(w: World) -> void:
	var remaining: Array = []
	for battle in w.battles:
		var inst: BattleInstance = battle
		inst.sim.step(inst.state, Tuning.DT)
		var win := inst.sim.winner(inst.state)
		if win != -1:
			BattleBridge.finish(inst, w)
		else:
			remaining.append(inst)
	w.battles = remaining


static func _live_battle_at(w: World, tile: Vector2i) -> BattleInstance:
	for battle in w.battles:
		var inst: BattleInstance = battle
		if inst.tile == tile:
			return inst
	return null
